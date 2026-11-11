-- supabase/tests/qbo_list_perf_1_check.sql — qbo-list-perf-1 검증 (2026-11-10 토론토 · deferred 561 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] 두 토막:
--   A (트랜잭션 밖 · 잠금 0 · 쓰기는 이 세션의 임시 객체뿐) — 옛 몸(20261111003341 파일)과 새 몸(이 차수 파일)을 pg_temp 사본으로 떠서 같은 인자 · 같은 문장으로 불러 반환 jsonb 를 통째로 비교 + 속도 표
--       사본은 문 한 줄만 다르다(public.qbo_key_gate(false) → null::uuid — v_staff 는 몸에서 쓰지 않는다) · 되돌린 md5 를 A0 가 단언한다
--   B (begin → (-v mig 면 \i) → rollback · lock_timeout 3 s · 가짜 직원 셋만 넣는다) — 착지 · 실제 창구 = 옛 사본 · 문(qbo · qbo:read · 없음 · anon · service_role) · 실제 창구 속도 · 거부 글 · REST 두 겹 ①
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111010639_qbo_list_perf_1_job_list_page_only.sql -f supabase/tests/qbo_list_perf_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(갈래마다 같다)
--   마른 실행(적용 전 · -v mig 없이): A 는 통과 · B 의 착지 · 속도가 FAIL(옛 몸은 느려서 재지 않고 FAIL 로 적는다) → exit 3
--   ⚠️ A 는 옛 몸을 여러 번 부른다(All · Sent 한 번 ≈ 10 s) — 전부 ≈ 6 ~ 7 분 · 읽기뿐이지만 창고 시간에는 돌리지 마라
--   ⚠️ 레포 루트에서 돌린다(\! 가 상대 경로로 두 마이그레이션 파일을 읽는다)
\set ON_ERROR_STOP on
\pset pager off
\set EXPECT_OK 16
\set OLD_MD5 e123778349c5491e728857dc59c17c72
\set NEW_MD5 8342809117f91827f0bcc8c2ba57f2d8
set statement_timeout = 0;
create temp table t_res (n serial, label text, got text, want text, ok boolean);
create temp table t_cmp (n serial, st text, kinds text, q text, lim int, off int, dfrom date, same boolean, n_rows int, total int, ms numeric);
create temp table t_ms (k text primary key, ms_old numeric, ms_new numeric);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns void language sql security definer as $$ insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want); $$;

-- ═══ A) 사본 둘 — 파일에서 함수 문장만 떼어 이름과 문 한 줄을 바꾼다 ═══
\! awk '/^CREATE OR REPLACE FUNCTION public\.qbo_job_list\(/{f=1} f{print} f&&/^\$function\$;/{exit}' supabase/migrations/20261111003341_qbo_hide_1_skipped_job_hide.sql | sed -e '1s/public\.qbo_job_list(/pg_temp.old_list(/' -e 's/public\.qbo_key_gate(false)/null::uuid/' > /tmp/qbo_list_perf_1_old.sql
\! awk '/^CREATE OR REPLACE FUNCTION public\.qbo_job_list\(/{f=1} f{print} f&&/^\$function\$;/{exit}' supabase/migrations/20261111010639_qbo_list_perf_1_job_list_page_only.sql | sed -e '1s/public\.qbo_job_list(/pg_temp.new_list(/' -e 's/public\.qbo_key_gate(false)/null::uuid/' > /tmp/qbo_list_perf_1_new.sql
\i /tmp/qbo_list_perf_1_old.sql
\i /tmp/qbo_list_perf_1_new.sql
select pg_temp.chk('A0 사본의 몸(문 한 줄을 되돌린 md5) = 옛 e1237783… · 새 ' || :'NEW_MD5',
  (select md5(replace(p.prosrc, 'null::uuid', 'public.qbo_key_gate(false)')) from pg_proc p where p.oid = 'pg_temp.old_list(text, text[], date, date, text, int, int)'::regprocedure) || ' ' ||
  (select md5(replace(p.prosrc, 'null::uuid', 'public.qbo_key_gate(false)')) from pg_proc p where p.oid = 'pg_temp.new_list(text, text[], date, date, text, int, int)'::regprocedure), :'OLD_MD5' || ' ' || :'NEW_MD5');

