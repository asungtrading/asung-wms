-- supabase/tests/link_dup_1.sql — link-dup-1 검증: shop_link_plan 이 「한 IMS 대상 ↔ Shopify 상품 여럿」 을 전부 block(dup_target) · 그 밖의 줄은 옛 판정과 한 글자도 같다 (2026-10-27 · 판정 830)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 첫 문장 = ops/guard-test-only.sql 바이트 복사 → 기준값(begin 앞 · 잠금 없음) → begin(lock_timeout 3s) → 옛 정의로 plan(asung · test) → 스냅샷 → 되돌림 → 가짜 재료(test 스토어의 가짜 run 5 줄 + 이어진 shop_product 1) → (-v mig 면 \i) → 새 정의로 plan → 비교 → rollback → 실제 run 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027235128_link_dup_1.sql -f supabase/tests/link_dup_1.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 「옛 정의」 자리가 이미 새 정의라 A0 의 기대 md5 만 다르고(갈래로 가른다) · 옛 정의에서만 성립하는 갈래(F0 · 결함 재현)는 \if :{?mig} 안 → 확인 갈래 기대 OK = 아래 「기대」(옛 = 새 대조 O · A1 · A1c · A1f · A3 · A3b · A7b 와 결함 재현 F0 은 전부 \if :{?mig} 안 · 확인 실행은 새 결과만으로 dup_target 16 · 묶음 8 · 4 · 4 · changes 꼴 · 자기 줄 빠짐을 본다)
--   기대(2026-10-27 · 시험 갈래 -v mig 2 회차 OK 42 / 42 는 옛 틀 — 적용 뒤 고친 틀의 시험 갈래 OK 43 은 셈(확인 31 + \if 안 12 · 적용된 DB 라 다시 못 돌린다) · 확인 갈래 OK 31 은 실측(2026-10-28 4 회차) · 실제 값): asung run 2b81c902(5,079) — dup_target 16 줄(묶음 셋 8 · 4 · 4 · 모두 link · ACTIVE · partial_family) · block 75 → 91 · link 4,954 → 4,938 · link_off 0 · report 50 · 기존 block 과 겹침 0(⑦ 은 link · link_off 줄에서만 뽑는다) · 섞인(link + link_off) 묶음 0
--   ⚠️ 잠금: begin ~ rollback 한 트랜잭션 실측 8.5 s(2026-10-27 2 회차 · 옛 plan 1.6 s + 새 plan 2.0 s + 둘째 plan + 가짜 run · test run · 비교 — 1 회차는 비교 도우미가 O(n²) 라 31.6 s → 창 함수로 고침) — asung run 행(for update)과 item 5,079 행의 판정 칸 · 그 사이 화면의 Plan · Apply(그 run)는 기다린다 · 다른 표는 안 잠근다 · 10 s 를 넘으면 돌리기 전에 멈춘다(asung-workflow §4 잠금 규칙 ④)
--   ⚠️ REST(authenticated 8 s · safeupdate)는 psql 직결로 못 싣는다 — 시간(새 plan < 옛 실측 1.9 s 의 2 배)과 정적 WHERE 셈까지 · 실제 REST 한 번은 Caleb(적용 뒤 화면 Plan again)
--   쓰기: 가짜 직원 2 · asung · test run 의 판정 칸(되돌리고 다시 씀) · test 스토어에 가짜 run 1 + item 5 + shop_product 1 — 전부 rollback · 시퀀스 0 · Shopify 호출 0
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
\set ON_ERROR_STOP on
\pset pager off
\if :{?mig}
\set want_pre 95272460ee63cbe3f6c62fae80c45d9e
\set EXPECT_OK 43
\else
\set want_pre bff179a2600cecb4cb5ca695c9a14c77
\set EXPECT_OK 31
\endif
select value as db_role from public.inv_config where key = 'db_role' \gset
select r.id::text as run_a, r.version as ver_a0, r.status as st_a0, r.item_count as cnt_a0 from public.shop_link_run r join public.shop_store s on s.id = r.store_id where s.code = 'asung' and r.status in ('read', 'planned') order by r.started_at desc limit 1 \gset
select r.id::text as run_t, r.version as ver_t0, r.status as st_t0, r.item_count as cnt_t0 from public.shop_link_run r join public.shop_store s on s.id = r.store_id where s.code = 'test' and r.status in ('read', 'planned') order by r.started_at desc limit 1 \gset
select s.id::text as store_t from public.shop_store s where s.code = 'test' \gset
select (select count(*) from public.shop_link_item where run_id = :'run_a'::uuid) as n_a, (select count(*) from public.shop_link_item where run_id = :'run_t'::uuid) as n_t, (select count(*) from public.ims_staff) as n_staff0,
       (select count(*) from public.shop_link_run) as n_run0, (select count(*) from public.shop_product where store_id = :'store_t'::uuid) as n_sp_t0 \gset
-- 가짜 재료의 실물 뿌리(begin 앞 · 읽기만): 구성원 셋 이상 · 모두 활성 · parent 없음 · shop 표 어디에도 안 나온 family 둘 + 대소문자가 섞인 SKU 의 낱개 product 하나(lower 가 같은 다른 product 없음)
select f.id::text as fam1, f.sku as fam1_sku, coalesce(f.option1_name, 'Option') as fam1_opt, (array_agg(p.sku order by p.sku))[1] as f1s1, (array_agg(p.sku order by p.sku))[2] as f1s2
  from public.product_family f join public.product p on p.family_id = f.id
 where not exists (select 1 from public.shop_product sp where sp.family_id = f.id) and not exists (select 1 from public.shop_listing l where l.family_id = f.id)
   and not exists (select 1 from public.shop_link_item i where i.ims_family_id = f.id)
   and not exists (select 1 from public.product q where q.family_id = f.id and (q.parent_product_id is not null or not q.is_active or q.is_discontinued or exists (select 1 from public.shop_variant sv where sv.product_id = q.id)))
 group by f.id having count(p.id) >= 3 order by f.sku limit 1 \gset
