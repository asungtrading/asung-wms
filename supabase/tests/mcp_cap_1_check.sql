-- supabase/tests/mcp_cap_1_check.sql — mcp-cap-1 검증: mcp_sales 쪽 넘기기(p_offset · limit 500 · page · rows_truncated = 안 보인 줄 전부 · 925 항등식 모든 쪽 · 정렬 유일 · 끝 넘으면 빈 쪽) · 시그니처 한 벌 · 권한 · 이견 3 실측(group customer · 1 개월 · 전 200 · 후 500) (2026-11-07 UTC · 지시서 ~/asung/prompts/mcp-cap-1.md)
-- [IMS 메인 · fazgmyvzzhqybtvtktyg] 시험 적용 장치 틀(asung-workflow §4 · mcp_1b_check 본보기) — 기준(begin 앞) → 시간 재기(시험 갈래: 짧은 트랜잭션 둘 · 전(옛 판 · limit 200) · 후(\i → 새 판 · limit 500) · 각 rollback / 확인 갈래: 후만) → 트랜잭션 셋 A · B · C(각 lock_timeout 2s · 각 ≤ 10 s · 각 (-v mig 면 \i) → 가짜 행 seed(2027-06 · 실자료 0) → 호출 결과를 \gset → rollback) → 검사는 트랜잭션 밖
--   Claude Code(시험): MIG=supabase/migrations/20261107051447_mcp_cap_1_sales_paging.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/mcp_cap_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 같다(전 실측은 「(applied)」 로 찍힌다)
--   실데이터 집계는 둘(전 · 후)뿐 · 가짜 기간 호출 11(각각 hist_so_line 283k 훑기 ≈ 0.2 ~ 0.5 s) · ⚠️ 가짜 날짜 2027-06 — hist · IMS 인보이스 · 크레딧 모두 2027 에 0 행(기준에서 단언)
\set ON_ERROR_STOP on
\set EXPECT_OK 19
\set cid mcp-test-client-c1a
\pset pager off
select (select count(*) from public.hist_so) as n_hist, (select count(*) from public.hist_so_line) as n_hist_line, (select count(*) from public.product) as n_product, (select count(*) from public.customer) as n_cust,
       (select count(*) from public.ims_staff) as n_staff, (select count(*) from public.ref_brand) as n_brand, (select claude_client_id from public.mcp_config where singleton) as cid0,
       (select count(*) from public.hist_so where invoice_date >= '2027-01-01') + (select count(*) from public.so_invoice where issued_on >= '2027-01-01') + (select count(*) from public.so_credit where issued_on >= '2027-01-01') as n_2027 \gset
select md5(p.prosrc) as ms_pre_md5, pg_get_function_identity_arguments(p.oid) as ms_pre_sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales' \gset
\echo '── 기준: hist_so' :n_hist '· hist_so_line' :n_hist_line '· product' :n_product '· customer' :n_cust '· staff' :n_staff '· 2027 실자료' :n_2027 '(0 이어야) · mcp_sales md5' :ms_pre_md5 '· sig' :ms_pre_sig
-- ── 도우미(세션 임시 스키마 — 트랜잭션 밖 · rollback 에 안 사라진다) ──
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
create function pg_temp.st(v text, p text) returns text language sql as $$ select case when v like p || '%' then p else left(v, 120) end $$;
create function pg_temp.keys(j jsonb) returns setof text language plpgsql as $$
declare r record;
begin
  if jsonb_typeof(j) = 'object' then
    for r in select key, value from jsonb_each(j) loop
      return next r.key;
      if jsonb_typeof(r.value) in ('object', 'array') then return query select pg_temp.keys(r.value); end if;
    end loop;
  elsif jsonb_typeof(j) = 'array' then
    for r in select value from jsonb_array_elements(j) loop
      if jsonb_typeof(r.value) in ('object', 'array') then return query select pg_temp.keys(r.value); end if;
    end loop;
  end if;
