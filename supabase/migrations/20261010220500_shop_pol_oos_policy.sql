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
-- shop-pol — 품절 판매를 스토어마다 · 단종은 남은 재고까지만 (2026-10-10 밤 · 판정 426 ~ 428 · 정본 docs/design/shopify-integration.md §3-c · 원문 so-module §59 예정)
--   ① shop_store.oos_policy(continue | deny · 기본 continue · 판정 427: asung.ca = continue · aonebeauty.com = deny · 시험 스토어 = asung.ca 를 따름)
--   ② shop_variant_payload 재발행(2a1 276 ~ 295 행 원본 · DB prosrc md5 746b3709 와 같음) — inventory_policy = 꺼진 구성원 DENY(406) → 단종 DENY(428) → 스토어 deny → CONTINUE · 나머지 칸 바이트 그대로(키를 더하지 않는다 — hash 가 전부 바뀌지 않게)
--   ③ shop_product_payload 재발행(2a1 187 ~ 272 행 원본 · md5 e78ab8ab) — blocks no_price 의 「켜짐」 을 inventory_policy = CONTINUE 가 아니라 is_active and sellable 로(DENY 스토어 · 단종 변형의 가격 없음을 놓치지 않게) · 그 한 줄만
--   ④ shop_store_save 재발행(1a 151 ~ 400 행 원본 · md5 61cd73a2) — store_set 이 oos_policy 를 받는다(없으면 새 스토어 continue · 있는 스토어는 그대로 · old 에 있을 때만 changed_elsewhere 대조 — 옛 화면 ss v1a 는 여섯 칸만 보내므로 깨지지 않는다) · 막기 oos_policy_invalid
--   ⑤ 뷰 shop_store_list 재발행(끝에 oos_policy · send_tags) ⑥ shop_store 트리거 — payload 에 드는 스토어 칸(oos_policy · send_tags · sale_tier_id · compare_tier_id)이 바뀌면 그 스토어의 켜진 대상 전부를 상품 큐에(reason store · shop_queue_add)
--   무접촉: product 트리거(2a2 · 모든 update 행을 큐에 — is_discontinued 바뀜도 이미 잡는다 · 검증 T3) · 재고 쪽(shop_stock_payload 는 is_off = not(is_active and sellable) 만 — 단종은 숫자 그대로 · 판정 428) · EF(_shared/shopify-product.ts 46 행이 inventory_policy 를 그대로 싣는다)
--   ⚠️ aone 스토어 행 · 위치 짝(Toronto 하나)은 컷오버 차수 — 이 차수는 칸 · 함수만
-- ════════════════════════════════════════════════════════════════════════════════════════════

-- ═══ 1) shop_store.oos_policy ═══
alter table public.shop_store add column if not exists oos_policy text not null default 'continue';
alter table public.shop_store add constraint shop_store_oos_policy_ck check (oos_policy in ('continue', 'deny'));
comment on column public.shop_store.oos_policy is 'shop-pol 판정 427: 품절 판매 — continue = 켜진 변형이 0 이어도 주문을 받는다(asung.ca · 시험 스토어) · deny = 0 이면 Shopify 가 막는다(aonebeauty.com · Toronto 재고만 — 위치 짝을 Toronto 하나로) · 변형의 inventoryPolicy = 꺼진 구성원 DENY(406) → 단종 DENY(428) → 이 칸 · 바꾸면 트리거가 켜진 대상 전부를 상품 큐에';

-- ═══ 2) shop_variant_payload 재발행 — inventory_policy 한 칸 ═══
create or replace function public.shop_variant_payload(p_s public.shop_store, p_p public.product, p_f public.product_family) returns jsonb
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
    'inventory_policy', case when not (p_p.is_active and p_p.sellable) then 'DENY'                  -- 판정 406: 꺼진 구성원 DENY(재고 0 은 stock 쪽)
                             when p_p.is_discontinued then 'DENY'                                       -- 판정 428: 단종은 스토어 설정과 상관없이 DENY · 남은 재고까지만(재고 숫자는 그대로)
                             when p_s.oos_policy = 'deny' then 'DENY'                                   -- 판정 427: 스토어가 품절 판매를 막음(aone)
                             else 'CONTINUE' end,                                                       -- 판정 427: asung.ca 꼴 · 판정 407 은 이것으로 바뀜
    'is_active', p_p.is_active, 'sellable', p_p.sellable,
    'image_id', (select i.id from public.product_image i where i.product_id = p_p.id and i.is_active order by i.is_primary desc, i.sort_order limit 1),
    'weight', case when coalesce(p_p.weight, 0) > 0 and p_p.weight_unit in ('g', 'kg', 'lb', 'oz')
                   then jsonb_build_object('value', p_p.weight, 'unit', case p_p.weight_unit when 'g' then 'GRAMS' when 'kg' then 'KILOGRAMS' when 'lb' then 'POUNDS' else 'OUNCES' end) else null end,   -- 0 · 단위 없음 = 안 보냄
    'hs_code', nullif(trim(coalesce(p_p.hs_code, '')), ''),
    'country_code', nullif(upper(trim(coalesce(p_p.country_of_origin_code, ''))), ''));
