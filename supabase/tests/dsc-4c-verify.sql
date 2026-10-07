-- dsc-4c-verify.sql — 제품 속성 변경 → 그 제품이 든 열린 오더에 reprice 표시(트리거 · 판정 344) (Asung-IMS · 2026-10-06)
--   기대: 시험 갈래 OK 24 · 확인 갈래(G0 없음) OK 23 · MISMATCH 0(시험 적용 4회차 통과 · 2026-10-06) · 실제 행(TEST POS SALE 15) md5 전후 같음 · 시퀀스 무변
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261007005851_dsc_4c_product_flag.sql -f supabase/tests/dsc-4c-verify.sql 2>&1 | tee /tmp/dsc-4c.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다(G0 는 시험 갈래에서만)
--   재료는 가짜만(DSC4C-* · SO-7991x · 2031년 · 가짜 브랜드 · 카테고리) · 실제 행은 읽기만 · 끝은 rollback
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
select 'dsc-4b applied on this DB: ' || (to_regprocedure('public.so_deal_products(uuid)') is not null)::text;

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
\if :{?mig}
select pg_temp.chk('G0 so_deal_flag_open_orders last def = 20261006201443:238~252', (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_flag_open_orders'), 'b70a24a06f0711a7dac7796c91fe3141');
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
create function pg_temp.flags() returns text language sql as $$
  select string_agg(s.so_number || ':' || (s.reprice_suggested_at is not null)::text, ',' order by s.so_number) from public.so s where s.so_number in ('SO-79911', 'SO-79912', 'SO-79913', 'SO-79914')
$$;

-- ═══ 재료 — 직원 · 손님 · 브랜드 셋 · 카테고리 둘 · 제품 X(낱개) · S(X 의 세트) · Y · 딜 둘 · 오더 넷 ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'dsc4c-master@test.invalid', 'DSC4C Master', 'manager', '["master","sales"]'::jsonb) returning auth_user_id::text as m_uid \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as wh1 from public.ref_warehouse order by name limit 1 \gset
select id::text as tier, name as tier_name from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' limit 1 \gset
insert into public.ref_brand (name) values ('DSC4C Brand A') returning id::text as ba \gset
insert into public.ref_brand (name) values ('DSC4C Brand B') returning id::text as bb \gset
insert into public.ref_brand (name) values ('DSC4C Brand C') returning id::text as bc \gset
insert into public.ref_category (name) values ('DSC4C Cat A') returning id::text as ca \gset
insert into public.ref_category (name) values ('DSC4C Cat B') returning id::text as cb \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('DSC4C Customer', 'manual', :'tier_name', :'wh1'::uuid, 0) returning id::text as cust \gset
insert into public.product (sku, name, source, brand_id, category_id) values ('DSC4C-X', 'DSC4C Product X', 'manual', :'bb'::uuid, :'cb'::uuid) returning id::text as px \gset
insert into public.product (sku, name, source, parent_product_id, pack_factor) values ('DSC4C-X-12', 'DSC4C Product X x12', 'manual', :'px'::uuid, 12) returning id::text as ps \gset
insert into public.product (sku, name, source, brand_id, category_id) values ('DSC4C-Y', 'DSC4C Product Y', 'manual', :'bb'::uuid, :'cb'::uuid) returning id::text as py \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4C Live Deal', 'date_from', '2031-01-01', 'date_to', '2031-12-31',
  'lines', jsonb_build_array(
     jsonb_build_object('line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4C-Tag'))),
     jsonb_build_object('line_no', 2, 'pct', 5,  'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'brand', 'brand_id', :'ba'))),
     jsonb_build_object('line_no', 3, 'pct', 7,  'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'category', 'category_id', :'ca'))),
     jsonb_build_object('line_no', 4, 'pct', 3,  'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4C-OffTag')))),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), null, true, array['deal:new:tag_unused']) as r \gset d1_
