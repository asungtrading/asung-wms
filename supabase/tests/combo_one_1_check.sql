-- supabase/tests/combo_one_1_check.sql — combo-one-1 콤보에 「구성품 하나 + 수량 2 이상」 허락 (2026-10-30 · 판정 885)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — 기준(begin 앞 · 잠금 없음: 실제 행 수 · 함수 md5) → begin → 옛 prosrc 담기 → (-v mig 면 \i) → 가짜 재료 CO1-*
--   → T1 New combo A × 2 · T2 A × 1 / 1.5 / "1.0" 막힘 · T3 product_bom_set 둘 → A × 3 · A × 1 · T4 오더 넣기 · 가용 · T5 Shopify 콤보 재고 · T6 권한
--   → C(재발행 diff · 시험 갈래만) · D(nowhere 정적) · E(속성 · md5 · 무접촉) → rollback → Z1 실제 행 무변 · Z2 md5 복귀(시험 갈래만)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261030125215_combo_one_1.sql -f supabase/tests/combo_one_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 30 · 확인(적용 뒤) 28 — C1 · C2(옛 = 새 대조)는 시험 갈래만 · Z1 · Z2 는 t_res 밖 한 줄씩
--   적용 전 마른 실행(-v mig 없음)은 옛 규칙이 막아 T · E 가 MISMATCH(정상) — 실측 2026-10-30(이견 4 · 6 반영판): OK 10 · MISMATCH 18 · ERROR 0
--   실제 값(2026-10-30 · 테스트 DB): 첫판 3 회차(1 회차 T3a · C2 시험 파일 결함) → 이견 4 · 6 반영판 1 회차에 시험 OK 30 / 30 · begin~rollback 2.14 s
--   쓰기 0 — 가짜 재료는 rollback · 번호 시퀀스를 당기는 창구(so_create)는 부르지 않는다(so_number 는 글자 그대로 SO-79930)
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안(끝에 begin_to_rollback 을 찍는다)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 30
\else
\set EXPECT_OK 28
\endif
\pset pager off
select (select count(*) from public.product) as n_prod0, (select count(*) from public.product_bom) as n_bom0, (select count(*) from public.product_bom where is_active) as n_bom_act0,
       (select count(*) from public.so) as n_so0, (select count(*) from public.so_line) as n_line0, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.inv_ledger) as n_led0,
       (select count(*) from public.shop_listing) as n_list0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_bom_check_lines') as chk_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_combo_children_insert') as cci_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_bom_set') as bset_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_combo_create') as ccr_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_add') as add_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_paste') as paste_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_combo_children_sync') as sync_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_stock_payload') as pay_md5_0,
       (select id from public.shop_store where code = 'test') as test_id,
       (select id from public.ref_warehouse where name = 'Asung Trading Inc.') as wh_to, (select id from public.ref_warehouse where name = 'Asung - Edmonton') as wh_ed \gset
\echo '── 기준: product' :n_prod0 '· bom' :n_bom0 '(켜짐' :n_bom_act0 ') · so_line' :n_line0 '· check_lines md5' :chk_md5_0 '· children_insert md5' :cci_md5_0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
create temp table t_pre as select proname, prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname in ('product_bom_check_lines', 'so_combo_children_insert', 'product_combo_create');
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 도우미 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
grant insert on t_res to authenticated; grant usage on sequence t_res_n_seq to authenticated;
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when p like '{%' then p::jsonb else jsonb_build_object('err', p) end $$;
create function pg_temp.codes(p jsonb) returns text language sql as $$
  select coalesce((select string_agg(x->>'code', ',' order by x->>'code') from jsonb_array_elements(p->'blocks') x), coalesce(p->>'err', ''));
$$;
create function pg_temp.msg(p jsonb, p_code text) returns text language sql as $$
  select (select x->>'message' from jsonb_array_elements(p->'blocks') x where x->>'code' = p_code limit 1);
$$;
-- 미리 보기의 알림 열쇠 전부(저장 때 ack 로)
create function pg_temp.keys(p jsonb) returns text[] language sql as $$
  select coalesce(array_agg(x->>'key' order by x->>'key'), '{}') from jsonb_array_elements(coalesce(p->'warnings', '[]'::jsonb)) x;
$$;
create function pg_temp.bom(p_sku text) returns text language sql security definer as $$
  select coalesce(string_agg(c.sku || '×' || trim_scale(b.quantity)::text, ',' order by c.sku), '') from public.product_bom b join public.product c on c.id = b.component_product_id join public.product p on p.id = b.parent_product_id
   where p.sku = p_sku and b.is_active;
