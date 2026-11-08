-- supabase/tests/pbc_1_check.sql — pbc-1 검증 (2026-11-08 밤 · 판정 1111 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] begin → 기준(검색어 없음 시간 · SKU · 이름 검색 몇 개 · export · 시퀀스) → (-v mig 면 \i) → B 바코드(낱개 · 꺼진 · 세트 · 일부 · 띄어쓰기) · U 무변(SKU · 이름 검색 앞뒤 · export 앞뒤) · X export 같은 규칙 · E explain(색인 · null 이면 안 돈다) · M 메타(시그니처 · invoker/definer · search_path · acl · comment) · W WHERE 정적(REST 두 겹 ①) · Q 시퀀스 → rollback → Z
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261108165000_pbc_1_product_search_barcode.sql -f supabase/tests/pbc_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 결과 같다(U 의 「앞뒤 같음」은 적용 뒤엔 「같은 판 두 번」일 뿐)
--   ⚠️ 공개 레포 — 상호 없음 · 제품 SKU 와 바코드만(상품 마스터 · 공개 바코드) · 쓰기는 「꺼진 바코드」 시험 한 줄(update is_active · session_replication_role = replica 로 트리거 끔 → shop 큐 시퀀스 안 나감) · 전부 rollback
--   실물: 낱개 NIM12013 바코드 696399120131(그 세트 NIM12013-6 은 제 바코드 696399150602) · 세트 MNT54322-6 바코드 10071409543228(부모 MNT54322 · 제 바코드 071409543221) · 앞 6 자리 100714 · 696399 는 SKU · 이름에 없음(실측 0 · 아래 B6 이 다시 센다)
\set ON_ERROR_STOP on
\pset pager off
select (select value from public.inv_config where key = 'db_role') as db_role;

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns text language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
  return case when p_got is not distinct from p_want then 'OK   ' else 'FAIL ' end || p_label || case when p_got is not distinct from p_want then '' else format(' — got %s · want %s', coalesce(p_got, '(null)'), coalesce(p_want, '(null)')) end;
end $$;
-- skus: product_list 결과를 「sku,sku,… |total」 한 줄로
create function pg_temp.skus(p_q text, p_kind text) returns text language sql as $$
  select coalesce(string_agg(l.sku, ',' order by l.sku), '') || '|' || coalesce(max(l.total), 0)::text from public.product_list(p_q => p_q, p_kind => p_kind, p_limit => 1000) l;
$$;
-- xskus: product_export(sku 칸만) 결과를 같은 꼴로
create function pg_temp.xskus(p_q text, p_kind text) returns text language sql as $$
  select (select coalesce(string_agg(r ->> 0, ',' order by r ->> 0), '') from jsonb_array_elements(x -> 'rows') r) || '|' || (x ->> 'total') from public.product_export(p_q => p_q, p_kind => p_kind, p_columns => array['sku']) x;
$$;
-- ms: 검색어 없는 첫 화면(single · 100 줄) 세 번 — 「최소|첫,둘,셋」(ms)
create function pg_temp.ms() returns text language plpgsql as $$
declare v_t0 timestamptz; v_best numeric := 1e9; v_ms numeric; v_all text := ''; i int;
begin
  for i in 1..3 loop
    v_t0 := clock_timestamp();
    perform count(*) from public.product_list(p_kind => 'single', p_limit => 100);
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    v_all := v_all || case when i > 1 then ',' else '' end || v_ms::text;
    if v_ms < v_best then v_best := v_ms; end if;
  end loop;
  return v_best::text || '|' || v_all;
end $$;
-- safeupdate 규칙 정적 스캐너(qbo_1c_check 의 것 그대로)
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
    if v_chunk ~* '\m(update|delete)\M' and v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;

begin;
-- product_export 는 export_door('product') = Products (master) 열쇠를 jwt 에서 본다 — master 열쇠 가진 직원 하나의 이름표(sub)만 트랜잭션 안에 둔다(역할은 postgres 그대로 · M5 만 authenticated 로)
select set_config('request.jwt.claims', json_build_object('sub', (select auth_user_id::text from public.ims_staff where is_active and auth_user_id is not null and perms ? 'master' order by created_at limit 1), 'role', 'authenticated')::text, true) as claims_set \gset
-- ── 기준(begin 안 · \i 앞) ──
create temp table t_seq_pre as select schemaname, sequencename, last_value from pg_sequences where schemaname not like 'pg\_temp%';
select count(*) as seq_n from t_seq_pre \gset
select split_part(m, '|', 1)::numeric as ms_pre, split_part(m, '|', 2) as ms_pre3 from pg_temp.ms() m \gset
create temp table t_pre as
  select q, k, pg_temp.skus(q, k) as skus, pg_temp.xskus(q, k) as xskus
    from unnest(array['MNT54322', 'ORS2312', 'nim', 'shampoo', 'braid', 'Blue Dot', ' MNT54322 ', 'zzz-no-such']) q, unnest(array['single', 'set', 'all']) k;
