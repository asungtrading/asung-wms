-- supabase/tests/link_perf_3.sql — link-perf-3 검증: shop_link_plan ⑤(이미 이어진 것)를 집합으로 — 이어진 것 0 · 이어진 5 천(통계 새로 · 낡음) 에서 옛 = 새 판정 한 글자도 같다 · 시간 (2026-10-28 · 판정 832)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 첫 문장 = ops/guard-test-only.sql 바이트 복사 → 기준값(begin 앞) → 트랜잭션 셋(잠금 규칙 · 회차마다 10 s 안):
--   TA 이어진 것 0: (-v mig 면 옛 plan asung · test · 가짜 run → 스냅샷 → 되돌림) → (-v mig 면 \i) → 새 plan 셋 → 옛 = 새 · 가짜 갈래 절대값 · 시간
--   TB 이어진 상태(가짜 · ANALYZE): asung run 의 link 줄로 shop_product 4,938 · shop_variant 8,363 을 집합 insert(apply 가 쓰는 것을 흉내 · 묶음 apply 16 ~ 24 s 는 잠금 규칙으로 안 돌린다) → analyze → (-v mig 면 옛 plan → 스냅샷 → 되돌림 → \i) → 새 plan → 옛 = 새 · 시간
--   TD 이어진 것 0 · 새 정의만 · 트랜잭션 첫 plan(시간 — TA 의 둘째 자리와 가르려고)
--   TC 이어진 상태(통계 낡음 · insert 뒤 ANALYZE 없이 = link-perf-2 가 12 ~ 17 s 를 본 조건의 기본 재현): (-v mig 면 \i) → 새 plan → 시간(옛 정의는 500 줄에 (라) 1,165 ms 라 전부는 안 돌린다 — 실측은 마이그레이션 머리)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028001328_link_perf_3.sql -f supabase/tests/link_perf_3.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 옛 = 새 대조와 옛 plan 은 \if :{?mig} 안 · 확인 갈래는 새 결과만(가짜 갈래 절대값 · dup_target · 시간 · 몸 · 권한)
--   기대(2026-10-28 시험 갈래 2 회차 통과 · OK 42 / 42 · MISMATCH 0 · 실제 값): 이어진 것 0 옛(첫 자리) 1,630 → 새(첫 자리) 1,798 ms · 이어진 4,938 + 변형 8,363 ANALYZE 옛 2,580 → 새 2,525 ms · 통계 낡음 새 2,700 ms(옛은 500 줄 외삽 약 12 s · 안 돌림) · 회차 TA 5.7 s · TB 7.5 s · TC 4.3 s · TD 2.1 s
--     확인 갈래(-v mig 없이) 기대 OK 33 = 42 − \if 안 9(옛 plan · 옛 = 새 대조 · 첫 자리 비교) — 셈(적용 뒤 첫 확인 실행에서 실측)
--   ⚠️ 잠금: 회차마다 begin ~ rollback 을 찍는다 · TA 약 5 s · TB 약 8 s(시험) / 5 s(확인) · TC 약 4 s — asung run 행 · item 판정 칸 · asung 스토어의 shop_product · shop_variant(0 행에서 시작 · 가짜 insert) · 다른 표는 안 잠근다
--   쓰기: 가짜 직원 1(트랜잭션마다) · run · item 판정 칸 · test 스토어 가짜 run 1 + item 8 + shop_product 4 + shop_variant 2 · asung 스토어 shop_product · shop_variant 가짜 — 전부 rollback · 시퀀스 0 · Shopify 호출 0
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
\set want_pre bff179a2600cecb4cb5ca695c9a14c77
\set EXPECT_OK 42
\else
\set want_pre bccc29e5e376895bf58d53b1f449ef9c
\set EXPECT_OK 33
\endif
select value as db_role from public.inv_config where key = 'db_role' \gset
select r.id::text as run_a, r.version as ver_a0, r.status as st_a0, r.item_count as cnt_a0, r.store_id::text as store_a from public.shop_link_run r join public.shop_store s on s.id = r.store_id where s.code = 'asung' and r.status in ('read', 'planned') order by r.started_at desc limit 1 \gset
select r.id::text as run_t, r.version as ver_t0, r.status as st_t0, r.item_count as cnt_t0 from public.shop_link_run r join public.shop_store s on s.id = r.store_id where s.code = 'test' and r.status in ('read', 'planned') order by r.started_at desc limit 1 \gset
select s.id::text as store_t from public.shop_store s where s.code = 'test' \gset
select (select count(*) from public.shop_link_item where run_id = :'run_a'::uuid) as n_a, (select count(*) from public.shop_link_item where run_id = :'run_t'::uuid) as n_t, (select count(*) from public.ims_staff) as n_staff0,
       (select count(*) from public.shop_link_run) as n_run0, (select count(*) from public.shop_product where store_id = :'store_t'::uuid) as n_sp_t0, (select count(*) from public.shop_variant where store_id = :'store_t'::uuid) as n_sv_t0,
       (select count(*) from public.shop_product where store_id = :'store_a'::uuid) as n_sp_a0, (select count(*) from public.shop_variant where store_id = :'store_a'::uuid) as n_sv_a0,
       (select count(*) from public.shop_link_item where run_id = :'run_a'::uuid and decision in ('link', 'link_off')) as n_link_a0 \gset
