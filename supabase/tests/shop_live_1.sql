-- supabase/tests/shop_live_1.sql — shop-live-1 검증: shop_store.live · auth_mode · 창구 store_live · 일하는 SQL 길 is_active and live (2026-10-27 · 판정 811 · 813 · 814 · 815)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞 · 잠금 없음) → begin → (-v mig 면 \i) → 검사 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027190714_shop_live_1.sql -f supabase/tests/shop_live_1.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK = 시험 = 확인 = EXPECT_OK
--   쓰기: 가짜 직원 2 · 가짜 스토어 1 · listing 2 · 잇기 판 1 · 큐 줄 — 전부 rollback · 시퀀스는 당기지 않는다(큐 id 시퀀스는 insert 로 당겨진다 — bigserial · 번호 뜻 없음 · 허용)
--   ⚠️ REST(safeupdate · 21000)는 psql 직결로 못 싣는다 — 여기서는 정적 셈(S1 · 최상위 WHERE 없는 update · delete 0) · 실제 REST 한 번은 Caleb(적용 뒤 · 회신의 curl)
\set ON_ERROR_STOP on
\set EXPECT_OK 59
\pset pager off
-- 기준(begin 앞 · 잠금 없음)
select (select count(*) from public.shop_push_queue where done_at is null) as pq0, (select count(*) from public.shop_stock_queue where done_at is null) as sq0,
       (select count(*) from public.shop_store) as n_store0, (select count(*) from public.shop_listing) as n_list0, (select count(*) from public.ims_staff) as n_staff0,
       (select count(*) from public.shop_link_run) as n_run0, (select id from public.shop_store where code = 'test') as test_id \gset
select value as db_role from public.inv_config where key = 'db_role' \gset
\echo '── 기준: db_role' :db_role '· open push q' :pq0 '· open stock q' :sq0 '· stores' :n_store0 '· listings' :n_list0 '· staff' :n_staff0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
grant insert on t_res to authenticated; grant usage on sequence t_res_n_seq to authenticated;                                                           -- set local role authenticated 안에서도 chk 가 적게
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 창구 호출(invoker · 지금 role 로) — 막기 0 이고 미확인 경고가 있으면 그 키를 ack 해 한 번 더(두 번 부르기 모양)
create function pg_temp.save(p jsonb) returns jsonb language plpgsql as $$
declare r jsonb; ack text[];
begin
  r := public.shop_store_save(p, true, '{}');
  if not (r->>'committed')::boolean and jsonb_array_length(r->'blocks') = 0 and jsonb_array_length(r->'unacked') > 0 then
    select array_agg(x) into ack from jsonb_array_elements_text(r->'unacked') x;
    r := jsonb_build_object('first_unacked', r->'unacked') || public.shop_store_save(p, true, ack);
  end if;
  return r;
exception when others then
  return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
end $$;
create function pg_temp.codes(r jsonb, k text) returns text language sql as $$
  select coalesce(string_agg(x->>'code', ',' order by x->>'code'), '') from jsonb_array_elements(r->k) x;
$$;
-- 깊이 0 WHERE 스캐너(ar_2b 와 같은 규칙의 작은 판): 주석을 빼고 ; 로 끊어 update · delete 로 시작하는 문장에 where 가 없으면 센다
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; c text; n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach c in array string_to_array(v, ';') loop
    if c ~* '^\s*(update|delete)\M' and c !~* '\mwhere\M' then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- ── A 칸 · 시작값 · 트리거 무발화 · 뷰 ──
