-- pset-1-verify.sql — 세트 더하기 창구 · 세트 규칙 한 곳 · 세트 판매 기본 false(판정 585 ~ 589):
--   ① 동작 동일성(product_create · 같은 입력 묶음 10 을 \i 앞 · 뒤에 — 반환 · 넣은 행 같음 · 다른 것은 세트 sellable 과 판정 587 문장뿐 · I1 ~ I3) · ② 결함 판(S0 · 시험 전용) · ③ product_set_add(A1 ~ A9) · ④ 데이터(D1) · 무접촉(G1 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261021143904_pset_1_set_add.sql -f supabase/tests/pset-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · I1 · I2 · I3 다섯은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 16 − 5 + 1 = **12** · MISMATCH 0
--   가짜 재료는 전부 PSET79… SKU · 가짜 직원 셋(master · sales · 열쇠 없음) · 번호 시퀀스 so_number_seq(A6 의 so_create)는 머리에서 읽고 rollback 뒤 greatest(실제 최대, 머리)
--   ⚠️ 동일성 시험의 각 경우는 pg_temp.trial 이 서브트랜잭션 안에서 돌리고 결과를 예외 메시지로 꺼낸 뒤 되감는다(쓰기 0 이 남는다)

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261021143904' \gset
select :n_applied as schema_migrations_rows_for_20261021143904;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select :so_seq_last as so_number_seq_head, :'so_seq_called' as so_called_head, (select max(substring(so_number from '[0-9]+')::bigint) from public.so) as so_max_head;

begin;
set local statement_timeout = '600s';

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
-- uuid 를 # 로(두 회차의 id 가 다르다)
create function pg_temp.norm(p text) returns text language sql immutable as $$ select regexp_replace(coalesce(p, ''), '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '#', 'g') $$;
-- 가짜 제품 행(sellable 뺀 칸) · 세트 sellable · 바코드 · 가격 — 한 글로
create function pg_temp.rows_snapshot(p_prefix text) returns text language sql security definer as $$
  select 'product:' || coalesce((select string_agg(p.sku || '|' || p.name || '|' || p.source || '|' || coalesce(q.sku, '-') || '|' || coalesce(trim_scale(p.pack_factor)::text, '-') || '|' || coalesce(trim_scale(p.set_discount_pct)::text, '-') || '|' || coalesce(p.brand_name, '-') || '|' || coalesce(p.category_name, '-') || '|' || coalesce(p.uom_name, '-') || '|' || coalesce(p.unit_id::text, '-') || '|' || coalesce(p.registered_on::text, '-') || '|' || p.is_active || '|' || coalesce(p.note, '-'),
                                          E'\n' order by p.sku) from public.product p left join public.product q on q.id = p.parent_product_id where p.sku like p_prefix || '%'), '')
      || E'\nbarcode:' || coalesce((select string_agg(p.sku || '|' || b.barcode || '|' || b.is_primary || '|' || b.source, E'\n' order by p.sku, b.barcode) from public.product_barcode b join public.product p on p.id = b.product_id where p.sku like p_prefix || '%'), '')
      || E'\nprice:' || coalesce((select string_agg(p.sku || '|' || t.name || '|' || trim_scale(pr.price) || '|' || pr.source, E'\n' order by p.sku, t.name) from public.product_price pr join public.product p on p.id = pr.product_id join public.ref_price_tier t on t.id = pr.tier_id where p.sku like p_prefix || '%'), '') $$;
create function pg_temp.sets_sellable(p_prefix text) returns text language sql security definer as $$
  select coalesce((select string_agg(p.sku || ':' || p.sellable || ':' || coalesce(p.sellable_source, '-'), ',' order by p.sku) from public.product p where p.sku like p_prefix || '%' and p.parent_product_id is not null), '(no sets)') $$;
-- 동일성 시험 한 경우: 서브트랜잭션에서 product_create 를 돌리고 반환 + 행을 예외 메시지로 꺼낸 뒤 되감는다
create function pg_temp.trial(p_items jsonb, p_commit boolean, p_ack text[], p_prefix text) returns jsonb language plpgsql as $$
declare v_ret jsonb;
begin
  begin
    v_ret := public.product_create(p_items, p_commit, p_ack);
    raise exception using errcode = 'P7777', message = jsonb_build_object('ret', v_ret, 'rows', pg_temp.rows_snapshot(p_prefix), 'sell', pg_temp.sets_sellable(p_prefix))::text;
  exception when sqlstate 'P7777' then
    return sqlerrm::jsonb;
  when others then
    return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
  end;
end $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'check=' || (to_regprocedure('public.product_set_check(jsonb, jsonb, jsonb)') is not null)::text
      || ' insert=' || (to_regprocedure('public.product_set_insert(jsonb, jsonb, uuid)') is not null)::text
      || ' add=' || (to_regprocedure('public.product_set_add(uuid, jsonb, boolean, text[])') is not null)::text
      || ' core_calls_helpers=' || (select (p.prosrc ~ 'public\.product_set_check\(' and p.prosrc ~ 'public\.product_set_insert\(')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create_core')
      || ' add_auth=' || coalesce((select has_function_privilege('authenticated', p.oid, 'execute')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_set_add'), 'na')
      || ' helpers_auth=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_set_check', 'product_set_insert') and has_function_privilege('authenticated', p.oid, 'execute'))::text $$;
create function pg_temp.fn_md5s() returns text language sql as $$
  select string_agg(p.proname || '=' || md5(p.prosrc) || '/' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_create', 'product_update', 'product_family_create') $$;
create function pg_temp.real_rows() returns text language sql security definer as $$
  select 'sets_sellable_other=' || (select count(*) from public.product x where x.parent_product_id is not null and x.sellable and x.sku not like 'PSET79%' and x.sku not in ('AS85203-72', 'AS85203-6', 'TBR43447-6', 'TBR00182-12', 'TBR16260-6', 'TBR63096-6', 'TBR39231-12'))
      || ' singles=' || (select count(*) || '/' || count(*) filter (where sellable) || '/' || count(*) filter (where is_active) from public.product x where x.parent_product_id is null and x.sku not like 'PSET79%')
      || ' sets=' || (select count(*) || '/' || md5(string_agg(x.sku || ':' || x.pack_factor || ':' || x.is_active, ',' order by x.sku)) from public.product x where x.parent_product_id is not null and x.sku not like 'PSET79%')
      || ' barcodes=' || (select count(*) from public.product_barcode b join public.product p on p.id = b.product_id where p.sku not like 'PSET79%')
      || ' prices=' || (select count(*) from public.product_price pr join public.product p on p.id = pr.product_id where p.sku not like 'PSET79%')
      || ' push_q=' || (select count(*) from public.shop_push_queue) || ' stock_q=' || (select count(*) from public.shop_stock_queue) $$;

\echo '── M0) 가짜 직원 셋(M master · S sales · W 없음) · 참조(브랜드 · 분류 · EA · 판매 티어 · 실제 바코드 둘: 활성 제품의 것 · 꺼진 제품의 것) · 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pset1-m@test.invalid', 'PSET1 M', 'manager', '["ims","master"]', '{}') returning auth_user_id::text as m_uid, id::text as m_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pset1-s@test.invalid', 'PSET1 S', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as s_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pset1-w@test.invalid', 'PSET1 W', 'worker', '[]', '{}') returning auth_user_id::text as w_uid \gset
\set m '{"sub":"' :m_uid '","role":"authenticated"}'
\set s '{"sub":"' :s_uid '","role":"authenticated"}'
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
select b.id::text as brand, b.name as brand_name from public.ref_brand b where b.is_active and not exists (select 1 from public.product p where p.brand_id = b.id and p.is_active and p.parent_product_id is null) order by b.name limit 1 \gset
select s.id::text as sup, s.name as sup_name from public.supplier s where s.is_active order by s.name limit 1 \gset
select c.id::text as cat, c.name as cat_name from public.ref_category c where c.is_active order by c.name limit 1 \gset
select u.id::text as unit_ea from public.ref_unit u where u.name = 'EA' and u.is_active \gset
select t.id::text as tier, t.name as tier_name from public.ref_price_tier t where t.purpose = 'sale' and t.is_active order by t.name limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select rt.name as tier_sale_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as tax_rule, name as tax_rule_name from public.ref_tax_rule where name = 'Exempt (Sale)' and is_active \gset
select pb.barcode as act_bc, p.sku as act_bc_sku from public.product_barcode pb join public.product p on p.id = pb.product_id where p.is_active and pb.is_active and pb.barcode ~ '^[0-9]{12,13}$' and not exists (select 1 from public.product_barcode q where q.barcode = pb.barcode and q.id <> pb.id) order by p.sku limit 1 \gset
select pb.barcode as inact_bc, p.sku as inact_bc_sku from public.product_barcode pb join public.product p on p.id = pb.product_id where not p.is_active and pb.barcode ~ '^[0-9]{12,13}$' and not exists (select 1 from public.product_barcode q join public.product r on r.id = q.product_id where q.barcode = pb.barcode and r.is_active and q.is_active) order by p.sku limit 1 \gset
select (select count(*) from public.ref_unit u where u.name = '7' and u.is_active) as unit7 \gset
select pg_temp.real_rows() as real_before, pg_temp.fn_md5s() as md5_before, pg_temp.gate_state() as gate_before \gset
select pg_temp.chk(format('M0 staff ×3 · brand %s (no active singles — no sku_prefix warning) · supplier %s · category %s · tier %s · active barcode %s (%s) · inactive barcode %s (%s) · unit "7" absent · snapshots taken', :'brand_name', :'sup_name', :'cat_name', :'tier_name', :'act_bc', :'act_bc_sku', :'inact_bc', :'inact_bc_sku'),
  :'m_uid' <> '' and :'brand' <> '' and :'sup' <> '' and :'cat' <> '' and :'unit_ea' <> '' and :'tier' <> '' and :'act_bc' <> '' and :'inact_bc' <> '' and :unit7 = 0 and :'real_before' <> '', 'see M0');

\echo '── M1) 동일성 재료 — 꺼진 제품 PSET79I-6(판정 587 경우) · 입력 묶음 열(psql 변수)'
set local session_replication_role = replica;
insert into public.product (sku, name, source, is_active, registered_on) values ('PSET79I-6', 'PSET79 I six (inactive)', 'manual', false, public.ims_today());
set local session_replication_role = origin;
\set base '"brand_id":"' :brand '","category_id":"' :cat '","unit_id":"' :unit_ea '","suppliers":[{"supplier_id":"' :sup '"}]'
\set tA '[{"sku":"PSET79A","name":"PSET79 A",' :base ',"barcodes":["79000001"],"prices":[{"tier_id":"' :tier '","price":10}]}]'
\set tB '[{"sku":"PSET79B","name":"PSET79 B",' :base ',"barcodes":["79000002"],"prices":[{"tier_id":"' :tier '","price":10}],"sets":[{"pack_factor":6,"barcodes":["79000026"],"set_discount_pct":10,"name":"PSET79 B six"},{"pack_factor":12}]}]'
\set tC '[{"sku":"PSET79C","name":"PSET79 C",' :base ',"sets":[{"pack_factor":6,"barcodes":["' :act_bc '"]}]}]'
\set tD '[{"sku":"PSET79D","name":"PSET79 D",' :base ',"barcodes":["79000004"],"prices":[{"tier_id":"' :tier '","price":10}],"sets":[{"pack_factor":6,"barcodes":["' :inact_bc '"]}]}]'
\set tE '[{"sku":"PSET79E","name":"PSET79 E",' :base ',"barcodes":["79000005"],"prices":[{"tier_id":"' :tier '","price":10}],"sets":[{"pack_factor":7}]}]'
\set tF '[{"sku":"PSET79F","name":"PSET79 F",' :base ',"sets":[{"pack_factor":6,"set_discount_pct":150}]}]'
\set tG '[{"sku":"PSET79G","name":"PSET79 G",' :base ',"sets":[{"pack_factor":6},{"pack_factor":6}]}]'
\set tI '[{"sku":"PSET79I","name":"PSET79 I",' :base ',"sets":[{"pack_factor":6}]}]'
\set tJ '[{"sku":"PSET79J","name":"PSET79 J",' :base ',"barcodes":["79000003"],"sets":[{"pack_factor":6,"barcodes":["79000036"]}]},{"sku":"PSET79J-6","name":"PSET79 J dup",' :base ',"barcodes":["79000036"]}]'
\set ackD '''{"PSET79D-6:barcode_inactive_elsewhere:' :inact_bc '"}''::text[]'
\set ackE '''{"PSET79E-7:set_unit_unknown"}''::text[]'
create temp table t_ident (phase text, c text, ret text, rows_ text, sell text);
create function pg_temp.ident(p_phase text) returns int language plpgsql security definer as $$   -- definer: authenticated 구간에서 임시 표에 쓴다(§4 규칙)
declare v jsonb; v_n int := 0;
  v_cases jsonb := current_setting('pset1.cases', true)::jsonb;
  c jsonb;
begin
  for c in select x from jsonb_array_elements(v_cases) as x loop
    v := pg_temp.trial(c->'items', (c->>'commit')::boolean, coalesce((select array_agg(a) from jsonb_array_elements_text(coalesce(c->'ack', '[]'::jsonb)) a), '{}'), 'PSET79');
    insert into t_ident values (p_phase, c->>'c', pg_temp.norm(coalesce((v->'ret')::text, v->>'err')), v->>'rows', v->>'sell');
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
select set_config('pset1.cases', jsonb_build_array(
  jsonb_build_object('c', 'A single only · commit',                 'items', :'tA'::jsonb, 'commit', true),
  jsonb_build_object('c', 'B single + sets ×6(bc·disc·name) ×12 · commit', 'items', :'tB'::jsonb, 'commit', true),
  jsonb_build_object('c', 'C set barcode of an active product · block', 'items', :'tC'::jsonb, 'commit', true),
  jsonb_build_object('c', 'D1 set barcode of an inactive product · warn · no ack', 'items', :'tD'::jsonb, 'commit', true),
  jsonb_build_object('c', 'D2 same · ack · saved',                  'items', :'tD'::jsonb, 'commit', true, 'ack', jsonb_build_array('PSET79D-6:barcode_inactive_elsewhere:' || :'inact_bc')),
  jsonb_build_object('c', 'E factor 7 (no unit) · warn · ack · saved', 'items', :'tE'::jsonb, 'commit', true, 'ack', jsonb_build_array('PSET79E-7:set_unit_unknown')),
  jsonb_build_object('c', 'F discount 150 · block',                 'items', :'tF'::jsonb, 'commit', true),
  jsonb_build_object('c', 'G factor 6 twice · block',               'items', :'tG'::jsonb, 'commit', true),
  jsonb_build_object('c', 'H preview of B',                         'items', :'tB'::jsonb, 'commit', false),
  jsonb_build_object('c', 'I inactive set PSET79I-6 exists · block (587 differs)', 'items', :'tI'::jsonb, 'commit', true),
  jsonb_build_object('c', 'J seen shared: set sku · set barcode reused by 2nd item · block', 'items', :'tJ'::jsonb, 'commit', true)
)::text, true) as cases_set;

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — New product 로 세트를 지으면 sellable true · 세트 더하기 창구 없음 · 7 개 sellable true'
set local role authenticated;
select set_config('request.jwt.claims', :'m', true) as claims;
select pg_temp.trial(:'tB'::jsonb, true, '{}', 'PSET79') as s0_trial \gset
select coalesce(pg_temp.j(:'s0_trial')->>'sell', 'null') as s0_sell \gset
reset role;
select (select count(*) from public.product where sku in ('AS85203-72', 'AS85203-6', 'TBR43447-6', 'TBR00182-12', 'TBR16260-6', 'TBR63096-6', 'TBR39231-12') and sellable and sellable_source is null) as s0_seven \gset
select pg_temp.chk('S0 before the trial: product_create makes sets with sellable true (PSET79B-6 · PSET79B-12) · no product_set_add · helpers absent · the 7 hand-made sets are sellable true with sellable_source null · not in schema_migrations',
  :'s0_sell' = 'PSET79B-12:true:-,PSET79B-6:true:-' and :'gate_before' like 'check=false insert=false add=false %' and :s0_seven = 7 and :n_applied = 0,
  format('sell %s | trial %s | gate %s | seven %s | n_applied %s', :'s0_sell', left(:'s0_trial', 500), :'gate_before', :s0_seven, :n_applied));
\echo '── I0) 동일성 — 옛 판으로 열한 경우(savepoint 꼴 · 되감김)'
set local role authenticated;
select set_config('request.jwt.claims', :'m', true) as claims;
select pg_temp.ident('old') as old_cases \gset
reset role;
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: product_create · product_update · product_family_create bodies and ACLs unchanged', pg_temp.fn_md5s() = :'md5_before', format('before %s | after %s', :'md5_before', pg_temp.fn_md5s()));
\echo '── I1 ~ I3) 동일성 — 새 판으로 같은 열한 경우 · 비교'
set local role authenticated;
select set_config('request.jwt.claims', :'m', true) as claims;
select pg_temp.ident('new') as new_cases \gset
reset role;
select count(*) filter (where o.ret = n.ret) as same_ret, count(*) filter (where o.rows_ = n.rows_) as same_rows, count(*) as n_cases,
       coalesce(string_agg(o.c, ' | ' order by o.c) filter (where o.ret <> n.ret), '-') as diff_ret_cases,
       coalesce(string_agg(o.c, ' | ' order by o.c) filter (where o.rows_ <> n.rows_), '-') as diff_rows_cases,
       coalesce(string_agg(o.c || ': ' || o.sell || ' → ' || n.sell, ' | ' order by o.c) filter (where o.sell <> n.sell), '-') as sell_changes,
       count(*) filter (where o.sell <> n.sell) as n_sell_changes,
       count(*) filter (where o.sell <> n.sell and o.sell ~ ':true:' and n.sell !~ ':true:' and replace(o.sell, ':true:', ':false:') = n.sell) as n_sell_true_to_false
  from t_ident o join t_ident n on n.c = o.c and n.phase = 'new' where o.phase = 'old' \gset
select o.ret as i_old_ret, n.ret as i_new_ret from t_ident o join t_ident n on n.c = o.c and n.phase = 'new' where o.phase = 'old' and o.c like 'I %' \gset
select pg_temp.chk(format('I1 same return for %s of %s cases — the only different case is I (587 wording) · rows identical in all %s (uuid · time columns excluded · sellable excluded)', :same_ret, :n_cases, :n_cases),
  :n_cases = 11 and :same_ret = 10 and :'diff_ret_cases' = 'I inactive set PSET79I-6 exists · block (587 differs)' and :same_rows = 11,
  format('same_ret %s | diff_ret %s | same_rows %s | diff_rows %s', :same_ret, :'diff_ret_cases', :same_rows, :'diff_rows_cases'));
select pg_temp.chk('I2 case I: old block = set_sku_exists · new block = set_sku_inactive_exists with existing_product_id · nothing else differs in that return',
  :'i_old_ret' like '%"set_sku_exists"%' and :'i_old_ret' not like '%inactive_exists%' and :'i_new_ret' like '%"set_sku_inactive_exists"%' and :'i_new_ret' like '%"existing_product_id": "#"%' and :'i_new_ret' like '%switch Active on in Edit%'
  and replace(replace(replace(:'i_new_ret', 'set_sku_inactive_exists', 'set_sku_exists'), ' already exists but is inactive — open it in Products and switch Active on in Edit instead of making it again — nothing was saved', ' already exists — nothing was saved'), ', "existing_product_id": "#"', '') = :'i_old_ret',
  format('old %s | new %s', left(:'i_old_ret', 300), left(:'i_new_ret', 400)));
select pg_temp.chk(format('I3 sets sellable: %s cases changed and every change is true → false only (B · D2 · E — the three that save sets) · preview/blocked cases unchanged', :n_sell_changes),
  :n_sell_changes = 3 and :n_sell_true_to_false = 3 and :'sell_changes' like '%B single%' and :'sell_changes' like '%D2 same%' and :'sell_changes' like '%E factor 7%',
  :'sell_changes' || ' | per case: ' || (select string_agg(n.c || '=' || coalesce((pg_temp.j(n.ret)->>'committed'), 'err') || coalesce(' unacked ' || (pg_temp.j(n.ret)->'unacked')::text, ''), ' ; ' order by n.c) from t_ident n where n.phase = 'new'));
\else
select pg_temp.chk('P0c confirm run: migration 20261021143904 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() like 'check=true insert=true add=true core_calls_helpers=true %') as landed \gset
\if :landed
\echo '── G1) 실물 — 도우미 둘 · 창구 · core 가 도우미를 부른다 · ACL(도우미는 authenticated 불가 · 창구는 가능) · 세 창구 md5 무변'
select pg_temp.chk('G1 gate state exact · product_create/update/family_create unchanged', pg_temp.gate_state() = 'check=true insert=true add=true core_calls_helpers=true add_auth=true helpers_auth=0' and pg_temp.fn_md5s() = :'md5_before', pg_temp.gate_state());

\echo '── A0) 재료 — product_create 로 낱개 PSET79P(판매가 10 · 바코드) · replica: 꺼진 낱개 Q · 콤보 부모 R · 단종 S · 판매 안 함 T · U(꺼진 세트 U-6 · 계수 12 인 옛 꼴 세트 U-X)'
set local role authenticated;
select set_config('request.jwt.claims', :'m', true) as claims;
select pg_temp.as_user(:'m', format('select public.product_create(%L::jsonb, true, ''{}'')::text', ('[{"sku":"PSET79P","name":"PSET79 P",' || :'base' || ',"barcodes":["79000010"],"prices":[{"tier_id":"' || :'tier' || '","price":10}]}]'))) as a0 \gset
reset role;
select coalesce(pg_temp.j(:'a0')->'items'->0->>'product_id', '00000000-0000-0000-0000-000000000000') as pid_p \gset
set local session_replication_role = replica;
insert into public.product (sku, name, source, is_active, registered_on, brand_id, brand_name, category_id, category_name) values ('PSET79Q', 'PSET79 Q (inactive)', 'manual', false, public.ims_today(), :'brand'::uuid, :'brand_name', :'cat'::uuid, :'cat_name') returning id::text as pid_q \gset
insert into public.product (sku, name, source, registered_on) values ('PSET79R', 'PSET79 R (combo)', 'manual', public.ims_today()) returning id::text as pid_r \gset
insert into public.product_bom (parent_product_id, component_product_id, quantity, source, is_active) values (:'pid_r'::uuid, :'pid_p'::uuid, 2, 'manual', true);
insert into public.product (sku, name, source, registered_on, is_discontinued) values ('PSET79S', 'PSET79 S (discontinued)', 'manual', public.ims_today(), true) returning id::text as pid_s \gset
insert into public.product (sku, name, source, registered_on, sellable, sellable_source) values ('PSET79T', 'PSET79 T (not for sale)', 'manual', public.ims_today(), false, 'ims') returning id::text as pid_t \gset
insert into public.product (sku, name, source, registered_on) values ('PSET79U', 'PSET79 U', 'manual', public.ims_today()) returning id::text as pid_u \gset
insert into public.product (sku, name, source, parent_product_id, pack_factor, uom_name, is_active, sellable, registered_on) values ('PSET79U-6', 'PSET79 U-6 (inactive)', 'manual', :'pid_u'::uuid, 6, '6', false, false, public.ims_today()) returning id::text as pid_u6 \gset
insert into public.product (sku, name, source, parent_product_id, pack_factor, uom_name, is_active, sellable, registered_on) values ('PSET79U-X', 'PSET79 U-X (odd sku · 12)', 'manual', :'pid_u'::uuid, 12, '12', true, false, public.ims_today()) returning id::text as pid_ux \gset
set local session_replication_role = origin;
select pg_temp.chk('A0 fixtures: PSET79P created (price 10 · barcode) · Q inactive · R combo parent · S discontinued · T not sellable · U with inactive U-6 and odd-sku ×12 U-X',
  :'a0' not like 'ERR%' and pg_temp.j(:'a0')->>'committed' = 'true' and :'pid_q' <> '' and :'pid_r' <> '' and :'pid_u6' <> '' and :'pid_ux' <> '', left(:'a0', 200));

\echo '── A1) 미리 보기 — P 에 ×6(바코드 · 할인 10 · 이름) · ×12 → committed false · 세트 SKU · 이름 · sellable false · scan_adds · 행 0'
\set setsP '[{"pack_factor":6,"barcodes":["79000016"],"set_discount_pct":10,"name":"PSET79 P six"},{"pack_factor":12}]'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, %L::jsonb, false, ''{}'')::text', :'pid_p', :'setsP')) as a1 \gset
reset role;
select pg_temp.chk('A1 preview: committed false · blocks 0 · sets[0] {sku PSET79P-6 · name "PSET79 P six" · pack 6 · discount 10 · sellable false · scan_adds "PSET79P × 6"} · sets[1] {sku PSET79P-12 · name "PSET79 P-12" (auto)} · no product rows yet',
  :'a1' not like 'ERR%' and pg_temp.j(:'a1')->>'committed' = 'false' and jsonb_array_length(pg_temp.j(:'a1')->'blocks') = 0
  and pg_temp.j(:'a1')->'items'->0->'sets'->0->>'sku' = 'PSET79P-6' and pg_temp.j(:'a1')->'items'->0->'sets'->0->>'name' = 'PSET79 P six' and pg_temp.j(:'a1')->'items'->0->'sets'->0->>'sellable' = 'false'
  and pg_temp.j(:'a1')->'items'->0->'sets'->0->>'scan_adds' = 'PSET79P × 6' and (pg_temp.j(:'a1')->'items'->0->'sets'->0->>'set_discount_pct')::numeric = 10
  and pg_temp.j(:'a1')->'items'->0->'sets'->1->>'sku' = 'PSET79P-12' and pg_temp.j(:'a1')->'items'->0->'sets'->1->>'name' = 'PSET79 P-12'
  and (select count(*) from public.product where sku like 'PSET79P-%') = 0,
  left(:'a1', 600));

\echo '── A2) 저장 → product 행 둘(parent · pack · brand · category · unit 6/12 · uom · registered_on · sellable false · source manual) · 바코드 primary · so_price_for = 10 × 6 × 0.9 = 54.00 set_calc · 12 → 120.00 · so_available(set) = so_available(single) · shop_listing 0'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, %L::jsonb, true, ''{}'')::text', :'pid_p', :'setsP')) as a2 \gset
reset role;
select coalesce(pg_temp.j(:'a2')->'items'->0->'sets'->0->>'product_id', '00000000-0000-0000-0000-000000000000') as pid_p6, coalesce(pg_temp.j(:'a2')->'items'->0->'sets'->1->>'product_id', '00000000-0000-0000-0000-000000000000') as pid_p12 \gset
select (select string_agg(s.sku || '|' || s.name || '|' || s.source || '|' || (s.parent_product_id = :'pid_p'::uuid) || '|' || trim_scale(s.pack_factor) || '|' || coalesce(trim_scale(s.set_discount_pct)::text, '-') || '|' || coalesce(s.brand_name, '-') || '|' || coalesce(s.category_name, '-') || '|' || coalesce(u.name, '-') || '|' || s.uom_name || '|' || (s.registered_on = public.ims_today()) || '|' || s.sellable || '|' || coalesce(s.sellable_source, '-') || '|' || s.is_active, E'\n' order by s.sku)
          from public.product s left join public.ref_unit u on u.id = s.unit_id where s.parent_product_id = :'pid_p'::uuid) as a2_rows \gset
select (select string_agg(b.barcode || ':' || b.is_primary || ':' || b.source, ',') from public.product_barcode b where b.product_id = :'pid_p6'::uuid) as a2_bc \gset
select (select list_price || '|' || price_source from public.so_price_for(:'pid_p6'::uuid, :'tier'::uuid)) as a2_price6, (select list_price || '|' || price_source from public.so_price_for(:'pid_p12'::uuid, :'tier'::uuid)) as a2_price12 \gset
select public.so_available(:'pid_p6'::uuid, :'wh'::uuid)::text as a2_av_set, public.so_available(:'pid_p'::uuid, :'wh'::uuid)::text as a2_av_single \gset
select pg_temp.chk('A2 saved: 2 set rows exactly as expected (manual · parent P · 6 @10% · 12 · brand · category · unit 6/12 · uom · today · sellable false · source null · active) · barcode 79000016 primary manual · price 54.00|set_calc · 120.00|set_calc · available(set) = available(single) · no shop_listing',
  :'a2' not like 'ERR%' and pg_temp.j(:'a2')->>'committed' = 'true' and pg_temp.j(:'a2')->'items'->0->'sets'->0->>'sellable' = 'false' and pg_temp.j(:'a2')->'items'->0->'sets'->0->>'scan_adds' = 'PSET79P × 6'
  and :'a2_rows' = format(E'PSET79P-12|PSET79 P-12|manual|true|12|-|%s|%s|12|12|true|false|-|true\nPSET79P-6|PSET79 P six|manual|true|6|10|%s|%s|6|6|true|false|-|true', :'brand_name', :'cat_name', :'brand_name', :'cat_name')
  and :'a2_bc' = '79000016:true:manual' and :'a2_price6' = '54.00|set_calc' and :'a2_price12' = '120.00|set_calc' and :'a2_av_set' = :'a2_av_single'
  and (select count(*) from public.shop_listing l where l.product_id in (:'pid_p6'::uuid, :'pid_p12'::uuid)) = 0,
  format('a2 %s | rows %s | bc %s | price %s/%s | av %s/%s', left(:'a2', 200), replace(:'a2_rows', E'\n', ' ‖ '), :'a2_bc', :'a2_price6', :'a2_price12', :'a2_av_set', :'a2_av_single'));

\echo '── A3) 막기 — 활성 같은 계수(set_sku_exists) · 꺼진 같은 계수 U-6(set_sku_inactive_exists + existing_product_id · 판정 587) · 꺼진 낱개 Q · 세트에 세트(P-6) · 콤보 부모 R · 계수 1 · 2.5 · 빈 바코드 · 활성 제품 바코드 · prices(589) · 같은 계수 옛 꼴 세트 U-X(set_factor_exists) · 빈 sets(예외) · 없는 부모'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":6}]''::jsonb, true, ''{}'')::text', :'pid_p')) as b_active \gset
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":6}]''::jsonb, true, ''{}'')::text', :'pid_u')) as b_inact \gset
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":12}]''::jsonb, true, ''{}'')::text', :'pid_u')) as b_factor \gset
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":6}]''::jsonb, true, ''{}'')::text', :'pid_q')) as b_q \gset
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":2}]''::jsonb, true, ''{}'')::text', :'pid_p6')) as b_setset \gset
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":6}]''::jsonb, true, ''{}'')::text', :'pid_r')) as b_combo \gset
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":1},{"pack_factor":2.5},{"pack_factor":3,"barcodes":[""]},{"pack_factor":4,"barcodes":["%s"]},{"pack_factor":5,"prices":[{"tier_id":"%s","price":1}]}]''::jsonb, true, ''{}'')::text', :'pid_p', :'act_bc', :'tier')) as b_many \gset
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[]''::jsonb, true, ''{}'')::text', :'pid_p')) as b_empty \gset
select pg_temp.as_user(:'m', 'select public.product_set_add(''00000000-0000-0000-0000-000000000000''::uuid, ''[{"pack_factor":6}]''::jsonb, true, ''{}'')::text') as b_none \gset
reset role;
create function pg_temp.codes(p text) returns text language sql as $$ select coalesce((select string_agg(b->>'code', ',' order by b->>'code') from jsonb_array_elements(pg_temp.j(p)->'blocks') b), coalesce(left(p, 80), '-')) $$;
select pg_temp.chk('A3 blocks: set_sku_exists · set_sku_inactive_exists(+existing_product_id = U-6 · "Edit") · set_factor_exists(+existing_sku U-X) · parent_inactive · parent_is_set · parent_is_combo · [set_factor_invalid ×2, barcode_empty, barcode_active_elsewhere, set_prices_not_here] · empty sets → exception · unknown parent → parent_unknown · nothing saved',
  pg_temp.codes(:'b_active') = 'set_sku_exists'
  and pg_temp.codes(:'b_inact') = 'set_sku_inactive_exists' and pg_temp.j(:'b_inact')->'blocks'->0->>'existing_product_id' = :'pid_u6' and pg_temp.j(:'b_inact')->'blocks'->0->>'message' like '%Edit%'
  and pg_temp.codes(:'b_factor') = 'set_factor_exists' and pg_temp.j(:'b_factor')->'blocks'->0->>'existing_sku' = 'PSET79U-X' and pg_temp.j(:'b_factor')->'blocks'->0->>'existing_product_id' = :'pid_ux'
  and pg_temp.codes(:'b_q') = 'parent_inactive' and pg_temp.codes(:'b_setset') = 'parent_is_set' and pg_temp.codes(:'b_combo') = 'parent_is_combo'
  and pg_temp.codes(:'b_many') = 'barcode_active_elsewhere,barcode_empty,set_factor_invalid,set_factor_invalid,set_prices_not_here'
  and :'b_empty' like 'ERR%' and :'b_empty' like '%p_sets must be a JSON array%' and pg_temp.codes(:'b_none') = 'parent_unknown'
  and (select count(*) from public.product where sku like 'PSET79%' and parent_product_id is not null) = 4,
  format('active %s | inact %s | factor %s | q %s | setset %s | combo %s | many %s | empty %s | none %s', pg_temp.codes(:'b_active'), pg_temp.codes(:'b_inact'), pg_temp.codes(:'b_factor'), pg_temp.codes(:'b_q'), pg_temp.codes(:'b_setset'), pg_temp.codes(:'b_combo'), pg_temp.codes(:'b_many'), left(:'b_empty', 80), pg_temp.codes(:'b_none')));

