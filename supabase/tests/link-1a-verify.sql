-- link-1a-verify.sql — 기존 Shopify 상품 잇기 DB: 판 표 둘 · 판정 규칙 전부(열아홉 줄) · 실행(gid · hash 심음 · listing 켬/끔 · 큐 0 · 재고 큐) · 판 번호 어긋남 · 권한 · 멱등 · 묶음 보내기 · 남은 수 · 판정 557(payload 변형 = 지금 구성원)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020173401_link_1a_shop_link.sql -f supabase/tests/link-1a-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 G0 는 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더
--   재료는 가짜만(직원 둘 · 스토어 lk · 브랜드 둘 · 제품 · family 둘 · 판 하나 · 줄 열아홉 — 1b 가 채울 원자료를 직접 넣는다) · 시험 스토어(test) 무접촉 = 스냅샷 id 집합 · rollback
--   ⚠️ \gset 줄 끝에 주석 금지 · 변수 이름 접두어

\echo '── db_role · schema_migrations'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261020173401' \gset
select :n_applied as schema_migrations_rows_for_20261020173401;

begin;
set local statement_timeout = '300s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return v;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 새 표를 읽는 도우미는 plpgsql(본문을 만들 때 검사하지 않는다 — sql 함수면 \i 전에 「relation does not exist」로 선다)
create function pg_temp.dec(p_handle text) returns text language plpgsql as $$
declare v text;
begin
  select i.decision || ':' || array_to_string(i.reasons, '+') into v from public.shop_link_item i join public.shop_link_run r on r.id = i.run_id join public.shop_store s on s.id = r.store_id where s.code = 'lk' and i.handle = p_handle;
  return coalesce(v, '(none)');
end $$;
create function pg_temp.sp(p_sku text) returns text language plpgsql as $$
declare v text;
begin
  select sp.shopify_product_gid || '|' || coalesce(sp.last_hash, '-') || '|' || coalesce(sp.last_pushed_at::text, '-') || '|' || coalesce(sp.last_status, '-') into v
    from public.shop_product sp join public.shop_store s on s.id = sp.store_id left join public.product_family f on f.id = sp.family_id left join public.product p on p.id = sp.product_id
   where s.code = 'lk' and coalesce(f.sku, p.sku) = p_sku;
  return coalesce(v, '(none)');
end $$;
create function pg_temp.lon(p_sku text) returns text language plpgsql as $$
declare v text;
begin
  select l.is_on::text || '|' || (l.turned_off_at is not null)::text into v from public.shop_listing l join public.shop_store s on s.id = l.store_id left join public.product_family f on f.id = l.family_id left join public.product p on p.id = l.product_id
   where s.code = 'lk' and coalesce(f.sku, p.sku) = p_sku;
  return coalesce(v, '(none)');
end $$;

\echo '── M0) 직원 둘(shopify · 없음) · 티어 · 실제 shop_* 행 스냅샷(id 집합)'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'link1a-shop@test.invalid', 'LINK1A shop', 'manager', '["ims","shopify"]', '{}') returning auth_user_id::text as g_uid, id::text as st \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'link1a-noperm@test.invalid', 'LINK1A noperm', 'worker', '["ims"]', '{}') returning auth_user_id::text as g_uid2 \gset
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
\set g_claims2 '{"sub":"' :g_uid2 '","role":"authenticated"}'
select id::text as tier from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
create temp table t_real_shop as
  select 'p' as k, sp.id::text as id, sp.shopify_product_gid || '|' || coalesce(sp.last_hash, '') || '|' || coalesce(sp.last_pushed_at::text, '') as v from public.shop_product sp
  union all select 'l', l.id::text, l.is_on::text from public.shop_listing l
  union all select 'v', v.id::text, v.shopify_variant_gid || '|' || coalesce(v.inventory_item_gid, '') from public.shop_variant v
  union all select 'q', q.id::text, coalesce(q.result, 'open') from public.shop_push_queue q;
select count(*) as n_real_shop from t_real_shop \gset
create function pg_temp.md5_real() returns text language sql as $$
  select md5(coalesce(string_agg(t.k || t.id || t.v, '|' order by t.k, t.id), '')) from t_real_shop t
   where (t.k = 'p' and exists (select 1 from public.shop_product x where x.id::text = t.id and x.shopify_product_gid || '|' || coalesce(x.last_hash, '') || '|' || coalesce(x.last_pushed_at::text, '') = t.v))
      or (t.k = 'l' and exists (select 1 from public.shop_listing x where x.id::text = t.id and x.is_on::text = t.v))
      or (t.k = 'v' and exists (select 1 from public.shop_variant x where x.id::text = t.id and x.shopify_variant_gid || '|' || coalesce(x.inventory_item_gid, '') = t.v))
      or (t.k = 'q' and exists (select 1 from public.shop_push_queue x where x.id::text = t.id and coalesce(x.result, 'open') = t.v)) $$;
