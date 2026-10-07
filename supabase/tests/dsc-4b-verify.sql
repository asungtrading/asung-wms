-- dsc-4b-verify.sql — 태그 op · rules_open_to_all · so_deal_products · so_deal_customers · so_deal_list · so_deal_detail (Asung-IMS · 2026-10-06)
--   기대: 시험 갈래 OK 41 · 확인 갈래(G0 둘 없음) OK 39 · MISMATCH 0(시험 적용 3회차 통과 · 2026-10-06) · 실제 행(TEST POS SALE 15) md5 전후 같음 · 시퀀스 무변
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261007003838_dsc_4b_tags_deal_read.sql -f supabase/tests/dsc-4b-verify.sql 2>&1 | tee /tmp/dsc-4b.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다(G0 는 시험 갈래에서만 돈다)
--   재료는 가짜만(DSC4B-* · 2031년) · 실제 행은 읽기만(브랜드 · 카테고리 · 손님 집합은 실제를 읽어 센다 · 바꾸지 않는다) · 끝은 rollback
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
\echo '== seq head so' :so_seq_last :so_seq_called 'inv' :inv_seq_last :inv_seq_called 'cr' :cr_seq_last :cr_seq_called
select md5(string_agg(x, '|' order by x)) as real_md5_head from (
  select d::text as x from public.so_deal d where d.id = '7a6b411a-b2e4-4a7f-8735-d74f24b0c8c3'
  union all select l::text from public.so_deal_line l where l.id = '28447237-8d1e-40e4-8b26-777600b50090'
  union all select t::text from public.so_deal_target t where t.id = 'fa1d5e67-2068-40ba-9f23-cf567455a115') s \gset
\echo '== real rows md5 head' :real_md5_head

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
\if :{?mig}
\echo '── G0 재발행 원본 대조(적용 전 DB prosrc md5 = 파일 본문 md5)'
select pg_temp.chk('G0a product_update last def = 20261006183851:491~1357', (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'product_update'), '505028553e983e4f75bce5d0583391dd');
select pg_temp.chk('G0b so_deal_save last def = 20261007001229:162~783', (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_save'), 'd795f0666c56393bd7cb43279199f48e');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create function pg_temp.real_md5() returns text language sql as $$
  select md5(string_agg(x, '|' order by x)) from (
    select row(d.id, d.name, d.is_active, d.source, d.note, d.date_from, d.date_to, d.is_order_level, d.coupon_code, d.kind, d.coupon_required, d.updated_at, d.updated_by, d.created_at)::text as x from public.so_deal d where d.id = '7a6b411a-b2e4-4a7f-8735-d74f24b0c8c3'
    union all select row(l.id, l.deal_id, l.line_no, l.pct, l.min_qty_mode, l.min_qty, l.source, l.note, l.updated_at, l.is_active)::text from public.so_deal_line l where l.id = '28447237-8d1e-40e4-8b26-777600b50090'
    union all select row(t.id, t.line_id, t.kind, t.target, t.tag, t.brand_id, t.product_id, t.category_id, t.source, t.updated_at)::text from public.so_deal_target t where t.id = 'fa1d5e67-2068-40ba-9f23-cf567455a115') s
$$;
select pg_temp.real_md5() as real_in_before \gset

-- ═══ 재료 — 직원 셋 · 손님 · 제품 셋(낱개 A · 세트 A-12 · B) · 실제 브랜드 · 카테고리 하나씩(읽기만) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'dsc4b-master@test.invalid', 'DSC4B Master', 'manager', '["master","sales"]'::jsonb) returning auth_user_id::text as m_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'dsc4b-sales@test.invalid',  'DSC4B Sales',  'manager', '["sales"]'::jsonb)          returning auth_user_id::text as s_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'dsc4b-worker@test.invalid', 'DSC4B Worker', 'worker',  '["picking"]'::jsonb)        returning auth_user_id::text as w_uid \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
\set s_claims '{"sub":"' :s_uid '","role":"authenticated"}'
\set w_claims '{"sub":"' :w_uid '","role":"authenticated"}'
select id::text as wh1 from public.ref_warehouse order by name limit 1 \gset
select id::text as wh2 from public.ref_warehouse order by name desc limit 1 \gset
select id::text as tier, name as tier_name from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
select id::text as tier2 from public.ref_price_tier where purpose = 'sale' and is_active order by code desc limit 1 \gset
select brand_id::text as brand from public.product where is_active and brand_id is not null group by brand_id having count(*) between 60 and 400 and bool_or(parent_product_id is not null) order by count(*) desc limit 1 \gset
select category_id::text as cat from public.product where is_active and category_id is not null group by category_id having count(*) between 60 and 400 order by count(*) desc limit 1 \gset
select id::text as xprod from public.product p where p.brand_id = :'brand'::uuid and p.parent_product_id is null and exists (select 1 from public.product s where s.parent_product_id = p.id) order by p.sku limit 1 \gset
select id::text as xcust from public.customer where is_active and price_tier = :'tier_name' order by name limit 1 \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('DSC4B Customer', 'manual', :'tier_name', :'wh1'::uuid, 0) returning id::text as cust \gset
insert into public.product (sku, name, source, brand_id) values ('DSC4B-A', 'DSC4B Product A', 'manual', null) returning id::text as pa \gset
insert into public.product (sku, name, source, parent_product_id, pack_factor) values ('DSC4B-A-12', 'DSC4B Product A x12', 'manual', :'pa'::uuid, 12) returning id::text as pas \gset
insert into public.product (sku, name, source) values ('DSC4B-B', 'DSC4B Product B', 'manual') returning id::text as pb \gset
\echo '== material: brand' :brand 'cat' :cat 'xprod' :xprod 'tier' :tier_name