end $$;
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
-- 가짜 admin 직원(claude · 원가는 역할로) + mcp_config 시험 값 — 트랜잭션마다(전부 rollback)
create function pg_temp.setup_admin() returns text language plpgsql as $$
declare v_uid uuid := gen_random_uuid();
begin
  insert into public.ims_staff (id, auth_user_id, email, name, role, perms, is_active) values ('0c1a0000-0000-4000-8000-000000000001', v_uid, 'mcpc1a-a@test.invalid', 'MCPcap1 Fake Admin', 'admin', '["claude"]'::jsonb, true);
  update public.mcp_config set claude_client_id = 'mcp-test-client-c1a' where singleton;
  return v_uid::text;
end $$;
-- 판매 집계 한 번(ims_connector · 가짜 기간 2027-06 · sku 기본) — 인자 글은 그대로 함수 뒤에 붙는다
create function pg_temp.sj(p_uid text, p_args text) returns text language sql as $$
  select pg_temp.as_conn('ims_connector', pg_temp.cl(p_uid, 'mcp-test-client-c1a'), format($q$select public.mcp_sales(%s)::text$q$, p_args))
$$;
create function pg_temp.rows_net(j jsonb) returns text language sql as $$ select coalesce(string_agg((r->>'key') || '=' || (r->>'net'), ' ' order by o), '(none)') from jsonb_array_elements(j->'rows') with ordinality as x(r, o) $$;
create function pg_temp.page(j jsonb) returns text language sql as $$ select (j->'page'->>'offset') || '/' || (j->'page'->>'limit') || '/' || (j->'page'->>'shown') || '/' || (j->'page'->>'total_rows') || '/' || coalesce(j->'page'->>'next_offset', 'null') $$;
create function pg_temp.trunc(j jsonb) returns text language sql as $$ select coalesce((j->'rows_truncated'->>'rows') || '/' || (j->'rows_truncated'->>'net'), '(absent)') $$;
create function pg_temp.ident(j jsonb) returns text language sql as $$
  select (round(coalesce((select sum((r->>'net')::numeric) from jsonb_array_elements(j->'rows') r), 0) + coalesce((j->'rows_truncated'->>'net')::numeric, 0), 2) = (j->'totals'->>'net')::numeric)::text || ' ' || (j->'totals'->>'net') $$;
-- 이견 3 실측: group customer · 2026-10(실자료 · hist 10-31 까지 + IMS 10-30 부터) · limit p_limit
create function pg_temp.timed(p_uid text, p_limit int) returns numeric language plpgsql as $$
declare t timestamptz; v text;
begin
  t := clock_timestamp();
  v := pg_temp.as_conn('ims_connector', pg_temp.cl(p_uid, 'mcp-test-client-c1a'), format($q$select public.mcp_sales('2026-10-01', '2026-10-31', 'customer', null, null, null, null, %s)->'totals'->>'sales'$q$, p_limit));
  if left(v, 4) = 'ERR ' then raise exception 'timed % failed: %', p_limit, v; end if;
  return round(extract(epoch from clock_timestamp() - t) * 1000);
end $$;

-- ── 실측(이견 3) — 실데이터 집계는 둘뿐 ──
\if :{?mig}
\echo '── 실측(시험 갈래 · 트랜잭션 둘 · rollback 됨):' :mig
begin;
set local lock_timeout = '2s';
select pg_temp.setup_admin() as t_uid \gset
select pg_temp.timed(:'t_uid', 200) as ms_before \gset
rollback;
begin;
set local lock_timeout = '2s';
\i :mig
select pg_temp.setup_admin() as t_uid \gset
select pg_temp.timed(:'t_uid', 500) as ms_after \gset
rollback;
\else
\echo '── 실측(확인 갈래 · 적용 뒤 · 후만 · rollback 됨)'
\set ms_before '(applied)'
begin;
set local lock_timeout = '2s';
select pg_temp.setup_admin() as t_uid \gset
select pg_temp.timed(:'t_uid', 500) as ms_after \gset
rollback;
\endif
\echo '── 이견 3 실측 group customer · 2026-10(ms): 전(옛 판 · limit 200)' :ms_before '· 후(새 판 · limit 500)' :ms_after