$$;
comment on function public.shop_variant_payload(public.shop_store, public.product, public.product_family) is 'shop-2a1: 변형 한 줄 — sku · barcode(주 바코드) · price(스토어 sale 티어 · shop_tier_price) · compare_at_price(compare 티어 · null = 안 보냄) · option_values · inventory_policy · is_active · sellable · image_id · weight · hs_code · country_code · ⭐ shop-pol 판정 427 · 428: inventory_policy = not(is_active and sellable) → DENY(406) · is_discontinued → DENY(남은 재고까지만 · 재고 숫자는 그대로) · 스토어 oos_policy deny → DENY · 그 밖 CONTINUE(판정 407 은 이것으로 바뀜) · 키 목록은 2a1 과 같다(hash 보존)';

-- ═══ 3) shop_product_payload 재발행 — blocks no_price 의 켜짐 판단 한 줄 ═══
create or replace function public.shop_product_payload(p_store_id uuid, p_family_id uuid default null, p_product_id uuid default null) returns jsonb
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
    from jsonb_array_elements(v_variants) x where (x->>'is_active')::boolean and (x->>'sellable')::boolean and (x->>'price') is null;   -- 켜진 변형에 Price 가 없으면 못 보낸다 · shop-pol: 켜짐 = is_active and sellable(inventory_policy 는 이제 DENY 스토어 · 단종에서도 DENY · 판정 427 · 428)
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
comment on function public.shop_product_payload(uuid, uuid, uuid) is 'shop-2a1 설계 §3 · 판정 403 ~ 409 (shop-pol 재발행: blocks no_price 의 「켜진 변형」 = is_active and sellable — inventory_policy 는 판정 427 · 428 로 DENY 스토어 · 단종에서도 DENY 라 켜짐의 표식이 아니다 · 그 한 줄만 바뀜): 스토어로 보낼 상품 한 건의 내용 — kind family | product · title · description_html(원문 coalesce(description_html, cin7_description) · 거르기는 EF · 판정 402 · 412) · vendor · product_type · tags · send_tags · status(ACTIVE | ARCHIVED · 판정 405) · active_variants · options · variants(shop_variant_payload) · files · listing_on · blocks(no_variants · family_member_goes_with_family · set_not_sellable · listing_missing · no_price:<sku>) · hash = blocks · listing_on 을 뺀 md5';

