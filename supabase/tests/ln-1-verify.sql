-- ln-1 검증 — 20261020123910_ln_1_paste_price_lines_clear_price_set_by.sql (판정 532 · 541 ~ 546 · 붙여넣기 가격 · so_lines_clear · price_set_by/at)
--   시험 적용 + 검증(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020123910_ln_1_paste_price_lines_clear_price_set_by.sql -f ~/asung/prompts/ln-1-verify.sql
--   확인 실행(Caleb · 적용 뒤):          cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -f ~/asung/prompts/ln-1-verify.sql
--   ⚠️ 재료는 전부 가짜(직원 LN1 셋 · 제품 LN1-* · 손님 LN1 CU_A · 오더 SO-791xx · 딜 LN1 둘 · 쿠폰 LN1COUPON) · 가짜 「오늘」= 실제 오늘 − 380 일 · 실제 행 무접촉(Z1) · rollback
--   흐름: 머리 → begin → 도우미 → M0(직원 · 참조 · 실제 줄 스냅샷) → M1 가짜 재료 → [mig] 적용 전 paste 반환 \gset · G0 → \i → G1 → S1 ~ S9 → Z1 → rollback → 시퀀스

\echo '── 시퀀스 · db_role · schema_migrations'
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select :so_seq_last as so_seq, :'so_seq_called' as so_seq_called, (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261020123910' \gset
select :n_applied as schema_migrations_rows_for_20261020123910;

begin;
set local statement_timeout = '300s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.attempt(p_sql text) returns text
  language plpgsql security invoker as $$
begin
  begin
    execute p_sql;
    raise exception using errcode = 'ZZ999', message = '__undo__';
  exception when others then
    if sqlstate = 'ZZ999' then return 'no error'; end if;
    return sqlstate || ' ' || sqlerrm;
  end;
end $$;
-- 되돌리지 않는 호출(결과 글 · 오류면 ERR) — \gset 으로 받아 다음 문장에서 판정(쓰기와 상태 읽기를 한 문장에 두지 않는다)
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
create function pg_temp.ln(p_sku text, p_qty text, p_price text default null) returns jsonb language sql immutable as $$
  select case when p_price is null then jsonb_build_object('sku', p_sku, 'qty', p_qty) else jsonb_build_object('sku', p_sku, 'qty', p_qty, 'price', p_price) end $$;
-- 오더 줄 지문: line_no:sku:qty:unit:override:source:setter(이메일 머리)
create function pg_temp.lines_of(p_num text) returns text language plpgsql as $$
begin
  return (select coalesce(string_agg(l.line_no || ':' || l.sku || ':' || trim_scale(l.qty_ordered)::text || ':' || coalesce(trim_scale(l.unit_price)::text, '∅') || ':' || case when l.price_override then 'O' else '-' end || ':' || coalesce(l.discount_source, '-')
                                     || ':' || coalesce((select split_part(s.email, '@', 1) from public.ims_staff s where s.id = l.price_set_by), '-'), ' | ' order by l.line_no), '(none)')
          from public.so_line l where l.so_id = pg_temp.sid(p_num));
end $$;
create function pg_temp.od(p_num text) returns text language sql stable as $$
  select concat_ws('|', coalesce(s.order_discount_pct::text, 'null'), coalesce(s.order_discount_source, 'null'), case when s.coupon_id is null then 'nocoupon' else 'coupon' end) from public.so s where s.so_number = p_num $$;
create function pg_temp.odeal(p_name text, p_from date, p_to date, p_customers text[], p_tiers jsonb, p_coupon boolean) returns uuid
  language plpgsql as $$
declare v_d uuid; c text; t jsonb;
begin
  insert into public.so_deal (name, source, is_active, is_order_level, date_from, date_to, coupon_required) values (p_name, 'manual', false, true, p_from, p_to, p_coupon) returning id into v_d;
  foreach c in array p_customers loop
    insert into public.so_deal_customer_rule (deal_id, kind, target, customer_id) values (v_d, 'include', 'customer', pg_temp.cid(c));
  end loop;
  for t in select * from jsonb_array_elements(p_tiers) loop
    insert into public.so_deal_tier (deal_id, tier_no, min_amount, pct, source) values (v_d, (t->>'n')::int, (t->>'min')::numeric, (t->>'pct')::numeric, 'manual');
  end loop;
  update public.so_deal set is_active = true where id = v_d;
  return v_d;
end $$;

\echo '── M0) 직원 셋 · 참조 · 실제 줄 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'ln1-sa@test.invalid', 'LN1 sales A', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as au_sa, id::text as st_sa \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'ln1-sb@test.invalid', 'LN1 sales B', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as au_sb, id::text as st_sb \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'ln1-w@test.invalid', 'LN1 worker (no sales)', 'worker', '["ims"]', '{}') returning auth_user_id::text as au_w, id::text as st_w \gset
select id::text as tor from public.ref_warehouse where name = 'Asung Trading Inc.' and is_active \gset
select id::text as tier_w from public.ref_price_tier where name = 'Wholesale' and purpose = 'sale' and is_active \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as taxr from public.ref_tax_rule where name = 'HST ON (Sale)' \gset
select (public.ims_today() - 380)::text as day \gset
select count(*) as n_real_lines, md5(coalesce(string_agg(l.id::text || ':' || l.qty_ordered || ':' || coalesce(l.unit_price::text, '') || ':' || l.price_override || ':' || coalesce(l.discount_source, ''), '|' order by l.id), '')) as md5_real_lines from public.so_line l \gset
select count(*) as n_real_so, md5(coalesce(string_agg(s.id::text || ':' || s.status || ':' || coalesce(s.order_discount_pct::text, '') || ':' || coalesce(s.order_discount_source, '') || ':' || coalesce(s.coupon_id::text, ''), '|' order by s.id), '')) as md5_real_so from public.so s \gset
select pg_temp.chk(format('M0 staff 3 · refs · fake day %s · %s real lines · %s real orders snapshotted', :'day', :n_real_lines, :n_real_so),
  :'au_sa' <> '' and :'au_sb' <> '' and :'au_w' <> '' and :'tor' <> '' and :'tier_w' <> '' and :'cad' <> '' and :'taxr' <> '' and :n_real_so > 0, 'see M0');

\echo '── M1) 가짜 재료 — 제품(낱개 셋 · 안 파는 세트 · 콤보) · 손님 · 딜 둘(문턱 · 쿠폰) · 쿠폰 · 오더'
insert into public.product (sku, name, source, is_active, sellable) values ('LN1-P1', 'LN1 base P1 (100)', 'manual', true, true), ('LN1-P2', 'LN1 base P2 (50)', 'manual', true, true), ('LN1-P3', 'LN1 base P3 (10)', 'manual', true, true), ('LN1-C', 'LN1 combo (120)', 'manual', true, true);
insert into public.product (sku, name, source, is_active, parent_product_id, pack_factor, sellable) values ('LN1-P1-6', 'LN1 set of 6 (not sold as set)', 'manual', true, pg_temp.pid('LN1-P1'), 6, false);
update public.product set sellable = false where sku = 'LN1-P1-6';
insert into public.product_price (product_id, tier_id, price, source) values (pg_temp.pid('LN1-P1'), :'tier_w'::uuid, 100.00, 'manual'), (pg_temp.pid('LN1-P2'), :'tier_w'::uuid, 50.00, 'manual'), (pg_temp.pid('LN1-P3'), :'tier_w'::uuid, 10.00, 'manual'), (pg_temp.pid('LN1-C'), :'tier_w'::uuid, 120.00, 'manual');
insert into public.product_bom (parent_product_id, component_product_id, quantity, source) values (pg_temp.pid('LN1-C'), pg_temp.pid('LN1-P2'), 2, 'manual'), (pg_temp.pid('LN1-C'), pg_temp.pid('LN1-P3'), 1, 'manual');
insert into public.customer (name, source, is_active, currency_id, currency_code, price_tier, discount_pct, default_location_id, default_location_name) values
  ('LN1 CU_A', 'manual', true, :'cad'::uuid, 'CAD', 'Wholesale', 0, :'tor'::uuid, 'Asung Trading Inc.');
select pg_temp.odeal('LN1 D1 tiers 500/5 1000/7', :'day'::date - 20, :'day'::date + 20, array['LN1 CU_A'], '[{"n":1,"min":500,"pct":5},{"n":2,"min":1000,"pct":7}]', false) as _ \gset
select pg_temp.odeal('LN1 DC coupon 10 min 100', :'day'::date - 20, :'day'::date + 20, array['LN1 CU_A'], '[{"n":1,"min":100,"pct":10}]', true) as _ \gset
insert into public.so_coupon (code, code_key, deal_id, customer_id) values ('LN1COUPON', public.so_coupon_key('LN1COUPON'), pg_temp.did('LN1 DC coupon 10 min 100'), pg_temp.cid('LN1 CU_A'));
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, price_tier_id, price_tier, discount_pct, location_id, tax_rule_id, tax_rule, order_date)
select 'SO-791' || lpad(g::text, 2, '0'), pg_temp.cid('LN1 CU_A'), 'warehouse', case when g = 7 then 'shopify' when g = 8 then 'pos' else 'manual' end, :'cad'::uuid, 'draft', :'tier_w'::uuid, 'Wholesale', 0, :'tor'::uuid, :'taxr'::uuid, 'HST ON (Sale)', case when g = 10 then :'day'::date - 3 else :'day'::date end
from generate_series(1, 11) g;
select pg_temp.chk('M1 fixtures: 5 products (set LN1-P1-6 not sellable · combo LN1-C with 2 components) · prices · customer · 2 deals · coupon · 11 draft orders (SO-79107 shopify · SO-79108 pos · SO-79110 three days older)',
  (select count(*) from public.product where sku like 'LN1-%') = 5 and (select not sellable and parent_product_id = pg_temp.pid('LN1-P1') from public.product where sku = 'LN1-P1-6')
  and public.so_combo_is(pg_temp.pid('LN1-C')) and (select count(*) from public.so where so_number like 'SO-791%') = 11
  and (select intake from public.so where so_number = 'SO-79107') = 'shopify' and (select intake from public.so where so_number = 'SO-79108') = 'pos'
  and (select count(*) from public.so_coupon where code = 'LN1COUPON') = 1, 'see M1');

select pg_temp.who(:'au_sa') as claims;
\if :{?mig}
\echo '── 적용 전 — 가격 없는 붙여넣기 반환(S4 에서 견준다) · G0'
select public.so_lines_paste(pg_temp.sid('SO-79102'), jsonb_build_array(pg_temp.ln('LN1-P1', '3'), pg_temp.ln('LN1-P2', '2'), pg_temp.ln('NOPE-1', '1'), pg_temp.ln('LN1-P1', 'x'), pg_temp.ln('ln1-p3', '4')), false)::text as paste_pre \gset
select pg_temp.chk('G0 before the trial: so_line has no price_set_by/at · no so_lines_clear · so_lines_paste knows no price · migration not in schema_migrations',
  not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so_line' and column_name in ('price_set_by', 'price_set_at'))
  and to_regprocedure('public.so_lines_clear(uuid, boolean)') is null
  and (select prosrc from pg_proc where oid = 'public.so_lines_paste(uuid, jsonb, boolean)'::regprocedure) !~ 'set_price_refused'
  and :n_applied = 0, format('n_applied %s', :n_applied));
\echo '── \i 시험 적용'
\i :mig
\else
select pg_temp.chk('P0c confirm run: migration 20261020123910 applied', :n_applied = 1, format('%s rows', :n_applied));
select public.so_lines_paste(pg_temp.sid('SO-79102'), jsonb_build_array(pg_temp.ln('LN1-P1', '3'), pg_temp.ln('LN1-P2', '2'), pg_temp.ln('NOPE-1', '1'), pg_temp.ln('LN1-P1', 'x'), pg_temp.ln('ln1-p3', '4')), false)::text as paste_pre \gset
\endif

\echo '── G1) 실물'
select pg_temp.chk('G1 columns price_set_by (fk ims_staff) · price_set_at · pair CHECK · so_lines_clear (authenticated · not anon · definer) · so_lines_paste · so_line_add · so_line_update · so_detail · so_split · so_merge bodies carry the new lines · so_reprice kept line present',
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_line' and column_name in ('price_set_by', 'price_set_at')) = 2
  and exists (select 1 from pg_constraint where conrelid = 'public.so_line'::regclass and conname = 'so_line_price_set_pair_ck')
  and exists (select 1 from pg_constraint where conrelid = 'public.so_line'::regclass and contype = 'f' and confrelid = 'public.ims_staff'::regclass and conkey = array[(select attnum from pg_attribute where attrelid = 'public.so_line'::regclass and attname = 'price_set_by')])
  and (select p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') from pg_proc p where p.oid = to_regprocedure('public.so_lines_clear(uuid, boolean)'))
  and (select prosrc from pg_proc where oid = 'public.so_lines_paste(uuid, jsonb, boolean)'::regprocedure) ~ 'set_price_refused'
  and (select prosrc from pg_proc where oid = 'public.so_line_add(uuid, uuid, numeric, numeric, numeric, text, text, boolean)'::regprocedure) ~ 'case when v_manual then v_staff end'
  and (select prosrc from pg_proc where oid = 'public.so_line_update(uuid, jsonb)'::regprocedure) ~ 'price_set_by     = v_pset_by'
  and (select prosrc from pg_proc where oid = 'public.so_detail(uuid)'::regprocedure) ~ 'price_set_by_name'
  and (select prosrc from pg_proc where oid = 'public.so_split(uuid, text, jsonb, text, uuid)'::regprocedure) ~ 'l\.price_set_by, l\.price_set_at'
  and (select prosrc from pg_proc where oid = 'public.so_merge(uuid[], boolean)'::regprocedure) ~ 'price_set_by'
  and (select prosrc from pg_proc where oid = 'public.so_reprice(uuid)'::regprocedure) ~ 'if l\.price_override or l\.discount_source in \(''manual'', ''shopify''\) then', 'see G1');

\echo '── S1) 가격 줄 → 새 줄(override · 출처 없음 · 딜 없음 · setter = SA) · 오더 할인 몫 0 · 문턱 합계에는 든다'
select pg_temp.run(format('select public.so_lines_paste(%L::uuid, %L::jsonb, true)::text', pg_temp.sid('SO-79101'), jsonb_build_array(pg_temp.ln('LN1-P1', '4', '90')))) as r1 \gset
select pg_temp.lines_of('SO-79101') as l1a, pg_temp.od('SO-79101') as od1a \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 4)::text', pg_temp.sid('SO-79101'), pg_temp.pid('LN1-P2'))) as a1 \gset
select pg_temp.lines_of('SO-79101') as l1b, pg_temp.od('SO-79101') as od1b \gset
select public.so_detail(pg_temp.sid('SO-79101'))::text as d1 \gset
select pg_temp.chk('S1 paste P1×4 @90: summary ok 1 · priced 1 · inserted 1 · row price_source paste · line 1:P1:4:90:O:-:ln1-sa (list 100 · discount null · deal null · price_set_at set) · 360 < 500 → no discount · + system P2×4 (200) → 560 → D1 5% · basis 200 · amount 10 · so_detail price_set_by_name',
  (pg_temp.j(:'r1')->'summary'->>'ok')::int = 1 and (pg_temp.j(:'r1')->'summary'->>'priced')::int = 1 and (pg_temp.j(:'r1')->'summary'->>'inserted')::int = 1 and (pg_temp.j(:'r1')->'lines'->0->>'price_source') = 'paste' and (pg_temp.j(:'r1')->'lines'->0->>'line_no') = '1'
  and :'l1a' = '1:LN1-P1:4:90:O:-:ln1-sa'
  and (select l.list_price = 100 and l.discount_pct is null and l.discount_source is null and l.deal_line_id is null and l.price_set_at is not null and l.price_set_by = :'st_sa'::uuid from public.so_line l where l.so_id = pg_temp.sid('SO-79101') and l.sku = 'LN1-P1')
  and :'od1a' = 'null|null|nocoupon'
  and :'l1b' = '1:LN1-P1:4:90:O:-:ln1-sa | 2:LN1-P2:4:50:-:customer:-' and :'od1b' = '5|deal|nocoupon'
  and (pg_temp.j(:'d1')->'totals'->>'discount_basis_amount')::numeric = 200 and (pg_temp.j(:'d1')->'totals'->>'order_discount_amount')::numeric = 10 and public.so_lines_total(pg_temp.sid('SO-79101')) = 560
  and (pg_temp.j(:'d1')->'lines'->0->>'price_set_by_name') = 'LN1 sales A' and (pg_temp.j(:'d1')->'lines'->1->>'price_set_by_name') is null,
  format('%s | %s | %s | %s', left(:'r1', 300), :'l1b', :'od1b', left((pg_temp.j(:'d1')->'totals')::text, 200)));

\echo '── S2) 같은 가격 사람 줄에 다시 → 수량만(setter 그대로) · 다른 가격 → ask · 가격 없이 → ask · 시스템 줄과 같은 가격 → ask(판정 532) · 저장 0'
select price_set_at::text as t1 from public.so_line where so_id = pg_temp.sid('SO-79101') and sku = 'LN1-P1' \gset
select pg_temp.run(format('select public.so_lines_paste(%L::uuid, %L::jsonb, true)::text', pg_temp.sid('SO-79101'), jsonb_build_array(pg_temp.ln('LN1-P1', '2', '90.0')))) as r2a \gset
select pg_temp.lines_of('SO-79101') as l2a \gset
select pg_temp.run(format('select public.so_lines_paste(%L::uuid, %L::jsonb, true)::text', pg_temp.sid('SO-79101'), jsonb_build_array(pg_temp.ln('LN1-P1', '1', '95'), pg_temp.ln('LN1-P1', '1'), pg_temp.ln('LN1-P2', '1', '50'), pg_temp.ln('LN1-P2', '1', '45')))) as r2b \gset
select pg_temp.lines_of('SO-79101') as l2b \gset
select pg_temp.chk('S2 P1 @90.0 again → merged (qty 6 · price_set_at unchanged) — P1 @95 · P1 no price · P2 @50 (system line at the same price) · P2 @45 → four ask · nothing saved',
  (pg_temp.j(:'r2a')->'summary'->>'merged')::int = 1 and (pg_temp.j(:'r2a')->'summary'->>'updated')::int = 1 and :'l2a' = '1:LN1-P1:6:90:O:-:ln1-sa | 2:LN1-P2:4:50:-:customer:-'
  and (select price_set_at::text from public.so_line where so_id = pg_temp.sid('SO-79101') and sku = 'LN1-P1') = :'t1'
  and (pg_temp.j(:'r2b')->'summary'->>'ask')::int = 4 and (pg_temp.j(:'r2b')->'summary'->>'inserted')::int = 0 and (pg_temp.j(:'r2b')->'summary'->>'updated')::int = 0
  and (select bool_and(e->>'verdict' = 'ask') from jsonb_array_elements(pg_temp.j(:'r2b')->'lines') e) and :'l2b' = :'l2a',
  format('%s | %s | %s', left(:'r2a', 200), left(:'r2b', 500), :'l2b'));

\echo '── S3) 한 붙여넣기 안 같은 SKU 두 가격 → 둘째부터 ask · 미리 보기 = 저장'
select pg_temp.run(format('select public.so_lines_paste(%L::uuid, %L::jsonb, false)::text', pg_temp.sid('SO-79103'), jsonb_build_array(pg_temp.ln('LN1-P3', '10', '5'), pg_temp.ln('LN1-P3', '5'), pg_temp.ln('LN1-P3', '2', '5'), pg_temp.ln('LN1-P3', '1', '6')))) as r3p \gset
select pg_temp.run(format('select public.so_lines_paste(%L::uuid, %L::jsonb, true)::text', pg_temp.sid('SO-79103'), jsonb_build_array(pg_temp.ln('LN1-P3', '10', '5'), pg_temp.ln('LN1-P3', '5'), pg_temp.ln('LN1-P3', '2', '5'), pg_temp.ln('LN1-P3', '1', '6')))) as r3c \gset
select pg_temp.lines_of('SO-79103') as l3 \gset
select pg_temp.chk('S3 verdicts ok · ask · duplicate · ask in preview and commit alike (summary equal apart from committed/inserted) · one line P3×12 @5 by SA',
  (select jsonb_agg(e->>'verdict') from jsonb_array_elements(pg_temp.j(:'r3p')->'lines') e) = '["ok","ask","duplicate","ask"]'::jsonb
  and (select jsonb_agg(e->>'verdict') from jsonb_array_elements(pg_temp.j(:'r3c')->'lines') e) = '["ok","ask","duplicate","ask"]'::jsonb
  and (pg_temp.j(:'r3p')->'summary') - 'inserted' - 'updated' = (pg_temp.j(:'r3c')->'summary') - 'inserted' - 'updated'
  and (pg_temp.j(:'r3p')->'lines'->0->>'line_no') = (pg_temp.j(:'r3c')->'lines'->0->>'line_no') and (pg_temp.j(:'r3c')->'summary'->>'inserted')::int = 1
  and :'l3' = '1:LN1-P3:12:5:O:-:ln1-sa', format('%s | %s', left(:'r3p', 400), :'l3'));

\echo '── S4) 가격 칸 없음 · 빈 글자 → 지금과 같은 결과(적용 전 반환과 견준다 · 새 열쇠만 뺀다)'
select public.so_lines_paste(pg_temp.sid('SO-79102'), jsonb_build_array(pg_temp.ln('LN1-P1', '3'), pg_temp.ln('LN1-P2', '2'), pg_temp.ln('NOPE-1', '1'), pg_temp.ln('LN1-P1', 'x'), pg_temp.ln('ln1-p3', '4')), false)::text as paste_post \gset
select public.so_lines_paste(pg_temp.sid('SO-79102'), jsonb_build_array(pg_temp.ln('LN1-P1', '3', ''), pg_temp.ln('LN1-P2', '2', '  '), pg_temp.ln('NOPE-1', '1'), pg_temp.ln('LN1-P1', 'x'), pg_temp.ln('ln1-p3', '4')), false)::text as paste_blank \gset
create function pg_temp.strip(p jsonb) returns jsonb language sql immutable as $$
  select jsonb_set(jsonb_set(p, '{summary}', (p->'summary') - 'bad_price' - 'free_price' - 'set_price_refused' - 'priced'), '{lines}', (select coalesce(jsonb_agg(e - 'input_price' - 'price' order by (e->>'n')::int), '[]'::jsonb) from jsonb_array_elements(p->'lines') e)) $$;
select pg_temp.chk('S4 no price / blank price: preview identical to the pre-migration return (minus the four new summary keys and two new row keys) · new keys are 0 / null',
  pg_temp.strip(:'paste_post'::jsonb) = pg_temp.strip(:'paste_pre'::jsonb) and pg_temp.strip(:'paste_blank'::jsonb) = pg_temp.strip(:'paste_pre'::jsonb)
  and (:'paste_post'::jsonb->'summary'->>'priced')::int = 0 and (:'paste_post'::jsonb->'summary'->>'bad_price')::int = 0
  and (select bool_and(e->'price' = 'null'::jsonb) from jsonb_array_elements(:'paste_blank'::jsonb->'lines') e),
  format('pre %s | post %s', left(:'paste_pre', 300), left(:'paste_post', 300)));
select pg_temp.run(format('select public.so_lines_paste(%L::uuid, %L::jsonb, true)::text', pg_temp.sid('SO-79102'), jsonb_build_array(pg_temp.ln('LN1-P1', '3')))) as r4 \gset
select pg_temp.chk('S4b no-price commit → system line (override false · no setter)', pg_temp.lines_of('SO-79102') = '1:LN1-P1:3:100:-:customer:-', pg_temp.lines_of('SO-79102'));

\echo '── S5) 0 · 음수 · 글자 · 안 파는 세트 + 가격 → 거부 · 아무것도 안 들어감 · 세트 가격 없이 → 바뀌어 들어간다(전과 같다)'
select pg_temp.run(format('select public.so_lines_paste(%L::uuid, %L::jsonb, true)::text', pg_temp.sid('SO-79104'), jsonb_build_array(pg_temp.ln('LN1-P1', '1', '0'), pg_temp.ln('LN1-P2', '1', '-1'), pg_temp.ln('LN1-P3', '1', 'abc'), pg_temp.ln('LN1-P1-6', '1', '20'), pg_temp.ln('LN1-P3', '1', '1e2')))) as r5 \gset
select pg_temp.lines_of('SO-79104') as l5 \gset
select pg_temp.run(format('select public.so_lines_paste(%L::uuid, %L::jsonb, true)::text', pg_temp.sid('SO-79104'), jsonb_build_array(pg_temp.ln('LN1-P1-6', '1')))) as r5b \gset
select pg_temp.chk('S5 free_price 1 · bad_price 3 (−1 · abc · 1e2) · set_price_refused 1 · inserted 0 · no line — set without price → converted 6 × P1 (as before)',
  (pg_temp.j(:'r5')->'summary'->>'free_price')::int = 1 and (pg_temp.j(:'r5')->'summary'->>'bad_price')::int = 3 and (pg_temp.j(:'r5')->'summary'->>'set_price_refused')::int = 1 and (pg_temp.j(:'r5')->'summary'->>'inserted')::int = 0
  and (select jsonb_agg(e->>'verdict') from jsonb_array_elements(pg_temp.j(:'r5')->'lines') e) = '["free_price","bad_price","bad_price","set_price_refused","bad_price"]'::jsonb
  and (pg_temp.j(:'r5')->'lines'->3->>'message') like '%paste the base SKU LN1-P1 with its own price%' and (pg_temp.j(:'r5')->'lines'->0->>'message') like 'free lines: use Add line%'
  and :'l5' = '(none)' and (pg_temp.j(:'r5b')->'summary'->>'converted')::int = 1 and pg_temp.lines_of('SO-79104') = '1:LN1-P1:6:100:-:customer:-',
  format('%s | %s', left(:'r5', 600), pg_temp.lines_of('SO-79104')));

\echo '── S6) 콤보 + 가격 → 콤보 줄 단가 · 구성품 줄 따라옴(값 0 · setter 없음) · 미리 보기 줄 번호 = 저장'
select pg_temp.run(format('select public.so_lines_paste(%L::uuid, %L::jsonb, false)::text', pg_temp.sid('SO-79105'), jsonb_build_array(pg_temp.ln('LN1-C', '2', '100'), pg_temp.ln('LN1-P1', '1')))) as r6p \gset
select pg_temp.run(format('select public.so_lines_paste(%L::uuid, %L::jsonb, true)::text', pg_temp.sid('SO-79105'), jsonb_build_array(pg_temp.ln('LN1-C', '2', '100'), pg_temp.ln('LN1-P1', '1')))) as r6c \gset
select pg_temp.chk('S6 combo @100: line 1 LN1-C 2 @100 override by SA · components P2×4 · P3×2 at 0 with combo_line_id · no setter · P1 lands on line 4 in preview and commit',
  pg_temp.lines_of('SO-79105') = '1:LN1-C:2:100:O:-:ln1-sa | 2:LN1-P2:4:0:-:-:- | 3:LN1-P3:2:0:-:-:- | 4:LN1-P1:1:100:-:customer:-'
  and (select bool_and(c.combo_line_id = (select p.id from public.so_line p where p.so_id = pg_temp.sid('SO-79105') and p.sku = 'LN1-C') and c.price_set_by is null) from public.so_line c where c.so_id = pg_temp.sid('SO-79105') and c.sku in ('LN1-P2', 'LN1-P3'))
  and (pg_temp.j(:'r6p')->'lines'->1->>'line_no') = '4' and (pg_temp.j(:'r6c')->'lines'->1->>'line_no') = '4' and (pg_temp.j(:'r6c')->'lines'->0->>'components')::int = 2,
  format('%s | %s', pg_temp.lines_of('SO-79105'), left(:'r6c', 300)));

\echo '── S7) so_lines_clear — 미리 보기 · 실행(콤보 · 운임 · 쿠폰) · confirmed · shopify · 권한 · pos · 잠금'
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 1)::text', pg_temp.sid('SO-79101'), pg_temp.pid('LN1-C'))) as c7a \gset
select pg_temp.run(format('select public.so_charge_set(%L::uuid, ''Freight'', 20)::text', pg_temp.sid('SO-79101'))) as c7b \gset
select pg_temp.run(format('select public.so_coupon_apply(%L::uuid, ''LN1COUPON'')::text', pg_temp.sid('SO-79101'))) as c7c \gset
select pg_temp.lines_of('SO-79101') as l7a, pg_temp.od('SO-79101') as od7a \gset
select pg_temp.run(format('select public.so_lines_clear(%L::uuid, false)::text', pg_temp.sid('SO-79101'))) as p7 \gset
select pg_temp.lines_of('SO-79101') as l7b \gset
select pg_temp.who(:'au_w') as claims;
select pg_temp.run(format('select public.so_lines_clear(%L::uuid, true)::text', pg_temp.sid('SO-79101'))) as w7 \gset
select pg_temp.who(:'au_sa') as claims;
select pg_temp.lines_of('SO-79101') as l7c \gset
select pg_temp.run(format('select public.so_lines_clear(%L::uuid, true)::text', pg_temp.sid('SO-79101'))) as c7 \gset
select pg_temp.lines_of('SO-79101') as l7d, pg_temp.od('SO-79101') as od7d \gset
select (select count(*) from public.so_charge where so_id = pg_temp.sid('SO-79101')) as n_chg, (select coupon_id is not null from public.so where id = pg_temp.sid('SO-79101')) as cp_left \gset
select pg_temp.chk('S7a order with 3 lines (P1 manual · P2 system · combo + 2 components) · freight 20 · coupon applied (10 coupon) — preview: lines 3 · combo 1 · components 2 · charges 1 · coupon true · nothing changed — worker refused (sales) · nothing changed — commit: lines 0 · charge stays · coupon_id stays · discount null/null (basis 0 < 100)',
  :'l7a' like '1:LN1-P1:6:90:O:-:ln1-sa | 2:LN1-P2:4:50:-:customer:- | 3:LN1-C:1:120:-:customer:- | 4:%' and :'od7a' = '10|coupon|coupon' and :'c7b' not like 'ERR%' and :'c7c' not like 'ERR%'
  and pg_temp.j(:'p7') @> '{"committed": false, "lines": 3, "combo_lines": 1, "component_lines": 2, "charges_left": 1, "coupon_left": true}'::jsonb and :'l7b' = :'l7a'
  and (:'w7' like 'ERR 42501%' or :'w7' like 'ERR %cannot change sales data%')
  and :'l7c' = :'l7a'
  and pg_temp.j(:'c7') @> '{"committed": true, "lines": 3, "combo_lines": 1, "component_lines": 2, "charges_left": 1, "coupon_left": true}'::jsonb and (pg_temp.j(:'c7')->'order_discount'->>'pct') is null
  and :'l7d' = '(none)' and :n_chg = 1 and :'cp_left' = 't' and :'od7d' = 'null|null|coupon',
  format('%s | %s | %s | %s | %s', left(:'p7', 200), left(:'w7', 120), left(:'c7', 300), :'l7d', :'od7d'));
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 2)::text', pg_temp.sid('SO-79101'), pg_temp.pid('LN1-P1'))) as c7e \gset
select pg_temp.chk('S7b lines come back (P1×2 = 200) → the coupon deal is picked again (10 coupon) · the line added after the clear survives (same transaction — the cross-session case is assumed, not tested)',
  pg_temp.od('SO-79101') = '10|coupon|coupon' and pg_temp.lines_of('SO-79101') = '1:LN1-P1:2:100:-:customer:-', pg_temp.od('SO-79101') || ' ' || pg_temp.lines_of('SO-79101'));
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 1)::text', pg_temp.sid('SO-79109'), pg_temp.pid('LN1-P1'))) as c7f \gset
set local session_replication_role = replica;
update public.so set status = 'confirmed', confirmed_at = now() where so_number = 'SO-79109';
set local session_replication_role = origin;
select pg_temp.run(format('select public.so_lines_clear(%L::uuid, true)::text', pg_temp.sid('SO-79109'))) as e7a \gset
select pg_temp.run(format('select public.so_lines_clear(%L::uuid, true)::text', pg_temp.sid('SO-79107'))) as e7b \gset
select pg_temp.run(format('select public.so_lines_clear(%L::uuid, true)::text', '00000000-0000-4000-8000-00000000dead')) as e7c \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 1, 7)::text', pg_temp.sid('SO-79108'), pg_temp.pid('LN1-P3'))) as c7g \gset
select pg_temp.run(format('select public.so_lines_clear(%L::uuid, true)::text', pg_temp.sid('SO-79108'))) as c7h \gset
select pg_temp.chk('S7c confirmed → "not a draft … unconfirm it first" (line kept) · shopify → "came from Shopify" · unknown id → not found · pos draft → cleared · so row lock held by this backend (RowShareLock on so, granted)',
  :'e7a' like 'ERR %is not a draft (status confirmed) — unconfirm it first%' and pg_temp.lines_of('SO-79109') <> '(none)'
  and :'e7b' like 'ERR %came from Shopify%' and :'e7c' like 'ERR %Order not found%'
  and pg_temp.j(:'c7h') @> '{"committed": true, "lines": 1}'::jsonb and pg_temp.lines_of('SO-79108') = '(none)'
  and exists (select 1 from pg_locks k where k.pid = pg_backend_pid() and k.relation = 'public.so'::regclass and k.mode = 'RowShareLock' and k.granted),
  format('%s | %s | %s | %s', left(:'e7a', 120), left(:'e7b', 120), left(:'e7c', 80), left(:'c7h', 160)));

