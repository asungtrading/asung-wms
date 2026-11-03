-- supabase/tests/wms_balance_perf_2b_capture.sql — wms-balance-perf-2b ②-b(deferred 450) 결과 받기(파일 diff 용 · ① · ②-a · ③ 캡처와 같은 꼴) (2026-11-02)
-- [메인 IMS · Asung-IMS] 트랜잭션 없음(문장마다 자동 커밋 읽기 · 세션 read only) · 지문 머리 · 꼬리(다르면 그 입력의 옛 결과를 다시 받는다)
--   입력 = stk_availability: Both · 토론토 · 에드먼턴 × Zero stock off · on × 100 줄 · 2 쪽 · 3 쪽 · 500 줄 · 검색 UNF · 세일만 · 브랜드 · 공급처 · 내보내기 꼴 20,000(함수 직접) · stk_availability_export(Both zero on · 토론토 zero off) — 줄 순서까지(with ordinality)
--   Claude Code(적용 전): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v out=<파일> -f supabase/tests/wms_balance_perf_2b_capture.sql   (호출마다 ms 는 stdout 의 Time: 줄)
--   Caleb(적용 뒤): 같은 명령에 다른 out → diff <옛> <새>  (기대 차이 = 첫 FP 줄의 functions md5 뿐)
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
select 'FP ' || (select max(id) from public.inv_ledger) || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.so_reserve where released_at is null) || '/' || (select count(*) from public.po_line) || '/' || (select count(*) from public.inv_transfer_line) || ' functions ' ||
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stk_availability', 'stk_availability_export'));
insert into t_in (name, sql)
  select 'STK ' || k.lbl, format('select %L || '' '' || coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'')::text from public.stk_availability(%s, %L, %s, null, %s, %s, %s, %s, %s) with ordinality r', 'STK ' || k.lbl, k.wh, k.q, k.brand, k.zero, k.lim, k.off, k.sale, k.sup)
  from (
    select w.lbl || ' zero ' || z.lbl || ' 100' as lbl, w.wh, 'null'::text as q, 'null' as brand, z.v as zero, '100' as lim, '0' as off, 'false' as sale, 'null' as sup
    from (values ('Both', 'null'), ('Toronto', (select quote_literal(id) || '::uuid' from public.ref_warehouse where name = 'Asung Trading Inc.')), ('Edmonton', (select quote_literal(id) || '::uuid' from public.ref_warehouse where name = 'Asung - Edmonton'))) w(lbl, wh)
    cross join (values ('off', 'false'), ('on', 'true')) z(lbl, v)
    union all select 'Both zero off page 2', 'null', 'null', 'null', 'false', '100', '100', 'false', 'null'
    union all select 'Both zero off page 3', 'null', 'null', 'null', 'false', '100', '200', 'false', 'null'
    union all select 'Both zero off 500', 'null', 'null', 'null', 'false', '500', '0', 'false', 'null'
    union all select 'Both q UNF zero on 500', 'null', 'UNF', 'null', 'true', '500', '0', 'false', 'null'
    union all select 'Both sale only zero on 100', 'null', 'null', 'null', 'true', '100', '0', 'true', 'null'
    union all select 'Both brand zero on 100', 'null', 'null', (select quote_literal(p.brand_id) || '::uuid' from public.product p where p.brand_id is not null and p.parent_product_id is null group by p.brand_id order by count(*) desc limit 1), 'true', '100', '0', 'false', 'null'
    union all select 'Both supplier zero on 100', 'null', 'null', 'null', 'true', '100', '0', 'false', (select quote_literal(ps.supplier_id) || '::uuid' from public.product_supplier ps where ps.is_active group by ps.supplier_id order by count(*) desc limit 1)
    union all select 'Both export shape zero on 20000', 'null', 'null', 'null', 'true', '20000', '0', 'false', 'null'
  ) k order by k.lbl;
insert into t_in (name, sql) values
  ('EXPORT Both zero on', 'select ''EXPORT Both zero on '' || public.stk_availability_export(null, null, null, null, true, false, null)::text'),
  ('EXPORT Toronto zero off', format('select ''EXPORT Toronto zero off '' || public.stk_availability_export(%L::uuid, null, null, null, false, false, null)::text', (select id from public.ref_warehouse where name = 'Asung Trading Inc.')));
select 'INPUT ' || ord || ' ' || name from t_in order by ord;
\timing on
select sql from t_in order by ord \gexec
\timing off
select 'FP ' || (select max(id) from public.inv_ledger) || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.so_reserve where released_at is null) || '/' || (select count(*) from public.po_line) || '/' || (select count(*) from public.inv_transfer_line) || ' (end)';
select 'inputs ' || count(*) from t_in;