-- ═══ D1 가짜 줄 딜(2031 · 손님 조건 fake) — L1 브랜드 걸기 + 실제 제품 X 빼기 · L2 태그 DSC4B-Tag(아직 제품 없음 → tag_unused ack) · L3 카테고리 + 제품 B · L4 는 뒤에 끈다 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4B Line Deal', 'date_from', '2031-01-01', 'date_to', '2031-01-31',
  'lines', jsonb_build_array(
     jsonb_build_object('line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'brand', 'brand_id', :'brand'), jsonb_build_object('kind', 'exclude', 'target', 'product', 'product_id', :'xprod'))),
     jsonb_build_object('line_no', 2, 'pct', 20, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4B-Tag'))),
     jsonb_build_object('line_no', 3, 'pct', 5,  'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'category', 'category_id', :'cat'), jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pb'))),
     jsonb_build_object('line_no', 4, 'pct', 7,  'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pa')))),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'), jsonb_build_object('kind', 'include', 'target', 'tier', 'tier_id', :'tier'))), null, true, array['deal:new:tag_unused']) as r \gset d1_
reset role;
select pg_temp.chk('D1 fake line deal created (tag_unused acked)', :'d1_r'::jsonb->>'committed', 'true');
select (:'d1_r'::jsonb->>'deal_id') as d1, (:'d1_r'::jsonb->>'updated_at') as u1 \gset
select l.id::text as l1 from public.so_deal_line l where l.deal_id = :'d1'::uuid and l.line_no = 1 \gset
select l.id::text as l2 from public.so_deal_line l where l.deal_id = :'d1'::uuid and l.line_no = 2 \gset
select l.id::text as l3 from public.so_deal_line l where l.deal_id = :'d1'::uuid and l.line_no = 3 \gset
select l.id::text as l4 from public.so_deal_line l where l.deal_id = :'d1'::uuid and l.line_no = 4 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10), jsonb_build_object('id', :'l2', 'line_no', 2, 'pct', 20), jsonb_build_object('id', :'l3', 'line_no', 3, 'pct', 5))), to_jsonb(:'u1'::text), true) as r \gset d1b_
reset role;
select pg_temp.chk('D1b line 4 turned off (product A direct) — no fake orders so no flag ack needed', (:'d1b_r'::jsonb->>'committed') || '/' || (select l.is_active::text from public.so_deal_line l where l.id = :'l4'::uuid), 'true/false');
select (:'d1b_r'::jsonb->>'updated_at') as u1 \gset

