-- supabase/tests/wms_balance_perf_1_check.sql — wms-balance-perf-1 ①(deferred 450) 키 잔고 함수 ims_inv_balance_of + 창고 창구 넷(wms_pick_lines · so_pick_plan · ims_last_bin · product_bom_set) 검증 (2026-11-02)
-- [메인 IMS · Asung-IMS] 시험 적용 장치 틀 — 기준(begin 앞 · 잠금 없음: 지문 · 무접촉 md5 · 속성 · 입력 고르기)
--   → (-v mig 면: O 옛 창구를 begin 앞 자동 커밋 읽기로 돌려 temp 표 t_old 에 담는다 — 긴 트랜잭션 없음 · 호출마다 ms) → begin → (-v mig 면 \i)
--   → 뷰 쪽 집합을 begin 앞에 t_view 로(건당 0.5 ~ 1 s · 트랜잭션 밖) → K 함수 vs 뷰 집합(except 양방향 0 · 행 수 · 두 창고 · 큰 입력 324 · B급 칸 · bin '' · 음수 · 세트 · 창고 null · 모르는 id · 빈 배열 · null)
--   → C 옛 = 새(시험 갈래만 · jsonb 같음 · 장부 지문이 움직였으면 「skipped: ledger moved」 로 OK 처리 · ms 전후) → E 꼴(태그 줄 뺀 본문 = 옛 본문에서 바뀐 줄 뺀 것 · 속성 · comment · 무접촉 md5 · 뷰 무변) → rollback → Z 지문 · 시간
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261102230000_wms_balance_perf_1.sql -f supabase/tests/wms_balance_perf_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 39 · 확인(적용 뒤) 27 — C0 ~ C11 은 시험 갈래만 · Z 는 t_res 밖 한 줄
--   쓰기 0 — 창구는 전부 읽기(stable) · product_bom_set 은 부르지 않는다(definer · 직원 열쇠) — 그 한 줄(부모 장부 합)은 K7 이 함수 vs 뷰로 잰다
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안(끝에 begin_to_rollback · mig_to_rollback) · 실제 행은 잠그지 않는다 · lock_timeout 3s
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 39
\else
\set EXPECT_OK 27
\endif
\pset pager off
-- ── 기준(begin 앞) ──
select (select max(id) from public.inv_ledger) as fp_led_max, (select count(*) from public.inv_ledger) as fp_led_n,
       (select count(*) from public.inv_snapshot) as fp_snap_n, (select count(*) from public.wms_pick_line_bins) as fp_plb_n, (select count(*) from public.product_bin_overflow) as fp_ovf_n,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('stk_bins', 'stk_bins_many', 'inv_available_base', 'stk_availability', 'wms_pick_line_bins_write', 'wms_complete_pick', 'wms_pick_line_save', 'wms_batch_create', 'so_pos_complete')) as un_md5_0,
       (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner), ' ' order by p.proname)
          from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'product_bom_set')) as attr_0,
       (select md5(pg_get_viewdef(c.oid, true) || coalesce(c.reloptions::text, '')) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'ims_inv_balance') as view_md5_0,
       (select md5(pg_get_viewdef(c.oid, true)) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'ims_ledger_unlinked') as unl_md5_0,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1,
       (select id::text from public.ref_warehouse where name = 'Asung - Edmonton') as wh2 \gset
