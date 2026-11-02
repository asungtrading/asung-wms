-- supabase/tests/qbo_sync_2a2_check.sql — qbo-sync-2a′ 검증: qbo_job_unknown(p_name) · qbo_job_unknown_list (2026-11-01 · 판정 945)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback · 2a(20261102003000) 적용 뒤에 돈다
--   Claude Code(시험): MIG=supabase/migrations/20261102030000_qbo_sync_2a2_unknown_name.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2a2_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK 수 같다
--   쓰기: 가짜 일감 둘(postgres 로 직접 · sending) — 전부 rollback
\set ON_ERROR_STOP on
\set EXPECT_OK 7
\pset pager off
select (select realm_id from public.qbo_connection where singleton) as realm, (select count(*) from public.qbo_job) as n_job0 \gset
begin;
set local lock_timeout = '3s';
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
declare v text; v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
  execute format('set local role %I', p_role);
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return coalesce(v, '(null)');
end $$;
create function pg_temp.svc(p_sql text) returns text language sql as $$ select pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, p_sql) $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g'); exit when v_chunk = v_prev; end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
-- 가짜 일감 둘(sending) — 손님 · 제품(실제 활성 제품 하나의 id 를 빌린다 · sku 를 돌려주는지 보려고)
select p.id::text as pid, btrim(p.sku) as psku from public.product p where p.is_active and nullif(btrim(p.sku), '') is not null order by p.sku limit 1 \gset
insert into public.qbo_job (id, realm_id, kind, ims_kind, ims_id, state, claimed_at, attempts) values
  ('e2a20000-0000-4000-8000-000000000001', :'realm', 'customer', 'customer', 'c2a20000-0000-4000-8000-000000000001', 'sending', now(), 1),
  ('e2a20000-0000-4000-8000-000000000002', :'realm', 'item', 'product', :'pid', 'sending', now(), 2);

select pg_temp.chk('A1 서명 — qbo_job_unknown 은 4 인자 하나 · 둘 다 service_role 만', (select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_job_unknown', 'qbo_job_unknown_list')),
  'qbo_job_unknown(p_job uuid, p_error text, p_intuit_tid text, p_name text)={postgres=X/postgres,service_role=X/postgres} qbo_job_unknown_list()={postgres=X/postgres,service_role=X/postgres}');
select pg_temp.chk('A2 unknown_list 비어 있음(아직 unknown 0)', pg_temp.svc('select public.qbo_job_unknown_list()::text'), '[]');
select pg_temp.svc('select public.qbo_job_unknown(''e2a20000-0000-4000-8000-000000000001'', ''Intuit customer unreachable: timeout'', ''tid-u1'', ''Some Shop Inc'')::text') as u1 \gset
select pg_temp.svc('select public.qbo_job_unknown(''e2a20000-0000-4000-8000-000000000002'', ''HTTP 503 SystemFault'', null, ''Some Product [SKU-1]'')::text') as u2 \gset
select pg_temp.chk('A3 unknown(p_name) → unknown · qbo_name 에 보낸 이름 · last_error · tid · claimed_at null', (:'u1'::jsonb->>'state') || ' ' || (:'u1'::jsonb->>'qbo_name') || ' | ' || (select j.state || ' ' || j.qbo_name || ' ' || j.last_intuit_tid || ' ' || (j.claimed_at is null)::text || ' ' || left(j.last_error, 16) from public.qbo_job j where j.id = 'e2a20000-0000-4000-8000-000000000001'),
  'unknown Some Shop Inc | unknown Some Shop Inc tid-u1 true Intuit customer ');
select pg_temp.chk('A4 unknown_list → 둘(created_at 순) · 손님은 sku null · 제품은 sku · request_id · attempts', (select jsonb_array_length(j)::text || ' ' || (j->0->>'kind') || ':' || (j->0->>'qbo_name') || ':' || coalesce(j->0->>'sku', '-') || ':' || (j->0->>'attempts') || ' ' || (j->1->>'kind') || ':' || (j->1->>'qbo_name') || ':' || (j->1->>'sku') || ':' || (j->1->>'attempts') || ' ' || (j->1->>'request_id' ~ '^[0-9a-f-]{36}$')::text from (select pg_temp.svc('select public.qbo_job_unknown_list()::text')::jsonb j) x),
  '2 customer:Some Shop Inc:-:1 item:Some Product [SKU-1]:' || :'psku' || ':2 true');
select pg_temp.chk('A5 unknown 은 sending 에서만 · p_name 없이도 됨(qbo_name 그대로) · authenticated 는 42501', left(pg_temp.svc('select public.qbo_job_unknown(''e2a20000-0000-4000-8000-000000000001'', ''x'')::text'), 43) || ' | ' || left(pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"a2a2a2a2-0000-4000-8000-000000000009"}'::jsonb, 'select public.qbo_job_unknown_list()::text'), 9),
  'ERR P0001: Only a job being sent can become | ERR 42501');
update public.qbo_job set state = 'sending', claimed_at = now() where id = 'e2a20000-0000-4000-8000-000000000001';
select pg_temp.svc('select public.qbo_job_unknown(''e2a20000-0000-4000-8000-000000000001'', ''again'')::text') as u3 \gset
select pg_temp.chk('A6 p_name null → 옛 qbo_name 유지', (:'u3'::jsonb->>'qbo_name') || ' ' || (select j.qbo_name from public.qbo_job j where j.id = 'e2a20000-0000-4000-8000-000000000001'), 'Some Shop Inc Some Shop Inc');
select pg_temp.chk('L1 nowhere 스캐너 = 0(둘)', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_job_unknown', 'qbo_job_unknown_list') and pg_temp.nowhere(p.prosrc) <> 0), null);

select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.qbo_job) = :n_job0 as jobs_same, (select count(*) from public.qbo_job where id::text like 'e2a20000%') = 0 as fake_jobs_gone;
