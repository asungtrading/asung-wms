-- ch-1-verify.sql — packed 오더에 비용 더하기 · 고치기 · 지우기(판정 531 · 539 · 540 · 549) · so_charge_gate · aone 거부 · 다른 상태 거부 · so_finalize 와 인보이스 · shop_order_freight 그대로
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020134522_ch_1_packed_charges.sql -f supabase/tests/ch-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0(옛 함수 · packed 거부 재현) · G0 는 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더
--   재료: 직원 셋 가짜(CH1 sales A · sales+master M · master-only O) · 오더는 so_create 로 시험 스토어 손님 「TEST IMS Shopify」(91442ea9) 밑에 · 제품 AS91581(fe268add · 재고 있음) · 창고 Toronto(045e4ca6)
--         가짜 스토어(kind aone) · 가짜 shop_order · packed 는 ful-1a-verify 의 길(so_confirm → confirmed → at_wms → picking → packed 직접) · Shopify intake 오더는 replica 로 intake 만 바꾼다
--   실제 행 무변 = 스냅샷 때 있던 id 집합(so · so_charge) · rollback · so_create · so_finalize(인보이스) 가 시퀀스 둘을 당긴다 → 머리에서 읽고 greatest 로 되돌린다
--   권한 갈래 = set local role authenticated + claims(pg_temp.asu)

\echo '── 시퀀스 · db_role · schema_migrations'
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select :so_seq_last as so_seq, :'so_seq_called' as so_seq_called, :inv_seq_last as inv_seq, (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261020134522' \gset
select :n_applied as schema_migrations_rows_for_20261020134522;

begin;
set local statement_timeout = '300s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.who(p_au text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', p_au, 'role', 'authenticated')::text, true) $$;
-- 직원 신원 + authenticated 역할로 한 문장(결과 글 · 오류면 ERR) — \gset 으로 받아 다음 문장에서 판정
create function pg_temp.asu(p_au text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform pg_temp.who(p_au);
  execute 'set local role authenticated';
  execute p_sql into v;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.runp(p_au text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform pg_temp.who(p_au);
  execute p_sql into v;
  return v;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.sid(p_num text) returns uuid language sql stable as $$ select id from public.so where so_number = p_num $$;
create function pg_temp.charges_of(p_so uuid) returns text language sql stable as $$
  select coalesce(string_agg(c.line_no || ':' || c.name || ':' || trim_scale(c.amount)::text || ':' || coalesce(trim_scale(c.discount_pct)::text, '-') || ':' || coalesce(trim_scale(c.discount_amount)::text, '-') || ':' || coalesce(c.account_code, '-')
                             || ':' || coalesce((select split_part(s.email, '@', 1) from public.ims_staff s where s.id = c.updated_by), '-'), ' | ' order by c.line_no), '(none)')
  from public.so_charge c where c.so_id = p_so $$;
-- 가짜 SO: 손님 밑에 draft → P1 × qty(so_create 는 통화 · 결제조건을 손님에서 복사한다)
create function pg_temp.mk_so(p_qty numeric) returns uuid language plpgsql as $$
declare v_so uuid;
begin
  v_so := (public.so_create('91442ea9-270c-4026-92bb-cc6cf7665835'::uuid, 'warehouse', 'manual', '045e4ca6-b7a9-446e-9e6a-a5a0db56d456'::uuid, 'ch-1 verify')->>'id')::uuid;
  perform public.so_line_add(v_so, 'fe268add-677a-4144-90fb-2b18aac8b7ce'::uuid, p_qty);
  return v_so;
end $$;
-- confirmed → packed(창고 걸음은 직접 — so_status_guard 의 허락 짝 · ful-1a-verify 와 같다)
create function pg_temp.to_packed(p_so uuid) returns void language plpgsql as $$
begin
  perform public.so_confirm(p_so);
  update public.so set status = 'at_wms'  where id = p_so and status = 'confirmed';
  update public.so set status = 'picking' where id = p_so and status = 'at_wms';
  update public.so set status = 'packed'  where id = p_so and status = 'picking';
  if (select status from public.so where id = p_so) <> 'packed' then raise exception 'to_packed: % is %', p_so, (select status from public.so where id = p_so); end if;
end $$;
create function pg_temp.picks(p_so uuid) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'bin', '', 'qty', l.qty_ordered) order by l.line_no), '[]'::jsonb)
    from public.so_line l where l.so_id = p_so and not exists (select 1 from public.so_line c where c.combo_line_id = l.id);
