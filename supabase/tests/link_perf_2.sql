-- supabase/tests/link_perf_2.sql — link-perf-2 검증: shop_link_apply 를 묶음(p_limit)으로 — 한 번에 전부와 묶음으로 끝까지가 같은 결과 · 이어서 · 계획 다시 하면 막힘 · 묶음 3 s 안 (2026-10-27 · 판정 829 · 815)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — begin → (가) 옛 정의로 한 번에 apply(asung · test) → 스냅샷 md5 를 psql 변수로 → rollback to savepoint → (-v mig 면 \i) → (나) 새 정의로 묶음 끝까지 → md5 같음 · 이어서 · version → (다) 새 정의 한 번에 → md5 같음 → rollback → 실제 run 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027205600_link_perf_2.sql -f supabase/tests/link_perf_2.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — (가) 자리가 이미 새 정의라 A1 의 기대 md5 만 다르고 OK 수는 같다
--   ⚠️ 잠금: (가) 옛 apply 가 asung run 행(for update)을 약 73 s 쥔다 + 새 정의 두 번(묶음 · 한 번에) — 트랜잭션 한 번에 약 2 분 반 · 그 사이 화면의 Plan · Apply(그 run)는 기다린다(8 s 시한에 걸린다) · 확인 갈래는 약 1 분
--   ⚠️ 임시 표의 행도 rollback to savepoint 에 되돌아간다 — 검사 값은 savepoint 안에서 \gset 으로 받고 chk(t_res) 는 되돌린 뒤에 적는다(1회차 실측: chk 39 중 12 만 남았다)
--   ⚠️ REST(authenticated 8 s · safeupdate)는 psql 직결로 못 싣는다 — 여기서는 묶음 시간(< 3 s)과 정적 WHERE 셈까지 · 실제 REST 한 번은 Caleb(화면 차수)
--   쓰기: 가짜 직원 2 · asung 스토어의 shop_listing · shop_product · shop_variant(0 행에서 시작) · item applied_at · run — 전부 rollback · 시퀀스 0 · Shopify 호출 0
\set ON_ERROR_STOP on
\set EXPECT_OK 40
\pset pager off
\if :{?mig}
\set want_pre d9af643812f372b04b3b50beececb0a6
\else
\set want_pre 8adbc8dbdd465a3f26a81b8135785ad1
\endif
select value as db_role from public.inv_config where key = 'db_role' \gset
select r.id::text as run_a, r.version as ver_a, s.id::text as store_a from public.shop_link_run r join public.shop_store s on s.id = r.store_id where s.code = 'asung' and r.status = 'planned' order by r.started_at desc limit 1 \gset
select r.id::text as run_t, r.version as ver_t, s.id::text as store_t from public.shop_link_run r join public.shop_store s on s.id = r.store_id where s.code = 'test' and r.status = 'planned' order by r.started_at desc limit 1 \gset
select (select count(*) from public.shop_link_item where run_id = :'run_a'::uuid and decision in ('link', 'link_off')) as todo_a,
       (select count(*) from public.shop_link_item where run_id = :'run_a'::uuid and decision = 'link') as link_a,
       (select count(*) from public.shop_link_item where run_id = :'run_a'::uuid and decision not in ('link', 'link_off')) as skip_a,
       (select count(distinct coalesce(ims_family_id, ims_product_id)) from public.shop_link_item where run_id = :'run_a'::uuid and decision in ('link', 'link_off')) as tgt_a,
       (select count(*) from public.shop_link_item where run_id = :'run_t'::uuid and decision in ('link', 'link_off')) as todo_t,
       (select count(*) from public.shop_product where store_id = :'store_a'::uuid) as sp_a0,
       (select count(*) from public.ims_staff) as n_staff0 \gset