-- 찾기 글은 실물에서 고른다 — 값은 찍지 않는다(손님 이름): doc = 인보이스 번호의 앞 세 글자(여러 줄이 걸린다) · name = 이름의 일부 · qid = QuickBooks id 의 앞 네 글자(qbo_id 갈래) · nohit = 맞는 것 없음 · docfull = 실제 문서 번호 하나(A4 에서)
select (select public.qbo_job_doc(j.ims_kind, j.ims_id)->>'doc_number' from public.qbo_job j where j.ims_kind = 'invoice' and j.state = 'sent' order by j.created_at desc limit 1) as q_doc,
       (select lower(substr(public.qbo_job_doc(j.ims_kind, j.ims_id)->>'name', 2, 4)) from public.qbo_job j where j.ims_kind = 'payment' and j.state = 'sent' order by j.created_at limit 1) as q_name,
       (select left(j.qbo_id, 4) from public.qbo_job j where j.state = 'sent' and length(j.qbo_id) >= 5 order by j.created_at desc limit 1) as q_qid \gset
create temp table t_q as select * from (values ('none', null::text), ('doc', left(:'q_doc', 3)), ('name', :'q_name'), ('qid', :'q_qid'), ('nohit', 'zz-no-such-doc-qq'), ('docfull', :'q_doc')) x(k, q);
create temp table t_qm as select * from t_q where k <> 'docfull';

-- 한 경우 = 한 문장(옛 · 새가 같은 스냅샷) — 반환 jsonb 통째로 같은가
create function pg_temp.cmp(p_state text, p_kinds text[], p_qk text, p_lim int, p_off int, p_from date default null, p_to date default null) returns void language plpgsql as $$
declare v_o jsonb; v_n jsonb; v_q text := (select q from t_q where k = p_qk); v_t timestamptz := clock_timestamp();
begin
  select pg_temp.old_list(p_state, p_kinds, p_from, p_to, v_q, p_lim, p_off), pg_temp.new_list(p_state, p_kinds, p_from, p_to, v_q, p_lim, p_off) into v_o, v_n;
  insert into t_cmp (st, kinds, q, lim, off, dfrom, same, n_rows, total, ms) values (coalesce(p_state, '(all)'), coalesce(p_kinds[1], '(any)'), p_qk, p_lim, p_off, p_from, v_o = v_n, jsonb_array_length(v_n->'rows'), (v_n->>'total')::int,
    round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 0));
