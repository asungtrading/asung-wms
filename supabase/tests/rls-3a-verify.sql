-- rls-3a-verify.sql — 원가 · 기준선 · 수집기 · 기록 표 열다섯 + inv_bin_notes 쓰기 닫기 · 문 없는 쓰기 함수 실행권 회수(판정 579 · rls-3a):
--   결함 재현(S0 · 시험 전용) · 직접 쓰기 거부(S1 · S2) · 함수 실행권(S3) · 살아야 하는 길 — postgres(cron) 둘(S4) · definer 사슬 carry · settle(S5 ~ S7 · 직원 신원 authenticated) · tf_charge_*(S8) · service_role · 무접촉(G1 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261021125743_rls_3a_collector_cost_write_gate.sql -f supabase/tests/rls-3a-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · S0b · G0 셋은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 15 − 3 + 1 = **13** · MISMATCH 0
--   가짜 재료는 전부 RLS3A-/797xx · 가짜 직원 둘(worker 열쇠 없음 · office manager) · 끝은 rollback

\echo '── db_role · schema_migrations'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261021125743' \gset
select :n_applied as schema_migrations_rows_for_20261021125743;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 열여섯 표의 정책 · grant 를 한 글로(열다섯 + inv_bin_notes)
create function pg_temp.gate_state() returns text language sql security definer as $$
  with t(tab) as (values ('inv_snapshot'), ('inv_cost'), ('inv_doc_cost'), ('inv_sync_state'), ('inv_sku_types'), ('inv_doc_state'), ('inv_voided_docs'),
                         ('inv_missing_docs'), ('inv_missing_lines'), ('inv_conflicts'), ('inv_collect_runs'), ('inv_snapshot_runs'), ('inv_compare'), ('inv_compare_runs'), ('inv_balance_diffs'), ('inv_bin_notes'))
  select 'auth_all=' || (select count(*) from pg_policies p join t on t.tab = p.tablename where p.schemaname = 'public' and p.policyname = 'auth_all')
      || ' write_pol=' || (select count(*) from pg_policies p join t on t.tab = p.tablename where p.schemaname = 'public' and p.cmd <> 'SELECT')
      || ' select_pol=' || (select count(*) from pg_policies p join t on t.tab = p.tablename where p.schemaname = 'public' and p.cmd = 'SELECT' and p.qual = 'true' and p.roles::text ~ 'authenticated')
      || ' auth_write_grants=' || (select count(*) from information_schema.role_table_grants g join t on t.tab = g.table_name where g.table_schema = 'public' and g.grantee in ('authenticated', 'anon') and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'))
      || ' auth_select=' || (select count(*) from information_schema.role_table_grants g join t on t.tab = g.table_name where g.table_schema = 'public' and g.grantee = 'authenticated' and g.privilege_type = 'SELECT')
      || ' service_role_write=' || (select count(*) from information_schema.role_table_grants g join t on t.tab = g.table_name where g.table_schema = 'public' and g.grantee = 'service_role' and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE'))
      || ' fn_auth=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and has_function_privilege('authenticated', p.oid, 'execute') and p.proname in ('inv_layer_carry', 'inv_layer_cost_add_settle', 'inv_snap_balance_diffs', 'inv_compare_run', 'inv_ack_diff'))
      || ' fn_anon=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'execute') and p.proname in ('inv_layer_carry', 'inv_layer_cost_add_settle', 'inv_snap_balance_diffs', 'inv_compare_run', 'inv_ack_diff', 'tf_charge_confirm', 'tf_charge_update', 'tf_charge_delete', 'tf_charge_alloc_add', 'tf_charge_alloc_update', 'tf_charge_alloc_delete'))
      || ' fn_svc=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and has_function_privilege('service_role', p.oid, 'execute') and p.proname in ('inv_layer_carry', 'inv_layer_cost_add_settle', 'inv_snap_balance_diffs', 'inv_compare_run', 'inv_ack_diff', 'tf_charge_confirm', 'tf_charge_update', 'tf_charge_delete', 'tf_charge_alloc_add', 'tf_charge_alloc_update', 'tf_charge_alloc_delete'))
      || ' tf_auth=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and has_function_privilege('authenticated', p.oid, 'execute') and p.proname in ('tf_charge_confirm', 'tf_charge_update', 'tf_charge_delete', 'tf_charge_alloc_add', 'tf_charge_alloc_update', 'tf_charge_alloc_delete')) $$;
-- 무접촉 집합(WMS 18 · rls-1 · rls-2 다섯)의 정책 · grant md5 — 마이그레이션 ⓪ 과 같은 식
create function pg_temp.untouched_md5() returns text language sql security definer as $$
  select md5(string_agg(k, ',' order by k)) from (
    select 'pol:' || tablename || ':' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-') as k
      from pg_policies where schemaname = 'public' and (tablename like 'wms\_%' or tablename in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume', 'inv_config'))
    union all
    select 'grant:' || table_name || ':' || grantee || ':' || privilege_type
      from information_schema.role_table_grants where table_schema = 'public' and (table_name like 'wms\_%' or table_name in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume', 'inv_config'))
  ) s $$;
-- 열한 함수의 몸(prosrc) md5 — 이 차수는 함수를 재발행하지 않는다(ACL 만)
create function pg_temp.fn_bodies() returns text language sql as $$
  select md5(string_agg(p.proname || '=' || md5(p.prosrc) || '/' || p.prosecdef::text, ',' order by p.proname)) from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_carry', 'inv_layer_cost_add_settle', 'inv_snap_balance_diffs', 'inv_compare_run', 'inv_ack_diff', 'tf_charge_confirm', 'tf_charge_update', 'tf_charge_delete', 'tf_charge_alloc_add', 'tf_charge_alloc_update', 'tf_charge_alloc_delete') $$;
-- service_role 의 열여섯 표 grant 글(전후 같음)
create function pg_temp.svc_grants() returns text language sql security definer as $$
  select md5(string_agg(table_name || ':' || privilege_type, ',' order by table_name, privilege_type)) from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'service_role' and table_name in ('inv_snapshot', 'inv_cost', 'inv_doc_cost', 'inv_sync_state', 'inv_sku_types', 'inv_doc_state', 'inv_voided_docs', 'inv_missing_docs', 'inv_missing_lines', 'inv_conflicts', 'inv_collect_runs', 'inv_snapshot_runs', 'inv_compare', 'inv_compare_runs', 'inv_balance_diffs', 'inv_bin_notes') $$;
-- 실제 행 내용(가짜 RLS3A- 제외) — 작은 표 넷은 내용 md5 · 큰 셋은 count + 합
create function pg_temp.real_rows() returns text language sql security definer as $$
  select 'sku_types=' || (select md5(coalesce(string_agg(sku || ':' || product_type || ':' || coalesce(is_service::text, '-') || ':' || refreshed_at, ',' order by sku), '')) from public.inv_sku_types where sku not like 'RLS3A-%')
      || ' sync=' || (select md5(coalesce(string_agg(source_key || ':' || coalesce(last_cursor, '-') || ':' || coalesce(last_run_at::text, '-'), ',' order by source_key), '')) from public.inv_sync_state)
      || ' doc_cost=' || (select md5(coalesce(string_agg(id || ':' || amount, ',' order by id), '')) from public.inv_doc_cost)
      || ' bin_notes=' || (select md5(coalesce(string_agg(id || ':' || note, ',' order by id), '')) from public.inv_bin_notes)
      || ' cost=' || (select count(*) || '/' || coalesce(sum(id), 0) || '/' || coalesce(sum(amount), 0) from public.inv_cost)
      || ' snapshot=' || (select count(*) || '/' || coalesce(sum(id), 0) || '/' || coalesce(sum(qty), 0) || '/' || coalesce(sum(value), 0) from public.inv_snapshot)
      || ' diffs=' || (select count(*) || '/' || coalesce(sum(id), 0) || '/' || count(*) filter (where acknowledged_at is not null) from public.inv_balance_diffs)
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where sku not like 'RLS3A-%')
      || ' layer=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_layer where sku not like 'RLS3A-%') $$;
create function pg_temp.ledger_of(p_doc text) returns text language sql security definer as $$
  select coalesce(string_agg(regexp_replace(l.line_ref, '^[0-9a-f-]{36}', '#') || ':' || l.bin || ':' || trim_scale(l.qty_delta), ' | ' order by l.id), '(none)') from public.inv_ledger l where l.doc_number = p_doc $$;
create function pg_temp.layers_of(p_doc text) returns text language sql security definer as $$
  select coalesce(string_agg(regexp_replace(x.line_ref, '^[0-9a-f-]{36}', '#') || ':' || x.sku || ':' || trim_scale(x.qty) || '@' || trim_scale(x.unit_cost) || ':' || x.cost_source, ' | ' order by x.id), '(none)') from public.inv_layer x where x.doc_number = p_doc $$;
create function pg_temp.adds_of(p_doc text) returns text language sql security definer as $$
  select coalesce(string_agg(x.doc_number || '/' || regexp_replace(x.line_ref, '^[0-9a-f-]{36}', '#') || '=' || trim_scale(a.amount) || ':' || a.kind, ' | ' order by x.doc_number, x.line_ref), '(none)') from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where a.doc_number = p_doc $$;
create function pg_temp.consumes_of(p_doc text) returns text language sql security definer as $$
  select coalesce(string_agg(c.reason || ':' || trim_scale(c.qty) || '@' || trim_scale(c.amount), ' | ' order by c.id), '(none)') from public.inv_layer_consume c join public.inv_layer x on x.id = c.layer_id where x.doc_number = p_doc $$;

\echo '── M0) 가짜 직원 둘(worker 열쇠 없음 · office manager receiving + purchasing + stock_adjust · 창고 전부) · 참조 · 실제 행 · 무접촉 집합 · 함수 몸 · service_role grant 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3a-worker@test.invalid', 'RLS3A worker', 'worker', '[]', '{}') returning auth_user_id::text as w_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3a-office@test.invalid', 'RLS3A office', 'manager', '["ims","receiving","purchasing","stock_adjust"]', '{}') returning auth_user_id::text as o_uid, id::text as st \gset
\set w_claims '{"sub":"' :w_uid '","role":"authenticated"}'
\set o_claims '{"sub":"' :o_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select (public.ims_today() - 2)::text as d0, (public.ims_today() - 1)::text as d1 \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bina, b.name as binaname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select id as snap_id from public.inv_snapshot order by id desc limit 1 \gset
select id as cost_id from public.inv_cost order by id desc limit 1 \gset
select snapshot_key as snap_key from public.inv_snapshot where snapshot_key not like '%-initial' group by 1 order by max(taken_at) desc limit 1 \gset
select pg_temp.real_rows() as real_before, pg_temp.untouched_md5() as untouched_before, pg_temp.fn_bodies() as fn_before, pg_temp.svc_grants() as svc_before \gset
select pg_temp.chk(format('M0 staff ×2 · warehouse %s · bin %s · snapshot row %s · cost row %s · key %s · snapshots taken', :'whname', :'binaname', :snap_id, :cost_id, :'snap_key'),
  :'w_uid' <> '' and :'o_uid' <> '' and :'wh' <> '' and :'bina' <> '' and :snap_id > 0 and :cost_id > 0 and :'snap_key' <> '' and :'real_before' <> '' and :'untouched_before' <> '', 'see M0');

\if :{?mig}
\echo '── S0) 결함 재현(시험 전용) — 열쇠 없는 worker(authenticated)가 inv_sku_types 에 넣고 · inv_sync_state 커서를 고치고 · inv_snapshot 줄을 지우고 · inv_cost 를 고치고 · inv_bin_notes 에 넣고 · inv_layer_carry · inv_compare_run · inv_ack_diff 를 부를 수 있다(savepoint 로 되돌림)'
select pg_temp.gate_state() as gate_before \gset
savepoint s0;
set local role authenticated;
select set_config('request.jwt.claims', :'w_claims', true) as claims;
select pg_temp.run('insert into public.inv_sku_types (sku, product_type, is_service, refreshed_at) values (''RLS3A-NOTSTOCK'', ''Service'', false, now()) returning sku') as s0_sku \gset
select pg_temp.run('update public.inv_sync_state set last_cursor = ''RLS3A-CURSOR'' where source_key = (select source_key from public.inv_sync_state order by source_key limit 1) returning source_key') as s0_cur \gset
select pg_temp.run(format('delete from public.inv_snapshot where id = %s returning id::text', :snap_id)) as s0_snap \gset
select pg_temp.run(format('update public.inv_cost set amount = amount + 1 where id = %s returning id::text', :cost_id)) as s0_cost \gset
select pg_temp.run(format('insert into public.inv_bin_notes (sku, warehouse, bin, note, author) values (''RLS3A-X'', %L, %L, ''rls-3a'', ''rls3a'') returning id::text', :'whname', :'binaname')) as s0_note \gset
select pg_temp.run('select public.inv_layer_carry(0)::text') as s0_carry \gset
select pg_temp.run('select public.inv_ack_diff(''RLS3A-NONE'', ''x'', null, ''rls-3a'', null)::text') as s0_ack \gset
select has_function_privilege('authenticated', 'public.inv_compare_run(text)', 'execute')::text as s0_cmp \gset
reset role;
rollback to savepoint s0;
select pg_temp.chk('S0 before the trial: worker without any key wrote inv_sku_types · inv_sync_state · deleted an inv_snapshot row · changed inv_cost · wrote inv_bin_notes · called inv_layer_carry · inv_ack_diff · may execute inv_compare_run (the defect) · auth_all ×15 · not in schema_migrations',
  :'s0_sku' = 'RLS3A-NOTSTOCK' and :'s0_cur' not like 'ERR%' and :'s0_snap' = :'snap_id'::text and :'s0_cost' = :'cost_id'::text and :'s0_note' not like 'ERR%'
  and :'s0_carry' = '0' and :'s0_ack' like '{%' and :'s0_cmp' = 'true' and :'gate_before' like 'auth_all=15 %' and :n_applied = 0,
  format('sku %s | cur %s | snap %s | cost %s | note %s | carry %s | ack %s | cmp %s | gate %s | n_applied %s', left(:'s0_sku', 60), left(:'s0_cur', 60), left(:'s0_snap', 60), left(:'s0_cost', 60), left(:'s0_note', 60), left(:'s0_carry', 60), left(:'s0_ack', 80), :'s0_cmp', :'gate_before', :n_applied));
select pg_temp.chk('S0b savepoint rolled back: real rows as at M0', pg_temp.real_rows() = :'real_before', 'see S0b');
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: the 11 function bodies (prosrc · security) are byte-identical — only ACLs changed · untouched set (WMS 18 · rls-1 · rls-2 five) md5 same · service_role grants same',
  pg_temp.fn_bodies() = :'fn_before' and pg_temp.untouched_md5() = :'untouched_before' and pg_temp.svc_grants() = :'svc_before',
  format('bodies eq %s | untouched eq %s | svc eq %s', pg_temp.fn_bodies() = :'fn_before', pg_temp.untouched_md5() = :'untouched_before', pg_temp.svc_grants() = :'svc_before'));
\else
select pg_temp.chk('P0c confirm run: migration 20261021125743 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() like 'auth_all=0 write_pol=0 select_pol=16 %') as landed \gset
\if :landed
\echo '── G1) 실물 — auth_all 0 · 쓰기 정책 0 · select 정책 16 · authenticated/anon 쓰기 grant 0 · select 16 · service_role 쓰기 48 · 다섯 함수 authenticated 0 · anon 0 of 11 · service_role 11 · tf_charge_* authenticated 6'
select pg_temp.gate_state() as gate \gset
select pg_temp.chk('G1 gate state exact', :'gate' = 'auth_all=0 write_pol=0 select_pol=16 auth_write_grants=0 auth_select=16 service_role_write=48 fn_auth=0 fn_anon=0 fn_svc=11 tf_auth=6', :'gate');

\echo '── S1) 직접 쓰기 거부 — worker(authenticated): 같은 다섯 시도 → 42501 permission denied for table(grant 벽이 먼저) · select 는 그대로(행 수 같음)'
set local role authenticated;
select set_config('request.jwt.claims', :'w_claims', true) as claims;
select pg_temp.run('insert into public.inv_sku_types (sku, product_type, is_service, refreshed_at) values (''RLS3A-NOTSTOCK'', ''Service'', false, now()) returning sku') as s1_sku \gset
select pg_temp.run('update public.inv_sync_state set last_cursor = ''RLS3A-CURSOR'' where source_key = (select source_key from public.inv_sync_state order by source_key limit 1) returning source_key') as s1_cur \gset
select pg_temp.run(format('delete from public.inv_snapshot where id = %s returning id::text', :snap_id)) as s1_snap \gset
select pg_temp.run(format('update public.inv_cost set amount = amount + 1 where id = %s returning id::text', :cost_id)) as s1_cost \gset
select pg_temp.run('insert into public.inv_doc_cost (doc_type, doc_number, kind, amount, occurred_on, collector) values (''transfer'', ''RLS3A-T'', ''transfer_freight'', 1, current_date, ''rls3a'') returning id::text') as s1_doc \gset
select pg_temp.run('update public.inv_doc_state set last_modified = last_modified where source_key = (select source_key from public.inv_doc_state limit 1) returning doc_number') as s1_ds \gset
select pg_temp.run('truncate public.inv_voided_docs') as s1_void \gset
select pg_temp.run('delete from public.inv_balance_diffs where false returning id::text') as s1_diff \gset
select pg_temp.run('insert into public.inv_compare_runs (snapshot_key, compared_pairs, match_count, explained_count, unknown_count) values (''RLS3A'', 0, 0, 0, 0) returning id::text') as s1_cr \gset
select pg_temp.run((select 'select ' || string_agg(format('(select count(*) from public.%I)', t), ' || ''/'' || ' order by t) from unnest(array['inv_snapshot', 'inv_cost', 'inv_doc_cost', 'inv_sync_state', 'inv_sku_types', 'inv_doc_state', 'inv_voided_docs', 'inv_missing_docs', 'inv_missing_lines', 'inv_conflicts', 'inv_collect_runs', 'inv_snapshot_runs', 'inv_compare', 'inv_compare_runs', 'inv_balance_diffs', 'inv_bin_notes']) t)) as s1_sel \gset
reset role;
select (select string_agg(format('(select count(*) from public.%I)', t), ' || ''/'' || ' order by t) from unnest(array['inv_snapshot', 'inv_cost', 'inv_doc_cost', 'inv_sync_state', 'inv_sku_types', 'inv_doc_state', 'inv_voided_docs', 'inv_missing_docs', 'inv_missing_lines', 'inv_conflicts', 'inv_collect_runs', 'inv_snapshot_runs', 'inv_compare', 'inv_compare_runs', 'inv_balance_diffs', 'inv_bin_notes']) t) as sel_sql \gset
select pg_temp.run('select ' || :'sel_sql') as s1_sel_pg \gset
select pg_temp.chk('S1 direct writes refused for authenticated: insert ×3 · update ×3 · delete ×2 · truncate ×1 → 42501 "permission denied for table" · select on all 16 works with the same counts as postgres',
  :'s1_sku' like 'ERR 42501%' and :'s1_sku' like '%inv_sku_types%' and :'s1_cur' like 'ERR 42501%' and :'s1_cur' like '%inv_sync_state%' and :'s1_snap' like 'ERR 42501%' and :'s1_snap' like '%inv_snapshot%'
  and :'s1_cost' like 'ERR 42501%' and :'s1_cost' like '%inv_cost%' and :'s1_doc' like 'ERR 42501%' and :'s1_ds' like 'ERR 42501%' and :'s1_void' like 'ERR 42501%' and :'s1_diff' like 'ERR 42501%' and :'s1_cr' like 'ERR 42501%'
  and :'s1_sel' = :'s1_sel_pg' and :'s1_sel' ~ '^[0-9/]+$',
  format('sku %s | cur %s | snap %s | cost %s | doc %s | ds %s | void %s | diff %s | cr %s | sel %s vs %s', left(:'s1_sku', 70), left(:'s1_cur', 70), left(:'s1_snap', 70), left(:'s1_cost', 70), left(:'s1_doc', 70), left(:'s1_ds', 70), left(:'s1_void', 70), left(:'s1_diff', 70), left(:'s1_cr', 70), :'s1_sel', :'s1_sel_pg'));

\echo '── S2) inv_bin_notes — 넣기 거부 · 읽기 그대로'
set local role authenticated;
select set_config('request.jwt.claims', :'w_claims', true) as claims;
select pg_temp.run(format('insert into public.inv_bin_notes (sku, warehouse, bin, note, author) values (''RLS3A-X'', %L, %L, ''rls-3a'', ''rls3a'') returning id::text', :'whname', :'binaname')) as s2_ins \gset
select pg_temp.run('select count(*)::text from public.inv_bin_notes') as s2_sel \gset
reset role;
select pg_temp.chk('S2 inv_bin_notes: insert refused 42501 · select works · auth_insert policy gone · auth_read kept',
  :'s2_ins' like 'ERR 42501%' and :'s2_ins' like '%inv_bin_notes%' and :'s2_sel' = (select count(*)::text from public.inv_bin_notes)
  and (select string_agg(policyname, ',' order by policyname) from pg_policies where schemaname = 'public' and tablename = 'inv_bin_notes') = 'auth_read',
  format('ins %s | sel %s | pols %s', left(:'s2_ins', 80), :'s2_sel', (select string_agg(policyname, ',' order by policyname) from pg_policies where schemaname = 'public' and tablename = 'inv_bin_notes')));

\echo '── S3) 함수 실행권 — authenticated: 다섯 → 42501 permission denied for function · anon: tf_charge_confirm → 42501 · authenticated(열쇠 없음): tf_charge_update 는 실행되어 열쇠 문에서 선다(42501 이 아니다)'
set local role authenticated;
select set_config('request.jwt.claims', :'w_claims', true) as claims;
select pg_temp.run('select public.inv_layer_carry(0)::text') as s3_carry \gset
select pg_temp.run('select public.inv_layer_cost_add_settle(0)::text') as s3_settle \gset
select pg_temp.run('select public.inv_snap_balance_diffs()::text') as s3_snap \gset
select pg_temp.run('select public.inv_compare_run(''RLS3A'')::text') as s3_cmp \gset
select pg_temp.run('select public.inv_ack_diff(''RLS3A-NONE'', ''x'', null, ''rls-3a'', null)::text') as s3_ack \gset
select pg_temp.run('select public.tf_charge_update(''00000000-0000-0000-0000-000000000000''::uuid, ''{"note":"x"}''::jsonb)::text') as s3_tf_auth \gset
reset role;
set local role anon;
select pg_temp.run('select public.tf_charge_confirm(''00000000-0000-0000-0000-000000000000''::uuid, true)::text') as s3_tf_anon \gset
reset role;
select pg_temp.chk('S3 function ACLs: carry · settle · snap_balance_diffs · compare_run · ack_diff → 42501 "permission denied for function" as authenticated · tf_charge_confirm → 42501 as anon · tf_charge_update as keyless staff runs into the transfer key gate (not 42501)',
  :'s3_carry' like 'ERR 42501%' and :'s3_carry' like '%function inv_layer_carry%' and :'s3_settle' like 'ERR 42501%' and :'s3_snap' like 'ERR 42501%' and :'s3_cmp' like 'ERR 42501%' and :'s3_ack' like 'ERR 42501%'
  and :'s3_tf_anon' like 'ERR 42501%' and :'s3_tf_anon' like '%function tf_charge_confirm%'
  and :'s3_tf_auth' like 'ERR%' and :'s3_tf_auth' not like 'ERR 42501%' and :'s3_tf_auth' like '%transfer%',
  format('carry %s | settle %s | snap %s | cmp %s | ack %s | tf_anon %s | tf_auth %s', left(:'s3_carry', 80), left(:'s3_settle', 80), left(:'s3_snap', 80), left(:'s3_cmp', 80), left(:'s3_ack', 80), left(:'s3_tf_anon', 80), left(:'s3_tf_auth', 120)));

\echo '── S4) 살아야 하는 길 — postgres(cron 꼴): inv_snap_balance_diffs() ok · inv_compare_run(최신 compare 키) ok(시간)'
select clock_timestamp()::text as t0 \gset
select public.inv_snap_balance_diffs()::text as s4_snap \gset
select clock_timestamp()::text as t1 \gset
select public.inv_compare_run(:'snap_key')::text as s4_cmp \gset
select clock_timestamp()::text as t2 \gset
select pg_temp.chk(format('S4 cron paths as postgres: inv_snap_balance_diffs ok (%s ms) · inv_compare_run(%s) ok · compared_pairs > 0 (%s ms) · cron jobs run as postgres',
    round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000), :'snap_key', round(extract(epoch from (:'t2'::timestamptz - :'t1'::timestamptz)) * 1000)),
  (pg_temp.j(:'s4_snap')->>'ok')::boolean and (pg_temp.j(:'s4_cmp')->>'ok')::boolean and (pg_temp.j(:'s4_cmp')->>'compared_pairs')::int > 0
  and not exists (select 1 from cron.job where username <> 'postgres'),
  format('snap %s | cmp %s', left(:'s4_snap', 160), left(:'s4_cmp', 200)));

\echo '── M1) 가짜 재료 — 공급처 · 제품 · PO-79700(600 @2.00 · 인보이스 600 @2.50) · 입고 draft(오늘−2) · CHG-79700 60 CAD draft(PO-79700)'
set local session_replication_role = replica;
insert into public.supplier (name, payment_term_name, account_payable_code) values ('RLS3A Supplier', 'Net 30', '2000') returning id::text as sup \gset
insert into public.product (sku, name, source) values ('RLS3A-P1', 'RLS3A P1', 'manual') returning id::text as p1 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79700', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, :'d0', :'wh'::uuid, now()) returning id::text as po1 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po1'::uuid, 1, :'p1'::uuid, 600, 2.00) returning id::text as l1 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'RLS3A-I1', :'d0', :'cad'::uuid, null, 1500, 'confirmed', 'invoice', now()) returning id::text as i1 \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (:'i1'::uuid, 1, 'goods', :'l1'::uuid, 600, 2.50, true);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-79700', :'po1'::uuid, :'wh'::uuid, :'d0'::date, 'draft', :'st'::uuid) returning id::text as r1 \gset
insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status) values (:'sup'::uuid, 'CHG-79700', :'d1'::date, 'freight', :'cad'::uuid, 60, 'draft') returning id::text as c1 \gset
insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (:'c1'::uuid, :'po1'::uuid, 60) returning id::text as al1 \gset
set local session_replication_role = origin;
select pg_temp.chk('M1 fixtures: PO-79700 confirmed · invoice confirmed · draft receipt · CHG-79700 draft allocated 60',
  (select status from public.po where id = :'po1'::uuid) = 'confirmed' and (select status from public.po_receipt where id = :'r1'::uuid) = 'draft' and :'al1' <> '', 'see M1');

