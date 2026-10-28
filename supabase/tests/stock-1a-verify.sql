-- stock-1a-verify.sql — Shopify ③ 재고 올리기 DB: shop_stock_sent · shop_stock_queue · targets · payload · queue_add · 트리거 13 · diff · all · shop_queue_all 재발행 · 뷰 (Asung-IMS · 테스트)
--   기대: 시험 갈래(-v mig) OK 30 · 확인 갈래 OK 29(= 30 − 시험 전용 1: G0a) · MISMATCH 0 · 확인 갈래 전용 줄(\else)은 없다 · 1회차 OK 27(NOTICE 는 30) — savepoint 안의 chk 셋(T4a · T4b · T9b)이 되감기에 지워졌다 → 측정은 안에서 · chk 는 되감은 뒤에(2회차)
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261010194732_stock_1a_queue.sql -f supabase/tests/stock-1a-verify.sql > /tmp/stock-1a.out 2>&1; echo exit=$?
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료: 실제 ANN01001FAM(켜짐 · 구성원 10) · ANN03907(켜짐) · ANN01291(꺼짐) 은 그대로 · BEL43475-12(sellable 세트)는 시험 안에서 직접 insert 로 켠다(rollback) · 가짜 원장 줄(doc STOCK1A-*) · 가짜 트랜스퍼(STOCK1A-T1)
--   ⚠️ 실제 행을 바꾸는 갈래는 둘 뿐 — T4 ANN01015 sellable 끄기(savepoint 안 · 되감은 뒤 행 md5 같음을 센다) · T10 Annie 상품 값 같은 update(2a2 T7 과 같은 결)
--   기대값은 손으로 적지 않는다 — 가용은 같은 파일 안에서 inv_available_base 로 다시 센다(stock-0 실물 ANN01001 32/8 · ANN03907 43/1 · BEL43475-12 12/2 는 \echo 로만)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value::text as q_seq_head from public.shop_push_queue_id_seq \gset
select coalesce((select last_value::text from pg_sequences where schemaname = 'public' and sequencename = 'shop_stock_queue_id_seq'), '0') as sq_seq_head \gset
\echo '== head push seq' :q_seq_head '· stock seq' :sq_seq_head

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
create function pg_temp.open_stock(p_store uuid) returns text language sql security definer as $$
  select coalesce(string_agg(p.sku || ':' || q.reason || ':' || q.force::text, ',' order by p.sku), '') from public.shop_stock_queue q join public.product p on p.id = q.product_id where q.store_id = p_store and q.done_at is null;
$$;
create function pg_temp.close_stock() returns void language sql security definer as $$
  update public.shop_stock_queue set started_at = now(), done_at = now(), result = 'ok' where done_at is null;
$$;
\if :{?mig}
select pg_temp.chk('G0a trial marker: shop_stock_payload exists only after the trial apply', (to_regprocedure('public.shop_stock_payload(uuid, uuid[])') is not null)::text, 'true');
\endif

-- ═══ T1 — 객체 · 권한 ═══
select pg_temp.chk('T1a tables 2 (rls on · select policy) · functions 6 (definer 4: queue_add · trigger · diff · all) · triggers *_shop_stock_* 16 (all AFTER STATEMENT · shop-combo-1 product_bom 3) · view 1',
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname in ('shop_stock_sent', 'shop_stock_queue') and c.relrowsecurity)::text || '/' ||
  (select count(*) from pg_policies where schemaname = 'public' and tablename in ('shop_stock_sent', 'shop_stock_queue') and cmd = 'SELECT')::text || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_stock_targets', 'shop_stock_payload', 'shop_stock_queue_add', 'shop_stock_queue_trigger', 'shop_stock_queue_diff', 'shop_stock_queue_all'))::text || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_stock_queue_add', 'shop_stock_queue_trigger', 'shop_stock_queue_diff', 'shop_stock_queue_all') and prosecdef)::text || '/' ||
  (select count(*) from pg_trigger where not tgisinternal and tgname like '%\_shop\_stock\_%')::text || '/' || (select count(*) from pg_trigger where not tgisinternal and tgname like '%\_shop\_stock\_%' and (tgtype & 1) = 0)::text || '/' ||
  (to_regclass('public.shop_stock_list') is not null)::text,
  '2/2/6/4/16/16/true');
