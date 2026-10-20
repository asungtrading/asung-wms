-- mrg-1-verify.sql — 합치기(so_merge)가 출처 · 딜을 그대로 싣는다(판정 548 · 433 · 484 · 묶기 열쇠 + discount_source · deal_line_id · 옛 결함 재현 · so_reprice 뒤 동작)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020130409_mrg_1_merge_keeps_discount_source.sql -f supabase/tests/mrg-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0(옛 함수로 결함 재현) · G0 는 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더
--   재료는 전부 가짜(직원 MRG1 둘 · 제품 MRG1-* · 손님 MRG1 CU_A(10 %) · CU_0(0 %) · 딜 셋 · 오더 SO-792xx) · 실제 행 무변(Z1) · rollback · so_merge 가 so_number_seq 를 당긴다 → 머리에서 읽고 되돌린다
--   흐름: 머리 → begin → 도우미 → M0 · M1 → [mig] S0(옛 so_merge: 10 % 줄 둘 → manual · 딜 줄 → deal_line_id 사라짐) · G0 → \i → G1 → S1 ~ S8 → Z1 → rollback → 시퀀스

\echo '── 시퀀스 · db_role · schema_migrations'
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select :so_seq_last as so_seq, :'so_seq_called' as so_seq_called, (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261020130409' \gset
select :n_applied as schema_migrations_rows_for_20261020130409;

begin;
set local statement_timeout = '300s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.run(p_sql text) returns text
  language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return v;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.pid(p_sku text) returns uuid language sql stable as $$ select id from public.product where sku = p_sku $$;
create function pg_temp.cid(p_name text) returns uuid language sql stable as $$ select id from public.customer where name = p_name $$;
create function pg_temp.sid(p_num text) returns uuid language sql stable as $$ select id from public.so where so_number = p_num $$;
create function pg_temp.did(p_name text) returns uuid language sql stable as $$ select id from public.so_deal where name = p_name $$;
create function pg_temp.who(p_au text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', p_au, 'role', 'authenticated')::text, true) $$;
-- 줄 지문: line_no:sku:qty:unit:pct:source:deal?:override:manual?:setter
create function pg_temp.lines_of(p_id uuid) returns text language plpgsql as $$
begin
  return (select coalesce(string_agg(l.line_no || ':' || l.sku || ':' || trim_scale(l.qty_ordered)::text || ':' || coalesce(trim_scale(l.unit_price)::text, '∅') || ':' || coalesce(trim_scale(l.discount_pct)::text, '∅') || ':' || coalesce(l.discount_source, '-')
                                     || ':' || case when l.deal_line_id is null then '-' else 'D' end || ':' || case when l.price_override then 'O' else '-' end || ':' || case when public.so_line_manual(l) then 'M' else 's' end
                                     || ':' || coalesce((select split_part(s.email, '@', 1) from public.ims_staff s where s.id = l.price_set_by), '-'), ' | ' order by l.line_no), '(none)')
          from public.so_line l where l.so_id = p_id);
end $$;
create function pg_temp.merge(p_a text, p_b text) returns text language plpgsql as $$
declare v text;
begin
  v := pg_temp.run(format('select public.so_merge(%L::uuid[], true)::text', array[pg_temp.sid(p_a), pg_temp.sid(p_b)]));
  return v;
end $$;
create function pg_temp.odeal(p_name text, p_from date, p_to date, p_customers text[], p_tiers jsonb) returns uuid
  language plpgsql as $$
declare v_d uuid; c text; t jsonb;
begin
  insert into public.so_deal (name, source, is_active, is_order_level, date_from, date_to) values (p_name, 'manual', false, true, p_from, p_to) returning id into v_d;
  foreach c in array p_customers loop insert into public.so_deal_customer_rule (deal_id, kind, target, customer_id) values (v_d, 'include', 'customer', pg_temp.cid(c)); end loop;
  for t in select * from jsonb_array_elements(p_tiers) loop
    insert into public.so_deal_tier (deal_id, tier_no, min_amount, pct, source) values (v_d, (t->>'n')::int, (t->>'min')::numeric, (t->>'pct')::numeric, 'manual');
  end loop;
  update public.so_deal set is_active = true where id = v_d;
  return v_d;
end $$;

\echo '── M0) 직원 둘 · 참조 · 실제 줄 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'mrg1-sa@test.invalid', 'MRG1 sales A', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as au_sa, id::text as st_sa \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'mrg1-sb@test.invalid', 'MRG1 sales B', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as au_sb, id::text as st_sb \gset
select id::text as tor from public.ref_warehouse where name = 'Asung Trading Inc.' and is_active \gset
select id::text as tier_w from public.ref_price_tier where name = 'Wholesale' and purpose = 'sale' and is_active \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as taxr from public.ref_tax_rule where name = 'HST ON (Sale)' \gset
select (public.ims_today() - 380)::text as day, public.ims_today()::text as today \gset
create temp table t_real_so as select s.id from public.so s;
create temp table t_real_lines as select l.id from public.so_line l;
select count(*) as n_real_lines, md5(coalesce(string_agg(l.id::text || ':' || l.qty_ordered || ':' || coalesce(l.unit_price::text, '') || ':' || coalesce(l.discount_source, '') || ':' || coalesce(l.deal_line_id::text, '') || ':' || l.price_override, '|' order by l.id), '')) as md5_real_lines from public.so_line l join t_real_lines t on t.id = l.id \gset
select count(*) as n_real_so, md5(coalesce(string_agg(s.id::text || ':' || s.status || ':' || coalesce(s.order_discount_pct::text, '') || ':' || coalesce(s.order_discount_source, ''), '|' order by s.id), '')) as md5_real_so from public.so s join t_real_so t on t.id = s.id \gset
select pg_temp.chk(format('M0 staff 2 · refs · fake day %s · today %s · %s real lines · %s real orders snapshotted', :'day', :'today', :n_real_lines, :n_real_so),
  :'au_sa' <> '' and :'au_sb' <> '' and :'tor' <> '' and :'tier_w' <> '' and :'cad' <> '' and :'taxr' <> '' and :n_real_so > 0, 'see M0');

\echo '── M1) 가짜 재료 — 제품(낱개 셋 · 콤보) · 손님 둘(10 % · 0 %) · 딜(오더 500/5 · 줄 딜 P2 8 %) · 오더 SO-79201 ~ 79218(짝수 번호 = 둘째 · 날짜 day + 1)'
insert into public.product (sku, name, source, is_active, sellable) values ('MRG1-P1', 'MRG1 P1 (100)', 'manual', true, true), ('MRG1-P2', 'MRG1 P2 (50)', 'manual', true, true), ('MRG1-P3', 'MRG1 P3 (10)', 'manual', true, true), ('MRG1-C', 'MRG1 combo (120)', 'manual', true, true);
insert into public.product_price (product_id, tier_id, price, source) values (pg_temp.pid('MRG1-P1'), :'tier_w'::uuid, 100.00, 'manual'), (pg_temp.pid('MRG1-P2'), :'tier_w'::uuid, 50.00, 'manual'), (pg_temp.pid('MRG1-P3'), :'tier_w'::uuid, 10.00, 'manual'), (pg_temp.pid('MRG1-C'), :'tier_w'::uuid, 120.00, 'manual');
insert into public.product_bom (parent_product_id, component_product_id, quantity, source) values (pg_temp.pid('MRG1-C'), pg_temp.pid('MRG1-P2'), 2, 'manual'), (pg_temp.pid('MRG1-C'), pg_temp.pid('MRG1-P3'), 1, 'manual');
insert into public.customer (name, source, is_active, currency_id, currency_code, price_tier, discount_pct, default_location_id, default_location_name) values
  ('MRG1 CU_A', 'manual', true, :'cad'::uuid, 'CAD', 'Wholesale', 10, :'tor'::uuid, 'Asung Trading Inc.'),
  ('MRG1 CU_0', 'manual', true, :'cad'::uuid, 'CAD', 'Wholesale', 0, :'tor'::uuid, 'Asung Trading Inc.');
select pg_temp.odeal('MRG1 D1 tiers 500/5', :'day'::date - 20, :'today'::date + 20, array['MRG1 CU_A', 'MRG1 CU_0'], '[{"n":1,"min":500,"pct":5}]') as _ \gset
insert into public.so_deal (name, source, is_active, is_order_level, date_from, date_to) values ('MRG1 L1 line deal P2 8', 'manual', false, false, :'day'::date - 20, :'today'::date + 20);
insert into public.so_deal_customer_rule (deal_id, kind, target, customer_id) values (pg_temp.did('MRG1 L1 line deal P2 8'), 'include', 'customer', pg_temp.cid('MRG1 CU_0'));
insert into public.so_deal_line (deal_id, line_no, pct, min_qty_mode, source) values (pg_temp.did('MRG1 L1 line deal P2 8'), 1, 8, 'none', 'manual');
insert into public.so_deal_target (line_id, kind, target, product_id, source) values ((select id from public.so_deal_line where deal_id = pg_temp.did('MRG1 L1 line deal P2 8')), 'include', 'product', pg_temp.pid('MRG1-P2'), 'manual');
update public.so_deal set is_active = true where name = 'MRG1 L1 line deal P2 8';
select id::text as dl from public.so_deal_line where deal_id = pg_temp.did('MRG1 L1 line deal P2 8') \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, price_tier_id, price_tier, discount_pct, location_id, tax_rule_id, tax_rule, order_date)
select 'SO-792' || lpad(g::text, 2, '0'), case when g in (5, 6, 7, 8) then pg_temp.cid('MRG1 CU_0') else pg_temp.cid('MRG1 CU_A') end, 'warehouse', case when g = 13 then 'shopify' else 'manual' end, :'cad'::uuid, 'draft', :'tier_w'::uuid, 'Wholesale',
       case when g in (5, 6, 7, 8) then 0 else 10 end, :'tor'::uuid, :'taxr'::uuid, 'HST ON (Sale)', case when g % 2 = 0 then :'day'::date + 1 else :'day'::date end
from generate_series(1, 18) g;
select pg_temp.chk('M1 fixtures: 4 products (combo with 2 components) · prices · CU_A 10 % · CU_0 0 % · order deal 500/5 (period reaches today) · line deal P2 8 % for CU_0 · 18 draft orders (SO-79213 shopify · CU_0 = 05 ~ 08)',
  (select count(*) from public.product where sku like 'MRG1-%') = 4 and public.so_combo_is(pg_temp.pid('MRG1-C')) and (select count(*) from public.so where so_number like 'SO-792%') = 18 and :'dl' <> ''
  and (select intake from public.so where so_number = 'SO-79213') = 'shopify', 'see M1');

select pg_temp.who(:'au_sa') as claims;
-- 줄 재료(so_line_add · 가짜 오더) — 홀수 = 첫 원본 · 짝수 = 둘째
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 3)::text', pg_temp.sid('SO-79201'), pg_temp.pid('MRG1-P1'))) as _1 \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 3)::text', pg_temp.sid('SO-79202'), pg_temp.pid('MRG1-P1'))) as _2 \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 2)::text', pg_temp.sid('SO-79205'), pg_temp.pid('MRG1-P2'))) as _5 \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 4)::text', pg_temp.sid('SO-79206'), pg_temp.pid('MRG1-P2'))) as _6 \gset
select pg_temp.chk('M2 lines: SO-79201/02 P1×3 customer 10 % (unit 90) · SO-79205/06 P2×2/×4 deal 8 % (unit 46 · deal_line_id)',
  pg_temp.lines_of(pg_temp.sid('SO-79201')) = '1:MRG1-P1:3:90:10:customer:-:-:s:-' and pg_temp.lines_of(pg_temp.sid('SO-79202')) = '1:MRG1-P1:3:90:10:customer:-:-:s:-'
  and pg_temp.lines_of(pg_temp.sid('SO-79205')) = '1:MRG1-P2:2:46:8:deal:D:-:s:-' and pg_temp.lines_of(pg_temp.sid('SO-79206')) = '1:MRG1-P2:4:46:8:deal:D:-:s:-'
  and (select deal_line_id::text from public.so_line where so_id = pg_temp.sid('SO-79205')) = :'dl',
  format('%s | %s | %s', pg_temp.lines_of(pg_temp.sid('SO-79201')), pg_temp.lines_of(pg_temp.sid('SO-79205')), left(:'_5', 160)));

