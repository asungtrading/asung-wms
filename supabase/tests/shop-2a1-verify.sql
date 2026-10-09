-- shop-2a1-verify.sql — Shopify ② DB 앞 절반: send_tags · web_image_id · 표 다섯 · shop_product_payload · shop_variant_payload · shop_tier_price · shop_listing_list (Asung-IMS · 테스트)
--   기대: 시험 갈래(-v mig) OK 18 · 확인 갈래 OK 17(= 18 − 시험 전용 1: G0a) · MISMATCH 0 · 확인 갈래 전용 줄(\else)은 없다 · 2회차 통과(1회차 1: T4a 기대 문자열에 sku 열쇠 누락 + jsonb 열쇠 순서 — 기대 쪽)
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261009200731_shop_2a1_listing.sql -f supabase/tests/shop-2a1-verify.sql > /tmp/shop-2a1.out 2>&1; echo exit=$?
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료: 실제 ANN01001FAM · ANN01291 · ANN03907 · BEL43475-12 는 읽기만(listing 행도 가짜 · rollback) · 가짜 family SHOP2A-FAM + 낱개 셋 + 세트 + 가격 + 사진 + 바코드 · 직원 하나 · 끝은 rollback · 큐 identity 는 greatest(max, head)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
do $$ declare v_last text; begin
  if to_regclass('public.shop_push_queue_id_seq') is not null then execute 'select last_value::text from public.shop_push_queue_id_seq' into v_last; else v_last := '0'; end if;
  perform set_config('shop2a.q_seq_head', v_last, false);
end $$;
select current_setting('shop2a.q_seq_head') as q_seq_head \gset
\echo '== head queue seq' :q_seq_head

begin;
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql security definer as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql security definer as $$
begin
  execute p_sql; return 'no-error';
exception when others then return sqlstate || ' ' || sqlerrm;
end $$;
\if :{?mig}
select pg_temp.chk('G0a trial marker: shop_listing exists only after the trial apply', (to_regclass('public.shop_listing') is not null)::text, 'true');
\endif

-- ═══ T1 — 칸 · 표 · 제약 · 권한 · 뷰 · 함수 ═══
select pg_temp.chk('T1a send_tags default false on the test store · web_image_id column + index',
  (select send_tags::text from public.shop_store where code = 'test') || '/' || (select column_default from information_schema.columns where table_schema = 'public' and table_name = 'shop_store' and column_name = 'send_tags') || '/' ||
  (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'product_family' and column_name = 'web_image_id') || '/' || (select count(*)::text from pg_indexes where schemaname = 'public' and indexname = 'product_family_web_image_id_idx'), 'false/false/1/1');
select pg_temp.chk('T1b tables 5 · touch triggers 4 · target CHECKs 3 · uniques (listing 2 · product 3 · variant 2 · media 2) · functions 3 · view',
  (select count(*) from pg_tables where schemaname = 'public' and tablename in ('shop_listing', 'shop_product', 'shop_variant', 'shop_media', 'shop_push_queue'))::text || '/' ||
  (select count(*) from pg_trigger where not tgisinternal and tgname in ('shop_listing_touch', 'shop_product_touch', 'shop_variant_touch', 'shop_media_touch'))::text || '/' ||
  (select count(*) from pg_constraint where conname in ('shop_listing_target_ck', 'shop_product_target_ck', 'shop_push_queue_target_ck'))::text || '/' ||
  (select string_agg(c.relname || ':' || n, ',' order by c.relname) from (select conrelid, count(*) n from pg_constraint where contype = 'u' and conrelid in ('public.shop_listing'::regclass, 'public.shop_product'::regclass, 'public.shop_variant'::regclass, 'public.shop_media'::regclass) group by conrelid) x join pg_class c on c.oid = x.conrelid) || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_product_payload', 'shop_variant_payload', 'shop_tier_price'))::text || '/' ||
  (select count(*) from pg_views where schemaname = 'public' and viewname = 'shop_listing_list')::text, '5/4/3/shop_listing:2,shop_media:2,shop_product:3,shop_variant:2/3/1');
