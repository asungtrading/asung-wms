-- supabase/tests/wms_balance_perf_2c_capture.sql — wms-balance-perf-2c ②-c(deferred 450) 결과 받기(파일 diff 용 · 앞 캡처들과 같은 꼴) (2026-11-02)
-- [메인 IMS · Asung-IMS] 트랜잭션 없음(문장마다 자동 커밋 읽기 · 세션 read only) · 지문 머리 · 꼬리
--   입력 = so_sale_now 2 인자 꼴만(옛 · 새 모두 있는 서명: (null, null) · (세일 제품 20) · (null, 날짜) · 이름 인자 꼴) · stk_availability(Both · 토론토 · 에드먼턴 × zero off · on 100 · 세일만 · q UNF · 내보내기 꼴 20000) · stk_availability_export(Both zero on)
--   Claude Code(적용 전): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v out=<파일> -f supabase/tests/wms_balance_perf_2c_capture.sql
--   Caleb(적용 뒤): 같은 명령에 다른 out → diff <옛> <새>  (기대 차이 = 첫 FP 줄의 functions md5 · so_sale_now 서명 뿐)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
create temp table t_in (ord serial, name text, sql text);
set default_transaction_read_only = on;
set statement_timeout = '30s';
select set_config('request.jwt.claim.sub', s.auth_user_id::text, false), set_config('request.jwt.claims', json_build_object('sub', s.auth_user_id, 'role', 'authenticated')::text, false)
  from (select auth_user_id from public.ims_staff where is_active and auth_user_id is not null and role = 'admin' order by created_at limit 1) s;
\o :out
select 'FP ' || (select max(id) from public.inv_ledger) || '/' || (select count(*) from public.so_deal) || '/' || (select count(*) from public.so_deal_line) || '/' || (select count(*) from public.so_deal_target) || '/' || (select count(*) from public.so_reserve where released_at is null) || ' functions ' ||
       (select string_agg(p.proname || '=' || md5(p.prosrc) || '(' || pg_get_function_identity_arguments(p.oid) || ')', ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_sale_now', 'stk_availability'));
insert into t_in (name, sql) values
  ('SALE null null', 'select ''SALE null null '' || coalesce(jsonb_agg(to_jsonb(z) order by z.product_id), ''[]'')::text from public.so_sale_now(null, null) z'),
  ('SALE 20 products', format('select ''SALE 20 products '' || coalesce(jsonb_agg(to_jsonb(z) order by z.product_id), ''[]'')::text from public.so_sale_now(%L::uuid[], null) z', (select array_agg(x.product_id) from (select z.product_id from public.so_sale_now(null, null) z order by z.conditional desc, z.best_pct desc, z.product_id limit 20) x))),
  ('SALE null date', format('select ''SALE null date '' || coalesce(jsonb_agg(to_jsonb(z) order by z.product_id), ''[]'')::text from public.so_sale_now(null, %L::date) z', (select coalesce(max(x.date_from), public.ims_today()) from public.so_deal x where x.is_active and x.kind = 'pct'))),
  ('SALE named args', format('select ''SALE named args '' || coalesce(jsonb_agg(to_jsonb(z) order by z.product_id), ''[]'')::text from public.so_sale_now(p_product_ids => %L::uuid[], p_on => null) z', (select array_agg(x.product_id) from (select z.product_id from public.so_sale_now(null, null) z order by z.product_id limit 5) x)));
insert into t_in (name, sql)
  select 'STK ' || k.lbl, format('select %L || '' '' || coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'')::text from public.stk_availability(%s, %L, null, null, %s, %s, 0, %s, null) with ordinality r', 'STK ' || k.lbl, k.wh, k.q, k.zero, k.lim, k.sale)
  from (
    select w.lbl || ' zero ' || z.lbl || ' 100' as lbl, w.wh, 'null'::text as q, z.v as zero, '100' as lim, 'false' as sale
    from (values ('Both', 'null'), ('Toronto', (select quote_literal(id) || '::uuid' from public.ref_warehouse where name = 'Asung Trading Inc.')), ('Edmonton', (select quote_literal(id) || '::uuid' from public.ref_warehouse where name = 'Asung - Edmonton'))) w(lbl, wh)
    cross join (values ('off', 'false'), ('on', 'true')) z(lbl, v)
    union all select 'Both q UNF zero on 500', 'null', 'UNF', 'true', '500', 'false'
    union all select 'Both sale only zero on 100', 'null', 'null', 'true', '100', 'true'
    union all select 'Both export shape zero on 20000', 'null', 'null', 'true', '20000', 'false'
  ) k order by k.lbl;
insert into t_in (name, sql) values ('EXPORT Both zero on', 'select ''EXPORT Both zero on '' || public.stk_availability_export(null, null, null, null, true, false, null)::text');
select 'INPUT ' || ord || ' ' || name from t_in order by ord;
\timing on
select sql from t_in order by ord \gexec
\timing off
select 'FP ' || (select max(id) from public.inv_ledger) || '/' || (select count(*) from public.so_deal) || '/' || (select count(*) from public.so_deal_line) || '/' || (select count(*) from public.so_deal_target) || '/' || (select count(*) from public.so_reserve where released_at is null) || ' (end)';
select 'inputs ' || count(*) from t_in;
