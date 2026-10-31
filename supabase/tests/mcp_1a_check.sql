-- supabase/tests/mcp_1a_check.sql — mcp-1a 검증: 역할 ims_connector · PUBLIC 9 회수 · mcp_config · 훅 · 열쇠 claude · mcp_gate · 도구 ① ~ ⑤ (2026-10-31 UTC · 판정 917 ~ 923)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4 · 잠금 규칙) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i) → 가짜 재료 → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): MIG=supabase/migrations/20261031233700_mcp_1a_connector_role_hook_tools.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/mcp_1a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다(MIG= 도 필요 없다) — 두 갈래의 차이는 G0(시험만 · echo 줄 · t_res 밖) · Z 의 역할 수(시험 0 · 확인 1) · 기대 OK 수는 같다
--   쓰기: 가짜 직원 6 · 손님 1(+연락처) · 공급처 1 · SO-79001(줄 2 · 백오더 예약 1) · PO-79001(줄 1 · RCV-79001) · ⚠️ mcp_config 한 줄의 claude_client_id 를 시험 값으로 바꾼다(설정 행 · rollback 으로 되돌아간다 · 거래 행 아님) · 시퀀스 무접촉(번호 명시)
--   REST 두 겹: ① 아래 L1 nowhere 정적 셈 ② 실호출은 ims_connector 토큰을 OAuth 없이 못 만든다 → mcp-4 실연결에서(보고에 「REST 미시험 · mcp-4」)
\set ON_ERROR_STOP on
\set EXPECT_OK 76
\pset pager off
select md5(public.ims_perm_catalog()::text) as cat_pre_md5, public.ims_perm_catalog()::text as cat_pre \gset
select (select count(*) from public.so) as n_so, (select count(*) from public.so_line) as n_so_line, (select count(*) from public.customer) as n_cust, (select count(*) from public.ims_staff) as n_staff,
       (select count(*) from public.po) as n_po, (select count(*) from public.supplier) as n_sup, (select count(*) from pg_roles where rolname = 'ims_connector') as n_role0,
       (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')) as n_pub0 \gset
select p.sku as stk_sku from public.inv_available_base('045e4ca6-b7a9-446e-9e6a-a5a0db56d456'::uuid, null) b join public.product p on p.id = b.stock_pid where b.qty_ea > 0 and p.parent_product_id is null order by p.sku limit 1 \gset
\echo '── 기준: so' :n_so '· so_line' :n_so_line '· customer' :n_cust '· staff' :n_staff '· po' :n_po '· supplier' :n_sup '· role ims_connector' :n_role0 '· PUBLIC EXECUTE 함수' :n_pub0 '· 재고 있는 sku' :stk_sku '· catalog md5' :cat_pre_md5
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
-- 역할 · claims 를 바꿔 한 문장을 돌린다(끝나면 되돌린다 · 오류는 'ERR sqlstate: msg' 글로)
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
create function pg_temp.keys(j jsonb) returns setof text language plpgsql as $$
declare r record;
begin
  if jsonb_typeof(j) = 'object' then
    for r in select key, value from jsonb_each(j) loop
      return next r.key;
      if jsonb_typeof(r.value) in ('object', 'array') then return query select pg_temp.keys(r.value); end if;
    end loop;
  elsif jsonb_typeof(j) = 'array' then
    for r in select value from jsonb_array_elements(j) loop
      if jsonb_typeof(r.value) in ('object', 'array') then return query select pg_temp.keys(r.value); end if;
    end loop;
  end if;
end $$;
-- 앞글자 비교 도우미: v 가 p 로 시작하면 p 를, 아니면 v 앞 120 자를 돌려준다(want = p)
create function pg_temp.st(v text, p text) returns text language sql as $$ select case when v like p || '%' then p else left(v, 120) end $$;
-- safeupdate 정적 셈(ar_2b_check.sql 의 nowhere 그대로): 깊이 0 WHERE 없는 update · delete 수
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

-- ── 가짜 재료(79xxx · 메모 · 이메일 · 전화 · 주소를 일부러 채운다 — 923 시험) ──
create temp table t_f as select gen_random_uuid() as a_id, gen_random_uuid() as b_id, gen_random_uuid() as c_id, gen_random_uuid() as d_id, gen_random_uuid() as e_id, gen_random_uuid() as f_id,
                                gen_random_uuid() as cust_id, gen_random_uuid() as sup_id, gen_random_uuid() as so_id, gen_random_uuid() as l1_id, gen_random_uuid() as l2_id,
                                gen_random_uuid() as po_id, gen_random_uuid() as pl_id, gen_random_uuid() as rc_id,
                                '045e4ca6-b7a9-446e-9e6a-a5a0db56d456'::uuid as wh_tor, 'e6f5d46f-b345-47e2-916c-f7f64aeb78b7'::uuid as cad, 'mcp-test-client-79001'::text as cid;
insert into public.ims_staff (id, auth_user_id, email, name, role, perms, is_active)
select a_id, gen_random_uuid(), 'mcp79001a@test.invalid', 'MCP Fake A', 'manager', '["ims","claude","sales","purchasing","cost"]'::jsonb, true from t_f union all
select b_id, gen_random_uuid(), 'mcp79001b@test.invalid', 'MCP Fake B', 'manager', '["ims","claude"]'::jsonb, true from t_f union all
select c_id, gen_random_uuid(), 'mcp79001c@test.invalid', 'MCP Fake C', 'manager', '["ims","sales","purchasing"]'::jsonb, true from t_f union all
select d_id, gen_random_uuid(), 'mcp79001d@test.invalid', 'MCP Fake D', 'manager', '["ims","claude","sales"]'::jsonb, false from t_f union all
select e_id, gen_random_uuid(), 'mcp79001e@test.invalid', 'MCP Fake E', 'admin', '[]'::jsonb, true from t_f union all
select f_id, gen_random_uuid(), 'mcp79001f@test.invalid', 'MCP Fake F', 'manager', '["ims","claude:read","sales"]'::jsonb, true from t_f;
insert into public.customer (id, name, source, note, cin7_comments, tax_number, currency_id, currency_code, price_tier, default_location_id, default_location_name)
select cust_id, 'MCP Test Customer 79001', 'manual', 'MCP-MEMO-79001-CUSTNOTE', 'MCP-MEMO-79001-CIN7C', 'MCPTAX79001', cad, 'CAD', 'Wholesale', wh_tor, 'Asung Trading Inc.' from t_f;
insert into public.customer_contact (customer_id, name, email, phone, source, is_default) select cust_id, 'MCP Contact 79001', 'mcp79001@test.invalid', '416-555-7979', 'manual', true from t_f;
insert into public.supplier (id, name, payment_term_name, account_payable_code, source) select sup_id, 'MCP Test Supplier 79001', 'Net 30', '2000', 'manual' from t_f;
insert into public.so (id, so_number, customer_id, channel, intake, status, currency_id, currency_code, location_id, location_name, order_date, comments, shipping_notes, ship_to_phone, ship_to_contact, ship_to_line1, bill_to_line1, carrier, tracking_number)
select so_id, 'SO-79001', cust_id, 'warehouse', 'manual', 'draft', cad, 'CAD', wh_tor, 'Asung Trading Inc.', public.ims_today(),
       'MCP-MEMO-79001-SOCOMMENT', 'MCP-MEMO-79001-SHIPNOTE', '416-555-7980', 'MCP Contact 79001', 'MCP-ADDR-79001 Fake St', 'MCP-BILL-79001 Fake Ave', 'MCP Carrier', 'MCPTRK79001' from t_f;
insert into public.so_line (id, so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, unit_price, comments)
select l1_id, so_id, 1, '0fe1366f-3bf4-45e1-bad0-3fc6cd69fbf5'::uuid, 'AAL10850', 'ARMOR ALL Glass Wipes (30 wipes)', 1, 2, 10, 'MCP-MEMO-79001-LINECOMMENT' from t_f union all
select l2_id, so_id, 2, '229a3802-886c-42e6-b58b-9da105ee936d'::uuid, 'AAL10925', 'MCP second line', 1, 3, 5, null from t_f;
update public.so set status = 'confirmed', confirmed_at = now() where id = (select so_id from t_f);
insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_at) select l2_id, 3, 'backorder', now() from t_f;
insert into public.po (id, po_number, status, supplier_id, currency_id, ship_to_warehouse_id, order_date, confirmed_at, note, supplier_contact_phone, supplier_contact_email, supplier_address_line1)
select po_id, 'PO-79001', 'confirmed', sup_id, cad, wh_tor, public.ims_today(), now(), 'MCP-MEMO-79001-PONOTE', '416-555-7981', 'mcpsup79001@test.invalid', 'MCP-ADDR-79001 Supplier Rd' from t_f;
insert into public.po_line (id, po_id, line_no, product_id, qty_ea, unit_price, note) select pl_id, po_id, 1, '0fe1366f-3bf4-45e1-bad0-3fc6cd69fbf5', 10, 7.25, 'MCP-MEMO-79001-POLINENOTE' from t_f;
insert into public.po_receipt (id, receipt_number, po_id, warehouse_id, received_on, status, confirmed_at, note) select rc_id, 'RCV-79001', po_id, wh_tor, public.ims_today(), 'confirmed', now(), 'MCP-MEMO-79001-RCVNOTE' from t_f;
insert into public.po_receipt_line (po_line_id, receipt_id, bin_id, qty_ea, received_on, note) select pl_id, rc_id, '5a35b085-c4a2-4039-87dd-3de5ff9c55ef', 4, public.ims_today(), 'MCP-MEMO-79001-RCVLINENOTE' from t_f;
select a_id, b_id, c_id, d_id, e_id, f_id, cust_id, so_id, po_id, cid from t_f \gset
select s.auth_user_id as a_uid from public.ims_staff s where s.id = :'a_id' \gset
select s.auth_user_id as b_uid from public.ims_staff s where s.id = :'b_id' \gset
select s.auth_user_id as c_uid from public.ims_staff s where s.id = :'c_id' \gset
select s.auth_user_id as d_uid from public.ims_staff s where s.id = :'d_id' \gset
select s.auth_user_id as e_uid from public.ims_staff s where s.id = :'e_id' \gset
select s.auth_user_id as f_uid from public.ims_staff s where s.id = :'f_id' \gset
select set_config('mcp.a_uid', :'a_uid', true), set_config('mcp.cid', :'cid', true), set_config('mcp.stk_sku', :'stk_sku', true), set_config('mcp.so_id', :'so_id', true);
-- claims 꼴(훅이 찍은 뒤의 토큰): sub · role · client_id
create function pg_temp.cl(p_uid text, p_cid text) returns jsonb language sql as $$ select jsonb_strip_nulls(jsonb_build_object('sub', p_uid, 'role', 'ims_connector', 'aud', 'authenticated', 'client_id', p_cid)) $$;

