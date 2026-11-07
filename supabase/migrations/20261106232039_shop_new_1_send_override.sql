-- ============================================================
-- shop-new-1 — 상품 단위 사진 · 태그 보내기: IMS 가 만든 상품은 자동 · 관리자 덧씌우기 (2026-11-06 · 판정 1042 · 1043 · 조사 shop-new-0 · 이견 1 ~ 7 답)
--   [운영 메인 · Asung-IMS] 시험(Claude Code · rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261106232039_shop_new_1_send_override.sql -f supabase/tests/shop_new_1_check.sql
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261106232039_shop_new_1_send_override.sql && supabase migration repair --status applied 20261106232039 --db-url "$(cat ~/.asung-testdb-url)"
--   왜: asung · aone 은 스토어 스위치(send_images false · send_tags false · 판정 890 · 410)로 Shopify 전용 사진 · 태그를 지킨다. 그런데 IMS 가 새로 만든 상품(컷 뒤 신제품 · cin7_id null · 잇기 짝 없음)은
--       Shopify 에 지킬 것이 없고 사진 · 태그가 IMS 에만 있다 — 스토어 스위치가 꺼진 채로는 사진 0 · 태그 0 으로 만들어진다(shop-new-0 ① 2).
--   무엇(판정 가 · 나 · 다 · 라 · 마):
--     1) shop_product 칸 셋 — send_images boolean(null = 스토어를 따름 · true = 보냄 · false = 스토어가 켜도 안 보냄 · 이견 4 coalesce) · send_tags boolean(같은 꼴) · origin text(link | ims · 감사용 · 기존 9,502 행 link)
--     2) shop_product_payload 재발행(원본 20261030192911_shop_img_off_1_send_images.sql 그대로 + 넷) —
--        ① 그 (스토어, 대상)의 shop_product 행을 읽어 **실효값** = 행 없음 → 둘 다 true(지금 만든다 = IMS 가 만드는 상품 · 판정 가) · 행 있음 → coalesce(행, 스토어)
--        ② 실효값을 v_s.send_images · v_s.send_tags 에 넣는다 → 아래 몸(files · image_id · 'send_tags' · 반환 send_images)은 한 줄도 안 바뀌고 shop_variant_payload 도 p_s 로 실효값을 받는다(재발행 없음 · md5 무변)
--        ③ IMS 태그 0 개면 send_tags false(판정 다 · 559 의 태그판 · EF :103 이 tags 칸을 안 보낸다 · EF 에도 `&& p.tags.length` 안전띠 = 두 겹 · 이견 5)
--        ④ 반환에 origin(hash 밖 · EF 가 안 읽는다 · 보는 사람용)
--        → hash: 덧씌움 null 인 기존 행은 실효값 = 스토어 값 = 10-30 과 같은 payload → 9,496 행 hash 무변(nightly 재전송 0 · 검사 C 전수) · 사진 덧씌움은 변형 image_id(hash 안)로 · 태그 덧씌움은 'send_tags'(hash 안)로 hash 가 바뀌어 drain 이 보낸다
--        → shop_link_apply ④ 는 행을 insert 한 뒤 hash 를 심는다 → 「행 없음 = true」 가 잇기 hash 를 오염시키지 않는다(이견 7)
--     3) 창구 shop_product_send_override(p_store_code, p_family_id, p_product_id, p_images, p_tags, p_queue) — ims_require_admin 하나(이견 3 · 선례 shop_store_save) · 행 없음 → 거부(새 상품은 자동 · 이견 2) · 두 칸을 그대로 쓴다(null = 끄기) · p_queue 면 shop_queue_add(reason override · 켜진 listing 만) · 반환 전 · 후 · 실효값 · hash 전 · 후 · 큐 줄 수
--     4) EF shopify pushOne — shop_product 행이 없어 identifier 없이 productSet 으로 만든 뒤의 upsert(POST)에만 origin 'ims' · send_images true · send_tags true(_shared/shopify-product.ts newShopProductColumns) · 그 밖의 PATCH 는 세 칸 무접촉 · :103 `if (p.send_tags && p.tags.length)`
--   무접촉: shop_variant_payload(p_s 가 실효값을 나른다) · shop_store_queue_trigger · shop_queue_add · shop_queue_all · shop_link_apply(origin 은 기본값 link) · shop_listing_set · 화면(SQL 창구 · 화면은 다음 차수)
--   새 표 · 새 FK 없음 · add column 은 null 또는 상수 기본값(PG 11+ 메타만) · 직원 규칙(IMS 가 만든 · 덧씌운 상품의 사진 · 태그는 IMS Products 에서만)은 매뉴얼 몫
--   창구(SQL · 관리자 psql 또는 rpc): select public.shop_product_send_override('asung', null, (select id from public.product where sku = 'ABE10612'), true, null, true);   -- 사진만 켜고 큐
--                                   select public.shop_product_send_override('asung', null, (select id from public.product where sku = 'ABE10612'), null, null, false);  -- 끄기(스토어를 따름)
-- ============================================================