select md5(string_agg(handle || '|' || shopify_product_gid, ',' order by handle, shopify_product_gid)) as want_r4 from (select i.handle, i.shopify_product_gid from public.shop_link_item i where i.run_id = :'run_a'::uuid and i.decision in ('link', 'link_off') order by i.handle, i.shopify_product_gid offset 200 limit 100) x \gset
\echo '── 기준: db_role' :db_role '· asung run' :run_a '(v' :ver_a '· link+off' :todo_a '· 대상' :tgt_a '· skip' :skip_a '· shop_product 전' :sp_a0 ') · test run' :run_t '(v' :ver_t '· link+off' :todo_t ') · staff' :n_staff0
begin;
set local lock_timeout = '3s';
set local statement_timeout = '300s';
set local client_min_messages = warning;
select clock_timestamp() as t_begin \gset
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create temp table t_batches (n serial, run_id uuid, ms numeric, result jsonb);
grant insert on t_batches to authenticated; grant usage on sequence t_batches_n_seq to authenticated;
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
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; c text; n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach c in array string_to_array(v, ';') loop
    if c ~* '^\s*(update|delete)\M' and c !~* '\mwhere\M' then n := n + 1; end if;
  end loop;
  return n;
end $$;
-- 스냅샷 md5: shop_product · shop_variant · shop_listing(시각 · id 빼고 자연 열쇠로 정렬) · 줄 applied(수) · run — 묶음마다 now() 가 달라 시각은 「있다/없다」만
create function pg_temp.snap(p_store uuid, p_run uuid) returns text language plpgsql as $$
declare v_sp text; v_sv text; v_sl text; v_it text; v_run text;
begin
  select coalesce(md5(string_agg(k, E'\n' order by k)), '(none)') || ' ' || count(*) into v_sp from (
    select coalesce(family_id::text, '-') || '|' || coalesce(product_id::text, '-') || '|' || shopify_product_gid || '|' || coalesce(handle, '') || '|' || coalesce(shopify_status, '') || '|' || coalesce(last_status, '') || '|' || coalesce(last_error, '') || '|' || coalesce(last_pushed_at::text, '') || '|' || coalesce(last_hash, '') || '|' || coalesce(updated_by::text, '') as k
      from public.shop_product where store_id = p_store) x;
  select coalesce(md5(string_agg(k, E'\n' order by k)), '(none)') || ' ' || count(*) into v_sv from (
    select product_id::text || '|' || shopify_variant_gid || '|' || coalesce(inventory_item_gid, '') || '|' || coalesce(last_hash, '') || '|' || coalesce(updated_by::text, '') as k
      from public.shop_variant where store_id = p_store) x;
  select coalesce(md5(string_agg(k, E'\n' order by k)), '(none)') || ' ' || count(*) into v_sl from (
    select coalesce(family_id::text, '-') || '|' || coalesce(product_id::text, '-') || '|' || is_on::text || '|' || (turned_on_at is not null)::text || '|' || coalesce(turned_on_by::text, '') || '|' || (turned_off_at is not null)::text || '|' || coalesce(turned_off_by::text, '') || '|' || coalesce(note, '') || '|' || coalesce(updated_by::text, '') as k
      from public.shop_listing where store_id = p_store) x;
  select count(*) filter (where applied_at is not null and decision in ('link', 'link_off'))::text || '/' || count(*) filter (where applied_at is null and decision in ('link', 'link_off'))::text || '/' || count(*) filter (where applied_at is not null and decision not in ('link', 'link_off'))::text
    into v_it from public.shop_link_item where run_id = p_run;
  select status || ' v' || version::text || ' ' || (applied_at is not null)::text || ' ' || coalesce(applied_by::text, '') into v_run from public.shop_link_run where id = p_run;
  return 'sp ' || v_sp || ' · sv ' || v_sv || ' · sl ' || v_sl || ' · items ' || v_it || ' · run ' || v_run;