\echo '── 기준: ledger max' :fp_led_max '· rows' :fp_led_n '· snapshot' :fp_snap_n '· plan bins' :fp_plb_n
\echo '── 속성(전):' :attr_0
-- 입력 고르기(실제 데이터 · 두 창고)
select (select d.doc_id::text from public.wms_order_doc d where d.doc_number = 'TRF-00003') as trf3,
       (select array_agg(t.id order by t.id)::text from public.wms_pick_tasks t where t.status in ('pending', 'in_progress')) as tasks_open,
       (select t.id::text from public.wms_pick_tasks t join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id) where t.status in ('pending', 'in_progress') and d.warehouse_id = :'wh1'::uuid
          order by (select count(*) from public.wms_pick_task_lines l where l.pick_task_id = t.id) desc, t.id limit 1) as task_t,
       (select t.id::text from public.wms_pick_tasks t join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id) where t.status in ('pending', 'in_progress') and d.warehouse_id = :'wh2'::uuid
          order by (select count(*) from public.wms_pick_task_lines l where l.pick_task_id = t.id) desc, t.id limit 1) as task_e,
       (select d.doc_id::text from public.wms_order_doc d where d.warehouse_id = :'wh1'::uuid and d.status in ('at_wms', 'picking') order by (select count(*) from public.wms_order_doc_line l where l.doc_id = d.doc_id) desc, d.doc_number limit 1) as doc_t,
       (select d.doc_id::text from public.wms_order_doc d where d.warehouse_id = :'wh2'::uuid and d.status in ('at_wms', 'picking') order by (select count(*) from public.wms_order_doc_line l where l.doc_id = d.doc_id) desc, d.doc_number limit 1) as doc_e,
       (select d.doc_id::text from public.wms_order_doc d where exists (select 1 from public.so_line sl where sl.so_id = d.doc_id and sl.combo_line_id is not null) order by d.doc_number desc limit 1) as doc_combo,
       (select array_agg(x.stock_product_id)::text from (select distinct l.stock_product_id from public.wms_order_doc_line l join public.wms_order_doc d on d.doc_id = l.doc_id where d.doc_number = 'TRF-00003') x) as pids_trf,
       (select p.id::text from public.product p where exists (select 1 from public.product_bom b where b.parent_product_id = p.id and b.is_active) and p.parent_product_id is null
          order by (select count(*) from public.ims_inv_balance v where v.product_id = p.id) desc, p.sku limit 1) as combo_pid \gset
-- 날카로운 제품 집합(창고마다): B급 칸에 재고 · bin '' 에 qty ≠ 0 · 음수 칸 · 세트 부모 · 콤보 부모 — 500 안
create temp table t_sharp as
  select w.id as warehouse_id, array_agg(distinct x.pid) as pids
  from public.ref_warehouse w
  join lateral (
    (select p.id as pid from public.ref_bin rb join public.inv_balance b on b.warehouse = w.name and b.bin = rb.name and rb.warehouse_id = w.id join public.product p on p.sku = b.sku where rb.is_bgrade and b.qty <> 0 limit 40)
    union all (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.bin = '' and b.qty <> 0 order by b.sku limit 40)
    union all (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.qty < 0 order by b.sku limit 40)
    union all (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and exists (select 1 from public.product c where c.parent_product_id = p.id) order by b.sku limit 40)
    union all (select :'combo_pid'::uuid)
  ) x on true
  where w.id in (:'wh1'::uuid, :'wh2'::uuid)
  group by w.id;
select (select cardinality(pids) from t_sharp where warehouse_id = :'wh1'::uuid) as n_sharp_t, (select cardinality(pids) from t_sharp where warehouse_id = :'wh2'::uuid) as n_sharp_e \gset
\echo '── 입력: TRF-00003' :trf3 '(제품' :pids_trf '…)' '· 열린 과제' :tasks_open '· 큰 과제 T' :task_t 'E' :task_e '· 문서 T' :doc_t 'E' :doc_e '· 콤보 문서' :doc_combo '· 날카로운 집합 T' :n_sharp_t 'E' :n_sharp_e '· 콤보 부모' :combo_pid
-- ── 도우미 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
-- 창구 한 번 → 결과 jsonb + ms(실패면 {"err": …})
create temp table t_run (phase text, name text, res jsonb, ms numeric);
create function pg_temp.run(p_phase text, p_name text, p_sql text) returns void language plpgsql as $$
declare v jsonb; t0 timestamptz := clock_timestamp();
begin
  execute p_sql into v;
  insert into t_run values (p_phase, p_name, v, round(extract(epoch from clock_timestamp() - t0) * 1000, 1));
exception when others then
  insert into t_run values (p_phase, p_name, jsonb_build_object('err', sqlerrm), round(extract(epoch from clock_timestamp() - t0) * 1000, 1));
