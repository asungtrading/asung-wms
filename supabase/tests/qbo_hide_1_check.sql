-- supabase/tests/qbo_hide_1_check.sql — qbo-hide-1 검증 (2026-11-10 토론토 · 판정 1152 + 보충 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] 기준(begin 앞) → begin(lock_timeout 3s) → 가짜 재료(DO 하나 · 직원 셋 · 일감 여덟 — 표에 직접 · 창구로 문서를 발행하지 않는다) → 옛 목록 시간(T1 앞) → (-v mig 면 \i) → 시나리오(DO 하나) → 구조 · 정적 검사 → 집계 → rollback
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111003341_qbo_hide_1_skipped_job_hide.sql -f supabase/tests/qbo_hide_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(갈래마다 같다)
--   마른 실행(적용 전 · -v mig 없이): 새 창구 · 칸이 없어 대부분 FAIL 로 잡히고 exit 3(죽지 않는다 — 모든 호출이 try 로 싸여 있다)
--   ⚠️ 가짜 재료만(직원 f1de0000-… · 일감 kind customer · ims_id = 가짜 uuid · 다른 realm 하나 'zz-hide-other-realm') — 실제 행은 읽기만
--   ⚠️ 목록은 늘 p_kinds ['customer'] + p_from 오늘로 좁혀 부른다 — 좁히지 않은 All · Sent 는 지금 10 ~ 12 초(실측 11-10)라 잠금을 쥔 채 부르지 않는다 · T1 만 'blocked'
\set ON_ERROR_STOP on
\pset pager off
\if :{?mig}
\set EXPECT_OK 34
\else
\set EXPECT_OK 34
\endif
\set NEW_LIST_MD5 e123778349c5491e728857dc59c17c72
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%';
create temp table t_ids (k text primary key, v text);
insert into t_ids values ('realm', (select realm_id from public.qbo_connection where singleton)), ('today', public.ims_today()::text), ('new_list_md5', :'NEW_LIST_MD5');
select (select count(*) from t_pre) as n_fn, (select md5 from t_pre where proname = 'qbo_job_list') as pre_list_md5, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.qbo_job) as n_job0 \gset
\echo '── 기준: qbo_ 함수' :n_fn '· qbo_job_list' :pre_list_md5 '· job' :n_job0
create temp table t_res (n serial, label text, got text, want text, ok boolean);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns void language sql as $$ insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want); $$;
create function pg_temp.id(p_k text) returns text language sql as $$ select v from t_ids where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_ids values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
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
-- bk = 쓰기 열쇠(qbo) 가짜 직원 · rd = 보기 열쇠(qbo:read)만 · try = postgres 로(직접 update 시험 · 읽기)
create function pg_temp.bk(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"f1de0000-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
create function pg_temp.rd(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"f1de0000-0000-4000-8000-000000000002"}'::jsonb, p_sql) $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  return coalesce(v, '(null)');
end $$;
-- 좁힌 목록(가짜 일감만 걸리게: kind customer · 오늘) — p_what: total | counts.<k> | ids(행 id 를 글자 순으로) | row.<칸>(첫 행)
create function pg_temp.ls(p_state text, p_what text, p_q text default null) returns text language plpgsql as $$
declare v text; v_j jsonb;
begin
  v := pg_temp.bk(format('select public.qbo_job_list(%L, array[''customer''], %L::date, null, %L, 200, 0)::text', p_state, pg_temp.id('today'), p_q));
  if v like 'ERR %' then return v; end if;
  v_j := v::jsonb;
  if p_what = 'total' then return v_j->>'total'; end if;
  if p_what like 'counts.%' then return coalesce(v_j->'counts'->>substr(p_what, 8), '(absent)'); end if;
  if p_what = 'ids' then return coalesce((select string_agg(x->>'id', ',' order by x->>'id') from jsonb_array_elements(v_j->'rows') x), '(none)'); end if;
  if p_what like 'row.%' then return coalesce(v_j->'rows'->0->>substr(p_what, 5), '(null)'); end if;
  return '?';
end $$;
-- 창구가 돌려준 글을 jsonb 로 고른 글(또는 그 열쇠 하나) — 'ERR …' 면 그대로(마른 실행이 죽지 않게)
create function pg_temp.j(p_v text, p_key text default null) returns text language sql as $$ select case when p_v like 'ERR %' or p_v = '(null)' then p_v when p_key is null then (p_v::jsonb)::text else p_v::jsonb->>p_key end $$;
create function pg_temp.hide(p_keys text[], p_hide boolean, p_as text default 'bk') returns text language plpgsql as $$
declare v_sql text := format('select public.qbo_job_hide(%L::uuid[], %L)::text', (select coalesce(array_agg(pg_temp.id(k)), '{}') from unnest(p_keys) k), p_hide);
begin
  return case p_as when 'rd' then pg_temp.rd(v_sql) else pg_temp.bk(v_sql) end;
end $$;
-- 일감 하나의 꼴: state · 숨김 여부 · 숨긴 사람 열쇠 · updated_at 이 Skip 때 값인가 · updated_by 열쇠
create function pg_temp.job(p_k text) returns text language sql as $$
  select pg_temp.try(format($q$ select j.state || ' hidden=' || (j.hidden_at is not null)::text || ' by=' || coalesce((select k from t_ids where v = j.hidden_by::text), '-') || ' skip_at_kept=' || (j.updated_at = '2026-11-05 15:00:00+00'::timestamptz)::text || ' upd_by=' || coalesce((select k from t_ids where v = j.updated_by::text), '-') from public.qbo_job j where j.id = %L $q$, pg_temp.id(p_k)))
$$;
create function pg_temp.ms(p_sql text) returns numeric language plpgsql as $$
declare v_t timestamptz := clock_timestamp(); v text;
begin
  v := pg_temp.bk(p_sql);
  if v like 'ERR %' then return null; end if;
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

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
-- ── 가짜 재료(마이그레이션 앞 — 새 칸을 쓰지 않는다): 직원 W(qbo) · R(qbo:read) · S(Skip 한 사람) · 일감 a1 ~ a3 · b1 skipped · q1 queued · p1 skipped + c1 blocked(p1 을 기다림) · x1 다른 realm skipped
do $$
declare v_realm text := pg_temp.id('realm'); v_k text; v_id uuid; v_s uuid := 'f1de0000-0000-4000-8000-00000000000c';
begin
  insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
    ('f1de0000-0000-4000-8000-00000000000a', 'f1de0000-0000-4000-8000-000000000001', 'qbo-hide-1-w@asung.invalid', 'ZZHIDE Writer', 'manager', '["qbo"]'),
    ('f1de0000-0000-4000-8000-00000000000b', 'f1de0000-0000-4000-8000-000000000002', 'qbo-hide-1-r@asung.invalid', 'ZZHIDE Reader', 'manager', '["qbo:read"]'),
    (v_s, 'f1de0000-0000-4000-8000-000000000003', 'qbo-hide-1-s@asung.invalid', 'ZZHIDE Skipper', 'manager', '[]');
  perform pg_temp.put('W', 'f1de0000-0000-4000-8000-00000000000a'), pg_temp.put('R', 'f1de0000-0000-4000-8000-00000000000b'), pg_temp.put('S', v_s::text);
  foreach v_k in array array['a1', 'a2', 'a3', 'b1', 'p1'] loop
    insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, note, by_staff, updated_at, updated_by) values (v_realm, 'customer', 'customer', gen_random_uuid()::text, 'skipped', 'zz hide test: settled by hand in QuickBooks', v_s, '2026-11-05 15:00:00+00', v_s) returning id into v_id;
    perform pg_temp.put(v_k, v_id::text);
  end loop;
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, updated_at, updated_by) values (v_realm, 'customer', 'customer', gen_random_uuid()::text, 'queued', v_s, '2026-11-05 15:00:00+00', v_s) returning id into v_id;
  perform pg_temp.put('q1', v_id::text);
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, updated_at, updated_by) values (v_realm, 'customer', 'customer', gen_random_uuid()::text, 'blocked', pg_temp.id('p1')::uuid, v_s, '2026-11-05 15:00:00+00', v_s) returning id into v_id;
  perform pg_temp.put('c1', v_id::text);
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, note, by_staff, updated_at, updated_by) values ('zz-hide-other-realm', 'customer', 'customer', gen_random_uuid()::text, 'skipped', 'zz hide test: other realm', v_s, '2026-11-05 15:00:00+00', v_s) returning id into v_id;
  perform pg_temp.put('x1', v_id::text);
  perform pg_temp.put('missing', gen_random_uuid()::text);
  perform pg_temp.put('a1_ims', (select j.ims_id from public.qbo_job j where j.id = pg_temp.id('a1')::uuid));
