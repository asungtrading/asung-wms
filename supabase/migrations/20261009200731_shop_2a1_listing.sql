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

-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- shop-2a1 — Shopify 연동 ② 상품 보내기 · DB 앞 절반 (2026-10-09 · 판정 403 ~ 411 · shop-2-0 회신 ⬜1 · ⬜2 · ⬜6 · 정본 docs/design/shopify-integration.md §3)
--   ① shop_store.send_tags(판정 410 · 기본 false) ② product_family.web_image_id(웹 대표 사진 · 쓰기는 2a2 창구) ③ 표 다섯 shop_listing · shop_product · shop_variant · shop_media · shop_push_queue
--   ④ 보낼 내용 함수 shop_product_payload(store, family | product) → jsonb(원문 설명 · 거르기는 EF · 지문 md5) ⑤ 뷰 shop_listing_list
--   2a2 로 미룬 것(크기 900 경계): 창구 shop_listing_set · 큐 트리거 *_shop_queue · 새벽 함수 shop_queue_all · web_image_id 쓰기
--   ⭐ 다섯 표 모두 authenticated select 만(revoke all + grant select · shop-1a 모양) · 쓰기는 창구(2a2) 와 EF(service_role · 2b)
--   적용: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f <이 파일> && supabase migration repair --status applied <버전> --db-url "$(cat ~/.asung-testdb-url)"
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ═══ 1) shop_store.send_tags — 판정 410: Cin7 태그를 IMS 로 적재하기 전에는 tags 칸을 보내지 않는다 · 켜기는 SQL 로(store_set 은 2a2 에서 받을지 판단) ═══
alter table public.shop_store add column if not exists send_tags boolean not null default false;
comment on column public.shop_store.send_tags is 'shop-2a1 판정 410: true 면 productSet 에 tags(IMS product_tag)를 보낸다 · 기본 false — IMS product_tag 가 0 행이라(Cin7 태그 1,245 종 적재 전) 보내면 Shopify 태그가 지워진다 · 적재 뒤 SQL 한 줄로 켠다(update shop_store set send_tags = true where code = …)';

-- ═══ 2) product_family.web_image_id — 웹 대표 사진(설계 §3-b · 없으면 첫 변형의 대표 사진) · 구성원 사진만 · 쓰기는 2a2 창구(family_head_set 또는 shop_listing_set) ═══
alter table public.product_family add column if not exists web_image_id uuid references public.product_image (id) on delete no action;
create index if not exists product_family_web_image_id_idx on public.product_family (web_image_id);
comment on column public.product_family.web_image_id is 'shop-2a1 설계 §3-b: Shopify 상품의 대표 사진(product_image · 이 family 구성원의 사진만 — 2a2 창구가 막는다) · null = 첫 변형(sku 순)의 대표 사진 · shop_product_payload.files 의 첫 장';

-- ═══ 3) 표 다섯 ═══
-- 3-a shop_listing — 「이 스토어로 보냄」 표시(설계 §3-c · 판정 404 · 405) · 대상은 family 또는 낱개(둘 중 하나)
create table public.shop_listing (
  id             uuid primary key default gen_random_uuid(),
  store_id       uuid not null references public.shop_store (id) on delete no action,
  family_id      uuid references public.product_family (id) on delete no action,
  product_id     uuid references public.product (id) on delete no action,                   -- 낱개(family 없음) 또는 sellable 세트(판정 404) · family 구성원은 family 로만
  is_on          boolean not null default true,
  turned_on_at   timestamptz not null default now(),
  turned_on_by   uuid references public.ims_staff (id) on delete no action,
  turned_off_at  timestamptz,
  turned_off_by  uuid references public.ims_staff (id) on delete no action,
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.ims_staff (id) on delete no action,
  constraint shop_listing_target_ck     check ((family_id is null) <> (product_id is null)),
  constraint shop_listing_off_pair_ck   check (is_on or turned_off_at is not null),
  constraint shop_listing_store_fam_uk  unique (store_id, family_id),
  constraint shop_listing_store_prod_uk unique (store_id, product_id)
);
create index shop_listing_family_id_idx  on public.shop_listing (family_id);
create index shop_listing_product_id_idx on public.shop_listing (product_id);
create index shop_listing_updated_by_idx on public.shop_listing (updated_by);
create trigger shop_listing_touch before update on public.shop_listing for each row execute function public.ims_touch();
comment on table public.shop_listing is 'shop-2a1 설계 §3-c · 판정 404 · 405: 스토어별 「이 스토어로 보냄」 — family 하나 또는 낱개 하나(둘 중 하나 · family 구성원은 family 로만 · 세트는 sellable 세트만) · is_on false = Shopify 상품 ARCHIVED(지우지 않는다) · 쓰기는 shop_listing_set(2a2 · 문 shopify) 만';

