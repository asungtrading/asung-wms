-- shop-pol-verify.sql — 품절 판매를 스토어마다 · 단종은 DENY: shop_store.oos_policy · shop_variant_payload · shop_product_payload blocks · shop_store_save · 뷰 · 스토어 트리거 (Asung-IMS · 테스트)
--   기대: 시험 갈래(-v mig) OK 17 · 확인 갈래 OK 14(= 17 − 시험 전용 3: G0a · T1b · T1c) · MISMATCH 0 · 확인 갈래 전용 줄(\else)은 없다
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261010220500_shop_pol_oos_policy.sql -f supabase/tests/shop-pol-verify.sql > /tmp/shop-pol.out 2>&1; echo exit=$?
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료: 실제 ANN01001FAM(켜짐 · 구성원 10 전부 켜짐 · 단종 0 · 가격 있음) · ANN03907(켜짐) · 시험 스토어 test(continue) · 가짜 admin 직원 하나(rollback)
--   ⚠️ 실제 행을 바꾸는 갈래는 savepoint 안에서만(ANN01001 단종 · ANN01015 sellable · ANN01015 가격 지우기 · test 스토어 oos_policy) · 되감은 뒤 행 md5 같음을 센다(stock-1a T4 와 같은 결) · 큐 줄은 되감기 · 시퀀스는 머리로 되돌린다
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value::text as q_seq_head from public.shop_push_queue_id_seq \gset
select last_value::text as sq_seq_head from public.shop_stock_queue_id_seq \gset
\echo '== head push seq' :q_seq_head '· stock seq' :sq_seq_head

begin;
select id::text as store from public.shop_store where code = 'test' \gset
select id::text as fam from public.product_family where sku = 'ANN01001FAM' \gset
select id::text as p_1001 from public.product where sku = 'ANN01001' \gset
select id::text as p_1015 from public.product where sku = 'ANN01015' \gset
select id::text as p_3907 from public.product where sku = 'ANN03907' \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
select md5(prosrc) as h0_variant from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_variant_payload' \gset
select md5(prosrc) as h0_product from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload' \gset
select md5(prosrc) as h0_save from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_save' \gset
select string_agg(proname || ':' || md5(prosrc), ',' order by proname) as h0_untouched from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_queue_trigger', 'shop_queue_add', 'shop_listing_set', 'shop_stock_payload', 'shop_stock_queue_trigger', 'shop_tier_price') \gset
select md5(public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)::text) as pay0_fam \gset
select md5(public.shop_product_payload(:'store'::uuid, null, :'p_3907'::uuid)::text) as pay0_prod \gset
\i :mig
\endif
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql security definer as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql security definer as $$
begin execute p_sql; return 'no-error'; exception when others then return sqlstate || ' ' || sqlerrm; end $$;
create function pg_temp.open_push(p_store uuid) returns text language sql security definer as $$
  select coalesce(string_agg(coalesce(f.sku, p.sku) || ':' || q.reason, ',' order by coalesce(f.sku, p.sku)), '') from public.shop_push_queue q left join public.product_family f on f.id = q.family_id left join public.product p on p.id = q.product_id where q.store_id = p_store and q.done_at is null;
$$;
create function pg_temp.close_push() returns void language sql security definer as $$
  update public.shop_push_queue set started_at = now(), done_at = now(), result = 'ok' where done_at is null;
$$;
create function pg_temp.policies(p_store uuid, p_fam uuid, p_prod uuid) returns text language sql security definer as $$
  select string_agg(v->>'sku' || ':' || (v->>'inventory_policy'), ',' order by v->>'sku') from jsonb_array_elements(public.shop_product_payload(p_store, p_fam, p_prod)->'variants') v;
$$;
create function pg_temp.stock_numbers(p_store uuid, p_pids uuid[]) returns text language sql security definer as $$
  select coalesce(string_agg(x.sku || ':' || x.location_gid || ':' || x.quantity::text || ':' || x.is_off::text, ',' order by x.sku, x.location_gid), '') from public.shop_stock_payload(p_store, p_pids) x;
$$;
\if :{?mig}
select pg_temp.chk('G0a trial marker: shop_store.oos_policy exists only after the trial apply', (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'shop_store' and column_name = 'oos_policy'), '1');
\endif

