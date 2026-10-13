-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- ful-1a — Shopify 연동 ⑤ 오더 상태 · DB 첫 차수 (2026-10-13 · 판정 436 ~ 452 · ful-0 보고 · 정본 docs/design/shopify-integration.md §4 · so-module §61 · ord-1b2 20261011020000 위에)
--   ① 표 ref_carrier(판정 436 · 450 — 운송사는 작은 표에서 · 우리 이름 · Shopify 이름 · 종류 carrier | pickup | delivery · 켜기 · 끄기 · 시작값 일곱 · 지우지 않는다)
--      ⚠️ asung-po §2 예외 둘(주석) — 「종류 칸」(판정 436 자체 · 관계로 못 쓴다) · 행 적재(ref_embed_host 선례) · sort_order 없음 · cin7_id · source 없음(Cin7 원천이 없다)
--   ② so.carrier_id(FK · 글자 so.carrier 는 그대로 — 그 순간의 이름 · 옛 오더) · customer.default_carrier_id(판정 451 — 글자 default_carrier 는 「Cin7 원문」 그대로 남는다 · 표에 없으면 id 만 비움)
--      옛 글자 → id 잇기는 이름이 정확히 같을 때만(대소문자 · 앞뒤 공백 무시 · 하나만 맞을 때) · 이관은 touch 트리거를 잠시 끄고(updated_by 를 안 덮는다)
--   ③ so_copy_customer 재발행(마지막 정의 20260924200029:93 · 두 줄 — carrier_id 복사 · 글자는 표 이름 또는 옛 글자)
--   ④ 표 shop_fulfillment(SO × Shopify 오더 — 보낼 발송 · Shopify 가 돌려주는 GID · 판정 443 ready_at · picked_up_at · 447 메아리 거르기) · shop_fulfillment_line(줄 짝 · 수량) · shop_fulfill_queue(SO × 종류 · unique — 한 SO 는 한 번만 출고)
--   ⑤ 함수 shop_tracking_split(판정 437 쉼표 · 줄바꿈) · shop_fulfill_trace(줄 계보 — split_from_line_id · so_line_merge_source 를 shop_order_line 까지 · 합친 줄은 출처 순으로 채움 · 이견 2) · shop_fulfill_lineage(SO → Shopify 오더 · 줄 · 출고 수량 · 콤보는 콤보 줄)
--      shop_fulfill_web_orders(계보가 닿는 Shopify 오더 — so_finalize 의 「필수」 · PICK_UP 검사) · shop_fulfill_enqueue(출고 방아쇠 — shipped_at 이 있을 때만 · 계보 0 이면 안 넣음 · 멱등)
--   ⑥ so_ship 재발행(마지막 정의 20261005201634:222 · 석 줄 — 끝에 shop_fulfill_enqueue · 이견 1: shipped_at(①) · qty_shipped(③) · 형제 split(④) 뒤라야 수량이 맞다)
--   ⑦ so_finalize 재발행(마지막 정의 20261007171939:163 · ① 검사에 운송사 · 송장 — 판정 452: 표에서만(id 또는 글자) · Shopify 계보면 필수 · carrier 면 송장 필수(모든 SO) · pickup · delivery 면 송장 없음 · PICK_UP 오더에 carrier 는 막음(미룬) · ② 에서 쓴다)
--   ⭐ 표 셋은 authenticated select 만 · 쓰기는 definer 창구(so_ship 안) 와 EF(service_role · ful-2) · 함수는 전부 service_role 몫(authenticated revoke) · ref_carrier 쓰기는 다른 ref_ 표와 같이 ims_can_write('master')
--   ⚠️ 이 차수에 없는 것: 송장 고치기 창구(438) · 픽업 Ready · Picked up(443) · 경고(439 · 441 · 447) · 환불 원문(440) · EF · 화면 · cron — ful-1b 이후
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


-- ═══ 1) ref_carrier — 운송사 표(판정 436 · 450) ═══
create table public.ref_carrier (
  id                     uuid primary key default gen_random_uuid(),
  name                   text not null,                                                   -- 우리 이름(화면 · so.carrier 글자에 그대로)
  kind                   text not null,                                                   -- carrier(택배 · 화물 — 송장 · 손님 메일) · pickup(손님이 찾아감) · delivery(우리 차량) — 둘은 송장 없음 · 메일 없음
  shopify_company        text,                                                            -- Shopify 운송사 목록의 이름 그대로(대소문자) · kind carrier 만 · 목록에 없으면 null(글자만 실리고 링크 없음)
  tracking_url_template  text,                                                            -- 송장 링크 틀({number}) · Shopify 목록에 없는 운송사를 위해 · 지금은 전부 null
  is_active              boolean not null default true,                                   -- 끄기 = 고르기 목록에서만 빠진다(옛 오더의 이름 · id 는 그대로)
  note                   text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  updated_by             uuid references public.ims_staff (id) on delete no action,
  constraint ref_carrier_name_uk          unique (name),
  constraint ref_carrier_name_ck          check (name <> '' and name = btrim(name)),
  constraint ref_carrier_kind_ck          check (kind in ('carrier', 'pickup', 'delivery')),
  constraint ref_carrier_kind_fields_ck   check (kind = 'carrier' or (shopify_company is null and tracking_url_template is null)),
  constraint ref_carrier_company_ck       check (shopify_company is null or (shopify_company <> '' and shopify_company = btrim(shopify_company)))
);
create index ref_carrier_updated_by_idx on public.ref_carrier (updated_by);
create trigger ref_carrier_touch before update on public.ref_carrier for each row execute function public.ims_touch();
alter table public.ref_carrier enable row level security;
create policy ref_carrier_select on public.ref_carrier for select to authenticated using (true);
create policy ref_carrier_insert on public.ref_carrier for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_carrier_update on public.ref_carrier for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
revoke all on public.ref_carrier from anon;
revoke delete, truncate on public.ref_carrier from authenticated;                        -- 마스터는 is_active 로(판정 450 지우지 않는다)
comment on table public.ref_carrier is 'ful-1a 판정 436 · 450: 운송사 표 — Ship & invoice 의 Carrier 는 여기서 고른다(자유 글자 금지) · kind 가 손님 메일을 정한다(carrier = Shopify 발송 메일 · pickup · delivery = 메일 없음 · 송장 없음) · shopify_company 는 Shopify 운송사 목록의 이름 그대로 · 더하기 · 이름 고치기 · 끄기(is_active) 만 — 지우지 않는다(옛 오더가 가리킨다) · ⚠️ asung-po §2 예외: kind(「종류 칸」)는 판정 436 자체라 관계로 못 쓴다 · 시작값 일곱(판정 450) · sort_order 없음 · Cin7 원천 없음(cin7_id · source 없음 · ref_embed_host 선례) · 쓰기 = ims_can_write(master) · 화면은 ful-3(Settings)';
comment on column public.ref_carrier.kind is 'carrier | pickup | delivery — carrier 만 송장 · Shopify 이름 · 손님 메일 · pickup · delivery 는 송장 없음 · 메일 없음(so_finalize 가 송장을 비운다 · shop_fulfillment.notify_customer false)';
comment on column public.ref_carrier.shopify_company is 'Shopify 운송사 목록의 이름 그대로(대소문자 · https://shopify.dev/docs/api/admin-graphql/2026-10/objects/FulfillmentTrackingInfo) · 목록에 없으면 null → EF 가 글자만 싣고 url 을 같이 보낸다 · ⚠️ Purolator · UPS 는 목록에 있는지 못 봤다(so-module 미룬 202 · ful-4 에서 확인)';
insert into public.ref_carrier (name, kind, shopify_company, note) values
  ('Pickup',      'pickup',   null,          '판정 450 · 손님이 찾아감 · Toronto · Edmonton 으로 나누지 않는다(창고는 SO 에)'),
  ('Delivery',    'delivery', null,          '판정 450 · 우리 차량'),
  ('Canada Post', 'carrier',  'Canada Post', '판정 450 · Shopify 목록에서 봤다(ful-0)'),
  ('Purolator',   'carrier',  'Purolator',   '판정 450 · Shopify 목록에 있는지 못 봤다 — ful-4 ① 에서 확인(미룬 202)'),
  ('UPS',         'carrier',  'UPS',         '판정 450 · Shopify 목록에 있는지 못 봤다 — ful-4 ① 에서 확인(미룬 202)'),
  ('Canpar',      'carrier',  'Canpar',      '판정 450 · Shopify 목록에서 봤다(ful-0)'),
  ('FedEx',       'carrier',  'FedEx',       '판정 450 · Shopify 목록에서 봤다(ful-0)');

-- ═══ 2) so.carrier_id · customer.default_carrier_id — 글자 칸은 그대로(판정 436 · 451) · 옛 글자 잇기는 정확히 같을 때만 ═══
alter table public.so add column carrier_id uuid references public.ref_carrier (id) on delete no action;
create index so_carrier_id_idx on public.so (carrier_id);
comment on column public.so.carrier_id is 'ful-1a 판정 436: 운송사(ref_carrier) · so_finalize(Ship & invoice)가 표에서 고른 것을 쓴다(글자 so.carrier 는 그 순간의 표 이름) · 새 오더는 so_copy_customer 가 손님 기본(default_carrier_id)을 복사 · null = 아직 안 고름(계보가 Shopify 에 닿는 오더는 Ship & invoice 가 요구한다 · 판정 452)';
comment on column public.so.carrier is '택배사 글자 — ⭐ [ful-1a 판정 436] 표(carrier_id)가 주인 · 이 칸은 그 순간의 표 이름(옛 오더의 자유 글자는 그대로 남는다) · so_header_update(초안)는 아직 글자를 받는다(화면 ful-3 에서 id 로)';
alter table public.customer add column default_carrier_id uuid references public.ref_carrier (id) on delete no action;
create index customer_default_carrier_id_idx on public.customer (default_carrier_id);
comment on column public.customer.default_carrier_id is 'ful-1a 판정 436 · 451: 손님 기본 운송사(ref_carrier) — so_copy_customer 가 새 오더의 carrier_id 로 복사 · 옛 글자(default_carrier)와 이름이 정확히 같을 때만 이었고 나머지는 null(억지로 맞추면 Pickup 손님에게 발송 메일이 간다) · 적재(ImsLoadCustomer)는 글자만 쓰므로 이 칸을 덮지 않는다';
comment on column public.customer.default_carrier is 'Cin7 Carrier 원문 — ⭐ [ful-1a 판정 451] 기본값의 주인은 default_carrier_id · 이 글자는 원래 글자로 남긴다(표에 없는 글자를 직원이 보고 고른다)';

alter table public.so       disable trigger so_touch;                                     -- 이관은 「고침」이 아니다 — updated_at · updated_by 를 안 덮는다
alter table public.customer disable trigger customer_touch;
update public.so s set carrier_id = rc.id
  from public.ref_carrier rc
 where s.carrier is not null and lower(rc.name) = lower(btrim(s.carrier))
   and (select count(*) from public.ref_carrier r2 where lower(r2.name) = lower(btrim(s.carrier))) = 1;
update public.customer c set default_carrier_id = rc.id
  from public.ref_carrier rc
 where c.default_carrier is not null and lower(rc.name) = lower(btrim(c.default_carrier))
   and (select count(*) from public.ref_carrier r2 where lower(r2.name) = lower(btrim(c.default_carrier))) = 1;