select pg_temp.chk('T1b trigger names per table', (select string_agg(c.relname || ':' || n, ',' order by c.relname) from (select tgrelid, count(*) n from pg_trigger where not tgisinternal and tgname like '%\_shop\_stock\_%' group by tgrelid) x join pg_class c on c.oid = x.tgrelid),
  'inv_ledger:3,inv_transfer:1,inv_transfer_line:3,product:1,product_bom:3,shop_listing:2,so_reserve:3');
select pg_temp.chk('T1c authenticated: select on both tables + view · no insert/update/delete · no execute on the six functions · anon nothing',
  has_table_privilege('authenticated', 'public.shop_stock_sent', 'select')::text || has_table_privilege('authenticated', 'public.shop_stock_queue', 'select')::text || has_table_privilege('authenticated', 'public.shop_stock_list', 'select')::text || '/' ||
  (has_table_privilege('authenticated', 'public.shop_stock_sent', 'insert') or has_table_privilege('authenticated', 'public.shop_stock_sent', 'update') or has_table_privilege('authenticated', 'public.shop_stock_sent', 'delete') or has_table_privilege('authenticated', 'public.shop_stock_queue', 'insert') or has_table_privilege('authenticated', 'public.shop_stock_queue', 'update') or has_table_privilege('authenticated', 'public.shop_stock_queue', 'delete'))::text || '/' ||
  (has_function_privilege('authenticated', 'public.shop_stock_targets(uuid, uuid[])', 'execute') or has_function_privilege('authenticated', 'public.shop_stock_payload(uuid, uuid[])', 'execute') or has_function_privilege('authenticated', 'public.shop_stock_queue_add(uuid, uuid[], text, boolean)', 'execute') or has_function_privilege('authenticated', 'public.shop_stock_queue_trigger()', 'execute') or has_function_privilege('authenticated', 'public.shop_stock_queue_diff(uuid)', 'execute') or has_function_privilege('authenticated', 'public.shop_stock_queue_all(uuid)', 'execute'))::text || '/' ||
  (has_table_privilege('anon', 'public.shop_stock_sent', 'select') or has_table_privilege('anon', 'public.shop_stock_queue', 'select') or has_table_privilege('anon', 'public.shop_stock_list', 'select'))::text,
  'truetruetrue/false/false/false');

-- ═══ 재료 ═══
select id::text as store from public.shop_store where code = 'test' \gset
select id::text as wh_to from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as wh_ed from public.ref_warehouse where name = 'Asung - Edmonton' \gset
select id::text as p_1001 from public.product where sku = 'ANN01001' \gset
select id::text as p_1015 from public.product where sku = 'ANN01015' \gset
select id::text as p_3907 from public.product where sku = 'ANN03907' \gset
select id::text as p_1291 from public.product where sku = 'ANN01291' \gset
select id::text as p_bel from public.product where sku = 'BEL43475' \gset
select id::text as p_bel12, pack_factor::text as bel12_pf from public.product where sku = 'BEL43475-12' \gset
select id::text as brand_annie from public.ref_brand where name = 'Annie' \gset
select count(*)::text as annie_n from public.product where brand_id = :'brand_annie'::uuid \gset
select pg_temp.close_stock();
select pg_temp.chk('T0 fixtures: test store · listings on = family ANN01001FAM + ANN03907 · ANN01291 off · BEL43475-12 sellable set (pack 12) with no listing · 12 shop_variant rows all with inventory_item_gid · stock queue empty',
  (select count(*)::text from public.shop_listing l where l.store_id = :'store'::uuid and l.is_on) || '/' || (select is_on::text from public.shop_listing where product_id = :'p_1291'::uuid) || '/' ||
  (select (sellable and parent_product_id = :'p_bel'::uuid)::text from public.product where id = :'p_bel12'::uuid) || '/' || :bel12_pf || '/' || (select count(*)::text from public.shop_listing where product_id = :'p_bel12'::uuid) || '/' ||
  (select count(*)::text || '/' || count(*) filter (where inventory_item_gid is not null)::text from public.shop_variant where store_id = :'store'::uuid) || '/' || (select count(*)::text from public.shop_stock_queue where done_at is null),
  '2/false/true/12/0/12/12/0');

