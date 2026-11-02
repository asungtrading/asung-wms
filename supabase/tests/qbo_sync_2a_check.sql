-- supabase/tests/qbo_sync_2a_check.sql — qbo-sync-2a 검증: 열쇠 qbo(945) · qbo_job · qbo_txn · 몸 함수 둘 · 일감 창구 8 (2026-11-01 · 판정 935 ~ 946 · 지시서 ~/asung/prompts/qbo-sync-2a.md)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): MIG=supabase/migrations/20261102003000_qbo_sync_2a_key_jobs.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 두 갈래의 차이는 G0(시험만 · echo 줄 · t_res 밖) · 기대 OK 수는 같다
--   쓰기: 가짜 직원 넷(admin 열쇠 없음 · manager qbo · manager qbo:read · worker) · 가짜 손님 7 · 제품 8 · QBO 거울 행(C-2A-* · V-2A-* · I-2A-*) · 일감 — 전부 rollback · 실제 행 0 변경 · EF 없음 · Intuit 없음
--   REST 두 겹: ① L1 nowhere 스캐너(새 · 재발행 함수 18 의 update · delete 깊이 0 WHERE) ② 배포 뒤 북키퍼 열쇠로 Refresh list 한 번(Caleb)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 48
\else
\set EXPECT_OK 47
\endif
\pset pager off
\set adm '{"role":"authenticated","sub":"a2a2a2a2-0000-4000-8000-000000000001"}'
\set mgw '{"role":"authenticated","sub":"a2a2a2a2-0000-4000-8000-000000000002"}'
\set mgr '{"role":"authenticated","sub":"a2a2a2a2-0000-4000-8000-000000000003"}'
\set wrk '{"role":"authenticated","sub":"a2a2a2a2-0000-4000-8000-000000000004"}'
\set nobody '{"role":"authenticated","sub":"a2a2a2a2-0000-4000-8000-000000000009"}'
\set svc '{"role":"service_role"}'
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%';
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.product) as n_prod0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select count(*) from public.qbo_link) as n_link0, (select count(*) from public.qbo_entity) as n_ent0,
       (select id::text from public.ref_payment_term where name = 'C.B.S (Cash Before Shipment)') as term_id,
       (select l.qbo_id from public.ref_payment_term pt join public.qbo_link l on l.ims_kind = 'payment_term' and l.ims_id = pt.id::text where pt.name = 'C.B.S (Cash Before Shipment)') as term_qbo,
       (select l.qbo_id from public.ref_tax_rule t join public.qbo_link l on l.ims_kind = 'tax_rule' and l.ims_id = t.id::text where t.name = 'HST ON (Sale)') as tax_qbo,
       (select l.qbo_id from public.ref_account a join public.qbo_link l on l.ims_kind = 'account' and l.ims_id = a.id::text where a.code = '_98_') as acc98,
       (select l.qbo_id from public.ref_account a join public.qbo_link l on l.ims_kind = 'account' and l.ims_id = a.id::text where a.code = '_58_') as acc58,
       (select l.qbo_id from public.ref_account a join public.qbo_link l on l.ims_kind = 'account' and l.ims_id = a.id::text where a.code = '_94_') as acc94 \gset
\echo '── 기준: qbo_* 함수' :n_fn '· staff' :n_staff0 '· customer' :n_cust0 '· product' :n_prod0 '· realm' :realm '· link' :n_link0 '· entity' :n_ent0 '· term' :term_qbo '· HST ON' :tax_qbo '· 98/58/94 =' :acc98 :acc58 :acc94
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
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
create function pg_temp.adm(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"a2a2a2a2-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
create function pg_temp.mgw(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"a2a2a2a2-0000-4000-8000-000000000002"}'::jsonb, p_sql) $$;
create function pg_temp.mgr(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"a2a2a2a2-0000-4000-8000-000000000003"}'::jsonb, p_sql) $$;
create function pg_temp.svc(p_sql text) returns text language sql as $$ select pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, p_sql) $$;
create function pg_temp.pg(p_sql text) returns text language sql as $$ select pg_temp.as_conn('postgres', null, p_sql) $$;
-- safeupdate 규칙을 정적으로 센다(qbo_1c_check 의 것 그대로)
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
-- 가짜 직원 넷 — admin 은 열쇠 없음(945: admin 도 켜야 한다) · manager 둘(qbo · qbo:read) · worker 없음
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('a2a2a2a2-0000-4000-8000-00000000000a', 'a2a2a2a2-0000-4000-8000-000000000001', 'qbo-sync-2a-admin@asung.invalid', 'QBO 2a Admin NoKey', 'admin', '["master"]'),
  ('a2a2a2a2-0000-4000-8000-00000000000b', 'a2a2a2a2-0000-4000-8000-000000000002', 'qbo-sync-2a-mgr-write@asung.invalid', 'QBO 2a Bookkeeper', 'manager', '["qbo", "sales:read"]'),
  ('a2a2a2a2-0000-4000-8000-00000000000c', 'a2a2a2a2-0000-4000-8000-000000000003', 'qbo-sync-2a-mgr-read@asung.invalid', 'QBO 2a Reader', 'manager', '["qbo:read"]'),
  ('a2a2a2a2-0000-4000-8000-00000000000d', 'a2a2a2a2-0000-4000-8000-000000000004', 'qbo-sync-2a-worker@asung.invalid', 'QBO 2a Worker', 'worker', '["picking"]');
-- 가짜 손님 7 · 주소 · 연락처
insert into public.customer (id, name, is_active, source, currency_code, payment_term_id, payment_term_name, tax_rule) values
  ('c2a00000-0000-4000-8000-00000000000a', 'QBO2A Test Co', true, 'manual', 'CAD', :'term_id'::uuid, 'C.B.S (Cash Before Shipment)', 'HST ON (Sale)'),
  ('c2a00000-0000-4000-8000-00000000000b', 'QBO2A No Address', true, 'manual', 'CAD', null, null, null),
  ('c2a00000-0000-4000-8000-00000000000c', 'QBO2A US Co', true, 'manual', 'USD', null, null, null),
  ('c2a00000-0000-4000-8000-00000000000d', 'QBO2A Far Co', true, 'manual', 'CAD', null, null, null),
  ('c2a00000-0000-4000-8000-00000000000e', 'QBO2A Vendor Dup', true, 'manual', 'CAD', null, null, null),
  ('c2a00000-0000-4000-8000-00000000000f', 'QBO2A Gone Co', false, 'manual', 'CAD', null, null, null),
  ('c2a00000-0000-4000-8000-000000000010', 'QBO2A Parent', true, 'manual', 'CAD', null, null, null);