-- 가짜 재료 뿌리(begin 앞 · 읽기만): family 다섯(구성원 둘 이상 · 모두 활성 · parent 없음 · shop_product · shop_listing · shop_variant 어디에도 없음) · 낱개 product 둘(대소문자 섞인 SKU · lower 가 같은 다른 product 없음 · shop 표에 없음)
create temp table t_fam (k int, id uuid, sku text, opt text, s1 text, s2 text);
insert into t_fam select row_number() over (order by f.sku), f.id, f.sku, coalesce(f.option1_name, 'Option'), (array_agg(p.sku order by p.sku))[1], (array_agg(p.sku order by p.sku))[2]
  from public.product_family f join public.product p on p.family_id = f.id
 where not exists (select 1 from public.shop_product sp where sp.family_id = f.id) and not exists (select 1 from public.shop_listing l where l.family_id = f.id)
   and not exists (select 1 from public.product q where q.family_id = f.id and (q.parent_product_id is not null or not q.is_active or q.is_discontinued or exists (select 1 from public.shop_variant sv where sv.product_id = q.id)))
 group by f.id, f.sku, f.option1_name having count(p.id) >= 2 order by f.sku limit 5;
create temp table t_prd (k int, id uuid, sku text);
insert into t_prd select row_number() over (order by p.sku), p.id, p.sku from public.product p
 where p.family_id is null and p.parent_product_id is null and p.is_active and not p.is_discontinued and p.sellable and lower(p.sku) <> p.sku
   and not exists (select 1 from public.product q where q.id <> p.id and lower(q.sku) = lower(p.sku))
   and not exists (select 1 from public.shop_product sp where sp.product_id = p.id) and not exists (select 1 from public.shop_variant sv where sv.product_id = p.id) and not exists (select 1 from public.shop_listing l where l.product_id = p.id)
 order by p.sku limit 2;
select (select count(*) from t_fam) as n_fam, (select count(*) from t_prd) as n_prd, (select string_agg(sku, ' ' order by k) from t_fam) as fam_skus, (select string_agg(sku, ' ' order by k) from t_prd) as prd_skus \gset
select id::text as f1, s1 as f1s1, s2 as f1s2, opt as f1opt from t_fam where k = 1 \gset
select id::text as f2, s1 as f2s1, s2 as f2s2, opt as f2opt from t_fam where k = 2 \gset
select id::text as f3, s1 as f3s1, s2 as f3s2, opt as f3opt from t_fam where k = 3 \gset
select id::text as f4, s1 as f4s1, s2 as f4s2, opt as f4opt from t_fam where k = 4 \gset
select id::text as f5, s1 as f5s1, s2 as f5s2, opt as f5opt from t_fam where k = 5 \gset
select id::text as p1, sku as p1sku, lower(sku) as p1lc from t_prd where k = 1 \gset
select id::text as p2, sku as p2sku from t_prd where k = 2 \gset
select p.id::text as f5m1 from public.product p where p.sku = :'f5s1' \gset
\echo '── 기준: db_role' :db_role '· asung run' :run_a '(' :st_a0 '· v' :ver_a0 '· items' :n_a '· link+off' :n_link_a0 '· asung shop_product' :n_sp_a0 '· shop_variant' :n_sv_a0 ') · test run' :run_t '(' :st_t0 '· v' :ver_t0 '· items' :n_t ') · staff' :n_staff0 '· runs' :n_run0 '· test sp' :n_sp_t0 'sv' :n_sv_t0
\echo '── 가짜 재료 뿌리: family' :n_fam '(' :fam_skus ') · product' :n_prd '(' :prd_skus ')'
-- ── 도우미(세션 · begin 밖 — 트랜잭션 셋이 같이 쓴다 · t_res 행은 트랜잭션마다 찍고 되돌린다) ──
set client_min_messages = warning;
create temp table t_res (n serial, name text, ok boolean, got text, want text);
grant insert on t_res to authenticated; grant usage on sequence t_res_n_seq to authenticated;
create temp table t_snap (phase text, run_id uuid, item_id uuid, gid text, handle text, decision text, reasons text[], ims_family_id uuid, ims_product_id uuid, changes jsonb, primary key (phase, item_id));
create temp table t_out (phase text, run_id uuid, result jsonb, ms numeric);
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
create function pg_temp.snap(p_phase text, p_run uuid) returns void language sql as $$
  insert into t_snap select p_phase, run_id, id, shopify_product_gid, handle, decision, reasons, ims_family_id, ims_product_id, changes from public.shop_link_item where run_id = p_run;
$$;
create function pg_temp.rewind(p_run uuid, p_status text, p_version int, p_count int) returns void language sql as $$
  update public.shop_link_item set decision = null, reasons = '{}', ims_family_id = null, ims_product_id = null, changes = '{}'::jsonb where run_id = p_run;
  update public.shop_link_run set status = p_status, version = p_version, planned_at = null, item_count = p_count where id = p_run;