end $$;
-- T1 앞: 지금 서 있는 목록 함수(시험 갈래 = 옛 판 · 확인 갈래 = 새 판)의 'blocked' 두 번 중 빠른 쪽 + 앞 셈(좁힌 목록 · counts 는 realm 전체)
select least(pg_temp.ms($q$ select (public.qbo_job_list('blocked'))->>'total' $q$), pg_temp.ms($q$ select (public.qbo_job_list('blocked'))->>'total' $q$)) as ms_pre,
       pg_temp.ls('skipped', 'total')::int as ts0, pg_temp.ls('open', 'total')::int as to0, pg_temp.ls(null, 'total')::int as ta0, pg_temp.ls('skipped', 'counts.skipped')::int as cs0,
       (select count(*) from public.qbo_job j where j.realm_id = pg_temp.id('realm') and j.state = 'skipped') as n_skipped_realm \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset
select pg_temp.put('ms_pre', :'ms_pre'), pg_temp.put('ts0', :'ts0'), pg_temp.put('to0', :'to0'), pg_temp.put('ta0', :'ta0'), pg_temp.put('cs0', :'cs0'), pg_temp.put('n_skipped_realm', :'n_skipped_realm');

-- ── 시나리오(DO 하나 · 순서대로) — 기대값은 앞 셈(ts0 · to0 · ta0 · cs0 · th0 · ch0)에서 식으로
do $$
declare ts0 int := pg_temp.id('ts0')::int; to0 int := pg_temp.id('to0')::int; ta0 int := pg_temp.id('ta0')::int; cs0 int := pg_temp.id('cs0')::int; th0 int; ch0 int; v text; v_ms numeric;
  v_a text := (select string_agg(x, ',' order by x) from unnest(array[pg_temp.id('a1'), pg_temp.id('a2'), pg_temp.id('a3')]) x);
