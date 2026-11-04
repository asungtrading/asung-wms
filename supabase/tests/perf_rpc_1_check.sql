-- supabase/tests/perf_rpc_1_check.sql — perf-rpc-1 inv_available_base bal 두 갈래(키 갈래 OR 없이 · 창고 전체 갈래 옛 줄 그대로) — 검증 (2026-11-04)
-- [메인 IMS · Asung-IMS] 시험 적용 장치 틀 — 기준값은 적용 전에 **같은 트랜잭션**에서: begin → 옛 함수 반환을 임시 표에(phase old) → (-v mig 면 \i) → 새 반환(phase new) → 견줌 → rollback
--   G1 전수 동치(모든 재고 키 12,8xx 배열 한 번에 × 두 창고) · G2 화면 크기(1 · 63 · 120 덩이 합집합 = G1 옛) · G3 가장자리(빈 배열 · 중복 · 없는 pid · 스냅샷만 · 원장만 · 둘 다 없음 · 콤보 · 세트 · 섞음)
--   G4 null 길(두 창고 옛 = 새 · 재발행 본문에서 키 갈래 · 문 한 줄을 빼면 옛 본문 md5 3cacac31…) · G5 겉 창구(so_available_many · so_lines_available · shop_stock_payload · 가짜 직원 신원)
--   G6 속성(prosecdef · proconfig · provolatile · 서명 · 반환 · acl · 소유자 · comment md5 3e4be82f…) · G7 REST 두 겹 ①(update · delete 0) · G8 시간(SO-21021 꼴 63 키 → Edmonton · explain analyze 옛 · 새 — 보고)
--   가짜 직원 신원: set local role authenticated + request.jwt.claims(활성 admin) · 결과는 set_config 로 내보내고 reset role 뒤 임시 표에 · 쓰기 0 · 실제 행은 잠그지 않는다(lock_timeout 5s)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261104205654_perf_rpc_1_iab_bal_branches.sql -f supabase/tests/perf_rpc_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 옛 = 새 가 같은 함수라 동치 검사는 0 차이로 지나가고, G4b · G6 comment · G7 이 새 본문을 본다
--   기대 OK: 시험(-v mig) 42 · 확인(적용 뒤) 41 (G4c 옛 본문 md5 는 시험 갈래만 · 회차 3 실측 42/42) · MISMATCH 0 · 회차 전체 60 초를 넘으면 멈추고 보고(statement_timeout 30s)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 42
\else
\set EXPECT_OK 41
\endif
\pset pager off
-- ── 기준 머리(begin 앞 · 읽기만) ──
select (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1, (select id::text from public.ref_warehouse where name = 'Asung - Edmonton') as wh2,
       (select s.auth_user_id::text from public.ims_staff s where s.is_active and s.role = 'admin' and s.auth_user_id is not null order by s.created_at limit 1) as staff_uid,
       (select id::text from public.so where so_number = 'SO-21021') as so_a,
       (select s.id::text from public.so s where s.status = 'draft' and s.location_id is not null and exists (select 1 from public.so_line l where l.so_id = s.id) order by s.so_number desc limit 1) as so_draft,
       (select id::text from public.product where sku = 'AAL10925') as k_snap_only, (select id::text from public.product where sku = 'APR16008') as k_ledger_only,
       (select id::text from public.product where sku = '_13944_') as k_neither, (select id::text from public.product where sku = 'CB-CVT18157') as k_combo,
       (select id::text from public.product where sku = 'AAA07391-6') as k_set,
       (select max(id) from public.inv_ledger) as fp_led_max, (select count(*) from public.inv_ledger) as fp_led_n, (select count(*) from public.inv_snapshot) as fp_snap_n \gset
\echo '── 기준: ledger max' :fp_led_max '· rows' :fp_led_n '· snapshot' :fp_snap_n '· staff' :staff_uid '· SO-21021' :so_a '· draft' :so_draft
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
select clock_timestamp() as t_begin \gset
-- ── 도우미 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create temp table t_av (phase text, grp text, wh uuid, stock_pid uuid, qty_ea numeric, sales_alloc_ea numeric, transfer_alloc_ea numeric, bgrade_ea numeric);
create temp table t_ms (phase text, name text, ms numeric, rows int);
create function pg_temp.cap(p_phase text, p_grp text, p_wh uuid, p_pids uuid[]) returns int language plpgsql as $$
declare t0 timestamptz := clock_timestamp(); n int;
begin
  insert into t_av select p_phase, p_grp, p_wh, b.* from public.inv_available_base(p_wh, p_pids) b;
  get diagnostics n = row_count;
  insert into t_ms values (p_phase, p_grp || ' ' || left(p_wh::text, 8), round(extract(epoch from clock_timestamp() - t0) * 1000, 1), n);
  return n;
end $$;
create function pg_temp.chunks(p_phase text, p_wh uuid, p_size int, p_pids uuid[]) returns int language plpgsql as $$
declare i int := 1; n int := 0; tot int := 0; t0 timestamptz := clock_timestamp(); calls int := 0;
begin
  while i <= cardinality(p_pids) loop
    insert into t_av select p_phase, 'G2-' || p_size, p_wh, b.* from public.inv_available_base(p_wh, p_pids[i : i + p_size - 1]) b;
    get diagnostics n = row_count; tot := tot + n; i := i + p_size; calls := calls + 1;
  end loop;
  insert into t_ms values (p_phase, 'G2-' || p_size || ' x' || calls || ' ' || left(p_wh::text, 8), round(extract(epoch from clock_timestamp() - t0) * 1000, 1), tot);
  return tot;
end $$;
create function pg_temp.xplain(p_sql text) returns text language plpgsql as $$
declare r record; s text := '';
begin
  for r in execute 'explain (analyze, buffers, summary on) ' || p_sql loop s := s || r."QUERY PLAN" || E'\n'; end loop;
  return s;
end $$;
create temp table t_j (phase text, name text, res text);
create temp table t_x (phase text, plan text);
create temp table t_src (phase text, src text, attrs text, comment_md5 text);
-- 키 집합: 모든 재고 키(활성 · 비활성 · 낱개 = 세트의 parent) · 화면 크기 표본 120(SO-21021 의 63 키 + Edmonton 잔고 있는 키 57) · 63(SO-21021)
create temp table t_keys as select distinct coalesce(p.parent_product_id, p.id) as pid from public.product p;
create temp table t_s63 as select row_number() over (order by x.pid) as ord, x.pid from (select distinct coalesce(p.parent_product_id, p.id) as pid from public.so_line l join public.product p on p.id = l.product_id where l.so_id = :'so_a'::uuid) x;
create temp table t_s120 as
  select row_number() over (order by src, pid) as ord, pid from (
    select 0 as src, pid from t_s63
    union all
    (select 1, p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = 'Asung - Edmonton' and b.qty <> 0 and p.parent_product_id is null and p.id not in (select pid from t_s63) order by p.sku limit 57)) z;
select (select count(*) from t_keys) as n_keys, (select count(*) from t_s63) as n_s63, (select count(*) from t_s120) as n_s120 \gset
\echo '── 키: 전수' :n_keys '· 63 표본' :n_s63 '· 120 표본' :n_s120
-- ── 한 phase 의 캡처(옛 · 새 같은 문장) ──
create function pg_temp.capture_all(p_phase text) returns void language plpgsql as $$
declare v_all uuid[]; v_63 uuid[]; v_120 uuid[]; w uuid;
begin
  select array_agg(pid order by pid) into v_all from t_keys;
  select array_agg(pid order by ord) into v_63 from t_s63;
  select array_agg(pid order by ord) into v_120 from t_s120;
  foreach w in array array[current_setting('perf.wh1')::uuid, current_setting('perf.wh2')::uuid] loop
    perform pg_temp.cap(p_phase, 'G1', w, v_all);                                       -- G1 전수 한 번에
    perform pg_temp.chunks(p_phase, w, 1, v_63);                                        -- G2 덩이 1(63 키 × 63 번)
    perform pg_temp.chunks(p_phase, w, 63, v_120);                                      -- G2 덩이 63(120 키 → 2 번)
    perform pg_temp.chunks(p_phase, w, 120, v_120);                                     -- G2 덩이 120(한 번)
    perform pg_temp.cap(p_phase, 'G4-null', w, null);                                   -- G4 null 길
    perform pg_temp.cap(p_phase, 'G3-mixed', w, array[current_setting('perf.k_snap_only')::uuid, current_setting('perf.k_ledger_only')::uuid, current_setting('perf.k_neither')::uuid,
                                                     current_setting('perf.k_combo')::uuid, current_setting('perf.k_set')::uuid, '00000000-0000-0000-0000-000000000001'::uuid, v_63[1], v_63[1], v_63[2]]);
  end loop;
  w := current_setting('perf.wh2')::uuid;
  perform pg_temp.cap(p_phase, 'G3-empty', w, '{}'::uuid[]);
  perform pg_temp.cap(p_phase, 'G3-dup', w, array[v_63[1], v_63[1], v_63[2]]);
  perform pg_temp.cap(p_phase, 'G3-unknown', w, array['00000000-0000-0000-0000-000000000001'::uuid]);
  perform pg_temp.cap(p_phase, 'G3-unknown+known', w, array['00000000-0000-0000-0000-000000000001'::uuid, v_63[1]]);
  perform pg_temp.cap(p_phase, 'G3-snap_only', w, array[current_setting('perf.k_snap_only')::uuid]);
  perform pg_temp.cap(p_phase, 'G3-ledger_only', w, array[current_setting('perf.k_ledger_only')::uuid]);
  perform pg_temp.cap(p_phase, 'G3-neither', w, array[current_setting('perf.k_neither')::uuid]);
  perform pg_temp.cap(p_phase, 'G3-combo', w, array[current_setting('perf.k_combo')::uuid]);
  perform pg_temp.cap(p_phase, 'G3-set', w, array[current_setting('perf.k_set')::uuid]);
  insert into t_src select p_phase, p.prosrc,
         coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) || '/' || pg_get_function_identity_arguments(p.oid) || '/' || pg_get_function_result(p.oid) || '/' || (select l.lanname from pg_language l where l.oid = p.prolang),
         md5(coalesce(obj_description(p.oid, 'pg_proc'), ''))
    from pg_proc p where p.oid = 'public.inv_available_base(uuid, uuid[])'::regprocedure;
