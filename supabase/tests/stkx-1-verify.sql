-- stkx-1-verify.sql — Stock Availability 내보내기 · stk_availability 한도 500 → 20000 + stk_availability_export(jsonb 한 행)(판정 628):
--   T1 동일성(옛 함수 = 새 함수 · 거르기 여덟 가지 · 줄마다 · 시험 갈래) · T2 큰 한 번(20000 의 행 수 = 첫 줄 total = 500 씩 쪽을 합친 것 · 같은 문장) · T3 내보내기 창구(한 행 · row_count = total · 칸 = 화면 칸 · anon 42501) · Z1 다른 stk_ md5 무변
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261022193830_stkx_1_availability_export.sql -f supabase/tests/stkx-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · T1 셋은 확인 갈래에 없고 P0c 한 줄이 찍힌다 ⇒ 확인 갈래 OK 줄 = M0 · P0c · G1 · T2 · T3 · Z1 = **6** · MISMATCH 0
--   가짜 재료 = 직원 신원 하나(STKX1 · 되감긴다) · 읽기 창구라 실제 행만 읽는다 · ⚠️ T2 의 쪽 돌기(500 × 16)가 1 분쯤 걸린다

\echo '── db_role · schema_migrations'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261022193830' \gset
select :n_applied as schema_migrations_rows_for_20261022193830;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
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
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('stk_bins', 'stk_bins_many', 'stk_movements', 'stk_reserved', 'stk_value_many', 'stk_value_total', 'inv_available_base', 'so_sale_now', 'pur_stock') $$;
create function pg_temp.alen(p jsonb) returns int language sql immutable as $$ select case when jsonb_typeof(p) = 'array' then jsonb_array_length(p) else 0 end $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'md5=' || (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stk_availability')
      || ' n=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stk_availability')
      || ' acl=' || (select p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stk_availability')
      || ' export=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stk_availability_export') $$;
-- 거르기 여덟 가지를 한 번에 — 각각 jsonb 배열(줄 순서 = 함수 순서) · 같은 문장 = 같은 스냅샷
create function pg_temp.runs(p_wh uuid, p_brand uuid, p_sup uuid) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'p100_0',   (select jsonb_agg(to_jsonb(r)) from public.stk_availability(null, null, null, null, false, 100, 0) r),
    'p100_100', (select jsonb_agg(to_jsonb(r)) from public.stk_availability(null, null, null, null, false, 100, 100) r),
    'q',        (select jsonb_agg(to_jsonb(r)) from public.stk_availability(null, 'AAL', null, null, false, 100, 0) r),
    'brand',    (select jsonb_agg(to_jsonb(r)) from public.stk_availability(null, null, p_brand, null, false, 100, 0) r),
    'supplier', (select jsonb_agg(to_jsonb(r)) from public.stk_availability(null, null, null, null, false, 100, 0, false, p_sup) r),
    'sale',     (select jsonb_agg(to_jsonb(r)) from public.stk_availability(null, null, null, null, false, 100, 0, true) r),
    'zero',     (select jsonb_agg(to_jsonb(r)) from public.stk_availability(null, null, null, null, true, 100, 0) r),
    'one_wh',   (select jsonb_agg(to_jsonb(r)) from public.stk_availability(p_wh, null, null, null, false, 100, 0) r)) $$;

\echo '── M0) 직원 신원 · 거르기 재료(실제 브랜드 · 공급처 하나) · 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'stkx1-w@test.invalid', 'STKX1 W', 'manager', '["ims","purchasing"]', '{}') returning auth_user_id::text as w_uid \gset
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
select set_config('request.jwt.claims', :'w', true) as claims;
select id::text as wh from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as brand from public.ref_brand b where exists (select 1 from public.product p where p.brand_id = b.id and p.parent_product_id is null) order by b.name limit 1 \gset
select s.id::text as sup from public.supplier s where exists (select 1 from public.product_supplier ps where ps.supplier_id = s.id and ps.is_active) order by s.name limit 1 \gset
select pg_temp.fns() as fns_before, pg_temp.gate_state() as gate_before \gset
select pg_temp.chk(format('M0 staff W · warehouse %s · brand %s · supplier %s · snapshot (%s)', left(:'wh', 8), left(:'brand', 8), left(:'sup', 8), left(:'gate_before', 60)), :'w_uid' <> '' and :'wh' <> '' and :'brand' <> '' and :'sup' <> '' and :'fns_before' <> '', :'gate_before');

