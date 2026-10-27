-- supabase/tests/hcr_1_check.sql — hcr-1 이력(hist_)을 보고 채우는 참조 크레딧 검증 (2026-10-26 · 판정 774 · 778 · 779 · 781 · 782 · 기술 넷)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4 · 잠금 규칙) — 기준(begin 앞 · 잠금 없음 · 실물 전수) → begin(lock_timeout 3s) → (-v mig 면 \i) → 가짜 재료 → 검증 → rollback → 시퀀스 greatest
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027010153_hcr_1_history_reference_credit.sql -f supabase/tests/hcr_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — alter · lock · truncate · drop 줄은 \i 갈래 밖에 없다
--   기대 OK: 시험 = 확인 = 아래 EXPECT_OK(29 · 시험 run 3 실측 29/0) · 적용 전 마른 실행(-v mig 없음)은 R1 의 직접 호출에서 멈춘다(function hist_credit_lines does not exist · ON_ERROR_STOP — 정상 · 실측 2026-10-26)
--   begin 앞 기준(실물 · 읽기만): B1 778 — 할인 줄이 있는 오더 전부의 P(제품 줄 합) · D(할인 줄 합) · B2 781 — 손님을 푼 오더 전부의 옛 세율(줄마다 1 센트 허용 · 이 파일이 독립으로 센다)과 매장 지금 규칙 세율 · B3 인보이스 둘 오더
--   begin 안(가짜 재료 · 작게): 직원 셋(M manager sales · W worker sales · V worker sales:read · N 열쇠 없음) · 손님(HQ · HQ2 · 매장 ON→HQ · 매장 AB→HQ · 배송지 없음) · 제품 셋 · 가짜 hist 오더 셋(HCR1-INV1 할인 · 운임 · 숨김 · 못 푼 제품 · 소문자 sku · Cin7 반품 / HCR1-INV2 매장 AB 13 % / HCR1-INV3 매장 ON 5 %)
--   시퀀스: I9 · I10 가 CR 번호를 둘 당긴다(발행 실물 — 남은 수량이 줄어드는 것을 보려면 필요) → 끝에 greatest(실제 최대, 머리)
\set ON_ERROR_STOP on
\set EXPECT_OK 29
\pset pager off

-- ═══ 기준(begin 앞 · 잠금 없음) ═══
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
select (select count(*) from public.so_credit) as n_cr, (select count(*) from public.so_credit_line) as n_crl, (select count(*) from public.ims_staff) as n_staff,
       (select count(*) from public.customer) as n_cust, (select count(*) from public.product) as n_prod, (select count(*) from public.hist_so) as n_hso, (select count(*) from public.hist_so_line) as n_hsl,
       (select count(*) from public.customer_address) as n_addr \gset
-- B1 778 기준: 할인 줄(Discount · Order total discount)이 있는 실제 오더 전부 — 이 파일의 분류(함수와 독립): 운임 = _4_ · Shipping… · 숨김 = Customer Credit… · CREDIT-… · 나머지 = 제품
create temp table t_disc as
  select h.id as hist_so_id, h.order_number,
         (select min(l2.doc_number) from public.hist_so_line l2 where l2.hist_so_id = h.id and l2.doc_type = 'invoice') as doc_number,
         (select count(distinct l2.doc_number) from public.hist_so_line l2 where l2.hist_so_id = h.id and l2.doc_type = 'invoice') as n_doc,
         sum(l.sale) filter (where l.sku not in ('_4_', 'Discount', 'Order total discount') and lower(l.sku) not like 'shipping%' and lower(l.sku) not like 'customer credit%' and upper(l.sku) not like 'CREDIT-%') as p,
         sum(l.sale) filter (where l.sku in ('Discount', 'Order total discount')) as d
  from public.hist_so h join public.hist_so_line l on l.hist_so_id = h.id and l.doc_type = 'invoice'
  where exists (select 1 from public.hist_so_line d where d.hist_so_id = h.id and d.doc_type = 'invoice' and d.sku in ('Discount', 'Order total discount'))
  group by h.id, h.order_number;
select count(*) as n_disc, count(*) filter (where n_doc > 1) as n_disc_multi, round(sum(d), 2) as sum_d from t_disc \gset
-- B2 781 기준: 손님을 푼 오더마다 옛 세율(후보 = 활성 판매 규칙 세율 · 줄마다 |tax − round(sale × c/100, 2)| 합 최소 · 동률이면 Σtax/Σsale 에 가까운 것) · 매장 지금 규칙 세율(기본 배송지 → so_tax_rule_for)
create temp table t_cur as
  select c.id as customer_id, (public.so_tax_rule_for(a.country, a.state_province, public.ims_today(), 'sale')->>'rate_pct')::numeric as cur_rate,
         public.so_tax_rule_for(a.country, a.state_province, public.ims_today(), 'sale')->>'rule' as cur_rule
  from public.customer c join public.customer_address a on a.customer_id = c.id and a.type = 'Shipping' and a.is_active and a.is_default_for_type
  where c.id in (select h.customer_id from public.hist_so h where h.customer_id is not null);
create temp table t_rate as
  with pl as (
    select l.hist_so_id, l.sale, coalesce(l.tax, 0) as tax from public.hist_so_line l
    where l.doc_type = 'invoice' and l.sale <> 0 and l.sku not in ('_4_', 'Discount', 'Order total discount') and lower(l.sku) not like 'shipping%' and lower(l.sku) not like 'customer credit%' and upper(l.sku) not like 'CREDIT-%'),
  cand as (select distinct r.rate_pct as rate from public.ref_tax_rule r where r.direction = 'sale' and r.is_active),
  err as (select pl.hist_so_id, c.rate, sum(abs(pl.tax - round(pl.sale * c.rate / 100, 2))) as err, max(abs(pl.tax - round(pl.sale * c.rate / 100, 2))) as maxerr, sum(pl.tax) as t, sum(pl.sale) as s
          from pl cross join cand c group by pl.hist_so_id, c.rate),
  best as (select distinct on (e.hist_so_id) e.hist_so_id, e.rate, e.maxerr from err e order by e.hist_so_id, e.err, abs(e.rate - 100 * e.t / e.s), e.rate)
  select h.id as hist_so_id, h.order_number, h.customer_id,
         (select min(l2.doc_number) from public.hist_so_line l2 where l2.hist_so_id = h.id and l2.doc_type = 'invoice') as doc_number,
         b.rate as old_rate, b.maxerr, tc.cur_rate, tc.cur_rule,
         (select count(*) from public.ref_tax_rule r where r.direction = 'sale' and r.is_active and r.rate_pct = b.rate) as n_same_rate
  from public.hist_so h join best b on b.hist_so_id = h.id left join t_cur tc on tc.customer_id = h.customer_id
  where h.customer_id is not null;
select count(*) as n_rate, count(*) filter (where cur_rate is null) as n_rate_nocur, count(*) filter (where cur_rate is not null and cur_rate <> old_rate) as n_differ,
       count(*) filter (where cur_rate is not null and cur_rate <> old_rate and n_same_rate = 1) as n_differ_one,
       count(*) filter (where cur_rate is not null and cur_rate <> old_rate and n_same_rate > 1) as n_differ_many,
       count(*) filter (where cur_rate is not null and cur_rate <> old_rate and n_same_rate = 0) as n_differ_none,
       count(*) filter (where maxerr > 0.01) as n_mixed from t_rate \gset
