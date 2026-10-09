-- shop-2a2-verify.sql — Shopify ② DB 뒤 절반: shop_queue_add · 큐 트리거 16 · shop_listing_set · shop_queue_all (Asung-IMS · 테스트)
--   기대: 시험 갈래(-v mig) OK 13 · 확인 갈래 OK 12(= 13 − 시험 전용 1: G0a) · MISMATCH 0 · 확인 갈래 전용 줄(\else)은 없다 · 3회차 통과(1회차 4: T4a listing_off 가 큐를 못 넣음 — 마이그레이션 고침(끄기 전에 넣는다) · T3c 열쇠 모양 · 순서 · T5a · T7a 검사 시점 — 기대 쪽 / 2회차 1: T4a 상태를 다시 켠 뒤에 읽음 — 기대 쪽)
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261009204650_shop_2a2_listing_set.sql -f supabase/tests/shop-2a2-verify.sql > /tmp/shop-2a2.out 2>&1; echo exit=$?
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료: 실제 ANN01001FAM · ANN01291 · ANN03907 은 시험 안에서만 켠다(rollback) · 가짜 family SHOP2A-FAM(2a1 과 같은 모양) · 직원 둘 · 큰 갱신은 실제 Annie 상품에 값이 같은 update(rollback · 칸 값 md5 전후 같음 · updated_at 만 trigger 로 움직였다가 되돌아간다) · 끝은 rollback · 큐 identity 는 greatest(max, head)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value::text as q_seq_head from public.shop_push_queue_id_seq \gset
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
select pg_temp.chk('G0a trial marker: shop_listing_set exists only after the trial apply', (to_regprocedure('public.shop_listing_set(jsonb, boolean, text[])') is not null)::text, 'true');
\endif

-- ═══ T1 — 함수 넷 · 트리거 16 · 권한 ═══
select pg_temp.chk('T1a functions 4 (definer) · triggers *_shop_queue 16 (all AFTER STATEMENT) · window executable by authenticated · queue_add/queue_all/trigger not',
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_queue_add', 'shop_queue_trigger', 'shop_listing_set', 'shop_queue_all') and prosecdef)::text || '/' ||
  (select count(*) from pg_trigger where not tgisinternal and tgname like '%\_shop\_queue\_%')::text || '/' || (select count(*) from pg_trigger where not tgisinternal and tgname like '%\_shop\_queue\_%' and (tgtype & 1) = 0)::text || '/' ||
  has_function_privilege('authenticated', 'public.shop_listing_set(jsonb, boolean, text[])', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.shop_queue_add(uuid[], uuid[], text, uuid)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.shop_queue_all(uuid)', 'execute')::text,
  '4/16/16/true/false/false');
select pg_temp.chk('T1b trigger names per table', (select string_agg(c.relname || ':' || n, ',' order by c.relname) from (select tgrelid, count(*) n from pg_trigger where not tgisinternal and tgname like '%\_shop\_queue\_%' group by tgrelid) x join pg_class c on c.oid = x.tgrelid),
  'product:1,product_barcode:3,product_family:1,product_image:3,product_price:3,product_tag:3,ref_brand:1,ref_category:1');

-- ═══ 재료 ═══
select id::text as store from public.shop_store where code = 'test' \gset
select id::text as fam_ann from public.product_family where sku = 'ANN01001FAM' \gset
select id::text as p_1291 from public.product where sku = 'ANN01291' \gset
select id::text as p_3907 from public.product where sku = 'ANN03907' \gset
select id::text as tier_ws from public.ref_price_tier where name = 'Wholesale' \gset
select id::text as brand_annie from public.ref_brand where name = 'Annie' \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'shop2a2-mgr@test.invalid', 'SHOP2A2 Manager', 'manager', '["shopify"]'::jsonb) returning auth_user_id::text as m_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'shop2a2-none@test.invalid', 'SHOP2A2 NoKeys', 'manager', '["master"]'::jsonb) returning auth_user_id::text as n_uid \gset
select s.id::text as m_sid from public.ims_staff s where s.email = 'shop2a2-mgr@test.invalid' \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
\set n_claims '{"sub":"' :n_uid '","role":"authenticated"}'
insert into public.product_family (sku, name, source, brand_id, brand_name, category_name, option1_name, option2_name, cin7_description) values ('SHOP2A-FAM', 'SHOP2A Fake Rollers', 'manual', :'brand_annie'::uuid, 'Annie', 'Fake Category', 'Color', 'Size', '<p>fake family</p>') returning id::text as fam_fake \gset
insert into public.product (sku, name, source, family_id, option1_value, option2_value, brand_id, brand_name, category_name, weight, weight_unit, is_active, sellable)
values ('SHOP2A-P1', 'SHOP2A P1', 'manual', :'fam_fake'::uuid, 'Red', 'Small', :'brand_annie'::uuid, 'Annie', 'Fake Category', 0.05, 'kg', true, true),
       ('SHOP2A-P2', 'SHOP2A P2', 'manual', :'fam_fake'::uuid, 'Red', 'Large', :'brand_annie'::uuid, 'Annie', 'Fake Category', 0, 'kg', true, true),
       ('SHOP2A-P3', 'SHOP2A P3', 'manual', :'fam_fake'::uuid, 'Blue', 'Small', :'brand_annie'::uuid, 'Annie', 'Fake Category', 120, 'g', true, true);
