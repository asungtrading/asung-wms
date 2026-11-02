-- supabase/tests/qbo_sync_2d1_check.sql — qbo-sync-2d1 검증: claim(p_job_ids · need_jobs · requested) · 미리 보기 · 목록(거르기 · 칸 · 정렬) · retry skipped · 권한(qbo · qbo:read · 없음) · nowhere (2026-11-02 · 판정 971)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback · ⚠️ begin ~ rollback 10 초 안
--   Claude Code(시험): MIG=supabase/migrations/20261102150000_qbo_sync_2d1_pick_send.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2d1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 차이는 G0 · L2(시험만) · 기대 OK 수는 EXPECT_OK
--   쓰기: 가짜 직원 3(북키퍼 qbo · 보기 qbo:read · 아무 열쇠 없음) · 손님 4 · 제품 2 · 인보이스 6 · 크레딧 2 · 전부 rollback · QBO 호출 0
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 18
\else
\set EXPECT_OK 17
\endif
\pset pager off
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%';
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.product) as n_prod0,
       (select count(*) from public.so) as n_so0, (select count(*) from public.so_invoice) as n_inv0, (select count(*) from public.qbo_job) as n_job0, (select count(*) from public.qbo_txn) as n_txn0, (select count(*) from public.so_credit) as n_cr0,
       (select realm_id from public.qbo_connection where singleton) as realm, (select count(*) from public.qbo_link) as n_link0, (select count(*) from public.qbo_entity) as n_ent0,
       (select id::text from public.ref_currency where code = 'CAD') as cad_id, (select id::text from public.ref_tax_rule where name = 'HST ON (Sale)') as hst_id,
       (select l.qbo_id from public.ref_tax_rule t join public.qbo_link l on l.ims_kind = 'tax_rule' and l.ims_id = t.id::text where t.name = 'HST ON (Sale)') as hst_qbo,
       (select id::text from public.ref_payment_term where name = 'Net 60') as net60_id,
       (select coalesce(to_jsonb(e)->>'detail', '') from public.qbo_entity e where e.qbo_type = 'TaxCode' and e.qbo_id = (select l.qbo_id from public.ref_tax_rule t join public.qbo_link l on l.ims_kind = 'tax_rule' and l.ims_id = t.id::text where t.name = 'HST ON (Sale)')) as tc_detail0,
       (select count(*) from public.qbo_job where state = 'queued') as n_queued0, (select count(*) from public.qbo_job where state = 'sent') as n_sent0 \gset
\echo '── 기준: 함수' :n_fn '· staff' :n_staff0 '· job' :n_job0 '(queued' :n_queued0 '· sent' :n_sent0 ') · realm' :realm '· HST ON →' :hst_qbo
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$ insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want); $$;
create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
declare v text; v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
  execute format('set local role %I', p_role);
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return coalesce(v, '(null)');
end $$;
create function pg_temp.bk(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"d2d2d2d2-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
create function pg_temp.vw(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"d2d2d2d2-0000-4000-8000-000000000002"}'::jsonb, p_sql) $$;
create function pg_temp.nobody(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"d2d2d2d2-0000-4000-8000-000000000003"}'::jsonb, p_sql) $$;
create function pg_temp.svc(p_sql text) returns text language sql as $$ select pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, p_sql) $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g'); exit when v_chunk = v_prev; end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
-- 가짜 직원 셋 · 손님 넷(A 짝 있음 · B 짝 있음 · 부모 P · 자식 C) · 제품 둘(1 짝 · 2 없음)
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('d2d2d2d2-0000-4000-8000-00000000000a', 'd2d2d2d2-0000-4000-8000-000000000001', 'qbo-sync-2d1-bk@asung.invalid', 'QBO 2d1 Bookkeeper', 'manager', '["qbo", "sales"]'),
  ('d2d2d2d2-0000-4000-8000-00000000000b', 'd2d2d2d2-0000-4000-8000-000000000002', 'qbo-sync-2d1-view@asung.invalid', 'QBO 2d1 Viewer', 'worker', '["qbo:read"]'),
  ('d2d2d2d2-0000-4000-8000-00000000000c', 'd2d2d2d2-0000-4000-8000-000000000003', 'qbo-sync-2d1-none@asung.invalid', 'QBO 2d1 Nobody', 'worker', '["picking"]');
insert into public.customer (id, name, is_active, source, currency_code, payment_term_id, payment_term_name, tax_rule) values
  ('c2d00000-0000-4000-8000-00000000000a', 'QBO2D Store A', true, 'manual', 'CAD', :'net60_id'::uuid, 'Net 60', 'HST ON (Sale)'),
  ('c2d00000-0000-4000-8000-00000000000b', 'QBO2D Store B', true, 'manual', 'CAD', null, null, null),
  ('c2d00000-0000-4000-8000-000000000010', 'QBO2D Parent', true, 'manual', 'CAD', null, null, null);
insert into public.customer (id, name, is_active, source, currency_code, parent_id, parent_source, default_bill_to_customer_id) values
  ('c2d00000-0000-4000-8000-000000000011', 'QBO2D Kid Store', true, 'manual', 'CAD', 'c2d00000-0000-4000-8000-000000000010', 'ims', 'c2d00000-0000-4000-8000-000000000010');
insert into public.customer_address (customer_id, type, is_default_for_type, line1, city, state_province, postal_code, country, source) values ('c2d00000-0000-4000-8000-000000000010', 'Billing', true, '9 Parent Rd', 'Toronto', 'ON', 'M2M 2M2', 'CA', 'manual');
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values
  (:'realm', 'customer', 'c2d00000-0000-4000-8000-00000000000a', 'Customer', 'C-2D-A', 'manual', 'QBO2D Store A'), (:'realm', 'customer', 'c2d00000-0000-4000-8000-00000000000b', 'Customer', 'C-2D-B', 'manual', 'QBO2D Store B');