\echo '── S8) price_set_by/at — update 단가 → 찍힘 · 수량만 → 그대로 · 할인 % → 찍힘(SB) · ↺ → 비움 · comments 만 → 그대로 · 짝 CHECK · FK'
select id::text as l8 from public.so_line where so_id = pg_temp.sid('SO-79102') and sku = 'LN1-P1' \gset
select pg_temp.run(format('select public.so_line_update(%L::uuid, ''{"unit_price": "80"}'')::text', :'l8')) as u8a \gset
select price_set_by::text as b8a, price_set_at::text as t8a from public.so_line where id = :'l8'::uuid \gset
select pg_temp.run(format('select public.so_line_update(%L::uuid, ''{"qty_ordered": "5"}'')::text', :'l8')) as u8b \gset
select price_set_by::text as b8b, price_set_at::text as t8b, price_override::text as o8b from public.so_line where id = :'l8'::uuid \gset
select pg_temp.who(:'au_sb') as claims;
select pg_temp.run(format('select public.so_line_update(%L::uuid, ''{"discount_pct": "15"}'')::text', :'l8')) as u8c \gset
select price_set_by::text as b8c, price_set_at::text as t8c, discount_source as s8c, price_override::text as o8c from public.so_line where id = :'l8'::uuid \gset
select pg_temp.run(format('select public.so_line_update(%L::uuid, ''{"comments": "hello"}'')::text', :'l8')) as u8d \gset
select price_set_by::text as b8d, price_set_at::text as t8d from public.so_line where id = :'l8'::uuid \gset
select pg_temp.run(format('select public.so_line_update(%L::uuid, ''{"discount_pct": ""}'')::text', :'l8')) as u8e \gset
select coalesce(price_set_by::text, 'null') as b8e, coalesce(price_set_at::text, 'null') as t8e, price_override::text as o8e, coalesce(discount_source, 'null') as s8e from public.so_line where id = :'l8'::uuid \gset
select pg_temp.who(:'au_sa') as claims;
select pg_temp.attempt(format('update public.so_line set price_set_by = %L::uuid where id = %L::uuid', :'st_sa', :'l8')) as k8a \gset
select pg_temp.attempt(format('update public.so_line set price_set_at = now() where id = %L::uuid', :'l8')) as k8b \gset
select pg_temp.attempt(format('update public.so_line set price_set_by = ''00000000-0000-4000-8000-00000000dead'', price_set_at = now() where id = %L::uuid', :'l8')) as k8c \gset
select pg_temp.chk('S8 unit_price 80 → by SA · at set — qty 5 → unchanged (same at · still override) — discount 15 by SB → by SB · newer at · manual · override false — comments → unchanged — discount "" → both null · override false · system source — CHECK by-only · at-only → so_line_price_set_pair_ck · bogus staff → 23503',
  :'u8a' not like 'ERR%' and :'b8a' = :'st_sa' and :'t8a' <> ''
  and :'u8b' not like 'ERR%' and :'b8b' = :'st_sa' and :'t8b' = :'t8a' and :'o8b' = 'true'
  and :'u8c' not like 'ERR%' and :'b8c' = :'st_sb' and :'t8c' >= :'t8a' and :'s8c' = 'manual' and :'o8c' = 'false'
  and :'u8d' not like 'ERR%' and :'b8d' = :'st_sb' and :'t8d' = :'t8c'
  and :'u8e' not like 'ERR%' and :'b8e' = 'null' and :'t8e' = 'null' and :'o8e' = 'false' and :'s8e' <> 'manual'
  and :'k8a' like '23514%so_line_price_set_pair_ck%' and :'k8b' like '23514%so_line_price_set_pair_ck%' and :'k8c' like '23503%',
  format('%s %s | %s %s %s | %s %s | %s %s %s | %s | %s | %s', left(:'b8a', 8), :'t8a', left(:'b8c', 8), :'t8c', :'s8c', :'b8e', :'s8e', :'k8a', :'k8b', :'k8c', left(:'u8a', 60), left(:'u8c', 60), left(:'u8e', 60)));