-- ═══ T1 · T2 태그 붙이기 · 떼기 — product_update op · 딜이 태그로 걸리기 시작함 ═══
select pg_temp.chk('T2a before tag: line 2 (tag) matches nothing', (select count(*)::text from public.so_deal_products(:'d1'::uuid) p where p.line_id = :'l2'::uuid), '0');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4B-A', 'op', 'tag_add', 'tag', ' DSC4B-Tag ')), false) as r \gset t1p_
reset role;
select pg_temp.chk('T1a preview tag_add: not committed · no row · change applied false', (:'t1p_r'::jsonb->>'committed') || '/' || (select count(*) from public.product_tag pt where pt.product_id = :'pa'::uuid) || '/' || (:'t1p_r'::jsonb->'changes'->0->>'applied'), 'false/0/false');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4B-A', 'op', 'tag_add', 'tag', ' DSC4B-Tag ')), true) as r \gset t1c_
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4B-A', 'op', 'tag_add', 'tag', 'DSC4B-Tag')), true) as r \gset t1d_
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4B-B', 'op', 'tag_off', 'tag', 'DSC4B-Tag')), true) as r \gset t1e_
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4B-B', 'op', 'tag_add', 'tag', 'dsc4b-tag')), true) as r \gset t1f_
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4B-B', 'op', 'tag_add', 'tag', 'DSC4B-X'), jsonb_build_object('sku', 'DSC4B-A', 'op', 'tag_add', 'tag', 'dsc4b-x')), true) as r \gset t1g_
reset role;
select pg_temp.chk('T1b commit tag_add: row with btrim tag · source manual · updated_by set', (:'t1c_r'::jsonb->>'committed') || '/' || (select pt.tag || '/' || pt.source || '/' || (pt.updated_by is not null)::text from public.product_tag pt where pt.product_id = :'pa'::uuid), 'true/DSC4B-Tag/manual/true');
select pg_temp.chk('T1c add again → tag_exists', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'t1d_r'::jsonb->'blocks') x), 'tag_exists');
select pg_temp.chk('T1d off a tag the product lacks → tag_not_found', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'t1e_r'::jsonb->'blocks') x), 'tag_not_found');
select pg_temp.chk('T1e case clash with another product tag → tag_case_conflict', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'t1f_r'::jsonb->'blocks') x), 'tag_case_conflict');
select pg_temp.chk('T1f case clash inside the call → tag_case_conflict · nothing saved', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'t1g_r'::jsonb->'blocks') x) || '/' || (select count(*) from public.product_tag pt where pt.tag in ('DSC4B-X', 'dsc4b-x')), 'tag_case_conflict/0');
select pg_temp.chk('T2b after tag: line 2 matches A and its set A-12 (via base)', (select string_agg(pr.sku || ':' || array_to_string(p.matched_by, '+'), ',' order by pr.sku) from public.so_deal_products(:'d1'::uuid) p join public.product pr on pr.id = p.product_id where p.line_id = :'l2'::uuid), 'DSC4B-A:tag,DSC4B-A-12:tag:base');
-- 딜 대상 태그와의 대소문자 충돌 · 켜진 딜이 쓰는 마지막 태그 떼기
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4B Tag Deal', 'date_from', '2031-02-01', 'date_to', '2031-02-28', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 5, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4B-DealTag'))))), null, true, array['deal:new:tag_unused']) as r \gset d3_
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4B-B', 'op', 'tag_add', 'tag', 'dsc4b-dealtag')), true) as r \gset t1h_
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4B-A', 'op', 'tag_off', 'tag', 'DSC4B-Tag')), true) as r \gset t1i_
reset role;
select pg_temp.chk('T1g case clash with a deal target tag → tag_case_conflict', (:'d3_r'::jsonb->>'committed') || '/' || (select string_agg(x->>'code', ',') from jsonb_array_elements(:'t1h_r'::jsonb->'blocks') x), 'true/tag_case_conflict');
select pg_temp.chk('T1h off the last product of a tag an active deal targets → tag_off_used_by_deal{deals} · unacked · tag kept', (:'t1i_r'::jsonb->>'committed') || '/' || (select x->>'deals' from jsonb_array_elements(:'t1i_r'::jsonb->'warnings') x where x->>'code' = 'tag_off_used_by_deal') || '/' || (select string_agg(u, ',') from jsonb_array_elements_text(:'t1i_r'::jsonb->'unacked') u) || '/' || (select count(*) from public.product_tag pt where pt.product_id = :'pa'::uuid), 'false/DSC4B Line Deal/DSC4B-A:tag_off_used_by_deal:DSC4B-Tag/1');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4B-A', 'op', 'tag_off', 'tag', 'DSC4B-Tag')), true, array['DSC4B-A:tag_off_used_by_deal:DSC4B-Tag']) as r \gset t1j_
reset role;
select pg_temp.chk('T1i acked → row deleted', (:'t1j_r'::jsonb->>'committed') || '/' || (select count(*) from public.product_tag pt where pt.product_id = :'pa'::uuid), 'true/0');
select pg_temp.chk('T2c after tag off: line 2 matches nothing again', (select count(*)::text from public.so_deal_products(:'d1'::uuid) p where p.line_id = :'l2'::uuid), '0');
-- 뒤 절을 위해 태그를 다시 붙인다(A 만 · 세트는 낱개를 거쳐)
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4B-A', 'op', 'tag_add', 'tag', 'DSC4B-Tag')), true) as r \gset t1k_
reset role;