-- ═══ T2 — targets · payload 숫자(가용은 파일 안에서 inv_available_base 로 다시 센다) ═══
select (b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea)::text as av_1001_to from public.inv_available_base(:'wh_to'::uuid, array[:'p_1001'::uuid]) b \gset
select (b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea)::text as av_1001_ed from public.inv_available_base(:'wh_ed'::uuid, array[:'p_1001'::uuid]) b \gset
select (b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea)::text as av_3907_to from public.inv_available_base(:'wh_to'::uuid, array[:'p_3907'::uuid]) b \gset
select (b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea)::text as av_3907_ed from public.inv_available_base(:'wh_ed'::uuid, array[:'p_3907'::uuid]) b \gset
select (b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea)::text as av_bel_to from public.inv_available_base(:'wh_to'::uuid, array[:'p_bel'::uuid]) b \gset
select (b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea)::text as av_bel_ed from public.inv_available_base(:'wh_ed'::uuid, array[:'p_bel'::uuid]) b \gset
\echo '── 가용(inv_available_base): ANN01001 Toronto' :av_1001_to 'Edmonton' :av_1001_ed '· ANN03907 Toronto' :av_3907_to 'Edmonton' :av_3907_ed '· BEL43475 Toronto' :av_bel_to 'Edmonton' :av_bel_ed '(stock-0 실물 32/8 · 43/1 · 150/24)'
select pg_temp.chk('T2a targets(store): 11 variants (10 family members + ANN03907) · ANN01291 absent · narrowed to ANN01001+ANN01291 → 1',
  (select count(*)::text from public.shop_stock_targets(:'store'::uuid, null)) || '/' || (select count(*)::text from public.shop_stock_targets(:'store'::uuid, null) t where t.product_id = :'p_1291'::uuid) || '/' ||
  (select count(*)::text from public.shop_stock_targets(:'store'::uuid, array[:'p_1001'::uuid, :'p_1291'::uuid])),
  '11/0/1');
select pg_temp.chk('T2b payload(store, all): 22 rows (11 × 2 locations) · blocks all [] · is_off none · location gids are the two shop_location rows · ANN01291 absent',
  (select count(*)::text || '/' || count(*) filter (where blocks = '[]'::jsonb)::text || '/' || count(*) filter (where is_off)::text || '/' || count(distinct location_gid)::text || '/' || count(*) filter (where product_id = :'p_1291'::uuid)::text from public.shop_stock_payload(:'store'::uuid, null)),
  '22/22/0/2/0');
select pg_temp.chk('T2c payload numbers = inv_available_base (ANN01001 Toronto/Edmonton · ANN03907 Toronto/Edmonton) · narrowed call gives the same',
  (select string_agg(x.sku || ':' || x.quantity::text, ',' order by x.sku, x.warehouse_id = :'wh_to'::uuid desc) from public.shop_stock_payload(:'store'::uuid, array[:'p_1001'::uuid, :'p_3907'::uuid]) x) || '|' ||
  (select string_agg(x.sku || ':' || x.quantity::text, ',' order by x.sku, x.warehouse_id = :'wh_to'::uuid desc) from public.shop_stock_payload(:'store'::uuid, null) x where x.product_id in (:'p_1001'::uuid, :'p_3907'::uuid)),
  'ANN01001:' || greatest(0, floor(:av_1001_to::numeric))::text || ',ANN01001:' || greatest(0, floor(:av_1001_ed::numeric))::text || ',ANN03907:' || greatest(0, floor(:av_3907_to::numeric))::text || ',ANN03907:' || greatest(0, floor(:av_3907_ed::numeric))::text || '|' ||
  'ANN01001:' || greatest(0, floor(:av_1001_to::numeric))::text || ',ANN01001:' || greatest(0, floor(:av_1001_ed::numeric))::text || ',ANN03907:' || greatest(0, floor(:av_3907_to::numeric))::text || ',ANN03907:' || greatest(0, floor(:av_3907_ed::numeric))::text);