select id::text as f1 from public.product where sku = 'SHOP2A-P1' \gset
select id::text as f3 from public.product where sku = 'SHOP2A-P3' \gset
insert into public.product (sku, name, source, parent_product_id, pack_factor, brand_name, is_active, sellable) values ('SHOP2A-P1-6', 'SHOP2A P1 set', 'manual', :'f1'::uuid, 6, 'Annie', true, false);
insert into public.product (sku, name, source, brand_name, is_active, sellable) values ('SHOP2A-LONE', 'SHOP2A lone single (no listing)', 'manual', 'Annie', true, true) returning id::text as lone \gset
insert into public.product_price (product_id, tier_id, price, source) values (:'f1'::uuid, :'tier_ws'::uuid, 2.50, 'manual'), ((select id from public.product where sku = 'SHOP2A-P2'), :'tier_ws'::uuid, 2.75, 'manual'), (:'lone'::uuid, :'tier_ws'::uuid, 1.00, 'manual');
insert into public.product_image (product_id, storage_path, content_type, is_primary, sort_order, source) values (:'f1'::uuid, :'f1' || '/a.jpg', 'image/jpeg', true, 1, 'manual'), (:'lone'::uuid, :'lone' || '/z.jpg', 'image/jpeg', true, 1, 'manual');
select id::text as img_a from public.product_image where storage_path = :'f1' || '/a.jpg' \gset
select id::text as img_z from public.product_image where storage_path = :'lone' || '/z.jpg' \gset
select md5(string_agg(p.sku || '|' || p.name || '|' || coalesce(p.note, '') || '|' || coalesce(p.brand_name, ''), ',' order by p.sku)) as annie_md5_head, count(*)::text as annie_n from public.product p where p.brand_id = :'brand_annie'::uuid and p.sku not like 'SHOP2A%' \gset

-- ═══ T2 — 문 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'n_claims', true);
do $$ begin perform public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'family_sku', 'ANN01001FAM', 'old', null)), true); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as t2_nokey \gset
reset role;
select pg_temp.chk('T2a staff without the shopify key: door refuses', (:'t2_nokey' like 'P0001 You cannot change shopify data%')::text, 'true');

-- ═══ T3 — listing_on · 막기 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'family_sku', 'ANN01001FAM', 'old', null)), false)::text as t3_pre \gset
select (select count(*) from public.shop_listing)::text || '/' || (select count(*) from public.shop_push_queue)::text as t3_pre_n \gset
select public.shop_listing_set(jsonb_build_array(
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'family_sku', 'ANN01001FAM', 'old', null),
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'sku', 'ANN01291', 'old', null),
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'sku', 'ANN03907', 'old', null)), true)::text as t3_on \gset
select public.shop_listing_set(jsonb_build_array(
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'sku', 'ANN01001', 'old', null),
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'sku', 'SHOP2A-P1-6', 'old', null),
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'family_sku', 'SHOP2A-FAM', 'old', null),
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'sku', 'NOPE-SKU', 'old', null),
  jsonb_build_object('op', 'listing_on', 'store_code', 'nope', 'sku', 'ANN01291', 'old', null),
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'sku', 'ANN01291', 'old', null),
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'sku', 'ANN03907', 'old', 'true'),
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'sku', 'ANN03907', 'old', 'true'),
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'family_sku', 'ANN01001FAM', 'sku', 'ANN01291', 'old', null),
  jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'sku', 'SHOP2A-LONE')), true)::text as t3_bad \gset
