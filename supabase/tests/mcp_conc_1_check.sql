-- supabase/tests/mcp_conc_1_check.sql — mcp-conc-1 검증: mcp_sales 자리표(동시 3 · 다 차면 즉시 PT429 · 하나 놓으면 진행 · 후보 돌려주기 · 인자 틀림 · 다른 도구는 무관) · 시그니처 · 권한 · comment · REST 두 겹 ① · pg_sequences 무변 (2026-11-08 UTC · 지시서 ~/asung/prompts/mcp-conc-1.md)
-- [IMS 메인 · fazgmyvzzhqybtvtktyg] ⚠️ 혼자 돌리지 말고 supabase/tests/mcp_conc_1_run.sh 로 — 실행기가 자리 1 · 2 · 3 을 쥐는 psql 세션 셋(application_name mcp_conc_1_holder_k · pg_sleep)을 먼저 띄우고 이 파일을 넷째 세션으로 돈다
--   흐름: 기준(begin 앞 · pg_sequences 스냅샷) → 트랜잭션 하나(lock_timeout 2s · (-v mig 면 \i) → 가짜 admin → 자리 셋 찬 채로: 판매 집계 → PT429 즉시(ms 잼) · 후보 돌려주기 · 인자 틀림 · mcp_order → 자리 무관 → 자리 3 을 쥔 세션을 pg_terminate_backend → 판매 집계 한 번(실데이터 · 2026-10 · brand · 성공 길) → 우리 pid 의 권고 잠금 1 → rollback) → 검사는 트랜잭션 밖(잠금 0 · 행 무변 · 시퀀스 무변)
--   ⚠️ 운영 부하: 실데이터 집계는 성공 길 한 번뿐 · busy 호출은 집계 앞에서 끝난다(수십 ms) · 자리를 쥐는 동안 실제 커넥터는 영향 없음(시험 갈래 — 배포된 판엔 자리표가 없다 / 확인 갈래 — 적용 뒤 몇 초 동안 실제 호출이 busy 를 받을 수 있다 · 호출 0 인 때에)
\set ON_ERROR_STOP on
\set EXPECT_OK 16
-- 성공 길 한 번의 기간: 기본 실데이터 2026-10(무거운 집계 · 운영 부하 한 번) · -v light=1 이면 가짜 기간 2027-06(실자료 0 · 집계 파이프라인은 다 돌되 가볍다 — 되돌이 시험용 · S1 기대 rows 0)
\if :{?light}
\set s1_from 2027-06-01
\set s1_to 2027-06-30
\set s1_rows 0
\else
\set s1_from 2026-10-01
\set s1_to 2026-10-31
\set s1_rows 50
\endif
\pset pager off
select (select count(*) from public.hist_so) as n_hist, (select count(*) from public.hist_so_line) as n_hist_line, (select count(*) from public.product) as n_product, (select count(*) from public.customer) as n_cust,
       (select count(*) from public.ims_staff) as n_staff, (select claude_client_id from public.mcp_config where singleton) as cid0, (select count(*) from public.mcp_call_log) as n_log \gset
select md5(p.prosrc) as ms_pre_md5, pg_get_function_identity_arguments(p.oid) as ms_pre_sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales' \gset
create temp table t_seq_pre as select schemaname, sequencename, last_value from pg_sequences;   -- 앞뒤 diff(⚠️ 운영 메인 — 시험 중 실제 트래픽이 다른 시퀀스를 밀 수 있다 · 바뀐 이름을 찍는다)
\echo '── 기준: hist_so' :n_hist '· hist_so_line' :n_hist_line '· product' :n_product '· customer' :n_cust '· staff' :n_staff '· mcp_call_log' :n_log '· mcp_sales md5' :ms_pre_md5 '· sig' :ms_pre_sig
-- ── 도우미(세션 임시 스키마 — 트랜잭션 밖 · rollback 에 안 사라진다 · mcp_cap_1_check 와 같은 꼴) ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
declare v text; v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERR ' || sqlstate || ': ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return coalesce(v, '(null)');
end $$;
create function pg_temp.cl(p_uid text, p_cid text) returns jsonb language sql as $$ select jsonb_strip_nulls(jsonb_build_object('sub', p_uid, 'role', 'ims_connector', 'aud', 'authenticated', 'client_id', p_cid)) $$;
create function pg_temp.st(v text, p text) returns text language sql as $$ select case when v like p || '%' then p else left(v, 160) end $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop
      v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g');
      exit when v_chunk = v_prev;
    end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