alter table public.so       enable trigger so_touch;
alter table public.customer enable trigger customer_touch;

-- ═══ 3) so_copy_customer 재발행 — 20260924200029_so_invoice_a1.sql:93 바이트 복사 · 두 줄: carrier_id 복사 · 글자는 표 이름(없으면 옛 글자 그대로 — 힌트 · so_finalize 가 문) ═══
create or replace function public.so_copy_customer(p_so_id uuid, p_customer_id uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so        public.so%rowtype;
  c           public.customer%rowtype;
  v_bill      public.customer%rowtype;           -- 청구처 손님
  v_ship      public.customer%rowtype;           -- 배송 손님(주소 주인)
  v_tier      public.ref_price_tier%rowtype;
  v_ba        public.customer_address%rowtype;   -- 청구 주소
  v_sa        public.customer_address%rowtype;   -- 배송 주소
  v_contact   public.customer_contact%rowtype;   -- 배송 손님의 기본 연락처
  v_company   boolean;
  v_ship_n    integer;
  v_warn      text[] := '{}';
  v_n         integer;
  v_tax       jsonb;                              -- 세금 ② — 배송지에서 고른 규칙
  v_tw        text[];
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found — nothing was saved';
  end if;
  if v_so.status <> 'draft' then
    raise exception 'This order is not a draft (status %) — nothing was saved', v_so.status;
  end if;

  select * into c from public.customer where id = p_customer_id;
  if not found then
    raise exception 'Customer not found — nothing was saved';
  end if;
  if not c.is_active then
    v_warn := array_append(v_warn, 'customer_inactive');
  end if;
  if c.currency_id is null then
    raise exception 'Customer % has no currency — set it on the customer first — nothing was saved', c.name;
  end if;

  -- 티어(⬜3) — 이름 글자 그대로 · id 는 purpose 와 무관하게 남긴다
  if c.price_tier is null then
    v_warn := array_append(v_warn, 'price_tier_missing');
  else
    select * into v_tier from public.ref_price_tier where name = c.price_tier;
    if not found then
      v_warn := array_append(v_warn, 'price_tier_missing');
    else
      if v_tier.purpose <> 'sale' then v_warn := array_append(v_warn, 'price_tier_not_for_sale'); end if;
      if not v_tier.is_active     then v_warn := array_append(v_warn, 'price_tier_inactive');     end if;
      if v_tier.currency_id <> c.currency_id then v_warn := array_append(v_warn, 'currency_mismatch'); end if;
    end if;
  end if;

  -- 청구처 · 배송 손님
  select * into v_bill from public.customer where id = coalesce(c.default_bill_to_customer_id, c.id);
  select * into v_ship from public.customer where id = coalesce(c.default_ship_to_customer_id, c.id);

  -- 청구 주소 — 기본 Billing · 없으면 비움
  select * into v_ba
  from public.customer_address a
  where a.customer_id = v_bill.id and a.type = 'Billing' and a.is_active and a.is_default_for_type
  order by a.created_at limit 1;
  if not found then v_warn := array_append(v_warn, 'bill_to_empty'); end if;

  -- 배송 주소 — 판정 ⑧
  select * into v_sa
  from public.customer_address a
  where a.customer_id = v_ship.id and a.type = 'Shipping' and a.is_active and a.is_default_for_type
  order by a.created_at limit 1;
  if not found then
    select count(*) into v_ship_n from public.customer_address a
    where a.customer_id = v_ship.id and a.type = 'Shipping' and a.is_active;
    if v_ship_n = 0 then
      select * into v_sa
      from public.customer_address a
      where a.customer_id = v_ship.id and a.type = 'Billing' and a.is_active and a.is_default_for_type
      order by a.created_at limit 1;
      if found then
        v_warn := array_append(v_warn, 'ship_to_from_billing');
      else
        v_warn := array_append(v_warn, 'ship_to_empty');
      end if;
    else
      v_warn := array_append(v_warn, 'ship_to_empty');     -- Shipping 여럿 · 기본 없음 → 사람이 고른다
    end if;
  end if;

  -- 배송 손님의 기본 연락처 · 회사/사람(판정 3)
  select * into v_contact
  from public.customer_contact cc
  where cc.customer_id = v_ship.id and cc.is_default and cc.is_active
  order by cc.created_at limit 1;
  v_company := public.so_customer_is_company(v_ship.id);

  update public.so s set
    customer_id        = c.id,
    currency_id        = c.currency_id,
    currency_code      = c.currency_code,
    payment_term_id    = c.payment_term_id,
    payment_term_name  = c.payment_term_name,
    discount_pct       = c.discount_pct,
    price_tier         = c.price_tier,
    price_tier_id      = v_tier.id,
    ar_account_id      = c.ar_account_id,
    ar_account_code    = c.ar_account_code,
    sale_account_id    = c.sale_account_id,
    sale_account_code  = c.sale_account_code,
    location_id        = coalesce(s.location_id, c.default_location_id),
    location_name      = case when s.location_id is null then c.default_location_name else s.location_name end,
    carrier_id         = c.default_carrier_id,                                                                                   -- ful-1a 판정 436 · 451: 손님 기본 운송사(표)
    carrier            = coalesce((select rc.name from public.ref_carrier rc where rc.id = c.default_carrier_id), c.default_carrier),   -- ful-1a: 글자 = 표 이름 · 표에 없으면 옛 글자(힌트 · Ship & invoice 가 막는다)
    bill_to_customer_id      = v_bill.id,                       -- ⓐ1 이견 5 — 청구처 손님(FK) · 원문 bill_to_name 과 짝
    bill_to_name             = v_bill.name,
    bill_to_line1            = v_ba.line1,
    bill_to_line2            = v_ba.line2,
    bill_to_city             = v_ba.city,
    bill_to_state_province   = v_ba.state_province,
    bill_to_postal_code      = v_ba.postal_code,
    bill_to_country          = v_ba.country,
    ship_to_company          = case when v_company then v_ship.name else null end,
    ship_to_contact          = case when v_company then nullif(trim(v_contact.name), '') else v_ship.name end,
    ship_to_phone            = coalesce(nullif(trim(v_contact.phone), ''), nullif(trim(v_contact.mobile_phone), '')),
    ship_to_line1            = v_sa.line1,
    ship_to_line2            = v_sa.line2,
    ship_to_city             = v_sa.city,
    ship_to_state_province   = v_sa.state_province,
    ship_to_postal_code      = v_sa.postal_code,
    ship_to_country          = v_sa.country
  where s.id = p_so_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order not found — nothing was saved';
  end if;

  -- 세금 규칙(세금 ② · 판정 2·7) — 손님 저장값(c.tax_rule)은 읽지 않는다 · 새 배송지에서 고른다 · 사람이 정한 규칙은 나라·주가 같으면 그대로(바뀌기 전 배송지 = v_so)
  v_tax := public.so_tax_refresh(p_so_id, null, v_so.ship_to_country, v_so.ship_to_state_province);
  select array_agg(t.v) into v_tw from jsonb_array_elements_text(v_tax->'warnings') as t(v);
  v_warn := v_warn || coalesce(v_tw, '{}');

  return jsonb_build_object(
    'so_id',            p_so_id,
    'customer_id',      c.id,
    'price_tier_id',    v_tier.id,
    'ship_to_is_company', v_company,
    'tax_rule',         v_tax->'rule',
    'tax_rule_id',      v_tax->'rule_id',
    'tax_rule_manual',  v_tax->'manual',
    'warnings',         to_jsonb(v_warn)
  );
end;
$$;


-- ═══ 4) 표 셋 — 발송 결과 · 발송 줄 · 발송 큐 ═══
-- 4-a shop_fulfillment — 한 줄 = SO × Shopify 오더(합친 SO 는 오더마다 · 판정 442) · Shopify 가 돌려주는 fulfillment GID(판정 447 메아리 거르기 · 438 고치기) · 픽업 진행 시각(판정 443)
create table public.shop_fulfillment (
  id                       uuid primary key default gen_random_uuid(),
  so_id                    uuid not null references public.so (id) on delete no action,
  shop_order_id            uuid not null references public.shop_order (id) on delete no action,
  store_id                 uuid not null references public.shop_store (id) on delete no action,
  fulfillment_order_gid    text,                                                          -- EF 가 보내기 직전에 읽어 채운다(ful-2 · 위치 맞추기 판정 445 뒤의 FO)
  shopify_fulfillment_gid  text,                                                          -- Shopify 가 돌려준 GID(보내기 전 null)
  carrier_id               uuid references public.ref_carrier (id) on delete no action,
  carrier_name             text,                                                          -- 그 순간의 표 이름
  carrier_kind             text,                                                          -- carrier · pickup · delivery(그 순간)
  shopify_company          text,                                                          -- 그 순간의 Shopify 이름(null = 글자만)
  tracking_numbers         text[] not null default '{}',                                  -- 판정 437 · 쉼표 · 줄바꿈으로 나눈 것 · pickup · delivery 는 빈 배열
  notify_customer          boolean not null default false,                               -- carrier 만 true(판정 436)
  status                   text not null default 'pending',                               -- pending · sent · error
  attempts                 int not null default 0,
  last_error               text,
  sent_at                  timestamptz,
  ready_at                 timestamptz,                                                   -- 판정 443 「Ready for pickup」 보낸 시각(ful-1b)
  picked_up_at             timestamptz,                                                   -- 판정 443 「Picked up」 보낸 시각(ful-1b)
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  updated_by               uuid references public.ims_staff (id) on delete no action,
  constraint shop_fulfillment_uk         unique (so_id, shop_order_id),
  constraint shop_fulfillment_gid_uk     unique (shopify_fulfillment_gid),
  constraint shop_fulfillment_gid_ck     check (shopify_fulfillment_gid is null or shopify_fulfillment_gid ~ '^gid://shopify/Fulfillment/[0-9]+$'),
  constraint shop_fulfillment_fo_gid_ck  check (fulfillment_order_gid is null or fulfillment_order_gid ~ '^gid://shopify/FulfillmentOrder/[0-9]+$'),
  constraint shop_fulfillment_kind_ck    check (carrier_kind is null or carrier_kind in ('carrier', 'pickup', 'delivery')),
  constraint shop_fulfillment_status_ck  check (status in ('pending', 'sent', 'error')),
  constraint shop_fulfillment_sent_ck    check ((status = 'sent') = (shopify_fulfillment_gid is not null))
);
create index shop_fulfillment_shop_order_id_idx on public.shop_fulfillment (shop_order_id);
create index shop_fulfillment_store_id_idx      on public.shop_fulfillment (store_id);
create index shop_fulfillment_carrier_id_idx    on public.shop_fulfillment (carrier_id);
create index shop_fulfillment_updated_by_idx    on public.shop_fulfillment (updated_by);
create trigger shop_fulfillment_touch before update on public.shop_fulfillment for each row execute function public.ims_touch();
comment on table public.shop_fulfillment is 'ful-1a 판정 436 ~ 448: IMS 가 Shopify 에 보낼(보낸) 발송 — 한 줄 = SO × Shopify 오더(합친 SO 는 오더마다 · 판정 442) · shop_fulfill_enqueue 가 출고 순간 pending 으로 만든다 · EF(ful-2)가 fulfillmentCreate 뒤 shopify_fulfillment_gid · status sent · 메아리 거르기(판정 447)는 이 GID 로 · 송장 고치기(438) · 픽업 진행(443 ready_at · picked_up_at)은 ful-1b · 쓰기는 definer 창구(so_ship 안)와 EF(service_role)만';