$$;
-- 옛 = 새 대조: 줄 id · decision · reasons(순서 포함 — text[] 등호) · family · product · changes 가 하나라도 다른 줄 수
create function pg_temp.cmp(p_old text, p_new text, p_run uuid) returns int language sql as $$
  select count(*)::int from t_snap o full join t_snap n on n.item_id = o.item_id and n.phase = p_new and o.phase = p_old
   where (o.phase = p_old or o.phase is null) and (n.phase = p_new or n.phase is null) and coalesce(o.run_id, n.run_id) = p_run
     and (o.item_id is null or n.item_id is null or o.decision is distinct from n.decision or o.reasons is distinct from n.reasons or o.ims_family_id is distinct from n.ims_family_id or o.ims_product_id is distinct from n.ims_product_id or o.changes is distinct from n.changes);
$$;
-- 가짜 「이어진 상태」 — apply 가 shop_product · shop_variant 에 쓰는 것을 집합 insert 로 흉내(shop_listing · last_hash 는 plan 이 안 읽는다) · 변형 → 제품은 plan 과 같은 되찾기(정확히 · 없으면 lower(sku) order by sku limit 1)
create function pg_temp.fab(p_run uuid, p_store uuid) returns text language plpgsql as $$
declare v_sp int; v_sv int; v_t timestamptz := clock_timestamp();
begin
  insert into public.shop_product (store_id, family_id, product_id, shopify_product_gid, handle, shopify_status, last_status)
  select p_store, i.ims_family_id, i.ims_product_id, i.shopify_product_gid, i.handle, i.status, 'pending'
    from public.shop_link_item i where i.run_id = p_run and i.decision in ('link', 'link_off');
  get diagnostics v_sp = row_count;
  insert into public.shop_variant (store_id, product_id, shopify_variant_gid, inventory_item_gid)
  select p_store, coalesce(pe.id, pl.id), v.val->>'variant_gid', v.val->>'inventory_item_gid'
    from public.shop_link_item i cross join lateral jsonb_array_elements(i.variants) v(val)
    left join public.product pe on pe.sku = nullif(trim(v.val->>'sku'), '')
    left join lateral (select p.id from public.product p where pe.id is null and lower(p.sku) = lower(nullif(trim(v.val->>'sku'), '')) order by p.sku limit 1) pl on true
   where i.run_id = p_run and i.decision in ('link', 'link_off') and coalesce(pe.id, pl.id) is not null;
  get diagnostics v_sv = row_count;
  return format('sp=%s sv=%s ms=%s', v_sp, v_sv, round(extract(epoch from (clock_timestamp() - v_t)) * 1000));
end $$;
-- plan 을 가짜 관리자로 돌리고 시간(ms)을 t_out 에 — 반환 JSON 에서 planned_at 을 뺀다
create function pg_temp.plan_as(p_phase text, p_run uuid, p_uid text) returns text language plpgsql as $$
declare v_t timestamptz := clock_timestamp(); v jsonb; v_err text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    v := public.shop_link_plan(p_run) - 'planned_at';
  exception when others then
    v_err := 'ERR ' || sqlstate || ': ' || sqlerrm;
  end;
  perform set_config('role', 'none', true);
  if v_err is not null then return v_err; end if;
  insert into t_out values (p_phase, p_run, v, extract(epoch from (clock_timestamp() - v_t)) * 1000);
  return 'ok';
end $$;
create function pg_temp.ms_of(p_phase text, p_run uuid) returns text language sql as $$ select round(ms)::text from t_out where phase = p_phase and run_id = p_run $$;
create function pg_temp.staff_fake() returns text language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values (v, 'linkperf3-admin@test.invalid', 'linkperf3 admin', 'admin', '[]', true);
  return v::text;