-- ═══ 4) shop_store_save 재발행 — store_set 이 oos_policy 를 받는다 ═══
create or replace function public.shop_store_save(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_n        int;
  v_i        int := 0;
  v_c        jsonb;
  v_op       text;
  v_code     text;
  v_key      text;
  v_gid      text;
  v_seen     text[] := '{}';
  v_keys     text[] := '{}';
  v_unacked  text[] := '{}';
  v_s        public.shop_store%rowtype;
  v_l        public.shop_location%rowtype;
  v_sale     public.ref_price_tier%rowtype;
  v_cmp      public.ref_price_tier%rowtype;
  v_wh       public.ref_warehouse%rowtype;
  v_old      jsonb;
  v_cur      jsonb;
  v_prefix   text;
  v_cnt      bigint;
  c_ops      constant text[] := array['store_set', 'store_off', 'location_set', 'location_off'];
begin
  perform public.ims_require_admin('Shopify stores');                                             -- ⭐ 유일한 문 — 첫 줄(shop-0 이견 5)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;

  -- ① 모양
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    raise exception 'p_changes must be a JSON array of changes — nothing was saved';
  end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then raise exception 'No changes given — nothing was saved'; end if;
  if v_n > 200 then raise exception 'Too many changes in one call (% — the limit is 200) — nothing was saved', v_n; end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    if not (coalesce(v_c->>'op', '') = any(c_ops)) then
      raise exception 'Unknown op "%" — store_set, store_off, location_set or location_off — nothing was saved', coalesce(v_c->>'op', '(none)');
    end if;
  end loop;

  -- ② 줄마다 막기 · 알리기 — 전부 모은다
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_s := null; v_l := null; v_sale := null; v_cmp := null; v_wh := null;
    v_code := lower(trim(coalesce(v_c->>(case when v_op like 'store_%' then 'code' else 'store_code' end), '')));
    v_key := case when v_code = '' then '(blank)' else v_code end;
    v_changes := v_changes || jsonb_build_object('i', v_i, 'op', v_op, 'code', v_code, 'applied', false);
    if v_code !~ '^[a-z0-9_]{1,20}$' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':code_invalid', 'code', 'code_invalid', 'message', format('Store code "%s" must be 1-20 lowercase letters, digits or _ — nothing was saved', v_code));
      continue;
    end if;
    select * into v_s from public.shop_store s where s.code = v_code;

    if v_op = 'store_set' then
      if (v_code || '|store') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Store %s appears twice in this call — nothing was saved', v_code));
        continue;
      end if;
      v_seen := v_seen || (v_code || '|store');
      -- old: 새 스토어는 null · 있는 스토어는 화면이 본 여섯 칸
      if v_s.id is not null then
        if coalesce(jsonb_typeof(v_c->'old'), 'none') <> 'object' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('Store %s exists — the old values the screen saw are missing — nothing was saved', v_code));
          continue;
        end if;
        v_old := v_c->'old';
        v_cur := jsonb_build_object('shop_domain', v_s.shop_domain, 'label', v_s.label, 'kind', v_s.kind,
                                    'sale_tier', (select t.name from public.ref_price_tier t where t.id = v_s.sale_tier_id),
                                    'compare_tier', (select t.name from public.ref_price_tier t where t.id = v_s.compare_tier_id),
                                    'secret_prefix', v_s.secret_prefix, 'oos_policy', v_s.oos_policy);
        if (v_cur->>'shop_domain') is distinct from nullif(v_old->>'shop_domain', '') or (v_cur->>'label') is distinct from nullif(v_old->>'label', '') or (v_cur->>'kind') is distinct from nullif(v_old->>'kind', '')
           or (v_cur->>'sale_tier') is distinct from nullif(v_old->>'sale_tier', '') or (v_cur->>'compare_tier') is distinct from nullif(v_old->>'compare_tier', '') or (v_cur->>'secret_prefix') is distinct from nullif(v_old->>'secret_prefix', '')
           or ((v_old ? 'oos_policy') and (v_cur->>'oos_policy') is distinct from nullif(v_old->>'oos_policy', '')) then   -- shop-pol: old 에 oos_policy 가 있을 때만 대조(옛 화면 ss v1a 는 여섯 칸만 보낸다)
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Someone just changed store %s — check again — nothing was saved', v_code));
          continue;
        end if;
      elsif coalesce(jsonb_typeof(v_c->'old'), 'null') <> 'null' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_unknown', 'code', 'store_unknown', 'message', format('Store %s does not exist — to create it send old as null — nothing was saved', v_code));
        continue;
      end if;
      -- 칸 검사
      if coalesce(v_c->>'shop_domain', '') !~ '^[a-z0-9][a-z0-9-]*\.myshopify\.com$' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':domain_invalid', 'code', 'domain_invalid', 'message', format('Store %s: the domain must look like name.myshopify.com (lowercase) — nothing was saved', v_code));
      elsif exists (select 1 from public.shop_store x where x.shop_domain = v_c->>'shop_domain' and x.code <> v_code) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':domain_taken', 'code', 'domain_taken', 'message', format('Store %s: %s is already used by another store — nothing was saved', v_code, v_c->>'shop_domain'));
      end if;
      if nullif(trim(coalesce(v_c->>'label', '')), '') is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':label_missing', 'code', 'label_missing', 'message', format('Store %s needs a label — nothing was saved', v_code));
      end if;
      if coalesce(v_c->>'kind', '') not in ('asung', 'aone') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':kind_invalid', 'code', 'kind_invalid', 'message', format('Store %s: kind must be asung or aone — nothing was saved', v_code));
      end if;
      if (v_c ? 'oos_policy') and coalesce(v_c->>'oos_policy', '') not in ('continue', 'deny') then          -- shop-pol 판정 427: 품절 판매 continue | deny · 없으면 새 스토어 continue · 있는 스토어는 그대로
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':oos_policy_invalid', 'code', 'oos_policy_invalid', 'message', format('Store %s: sell when out of stock must be continue or deny — nothing was saved', v_code));
      end if;
      v_prefix := coalesce(nullif(trim(coalesce(v_c->>'secret_prefix', '')), ''), 'SHOPIFY_IMS');
      if v_prefix !~ '^[A-Z][A-Z0-9_]*$' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':prefix_invalid', 'code', 'prefix_invalid', 'message', format('Store %s: the secret prefix must be CAPITALS, digits or _ (e.g. SHOPIFY_IMS) — nothing was saved', v_code));
      end if;
      -- 티어 — 이름으로 받는다 · Price 는 sale 만 · Compare-at 은 sale 또는 compare(같아도 됨 · 비워도 됨) · reference 는 어디에도 안 된다(판정 403 고침)
      select * into v_sale from public.ref_price_tier t where t.name = trim(coalesce(v_c->>'sale_tier', '')) and t.is_active;
      if v_sale.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sale_tier_unknown', 'code', 'sale_tier_unknown', 'message', format('Store %s: there is no active price tier named "%s" for Price — nothing was saved', v_code, coalesce(v_c->>'sale_tier', '')));
      elsif v_sale.purpose <> 'sale' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sale_tier_not_sale', 'code', 'sale_tier_not_sale', 'message', format('Store %s: Price must be a sale tier — %s is a %s tier — nothing was saved', v_code, v_sale.name, v_sale.purpose));
      end if;
      if nullif(trim(coalesce(v_c->>'compare_tier', '')), '') is not null then
        select * into v_cmp from public.ref_price_tier t where t.name = trim(v_c->>'compare_tier') and t.is_active;
        if v_cmp.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':compare_tier_unknown', 'code', 'compare_tier_unknown', 'message', format('Store %s: there is no active price tier named "%s" for Compare-at — nothing was saved', v_code, v_c->>'compare_tier'));
        elsif v_cmp.purpose not in ('sale', 'compare') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':compare_tier_reference', 'code', 'compare_tier_reference', 'message', format('Store %s: Compare-at cannot be a %s tier (%s) — use a sale or compare tier, or leave it empty — nothing was saved', v_code, v_cmp.purpose, v_cmp.name));
        end if;
      end if;
      -- 알리기: 같은 kind 의 다른 활성 스토어(시험 + 실제가 같은 kind 일 수 있다 — 막지 않는다) · 꺼진 스토어를 다시 켬
      select count(*) into v_cnt from public.shop_store x where x.kind = coalesce(v_c->>'kind', '') and x.is_active and x.code <> v_code;
      if v_cnt > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':kind_active_dup', 'code', 'kind_active_dup', 'count', v_cnt, 'message', format('Store %s: %s other active store(s) already have kind %s — fine for a test store next to the real one, check it is what you mean', v_code, v_cnt, v_c->>'kind'));
      end if;
      if v_s.id is not null and not v_s.is_active then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':store_reactivated', 'code', 'store_reactivated', 'message', format('Store %s is off — saving turns it back on', v_code));
      end if;

    elsif v_op = 'store_off' then
      if v_s.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_unknown', 'code', 'store_unknown', 'message', format('Store %s does not exist — nothing was saved', v_code));
        continue;
      end if;
      if (v_code || '|store') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Store %s appears twice in this call — nothing was saved', v_code));
        continue;
      end if;
      v_seen := v_seen || (v_code || '|store');
      if not v_s.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':already_off', 'code', 'already_off', 'message', format('Store %s is already off — nothing was saved', v_code));
        continue;
      end if;
      if not (v_c ? 'old') or (v_c->>'old') is distinct from v_s.shop_domain then                  -- old = 화면이 본 shop_domain(스토어 확인용)
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Store %s: the domain the screen saw does not match — check again — nothing was saved', v_code));
        continue;
      end if;
      select count(*) into v_cnt from public.shop_location l where l.store_id = v_s.id and l.is_active;
      if v_cnt > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':locations_stay', 'code', 'locations_stay', 'count', v_cnt, 'message', format('Store %s has %s active location pair(s) — they stay as they are (the store is only switched off)', v_code, v_cnt));
      end if;

    else                                                                                            -- location_set · location_off
      if v_s.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_unknown', 'code', 'store_unknown', 'message', format('Store %s does not exist — nothing was saved', v_code));
        continue;
      end if;
      v_gid := trim(coalesce(v_c->>'shopify_location_gid', ''));
      v_key := v_code || ':' || (case when v_gid = '' then '(blank)' else v_gid end);
      if v_gid !~ '^gid://shopify/Location/[0-9]+$' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':gid_invalid', 'code', 'gid_invalid', 'message', format('Store %s: the Shopify location id must look like gid://shopify/Location/123 — nothing was saved', v_code));
        continue;
      end if;
      if (v_code || '|gid|' || v_gid) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Store %s: location %s appears twice in this call — nothing was saved', v_code, v_gid));
        continue;
      end if;
      v_seen := v_seen || (v_code || '|gid|' || v_gid);
      select * into v_l from public.shop_location l where l.store_id = v_s.id and l.shopify_location_gid = v_gid;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('Store %s location %s: the old warehouse the screen saw is missing (null for a new pair) — nothing was saved', v_code, v_gid));
        continue;
      end if;
      if (case when v_l.id is not null and v_l.is_active then v_l.warehouse_id::text end) is distinct from nullif(v_c->>'old', '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Someone just changed the warehouse of location %s on store %s — check again — nothing was saved', v_gid, v_code));
        continue;
      end if;
      if v_op = 'location_set' then
        if coalesce(v_c->>'warehouse_id', '') ~ '^[0-9a-fA-F-]{36}$' then
          select * into v_wh from public.ref_warehouse w where w.id = (v_c->>'warehouse_id')::uuid and w.is_active;
        end if;
        if v_wh.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_unknown', 'code', 'warehouse_unknown', 'message', format('Store %s location %s: the warehouse is missing or inactive — nothing was saved', v_code, v_gid));
          continue;
        end if;
        if (v_code || '|wh|' || v_wh.id::text) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_duplicate_in_call', 'code', 'warehouse_duplicate_in_call', 'message', format('Store %s: warehouse %s is given to two locations in this call — nothing was saved', v_code, v_wh.name));
          continue;
        end if;
        v_seen := v_seen || (v_code || '|wh|' || v_wh.id::text);
        if exists (select 1 from public.shop_location x where x.store_id = v_s.id and x.warehouse_id = v_wh.id and x.is_active and x.shopify_location_gid <> v_gid) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_already_mapped', 'code', 'warehouse_already_mapped', 'message', format('Store %s: warehouse %s is already paired with another Shopify location — switch that pair off first — nothing was saved', v_code, v_wh.name));
          continue;
        end if;
      else
        if v_l.id is null or not v_l.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':location_unknown', 'code', 'location_unknown', 'message', format('Store %s has no active pair for location %s — nothing was saved', v_code, v_gid));
          continue;
        end if;
      end if;
    end if;
  end loop;

  -- ③ 판정
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ④ 저장 — 줄 순서대로 · 한 트랜잭션
  v_i := 0;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_code := lower(trim(coalesce(v_c->>(case when v_op like 'store_%' then 'code' else 'store_code' end), '')));
    select * into v_s from public.shop_store s where s.code = v_code;
    if v_op = 'store_set' then
      select t.id into v_sale from public.ref_price_tier t where t.name = trim(v_c->>'sale_tier') and t.is_active;
      v_cmp := null;
      if nullif(trim(coalesce(v_c->>'compare_tier', '')), '') is not null then
        select t.id into v_cmp from public.ref_price_tier t where t.name = trim(v_c->>'compare_tier') and t.is_active;
      end if;
      v_prefix := coalesce(nullif(trim(coalesce(v_c->>'secret_prefix', '')), ''), 'SHOPIFY_IMS');
      if v_s.id is null then
        insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, compare_tier_id, secret_prefix, oos_policy, is_active, updated_by)
        values (v_code, v_c->>'shop_domain', trim(v_c->>'label'), v_c->>'kind', v_sale.id, v_cmp.id, v_prefix, coalesce(v_c->>'oos_policy', 'continue'), true, v_staff);
      else
        update public.shop_store set shop_domain = v_c->>'shop_domain', label = trim(v_c->>'label'), kind = v_c->>'kind', sale_tier_id = v_sale.id, compare_tier_id = v_cmp.id, secret_prefix = v_prefix, oos_policy = coalesce(v_c->>'oos_policy', v_s.oos_policy), is_active = true
         where id = v_s.id;
      end if;
    elsif v_op = 'store_off' then
      update public.shop_store set is_active = false where id = v_s.id;
    elsif v_op = 'location_set' then
      v_gid := trim(v_c->>'shopify_location_gid');
      select * into v_l from public.shop_location l where l.store_id = v_s.id and l.shopify_location_gid = v_gid;
      if v_l.id is not null then
        update public.shop_location set warehouse_id = (v_c->>'warehouse_id')::uuid, is_active = true where id = v_l.id;
      elsif exists (select 1 from public.shop_location x where x.store_id = v_s.id and x.warehouse_id = (v_c->>'warehouse_id')::uuid and not x.is_active) then
        update public.shop_location set shopify_location_gid = v_gid, shopify_name = null, checked_at = null, is_active = true     -- 꺼진 같은 창고 짝을 되살려 새 GID 로(유니크 둘을 지킨다)
         where store_id = v_s.id and warehouse_id = (v_c->>'warehouse_id')::uuid and not is_active;
      else
        insert into public.shop_location (store_id, shopify_location_gid, warehouse_id, is_active, updated_by) values (v_s.id, v_gid, (v_c->>'warehouse_id')::uuid, true, v_staff);
      end if;
    elsif v_op = 'location_off' then
      update public.shop_location set is_active = false where store_id = v_s.id and shopify_location_gid = trim(v_c->>'shopify_location_gid');
    end if;
    v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
  end loop;
  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