select f.id::text as fam2, f.sku as fam2_sku, coalesce(f.option1_name, 'Option') as fam2_opt, (array_agg(p.sku order by p.sku))[1] as f2s1, (array_agg(p.sku order by p.sku))[2] as f2s2
  from public.product_family f join public.product p on p.family_id = f.id
 where f.id <> :'fam1'::uuid
   and not exists (select 1 from public.shop_product sp where sp.family_id = f.id) and not exists (select 1 from public.shop_listing l where l.family_id = f.id)
   and not exists (select 1 from public.shop_link_item i where i.ims_family_id = f.id)
   and not exists (select 1 from public.product q where q.family_id = f.id and (q.parent_product_id is not null or not q.is_active or q.is_discontinued or exists (select 1 from public.shop_variant sv where sv.product_id = q.id)))
 group by f.id having count(p.id) >= 3 order by f.sku limit 1 \gset
select p.id::text as prd, p.sku as prd_sku, lower(p.sku) as prd_sku_lc from public.product p
 where p.family_id is null and p.parent_product_id is null and p.is_active and not p.is_discontinued and p.sellable and lower(p.sku) <> p.sku
   and not exists (select 1 from public.product q where q.id <> p.id and lower(q.sku) = lower(p.sku))
   and not exists (select 1 from public.shop_product sp where sp.product_id = p.id) and not exists (select 1 from public.shop_variant sv where sv.product_id = p.id)
   and not exists (select 1 from public.shop_listing l where l.product_id = p.id) and not exists (select 1 from public.shop_link_item i where i.ims_product_id = p.id)
 order by p.sku limit 1 \gset
\echo '── 기준: db_role' :db_role '· asung run' :run_a '(' :st_a0 '· v' :ver_a0 '· items' :n_a ') · test run' :run_t '(' :st_t0 '· v' :ver_t0 '· items' :n_t ') · staff' :n_staff0 '· runs' :n_run0 '· test shop_product' :n_sp_t0
\echo '── 가짜 재료 뿌리: family 1' :fam1_sku '(' :f1s1 ',' :f1s2 '· 옵션' :fam1_opt ') · family 2' :fam2_sku '(' :f2s1 ',' :f2s2 ') · product' :prd_sku '/' :prd_sku_lc
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local client_min_messages = warning;
select clock_timestamp() as t_begin \gset
create temp table t_res (n serial, name text, ok boolean, got text, want text);
grant insert on t_res to authenticated; grant usage on sequence t_res_n_seq to authenticated;
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; c text; n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach c in array string_to_array(v, ';') loop
    if c ~* '^\s*(update|delete)\M' and c !~* '\mwhere\M' then n := n + 1; end if;
  end loop;
  return n;
end $$;
create temp table t_snap (phase text, run_id uuid, item_id uuid, gid text, handle text, decision text, reasons text[], ims_family_id uuid, ims_product_id uuid, changes jsonb, primary key (phase, item_id));
create temp table t_out (phase text, run_id uuid, result jsonb, ms numeric);
create function pg_temp.snap(p_phase text, p_run uuid) returns void language sql as $$
  insert into t_snap select p_phase, run_id, id, shopify_product_gid, handle, decision, reasons, ims_family_id, ims_product_id, changes from public.shop_link_item where run_id = p_run;
$$;
create function pg_temp.rewind(p_run uuid, p_status text, p_version int, p_count int) returns void language sql as $$
  update public.shop_link_item set decision = null, reasons = '{}', ims_family_id = null, ims_product_id = null, changes = '{}'::jsonb where run_id = p_run;
  update public.shop_link_run set status = p_status, version = p_version, planned_at = null, item_count = p_count where id = p_run;
$$;
-- 묶음 수(apply 의 t_link_todo.dup 와 같은 식): link · link_off 줄을 대상으로 묶어 2 줄 이상인 묶음의 줄 수
create function pg_temp.dup_rows(p_phase text, p_run uuid) returns int language sql as $$
  select count(*)::int from (select count(*) over (partition by coalesce(s.ims_family_id, s.ims_product_id)) as c from t_snap s where s.phase = p_phase and s.run_id = p_run and s.decision in ('link', 'link_off')) x where x.c > 1;
$$;
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values (gen_random_uuid(), 'linkdup1-admin@test.invalid', 'linkdup1 admin', 'admin', '[]', true);
select auth_user_id::text as u_adm from public.ims_staff where email = 'linkdup1-admin@test.invalid' \gset