-- B3 인보이스 둘 오더(줄의 doc_number 가 둘)
create temp table t_multi as
  select h.order_number, l.doc_number, count(*) as n_lines, (select count(*) from public.hist_so_line l2 where l2.hist_so_id = h.id and l2.doc_type = 'invoice') as n_order_lines
  from public.hist_so h join public.hist_so_line l on l.hist_so_id = h.id and l.doc_type = 'invoice'
  where (select count(distinct l2.doc_number) from public.hist_so_line l2 where l2.hist_so_id = h.id and l2.doc_type = 'invoice') > 1
  group by h.id, h.order_number, l.doc_number;
select count(*) as n_multi_docs, count(distinct order_number) as n_multi_orders from t_multi \gset
\echo '── 기준: discount orders' :n_disc '(multi-invoice among them' :n_disc_multi '· Σdiscount' :sum_d ') · rated orders' :n_rate '(no current rule' :n_rate_nocur '· differ' :n_differ '= one' :n_differ_one '· many' :n_differ_many '· none' :n_differ_none '· mixed' :n_mixed ') · multi-invoice orders' :n_multi_orders '/ docs' :n_multi_docs
\echo '── 기준: so_credit' :n_cr '· lines' :n_crl '· staff' :n_staff '· customer' :n_cust '· product' :n_prod '· hist_so' :n_hso '· hist_so_line' :n_hsl '· cr seq' :cr_seq_last

-- ═══ 시험(begin 안 · 짧게) ═══
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, detail text);
create function pg_temp.chk(p_name text, p_ok boolean, p_detail text) returns void language sql as $$
  insert into t_res(name, ok, detail) values (p_name, coalesce(p_ok, false), p_detail);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 가짜 직원 신원으로 부른다(set local role authenticated + claims) · 예외는 'ERR …' 글자로
create function pg_temp.as_user(p_uid text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute p_sql into v;
  execute 'reset role';
  return coalesce(v, '(null)');
exception when others then
  execute 'reset role';
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.hasw(p text, p_w text) returns boolean language sql as $$ select coalesce((select bool_or(w like p_w) from jsonb_array_elements_text(coalesce(pg_temp.j(p)->'warnings', '[]'::jsonb)) w), false) $$;

-- ── F 착지 꼴 ──
select pg_temp.chk('F1 four hist functions · tax/source definer+stable · kind/lines postgres-only · tax/source authenticated',
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('hist_line_kind', 'hist_credit_lines', 'hist_credit_tax', 'hist_credit_source')) = 4
  and (select bool_and(p.prosecdef and p.provolatile = 's') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('hist_credit_lines', 'hist_credit_tax', 'hist_credit_source'))
  and has_function_privilege('authenticated', 'public.hist_credit_source(text)', 'execute') and has_function_privilege('authenticated', 'public.hist_credit_tax(text, uuid, date)', 'execute')
  and not has_function_privilege('authenticated', 'public.hist_credit_lines(text)', 'execute') and not has_function_privilege('anon', 'public.hist_credit_source(text)', 'execute') and not has_function_privilege('service_role', 'public.hist_credit_source(text)', 'execute'),
  pg_temp.run('select string_agg(p.proname || ''='' || coalesce(p.proacl::text, ''-'') || ''/'' || p.prosecdef::text, '' '') from pg_proc p where p.pronamespace = ''public''::regnamespace and p.proname like ''hist_%'''));
select pg_temp.chk('F2 so_credit.store_customer_id (fk customer) · warnings jsonb array default [] · table acl unchanged · no column acl',
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_credit' and column_name in ('store_customer_id', 'warnings')) = 2
  and (select relacl::text from pg_class where oid = 'public.so_credit'::regclass) = '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}'
  and not exists (select 1 from pg_attribute where attrelid = 'public.so_credit'::regclass and attacl is not null)
  and exists (select 1 from pg_constraint where conrelid = 'public.so_credit'::regclass and conname = 'so_credit_warnings_ck'),
  (select relacl::text from pg_class where oid = 'public.so_credit'::regclass));
select pg_temp.chk('F3 indexes: hist_so_line_doc_number_idx (lower(trim) · hist_so_id · not partial) · so_credit_store_idx · so_credit_ref_number_idx',
  (select count(*) from pg_indexes where schemaname = 'public' and indexname in ('hist_so_line_doc_number_idx', 'so_credit_store_idx', 'so_credit_ref_number_idx')) = 3
  and (select indexdef from pg_indexes where indexname = 'hist_so_line_doc_number_idx') like '%lower(TRIM(BOTH FROM doc_number)), hist_so_id)',
  (select indexdef from pg_indexes where indexname = 'hist_so_line_doc_number_idx'));
select pg_temp.chk('F4 so_credit_list: old columns in place · store_customer_id · store_name at the end · acl · security_invoker · so_credit_detail has store_name',
  (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'so_credit_list') like 'id,credit_number,status,issued_on,customer_id,customer_name,%,surcharge_amount,store_customer_id,store_name'
  and (select relacl::text from pg_class where oid = 'public.so_credit_list'::regclass) = '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}'
  and (select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_detail') like '%store_name%',
  (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'so_credit_list'));
do $$
declare v text;
begin
  execute 'explain (format json) select count(*) from public.hist_so_line where doc_type = ''invoice'' and lower(trim(doc_number)) = ''47441''' into v;
  perform set_config('app.plan', v, true);
exception when others then perform set_config('app.plan', 'ERR ' || sqlerrm, true);
end $$;
select pg_temp.chk('F5 plan for the normalized number lookup names hist_so_line_doc_number_idx', current_setting('app.plan', true) like '%hist_so_line_doc_number_idx%', left(current_setting('app.plan', true), 300));

-- 가짜 직원(먼저 — 정문이 걸린 창구를 postgres 세션에서 부를 때도 claims 가 필요하다)
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'hcr1-m@test.invalid', 'HCR1 M', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as m_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'hcr1-w@test.invalid', 'HCR1 W', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as w_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'hcr1-v@test.invalid', 'HCR1 V', 'worker', '["ims","sales:read"]', '{}') returning auth_user_id::text as v_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'hcr1-n@test.invalid', 'HCR1 N', 'worker', '[]', '{}') returning auth_user_id::text as n_uid \gset
select set_config('request.jwt.claims', json_build_object('sub', :'m_uid', 'role', 'authenticated')::text, true);
-- ── R 실물(적용 뒤 · 읽기만 · 작게) ──
-- R1 778: 할인 줄이 있는 오더 전부 — Σ round(unit_price_adj × qty, 2) = P + D (센트) · Σ sale_adj = P + D
create temp table t_r1 as
  select d.order_number, d.doc_number, d.p, d.d,
         (select sum(round(l.unit_price_adj * l.quantity, 2)) from public.hist_credit_lines(d.doc_number) l where l.kind = 'product') as s_unit,
         (select sum(l.sale_adj) from public.hist_credit_lines(d.doc_number) l where l.kind = 'product') as s_adj,
         (select sum(l.sale) from public.hist_credit_lines(d.doc_number) l where l.kind = 'product') as s_p,
         (select count(*) from public.hist_credit_lines(d.doc_number) l where l.kind = 'discount') as n_dl
  from t_disc d where d.n_doc = 1;