insert into public.product (id, name, sku, is_active, source, sellable, revenue_account_code) values
  ('d2d00000-0000-4000-8000-000000000001', 'QBO2D Widget Blue', 'QBO2D-001', true, 'manual', true, '_98_'), ('d2d00000-0000-4000-8000-000000000002', 'QBO2D Widget Red', 'QBO2D-002', true, 'manual', true, '_98_');
insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, active) values (:'realm', 'Item', 'I-2D-1', 'QBO2D Widget Blue', 'QBO2D-001', true);
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values (:'realm', 'product', 'd2d00000-0000-4000-8000-000000000001', 'Item', 'I-2D-1', 'manual', 'QBO2D Widget Blue');
update public.qbo_entity set detail = coalesce(detail, '{"TaxRateDetail":[{"TaxRateRef":{"value":"12","name":"HST ON"},"TaxTypeApplicable":"TaxOnAmount","TaxOrder":0}]}'::jsonb) where realm_id = :'realm' and qbo_type = 'TaxCode' and qbo_id = :'hst_qbo';
-- 인보이스 여섯(발행 트리거가 invoice 일감을 쌓는다 · DEFERRED → immediate) — INV1 A 단순 · INV2 자식 C(needs 손님 + 부모 · Item 2) · INV3 A(skip · retry · 목록) · INV4 A 보내진 셈 · INV5 매장 둘(몸 거부) · INV6 A(not_due)
create temp sequence s_so start 99920;
create function pg_temp.mk_inv(p_id uuid, p_num text, p_bill uuid, p_bill_name text, p_cust uuid[], p_product uuid) returns void language plpgsql as $$
declare i int; v_oid uuid; v_so uuid; v_sl uuid; v_num text; v_n int := coalesce(array_length(p_cust, 1), 0);
begin
  insert into public.so_invoice (id, invoice_number, kind, status, bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country, issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due)
  values (p_id, p_num, 'sale', 'issued', p_bill, p_bill_name, '1 Any St', 'Toronto', 'ON', 'M1M 1M1', 'CA', public.ims_today(), 'd2d2d2d2-0000-4000-8000-00000000000a', null, null, null, (select id from public.ref_currency where code = 'CAD'), 'CAD', 2 * v_n, 2 * v_n, 0.26 * v_n, 2.26 * v_n, 2.26 * v_n);
  for i in 1 .. v_n loop
    v_so := gen_random_uuid(); v_sl := gen_random_uuid(); v_oid := gen_random_uuid(); v_num := 'SO-' || nextval('s_so')::text;
    insert into public.so (id, so_number, customer_id, bill_to_customer_id, channel, intake, currency_id, currency_code, order_date, ref, shipped_at, ship_to_company, ship_to_line1, ship_to_city, ship_to_country)
    values (v_so, v_num, p_cust[i], p_bill, 'pos', 'manual', (select id from public.ref_currency where code = 'CAD'), 'CAD', public.ims_today(), 'PO-' || v_num, now(), 'Ship', '5 St', 'Toronto', 'CA');
    insert into public.so_line (id, so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, unit_price) values (v_sl, v_so, 1, p_product, (select sku from public.product where id = p_product), (select name from public.product where id = p_product), 1, 1, 1, 2);
    insert into public.so_invoice_order (id, invoice_id, so_id, so_number, customer_id, ship_to_company, ship_to_line1, ship_to_city, ship_to_country, tax_rule_id, tax_rule, rate_pct, tax_source, lines_amount, taxable_amount, tax_amount, total)
    values (v_oid, p_id, v_so, v_num, p_cust[i], 'Ship', '5 St', 'Toronto', 'CA', (select id from public.ref_tax_rule where name = 'HST ON (Sale)'), 'HST ON (Sale)', 13, 'ship_to', 2, 2, 0.26, 2.26);
    insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, qty, unit_price, amount, tax_amount, account_code) values (p_id, v_oid, i, 'product', v_sl, (select sku from public.product where id = p_product), (select name from public.product where id = p_product), 1, 2, 2, 0.26, '_98_');
  end loop;