\if :{?mig}
\echo '── S0) 옛 so_merge 로 결함 재현 — 10 % 줄 둘 → manual · 딜 줄 둘 → manual + 딜 연결 없음'
select pg_temp.merge('SO-79201', 'SO-79202') as m0a \gset
select pg_temp.j(:'m0a')->>'so_number' as n0a \gset
select pg_temp.merge('SO-79205', 'SO-79206') as m0b \gset
select pg_temp.j(:'m0b')->>'so_number' as n0b \gset
select pg_temp.chk('S0 (old function · trial only) merged P1×6 is source manual · so_line_manual true · no setter — merged P2×6 is manual · deal_line_id gone · plan discount_source manual',
  :'m0a' not like 'ERR%' and pg_temp.lines_of(pg_temp.sid(:'n0a')) = '1:MRG1-P1:6:90:10:manual:-:-:M:-'
  and :'m0b' not like 'ERR%' and pg_temp.lines_of(pg_temp.sid(:'n0b')) = '1:MRG1-P2:6:46:8:manual:-:-:M:-' and (pg_temp.j(:'m0b')->'lines'->0->>'discount_source') = 'manual',
  format('%s | %s', pg_temp.lines_of(pg_temp.sid(:'n0a')), pg_temp.lines_of(pg_temp.sid(:'n0b'))));