end $$;
create temp table t_kinds as select * from (values (1, null::text[]), (2, array['payment', 'payment_void']), (3, array['vendor', 'bill', 'vendor_credit', 'bill_delete_manual']), (4, array['customer', 'item'])) x(i, kinds);
create temp table t_page as select * from (values (50, 0), (50, 50), (200, 0), (200, 50)) x(lim, off);
-- 가벼운 상태 일곱: kinds 4 × q 5 × 쪽 4 = 80 씩
\echo '── A1 가벼운 상태(open · queued · blocked · failed · unknown · skipped · hidden)'
select count(pg_temp.cmp(s.st, k.kinds, q.k, p.lim, p.off)) as cases_light from unnest(array['open', 'queued', 'blocked', 'failed', 'unknown', 'skipped', 'hidden']) s(st), t_kinds k, t_qm q, t_page p;
-- 무거운 상태 둘(All · Sent — 옛 몸 한 번 ≈ 10 s): kinds 4 × q 5 × 쪽 2 = 40 씩
\echo '── A2 무거운 상태(All) — 옛 몸이 느리다'
select count(pg_temp.cmp(null, k.kinds, q.k, p.lim, p.off)) as cases_all from t_kinds k, t_qm q, (values (50, 0), (200, 50)) p(lim, off);
\echo '── A3 무거운 상태(Sent)'
select count(pg_temp.cmp('sent', k.kinds, q.k, p.lim, p.off)) as cases_sent from t_kinds k, t_qm q, (values (50, 0), (200, 50)) p(lim, off);
-- 날짜 거르기 · 경계(limit 1 · 200 넘김 · null · offset 이 끝을 넘김 · 빈칸 찾기 글)
\echo '── A4 날짜 · 경계'
select count(pg_temp.cmp(s.st, null, q.k, 50, 0, public.ims_today() - 2, public.ims_today())) + count(pg_temp.cmp(s.st, null, q.k, 50, 0, null, public.ims_today() - 3)) as cases_date from unnest(array['open', 'skipped', 'blocked']) s(st), t_q q where q.k in ('none', 'name');
select count(pg_temp.cmp(s.st, null, 'none', p.lim, p.off)) as cases_edge from unnest(array['open', 'skipped']) s(st), (values (1, 0), (1, 3), (500, 0), (null::int, null::int), (50, 100000), (0, -5)) p(lim, off);
insert into t_q values ('blank', '   ');
select count(pg_temp.cmp('open', null, 'blank', 50, 0)) + count(pg_temp.cmp(null, null, 'docfull', 50, 0)) + count(pg_temp.cmp('sent', null, 'docfull', 200, 0)) as cases_blank_docfull;
select pg_temp.chk('A1 ~ A4 반환 jsonb 통째 비교 — 다른 경우 0 · 경우 수 = 7×80 + 2×40 + 12 + 12 + 3 = 667', (select count(*) filter (where not same or same is null)::text || ' / ' || count(*)::text from t_cmp), '0 / 667');
select pg_temp.chk('A5 빈 비교가 아니다 — 행이 있는 경우 ≥ 60 · 찾기 갈래마다(doc · name · qid · docfull) 행이 나온 경우 ≥ 1 · 찾기로 좁혀진(행 > 0) 경우 ≥ 15 · 둘째 쪽(offset 50)에 행이 있는 경우 ≥ 5 · 꽉 찬 쪽(200 행) ≥ 1',
  (select (count(*) filter (where n_rows > 0) >= 60)::text || ' ' || (count(distinct q) filter (where n_rows > 0 and q in ('doc', 'name', 'qid', 'docfull')) = 4)::text || ' ' || (count(*) filter (where n_rows > 0 and q in ('doc', 'name', 'qid', 'docfull')) >= 15)::text || ' '
       || (count(*) filter (where n_rows > 0 and off = 50) >= 5)::text || ' ' || (count(*) filter (where n_rows = 200) >= 1)::text from t_cmp), 'true true true true true');
select q, count(*) as cases, count(*) filter (where n_rows > 0) as with_rows, max(total) as max_total from t_cmp group by q order by q;
select st, count(*) as cases, count(*) filter (where n_rows > 0) as with_rows, count(*) filter (where not same) as differ, max(total) as max_total, round(sum(ms) / 1000, 1) as sec from t_cmp group by st order by st;

-- ═══ A6) 속도 — 옛 · 새 사본을 따로 재서(각 두 번 중 빠른 쪽) 표로 ═══
create function pg_temp.ms1(p_fn text, p_state text, p_qk text) returns numeric language plpgsql as $$
declare v_t timestamptz; v_len bigint; v_best numeric; v_i int; v_q text := (select q from t_q where k = p_qk);
begin
  for v_i in 1 .. 2 loop
    v_t := clock_timestamp();
    execute format('select length(pg_temp.%I($1, null, null, null, $2, 50, 0)::text)', p_fn) into v_len using p_state, v_q;
    v_best := least(v_best, round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 0));
  end loop;
  return v_best;
end $$;
\echo '── A6 속도(옛 몸을 열 번 남짓 부른다 — 1 분쯤)'
insert into t_ms select x.k, pg_temp.ms1('old_list', x.st, x.qk), pg_temp.ms1('new_list', x.st, x.qk)
  from (values ('1 All', null, 'none'), ('2 Sent', 'sent', 'none'), ('3 Blocked', 'blocked', 'none'), ('4 Open', 'open', 'none'), ('5 Hidden', 'hidden', 'none'), ('6 All + find(doc number)', null, 'doc'), ('7 All + find(name)', null, 'name')) x(k, st, qk);