insert into public.customer (id, name, is_active, source, currency_code, parent_id, parent_source, default_bill_to_customer_id) values
  ('c2a00000-0000-4000-8000-000000000011', 'QBO2A Kid', true, 'manual', 'CAD', 'c2a00000-0000-4000-8000-000000000010', 'ims', 'c2a00000-0000-4000-8000-000000000010');
insert into public.customer_address (customer_id, type, is_default_for_type, line1, line2, city, state_province, postal_code, country, source) values   -- default_customer_id 는 생성 칸
  ('c2a00000-0000-4000-8000-00000000000a', 'Billing', true, '1 Test St', 'Unit 2', 'Toronto', 'ON', 'M1M 1M1', 'CA', 'manual'),
  ('c2a00000-0000-4000-8000-00000000000a', 'Shipping', true, '9 Ship Rd', null, 'Toronto', 'ON', 'M2M 2M2', 'CA', 'manual'),
  ('c2a00000-0000-4000-8000-00000000000c', 'Billing', true, '5 Main St', null, 'Boston', 'MA', '02101', 'US', 'manual'),
  ('c2a00000-0000-4000-8000-00000000000d', 'Billing', true, 'Calle 1', null, 'Tijuana', 'BC', '22000', 'Mexico', 'manual');
insert into public.customer_contact (customer_id, name, email, phone, is_default, source) values
  ('c2a00000-0000-4000-8000-00000000000a', 'Pat Test', 'QBO2A@asung.invalid', '416-000-0000', true, 'manual'),
  ('c2a00000-0000-4000-8000-00000000000c', 'Sam US', 'us@asung.invalid', null, true, 'manual');
-- 가짜 제품 8
insert into public.product (id, name, sku, is_active, source) values
  ('d2a00000-0000-4000-8000-000000000001', 'QBO2A Widget: Blue', 'QBO2A-001', true, 'manual'),
  ('d2a00000-0000-4000-8000-000000000002', 'QBO2A Taken Name', 'QBO2A-002', true, 'manual'),
  ('d2a00000-0000-4000-8000-000000000003', 'QBO2A Inactive In QBO', 'QBO2A-003', true, 'manual'),
  ('d2a00000-0000-4000-8000-000000000004', 'QBO2A Active In QBO', 'QBO2A-004', true, 'manual'),
  ('d2a00000-0000-4000-8000-000000000005', repeat('QBO2A Long Name ', 8), 'QBO2A-005', true, 'manual'),
  ('d2a00000-0000-4000-8000-000000000006', 'QBO2A Inactive Product', 'QBO2A-006', false, 'manual'),
  ('d2a00000-0000-4000-8000-000000000007', 'QBO2A Seventh', 'QBO2A-007', true, 'manual'),
  ('d2a00000-0000-4000-8000-000000000008', 'QBO2A Eighth', 'QBO2A-008', true, 'manual');
-- 가짜 QBO 거울 행 — Vendor 이름 충돌 · Item 이름 선점(다른 Sku) · 같은 Sku 비활성 · 같은 Sku 활성 · 부모 손님의 QBO 행
insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, active) values
  (:'realm', 'Vendor', 'V-2A-DUP', 'qbo2a vendor dup', null, true),
  (:'realm', 'Item', 'I-2A-TAKEN', 'QBO2A Taken Name', 'OTHER-SKU', true),
  (:'realm', 'Item', 'I-2A-INACT', 'QBO2A Inactive In QBO (deleted)', 'QBO2A-003', false),
  (:'realm', 'Item', 'I-2A-ACT', 'QBO2A Active In QBO', 'QBO2A-004', true),
  (:'realm', 'Customer', 'C-2A-P', 'QBO2A Parent (old name in QuickBooks)', null, true);   -- 이름은 다르게(같으면 몸이 충돌로 막는다 · C4) · D10 의 upsert 가 이름을 고친다

-- ── A) 착지 ──
select pg_temp.chk('A1 표 2 acl(postgres 만) + RLS · 정책 0', (select string_agg(c.relname || '=' || c.relacl::text || '/rls=' || c.relrowsecurity::text, ' ' order by c.relname) from pg_class c where c.relname in ('qbo_job', 'qbo_txn') and c.relnamespace = 'public'::regnamespace)
  || ' ' || (select count(*)::text from pg_policies where schemaname = 'public' and tablename in ('qbo_job', 'qbo_txn')), 'qbo_job={postgres=arwdDxtm/postgres}/rls=true qbo_txn={postgres=arwdDxtm/postgres}/rls=true 0');
select pg_temp.chk('A2 qbo_job 제약 · FK(ims_staff 둘 · 자기 참조)', (select string_agg(conname || ':' || contype::text || case when contype = 'f' then '>' || confrelid::regclass::text else '' end, ' ' order by conname) from pg_constraint where conrelid = 'public.qbo_job'::regclass),
  'qbo_job_attempts_ck:c qbo_job_blocked_by_fkey:f>qbo_job qbo_job_blocked_ck:c qbo_job_by_staff_fkey:f>ims_staff qbo_job_error_ck:c qbo_job_ims_kind_ck:c qbo_job_kind_ck:c qbo_job_not_self_ck:c qbo_job_pair_ck:c qbo_job_pkey:p qbo_job_sending_ck:c qbo_job_sent_ck:c qbo_job_skipped_ck:c qbo_job_state_ck:c qbo_job_updated_by_fkey:f>ims_staff');
select pg_temp.chk('A3 열린 일감 하나(부분 유일) · qbo_txn 유일 둘', (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'qbo_job_open_idx') || ' | ' || (select string_agg(conname, ' ' order by conname) from pg_constraint where conrelid = 'public.qbo_txn'::regclass and contype = 'u'),
  'CREATE UNIQUE INDEX qbo_job_open_idx ON public.qbo_job USING btree (realm_id, kind, ims_kind, ims_id) WHERE (state <> ALL (ARRAY[''sent''::text, ''skipped''::text])) | qbo_txn_ims_key qbo_txn_qbo_key');
select pg_temp.chk('A4 카탈로그 screens.qbo(room ims · label) · claude 그대로 · freight_booking 마지막', (select (s->'qbo'->>'room') || ' ' || left(s->'qbo'->>'label', 10) || ' ' || (s ? 'claude')::text || ' ' || (select count(*)::text from jsonb_object_keys(s)) from (select public.ims_perm_catalog()->'screens' s) x), 'ims QuickBooks true 20');
select pg_temp.chk('A5 qbo_link_by_ck 에 created · inv_config 키 넷 값', (select (pg_get_constraintdef(oid) ~ '''created''')::text from pg_constraint where conname = 'qbo_link_by_ck') || ' ' || (select string_agg(key || '=' || coalesce(value, '<null>'), ' ' order by key) from public.inv_config where key like 'qbo_send_%' or key = 'qbo_cogs_account_code'),
  'true qbo_cogs_account_code=_58_ qbo_send_batch=15 qbo_send_enabled=off qbo_send_since=');