end $$;
select set_config('perf.wh1', :'wh1', true), set_config('perf.wh2', :'wh2', true), set_config('perf.k_snap_only', :'k_snap_only', true), set_config('perf.k_ledger_only', :'k_ledger_only', true),
       set_config('perf.k_neither', :'k_neither', true), set_config('perf.k_combo', :'k_combo', true), set_config('perf.k_set', :'k_set', true);
select array_agg(pid order by ord)::text as p63 from t_s63 \gset
select array_agg(pid order by ord)::text as p120 from t_s120 \gset
-- ── G5 · G8 겉 창구(가짜 직원 신원 · 결과는 set_config → reset role 뒤 t_j · t_x) ──
create function pg_temp.front(p_phase text) returns void language plpgsql as $$
declare v_63 uuid[] := current_setting('perf.p63')::uuid[]; v_120 uuid[] := current_setting('perf.p120')::uuid[]; w1 uuid := current_setting('perf.wh1')::uuid; w2 uuid := current_setting('perf.wh2')::uuid;
begin
  perform set_config('perf.j.sam_e63',  coalesce((select jsonb_agg(to_jsonb(r) order by r.stock_pid) from public.so_available_many(v_63, w2) r), '[]')::text, true);
  perform set_config('perf.j.sam_t63',  coalesce((select jsonb_agg(to_jsonb(r) order by r.stock_pid) from public.so_available_many(v_63, w1) r), '[]')::text, true);
  perform set_config('perf.j.sam_e1',   coalesce((select jsonb_agg(to_jsonb(r) order by r.stock_pid) from public.so_available_many(array[v_63[1]], w2) r), '[]')::text, true);
  perform set_config('perf.j.sam_e120', coalesce((select jsonb_agg(to_jsonb(r) order by r.stock_pid) from public.so_available_many(v_120, w2) r), '[]')::text, true);
  perform set_config('perf.j.sam_t120', coalesce((select jsonb_agg(to_jsonb(r) order by r.stock_pid) from public.so_available_many(v_120, w1) r), '[]')::text, true);
  perform set_config('perf.j.sla_21021', coalesce((select jsonb_agg(to_jsonb(r) order by r.ordinality) from public.so_lines_available(current_setting('perf.so_a')::uuid) with ordinality r), '[]')::text, true);
  perform set_config('perf.j.sla_draft', coalesce((select jsonb_agg(to_jsonb(r) order by r.ordinality) from public.so_lines_available(current_setting('perf.so_draft')::uuid) with ordinality r), '[]')::text, true);
  -- G8: SO-21021 꼴(63 키 → Edmonton) · 데움 한 번 · explain 한 번
  perform count(*) from public.so_available_many(v_63, w2);
  perform set_config('perf.x', pg_temp.xplain(format('select * from public.so_available_many(%L::uuid[], %L::uuid)', v_63, w2)), true);