end $$;
-- 가짜 run(test 스토어 · 여덟 줄) + 이어진 흔적 — ⑤ 의 갈래마다 하나
--   a  already_linked(family)                : shop_product(F1 → G1) · 줄 G1 = [F1 첫 구성원]                       → link · already_linked
--   b  already_linked_other(family · 가)     : 줄 G2 = [F1 둘째 구성원]                                              → block · already_linked_other · linked_gid G1
--   c  already_linked(product)               : shop_product(P1 → G3) · 줄 G3 = [P1]                                  → link · already_linked
--   c2 already_linked_other(product · 가)    : 줄 G4 = [P1 소문자 SKU](sku_case · dup_sku 는 정확히 같은 SKU 만)    → block · sku_case · already_linked_other · linked_gid G3
--   d  gid_linked_elsewhere(상품 gid · 나)    : shop_product(F2 → G5) · 줄 G5 = [F3 첫 구성원](다른 family)            → block · gid_linked_elsewhere
--   e  gid_linked_elsewhere(변형 gid · 다)    : shop_product(P2 → G6) + shop_variant(P2 · V6) · 줄 G7 = [F4 첫 구성원 · variant_gid V6] → block · gid_linked_elsewhere
--   f  already_linked_other(변형 · 라)        : shop_variant(F5 첫 구성원 · V8 · shop_product 없음) · 줄 G9 = [F5 첫 구성원 · variant_gid V9] → block · already_linked_other
--   g  아무 흔적 없음                         : 줄 G10 = [F5 둘째 구성원]                                              → link(partial_family)
--   Product/0 자리표시 갈래: shop_product_gid_real_ck(link-1b)가 Product/0 행을 막아 실물이 있을 수 없다 — 코드는 그대로 · 시험 불가
create temp table t_cfg (store_t uuid, f5m1 uuid);
insert into t_cfg select :'store_t'::uuid, :'f5m1'::uuid;
create function pg_temp.fake_run() returns text language plpgsql as $$
declare v_run uuid; v_store uuid; v_f5m1 uuid; f1 t_fam; f2 t_fam; f3 t_fam; f4 t_fam; f5 t_fam; p1 t_prd; p2 t_prd;
begin
  select store_t, f5m1 into v_store, v_f5m1 from t_cfg;
  select * into f1 from t_fam where k = 1; select * into f2 from t_fam where k = 2; select * into f3 from t_fam where k = 3; select * into f4 from t_fam where k = 4; select * into f5 from t_fam where k = 5;
  select * into p1 from t_prd where k = 1; select * into p2 from t_prd where k = 2;
  insert into public.shop_link_run (store_id, status, version, item_count) values (v_store, 'read', 0, 8) returning id into v_run;
  insert into public.shop_product (store_id, family_id, product_id, shopify_product_gid, handle) values
    (v_store, f1.id, null, 'gid://shopify/Product/991000000001', 'linkperf3-a'),
    (v_store, null, p1.id, 'gid://shopify/Product/991000000003', 'linkperf3-c'),
    (v_store, f2.id, null, 'gid://shopify/Product/991000000005', 'linkperf3-d-other-family'),
    (v_store, null, p2.id, 'gid://shopify/Product/991000000006', 'linkperf3-e-other-product');
  insert into public.shop_variant (store_id, product_id, shopify_variant_gid) values
    (v_store, p2.id, 'gid://shopify/ProductVariant/991000000006'),
    (v_store, v_f5m1, 'gid://shopify/ProductVariant/991000000008');
  insert into public.shop_link_item (run_id, shopify_product_gid, handle, title, status, options, variants)
  select v_run, 'gid://shopify/Product/9910000000' || x.n, 'linkperf3-' || x.h, 'linkperf3 ' || x.h, 'ACTIVE',
         jsonb_build_array(jsonb_build_object('name', x.opt, 'values', jsonb_build_array('v'))),
         jsonb_build_array(jsonb_build_object('sku', x.sku, 'title', 'v', 'position', 1, 'variant_gid', 'gid://shopify/ProductVariant/9910000000' || x.vn, 'inventory_item_gid', 'gid://shopify/InventoryItem/9910000000' || x.vn, 'option_values', jsonb_build_array(jsonb_build_object('name', x.opt, 'value', 'v'))))
    from (values ('01', '01', 'a',  f1.opt, f1.s1), ('02', '02', 'b',  f1.opt, f1.s2), ('03', '03', 'c', 'Title', p1.sku), ('04', '04', 'c2', 'Title', lower(p1.sku)),
                 ('05', '05', 'd',  f3.opt, f3.s1), ('07', '06', 'e',  f4.opt, f4.s1), ('09', '09', 'f', f5.opt, f5.s1), ('10', '10', 'g', f5.opt, f5.s2)) as x(n, vn, h, opt, sku);
  return v_run::text;
end $$;
create function pg_temp.fake_row(p_run uuid, p_h text) returns text language sql as $$
  select decision || ':' || array_to_string(array_remove(reasons, 'no_ims_images'), ',') || coalesce(' linked=' || (changes->>'linked_gid'), '') from public.shop_link_item where run_id = p_run and handle = 'linkperf3-' || p_h;
$$;

