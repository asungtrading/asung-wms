-- sale-1-verify.sql — 지금 세일하는 제품(판정 361) · so_deal_products 식 한 곳 · so_sale_now · stk_availability(p_sale_only) · product_list (Asung-IMS · 2026-10-07)
--   기대: 시험 갈래 OK <머리> · 확인 갈래(G0 둘 없음) · MISMATCH 0 · 재료는 가짜만(SALE1-* · 가짜 딜 일곱 · 가짜 손님 · 직원) · 실제 딜은 읽기만(켜고 끄지 않는다) · 번호를 당기지 않는다 · 끝은 rollback
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261007202707_sale_1_sale_now.sql -f supabase/tests/sale-1-verify.sql 2>&1 | tee /tmp/sale-1.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다(D-pre 둘은 확인 갈래에서 새 함수)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
\echo '== seq head so' :so_seq_last :so_seq_called
select count(*) as n_deals, count(*) filter (where is_active and not is_order_level and not coupon_required) as n_line_deals from public.so_deal \gset
\echo '== deals on this DB' :n_deals '· active line deals' :n_line_deals

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql security definer as $$   -- definer: authenticated 구간(set local role)에서 불러도 t_res 에 쓴다(1회차 42501)
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create temp table t_pre as
  select p.proname as n, p.prosrc as src, pg_get_function_result(p.oid) as res from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public'
   and p.proname in ('so_deal_products', 'stk_availability', 'so_deal_candidates', 'so_deal_best', 'so_deal_customer_ok', 'so_deal_list', 'so_deal_detail', 'so_deal_save');
do $$
declare v_src text; v_res text;
begin
  select src into v_src from t_pre where n = 'so_deal_products';
  execute format('create function public.sale1_pre_products(p_deal_id uuid) returns table (product_id uuid, line_id uuid, line_no int, matched_by text[]) language plpgsql stable security definer set search_path = public, pg_temp as %L', v_src);
  select src, res into v_src, v_res from t_pre where n = 'stk_availability';
  execute format('create function public.sale1_pre_stk(p_warehouse_id uuid, p_q text default null, p_brand_id uuid default null, p_category_id uuid default null, p_include_zero boolean default false, p_limit int default 100, p_offset int default 0, p_sale_only boolean default false) returns %s language plpgsql stable security definer set search_path = public, pg_temp as %L', v_res, v_src);
end $$;
grant execute on function public.sale1_pre_stk(uuid, text, uuid, uuid, boolean, int, int, boolean) to authenticated;
\if :{?mig}
select pg_temp.chk('G0a so_deal_products last def = 20261007003838:1600~1627', (select md5(src) from t_pre where n = 'so_deal_products'), '243b8fce2d6136460bf7c0550a4e1c14');
select pg_temp.chk('G0b stk_availability last def = 20261006143300:118~217', (select md5(src) from t_pre where n = 'stk_availability'), '62dd512d5342761a83b99d43242ec2a6');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'no-error'; exception when others then return sqlerrm; end $$;
create function pg_temp.sale_of(p_sku text, p_on date default null) returns text language sql as $$
  select coalesce((select trim_scale(z.best_pct) || '/' || z.deal_count || '/' || z.conditional::text || '/' || (select string_agg((e->>'name') || ':' || trim_scale((e->>'pct')::numeric), ',') from jsonb_array_elements(z.deals) e)
                   from public.so_sale_now(array[(select id from public.product where sku = p_sku)], p_on) z), '-')
