-- ord-1a2-verify.sql — Shopify ④ 오더 받기 DB 둘째 차수: discount_source shopify · 다시 매기기 건너뛰기 · process · cancelled · resolve_lines · ingest 재발행 (Asung-IMS · 테스트)
--   기대: 시험 갈래(-v mig) OK 16 · 확인 갈래 OK 14(= 16 − 시험 전용 2: G0a · T1b) · MISMATCH 0 · 확인 갈래 전용 줄(\else)은 없다
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261011003000_ord_1a2_shop_order_process.sql -f supabase/tests/ord-1a2-verify.sql > /tmp/ord-1a2.out 2>&1; echo exit=$?
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다 · ⚠️ T6a 의 기대값은 ord-1b2(20261011020000 · ingest 재발행) 뒤의 것 — 1b2 전 DB 에서는 T6a 가 MISMATCH(경고 넷)
--   재료: 오더 원문은 pg_temp.ord() 가 손으로 만든 jsonb · 실제 손님 Debi Blair(72cf6eba · 이메일 하나 · Wholesale · Net30 · 할인 0)는 읽기만 · 20 % 케이스 딜(AAL10850 · 12 개 이상)은 시험 안에서 insert · 가짜 aone 스토어 · 가짜 직원 · 만들어지는 SO 는 전부 rollback
--   ⚠️ so_number_seq 는 rollback 되지 않는다 — 머리를 읽고 끝에서 greatest(실제 최대, 머리)로 되돌린다 · 실제 행 변경 0
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value::text as so_seq_head, is_called::text as so_seq_called from public.so_number_seq \gset
\echo '== head so seq' :so_seq_head :so_seq_called
begin;
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
select string_agg(proname || ':' || md5(prosrc), ',' order by proname) as h0_untouched from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_line_add', 'so_charge_set', 'so_payment_add', 'so_confirm', 'so_cancel', 'so_tax_refresh', 'so_header_update', 'so_finalize', 'so_lines_paste', 'customer_create', 'shop_order_prepare', 'shop_order_resolve_customer') \gset
select string_agg(proname || ':' || md5(prosrc), ',' order by proname) as h0_changed from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_create', 'so_line_requote', 'so_line_update', 'so_reprice', 'shop_order_ingest') \gset
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
create function pg_temp.err_inv(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'no-error'; exception when others then return sqlstate || ' ' || sqlerrm; end $$;
-- 오더 원문 — ① 모양 · p_lines = [{sku, qty, list, unit}] · p_ship = 운임 {orig, disc, title} · p_extra 로 덮기
create function pg_temp.ord(p_gid text, p_name text, p_email text, p_cust_gid text, p_prov text, p_lines jsonb, p_tax text, p_fin text default 'PENDING', p_ship jsonb default null, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select (jsonb_build_object('id', p_gid, 'name', p_name, 'createdAt', '2026-10-10T20:00:00Z', 'updatedAt', '2026-10-10T20:00:00Z', 'cancelledAt', null, 'test', true,
            'displayFinancialStatus', p_fin, 'sourceName', '2627105', 'email', p_email, 'phone', '555-0100', 'poNumber', 'PO-' || p_name, 'note', 'leave at door',
            'customer', case when p_cust_gid is null then null else jsonb_build_object('id', p_cust_gid, 'firstName', 'Debi', 'lastName', 'Blair', 'displayName', 'Debi Blair', 'defaultEmailAddress', jsonb_build_object('emailAddress', p_email)) end,
            'shippingAddress', jsonb_build_object('name', 'Debi Blair', 'company', 'Debi Salon', 'address1', '1 Test St', 'city', 'Somewhere', 'provinceCode', p_prov, 'zip', 'A1A 1A1', 'countryCodeV2', 'CA', 'phone', '555-0100'),
            'billingAddress', jsonb_build_object('name', 'Debi Blair', 'address1', '1 Test St', 'city', 'Somewhere', 'provinceCode', coalesce(p_prov, 'ON'), 'zip', 'A1A 1A1', 'countryCodeV2', 'CA'),
            'currencyCode', 'CAD',
            'subtotalPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', to_char((select sum((l->>'unit')::numeric * (l->>'qty')::numeric) from jsonb_array_elements(p_lines) l), 'FM999999990.00'))),
            'totalDiscountsSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', to_char((select sum(((l->>'list')::numeric - (l->>'unit')::numeric) * (l->>'qty')::numeric) from jsonb_array_elements(p_lines) l), 'FM999999990.00'))),
            'totalShippingPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', coalesce(p_ship->>'disc', '0.00'))),
            'totalTaxSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', p_tax)),
            'totalPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', to_char((select sum((l->>'unit')::numeric * (l->>'qty')::numeric) from jsonb_array_elements(p_lines) l) + coalesce((p_ship->>'disc')::numeric, 0) + p_tax::numeric, 'FM999999990.00'))),
            'shippingLines', jsonb_build_object('nodes', case when p_ship is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('title', coalesce(p_ship->>'title', 'Standard'), 'originalPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', p_ship->>'orig')), 'discountedPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', p_ship->>'disc')))) end),
            'lineItems', jsonb_build_object('nodes', (select coalesce(jsonb_agg(jsonb_build_object('id', 'gid://shopify/LineItem/' || t.n, 'sku', l->>'sku', 'name', 'Item ' || (l->>'sku'), 'quantity', (l->>'qty')::numeric,
                              'originalUnitPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', l->>'list')), 'discountedUnitPriceAfterAllDiscountsSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', l->>'unit')),
                              'totalDiscountSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', to_char(((l->>'list')::numeric - (l->>'unit')::numeric) * (l->>'qty')::numeric, 'FM999999990.00'))))), '[]'::jsonb) from jsonb_array_elements(p_lines) with ordinality as t(l, n))))
         ) || p_extra;
