-- supabase/tests/qbo_read_1_check.sql — qbo-read-1 검증: qbo_call_log.detail jsonb 칸 하나 · 다른 것 무접촉 (2026-11-01 · 판정 933 · 이견 1 「B」)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): MIG=supabase/migrations/20261101190000_qbo_read_1_call_log_detail.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_read_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 두 갈래의 차이는 G0(시험만 · echo 줄 · t_res 밖) · 기대 OK 수는 같다(13)
--   쓰기: qbo_call_log 가짜 줄 셋(action qbo-read-1-test · 전부 rollback) · 실제 행 0 변경 · 함수 · 정책 · grant 무접촉
--   REST 두 겹: ① 이 차수는 DB 창구를 새로 만들지도 부르지도 않는다 — EF 의 call_log 쓰기 길은 insert 와 90 일 delete(WHERE called_at=lt. · index.ts recordCall) 둘뿐 · L1 이 qbo_* 함수 17 의 md5 무변을 센다 ② 배포 뒤 Caleb 의 콘솔 두 줄(CompanyInfo · count Item)
\set ON_ERROR_STOP on
\set EXPECT_OK 13
\pset pager off
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%';
select (select count(*) from t_pre) as n_fn, (select count(*) from public.qbo_call_log) as n_log0, (select count(*) from public.qbo_connection) as w_conn,
       (select relacl::text from pg_class where oid = 'public.qbo_call_log'::regclass) as acl0,
       (select string_agg(policyname || ':' || cmd || ':' || roles::text, ' ' order by policyname) from pg_policies where schemaname = 'public' and tablename = 'qbo_call_log') as pol0,
       (select string_agg(conname || ':' || contype::text, ' ' order by conname) from pg_constraint where conrelid = 'public.qbo_call_log'::regclass) as con0,
       (select string_agg(indexname, ' ' order by indexname) from pg_indexes where schemaname = 'public' and tablename = 'qbo_call_log') as idx0 \gset
\echo '── 기준: qbo_* 함수' :n_fn '· qbo_call_log 줄' :n_log0 '· qbo_connection' :w_conn
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
-- 역할 · claims 를 바꿔 한 문장을 돌린다(끝나면 되돌린다 · 오류는 'ERR sqlstate: msg' 글로) — mcp_2_check 의 as_conn 그대로
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

-- ── A) 착지 — 칸 12(detail jsonb 가 끝에) · 제약 · 색인 · acl · 정책 무변 ──
select pg_temp.chk('A1 칸 12 · 꼴(detail jsonb 가 끝에)', (select string_agg(column_name || ':' || data_type, ' ' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'qbo_call_log'),
  'id:bigint called_at:timestamp with time zone env:text realm_id:text action:text ok:boolean http_status:integer intuit_tid:text error:text by_staff:uuid ms:integer detail:jsonb');
select pg_temp.chk('A2 detail 은 null 허용 · 기본값 없음', (select is_nullable || '/' || coalesce(column_default, '-') from information_schema.columns where table_schema = 'public' and table_name = 'qbo_call_log' and column_name = 'detail'), 'YES/-');
select pg_temp.chk('A3 제약 그대로 — PK · FK 하나(by_staff → ims_staff) · 거래 표 FK 0', (select string_agg(conname || ':' || contype::text, ' ' order by conname) from pg_constraint where conrelid = 'public.qbo_call_log'::regclass), :'con0');
select pg_temp.chk('A3b FK 의 상대는 ims_staff 뿐', (select string_agg(confrelid::regclass::text, ' ') from pg_constraint where conrelid = 'public.qbo_call_log'::regclass and contype = 'f'), 'ims_staff');
select pg_temp.chk('A4 색인 그대로', (select string_agg(indexname, ' ' order by indexname) from pg_indexes where schemaname = 'public' and tablename = 'qbo_call_log'), :'idx0');
select pg_temp.chk('A5 표 acl 그대로(authenticated r · service_role r/insert/delete) + RLS', (select relacl::text || ' rls=' || relrowsecurity::text from pg_class where oid = 'public.qbo_call_log'::regclass), :'acl0' || ' rls=true');
select pg_temp.chk('A6 정책 그대로(select · authenticated)', (select string_agg(policyname || ':' || cmd || ':' || roles::text, ' ' order by policyname) from pg_policies where schemaname = 'public' and tablename = 'qbo_call_log'), :'pol0');
select pg_temp.chk('A7 칸 comment 에 「결과 행은 담지 않는다」', (select (col_description('public.qbo_call_log'::regclass, attnum) like '%결과 행은 담지 않는다%')::text from pg_attribute where attrelid = 'public.qbo_call_log'::regclass and attname = 'detail'), 'true');

-- ── B) EF 의 쓰기 길 그대로 — service_role insert(detail 있음 · 없음) · 기존 줄 detail null · authenticated 는 읽기만 ──
select pg_temp.chk('B1 service_role insert — detail jsonb 있음 · 없음 둘 다',
  left(pg_temp.as_conn('service_role', '{"role":"service_role"}', $q$insert into public.qbo_call_log (env, realm_id, action, ok, http_status, intuit_tid, ms, detail) values ('sandbox', '1', 'qbo-read-1-test', true, 200, 'tid-x', 12, '{"entity":"Customer","rows":2,"q":"select Id from Customer where DisplayName = ?","startPosition":1,"maxResults":100}') returning action$q$), 15)
  || ' ' || left(pg_temp.as_conn('service_role', '{"role":"service_role"}', $q$insert into public.qbo_call_log (env, realm_id, action, ok, ms) values ('sandbox', '1', 'qbo-read-1-test', true, 3) returning action$q$), 15), 'qbo-read-1-test qbo-read-1-test');