select pg_temp.chk('A6 함수 acl — 열쇠 창구 5 authenticated · service 4 service_role · 속 4 grant 0', (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('qbo_key_gate', 'qbo_country_name', 'qbo_account_ref', 'qbo_customer_body', 'qbo_item_body', 'qbo_job_add', 'qbo_job_list', 'qbo_job_retry', 'qbo_job_skip', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_fail', 'qbo_job_unknown')),
  'qbo_account_ref={postgres=X/postgres} qbo_country_name={postgres=X/postgres} qbo_customer_body={postgres=X/postgres} qbo_item_body={postgres=X/postgres} qbo_job_add={postgres=X/postgres,authenticated=X/postgres} qbo_job_claim={postgres=X/postgres,service_role=X/postgres} qbo_job_done={postgres=X/postgres,service_role=X/postgres} qbo_job_fail={postgres=X/postgres,service_role=X/postgres} qbo_job_list={postgres=X/postgres,authenticated=X/postgres} qbo_job_retry={postgres=X/postgres,authenticated=X/postgres} qbo_job_skip={postgres=X/postgres,authenticated=X/postgres} qbo_job_unknown={postgres=X/postgres,service_role=X/postgres} qbo_key_gate={postgres=X/postgres,authenticated=X/postgres}');

-- ── B) 문(945) — 열쇠 글자 그대로 · admin 예외 없음 · 읽기 셋은 qbo:read 도 · service 창구는 authenticated 거부 ──
select pg_temp.chk('B1 qbo_key_gate(true) — 북키퍼(qbo) → staff id · reader(qbo:read) → ERR (write) · admin 열쇠 없음 → ERR · worker → ERR · 직원 아님 → ERR',
  pg_temp.mgw('select public.qbo_key_gate(true)::text') || ' | ' || left(pg_temp.mgr('select public.qbo_key_gate(true)::text'), 54) || ' | ' || left(pg_temp.adm('select public.qbo_key_gate(true)::text'), 46) || ' | ' || left(pg_temp.as_conn('authenticated', :'wrk'::jsonb, 'select public.qbo_key_gate()::text'), 46) || ' | ' || left(pg_temp.as_conn('authenticated', :'nobody'::jsonb, 'select public.qbo_key_gate()::text'), 50),
  'a2a2a2a2-0000-4000-8000-00000000000b | ERR P0001: Your account does not have the ''qbo'' (write | ERR P0001: Your account does not have the ''qbo | ERR P0001: Your account does not have the ''qbo | ERR P0001: You are not registered as active staff ');
select pg_temp.chk('B2 qbo_key_gate(false) — reader → id · admin 열쇠 없음 → ERR', pg_temp.mgr('select public.qbo_key_gate(false)::text') || ' | ' || left(pg_temp.adm('select public.qbo_key_gate(false)::text'), 10), 'a2a2a2a2-0000-4000-8000-00000000000c | ERR P0001:');
select pg_temp.chk('B3 1a 읽기 셋 — reader 통과(summary 9 · page · find) · worker 거부', (select jsonb_array_length(pg_temp.mgr('select public.qbo_link_summary()::text')::jsonb)::text) || ' ' || (pg_temp.mgr('select public.qbo_link_page(''charge'', ''all'')::text')::jsonb->>'total') || ' ' || jsonb_array_length(pg_temp.mgr('select public.qbo_entity_find(''Customer'', ''QBO2A Parent'')::text')::jsonb)::text
  || ' | ' || left(pg_temp.as_conn('authenticated', :'wrk'::jsonb, 'select public.qbo_link_summary()::text'), 10), '9 4 1 | ERR P0001:');
select pg_temp.chk('B4 1a 쓰기 창구(qbo_sync_gate) — reader 거부(write) · 북키퍼 통과(clear 없는 짝 → deleted 0) · admin 열쇠 없음 거부', left(pg_temp.mgr('select public.qbo_link_clear(''service'', ''x'')::text'), 54) || ' | ' || (pg_temp.mgw('select public.qbo_link_clear(''service'', ''x'')::text')::jsonb->>'deleted') || ' | ' || left(pg_temp.adm('select public.qbo_match_auto(''charge'')::text'), 46),
  'ERR P0001: Your account does not have the ''qbo'' (write | 0 | ERR P0001: Your account does not have the ''qbo');
select pg_temp.chk('B5 qbo_status caller_qbo — 북키퍼 write · reader read · admin null(caller_is_admin true) · worker null', (pg_temp.mgw('select public.qbo_status()::text')::jsonb->>'caller_qbo') || ' ' || (pg_temp.mgr('select public.qbo_status()::text')::jsonb->>'caller_qbo') || ' ' || coalesce(pg_temp.adm('select public.qbo_status()::text')::jsonb->>'caller_qbo', 'null') || '/' || (pg_temp.adm('select public.qbo_status()::text')::jsonb->>'caller_is_admin')
  || ' ' || coalesce(pg_temp.as_conn('authenticated', :'wrk'::jsonb, 'select public.qbo_status()::text')::jsonb->>'caller_qbo', 'null') || ' ' || (pg_temp.mgw('select public.qbo_status()::text')::jsonb->>'status'), 'write read null/true null connected');
select pg_temp.chk('B6 연결류는 admin 그대로 — qbo_admin_gate: admin 통과 · 북키퍼 거부', (pg_temp.adm('select public.qbo_admin_gate()::text')::jsonb->>'name') || ' | ' || left(pg_temp.mgw('select public.qbo_admin_gate()::text'), 29), 'QBO 2a Admin NoKey | ERR P0001: Only an admin can ');
select pg_temp.chk('B7 service 창구는 authenticated 42501 · 표 직접 42501 · 몸 함수 직접 42501 · postgres 라도 claim 은 service 만', left(pg_temp.mgw('select public.qbo_job_claim(1)::text'), 9) || ' ' || left(pg_temp.mgw('select count(*)::text from public.qbo_job'), 9) || ' ' || left(pg_temp.mgw('select public.qbo_item_body(''surcharge'')::text'), 9) || ' ' || left(pg_temp.pg('select public.qbo_job_claim(1)::text'), 40),
  'ERR 42501 ERR 42501 ERR 42501 ERR P0001: qbo_job_claim is for the send');

-- ── C) 몸 함수(postgres 로 직접) — 손님 ──
select pg_temp.pg('select public.qbo_customer_body(''c2a00000-0000-4000-8000-00000000000a'')::text') as ca \gset
select pg_temp.chk('C1 손님 A 몸 — DisplayName · CompanyName · Taxable · CurrencyRef CAD · BillAddr(Country CA → Canada · Line1 · Line2 · City · ON · 우편) · 이메일 소문자 · SalesTermRef · DefaultTaxCodeRef(HST ON) · 전화 · 배송 없음 · 경고 0',
  (select (b->>'DisplayName') || '|' || (b->>'CompanyName') || '|' || (b->>'Taxable') || '|' || (b->'CurrencyRef'->>'value') || '|' || (b->'BillAddr'->>'Country') || '|' || (b->'BillAddr'->>'Line1') || '|' || (b->'BillAddr'->>'Line2') || '|' || (b->'BillAddr'->>'City') || '|' || (b->'BillAddr'->>'CountrySubDivisionCode') || '|' || (b->'BillAddr'->>'PostalCode')
     || '|' || (b->'PrimaryEmailAddr'->>'Address') || '|' || (b->'SalesTermRef'->>'value') || '|' || (b->'DefaultTaxCodeRef'->>'value') || '|' || (b ? 'PrimaryPhone')::text || (b ? 'ShipAddr')::text || (b ? 'ParentRef')::text || '|' || jsonb_array_length(j->'warnings')::text || '|' || (j->>'parent_customer_id' is null)::text
   from (select :'ca'::jsonb j, :'ca'::jsonb->'body' b) x),
  'QBO2A Test Co|QBO2A Test Co|true|CAD|Canada|1 Test St|Unit 2|Toronto|ON|M1M 1M1|qbo2a@asung.invalid|' || :'term_qbo' || '|' || :'tax_qbo' || '|falsefalsefalse|0|true');