$$;
-- ar_2b_check 꼴: 깊이 0 의 update · delete 에 WHERE 가 없는 수(주석 제거 · 괄호 속은 지움 · 글자 리터럴은 세지 않는다)
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
-- Shopify payload 한 줄 「sku:TO qty:ED qty:is_off」
create temp table t_base as select :'wh_to'::uuid as wh_to, :'wh_ed'::uuid as wh_ed;
create function pg_temp.pl(p_store uuid, p_pids uuid[]) returns text language sql as $$
  select coalesce(string_agg(x.sku || ':' || coalesce(to_q, '-') || ':' || coalesce(ed_q, '-') || ':' || off, ',' order by x.sku), '')
    from (select p.sku, max(p.quantity::text) filter (where p.warehouse_id = (select b.wh_to from t_base b)) as to_q, max(p.quantity::text) filter (where p.warehouse_id = (select b.wh_ed from t_base b)) as ed_q, bool_or(p.is_off)::text as off
            from public.shop_stock_payload(p_store, p_pids) p group by p.sku) x;
$$;

-- ── 가짜 재료 CO1-*: 직원 셋(master+sales · sales 만 · master 만) · 브랜드 · 낱개 A B · 원장 TO A 7 · 손님 · 초안 SO ──
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'co1-ms@test.invalid', 'CO1 master+sales', 'manager', '["ims","master","sales"]', '{}') returning auth_user_id::text as u_ms \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'co1-s@test.invalid', 'CO1 sales only', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as u_s \gset
insert into public.ref_brand (name, source) values ('CO1 Brand', 'manual') returning id::text as br \gset
select id::text as unit from public.ref_unit where is_active order by name limit 1 \gset
select id::text as tier from public.ref_price_tier where purpose = 'sale' and is_active order by name limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset
insert into public.product (sku, name, source, is_active, sellable) values ('CO1-A', 'CO1 component A', 'manual', true, true), ('CO1-B', 'CO1 component B', 'manual', true, true);
select (select id from public.product where sku = 'CO1-A')::text as pa \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values
  (public.ims_today(), 1, 'CO1-A', 'Asung Trading Inc.', 'B061102', 7, 'adjust_existing', 'adjustment', 'COMBOONE1', 'L1', 'manual');
insert into public.customer (name, source, currency_id, price_tier) values ('CO1 Alpha Corp', 'manual', :'cad'::uuid, 'Wholesale') returning id::text as cust \gset
insert into public.so (so_number, customer_id, channel, intake, status, currency_id, location_id, location_name)
  values ('SO-79930', :'cust'::uuid, 'warehouse', 'manual', 'draft', :'cad'::uuid, :'wh_to'::uuid, 'Asung Trading Inc.') returning id::text as so1 \gset
\set itemx2 '{"sku":"CO1-X2","name":"CO1 combo A x2","brand_id":"' :br '","unit_id":"' :unit '","prices":[{"tier_id":"' :tier '","price":5}]}'
\set itemx1 '{"sku":"CO1-X1","name":"CO1 combo A x1","brand_id":"' :br '","unit_id":"' :unit '","prices":[{"tier_id":"' :tier '","price":5}]}'
\set itemy '{"sku":"CO1-Y","name":"CO1 combo A+B","brand_id":"' :br '","unit_id":"' :unit '","prices":[{"tier_id":"' :tier '","price":5}]}'

-- ═══ T1 New combo: A × 2 하나 → 미리 보기 막기 0 · 저장 · 켜진 bom 1 (qty 2) ═══
select set_config('request.jwt.claims', json_build_object('sub', :'u_ms', 'role', 'authenticated')::text, true) \gset
set local role authenticated;
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CO1-A","qty":2}]'::jsonb, false)::text$q$, :'itemx2')) as r1p \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CO1-A","qty":2}]'::jsonb, true, %L::text[])::text$q$, :'itemx2', pg_temp.keys(pg_temp.j(:'r1p')))) as r1c \gset
reset role;
select pg_temp.chk('T1a preview A × 2 → blocks 0', '[' || pg_temp.codes(pg_temp.j(:'r1p')) || ']', '[]');
select pg_temp.chk('T1b commit → committed true · product CO1-X2 exists', coalesce(pg_temp.j(:'r1c')->>'committed', :'r1c') || ' ' || (select count(*) from public.product where sku = 'CO1-X2'), 'true 1');
select pg_temp.chk('T1c active bom rows of CO1-X2 = A × 2 (one row)', pg_temp.bom('CO1-X2'), 'CO1-A×2');

