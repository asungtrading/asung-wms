-- supabase/tests/qbo_sync_1a_check.sql — qbo-sync-1a 검증: qbo_entity · qbo_pull_state · qbo_link + 창구 9 · 속 함수 4 (2026-11-01 · 판정 934 · 지시서 ~/asung/prompts/qbo-sync-1.md 이견 1 ~ 15)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): MIG=supabase/migrations/20261101210000_qbo_sync_1a_link_entity.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_1a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 두 갈래의 차이는 G0(시험만 · echo 줄 · t_res 밖) · 기대 OK 수는 같다 · ⚠️ 확인 갈래는 적용 직후(표 셋이 빈 상태 · 1b pull 전) 기준 — 실제 pull 뒤에는 D 의 수가 달라진다
--   쓰기: 가짜 직원 둘(admin · manager) · 가짜 QBO 행(T-* · C-* · V-* · 계정 · 세금 · 결제조건 · 결제 수단) · 짝 — 전부 rollback · 실제 행 0 변경 · EF 없이(1b 는 이 창구를 부를 뿐)
--   REST 두 겹: ① L1 nowhere 스캐너(창구 9 + 속 4 의 update · delete 깊이 0 WHERE · qbo_1c_check 의 것 그대로) ② 1b 배포 뒤 실제 pull(Caleb)
\set ON_ERROR_STOP on
\set EXPECT_OK 50
\pset pager off
\set adm '{"role":"authenticated","sub":"a1a1a1a1-0000-4000-8000-000000000001"}'
\set mgr '{"role":"authenticated","sub":"a1a1a1a1-0000-4000-8000-000000000002"}'
\set nobody '{"role":"authenticated","sub":"a1a1a1a1-0000-4000-8000-000000000009"}'
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%';
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select count(*) from public.ref_account where is_active) as n_acc, (select count(*) from public.ref_tax_rule where is_active) as n_tax,
       (select count(*) from public.ref_payment_term where is_active) as n_term, (select count(*) from public.customer where is_active) as n_cust,
       (select count(*) from public.supplier where is_active) as n_sup, (select count(*) from public.product where is_active) as n_prod,
       (select count(*) from public.ref_service where is_active) as n_svc \gset
select p.sku as pa_sku, p.name as pa_name, p.id::text as pa_id from public.product p where p.is_active order by p.sku limit 1 \gset
select p.sku as pb_sku, p.name as pb_name, p.id::text as pb_id from public.product p where p.is_active order by p.sku limit 1 offset 1 \gset
select p.sku as pc_sku, p.name as pc_name, p.id::text as pc_id from public.product p where p.is_active order by p.sku limit 1 offset 2 \gset
select c.name as ca_name, c.id::text as ca_id from public.customer c where c.is_active order by c.name, c.id limit 1 \gset
select c.name as cb_name, c.id::text as cb_id from public.customer c where c.is_active order by c.name, c.id limit 1 offset 1 \gset
select c.name as cc_name, c.id::text as cc_id from public.customer c where c.is_active order by c.name, c.id limit 1 offset 2 \gset
select s.name as sa_name, s.id::text as sa_id from public.supplier s where s.is_active order by s.name limit 1 \gset
select r.id::text as svc_id from public.ref_service r where r.is_active order by r.name limit 1 \gset
select t.id::text as tx_id from public.ref_tax_rule t where t.name = 'Exempt (Sale)' \gset
\echo '── 기준: qbo_* 함수' :n_fn '· staff' :n_staff0 '· realm' :realm '· 활성 account' :n_acc '· tax' :n_tax '· term' :n_term '· customer' :n_cust '· supplier' :n_sup '· product' :n_prod '· service' :n_svc
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
select set_config('qbo_test.realm', :'realm', true);                                                   -- $$ 안에서는 psql 변수가 안 바뀐다 → 함수는 current_setting 으로 읽는다
create function pg_temp.adm(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"a1a1a1a1-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
-- 한 종류를 통째로 받는다(begin → upsert 한 쪽 → finish) · 돌려주는 것 = finish 의 received/gone
create function pg_temp.pull(p_type text, p_rows jsonb) returns text language plpgsql as $$
declare v text; v_realm text := current_setting('qbo_test.realm', true);
begin
  v := pg_temp.adm(format('select public.qbo_pull_begin(%L, %L, true)::text', v_realm, p_type)); if v like 'ERR%' then return v; end if;
  v := pg_temp.adm(format('select public.qbo_entity_upsert(%L, %L, %L::jsonb, 1001)::text', v_realm, p_type, p_rows::text)); if v like 'ERR%' then return v; end if;
  v := pg_temp.adm(format('select public.qbo_pull_finish(%L, %L)::text', v_realm, p_type));
  return coalesce((v::jsonb->>'received') || '/' || (v::jsonb->>'gone'), v);
end $$;
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
insert into public.ims_staff (id, auth_user_id, email, name, role) values
  ('a1a1a1a1-0000-4000-8000-00000000000a', 'a1a1a1a1-0000-4000-8000-000000000001', 'qbo-sync-1a-admin@asung.invalid', 'QBO Sync Test Admin', 'admin'),
  ('a1a1a1a1-0000-4000-8000-00000000000b', 'a1a1a1a1-0000-4000-8000-000000000002', 'qbo-sync-1a-manager@asung.invalid', 'QBO Sync Test Manager', 'manager');

-- ── A) 착지 ──
select pg_temp.chk('A1 표 3 acl(postgres 만) + RLS', (select string_agg(c.relname || '=' || c.relacl::text || '/rls=' || c.relrowsecurity::text, ' ' order by c.relname) from pg_class c where c.relname in ('qbo_entity', 'qbo_pull_state', 'qbo_link') and c.relnamespace = 'public'::regnamespace),
  'qbo_entity={postgres=arwdDxtm/postgres}/rls=true qbo_link={postgres=arwdDxtm/postgres}/rls=true qbo_pull_state={postgres=arwdDxtm/postgres}/rls=true');