select md5(coalesce(string_agg(t.k || t.id || t.v, '|' order by t.k, t.id), '')) as md5_real from t_real_shop t \gset
select pg_temp.chk(format('M0 staff ×2 · sale tier · %s real shop rows snapshotted', :n_real_shop), :'g_uid' <> '' and :'g_uid2' <> '' and :'tier' <> '' and :n_real_shop > 0, 'see M0');

\echo '── M1) 가짜 재료 — 스토어 lk · 브랜드 둘 · 제품(낱개 · 세트 · family 둘 · 비활성 · 단종 · 사진 0) · 이미 이어진 것 셋(같은 gid · 다른 gid · Product/0) · 판 하나 · 줄 열아홉'
set local session_replication_role = replica;
insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, secret_prefix, oos_policy, is_active) values ('lk', 'ims-link1a-test.myshopify.com', 'LINK1A', 'asung', :'tier'::uuid, 'LINK1A', 'continue', true) returning id::text as store \gset
insert into public.ref_brand (name, source) values ('LK Brand A', 'manual') returning id::text as bra \gset
insert into public.ref_brand (name, source) values ('LK Brand B', 'manual') returning id::text as brb \gset
insert into public.product_family (sku, name, source, option1_name) values ('LKF1', 'LK Family 1', 'manual', 'Color') returning id::text as f1 \gset
insert into public.product_family (sku, name, source, option1_name) values ('LKF2', 'LK Family 2', 'manual', 'Color') returning id::text as f2 \gset
insert into public.product_family (sku, name, source, option1_name) values ('LKF3', 'LK Family 3', 'manual', 'Size') returning id::text as f3 \gset
insert into public.product (sku, name, source, is_active, sellable, brand_id, brand_name) values
  ('LK-S1', 'LK single 1', 'manual', true, true, :'bra'::uuid, 'LK Brand A'), ('LK-S2', 'LK single 2', 'manual', true, true, :'brb'::uuid, 'LK Brand B'),
  ('LK-INA', 'LK inactive', 'manual', false, true, :'brb'::uuid, 'LK Brand B'), ('LK-D1', 'LK draft', 'manual', true, true, :'bra'::uuid, 'LK Brand A'),
  ('LK-A1', 'LK archived', 'manual', true, true, :'bra'::uuid, 'LK Brand A'), ('LK-C1', 'LK case', 'manual', true, true, :'brb'::uuid, 'LK Brand B'),
  ('LK-N1', 'LK no image', 'manual', true, true, :'brb'::uuid, 'LK Brand B'), ('LK-L1', 'LK linked same', 'manual', true, true, :'bra'::uuid, 'LK Brand A'),
  ('LK-L2', 'LK linked other', 'manual', true, true, :'bra'::uuid, 'LK Brand A'), ('LK-L3', 'LK gid holder', 'manual', true, true, :'bra'::uuid, 'LK Brand A'),
  ('LK-L4', 'LK gid wants', 'manual', true, true, :'bra'::uuid, 'LK Brand A'), ('LK-P0', 'LK product zero', 'manual', true, true, :'brb'::uuid, 'LK Brand B');
insert into public.product (sku, name, source, is_active, sellable, family_id, option1_value, brand_id, brand_name) values
  ('LKF1-RED', 'LK F1 red', 'manual', true, true, :'f1'::uuid, 'Red', :'bra'::uuid, 'LK Brand A'), ('LKF1-BLU', 'LK F1 blue', 'manual', true, true, :'f1'::uuid, 'Blue', :'bra'::uuid, 'LK Brand A'),
  ('LKF1-GRN', 'LK F1 green', 'manual', true, true, :'f1'::uuid, 'Green', :'bra'::uuid, 'LK Brand A'),
  ('LKF2-A', 'LK F2 a', 'manual', true, true, :'f2'::uuid, 'A', :'brb'::uuid, 'LK Brand B'), ('LKF2-B', 'LK F2 b', 'manual', true, true, :'f2'::uuid, 'B', :'brb'::uuid, 'LK Brand B'),
  ('LKF3-X', 'LK F3 x', 'manual', true, true, :'f3'::uuid, 'X', :'brb'::uuid, 'LK Brand B'), ('LKF3-Y', 'LK F3 y', 'manual', true, true, :'f3'::uuid, 'Y', :'brb'::uuid, 'LK Brand B');