-- ═══ T1 — 객체 · 권한 · 재발행 ═══
select pg_temp.chk('T1a column oos_policy (text · not null · default continue · check continue|deny) · store trigger (AFTER STATEMENT) · trigger function definer · view has oos_policy + send_tags at the end · store_save definer',
  (select data_type || '/' || is_nullable || '/' || (column_default like '%continue%')::text from information_schema.columns where table_schema = 'public' and table_name = 'shop_store' and column_name = 'oos_policy') || '/' ||
  (select count(*)::text from pg_constraint where conname = 'shop_store_oos_policy_ck' and contype = 'c') || '/' ||
  (select count(*)::text from pg_trigger where tgname = 'shop_store_shop_queue_u' and (tgtype & 1) = 0) || '/' ||
  (select prosecdef::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_queue_trigger') || '/' ||
  (select string_agg(column_name, '+' order by ordinal_position) from (select column_name, ordinal_position from information_schema.columns where table_schema = 'public' and table_name = 'shop_store_list' order by ordinal_position desc limit 2) z) || '/' ||
  (select prosecdef::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_save'),
  'text/NO/true/1/1/true/oos_policy+send_tags/true');
\if :{?mig}
select pg_temp.chk('T1b (trial) three functions re-issued (prosrc changed) · six untouched functions byte-identical',
  (:'h0_variant' <> (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_variant_payload'))::text || '/' ||
  (:'h0_product' <> (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload'))::text || '/' ||
  (:'h0_save' <> (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_save'))::text || '/' ||
  (:'h0_untouched' = (select string_agg(proname || ':' || md5(prosrc), ',' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_queue_trigger', 'shop_queue_add', 'shop_listing_set', 'shop_stock_payload', 'shop_stock_queue_trigger', 'shop_tier_price')))::text,
  'true/true/true/true');
\endif
\if :{?mig}
select pg_temp.chk('T1c (trial) payload bytes identical before/after for ANN01001FAM and ANN03907 (continue store · no discontinued member → same policies · same hash)',
  (:'pay0_fam' = md5(public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)::text))::text || '/' || (:'pay0_prod' = md5(public.shop_product_payload(:'store'::uuid, null, :'p_3907'::uuid)::text))::text, 'true/true');
\endif
select pg_temp.chk('T1d privileges: authenticated select on view · execute store_save · no execute on store trigger fn · anon nothing on view',
  has_table_privilege('authenticated', 'public.shop_store_list', 'select')::text || '/' || has_function_privilege('authenticated', 'public.shop_store_save(jsonb, boolean, text[])', 'execute')::text || '/' ||
  has_function_privilege('authenticated', 'public.shop_store_queue_trigger()', 'execute')::text || '/' || has_table_privilege('anon', 'public.shop_store_list', 'select')::text, 'true/true/false/false');

-- ═══ T2 — 지금 상태(continue 스토어) ═══
select pg_temp.close_push();
select pg_temp.chk('T2a test store continue (table · view) · family 10 members all CONTINUE · ANN03907 CONTINUE · blocks [] · stock queue untouched baseline',
  (select oos_policy from public.shop_store where id = :'store'::uuid) || '/' || (select oos_policy || '/' || send_tags::text from public.shop_store_list where id = :'store'::uuid) || '/' ||
  (select count(*)::text from jsonb_array_elements(public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)->'variants') v where v->>'inventory_policy' = 'CONTINUE') || '/' ||
  pg_temp.policies(:'store'::uuid, null, :'p_3907'::uuid) || '/' || (public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)->'blocks')::text,
  'continue/continue/true/10/ANN03907:CONTINUE/[]');

-- ═══ T3 — 단종(판정 428) · savepoint ═══
select md5(row(p.*)::text) as md5_1001 from public.product p where p.id = :'p_1001'::uuid \gset
select public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null) as pay_before \gset
select pg_temp.stock_numbers(:'store'::uuid, array[:'p_1001'::uuid]) as stock_before \gset
select count(*)::text as sq_before from public.shop_stock_queue where done_at is null \gset
savepoint t3;
update public.product set is_discontinued = true where id = :'p_1001'::uuid;
select pg_temp.policies(:'store'::uuid, :'fam'::uuid, null) as t3_pol \gset
select pg_temp.open_push(:'store'::uuid) as t3_q \gset
select ((:'pay_before'::jsonb - 'hash' - 'variants') = (public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null) - 'hash' - 'variants'))::text as t3_same_rest \gset
select ((select jsonb_agg(v - 'inventory_policy' order by v->>'sku') from jsonb_array_elements(:'pay_before'::jsonb->'variants') v) = (select jsonb_agg(v - 'inventory_policy' order by v->>'sku') from jsonb_array_elements(public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)->'variants') v))::text as t3_same_vars \gset
select ((:'pay_before'::jsonb->>'hash') <> (public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)->>'hash'))::text as t3_hash_changed \gset
select (pg_temp.stock_numbers(:'store'::uuid, array[:'p_1001'::uuid]) = :'stock_before')::text as t3_stock_same \gset
select count(*)::text as t3_sq from public.shop_stock_queue where done_at is null \gset
rollback to savepoint t3;
select pg_temp.chk('T3a ANN01001 discontinued → only that variant DENY · the other 9 CONTINUE · product queue gets ANN01001FAM (reason product · 2a2 trigger already catches is_discontinued) · hash changed',
  (select count(*)::text from regexp_split_to_table(:'t3_pol', ',') x where x like '%:DENY') || '/' || (select count(*)::text from regexp_split_to_table(:'t3_pol', ',') x where x like '%:CONTINUE') || '/' || (:'t3_pol' like '%ANN01001:DENY%')::text || '/' || :'t3_q' || '/' || :'t3_hash_changed',
  '1/9/true/ANN01001FAM:product/true');
select pg_temp.chk('T3b payload byte-same except inventory_policy (title · tags · files · status · variants minus policy) · stock payload unchanged (numbers stay · is_off false) · no stock queue row (판정 428: 재고 숫자는 그대로)',
  :'t3_same_rest' || '/' || :'t3_same_vars' || '/' || :'t3_stock_same' || '/' || (:'t3_sq'::int - :'sq_before'::int)::text, 'true/true/true/0');
select pg_temp.chk('T3c after rollback to savepoint: ANN01001 row md5 unchanged · push queue 0 open · policies back to 10 CONTINUE',
  ((select md5(row(p.*)::text) from public.product p where p.id = :'p_1001'::uuid) = :'md5_1001')::text || '/' || pg_temp.open_push(:'store'::uuid) || '/' || (select count(*)::text from regexp_split_to_table(pg_temp.policies(:'store'::uuid, :'fam'::uuid, null), ',') x where x like '%:CONTINUE'), 'true//10');

-- ═══ T4 — 꺼진 구성원은 그대로 DENY + 재고 0(406 · 425 그대로) · savepoint ═══
select md5(row(p.*)::text) as md5_1015 from public.product p where p.id = :'p_1015'::uuid \gset
savepoint t4;
update public.product set sellable = false where id = :'p_1015'::uuid;
select (pg_temp.policies(:'store'::uuid, :'fam'::uuid, null) like '%ANN01015:DENY%')::text as t4_pol \gset
select string_agg(x.quantity::text || '|' || x.is_off::text, ',' order by x.location_gid) as t4_stock from public.shop_stock_payload(:'store'::uuid, array[:'p_1015'::uuid]) x \gset
rollback to savepoint t4;
select pg_temp.chk('T4a ANN01015 sellable off → DENY · stock payload 0 at both locations · is_off true (unchanged behaviour) · row md5 restored',
  :'t4_pol' || '/' || :'t4_stock' || '/' || ((select md5(row(p.*)::text) from public.product p where p.id = :'p_1015'::uuid) = :'md5_1015')::text,
  'true/0|true,0|true/true');

-- ═══ T5 — 스토어 deny(판정 427) · 트리거 · savepoint ═══
select md5(row(s.*)::text) as md5_store from public.shop_store s where s.id = :'store'::uuid \gset
select (public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)->>'hash') as hash_fam0 \gset
savepoint t5;
update public.shop_store set note = coalesce(note, '') || '' where id = :'store'::uuid;                   -- 값 같은 update(touch 만) → 줄 0
select pg_temp.open_push(:'store'::uuid) as t5_q0 \gset
update public.shop_store set oos_policy = 'deny' where id = :'store'::uuid;
select pg_temp.open_push(:'store'::uuid) as t5_q1 \gset
select (select count(*)::text from regexp_split_to_table(pg_temp.policies(:'store'::uuid, :'fam'::uuid, null), ',') x where x like '%:DENY') || '/' || pg_temp.policies(:'store'::uuid, null, :'p_3907'::uuid) as t5_pol \gset
select ((public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)->>'hash') <> :'hash_fam0')::text as t5_hash \gset
select (select oos_policy from public.shop_store_list where id = :'store'::uuid) as t5_view \gset
update public.shop_store set oos_policy = 'deny' where id = :'store'::uuid;                                -- 같은 값 다시 → 줄 더 없음
select pg_temp.open_push(:'store'::uuid) as t5_q2 \gset
select pg_temp.err($q$update public.shop_store set oos_policy = 'maybe' where code = 'test'$q$) as t5_ck \gset
rollback to savepoint t5;
select pg_temp.chk('T5a note-only store update → 0 queue rows · oos_policy deny → both listed targets queued (reason store) · all 10 + ANN03907 DENY · hash changed · view shows deny · same value again → no new rows · check blocks maybe',
  :'t5_q0' || '/' || :'t5_q1' || '/' || :'t5_pol' || '/' || :'t5_hash' || '/' || :'t5_view' || '/' || :'t5_q2' || '/' || left(:'t5_ck', 5),
  '/ANN01001FAM:store,ANN03907:store/10/ANN03907:DENY/true/deny/ANN01001FAM:store,ANN03907:store/23514');
select pg_temp.chk('T5b after rollback: store row md5 unchanged · queue 0 open · policies CONTINUE again',
  ((select md5(row(s.*)::text) from public.shop_store s where s.id = :'store'::uuid) = :'md5_store')::text || '/' || pg_temp.open_push(:'store'::uuid) || '/' || pg_temp.policies(:'store'::uuid, null, :'p_3907'::uuid), 'true//ANN03907:CONTINUE');

-- ═══ T6 — blocks no_price 는 켜짐(is_active and sellable)으로 · deny 스토어 · 단종 변형에서도 잡는다 · savepoint ═══
select count(*)::text as price_1015_n from public.product_price pr where pr.product_id = :'p_1015'::uuid \gset
savepoint t6;
delete from public.product_price where product_id = :'p_1015'::uuid and tier_id = (select sale_tier_id from public.shop_store where id = :'store'::uuid);
select (public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)->'blocks')::text as t6_b_cont \gset
update public.shop_store set oos_policy = 'deny' where id = :'store'::uuid;
select (public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)->'blocks')::text as t6_b_deny \gset
update public.shop_store set oos_policy = 'continue' where id = :'store'::uuid;
update public.product set is_discontinued = true where id = :'p_1015'::uuid;
select (public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)->'blocks')::text || '/' || (pg_temp.policies(:'store'::uuid, :'fam'::uuid, null) like '%ANN01015:DENY%')::text as t6_b_disc \gset
update public.product set sellable = false where id = :'p_1015'::uuid;
select (public.shop_product_payload(:'store'::uuid, :'fam'::uuid, null)->'blocks')::text as t6_b_off \gset
rollback to savepoint t6;
select pg_temp.chk('T6a ANN01015 without sale price: blocked in continue store · blocked in deny store (old code missed this: policy DENY ≠ off) · blocked when discontinued (DENY) · not blocked once sellable off (truly off)',
  :'t6_b_cont' || '/' || :'t6_b_deny' || '/' || :'t6_b_disc' || '/' || :'t6_b_off', '["no_price:ANN01015"]/["no_price:ANN01015"]/["no_price:ANN01015"]/true/[]');