-- ── 가짜 재료(c1a · 2027-06) — 브랜드 1 · 제품 7 · 손님 본사 + 지점 + 단독 · hist 오더 4(손님 없는 오더 하나) · 트랜잭션마다 seed() 로(각 rollback) ──
create temp table t_f as select
  '0c1a0000-0000-4000-8000-000000000011'::uuid as hq_id, '0c1a0000-0000-4000-8000-000000000012'::uuid as br_id, '0c1a0000-0000-4000-8000-000000000013'::uuid as solo_id,
  '0c1a0000-0000-4000-8000-000000000021'::uuid as brand_id,
  '0c1a0000-0000-4000-8000-000000000061'::uuid as h1_id, '0c1a0000-0000-4000-8000-000000000062'::uuid as h2_id, '0c1a0000-0000-4000-8000-000000000063'::uuid as h3_id, '0c1a0000-0000-4000-8000-000000000064'::uuid as h4_id,
  'e6f5d46f-b345-47e2-916c-f7f64aeb78b7'::uuid as cad;
create function pg_temp.seed() returns text language plpgsql as $s$
declare v_uid text := pg_temp.setup_admin();
begin
  insert into public.ref_brand (id, name, source) select brand_id, 'MCPC Brand 1', 'manual' from t_f;
  insert into public.product (id, name, sku, brand_id, brand_name, source)
  select ('0c1a0000-0000-4000-8000-0000000005' || lpad(n::text, 2, '0'))::uuid, 'MCPC Product ' || n, 'MCPC10' || lpad(n::text, 2, '0'), brand_id, 'MCPC Brand 1', 'manual' from t_f, generate_series(1, 7) n;
  insert into public.customer (id, name, source, currency_id, currency_code) select hq_id, 'MCPC HQ 1', 'manual', cad, 'CAD' from t_f union all select solo_id, 'MCPC Solo 1', 'manual', cad, 'CAD' from t_f;
  insert into public.customer (id, name, source, currency_id, currency_code, parent_id, parent_source) select br_id, 'MCPC Branch 1', 'manual', cad, 'CAD', hq_id, 'ims' from t_f;
  insert into public.hist_so (id, era, order_number, customer_id, customer_name, invoice_date, invoice_number, source, line_count)
  select h1_id, 'core', 'SO-C1A01', hq_id, 'MCPC HQ 1', '2027-06-10'::date, 'C1A01', 'bq_confirmed', 4 from t_f union all
  select h2_id, 'core', 'SO-C1A02', br_id, 'MCPC Branch 1', '2027-06-12', 'C1A02', 'bq_confirmed', 3 from t_f union all
  select h3_id, 'core', 'SO-C1A03', solo_id, 'MCPC Solo 1', '2027-06-15', 'C1A03', 'bq_confirmed', 1 from t_f union all
  select h4_id, 'core', 'SO-C1A04', null, null, '2027-06-16', 'C1A04', 'bq_confirmed', 1 from t_f;
  -- 순매출: 1001 = 70 + 5 = 75 · 1002 = 60 + 1 = 61 · 1003 50 · 1004 40 · 1005 30 · 1006 20 · 1007 20(1006 과 같음 → key 순) · 합 296 / 손님: HQ 묶음 290(HQ 220 · Branch 70) · Solo 5 · (no customer) 1
  insert into public.hist_so_line (hist_so_id, seq, doc_type, doc_number, doc_date, sku, product_id, product_name, brand, quantity, unit_price, sale, is_return)
  select h1_id, 1, 'invoice', 'C1A01', '2027-06-10'::date, 'MCPC1001', '0c1a0000-0000-4000-8000-000000000501'::uuid, 'MCPC Product 1', 'MCPC Brand 1', 7::numeric, 10::numeric, 70::numeric, false from t_f union all
  select h1_id, 2, 'invoice', 'C1A01', '2027-06-10', 'MCPC1002', '0c1a0000-0000-4000-8000-000000000502', 'MCPC Product 2', 'MCPC Brand 1', 6, 10, 60, false from t_f union all
  select h1_id, 3, 'invoice', 'C1A01', '2027-06-10', 'MCPC1003', '0c1a0000-0000-4000-8000-000000000503', 'MCPC Product 3', 'MCPC Brand 1', 5, 10, 50, false from t_f union all
  select h1_id, 4, 'invoice', 'C1A01', '2027-06-10', 'MCPC1004', '0c1a0000-0000-4000-8000-000000000504', 'MCPC Product 4', 'MCPC Brand 1', 4, 10, 40, false from t_f union all
  select h2_id, 1, 'invoice', 'C1A02', '2027-06-12', 'MCPC1005', '0c1a0000-0000-4000-8000-000000000505', 'MCPC Product 5', 'MCPC Brand 1', 3, 10, 30, false from t_f union all
  select h2_id, 2, 'invoice', 'C1A02', '2027-06-12', 'MCPC1006', '0c1a0000-0000-4000-8000-000000000506', 'MCPC Product 6', 'MCPC Brand 1', 2, 10, 20, false from t_f union all
  select h2_id, 3, 'invoice', 'C1A02', '2027-06-12', 'MCPC1007', '0c1a0000-0000-4000-8000-000000000507', 'MCPC Product 7', 'MCPC Brand 1', 2, 10, 20, false from t_f union all
  select h3_id, 1, 'invoice', 'C1A03', '2027-06-15', 'MCPC1001', '0c1a0000-0000-4000-8000-000000000501', 'MCPC Product 1', 'MCPC Brand 1', 1, 5, 5, false from t_f union all
  select h4_id, 1, 'invoice', 'C1A04', '2027-06-16', 'MCPC1002', '0c1a0000-0000-4000-8000-000000000502', 'MCPC Product 2', 'MCPC Brand 1', 1, 1, 1, false from t_f;
  return v_uid;
