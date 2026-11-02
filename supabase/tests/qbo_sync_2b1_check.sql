-- supabase/tests/qbo_sync_2b1_check.sql — qbo-sync-2b1 검증: 인보이스 몸 · 발행 · 취소 트리거 · claim(p_kinds · needs) · done(qbo_txn · 942) · list · txn_of · ims_rows acct (2026-11-01 · 판정 935 ~ 946 · 951 · 지시서 ~/asung/prompts/qbo-sync-2b.md)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): MIG=supabase/migrations/20261102040000_qbo_sync_2b1_invoice_jobs.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2b1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 두 갈래의 차이는 G0(시험만) · L2(시험만 · 적용 앞 지문) · 기대 OK 수는 아래 EXPECT_OK
--   쓰기: 가짜 직원 셋(북키퍼 qbo · worker · 등록 없음) · 가짜 손님 4(매장 A · B · 부모 P · 자식 C) · 제품 3 · SO 3 · 줄 · 비용 · 인보이스 7(번호 QBO2B-* 명시 — so_invoice_next_number 시퀀스를 안 쓴다 · 시퀀스는 rollback 되지 않는다) · 거울 행 · 일감 — 전부 rollback · 실제 행 0 변경 · EF 없음 · Intuit 없음
--   ⚠️ 발행 트리거는 DEFERRED — 시험은 `set constraints all immediate` 로 당겨 쏜다(커밋하지 않으므로) · 실제 TaxCode 6(HST ON) 거울 행의 detail 을 잠깐 채운다(rollback)
--   REST 두 겹: ① L1 nowhere 스캐너(새 · 재발행 함수의 update · delete 깊이 0 WHERE) ② 배포 뒤 북키퍼 열쇠로 Settings → QuickBooks 의 일감 목록(qbo_job_list) 한 번(Caleb)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 27
\else
\set EXPECT_OK 26
\endif
\pset pager off
\set svc '{"role":"service_role"}'
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%';
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.product) as n_prod0,
       (select count(*) from public.so) as n_so0, (select count(*) from public.so_invoice) as n_inv0, (select count(*) from public.qbo_job) as n_job0, (select count(*) from public.qbo_txn) as n_txn0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select count(*) from public.qbo_link) as n_link0, (select count(*) from public.qbo_entity) as n_ent0,
       (select coalesce(value, '') from public.inv_config where key = 'qbo_send_since') as since0,
       (select id::text from public.ref_currency where code = 'CAD') as cad_id,
       (select id::text from public.ref_tax_rule where name = 'HST ON (Sale)') as hst_id,
       (select l.qbo_id from public.ref_tax_rule t join public.qbo_link l on l.ims_kind = 'tax_rule' and l.ims_id = t.id::text where t.name = 'HST ON (Sale)') as hst_qbo,
       (select id::text from public.ref_payment_term where name = 'Net 60') as net60_id,
       (select l.qbo_id from public.ref_payment_term pt join public.qbo_link l on l.ims_kind = 'payment_term' and l.ims_id = pt.id::text where pt.name = 'Net 60') as net60_qbo,
       (select id::text from public.ref_account where code = '_99_') as a99, (select id::text from public.ref_account where code = '_20_') as a20,
       (select id::text from public.ref_account where code = '_6_') as a6, (select id::text from public.ref_account where code = '_98_') as a98,
       (select l.qbo_id from public.qbo_link l where l.ims_kind = 'charge' and l.ims_id = 'freight') as freight_qbo,
       (select l.qbo_id from public.qbo_link l where l.ims_kind = 'charge' and l.ims_id = 'discount') as discount_qbo,
       (select coalesce(to_jsonb(e)->>'detail', '') from public.qbo_entity e where e.qbo_type = 'TaxCode' and e.qbo_id = '6') as tc6_detail0 \gset
\echo '── 기준: qbo_* 함수' :n_fn '· staff' :n_staff0 '· customer' :n_cust0 '· so' :n_so0 '· invoice' :n_inv0 '· job' :n_job0 '· txn' :n_txn0 '· realm' :realm '· since' :since0 '· HST ON →' :hst_qbo '· Net 60 →' :net60_qbo '· freight/discount =' :freight_qbo :discount_qbo
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
create function pg_temp.mgw(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"b2b2b2b2-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
create function pg_temp.wrk(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"b2b2b2b2-0000-4000-8000-000000000002"}'::jsonb, p_sql) $$;
create function pg_temp.nobody(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"b2b2b2b2-0000-4000-8000-000000000009"}'::jsonb, p_sql) $$;
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
-- 가짜 직원 셋
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('b2b2b2b2-0000-4000-8000-00000000000a', 'b2b2b2b2-0000-4000-8000-000000000001', 'qbo-sync-2b1-bk@asung.invalid', 'QBO 2b1 Bookkeeper', 'manager', '["qbo", "sales:read"]'),
  ('b2b2b2b2-0000-4000-8000-00000000000b', 'b2b2b2b2-0000-4000-8000-000000000002', 'qbo-sync-2b1-worker@asung.invalid', 'QBO 2b1 Worker', 'worker', '["picking"]');
-- 가짜 손님 — 매장 A(짝 있음 · 이메일) · 매장 B(짝 있음) · 부모 P(짝 없음) · 자식 C(부모 P · 짝 없음)
insert into public.customer (id, name, is_active, source, currency_code, payment_term_id, payment_term_name, tax_rule) values
  ('c2b00000-0000-4000-8000-00000000000a', 'QBO2B Store A', true, 'manual', 'CAD', :'net60_id'::uuid, 'Net 60', 'HST ON (Sale)'),
  ('c2b00000-0000-4000-8000-00000000000b', 'QBO2B Store B', true, 'manual', 'CAD', null, null, null),
  ('c2b00000-0000-4000-8000-000000000010', 'QBO2B Parent', true, 'manual', 'CAD', null, null, null);
insert into public.customer (id, name, is_active, source, currency_code, parent_id, parent_source, default_bill_to_customer_id) values
  ('c2b00000-0000-4000-8000-000000000011', 'QBO2B Kid Store', true, 'manual', 'CAD', 'c2b00000-0000-4000-8000-000000000010', 'ims', 'c2b00000-0000-4000-8000-000000000010');
insert into public.customer_contact (customer_id, name, email, is_default, is_active, source) values ('c2b00000-0000-4000-8000-00000000000a', 'AP', 'ap-2b@asung.invalid', true, true, 'manual');
insert into public.customer_address (customer_id, type, is_default_for_type, line1, city, state_province, postal_code, country, source) values ('c2b00000-0000-4000-8000-000000000010', 'Billing', true, '9 Parent Rd', 'Toronto', 'ON', 'M2M 2M2', 'CA', 'manual');
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values
  (:'realm', 'customer', 'c2b00000-0000-4000-8000-00000000000a', 'Customer', 'C-2B-A', 'manual', 'QBO2B Store A'),
  (:'realm', 'customer', 'c2b00000-0000-4000-8000-00000000000b', 'Customer', 'C-2B-B', 'manual', 'QBO2B Store B');
-- 가짜 제품 셋 — 1 짝 있음 · 2 짝 없음(처음 팔 때 Item) · 3 짝 없음 + 같은 Sku 의 비활성 Item 만(941)
insert into public.product (id, name, sku, is_active, source, sellable, revenue_account_code) values
  ('d2b00000-0000-4000-8000-000000000001', 'QBO2B Widget Blue', 'QBO2B-001', true, 'manual', true, '_98_'),
  ('d2b00000-0000-4000-8000-000000000002', 'QBO2B Widget Red', 'QBO2B-002', true, 'manual', true, '_98_'),
  ('d2b00000-0000-4000-8000-000000000003', 'QBO2B Widget Gone', 'QBO2B-003', true, 'manual', true, '_98_');
insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, active) values (:'realm', 'Item', 'I-2B-1', 'QBO2B Widget Blue', 'QBO2B-001', true), (:'realm', 'Item', 'I-2B-INACT', 'QBO2B Widget Gone', 'QBO2B-003', false);
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values (:'realm', 'product', 'd2b00000-0000-4000-8000-000000000001', 'Item', 'I-2B-1', 'manual', 'QBO2B Widget Blue');
-- 가짜 SO 둘(INV1 손으로 · draft 로 넣는다 — 몸은 so 의 ref · tracking · shipped_at 만 읽는다) · 줄 · 비용 — 나머지 인보이스의 SO 는 mk_inv 가 만든다(한 SO 는 살아 있는 인보이스 하나 · so_invoice_order_active_uq)
insert into public.so (id, so_number, customer_id, bill_to_customer_id, channel, intake, currency_id, currency_code, order_date, ref, tracking_number, shipped_at, ship_to_company, ship_to_line1, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country) values
  ('e2b00000-0000-4000-8000-000000000001', 'SO-99901', 'c2b00000-0000-4000-8000-00000000000a', 'c2b00000-0000-4000-8000-00000000000a', 'pos', 'manual', :'cad_id'::uuid, 'CAD', '2026-11-02', 'PO-1', 'TRK1', '2026-11-02 15:00+00', 'QBO2B Store A', '1 Store St', 'Toronto', 'ON', 'M1M 1M1', 'CA'),
  ('e2b00000-0000-4000-8000-000000000002', 'SO-99902', 'c2b00000-0000-4000-8000-00000000000a', 'c2b00000-0000-4000-8000-00000000000a', 'pos', 'manual', :'cad_id'::uuid, 'CAD', '2026-11-02', null, null, '2026-11-02 16:00+00', 'QBO2B Store A', '2 Other St', 'Toronto', 'ON', 'M1M 1M1', 'CA');