select pg_temp.chk('A2 정책 0', (select count(*)::text from pg_policies where schemaname = 'public' and tablename in ('qbo_entity', 'qbo_pull_state', 'qbo_link')), '0');
select pg_temp.chk('A3 qbo_link 제약(PK · ims_key · 짝 check · kind · type · by · FK 둘 → ims_staff)', (select string_agg(conname || ':' || contype::text || case when contype = 'f' then '>' || confrelid::regclass::text else '' end, ' ' order by conname) from pg_constraint where conrelid = 'public.qbo_link'::regclass),
  'qbo_link_by_ck:c qbo_link_by_staff_fkey:f>ims_staff qbo_link_ims_key:u qbo_link_kind_ck:c qbo_link_pair_ck:c qbo_link_pkey:p qbo_link_type_ck:c qbo_link_updated_by_fkey:f>ims_staff');
select pg_temp.chk('A4 qbo_link 부분 유일 색인(tax_rule 빼고 QBO 1:1)', (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'qbo_link_qbo_one_idx'),
  'CREATE UNIQUE INDEX qbo_link_qbo_one_idx ON public.qbo_link USING btree (realm_id, qbo_type, qbo_id) WHERE (ims_kind <> ''tax_rule''::text)');
select pg_temp.chk('A5 qbo_entity 칸 11(934 — 연락처 · 주소 · 금액 없음)', (select string_agg(column_name, ' ' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'qbo_entity'),
  'realm_id qbo_type qbo_id name sku parent_id fully_qualified_name active sync_token fetched_at gone_at');
select pg_temp.chk('A6 함수 acl — 창구 9 authenticated · 속 4 grant 0', (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('qbo_sync_gate', 'qbo_realm_of', 'qbo_type_of', 'qbo_ims_rows', 'qbo_pull_begin', 'qbo_entity_upsert', 'qbo_pull_finish', 'qbo_match_auto', 'qbo_link_set', 'qbo_link_clear', 'qbo_link_summary', 'qbo_link_page', 'qbo_entity_find')),
  'qbo_entity_find={postgres=X/postgres,authenticated=X/postgres} qbo_entity_upsert={postgres=X/postgres,authenticated=X/postgres} qbo_ims_rows={postgres=X/postgres} qbo_link_clear={postgres=X/postgres,authenticated=X/postgres} qbo_link_page={postgres=X/postgres,authenticated=X/postgres} qbo_link_set={postgres=X/postgres,authenticated=X/postgres} qbo_link_summary={postgres=X/postgres,authenticated=X/postgres} qbo_match_auto={postgres=X/postgres,authenticated=X/postgres} qbo_pull_begin={postgres=X/postgres,authenticated=X/postgres} qbo_pull_finish={postgres=X/postgres,authenticated=X/postgres} qbo_realm_of={postgres=X/postgres} qbo_sync_gate={postgres=X/postgres} qbo_type_of={postgres=X/postgres}');
select pg_temp.chk('A7 ref_tax_rule.qbo_id 주석 = 쓰지 않는다 · 값 전부 null 그대로', (select left(col_description('public.ref_tax_rule'::regclass, attnum), 19) from pg_attribute where attrelid = 'public.ref_tax_rule'::regclass and attname = 'qbo_id') || ' ' || (select count(*)::text from public.ref_tax_rule where qbo_id is not null), 'qbo-sync-1a: 쓰지 않는다 0');

-- ── B) 문 — admin 만 · 표 · 속 함수는 직접 못 부른다 ──
select pg_temp.chk('B1 manager → P0001 Only an admin', left(pg_temp.as_conn('authenticated', :'mgr'::jsonb, 'select public.qbo_link_summary()::text'), 30), 'ERR P0001: Only an admin can m');
select pg_temp.chk('B2 직원 아닌 사용자 → P0001', left(pg_temp.as_conn('authenticated', :'nobody'::jsonb, 'select public.qbo_match_auto(''product'')::text'), 10), 'ERR P0001:');
select pg_temp.chk('B3 service_role · anon → 42501(grant 없음)', left(pg_temp.as_conn('service_role', '{"role":"service_role"}', 'select public.qbo_link_summary()::text'), 9) || ' ' || left(pg_temp.as_conn('anon', '{"role":"anon"}', 'select public.qbo_link_set(''charge'', ''freight'', ''4'')::text'), 9), 'ERR 42501 ERR 42501');
select pg_temp.chk('B4 admin 이라도 표 · 속 함수 직접은 42501', left(pg_temp.adm('select count(*)::text from public.qbo_link'), 9) || ' ' || left(pg_temp.adm('select count(*)::text from public.qbo_ims_rows(''product'')'), 9) || ' ' || left(pg_temp.adm('select public.qbo_realm_of()'), 9), 'ERR 42501 ERR 42501 ERR 42501');