end $s$;

-- ── 본 트랜잭션 셋(각 ≤ 10 s · 95-e 39 — 가짜 기간 호출도 한 번에 ≈ 2 s · hist_so_line 283k · inv_layer_consume 85k 전체 훑기) — 결과는 psql 변수(\gset)로 모아 트랜잭션 밖에서 검사 ──
-- A) 적용 · 카탈로그 · sku 쪽 1 ~ 3
begin;
set local lock_timeout = '2s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용 A(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
select (select count(*)::text || ' | ' || string_agg(pg_get_function_identity_arguments(p.oid), ' ; ') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') as r1,
       (select string_agg(p.proname || '=' || p.proacl::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_sales', 'mcp_name_pick', 'mcp_sales_cell')) || ' ' ||
         (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mcp\_%' and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'))::text as r2,
       (select p.prosecdef::text || p.provolatile::text || coalesce(p.proconfig::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') as r3,
       (select pg_temp.nowhere(p.prosrc)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') as r4,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') as new_md5 \gset
\echo '── (정보) public 에서 PUBLIC EXECUTE 가 있는 함수 — 이 차수 밖:'
select p.proname, p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE') order by 1;
select pg_temp.seed() as a_uid \gset
select pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'sku', null, null, null, null, 3, 0$a$)::jsonb as p1 \gset
select pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'sku', null, null, null, null, 3, 3$a$)::jsonb as p2 \gset
select pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'sku', null, null, null, null, 3, 6$a$)::jsonb as p3 \gset
select clock_timestamp() - :'t_begin'::timestamptz as tx_a_begin_to_rollback;
rollback;
-- B) sku 끝 넘음 · 전체 쪽 · 옛 EF 꼴
begin;
set local lock_timeout = '2s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\i :mig
\endif
select pg_temp.seed() as a_uid \gset
select pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'sku', null, null, null, null, 3, 99$a$)::jsonb as p4 \gset
select pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'sku', null, null, null, null, 500, 0$a$)::jsonb as pall \gset
select pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'sku'$a$)::jsonb as pdef \gset
select clock_timestamp() - :'t_begin'::timestamptz as tx_b_begin_to_rollback;
rollback;
-- C) customer 쪽 셋 · 인자 검사(즉시 · 읽기 전) · 권한 실호출(즉시)
begin;
set local lock_timeout = '2s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\i :mig
\endif
select pg_temp.seed() as a_uid \gset
select pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'customer', null, null, null, null, 1, 0$a$)::jsonb as c1 \gset
select pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'customer', null, null, null, null, 1, 1$a$)::jsonb as c2 \gset
select pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'customer', null, null, null, null, 1, 2$a$)::jsonb as c3 \gset
select pg_temp.st(pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'sku', null, null, null, null, 3, -1$a$), 'ERR P0001: offset must be 0 or more — nothing was read') as v1,
       pg_temp.st(pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'sku', null, null, null, null, 501, 0$a$), 'ERR P0001: limit must be between 1 and 500') || ' | ' || pg_temp.st(pg_temp.sj(:'a_uid', $a$'2027-06-01', '2027-06-30', 'sku', null, null, null, null, 0, 0$a$), 'ERR P0001: limit must be between 1 and 500') as v2,
       left(pg_temp.as_conn('authenticated', jsonb_build_object('sub', :'a_uid', 'role', 'authenticated'), $q$select public.mcp_sales('2027-06-01', '2027-06-30', 'sku')::text$q$), 9) || ' ' ||
         left(pg_temp.as_conn('anon', '{}'::jsonb, $q$select public.mcp_sales('2027-06-01', '2027-06-30', 'sku')::text$q$), 9) || ' ' || left(pg_temp.as_conn('service_role', '{}'::jsonb, $q$select public.mcp_sales('2027-06-01', '2027-06-30', 'sku')::text$q$), 9) as x1 \gset