$$;
-- 가짜 Shopify 오더 짝(shop_order 한 줄 · 스토어 id · 상태 created · 시험 표식)
create function pg_temp.mk_web(p_so uuid, p_store uuid, p_name text, p_num bigint) returns uuid language plpgsql as $$
declare v_o uuid; v_cust uuid; v_loc uuid;
begin
  select customer_id, location_id into v_cust, v_loc from public.so where id = p_so;
  insert into public.shop_order (store_id, shopify_order_gid, name, raw, status, customer_id, location_id, so_id, processed_at, is_test)
  values (p_store, 'gid://shopify/Order/' || p_num, p_name, jsonb_build_object('id', 'gid://shopify/Order/' || p_num, 'name', p_name), 'created', v_cust, v_loc, p_so, now(), true)
  returning id into v_o;
  return v_o;
end $$;
-- intake 만 shopify 로(so_create 는 shopify 를 받지 않는다 · 트리거는 안 깨운다)
create function pg_temp.set_intake(p_so uuid, p_intake text) returns void language plpgsql as $$
begin
  set local session_replication_role = replica;
  update public.so set intake = p_intake where id = p_so;
  set local session_replication_role = origin;
end $$;
create function pg_temp.set_status(p_so uuid, p_status text) returns void language plpgsql as $$
begin
  set local session_replication_role = replica;
  update public.so set status = p_status, closed_at = case when p_status in ('fulfilled', 'cancelled') then now() end, closed_reason = case when p_status = 'cancelled' then 'voided' end where id = p_so;   -- so_closed_at_ck · so_cancel_reason_ck
  set local session_replication_role = origin;
end $$;

\echo '── M0) 직원 셋 · 참조 · 실제 행 스냅샷(id 집합)'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'ch1-sa@test.invalid', 'CH1 sales A', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as au_sa, id::text as st_sa \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'ch1-sm@test.invalid', 'CH1 sales+master M', 'manager', '["ims","sales","master"]', '{}') returning auth_user_id::text as au_sm, id::text as st_sm \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'ch1-mo@test.invalid', 'CH1 master-only O', 'manager', '["ims","master"]', '{}') returning auth_user_id::text as au_mo, id::text as st_mo \gset
select id::text as st_asung, sale_tier_id::text as tier from public.shop_store where kind = 'asung' and is_active order by created_at limit 1 \gset
create temp table t_real_so as select s.id from public.so s;
create temp table t_real_ch as select c.id from public.so_charge c;
select count(*) as n_real_so, md5(coalesce(string_agg(s.id::text || ':' || s.status || ':' || coalesce(s.intake, ''), '|' order by s.id), '')) as md5_real_so from public.so s join t_real_so t on t.id = s.id \gset
select count(*) as n_real_ch, md5(coalesce(string_agg(c.id::text || ':' || c.name || ':' || c.amount || ':' || coalesce(c.discount_pct::text, '') || ':' || coalesce(c.discount_amount::text, ''), '|' order by c.id), '')) as md5_real_ch from public.so_charge c join t_real_ch t on t.id = c.id \gset
select pg_temp.chk(format('M0 staff 3 (sales · sales+master · master-only) · asung test store · %s real orders · %s real charges snapshotted', :n_real_so, :n_real_ch),
  :'au_sa' <> '' and :'au_sm' <> '' and :'au_mo' <> '' and :'st_asung' <> '' and :'tier' <> '' and :n_real_so > 0
  and public.ims_perm_catalog()->'screens' ? 'master' and exists (select 1 from public.ref_account where code = '_99_'), 'see M0');