-- ═══ T2 New combo: A × 1 · A × 1.5 · A × "1.0" → component_single · 아무것도 저장 안 됨 ═══
set local role authenticated;
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CO1-A","qty":1}]'::jsonb, true, array['CO1-X1:barcode_missing'])::text$q$, :'itemx1')) as r2a \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CO1-A","qty":1.5}]'::jsonb, false)::text$q$, :'itemx1')) as r2b \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CO1-A","qty":"1.0"}]'::jsonb, false)::text$q$, :'itemx1')) as r2c \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[]'::jsonb, false)::text$q$, :'itemx1')) as r2f \gset
reset role;
select pg_temp.chk('T2a A × 1 (commit) → component_single only · committed false', pg_temp.codes(pg_temp.j(:'r2a')) || ' ' || coalesce(pg_temp.j(:'r2a')->>'committed', '-'), 'component_single false');
select pg_temp.chk('T2b message text (A × 1)', pg_temp.msg(pg_temp.j(:'r2a'), 'component_single'), 'A combo with one component needs a qty of 2 or more (CO1-A × 1) — nothing was saved');
select pg_temp.chk('T2c A × 1.5 → component_single · message shows 1.5', pg_temp.codes(pg_temp.j(:'r2b')) || ' | ' || coalesce(pg_temp.msg(pg_temp.j(:'r2b'), 'component_single'), '-'), 'component_single | A combo with one component needs a qty of 2 or more (CO1-A × 1.5) — nothing was saved');
select pg_temp.chk('T2d A × "1.0" → component_single (rounded value is 1)', pg_temp.codes(pg_temp.j(:'r2c')), 'component_single');
select pg_temp.chk('T2f empty list → components_missing · new message', pg_temp.codes(pg_temp.j(:'r2f')) || ' | ' || coalesce(pg_temp.msg(pg_temp.j(:'r2f'), 'components_missing'), '-'),
  'components_missing | A combo needs at least one component (a single component needs a qty of 2 or more) — nothing was saved');
select pg_temp.chk('T2e CO1-X1 never created · no bom rows for it', (select count(*) from public.product where sku = 'CO1-X1')::text || ' ' || pg_temp.bom('CO1-X1'), '0 ');

-- ═══ T3 product_bom_set: A1 + B1 콤보 → A × 3 하나 → 통과 · → A × 1 하나 → component_single ═══
set local role authenticated;
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CO1-A","qty":1},{"sku":"CO1-B","qty":1}]'::jsonb, false)::text$q$, :'itemy')) as r3p \gset
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CO1-A","qty":1},{"sku":"CO1-B","qty":1}]'::jsonb, true, %L::text[])::text$q$, :'itemy', pg_temp.keys(pg_temp.j(:'r3p')))) as r3c \gset
select pg_temp.bom('CO1-Y') as r3c_bom \gset
select pg_temp.run($q$select public.product_bom_set('CO1-Y', '[{"sku":"CO1-A","qty":3}]'::jsonb, '[{"sku":"CO1-A","qty":1},{"sku":"CO1-B","qty":1}]'::jsonb, false)::text$q$) as r3sp \gset
select pg_temp.run(format($q$select public.product_bom_set('CO1-Y', '[{"sku":"CO1-A","qty":3}]'::jsonb, '[{"sku":"CO1-A","qty":1},{"sku":"CO1-B","qty":1}]'::jsonb, true, %L::text[])::text$q$, pg_temp.keys(pg_temp.j(:'r3sp')))) as r3sc \gset
select pg_temp.run($q$select public.product_bom_set('CO1-Y', '[{"sku":"CO1-A","qty":1}]'::jsonb, '[{"sku":"CO1-A","qty":3}]'::jsonb, true)::text$q$) as r3s1 \gset
reset role;
select pg_temp.chk('T3a two-component combo still born (A1 + B1) · committed true', coalesce(pg_temp.j(:'r3c')->>'committed', :'r3c') || ' ' || :'r3c_bom', 'true CO1-A×1,CO1-B×1');
select pg_temp.chk('T3b bom_set → A × 3: preview blocks 0 · commit committed true · active rows = A × 3', '[' || pg_temp.codes(pg_temp.j(:'r3sp')) || '] ' || coalesce(pg_temp.j(:'r3sc')->>'committed', :'r3sc') || ' ' || pg_temp.bom('CO1-Y'), '[] true CO1-A×3');
select pg_temp.chk('T3c bom_set → A × 1 → component_single · rows stay A × 3', pg_temp.codes(pg_temp.j(:'r3s1')) || ' ' || pg_temp.bom('CO1-Y'), 'component_single CO1-A×3');

