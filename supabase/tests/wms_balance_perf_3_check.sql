-- supabase/tests/wms_balance_perf_3_check.sql — wms-balance-perf-3 ③(deferred 450) 식 인덱스 둘 + wms_pick_shelf · bgrade_stock InitPlan 술어 · inv_move_bin_contents · ref_bin_bgrade_set 무변 — 검증 (2026-11-02)
-- [메인 IMS · Asung-IMS] 시험 적용 장치 틀(①· ②-a 와 같은 꼴) — 기준(begin 앞: 지문 · 무접촉 md5 · 속성 · 입력) → D 술어 더한 식 vs 옛 식(begin 앞 · except 양방향 0)
--   → (-v mig 면: O 옛 창구를 begin 앞 자동 커밋 읽기로 — wms_pick_shelf 5 · bgrade_stock 3 · inv_move_bin_contents 3 · ref_bin_bgrade_set 의 장부 줄 직접 3)
--   → begin → (-v mig 면 \i — 인덱스 둘 만들기 약 1.7 s 포함) → N 새 창구 · C 옛 = 새 → E 꼴(태그 줄 뺀 본문 · 무변 md5 · 인덱스 정의 · 속성 · comment · 무접촉) → rollback → Z(인덱스 사라짐)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261103023000_wms_balance_perf_3.sql -f supabase/tests/wms_balance_perf_3_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 32 · 확인(적용 뒤) 17 — C0 ~ C14 는 시험 갈래만(칸 비우기는 창고마다 재고 많은 칸 1 — 그 함수의 시간은 장부가 아니라 칸마다의 열린 계획 조회라 트랜잭션 안 10 초 규칙에 맞춰 줄였다 · 캡처는 10 칸) · Z 는 t_res 밖 한 줄
--   직원 문: request.jwt.claims 에 활성 admin 직원 sub(wms_pick_shelf 는 picking 쓰기 열쇠 · inv_move_bin_contents 는 stock_move · admin 은 통과) · ref_bin_bgrade_set 은 volatile(ref_bin 쓰기)이라 부르지 않는다 — 그 장부 줄(count · sum)을 직접 돌린다 · 쓰기 0
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안 · create index 는 두 표 쓰기를 1 ~ 2 초 막는다(두 창고 멈춤) · lock_timeout 3s
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 32
\else
\set EXPECT_OK 17
\endif
\pset pager off
select (select max(id) from public.inv_ledger) as fp_led_max, (select count(*) from public.inv_ledger) as fp_led_n, (select count(*) from public.inv_snapshot) as fp_snap_n,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('ims_inv_balance_of', 'wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'inv_available_base', 'stk_availability', 'inv_move_bin_contents', 'ref_bin_bgrade_set', 'inv_adjust_picked', 'inv_move_open_plans', 'wms_health_check')) as un_md5_0,
       (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) || '/' || pg_get_function_result(p.oid), ' ' order by p.proname)
          from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_pick_shelf', 'bgrade_stock')) as attr_0,
       (select md5(pg_get_viewdef(c.oid, true) || coalesce(c.reloptions::text, '')) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'ims_inv_balance') as view_md5_0,
       (select md5(pg_get_viewdef(c.oid, true)) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'inv_balance') as ib_md5_0,
       (select count(*) from pg_indexes where schemaname = 'public' and indexname in ('inv_ledger_wh_bin_sku_idx', 'inv_snapshot_key_wh_bin_sku_idx')) as idx_n0,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1, (select name from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1n,
       (select id::text from public.ref_warehouse where name = 'Asung - Edmonton') as wh2, (select name from public.ref_warehouse where name = 'Asung - Edmonton') as wh2n,
       (select s.auth_user_id::text from public.ims_staff s where s.is_active and s.auth_user_id is not null and s.role = 'admin' order by s.created_at limit 1) as staff_uid \gset
\echo '── 기준: ledger max' :fp_led_max '· rows' :fp_led_n '· snapshot' :fp_snap_n '· 새 인덱스(전)' :idx_n0
select set_config('request.jwt.claim.sub', :'staff_uid', false), set_config('request.jwt.claims', json_build_object('sub', :'staff_uid', 'role', 'authenticated')::text, false);
-- 입력: 창고마다 sku 목록(TRF-00003 · 잔고 있는 300 · 세트 + 모르는 + 빈) · 칸(재고 많은 활성 칸 1 · B급 칸 1 · 비활성 칸 1 — 있는 창고만)
create temp table t_in_sku as
  select w.id as warehouse_id, w.name as whn,
         (select array_agg(distinct l.sku order by l.sku) from public.wms_order_doc_line l join public.wms_order_doc d on d.doc_id = l.doc_id where d.doc_number = 'TRF-00003') as trf_skus,
         (select array_agg(x.sku) from (select b.sku from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.qty <> 0 order by b.sku limit 300) x) as top_skus,
         (select array_agg(x.sku) from (select c.sku from public.product c where c.parent_product_id is not null and exists (select 1 from public.inv_balance b where b.sku = (select pp.sku from public.product pp where pp.id = c.parent_product_id) and b.warehouse = w.name and b.qty <> 0) order by c.sku limit 20) x)
           || array['ZZZ-NOPE-1', ' ', ''] || (select array_agg(x.sku) from (select b.sku from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.qty < 0 order by b.sku limit 20) x) as mix_skus
  from public.ref_warehouse w where w.id in (:'wh1'::uuid, :'wh2'::uuid);
create temp table t_in_bin as
  select w.id as warehouse_id, w.name as whn, rb.id as bin_id, rb.name as bin, rb.is_bgrade, rb.is_active, k.kind
  from public.ref_warehouse w
  cross join lateral (
    (select rb.id, 'top' as kind from public.ref_bin rb join (select b.bin, count(*) as n from public.inv_balance b where b.warehouse = w.name and b.qty <> 0 and b.bin <> '' group by 1) c on c.bin = rb.name where rb.warehouse_id = w.id and rb.is_active and not rb.is_bgrade order by c.n desc, rb.name limit 1)
    union all (select rb.id, 'bgrade' from public.ref_bin rb where rb.warehouse_id = w.id and rb.is_bgrade order by rb.name limit 1)
    union all (select rb.id, 'inactive' from public.ref_bin rb where rb.warehouse_id = w.id and not rb.is_active order by rb.name limit 1)
  ) k join public.ref_bin rb on rb.id = k.id
  where w.id in (:'wh1'::uuid, :'wh2'::uuid);
select string_agg(whn || ':' || kind || ':' || bin, ' · ' order by whn, kind, bin) as bins_txt from t_in_bin \gset
\echo '── 입력 칸:' :bins_txt
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
-- D 술어를 더한 식 vs 옛 식(마이그레이션 본문 그대로 · begin 앞)
create function pg_temp.dshelf(p_whn text, p_wh uuid, p_skus text[]) returns text language plpgsql as $$
declare a int; b int; n int;
begin
  create temp table t_o on commit drop as
    with req as (select distinct on (coalesce(sp.sku, btrim(s.sku))) coalesce(sp.sku, btrim(s.sku)) as sku from unnest(p_skus) as s(sku) left join public.product p on p.sku = btrim(s.sku) left join public.product sp on sp.id = coalesce(p.parent_product_id, p.id) where btrim(coalesce(s.sku, '')) <> '')
    select r.sku, b.bin, b.qty as book from req r join public.inv_balance b on b.sku = r.sku and b.warehouse = p_whn
     where b.bin <> '' and b.qty <> 0 and not exists (select 1 from public.ref_bin rb0 where rb0.warehouse_id = p_wh and rb0.name = b.bin and rb0.is_bgrade);
  create temp table t_n on commit drop as
    with req as (select distinct on (coalesce(sp.sku, btrim(s.sku))) coalesce(sp.sku, btrim(s.sku)) as sku from unnest(p_skus) as s(sku) left join public.product p on p.sku = btrim(s.sku) left join public.product sp on sp.id = coalesce(p.parent_product_id, p.id) where btrim(coalesce(s.sku, '')) <> '')
    select r.sku, b.bin, b.qty as book from req r join public.inv_balance b on b.sku = r.sku and b.warehouse = p_whn
     where b.sku = any((select array_agg(r2.sku) from req r2)::text[]) and b.bin <> '' and b.qty <> 0 and not exists (select 1 from public.ref_bin rb0 where rb0.warehouse_id = p_wh and rb0.name = b.bin and rb0.is_bgrade);
  select count(*) into n from t_n;
  select count(*) into a from (select * from t_n except all select * from t_o) x;
  select count(*) into b from (select * from t_o except all select * from t_n) x;
  drop table t_o; drop table t_n;
  return 'only_new=' || a || ' only_old=' || b || ' rows=' || n;
end $$;
create function pg_temp.dbg(p_wh uuid) returns text language plpgsql as $$
declare a int; b int; n int;
begin
  create temp table t_o on commit drop as
    with b as (select rb.id, rb.name, w.id as wh_id, w.name as wh from public.ref_bin rb join public.ref_warehouse w on w.id = rb.warehouse_id where rb.is_bgrade and w.is_active and (p_wh is null or w.id = p_wh))
    select b.wh, b.name, ib.sku, ib.qty from b join public.inv_balance ib on ib.warehouse = b.wh and ib.bin = b.name and ib.qty <> 0;
  create temp table t_n on commit drop as
    with b as (select rb.id, rb.name, w.id as wh_id, w.name as wh from public.ref_bin rb join public.ref_warehouse w on w.id = rb.warehouse_id where rb.is_bgrade and w.is_active and (p_wh is null or w.id = p_wh))
    select b.wh, b.name, ib.sku, ib.qty from b join public.inv_balance ib on ib.warehouse = b.wh and ib.bin = b.name and ib.qty <> 0
      and ib.warehouse = any((select array_agg(b2.wh) from b b2)::text[]) and ib.bin = any((select array_agg(b2.name) from b b2)::text[]);
  select count(*) into n from t_n;
  select count(*) into a from (select * from t_n except all select * from t_o) x;
  select count(*) into b from (select * from t_o except all select * from t_n) x;
  drop table t_o; drop table t_n;
  return 'only_new=' || a || ' only_old=' || b || ' rows=' || n;
end $$;
select pg_temp.chk('D1 pick_shelf bk new = old · Toronto · TRF-00003 skus', regexp_replace(pg_temp.dshelf(:'wh1n', :'wh1'::uuid, (select trf_skus from t_in_sku where warehouse_id = :'wh1'::uuid)), ' rows=\d+$', ''), 'only_new=0 only_old=0');
select pg_temp.chk('D2 pick_shelf bk new = old · Edmonton · top 300 skus', regexp_replace(pg_temp.dshelf(:'wh2n', :'wh2'::uuid, (select top_skus from t_in_sku where warehouse_id = :'wh2'::uuid)), ' rows=\d+$', ''), 'only_new=0 only_old=0');
select pg_temp.chk('D3 pick_shelf bk new = old · Toronto · sets + unknown + blank + negative', regexp_replace(pg_temp.dshelf(:'wh1n', :'wh1'::uuid, (select mix_skus from t_in_sku where warehouse_id = :'wh1'::uuid)), ' rows=\d+$', ''), 'only_new=0 only_old=0');
select pg_temp.chk('D4 pick_shelf bk rows > 0 · Toronto · Edmonton', (((regexp_match(pg_temp.dshelf(:'wh1n', :'wh1'::uuid, (select top_skus from t_in_sku where warehouse_id = :'wh1'::uuid)), 'rows=(\d+)$'))[1]::int > 0) and ((regexp_match(pg_temp.dshelf(:'wh2n', :'wh2'::uuid, (select top_skus from t_in_sku where warehouse_id = :'wh2'::uuid)), 'rows=(\d+)$'))[1]::int > 0))::text, 'true');
select pg_temp.chk('D5 bgrade x new = old · all warehouses', regexp_replace(pg_temp.dbg(null), ' rows=\d+$', ''), 'only_new=0 only_old=0');
select pg_temp.chk('D6 bgrade x new = old · Toronto · Edmonton', regexp_replace(pg_temp.dbg(:'wh1'::uuid), ' rows=\d+$', '') || ' / ' || regexp_replace(pg_temp.dbg(:'wh2'::uuid), ' rows=\d+$', ''), 'only_new=0 only_old=0 / only_new=0 only_old=0');
select pg_temp.chk('D7 bgrade x rows > 0 (B-grade bins with stock exist)', ((regexp_match(pg_temp.dbg(null), 'rows=(\d+)$'))[1]::int > 0)::text, 'true');
-- 창구 호출문
create temp table t_calls (ord serial, name text, sql text);
insert into t_calls (name, sql)
  select 'wms_pick_shelf ' || k.whn || ' ' || k.lbl, format('select public.wms_pick_shelf(%L::uuid, %L::text[])', k.warehouse_id, k.skus)
  from (select s.warehouse_id, s.whn, 'TRF-00003 skus' as lbl, s.trf_skus as skus from t_in_sku s
        union all select s.warehouse_id, s.whn, 'top 300', s.top_skus from t_in_sku s
        union all select s.warehouse_id, s.whn, 'sets+unknown+blank+negative', s.mix_skus from t_in_sku s where s.warehouse_id = :'wh1'::uuid) k order by k.whn, k.lbl;
insert into t_calls (name, sql) values
  ('bgrade_stock (null)', 'select public.bgrade_stock(null)'),
  ('bgrade_stock (Toronto)', format('select public.bgrade_stock(%L::uuid)', :'wh1')),
  ('bgrade_stock (Edmonton)', format('select public.bgrade_stock(%L::uuid)', :'wh2'));
insert into t_calls (name, sql)
  select 'inv_move_bin_contents ' || b.whn || ' ' || b.kind || ' ' || b.bin, format('select public.inv_move_bin_contents(%L::uuid, %L::uuid)', b.warehouse_id, b.bin_id) from t_in_bin b order by b.whn, b.kind, b.bin;
insert into t_calls (name, sql)
  select 'bgrade_set ledger line ' || b.whn || ' ' || b.kind || ' ' || b.bin, format('select jsonb_build_array(count(*), coalesce(sum(b.qty), 0)) from public.inv_balance b where b.warehouse = %L and b.bin = %L and b.qty <> 0', b.whn, b.bin) from t_in_bin b where b.kind in ('top', 'bgrade') order by b.whn, b.kind, b.bin;
-- ── O 옛 창구(시험 갈래만 · begin 앞 · 문장마다 자동 커밋 읽기) ──
\if :{?mig}
select format('select pg_temp.run(%L, %L, %L)', 'old', c.name, c.sql) from t_calls c order by c.ord \gexec
select (select max(id) from public.inv_ledger)::text || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.wms_pick_line_bins) as fp_old \gset
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
select format('select pg_temp.run(%L, %L, %L)', 'new', c.name, c.sql) from t_calls c order by c.ord \gexec
select (select max(id) from public.inv_ledger)::text || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.wms_pick_line_bins) as fp_new \gset
select pg_temp.chk('N1 new calls succeeded except the two expected refusals (B-grade bin · inactive bin in inv_move_bin_contents)',
  (select string_agg(name || '=' || coalesce(res ->> 'err', 'ok'), ' | ' order by name) from t_run where phase = 'new' and res ? 'err'),
  (select string_agg('inv_move_bin_contents ' || b.whn || ' ' || b.kind || ' ' || b.bin || '=' || case b.kind when 'bgrade' then format('Bin %s is a B-grade bin — take stock out of it with Move back — nothing was saved', b.bin) else format('Bin %s is inactive — nothing was saved', b.bin) end, ' | ' order by 'inv_move_bin_contents ' || b.whn || ' ' || b.kind || ' ' || b.bin) from t_in_bin b where b.kind in ('bgrade', 'inactive')));