comment on function public.shop_store_save(jsonb, boolean, text[]) is
  '⭐ Shopify 스토어 설정 창구(shop-1a · 판정 362 · 403 · shop-0 이견 5) — definer · 첫 줄 ims_require_admin · p_changes = 바꿀 것 목록(최대 200) · op 넷: store_set {code, shop_domain, label, kind, sale_tier, compare_tier, secret_prefix?, oos_policy?, old}(새 스토어는 old null · 있는 스토어는 old = 화면이 본 여섯 칸 {shop_domain, label, kind, sale_tier, compare_tier, secret_prefix} + shop-pol 부터 oos_policy(old 에 있을 때만 대조) · 티어는 이름 · compare_tier 비움 = 안 보냄 · 꺼진 스토어는 다시 켠다) · store_off {code, old = shop_domain} · location_set {store_code, shopify_location_gid, warehouse_id, old = 지금 warehouse_id | null} · location_off {store_code, shopify_location_gid, old = warehouse_id}. 막기 code_invalid · oos_policy_invalid(shop-pol 판정 427 · continue | deny · 없으면 새 스토어 continue · 있는 스토어는 그대로) · domain_invalid · domain_taken · label_missing · kind_invalid · prefix_invalid · sale_tier_unknown · sale_tier_not_sale · compare_tier_unknown · compare_tier_reference · store_unknown · already_off · old_missing · changed_elsewhere · field_duplicate_in_call · gid_invalid · warehouse_unknown · warehouse_duplicate_in_call · warehouse_already_mapped · location_unknown. 알리기(ack) kind_active_dup{count} · store_reactivated · locations_stay{count}. 검사만(p_commit false) → 저장(p_commit true + p_ack) · 막기 하나면 아무것도 안 바뀐다 · Compare-at = Price 같은 티어는 막기도 경고도 아님(판정 403 고침)';