\echo '── M1) 가짜 재료 — aone 스토어 · 오더 열(draft 1 · packed 5 · 다른 상태 4) · Shopify 짝'
insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, secret_prefix, is_active) values ('ch1aone', 'ch1-aone-test.myshopify.com', 'CH1 fake aone store', 'aone', :'tier'::uuid, 'CH1AONE', true) returning id::text as st_aone \gset
select pg_temp.who(:'au_sa') as claims;
select pg_temp.mk_so(1)::text as d1 \gset
select pg_temp.mk_so(2)::text as k1 \gset
select pg_temp.mk_so(1)::text as k2 \gset
select pg_temp.mk_so(1)::text as k3 \gset
select pg_temp.mk_so(1)::text as k4 \gset
select pg_temp.mk_so(1)::text as k5 \gset
select pg_temp.mk_so(1)::text as c1 \gset
select pg_temp.mk_so(1)::text as a1 \gset
select pg_temp.mk_so(1)::text as f1 \gset
select pg_temp.mk_so(1)::text as x1 \gset
select pg_temp.to_packed(:'k1'::uuid), pg_temp.to_packed(:'k2'::uuid), pg_temp.to_packed(:'k3'::uuid), pg_temp.to_packed(:'k4'::uuid), pg_temp.to_packed(:'k5'::uuid);
select pg_temp.set_intake(:'k3'::uuid, 'shopify'), pg_temp.set_intake(:'k4'::uuid, 'shopify'), pg_temp.set_intake(:'k5'::uuid, 'shopify');
select pg_temp.mk_web(:'k3'::uuid, :'st_aone'::uuid, '#CH1-AONE', 9200000000003)::text as w3 \gset
select pg_temp.mk_web(:'k4'::uuid, :'st_asung'::uuid, '#CH1-ASUNG', 9200000000004)::text as w4 \gset
select public.so_confirm(:'c1'::uuid)->>'status' as st_c1 \gset
select pg_temp.to_packed(:'a1'::uuid), pg_temp.to_packed(:'f1'::uuid);
select pg_temp.set_status(:'a1'::uuid, 'at_wms'), pg_temp.set_status(:'f1'::uuid, 'fulfilled'), pg_temp.set_status(:'x1'::uuid, 'cancelled');
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, updated_by) values (:'k3'::uuid, 1, 'Old freight', 9, (select tax_rule from public.so where id = :'k3'::uuid), :'st_sa'::uuid);
select pg_temp.chk('M1 fixtures: aone store · D1 draft · K1 ~ K5 packed (K3 shopify+aone · K4 shopify+asung · K5 shopify without shop_order) · C1 confirmed · A1 at_wms · F1 fulfilled · X1 cancelled · K3 has one charge',
  (select status from public.so where id = :'d1'::uuid) = 'draft' and (select count(*) from public.so where id in (:'k1'::uuid, :'k2'::uuid, :'k3'::uuid, :'k4'::uuid, :'k5'::uuid) and status = 'packed') = 5
  and (select count(*) from public.so where id in (:'k3'::uuid, :'k4'::uuid, :'k5'::uuid) and intake = 'shopify') = 3 and :'w3' <> '' and :'w4' <> ''
  and :'st_c1' = 'confirmed' and (select status from public.so where id = :'a1'::uuid) = 'at_wms' and (select status from public.so where id = :'f1'::uuid) = 'fulfilled' and (select status from public.so where id = :'x1'::uuid) = 'cancelled'
  and pg_temp.charges_of(:'k3'::uuid) = '1:Old freight:9:-:-:-:ch1-sa', format('%s | %s', :'st_c1', pg_temp.charges_of(:'k3'::uuid)));

\if :{?mig}
\echo '── S0) 옛 함수 — packed 에 넣기 · 지우기가 거부된다(결함 재현 · sales+master 여도)'
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 12.5)::text', :'k2')) as o1 \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_remove(%L::uuid)::text', (select id from public.so_charge where so_id = :'k3'::uuid order by line_no limit 1))) as o2 \gset
select pg_temp.chk('S0 (old function · trial only) packed: set → "is not a draft (status packed)" · remove → same · nothing changed',
  :'o1' like 'ERR %is not a draft (status packed)%' and :'o2' like 'ERR %is not a draft (status packed)%' and pg_temp.charges_of(:'k2'::uuid) = '(none)' and pg_temp.charges_of(:'k3'::uuid) like '1:Old freight%',
  format('%s | %s', left(:'o1', 120), left(:'o2', 120)));
