-- supabase/tests/drx_1_check.sql — drx-1 deal_export 검증 (2026-10-27 · 판정 790 ~ 792 짐작 번호)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞 · 잠금 없음: 실제 딜 id · 세 kind 칸 목록 md5 · 행 수) → begin · lock_timeout 3s → (-v mig 면 \i)
--   → 가짜 재료(DRX- 접두 · 직원 셋 · 브랜드 · 카테고리 · 제품 낱개 넷 + 세트 둘 · 태그 · 가격 · 손님 · 딜 여섯 — 꺼진 채 만들고 → 켜기) → 꼴 · 권한 · 칸 · ⓐ · ⓑ · 가격 = so_quote_preview · 시간 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027134231_drx_1_deal_export.sql -f supabase/tests/drx_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 적용 전 마른 실행은 첫 deal_export 호출에서 「function does not exist」 로 선다(정상)
--   기대 OK: 시험 = 확인 = 아래 EXPECT_OK(시험에서만 도는 갈래 없음)
--   쓰기 = 가짜 재료만(rollback) · 창구는 stable · 시퀀스 0(딜 · 쿠폰 번호 없음)
--   ⭐⭐ Q 갈래 = deal_export 의 가격 식(so_line_quote 복사)이 Price check(so_quote_preview)와 같다는 증명 — so_line_quote 를 고치면 여기서 걸려야 한다
\set ON_ERROR_STOP on
\set EXPECT_OK 65
\pset pager off
-- ── 기준(begin 앞 · 잠금 없음) ──
select (select count(*) from public.so_deal) as n_deal, (select count(*) from public.so_deal_line) as n_line, (select count(*) from public.so_deal_target) as n_target,
       (select count(*) from public.so_deal_tier) as n_tier, (select count(*) from public.so_deal_customer_rule) as n_rule, (select count(*) from public.product) as n_prod,
       (select count(*) from public.product_tag) as n_tag, (select count(*) from public.product_price) as n_price, (select count(*) from public.ref_brand) as n_brand,
       (select count(*) from public.ref_category) as n_cat, (select count(*) from public.customer) as n_cust, (select count(*) from public.ims_staff) as n_staff,
       (select count(*) from public.so where reprice_suggested_at is not null) as n_flag \gset
select string_agg(id::text, ',') as real_line_deals from public.so_deal where is_active and not is_order_level \gset
select count(*) as want_b_real from public.so_deal_products_all((select array_agg(id) from public.so_deal where is_active and not is_order_level)) a join public.product p on p.id = a.product_id where p.is_active \gset
select count(*) as want_a_real from public.so_deal d left join public.so_deal_line l on l.deal_id = d.id \gset
select md5(string_agg(x.k || c.ord || c.key || c.label || c.grp || c.dflt || c.gate || c.is_text, '|' order by x.k, c.ord)) as old_cat_md5, count(*) as old_cat_n
from (select 'product' as k union all select 'customer' union all select 'supplier') x, lateral public.export_catalog(x.k) c \gset
select t.id::text as t1_id, t.name as t1_name from public.ref_price_tier t where t.code = 1 and t.purpose = 'sale' and t.is_active \gset
select t.id::text as t2_id, t.name as t2_name from public.ref_price_tier t where t.code = 2 and t.purpose = 'sale' and t.is_active \gset
select count(*) as n_sale_tiers from public.ref_price_tier t where t.purpose = 'sale' and t.is_active \gset
select w.id::text as wh_id, w.name as wh_name from public.ref_warehouse w where w.is_active order by w.name limit 1 \gset
\echo '── 기준: so_deal' :n_deal '· line' :n_line '· product' :n_prod '· product_tag' :n_tag '· product_price' :n_price '· staff' :n_staff '· 실제 ⓑ 활성 줄' :want_b_real '· 실제 ⓐ 줄' :want_a_real '· 옛 kind 칸' :old_cat_n '· sale 등급' :n_sale_tiers '· 티어1' :t1_name '· 티어2' :t2_name
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
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

-- ── 가짜 재료 ──
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values
  (gen_random_uuid(), 'drx1-admin@test.invalid', 'drx1 admin',      'admin',  '[]', true),
  (gen_random_uuid(), 'drx1-sales@test.invalid', 'drx1 sales read', 'worker', '["sales:read"]', true),
  (gen_random_uuid(), 'drx1-none@test.invalid',  'drx1 no keys',    'worker', '[]', true);
select max(auth_user_id::text) filter (where email = 'drx1-admin@test.invalid') as u_a, max(auth_user_id::text) filter (where email = 'drx1-sales@test.invalid') as u_s,
       max(auth_user_id::text) filter (where email = 'drx1-none@test.invalid') as u_n from public.ims_staff where email like 'drx1-%@test.invalid' \gset