-- 재료를 다시(합쳐진 원본은 cancelled/merged · 새 오더 둘)
select pg_temp.chk('G0 before the trial: so_merge still has the old expression · not in schema_migrations', (select prosrc from pg_proc where oid = 'public.so_merge(uuid[], boolean)'::regprocedure) ~ 'when x\.discount_pct is not null then ''manual''' and :n_applied = 0, format('n_applied %s', :n_applied));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 3)::text', pg_temp.sid('SO-79203'), pg_temp.pid('MRG1-P1'))) as _3 \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 3)::text', pg_temp.sid('SO-79204'), pg_temp.pid('MRG1-P1'))) as _4 \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 2)::text', pg_temp.sid('SO-79207'), pg_temp.pid('MRG1-P2'))) as _7 \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 4)::text', pg_temp.sid('SO-79208'), pg_temp.pid('MRG1-P2'))) as _8 \gset
select 'SO-79203' as a1, 'SO-79204' as a2, 'SO-79207' as b1, 'SO-79208' as b2 \gset
\else
select pg_temp.chk('P0c confirm run: migration 20261020130409 applied', :n_applied = 1, format('%s rows', :n_applied));
select 'SO-79201' as a1, 'SO-79202' as a2, 'SO-79205' as b1, 'SO-79206' as b2 \gset
\endif