select public.so_deal_save(jsonb_build_object('name', 'DSC4C Dead Deal', 'is_active', false, 'date_from', '2031-01-01', 'date_to', '2031-12-31',
  'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4C-DeadTag'))))), null, true, array['deal:new:tag_unused']) as r \gset d2_
reset role;
select (:'d1_r'::jsonb->>'deal_id') as d1, (:'d1_r'::jsonb->>'updated_at') as u1 \gset
select l.id::text as l1 from public.so_deal_line l where l.deal_id = :'d1'::uuid and l.line_no = 1 \gset
select l.id::text as l2 from public.so_deal_line l where l.deal_id = :'d1'::uuid and l.line_no = 2 \gset
select l.id::text as l3 from public.so_deal_line l where l.deal_id = :'d1'::uuid and l.line_no = 3 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10), jsonb_build_object('id', :'l2', 'line_no', 2, 'pct', 5), jsonb_build_object('id', :'l3', 'line_no', 3, 'pct', 7))), to_jsonb(:'u1'::text), true) as r \gset d1b_
reset role;
select pg_temp.chk('M1 deals: live (3 on · 1 off) · dead inactive', (:'d1_r'::jsonb->>'committed') || '/' || (:'d1b_r'::jsonb->>'committed') || '/' || (select count(*) filter (where is_active) || '-' || count(*) filter (where not is_active) from public.so_deal_line l where l.deal_id = :'d1'::uuid) || '/' || (:'d2_r'::jsonb->>'committed') || '/' || (select d.is_active::text from public.so_deal d where d.id = (:'d2_r'::jsonb->>'deal_id')::uuid), 'true/true/3-1/true/false');
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct) values ('SO-79911', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', '2031-01-15', :'tier'::uuid, 0) returning id::text as o1 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, confirmed_at) values ('SO-79912', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'confirmed', '2031-01-15', :'tier'::uuid, 0, now()) returning id::text as o2 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, confirmed_at) values ('SO-79913', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', '2031-01-15', :'tier'::uuid, 0, now()) returning id::text as o3 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, reprice_suggested_at) values ('SO-79914', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', '2031-01-15', :'tier'::uuid, 0, now() - interval '1 hour') returning id::text as o4 \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, unit_price) values (:'o1'::uuid, 1, :'px'::uuid, 'DSC4C-X', 1, 1, 10, 10);
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, unit_price) values (:'o2'::uuid, 1, :'ps'::uuid, 'DSC4C-X-12', 12, 1, 120, 120);
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, unit_price) values (:'o3'::uuid, 1, :'px'::uuid, 'DSC4C-X', 1, 1, 10, 10);
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, unit_price) values (:'o4'::uuid, 1, :'px'::uuid, 'DSC4C-X', 1, 1, 10, 10);
set local session_replication_role = origin;
select to_json(s.reprice_suggested_at)::text as o4_ts from public.so s where s.id = :'o4'::uuid \gset
select pg_temp.chk('M2 orders: O1 draft X · O2 confirmed S(set of X) · O3 shipped X (outside draft·confirmed) · O4 draft X already flagged', pg_temp.flags(), 'SO-79911:false,SO-79912:false,SO-79913:false,SO-79914:true');