-- ═══ T4 판매 길: CO1-X2 를 오더에 3 개 → 콤보 줄 1 + 구성품 줄 1(combo_qty 2 · qty_ordered 6) · 가용 ⌊7 ÷ 2⌋ = 3 ═══
set local role authenticated;
select pg_temp.run(format($q$select public.so_line_add(%L::uuid, (select id from public.product where sku = 'CO1-X2'), 3)::text$q$, :'so1')) as r4 \gset
select pg_temp.run(format($q$select coalesce(string_agg(sku || ':' || is_combo || ':' || trim_scale(qty_ordered) || ':' || coalesce(available_units::text, '-'), ',' order by line_no), '')
                              from public.so_lines_available(%L::uuid)$q$, :'so1')) as r4av \gset
reset role;
select pg_temp.chk('T4a so_line_add ok (no ERR)', (left(:'r4', 4) <> 'ERR ')::text, 'true');
select pg_temp.chk('T4b lines: combo line CO1-X2 × 3 (no combo_line_id) + one component line CO1-A combo_qty 2 · qty_ordered 6 · under the combo line',
  (select string_agg(l.sku || ':' || trim_scale(l.qty_ordered) || ':' || coalesce(trim_scale(l.combo_qty)::text, '-') || ':' || (l.combo_line_id is not null)::text
          || ':' || coalesce((select k.sku from public.so_line k where k.id = l.combo_line_id), '-'), ',' order by l.line_no) from public.so_line l where l.so_id = :'so1'::uuid),
  'CO1-X2:3:-:false:-,CO1-A:6:2:true:CO1-X2');
select pg_temp.chk('T4c so_lines_available: combo line available 3 combos (⌊7 ÷ 2⌋ · the SO screen reads this) · component line 7', :'r4av', 'CO1-X2:true:3:3,CO1-A:false:6:7');

-- ═══ T5 Shopify 콤보 재고: test 스토어 listing(rollback) → CO1-X2 TO ⌊7 ÷ 2⌋ = 3 · ED 0 ═══
insert into public.shop_listing (store_id, product_id, is_on, turned_on_at) select :'test_id'::uuid, p.id, true, now() from public.product p where p.sku = 'CO1-X2';
select pg_temp.chk('T5 shop_stock_payload combo branch, one-component combo A × 2 → TO 3 · ED 0 · is_off false',
  pg_temp.pl(:'test_id'::uuid, array[(select id from public.product where sku = 'CO1-X2')]), 'CO1-X2:3:0:false');

-- ═══ T6 권한: master 없음 → 막힘(아무것도 안 생김) · master 있음은 T1 ═══
select set_config('request.jwt.claims', json_build_object('sub', :'u_s', 'role', 'authenticated')::text, true) \gset
set local role authenticated;
select pg_temp.run(format($q$select public.product_combo_create(%L::jsonb, '[{"sku":"CO1-A","qty":2}]'::jsonb, false)::text$q$, replace(:'itemx2', 'CO1-X2', 'CO1-X3'))) as r6a \gset
select pg_temp.run($q$select public.product_bom_set('CO1-Y', '[{"sku":"CO1-A","qty":4}]'::jsonb, '[{"sku":"CO1-A","qty":3}]'::jsonb, false)::text$q$) as r6b \gset
reset role;
select pg_temp.chk('T6a sales-only staff → product_combo_create refused (ERR) · CO1-X3 absent', (left(:'r6a', 4) = 'ERR ')::text || ' ' || (select count(*) from public.product where sku = 'CO1-X3'), 'true 0');
select pg_temp.chk('T6b sales-only staff → product_bom_set refused (ERR) · rows stay A × 3', (left(:'r6b', 4) = 'ERR ')::text || ' ' || pg_temp.bom('CO1-Y'), 'true CO1-A×3');
select pg_temp.chk('T6c helpers not callable by authenticated · anon (product_bom_check_lines · so_combo_children_insert)',
  (has_function_privilege('authenticated', 'public.product_bom_check_lines(uuid, text, jsonb, jsonb, jsonb, text[])', 'execute') or has_function_privilege('anon', 'public.product_bom_check_lines(uuid, text, jsonb, jsonb, jsonb, text[])', 'execute')
   or has_function_privilege('authenticated', 'public.so_combo_children_insert(public.so_line, uuid)', 'execute') or has_function_privilege('anon', 'public.so_combo_children_insert(public.so_line, uuid)', 'execute'))::text, 'false');