select k as view, ms_old, ms_new from t_ms order by k;
select pg_temp.chk('A6 새 몸: All · Sent < 2,000 ms · Blocked · Open · Hidden 은 옛 몸보다 늘지 않음(+50 ms 까지) · 찾기(All)도 < 2,000 ms',
  (select bool_and(ms_new < 2000) filter (where k like '1%' or k like '2%')::text || ' ' || bool_and(ms_new <= ms_old + 50) filter (where k like '3%' or k like '4%' or k like '5%')::text || ' ' || bool_and(ms_new < 2000) filter (where k like '6%' or k like '7%')::text from t_ms), 'true true true');
select coalesce(string_agg(k || ' ' || ms_old || ' → ' || ms_new, ' · ' order by k), '') as ms_line from t_ms \gset

-- ═══ B) 실제 창구 — begin → (시험 적용) → rollback ═══
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
create function pg_temp.who(p_n int, p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', jsonb_build_object('role', 'authenticated', 'sub', 'f1de0001-0000-4000-8000-00000000000' || p_n), p_sql) $$;
create function pg_temp.msw(p_sql text) returns numeric language plpgsql as $$
declare v_t timestamptz := clock_timestamp(); v text;
begin
  v := pg_temp.who(1, p_sql);
  if v !~ '^\d+$' then return 999999; end if;
  return round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 0);
