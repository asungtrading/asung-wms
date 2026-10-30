-- ============================================================
-- shop-img-off-1 — 스토어마다 「사진 보내기」 스위치 shop_store.send_images · asung · aone 은 꺼서 Shopify 사진을 지킨다 (2026-10-30 · 판정 890 · 조사 shop-photo-0)
--   [테스트 · Asung-IMS] 시험(Claude Code · rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261030192911_shop_img_off_1_send_images.sql -f supabase/tests/shop_img_off_1_check.sql
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261030192911_shop_img_off_1_send_images.sql && supabase migration repair --status applied 20261030192911 --db-url "$(cat ~/.asung-testdb-url)"
--   왜: 첫 push 가 그 상품의 Shopify media 를 IMS 목록으로 갈아 끼운다(productSet files 는 목록 칸 · 빠진 것은 지워진다 · 판정 409 · _shared/shopify-product.ts 98 · 133 ~ 137) — Shopify 에만 있는 사진이 asung 1,849 장(971 상품) · aone 1,415 장(751 상품) 사라진다(shop-photo-0).
--       Shopify 전용 사진을 IMS 로 가져오는 일은 나중 차수(deferred 387) · 그때까지 두 스토어는 사진만 보내지 않는다(값 · 재고 · 제목 · 설명 · 상태 · 태그는 평소대로).
--   무엇:
--     1) shop_store.send_images boolean not null default true — 켜진 스토어는 지금 그대로(test) · asung · aone 은 이 파일에서 false(live false · 켜진 listing 0 · 열린 상품 큐 0 — 줄 0)
--     2) shop_variant_payload 재발행 — image_id 는 send_images 일 때만(아니면 null · 키 목록 같다 → 켜진 스토어 hash 보존 · 시험 A5)
--     3) shop_product_payload 재발행 — files 는 send_images 일 때만 모은다(아니면 [] · product_image 조회 0) · send_images 를 hash 밖에 실어 EF 가 두 번째 안전띠로 본다(buildProductSetInput)
--        → 꺼진 스토어 payload 는 판정 559 꼴(사진 0 장): EF 는 files 키 · 변형 file 을 보내지 않는다 — Shopify 문서 ProductVariantSetInput.file 「Any file specified here must also be specified in the files input for the product」 이라 변형 file 만 보내는 길은 없다 · files 를 빼면 media 무접촉(ProductSetInput: 목록 칸은 빠진 것을 지우고 · 안 준 칸은 그대로)
--        → hash 에 사진이 없다 = 사진만 바뀐 일(새 첨부 · 순서 · 표지 · cron 40 · 41 의 새 첨부)로는 큐 줄이 생겨도 drain 이 skipped_same_hash(Shopify 호출 0) · nightly(shop_queue_all · cron 43)가 줄을 세우지 않는다
--        → 오늘 밤 Apply links(shop_link_apply ④)가 심는 last_hash 는 이 함수의 「사진 뺀 hash」 — 새벽 08:00 nightly 가 전부를 다시 보내지 않는다(이 파일이 Apply 앞에 적용돼야 한다)
--     4) shop_store_queue_trigger 재발행 — send_images false → true 에만 켜진 listing 전부 큐(reason store · send_tags 와 같은 꼴) · true → false 는 줄 0(사진을 지우러 가지 않는다)
--   무접촉: shop_store_save(스위치는 SQL · 화면 칸은 다음 차수) · shop_store_list(화면 차수에서 끝에 더한다) · shop_queue_add · shop_queue_all · shop_link_apply · shop_link_push_batch · product_image 트리거 · EF index.ts(안전띠는 _shared/shopify-product.ts 두 줄)
--   새 표 · 새 FK 없음(칸 하나 · 함수 셋 재발행) → 「컷오버 날 지우는 순서」 해당 없음
--   스위치(SQL · 관리자 psql): 보기  select code, send_images from public.shop_store order by code;
--                              켜기  update public.shop_store set send_images = true  where code = 'asung';   -- 켜는 순간 그 스토어 켜진 listing 전부 큐(사진이 나간다)
--                              끄기  update public.shop_store set send_images = false where code = 'asung';   -- 줄 0
-- ============================================================