select pg_temp.chk('A1 shop_store has live · auth_mode', (select string_agg(column_name || ':' || data_type || ':' || column_default, ' ' order by column_name) from information_schema.columns where table_name = 'shop_store' and column_name in ('live', 'auth_mode')), 'auth_mode:text:''client_credentials''::text live:boolean:false');
select pg_temp.chk('A2 test store live t · auth_mode client_credentials', (select live::text || ' ' || auth_mode from public.shop_store where code = 'test'), 'true client_credentials');
select pg_temp.chk('A3 open push · stock queue unchanged by the migration (store trigger did not fire)', (select count(*)::text from public.shop_push_queue where done_at is null) || ' ' || (select count(*)::text from public.shop_stock_queue where done_at is null), :'pq0' || ' ' || :'sq0');
select pg_temp.chk('A4 shop_store_list ends with live · auth_mode · orders_polled_at', (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_name = 'shop_store_list' and ordinal_position > (select max(ordinal_position) - 3 from information_schema.columns where table_name = 'shop_store_list')), 'live,auth_mode,orders_polled_at');
select pg_temp.chk('A5 auth_mode check constraint', (select pg_get_constraintdef(oid) from pg_constraint where conname = 'shop_store_auth_mode_ck'), 'CHECK ((auth_mode = ANY (ARRAY[''client_credentials''::text, ''stored_token''::text])))');
select pg_temp.chk('A6 no new FK on shop_store (none added by this step)', (select count(*)::text from pg_constraint where conrelid = 'public.shop_store'::regclass and contype = 'f'), '3');

-- ── 가짜 직원 둘(admin · manager+shopify) ──
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values
  (gen_random_uuid(), 'shoplive1-admin@test.invalid', 'shoplive1 admin', 'admin', '[]', true),
  (gen_random_uuid(), 'shoplive1-mgr@test.invalid',   'shoplive1 manager', 'manager', '["shopify"]', true);
select auth_user_id::text as u_adm, id::text as adm_id from public.ims_staff where email = 'shoplive1-admin@test.invalid' \gset
select auth_user_id::text as u_mgr from public.ims_staff where email = 'shoplive1-mgr@test.invalid' \gset
select id::text as p1 from public.product where sku = 'AAL10850' \gset
select id::text as p2 from public.product where sku = 'AAL10925' \gset

-- ── B 창구(admin): store_set 새 스토어 → live false · auth_mode · 막기 auth_mode_invalid · 있는 스토어 store_set 은 live 무접촉 ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.save('[{"op":"store_set","code":"shoplv1","shop_domain":"shoplive1-test.myshopify.com","label":"shop-live-1 fake","kind":"aone","sale_tier":"AONE","compare_tier":"","secret_prefix":"SHOPIFY_AONE","oos_policy":"deny","auth_mode":"stored_token","old":null}]'::jsonb)::text as r_b1 \gset
select pg_temp.chk('B1 store_set new store committed', (:'r_b1'::jsonb->>'committed') || ' blocks=' || pg_temp.codes(:'r_b1'::jsonb, 'blocks'), 'true blocks=');
select pg_temp.chk('B2 new store: live false · auth_mode stored_token · is_active · orders_polled_at null', (select live::text || ' ' || auth_mode || ' ' || is_active::text || ' ' || coalesce(orders_polled_at::text, 'null') from public.shop_store where code = 'shoplv1'), 'false stored_token true null');
select pg_temp.save('[{"op":"store_set","code":"shoplv2","shop_domain":"shoplive2-test.myshopify.com","label":"x","kind":"aone","sale_tier":"AONE","compare_tier":"","secret_prefix":"SHOPIFY_AONE","auth_mode":"magic","old":null}]'::jsonb)::text as r_b3 \gset
select pg_temp.chk('B3 store_set auth_mode magic → block auth_mode_invalid · nothing saved', pg_temp.codes(:'r_b3'::jsonb, 'blocks') || ' ' || (select count(*)::text from public.shop_store where code = 'shoplv2'), 'auth_mode_invalid 0');
select pg_temp.save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'test', 'shop_domain', s.shop_domain, 'label', s.label, 'kind', s.kind, 'sale_tier', ts.name, 'compare_tier', coalesce(tc.name, ''), 'secret_prefix', s.secret_prefix, 'oos_policy', s.oos_policy,
         'old', jsonb_build_object('shop_domain', s.shop_domain, 'label', s.label, 'kind', s.kind, 'sale_tier', ts.name, 'compare_tier', coalesce(tc.name, ''), 'secret_prefix', s.secret_prefix, 'oos_policy', s.oos_policy))))::text as r_b4
  from public.shop_store s join public.ref_price_tier ts on ts.id = s.sale_tier_id left join public.ref_price_tier tc on tc.id = s.compare_tier_id where s.code = 'test' \gset