-- ═══ T3 rules_open_to_all(343) — 걸기 2 → 0 · 빼기만 남아도 · 2 → 1 은 안 묻는다 · 만들기는 안 묻는다 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'rules', '[]'::jsonb), to_jsonb(:'u1'::text), true) as r \gset t3a_
reset role;
select pg_temp.chk('T3a include 2 → 0: warning rules_open_to_all n_before 2 · unacked · rules kept', (:'t3a_r'::jsonb->>'committed') || '/' || (select x->>'n_before' from jsonb_array_elements(:'t3a_r'::jsonb->'warnings') x where x->>'code' = 'rules_open_to_all') || '/' || (select string_agg(u, ',') from jsonb_array_elements_text(:'t3a_r'::jsonb->'unacked') u) || '/' || (select count(*) from public.so_deal_customer_rule r where r.deal_id = :'d1'::uuid), 'false/2/deal:' || :'d1' || ':rules_open_to_all/2');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'rules', '[]'::jsonb), to_jsonb(:'u1'::text), true, array['deal:' || :'d1' || ':rules_open_to_all']) as r \gset t3b_
reset role;
select pg_temp.chk('T3b acked → rules 0', (:'t3b_r'::jsonb->>'committed') || '/' || (select count(*) from public.so_deal_customer_rule r where r.deal_id = :'d1'::uuid), 'true/0');
select (:'t3b_r'::jsonb->>'updated_at') as u1 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'), jsonb_build_object('kind', 'exclude', 'target', 'branch', 'warehouse_id', :'wh2'))), to_jsonb(:'u1'::text), true) as r \gset t3c_
reset role;
select pg_temp.chk('T3c include 0 → 1 (+exclude): no question', (:'t3c_r'::jsonb->>'committed') || '/' || (select count(*) from jsonb_array_elements(:'t3c_r'::jsonb->'warnings') x where x->>'code' = 'rules_open_to_all'), 'true/0');
select (:'t3c_r'::jsonb->>'updated_at') as u1 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'rules', jsonb_build_array(jsonb_build_object('kind', 'exclude', 'target', 'branch', 'warehouse_id', :'wh2'))), to_jsonb(:'u1'::text), true) as r \gset t3d_
reset role;
select pg_temp.chk('T3d only an exclude left (include 1 → 0) → asks', (:'t3d_r'::jsonb->>'committed') || '/' || (select x->>'n_before' from jsonb_array_elements(:'t3d_r'::jsonb->'warnings') x where x->>'code' = 'rules_open_to_all'), 'false/1');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'), jsonb_build_object('kind', 'include', 'target', 'tier', 'tier_id', :'tier'))), to_jsonb(:'u1'::text), true) as r \gset t3e_
reset role;
select (:'t3e_r'::jsonb->>'updated_at') as u1 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), to_jsonb(:'u1'::text), true) as r \gset t3f_
select public.so_deal_save(jsonb_build_object('name', 'DSC4B Open Deal', 'date_from', '2031-03-01', 'date_to', '2031-03-31', 'is_order_level', true, 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 2))), null, true) as r \gset t3g_
reset role;
select pg_temp.chk('T3e include 2 → 1: no question', (:'t3e_r'::jsonb->>'committed') || '/' || (:'t3f_r'::jsonb->>'committed') || '/' || (select count(*) from jsonb_array_elements(:'t3f_r'::jsonb->'warnings') x where x->>'code' = 'rules_open_to_all'), 'true/true/0');
select pg_temp.chk('T3f create without rules: no question', (:'t3g_r'::jsonb->>'committed') || '/' || (select count(*) from jsonb_array_elements(:'t3g_r'::jsonb->'warnings') x where x->>'code' = 'rules_open_to_all'), 'true/0');
select (:'t3f_r'::jsonb->>'updated_at') as u1 \gset
select (:'t3g_r'::jsonb->>'deal_id') as d4 \gset