-- ═══ 1) 칸 — send_images(기본 true) · 트리거 함수 먼저 바꾸고 실제 스토어를 끈다 ═══
alter table public.shop_store add column if not exists send_images boolean not null default true;
comment on column public.shop_store.send_images is 'shop-img-off-1 판정 890: 사진 보내기 — true = push 가 상품 media · 변형 사진을 IMS 목록대로(판정 409) · false = payload 에 files [] · image_id null(판정 559 꼴 · EF 가 files 키 · 변형 file 을 안 보내 Shopify 사진이 그대로) · hash 에 사진이 안 들어 사진만 바뀐 일로는 push 0 · false → true 로 켜는 순간 트리거가 켜진 listing 전부를 상품 큐에(사진이 그때 나간다) · 끄기는 줄 0 · 바꾸기 = SQL update(화면 칸은 다음 차수) · asung · aone 은 2026-10-30 false(Shopify 전용 사진 3,264 장을 지키려고 · 가져오기는 deferred 387)';

-- ═══ 2) shop_store 트리거 재발행 — send_images 가 false → true 가 된 스토어도 켜진 대상 전부를 큐에 ═══
create or replace function public.shop_store_queue_trigger() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_id   uuid;
  v_fids uuid[];
  v_pids uuid[];
begin
  for v_id in select n.id from n join o on o.id = n.id
               where (o.oos_policy, o.send_tags, o.sale_tier_id, o.compare_tier_id) is distinct from (n.oos_policy, n.send_tags, n.sale_tier_id, n.compare_tier_id)
                  or (not o.send_images and n.send_images) loop                                     -- shop-img-off-1 판정 890: 사진 보내기를 켜는 순간만(끄는 쪽은 줄 0)
    select coalesce(array_agg(l.family_id) filter (where l.family_id is not null), '{}'), coalesce(array_agg(l.product_id) filter (where l.product_id is not null), '{}')
      into v_fids, v_pids from public.shop_listing l where l.store_id = v_id and l.is_on;
    perform public.shop_queue_add(v_fids, v_pids, 'store', v_id);                                   -- 그 스토어의 켜진 대상마다 열린 줄 하나(이미 열려 있으면 건너뜀)
  end loop;
  return null;
end;
$$;
revoke all on function public.shop_store_queue_trigger() from public, anon, authenticated;
comment on function public.shop_store_queue_trigger() is 'shop-pol: shop_store 의 AFTER UPDATE STATEMENT 트리거 — payload 에 드는 칸(oos_policy · send_tags · sale_tier_id · compare_tier_id)이 바뀐 스토어의 켜진 listing 전부를 shop_queue_add(reason store) · ⭐ shop-img-off-1 판정 890: send_images 가 false → true 가 된 스토어도(사진이 그때 나간다) · true → false 는 줄 0 · 다른 칸(label · note · is_active · live …)은 줄 0';

-- 실제 두 스토어를 끈다 — 이 update 로 큐 줄 0(true → false 는 트리거 조건 밖 · 지금 켜진 listing 도 0 · 시험 C5)
update public.shop_store set send_images = false where code in ('asung', 'aone');

-- ═══ 3) shop_variant_payload 재발행 — image_id 는 send_images 일 때만(원본 20261010220500_shop_pol_oos_policy.sql:45 그대로 + 그 한 줄) ═══
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
    'image_id', case when p_s.send_images then (select i.id from public.product_image i where i.product_id = p_p.id and i.is_active order by i.is_primary desc, i.sort_order limit 1) end,   -- shop-img-off-1 판정 890: 스토어가 사진을 안 보내면 null(키는 남는다 · 켜진 스토어 hash 보존)
    'weight', case when coalesce(p_p.weight, 0) > 0 and p_p.weight_unit in ('g', 'kg', 'lb', 'oz')
                   then jsonb_build_object('value', p_p.weight, 'unit', case p_p.weight_unit when 'g' then 'GRAMS' when 'kg' then 'KILOGRAMS' when 'lb' then 'POUNDS' else 'OUNCES' end) else null end,   -- 0 · 단위 없음 = 안 보냄
    'hs_code', nullif(trim(coalesce(p_p.hs_code, '')), ''),
    'country_code', nullif(upper(trim(coalesce(p_p.country_of_origin_code, ''))), ''));