-- 3-b shop_product — Shopify 상품 대응(대상 하나 = Shopify 상품 하나) · 지문 · 마지막 결과
create table public.shop_product (
  id                   uuid primary key default gen_random_uuid(),
  store_id             uuid not null references public.shop_store (id) on delete no action,
  family_id            uuid references public.product_family (id) on delete no action,
  product_id           uuid references public.product (id) on delete no action,
  shopify_product_gid  text not null,                                                        -- gid://shopify/Product/<숫자>
  handle               text,                                                                 -- Shopify 가 정한다(IMS 가 안 정한다) · 기록만
  shopify_status       text,                                                                 -- 마지막으로 보낸 status(ACTIVE | ARCHIVED | DRAFT)
  last_hash            text,                                                                 -- 마지막으로 보낸 payload 의 md5 · 같으면 안 보낸다
  last_pushed_at       timestamptz,
  last_status          text,                                                                 -- ok · error · pending
  last_error           text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  updated_by           uuid references public.ims_staff (id) on delete no action,
  constraint shop_product_target_ck    check ((family_id is null) <> (product_id is null)),
  constraint shop_product_gid_ck       check (shopify_product_gid ~ '^gid://shopify/Product/[0-9]+$'),
  constraint shop_product_status_ck    check (last_status is null or last_status in ('ok', 'error', 'pending')),
  constraint shop_product_store_fam_uk  unique (store_id, family_id),
  constraint shop_product_store_prod_uk unique (store_id, product_id),
  constraint shop_product_store_gid_uk  unique (store_id, shopify_product_gid)
);
create index shop_product_family_id_idx  on public.shop_product (family_id);
create index shop_product_product_id_idx on public.shop_product (product_id);
create index shop_product_updated_by_idx on public.shop_product (updated_by);
create trigger shop_product_touch before update on public.shop_product for each row execute function public.ims_touch();
comment on table public.shop_product is 'shop-2a1: IMS 대상(family | 낱개) ↔ Shopify 상품 GID · handle(Shopify 가 정함) · last_hash(payload md5 · 같으면 안 보냄) · last_status ok | error | pending · 컷오버 잇기(link_by_sku · ⑦)는 이 표에 GID 를 먼저 적는다 · 쓰기는 EF(service_role) 만';