select pg_temp.chk('T6d windows: authenticated yes · anon no (product_combo_create · product_bom_set)',
  (has_function_privilege('authenticated', 'public.product_combo_create(jsonb, jsonb, boolean, text[])', 'execute') and has_function_privilege('authenticated', 'public.product_bom_set(text, jsonb, jsonb, boolean, text[])', 'execute')
   and not has_function_privilege('anon', 'public.product_combo_create(jsonb, jsonb, boolean, text[])', 'execute') and not has_function_privilege('anon', 'public.product_bom_set(text, jsonb, jsonb, boolean, text[])', 'execute'))::text, 'true');

-- ═══ C) 재발행 diff — 옛(begin 뒤 담은 것) 대 새 · 시험 갈래만 ═══
\if :{?mig}
create temp table t_diff as
  with o as (select t.proname, l from t_pre t, regexp_split_to_table(t.prosrc, E'\n') l), n as (select p.proname, l from pg_proc p, regexp_split_to_table(p.prosrc, E'\n') l where p.pronamespace = 'public'::regnamespace and p.proname in ('product_bom_check_lines', 'so_combo_children_insert', 'product_combo_create'))
  select 'removed' as side, proname, l from (select proname, l from o except all select proname, l from n) x
  union all select 'added', proname, l from (select proname, l from n except all select proname, l from o) y;
select pg_temp.chk('C1 changed lines per function: removed/added = check_lines 2/2 · combo_create 1/1 · children_insert 2/2',
  (select string_agg(proname || ' ' || coalesce(sum_r, 0) || '/' || coalesce(sum_a, 0), ' · ' order by proname) from (select proname, count(*) filter (where side = 'removed') sum_r, count(*) filter (where side = 'added') sum_a from t_diff group by proname) z),
  'product_bom_check_lines 2/2 · product_combo_create 1/1 · so_combo_children_insert 2/2');
select pg_temp.chk('C2 removed lines = the old component_single test + message · the old components_missing message · the old v_n < 2 test + message (nothing else)',
  (select string_agg(proname || ':' || left(btrim(l), 40), ' || ' order by proname, btrim(l) collate "C") from t_diff where side = 'removed'),
  'product_bom_check_lines:' || left('if jsonb_array_length(v_new) = 1 and jsonb_array_length(v_blocks) = 0 then', 40) || ' || product_bom_check_lines:' || left('v_blocks := v_blocks || jsonb_build_object(''key'', v_key || '':component_single''', 40)
  || ' || product_combo_create:' || left('v_blocks := v_blocks || jsonb_build_object(''key'', v_key || '':components_missing''', 40)
  || ' || so_combo_children_insert:if v_n < 2 then || so_combo_children_insert:' || left('raise exception ''Combo % has fewer than two components', 40));
\endif

-- ── D) REST 첫 겹 — 정적: 깊이 0 의 update · delete 에 WHERE ──
select pg_temp.chk('D0 scanner self-test: no-where update 1 · where 0 · subquery-where-only 1 · with-update no-where 1 · delete no-where 1 · then-update 1 · string update 0',
  pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text, '1011110');