-- ── H) 훅(postgres 로 직접 · mcp_config 가 아직 null 인 채) ──
create temp table t_ev as select jsonb_build_object('user_id', :'a_uid', 'authentication_method', 'password',
  'claims', jsonb_build_object('sub', :'a_uid', 'role', 'authenticated', 'aud', 'authenticated', 'email', 'mcp79001a@test.invalid', 'aal', 'aal1', 'session_id', 'x', 'is_anonymous', false)) as ev;
savepoint h_null;
update public.mcp_config set claude_client_id = null where singleton;
select pg_temp.chk('H4 config null + client_id 있음 → 거부 403', (select public.ims_access_token_hook(jsonb_set(ev, '{claims,client_id}', to_jsonb(:'cid'::text)))->'error'->>'http_code' from t_ev), '403');
rollback to savepoint h_null;
update public.mcp_config set claude_client_id = :'cid' where singleton;
select pg_temp.chk('H1 client_id 없음 → 입력 그대로(jsonb 동등)', (select (public.ims_access_token_hook(ev) = ev)::text from t_ev), 'true');
select pg_temp.chk('H2 같은 client_id → role 만 ims_connector · 나머지 동등', (select (public.ims_access_token_hook(e2)->'claims'->>'role') || ' ' || ((public.ims_access_token_hook(e2) #- '{claims,role}') = (e2 #- '{claims,role}'))::text from (select jsonb_set(ev, '{claims,client_id}', to_jsonb(:'cid'::text)) as e2 from t_ev) x), 'ims_connector true');
select pg_temp.chk('H3 다른 client_id → {"error":{"http_code":403}}', (select public.ims_access_token_hook(jsonb_set(ev, '{claims,client_id}', '"someone-else"'))->'error'->>'http_code' from t_ev), '403');
select pg_temp.chk('H5 깨진 입력(claims 없음 · 글자 · null · claims 숫자) → 터지지 않고 입력 그대로',
  (public.ims_access_token_hook('{}'::jsonb) = '{}'::jsonb)::text || ' ' || (public.ims_access_token_hook('"x"'::jsonb) = '"x"'::jsonb)::text || ' ' || (public.ims_access_token_hook(null) is null)::text || ' ' || (public.ims_access_token_hook('{"claims": 5}'::jsonb) = '{"claims": 5}'::jsonb)::text, 'true true true true');
select pg_temp.chk('H6 supabase_auth_admin: 훅 EXECUTE · mcp_config SELECT · select 정책 · public USAGE',
  has_function_privilege('supabase_auth_admin', 'public.ims_access_token_hook(jsonb)', 'execute')::text || ' ' || has_table_privilege('supabase_auth_admin', 'public.mcp_config', 'select')::text || ' ' ||
  (select count(*) from pg_policies where tablename = 'mcp_config' and roles = '{supabase_auth_admin}' and cmd = 'SELECT')::text || ' ' || has_schema_privilege('supabase_auth_admin', 'public', 'usage')::text, 'true true 1 true');
select pg_temp.chk('H7 훅은 authenticated · anon · service_role · ims_connector · PUBLIC 이 못 부른다',
  (select count(*) from unnest(array['authenticated', 'anon', 'service_role', 'ims_connector']) r where has_function_privilege(r, 'public.ims_access_token_hook(jsonb)', 'execute'))::text, '0');

-- ── R) 착지 — 역할 · 권한 · 카탈로그 ──
select pg_temp.chk('R1 role ims_connector: nologin · noinherit · statement_timeout 8s', (select (not rolcanlogin)::text || ' ' || (not rolinherit)::text || ' ' || rolconfig::text from pg_roles where rolname = 'ims_connector'), 'true true {statement_timeout=8s}');
select pg_temp.chk('R2 authenticator 멤버', (select count(*) from pg_auth_members m join pg_roles r on r.oid = m.roleid join pg_roles u on u.oid = m.member where r.rolname = 'ims_connector' and u.rolname = 'authenticator')::text, '1');
select pg_temp.chk('R3 public 함수의 PUBLIC EXECUTE 0(시험 전 ' || :'n_pub0' || ')', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'))::text, '0');
select pg_temp.chk('R4 옛 PUBLIC 9: ims_connector EXECUTE 0 · authenticated 9 그대로',
  (select count(*) filter (where has_function_privilege('ims_connector', p.oid, 'execute'))::text || ' ' || count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute'))::text
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('set_updated_at', 'wms_pallet_dims', 'wms_reports_planned_empty_once', 'wms_reports_resolved_how_stamp', 'so_line_combo_parent_check', 'ims_html_forbidden', 'wms_pallet_frozen_check', 'wms_pallet_freeze', 'wms_pallet_item_freeze')), '0 9');
select pg_temp.chk('R5 ims_connector 의 표 · 뷰 · 시퀀스 권한 0(public 전체 · storage.objects 포함)',
  (select count(*) from pg_class c where c.relnamespace in ('public'::regnamespace, 'storage'::regnamespace) and c.relkind in ('r', 'v', 'm', 'p', 'S') and exists (select 1 from aclexplode(c.relacl) a where a.grantee = 'ims_connector'::regrole))::text, '0');
select pg_temp.chk('R6 도구 ① ~ ⑤ proacl = postgres + ims_connector 만',
  (select string_agg(p.proname || '=' || p.proacl::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_order', 'mcp_stock', 'mcp_customer', 'mcp_po', 'mcp_backorders')),
  'mcp_backorders={postgres=X/postgres,ims_connector=X/postgres} mcp_customer={postgres=X/postgres,ims_connector=X/postgres} mcp_order={postgres=X/postgres,ims_connector=X/postgres} mcp_po={postgres=X/postgres,ims_connector=X/postgres} mcp_stock={postgres=X/postgres,ims_connector=X/postgres}');
select pg_temp.chk('R7 mcp_config relacl · RLS · 행 1', (select c.relacl::text || ' ' || c.relrowsecurity::text from pg_class c where c.oid = 'public.mcp_config'::regclass) || ' ' || (select count(*) from public.mcp_config)::text, '{postgres=arwdDxtm/postgres,supabase_auth_admin=r/postgres} true 1');
select pg_temp.chk('R8 카탈로그: claude 열쇠를 빼면 앞 판과 같다(modes · screens)', ((public.ims_perm_catalog() #- '{screens,claude}') = (:'cat_pre'::jsonb #- '{screens,claude}'))::text, 'true');
select pg_temp.chk('R9 카탈로그 claude: room ims · label 머리', (select (v->>'room') || ' ' || left(v->>'label', 16) from (select public.ims_perm_catalog()->'screens'->'claude' as v) x), 'ims Claude connector');
select pg_temp.chk('R10 ims_can_view(claude) 는 쓰지 않는다 — admin 은 역할로 true 지만 mcp_gate 는 거부(K3 에서) · 카탈로그에 열쇠가 있어야 Staff 가 그린다', (public.ims_perm_catalog()->'screens' ? 'claude')::text, 'true');

-- ── T) 도구 ① ~ ⑤ — ⓐ(claude + sales + purchasing + cost) · 역할 ims_connector · 시간 ──
create temp table t_out (k text primary key, j jsonb, ms numeric);
do $$
declare v_t timestamptz; v text; v_k text; v_sql text; v_claims jsonb := pg_temp.cl(current_setting('mcp.a_uid'), current_setting('mcp.cid'));
begin
  for v_k, v_sql in select * from (values
      ('o1', $q$select public.mcp_order(' so-79001 ')::text$q$),
      ('o2', $q$select public.mcp_order('79001')::text$q$),
      ('o3', $q$select public.mcp_order('SO-79999')::text$q$),
      ('s1', format($q$select public.mcp_stock(%L, 'North York', 5)::text$q$, current_setting('mcp.stk_sku'))),
      ('s2', format($q$select public.mcp_stock(%L, null, 5)::text$q$, current_setting('mcp.stk_sku'))),
      ('s3', $q$select public.mcp_stock('AAL10850', 'Nowhere', 5)::text$q$),
      ('s4', $q$select public.mcp_stock('AAL10850', 'edmonton', 5)::text$q$),
      ('c1', $q$select public.mcp_customer('MCP Test Customer 79001')::text$q$),
      ('c2', $q$select public.mcp_customer('beauty')::text$q$),
      ('p1', $q$select public.mcp_po('po-79001')::text$q$),
      ('p2', $q$select public.mcp_po('79999')::text$q$),
      ('b1', $q$select public.mcp_backorders('{"customer": "MCP Test Customer 79001"}', 10)::text$q$),
      ('b2', $q$select public.mcp_backorders('{"sku": "AAL109", "state": "open"}', 10)::text$q$),
      ('b3', $q$select public.mcp_backorders('{"brand": "ZZZNOBRAND79"}', 10)::text$q$),
      ('b4', $q$select public.mcp_backorders('{"warehouse": "Edmonton", "kind": "backorder"}', 10)::text$q$)) t(k, s) loop
    v_t := clock_timestamp();
    v := pg_temp.as_conn('ims_connector', v_claims, v_sql);
    if left(v, 4) = 'ERR ' then raise exception 'tool % failed: %', v_k, v; end if;
    insert into t_out values (v_k, v::jsonb, round(extract(epoch from clock_timestamp() - v_t) * 1000, 1));
  end loop;
end $$;
select k, ms, left(j::text, 110) as head from t_out order by k;
select pg_temp.chk('T1 ① found · status · 손님 이름 · 줄 2 · 운송사 · 추적번호(앞뒤 빈칸 · 소문자)', (select (j->>'found') || ' ' || (j->>'status') || ' ' || (j->>'customer_name') || ' ' || jsonb_array_length(j->'lines') || ' ' || (j->>'carrier') || ' ' || (j->>'tracking_number') from t_out where k = 'o1'), 'true confirmed MCP Test Customer 79001 2 MCP Carrier MCPTRK79001');
select pg_temp.chk('T1b ① 숫자만 → SO- 접두 · lines_total = 2×10 + 3×5', (select (j->>'so_number') || ' ' || trim_scale((j->'totals'->>'lines_total')::numeric)::text || ' ' || trim_scale((j->'lines'->0->>'unit_price')::numeric)::text from t_out where k = 'o2'), 'SO-79001 35 10');
select pg_temp.chk('T1c ① 없는 번호 → {found:false}', (select (j->>'found') || ' ' || (j->>'so_number') from t_out where k = 'o3'), 'false SO-79999');
select pg_temp.chk('T2 ② city 로 창고 → Asung Trading Inc. · 첫 줄 = 재고 있는 sku · on_hand > 0', (select (j->>'warehouse') || ' ' || (j->'rows'->0->>'sku' = current_setting('mcp.stk_sku'))::text || ' ' || ((j->'rows'->0->>'on_hand')::numeric > 0)::text from t_out where k = 's1'), 'Asung Trading Inc. true true');
select pg_temp.chk('T2b ② 창고 null = Both · by_warehouse 2', (select (j->>'warehouse' is null)::text || ' ' || jsonb_array_length(j->'rows'->0->'by_warehouse') from t_out where k = 's2'), 'true 2');
select pg_temp.chk('T2c ② 못 푸는 창고 → 활성 창고 목록 2(name · city)', (select (j->>'warehouse_not_found') || ' ' || jsonb_array_length(j->'warehouses') || ' ' || (j->'warehouses'->0->>'name') from t_out where k = 's3'), 'Nowhere 2 Asung - Edmonton');
select pg_temp.chk('T2d ② 이름 일부(edmonton) → Asung - Edmonton', (select j->>'warehouse' from t_out where k = 's4'), 'Asung - Edmonton');
select pg_temp.chk('T3 ③ 정확 이름 → 요약 · 최근 SO 1 = SO-79001 · 잔액 배열 · 연체 count 0', (select (j->>'found') || ' ' || (j->'customer'->>'name') || ' ' || jsonb_array_length(j->'recent_orders') || ' ' || (j->'recent_orders'->0->>'so_number') || ' ' || jsonb_typeof(j->'balance') || ' ' || (j->'overdue'->>'count') from t_out where k = 'c1'), 'true MCP Test Customer 79001 1 SO-79001 array 0');
select pg_temp.chk('T3b ③ 여럿(beauty) → found false · 후보 5', (select (j->>'found') || ' ' || jsonb_array_length(j->'candidates') || ' ' || ((j->>'matches')::int > 5)::text from t_out where k = 'c2'), 'false 5 true');
select pg_temp.chk('T4 ④ found · 공급처 · 줄 1(주문 10 · 받은 4 · 남은 6) · 입고 1 RCV-79001 confirmed', (select (j->>'found') || ' ' || (j->>'supplier_name') || ' ' || trim_scale((j->'lines'->0->>'qty_ordered')::numeric) || ' ' || trim_scale((j->'lines'->0->>'qty_received')::numeric) || ' ' || trim_scale((j->'lines'->0->>'qty_remaining')::numeric) || ' ' || jsonb_array_length(j->'receipts') || ' ' || (j->'receipts'->0->>'receipt_number') || ' ' || (j->'receipts'->0->>'status') from t_out where k = 'p1'), 'true MCP Test Supplier 79001 10 4 6 1 RCV-79001 confirmed');
select pg_temp.chk('T4b ④ 없는 번호 → {found:false, PO-79999}', (select (j->>'found') || ' ' || (j->>'po_number') from t_out where k = 'p2'), 'false PO-79999');
select pg_temp.chk('T5 ⑤ 손님 이름 → SO-79001 줄(AAL10925 · 열린 3 · backorder)', (select (x->>'so_number') || ' ' || (x->>'sku') || ' ' || trim_scale((x->>'qty_open')::numeric) || ' ' || (x->>'state') || ' ' || (x->>'kind') from t_out, jsonb_array_elements(j->'rows') x where k = 'b1' and x->>'so_number' = 'SO-79001'), 'SO-79001 AAL10925 3 open backorder');
select pg_temp.chk('T5b ⑤ sku 앞글자 + state → 그 줄이 든다 · total ≥ 1', (select (count(*) filter (where x->>'so_number' = 'SO-79001'))::text || ' ' || (min((j->>'total')::int) >= 1)::text from t_out, jsonb_array_elements(j->'rows') x where k = 'b2'), '1 true');
select pg_temp.chk('T5c ⑤ 못 푸는 브랜드 → resolved false · field brand', (select (j->>'resolved') || ' ' || (j->>'field') || ' ' || jsonb_typeof(j->'candidates') from t_out where k = 'b3'), 'false brand array');
select pg_temp.chk('T5d ⑤ 창고 이름(Edmonton) + kind → 돈다 · SO-79001 은 토론토라 없다', (select (j ? 'rows')::text || ' ' || (count(x) filter (where x->>'so_number' = 'SO-79001'))::text from t_out left join lateral jsonb_array_elements(j->'rows') x on true where k = 'b4' group by j), 'true 0');
select pg_temp.chk('T5e ⑤ 모르는 열쇠 → 거부 한 문장', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', :'cid'), $q$select public.mcp_backorders('{"customer_id": "x"}', 10)::text$q$), 'ERR P0001: Unknown filter customer_id'), 'ERR P0001: Unknown filter customer_id');
select pg_temp.chk('T6 시간: 도구 15 호출 전부 8 초 안 · 최대(ms)', (select (max(ms) < 8000)::text from t_out), 'true');

-- ── P) 923 · 919 — 결과 글자 · 열쇠 ──
select pg_temp.chk('P1 923: ① ② ③ ④ ⑤ 결과 글자에 심은 메모 · 이메일 · 전화 · 주소 · 세금번호 문자열 0',
  (select count(*) from t_out, unnest(array['MCP-MEMO', 'test.invalid', '416-555', 'MCP-ADDR', 'MCP-BILL', 'MCPTAX', 'MCP Contact']) s where j::text like '%' || s || '%')::text, '0');
select pg_temp.chk('P2 923: 결과 열쇠에 note · comment · email · phone · line1 · address · postal · contact 0',
  (select count(*) from t_out, lateral pg_temp.keys(j) ky where ky ~* '(note|comment|email|phone|line1|line2|address|postal|contact|ship_to_(line|phone|contact|company|city|state|country)|bill_to_(line|city|postal|state|country)|tax_number|tags)')::text, '0');
select pg_temp.chk('P3 919: ① ~ ⑤ 열쇠에 cost · landed · margin · unit_cost · cogs · gp · value 0', (select count(*) from t_out, lateral pg_temp.keys(j) ky where ky ~* '(cost|landed|margin|cogs|^gp$|value)')::text, '0');
select pg_temp.chk('P4 919: ④ 열쇠에 단가 · 금액 0(unit_price · amount · price · total · subtotal · tax · paid · unpaid)', (select count(*) from t_out, lateral pg_temp.keys(j) ky where t_out.k in ('p1', 'p2') and ky ~* '(price|amount|subtotal|^total$|_total|total_|tax|paid|unpaid|discount|charge|invoice|^payments?$|landed|cost)')::text, '0');
select pg_temp.chk('P5 ① 은 판매가 · 할인 · 합계를 낸다(원가 아님 · 919)', (select (j->'lines'->0 ? 'unit_price')::text || ' ' || (j->'lines'->0 ? 'discount_pct')::text || ' ' || (j->'totals' ? 'order_total')::text from t_out where k = 'o1'), 'true true true');

-- ── C) 닫힌 것 — ⓐ 라도 ims_connector 로는 표 · 다른 창구 · Storage 가 42501 ──
do $$
declare v_sql text; v text;
begin
  foreach v_sql in array array[
      'select count(*)::text from public.so', 'select count(*)::text from public.customer', 'select count(*)::text from public.product', 'select count(*)::text from public.ims_staff',
      'select count(*)::text from public.mcp_config', 'select count(*)::text from public.so_line', 'select count(*)::text from storage.objects',
      format('select public.so_detail(%L)::text', current_setting('mcp.so_id')), 'select public.ims_can_write(''sales'')::text', 'select public.so_confirm(null, null, false, false)::text',
      'select public.mcp_config_set(''x'')::text', 'select public.mcp_config_get()::text', 'select public.ims_html_forbidden(''x'')::text',
      'select public.stk_availability(null, ''AAL'', null, null, false, 1, 0, false, null)::text', 'select public.so_backorder_list(''{}'')::text', 'select public.mcp_gate(null)::text', 'select public.mcp_customer_pick(''a'')::text',
      'select nextval(''public.so_number_seq'')::text', 'select public.ims_access_token_hook(''{}'')::text'] loop
    v := pg_temp.as_conn('ims_connector', pg_temp.cl(current_setting('mcp.a_uid'), current_setting('mcp.cid')), v_sql);
    perform pg_temp.chk('C ims_connector 닫힘 → 42501: ' || v_sql, left(v, 9), 'ERR 42501');
  end loop;
end $$;
select pg_temp.chk('C-auth authenticated(직원 ⓐ) 는 ① ~ ⑤ EXECUTE 없음 → 42501 ×5', (select string_agg(left(pg_temp.as_conn('authenticated', jsonb_build_object('sub', :'a_uid', 'role', 'authenticated'), s), 9), ' ') from unnest(array[
  $q$select public.mcp_order('SO-79001')::text$q$, $q$select public.mcp_stock('AAL', null, 5)::text$q$, $q$select public.mcp_customer('MCP')::text$q$, $q$select public.mcp_po('PO-79001')::text$q$, $q$select public.mcp_backorders('{}', 5)::text$q$]) s), 'ERR 42501 ERR 42501 ERR 42501 ERR 42501 ERR 42501');
select pg_temp.chk('C-svc service_role · anon 도 ① EXECUTE 없음', left(pg_temp.as_conn('service_role', '{"role":"service_role"}', $q$select public.mcp_order('SO-79001')::text$q$), 9) || ' ' || left(pg_temp.as_conn('anon', '{"role":"anon"}', $q$select public.mcp_order('SO-79001')::text$q$), 9), 'ERR 42501 ERR 42501');

-- ── K) 열쇠 · 문(mcp_gate) — 921 · 이견 5 · 6 ──
select pg_temp.chk('K1 ⓑ claude 만: ① → sales 없음 거부', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'b_uid', :'cid'), $q$select public.mcp_order('SO-79001')::text$q$), 'ERR P0001: You need the ''sales'' permission to use this tool'), 'ERR P0001: You need the ''sales'' permission to use this tool');
select pg_temp.chk('K1b ⓑ claude 만: ② 재고는 열쇠 없이 된다', pg_temp.as_conn('ims_connector', pg_temp.cl(:'b_uid', :'cid'), $q$select public.mcp_stock('AAL10850', 'Edmonton', 3)->>'warehouse'$q$), 'Asung - Edmonton');
select pg_temp.chk('K2 ⓒ sales 만(claude 없음) → claude 열쇠 거부', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'c_uid', :'cid'), $q$select public.mcp_order('SO-79001')::text$q$), 'ERR P0001: Your account does not have the ''claude'' permission'), 'ERR P0001: Your account does not have the ''claude'' permission');
select pg_temp.chk('K3 ⓔ admin 인데 claude 없음 → 역할 통과 없이 거부(921)', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'e_uid', :'cid'), $q$select public.mcp_stock('AAL', null, 3)::text$q$), 'ERR P0001: Your account does not have the ''claude'' permission'), 'ERR P0001: Your account does not have the ''claude'' permission');
select pg_temp.chk('K4 ⓓ 비활성(claude + sales) → 거부', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'d_uid', :'cid'), $q$select public.mcp_order('SO-79001')::text$q$), 'ERR P0001: No active staff record for this login'), 'ERR P0001: No active staff record for this login');
select pg_temp.chk('K5 ⓕ claude:read + sales → ① 된다(이견 6)', pg_temp.as_conn('ims_connector', pg_temp.cl(:'f_uid', :'cid'), $q$select public.mcp_order('SO-79001')->>'found'$q$), 'true');
select pg_temp.chk('K6 client_id 없는 claims → 거부(이견 5)', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', null), $q$select public.mcp_order('SO-79001')::text$q$), 'ERR P0001: This tool can only be used through the Claude connector'), 'ERR P0001: This tool can only be used through the Claude connector');
select pg_temp.chk('K7 다른 client_id → 거부(이견 5)', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', 'another-client'), $q$select public.mcp_order('SO-79001')::text$q$), 'ERR P0001: This OAuth client is not the registered Claude connector'), 'ERR P0001: This OAuth client is not the registered Claude connector');
select pg_temp.chk('K8 ⓐ 가 모르는 사람(sub 없음) → 거부', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(null, :'cid'), $q$select public.mcp_order('SO-79001')::text$q$), 'ERR P0001: No active staff record for this login'), 'ERR P0001: No active staff record for this login');