\echo '── S5) 입고 확정 길(office · authenticated): RCV-79700 600 → 칸 A → 확정 → 원장 600 · 레이어 600 @2.5'
set local role authenticated;
select set_config('request.jwt.claims', :'o_claims', true) as claims;
select pg_temp.run(format('select public.po_receipt_work_save(%L::uuid, %L::uuid, 600, ''manual'')::text', :'r1', :'l1')) as sv1 \gset
select coalesce(pg_temp.j(:'sv1')->>'work_id', '00000000-0000-0000-0000-000000000000') as w1 \gset
select pg_temp.run(format('select public.po_receipt_work_putaway(%L::uuid, %L::uuid, true)::text', :'w1', :'bina')) as pa1 \gset
select pg_temp.run(format('select public.po_receipt_confirm(%L::uuid)::text', :'r1')) as cf1 \gset
reset role;
select pg_temp.chk('S5 receipt confirm path as authenticated: RCV-79700 ledger 600 in bin A · layer 600 @2.5 po_line',
  :'sv1' not like 'ERR%' and :'pa1' not like 'ERR%' and :'cf1' not like 'ERR%'
  and pg_temp.ledger_of('RCV-79700') = '#:' || :'binaname' || ':600' and pg_temp.layers_of('RCV-79700') = '#:RLS3A-P1:600@2.5:po_line',
  format('sv1 %s | pa1 %s | cf1 %s | led %s | lay %s', left(:'sv1', 80), left(:'pa1', 80), left(:'cf1', 160), pg_temp.ledger_of('RCV-79700'), pg_temp.layers_of('RCV-79700')));