select pg_temp.pg('select public.qbo_customer_body(''c2a00000-0000-4000-8000-00000000000b'')::text') as cb \gset
select pg_temp.chk('C2 손님 B(주소 · 연락처 · 결제조건 · 세금 없음) — BillAddr · Email · SalesTermRef · DefaultTaxCodeRef 없음 · 경고 2 · CurrencyRef 는 CAD',
  (select (b ? 'BillAddr')::text || (b ? 'PrimaryEmailAddr')::text || (b ? 'SalesTermRef')::text || (b ? 'DefaultTaxCodeRef')::text || ' ' || (b->'CurrencyRef'->>'value') || ' ' || jsonb_array_length(j->'warnings')::text || ' ' || left(j->'warnings'->>0, 26) || ' · ' || left(j->'warnings'->>1, 16) from (select :'cb'::jsonb j, :'cb'::jsonb->'body' b) x),
  'falsefalsefalsefalse CAD 2 no default billing address · no email on file');
select pg_temp.chk('C3 나라 이름(946) — US → USA(경고 0) · Mexico 그대로 + 경고 · qbo_country_name 직접', (select (b->'BillAddr'->>'Country') || ' ' || jsonb_array_length(j->'warnings')::text from (select pg_temp.pg('select public.qbo_customer_body(''c2a00000-0000-4000-8000-00000000000c'')::text')::jsonb j) x, lateral (select j->'body' b) y)
  || ' | ' || (select (b->'BillAddr'->>'Country') || ' ' || (select count(*)::text from jsonb_array_elements_text(j->'warnings') w where w like 'country "Mexico" sent as is%') from (select pg_temp.pg('select public.qbo_customer_body(''c2a00000-0000-4000-8000-00000000000d'')::text')::jsonb j) x, lateral (select j->'body' b) y)
  || ' | ' || public.qbo_country_name('ca') || ' ' || public.qbo_country_name(' Canada ') || ' ' || public.qbo_country_name('us') || ' ' || coalesce(public.qbo_country_name(''), 'null') || ' ' || public.qbo_country_name('France'), 'USA 0 | Mexico 1 | Canada Canada USA null France');
select pg_temp.chk('C4 이름 충돌(Vendor 거울 · 대소문자 무시) → 실패 · 비활성 손님 → 실패 · 없는 손님 → 실패', left(pg_temp.pg('select public.qbo_customer_body(''c2a00000-0000-4000-8000-00000000000e'')::text'), 85) || ' | ' || left(pg_temp.pg('select public.qbo_customer_body(''c2a00000-0000-4000-8000-00000000000f'')::text'), 50) || ' | ' || left(pg_temp.pg('select public.qbo_customer_body(''c2a00000-0000-4000-8000-0000000000ff'')::text'), 27),
  'ERR P0001: QuickBooks already has a customer or supplier named "QBO2A Vendor Dup" (Ve | ERR P0001: IMS customer QBO2A Gone Co is inactive  | ERR P0001: No IMS customer ');
select pg_temp.chk('C5 자식(부모 짝 없음) — ParentRef 없음 · parent_customer_id = 부모', (select (b ? 'ParentRef')::text || ' ' || (j->>'parent_customer_id') from (select pg_temp.pg('select public.qbo_customer_body(''c2a00000-0000-4000-8000-000000000011'')::text')::jsonb j) x, lateral (select j->'body' b) y), 'false c2a00000-0000-4000-8000-000000000010');

-- ── C) 몸 함수 — Item ──
select pg_temp.pg('select public.qbo_item_body(''d2a00000-0000-4000-8000-000000000001'')::text') as i1 \gset
select pg_temp.chk('C6 제품 1 몸 — 콜론 → - · Sku · Type Service · Taxable · Income 98(기본 _98_) · Expense 58(qbo_cogs_account_code) · name_alt · 경고 1(colon)',
  (select (b->>'Name') || '|' || (b->>'Sku') || '|' || (b->>'Type') || '|' || (b->>'Taxable') || '|' || (b->'IncomeAccountRef'->>'value') || '|' || (b->'ExpenseAccountRef'->>'value') || '|' || (j->>'name_alt') || '|' || (j->>'ims_kind') || '|' || jsonb_array_length(j->'warnings')::text || '|' || (j->'warnings'->>0) from (select :'i1'::jsonb j, :'i1'::jsonb->'body' b) x),
  'QBO2A Widget- Blue|QBO2A-001|Service|true|' || :'acc98' || '|' || :'acc58' || '|QBO2A Widget- Blue [QBO2A-001]|product|1|colon in name replaced with -');
select pg_temp.chk('C7 제품 2(이름을 다른 Sku 의 활성 Item 이 선점) — Name = ` [SKU]` 꼴 · 경고', (select (b->>'Name') || ' | ' || left(j->'warnings'->>0, 73) from (select pg_temp.pg('select public.qbo_item_body(''d2a00000-0000-4000-8000-000000000002'')::text')::jsonb j) x, lateral (select j->'body' b) y),
  'QBO2A Taken Name [QBO2A-002] | name "QBO2A Taken Name" is already used by QuickBooks Item #I-2A-TAKEN — ');