\echo '── A4) 경고 → 확인 — 단종 S(×6 · 계수 7 단위 없음 · 꺼진 제품 바코드) · 판매 안 함 T(×6) → ack 없이 저장 안 됨(unacked) · ack 하면 저장(sellable false)'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":7,"barcodes":["%s"]}]''::jsonb, true, ''{}'')::text', :'pid_s', :'inact_bc')) as w_s0 \gset
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":7,"barcodes":["%s"]}]''::jsonb, true, ''{"PSET79S:parent_discontinued","PSET79S-7:set_unit_unknown","PSET79S-7:barcode_inactive_elsewhere:%s"}''::text[])::text', :'pid_s', :'inact_bc', :'inact_bc')) as w_s1 \gset
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":6}]''::jsonb, true, ''{}'')::text', :'pid_t')) as w_t0 \gset
select pg_temp.as_user(:'m', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":6}]''::jsonb, true, ''{"PSET79T:parent_not_sellable"}''::text[])::text', :'pid_t')) as w_t1 \gset
reset role;
create function pg_temp.wcodes(p text) returns text language sql as $$ select coalesce((select string_agg(w->>'code', ',' order by w->>'code') from jsonb_array_elements(pg_temp.j(p)->'warnings') w), coalesce(left(p, 80), '-')) $$;
select pg_temp.chk('A4 warnings: S → parent_discontinued + set_unit_unknown + barcode_inactive_elsewhere (unacked 3 · not saved) → acked → saved PSET79S-7 (uom 7 · no unit id · sellable false) · T → parent_not_sellable (unacked 1) → acked → saved PSET79T-6 sellable false',
  pg_temp.wcodes(:'w_s0') = 'barcode_inactive_elsewhere,parent_discontinued,set_unit_unknown' and pg_temp.j(:'w_s0')->>'committed' = 'false' and jsonb_array_length(pg_temp.j(:'w_s0')->'unacked') = 3
  and pg_temp.j(:'w_s1')->>'committed' = 'true' and (select s.uom_name || '|' || coalesce(s.unit_id::text, 'nounit') || '|' || s.sellable from public.product s where s.sku = 'PSET79S-7') = '7|nounit|false'
  and pg_temp.wcodes(:'w_t0') = 'parent_not_sellable' and pg_temp.j(:'w_t0')->>'committed' = 'false' and jsonb_array_length(pg_temp.j(:'w_t0')->'unacked') = 1
  and pg_temp.j(:'w_t1')->>'committed' = 'true' and (select s.sellable from public.product s where s.sku = 'PSET79T-6') = false,
  format('s0 %s | s1 %s | t0 %s | t1 %s', pg_temp.wcodes(:'w_s0'), left(:'w_s1', 120), pg_temp.wcodes(:'w_t0'), left(:'w_t1', 120)));

\echo '── A5) 문 — master 없는 직원(sales 만 · 열쇠 없음) → ims_require_write 거부 · 도우미 둘은 authenticated 가 직접 못 부른다(42501)'
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":2}]''::jsonb, false, ''{}'')::text', :'pid_p')) as g_s \gset
select pg_temp.as_user(:'w', format('select public.product_set_add(%L::uuid, ''[{"pack_factor":2}]''::jsonb, false, ''{}'')::text', :'pid_p')) as g_w \gset
select pg_temp.as_user(:'m', 'select public.product_set_check(''{"sku":"X"}''::jsonb, ''[]''::jsonb, ''{}''::jsonb)::text') as g_h1 \gset
select pg_temp.as_user(:'m', format('select public.product_set_insert(''{"sku":"X"}''::jsonb, ''[]''::jsonb, %L::uuid)::text', :'m_id')) as g_h2 \gset
reset role;
select pg_temp.chk('A5 gate: sales-only and keyless staff refused ("cannot change master data") · helpers refused 42501 even for master staff',
  :'g_s' like 'ERR%' and :'g_s' like '%cannot change master data%' and :'g_w' like 'ERR%' and :'g_w' like '%cannot change master data%'
  and :'g_h1' like 'ERR 42501%' and :'g_h2' like 'ERR 42501%',
  format('s %s | w %s | h1 %s | h2 %s', left(:'g_s', 100), left(:'g_w', 100), left(:'g_h1', 80), left(:'g_h2', 80)));

\echo '── A6) 따라오는 것 — S(sales)가 초안 오더에 세트 SKU PSET79P-6 ×2 를 붙여넣으면 낱개 PSET79P × 12 로 바뀐다(판매 안 함 세트 · 판정 281 · 293)'
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id) values ('PSET1 Customer', 'manual', :'tier_sale_name', :'wh'::uuid, 0, :'cad'::uuid) returning id::text as cust \gset
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''pset-1 test'')::text', :'cust', :'wh')) as so0 \gset
select coalesce(pg_temp.j(:'so0')->>'id', '00000000-0000-0000-0000-000000000000') as so1 \gset
select pg_temp.as_user(:'s', format('select public.so_lines_paste(%L::uuid, ''[{"sku":"PSET79P-6","qty":"2"}]''::jsonb, true)::text', :'so1')) as paste \gset
reset role;
select pg_temp.chk('A6 paste PSET79P-6 ×2 as sales: converted → one line PSET79P qty 12',
  :'so0' not like 'ERR%' and :'paste' not like 'ERR%' and pg_temp.j(:'paste')->'lines'->0->>'verdict' = 'ok' and pg_temp.j(:'paste')->'lines'->0->'converted'->>'set_sku' = 'PSET79P-6' and (pg_temp.j(:'paste')->'lines'->0->'converted'->>'base_qty')::numeric = 12
  and (select string_agg(l.sku || ':' || trim_scale(l.qty_ordered), ',' order by l.line_no) from public.so_line l where l.so_id = :'so1'::uuid) = 'PSET79P:12',
  format('so0 %s | paste %s | lines %s', left(:'so0', 80), left(:'paste', 240), (select string_agg(l.sku || ':' || trim_scale(l.qty_ordered), ',') from public.so_line l where l.so_id = :'so1'::uuid)));