select clock_timestamp() - :'t_begin'::timestamptz as tx_c_begin_to_rollback;
rollback;

-- ── 검사(트랜잭션 밖 · 모은 변수로) ──
select pg_temp.chk('S1 시간: 새 판 customer · 1 개월 · limit 500 이 8 초 안(' || :'ms_after' || ' ms · 전 ' || :'ms_before' || ')', (:ms_after < 8000)::text, 'true');
select pg_temp.chk('S2 2027 실자료 0(가짜 기간이 실자료와 안 섞인다)', :'n_2027', '0');
select pg_temp.chk('R1 mcp_sales 한 벌 · 새 시그니처(…, p_limit integer, p_offset integer)', :'r1', '1 | p_from text, p_to text, p_group text, p_brand text, p_customer text, p_sku text, p_supplier text, p_limit integer, p_offset integer');
select pg_temp.chk('R2 권한: mcp_sales = postgres + ims_connector · 도우미 둘 = postgres 만 · mcp_* 에 PUBLIC EXECUTE 0(⚠️ 전체 0 은 이제 안 선다 — inv_transfer_line_combo_parent_check · 이 차수 밖 · 위 echo)', :'r2', 'mcp_name_pick={postgres=X/postgres} mcp_sales={postgres=X/postgres,ims_connector=X/postgres} mcp_sales_cell={postgres=X/postgres} 0');
select pg_temp.chk('R3 mcp_sales: definer · stable · search_path + work_mem 그대로', :'r3', 'trues{"search_path=public, pg_temp",work_mem=32MB}');
select pg_temp.chk('R4 REST 정적: mcp_sales 의 깊이 0 WHERE 없는 update · delete 0', :'r4', '0');
select pg_temp.chk('P1 쪽 1(offset 0 · limit 3): 1001 1002 1003 · page 0/3/3/7/3 · rows_truncated 4 줄 · 110 · 항등식',
  pg_temp.rows_net(:'p1') || ' | ' || pg_temp.page(:'p1') || ' | ' || pg_temp.trunc(:'p1') || ' | ' || pg_temp.ident(:'p1'),
  'MCPC1001=75.00 MCPC1002=61.00 MCPC1003=50.00 | 0/3/3/7/3 | 4/110.00 | true 296.00');