$$;
create function pg_temp.warns(p_id uuid) returns text language sql security definer as $$
  select coalesce(string_agg(r->>'code', ',' order by r->>'code'), '') from public.shop_order o, jsonb_array_elements(o.warnings) r where o.id = p_id;
$$;
create function pg_temp.lines(p_so uuid) returns text language sql security definer as $$
  select string_agg(l.sku || ':' || l.qty_ordered || ':' || coalesce(l.discount_pct::text, '-') || ':' || coalesce(l.discount_source, '-') || ':' || round(l.unit_price, 2), ',' order by s.so_number, l.line_no)
    from public.so_line l join public.so s on s.id = l.so_id where (s.id = p_so or s.split_from_id = p_so) and l.combo_line_id is null;
$$;
\if :{?mig}
select pg_temp.chk('G0a trial marker: so_line_set_shopify exists only after the trial apply', (to_regprocedure('public.so_line_set_shopify(uuid, numeric, numeric)') is not null)::text, 'true');
\endif

-- ═══ 재료 ═══
select id::text as store from public.shop_store where code = 'test' \gset
select id::text as wh_to from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as wh_ed from public.ref_warehouse where name = 'Asung - Edmonton' \gset
select s.id::text as sys_id from public.ims_staff s where s.is_system \gset
select '72cf6eba-13ba-4670-95dd-0a9733cb5c4c' as c_debi \gset
select id::text as p_10850 from public.product where sku = 'AAL10850' \gset
select count(*)::text as so_head from public.so \gset
insert into public.so_deal (name, source, is_order_level, kind) values ('ORD1A2 case 20', 'manual', false, 'pct') returning id::text as deal \gset
insert into public.so_deal_line (deal_id, line_no, pct, min_qty_mode, min_qty, source) values (:'deal'::uuid, 1, 20, 'qty', 12, 'manual') returning id::text as dline \gset
insert into public.so_deal_target (line_id, kind, target, product_id, source) values (:'dline'::uuid, 'include', 'product', :'p_10850'::uuid, 'manual');
select coalesce(pct::text, 'null') as deal_pct from public.so_deal_best(:'p_10850'::uuid, :'c_debi'::uuid, 12, public.ims_today(), null) \gset
select to_char(public.so_tax_amount(75.72, 5) + public.so_tax_amount(7.89, 5) + public.so_tax_amount(7.89, 5), 'FM999999990.00') as tax_ab_9150 from (select 1) z \gset
-- (IMS 세금은 줄마다 반올림 · so_tax_preview · \gset 줄에는 주석을 달 수 없다)
select to_char(public.so_tax_amount(7.89, 5), 'FM999999990.00') as tax_ab_789 from (select 1) z \gset
select to_char(public.so_tax_amount(7.34, 5), 'FM999999990.00') as tax_ab_734 from (select 1) z \gset
select to_char(public.so_tax_amount(7.89, 5) + public.so_tax_amount(9.99, 5), 'FM999999990.00') as tax_ab_aone from (select 1) z \gset
select to_char(public.so_tax_amount(7.89, 13), 'FM999999990.00') as tax_on_789 from (select 1) z \gset
insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, oos_policy) values ('ord1a2_aone', 'ord1a2-aone.myshopify.com', 'Fake aone', 'aone', (select id from public.ref_price_tier where name = 'AONE'), 'deny') returning id::text as aone \gset
insert into public.shop_location (store_id, shopify_location_gid, warehouse_id) values (:'aone'::uuid, 'gid://shopify/Location/990000000002', :'wh_to'::uuid);
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'ord1a2-sales@test.invalid', 'ORD1A2 Sales', 'manager', '["sales"]'::jsonb) returning auth_user_id::text as s_uid, id::text as s_sid \gset
\set s_claims '{"sub":"' :s_uid '","role":"authenticated"}'
select coalesce(current_setting('request.jwt.claims', true), '') as claims0 \gset

