-- supabase/tests/wms_balance_perf_2a_check.sql — wms-balance-perf-2a ②-a(deferred 450) inv_available_base bal · stk_availability lastev 를 뷰 대신 직접 읽기 — 검증 (2026-11-02)
-- [메인 IMS · Asung-IMS] 시험 적용 장치 틀(wms_balance_perf_1_check 와 같은 꼴) — 기준(begin 앞 · 잠금 없음: 지문 · 무접촉 md5 · 속성 · 입력 고르기)
--   → D 직접 식 vs 뷰 식(begin 앞 · 두 창고 · bal(null · sharp) · lastev · except 양방향 0 — 마이그레이션과 무관하게 식 자체가 같은 집합인가)
--   → (-v mig 면: O 옛 창구를 begin 앞 자동 커밋 읽기로 돌려 t_run 에 담는다 — inv_available_base 두 길 5 · so_available_many 2 · shop_stock_payload 1 · stk_availability 3)
--   → begin → (-v mig 면 \i) → N 새 창구 · C 옛 = 새(jsonb 같음 · 지문 움직이면 skipped) → E 꼴(태그 줄 뺀 본문 · 속성 · comment · 무접촉 md5 · 뷰 무변) → rollback → Z
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261103010000_wms_balance_perf_2a.sql -f supabase/tests/wms_balance_perf_2a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 29 · 확인(적용 뒤) 17 — C0 ~ C12(10 없음 · 내보내기 꼴 2 초는 캡처 파일이 덮는다 · 10 초 규칙) 는 시험 갈래만 · Z 는 t_res 밖 한 줄
--   stk_availability 는 직원 문(auth.uid())이 있어 request.jwt.claims 에 활성 직원(Caleb) sub 를 실어 부른다(definer · 읽기만) · 쓰기 0
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안(끝에 begin_to_rollback · mig_to_rollback) · 실제 행은 잠그지 않는다 · lock_timeout 3s
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 29
\else
\set EXPECT_OK 17
\endif
\pset pager off
select (select max(id) from public.inv_ledger) as fp_led_max, (select count(*) from public.inv_ledger) as fp_led_n, (select count(*) from public.inv_snapshot) as fp_snap_n,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('ims_inv_balance_of', 'wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'stk_bins', 'stk_bins_many', 'stk_reserved', 'shop_stock_payload', 'so_available_many', 'stk_availability_export', 'so_sale_now', 'shop_stock_targets')) as un_md5_0,
       (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) || '/' || pg_get_function_result(p.oid), ' ' order by p.proname)
          from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_available_base', 'stk_availability')) as attr_0,
       (select md5(pg_get_viewdef(c.oid, true) || coalesce(c.reloptions::text, '')) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'ims_inv_balance') as view_md5_0,
       (select md5(pg_get_viewdef(c.oid, true)) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'inv_balance') as ib_md5_0,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1, (select name from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1n,
       (select id::text from public.ref_warehouse where name = 'Asung - Edmonton') as wh2, (select name from public.ref_warehouse where name = 'Asung - Edmonton') as wh2n,
       (select s.auth_user_id::text from public.ims_staff s where s.is_active and s.auth_user_id is not null order by s.created_at limit 1) as staff_uid \gset
\echo '── 기준: ledger max' :fp_led_max '· rows' :fp_led_n '· snapshot' :fp_snap_n
\echo '── 속성(전):' :attr_0
-- 직원 문 — 활성 직원 sub(definer 함수 안 auth.uid() 만 본다 · 역할은 postgres 그대로)
select set_config('request.jwt.claim.sub', :'staff_uid', false), set_config('request.jwt.claims', json_build_object('sub', :'staff_uid', 'role', 'authenticated')::text, false);
-- 입력 고르기
create temp table t_sharp as
  select w.id as warehouse_id, array_agg(distinct x.pid) as pids
  from public.ref_warehouse w
  join lateral (
    (select p.id as pid from public.ref_bin rb join public.inv_balance b on b.warehouse = w.name and b.bin = rb.name and rb.warehouse_id = w.id join public.product p on p.sku = b.sku where rb.is_bgrade and b.qty <> 0 limit 40)
    union all (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.bin = '' and b.qty <> 0 order by b.sku limit 40)
    union all (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.qty < 0 order by b.sku limit 40)
    union all (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and exists (select 1 from public.product c where c.parent_product_id = p.id) order by b.sku limit 40)
    union all (select coalesce(p.parent_product_id, p.id) from public.so_reserve r join public.so_line l on l.id = r.so_line_id join public.so s on s.id = l.so_id join public.product p on p.id = l.product_id where r.released_at is null and s.location_id = w.id limit 40)
  ) x on true
  where w.id in (:'wh1'::uuid, :'wh2'::uuid)
  group by w.id;
select (select pids::text from t_sharp where warehouse_id = :'wh1'::uuid) as sharp1, (select pids::text from t_sharp where warehouse_id = :'wh2'::uuid) as sharp2,
       (select array_agg(distinct p) ::text from t_sharp, unnest(pids) p) as sharp_all,
       (select array_agg(distinct coalesce(p.parent_product_id, p.id))::text from public.so s join public.so_line l on l.so_id = s.id join public.product p on p.id = l.product_id
          where s.id = (select s2.id from public.so s2 where s2.location_id = :'wh1'::uuid and s2.status in ('picking', 'confirmed', 'at_wms') order by (select count(*) from public.so_line x where x.so_id = s2.id) desc limit 1)) as so_pids1,
       (select array_agg(distinct coalesce(p.parent_product_id, p.id))::text from public.so s join public.so_line l on l.so_id = s.id join public.product p on p.id = l.product_id
          where s.id = (select s2.id from public.so s2 where s2.location_id = :'wh2'::uuid and s2.status in ('picking', 'confirmed', 'at_wms') order by (select count(*) from public.so_line x where x.so_id = s2.id) desc limit 1)) as so_pids2 \gset
\echo '── 입력: sharp T' :sharp1 '· sharp E' :sharp2
-- ── 도우미 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create temp table t_run (phase text, name text, res jsonb, ms numeric);
create function pg_temp.run(p_phase text, p_name text, p_sql text) returns void language plpgsql as $$
declare v jsonb; t0 timestamptz := clock_timestamp();
begin
  execute p_sql into v;
  insert into t_run values (p_phase, p_name, v, round(extract(epoch from clock_timestamp() - t0) * 1000, 1));
exception when others then
  insert into t_run values (p_phase, p_name, jsonb_build_object('err', sqlerrm), round(extract(epoch from clock_timestamp() - t0) * 1000, 1));
end $$;
-- 직접 식 vs 뷰 식(마이그레이션 본문의 bal · lastev 식 그대로) → 'only_direct=<a> only_view=<b> rows=<n>'
create function pg_temp.dbal(p_wh uuid, p_whn text, p_pids uuid[]) returns text language plpgsql as $$
declare a int; b int; n int; v_skus text[];
begin
  if p_pids is not null then select array_agg(p.sku) into v_skus from public.product p where p.id = any(p_pids); end if;
  create temp table t_d on commit drop as
    select p.id as stock_pid, sum(b.qty) filter (where not coalesce(rb.is_bgrade, false)) as qty, sum(b.qty) filter (where coalesce(rb.is_bgrade, false)) as bg
    from public.inv_balance b join public.product p on p.sku = b.sku
    left join public.ref_bin rb on rb.warehouse_id = p_wh and rb.name = b.bin and b.bin <> ''
    where b.warehouse = p_whn and (v_skus is null or b.sku = any(v_skus)) group by p.id;
  create temp table t_v on commit drop as
    select b.product_id as stock_pid, sum(b.qty) filter (where not b.bin_is_bgrade) as qty, sum(b.qty) filter (where b.bin_is_bgrade) as bg
    from public.ims_inv_balance b where b.warehouse = p_whn and b.product_id is not null and (v_skus is null or b.sku = any(v_skus)) group by b.product_id;
  select count(*) into n from t_d;
  select count(*) into a from (select * from t_d except all select * from t_v) x;
  select count(*) into b from (select * from t_v except all select * from t_d) x;
  drop table t_d; drop table t_v;
  return 'only_direct=' || a || ' only_view=' || b || ' rows=' || n;
end $$;
create function pg_temp.dlast(p_whn text) returns text language plpgsql as $$
declare a int; b int; n int;
begin
  create temp table t_d on commit drop as select p.id as product_id, max(l.occurred_on) as last_event_on from public.inv_ledger l join public.product p on p.sku = l.sku where l.warehouse = p_whn group by 1;
  create temp table t_v on commit drop as select b.product_id, max(b.last_event_on) as last_event_on from public.ims_inv_balance b where b.warehouse = p_whn and b.product_id is not null group by 1;
  select count(*) into n from t_d;
  select count(*) into a from (select * from t_d except all select * from t_v where t_v.last_event_on is not null) x;   -- 뷰는 사건 없는(스냅샷만) 제품도 null 로 낸다 · 직접 식에는 그 행이 없다 — left join 이라 같은 값(null)
  select count(*) into b from (select * from t_v where t_v.last_event_on is not null except all select * from t_d) x;
  drop table t_d; drop table t_v;
  return 'only_direct=' || a || ' only_view=' || b || ' rows=' || n;
end $$;
-- ── D 직접 식 vs 뷰 식(begin 앞 · 두 갈래 모두) ──
select pg_temp.chk('D1 bal direct = view · Toronto · all products', regexp_replace(pg_temp.dbal(:'wh1'::uuid, :'wh1n', null), ' rows=\d+$', ''), 'only_direct=0 only_view=0');
select pg_temp.chk('D2 bal direct = view · Edmonton · all products', regexp_replace(pg_temp.dbal(:'wh2'::uuid, :'wh2n', null), ' rows=\d+$', ''), 'only_direct=0 only_view=0');
select pg_temp.chk('D3 bal direct = view · Toronto · sharp pids', regexp_replace(pg_temp.dbal(:'wh1'::uuid, :'wh1n', :'sharp1'::uuid[]), ' rows=\d+$', ''), 'only_direct=0 only_view=0');
select pg_temp.chk('D4 bal direct = view · Edmonton · sharp pids', regexp_replace(pg_temp.dbal(:'wh2'::uuid, :'wh2n', :'sharp2'::uuid[]), ' rows=\d+$', ''), 'only_direct=0 only_view=0');
select pg_temp.chk('D5 lastev direct = view (non-null) · Toronto', regexp_replace(pg_temp.dlast(:'wh1n'), ' rows=\d+$', ''), 'only_direct=0 only_view=0');
select pg_temp.chk('D6 lastev direct = view (non-null) · Edmonton', regexp_replace(pg_temp.dlast(:'wh2n'), ' rows=\d+$', ''), 'only_direct=0 only_view=0');
select pg_temp.chk('D7 bal direct rows > 0 · Toronto · Edmonton', (((regexp_match(pg_temp.dbal(:'wh1'::uuid, :'wh1n', null), 'rows=(\d+)$'))[1]::int > 0) and ((regexp_match(pg_temp.dbal(:'wh2'::uuid, :'wh2n', null), 'rows=(\d+)$'))[1]::int > 0))::text, 'true');
-- 창구 호출문(옛 · 새 같은 문장) — 집합 함수는 jsonb 배열로(정렬 고정)
create temp table t_calls (ord int, name text, sql text);
insert into t_calls values
  (1, 'inv_available_base (Toronto, null)',  format('select coalesce(jsonb_agg(to_jsonb(r) order by r.stock_pid), ''[]'') from public.inv_available_base(%L::uuid, null) r', :'wh1')),
  (2, 'inv_available_base (Edmonton, null)', format('select coalesce(jsonb_agg(to_jsonb(r) order by r.stock_pid), ''[]'') from public.inv_available_base(%L::uuid, null) r', :'wh2')),
  (3, 'inv_available_base (Toronto, sharp)',  format('select coalesce(jsonb_agg(to_jsonb(r) order by r.stock_pid), ''[]'') from public.inv_available_base(%L::uuid, %L::uuid[]) r', :'wh1', :'sharp1')),
  (4, 'inv_available_base (Edmonton, sharp)', format('select coalesce(jsonb_agg(to_jsonb(r) order by r.stock_pid), ''[]'') from public.inv_available_base(%L::uuid, %L::uuid[]) r', :'wh2', :'sharp2')),
  (5, 'inv_available_base (Toronto, {}) · (Toronto, unknown id) · (unknown wh, null)',
      format('select jsonb_build_array((select count(*) from public.inv_available_base(%L::uuid, ''{}''::uuid[])), (select count(*) from public.inv_available_base(%L::uuid, array[''00000000-0000-0000-0000-000000000001''::uuid])), (select count(*) from public.inv_available_base(''00000000-0000-0000-0000-000000000002''::uuid, null)))', :'wh1', :'wh1')),
  (6, 'so_available_many (so pids, Toronto)',  format('select coalesce(jsonb_agg(to_jsonb(r) order by r.stock_pid), ''[]'') from public.so_available_many(%L::uuid[], %L::uuid) r', :'so_pids1', :'wh1')),
  (7, 'so_available_many (so pids, Edmonton)', format('select coalesce(jsonb_agg(to_jsonb(r) order by r.stock_pid), ''[]'') from public.so_available_many(%L::uuid[], %L::uuid) r', :'so_pids2', :'wh2')),
  (8, 'shop_stock_payload (all stores, sharp T ∪ E)', format('select coalesce(jsonb_agg(to_jsonb(r) order by r.store_id, r.product_id, r.warehouse_id), ''[]'') from public.shop_stock_payload(null, %L::uuid[]) r', :'sharp_all')),
  (9, 'stk_availability Both · zero off · 100',   'select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(null, null, null, null, false, 100, 0, false, null) with ordinality r'),
  (11, 'stk_availability Toronto · zero off · 100', format('select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(%L::uuid, null, null, null, false, 100, 0, false, null) with ordinality r', :'wh1')),
  (12, 'stk_availability Both · q UNF · zero on · 500', 'select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(null, ''UNF'', null, null, true, 500, 0, false, null) with ordinality r');
-- ── O 옛 창구(시험 갈래만 · begin 앞 · 문장마다 자동 커밋 읽기) ──
\if :{?mig}
select format('select pg_temp.run(%L, %L, %L)', 'old', c.name, c.sql) from t_calls c order by c.ord \gexec
select (select max(id) from public.inv_ledger)::text || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.so_reserve where released_at is null) || '/' || (select count(*) from public.inv_transfer_line) as fp_old \gset
\echo '── 옛 결과 담음 · 지문' :fp_old
\endif

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select clock_timestamp() as t_mig \gset
-- ── N 새 창구 + C 옛 = 새 ──
select format('select pg_temp.run(%L, %L, %L)', 'new', c.name, c.sql) from t_calls c order by c.ord \gexec
select (select max(id) from public.inv_ledger)::text || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.so_reserve where released_at is null) || '/' || (select count(*) from public.inv_transfer_line) as fp_new \gset
select pg_temp.chk('N1 new calls all succeeded (no err)', (select count(*)::text from t_run where phase = 'new' and res ? 'err'), '0');
select pg_temp.chk('N2 new inv_available_base (Toronto, null) rows = direct bal keys ∪ alloc ∪ talloc (> 0)', (select (jsonb_array_length(res) > 0)::text from t_run where phase = 'new' and name = 'inv_available_base (Toronto, null)'), 'true');
select pg_temp.chk('N3 new stk_availability Both zero off returned 100 rows with total', (select jsonb_array_length(res)::text || '/' || ((res -> 0 ->> 'total')::int > 100)::text from t_run where phase = 'new' and name like 'stk_availability Both · zero off%'), '100/true');
\if :{?mig}
select pg_temp.chk('C0 fingerprint stable between old and new (' || :'fp_old' || ' → ' || :'fp_new' || ')', :'fp_new', :'fp_old');
select pg_temp.chk('C' || c.ord || ' new = old: ' || c.name || case when :'fp_new' <> :'fp_old' then ' (skipped: ledger moved)' else '' end || ' · ms old ' || o.ms || ' → new ' || n.ms,
                   case when :'fp_new' <> :'fp_old' then 'skipped' else (n.res = o.res)::text end, case when :'fp_new' <> :'fp_old' then 'skipped' else 'true' end)