end $$;
-- 묶음으로 끝까지: done 이 참이 될 때까지 되풀이 · 호출마다 시간 · 결과를 t_batches 에
create function pg_temp.batch_all(p_run uuid, p_ver int, p_limit int, p_max_calls int default 100) returns text language plpgsql as $$
declare v jsonb; t0 timestamptz; n int := 0; v_max numeric := 0; v_sum numeric := 0; v_ms numeric;
begin
  loop
    n := n + 1;
    t0 := clock_timestamp();
    v := public.shop_link_apply(p_run, true, p_ver, p_limit);
    v_ms := extract(epoch from (clock_timestamp() - t0)) * 1000;
    insert into t_batches (run_id, ms, result) values (p_run, v_ms, v - 'items');
    v_max := greatest(v_max, v_ms); v_sum := v_sum + v_ms;
    exit when (v->>'done')::boolean or n >= p_max_calls;
  end loop;
  return jsonb_build_object('calls', n, 'max_ms', round(v_max), 'sum_ms', round(v_sum), 'last', v - 'items')::text;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
grant execute on function pg_temp.snap(uuid, uuid), pg_temp.batch_all(uuid, int, int, int), pg_temp.run(text), pg_temp.j(text) to authenticated;
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values (gen_random_uuid(), 'linkperf2-admin@test.invalid', 'linkperf2 admin', 'admin', '[]', true);
select auth_user_id::text as u_adm from public.ims_staff where email = 'linkperf2-admin@test.invalid' \gset

-- ── A 정의 ──
select pg_temp.chk('A1 shop_link_apply before this step (md5 · 시험 갈래 = link-1a 옛 판 · 확인 갈래 = 새 판)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply'), :'want_pre');