-- ═══ T1 — 객체 · 권한 · 재발행 ═══
select pg_temp.chk('T1a discount_source CHECK has shopify · shop_order_so_ck relaxed · so_baseline_at column · functions 4 · privileges (authenticated: resolve_lines only · none on process · cancelled · set_shopify) · view so_baseline_at · deal fixture gives 20 at qty 12',
  ((select pg_get_constraintdef(oid) from pg_constraint where conname = 'so_line_discount_source_ck') like '%shopify%')::text || '/' || ((select pg_get_constraintdef(oid) from pg_constraint where conname = 'shop_order_so_ck') like '%<> ''created''%')::text || '/' ||
  (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'shop_order' and column_name = 'so_baseline_at') || '/' ||
  (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_line_set_shopify', 'shop_order_process', 'shop_order_cancelled', 'shop_order_resolve_lines') and prosecdef) || '/' ||
  has_function_privilege('authenticated', 'public.shop_order_resolve_lines(uuid, jsonb, boolean, text[])', 'execute')::text || '/' ||
  (has_function_privilege('authenticated', 'public.shop_order_process(uuid)', 'execute') or has_function_privilege('authenticated', 'public.shop_order_cancelled(uuid)', 'execute') or has_function_privilege('authenticated', 'public.so_line_set_shopify(uuid, numeric, numeric)', 'execute'))::text || '/' ||
  (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'shop_order_list' and column_name = 'so_baseline_at') || '/' || :'deal_pct',
  'true/true/1/4/true/false/1/20');
\if :{?mig}
select pg_temp.chk('T1b (trial) twelve untouched functions byte-identical · five re-issued changed (so_create · so_line_requote · so_line_update · so_reprice · shop_order_ingest)',
  (:'h0_untouched' = (select string_agg(proname || ':' || md5(prosrc), ',' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_line_add', 'so_charge_set', 'so_payment_add', 'so_confirm', 'so_cancel', 'so_tax_refresh', 'so_header_update', 'so_finalize', 'so_lines_paste', 'customer_create', 'shop_order_prepare', 'shop_order_resolve_customer')))::text || '/' ||
  (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_create', 'so_line_requote', 'so_line_update', 'so_reprice', 'shop_order_ingest') and position(proname || ':' || md5(prosrc) in :'h0_changed') = 0), 'true/5');
\endif

-- ═══ T2 — 깨끗한 asung 오더(NetTerm · AB · 줄 셋 · 20 % 케이스 한 줄 = IMS 딜) → SO 확정 · shopify 줄 · 어긋남 0 · 결제 0 · 운임은 담기만 ═══
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000021', 'AS-T0021', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10850","qty":12,"list":"7.89","unit":"6.31"},{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"},{"sku":"AAL10850","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_9150', 'PENDING', '{"orig":"11.69","disc":"11.69","title":"Expedited Parcel"}'::jsonb))->>'shop_order_id' as o21 \gset
select public.shop_order_process(:'o21'::uuid)::text as t2_a \gset
select so_id::text as so21 from public.shop_order where id = :'o21'::uuid \gset
select pg_temp.chk('T2a process → created · SO confirmed · intake shopify · ref = Shopify name · Edmonton · ship-to AB (Shopify address) · tax GST · comments PO + note · created_by system · lines all shopify (20.03 / 0 / 0 · Shopify unit kept · stock-short split keeps the discount) · warnings only freight_not_applied (asung) · no payment · no charge · claims restored',
  (:'t2_a'::jsonb->>'status') || '/' || (:'t2_a'::jsonb->>'so_status') || '/' || (:'t2_a'::jsonb->>'confirmed') || '/' ||
  (select intake || '/' || ref || '/' || location_name || '/' || ship_to_state_province || '/' || tax_rule || '/' || (comments like 'PO PO-AS-T0021 · leave at door%')::text || '/' || (created_by = :'sys_id'::uuid)::text from public.so where id = :'so21'::uuid) || '/' ||
  (select count(*)::text || ':' || count(*) filter (where l.discount_source = 'shopify') || ':' || string_agg(distinct l.discount_pct::text, '|' order by l.discount_pct::text) from public.so_line l join public.so s on s.id = l.so_id where (s.id = :'so21'::uuid or s.split_from_id = :'so21'::uuid) and l.combo_line_id is null) || '/' ||
  pg_temp.warns(:'o21'::uuid) || '/' || (select count(*)::text from public.so_payment_order where so_id = :'so21'::uuid) || '/' || (select count(*)::text from public.so_charge where so_id = :'so21'::uuid) || '/' || (coalesce(current_setting('request.jwt.claims', true), '') = :'claims0')::text,
  'created/confirmed/true/shopify/AS-T0021/Asung - Edmonton/AB/GST (Sale)/true/true/4:4:0.00|20.03/freight_not_applied/0/0/true');
select pg_temp.chk('T2b shop_order: so_id · processed_at · so_baseline_at set · shop_order_line.so_line_id filled for the 3 lines · view so_number · so_status · process again → skipped (not received)',
  (select (so_id is not null)::text || '/' || (processed_at is not null)::text || '/' || (so_baseline_at is not null)::text from public.shop_order where id = :'o21'::uuid) || '/' ||
  (select count(*)::text from public.shop_order_line where shop_order_id = :'o21'::uuid and so_line_id is not null) || '/' || (select (so_number is not null)::text || '/' || so_status from public.shop_order_list where id = :'o21'::uuid) || '/' || (public.shop_order_process(:'o21'::uuid)->>'skipped'),
  'true/true/true/3/true/confirmed/true');

-- ═══ T3 — 할인 어긋남(431 ③) · 세금 어긋남(368) ═══
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000022', 'AS-T0022', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.34"}]'::jsonb, :'tax_ab_734'))->>'shop_order_id' as o22 \gset
select public.shop_order_process(:'o22'::uuid)::text as t3_a \gset
select so_id::text as so22 from public.shop_order where id = :'o22'::uuid \gset
select pg_temp.chk('T3a Shopify 7 % on a line IMS gives 0 % → created · warning discount_mismatch (sku · shopify 6.97 · ims 0) · SO line keeps Shopify unit 7.34 · pct 6.97 · source shopify',
  (:'t3_a'::jsonb->>'status') || '/' || (select r->>'sku' || ':' || (r->>'shopify_pct') || ':' || (r->>'ims_pct') from public.shop_order o, jsonb_array_elements(o.warnings) r where o.id = :'o22'::uuid and r->>'code' = 'discount_mismatch') || '/' || pg_temp.lines(:'so22'::uuid),
  'created/AAL10925:6.97:0/AAL10925:1:6.97:shopify:7.34');
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000023', 'AS-T0023', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, '9.99'))->>'shop_order_id' as o23 \gset
select public.shop_order_process(:'o23'::uuid)::text as t3_b \gset
select pg_temp.chk('T3b Shopify tax 9.99 vs IMS GST → warning tax_mismatch (ims = so_tax_amount · shopify 9.99) · still created and confirmed',
  (:'t3_b'::jsonb->>'status') || '/' || (:'t3_b'::jsonb->>'so_status') || '/' || (select (r->>'ims') || ':' || (r->>'shopify') from public.shop_order o, jsonb_array_elements(o.warnings) r where o.id = :'o23'::uuid and r->>'code' = 'tax_mismatch'),
  'created/confirmed/' || :'tax_ab_789'::numeric || ':9.99');

-- ═══ T4 — aone(PAID · 배송비 9.99 · 무료 배송 한 건) → Toronto · 운임 줄 · 100 % 할인 줄 · 결제 줄 · 확정 ═══
select public.shop_order_ingest(:'aone'::uuid, pg_temp.ord('gid://shopify/Order/900000000031', '#1031', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_aone', 'PAID', '{"orig":"9.99","disc":"9.99","title":"Local delivery"}'::jsonb))->>'shop_order_id' as o31 \gset
select public.shop_order_process(:'o31'::uuid)::text as t4_a \gset
select so_id::text as so31 from public.shop_order where id = :'o31'::uuid \gset
select public.shop_order_ingest(:'aone'::uuid, pg_temp.ord('gid://shopify/Order/900000000032', '#1032', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'ON',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_on_789', 'PAID', '{"orig":"9.99","disc":"0.00","title":"Free shipping"}'::jsonb))->>'shop_order_id' as o32 \gset
select public.shop_order_process(:'o32'::uuid)::text as t4_b \gset
select so_id::text as so32 from public.shop_order where id = :'o32'::uuid \gset
select pg_temp.chk('T4a aone paid order with AB address → Toronto (one pair · 427) · confirmed · freight charge 9.99 no discount · payment shopify = total targeting the SO · no tax warning (GST on lines + freight · tax follows the AB ship-to) · no freight_not_applied',
  (:'t4_a'::jsonb->>'status') || '/' || (:'t4_a'::jsonb->>'so_status') || '/' || (select location_name from public.so where id = :'so31'::uuid) || '/' ||
  (select name || ':' || amount || ':' || coalesce(discount_pct::text, '-') from public.so_charge where so_id = :'so31'::uuid) || '/' ||
  (select p.method || ':' || p.amount || ':' || p.reference from public.so_payment p join public.so_payment_order o on o.payment_id = p.id where o.so_id = :'so31'::uuid) || '/' || pg_temp.warns(:'o31'::uuid),
  'created/confirmed/Asung Trading Inc./Local delivery:9.99:-/shopify:' || (7.89 + 9.99 + :'tax_ab_aone'::numeric)::text || ':#1031/');
select pg_temp.chk('T4b aone free shipping → freight charge 9.99 with 100 % discount · net 0 · payment = goods + tax · confirmed',
  (:'t4_b'::jsonb->>'so_status') || '/' || (select name || ':' || amount || ':' || discount_pct || ':' || (amount - public.so_charge_discount(amount, discount_pct, discount_amount)) from public.so_charge where so_id = :'so32'::uuid) || '/' ||
  (select p.amount::text from public.so_payment p join public.so_payment_order o on o.payment_id = p.id where o.so_id = :'so32'::uuid),
  'confirmed/Free shipping:9.99:100:0.00/' || (7.89 + :'tax_on_789'::numeric)::text);

-- ═══ T5 — 확정 막기(세금 규칙 없음) → SO draft · warnings confirm_blocked · 그 draft 로 433 ═══
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000041', 'AS-T0041', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', null,
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.34"},{"sku":"AAL10850","qty":12,"list":"7.89","unit":"6.31"}]'::jsonb, '0.00', 'PENDING', null,
  '{"shippingAddress":{"name":"Debi Blair","address1":"1 Far St","city":"Nowhere","provinceCode":null,"zip":"00000","countryCodeV2":"CA"}}'::jsonb))->>'shop_order_id' as o41 \gset
select public.shop_order_process(:'o41'::uuid)::text as t5_a \gset
select so_id::text as so41 from public.shop_order where id = :'o41'::uuid \gset
select pg_temp.chk('T5a no province (CA · null) → no tax rule → created but SO draft · confirmed false · warning confirm_blocked mentions the tax rule · claims restored',
  (:'t5_a'::jsonb->>'status') || '/' || (:'t5_a'::jsonb->>'so_status') || '/' || (:'t5_a'::jsonb->>'confirmed') || '/' || (select (r->>'message' like '%tax rule%')::text from public.shop_order o, jsonb_array_elements(o.warnings) r where o.id = :'o41'::uuid and r->>'code' = 'confirm_blocked') || '/' || (coalesce(current_setting('request.jwt.claims', true), '') = :'claims0')::text,
  'created/draft/false/true/true');
savepoint t5;
set local role authenticated;
select set_config('request.jwt.claims', :'s_claims', true);
select l.id::text as l41 from public.so_line l where l.so_id = :'so41'::uuid and l.sku = 'AAL10925' \gset
select (public.so_line_update(:'l41'::uuid, '{"qty_ordered": 5}'::jsonb)->'line') as t5_line \gset
select public.so_line_add(:'so41'::uuid, (select id from public.product where sku = 'AAL10850'), 1) as t5_merge \gset
select public.so_line_add(:'so41'::uuid, (select id from public.product where sku = 'AAL11056'), 1)->'line'->>'discount_source' as t5_add_src \gset
select public.so_reprice(:'so41'::uuid)::text as t5_rep \gset
reset role;
rollback to savepoint t5;
select pg_temp.chk('T5b (판정 433) staff changes qty of a shopify line 1 → 5 → discount 6.97 % and source shopify kept · staff adds the same SKU as the shopify line → merged into it (qty 13 · 20.03 % kept) · another SKU quotes as customer · so_reprice keeps both shopify lines (reason shopify_discount) and re-quotes the customer line',
  (:'t5_line'::jsonb->>'qty_ordered') || '/' || (:'t5_line'::jsonb->>'discount_pct') || '/' || (:'t5_line'::jsonb->>'discount_source') || '/' || (:'t5_merge'::jsonb->>'action') || ':' || (:'t5_merge'::jsonb->'line'->>'qty_ordered') || ':' || (:'t5_merge'::jsonb->'line'->>'discount_pct') || ':' || (:'t5_merge'::jsonb->'line'->>'discount_source') || '/' || :'t5_add_src' || '/' ||
  (select string_agg((r->>'sku') || ':' || (r->>'kept') || ':' || coalesce(r->>'reason', '-'), ',' order by (r->>'line_no')::int) from jsonb_array_elements(:'t5_rep'::jsonb->'lines') r),
  '5/6.97/shopify/merged:13:20.03:shopify/customer/AAL10925:true:shopify_discount,AAL10850:true:shopify_discount,AAL11056:false:-');

-- ═══ T6 — 취소(434): 손 안 댄 confirmed → 자동 취소 · 손댄 draft → 경고 · 창고로 간 것 → 경고 ═══
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000021', 'AS-T0021', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10850","qty":12,"list":"7.89","unit":"6.31"},{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"},{"sku":"AAL10850","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_9150', 'PENDING', '{"orig":"11.69","disc":"11.69","title":"Expedited Parcel"}'::jsonb,
  '{"updatedAt":"2026-10-10T21:00:00Z","cancelledAt":"2026-10-10T21:00:00Z"}'::jsonb))::text as t6_a \gset
select pg_temp.chk('T6a untouched confirmed SO + Shopify cancel → auto cancelled: shop_order cancelled · SO (and its stock-short sibling) cancelled · reserves released · warnings auto_cancelled only (ord-1b2 20261011020000: updated_after_so · cancelled_in_shopify are not kept after an automatic cancel) · so_id kept',
  (:'t6_a'::jsonb->>'action') || '/' || (select status || '/' || (so_id is not null)::text from public.shop_order where id = :'o21'::uuid) || '/' ||
  (select string_agg(status, ',' order by so_number) from public.so where id = :'so21'::uuid or split_from_id = :'so21'::uuid) || '/' ||
  (select count(*)::text from public.so_reserve r join public.so_line l on l.id = r.so_line_id join public.so s on s.id = l.so_id where (s.id = :'so21'::uuid or s.split_from_id = :'so21'::uuid) and r.released_at is null) || '/' || pg_temp.warns(:'o21'::uuid),
  'updated_after_created/cancelled/true/cancelled,cancelled/0/auto_cancelled,freight_not_applied');
savepoint t6;
update public.shop_order set so_baseline_at = now() - interval '1 minute' where id = :'o41'::uuid;                                -- 한 트랜잭션 안에서는 now() 가 멈춰 있다 — SO 를 1 분 전에 만든 것으로(ims_touch 의 updated_at = now() 가 기준 뒤가 되게)
set local role authenticated;
select set_config('request.jwt.claims', :'s_claims', true);
select public.so_header_update(:'so41'::uuid, '{"comments": "staff touched this"}'::jsonb)->>'so_number' as t6_touch \gset
reset role;
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000041', 'AS-T0041', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', null,
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.34"},{"sku":"AAL10850","qty":12,"list":"7.89","unit":"6.31"}]'::jsonb, '0.00', 'PENDING', null,
  '{"shippingAddress":{"name":"Debi Blair","address1":"1 Far St","city":"Nowhere","provinceCode":null,"zip":"00000","countryCodeV2":"CA"},"updatedAt":"2026-10-10T21:10:00Z","cancelledAt":"2026-10-10T21:10:00Z"}'::jsonb))::text as t6_b \gset
