-- supabase/tests/cost_fix_1_regen_trial.sql — cost-fix-1 재생성 생존 시험(전량 · 따로 돈다 · 끝에 rollback) (2026-11-01 · 판정 932)
-- [테스트 · Asung-IMS] begin → (-v mig 면 \i) → Caleb 열쇠 → 두 문서 실제 얹기(inv_cost_fix_opening_transfer) → 전(자연키 집합 md5 · 가족 남은 가치 · EDM 평가액) → inv_layer_apply() → 후 → 비교 → rollback
--   Claude Code: MIG=supabase/migrations/20261101160000_cost_fix_1_opening_transfer_layer_cost.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/cost_fix_1_regen_trial.sql
--   ⚠️ inv_layer_apply() 는 90 초쯤 걸리고 consume · cost_add 전부를 지웠다 다시 쓴다 — 그 동안 포스터(원장 쓰기)는 대기한다. lock_timeout 30s. 10 초 규칙 밖이라 cost_fix_1_check.sql 과 떼어 놓았다.
--   기대: C1 ~ C5 전부 OK · adj_skipped 0 · adj_deferred 0 · adj_n = 259 + 재생성 전 opening_fix 수(0) · 얹기 줄 집합(자연키) 전 = 후 · cost_late · cost_moved 집합 전 = 후 · 가족 남은 가치 전 = 후 · 전체 평가액 전 = 후(0.01 안)
\set ON_ERROR_STOP on
\pset pager off
select coalesce((select value from public.inv_config where key = 'db_role'), '(missing)') as db_role \gset
select (:'db_role' = 'test') as is_test \gset
\if :is_test
\else
\echo 'STOP — inv_config.db_role is not test — nothing was run'
\quit
\endif
begin;
set local lock_timeout = '30s';
select clock_timestamp() as t0 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select set_config('request.jwt.claims', (select jsonb_build_object('sub', auth_user_id, 'role', 'authenticated')::text from public.ims_staff where email = 'caleb@asung.ca'), true) as claims \gset
-- 얹기(실시간 자리)
create temp table rt_apply on commit drop as select public.inv_cost_fix_opening_transfer(array['TR-03975', 'TR-03976'], null, '2026-10-30-compare', false) as res;
select (res ->> 'posted') as posted, (res ->> 'skipped_no_unit_cost') as nounit, (res ->> 'amount_total_cad') as total, (res ->> 'gone_cad') as gone, (res ->> 'remaining_cad') as remaining, res -> 'by_basis' as by_basis from rt_apply;
-- 전(자연키 · id 없이)
create temp table rt_fam on commit drop as
with recursive fam as (
  select id from public.inv_layer where doc_number in ('TR-03975', 'TR-03976')
  union all select c.id from public.inv_layer c join fam f on c.parent_layer_id = f.id)
select l.doc_number, l.line_ref, l.sku, l.warehouse, l.qty, v.remaining_qty, round(v.remaining_value, 4) as remaining_value, round(v.add_amount, 4) as add_amount
  from fam join public.inv_layer l on l.id = fam.id cross join lateral public.inv_layer_value(l.id) v;
create temp table rt_adds_before on commit drop as
  select l.doc_number, l.line_ref, l.sku, l.warehouse, ca.kind, ca.amount, ca.occurred_on, ca.doc_number as add_doc, ca.line_ref as add_ref
    from public.inv_layer_cost_add ca join public.inv_layer l on l.id = ca.layer_id where ca.line_ref like 'adj:%';
create temp table rt_cons_before on commit drop as
  select l.doc_number, l.line_ref, l.sku, l.warehouse, k.reason, k.amount, k.occurred_on, k.split_basis ->> 'kind' as sb_kind, k.line_ref as k_ref
    from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where k.reason in ('cost_late', 'cost_moved') and k.line_ref like 'adj:%';
select (select count(*) from rt_adds_before) as adds_n0, (select md5(string_agg(doc_number || '|' || line_ref || '|' || sku || '|' || warehouse || '|' || kind || '|' || amount || '|' || occurred_on || '|' || add_doc || '|' || add_ref, E'\n' order by doc_number, line_ref, sku, warehouse, kind, amount, add_ref)) from rt_adds_before) as adds_md5_0,
       (select count(*) from rt_cons_before) as cons_n0, (select md5(string_agg(doc_number || '|' || line_ref || '|' || sku || '|' || warehouse || '|' || reason || '|' || amount || '|' || occurred_on || '|' || coalesce(sb_kind, '') || '|' || k_ref, E'\n' order by doc_number, line_ref, sku, warehouse, reason, amount, k_ref)) from rt_cons_before) as cons_md5_0,
       (select round(sum(remaining_value), 2) from rt_fam) as fam_val0, (select sum(remaining_qty) from rt_fam) as fam_qty0, (select count(*) from rt_fam) as fam_n0,
       (select round(sum(remaining_cost), 2) from public.inv_layer_open) as all_val0, (select round(sum(remaining_cost), 2) from public.inv_layer_open where warehouse = 'Asung - Edmonton') as edm_val0 \gset