-- ═══ 1) 칸 셋 ═══
alter table public.shop_product
  add column if not exists send_images boolean,
  add column if not exists send_tags   boolean,
  add column if not exists origin      text not null default 'link',
  drop constraint if exists shop_product_origin_ck,
  add constraint shop_product_origin_ck check (origin in ('link', 'ims'));                          -- 한 문장(왕복 0.33 s · 잠금 구간을 줄인다)
comment on column public.shop_product.send_images is 'shop-new-1 판정 나: 이 (스토어, 대상)의 사진 보내기 덧씌우기 — null = 스토어 send_images 를 따름 · true = 보냄(IMS 목록대로 · 판정 409) · false = 스토어가 켜도 안 보냄 · 실효값은 shop_product_payload 가 coalesce(행, 스토어)로 · 행이 없으면(IMS 가 지금 만드는 상품) true · 쓰기는 shop_product_send_override(관리자) 와 EF 가 만들 때(true)';
comment on column public.shop_product.send_tags is 'shop-new-1 판정 나 · 다: 태그 보내기 덧씌우기 — null = 스토어 send_tags 를 따름 · true = 보냄(내부 표식 태그도 · 판정 426) · false = 안 보냄 · 실효값이 true 여도 IMS 태그 0 개면 payload send_tags false(tags 칸을 안 보내 Shopify 태그를 안 지운다) · 행이 없으면 true';
comment on column public.shop_product.origin is 'shop-new-1 감사용: link = 잇기(shop_link_apply · 기존 9,502 행 · 기본값) · ims = EF shopify pushOne 이 identifier 없이 productSet 으로 만든 상품(그 순간 send_images · send_tags true) · 추론으로 바꾸지 않는다';

-- ═══ 2) shop_product_payload 재발행 — 원본 20261030192911 그대로 + 실효값(행 읽기 · 대입) + 태그 0 규칙 + 반환 origin ═══
create or replace function public.shop_product_payload(p_store_id uuid, p_family_id uuid default null, p_product_id uuid default null) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_s        public.shop_store%rowtype;
  v_f        public.product_family%rowtype;
  v_p        public.product%rowtype;
  v_l        public.shop_listing%rowtype;
  v_sp       public.shop_product%rowtype;                                                          -- shop-new-1: 이 (스토어, 대상)의 행 — 덧씌우기 · 있고 없음
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
  -- shop-new-1(판정 가 · 나 · 이견 4): 실효값 = 행 없음(IMS 가 지금 만든다) → 둘 다 true · 행 있음 → coalesce(행, 스토어) — v_s 에 넣어 아래 몸과 shop_variant_payload(p_s)가 그대로 읽는다
  if p_family_id is not null then
    select * into v_sp from public.shop_product sp where sp.store_id = p_store_id and sp.family_id = p_family_id;
  else
    select * into v_sp from public.shop_product sp where sp.store_id = p_store_id and sp.product_id = p_product_id;
  end if;
  if v_sp.id is null then
    v_s.send_images := true;  v_s.send_tags := true;
  else
    v_s.send_images := coalesce(v_sp.send_images, v_s.send_images);  v_s.send_tags := coalesce(v_sp.send_tags, v_s.send_tags);
  end if;

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
  if jsonb_array_length(v_tags) = 0 then v_s.send_tags := false; end if;                           -- shop-new-1 판정 다(1043): IMS 태그 0 개면 tags 칸을 안 보낸다(559 의 태그판 · Shopify 태그를 지우지 않는다) · EF :103 이 send_tags 로 거른다

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
  return v_out || jsonb_build_object('send_images', v_s.send_images, 'origin', v_sp.origin, 'hash', md5((v_out - 'blocks' - 'listing_on')::text));   -- shop-img-off-1: send_images 는 hash 밖(켜진 스토어 hash 보존) · EF 두 번째 안전띠가 읽는다 · shop-new-1: origin 도 hash 밖(행 없음 = null · 보는 사람용)