\echo '── G1) 실물'
select pg_temp.chk('G1 so_merge: old expression gone · plan carries x.discount_source + x.deal_line_id · group by 12 · insert deal_line_id · differs_in has deal · no other function has the old expression · comment says 548',
  (select prosrc !~ 'when x\.discount_pct is not null then ''manual''' and prosrc ~ '''discount_source'', x\.discount_source, ''deal_line_id'', x\.deal_line_id' and prosrc ~ 'group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12' and prosrc ~ '\(e->>''deal_line_id''\)::uuid' and prosrc ~ 'then ''deal'' end'
     from pg_proc where oid = 'public.so_merge(uuid[], boolean)'::regprocedure)
  and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prosrc ~ 'when x\.discount_pct is not null then ''manual''') = 0
  and obj_description('public.so_merge(uuid[], boolean)'::regprocedure, 'pg_proc') like '%548%', 'see G1');

\echo '── S1) 손님 10 % 줄 둘 → customer · manual false · 오더 할인이 그 줄에 걸린다(540 ≥ 500 → 5 % · so_tax_preview)'
select pg_temp.merge(:'a1', :'a2') as m1 \gset
select pg_temp.j(:'m1')->>'so_number' as n1 \gset
select pg_temp.lines_of(pg_temp.sid(:'n1')) as l1 \gset
select public.so_tax_preview(pg_temp.sid(:'n1'))::text as t1 \gset
select pg_temp.chk('S1 merged P1×6 @90: source customer · deal none · not manual · no setter · plan line discount_source customer · kept_apart false — order 540 → D1 5 % · basis 540 · order_discount_amount −27 · line manual false in so_tax_preview',
  :'m1' not like 'ERR%' and :'l1' = '1:MRG1-P1:6:90:10:customer:-:-:s:-'
  and (pg_temp.j(:'m1')->'lines'->0->>'discount_source') = 'customer' and not (pg_temp.j(:'m1')->'lines'->0->>'kept_apart')::boolean
  and (select order_discount_pct = 5 and order_discount_source = 'deal' from public.so where id = pg_temp.sid(:'n1'))
  and (pg_temp.j(:'t1')->'order_discount'->>'basis')::numeric = 540 and (pg_temp.j(:'t1')->'totals'->>'order_discount_amount')::numeric = -27
  and not (pg_temp.j(:'t1')->'lines'->0->>'manual')::boolean,
  format('%s | %s | %s', :'l1', left((pg_temp.j(:'m1')->'lines'->0)::text, 300), left((pg_temp.j(:'t1')->'totals')::text, 200)));