select pg_temp.chk('D1 reissued last definitions: WHERE-less update · delete = 0',
  (select string_agg(proname || ' ' || pg_temp.nowhere(prosrc)::text, ' · ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('product_bom_check_lines', 'so_combo_children_insert', 'product_combo_create')),
  'product_bom_check_lines 0 · product_combo_create 0 · so_combo_children_insert 0');

-- ── E) 속성 · md5 · 무접촉 ──
select pg_temp.chk('E1 product_bom_check_lines: definer · stable · search_path · owner-only acl · one · comment has 885 · new test line',
  (select prosecdef::text || '/' || provolatile::text || '/' || array_to_string(proconfig, ';') || '/' || coalesce(proacl::text, '-') || '/' || (prosrc ~ $r$\(v_new->0->>'qty'\)::numeric < 2$r$)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_bom_check_lines')
  || '/' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_bom_check_lines') || '/' || (coalesce(obj_description('public.product_bom_check_lines(uuid, text, jsonb, jsonb, jsonb, text[])'::regprocedure, 'pg_proc'), '') like '%판정 885%')::text,
  'true/s/search_path=public, pg_temp/{postgres=X/postgres}/true/1/true');
select pg_temp.chk('E2 so_combo_children_insert: invoker · volatile · search_path · acl postgres + service_role · one · v_n < 1',
  (select prosecdef::text || '/' || provolatile::text || '/' || array_to_string(proconfig, ';') || '/' || coalesce(proacl::text, '-') || '/' || (prosrc like '%if v_n < 1 then%' and prosrc not like '%v_n < 2%')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_combo_children_insert')
  || '/' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_combo_children_insert'),
  'false/v/search_path=public, pg_temp/{postgres=X/postgres,service_role=X/postgres}/true/1');
select pg_temp.chk('E3 comments: product_bom_set · product_combo_create carry 885 and the new rule',
  (coalesce(obj_description('public.product_bom_set(text, jsonb, jsonb, boolean, text[])'::regprocedure, 'pg_proc'), '') like '%판정 885%one component with qty 2 or more%')::text || '/' ||
  (coalesce(obj_description('public.product_combo_create(jsonb, jsonb, boolean, text[])'::regprocedure, 'pg_proc'), '') like '%판정 885%one component with qty 2 or more%')::text, 'true/true');
select pg_temp.chk('E4 untouched (md5 begin 앞 = 지금): product_bom_set · so_line_add · so_lines_paste · so_combo_children_sync · shop_stock_payload',
  (select string_agg((md5(prosrc) = case proname when 'product_bom_set' then :'bset_md5_0' when 'so_line_add' then :'add_md5_0'
                                              when 'so_lines_paste' then :'paste_md5_0' when 'so_combo_children_sync' then :'sync_md5_0' else :'pay_md5_0' end)::text, '/' order by proname)
     from pg_proc where pronamespace = 'public'::regnamespace and proname in ('product_bom_set', 'so_line_add', 'so_lines_paste', 'so_combo_children_sync', 'shop_stock_payload')),
  'true/true/true/true/true');
select pg_temp.chk('E5 every function that reads product_bom: no other 「fewer than two」 / count < 2 test left',
  (select coalesce(string_agg(proname, ','), '') from pg_proc where pronamespace = 'public'::regnamespace and prosrc ~ 'product_bom' and (prosrc ~* 'fewer than two|at least two components' or prosrc ~ 'v_n < 2')
),
  '');
select pg_temp.chk('E6 product_combo_create: definer · volatile · search_path · acl postgres + authenticated · one · comment 885 · table comment product_bom 885 (one component + qty 2 or more)',
  (select prosecdef::text || '/' || provolatile::text || '/' || array_to_string(proconfig, ';') || '/' || coalesce(proacl::text, '-') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_combo_create')
  || '/' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_combo_create') || '/' || (coalesce(obj_description('public.product_combo_create(jsonb, jsonb, boolean, text[])'::regprocedure, 'pg_proc'), '') like '%판정 885%')::text
  || '/' || (coalesce(obj_description('public.product_bom'::regclass, 'pg_class'), '') like '%구성품 하나 + 수량 2 이상(판정 885%')::text,
  'true/v/search_path=public, pg_temp/{postgres=X/postgres,authenticated=X/postgres}/1/true/true');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
select case when (select count(*) from public.product) = :n_prod0 and (select count(*) from public.product_bom) = :n_bom0 and (select count(*) from public.product_bom where is_active) = :n_bom_act0
            and (select count(*) from public.so) = :n_so0 and (select count(*) from public.so_line) = :n_line0 and (select count(*) from public.ims_staff) = :n_staff0
            and (select count(*) from public.inv_ledger) = :n_led0 and (select count(*) from public.shop_listing) = :n_list0
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_bom_check_lines') = :'chk_md5_0'
             and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_combo_children_insert') = :'cci_md5_0'
             and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_combo_create') = :'ccr_md5_0'
             and (select obj_description('public.product_bom'::regclass, 'pg_class')) not like '%판정 885%'
       then 'Z2 OK three functions + table comment back to before' else 'Z2 MISMATCH functions not restored' end as z2;
\endif