-- ── A0 정의 ──
select pg_temp.chk('A0 shop_link_plan before this step (md5 · 시험 갈래 = link-perf-1 · 확인 갈래 = link-dup-1)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), :'want_pre');
select pg_temp.chk('A0b fake roots found (family 1 · family 2 · product)', (:'fam1' <> '' and :'fam2' <> '' and :'prd' <> '')::text, 'true');

\set old_ms_a '(skip)'
\if :{?mig}
-- ── O 옛 정의로 plan(asung · test) → 스냅샷 → 되돌림 — 옛 = 새 대조의 기준 · 시험 갈래만(확인 실행은 DB 에 새 정의뿐이라 뜻이 없다) ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select clock_timestamp() as t0 \gset
select pg_temp.run('select set_config(''app.out'', (public.shop_link_plan(''' || :'run_a' || ''') - ''planned_at'')::text, true)') as r_oa \gset
select clock_timestamp() as t1 \gset
select pg_temp.run('select set_config(''app.out2'', (public.shop_link_plan(''' || :'run_t' || ''') - ''planned_at'')::text, true)') as r_ot \gset
select clock_timestamp() as t2 \gset
reset role;
select pg_temp.chk('O1 old plan ran on both runs', case when :'r_oa' like 'ERR%' then :'r_oa' when :'r_ot' like 'ERR%' then :'r_ot' else 'ok' end, 'ok');
insert into t_out values ('old', :'run_a'::uuid, current_setting('app.out', true)::jsonb, extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000),
                         ('old', :'run_t'::uuid, current_setting('app.out2', true)::jsonb, extract(epoch from (:'t2'::timestamptz - :'t1'::timestamptz)) * 1000);
select pg_temp.snap('old', :'run_a'::uuid); select pg_temp.snap('old', :'run_t'::uuid);
select pg_temp.chk('O2 old snapshot rows = items (asung · test)', (select count(*)::text from t_snap where phase = 'old' and run_id = :'run_a'::uuid) || ' ' || (select count(*)::text from t_snap where phase = 'old' and run_id = :'run_t'::uuid), :'n_a' || ' ' || :'n_t');
select round((select ms from t_out where phase = 'old' and run_id = :'run_a'::uuid))::text as old_ms_a \gset
select pg_temp.dup_rows('old', :'run_a'::uuid) as dup_old_a, pg_temp.dup_rows('old', :'run_t'::uuid) as dup_old_t \gset
select (select count(*) from t_snap where phase = 'old' and run_id = :'run_a'::uuid and decision = 'block') as blk_old_a,
       (select count(*) from t_snap where phase = 'old' and run_id = :'run_a'::uuid and decision = 'link') as lnk_old_a,
       (select count(*) from t_snap where phase = 'old' and run_id = :'run_a'::uuid and decision = 'link_off') as off_old_a,
       (select count(*) from t_snap where phase = 'old' and run_id = :'run_a'::uuid and decision = 'report') as rep_old_a \gset
select (select count(*) from (select 1 from t_snap s where s.phase = 'old' and s.run_id = :'run_a'::uuid and s.decision in ('link', 'link_off') group by coalesce(s.ims_family_id, s.ims_product_id) having count(*) > 1) x) as grp_old_a,
       (select count(*) from (select 1 from t_snap s where s.phase = 'old' and s.run_id = :'run_a'::uuid and s.decision in ('link', 'link_off') group by coalesce(s.ims_family_id, s.ims_product_id) having count(*) > 1 and count(distinct s.decision) > 1) x) as mixed_old_a \gset
\echo '── 옛 정의 plan(asung' :n_a ') 걸린 시간' :old_ms_a 'ms · 옛 판정 block' :blk_old_a '· link' :lnk_old_a '· link_off' :off_old_a '· report' :rep_old_a '· 겹치는 대상 묶음' :grp_old_a '(줄' :dup_old_a '· link+link_off 섞인 묶음' :mixed_old_a ') · test run 겹침 줄' :dup_old_t
select pg_temp.rewind(:'run_a'::uuid, :'st_a0', :ver_a0, :cnt_a0); select pg_temp.rewind(:'run_t'::uuid, :'st_t0', :ver_t0, :cnt_t0);
select pg_temp.chk('O3 rewound: decisions null · version back', (select count(*)::text from public.shop_link_item where run_id = :'run_a'::uuid and decision is not null) || ' ' || (select version::text || ' ' || status from public.shop_link_run where id = :'run_a'::uuid), '0 ' || :ver_a0 || ' ' || :'st_a0');
\endif

-- ── F 가짜 재료(test 스토어 · rollback 됨) — 가짜 run 하나에 다섯 줄 ──
--   A5  P(ACTIVE · family 1 의 첫 구성원 하나) + Q(ARCHIVED · 같은 family 의 둘째 구성원 하나) → 옛: link + link_off · 새: 둘 다 block dup_target
--   A4  X(gid 가 shop_product 로 family 2 에 이미 이어짐 · 첫 구성원) + Y(새 gid · 같은 family 의 둘째 구성원) → X link already_linked · Y block already_linked_other · dup_target 없음(옛 = 새)
--   A5b U(낱개 product 의 SKU 그대로) + V(같은 SKU 소문자 → 대소문자 되찾기로 같은 product) → 옛: 둘 다 link(V 는 sku_case) · 새: 둘 다 block dup_target(② dup_sku 는 정확히 같은 SKU 만 세므로 여기엔 안 걸린다)
insert into public.shop_link_run (store_id, status, version, item_count) values (:'store_t'::uuid, 'read', 0, 6);
select r.id::text as run_f from public.shop_link_run r where r.store_id = :'store_t'::uuid and r.status = 'read' and r.item_count = 6 and r.version = 0 and r.started_by is null order by r.created_at desc limit 1 \gset
insert into public.shop_product (store_id, family_id, shopify_product_gid, handle) values (:'store_t'::uuid, :'fam2'::uuid, 'gid://shopify/Product/990000000003', 'linkdup1-x-linked');
insert into public.shop_link_item (run_id, shopify_product_gid, handle, title, status, options, variants)
values
  (:'run_f'::uuid, 'gid://shopify/Product/990000000001', 'linkdup1-p-active',   'linkdup1 P', 'ACTIVE',   jsonb_build_array(jsonb_build_object('name', :'fam1_opt', 'values', jsonb_build_array('a'))),
     jsonb_build_array(jsonb_build_object('sku', :'f1s1', 'title', 'a', 'position', 1, 'variant_gid', 'gid://shopify/ProductVariant/990000000001', 'inventory_item_gid', 'gid://shopify/InventoryItem/990000000001', 'option_values', jsonb_build_array(jsonb_build_object('name', :'fam1_opt', 'value', 'a'))))),
  (:'run_f'::uuid, 'gid://shopify/Product/990000000002', 'linkdup1-q-archived', 'linkdup1 Q', 'ARCHIVED', jsonb_build_array(jsonb_build_object('name', :'fam1_opt', 'values', jsonb_build_array('b'))),
     jsonb_build_array(jsonb_build_object('sku', :'f1s2', 'title', 'b', 'position', 1, 'variant_gid', 'gid://shopify/ProductVariant/990000000002', 'inventory_item_gid', 'gid://shopify/InventoryItem/990000000002', 'option_values', jsonb_build_array(jsonb_build_object('name', :'fam1_opt', 'value', 'b'))))),
  (:'run_f'::uuid, 'gid://shopify/Product/990000000003', 'linkdup1-x-linked',   'linkdup1 X', 'ACTIVE',   jsonb_build_array(jsonb_build_object('name', :'fam2_opt', 'values', jsonb_build_array('a'))),
     jsonb_build_array(jsonb_build_object('sku', :'f2s1', 'title', 'a', 'position', 1, 'variant_gid', 'gid://shopify/ProductVariant/990000000003', 'inventory_item_gid', 'gid://shopify/InventoryItem/990000000003', 'option_values', jsonb_build_array(jsonb_build_object('name', :'fam2_opt', 'value', 'a'))))),
  (:'run_f'::uuid, 'gid://shopify/Product/990000000004', 'linkdup1-y-new',      'linkdup1 Y', 'ACTIVE',   jsonb_build_array(jsonb_build_object('name', :'fam2_opt', 'values', jsonb_build_array('b'))),
     jsonb_build_array(jsonb_build_object('sku', :'f2s2', 'title', 'b', 'position', 1, 'variant_gid', 'gid://shopify/ProductVariant/990000000004', 'inventory_item_gid', 'gid://shopify/InventoryItem/990000000004', 'option_values', jsonb_build_array(jsonb_build_object('name', :'fam2_opt', 'value', 'b'))))),
  (:'run_f'::uuid, 'gid://shopify/Product/990000000005', 'linkdup1-u-exact',    'linkdup1 U', 'ACTIVE',   jsonb_build_array(jsonb_build_object('name', 'Title', 'values', jsonb_build_array('Default Title'))),
     jsonb_build_array(jsonb_build_object('sku', :'prd_sku', 'title', 'Default Title', 'position', 1, 'variant_gid', 'gid://shopify/ProductVariant/990000000005', 'inventory_item_gid', 'gid://shopify/InventoryItem/990000000005', 'option_values', jsonb_build_array(jsonb_build_object('name', 'Title', 'value', 'Default Title'))))),
  (:'run_f'::uuid, 'gid://shopify/Product/990000000006', 'linkdup1-v-lower',    'linkdup1 V', 'ACTIVE',   jsonb_build_array(jsonb_build_object('name', 'Title', 'values', jsonb_build_array('Default Title'))),
     jsonb_build_array(jsonb_build_object('sku', :'prd_sku_lc', 'title', 'Default Title', 'position', 1, 'variant_gid', 'gid://shopify/ProductVariant/990000000006', 'inventory_item_gid', 'gid://shopify/InventoryItem/990000000006', 'option_values', jsonb_build_array(jsonb_build_object('name', 'Title', 'value', 'Default Title')))));
select pg_temp.chk('F1 fake run has 6 items · test store shop_product +1', (select count(*)::text from public.shop_link_item where run_id = :'run_f'::uuid) || ' ' || (select count(*) from public.shop_product where store_id = :'store_t'::uuid)::text, '6 ' || (:n_sp_t0 + 1)::text);
\if :{?mig}
-- 결함 재현(옛 정의 · 시험 갈래만): 가짜 run 을 옛 정의로 plan 하면 P link · Q link_off · U · V link — 같은 대상을 둘이 가리키는데 막지 않는다
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run('select set_config(''app.out3'', (public.shop_link_plan(''' || :'run_f' || ''') - ''planned_at'')::text, true)') as r_of \gset
reset role;
select pg_temp.chk('F0 old plan ran on the fake run', case when :'r_of' like 'ERR%' then :'r_of' else 'ok' end, 'ok');
select pg_temp.chk('F0a old definition does NOT block the pair P · Q (link + link_off · same family) — the defect', (select string_agg(handle || '=' || decision, ' ' order by handle) from public.shop_link_item where run_id = :'run_f'::uuid and handle in ('linkdup1-p-active', 'linkdup1-q-archived')), 'linkdup1-p-active=link linkdup1-q-archived=link_off');
select pg_temp.chk('F0b old definition does NOT block the pair U · V (same product via sku_case)', (select string_agg(handle || '=' || decision || ':' || array_to_string(reasons, ','), ' ' order by handle) from public.shop_link_item where run_id = :'run_f'::uuid and handle in ('linkdup1-u-exact', 'linkdup1-v-lower')), 'linkdup1-u-exact=link: linkdup1-v-lower=link:sku_case');
select pg_temp.rewind(:'run_f'::uuid, 'read', 0, 6);
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── N 새 정의로 plan → 비교 ──
select pg_temp.chk('N1 shop_link_plan now = link-dup-1 (md5)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), 'bff179a2600cecb4cb5ca695c9a14c77');
select pg_temp.chk('N2 definer · search_path · grants unchanged (authenticated · service_role yes · anon no)', (select prosecdef::text || ' ' || array_to_string(proconfig, ',') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan') || ' ' || has_function_privilege('authenticated', 'public.shop_link_plan(uuid)', 'execute')::text || has_function_privilege('service_role', 'public.shop_link_plan(uuid)', 'execute')::text || has_function_privilege('anon', 'public.shop_link_plan(uuid)', 'execute')::text, 'true search_path=public, pg_temp truetruefalse');
select pg_temp.chk('N3 signature · comment mentions dup_target 830', (select pg_get_function_identity_arguments(oid) || ' ' || (obj_description(oid, 'pg_proc') ~ 'dup_target 830')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), 'p_run_id uuid true');
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select clock_timestamp() as t3 \gset
select pg_temp.run('select set_config(''app.out'', (public.shop_link_plan(''' || :'run_a' || ''') - ''planned_at'')::text, true)') as r_na \gset
select clock_timestamp() as t4 \gset
select pg_temp.run('select set_config(''app.out2'', (public.shop_link_plan(''' || :'run_t' || ''') - ''planned_at'')::text, true)') as r_nt \gset
select clock_timestamp() as t5 \gset
select pg_temp.run('select set_config(''app.out3'', (public.shop_link_plan(''' || :'run_f' || ''') - ''planned_at'')::text, true)') as r_nf \gset
select clock_timestamp() as t6 \gset
reset role;
select pg_temp.chk('N4 new plan ran on asung · test · fake runs', case when :'r_na' like 'ERR%' then :'r_na' when :'r_nt' like 'ERR%' then :'r_nt' when :'r_nf' like 'ERR%' then :'r_nf' else 'ok' end, 'ok');
insert into t_out values ('new', :'run_a'::uuid, current_setting('app.out', true)::jsonb, extract(epoch from (:'t4'::timestamptz - :'t3'::timestamptz)) * 1000),
                         ('new', :'run_t'::uuid, current_setting('app.out2', true)::jsonb, extract(epoch from (:'t5'::timestamptz - :'t4'::timestamptz)) * 1000),
                         ('new', :'run_f'::uuid, current_setting('app.out3', true)::jsonb, extract(epoch from (:'t6'::timestamptz - :'t5'::timestamptz)) * 1000);
select pg_temp.snap('new', :'run_a'::uuid); select pg_temp.snap('new', :'run_t'::uuid); select pg_temp.snap('new', :'run_f'::uuid);
select round((select ms from t_out where phase = 'new' and run_id = :'run_a'::uuid))::text as new_ms_a, round((select ms from t_out where phase = 'new' and run_id = :'run_t'::uuid))::text as new_ms_t, round((select ms from t_out where phase = 'new' and run_id = :'run_f'::uuid))::text as new_ms_f \gset
select (select count(*) from t_snap where phase = 'new' and run_id = :'run_a'::uuid and 'dup_target' = any(reasons)) as dup_new_a \gset
\echo '── 새 정의 plan(asung' :n_a ') 걸린 시간' :new_ms_a 'ms · test(' :n_t ')' :new_ms_t 'ms · fake(6)' :new_ms_f 'ms · asung dup_target 줄' :dup_new_a

-- A1 asung: dup_target 줄 수 = 옛 판정에서 같은 대상을 둘 이상이 가리키던 줄 수(16 · 실측) · block = 옛 block + 그 수(겹침 0 — ⑦ 은 link · link_off 에서만 뽑는다) · link + link_off 는 그만큼 준다 · report 무변
select pg_temp.chk('A1b asung: dup_target rows = 16 (실측 2026-10-27 · 묶음 8 + 4 + 4)', :'dup_new_a', '16');
select pg_temp.chk('A1d asung: every dup_target row is block with no target', (select count(*)::text from t_snap where phase = 'new' and run_id = :'run_a'::uuid and 'dup_target' = any(reasons) and not (decision = 'block' and ims_family_id is null and ims_product_id is null)), '0');
select pg_temp.chk('A1e asung: returned JSON counts · reasons agree with the snapshot (block · link · dup_target · version)', (select (result->'counts'->>'block') || ' ' || (result->'counts'->>'link') || ' ' || coalesce(result->'reasons'->>'dup_target', '0') || ' v' || (result->>'version') from t_out where phase = 'new' and run_id = :'run_a'::uuid), (select count(*) filter (where decision = 'block') || ' ' || count(*) filter (where decision = 'link') || ' ' || count(*) filter (where 'dup_target' = any(reasons)) from t_snap where phase = 'new' and run_id = :'run_a'::uuid) || ' v' || (:ver_a0 + 1)::text);
-- A2 묶음마다 한 줄(새 결과만 · 옛 기준 없음): 묶음 열쇠 = 자기 gid ∪ changes.dup_target.gids 를 정렬한 집합 · family 는 첫 변형 SKU 의 product 로
\echo '── A2 dup_target 묶음(asung · 새 판정) — family · n · handles'
select min(f.sku) as family_sku, count(*) as n, string_agg(s.handle, ' ' order by s.handle, s.gid) as handles
  from t_snap s join public.shop_link_item i on i.id = s.item_id left join public.product p on p.sku = i.variants->0->>'sku' left join public.product_family f on f.id = p.family_id
 where s.phase = 'new' and s.run_id = :'run_a'::uuid and 'dup_target' = any(s.reasons)
 group by (select string_agg(g, ',' order by g) from jsonb_array_elements_text(s.changes->'dup_target'->'gids' || to_jsonb(s.gid)) g) order by 2 desc, 1;
select pg_temp.chk('A2 asung: dup_target groups by gid set = 3 (실측 · 8 · 4 · 4)', (select string_agg(n::text, ' ' order by n desc) from (select count(*) as n from t_snap s where s.phase = 'new' and s.run_id = :'run_a'::uuid and 'dup_target' = any(s.reasons) group by (select string_agg(g, ',' order by g) from jsonb_array_elements_text(s.changes->'dup_target'->'gids' || to_jsonb(s.gid)) g)) x), '8 4 4');
select pg_temp.chk('A2b asung: changes.dup_target — count = gids + 1 = handles + 1 · self not listed · every listed gid is a dup_target row with the same count that lists me back · gids · handles in (handle, gid) order',
  (select count(*)::text from t_snap s where s.phase = 'new' and s.run_id = :'run_a'::uuid and 'dup_target' = any(s.reasons)
    and not ((s.changes->'dup_target'->>'count')::int = jsonb_array_length(s.changes->'dup_target'->'gids') + 1
         and jsonb_array_length(s.changes->'dup_target'->'handles') = jsonb_array_length(s.changes->'dup_target'->'gids')
         and not (s.changes->'dup_target'->'gids') ? s.gid
         and (select count(*) from jsonb_array_elements_text(s.changes->'dup_target'->'gids') g join t_snap z on z.phase = 'new' and z.run_id = s.run_id and z.gid = g
               where 'dup_target' = any(z.reasons) and (z.changes->'dup_target'->>'count')::int = (s.changes->'dup_target'->>'count')::int and (z.changes->'dup_target'->'gids') ? s.gid) = jsonb_array_length(s.changes->'dup_target'->'gids')
         and (s.changes->'dup_target'->'gids') = (select jsonb_agg(z.gid order by z.handle, z.gid) from t_snap z where z.phase = 'new' and z.run_id = s.run_id and (s.changes->'dup_target'->'gids') ? z.gid)
         and (s.changes->'dup_target'->'handles') = (select jsonb_agg(z.handle order by z.handle, z.gid) from t_snap z where z.phase = 'new' and z.run_id = s.run_id and (s.changes->'dup_target'->'gids') ? z.gid))), '0');
-- A3 새 결과만: 줄 수 · null 없음 · run 행 · apply 의 dup 갈래 0 — 옛 = 새 대조(A3 · A3b)는 아래 \if :{?mig} 안
select pg_temp.chk('A3c asung: new snapshot rows = items · no null decision', (select count(*)::text || ' ' || count(*) filter (where decision is null)::text from t_snap where phase = 'new' and run_id = :'run_a'::uuid), :'n_a' || ' 0');
select pg_temp.chk('A3d asung: run row after new plan — planned · version +1 · item_count', (select status || ' ' || version::text || ' ' || item_count::text from public.shop_link_run where id = :'run_a'::uuid), 'planned ' || (:ver_a0 + 1)::text || ' ' || :'n_a');
select pg_temp.chk('A3e asung: after the new plan no link/link_off group shares a target (apply t_link_todo.dup branch would see 0 rows)', pg_temp.dup_rows('new', :'run_a'::uuid)::text, '0');
\if :{?mig}
-- 옛 = 새 대조(시험 갈래만): A1 · A1c · A1f · A3 · A3b
select pg_temp.chk('A1 asung: dup_target rows = rows of old link/link_off groups sharing a target (실측 16)', :'dup_new_a', :'dup_old_a');
select pg_temp.chk('A1c asung: block = old block + dup rows · link + link_off = old − dup rows · report same',
  (select count(*) filter (where decision = 'block') || ' ' || count(*) filter (where decision in ('link', 'link_off')) || ' ' || count(*) filter (where decision = 'report') from t_snap where phase = 'new' and run_id = :'run_a'::uuid),
  (:blk_old_a + :dup_old_a)::text || ' ' || (:lnk_old_a + :off_old_a - :dup_old_a)::text || ' ' || :rep_old_a);
select pg_temp.chk('A1f asung: mixed link + link_off groups in the old plan = 0 (실측 · Caleb 의 판단 근거)', :'mixed_old_a', '0');
select pg_temp.chk('A3 asung: rows without dup_target — any difference vs old (decision · reasons · family · product · changes) = 0',
  (select count(*)::text from t_snap o full join t_snap n on n.item_id = o.item_id and n.phase = 'new' and o.phase = 'old'
    where (o.phase = 'old' or o.phase is null) and (n.phase = 'new' or n.phase is null) and coalesce(o.run_id, n.run_id) = :'run_a'::uuid
      and not ('dup_target' = any(coalesce(n.reasons, '{}')))
      and (o.item_id is null or n.item_id is null or o.decision is distinct from n.decision or o.reasons is distinct from n.reasons or o.ims_family_id is distinct from n.ims_family_id or o.ims_product_id is distinct from n.ims_product_id or o.changes is distinct from n.changes)), '0');
select pg_temp.chk('A3b asung: dup_target rows — old was link/link_off · new reasons = old || dup_target · new changes − dup_target = old changes · target was not null',
  (select count(*)::text from t_snap n join t_snap o on o.item_id = n.item_id and o.phase = 'old' where n.phase = 'new' and n.run_id = :'run_a'::uuid and 'dup_target' = any(n.reasons)
      and not (o.decision in ('link', 'link_off') and n.reasons = o.reasons || '{dup_target}'::text[] and (n.changes - 'dup_target') = o.changes and coalesce(o.ims_family_id, o.ims_product_id) is not null)), '0');
\endif
-- A4 · A5 · A5b 가짜 run
select pg_temp.chk('A4 fake: X already linked (same gid) = link · already_linked · no dup_target (no_ims_images stripped — depends on the picked family)', (select decision || ':' || array_to_string(array_remove(reasons, 'no_ims_images'), ',') || ' fam=' || (ims_family_id = :'fam2'::uuid)::text from t_snap where phase = 'new' and run_id = :'run_f'::uuid and handle = 'linkdup1-x-linked'), 'link:partial_family,already_linked fam=true');
select pg_temp.chk('A4b fake: Y same family · other gid = block · already_linked_other · linked_gid · no dup_target', (select decision || ':' || array_to_string(array_remove(reasons, 'no_ims_images'), ',') || ' ' || (changes->>'linked_gid') || ' tgt=' || coalesce(ims_family_id::text, 'null') from t_snap where phase = 'new' and run_id = :'run_f'::uuid and handle = 'linkdup1-y-new'), 'block:partial_family,already_linked_other gid://shopify/Product/990000000003 tgt=null');
select pg_temp.chk('A5 fake: P (ACTIVE) + Q (ARCHIVED) same family = both block · dup_target · no target (no_ims_images stripped)', (select string_agg(handle || '=' || decision || ':' || array_to_string(array_remove(reasons, 'no_ims_images'), ',') || ' tgt=' || coalesce(ims_family_id::text, 'null'), ' ' order by handle) from t_snap where phase = 'new' and run_id = :'run_f'::uuid and handle in ('linkdup1-p-active', 'linkdup1-q-archived')), 'linkdup1-p-active=block:partial_family,dup_target tgt=null linkdup1-q-archived=block:partial_family,archived,dup_target tgt=null');
select pg_temp.chk('A5a fake: P changes.dup_target = {count 2 · gids [Q] · handles [Q]} · images kept', (select (changes->'dup_target')::text || ' ' || (changes ? 'images')::text from t_snap where phase = 'new' and run_id = :'run_f'::uuid and handle = 'linkdup1-p-active'), '{"gids": ["gid://shopify/Product/990000000002"], "count": 2, "handles": ["linkdup1-q-archived"]} true');
select pg_temp.chk('A5b fake: U (exact SKU) + V (lower-case SKU → same product) = both block · dup_target (product target · dup_sku not involved)', (select string_agg(handle || '=' || decision || ':' || array_to_string(array_remove(reasons, 'no_ims_images'), ',') || ' tgt=' || coalesce(ims_product_id::text, 'null'), ' ' order by handle) from t_snap where phase = 'new' and run_id = :'run_f'::uuid and handle in ('linkdup1-u-exact', 'linkdup1-v-lower')), 'linkdup1-u-exact=block:dup_target tgt=null linkdup1-v-lower=block:sku_case,dup_target tgt=null');
select pg_temp.chk('A5c fake: returned JSON — counts block 5 (P Q U V + Y) · link 1 (X) · reasons dup_target 4 · items 6 · version 1', (select (result->'counts'->>'block') || ' ' || (result->'counts'->>'link') || ' ' || (result->'reasons'->>'dup_target') || ' ' || (result->>'items') || ' v' || (result->>'version') from t_out where phase = 'new' and run_id = :'run_f'::uuid), '5 1 4 6 v1');
-- A7 test 스토어 run: dup_target 0 · 판정 무변 · 반환 JSON 같음
select pg_temp.chk('A7 test run: dup_target 0 · every item decided', (select count(*) filter (where 'dup_target' = any(reasons))::text || ' ' || count(*) filter (where decision is null)::text || '/' || count(*)::text from t_snap where phase = 'new' and run_id = :'run_t'::uuid), '0 0/' || :'n_t');
\if :{?mig}
select pg_temp.chk('A7b test run: any difference vs old = 0 · JSON identical (시험 갈래만)',
  (select count(*)::text from t_snap o full join t_snap n on n.item_id = o.item_id and n.phase = 'new' and o.phase = 'old'
    where (o.phase = 'old' or o.phase is null) and (n.phase = 'new' or n.phase is null) and coalesce(o.run_id, n.run_id) = :'run_t'::uuid
      and (o.item_id is null or n.item_id is null or o.decision is distinct from n.decision or o.reasons is distinct from n.reasons or o.ims_family_id is distinct from n.ims_family_id or o.ims_product_id is distinct from n.ims_product_id or o.changes is distinct from n.changes)) || ' ' ||
  (select (o.result = n.result)::text from t_out o join t_out n on n.run_id = o.run_id and n.phase = 'new' where o.phase = 'old' and o.run_id = :'run_t'::uuid), '0 true');
\endif
-- 두 번째 plan(멱등 · version +1 만)
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select clock_timestamp() as t7 \gset
select pg_temp.run('select set_config(''app.out'', (public.shop_link_plan(''' || :'run_a' || ''') - ''planned_at'')::text, true)') as r_n2 \gset
select clock_timestamp() as t8 \gset
reset role;
select pg_temp.snap('new2', :'run_a'::uuid);
insert into t_out values ('new2', :'run_a'::uuid, current_setting('app.out', true)::jsonb, extract(epoch from (:'t8'::timestamptz - :'t7'::timestamptz)) * 1000);
select pg_temp.chk('C9 asung: second new plan (planned → planned) same decisions · version +2', case when :'r_n2' like 'ERR%' then :'r_n2' else
  (select count(*)::text from t_snap a join t_snap b on b.item_id = a.item_id and b.phase = 'new2' where a.phase = 'new' and a.run_id = :'run_a'::uuid
     and (a.decision is distinct from b.decision or a.reasons is distinct from b.reasons or a.ims_family_id is distinct from b.ims_family_id or a.ims_product_id is distinct from b.ims_product_id or a.changes is distinct from b.changes)) || ' v' || (select result->>'version' from t_out where phase = 'new2') end, '0 v' || (:ver_a0 + 2)::text);

-- ── T 시간(A6) ──
select pg_temp.chk('T1 new plan asung < 8000 ms (authenticated statement_timeout)', (:new_ms_a::numeric < 8000)::text || ' (' || :new_ms_a || ' ms)', 'true (' || :new_ms_a || ' ms)');
select pg_temp.chk('T2 new plan asung < 3800 ms (옛 실측 1.9 s 의 2 배)', (:new_ms_a::numeric < 3800)::text || ' (' || :new_ms_a || ' ms)', 'true (' || :new_ms_a || ' ms)');
select pg_temp.chk('T3 second new plan asung < 3800 ms', ((select ms from t_out where phase = 'new2') < 3800)::text, 'true');
select pg_temp.chk('T4 new plan test run < 1000 ms · fake run < 1000 ms', (:new_ms_t::numeric < 1000 and :new_ms_f::numeric < 1000)::text, 'true');

-- ── S safeupdate 정적 셈 · 몸 · apply 무접촉 ──
select pg_temp.chk('S1 shop_link_plan: no-WHERE update · delete = 0', pg_temp.nowhere((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'))::text, '0');
select pg_temp.chk('S2 body: ⑦ updates t_link_res before the single update … from · link-perf-1 tables kept', (select ((prosrc ~ 'update t_link_res r') and (prosrc ~ 't_link_var') and (prosrc ~ 't_link_dup') and (prosrc ~ 'update public\.shop_link_item i set') and (position('update t_link_res r' in prosrc) < position('update public.shop_link_item i set' in prosrc)))::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), 'true');
select pg_temp.chk('S3 shop_link_apply untouched (link-perf-2 md5)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply'), '8adbc8dbdd465a3f26a81b8135785ad1');
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values (gen_random_uuid(), 'linkdup1-worker@test.invalid', 'linkdup1 worker', 'worker', '[]', true);
select auth_user_id::text as u_wrk from public.ims_staff where email = 'linkdup1-worker@test.invalid' \gset
select set_config('request.jwt.claims', json_build_object('sub', :'u_wrk', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run('select public.shop_link_plan(''' || :'run_a' || ''')::text') as r_p1 \gset
reset role;
select pg_temp.chk('P1 worker without the shopify key cannot plan (ims_require_write · nothing saved)', case when :'r_p1' like 'ERR P0001:%' then 'refused' else left(:'r_p1', 80) end, 'refused');

-- ── 결과 ──
select clock_timestamp() as t_end \gset
select n, case when ok then 'OK  ' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok_n, count(*) filter (where not ok) as bad_n, count(*) as total from t_res \gset
select round(extract(epoch from (:'t_end'::timestamptz - :'t_begin'::timestamptz)) * 1000)::text as txn_ms \gset
\echo '── OK' :ok_n '/ ' :total '(expect' :EXPECT_OK ') · MISMATCH' :bad_n '· 옛 plan' :old_ms_a 'ms → 새 plan' :new_ms_a 'ms(asung' :n_a ') · test' :new_ms_t 'ms · fake' :new_ms_f 'ms · begin~end' :txn_ms 'ms (' :t_begin '→' :t_end ')'
rollback;
select r.status as st_a1, r.version as ver_a1, coalesce(r.planned_at::text, 'null') as pl_a1 from public.shop_link_run r where r.id = :'run_a'::uuid \gset
select (select count(*) from public.shop_link_item where run_id = :'run_a'::uuid and decision is not null) as dec_a1, (select count(*) from public.ims_staff) as n_staff1, (select count(*) from public.shop_link_run) as n_run1, (select count(*) from public.shop_product where store_id = :'store_t'::uuid) as n_sp_t1 \gset
\echo '── rollback 뒤 실제: asung run' :st_a1 '· v' :ver_a1 '· planned_at' :pl_a1 '· decided items' :dec_a1 '(planned 판은 그대로 · version 무변) · staff' :n_staff0 '→' :n_staff1 '· runs' :n_run0 '→' :n_run1 '· test shop_product' :n_sp_t0 '→' :n_sp_t1