$$;
create function pg_temp.stk_canon(p_fn text, p_q text, p_zero boolean) returns text language plpgsql as $$
declare v text;
begin
  execute format('select md5(coalesce(string_agg(x.product_id::text || ''|'' || x.sku || ''|'' || coalesce(x.name, '''') || ''|'' || coalesce(x.brand_name, '''') || ''|'' || x.is_active::text || ''|'' || trim_scale(x.on_hand) || ''|'' || trim_scale(x.sales_allocated) || ''|'' || trim_scale(x.transfer_reserved) || ''|'' || trim_scale(x.available) || ''|'' || trim_scale(x.on_order) || ''|'' || trim_scale(x.in_transit) || ''|'' || coalesce(x.last_event_on::text, ''-'') || ''|'' || coalesce(x.matched_set_sku, ''-'') || ''|'' || coalesce(x.matched_set_count::text, ''-'') || ''|'' || x.total, E''\n'' order by x.sku, x.product_id), ''''))
                  from public.%I((select id from public.ref_warehouse where name = ''Asung Trading Inc.''), %L, null, null, %L, 500, 0) x', p_fn, p_q, p_zero) into v;
  return v;
end $$;

-- ═══ 재료 — 직원(master · sales) · 손님 · 브랜드 · 태그 · 제품 X(브랜드) · Y(브랜드 + 태그) · Ys(Y 의 세트) · Z(브랜드 · D1 에서 빼기 · 꺼짐) · 딜 일곱(D1 브랜드 15 · D2 태그 20 min 12 · D3 브랜드 5 손님 조건 · D4 내일부터 30 · D5 쿠폰 오더 딜 · D6 꺼진 딜 50 · D7 줄 꺼짐 40) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'sale1-master@test.invalid', 'SALE1 Master', 'manager', '["master","sales"]'::jsonb) returning auth_user_id::text as m_uid \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as tier, name as tier_name from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
select id::text as whx from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
insert into public.ref_brand (name) values ('SALE1 Brand') returning id::text as br \gset
insert into public.ref_category (name) values ('SALE1 Cat') returning id::text as ca \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('SALE1 Customer', 'manual', :'tier_name', :'whx'::uuid, 0) returning id::text as cust \gset
insert into public.product (sku, name, source, brand_id, brand_name, category_id, category_name) values ('SALE1-X', 'SALE1 Product X', 'manual', :'br'::uuid, 'SALE1 Brand', :'ca'::uuid, 'SALE1 Cat') returning id::text as px \gset
insert into public.product (sku, name, source, brand_id, brand_name, category_id, category_name) values ('SALE1-Y', 'SALE1 Product Y', 'manual', :'br'::uuid, 'SALE1 Brand', :'ca'::uuid, 'SALE1 Cat') returning id::text as py \gset
insert into public.product (sku, name, source, parent_product_id, pack_factor, brand_id, brand_name) values ('SALE1-Y-6', 'SALE1 Product Y x6', 'manual', :'py'::uuid, 6, :'br'::uuid, 'SALE1 Brand') returning id::text as pys \gset
insert into public.product (sku, name, source, brand_id, brand_name, is_active) values ('SALE1-Z', 'SALE1 Product Z (excluded · inactive)', 'manual', :'br'::uuid, 'SALE1 Brand', false) returning id::text as pz \gset
insert into public.product_tag (product_id, tag, source) values (:'py'::uuid, 'SALE1-T', 'manual');
select (public.ims_today() + 1)::text as tomorrow \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'SALE1 brand 15', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 15, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'brand', 'brand_id', :'br'), jsonb_build_object('kind', 'exclude', 'target', 'product', 'product_id', :'pz'))))), null, true, array['deal:new:open_orders_flagged']) as r \gset d1_
select public.so_deal_save(jsonb_build_object('name', 'SALE1 tag 20 min12', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 20, 'min_qty_mode', 'qty', 'min_qty', 12, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'SALE1-T'))))), null, true, array['deal:new:open_orders_flagged']) as r \gset d2_
select public.so_deal_save(jsonb_build_object('name', 'SALE1 brand 5 cust', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 5, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'brand', 'brand_id', :'br')))), 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), null, true, array['deal:new:open_orders_flagged']) as r \gset d3_
select public.so_deal_save(jsonb_build_object('name', 'SALE1 future 30', 'date_from', :'tomorrow', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 30, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'brand', 'brand_id', :'br'))))), null, true, array['deal:new:open_orders_flagged']) as r \gset d4_
select public.so_deal_save(jsonb_build_object('name', 'SALE1 coupon order 10', 'is_order_level', true, 'coupon_required', true, 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 10)), 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), null, true, array['deal:new:open_orders_flagged']) as r \gset d5_
select public.so_deal_save(jsonb_build_object('name', 'SALE1 off deal 50', 'is_active', false, 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 50, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'brand', 'brand_id', :'br'))))), null, true, array['deal:new:open_orders_flagged']) as r \gset d6_
select public.so_deal_save(jsonb_build_object('name', 'SALE1 line off 40', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 40, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'brand', 'brand_id', :'br'))))), null, true, array['deal:new:open_orders_flagged']) as r \gset d7_
reset role;
select (:'d1_r'::jsonb->>'deal_id') as d1, (:'d2_r'::jsonb->>'deal_id') as d2, (:'d3_r'::jsonb->>'deal_id') as d3, (:'d4_r'::jsonb->>'deal_id') as d4, (:'d5_r'::jsonb->>'deal_id') as d5, (:'d6_r'::jsonb->>'deal_id') as d6, (:'d7_r'::jsonb->>'deal_id') as d7, (:'d7_r'::jsonb->>'updated_at') as u7 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d7', 'lines', '[]'::jsonb), to_jsonb(:'u7'::text), true, array['deal:' || :'d7' || ':open_orders_flagged']) as r \gset d7b_
reset role;
select pg_temp.chk('M0 seven fake deals saved · D7 line turned off · none flagged any open order (fake products are in no order)', (select count(*) from public.so_deal where name like 'SALE1 %')::text || '/' || (select count(*) filter (where is_active) from public.so_deal_line where deal_id = :'d7'::uuid) || '/' || (:'d1_r'::jsonb->>'open_orders_to_flag') || (:'d2_r'::jsonb->>'open_orders_to_flag') || (:'d3_r'::jsonb->>'open_orders_to_flag') || (:'d7b_r'::jsonb->>'committed'), '7/0/000true');

-- ═══ E 식 한 곳 · 같음 ═══
select pg_temp.chk('E1 so_deal_products (thin wrapper) = old so_deal_products on every deal (rows ordered · all deals)', (select count(*) filter (where a.m is distinct from b.m)::text || '/' || count(*) from public.so_deal d cross join lateral (select md5(coalesce(string_agg(x.product_id::text || '|' || x.line_id::text || '|' || x.line_no || '|' || array_to_string(x.matched_by, ','), E'\n' order by x.product_id, x.line_id), '')) as m from public.so_deal_products(d.id) x) a cross join lateral (select md5(coalesce(string_agg(x.product_id::text || '|' || x.line_id::text || '|' || x.line_no || '|' || array_to_string(x.matched_by, ','), E'\n' order by x.product_id, x.line_id), '')) as m from public.sale1_pre_products(d.id) x) b), '0/' || (select count(*) from public.so_deal));
select pg_temp.chk('E2 sale set = ∪ so_deal_products over in-scope deals (active · line deal · not coupon · in period today) — both directions 0 · sale products count · in-scope deals count', (with sc as (select id from public.so_deal where is_active and not is_order_level and not coupon_required and kind = 'pct' and (date_from is null or date_from <= public.ims_today()) and (date_to is null or date_to >= public.ims_today())),
  a as (select distinct sc.id as deal_id, x.product_id from sc cross join lateral public.so_deal_products(sc.id) x),
  b as (select distinct (e->>'deal_id')::uuid as deal_id, z.product_id from public.so_sale_now(null, null) z cross join lateral jsonb_array_elements(z.deals) e)
  select (select count(*) from (select * from a except select * from b) q)::text || '/' || (select count(*) from (select * from b except select * from a) q) || '/' || (select count(*) from public.so_sale_now(null, null)) || '/' || (select count(*) from sc) || '/' || (select count(*) from (select distinct product_id from a) q)), (with sc as (select id from public.so_deal where is_active and not is_order_level and not coupon_required and kind = 'pct' and (date_from is null or date_from <= public.ims_today()) and (date_to is null or date_to >= public.ims_today())), a as (select distinct x.product_id from sc cross join lateral public.so_deal_products(sc.id) x) select '0/0/' || (select count(*) from a) || '/' || (select count(*) from sc) || '/' || (select count(*) from a)));
select pg_temp.chk('E3 out of scope never listed: coupon order deal D5 · off deal D6 · line-off deal D7 · future D4 · real order/coupon/off deals', (select count(*) from public.so_sale_now(null, null) z cross join lateral jsonb_array_elements(z.deals) e where (e->>'deal_id')::uuid in (:'d4'::uuid, :'d5'::uuid, :'d6'::uuid, :'d7'::uuid) or (e->>'deal_id')::uuid in (select id from public.so_deal where is_order_level or coupon_required or not is_active))::text, '0');

-- ═══ N 가짜 제품 — best · count · conditional · deals 순서 · 빼기 · 세트 · 날짜 ═══
select pg_temp.chk('N1 X (brand): D1 15 + D3 5 → best 15 · 2 deals · conditional (D3 customer rule) · deals pct desc', pg_temp.sale_of('SALE1-X'), '15/2/true/SALE1 brand 15:15,SALE1 brand 5 cust:5');
select pg_temp.chk('N2 Y (brand + tag): D2 20(min 12) · D1 15 · D3 5 → best 20 · 3 · conditional', pg_temp.sale_of('SALE1-Y'), '20/3/true/SALE1 tag 20 min12:20,SALE1 brand 15:15,SALE1 brand 5 cust:5');
select pg_temp.chk('N3 Ys (set of Y · ruling 302 · via base): same three deals · matched_by carries :base', pg_temp.sale_of('SALE1-Y-6') || ' » ' || (select (select string_agg(distinct m, ',' order by m) from jsonb_array_elements(z.deals) e, jsonb_array_elements_text(e->'matched_by') m) from public.so_sale_now(array[:'pys'::uuid], null) z), '20/3/true/SALE1 tag 20 min12:20,SALE1 brand 15:15,SALE1 brand 5 cust:5 » brand,brand:base,tag:base');
select pg_temp.chk('N4 Z (excluded in D1 · inactive product): D3 only → 5 · 1 · conditional · listed although inactive (screens filter)', pg_temp.sale_of('SALE1-Z'), '5/1/true/SALE1 brand 5 cust:5');
select pg_temp.chk('N5 p_on tomorrow: X gains D4 30 → best 30 · 3 deals · deals[0] date_from = tomorrow', pg_temp.sale_of('SALE1-X', :'tomorrow'::date) || ' » ' || (select z.deals->0->>'date_from' from public.so_sale_now(array[:'px'::uuid], :'tomorrow'::date) z), '30/3/true/SALE1 future 30:30,SALE1 brand 15:15,SALE1 brand 5 cust:5 » ' || :'tomorrow');
select pg_temp.chk('N6 deals entry keys: D2 min_qty_mode qty · min_qty 12 · customer_limited false / D3 customer_limited true · line_no 1', (select (e->>'min_qty_mode') || '/' || trim_scale((e->>'min_qty')::numeric) || '/' || (e->>'customer_limited') from public.so_sale_now(array[:'py'::uuid], null) z, jsonb_array_elements(z.deals) e where e->>'deal_id' = :'d2') || ' » ' || (select (e->>'customer_limited') || '/' || (e->>'line_no') from public.so_sale_now(array[:'py'::uuid], null) z, jsonb_array_elements(z.deals) e where e->>'deal_id' = :'d3'), 'qty/12/false » true/1');
select pg_temp.chk('N7 ids filter: unknown id → 0 rows · [] → 0 rows · null → all', (select count(*) from public.so_sale_now(array[gen_random_uuid()], null))::text || '/' || (select count(*) from public.so_sale_now('{}'::uuid[], null)) || '/' || ((select count(*) from public.so_sale_now(null, null)) > 0)::text, '0/0/true');

-- ═══ S stk_availability — p_sale_only 거짓 = 옛 함수와 같은 행(세 거르기) · 참 = 세일 낱개만 · 세일 열쇠 · X/Y/Z 낱개 줄 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select pg_temp.chk('S1 stk p_sale_only false = old rows (q null · include_zero false / q SALE1 · include_zero true / q null · include_zero true)', (pg_temp.stk_canon('stk_availability', null, false) = pg_temp.stk_canon('sale1_pre_stk', null, false))::text || '/' || (pg_temp.stk_canon('stk_availability', 'SALE1', true) = pg_temp.stk_canon('sale1_pre_stk', 'SALE1', true))::text || '/' || (pg_temp.stk_canon('stk_availability', null, true) = pg_temp.stk_canon('sale1_pre_stk', null, true))::text, 'true/true/true');
select pg_temp.chk('S2 stk q SALE1 · include_zero: three base rows X · Y · Z (set Ys is not a stock row) · sale_pct 15 · 20 · 5 · conditional all true', (select string_agg(x.sku || ':' || coalesce(trim_scale(x.sale_pct)::text, '-') || ':' || coalesce(x.sale_conditional::text, '-'), ',' order by x.sku) from public.stk_availability(:'whx'::uuid, 'SALE1', null, null, true, 100, 0, false) x), 'SALE1-X:15:true,SALE1-Y:20:true,SALE1-Z:5:true');
select pg_temp.chk('S3 stk p_sale_only true (include_zero): every row has sale_pct · count = base products on sale · total matches · fake three included', (select (bool_and(x.sale_pct is not null))::text || '/' || count(*) || '/' || min(x.total) || '/' || count(*) filter (where x.sku like 'SALE1-%') from public.stk_availability(:'whx'::uuid, null, null, null, true, 500, 0, true) x), 'true/' || (select count(*)::text from public.so_sale_now(null, null) z join public.product p on p.id = z.product_id where p.parent_product_id is null and not exists (select 1 from public.product_bom bm where bm.parent_product_id = p.id and bm.is_active)) || '/' || (select count(*)::text from public.so_sale_now(null, null) z join public.product p on p.id = z.product_id where p.parent_product_id is null and not exists (select 1 from public.product_bom bm where bm.parent_product_id = p.id and bm.is_active)) || '/3');
select pg_temp.chk('S4 stk p_sale_only true without include_zero: fake products have no stock → not listed · all listed rows still carry sale_pct', (select (count(*) filter (where x.sku like 'SALE1-%'))::text || '/' || coalesce(bool_and(x.sale_pct is not null)::text, 'true') from public.stk_availability(:'whx'::uuid, null, null, null, false, 500, 0, true) x), '0/true');
reset role;

-- ═══ L product_list — 화면 질의(listQuery)와 같은 행 · 순서(거르기 다섯) · total = count exact · 세일만 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select pg_temp.chk('L1 q SALE1 (sku or name ilike): same ids · order sku as the screen query · total 4', (select string_agg(x.id::text, ',' order by x.sku, x.id) || '|' || min(x.total) from public.product_list('SALE1', null, null, null, null, false, false, 100, 0) x), (select string_agg(p.id::text, ',' order by p.sku, p.id) || '|' || count(*) from public.product p where p.sku ilike '%SALE1%' or p.name ilike '%SALE1%'));
select pg_temp.chk('L2 brand_name eq + only_active + kind single: X · Y (Z inactive · Ys set)', (select string_agg(x.sku, ',' order by x.sku) || '|' || min(x.total) from public.product_list(null, 'SALE1 Brand', null, null, 'single', true, false, 100, 0) x), 'SALE1-X,SALE1-Y|2');
select pg_temp.chk('L3 category_name eq: X · Y (Ys and Z have no category) · kind set with brand: Ys', (select string_agg(x.sku, ',' order by x.sku) from public.product_list(null, null, 'SALE1 Cat', null, null, false, false, 100, 0) x) || ' » ' || (select string_agg(x.sku, ',' order by x.sku) from public.product_list(null, 'SALE1 Brand', null, null, 'set', false, false, 100, 0) x), 'SALE1-X,SALE1-Y » SALE1-Y-6');
select s.supplier_id::text as sup1 from (select ps.supplier_id, count(*) n from public.product_supplier ps where ps.is_active group by ps.supplier_id order by n desc limit 1) s \gset
select pg_temp.chk('L4 supplier filter (product_supplier active rows · !inner equivalent · real supplier · read only): same ids · same total as the direct query (first 100)', (select string_agg(x.id::text, ',' order by x.sku, x.id) || '|' || min(x.total) from public.product_list(null, null, null, :'sup1'::uuid, null, false, false, 100, 0) x), (select string_agg(q.id::text, ',' order by q.sku, q.id) || '|' || (select count(*) from public.product p where exists (select 1 from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = :'sup1'::uuid and ps.is_active)) from (select p.id, p.sku from public.product p where exists (select 1 from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = :'sup1'::uuid and ps.is_active) order by p.sku, p.id limit 100) q));
select pg_temp.chk('L5 paging: offset 1 limit 2 on q SALE1 → 2nd and 3rd skus · total still 4', (select string_agg(x.sku, ',' order by x.sku) || '|' || min(x.total) from public.product_list('SALE1', null, null, null, null, false, false, 2, 1) x), 'SALE1-Y,SALE1-Y-6|4');
select pg_temp.chk('L6 sale_only: q SALE1 → X · Y · Ys · Z all on sale (Ys via base · Z via D3) with pct · kind single + sale_only → X · Y · Z', (select string_agg(x.sku || ':' || trim_scale(x.sale_pct) || ':' || x.sale_conditional::text, ',' order by x.sku) from public.product_list('SALE1', null, null, null, null, false, true, 100, 0) x) || ' » ' || (select string_agg(x.sku, ',' order by x.sku) from public.product_list('SALE1', null, null, null, 'single', false, true, 100, 0) x), 'SALE1-X:15:true,SALE1-Y:20:true,SALE1-Y-6:20:true,SALE1-Z:5:true » SALE1-X,SALE1-Y,SALE1-Z');
select pg_temp.chk('L7 sale_only over all: count = so_sale_now rows · sale keys null off sale · bad p_kind refused', (select count(*)::text from public.product_list(null, null, null, null, null, false, true, 1000, 0)) || '/' || (select count(*) from public.so_sale_now(null, null)) || '/' || (select coalesce(x.sale_pct::text, 'null') from public.product_list(null, null, null, null, null, false, false, 1, 0) x where x.sale_pct is null limit 1) || '/' || pg_temp.try('select count(*) from public.product_list(null, null, null, null, ''bogus'', false, false, 10, 0)'), (select count(*)::text || '/' || count(*) from public.so_sale_now(null, null)) || '/null/p_kind must be single, set or all');
reset role;

-- ═══ T 비용(ms · 뜨거운 판) · P 권한 ═══
select count(*) from public.so_sale_now(null, null);
select clock_timestamp() as t0 \gset
select count(*) from public.so_sale_now(null, null);
select clock_timestamp() as t1 \gset
select count(*) from public.so_sale_now((select array_agg(id) from (select id from public.product where is_active order by sku limit 100) q), null);
select clock_timestamp() as t2 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select count(*) from public.stk_availability(:'whx'::uuid, null, null, null, false, 100, 0, true);
select clock_timestamp() as t3 \gset
select count(*) from public.stk_availability(:'whx'::uuid, null, null, null, false, 100, 0, false);
select clock_timestamp() as t4 \gset
select count(*) from public.product_list(null, null, null, null, null, true, true, 100, 0);
select clock_timestamp() as t5 \gset
select count(*) from public.product_list(null, null, null, null, null, true, false, 100, 0);
select clock_timestamp() as t6 \gset
reset role;
select 'T cost (ms · warm): so_sale_now all=' || round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000) || ' (' || (select count(*) from public.so_sale_now(null, null)) || ' products) · so_sale_now 100 ids=' || round(extract(epoch from (:'t2'::timestamptz - :'t1'::timestamptz)) * 1000) || ' · stk sale_only=' || round(extract(epoch from (:'t3'::timestamptz - :'t2'::timestamptz)) * 1000) || ' · stk all=' || round(extract(epoch from (:'t4'::timestamptz - :'t3'::timestamptz)) * 1000) || ' · product_list sale_only=' || round(extract(epoch from (:'t5'::timestamptz - :'t4'::timestamptz)) * 1000) || ' · product_list all=' || round(extract(epoch from (:'t6'::timestamptz - :'t5'::timestamptz)) * 1000);
set local role anon;
select pg_temp.try('select count(*) from public.so_sale_now(null, null)') as a1 \gset
select pg_temp.try('select count(*) from public.product_list()') as a2 \gset
select pg_temp.try('select count(*) from public.so_deal_products_all(null)') as a3 \gset
reset role;
select pg_temp.chk('P1 anon: so_sale_now · product_list · so_deal_products_all → permission denied', (:'a1' like 'permission denied%')::text || '/' || (:'a2' like 'permission denied%')::text || '/' || (:'a3' like 'permission denied%')::text, 'true/true/true');
select pg_temp.chk('P2 acl: so_sale_now · product_list · so_deal_products_all · stk authenticated yes · so_deal_products still revoked from authenticated · old stk signature gone', has_function_privilege('authenticated', 'public.so_sale_now(uuid[], date)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.product_list(text, text, text, uuid, text, boolean, boolean, int, int)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.so_deal_products_all(uuid[])', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.so_deal_products(uuid)', 'execute')::text || '/' || (to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int)') is null)::text, 'true/true/true/true/false/true');
select pg_temp.chk('P3 untouched md5 (so_deal_candidates · so_deal_best · so_deal_customer_ok · so_deal_list · so_deal_detail · so_deal_save = 6)', (select count(*)::text from t_pre t join pg_proc p on p.proname = t.n join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public' where t.n not in ('so_deal_products', 'stk_availability') and md5(p.prosrc) = md5(t.src)), '6');
select count(*)::text as d1_n from public.so_deal_products(:'d1'::uuid) \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select pg_temp.chk('P4 so_deal_list product_n_all for D1 (through so_deal_products · as staff) = so_deal_products count (as postgres · the inner function is revoked from staff)', (select (x->>'product_n_all') from jsonb_array_elements(public.so_deal_list()->'deals') x where coalesce(x->>'deal_id', x->>'id') = :'d1'), :'d1_n');
reset role;

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select 'seq tail so ' || last_value || ' ' || is_called from public.so_number_seq;
