-- ord-1b2-verify.sql — Shopify ④ 오더 받기 · 작은 보탬: shop_order_ingest 재발행(자동 취소 뒤 경고 정리) · resolve → received → process (Asung-IMS · 테스트)
--   기대: 시험 갈래(-v mig) OK 6 · 확인 갈래 OK 5(= 6 − 시험 전용 1: G0a) · MISMATCH 0 · 확인 갈래 전용 줄(\else)은 없다
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261011020000_ord_1b2_ingest_warnings.sql -f supabase/tests/ord-1b2-verify.sql > /tmp/ord-1b2.out 2>&1; echo exit=$?
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료: 오더 원문은 pg_temp.ord()(ord-1a2-verify 와 같은 것) · 실제 손님 Debi Blair(72cf6eba · 이메일 하나)는 읽기만 · 겹치는 이메일은 실제 손님 여럿이 가진 것을 읽기만(T2 · 고른 손님의 SO 는 rollback) · 가짜 직원 · 만들어지는 SO · shop_order 는 전부 rollback
--   ⚠️ so_number_seq 는 rollback 되지 않는다 — 머리를 읽고 끝에서 greatest(실제 최대, 머리)로 되돌린다 · 실제 행 변경 0 · 받은 일 표(shop_order_inbox)는 건드리지 않는다(EF 가 쓰는 줄 · 되감기 안에서 쓸 일 없음)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value::text as so_seq_head, is_called::text as so_seq_called from public.so_number_seq \gset
\echo '== head so seq' :so_seq_head :so_seq_called
begin;
select string_agg(proname || ':' || md5(prosrc), ',' order by proname) as h0_untouched from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_order_prepare', 'shop_order_process', 'shop_order_cancelled', 'shop_order_resolve_customer', 'shop_order_resolve_lines', 'shop_order_inbox_add', 'shop_order_pick_location', 'shop_system_enter', 'shop_system_leave', 'so_create', 'so_cancel', 'so_confirm', 'so_header_update', 'customer_create') \gset
select md5(prosrc) as h0_ingest from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest' \gset
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
\if :{?mig}
select pg_temp.chk('G0a (trial) fourteen untouched functions byte-identical · shop_order_ingest changed · marker ord-1b2 present',
  (:'h0_untouched' = (select string_agg(proname || ':' || md5(prosrc), ',' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_order_prepare', 'shop_order_process', 'shop_order_cancelled', 'shop_order_resolve_customer', 'shop_order_resolve_lines', 'shop_order_inbox_add', 'shop_order_pick_location', 'shop_system_enter', 'shop_system_leave', 'so_create', 'so_cancel', 'so_confirm', 'so_header_update', 'customer_create')))::text || '/' ||
  (select (md5(prosrc) <> :'h0_ingest')::text || '/' || (prosrc like '%ord-1b2%')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest'), 'true/true/true');
\endif

-- ═══ 재료 ═══
select id::text as store from public.shop_store where code = 'test' \gset
select s.id::text as sys_id from public.ims_staff s where s.is_system \gset
select count(*)::text as so_head from public.so \gset
select to_char(public.so_tax_amount(7.89, 5), 'FM999999990.00') as tax_ab_789 from (select 1) z \gset
select e as multi_email, n::text as multi_n from (select lower(trim(cc.email)) e, count(distinct cc.customer_id) n from public.customer_contact cc join public.customer c on c.id = cc.customer_id and c.is_active where cc.is_active and nullif(trim(cc.email), '') is not null group by 1 having count(distinct cc.customer_id) > 1 order by 2 desc, 1 limit 1) z \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'ord1b2-sales@test.invalid', 'ORD1B2 Sales', 'manager', '["sales"]'::jsonb) returning auth_user_id::text as s_uid, id::text as s_sid \gset
\set s_claims '{"sub":"' :s_uid '","role":"authenticated"}'
select coalesce(current_setting('request.jwt.claims', true), '') as claims0 \gset

-- ═══ T1 — 재발행 실물 · 옛 문구 없음 · 권한 ═══
select pg_temp.chk('T1a shop_order_ingest: marker ord-1b2 · new text · old text gone · definer · service_role only (authenticated · anon cannot execute) · returns cancel key',
  (select (prosrc like '%ord-1b2%')::text || '/' || (prosrc like '%was not cancelled automatically%')::text || '/' || (prosrc like '%until shop_order_cancelled runs%')::text || '/' || prosecdef::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest') || '/' ||
  has_function_privilege('authenticated', 'public.shop_order_ingest(uuid, jsonb)', 'execute')::text || '/' || has_function_privilege('anon', 'public.shop_order_ingest(uuid, jsonb)', 'execute')::text || '/' ||
  (public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/910000000001', 'B2-T0001', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB', '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_789')) ? 'cancel')::text,
  'true/true/false/true/false/false/true');

-- ═══ T2 — 이메일 여럿 → needs_review → resolve_customer(직원) → received → (EF 없이) process → created ═══
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/910000000002', 'B2-T0002', :'multi_email', null, 'AB',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_789'))::text as t2_in \gset
select (:'t2_in'::jsonb->>'shop_order_id') as o2 \gset
select (:'t2_in'::jsonb->'reasons'->0->'candidates'->0->>'customer_id') as c2 \gset
select count(*)::text as recv_before from public.shop_order where status = 'received' \gset
set local role authenticated;
select set_config('request.jwt.claims', :'s_claims', true);
select public.shop_order_resolve_customer(:'o2'::uuid, :'c2'::uuid, false)::text as t2_pre \gset
select public.shop_order_resolve_customer(:'o2'::uuid, :'c2'::uuid, true)::text as t2_go \gset
reset role;
select set_config('request.jwt.claims', '', true);
select count(*)::text as recv_mid from public.shop_order where status = 'received' and id = :'o2'::uuid \gset
select public.shop_order_process(:'o2'::uuid)::text as t2_proc \gset
select pg_temp.chk('T2a guest order with an email shared by several IMS customers → needs_review email_multiple · resolve_customer preview (not committed) → commit → prepare received · shop_order received (what EF orders_drain sweeps) · process → created · so_id · back to not received · claims restored',
  (:'t2_in'::jsonb->>'status') || '/' || (:'t2_in'::jsonb->'reasons'->0->>'code') || '/' || ((:'t2_in'::jsonb->'reasons'->0->>'count')::int = :multi_n::int)::text || '/' || (:'t2_pre'::jsonb->>'committed') || '/' || (:'t2_go'::jsonb->>'committed') || '/' || (:'t2_go'::jsonb->'prepare'->>'status') || '/' || :recv_mid || '/' ||
  (:'t2_proc'::jsonb->>'status') || '/' || (select status || '/' || (so_id is not null)::text || '/' || (customer_id = :'c2'::uuid)::text from public.shop_order where id = :'o2'::uuid) || '/' || (coalesce(current_setting('request.jwt.claims', true), '') = :'claims0')::text,
  'needs_review/email_multiple/true/false/true/received/1/created/created/true/true/true');

-- ═══ T3 — 손 안 댄 SO + Shopify 취소 → 자동 취소 · 경고는 auto_cancelled 만 더해진다(앞의 경고는 그대로) ═══
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/910000000003', 'B2-T0003', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_789', 'PENDING', '{"orig":"11.69","disc":"11.69","title":"Expedited Parcel"}'::jsonb))->>'shop_order_id' as o3 \gset
select public.shop_order_process(:'o3'::uuid)->>'status' as t3_proc \gset
select pg_temp.warns(:'o3'::uuid) as t3_w0 \gset
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/910000000003', 'B2-T0003', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_789', 'PENDING', '{"orig":"11.69","disc":"11.69","title":"Expedited Parcel"}'::jsonb,
  '{"updatedAt":"2026-10-10T21:00:00Z","cancelledAt":"2026-10-10T21:00:00Z"}'::jsonb))::text as t3_a \gset