select pg_temp.chk('T2d negative available → 0: a product whose IN_TRANSIT/any warehouse is negative never yields a negative quantity (whole payload min ≥ 0)',
  (select (min(quantity) >= 0)::text from public.shop_stock_payload(null, null)), 'true');

-- ═══ T3 — sellable 세트 켜기(직접 insert · shop_listing_shop_stock_i → force 줄) · 세트 ⌊낱개 ÷ 12⌋ · inventory_item 없음 → blocks ═══
insert into public.shop_listing (store_id, product_id, is_on, turned_on_at) values (:'store'::uuid, :'p_bel12'::uuid, true, now());
select pg_temp.chk('T3a listing_on(set) → 1 open stock row for the set · reason listing_on · force true · set appears in targets (12) · payload Toronto/Edmonton = floor(BEL43475 avail / 12) · blocks no_inventory_item',
  pg_temp.open_stock(:'store'::uuid) || '/' || (select count(*)::text from public.shop_stock_targets(:'store'::uuid, null)) || '/' ||
  (select string_agg(x.quantity::text || ':' || x.blocks::text, ',' order by x.warehouse_id = :'wh_to'::uuid desc) from public.shop_stock_payload(:'store'::uuid, array[:'p_bel12'::uuid]) x),
  'BEL43475-12:listing_on:true/12/' || greatest(0, floor(:av_bel_to::numeric / :bel12_pf))::text || ':["no_inventory_item"],' || greatest(0, floor(:av_bel_ed::numeric / :bel12_pf))::text || ':["no_inventory_item"]');
select pg_temp.close_stock();
update public.shop_listing set note = note where product_id = :'p_bel12'::uuid;
update public.shop_listing set is_on = false, turned_off_at = now() where product_id = :'p_bel12'::uuid;
select pg_temp.chk('T3b note-only update → 0 rows · turning off → 0 rows (판정 425: 끄는 순간 안 보냄) · set no longer in targets',
  pg_temp.open_stock(:'store'::uuid) || '/' || (select count(*)::text from public.shop_stock_targets(:'store'::uuid, array[:'p_bel12'::uuid])), '/0');
update public.shop_listing set is_on = true, turned_off_at = null where product_id = :'p_bel12'::uuid;
select pg_temp.chk('T3c off → on again → 1 force row (다시 켜면 그때 전부)', pg_temp.open_stock(:'store'::uuid), 'BEL43475-12:listing_on:true');
select pg_temp.close_stock();

-- ═══ T4 — 구성원 끄기 → 0 (savepoint · 실제 행은 되감는다 · md5 전후) ═══
select md5(row(p.*)::text) as md5_1015 from public.product p where p.id = :'p_1015'::uuid \gset
savepoint t4;
update public.product set sellable = false where id = :'p_1015'::uuid;
select pg_temp.open_stock(:'store'::uuid) || '/' || (select string_agg(x.quantity::text || ':' || x.is_off::text, ',') from public.shop_stock_payload(:'store'::uuid, array[:'p_1015'::uuid]) x) || '/' ||
  (select count(*)::text from public.shop_stock_payload(:'store'::uuid, array[:'p_1001'::uuid]) x where x.is_off) as t4_a \gset
update public.product set note = note where id = :'p_1015'::uuid;
select pg_temp.open_stock(:'store'::uuid) as t4_b \gset
rollback to savepoint t4;
select pg_temp.chk('T4a member sellable off → 1 stock row (reason product) · payload ANN01015 = 0/0 · is_off true · other members untouched (measured inside the savepoint)', :'t4_a', 'ANN01015:product:false/0:true,0:true/0');
select pg_temp.chk('T4b note-only product update → no new stock row (filter on is_active · sellable · pack_factor · parent)', :'t4_b', 'ANN01015:product:false');
select pg_temp.chk('T4c after rollback to savepoint: ANN01015 row md5 unchanged · stock queue back to 0 open', ((select md5(row(p.*)::text) from public.product p where p.id = :'p_1015'::uuid) = :'md5_1015')::text || '/' || pg_temp.open_stock(:'store'::uuid), 'true/');