\echo '── S9) 복사하는 길 — so_divide(일부 분할) · so_merge(두 초안 · 같은 손 가격)'
select pg_temp.who(:'au_sb') as claims;
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 10, 90)::text', pg_temp.sid('SO-79106'), pg_temp.pid('LN1-P1'))) as a9 \gset
select id::text as l9, price_set_at::text as t9 from public.so_line where so_id = pg_temp.sid('SO-79106') \gset
select pg_temp.run(format('select public.so_divide(%L::uuid, %L::jsonb, true)::text', pg_temp.sid('SO-79106'), jsonb_build_array(jsonb_build_object('line_id', :'l9', 'qty', 4)))) as v9 \gset
select pg_temp.chk('S9a divide 4 of 10 (manual @90 by SB): parent 6 · sibling SO-79106a 4 — both override · both price_set_by SB · same price_set_at',
  :'v9' not like 'ERR%' and pg_temp.lines_of('SO-79106') = '1:LN1-P1:6:90:O:-:ln1-sb' and pg_temp.lines_of('SO-79106a') = '1:LN1-P1:4:90:O:-:ln1-sb'
  and (select price_set_at::text = :'t9' from public.so_line where so_id = pg_temp.sid('SO-79106a')),
  format('%s | %s | %s', left(:'v9', 120), pg_temp.lines_of('SO-79106'), pg_temp.lines_of('SO-79106a')));