-- ═══ 5) 뷰 shop_store_list 재발행 — 끝에 oos_policy · send_tags ═══
create or replace view public.shop_store_list
  with (security_invoker = true) as
  select s.id, s.code, s.shop_domain, s.label, s.kind, s.is_active, s.secret_prefix, s.note, s.updated_at, s.updated_by,
         s.sale_tier_id,    ts.name as sale_tier_name,
         s.compare_tier_id, tc.name as compare_tier_name,
         coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'shopify_location_gid', l.shopify_location_gid, 'shopify_name', l.shopify_name,
                                                        'warehouse_id', l.warehouse_id, 'warehouse_name', w.name, 'is_active', l.is_active, 'checked_at', l.checked_at)
                                     order by l.is_active desc, w.name)
                     from public.shop_location l join public.ref_warehouse w on w.id = l.warehouse_id
                    where l.store_id = s.id), '[]'::jsonb) as locations,
         (select count(*) from public.shop_location l where l.store_id = s.id and l.is_active) as locations_active,
         p.ok as last_ping_ok, p.called_at as last_ping_at, p.error as last_ping_error,
         s.oos_policy, s.send_tags                                                                   -- shop-pol: 끝에 둘(create or replace 는 끝에만 더할 수 있다) · send_tags 는 2a1 이 칸만 더하고 뷰에 안 넣었던 것
    from public.shop_store s
    join public.ref_price_tier ts on ts.id = s.sale_tier_id
    left join public.ref_price_tier tc on tc.id = s.compare_tier_id
    left join lateral (select g.ok, g.called_at, g.error from public.shop_call_log g where g.store_id = s.id and g.action = 'ping' order by g.called_at desc, g.id desc limit 1) p on true;