-- ═══ T5 — 원장(sku → product · 낱개 → 켜진 sellable 세트 · 꺼진 listing 0 · 같은 대상 두 번 → 열린 줄 하나) ═══
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
values (current_date, 1, 'BEL43475', 'Asung Trading Inc.', 'B061102', 0, 'adjust_existing', 'adjustment', 'STOCK1A-TEST', 'L1', 'manual');
select pg_temp.chk('T5a ledger row for BEL43475 (single · not listed) → its listed sellable set BEL43475-12 queued (reason inv_ledger) · nothing else', pg_temp.open_stock(:'store'::uuid), 'BEL43475-12:inv_ledger:false');
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
values (current_date, 1, 'BEL43475', 'Asung - Edmonton', 'EU060502', 0, 'adjust_existing', 'adjustment', 'STOCK1A-TEST', 'L2', 'manual'),
       (current_date, 1, 'ANN01291', 'Asung Trading Inc.', 'B030901', 0, 'adjust_existing', 'adjustment', 'STOCK1A-TEST', 'L3', 'manual'),
       (current_date, 1, 'ANN01001', 'Asung Trading Inc.', 'B031103', 0, 'adjust_existing', 'adjustment', 'STOCK1A-TEST', 'L4', 'manual');
select pg_temp.chk('T5b 3-row insert: BEL43475 again → still one open row · ANN01291 (listing off) → none · ANN01001 (family member) → 1 row', pg_temp.open_stock(:'store'::uuid), 'ANN01001:inv_ledger:false,BEL43475-12:inv_ledger:false');
delete from public.inv_ledger where doc_number = 'STOCK1A-TEST';
select pg_temp.chk('T5c delete of the fake rows → same two open rows (no duplicates) · ledger fake rows gone', pg_temp.open_stock(:'store'::uuid) || '/' || (select count(*)::text from public.inv_ledger where doc_number = 'STOCK1A-TEST'), 'ANN01001:inv_ledger:false,BEL43475-12:inv_ledger:false/0');
select pg_temp.close_stock();

-- ═══ T6 — 예약(값 같은 update → 0) · 트랜스퍼(가짜 문서 · 줄 insert → 줄 · status 바뀜 → 문서) ═══
update public.so_reserve set updated_by = updated_by where released_at is null;
select pg_temp.chk('T6a so_reserve value-same update over open rows → 0 stock rows (filter on qty · kind · released_at · line)', pg_temp.open_stock(:'store'::uuid), '');
insert into public.inv_transfer (transfer_number, status, from_warehouse_id, to_warehouse_id, note) values ('STOCK1A-T1', 'draft', :'wh_to'::uuid, :'wh_ed'::uuid, 'stock-1a verify') returning id::text as tr_id \gset
insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (:'tr_id'::uuid, 1, :'p_3907'::uuid, 'ANN03907', 1, 1);
select pg_temp.chk('T6b transfer line insert (draft) → ANN03907 queued (reason inv_transfer_line)', pg_temp.open_stock(:'store'::uuid), 'ANN03907:inv_transfer_line:false');
select pg_temp.close_stock();
update public.inv_transfer set note = 'touched' where id = :'tr_id'::uuid;
select pg_temp.chk('T6c transfer note-only update → 0', pg_temp.open_stock(:'store'::uuid), '');
update public.inv_transfer set status = 'confirmed', confirmed_at = now() where id = :'tr_id'::uuid;
select (b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea)::text as av_3907_to_after from public.inv_available_base(:'wh_to'::uuid, array[:'p_3907'::uuid]) b \gset
select pg_temp.chk('T6d transfer draft → confirmed → ANN03907 queued (reason inv_transfer) · Toronto available drops by 1 (transfer reservation) · payload follows',
  pg_temp.open_stock(:'store'::uuid) || '/' || (:av_3907_to::numeric - :av_3907_to_after::numeric)::text || '/' || (select x.quantity::text from public.shop_stock_payload(:'store'::uuid, array[:'p_3907'::uuid]) x where x.warehouse_id = :'wh_to'::uuid),
  'ANN03907:inv_transfer:false/1/' || greatest(0, floor(:av_3907_to_after::numeric))::text);