-- ── C) 받기 — begin · upsert · finish · gone · 이어 받기 · 거부 ──
select pg_temp.chk('C1 begin Item → next_start 1 · resumed false', (select (j->>'next_start') || ' ' || (j->>'resumed') || ' ' || (j->>'qbo_type') from (select pg_temp.adm(format('select public.qbo_pull_begin(%L, ''Item'')::text', :'realm'))::jsonb j) x), '1 false Item');
select pg_temp.chk('C2 begin 다시(끝나지 않음 · restart 아님) → resumed true', (select j->>'resumed' from (select pg_temp.adm(format('select public.qbo_pull_begin(%L, ''Item'')::text', :'realm'))::jsonb j) x), 'true');
select pg_temp.chk('C3 upsert 쪽 1(Item 6 · QBO 원래 꼴 · next_start 1001)', (select (j->>'received_now') || '/' || (j->>'received') || '/' || (j->>'pages') || '/' || (j->>'next_start') from (select pg_temp.adm(format('select public.qbo_entity_upsert(%L, ''Item'', %L::jsonb, 1001)::text', :'realm',
    jsonb_build_array(jsonb_build_object('Id', 'T-A', 'Name', :'pa_name', 'Sku', :'pa_sku', 'Active', true, 'SyncToken', '3', 'Type', 'Service', 'UnitPrice', 9.99, 'IncomeAccountRef', jsonb_build_object('value', '98')),
                      jsonb_build_object('Id', 'T-B1', 'Name', left(:'pb_name', 100), 'Sku', :'pb_sku', 'Active', true),
                      jsonb_build_object('Id', 'T-B2', 'Name', 'Older name of the same product', 'Sku', :'pb_sku', 'Active', true),
                      jsonb_build_object('Id', 'T-C', 'Name', :'pc_name', 'Sku', :'pc_sku', 'Active', false),
                      jsonb_build_object('Id', 'T-F', 'Name', 'Freight', 'Active', true, 'FullyQualifiedName', 'Freight'),
                      jsonb_build_object('Id', 'T-S', 'Name', 'DROPSHIP SERVICE CHARGE - Base Charge per Order', 'Sku', 'DRO00001', 'Active', true, 'ParentRef', jsonb_build_object('value', 'T-F')))::text))::jsonb j) x), '6/6/1/1001');
select pg_temp.chk('C4 담긴 것 — 버린 칸 없음 · sku · parent · active · sync_token 그대로', (select string_agg(qbo_id || ':' || coalesce(sku, '-') || ':' || coalesce(parent_id, '-') || ':' || active::text || ':' || coalesce(sync_token, '-'), ' ' order by qbo_id) from public.qbo_entity where realm_id = :'realm' and qbo_type = 'Item' and qbo_id in ('T-A', 'T-C', 'T-S')),
  'T-A:' || :'pa_sku' || ':-:true:3 T-C:' || :'pc_sku' || ':-:false:- T-S:DRO00001:T-F:true:-');
insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active, fetched_at) values (:'realm', 'Item', 'T-OLD', 'Gone from QuickBooks', true, now() - interval '1 day');
select pg_temp.chk('C5 upsert 쪽 2 → received 7 · pages 2', (select (j->>'received') || '/' || (j->>'pages') from (select pg_temp.adm(format('select public.qbo_entity_upsert(%L, ''Item'', %L::jsonb, 2001)::text', :'realm', jsonb_build_array(jsonb_build_object('Id', 'T-D', 'Name', 'Second page row', 'Active', true))::text))::jsonb j) x), '7/2');
select pg_temp.adm(format('select public.qbo_pull_finish(%L, ''Item'')::text', :'realm')) as c6 \gset
select pg_temp.chk('C6 finish → gone 1(T-OLD · 이번 run 에 안 옴) · finished_at 있음', (select (j->>'received') || '/' || (j->>'pages') || '/' || (j->>'gone') || '/' || (j->>'finished_at' is not null)::text from (select :'c6'::jsonb j) x)
  || ' ' || (select (gone_at is not null)::text from public.qbo_entity where realm_id = :'realm' and qbo_type = 'Item' and qbo_id = 'T-OLD') || ' ' || (select count(*)::text from public.qbo_entity where realm_id = :'realm' and qbo_type = 'Item' and gone_at is not null), '7/2/1/true true 1');
select pg_temp.chk('C7 거부 — finish 두 번 · begin 없이 upsert(Account) · 다른 realm · Id 없는 행 · 모르는 type',
  left(pg_temp.adm(format('select public.qbo_pull_finish(%L, ''Item'')::text', :'realm')), 30) || ' | ' || left(pg_temp.adm(format('select public.qbo_entity_upsert(%L, ''Account'', ''[]''::jsonb)::text', :'realm')), 33)
  || ' | ' || left(pg_temp.adm('select public.qbo_pull_begin(''1'', ''Item'')::text'), 31) || ' | ' || left(pg_temp.adm(format('select public.qbo_entity_upsert(%L, ''Item'', ''[{"Name":"x"}]''::jsonb)::text', :'realm')), 20) || ' | ' || left(pg_temp.adm(format('select public.qbo_pull_begin(%L, ''Invoice'')::text', :'realm')), 23),
  'ERR P0001: No pull in progress | ERR P0001: No pull in progress fo | ERR P0001: QuickBooks company 1 | ERR P0001: No pull i | ERR P0001: type must be');
select pg_temp.chk('C8 Id 없는 행 → upsert 전체 거부(쪽 안 열림)', left(pg_temp.adm(format('select public.qbo_pull_begin(%L, ''Item'')::text', :'realm'))::jsonb->>'resumed', 5) || ' ' || left(pg_temp.adm(format('select public.qbo_entity_upsert(%L, ''Item'', ''[{"Id":"T-X","Name":"x"},{"Name":"no id"}]''::jsonb)::text', :'realm')), 34) || ' ' || (select count(*)::text from public.qbo_entity where qbo_id = 'T-X'), 'false ERR P0001: Every Item row needs Id 0');
select pg_temp.pull('Item', jsonb_build_array(
    jsonb_build_object('Id', 'T-A', 'Name', :'pa_name', 'Sku', :'pa_sku', 'Active', true, 'SyncToken', '4'), jsonb_build_object('Id', 'T-B1', 'Name', left(:'pb_name', 100), 'Sku', :'pb_sku', 'Active', true),
    jsonb_build_object('Id', 'T-B2', 'Name', 'Older name of the same product', 'Sku', :'pb_sku', 'Active', true), jsonb_build_object('Id', 'T-C', 'Name', :'pc_name', 'Sku', :'pc_sku', 'Active', false),
    jsonb_build_object('Id', 'T-F', 'Name', 'Freight', 'Active', true), jsonb_build_object('Id', 'T-S', 'Name', 'DROPSHIP SERVICE CHARGE - Base Charge per Order', 'Sku', 'DRO00001', 'Active', true), jsonb_build_object('Id', 'T-D', 'Name', 'Second page row', 'Active', true))) as c9 \gset