end $$;
select pg_temp.mk_inv('12d00000-0000-4000-8000-000000000001', '9980001', 'c2d00000-0000-4000-8000-00000000000a', 'QBO2D Store A', array['c2d00000-0000-4000-8000-00000000000a'::uuid], 'd2d00000-0000-4000-8000-000000000001');
select pg_temp.mk_inv('12d00000-0000-4000-8000-000000000002', '9980002', 'c2d00000-0000-4000-8000-000000000010', 'QBO2D Parent', array['c2d00000-0000-4000-8000-000000000011'::uuid], 'd2d00000-0000-4000-8000-000000000002');
select pg_temp.mk_inv('12d00000-0000-4000-8000-000000000003', '9980003', 'c2d00000-0000-4000-8000-00000000000a', 'QBO2D Store A', array['c2d00000-0000-4000-8000-00000000000a'::uuid], 'd2d00000-0000-4000-8000-000000000001');
select pg_temp.mk_inv('12d00000-0000-4000-8000-000000000004', '9980004', 'c2d00000-0000-4000-8000-00000000000a', 'QBO2D Store A', array['c2d00000-0000-4000-8000-00000000000a'::uuid], 'd2d00000-0000-4000-8000-000000000001');
select pg_temp.mk_inv('12d00000-0000-4000-8000-000000000005', '9980005', 'c2d00000-0000-4000-8000-00000000000a', 'QBO2D Store A', array['c2d00000-0000-4000-8000-00000000000a'::uuid, 'c2d00000-0000-4000-8000-00000000000b'::uuid], 'd2d00000-0000-4000-8000-000000000001');
select pg_temp.mk_inv('12d00000-0000-4000-8000-000000000006', '9980006', 'c2d00000-0000-4000-8000-00000000000a', 'QBO2D Store A', array['c2d00000-0000-4000-8000-00000000000a'::uuid], 'd2d00000-0000-4000-8000-000000000001');
set constraints all immediate;
-- INV4 는 보내진 셈(일감 sent · qbo_txn) · INV6 은 내일로(not_due) · 크레딧 둘(CR1 INV1 → 960 기다림 · CR2 INV4 → 간다) · 일감 만든 순서를 또렷하게(created_at 1 초씩)
update public.qbo_job set state = 'sent', qbo_id = 'INV-2D-4', qbo_name = '9980004', sent_at = now() where ims_id = '12d00000-0000-4000-8000-000000000004' and kind = 'invoice';
insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, sent_at) values (:'realm', 'invoice', '12d00000-0000-4000-8000-000000000004', 'Invoice', 'INV-2D-4', '9980004', '0', 2.26, 0.26, now());
update public.qbo_job set next_at = now() + interval '1 day' where ims_id = '12d00000-0000-4000-8000-000000000006' and kind = 'invoice';
insert into public.so_credit (id, credit_number, status, customer_id, store_customer_id, currency_id, currency_code, invoice_id, reason, warehouse_id, warehouse_name, issued_on, issued_by, lines_amount, fee_amount, tax_amount, total, order_discount_amount, freight_discount_amount, surcharge_amount)
select x.id, x.num, 'issued', 'c2d00000-0000-4000-8000-00000000000a', 'c2d00000-0000-4000-8000-00000000000a', :'cad_id'::uuid, 'CAD', x.inv, 'customer_return', (select id from public.ref_warehouse where name = 'Asung Trading Inc.'), 'Asung Trading Inc.', public.ims_today(), 'd2d2d2d2-0000-4000-8000-00000000000a', 2, 0, 0.26, 2.26, 0, 0, 0
  from (values ('32d00000-0000-4000-8000-000000000001'::uuid, 'CR-99801', '12d00000-0000-4000-8000-000000000001'::uuid), ('32d00000-0000-4000-8000-000000000002'::uuid, 'CR-99802', '12d00000-0000-4000-8000-000000000004'::uuid)) x(id, num, inv);
insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, product_id, sku, description, qty_returned, not_restocked_reason, unit_price, amount, rate_pct, tax_amount, account_code)
select c.id, 1, 'product', (select il.id from public.so_invoice_line il where il.invoice_id = c.invoice_id and il.line_no = 1), 'd2d00000-0000-4000-8000-000000000001', 'QBO2D-001', 'QBO2D Widget Blue', 1, 'not_returned', 2, 2, 13, 0.26, '_98_' from public.so_credit c where c.id::text like '32d00000%';
set constraints all immediate;
update public.qbo_job j set created_at = now() - interval '2 years' + (x.n * interval '1 second') from (select id, row_number() over (order by ims_id) as n from public.qbo_job where ims_id like '12d00000%' or ims_id like '32d00000%') x where j.id = x.id;
select (select id from public.qbo_job where ims_id = '12d00000-0000-4000-8000-000000000001' and kind = 'invoice') as j1, (select id from public.qbo_job where ims_id = '12d00000-0000-4000-8000-000000000002' and kind = 'invoice') as j2,
       (select id from public.qbo_job where ims_id = '12d00000-0000-4000-8000-000000000003' and kind = 'invoice') as j3, (select id from public.qbo_job where ims_id = '12d00000-0000-4000-8000-000000000004' and kind = 'invoice') as j4,
       (select id from public.qbo_job where ims_id = '12d00000-0000-4000-8000-000000000005' and kind = 'invoice') as j5, (select id from public.qbo_job where ims_id = '12d00000-0000-4000-8000-000000000006' and kind = 'invoice') as j6,
       (select id from public.qbo_job where ims_id = '32d00000-0000-4000-8000-000000000001' and kind = 'credit') as jc1, (select id from public.qbo_job where ims_id = '32d00000-0000-4000-8000-000000000002' and kind = 'credit') as jc2,
       (select count(*) from public.qbo_job) as n_job1, ((now() - interval '2 years') at time zone 'America/Toronto')::date::text as fx_date \gset

-- ── A) 착지 ──
select pg_temp.chk('A1 착지 — ACL(claim 3 인자 service · doc grant 0 · preview · list 7 인자 · retry authenticated) · 옛 서명 없음',
  (select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname, p.oid) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_job_claim', 'qbo_job_doc', 'qbo_job_preview', 'qbo_job_list', 'qbo_job_retry')),
  'qbo_job_claim(p_limit integer, p_kinds text[], p_job_ids uuid[])={postgres=X/postgres,service_role=X/postgres} qbo_job_doc(p_ims_kind text, p_ims_id text)={postgres=X/postgres} qbo_job_list(p_state text, p_kinds text[], p_from date, p_to date, p_q text, p_limit integer, p_offset integer)={postgres=X/postgres,authenticated=X/postgres} qbo_job_preview(p_job uuid)={postgres=X/postgres,authenticated=X/postgres} qbo_job_retry(p_job uuid, p_note text)={postgres=X/postgres,authenticated=X/postgres}');

