-- supabase/tests/combo_1_check.sql — combo-1 「콤보는 New combo 에서만」 서버 쪽 검증 (2026-10-27 · 판정 810 · 817 ~ 825)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞 · 잠금 없음: 행 수 · 함수 md5 · 권한)
--   → begin → (-v mig 면 \i) → 꼴(F) · 권한(P) · 정적 safeupdate(S) · 가짜 재료(CB1-* · 직원 combo1-w@test.invalid · master 열쇠)로 갈래 1 ~ 7 → rollback → 실제 행 무변(R)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027191301_combo_1.sql -f supabase/tests/combo_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 55 · 확인(적용 뒤 · -v mig 없음) 54 — M1(product_bom_set md5 ≠ 적용 전 md5)은 「적용 전 기준」 이 있어야 성립해 시험 갈래에서만 돈다
--   적용 전 마른 실행(-v mig 없음)은 새 함수 셋이 없어 F · P · 갈래 대부분이 MISMATCH(정상) — 실측 2026-10-27: OK 10 · MISMATCH 44 · ERROR 0
--   쓰기 0 — 가짜 재료는 rollback · 시퀀스 없음(product · product_bom · ims_staff · ref_brand 는 uuid) · 실제 콤보 UNF18155 · 낱개 ABC59138 은 읽고 창구로만 건드리며 rollback
--   갈래 8(도우미 옮김 diff) · 9(product_bom_set 재발행 diff)는 파일 대 파일 — bash diff 로(보고에 원문) · 여기서는 md5 로 「파일의 함수 = DB 의 함수」 만 본다
--   ⚠️ REST 한 번씩은 적용 뒤에만 가능(새 함수가 적용 전 DB 에 없다) — 아래 R0 주석의 curl 셋(미리 보기 · 쓰기 0)을 Caleb 이 돌린다
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 55
\else
\set EXPECT_OK 54
\endif
\pset pager off
-- 기준(begin 앞 · 잠금 없음)
select (select count(*) from public.product) as n_product, (select count(*) from public.product_bom) as n_bom, (select count(*) from public.product_bom where is_active) as n_bom_act,
       (select count(*) from public.ims_staff) as n_staff, (select count(*) from public.ref_brand) as n_brand,
       (select count(*) from public.product_barcode) as n_bc, (select count(*) from public.product_price) as n_price,
       (select count(distinct parent_product_id) from public.product_bom where is_active) as n_combo0,
       (select coalesce(md5(p.prosrc), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_set') as md5_bom_set_0,
       (select coalesce(md5(p.prosrc), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create_core') as md5_core_0,
       (select coalesce(md5(p.prosrc), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create') as md5_create_0,
       (select coalesce(md5(p.prosrc), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_list') as md5_list_0,
       (select value from public.inv_config where key = 'db_role') as db_role
\gset
\echo '── db_role' :db_role '· product' :n_product '· bom' :n_bom '(active' :n_bom_act ') · combos' :n_combo0 '· bom_set md5' :md5_bom_set_0
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
-- 마지막 정의의 깊이 0 WHERE 없는 update · delete 를 센다(ar_2b_check.sql 과 같은 것 · REST safeupdate 21000 의 정적 겹)
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

-- ── F 꼴: 함수 넷 하나씩 · definer/invoker · search_path · 반환 · comment 머리 ──
select pg_temp.chk('F1 four functions, one overload each',
  (select coalesce(string_agg(p.proname || ':' || c, ' ' order by p.proname), '(none)') from (select proname, count(*) c from pg_proc where pronamespace = 'public'::regnamespace and proname in ('product_bom_check_lines', 'product_combo_create', 'product_combo_list', 'product_bom_set') group by proname) p),
  'product_bom_check_lines:1 product_bom_set:1 product_combo_create:1 product_combo_list:1');
select pg_temp.chk('F2 definer: helper · bom_set · combo_create (volatile/stable) · list invoker stable',
  (select coalesce(string_agg(p.proname || ':' || p.prosecdef || ':' || p.provolatile::text, ' ' order by p.proname), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_bom_check_lines', 'product_combo_create', 'product_combo_list', 'product_bom_set')),
  'product_bom_check_lines:true:s product_bom_set:true:v product_combo_create:true:v product_combo_list:false:s');
select pg_temp.chk('F3 search_path on all four',
  (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proconfig::text ~ 'search_path=public, pg_temp' and p.proname in ('product_bom_check_lines', 'product_combo_create', 'product_combo_list', 'product_bom_set')), '4');
select pg_temp.chk('F4 product_combo_list returns (id, sku, name, is_active, component_count, components, released, total)',
  coalesce(pg_get_function_result(to_regprocedure('public.product_combo_list(text, boolean, boolean, int, int)')), '(none)'),
  'TABLE(id uuid, sku text, name text, is_active boolean, component_count integer, components text, released boolean, total bigint)');
select pg_temp.chk('F5 comments start combo-1 (helper · create · list) · bom_set asm-1 · combo-1',
  (select coalesce(string_agg(left(obj_description(p.oid, 'pg_proc'), 7), ' ' order by p.proname), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_bom_check_lines', 'product_combo_create', 'product_combo_list', 'product_bom_set')),
  'combo-1 asm-1(판 combo-1 combo-1');
\if :{?mig}
select pg_temp.chk('M1 product_bom_set body changed (md5 ≠ before) — before was asm-1 5095ab16',
  ((select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_set') <> :'md5_bom_set_0' and :'md5_bom_set_0' = '5095ab16f3e72f6222dab75775294d0e')::text, 'true');
\endif
select pg_temp.chk('M2 product_create_core · product_create · product_list untouched (md5 = before)',
  ((select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create_core') = :'md5_core_0'
   and (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create') = :'md5_create_0'
   and (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_list') = :'md5_list_0')::text, 'true');
select pg_temp.chk('M3 bom_set body: parent_not_combo in · cin7_combo code out · calls helper · old inline loop gone',
  (coalesce(pg_temp.src('product_bom_set'), '') ~ 'code., .parent_not_combo' and coalesce(pg_temp.src('product_bom_set'), '') !~ 'code., .cin7_combo'
   and coalesce(pg_temp.src('product_bom_set'), '') ~ 'public\.product_bom_check_lines\(' and coalesce(pg_temp.src('product_bom_set'), '') !~ 'for v_e in select x from jsonb_array_elements\(p_lines\)')::text, 'true');

-- ── P 권한: 창구 둘 + bom_set = authenticated 만 · 도우미 = owner 만 · product_bom 닫힌 채 ──
select pg_temp.chk('P1 product_combo_create · product_combo_list · product_bom_set: authenticated yes · anon no',
  (select coalesce(string_agg(x.f || ':' || has_function_privilege('authenticated', x.f, 'execute') || '/' || has_function_privilege('anon', x.f, 'execute'), ' ' order by x.f), '(none)')
     from (values ('public.product_combo_create(jsonb, jsonb, boolean, text[])'), ('public.product_combo_list(text, boolean, boolean, int, int)'), ('public.product_bom_set(text, jsonb, jsonb, boolean, text[])')) x(f)
    where to_regprocedure(x.f) is not null),
  'public.product_bom_set(text, jsonb, jsonb, boolean, text[]):true/false public.product_combo_create(jsonb, jsonb, boolean, text[]):true/false public.product_combo_list(text, boolean, boolean, int, int):true/false');
select pg_temp.chk('P2 helper acl = owner only {postgres=X/postgres}',
  coalesce((select p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_check_lines'), '(none)'), '{postgres=X/postgres}');
select pg_temp.chk('P3 product_bom still closed: authenticated insert/update/delete false · one policy',
  (has_table_privilege('authenticated', 'public.product_bom', 'insert') or has_table_privilege('authenticated', 'public.product_bom', 'update') or has_table_privilege('authenticated', 'public.product_bom', 'delete'))::text
  || ' ' || (select count(*) from pg_policies where schemaname = 'public' and tablename = 'product_bom'), 'false 1');

-- ── S 정적: REST safeupdate — 마지막 정의의 깊이 0 WHERE 없는 update · delete = 0 (셋 다) ──
select pg_temp.chk('S0 scanner self-test', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text, '101');
select pg_temp.chk('S1 no WHERE-less update/delete in product_bom_set · product_combo_create · product_bom_check_lines',
  (select coalesce(string_agg(p.proname || ' ' || pg_temp.nowhere(p.prosrc), ' · ' order by p.proname), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_bom_set', 'product_combo_create', 'product_bom_check_lines')),
  'product_bom_check_lines 0 · product_bom_set 0 · product_combo_create 0');

-- ── 가짜 재료: 직원(master) · 브랜드(제품 0 → sku_prefix 알림 없음) · 낱개 넷(구성품 셋 + 이력 0 낱개 하나) ──
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values
  (gen_random_uuid(), 'combo1-w@test.invalid', 'COMBO1 master write', 'manager', '["ims","master"]', '{}');
select auth_user_id::text as uid, id::text as sid from public.ims_staff where email = 'combo1-w@test.invalid' \gset
insert into public.ref_brand (name, source) values ('CB1 Brand', 'manual') returning id::text as br \gset
select id::text as unit from public.ref_unit where is_active order by name limit 1 \gset
select id::text as tier from public.ref_price_tier where purpose = 'sale' and is_active order by name limit 1 \gset
insert into public.product (sku, name, source, is_active, sellable) values
  ('CB1-C1', 'CB1 component 1', 'manual', true, true), ('CB1-C2', 'CB1 component 2', 'manual', true, true), ('CB1-C3', 'CB1 component 3', 'manual', true, true),
  ('CB1-S0', 'CB1 plain single · no history', 'manual', true, true);
select set_config('request.jwt.claims', json_build_object('sub', :'uid', 'role', 'authenticated')::text, true) \gset
-- 실제 콤보 UNF18155(cin7 · 잔고 1 · 열린 오더 0) 의 지금 구성품 = p_old
select coalesce(jsonb_agg(jsonb_build_object('sku', c.sku, 'qty', b.quantity) order by c.sku), '[]'::jsonb)::text as old_unf
  from public.product_bom b join public.product c on c.id = b.component_product_id join public.product p on p.id = b.parent_product_id
 where p.sku = 'UNF18155' and b.is_active \gset
select (select count(*) from public.product_bom b join public.product p on p.id = b.parent_product_id where p.sku = 'UNF18155' and b.is_active)::text as n_unf,
       (select c.sku from public.product_bom b join public.product c on c.id = b.component_product_id join public.product p on p.id = b.parent_product_id where p.sku = 'UNF18155' and b.is_active order by c.sku limit 1) as unf_c1,
       (select coalesce(sum(x.qty), 0)::text from public.ims_inv_balance x join public.product p on p.id = x.product_id where p.sku = 'UNF18155') as unf_bal,
       (select count(*)::text from public.product_bom b join public.product p on p.id = b.parent_product_id where p.sku = 'ABC59138') as n_abc,
       (select (count(*) > 0)::text from public.inv_ledger l where l.sku = 'ABC59138') as abc_hist \gset
select pg_temp.chk('M0 real material: UNF18155 is a 6-component cin7 combo with balance 1 · ABC59138 has history and 0 bom rows',
  :'n_unf' || ' ' || :'unf_bal' || ' ' || :'n_abc' || ' ' || :'abc_hist', '6 1 0 true');

set local role authenticated;
-- ── 갈래 1 · 2: 낱개에 줄을 주면 막는다(이력 있음 ABC59138 · 이력 0 CB1-S0) — commit=true 로 불러도 저장 0 ──
select pg_temp.run($q$select public.product_bom_set('ABC59138', '[{"sku":"CB1-C1","qty":1},{"sku":"CB1-C2","qty":1}]'::jsonb, null, true, '{}')::text$q$) as r1 \gset
select pg_temp.run($q$select public.product_bom_set('CB1-S0', '[{"sku":"CB1-C1","qty":1},{"sku":"CB1-C2","qty":1}]'::jsonb, null, true, '{}')::text$q$) as r2 \gset
reset role;
select pg_temp.chk('1a ABC59138 (history · stock 13): blocked parent_not_combo · committed false',
  coalesce(pg_temp.j(:'r1')->>'committed', :'r1') || ' ' || pg_temp.codes(pg_temp.j(:'r1'), 'blocks'), 'false parent_not_combo');
select pg_temp.chk('1b ABC59138 message names Combos → New combo',
  coalesce((select x->>'message' from jsonb_array_elements(pg_temp.j(:'r1')->'blocks') x where x->>'code' = 'parent_not_combo'), '(none)'),
  'ABC59138 is not a combo — make a new combo SKU in Combos → New combo — nothing was saved');
select pg_temp.chk('1c ABC59138: 0 bom rows after (nothing saved)', (select count(*)::text from public.product_bom b join public.product p on p.id = b.parent_product_id where p.sku = 'ABC59138'), '0');
select pg_temp.chk('2a CB1-S0 (no history): blocked parent_not_combo too (817 asks no reason)',
  coalesce(pg_temp.j(:'r2')->>'committed', :'r2') || ' ' || pg_temp.codes(pg_temp.j(:'r2'), 'blocks'), 'false parent_not_combo');
select pg_temp.chk('2b CB1-S0: 0 bom rows after', (select count(*)::text from public.product_bom b join public.product p on p.id = b.parent_product_id where p.sku = 'CB1-S0'), '0');

-- ── 갈래 3: 이미 콤보(UNF18155 · cin7)의 구성품 고치기 — 지금처럼 · cin7_combo 없음 · parent_stock 그대로 ──
select (jsonb_agg(case when x->>'sku' = :'unf_c1' then jsonb_build_object('sku', x->>'sku', 'qty', (x->>'qty')::numeric + 1) else x end order by x->>'sku'))::text as new_unf
  from jsonb_array_elements(:'old_unf'::jsonb) x \gset
set local role authenticated;
select pg_temp.run(format($q$select public.product_bom_set('UNF18155', %L::jsonb, %L::jsonb, false, '{}')::text$q$, :'new_unf', :'old_unf')) as r3p \gset
select pg_temp.run(format($q$select public.product_bom_set('UNF18155', %L::jsonb, %L::jsonb, true, '{}')::text$q$, :'new_unf', :'old_unf')) as r3u \gset
select pg_temp.run(format($q$select public.product_bom_set('UNF18155', %L::jsonb, %L::jsonb, true, array['combo:UNF18155:parent_stock'])::text$q$, :'new_unf', :'old_unf')) as r3c \gset
reset role;
select pg_temp.chk('3a UNF18155 preview: blocks none · warnings = parent_stock only (no cin7_combo · no open_orders)',
  coalesce(pg_temp.j(:'r3p')->>'committed', :'r3p') || ' [' || pg_temp.codes(pg_temp.j(:'r3p'), 'blocks') || '] [' || pg_temp.codes(pg_temp.j(:'r3p'), 'warnings') || ']', 'false [] [parent_stock]');
select pg_temp.chk('3b UNF18155 changes: one changed · five unchanged',
  (select coalesce(string_agg(x->>'action' || ':' || c, ' ' order by x->>'action'), '(none)') from (select x->>'action' as a, count(*) c, min(x::text)::jsonb x from jsonb_array_elements(pg_temp.j(:'r3p')->'changes') x group by 1) q(a, c, x)), 'changed:1 unchanged:5');
select pg_temp.chk('3c commit without ack → committed false · unacked = combo:UNF18155:parent_stock',
  coalesce(pg_temp.j(:'r3u')->>'committed', :'r3u') || ' ' || coalesce((pg_temp.j(:'r3u')->'unacked')::text, '-'), 'false ["combo:UNF18155:parent_stock"]');
select pg_temp.chk('3d commit with ack → committed true · changed 1',
  coalesce(pg_temp.j(:'r3c')->>'committed', :'r3c') || ' ' || coalesce(pg_temp.j(:'r3c')->>'changed', '-'), 'true 1');
select pg_temp.chk('3e touched row: source manual · updated_by = fake staff · others still cin7 (5)',
  (select b.source || ' ' || (b.updated_by::text = :'sid') from public.product_bom b join public.product p on p.id = b.parent_product_id join public.product c on c.id = b.component_product_id where p.sku = 'UNF18155' and c.sku = :'unf_c1')
  || ' ' || (select count(*) from public.product_bom b join public.product p on p.id = b.parent_product_id where p.sku = 'UNF18155' and b.source = 'cin7' and b.is_active), 'manual true 5');

-- ── 갈래 5: product_combo_create — 미리 보기 · 받지 않는 칸 · commit → SKU + 줄 · so_combo_is ──
\set item '{"sku":"CB1-COMBO1","name":"CB1 combo one","brand_id":"' :br '","unit_id":"' :unit '","barcodes":[],"prices":[{"tier_id":"' :tier '","price":9.99}]}'
\set lines '[{"sku":"CB1-C1","qty":1},{"sku":"CB1-C2","qty":2},{"sku":"CB1-C3","qty":1}]'
set local role authenticated;
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, %L::jsonb, false, '{}')::text$q$, :'item', :'lines')) as r5p \gset
select pg_temp.run(format($q$select public.product_combo_create((%L::jsonb) || '{"sets":[{"pack_factor":6}]}'::jsonb, %L::jsonb, false, '{}')::text$q$, :'item', :'lines')) as r5s \gset
select pg_temp.run(format($q$select public.product_combo_create((%L::jsonb) || '{"suppliers":[{"supplier_id":"00000000-0000-0000-0000-000000000000"}]}'::jsonb, %L::jsonb, false, '{}')::text$q$, :'item', :'lines')) as r5u \gset
select pg_temp.run(format($q$select public.product_combo_create((%L::jsonb) || '{"family_id":"00000000-0000-0000-0000-000000000000"}'::jsonb, %L::jsonb, false, '{}')::text$q$, :'item', :'lines')) as r5f \gset
select pg_temp.run(format($q$select public.product_combo_create((%L::jsonb) || '{"options":["Red"]}'::jsonb, %L::jsonb, false, '{}')::text$q$, :'item', :'lines')) as r5o \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, %L::jsonb, true, '{}')::text$q$, :'item', :'lines')) as r5n \gset
select (select count(*) from public.product where sku = 'CB1-COMBO1')::text as c5n \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, %L::jsonb, true, array['CB1-COMBO1:barcode_missing'])::text$q$, :'item', :'lines')) as r5c \gset
reset role;
select pg_temp.chk('5a preview: committed false · blocks none · warnings = barcode_missing only (no supplier_missing) · components 3 echoed',
  coalesce(pg_temp.j(:'r5p')->>'committed', :'r5p') || ' [' || pg_temp.codes(pg_temp.j(:'r5p'), 'blocks') || '] [' || pg_temp.codes(pg_temp.j(:'r5p'), 'warnings') || '] ' || coalesce(jsonb_array_length(pg_temp.j(:'r5p')->'components')::text, '-'),
  'false [] [barcode_missing] 3');
select pg_temp.chk('5b sets → combo_no_sets', pg_temp.codes(pg_temp.j(:'r5s'), 'blocks'), 'combo_no_sets');
select pg_temp.chk('5c suppliers → combo_no_suppliers (+ core supplier_unknown for the fake id)', pg_temp.codes(pg_temp.j(:'r5u'), 'blocks'), 'combo_no_suppliers,supplier_unknown');
select pg_temp.chk('5d family_id → combo_no_family', pg_temp.codes(pg_temp.j(:'r5f'), 'blocks'), 'combo_no_family');
select pg_temp.chk('5e options → combo_no_family', pg_temp.codes(pg_temp.j(:'r5o'), 'blocks'), 'combo_no_family');
select pg_temp.chk('5f commit without ack → committed false · unacked = CB1-COMBO1:barcode_missing · no product',
  coalesce(pg_temp.j(:'r5n')->>'committed', :'r5n') || ' ' || coalesce((pg_temp.j(:'r5n')->'unacked')::text, '-') || ' ' || :'c5n', 'false ["CB1-COMBO1:barcode_missing"] 0');
select pg_temp.chk('5g commit with ack → committed true · added 3 · product_id given · items[0].sku',
  coalesce(pg_temp.j(:'r5c')->>'committed', :'r5c') || ' ' || coalesce(pg_temp.j(:'r5c')->>'added', '-') || ' ' || ((pg_temp.j(:'r5c')->>'product_id') is not null)::text || ' ' || coalesce(pg_temp.j(:'r5c')->'items'->0->>'sku', '-'), 'true 3 true CB1-COMBO1');
-- 적용 전 마른 실행에서는 CB1-COMBO1 이 없다 — \gset 이 0 행으로 서지 않게(MISMATCH 로 끝나게) 빈 uuid 로
select coalesce((select id::text from public.product where sku = 'CB1-COMBO1'), '00000000-0000-0000-0000-000000000000') as combo1 \gset
select pg_temp.chk('5h CB1-COMBO1 row: source manual · active · price 1 · bom rows 3 active manual · updated_by fake staff · so_combo_is true',
  (select p.source || ' ' || p.is_active from public.product p where p.id = :'combo1'::uuid) || ' ' || (select count(*) from public.product_price where product_id = :'combo1'::uuid)
  || ' ' || (select count(*) || '/' || count(*) filter (where is_active and source = 'manual' and updated_by::text = :'sid') from public.product_bom where parent_product_id = :'combo1'::uuid)
  || ' ' || public.so_combo_is(:'combo1'::uuid), 'manual true 1 3/3 true');
select pg_temp.chk('5i components echoed in commit response = C1×1 C2×2 C3×1',
  (select coalesce(string_agg(x->>'sku' || 'x' || trim_scale((x->>'qty')::numeric), ' ' order by x->>'sku'), '-') from jsonb_array_elements(pg_temp.j(:'r5c')->'components') x), 'CB1-C1x1 CB1-C2x2 CB1-C3x1');
set local role authenticated;
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, %L::jsonb, true, array['CB1-COMBO1:barcode_missing'])::text$q$, :'item', :'lines')) as r5x \gset
reset role;
select pg_temp.chk('5j same SKU again → sku_exists · nothing added', pg_temp.codes(pg_temp.j(:'r5x'), 'blocks') || ' ' || (select count(*) from public.product where sku = 'CB1-COMBO1'), 'sku_exists 1');

-- ── 갈래 6: 구성품 하나 틀림 → 막기 · SKU 도 안 생김 · 하나뿐 · 0 개 · 콤보를 구성품으로 ──
\set item2 '{"sku":"CB1-COMBO2","name":"CB1 combo two","brand_id":"' :br '","unit_id":"' :unit '","prices":[{"tier_id":"' :tier '","price":5}]}'
set local role authenticated;
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CB1-C1","qty":1},{"sku":"CB1-NOPE","qty":1}]'::jsonb, true, array['CB1-COMBO2:barcode_missing'])::text$q$, :'item2')) as r6a \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CB1-C1","qty":1}]'::jsonb, true, array['CB1-COMBO2:barcode_missing'])::text$q$, :'item2')) as r6b \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[]'::jsonb, true, array['CB1-COMBO2:barcode_missing'])::text$q$, :'item2')) as r6c \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CB1-C1","qty":1},{"sku":"CB1-COMBO1","qty":1}]'::jsonb, true, array['CB1-COMBO2:barcode_missing'])::text$q$, :'item2')) as r6d \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CB1-C1","qty":1},{"sku":"CB1-C2","qty":"x"}]'::jsonb, true, array['CB1-COMBO2:barcode_missing'])::text$q$, :'item2')) as r6e \gset
reset role;
select pg_temp.chk('6a unknown component → component_unknown · committed false · product CB1-COMBO2 absent (one transaction)',
  pg_temp.codes(pg_temp.j(:'r6a'), 'blocks') || ' ' || coalesce(pg_temp.j(:'r6a')->>'committed', '-') || ' ' || (select count(*) from public.product where sku = 'CB1-COMBO2'), 'component_unknown false 0');
select pg_temp.chk('6b one component → component_single', pg_temp.codes(pg_temp.j(:'r6b'), 'blocks'), 'component_single');
select pg_temp.chk('6c no components → components_missing', pg_temp.codes(pg_temp.j(:'r6c'), 'blocks'), 'components_missing');
select pg_temp.chk('6d a combo as component → component_is_combo', pg_temp.codes(pg_temp.j(:'r6d'), 'blocks'), 'component_is_combo');
select pg_temp.chk('6e bad qty → quantity_invalid', pg_temp.codes(pg_temp.j(:'r6e'), 'blocks'), 'quantity_invalid');
select pg_temp.chk('6f CB1-COMBO2 never created · no bom rows for it', (select count(*) from public.product where sku = 'CB1-COMBO2')::text || ' ' || (select count(*) from public.product_bom b join public.product p on p.id = b.parent_product_id where p.sku = 'CB1-COMBO2'), '0 0');

-- ── 갈래 7: product_combo_list — 구성품 SKU 로 검색 · 부모 이름 · 쪽 · released 거르기 · 시간 ──
set local role authenticated;
select clock_timestamp() as t_l0 \gset
select pg_temp.run($q$select string_agg(sku || ':' || component_count || ':' || components || ':' || released || ':' || total, ' | ' order by sku) from public.product_combo_list('CB1-C2', true, false, 200, 0)$q$) as r7a \gset
select clock_timestamp() as t_l1 \gset
select pg_temp.run($q$select string_agg(sku, ',' order by sku) from public.product_combo_list('combo one', true, false, 200, 0)$q$) as r7b \gset
select pg_temp.run($q$select count(*)::text || ' ' || max(total) from public.product_combo_list(null, true, false, 1000, 0)$q$) as r7c \gset
select pg_temp.run($q$select count(*)::text || ' ' || max(total) || ' ' || min(sku) from public.product_combo_list(null, true, false, 2, 1)$q$) as r7d \gset
select pg_temp.run($q$select string_agg(sku || ':' || component_count, ',' order by sku) from public.product_combo_list('UNF1825', true, false, 200, 0)$q$) as r7e \gset
reset role;
select pg_temp.chk('7a search by component SKU CB1-C2 → CB1-COMBO1 · 3 components · summary · not released · total 1',
  :'r7a', 'CB1-COMBO1:3:CB1-C1 × 1, CB1-C2 × 2, CB1-C3 × 1:false:1');
select pg_temp.chk('7b search by combo name "combo one" → CB1-COMBO1', :'r7b', 'CB1-COMBO1');
select pg_temp.chk('7c all active combos = before + 1 (CB1-COMBO1)', :'r7c', (:n_combo0 + 1)::text || ' ' || (:n_combo0 + 1)::text);
select pg_temp.chk('7d paging: limit 2 offset 1 → 2 rows · total unchanged · second sku',
  :'r7d', '2 ' || (:n_combo0 + 1)::text || ' ' || (select p.sku from public.product p where exists (select 1 from public.product_bom b where b.parent_product_id = p.id and b.is_active) and p.is_active order by p.sku, p.id offset 1 limit 1));
select pg_temp.chk('7e search UNF1825 matches combos UNF18250 · UNF18251 · UNF18259 (real · by parent sku)', :'r7e', 'UNF18250:2,UNF18251:2,UNF18259:4');
select pg_temp.chk('7t list call under 1 s', ((:'t_l1'::timestamptz - :'t_l0'::timestamptz) < interval '1 second')::text, 'true');

-- ── 갈래 4: Release(빈 목록) → 됨 · 그 SKU 에 다시 줄 2 → parent_not_combo · 목록의 released ──
set local role authenticated;
select pg_temp.run(format($q$select public.product_bom_set('CB1-COMBO1', '[]'::jsonb, %L::jsonb, true, '{}')::text$q$, (pg_temp.j(:'r5c')->'components')::text)) as r4a \gset
select pg_temp.run($q$select public.product_bom_set('CB1-COMBO1', '[{"sku":"CB1-C1","qty":1},{"sku":"CB1-C2","qty":1}]'::jsonb, '[]'::jsonb, true, '{}')::text$q$) as r4b \gset
select pg_temp.run($q$select coalesce(string_agg(sku, ','), '(none)') from public.product_combo_list('CB1-C', true, false, 200, 0)$q$) as r4c \gset
select pg_temp.run($q$select coalesce(string_agg(sku || ':' || component_count || ':' || released, ','), '(none)') from public.product_combo_list('CB1-COMBO', true, true, 200, 0)$q$) as r4d \gset
reset role;
select pg_temp.chk('4a release CB1-COMBO1 → committed · removed 3 · active rows 0 (rows kept · manual)',
  coalesce(pg_temp.j(:'r4a')->>'committed', :'r4a') || ' ' || coalesce(pg_temp.j(:'r4a')->>'removed', '-') || ' ' || (select count(*) filter (where is_active) || '/' || count(*) from public.product_bom where parent_product_id = :'combo1'::uuid), 'true 3 0/3');
select pg_temp.chk('4b lines again on the released SKU → parent_not_combo (819: release cannot be undone)',
  coalesce(pg_temp.j(:'r4b')->>'committed', :'r4b') || ' ' || pg_temp.codes(pg_temp.j(:'r4b'), 'blocks'), 'false parent_not_combo');
select pg_temp.chk('4c list without released: CB1-COMBO1 gone (component search too)', :'r4c', '(none)');
select pg_temp.chk('4d list with p_include_released: CB1-COMBO1 · 0 components · released true', :'r4d', 'CB1-COMBO1:0:true');

-- ── 갈래 1′: 낱개 + 빈 목록(해제가 아닌 것) → no_change(기존 그대로) · 모양 틀림 → lines_invalid(도우미) ──
set local role authenticated;
select pg_temp.run($q$select public.product_bom_set('CB1-S0', '[]'::jsonb, '[]'::jsonb, true, '{}')::text$q$) as r1x \gset
select pg_temp.run($q$select public.product_bom_set('UNF18155', '{"sku":1}'::jsonb, '[]'::jsonb, true, '{}')::text$q$) as r1y \gset
reset role;
select pg_temp.chk('1d plain SKU + empty list → no_change (unchanged behaviour · no parent_not_combo)', pg_temp.codes(pg_temp.j(:'r1x'), 'blocks'), 'no_change');
select pg_temp.chk('1e lines not an array → lines_invalid (helper) · changed_elsewhere (p_old)', pg_temp.codes(pg_temp.j(:'r1y'), 'blocks'), 'changed_elsewhere,lines_invalid');

-- ── 권한 길: 열쇠 없는 직원은 창구 둘 거부 · 목록은 읽힌다 ──
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'combo1-z@test.invalid', 'COMBO1 no keys', 'worker', '["wms"]', '{}');
select auth_user_id::text as uid_z from public.ims_staff where email = 'combo1-z@test.invalid' \gset
select set_config('request.jwt.claims', json_build_object('sub', :'uid_z', 'role', 'authenticated')::text, true) \gset
set local role authenticated;
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, %L::jsonb, false, '{}')::text$q$, :'item2', :'lines')) as rz1 \gset
select pg_temp.run($q$select public.product_bom_set('UNF18155', '[]'::jsonb, '[]'::jsonb, false, '{}')::text$q$) as rz2 \gset
select pg_temp.run($q$select count(*)::text from public.product_combo_list('UNF18155', true, false, 10, 0)$q$) as rz3 \gset
reset role;
select pg_temp.chk('Z1 no master key: product_combo_create refused by ims_require_write', left(:'rz1', 55), 'ERR P0001: You cannot change master data — ask an admin');
select pg_temp.chk('Z2 no master key: product_bom_set refused', left(:'rz2', 55), 'ERR P0001: You cannot change master data — ask an admin');
select pg_temp.chk('Z3 no master key: product_combo_list readable (invoker · RLS select true)', :'rz3', '1');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.product) = :n_product as product_same, (select count(*) from public.product_bom) = :n_bom as bom_same,
       (select count(*) from public.product_bom where is_active) = :n_bom_act as bom_active_same, (select count(*) from public.ims_staff) = :n_staff as staff_same,
       (select count(*) from public.ref_brand) = :n_brand as brand_same, (select count(*) from public.product_barcode) = :n_bc as barcode_same, (select count(*) from public.product_price) = :n_price as price_same,
       (select count(*) from public.product where sku like 'CB1-%') = 0 as no_cb1_rows,
       (select coalesce(md5(p.prosrc), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_set') = :'md5_bom_set_0' as bom_set_md5_same_as_before,
       (select coalesce(md5(p.prosrc), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create_core') = :'md5_core_0' as core_md5_same;
-- R0 REST(적용 뒤 · Caleb · 미리 보기만 = 쓰기 0 · 직원 토큰은 tools/shopify-ping.sh 의 로그인 꼴로 받는다 · U=테스트 프로젝트 URL · T=access_token · A=anon key):
--   curl -sS "$U/rest/v1/rpc/product_combo_list" -H "apikey: $A" -H "Authorization: Bearer $T" -H "Content-Type: application/json" -d '{"p_q":"UNF1825","p_only_active":true,"p_include_released":false,"p_limit":50,"p_offset":0}'
--   curl -sS "$U/rest/v1/rpc/product_combo_create" -H "apikey: $A" -H "Authorization: Bearer $T" -H "Content-Type: application/json" -d '{"p_item":{"sku":"ZZCOMBO1","name":"rest preview","barcodes":[],"prices":[]},"p_lines":[{"sku":"UNF18250","qty":1},{"sku":"UNF18251","qty":1}],"p_commit":false,"p_ack":[]}'
--   curl -sS "$U/rest/v1/rpc/product_bom_set" -H "apikey: $A" -H "Authorization: Bearer $T" -H "Content-Type: application/json" -d '{"p_parent_sku":"ABC59138","p_lines":[{"sku":"UNF18250","qty":1},{"sku":"UNF18251","qty":1}],"p_old":null,"p_commit":false,"p_ack":[]}'
--   기대: ① 행 3(UNF18250 · 51 · 59) ② committed false · blocks [] · warnings 에 brand_missing · barcode_missing · price_missing(supplier_missing 없음) ③ blocks 에 parent_not_combo · 21000 없음