select pg_temp.chk('T1c privileges: authenticated SELECT only on 5 tables + view · anon 0',
  (select string_agg(t || ':' || coalesce(p, '-'), ',' order by t) from (select t, (select string_agg(privilege_type, '+' order by privilege_type) from information_schema.role_table_grants g where g.table_schema = 'public' and g.table_name = t and g.grantee = 'authenticated') p from unnest(array['shop_listing', 'shop_product', 'shop_variant', 'shop_media', 'shop_push_queue', 'shop_listing_list']) t) x) || '/' ||
  (select count(*) from information_schema.role_table_grants g where g.table_schema = 'public' and g.table_name in ('shop_listing', 'shop_product', 'shop_variant', 'shop_media', 'shop_push_queue', 'shop_listing_list') and g.grantee = 'anon')::text,
  'shop_listing:SELECT,shop_listing_list:SELECT,shop_media:SELECT,shop_product:SELECT,shop_push_queue:SELECT,shop_variant:SELECT/0');
select pg_temp.chk('T1d CHECKs (23514): listing both targets · listing neither · product gid shape · variant gid · media gid · queue result vocabulary · queue done/result pair · listing off without time',
  left(pg_temp.err($q$insert into public.shop_listing (store_id, family_id, product_id) values ((select id from shop_store where code = 'test'), (select id from product_family where sku = 'ANN01001FAM'), (select id from product where sku = 'ANN01291'))$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_listing (store_id) values ((select id from shop_store where code = 'test'))$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_product (store_id, product_id, shopify_product_gid) values ((select id from shop_store where code = 'test'), (select id from product where sku = 'ANN01291'), 'Product/1')$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_variant (store_id, product_id, shopify_variant_gid) values ((select id from shop_store where code = 'test'), (select id from product where sku = 'ANN01291'), 'gid://shopify/Product/1')$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_media (store_id, product_image_id, shopify_file_gid) values ((select id from shop_store where code = 'test'), (select id from product_image limit 1), 'gid://shopify/Product/1')$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_push_queue (store_id, product_id, reason, done_at, result) values ((select id from shop_store where code = 'test'), (select id from product where sku = 'ANN01291'), 'x', now(), 'nope')$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_push_queue (store_id, product_id, reason, done_at) values ((select id from shop_store where code = 'test'), (select id from product where sku = 'ANN01291'), 'x', now())$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_listing (store_id, product_id, is_on) values ((select id from shop_store where code = 'test'), (select id from product where sku = 'ANN01291'), false)$q$), 5), '23514/23514/23514/23514/23514/23514/23514/23514');

-- ═══ 재료 — 실제 셋의 id(읽기) · 가짜 listing 행(postgres · rollback) · 가짜 family ═══
select id::text as store from public.shop_store where code = 'test' \gset
select id::text as fam_ann from public.product_family where sku = 'ANN01001FAM' \gset
select id::text as p_1291 from public.product where sku = 'ANN01291' \gset
select id::text as p_3907 from public.product where sku = 'ANN03907' \gset
select id::text as p_bel from public.product where sku = 'BEL43475-12' \gset
select id::text as p_01001 from public.product where sku = 'ANN01001' \gset
select id::text as tier_ws from public.ref_price_tier where name = 'Wholesale' \gset
select id::text as tier_cmp from public.ref_price_tier where name = 'wholesalespecia CAD' \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'shop2a-mgr@test.invalid', 'SHOP2A Manager', 'manager', '["shopify"]'::jsonb) returning auth_user_id::text as m_uid \gset
select s.id::text as m_sid from public.ims_staff s where s.email = 'shop2a-mgr@test.invalid' \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as brand_annie from public.ref_brand where name = 'Annie' \gset
-- 가짜 family SHOP2A-FAM — 낱개 셋(Color · Size) · 세트 하나(sellable false) · 가격 · 사진 · 바코드
insert into public.product_family (sku, name, source, brand_id, brand_name, category_name, option1_name, option2_name, cin7_description) values ('SHOP2A-FAM', 'SHOP2A Fake Rollers', 'manual', :'brand_annie'::uuid, 'Annie', 'Fake Category', 'Color', 'Size', '<p>fake family</p>') returning id::text as fam_fake \gset
insert into public.product (sku, name, source, family_id, option1_value, option2_value, brand_name, category_name, weight, weight_unit, is_active, sellable, hs_code, country_of_origin_code)
values ('SHOP2A-P1', 'SHOP2A P1', 'manual', :'fam_fake'::uuid, 'Red', 'Small', 'Annie', 'Fake Category', 0.05, 'kg', true, true, '9615.11', 'cn'),
       ('SHOP2A-P2', 'SHOP2A P2', 'manual', :'fam_fake'::uuid, 'Red', 'Large', 'Annie', 'Fake Category', 0, 'kg', true, true, null, null),
       ('SHOP2A-P3', 'SHOP2A P3', 'manual', :'fam_fake'::uuid, 'Blue', 'Small', 'Annie', 'Fake Category', 120, 'g', true, true, null, null);