select md5(string_agg(skus || '/' || xskus, ';' order by q, k)) as pre_md5, sum(length(skus)) as pre_len from t_pre \gset
select md5(p.prosrc) as list_md5_pre from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_list' \gset
select md5(string_agg(p.proname || '=' || obj_description(p.oid, 'pg_proc') || '/' || p.proacl::text, ' ' order by p.proname)) as meta_pre from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_list', 'product_export') \gset
\echo '── 기준: 검색어 없음 single 100 줄 최소' :ms_pre 'ms (' :ms_pre3 ') · 시퀀스' :seq_n '· SKU·이름 검색 24 짝 md5' :pre_md5 '· product_list md5' :list_md5_pre
\if :{?mig}
\echo '── 시험 적용:' :mig
\i :mig
\endif

-- ── B 바코드 ──
select pg_temp.chk('B1 낱개 바코드 696399120131 → Singles 그 낱개 1 줄', pg_temp.skus('696399120131', 'single'), 'NIM12013|1');
select pg_temp.chk('B2 낱개 바코드 → Sets 0 줄(세트는 따라오지 않는다) · All 1 줄', pg_temp.skus('696399120131', 'set') || ' ' || pg_temp.skus('696399120131', 'all'), '|0 NIM12013|1');
select pg_temp.chk('B3 세트 바코드 10071409543228 → Singles 부모 낱개 · Sets 세트 · All 둘',
  pg_temp.skus('10071409543228', 'single') || ' ' || pg_temp.skus('10071409543228', 'set') || ' ' || pg_temp.skus('10071409543228', 'all'), 'MNT54322|1 MNT54322-6|1 MNT54322,MNT54322-6|2');
select pg_temp.chk('B4 부모의 제 바코드 071409543221 → Singles 부모 · Sets 0(낱개 바코드로 세트는 안 나옴)', pg_temp.skus('071409543221', 'single') || ' ' || pg_temp.skus('071409543221', 'set'), 'MNT54322|1 |0');
-- 꺼진 바코드: 지금 데이터엔 꺼진 줄이 0 — 한 줄을 트랜잭션 안에서 끄고(트리거 끔 · rollback) 본다
set local session_replication_role = replica;
update public.product_barcode set is_active = false where barcode = '696399120131';
set local session_replication_role = origin;
select pg_temp.chk('B5 꺼진 바코드 696399120131 → Singles 0 · All 0', pg_temp.skus('696399120131', 'single') || ' ' || pg_temp.skus('696399120131', 'all'), '|0 |0');
set local session_replication_role = replica;
update public.product_barcode set is_active = true where barcode = '696399120131';
set local session_replication_role = origin;
select pg_temp.chk('B6 바코드 앞 6 자리 100714 · 696399 → 0 줄(All) · SKU·이름에 그 글자 든 제품 0(우연 일치 없음 실측)',
  pg_temp.skus('100714', 'all') || ' ' || pg_temp.skus('696399', 'all') || ' ' || (select count(*) from public.product where sku ilike '%100714%' or name ilike '%100714%' or sku ilike '%696399%' or name ilike '%696399%')::text, '|0 |0 0');
select pg_temp.chk('B7 앞뒤 띄어쓰기는 btrim(「  10071409543228  」 → 세트) — 줄바꿈 · 탭은 지금처럼 안 깎는다(btrim 기본 = 공백만 · SKU 검색도 같다 · 범위 밖)', pg_temp.skus('  10071409543228  ', 'set') || ' ' || pg_temp.skus(E'10071409543228\n', 'set'), 'MNT54322-6|1 |0');
select pg_temp.chk('B8 빈 검색어 · 공백만 → 거르지 않음(single total = 낱개 전체 수)', pg_temp.skus('   ', 'single'), pg_temp.skus(null, 'single'));

-- ── U 무변(SKU · 이름 검색 앞뒤 · export 앞뒤) ──
select pg_temp.chk('U1 SKU · 이름 검색 8 어 × 3 보기 = 24 짝 · product_list 와 product_export 둘 다 앞뒤 같음',
  (select md5(string_agg(pg_temp.skus(q, k) || '/' || pg_temp.xskus(q, k), ';' order by q, k)) from t_pre), :'pre_md5');