-- ── C) 미리 보기(먼저 — need 일감을 만들지 않는 것을 본다) ──
select pg_temp.bk(format('select public.qbo_job_preview(%L)::text', :'j2')) as pv2 \gset
select pg_temp.chk('C1 preview INV2(자식 매장 C · 제품 2) — needs 2(customer C job_id null · item 2 job_id null) · 부모 P 는 손님 몸이 알아서(needs 에 없음 · C 의 부모) · sendable false · error null · 일감 수 무변 · doc 칸 · body CustomerRef 없음',
  (select string_agg((e->>'kind') || ':' || (e->>'name') || ':' || coalesce(e->>'job_id', 'null'), ' ' order by e->>'kind') from jsonb_array_elements(:'pv2'::jsonb->'needs') e) || ' | ' || (:'pv2'::jsonb->>'sendable') || ' ' || coalesce(:'pv2'::jsonb->>'error', 'null')
  || ' | ' || (select count(*)::text from public.qbo_job) || ' | ' || (:'pv2'::jsonb->'doc'->>'doc_number') || ' ' || (:'pv2'::jsonb->'doc'->>'name') || ' ' || (:'pv2'::jsonb->'doc'->>'currency') || ' ' || (:'pv2'::jsonb->'doc'->>'total') || ' ' || (:'pv2'::jsonb->'doc'->>'doc_status')
  || ' | ' || (:'pv2'::jsonb->'body' ? 'CustomerRef')::text || ' ' || (:'pv2'::jsonb->'job'->>'state') || ' ' || (:'pv2'::jsonb->'job'->>'by_name'),
  'customer:QBO2D Kid Store:null item:QBO2D-002:null | false null | ' || :n_job1 || ' | 9980002 QBO2D Parent CAD 2.26 issued | false queued QBO 2d1 Bookkeeper');
select pg_temp.vw(format('select public.qbo_job_preview(%L)::text', :'j1')) as pv1 \gset
select pg_temp.chk('C2 preview INV1(보기 열쇠 qbo:read 로) — sendable true · needs 0 · wait null · body CustomerRef C-2D-A · DocNumber · totals 2.26 / 0.26 · warnings 3(결제조건 · 만기 · 이메일 없음 — 막지 않는다)',
  (:'pv1'::jsonb->>'sendable') || ' ' || jsonb_array_length(:'pv1'::jsonb->'needs')::text || ' ' || coalesce(:'pv1'::jsonb->>'wait', 'null') || ' | ' || (:'pv1'::jsonb->'body'->'CustomerRef'->>'value') || ' ' || (:'pv1'::jsonb->'body'->>'DocNumber') || ' | ' || (:'pv1'::jsonb->'totals'->>'total') || ' ' || (:'pv1'::jsonb->'totals'->>'tax') || ' ' || jsonb_array_length(:'pv1'::jsonb->'warnings')::text,
  'true 0 null | C-2D-A 9980001 | 2.26 0.26 3');
select pg_temp.bk(format('select public.qbo_job_preview(%L)::text', :'jc1')) as pvc1 \gset
select pg_temp.bk(format('select public.qbo_job_preview(%L)::text', :'j5')) as pv5 \gset
select pg_temp.chk('C3 preview 크레딧 CR1(INV1 queued · 960) — wait {job_id = INV1 일감 · state queued · invoice 9980001 · reason} · sendable false / INV5(매장 둘) — error 글 · body null · sendable false',
  (:'pvc1'::jsonb->'wait'->>'job_id' = :'j1')::text || ' ' || (:'pvc1'::jsonb->'wait'->>'state') || ' ' || (:'pvc1'::jsonb->'wait'->>'invoice') || ' ' || (:'pvc1'::jsonb->'wait'->>'reason') || ' ' || (:'pvc1'::jsonb->>'sendable')
  || ' | ' || left(:'pv5'::jsonb->>'error', 62) || ' ' || coalesce(:'pv5'::jsonb->>'body', 'null') || ' ' || (:'pv5'::jsonb->>'sendable'),
  'true queued 9980001 waiting for invoice 9980001 to reach QuickBooks first — send it too false | Invoice 9980005 covers 2 stores — cancel and reissue per store null false');
select pg_temp.chk('C4 preview 문 — 열쇠 없음 거부 · 없는 일감 거부 · service_role 은 grant 없음(열쇠 창구)',
  left(pg_temp.nobody(format('select public.qbo_job_preview(%L)::text', :'j1')), 58) || ' | ' || left(pg_temp.bk('select public.qbo_job_preview(''00000000-0000-4000-8000-000000000000'')::text'), 71) || ' | ' || left(pg_temp.svc(format('select public.qbo_job_preview(%L)::text', :'j1')), 50),
  'ERR P0001: Your account does not have the ''qbo'' permission | ERR P0001: Job 00000000-0000-4000-8000-000000000000 not found — nothing | ERR 42501: permission denied for function qbo_job_');

-- ── B) claim(p_job_ids) ──
select pg_temp.svc(format('select public.qbo_job_claim(15, array[''customer'',''item'',''invoice'',''invoice_void'',''credit'',''credit_void''], array[%L, %L, %L, %L, %L]::uuid[])::text', :'j1', :'j2', :'j4', :'j6', '00000000-0000-4000-8000-000000000000')) as c1 \gset
select pg_temp.chk('B1 claim 고른 5(INV1 · INV2 · INV4 sent · INV6 내일 · 없는 id) — claimed 2 · jobs 1(INV1 몸) · INV2 blocked_for_needs · need_jobs 3(customer C · 부모 P(for_job = C 일감) · item 2 · 전부 queued/blocked · existing false) · requested 5 결과 · INV2 blocked_by = 손님 C 일감(손님 우선) · 나머지 queued 는 손대지 않음',
  (:'c1'::jsonb->>'claimed') || ' ' || jsonb_array_length(:'c1'::jsonb->'jobs')::text || ' ' || (:'c1'::jsonb->'jobs'->0->>'doc_number') || ' ' || (:'c1'::jsonb->>'blocked_for_needs') || ' ' || jsonb_array_length(:'c1'::jsonb->'picked')::text
  || ' | ' || (select string_agg((e->>'kind') || ':' || (e->>'state') || ':' || (e->>'existing') || ':' || case when e->>'for_job' = :'j2' then 'inv2' when e->>'for_job' = (select id::text from public.qbo_job where kind = 'customer' and ims_id = 'c2d00000-0000-4000-8000-000000000011') then 'custC' else '?' end, ' ' order by e->>'kind', e->>'ims_id') from jsonb_array_elements(:'c1'::jsonb->'need_jobs') e)
  || ' | ' || (select string_agg((e->>'result') || case when e->>'result' = 'blocked' then '(' || (e->>'reason' like '%waiting for 2 QuickBooks record(s) to be created first')::text || ')' when e->>'result' = 'not_due' then '(' || left(e->>'reason', 24) || ')' when e->>'reason' is not null then '(' || left(e->>'reason', 45) || ')' else '' end, ' ' order by array_position(array[:'j1', :'j2', :'j4', :'j6', '00000000-0000-4000-8000-000000000000'], e->>'job_id')) from jsonb_array_elements(:'c1'::jsonb->'requested') e)
  || ' | ' || (select (j.blocked_by = (select c.id from public.qbo_job c where c.kind = 'customer' and c.ims_id = 'c2d00000-0000-4000-8000-000000000011'))::text from public.qbo_job j where j.id = :'j2')
  || ' | ' || (select string_agg(j.state, ' ' order by j.ims_id) from public.qbo_job j where j.id in (:'j3', :'j5', :'jc1', :'jc2')),
  '2 1 9980001 1 5 | customer:queued:false:custC customer:blocked:false:inv2 item:queued:false:inv2 | claimed blocked(true) not_queued(the job is sent — not sent) not_due(the job is scheduled for) not_found(no such job) | true | queued queued queued queued');