end $$;
select set_config('perf.p63', :'p63', true), set_config('perf.p120', :'p120', true), set_config('perf.so_a', :'so_a', true), set_config('perf.so_draft', :'so_draft', true);
-- 직원 신원으로 받은 것(set_config)을 reset role 뒤 t_j · t_x 에 · shop_stock_payload 는 authenticated 에 execute 가 없다(service_role 전용) → postgres 로 직접 t_j 에
create function pg_temp.pull(p_phase text) returns void language plpgsql as $$
declare nm text; st record;
begin
  foreach nm in array array['sam_e63', 'sam_t63', 'sam_e1', 'sam_e120', 'sam_t120', 'sla_21021', 'sla_draft'] loop
    insert into t_j values (p_phase, nm, current_setting('perf.j.' || nm));
  end loop;
  insert into t_x values (p_phase, current_setting('perf.x'));
  for st in select distinct sl.store_id from public.shop_location sl where sl.is_active order by 1 loop
    insert into t_j select p_phase, 'ssp_' || left(st.store_id::text, 8), coalesce((select jsonb_agg(to_jsonb(r) order by r.store_id, r.product_id, r.warehouse_id) from public.shop_stock_payload(st.store_id, null) r), '[]')::text;
  end loop;
end $$;
-- ═══ OLD(적용 전) ═══
select pg_temp.capture_all('old');
set local role authenticated;
select set_config('request.jwt.claim.sub', :'staff_uid', true), set_config('request.jwt.claims', json_build_object('sub', :'staff_uid', 'role', 'authenticated')::text, true);
select pg_temp.front('old');
reset role;
select pg_temp.pull('old');
select clock_timestamp() as t_old_done \gset
-- ═══ 시험 적용 ═══
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select clock_timestamp() as t_mig \gset
-- ═══ NEW(적용 뒤 · 확인 갈래면 같은 함수) ═══
select pg_temp.capture_all('new');
set local role authenticated;
select set_config('request.jwt.claim.sub', :'staff_uid', true), set_config('request.jwt.claims', json_build_object('sub', :'staff_uid', 'role', 'authenticated')::text, true);
select pg_temp.front('new');
reset role;
select pg_temp.pull('new');
-- ═══ 견줌 ═══
create function pg_temp.cmp(p_grp text, p_wh uuid) returns text language sql as $$
  select (select count(*) from t_av where phase = 'old' and grp = p_grp and wh = p_wh) || '/' || (select count(*) from t_av where phase = 'new' and grp = p_grp and wh = p_wh) || '/' ||
         (select count(*) from (select stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = 'old' and grp = p_grp and wh = p_wh except all select stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = 'new' and grp = p_grp and wh = p_wh) x) || '/' ||
         (select count(*) from (select stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = 'new' and grp = p_grp and wh = p_wh except all select stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = 'old' and grp = p_grp and wh = p_wh) x);