insert into public.so_line (id, so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, list_price, discount_pct, discount_source, unit_price) values
  ('f2b00000-0000-4000-8000-000000000001', 'e2b00000-0000-4000-8000-000000000001', 1, 'd2b00000-0000-4000-8000-000000000001', 'QBO2B-001', 'QBO2B Widget Blue', 1, 20, 20, 2, 10, 'customer', 1.8),
  ('f2b00000-0000-4000-8000-000000000002', 'e2b00000-0000-4000-8000-000000000001', 2, 'd2b00000-0000-4000-8000-000000000002', 'QBO2B-002', 'QBO2B Widget Red', 1, 2, 2, null, null, null, 24.635);
insert into public.so_charge (id, so_id, line_no, name, amount, account_id, account_code, discount_pct, discount_amount) values
  ('a2b00000-0000-4000-8000-000000000001', 'e2b00000-0000-4000-8000-000000000001', 1, 'Standard', 10, :'a99'::uuid, '_99_', 50, null),
  ('a2b00000-0000-4000-8000-000000000002', 'e2b00000-0000-4000-8000-000000000001', 2, 'Card fee', 3, :'a20'::uuid, '_20_', null, null);
-- 인보이스 — 번호 명시(시퀀스 무접촉) · 합계는 CHECK 를 만족하게 손으로
-- INV1 매장 A · S1 + S2 · 줄 6(제품 2 · 운임 · 운임 할인 · 카드 수수료 · 오더 할인) — S1 몫: lines 85.27 · od −3.60 · charges 13 · chd 5 · taxable 89.67 · tax 11.66 · total 101.33 · S2 몫 0
insert into public.so_invoice (id, invoice_number, kind, status, bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country, issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code,
                               lines_amount, order_discount_amount, charges_amount, charges_discount_amount, surcharge_amount, taxable_amount, tax_amount, total, amount_due) values
  ('12b00000-0000-4000-8000-000000000001', '9990001', 'sale', 'issued', 'c2b00000-0000-4000-8000-00000000000a', 'QBO2B Store A', '1 Store St', 'Toronto', 'ON', 'M1M 1M1', 'CA', '2026-11-02', 'b2b2b2b2-0000-4000-8000-00000000000a', :'net60_id'::uuid, 'Net 60', '2027-01-01', :'cad_id'::uuid, 'CAD',
   85.27, -3.60, 13, 5, 0, 89.67, 11.66, 101.33, 101.33);
insert into public.so_invoice_order (id, invoice_id, so_id, so_number, customer_id, ship_to_company, ship_to_line1, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country, tax_rule_id, tax_rule, rate_pct, tax_source, lines_amount, order_discount_pct, order_discount_amount, charges_amount, charges_discount_amount, surcharge_amount, taxable_amount, tax_amount, total) values
  ('22b00000-0000-4000-8000-000000000001', '12b00000-0000-4000-8000-000000000001', 'e2b00000-0000-4000-8000-000000000001', 'SO-99901', 'c2b00000-0000-4000-8000-00000000000a', 'QBO2B Store A', '1 Store St', 'Toronto', 'ON', 'M1M 1M1', 'CA', :'hst_id'::uuid, 'HST ON (Sale)', 13, 'ship_to', 85.27, 4, -3.60, 13, 5, 0, 89.67, 11.66, 101.33),
  ('22b00000-0000-4000-8000-000000000002', '12b00000-0000-4000-8000-000000000001', 'e2b00000-0000-4000-8000-000000000002', 'SO-99902', 'c2b00000-0000-4000-8000-00000000000a', 'QBO2B Store A', '2 Other St', 'Toronto', 'ON', 'M1M 1M1', 'CA', :'hst_id'::uuid, 'HST ON (Sale)', 13, 'ship_to', 0, null, 0, 0, 0, 0, 0, 0, 0);
insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, so_charge_id, sku, description, unit, pack_factor, qty, list_price, discount_pct, discount_source, unit_price, amount, tax_amount, account_id, account_code) values
  ('12b00000-0000-4000-8000-000000000001', '22b00000-0000-4000-8000-000000000001', 1, 'product', 'f2b00000-0000-4000-8000-000000000001', null, 'QBO2B-001', 'QBO2B Widget Blue', 'ea', 1, 20, 2, 10, 'customer', 1.8, 36.00, 4.68, :'a98'::uuid, '_98_'),
  ('12b00000-0000-4000-8000-000000000001', '22b00000-0000-4000-8000-000000000001', 2, 'product', 'f2b00000-0000-4000-8000-000000000002', null, 'QBO2B-002', 'QBO2B Widget Red', 'ea', 1, 2, null, null, null, 24.635, 49.27, 6.41, :'a98'::uuid, '_98_'),
  ('12b00000-0000-4000-8000-000000000001', '22b00000-0000-4000-8000-000000000001', 3, 'order_discount', null, null, null, 'Order discount 4%', null, null, null, null, null, null, null, -3.60, -0.47, :'a98'::uuid, '_98_'),
  ('12b00000-0000-4000-8000-000000000001', '22b00000-0000-4000-8000-000000000001', 4, 'charge', null, 'a2b00000-0000-4000-8000-000000000001', null, 'Standard', null, null, null, null, null, null, null, 10, 1.30, :'a99'::uuid, '_99_'),
  ('12b00000-0000-4000-8000-000000000001', '22b00000-0000-4000-8000-000000000001', 5, 'charge_discount', null, 'a2b00000-0000-4000-8000-000000000001', null, 'Standard discount 50%', null, null, null, null, 50, null, null, -5, -0.65, :'a6'::uuid, '_6_'),
  ('12b00000-0000-4000-8000-000000000001', '22b00000-0000-4000-8000-000000000001', 6, 'charge', null, 'a2b00000-0000-4000-8000-000000000002', null, 'Card fee', null, null, null, null, null, null, null, 3, 0.39, :'a20'::uuid, '_20_');
-- INV2 자식 매장 C(짝 없음 · 부모도 없음) · S4 · 제품 1 — needs 손님 → 부모 먼저 · INV3 매장 둘(S1 + S3) · INV4 · INV5 매장 A 단순(취소 시험) · INV_OLD 11-01 발행(since 전) · INV_OPEN 이월
create temp sequence s_so start 99910;
create function pg_temp.mk_inv(p_id uuid, p_num text, p_kind text, p_bill uuid, p_bill_name text, p_on date, p_cust uuid[], p_product uuid, p_lines boolean) returns void language plpgsql as $$
declare i int; v_oid uuid; v_so uuid; v_sl uuid; v_num text; v_n int := coalesce(array_length(p_cust, 1), 0);
begin
  insert into public.so_invoice (id, invoice_number, kind, status, bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country, issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due, legacy_sale_id, legacy_invoice_id, store_customer_id)
  values (p_id, p_num, p_kind, 'issued', p_bill, p_bill_name, '1 Any St', 'Toronto', 'ON', 'M1M 1M1', 'CA', p_on, 'b2b2b2b2-0000-4000-8000-00000000000a', null, null, null, (select id from public.ref_currency where code = 'CAD'), 'CAD', 2 * v_n, 2 * v_n, 0.26 * v_n, 2.26 * v_n, 2.26 * v_n,
          case when p_kind = 'opening' then 'QBO2B-LS' end, case when p_kind = 'opening' then 'QBO2B-LI' end, case when p_kind = 'opening' then p_bill end);   -- so_invoice_opening_ck
  for i in 1 .. v_n loop
    v_so := gen_random_uuid(); v_sl := gen_random_uuid(); v_oid := gen_random_uuid(); v_num := 'SO-' || nextval('s_so')::text;
    insert into public.so (id, so_number, customer_id, bill_to_customer_id, channel, intake, currency_id, currency_code, order_date, ref, shipped_at, ship_to_company, ship_to_line1, ship_to_city, ship_to_country)
    values (v_so, v_num, p_cust[i], p_bill, 'pos', 'manual', (select id from public.ref_currency where code = 'CAD'), 'CAD', p_on, 'PO-' || v_num, p_on::timestamptz + interval '16 hours', 'Ship', '5 St', 'Toronto', 'CA');
    insert into public.so_line (id, so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, unit_price)
    values (v_sl, v_so, 1, p_product, (select sku from public.product where id = p_product), (select name from public.product where id = p_product), 1, 1, 1, 2);
    insert into public.so_invoice_order (id, invoice_id, so_id, so_number, customer_id, ship_to_company, ship_to_line1, ship_to_city, ship_to_country, tax_rule_id, tax_rule, rate_pct, tax_source, lines_amount, taxable_amount, tax_amount, total)
    values (v_oid, p_id, v_so, v_num, p_cust[i], 'Ship', '5 St', 'Toronto', 'CA', (select id from public.ref_tax_rule where name = 'HST ON (Sale)'), 'HST ON (Sale)', 13, 'ship_to', 2, 2, 0.26, 2.26);
    if p_lines then
      insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, qty, unit_price, amount, tax_amount, account_code)
      values (p_id, v_oid, i, 'product', v_sl, (select sku from public.product where id = p_product), (select name from public.product where id = p_product), 1, 2, 2, 0.26, '_98_');
    end if;
  end loop;