-- 3-c shop_variant — 변형 대응(③ 재고 올리기가 inventory_item_gid 를 쓴다)
create table public.shop_variant (
  id                   uuid primary key default gen_random_uuid(),
  store_id             uuid not null references public.shop_store (id) on delete no action,
  product_id           uuid not null references public.product (id) on delete no action,
  shopify_variant_gid  text not null,
  inventory_item_gid   text,
  last_hash            text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  updated_by           uuid references public.ims_staff (id) on delete no action,
  constraint shop_variant_gid_ck        check (shopify_variant_gid ~ '^gid://shopify/ProductVariant/[0-9]+$'),
  constraint shop_variant_inv_ck        check (inventory_item_gid is null or inventory_item_gid ~ '^gid://shopify/InventoryItem/[0-9]+$'),
  constraint shop_variant_store_prod_uk unique (store_id, product_id),
  constraint shop_variant_store_gid_uk  unique (store_id, shopify_variant_gid)
);
create index shop_variant_product_id_idx on public.shop_variant (product_id);
create index shop_variant_updated_by_idx on public.shop_variant (updated_by);
create trigger shop_variant_touch before update on public.shop_variant for each row execute function public.ims_touch();
comment on table public.shop_variant is 'shop-2a1: IMS 상품(변형) ↔ Shopify 변형 GID · inventory_item_gid(③ 재고 올리기 · ⑤ 발송이 쓴다) · 쓰기는 EF(service_role) 만';

-- 3-d shop_media — 사진 대응(두 번째부터 Shopify file id 로 보내 쌓임을 막는다 · 판정 409)
create table public.shop_media (
  id                uuid primary key default gen_random_uuid(),
  store_id          uuid not null references public.shop_store (id) on delete no action,
  product_image_id  uuid not null references public.product_image (id) on delete no action,
  shopify_file_gid  text not null,
  last_pushed_at    timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  updated_by        uuid references public.ims_staff (id) on delete no action,
  constraint shop_media_gid_ck         check (shopify_file_gid ~ '^gid://shopify/(MediaImage|GenericFile|Video)/[0-9]+$'),
  constraint shop_media_store_img_uk   unique (store_id, product_image_id),
  constraint shop_media_store_gid_uk   unique (store_id, shopify_file_gid)
);
create index shop_media_product_image_id_idx on public.shop_media (product_image_id);
create index shop_media_updated_by_idx       on public.shop_media (updated_by);
create trigger shop_media_touch before update on public.shop_media for each row execute function public.ims_touch();
comment on table public.shop_media is 'shop-2a1 판정 409: product_image ↔ Shopify 파일 GID — 처음은 originalSource(공개 URL)로 올리고 돌아온 id 를 적는다 · 두 번째부터 FileSetInput.id 로(같은 사진이 쌓이지 않게) · 쓰기는 EF(service_role) 만';

-- 3-e shop_push_queue — 바뀜 큐(넣는 트리거 · 새벽 함수는 2a2 · 비우는 EF drain 은 2b)
create table public.shop_push_queue (
  id          bigint generated always as identity primary key,
  store_id    uuid not null references public.shop_store (id) on delete no action,
  family_id   uuid references public.product_family (id) on delete no action,
  product_id  uuid references public.product (id) on delete no action,
  reason      text not null,                                                                 -- 어느 표 · 누가(manual · nightly · product · product_price …)
  queued_at   timestamptz not null default now(),
  started_at  timestamptz,
  done_at     timestamptz,
  result      text,                                                                          -- ok · skipped_same_hash · error
  error       text,
  constraint shop_push_queue_target_ck check ((family_id is null) <> (product_id is null)),
  constraint shop_push_queue_result_ck check (result is null or result in ('ok', 'skipped_same_hash', 'error')),
  constraint shop_push_queue_done_ck   check ((done_at is null) = (result is null))
);
create index shop_push_queue_open_idx    on public.shop_push_queue (store_id, queued_at) where done_at is null;   -- 열린 줄 찾기(유니크 아님 · 규칙 29 는 유니크 부분 인덱스만 금지)
create index shop_push_queue_family_idx  on public.shop_push_queue (family_id);
create index shop_push_queue_product_idx on public.shop_push_queue (product_id);
comment on table public.shop_push_queue is 'shop-2a1 설계 §3-e: 「보낼 것 있음」 한 줄 = 대상 하나(family | 낱개) · 열린 줄(done_at null)은 대상마다 하나(넣는 쪽이 not exists 로 지킨다 · 부분 유니크 금지 규칙 29) · result ok | skipped_same_hash | error · 넣기 = 트리거 *_shop_queue · shop_queue_all(2a2) · push_now · 비우기 = EF drain(2b · cron 1 분)';

