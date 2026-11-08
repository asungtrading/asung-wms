-- supabase/tests/perf_bo_1_check.sql — perf-bo-1 inv_receipt_events sku 조건 두 갈래(키 갈래 OR 없이 · 전체 갈래 옛 줄 그대로) — 검증 (2026-11-08)
-- [메인 IMS · Asung-IMS] 시험 적용 장치 틀 — 옛 기준은 **begin 앞**(잠금 없음 · 이견 답 6 · 잠금 규칙 ①): 파일 속 옛 몸 글자 그대로 pg_temp.ire_old(SET 포함 · 인라인 안 됨 · md5 56ecce6e…) 로
--   열린 백오더 (sku, 창고) 쌍 전부 × {fill 길(오늘−30 · null) · overview 길(null · null)} + null 갈래 {두 창고 최근 30 일 · 전부 null} 을 임시 표에 → begin → (-v mig 면 \i) → 새 함수 같은 입력 → 집합 차 0 → rollback
--   G0 머리(시험 갈래만: DB 옛 md5 56ecce6e… · 적용 뒤 md5 바뀜) · G1 ① 같은 입력 → 같은 출력(네 묶음 · old except new · new except old · 행 수) · G2 ② 속도(키 갈래 일반 계획 explain — sku 색인 · ms ·
--   so_backorder_ready 기본 거르기 직원 신원 × 3 · 8 s 안 · arrivals 한 번 숫자만) · G3 ③ 착지(속성 · acl · comment · 과부하 · 시그니처 · 반환 · 새 몸 − 갈래 = 옛 md5) · G4 REST 두 겹 ①(update · delete 0 — 읽기 함수 · 해당 없음)
--   가짜 직원 신원: set local role authenticated + request.jwt.claims(활성 admin) + statement_timeout 8 s(set role 은 rolconfig 를 안 싣는다 · 이견 답 7) · 쓰기 0 · 시퀀스 무관(setval 없음)
--   회차 2(까닭): 회차 1 은 26/26 인데 begin ~ rollback 21 s — 트랜잭션 안 문장 ≈ 60 × 왕복 0.3 s(so §101-c 9) ⇒ 도우미 · 임시 표 · psql 변수(t_vars)는 begin 앞 · 검사는 DO 하나 · ready 넷은 함수 하나(안에서 set local role → reset role) · 트랜잭션 안 ≈ 13 문장
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261108075000_perf_bo_1_ire_sku_branches.sql -f supabase/tests/perf_bo_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 옛 = 파일 속 옛 몸 · 새 = DB 라 동치 검사는 그대로 뜻이 있다 · G0 둘은 시험 갈래만
--   기대 OK: 시험(-v mig) 26 · 확인(적용 뒤) 24 (G0 둘은 시험 갈래만 · 호출 줄 셈: G1 10 · G2 6 · G3 7 · G4 1) · MISMATCH 0 · begin ~ rollback 10 초 안(넘으면 보고)
--   마른 실행(적용 전 · -v mig 없음 · 결함 재현): OK 12 · MISMATCH 12 = G1 다섯(쌍 묶음 둘 건너뜀 · rows 0 ≠ old) + G2 explain 둘(옛 몸은 Bitmap Heap Scan · 갈래 없음) + ready 넷(#1 statement_timeout 8 s 를 잡아 99999 ms · #2 · #3 건너뜀) + G3 strip(markers missing)
--     · 마른 실행의 begin ~ rollback 은 ready timeout 8 s 때문에 ≈ 12 s — \i 가 없어 DDL 잠금은 0(AccessShare 읽기만) · 적용 뒤 확인 실행은 10 초 안
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 26
\set has_mig 1
\else
\set EXPECT_OK 24
\set has_mig 0
\endif
\pset pager off
-- ── 기준 머리(begin 앞 · 읽기만) ──
select (select s.auth_user_id::text from public.ims_staff s where s.is_active and s.role = 'admin' and s.auth_user_id is not null order by s.created_at limit 1) as staff_uid,
       public.ims_today()::text as today,
       (select max(id) from public.inv_ledger) as fp_led_max, (select count(*) from public.inv_ledger) as fp_led_n,
       (select md5(prosrc) from pg_proc where oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure) as md5_before,
       (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '-') || (select l.lanname from pg_language l where l.oid = p.prolang) || ' ' || p.proowner::regrole::text || ' ' || pg_get_function_identity_arguments(p.oid) || ' → ' || pg_get_function_result(p.oid)
          from pg_proc p where p.oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure) as attrs_before,
       (select proacl::text from pg_proc where oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure) as acl_before \gset