select pg_temp.chk('C9 끝난 뒤 begin → 새 run · 같은 7 을 다시 받고 finish → gone 0(T-OLD 는 이미 gone) · sync_token 갱신', :'c9' || ' ' || (select sync_token from public.qbo_entity where realm_id = :'realm' and qbo_type = 'Item' and qbo_id = 'T-A'), '7/0 4');
select pg_temp.chk('C10 다른 종류 받기 — Account 3 · TaxCode 5 · Term 3 · PaymentMethod 8 · Customer 4',
  pg_temp.pull('Account', '[{"Id":"98","Name":"Sales Account","Active":true},{"Id":"61","Name":"Accounts Receivable","Active":true},{"Id":"4","Name":"Prepaid Expenses","Active":false}]')
  || ' ' || pg_temp.pull('TaxCode', '[{"Id":"7","Name":"GST","Active":false},{"Id":"8","Name":"GST","Active":true},{"Id":"6","Name":"HST ON","Active":true},{"Id":"3","Name":"Exempt","Active":true},{"Id":"2","Name":"Zero-rated","Active":true}]')
  || ' ' || pg_temp.pull('Term', '[{"Id":"3","Name":"Net 30","Active":true},{"Id":"8","Name":"Net 7","Active":true},{"Id":"1000000071","Name":"1%20 Net30","Active":true}]')
  || ' ' || pg_temp.pull('PaymentMethod', '[{"Id":"1","Name":"Cash","Active":true},{"Id":"2","Name":"Cheque","Active":true},{"Id":"3","Name":"Visa","Active":true},{"Id":"4","Name":"Debit","Active":true},{"Id":"5","Name":"E-Transfer","Active":true},{"Id":"8","Name":"Shopify","Active":true},{"Id":"11","Name":"Wire","Active":true},{"Id":"12","Name":"EFT (ACH)","Active":true}]')
  || ' ' || pg_temp.pull('Customer', jsonb_build_array(jsonb_build_object('Id', 'C-A', 'DisplayName', :'ca_name', 'Active', true, 'Job', false), jsonb_build_object('Id', 'C-B', 'DisplayName', upper(:'cb_name') || '  ', 'Active', true),
                                                      jsonb_build_object('Id', 'C-C1', 'DisplayName', :'cc_name', 'Active', true), jsonb_build_object('Id', 'C-C2', 'DisplayName', :'cc_name', 'Active', true, 'ParentRef', jsonb_build_object('value', 'C-A')))), '3/0 5/0 3/0 8/0 4/0');

-- ── D) 자동 짝 — 종류마다 linked / ambiguous / absent / skipped / considered ──
create function pg_temp.m(p_kind text) returns text language sql as $$
  select coalesce((select (j->>'linked') || '/' || (j->>'ambiguous') || '/' || (j->>'absent') || '/' || (j->>'skipped') || '/' || (j->>'considered') from (select pg_temp.adm(format('select public.qbo_match_auto(%L, null, 20000)::text', p_kind)) t) x, lateral (select case when t like 'ERR%' then null else t::jsonb end j) y where j is not null),
                  (select pg_temp.adm(format('select public.qbo_match_auto(%L, null, 20000)::text', p_kind))))   -- qbo-sync-1c 뒤: 묶음 없이 한 번에(20000) · 1a 의 기대 수 그대로
$$;
select pg_temp.chk('D1 account — 98 · 61 linked · _4_ ambiguous(QBO 비활성) · 나머지 absent · 숫자 꼴은 비활성이라 안 센다', pg_temp.m('account'), '2/1/' || (:n_acc - 3)::text || '/0/' || :n_acc::text);
select pg_temp.chk('D2 account 짝 = auto_code · _98_ → 98 · 이름 기록', (select l.matched_by || ' ' || l.qbo_id || ' ' || l.qbo_name_at_match || ' ' || (l.by_staff = 'a1a1a1a1-0000-4000-8000-00000000000a')::text from public.qbo_link l join public.ref_account a on a.id::text = l.ims_id where l.ims_kind = 'account' and a.code = '_98_'), 'auto_code 98 Sales Account true');
select pg_temp.m('tax_rule') as d3 \gset
select pg_temp.chk('D3 tax_rule — 4 TaxCode × Sale · Purchase = 8 linked(GST → 8 활성 쪽) · absent 16', :'d3' || ' ' || (select string_agg(qbo_id || 'x' || n, ' ' order by qbo_id::int) from (select qbo_id, count(*) n from public.qbo_link where ims_kind = 'tax_rule' group by 1) z), '8/0/' || (:n_tax - 8)::text || '/0/' || :n_tax::text || ' 2x2 3x2 6x2 8x2');
select pg_temp.m('payment_term') as d4 \gset
select pg_temp.chk('D4 payment_term — Net 30 · Net 7 linked(활성만 · Net30 · Net7 비활성은 안 센다) · 1%20 Net30 은 IMS 쪽 둘 다 비활성 → 0', :'d4' || ' ' || (select string_agg(pt.name || '→' || l.qbo_id, ' ' order by pt.name) from public.qbo_link l join public.ref_payment_term pt on pt.id::text = l.ims_id where l.ims_kind = 'payment_term'), '2/0/' || (:n_term - 2)::text || '/0/' || :n_term::text || ' Net 30→3 Net 7→8');
select pg_temp.m('payment_method') as d5 \gset
select pg_temp.chk('D5 payment_method — 7 linked(auto_map) · credit_card skipped · opening 없음', :'d5' || ' ' || (select string_agg(ims_id || '→' || qbo_id, ' ' order by ims_id) from public.qbo_link where ims_kind = 'payment_method') || ' ' || (select pg_temp.adm('select public.qbo_match_auto(''payment_method'', null, 20000)::text')::jsonb->'examples'->>'skipped'),
  '7/0/0/1/8 cash→1 cheque→2 debit_card→4 direct_deposit→12 e_transfer→5 shopify→8 wire→11 ["credit_card"]');