-- 권한 — 다섯 표 모두 authenticated select 만(기본 references · trigger 까지 거둔다 · shop-1a 1회차 T1c) · anon 없음
do $$ declare t text; begin
  foreach t in array array['shop_listing', 'shop_product', 'shop_variant', 'shop_media', 'shop_push_queue'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- ═══ 4) 보낼 내용 함수 — shop_product_payload(store, family | product) → jsonb · 원문 설명(거르기는 EF · 판정 402) · 지문 md5 ═══
-- 가격 — 티어 purpose 를 가리지 않는다(판정 403 고침: Compare-at 은 sale 또는 compare) · so_price_for 와 같은 식(자기 줄 → 세트 계산 낱개 × 계수 × (1 − 세트 할인%)) · so_price_for 는 무접촉
create function public.shop_tier_price(p_product_id uuid, p_tier_id uuid) returns numeric
  language sql stable
  set search_path = public, pg_temp
as $$
  select coalesce(
    (select pp.price from public.product_price pp where pp.product_id = p_product_id and pp.tier_id = p_tier_id and pp.is_active),
    (select round(pp.price * p.pack_factor * (1 - coalesce(p.set_discount_pct, 0) / 100), 2)
       from public.product p join public.product_price pp on pp.product_id = p.parent_product_id and pp.tier_id = p_tier_id and pp.is_active
      where p.id = p_product_id and p.parent_product_id is not null and p.pack_factor is not null));
$$;
comment on function public.shop_tier_price(uuid, uuid) is 'shop-2a1: 상품의 티어 가격 — 자기 활성 줄 → 없으면 세트 계산(낱개 × pack_factor × (1 − set_discount_pct/100) · round 2) · so_price_for 와 같은 식이되 purpose 를 가리지 않는다(Compare-at 티어 · 판정 403 고침) · null = 가격 없음';

create function public.shop_product_payload(p_store_id uuid, p_family_id uuid default null, p_product_id uuid default null) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_s        public.shop_store%rowtype;
  v_f        public.product_family%rowtype;
  v_p        public.product%rowtype;
  v_l        public.shop_listing%rowtype;
  v_kind     text;
  v_title    text;
  v_desc     text;
  v_vendor   text;
  v_ptype    text;
  v_options  jsonb := '[]'::jsonb;
  v_variants jsonb := '[]'::jsonb;
  v_files    jsonb := '[]'::jsonb;
  v_tags     jsonb := '[]'::jsonb;
  v_blocks   jsonb := '[]'::jsonb;
  v_status   text;
  v_active   int := 0;
  v_cover    uuid;
  v_base     text := rtrim(coalesce(current_setting('app.settings.supabase_url', true), ''), '/');   -- 비어 있으면 EF 가 자기 SUPABASE_URL 로 채운다(url 은 경로만 · image_path)
  v_m        public.product%rowtype;
  v_out      jsonb;
