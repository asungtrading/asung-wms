-- supabase/tests/wms_balance_perf_2a_capture.sql — wms-balance-perf-2a ②-a(deferred 450) 결과 받기(파일 diff 용 · ① 캡처와 같은 꼴) (2026-11-02)
-- [메인 IMS · Asung-IMS] 옛 결과(적용 전)와 새 결과(적용 뒤)를 같은 입력으로 파일에 받아 diff — 트랜잭션 없음(문장마다 자동 커밋 읽기 · 세션 read only) · 지문 머리 · 꼬리(다르면 그 입력의 옛 결과를 다시 받는다)
--   입력 = inv_available_base (창고, null) × 2 · (창고, sharp) × 2 · so_available_many(picking · confirmed · at_wms 오더마다 그 오더의 재고 키 · 그 창고) · shop_stock_payload(스토어마다 전체 · 전체 스토어 sharp) ·
--          stk_availability(Both · 토론토 · 에드먼턴 × zero off · on 100 · export Both 20000 · q UNF 500 · sale only) — 직원 문은 request.jwt.claims 에 활성 직원 sub
--   Claude Code(적용 전): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v out=<파일> -f supabase/tests/wms_balance_perf_2a_capture.sql   (호출마다 ms 는 stdout 의 Time: 줄)
--   Caleb(적용 뒤): 같은 명령에 다른 out → diff <옛> <새>  (기대 차이 = 첫 FP 줄의 functions md5 뿐)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
create temp table t_in (ord serial, name text, sql text);
set default_transaction_read_only = on;
set statement_timeout = '20s';
select set_config('request.jwt.claim.sub', s.auth_user_id::text, false), set_config('request.jwt.claims', json_build_object('sub', s.auth_user_id, 'role', 'authenticated')::text, false)
  from (select auth_user_id from public.ims_staff where is_active and auth_user_id is not null order by created_at limit 1) s;
\o :out
select 'FP ' || (select max(id) from public.inv_ledger) || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.so_reserve where released_at is null) || '/' || (select count(*) from public.inv_transfer_line) || ' functions ' ||
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_available_base', 'stk_availability'));
insert into t_in (name, sql)
  select 'IAB ' || w.name || ' null', format('select %L || '' '' || coalesce(jsonb_agg(to_jsonb(r) order by r.stock_pid), ''[]'')::text from public.inv_available_base(%L::uuid, null) r', 'IAB ' || w.name || ' null', w.id)
  from public.ref_warehouse w where w.is_active order by w.name;
insert into t_in (name, sql)
  select 'IAB ' || w.name || ' sharp', format('select %L || '' '' || coalesce(jsonb_agg(to_jsonb(r) order by r.stock_pid), ''[]'')::text from public.inv_available_base(%L::uuid, %L::uuid[]) r', 'IAB ' || w.name || ' sharp', w.id, s.pids)
  from public.ref_warehouse w
  cross join lateral (select array_agg(pid) as pids from (
      (select p.id as pid from public.ref_bin rb join public.inv_balance b on b.warehouse = w.name and b.bin = rb.name and rb.warehouse_id = w.id join public.product p on p.sku = b.sku where rb.is_bgrade and b.qty <> 0 order by p.sku limit 50)
      union (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.bin = '' and b.qty <> 0 order by p.sku limit 150)
      union (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.qty < 0 order by p.sku limit 150)
      union (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and exists (select 1 from public.product c where c.parent_product_id = p.id) order by p.sku limit 150)) x) s
  where w.is_active and s.pids is not null order by w.name;
insert into t_in (name, sql)
  select 'SAM ' || s.so_number, format('select %L || '' '' || coalesce(jsonb_agg(to_jsonb(r) order by r.stock_pid), ''[]'')::text from public.so_available_many(%L::uuid[], %L::uuid) r', 'SAM ' || s.so_number,
         (select array_agg(distinct coalesce(p.parent_product_id, p.id)) from public.so_line l join public.product p on p.id = l.product_id where l.so_id = s.id), s.location_id)
  from public.so s where s.status in ('picking', 'confirmed', 'at_wms') and s.location_id is not null order by s.so_number;
insert into t_in (name, sql)
  select 'SSP store ' || st.store_id, format('select %L || '' '' || coalesce(jsonb_agg(to_jsonb(r) order by r.store_id, r.product_id, r.warehouse_id), ''[]'')::text from public.shop_stock_payload(%L::uuid, null) r', 'SSP store ' || st.store_id, st.store_id)
  from (select distinct sl.store_id from public.shop_location sl where sl.is_active) st order by st.store_id;
insert into t_in (name, sql) values
  ('STK Both zero off 100',  'select ''STK Both zero off 100 '' || coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'')::text from public.stk_availability(null, null, null, null, false, 100, 0, false, null) with ordinality r'),
  ('STK Both zero on 100',   'select ''STK Both zero on 100 '' || coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'')::text from public.stk_availability(null, null, null, null, true, 100, 0, false, null) with ordinality r'),
  ('STK Both export 20000',  'select ''STK Both export 20000 '' || coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'')::text from public.stk_availability(null, null, null, null, true, 20000, 0, false, null) with ordinality r'),
  ('STK Both q UNF 500',     'select ''STK Both q UNF 500 '' || coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'')::text from public.stk_availability(null, ''UNF'', null, null, true, 500, 0, false, null) with ordinality r'),
  ('STK Both sale only 100', 'select ''STK Both sale only 100 '' || coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'')::text from public.stk_availability(null, null, null, null, true, 100, 0, true, null) with ordinality r');
insert into t_in (name, sql)
  select 'STK ' || w.name || ' zero ' || z.lbl || ' 100', format('select %L || '' '' || coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'')::text from public.stk_availability(%L::uuid, null, null, null, %s, 100, 0, false, null) with ordinality r', 'STK ' || w.name || ' zero ' || z.lbl || ' 100', w.id, z.v)
  from public.ref_warehouse w cross join (values ('off', 'false'), ('on', 'true')) z(lbl, v) where w.is_active order by w.name, z.lbl;
select 'INPUT ' || ord || ' ' || name from t_in order by ord;
\timing on
select sql from t_in order by ord \gexec
\timing off
select 'FP ' || (select max(id) from public.inv_ledger) || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.so_reserve where released_at is null) || '/' || (select count(*) from public.inv_transfer_line) || ' (end)';
select 'inputs ' || count(*) from t_in;