\echo '── S6) 조정 길(office · authenticated · inv_adjust_confirm definer → inv_post_adjust → inv_layer_post_adjust → inv_layer_fifo_take → inv_layer_carry): RLS3A-P1 칸 A −100 lost → 레이어 소진 fifo 100 @2.5'
set local role authenticated;
select set_config('request.jwt.claims', :'o_claims', true) as claims;
select pg_temp.run(format('select public.inv_adjust_create(%L::uuid, ''rls-3a test'', null)::text', :'wh')) as ad0 \gset
select coalesce(pg_temp.j(:'ad0')->>'id', '00000000-0000-0000-0000-000000000000') as adj, coalesce(pg_temp.j(:'ad0')->>'adjust_number', '?') as adjno \gset
select pg_temp.run(format('select public.inv_adjust_line_set(%L::uuid, %L::jsonb)::text', :'adj', json_build_object('sku', 'RLS3A-P1', 'bin', :'binaname', 'mode', 'delta', 'qty', -100, 'reason', 'lost')::text)) as ad1 \gset
select pg_temp.run(format('select public.inv_adjust_confirm(%L::uuid)::text', :'adj')) as ad2 \gset
reset role;
select pg_temp.chk('S6 adjustment path as authenticated (fifo_take → inv_layer_carry inside the definer chain): ledger adjustment −100 · layer RCV-79700 consumed fifo 100 @ 250',
  :'ad0' not like 'ERR%' and :'ad1' not like 'ERR%' and :'ad2' not like 'ERR%'
  and (select count(*) from public.inv_ledger l where l.doc_type = 'adjustment' and l.doc_number = :'adjno' and l.sku = 'RLS3A-P1' and l.qty_delta = -100) = 1
  and pg_temp.consumes_of('RCV-79700') ~ '^[a-z_]+:100@250$',
  format('ad0 %s | ad1 %s | ad2 %s | consumes %s', left(:'ad0', 120), left(:'ad1', 160), left(:'ad2', 200), pg_temp.consumes_of('RCV-79700')));