insert into public.ref_brand (name, source) values ('DRX-Brand', 'manual'), ('DRX-Brand2', 'manual');
insert into public.ref_category (name, source) values ('DRX-Cat', 'manual');
select (select id::text from public.ref_brand where name = 'DRX-Brand') as b1, (select id::text from public.ref_brand where name = 'DRX-Brand2') as b2, (select id::text from public.ref_category where name = 'DRX-Cat') as c1 \gset
-- 낱개 A(브랜드1 · 카테고리 · 태그 DRX-tag) · B(브랜드1 · 카테고리 · 태그 DRX-skip → 딜 1 에서 빠짐) · C(브랜드2 · 카테고리 · 태그 DRX-tag) · D(브랜드2 · 개별 제품 대상) · X(브랜드1 · 비활성)
insert into public.product (sku, name, source, is_active, brand_id, brand_name, category_id, category_name) values
  ('DRX-A', 'DRX single A', 'manual', true,  :'b1', 'DRX-Brand',  :'c1', 'DRX-Cat'),
  ('DRX-B', 'DRX single B', 'manual', true,  :'b1', 'DRX-Brand',  :'c1', 'DRX-Cat'),
  ('DRX-C', 'DRX single C', 'manual', true,  :'b2', 'DRX-Brand2', :'c1', 'DRX-Cat'),
  ('DRX-D', 'DRX single D', 'manual', true,  :'b2', 'DRX-Brand2', null, null),
  ('DRX-X', 'DRX single X', 'manual', false, :'b1', 'DRX-Brand',  :'c1', 'DRX-Cat');
select (select id::text from public.product where sku = 'DRX-A') as pa, (select id::text from public.product where sku = 'DRX-B') as pb, (select id::text from public.product where sku = 'DRX-C') as pc,
       (select id::text from public.product where sku = 'DRX-D') as pd \gset
-- 세트 둘(A 의) — A-12 는 티어1 에 자기 가격 줄(row) · A-24 는 가격 줄 없음(set_calc) + set_discount_pct 35(세트 할인이 줄 % 를 이기는 경우)
insert into public.product (sku, name, source, is_active, brand_id, brand_name, category_id, category_name, parent_product_id, pack_factor, set_discount_pct) values
  ('DRX-A-12', 'DRX set A x12', 'manual', true, :'b1', 'DRX-Brand', :'c1', 'DRX-Cat', :'pa', 12, null),
  ('DRX-A-24', 'DRX set A x24', 'manual', true, :'b1', 'DRX-Brand', :'c1', 'DRX-Cat', :'pa', 24, 35);
select (select id::text from public.product where sku = 'DRX-A-12') as pa12, (select id::text from public.product where sku = 'DRX-A-24') as pa24 \gset
insert into public.product_tag (product_id, tag, source) values (:'pa', 'DRX-tag', 'manual'), (:'pc', 'DRX-tag', 'manual'), (:'pb', 'DRX-skip', 'manual');
insert into public.product_price (product_id, tier_id, price, source) values
  (:'pa', :'t1_id', 10.00, 'manual'), (:'pb', :'t1_id', 8.50, 'manual'), (:'pc', :'t1_id', 3.33, 'manual'), (:'pd', :'t1_id', 2.49, 'manual'), (:'pa12', :'t1_id', 100.00, 'manual'),
  (:'pa', :'t2_id', 9.00, 'manual');
insert into public.customer (name, source, is_active, price_tier, discount_pct) values ('DRX Cust', 'manual', true, :'t1_name', 0);
select id::text as cu from public.customer where name = 'DRX Cust' \gset
-- 딜 여섯 — 꺼진 채 만들고 자식 뒤에 켠다(so_deal_save 가 하는 순서 · 켠 채 넣으면 손님 조건 없는 순간에 열린 초안을 전부 표시)
insert into public.so_deal (name, source, is_active, is_order_level, coupon_required, date_from, date_to) values
  ('DRX-1 brand',   'manual', false, false, false, null, null),
  ('DRX-2 product', 'manual', false, false, false, null, null),
  ('DRX-3 qty',     'manual', false, false, false, null, null),
  ('DRX-4 order',   'manual', false, true,  false, null, null),
  ('DRX-5 custlim', 'manual', false, false, false, null, null),
  ('DRX-6 coupon',  'manual', false, true,  true,  public.ims_today() - 10, public.ims_today() - 1);
select (select id::text from public.so_deal where name = 'DRX-1 brand') as d1, (select id::text from public.so_deal where name = 'DRX-2 product') as d2, (select id::text from public.so_deal where name = 'DRX-3 qty') as d3,
       (select id::text from public.so_deal where name = 'DRX-4 order') as d4, (select id::text from public.so_deal where name = 'DRX-5 custlim') as d5, (select id::text from public.so_deal where name = 'DRX-6 coupon') as d6 \gset
insert into public.so_deal_line (deal_id, line_no, pct, min_qty_mode, min_qty, is_active, source) values
  (:'d1', 1, 20, 'none', null, true,  'manual'),
  (:'d2', 1, 15, 'none', null, true,  'manual'), (:'d2', 2, 50, 'none', null, false, 'manual'),
  (:'d3', 1, 10, 'qty',  12,   true,  'manual'), (:'d3', 2, 8,  'case', null, true,  'manual'),
  (:'d5', 1, 25, 'none', null, true,  'manual');