update public.product set is_discontinued = true where sku = 'LKF1-BLU';
insert into public.product (sku, name, source, is_active, sellable, parent_product_id, pack_factor, brand_id, brand_name) values
  ('LK-SET', 'LK set 12', 'manual', true, true, (select id from public.product where sku = 'LK-S1'), 12, :'bra'::uuid, 'LK Brand A'),
  ('LK-SETN', 'LK set no sell', 'manual', true, false, (select id from public.product where sku = 'LK-S2'), 6, :'brb'::uuid, 'LK Brand B'),
  ('LK-SETN2', 'LK set no sell 2', 'manual', true, false, (select id from public.product where sku = 'LK-C1'), 6, :'brb'::uuid, 'LK Brand B');
insert into public.product_image (product_id, storage_path, content_type, is_active, is_primary, source)
  select p.id, p.id::text || '/' || gen_random_uuid()::text || '.jpg', 'image/jpeg', true, true, 'manual' from public.product p where p.sku in ('LK-S1', 'LK-S2', 'LK-D1', 'LK-A1', 'LK-C1', 'LK-L1', 'LK-P0', 'LKF1-RED', 'LKF2-A', 'LK-SET');
insert into public.product_tag (product_id, tag, source) select p.id, 'lk-tag', 'manual' from public.product p where p.sku in ('LK-S1', 'LKF1-RED');
-- 이미 이어진 것: L1 같은 gid(보낸 적 있음) · L2 다른 gid · L3 가 gid 1018 을 들고 있다 · (link-1b 뒤) P0 자리표시 행은 없다
insert into public.shop_product (store_id, product_id, shopify_product_gid, handle, shopify_status, last_hash, last_pushed_at, last_status)
  select :'store'::uuid, p.id, 'gid://shopify/Product/1016', 'lk-l1', 'ACTIVE', 'oldhash', now() - interval '1 day', 'ok' from public.product p where p.sku = 'LK-L1';
insert into public.shop_variant (store_id, product_id, shopify_variant_gid, inventory_item_gid) select :'store'::uuid, p.id, 'gid://shopify/ProductVariant/1016', 'gid://shopify/InventoryItem/1016' from public.product p where p.sku = 'LK-L1';
insert into public.shop_product (store_id, product_id, shopify_product_gid, handle, shopify_status) select :'store'::uuid, p.id, 'gid://shopify/Product/9017', 'lk-l2-old', 'ACTIVE' from public.product p where p.sku = 'LK-L2';
insert into public.shop_product (store_id, product_id, shopify_product_gid, handle, shopify_status) select :'store'::uuid, p.id, 'gid://shopify/Product/1018', 'lk-l3', 'ACTIVE' from public.product p where p.sku = 'LK-L3';
insert into public.shop_listing (store_id, product_id, is_on) select :'store'::uuid, p.id, true from public.product p where p.sku = 'LK-L1';
set local session_replication_role = origin;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.chk('M1 fixtures: store lk · 2 brands · 3 families · 22 products · images 10 · 3 pre-existing shop_product rows (same gid · other gid · holder)',
  :'store' <> '' and (select count(*) from public.product where sku like 'LK%') = 22 and (select count(*) from public.shop_product where store_id = :'store'::uuid) = 3, 'see M1');

\if :{?mig}
select pg_temp.chk('G0 before the trial: no shop_link_run · no shop_link_plan · not in schema_migrations',
  to_regclass('public.shop_link_run') is null and to_regprocedure('public.shop_link_plan(uuid)') is null and :n_applied = 0, format('n_applied %s', :n_applied));
\echo '── \i 시험 적용'
\i :mig
\else
select pg_temp.chk('P0c confirm run: migration 20261020173401 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (to_regclass('public.shop_link_item') is not null and to_regprocedure('public.shop_link_apply(uuid, boolean, int)') is not null) as landed \gset
\if :landed
\echo '── M2) 판 하나(read) · 줄 열아홉(1b 가 채울 원자료 모양 그대로) — [link-1b] Product/0 자리표시 가짜 행은 제약 shop_product_gid_real_ck 가 막아 더는 넣지 않는다(lk-p0 는 보통 link · plan 의 Product/0 분기는 옛 데이터 방어로 남는다)'
insert into public.shop_link_run (store_id, status, started_by, read_at, bulk_operation_gid) values (:'store'::uuid, 'read', :'st'::uuid, now(), 'gid://shopify/BulkOperation/777') returning id::text as run \gset
create function pg_temp.v(p_sku text, p_n int, p_opt text default null) returns jsonb language sql as $$
  select jsonb_build_object('sku', p_sku, 'variant_gid', 'gid://shopify/ProductVariant/' || p_n, 'inventory_item_gid', 'gid://shopify/InventoryItem/' || p_n, 'title', coalesce(p_opt, 'Default Title'),
                            'option_values', case when p_opt is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('name', 'color', 'value', p_opt)) end, 'inventory_policy', 'CONTINUE', 'position', 1) $$;