select pg_temp.chk('C8 941 같은 Sku 비활성뿐 → 「QuickBooks item is inactive」 · 같은 Sku 활성 → 사람 짝 · 비활성 제품 → 실패 · 엉뚱한 id → 실패', left(pg_temp.pg('select public.qbo_item_body(''d2a00000-0000-4000-8000-000000000003'')::text'), 72) || ' | ' || left(pg_temp.pg('select public.qbo_item_body(''d2a00000-0000-4000-8000-000000000004'')::text'), 76)
  || ' | ' || left(pg_temp.pg('select public.qbo_item_body(''d2a00000-0000-4000-8000-000000000006'')::text'), 44) || ' | ' || left(pg_temp.pg('select public.qbo_item_body(''not-a-uuid'')::text'), 47),
  'ERR P0001: QuickBooks item is inactive — Item #I-2A-INACT QBO2A Inactive | ERR P0001: QuickBooks already has an active item with SKU QBO2A-004 (Item #I | ERR P0001: IMS product QBO2A-006 (QBO2A Inac | ERR P0001: ims_id must be a product id or ''surc');
select pg_temp.chk('C9 긴 이름 → 100 자 · 경고 · name_alt 도 100 자 안', (select length(b->>'Name')::text || ' ' || length(j->>'name_alt')::text || ' ' || (j->'warnings'->>0) from (select pg_temp.pg('select public.qbo_item_body(''d2a00000-0000-4000-8000-000000000005'')::text')::jsonb j) x, lateral (select j->'body' b) y), '100 100 name cut to 100 characters');
select pg_temp.chk('C10 surcharge → Tariff Surcharge · Income 94 · Expense · Sku 없음 · ims_kind charge · freight · discount · freight_discount 거부', (select (b->>'Name') || '|' || (b->'IncomeAccountRef'->>'value') || '|' || (b ? 'ExpenseAccountRef')::text || (b ? 'Sku')::text || '|' || (j->>'ims_kind') from (select pg_temp.pg('select public.qbo_item_body(''surcharge'')::text')::jsonb j) x, lateral (select j->'body' b) y)
  || ' | ' || left(pg_temp.pg('select public.qbo_item_body(''freight'')::text'), 33) || ' | ' || left(pg_temp.pg('select public.qbo_item_body(''freight_discount'')::text'), 42), 'Tariff Surcharge|' || :'acc94' || '|falsefalse|charge | ERR P0001: Charge freight is not  | ERR P0001: Charge freight_discount is not ');
insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active) values (:'realm', 'Item', 'I-2A-TS', 'Tariff Surcharge', false);
select left(pg_temp.pg('select public.qbo_item_body(''surcharge'')::text'), 70) as c11a \gset
delete from public.qbo_entity where realm_id = :'realm' and qbo_type = 'Item' and qbo_id = 'I-2A-TS';
select pg_temp.chk('C11 surcharge — QBO 에 같은 이름(비활성이라도)이 있으면 사람 짝 · 잠깐 넣은 행을 지우면 다시 된다', :'c11a' || ' | ' || (pg_temp.pg('select public.qbo_item_body(''surcharge'')::text')::jsonb->>'name'),
  'ERR P0001: QuickBooks already has an item named "Tariff Surcharge" (It | Tariff Surcharge');

-- ── D) 일감 — add(열쇠) · claim · done · fail · unknown(service) · retry · skip(열쇠) · list ──
select pg_temp.chk('D1 add — reader 거부 · kind 밖 거부 · 이미 짝인 손님 거부(실제 짝 하나 골라) · 비활성 Item 제품은 몸이 거부', left(pg_temp.mgr('select public.qbo_job_add(''customer'', ''c2a00000-0000-4000-8000-00000000000a'')::text'), 54) || ' | ' || left(pg_temp.mgw('select public.qbo_job_add(''invoice'', ''x'')::text'), 40)
  || ' | ' || left(pg_temp.mgw(format('select public.qbo_job_add(''customer'', %L)::text', (select l.ims_id from public.qbo_link l where l.ims_kind = 'customer' and l.realm_id = :'realm' limit 1))), 15) || ' | ' || left(pg_temp.mgw('select public.qbo_job_add(''item'', ''d2a00000-0000-4000-8000-000000000003'')::text'), 42),
  'ERR P0001: Your account does not have the ''qbo'' (write | ERR P0001: kind must be customer or item | ERR P0001: Quic | ERR P0001: QuickBooks item is inactive — I');
select pg_temp.mgw('select public.qbo_job_add(''customer'', ''c2a00000-0000-4000-8000-00000000000a'')::text') as ja \gset
select pg_temp.chk('D2 add 손님 A → queued · existing false · by_staff 북키퍼 · attempts 0 · warning 없음 · preview 에 몸', (select (j->>'state') || ' ' || (j->>'existing') || ' ' || (j->>'by_staff') || ' ' || (j->>'attempts') || ' ' || (j->>'warning' is null)::text || ' ' || (j->'preview'->'body'->>'DisplayName') from (select :'ja'::jsonb j) x), 'queued false a2a2a2a2-0000-4000-8000-00000000000b 0 true QBO2A Test Co');
select pg_temp.chk('D3 add 손님 A 다시 → 같은 일감 · existing true', (select (j->>'id') || ' ' || (j->>'existing') from (select pg_temp.mgw('select public.qbo_job_add(''customer'', ''c2a00000-0000-4000-8000-00000000000a'')::text')::jsonb j) x), (:'ja'::jsonb->>'id') || ' true');
select pg_temp.mgw('select public.qbo_job_add(''customer'', ''c2a00000-0000-4000-8000-000000000011'')::text') as jk \gset
select pg_temp.chk('D4 add 자식 → 부모 일감 먼저(queued) · 자식 blocked · blocked_by = 부모 일감', (select (j->>'state') || ' ' || (j->'parent_job'->>'state') || ' ' || (j->'parent_job'->>'ims_id') || ' ' || (j->>'blocked_by' = j->'parent_job'->>'id')::text from (select :'jk'::jsonb j) x), 'blocked queued c2a00000-0000-4000-8000-000000000010 true');
select pg_temp.mgw('select public.qbo_job_add(''item'', ''d2a00000-0000-4000-8000-000000000001'')::text') as j1 \gset
select pg_temp.mgw('select public.qbo_job_add(''item'', ''d2a00000-0000-4000-8000-00000000000b'')::text') as jb_err \gset
select pg_temp.chk('D5 add 제품 1 → queued · warning 에 colon 경고 · 손님 B 를 item 으로 → 없는 제품', (select (j->>'state') || ' ' || (j->>'warning') from (select :'j1'::jsonb j) x) || ' | ' || left(:'jb_err', 25), 'queued colon in name replaced with - | ERR P0001: No IMS product');
select pg_temp.chk('D6 list(reader) open → total 4 · counts queued 3 · blocked 1 · 행에 ims_name · by_name · worker 거부', (select (j->>'total') || ' ' || (j->'counts'->>'queued') || ' ' || (j->'counts'->>'blocked') || ' ' || (select count(*)::text from jsonb_array_elements(j->'rows') r where r->>'ims_name' like 'QBO2A%') || ' ' || (j->'rows'->0->>'by_name') from (select pg_temp.mgr('select public.qbo_job_list(''open'')::text')::jsonb j) x)
  || ' | ' || left(pg_temp.as_conn('authenticated', :'wrk'::jsonb, 'select public.qbo_job_list()::text'), 10) || ' | ' || left(pg_temp.mgr('select public.qbo_job_list(''bogus'')::text'), 30), '4 3 1 4 QBO 2a Bookkeeper | ERR P0001: | ERR P0001: state must be one o');