$$;
create function pg_temp.want(p_grp text, p_wh uuid) returns text language sql as $$
  select (select count(*) from t_av where phase = 'old' and grp = p_grp and wh = p_wh) || '/' || (select count(*) from t_av where phase = 'old' and grp = p_grp and wh = p_wh) || '/0/0';
$$;
-- G1 전수(옛 행 수 > 0 · 옛 = 새 집합 차 두 방향 0 · 칸 전부)
select pg_temp.chk('G1 all keys T old=new (o/n/o-n/n-o)', pg_temp.cmp('G1', :'wh1'::uuid), pg_temp.want('G1', :'wh1'::uuid));
select pg_temp.chk('G1 all keys E old=new (o/n/o-n/n-o)', pg_temp.cmp('G1', :'wh2'::uuid), pg_temp.want('G1', :'wh2'::uuid));
select pg_temp.chk('G1 all keys rows > 1000 both', (select (count(*) filter (where wh = :'wh1'::uuid) > 1000 and count(*) filter (where wh = :'wh2'::uuid) > 1000)::text from t_av where phase = 'old' and grp = 'G1'), 'true');
select pg_temp.chk('G1 all keys = every stock key with a row in G4-null (old · both)',
  (select count(*)::text from (select wh, stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = 'old' and grp = 'G1' except all select wh, stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = 'old' and grp = 'G4-null') x)
    || '/' || (select count(*)::text from (select wh, stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = 'old' and grp = 'G4-null' except all select wh, stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = 'old' and grp = 'G1') x), '0/0');