\echo '── S2) 딜 줄 둘 → deal · deal_line_id 원본 그대로'
select pg_temp.merge(:'b1', :'b2') as m2 \gset
select pg_temp.j(:'m2')->>'so_number' as n2 \gset
select pg_temp.chk('S2 merged P2×6 @46: source deal · deal_line_id = the line deal · not manual · plan deal_line_id too',
  :'m2' not like 'ERR%' and pg_temp.lines_of(pg_temp.sid(:'n2')) = '1:MRG1-P2:6:46:8:deal:D:-:s:-'
  and (select deal_line_id::text from public.so_line where so_id = pg_temp.sid(:'n2')) = :'dl' and (pg_temp.j(:'m2')->'lines'->0->>'deal_line_id') = :'dl',
  format('%s | %s', pg_temp.lines_of(pg_temp.sid(:'n2')), left((pg_temp.j(:'m2')->'lines'->0)::text, 300)));

\echo '── S3) 0 % customer 줄 둘(CU_0 · P3) → customer 0'
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 1)::text', pg_temp.sid('SO-79209'), pg_temp.pid('MRG1-P3'))) as _9 \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 2)::text', pg_temp.sid('SO-79210'), pg_temp.pid('MRG1-P3'))) as _10 \gset
update public.so set customer_id = pg_temp.cid('MRG1 CU_0'), discount_pct = 0 where so_number in ('SO-79209', 'SO-79210');
select pg_temp.run(format('select public.so_line_requote(%L::uuid, 1)::text', (select id from public.so_line where so_id = pg_temp.sid('SO-79209')))) as _9r \gset
select pg_temp.run(format('select public.so_line_requote(%L::uuid, 2)::text', (select id from public.so_line where so_id = pg_temp.sid('SO-79210')))) as _10r \gset
select pg_temp.merge('SO-79209', 'SO-79210') as m3 \gset
select pg_temp.j(:'m3')->>'so_number' as n3 \gset
select pg_temp.chk('S3 (CU_0) merged P3×3 @10: discount 0 · source customer · not manual',
  :'m3' not like 'ERR%' and pg_temp.lines_of(pg_temp.sid(:'n3')) = '1:MRG1-P3:3:10:0:customer:-:-:s:-', format('%s | %s | %s', pg_temp.lines_of(pg_temp.sid('SO-79209')), pg_temp.lines_of(pg_temp.sid(:'n3')), left(:'m3', 120)));