select pg_temp.m('customer') as d6 \gset
select pg_temp.chk('D6 customer — cA · cB(대소문자 · 꼬리 공백 무시) linked · cC ambiguous(QBO 활성 둘) · 나머지 absent', :'d6' || ' ' || (select string_agg(l.qbo_id, ' ' order by l.qbo_id) from public.qbo_link l where l.ims_kind = 'customer')
  || ' ' || (select j->'examples'->'ambiguous'->0->>'candidates' from (select pg_temp.adm('select public.qbo_match_auto(''customer'', null, 20000)::text')::jsonb j) x), '2/1/' || (:n_cust - 3)::text || '/0/' || :n_cust::text || ' C-A C-B C-C1 ' || :'cc_name' || ' | C-C2 ' || :'cc_name');
select pg_temp.chk('D7 supplier — Vendor 받기 전 → 거부', left(pg_temp.m('supplier'), 50), 'ERR P0001: The QuickBooks Vendor list has not been');
select pg_temp.chk('D8 supplier — Vendor 1 받은 뒤 → 1 linked', pg_temp.pull('Vendor', jsonb_build_array(jsonb_build_object('Id', 'V-A', 'DisplayName', :'sa_name', 'Active', true))) || ' ' || pg_temp.m('supplier'), '1/0 1/0/' || (:n_sup - 1)::text || '/0/' || :n_sup::text);
select pg_temp.m('product') as d9 \gset
select pg_temp.chk('D9 product — Sku 하나(T-A auto_sku) · Sku 둘 → 이름(T-B1 auto_sku_name) · 비활성만(T-C) ambiguous · 나머지 absent', :'d9' || ' ' || (select string_agg(l.qbo_id || ':' || l.matched_by, ' ' order by l.qbo_id) from public.qbo_link l where l.ims_kind = 'product'), '2/1/' || (:n_prod - 3)::text || '/0/' || :n_prod::text || ' T-A:auto_sku T-B1:auto_sku_name');
select pg_temp.chk('D10 product 다시 → 짝 있는 것은 안 센다 · 새로 0', pg_temp.m('product'), '0/1/' || (:n_prod - 3)::text || '/0/' || (:n_prod - 2)::text);
select pg_temp.chk('D11 charge · service · 모르는 kind → 거부', left(pg_temp.m('charge'), 39) || ' | ' || left(pg_temp.m('service'), 40) || ' | ' || left(pg_temp.m('bogus'), 30), 'ERR P0001: No automatic rule for charge | ERR P0001: No automatic rule for service | ERR P0001: kind must be one of');
select pg_temp.chk('D12 absent 예시 ≤ 20 · 이름 순', (select jsonb_array_length(j->'examples'->'absent')::text || ' ' || (j->'examples'->'absent'->>0 <= j->'examples'->'absent'->>1)::text from (select pg_temp.adm('select public.qbo_match_auto(''customer'', null, 20000)::text')::jsonb j) x), '20 true');

-- ── E) 사람 짝 · 풀기 ──
select pg_temp.chk('E1 charge freight → T-A(이미 product 의 짝) → 거부 · 어느 IMS 행인지 말한다', pg_temp.adm('select public.qbo_link_set(''charge'', ''freight'', ''T-A'')::text'), 'ERR P0001: QuickBooks Item T-A (' || :'pa_name' || ') is already linked to IMS product ' || :'pa_name' || ' — clear that link first');
select pg_temp.chk('E2 charge freight → T-F · manual · qbo_name', (select (j->>'matched_by') || ' ' || (j->>'qbo_id') || ' ' || (j->>'qbo_name') || ' ' || (j->>'ims_name') from (select pg_temp.adm('select public.qbo_link_set(''charge'', ''freight'', ''T-F'')::text')::jsonb j) x), 'manual T-F Freight freight');
select pg_temp.adm('select public.qbo_link_set(''charge'', ''freight'', ''T-D'')::text') as e3 \gset
select pg_temp.chk('E3 charge freight → T-D(덮기) · updated_by = 가짜 admin(ims_touch)', (select (j->>'qbo_id') || ' ' || (j->>'matched_by') from (select :'e3'::jsonb j) x)
  || ' ' || (select (l.updated_by = 'a1a1a1a1-0000-4000-8000-00000000000a')::text || ' ' || (l.updated_at >= l.matched_at)::text from public.qbo_link l where l.ims_kind = 'charge' and l.ims_id = 'freight'), 'T-D manual true true');