select pg_temp.svc('select public.qbo_job_claim(2)::text') as cl1 \gset
select pg_temp.chk('D7 claim(2) → 손님 A · 부모(created_at 순 · clock_timestamp) sending · attempts 1 · 몸 · request_id · name · 자식 · 제품 1 은 아직', (select (j->>'claimed') || ' ' || (j->>'recovered_unknown') || ' ' || (j->>'unblocked') || ' ' || (j->>'body_failed') || ' ' || (j->'jobs'->0->>'kind') || ':' || (j->'jobs'->0->>'name') || ':' || (j->'jobs'->0->>'attempt') || ':' || (j->'jobs'->0->'body'->>'DisplayName') || ' ' || (j->'jobs'->1->>'name') || ' ' || (j->'jobs'->0->>'request_id' ~ '^[0-9a-f-]{36}$')::text from (select :'cl1'::jsonb j) x)
  || ' | ' || (select string_agg(state || ':' || attempts, ' ' order by created_at) from public.qbo_job where ims_id like 'c2a00000%' or ims_id like 'd2a00000%'), '2 0 0 0 customer:QBO2A Test Co:1:QBO2A Test Co QBO2A Parent true | sending:1 sending:1 blocked:0 queued:0');
select pg_temp.svc('select public.qbo_job_claim(5)::text') as cl2 \gset
select pg_temp.svc('select public.qbo_job_claim(5)::text') as cl3 \gset
select pg_temp.chk('D8 claim 다시 → 제품 1(name · name_alt · sku · body) · 그 다음 → 0', (select (j->>'claimed') || ' ' || (j->'jobs'->0->>'name') || ' | ' || (j->'jobs'->0->>'name_alt') || ' | ' || (j->'jobs'->0->>'sku') || ' ' || (j->'jobs'->0->'body'->>'Type') from (select :'cl2'::jsonb j) x) || ' | ' || (:'cl3'::jsonb->>'claimed'),
  '1 QBO2A Widget- Blue | QBO2A Widget- Blue [QBO2A-001] | QBO2A-001 Service | 0');
select pg_temp.svc(format('select public.qbo_job_done(%L, ''C-2A-A'', ''QBO2A Test Co'', ''0'', ''tid-a'')::text', :'ja'::jsonb->>'id')) as da \gset
select pg_temp.chk('D9 done 손님 A → sent · linked · qbo_link created(북키퍼) · qbo_entity Customer C-2A-A · 일감에 qbo_id · sent_at · claimed_at null', (select (j->>'state') || ' ' || (j->>'linked') || ' ' || (j->>'unblocked') from (select :'da'::jsonb j) x)
  || ' | ' || (select l.matched_by || ' ' || l.qbo_id || ' ' || (l.by_staff = 'a2a2a2a2-0000-4000-8000-00000000000b')::text from public.qbo_link l where l.ims_kind = 'customer' and l.ims_id = 'c2a00000-0000-4000-8000-00000000000a')
  || ' | ' || (select e.name || ' ' || e.active::text || ' ' || coalesce(e.sync_token, '-') from public.qbo_entity e where e.qbo_type = 'Customer' and e.qbo_id = 'C-2A-A')
  || ' | ' || (select j.qbo_id || ' ' || (j.sent_at is not null)::text || ' ' || (j.claimed_at is null)::text || ' ' || j.last_intuit_tid from public.qbo_job j where j.id = (:'ja'::jsonb->>'id')::uuid), 'sent true 0 | created C-2A-A true | QBO2A Test Co true 0 | C-2A-A true true tid-a');
select pg_temp.svc(format('select public.qbo_job_done(%L, ''C-2A-P'', ''QBO2A Parent'')::text', :'jk'::jsonb->'parent_job'->>'id')) as dp \gset
select pg_temp.chk('D10 done 부모(QBO 거울에 이미 있는 C-2A-P · 옛 이름) → sent · 자식 queued(unblocked 1) · 거울 행 이름 갱신 · gone 없음', (select (j->>'state') || ' ' || (j->>'unblocked') from (select :'dp'::jsonb j) x)
  || ' | ' || (select state from public.qbo_job where id = (:'jk'::jsonb->>'id')::uuid) || ' ' || (select count(*)::text || ' ' || min(name) from public.qbo_entity where qbo_type = 'Customer' and qbo_id = 'C-2A-P' and gone_at is null), 'sent 1 | queued 1 QBO2A Parent');
select pg_temp.svc('select public.qbo_job_claim(5)::text') as cl4 \gset
select pg_temp.chk('D11 claim → 자식 몸에 ParentRef C-2A-P · Job true · BillWithParent true', (select (j->'jobs'->0->'body'->'ParentRef'->>'value') || ' ' || (j->'jobs'->0->>'name') || ' ' || (j->'jobs'->0->'body'->>'Job') || ' ' || (j->'jobs'->0->'body'->>'BillWithParent') || ' ' || (j->>'claimed') from (select :'cl4'::jsonb j) x), 'C-2A-P QBO2A Kid true true 1');
select pg_temp.svc(format('select public.qbo_job_fail(%L, ''HTTP 400 ValidationFault code 6000: test'', ''tid-k'')::text', :'jk'::jsonb->>'id')) as fk \gset
select pg_temp.mgr(format('select public.qbo_job_retry(%L)::text', :'jk'::jsonb->>'id')) as rk_reader \gset
select pg_temp.mgw(format('select public.qbo_job_retry(%L)::text', :'jk'::jsonb->>'id')) as rk \gset
select pg_temp.chk('D12 fail 자식 → failed · reader 는 retry 거부 · retry(북키퍼 · note 없이 됨) → queued · request_id 바뀜 · last_error 남음 · claimed_at null', (:'fk'::jsonb->>'state') || ' | ' || left(:'rk_reader', 10) || ' | ' || (:'rk'::jsonb->>'state')
  || ' ' || (select (j.request_id <> (:'jk'::jsonb->>'request_id')::uuid)::text || ' ' || (j.last_error like 'HTTP 400%')::text || ' ' || (j.claimed_at is null)::text from public.qbo_job j where j.id = (:'jk'::jsonb->>'id')::uuid), 'failed | ERR P0001: | queued true true true');