\echo '── S7) 비용 확정 길(office · authenticated · po_charge_confirm → inv_layer_post_charge definer → inv_layer_cost_add_settle): CHG-79700 landed 60 얹힘 · 팔린 몫 100/600 → cost_late 10 (settle 이 돌았다는 행 증거)'
select (select count(*) from public.inv_layer_consume) as n_con0 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'o_claims', true) as claims;
select pg_temp.run(format('select public.po_charge_confirm(%L::uuid, true)::text', :'c1')) as ch1 \gset
reset role;
select pg_temp.chk('S7 charge confirm path as authenticated: CHG-79700 confirmed · landed add 60 on RCV-79700 layer · settle wrote cost_late 0 @ 10 (= 60 × 100/600) · inv_layer_consume +1',
  :'ch1' not like 'ERR%' and pg_temp.adds_of('CHG-79700') = 'RCV-79700/#=60:landed'
  and pg_temp.consumes_of('RCV-79700') ~ '^[a-z_]+:100@250 \| cost_late:0@10$' and (select count(*) from public.inv_layer_consume) = :n_con0 + 1
  and (select status from public.po_charge where id = :'c1'::uuid) = 'confirmed',
  format('ch1 %s | adds %s | consumes %s | n_con %s → %s', left(:'ch1', 200), pg_temp.adds_of('CHG-79700'), pg_temp.consumes_of('RCV-79700'), :n_con0, (select count(*) from public.inv_layer_consume)));