-- ── G (가) 한 번에 전부(옛 정의 · 확인 갈래는 새 정의) — asung → 값 → 되돌림 → chk · test 도 ──
savepoint s_ga;
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select clock_timestamp() as t0 \gset
select pg_temp.run('select (public.shop_link_apply(''' || :'run_a' || ''', true, ' || :ver_a || ') - ''items'')::text') as r_ga \gset
select clock_timestamp() as t1 \gset
reset role;
select round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000)::text as ga_ms \gset
select pg_temp.snap(:'store_a'::uuid, :'run_a'::uuid) as snap_ga \gset
select (select status || ' ' || (applied_at is not null)::text from public.shop_link_run where id = :'run_a'::uuid) || ' ' || (select count(*)::text from public.shop_link_item where run_id = :'run_a'::uuid and decision in ('link', 'link_off') and applied_at is null) || ' ' || (select count(*)::text from public.shop_product where store_id = :'store_a'::uuid) as g2 \gset
select (select count(*)::text from public.shop_stock_queue where store_id = :'store_a'::uuid and done_at is null) || ' ' || (select count(*)::text from public.shop_push_queue where store_id = :'store_a'::uuid and done_at is null) as g4 \gset
rollback to savepoint s_ga;
\echo '── (가) 한 번에 전부(asung' :todo_a ')' :ga_ms 'ms ·' :snap_ga
select pg_temp.chk('G1 (가) one-shot apply on asung ran', case when :'r_ga' like 'ERR%' then :'r_ga' else 'ok' end, 'ok');
select pg_temp.chk('G2 (가) run applied · every link/off item applied · targets = shop_product rows', :'g2', 'applied true 0 ' || :tgt_a);
select pg_temp.chk('G3 (가) result: linked + linked_off = todo · skipped · hash_seeded ≥ targets', (select ((r->>'linked')::int + (r->>'linked_off')::int)::text || ' ' || (r->>'skipped') || ' ' || ((r->>'hash_seeded')::int >= :tgt_a)::text from pg_temp.j(:'r_ga') r), :todo_a || ' ' || :skip_a || ' true');
select pg_temp.chk('G4 (가) live-before store: stock queue 0 · push queue 0 (판정 815)', :'g4', '0 0');
select pg_temp.chk('G5 rewound: shop_product asung back · run planned', (select count(*)::text from public.shop_product where store_id = :'store_a'::uuid) || ' ' || (select status from public.shop_link_run where id = :'run_a'::uuid), :sp_a0 || ' planned');
savepoint s_gt;
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run('select (public.shop_link_apply(''' || :'run_t' || ''', true, ' || :ver_t || ') - ''items'')::text') as r_gt \gset
reset role;
select pg_temp.snap(:'store_t'::uuid, :'run_t'::uuid) as snap_gt \gset
rollback to savepoint s_gt;
select pg_temp.chk('G6 (가) one-shot apply on test run ran', case when :'r_gt' like 'ERR%' then :'r_gt' else 'ok' end, 'ok');

\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── N 새 정의 ──
select pg_temp.chk('N1 shop_link_apply now = link-perf-2 (md5)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply'), '8adbc8dbdd465a3f26a81b8135785ad1');
select pg_temp.chk('N2 one shop_link_apply · signature (run, commit, version, limit)', (select count(*)::text || ' ' || string_agg(pg_get_function_identity_arguments(oid), ';') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply'), '1 p_run_id uuid, p_commit boolean, p_run_version integer, p_limit integer');
select pg_temp.chk('N3 definer · search_path · grants (authenticated · service_role yes · anon no)', (select prosecdef::text || ' ' || array_to_string(proconfig, ',') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply') || ' ' || has_function_privilege('authenticated', 'public.shop_link_apply(uuid, boolean, int, int)', 'execute')::text || has_function_privilege('service_role', 'public.shop_link_apply(uuid, boolean, int, int)', 'execute')::text || has_function_privilege('anon', 'public.shop_link_apply(uuid, boolean, int, int)', 'execute')::text, 'true search_path=public, pg_temp truetruefalse');

select pg_temp.chk('N4 column shop_link_item.applied_version · backfilled for applied runs', (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'shop_link_item' and column_name = 'applied_version') || ' ' || (select count(*)::text from public.shop_link_item where applied_at is not null and applied_version is null), '1 0');

-- ── B (나) 묶음으로 끝까지(500) → md5 같음 ──
savepoint s_b;
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select clock_timestamp() as t2 \gset
select pg_temp.run('select (public.shop_link_apply(''' || :'run_a' || ''', false, ' || :ver_a || ', 500) - ''items'')::text') as r_pv \gset
select pg_temp.run('select jsonb_array_length(public.shop_link_apply(''' || :'run_a' || ''', false, ' || :ver_a || ')->''items'')::text') as r_pvn \gset
select clock_timestamp() as t3 \gset
select (select count(*)::text from public.shop_product where store_id = :'store_a'::uuid) || ' ' || (select count(*)::text from public.shop_link_item where run_id = :'run_a'::uuid and applied_at is not null) as b2 \gset
select pg_temp.batch_all(:'run_a'::uuid, :ver_a, 500) as r_b \gset
select clock_timestamp() as t4 \gset
select pg_temp.run('select public.shop_link_apply(''' || :'run_a' || ''', true, ' || :ver_a || ', 500)::text') as r_b2 \gset
reset role;
select round(extract(epoch from (:'t3'::timestamptz - :'t2'::timestamptz)) * 1000 / 2)::text as pv_ms, round(extract(epoch from (:'t4'::timestamptz - :'t3'::timestamptz)) * 1000)::text as b_ms \gset
select n, round(ms) as ms, result->>'linked' as linked, result->>'linked_off' as off, result->>'variants' as variants, result->>'hash_seeded' as hash, result->>'remaining' as remaining, result->>'done' as done from t_batches where run_id = :'run_a'::uuid order by n;
select coalesce((r->>'calls'), '0') as b_calls, coalesce((r->>'max_ms'), '0') as b_max, coalesce((r->>'sum_ms'), '0') as b_sum from pg_temp.j(:'r_b') r \gset
select coalesce((select (result->>'done') || ' ' || (result->>'remaining') from t_batches where run_id = :'run_a'::uuid order by n desc limit 1), '(none)') as b4 \gset
select coalesce((select (bool_and(ok) || ' ' || sum(k)::text) from (select (result->>'remaining')::int = lag((result->>'remaining')::int, 1, :todo_a) over (order by n) - (result->>'linked')::int - (result->>'linked_off')::int as ok, (result->>'linked')::int + (result->>'linked_off')::int as k from t_batches where run_id = :'run_a'::uuid) x), '(none)') as b6 \gset
select coalesce((select bool_and((result->>'total_linked')::int + (result->>'total_linked_off')::int = :todo_a and (result->>'version')::int = :ver_a and (result->>'limit')::int = 500)::text from t_batches where run_id = :'run_a'::uuid), '(none)') as b7 \gset
select pg_temp.snap(:'store_a'::uuid, :'run_a'::uuid) as snap_b \gset
select (select count(*)::text from public.shop_stock_queue where store_id = :'store_a'::uuid and done_at is null) || ' ' || (select count(*)::text from public.shop_push_queue where store_id = :'store_a'::uuid and done_at is null) as b9 \gset
rollback to savepoint s_b;
\echo '── (나) 묶음 500: 호출' :b_calls '· 최대' :b_max 'ms · 합' :b_sum 'ms · 미리 보기' :pv_ms 'ms'
\echo '── 화면이 부를 모양 · 미리 보기(처음 · items 뺌):' :r_pv
\echo '── 화면이 부를 모양 · 마지막 묶음(batch_all 의 last):' :r_b
\echo '── 화면이 부를 모양 · applied 뒤 한 번 더:' :r_b2
select pg_temp.chk('B1 preview (commit false · limit ignored): whole numbers · remaining = todo · done false · hash 0 · items = todo', (select ((r->>'linked')::int + (r->>'linked_off')::int)::text || ' ' || (r->>'remaining') || ' ' || (r->>'done') || ' ' || (r->>'hash_seeded') || ' ' || (r->>'limit') from pg_temp.j(:'r_pv') r) || ' ' || :'r_pvn', :todo_a || ' ' || :todo_a || ' false 0 500 ' || :todo_a);
select pg_temp.chk('B2 preview wrote nothing (shop_product asung · applied items)', :'b2', :sp_a0 || ' 0');
select pg_temp.chk('B3 (나) batched to the end ran', case when :'r_b' like 'ERR%' then :'r_b' else 'ok' end, 'ok');
select pg_temp.chk('B4 calls = ceil(todo / 500) · last done · remaining 0', :'b_calls' || ' ' || :'b4', ceil(:todo_a / 500.0)::int::text || ' true 0');
select pg_temp.chk('B5 every batch < 3000 ms (authenticated 8 s 의 여유)', (:b_max::numeric < 3000)::text || ' (max ' || :b_max || ' ms)', 'true (max ' || :b_max || ' ms)');
select pg_temp.chk('B6 remaining steps down by linked + linked_off each call · sums to todo', :'b6', 'true ' || :todo_a);
select pg_temp.chk('B7 every batch returned total_* · version · limit', :'b7', 'true');
select pg_temp.chk('B8 ⭐ (나) batched end state = (가) one-shot (shop_product · shop_variant · shop_listing · items · run md5)', :'snap_b', :'snap_ga');
select pg_temp.chk('B9 (나) live-before store: stock queue 0 · push queue 0', :'b9', '0 0');
select pg_temp.chk('B10 one more call after done → refused (run is applied)', case when :'r_b2' like 'ERR P0001:%applied%' then 'refused' else left(:'r_b2', 90) end, 'refused');

-- ── R 이어서 · 계획 다시 하면 막힘 ──
savepoint s_r;
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run('select (public.shop_link_apply(''' || :'run_a' || ''', true, ' || :ver_a || ', 100) - ''items'')::text') as r_r1 \gset
select (select status from public.shop_link_run where id = :'run_a'::uuid) as r1_st \gset
select pg_temp.run('select (public.shop_link_apply(''' || :'run_a' || ''', false, ' || :ver_a || ') - ''items'')::text') as r_r1p \gset
select pg_temp.run('select (public.shop_link_apply(''' || :'run_a' || ''', true, ' || :ver_a || ', 100) - ''items'')::text') as r_r2 \gset
select (select count(*)::text from public.shop_link_item where run_id = :'run_a'::uuid and applied_at is not null) || ' ' || (select count(*)::text from (select i.id, i.applied_at from public.shop_link_item i where i.run_id = :'run_a'::uuid and i.decision in ('link', 'link_off') order by i.handle, i.shopify_product_gid limit 200) x where x.applied_at is null) as r3 \gset
select pg_temp.run('select md5(string_agg(x->>''handle'' || ''|'' || (x->>''gid''), '','' order by x->>''handle'', x->>''gid'')) from jsonb_array_elements(public.shop_link_apply(''' || :'run_a' || ''', true, ' || :ver_a || ', 100)->''items'') x') as r_r3i \gset
select clock_timestamp() as t5 \gset
select pg_temp.run('select (public.shop_link_plan(''' || :'run_a' || ''') - ''planned_at'')::text') as r_plan \gset
select clock_timestamp() as t6 \gset
select pg_temp.run('select public.shop_link_apply(''' || :'run_a' || ''', true, ' || :ver_a || ', 100)::text') as r_r3 \gset
select pg_temp.run('select (public.shop_link_apply(''' || :'run_a' || ''', false, ' || (:ver_a + 1) || ') - ''items'')::text') as r_r4p \gset
select pg_temp.run('select (public.shop_link_apply(''' || :'run_a' || ''', true, ' || (:ver_a + 1) || ', 100) - ''items'')::text') as r_r4 \gset
select (select count(*)::text from public.shop_link_item i join public.shop_link_run r on r.id = i.run_id where i.run_id = :'run_a'::uuid and i.applied_version = r.version) || ' ' || (select count(*)::text from public.shop_link_item i where i.run_id = :'run_a'::uuid and i.applied_version = :ver_a) as r7 \gset
reset role;
rollback to savepoint s_r;
select round(extract(epoch from (:'t6'::timestamptz - :'t5'::timestamptz)) * 1000)::text as plan_ms \gset
select pg_temp.chk('R1 first batch of 100: remaining = todo - 100 · done false · run still planned', (select (r->>'remaining') || ' ' || (r->>'done') from pg_temp.j(:'r_r1') r) || ' ' || :'r1_st', (:todo_a - 100)::text || ' false planned');
select pg_temp.chk('R2 preview in the middle shows remaining = todo - 100 · linked still whole (이어서 할 수 있다)', (select (r->>'remaining') || ' ' || (r->>'linked') from pg_temp.j(:'r_r1p') r), (:todo_a - 100)::text || ' ' || :link_a);
select pg_temp.chk('R3 second call continues: remaining = todo - 200 · applied items 200 · = first 200 in (handle, gid) order', (select (r->>'remaining') from pg_temp.j(:'r_r2') r) || ' ' || :'r3', (:todo_a - 200)::text || ' 200 0');
select pg_temp.chk('R4 third batch items = rows 201 ~ 300 in (handle, gid) order', :'r_r3i', :'want_r4');
select pg_temp.chk('R5 plan again (planned → planned · partly applied) · version +1', case when :'r_plan' like 'ERR%' then :'r_plan' else (select r->>'version' from pg_temp.j(:'r_plan') r) end, (:ver_a + 1)::text);
select pg_temp.chk('R6 continuing with the old version is refused (막기 문장)', case when :'r_r3' like 'ERR P0001: The plan you looked at is version ' || :ver_a || ' but the run is now version ' || (:ver_a + 1) || '%' then 'refused' else left(:'r_r3', 120) end, 'refused');
select pg_temp.chk('R7 new version starts over: preview remaining = todo (옛 applied_version ≠ 새 version) · first batch → todo - 100 · applied under new version 100 · under old version 200 (앞 100 줄은 새 판이 덮었다)', (select r->>'remaining' from pg_temp.j(:'r_r4p') r) || ' ' || (select r->>'remaining' from pg_temp.j(:'r_r4') r) || ' ' || :'r7', :todo_a || ' ' || (:todo_a - 100)::text || ' 100 200');
\echo '── (보고) 일부 적용(300) 뒤 plan 다시' :plan_ms 'ms — plan 의 ⑤ 길(스토어에 이어진 것이 있을 때) · link-perf-1 범위 밖 · 이 차수는 재기만'
\echo '── 화면이 부를 모양 · 첫 묶음(100 · items 뺌):' :r_r1
\echo '── 화면이 부를 모양 · 미리 보기(중간 · items 뺌):' :r_r1p
\echo '── 화면이 부를 모양 · 버전 어긋남:' :r_r3
\echo '── 화면이 부를 모양 · 새 version 첫 묶음:' :r_r4

-- ── F (다) 새 정의 한 번에 전부(p_limit 없음 · 옛 화면 호환) → md5 같음 ──
savepoint s_f;
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select clock_timestamp() as t7 \gset
select pg_temp.run('select (public.shop_link_apply(''' || :'run_a' || ''', true, ' || :ver_a || ') - ''items'')::text') as r_f \gset
select clock_timestamp() as t8 \gset
reset role;
select pg_temp.snap(:'store_a'::uuid, :'run_a'::uuid) as snap_f \gset
rollback to savepoint s_f;
select round(extract(epoch from (:'t8'::timestamptz - :'t7'::timestamptz)) * 1000)::text as f_ms \gset
\echo '── (다) 새 정의 한 번에 전부(asung)' :f_ms 'ms'
select pg_temp.chk('F1 (다) new one-shot ran · done · remaining 0 · linked + off = todo · limit null', case when :'r_f' like 'ERR%' then :'r_f' else (select (r->>'done') || ' ' || (r->>'remaining') || ' ' || ((r->>'linked')::int + (r->>'linked_off')::int)::text || ' ' || coalesce(r->>'limit', 'null') from pg_temp.j(:'r_f') r) end, 'true 0 ' || :todo_a || ' null');
select pg_temp.chk('F2 ⭐ (다) one-shot end state = (가)', :'snap_f', :'snap_ga');

-- ── T test 스토어 run(작음 · 이미 이어진 것 · live) — 묶음 2 로 끝까지 = (가) ──
savepoint s_t;
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.batch_all(:'run_t'::uuid, :ver_t, 2) as r_bt \gset
reset role;
select pg_temp.snap(:'store_t'::uuid, :'run_t'::uuid) as snap_bt \gset
select (select count(*)::text from public.shop_push_queue where store_id = :'store_t'::uuid and done_at is null) as t3 \gset
rollback to savepoint s_t;
select pg_temp.chk('T1 test run batched (2) ran · calls = ceil(todo / 2)', case when :'r_bt' like 'ERR%' then :'r_bt' else (select r->>'calls' from pg_temp.j(:'r_bt') r) end, ceil(:todo_t / 2.0)::int::text);
select pg_temp.chk('T2 ⭐ test run: batched end state = (가) (last_pushed_at kept on same gid)', :'snap_bt', :'snap_gt');
select pg_temp.chk('T3 test run: push queue 0 (linking must not send)', :'t3', '0');

-- ── S 정적 · 몸 ──
select pg_temp.chk('S1 shop_link_apply: no-WHERE update · delete = 0', pg_temp.nowhere((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply'))::text, '0');
select pg_temp.chk('S2 body: t_link_todo · t_link_vv · dup · applied_version rule · for update · no "is not distinct from" · jsonb_agg once', (select ((prosrc ~ 't_link_todo') and (prosrc ~ 't_link_vv') and (prosrc ~ 'not t\.dup') and (prosrc ~ 'applied_version is distinct from v_run\.version') and (prosrc !~ 'planned_at') and (prosrc ~ 'for update') and (prosrc !~ 'is not distinct from') and (prosrc ~ 'jsonb_agg') and (prosrc !~ 'v_list := v_list \|\|'))::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply'), 'true');
select pg_temp.chk('S3 shop_link_plan untouched (link-perf-1 md5)', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_plan'), '95272460ee63cbe3f6c62fae80c45d9e');
select pg_temp.chk('S4 shop_link_push_batch · shop_link_remaining · shop_product_payload untouched', (select string_agg(md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_link_push_batch', 'shop_link_remaining', 'shop_product_payload')), (select string_agg(m, ' ' order by p) from (values ('shop_link_push_batch', '41c5f51a42d1f001bad1e5dc74033a72'), ('shop_link_remaining', 'adda6ab5cd124ddd31d418458bc4c652'), ('shop_product_payload', '7dc83d5510f4c800fd461dcc78419d1d')) v(p, m)));
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run('select public.shop_link_apply(''' || :'run_a' || ''', true, ' || :ver_a || ', 0)::text') as r_s5 \gset
reset role;
select pg_temp.chk('S5 p_limit 0 refused', :'r_s5', 'ERR P0001: p_limit must be null (everything) or 1 or more — nothing was saved');
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values (gen_random_uuid(), 'linkperf2-worker@test.invalid', 'linkperf2 worker', 'worker', '[]', true);
select auth_user_id::text as u_wrk from public.ims_staff where email = 'linkperf2-worker@test.invalid' \gset
select set_config('request.jwt.claims', json_build_object('sub', :'u_wrk', 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.run('select public.shop_link_apply(''' || :'run_a' || ''', true, ' || :ver_a || ', 100)::text') as r_p1 \gset
reset role;
select pg_temp.chk('P1 worker without the shopify key cannot apply (ims_require_write · nothing saved)', case when :'r_p1' like 'ERR P0001:%' then 'refused' else left(:'r_p1', 80) end, 'refused');
select pg_temp.chk('P2 nothing applied by the refused calls', (select count(*)::text from public.shop_link_item where run_id = :'run_a'::uuid and applied_at is not null) || ' ' || (select count(*)::text from public.shop_product where store_id = :'store_a'::uuid), '0 ' || :sp_a0);

-- ── 결과 ──
select clock_timestamp() as t_end \gset
select n, case when ok then 'OK  ' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok_n, count(*) filter (where not ok) as bad_n, count(*) as total from t_res \gset
\echo '── OK' :ok_n '/ ' :total '(expect' :EXPECT_OK ') · MISMATCH' :bad_n '· (가) 한 번에' :ga_ms 'ms → (나) 묶음 500 최대' :b_max 'ms × ' :b_calls '회 (합' :b_sum ') · (다) 새 한 번에' :f_ms 'ms · begin~end' :t_begin '→' :t_end
rollback;
select r.status as st_a1, r.version as ver_a1, coalesce(r.applied_at::text, 'null') as ap_a1 from public.shop_link_run r where r.id = :'run_a'::uuid \gset
select (select count(*) from public.shop_link_item where run_id = :'run_a'::uuid and applied_at is not null) as ap_items1, (select count(*) from public.shop_product where store_id = :'store_a'::uuid) as sp_a1, (select count(*) from public.ims_staff) as n_staff1 \gset
\echo '── rollback 뒤 실제: asung run' :st_a1 '· v' :ver_a1 '· applied_at' :ap_a1 '· applied items' :ap_items1 '· shop_product asung' :sp_a0 '→' :sp_a1 '· staff' :n_staff0 '→' :n_staff1