-- 바퀴 2 — 같은 id + need 일감 셋 → item · 부모 P 가 잡힌다(C 는 blocked · INV2 blocked) · 둘을 보낸 셈 → 바퀴 3 — ② 가 C 를 풀고 잡는다 → 보낸 셈 → 바퀴 4 — ② 가 INV2 를 풀고 잡는다(몸 CustomerRef = C 의 QBO id)
select (select id::text from public.qbo_job where kind = 'customer' and ims_id = 'c2d00000-0000-4000-8000-000000000011') as jcc, (select id::text from public.qbo_job where kind = 'customer' and ims_id = 'c2d00000-0000-4000-8000-000000000010') as jcp, (select id::text from public.qbo_job where kind = 'item' and ims_id = 'd2d00000-0000-4000-8000-000000000002') as ji2 \gset
select pg_temp.svc(format('select public.qbo_job_claim(15, array[''customer'',''item'',''invoice'',''invoice_void'',''credit'',''credit_void''], array[%L, %L, %L, %L]::uuid[])::text', :'j2', :'jcc', :'jcp', :'ji2')) as c2 \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''C-2D-P'', ''QBO2D Parent'', ''0'', ''tid-p'', null, null)::text', :'jcp')) as dP \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''I-2D-2'', ''QBO2D Widget Red'', ''0'', ''tid-i2'', null, ''QBO2D-002'')::text', :'ji2')) as dI \gset
select pg_temp.svc(format('select public.qbo_job_claim(15, array[''customer'',''item'',''invoice'',''invoice_void'',''credit'',''credit_void''], array[%L, %L, %L, %L]::uuid[])::text', :'j2', :'jcc', :'jcp', :'ji2')) as c3 \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''C-2D-C'', ''QBO2D Kid Store'', ''0'', ''tid-c'', null, null)::text', :'jcc')) as dC \gset
select pg_temp.svc(format('select public.qbo_job_claim(15, array[''customer'',''item'',''invoice'',''invoice_void'',''credit'',''credit_void''], array[%L, %L, %L, %L]::uuid[])::text', :'j2', :'jcc', :'jcp', :'ji2')) as c4 \gset
select pg_temp.chk('B2 바퀴 2 ~ 4 — 2: claimed 2(item · 부모 P) · C not_queued(blocked) · INV2 not_queued(blocked) / 3: C 는 done 이 이미 풀었다(unblocked 0) · claimed 1 / 4: INV2 도(unblocked 0) · claimed 1 · 몸 CustomerRef C-2D-C · ItemRef I-2D-2 · ParentRef 는 C 몸에',
  (:'c2'::jsonb->>'claimed') || ' ' || (select string_agg(j->>'kind', ' ' order by j->>'kind') from jsonb_array_elements(:'c2'::jsonb->'jobs') j) || ' ' || (select string_agg(e->>'result' || ':' || coalesce(e->>'state', '-'), ' ' order by array_position(array[:'j2', :'jcc', :'jcp', :'ji2'], e->>'job_id')) from jsonb_array_elements(:'c2'::jsonb->'requested') e)
  || ' | ' || (:'c3'::jsonb->>'unblocked') || ' ' || (:'c3'::jsonb->>'claimed') || ' ' || (:'c3'::jsonb->'jobs'->0->>'kind') || ' ' || (:'c3'::jsonb->'jobs'->0->'body'->'ParentRef'->>'value')
  || ' | ' || (:'c4'::jsonb->>'unblocked') || ' ' || (:'c4'::jsonb->>'claimed') || ' ' || (:'c4'::jsonb->'jobs'->0->>'doc_number') || ' ' || (:'c4'::jsonb->'jobs'->0->'body'->'CustomerRef'->>'value') || ' ' || (:'c4'::jsonb->'jobs'->0->'body'->'Line'->0->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || jsonb_array_length(:'c4'::jsonb->'need_jobs')::text,
  '2 customer item not_queued:blocked not_queued:blocked claimed:sending claimed:sending | 0 1 customer C-2D-P | 0 1 9980002 C-2D-C I-2D-2 0');
select pg_temp.chk('B3 claim 거부 · 옛 길 — job_ids 빈 배열 거부 · 201 개 거부 · wrong_kind(kinds customer 만 + INV3) · 열쇠 창구에서 service 아님 거부 · p_job_ids null = 옛 길(limit 1 · 가장 오래된 queued = INV3)',
  left(pg_temp.svc('select public.qbo_job_claim(15, null, array[]::uuid[])::text'), 64) || ' | ' || left(pg_temp.svc('select public.qbo_job_claim(15, null, (select array_agg(gen_random_uuid()) from generate_series(1, 201)))::text'), 66)
  || ' | ' || (select e->>'result' from jsonb_array_elements(pg_temp.svc(format('select public.qbo_job_claim(15, array[''customer''], array[%L]::uuid[])::text', :'j3'))::jsonb->'requested') e)
  || ' | ' || left(pg_temp.bk(format('select public.qbo_job_claim(15, null, array[%L]::uuid[])::text', :'j3')), 28)
  || ' | ' || (select (x::jsonb->>'claimed') || ' ' || (x::jsonb->'jobs'->0->>'doc_number') || ' ' || coalesce(x::jsonb->>'picked', 'null') || ' ' || jsonb_array_length(x::jsonb->'requested')::text from pg_temp.svc('select public.qbo_job_claim(1, array[''invoice''], null)::text') x),
  'ERR P0001: job_ids must name at least one job — nothing was read | ERR P0001: job_ids may name at most 200 jobs in one call (got 201) | wrong_kind | ERR 42501: permission denied | 1 9980003 null 0');
select pg_temp.svc(format('select public.qbo_job_fail(%L, ''test failed — body rejected'', null)::text', :'j3')) as f3 \gset
select pg_temp.svc(format('select public.qbo_job_claim(15, null, array[%L]::uuid[])::text', :'j3')) as b4a \gset
select pg_temp.svc(format('select public.qbo_job_claim(15, array[''credit''], array[%L]::uuid[])::text', :'jc1')) as b4b \gset
select pg_temp.chk('B4 requested 의 not_queued 글 — failed(retry it first) · 크레딧 CR1 고르면 blocked(960 · 인보이스 대신 보내지 않는다 · blocked_by = INV1 일감 · jobs 0)',
  (:'b4a'::jsonb->'requested'->0->>'result') || ' ' || (:'b4a'::jsonb->'requested'->0->>'reason')
  || ' | ' || (:'b4b'::jsonb->>'claimed') || ' ' || (:'b4b'::jsonb->>'blocked_for_invoice') || ' ' || jsonb_array_length(:'b4b'::jsonb->'jobs')::text || ' ' || (:'b4b'::jsonb->'requested'->0->>'result') || ' ' || ((:'b4b'::jsonb->'requested'->0->>'reason') like '%waiting for invoice 9980001 to reach QuickBooks first')::text
  || ' ' || (select (j.blocked_by = :'j1')::text from public.qbo_job j where j.id = :'jc1'),
  'not_queued the job is failed — not sent — retry it first | 1 1 0 blocked true true');
select pg_temp.svc(format('select public.qbo_job_claim(15, array[''credit''], array[%L]::uuid[])::text', :'jc1')) as b5a \gset
update public.qbo_job set state = 'blocked', blocked_by = :'j1' where id = :'j6';   -- INV6 을 「needs 로 blocked 된 꼴」 로 꾸민다(blocked_by 는 INV1 일감 · 몸은 needs 0) → 되살리기는 blocked_by 만
select pg_temp.svc(format('select public.qbo_job_claim(15, null, array[%L]::uuid[])::text', :'j6')) as b5b \gset
select pg_temp.chk('B5 blocked 인 id 를 다시 고르면(⑤ 되살리기) — CR1: not_queued(blocked) + need_jobs 1 = INV1 일감(kind invoice · existing true · for_job CR1 — EF 는 거래 종류를 안 잡는다 = 960) / INV6(blocked_by INV1 꾸밈 · needs 0): need_jobs 1 = INV1 일감 · claimed 0',
  (:'b5a'::jsonb->'requested'->0->>'result') || ':' || (:'b5a'::jsonb->'requested'->0->>'state') || ' ' || jsonb_array_length(:'b5a'::jsonb->'need_jobs')::text || ' ' || (:'b5a'::jsonb->'need_jobs'->0->>'job_id' = :'j1')::text || ' ' || (:'b5a'::jsonb->'need_jobs'->0->>'kind') || ' ' || (:'b5a'::jsonb->'need_jobs'->0->>'existing') || ' ' || (:'b5a'::jsonb->'need_jobs'->0->>'for_job' = :'jc1')::text
  || ' | ' || (:'b5b'::jsonb->>'claimed') || ' ' || jsonb_array_length(:'b5b'::jsonb->'need_jobs')::text || ' ' || (:'b5b'::jsonb->'need_jobs'->0->>'job_id' = :'j1')::text || ' ' || (:'b5b'::jsonb->'need_jobs'->0->>'state'),
  'not_queued:blocked 1 true invoice true true | 0 1 true sending');
update public.qbo_job set state = 'queued', blocked_by = null where id = :'j6';

-- ── D) 목록 ──
select pg_temp.bk('select public.qbo_job_list(null, null, null, null, null, 200, 0)::text') as l1 \gset
select pg_temp.chk('D1 list 전부 — 장치 행 11(인보이스 6 · 크레딧 2 · need 3 · by_name 으로 셈 — 실제 일감은 같은 realm 에 섞여 있다) · counts 키 · 장치 행 중 맨 앞 = failed(INV3) · 행 칸(doc_number · name · currency · total · doc_date · doc_status · job_date · blocked_kind · txn_qbo_id)',
  (select count(*)::text from jsonb_array_elements(:'l1'::jsonb->'rows') r where r->>'by_name' = 'QBO 2d1 Bookkeeper') || ' ' || (select count(*)::text from jsonb_object_keys(:'l1'::jsonb->'counts')) || ' | ' || (select (r->>'state') || ' ' || (r->>'doc_number') from jsonb_array_elements(:'l1'::jsonb->'rows') with ordinality x(r, o) where r->>'by_name' = 'QBO 2d1 Bookkeeper' order by o limit 1)
  || ' | ' || (select (r->>'doc_number') || ' ' || (r->>'name') || ' ' || (r->>'currency') || ' ' || (r->>'total') || ' ' || (r->>'doc_date' = public.ims_today()::text)::text || ' ' || (r->>'doc_status') || ' ' || (r->>'job_date' = :'fx_date')::text || ' ' || coalesce(r->>'blocked_kind', 'null') || ' ' || (r->>'txn_qbo_id') from jsonb_array_elements(:'l1'::jsonb->'rows') r where r->>'id' = :'j4'),
  '11 ' || (select count(distinct state)::text from public.qbo_job) || ' | failed 9980003 | 9980004 QBO2D Store A CAD 2.26 true issued true null INV-2D-4');