from t_calls c join t_run o on o.phase = 'old' and o.name = c.name join t_run n on n.phase = 'new' and n.name = c.name order by c.ord;
\endif
-- ── E 꼴 ──
select pg_temp.chk('E1 inv_available_base body = original 878dc250 minus replaced lines + tagged (6)',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-balance-perf-2a[^\n]*\n', '', 'g')) || '/' || (select count(*) from regexp_matches(prosrc, 'wms-balance-perf-2a', 'g')) from pg_proc where oid = 'public.inv_available_base(uuid, uuid[])'::regprocedure), '69b29679f6a5c41ade618f77e3290600/6');
select pg_temp.chk('E2 stk_availability body = original 6eda5898 minus replaced line + tagged (1)',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-balance-perf-2a[^\n]*\n', '', 'g')) || '/' || (select count(*) from regexp_matches(prosrc, 'wms-balance-perf-2a', 'g')) from pg_proc where oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure), 'e9795444d37d245dfbd837833dbfe2c5/1');
select pg_temp.chk('E3 neither reads the view any more', (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('inv_available_base', 'stk_availability') and prosrc ~ 'public\.ims_inv_balance\M'), '0');
select pg_temp.chk('E4 attributes · return types unchanged × 2',
  (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) || '/' || pg_get_function_result(p.oid), ' ' order by p.proname)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_available_base', 'stk_availability')), :'attr_0');
select pg_temp.chk('E5 comments carry wms-balance-perf-2a × 2', (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_available_base', 'stk_availability') and obj_description(p.oid, 'pg_proc') like '%wms-balance-perf-2a%'), '2');
select pg_temp.chk('E6 untouched md5 (① 넷 · stk_bins · stk_bins_many · stk_reserved · shop_stock_payload · so_available_many · export · so_sale_now · shop_stock_targets)',
  (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('ims_inv_balance_of', 'wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'stk_bins', 'stk_bins_many', 'stk_reserved', 'shop_stock_payload', 'so_available_many', 'stk_availability_export', 'so_sale_now', 'shop_stock_targets')), :'un_md5_0');
select pg_temp.chk('E7 views ims_inv_balance (def + options) · inv_balance unchanged',
  (select md5(pg_get_viewdef(c.oid, true) || coalesce(c.reloptions::text, '')) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'ims_inv_balance') || '/' || (select md5(pg_get_viewdef(c.oid, true)) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'inv_balance'),
  :'view_md5_0' || '/' || :'ib_md5_0');
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || left(coalesce(got, '(null)'), 300) || ' | want=' || left(coalesce(want, '(null)'), 300) end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_bad, count(*) as n_all from t_res \gset
select phase, name, ms, jsonb_array_length(case when jsonb_typeof(res) = 'array' then res else '[]'::jsonb end) as rows, case when res ? 'err' then res ->> 'err' else '' end as err from t_run order by name, phase;
select clock_timestamp() as t_end \gset
rollback;
select (select max(id) from public.inv_ledger) = :fp_led_max and (select count(*) from public.inv_ledger) = :fp_led_n and (select count(*) from public.inv_snapshot) = :fp_snap_n as z_fingerprint_same_as_start,
       (select md5(prosrc) from pg_proc where oid = 'public.inv_available_base(uuid, uuid[])'::regprocedure) as z_iab_md5_after,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_begin'::timestamptz))::numeric, 2) as begin_to_rollback_s,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_mig'::timestamptz))::numeric, 2) as mig_to_rollback_s;
\echo '── 결과: OK' :n_ok '· MISMATCH' :n_bad '· 전체' :n_all '· 기대 OK' :EXPECT_OK
\if :{?mig}
\echo '   (시험 갈래 · 적용은 rollback 됨 · z_iab_md5_after 는 옛 878dc250… 이어야 한다)'
\else
\echo '   (확인 갈래 · z_iab_md5_after 는 새 값)'
\endif