begin
  if (p_family_id is null) = (p_product_id is null) then
    raise exception 'shop_product_payload: give exactly one of p_family_id, p_product_id';
  end if;
  select * into v_s from public.shop_store s where s.id = p_store_id;
  if v_s.id is null then raise exception 'shop_product_payload: store % not found', p_store_id; end if;

  if p_family_id is not null then
    v_kind := 'family';
    select * into v_f from public.product_family f where f.id = p_family_id;
    if v_f.id is null then raise exception 'shop_product_payload: family % not found', p_family_id; end if;
    select * into v_l from public.shop_listing l where l.store_id = p_store_id and l.family_id = p_family_id;
    v_title := v_f.name; v_desc := coalesce(v_f.description_html, v_f.cin7_description); v_vendor := v_f.brand_name; v_ptype := v_f.category_name;
    select coalesce(jsonb_agg(jsonb_build_object('name', o.n, 'values', (select coalesce(jsonb_agg(x.v order by x.first_sku), '[]'::jsonb) from (select y.v, min(y.sku) as first_sku from (select p.sku, case o.i when 1 then p.option1_value when 2 then p.option2_value else p.option3_value end as v from public.product p where p.family_id = v_f.id and p.parent_product_id is null) y where y.v is not null group by y.v) x)) order by o.i), '[]'::jsonb)
      into v_options
      from (values (1, v_f.option1_name), (2, v_f.option2_name), (3, v_f.option3_name)) as o(i, n) where o.n is not null;
    for v_m in select p.* from public.product p where p.family_id = v_f.id and p.parent_product_id is null order by p.sku loop   -- 구성원 = family 의 낱개(세트는 family 로 안 보낸다 · 판정 404)
      v_variants := v_variants || public.shop_variant_payload(v_s, v_m, v_f);
      if v_m.is_active and v_m.sellable then v_active := v_active + 1; end if;
    end loop;
    if jsonb_array_length(v_variants) = 0 then v_blocks := v_blocks || to_jsonb('no_variants'::text); end if;
    v_cover := v_f.web_image_id;
    if v_cover is null then
      select i.id into v_cover from public.product_image i join public.product p on p.id = i.product_id
       where p.family_id = v_f.id and p.parent_product_id is null and i.is_active and i.is_primary order by p.sku limit 1;
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('product_image_id', x.id, 'image_path', x.storage_path, 'url', case when v_base = '' then null else v_base || '/storage/v1/object/public/product-images/' || x.storage_path end, 'alt', x.alt, 'product_id', x.product_id) order by x.ord, x.sku, x.sort_order), '[]'::jsonb)
      into v_files
      from (select i.id, i.storage_path, i.sort_order, i.product_id, p.sku, p.name as alt,
                   case when i.id = v_cover then 0 when i.is_primary then 1 else 2 end as ord
              from public.product_image i join public.product p on p.id = i.product_id
             where p.family_id = v_f.id and p.parent_product_id is null and i.is_active) x;
    select coalesce(jsonb_agg(distinct t.tag), '[]'::jsonb) into v_tags from public.product_tag t join public.product p on p.id = t.product_id where p.family_id = v_f.id;
  else
    v_kind := 'product';
    select * into v_p from public.product p where p.id = p_product_id;
    if v_p.id is null then raise exception 'shop_product_payload: product % not found', p_product_id; end if;
    select * into v_l from public.shop_listing l where l.store_id = p_store_id and l.product_id = p_product_id;
    v_title := v_p.name; v_desc := coalesce(v_p.description_html, v_p.cin7_description); v_vendor := v_p.brand_name; v_ptype := v_p.category_name;
    if v_p.family_id is not null then v_blocks := v_blocks || to_jsonb('family_member_goes_with_family'::text); end if;   -- family 구성원은 family 로만
    if v_p.parent_product_id is not null and not v_p.sellable then v_blocks := v_blocks || to_jsonb('set_not_sellable'::text); end if;   -- 판정 404
    v_variants := v_variants || public.shop_variant_payload(v_s, v_p, null);
    if v_p.is_active and v_p.sellable then v_active := 1; end if;
    select coalesce(jsonb_agg(jsonb_build_object('product_image_id', i.id, 'image_path', i.storage_path, 'url', case when v_base = '' then null else v_base || '/storage/v1/object/public/product-images/' || i.storage_path end, 'alt', v_p.name, 'product_id', i.product_id) order by i.is_primary desc, i.sort_order), '[]'::jsonb)
      into v_files from public.product_image i where i.product_id = v_p.id and i.is_active;
    select coalesce(jsonb_agg(distinct t.tag), '[]'::jsonb) into v_tags from public.product_tag t where t.product_id = v_p.id;
  end if;

  if v_l.id is null then v_blocks := v_blocks || to_jsonb('listing_missing'::text); end if;
  select v_blocks || coalesce(jsonb_agg(to_jsonb('no_price:' || (x->>'sku'))), '[]'::jsonb) into v_blocks
    from jsonb_array_elements(v_variants) x where (x->>'inventory_policy') = 'CONTINUE' and (x->>'price') is null;   -- 켜진 변형에 Price 가 없으면 못 보낸다
  v_status := case when v_l.id is not null and v_l.is_on and v_active > 0 then 'ACTIVE' else 'ARCHIVED' end;              -- 판정 405
  v_out := jsonb_build_object(
    'kind', v_kind, 'store_code', v_s.code, 'family_id', p_family_id, 'product_id', p_product_id,
    'title', v_title, 'description_html', v_desc, 'vendor', v_vendor, 'product_type', v_ptype,
    'tags', v_tags, 'send_tags', v_s.send_tags, 'status', v_status, 'active_variants', v_active,
    'options', v_options, 'variants', v_variants, 'files', v_files,
    'listing_on', coalesce(v_l.is_on, false), 'blocks', v_blocks);
  return v_out || jsonb_build_object('hash', md5((v_out - 'blocks' - 'listing_on')::text));