select (select status from public.shop_order where id = :'o41'::uuid) || '/' || (select status from public.so where id = :'so41'::uuid) || '/' || (select r->>'reason' from public.shop_order o, jsonb_array_elements(o.warnings) r where o.id = :'o41'::uuid and r->>'code' = 'cancel_needs_review') as t6_b_res \gset
rollback to savepoint t6;
update public.so set status = 'at_wms', at_wms_at = now() where id = :'so22'::uuid;                                            -- 창고로 보낸 것을 흉내(confirmed → at_wms 는 guard 가 허락)
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000022', 'AS-T0022', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.34"}]'::jsonb, :'tax_ab_734', 'PENDING', null, '{"updatedAt":"2026-10-10T21:20:00Z","cancelledAt":"2026-10-10T21:20:00Z"}'::jsonb))::text as t6_c \gset
select pg_temp.chk('T6b staff touched the draft SO (comments) → Shopify cancel → warning only (cancel_needs_review changed_in_ims) · shop_order stays created · SO stays draft; SO at the warehouse (at_wms) → cancel_needs_review in_warehouse · SO untouched',
  :'t6_b_res' || '/' || (select status from public.shop_order where id = :'o22'::uuid) || '/' || (select status from public.so where id = :'so22'::uuid) || '/' || (select r->>'reason' from public.shop_order o, jsonb_array_elements(o.warnings) r where o.id = :'o22'::uuid and r->>'code' = 'cancel_needs_review'),
  'created/draft/changed_in_ims/created/at_wms/in_warehouse');
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000024', 'AS-T0024', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_789', 'PENDING', null, '{"cancelledAt":"2026-10-10T20:30:00Z"}'::jsonb))::text as t6_d \gset
select pg_temp.chk('T6c order already cancelled in Shopify when first received → cancelled without an SO · process on it → skipped',
  (:'t6_d'::jsonb->>'status') || '/' || (select (so_id is null)::text from public.shop_order where id = (:'t6_d'::jsonb->>'shop_order_id')::uuid) || '/' || (public.shop_order_process((:'t6_d'::jsonb->>'shop_order_id')::uuid)->>'skipped'),
  'cancelled/true/true');