\echo '── 전: adj 얹기 줄' :adds_n0 :adds_md5_0 '· cost_late/moved' :cons_n0 :cons_md5_0 '· 가족 남은 가치' :fam_val0 '(수량' :fam_qty0 '· 레이어' :fam_n0 ') · 전체 평가액' :all_val0 '· EDM' :edm_val0
select clock_timestamp() as t1 \gset
create temp table rt_regen on commit drop as select public.inv_layer_apply() as res;
select clock_timestamp() - :'t1'::timestamptz as regen_elapsed \gset
\echo '── inv_layer_apply() 걸린 시간' :regen_elapsed
select res -> 'ims' -> 'adjusts' as ims_adjusts, res ->> 'short_events' as short_events, res ->> 'cost_unknown_layers' as cost_unknown_layers, res ->> 'transfer_unknown_layers' as transfer_unknown_layers, res ->> 'layers_created' as layers_created, res ->> 'consume_rows' as consume_rows from rt_regen;
-- 후
create temp table rt_fam_after on commit drop as
with recursive fam as (
  select id from public.inv_layer where doc_number in ('TR-03975', 'TR-03976')
  union all select c.id from public.inv_layer c join fam f on c.parent_layer_id = f.id)
select l.doc_number, l.line_ref, l.sku, l.warehouse, l.qty, v.remaining_qty, round(v.remaining_value, 4) as remaining_value, round(v.add_amount, 4) as add_amount
  from fam join public.inv_layer l on l.id = fam.id cross join lateral public.inv_layer_value(l.id) v;
create temp table rt_adds_after on commit drop as
  select l.doc_number, l.line_ref, l.sku, l.warehouse, ca.kind, ca.amount, ca.occurred_on, ca.doc_number as add_doc, ca.line_ref as add_ref
    from public.inv_layer_cost_add ca join public.inv_layer l on l.id = ca.layer_id where ca.line_ref like 'adj:%';
create temp table rt_cons_after on commit drop as
  select l.doc_number, l.line_ref, l.sku, l.warehouse, k.reason, k.amount, k.occurred_on, k.split_basis ->> 'kind' as sb_kind, k.line_ref as k_ref
    from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where k.reason in ('cost_late', 'cost_moved') and k.line_ref like 'adj:%';
select (select count(*) from rt_adds_after) as adds_n1, (select md5(string_agg(doc_number || '|' || line_ref || '|' || sku || '|' || warehouse || '|' || kind || '|' || amount || '|' || occurred_on || '|' || add_doc || '|' || add_ref, E'\n' order by doc_number, line_ref, sku, warehouse, kind, amount, add_ref)) from rt_adds_after) as adds_md5_1,
       (select count(*) from rt_cons_after) as cons_n1, (select md5(string_agg(doc_number || '|' || line_ref || '|' || sku || '|' || warehouse || '|' || reason || '|' || amount || '|' || occurred_on || '|' || coalesce(sb_kind, '') || '|' || k_ref, E'\n' order by doc_number, line_ref, sku, warehouse, reason, amount, k_ref)) from rt_cons_after) as cons_md5_1,
       (select round(sum(remaining_value), 2) from rt_fam_after) as fam_val1, (select sum(remaining_qty) from rt_fam_after) as fam_qty1, (select count(*) from rt_fam_after) as fam_n1,
       (select round(sum(remaining_cost), 2) from public.inv_layer_open) as all_val1, (select round(sum(remaining_cost), 2) from public.inv_layer_open where warehouse = 'Asung - Edmonton') as edm_val1 \gset
\echo '── 후: adj 얹기 줄' :adds_n1 :adds_md5_1 '· cost_late/moved' :cons_n1 :cons_md5_1 '· 가족 남은 가치' :fam_val1 '(수량' :fam_qty1 '· 레이어' :fam_n1 ') · 전체 평가액' :all_val1 '· EDM' :edm_val1
select case when :adds_n0 = :adds_n1 and :'adds_md5_0' = :'adds_md5_1' then 'C1 OK' else 'C1 FAIL' end as c1_adds_same,
       case when :cons_n0 = :cons_n1 and :'cons_md5_0' = :'cons_md5_1' then 'C2 OK' else 'C2 FAIL' end as c2_cost_late_moved_same,
       case when :fam_val0 = :fam_val1 and :fam_qty0 = :fam_qty1 and :fam_n0 = :fam_n1 then 'C3 OK' else 'C3 FAIL' end as c3_family_value_same,
       case when abs(:all_val0 - :all_val1) < 0.01 and abs(:edm_val0 - :edm_val1) < 0.01 then 'C4 OK' else 'C4 FAIL' end as c4_total_value_same,
       case when (select (res -> 'ims' -> 'adjusts' ->> 'skipped')::int = 0 and (res -> 'ims' -> 'adjusts' ->> 'deferred')::int = 0 from rt_regen) then 'C5 OK' else 'C5 FAIL' end as c5_no_skip_defer;
-- 가족 레이어 단위 차이(있으면 보인다 · 기대 0 행)
select 'diff' as side, count(*) as rows_differ from (select * from rt_fam except select * from rt_fam_after union all select * from rt_fam_after except select * from rt_fam) d;
\echo '── begin ~ here:' :t0
select clock_timestamp() - :'t0'::timestamptz as begin_to_now;
rollback;