-- ═══ T4 제품 집합 같음 — 후보 집합(브랜드 · 카테고리 · 태그 · 제품 대상의 제품 + 세트 · 낱개 짝 + 빼기 경계 + 무작위 300)에서 so_deal_products = candidates 걸림 ═══
create temp table t_u (product_id uuid primary key);
insert into t_u select p.id from public.product p where p.brand_id = :'brand'::uuid or p.category_id = :'cat'::uuid on conflict do nothing;
insert into t_u select s.id from public.product s join t_u u on s.parent_product_id = u.product_id on conflict do nothing;
insert into t_u select b.id from public.product p join t_u u on p.id = u.product_id join public.product b on b.id = p.parent_product_id on conflict do nothing;
insert into t_u select pt.product_id from public.product_tag pt where pt.tag = 'DSC4B-Tag' on conflict do nothing;
insert into t_u values (:'pa'::uuid), (:'pas'::uuid), (:'pb'::uuid), (:'xprod'::uuid) on conflict do nothing;
insert into t_u select s.id from public.product s where s.parent_product_id = :'xprod'::uuid on conflict do nothing;
insert into t_u select p.id from public.product p where p.is_active and p.id not in (select product_id from t_u) order by random() limit 300 on conflict do nothing;
select count(*) as u_n from t_u \gset
select clock_timestamp() as t4_0 \gset
create temp table t_a as select p.product_id, p.line_id from public.so_deal_products(:'d1'::uuid) p where p.product_id in (select u.product_id from t_u u);
select clock_timestamp() as t4_1 \gset
create temp table t_b as
  select u.product_id, l.id as line_id
    from t_u u cross join public.so_deal_line l
   where l.deal_id = :'d1'::uuid
     and exists (select 1 from public.so_deal_candidates(u.product_id, :'cust'::uuid, :'tier'::uuid, 1, '2031-01-15') c where c.deal_id = :'d1'::uuid and c.line_id = l.id and c.reason not in ('excluded_product', 'line_inactive'));