-- ═══ T7 — resolve_lines(366): 모르는 SKU → 직원이 잇기 · 빼기(ack) → received → process → created ═══
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000051', 'AS-T0051', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"NOPE-1","qty":2,"list":"7.89","unit":"7.89"},{"sku":"NOPE-2","qty":1,"list":"1.00","unit":"1.00"},{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_789'))->>'shop_order_id' as o51 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'s_claims', true);
select public.shop_order_resolve_lines(:'o51'::uuid, '[{"line_no": 1, "sku": "AAL10850"}, {"line_no": 2, "drop": true}]'::jsonb, false)::text as t7_pre \gset
select public.shop_order_resolve_lines(:'o51'::uuid, '[{"line_no": 1, "sku": "AAL10850"}, {"line_no": 2, "drop": true}]'::jsonb, true)::text as t7_unack \gset
select public.shop_order_resolve_lines(:'o51'::uuid, '[{"line_no": 1, "sku": "AAL10850"}, {"line_no": 2, "drop": true}]'::jsonb, true, array['drop:2'])::text as t7_go \gset
select public.shop_order_resolve_lines(:'o51'::uuid, '[{"line_no": 1, "sku": "17251"}]'::jsonb, true)->'blocks'->0->>'code' as t7_bad \gset
reset role;
select set_config('request.jwt.claims', '', true);
select public.shop_order_process(:'o51'::uuid)::text as t7_proc \gset
select pg_temp.chk('T7a resolve_lines: preview → plan replace + drop · commit without ack → unacked drop:2 · with ack → committed · received · 2 lines left (AAL10850 · AAL10925) · inactive SKU → block product_inactive · then process → created · SO lines 2 with shopify source',
  (select count(*)::text from jsonb_array_elements(:'t7_pre'::jsonb->'plan')) || '/' || (:'t7_pre'::jsonb->>'committed') || '/' || (:'t7_unack'::jsonb->'unacked')::text || '/' || (:'t7_go'::jsonb->>'committed') || '/' || (:'t7_go'::jsonb->'prepare'->>'status') || '/' ||
  (select string_agg(sku, ',' order by line_no) from public.shop_order_line where shop_order_id = :'o51'::uuid) || '/' || :'t7_bad' || '/' ||
  (:'t7_proc'::jsonb->>'status') || '/' || (select count(*)::text || ':' || count(*) filter (where l.discount_source = 'shopify') from public.so_line l join public.so s on s.id = l.so_id where (s.id = (:'t7_proc'::jsonb->>'so_id')::uuid or s.split_from_id = (:'t7_proc'::jsonb->>'so_id')::uuid) and l.combo_line_id is null),
  '2/false/["drop:2"]/true/received/AAL10850,AAL10925/product_inactive/created/2:2');