reset role;
select pg_temp.chk('T3a preview: committed false · no listing · no queue', (:'t3_pre'::jsonb->>'committed') || '/' || :'t3_pre_n', 'false/0/0');
select pg_temp.chk('T3b commit: three listings on (family + 2 singles) · turned_on_by manager · three queue rows reason listing_on · queue_id in changes',
  (:'t3_on'::jsonb->>'committed') || '/' || (select count(*)::text || '/' || bool_and(l.is_on and l.turned_on_by = :'m_sid'::uuid)::text from public.shop_listing l) || '/' || (select count(*)::text || '/' || string_agg(distinct q.reason, ',') from public.shop_push_queue q where q.done_at is null) || '/' || (select count(*)::text from jsonb_array_elements(:'t3_on'::jsonb->'changes') c where (c->>'queue_id') is not null and (c->>'applied') = 'true'),
  'true/3/true/3/listing_on/3');
select pg_temp.chk('T3c blocks: family member · set not sellable · fake family no_price P3 · unknown sku · unknown store (key without store) · ANN01291 old null while on → changed_elsewhere (old check first) · ANN03907 old true → already_on · duplicate in call · both targets · old missing · nothing saved',
  (select string_agg(b->>'key', ',' order by b->>'key') from jsonb_array_elements(:'t3_bad'::jsonb->'blocks') b) || '/' || (select count(*)::text from public.shop_listing),
  'ANN01001FAM:target_invalid,ANN01291:store_unknown,NOPE-SKU:target_unknown,test:ANN01001:family_member_goes_with_family,test:ANN01291:changed_elsewhere,test:ANN03907:already_on,test:ANN03907:field_duplicate_in_call,test:SHOP2A-FAM:no_price:SHOP2A-P3,test:SHOP2A-LONE:old_missing,test:SHOP2A-P1-6:set_not_sellable/3');

-- ═══ T4 — listing_off · push_now ═══
update public.shop_push_queue set started_at = now(), done_at = now(), result = 'ok' where done_at is null;                -- 큐를 비운 척(EF 가 하는 일)
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'listing_off', 'store_code', 'test', 'sku', 'ANN03907', 'old', 'true')), true)::text as t4_off \gset
select (not l.is_on)::text || '|' || (l.turned_off_by = :'m_sid'::uuid)::text || '|' || (select q.reason from public.shop_push_queue q where q.product_id = :'p_3907'::uuid and q.done_at is null) as t4_off_state from public.shop_listing l where l.product_id = :'p_3907'::uuid \gset
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'push_now', 'store_code', 'test', 'sku', 'ANN03907')), true)::text as t4_push_off \gset
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'push_now', 'store_code', 'test', 'family_sku', 'ANN01001FAM')), true)::text as t4_push \gset
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'push_now', 'store_code', 'test', 'family_sku', 'ANN01001FAM')), true)::text as t4_push2 \gset
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'listing_off', 'store_code', 'test', 'sku', 'ANN03907', 'old', 'false')), true)::text as t4_off2 \gset
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'sku', 'ANN03907', 'old', 'false')), true)::text as t4_on2 \gset
reset role;
select pg_temp.chk('T4a listing_off: is_on false · turned_off_by · queue row reason listing_off · push_now on an off listing → listing_off block · push_now → queue row reason push_now · second push_now reuses the open row (same queue_id) · off again → already_off · on again → is_on true · turned_off cleared',
  (:'t4_off'::jsonb->>'committed') || '/' || :'t4_off_state' || '/' || (:'t4_push_off'::jsonb->'blocks'->0->>'code') || '/' ||
  (select q.reason from public.shop_push_queue q where q.family_id = :'fam_ann'::uuid and q.done_at is null) || '/' || ((:'t4_push'::jsonb->'changes'->0->>'queue_id') = (:'t4_push2'::jsonb->'changes'->0->>'queue_id'))::text || '/' || (:'t4_off2'::jsonb->'blocks'->0->>'code') || '/' || (select l.is_on::text || '|' || coalesce(l.turned_off_at::text, 'null') from public.shop_listing l where l.product_id = :'p_3907'::uuid),
  'true/true|true|listing_off/listing_off/push_now/true/already_off/true|null');