select pg_temp.vw(format('select public.qbo_job_list(''open'', array[''invoice'', ''credit''], %L::date, %L::date, null, 50, 0)::text', :'fx_date', :'fx_date')) as l2 \gset
select pg_temp.chk('D2 list(보기 열쇠) open · kinds invoice · credit · 장치 날짜(2 년 전) — 열린 것만(INV1 · INV2 sending · INV3 failed · INV5 · INV6 queued · CR1 blocked · CR2 queued = 7 · need 3 은 kind 밖) · 정렬 failed → sending(최신순) → queued(오래된 것 먼저 = INV5 → INV6 → CR2) → blocked · blocked 행 = CR1 에 부모 칸(invoice · 9980001 · sending)',
  (:'l2'::jsonb->>'total') || ' | ' || (select string_agg((r->>'state') || ':' || (r->>'doc_number'), ' ' order by o) from jsonb_array_elements(:'l2'::jsonb->'rows') with ordinality x(r, o))
  || ' | ' || (select (r->>'blocked_kind') || ' ' || (r->>'blocked_name') || ' ' || (r->>'blocked_state') from jsonb_array_elements(:'l2'::jsonb->'rows') r where r->>'id' = :'jc1'),
  '7 | failed:9980003 sending:9980002 sending:9980001 queued:9980005 queued:9980006 queued:CR-99802 blocked:CR-99801 | invoice 9980001 sending');
