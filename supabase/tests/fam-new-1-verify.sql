-- fam-new-1-verify.sql — 기존 SKU 들로 새 family(판정 652 · 653 B):
--   S0 결함 판 · 옛 출력 담기(product_family_create 새 · 있는 · 막힘 · family_join — 서브트랜잭션 · 쓰기 0) · G0 손대지 않은 함수 무변 · N5 옛 = 새(도우미로 뗀 둘 · 같은 입력 → 같은 출력 · 행) · G1 모양 ·
--   N1 family 없는 SKU 셋 → 새 family(머리 = 첫 SKU + FAM · 미리 보기 무쓰기 · 저장) · N2 옛 family 의 하나를 옮김(moves_from_family · ack 없이 거부 · ack 로 저장) · N3 마지막 둘을 옮김(old_family_emptied · 빈 머리 그대로) ·
--   N4 거부 갈래(없는 · 비활성 · 세트 · 두 번 · 옵션 수 · 조합 겹침 · 머리 SKU 있음 · 빈 · id 넘김 · master 아님) · Z1 실제 행 무접촉
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261023152737_fam_new_1_family_from_skus.sql -f supabase/tests/fam-new-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · N5 셋은 없고 P0c 한 줄
--   기대(2026-10-23 시험 통과 실행 · 찍힌 OK 줄을 셈): 시험 갈래 OK 10(M0 S0 G0 N5 G1 N1 N2 N3 N4 Z1) · MISMATCH 0 · begin ~ rollback 약 1.5 초 / 확인 갈래 OK 8(M0 P0c G1 N1 N2 N3 N4 Z1) · MISMATCH 0
--   ⭐ 잠금 규칙: 첫 줄 lock_timeout 3s · 가짜 재료만 · 번호 시퀀스 0 · 끝에 begin ~ rollback 초 · alter · lock · truncate · drop 없음
--   가짜 재료 = 직원 둘(master · sales) · 제품 FAMN1-A ~ F(E 비활성) · 세트 FAMN1-A-6 · 옛 family FAMN1-OLDFAM(X · Y · Z · Color) — 전부 되감긴다