-- ══════════ TA 이어진 것 0 · 가짜 갈래 · test run ══════════
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local client_min_messages = warning;
select clock_timestamp() as ta_begin \gset
select pg_temp.staff_fake() as u_adm \gset
select pg_temp.fake_run() as run_f \gset
select pg_temp.chk('R0 fake roots found (family 5 · product 2)', :n_fam::text || ' ' || :n_prd::text, '5 2');
select pg_temp.chk('A0 shop_link_plan before this step (md5 · 시험 갈래 = link-dup-1 · 확인 갈래 = link-perf-3)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), :'want_pre');
select pg_temp.chk('F1 fake run 8 items · test store shop_product +4 · shop_variant +2', (select count(*)::text from public.shop_link_item where run_id = :'run_f'::uuid) || ' ' || (select count(*) from public.shop_product where store_id = :'store_t'::uuid)::text || ' ' || (select count(*) from public.shop_variant where store_id = :'store_t'::uuid)::text, '8 ' || (:n_sp_t0 + 4)::text || ' ' || (:n_sv_t0 + 2)::text);
\if :{?mig}
select pg_temp.plan_as('old0', :'run_a'::uuid, :'u_adm') as r_oa, pg_temp.plan_as('old0', :'run_t'::uuid, :'u_adm') as r_ot, pg_temp.plan_as('old0', :'run_f'::uuid, :'u_adm') as r_of \gset
select pg_temp.chk('O1 old plan ran (asung · test · fake)', case when :'r_oa' <> 'ok' then :'r_oa' when :'r_ot' <> 'ok' then :'r_ot' when :'r_of' <> 'ok' then :'r_of' else 'ok' end, 'ok');
select pg_temp.snap('old0', :'run_a'::uuid); select pg_temp.snap('old0', :'run_t'::uuid); select pg_temp.snap('old0', :'run_f'::uuid);
select pg_temp.ms_of('old0', :'run_a'::uuid) as old_ms0 \gset
select pg_temp.rewind(:'run_a'::uuid, :'st_a0', :ver_a0, :cnt_a0); select pg_temp.rewind(:'run_t'::uuid, :'st_t0', :ver_t0, :cnt_t0); select pg_temp.rewind(:'run_f'::uuid, 'read', 0, 8);
\echo '── TA 옛 정의 plan(asung · 이어진 것 0)' :old_ms0 'ms'
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\else
\set old_ms0 '(skip)'
\endif
select pg_temp.chk('N1 shop_link_plan now = link-perf-3 (md5)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), 'bccc29e5e376895bf58d53b1f449ef9c');
select pg_temp.chk('N2 definer · search_path · grants (authenticated · service_role yes · anon no)', (select prosecdef::text || ' ' || array_to_string(proconfig, ',') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan') || ' ' || has_function_privilege('authenticated', 'public.shop_link_plan(uuid)', 'execute')::text || has_function_privilege('service_role', 'public.shop_link_plan(uuid)', 'execute')::text || has_function_privilege('anon', 'public.shop_link_plan(uuid)', 'execute')::text, 'true search_path=public, pg_temp truetruefalse');
select pg_temp.chk('N3 signature · comment mentions link-perf-3', (select pg_get_function_identity_arguments(oid) || ' ' || (obj_description(oid, 'pg_proc') ~ 'link-perf-3')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), 'p_run_id uuid true');
select pg_temp.plan_as('new0', :'run_a'::uuid, :'u_adm') as r_na, pg_temp.plan_as('new0', :'run_t'::uuid, :'u_adm') as r_nt, pg_temp.plan_as('new0', :'run_f'::uuid, :'u_adm') as r_nf \gset
select pg_temp.chk('N4 new plan ran (asung · test · fake)', case when :'r_na' <> 'ok' then :'r_na' when :'r_nt' <> 'ok' then :'r_nt' when :'r_nf' <> 'ok' then :'r_nf' else 'ok' end, 'ok');
select pg_temp.snap('new0', :'run_a'::uuid); select pg_temp.snap('new0', :'run_t'::uuid); select pg_temp.snap('new0', :'run_f'::uuid);
select pg_temp.ms_of('new0', :'run_a'::uuid) as new_ms0, pg_temp.ms_of('new0', :'run_t'::uuid) as new_ms0_t, pg_temp.ms_of('new0', :'run_f'::uuid) as new_ms0_f \gset
\echo '── TA 새 정의 plan(asung · 이어진 것 0)' :new_ms0 'ms · test' :new_ms0_t 'ms · fake' :new_ms0_f 'ms'
select pg_temp.chk('A1a asung (이어진 것 0): new snapshot rows = items · none null · run planned v+1', (select count(*)::text || ' ' || count(*) filter (where decision is null)::text from t_snap where phase = 'new0' and run_id = :'run_a'::uuid) || ' ' || (select status || ' ' || version::text from public.shop_link_run where id = :'run_a'::uuid), :'n_a' || ' 0 planned ' || (:ver_a0 + 1)::text);
select pg_temp.chk('A1b asung (이어진 것 0): dup_target 16 · block 91 · link 4938 · report 50 (실측 link-dup-1 · 새 결과만)', (select count(*) filter (where 'dup_target' = any(reasons))::text || ' ' || count(*) filter (where decision = 'block')::text || ' ' || count(*) filter (where decision = 'link')::text || ' ' || count(*) filter (where decision = 'report')::text from t_snap where phase = 'new0' and run_id = :'run_a'::uuid), '16 91 4938 50');
-- 가짜 갈래 절대값(새 결과만 · 두 실행 다)
select pg_temp.chk('A4a fake a: already_linked (family)',                     pg_temp.fake_row(:'run_f'::uuid, 'a'),  'link:partial_family,already_linked');
select pg_temp.chk('A4b fake b: already_linked_other (family · 가) · linked_gid', pg_temp.fake_row(:'run_f'::uuid, 'b'),  'block:partial_family,already_linked_other linked=gid://shopify/Product/991000000001');
select pg_temp.chk('A4c fake c: already_linked (product)',                    pg_temp.fake_row(:'run_f'::uuid, 'c'),  'link:already_linked');
select pg_temp.chk('A4c2 fake c2: already_linked_other (product · 가 · sku_case) · linked_gid', pg_temp.fake_row(:'run_f'::uuid, 'c2'), 'block:sku_case,already_linked_other linked=gid://shopify/Product/991000000003');
select pg_temp.chk('A4d fake d: gid_linked_elsewhere (상품 gid · 나)',           pg_temp.fake_row(:'run_f'::uuid, 'd'),  'block:partial_family,gid_linked_elsewhere');
select pg_temp.chk('A4e fake e: gid_linked_elsewhere (변형 gid · 다)',           pg_temp.fake_row(:'run_f'::uuid, 'e'),  'block:partial_family,gid_linked_elsewhere');
select pg_temp.chk('A4f fake f: already_linked_other (변형 · 라)',               pg_temp.fake_row(:'run_f'::uuid, 'f'),  'block:partial_family,already_linked_other');
select pg_temp.chk('A4g fake g: no trace = link',                              pg_temp.fake_row(:'run_f'::uuid, 'g'),  'link:partial_family');
select pg_temp.chk('A4h fake: targets null on blocks · set on links · JSON counts link 3 · block 5', (select count(*) filter (where decision = 'block' and (ims_family_id is not null or ims_product_id is not null))::text || ' ' || count(*) filter (where decision = 'link' and ims_family_id is null and ims_product_id is null)::text from t_snap where phase = 'new0' and run_id = :'run_f'::uuid) || ' ' || (select (result->'counts'->>'link') || ' ' || (result->'counts'->>'block') from t_out where phase = 'new0' and run_id = :'run_f'::uuid), '0 0 3 5');
select pg_temp.chk('A5 test run: every item decided · dup_target 0', (select count(*) filter (where decision is null)::text || '/' || count(*)::text || ' ' || count(*) filter (where 'dup_target' = any(reasons))::text from t_snap where phase = 'new0' and run_id = :'run_t'::uuid), '0/' || :'n_t' || ' 0');
\if :{?mig}
select pg_temp.chk('A3-0 asung (이어진 것 0): old = new — rows with any difference (id · decision · reasons 순서 · family · product · changes) = 0', pg_temp.cmp('old0', 'new0', :'run_a'::uuid)::text, '0');
select pg_temp.chk('A3-0b asung: returned JSON identical (counts · reasons · version)', (select (o.result = n.result)::text from t_out o join t_out n on n.run_id = o.run_id and n.phase = 'new0' where o.phase = 'old0' and o.run_id = :'run_a'::uuid), 'true');
select pg_temp.chk('A4-old fake run: old = new (eight branches)', pg_temp.cmp('old0', 'new0', :'run_f'::uuid)::text || ' ' || (select (o.result = n.result)::text from t_out o join t_out n on n.run_id = o.run_id and n.phase = 'new0' where o.phase = 'old0' and o.run_id = :'run_f'::uuid), '0 true');
select pg_temp.chk('A5-old test run: old = new', pg_temp.cmp('old0', 'new0', :'run_t'::uuid)::text || ' ' || (select (o.result = n.result)::text from t_out o join t_out n on n.run_id = o.run_id and n.phase = 'new0' where o.phase = 'old0' and o.run_id = :'run_t'::uuid), '0 true');
\endif
select pg_temp.chk('S1 shop_link_plan: no-WHERE update · delete = 0', pg_temp.nowhere((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'))::text, '0');
select pg_temp.chk('S2 body: t_link_sp · t_link_sv · t_link_lk before the loop · no per-row shop_product / shop_variant query in the loop · ⑦ dup_target kept', (select ((prosrc ~ 't_link_lk') and (prosrc ~ 'update t_link_res r') and (prosrc !~ 'select \* into v_sp') and (prosrc !~ 'p\.id = any\(v_pids\)') and (position('insert into t_link_lk' in prosrc) < position('for it in select' in prosrc)))::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), 'true');
select pg_temp.chk('S3 shop_link_apply untouched (link-perf-2 md5)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply'), '8adbc8dbdd465a3f26a81b8135785ad1');
select pg_temp.run('select set_config(''request.jwt.claims'', json_build_object(''sub'', gen_random_uuid(), ''role'', ''authenticated'')::text, true)') as r_x \gset
set local role authenticated;
select pg_temp.run('select public.shop_link_plan(''' || :'run_a' || ''')::text') as r_p1 \gset
reset role;
select pg_temp.chk('P1 login without a staff row cannot plan (nothing saved)', case when :'r_p1' like 'ERR P0001:%' then 'refused' else left(:'r_p1', 80) end, 'refused');
select n, case when ok then 'OK  ' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok_a, count(*) filter (where not ok) as bad_a from t_res \gset
select round(extract(epoch from (clock_timestamp() - :'ta_begin'::timestamptz)) * 1000)::text as ta_ms \gset
\echo '── TA OK' :ok_a '· MISMATCH' :bad_a '· begin~rollback' :ta_ms 'ms'
rollback;

-- ══════════ TB 이어진 상태(가짜 4,938 상품 · ANALYZE) ══════════
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local client_min_messages = warning;
select clock_timestamp() as tb_begin \gset
select pg_temp.staff_fake() as u_adm \gset
select pg_temp.fab(:'run_a'::uuid, :'store_a'::uuid) as fab_b \gset
analyze public.shop_product; analyze public.shop_variant;
select (select count(*) from public.shop_product where store_id = :'store_a'::uuid) as n_sp_b, (select count(*) from public.shop_variant where store_id = :'store_a'::uuid) as n_sv_b \gset
\echo '── TB 가짜 이어진 상태' :fab_b '· asung shop_product' :n_sp_b '· shop_variant' :n_sv_b '· ANALYZE 함'
select pg_temp.chk('B0 linked state: shop_product = link+off rows · shop_variant > 0', (:n_sp_b = :n_link_a0 and :n_sv_b > 0)::text || ' (' || :n_sp_b || ' · ' || :n_sv_b || ')', 'true (' || :n_sp_b || ' · ' || :n_sv_b || ')');
\if :{?mig}
select pg_temp.chk('B1 shop_link_plan before this step = link-dup-1 (md5)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), :'want_pre');
select pg_temp.plan_as('oldL', :'run_a'::uuid, :'u_adm') as r_ol \gset
select pg_temp.chk('O2 old plan ran (asung · linked · analyzed)', :'r_ol', 'ok');
select pg_temp.snap('oldL', :'run_a'::uuid);
select pg_temp.ms_of('oldL', :'run_a'::uuid) as old_msl \gset
select pg_temp.rewind(:'run_a'::uuid, :'st_a0', :ver_a0, :cnt_a0);
\echo '── TB 옛 정의 plan(asung · 이어진 4,938 · ANALYZE)' :old_msl 'ms'
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\else
\set old_msl '(skip)'
\endif
select pg_temp.plan_as('newL', :'run_a'::uuid, :'u_adm') as r_nl \gset
select pg_temp.chk('N5 new plan ran (asung · linked · analyzed)', :'r_nl', 'ok');
select pg_temp.snap('newL', :'run_a'::uuid);
select pg_temp.ms_of('newL', :'run_a'::uuid) as new_msl \gset
\echo '── TB 새 정의 plan(asung · 이어진 4,938 · ANALYZE)' :new_msl 'ms'
select pg_temp.chk('A2a asung (linked · analyzed): every link row now already_linked · dup_target 16 · no already_linked_other · no gid_linked_elsewhere (가짜 상태 = 이 판 그대로 이어진 것)', (select count(*) filter (where decision = 'link' and not ('already_linked' = any(reasons)))::text || ' ' || count(*) filter (where 'dup_target' = any(reasons))::text || ' ' || count(*) filter (where 'already_linked_other' = any(reasons) or 'gid_linked_elsewhere' = any(reasons))::text || ' link=' || count(*) filter (where decision = 'link')::text from t_snap where phase = 'newL' and run_id = :'run_a'::uuid), '0 16 0 link=4938');
\if :{?mig}
select pg_temp.chk('A3-L asung (linked · analyzed): old = new — rows with any difference = 0 · JSON identical', pg_temp.cmp('oldL', 'newL', :'run_a'::uuid)::text || ' ' || (select (o.result = n.result)::text from t_out o join t_out n on n.run_id = o.run_id and n.phase = 'newL' where o.phase = 'oldL' and o.run_id = :'run_a'::uuid), '0 true');
\endif
select pg_temp.chk('T2 asung (linked · analyzed): new plan < 3000 ms (목표)', (:new_msl::numeric < 3000)::text || ' (' || :new_msl || ' ms)', 'true (' || :new_msl || ' ms)');
select n, case when ok then 'OK  ' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok_b, count(*) filter (where not ok) as bad_b from t_res \gset
select round(extract(epoch from (clock_timestamp() - :'tb_begin'::timestamptz)) * 1000)::text as tb_ms \gset
\echo '── TB OK' :ok_b '· MISMATCH' :bad_b '· begin~rollback' :tb_ms 'ms'
rollback;

-- ══════════ TC 이어진 상태(가짜 · 통계 낡음 — insert 뒤 ANALYZE 없이) ══════════
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local client_min_messages = warning;
select clock_timestamp() as tc_begin \gset
select pg_temp.staff_fake() as u_adm \gset
select pg_temp.fab(:'run_a'::uuid, :'store_a'::uuid) as fab_c \gset
select (select n_live_tup from pg_stat_user_tables where relname = 'shop_product') as stat_sp, (select n_live_tup from pg_stat_user_tables where relname = 'shop_variant') as stat_sv \gset
\echo '── TC 가짜 이어진 상태' :fab_c '· ANALYZE 안 함(통계의 shop_product' :stat_sp '· shop_variant' :stat_sv '행)'
\if :{?mig}
\i :mig
\endif
select pg_temp.plan_as('newS', :'run_a'::uuid, :'u_adm') as r_ns \gset
select pg_temp.chk('N6 new plan ran (asung · linked · stale stats)', :'r_ns', 'ok');
select pg_temp.snap('newS', :'run_a'::uuid);
select pg_temp.ms_of('newS', :'run_a'::uuid) as new_mss \gset
\echo '── TC 새 정의 plan(asung · 이어진 4,938 · 통계 낡음)' :new_mss 'ms'
select pg_temp.chk('A2b asung (linked · stale): same shape as analyzed — link rows all already_linked · dup_target 16 · link 4938', (select count(*) filter (where decision = 'link' and not ('already_linked' = any(reasons)))::text || ' ' || count(*) filter (where 'dup_target' = any(reasons))::text || ' link=' || count(*) filter (where decision = 'link')::text from t_snap where phase = 'newS' and run_id = :'run_a'::uuid), '0 16 link=4938');
select pg_temp.chk('T3 asung (linked · stale stats): new plan < 4000 ms (8 s 의 절반 — 넘으면 멈추고 회신)', (:new_mss::numeric < 4000)::text || ' (' || :new_mss || ' ms)', 'true (' || :new_mss || ' ms)');
select pg_temp.chk('T4 asung (linked · stale stats): new plan < 3000 ms (목표)', (:new_mss::numeric < 3000)::text || ' (' || :new_mss || ' ms)', 'true (' || :new_mss || ' ms)');
select n, case when ok then 'OK  ' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok_c, count(*) filter (where not ok) as bad_c from t_res \gset
select round(extract(epoch from (clock_timestamp() - :'tc_begin'::timestamptz)) * 1000)::text as tc_ms \gset
\echo '── TC OK' :ok_c '· MISMATCH' :bad_c '· begin~rollback' :tc_ms 'ms'
rollback;

-- ══════════ TD 이어진 것 0 · 새 정의 · 트랜잭션의 첫 plan(시간만 — TA 의 새 plan 은 옛 plan 이 남긴 죽은 튜플 5,079 행 위의 둘째 자리라 옛 첫 plan 과 같은 자리가 아니다) ══════════
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local client_min_messages = warning;
select clock_timestamp() as td_begin \gset
select pg_temp.staff_fake() as u_adm \gset
\if :{?mig}
\i :mig
\endif
select pg_temp.plan_as('newD', :'run_a'::uuid, :'u_adm') as r_nd \gset
select pg_temp.chk('N7 new plan ran (asung · 이어진 것 0 · first in txn)', :'r_nd', 'ok');
select pg_temp.ms_of('newD', :'run_a'::uuid) as new_msd \gset
\echo '── TD 새 정의 plan(asung · 이어진 것 0 · 첫 자리)' :new_msd 'ms'
\if :{?mig}
select pg_temp.chk('T1-old asung (이어진 것 0 · 첫 자리끼리): new ≤ old + 500 ms (나빠지지 않음)', (:new_msd::numeric <= :old_ms0::numeric + 500)::text || ' (' || :old_ms0 || ' → ' || :new_msd || ' ms)', 'true (' || :old_ms0 || ' → ' || :new_msd || ' ms)');
\endif
select pg_temp.chk('T1 asung (이어진 것 0 · 첫 자리): new plan < 3000 ms', (:new_msd::numeric < 3000)::text || ' (' || :new_msd || ' ms)', 'true (' || :new_msd || ' ms)');
select n, case when ok then 'OK  ' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok_d, count(*) filter (where not ok) as bad_d from t_res \gset
select round(extract(epoch from (clock_timestamp() - :'td_begin'::timestamptz)) * 1000)::text as td_ms \gset
\echo '── TD OK' :ok_d '· MISMATCH' :bad_d '· begin~rollback' :td_ms 'ms'
rollback;

-- ── 합계 · rollback 뒤 실제 ──
select (:ok_a + :ok_b + :ok_c + :ok_d) as ok_n, (:bad_a + :bad_b + :bad_c + :bad_d) as bad_n \gset
\echo '── OK' :ok_n '(expect' :EXPECT_OK ') · MISMATCH' :bad_n '· 이어진 것 0: 옛(첫)' :old_ms0 '→ 새(첫)' :new_msd 'ms(TA 둘째 자리' :new_ms0 ') · 이어진 4,938 ANALYZE: 옛' :old_msl '→ 새' :new_msl 'ms · 통계 낡음 새' :new_mss 'ms · 회차 TA' :ta_ms '· TB' :tb_ms '· TC' :tc_ms '· TD' :td_ms 'ms'
select r.status as st_a1, r.version as ver_a1 from public.shop_link_run r where r.id = :'run_a'::uuid \gset
select (select count(*) from public.ims_staff) as n_staff1, (select count(*) from public.shop_link_run) as n_run1, (select count(*) from public.shop_product where store_id = :'store_a'::uuid) as n_sp_a1, (select count(*) from public.shop_variant where store_id = :'store_a'::uuid) as n_sv_a1, (select count(*) from public.shop_product where store_id = :'store_t'::uuid) as n_sp_t1 \gset
\echo '── rollback 뒤 실제: asung run' :st_a1 '· v' :ver_a1 '(전' :ver_a0 ') · staff' :n_staff0 '→' :n_staff1 '· runs' :n_run0 '→' :n_run1 '· asung sp' :n_sp_a0 '→' :n_sp_a1 '· sv' :n_sv_a0 '→' :n_sv_a1 '· test sp' :n_sp_t0 '→' :n_sp_t1
