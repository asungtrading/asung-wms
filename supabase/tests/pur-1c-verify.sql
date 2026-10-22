-- pur-1c-verify.sql — 발주앱 재고 읽기 창구 pur_stock()(판정 604 · 608 · 615):
--   같음(stk_availability 전 쪽을 화면 규칙으로 접은 것 ↔ pur_stock · 같은 문장 = 같은 스냅샷 · SKU × 브랜치 × 다섯 칸) · 시간(한 번 · 첫 쪽 · 전 쪽) · 권한(purchasing 있음 · 없음 · anon · has_function_privilege) · 무접촉(stk_availability · inv_available_base md5)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261022161832_pur_1c_stock_window.sql -f supabase/tests/pur-1c-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 둘은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 OK 8 − 2 + 1 = **7** · MISMATCH 0
--   시험 재료 없음(읽기 창구 · 실제 행만 읽는다) — 직원 신원 둘만 가짜(ims_staff 두 행 · 되감긴다 · 시퀀스 무접촉) · ⚠️ 전 쪽 대조는 16 쪽 × 전체 계산이라 50 초쯤 걸린다

\echo '── db_role · schema_migrations'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261022161832' \gset
select :n_applied as schema_migrations_rows_for_20261022161832;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.as_role(p_role text, p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  if p_claims is not null then perform set_config('request.jwt.claims', p_claims, true); end if;
  execute p_sql into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then
  reset role;
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.fns() returns text language sql security definer as $$
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stk_availability', 'inv_available_base', 'pur_staff') $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'pur_stock=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_stock')::text $$;

\echo '── M0) 가짜 직원 신원 둘(W purchasing · N 없음) · 무접촉 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pur1c-w@test.invalid', 'PUR1C W', 'manager', '["ims","purchasing"]', '{}') returning auth_user_id::text as w_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pur1c-n@test.invalid', 'PUR1C N', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as n_uid \gset
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
\set n '{"sub":"' :n_uid '","role":"authenticated"}'
select pg_temp.fns() as fns_before, pg_temp.gate_state() as gate_before \gset
select pg_temp.chk(format('M0 staff W · N · snapshot (%s)', :'gate_before'), :'w_uid' <> '' and :'n_uid' <> '' and :'fns_before' like '%stk_availability=97a3160d2f7a1aaadecbbc9924c65b86%' and :'fns_before' like '%inv_available_base=fd141ec16a8b98aad23eb1b17dadc0ab%', :'fns_before');

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — pur_stock 없음'
select pg_temp.chk('S0 before the trial: no pur_stock · not in schema_migrations', :'gate_before' = 'pur_stock=0' and :n_applied = 0, :'gate_before');
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: stk_availability · inv_available_base · pur_staff md5 unchanged', pg_temp.fns() = :'fns_before', format('before %s | after %s', :'fns_before', pg_temp.fns()));
\else
select pg_temp.chk('P0c confirm run: migration 20261022161832 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() = 'pur_stock=1') as landed \gset
\if :landed
\echo '── G1) 실물 — definer · stable · search_path · ACL(authenticated 만 · public · anon · service_role 없음)'
select pg_temp.chk('G1 pur_stock(): one overload · security definer · stable · search_path public,pg_temp · execute = authenticated only (public · anon · service_role none)',
  (select p.prosecdef and p.provolatile = 's' and p.proconfig::text like '%search_path=public, pg_temp%' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_stock')
  and has_function_privilege('authenticated', 'public.pur_stock()', 'execute') and not has_function_privilege('anon', 'public.pur_stock()', 'execute')
  and not has_function_privilege('service_role', 'public.pur_stock()', 'execute') and (select p.proacl::text !~ '[{,]=X' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_stock'),
  (select p.proacl::text || ' ' || p.provolatile::text || ' ' || p.prosecdef::text || ' ' || coalesce(p.proconfig::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_stock'));

\echo '── T1) 같음 — 같은 문장(같은 스냅샷): stk_availability 전 쪽(500 × 쪽 돌기 · include_zero false)을 화면 규칙으로 접은 것 ↔ pur_stock.rows · SKU × 브랜치 × 다섯 칸'
select set_config('request.jwt.claims', :'w', true) as claims_w;
with pages as (
  select s.sku, s.product_id, s.by_warehouse from generate_series(0, 50000, 500) g(o) cross join lateral public.stk_availability(null, null, null, null, false, 500, g.o) s
),
a as (                                                                                    -- 화면 purLoadStock 의 접기 — 이름에 edmonton → edm · 그 밖 → tor · alloc = sales_allocated + transfer_reserved
  select p.sku, p.product_id, case when lower(w->>'warehouse') like '%edmonton%' then 'edm' else 'tor' end as br,
         sum((w->>'on_hand')::numeric) as qoh, sum((w->>'sales_allocated')::numeric + (w->>'transfer_reserved')::numeric) as alloc,
         sum((w->>'on_order')::numeric) as oo, sum((w->>'in_transit')::numeric) as it, sum((w->>'available')::numeric) as avail
  from pages p cross join lateral jsonb_array_elements(p.by_warehouse) w group by 1, 2, 3
),
ps as (select public.pur_stock() as j),
b as (
  select r->>'sku' as sku, (r->>'product_id')::uuid as product_id, k.br,
         (r->k.br->>'qoh')::numeric as qoh, (r->k.br->>'alloc')::numeric as alloc, (r->k.br->>'oo')::numeric as oo, (r->k.br->>'it')::numeric as it, (r->k.br->>'avail')::numeric as avail
  from ps cross join lateral jsonb_array_elements(ps.j->'rows') r cross join (values ('tor'), ('edm')) k(br)
),
cmp as (
  select coalesce(a.sku, b.sku) as sku, coalesce(a.br, b.br) as br, a.sku is null as only_b, b.sku is null as only_a,
         (a.product_id is distinct from b.product_id or a.qoh is distinct from b.qoh or a.alloc is distinct from b.alloc or a.oo is distinct from b.oo or a.it is distinct from b.it or a.avail is distinct from b.avail) as differs,
         a.qoh as aq, b.qoh as bq, a.alloc as aa, b.alloc as ba, a.oo as ao, b.oo as bo, a.it as ai, b.it as bi, a.avail as av, b.avail as bv
  from a full outer join b on b.sku = a.sku and b.br = a.br
)
select (select count(distinct sku) from a) as a_skus, (select count(*) from a) as a_cells, (select (j->>'row_count')::int from ps) as b_rows, (select count(*) from b) as b_cells,
       (select count(*) from cmp where only_a) as only_in_stk, (select count(*) from cmp where only_b) as only_in_pur, (select count(*) from cmp where not only_a and not only_b and differs) as differ,
       (select coalesce(string_agg(sku || '/' || br || ' stk ' || coalesce(aq::text, '-') || '|' || coalesce(aa::text, '-') || '|' || coalesce(ao::text, '-') || '|' || coalesce(ai::text, '-') || '|' || coalesce(av::text, '-') || ' pur ' || coalesce(bq::text, '-') || '|' || coalesce(ba::text, '-') || '|' || coalesce(bo::text, '-') || '|' || coalesce(bi::text, '-') || '|' || coalesce(bv::text, '-'), ' ; '), '-') from (select * from cmp where only_a or only_b or differs order by sku, br limit 5) x) as samples
\gset
select pg_temp.chk(format('T1 same set and numbers — stk_availability %s SKUs / %s cells (all pages) vs pur_stock %s rows / %s cells · only in stk %s · only in pur %s · differing cells %s', :a_skus, :a_cells, :b_rows, :b_cells, :only_in_stk, :only_in_pur, :differ),
  :a_skus > 0 and :a_skus = :b_rows and :a_cells = :b_cells and :only_in_stk = 0 and :only_in_pur = 0 and :differ = 0, coalesce(:'samples', '-'));

\echo '── T2) 시간 — pur_stock 한 번 · stk_availability 첫 쪽 · 전 쪽(500 × 16) · 응답 크기(반환값을 써서 잰다)'
select clock_timestamp() as t_a \gset
select length(public.pur_stock()::text) as pur_bytes \gset
select extract(epoch from clock_timestamp() - :'t_a'::timestamptz)::numeric(10, 3) as pur_stock_s \gset
select clock_timestamp() as t_b \gset
select sum(length(by_warehouse::text)) as page1_bytes from public.stk_availability(null, null, null, null, false, 500, 0) \gset
select extract(epoch from clock_timestamp() - :'t_b'::timestamptz)::numeric(10, 3) as page1_s \gset
select clock_timestamp() as t_c \gset
select count(*) as all_rows, sum(length(by_warehouse::text)) as all_bytes from (select s.by_warehouse from generate_series(0, 50000, 500) g(o) cross join lateral public.stk_availability(null, null, null, null, false, 500, g.o) s) x \gset
select extract(epoch from clock_timestamp() - :'t_c'::timestamptz)::numeric(10, 3) as all_pages_s \gset
select pg_temp.chk(format('T2 time — pur_stock once %s s (%s bytes · target < 2 s) · stk_availability first page %s s · all %s rows over %s pages serial %s s', :pur_stock_s, :pur_bytes, :page1_s, :all_rows, ceil(:all_rows / 500.0)::int, :all_pages_s),
  :pur_stock_s < 2 and :pur_bytes > 0, format('pur_stock %s s · page1 %s s · all pages %s s', :pur_stock_s, :page1_s, :all_pages_s));

\echo '── T3) 권한 — W(purchasing) 성공 · N(없음) 거부 · anon 42501 · 실행권 public · anon 없음'
select set_config('request.jwt.claims', '', true) as claims_cleared;
select pg_temp.as_role('authenticated', :'w', 'select (public.pur_stock()->>''row_count'')') as t3w \gset
select pg_temp.as_role('authenticated', :'n', 'select (public.pur_stock()->>''row_count'')') as t3n \gset
select pg_temp.as_role('anon', null, 'select (public.pur_stock()->>''row_count'')') as t3a \gset
select pg_temp.chk(format('T3 W (purchasing) → row_count %s · N (no purchasing) → "%s" · anon → 42501 · has_function_privilege public · anon = false', :'t3w', left(:'t3n', 90)),
  :'t3w' ~ '^[0-9]+$' and :'t3w'::int = :b_rows and :'t3n' like 'ERR P0001: You cannot view purchasing data%' and :'t3a' like 'ERR 42501:%'
  and not has_function_privilege('anon', 'public.pur_stock()', 'execute') and (select p.proacl::text !~ '[{,]=X' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_stock'),
  format('%s | %s | %s', left(:'t3w', 60), left(:'t3n', 160), left(:'t3a', 120)));
\else
select pg_temp.chk('G1 ~ T3 skipped: pur-1c not landed', false, pg_temp.gate_state());
\endif

\echo '── Z1) 무접촉'
select pg_temp.chk('Z1 stk_availability · inv_available_base · pur_staff md5 unchanged · pur_stock count', pg_temp.fns() = :'fns_before', format('before %s | after %s', :'fns_before', pg_temp.fns()));

rollback;
\echo '── rollback 뒤 — 가짜 신원 0'
select (select count(*) from public.ims_staff where email like 'pur1c-%') as leftovers;