select pg_temp.chk('G0 before the trial: no so_charge_gate · so_charge_set still calls so_require_draft · not in schema_migrations',
  to_regprocedure('public.so_charge_gate(uuid, text)') is null and (select prosrc from pg_proc where oid = 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)'::regprocedure) ~ 'so_require_draft' and :n_applied = 0, format('n_applied %s', :n_applied));
\echo '── \i 시험 적용'
\i :mig
\else
select pg_temp.chk('P0c confirm run: migration 20261020134522 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

\echo '── G1) 실물'
select pg_temp.chk('G1 so_charge_gate (definer · not executable by authenticated/anon · aone + master in body) · so_charge_set · so_charge_remove call the gate · no so_require_draft · authenticated can execute both · comments mention 540 · 549',
  (select p.prosecdef and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and p.prosrc ~ 'st\.kind = ''aone''' and p.prosrc ~ 'ims_can_write\(''master''\)' and p.prosrc ~ 'for update' from pg_proc p where p.oid = to_regprocedure('public.so_charge_gate(uuid, text)'))
  and (select prosrc ~ 'so_charge_gate\(p_so_id' and prosrc !~ 'so_require_draft' from pg_proc where oid = 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)'::regprocedure)
  and (select prosrc ~ 'so_charge_gate\(v_ch\.so_id' and prosrc !~ 'so_require_draft' from pg_proc where oid = 'public.so_charge_remove(uuid)'::regprocedure)
  and has_function_privilege('authenticated', 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)', 'execute') and has_function_privilege('authenticated', 'public.so_charge_remove(uuid)', 'execute')
  and obj_description('public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)'::regprocedure, 'pg_proc') like '%549%' and obj_description('public.so_charge_remove(uuid)'::regprocedure, 'pg_proc') like '%540%', 'see G1');

\echo '── S1) draft — sales 만으로 넣기 · 고치기 · 지우기 그대로(status draft)'
select pg_temp.asu(:'au_sa', format('select public.so_charge_set(%L::uuid, ''Packing'', 5)::text', :'d1')) as s1a \gset
select coalesce(pg_temp.j(:'s1a')->'charge'->>'id', '00000000-0000-4000-8000-000000000000') as ch1 \gset
select pg_temp.asu(:'au_sa', format('select public.so_charge_set(%L::uuid, ''Packing box'', 6, %L::uuid)::text', :'d1', :'ch1')) as s1b \gset
select pg_temp.asu(:'au_sa', format('select public.so_charge_remove(%L::uuid)::text', :'ch1')) as s1c \gset
select pg_temp.chk('S1 draft by sales: added (status draft · account _99_ · updated_by SA) → updated → removed (status draft · removed_line_no 1) · no charge left',
  (pg_temp.j(:'s1a')->>'action') = 'added' and (pg_temp.j(:'s1a')->>'status') = 'draft' and (pg_temp.j(:'s1a')->'charge'->>'account_code') = '_99_' and (pg_temp.j(:'s1a')->'charge'->>'updated_by') = :'st_sa'
  and (pg_temp.j(:'s1b')->>'action') = 'updated' and (pg_temp.j(:'s1b')->>'status') = 'draft' and (pg_temp.j(:'s1b')->'charge'->>'amount')::numeric = 6
  and pg_temp.j(:'s1c') @> '{"status": "draft", "removed_line_no": 1}'::jsonb and pg_temp.charges_of(:'d1'::uuid) = '(none)',
  format('%s | %s | %s', left(:'s1a', 200), left(:'s1b', 120), left(:'s1c', 120)));

\echo '── S2) packed K2 — sales 만 ❌ · master 만 ❌(sales 문이 먼저) · sales + master ✅ 넣기 · 고치기(할인 · 계정 · 세금 규칙 검사 그대로) · 지우기'
select pg_temp.asu(:'au_sa', format('select public.so_charge_set(%L::uuid, ''Packing'', 12.5)::text', :'k2')) as s2a \gset
select pg_temp.asu(:'au_mo', format('select public.so_charge_set(%L::uuid, ''Packing'', 12.5)::text', :'k2')) as s2b \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 12.5, null, ''two boxes'', null, null, 10, null)::text', :'k2')) as s2c \gset
select coalesce(pg_temp.j(:'s2c')->'charge'->>'id', '00000000-0000-4000-8000-000000000000') as ch2 \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 20, %L::uuid, ''two boxes'', null, null, null, 5)::text', :'k2', :'ch2')) as s2d \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 20, %L::uuid, null, null, null, 10, 5)::text', :'k2', :'ch2')) as s2e \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 20, %L::uuid, null, ''HST BC (Sale)'', null, null, null)::text', :'k2', :'ch2')) as s2f \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 20, %L::uuid, null, null, ''00000000-0000-4000-8000-00000000dead''::uuid, null, null)::text', :'k2', :'ch2')) as s2g \gset
select pg_temp.asu(:'au_sa', format('select public.so_charge_remove(%L::uuid)::text', :'ch2')) as s2h \gset
select pg_temp.charges_of(:'k2'::uuid) as c2 \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_remove(%L::uuid)::text', :'ch2')) as s2i \gset
select pg_temp.chk('S2 packed: sales-only → "needs the master permission as well" · master-only → sales refusal · sales+master → added (status packed · 12.5 · 10 % · net 11.25 · updated_by SM) → updated (20 · amount discount 5) · both discounts → refused · other tax rule → refused · bad account → refused · sales-only remove → refused · sales+master remove → status packed',
  :'s2a' like 'ERR %is packed — adding or changing charges after packing needs the master permission as well — nothing was saved' and :'s2b' like 'ERR %cannot change sales data%'
  and (pg_temp.j(:'s2c')->>'action') = 'added' and (pg_temp.j(:'s2c')->>'status') = 'packed' and (pg_temp.j(:'s2c')->'charge'->>'net')::numeric = 11.25 and (pg_temp.j(:'s2c')->'charge'->>'updated_by') = :'st_sm'
  and (pg_temp.j(:'s2d')->>'action') = 'updated' and (pg_temp.j(:'s2d')->'charge'->>'discount_amount')::numeric = 5 and (pg_temp.j(:'s2d')->'charge'->>'discount_pct') is null
  and :'s2e' like 'ERR %' and :'s2f' like 'ERR %follow the order tax rule%' and :'s2g' like 'ERR %Account not found%'
  and :'s2h' like 'ERR %needs the master permission as well — nothing was deleted' and :'c2' = '1:Packing:20:-:5:_99_:ch1-sm'
  and pg_temp.j(:'s2i') @> '{"status": "packed", "removed_line_no": 1}'::jsonb and pg_temp.charges_of(:'k2'::uuid) = '(none)',
  format('%s | %s | %s | %s | %s | %s | %s', left(:'s2a', 120), left(:'s2b', 100), left(:'s2c', 160), left(:'s2e', 80), left(:'s2f', 80), left(:'s2h', 100), :'c2'));