\if :{?mig}
\echo '── S0 · D-pre) 결함 판 — 옛 몸(한도 500) · 내보내기 창구 없음 · 옛 결과 여덟 가지 담기'
select pg_temp.runs(:'wh'::uuid, :'brand'::uuid, :'sup'::uuid)::text as pre \gset
select (select count(*) from public.stk_availability(null, null, null, null, false, 20000, 0)) as pre_big \gset
select pg_temp.chk(format('S0 before the trial: body = stk-av-1 (97a3160d…) · no export window · p_limit 20000 is capped at 500 (%s rows) · eight old results captured', :pre_big),
  :'gate_before' = 'md5=97a3160d2f7a1aaadecbbc9924c65b86 n=1 acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} export=0' and :n_applied = 0 and :pre_big = 500 and pg_temp.j(:'pre') ? 'one_wh',
  format('%s | big %s', :'gate_before', :pre_big));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: other stk_ · inv_available_base · so_sale_now · pur_stock md5 unchanged', pg_temp.fns() = :'fns_before', format('before %s | after %s', left(:'fns_before', 300), left(pg_temp.fns(), 300)));
\echo '── T1) 동일성 — 거르기 여덟 가지 · 줄마다 같다'
select pg_temp.runs(:'wh'::uuid, :'brand'::uuid, :'sup'::uuid)::text as post \gset
select pg_temp.chk(format('T1 old = new, line by line, for eight filter sets (rows: %s)', (select string_agg(k || '=' || pg_temp.alen(pg_temp.j(:'post')->k), ' ' order by k) from jsonb_object_keys(pg_temp.j(:'post')) k)),
  pg_temp.j(:'pre') = pg_temp.j(:'post') and pg_temp.alen(pg_temp.j(:'post')->'p100_0') = 100 and pg_temp.alen(pg_temp.j(:'post')->'p100_100') = 100 and pg_temp.alen(pg_temp.j(:'post')->'one_wh') >= 1,
  (select string_agg(k || ': ' || pg_temp.alen(pg_temp.j(:'pre')->k) || ' vs ' || pg_temp.alen(pg_temp.j(:'post')->k), ' ') from jsonb_object_keys(pg_temp.j(:'post')) k where pg_temp.j(:'pre')->k is distinct from pg_temp.j(:'post')->k));