select pg_temp.chk('T6b after rollback: ANN01015 price rows back · row md5 unchanged · store continue',
  (select count(*)::text from public.product_price pr where pr.product_id = :'p_1015'::uuid) || '/' || ((select md5(row(p.*)::text) from public.product p where p.id = :'p_1015'::uuid) = :'md5_1015')::text || '/' || (select oos_policy from public.shop_store where id = :'store'::uuid), :price_1015_n || '/true/continue');

-- ═══ T7 — 창구 shop_store_save(가짜 admin · savepoint) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'shoppol-admin@test.invalid', 'SHOPPOL Admin', 'admin', '[]'::jsonb) returning auth_user_id::text as a_uid \gset
\set a_claims '{"sub":"' :a_uid '","role":"authenticated"}'
select jsonb_build_object('shop_domain', s.shop_domain, 'label', s.label, 'kind', s.kind, 'sale_tier', ts.name, 'compare_tier', tc.name, 'secret_prefix', s.secret_prefix)::text as old6
  from public.shop_store s join public.ref_price_tier ts on ts.id = s.sale_tier_id left join public.ref_price_tier tc on tc.id = s.compare_tier_id where s.id = :'store'::uuid \gset
select (:'old6'::jsonb || jsonb_build_object('oos_policy', 'continue'))::text as old7 \gset
savepoint t7;
set local role authenticated;
select set_config('request.jwt.claims', :'a_claims', true);
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'test', 'old', :'old6'::jsonb) || :'old6'::jsonb), false)::text as t7_a \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'test', 'old', :'old7'::jsonb, 'oos_policy', 'maybe') || :'old6'::jsonb), false)::text as t7_b \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'test', 'old', (:'old7'::jsonb || '{"oos_policy":"deny"}'::jsonb), 'oos_policy', 'deny') || :'old6'::jsonb), false)::text as t7_c \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'test', 'old', :'old7'::jsonb, 'oos_policy', 'deny') || :'old6'::jsonb), true)::text as t7_d \gset
select oos_policy as t7_d_row from public.shop_store where id = :'store'::uuid \gset
select pg_temp.open_push(:'store'::uuid) as t7_d_q \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'test', 'old', :'old6'::jsonb) || :'old6'::jsonb), true)::text as t7_e \gset
select oos_policy as t7_e_row from public.shop_store where id = :'store'::uuid \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'shoppol_x', 'shop_domain', 'shoppol-x.myshopify.com', 'label', 'Fake X', 'kind', 'asung', 'sale_tier', 'Wholesale', 'old', null)), true, array['shoppol_x:kind_active_dup'])::text as t7_f \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'shoppol_y', 'shop_domain', 'shoppol-y.myshopify.com', 'label', 'Fake Y', 'kind', 'aone', 'sale_tier', 'AONE', 'oos_policy', 'deny', 'old', null)), true)::text as t7_g \gset
select string_agg(code || '=' || oos_policy, ',' order by code) as t7_new from public.shop_store where code in ('shoppol_x', 'shoppol_y') \gset
reset role;
rollback to savepoint t7;
select pg_temp.chk('T7a old six only (current screen ss v1a) → no block · oos_policy maybe → oos_policy_invalid · stale old oos_policy → changed_elsewhere',
  ((:'t7_a'::jsonb->'blocks')::text = '[]')::text || '/' || (:'t7_b'::jsonb->'blocks'->0->>'code') || '/' || (:'t7_c'::jsonb->'blocks'->0->>'code'), 'true/oos_policy_invalid/changed_elsewhere');