-- ── W) 설정 창구(authenticated) · 바뀐 설정은 다음 호출부터(921 의 「끄면 다음 질문부터」 꼴) ──
select pg_temp.chk('W1 admin ⓔ: mcp_config_get → client_id', pg_temp.as_conn('authenticated', jsonb_build_object('sub', :'e_uid', 'role', 'authenticated'), $q$select public.mcp_config_get()->>'client_id'$q$), :'cid');
select pg_temp.chk('W2 manager ⓐ: mcp_config_set 거부(admin 만) · get 은 null', pg_temp.st(pg_temp.as_conn('authenticated', jsonb_build_object('sub', :'a_uid', 'role', 'authenticated'), $q$select public.mcp_config_set('zz')::text$q$), 'ERR P0001: Only an admin can change the Claude connector client') || ' ' || pg_temp.as_conn('authenticated', jsonb_build_object('sub', :'a_uid', 'role', 'authenticated'), $q$select public.mcp_config_get()::text$q$), 'ERR P0001: Only an admin can change the Claude connector client (null)');
select pg_temp.chk('W3 admin ⓔ: set(''zz'') → client_id zz · updated_by_name ⓔ', pg_temp.as_conn('authenticated', jsonb_build_object('sub', :'e_uid', 'role', 'authenticated'), $q$select (x->>'client_id') || ' ' || (x->>'updated_by_name') from public.mcp_config_set(' zz ') as x$q$), 'zz MCP Fake E');
select pg_temp.chk('W4 바뀐 뒤 옛 client_id 토큰 → 다음 호출부터 거부', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', :'cid'), $q$select public.mcp_order('SO-79001')::text$q$), 'ERR P0001: This OAuth client is not the registered Claude connector'), 'ERR P0001: This OAuth client is not the registered Claude connector');
select pg_temp.chk('W5 admin ⓔ: set(null) = 끄기 → client_id null', pg_temp.as_conn('authenticated', jsonb_build_object('sub', :'e_uid', 'role', 'authenticated'), $q$select coalesce(public.mcp_config_set(null)->>'client_id', '(null)')$q$), '(null)');
select pg_temp.chk('W5b 끈 뒤(다음 문장) 훅은 zz 토큰도 거부 403 · 도구도 거부', (select public.ims_access_token_hook(jsonb_set(ev, '{claims,client_id}', '"zz"'))->'error'->>'http_code' from t_ev) || ' ' || pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', 'zz'), $q$select public.mcp_order('SO-79001')::text$q$), 'ERR P0001: This OAuth client is not the registered Claude connector'), '403 ERR P0001: This OAuth client is not the registered Claude connector');

-- ── L) REST 두 겹 ① 정적 · 새 함수 md5(기록) ──
select pg_temp.chk('L1 새 함수 11 의 깊이 0 WHERE 없는 update · delete 0(mcp_config_set 은 where singleton)', (select sum(pg_temp.nowhere(p.prosrc))::text || ' ' || count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_config_get', 'mcp_config_set', 'ims_access_token_hook', 'mcp_gate', 'mcp_warehouse_id', 'mcp_customer_pick', 'mcp_order', 'mcp_stock', 'mcp_customer', 'mcp_po', 'mcp_backorders')), '0 11');
select pg_temp.chk('L2 새 함수 전부 definer(훅 · 도우미 제외 훅만 invoker) · stable(set 만 volatile) · search_path 고정', (select string_agg(p.proname || ':' || p.prosecdef::text || p.provolatile::text || (p.proconfig::text = '{"search_path=public, pg_temp"}')::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('ims_access_token_hook', 'mcp_backorders', 'mcp_config_get', 'mcp_config_set', 'mcp_customer', 'mcp_gate', 'mcp_order', 'mcp_po', 'mcp_stock')),
  'ims_access_token_hook:falsestrue mcp_backorders:truestrue mcp_config_get:truestrue mcp_config_set:truevtrue mcp_customer:truestrue mcp_gate:truestrue mcp_order:truestrue mcp_po:truestrue mcp_stock:truestrue');
select p.proname, md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'mcp\_%' or p.proname in ('ims_access_token_hook', 'ims_perm_catalog')) order by 1;

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
\if :{?mig}
\set role_want 0
\else
\set role_want 1
\endif
select (select count(*) from public.so) = :n_so as so_same, (select count(*) from public.so_line) = :n_so_line as so_line_same, (select count(*) from public.customer) = :n_cust as customer_same,
       (select count(*) from public.ims_staff) = :n_staff as staff_same, (select count(*) from public.po) = :n_po as po_same, (select count(*) from public.supplier) = :n_sup as supplier_same,
       (select count(*) from pg_roles where rolname = 'ims_connector') = :role_want as role_as_expected,
       (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')) = :n_pub0 as public_exec_same_as_before,
       md5(public.ims_perm_catalog()::text) = :'cat_pre_md5' as catalog_same_as_before;