\else
select pg_temp.chk('P0c confirm run: migration 20261022193830 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() like 'md5=fd12bcc1280c2bc952490d240cd58f05 n=1 %export=1') as landed \gset
\if :landed
\echo '── G1) 실물'
select pg_temp.chk('G1 stk_availability body = stkx-1 (fd12bcc1…) · one overload · ACL unchanged · definer · stable · export window: authenticated only (anon · service_role · public none) · definer · stable',
  pg_temp.gate_state() = 'md5=fd12bcc1280c2bc952490d240cd58f05 n=1 acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} export=1'
  and (select p.prosecdef and p.provolatile = 's' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stk_availability')
  and (select p.prosecdef and p.provolatile = 's' and p.proacl::text !~ 'anon=' and p.proacl::text !~ 'service_role=' and p.proacl::text !~ '[{,]=X' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stk_availability_export')
  and has_function_privilege('authenticated', 'public.stk_availability_export(uuid, text, uuid, uuid, boolean, boolean, uuid)', 'execute'),
  pg_temp.gate_state());

\echo '── T2) 큰 한 번 = 쪽 합(같은 문장 · 같은 스냅샷) · 행 수 = 첫 줄 total'
select clock_timestamp() as t0 \gset
with big as (select to_jsonb(r) - 'total' as j, r.total, r.sku, r.product_id from public.stk_availability(null, null, null, null, false, 20000, 0) r),
     pages as (select to_jsonb(r) - 'total' as j, r.sku, r.product_id from generate_series(0, 50000, 500) g(o) cross join lateral public.stk_availability(null, null, null, null, false, 500, g.o) r)
select (select count(*) from big) as big_rows, (select max(total) from big) as big_total, (select count(*) from pages) as page_rows,
       (select jsonb_agg(j order by sku, product_id) from big) = (select jsonb_agg(j order by sku, product_id) from pages) as same_rows,
       (select count(*) from big b full join pages p on p.product_id = b.product_id where b.product_id is null or p.product_id is null) as unmatched \gset
select extract(epoch from clock_timestamp() - :'t0'::timestamptz)::numeric(10, 1) as t2_s \gset
select pg_temp.chk(format('T2 one call with p_limit 20000 → %s rows = first-row total %s = 500-row pages joined (%s rows · %s unmatched) · identical rows · %s s for both paths', :big_rows, :big_total, :page_rows, :unmatched, :t2_s),
  :big_rows = :big_total and :big_rows = :page_rows and :'same_rows' = 't' and :unmatched = 0 and :big_rows > 500, format('big %s total %s pages %s same %s unmatched %s', :big_rows, :big_total, :page_rows, :'same_rows', :unmatched));

\echo '── T3) 내보내기 창구 — 한 행 · row_count = total · 칸 = 화면 칸(total 없음) · 크기 · 시간 · anon 42501'
select clock_timestamp() as t1 \gset
select pg_temp.as_role('authenticated', :'w', 'select public.stk_availability_export(null)::text') as ex \gset
select extract(epoch from clock_timestamp() - :'t1'::timestamptz)::numeric(10, 2) as ex_s \gset
select pg_temp.as_role('anon', null, 'select public.stk_availability_export(null)::text') as ex_anon \gset
select pg_temp.chk(format('T3 export(null): one jsonb · total %s = row_count %s = T2 big rows · truncated false · row keys = stk columns minus total (%s) · %s bytes · %s s · anon → 42501', pg_temp.j(:'ex')->>'total', pg_temp.j(:'ex')->>'row_count', (select count(*) from jsonb_object_keys(pg_temp.j(:'ex')->'rows'->0)), length(:'ex'), :ex_s),
  (pg_temp.j(:'ex')->>'total')::int = (pg_temp.j(:'ex')->>'row_count')::int and (pg_temp.j(:'ex')->>'row_count')::int = :big_rows and not (pg_temp.j(:'ex')->>'truncated')::boolean
  and (select string_agg(k, ',' order by k) from jsonb_object_keys(pg_temp.j(:'ex')->'rows'->0) k) = 'available,brand_id,brand_name,by_warehouse,category_id,category_name,in_transit,is_active,last_event_on,matched_set_count,matched_set_pack_factor,matched_set_sku,name,on_hand,on_order,product_id,sale_conditional,sale_pct,sales_allocated,sku,transfer_reserved'
  and :'ex_anon' like 'ERR 42501:%',
  format('%s | anon %s', left(:'ex', 300), left(:'ex_anon', 100)));
\else
select pg_temp.chk('G1 ~ T3 skipped: stkx-1 not landed', false, pg_temp.gate_state());
\endif

\echo '── Z1) 무접촉'
select pg_temp.chk('Z1 other stk_ · inv_available_base · so_sale_now · pur_stock md5 unchanged', pg_temp.fns() = :'fns_before', format('before %s | after %s', left(:'fns_before', 300), left(pg_temp.fns(), 300)));

rollback;
\echo '── rollback 뒤 — 가짜 신원 0'
select (select count(*) from public.ims_staff where email like 'stkx1-%') as leftovers;