select clock_timestamp() as t4_2 \gset
\echo '== T4 universe' :u_n 'products · so_deal_products ms' 
select round(extract(epoch from (:'t4_1'::timestamptz - :'t4_0'::timestamptz)) * 1000) as products_ms, round(extract(epoch from (:'t4_2'::timestamptz - :'t4_1'::timestamptz)) * 1000) as candidates_ms;
select pg_temp.chk('T4a so_deal_products − candidates = 0', (select count(*)::text from (select * from t_a except select * from t_b) q), '0');
select pg_temp.chk('T4b candidates − so_deal_products = 0', (select count(*)::text from (select * from t_b except select * from t_a) q), '0');
select pg_temp.chk('T4c set has brand products > 0 · excluded X and its sets absent on line 1 · off line 4 absent · line 3 has product B', ((select count(*) from t_a where line_id = :'l1'::uuid) > 0)::text || '/' || (select count(*) from t_a where line_id = :'l1'::uuid and product_id in (select id from public.product where id = :'xprod'::uuid or parent_product_id = :'xprod'::uuid)) || '/' || (select count(*) from t_a where line_id = :'l4'::uuid) || '/' || (select count(*) from t_a where line_id = :'l3'::uuid and product_id = :'pb'::uuid), 'true/0/0/1');
select pg_temp.chk('T4d a real set of the brand is matched via its base (brand:base) on line 1', ((select count(*) from public.so_deal_products(:'d1'::uuid) p where p.line_id = :'l1'::uuid and 'brand:base' = any(p.matched_by)) > 0)::text, 'true');

-- ═══ T5 손님 수 — 잰다(손님마다 so_deal_customer_ok) · 집합 식과 같음 · 조건 없는 딜 = 활성 손님 전부 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4B Cust Deal', 'date_from', '2031-04-01', 'date_to', '2031-04-30', 'is_order_level', true, 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 3)),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tier', 'tier_id', :'tier'), jsonb_build_object('kind', 'include', 'target', 'tier', 'tier_id', :'tier2'), jsonb_build_object('kind', 'exclude', 'target', 'branch', 'warehouse_id', :'wh2'), jsonb_build_object('kind', 'exclude', 'target', 'customer', 'customer_id', :'xcust'))), null, true) as r \gset d2_
reset role;
select (:'d2_r'::jsonb->>'deal_id') as d2 \gset
select clock_timestamp() as t5_0 \gset
create temp table t_ok as select c.id from public.customer c where c.is_active and public.so_deal_customer_ok(:'d2'::uuid, c.id, (select rt.id from public.ref_price_tier rt where rt.name = c.price_tier and rt.purpose = 'sale' and rt.is_active limit 1));
select clock_timestamp() as t5_1 \gset
create temp table t_set as select c.customer_id as id from public.so_deal_customers(:'d2'::uuid) c;
select clock_timestamp() as t5_2 \gset
select 'T5 timing: per-customer so_deal_customer_ok ms=' || round(extract(epoch from (:'t5_1'::timestamptz - :'t5_0'::timestamptz)) * 1000) || ' · set so_deal_customers ms=' || round(extract(epoch from (:'t5_2'::timestamptz - :'t5_1'::timestamptz)) * 1000) || ' · customers=' || (select count(*) from t_ok);
select pg_temp.chk('T5a set − per-customer = 0', (select count(*)::text from (select id from t_set except select id from t_ok) q), '0');
select pg_temp.chk('T5b per-customer − set = 0 · n > 0 · excluded X absent · fake customer (tier T · wh1) present', (select count(*)::text from (select id from t_ok except select id from t_set) q) || '/' || ((select count(*) from t_ok) > 0)::text || '/' || (select count(*) from t_set where id = :'xcust'::uuid) || '/' || (select count(*) from t_set where id = :'cust'::uuid), '0/true/0/1');
select pg_temp.chk('T5c deal without rules = all active customers', (select count(*)::text from public.so_deal_customers(:'d4'::uuid)) , (select count(*)::text from public.customer where is_active));

