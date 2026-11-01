-- supabase/ops/cost-fix-1-apply.sql — cost-fix-1 적용: TR-03975 · TR-03976 도착 레이어 259 에 원가 사건을 얹는다 (2026-11-01 · 판정 932)
-- [테스트 · Asung-IMS = IMS 메인(판정 617)] 마이그레이션 20261101160000 이 먼저 적용돼 있어야 한다(아래 가드가 prosrc 로 확인).
--   시험(끝에 rollback · Claude 또는 Caleb): psql "$(cat ~/.asung-testdb-url)" -v mode=trial -f supabase/ops/cost-fix-1-apply.sql
--   실행(끝에 commit · Caleb):               psql "$(cat ~/.asung-testdb-url)" -v mode=apply -f supabase/ops/cost-fix-1-apply.sql
--   mode 를 안 주면 trial 이다. 두 모드는 마지막 한 줄(commit / rollback)만 다르다.
--   열쇠: caleb@asung.ca(admin · ims_can_write purchasing 통과) — request.jwt.claims 를 reload §H 꼴로 세운다 · 사건 created_by = 그 직원
--   멱등: 두 번 돌리면 두 번째는 posted 0 · skipped_already_fixed 259
--   되돌리기: 사건마다 inv_cost_adjust_reverse(id) — 사건은 지우지 않는다(판정 391)
\set ON_ERROR_STOP on
\pset pager off
\if :{?mode}
\else
\set mode trial
\endif
\echo mode = :mode
select coalesce((select value from public.inv_config where key = 'db_role'), '(missing)') as db_role \gset
select (:'db_role' = 'test') as is_test \gset
\if :is_test
\else
\echo 'STOP — inv_config.db_role is not test — nothing was run'
\quit
\endif
begin;
set local lock_timeout = '30s';
-- 가드: 마이그레이션 적용됐나(새 창구 둘 · 위임 · layer 갈래)
do $$ begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_post_opening_fix', 'inv_cost_fix_opening_transfer')) <> 2
     or not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_layer_apply_flush_adds' and p.prosrc like '%if v_adj.target_type = ''layer'' then%')
     or not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_layer_post_cost_adjust' and p.prosrc like '%inv_layer_post_opening_fix(p_adjust_id, p_on)%') then
    raise exception 'STOP — migration 20261101160000_cost_fix_1 is not applied here (functions missing) — apply it first with psql -1 -f';
  end if;
end $$;
select set_config('request.jwt.claims', (select jsonb_build_object('sub', auth_user_id, 'role', 'authenticated')::text from public.ims_staff where email = 'caleb@asung.ca' and is_active), true) as claims \gset
-- 전
select (select count(*) from public.inv_layer where doc_number in ('TR-03975', 'TR-03976') and cost_source = 'unknown') as roots_unknown,
       (select round(sum(remaining_cost), 2) from public.inv_layer_open where warehouse = 'Asung - Edmonton') as edm_value_before,
       (select round(sum(value), 2) from public.inv_snapshot where snapshot_key = '2026-10-30-compare' and warehouse = 'Asung - Edmonton') as edm_compare_1030,
       (select count(*) from public.inv_layer_open o where o.warehouse = 'Asung - Edmonton' and o.remaining_cost = 0 and o.remaining_qty > 0 and o.origin_type = 'transfer') as edm_zero_open_transfer_before,
       (select count(*) from public.inv_cost_adjust where kind = 'opening_fix') as opening_fix_events_before;
-- 얹기
create temp table cf1 on commit drop as select public.inv_cost_fix_opening_transfer(array['TR-03975', 'TR-03976'], null, '2026-10-30-compare', false) as res;
select res ->> 'layers_seen' as layers_seen, res ->> 'posted' as posted, res ->> 'skipped_already_fixed' as already, res ->> 'skipped_no_unit_cost' as no_unit_cost,
       res ->> 'amount_total_cad' as amount_total, res ->> 'gone_cad' as gone_cost_late, res ->> 'remaining_cad' as remaining_on_layers from cf1;
select jsonb_pretty(res -> 'by_basis') as by_basis from cf1;
select e ->> 'status' as status, e ->> 'basis' as basis, count(*) as skus, sum((e ->> 'qty')::numeric) as qty, round(sum((e ->> 'amount_cad')::numeric), 2) as amount
  from cf1, jsonb_array_elements(res -> 'lines') e group by 1, 2 order by 1, 2;
-- 갈래가 기초가 아닌 SKU 와 건너뛴 SKU(있으면 전부 보인다)
select e ->> 'sku' as sku, e ->> 'doc_number' as doc, e ->> 'qty' as qty, e ->> 'remaining_qty' as root_remaining, e ->> 'unit_cost' as unit_cost, e ->> 'basis' as basis, e ->> 'status' as status
  from cf1, jsonb_array_elements(res -> 'lines') e where coalesce(e ->> 'basis', '') not in ('baseline_other_wh') order by 1;
-- 후
select (select count(*) from public.inv_layer_open o where o.warehouse = 'Asung - Edmonton' and o.remaining_cost = 0 and o.remaining_qty > 0 and o.origin_type = 'transfer') as edm_zero_open_transfer_after,
       (select round(sum(remaining_cost), 2) from public.inv_layer_open where warehouse = 'Asung - Edmonton') as edm_value_after,
       (select round(sum(value), 2) from public.inv_snapshot where snapshot_key = '2026-10-30-compare' and warehouse = 'Asung - Edmonton') as edm_compare_1030,
       (select count(*) from public.inv_cost_adjust where kind = 'opening_fix' and status = 'posted') as opening_fix_posted,
       (select round(sum(k.amount), 2) from public.inv_layer_consume k where k.reason = 'cost_late' and k.line_ref like 'adj:%') as cost_late_total;
-- 가족 0 원 열린 레이어(뿌리 · 자식) — 기대 0
with recursive fam as (
  select id from public.inv_layer where doc_number in ('TR-03975', 'TR-03976')
  union all select c.id from public.inv_layer c join fam f on c.parent_layer_id = f.id)
select count(*) as family_layers, count(*) filter (where v.remaining_qty > 0) as family_open, count(*) filter (where v.remaining_qty > 0 and v.remaining_value = 0) as family_open_zero_value_expect_0,
       round(sum(v.remaining_value), 2) as family_remaining_value
  from fam cross join lateral public.inv_layer_value(fam.id) v;
select :'mode' = 'apply' as is_apply \gset
\if :is_apply
\echo === COMMIT (mode=apply)
commit;
\else
\echo === ROLLBACK (mode=trial)
rollback;
\endif