select id::text as f1 from public.product where sku = 'SHOP2A-P1' \gset
select id::text as f2 from public.product where sku = 'SHOP2A-P2' \gset
select id::text as f3 from public.product where sku = 'SHOP2A-P3' \gset
insert into public.product (sku, name, source, parent_product_id, pack_factor, brand_name, is_active, sellable) values ('SHOP2A-P1-6', 'SHOP2A P1 set', 'manual', :'f1'::uuid, 6, 'Annie', true, false) returning id::text as fset \gset
insert into public.product_price (product_id, tier_id, price, source) values (:'f1'::uuid, :'tier_ws'::uuid, 2.50, 'manual'), (:'f2'::uuid, :'tier_ws'::uuid, 2.75, 'manual'), (:'f1'::uuid, :'tier_cmp'::uuid, 3.00, 'manual');
insert into public.product_image (product_id, storage_path, content_type, is_primary, sort_order, source) values
  (:'f1'::uuid, :'f1' || '/a.jpg', 'image/jpeg', true, 1, 'manual'), (:'f1'::uuid, :'f1' || '/b.jpg', 'image/jpeg', false, 2, 'manual'),
  (:'f2'::uuid, :'f2' || '/c.jpg', 'image/jpeg', true, 1, 'manual'), (:'f3'::uuid, :'f3' || '/d.jpg', 'image/jpeg', true, 1, 'manual');
select id::text as img_b from public.product_image where storage_path = :'f1' || '/b.jpg' \gset
insert into public.product_barcode (product_id, barcode, is_primary, source) values (:'f1'::uuid, '111111111111', true, 'manual'), (:'f1'::uuid, '222222222222', false, 'manual');
insert into public.shop_listing (store_id, family_id, turned_on_by, updated_by) values (:'store'::uuid, :'fam_fake'::uuid, :'m_sid'::uuid, :'m_sid'::uuid);
insert into public.shop_listing (store_id, family_id, turned_on_by) values (:'store'::uuid, :'fam_ann'::uuid, :'m_sid'::uuid);
insert into public.shop_listing (store_id, product_id, turned_on_by) values (:'store'::uuid, :'p_1291'::uuid, :'m_sid'::uuid);