update public.inv_transfer set status = 'cancelled', cancelled_at = now() where id = :'tr_id'::uuid;
select pg_temp.close_stock();

-- ═══ T7 — 낮 비교 diff(판정 423 낮) ═══
insert into public.shop_stock_sent (store_id, product_id, warehouse_id, quantity) select x.store_id, x.product_id, x.warehouse_id, x.quantity from public.shop_stock_payload(:'store'::uuid, null) x where x.blocks = '[]'::jsonb;
select count(*)::text as sent_n from public.shop_stock_sent where store_id = :'store'::uuid \gset
select public.shop_stock_queue_diff(:'store'::uuid)::text as t7_a \gset
update public.shop_stock_sent set quantity = quantity + 1 where store_id = :'store'::uuid and product_id = :'p_1001'::uuid and warehouse_id = :'wh_ed'::uuid;
select public.shop_stock_queue_diff(:'store'::uuid)::text as t7_b \gset
update public.shop_stock_sent set last_status = 'error', last_error = 'x' where store_id = :'store'::uuid and product_id = :'p_3907'::uuid and warehouse_id = :'wh_to'::uuid;
select public.shop_stock_queue_diff(null)::text as t7_c \gset
select pg_temp.chk('T7a sent filled from payload (22 rows · set excluded: no inventory item) → diff 0 · one quantity changed → 1 (ANN01001 · reason diff) · one error → +1 (ANN03907) · set never queued by diff',
  :sent_n || '/' || :'t7_a' || '/' || :'t7_b' || '/' || :'t7_c' || '/' || pg_temp.open_stock(:'store'::uuid), '22/0/1/1/ANN01001:diff:false,ANN03907:diff:false');
select pg_temp.chk('T7b view shop_stock_list: 22 rows · open_queue 1 for ANN01001 rows · location names Toronto/Edmonton · updated_by null (system)',
  (select count(*)::text || '/' || max(open_queue) filter (where product_id = :'p_1001'::uuid)::text || '/' || string_agg(distinct location_name, ',' order by location_name) || '/' || count(*) filter (where last_status = 'error')::text from public.shop_stock_list where store_id = :'store'::uuid) || '/' ||
  (select count(*)::text from public.shop_stock_sent where updated_by is not null), '22/1/Edmonton,Toronto/1/0');
select pg_temp.close_stock();

-- ═══ T8 — 새벽 덮기 all(판정 423 새벽) · force 올리기 ═══
select public.shop_stock_queue_all(:'store'::uuid)::text as t8_a \gset
select public.shop_stock_queue_all(:'store'::uuid)::text as t8_b \gset
select pg_temp.chk('T8a nightly: 12 targets (11 + set) all force true reason nightly · again → 0', :'t8_a' || '/' || :'t8_b' || '/' || (select count(*)::text || '/' || count(*) filter (where force)::text || '/' || string_agg(distinct reason, ',') from public.shop_stock_queue where done_at is null), '12/0/12/12/nightly');
select pg_temp.close_stock();
select public.shop_stock_queue_add(:'store'::uuid, array[:'p_3907'::uuid], 'manual', false)::text as t8_c \gset
select public.shop_stock_queue_add(:'store'::uuid, array[:'p_3907'::uuid], 'manual', false)::text as t8_d \gset
select public.shop_stock_queue_add(:'store'::uuid, array[:'p_3907'::uuid], 'nightly', true)::text as t8_e \gset
select pg_temp.chk('T8b queue_add: open row 1 · again 0 · with force on an open non-force row → 1 (upgraded · reason stays manual) · single BEL43475 input expands to its sellable set', :'t8_c' || '/' || :'t8_d' || '/' || :'t8_e' || '/' || pg_temp.open_stock(:'store'::uuid) || '/' || public.shop_stock_queue_add(:'store'::uuid, array[:'p_bel'::uuid], 'manual', false)::text || '/' || pg_temp.open_stock(:'store'::uuid), '1/0/1/ANN03907:manual:true/1/ANN03907:manual:true,BEL43475-12:manual:false');
select pg_temp.close_stock();