-- G2 화면 크기 — 덩이 합집합(옛 · 새 각각) = G1 옛 반환을 그 키들로 좁힌 것
create function pg_temp.g2(p_phase text, p_size int, p_wh uuid, p_sample text) returns text language plpgsql as $$
declare a int; b int;
begin
  execute format('select (select count(*) from (select stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = %L and grp = %L and wh = %L
                           except all select stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = ''old'' and grp = ''G1'' and wh = %L and stock_pid in (select pid from %I)) x),
                         (select count(*) from (select stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = ''old'' and grp = ''G1'' and wh = %L and stock_pid in (select pid from %I)
                           except all select stock_pid, qty_ea, sales_alloc_ea, transfer_alloc_ea, bgrade_ea from t_av where phase = %L and grp = %L and wh = %L) x)',
                 p_phase, 'G2-' || p_size, p_wh, p_wh, p_sample, p_wh, p_sample, p_phase, 'G2-' || p_size, p_wh) into a, b;
  return a || '/' || b;
end $$;
select pg_temp.chk('G2 chunks 1 (63 keys) T old∪=G1old · new∪=G1old', pg_temp.g2('old', 1, :'wh1'::uuid, 't_s63') || ' ' || pg_temp.g2('new', 1, :'wh1'::uuid, 't_s63'), '0/0 0/0');
select pg_temp.chk('G2 chunks 1 (63 keys) E old∪=G1old · new∪=G1old', pg_temp.g2('old', 1, :'wh2'::uuid, 't_s63') || ' ' || pg_temp.g2('new', 1, :'wh2'::uuid, 't_s63'), '0/0 0/0');
select pg_temp.chk('G2 chunks 63 (120 keys) T', pg_temp.g2('old', 63, :'wh1'::uuid, 't_s120') || ' ' || pg_temp.g2('new', 63, :'wh1'::uuid, 't_s120'), '0/0 0/0');
select pg_temp.chk('G2 chunks 63 (120 keys) E', pg_temp.g2('old', 63, :'wh2'::uuid, 't_s120') || ' ' || pg_temp.g2('new', 63, :'wh2'::uuid, 't_s120'), '0/0 0/0');
select pg_temp.chk('G2 chunks 120 (120 keys) T', pg_temp.g2('old', 120, :'wh1'::uuid, 't_s120') || ' ' || pg_temp.g2('new', 120, :'wh1'::uuid, 't_s120'), '0/0 0/0');
select pg_temp.chk('G2 chunks 120 (120 keys) E', pg_temp.g2('old', 120, :'wh2'::uuid, 't_s120') || ' ' || pg_temp.g2('new', 120, :'wh2'::uuid, 't_s120'), '0/0 0/0');
select pg_temp.chk('G2 sample rows > 0 (63 · 120 · E old)', (select (count(*) filter (where grp = 'G2-1') > 0 and count(*) filter (where grp = 'G2-120') > count(*) filter (where grp = 'G2-1'))::text from t_av where phase = 'old' and wh = :'wh2'::uuid), 'true');
-- G3 가장자리(Edmonton · 옛 = 새 · 섞음은 두 창고)
select pg_temp.chk('G3 empty array E old=new (옛 버릇: 창고 전체)', pg_temp.cmp('G3-empty', :'wh2'::uuid), pg_temp.want('G3-empty', :'wh2'::uuid));
-- 회차 2 정정: 빈 배열의 옛 버릇 = 장부(bal)는 창고 전체(arr null) · 예약(alloc · talloc)은 `= any('{}')` 가 거짓이라 0 — 장부 세 칸만 null 길과 같고 예약 두 칸은 전부 0
select pg_temp.chk('G3 empty array old = null path on (stock_pid · qty_ea · bgrade_ea) · allocs all 0 (옛 버릇 모양)',
  (select count(*)::text from (select stock_pid, qty_ea, bgrade_ea from t_av where phase = 'old' and grp = 'G3-empty' and wh = :'wh2'::uuid except all select stock_pid, qty_ea, bgrade_ea from t_av where phase = 'old' and grp = 'G4-null' and wh = :'wh2'::uuid) x)
    || '/' || (select count(*)::text from (select stock_pid, qty_ea, bgrade_ea from t_av where phase = 'old' and grp = 'G4-null' and wh = :'wh2'::uuid except all select stock_pid, qty_ea, bgrade_ea from t_av where phase = 'old' and grp = 'G3-empty' and wh = :'wh2'::uuid) x)
    || '/' || (select coalesce(max(greatest(abs(sales_alloc_ea), abs(transfer_alloc_ea))), 0)::text from t_av where phase in ('old', 'new') and grp in ('G3-empty', 'G3-unknown') and wh = :'wh2'::uuid), '0/0/0');