select pg_temp.chk('D3 list 거르기 — q 번호 1 행 · q 손님 이름(Kid = 손님 일감 1 · 인보이스 ims_name 은 청구처) · q QBO id(INV-2D-4) · 어제 0 · kinds 밖 거부 · from > to 거부 · state 밖 거부 · limit 201 → 200 · offset · 열쇠 없음 거부',
  (select (x::jsonb->>'total') || ' ' || (x::jsonb->'rows'->0->>'doc_number') from pg_temp.bk('select public.qbo_job_list(null, null, null, null, ''9980002'', 50, 0)::text') x)
  || ' | ' || (select (x::jsonb->>'total') || ' ' || (select string_agg(r->>'kind', '+' order by r->>'kind') from jsonb_array_elements(x::jsonb->'rows') r) from pg_temp.bk('select public.qbo_job_list(null, null, null, null, ''kid store'', 50, 0)::text') x)
  || ' | ' || (select (x::jsonb->>'total') from pg_temp.bk('select public.qbo_job_list(null, null, null, null, ''INV-2D-4'', 50, 0)::text') x)
  || ' | ' || (select (x::jsonb->>'total') from pg_temp.bk(format('select public.qbo_job_list(null, array[''invoice''], %L::date, %L::date, null, 50, 0)::text', :'fx_date'::date - 1, :'fx_date'::date - 1)) x)
  || ' | ' || left(pg_temp.bk('select public.qbo_job_list(null, array[''bogus''], null, null, null, 50, 0)::text'), 45) || ' | ' || left(pg_temp.bk('select public.qbo_job_list(null, null, ''2026-11-03'', ''2026-11-02'', null, 50, 0)::text'), 49)
  || ' | ' || left(pg_temp.bk('select public.qbo_job_list(''bogus'', null, null, null, null, 50, 0)::text'), 28) || ' | ' || (select (x::jsonb->>'limit') || ' ' || (x::jsonb->>'offset') || ' ' || jsonb_array_length(x::jsonb->'rows')::text from pg_temp.bk('select public.qbo_job_list(null, null, null, null, null, 201, 100000)::text') x)
  || ' | ' || left(pg_temp.nobody('select public.qbo_job_list()::text'), 58),
  '1 9980002 | 1 customer | 1 | 0 | ERR P0001: kinds must be among customer, item | ERR P0001: from 2026-11-03 is after to 2026-11-02 | ERR P0001: state must be one | 200 100000 0 | ERR P0001: Your account does not have the ''qbo'' permission');

-- ── E) retry skipped(문장마다 \gset — 같은 문장 안의 InitPlan 순서는 믿지 않는다) ──
select pg_temp.bk(format('select public.qbo_job_skip(%L, ''sent by hand'')::text', :'j5')) as s5 \gset
select j.request_id::text as rid0 from public.qbo_job j where j.id = :'j5' \gset
select left(pg_temp.bk(format('select public.qbo_job_retry(%L)::text', :'j5')), 81) as e1a \gset
select pg_temp.bk(format('select public.qbo_job_retry(%L, ''changed my mind'')::text', :'j5')) as e1b \gset
select coalesce(j.blocked_by::text, 'null') || ' ' || (j.request_id::text <> :'rid0')::text || ' ' || j.note as e1c from public.qbo_job j where j.id = :'j5' \gset
select pg_temp.bk(format('select public.qbo_job_skip(%L, ''again'')::text', :'j5')) as e1d \gset
select coalesce(pg_temp.as_conn('postgres', null, format('update public.so_invoice set status = ''cancelled'', cancelled_at = now(), cancelled_by = %L, cancel_note = ''t'' where id = ''12d00000-0000-4000-8000-000000000005'' returning status', 'd2d2d2d2-0000-4000-8000-00000000000a')), '?') as e1e \gset
select left(pg_temp.bk(format('select public.qbo_job_retry(%L, ''try'')::text', :'j5')), 107) as e1f \gset
select pg_temp.bk(format('select public.qbo_job_retry(%L)::text', :'j3')) as e1g \gset
select left(pg_temp.vw(format('select public.qbo_job_retry(%L, ''x'')::text', :'j3')), 66) as e1h \gset
select pg_temp.chk('E1 retry skipped — note 없음 거부 · note 있으면 queued(was skipped · blocked_by null · request_id 새로 · note) · 다시 skip → 인보이스 취소(직접 update · 트리거는 skipped 를 건드리지 않음) → retry 거부(is cancelled) · failed(INV3) 는 옛대로 note 없이 queued(was failed) · 보기 열쇠 거부',
  :'e1a' || ' | ' || (:'e1b'::jsonb->>'state') || ' ' || (:'e1b'::jsonb->>'was') || ' ' || :'e1c' || ' | ' || (:'e1d'::jsonb->>'state') || ' ' || :'e1e' || ' ' || :'e1f' || ' | ' || (:'e1g'::jsonb->>'state') || ' ' || (:'e1g'::jsonb->>'was') || ' | ' || :'e1h',
  'ERR P0001: Say why this skipped job should be sent after all (a note is required) | queued skipped null true changed my mind | skipped cancelled ERR P0001: Invoice 9980005 is cancelled — a skipped job can only be sent again while the document is issued | queued failed | ERR P0001: Your account does not have the ''qbo'' (write) permission');