-- ═══ T6 so_deal_list · so_deal_detail — 수가 T4 · T5 와 같다 · 덩이 왕복 no_change · 꺼진 줄 포함 · 이름표 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'s_claims', true);
select clock_timestamp() as t6_0 \gset
select public.so_deal_list() as r \gset t6_
select clock_timestamp() as t6_1 \gset
select public.so_deal_detail(:'d1'::uuid, 5) as r \gset t6d_
reset role;
select 'T6 timing: so_deal_list ms=' || round(extract(epoch from (:'t6_1'::timestamptz - :'t6_0'::timestamptz)) * 1000) || ' · deals=' || (:'t6_r'::jsonb->>'count');
select x as d1row from jsonb_array_elements(:'t6_r'::jsonb->'deals') x where x->>'id' = :'d1' \gset
select x as d2row from jsonb_array_elements(:'t6_r'::jsonb->'deals') x where x->>'id' = :'d2' \gset
select x as d4row from jsonb_array_elements(:'t6_r'::jsonb->'deals') x where x->>'id' = :'d4' \gset
select pg_temp.chk('T6a list d1: lines_on 3 · lines_off 1 · tiers 0 · product_n_all = so_deal_products distinct · product_n = active ones', (:'d1row'::jsonb->>'lines_on') || '/' || (:'d1row'::jsonb->>'lines_off') || '/' || (:'d1row'::jsonb->>'tiers') || '/' || (:'d1row'::jsonb->>'product_n_all') || '/' || (:'d1row'::jsonb->>'product_n'),
  '3/1/0/' || (select count(distinct p.product_id) from public.so_deal_products(:'d1'::uuid) p) || '/' || (select count(distinct p.product_id) from public.so_deal_products(:'d1'::uuid) p join public.product pr on pr.id = p.product_id where pr.is_active));
select pg_temp.chk('T6b list d1 customer_n = 1 (include fake customer only) · all_customers false', (:'d1row'::jsonb->>'customer_n') || '/' || (:'d1row'::jsonb->>'all_customers'), '1/false');
select pg_temp.chk('T6c list d2 customer_n = T5 set · product_n null (order deal) · d4 all_customers · customer_n = active', (:'d2row'::jsonb->>'customer_n') || '/' || coalesce(:'d2row'::jsonb->>'product_n', 'null') || '/' || (:'d4row'::jsonb->>'all_customers') || '/' || (:'d4row'::jsonb->>'customer_n'), (select count(*)::text from t_set) || '/null/true/' || (select count(*)::text from public.customer where is_active));
select pg_temp.chk('T6d list: fake deals present 4 · updated_at of d1 = row', (select count(*)::text from jsonb_array_elements(:'t6_r'::jsonb->'deals') x where x->>'name' like 'DSC4B %') || '/' || (select ((:'d1row'::jsonb->>'updated_at')::timestamptz = d.updated_at)::text from public.so_deal d where d.id = :'d1'::uuid), '4/true');
select pg_temp.chk('T6e detail d1: deal.lines 4 (off line included with is_active false) · products.n_all = list · customers.n 1 · items ≤ 5 · labels brand name present', jsonb_array_length(:'t6d_r'::jsonb->'deal'->'lines') || '/' || (select count(*) from jsonb_array_elements(:'t6d_r'::jsonb->'deal'->'lines') x where (x->>'is_active') = 'false') || '/' || (:'t6d_r'::jsonb->'products'->>'n_all') || '/' || (:'t6d_r'::jsonb->'customers'->>'n') || '/' || jsonb_array_length(:'t6d_r'::jsonb->'products'->'items') || '/' || ((:'t6d_r'::jsonb->'labels'->'brands'->>(:'brand')) = (select b.name from public.ref_brand b where b.id = :'brand'::uuid))::text, '4/1/' || (:'d1row'::jsonb->>'product_n_all') || '/1/5/true');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(:'t6d_r'::jsonb->'deal', jsonb_build_object('updated_at', :'t6d_r'::jsonb->'updated_at'), true) as r \gset t6f_
reset role;
select pg_temp.chk('T6f detail deal bundle sent back as-is → no_change (343 round trip)', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'t6f_r'::jsonb->'blocks') x), 'no_change');
select pg_temp.chk('T6g detail of order deal d2: tiers 1 · lines 0 · products.n null · coupons 0', (select public.so_deal_detail(:'d2'::uuid) as r) is not null::text, 'true');