-- ═══ T5 — family_web_image_set ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'family_web_image_set', 'family_sku', 'SHOP2A-FAM', 'product_image_id', :'img_z', 'old', null)), true)::text as t5_bad \gset
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'family_web_image_set', 'family_sku', 'SHOP2A-FAM', 'product_image_id', :'img_a', 'old', null)), true)::text as t5_set \gset
select (coalesce(f.web_image_id::text, 'null') = :'img_a')::text as t5_set_val from public.product_family f where f.id = :'fam_fake'::uuid \gset
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'family_web_image_set', 'family_sku', 'SHOP2A-FAM', 'product_image_id', null, 'old', :'img_a')), true)::text as t5_null \gset
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'family_web_image_set', 'sku', 'ANN01291', 'product_image_id', null, 'old', null)), true)::text as t5_sku \gset
reset role;
select pg_temp.chk('T5a web image: another product''s photo → image_not_in_family · own variant photo → set · null → cleared · sku instead of family_sku → target_invalid',
  (:'t5_bad'::jsonb->'blocks'->0->>'code') || '/' || (:'t5_set'::jsonb->>'committed') || '/' || :'t5_set_val' || '/' || (:'t5_null'::jsonb->>'committed') || '/' || (select coalesce(f.web_image_id::text, 'null') from public.product_family f where f.id = :'fam_fake'::uuid) || '/' || (:'t5_sku'::jsonb->'blocks'->0->>'code'),
  'image_not_in_family/true/true/true/null/target_invalid');

-- ═══ T6 — 큐 트리거 ═══
insert into public.product_price (product_id, tier_id, price, source) values (:'f3'::uuid, :'tier_ws'::uuid, 2.00, 'manual');       -- 가짜 family 를 켤 수 있게
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.shop_listing_set(jsonb_build_array(jsonb_build_object('op', 'listing_on', 'store_code', 'test', 'family_sku', 'SHOP2A-FAM', 'old', null)), true)::text as t6_on \gset
reset role;
update public.shop_push_queue set started_at = now(), done_at = now(), result = 'ok' where done_at is null;
update public.product_price set price = 2.60 where product_id = :'f1'::uuid and tier_id = :'tier_ws'::uuid;
select count(*)::text as t6_q1 from public.shop_push_queue where done_at is null \gset
update public.product set note = 'touched' where family_id = :'fam_fake'::uuid;                     -- 세 행 한 문장 → 열린 줄은 그대로 하나
select count(*)::text || '/' || string_agg(q.reason, ',') as t6_q2 from public.shop_push_queue q where q.done_at is null \gset
update public.product set note = 'lone' where id = :'lone'::uuid;                                   -- listing 없는 낱개 → 큐 없음
update public.product_price set price = 1.10 where product_id = :'lone'::uuid;
select count(*)::text as t6_q3 from public.shop_push_queue where done_at is null \gset
update public.shop_push_queue set started_at = now(), done_at = now(), result = 'ok' where done_at is null;
insert into public.product_image (product_id, storage_path, content_type, is_primary, sort_order, source) values (:'f3'::uuid, :'f3' || '/n.jpg', 'image/jpeg', true, 1, 'manual');
delete from public.product_image where storage_path = :'f3' || '/n.jpg';
select count(*)::text || '/' || string_agg(q.reason, ',') as t6_q4 from public.shop_push_queue q where q.done_at is null \gset
update public.shop_push_queue set started_at = now(), done_at = now(), result = 'ok' where done_at is null;
update public.ref_brand set note = coalesce(note, '') where id = :'brand_annie'::uuid;              -- 이름 그대로 → 큐 없음
select count(*)::text as t6_q5 from public.shop_push_queue where done_at is null \gset
update public.ref_brand set name = 'Annie' where id = :'brand_annie'::uuid;                           -- 같은 이름 → 큐 없음
select count(*)::text as t6_q5b from public.shop_push_queue where done_at is null \gset
update public.ref_brand set name = 'Annie X' where id = :'brand_annie'::uuid;                         -- 이름 바뀜 → Annie 의 켜진 대상 넷(fam_ann · 1291 · 3907 · fam_fake)
select count(*)::text || '/' || string_agg(distinct q.reason, ',') as t6_q6 from public.shop_push_queue q where q.done_at is null \gset
update public.ref_brand set name = 'Annie' where id = :'brand_annie'::uuid;
select pg_temp.chk('T6a price change on a listed family member → 1 open row (product_price) · 3-row product update in one statement → still 1 · unlisted single → none',
  (:'t6_on'::jsonb->>'committed') || '/' || :'t6_q1' || '/' || :'t6_q2' || '/' || :'t6_q3', 'true/1/1/product_price/1');