-- 4-b shop_fulfillment_line — 발송의 줄 = Shopify 줄(line_gid) × IMS 줄(콤보 · 세트는 그 줄 · 구성품 없음) × 수량(판매 단위 · IMS 쪽 수량 — Shopify 남은 수량으로 자르기는 EF · 미룬 201 b)
create table public.shop_fulfillment_line (
  id                               uuid primary key default gen_random_uuid(),
  fulfillment_id                   uuid not null references public.shop_fulfillment (id) on delete cascade,   -- 문서 → 소유 줄(거래 표 규약)
  shop_order_line_id               uuid not null references public.shop_order_line (id) on delete no action,
  line_gid                         text not null,                                          -- Shopify LineItem GID(그 순간 복사)
  so_line_id                       uuid not null references public.so_line (id) on delete no action,   -- 출고한 IMS 줄(형제 · 합친 줄)
  quantity                         numeric not null,
  fulfillment_order_line_item_gid  text,                                                   -- EF 가 보내기 직전에 읽어 채운다(ful-2)
  constraint shop_fulfillment_line_uk      unique (fulfillment_id, shop_order_line_id, so_line_id),
  constraint shop_fulfillment_line_qty_ck  check (quantity > 0)
);
create index shop_fulfillment_line_shop_order_line_id_idx on public.shop_fulfillment_line (shop_order_line_id);
create index shop_fulfillment_line_so_line_id_idx         on public.shop_fulfillment_line (so_line_id);
comment on table public.shop_fulfillment_line is 'ful-1a: 발송의 줄 — shop_fulfill_lineage 가 계보(split_from_line_id · so_line_merge_source)로 찾은 Shopify 줄 × 출고한 IMS 줄 × 수량(콤보 · 세트는 그 줄의 qty_shipped · 구성품 없음) · 합친 줄은 출처 순으로 나눈 몫(이견 2)';

-- 4-c shop_fulfill_queue — 한 줄 = SO × 일 종류 · unique(so_id, kind) = 멱등(한 SO 는 한 번만 출고 · 인보이스 취소 · 재발행은 두 번 넣지 못한다) · 반복되는 일(tracking_fix)은 같은 행을 다시 연다(ful-1b)
create table public.shop_fulfill_queue (
  id          bigint generated always as identity primary key,
  so_id       uuid not null references public.so (id) on delete no action,
  kind        text not null,                                                              -- ship(이 차수) · tracking_fix · ready_pickup · picked_up(ful-1b)
  queued_at   timestamptz not null default now(),
  started_at  timestamptz,
  done_at     timestamptz,
  attempts    int not null default 0,
  result      text,                                                                       -- ok · skipped · error
  error       text,
  constraint shop_fulfill_queue_uk        unique (so_id, kind),
  constraint shop_fulfill_queue_kind_ck   check (kind in ('ship', 'tracking_fix', 'ready_pickup', 'picked_up')),
  constraint shop_fulfill_queue_result_ck check (result is null or result in ('ok', 'skipped', 'error')),
  constraint shop_fulfill_queue_done_ck   check ((done_at is null) = (result is null))
);
create index shop_fulfill_queue_open_idx on public.shop_fulfill_queue (queued_at) where done_at is null;   -- 열린 줄 찾기(유니크 아님 · 규칙 29 는 유니크 부분 인덱스만 금지)
comment on table public.shop_fulfill_queue is 'ful-1a: 발송 큐 — 한 줄 = SO × kind · unique(so_id, kind) 가 멱등(한 SO 는 한 번만 출고 · 판정 §61-b) · ship 은 so_ship 끝의 shop_fulfill_enqueue 가 넣는다(계보가 Shopify 에 닿는 SO 만) · tracking_fix · ready_pickup · picked_up 은 ful-1b(반복되면 같은 행을 다시 연다 — 부분 유니크 인덱스 없이) · 441 order_edit · 449 mark_paid 는 열쇠가 shop_order 라 이 큐가 아니다 · 비우는 EF 는 ful-2(fulfill_drain · cron)';

do $$ declare t text; begin
  foreach t in array array['shop_fulfillment', 'shop_fulfillment_line', 'shop_fulfill_queue'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- ═══ 5) 함수 — 송장 나누기 · 줄 계보 · 큐 넣기 ═══
-- 5-a 송장 나누기(판정 437) — 쉼표 · 줄바꿈으로 나눠 앞뒤 공백을 빼고 빈 조각을 버린다 · null · '' → 빈 배열
create function public.shop_tracking_split(p_text text) returns text[]
  language sql immutable
  set search_path = public, pg_temp
as $$
  select coalesce((select array_agg(s.x order by s.ord) from (select btrim(t.x) as x, t.ord from regexp_split_to_table(coalesce(p_text, ''), '[,\n\r]+') with ordinality as t(x, ord)) s where s.x <> ''), '{}'::text[]);
$$;
revoke all on function public.shop_tracking_split(text) from public, anon, authenticated;
comment on function public.shop_tracking_split(text) is 'ful-1a 판정 437: 송장 칸 하나에 쉼표 · 줄바꿈으로 적은 여러 송장을 배열로(앞뒤 공백 뺌 · 빈 조각 버림) · so_finalize 가 검사 · shop_fulfillment.tracking_numbers · EF 가 Shopify numbers[] 로';

-- 5-b 줄 계보 — IMS 줄 하나(수량)를 shop_order_line 까지 올라간다: 짝이 있으면 그것 · split_from_line_id 면 모체 줄 · 합친 줄이면 출처들(출처 SO 번호 · 줄 번호 순 · 출처 줄 수량까지 · 남는 몫은 마지막 출처 · 이견 2) · 어느 것도 아니면 0 행(웹 줄이 아니다)
create function public.shop_fulfill_trace(p_line_id uuid, p_qty numeric, p_depth int default 0)
  returns table (shop_order_line_id uuid, quantity numeric)
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_l    public.so_line%rowtype;
  v_sol  uuid;
  v_n    int;  i int := 0;
  v_rem  numeric;  v_take numeric;
  src    record;
begin
  if p_qty is null or p_qty <= 0 then return; end if;
  if p_depth > 32 then raise exception 'shop_fulfill_trace: line % — lineage deeper than 32 (loop?) — nothing was saved', p_line_id; end if;
  select l.id into v_sol from public.shop_order_line l where l.so_line_id = p_line_id order by l.line_no limit 1;
  if v_sol is not null then
    shop_order_line_id := v_sol;  quantity := p_qty;  return next;  return;
  end if;
  select * into v_l from public.so_line l where l.id = p_line_id;
  if not found then return; end if;
  if v_l.split_from_line_id is not null then
    return query select t.shop_order_line_id, t.quantity from public.shop_fulfill_trace(v_l.split_from_line_id, p_qty, p_depth + 1) t;
    return;
  end if;
  select count(*) into v_n from public.so_line_merge_source m where m.line_id = p_line_id;
  if v_n = 0 then return; end if;
  v_rem := p_qty;
  for src in
    select m.from_line_id, greatest(f.qty_ordered - coalesce(f.qty_removed, 0), 0) as cap
      from public.so_line_merge_source m join public.so_line f on f.id = m.from_line_id join public.so fs on fs.id = f.so_id
     where m.line_id = p_line_id
     order by fs.so_number, f.line_no
  loop
    i := i + 1;
    v_take := case when i = v_n then v_rem else least(v_rem, src.cap) end;
    if v_take > 0 then
      return query select t.shop_order_line_id, t.quantity from public.shop_fulfill_trace(src.from_line_id, v_take, p_depth + 1) t;
      v_rem := v_rem - v_take;
    end if;
    exit when v_rem <= 0;
  end loop;
  return;
end;
$$;
revoke all on function public.shop_fulfill_trace(uuid, numeric, int) from public, anon, authenticated;
comment on function public.shop_fulfill_trace(uuid, numeric, int) is 'ful-1a 이견 2: IMS 줄(수량) → Shopify 줄(shop_order_line) 짝 — 직접 짝 · split_from_line_id(모체 줄) · so_line_merge_source(출처들 — 출처 SO 번호 · 줄 번호 순으로 출처 줄 수량까지 채우고 남는 몫은 마지막 출처) 를 만날 때까지 올라간다 · 웹 줄이 아니면 0 행 · 깊이 32 넘으면 예외';

-- 5-c SO 하나의 보낼 것 — (Shopify 오더 · Shopify 줄 · IMS 줄 · 출고 수량) · 콤보 · 세트는 그 줄(구성품 줄 제외) · 수량 = qty_shipped(IMS 쪽 — Shopify 남은 수량으로 자르기는 EF · 미룬 201 b)
create function public.shop_fulfill_lineage(p_so_id uuid)
  returns table (shop_order_id uuid, shop_order_line_id uuid, line_gid text, so_line_id uuid, quantity numeric)
  language sql stable
  set search_path = public, pg_temp
as $$
  select o.id, sol.id, sol.line_gid, l.id, sum(t.quantity)
    from public.so_line l
    cross join lateral public.shop_fulfill_trace(l.id, l.qty_shipped, 0) t
    join public.shop_order_line sol on sol.id = t.shop_order_line_id
    join public.shop_order o on o.id = sol.shop_order_id
   where l.so_id = p_so_id and l.combo_line_id is null and coalesce(l.qty_shipped, 0) > 0
   group by o.id, o.name, sol.id, sol.line_gid, sol.line_no, l.id, l.line_no
   order by o.name, sol.line_no, l.line_no;
$$;
revoke all on function public.shop_fulfill_lineage(uuid) from public, anon, authenticated;
comment on function public.shop_fulfill_lineage(uuid) is 'ful-1a 판정 442: 출고한 SO 하나 → 보낼 (Shopify 오더 · Shopify 줄 · IMS 줄 · 수량) 목록 — 계보(shop_fulfill_trace)로 · 합친 SO 는 Shopify 오더가 둘 이상 · 콤보 · 세트는 그 줄의 qty_shipped(구성품 아님) · 0 행 = 웹 오더가 아니다(POS · 전화 오더)';

-- 5-d 계보가 닿는 Shopify 오더(출고 전 · 수량 무관) — so_finalize 의 「Shopify 오더면 운송사 필수」(판정 452) · PICK_UP 검사
create function public.shop_fulfill_web_orders(p_so_id uuid) returns setof public.shop_order
  language sql stable
  set search_path = public, pg_temp
as $$
  select distinct o.*
    from public.so_line l
    cross join lateral public.shop_fulfill_trace(l.id, greatest(coalesce(l.qty_ordered, 0), 1), 0) t
    join public.shop_order_line sol on sol.id = t.shop_order_line_id
    join public.shop_order o on o.id = sol.shop_order_id
   where l.so_id = p_so_id and l.combo_line_id is null;