-- ═══ T9 — 상품 새벽 맞추기 재발행 shop_queue_all(판정 424 ①): hash 같은 대상 0 · 다른 대상만 ═══
update public.shop_push_queue set started_at = now(), done_at = now(), result = 'ok' where done_at is null;
select count(*)::text as t9_want from public.shop_listing l where l.store_id = :'store'::uuid and l.is_on
   and not exists (select 1 from public.shop_product sp where sp.store_id = l.store_id and sp.family_id is not distinct from l.family_id and sp.product_id is not distinct from l.product_id and sp.last_status = 'ok'
                      and sp.last_hash = (public.shop_product_payload(l.store_id, l.family_id, l.product_id)->>'hash')) \gset
select clock_timestamp() as t9_0 \gset
select public.shop_queue_all(:'store'::uuid)::text as t9_a \gset
select clock_timestamp() as t9_1 \gset
select pg_temp.chk('T9a shop_queue_all re-issue: only targets whose hash differs or have no shop_product row (here: the set turned on in T3) · rows reason nightly', :'t9_a' || '/' || (select coalesce(string_agg(coalesce(f.sku, p.sku), ',' order by coalesce(f.sku, p.sku)), '') from public.shop_push_queue q left join public.product_family f on f.id = q.family_id left join public.product p on p.id = q.product_id where q.done_at is null), :t9_want || '/BEL43475-12');
update public.shop_push_queue set started_at = now(), done_at = now(), result = 'ok' where done_at is null;
savepoint t9;
update public.shop_product set last_hash = 'stock1a-differs' where store_id = :'store'::uuid and product_id = :'p_3907'::uuid;
select public.shop_queue_all(:'store'::uuid)::text as t9_b \gset
select :'t9_b' || '/' || (select string_agg(coalesce(f.sku, p.sku), ',' order by coalesce(f.sku, p.sku)) from public.shop_push_queue q left join public.product_family f on f.id = q.family_id left join public.product p on p.id = q.product_id where q.done_at is null) as t9_bb \gset
rollback to savepoint t9;
select pg_temp.chk('T9b one last_hash made different (ANN03907) → that target + the set (no shop_product) = 2 rows (measured inside the savepoint)', :'t9_bb', '2/ANN03907,BEL43475-12');
update public.shop_listing set is_on = false, turned_off_at = now() where product_id = :'p_bel12'::uuid;
update public.shop_push_queue set started_at = now(), done_at = now(), result = 'ok' where done_at is null;
select public.shop_queue_all(null)::text as t9_c \gset
select pg_temp.chk('T9c set listing off · every remaining on-target hash equal → all stores 0 rows', :'t9_c', (select count(*)::text from public.shop_listing l join public.shop_store s on s.id = l.store_id and s.is_active where l.is_on and l.store_id <> :'store'::uuid));
select round(extract(epoch from (:'t9_1'::timestamptz - :'t9_0'::timestamptz)) * 1000)::text as t9_ms \gset
\echo '── T9 shop_queue_all 재발행 시간(대상 4 · payload 4 번):' :t9_ms 'ms'
select pg_temp.close_stock();

-- ═══ T10 — 큰 갱신 비용(원장 5,000 행 insert · delete · Annie 상품 값 같은 update · diff · all) ═══
select clock_timestamp() as t10_0 \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
select current_date, 1, p.sku, 'Asung Trading Inc.', '', 0, 'adjust_existing', 'adjustment', 'STOCK1A-BIG', 'B' || row_number() over (order by p.sku), 'manual'
  from public.product p where p.parent_product_id is null and p.is_active and p.source = 'cin7' order by p.sku limit 5000;