select pg_temp.chk('P2 쪽 2(offset 3): 1004 1005 1006 · page 3/3/3/7/6 · rows_truncated = 앞 3 + 뒤 1 = 4 줄 · 206 · 항등식',
  pg_temp.rows_net(:'p2') || ' | ' || pg_temp.page(:'p2') || ' | ' || pg_temp.trunc(:'p2') || ' | ' || pg_temp.ident(:'p2'),
  'MCPC1004=40.00 MCPC1005=30.00 MCPC1006=20.00 | 3/3/3/7/6 | 4/206.00 | true 296.00');
select pg_temp.chk('P3 쪽 3(offset 6): 1007(1006 과 같은 20 · key 순 뒤) · page 6/3/1/7/null · rows_truncated 6 줄 · 276 · 항등식',
  pg_temp.rows_net(:'p3') || ' | ' || pg_temp.page(:'p3') || ' | ' || pg_temp.trunc(:'p3') || ' | ' || pg_temp.ident(:'p3'),
  'MCPC1007=20.00 | 6/3/1/7/null | 6/276.00 | true 296.00');
select pg_temp.chk('P4 끝 넘음(offset 99): 빈 쪽(예외 아님) · page 99/3/0/7/null · rows_truncated 7 줄 · 296 · totals 그대로',
  pg_temp.rows_net(:'p4') || ' | ' || pg_temp.page(:'p4') || ' | ' || pg_temp.trunc(:'p4') || ' | ' || pg_temp.ident(:'p4'),
  '(none) | 99/3/0/7/null | 7/296.00 | true 296.00');
select pg_temp.chk('U1 쪽 1 ∪ 쪽 2 ∪ 쪽 3 = 전체(limit 500 · 한 쪽) · 교집합 0 · 순서 같음 · 전체 쪽은 rows_truncated 없음 · page 0/500/7/7/null',
  (select string_agg(r->>'key', ' ' order by o) from jsonb_array_elements((:'p1'::jsonb->'rows') || (:'p2'::jsonb->'rows') || (:'p3'::jsonb->'rows')) with ordinality x(r, o)) || ' | ' ||
  (select count(distinct r->>'key')::text from jsonb_array_elements((:'p1'::jsonb->'rows') || (:'p2'::jsonb->'rows') || (:'p3'::jsonb->'rows')) r) || ' | ' ||
  (select string_agg(r->>'key', ' ' order by o) from jsonb_array_elements(:'pall'::jsonb->'rows') with ordinality x(r, o)) || ' | ' || pg_temp.trunc(:'pall') || ' | ' || pg_temp.page(:'pall'),
  'MCPC1001 MCPC1002 MCPC1003 MCPC1004 MCPC1005 MCPC1006 MCPC1007 | 7 | MCPC1001 MCPC1002 MCPC1003 MCPC1004 MCPC1005 MCPC1006 MCPC1007 | (absent) | 0/500/7/7/null');
select pg_temp.chk('D1 옛 EF 꼴(인자 8 · p_offset 없음) → offset 0 · limit 50 · 7 줄 · 전체 쪽과 같은 rows · totals · other 열쇠 있음(거르기 없음) · rows_before 없음',
  pg_temp.page(:'pdef') || ' | ' || ((:'pdef'::jsonb->'rows') = (:'pall'::jsonb->'rows'))::text || ' | ' || ((:'pdef'::jsonb->'totals') = (:'pall'::jsonb->'totals'))::text || ' | ' || (:'pdef'::jsonb ? 'other')::text || ' | ' || (select count(*) from pg_temp.keys(:'pdef'::jsonb) k where k in ('rows_before', 'rows_after'))::text,
  '0/50/7/7/null | true | true | true | 0');