begin
  -- P 앞 셈: 좁힌 hidden 보기 · counts.hidden(늘 있는 열쇠) · counts.skipped 는 실제 skipped 수(숨긴 것 0 일 때)
  v := pg_temp.ls('hidden', 'total'); th0 := case when v ~ '^\d+$' then v::int else -1 end; v := pg_temp.ls('skipped', 'counts.hidden'); ch0 := case when v ~ '^\d+$' then v::int else -1 end;   -- 마른 실행(적용 전)에서는 -1(뒤 검사가 FAIL 로 잡는다)
  perform pg_temp.chk('P1 앞 셈: counts.skipped = realm 의 skipped 수(가짜 5 포함 · 숨긴 것 0) · counts.hidden 열쇠가 0 이어도 있다 · 좁힌 hidden 보기 0', cs0::text || ' ' || ch0::text || ' ' || th0::text, pg_temp.id('n_skipped_realm') || ' 0 0');
  -- H1 skipped 3 건 hide
  perform pg_temp.chk('H1a hide 3 → changed 3 · already 0 · hidden true', pg_temp.j(pg_temp.hide(array['a1', 'a2', 'a3'], true)), jsonb_build_object('changed', 3, 'already', 0, 'hidden', true)::text);
  perform pg_temp.chk('H1b list(skipped) 에서 3 빠짐 · list(hidden) 에 그 3 건만 · counts.skipped − 3 · counts.hidden + 3',
    pg_temp.ls('skipped', 'total') || ' ' || pg_temp.ls('hidden', 'total') || ' ' || (pg_temp.ls('hidden', 'ids') = v_a)::text || ' ' || pg_temp.ls('skipped', 'counts.skipped') || ' ' || pg_temp.ls('skipped', 'counts.hidden'),
    (ts0 - 3)::text || ' ' || (th0 + 3)::text || ' true ' || (cs0 - 3)::text || ' ' || (ch0 + 3)::text);
  perform pg_temp.chk('H1c 숨긴 줄의 꼴: state 는 skipped 그대로 · hidden_by_name = 숨긴 직원 · hidden_at 있음', pg_temp.ls('hidden', 'row.state') || ' ' || pg_temp.ls('hidden', 'row.hidden_by_name') || ' ' || (pg_temp.ls('hidden', 'row.hidden_at') <> '(null)')::text, 'skipped ZZHIDE Writer true');
  perform pg_temp.chk('H1d 숨긴 뒤 updated_at · updated_by 는 Skip 때 값 그대로(보충 이견 1) · hidden_by = 숨긴 직원 — 3 건 모두', pg_temp.job('a1') || ' | ' || pg_temp.job('a2') || ' | ' || pg_temp.job('a3'),
    'skipped hidden=true by=W skip_at_kept=true upd_by=S | skipped hidden=true by=W skip_at_kept=true upd_by=S | skipped hidden=true by=W skip_at_kept=true upd_by=S');
  -- H2 멱등
  perform pg_temp.chk('H2 같은 3 건 다시 hide → changed 0 · already 3', pg_temp.j(pg_temp.hide(array['a1', 'a2', 'a3'], true)), jsonb_build_object('changed', 0, 'already', 3, 'hidden', true)::text);
  perform pg_temp.chk('H2b 이미 숨긴 2 + 새 1(b1) → changed 1 · already 2 → b1 다시 보이기 changed 1', pg_temp.j(pg_temp.hide(array['a1', 'a2', 'b1'], true)) || ' ' || pg_temp.j(pg_temp.hide(array['b1'], false)),
    jsonb_build_object('changed', 1, 'already', 2, 'hidden', true)::text || ' ' || jsonb_build_object('changed', 1, 'already', 0, 'hidden', false)::text);
  -- H3 섞임 → 전부 아니면 아무것도
  v := pg_temp.hide(array['b1', 'q1'], true);
  perform pg_temp.chk('H3 skipped 1 + queued 1 → 예외(1 of the 2 … not skipped · nothing was changed) · 둘 다 그대로', (v like 'ERR P0001:%Only skipped jobs can be hidden — 1 of the 2 picked jobs are not skipped — nothing was changed')::text || ' ' || pg_temp.job('b1') || ' | ' || pg_temp.job('q1'),
    'true skipped hidden=false by=- skip_at_kept=true upd_by=S | queued hidden=false by=- skip_at_kept=true upd_by=S');
  -- H4 없는 id · 중복 · 빈 배열 · null · 다른 realm · p_hide null
  perform pg_temp.chk('H4a 없는 id 섞임 → 예외(1 of the 2 … not found)', (pg_temp.hide(array['b1', 'missing'], true) like 'ERR P0001:%1 of the 2 picked jobs were not found in this QuickBooks company — nothing was changed')::text, 'true');
  perform pg_temp.chk('H4b 중복 id → 예외(1 of the 2 … more than once)', (pg_temp.hide(array['b1', 'b1'], true) like 'ERR P0001:%1 of the 2 picked jobs are listed more than once — nothing was changed')::text, 'true');
  perform pg_temp.chk('H4c 빈 배열 · null 배열 → 예외(Pick at least one job)', (pg_temp.hide(array[]::text[], true) like 'ERR P0001:%Pick at least one job — nothing was changed')::text || ' ' || (pg_temp.bk('select public.qbo_job_hide(null, true)::text') like 'ERR P0001:%Pick at least one job — nothing was changed')::text, 'true true');
  perform pg_temp.chk('H4d 다른 realm 의 skipped → 예외(not found) · 그 줄 그대로 · unhide 도 같은 거부', (pg_temp.hide(array['x1'], true) like 'ERR P0001:%1 of the 1 picked jobs were not found%')::text || ' ' || (pg_temp.hide(array['x1'], false) like 'ERR P0001:%1 of the 1 picked jobs were not found%')::text || ' ' || pg_temp.job('x1'), 'true true skipped hidden=false by=- skip_at_kept=true upd_by=S');
  perform pg_temp.chk('H4e p_hide null → 예외 · 배열 안 null → 예외', (pg_temp.bk(format('select public.qbo_job_hide(array[%L]::uuid[], null)::text', pg_temp.id('b1'))) like 'ERR P0001:%nothing was changed')::text || ' ' || (pg_temp.bk(format('select public.qbo_job_hide(array[%L, null]::uuid[], true)::text', pg_temp.id('b1'))) like 'ERR P0001:%empty entry — nothing was changed')::text, 'true true');
  -- H10 blocked 자식이 기다리는 skipped 는 숨기기 거부(보충 이견 3) — 다른 것과 섞어도 전부 거부
  v := pg_temp.hide(array['b1', 'p1'], true);
  perform pg_temp.chk('H10 blocked 일감이 기다리는 skipped(p1) + 보통 skipped(b1) → 예외(1 of the 2 … waiting on them) · 둘 다 그대로', (v like 'ERR P0001:%1 of the 2 picked jobs still have other jobs waiting on them (blocked)%nothing was changed')::text || ' ' || pg_temp.job('p1') || ' | ' || pg_temp.job('b1'),
    'true skipped hidden=false by=- skip_at_kept=true upd_by=S | skipped hidden=false by=- skip_at_kept=true upd_by=S');
  -- H7 qbo:read 직원: 숨기기 거부 · 읽기(hidden 보기)는 된다
  perform pg_temp.chk('H7 qbo:read 직원 hide → 거부(qbo (write) permission) · b1 그대로 · 같은 직원의 list(hidden) 읽기는 된다',
    (pg_temp.hide(array['b1'], true, 'rd') like 'ERR P0001:%does not have the ''qbo'' (write) permission%')::text || ' ' || pg_temp.job('b1') || ' ' || pg_temp.rd(format('select (public.qbo_job_list(''hidden'', array[''customer''], %L::date))->>''total''', pg_temp.id('today'))),
    'true skipped hidden=false by=- skip_at_kept=true upd_by=S ' || (th0 + 3)::text);
  perform pg_temp.chk('H7b anon · service_role 은 창구를 못 부른다(42501)', left(pg_temp.as_conn('anon', '{"role":"anon"}'::jsonb, format('select public.qbo_job_hide(array[%L]::uuid[], true)::text', pg_temp.id('b1'))), 9) || ' ' || left(pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, format('select public.qbo_job_hide(array[%L]::uuid[], true)::text', pg_temp.id('b1'))), 9), 'ERR 42501 ERR 42501');
  -- H8 다른 보기에는 숨긴 줄 0
  perform pg_temp.chk('H8 list(null) − 3 · list(open) 그대로 · 숨긴 일감을 이름으로 찾으면 null · open · skipped 보기 0 · hidden 보기 1',
    pg_temp.ls(null, 'total') || ' ' || pg_temp.ls('open', 'total') || ' ' || pg_temp.ls(null, 'total', pg_temp.id('a1_ims')) || ' ' || pg_temp.ls('open', 'total', pg_temp.id('a1_ims')) || ' ' || pg_temp.ls('skipped', 'total', pg_temp.id('a1_ims')) || ' ' || pg_temp.ls('hidden', 'total', pg_temp.id('a1_ims')),
    (ta0 - 3)::text || ' ' || to0::text || ' 0 0 0 1');
  perform pg_temp.chk('H8b 모르는 상태 값 거부 글에 hidden', (pg_temp.ls('nope', 'total') like 'ERR P0001:%state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open, hidden (got nope)')::text, 'true');
  -- H5 숨긴 a1 을 Retry 로 되살림 → 숨김이 저절로 풀린다(판정 ⑤) · updated_by 는 되살린 사람(보통 update 는 touch 그대로)
  v := pg_temp.bk(format('select public.qbo_job_retry(%L, %L)::text', pg_temp.id('a1'), 'zz hide test: send after all'));
  perform pg_temp.chk('H5 retry(숨긴 a1) → queued · hidden 풀림 · updated_* 는 되살린 사람 · 지금 · list(hidden) − 1 · list(open) + 1', pg_temp.j(v, 'state') || ' | ' || pg_temp.job('a1') || ' | ' || pg_temp.ls('hidden', 'total') || ' ' || pg_temp.ls('open', 'total'),
    'queued | queued hidden=false by=- skip_at_kept=false upd_by=W | ' || (th0 + 2)::text || ' ' || (to0 + 1)::text);
  -- H5b 다른 길(직접 update 로 skipped → failed)로 벗어나도 풀린다 — 「어떤 길로든」
  v := pg_temp.try(format($q$ update public.qbo_job j set state = 'failed', last_error = 'zz hide test' where j.id = %L returning 'updated' $q$, pg_temp.id('a3')));
  perform pg_temp.chk('H5b 숨긴 a3 을 직접 update 로 failed → 숨김 풀림 · counts.hidden = 앞 + 1(a2 만 남음)', v || ' | ' || pg_temp.job('a3') || ' | ' || pg_temp.ls('skipped', 'counts.hidden'), 'updated | failed hidden=false by=- skip_at_kept=false upd_by=- | ' || (ch0 + 1)::text);
  -- H6 unhide
  perform pg_temp.chk('H6a unhide a2 → changed 1 · 다시 → changed 0 · already 1', pg_temp.j(pg_temp.hide(array['a2'], false)) || ' ' || pg_temp.j(pg_temp.hide(array['a2'], false)),
    jsonb_build_object('changed', 1, 'already', 0, 'hidden', false)::text || ' ' || jsonb_build_object('changed', 0, 'already', 1, 'hidden', false)::text);
  perform pg_temp.chk('H6b unhide 뒤: list(skipped) 에 다시(앞 − 2: a1 queued · a3 failed) · counts.hidden = 앞 · a2 의 updated_* 는 Skip 때 값 그대로', pg_temp.ls('skipped', 'total') || ' ' || pg_temp.ls('skipped', 'counts.hidden') || ' ' || pg_temp.ls('skipped', 'total', (select j.ims_id from public.qbo_job j where j.id = pg_temp.id('a2')::uuid)) || ' | ' || pg_temp.job('a2'),
    (ts0 - 2)::text || ' ' || ch0::text || ' 1 | skipped hidden=false by=- skip_at_kept=true upd_by=S');
  perform pg_temp.chk('H6c unhide 는 skipped 아닌 일감에도 예외 없이 already(q1)', pg_temp.j(pg_temp.hide(array['q1'], false)), jsonb_build_object('changed', 0, 'already', 1, 'hidden', false)::text);
  -- H9 CHECK — 직접 넣기 거부(트리거가 조용히 고치지 않는다 · 보충 이견 2)
  perform pg_temp.chk('H9 queued 줄에 hidden 두 칸 직접 → 23514 · skipped 줄에 hidden_at 만(hidden_by 없이) → 23514 · insert 로 queued + hidden → 23514',
    left(pg_temp.try(format($q$ update public.qbo_job j set hidden_at = now(), hidden_by = %L where j.id = %L returning 'updated' $q$, pg_temp.id('W'), pg_temp.id('q1'))), 9) || ' ' ||
    left(pg_temp.try(format($q$ update public.qbo_job j set hidden_at = now() where j.id = %L returning 'updated' $q$, pg_temp.id('b1'))), 9) || ' ' ||
    left(pg_temp.try(format($q$ insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, hidden_at, hidden_by) values (%L, 'customer', 'customer', gen_random_uuid()::text, 'queued', now(), %L) returning 'inserted' $q$, pg_temp.id('realm'), pg_temp.id('W'))), 9),
    'ERR 23514 ERR 23514 ERR 23514');
  -- H11 트리거가 보통 update 의 touch 를 막지 않는다(숨기지 않은 b1 의 note 만 고침 → updated_at 이 바뀐다)
  v := pg_temp.try(format($q$ update public.qbo_job j set note = j.note || ' (edited)' where j.id = %L returning 'updated' $q$, pg_temp.id('b1')));
  perform pg_temp.chk('H11 보통 update(note)는 updated_at 이 그대로 바뀐다(ims_touch 무변)', v || ' | ' || pg_temp.job('b1'), 'updated | skipped hidden=false by=- skip_at_kept=false upd_by=-');
  -- T1 새 목록 시간('blocked' 두 번 중 빠른 쪽) — 앞(옛 판)의 1.5 배 + 300 ms 안
  v_ms := least(pg_temp.ms($q$ select (public.qbo_job_list('blocked'))->>'total' $q$), pg_temp.ms($q$ select (public.qbo_job_list('blocked'))->>'total' $q$));
  perform pg_temp.put('ms_post', v_ms::text);
  perform pg_temp.chk('T1 qbo_job_list(blocked) 실행 시간이 크게 늘지 않았다(뒤 ≤ 앞 × 1.5 + 300 ms) — 값은 아래 줄', (v_ms <= pg_temp.id('ms_pre')::numeric * 1.5 + 300)::text, 'true');