comment on view public.shop_store_list is 'shop-1a: Settings → Shopify Stores 화면의 목록 — 스토어 + 티어 이름(sale_tier_name · compare_tier_name) + locations jsonb[{id, shopify_location_gid, shopify_name, warehouse_id, warehouse_name, is_active, checked_at}] + locations_active + 마지막 ping(last_ping_ok · last_ping_at · last_ping_error · shop_call_log action ping) + shop-pol: oos_policy(판정 427) · send_tags(판정 410) · security_invoker · select 만';

-- ═══ 6) shop_store 트리거 — payload 에 드는 스토어 칸이 바뀌면 켜진 대상 전부를 상품 큐에 ═══
create function public.shop_store_queue_trigger() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_id   uuid;
  v_fids uuid[];
  v_pids uuid[];
begin
  for v_id in select n.id from n join o on o.id = n.id
               where (o.oos_policy, o.send_tags, o.sale_tier_id, o.compare_tier_id) is distinct from (n.oos_policy, n.send_tags, n.sale_tier_id, n.compare_tier_id) loop
    select coalesce(array_agg(l.family_id) filter (where l.family_id is not null), '{}'), coalesce(array_agg(l.product_id) filter (where l.product_id is not null), '{}')
      into v_fids, v_pids from public.shop_listing l where l.store_id = v_id and l.is_on;
    perform public.shop_queue_add(v_fids, v_pids, 'store', v_id);                                   -- 그 스토어의 켜진 대상마다 열린 줄 하나(이미 열려 있으면 건너뜀)
  end loop;
  return null;