select pg_temp.chk('K1 page 열쇠 다섯 그대로(offset · limit · shown · total_rows · next_offset) · 원가 열쇠(admin 역할 → cogs) 는 1b 그대로',
  (select string_agg(k, ' ' order by k) from jsonb_object_keys(:'p1'::jsonb->'page') k) || ' | ' || (:'p1'::jsonb->'rows'->0 ? 'cogs')::text || ' ' || (:'p1'::jsonb->'totals' ? 'cogs_unmatched')::text,
  'limit next_offset offset shown total_rows | true true');

select pg_temp.chk('V1 offset -1 → 한 문장 · 읽기 0', :'v1', 'ERR P0001: offset must be 0 or more — nothing was read');
select pg_temp.chk('V2 limit 501 · 0 → 한 문장(1 ~ 500)', :'v2', 'ERR P0001: limit must be between 1 and 500 | ERR P0001: limit must be between 1 and 500');
select pg_temp.chk('C1 쪽 1: MCPC HQ 1 = 290 · accounts [HQ 220, Branch 70](순매출 순) · page 0/1/1/3/1 · rows_truncated 2 줄 · 6 · 항등식',
  pg_temp.rows_net(:'c1') || ' | ' || (select string_agg((a->>'name') || '=' || (a->>'net'), ', ' order by o) from jsonb_array_elements(:'c1'::jsonb->'rows'->0->'accounts') with ordinality x(a, o)) || ' | ' || pg_temp.page(:'c1') || ' | ' || pg_temp.trunc(:'c1') || ' | ' || pg_temp.ident(:'c1'),
  'MCPC HQ 1=290.00 | MCPC HQ 1=220.00, MCPC Branch 1=70.00 | 0/1/1/3/1 | 2/6.00 | true 296.00');
select pg_temp.chk('C2 쪽 2: MCPC Solo 1 = 5 · accounts 열쇠 없음(계정 하나) · page 1/1/1/3/2 · rows_truncated 2 줄 · 291',
  pg_temp.rows_net(:'c2') || ' | ' || (:'c2'::jsonb->'rows'->0 ? 'accounts')::text || ' | ' || pg_temp.page(:'c2') || ' | ' || pg_temp.trunc(:'c2') || ' | ' || pg_temp.ident(:'c2'),
  'MCPC Solo 1=5.00 | false | 1/1/1/3/2 | 2/291.00 | true 296.00');
select pg_temp.chk('C3 쪽 3: (no customer) = 1 · accounts 없음 · page 2/1/1/3/null · rows_truncated 2 줄 · 295',
  pg_temp.rows_net(:'c3') || ' | ' || (:'c3'::jsonb->'rows'->0 ? 'accounts')::text || ' | ' || pg_temp.page(:'c3') || ' | ' || pg_temp.trunc(:'c3') || ' | ' || pg_temp.ident(:'c3'),
  '(no customer)=1.00 | false | 2/1/1/3/null | 2/295.00 | true 296.00');

select pg_temp.chk('X1 authenticated · anon · service_role → 42501 ×3', :'x1', 'ERR 42501 ERR 42501 ERR 42501');
\echo '── 새 판 mcp_sales 본문 md5:' :new_md5

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다 · 시험 갈래는 mcp_sales md5 · sig 도 전과 같다'
select (select count(*) from public.hist_so) = :n_hist as hist_same, (select count(*) from public.hist_so_line) = :n_hist_line as hist_line_same, (select count(*) from public.product) = :n_product as product_same,
       (select count(*) from public.customer) = :n_cust as cust_same, (select count(*) from public.ims_staff) = :n_staff as staff_same, (select count(*) from public.ref_brand) = :n_brand as brand_same,
       (select claude_client_id is not distinct from nullif(:'cid0', '') from public.mcp_config where singleton) as cid_same,
       (select md5(p.prosrc) = :'ms_pre_md5' and pg_get_function_identity_arguments(p.oid) = :'ms_pre_sig' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') as mcp_sales_same;