end $$;

-- ── 구조 · 정적 검사(한 문장)
select
  pg_temp.chk('S1 칸 둘(hidden_at timestamptz · hidden_by uuid · 둘 다 null 허용)', pg_temp.try($q$ select string_agg(column_name || ':' || data_type || ':' || is_nullable, ',' order by column_name) from information_schema.columns where table_schema = 'public' and table_name = 'qbo_job' and column_name in ('hidden_at', 'hidden_by') $q$), 'hidden_at:timestamp with time zone:YES,hidden_by:uuid:YES'),
  pg_temp.chk('S2 CHECK qbo_job_hidden_only_skipped_ck · hidden_by FK → ims_staff', pg_temp.try($q$ select (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.qbo_job'::regclass and c.conname = 'qbo_job_hidden_only_skipped_ck') || ' | ' || (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.qbo_job'::regclass and c.conname = 'qbo_job_hidden_by_fkey') $q$),
    'CHECK ((((hidden_at IS NULL) OR (state = ''skipped''::text)) AND ((hidden_at IS NULL) = (hidden_by IS NULL)))) | FOREIGN KEY (hidden_by) REFERENCES ims_staff(id)'),
  pg_temp.chk('S3 트리거: BEFORE UPDATE 둘 · 이름 순 qbo_job_touch → qbo_job_touch_hidden · WHEN 그대로', pg_temp.try($q$ select string_agg(t.tgname, ',' order by t.tgname) || ' | ' || (select pg_get_triggerdef(t2.oid) from pg_trigger t2 where t2.tgrelid = 'public.qbo_job'::regclass and t2.tgname = 'qbo_job_touch_hidden') from pg_trigger t where t.tgrelid = 'public.qbo_job'::regclass and not t.tgisinternal and t.tgtype & 2 = 2 $q$),
    'qbo_job_touch,qbo_job_touch_hidden | CREATE TRIGGER qbo_job_touch_hidden BEFORE UPDATE ON public.qbo_job FOR EACH ROW WHEN (((old.hidden_at IS DISTINCT FROM new.hidden_at) OR ((old.hidden_at IS NOT NULL) AND (new.state <> ''skipped''::text)))) EXECUTE FUNCTION qbo_job_touch_hidden()'),
  pg_temp.chk('S4 창구 grant: qbo_job_hide = authenticated 만 · definer · search_path · 트리거 함수 grant 0', pg_temp.try($q$ select (select p.proacl::text || ' ' || p.prosecdef::text || ' ' || p.proconfig::text from pg_proc p where p.oid = 'public.qbo_job_hide(uuid[], boolean)'::regprocedure) || ' | ' || (select p.proacl::text from pg_proc p where p.oid = 'public.qbo_job_touch_hidden()'::regprocedure) $q$),
    '{postgres=X/postgres,authenticated=X/postgres} true {"search_path=public, pg_temp"} | {postgres=X/postgres}'),
  pg_temp.chk('S5 qbo_job_list 재발행 md5 · 같은 이름 하나 · ACL 그대로', (select md5(p.prosrc) || ' ' || p.proacl::text || ' ' || (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = 'qbo_job_list')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_job_list'),
    pg_temp.id('new_list_md5') || ' {postgres=X/postgres,authenticated=X/postgres} 1'),
  pg_temp.chk('S6 실제 일감 중 숨긴 것 0(가짜 제외)', pg_temp.try($q$ select count(*)::text from public.qbo_job j where j.hidden_at is not null and j.id::text not in (select v from t_ids) $q$), '0'),
  pg_temp.chk('R1 REST 겹 ① — 새 · 재발행 함수의 깊이 0 WHERE 없는 update · delete = 0(qbo_job_hide · qbo_job_list · qbo_job_touch_hidden) · hide 의 update 문장 수 2', pg_temp.try($q$ select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc)::text, ',' order by p.proname) || ' ' || (select count(*) from regexp_matches((select q.prosrc from pg_proc q where q.proname = 'qbo_job_hide' and q.pronamespace = 'public'::regnamespace), '\mupdate public\.qbo_job\M', 'g'))::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_job_hide', 'qbo_job_list', 'qbo_job_touch_hidden') $q$),
    'qbo_job_hide=0,qbo_job_list=0,qbo_job_touch_hidden=0 2');