end;
$$;
revoke all on function public.shop_store_queue_trigger() from public, anon, authenticated;
comment on function public.shop_store_queue_trigger() is 'shop-pol: shop_store 의 AFTER UPDATE STATEMENT 트리거 — payload 에 드는 칸(oos_policy · send_tags · sale_tier_id · compare_tier_id)이 바뀐 스토어의 켜진 listing 전부를 shop_queue_add(reason store) · 다른 칸(label · note · is_active …)은 줄 0';
create trigger shop_store_shop_queue_u after update on public.shop_store referencing old table as o new table as n for each statement execute function public.shop_store_queue_trigger();

-- ═══ 끝 — 자기 점검 ═══
do $$
declare v_src text;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_store' and column_name = 'oos_policy' and column_default like '%continue%') <> 1 then raise exception 'shop-pol: shop_store.oos_policy missing'; end if;
  if to_regprocedure('public.shop_store_queue_trigger()') is null or not exists (select 1 from pg_trigger where tgname = 'shop_store_shop_queue_u') then raise exception 'shop-pol: store trigger missing'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload';
  if v_src like '%= ''CONTINUE'' and (x->>''price'')%' then raise exception 'shop-pol: shop_product_payload still keys no_price on CONTINUE'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_variant_payload';
  if v_src not like '%is_discontinued%' or v_src not like '%oos_policy%' then raise exception 'shop-pol: shop_variant_payload not re-issued'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_save';
  if v_src not like '%oos_policy_invalid%' then raise exception 'shop-pol: shop_store_save not re-issued'; end if;
  if (select oos_policy from public.shop_store where code = 'test') is distinct from 'continue' then raise exception 'shop-pol: test store must stay continue'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_store_list' and column_name in ('oos_policy', 'send_tags')) <> 2 then raise exception 'shop-pol: view columns missing'; end if;
end $$;