select pg_temp.chk('N2 new wms_pick_shelf Toronto top 300 has items with bins', (select ((jsonb_array_length(res -> 'items') > 0) and exists (select 1 from jsonb_array_elements(res -> 'items') i where jsonb_array_length(i -> 'bins') > 0))::text from t_run where phase = 'new' and name = 'wms_pick_shelf ' || :'wh1n' || ' top 300'), 'true');
select pg_temp.chk('N3 new bgrade_stock (null) row_count > 0', (select ((res ->> 'row_count')::int > 0)::text from t_run where phase = 'new' and name = 'bgrade_stock (null)'), 'true');
\if :{?mig}
select pg_temp.chk('C0 fingerprint stable between old and new (' || :'fp_old' || ' → ' || :'fp_new' || ')', :'fp_new', :'fp_old');
select pg_temp.chk('C' || c.ord || ' new = old: ' || c.name || case when :'fp_new' <> :'fp_old' then ' (skipped: ledger moved)' else '' end || ' · ms old ' || o.ms || ' → new ' || n.ms,
                   case when :'fp_new' <> :'fp_old' then 'skipped' else (n.res = o.res)::text end, case when :'fp_new' <> :'fp_old' then 'skipped' else 'true' end)
from t_calls c join t_run o on o.phase = 'old' and o.name = c.name join t_run n on n.phase = 'new' and n.name = c.name order by c.ord;
\endif
-- ── E 꼴 ──
select pg_temp.chk('E1 wms_pick_shelf body = original 8c6f9ffd minus replaced line + tagged (2)',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-balance-perf-3[^\n]*\n', '', 'g')) || '/' || (select count(*) from regexp_matches(prosrc, 'wms-balance-perf-3', 'g')) from pg_proc where oid = 'public.wms_pick_shelf(uuid, text[])'::regprocedure), '35d15384b47501245d10437958581c8a/2');
select pg_temp.chk('E2 bgrade_stock body = original 768feb98 + tagged (1)',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-balance-perf-3[^\n]*\n', '', 'g')) || '/' || (select count(*) from regexp_matches(prosrc, 'wms-balance-perf-3', 'g')) from pg_proc where oid = 'public.bgrade_stock(uuid)'::regprocedure), '768feb98c548446556c0eb94a07b41bd/1');
select pg_temp.chk('E3 indexes exist with the expected definitions (ledger · snapshot)',
  (select string_agg(indexname || ':' || (indexdef ~ 'USING btree \(warehouse, COALESCE\(bin, ''''::text\), sku\)|USING btree \(snapshot_key, warehouse, COALESCE\(bin, ''''::text\), sku\)')::text, ' ' order by indexname) from pg_indexes where schemaname = 'public' and indexname in ('inv_ledger_wh_bin_sku_idx', 'inv_snapshot_key_wh_bin_sku_idx')),
  'inv_ledger_wh_bin_sku_idx:true inv_snapshot_key_wh_bin_sku_idx:true');
select pg_temp.chk('E4 attributes · return types unchanged × 2',
  (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) || '/' || pg_get_function_result(p.oid), ' ' order by p.proname)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_pick_shelf', 'bgrade_stock')), :'attr_0');
select pg_temp.chk('E5 comments carry wms-balance-perf-3 × 2 + index comments × 2',
  (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_pick_shelf', 'bgrade_stock') and obj_description(p.oid, 'pg_proc') like '%wms-balance-perf-3%') || '/' ||
  (select count(*)::text from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('inv_ledger_wh_bin_sku_idx', 'inv_snapshot_key_wh_bin_sku_idx') and obj_description(c.oid, 'pg_class') like '%wms-balance-perf-3%'), '2/2');
select pg_temp.chk('E6 untouched md5 (① · ②-a 함수 · inv_move_bin_contents · ref_bin_bgrade_set · inv_adjust_picked · inv_move_open_plans · wms_health_check)',
  (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('ims_inv_balance_of', 'wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'inv_available_base', 'stk_availability', 'inv_move_bin_contents', 'ref_bin_bgrade_set', 'inv_adjust_picked', 'inv_move_open_plans', 'wms_health_check')), :'un_md5_0');
select pg_temp.chk('E7 views ims_inv_balance · inv_balance unchanged',
  (select md5(pg_get_viewdef(c.oid, true) || coalesce(c.reloptions::text, '')) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'ims_inv_balance') || '/' || (select md5(pg_get_viewdef(c.oid, true)) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'inv_balance'),
  :'view_md5_0' || '/' || :'ib_md5_0');
select 'index sizes: ' || string_agg(c.relname || '=' || pg_size_pretty(pg_relation_size(c.oid)), ' ' order by c.relname) as idx_sizes from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('inv_ledger_wh_bin_sku_idx', 'inv_snapshot_key_wh_bin_sku_idx') \gset
\echo '──' :idx_sizes
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || left(coalesce(got, '(null)'), 300) || ' | want=' || left(coalesce(want, '(null)'), 300) end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_bad, count(*) as n_all from t_res \gset
select phase, name, ms, case when res ? 'err' then left(res ->> 'err', 80) else '' end as err from t_run order by name, phase;
select clock_timestamp() as t_end \gset
rollback;
select (select max(id) from public.inv_ledger) = :fp_led_max and (select count(*) from public.inv_ledger) = :fp_led_n and (select count(*) from public.inv_snapshot) = :fp_snap_n as z_fingerprint_same_as_start,
       (select count(*) from pg_indexes where schemaname = 'public' and indexname in ('inv_ledger_wh_bin_sku_idx', 'inv_snapshot_key_wh_bin_sku_idx')) as z_new_index_count_after,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_begin'::timestamptz))::numeric, 2) as begin_to_rollback_s,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_mig'::timestamptz))::numeric, 2) as mig_to_rollback_s;
\echo '── 결과: OK' :n_ok '· MISMATCH' :n_bad '· 전체' :n_all '· 기대 OK' :EXPECT_OK
\if :{?mig}
\echo '   (시험 갈래 · 적용은 rollback 됨 · z_new_index_count_after 는 0 이어야 한다)'
\else
\echo '   (확인 갈래 · z_new_index_count_after 는 2 이어야 한다)'
\endif