\echo '── S3) packed · aone 스토어 Shopify 오더(K3) — sales + master 여도 넣기 · 지우기 거부'
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 3)::text', :'k3')) as s3a \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_remove(%L::uuid)::text', (select id from public.so_charge where so_id = :'k3'::uuid order by line_no limit 1))) as s3b \gset
select pg_temp.chk('S3 aone: set → "came from aonebeauty and was paid at checkout — charges cannot change after packing" · remove → same · the old charge stays',
  :'s3a' like 'ERR %came from aonebeauty and was paid at checkout — charges cannot change after packing — nothing was saved' and :'s3b' like 'ERR %came from aonebeauty%nothing was deleted'
  and pg_temp.charges_of(:'k3'::uuid) = '1:Old freight:9:-:-:-:ch1-sa', format('%s | %s', left(:'s3a', 140), left(:'s3b', 140)));

\echo '── S4) packed · asung.ca 스토어 Shopify 오더(K4) — 보통 오더와 같다 · 새 경고 없음'
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 4)::text', :'k4')) as s4a \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_remove(%L::uuid)::text', coalesce(pg_temp.j(:'s4a')->'charge'->>'id', '00000000-0000-4000-8000-000000000000'))) as s4b \gset
select pg_temp.chk('S4 asung store: added (status packed · warnings []) → removed · no charge left',
  (pg_temp.j(:'s4a')->>'action') = 'added' and (pg_temp.j(:'s4a')->>'status') = 'packed' and (pg_temp.j(:'s4a')->'warnings') = '[]'::jsonb
  and pg_temp.j(:'s4b') @> '{"status": "packed"}'::jsonb and pg_temp.charges_of(:'k4'::uuid) = '(none)', format('%s | %s', left(:'s4a', 200), left(:'s4b', 100)));