$$;
revoke all on function public.shop_fulfill_web_orders(uuid) from public, anon, authenticated;
comment on function public.shop_fulfill_web_orders(uuid) is 'ful-1a 판정 452: 이 SO 의 줄 계보가 닿는 Shopify 오더들(출고 전에도 · 수량 무관) — so_finalize 가 「운송사 필수」 · 「PICK_UP 오더에 carrier 금지」 에 쓴다 · 0 행 = 웹 오더가 아니다';

-- 5-e 큐 넣기(출고 방아쇠 · 이견 1) — so_ship 끝에서 부른다 · shipped_at 이 없으면 안 넣음 · 계보 0 이면 안 넣음 · unique(so_id, ship) 로 멱등(이미 있으면 결과 표도 다시 안 만든다)
create function public.shop_fulfill_enqueue(p_so_id uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so   public.so%rowtype;
  v_car  public.ref_carrier%rowtype;
  v_trk  text[];
  v_n    int;  v_f int := 0;  v_fl int := 0;
  v_fid  uuid;
  r      record;
begin
  select * into v_so from public.so s where s.id = p_so_id;
  if not found then raise exception 'shop_fulfill_enqueue: order % not found — nothing was saved', p_so_id; end if;
  if v_so.shipped_at is null then return jsonb_build_object('queued', false, 'reason', 'not_shipped'); end if;
  if not exists (select 1 from public.shop_fulfill_lineage(p_so_id)) then return jsonb_build_object('queued', false, 'reason', 'no_shopify_lineage'); end if;
  insert into public.shop_fulfill_queue (so_id, kind) values (p_so_id, 'ship') on conflict (so_id, kind) do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then return jsonb_build_object('queued', false, 'reason', 'already_queued'); end if;
  if v_so.carrier_id is not null then select * into v_car from public.ref_carrier rc where rc.id = v_so.carrier_id; end if;
  v_trk := case when v_car.kind = 'carrier' then public.shop_tracking_split(v_so.tracking_number) else '{}'::text[] end;
  for r in select distinct g.shop_order_id from public.shop_fulfill_lineage(p_so_id) g loop
    insert into public.shop_fulfillment (so_id, shop_order_id, store_id, carrier_id, carrier_name, carrier_kind, shopify_company, tracking_numbers, notify_customer, updated_by)
    select p_so_id, o.id, o.store_id, v_car.id, v_car.name, v_car.kind, v_car.shopify_company, v_trk, coalesce(v_car.kind = 'carrier', false), v_so.shipped_by
      from public.shop_order o where o.id = r.shop_order_id
    returning id into v_fid;
    insert into public.shop_fulfillment_line (fulfillment_id, shop_order_line_id, line_gid, so_line_id, quantity)
    select v_fid, g.shop_order_line_id, g.line_gid, g.so_line_id, g.quantity from public.shop_fulfill_lineage(p_so_id) g where g.shop_order_id = r.shop_order_id;
    get diagnostics v_n = row_count;
    v_f := v_f + 1;  v_fl := v_fl + v_n;
  end loop;
  return jsonb_build_object('queued', true, 'fulfillments', v_f, 'lines', v_fl, 'carrier', v_car.name, 'kind', v_car.kind, 'tracking', to_jsonb(v_trk));
end;
$$;
revoke all on function public.shop_fulfill_enqueue(uuid) from public, anon, authenticated;
comment on function public.shop_fulfill_enqueue(uuid) is 'ful-1a 이견 1 · §61-b: 출고 방아쇠 — so_ship 끝(shipped_at · qty_shipped · 형제 split 뒤)에서 부른다 · shipped_at 없으면 안 넣음 · 계보가 Shopify 에 안 닿으면(POS · 전화) 안 넣음 · 큐 unique(so_id, ship) 로 멱등(인보이스 취소 · 재발행은 못 넣는다) · 넣을 때 shop_fulfillment(오더마다) + 줄을 pending 으로 만든다(운송사 · 송장은 so 의 그 순간 값 · pickup · delivery 는 송장 없음 · 메일 없음) · service_role · definer 창구 안에서만';

-- ═══ 6) so_ship 재발행 — 20261005201634_asm_2b1_combo_warehouse_path.sql:222 바이트 복사 · 석 줄(v_fulfill · 끝에 enqueue · 반환 fulfill) ═══
create or replace function public.so_ship(p_so_id uuid, p_picks jsonb, p_staff uuid, p_shipped_on date default null) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  v_wh       public.ref_warehouse%rowtype;
  v_on       date;
  v_bad      text;
  v_norm     jsonb;
  v_lines    jsonb := '[]'::jsonb;
  b_moves    jsonb := '[]'::jsonb;
  b_n        int := 0;
  v_shipped  int := 0;
  v_sib      public.so%rowtype;
  v_warn     text[] := '{}';
  v_fulfill  jsonb;                                                   -- ful-1a: 발송 큐 넣기 결과(shop_fulfill_enqueue)
  v_ledger   jsonb;
  v_n        int;
  r          record;
  v_from     text;                                              -- ④a2: 「아직 안 나감」 상태 — pos·counter confirmed · warehouse packed(7-c)
  c          record;                                            -- asm-2b1(판정 244 · 묶음 2 · 4): 콤보 줄은 구성품이 나간 만큼 통째로 · 반쪽 콤보는 내보내지 않는다