end;
$$;
comment on function public.shop_product_payload(uuid, uuid, uuid) is
  'shop-2a1 설계 §3 · 판정 403 ~ 409: 스토어로 보낼 상품 한 건의 내용 — kind family | product · title · description_html(⚠️ 원문 coalesce(description_html, cin7_description) · 거르기는 EF 가 DOMPurify 로 · 판정 402) · vendor(brand_name) · product_type(category_name) · tags[](send_tags false 면 EF 가 뺀다 · 판정 410) · status ACTIVE | ARCHIVED(listing 켜짐 + 켜진 변형 ≥ 1 · 판정 405) · options[{name, values[]}] · variants[](shop_variant_payload · 꺼진 구성원도 남긴다 · 판정 406) · files[](순서 web_image_id → 변형 대표 → 나머지 · 판정 409 · url 은 app.settings.supabase_url 이 있을 때만 · image_path 는 늘) · blocks[](no_variants · family_member_goes_with_family · set_not_sellable · listing_missing · no_price:<sku>) · hash = blocks · listing_on 을 뺀 md5 · stable · 읽기만';

create function public.shop_variant_payload(p_s public.shop_store, p_p public.product, p_f public.product_family) returns jsonb
  language sql stable
  set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'product_id', p_p.id, 'sku', p_p.sku, 'name', p_p.name,
    'barcode', (select pb.barcode from public.product_barcode pb where pb.product_id = p_p.id and pb.is_active order by pb.is_primary desc, pb.barcode limit 1),
    'price', public.shop_tier_price(p_p.id, p_s.sale_tier_id),
    'compare_at_price', case when p_s.compare_tier_id is null then null else public.shop_tier_price(p_p.id, p_s.compare_tier_id) end,   -- null = 안 보냄 · 같은 값이어도 보낸다(판정 403 · 408)
    'option_values', case when p_f.id is null then '[]'::jsonb else
       (select coalesce(jsonb_agg(jsonb_build_object('name', o.n, 'value', o.v) order by o.i), '[]'::jsonb)
          from (values (1, p_f.option1_name, p_p.option1_value), (2, p_f.option2_name, p_p.option2_value), (3, p_f.option3_name, p_p.option3_value)) as o(i, n, v) where o.n is not null) end,
    'inventory_policy', case when p_p.is_active and p_p.sellable then 'CONTINUE' else 'DENY' end,   -- 판정 406 · 407
    'is_active', p_p.is_active, 'sellable', p_p.sellable,
    'image_id', (select i.id from public.product_image i where i.product_id = p_p.id and i.is_active order by i.is_primary desc, i.sort_order limit 1),
    'weight', case when coalesce(p_p.weight, 0) > 0 and p_p.weight_unit in ('g', 'kg', 'lb', 'oz')
                   then jsonb_build_object('value', p_p.weight, 'unit', case p_p.weight_unit when 'g' then 'GRAMS' when 'kg' then 'KILOGRAMS' when 'lb' then 'POUNDS' else 'OUNCES' end) else null end,   -- 0 · 단위 없음 = 안 보냄
    'hs_code', nullif(trim(coalesce(p_p.hs_code, '')), ''),
    'country_code', nullif(upper(trim(coalesce(p_p.country_of_origin_code, ''))), ''));