end;
$$;
comment on function public.shop_product_payload(uuid, uuid, uuid) is '⭐ shop-new-1 재발행(판정 1042 · 1043 · 2026-11-06): send_images · send_tags 는 **실효값** — 그 (스토어, 대상)의 shop_product 행이 없으면(IMS 가 지금 만든다) 둘 다 true · 있으면 coalesce(행 덧씌우기, 스토어) · 실효값을 v_s 에 넣어 몸과 shop_variant_payload(p_s)가 그대로 읽는다(변형 image_id 가 hash 안이라 사진 덧씌우기가 hash 를 바꾼다) · IMS 태그 0 개면 send_tags false(tags 칸을 안 보낸다 · 1043) · 반환에 origin(hash 밖) · 덧씌움 null 인 기존 행은 10-30 과 같은 payload(hash 무변 · 검사 C 전수) · ⭐ shop-img-off-1 재발행(판정 890 · 2026-10-30): 스토어 send_images false 면 files [] · 변형 image_id null(사진 조회 0) → hash 에 사진이 없다(사진만 바뀐 일은 drain skipped_same_hash · nightly 줄 0) · send_images 를 hash 밖에 실어 EF 가 두 번째 안전띠로 본다 · shop-2a1 설계 §3 · 판정 403 ~ 409 (shop-pol 재발행: blocks no_price 의 「켜진 변형」 = is_active and sellable — inventory_policy 는 판정 427 · 428 로 DENY 스토어 · 단종에서도 DENY 라 켜짐의 표식이 아니다): 스토어로 보낼 상품 한 건의 내용 — kind family | product · title · description_html(원문 coalesce(description_html, cin7_description) · 거르기는 EF · 판정 402 · 412) · vendor · product_type · tags · send_tags · status(ACTIVE | ARCHIVED · 판정 405) · active_variants · options · variants(shop_variant_payload) · files · listing_on · blocks(no_variants · family_member_goes_with_family · set_not_sellable · listing_missing · no_price:<sku>) · hash = blocks · listing_on 을 뺀 md5';