create function pg_temp.setup_admin() returns text language plpgsql as $$
declare v_uid uuid := gen_random_uuid();
begin
  insert into public.ims_staff (id, auth_user_id, email, name, role, perms, is_active) values ('0c010000-0000-4000-8000-000000000001', v_uid, 'mcpconc1-a@test.invalid', 'MCPconc1 Fake Admin', 'admin', '["claude"]'::jsonb, true);
  update public.mcp_config set claude_client_id = 'mcp-test-client-conc1' where singleton;
  return v_uid::text;
end $$;
-- 판매 집계 한 번(ims_connector) — 인자 글은 그대로 함수 뒤에 붙는다 · 걸린 ms 와 결과(앞 160 자 · 또는 ERR 꼴)를 함께
create function pg_temp.sj(p_uid text, p_args text) returns text language sql as $$
  select pg_temp.as_conn('ims_connector', pg_temp.cl(p_uid, 'mcp-test-client-conc1'), format($q$select public.mcp_sales(%s)::text$q$, p_args))
$$;
create function pg_temp.timed(p_uid text, p_args text, out ms numeric, out res text) language plpgsql as $$
declare t timestamptz;
begin
  t := clock_timestamp();
  res := pg_temp.sj(p_uid, p_args);
  ms := round(extract(epoch from clock_timestamp() - t) * 1000);
end $$;
create function pg_temp.holders() returns text language sql as $$
  select coalesce(string_agg(application_name, ',' order by application_name), '(none)') from pg_stat_activity where application_name like 'mcp\_conc\_1\_holder\_%' and pid <> pg_backend_pid()
$$;
create function pg_temp.adv_locks(p_pid int) returns int language sql as $$ select count(*)::int from pg_locks where locktype = 'advisory' and pid = p_pid and granted $$;
-- 자리 열쇠 셋이 pg_locks 에 어떻게 보이나: pg_try_advisory_xact_lock(bigint) → classid = 위 32 비트 · objid = 아래 32 비트 · objsubid 1 (hashtext 는 int4 → bigint 부호 확장) — application_name 과 무관하게 잠금 자체로 센다
create function pg_temp.slot_locks(p_mine boolean) returns text language sql as $$
  select coalesce(string_agg(k.n::text, ',' order by k.n), '(none)')
    from (select n, hashtext('mcp_sales:slot:' || n)::bigint as key from generate_series(1, 3) n) k
    join pg_locks l on l.locktype = 'advisory' and l.granted and l.objsubid = 1
                   and l.classid = ((k.key >> 32) & 4294967295)::oid and l.objid = (k.key & 4294967295)::oid
   where (l.pid = pg_backend_pid()) = p_mine $$;

-- ── 자리 쥔 세션 셋이 보일 때까지(≤ 10 s) ──
do $$ declare i int := 0; begin loop exit when (select count(*) from pg_stat_activity where application_name like 'mcp\_conc\_1\_holder\_%') >= 3 or i >= 50; perform pg_sleep(0.2); i := i + 1; end loop; end $$;
select pg_temp.holders() as h0 \gset
select pg_temp.slot_locks(false) as h1 \gset
\echo '── 자리 쥔 세션:' :h0 '· 남이 쥔 자리(pg_locks 열쇠로)' :h1