end $$;
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
select (select md5(p.prosrc) from pg_proc p where p.oid = 'public.qbo_job_doc(text, text)'::regprocedure) as doc_md5_pre,
       (select md5(string_agg(p.proname || ':' || md5(p.prosrc), ',' order by p.proname, p.oid)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%' and p.proname <> 'qbo_job_list') as others_pre \gset
select set_config('perf.new_md5', :'NEW_MD5', false) as g1, set_config('perf.others_pre', :'others_pre', false) as g2;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('f1de0001-0000-4000-8000-0000000000a1', 'f1de0001-0000-4000-8000-000000000001', 'qbo-list-perf-1-w@asung.invalid', 'ZZPERF Writer', 'manager', '["qbo"]'),
  ('f1de0001-0000-4000-8000-0000000000a2', 'f1de0001-0000-4000-8000-000000000002', 'qbo-list-perf-1-r@asung.invalid', 'ZZPERF Reader', 'manager', '["qbo:read"]'),
  ('f1de0001-0000-4000-8000-0000000000a3', 'f1de0001-0000-4000-8000-000000000003', 'qbo-list-perf-1-n@asung.invalid', 'ZZPERF Nokey', 'manager', '[]');
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select (md5(p.prosrc) = :'NEW_MD5') as is_new from pg_proc p where p.oid = 'public.qbo_job_list(text, text[], date, date, text, int, int)'::regprocedure \gset
do $$
declare v_oid oid := 'public.qbo_job_list(text, text[], date, date, text, int, int)'::regprocedure; v text; v_same text;
begin
  perform pg_temp.chk('B1 착지: 새 몸 md5 · 실행권(postgres · authenticated 만) · stable · definer · search_path · 같은 이름 함수 하나',
    (select md5(p.prosrc) || ' ' || p.proacl::text || ' ' || p.provolatile::text || ' ' || p.prosecdef::text || ' ' || p.proconfig::text from pg_proc p where p.oid = v_oid) || ' ' || (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = 'qbo_job_list')::text,
    current_setting('perf.new_md5') || ' {postgres=X/postgres,authenticated=X/postgres} s true {"search_path=public, pg_temp"} 1');
  v := obj_description(v_oid, 'pg_proc');
  perform pg_temp.chk('B2 comment: 앞 글(qbo-sync-2a … qbo-hide-1 판정 1152)이 남고 끝에 qbo-list-perf-1 한 번', (v like 'qbo-sync-2a%')::text || ' ' || (v like '%[qbo-hide-1 판정 1152:%')::text || ' ' || ((length(v) - length(replace(v, '[qbo-list-perf-1 deferred 561:', ''))) / length('[qbo-list-perf-1 deferred 561:'))::text, 'true true 1');
  perform pg_temp.chk('B3 무접촉: qbo_job_doc md5 · 그 밖의 qbo_ 함수 몸 전부 그대로',
    (select md5(p.prosrc) from pg_proc p where p.oid = 'public.qbo_job_doc(text, text)'::regprocedure) || ' ' ||
    ((select md5(string_agg(p.proname || ':' || md5(p.prosrc), ',' order by p.proname, p.oid)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%' and p.proname <> 'qbo_job_list') = current_setting('perf.others_pre'))::text,
    '9d6a689d2b3814991deabe6310597931 true');
  perform pg_temp.chk('B4 REST 두 겹 ①: 새 몸의 깊이 0 WHERE 없는 update · delete = 0(읽기 함수) · 몸에 insert · update · delete 글자 0',
    pg_temp.nowhere((select p.prosrc from pg_proc p where p.oid = v_oid)) || ' ' || (select count(*) from regexp_matches(regexp_replace((select p.prosrc from pg_proc p where p.oid = v_oid), '--[^\n]*', '', 'g'), '\m(insert|update|delete|truncate)\M', 'gi'))::text, '0 0');
  -- 실제 창구 = 옛 사본(같은 문장 · 가짜 qbo 직원 claims 를 postgres 세션에 세워 문을 지난다)
  perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"f1de0001-0000-4000-8000-000000000001"}', true);
  select (public.qbo_job_list('skipped', null, null, null, null, 200, 0) = pg_temp.old_list('skipped', null, null, null, null, 200, 0))::text || ' ' ||
         (public.qbo_job_list('open', array['payment', 'payment_void'], null, null, (select q from t_q where k = 'name'), 50, 0) = pg_temp.old_list('open', array['payment', 'payment_void'], null, null, (select q from t_q where k = 'name'), 50, 0))::text || ' ' ||
         (public.qbo_job_list('blocked') = pg_temp.old_list('blocked'))::text into v_same;
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.chk('B5 실제 창구(public) = 옛 사본 — skipped 200 · open + kinds + 찾기 · blocked(기본 인자)', v_same, 'true true true');
  -- 문: 실제 authenticated 역할로
  perform pg_temp.chk('B6 문: qbo(쓰기) 직원 · qbo:read 직원은 읽는다(total 이 숫자) · 열쇠 없는 직원은 거부 글 그대로',
    (pg_temp.who(1, $q$ select (public.qbo_job_list('hidden'))->>'total' $q$) ~ '^\d+$')::text || ' ' || (pg_temp.who(2, $q$ select (public.qbo_job_list('hidden'))->>'total' $q$) ~ '^\d+$')::text || ' ' ||
    (pg_temp.who(3, $q$ select (public.qbo_job_list('hidden'))->>'total' $q$) like 'ERR P0001: Your account does not have the ''qbo'' permission — ask an admin to switch it on in Staff — nothing was changed')::text, 'true true true');
  perform pg_temp.chk('B7 문: 직원 아님(없는 sub) 거부 · anon · service_role 은 못 부른다(42501)',
    (pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"f1de0001-0000-4000-8000-0000000000ff"}'::jsonb, $q$ select (public.qbo_job_list('hidden'))->>'total' $q$) like 'ERR P0001: You are not registered as active staff%')::text || ' ' ||
    left(pg_temp.as_conn('anon', '{"role":"anon"}'::jsonb, $q$ select (public.qbo_job_list('hidden'))->>'total' $q$), 9) || ' ' || left(pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, $q$ select (public.qbo_job_list('hidden'))->>'total' $q$), 9), 'true ERR 42501 ERR 42501');
  perform pg_temp.chk('B8 거부 글 그대로: 모르는 상태 · 모르는 kind · 빈 kinds · from > to',
    (pg_temp.who(1, $q$ select public.qbo_job_list('nope')::text $q$) like 'ERR P0001: state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open, hidden (got nope)')::text || ' ' ||
    (pg_temp.who(1, $q$ select public.qbo_job_list(null, array['nope'])::text $q$) like 'ERR P0001: kinds must be among customer, item, invoice,%bill_payment_void (got {nope})')::text || ' ' ||
    (pg_temp.who(1, $q$ select public.qbo_job_list(null, array[]::text[])::text $q$) like 'ERR P0001: kinds must be among %(got {})')::text || ' ' ||
    (pg_temp.who(1, $q$ select public.qbo_job_list(null, null, '2026-11-10', '2026-11-01')::text $q$) like 'ERR P0001: from 2026-11-10 is after to 2026-11-01 — nothing was read')::text, 'true true true true');
  v := pg_temp.who(2, $q$ select (select string_agg(k, ',' order by k collate "C") from jsonb_object_keys((public.qbo_job_list('skipped', null, null, null, null, 1, 0))->'rows'->0) k) $q$);
  perform pg_temp.chk('B9 행의 칸 38 개 이름 그대로(qbo:read 직원)', v,
    'attempts,blocked_by,blocked_kind,blocked_name,blocked_state,by_name,by_staff,claimed_at,created_at,currency,doc_date,doc_number,doc_status,hidden_at,hidden_by_name,id,ims_id,ims_kind,ims_name,job_date,kind,last_error,last_intuit_tid,name,next_at,note,qbo_id,qbo_name,sent_at,state,total,txn_mismatch,txn_qbo_id,txn_total_amt,txn_total_tax,txn_voided_at,updated_at,warning');
  v := pg_temp.who(2, $q$ select (select string_agg(k, ',' order by k collate "C") from jsonb_object_keys(public.qbo_job_list('hidden')) k) || ' | ' || ((public.qbo_job_list('hidden'))->'counts' ? 'hidden')::text $q$);
  perform pg_temp.chk('B10 머리 열쇠 10 개 그대로 · counts 에 hidden 이 늘 있다', v, 'counts,from,kinds,limit,offset,q,rows,state,to,total | true');
end $$;
-- 실제 창구 속도 — 새 몸일 때만 잰다(옛 몸은 All · Sent 가 10 초 남짓이라 잠금 구간에서 부르지 않는다 → FAIL 로 적는다)
\if :is_new
select pg_temp.msw($q$ select length(public.qbo_job_list()::text)::text $q$) as ms_all, pg_temp.msw($q$ select length(public.qbo_job_list('sent')::text)::text $q$) as ms_sent \gset
select pg_temp.chk('B11 실제 창구 속도(authenticated · qbo 직원): All · Sent 둘 다 < 2,000 ms', (:ms_all < 2000)::text || ' ' || (:ms_sent < 2000)::text, 'true true'), :ms_all as ms_all, :ms_sent as ms_sent;
\else
select pg_temp.chk('B11 실제 창구 속도(authenticated · qbo 직원): All · Sent 둘 다 < 2,000 ms', 'not measured — public.qbo_job_list is still the old body (All 10 s · Sent 12 s)', 'true true');
\endif
select pg_temp.chk('B12 잠금 구간(begin → 여기) < 10 s', (extract(epoch from clock_timestamp() - :'t_begin'::timestamptz) < 10)::text, 'true'), round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 1) as sec_in_txn;

-- ═══ 집계(rollback 앞) ═══
select n, case when ok then 'OK  ' else 'FAIL' end as r, label, case when ok then '' else 'got: ' || coalesce(got, '(null)') || ' · want: ' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok or ok is null) as n_fail from t_res \gset
rollback;
\echo '── 속도(ms · 옛 → 새):' :ms_line
\echo '── OK' :n_ok '/ 기대' :EXPECT_OK '· FAIL' :n_fail
select (:n_fail = 0 and :n_ok = :EXPECT_OK) as pass \gset
\if :pass
\echo 'PASS qbo-list-perf-1'
\else
do $$ begin raise exception 'qbo-list-perf-1 check FAILED — see FAIL lines above'; end $$;
\endif
