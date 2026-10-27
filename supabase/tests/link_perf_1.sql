-- supabase/tests/link_perf_1.sql — link-perf-1 검증: shop_link_plan 집합 한 번(5,079 상품 31 s → 3 s 안) · 옛 판정과 한 글자도 같다 (2026-10-27 · 판정 555 ~ 558 · 562)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — begin → 옛 정의로 plan(asung · test 두 run) → 판정 스냅샷 → run · item 을 plan 전 상태로 되돌림(같은 트랜잭션 · rollback 됨) → (-v mig 면 \i) → 새 정의로 plan → 스냅샷 비교(차이 0 · 반환 JSON 같음 · version 같음) → 시간 → rollback → 실제 run 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027202614_link_perf_1.sql -f supabase/tests/link_perf_1.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 「옛 정의」 자리가 이미 새 정의라 A1 의 기대 md5 만 다르고(갈래로 가른다) OK 수는 같다
--   ⚠️ 잠금: 옛 plan 이 asung run 행(for update)과 item 5,079 행을 약 31 s 쥔다 + 새 plan 두 번 — 트랜잭션 한 번에 약 40 s · 그 사이 화면의 Plan · Apply(그 run)는 기다린다 · 다른 표는 잠그지 않는다
--   ⚠️ REST(authenticated 8 s · safeupdate)는 psql 직결로 못 싣는다 — 여기서는 시간(새 plan < 3 s · < 8 s)과 정적 WHERE 셈까지 · 실제 REST 한 번은 Caleb(적용 뒤 화면 Plan 또는 회신의 curl)
--   쓰기: 가짜 직원 1 · run · item 의 판정 칸(되돌리고 다시 씀) — 전부 rollback · 시퀀스 0 · Shopify 호출 0
\set ON_ERROR_STOP on
\set EXPECT_OK 26
\pset pager off
\if :{?mig}
\set want_pre 7b3d7266c0e8c4c2865ec74f3b3b8737
\else
\set want_pre 95272460ee63cbe3f6c62fae80c45d9e
\endif
select value as db_role from public.inv_config where key = 'db_role' \gset
select r.id::text as run_a, r.version as ver_a0, r.status as st_a0, r.item_count as cnt_a0 from public.shop_link_run r join public.shop_store s on s.id = r.store_id where s.code = 'asung' and r.status in ('read', 'planned') order by r.started_at desc limit 1 \gset
select r.id::text as run_t, r.version as ver_t0, r.status as st_t0, r.item_count as cnt_t0 from public.shop_link_run r join public.shop_store s on s.id = r.store_id where s.code = 'test' and r.status in ('read', 'planned') order by r.started_at desc limit 1 \gset
select (select count(*) from public.shop_link_item where run_id = :'run_a'::uuid) as n_a, (select count(*) from public.shop_link_item where run_id = :'run_t'::uuid) as n_t, (select count(*) from public.ims_staff) as n_staff0 \gset
\echo '── 기준: db_role' :db_role '· asung run' :run_a '(' :st_a0 '· v' :ver_a0 '· items' :n_a ') · test run' :run_t '(' :st_t0 '· v' :ver_t0 '· items' :n_t ') · staff' :n_staff0
begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
set local client_min_messages = warning;                                                         -- create temp table if not exists 의 NOTICE 를 끈다
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
-- 판정 스냅샷(옛 · 새 · 새 두 번째) — 비교 칸 다섯
create temp table t_snap (phase text, run_id uuid, item_id uuid, decision text, reasons text[], ims_family_id uuid, ims_product_id uuid, changes jsonb, primary key (phase, item_id));
create temp table t_out (phase text, run_id uuid, result jsonb, ms numeric);
create function pg_temp.snap(p_phase text, p_run uuid) returns void language sql as $$
  insert into t_snap select p_phase, run_id, id, decision, reasons, ims_family_id, ims_product_id, changes from public.shop_link_item where run_id = p_run;
$$;
-- plan 전 상태로 되돌리기(같은 트랜잭션 · rollback 됨) — 새 정의가 옛 정의와 같은 출발점에서 돌게
create function pg_temp.rewind(p_run uuid, p_status text, p_version int, p_count int) returns void language sql as $$
  update public.shop_link_item set decision = null, reasons = '{}', ims_family_id = null, ims_product_id = null, changes = '{}'::jsonb where run_id = p_run;
  update public.shop_link_run set status = p_status, version = p_version, planned_at = null, item_count = p_count where id = p_run;