select pg_temp.svc('select public.qbo_job_claim(5)::text') as cl_k \gset
update public.qbo_job set claimed_at = now() - interval '11 minutes' where id = (:'jk'::jsonb->>'id')::uuid;
select pg_temp.svc('select public.qbo_job_claim(5)::text') as cl_stale \gset
select pg_temp.mgw(format('select public.qbo_job_retry(%L)::text', :'jk'::jsonb->>'id')) as rk_nonote \gset
select pg_temp.chk('D13 stale — sending 11 분 → 다음 claim 이 unknown(recovered 1 · claimed 0) · last_error 에 stale · retry 는 note 필수', (:'cl_k'::jsonb->>'claimed') || ' ' || (:'cl_stale'::jsonb->>'recovered_unknown') || ' ' || (:'cl_stale'::jsonb->>'claimed')
  || ' ' || (select j.state || ' ' || (j.last_error like '%stale: still sending%')::text from public.qbo_job j where j.id = (:'jk'::jsonb->>'id')::uuid) || ' | ' || left(:'rk_nonote', 50), '1 1 0 unknown true | ERR P0001: Say what you checked in QuickBooks (a n');
select pg_temp.mgw(format('select public.qbo_job_retry(%L, ''checked QBO: not there'')::text', :'jk'::jsonb->>'id')) as rk_note \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''I-2A-P1'', ''QBO2A Widget- Blue [QBO2A-001]'', ''0'', ''tid-p1'', ''Duplicate Name (6240) on "QBO2A Widget- Blue" — sent again as "QBO2A Widget- Blue [QBO2A-001]"'', ''QBO2A-001'')::text', :'j1'::jsonb->>'id')) as d1 \gset
select pg_temp.chk('D14 unknown + note → queued(note 저장) · done 제품 1 with note(6240 뒤 [SKU]) → sent · attempts +1 · last_error 에 note · qbo_link product created · qbo_entity Item sku', (:'rk_note'::jsonb->>'state') || ' ' || (select j.note from public.qbo_job j where j.id = (:'jk'::jsonb->>'id')::uuid) || ' | ' || (:'d1'::jsonb->>'state')
  || ' ' || (select j.attempts::text || ' ' || (j.last_error like 'Duplicate Name (6240)%')::text || ' ' || j.qbo_name from public.qbo_job j where j.id = (:'j1'::jsonb->>'id')::uuid)
  || ' | ' || (select l.matched_by || ' ' || l.qbo_id from public.qbo_link l where l.ims_kind = 'product' and l.ims_id = 'd2a00000-0000-4000-8000-000000000001') || ' | ' || (select e.sku || ' ' || e.name from public.qbo_entity e where e.qbo_type = 'Item' and e.qbo_id = 'I-2A-P1'),
  'queued checked QBO: not there | sent 2 true QBO2A Widget- Blue [QBO2A-001] | created I-2A-P1 | QBO2A-001 QBO2A Widget- Blue [QBO2A-001]');
select pg_temp.chk('D15 제품 1 이 짝이 되니 다시 add → 몸이 거부(already linked) · 열린 일감 없음', left(pg_temp.mgw('select public.qbo_job_add(''item'', ''d2a00000-0000-4000-8000-000000000001'')::text'), 50) || ' ' || (select count(*)::text from public.qbo_job where ims_id = 'd2a00000-0000-4000-8000-000000000001' and state not in ('sent', 'skipped')), 'ERR P0001: IMS product QBO2A-001 is already linked 0');
select pg_temp.mgw('select public.qbo_job_add(''item'', ''d2a00000-0000-4000-8000-000000000007'')::text') as j7 \gset
select pg_temp.svc('select public.qbo_job_claim(5)::text') as cl7 \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''I-2A-P1'', ''QBO2A Seventh'')::text', :'j7'::jsonb->>'id')) as d7 \gset
select pg_temp.chk('D16 claim 은 자식(queued) + 제품 7 · done 으로 받은 QBO Id 가 이미 다른 IMS 행의 짝(I-2A-P1) → failed + link_error · 짝은 그대로 제품 1 · sent_at null', (:'cl7'::jsonb->>'claimed') || ' ' || (:'d7'::jsonb->>'state') || ' ' || (:'d7'::jsonb->>'linked') || ' ' || left(:'d7'::jsonb->>'link_error', 43)
  || ' | ' || (select l.ims_id from public.qbo_link l where l.ims_kind = 'product' and l.qbo_id = 'I-2A-P1') || ' ' || (select j.state || ' ' || (j.sent_at is null)::text from public.qbo_job j where j.id = (:'j7'::jsonb->>'id')::uuid),
  '2 failed false QuickBooks Item #I-2A-P1 was created but is | d2a00000-0000-4000-8000-000000000001 failed true');
select pg_temp.svc(format('select public.qbo_job_unknown(%L, ''Intuit customer unreachable: timeout'')::text', :'jk'::jsonb->>'id')) as uk \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''C-2A-K'', ''QBO2A Kid'')::text', :'jk'::jsonb->>'id')) as dk \gset
select pg_temp.chk('D17 unknown(service) — 자식 sending → unknown · done 은 unknown 에서도 된다(조회로 찾음) → sent · 짝 created', (:'uk'::jsonb->>'state') || ' ' || (:'dk'::jsonb->>'state') || ' ' || (:'dk'::jsonb->>'linked') || ' ' || (select l.qbo_id || ' ' || l.matched_by from public.qbo_link l where l.ims_kind = 'customer' and l.ims_id = 'c2a00000-0000-4000-8000-000000000011'), 'unknown sent true C-2A-K created');
select pg_temp.mgw('select public.qbo_job_add(''item'', ''d2a00000-0000-4000-8000-000000000008'')::text') as j8 \gset
select left(pg_temp.svc(format('select public.qbo_job_fail(%L, ''x'')::text', :'j8'::jsonb->>'id')), 30) as e1, left(pg_temp.svc(format('select public.qbo_job_done(%L, ''I-X'', ''x'')::text', :'j8'::jsonb->>'id')), 30) as e2, left(pg_temp.svc(format('select public.qbo_job_unknown(%L, ''x'')::text', :'j8'::jsonb->>'id')), 30) as e3,
       left(pg_temp.mgw(format('select public.qbo_job_retry(%L)::text', :'j8'::jsonb->>'id')), 30) as e4, left(pg_temp.mgw(format('select public.qbo_job_skip(%L, '' '')::text', :'j8'::jsonb->>'id')), 36) as e5 \gset