\echo '── S4) 손 단가 둘(SA · SB) · 손 할인 둘 → 지금 그대로(override · manual · 첫 원본의 setter)'
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 2, 80)::text', pg_temp.sid('SO-79211'), pg_temp.pid('MRG1-P1'))) as _11 \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 1, null, 15)::text', pg_temp.sid('SO-79211'), pg_temp.pid('MRG1-P3'))) as _11b \gset
select pg_temp.who(:'au_sb') as claims;
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 1, 80)::text', pg_temp.sid('SO-79212'), pg_temp.pid('MRG1-P1'))) as _12 \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 2, null, 15)::text', pg_temp.sid('SO-79212'), pg_temp.pid('MRG1-P3'))) as _12b \gset
select pg_temp.who(:'au_sa') as claims;
select pg_temp.merge('SO-79211', 'SO-79212') as m4 \gset
select pg_temp.j(:'m4')->>'so_number' as n4 \gset
select pg_temp.chk('S4 merged: P1×3 @80 override · null source · setter SA (first original) — P3×3 15 % manual · setter SA — both so_line_manual true',
  :'m4' not like 'ERR%' and pg_temp.lines_of(pg_temp.sid(:'n4')) = '1:MRG1-P1:3:80:∅:-:-:O:M:mrg1-sa | 2:MRG1-P3:3:8.5:15:manual:-:-:M:mrg1-sa', format('%s | %s', pg_temp.lines_of(pg_temp.sid(:'n4')), left(:'m4', 120)));

\echo '── S5) 같은 제품 · 같은 단가 · 출처 다름(customer 10 % vs 손 할인 10 %) → 따로 줄 · kept_apart · differs_in discount_source'
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 2)::text', pg_temp.sid('SO-79215'), pg_temp.pid('MRG1-P1'))) as _15 \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 1, null, 10)::text', pg_temp.sid('SO-79216'), pg_temp.pid('MRG1-P1'))) as _16 \gset
select pg_temp.run(format('select public.so_merge(%L::uuid[], false)::text', array[pg_temp.sid('SO-79215'), pg_temp.sid('SO-79216')])) as p5 \gset
select pg_temp.merge('SO-79215', 'SO-79216') as m5 \gset
select pg_temp.j(:'m5')->>'so_number' as n5 \gset
select pg_temp.chk('S5 two lines kept apart: P1×2 @90 customer (system) · P1×1 @90 manual (setter SA) · preview plan = saved plan · differs_in of line 2 contains discount_source (not unit_price)',
  :'m5' not like 'ERR%' and pg_temp.lines_of(pg_temp.sid(:'n5')) = '1:MRG1-P1:2:90:10:customer:-:-:s:- | 2:MRG1-P1:1:90:10:manual:-:-:M:mrg1-sa'
  and (pg_temp.j(:'p5')->'lines') = (pg_temp.j(:'m5')->'lines')
  and (pg_temp.j(:'m5')->'lines'->1->>'kept_apart')::boolean and (pg_temp.j(:'m5')->'lines'->1->'differs_in') ? 'discount_source' and not ((pg_temp.j(:'m5')->'lines'->1->'differs_in') ? 'unit_price'),
  format('%s | %s', pg_temp.lines_of(pg_temp.sid(:'n5')), left((pg_temp.j(:'m5')->'lines')::text, 500)));