select pg_temp.chk(format('R1 778 on all %s real discount orders: Σround(unit_adj×qty,2) = P+D to the cent · Σsale_adj = P+D · Σsale = P (file classification = function classification) · Σdiscount %s', :n_disc, :sum_d),
  (select count(*) from t_r1) = :n_disc and (select bool_and(s_unit = round(p + d, 2) and s_adj = round(p + d, 2) and s_p = p and n_dl > 0) from t_r1),
  (select string_agg(format('%s P %s D %s unit %s adj %s', order_number, p, d, s_unit, s_adj), ' | ') from t_r1 where not (s_unit = round(p + d, 2) and s_adj = round(p + d, 2) and s_p = p)));
-- R2 781: 세율이 다른 오더 전부 + 같은 오더 표본 50 — hist_credit_tax 의 old_rate_pct = 파일의 옛 세율 · differs · suggested 하나/여럿/없음 분포
create temp table t_r2 as
  select r.order_number, r.doc_number, r.old_rate, r.cur_rate, r.cur_rule, r.n_same_rate, r.maxerr,
         public.hist_credit_tax(r.doc_number, r.customer_id, public.ims_today()) as t
  from t_rate r where r.cur_rate is not null and (r.cur_rate <> r.old_rate or r.hist_so_id in (select hist_so_id from t_rate where cur_rate is not null and cur_rate = old_rate order by order_number desc limit 50));
select count(*) filter (where cur_rate <> old_rate) as r2_diff, count(*) filter (where cur_rate = old_rate) as r2_same,
       count(*) filter (where cur_rate <> old_rate and t->'suggested' is not null and jsonb_typeof(t->'suggested') = 'object') as r2_one,
       count(*) filter (where cur_rate <> old_rate and jsonb_typeof(t->'suggested') <> 'object' and jsonb_array_length(t->'candidates') > 1) as r2_many,
       count(*) filter (where cur_rate <> old_rate and jsonb_typeof(t->'suggested') <> 'object' and jsonb_array_length(t->'candidates') = 0) as r2_none,
       count(*) filter (where t->>'tax_fit' = 'mixed') as r2_mixed from t_r2 \gset
select pg_temp.chk(format('R2 781 on all %s differing real orders (+%s same-rate sample): old_rate_pct = file rate · differs flag · suggested one %s / many %s / none %s · mixed %s · same-rate → suggested = current rule',
                          :r2_diff, :r2_same, :r2_one, :r2_many, :r2_none, :r2_mixed),
  :r2_diff = :n_differ and :r2_one = :n_differ_one and :r2_many = :n_differ_many and :r2_none = :n_differ_none
  and (select bool_and((t->>'old_rate_pct')::numeric = old_rate and (t->>'differs')::boolean = (cur_rate <> old_rate) and ((t->>'tax_fit' = 'mixed') = (maxerr > 0.01))) from t_r2)
  and (select bool_and(t->'suggested'->>'rule' = cur_rule and not (t->>'differs')::boolean) from t_r2 where cur_rate = old_rate),
  (select string_agg(format('%s old %s cur %s fn %s', order_number, old_rate, cur_rate, left(t::text, 160)), ' | ') from t_r2 where not ((t->>'old_rate_pct')::numeric = old_rate and (t->>'differs')::boolean = (cur_rate <> old_rate)) limit 1));
-- R3 인보이스 둘 오더: 번호마다 그 번호의 줄만(줄 수 = hist 실물) · 47441 ↔ 47143 서로 안 섞임 · 창구 경고 order_has_other_invoice
create temp table t_r3 as
  select m.order_number, m.doc_number, m.n_lines, (select count(*) from public.hist_credit_lines(m.doc_number) l) as n_fn,
         (select count(*) from public.hist_credit_lines(m.doc_number) l where l.doc_number <> m.doc_number) as n_other from t_multi m;
select pg_temp.chk(format('R3 %s multi-invoice orders / %s numbers: each number returns exactly its own lines (47441 → 3 incl. freight · 47143 → 2) · none of the other number', :n_multi_orders, :n_multi_docs),
  (select bool_and(n_fn = n_lines and n_other = 0) from t_r3) and (select n_fn from t_r3 where doc_number = '47441') = 3 and (select n_fn from t_r3 where doc_number = '47143') = 2,
  (select string_agg(format('%s %s hist %s fn %s other %s', order_number, doc_number, n_lines, n_fn, n_other), ' | ') from t_r3));