select pg_temp.chk('G3 dup pids E old=new', pg_temp.cmp('G3-dup', :'wh2'::uuid), pg_temp.want('G3-dup', :'wh2'::uuid));
select pg_temp.chk('G3 unknown pid E old=new (옛 버릇: 창고 전체)', pg_temp.cmp('G3-unknown', :'wh2'::uuid), pg_temp.want('G3-unknown', :'wh2'::uuid));
select pg_temp.chk('G3 unknown+known E old=new', pg_temp.cmp('G3-unknown+known', :'wh2'::uuid), pg_temp.want('G3-unknown+known', :'wh2'::uuid));
select pg_temp.chk('G3 snapshot-only sku E old=new', pg_temp.cmp('G3-snap_only', :'wh2'::uuid), pg_temp.want('G3-snap_only', :'wh2'::uuid));
select pg_temp.chk('G3 ledger-only sku E old=new', pg_temp.cmp('G3-ledger_only', :'wh2'::uuid), pg_temp.want('G3-ledger_only', :'wh2'::uuid));
select pg_temp.chk('G3 neither sku E old=new', pg_temp.cmp('G3-neither', :'wh2'::uuid), pg_temp.want('G3-neither', :'wh2'::uuid));
select pg_temp.chk('G3 combo E old=new', pg_temp.cmp('G3-combo', :'wh2'::uuid), pg_temp.want('G3-combo', :'wh2'::uuid));
select pg_temp.chk('G3 set product id E old=new', pg_temp.cmp('G3-set', :'wh2'::uuid), pg_temp.want('G3-set', :'wh2'::uuid));
select pg_temp.chk('G3 mixed T old=new', pg_temp.cmp('G3-mixed', :'wh1'::uuid), pg_temp.want('G3-mixed', :'wh1'::uuid));
select pg_temp.chk('G3 mixed E old=new', pg_temp.cmp('G3-mixed', :'wh2'::uuid), pg_temp.want('G3-mixed', :'wh2'::uuid));
-- G4 null 길 무변 — 두 창고 옛 = 새 · 재발행 본문에서 키 갈래(bal 머리 다음 ~ union all) · 문 한 줄을 빼면 옛 본문(perf-2a prosrc md5 3cacac31…) 바이트 그대로
select pg_temp.chk('G4 null T old=new', pg_temp.cmp('G4-null', :'wh1'::uuid), pg_temp.want('G4-null', :'wh1'::uuid));
select pg_temp.chk('G4 null E old=new', pg_temp.cmp('G4-null', :'wh2'::uuid), pg_temp.want('G4-null', :'wh2'::uuid));
create function pg_temp.strip_new(p_src text) returns text language plpgsql as $$
declare v_lines text[] := string_to_array(p_src, E'\n'); v_i int; v_bal int; v_k3 int; v_k4 int; v_rest text[] := '{}';
begin
  for v_i in 1 .. array_length(v_lines, 1) loop
    if v_lines[v_i] like '  bal as (%' then v_bal := v_i; end if;
    if v_lines[v_i] like '    union all%-- perf-rpc-1%' then v_k3 := v_i; end if;
    if v_lines[v_i] like '      and (select k.arr from skus k) is null %-- perf-rpc-1%' then v_k4 := v_i; end if;
  end loop;
  if v_bal is null or v_k3 is null or v_k4 is null then return 'markers missing'; end if;
  for v_i in 1 .. array_length(v_lines, 1) loop
    if (v_i > v_bal and v_i <= v_k3) or v_i = v_k4 then continue; end if;
    v_rest := v_rest || v_lines[v_i];
  end loop;
  return md5(array_to_string(v_rest, E'\n'));
