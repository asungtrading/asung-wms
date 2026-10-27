-- supabase/tests/combo_1b_check.sql — combo-1b 「New combo 에서 sku_prefix 알림 빼기」 서버 쪽 검증 (2026-10-27 · 판정 826 ~ 828)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞 · 잠금 없음: 행 수 · 함수 md5 일곱 · 권한)
--   → begin → (-v mig 면 \i) → 꼴(F) · md5(M) · 권한(P) · 정적 safeupdate(S) · 가짜 재료(CB2-* · 직원 combo1b-w@test.invalid · master 열쇠 · 브랜드에 낱개 둘 → 앞글자 CB)로 갈래 1 ~ 4 → rollback → 실제 행 무변(R)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027202949_combo_1b.sql -f supabase/tests/combo_1b_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 19 · 확인(적용 뒤 · -v mig 없음) 18 — M1(combo_create md5 ≠ 적용 전 · 적용 전 = combo-1 ad702b96)은 「적용 전 기준」 이 있어야 성립해 시험 갈래에서만 돈다
--   적용 전 마른 실행(-v mig 없음)은 combo-1 본문이라 F2 · M3 · 1a · 3a · 3b · 3c 가 MISMATCH(정상 · sku_prefix 가 뜨고 commit 이 그 ack 를 기다린다) — 실측 2026-10-27: OK 12 · MISMATCH 6 · ERROR 0
--   쓰기 0 — 가짜 재료는 rollback · 시퀀스 없음(product · product_bom · ims_staff · ref_brand 는 uuid)
--   ⚠️ REST 한 번은 적용 뒤에만 가능 — 아래 R0 주석의 curl(미리 보기 · 쓰기 0)을 Caleb 이 화면 차수에서 돌린다
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 19
\else
\set EXPECT_OK 18
\endif
\pset pager off
-- 기준(begin 앞 · 잠금 없음)
select (select count(*) from public.product) as n_product, (select count(*) from public.product_bom) as n_bom, (select count(*) from public.product_bom where is_active) as n_bom_act,
       (select count(*) from public.ims_staff) as n_staff, (select count(*) from public.ref_brand) as n_brand,
       (select count(*) from public.product_barcode) as n_bc, (select count(*) from public.product_price) as n_price,
       (select coalesce(md5(p.prosrc), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create') as md5_combo_create_0,
       (select coalesce(string_agg(md5(p.prosrc), ' ' order by p.proname), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('product_create_core', 'product_create', 'product_list', 'product_bom_set', 'product_bom_check_lines', 'product_combo_list')) as md5_others_0,
       (select value from public.inv_config where key = 'db_role') as db_role
\gset
\echo '── db_role' :db_role '· product' :n_product '· bom' :n_bom '(active' :n_bom_act ') · combo_create md5' :md5_combo_create_0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
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
create function pg_temp.j(p text) returns jsonb language plpgsql as $$
begin
  if p is null or left(p, 1) not in ('[', '{') then return null; end if;
  return p::jsonb;
end $$;
create function pg_temp.src(p_name text) returns text language sql as $$
  select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = p_name
$$;
-- 응답의 code 목록(blocks 또는 warnings) — 정렬 · 쉼표
create function pg_temp.codes(p jsonb, p_arr text) returns text language sql as $$
  select coalesce(string_agg(x->>'code', ',' order by x->>'code'), '') from jsonb_array_elements(coalesce(p->p_arr, '[]'::jsonb)) x
$$;
-- 마지막 정의의 깊이 0 WHERE 없는 update · delete 를 센다(combo_1_check.sql 과 같은 것 · REST safeupdate 21000 의 정적 겹)
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

-- ── F 꼴: product_combo_create 하나 · definer volatile · search_path · comment 머리 combo-1 + combo-1b 표시 ──
select pg_temp.chk('F1 product_combo_create: one overload · definer · volatile · search_path',
  (select coalesce(string_agg(p.prosecdef || ':' || p.provolatile::text || ':' || (p.proconfig::text ~ 'search_path=public, pg_temp')::text, ' '), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create'),
  'true:v:true');
select pg_temp.chk('F2 comment starts combo-1 · mentions combo-1b(판정 826) · warnings minus supplier_missing · sku_prefix',
  (select left(c, 7) || ' ' || (c ~ 'combo-1b\(판정 826\)')::text || ' ' || (c ~ 'warnings minus supplier_missing · sku_prefix')::text
     from (select coalesce(obj_description(to_regprocedure('public.product_combo_create(jsonb, jsonb, boolean, text[])'), 'pg_proc'), '') as c) x),
  'combo-1 true true');

-- ── M md5: combo_create 바뀜(시험 갈래만) · 나머지 여섯 무변 · 본문에 두 자리 ──
\if :{?mig}
select pg_temp.chk('M1 product_combo_create body changed (md5 ≠ before) — before was combo-1 ad702b96',
  ((select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create') <> :'md5_combo_create_0' and :'md5_combo_create_0' = 'ad702b9688307091fa737c2f46db62fd')::text, 'true');
\endif
select pg_temp.chk('M2 core · product_create · product_list · product_bom_set · product_bom_check_lines · product_combo_list untouched (md5 = before)',
  ((select coalesce(string_agg(md5(p.prosrc), ' ' order by p.proname), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('product_create_core', 'product_create', 'product_list', 'product_bom_set', 'product_bom_check_lines', 'product_combo_list')) = :'md5_others_0')::text, 'true');
select pg_temp.chk('M3 combo_create body: preview filter in (supplier_missing, sku_prefix) · commit ack array[…:supplier_missing, …:sku_prefix] · helper · core · bom insert',
  (coalesce(pg_temp.src('product_combo_create'), '') ~ $r$in \('supplier_missing', 'sku_prefix'\) then continue$r$
   and coalesce(pg_temp.src('product_combo_create'), '') ~ $r$array\[v_sku \|\| ':supplier_missing', v_sku \|\| ':sku_prefix'\]$r$
   and coalesce(pg_temp.src('product_combo_create'), '') ~ 'public\.product_bom_check_lines\(' and coalesce(pg_temp.src('product_combo_create'), '') ~ 'public\.product_create_core\('
   and coalesce(pg_temp.src('product_combo_create'), '') ~ 'insert into public\.product_bom')::text, 'true');

-- ── P 권한: authenticated 만 · acl 문자열 combo-1 그대로 · product_bom 닫힌 채 ──
select pg_temp.chk('P1 product_combo_create: authenticated yes · anon no · service_role no · acl = {postgres,authenticated}',
  has_function_privilege('authenticated', 'public.product_combo_create(jsonb, jsonb, boolean, text[])', 'execute')::text || '/' || has_function_privilege('anon', 'public.product_combo_create(jsonb, jsonb, boolean, text[])', 'execute')::text
  || '/' || has_function_privilege('service_role', 'public.product_combo_create(jsonb, jsonb, boolean, text[])', 'execute')::text
  || ' ' || coalesce((select p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create'), '(none)'),
  'true/false/false {postgres=X/postgres,authenticated=X/postgres}');
select pg_temp.chk('P2 product_bom still closed: authenticated insert/update/delete false · one policy',
  (has_table_privilege('authenticated', 'public.product_bom', 'insert') or has_table_privilege('authenticated', 'public.product_bom', 'update') or has_table_privilege('authenticated', 'public.product_bom', 'delete'))::text
  || ' ' || (select count(*) from pg_policies where schemaname = 'public' and tablename = 'product_bom'), 'false 1');

-- ── S 정적: REST safeupdate — 마지막 정의의 깊이 0 WHERE 없는 update · delete = 0 ──
select pg_temp.chk('S0 scanner self-test', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text, '101');
select pg_temp.chk('S1 no WHERE-less update/delete in product_combo_create · product_bom_set · product_bom_check_lines',
  (select coalesce(string_agg(p.proname || ' ' || pg_temp.nowhere(p.prosrc), ' · ' order by p.proname), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_bom_set', 'product_combo_create', 'product_bom_check_lines')),
  'product_bom_check_lines 0 · product_bom_set 0 · product_combo_create 0');

-- ── 가짜 재료: 직원(master) · 브랜드 CB2 에 켜진 낱개 둘(CB2-C1 · CB2-C2 → 브랜드 앞글자 집합 = {CB}) · 콤보 SKU CBRCOMBO9(앞글자 CBRCOMBO ≠ CB → core R1 이 sku_prefix 를 낸다 · TBRCOMBO9 꼴) ──
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values
  (gen_random_uuid(), 'combo1b-w@test.invalid', 'COMBO1B master write', 'manager', '["ims","master"]', '{}'),
  (gen_random_uuid(), 'combo1b-z@test.invalid', 'COMBO1B no key', 'manager', '["ims"]', '{}');
select auth_user_id::text as uid, id::text as sid from public.ims_staff where email = 'combo1b-w@test.invalid' \gset
select auth_user_id::text as uid_z from public.ims_staff where email = 'combo1b-z@test.invalid' \gset
insert into public.ref_brand (name, source) values ('CB2 Brand', 'manual') returning id::text as br \gset
select id::text as unit from public.ref_unit where is_active order by name limit 1 \gset
select id::text as tier from public.ref_price_tier where purpose = 'sale' and is_active order by name limit 1 \gset
insert into public.product (sku, name, brand_id, source, is_active, sellable) values
  ('CB2-C1', 'CB2 component 1', :'br'::uuid, 'manual', true, true), ('CB2-C2', 'CB2 component 2', :'br'::uuid, 'manual', true, true);
select pg_temp.chk('X0 fixture: brand CB2 has 2 active singles · prefix set = CB · combo SKU prefix = CBRCOMBO',
  (select count(*)::text || ' ' || string_agg(distinct substring(p.sku from '^[A-Z]+'), ',') from public.product p where p.brand_id = :'br'::uuid and p.is_active and p.parent_product_id is null)
  || ' ' || substring('CBRCOMBO9' from '^[A-Z]+'), '2 CB CBRCOMBO');
select set_config('request.jwt.claims', json_build_object('sub', :'uid', 'role', 'authenticated')::text, true) \gset
\set item '{"sku":"CBRCOMBO9","name":"CB2 combo nine","brand_id":"' :br '","unit_id":"' :unit '","barcodes":[],"prices":[{"tier_id":"' :tier '","price":19.99}]}'
\set lines '[{"sku":"CB2-C1","qty":1},{"sku":"CB2-C2","qty":2}]'

-- ── 갈래 1: New combo 미리 보기 → sku_prefix · supplier_missing 둘 다 없음 · barcode_missing 은 남음 ──
set local role authenticated;
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, %L::jsonb, false, '{}')::text$q$, :'item', :'lines')) as r1p \gset
-- ── 갈래 2: 같은 p_item 을 일반 product_create 미리 보기 → sku_prefix 가 여전히 뜬다(일반 길 무변) · commit 전에 부른다(뒤면 sku_exists 가 막는다) ──
select pg_temp.run(format($q$select public.product_create(jsonb_build_array(%L::jsonb), false, '{}')::text$q$, :'item')) as r2p \gset
-- ── 갈래 3: commit — ack 없음 → unacked 는 barcode_missing 만(sku_prefix 가 끼지 않는다) · ack = barcode_missing 만 → committed true ──
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, %L::jsonb, true, '{}')::text$q$, :'item', :'lines')) as r3n \gset
select (select count(*) from public.product where sku = 'CBRCOMBO9')::text as c3n \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, %L::jsonb, true, array['CBRCOMBO9:barcode_missing'])::text$q$, :'item', :'lines')) as r3c \gset
reset role;
select pg_temp.chk('1a combo preview: committed false · blocks none · warnings = barcode_missing only (no sku_prefix · no supplier_missing) · components 2',
  coalesce(pg_temp.j(:'r1p')->>'committed', :'r1p') || ' [' || pg_temp.codes(pg_temp.j(:'r1p'), 'blocks') || '] [' || pg_temp.codes(pg_temp.j(:'r1p'), 'warnings') || '] ' || coalesce(jsonb_array_length(pg_temp.j(:'r1p')->'components')::text, '-'),
  'false [] [barcode_missing] 2');
select pg_temp.chk('1b combo preview: unacked [] (preview never lists)', coalesce((pg_temp.j(:'r1p')->'unacked')::text, :'r1p'), '[]');
select pg_temp.chk('2a general product_create preview of the same item: committed false · blocks none · warnings include sku_prefix and barcode_missing',
  coalesce(pg_temp.j(:'r2p')->>'committed', :'r2p') || ' [' || pg_temp.codes(pg_temp.j(:'r2p'), 'blocks') || '] ' || (pg_temp.codes(pg_temp.j(:'r2p'), 'warnings') ~ '(^|,)sku_prefix(,|$)')::text || ' ' || (pg_temp.codes(pg_temp.j(:'r2p'), 'warnings') ~ '(^|,)barcode_missing(,|$)')::text,
  'false [] true true');
select pg_temp.chk('2b general preview warning codes (record) · sku_prefix message names CB',
  pg_temp.codes(pg_temp.j(:'r2p'), 'warnings') || ' ' || (select coalesce((x->>'message') ~ 'CB2 Brand products start with CB$', false)::text from jsonb_array_elements(coalesce(pg_temp.j(:'r2p')->'warnings', '[]'::jsonb)) x where x->>'code' = 'sku_prefix'),
  'barcode_missing,sku_prefix,supplier_missing true');
select pg_temp.chk('3a commit without ack → committed false · unacked = CBRCOMBO9:barcode_missing only · no product',
  coalesce(pg_temp.j(:'r3n')->>'committed', :'r3n') || ' ' || coalesce((pg_temp.j(:'r3n')->'unacked')::text, '-') || ' ' || :'c3n', 'false ["CBRCOMBO9:barcode_missing"] 0');
select pg_temp.chk('3b commit with ack barcode_missing only → committed true · added 2 · warnings = barcode_missing · unacked []',
  coalesce(pg_temp.j(:'r3c')->>'committed', :'r3c') || ' ' || coalesce(pg_temp.j(:'r3c')->>'added', '-') || ' [' || pg_temp.codes(pg_temp.j(:'r3c'), 'warnings') || '] ' || coalesce((pg_temp.j(:'r3c')->'unacked')::text, '-') || ' ' || coalesce(pg_temp.j(:'r3c')->'items'->0->>'sku', '-'),
  'true 2 [barcode_missing] [] CBRCOMBO9');
select coalesce((select id::text from public.product where sku = 'CBRCOMBO9'), '00000000-0000-0000-0000-000000000000') as combo9 \gset
select pg_temp.chk('3c CBRCOMBO9 row: one product · source manual · active · brand CB2 · price 1 · bom rows 2 active manual · updated_by fake staff · so_combo_is true',
  (select count(*) from public.product where sku = 'CBRCOMBO9')::text || ' ' || (select p.source || ' ' || p.is_active || ' ' || (p.brand_id::text = :'br') from public.product p where p.id = :'combo9'::uuid) || ' ' || (select count(*) from public.product_price where product_id = :'combo9'::uuid)
  || ' ' || (select count(*) || '/' || count(*) filter (where is_active and source = 'manual' and updated_by::text = :'sid') from public.product_bom where parent_product_id = :'combo9'::uuid)
  || ' ' || public.so_combo_is(:'combo9'::uuid), '1 manual true true 1 2/2 true');
select pg_temp.chk('3d components echoed in commit response = C1×1 C2×2',
  (select coalesce(string_agg(x->>'sku' || 'x' || trim_scale((x->>'qty')::numeric), ' ' order by x->>'sku'), '-') from jsonb_array_elements(pg_temp.j(:'r3c')->'components') x), 'CB2-C1x1 CB2-C2x2');

-- ── 갈래 4: 권한 길 — 열쇠 없는 직원은 거부 · 저장 0 ──
select set_config('request.jwt.claims', json_build_object('sub', :'uid_z', 'role', 'authenticated')::text, true) \gset
\set item2 '{"sku":"CBRCOMBO8","name":"CB2 combo eight","brand_id":"' :br '","unit_id":"' :unit '","prices":[{"tier_id":"' :tier '","price":5}]}'
set local role authenticated;
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, %L::jsonb, true, array['CBRCOMBO8:barcode_missing'])::text$q$, :'item2', :'lines')) as r4a \gset
reset role;
select pg_temp.chk('4a no master key → refused (ERR) · CBRCOMBO8 not created', left(:'r4a', 3) || ' ' || (select count(*) from public.product where sku = 'CBRCOMBO8'), 'ERR 0');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.product) = :n_product as product_same, (select count(*) from public.product_bom) = :n_bom as bom_same,
       (select count(*) from public.product_bom where is_active) = :n_bom_act as bom_active_same, (select count(*) from public.ims_staff) = :n_staff as staff_same,
       (select count(*) from public.ref_brand) = :n_brand as brand_same, (select count(*) from public.product_barcode) = :n_bc as barcode_same, (select count(*) from public.product_price) = :n_price as price_same,
       (select count(*) from public.product where sku like 'CB2-%' or sku like 'CBRCOMBO%') = 0 as no_cb2_rows,
       (select coalesce(md5(p.prosrc), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create') = :'md5_combo_create_0' as combo_create_md5_same_as_before,
       (select coalesce(string_agg(md5(p.prosrc), ' ' order by p.proname), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('product_create_core', 'product_create', 'product_list', 'product_bom_set', 'product_bom_check_lines', 'product_combo_list')) = :'md5_others_0' as others_md5_same;
-- R0 REST(적용 뒤 · Caleb · 화면 차수에서 · 미리 보기만 = 쓰기 0 · 직원 토큰은 tools/shopify-ping.sh 의 로그인 꼴로 받는다 · U=테스트 프로젝트 URL · T=access_token · A=anon key · B=브랜드 id(제품이 있는 브랜드 · 예 TBR)):
--   curl -sS "$U/rest/v1/rpc/product_combo_create" -H "apikey: $A" -H "Authorization: Bearer $T" -H "Content-Type: application/json" -d '{"p_item":{"sku":"TBRCOMBO9","name":"rest preview","brand_id":"'"$B"'","barcodes":[],"prices":[]},"p_lines":[{"sku":"UNF18250","qty":1},{"sku":"UNF18251","qty":1}],"p_commit":false,"p_ack":[]}'
--   기대: committed false · blocks [] · warnings 에 barcode_missing · price_missing(sku_prefix · supplier_missing 없음) · 21000 없음