insert into public.qbo_job (id, realm_id, kind, ims_kind, ims_id, state, note, by_staff) values ('a2d00000-0000-4000-8000-000000000001', :'realm', 'customer', 'customer', 'c2d00000-0000-4000-8000-00000000000b', 'skipped', 'old skip', 'd2d2d2d2-0000-4000-8000-00000000000a');
insert into public.qbo_job (id, realm_id, kind, ims_kind, ims_id, state, by_staff) values ('a2d00000-0000-4000-8000-000000000002', :'realm', 'customer', 'customer', 'c2d00000-0000-4000-8000-00000000000b', 'queued', 'd2d2d2d2-0000-4000-8000-00000000000a');
update public.qbo_job set state = 'skipped', note = 'skip void' where id = :'jc2';
update public.so_credit set status = 'cancelled', cancelled_at = now(), cancelled_by = 'd2d2d2d2-0000-4000-8000-00000000000a', cancel_note = 't' where id = '32d00000-0000-4000-8000-000000000002';
select left(pg_temp.bk('select public.qbo_job_retry(''a2d00000-0000-4000-8000-000000000001'', ''why'')::text'), 114) as e2a \gset
select left(pg_temp.bk(format('select public.qbo_job_retry(%L, ''why'')::text', :'jc2')), 112) as e2b \gset
select coalesce(pg_temp.as_conn('postgres', null, 'delete from public.qbo_job where id = ''a2d00000-0000-4000-8000-000000000002'' returning state'), '?') as e2c \gset
select pg_temp.bk('select public.qbo_job_retry(''a2d00000-0000-4000-8000-000000000001'', ''why'')::text') as e2d \gset
select pg_temp.chk('E2 retry skipped 거부 둘 — 같은 열쇠의 열린 일감이 있으면(손님 B) · 크레딧 CR2 skipped 뒤 크레딧이 취소되면(credit 은 issued 여야) · 손님 · Item 은 문서 검사 없음(열린 일감 없으면 queued)',
  :'e2a' || ' | ' || :'e2b' || ' | ' || :'e2c' || ' ' || (:'e2d'::jsonb->>'state') || ' ' || (:'e2d'::jsonb->>'was'),
  'ERR P0001: Another open job (a2d00000-0000-4000-8000-000000000002) already exists for this customer — send or skip | ERR P0001: Credit note CR-99802 is cancelled — a skipped job can only be sent again while the document is issued | queued queued skipped');

-- ── L) REST 두 겹 ① — nowhere · 다른 함수 md5 무변 ──
select pg_temp.chk('L1 nowhere 스캐너 = 0(새 2 + 재발행 3)', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_job_claim', 'qbo_job_doc', 'qbo_job_preview', 'qbo_job_list', 'qbo_job_retry')),
  'qbo_job_claim=0 qbo_job_doc=0 qbo_job_list=0 qbo_job_preview=0 qbo_job_retry=0');
\if :{?mig}
select pg_temp.chk('L2 기존 함수 md5 — 재발행 3(claim · list · retry) 빼고 전부 begin 앞과 같다', (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5)
  || ' ' || (select string_agg(t.proname, ' ' order by t.proname) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5), (:n_fn - 3)::text || ' qbo_job_claim qbo_job_list qbo_job_retry');
\endif
select pg_temp.chk('L3 scanner 자기 시험', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text, '101');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.ims_staff where email like 'qbo-sync-2d1-%') = 0 as fake_staff_gone,
       (select count(*) from public.customer) = :n_cust0 as customer_same, (select count(*) from public.product) = :n_prod0 as product_same, (select count(*) from public.so) = :n_so0 as so_same,
       (select count(*) from public.so_invoice) = :n_inv0 as invoice_same, (select count(*) from public.so_credit) = :n_cr0 as credit_same, (select count(*) from public.qbo_job) = :n_job0 as job_same, (select count(*) from public.qbo_job where state = 'queued') = :n_queued0 as queued_same,
       (select count(*) from public.qbo_txn) = :n_txn0 as txn_same, (select count(*) from public.qbo_link) = :n_link0 as link_same, (select count(*) from public.qbo_entity) = :n_ent0 as entity_same,
       (select coalesce(to_jsonb(e)->>'detail', '') from public.qbo_entity e where e.qbo_type = 'TaxCode' and e.qbo_id = :'hst_qbo') = :'tc_detail0' as tc_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
\if :{?mig}
select (select count(*) from pg_proc where proname = 'qbo_job_preview') = 0 as fn_gone_as_expected;
\else
select (select count(*) from pg_proc where proname = 'qbo_job_preview') = 1 as fn_present;
\endif