select pg_temp.chk('B2 넣은 줄 — detail 의 entity · rows · q 그대로 · 둘째 줄 detail null', (select string_agg(coalesce(detail->>'entity', '-') || '/' || coalesce(detail->>'rows', '-') || '/' || coalesce(detail->>'q', '-'), ' | ' order by id) from public.qbo_call_log where action = 'qbo-read-1-test'),
  'Customer/2/select Id from Customer where DisplayName = ? | -/-/-');
select pg_temp.chk('B3 기존 줄은 전부 detail null(칸 추가가 값을 만들지 않는다)', (select count(*)::text from public.qbo_call_log where action <> 'qbo-read-1-test' and detail is not null), '0');
select pg_temp.chk('B4 authenticated — 읽기는 되고(RLS true) insert · update · delete 는 42501',
  (pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"00000000-0000-4000-8000-000000000000"}', $q$select count(*)::text from public.qbo_call_log where action = 'qbo-read-1-test'$q$))
  || ' ' || left(pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"00000000-0000-4000-8000-000000000000"}', $q$insert into public.qbo_call_log (action, ok) values ('x', true) returning action$q$), 9)
  || ' ' || left(pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"00000000-0000-4000-8000-000000000000"}', $q$update public.qbo_call_log set detail = null where action = 'qbo-read-1-test' returning action$q$), 9)
  || ' ' || left(pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"00000000-0000-4000-8000-000000000000"}', $q$delete from public.qbo_call_log where action = 'qbo-read-1-test' returning action$q$), 9), '2 ERR 42501 ERR 42501 ERR 42501');

-- ── L) REST 두 겹 ① — DB 창구 무접촉(qbo_* 함수 17 md5 = begin 앞) · 90 일 delete 는 EF 쪽 WHERE(index.ts recordCall) ──
select pg_temp.chk('L1 qbo_* 함수 md5 전부 begin 앞과 같다 · 수 그대로', (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) || '/' || (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname like 'qbo\_%'), :n_fn || '/' || :n_fn);

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.qbo_call_log) = :n_log0 as log_rows_same, (select count(*) from public.qbo_connection) = :w_conn as conn_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same,
       (select count(*) from public.qbo_call_log where action = 'qbo-read-1-test') = 0 as fake_rows_gone;
\if :{?mig}
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'qbo_call_log' and column_name = 'detail') = 0 as detail_column_gone_as_expected;
\else
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'qbo_call_log' and column_name = 'detail') = 1 as detail_column_present;
\endif