end $$;
-- 함수 vs 뷰 집합 비교 → 'rows=<n> only_fn=<a> only_view=<b>' — 뷰 쪽은 begin 앞에 t_view(key) 로 받아 둔다(뷰는 무변 · id 술어 뷰 읽기는 건당 0.5 ~ 1 s 라 트랜잭션 안에서 돌리면 10 초 규칙을 넘긴다)
create temp table t_view (key text, sku text, warehouse text, bin text, baseline_qty numeric, delta_qty numeric, qty numeric, product_id uuid, warehouse_id uuid, bin_id uuid, bin_zone text, bin_is_active boolean, last_event_on date, last_seen_on date, event_rows bigint, bin_is_bgrade boolean);
create temp table t_kin (key text, pids uuid[], wh uuid);
insert into t_kin values
  ('K1', :'pids_trf'::uuid[], :'wh1'::uuid), ('K2', :'pids_trf'::uuid[], :'wh2'::uuid),
  ('K3', (select pids from t_sharp where warehouse_id = :'wh1'::uuid), :'wh1'::uuid), ('K4', (select pids from t_sharp where warehouse_id = :'wh2'::uuid), :'wh2'::uuid),
  ('K5', (select array_agg(distinct p) from t_sharp, unnest(pids) p), null);
select format('insert into t_view select %L, v.* from public.ims_inv_balance v where v.product_id = any(%L::uuid[]) and (%L::uuid is null or v.warehouse_id = %L::uuid)', key, pids, wh, wh) from t_kin order by key \gexec
select coalesce(sum(b.qty), 0)::text as k7_view from public.ims_inv_balance b where b.product_id = :'combo_pid'::uuid \gset
select string_agg(key || '=' || n, ' ' order by key) as t_view_rows from (select key, count(*) as n from t_view group by key) x \gset
\echo '── 뷰 쪽 집합 받음(begin 앞):' :t_view_rows '· K7 뷰 합' :k7_view
create function pg_temp.kcmp(p_key text) returns text language plpgsql as $$
declare n int; a int; b int; k record;
begin
  select * into k from t_kin where key = p_key;
  select count(*) into n from public.ims_inv_balance_of(k.pids, k.wh);
  select count(*) into a from (select * from public.ims_inv_balance_of(k.pids, k.wh) except all select v.sku, v.warehouse, v.bin, v.baseline_qty, v.delta_qty, v.qty, v.product_id, v.warehouse_id, v.bin_id, v.bin_zone, v.bin_is_active, v.last_event_on, v.last_seen_on, v.event_rows, v.bin_is_bgrade from t_view v where v.key = p_key) x;
  select count(*) into b from (select v.sku, v.warehouse, v.bin, v.baseline_qty, v.delta_qty, v.qty, v.product_id, v.warehouse_id, v.bin_id, v.bin_zone, v.bin_is_active, v.last_event_on, v.last_seen_on, v.event_rows, v.bin_is_bgrade from t_view v where v.key = p_key except all select * from public.ims_inv_balance_of(k.pids, k.wh)) x;
  return 'rows=' || n || ' only_fn=' || a || ' only_view=' || b;
end $$;
-- 창구 호출문(옛 · 새 같은 문장)
create temp table t_calls (ord int, name text, sql text);
insert into t_calls values
  (1, 'wms_pick_lines all open tasks (' || :'tasks_open' || ')', format('select public.wms_pick_lines(%L::bigint[])', :'tasks_open')),
  (2, 'wms_pick_lines task T ' || :'task_t', format('select public.wms_pick_lines(array[%s]::bigint[])', :'task_t')),
  (3, 'wms_pick_lines task E ' || :'task_e', format('select public.wms_pick_lines(array[%s]::bigint[])', :'task_e')),
  (4, 'so_pick_plan TRF-00003 (324 lines)', format('select public.so_pick_plan(%L::uuid)', :'trf3')),
  (5, 'so_pick_plan doc T ' || :'doc_t', format('select public.so_pick_plan(%L::uuid)', :'doc_t')),
  (6, 'so_pick_plan doc E ' || :'doc_e', format('select public.so_pick_plan(%L::uuid)', :'doc_e')),
  (7, 'so_pick_plan combo doc ' || :'doc_combo', format('select public.so_pick_plan(%L::uuid)', :'doc_combo')),
  (8, 'ims_last_bin TRF-00003 pids × T', format('select public.ims_last_bin(%L::uuid[], %L::uuid)', :'pids_trf', :'wh1')),
  (9, 'ims_last_bin sharp × T', format('select public.ims_last_bin((select pids from t_sharp where warehouse_id = %L::uuid), %L::uuid)', :'wh1', :'wh1')),
  (10, 'ims_last_bin sharp × E', format('select public.ims_last_bin((select pids from t_sharp where warehouse_id = %L::uuid), %L::uuid)', :'wh2', :'wh2')),
  (11, 'ims_last_bin empty · null warehouse · unknown id', 'select jsonb_build_array(public.ims_last_bin(''{}''::uuid[], ' || quote_literal(:'wh1') || '::uuid), public.ims_last_bin(array[' || quote_literal(:'combo_pid') || '::uuid], null), public.ims_last_bin(array[''00000000-0000-0000-0000-000000000001''::uuid], ' || quote_literal(:'wh1') || '::uuid))');