\echo '── S5) 다른 상태 · 스토어 모르는 Shopify 오더 · 없는 오더 → 거부'
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 1)::text', :'c1')) as s5a \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 1)::text', :'a1')) as s5b \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 1)::text', :'f1')) as s5c \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 1)::text', :'x1')) as s5d \gset
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 1)::text', :'k5')) as s5e \gset
select pg_temp.asu(:'au_sm', 'select public.so_charge_set(''00000000-0000-4000-8000-00000000dead''::uuid, ''Packing'', 1)::text') as s5f \gset
select pg_temp.chk('S5 confirmed · at_wms · fulfilled · cancelled → "only on a draft or a packed order" · shopify without shop_order → "store is unknown" · unknown id → "Order not found" · no charge anywhere',
  :'s5a' like 'ERR %is confirmed — charges can be added or removed only on a draft or a packed order%' and :'s5b' like 'ERR %is at_wms — charges can be added%' and :'s5c' like 'ERR %is fulfilled — charges%' and :'s5d' like 'ERR %is cancelled — charges%'
  and :'s5e' like 'ERR %is a Shopify order but its store is unknown — nothing was saved' and :'s5f' like 'ERR %Order not found — nothing was saved'
  and (select count(*) from public.so_charge where so_id in (:'c1'::uuid, :'a1'::uuid, :'f1'::uuid, :'x1'::uuid, :'k5'::uuid)) = 0,
  format('%s | %s | %s | %s', left(:'s5a', 120), left(:'s5d', 100), left(:'s5e', 100), left(:'s5f', 80)));

\echo '── S6) packed K1 에 비용 더한 뒤 Ship & invoice — 미리 보기 · 발행 · 인보이스에 한 번 · 합계 = so_detail 의 order_total_with_tax'
select pg_temp.asu(:'au_sm', format('select public.so_charge_set(%L::uuid, ''Packing'', 7.5)::text', :'k1')) as s6a \gset
select coalesce(pg_temp.j(:'s6a')->'charge'->>'id', '00000000-0000-4000-8000-000000000000') as ch6 \gset
select public.so_detail(:'k1'::uuid)::text as d6 \gset
select pg_temp.asu(:'au_sm', format('select public.so_finalize(%L::jsonb, false)::text', jsonb_build_array(jsonb_build_object('so_id', :'k1', 'picks', pg_temp.picks(:'k1'::uuid))))) as p6 \gset
select pg_temp.charges_of(:'k1'::uuid) as c6p \gset
select pg_temp.asu(:'au_sm', format('select public.so_finalize(%L::jsonb, true)::text', jsonb_build_array(jsonb_build_object('so_id', :'k1', 'picks', pg_temp.picks(:'k1'::uuid))))) as f6 \gset
select i.invoice_number as inv6, i.total::text as tot6, (select count(*) from public.so_invoice_line il where il.invoice_id = i.id and il.so_charge_id = :'ch6'::uuid) as n_ch6, (select string_agg(il.kind || ':' || trim_scale(il.amount)::text, ',' order by il.line_no) from public.so_invoice_line il where il.invoice_id = i.id and il.so_charge_id = :'ch6'::uuid) as chl6
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = :'k1'::uuid \gset
select pg_temp.chk('S6 packed + charge 7.5 → preview writes nothing (charge untouched) → commit: shipped/fulfilled (full pick → fulfilled) · one invoice · the charge once on the invoice (amount 7.5) · invoice total = so_detail order_total_with_tax before finalize · charge count still 1',
  (pg_temp.j(:'s6a')->>'status') = 'packed' and :'p6' not like 'ERR%' and :'c6p' = '1:Packing:7.5:-:-:_99_:ch1-sm'
  and :'f6' not like 'ERR%' and (select status from public.so where id = :'k1'::uuid) in ('shipped', 'fulfilled')
  and :n_ch6 = 1 and :'chl6' = 'charge:7.5' and :'tot6'::numeric = (pg_temp.j(:'d6')->'totals'->>'order_total_with_tax')::numeric
  and (pg_temp.j(:'d6')->'totals'->>'charges_total')::numeric = 7.5 and pg_temp.charges_of(:'k1'::uuid) = '1:Packing:7.5:-:-:_99_:ch1-sm',
  format('s6a %s | preview %s | c6p %s | inv %s total %s (detail %s · charges_total %s) · charge lines %s %s | status %s | after %s', left(:'s6a', 80), left(:'p6', 60), :'c6p', :'inv6', :'tot6', pg_temp.j(:'d6')->'totals'->>'order_total_with_tax', pg_temp.j(:'d6')->'totals'->>'charges_total', :n_ch6, :'chl6', (select status from public.so where id = :'k1'::uuid), pg_temp.charges_of(:'k1'::uuid)));