$$;
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values (gen_random_uuid(), 'linkperf1-admin@test.invalid', 'linkperf1 admin', 'admin', '[]', true);
select auth_user_id::text as u_adm from public.ims_staff where email = 'linkperf1-admin@test.invalid' \gset

-- ── A 정의 ──
select pg_temp.chk('A1 shop_link_plan before this step (md5 · 시험 갈래 = link-1a 옛 판 · 확인 갈래 = 새 판)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), :'want_pre');

-- ── O 옛 정의로 plan(asung · test) → 스냅샷 → 되돌림 ──
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
select pg_temp.chk('O3 old result: version = before + 1 · items = count', (select (result->>'version') || ' ' || (result->>'items') from t_out where phase = 'old' and run_id = :'run_a'::uuid), (:ver_a0 + 1)::text || ' ' || :'n_a');
select round((select ms from t_out where phase = 'old' and run_id = :'run_a'::uuid))::text as old_ms_a \gset
\echo '── 옛 정의 plan(asung' :n_a ') 걸린 시간' :old_ms_a 'ms'
select pg_temp.rewind(:'run_a'::uuid, :'st_a0', :ver_a0, :cnt_a0); select pg_temp.rewind(:'run_t'::uuid, :'st_t0', :ver_t0, :cnt_t0);
select pg_temp.chk('O4 rewound: decisions null · version back', (select count(*)::text from public.shop_link_item where run_id = :'run_a'::uuid and decision is not null) || ' ' || (select version::text || ' ' || status from public.shop_link_run where id = :'run_a'::uuid), '0 ' || :ver_a0 || ' ' || :'st_a0');

\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── N 새 정의로 plan → 비교 ──
select pg_temp.chk('N1 shop_link_plan now = link-perf-1 (md5)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), '95272460ee63cbe3f6c62fae80c45d9e');
select pg_temp.chk('N2 index product_sku_lower_idx (lower(sku), sku)', (select indexdef from pg_indexes where indexname = 'product_sku_lower_idx'), 'CREATE INDEX product_sku_lower_idx ON public.product USING btree (lower(sku), sku)');
select pg_temp.chk('N3 definer · search_path · grants unchanged (authenticated · service_role yes · anon no)', (select prosecdef::text || ' ' || array_to_string(proconfig, ',') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan') || ' ' || has_function_privilege('authenticated', 'public.shop_link_plan(uuid)', 'execute')::text || has_function_privilege('service_role', 'public.shop_link_plan(uuid)', 'execute')::text || has_function_privilege('anon', 'public.shop_link_plan(uuid)', 'execute')::text, 'true search_path=public, pg_temp truetruefalse');
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select clock_timestamp() as t3 \gset
select pg_temp.run('select set_config(''app.out'', (public.shop_link_plan(''' || :'run_a' || ''') - ''planned_at'')::text, true)') as r_na \gset
select clock_timestamp() as t4 \gset
select pg_temp.run('select set_config(''app.out2'', (public.shop_link_plan(''' || :'run_t' || ''') - ''planned_at'')::text, true)') as r_nt \gset
select clock_timestamp() as t5 \gset
reset role;
select pg_temp.chk('N4 new plan ran on both runs', case when :'r_na' like 'ERR%' then :'r_na' when :'r_nt' like 'ERR%' then :'r_nt' else 'ok' end, 'ok');
insert into t_out values ('new', :'run_a'::uuid, current_setting('app.out', true)::jsonb, extract(epoch from (:'t4'::timestamptz - :'t3'::timestamptz)) * 1000),
                         ('new', :'run_t'::uuid, current_setting('app.out2', true)::jsonb, extract(epoch from (:'t5'::timestamptz - :'t4'::timestamptz)) * 1000);
select pg_temp.snap('new', :'run_a'::uuid); select pg_temp.snap('new', :'run_t'::uuid);
select round((select ms from t_out where phase = 'new' and run_id = :'run_a'::uuid))::text as new_ms_a, round((select ms from t_out where phase = 'new' and run_id = :'run_t'::uuid))::text as new_ms_t \gset
\echo '── 새 정의 plan(asung' :n_a ') 걸린 시간' :new_ms_a 'ms · test(' :n_t ')' :new_ms_t 'ms'
select pg_temp.chk('C1 asung: items with any difference (decision · reasons · family · product · changes) = 0',
  (select count(*)::text from t_snap o full join t_snap n on n.item_id = o.item_id and n.phase = 'new' and o.phase = 'old'
    where (o.phase = 'old' or o.phase is null) and (n.phase = 'new' or n.phase is null) and coalesce(o.run_id, n.run_id) = :'run_a'::uuid
      and (o.item_id is null or n.item_id is null or o.decision is distinct from n.decision or o.reasons is distinct from n.reasons or o.ims_family_id is distinct from n.ims_family_id or o.ims_product_id is distinct from n.ims_product_id or o.changes is distinct from n.changes)), '0');
select pg_temp.chk('C2 asung: new snapshot rows = items', (select count(*)::text from t_snap where phase = 'new' and run_id = :'run_a'::uuid), :'n_a');
select pg_temp.chk('C3 asung: returned JSON identical (run_id · store_code · version · items · counts · reasons)', (select (o.result = n.result)::text || ' v' || (n.result->>'version') from t_out o join t_out n on n.run_id = o.run_id and n.phase = 'new' where o.phase = 'old' and o.run_id = :'run_a'::uuid), 'true v' || (:ver_a0 + 1)::text);
select pg_temp.chk('C4 asung: run row after new plan — planned · version +1 · item_count', (select status || ' ' || version::text || ' ' || item_count::text from public.shop_link_run where id = :'run_a'::uuid), 'planned ' || (:ver_a0 + 1)::text || ' ' || :'n_a');
select pg_temp.chk('C5 test run: items with any difference = 0',
  (select count(*)::text from t_snap o full join t_snap n on n.item_id = o.item_id and n.phase = 'new' and o.phase = 'old'
    where (o.phase = 'old' or o.phase is null) and (n.phase = 'new' or n.phase is null) and coalesce(o.run_id, n.run_id) = :'run_t'::uuid
      and (o.item_id is null or n.item_id is null or o.decision is distinct from n.decision or o.reasons is distinct from n.reasons or o.ims_family_id is distinct from n.ims_family_id or o.ims_product_id is distinct from n.ims_product_id or o.changes is distinct from n.changes)), '0');
select pg_temp.chk('C6 test run: returned JSON identical', (select (o.result = n.result)::text from t_out o join t_out n on n.run_id = o.run_id and n.phase = 'new' where o.phase = 'old' and o.run_id = :'run_t'::uuid), 'true');
select pg_temp.chk('C7 asung: decisions cover every item (none null) · counts in JSON add up to items', (select count(*) filter (where decision is null) from t_snap where phase = 'new' and run_id = :'run_a'::uuid)::text || ' ' || (select (select sum(v::int) from jsonb_each_text(result->'counts') x(k, v))::text from t_out where phase = 'new' and run_id = :'run_a'::uuid), '0 ' || :'n_a');
select pg_temp.chk('C8 asung: dup_sku reason count = items touching a SKU seen twice (store-wide rule intact)',
  (select count(*)::text from t_snap s where s.phase = 'new' and s.run_id = :'run_a'::uuid and 'dup_sku' = any(s.reasons)),
  (select count(distinct i.id)::text from public.shop_link_item i cross join lateral jsonb_array_elements(i.variants) v
    where i.run_id = :'run_a'::uuid and nullif(trim(v->>'sku'), '') in (select nullif(trim(w->>'sku'), '') from public.shop_link_item j cross join lateral jsonb_array_elements(j.variants) w where j.run_id = :'run_a'::uuid group by 1 having count(*) > 1)));
-- 두 번째 plan(멱등 · version +1 만)
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select clock_timestamp() as t6 \gset
select pg_temp.run('select set_config(''app.out'', (public.shop_link_plan(''' || :'run_a' || ''') - ''planned_at'')::text, true)') as r_n2 \gset
select clock_timestamp() as t7 \gset
reset role;
select pg_temp.snap('new2', :'run_a'::uuid);
insert into t_out values ('new2', :'run_a'::uuid, current_setting('app.out', true)::jsonb, extract(epoch from (:'t7'::timestamptz - :'t6'::timestamptz)) * 1000);
select pg_temp.chk('C9 asung: second new plan (planned → planned) same decisions · version +2', case when :'r_n2' like 'ERR%' then :'r_n2' else
  (select count(*)::text from t_snap a join t_snap b on b.item_id = a.item_id and b.phase = 'new2' where a.phase = 'new' and a.run_id = :'run_a'::uuid
     and (a.decision is distinct from b.decision or a.reasons is distinct from b.reasons or a.ims_family_id is distinct from b.ims_family_id or a.ims_product_id is distinct from b.ims_product_id or a.changes is distinct from b.changes)) || ' v' || (select result->>'version' from t_out where phase = 'new2') end, '0 v' || (:ver_a0 + 2)::text);

-- ── T 시간 ──
select pg_temp.chk('T1 new plan asung < 8000 ms (authenticated statement_timeout)', (:new_ms_a::numeric < 8000)::text || ' (' || :new_ms_a || ' ms)', 'true (' || :new_ms_a || ' ms)');
select pg_temp.chk('T2 new plan asung < 3000 ms (목표 · 8 s 의 여유)', (:new_ms_a::numeric < 3000)::text || ' (' || :new_ms_a || ' ms)', 'true (' || :new_ms_a || ' ms)');
select pg_temp.chk('T3 second new plan asung < 3000 ms', ((select ms from t_out where phase = 'new2') < 3000)::text, 'true');
select pg_temp.chk('T4 new plan test run < 1000 ms', (:new_ms_t::numeric < 1000)::text || ' (' || :new_ms_t || ' ms)', 'true (' || :new_ms_t || ' ms)');

-- ── S safeupdate 정적 셈 · 몸 ──
select pg_temp.chk('S1 shop_link_plan: no-WHERE update · delete = 0', pg_temp.nowhere((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'))::text, '0');
select pg_temp.chk('S2 body uses t_link_var · t_link_dup · t_link_res · one update … from', (select ((prosrc ~ 't_link_var') and (prosrc ~ 't_link_dup') and (prosrc ~ 't_link_res') and (prosrc ~ 'update public\.shop_link_item i set') and (prosrc !~ 't_link_sku'))::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), 'true');
select pg_temp.chk('S3 shop_link_apply untouched (link-1a md5)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply'), 'd9af643812f372b04b3b50beececb0a6');
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values (gen_random_uuid(), 'linkperf1-worker@test.invalid', 'linkperf1 worker', 'worker', '[]', true);
select auth_user_id::text as u_wrk from public.ims_staff where email = 'linkperf1-worker@test.invalid' \gset
select set_config('request.jwt.claims', json_build_object('sub', :'u_wrk', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run('select public.shop_link_plan(''' || :'run_a' || ''')::text') as r_p1 \gset
reset role;
select pg_temp.chk('P1 worker without the shopify key cannot plan (ims_require_write · nothing saved)', case when :'r_p1' like 'ERR P0001:%' then 'refused' else left(:'r_p1', 80) end, 'refused');

-- ── 결과 ──
select clock_timestamp() as t_end \gset
select n, case when ok then 'OK  ' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok_n, count(*) filter (where not ok) as bad_n, count(*) as total from t_res \gset
\echo '── OK' :ok_n '/ ' :total '(expect' :EXPECT_OK ') · MISMATCH' :bad_n '· 옛 plan' :old_ms_a 'ms → 새 plan' :new_ms_a 'ms(asung' :n_a ') · test' :new_ms_t 'ms · begin~end' :t_begin '→' :t_end
rollback;
select r.status as st_a1, r.version as ver_a1, coalesce(r.planned_at::text, 'null') as pl_a1 from public.shop_link_run r where r.id = :'run_a'::uuid \gset
select (select count(*) from public.shop_link_item where run_id = :'run_a'::uuid and decision is not null) as dec_a1, (select count(*) from public.ims_staff) as n_staff1, (select count(*) from pg_indexes where indexname = 'product_sku_lower_idx') as idx1 \gset
\echo '── rollback 뒤 실제: asung run' :st_a1 '· v' :ver_a1 '· planned_at' :pl_a1 '· decided items' :dec_a1 '(전 0 기대 · 확인 갈래는 화면이 이미 plan 했으면 다름) · staff' :n_staff0 '→' :n_staff1 '· index present' :idx1