\if :{?mig}
select pg_temp.chk('G1(시험 갈래) begin 앞과 md5 가 다른 qbo_ 함수 = qbo_job_list 하나(옛 a853b47b…) · 새 qbo_ 함수 = 둘(qbo_job_hide · qbo_job_touch_hidden)',
  (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5) || ' ' || :'pre_list_md5' || ' ' ||
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%' and p.proname not in (select proname from t_pre)),
  'qbo_job_list a853b47b76e899e44ebbb270779e2a26 qbo_job_hide,qbo_job_touch_hidden');
\else
select pg_temp.chk('G1(확인 갈래) begin 앞과 md5 가 다른 qbo_ 함수 없음 · 새 함수 없음(이미 적용)',
  (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5) || ' ' ||
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%' and p.proname not in (select proname from t_pre)), '(none) (none)');
\endif

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(가짜 행은 rollback) ──'
select n, case when ok then 'OK  ' else 'FAIL' end as r, label, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' · want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, (count(*) filter (where not ok) > 0 or count(*) filter (where ok) <> :EXPECT_OK) as bad from t_res \gset
\echo 'OK' :ok '· FAIL' :fail '· total' :total '· expect_ok' :EXPECT_OK
select pg_temp.id('ms_pre') as t1_blocked_ms_before, pg_temp.id('ms_post') as t1_blocked_ms_after, round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 and (select count(*) from public.qbo_job) = :n_job0
   and (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_job_list') = :'pre_list_md5'
   and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%') = :n_fn as rolled_back_clean;
\if :bad
do $$ begin raise exception 'qbo_hide_1_check: FAIL or OK count differs from EXPECT_OK — see the result table above'; end $$;
\endif