select pg_temp.who(:'au_sa') as claims;
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 2, 40)::text', pg_temp.sid('SO-79110'), pg_temp.pid('LN1-P2'))) as m9a \gset
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 1)::text', pg_temp.sid('SO-79110'), pg_temp.pid('LN1-P3'))) as m9b \gset
select price_set_at::text as t9m from public.so_line where so_id = pg_temp.sid('SO-79110') and sku = 'LN1-P2' \gset
select pg_temp.who(:'au_sb') as claims;
select pg_temp.run(format('select public.so_line_add(%L::uuid, %L::uuid, 3, 40)::text', pg_temp.sid('SO-79111'), pg_temp.pid('LN1-P2'))) as m9c \gset
select pg_temp.run(format('select public.so_merge(%L::uuid[], true)::text', array[pg_temp.sid('SO-79110'), pg_temp.sid('SO-79111')])) as m9 \gset
select pg_temp.j(:'m9')->>'so_number' as merged_num \gset
select pg_temp.chk('S9b merge SO-79110 (older · P2×2 @40 by SA · P3 system) + SO-79111 (P2×3 @40 by SB) → merged P2×5 @40 override · price_set_by = SA (first original) · same price_set_at · P3 line: no setter — ⚠️ bo-1d plan turns a system line with discount_pct 0 (customer 0%) into source manual (pre-existing · not ln-1 · reported)',
  :'m9' not like 'ERR%' and pg_temp.lines_of(:'merged_num') = '1:LN1-P2:5:40:O:-:ln1-sa | 2:LN1-P3:1:10:-:manual:-'
  and (select price_set_at::text = :'t9m' from public.so_line where so_id = pg_temp.sid(:'merged_num') and sku = 'LN1-P2'),
  format('%s | %s', left(:'m9', 160), pg_temp.lines_of(:'merged_num')));

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk(format('Z1 %s real lines and %s real orders untouched (md5 of qty · price · override · source · status · discount · coupon) · real lines have no price_set_by', :n_real_lines, :n_real_so),
  (select md5(coalesce(string_agg(l.id::text || ':' || l.qty_ordered || ':' || coalesce(l.unit_price::text, '') || ':' || l.price_override || ':' || coalesce(l.discount_source, ''), '|' order by l.id), '')) from public.so_line l join public.so s on s.id = l.so_id where s.so_number not like 'SO-791%' and s.so_number <> :'merged_num') = :'md5_real_lines'
  and (select md5(coalesce(string_agg(s.id::text || ':' || s.status || ':' || coalesce(s.order_discount_pct::text, '') || ':' || coalesce(s.order_discount_source, '') || ':' || coalesce(s.coupon_id::text, ''), '|' order by s.id), '')) from public.so s where s.so_number not like 'SO-791%' and s.so_number <> :'merged_num') = :'md5_real_so'
  and (select count(*) from public.so_line l join public.so s on s.id = l.so_id where s.so_number not like 'SO-791%' and s.so_number <> :'merged_num' and l.price_set_by is not null) = 0, 'see Z1');

rollback;
\echo '── rollback 뒤 — 시퀀스(so 는 greatest(실제 최대, 머리) 로 되돌림) · 가짜 흔적 0'
select setval('public.so_number_seq', greatest(:so_seq_last, (select max(substring(so_number from 4 for 5)::int) from public.so where so_number ~ '^SO-[0-9]{5}')), :'so_seq_called'::boolean) as so_seq_restored;
select (select last_value from public.so_number_seq) as so_seq_now, :so_seq_last as so_seq_head,
       (select count(*) from public.product where sku like 'LN1-%') + (select count(*) from public.customer where name like 'LN1 %') + (select count(*) from public.so where so_number like 'SO-791%') + (select count(*) from public.ims_staff where email like 'ln1-%') + (select count(*) from public.so_deal where name like 'LN1 %') as fake_traces_left,
       exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so_line' and column_name = 'price_set_by') as column_now;