select pg_temp.chk('U2 비교가 빈 것이 아니다(앞 결과 글자 수 > 0)', (:pre_len > 0)::text, 'true');

-- ── X export 같은 규칙 ──
select pg_temp.chk('X1 product_export 세트 바코드 → Singles 부모 · Sets 세트 · All 둘(product_list 와 같음)',
  pg_temp.xskus('10071409543228', 'single') || ' ' || pg_temp.xskus('10071409543228', 'set') || ' ' || pg_temp.xskus('10071409543228', 'all'), 'MNT54322|1 MNT54322-6|1 MNT54322,MNT54322-6|2');
select pg_temp.chk('X2 product_export 낱개 바코드 → 그 낱개만 · 일부 일치 0', pg_temp.xskus('696399120131', 'all') || ' ' || pg_temp.xskus('100714', 'all'), 'NIM12013|1 |0');
select pg_temp.chk('X3 product_export barcodes 칸과 함께(pick 안 바코드 잇기 그대로)',
  (select x -> 'rows' -> 0 ->> 1 from public.product_export(p_q => '10071409543228', p_kind => 'set', p_columns => array['sku', 'barcodes']) x), '10071409543228');

-- ── E explain(색인 · null 이면 안 돈다) — 함수 몸과 같은 조건을 같은 글로(plpgsql 안의 문장은 explain 이 못 본다 · E1 · E2 가 글이 같음을 확인) ──
\echo '── explain (바코드 검색어) ──'
explain (analyze, costs off, timing off, summary off)
select p.id from public.product p
where ('10071409543228' is null or p.sku ilike '%' || '10071409543228' || '%' or p.name ilike '%' || '10071409543228' || '%'
       or p.id in (select b.product_id from public.product_barcode b where b.is_active and b.barcode = '10071409543228'
                   union all
                   select s.parent_product_id from public.product_barcode b join public.product s on s.id = b.product_id where b.is_active and b.barcode = '10071409543228' and s.parent_product_id is not null))
order by p.sku, p.id limit 100;
\echo '── explain (검색어 null · 매개변수 $1 · generic plan = plpgsql 변수와 같은 꼴 — 바코드 SubPlan 은 never executed 여야) ──'
set local plan_cache_mode = force_generic_plan;
prepare pbc1_null (text) as
select p.id from public.product p
where ($1 is null or p.sku ilike '%' || $1 || '%' or p.name ilike '%' || $1 || '%'
       or p.id in (select b.product_id from public.product_barcode b where b.is_active and b.barcode = $1
                   union all
                   select s.parent_product_id from public.product_barcode b join public.product s on s.id = b.product_id where b.is_active and b.barcode = $1 and s.parent_product_id is not null))