$$;
comment on function public.shop_variant_payload(public.shop_store, public.product, public.product_family) is 'shop-2a1: 변형 한 줄 — sku · barcode(주 바코드) · price(스토어 sale 티어 · shop_tier_price) · compare_at_price(compare 티어 · null = 안 보냄) · option_values(family 옵션 이름 순) · inventory_policy CONTINUE(켜짐 · 판정 407) | DENY(꺼짐 · 판정 406) · image_id(대표 사진) · weight{value, unit GRAMS | KILOGRAMS | POUNDS | OUNCES · 0 이면 null} · hs_code · country_code';
revoke all on function public.shop_product_payload(uuid, uuid, uuid) from public, anon;
revoke all on function public.shop_variant_payload(public.shop_store, public.product, public.product_family) from public, anon;
revoke all on function public.shop_tier_price(uuid, uuid) from public, anon;
grant execute on function public.shop_product_payload(uuid, uuid, uuid) to authenticated;
grant execute on function public.shop_variant_payload(public.shop_store, public.product, public.product_family) to authenticated;
grant execute on function public.shop_tier_price(uuid, uuid) to authenticated;

-- ═══ 5) 뷰 shop_listing_list — Settings · products · families 의 Shopify 칸(2c) ═══
create view public.shop_listing_list
  with (security_invoker = true) as
  select l.id as listing_id, l.store_id, s.code as store_code, s.label as store_label,
         case when l.family_id is not null then 'family' else 'product' end as kind,
         l.family_id, l.product_id,
         coalesce(f.sku, p.sku) as sku, coalesce(f.name, p.name) as name,
         l.is_on, l.turned_on_at, (select st.name from public.ims_staff st where st.id = l.turned_on_by) as turned_on_by_name,
         l.turned_off_at, (select st.name from public.ims_staff st where st.id = l.turned_off_by) as turned_off_by_name,
         sp.shopify_product_gid, sp.handle, sp.shopify_status, sp.last_pushed_at, sp.last_status, sp.last_error, sp.last_hash,
         (select count(*) from public.shop_push_queue q where q.store_id = l.store_id and q.done_at is null and q.family_id is not distinct from l.family_id and q.product_id is not distinct from l.product_id) as open_queue,
         (select max(q.done_at) from public.shop_push_queue q where q.store_id = l.store_id and q.family_id is not distinct from l.family_id and q.product_id is not distinct from l.product_id) as last_queue_done_at,
         l.updated_at
    from public.shop_listing l
    join public.shop_store s on s.id = l.store_id
    left join public.product_family f on f.id = l.family_id
    left join public.product p on p.id = l.product_id
    left join public.shop_product sp on sp.store_id = l.store_id and sp.family_id is not distinct from l.family_id and sp.product_id is not distinct from l.product_id;
revoke all on public.shop_listing_list from anon, authenticated;
grant select on public.shop_listing_list to authenticated;
comment on view public.shop_listing_list is 'shop-2a1 shop-2-0 ⬜8: 보냄 표시 한 줄 = 스토어 × 대상(family | product) — sku · name · is_on · 켠/끈 사람 · Shopify 대응(gid · handle · shopify_status · last_pushed_at · last_status · last_error) · open_queue(열린 큐 수) · security_invoker · select 만';