\echo '── S6) shopify 줄(intake shopify 오더)이 든 합치기 — 받는다 · shopify 그대로(판정 433) · 손님 줄과 따로'
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 2, 85)::text', pg_temp.sid('SO-79213'), pg_temp.pid('MRG1-P1'))) as _13 \gset
select pg_temp.run(format('select public.so_line_set_shopify(%L::uuid, 100, 15)::text', (select id from public.so_line where so_id = pg_temp.sid('SO-79213')))) as _13s \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 1)::text', pg_temp.sid('SO-79214'), pg_temp.pid('MRG1-P1'))) as _14 \gset
select pg_temp.merge('SO-79213', 'SO-79214') as m6 \gset
select pg_temp.j(:'m6')->>'so_number' as n6 \gset
select pg_temp.chk('S6 so_merge accepts the shopify-intake order (channel warehouse) · merged: P1×2 @85 15 % shopify (M · override false) · P1×1 @90 customer — kept apart (unit_price · discount_source)',
  :'_13s' not like 'ERR%' and :'m6' not like 'ERR%' and pg_temp.lines_of(pg_temp.sid(:'n6')) = '1:MRG1-P1:2:85:15:shopify:-:-:M:mrg1-sa | 2:MRG1-P1:1:90:10:customer:-:-:s:-',
  format('%s | %s | %s', left(:'_13s', 100), pg_temp.lines_of(pg_temp.sid(:'n6')), left(:'m6', 120)));

\echo '── S7) 콤보 줄 · 구성품 줄 — 지금 동작 그대로(합친 콤보 ×3 · 구성품 다시 매달림 · 값 0 · 출처 없음)'
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 1)::text', pg_temp.sid('SO-79217'), pg_temp.pid('MRG1-C'))) as _17 \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 2)::text', pg_temp.sid('SO-79218'), pg_temp.pid('MRG1-C'))) as _18 \gset
select pg_temp.merge('SO-79217', 'SO-79218') as m7 \gset
select pg_temp.j(:'m7')->>'so_number' as n7 \gset
select pg_temp.chk('S7 merged combo ×3 @108 customer 10 % (system) · components P2×6 · P3×3 at 0 · no source · attached to the merged combo line · component_lines 2',
  :'m7' not like 'ERR%' and pg_temp.lines_of(pg_temp.sid(:'n7')) = '1:MRG1-C:3:108:10:customer:-:-:s:- | 2:MRG1-P2:6:0:∅:-:-:-:s:- | 3:MRG1-P3:3:0:∅:-:-:-:s:-'
  and (select bool_and(c.combo_line_id = (select p.id from public.so_line p where p.so_id = pg_temp.sid(:'n7') and p.sku = 'MRG1-C')) from public.so_line c where c.so_id = pg_temp.sid(:'n7') and c.sku <> 'MRG1-C')
  and (pg_temp.j(:'m7')->>'component_lines')::int = 2, format('%s | %s', pg_temp.lines_of(pg_temp.sid(:'n7')), left(:'m7', 160)));