select clock_timestamp() as t10_1 \gset
select count(*)::text as t10_n from public.inv_ledger where doc_number = 'STOCK1A-BIG' \gset
select count(*)::text as t10_led from public.shop_stock_queue where done_at is null and reason = 'inv_ledger' \gset
delete from public.inv_ledger where doc_number = 'STOCK1A-BIG';
select clock_timestamp() as t10_2 \gset
update public.product set note = note where brand_id = :'brand_annie'::uuid;
select clock_timestamp() as t10_3 \gset
select pg_temp.close_stock();
select clock_timestamp() as t10_4 \gset
select public.shop_stock_queue_diff(null)::text as t10_diff \gset
select clock_timestamp() as t10_5 \gset
select public.shop_stock_queue_all(null)::text as t10_all \gset
select clock_timestamp() as t10_6 \gset
select round(extract(epoch from (:'t10_1'::timestamptz - :'t10_0'::timestamptz)) * 1000)::text as ms_ins, round(extract(epoch from (:'t10_2'::timestamptz - :'t10_1'::timestamptz)) * 1000)::text as ms_del,
       round(extract(epoch from (:'t10_3'::timestamptz - :'t10_2'::timestamptz)) * 1000)::text as ms_prod, round(extract(epoch from (:'t10_5'::timestamptz - :'t10_4'::timestamptz)) * 1000)::text as ms_diff,
       round(extract(epoch from (:'t10_6'::timestamptz - :'t10_5'::timestamptz)) * 1000)::text as ms_all \gset
\echo '── T10 큰 갱신: 원장 insert' :t10_n '행' :ms_ins 'ms · delete' :ms_del 'ms · product Annie' :annie_n '행 값 같은 update' :ms_prod 'ms · diff(전 스토어)' :ms_diff 'ms · all(전 스토어)' :ms_all 'ms'
select pg_temp.chk('T10a 5,000-row ledger insert and delete each under 5 s · stock rows only for listed targets among them (≤ 12) · Annie value-same product update → 0 new rows · diff/all each under 5 s',
  (:'ms_ins'::int < 5000)::text || '/' || (:'ms_del'::int < 5000)::text || '/' || (:'ms_prod'::int < 5000)::text || '/' || (:'ms_diff'::int < 5000)::text || '/' || (:'ms_all'::int < 5000)::text || '/' || :t10_n || '/' || (:t10_led::int between 1 and 12)::text || '/' || (select count(*)::text from public.shop_stock_queue where done_at is null and reason = 'product') || '/' || (select count(*)::text from public.inv_ledger where doc_number = 'STOCK1A-BIG'),
  'true/true/true/true/true/5000/true/0/0');
\echo '── T10 원장 5,000 행이 만든 열린 재고 줄(켜진 대상만):' :t10_led '· diff 넣음' :t10_diff '· all 넣음' :t10_all

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select (to_regclass('public.shop_stock_queue') is not null)::text as has_sq \gset
\if :has_sq
select 'after rollback: stock queue rows ' || (select count(*) from public.shop_stock_queue) || ' · sent rows ' || (select count(*) from public.shop_stock_sent) || ' (applied DB — the trial leaves 0 new)';
select setval('public.shop_stock_queue_id_seq', greatest(coalesce((select max(id) from public.shop_stock_queue), 0), :sq_seq_head::bigint, 1), (select count(*) > 0 from public.shop_stock_queue));
select 'seq tail stock ' || last_value || ' ' || is_called from public.shop_stock_queue_id_seq;
\else
select 'after rollback: shop_stock_queue does not exist (trial run — rolled back)';
\endif
select 'after rollback: ledger STOCK1A rows ' || (select count(*) from public.inv_ledger where doc_number like 'STOCK1A-%') || ' · transfer STOCK1A rows ' || (select count(*) from public.inv_transfer where transfer_number = 'STOCK1A-T1') || ' · BEL43475-12 listing ' || (select count(*) from public.shop_listing where product_id = (select id from public.product where sku = 'BEL43475-12')) || ' (0/0/0)';
select setval('public.shop_push_queue_id_seq', greatest(coalesce((select max(id) from public.shop_push_queue), 0), :q_seq_head::bigint, 1), (select count(*) > 0 from public.shop_push_queue));
select 'seq tail push ' || last_value || ' ' || is_called from public.shop_push_queue_id_seq;