\echo '── D1) 데이터(판정 585) — 7 개 sellable false · sellable_source ims · 다른 세트 · 낱개 집계 무변 · Shopify 큐 무변'
select pg_temp.chk('D1 the 7 hand-made sets are sellable false · sellable_source ims · no other manual set sellable · real aggregates unchanged (sets · singles · barcodes · prices · shop queues)',
  (select count(*) from public.product where sku in ('AS85203-72', 'AS85203-6', 'TBR43447-6', 'TBR00182-12', 'TBR16260-6', 'TBR63096-6', 'TBR39231-12') and not sellable and sellable_source = 'ims') = 7
  and (select count(*) from public.product where source = 'manual' and parent_product_id is not null and sellable and sku not like 'PSET79%') = 0
  and pg_temp.real_rows() = :'real_before',
  format('seven %s | before %s | after %s', (select count(*) from public.product where sku in ('AS85203-72', 'AS85203-6', 'TBR43447-6', 'TBR00182-12', 'TBR16260-6', 'TBR63096-6', 'TBR39231-12') and not sellable and sellable_source = 'ims'), :'real_before', pg_temp.real_rows()));

\echo '── A7) 화면 재료 — 미리 보기 반환 원문(대화 Claude 가 Add set 창을 쓸 재료 · 판정 아님)'
select 'product_set_add preview: ' || :'a1' as shape union all select 'product_set_add commit: ' || :'a2' union all select 'block 587: ' || :'b_inact' union all select 'block set_factor_exists: ' || :'b_factor' union all select 'warnings S: ' || :'w_s0';
\else
select pg_temp.chk('G1 ~ D1 skipped: pset-1 not landed', false, 'not landed — nothing to exercise');
\endif

\echo '── Z1) 실제 행 무접촉(PSET79 · 일곱 제외)'
select pg_temp.chk('Z1 real rows untouched', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · so_number_seq 되돌리기'
select (select count(*) from public.product where sku like 'PSET79%') + (select count(*) from public.ims_staff where email like 'pset1-%') + (select count(*) from public.customer where name = 'PSET1 Customer') as fake_traces_left;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select last_value as so_seq_last_after, is_called as so_seq_called_after from public.so_number_seq;