$$;
comment on function public.shop_variant_payload(public.shop_store, public.product, public.product_family) is 'shop-img-off-1 재발행(판정 890): image_id 는 스토어 send_images 일 때만 · 아니면 null(키 목록 같다) · 그 한 줄만 바뀜 · shop-2a1: 변형 한 줄 — sku · barcode(주 바코드) · price(스토어 sale 티어 · shop_tier_price) · compare_at_price(compare 티어 · null = 안 보냄) · option_values · inventory_policy · is_active · sellable · image_id · weight · hs_code · country_code · ⭐ shop-pol 판정 427 · 428: inventory_policy = not(is_active and sellable) → DENY(406) · is_discontinued → DENY(남은 재고까지만 · 재고 숫자는 그대로) · 스토어 oos_policy deny → DENY · 그 밖 CONTINUE(판정 407 은 이것으로 바뀜) · 키 목록은 2a1 과 같다(hash 보존)';

-- ═══ 4) shop_product_payload 재발행 — files 는 send_images 일 때만 · send_images 를 hash 밖에(원본 20261010220500_shop_pol_oos_policy.sql:71 그대로 + if 두 겹 + return 한 줄) ═══
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
    if v_s.send_images then                                                                        -- shop-img-off-1 판정 890: 스토어가 사진을 안 보내면 files 는 [] (사진 조회도 안 한다 · 판정 559 꼴 · EF 가 files 키 · 변형 file 을 안 보낸다)
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
    end if;
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
    if v_s.send_images then                                                                        -- shop-img-off-1 판정 890
    select coalesce(jsonb_agg(jsonb_build_object('product_image_id', i.id, 'image_path', i.storage_path, 'url', case when v_base = '' then null else v_base || '/storage/v1/object/public/product-images/' || i.storage_path end, 'alt', v_p.name, 'product_id', i.product_id) order by i.is_primary desc, i.sort_order), '[]'::jsonb)
      into v_files from public.product_image i where i.product_id = v_p.id and i.is_active;
    end if;
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
  return v_out || jsonb_build_object('send_images', v_s.send_images, 'hash', md5((v_out - 'blocks' - 'listing_on')::text));   -- shop-img-off-1: send_images 는 hash 밖(켜진 스토어 hash 보존) · EF 두 번째 안전띠가 읽는다
end;
$$;
comment on function public.shop_product_payload(uuid, uuid, uuid) is '⭐ shop-img-off-1 재발행(판정 890 · 2026-10-30): 스토어 send_images false 면 files [] · 변형 image_id null(사진 조회 0) → hash 에 사진이 없다(사진만 바뀐 일은 drain skipped_same_hash · nightly 줄 0) · send_images 를 hash 밖에 실어 EF 가 두 번째 안전띠로 본다 · 바뀐 줄 = if send_images 두 겹 + return 한 줄 · shop-2a1 설계 §3 · 판정 403 ~ 409 (shop-pol 재발행: blocks no_price 의 「켜진 변형」 = is_active and sellable — inventory_policy 는 판정 427 · 428 로 DENY 스토어 · 단종에서도 DENY 라 켜짐의 표식이 아니다 · 그 한 줄만 바뀜): 스토어로 보낼 상품 한 건의 내용 — kind family | product · title · description_html(원문 coalesce(description_html, cin7_description) · 거르기는 EF · 판정 402 · 412) · vendor · product_type · tags · send_tags · status(ACTIVE | ARCHIVED · 판정 405) · active_variants · options · variants(shop_variant_payload) · files · listing_on · blocks(no_variants · family_member_goes_with_family · set_not_sellable · listing_missing · no_price:<sku>) · hash = blocks · listing_on 을 뺀 md5';

-- ═══ 끝 — 자기 점검 ═══
do $$
declare v_src text;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_store' and column_name = 'send_images' and column_default = 'true' and is_nullable = 'NO') <> 1 then raise exception 'shop-img-off-1: shop_store.send_images missing'; end if;
  if exists (select 1 from public.shop_store where code in ('asung', 'aone') and send_images) then raise exception 'shop-img-off-1: asung · aone must be off'; end if;
  if (select send_images from public.shop_store where code = 'test') is distinct from true then raise exception 'shop-img-off-1: test store must stay on'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_queue_trigger';
  if v_src not like '%not o.send_images and n.send_images%' then raise exception 'shop-img-off-1: store trigger not re-issued'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_variant_payload';
  if v_src not like '%case when p_s.send_images then (select i.id%' then raise exception 'shop-img-off-1: shop_variant_payload not re-issued'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload';
  if (length(v_src) - length(replace(v_src, 'if v_s.send_images then', ''))) / length('if v_s.send_images then') <> 2 or v_src not like '%''send_images'', v_s.send_images, ''hash''%' then raise exception 'shop-img-off-1: shop_product_payload not re-issued'; end if;
end $$;