select pg_temp.adm(format('select public.qbo_link_set(''service'', %L, ''T-S'')::text', :'svc_id')) as e4a, pg_temp.adm(format('select public.qbo_link_set(''tax_rule'', %L, ''2'')::text', :'tx_id')) as e4b \gset
select pg_temp.chk('E4 service(ref_service.id) → T-S · tax_rule Exempt (Sale) → 2(Zero-rated · 이미 둘의 짝 · N:1 허용)', (:'e4a'::jsonb->>'qbo_id') || ' ' || (:'e4b'::jsonb->>'qbo_id') || ' ' || (select count(*)::text from public.qbo_link where ims_kind = 'tax_rule' and qbo_id = '2'), 'T-S 2 3');
select pg_temp.chk('E5 customer cA → C-C1(비어 있음) 덮기 OK · cB → C-C1 은 거부', (select (j->>'qbo_id') || ' ' || (j->>'matched_by') from (select pg_temp.adm(format('select public.qbo_link_set(''customer'', %L, ''C-C1'')::text', :'ca_id'))::jsonb j) x)
  || ' | ' || left(pg_temp.adm(format('select public.qbo_link_set(''customer'', %L, ''C-C1'')::text', :'cb_id')), 35), 'C-C1 manual | ERR P0001: QuickBooks Customer C-C1');
select pg_temp.chk('E6 거부 — opening · 없는 IMS 행 · gone 행 · 안 받은 Id · 모르는 kind',
  left(pg_temp.adm('select public.qbo_link_set(''payment_method'', ''opening'', ''1'')::text'), 48) || ' | ' || left(pg_temp.adm('select public.qbo_link_set(''product'', ''00000000-0000-4000-8000-000000000000'', ''T-A'')::text'), 25)
  || ' | ' || left(pg_temp.adm(format('select public.qbo_link_set(''product'', %L, ''T-OLD'')::text', :'pa_id')), 61) || ' | ' || left(pg_temp.adm(format('select public.qbo_link_set(''product'', %L, ''T-NOPE'')::text', :'pa_id')), 54) || ' | ' || left(pg_temp.adm('select public.qbo_link_set(''bogus'', ''x'', ''1'')::text'), 30),
  'ERR P0001: No IMS payment_method with id opening | ERR P0001: No IMS product | ERR P0001: QuickBooks Item T-OLD (Gone from QuickBooks) is no | ERR P0001: QuickBooks Item T-NOPE is not in the pulled | ERR P0001: kind must be one of');
select pg_temp.chk('E7 clear charge freight → 1 · 다시 → 0 · manager 는 거부', (select j->>'deleted' from (select pg_temp.adm('select public.qbo_link_clear(''charge'', ''freight'')::text')::jsonb j) x) || ' ' || (select j->>'deleted' from (select pg_temp.adm('select public.qbo_link_clear(''charge'', ''freight'')::text')::jsonb j) x)
  || ' ' || left(pg_temp.as_conn('authenticated', :'mgr'::jsonb, 'select public.qbo_link_clear(''service'', ''x'')::text'), 10), '1 0 ERR P0001:');
select pg_temp.chk('E8 pair check — DB 에 직접 틀린 짝(product ↔ Customer)은 23514', left(pg_temp.as_conn('postgres', null, format('insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by) values (%L, ''product'', ''x'', ''Customer'', ''C-A'', ''manual'') returning id::text', :'realm')), 9), 'ERR 23514');

-- ── F) 읽기 셋 ──
select pg_temp.chk('F1 summary — 9 종류 · product linked 2 · unlinked n-2 · Item pull 완주 · charge linked 0(clear 뒤) · service 1', (select jsonb_array_length(j)::text || ' ' || (select (e->>'linked') || '/' || (e->>'unlinked') || '/' || (e->>'qbo_rows') || '/' || (e->>'qbo_active') || '/' || (e->>'pull_finished_at' is not null)::text || '/' || (e->>'pull_in_progress') from jsonb_array_elements(j) e where e->>'kind' = 'product')
  || ' ' || (select (e->>'linked') || '/' || (e->>'ims_active') from jsonb_array_elements(j) e where e->>'kind' = 'charge') || ' ' || (select (e->>'linked') || '/' || (e->>'ims_active') from jsonb_array_elements(j) e where e->>'kind' = 'service') || ' ' || (select e->>'ims_active' from jsonb_array_elements(j) e where e->>'kind' = 'payment_method')
  from (select pg_temp.adm('select public.qbo_link_summary()::text')::jsonb j) x), '9 2/' || (:n_prod - 2)::text || '/7/6/true/false 0/4 1/' || :n_svc::text || ' 8');