select pg_temp.chk('B4 store_set on the test store (old without auth_mode · ss v3a shape) committed · live stays true · auth_mode stays', (:'r_b4'::jsonb->>'committed') || ' ' || (select live::text || ' ' || auth_mode from public.shop_store where code = 'test'), 'true true client_credentials');
select pg_temp.chk('B5 that save queued no product push (payload columns unchanged)', (select count(*)::text from public.shop_push_queue where done_at is null), :'pq0');
reset role;
select id::text as s1 from public.shop_store where code = 'shoplv1' \gset

-- ── C 일하는 SQL 길: live 전 스토어는 줄 0 ──
insert into public.shop_listing (store_id, product_id, is_on, turned_on_at, turned_on_by, updated_by) values (:'s1'::uuid, :'p1'::uuid, true, now(), :'adm_id'::uuid, :'adm_id'::uuid);
select pg_temp.chk('C1 listing on (is_on) for the not-live store → stock trigger queued 0 rows for it', (select count(*)::text from public.shop_stock_queue where store_id = :'s1'::uuid), '0');
select pg_temp.chk('C2 shop_stock_targets(store) empty while not live', (select count(*)::text from public.shop_stock_targets(:'s1'::uuid, null)), '0');
select pg_temp.chk('C3 shop_stock_queue_all(store) · _diff(store) · shop_queue_all(store) → 0 · 0 · 0', public.shop_stock_queue_all(:'s1'::uuid)::text || ' ' || public.shop_stock_queue_diff(:'s1'::uuid)::text || ' ' || public.shop_queue_all(:'s1'::uuid)::text, '0 0 0');
select pg_temp.chk('C4 shop_paid_scan(200, store) scanned 0', (public.shop_paid_scan(200, :'s1'::uuid)->>'scanned'), '0');
select pg_temp.chk('C5 shop_unshipped_scan(5) runs · its store filter is is_active and live (source)', (public.shop_unshipped_scan(5) ? 'scanned')::text || ' ' || (select (prosrc ~ 'st\.is_active and st\.live')::text from pg_proc where proname = 'shop_unshipped_scan'), 'true true');
select pg_temp.chk('C6 queues for the not-live store after all scans: push 0 · stock 0', (select count(*)::text from public.shop_push_queue where store_id = :'s1'::uuid) || ' ' || (select count(*)::text from public.shop_stock_queue where store_id = :'s1'::uuid), '0 0');
select pg_temp.chk('C7 test store (live) still gets stock rows from shop_stock_queue_all(test)', (public.shop_stock_queue_all(:'test_id'::uuid) > 0)::text, 'true');