select pg_temp.chk('T6b image insert + delete → 1 open row (product_image) · ref_brand note-only / same-name updates → 0 · brand renamed → 4 (reason ref_brand)', :'t6_q4' || '/' || :'t6_q5' || '/' || :'t6_q5b' || '/' || :'t6_q6', '1/product_image/0/0/4/ref_brand');

-- ═══ T7 — 큰 갱신 시간(실제 Annie 상품 · 값 같은 update · rollback) ═══
select clock_timestamp() as t7_0 \gset
update public.product set note = note where brand_id = :'brand_annie'::uuid;
select clock_timestamp() as t7_1 \gset
update public.product_price set price = price where product_id in (select id from public.product where brand_id = :'brand_annie'::uuid);
select clock_timestamp() as t7_2 \gset
select count(*)::text as t7_n from public.product_price where product_id in (select id from public.product where brand_id = :'brand_annie'::uuid) \gset
select round(extract(epoch from (:'t7_1'::timestamptz - :'t7_0'::timestamptz)) * 1000)::text as t7_ms_p, round(extract(epoch from (:'t7_2'::timestamptz - :'t7_1'::timestamptz)) * 1000)::text as t7_ms_pp \gset
\echo '── T7 큰 갱신 시간: product Annie' :annie_n '행' :t7_ms_p 'ms · product_price' :t7_n '행' :t7_ms_pp 'ms'
select pg_temp.chk('T7a big updates: product (Annie ~1,516 rows) and product_price rows each under 5 s · open queue stays 4 (one per listed target · no per-row rows) · Annie column values unchanged (md5)',
  (:'t7_ms_p'::int < 5000)::text || '/' || (:'t7_ms_pp'::int < 5000)::text || '/' || (select count(*)::text from public.shop_push_queue where done_at is null) || '/' || ((select md5(string_agg(p.sku || '|' || p.name || '|' || coalesce(p.note, '') || '|' || coalesce(p.brand_name, ''), ',' order by p.sku)) from public.product p where p.brand_id = :'brand_annie'::uuid and p.sku not like 'SHOP2A%') = :'annie_md5_head')::text,
  'true/true/4/true');

-- ═══ T8 — shop_queue_all ═══
update public.shop_push_queue set started_at = now(), done_at = now(), result = 'ok' where done_at is null;
select public.shop_queue_all(:'store'::uuid)::text as t8_a \gset
select public.shop_queue_all(:'store'::uuid)::text as t8_b \gset
select public.shop_queue_all(null)::text as t8_c \gset
select pg_temp.chk('T8a nightly: 4 listed-on targets queued (reason nightly) · again → 0 (open rows exist) · all stores → 0', :'t8_a' || '/' || (select string_agg(distinct q.reason, ',') from public.shop_push_queue q where q.done_at is null) || '/' || :'t8_b' || '/' || :'t8_c', '4/nightly/0/0');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select 'after rollback: listings ' || (select count(*) from public.shop_listing) || ' · queue ' || (select count(*) from public.shop_push_queue) || ' (both 0 = nothing stuck)';
select setval('public.shop_push_queue_id_seq', greatest(coalesce((select max(id) from public.shop_push_queue), 0), :q_seq_head::bigint, 1), (select count(*) > 0 from public.shop_push_queue));
select 'seq tail queue ' || last_value || ' ' || is_called from public.shop_push_queue_id_seq;