order by p.sku, p.id limit 100;
explain (analyze, costs off, timing off, summary off) execute pbc1_null(null);
deallocate pbc1_null;
set local plan_cache_mode = auto;
select pg_temp.chk('E1 함수 몸(product_list)에 위 explain 과 같은 조건 글이 있다(b.is_active and b.barcode = v_q · union all · s.parent_product_id is not null)',
  (select (p.prosrc like '%b.is_active and b.barcode = v_q%' and p.prosrc like '%union all%' and p.prosrc like '%s.parent_product_id is not null))%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_list'), 'true');
select pg_temp.chk('E2 함수 몸(product_export)에 같은 조건($1)', (select (p.prosrc like '%b.is_active and b.barcode = $1%' and p.prosrc like '%b.barcode = $1 and s.parent_product_id is not null))%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_export'), 'true');
select split_part(m, '|', 1)::numeric as ms_post, split_part(m, '|', 2) as ms_post3 from pg_temp.ms() m \gset
\echo '── 검색어 없음 single 100 줄 최소: 앞' :ms_pre 'ms (' :ms_pre3 ') · 뒤' :ms_post 'ms (' :ms_post3 ')'
select pg_temp.chk('E3 검색어 없음 시간 뒤 ≤ 앞 × 1.5 + 20ms(흔들림 여유 · 수치는 위 줄)', (:ms_post <= :ms_pre * 1.5 + 20)::text, 'true');

-- ── M 메타(무변) ──
select pg_temp.chk('M1 시그니처 · 반환 꼴 둘 그대로',
  (select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')→' || left(pg_get_function_result(p.oid), 5), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_list', 'product_export')),
  'product_export(p_q text, p_brand_name text, p_category_name text, p_supplier_id uuid, p_kind text, p_only_active boolean, p_sale_only boolean, p_columns text[])→jsonb product_list(p_q text, p_brand_name text, p_category_name text, p_supplier_id uuid, p_kind text, p_only_active boolean, p_sale_only boolean, p_limit integer, p_offset integer)→TABLE');
select pg_temp.chk('M2 product_list invoker · product_export definer · 둘 stable · search_path 그대로',
  (select string_agg(p.proname || ':' || p.prosecdef::text || ':' || p.provolatile::text || ':' || array_to_string(p.proconfig, ','), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_list', 'product_export')),
  'product_export:true:s:search_path=public, pg_temp product_list:false:s:search_path=public, pg_temp');
select pg_temp.chk('M3 acl 그대로(list: authenticated · service_role · export: authenticated) · anon 0',
  (select string_agg(p.proname || ':' || p.proacl::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_list', 'product_export')) || ' ' ||
  (has_function_privilege('anon', 'public.product_list(text, text, text, uuid, text, boolean, boolean, int, int)', 'execute') or has_function_privilege('anon', 'public.product_export(text, text, text, uuid, text, boolean, boolean, text[])', 'execute'))::text,
  'product_export:{postgres=X/postgres,authenticated=X/postgres} product_list:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} false');
select pg_temp.chk('M4 comment · acl 둘 통째로 앞뒤 같음(md5)',
  (select md5(string_agg(p.proname || '=' || obj_description(p.oid, 'pg_proc') || '/' || p.proacl::text, ' ' order by p.proname)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_list', 'product_export')), :'meta_pre');
set local role authenticated;
select coalesce(string_agg(l.sku, ',' order by l.sku), '') || '|' || coalesce(max(l.total), 0)::text as auth_list from public.product_list(p_q => '10071409543228', p_kind => 'all') l \gset
select (select coalesce(string_agg(r ->> 0, ',' order by r ->> 0), '') from jsonb_array_elements(x -> 'rows') r) || '|' || (x ->> 'total') as auth_export from public.product_export(p_q => '10071409543228', p_kind => 'all', p_columns => array['sku']) x \gset
reset role;
select pg_temp.chk('M5 authenticated 역할(RLS 길)로 세트 바코드 검색 — product_list · product_export 둘 다 All 둘', :'auth_list' || ' ' || :'auth_export', 'MNT54322,MNT54322-6|2 MNT54322,MNT54322-6|2');

-- ── W WHERE 정적(REST 두 겹 ①) ──
select pg_temp.chk('W1 둘 다 깊이 0 WHERE 없는 update · delete 0(읽기만)',
  (select string_agg(p.proname || ' ' || pg_temp.nowhere(p.prosrc)::text, ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_list', 'product_export')), 'product_export 0 · product_list 0');

-- ── Q 시퀀스(살아 있는 DB) ──
-- 메인은 살아 있는 DB — 다른 사람 · cron 이 올린 시퀀스는 이 시험 탓이 아니다 · 이 시험의 쓰기 길이 닿을 수 있는 것(product_barcode update → shop_queue_trigger → shop_push_queue_id_seq)만 무변을 묻고 · 나머지 움직임은 이름 · 앞뒤 값으로 보인다
select pg_temp.chk('Q1 shop_push_queue_id_seq 무변(바코드 update 의 트리거를 끈 증거) · 이 스크립트의 temp 표 serial 은 뺀다',
  (select string_agg(a.sequencename || ':' || coalesce(a.last_value::text, '-') || '→' || coalesce(b.last_value::text, '-'), ' ') from t_seq_pre a join pg_sequences b using (schemaname, sequencename) where a.sequencename = 'shop_push_queue_id_seq' and a.last_value is distinct from b.last_value), null);
select 'Q2 info · 시험 동안 움직인 다른 시퀀스(' || :seq_n || ' 개 중 · 살아 있는 DB 의 다른 활동): ' || coalesce((select string_agg(a.schemaname || '.' || a.sequencename || ' ' || coalesce(a.last_value::text, '-') || '→' || coalesce(b.last_value::text, '-'), ' · ' order by a.sequencename) from t_seq_pre a join pg_sequences b using (schemaname, sequencename) where a.last_value is distinct from b.last_value), '(없음)') as seq_moves;

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(상호 없음 · 쓰기 한 줄은 rollback) ──'
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, 23 as expect_total from t_res;
select 'FAIL ' || label || format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) as fail_line from t_res where not ok order by n;
select 'OK ' || label as ok_line from t_res where ok order by n;
rollback;
select (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_list') = :'list_md5_pre' as list_rolled_back,
       (select is_active from public.product_barcode where barcode = '696399120131') as barcode_active_again,
       (select last_value from pg_sequences where sequencename = 'shop_push_queue_id_seq') as shop_push_seq_now;