\echo '── S8) 부르는 쪽 전수(pg_proc): carry · settle 을 부르는 함수는 전부 definer · inv_snapshot · inv_balance_diffs · inv_compare 를 쓰는 함수 중 authenticated 가 부를 수 있는 invoker 0'
select pg_temp.chk('S8 callers of carry · settle all definer (≥ 8) · no authenticated-callable invoker writes any of the 16 tables',
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'inv_layer_(carry|cost_add_settle)\s*\(' and p.proname not in ('inv_layer_carry', 'inv_layer_cost_add_settle') and not p.prosecdef) = 0
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'inv_layer_(carry|cost_add_settle)\s*\(' and p.proname not in ('inv_layer_carry', 'inv_layer_cost_add_settle')) >= 8
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')
         and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* '(insert\s+into|update|delete\s+from|truncate)\s+(public\.)?inv_(snapshot|cost|doc_cost|sync_state|sku_types|doc_state|voided_docs|missing_docs|missing_lines|conflicts|collect_runs|snapshot_runs|compare|compare_runs|balance_diffs|bin_notes)\M') = 0,
  format('invoker callers %s | callers %s | callable invoker writers %s',
    (select string_agg(p.proname, ' ') from pg_proc p where p.pronamespace = 'public'::regnamespace and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'inv_layer_(carry|cost_add_settle)\s*\(' and p.proname not in ('inv_layer_carry', 'inv_layer_cost_add_settle') and not p.prosecdef),
    (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'inv_layer_(carry|cost_add_settle)\s*\(' and p.proname not in ('inv_layer_carry', 'inv_layer_cost_add_settle')),
    (select string_agg(p.proname, ' ') from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')
         and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* '(insert\s+into|update|delete\s+from|truncate)\s+(public\.)?inv_(snapshot|cost|doc_cost|sync_state|sku_types|doc_state|voided_docs|missing_docs|missing_lines|conflicts|collect_runs|snapshot_runs|compare|compare_runs|balance_diffs|bin_notes)\M')));