select pg_temp.chk('T7b commit with oos_policy deny → committed · row deny · both targets queued (reason store) · then old six only without oos_policy → keeps deny (not reset)',
  (:'t7_d'::jsonb->>'committed') || '/' || :'t7_d_row' || '/' || :'t7_d_q' || '/' || (:'t7_e'::jsonb->>'committed') || '/' || :'t7_e_row', 'true/deny/ANN01001FAM:store,ANN03907:store/true/deny');
select pg_temp.chk('T7c new store without oos_policy → continue · new aone store with deny → deny · after rollback test store continue · fake stores gone · queue 0',
  :'t7_new' || '/' || (:'t7_f'::jsonb->>'committed') || '/' || (:'t7_g'::jsonb->>'committed') || '/' || (select oos_policy from public.shop_store where id = :'store'::uuid) || '/' || (select count(*)::text from public.shop_store where code like 'shoppol_%') || '/' || pg_temp.open_push(:'store'::uuid),
  'shoppol_x=continue,shoppol_y=deny/true/true/continue/0/');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select 'after rollback: push queue open ' || (select count(*) from public.shop_push_queue where done_at is null) || ' · fake staff ' || (select count(*) from public.ims_staff where email like 'shoppol-%') || ' · oos_policy column ' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_store' and column_name = 'oos_policy') || ' (trial run → 0 · applied DB → 1)';
select setval('public.shop_push_queue_id_seq', greatest(coalesce((select max(id) from public.shop_push_queue), 0), :q_seq_head::bigint, 1), (select count(*) > 0 from public.shop_push_queue));
select 'seq tail push ' || last_value || ' ' || is_called from public.shop_push_queue_id_seq;
select setval('public.shop_stock_queue_id_seq', greatest(coalesce((select max(id) from public.shop_stock_queue), 0), :sq_seq_head::bigint, 1), (select count(*) > 0 from public.shop_stock_queue));
select 'seq tail stock ' || last_value || ' ' || is_called from public.shop_stock_queue_id_seq;