-- ── O 옛 창구(시험 갈래만 · begin 앞 · 자동 커밋 읽기 · 긴 트랜잭션 없음) ──
\if :{?mig}
select format('select pg_temp.run(%L, %L, %L)', 'old', c.name, c.sql) from t_calls c order by c.ord \gexec
select (select max(id) from public.inv_ledger)::text || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.wms_pick_line_bins) || '/' || (select count(*) from public.product_bin_overflow) as fp_old \gset
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

-- ── K 함수 vs 뷰 집합(두 갈래 모두) ──
select pg_temp.chk('K1 TRF-00003 324 products × Toronto: fn = view (except both ways 0 · rows ' || (select count(*) from t_view where key = 'K1') || ')', regexp_replace(pg_temp.kcmp('K1'), '^rows=\d+ ', ''), 'only_fn=0 only_view=0');
select pg_temp.chk('K1b rows > 0', (select (count(*) > 0)::text from public.ims_inv_balance_of(:'pids_trf'::uuid[], :'wh1'::uuid)), 'true');
select pg_temp.chk('K2 TRF-00003 324 products × Edmonton: fn = view', regexp_replace(pg_temp.kcmp('K2'), '^rows=\d+ ', ''), 'only_fn=0 only_view=0');
select pg_temp.chk('K3 sharp set (B-grade bins · bin '''' · negative · set parents · combo) × Toronto: fn = view', regexp_replace(pg_temp.kcmp('K3'), '^rows=\d+ ', ''), 'only_fn=0 only_view=0');
select pg_temp.chk('K3b sharp × Toronto rows > 0', (select (count(*) > 0)::text from public.ims_inv_balance_of((select pids from t_sharp where warehouse_id = :'wh1'::uuid), :'wh1'::uuid)), 'true');
select pg_temp.chk('K4 sharp set × Edmonton: fn = view', regexp_replace(pg_temp.kcmp('K4'), '^rows=\d+ ', ''), 'only_fn=0 only_view=0');
select pg_temp.chk('K4b sharp × Edmonton rows > 0', (select (count(*) > 0)::text from public.ims_inv_balance_of((select pids from t_sharp where warehouse_id = :'wh2'::uuid), :'wh2'::uuid)), 'true');
select pg_temp.chk('K5 warehouse null (all warehouses) sharp T ∪ E: fn = view', regexp_replace(pg_temp.kcmp('K5'), '^rows=\d+ ', ''), 'only_fn=0 only_view=0');
select pg_temp.chk('K5b warehouse null rows ≥ Toronto rows + Edmonton rows',
  (select ((select count(*) from public.ims_inv_balance_of((select array_agg(distinct p) from t_sharp, unnest(pids) p), null))
        >= (select count(*) from public.ims_inv_balance_of((select pids from t_sharp where warehouse_id = :'wh1'::uuid), :'wh1'::uuid)) + (select count(*) from public.ims_inv_balance_of((select pids from t_sharp where warehouse_id = :'wh2'::uuid), :'wh2'::uuid)))::text), 'true');
select pg_temp.chk('K6 empty array · null array · unknown product · unknown warehouse → 0 rows',
  (select count(*) from public.ims_inv_balance_of('{}'::uuid[], :'wh1'::uuid))::text || '/' || (select count(*) from public.ims_inv_balance_of(null, :'wh1'::uuid))::text || '/' ||
  (select count(*) from public.ims_inv_balance_of(array['00000000-0000-0000-0000-000000000001'::uuid], :'wh1'::uuid))::text || '/' || (select count(*) from public.ims_inv_balance_of(:'pids_trf'::uuid[], '00000000-0000-0000-0000-000000000002'::uuid))::text, '0/0/0/0');
select pg_temp.chk('K7 product_bom_set line: sum over fn(combo parent, null) = sum over view (product_id = parent)',
  (select coalesce(sum(b.qty), 0)::text from public.ims_inv_balance_of(array[:'combo_pid'::uuid], null) b), :'k7_view');
select pg_temp.chk('K8 columns = view columns (name · type · order)',
  (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attnum) from pg_attribute a where a.attrelid = 'public.ims_inv_balance'::regclass and a.attnum > 0 and not a.attisdropped),
  (select string_agg(n || ' ' || format_type(t, null), ', ' order by o) from unnest((select proallargtypes from pg_proc where oid = 'public.ims_inv_balance_of(uuid[], uuid)'::regprocedure),
                                                                          (select proargnames from pg_proc where oid = 'public.ims_inv_balance_of(uuid[], uuid)'::regprocedure),
                                                                          (select proargmodes from pg_proc where oid = 'public.ims_inv_balance_of(uuid[], uuid)'::regprocedure)) with ordinality x(t, n, m, o) where m = 't'));
select pg_temp.chk('K9 helper attrs (sql · stable · invoker · search_path · acl authenticated+service_role · not anon)',
  (select p.prolang = (select oid from pg_language where lanname = 'sql') and p.provolatile = 's' and not p.prosecdef and p.proconfig::text = '{"search_path=public, pg_temp"}'
          and has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
     from pg_proc p where p.oid = 'public.ims_inv_balance_of(uuid[], uuid)'::regprocedure)::text, 'true');

-- ── N 새 창구(시간) + C 옛 = 새(시험 갈래만) ──
select format('select pg_temp.run(%L, %L, %L)', 'new', c.name, c.sql) from t_calls c order by c.ord \gexec
select (select max(id) from public.inv_ledger)::text || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.wms_pick_line_bins) || '/' || (select count(*) from public.product_bin_overflow) as fp_new \gset
select pg_temp.chk('N1 new calls all succeeded (no err)', (select count(*)::text from t_run where phase = 'new' and res ? 'err'), '0');
select pg_temp.chk('N2 new wms_pick_lines all-open-tasks returned every open line', (select jsonb_array_length(res)::text from t_run where phase = 'new' and name like 'wms_pick_lines all open%'),
  (select count(*)::text from public.wms_pick_task_lines l join public.wms_pick_tasks t on t.id = l.pick_task_id where t.status in ('pending', 'in_progress')));
select pg_temp.chk('N3 new so_pick_plan TRF-00003 lines = 324', (select jsonb_array_length(res -> 'lines')::text from t_run where phase = 'new' and name like 'so_pick_plan TRF-00003%'), (select count(*)::text from public.wms_order_doc_line l where l.doc_id = :'trf3'::uuid));
select pg_temp.chk('N4 new ims_last_bin sharp × T has keys', (select (count(*) > 0)::text from t_run r, jsonb_object_keys(r.res) where r.phase = 'new' and r.name = 'ims_last_bin sharp × T'), 'true');
\if :{?mig}
select pg_temp.chk('C0 ledger fingerprint stable between old and new (' || :'fp_old' || ' → ' || :'fp_new' || ')', :'fp_new', :'fp_old');
select pg_temp.chk('C' || c.ord || ' new = old: ' || c.name || case when :'fp_new' <> :'fp_old' then ' (skipped: ledger moved)' else '' end || ' · ms old ' || o.ms || ' → new ' || n.ms,
                   case when :'fp_new' <> :'fp_old' then 'skipped' else (n.res = o.res)::text end, case when :'fp_new' <> :'fp_old' then 'skipped' else 'true' end)
from t_calls c join t_run o on o.phase = 'old' and o.name = c.name join t_run n on n.phase = 'new' and n.name = c.name order by c.ord;
\endif

-- ── E 꼴 ──
select pg_temp.chk('E1 wms_pick_lines body = original ac211fbe minus replaced lines + only lines tagged wms-balance-perf-1 (11)',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-balance-perf-1[^\n]*\n', '', 'g')) || '/' || (select count(*) from regexp_matches(prosrc, 'wms-balance-perf-1', 'g')) from pg_proc where oid = 'public.wms_pick_lines(bigint[], bigint)'::regprocedure), '212e088d3fe40ecca388cf3995f39785/11');
select pg_temp.chk('E2 so_pick_plan body = original bdde73f2 minus replaced lines + tagged (1)',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-balance-perf-1[^\n]*\n', '', 'g')) || '/' || (select count(*) from regexp_matches(prosrc, 'wms-balance-perf-1', 'g')) from pg_proc where oid = 'public.so_pick_plan(uuid)'::regprocedure), '54ee22264ffb9b5bf0a4db7df8334e17/1');
select pg_temp.chk('E3 ims_last_bin body = original 69f43ebf minus replaced lines + tagged (2)',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-balance-perf-1[^\n]*\n', '', 'g')) || '/' || (select count(*) from regexp_matches(prosrc, 'wms-balance-perf-1', 'g')) from pg_proc where oid = 'public.ims_last_bin(uuid[], uuid)'::regprocedure), '04385b1229a0df0be4ee4188ed5b65d1/2');
select pg_temp.chk('E4 product_bom_set body = original cc5069f1 minus replaced line + tagged (1)',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-balance-perf-1[^\n]*\n', '', 'g')) || '/' || (select count(*) from regexp_matches(prosrc, 'wms-balance-perf-1', 'g')) from pg_proc where oid = 'public.product_bom_set(text, jsonb, jsonb, boolean, text[])'::regprocedure), '9c2e0e053dfe94a995675a02df66ec9b/1');
select pg_temp.chk('E5 the four no longer read the view · all read the helper',
  (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'product_bom_set') and prosrc ~ 'public\.ims_inv_balance\M') || '/' ||
  (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'product_bom_set') and prosrc ~ 'public\.ims_inv_balance_of\('), '0/4');
select pg_temp.chk('E6 attributes unchanged (acl · definer · volatile · search_path · owner) × 4',
  (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner), ' ' order by p.proname)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'product_bom_set')), :'attr_0');
select pg_temp.chk('E7 comments carry wms-balance-perf-1 × 4 + helper', (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'product_bom_set', 'ims_inv_balance_of') and obj_description(p.oid, 'pg_proc') like '%wms-balance-perf-1%'), '5');
select pg_temp.chk('E8 untouched md5 (stk_bins · stk_bins_many · inv_available_base · stk_availability · bins_write · complete_pick · line_save · batch_create · pos_complete)',
  (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('stk_bins', 'stk_bins_many', 'inv_available_base', 'stk_availability', 'wms_pick_line_bins_write', 'wms_complete_pick', 'wms_pick_line_save', 'wms_batch_create', 'so_pos_complete')), :'un_md5_0');
select pg_temp.chk('E9 views ims_inv_balance (def + options) · ims_ledger_unlinked unchanged',
  (select md5(pg_get_viewdef(c.oid, true) || coalesce(c.reloptions::text, '')) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'ims_inv_balance') || '/' || (select md5(pg_get_viewdef(c.oid, true)) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'ims_ledger_unlinked'),
  :'view_md5_0' || '/' || :'unl_md5_0');
select pg_temp.chk('E10 helper count = 1 (no overloads)', (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_inv_balance_of'), '1');

select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || left(coalesce(got, '(null)'), 300) || ' | want=' || left(coalesce(want, '(null)'), 300) end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_bad, count(*) as n_all from t_res \gset
select phase, name, ms, case when res ? 'err' then res ->> 'err' else '' end as err from t_run order by name, phase;
select clock_timestamp() as t_end \gset
rollback;
-- ── Z 지문 · 시간(begin 밖) ──
select (select max(id) from public.inv_ledger) = :fp_led_max and (select count(*) from public.inv_ledger) = :fp_led_n and (select count(*) from public.inv_snapshot) = :fp_snap_n as z_fingerprint_same_as_start,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_inv_balance_of') as z_helper_count_after_rollback,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_begin'::timestamptz))::numeric, 2) as begin_to_rollback_s,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_mig'::timestamptz))::numeric, 2) as mig_to_rollback_s;
\echo '── 결과: OK' :n_ok '· MISMATCH' :n_bad '· 전체' :n_all '· 기대 OK' :EXPECT_OK
\if :{?mig}
\echo '   (시험 갈래 · 적용은 rollback 됨 · z_helper_count_after_rollback 는 0 이어야 한다)'
\else
\echo '   (확인 갈래 · z_helper_count_after_rollback 는 1 이어야 한다)'
\endif