\echo '── db_role · schema_migrations'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261023152737' \gset
select :n_applied as schema_migrations_rows_for_20261023152737;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as tb, now() as t0 \gset

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.norm(p text) returns text language sql immutable as $$ select regexp_replace(coalesce(p, ''), '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '#', 'g') $$;
-- 가짜 family · 구성원의 지금 모양 한 글(옛 = 새 · 시나리오)
create function pg_temp.fam_state() returns text language sql security definer as $$
  select coalesce((select string_agg(f.sku || '[' || f.name || '|' || f.is_active || '|' || coalesce(f.brand_name, '-') || '|' || coalesce(f.option1_name, '-') || '|' || coalesce(f.option2_name, '-') || ']='
                     || coalesce((select string_agg(p.sku || '(' || coalesce(p.option1_value, '-') || coalesce('/' || p.option2_value, '') || ')', ',' order by p.sku) from public.product p where p.family_id = f.id), ''), ' ' order by f.sku)
                     from public.product_family f where f.sku like 'FAMN1-%'), '-') $$;
-- 옛 = 새 한 경우: 서브트랜잭션에서 창구를 돌리고 반환 + 행을 예외 메시지로 꺼낸 뒤 되감는다(쓰기 0)
create function pg_temp.trial(p_claims text, p_sql text) returns text language plpgsql as $$
declare v jsonb;
begin
  begin
    perform set_config('request.jwt.claims', p_claims, true);
    execute p_sql into v;
    raise exception using errcode = 'P7777', message = jsonb_build_object('ret', v, 'rows', pg_temp.fam_state(), 'products', (select string_agg(p.sku || '|' || p.name || '|' || coalesce(f.sku, '-'), ',' order by p.sku) from public.product p left join public.product_family f on f.id = p.family_id where p.sku like 'FAMN1-N%'))::text;
  exception when sqlstate 'P7777' then
    return pg_temp.norm(sqlerrm);
  when others then
    return 'ERR ' || sqlstate || ': ' || sqlerrm;
  end;
end $$;
create function pg_temp.fns() returns text language sql security definer as $$
  select string_agg(p.proname || '=' || md5(p.prosrc) || '/' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('product_update', 'product_create', 'product_set_check', 'product_set_insert', 'product_set_add', 'product_axis_case_hint', 'shop_product_payload', 'shop_queue_trigger') $$;
create function pg_temp.real_rows(p_t0 timestamptz) returns text language plpgsql security definer as $$
begin
  return 'families=' || (select count(*) || '/' || md5(coalesce(string_agg(f.id::text || f.sku || f.is_active || coalesce(f.updated_at::text, ''), ',' order by f.id), '')) from public.product_family f where f.created_at < p_t0)
      || ' members=' || (select count(*) || '/' || md5(coalesce(string_agg(p.id::text || coalesce(p.family_id::text, '-') || coalesce(p.option1_value, '-'), ',' order by p.id), '')) from public.product p where p.created_at < p_t0)
      || ' queue=' || (select count(*) from public.shop_push_queue q where q.queued_at < p_t0);
end $$;

\echo '── M0) 가짜 직원 둘 · 제품 · 세트 · 옛 family'
select pg_temp.real_rows(:'t0'::timestamptz) as real_before, pg_temp.fns() as fns_before \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'famn1-m@test.invalid', 'FAMN1 M', 'manager', '["ims","master"]', '{}') returning auth_user_id::text as m_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'famn1-s@test.invalid', 'FAMN1 S', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as s_uid \gset
\set m '{"sub":"' :m_uid '","role":"authenticated"}'
\set s '{"sub":"' :s_uid '","role":"authenticated"}'
select b.id::text as brand, b.name as brand_name from public.ref_brand b where b.is_active order by b.name limit 1 \gset
select b.id::text as brand2 from public.ref_brand b where b.is_active and b.id <> :'brand'::uuid order by b.name limit 1 \gset
select c.id::text as cat from public.ref_category c where c.is_active order by c.name limit 1 \gset
select u.id::text as unit from public.ref_unit u where u.is_active order by u.name limit 1 \gset
set local session_replication_role = replica;
insert into public.product (sku, name, source, is_active, sellable, brand_id, brand_name, category_id, unit_id)
  select 'FAMN1-' || s, 'FAMN1 ' || s, 'manual', s <> 'E', true, case when s = 'F' then :'brand2'::uuid else :'brand'::uuid end, :'brand_name', :'cat'::uuid, :'unit'::uuid from unnest(array['A', 'B', 'C', 'D', 'E', 'F', 'X', 'Y', 'Z']) s;
insert into public.product (sku, name, source, is_active, sellable, parent_product_id, pack_factor, uom_name) values ('FAMN1-A-6', 'FAMN1 A', 'manual', true, false, (select id from public.product where sku = 'FAMN1-A'), 6, '6');
insert into public.product_family (sku, name, source, brand_id, brand_name, category_id, option1_name) values ('FAMN1-OLDFAM', 'FAMN1 Old family', 'manual', :'brand'::uuid, :'brand_name', :'cat'::uuid, 'Color') returning id::text as oldfam \gset
update public.product p set family_id = :'oldfam'::uuid, option1_value = case p.sku when 'FAMN1-X' then 'Red' when 'FAMN1-Y' then 'Blue' else 'Green' end where p.sku in ('FAMN1-X', 'FAMN1-Y', 'FAMN1-Z');
set local session_replication_role = origin;
select pg_temp.fam_state() as m0_state \gset
select pg_temp.chk(format('M0 staff M(master) · S(sales) · products A ~ F (E inactive · F other brand) · set A-6 · old family %s', :'m0_state'),
  :'m_uid' <> '' and :'s_uid' <> '' and :'brand2' <> '' and :'oldfam' ~ '^[0-9a-f-]{36}$' and :'m0_state' = 'FAMN1-OLDFAM[FAMN1 Old family|true|' || :'brand_name' || '|Color|-]=FAMN1-X(Red),FAMN1-Y(Blue),FAMN1-Z(Green)' and :'real_before' <> '',
  format('%s | %s', :'m0_state', :'oldfam'));

-- 옛 = 새 입력 넷 — 새 family(새 SKU 둘 · 미리 보기 · 저장) · 있는 family 에 더하기 · 막히는 머리 · family_join
\set n5a 'select public.product_family_create(%L::jsonb, %L::jsonb, %s, %L::text[])::text'
create function pg_temp.n5(p_claims text) returns jsonb language plpgsql as $$
declare v_head jsonb := jsonb_build_object('name', 'FAMN1 New', 'brand_id', (select brand_id from public.product where sku = 'FAMN1-A'), 'option1_name', 'Color', 'option2_name', 'Size');
        v_items jsonb := jsonb_build_array(jsonb_build_object('sku', 'FAMN1-N1', 'options', jsonb_build_array('Red', 'S')), jsonb_build_object('sku', 'FAMN1-N2', 'options', jsonb_build_array('Blue', 'M')));
        v_old uuid := (select id from public.product_family where sku = 'FAMN1-OLDFAM');
        v_ack1 text[];  v_ack2 text[];
begin
  perform set_config('request.jwt.claims', p_claims, true);
  -- 저장 경우의 ack = 미리 보기(쓰기 0)가 낸 경고 열쇠 전부(새 제품의 price_missing · supplier_missing 등)
  select coalesce(array_agg(w->>'key'), '{}') into v_ack1 from jsonb_array_elements(public.product_family_create(v_head, v_items, false, '{}'::text[])->'warnings') w;
  select coalesce(array_agg(w->>'key'), '{}') into v_ack2 from jsonb_array_elements(public.product_family_create(jsonb_build_object('id', v_old), jsonb_build_array(jsonb_build_object('sku', 'FAMN1-N3', 'options', jsonb_build_array('Black'))), false, '{}'::text[])->'warnings') w;
  return jsonb_build_object(
    'new_preview', pg_temp.trial(p_claims, format('select public.product_family_create(%L::jsonb, %L::jsonb, false, %L::text[])', v_head, v_items, '{}'::text[])),
    'new_commit',  pg_temp.trial(p_claims, format('select public.product_family_create(%L::jsonb, %L::jsonb, true, %L::text[])', v_head, v_items, v_ack1)),
    'existing',    pg_temp.trial(p_claims, format('select public.product_family_create(%L::jsonb, %L::jsonb, true, %L::text[])', jsonb_build_object('id', v_old), jsonb_build_array(jsonb_build_object('sku', 'FAMN1-N3', 'options', jsonb_build_array('Black'))), v_ack2)),
    'blocked',     pg_temp.trial(p_claims, format('select public.product_family_create(%L::jsonb, %L::jsonb, true, %L::text[])', jsonb_build_object('sku', 'famn1 x', 'option2_name', 'Size'), jsonb_build_array(jsonb_build_object('sku', 'FAMN1-N4', 'options', jsonb_build_array('Red'))), '{}'::text[])),
    'ambiguous',   pg_temp.trial(p_claims, format('select public.product_family_create(%L::jsonb, %L::jsonb, false, %L::text[])', jsonb_build_object('id', v_old, 'name', 'x'), jsonb_build_array(jsonb_build_object('sku', 'FAMN1-N5', 'options', jsonb_build_array('Red'))), '{}'::text[])),
    'join',        pg_temp.trial(p_claims, format('select public.product_update(%L::jsonb, true, %L::text[])', jsonb_build_array(jsonb_build_object('op', 'family_join', 'sku', 'FAMN1-D', 'family_sku', 'FAMN1-OLDFAM', 'options', jsonb_build_array('White'))), '{}'::text[])));
end $$;

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — 창구 · 도우미 없음 · 옛 출력 담기'
select (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('product_family_from_skus', 'product_family_head_ctx', 'product_family_head_insert')) as s0_n \gset
select pg_temp.n5(:'m')::text as pre \gset
select pg_temp.chk(format('S0 before the trial: no window · no helpers · old outputs captured (new preview · new commit · existing · blocked · ambiguous · join — %s keys)', (select count(*) from jsonb_object_keys(pg_temp.j(:'pre')))),
  :s0_n = 0 and :n_applied = 0 and (select count(*) from jsonb_object_keys(pg_temp.j(:'pre'))) = 6 and (select bool_and(v not like 'ERR%') from jsonb_each_text(pg_temp.j(:'pre')) e(k, v))
  and pg_temp.j(pg_temp.j(:'pre')->>'new_commit')->'ret'->>'committed' = 'true' and pg_temp.j(pg_temp.j(:'pre')->>'blocked')->'ret'->>'committed' = 'false',
  left(:'pre', 1500));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: product_update · product_create · set helpers · axis hint · shopify payload · queue trigger unchanged (bodies and ACLs)', pg_temp.fns() = :'fns_before', format('before %s | after %s', :'fns_before', pg_temp.fns()));
\echo '── N5) 옛 = 새 — product_family_create(새 · 있는 · 막힘 · 모호) · family_join: 같은 입력 → 같은 반환 · 같은 행'
select pg_temp.n5(:'m')::text as post \gset
select pg_temp.chk('N5 old = new for six cases (return json byte-equal after uuid masking · family rows · new product rows)',
  pg_temp.j(:'pre') = pg_temp.j(:'post'),
  (select string_agg(k || ': ' || left(pg_temp.j(:'pre')->>k, 400) || ' <> ' || left(pg_temp.j(:'post')->>k, 400), ' || ') from jsonb_object_keys(pg_temp.j(:'post')) k where pg_temp.j(:'pre')->k is distinct from pg_temp.j(:'post')->k));
\else
select pg_temp.chk('P0c confirm run: migration 20261023152737 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_family_from_skus') as landed \gset
\if :landed
\echo '── G1) 모양 — 창구 authenticated · 도우미 실행권 0 · 부르는 둘'
select pg_temp.chk('G1 window authenticated only (anon · service_role no) · helpers no execute for anyone but postgres · product_family_create calls head_ctx · product_create_core calls head_insert',
  has_function_privilege('authenticated', 'public.product_family_from_skus(jsonb, jsonb, boolean, text[])', 'execute')
  and not has_function_privilege('anon', 'public.product_family_from_skus(jsonb, jsonb, boolean, text[])', 'execute') and not has_function_privilege('service_role', 'public.product_family_from_skus(jsonb, jsonb, boolean, text[])', 'execute')
  and not has_function_privilege('authenticated', 'public.product_family_head_ctx(jsonb, jsonb)', 'execute') and not has_function_privilege('authenticated', 'public.product_family_head_insert(jsonb)', 'execute')
  and (select prosrc ~ 'public\.product_family_head_ctx\(' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_family_create')
  and (select prosrc ~ 'public\.product_family_head_insert\(' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_create_core'),
  'see G1');

\echo '── N1) family 없는 A · B · C → 새 family(Color) — 미리 보기 무쓰기 · 저장'
\set items1 '[{"sku":"FAMN1-A","options":["Red"]},{"sku":"FAMN1-B","options":["Blue"]},{"sku":"FAMN1-C","options":["Green"]}]'
select pg_temp.as_user(:'m', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, false)::text', jsonb_build_object('name', 'FAMN1 Alpha', 'option1_name', 'Color'), :'items1')) as n1a \gset
select pg_temp.fam_state() as n1a_state \gset
select pg_temp.as_user(:'m', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, true)::text', jsonb_build_object('name', 'FAMN1 Alpha', 'option1_name', 'Color'), :'items1')) as n1b \gset
select pg_temp.fam_state() as n1b_state \gset
select pg_temp.chk(format('N1 preview: committed false · family sku %s (first SKU + FAM) · 3 items · nothing written · commit: created · head brand from first SKU · %s', pg_temp.j(:'n1a')->'family'->>'sku', :'n1b_state'),
  pg_temp.j(:'n1a')->>'committed' = 'false' and pg_temp.j(:'n1a')->'family'->>'sku' = 'FAMN1-AFAM' and jsonb_array_length(pg_temp.j(:'n1a')->'items') = 3 and pg_temp.j(:'n1a')->'blocks' = '[]'::jsonb and pg_temp.j(:'n1a')->'warnings' = '[]'::jsonb
  and :'n1a_state' = :'m0_state'
  and pg_temp.j(:'n1b')->>'committed' = 'true' and pg_temp.j(:'n1b')->'family'->>'created' = 'true' and pg_temp.j(:'n1b')->'family'->>'id' ~ '^[0-9a-f-]{36}$'
  and :'n1b_state' = 'FAMN1-AFAM[FAMN1 Alpha|true|' || :'brand_name' || '|Color|-]=FAMN1-A(Red),FAMN1-B(Blue),FAMN1-C(Green) FAMN1-OLDFAM[FAMN1 Old family|true|' || :'brand_name' || '|Color|-]=FAMN1-X(Red),FAMN1-Y(Blue),FAMN1-Z(Green)'
  and (select source from public.product_family where sku = 'FAMN1-AFAM') = 'manual',
  format('%s | %s | %s', left(:'n1a', 500), left(:'n1b', 500), :'n1b_state'));

\echo '── N2) D + X(옛 family) → 새 family — moves_from_family · ack 없이 거부 · ack 로 저장 · 옛 family 둘 남음'
\set items2 '[{"sku":"FAMN1-D","options":["Red","S"]},{"sku":"FAMN1-X","options":["Red","M"]}]'
select pg_temp.as_user(:'m', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, true)::text', jsonb_build_object('name', 'FAMN1 Beta', 'option1_name', 'Color', 'option2_name', 'Size'), :'items2')) as n2a \gset
select pg_temp.fam_state() as n2a_state \gset
select pg_temp.as_user(:'m', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, true, %L::text[])::text', jsonb_build_object('name', 'FAMN1 Beta', 'option1_name', 'Color', 'option2_name', 'Size'), :'items2', array['FAMN1-X:moves_from_family:FAMN1-OLDFAM'])) as n2b \gset
select pg_temp.fam_state() as n2b_state \gset
select pg_temp.chk(format('N2 warning %s · unacked without ack (nothing written) · with ack committed · %s', pg_temp.j(:'n2a')->'warnings'->0->>'key', :'n2b_state'),
  pg_temp.j(:'n2a')->>'committed' = 'false' and pg_temp.j(:'n2a')->'unacked' = '["FAMN1-X:moves_from_family:FAMN1-OLDFAM"]'::jsonb and pg_temp.j(:'n2a')->'blocks' = '[]'::jsonb
  and pg_temp.j(:'n2a')->'warnings'->0->>'message' = 'FAMN1-X will move out of FAMN1 Old family (FAMN1-OLDFAM) into FAMN1-DFAM' and pg_temp.j(:'n2a')->'items'->1->>'moves_from_family' = 'FAMN1-OLDFAM'
  and :'n2a_state' = :'n1b_state'
  and pg_temp.j(:'n2b')->>'committed' = 'true'
  and :'n2b_state' = 'FAMN1-AFAM[FAMN1 Alpha|true|' || :'brand_name' || '|Color|-]=FAMN1-A(Red),FAMN1-B(Blue),FAMN1-C(Green) FAMN1-DFAM[FAMN1 Beta|true|' || :'brand_name' || '|Color|Size]=FAMN1-D(Red/S),FAMN1-X(Red/M) FAMN1-OLDFAM[FAMN1 Old family|true|' || :'brand_name' || '|Color|-]=FAMN1-Y(Blue),FAMN1-Z(Green)',
  format('%s | %s | %s', left(:'n2a', 700), left(:'n2b', 300), :'n2b_state'));

\echo '── N3) Y + Z(옛 family 의 마지막 둘) → 새 family — old_family_emptied · 빈 머리 그대로(활성)'
\set items3 '[{"sku":"FAMN1-Y","options":["Blue"]},{"sku":"FAMN1-Z","options":["Green"]}]'
select pg_temp.as_user(:'m', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, true)::text', jsonb_build_object('name', 'FAMN1 Gamma', 'option1_name', 'Color'), :'items3')) as n3a \gset
select pg_temp.as_user(:'m', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, true, %L::text[])::text', jsonb_build_object('name', 'FAMN1 Gamma', 'option1_name', 'Color'), :'items3', array['FAMN1-Y:moves_from_family:FAMN1-OLDFAM', 'FAMN1-Z:moves_from_family:FAMN1-OLDFAM'])) as n3b \gset
select pg_temp.as_user(:'m', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, true, %L::text[])::text', jsonb_build_object('name', 'FAMN1 Gamma', 'option1_name', 'Color'), :'items3', array['FAMN1-Y:moves_from_family:FAMN1-OLDFAM', 'FAMN1-Z:moves_from_family:FAMN1-OLDFAM', 'FAMN1-OLDFAM:old_family_emptied'])) as n3c \gset
select pg_temp.fam_state() as n3_state, (select is_active::text || '|' || (select count(*) from public.product where family_id = f.id) from public.product_family f where f.sku = 'FAMN1-OLDFAM') as n3_old \gset
select pg_temp.chk(format('N3 unacked %s · with two acks still unacked %s · with all three committed · old head stays active with 0 members (%s) · %s', pg_temp.j(:'n3a')->'unacked', pg_temp.j(:'n3b')->'unacked', :'n3_old', :'n3_state'),
  pg_temp.j(:'n3a')->'unacked' = '["FAMN1-OLDFAM:old_family_emptied", "FAMN1-Y:moves_from_family:FAMN1-OLDFAM", "FAMN1-Z:moves_from_family:FAMN1-OLDFAM"]'::jsonb
  and pg_temp.j(:'n3b')->'unacked' = '["FAMN1-OLDFAM:old_family_emptied"]'::jsonb and pg_temp.j(:'n3c')->>'committed' = 'true' and :'n3_old' = 'true|0'
  and :'n3_state' like '%FAMN1-OLDFAM[FAMN1 Old family|true|' || :'brand_name' || '|Color|-]= %' and :'n3_state' like '%FAMN1-YFAM[FAMN1 Gamma|true|' || :'brand_name' || '|Color|-]=FAMN1-Y(Blue),FAMN1-Z(Green)%',
  format('%s | %s | %s', left(:'n3a', 600), left(:'n3b', 300), :'n3_state'));

\echo '── N4) 거부 갈래'
select pg_temp.as_user(:'m', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, true)::text', jsonb_build_object('name', 'FAMN1 Bad', 'option1_name', 'Color'),
  '[{"sku":"FAMN1-NOPE","options":["Red"]},{"sku":"FAMN1-E","options":["Red"]},{"sku":"FAMN1-A-6","options":["Red"]},{"sku":"FAMN1-F","options":["Red"]},{"sku":"FAMN1-F","options":["Blue"]},{"sku":"FAMN1-B","options":["Red","S"]},{"sku":"FAMN1-C","options":["red"]},{"sku":"","options":["x"]}]')) as n4a \gset
select (select string_agg(b->>'code', ',' order by (b->>'key')) from jsonb_array_elements(pg_temp.j(:'n4a')->'blocks') b) as n4a_codes, (select string_agg(w->>'code', ',' order by (w->>'key')) from jsonb_array_elements(pg_temp.j(:'n4a')->'warnings') w) as n4a_warns \gset
select pg_temp.as_user(:'m', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, true)::text', jsonb_build_object('name', 'FAMN1 Dup', 'sku', 'FAMN1-AFAM', 'option1_name', 'Colour'), '[{"sku":"FAMN1-F","options":["Red"]}]')) as n4b \gset
select pg_temp.as_user(:'m', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, true)::text', jsonb_build_object('name', 'FAMN1 Nil', 'option1_name', 'Color'), '[]')) as n4c,
       pg_temp.as_user(:'m', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, true)::text', jsonb_build_object('id', :'oldfam'), '[{"sku":"FAMN1-F","options":["Red"]}]')) as n4d,
       pg_temp.as_user(:'s', format('select public.product_family_from_skus(%L::jsonb, %L::jsonb, true)::text', jsonb_build_object('name', 'FAMN1 Sales', 'option1_name', 'Color'), '[{"sku":"FAMN1-F","options":["Red"]}]')) as n4e \gset
select pg_temp.fam_state() as n4_state \gset
select pg_temp.chk(format('N4 blocks %s · warnings %s (B · C now sit in AFAM · first SKU unknown → no brand default) · head SKU exists + Colour → %s · empty list · id given · sales staff refused · nothing written', :'n4a_codes', :'n4a_warns', (select string_agg(b->>'code', ',' order by (b->>'key')) from jsonb_array_elements(pg_temp.j(:'n4b')->'blocks') b)),
  pg_temp.j(:'n4a')->>'committed' = 'false'
  and :'n4a_codes' = 'sku_missing,set_not_family_member,option_count,option_duplicate_in_call,sku_inactive,field_duplicate_in_call,sku_unknown' and :'n4a_warns' = 'moves_from_family,moves_from_family,brand_missing'
  and pg_temp.j(:'n4b')->>'committed' = 'false' and (select string_agg(b->>'code', ',' order by (b->>'key')) from jsonb_array_elements(pg_temp.j(:'n4b')->'blocks') b) = 'family_sku_exists'
  and (select string_agg(w->>'code', ',') from jsonb_array_elements(pg_temp.j(:'n4b')->'warnings') w) ~ 'option_name_(unusual|case)'
  and :'n4c' like 'ERR P0001: No SKUs given%' and :'n4d' like 'ERR P0001: This window makes a new family from existing SKUs%' and :'n4e' like 'ERR P0001: You cannot change master data%'
  and :'n4_state' = :'n3_state',
  format('%s || %s || %s | %s | %s', left(:'n4a', 1600), left(:'n4b', 500), :'n4c', :'n4d', :'n4e'));
\else
select pg_temp.chk('G1 ~ N4 skipped: fam-new-1 not landed', false, 'product_family_from_skus missing');
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real families · members · push queue that existed at the snapshot untouched', pg_temp.real_rows(:'t0'::timestamptz) = :'real_before',
  format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));
select round(extract(epoch from clock_timestamp() - :'tb'::timestamptz)::numeric, 2) as tx_seconds_begin_to_rollback;
rollback;
\echo '── rollback 뒤 — 가짜 흔적 0(번호 시퀀스는 당기지 않았다)'
select (select count(*) from public.product where sku like 'FAMN1-%') + (select count(*) from public.product_family where sku like 'FAMN1-%') + (select count(*) from public.ims_staff where email like 'famn1-%') as leftovers;