insert into public.shop_link_item (run_id, shopify_product_gid, handle, title, status, options, variants, media) values
  (:'run'::uuid, 'gid://shopify/Product/1001', 'lk-s1', 'LK single 1', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('LK-S1', 1001)), '[{"gid":"gid://shopify/MediaImage/1","url":"x","alt":null}]'),
  (:'run'::uuid, 'gid://shopify/Product/1002', 'lkf1', 'LK Family 1', 'ACTIVE', '[{"name":"Colour","values":["Red","Blue","Green"]}]', jsonb_build_array(pg_temp.v('LKF1-RED', 1021, 'Red'), pg_temp.v('LKF1-BLU', 1022, 'Blue'), pg_temp.v('LKF1-GRN', 1023, 'Green')), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1003', 'lkf2-part', 'LK Family 2 part', 'ACTIVE', '[{"name":"Color","values":["A"]}]', jsonb_build_array(pg_temp.v('LKF2-A', 1031, 'A')), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1004', 'lk-dup-1', 'dup 1', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('LK-S2', 1004)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1005', 'lk-dup-2', 'dup 2', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('LK-S2', 1005)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1006', 'lk-miss-multi', 'missing multi', 'ACTIVE', '[{"name":"Color","values":["B","Z"]}]', jsonb_build_array(pg_temp.v('LKF2-B', 1061, 'B'), pg_temp.v('NOPE-1', 1062, 'Z')), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1007', 'lk-miss-one', 'missing one', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('NOPE-2', 1007)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1008', 'lk-shape-member', 'member as single', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('LKF3-X', 1008)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1009', 'lk-shape-multi', 'singles as family', 'ACTIVE', '[{"name":"Kind","values":["a","b"]}]', jsonb_build_array(pg_temp.v('LK-INA', 1091, 'a'), pg_temp.v('LK-SETN', 1092, 'b')), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1010', 'lk-set', 'LK set 12', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('LK-SET', 1010)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1011', 'lk-setn2', 'set not sellable', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('LK-SETN2', 1011)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1012', 'lk-d1', 'draft', 'DRAFT', '[]', jsonb_build_array(pg_temp.v('LK-D1', 1012)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1013', 'lk-a1', 'archived', 'ARCHIVED', '[]', jsonb_build_array(pg_temp.v('LK-A1', 1013)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1014', 'lk-c1', 'case', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('lk-c1', 1014)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1015', 'lk-n1', 'no image', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('LK-N1', 1015)), '[{"gid":"gid://shopify/MediaImage/2","url":"x","alt":null}]'),
  (:'run'::uuid, 'gid://shopify/Product/1016', 'lk-l1', 'linked same', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('LK-L1', 1016)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1017', 'lk-l2', 'linked other', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('LK-L2', 1017)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1018', 'lk-l4', 'gid elsewhere', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('LK-L4', 1018)), '[]'),
  (:'run'::uuid, 'gid://shopify/Product/1019', 'lk-p0', 'product zero', 'ACTIVE', '[]', jsonb_build_array(pg_temp.v('LK-P0', 1019)), '[]');
select pg_temp.chk('M2 run (read) + 19 items', (select count(*) from public.shop_link_item where run_id = :'run'::uuid) = 19, 'see M2');

\echo '── S1) 판정 — 열아홉 줄 전부'
select pg_temp.run(format('select public.shop_link_plan(%L::uuid)::text', :'run')) as pl1 \gset
select string_agg(i.handle || '=' || i.decision || ':' || array_to_string(i.reasons, '+'), ' | ' order by i.handle) as decs from public.shop_link_item i where i.run_id = :'run'::uuid \gset
select pg_temp.chk('S1 plan: version 1 · counts link 8 · link_off 2 · block 8 · report 1 · each rule lands where expected (dup_sku ×2 · not_in_ims block/report · shape_mismatch ×2 · set_not_sellable · partial_family · option_name_diff+discontinued · sku_case · no_ims_images · already_linked · already_linked_other · gid_linked_elsewhere · plain link (lk-p0) · draft · archived)',
  :'pl1' not like 'ERR%' and (pg_temp.j(:'pl1')->>'version')::int = 1
  and (pg_temp.j(:'pl1')->'counts'->>'link')::int = 8 and (pg_temp.j(:'pl1')->'counts'->>'link_off')::int = 2 and (pg_temp.j(:'pl1')->'counts'->>'block')::int = 8 and (pg_temp.j(:'pl1')->'counts'->>'report')::int = 1
  and pg_temp.dec('lk-s1') = 'link:' and pg_temp.dec('lkf1') = 'link:option_name_diff+discontinued' and pg_temp.dec('lkf2-part') = 'link:partial_family'
  and pg_temp.dec('lk-dup-1') = 'block:dup_sku' and pg_temp.dec('lk-dup-2') = 'block:dup_sku'
  and pg_temp.dec('lk-miss-multi') = 'block:not_in_ims' and pg_temp.dec('lk-miss-one') = 'report:not_in_ims'
  and pg_temp.dec('lk-shape-member') = 'block:shape_mismatch' and pg_temp.dec('lk-shape-multi') = 'block:shape_mismatch'
  and pg_temp.dec('lk-set') = 'link:' and pg_temp.dec('lk-setn2') = 'block:set_not_sellable'
  and pg_temp.dec('lk-d1') = 'link_off:draft' and pg_temp.dec('lk-a1') = 'link_off:archived'
  and pg_temp.dec('lk-c1') = 'link:sku_case' and pg_temp.dec('lk-n1') = 'link:no_ims_images'
  and pg_temp.dec('lk-l1') = 'link:already_linked' and pg_temp.dec('lk-l2') = 'block:already_linked_other' and pg_temp.dec('lk-l4') = 'block:gid_linked_elsewhere' and pg_temp.dec('lk-p0') = 'link:'
  and (select changes->'variants_to_add' from public.shop_link_item where run_id = :'run'::uuid and handle = 'lkf2-part') = '["LKF2-B"]'::jsonb
  and (select ims_family_id::text from public.shop_link_item where run_id = :'run'::uuid and handle = 'lkf1') = :'f1'
  and (select ims_product_id is null and ims_family_id is null from public.shop_link_item where run_id = :'run'::uuid and handle = 'lk-dup-1')
  and (select status from public.shop_link_run where id = :'run'::uuid) = 'planned',
  format('%s | %s', left(:'pl1', 400), :'decs'));

\echo '── S2) 다시 plan → version 2 · 같은 판정 · version 1 로 apply → 거부 · 미리 보기 쓰기 0'
select pg_temp.run(format('select public.shop_link_plan(%L::uuid)::text', :'run')) as pl2 \gset
select string_agg(i.handle || '=' || i.decision || ':' || array_to_string(i.reasons, '+'), ' | ' order by i.handle) as decs2 from public.shop_link_item i where i.run_id = :'run'::uuid \gset
select pg_temp.run(format('select public.shop_link_apply(%L::uuid, true, 1)::text', :'run')) as ap_v1 \gset
select (select count(*) from public.shop_product where store_id = :'store'::uuid) || '|' || (select count(*) from public.shop_listing where store_id = :'store'::uuid) || '|' || (select count(*) from public.shop_variant where store_id = :'store'::uuid) || '|' || (select count(*) from public.shop_stock_queue where store_id = :'store'::uuid) as cnt0 \gset
select pg_temp.run(format('select public.shop_link_apply(%L::uuid, false, 2)::text', :'run')) as ap_pv \gset
select (select count(*) from public.shop_product where store_id = :'store'::uuid) || '|' || (select count(*) from public.shop_listing where store_id = :'store'::uuid) || '|' || (select count(*) from public.shop_variant where store_id = :'store'::uuid) || '|' || (select count(*) from public.shop_stock_queue where store_id = :'store'::uuid) as cnt1 \gset
select pg_temp.chk('S2 plan again → version 2 · identical decisions · apply with version 1 refused ("plan again") · preview (version 2): linked 8 · linked_off 2 · skipped 9 · variants 12 · zero writes · run still planned',
  :'pl2' not like 'ERR%' and (pg_temp.j(:'pl2')->>'version')::int = 2 and :'decs2' = :'decs'
  and :'ap_v1' like 'ERR %version 1 but the run is now version 2%'
  and :'ap_pv' not like 'ERR%' and (pg_temp.j(:'ap_pv')->>'committed') = 'false' and (pg_temp.j(:'ap_pv')->>'linked')::int = 8 and (pg_temp.j(:'ap_pv')->>'linked_off')::int = 2 and (pg_temp.j(:'ap_pv')->>'skipped')::int = 9 and (pg_temp.j(:'ap_pv')->>'variants')::int = 12
  and :'cnt0' = :'cnt1' and (select status from public.shop_link_run where id = :'run'::uuid) = 'planned',
  format('pl2 %s | ap_v1 %s | pv %s | cnt %s → %s', left(:'pl2', 160), left(:'ap_v1', 200), left(:'ap_pv', 300), :'cnt0', :'cnt1'));

\echo '── S3) 실행 — gid · 변형 gid · inventory_item · hash = 그 순간의 payload hash · listing 켬/끔 · push 큐 0 · 재고 큐 켜진 변형만 · L1 의 last_pushed_at 그대로 · P0 자리표시 덮임 · run applied'
select (select count(*) from public.shop_push_queue where store_id = :'store'::uuid and done_at is null) as pq0 \gset
select pg_temp.run(format('select public.shop_link_apply(%L::uuid, true, 2)::text', :'run')) as ap1 \gset
select public.shop_product_payload(:'store'::uuid, null, (select id from public.product where sku = 'LK-S1'))->>'hash' as h_s1 \gset
select public.shop_product_payload(:'store'::uuid, :'f1'::uuid, null)->>'hash' as h_f1 \gset
select public.shop_product_payload(:'store'::uuid, null, (select id from public.product where sku = 'LK-D1'))->>'hash' as h_d1 \gset
select string_agg(p.sku, ',' order by p.sku) as stock_skus from public.shop_stock_queue q join public.product p on p.id = q.product_id where q.store_id = :'store'::uuid \gset
select pg_temp.chk('S3 apply: committed · hash_seeded 10 · shop_product 10 linked (S1 · LKF1 · LKF2 · SET · D1 off · A1 off · C1 · N1 · L1 kept last_pushed_at · P0 linked) · last_hash = payload hash (S1 · LKF1 · D1 archived-state) · listing on ×8 · off ×2 (turned_off_at) · variants 12 with inventory_item_gid · push queue unchanged · stock queue = variants of listings switched on by this apply (no LK-D1 · LK-A1 · no LK-L1 whose listing was already on) · items applied_at on 10 · run applied',
  :'ap1' not like 'ERR%' and (pg_temp.j(:'ap1')->>'committed') = 'true' and (pg_temp.j(:'ap1')->>'hash_seeded')::int = 10
  and pg_temp.sp('LK-S1') = 'gid://shopify/Product/1001|' || :'h_s1' || '|-|pending'
  and pg_temp.sp('LKF1') = 'gid://shopify/Product/1002|' || :'h_f1' || '|-|pending'
  and pg_temp.sp('LK-D1') = 'gid://shopify/Product/1012|' || :'h_d1' || '|-|pending'
  and pg_temp.sp('LK-L1') like 'gid://shopify/Product/1016|%' and pg_temp.sp('LK-L1') not like '%|-|pending' and pg_temp.sp('LK-L1') not like '%|oldhash|%'
  and pg_temp.sp('LK-P0') like 'gid://shopify/Product/1019|%|-|pending' and pg_temp.sp('LK-L2') = 'gid://shopify/Product/9017|-|-|-'
  and pg_temp.lon('LK-S1') = 'true|false' and pg_temp.lon('LKF1') = 'true|false' and pg_temp.lon('LK-D1') = 'false|true' and pg_temp.lon('LK-A1') = 'false|true' and pg_temp.lon('LK-L2') = '(none)'
  and (select count(*) from public.shop_variant v where v.store_id = :'store'::uuid) = 12
  and (select count(*) from public.shop_variant v where v.store_id = :'store'::uuid and v.inventory_item_gid is null) = 0
  and (select v.shopify_variant_gid from public.shop_variant v join public.product p on p.id = v.product_id where v.store_id = :'store'::uuid and p.sku = 'LKF1-GRN') = 'gid://shopify/ProductVariant/1023'
  and (select v.shopify_variant_gid from public.shop_variant v join public.product p on p.id = v.product_id where v.store_id = :'store'::uuid and p.sku = 'LK-C1') = 'gid://shopify/ProductVariant/1014'
  and (select count(*) from public.shop_push_queue where store_id = :'store'::uuid and done_at is null) = :pq0
  and :'stock_skus' = 'LK-C1,LK-N1,LK-P0,LK-S1,LK-SET,LKF1-BLU,LKF1-GRN,LKF1-RED,LKF2-A,LKF2-B'
  and (select count(*) from public.shop_link_item where run_id = :'run'::uuid and applied_at is not null) = 10
  and (select status from public.shop_link_run where id = :'run'::uuid) = 'applied',
  format('ap1 %s | S1 %s | F1 %s | D1 %s | L1 %s | P0 %s | lon %s %s %s %s | variants %s · noinv %s | pq %s→%s | stock %s', left(:'ap1', 300), pg_temp.sp('LK-S1'), pg_temp.sp('LKF1'), pg_temp.sp('LK-D1'), pg_temp.sp('LK-L1'), pg_temp.sp('LK-P0'), pg_temp.lon('LK-S1'), pg_temp.lon('LKF1'), pg_temp.lon('LK-D1'), pg_temp.lon('LK-A1'),
         (select count(*) from public.shop_variant v where v.store_id = :'store'::uuid), (select count(*) from public.shop_variant v where v.store_id = :'store'::uuid and v.inventory_item_gid is null), :pq0, (select count(*) from public.shop_push_queue where store_id = :'store'::uuid and done_at is null), :'stock_skus'));

\echo '── S4) 다시 apply → 거부(applied) · 다시 plan → 거부(applied) · 권한 없는 직원 → 거부 · 새 run 에 같은 줄을 넣고 plan → already_linked(멱등)'
select pg_temp.run(format('select public.shop_link_apply(%L::uuid, true, 2)::text', :'run')) as ap2 \gset
select pg_temp.run(format('select public.shop_link_plan(%L::uuid)::text', :'run')) as pl3 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims2', true) as claims2;
select pg_temp.run(format('select public.shop_link_plan(%L::uuid)::text', :'run')) as pm1 \gset
select pg_temp.run(format('select public.shop_link_push_batch(%L::uuid, ''{}''::jsonb, true, 10)::text', :'store')) as pm2 \gset
reset role;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
insert into public.shop_link_run (store_id, status, started_by, read_at) values (:'store'::uuid, 'read', :'st'::uuid, now()) returning id::text as run2 \gset
insert into public.shop_link_item (run_id, shopify_product_gid, handle, title, status, options, variants, media)
  select :'run2'::uuid, shopify_product_gid, handle, title, status, options, variants, media from public.shop_link_item where run_id = :'run'::uuid and handle in ('lk-s1', 'lkf1', 'lk-d1', 'lk-p0');
select pg_temp.run(format('select public.shop_link_plan(%L::uuid)::text', :'run2')) as pl4 \gset
select pg_temp.chk('S4 re-apply refused (applied) · re-plan refused (applied) · staff without shopify: plan and push_batch refused · second run with the same rows: all already_linked (idempotent · D1 link_off+draft+already_linked)',
  :'ap2' like 'ERR %is applied%' and :'pl3' like 'ERR %is applied%'
  and :'pm1' like 'ERR %cannot change shopify data%' and :'pm2' like 'ERR %cannot change shopify data%'
  and :'pl4' not like 'ERR%' and (select count(*) from public.shop_link_item where run_id = :'run2'::uuid and 'already_linked' = any(reasons)) = 4
  and (select decision from public.shop_link_item where run_id = :'run2'::uuid and handle = 'lk-d1') = 'link_off',
  format('ap2 %s | pl3 %s | pm1 %s | pm2 %s | pl4 %s', left(:'ap2', 120), left(:'pl3', 120), left(:'pm1', 120), left(:'pm2', 120), left(:'pl4', 300)));

\echo '── S5) 남은 수 · 묶음 보내기 — 브랜드 A 미리 보기(쓰기 0) → 실행 limit 2 → 큐 2 · last_hash 비움 · 남은 수(remaining_after) · L1(보낸 적 있음)은 애초에 없다 · tag · kind · sku_like 거르기'
select public.shop_link_remaining(:'store'::uuid)::text as rem0 \gset
select (select count(*) from public.shop_push_queue where store_id = :'store'::uuid and done_at is null) as pqa \gset
select pg_temp.run(format('select public.shop_link_push_batch(%L::uuid, %L::jsonb, false, 200)::text', :'store', '{"brand_id":["' || :'bra' || '"]}')) as pb_pv \gset
select (select count(*) from public.shop_push_queue where store_id = :'store'::uuid and done_at is null) as pq1 \gset
select pg_temp.run(format('select public.shop_link_push_batch(%L::uuid, %L::jsonb, true, 2)::text', :'store', '{"brand_id":["' || :'bra' || '"]}')) as pb1 \gset
select public.shop_link_remaining(:'store'::uuid)::text as rem1 \gset
select string_agg(coalesce(f.sku, p.sku), ',' order by coalesce(f.sku, p.sku)) as queued_skus from public.shop_push_queue q left join public.product_family f on f.id = q.family_id left join public.product p on p.id = q.product_id where q.store_id = :'store'::uuid and q.done_at is null and q.reason = 'link_push' \gset
select pg_temp.run(format('select public.shop_link_push_batch(%L::uuid, %L::jsonb, false, 200)::text', :'store', '{"tag":["lk-tag"]}')) as pb_tag \gset
select pg_temp.run(format('select public.shop_link_push_batch(%L::uuid, %L::jsonb, false, 200)::text', :'store', '{"kind":"family","sku_like":"LKF%"}')) as pb_kind \gset
select pg_temp.chk('S5 remaining 7 (on-listing · gid · never pushed: S1 · LKF1 · LKF2 · SET · C1 · N1 · P0 — L1 pushed before · D1/A1 off) · by_brand A 2 / B 3 / (no brand) 2 · preview brand A picks 2 · zero queue writes · commit limit 2 → picked 2 · queued 2 (LK-S1 · LK-SET by sku) · their last_hash null · remaining_after 5 · remaining() still 7 until the drain pushes · tag filter 2 (LK-S1 · LKF1 via member tag) · kind family + LKF% → 2',
  (pg_temp.j(:'rem0')->>'total')::int = 7
  and (select (b->>'remaining')::int from jsonb_array_elements(pg_temp.j(:'rem0')->'by_brand') b where b->>'brand_name' = 'LK Brand A') = 2
  and (select (b->>'remaining')::int from jsonb_array_elements(pg_temp.j(:'rem0')->'by_brand') b where b->>'brand_name' = 'LK Brand B') = 3
  and (select (b->>'remaining')::int from jsonb_array_elements(pg_temp.j(:'rem0')->'by_brand') b where b->>'brand_name' = '(no brand)') = 2
  and :'pb_pv' not like 'ERR%' and (pg_temp.j(:'pb_pv')->>'picked')::int = 2 and :pqa = :pq1
  and :'pb1' not like 'ERR%' and (pg_temp.j(:'pb1')->>'picked')::int = 2 and (pg_temp.j(:'pb1')->>'queued')::int = 2 and (pg_temp.j(:'pb1')->>'remaining_after')::int = 5
  and :'queued_skus' = 'LK-S1,LK-SET' and pg_temp.sp('LK-S1') like 'gid://shopify/Product/1001|-|-|pending' and pg_temp.sp('LK-SET') like '%|-|-|pending' and pg_temp.sp('LKF1') not like '%|-|-|%'
  and (pg_temp.j(:'rem1')->>'total')::int = 7
  and (pg_temp.j(:'pb_tag')->>'picked')::int = 2 and (pg_temp.j(:'pb_kind')->>'picked')::int = 2,
  format('rem0 total %s | pb_pv picked %s | pb1 picked %s queued %s after %s | rem1 total %s | queued %s | S1 %s | SET %s | LKF1 %s | tag picked %s | kind picked %s | pq %s', pg_temp.j(:'rem0')->>'total', pg_temp.j(:'pb_pv')->>'picked', pg_temp.j(:'pb1')->>'picked', pg_temp.j(:'pb1')->>'queued', pg_temp.j(:'pb1')->>'remaining_after', pg_temp.j(:'rem1')->>'total', :'queued_skus', pg_temp.sp('LK-S1'), pg_temp.sp('LK-SET'), pg_temp.sp('LKF1'), pg_temp.j(:'pb_tag')->>'picked', pg_temp.j(:'pb_kind')->>'picked', :pqa || '→' || :pq1));

\echo '── S6) 판정 557 — payload 의 변형 목록 = 지금 family 구성원(구성원을 빼면 변형에서 빠진다 · 더하면 더해진다)'
select jsonb_array_length(public.shop_product_payload(:'store'::uuid, :'f1'::uuid, null)->'variants') as nv0 \gset
update public.product set family_id = null, option1_value = null where sku = 'LKF1-GRN';
select jsonb_array_length(public.shop_product_payload(:'store'::uuid, :'f1'::uuid, null)->'variants') as nv1 \gset
select string_agg(v->>'sku', ',' order by v->>'sku') as nv1_skus from jsonb_array_elements(public.shop_product_payload(:'store'::uuid, :'f1'::uuid, null)->'variants') v \gset
set local session_replication_role = replica;
insert into public.product (sku, name, source, is_active, sellable, family_id, option1_value) values ('LKF1-YEL', 'LK F1 yellow', 'manual', true, true, :'f1'::uuid, 'Yellow');
set local session_replication_role = origin;
select jsonb_array_length(public.shop_product_payload(:'store'::uuid, :'f1'::uuid, null)->'variants') as nv2 \gset
select pg_temp.chk('S6 ruling 557: LKF1 payload variants 3 → member moved out → 2 (RED · BLU) → new member → 3 — productSet sends exactly these (variants not sent are deleted)',
  :nv0 = 3 and :nv1 = 2 and :'nv1_skus' = 'LKF1-BLU,LKF1-RED' and :nv2 = 3, format('%s → %s (%s) → %s', :nv0, :nv1, :'nv1_skus', :nv2));

\else
select pg_temp.chk('M2 ~ S6 skipped: link-1a not landed (shop_link_item · shop_link_apply missing)', false, 'not landed — nothing to exercise');
\endif

\echo '── Z1) 실제 shop_* 행 무접촉(스냅샷 id 집합 · 시험 스토어 test 포함)'
select pg_temp.chk(format('Z1 %s real shop rows untouched (product gid/hash/pushed · listing on/off · variant gids · queue result)', :n_real_shop), pg_temp.md5_real() = :'md5_real', 'see Z1');

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0'
select (select count(*) from public.shop_store where code = 'lk') + (select count(*) from public.product where sku like 'LK%') + (select count(*) from public.ims_staff where email like 'link1a-%') + (select count(*) from public.ref_brand where name like 'LK Brand%') as fake_traces_left;