-- ── D 잇기 — live 전에도 shop_link_apply 는 된다(판정 815) · 재고 · 상품 큐는 0 ──
insert into public.shop_link_run (id, store_id, status, version, started_by, read_at, planned_at, item_count) values ('a0000000-0000-4000-8000-00000000a001', :'s1'::uuid, 'planned', 1, :'adm_id'::uuid, now(), now(), 1);
insert into public.shop_link_item (run_id, shopify_product_gid, handle, title, status, options, variants, media, decision, reasons, ims_product_id, changes)
values ('a0000000-0000-4000-8000-00000000a001', 'gid://shopify/Product/999000111', 'shoplive1-fake', 'fake', 'ACTIVE', '[]', '[{"sku":"AAL10925","variant_gid":"gid://shopify/ProductVariant/999000111","inventory_item_gid":"gid://shopify/InventoryItem/999000111"}]', '[]', 'link', '{}', :'p2'::uuid, '{}');
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run('select set_config(''app.out'', public.shop_link_apply(''a0000000-0000-4000-8000-00000000a001'', true, 1)::text, true)') as r_d \gset
reset role;
select pg_temp.chk('D1 shop_link_apply on the not-live store: committed · linked 1', case when :'r_d' like 'ERR%' then :'r_d' else (current_setting('app.out', true)::jsonb->>'committed') || ' ' || (current_setting('app.out', true)::jsonb->>'linked') end, 'true 1');
select pg_temp.chk('D2 listing on · shop_product gid · shop_variant for the linked product', (select is_on::text from public.shop_listing where store_id = :'s1'::uuid and product_id = :'p2'::uuid) || ' ' || (select shopify_product_gid from public.shop_product where store_id = :'s1'::uuid and product_id = :'p2'::uuid) || ' ' || (select count(*)::text from public.shop_variant where store_id = :'s1'::uuid and product_id = :'p2'::uuid), 'true gid://shopify/Product/999000111 1');
select pg_temp.chk('D3 after linking: stock queue 0 · push queue 0 for that store', (select count(*)::text from public.shop_stock_queue where store_id = :'s1'::uuid) || ' ' || (select count(*)::text from public.shop_push_queue where store_id = :'s1'::uuid), '0 0');
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run('select set_config(''app.out'', public.shop_link_push_batch(''' || :'s1' || ''', ''{}'', true, 10)::text, true)') as r_d4 \gset
select pg_temp.run('select set_config(''app.out'', public.shop_link_push_batch(''' || :'s1' || ''', ''{}'', false, 10)::text, true)') as r_d5 \gset
reset role;
select pg_temp.chk('D4 shop_link_push_batch commit on the not-live store → refused (not live)', case when :'r_d4' like 'ERR P0001:%not live%' then 'refused' else :'r_d4' end, 'refused');
select pg_temp.chk('D5 shop_link_push_batch preview (commit false) still works: picked 1', case when :'r_d5' like 'ERR%' then :'r_d5' else current_setting('app.out', true)::jsonb->>'picked' end, '1');

-- ── E store_live(admin): 켜기 → orders_polled_at · live · 재고 force 전부 · 두 번째는 막기 · 끄기 · orders_from 빠짐 · store_off 는 live 도 끔 ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.save('[{"op":"store_live","code":"shoplv1","live":true,"orders_from":"2026-11-01T05:00:00Z"}]'::jsonb)::text as r_e1 \gset
select pg_temp.chk('E1 store_live on: first call asks ack(going_live · no_location_pair · orders_from_future) → second committed', (select string_agg(split_part(x, ':', 2), ',' order by x) from jsonb_array_elements_text(:'r_e1'::jsonb->'first_unacked') x) || ' | ' || (:'r_e1'::jsonb->>'committed'), 'going_live,no_location_pair,orders_from_future | true');
select pg_temp.chk('E2 live true · orders_polled_at = orders_from', (select live::text || ' ' || (orders_polled_at = '2026-11-01T05:00:00Z'::timestamptz)::text from public.shop_store where code = 'shoplv1'), 'true true');
select pg_temp.chk('E3 stock queue for the store = listed products (2) · all force · changes[0].stock_queued 2', (select count(*)::text || ' ' || bool_and(force)::text from public.shop_stock_queue where store_id = :'s1'::uuid and done_at is null) || ' ' || (:'r_e1'::jsonb#>>'{changes,0,stock_queued}'), '2 true 2');
reset role;
select pg_temp.chk('E4 shop_stock_targets(store) now 2', (select count(*)::text from public.shop_stock_targets(:'s1'::uuid, null)), '2');
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.save('[{"op":"store_live","code":"shoplv1","live":true,"orders_from":"2026-11-01T05:00:00Z"}]'::jsonb)::text as r_e5 \gset
select pg_temp.chk('E5 store_live on again → block already_live', pg_temp.codes(:'r_e5'::jsonb, 'blocks'), 'already_live');
select pg_temp.save('[{"op":"store_live","code":"shoplv1","live":false}]'::jsonb)::text as r_e6 \gset
select pg_temp.chk('E6 store_live off: ack going_dark → live false · orders_polled_at kept', (select string_agg(split_part(x, ':', 2), ',') from jsonb_array_elements_text(:'r_e6'::jsonb->'first_unacked') x) || ' ' || (:'r_e6'::jsonb->>'committed') || ' ' || (select live::text || ' ' || (orders_polled_at = '2026-11-01T05:00:00Z'::timestamptz)::text from public.shop_store where code = 'shoplv1'), 'going_dark true false true');
select pg_temp.save('[{"op":"store_live","code":"shoplv1","live":false}]'::jsonb)::text as r_e7 \gset
select pg_temp.chk('E7 store_live off again → block already_not_live', pg_temp.codes(:'r_e7'::jsonb, 'blocks'), 'already_not_live');
select pg_temp.save('[{"op":"store_live","code":"shoplv1","live":true}]'::jsonb)::text as r_e8 \gset
select pg_temp.chk('E8 store_live on without orders_from → block orders_from_missing', pg_temp.codes(:'r_e8'::jsonb, 'blocks'), 'orders_from_missing');
select pg_temp.save('[{"op":"store_live","code":"shoplv1","live":true,"orders_from":"not a time"}]'::jsonb)::text as r_e9 \gset
select pg_temp.chk('E9 store_live on with a bad orders_from → block orders_from_missing', pg_temp.codes(:'r_e9'::jsonb, 'blocks'), 'orders_from_missing');
select pg_temp.save('[{"op":"store_live","code":"shoplv1","live":"yes","orders_from":"2026-11-01T05:00:00Z"}]'::jsonb)::text as r_e10 \gset
select pg_temp.chk('E10 store_live with live "yes" → block live_missing', pg_temp.codes(:'r_e10'::jsonb, 'blocks'), 'live_missing');
select pg_temp.save('[{"op":"store_live","code":"nope","live":true,"orders_from":"2026-11-01T05:00:00Z"}]'::jsonb)::text as r_e11 \gset
select pg_temp.chk('E11 store_live on an unknown store → block store_unknown', pg_temp.codes(:'r_e11'::jsonb, 'blocks'), 'store_unknown');
select pg_temp.save('[{"op":"store_live","code":"shoplv1","live":true,"orders_from":"2026-10-01T05:00:00Z"}]'::jsonb)::text as r_e12 \gset
select pg_temp.chk('E12 store_live on with orders_from 7+ days ago → warn orders_from_old (not future) · committed', (select string_agg(split_part(x, ':', 2), ',' order by x) from jsonb_array_elements_text(:'r_e12'::jsonb->'first_unacked') x) || ' ' || (:'r_e12'::jsonb->>'committed'), 'going_live,no_location_pair,orders_from_old true');
select pg_temp.chk('E13 live store: store_set changing secret_prefix warns live_connection_change (commit false)',
  pg_temp.codes(public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'shoplv1', 'shop_domain', 'shoplive1-test.myshopify.com', 'label', 'shop-live-1 fake', 'kind', 'aone', 'sale_tier', 'AONE', 'compare_tier', '', 'secret_prefix', 'SHOPIFY_AONE2', 'oos_policy', 'deny',
    'old', jsonb_build_object('shop_domain', 'shoplive1-test.myshopify.com', 'label', 'shop-live-1 fake', 'kind', 'aone', 'sale_tier', 'AONE', 'compare_tier', '', 'secret_prefix', 'SHOPIFY_AONE', 'oos_policy', 'deny', 'auth_mode', 'stored_token'))), false, '{}'), 'warnings'), 'live_connection_change');
select pg_temp.chk('E14 old.auth_mode wrong → block changed_elsewhere',
  pg_temp.codes(public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'shoplv1', 'shop_domain', 'shoplive1-test.myshopify.com', 'label', 'shop-live-1 fake', 'kind', 'aone', 'sale_tier', 'AONE', 'compare_tier', '', 'secret_prefix', 'SHOPIFY_AONE', 'oos_policy', 'deny',
    'old', jsonb_build_object('shop_domain', 'shoplive1-test.myshopify.com', 'label', 'shop-live-1 fake', 'kind', 'aone', 'sale_tier', 'AONE', 'compare_tier', '', 'secret_prefix', 'SHOPIFY_AONE', 'oos_policy', 'deny', 'auth_mode', 'client_credentials'))), false, '{}'), 'blocks'), 'changed_elsewhere');
select pg_temp.save('[{"op":"store_off","code":"shoplv1","old":"shoplive1-test.myshopify.com"}]'::jsonb)::text as r_e15 \gset
select pg_temp.chk('E15 store_off on the live store → is_active false · live false', (:'r_e15'::jsonb->>'committed') || ' ' || (select is_active::text || ' ' || live::text from public.shop_store where code = 'shoplv1'), 'true false false');
select pg_temp.save('[{"op":"store_live","code":"shoplv1","live":true,"orders_from":"2026-11-01T05:00:00Z"}]'::jsonb)::text as r_e16 \gset
select pg_temp.chk('E16 store_live on a switched-off store → block store_off', pg_temp.codes(:'r_e16'::jsonb, 'blocks'), 'store_off');
select pg_temp.save('[{"op":"store_set","code":"shoplv1","shop_domain":"shoplive1-test.myshopify.com","label":"shop-live-1 fake","kind":"aone","sale_tier":"AONE","compare_tier":"","secret_prefix":"SHOPIFY_AONE","oos_policy":"deny","old":{"shop_domain":"shoplive1-test.myshopify.com","label":"shop-live-1 fake","kind":"aone","sale_tier":"AONE","compare_tier":"","secret_prefix":"SHOPIFY_AONE","oos_policy":"deny"}}]'::jsonb)::text as r_e17 \gset
select pg_temp.chk('E17 store_set turns a switched-off store back on (ack store_reactivated) · live stays false · auth_mode kept', (select string_agg(split_part(x, ':', 2), ',') from jsonb_array_elements_text(:'r_e17'::jsonb->'first_unacked') x) || ' ' || (:'r_e17'::jsonb->>'committed') || ' ' || (select is_active::text || ' ' || live::text || ' ' || auth_mode from public.shop_store where code = 'shoplv1'), 'store_reactivated true true false stored_token');
select pg_temp.save('[{"op":"store_set","code":"shoplv1","shop_domain":"shoplive1-test.myshopify.com","label":"shop-live-1 fake","kind":"aone","sale_tier":"AONE","compare_tier":"","secret_prefix":"SHOPIFY_AONE","oos_policy":"deny","auth_mode":"client_credentials","old":{"shop_domain":"shoplive1-test.myshopify.com","label":"shop-live-1 fake","kind":"aone","sale_tier":"AONE","compare_tier":"","secret_prefix":"SHOPIFY_AONE","oos_policy":"deny","auth_mode":"stored_token"}}]'::jsonb)::text as r_e18 \gset
select pg_temp.chk('E18 store_set changes auth_mode on an existing store', (:'r_e18'::jsonb->>'committed') || ' ' || (select auth_mode from public.shop_store where code = 'shoplv1'), 'true client_credentials');
reset role;

-- ── F 관리자 아닌 직원(manager · perms shopify) → store_live 거부 ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_mgr', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run('select public.shop_store_save(''[{"op":"store_live","code":"shoplv1","live":true,"orders_from":"2026-11-01T05:00:00Z"}]'', true, ''{}'')::text') as r_f \gset
reset role;
select pg_temp.chk('F1 manager (perms shopify) store_live → refused (admin only)', case when :'r_f' like 'ERR P0001: Only an admin can change Shopify stores%' then 'refused' else :'r_f' end, 'refused');
select pg_temp.chk('F2 anon · public cannot execute shop_store_save · authenticated can', pg_temp.run('select has_function_privilege(''anon'', ''public.shop_store_save(jsonb, boolean, text[])'', ''execute'')::text') || ' ' || pg_temp.run('select has_function_privilege(''authenticated'', ''public.shop_store_save(jsonb, boolean, text[])'', ''execute'')::text'), 'false true');

-- ── G 전수 표의 「바꿈」 8 — md5 = 새 정의 · 몸에 live · 「그대로」 shop_link_apply 무접촉 ──
select pg_temp.chk('G1 shop_stock_targets md5',   (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_stock_targets'),   '81a93a747ce3b17ae3388c9cf8eb0228');
select pg_temp.chk('G2 shop_queue_all md5',       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_all'),       'b715b4c75cd69c6fa7e71016356bb0a5');
select pg_temp.chk('G3 shop_stock_queue_all md5', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_stock_queue_all'), '7eded8fe7b77b0f719ccc977acf3cc68');
select pg_temp.chk('G4 shop_stock_queue_diff md5',(select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_stock_queue_diff'),'e01e63ef2e63d674db3f8d38af44eaf0');
select pg_temp.chk('G5 shop_unshipped_scan md5',  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_unshipped_scan'),  '854d78cbe0586eda7063ab79734be3f2');
select pg_temp.chk('G6 shop_paid_scan md5',       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_paid_scan'),       'd7a7c8f8e910e54f3604a49d394e6683');
select pg_temp.chk('G7 shop_link_push_batch md5', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_push_batch'), '41c5f51a42d1f001bad1e5dc74033a72');
select pg_temp.chk('G8 shop_store_save md5',      (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_save'),      '3b3b444f2a59c820469581086f3dc072');
select pg_temp.chk('G9 all eight mention live · one definition each', (select count(*)::text || ' ' || count(distinct proname)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_stock_targets', 'shop_queue_all', 'shop_stock_queue_all', 'shop_stock_queue_diff', 'shop_unshipped_scan', 'shop_paid_scan', 'shop_link_push_batch', 'shop_store_save') and prosrc ~ '\mlive\M'), '8 8');
select pg_temp.chk('G10 shop_link_apply untouched (md5 of link-1a) · looks at is_active only', (select md5(prosrc) || ' ' || (prosrc !~ '\mlive\M')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply'), 'd9af643812f372b04b3b50beececb0a6 true');
select pg_temp.chk('G11 definer · search_path on the seven plpgsql ones', (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_queue_all', 'shop_stock_queue_all', 'shop_stock_queue_diff', 'shop_unshipped_scan', 'shop_paid_scan', 'shop_link_push_batch', 'shop_store_save') and prosecdef and array_to_string(proconfig, ',') = 'search_path=public, pg_temp'), '7');
select pg_temp.chk('G12 shop_stock_targets stays sql stable invoker', (select provolatile::text || ' ' || prosecdef::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_stock_targets'), 's false');
select pg_temp.chk('G13 cron-only functions still not executable by authenticated', (select string_agg(has_function_privilege('authenticated', p.oid, 'execute')::text, ',' order by proname) from pg_proc p where pronamespace = 'public'::regnamespace and proname in ('shop_queue_all', 'shop_stock_queue_all', 'shop_stock_queue_diff', 'shop_unshipped_scan', 'shop_paid_scan', 'shop_stock_targets')), 'false,false,false,false,false,false');

-- ── S safeupdate 정적 셈: 새 창구에 최상위 WHERE 없는 update · delete 0 ──
select pg_temp.chk('S0 scanner self-test', pg_temp.nowhere('update a set x = 1; update b set y = 2 where id = 1; delete from c; -- update d set z = 3\nselect 1;')::text, '2');
select pg_temp.chk('S1 shop_store_save: no-WHERE update · delete = 0', pg_temp.nowhere((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_save'))::text, '0');
select pg_temp.chk('S2 shop_link_push_batch: no-WHERE update · delete = 0', pg_temp.nowhere((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_push_batch'))::text, '0');

-- ── 결과 ──
select clock_timestamp() as t_end \gset
select n, case when ok then 'OK  ' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok_n, count(*) filter (where not ok) as bad_n, count(*) as total from t_res \gset
\echo '── OK' :ok_n '/ ' :total '(expect' :EXPECT_OK ') · MISMATCH' :bad_n '· begin~end' :t_begin '→' :t_end
rollback;
select (select count(*) from public.shop_store) as n_store1, (select count(*) from public.shop_listing) as n_list1, (select count(*) from public.ims_staff) as n_staff1, (select count(*) from public.shop_link_run) as n_run1,
       (select count(*) from public.shop_push_queue where done_at is null) as pq1, (select count(*) from public.shop_stock_queue where done_at is null) as sq1 \gset
\echo '── rollback 뒤 실제 행: stores' :n_store0 '→' :n_store1 '· listings' :n_list0 '→' :n_list1 '· staff' :n_staff0 '→' :n_staff1 '· link runs' :n_run0 '→' :n_run1 '· open push q' :pq0 '→' :pq1 '· open stock q' :sq0 '→' :sq1