-- ═══ T7 권한 — anon 창구 · 속 함수 거절 · authenticated 속 함수 거절 · sales 만 → 목록 됨 · worker(sales 없음) → 거절 ═══
set local role anon;
do $$ begin perform public.so_deal_list(); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a1 \gset
do $$ begin perform public.so_deal_products(gen_random_uuid()); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a2 \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
do $$ begin perform public.so_deal_products(gen_random_uuid()); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a3 \gset
do $$ begin perform public.so_deal_customers(gen_random_uuid()); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a4 \gset
select set_config('request.jwt.claims', :'w_claims', true);
do $$ begin perform public.so_deal_list(); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as a5 \gset
reset role;
select pg_temp.chk('T7a anon list · anon products · auth products · auth customers → 42501 ×4', :'a1' || ',' || :'a2' || ',' || :'a3' || ',' || :'a4', '42501,42501,42501,42501');
select pg_temp.chk('T7b sales-only identity reads the list (T6 ran as sales) · worker without sales refused', ((:'t6_r'::jsonb->>'count')::int > 0)::text || '/' || (:'a5' like '%cannot view deals%')::text, 'true/true');
select pg_temp.chk('T7c grants: list · detail authenticated yes anon no · products · customers authenticated no', has_function_privilege('authenticated', 'public.so_deal_list()', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_deal_detail(uuid, int)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.so_deal_products(uuid)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.so_deal_customers(uuid)', 'execute')::text, 'true/false/false/false');
select pg_temp.chk('T7d candidates · customer_ok untouched (no dsc-4b mark) · product_update has tag ops · so_deal_save has rules_open_to_all', (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_deal_candidates', 'so_deal_customer_ok') and p.prosrc like '%dsc-4b%') || '/' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'product_update' and p.prosrc like '%tag_off_used_by_deal%') || '/' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_save' and p.prosrc like '%rules_open_to_all%'), '0/1/1');

-- ═══ 끝 — 실제 행 무변 · 집계 ═══
select pg_temp.chk('Z real rows (TEST POS SALE 15) unchanged inside', pg_temp.real_md5(), :'real_in_before');
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select md5(string_agg(x, '|' order by x)) as real_md5_tail from (
  select d::text as x from public.so_deal d where d.id = '7a6b411a-b2e4-4a7f-8735-d74f24b0c8c3'
  union all select l::text from public.so_deal_line l where l.id = '28447237-8d1e-40e4-8b26-777600b50090'
  union all select t::text from public.so_deal_target t where t.id = 'fa1d5e67-2068-40ba-9f23-cf567455a115') s \gset
\echo '== real rows md5 tail' :real_md5_tail '(head' :real_md5_head ')'
select 'REAL_ROWS_SAME ' || (:'real_md5_head' = :'real_md5_tail')::text;
select 'seq tail so ' || last_value || ' ' || is_called from public.so_number_seq;
select 'seq tail inv ' || last_value || ' ' || is_called from public.so_invoice_number_seq;
select 'seq tail cr ' || last_value || ' ' || is_called from public.so_credit_number_seq;