\echo '── S7) 다른 호출자 — shop_order_freight(draft · 시스템 길) 가 전과 같이 운임 줄을 넣는다'
select pg_temp.runp(:'au_sa', format('select public.shop_order_freight(%L::uuid, ''asung'', ''#CH1-X'', %L::jsonb)::text', :'d1', jsonb_build_object('title', 'Standard', 'originalPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', '12.00')), 'discountedPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', '12.00'))))) as s7 \gset
select pg_temp.chk('S7 shop_order_freight (system path · called as postgres with staff claims · authenticated has no execute right) on the draft: one Freight line "Standard" 12 · description Shopify #CH1-X · returns the freight_estimate_from_shopify element with charge_id',
  :'s7' not like 'ERR%' and pg_temp.charges_of(:'d1'::uuid) = '1:Standard:12:-:-:_99_:ch1-sa' and (select description from public.so_charge where so_id = :'d1'::uuid) = 'Shopify #CH1-X'
  and (pg_temp.j(:'s7')->0->>'code') = 'freight_estimate_from_shopify' and (pg_temp.j(:'s7')->0->>'charge_id') = (select id::text from public.so_charge where so_id = :'d1'::uuid),
  format('%s | %s', left(:'s7', 200), pg_temp.charges_of(:'d1'::uuid)));

\echo '── Z1) 실제 행 무접촉(스냅샷 때 있던 id 집합)'
select pg_temp.chk(format('Z1 %s real orders and %s real charges untouched (status · intake · charge name · amount · discounts)', :n_real_so, :n_real_ch),
  (select md5(coalesce(string_agg(s.id::text || ':' || s.status || ':' || coalesce(s.intake, ''), '|' order by s.id), '')) from public.so s join t_real_so t on t.id = s.id) = :'md5_real_so'
  and (select md5(coalesce(string_agg(c.id::text || ':' || c.name || ':' || c.amount || ':' || coalesce(c.discount_pct::text, '') || ':' || coalesce(c.discount_amount::text, ''), '|' order by c.id), '')) from public.so_charge c join t_real_ch t on t.id = c.id) = :'md5_real_ch', 'see Z1');

rollback;
\echo '── rollback 뒤 — 시퀀스 둘(greatest(실제 최대, 머리)) · 가짜 흔적 0'
select setval('public.so_number_seq', greatest(:so_seq_last, (select max(substring(so_number from 4 for 5)::int) from public.so where so_number ~ '^SO-[0-9]{5}')), :'so_seq_called'::boolean) as so_seq_restored;
select setval('public.so_invoice_number_seq', greatest(:inv_seq_last, (select max(invoice_number::int) from public.so_invoice where invoice_number ~ '^[0-9]+$')), :'inv_seq_called'::boolean) as inv_seq_restored;
select (select last_value from public.so_number_seq) as so_seq_now, :so_seq_last as so_seq_head, (select last_value from public.so_invoice_number_seq) as inv_seq_now, :inv_seq_last as inv_seq_head,
       (select count(*) from public.ims_staff where email like 'ch1-%') + (select count(*) from public.shop_store where code = 'ch1aone') + (select count(*) from public.shop_order where name like '#CH1-%') + (select count(*) from public.so where comments = 'ch-1 verify') as fake_traces_left;