-- ═══ T2 — 실제 셋 payload(읽기만) ═══
select public.shop_product_payload(:'store'::uuid, :'fam_ann'::uuid, null)::text as pa \gset
select public.shop_product_payload(:'store'::uuid, null, :'p_1291'::uuid)::text as p1 \gset
select public.shop_product_payload(:'store'::uuid, null, :'p_3907'::uuid)::text as p3 \gset
select public.shop_product_payload(:'store'::uuid, null, :'p_bel'::uuid)::text as pb \gset
select public.shop_product_payload(:'store'::uuid, null, :'p_01001'::uuid)::text as pm \gset
select pg_temp.chk('T2a ANN01001FAM: family · title · vendor Annie · 10 variants · options Color/Size (values in sku order) · ACTIVE · active 10 · blocks [] · send_tags false · tags []',
  (:'pa'::jsonb->>'kind') || '/' || (:'pa'::jsonb->>'title') || '/' || (:'pa'::jsonb->>'vendor') || '/' || jsonb_array_length(:'pa'::jsonb->'variants')::text || '/' || (select string_agg((o->>'name') || '=' || (o->'values')::text, ';') from jsonb_array_elements(:'pa'::jsonb->'options') o) || '/' || (:'pa'::jsonb->>'status') || '/' || (:'pa'::jsonb->>'active_variants') || '/' || (:'pa'::jsonb->'blocks')::text || '/' || (:'pa'::jsonb->>'send_tags') || '/' || (:'pa'::jsonb->'tags')::text,
  'family/ANNIE Snap-On Rollers/Annie/10/Color=["Blue", "Yellow", "Green", "Pink", "Orange", "Black"];Size=["Small (1/2\" Diameter)", "Medium (3/4\" Diameter)", "Large (7/8\" Diameter)", "X-Large (1 1/8\" Diameter)", "Jumbo (1 1/2\" Diameter)"]/ACTIVE/10/[]/false/[]');
select pg_temp.chk('T2b ANN01001FAM first variant: sku · barcode · price 1.49 · compare 1.49 (same value still sent · 408) · option_values · CONTINUE · weight 0.039 KILOGRAMS · image_id set · all 10 CONTINUE',
  (select (v->>'sku') || '/' || (v->>'barcode') || '/' || trim_scale((v->>'price')::numeric)::text || '/' || trim_scale((v->>'compare_at_price')::numeric)::text || '/' || (v->'option_values')::text || '/' || (v->>'inventory_policy') || '/' || (v->'weight')::text || '/' || ((v->>'image_id') is not null)::text from jsonb_array_elements(:'pa'::jsonb->'variants') v limit 1) || '/' ||
  (select count(*)::text from jsonb_array_elements(:'pa'::jsonb->'variants') v where v->>'inventory_policy' = 'CONTINUE'),
  'ANN01001/705372010014/1.49/1.49/[{"name": "Color", "value": "Blue"}, {"name": "Size", "value": "Small (1/2\" Diameter)"}]/CONTINUE/{"unit": "KILOGRAMS", "value": 0.039}/true/10');
select pg_temp.chk('T2c ANN01001FAM files: 10 (one primary each) · first = ANN01001 primary (no web_image_id) · image_path = storage_path · url null (no app.settings.supabase_url) · alt = product name',
  jsonb_array_length(:'pa'::jsonb->'files')::text || '/' || (select (f->>'product_id' = :'p_01001')::text || '/' || (f->>'image_path') || '/' || coalesce(f->>'url', 'null') || '/' || (f->>'alt') from jsonb_array_elements(:'pa'::jsonb->'files') f limit 1),
  '10/true/c31e163d-3634-4058-9353-b191d252f82d/07156d3a-52f1-4f21-8121-e07f86ea167c.jpg/null/ANNIE Snap-On Rollers - Blue Small (1/2" Diameter)');
select pg_temp.chk('T2d ANN01291: product · 1 variant · option_values [] · options [] · price 5.39 · compare null (no wholesalespecia row · omitted) · files 5 first primary · ACTIVE · hash equal on a second call',
  (:'p1'::jsonb->>'kind') || '/' || jsonb_array_length(:'p1'::jsonb->'variants')::text || '/' || (:'p1'::jsonb->'variants'->0->'option_values')::text || '/' || (:'p1'::jsonb->'options')::text || '/' || trim_scale((:'p1'::jsonb->'variants'->0->>'price')::numeric)::text || '/' || coalesce(:'p1'::jsonb->'variants'->0->>'compare_at_price', 'null') || '/' || jsonb_array_length(:'p1'::jsonb->'files')::text || '/' || (:'p1'::jsonb->'files'->0->>'image_path') || '/' || (:'p1'::jsonb->>'status') || '/' || ((:'p1'::jsonb->>'hash') = (public.shop_product_payload(:'store'::uuid, null, :'p_1291'::uuid)->>'hash'))::text,
  'product/1/[]/[]/5.39/null/5/f4d7532e-6db1-404a-b472-ca5dbbcc3018/c4ece265-0147-46e6-875f-e779591edc72.jpg/ACTIVE/true');