select pg_temp.mgw(format('select public.qbo_job_skip(%L, ''entered in QuickBooks by hand'')::text', :'j8'::jsonb->>'id')) as sk \gset
select left(pg_temp.mgw(format('select public.qbo_job_retry(%L, ''n'')::text', :'j8'::jsonb->>'id')), 30) as e6 \gset
select pg_temp.mgw('select public.qbo_job_add(''item'', ''d2a00000-0000-4000-8000-000000000008'')::text') as j8b \gset
select pg_temp.chk('D18 상태 규칙 — queued 에 fail · done · unknown 거부 · retry 는 failed · unknown 만 · skip 은 note 필수 · skip → skipped · skipped 에 retry 거부 · 열린 일감이 사라져 add 다시 → 새 일감',
  :'e1' || ' | ' || :'e2' || ' | ' || :'e3' || ' | ' || :'e4' || ' | ' || :'e5' || ' | ' || (:'sk'::jsonb->>'state') || ' | ' || :'e6' || ' | ' || (:'j8b'::jsonb->>'existing') || ' ' || (:'j8b'::jsonb->>'id' <> :'j8'::jsonb->>'id')::text,
  'ERR P0001: Only a job being se | ERR P0001: Only a job being se | ERR P0001: Only a job being se | ERR P0001: Only a failed job,  | ERR P0001: Say why this job is skipp | skipped | ERR P0001: Only a failed job,  | false true');
select pg_temp.chk('D19 reader — skip 거부(write) · list failed → 1 · 북키퍼는 service 창구 42501', left(pg_temp.mgr(format('select public.qbo_job_skip(%L, ''n'')::text', :'j7'::jsonb->>'id')), 54) || ' | ' || (pg_temp.mgr('select public.qbo_job_list(''failed'')::text')::jsonb->>'total') || ' | ' || left(pg_temp.mgw(format('select public.qbo_job_done(%L, ''a'', ''b'')::text', :'j7'::jsonb->>'id')), 9),
  'ERR P0001: Your account does not have the ''qbo'' (write | 1 | ERR 42501');
select pg_temp.chk('D20 표 제약 — 열린 일감 둘 23505 · kind item + ims_kind customer 23514 · sent 인데 qbo_id 없음 23514 · 자기 blocked_by 23514 · qbo_txn 짝 23514',
  left(pg_temp.pg(format('insert into public.qbo_job (realm_id, kind, ims_kind, ims_id) values (%L, ''item'', ''product'', ''d2a00000-0000-4000-8000-000000000007'') returning id::text', :'realm')), 9)
  || ' ' || left(pg_temp.pg(format('insert into public.qbo_job (realm_id, kind, ims_kind, ims_id) values (%L, ''item'', ''customer'', ''x'') returning id::text', :'realm')), 9)
  || ' ' || left(pg_temp.pg(format('insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, sent_at) values (%L, ''customer'', ''customer'', ''x2'', ''sent'', now()) returning id::text', :'realm')), 9)
  || ' ' || left(pg_temp.pg(format('insert into public.qbo_job (id, realm_id, kind, ims_kind, ims_id, state, blocked_by) values (''e2a00000-0000-4000-8000-000000000001'', %L, ''customer'', ''customer'', ''x3'', ''blocked'', ''e2a00000-0000-4000-8000-000000000001'') returning id::text', :'realm')), 9)
  || ' ' || left(pg_temp.pg(format('insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id) values (%L, ''invoice'', ''x'', ''CreditMemo'', ''1'') returning id::text', :'realm')), 9), 'ERR 23505 ERR 23514 ERR 23514 ERR 23514 ERR 23514');
select pg_temp.chk('D21 qbo_txn 넣기(postgres) → 유일 둘 · 짝 OK · touch 트리거', (select (pg_temp.pg(format('insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, total_amt, total_tax) values (%L, ''invoice'', ''inv-x'', ''Invoice'', ''T-1'', ''50001'', 93.30, 10.74) returning doc_number', :'realm')))
  || ' ' || left(pg_temp.pg(format('insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id) values (%L, ''invoice'', ''inv-x'', ''Invoice'', ''T-2'') returning id::text', :'realm')), 9) || ' ' || left(pg_temp.pg(format('insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id) values (%L, ''invoice'', ''inv-y'', ''Invoice'', ''T-1'') returning id::text', :'realm')), 9)), '50001 ERR 23505 ERR 23505');

-- ── L) REST 두 겹 ① — 새 · 재발행 함수의 update · delete 는 전부 깊이 0 WHERE · 다른 qbo_* 함수 md5 무변(재발행 5 빼고 · L2 는 시험 갈래만 — 확인 갈래는 begin 앞 지문이 이미 적용 뒤라 비교할 것이 없다 · 2a′ 에서 고침) ──
select pg_temp.chk('L1 nowhere 스캐너 = 0(새 13 + 재발행 5)', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('qbo_key_gate', 'qbo_sync_gate', 'qbo_status', 'qbo_link_summary', 'qbo_link_page', 'qbo_entity_find', 'qbo_country_name', 'qbo_account_ref', 'qbo_customer_body', 'qbo_item_body', 'qbo_job_add', 'qbo_job_list', 'qbo_job_retry', 'qbo_job_skip', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_fail', 'qbo_job_unknown') and pg_temp.nowhere(p.prosrc) <> 0), null);
\if :{?mig}
select pg_temp.chk('L2 기존 qbo_* 함수 md5 — 재발행 5(sync_gate · status · summary · page · entity_find) 빼고 전부 begin 앞과 같다', (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5)
  || ' ' || (select string_agg(t.proname, ' ' order by t.proname) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5), (:n_fn - 5)::text || ' qbo_entity_find qbo_link_page qbo_link_summary qbo_status qbo_sync_gate');
\endif
select pg_temp.chk('L3 scanner 자기 시험', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('update t set a = 1 from p where t.id = p.id;')::text, '10110');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.ims_staff where email like 'qbo-sync-2a-%') = 0 as fake_staff_gone,
       (select count(*) from public.customer) = :n_cust0 as customer_same, (select count(*) from public.product) = :n_prod0 as product_same,
       (select count(*) from public.qbo_link) = :n_link0 as link_same, (select count(*) from public.qbo_entity) = :n_ent0 as entity_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
\if :{?mig}
select (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname in ('qbo_job', 'qbo_txn')) = 0 as tables_gone_as_expected, (select count(*) from public.inv_config where key like 'qbo_send_%') = 0 as config_keys_gone;
\else
select (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname in ('qbo_job', 'qbo_txn')) = 2 as tables_present, (select count(*) from public.qbo_job where ims_id like 'c2a00000%' or ims_id like 'd2a00000%') = 0 as fake_jobs_gone;
\endif