-- ═══ 3) 창구 — 관리자가 (스토어, 대상) 하나의 사진 · 태그 덧씌우기를 쓴다 ═══
create or replace function public.shop_product_send_override(p_store_code text, p_family_id uuid, p_product_id uuid, p_images boolean, p_tags boolean, p_queue boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_s       public.shop_store%rowtype;
  v_sp      public.shop_product%rowtype;
  v_before  jsonb;
  v_after   jsonb;
  v_q       int := 0;
begin
  perform public.ims_require_admin('Shopify send override');                                       -- ⭐ 유일한 문 — 첫 줄(이견 3 · 선례 shop_store_save)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if (p_family_id is null) = (p_product_id is null) then
    raise exception 'shop_product_send_override: give exactly one of p_family_id, p_product_id';
  end if;
  select * into v_s from public.shop_store s where s.code = p_store_code;
  if v_s.id is null then raise exception 'shop_product_send_override: store % not found', p_store_code; end if;
  if p_family_id is not null then
    select * into v_sp from public.shop_product sp where sp.store_id = v_s.id and sp.family_id = p_family_id for update;
  else
    select * into v_sp from public.shop_product sp where sp.store_id = v_s.id and sp.product_id = p_product_id for update;
  end if;
  if v_sp.id is null then                                                                           -- 이견 2: gid 는 not null 이라 「행 없음」 이 유일한 거부 — 새 상품은 EF 가 만들 때 사진 · 태그를 자동으로 보낸다
    raise exception 'shop_product_send_override: no shop_product row for this target in store % — a product IMS has not sent yet gets photos and tags automatically', p_store_code;
  end if;
  v_before := public.shop_product_payload(v_s.id, p_family_id, p_product_id);
  update public.shop_product sp set send_images = p_images, send_tags = p_tags, updated_at = now(), updated_by = v_staff where sp.id = v_sp.id;
  v_after := public.shop_product_payload(v_s.id, p_family_id, p_product_id);
  if p_queue then
    v_q := public.shop_queue_add(case when p_family_id is null then '{}'::uuid[] else array[p_family_id] end,
                                 case when p_product_id is null then '{}'::uuid[] else array[p_product_id] end, 'override', v_s.id);   -- 켜진 listing 이 있을 때만 한 줄(이미 열려 있으면 0)
  end if;
  return jsonb_build_object(
    'store', v_s.code, 'family_id', p_family_id, 'product_id', p_product_id, 'origin', v_sp.origin, 'shopify_product_gid', v_sp.shopify_product_gid,
    'before', jsonb_build_object('send_images', v_sp.send_images, 'send_tags', v_sp.send_tags, 'effective_images', v_before->'send_images', 'effective_tags', v_before->'send_tags', 'hash', v_before->'hash'),
    'after',  jsonb_build_object('send_images', p_images, 'send_tags', p_tags, 'effective_images', v_after->'send_images', 'effective_tags', v_after->'send_tags', 'hash', v_after->'hash'),
    'files', jsonb_array_length(v_after->'files'), 'tags', jsonb_array_length(v_after->'tags'), 'hash_changed', (v_before->>'hash') is distinct from (v_after->>'hash'),
    'queued', v_q, 'last_hash', v_sp.last_hash);
end;
$$;
revoke all on function public.shop_product_send_override(text, uuid, uuid, boolean, boolean, boolean) from public, anon;
grant execute on function public.shop_product_send_override(text, uuid, uuid, boolean, boolean, boolean) to authenticated;
comment on function public.shop_product_send_override(text, uuid, uuid, boolean, boolean, boolean) is 'shop-new-1 판정 나(2026-11-06): 관리자가 (스토어 code, family_id | product_id 하나)의 shop_product.send_images · send_tags 덧씌우기를 쓴다 — null = 스토어를 따름(끄기) · true = 보냄 · false = 스토어가 켜도 안 보냄 · 행이 없으면 거부(새 상품은 EF 가 만들 때 자동) · p_queue 면 shop_queue_add(reason override · 켜진 listing 만 · 열린 줄 있으면 0) · 반환 before · after(칸 · 실효값 · hash) · files · tags 수 · hash_changed · queued · ⚠️ 사진 덧씌우기는 변형 image_id 로 hash 가 바뀐다(사진 0 장이면 hash 그대로 · drain skipped_same_hash) · 태그 덧씌우기는 IMS 태그 0 개면 실효 false(1043) · 문 = ims_require_admin 하나(선례 shop_store_save) · 화면 칸은 다음 차수(지금은 SQL · rpc)';

-- ═══ 끝 — 자기 점검 ═══
do $$
declare v_src text;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_product' and column_name in ('send_images', 'send_tags') and data_type = 'boolean' and is_nullable = 'YES') <> 2 then raise exception 'shop-new-1: shop_product.send_images · send_tags missing'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_product' and column_name = 'origin' and is_nullable = 'NO' and column_default = '''link''::text') <> 1 then raise exception 'shop-new-1: shop_product.origin missing'; end if;
  if exists (select 1 from public.shop_product where origin <> 'link' or send_images is not null or send_tags is not null) then raise exception 'shop-new-1: existing rows must be link · null · null'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload';
  if v_src not like '%v_s.send_images := coalesce(v_sp.send_images, v_s.send_images)%' or v_src not like '%if jsonb_array_length(v_tags) = 0 then v_s.send_tags := false; end if;%'
     or (length(v_src) - length(replace(v_src, 'if v_s.send_images then', ''))) / length('if v_s.send_images then') <> 2 then raise exception 'shop-new-1: shop_product_payload not re-issued'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_send_override') <> 1 then raise exception 'shop-new-1: window missing or duplicated'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload') <> 1 then raise exception 'shop-new-1: shop_product_payload duplicated'; end if;
end $$;