select (select id::text from public.so_deal_line where deal_id = :'d1' and line_no = 1) as l11, (select id::text from public.so_deal_line where deal_id = :'d2' and line_no = 1) as l21,
       (select id::text from public.so_deal_line where deal_id = :'d2' and line_no = 2) as l22, (select id::text from public.so_deal_line where deal_id = :'d3' and line_no = 1) as l31,
       (select id::text from public.so_deal_line where deal_id = :'d3' and line_no = 2) as l32, (select id::text from public.so_deal_line where deal_id = :'d5' and line_no = 1) as l51 \gset
insert into public.so_deal_target (line_id, kind, target, tag, brand_id, product_id, category_id, source) values
  (:'l11', 'include', 'brand',    null,       :'b1', null,  null,  'manual'), (:'l11', 'exclude', 'tag', 'DRX-skip', null, null, null, 'manual'),
  (:'l21', 'include', 'product',  null,       null,  :'pd', null,  'manual'),
  (:'l22', 'include', 'product',  null,       null,  :'pa', null,  'manual'),
  (:'l31', 'include', 'category', null,       null,  null,  :'c1', 'manual'),
  (:'l32', 'include', 'category', null,       null,  null,  :'c1', 'manual'),
  (:'l51', 'include', 'tag',      'DRX-tag',  null,  null,  null,  'manual');
insert into public.so_deal_tier (deal_id, tier_no, min_amount, pct, source) values (:'d4', 1, 0, 2, 'manual'), (:'d4', 2, 500, 5, 'manual'), (:'d6', 1, 0, 20, 'manual');
insert into public.so_deal_customer_rule (deal_id, kind, target, customer_id, warehouse_id, tier_id, source) values
  (:'d4', 'include', 'customer', :'cu', null, null, 'manual'), (:'d4', 'exclude', 'branch', null, :'wh_id', null, 'manual'),
  (:'d5', 'include', 'tier', null, null, :'t1_id', 'manual');
update public.so_deal set is_active = true where name like 'DRX-%';
select format('{%s,%s,%s,%s,%s,%s}', :'d1', :'d2', :'d3', :'d4', :'d5', :'d6') as all6 \gset
select format('{%s,%s,%s,%s,%s}', :'d1', :'d2', :'d3', :'d5', :'d6') as line5 \gset

-- ── F 꼴 ──
select count(*)::text as n_fn, coalesce(max(p.provolatile::text), '-') as vol, coalesce(max(p.prosecdef::text), '-') as def, coalesce(max(array_to_string(p.proconfig, ',')), '-') as cfg,
       coalesce(max(p.prorettype::regtype::text), '-') as rtype, coalesce(max(left(obj_description(p.oid, 'pg_proc'), 5)), '-') as cmt
from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'deal_export' \gset
select pg_temp.chk('F1 one deal_export', :'n_fn', '1');
select pg_temp.chk('F2 stable · definer · search_path · jsonb', :'vol' || ' ' || :'def' || ' ' || :'cfg' || ' ' || :'rtype', 's true search_path=public, pg_temp jsonb');
select pg_temp.chk('F3 comment starts drx-1', :'cmt', 'drx-1');
select pg_temp.chk('F4 deal_export body carries the so_line_quote marker', pg_temp.run('select (prosrc like ''%so_line_quote 복사 시작%'' and prosrc like ''%so_line_quote 복사 끝%'')::text from pg_proc where pronamespace = ''public''::regnamespace and proname = ''deal_export'''), 'true');
select pg_temp.chk('F5 export_pick untouched', pg_temp.run('select (prosrc not like ''%drx-1%'')::text from pg_proc where pronamespace = ''public''::regnamespace and proname = ''export_pick'''), 'true');