-- ── 본 트랜잭션(≤ 15 s) ──
begin;
set local lock_timeout = '2s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
select (select count(*)::text || ' | ' || string_agg(pg_get_function_identity_arguments(p.oid), ' ; ') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') as r1,
       (select p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') || ' ' ||
         (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mcp\_%' and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'))::text as r2,
       (select p.prosecdef::text || p.provolatile::text || coalesce(p.proconfig::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') as r3,
       (select pg_temp.nowhere(p.prosrc)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') as r4,
       (select left(coalesce(obj_description(p.oid, 'pg_proc'), '(none)'), 60) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') as r5,
       (select (count(*) filter (where p.proname = 'mcp_sales'))::text || '/' || (count(*) filter (where p.proname <> 'mcp_sales'))::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%mcp_sales:slot:%') as r6,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') as new_md5 \gset
select pg_temp.setup_admin() as a_uid \gset
-- 자리 셋 찬 채로 ①: 실기간 · brand — PT429 가 집계 앞에서 즉시
select ms as b1_ms, res as b1 from pg_temp.timed(:'a_uid', $a$'2026-10-01', '2026-10-31', 'brand'$a$) \gset
-- 후보 돌려주기(브랜드 못 풂) · 인자 틀림 · 다른 도구 — 자리와 무관
select pg_temp.st(pg_temp.sj(:'a_uid', $a$'2026-10-01', '2026-10-31', 'brand', 'zzzz-no-such-brand-conc1'$a$), '{"field": "brand", "query": "zzzz-no-such-brand-conc1", "matches": 0') as b2,
       pg_temp.st(pg_temp.sj(:'a_uid', $a$'2026-10-01', '2026-10-31', 'week'$a$), 'ERR P0001: group must be one of brand, customer, month, sku, supplier — nothing was read') as b3,
       left(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', 'mcp-test-client-conc1'), $q$select public.mcp_order('SO-00000')::text$q$), 9) as b4 \gset
-- 자리 3 을 쥔 세션을 끊는다 → ②: 넷째(우리)가 진행 — 성공 길 한 번(실데이터 · 2026-10 · brand · limit 50)
select count(*) as k3 from (select pg_terminate_backend(pid) from pg_stat_activity where application_name = 'mcp_conc_1_holder_3') x \gset
select pg_sleep(0.5);
-- 남이 쥔 자리(잠금 자체로 — 끊긴 세션은 pg_stat_activity 에 잠깐 더 보인다 · 11-08 실측) · ⚠️ \gset 줄 뒤에 주석을 두면 인자로 읽힌다
select pg_temp.slot_locks(false) as h2 \gset
select ms as s1_ms, res as s1 from pg_temp.timed(:'a_uid', format($a$'%s', '%s', 'brand', null, null, null, null, 50, 0$a$, :'s1_from', :'s1_to')) \gset
select pg_temp.adv_locks(pg_backend_pid())::text || ' | ' || pg_temp.slot_locks(true) || ' | ' || pg_temp.slot_locks(false) as l1 \gset
select clock_timestamp() - :'t_begin'::timestamptz as tx_begin_to_rollback;
rollback;
select pg_temp.adv_locks(pg_backend_pid())::text || ' | ' || pg_temp.slot_locks(true) as l2 \gset

-- ── 검사(트랜잭션 밖 · 모은 변수로) ──
select pg_temp.chk('H0 자리 쥔 세션 셋(holder_1 · 2 · 3) · 남이 쥔 자리 1,2,3', :'h0' || ' | ' || :'h1', 'mcp_conc_1_holder_1,mcp_conc_1_holder_2,mcp_conc_1_holder_3 | 1,2,3');
select pg_temp.chk('R1 mcp_sales 한 벌 · 시그니처 그대로', :'r1', '1 | p_from text, p_to text, p_group text, p_brand text, p_customer text, p_sku text, p_supplier text, p_limit integer, p_offset integer');
select pg_temp.chk('R2 권한: ims_connector 만 · mcp_* 에 PUBLIC EXECUTE 0', :'r2', '{postgres=X/postgres,ims_connector=X/postgres} 0');
select pg_temp.chk('R3 definer · stable · search_path + work_mem 그대로', :'r3', 'trues{"search_path=public, pg_temp",work_mem=32MB}');
select pg_temp.chk('R4 REST 두 겹 ①: mcp_sales 의 깊이 0 WHERE 없는 update · delete 0', :'r4', '0');
select pg_temp.chk('R5 comment 그대로(mcp-1b 도구 ⑥ … 으로 시작)', left(:'r5', 11), 'mcp-1b 도구 ⑥');
select pg_temp.chk('R6 자리표 열쇠(mcp_sales:slot:)는 mcp_sales 본문에만 — 다른 함수 0(화면 함수에 안 걸린다)', :'r6', '1/0');
select pg_temp.chk('B1 자리 셋 찬 채 판매 집계 → PT429 · 글에 busy · nothing was read', pg_temp.st(:'b1', 'ERR PT429: IMS is busy: 3 sales summaries are already running across all staff — try again in a few seconds, one at a time — nothing was read'), 'ERR PT429: IMS is busy: 3 sales summaries are already running across all staff — try again in a few seconds, one at a time — nothing was read');
select pg_temp.chk('B1t 즉시(' || :'b1_ms' || ' ms < 500 · 무거운 집계 안 돎)', (:b1_ms < 500)::text, 'true');
select pg_temp.chk('B2 자리 찬 채 브랜드 못 풂 → 후보 돌려주기(자리 안 씀 · busy 아님)', :'b2', '{"field": "brand", "query": "zzzz-no-such-brand-conc1", "matches": 0');
select pg_temp.chk('B3 자리 찬 채 인자 틀림 → 한 문장(자리 앞에서 · busy 아님)', :'b3', 'ERR P0001: group must be one of brand, customer, month, sku, supplier — nothing was read');
select pg_temp.chk('B4 자리 찬 채 다른 도구 mcp_order → 자리 무관(ERR 아님)', (:'b4' not like 'ERR %')::text || ' ' || left(:'b4', 9), 'true {"found":');
select pg_temp.chk('S0 자리 3 세션 끊음 1 · 남이 쥔 자리 1,2 만', :'k3' || ' | ' || :'h2', '1 | 1,2');
select pg_temp.chk('S1 하나 놓으면 넷째가 진행 — brand ' || :'s1_from' || ' ~ ' || :'s1_to' || ' ok(' || :'s1_ms' || ' ms < 8000) · 우리 pid 권고 잠금 1 = 자리 3 · 남은 자리 1,2 는 남이', (:'s1' not like 'ERR %' and :s1_ms < 8000)::text || ' | ' || case when :'s1' like 'ERR %' then left(:'s1', 40) else (:'s1'::jsonb->'page'->>'offset') || ' rows ' || jsonb_array_length(:'s1'::jsonb->'rows')::text end || ' | ' || :'l1', 'true | 0 rows ' || :'s1_rows' || ' | 1 | 3 | 1,2');
select pg_temp.chk('S2 rollback 뒤 우리 pid 권고 잠금 0(트랜잭션 끝에 저절로 풀림)', :'l2', '0 | (none)');
select coalesce(string_agg(x.schemaname || '.' || x.sequencename, ',' order by 1), '(none)') as seq_changed from (select schemaname, sequencename, last_value from pg_sequences except select schemaname, sequencename, last_value from t_seq_pre) x \gset
\echo '── 시험 중 last_value 가 바뀐 시퀀스(운영 메인 실제 트래픽 포함 · 정보):' :seq_changed
select pg_temp.chk('Q1 pg_sequences: 이 시험이 닿는 표(mcp_* · ims_staff · mcp_config · hist_* · customer · product)의 시퀀스 무변', (select coalesce(string_agg(x.sequencename, ',' order by 1), '(none)') from (select schemaname, sequencename, last_value from pg_sequences except select schemaname, sequencename, last_value from t_seq_pre) x where x.schemaname = 'public' and x.sequencename ~ '^(mcp_|ims_staff|mcp_config|hist_|customer|product)'), '(none)');
\echo '── 새 판 mcp_sales 본문 md5:' :new_md5 '· busy' :b1_ms 'ms · 성공 길' :s1_ms 'ms'

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다 · 시험 갈래는 mcp_sales md5 도 전과 같다'
select (select count(*) from public.hist_so) = :n_hist as hist_same, (select count(*) from public.hist_so_line) = :n_hist_line as hist_line_same, (select count(*) from public.product) = :n_product as product_same,
       (select count(*) from public.customer) = :n_cust as cust_same, (select count(*) from public.ims_staff) = :n_staff as staff_same, (select count(*) from public.mcp_call_log) = :n_log as log_same,
       (select claude_client_id is not distinct from nullif(:'cid0', '') from public.mcp_config where singleton) as cid_same,
       (select md5(p.prosrc) = :'ms_pre_md5' and pg_get_function_identity_arguments(p.oid) = :'ms_pre_sig' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') as mcp_sales_same;