begin
  if p_staff is null then raise exception 'so_ship needs the acting staff id — nothing was saved'; end if;

  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status = 'shipped' then                               -- 재호출 멱등 — 예외가 아니라 조용한 반환(7-c · wms_complete_pack)
    return jsonb_build_object('shipped', false, 'reason', 'already_shipped', 'so_number', v_so.so_number, 'shipped_at', v_so.shipped_at, 'shipped_by', v_so.shipped_by);
  end if;
  v_from := case when v_so.channel in ('pos', 'counter') then 'confirmed' else 'packed' end;
  if v_so.status <> v_from then
    raise exception 'Order % is % — only a % order can ship here — nothing was saved', v_so.so_number, v_so.status, v_from;
  end if;
  if v_so.location_id is null then raise exception 'Order % has no warehouse — nothing was saved', v_so.so_number; end if;
  select * into v_wh from public.ref_warehouse where id = v_so.location_id;
  if not found or not v_wh.is_active then
    raise exception 'Warehouse % of order % is inactive — nothing was saved', coalesce(v_wh.name, '?'), v_so.so_number;
  end if;
  v_on := coalesce(p_shipped_on, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Ship date % is in the future — nothing was saved', v_on; end if;

  -- 픽 다듬기 — 모양 · 줄 · 수량 · 칸
  if p_picks is null or jsonb_typeof(p_picks) <> 'array' or jsonb_array_length(p_picks) = 0 then
    raise exception 'p_picks must be a JSON array of {line_id, bin, qty} — nothing was saved';
  end if;
  if exists (select 1 from jsonb_array_elements(p_picks) e where nullif(e->>'line_id', '') is null or nullif(e->>'qty', '') is null) then
    raise exception 'Every pick needs a line_id and a qty — nothing was saved';
  end if;
  if exists (select 1 from jsonb_array_elements(p_picks) e where (e->>'qty') !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' or (e->>'qty')::numeric <= 0) then
    raise exception 'Every pick needs a positive quantity — nothing was saved';
  end if;
  select string_agg(distinct e->>'line_id', ', ') into v_bad
  from jsonb_array_elements(p_picks) e
  where not exists (select 1 from public.so_line l where l.id = (e->>'line_id')::uuid and l.so_id = p_so_id);
  if v_bad is not null then raise exception 'Pick line % is not on order % — nothing was saved', v_bad, v_so.so_number; end if;
  select string_agg(distinct l.line_no::text, ', ') into v_bad                                                                          -- asm-2b1: 콤보 줄에는 픽이 없다 — 구성품 줄이 재고를 든다
  from jsonb_array_elements(p_picks) e join public.so_line l on l.id = (e->>'line_id')::uuid
  where exists (select 1 from public.so_line k where k.combo_line_id = l.id);
  if v_bad is not null then raise exception 'Pick line % of % is a combo line — pick its component lines instead — nothing was saved', v_bad, v_so.so_number; end if;
  select string_agg(distinct x.bin, ', ') into v_bad
  from (select coalesce(nullif(trim(e->>'bin'), ''), '') as bin from jsonb_array_elements(p_picks) e) x
  where x.bin <> '' and not exists (select 1 from public.ref_bin rb where rb.warehouse_id = v_so.location_id and rb.name = x.bin);
  if v_bad is not null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bad, v_wh.name; end if;
  select string_agg(distinct x.bin, ', ') into v_bad
  from (select coalesce(nullif(trim(e->>'bin'), ''), '') as bin from jsonb_array_elements(p_picks) e) x
  join public.ref_bin rb on rb.warehouse_id = v_so.location_id and rb.name = x.bin
  where not rb.is_active;
  if v_bad is not null then v_warn := array_append(v_warn, 'inactive_bin:' || v_bad); end if;   -- 받는다 — 실물이 그 칸에서 나왔다(판정 12 · 안)

  select coalesce(jsonb_agg(jsonb_build_object('line_id', g.line_id, 'bin', g.bin, 'qty', g.qty) order by g.line_id, g.bin), '[]'::jsonb) into v_norm
  from (select (e->>'line_id')::uuid as line_id, coalesce(nullif(trim(e->>'bin'), ''), '') as bin, sum((e->>'qty')::numeric) as qty
        from jsonb_array_elements(p_picks) e group by 1, 2) g;

  -- 줄마다 — 열린 allocated 예약이 있어야(packed 오더는 전부 할당 · R1) · 합 > 주문 거부 · 합 < 주문은 차이
  for r in
    select l.id, l.line_no, l.sku, l.qty_ordered, l.qty_removed, l.qty_ordered - l.qty_removed as target, coalesce(s.qty, 0) as shipped,   -- ⓐ2 판정 5: 목표 = 주문 − 손님이 뺀 것
           exists (select 1 from public.so_reserve x where x.so_line_id = l.id and x.released_at is null and x.kind = 'allocated') as has_alloc
    from public.so_line l
    left join (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s on s.line_id = l.id
    where l.so_id = p_so_id
      and not exists (select 1 from public.so_line k where k.combo_line_id = l.id)                                                   -- asm-2b1: 콤보 줄은 아래 콤보 고리에서(예약 · 픽이 없다)
    order by l.line_no
  loop
    if not r.has_alloc then
      raise exception 'Line % of % (%) has no open allocation — an order must be fully allocated to ship — nothing was saved', r.line_no, v_so.so_number, r.sku;
    end if;
    if r.shipped > r.target then
      raise exception 'Line % of % (%): picked % but % to ship (ordered % minus removed %) — over-pick goes back to its bin, it does not ship — nothing was saved', r.line_no, v_so.so_number, r.sku, r.shipped, r.target, r.qty_ordered, r.qty_removed;
    end if;
    if r.shipped < r.target and v_so.channel in ('pos', 'counter') then   -- ④a2 6-d: pos·counter 에는 백오더가 없다 — 목표 아래 픽은 거부(줄이려면 다시 열기)
      raise exception 'Line % of % (%): picked % of % to ship — a % order ships only what was scanned (no backorder) — reopen the order and fix the line — nothing was saved', r.line_no, v_so.so_number, r.sku, r.shipped, r.target, v_so.channel;
    end if;
    if r.shipped < r.target then                                -- ⓐ2 판정 5·7: 뺀 몫은 백오더가 아니다 · 목표 아래 차이만 pick_short(할인 그대로)
      b_moves := b_moves || jsonb_build_object('line_id', r.id, 'qty', r.target - r.shipped);  b_n := b_n + 1;
    end if;
    if r.shipped > 0 then v_shipped := v_shipped + 1; end if;
    v_lines := v_lines || jsonb_build_object('line_id', r.id, 'line_no', r.line_no, 'sku', r.sku, 'ordered', r.qty_ordered, 'removed', r.qty_removed, 'to_ship', r.target, 'shipped', r.shipped, 'short', r.target - r.shipped);
  end loop;
  -- asm-2b1(묶음 4): 콤보 줄 — 나간 콤보 수 = min(구성품 나간 수 ÷ 콤보 하나의 구성품 수) · 어느 구성품이 그보다 더 나가면 반쪽 콤보라 거부(Finalize 가 먼저 줄인다 · 2b2) · 모자란 콤보는 통째로 백오더(구성품 줄의 몫은 위 고리가 이미 비례로 넣었다)
  for c in
    select p.id, p.line_no, p.sku, p.qty_ordered, p.qty_removed, p.qty_ordered - p.qty_removed as target,
           (select min(floor(coalesce(s.qty, 0) / k.combo_qty)) from public.so_line k
              left join (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s on s.line_id = k.id
             where k.combo_line_id = p.id) as whole
    from public.so_line p where p.so_id = p_so_id and exists (select 1 from public.so_line k where k.combo_line_id = p.id) order by p.line_no
  loop
    select string_agg(format('%s picked %s, whole combos need %s', k.sku, trim_scale(coalesce(s.qty, 0)), trim_scale(c.whole * k.combo_qty)), '; ' order by k.line_no) into v_bad   -- trim_scale: 「2.000000」 이 아니라 「2」
      from public.so_line k left join (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s on s.line_id = k.id
     where k.combo_line_id = c.id and coalesce(s.qty, 0) > c.whole * k.combo_qty;
    if v_bad is not null then
      raise exception 'Combo % (line %) of %: components picked beyond whole combos (%) — a combo ships whole or not at all; put the extra back — nothing was saved', c.sku, c.line_no, v_so.so_number, v_bad;
    end if;
    if c.whole < c.target then
      b_moves := b_moves || jsonb_build_object('line_id', c.id, 'qty', c.target - c.whole);  b_n := b_n + 1;
    end if;
    v_lines := v_lines || jsonb_build_object('line_id', c.id, 'line_no', c.line_no, 'sku', c.sku, 'ordered', c.qty_ordered, 'removed', c.qty_removed, 'to_ship', c.target, 'shipped', c.whole, 'short', c.target - c.whole, 'combo', true);
  end loop;
  if v_shipped = 0 then
    raise exception 'Order % has no picked quantity at all — nothing ships (cancel or hold it with the order actions) — nothing was saved', v_so.so_number;
  end if;

  -- ① CAS 플립 — 첫 쓰기(문지기 packed→shipped) · 0행 = 그 사이 남이 바꿨다
  update public.so set status = 'shipped', shipped_at = now(), shipped_by = p_staff, updated_by = p_staff
  where id = p_so_id and status = v_from;                       -- ④a2: 문지기 짝 packed→shipped · confirmed→shipped(pos·counter)
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order % was not shipped — it may have been changed by someone else just now — nothing was saved', v_so.so_number;
  end if;

  -- ② 할당 닫기(5-f · ⬜4) — 나간 줄 shipped · 전량 못 나간 줄 released(실물이 없었다 · 형제에 backorder 가 선다)
  update public.so_reserve x set released_at = now(), released_by = p_staff, updated_by = p_staff,
         released_reason = case when coalesce(s.qty, 0) > 0 then 'shipped' else 'released' end
  from public.so_line l
  left join (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s on s.line_id = l.id
  where x.so_line_id = l.id and l.so_id = p_so_id and x.released_at is null and x.kind = 'allocated';

  -- ③ 줄 qty_shipped(판매 단위 · 나간 줄만 · 전량 못 나간 줄은 0 그대로 행째 형제로 간다)
  update public.so_line l set qty_shipped = s.qty, updated_by = p_staff
  from (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s
  where s.line_id = l.id and l.so_id = p_so_id;
  update public.so_line p set qty_shipped = (select min(floor(k.qty_shipped / k.combo_qty)) from public.so_line k where k.combo_line_id = p.id), updated_by = p_staff   -- asm-2b1 ③′: 콤보 줄 「출고됨」 = 구성품이 다 나간 콤보 수(2b2 Finalize · 인보이스가 읽는다)
  where p.so_id = p_so_id and exists (select 1 from public.so_line k where k.combo_line_id = p.id);

  -- ④ 출하 차이 → 백오더 형제(2-f · 7-b · ⬜6 pick_short) — 할당 없이 · 물건이 들어와도 자동으로 잡지 않는다 · 재고 조정은 사람이(2-f)
  if b_n > 0 then
    v_sib := public.so_split(p_so_id, 'pick_short', b_moves, 'confirmed', p_staff);
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'backorder', null from public.so_line x where x.so_id = v_sib.id and not exists (select 1 from public.so_line k where k.combo_line_id = x.id);   -- asm-2b1: 콤보 줄 제외
  end if;

  -- ⑤ 원장 — 창구 하나(원장 행 + FIFO + 부족분 · 한 트랜잭션 · 실패하면 출고도 실패)
  v_ledger := public.inv_post_sale(p_so_id, v_norm, v_on);

  -- ⑥ ful-1a 이견 1 · 판정 §61-b: 출고 방아쇠 — shipped_at(①) · qty_shipped(③) · 형제 split(④) · 원장(⑤) 뒤 · 계보가 Shopify 에 닿는 SO 만 큐에(POS · 전화 오더는 0 행) · 같은 트랜잭션
  v_fulfill := public.shop_fulfill_enqueue(p_so_id);

  return jsonb_build_object(
    'shipped', true, 'so_number', v_so.so_number, 'shipped_on', v_on, 'shipped_by', p_staff,
    'lines', v_lines,
    'backorder', case when b_n > 0 then jsonb_build_object('so_id', v_sib.id, 'so_number', v_sib.so_number, 'split_reason', 'pick_short', 'lines', b_n) else null end,
    'ledger', v_ledger, 'warnings', to_jsonb(v_warn), 'fulfill', v_fulfill);   -- ful-1a
end;
$$;

-- ═══ 7) so_finalize 재발행 — 20261007171939_fr_1_freight_discount.sql:163 바이트 복사 · ① 검사에 운송사 · 송장(판정 436 · 437 · 452) · ② 쓰기는 ① 이 푼 값으로 ═══
create or replace function public.so_finalize(p_orders jsonb, p_commit boolean default true, p_shipped_on date default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_reasons  constant text[] := array['customer_removed', 'not_wanted', 'other'];
  v_staff    uuid;
  v_on       date;
  v_n        int;  v_cnt int;
  v_bad      text;
  e          jsonb;  x jsonb;
  v_so       public.so%rowtype;
  v_l        public.so_line%rowtype;
  v_c        public.customer%rowtype;
  v_acct     public.ref_account%rowtype;
  v_ch       public.so_charge%rowtype;
  q          record;
  v_qty      numeric;  v_remaining numeric;  v_new_unit numeric;
  v_reason   text;  v_key text;  k text;
  v_next     int;
  v_removed  jsonb;  v_repriced jsonb;  v_charges jsonb;  v_ship jsonb;  v_iss jsonb;
  v_surcharges jsonb;  v_spct numeric;  v_samt numeric;  v_slbl text;                 -- surcharge-2a(판정 230)
  v_orders   jsonb := '[]'::jsonb;
  v_groups   jsonb := '{}'::jsonb;
  v_invoices jsonb := '[]'::jsonb;
  v_ids      uuid[];
  v_warn     text[] := '{}';
  v_tw       text[];
  v_dp       numeric;  v_da numeric;                                                   -- fr-1 판정 353 · 356: 운임 할인(열쇠 없으면 그대로 · '' 이면 지움)
  v_car      public.ref_carrier%rowtype;  v_trk text[];  v_web boolean;  v_pick text;    -- ful-1a 판정 436 · 437 · 452: 운송사(표) · 송장 조각 · Shopify 계보 · PICK_UP 오더 이름
  v_rm       jsonb;  v_pk jsonb;  v_pb jsonb;  v_put_back jsonb := '[]'::jsonb;  v_ord int;  v_cut numeric;  i int;  cb record;  kk record;   -- asm-2b2(판정 246 · 묶음 3 · 4): 콤보 단위 removed(펼친 목록 v_rm) · 구성품 픽을 통째 콤보로 줄이기(v_pk · put_back) — 별칭은 cp · p2 · z · t2(declare 변수와 다르게)
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 8: 마무리는 오더 담당(sales)부터 · 역할 문 없음(R5 의 예외)
  v_staff := public.so_current_staff();
  v_on := coalesce(p_shipped_on, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Ship date % is in the future — nothing was saved', v_on; end if;
  if p_orders is null or jsonb_typeof(p_orders) <> 'array' or jsonb_array_length(p_orders) = 0 then
    raise exception 'p_orders must be a JSON array of orders — nothing was saved';
  end if;
  if exists (select 1 from jsonb_array_elements(p_orders) t where jsonb_typeof(t) <> 'object' or nullif(t->>'so_id', '') is null) then
    raise exception 'Every order needs a so_id — nothing was saved';
  end if;
  select count(*), count(distinct t->>'so_id') into v_cnt, v_n from jsonb_array_elements(p_orders) t;
  if v_n <> v_cnt then raise exception 'The same order is listed twice — nothing was saved'; end if;
  -- ⑤-2b(판정 16 · ⬜7): picks 가 없으면 WMS 인계(wms_so_handoff)의 picks 를 쓴다(있으면 그대로 — 오피스가 고칠 길)
  select jsonb_agg(case when t.e ? 'picks' then t.e else t.e || jsonb_build_object('picks', (public.wms_so_handoff((t.e->>'so_id')::uuid))->'picks') end order by t.ord) into p_orders from jsonb_array_elements(p_orders) with ordinality t(e, ord);

  -- ① 검사 — 오더마다(잠금) · 하나라도 막히면 전체 거부 · 오더 번호로 말한다
  v_ord := -1;
  for e in select t from jsonb_array_elements(p_orders) t loop
    v_ord := v_ord + 1;                                                                 -- asm-2b2: 줄인 picks · 펼친 removed 를 이 자리에 되적는다(②~⑤ 가 읽는다)
    select * into v_so from public.so s where s.id = (e->>'so_id')::uuid for update;
    if not found then raise exception 'Order % not found — nothing was saved', e->>'so_id'; end if;
    if v_so.status <> 'packed' then
      raise exception 'Order % is % — only a packed order (warehouse work finished) can be finalized here — nothing was saved', v_so.so_number, v_so.status;
    end if;
    if v_so.bill_to_customer_id is null then raise exception 'Order % has no bill-to customer — nothing was saved', v_so.so_number; end if;
    -- 뺀 몫(판정 5) — 모양 · 줄 · 수량 · 사유 · 중복
    if e ? 'removed' and jsonb_typeof(e->'removed') not in ('array', 'null') then
      raise exception 'Order %: removed must be an array of {line_id, qty, reason, note} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = nullif(x->>'line_id', '')::uuid and l.so_id = v_so.id;
      if not found then raise exception 'Order %: removed line % is not on this order — nothing was saved', v_so.so_number, coalesce(x->>'line_id', '?'); end if;
      if v_l.combo_line_id is not null then                                                                                                    -- asm-2b2(묶음 3): 뺀 몫은 콤보 줄에만 · 구성품은 따라간다
        raise exception 'Order %: line % is a component of combo % (line %) — remove from the combo line instead — nothing was saved', v_so.so_number, v_l.line_no,
          (select p2.sku from public.so_line p2 where p2.id = v_l.combo_line_id), (select p2.line_no from public.so_line p2 where p2.id = v_l.combo_line_id);
      end if;
      if v_l.qty_removed > 0 then raise exception 'Order % line % already has a removed quantity — nothing was saved', v_so.so_number, v_l.line_no; end if;
      v_qty := case when (x->>'qty') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (x->>'qty')::numeric else null end;
      if v_qty is null or v_qty <= 0 then raise exception 'Order % line %: removed qty must be a positive number — nothing was saved', v_so.so_number, v_l.line_no; end if;
      if v_qty > v_l.qty_ordered then raise exception 'Order % line %: cannot remove % — only % ordered — nothing was saved', v_so.so_number, v_l.line_no, v_qty, v_l.qty_ordered; end if;
      v_reason := nullif(trim(x->>'reason'), '');
      if v_reason is null or v_reason <> all (c_reasons) then
        raise exception 'Order % line %: removed reason must be one of customer_removed, not_wanted, other — nothing was saved', v_so.so_number, v_l.line_no;
      end if;
      if v_reason = 'other' and nullif(trim(x->>'note'), '') is null then
        raise exception 'Order % line %: reason other needs a note — nothing was saved', v_so.so_number, v_l.line_no;
      end if;
    end loop;
    if (select count(*) - count(distinct t->>'line_id') from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t) > 0 then
      raise exception 'Order %: the same line is removed twice — nothing was saved', v_so.so_number;
    end if;
    -- asm-2b2(묶음 3): 뺀 몫을 펼친다 — 콤보 줄 removed n ⇒ 구성품 줄 removed = n × combo_qty(같은 사유 · 메모 · derived true) · 아래 검사 · ③ · ④ 가 전부 이 목록(v_rm)을 본다
    select coalesce(jsonb_agg(jsonb_build_object('line_id', z.line_id, 'qty', z.qty, 'reason', z.reason, 'note', z.note, 'derived', z.derived)), '[]'::jsonb) into v_rm
    from (select (t2->>'line_id')::uuid as line_id, (t2->>'qty')::numeric as qty, nullif(trim(t2->>'reason'), '') as reason, nullif(trim(t2->>'note'), '') as note, false as derived
            from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t2
          union all
          select cp.id, (t2->>'qty')::numeric * cp.combo_qty, nullif(trim(t2->>'reason'), ''), nullif(trim(t2->>'note'), ''), true
            from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t2 join public.so_line cp on cp.combo_line_id = (t2->>'line_id')::uuid) z;
    -- 판정 9 — 모든 줄을 다 뺐다 → 거부 + 길
    if not exists (select 1 from public.so_line l
                   left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_rm) t where (t->>'line_id')::uuid = l.id) rm on true
                   where l.so_id = v_so.id and l.qty_ordered - coalesce(rm.q, 0) > 0) then
      raise exception 'Order % — every line was removed, there is nothing to ship: roll the order back in WMS, then cancel it (so_unconfirm / so_cancel) — nothing was saved', v_so.so_number;
    end if;
    -- 픽 — 모양 · 줄 · 수량 · 목표 초과(칸은 실행 때 so_ship 이 본다)
    if e->'picks' is null or jsonb_typeof(e->'picks') <> 'array' or jsonb_array_length(e->'picks') = 0 then
      raise exception 'Order %: picks must be a JSON array of {line_id, bin, qty} — nothing was saved', v_so.so_number;
    end if;
    if exists (select 1 from jsonb_array_elements(e->'picks') t where nullif(t->>'line_id', '') is null or (t->>'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' or (t->>'qty')::numeric <= 0) then
      raise exception 'Order %: every pick needs a line_id and a positive qty — nothing was saved', v_so.so_number;
    end if;
    select string_agg(distinct t->>'line_id', ', ') into v_bad from jsonb_array_elements(e->'picks') t
    where not exists (select 1 from public.so_line l where l.id = (t->>'line_id')::uuid and l.so_id = v_so.id);
    if v_bad is not null then raise exception 'Order %: pick line % is not on this order — nothing was saved', v_so.so_number, v_bad; end if;
    select string_agg(distinct l.line_no::text, ', ') into v_bad from jsonb_array_elements(e->'picks') t join public.so_line l on l.id = (t->>'line_id')::uuid
    where l.so_id = v_so.id and exists (select 1 from public.so_line cp where cp.combo_line_id = l.id);                                           -- asm-2b2: 콤보 줄에는 픽이 없다(so_ship 과 같은 문장 · 미리 보기에서도 걸린다)
    if v_bad is not null then raise exception 'Order %: pick line % is a combo line — pick its component lines instead — nothing was saved', v_so.so_number, v_bad; end if;
    -- asm-2b2(판정 246 · 묶음 4): 콤보 줄마다 whole = least(남은 콤보 수, min(구성품 픽 ÷ combo_qty)) · 어느 구성품 픽이 whole × combo_qty 를 넘으면 넘는 몫을 그 줄 picks 의 마지막 칸부터 덜어낸다(wms_so_handoff 의 cut 모양)
    --   덜어낸 것은 put_back(SKU · 칸 · 수량 — 실물만 제자리에 · 장부는 출고 때 빠지므로 닿지 않는다) · 줄인 picks 를 so_ship 에 넘긴다(so_ship 의 반쪽 거부는 안전망으로 그대로) · 보통 줄의 과다 픽은 아래에서 여전히 거부
    v_pk := e->'picks';  v_pb := '[]'::jsonb;
    for cb in
      select p2.id, p2.line_no, p2.sku,
             least(p2.qty_ordered - coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(v_rm) t2 where (t2->>'line_id')::uuid = p2.id), 0),
                   (select min(floor(coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(v_pk) t2 where (t2->>'line_id')::uuid = cp.id), 0) / cp.combo_qty)) from public.so_line cp where cp.combo_line_id = p2.id)) as whole
      from public.so_line p2 where p2.so_id = v_so.id and exists (select 1 from public.so_line cp where cp.combo_line_id = p2.id) order by p2.line_no
    loop
      for kk in select cp.id, cp.sku, cp.combo_qty from public.so_line cp where cp.combo_line_id = cb.id order by cp.line_no loop
        v_cut := coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(v_pk) t2 where (t2->>'line_id')::uuid = kk.id), 0) - greatest(cb.whole, 0) * kk.combo_qty;
        i := jsonb_array_length(v_pk) - 1;
        while v_cut > 0 and i >= 0 loop
          if (v_pk->i->>'line_id')::uuid = kk.id and (v_pk->i->>'qty')::numeric > 0 then
            v_qty := least(v_cut, (v_pk->i->>'qty')::numeric);
            v_pb := v_pb || jsonb_build_object('so_number', v_so.so_number, 'combo_sku', cb.sku, 'combo_line_no', cb.line_no, 'line_id', kk.id, 'sku', kk.sku, 'bin', coalesce(v_pk->i->>'bin', ''), 'qty', v_qty);
            v_pk := jsonb_set(v_pk, array[i::text, 'qty'], to_jsonb((v_pk->i->>'qty')::numeric - v_qty));
            v_cut := v_cut - v_qty;
          end if;
          i := i - 1;
        end loop;
      end loop;
    end loop;
    select coalesce(jsonb_agg(t2), '[]'::jsonb) into v_pk from jsonb_array_elements(v_pk) t2 where (t2->>'qty')::numeric > 0;                     -- 0 이 된 픽은 뺀다(so_ship 은 양수만 받는다)
    v_put_back := v_put_back || v_pb;
    p_orders := jsonb_set(jsonb_set(jsonb_set(p_orders, array[v_ord::text, 'picks'], v_pk), array[v_ord::text, 'removed_expanded'], v_rm), array[v_ord::text, 'put_back'], v_pb);
    select string_agg(format('line %s picked %s but %s to ship', l.line_no, pk.q, l.qty_ordered - coalesce(rm.q, 0)), '; ' order by l.line_no) into v_bad
    from public.so_line l
    join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_pk) t where (t->>'line_id')::uuid = l.id) pk on true
    left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_rm) t where (t->>'line_id')::uuid = l.id) rm on true
    where l.so_id = v_so.id and l.combo_line_id is null and pk.q > l.qty_ordered - coalesce(rm.q, 0);                                           -- asm-2b2: 구성품 줄은 위에서 줄였다 · 보통 줄은 그대로 거부
    if v_bad is not null then raise exception 'Order %: over-pick — % — over-pick goes back to its bin — nothing was saved', v_so.so_number, v_bad; end if;
    -- 운송사 · 송장(ful-1a 판정 436 · 437 · 452 · 미룬 208): 표에서만 — carrier_id(새 화면) 또는 carrier 글자 = 표의 이름(옛 화면 · 대소문자 · 앞뒤 공백 무시) · 열쇠가 없으면 오더의 carrier_id 그대로(손님 기본) · '' 이면 비움
    --   계보가 Shopify 에 닿으면 운송사 필수 · 고른 운송사는 켜져 있어야 · carrier 면 송장 필수(모든 SO · 쉼표 · 줄바꿈으로 나눠 빈 조각을 뺀 뒤) · pickup · delivery 면 송장 없음
    --   Shopify 배송 방식 PICK_UP 오더에 carrier 는 막는다(미룬 209 — 픽업 FO 에 송장 있는 fulfillmentCreate 가 되는지 못 봤다 · Shopify 에서 배송 방식을 먼저 바꾼다)
    v_car := null;
    if nullif(e->>'carrier_id', '') is not null then
      select * into v_car from public.ref_carrier rc where rc.id = (e->>'carrier_id')::uuid;
      if not found then raise exception 'Order %: carrier % is not on the carrier list — nothing was saved', v_so.so_number, e->>'carrier_id'; end if;
    elsif e ? 'carrier' and nullif(trim(e->>'carrier'), '') is not null then
      select * into v_car from public.ref_carrier rc where lower(rc.name) = lower(trim(e->>'carrier')) order by rc.is_active desc, rc.name limit 1;
      if not found then raise exception 'Order %: carrier "%" is not on the carrier list — pick one from the list (Pickup and Delivery are on it too) — nothing was saved', v_so.so_number, trim(e->>'carrier'); end if;
    elsif not (e ? 'carrier') and v_so.carrier_id is not null then
      select * into v_car from public.ref_carrier rc where rc.id = v_so.carrier_id;
    end if;
    if v_car.id is not null and not v_car.is_active then raise exception 'Order %: carrier % is switched off — pick an active carrier — nothing was saved', v_so.so_number, v_car.name; end if;
    v_web := exists (select 1 from public.shop_fulfill_web_orders(v_so.id));
    if v_web and v_car.id is null then raise exception 'Order % came from Shopify — choose a carrier (or Pickup / Delivery) before Ship & invoice — nothing was saved', v_so.so_number; end if;
    v_trk := public.shop_tracking_split(case when e ? 'tracking_number' then e->>'tracking_number' else v_so.tracking_number end);
    if v_car.kind = 'carrier' and coalesce(array_length(v_trk, 1), 0) = 0 then
      raise exception 'Order %: % needs a tracking number — enter it before Ship & invoice (several: separate with commas or new lines) — nothing was saved', v_so.so_number, v_car.name;
    end if;
    if v_car.kind in ('pickup', 'delivery') then v_trk := '{}'::text[]; end if;
    if v_car.kind = 'carrier' and v_web then
      select string_agg(w.name, ', ' order by w.name) into v_pick from public.shop_fulfill_web_orders(v_so.id) w
       where exists (select 1 from jsonb_array_elements(coalesce(w.raw->'fulfillmentOrders'->'nodes', '[]'::jsonb)) fo where fo->'deliveryMethod'->>'methodType' = 'PICK_UP');
      if v_pick is not null then raise exception 'Order %: Shopify order % is a pickup order — change its delivery method in Shopify first, or pick Pickup here — nothing was saved', v_so.so_number, v_pick; end if;
    end if;
    p_orders := jsonb_set(jsonb_set(jsonb_set(jsonb_set(p_orders, array[v_ord::text, '_carrier_id'], coalesce(to_jsonb(v_car.id::text), 'null'::jsonb)),
                          array[v_ord::text, '_carrier_touch'], to_jsonb(e ? 'carrier_id' or e ? 'carrier')),
                          array[v_ord::text, '_tracking_touch'], to_jsonb(e ? 'tracking_number' or v_car.id is not null)),
                          array[v_ord::text, '_tracking'], to_jsonb(v_trk));                                                                      -- ② 가 읽는다(①에서 푼 값 · 미리 보기도 같은 검사)
    -- 운임(판정 4 · so_charge_set 의 규칙)
    if e ? 'charges' and jsonb_typeof(e->'charges') not in ('array', 'null') then
      raise exception 'Order %: charges must be an array of {charge_id, name, amount, description, account_id} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'charges', 'null'::jsonb), '[]'::jsonb)) t loop
      if nullif(trim(x->>'name'), '') is null then raise exception 'Order %: a charge needs a name — nothing was saved', v_so.so_number; end if;
      if (x->>'amount') !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then raise exception 'Order %: charge % needs an amount — nothing was saved', v_so.so_number, trim(x->>'name'); end if;
      if (x->>'amount')::numeric < 0 then raise exception 'Order %: a charge cannot be negative — use a credit note — nothing was saved', v_so.so_number; end if;
      if nullif(x->>'charge_id', '') is not null and not exists (select 1 from public.so_charge c where c.id = (x->>'charge_id')::uuid and c.so_id = v_so.id) then
        raise exception 'Order %: charge % is not on this order — nothing was saved', v_so.so_number, x->>'charge_id';
      end if;
      if (x ? 'discount_pct' and nullif(x->>'discount_pct', '') is not null and (x->>'discount_pct') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$')
         or (x ? 'discount_amount' and nullif(x->>'discount_amount', '') is not null and (x->>'discount_amount') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$') then
        raise exception 'Order %: charge % discount needs a number — nothing was saved', v_so.so_number, trim(x->>'name');                       -- fr-1 판정 356
      end if;
      select * into v_ch from public.so_charge c where c.id = nullif(x->>'charge_id', '')::uuid;                                                   -- fr-1: 기존 줄의 할인(열쇠 없으면 그대로) · 새 줄이면 빈 행
      begin
        perform public.so_charge_discount_check((x->>'amount')::numeric,
                                                case when x ? 'discount_pct'    then nullif(x->>'discount_pct', '')::numeric    else v_ch.discount_pct    end,
                                                case when x ? 'discount_amount' then nullif(x->>'discount_amount', '')::numeric else v_ch.discount_amount end);   -- fr-1 판정 356: 한 곳의 검사 — 운임을 줄여 금액형 할인이 더 커져도 여기서 막힌다
      exception when others then
        raise exception 'Order %: charge %: %', v_so.so_number, trim(x->>'name'), sqlerrm;
      end;
      if nullif(x->>'account_id', '') is not null and not exists (select 1 from public.ref_account a where a.id = (x->>'account_id')::uuid) then
        raise exception 'Order %: account % not found — nothing was saved', v_so.so_number, x->>'account_id';
      end if;
    end loop;
    -- 부가 요금(판정 230 · surcharge-2a) — 운임과 같은 자리 · 모양 · 줄 · 짝·범위·무상(so_surcharge_check · so_line_update 와 한 곳) · 중복
    if e ? 'surcharges' and jsonb_typeof(e->'surcharges') not in ('array', 'null') then
      raise exception 'Order %: surcharges must be an array of {line_id, surcharge_pct, surcharge_amount, surcharge_label} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = nullif(x->>'line_id', '')::uuid and l.so_id = v_so.id;
      if not found then raise exception 'Order %: surcharge line % is not on this order — nothing was saved', v_so.so_number, coalesce(x->>'line_id', '?'); end if;
      v_spct := case when x ? 'surcharge_pct'    then nullif(x->>'surcharge_pct', '')::numeric    else v_l.surcharge_pct end;
      v_samt := case when x ? 'surcharge_amount' then nullif(x->>'surcharge_amount', '')::numeric else v_l.surcharge_amount end;
      v_slbl := case when x ? 'surcharge_label'  then nullif(trim(x->>'surcharge_label'), '')     else v_l.surcharge_label end;
      perform public.so_surcharge_check(v_spct, v_samt, v_slbl, v_l.free_reason);
    end loop;
    if (select count(*) - count(distinct t->>'line_id') from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t) > 0 then
      raise exception 'Order %: the same line has two surcharge changes — nothing was saved', v_so.so_number;
    end if;
  end loop;

  -- ②~⑤ 오더마다(주어진 순서) — 실행이면 쓰고 미리 보기면 계산만
  for e in select t from jsonb_array_elements(p_orders) t loop
    select * into v_so from public.so s where s.id = (e->>'so_id')::uuid;
    v_removed := '[]'::jsonb;  v_repriced := '[]'::jsonb;  v_charges := '[]'::jsonb;
    v_surcharges := '[]'::jsonb;                                                       -- surcharge-2a
    v_rm := coalesce(e->'removed_expanded', '[]'::jsonb);                               -- asm-2b2: ① 이 펼친 뺀 몫(구성품 derived 포함) · e->'picks' 는 줄인 picks

    -- ② 택배사 · 추적번호 · 배송 메모(열쇠가 온 것만) · 운임 줄(새로 · 또는 charge_id 로 고침 · 세금은 오더 규칙 · 기본 계정 _99_)
    if p_commit then                                                                                                                               -- ful-1a: 운송사 · 송장은 ① 이 푼 값(_carrier_id · _carrier_touch · _tracking · _tracking_touch)으로 · 메모는 열쇠가 온 것만
      update public.so s set
        carrier_id      = case when (e->>'_carrier_touch')::boolean  then nullif(e->>'_carrier_id', '')::uuid else s.carrier_id end,
        carrier         = case when (e->>'_carrier_touch')::boolean  then (select rc.name from public.ref_carrier rc where rc.id = nullif(e->>'_carrier_id', '')::uuid) else s.carrier end,
        tracking_number = case when (e->>'_tracking_touch')::boolean then nullif(array_to_string(array(select jsonb_array_elements_text(e->'_tracking')), ', '), '') else s.tracking_number end,
        shipping_notes  = case when e ? 'shipping_notes'  then nullif(trim(e->>'shipping_notes'), '')  else s.shipping_notes end,
        updated_by      = v_staff
      where s.id = v_so.id;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'charges', 'null'::jsonb), '[]'::jsonb)) t loop
      v_acct := null;
      if nullif(x->>'account_id', '') is not null then
        select * into v_acct from public.ref_account a where a.id = (x->>'account_id')::uuid;
      elsif nullif(x->>'charge_id', '') is null then
        select * into v_acct from public.ref_account a where a.code = '_99_';                      -- 기본 Freight Sales · 없으면 비우고 알린다(so_charge_set 과 같다)
        if not found then v_warn := array_append(v_warn, 'charge_account_unset:' || v_so.so_number); end if;
      end if;
      select * into v_ch from public.so_charge c where c.id = nullif(x->>'charge_id', '')::uuid;                                                   -- fr-1: 할인 — 열쇠 없으면 기존 그대로 · '' 이면 지움 · 새 줄이면 없음
      v_dp := case when x ? 'discount_pct'    then nullif(x->>'discount_pct', '')::numeric    else v_ch.discount_pct    end;
      v_da := case when x ? 'discount_amount' then nullif(x->>'discount_amount', '')::numeric else v_ch.discount_amount end;
      if nullif(x->>'charge_id', '') is null and exists (select 1 from public.so_charge c where c.so_id = v_so.id) and not (('charge_added_beside_existing:' || v_so.so_number) = any(v_warn)) then
        v_warn := array_append(v_warn, 'charge_added_beside_existing:' || v_so.so_number);                                                       -- fr-1(freight-0 틈): 운임이 이미 있는데 charge_id 없는 새 운임 — 막지 않고 알린다(견적 줄을 고치는 길은 charge_id)
      end if;
      if p_commit then
        if nullif(x->>'charge_id', '') is null then
          select coalesce(max(c.line_no), 0) + 1 into v_next from public.so_charge c where c.so_id = v_so.id;
          insert into public.so_charge (so_id, line_no, name, description, amount, tax_rule, account_id, account_code, updated_by, discount_pct, discount_amount)
          values (v_so.id, v_next, trim(x->>'name'), nullif(trim(x->>'description'), ''), (x->>'amount')::numeric, v_so.tax_rule, v_acct.id, v_acct.code, v_staff, v_dp, v_da)   -- fr-1
          returning * into v_ch;
        else
          update public.so_charge c set
            name = trim(x->>'name'), description = nullif(trim(x->>'description'), ''), amount = (x->>'amount')::numeric, tax_rule = v_so.tax_rule, discount_pct = v_dp, discount_amount = v_da,   -- fr-1
            account_id = case when v_acct.id is not null then v_acct.id else c.account_id end, account_code = case when v_acct.id is not null then v_acct.code else c.account_code end, updated_by = v_staff
          where c.id = (x->>'charge_id')::uuid returning * into v_ch;
        end if;
        v_charges := v_charges || jsonb_build_object('charge_id', v_ch.id, 'line_no', v_ch.line_no, 'name', v_ch.name, 'amount', v_ch.amount, 'tax_rule', v_ch.tax_rule, 'account_code', v_ch.account_code,
                                                     'discount_pct', v_ch.discount_pct, 'discount_amount', v_ch.discount_amount, 'discount', public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount), 'net', v_ch.amount - public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount));   -- fr-1
      else
        v_charges := v_charges || jsonb_build_object('charge_id', nullif(x->>'charge_id', ''), 'name', trim(x->>'name'), 'amount', (x->>'amount')::numeric, 'tax_rule', v_so.tax_rule, 'account_code', v_acct.code, 'preview', true,
                                                     'discount_pct', v_dp, 'discount_amount', v_da, 'discount', public.so_charge_discount((x->>'amount')::numeric, v_dp, v_da), 'net', (x->>'amount')::numeric - public.so_charge_discount((x->>'amount')::numeric, v_dp, v_da));   -- fr-1
      end if;
    end loop;

    -- ②′ 부가 요금(판정 230 · surcharge-2a) — so_line_update 와 같은 패치 모양(열쇠가 온 칸만 · '' 은 비움) · 실행이면 쓰고 미리 보기면 old → new 만 · ③ 다시 견적 앞(%형은 저장값이 아니라 계산 때 단가를 읽는다)
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = (x->>'line_id')::uuid;
      v_spct := case when x ? 'surcharge_pct'    then nullif(x->>'surcharge_pct', '')::numeric    else v_l.surcharge_pct end;
      v_samt := case when x ? 'surcharge_amount' then nullif(x->>'surcharge_amount', '')::numeric else v_l.surcharge_amount end;
      v_slbl := case when x ? 'surcharge_label'  then nullif(trim(x->>'surcharge_label'), '')     else v_l.surcharge_label end;
      if p_commit then
        update public.so_line set surcharge_pct = v_spct, surcharge_amount = v_samt, surcharge_label = v_slbl, updated_by = v_staff where id = v_l.id;
      end if;
      v_surcharges := v_surcharges || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku,
                                                         'old', jsonb_build_object('surcharge_pct', v_l.surcharge_pct, 'surcharge_amount', v_l.surcharge_amount, 'surcharge_label', v_l.surcharge_label),
                                                         'new', jsonb_build_object('surcharge_pct', v_spct, 'surcharge_amount', v_samt, 'surcharge_label', v_slbl),
                                                         'surcharge_unit', public.so_line_surcharge_unit(v_l.unit_price, v_spct, v_samt));
      if v_spct is not null and v_spct > 100 then v_warn := array_append(v_warn, 'surcharge_pct_over_100:' || v_so.so_number || ':' || v_l.line_no); end if;
    end loop;

    -- ③ 뺀 몫(판정 5) + 시스템 줄 다시 견적(판정 6 · 할인만 · 남은 수량 > 0 · 사람이 정한 줄은 그대로)
    for x in select t from jsonb_array_elements(v_rm) t loop
      select * into v_l from public.so_line l where l.id = (x->>'line_id')::uuid;
      v_qty := (x->>'qty')::numeric;  v_remaining := v_l.qty_ordered - v_qty;
      if p_commit then
        update public.so_line set qty_removed = v_qty, removed_reason = nullif(trim(x->>'reason'), ''), removed_note = nullif(trim(x->>'note'), ''), removed_at = now(), removed_by = v_staff, updated_by = v_staff
        where id = v_l.id;
      end if;
      v_removed := v_removed || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'qty_ordered', v_l.qty_ordered, 'qty_removed', v_qty, 'remaining', v_remaining,
                                                   'reason', nullif(trim(x->>'reason'), ''), 'free', v_l.free_reason is not null, 'derived', (x->>'derived')::boolean);
      if v_remaining > 0 and not (x->>'derived')::boolean and not v_l.price_override and v_l.discount_source is distinct from 'manual' then   -- asm-2b2: 구성품 줄은 다시 견적하지 않는다(값 0 · so_line_requote 가 거부한다)
        select * into q from public.so_line_quote(v_so, v_l.product_id, v_remaining);
        v_new_unit := case when v_l.list_price is null then null else v_l.list_price * (1 - q.discount_pct / 100) end;
        if p_commit then perform public.so_line_requote(v_l.id, v_remaining, false); end if;
        v_repriced := v_repriced || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'qty', v_remaining,
                                                       'old_unit_price', v_l.unit_price, 'new_unit_price', v_new_unit, 'old_discount_pct', v_l.discount_pct, 'new_discount_pct', q.discount_pct,
                                                       'old_discount_source', v_l.discount_source, 'new_discount_source', q.discount_source, 'changed', v_new_unit is distinct from v_l.unit_price);
      end if;
    end loop;

    -- ④ 출고(so_ship · 목표 = 주문 − 뺀 것 · 그 아래 차이만 pick_short 판정 7) — 미리 보기는 줄별 계산만(칸 검사·원장은 실행 때)
    if p_commit then
      v_ship := public.so_ship(v_so.id, e->'picks', v_staff, v_on);
      select array_agg(v_so.so_number || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_ship->'warnings', '[]'::jsonb)) as t(w);
      v_warn := v_warn || coalesce(v_tw, '{}');
      select jsonb_set(v_ship, '{lines}', coalesce(jsonb_agg(case when p2.sku is null then t2.x else t2.x || jsonb_build_object('combo_sku', p2.sku) end order by t2.ord), '[]'::jsonb)) into v_ship   -- asm-2b2: 구성품 줄에 combo_sku(콤보 줄의 combo true 는 so_ship 이 준다)
      from jsonb_array_elements(v_ship->'lines') with ordinality t2(x, ord) left join public.so_line cp on cp.id = (t2.x->>'line_id')::uuid left join public.so_line p2 on p2.id = cp.combo_line_id;
      if jsonb_array_length(coalesce(e->'put_back', '[]'::jsonb)) > 0 then                                                                           -- asm-2b2(⬜6): 되돌려 놓을 것을 창고 마무리 행에 남긴다(창고가 제자리에 놓는다 · 원장은 닿지 않는다) · 행이 없으면 반환만 + 경고
        update public.wms_order_finalize f set put_back = e->'put_back' where f.order_id = v_so.id;
        get diagnostics v_n = row_count;
        if v_n = 0 then v_warn := array_append(v_warn, 'put_back_unrecorded:' || v_so.so_number); end if;
      end if;
    else
      select jsonb_build_object('preview', true,
               'lines', coalesce(jsonb_agg((jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'ordered', l.qty_ordered, 'removed', coalesce(rm.q, 0), 'to_ship', l.qty_ordered - coalesce(rm.q, 0),
                                                              'picked', coalesce(pk.q, 0), 'short', l.qty_ordered - coalesce(rm.q, 0) - coalesce(pk.q, 0))
                                           || case when cm.is_combo then '{"combo": true}'::jsonb else '{}'::jsonb end || case when p2.sku is null then '{}'::jsonb else jsonb_build_object('combo_sku', p2.sku) end) order by l.line_no), '[]'::jsonb),   -- asm-2b2: 콤보 줄 picked = 통째 콤보 수 · 구성품 줄에 combo_sku · 보통 오더의 모양은 그대로
               'backorder_lines', count(*) filter (where l.qty_ordered - coalesce(rm.q, 0) - coalesce(pk.q, 0) > 0))
        into v_ship
      from public.so_line l
      left join public.so_line p2 on p2.id = l.combo_line_id
      cross join lateral (select exists (select 1 from public.so_line cp where cp.combo_line_id = l.id) as is_combo) cm
      left join lateral (select case when cm.is_combo then (select min(floor(coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(e->'picks') t2 where (t2->>'line_id')::uuid = cp.id), 0) / cp.combo_qty)) from public.so_line cp where cp.combo_line_id = l.id)
                                     else (select sum((t->>'qty')::numeric) from jsonb_array_elements(e->'picks') t where (t->>'line_id')::uuid = l.id) end as q) pk on true
      left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_rm) t where (t->>'line_id')::uuid = l.id) rm on true
      where l.so_id = v_so.id;
    end if;

    -- ⑤ 묶음 열쇠(판정 2) — 청구처 · 청구처 설정이 켜졌으면 오더의 손님(매장) · invoice_group 이 오면 그것(청구처 안에서 · 직원이 바꾼 묶음)
    select * into v_c from public.customer c where c.id = v_so.bill_to_customer_id;
    v_key := v_so.bill_to_customer_id::text || '|' || coalesce(nullif(trim(e->>'invoice_group'), ''), case when coalesce(v_c.invoice_split_by_store, false) then 'store:' || v_so.customer_id::text else '' end);
    v_groups := jsonb_set(v_groups, array[v_key], coalesce(v_groups->v_key, '[]'::jsonb) || to_jsonb(v_so.id));
    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'invoice_group', v_key, 'removed', v_removed, 'repriced', v_repriced, 'charges', v_charges, 'surcharges', v_surcharges, 'ship', v_ship, 'put_back', coalesce(e->'put_back', '[]'::jsonb));   -- asm-2b2: 오더마다 put_back
  end loop;

  -- ⑥ 발행 — 묶음마다 한 장(so_invoice_issue · 발행일 = 오늘 ims_today · §16 판정 5) · 미리 보기는 몇 장 · 어느 오더
  for k in select t.key_txt from jsonb_object_keys(v_groups) as t(key_txt) order by t.key_txt loop   -- 별칭은 변수 이름(x · e · k)과 다르게
    select array_agg(t.v::uuid) into v_ids from jsonb_array_elements_text(v_groups->k) as t(v);
    if p_commit then
      v_iss := public.so_invoice_issue(v_ids, v_staff, null);
      select array_agg((v_iss->>'invoice_number') || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_iss->'warnings', '[]'::jsonb)) as t(w);
      v_warn := v_warn || coalesce(v_tw, '{}');
      v_invoices := v_invoices || jsonb_build_object('group', k, 'invoice_id', v_iss->'invoice_id', 'invoice_number', v_iss->'invoice_number', 'issued_on', v_iss->'issued_on', 'due_on', v_iss->'due_on',
                                                     'orders', (select jsonb_agg(o->>'so_number') from jsonb_array_elements(v_iss->'orders') o), 'totals', v_iss->'totals', 'warnings', v_iss->'warnings');
    else
      v_invoices := v_invoices || jsonb_build_object('group', k, 'preview', true, 'orders', (select jsonb_agg(s.so_number order by s.so_number) from public.so s where s.id = any(v_ids)), 'order_count', array_length(v_ids, 1));
    end if;
  end loop;

  return jsonb_build_object('committed', p_commit, 'shipped_on', v_on, 'orders', v_orders, 'invoices', v_invoices, 'invoice_count', jsonb_array_length(v_invoices), 'put_back', v_put_back, 'warnings', to_jsonb(v_warn));   -- asm-2b2(판정 246): put_back — 미리 보기 · 실행 둘 다 · 화면이 「Put back」 목록으로 그린다
end;
$$;

comment on function public.so_finalize(jsonb, boolean, date) is 'ⓐ Ship & invoice(판정 382) — packed 오더들을 한 번에: 뺀 몫 · 운임 · 부가 요금 · 운송사 · 송장 → so_ship(출고 · 원장 · 형제) → so_invoice_issue(묶음마다 한 장) · 미리 보기 p_commit false · ⭐ [ful-1a 판정 436 · 437 · 452] 운송사는 ref_carrier 에서만(carrier_id · 또는 글자 = 표 이름) · 계보가 Shopify 에 닿으면 필수 · carrier 면 송장 필수(쉼표 · 줄바꿈 여럿) · pickup · delivery 면 송장을 비운다 · Shopify PICK_UP 오더에 carrier 는 거절(미룬 209) · 출고 순간 so_ship 이 shop_fulfill_enqueue 로 발송 큐 · 결과 표를 만든다';