select pg_temp.chk('F2 page product unlinked q=pC sku → 1 행 · 후보 1(비활성)', (select (j->>'total') || ' ' || (j->'rows'->0->>'ims_code') || ' ' || jsonb_array_length(j->'rows'->0->'candidates')::text || ' ' || (j->'rows'->0->'candidates'->0->>'active') || ' ' || (j->'rows'->0->>'qbo_id' is null)::text
  from (select pg_temp.adm(format('select public.qbo_link_page(''product'', ''unlinked'', %L)::text', :'pc_sku'))::jsonb j) x), '1 ' || :'pc_sku' || ' 1 false true');
select pg_temp.chk('F3 page product linked → 2 행 · 지금 QBO 이름 · matched_by · limit 은 200 으로 깎인다', (select (j->>'total') || ' ' || (j->>'limit') || ' ' || string_agg((r->>'qbo_id') || ':' || (r->>'matched_by') || ':' || (r->>'qbo_name' is not null)::text, ' ' order by r->>'qbo_id') from (select pg_temp.adm('select public.qbo_link_page(''product'', ''linked'', null, 999)::text')::jsonb j) x, jsonb_array_elements(j->'rows') r group by j), '2 200 T-A:auto_sku:true T-B1:auto_sku_name:true');
select pg_temp.chk('F4 page customer all q=cA id → 짝 C-C1(E5) · 후보는 이름으로(C-A)', (select (j->'rows'->0->>'qbo_id') || ' ' || (select string_agg(c->>'qbo_id', ' ' order by c->>'qbo_id') from jsonb_array_elements(j->'rows'->0->'candidates') c) from (select pg_temp.adm(format('select public.qbo_link_page(''customer'', ''all'', %L, 5, 0)::text', :'ca_id'))::jsonb j) x), 'C-C1 C-A');
select pg_temp.chk('F5 page 거부 — filter · kind', left(pg_temp.adm('select public.qbo_link_page(''product'', ''some'')::text'), 27) || ' | ' || left(pg_temp.adm('select public.qbo_link_page(''bogus'')::text'), 30), 'ERR P0001: filter must be l | ERR P0001: kind must be one of');
select pg_temp.chk('F6 entity_find Item q 없음 → 7(gone 제외) · T-A linked_to product · T-S linked_to service · limit ≤ 50', (select jsonb_array_length(j)::text || ' ' || (select (e->'linked_to'->>'kind') from jsonb_array_elements(j) e where e->>'qbo_id' = 'T-A') || ' ' || (select (e->'linked_to'->>'kind') from jsonb_array_elements(j) e where e->>'qbo_id' = 'T-S') || ' ' || (select count(*)::text from jsonb_array_elements(j) e where e->>'qbo_id' = 'T-OLD')
  from (select pg_temp.adm('select public.qbo_entity_find(''Item'', null, 500)::text')::jsonb j) x), '7 product service 0');
select pg_temp.chk('F7 entity_find 거부 — 모르는 type · manager', left(pg_temp.adm('select public.qbo_entity_find(''Invoice'', ''x'')::text'), 23) || ' | ' || left(pg_temp.as_conn('authenticated', :'mgr'::jsonb, 'select public.qbo_entity_find(''Item'', ''x'')::text'), 10), 'ERR P0001: type must be | ERR P0001:');

-- ── L) REST 두 겹 ① — 새 함수 13 의 update · delete 는 전부 깊이 0 WHERE · 기존 qbo_* 함수 md5 무변 ──
select pg_temp.chk('L1 nowhere 스캐너 = 0(새 함수 13)', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('qbo_sync_gate', 'qbo_realm_of', 'qbo_type_of', 'qbo_ims_rows', 'qbo_pull_begin', 'qbo_entity_upsert', 'qbo_pull_finish', 'qbo_match_auto', 'qbo_link_set', 'qbo_link_clear', 'qbo_link_summary', 'qbo_link_page', 'qbo_entity_find') and pg_temp.nowhere(p.prosrc) <> 0), null);
select pg_temp.chk('L2 기존 qbo_* 함수 md5 전부 begin 앞과 같다', (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5), :n_fn::text);

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.ims_staff where email like 'qbo-sync-1a-%') = 0 as fake_staff_gone,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same,
       (select count(*) from public.ref_tax_rule where qbo_id is not null) = 0 as tax_qbo_id_still_null;
\if :{?mig}
select (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname in ('qbo_entity', 'qbo_pull_state', 'qbo_link')) = 0 as tables_gone_as_expected;
\else
select (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname in ('qbo_entity', 'qbo_pull_state', 'qbo_link')) = 3 as tables_present,
       (select count(*) from public.qbo_link where ims_id in ('x', 'freight') and matched_by = 'manual' and qbo_id in ('T-D', 'T-F')) = 0 as fake_links_gone, (select count(*) from public.qbo_entity where qbo_id like 'T-%') = 0 as fake_entities_gone;
\endif