-- ── 가짜 재료(손님 · 제품 · hist 오더) ──
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('HCR1 HQ', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as c_hq \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('HCR1 HQ2', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as c_hq2 \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name, default_bill_to_customer_id) values ('HCR1 Store ON', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name', :'c_hq'::uuid) returning id::text as c_on \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name, default_bill_to_customer_id) values ('HCR1 Store AB', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name', :'c_hq'::uuid) returning id::text as c_ab \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('HCR1 NoAddr', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as c_no \gset
-- HQ 는 배송지 없음(매장 배송지가 쓰이는지 가른다) · HQ2 · 매장 ON 은 ON · 매장 AB 는 AB
insert into public.customer_address (customer_id, type, is_default_for_type, line1, city, state_province, postal_code, country, source, is_active) values
  (:'c_on'::uuid, 'Shipping', true, '1 Test St', 'Toronto', 'ON', 'M1M 1M1', 'Canada', 'manual', true),
  (:'c_hq2'::uuid, 'Shipping', true, '3 Test St', 'Toronto', 'ON', 'M1M 1M1', 'Canada', 'manual', true),
  (:'c_ab'::uuid, 'Shipping', true, '2 Test Ave', 'Calgary', 'Alberta', 'T1T 1T1', 'Canada', 'manual', true);
insert into public.product (sku, name, source) values ('HCR1-P1', 'HCR1 Product 1', 'manual') returning id::text as p1 \gset
insert into public.product (sku, name, source) values ('HCR1-P2', 'HCR1 Product 2', 'manual') returning id::text as p2 \gset
insert into public.product (sku, name, source) values ('HCR1-P3', 'HCR1 Product 3 (not on invoice)', 'manual') returning id::text as p3 \gset
set local session_replication_role = origin;
-- 가짜 hist 오더 ① HCR1-INV1(매장 ON · 통화 없음 → 손님 CAD): P1 10 @ 9.99 (sku 소문자 hcr1-p1 · product_id 는 P1) · P2 4 @ 5 · 못 푼 HCR1-ZZZ 2 @ 5 · Discount −12 · _4_ 운임 15 · Customer Credit Write-off 5 (숨김) · Cin7 반품 P1 −2 · 세금 13 %
\set p1_qty 10
\set p1_unit 9.99
\set p2_qty 4
\set p2_unit 5
\set zz_qty 2
\set zz_unit 5
\set disc -12
insert into public.hist_so (order_number, customer_id, customer_name, order_date, invoice_date, invoice_number, location, currency, sale_total, tax_total, total, line_count, has_return, source)
  values ('SO-HCR1-1', :'c_on'::uuid, 'HCR1 Store ON', public.ims_today() - 40, public.ims_today() - 30, 'HCR1-INV1', 'Asung - Toronto', null, 132.90, 17.28, 132.90, 7, true, 'bq_confirmed') returning id::text as h1 \gset
insert into public.hist_so_line (hist_so_id, seq, doc_type, doc_number, doc_date, sku, product_id, product_name, quantity, unit_price, sale, tax, total, is_return) values
  (:'h1'::uuid, 1, 'invoice', 'HCR1-INV1', public.ims_today() - 30, 'hcr1-p1', :'p1'::uuid, 'HCR1 Product 1', :p1_qty, :p1_unit, round(:p1_qty * :p1_unit, 2), round(round(:p1_qty * :p1_unit, 2) * 0.13, 2), round(:p1_qty * :p1_unit, 2), false),
  (:'h1'::uuid, 2, 'invoice', 'HCR1-INV1', public.ims_today() - 30, 'HCR1-P2', :'p2'::uuid, 'HCR1 Product 2', :p2_qty, :p2_unit, round(:p2_qty * :p2_unit, 2), round(round(:p2_qty * :p2_unit, 2) * 0.13, 2), round(:p2_qty * :p2_unit, 2), false),
  (:'h1'::uuid, 3, 'invoice', 'HCR1-INV1', public.ims_today() - 30, 'HCR1-ZZZ', null, 'Unknown thing', :zz_qty, :zz_unit, round(:zz_qty * :zz_unit, 2), round(round(:zz_qty * :zz_unit, 2) * 0.13, 2), round(:zz_qty * :zz_unit, 2), false),
  (:'h1'::uuid, 4, 'invoice', 'HCR1-INV1', public.ims_today() - 30, 'Discount', null, 'Discount', 1, :disc, :disc, round(:disc * 0.13, 2), :disc, false),
  (:'h1'::uuid, 5, 'invoice', 'HCR1-INV1', public.ims_today() - 30, '_4_', null, 'Freight', 1, 15, 15, 1.95, 15, false),
  (:'h1'::uuid, 6, 'invoice', 'HCR1-INV1', public.ims_today() - 30, 'Customer Credit Write-off', null, 'Customer Credit Write-off', 1, 5, 5, 0, 5, false),
  (:'h1'::uuid, 7, 'credit', 'CR-HCR1-1', public.ims_today() - 20, 'HCR1-P1', :'p1'::uuid, 'HCR1 Product 1', -2, 9.99, -19.98, -2.60, -19.98, true);
-- ② HCR1-INV2(매장 AB · 13 % 줄 → 지금 규칙 GST 5 와 다름 · 13 % 규칙 셋) ③ HCR1-INV3(매장 ON · 5 % 줄 → 지금 HST ON 13 과 다름 · 5 % 규칙 하나)
insert into public.hist_so (order_number, customer_id, customer_name, order_date, invoice_date, invoice_number, location, currency, sale_total, tax_total, total, line_count, has_return, source)
  values ('SO-HCR1-2', :'c_ab'::uuid, 'HCR1 Store AB', public.ims_today() - 40, public.ims_today() - 30, 'HCR1-INV2', 'Asung - Toronto', 'CAD', 100, 13, 100, 1, false, 'bq_current') returning id::text as h2 \gset
insert into public.hist_so_line (hist_so_id, seq, doc_type, doc_number, doc_date, sku, product_id, product_name, quantity, unit_price, sale, tax, total, is_return) values
  (:'h2'::uuid, 1, 'invoice', 'HCR1-INV2', public.ims_today() - 30, 'HCR1-P1', :'p1'::uuid, 'HCR1 Product 1', 10, 10, 100, 13, 100, false);
insert into public.hist_so (order_number, customer_id, customer_name, order_date, invoice_date, invoice_number, location, currency, sale_total, tax_total, total, line_count, has_return, source)
  values ('SO-HCR1-3', :'c_on'::uuid, 'HCR1 Store ON', public.ims_today() - 40, public.ims_today() - 30, 'HCR1-INV3', 'Asung - Toronto', 'CAD', 100, 5, 100, 1, false, 'bq_current') returning id::text as h3 \gset
insert into public.hist_so_line (hist_so_id, seq, doc_type, doc_number, doc_date, sku, product_id, product_name, quantity, unit_price, sale, tax, total, is_return) values
  (:'h3'::uuid, 1, 'invoice', 'HCR1-INV3', public.ims_today() - 30, 'HCR1-P2', :'p2'::uuid, 'HCR1 Product 2', 20, 5, 100, 5, 100, false);
-- 778 기대값(파일 안에서 입력으로 센다): P · D · 반영 금액 · 단가
select round(:p1_qty * :p1_unit, 2) + round(:p2_qty * :p2_unit, 2) + round(:zz_qty * :zz_unit, 2) as e_p \gset
select round(round(:p1_qty * :p1_unit, 2) * (:e_p + :disc) / :e_p, 2) as e_p1_amt, round(round(:p2_qty * :p2_unit, 2) * (:e_p + :disc) / :e_p, 2) as e_p2_amt, round(round(:zz_qty * :zz_unit, 2) * (:e_p + :disc) / :e_p, 2) as e_zz_amt \gset
select round(:e_p1_amt / :p1_qty, 6) as e_p1_unit, round(:e_p2_amt / :p2_qty, 6) as e_p2_unit, round(:e_zz_amt / :zz_qty, 6) as e_zz_unit \gset
\echo '── 778 기대: P' :e_p 'D' :disc '→ P1' :e_p1_amt '@' :e_p1_unit '· P2' :e_p2_amt '@' :e_p2_unit '· ZZZ' :e_zz_amt '@' :e_zz_unit
select pg_temp.chk('M0 fake staff ×4 · customers HQ / HQ2 / Store ON→HQ / Store AB→HQ / NoAddr · products ×3 · hist orders ×3 · Σ adjusted = P + D in the file''s own arithmetic',
  :'m_uid' <> '' and :'c_hq' <> '' and :'c_on' <> '' and :'c_ab' <> '' and :'p1' <> '' and :'h1' <> '' and :'h3' <> '' and (:e_p1_amt + :e_p2_amt + :e_zz_amt) = :e_p + :disc,
  format('P %s D %s adj %s + %s + %s', :e_p, :disc, :e_p1_amt, :e_p2_amt, :e_zz_amt));

-- ── S 창구 hist_credit_source ──
select pg_temp.as_user(:'v_uid', 'select public.hist_credit_source(''HCR1-INV1'')::text') as s1 \gset
select pg_temp.j(:'s1')->'orders'->0 as o1 \gset
select pg_temp.chk('S1 V (sales:read) reads HCR1-INV1: found · one order · store = Store ON · bill-to = HQ · currency CAD from customer · 2 resolved + 1 unresolved product lines · freight 1 (checked false · 15) · hidden 1 (5) · discount −12 · warnings product_unresolved:1',
  (pg_temp.j(:'s1')->>'found')::boolean and not (pg_temp.j(:'s1')->>'multiple_orders')::boolean
  and :'o1'::jsonb->'customer'->>'store_customer_id' = :'c_on' and :'o1'::jsonb->'customer'->>'bill_to_customer_id' = :'c_hq' and :'o1'::jsonb->'customer'->>'bill_to_name' = 'HCR1 HQ'
  and :'o1'::jsonb->'customer'->>'currency_code' = 'CAD' and :'o1'::jsonb->'customer'->>'currency_source' = 'customer' and not (:'o1'::jsonb->'customer'->>'bill_to_is_store')::boolean
  and jsonb_array_length(:'o1'::jsonb->'lines') = 3 and (select count(*) from jsonb_array_elements(:'o1'::jsonb->'lines') e where (e->>'resolved')::boolean) = 2
  and jsonb_array_length(:'o1'::jsonb->'freight') = 1 and not (:'o1'::jsonb->'freight'->0->>'checked')::boolean and (:'o1'::jsonb->'freight'->0->>'amount')::numeric = 15
  and (:'o1'::jsonb->'totals'->>'hidden_lines')::int = 1 and (:'o1'::jsonb->'totals'->>'hidden_amount')::numeric = 5 and (:'o1'::jsonb->'totals'->>'discount_amount')::numeric = :disc and (:'o1'::jsonb->'totals'->>'product_amount')::numeric = :e_p
  and :'o1'::jsonb->'warnings' ? 'product_unresolved:1' and :'o1'::jsonb->>'order_number' = 'SO-HCR1-1' and :'o1'::jsonb->>'invoice_number' = 'HCR1-INV1',
  left(:'s1', 900));
select pg_temp.chk(format('S2 778 lines: P1 unit %s (hist 9.99) · P2 unit %s · ZZZ unit %s · amounts %s / %s / %s · product_sku HCR1-P1 from hist sku hcr1-p1 · P1 remaining 8 (10 − Cin7 2) · P2 remaining 4 · ZZZ resolved false · line rate 13', :e_p1_unit, :e_p2_unit, :e_zz_unit, :e_p1_amt, :e_p2_amt, :e_zz_amt),
  (select bool_and(case e->>'sku'
                     when 'hcr1-p1' then (e->>'unit_price')::numeric = :e_p1_unit and (e->>'amount')::numeric = :e_p1_amt and (e->>'unit_price_hist')::numeric = :p1_unit and e->>'product_sku' = 'HCR1-P1' and (e->>'qty_remaining')::numeric = 8 and (e->>'qty_cin7_returned')::numeric = 2 and (e->>'qty_ims_credited')::numeric = 0 and (e->>'rate_pct_line')::numeric = 13
                     when 'HCR1-P2' then (e->>'unit_price')::numeric = :e_p2_unit and (e->>'amount')::numeric = :e_p2_amt and (e->>'qty_remaining')::numeric = 4
                     when 'HCR1-ZZZ' then (e->>'unit_price')::numeric = :e_zz_unit and not (e->>'resolved')::boolean and e->>'product_sku' is null
                     else false end)
     from jsonb_array_elements(:'o1'::jsonb->'lines') e),
  (:'o1'::jsonb->'lines')::text);
select pg_temp.chk('S3 tax for HCR1-INV1: old 13 (exact) · current HST ON (Sale) 13 (ship_to Store ON) · suggested = current · differs false · pick_needed false',
  (:'o1'::jsonb->'tax'->>'old_rate_pct')::numeric = 13 and :'o1'::jsonb->'tax'->>'tax_fit' = 'exact' and :'o1'::jsonb->'tax'->'current_rule'->>'rule' = 'HST ON (Sale)'
  and :'o1'::jsonb->'tax'->'suggested'->>'rule' = 'HST ON (Sale)' and not (:'o1'::jsonb->'tax'->>'differs')::boolean and not (:'o1'::jsonb->'tax'->>'pick_needed')::boolean,
  (:'o1'::jsonb->'tax')::text);
select pg_temp.as_user(:'v_uid', 'select public.hist_credit_source(''HCR1-INV2'')::text') as s4a \gset
select pg_temp.as_user(:'v_uid', 'select public.hist_credit_source(''HCR1-INV3'')::text') as s4b \gset
select pg_temp.chk('S4 tax differs: INV2 (Store AB · lines 13 %) → current GST 5 · candidates 3 × 13 % · suggested null · pick_needed · warnings tax_rule_differs + tax_pick_needed / INV3 (Store ON · lines 5 %) → suggested GST (Sale) · differs true',
  (pg_temp.j(:'s4a')->'orders'->0->'tax'->>'old_rate_pct')::numeric = 13 and pg_temp.j(:'s4a')->'orders'->0->'tax'->'current_rule'->>'rule' = 'GST (Sale)'
  and jsonb_array_length(pg_temp.j(:'s4a')->'orders'->0->'tax'->'candidates') = 3 and jsonb_typeof(pg_temp.j(:'s4a')->'orders'->0->'tax'->'suggested') = 'null' and (pg_temp.j(:'s4a')->'orders'->0->'tax'->>'pick_needed')::boolean
  and pg_temp.j(:'s4a')->'orders'->0->'warnings' ? 'tax_rule_differs' and pg_temp.j(:'s4a')->'orders'->0->'warnings' ? 'tax_pick_needed'
  and (pg_temp.j(:'s4b')->'orders'->0->'tax'->>'old_rate_pct')::numeric = 5 and pg_temp.j(:'s4b')->'orders'->0->'tax'->'suggested'->>'rule' = 'GST (Sale)' and (pg_temp.j(:'s4b')->'orders'->0->'tax'->>'differs')::boolean
  and pg_temp.j(:'s4b')->'orders'->0->'tax'->'current_rule'->>'rule' = 'HST ON (Sale)',
  format('INV2 %s | INV3 %s', left((pg_temp.j(:'s4a')->'orders'->0->'tax')::text, 400), left((pg_temp.j(:'s4b')->'orders'->0->'tax')::text, 300)));
select pg_temp.as_user(:'v_uid', 'select public.hist_credit_source(''no-such-number'')::text') as s5a \gset
select pg_temp.as_user(:'v_uid', 'select public.hist_credit_source(''  hcr1-inv1 '')::text') as s5b \gset
select pg_temp.as_user(:'v_uid', 'select public.hist_credit_source('''')::text') as s5c \gset
select pg_temp.chk('S5 not found → found false (no error) · case/space-insensitive number → found · blank → refused',
  not (pg_temp.j(:'s5a')->>'found')::boolean and jsonb_array_length(pg_temp.j(:'s5a')->'orders') = 0 and (pg_temp.j(:'s5b')->>'found')::boolean and pg_temp.j(:'s5b')->>'number_norm' = 'hcr1-inv1'
  and :'s5c' like 'ERR%' and :'s5c' like '%Give the number%',
  format('%s | %s | %s', left(:'s5a', 120), left(:'s5b', 80), left(:'s5c', 120)));
select pg_temp.as_user(:'n_uid', 'select public.hist_credit_source(''HCR1-INV1'')::text') as s6a \gset
select pg_temp.as_user(:'n_uid', 'select public.hist_credit_tax(''HCR1-INV1'', null, null)::text') as s6b \gset
select pg_temp.as_user(:'v_uid', 'select count(*)::text from public.hist_credit_lines(''HCR1-INV1'')') as s6c \gset
select pg_temp.chk('S6 gates: staff without sales → source + tax refused ("cannot view sales") · V cannot call hist_credit_lines directly (42501)',
  :'s6a' like 'ERR%' and :'s6a' like '%cannot view sales%' and :'s6b' like 'ERR%' and :'s6b' like '%cannot view sales%' and :'s6c' like 'ERR 42501%',
  format('%s | %s | %s', left(:'s6a', 100), left(:'s6b', 100), left(:'s6c', 100)));
select clock_timestamp() as t_s7 \gset
select pg_temp.as_user(:'v_uid', 'select public.hist_credit_source(''47441'')::text') as s7 \gset
select extract(epoch from clock_timestamp() - :'t_s7'::timestamptz) as s7_sec \gset
select pg_temp.chk(format('S7 real 47441 as V: found · 2 lines (COS47030 · TOR60026) · 1 freight · warning order_has_other_invoice:47143 · tax GST (Sale) · took %s s (< 2)', round(:s7_sec::numeric, 3)),
  (pg_temp.j(:'s7')->>'found')::boolean and jsonb_array_length(pg_temp.j(:'s7')->'orders'->0->'lines') = 2 and jsonb_array_length(pg_temp.j(:'s7')->'orders'->0->'freight') = 1
  and pg_temp.j(:'s7')->'orders'->0->'warnings' ? 'order_has_other_invoice:47143' and pg_temp.j(:'s7')->'orders'->0->'tax'->'suggested'->>'rule' = 'GST (Sale)'
  and pg_temp.j(:'s7')->'orders'->0->>'order_number' = 'SO-13743' and :s7_sec < 2,
  left(:'s7', 400));

-- ── I 발행 창구 so_credit_issue(ref) ──
-- 공통 재료: 매장 ON · 청구처 HQ · P1 (product_sku · 778 단가) · 사유 customer_return · 돌아오지 않음(damaged → 칸 · 원장 없음)
\set lnP1 '''{"kind":"product","sku":"HCR1-P1","qty_returned":%s,"unit_price":%s,"not_restocked_reason":"damaged"}'''
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1', 'order_number', 'SO-HCR1-1', 'invoice_date', public.ims_today() - 30),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 8, 'unit_price', :e_p1_unit, 'not_restocked_reason', 'damaged'))))) as i1 \gset
select pg_temp.chk(format('I1 M preview: store ON + bill-to HQ · P1 8 @ %s (hist price) · no tax_rule → tax from history HST ON (Sale) (source history) · no manual_unit_price · no qty_over_sold · no reference_not_in_history · amount %s', :e_p1_unit, round(8 * :e_p1_unit, 2)),
  :'i1' not like 'ERR%' and not (pg_temp.j(:'i1')->>'committed')::boolean and pg_temp.j(:'i1')->'origin'->>'tax_rule' = 'HST ON (Sale)' and pg_temp.j(:'i1')->'origin'->>'tax_rule_source' = 'history'
  and pg_temp.j(:'i1')->>'customer_id' = :'c_hq' and (pg_temp.j(:'i1')->'lines'->0->>'amount')::numeric = round(8 * :e_p1_unit, 2) and pg_temp.j(:'i1')->'lines'->0->>'account_code' = '_98_'
  and not pg_temp.hasw(:'i1', 'manual_unit_price%') and not pg_temp.hasw(:'i1', 'qty_over_sold%') and not pg_temp.hasw(:'i1', 'reference_not_in_history') and not pg_temp.hasw(:'i1', 'tax_rule_differs%'),
  left(:'i1', 700));
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_on', 'store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', :e_p1_unit, 'not_restocked_reason', 'damaged'))))) as i2a \gset
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', :e_p1_unit, 'not_restocked_reason', 'damaged'))))) as i2b \gset
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', '00000000-0000-0000-0000-000000000001', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', :e_p1_unit, 'not_restocked_reason', 'damaged'))))) as i2c \gset
select pg_temp.chk('I2 779 gate: customer_id = store itself (not its bill-to) → refused "must be the bill-to of store HCR1 Store ON" · store without customer_id → old "needs customer_id" · unknown store → "Store customer not found"',
  :'i2a' like 'ERR%' and :'i2a' like '%must be the bill-to of store HCR1 Store ON%' and :'i2b' like 'ERR%' and :'i2b' like '%needs customer_id%' and :'i2c' like 'ERR%' and :'i2c' like '%Store customer not found%',
  format('%s | %s | %s', left(:'i2a', 160), left(:'i2b', 120), left(:'i2c', 120)));
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 5, 'unit_price', :e_p1_unit, 'not_restocked_reason', 'damaged'),
                                                jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 4, 'unit_price', 9.99, 'not_restocked_reason', 'damaged'))))) as i3a \gset
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 2, 'unit_price', round(:e_p1_unit + 0.003, 3), 'not_restocked_reason', 'damaged'))))) as i3b \gset
select pg_temp.chk('I3 warnings only (not refused): 5 + 4 = 9 of 8 → qty_over_sold:HCR1-P1:9/8 once · 9.99 ≠ hist → manual_unit_price / unit within 0.003 of hist → no manual_unit_price',
  :'i3a' not like 'ERR%' and pg_temp.hasw(:'i3a', 'qty_over_sold:HCR1-P1:9/8') and pg_temp.hasw(:'i3a', 'manual_unit_price')
  and (select count(*) from jsonb_array_elements_text(pg_temp.j(:'i3a')->'warnings') w where w like 'qty_over_sold%') = 1
  and :'i3b' not like 'ERR%' and not pg_temp.hasw(:'i3b', 'manual_unit_price') and not pg_temp.hasw(:'i3b', 'qty_over_sold%'),
  format('%s | %s', (pg_temp.j(:'i3a')->'warnings')::text, (pg_temp.j(:'i3b')->'warnings')::text));
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'hcr1-p1', 'qty_returned', 1, 'unit_price', :e_p1_unit, 'not_restocked_reason', 'damaged'))))) as i4a \gset
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P3', 'qty_returned', 1, 'unit_price', 3, 'not_restocked_reason', 'damaged'),
                                                jsonb_build_object('kind', 'freight', 'amount', 15))))) as i4b \gset
select pg_temp.chk('I4 hist sku in lower case → "Product hcr1-p1 not found" (screen must send product_sku) · product not on the invoice → not_on_invoice:HCR1-P3 + manual_unit_price · freight line → account _99_ (Freight Sales Account) · 13 % tax',
  :'i4a' like 'ERR%' and :'i4a' like '%Product hcr1-p1 not found%'
  and :'i4b' not like 'ERR%' and pg_temp.hasw(:'i4b', 'not_on_invoice:HCR1-P3') and pg_temp.hasw(:'i4b', 'manual_unit_price')
  and pg_temp.j(:'i4b')->'lines'->1->>'kind' = 'freight' and pg_temp.j(:'i4b')->'lines'->1->>'account_code' = '_99_' and (pg_temp.j(:'i4b')->'lines'->1->>'tax_amount')::numeric = 1.95,
  format('%s | %s', left(:'i4a', 120), left(:'i4b', 500)));
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_ab', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV2'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', 10, 'not_restocked_reason', 'damaged'))))) as i5a \gset
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_ab', 'reason', 'customer_return', 'tax_rule', 'HST NB (Sale)', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV2'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', 10, 'not_restocked_reason', 'damaged'))))) as i5b \gset
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV3'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P2', 'qty_returned', 1, 'unit_price', 5, 'not_restocked_reason', 'damaged'))))) as i5c \gset
select pg_temp.chk('I5 781 in issue: INV2 (13 % · Store AB now GST) no tax_rule → "Pick a tax rule — invoice HCR1-INV2 was taxed at 13 percent and 3 active sale rule(s) …" · tax_rule given → given · INV3 (5 % · Store ON now HST ON) → GST (Sale) 5 % + warning tax_rule_differs:HST ON (Sale)',
  :'i5a' like 'ERR%' and :'i5a' like '%Pick a tax rule — invoice HCR1-INV2 was taxed at 13 percent and 3 active sale rule(s)%' and :'i5a' like '%HST NB (Sale), HST NL (Sale), HST ON (Sale)%'
  and :'i5b' not like 'ERR%' and pg_temp.j(:'i5b')->'origin'->>'tax_rule' = 'HST NB (Sale)' and pg_temp.j(:'i5b')->'origin'->>'tax_rule_source' = 'given'
  and :'i5c' not like 'ERR%' and pg_temp.j(:'i5c')->'origin'->>'tax_rule' = 'GST (Sale)' and (pg_temp.j(:'i5c')->'origin'->>'rate_pct')::numeric = 5 and pg_temp.j(:'i5c')->'origin'->>'tax_rule_source' = 'history'
  and pg_temp.hasw(:'i5c', 'tax_rule_differs:HST ON (Sale)') and (pg_temp.j(:'i5c')->'lines'->0->>'tax_amount')::numeric = 0.25,
  format('%s | %s | %s', left(:'i5a', 260), left(:'i5b', 160), left(:'i5c', 300)));
-- I6 발행(시퀀스 하나) — 매장 ON · 청구처 HQ · P1 2 damaged
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, true)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1', 'order_number', 'SO-HCR1-1', 'invoice_date', public.ims_today() - 30),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 2, 'unit_price', :e_p1_unit, 'not_restocked_reason', 'damaged'))))) as i6 \gset
select pg_temp.j(:'i6')->>'credit_id' as cr1, pg_temp.j(:'i6')->>'credit_number' as cr1_no \gset
select pg_temp.chk('I6 issue (commit): so_credit.customer_id = HQ · store_customer_id = Store ON · warnings column = the returned warnings (jsonb array) · tax HST ON · total = 2 × hist price + 13 %',
  :'i6' not like 'ERR%' and (pg_temp.j(:'i6')->>'committed')::boolean
  and (select c.customer_id::text = :'c_hq' and c.store_customer_id::text = :'c_on' and jsonb_typeof(c.warnings) = 'array' and c.warnings = pg_temp.j(:'i6')->'warnings' and c.tax_rule = 'HST ON (Sale)'
              and c.total = round(2 * :e_p1_unit, 2) + round(round(2 * :e_p1_unit, 2) * 0.13, 2) and c.ref_invoice_number = 'HCR1-INV1'
       from public.so_credit c where c.id = :'cr1'::uuid),
  left(:'i6', 500));
select pg_temp.chk('I7 list · detail · paper: so_credit_list store_name "HCR1 Store ON" · customer_name "HCR1 HQ" · search_text has the store · so_credit_detail store_name + credit.store_customer_id + credit.warnings · doc_data_credit bill = HQ · ship company = Store ON',
  (select l.store_name = 'HCR1 Store ON' and l.customer_name = 'HCR1 HQ' and l.store_customer_id::text = :'c_on' and l.search_text like '%HCR1 Store ON%' from public.so_credit_list l where l.id = :'cr1'::uuid)
  and (select d->>'store_name' = 'HCR1 Store ON' and d->'credit'->>'store_customer_id' = :'c_on' and jsonb_typeof(d->'credit'->'warnings') = 'array' from pg_temp.j(pg_temp.as_user(:'v_uid', format('select public.so_credit_detail(%L::uuid)::text', :'cr1'))) d)
  and (select d->'bill_to'->>'name' = 'HCR1 HQ' and d->'ship_to'->>'company' = 'HCR1 Store ON' from pg_temp.j(pg_temp.run(format('select public.doc_data_credit(%L::uuid, ''{}''::jsonb)::text', :'cr1'))) d),
  format('list %s | detail %s | doc %s', (select format('%s / %s', l.store_name, l.customer_name) from public.so_credit_list l where l.id = :'cr1'::uuid),
         left(pg_temp.as_user(:'v_uid', format('select public.so_credit_detail(%L::uuid)::text', :'cr1')), 200),
         left(regexp_replace(pg_temp.run(format('select public.doc_data_credit(%L::uuid, ''{}''::jsonb)::text', :'cr1')), '.*("bill_to"|"ship_to")', '\1'), 300)));
select pg_temp.as_user(:'v_uid', 'select public.hist_credit_source(''HCR1-INV1'')::text') as s8 \gset
-- I8 둘째 발행(시퀀스 둘) — 다른 손님(HQ2 · 매장 없음) 이 같은 번호 P1 1 → 손님이 달라도 센다
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, true)::text',
  jsonb_build_object('customer_id', :'c_hq2', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'hcr1-inv1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', :e_p1_unit, 'not_restocked_reason', 'damaged'))))) as i8 \gset
select pg_temp.j(:'i8')->>'credit_id' as cr2 \gset
select pg_temp.as_user(:'v_uid', 'select public.hist_credit_source(''HCR1-INV1'')::text') as s9 \gset
select pg_temp.chk('I8 after the first credit P1 qty_ims_credited 2 · remaining 6 · already_credited 1 — after a second credit by another customer (HQ2 · number in lower case · store = itself) credited 3 · remaining 5 · already_credited 2 · store_customer_id = HQ2',
  (select (e->>'qty_ims_credited')::numeric = 2 and (e->>'qty_remaining')::numeric = 6 from jsonb_array_elements(pg_temp.j(:'s8')->'orders'->0->'lines') e where e->>'sku' = 'hcr1-p1')
  and jsonb_array_length(pg_temp.j(:'s8')->'already_credited') = 1 and pg_temp.j(:'s8')->'already_credited'->0->>'store_name' = 'HCR1 Store ON'
  and :'i8' not like 'ERR%' and (select (e->>'qty_ims_credited')::numeric = 3 and (e->>'qty_remaining')::numeric = 5 from jsonb_array_elements(pg_temp.j(:'s9')->'orders'->0->'lines') e where e->>'sku' = 'hcr1-p1')
  and jsonb_array_length(pg_temp.j(:'s9')->'already_credited') = 2 and (select c.store_customer_id::text = :'c_hq2' from public.so_credit c where c.id = :'cr2'::uuid),
  format('s8 %s | i8 %s | s9 %s', left((pg_temp.j(:'s8')->'orders'->0->'lines'->0)::text, 200), left(:'i8', 160), left((pg_temp.j(:'s9')->'orders'->0->'lines'->0)::text, 200)));
select pg_temp.as_user(:'m_uid', format('select public.so_credit_cancel(%L::uuid, ''hcr-1 I9 cancel'')::text', :'cr1')) as i9 \gset
select pg_temp.as_user(:'v_uid', 'select public.hist_credit_source(''HCR1-INV1'')::text') as s10 \gset
select pg_temp.chk('I9 cancel the first credit → cancelled credits are not counted: credited 1 · remaining 7 · already_credited still lists both (status cancelled / issued)',
  :'i9' not like 'ERR%' and (select (e->>'qty_ims_credited')::numeric = 1 and (e->>'qty_remaining')::numeric = 7 from jsonb_array_elements(pg_temp.j(:'s10')->'orders'->0->'lines') e where e->>'sku' = 'hcr1-p1')
  and (select string_agg(a->>'status', ',' order by a->>'credit_number') from jsonb_array_elements(pg_temp.j(:'s10')->'already_credited') a) = 'cancelled,issued',
  format('%s | %s', left(:'i9', 160), left((pg_temp.j(:'s10')->'already_credited')::text, 300)));
-- I10 인보이스 크레딧 경로(ref 아님)는 바이트 그대로 + 매장 = 첫 오더의 손님 — 가짜 IMS 인보이스를 만들지 않고 「인보이스 크레딧 갈래의 코드가 안 바뀌었나」 를 본문 대조로: ref 갈래 밖의 바꾼 줄 = 0
select pg_temp.chk('I10 so_credit_issue body: every hcr-1 line is in the ref branch or the store/record lines (no other line changed) — reissued md5 = landing md5 · old tokens intact (reference_seen · manual_unit_price · _98_ · _99_)',
  (select p.prosrc like '%reference_seen:%' and p.prosrc like '%''manual_unit_price''%' and p.prosrc like '%a.code = ''_98_''%' and p.prosrc like '%a.code = ''_99_''%' and p.prosrc like '%coalesce(v_store, v_cust) and a.type = ''Shipping''%'
          and p.prosrc like '%update public.so_credit c set store_customer_id = v_store, warnings = to_jsonb(v_warn)%' and (select count(*) from regexp_matches(p.prosrc, 'hcr-1', 'g')) >= 8
   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_issue'),
  pg_temp.run('select md5(p.prosrc) from pg_proc p where p.pronamespace = ''public''::regnamespace and p.proname = ''so_credit_issue'''));

-- ── O 옛 동작 무변(이력에 없는 번호) ──
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq2', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-HCR1', 'order_number', 'SO-OLD-HCR1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 2, 'unit_price', 9.99, 'not_restocked_reason', 'damaged'), jsonb_build_object('kind', 'freight', 'amount', 10))))) as o1 \gset
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_no', 'reason', 'damaged', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-HCR1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'damaged'))))) as o2 \gset
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_on', 'reason', 'damaged', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-HCR1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'damaged'))))) as o3 \gset
select pg_temp.as_user(:'m_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'reason', 'damaged', 'cin7', jsonb_build_object('invoice_number', 'INV-OLD-HCR1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'damaged'))))) as o4 \gset
select pg_temp.chk('O1 number not in history: ship_to tax (HST ON · source ship_to) · warnings manual_unit_price (always) + reference_not_in_history · no qty_over_sold · freight _99_ 10 + 1.30 · totals 19.98 + 10 + 3.90',
  :'o1' not like 'ERR%' and pg_temp.j(:'o1')->'origin'->>'tax_rule' = 'HST ON (Sale)' and pg_temp.j(:'o1')->'origin'->>'tax_rule_source' = 'ship_to'
  and pg_temp.hasw(:'o1', 'manual_unit_price') and pg_temp.hasw(:'o1', 'reference_not_in_history') and not pg_temp.hasw(:'o1', 'qty_over_sold%') and not pg_temp.hasw(:'o1', 'not_on_invoice%')
  and pg_temp.j(:'o1')->'lines'->1->>'account_code' = '_99_' and (pg_temp.j(:'o1')->'totals'->>'lines_amount')::numeric = 29.98 and (pg_temp.j(:'o1')->'totals'->>'tax_amount')::numeric = 3.90,
  left(:'o1', 600));