end $$;
select pg_temp.chk('G4b new body minus key branch & gate = old body md5 3cacac31…', (select pg_temp.strip_new(src) from t_src where phase = 'new'), '3cacac3195fb93afb99a794a91cfbdf9');
\if :{?mig}
select pg_temp.chk('G4c old body md5 (before mig) = perf-2a 3cacac31…', (select md5(src) from t_src where phase = 'old'), '3cacac3195fb93afb99a794a91cfbdf9');
\endif
-- G5 겉 창구(가짜 직원 신원) — 이름마다 옛 = 새(jsonb 글자 같음 · SAM · SLA 는 비어 있지 않음)
select pg_temp.chk('G5 ' || o.name || ' old=new · rows ' || jsonb_array_length(o.res::jsonb), (o.res = n.res and (o.res <> '[]' or o.name like 'ssp_%'))::text, 'true')   -- 회차 2 정정: 스토어 하나는 payload 가 비어 있다(listing 6 · 보낼 줄 0) — 옛 = 새 만
  from t_j o join t_j n on n.name = o.name and n.phase = 'new' where o.phase = 'old' order by o.name;
select pg_temp.chk('G5 names captured (old · new)', (select count(*) filter (where phase = 'old') || '/' || count(*) filter (where phase = 'new') from t_j), '10/10');
-- G6 속성(acl · definer · volatile · search_path · 소유자 · 서명 · 반환 · 언어) 적용 전 = 뒤 · comment md5 상수(무변 결정 · 이견 답 3)
select pg_temp.chk('G6 attributes before = after', (select attrs from t_src where phase = 'new'), (select attrs from t_src where phase = 'old'));
select pg_temp.chk('G6 comment md5 = 3e4be82f… (unchanged · both phases)', (select string_agg(comment_md5, ' ' order by phase) from t_src), '3e4be82f8818ab5bbe0b8b345e442d21 3e4be82f8818ab5bbe0b8b345e442d21');
select pg_temp.chk('G6 overloads = 1', (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_available_base'), '1');
-- G7 REST 두 겹 ① — 새 본문에 깊이 0 update · delete 0(읽기 함수)
select pg_temp.chk('G7 update/delete statements in body = 0', (select count(*)::text from regexp_matches((select src from t_src where phase = 'new'), '^\s*(update|delete)\s', 'gn')), '0');
-- ═══ 결과 ═══
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || left(coalesce(got, '(null)'), 300) || ' | want=' || left(coalesce(want, '(null)'), 300) end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_bad, count(*) as n_all from t_res \gset
\echo '── 시간(ms · phase · name · rows) — G1 전수 · G2 덩이 · G4 null · G3'
select phase, name, ms, rows from t_ms order by name, phase;
\echo '── G8 explain (analyze, buffers) so_available_many(63 keys → Edmonton · staff identity) — OLD'
select plan from t_x where phase = 'old';
\echo '── G8 — NEW'
select plan from t_x where phase = 'new';
select clock_timestamp() as t_end \gset
rollback;
select (select max(id) from public.inv_ledger) = :fp_led_max and (select count(*) from public.inv_ledger) = :fp_led_n and (select count(*) from public.inv_snapshot) = :fp_snap_n as z_fingerprint_same_as_start,
       (select md5(prosrc) from pg_proc where oid = 'public.inv_available_base(uuid, uuid[])'::regprocedure) as z_iab_md5_after,
       round(extract(epoch from (:'t_old_done'::timestamptz - :'t_begin'::timestamptz))::numeric, 2) as old_capture_s,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_mig'::timestamptz))::numeric, 2) as mig_to_rollback_s,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_begin'::timestamptz))::numeric, 2) as begin_to_rollback_s;
\echo '── 결과: OK' :n_ok '· MISMATCH' :n_bad '· 전체' :n_all '· 기대 OK' :EXPECT_OK
\if :{?mig}
\echo '   (시험 갈래 · 적용은 rollback 됨 · z_iab_md5_after 는 옛 3cacac31… 이어야 한다)'
\else
\echo '   (확인 갈래 · z_iab_md5_after 는 새 값 7a1ef377…)'
\endif