-- ═══ T8 — 문 · 실패 경로 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'s_claims', true);
select pg_temp.err_inv(format('select public.shop_order_process(%L)', :'o51')) as t8_p \gset
select pg_temp.err_inv(format('select public.shop_order_cancelled(%L)', :'o51')) as t8_c \gset
select pg_temp.err_inv(format('select public.so_line_set_shopify(%L, 1, 0)', :'l41')) as t8_s \gset
reset role;
select set_config('request.jwt.claims', '', true);
select coalesce(current_setting('request.jwt.claims', true), '') as claims_t8 \gset
select id::text as c_off from public.customer where not is_active limit 1 \gset
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000061', 'AS-T0061', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_789'))->>'shop_order_id' as o61 \gset
select count(*)::text as so_before from public.so \gset
update public.shop_order set customer_id = :'c_off'::uuid where id = :'o61'::uuid;                                              -- 실패를 만든다: so_create 가 「inactive」 로 거부
select public.shop_order_process(:'o61'::uuid)::text as t8_e \gset
select pg_temp.chk('T8a authenticated cannot execute process · cancelled · so_line_set_shopify (42501) · failing process → status error · error text · no SO created · claims restored',
  left(:'t8_p', 5) || '/' || left(:'t8_c', 5) || '/' || left(:'t8_s', 5) || '/' || (:'t8_e'::jsonb->>'status') || '/' || (select status || '/' || (error like '%inactive%')::text || '/' || (so_id is null)::text from public.shop_order where id = :'o61'::uuid) || '/' ||
  ((select count(*) from public.so) - :so_before::int)::text || '/' || (coalesce(current_setting('request.jwt.claims', true), '') = :'claims_t8')::text,
  '42501/42501/42501/error/error/true/true/0/true');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select 'after rollback: so rows ' || (select count(*) from public.so) || ' (head ' || :so_head || ') · fake staff ' || (select count(*) from public.ims_staff where email like 'ord1a2-%') || ' · fake store ' || (select count(*) from public.shop_store where code = 'ord1a2_aone') || ' · deal ' || (select count(*) from public.so_deal where name = 'ORD1A2 case 20') || ' · shop_order rows ' || coalesce((select count(*)::text from public.shop_order), 'n/a');
select setval('public.so_number_seq', greatest(:so_seq_head::bigint, coalesce((select max(substring(so_number from '^SO-([0-9]+)')::bigint) from public.so), 0)), :'so_seq_called'::boolean);
select 'seq tail so ' || last_value || ' ' || is_called from public.so_number_seq;