end $$;
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000002', '9990002', 'sale', 'c2b00000-0000-4000-8000-000000000010', 'QBO2B Parent', '2026-11-02', array['c2b00000-0000-4000-8000-000000000011'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000003', '9990003', 'sale', 'c2b00000-0000-4000-8000-00000000000a', 'QBO2B Store A', '2026-11-02', array['c2b00000-0000-4000-8000-00000000000a'::uuid, 'c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000004', '9990004', 'sale', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2B Store B', '2026-11-02', array['c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000005', '9990005', 'sale', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2B Store B', '2026-11-02', array['c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000006', '9990006', 'sale', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2B Store B', '2026-10-31', array['c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000003', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000007', '9990007', 'opening', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2B Store B', '2026-11-02', '{}'::uuid[], 'd2b00000-0000-4000-8000-000000000001', false);

-- ── A) 착지 · since ──
select pg_temp.chk('A1 칸 3(detail · mismatch · updated_by — 2a 의 qbo_txn UPDATE 결함) · 트리거 · 오버로드 · 1a 창구 grant 그대로(entity_upsert authenticated · ims_rows grant 0)',
  (select count(*)::text from information_schema.columns c where c.table_schema = 'public' and ((c.table_name = 'qbo_entity' and c.column_name = 'detail') or (c.table_name = 'qbo_txn' and c.column_name in ('mismatch', 'updated_by'))))
  || ' ' || (select count(*)::text from pg_trigger t where t.tgrelid = 'public.so_invoice'::regclass and t.tgname in ('so_invoice_qbo_job', 'so_invoice_qbo_cancel'))
  || ' ' || (select string_agg(p.proname || ':' || pg_get_function_identity_arguments(p.oid), ' | ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_job_claim', 'qbo_job_done'))
  || ' | ' || (select coalesce(p.proacl::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_entity_upsert') || ' ' || (select coalesce(p.proacl::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_ims_rows'),
  '3 2 qbo_job_claim:p_limit integer, p_kinds text[] | qbo_job_done:p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text, p_intuit_tid text, p_note text, p_sku text, p_total_amt numeric, p_total_tax numeric | {postgres=X/postgres,authenticated=X/postgres} {postgres=X/postgres}');
update public.inv_config set value = '' where key = 'qbo_send_since';
select public.qbo_send_since_ok('2026-11-02')::text as s_empty \gset
update public.inv_config set value = '2026-11-01' where key = 'qbo_send_since';
select pg_temp.chk('A2 qbo_send_since_ok — 비었으면 false · 11-01 부터: 10-31 f · 11-01 t · 11-02 t · null f', :'s_empty' || ' ' || public.qbo_send_since_ok('2026-10-31')::text || ' ' || public.qbo_send_since_ok('2026-11-01')::text || ' ' || public.qbo_send_since_ok('2026-11-02')::text || ' ' || public.qbo_send_since_ok(null)::text, 'false false true true false');
-- 발행 트리거 — DEFERRED 를 당겨 쏜다(since 는 11-01 · INV_OLD 10-31 · INV_OPEN 이월은 안 쌓인다)
set constraints all immediate;
select pg_temp.chk('A3 발행 트리거 — sale · since 뒤 5 장 queued(by_staff = issued_by · ims_kind invoice) · 10-31 발행 0 · 이월 0',
  (select count(*)::text || ' ' || string_agg(distinct j.state, ',') || ' ' || bool_and(j.by_staff = 'b2b2b2b2-0000-4000-8000-00000000000a' and j.ims_kind = 'invoice' and j.kind = 'invoice')::text from public.qbo_job j where j.ims_id like '12b00000%')
  || ' | ' || (select count(*)::text from public.qbo_job j where j.ims_id in ('12b00000-0000-4000-8000-000000000006', '12b00000-0000-4000-8000-000000000007')), '5 queued true | 0');
select pg_temp.chk('A4 ims_rows charge — acct:_20_ 행(비용 줄이 쓴 계정) · _99_ 없음 · 고정 넷 그대로 · qbo_link_set(북키퍼) acct:_20_ → Item 14735 manual',
  (select string_agg(r.ims_id || '=' || coalesce(r.ims_code, '-'), ' ' order by r.ims_id) from public.qbo_ims_rows('charge') r where r.ims_id in ('freight', 'discount', 'surcharge', 'freight_discount', 'acct:_20_', 'acct:_99_'))
  || ' | ' || (select (j->>'matched_by') || ' ' || (j->>'qbo_id') || ' ' || (j->>'ims_name') from (select pg_temp.mgw('select public.qbo_link_set(''charge'', ''acct:_20_'', ''14735'')::text')::jsonb j) x),
  'acct:_20_=_20_ discount=- freight=- freight_discount=- surcharge=- | manual 14735 Charge on account _20_ Bank Service Fees');

-- ── C) 인보이스 몸 ──
select pg_temp.chk('C1 몸 거부 — 이월 · 매장 둘 · 없는 id · void 몸(보낸 적 없음)',
  left(pg_temp.pg('select public.qbo_invoice_body(''12b00000-0000-4000-8000-000000000007'')::text'), 60) || ' | ' || left(pg_temp.pg('select public.qbo_invoice_body(''12b00000-0000-4000-8000-000000000003'')::text'), 76)
  || ' | ' || left(pg_temp.pg('select public.qbo_invoice_body(''12b00000-0000-4000-8000-0000000000ff'')::text'), 30) || ' | ' || left(pg_temp.pg('select public.qbo_void_body(''12b00000-0000-4000-8000-000000000001'')::text'), 60),
  'ERR P0001: Invoice 9990007 was carried forward from the prev | ERR P0001: Invoice 9990003 covers 2 stores — cancel and reissue per store (o | ERR P0001: No IMS invoice 12b0 | ERR P0001: Invoice 9990001 was never sent to QuickBooks — no');
update public.qbo_entity set detail = null where realm_id = :'realm' and qbo_type = 'TaxCode' and qbo_id = :'hst_qbo';
select left(pg_temp.pg('select public.qbo_invoice_body(''12b00000-0000-4000-8000-000000000001'')::text'), 70) as b_norate \gset
update public.qbo_entity set detail = '{"TaxRateDetail":[{"TaxRateRef":{"value":"12","name":"HST ON"},"TaxTypeApplicable":"TaxOnAmount","TaxOrder":0}]}'::jsonb where realm_id = :'realm' and qbo_type = 'TaxCode' and qbo_id = :'hst_qbo';
select pg_temp.pg('select public.qbo_invoice_body(''12b00000-0000-4000-8000-000000000001'')::text') as b1 \gset
select pg_temp.chk('C2 세금 — 거울 detail 없으면 「no tax rate on file」 · 채우면 TxnTaxDetail TotalTax 11.66 · TaxLine 1 · TaxRateRef 12 · 13 % · NetAmountTaxable 89.67 · Amount 11.66',
  :'b_norate' || ' | ' || (select (b->'TxnTaxDetail'->>'TotalTax') || ' ' || jsonb_array_length(b->'TxnTaxDetail'->'TaxLine')::text || ' ' || (t->'TaxLineDetail'->'TaxRateRef'->>'value') || ' ' || (t->'TaxLineDetail'->>'TaxPercent') || ' ' || (t->'TaxLineDetail'->>'NetAmountTaxable') || ' ' || (t->>'Amount') || ' ' || (t->'TaxLineDetail'->>'PercentBased')
                            from (select :'b1'::jsonb->'body' b) x, lateral (select b->'TxnTaxDetail'->'TaxLine'->0 t) y),
  'ERR P0001: QuickBooks tax code #6 ("HST ON (Sale)") has no tax rate on | 11.66 1 12 13 89.67 11.66 true');
select pg_temp.chk('C3 머리 — DocNumber · 날짜 · CustomerRef 매장(935) · Term 4 · CAD · BillAddr(Line1 이름 · Canada) · ShipAddr 첫 오더 · BillEmail · 메모 둘(939 · ref 없는 오더는 so_number) · ShipDate · TrackingNum · TaxExcluded',
  (select (b->>'DocNumber') || ' ' || (b->>'TxnDate') || ' ' || (b->>'DueDate') || ' ' || (b->'CustomerRef'->>'value') || ' ' || (b->'SalesTermRef'->>'value') || ' ' || (b->'CurrencyRef'->>'value') || ' | ' || (b->'BillAddr'->>'Line1') || ' · ' || (b->'BillAddr'->>'Line2') || ' · ' || (b->'BillAddr'->>'Country')
          || ' | ' || (b->'ShipAddr'->>'Line1') || ' · ' || (b->'ShipAddr'->>'Line2') || ' | ' || (b->'BillEmail'->>'Address') || ' | ' || (b->>'PrivateNote') || ' | ' || (b->'CustomerMemo'->>'value') || ' | ' || (b->>'ShipDate') || ' ' || (b->>'TrackingNum') || ' ' || (b->>'GlobalTaxCalculation')
   from (select :'b1'::jsonb->'body' b) x),
  '9990001 2026-11-02 2027-01-01 C-2B-A ' || :'net60_qbo' || ' CAD | QBO2B Store A · 1 Store St · Canada | QBO2B Store A · 1 Store St | ap-2b@asung.invalid | Customer Reference: PO-1, SO-99902 | Customer Reference: PO-1, SO-99902, QBO2B Store A | 2026-11-02 TRK1 TaxExcluded');
select pg_temp.chk('C4 줄 6 — 제품(ItemRef I-2B-1 · list/off 꼴 · Qty 20 · 1.8 · 36 · TaxCode 6) · 제품 2 짝 없음(ItemRef 없음 → needs item) · 오더 할인(2170 · −3.6) · 운임(Item 4 · Qty 1 · 10) · 운임 할인(Item 4 · −5 · 943) · 카드 수수료(14735 · 951) · needs 1 · line_count · totals',
  (select (l0->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (l0->>'Description') || ' ' || (l0->'SalesItemLineDetail'->>'Qty') || ' ' || (l0->'SalesItemLineDetail'->>'UnitPrice') || ' ' || (l0->>'Amount') || ' ' || (l0->'SalesItemLineDetail'->'TaxCodeRef'->>'value')
          || ' | ' || (l1->'SalesItemLineDetail' ? 'ItemRef')::text || ' ' || (l1->>'Amount') || ' | ' || (l2->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (l2->>'Amount') || ' ' || (l2->'SalesItemLineDetail'->>'UnitPrice')
          || ' | ' || (l3->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (l3->'SalesItemLineDetail'->>'Qty') || ' ' || (l3->'SalesItemLineDetail'->>'UnitPrice') || ' ' || (l3->>'Amount') || ' | ' || (l4->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (l4->>'Amount')
          || ' | ' || (l5->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (l5->>'Amount') || ' | ' || jsonb_array_length(j->'needs')::text || ' ' || (j->'needs'->0->>'kind') || ' ' || (j->'needs'->0->>'ims_id') || ' | ' || (j->>'line_count') || ' ' || (j->'totals'->>'total') || ' ' || (j->'totals'->>'tax')
   from (select :'b1'::jsonb j) x, lateral (select j->'body'->'Line'->0 l0, j->'body'->'Line'->1 l1, j->'body'->'Line'->2 l2, j->'body'->'Line'->3 l3, j->'body'->'Line'->4 l4, j->'body'->'Line'->5 l5) y),
  'I-2B-1 QBO2B Widget Blue (list 2, 10% off) 20 1.8 36.00 ' || :'hst_qbo' || ' | false 49.27 | ' || :'discount_qbo' || ' -3.60 -3.6 | ' || :'freight_qbo' || ' 1 10 10 | ' || :'freight_qbo' || ' -5 | 14735 3 | 1 item d2b00000-0000-4000-8000-000000000002 | 6 101.33 11.66');
select pg_temp.chk('C5 경고 — ship-to 가 오더마다 다르다(첫 오더) · 짝 없는 계정 비용 줄은 거부 + 안내(951) — 짝을 풀고 본다',
  (select string_agg(w, ' · ') from jsonb_array_elements_text(:'b1'::jsonb->'warnings') w)
  || ' | ' || (select coalesce(pg_temp.pg('delete from public.qbo_link where ims_kind = ''charge'' and ims_id = ''acct:_20_'' returning ims_id'), '')) || left(pg_temp.pg('select public.qbo_invoice_body(''12b00000-0000-4000-8000-000000000001'')::text'), 118),
  'ship-to differs between orders — first order (SO-99901) used | acct:_20_ERR P0001: Charge "Card fee" on account _20_ has no QuickBooks item — link account item "acct:_20_" to a QuickBooks it');
select pg_temp.mgw('select public.qbo_link_set(''charge'', ''acct:_20_'', ''14735'')::text') as relink \gset

-- ── D) claim · needs · done · 취소 · void ──
select pg_temp.svc('select public.qbo_job_claim(10)::text') as cl0 \gset
select pg_temp.chk('D1 claim 기본 kinds(customer · item) — invoice 일감은 잡지 않는다(2a′ EF 가드) · kinds 밖 거부', (:'cl0'::jsonb->>'claimed') || ' ' || (:'cl0'::jsonb->'kinds')::text || ' | ' || left(pg_temp.svc('select public.qbo_job_claim(10, array[''bogus''])::text'), 48),
  '0 ["customer", "item"] | ERR P0001: kinds must be among customer, item, i');
select pg_temp.svc('select public.qbo_job_claim(10, array[''customer'', ''item'', ''invoice'', ''invoice_void''])::text') as cl1 \gset
select pg_temp.chk('D2 claim 전부 — 5 잡음 · INV1 · INV2 는 needs 로 blocked(2) · INV3 failed(매장 둘) · INV4 · INV5 몸 OK(jobs 2) · need 일감: item 제품 2 queued · 손님 C blocked(부모 P queued)',
  (:'cl1'::jsonb->>'claimed') || ' ' || (:'cl1'::jsonb->>'blocked_for_needs') || ' ' || (:'cl1'::jsonb->>'body_failed') || ' ' || jsonb_array_length(:'cl1'::jsonb->'jobs')::text || ' ' || (:'cl1'::jsonb->'jobs'->0->>'kind') || ' ' || (:'cl1'::jsonb->'jobs'->0->>'doc_number')
  || ' | ' || (select string_agg(right(j.ims_id, 1) || ':' || j.state, ' ' order by j.ims_id) from public.qbo_job j where j.ims_id like '12b00000%' and j.kind = 'invoice')
  || ' | ' || (select string_agg(j.kind || ':' || j.state || ':' || (j.blocked_by is not null)::text, ' ' order by j.kind, j.ims_id) from public.qbo_job j where j.ims_id in ('d2b00000-0000-4000-8000-000000000002', 'c2b00000-0000-4000-8000-000000000010', 'c2b00000-0000-4000-8000-000000000011'))
  || ' | ' || (select left(j.last_error, 40) from public.qbo_job j where j.ims_id = '12b00000-0000-4000-8000-000000000003') || ' | ' || (select (j.warning like '%waiting for 1 QuickBooks record(s) to be created first')::text from public.qbo_job j where j.ims_id = '12b00000-0000-4000-8000-000000000002'),
  '5 2 1 2 invoice 9990004 | 1:blocked 2:blocked 3:failed 4:sending 5:sending | customer:queued:false customer:blocked:true item:queued:false | Invoice 9990003 covers 2 stores — cancel | true');
select pg_temp.chk('D3 blocked 인보이스의 blocked_by = need 일감 · INV1 → item 제품 2 · INV2 → 손님 C',
  (select (j.blocked_by = (select n.id from public.qbo_job n where n.ims_id = 'd2b00000-0000-4000-8000-000000000002'))::text from public.qbo_job j where j.ims_id = '12b00000-0000-4000-8000-000000000001')
  || ' ' || (select (j.blocked_by = (select n.id from public.qbo_job n where n.ims_id = 'c2b00000-0000-4000-8000-000000000011'))::text from public.qbo_job j where j.ims_id = '12b00000-0000-4000-8000-000000000002'), 'true true');
-- need 들을 보낸 셈 친다: 제품 2 · 부모 P → done · 그다음 claim 이 ② 로 INV1 · 손님 C 를 풀어 잡는다
select pg_temp.svc('select public.qbo_job_claim(10, array[''customer'', ''item'', ''invoice'', ''invoice_void''])::text') as cl2 \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''I-2B-2'', ''QBO2B Widget Red'', ''0'', ''tid-i2'', null, ''QBO2B-002'')::text', (select id from public.qbo_job where ims_id = 'd2b00000-0000-4000-8000-000000000002'))) as d_i2 \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''C-2B-P'', ''QBO2B Parent'', ''0'')::text', (select id from public.qbo_job where ims_id = 'c2b00000-0000-4000-8000-000000000010'))) as d_p \gset
select pg_temp.svc('select public.qbo_job_claim(10, array[''customer'', ''item'', ''invoice'', ''invoice_void''])::text') as cl3 \gset
select pg_temp.chk('D4 need 둘 보냄(claim 2 · done 이 자식을 바로 푼다 → ② 는 0) → claim: 손님 C 몸(ParentRef C-2B-P) + INV1 몸(줄 2 ItemRef I-2B-2 · needs 없음) · INV2 는 아직 blocked(자식 C 미전송)',
  (:'cl2'::jsonb->>'claimed') || ' ' || (:'d_i2'::jsonb->>'state') || (:'d_p'::jsonb->>'unblocked') || ' | ' || (:'cl3'::jsonb->>'unblocked') || ' ' || (:'cl3'::jsonb->>'claimed') || ' ' || (:'cl3'::jsonb->>'blocked_for_needs')
  || ' | ' || (select string_agg((j->>'kind') || ':' || coalesce(j->'body'->'ParentRef'->>'value', j->'body'->'Line'->1->'SalesItemLineDetail'->'ItemRef'->>'value'), ' ' order by j->>'kind') from jsonb_array_elements(:'cl3'::jsonb->'jobs') j)
  || ' | ' || (select j.state from public.qbo_job j where j.ims_id = '12b00000-0000-4000-8000-000000000002'), '2 sent1 | 0 2 0 | customer:C-2B-P invoice:I-2B-2 | blocked');
select pg_temp.svc(format('select public.qbo_job_done(%L, ''INV-2B-1'', ''9990001'', ''3'', ''tid-inv1'', null, null, 101.33, 11.66)::text', (select id from public.qbo_job where ims_id = '12b00000-0000-4000-8000-000000000001'))) as d1 \gset
select pg_temp.chk('D5 done INV1(합계 같음) → sent · mismatch null · qbo_txn(Invoice INV-2B-1 · doc_number · sync_token 3 · 합계 · job_id) · 일감 qbo_name = DocNumber · warning 에 mismatch 없음',
  (:'d1'::jsonb->>'state') || ' ' || coalesce(:'d1'::jsonb->>'mismatch', 'null') || ' | ' || (select t.qbo_type || ' ' || t.qbo_id || ' ' || t.doc_number || ' ' || t.sync_token || ' ' || t.total_amt || ' ' || t.total_tax || ' ' || coalesce(t.mismatch, 'null') || ' ' || (t.job_id = (select id from public.qbo_job where ims_id = t.ims_id and kind = 'invoice'))::text || ' ' || (t.voided_at is null)::text from public.qbo_txn t where t.ims_id = '12b00000-0000-4000-8000-000000000001')
  || ' | ' || (select j.qbo_name || ' ' || coalesce(j.warning, 'null') from public.qbo_job j where j.ims_id = '12b00000-0000-4000-8000-000000000001' and j.kind = 'invoice'), 'sent null | Invoice INV-2B-1 9990001 3 101.33 11.66 null true true | 9990001 ship-to differs between orders — first order (SO-99901) used');
select pg_temp.svc(format('select public.qbo_job_done(%L, ''INV-2B-4'', ''9990004'', ''0'', ''tid-inv4'', null, null, 2.25, 0.25)::text', (select id from public.qbo_job where ims_id = '12b00000-0000-4000-8000-000000000004'))) as d4 \gset
select pg_temp.chk('D6 done INV4(합계 다름 942) → sent 그대로 · mismatch 글 · qbo_txn.mismatch · 일감 warning 에 덧붙음', (:'d4'::jsonb->>'state') || ' | ' || (:'d4'::jsonb->>'mismatch') || ' | ' || (select left(t.mismatch, 30) || ' ' || (j.warning like '%' || t.mismatch)::text from public.qbo_txn t join public.qbo_job j on j.id = t.job_id where t.ims_id = '12b00000-0000-4000-8000-000000000004'),
  'sent | QuickBooks total 2.25 / tax 0.25 differs from IMS 2.26 / 0.26 — check invoice 9990004 in QuickBooks (942) | QuickBooks total 2.25 / tax 0. true');
-- 취소 셋 — INV1(sent → void queued) · INV5(sending → void blocked_by) · 새 INV8(queued → skipped)
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000008', '9990008', 'sale', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2B Store B', '2026-11-02', array['c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
set constraints all immediate;
update public.so_invoice set status = 'cancelled', cancelled_at = now(), cancelled_by = 'b2b2b2b2-0000-4000-8000-00000000000a', cancel_note = 'wrong qty' where id in ('12b00000-0000-4000-8000-000000000001', '12b00000-0000-4000-8000-000000000005', '12b00000-0000-4000-8000-000000000008');
select pg_temp.chk('D7 취소 트리거 — INV1(보내짐) → invoice_void queued(note) · INV5(sending) → invoice_void blocked_by 그 일감 · INV8(queued) → skipped(note) · void 일감 0 · 이월 취소는 so_invoice_cancel 이 막고 트리거도 kind 로 거른다',
  (select string_agg(right(j.ims_id, 1) || ':' || j.kind || ':' || j.state || ':' || coalesce(left(j.note, 24), '-'), ' ' order by j.ims_id, j.kind) from public.qbo_job j where j.ims_id in ('12b00000-0000-4000-8000-000000000001', '12b00000-0000-4000-8000-000000000005', '12b00000-0000-4000-8000-000000000008'))
  || ' | ' || (select (v.blocked_by = i.id)::text from public.qbo_job v join public.qbo_job i on i.ims_id = v.ims_id and i.kind = 'invoice' where v.kind = 'invoice_void' and v.ims_id = '12b00000-0000-4000-8000-000000000005'),
  '1:invoice:sent:- 1:invoice_void:queued:cancelled: wrong qty 5:invoice:sending:- 5:invoice_void:blocked:cancelled while sending: 8:invoice:skipped:cancelled before sending | true');
select pg_temp.svc('select public.qbo_job_claim(10, array[''customer'', ''item'', ''invoice'', ''invoice_void''])::text') as cl4 \gset
select pg_temp.chk('D8 claim → INV1 void 몸(Id INV-2B-1 · SyncToken 3 · doc_number · qbo_id) · 손님 C 는 sending 중이라 없음 · INV5 void 는 blocked 그대로',
  (select (j->>'kind') || ' ' || (j->'body'->>'Id') || ' ' || (j->'body'->>'SyncToken') || ' ' || (j->>'doc_number') || ' ' || (j->>'qbo_id') || ' ' || (j->>'name') from jsonb_array_elements(:'cl4'::jsonb->'jobs') j where j->>'kind' = 'invoice_void')
  || ' | ' || (:'cl4'::jsonb->>'claimed') || ' ' || (select j.state from public.qbo_job j where j.kind = 'invoice_void' and j.ims_id = '12b00000-0000-4000-8000-000000000005'), 'invoice_void INV-2B-1 3 9990001 INV-2B-1 9990001 | 1 blocked');
select pg_temp.svc(format('select public.qbo_job_done(%L, ''INV-2B-1'', ''9990001'', ''4'', ''tid-void1'')::text', (select id from public.qbo_job where ims_id = '12b00000-0000-4000-8000-000000000001' and kind = 'invoice_void'))) as dv1 \gset
select pg_temp.chk('D9 done void → sent · qbo_txn.voided_at · sync_token 4 · void 몸 다시 → 「already voided」', (:'dv1'::jsonb->>'state') || ' ' || (select (t.voided_at is not null)::text || ' ' || t.sync_token from public.qbo_txn t where t.ims_id = '12b00000-0000-4000-8000-000000000001')
  || ' | ' || left(pg_temp.pg('select public.qbo_void_body(''12b00000-0000-4000-8000-000000000001'')::text'), 62), 'sent true 4 | ERR P0001: Invoice 9990001 (QuickBooks #INV-2B-1) is already v');
-- INV5: sending 중 취소 → done 되면 void 가 풀린다 · 같은 QBO Id 를 다른 인보이스에 → failed
select pg_temp.svc(format('select public.qbo_job_done(%L, ''INV-2B-4'', ''9990005'', ''0'', ''tid-inv5'', null, null, 2.26, 0.26)::text', (select id from public.qbo_job where ims_id = '12b00000-0000-4000-8000-000000000005' and kind = 'invoice'))) as d5dup \gset
select pg_temp.mgw(format('select public.qbo_job_retry(%L)::text', (select id from public.qbo_job where ims_id = '12b00000-0000-4000-8000-000000000005' and kind = 'invoice'))) as r5 \gset
select pg_temp.svc('select public.qbo_job_claim(10, array[''invoice''])::text') as cl5 \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''INV-2B-5'', ''9990005'', ''0'', ''tid-inv5b'', null, null, 2.26, 0.26)::text', (select id from public.qbo_job where ims_id = '12b00000-0000-4000-8000-000000000005' and kind = 'invoice'))) as d5 \gset
select pg_temp.chk('D10 done INV5 with INV4 의 QBO Id → failed + link_error(사람 말) · retry → queued · claim(invoice 만 · 취소된 인보이스는 몸이 거부 → failed) — 취소 뒤 재전송은 없다',
  (:'d5dup'::jsonb->>'state') || ' ' || left(:'d5dup'::jsonb->>'link_error', 44) || ' | ' || (:'r5'::jsonb->>'state') || ' | ' || (:'cl5'::jsonb->>'claimed') || ' ' || (:'cl5'::jsonb->>'body_failed') || ' | ' || left(:'d5', 40)
  || ' | ' || (select j.state || ' ' || left(j.last_error, 36) from public.qbo_job j where j.ims_id = '12b00000-0000-4000-8000-000000000005' and j.kind = 'invoice'),
  'failed QuickBooks Invoice #INV-2B-4 is already reco | queued | 1 1 | ERR P0001: Only a job being sent, or one | failed Invoice 9990005 is cancelled — only ');
select pg_temp.chk('D11 list(북키퍼 · open) — INV2 blocked 행 ims_name(번호 · 청구처 · 통화 총액) · INV4 sent 행 txn 칸(qbo_id · mismatch) · INV1 txn_voided_at · worker 거부',
  (select (r->>'ims_name') || ' | ' || (r->>'state') from jsonb_array_elements(pg_temp.mgw('select public.qbo_job_list(''blocked'')::text')::jsonb->'rows') r where r->>'ims_id' = '12b00000-0000-4000-8000-000000000002')
  || ' | ' || (select (r->>'txn_qbo_id') || ' ' || left(r->>'txn_mismatch', 16) || ' ' || (r->>'txn_voided_at' is null)::text from jsonb_array_elements(pg_temp.mgw('select public.qbo_job_list(''sent'')::text')::jsonb->'rows') r where r->>'ims_id' = '12b00000-0000-4000-8000-000000000004')
  || ' | ' || (select (r->>'txn_voided_at' is not null)::text from jsonb_array_elements(pg_temp.mgw('select public.qbo_job_list(''sent'')::text')::jsonb->'rows') r where r->>'ims_id' = '12b00000-0000-4000-8000-000000000001' and r->>'kind' = 'invoice')
  || ' | ' || left(pg_temp.wrk('select public.qbo_job_list()::text'), 10), '9990002 · QBO2B Parent · CAD 2.26 | blocked | INV-2B-4 QuickBooks total true | true | ERR P0001:');
select pg_temp.chk('D12 qbo_txn_of — worker 도 읽는다(INV4: qbo_id · mismatch · job_state) · INV1 voided · 일감만 있는 INV2(txn null · job blocked) · 없는 id null · kind 밖 거부 · 등록 없음 거부',
  (select (j->>'qbo_id') || ' ' || left(j->>'mismatch', 10) || ' ' || (j->>'job_state') from (select pg_temp.wrk('select public.qbo_txn_of(''invoice'', ''12b00000-0000-4000-8000-000000000004'')::text')::jsonb j) x)
  || ' | ' || (select (j->>'voided_at' is not null)::text || ' ' || (j->>'job_kind') from (select pg_temp.wrk('select public.qbo_txn_of(''invoice'', ''12b00000-0000-4000-8000-000000000001'')::text')::jsonb j) x)
  || ' | ' || (select coalesce(j->>'qbo_id', 'null') || ' ' || (j->>'job_state') from (select pg_temp.wrk('select public.qbo_txn_of(''invoice'', ''12b00000-0000-4000-8000-000000000002'')::text')::jsonb j) x)
  || ' | ' || pg_temp.wrk('select public.qbo_txn_of(''invoice'', ''nope'')::text') || ' | ' || left(pg_temp.wrk('select public.qbo_txn_of(''bogus'', ''x'')::text'), 40) || ' | ' || left(pg_temp.nobody('select public.qbo_txn_of(''invoice'', ''x'')::text'), 44),
  'INV-2B-4 QuickBooks sent | true invoice_void | null blocked | (null) | ERR P0001: kind must be invoice or credi | ERR P0001: You are not registered as active ');
select pg_temp.pg(format('insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, by_staff) values (%L, ''invoice'', ''invoice'', ''12b00000-0000-4000-8000-000000000006'', ''b2b2b2b2-0000-4000-8000-00000000000a'') returning state', :'realm')) as ins13 \gset
select pg_temp.svc('select public.qbo_job_claim(10, array[''invoice''])::text') as cl13 \gset
select pg_temp.chk('D13 open_or_add — 941 비활성 Item 만 있는 제품 3 의 인보이스(INV_OLD 를 손으로 큐) → claim 이 need 몸 거부로 failed + 그 까닭 · need 일감은 안 생긴다 · qbo_job_add(열쇠) 는 kind 검사 그대로',
  :'ins13' || ' ' || (:'cl13'::jsonb->>'claimed') || ' ' || (:'cl13'::jsonb->>'body_failed') || ' | ' || (select left(j.last_error, 62) from public.qbo_job j where j.ims_id = '12b00000-0000-4000-8000-000000000006')
  || ' | ' || (select count(*)::text from public.qbo_job j where j.ims_id = 'd2b00000-0000-4000-8000-000000000003') || ' | ' || left(pg_temp.mgw('select public.qbo_job_add(''invoice'', ''x'')::text'), 50),
  'queued 1 1 | QuickBooks item is inactive — Item #I-2B-INACT QBO2B Widget Go | 0 | ERR P0001: kind must be customer or item (invoice ');
select pg_temp.mgw(format('select public.qbo_pull_begin(%L, ''TaxCode'', true)::text', :'realm')) as pb14 \gset
select pg_temp.mgw(format('select public.qbo_entity_upsert(%L, ''TaxCode'', %L::jsonb, null)::text', :'realm', '[{"Id":"TC-2B","Name":"QBO2B Tax","Active":true,"SyncToken":"0","SalesTaxRateList":{"TaxRateDetail":[{"TaxRateRef":{"value":"R-2B"},"TaxTypeApplicable":"TaxOnAmount","TaxOrder":0}]}},{"Id":"TC-2B-2","Name":"QBO2B Tax Two","Active":true,"SyncToken":"0"}]')) as up14a \gset
select (select coalesce(e.detail->'TaxRateDetail'->0->'TaxRateRef'->>'value', 'null') from public.qbo_entity e where e.qbo_type = 'TaxCode' and e.qbo_id = 'TC-2B') || ' ' || (select coalesce(e.detail::text, 'null') from public.qbo_entity e where e.qbo_type = 'TaxCode' and e.qbo_id = 'TC-2B-2') as mid14 \gset
select pg_temp.mgw(format('select public.qbo_entity_upsert(%L, ''TaxCode'', %L::jsonb, null)::text', :'realm', '[{"Id":"TC-2B","Name":"QBO2B Tax renamed","Active":true,"SyncToken":"1"}]')) as up14b \gset
select pg_temp.chk('D14 entity_upsert — TaxCode 행의 SalesTaxRateList 가 detail 로 · 없으면 null · 다시 보낼 때 없으면 옛 값 유지 · Item 은 detail 없음',
  (:'pb14'::jsonb->>'qbo_type') || ' ' || (:'up14a'::jsonb->>'received_now') || ' | ' || :'mid14' || ' | ' || (:'up14b'::jsonb->>'received_now') || ' ' || (select e.name || ' ' || coalesce(e.detail->'TaxRateDetail'->0->'TaxRateRef'->>'value', 'null') from public.qbo_entity e where e.qbo_type = 'TaxCode' and e.qbo_id = 'TC-2B')
  || ' | ' || (select (e.detail is null)::text from public.qbo_entity e where e.qbo_type = 'Item' and e.qbo_id = 'I-2B-2'), 'TaxCode 2 | R-2B null | 1 QBO2B Tax renamed R-2B | true');
select pg_temp.chk('D15 표 제약 — 열린 invoice_void 둘 23505 · kind invoice + ims_kind product 23514',
  left(pg_temp.pg(format('insert into public.qbo_job (realm_id, kind, ims_kind, ims_id) values (%L, ''invoice_void'', ''invoice'', ''12b00000-0000-4000-8000-000000000005'') returning id::text', :'realm')), 9)
  || ' ' || left(pg_temp.pg(format('insert into public.qbo_job (realm_id, kind, ims_kind, ims_id) values (%L, ''invoice'', ''product'', ''x'') returning id::text', :'realm')), 9), 'ERR 23505 ERR 23514');

-- ── L) REST 두 겹 ① — 새 · 재발행 함수의 update · delete 는 전부 깊이 0 WHERE · 다른 qbo_* 함수 md5 무변 ──
select pg_temp.chk('L1 nowhere 스캐너 = 0(새 7 + 재발행 6)', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('qbo_send_since_ok', 'qbo_invoice_body', 'qbo_void_body', 'qbo_job_open_or_add', 'qbo_job_on_invoice_issue', 'qbo_job_on_invoice_cancel', 'qbo_txn_of', 'qbo_entity_upsert', 'qbo_ims_rows', 'qbo_job_add', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_list')),
  'qbo_entity_upsert=0 qbo_ims_rows=0 qbo_invoice_body=0 qbo_job_add=0 qbo_job_claim=0 qbo_job_done=0 qbo_job_list=0 qbo_job_on_invoice_cancel=0 qbo_job_on_invoice_issue=0 qbo_job_open_or_add=0 qbo_send_since_ok=0 qbo_txn_of=0 qbo_void_body=0');
\if :{?mig}
select pg_temp.chk('L2 기존 qbo_* 함수 md5 — 재발행 6(entity_upsert · ims_rows · job_add · job_claim · job_done · job_list) 빼고 전부 begin 앞과 같다', (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5)
  || ' ' || (select string_agg(t.proname, ' ' order by t.proname) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5), (:n_fn - 6)::text || ' qbo_entity_upsert qbo_ims_rows qbo_job_add qbo_job_claim qbo_job_done qbo_job_list');
\endif
select pg_temp.chk('L3 scanner 자기 시험', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('update t set a = 1 from p where t.id = p.id;')::text, '10110');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.ims_staff where email like 'qbo-sync-2b1-%') = 0 as fake_staff_gone,
       (select count(*) from public.customer) = :n_cust0 as customer_same, (select count(*) from public.product) = :n_prod0 as product_same, (select count(*) from public.so) = :n_so0 as so_same,
       (select count(*) from public.so_invoice) = :n_inv0 as invoice_same, (select count(*) from public.qbo_job) = :n_job0 as job_same, (select count(*) from public.qbo_txn) = :n_txn0 as txn_same,
       (select count(*) from public.qbo_link) = :n_link0 as link_same, (select count(*) from public.qbo_entity) = :n_ent0 as entity_same,
       (select coalesce(value, '') from public.inv_config where key = 'qbo_send_since') = :'since0' as since_same,
       (select coalesce(to_jsonb(e)->>'detail', '') from public.qbo_entity e where e.qbo_type = 'TaxCode' and e.qbo_id = '6') = coalesce(:'tc6_detail0', '') as tc6_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
\if :{?mig}
select (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'qbo_txn' and c.column_name = 'mismatch') = 0 as column_gone_as_expected, (select count(*) from pg_trigger where tgname = 'so_invoice_qbo_job') = 0 as trigger_gone_as_expected;
\else
select (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'qbo_txn' and c.column_name = 'mismatch') = 1 as column_present, (select count(*) from pg_trigger where tgname = 'so_invoice_qbo_job') = 1 as trigger_present;
\endif