\echo '── S8) 합친 뒤 so_reprice(판정 548) — 시스템 줄은 다시 매겨진다(kept false) · 손 줄 · shopify 줄은 kept'
select public.so_reprice(pg_temp.sid(:'n1'))::text as r1 \gset
select public.so_reprice(pg_temp.sid(:'n4'))::text as r4 \gset
select public.so_reprice(pg_temp.sid(:'n6'))::text as r6 \gset
select pg_temp.chk('S8 so_reprice: merged customer line kept false (requoted · still 10 % customer @90) — manual override and manual 15 % lines kept true — shopify line kept true · customer line beside it kept false',
  (select bool_and(not (e->>'kept')::boolean) from jsonb_array_elements(pg_temp.j(:'r1')->'lines') e) and pg_temp.lines_of(pg_temp.sid(:'n1')) = '1:MRG1-P1:6:90:10:customer:-:-:s:-'
  and (select bool_and((e->>'kept')::boolean) from jsonb_array_elements(pg_temp.j(:'r4')->'lines') e)
  and (select (e->>'kept')::boolean from jsonb_array_elements(pg_temp.j(:'r6')->'lines') e where e->>'sku' = 'MRG1-P1' and (e->>'line_no')::int = 1) and (select not (e->>'kept')::boolean from jsonb_array_elements(pg_temp.j(:'r6')->'lines') e where (e->>'line_no')::int = 2),
  format('%s | %s | %s', left((pg_temp.j(:'r1')->'lines')::text, 200), left((pg_temp.j(:'r4')->'lines')::text, 200), left((pg_temp.j(:'r6')->'lines')::text, 300)));

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk(format('Z1 %s real lines and %s real orders (the rows that existed at the snapshot — orders another session adds meanwhile are not counted) untouched (md5 of qty · price · source · deal · override · status · discount)', :n_real_lines, :n_real_so),
  (select md5(coalesce(string_agg(l.id::text || ':' || l.qty_ordered || ':' || coalesce(l.unit_price::text, '') || ':' || coalesce(l.discount_source, '') || ':' || coalesce(l.deal_line_id::text, '') || ':' || l.price_override, '|' order by l.id), '')) from public.so_line l join t_real_lines t on t.id = l.id) = :'md5_real_lines'
  and (select md5(coalesce(string_agg(s.id::text || ':' || s.status || ':' || coalesce(s.order_discount_pct::text, '') || ':' || coalesce(s.order_discount_source, ''), '|' order by s.id), '')) from public.so s join t_real_so t on t.id = s.id) = :'md5_real_so',
  format('real so now %s (snapshot %s) · real lines now %s (snapshot %s) · so md5 same %s · lines md5 same %s',
    (select count(*) from public.so s join t_real_so t on t.id = s.id), :n_real_so,
    (select count(*) from public.so_line l join t_real_lines t on t.id = l.id), :n_real_lines,
    (select md5(coalesce(string_agg(s.id::text || ':' || s.status || ':' || coalesce(s.order_discount_pct::text, '') || ':' || coalesce(s.order_discount_source, ''), '|' order by s.id), '')) from public.so s join t_real_so t on t.id = s.id) = :'md5_real_so',
    (select md5(coalesce(string_agg(l.id::text || ':' || l.qty_ordered || ':' || coalesce(l.unit_price::text, '') || ':' || coalesce(l.discount_source, '') || ':' || coalesce(l.deal_line_id::text, '') || ':' || l.price_override, '|' order by l.id), '')) from public.so_line l join t_real_lines t on t.id = l.id) = :'md5_real_lines'));

rollback;
\echo '── rollback 뒤 — 시퀀스(so 는 greatest(실제 최대, 머리) 로 되돌림) · 가짜 흔적 0'
select setval('public.so_number_seq', greatest(:so_seq_last, (select max(substring(so_number from 4 for 5)::int) from public.so where so_number ~ '^SO-[0-9]{5}')), :'so_seq_called'::boolean) as so_seq_restored;
select (select last_value from public.so_number_seq) as so_seq_now, :so_seq_last as so_seq_head,
       (select count(*) from public.product where sku like 'MRG1-%') + (select count(*) from public.customer where name like 'MRG1 %') + (select count(*) from public.so where so_number like 'SO-792%') + (select count(*) from public.ims_staff where email like 'mrg1-%') + (select count(*) from public.so_deal where name like 'MRG1 %') as fake_traces_left;
