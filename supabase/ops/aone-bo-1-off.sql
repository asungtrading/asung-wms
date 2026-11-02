do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;
-- supabase/ops/aone-bo-1-off.sql — aone 만 거래한 기존 손님의 backorder_mail 을 한 번 끈다 (2026-11-01 밤 · 판정 949 ② · Caleb 「함께 꺼줘」 — manual 20 + cin7 14 = 34)
-- [테스트 · Asung-IMS = IMS 메인(판정 617)] 위 가드(guard-test-only.sql 바이트 복사)가 운영 asung-WMS 를 막는다 · 마이그레이션 20261102020000(aone-bo-1)이 먼저 적용돼 있어야 한다(so_store_of · ops_aone_bo_off).
--   시험(끝에 rollback · Claude 또는 Caleb): psql "$(cat ~/.asung-testdb-url)" -v mode=trial -f supabase/ops/aone-bo-1-off.sql
--   실행(끝에 commit · Caleb):               psql "$(cat ~/.asung-testdb-url)" -v mode=apply -f supabase/ops/aone-bo-1-off.sql
--   mode 를 안 주면 trial · 두 모드는 마지막 한 줄(commit / rollback)만 다르다.
--   대상 = 조사 ③ 의 「aone 만」 셈 그대로: 손님의 오더(shop_order.customer_id · so — 나뉜 자식은 부모 계보로 shop_order 를 찾는다 · so_store_of) 가 전부 aone 이고 asung.ca · 직원(manual) · test 가 하나도 없는 손님.
--   멈춤: 대상 수가 -v expect(기본 34)와 다르면 아무것도 바꾸지 않는다 — 그 사이 바뀌었으면 수를 보고 -v expect=<n> 으로 다시.
--   멱등: 이미 off 인 손님은 건너뛴다(두 번 돌리면 updated 0) · 되돌리기 재료 = ops_aone_bo_off(customer_id · was_on · note) — 되돌리기 SQL 은 표 comment 에.
--   updated_by = caleb@asung.ca 직원 행(값 이력 표가 없으므로 ops_aone_bo_off 가 이력이다).
\set ON_ERROR_STOP on
\pset pager off
\if :{?mode}
\else
\set mode trial
\endif
\if :{?expect}
\else
\set expect 34
\endif
select (:'mode' = 'apply') as do_apply \gset
\echo '── mode' :mode '· expect' :expect
begin;
set local lock_timeout = '5s';
do $$ begin
  if to_regprocedure('public.so_store_of(text, text)') is null or to_regclass('public.ops_aone_bo_off') is null then
    raise exception 'STOP - aone-bo-1 migration (20261102020000) is not applied here - nothing was changed';
  end if;
end $$;
select s.id::text as caleb from public.ims_staff s where s.email = 'caleb@asung.ca' and s.is_active \gset
create temp table t_target as
with recursive root as (
  select s.id, s.id as root_id, s.split_from_id, 0 as d from public.so s
  union all
  select r.id, p.id, p.split_from_id, r.d + 1 from root r join public.so p on p.id = r.split_from_id where r.d < 20
),
rt as (select distinct on (id) id, root_id from root order by id, d desc),
so_store as (
  select s.customer_id, coalesce(st.kind, public.so_store_of(s.intake, s.ref)) as store
  from public.so s join rt on rt.id = s.id
  left join public.shop_order o on o.so_id = rt.root_id left join public.shop_store st on st.id = o.store_id
  union all
  select o.customer_id, st.kind from public.shop_order o join public.shop_store st on st.id = o.store_id where o.customer_id is not null
),
per as (
  select customer_id, bool_or(store = 'aone') as aone, bool_or(store <> 'aone') as other
  from so_store where customer_id is not null group by customer_id
)
select c.id as customer_id, c.name, c.source, c.backorder_mail
from per p join public.customer c on c.id = p.customer_id
where p.aone and not p.other
order by c.source, c.name;
select count(*) as n_target, count(*) filter (where backorder_mail) as n_on, count(*) filter (where source = 'manual') as n_manual, count(*) filter (where source = 'cin7') as n_cin7 from t_target \gset
\echo '── 대상' :n_target '(manual' :n_manual '· cin7' :n_cin7 ') · 아직 on' :n_on
select source, name, backorder_mail from t_target order by 1, 2;
create function pg_temp.stop(p_msg text) returns void language plpgsql as $$ begin raise exception '%', p_msg; end $$;   -- psql 변수는 do $$ 안에 안 들어간다 — where 로 거른 함수 호출로 멈춘다
select pg_temp.stop(format('STOP - %s target customers, expected %s - check the list above and rerun with -v expect=%s if it is right - nothing was changed', :n_target, :expect, :n_target)) where :n_target <> :expect;
select pg_temp.stop('STOP - no active staff row for caleb@asung.ca - nothing was changed') where coalesce(:'caleb', '') = '';
insert into public.ops_aone_bo_off (customer_id, was_on, note)
select t.customer_id, t.backorder_mail, format('aone-bo-1 949 ② · %s · %s', t.source, t.name) from t_target t where t.backorder_mail
on conflict (customer_id) do nothing;
update public.customer c set backorder_mail = false, updated_by = :'caleb'::uuid
from t_target t where t.customer_id = c.id and c.backorder_mail;
select count(*) as updated from t_target t join public.customer c on c.id = t.customer_id where not c.backorder_mail and t.backorder_mail \gset
select (select count(*) from t_target t join public.customer c on c.id = t.customer_id where c.backorder_mail) as still_on,
       (select count(*) from public.ops_aone_bo_off) as log_rows, :updated as updated;
do $$ begin
  if (select count(*) from t_target t join public.customer c on c.id = t.customer_id where c.backorder_mail) > 0 then raise exception 'STOP - some target customers are still on - rolled back'; end if;
end $$;
\if :do_apply
\echo '── commit (apply)'
commit;
\else
\echo '── rollback (trial)'
rollback;
\endif