-- ═══ P1 태그 붙임(product_update 길) → 표시 · 뗌 → 표시 · P4 세트 줄(O2) 도 · P5 닫힌 O3 아님 · O4 시각 그대로 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4C-X', 'op', 'tag_add', 'tag', 'DSC4C-Tag')), true) as r \gset p1a_
reset role;
select pg_temp.chk('P1a tag_add DSC4C-Tag on X → O1 · O2(set line) flagged · O3 shipped not · O4 kept', (:'p1a_r'::jsonb->>'committed') || '/' || pg_temp.flags() || '/' || (select (to_json(s.reprice_suggested_at)::text = :'o4_ts')::text from public.so s where s.id = :'o4'::uuid), 'true/SO-79911:true,SO-79912:true,SO-79913:false,SO-79914:true/true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'o1'::uuid, :'o2'::uuid);
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4C-X', 'op', 'tag_off', 'tag', 'DSC4C-Tag')), true, array['DSC4C-X:tag_off_used_by_deal:DSC4C-Tag']) as r \gset p1b_
reset role;
select pg_temp.chk('P1b tag_off → O1 · O2 flagged again', (:'p1b_r'::jsonb->>'committed') || '/' || pg_temp.flags(), 'true/SO-79911:true,SO-79912:true,SO-79913:false,SO-79914:true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'o1'::uuid, :'o2'::uuid);
set local session_replication_role = origin;

-- ═══ P2 딜이 안 쓰는 태그 · 꺼진 딜의 태그 · 꺼진 줄의 태그 → 표시 없음(적재 길 = 직접 insert · delete) ═══
insert into public.product_tag (product_id, tag, source) values (:'px'::uuid, 'DSC4C-Other', 'cin7');
insert into public.product_tag (product_id, tag, source) values (:'px'::uuid, 'DSC4C-DeadTag', 'cin7');
insert into public.product_tag (product_id, tag, source) values (:'px'::uuid, 'DSC4C-OffTag', 'cin7');
delete from public.product_tag where product_id = :'px'::uuid and tag in ('DSC4C-Other', 'DSC4C-DeadTag', 'DSC4C-OffTag');
select pg_temp.chk('P2 unrelated · dead-deal · off-line tags (insert + delete) → nothing flagged', pg_temp.flags(), 'SO-79911:false,SO-79912:false,SO-79913:false,SO-79914:true');
-- 적재 upsert 꼴: 같은 행의 tag 를 걸린 글자로 바꾸면 표시 · 같은 값으로 update 는 표시 없음(P6)
insert into public.product_tag (product_id, tag, source) values (:'px'::uuid, 'DSC4C-Other', 'cin7');
update public.product_tag set tag = 'DSC4C-Other' where product_id = :'px'::uuid and tag = 'DSC4C-Other';
select pg_temp.chk('P6a product_tag update to the same value → nothing', pg_temp.flags(), 'SO-79911:false,SO-79912:false,SO-79913:false,SO-79914:true');
update public.product_tag set tag = 'DSC4C-Tag' where product_id = :'px'::uuid and tag = 'DSC4C-Other';
select pg_temp.chk('P2b product_tag update Other → Tag (reload upsert shape) → flagged', pg_temp.flags(), 'SO-79911:true,SO-79912:true,SO-79913:false,SO-79914:true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'o1'::uuid, :'o2'::uuid);
set local session_replication_role = origin;
delete from public.product_tag where product_id = :'px'::uuid;
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'o1'::uuid, :'o2'::uuid);
set local session_replication_role = origin;

-- ═══ P3 브랜드 · 카테고리(적재 길 = 직접 update) — 새 값이 걸림 · 옛 값이 걸림 · P6 같은 값 ═══
update public.product set brand_id = :'bb'::uuid where id = :'px'::uuid;
select pg_temp.chk('P6b brand set to the same value → nothing', pg_temp.flags(), 'SO-79911:false,SO-79912:false,SO-79913:false,SO-79914:true');
update public.product set brand_id = :'bc'::uuid where id = :'px'::uuid;
select pg_temp.chk('P3a brand B → C (neither targeted) → nothing', pg_temp.flags(), 'SO-79911:false,SO-79912:false,SO-79913:false,SO-79914:true');
update public.product set brand_id = :'ba'::uuid where id = :'px'::uuid;
select pg_temp.chk('P3b brand C → A (new value targeted) → O1 · O2 flagged', pg_temp.flags(), 'SO-79911:true,SO-79912:true,SO-79913:false,SO-79914:true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'o1'::uuid, :'o2'::uuid);
set local session_replication_role = origin;
update public.product set brand_id = :'bb'::uuid where id = :'px'::uuid;
select pg_temp.chk('P3c brand A → B (old value targeted) → flagged', pg_temp.flags(), 'SO-79911:true,SO-79912:true,SO-79913:false,SO-79914:true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'o1'::uuid, :'o2'::uuid);
set local session_replication_role = origin;
update public.product set category_id = :'ca'::uuid where id = :'px'::uuid;
select pg_temp.chk('P3d category B → A (new targeted) → flagged', pg_temp.flags(), 'SO-79911:true,SO-79912:true,SO-79913:false,SO-79914:true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'o1'::uuid, :'o2'::uuid);
set local session_replication_role = origin;
update public.product set category_id = :'cb'::uuid where id = :'px'::uuid;
select pg_temp.chk('P3e category A → B (old targeted) → flagged', pg_temp.flags(), 'SO-79911:true,SO-79912:true,SO-79913:false,SO-79914:true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'o1'::uuid, :'o2'::uuid);
set local session_replication_role = origin;

-- ═══ P4 낱개 ↔ 세트 범위 — Y(무관) 에 걸린 속성 변경은 X 의 오더를 건드리지 않음 · S 의 낱개를 Y 로 바꾸면(parent 변경) S 줄의 O2 만 ═══
update public.product set brand_id = :'ba'::uuid where id = :'py'::uuid;
select pg_temp.chk('P4a Y gets brand A — Y is in no order → nothing', pg_temp.flags(), 'SO-79911:false,SO-79912:false,SO-79913:false,SO-79914:true');
update public.product set parent_product_id = :'py'::uuid where id = :'ps'::uuid;
select pg_temp.chk('P4b S re-parented X → Y → only O2 (S line) flagged', pg_temp.flags(), 'SO-79911:false,SO-79912:true,SO-79913:false,SO-79914:true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'o1'::uuid, :'o2'::uuid);
set local session_replication_role = origin;
update public.product set parent_product_id = :'px'::uuid where id = :'ps'::uuid;
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'o1'::uuid, :'o2'::uuid);
set local session_replication_role = origin;
update public.product set brand_id = :'bb'::uuid where id = :'py'::uuid;
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'o1'::uuid, :'o2'::uuid);
set local session_replication_role = origin;
select pg_temp.chk('P5 O3 (shipped · outside the open set) never flagged · O4 timestamp never moved', (select (s.reprice_suggested_at is null)::text from public.so s where s.id = :'o3'::uuid) || '/' || (select (to_json(s.reprice_suggested_at)::text = :'o4_ts')::text from public.so s where s.id = :'o4'::uuid), 'true/true');

-- ═══ P7 재적재 무게 — 가짜 제품 2,000 개의 brand_id 를 한 문장으로(무관 → 거의 0 · 관련) · 문장 트리거(실물) 대 행 트리거(임시 probe) ═══
insert into public.product (sku, name, source, brand_id) select 'DSC4C-M' || lpad(g::text, 5, '0'), 'DSC4C Mass ' || g, 'manual', :'bb'::uuid from generate_series(1, 2000) g;
select clock_timestamp() as t0 \gset
update public.product set brand_id = :'bc'::uuid where sku like 'DSC4C-M%';
select clock_timestamp() as t1 \gset
update public.product set brand_id = :'ba'::uuid where sku like 'DSC4C-M%';
select clock_timestamp() as t2 \gset
select pg_temp.chk('P7a mass update touched 2,000 rows · no fake order flagged (mass products are in no order)', (select count(*)::text from public.product where sku like 'DSC4C-M%' and brand_id = :'ba'::uuid) || '/' || pg_temp.flags(), '2000/SO-79911:false,SO-79912:false,SO-79913:false,SO-79914:true');
create function public.dsc4c_probe_row() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if (old.brand_id, old.category_id, old.parent_product_id) is distinct from (new.brand_id, new.category_id, new.parent_product_id)
     and (exists (select 1 from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id and l.is_active join public.so_deal d on d.id = l.deal_id and d.is_active and not d.is_order_level
                   where (x.target = 'brand' and x.brand_id in (old.brand_id, new.brand_id)) or (x.target = 'category' and x.category_id in (old.category_id, new.category_id)))
          or (old.parent_product_id is distinct from new.parent_product_id and exists (select 1 from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id and l.is_active join public.so_deal d on d.id = l.deal_id and d.is_active and not d.is_order_level))) then
    perform public.so_product_flag_open_orders(array[new.id]);
  end if;
  return null;
end $$;
alter table public.product disable trigger product_deal_hit_changed;
create trigger dsc4c_probe_row after update of brand_id, category_id, parent_product_id on public.product for each row execute function public.dsc4c_probe_row();
select clock_timestamp() as t3 \gset
update public.product set brand_id = :'bc'::uuid where sku like 'DSC4C-M%';
select clock_timestamp() as t4 \gset
update public.product set brand_id = :'ba'::uuid where sku like 'DSC4C-M%';
select clock_timestamp() as t5 \gset
drop trigger dsc4c_probe_row on public.product;
drop function public.dsc4c_probe_row();
select clock_timestamp() as t6 \gset
update public.product set brand_id = :'bc'::uuid where sku like 'DSC4C-M%';
select clock_timestamp() as t7 \gset
update public.product set brand_id = :'ba'::uuid where sku like 'DSC4C-M%';
select clock_timestamp() as t8 \gset
alter table public.product enable trigger product_deal_hit_changed;
select 'P7 baseline (no dsc-4c trigger · 2,000 rows · ms): unrelated=' || round(extract(epoch from (:'t7'::timestamptz - :'t6'::timestamptz)) * 1000) || ' related=' || round(extract(epoch from (:'t8'::timestamptz - :'t7'::timestamptz)) * 1000);
select 'P7 timing (2,000 rows · ms): statement trigger unrelated=' || round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000) || ' related=' || round(extract(epoch from (:'t2'::timestamptz - :'t1'::timestamptz)) * 1000)
    || ' · row trigger unrelated=' || round(extract(epoch from (:'t4'::timestamptz - :'t3'::timestamptz)) * 1000) || ' related=' || round(extract(epoch from (:'t5'::timestamptz - :'t4'::timestamptz)) * 1000);
select pg_temp.chk('P7b statement trigger re-enabled · probe gone', (select count(*)::text from pg_trigger where tgrelid = 'public.product'::regclass and tgname = 'product_deal_hit_changed' and tgenabled = 'O') || '/' || (select count(*) from pg_trigger where tgname = 'dsc4c_probe_row'), '1/0');
update public.product set brand_id = :'ba'::uuid where id = :'px'::uuid;
select pg_temp.chk('P7c after the probe round the shipped trigger still flags (X → brand A)', pg_temp.flags(), 'SO-79911:true,SO-79912:true,SO-79913:false,SO-79914:true');

-- ═══ P8 권한 — helper · flag 함수는 anon · authenticated 42501 · 트리거 함수 실행권 없음 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
do $$ begin perform public.so_product_flag_open_orders(array[gen_random_uuid()]); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a1 \gset
do $$ begin perform public.so_deal_flag_open_orders(null, null, null, false, array[gen_random_uuid()]); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a2 \gset
reset role;
set local role anon;
do $$ begin perform public.so_product_flag_open_orders(array[gen_random_uuid()]); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a3 \gset
reset role;
select pg_temp.chk('P8a authenticated helper · flag → 42501 · anon helper → 42501', :'a1' || ',' || :'a2' || ',' || :'a3', '42501,42501,42501');
select pg_temp.chk('P8b trigger functions: no execute for authenticated · anon · public', (select count(*)::text from unnest(array['public.product_deal_hit_changed()', 'public.product_tag_deal_hit_changed()']) f where has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') or has_function_privilege('public', f, 'execute')), '0');
select pg_temp.chk('P8c old 4-arg flag function gone · callers still resolve (so_deal_changed fired by D1 activation earlier = no error) · product_update untouched', (to_regprocedure('public.so_deal_flag_open_orders(uuid, date, date, boolean)') is null)::text || '/' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'product_update' and p.prosrc like '%dsc-4c%'), 'true/0');

-- ═══ 끝 ═══
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