\echo '── 기준: today' :today '· ledger max' :fp_led_max '· rows' :fp_led_n '· md5 before' :md5_before '· staff' :staff_uid
\echo '── attrs before:' :attrs_before
-- ── 옛 몸(begin 앞 · 잠금 없음) — 20261015015435_bo_2_arrivals_waiting.sql 41 ~ 50 행 글자 그대로 · SET 포함(인라인 안 됨 · 옛과 같은 일반 계획) ──
create function pg_temp.ire_old(p_sku text default null, p_warehouse text default null, p_from date default null, p_to date default null)
  returns table (ledger_id bigint, sku text, warehouse text, occurred_on date, kind text, doc_number text, qty_delta numeric, raw jsonb)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select g.id, g.sku, g.warehouse, g.occurred_on, g.event_type, g.doc_number, g.qty_delta, g.raw
  from public.inv_ledger g
  where (p_sku is null or g.sku = p_sku) and (p_warehouse is null or g.warehouse = p_warehouse)
    and (p_from is null or g.occurred_on >= p_from) and (p_to is null or g.occurred_on <= p_to)
    and g.qty_delta > 0
    and (g.event_type = 'po_in'
         or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
             and exists (select 1 from public.inv_ledger o
                         where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                           and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
$$;
-- 열린 백오더의 (sku, 창고) 쌍 — fill 의 share(need_sku · location) 와 같은 재료(열린 backorder 예약 · 오더 창고)
create temp table t_pairs as
  select distinct p.sku, w.name as wh
  from public.so_reserve r join public.so_line l on l.id = r.so_line_id join public.so s on s.id = l.so_id
  join public.product p on p.id = l.product_id join public.ref_warehouse w on w.id = s.location_id
  where r.kind = 'backorder' and r.released_at is null;
create temp table t_old (grp text, k_sku text, k_wh text, ledger_id bigint, sku text, warehouse text, occurred_on date, kind text, doc_number text, qty_delta numeric, raw jsonb);
select clock_timestamp() as t_old0 \gset
insert into t_old select 'G1a fill (sku, wh, today-30, null)', p.sku, p.wh, e.* from t_pairs p cross join lateral pg_temp.ire_old(p.sku, p.wh, :'today'::date - 30, null) e;
insert into t_old select 'G1b overview (sku, wh, null, null)', p.sku, p.wh, e.* from t_pairs p cross join lateral pg_temp.ire_old(p.sku, p.wh, null, null) e;
insert into t_old select 'G1c arrivals (null, wh, today-30, today)', null, v.w, e.* from (values ('Asung Trading Inc.'), ('Asung - Edmonton')) v(w) cross join lateral pg_temp.ire_old(null, v.w, :'today'::date - 30, :'today'::date) e;
insert into t_old select 'G1d all (null, null, null, null)', null, null, e.* from pg_temp.ire_old(null, null, null, null) e;
select clock_timestamp() as t_old1 \gset
\echo '── 옛 기준(begin 앞): 걸린 시간 아래'
select grp, count(*) as rows_old, count(distinct (k_sku, k_wh)) as keys from t_old group by grp order by grp;
select (select count(*) from t_pairs) as n_pairs, round(extract(epoch from (:'t_old1'::timestamptz - :'t_old0'::timestamptz))::numeric, 2) as old_capture_s;
-- ── 도우미 · 임시 표 · psql 변수(begin 앞 · 잠금 없음 — 트랜잭션 안 왕복을 줄인다) ──
create temp table t_vars as
  select :'today'::date as today, :'md5_before'::text as md5_before, :'attrs_before'::text as attrs_before, :'acl_before'::text as acl_before, :'staff_uid'::text as staff_uid, :has_mig::int as has_mig,
         (select count(*) from t_pairs) as n_pairs, (select p.sku from t_pairs p order by p.sku, p.wh limit 1) as k_sku, (select p.wh from t_pairs p order by p.sku, p.wh limit 1) as k_wh;
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create temp table t_new (like t_old);
create temp table t_x (name text, plan text);
create temp table t_g1 (grp text, old_minus_new bigint, new_minus_old bigint, rows_old bigint, rows_new bigint);
create temp table t_t (name text, ms numeric);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.xplain(p_sql text) returns text language plpgsql as $$
declare r record; s text := '';
begin
  for r in execute 'explain (analyze, buffers, summary on) ' || p_sql loop s := s || r."QUERY PLAN" || E'\n'; end loop;
  return s;
end $$;
create function pg_temp.strip_new(p_src text) returns text language plpgsql as $$
declare v_lines text[] := string_to_array(p_src, E'\n'); v_i int; v_k3 int; v_k4 int; v_rest text[] := '{}';
begin
  for v_i in 1 .. array_length(v_lines, 1) loop
    if v_lines[v_i] like '  union all%-- perf-bo-1%' then v_k3 := v_i; end if;
    if v_lines[v_i] like '    and p_sku is null %-- perf-bo-1%' then v_k4 := v_i; end if;
  end loop;
  if v_k3 is null or v_k4 is null then return 'markers missing'; end if;
  for v_i in 1 .. array_length(v_lines, 1) loop
    if (v_i >= 2 and v_i <= v_k3) or v_i = v_k4 then continue; end if;
    v_rest := v_rest || v_lines[v_i];
  end loop;
  return md5(array_to_string(v_rest, E'\n'));
end $$;
create function pg_temp.call_ms(p_fn text, p_f jsonb) returns text language plpgsql as $$
declare t0 timestamptz := clock_timestamp(); j jsonb;
begin
  if p_fn = 'ready' then j := public.so_backorder_ready(p_f); else j := public.so_backorder_arrivals(p_f); end if;
  return round(extract(epoch from (clock_timestamp() - t0)) * 1000)::text || ' ms · total ' || coalesce(j->>'total', '?') || ' · rows ' || coalesce(jsonb_array_length(j->'rows')::text, '?');
end $$;
-- 직원 신원으로 ready × 3 · arrivals × 1 — 한 문장(안에서 set local role → reset role · 결과는 reset 뒤 t_res · t_t 에)
create function pg_temp.ready_all() returns text language plpgsql as $$
declare v_uid text; v_r1 text; v_r2 text; v_r3 text; v_a1 text;
begin
  select staff_uid into v_uid from t_vars;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_uid, true), set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  -- 회차 3: 마른 실행(적용 전 · -v mig 없음)에서 옛 함수의 8 s timeout 을 잡아 MISMATCH 로 남긴다(ON_ERROR_STOP 으로 죽지 않게) · 시한은 문장당 한 번이라 첫 timeout 뒤 나머지 ready 는 건너뛴다(잠금 10 초)
  begin
    v_r1 := pg_temp.call_ms('ready', '{"limit":100}'::jsonb);
    v_r2 := pg_temp.call_ms('ready', '{"limit":100}'::jsonb);
    v_r3 := pg_temp.call_ms('ready', '{"limit":100}'::jsonb);
  exception when query_canceled then
    v_r1 := coalesce(v_r1, '99999 ms · total timeout(statement_timeout 8s) · rows ?');
    v_r2 := coalesce(v_r2, '99998 ms · skipped after timeout #2 · rows ?');
    v_r3 := coalesce(v_r3, '99997 ms · skipped after timeout #3 · rows ?');
  end;
  v_a1 := pg_temp.call_ms('arrivals', '{"limit":100}'::jsonb);
  execute 'reset role';
  perform pg_temp.chk('G2 ready #1 < 8000 ms (staff · default filter) — ' || v_r1, (split_part(v_r1, ' ', 1)::int < 8000)::text, 'true');
  perform pg_temp.chk('G2 ready #2 < 8000 ms — ' || v_r2, (split_part(v_r2, ' ', 1)::int < 8000)::text, 'true');
  perform pg_temp.chk('G2 ready #3 < 8000 ms — ' || v_r3, (split_part(v_r3, ' ', 1)::int < 8000)::text, 'true');
  perform pg_temp.chk('G2 ready #1 = #2 = #3 total (same answer thrice)', (split_part(v_r1, '·', 2) = split_part(v_r2, '·', 2) and split_part(v_r2, '·', 2) = split_part(v_r3, '·', 2))::text, 'true');
  insert into t_t values ('ready #1', split_part(v_r1, ' ', 1)::numeric), ('ready #2', split_part(v_r2, ' ', 1)::numeric), ('ready #3', split_part(v_r3, ' ', 1)::numeric), ('arrivals #1', split_part(v_a1, ' ', 1)::numeric);
  return 'ready ' || v_r1 || ' | ' || v_r2 || ' | ' || v_r3 || ' · arrivals ' || v_a1;
end $$;
begin;
select set_config('lock_timeout', '3s', true), set_config('statement_timeout', '30s', true), clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
-- ── G0 · G1 · G2(키 갈래 explain) · G3 · G4 — DO 하나(왕복 1) ──
do $$
declare v t_vars%rowtype; v_t0 timestamptz; v_sql text; v_md5_now text; v_g record;
begin
  select * into v from t_vars;
  insert into t_t values ('t_mig(epoch)', extract(epoch from clock_timestamp()));
  v_md5_now := (select md5(prosrc) from pg_proc where oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure);
  -- G0(시험 갈래만)
  if v.has_mig = 1 then
    perform pg_temp.chk('G0 DB body before mig = bo-2 old md5 56ecce6e…', v.md5_before, '56ecce6e032d6b09c9d67ebf8d671a00');
    perform pg_temp.chk('G0 DB body changed by mig', (v_md5_now <> v.md5_before)::text, 'true');
  end if;
  -- G1 ① 같은 입력 → 같은 출력
  -- 회차 4: 마른 실행(-v mig 없음 · DB 몸이 아직 옛 56ecce6e…)에서는 쌍 묶음 둘을 건너뛴다 — 옛 함수 332 쌍 × 2 ≈ 32 s 라 statement_timeout 30 s · 잠금 10 초를 넘는다 · 건너뛴 묶음은 rows 0 → MISMATCH 로 남는다(적용 뒤 확인 실행은 전부 돈다)
  v_t0 := clock_timestamp();
  if not (v.has_mig = 0 and v_md5_now = '56ecce6e032d6b09c9d67ebf8d671a00') then
    insert into t_new select 'G1a fill (sku, wh, today-30, null)', p.sku, p.wh, e.* from t_pairs p cross join lateral public.inv_receipt_events(p.sku, p.wh, v.today - 30, null) e;
    insert into t_new select 'G1b overview (sku, wh, null, null)', p.sku, p.wh, e.* from t_pairs p cross join lateral public.inv_receipt_events(p.sku, p.wh, null, null) e;
  else
    insert into t_t values ('G1a · G1b skipped: dry run on old body', 0);
  end if;
  insert into t_new select 'G1c arrivals (null, wh, today-30, today)', null, w.w, e.* from (values ('Asung Trading Inc.'), ('Asung - Edmonton')) w(w) cross join lateral public.inv_receipt_events(null, w.w, v.today - 30, v.today) e;
  insert into t_new select 'G1d all (null, null, null, null)', null, null, e.* from public.inv_receipt_events(null, null, null, null) e;
  insert into t_t values ('new capture (4 groups)', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000, 1));
  insert into t_g1
    select g.grp,
           (select count(*) from (select * from t_old o where o.grp = g.grp except all select * from t_new n where n.grp = g.grp) x),
           (select count(*) from (select * from t_new n where n.grp = g.grp except all select * from t_old o where o.grp = g.grp) x),
           (select count(*) from t_old o where o.grp = g.grp),
           (select count(*) from t_new n where n.grp = g.grp)
    from (select distinct grp from t_old) g;
  for v_g in select * from t_g1 order by grp loop
    perform pg_temp.chk(v_g.grp || ' · old∖new + new∖old = 0 (rows ' || v_g.rows_old || ')', (v_g.old_minus_new + v_g.new_minus_old)::text, '0');
  end loop;
  for v_g in select * from t_g1 order by grp loop
    perform pg_temp.chk(v_g.grp || ' · rows old = new', v_g.rows_new::text, v_g.rows_old::text);
  end loop;
  perform pg_temp.chk('G1 pairs > 0 and G1a has arrived rows (fill 길 비어 있지 않음)', (v.n_pairs > 0 and (select rows_new from t_g1 where grp like 'G1a%') > 0)::text, 'true');
  perform pg_temp.chk('G1 four groups captured', (select count(*)::text from t_g1), '4');
  -- G2 키 갈래 한 번 — 함수 속과 같은 일반 계획(prepare + force_generic_plan) · sku 색인 · 다른 갈래 never executed
  v_sql := (select prosrc from pg_proc where oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure);
  v_sql := regexp_replace(v_sql, '\mp_sku\M', '$1', 'g');
  v_sql := regexp_replace(v_sql, '\mp_warehouse\M', '$2', 'g');
  v_sql := regexp_replace(v_sql, '\mp_from\M', '$3', 'g');
  v_sql := regexp_replace(v_sql, '\mp_to\M', '$4', 'g');
  execute 'prepare pb_ire(text, text, date, date) as ' || v_sql;
  execute 'set local plan_cache_mode = force_generic_plan';
  insert into t_x select 'key branch (' || v.k_sku || ', ' || v.k_wh || ', today-30, null)', pg_temp.xplain(format('execute pb_ire(%L, %L, %L::date - 30, null)', v.k_sku, v.k_wh, v.today));
  insert into t_x select 'null branch (null, Asung Trading Inc., today-30, today)', pg_temp.xplain(format('execute pb_ire(null, %L, %L::date - 30, %L::date)', 'Asung Trading Inc.', v.today, v.today));
  execute 'reset plan_cache_mode';
  -- 회차 3: 옛 몸의 SubPlan 도 같은 색인을 타므로(sku = g.sku) 키 갈래 고유의 줄로 — Index Cond (sku = $1) · 전체 갈래 One-Time Filter ($1 IS NULL) 뒤 never executed
  perform pg_temp.chk('G2 key branch generic plan: Index Scan inv_ledger_sku_wh_on_idx · Index Cond (sku = $1)', (select (plan ~ 'Index Scan using inv_ledger_sku_wh_on_idx on inv_ledger g\s' and plan ~ 'Index Cond: \(sku = \$1\)')::text from t_x where name like 'key branch%'), 'true');
  perform pg_temp.chk('G2 key branch: full branch gated One-Time Filter ($1 IS NULL) · never executed', (select (plan ~ 'One-Time Filter: \(\$1 IS NULL\)\s+->\s+Bitmap Heap Scan on inv_ledger g_1 .*\(never executed\)')::text from t_x where name like 'key branch%'), 'true');
  insert into t_t select 'explain ' || name || ' (Execution Time ms)', (regexp_match(plan, 'Execution Time: ([0-9.]+) ms'))[1]::numeric from t_x;
  -- G3 ③ 착지
  perform pg_temp.chk('G3 attrs (volatile · secdef · search_path · lang · owner · signature · result) before = after',
       (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '-') || (select l.lanname from pg_language l where l.oid = p.prolang) || ' ' || p.proowner::regrole::text || ' ' || pg_get_function_identity_arguments(p.oid) || ' → ' || pg_get_function_result(p.oid)
          from pg_proc p where p.oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure), v.attrs_before);
  perform pg_temp.chk('G3 acl before = after', (select proacl::text from pg_proc where oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure), v.acl_before);
  perform pg_temp.chk('G3 acl: authenticated yes · service_role yes · anon no',
       (has_function_privilege('authenticated', 'public.inv_receipt_events(text, text, date, date)', 'execute') and has_function_privilege('service_role', 'public.inv_receipt_events(text, text, date, date)', 'execute') and not has_function_privilege('anon', 'public.inv_receipt_events(text, text, date, date)', 'execute'))::text, 'true');
  perform pg_temp.chk('G3 comment md5 unchanged 7b42f833…', md5(coalesce(obj_description('public.inv_receipt_events(text, text, date, date)'::regprocedure, 'pg_proc'), '')), '7b42f83364e403585d06fe40a86823bc');
  perform pg_temp.chk('G3 overloads = 1', (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_receipt_events'), '1');
  perform pg_temp.chk('G3 new body minus key branch & gate = old body md5 56ecce6e…', pg_temp.strip_new((select prosrc from pg_proc where oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure)), '56ecce6e032d6b09c9d67ebf8d671a00');
  perform pg_temp.chk('G3 file-literal old body (pg_temp.ire_old) md5 = 56ecce6e…', (select md5(prosrc) from pg_proc where oid = 'pg_temp.ire_old(text, text, date, date)'::regprocedure), '56ecce6e032d6b09c9d67ebf8d671a00');
  -- G4 REST 두 겹 ① — 깊이 0 update · delete 0(읽기 함수 · 해당 없음)
  perform pg_temp.chk('G4 update/delete statements in body = 0 (해당 없음)', (select count(*)::text from regexp_matches((select prosrc from pg_proc where oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure), '^\s*(update|delete)\s', 'gn')), '0');
  insert into t_x values ('md5 in txn', v_md5_now);
end $$;
-- ── G2 ② ready × 3 · arrivals × 1 — 직원 신원 · statement_timeout 8 s(문장 하나 · 넷 합이 8 s 안이면 각각도 안) ──
set local statement_timeout = '8s';
select pg_temp.ready_all() as ready_all \gset
set local statement_timeout = '30s';
-- ═══ 결과(rollback 앞) ═══
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || left(coalesce(got, '(null)'), 300) || ' | want=' || left(coalesce(want, '(null)'), 300) end as detail from t_res order by n;
select * from t_g1 order by grp;
select name, plan from t_x where name <> 'md5 in txn' order by name desc;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_bad, count(*) as n_all,
       (select plan from t_x where name = 'md5 in txn') as md5_in_txn,
       (select ms from t_t where name = 't_mig(epoch)') as t_mig_epoch,
       (select string_agg(name || ' ' || ms, ' | ' order by name) from t_t where name not in ('t_mig(epoch)', 'md5 in txn')) as times,
       clock_timestamp() as t_end from t_res \gset
rollback;
select (select max(id) from public.inv_ledger) = :fp_led_max and (select count(*) from public.inv_ledger) = :fp_led_n as z_fingerprint_same_as_start,
       (select md5(prosrc) from pg_proc where oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure) as z_ire_md5_after,
       :'md5_in_txn' as z_ire_md5_in_txn,
       round(extract(epoch from (:'t_old1'::timestamptz - :'t_old0'::timestamptz))::numeric, 2) as old_capture_before_begin_s,
       round((extract(epoch from :'t_end'::timestamptz) - :t_mig_epoch)::numeric, 2) as mig_to_rollback_s,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_begin'::timestamptz))::numeric, 2) as begin_to_rollback_s;
\echo '── 시간(ms):' :times
\echo '── ' :ready_all
\echo '── 결과: OK' :n_ok '· MISMATCH' :n_bad '· 전체' :n_all '· 기대 OK' :EXPECT_OK
\if :{?mig}
\echo '   (시험 갈래 · 적용은 rollback 됨 · z_ire_md5_after 는 옛 56ecce6e… · z_ire_md5_in_txn 이 새 값 = 적용 명령 if 의 md5)'
\else
\echo '   (확인 갈래 · z_ire_md5_after = z_ire_md5_in_txn = 새 값)'
\endif