select pg_temp.chk('O2 customer without default ship-to → "Pick a tax rule — the customer has no default ship-to" (unchanged) · HQ (no ship-to) + store ON → tax from the STORE''s ship-to (HST ON) · old cin7 key → "The cin7 key is gone" (unchanged)',
  :'o2' like 'ERR%' and :'o2' like '%Pick a tax rule — the customer has no default ship-to%'
  and :'o3' not like 'ERR%' and pg_temp.j(:'o3')->'origin'->>'tax_rule' = 'HST ON (Sale)' and pg_temp.j(:'o3')->'origin'->>'tax_rule_source' = 'ship_to'
  and :'o4' like 'ERR%' and :'o4' like '%The cin7 key is gone%',
  format('%s | %s | %s', left(:'o2', 140), left(:'o3', 200), left(:'o4', 120)));

-- ── P 권한: sales 보기만 · sales 쓰기(worker) · manager ──
select pg_temp.as_user(:'v_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', :e_p1_unit, 'not_restocked_reason', 'damaged'))))) as p1 \gset
select pg_temp.as_user(:'w_uid', format('select public.so_credit_issue(%L::jsonb, false)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', :e_p1_unit, 'not_restocked_reason', 'damaged'))))) as p2 \gset
select pg_temp.as_user(:'w_uid', format('select public.so_credit_issue(%L::jsonb, true)::text',
  jsonb_build_object('customer_id', :'c_hq', 'store_customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'HCR1-INV1'),
                     'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'HCR1-P1', 'qty_returned', 1, 'unit_price', :e_p1_unit, 'not_restocked_reason', 'damaged'))))) as p3 \gset
select pg_temp.as_user(:'w_uid', 'select public.hist_credit_source(''HCR1-INV1'')::text') as p4 \gset
select pg_temp.chk('P1 sales:read (V): source OK · issue preview refused ("cannot change sales data") / sales worker (W): source OK · preview and issue both refused ("manager or above" — so_require_role is the second line, before p_commit · unchanged) — gates unchanged',
  :'p1' like 'ERR%' and :'p1' like '%cannot change sales data%' and :'p2' like 'ERR%' and :'p2' like '%manager or above%' and :'p3' like 'ERR%' and :'p3' like '%manager or above%' and (pg_temp.j(:'p4')->>'found')::boolean,
  format('%s | %s | %s', left(:'p1', 120), left(:'p2', 60), left(:'p3', 120)));

-- ── Z ──
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select name, left(detail, 1200) as detail from t_res where not ok;
select 'OK ' || name as line from t_res where ok order by n;
select 'MISMATCH (' || name || '): ' || left(detail, 600) as line from t_res where not ok order by n;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── rollback 뒤 — 실제 행 무변 · 가짜 흔적 0 · 시퀀스 greatest(실제 최대, 머리)'
select (select count(*) from public.so_credit) = :n_cr as cr_same, (select count(*) from public.so_credit_line) = :n_crl as crl_same, (select count(*) from public.ims_staff) = :n_staff as staff_same,
       (select count(*) from public.customer) = :n_cust as cust_same, (select count(*) from public.product) = :n_prod as prod_same, (select count(*) from public.hist_so) = :n_hso as hso_same,
       (select count(*) from public.hist_so_line) = :n_hsl as hsl_same, (select count(*) from public.customer_address) = :n_addr as addr_same,
       (select count(*) from public.customer where name like 'HCR1 %') + (select count(*) from public.product where sku like 'HCR1-%') + (select count(*) from public.ims_staff where email like 'hcr1-%') + (select count(*) from public.hist_so where order_number like 'SO-HCR1-%') as fake_traces;
select setval('public.so_credit_number_seq', greatest(coalesce((select max(substring(credit_number from '[0-9]+')::bigint) from public.so_credit), 0), :cr_seq_last), :'cr_seq_called'::boolean) as so_credit_number_seq_reset_to;