select pg_temp.chk('T3a untouched SO + Shopify cancel (updatedAt moved too) → action updated_after_created · cancel auto_cancelled · shop_order cancelled · SO cancelled · warnings = before + auto_cancelled only (no updated_after_so · no cancelled_in_shopify) · second cancel ingest adds nothing',
  :'t3_proc' || '/' || (:'t3_a'::jsonb->>'action') || '/' || (:'t3_a'::jsonb->'cancel'->>'action') || '/' || (select status || '/' || (select s.status from public.so s where s.id = o.so_id) from public.shop_order o where o.id = :'o3'::uuid) || '/' ||
  :'t3_w0' || '→' || pg_temp.warns(:'o3'::uuid) || '/' ||
  (public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/910000000003', 'B2-T0003', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
     '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_789', 'PENDING', '{"orig":"11.69","disc":"11.69","title":"Expedited Parcel"}'::jsonb,
     '{"updatedAt":"2026-10-10T21:00:00Z","cancelledAt":"2026-10-10T21:00:00Z"}'::jsonb))->>'action') || '/' || pg_temp.warns(:'o3'::uuid),
  'created/updated_after_created/auto_cancelled/cancelled/cancelled/freight_not_applied→auto_cancelled,freight_not_applied/updated_after_cancelled/auto_cancelled,freight_not_applied');