select pg_temp.chk('T2e ANN03907: weight 323 GRAMS · no listing → ARCHIVED + blocks [listing_missing] · BEL43475-12 sellable set: no block set_not_sellable · ANN01001 as product: family_member_goes_with_family',
  (:'p3'::jsonb->'variants'->0->'weight')::text || '/' || (:'p3'::jsonb->>'status') || '/' || (:'p3'::jsonb->'blocks')::text || '/' || (select coalesce(string_agg(b #>> '{}', ','), '') from jsonb_array_elements(:'pb'::jsonb->'blocks') b where b #>> '{}' = 'set_not_sellable') || '/' || (select string_agg(b #>> '{}', ',') from jsonb_array_elements(:'pm'::jsonb->'blocks') b where b #>> '{}' like 'family%'),
  '{"unit": "GRAMS", "value": 323}/ARCHIVED/["listing_missing"]//family_member_goes_with_family');

-- ═══ T3 — 가짜 family: 변형 셋 · 옵션 값 순서 · 꺼진 구성원 DENY · ARCHIVED · hash · web_image_id · 세트 제외 · 가격 없음 · HS · 원산지 ═══
select public.shop_product_payload(:'store'::uuid, :'fam_fake'::uuid, null)::text as q0 \gset
select pg_temp.chk('T3a fake family: 3 variants (set excluded) · options Color [Red, Blue] · Size [Small, Large] (first-sku order) · P1 price 2.50 compare 3.00 · P3 price null → block no_price:SHOP2A-P3 · P2 weight 0 → null · P1 hs 9615.11 country CN · barcode primary 111… · files 4 ordered a(primary) c d b',
  jsonb_array_length(:'q0'::jsonb->'variants')::text || '/' || (:'q0'::jsonb->'options')::text || '/' || (select trim_scale((v->>'price')::numeric)::text || '|' || trim_scale((v->>'compare_at_price')::numeric)::text || '|' || (v->>'hs_code') || '|' || (v->>'country_code') || '|' || (v->>'barcode') from jsonb_array_elements(:'q0'::jsonb->'variants') v where v->>'sku' = 'SHOP2A-P1') || '/' || (:'q0'::jsonb->'blocks')::text || '/' || (select coalesce((v->'weight')::text, 'null') from jsonb_array_elements(:'q0'::jsonb->'variants') v where v->>'sku' = 'SHOP2A-P2') || '/' || (select string_agg(right(f->>'image_path', 5), ',') from jsonb_array_elements(:'q0'::jsonb->'files') f),
  '3/[{"name": "Color", "values": ["Red", "Blue"]}, {"name": "Size", "values": ["Small", "Large"]}]/2.5|3|9615.11|CN|111111111111/["no_price:SHOP2A-P3"]/null/a.jpg,c.jpg,d.jpg,b.jpg');
insert into public.product_price (product_id, tier_id, price, source) values (:'f3'::uuid, :'tier_ws'::uuid, 2.00, 'manual');
select public.shop_product_payload(:'store'::uuid, :'fam_fake'::uuid, null)::text as q1 \gset
update public.product set sellable = false where sku = 'SHOP2A-P2';
select public.shop_product_payload(:'store'::uuid, :'fam_fake'::uuid, null)::text as q2 \gset
select pg_temp.chk('T3b price added → blocks [] · hash changed · member P2 switched off → still 3 variants · P2 DENY · others CONTINUE · active 2 · ACTIVE · hash changed again',
  (:'q1'::jsonb->'blocks')::text || '/' || ((:'q0'::jsonb->>'hash') <> (:'q1'::jsonb->>'hash'))::text || '/' || jsonb_array_length(:'q2'::jsonb->'variants')::text || '/' || (select string_agg((v->>'sku') || '=' || (v->>'inventory_policy'), ',' order by v->>'sku') from jsonb_array_elements(:'q2'::jsonb->'variants') v) || '/' || (:'q2'::jsonb->>'active_variants') || '/' || (:'q2'::jsonb->>'status') || '/' || ((:'q1'::jsonb->>'hash') <> (:'q2'::jsonb->>'hash'))::text,
  '[]/true/3/SHOP2A-P1=CONTINUE,SHOP2A-P2=DENY,SHOP2A-P3=CONTINUE/2/ACTIVE/true');
update public.product set is_active = false where sku in ('SHOP2A-P1', 'SHOP2A-P3');
select public.shop_product_payload(:'store'::uuid, :'fam_fake'::uuid, null)::text as q3 \gset
update public.product set is_active = true where sku in ('SHOP2A-P1', 'SHOP2A-P3');
update public.shop_listing set is_on = false, turned_off_at = now(), turned_off_by = :'m_sid'::uuid where store_id = :'store'::uuid and family_id = :'fam_fake'::uuid;
select public.shop_product_payload(:'store'::uuid, :'fam_fake'::uuid, null)::text as q4 \gset
update public.shop_listing set is_on = true, turned_off_at = null, turned_off_by = null where store_id = :'store'::uuid and family_id = :'fam_fake'::uuid;
update public.product_family set web_image_id = :'img_b'::uuid where id = :'fam_fake'::uuid;
select public.shop_product_payload(:'store'::uuid, :'fam_fake'::uuid, null)::text as q5 \gset
select pg_temp.chk('T3c all members off → ARCHIVED (active 0 · variants kept 3 all DENY) · listing off → ARCHIVED (hash unchanged vs listing on — status is in the hash, so it differs; listing_on itself is excluded) · web_image_id → b.jpg first',
  (:'q3'::jsonb->>'status') || '/' || (:'q3'::jsonb->>'active_variants') || '/' || (select count(*)::text from jsonb_array_elements(:'q3'::jsonb->'variants') v where v->>'inventory_policy' = 'DENY') || '/' || (:'q4'::jsonb->>'status') || '/' || (:'q4'::jsonb->>'listing_on') || '/' || ((:'q4'::jsonb->>'hash') <> (:'q2'::jsonb->>'hash'))::text || '/' || (select string_agg(right(f->>'image_path', 5), ',') from jsonb_array_elements(:'q5'::jsonb->'files') f),
  'ARCHIVED/0/3/ARCHIVED/false/true/b.jpg,a.jpg,c.jpg,d.jpg');
select pg_temp.chk('T3d shop_tier_price: own row · set calc (2.50 × 6 = 15.00 · no fixed row) · compare tier (purpose compare) readable · unknown → null',
  trim_scale(public.shop_tier_price(:'f1'::uuid, :'tier_ws'::uuid))::text || '/' || trim_scale(public.shop_tier_price(:'fset'::uuid, :'tier_ws'::uuid))::text || '/' || trim_scale(public.shop_tier_price(:'f1'::uuid, :'tier_cmp'::uuid))::text || '/' || coalesce(public.shop_tier_price(:'f3'::uuid, :'tier_cmp'::uuid)::text, 'null'), '2.5/15/3/null');
select pg_temp.chk('T3e payload argument shape: both ids → raise · neither → raise · unknown store → raise',
  left(pg_temp.err(format('select public.shop_product_payload(%L, %L, %L)', :'store', :'fam_fake', :'f1')), 5) || '/' || left(pg_temp.err(format('select public.shop_product_payload(%L, null, null)', :'store')), 5) || '/' || left(pg_temp.err(format('select public.shop_product_payload(gen_random_uuid(), %L, null)', :'fam_fake')), 5), 'P0001/P0001/P0001');

-- ═══ T4 — 뷰 · 큐 · 권한 ═══
insert into public.shop_product (store_id, family_id, shopify_product_gid, handle, shopify_status, last_hash, last_pushed_at, last_status) values (:'store'::uuid, :'fam_fake'::uuid, 'gid://shopify/Product/9001', 'shop2a-fake', 'ACTIVE', 'abc', now(), 'ok');
insert into public.shop_push_queue (store_id, family_id, reason) values (:'store'::uuid, :'fam_fake'::uuid, 'test');
insert into public.shop_push_queue (store_id, product_id, reason, started_at, done_at, result) values (:'store'::uuid, :'p_1291'::uuid, 'test', now(), now(), 'ok');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select (row_to_json(v)::jsonb - 'listing_id' - 'store_id' - 'family_id' - 'product_id' - 'turned_on_at' - 'turned_off_at' - 'last_pushed_at' - 'updated_at' - 'last_queue_done_at')::text as v_fake from public.shop_listing_list v where v.sku = 'SHOP2A-FAM' \gset
select (v.kind || '/' || v.sku || '/' || coalesce(v.shopify_product_gid, 'null') || '/' || v.open_queue || '/' || (v.last_queue_done_at is not null)::text) as v_1291 from public.shop_listing_list v where v.sku = 'ANN01291' \gset
select (public.shop_product_payload(:'store'::uuid, null, :'p_1291'::uuid)->>'status') as auth_payload \gset
do $$ begin insert into public.shop_listing (store_id, product_id) values ((select id from public.shop_store where code = 'test'), (select id from public.product where sku = 'ANN03907')); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a_ins \gset
do $$ begin update public.shop_push_queue set reason = 'x' where false; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a_upd \gset
reset role;
set local role anon;
do $$ begin perform count(*) from public.shop_listing_list; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as anon_view \gset
reset role;
select pg_temp.chk('T4a view row (fake family): kind · sku · name · is_on · turned_on_by_name · gid · handle · ACTIVE · ok · open_queue 1 · store test', :'v_fake',
  '{"sku": "SHOP2A-FAM", "kind": "family", "name": "SHOP2A Fake Rollers", "is_on": true, "handle": "shop2a-fake", "last_hash": "abc", "last_error": null, "open_queue": 1, "store_code": "test", "last_status": "ok", "store_label": "Asung IMS test store", "shopify_status": "ACTIVE", "turned_on_by_name": "SHOP2A Manager", "turned_off_by_name": null, "shopify_product_gid": "gid://shopify/Product/9001"}');
select pg_temp.chk('T4b view row (ANN01291): product · no shop_product yet → gid null · open_queue 0 · last_queue_done_at set · payload callable by authenticated · direct insert 42501 · queue update 42501 · anon view 42501',
  :'v_1291' || '/' || :'auth_payload' || '/' || :'a_ins' || '/' || :'a_upd' || '/' || :'anon_view', 'product/ANN01291/null/0/true/ACTIVE/42501/42501/42501');
select pg_temp.chk('T4c real rows untouched: no real listing · shop_product · queue rows outside the fakes (fakes: listings 3 · products 1 · queue 2)',
  (select count(*)::text from public.shop_listing) || '/' || (select count(*)::text from public.shop_product) || '/' || (select count(*)::text from public.shop_push_queue), '3/1/2');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
do $$ begin
  if to_regclass('public.shop_push_queue_id_seq') is not null then
    execute format('select setval(''public.shop_push_queue_id_seq'', greatest(coalesce((select max(id) from public.shop_push_queue), 0), %s, 1), (select count(*) > 0 from public.shop_push_queue))', current_setting('shop2a.q_seq_head', true));
    raise notice 'seq tail queue %', (select last_value::text || ' ' || is_called::text from public.shop_push_queue_id_seq);
  else
    raise notice 'seq tail queue: no table (trial · nothing to restore)';
  end if;
end $$;