\else
select pg_temp.chk('G1 ~ S8 skipped: rls-3a not landed (auth_all still on the fifteen tables)', false, 'not landed — nothing to exercise');
\endif

\echo '── Z1) 실제 행 무접촉 — S4 의 cron 둘이 쓴 뒤라 inv_balance_diffs · inv_compare 는 빼고(그 둘은 rollback) · 나머지 내용 그대로'
select pg_temp.chk('Z1 real rows untouched (sku_types · sync_state · doc_cost · bin_notes md5 · cost · ledger · layer counts/sums) — snapshot · diffs differ only by S4 (cron paths ran inside this transaction)',
  regexp_replace(pg_temp.real_rows(), ' (snapshot|diffs)=[^ ]*', '', 'g') = regexp_replace(:'real_before', ' (snapshot|diffs)=[^ ]*', '', 'g'),
  format('before %s | after %s', :'real_before', pg_temp.real_rows()));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0'
select (select count(*) from public.po where po_number = 'PO-79700') + (select count(*) from public.inv_ledger where doc_number = 'RCV-79700' or sku like 'RLS3A-%') + (select count(*) from public.inv_layer where sku like 'RLS3A-%')
     + (select count(*) from public.ims_staff where email like 'rls3a-%') + (select count(*) from public.product where sku like 'RLS3A-%') + (select count(*) from public.inv_sku_types where sku like 'RLS3A-%') as fake_traces_left;