-- ═══ T4 — 직원이 손댄 SO + Shopify 취소 → needs_review: 「손으로 확인」 셋이 남는다(새 문구) · SO 는 배송지 주 없음 → confirm_blocked 로 draft(1a2 T6b 와 같은 결 · 직원이 so_header_update 로 손댈 수 있게) ═══
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/910000000004', 'B2-T0004', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', null,
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, '0.00', 'PENDING', null,
  '{"shippingAddress":{"name":"Debi Blair","address1":"1 Far St","city":"Nowhere","provinceCode":null,"zip":"00000","countryCodeV2":"CA"}}'::jsonb))->>'shop_order_id' as o4 \gset
select public.shop_order_process(:'o4'::uuid)->>'status' as t4_proc \gset
select so_id::text as so4 from public.shop_order where id = :'o4'::uuid \gset
update public.shop_order set so_baseline_at = now() - interval '1 minute' where id = :'o4'::uuid;
set local role authenticated;
select set_config('request.jwt.claims', :'s_claims', true);
select public.so_header_update(:'so4'::uuid, '{"comments": "staff touched this"}'::jsonb)->>'so_number' as t4_touch \gset
reset role;
select set_config('request.jwt.claims', '', true);
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/910000000004', 'B2-T0004', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', null,
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, '0.00', 'PENDING', null,
  '{"shippingAddress":{"name":"Debi Blair","address1":"1 Far St","city":"Nowhere","provinceCode":null,"zip":"00000","countryCodeV2":"CA"},"updatedAt":"2026-10-10T21:10:00Z","cancelledAt":"2026-10-10T21:10:00Z"}'::jsonb))::text as t4_a \gset
select pg_temp.chk('T4a staff touched the draft SO (comments) → Shopify cancel → cancel needs_review changed_in_ims · shop_order stays created · SO stays draft · warnings keep confirm_blocked + updated_after_so + cancelled_in_shopify (new text · old text gone) + cancel_needs_review',
  :'t4_proc' || '/' || (:'t4_a'::jsonb->'cancel'->>'action') || '/' || (:'t4_a'::jsonb->'cancel'->>'reason') || '/' || (select status || '/' || (select s.status from public.so s where s.id = o.so_id) from public.shop_order o where o.id = :'o4'::uuid) || '/' || pg_temp.warns(:'o4'::uuid) || '/' ||
  (select (r->>'message' like '%was not cancelled automatically%check it by hand%')::text || '/' || (r->>'message' like '%ord-1a2%')::text from public.shop_order o, jsonb_array_elements(o.warnings) r where o.id = :'o4'::uuid and r->>'code' = 'cancelled_in_shopify'),
  'created/needs_review/changed_in_ims/created/draft/cancel_needs_review,cancelled_in_shopify,confirm_blocked,updated_after_so/true/false');

-- ═══ T5 — status error(SO 없음) 오더의 Shopify 취소 → closed_before_so · 경고 없음 ═══
select id::text as c_off from public.customer where not is_active limit 1 \gset
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/910000000005', 'B2-T0005', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_789'))->>'shop_order_id' as o5 \gset
update public.shop_order set customer_id = :'c_off'::uuid where id = :'o5'::uuid;
select public.shop_order_process(:'o5'::uuid)->>'status' as t5_proc \gset
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/910000000005', 'B2-T0005', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, :'tax_ab_789', 'PENDING', null, '{"updatedAt":"2026-10-10T21:20:00Z","cancelledAt":"2026-10-10T21:20:00Z"}'::jsonb))::text as t5_a \gset
select pg_temp.chk('T5a failing process → error (no SO) · Shopify cancel → action updated_after_error · cancel closed_before_so · shop_order cancelled · no so_id · warnings empty (no updated_after_error · no cancelled_in_shopify) · so rows: SOs of T2 T3 T4 only',
  :'t5_proc' || '/' || (:'t5_a'::jsonb->>'action') || '/' || (:'t5_a'::jsonb->'cancel'->>'action') || '/' || (select status || '/' || (so_id is null)::text || '/' || coalesce(pg_temp.warns(id), '') from public.shop_order where id = :'o5'::uuid) || '/' ||
  (select count(*)::text from public.so s join public.shop_order o on o.so_id = s.id where o.name like 'B2-T%'),
  'error/updated_after_error/closed_before_so/cancelled/true//3');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select 'after rollback: so rows ' || (select count(*) from public.so) || ' (head ' || :so_head || ') · fake staff ' || (select count(*) from public.ims_staff where email like 'ord1b2-%') || ' · shop_order B2 rows ' || (select count(*) from public.shop_order where name like 'B2-T%') || ' · inbox open ' || (select count(*) from public.shop_order_inbox where done_at is null);
select setval('public.so_number_seq', greatest(:so_seq_head::bigint, coalesce((select max(substring(so_number from '^SO-([0-9]+)')::bigint) from public.so), 0)), :'so_seq_called'::boolean);
select 'seq tail so ' || last_value || ' ' || is_called from public.so_number_seq;