-- ── P 권한 ──
select pg_temp.chk('P1 authenticated can execute deal_export', pg_temp.run('select has_function_privilege(''authenticated'', ''public.deal_export(uuid[], text, text[])'', ''execute'')::text'), 'true');
select pg_temp.chk('P2 anon · public · service_role cannot', pg_temp.run('select (has_function_privilege(''anon'', ''public.deal_export(uuid[], text, text[])'', ''execute'') or has_function_privilege(''public'', ''public.deal_export(uuid[], text, text[])'', ''execute'') or has_function_privilege(''service_role'', ''public.deal_export(uuid[], text, text[])'', ''execute''))::text'), 'false');
select pg_temp.chk('P3 inner export_catalog · export_door still closed to authenticated', pg_temp.run('select (has_function_privilege(''authenticated'', ''public.export_catalog(text)'', ''execute'') or has_function_privilege(''authenticated'', ''public.export_door(text)'', ''execute''))::text'), 'false');
select pg_temp.chk('P4 export_columns still granted to authenticated only', pg_temp.run('select (has_function_privilege(''authenticated'', ''public.export_columns(text)'', ''execute'') and not has_function_privilege(''anon'', ''public.export_columns(text)'', ''execute''))::text'), 'true');
set local role anon;
select pg_temp.run('select public.deal_export(null, ''deal_rule'', null)::text') as anon_call \gset
reset role;
select pg_temp.chk('P5 anon role: 42501', left(:'anon_call', 9), 'ERR 42501');
select set_config('request.jwt.claims', json_build_object('sub', :'u_n', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run('select public.export_columns(''deal_rule'')::text') as n_cols \gset
select pg_temp.run(format('select public.deal_export(%L::uuid[], ''deal_product'', array[''sku''])::text', :'all6')) as n_exp \gset
reset role;
select pg_temp.chk('P6 no keys: column list refused', :'n_cols', 'ERR P0001: You cannot export discount rules — nothing was read');
select pg_temp.chk('P7 no keys: export refused at the door', :'n_exp', 'ERR P0001: You cannot export discount rules — ask an admin for the sales permission — nothing was exported');
select set_config('request.jwt.claims', json_build_object('sub', :'u_s', 'role', 'authenticated')::text, true);
set local role authenticated;
select (select count(*) from jsonb_array_elements(public.export_columns('deal_rule')->'columns')) as s_rule_cols,
       (select count(*) from jsonb_array_elements(public.export_columns('deal_product')->'columns')) as s_prod_cols,
       (select count(*) from jsonb_array_elements(public.export_columns('deal_product')->'columns') c where c->>'key' = 'after_8' or c->>'label' ilike '%REFERENCE%') as s_ref,
       (select string_agg(c->>'key', ',' order by ord) from jsonb_array_elements(public.export_columns('deal_product')->'columns') with ordinality x(c, ord) where (c->>'default')::boolean) as s_prod_dflt,
       (select string_agg(c->>'key', ',' order by ord) from jsonb_array_elements(public.export_columns('deal_rule')->'columns') with ordinality x(c, ord) where (c->>'default')::boolean) as s_rule_dflt,
       (select string_agg(c->>'key', ',' order by ord) from jsonb_array_elements(public.export_columns('deal_product')->'columns') with ordinality x(c, ord) where (c->>'text')::boolean) as s_prod_text,
       (select count(*) from jsonb_array_elements(public.export_columns('deal_product')->'columns') c where c->>'key' like 'list\_%') as s_list_n \gset
reset role;
select pg_temp.chk('P8 sales read: deal_rule columns = 20', :'s_rule_cols', '20');
select pg_temp.chk('P9 sales read: deal_product columns = 18 + 2 × sale tiers', :'s_prod_cols', (18 + 2 * :n_sale_tiers)::text);
select pg_temp.chk('C1 no reference tier (760)', :'s_ref', '0');
select pg_temp.chk('C2 deal_product defaults = up to Rule % (792)', :'s_prod_dflt', 'rule_name,customer_limited,line_no,sku,name,brand,category,pct,min_qty');
select pg_temp.chk('C3 deal_rule defaults', :'s_rule_dflt', 'rule_name,rule_type,status,date_from,date_to,coupon_required,customer_rules,tiers,line_no,pct,min_qty,include_targets,exclude_targets');
select pg_temp.chk('C4 text columns = sku · parent_sku', :'s_prod_text', 'sku,parent_sku');
select pg_temp.chk('C5 list_ columns = sale tiers', :'s_list_n', :'n_sale_tiers');
select pg_temp.chk('C6 old kinds: same columns, byte for byte', pg_temp.run('select md5(string_agg(x.k || c.ord || c.key || c.label || c.grp || c.dflt || c.gate || c.is_text, ''|'' order by x.k, c.ord)) || '' '' || count(*) from (select ''product'' as k union all select ''customer'' union all select ''supplier'') x, lateral public.export_catalog(x.k) c'), :'old_cat_md5' || ' ' || :'old_cat_n');

-- ── C 거부(sales read 직원) ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_s', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run(format('select public.deal_export(%L::uuid[], ''deal_product'', array[''sku'', ''price_1''])::text', :'all6')) as c_price1,
       pg_temp.run(format('select public.deal_export(%L::uuid[], ''deal_product'', array[''sku'', ''after_8''])::text', :'all6')) as c_after8,
       pg_temp.run(format('select public.deal_export(%L::uuid[], ''deal_rule'', array[''sku''])::text', :'all6')) as c_wrongkind,
       pg_temp.run(format('select public.deal_export(%L::uuid[], ''deal_rule'', array[]::text[])::text', :'all6')) as c_empty_cols,
       pg_temp.run(format('select public.deal_export(%L::uuid[], ''deal_rule'', array[''pct'', ''pct''])::text', :'all6')) as c_twice,
       pg_temp.run(format('select public.deal_export(%L::uuid[], ''deals'', array[''pct''])::text', :'all6')) as c_badkind,
       pg_temp.run('select public.deal_export(array[]::uuid[], ''deal_rule'', array[''pct''])::text') as c_noids,
       pg_temp.run('select public.deal_export(null, ''deal_rule'', array[''pct''])::text') as c_nullids,
       pg_temp.run(format('select public.deal_export(%L::uuid[], ''deal_rule'', array[''pct''])::text', format('{%s,%s}', :'d1', gen_random_uuid()))) as c_missing,
       (public.deal_export(format('{%s,%s,%s}', :'d1', :'d1', :'d1')::uuid[], 'deal_product', array['sku'])->>'row_count') as c_dup3,
       (public.deal_export(format('{%s}', :'d1')::uuid[], 'deal_product', array['sku'])->>'row_count') as c_dup1 \gset
reset role;
select pg_temp.chk('C7 product-kind price key refused in deal_product', :'c_price1', 'ERR P0001: Unknown columns: price_1 — nothing was exported');
select pg_temp.chk('C8 reference tier key refused (760)', :'c_after8', 'ERR P0001: Unknown columns: after_8 — nothing was exported');
select pg_temp.chk('C9 deal_product key refused in deal_rule', :'c_wrongkind', 'ERR P0001: Unknown columns: sku — nothing was exported');
select pg_temp.chk('C10 empty pick refused', :'c_empty_cols', 'ERR P0001: Pick at least one column — nothing was exported');
select pg_temp.chk('C11 same column twice refused', :'c_twice', 'ERR P0001: These columns are picked twice: pct — nothing was exported');
select pg_temp.chk('C12 bad kind refused', :'c_badkind', 'ERR P0001: p_kind must be deal_rule or deal_product — nothing was exported');
select pg_temp.chk('C13 empty id array refused', :'c_noids', 'ERR P0001: Pick at least one rule — nothing was exported');
select pg_temp.chk('C14 null id array refused', :'c_nullids', 'ERR P0001: Pick at least one rule — nothing was exported');
select pg_temp.chk('C15 unknown id refused', :'c_missing', 'ERR P0001: 1 of the picked rules no longer exist — reload the list — nothing was exported');
select pg_temp.chk('C16 same id three times = once', :'c_dup3', :'c_dup1');

-- ── A ⓐ 규칙 정의(sales read 직원 · 딜 여섯 · 칸 전부) ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_s', 'role', 'authenticated')::text, true);
set local role authenticated;
create temp table t_a as
  select r.o, r.v from (select public.deal_export(:'all6'::uuid[], 'deal_rule', (select array_agg(c->>'key' order by ord) from jsonb_array_elements(public.export_columns('deal_rule')->'columns') with ordinality x(c, ord))) as x) s,
       lateral jsonb_array_elements(s.x->'rows') with ordinality r(v, o);
select (public.deal_export(:'all6'::uuid[], 'deal_rule', array['rule_name'])->>'total') as a_total,
       (public.deal_export(:'all6'::uuid[], 'deal_rule', array['rule_name'])->>'truncated') as a_trunc,
       (public.deal_export(:'all6'::uuid[], 'deal_rule', array['rule_name'])->>'kind') as a_kind \gset
reset role;
-- 칸 자리: rule_name 0 · rule_type 1 · status 2 · is_active 3 · date_from 4 · date_to 5 · coupon_required 6 · customer_rules 7 · tiers 8 · note 9 · source 10 · updated_at 11 · line_no 12 · line_on 13 · pct 14 · min_qty_rule 15 · min_qty 16 · include_targets 17 · exclude_targets 18 · line_note 19
select pg_temp.chk('A1 rows = lines (off too) + deals without lines', :'a_total', '8');
select pg_temp.chk('A1b kind · not truncated', :'a_kind' || ' ' || :'a_trunc', 'deal_rule false');
select pg_temp.chk('A2 brand line: applies to brand, except tag', pg_temp.run('select (v->>17) || '' | '' || (v->>18) from t_a where v->>0 = ''DRX-1 brand'''), 'brand: DRX-Brand | tag: DRX-skip');
select pg_temp.chk('A3 order deal: one row, tiers text, customer rules text (except first)', pg_temp.run('select count(*)::text || '' | '' || max(v->>1) || '' | '' || max(v->>8) || '' | '' || max(v->>7) || '' | '' || max(coalesce(v->>12, ''-'')) from t_a where v->>0 = ''DRX-4 order'''), '1 | Order discount | ≥ 0.00: 2%; ≥ 500.00: 5% | Except branch = ' || :'wh_name' || '; customer = DRX Cust | -');
select pg_temp.chk('A4 off line is there with Line on = false', pg_temp.run('select (v->>13) || '' '' || (v->>14) || '' '' || (v->>17) from t_a where v->>0 = ''DRX-2 product'' and v->>12 = ''2'''), 'false 50 product: DRX-A');
select pg_temp.chk('A5 min qty rule words', pg_temp.run('select string_agg(coalesce(v->>15, ''-'') || ''/'' || coalesce(v->>16, ''-''), '', '' order by v->>12) from t_a where v->>0 = ''DRX-3 qty'''), 'at least 12 each/12, full case/-');
select pg_temp.chk('A6 ended coupon deal: status · coupon · tiers · dates', pg_temp.run('select (v->>2) || '' '' || (v->>6) || '' '' || (v->>8) || '' '' || (v->>5) from t_a where v->>0 = ''DRX-6 coupon'''), 'Ended true ≥ 0.00: 20% ' || (public.ims_today() - 1)::text);
select pg_temp.chk('A7 tier-rule deal: customer rules text', pg_temp.run('select v->>7 from t_a where v->>0 = ''DRX-5 custlim'''), 'tier = ' || :'t1_name');
select pg_temp.chk('A8 no customer rules = All customers · Live · Line discount · IMS', pg_temp.run('select (v->>7) || '' '' || (v->>2) || '' '' || (v->>1) || '' '' || (v->>10) from t_a where v->>0 = ''DRX-1 brand'''), 'All customers Live Line discount IMS');
select pg_temp.chk('A9 ordering = rule name, line no', pg_temp.run('select string_agg((v->>0) || ''#'' || coalesce(v->>12, ''-''), '','' order by o) from t_a'), 'DRX-1 brand#1,DRX-2 product#1,DRX-2 product#2,DRX-3 qty#1,DRX-3 qty#2,DRX-4 order#-,DRX-5 custlim#1,DRX-6 coupon#-');

-- ── B ⓑ 풀린 제품(sales read 직원 · 줄 딜 다섯 · 칸 전부) ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_s', 'role', 'authenticated')::text, true);
set local role authenticated;
create temp table t_b as
  select r.o, r.v from (select public.deal_export(:'line5'::uuid[], 'deal_product', (select array_agg(c->>'key' order by ord) from jsonb_array_elements(public.export_columns('deal_product')->'columns') with ordinality x(c, ord))) as x) s,
       lateral jsonb_array_elements(s.x->'rows') with ordinality r(v, o);
create temp table t_bc as
  select (r.o - 1)::int as i, r.v->>'key' as key from (select public.deal_export(:'line5'::uuid[], 'deal_product', (select array_agg(c->>'key' order by ord) from jsonb_array_elements(public.export_columns('deal_product')->'columns') with ordinality x(c, ord))) as x) s,
       lateral jsonb_array_elements(s.x->'columns') with ordinality r(v, o);
select (public.deal_export(:'line5'::uuid[], 'deal_product', array['sku'])->>'total') as b_total,
       (public.deal_export(format('{%s}', :'d4')::uuid[], 'deal_product', array['sku'])->>'total') as b_order_total,
       (public.deal_export(format('{%s}', :'d4')::uuid[], 'deal_product', array['sku'])->>'rows') as b_order_rows \gset
reset role;
create function pg_temp.bv(p_rule text, p_sku text, p_line int, p_key text) returns text language sql as $$
  select b.v->>(c.i) from t_b b, t_bc c where c.key = p_key and b.v->>(select i from t_bc where key = 'rule_name') = p_rule and b.v->>(select i from t_bc where key = 'sku') = p_sku and (b.v->>(select i from t_bc where key = 'line_no'))::int = p_line;
$$;
select pg_temp.chk('B1 rows = (rule × product × line) · active products · on lines', :'b_total', '18');
select pg_temp.chk('B1b same count by hand (so_deal_products_all ∩ active)', :'b_total', pg_temp.run(format('select count(*)::text from public.so_deal_products_all(%L::uuid[]) a join public.product p on p.id = a.product_id where p.is_active', :'line5')));
select pg_temp.chk('B2 brand deal: A + its two sets, not B (tag excluded), not X (inactive)', pg_temp.run('select string_agg(v->>(select i from t_bc where key = ''sku''), '','' order by o) from t_b where v->>(select i from t_bc where key = ''rule_name'') = ''DRX-1 brand'''), 'DRX-A,DRX-A-12,DRX-A-24');
select pg_temp.chk('B3 product deal: only the on line (D), not the off line (A)', pg_temp.run('select string_agg(v->>(select i from t_bc where key = ''sku'') || ''#'' || (v->>(select i from t_bc where key = ''line_no'')), '','' order by o) from t_b where v->>(select i from t_bc where key = ''rule_name'') = ''DRX-2 product'''), 'DRX-D#1');
select pg_temp.chk('B4 category deal: five products × two lines, ordered sku then line', pg_temp.run('select string_agg(v->>(select i from t_bc where key = ''sku'') || ''#'' || (v->>(select i from t_bc where key = ''line_no'')), '','' order by o) from t_b where v->>(select i from t_bc where key = ''rule_name'') = ''DRX-3 qty'''), 'DRX-A#1,DRX-A#2,DRX-A-12#1,DRX-A-12#2,DRX-A-24#1,DRX-A-24#2,DRX-B#1,DRX-B#2,DRX-C#1,DRX-C#2');
select pg_temp.chk('B5 set row: Kind · Set of · Pack factor · Picked by', pg_temp.bv('DRX-1 brand', 'DRX-A-24', 1, 'kind') || ' | ' || pg_temp.bv('DRX-1 brand', 'DRX-A-24', 1, 'parent_sku') || ' | ' || pg_temp.bv('DRX-1 brand', 'DRX-A-24', 1, 'pack_factor') || ' | ' || pg_temp.bv('DRX-1 brand', 'DRX-A-24', 1, 'matched_by'), 'Set | DRX-A | 24 | brand; brand:base');
select pg_temp.chk('B6 single row: Kind · Picked by · no parent', pg_temp.bv('DRX-1 brand', 'DRX-A', 1, 'kind') || ' | ' || pg_temp.bv('DRX-1 brand', 'DRX-A', 1, 'matched_by') || ' | ' || coalesce(pg_temp.bv('DRX-1 brand', 'DRX-A', 1, 'parent_sku'), '-'), 'Single | brand | -');
select pg_temp.chk('B7 customer rules flag: Yes on the tier-limited deal, No on the brand deal', pg_temp.bv('DRX-5 custlim', 'DRX-C', 1, 'customer_limited') || ' ' || pg_temp.bv('DRX-1 brand', 'DRX-A', 1, 'customer_limited'), 'true false');
select pg_temp.chk('B8 qty line: Min qty (each) 12 · words', pg_temp.bv('DRX-3 qty', 'DRX-B', 1, 'min_qty') || ' | ' || pg_temp.bv('DRX-3 qty', 'DRX-B', 1, 'min_qty_rule'), '12 | at least 12 each');
select pg_temp.chk('B9 case line: A = smallest active set (12) · C has no set = blank · set row = its single''s case', coalesce(pg_temp.bv('DRX-3 qty', 'DRX-A', 2, 'min_qty'), '-') || ' | ' || coalesce(pg_temp.bv('DRX-3 qty', 'DRX-C', 2, 'min_qty'), '-') || ' | ' || coalesce(pg_temp.bv('DRX-3 qty', 'DRX-A-24', 2, 'min_qty'), '-') || ' | ' || pg_temp.bv('DRX-3 qty', 'DRX-C', 2, 'min_qty_rule'), '12 | - | 12 | full case');
select pg_temp.chk('B10 order deal alone: 0 rows, no error', :'b_order_total' || ' ' || :'b_order_rows', '0 []');
select pg_temp.chk('B11 Rule % is the line pct as is', pg_temp.bv('DRX-5 custlim', 'DRX-A', 1, 'pct') || ' ' || pg_temp.bv('DRX-3 qty', 'DRX-C', 2, 'pct'), '25 8');
select pg_temp.chk('B12 status Live · coupon false on line deals', pg_temp.bv('DRX-1 brand', 'DRX-A', 1, 'status') || ' ' || pg_temp.bv('DRX-1 brand', 'DRX-A', 1, 'coupon_required'), 'Live false');

-- ── Q 가격 = so_line_quote 식 (티어1 · 티어2) · Price check(so_quote_preview) 와 같은 값 ──
select pg_temp.chk('Q1 single, own price: list 10 → 20% = 8.0000 (list comes with the stored 7 decimals, as product_export)', round(pg_temp.bv('DRX-1 brand', 'DRX-A', 1, 'list_1')::numeric, 2)::text || ' ' || pg_temp.bv('DRX-1 brand', 'DRX-A', 1, 'after_1'), '10.00 8.0000');
select pg_temp.chk('Q2 set with its own price row: list 100 → 20% = 80 (set % not a candidate)', round(pg_temp.bv('DRX-1 brand', 'DRX-A-12', 1, 'list_1')::numeric, 2)::text || ' ' || pg_temp.bv('DRX-1 brand', 'DRX-A-12', 1, 'after_1'), '100.00 80.0000');
select pg_temp.chk('Q3 set_calc set: list = round(10 × 24, 2) = 240.00 → greatest(20, set 35) = 156.0000', pg_temp.bv('DRX-1 brand', 'DRX-A-24', 1, 'list_1') || ' ' || pg_temp.bv('DRX-1 brand', 'DRX-A-24', 1, 'after_1'), '240.00 156.0000');
select pg_temp.chk('Q4 tier 2: single 9 → 7.2000 · set without own row falls to set_calc 108 → 86.4000 · no price = blank', round(pg_temp.bv('DRX-1 brand', 'DRX-A', 1, 'list_2')::numeric, 2)::text || ' ' || pg_temp.bv('DRX-1 brand', 'DRX-A', 1, 'after_2') || ' | ' || pg_temp.bv('DRX-1 brand', 'DRX-A-12', 1, 'list_2') || ' ' || pg_temp.bv('DRX-1 brand', 'DRX-A-12', 1, 'after_2') || ' | ' || coalesce(pg_temp.bv('DRX-3 qty', 'DRX-C', 1, 'list_2'), '-') || ' ' || coalesce(pg_temp.bv('DRX-3 qty', 'DRX-C', 1, 'after_2'), '-'), '9.00 7.2000 | 108.00 86.4000 | - -');
select pg_temp.chk('Q5 4 decimals, not 2: 3.33 → 10% = 2.9970', pg_temp.bv('DRX-3 qty', 'DRX-C', 1, 'after_1'), '2.9970');
-- Q6 ~ Q7: 제품 · 티어마다 so_quote_preview(DRX Cust · 손님 기본 할인 0 · 수량 100 → 모든 수량 문턱 통과) 의 unit_price(4 자리) = 그 제품 줄들의 가장 낮은 After(= 가장 큰 % · 티어 2 에선 티어1 조건 딜(DRX-5)을 뺀다) · list_price = List
select set_config('request.jwt.claims', json_build_object('sub', :'u_s', 'role', 'authenticated')::text, true);
set local role authenticated;
create temp table t_q as
  select p.sku, t.code, q.x->>'unit_price' as pv_unit, round((q.x->>'unit_price')::numeric, 4)::text as pv_unit4, q.x->>'list_price' as pv_list, q.x->>'discount_source' as pv_src, (q.x->>'discount_pct') as pv_pct
  from public.product p cross join (select :'t1_id'::uuid as id, 1 as code union all select :'t2_id'::uuid, 2) t
  cross join lateral (select public.so_quote_preview(:'cu'::uuid, p.id, 100, null, t.id) as x) q
  where p.sku in ('DRX-A', 'DRX-A-12', 'DRX-A-24', 'DRX-B', 'DRX-C', 'DRX-D');
reset role;
create temp table t_qx as
  select b.v->>(select i from t_bc where key = 'sku') as sku, t.code,
         min((b.v->>(select i from t_bc where key = 'after_' || t.code))::numeric)::text as ex_after,
         max(b.v->>(select i from t_bc where key = 'list_' || t.code)) as ex_list
  from t_b b cross join (select 1 as code union all select 2) t
  where not (t.code = 2 and b.v->>(select i from t_bc where key = 'rule_name') = 'DRX-5 custlim')
  group by 1, 2;
\echo '── Q 대조표(Price check unit_price vs export After · 제품 × 티어)'
select q.sku, q.code, q.pv_list, x.ex_list, q.pv_unit, x.ex_after, q.pv_src, q.pv_pct, (q.pv_unit4 is not distinct from x.ex_after and q.pv_list is not distinct from x.ex_list) as same from t_q q join t_qx x on x.sku = q.sku and x.code = q.code order by 1, 2;
select pg_temp.chk('Q6 every product × tier: Price check unit (4 dp) = lowest After rule % of its rows', pg_temp.run('select count(*)::text from t_q q join t_qx x on x.sku = q.sku and x.code = q.code where q.pv_unit4 is distinct from x.ex_after'), '0');
select pg_temp.chk('Q7 every product × tier: Price check list = List', pg_temp.run('select count(*)::text from t_q q join t_qx x on x.sku = q.sku and x.code = q.code where q.pv_list is distinct from x.ex_list'), '0');
select pg_temp.chk('Q8 pairs compared = 6 products × 2 tiers', pg_temp.run('select count(*)::text from t_q q join t_qx x on x.sku = q.sku and x.code = q.code'), '12');
select pg_temp.chk('Q9 Price check says the set discount won on DRX-A-24 (the export shows the same price)', pg_temp.run('select pv_src || '' '' || pv_pct from t_q where sku = ''DRX-A-24'' and code = 1'), 'set 35');

-- ── T 실제 딜 · 크기 · 시간(sales read 직원 · REST 조건 8 초) ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_s', 'role', 'authenticated')::text, true);
set local role authenticated;
set local statement_timeout = '8s';
select clock_timestamp() as t5a \gset
select (x->>'row_count') as t_b_rows, (x->>'total') as t_b_total, (x->>'truncated') as t_b_trunc, length(x::text) as t_b_bytes
from (select public.deal_export(format('{%s}', :'real_line_deals')::uuid[], 'deal_product', (select array_agg(c->>'key' order by ord) from jsonb_array_elements(public.export_columns('deal_product')->'columns') with ordinality x(c, ord))) as x) s \gset
select clock_timestamp() as t5b \gset
select (x->>'row_count') as t_a_rows, length(x::text) as t_a_bytes
from (select public.deal_export((select array_agg(id) from public.so_deal where name not like 'DRX-%'), 'deal_rule', (select array_agg(c->>'key' order by ord) from jsonb_array_elements(public.export_columns('deal_rule')->'columns') with ordinality x(c, ord))) as x) s \gset
select clock_timestamp() as t5c \gset
reset role;
select pg_temp.chk('T1 real active line deals: every active product row', :'t_b_rows', :'want_b_real');
select pg_temp.chk('T2 real deals: ⓐ rows = deals left join lines', :'t_a_rows', :'want_a_real');
select pg_temp.chk('T3 not truncated', :'t_b_trunc', 'false');
\echo '── 크기 · 시간(8 초 안이어야 · 문장이 섰다면 위에서 멈췄다)'
select :'t_b_rows' as b_rows, :'t_b_bytes' as b_bytes, (:'t5b'::timestamptz - :'t5a'::timestamptz) as b_time_all_columns, :'t_a_rows' as a_rows, :'t_a_bytes' as a_bytes, (:'t5c'::timestamptz - :'t5b'::timestamptz) as a_time;

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤)'
select (select count(*) from public.so_deal) = :n_deal as deal_same, (select count(*) from public.so_deal_line) = :n_line as line_same, (select count(*) from public.so_deal_target) = :n_target as target_same,
       (select count(*) from public.so_deal_tier) = :n_tier as tier_same, (select count(*) from public.so_deal_customer_rule) = :n_rule as rule_same, (select count(*) from public.product) = :n_prod as prod_same,
       (select count(*) from public.product_tag) = :n_tag as tag_same, (select count(*) from public.product_price) = :n_price as price_same, (select count(*) from public.ref_brand) = :n_brand as brand_same,
       (select count(*) from public.ref_category) = :n_cat as cat_same, (select count(*) from public.customer) = :n_cust as cust_same, (select count(*) from public.ims_staff) = :n_staff as staff_same,
       (select count(*) from public.so where reprice_suggested_at is not null) = :n_flag as flag_same;
