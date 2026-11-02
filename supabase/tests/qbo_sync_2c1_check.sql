-- supabase/tests/qbo_sync_2c1_check.sql — qbo-sync-2c1 검증: 959 · 968 인보이스 취소 거부 · 966 세금 줄 거부 · 크레딧 몸 · 발행 · 취소 트리거 · 채우기(965) · 960 기다림 · 961 짝 · claim · done(CreditMemo · 942) · void · list · txn_of · ims_rows (2026-11-02 · 판정 959 ~ 966 · 968)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback → 실제 행 무변 · ⚠️ begin ~ rollback 10 초 안(메인 DB · 11-02 오전 잠금 사고)
--   Claude Code(시험): MIG=supabase/migrations/20261102130000_qbo_sync_2c1_credit_jobs.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2c1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 두 갈래의 차이는 G0(시험만) · L2(시험만 · 적용 앞 지문) · 기대 OK 수는 아래 EXPECT_OK
--   쓰기: 2b1 장치 그대로(가짜 직원 · 손님 4 · 제품 3 · SO · 인보이스 10) + 가짜 크레딧 8(번호 CR-999xx 명시 · 시퀀스 무접촉) · 결제 1 · 전부 rollback
--   ⚠️ 발행 트리거는 DEFERRED — 시험은 `set constraints all immediate` 로 당겨 쏜다 · so_invoice_cancel 은 fulfilled 오더가 필요해 pg_temp.fulfill 이 상태 짝을 걸어 올린다(draft → confirmed → shipped(pos) → fulfilled)
--   REST 두 겹: ① L1 nowhere 스캐너(새 · 재발행 함수의 update · delete 깊이 0 WHERE) ② 배포 뒤 북키퍼 열쇠로 Settings → QuickBooks 의 일감 목록 한 번(Caleb)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 22
\else
\set EXPECT_OK 21
\endif
\pset pager off
\set svc '{"role":"service_role"}'
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo\_%' or p.proname in ('so_invoice_cancel', 'so_credit_issue'));
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.product) as n_prod0,
       (select count(*) from public.so) as n_so0, (select count(*) from public.so_invoice) as n_inv0, (select count(*) from public.qbo_job) as n_job0, (select count(*) from public.qbo_txn) as n_txn0, (select count(*) from public.so_credit) as n_cr0, (select count(*) from public.so_payment) as n_pay0, (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as wh_id,
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
\echo '── 기준: 함수' :n_fn '· staff' :n_staff0 '· customer' :n_cust0 '· so' :n_so0 '· invoice' :n_inv0 '· job' :n_job0 '· txn' :n_txn0 '· realm' :realm '· since' :since0 '· HST ON →' :hst_qbo '· Net 60 →' :net60_qbo '· freight/discount =' :freight_qbo :discount_qbo
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
  ('b2b2b2b2-0000-4000-8000-00000000000a', 'b2b2b2b2-0000-4000-8000-000000000001', 'qbo-sync-2c1-bk@asung.invalid', 'QBO 2c1 Bookkeeper', 'manager', '["qbo", "sales"]'),
  ('b2b2b2b2-0000-4000-8000-00000000000b', 'b2b2b2b2-0000-4000-8000-000000000002', 'qbo-sync-2c1-worker@asung.invalid', 'QBO 2c1 Worker', 'worker', '["picking"]');
-- 가짜 손님 — 매장 A(짝 있음 · 이메일) · 매장 B(짝 있음) · 부모 P(짝 없음) · 자식 C(부모 P · 짝 없음)
insert into public.customer (id, name, is_active, source, currency_code, payment_term_id, payment_term_name, tax_rule) values
  ('c2b00000-0000-4000-8000-00000000000a', 'QBO2C Store A', true, 'manual', 'CAD', :'net60_id'::uuid, 'Net 60', 'HST ON (Sale)'),
  ('c2b00000-0000-4000-8000-00000000000b', 'QBO2C Store B', true, 'manual', 'CAD', null, null, null),
  ('c2b00000-0000-4000-8000-000000000010', 'QBO2C Parent', true, 'manual', 'CAD', null, null, null);
insert into public.customer (id, name, is_active, source, currency_code, parent_id, parent_source, default_bill_to_customer_id) values
  ('c2b00000-0000-4000-8000-000000000011', 'QBO2C Kid Store', true, 'manual', 'CAD', 'c2b00000-0000-4000-8000-000000000010', 'ims', 'c2b00000-0000-4000-8000-000000000010');
insert into public.customer_contact (customer_id, name, email, is_default, is_active, source) values ('c2b00000-0000-4000-8000-00000000000a', 'AP', 'ap-2b@asung.invalid', true, true, 'manual');
insert into public.customer_address (customer_id, type, is_default_for_type, line1, city, state_province, postal_code, country, source) values ('c2b00000-0000-4000-8000-000000000010', 'Billing', true, '9 Parent Rd', 'Toronto', 'ON', 'M2M 2M2', 'CA', 'manual');
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values
  (:'realm', 'customer', 'c2b00000-0000-4000-8000-00000000000a', 'Customer', 'C-2B-A', 'manual', 'QBO2C Store A'),
  (:'realm', 'customer', 'c2b00000-0000-4000-8000-00000000000b', 'Customer', 'C-2B-B', 'manual', 'QBO2C Store B');
-- 가짜 제품 셋 — 1 짝 있음 · 2 짝 없음(처음 팔 때 Item) · 3 짝 없음 + 같은 Sku 의 비활성 Item 만(941)
insert into public.product (id, name, sku, is_active, source, sellable, revenue_account_code) values
  ('d2b00000-0000-4000-8000-000000000001', 'QBO2C Widget Blue', 'QBO2C-001', true, 'manual', true, '_98_'),
  ('d2b00000-0000-4000-8000-000000000002', 'QBO2C Widget Red', 'QBO2C-002', true, 'manual', true, '_98_'),
  ('d2b00000-0000-4000-8000-000000000003', 'QBO2C Widget Gone', 'QBO2C-003', true, 'manual', true, '_98_');
insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, active) values (:'realm', 'Item', 'I-2B-1', 'QBO2C Widget Blue', 'QBO2C-001', true), (:'realm', 'Item', 'I-2B-INACT', 'QBO2C Widget Gone', 'QBO2C-003', false);
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values (:'realm', 'product', 'd2b00000-0000-4000-8000-000000000001', 'Item', 'I-2B-1', 'manual', 'QBO2C Widget Blue');
-- 가짜 SO 둘(INV1 손으로 · draft 로 넣는다 — 몸은 so 의 ref · tracking · shipped_at 만 읽는다) · 줄 · 비용 — 나머지 인보이스의 SO 는 mk_inv 가 만든다(한 SO 는 살아 있는 인보이스 하나 · so_invoice_order_active_uq)
insert into public.so (id, so_number, customer_id, bill_to_customer_id, channel, intake, currency_id, currency_code, order_date, ref, tracking_number, shipped_at, ship_to_company, ship_to_line1, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country) values
  ('e2b00000-0000-4000-8000-000000000001', 'SO-99901', 'c2b00000-0000-4000-8000-00000000000a', 'c2b00000-0000-4000-8000-00000000000a', 'pos', 'manual', :'cad_id'::uuid, 'CAD', '2026-11-02', 'PO-1', 'TRK1', '2026-11-02 15:00+00', 'QBO2C Store A', '1 Store St', 'Toronto', 'ON', 'M1M 1M1', 'CA'),
  ('e2b00000-0000-4000-8000-000000000002', 'SO-99902', 'c2b00000-0000-4000-8000-00000000000a', 'c2b00000-0000-4000-8000-00000000000a', 'pos', 'manual', :'cad_id'::uuid, 'CAD', '2026-11-02', null, null, '2026-11-02 16:00+00', 'QBO2C Store A', '2 Other St', 'Toronto', 'ON', 'M1M 1M1', 'CA');
insert into public.so_line (id, so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, list_price, discount_pct, discount_source, unit_price) values
  ('f2b00000-0000-4000-8000-000000000001', 'e2b00000-0000-4000-8000-000000000001', 1, 'd2b00000-0000-4000-8000-000000000001', 'QBO2C-001', 'QBO2C Widget Blue', 1, 20, 20, 2, 10, 'customer', 1.8),
  ('f2b00000-0000-4000-8000-000000000002', 'e2b00000-0000-4000-8000-000000000001', 2, 'd2b00000-0000-4000-8000-000000000002', 'QBO2C-002', 'QBO2C Widget Red', 1, 2, 2, null, null, null, 24.635);
insert into public.so_charge (id, so_id, line_no, name, amount, account_id, account_code, discount_pct, discount_amount) values
  ('a2b00000-0000-4000-8000-000000000001', 'e2b00000-0000-4000-8000-000000000001', 1, 'Standard', 10, :'a99'::uuid, '_99_', 50, null),
  ('a2b00000-0000-4000-8000-000000000002', 'e2b00000-0000-4000-8000-000000000001', 2, 'Card fee', 3, :'a20'::uuid, '_20_', null, null);
-- 인보이스 — 번호 명시(시퀀스 무접촉) · 합계는 CHECK 를 만족하게 손으로
-- INV1 매장 A · S1 + S2 · 줄 6(제품 2 · 운임 · 운임 할인 · 카드 수수료 · 오더 할인) — S1 몫: lines 85.27 · od −3.60 · charges 13 · chd 5 · taxable 89.67 · tax 11.66 · total 101.33 · S2 몫 0
insert into public.so_invoice (id, invoice_number, kind, status, bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country, issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code,
                               lines_amount, order_discount_amount, charges_amount, charges_discount_amount, surcharge_amount, taxable_amount, tax_amount, total, amount_due) values
  ('12b00000-0000-4000-8000-000000000001', '9990001', 'sale', 'issued', 'c2b00000-0000-4000-8000-00000000000a', 'QBO2C Store A', '1 Store St', 'Toronto', 'ON', 'M1M 1M1', 'CA', '2026-11-02', 'b2b2b2b2-0000-4000-8000-00000000000a', :'net60_id'::uuid, 'Net 60', '2027-01-01', :'cad_id'::uuid, 'CAD',
   85.27, -3.60, 13, 5, 0, 89.67, 11.66, 101.33, 101.33);
insert into public.so_invoice_order (id, invoice_id, so_id, so_number, customer_id, ship_to_company, ship_to_line1, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country, tax_rule_id, tax_rule, rate_pct, tax_source, lines_amount, order_discount_pct, order_discount_amount, charges_amount, charges_discount_amount, surcharge_amount, taxable_amount, tax_amount, total) values
  ('22b00000-0000-4000-8000-000000000001', '12b00000-0000-4000-8000-000000000001', 'e2b00000-0000-4000-8000-000000000001', 'SO-99901', 'c2b00000-0000-4000-8000-00000000000a', 'QBO2C Store A', '1 Store St', 'Toronto', 'ON', 'M1M 1M1', 'CA', :'hst_id'::uuid, 'HST ON (Sale)', 13, 'ship_to', 85.27, 4, -3.60, 13, 5, 0, 89.67, 11.66, 101.33),
  ('22b00000-0000-4000-8000-000000000002', '12b00000-0000-4000-8000-000000000001', 'e2b00000-0000-4000-8000-000000000002', 'SO-99902', 'c2b00000-0000-4000-8000-00000000000a', 'QBO2C Store A', '2 Other St', 'Toronto', 'ON', 'M1M 1M1', 'CA', :'hst_id'::uuid, 'HST ON (Sale)', 13, 'ship_to', 0, null, 0, 0, 0, 0, 0, 0, 0);
insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, so_charge_id, sku, description, unit, pack_factor, qty, list_price, discount_pct, discount_source, unit_price, amount, tax_amount, account_id, account_code) values
  ('12b00000-0000-4000-8000-000000000001', '22b00000-0000-4000-8000-000000000001', 1, 'product', 'f2b00000-0000-4000-8000-000000000001', null, 'QBO2C-001', 'QBO2C Widget Blue', 'ea', 1, 20, 2, 10, 'customer', 1.8, 36.00, 4.68, :'a98'::uuid, '_98_'),
  ('12b00000-0000-4000-8000-000000000001', '22b00000-0000-4000-8000-000000000001', 2, 'product', 'f2b00000-0000-4000-8000-000000000002', null, 'QBO2C-002', 'QBO2C Widget Red', 'ea', 1, 2, null, null, null, 24.635, 49.27, 6.41, :'a98'::uuid, '_98_'),
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
          case when p_kind = 'opening' then 'QBO2C-LS' end, case when p_kind = 'opening' then 'QBO2C-LI' end, case when p_kind = 'opening' then p_bill end);   -- so_invoice_opening_ck
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
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000002', '9990002', 'sale', 'c2b00000-0000-4000-8000-000000000010', 'QBO2C Parent', '2026-11-02', array['c2b00000-0000-4000-8000-000000000011'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000003', '9990003', 'sale', 'c2b00000-0000-4000-8000-00000000000a', 'QBO2C Store A', '2026-11-02', array['c2b00000-0000-4000-8000-00000000000a'::uuid, 'c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000004', '9990004', 'sale', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2C Store B', '2026-11-02', array['c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000005', '9990005', 'sale', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2C Store B', '2026-11-02', array['c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000006', '9990006', 'sale', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2C Store B', '2026-10-31', array['c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000003', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000007', '9990007', 'opening', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2C Store B', '2026-11-02', '{}'::uuid[], 'd2b00000-0000-4000-8000-000000000001', false);

-- 2c1 덧: 매장 B 의 기본 Billing · Shipping 주소(참조 크레딧 962) · INV8(skipped 일감) · INV9(크레딧 → 959) · INV10(일감 없음 · 2b) · 상태 올리기 도우미
insert into public.customer_address (customer_id, type, is_default_for_type, line1, city, state_province, postal_code, country, source) values
  ('c2b00000-0000-4000-8000-00000000000b', 'Billing', true, '7 Bill Rd', 'Toronto', 'ON', 'M3M 3M3', 'CA', 'manual'),
  ('c2b00000-0000-4000-8000-00000000000b', 'Shipping', true, '8 Ship Rd', 'Toronto', 'ON', 'M4M 4M4', 'CA', 'manual');
insert into public.customer_contact (customer_id, name, email, is_default, is_active, source) values ('c2b00000-0000-4000-8000-00000000000b', 'AP B', 'ap-b-2c@asung.invalid', true, true, 'manual');
insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, active) values (:'realm', 'Item', 'I-2C-6', 'QBO2C Goodwill', null, true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000008', '9990008', 'sale', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2C Store B', '2026-11-02', array['c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000009', '9990009', 'sale', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2C Store B', '2026-11-02', array['c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000010', '9990010', 'sale', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2C Store B', '2026-11-02', array['c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
select pg_temp.mk_inv('12b00000-0000-4000-8000-000000000011', '9990011', 'sale', 'c2b00000-0000-4000-8000-00000000000b', 'QBO2C Store B', '2026-11-02', array['c2b00000-0000-4000-8000-00000000000b'::uuid], 'd2b00000-0000-4000-8000-000000000001', true);
create function pg_temp.fulfill(p_inv uuid) returns int language plpgsql as $$
declare v_so uuid; v_n int := 0;
begin
  for v_so in select o.so_id from public.so_invoice_order o where o.invoice_id = p_inv loop
    update public.so set status = 'confirmed', confirmed_at = now() where id = v_so;
    update public.so set status = 'shipped' where id = v_so;
    update public.so set status = 'fulfilled', closed_at = now(), invoiced_at = now() where id = v_so;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
select pg_temp.fulfill('12b00000-0000-4000-8000-000000000005') + pg_temp.fulfill('12b00000-0000-4000-8000-000000000009') + pg_temp.fulfill('12b00000-0000-4000-8000-000000000011') as fulfilled \gset
-- 가짜 크레딧 — 번호 명시 · 합계 CHECK 손으로 · 전부 매장 = 청구처 · 발행자 북키퍼
--   CR1 INV1(보내진 인보이스 — qbo_txn 손으로) 줄 셋: 제품 1 (2 × 1.8 = 3.60 · 0.47) · 운임 kind 로 카드 수수료 줄 6(3 · 0.39 · acct:_20_) · other _6_ (1 · 0.13 · 짝 없음 → 961) = 7.60 + 0.99 = 8.59
--   CR2 INV4(일감 queued · 960 기다림) · CR3 INV8(일감 skipped · 2a) · CR4 INV10(일감 없음 · 2b) · CR5 참조(매장 B · 머리 규칙 · 제품 1 · 운임) · CR6 INV6(since 전 인보이스 · 안 기다림 · 채우기 재료) · CR7 10-31 발행(since 전 · 일감 없음) · CR8 INV9(959 → 취소 → skipped)
create function pg_temp.mk_cr(p_id uuid, p_num text, p_inv uuid, p_ref text, p_cust uuid, p_on date, p_lines numeric, p_tax numeric, p_rule boolean) returns void language plpgsql as $$
begin
  insert into public.so_credit (id, credit_number, status, customer_id, store_customer_id, currency_id, currency_code, invoice_id, ref_invoice_number, ref_order_number, reason, warehouse_id, warehouse_name, tax_rule_id, tax_rule, rate_pct, issued_on, issued_by,
                                lines_amount, fee_amount, tax_amount, total, order_discount_amount, freight_discount_amount, surcharge_amount)
  values (p_id, p_num, 'issued', p_cust, p_cust, (select id from public.ref_currency where code = 'CAD'), 'CAD', p_inv, p_ref, case when p_ref is not null then 'SO-OLD-1' end, 'customer_return',
          (select id from public.ref_warehouse where name = 'Asung Trading Inc.'), 'Asung Trading Inc.', case when p_rule then (select id from public.ref_tax_rule where name = 'HST ON (Sale)') end, case when p_rule then 'HST ON (Sale)' end, case when p_rule then 13 end,
          p_on, 'b2b2b2b2-0000-4000-8000-00000000000a', p_lines, 0, p_tax, p_lines + p_tax, 0, 0, 0);
end $$;
select pg_temp.mk_cr('32c00000-0000-4000-8000-000000000001', 'CR-99901', '12b00000-0000-4000-8000-000000000001', null, 'c2b00000-0000-4000-8000-00000000000a', '2026-11-02', 7.60, 0.99, false);
select pg_temp.mk_cr('32c00000-0000-4000-8000-000000000002', 'CR-99902', '12b00000-0000-4000-8000-000000000004', null, 'c2b00000-0000-4000-8000-00000000000b', '2026-11-02', 2, 0.26, false);
select pg_temp.mk_cr('32c00000-0000-4000-8000-000000000003', 'CR-99903', '12b00000-0000-4000-8000-000000000008', null, 'c2b00000-0000-4000-8000-00000000000b', '2026-11-02', 2, 0.26, false);
select pg_temp.mk_cr('32c00000-0000-4000-8000-000000000004', 'CR-99904', '12b00000-0000-4000-8000-000000000010', null, 'c2b00000-0000-4000-8000-00000000000b', '2026-11-02', 2, 0.26, false);
select pg_temp.mk_cr('32c00000-0000-4000-8000-000000000005', 'CR-99905', null, '48160', 'c2b00000-0000-4000-8000-00000000000b', '2026-11-02', 7, 0.91, true);
select pg_temp.mk_cr('32c00000-0000-4000-8000-000000000006', 'CR-99906', '12b00000-0000-4000-8000-000000000006', null, 'c2b00000-0000-4000-8000-00000000000b', '2026-11-02', 2, 0.26, false);
select pg_temp.mk_cr('32c00000-0000-4000-8000-000000000007', 'CR-99907', '12b00000-0000-4000-8000-000000000006', null, 'c2b00000-0000-4000-8000-00000000000b', '2026-10-31', 2, 0.26, false);
select pg_temp.mk_cr('32c00000-0000-4000-8000-000000000008', 'CR-99908', '12b00000-0000-4000-8000-000000000009', null, 'c2b00000-0000-4000-8000-00000000000b', '2026-11-02', 2, 0.26, false);
-- 줄 — CR1 셋 · 나머지 제품 1 한 줄(인보이스 줄 = 그 인보이스의 1 번 줄 · CR5 는 인보이스 줄 없음 + 운임)
insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, product_id, sku, description, qty_returned, not_restocked_reason, unit_price, amount, rate_pct, tax_amount, account_id, account_code) values
  ('32c00000-0000-4000-8000-000000000001', 1, 'product', (select id from public.so_invoice_line where invoice_id = '12b00000-0000-4000-8000-000000000001' and line_no = 1), 'd2b00000-0000-4000-8000-000000000001', 'QBO2C-001', 'QBO2C Widget Blue', 2, 'not_returned', 1.8, 3.60, 13, 0.47, :'a98'::uuid, '_98_'),
  ('32c00000-0000-4000-8000-000000000001', 2, 'freight', (select id from public.so_invoice_line where invoice_id = '12b00000-0000-4000-8000-000000000001' and line_no = 6), null, null, 'Card fee', null, null, null, 3, 13, 0.39, :'a20'::uuid, '_20_'),
  ('32c00000-0000-4000-8000-000000000001', 3, 'other', null, null, null, 'Goodwill', null, null, null, 1, 13, 0.13, :'a6'::uuid, '_6_'),
  ('32c00000-0000-4000-8000-000000000005', 1, 'product', null, 'd2b00000-0000-4000-8000-000000000001', 'QBO2C-001', 'QBO2C Widget Blue', 1, 'not_returned', 5, 5, 13, 0.65, :'a98'::uuid, '_98_'),
  ('32c00000-0000-4000-8000-000000000005', 2, 'freight', null, null, null, 'Freight', null, null, null, 2, 13, 0.26, :'a99'::uuid, '_99_');
insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, product_id, sku, description, qty_returned, not_restocked_reason, unit_price, amount, rate_pct, tax_amount, account_id, account_code)
select c.id, 1, 'product', (select il.id from public.so_invoice_line il where il.invoice_id = c.invoice_id and il.line_no = 1), 'd2b00000-0000-4000-8000-000000000001', 'QBO2C-001', 'QBO2C Widget Blue', 1, 'not_returned', 2, 2, 13, 0.26, :'a98'::uuid, '_98_'
  from public.so_credit c where c.id in ('32c00000-0000-4000-8000-000000000002', '32c00000-0000-4000-8000-000000000003', '32c00000-0000-4000-8000-000000000004', '32c00000-0000-4000-8000-000000000006', '32c00000-0000-4000-8000-000000000007', '32c00000-0000-4000-8000-000000000008');
-- INV1 은 보내진 셈(qbo_txn 손으로) · INV4 는 일감 queued(발행 트리거) · INV8 일감은 skipped · INV10 일감은 지운다
set constraints all immediate;
insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, sent_at) values (:'realm', 'invoice', '12b00000-0000-4000-8000-000000000001', 'Invoice', 'INV-2C-1', '9990001', '3', 101.33, 11.66, now());
update public.qbo_job set state = 'skipped', note = 'test skip' where ims_id = '12b00000-0000-4000-8000-000000000008' and kind = 'invoice';
delete from public.qbo_job where ims_id = '12b00000-0000-4000-8000-000000000010' and kind = 'invoice';
update public.qbo_entity set detail = '{"TaxRateDetail":[{"TaxRateRef":{"value":"12","name":"HST ON"},"TaxTypeApplicable":"TaxOnAmount","TaxOrder":0}]}'::jsonb where realm_id = :'realm' and qbo_type = 'TaxCode' and qbo_id = :'hst_qbo';

-- ── A) 착지 · 966 · 968 · 959 ──
select pg_temp.chk('A1 착지 — so_credit 트리거 2 · 새 함수 5(grant 0) · so_credit_issue 에 tax 갈래 없음 · so_invoice_cancel 에 959 · 968 글 · 인보이스 트리거 둘 그대로',
  (select count(*)::text from pg_trigger t where t.tgrelid = 'public.so_credit'::regclass and t.tgname in ('so_credit_qbo_job', 'so_credit_qbo_cancel'))
  || ' ' || (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_credit_body', 'qbo_credit_void_body', 'qbo_job_on_credit_issue', 'qbo_job_on_credit_cancel', 'qbo_credit_backfill'))
  || ' | ' || (select (p.prosrc not like '%elsif v_kind = ''tax'' then%' and p.prosrc like '%A tax-only credit note is not allowed%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_issue')
  || ' ' || (select (p.prosrc like '%cancel those credit notes first%' and p.prosrc like '%settle it with a credit note instead%' and p.prosrc not like '%applied by hand — detach them first (or issue%' and p.prosrc like '%automatic allocations could not be released%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_invoice_cancel')
  || ' ' || (select count(*)::text from pg_trigger t where t.tgrelid = 'public.so_invoice'::regclass and t.tgname in ('so_invoice_qbo_job', 'so_invoice_qbo_cancel')),
  '2 qbo_credit_backfill={postgres=X/postgres} qbo_credit_body={postgres=X/postgres} qbo_credit_void_body={postgres=X/postgres} qbo_job_on_credit_cancel={postgres=X/postgres} qbo_job_on_credit_issue={postgres=X/postgres} | true true 2');
select pg_temp.chk('A2 966 so_credit_issue(북키퍼 manager · sales) — 세금만 거부 · 제품 + 세금도 거부(이견 1 나) · kind 목록 글에 tax 없음',
  left(pg_temp.mgw(format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', '12b00000-0000-4000-8000-000000000003', 'reason', 'billing_error', 'warehouse_id', :'wh_id', 'lines', jsonb_build_array(jsonb_build_object('kind', 'tax', 'amount', 0.26))))), 135)
  || ' | ' || left(pg_temp.mgw(format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', '12b00000-0000-4000-8000-000000000003', 'reason', 'billing_error', 'warehouse_id', :'wh_id',
        'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', (select id from public.so_invoice_line where invoice_id = '12b00000-0000-4000-8000-000000000003' and line_no = 1), 'qty_returned', 1, 'not_restocked_reason', 'not_returned'), jsonb_build_object('kind', 'tax', 'amount', 0.26))))), 40)
  || ' | ' || left(pg_temp.mgw(format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', '12b00000-0000-4000-8000-000000000003', 'reason', 'billing_error', 'warehouse_id', :'wh_id', 'lines', jsonb_build_array(jsonb_build_object('kind', 'bogus'))))), 113),
  'ERR P0001: A tax-only credit note is not allowed — credit the invoice in full and issue a corrected invoice instead — nothing was saved | ERR P0001: A tax-only credit note is not | ERR P0001: Line kind must be one of product, freight, other, restocking_fee, price_adjustment — nothing was saved');
select pg_temp.mgw(format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', '12b00000-0000-4000-8000-000000000003', 'reason', 'customer_return', 'warehouse_id', :'wh_id',
  'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', (select id from public.so_invoice_line where invoice_id = '12b00000-0000-4000-8000-000000000003' and line_no = 1), 'qty_returned', 1, 'not_restocked_reason', 'not_returned'),
                             jsonb_build_object('kind', 'product', 'so_invoice_line_id', (select id from public.so_invoice_line where invoice_id = '12b00000-0000-4000-8000-000000000003' and line_no = 2), 'qty_returned', 1, 'not_restocked_reason', 'not_returned'))))) as full_cr \gset
set constraints all immediate;
select pg_temp.chk('A3 전액 크레딧(INV3 두 줄 전부 · 세금은 줄마다 따라온다) 은 966 에 걸리지 않는다 — committed · total 4.52 · tax 0.52 · 발행 트리거 → credit 일감 queued(by_staff 북키퍼)',
  (:'full_cr'::jsonb->>'committed') || ' ' || (:'full_cr'::jsonb->'totals'->>'total') || ' ' || (:'full_cr'::jsonb->'totals'->>'tax_amount')
  || ' | ' || (select j.kind || ':' || j.ims_kind || ':' || j.state || ':' || (j.by_staff = 'b2b2b2b2-0000-4000-8000-00000000000a')::text from public.qbo_job j where j.ims_id = (:'full_cr'::jsonb->>'credit_id')), 'true 4.52 0.52 | credit:credit:queued:true');
-- 968 · 969 — INV5(fulfilled) 에 manual 결제 충당 하나 → 취소 거부 · INV11 에 auto_deposit 만 → 취소 통과 + void + 손님 잔액 복귀 · 959 — INV9 에 CR8 → 거부(번호) · CR8 취소 → INV9 취소 통과(오더 1 shipped)
insert into public.so_payment (id, kind, amount, paid_on, method, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, created_by)
  values ('42c00000-0000-4000-8000-000000000001', 'payment', 2, '2026-11-02', 'cash', 'c2b00000-0000-4000-8000-00000000000b', :'cad_id'::uuid, 'CAD', :'a98'::uuid, '_98_', :'wh_id'::uuid, 'Asung Trading Inc.', 'b2b2b2b2-0000-4000-8000-00000000000a');
insert into public.so_payment_alloc (payment_id, invoice_id, amount, source) values ('42c00000-0000-4000-8000-000000000001', '12b00000-0000-4000-8000-000000000005', 1, 'manual'), ('42c00000-0000-4000-8000-000000000001', '12b00000-0000-4000-8000-000000000011', 1, 'auto_deposit');
select pg_temp.chk('A4 968 — 손으로 넣은 결제(manual 1 건 · 일부)가 적용된 INV5 취소 거부 · 글 그대로 · 상태 issued 그대로 · alloc 그대로',
  pg_temp.mgw('select public.so_invoice_cancel(''12b00000-0000-4000-8000-000000000005'', ''wrong store'')::text') || ' | ' || (select i.status from public.so_invoice i where i.id = '12b00000-0000-4000-8000-000000000005')
  || ' ' || (select (a.voided_at is null)::text from public.so_payment_alloc a where a.invoice_id = '12b00000-0000-4000-8000-000000000005'),
  'ERR P0001: Invoice 9990005 has payments — settle it with a credit note instead — nothing was saved | issued true');
select (pg_temp.mgw('select to_jsonb(b)::text from public.so_customer_balance(''c2b00000-0000-4000-8000-00000000000b'') b where b.currency_code = ''CAD''')::jsonb->>'available') as avail0 \gset
select pg_temp.mgw('select public.so_invoice_cancel(''12b00000-0000-4000-8000-000000000011'', ''wrong store'')::text') as c969 \gset
select pg_temp.chk('A4b 969 — auto_deposit 만 붙은 INV11 취소 통과 · cancelled · auto 충당 1 건 1.00 void(void_note) · 손님 available +1(돌아감) · 오더 1 shipped',
  (:'c969'::jsonb->>'status') || ' ' || (:'c969'::jsonb->>'auto_allocations_released') || ' ' || (:'c969'::jsonb->>'released_amount')
  || ' | ' || (select (a.voided_at is not null)::text || ' ' || left(a.void_note, 34) from public.so_payment_alloc a where a.invoice_id = '12b00000-0000-4000-8000-000000000011')
  || ' | ' || trim_scale((:'c969'::jsonb->'customer_balance'->>'available')::numeric - :'avail0'::numeric)::text || ' | ' || (select s.status from public.so s join public.so_invoice_order o on o.so_id = s.id where o.invoice_id = '12b00000-0000-4000-8000-000000000011'),
  'cancelled 1 1 | true Invoice 9990011 cancelled: wrong s | 1 | shipped');
select pg_temp.mgw('select public.so_invoice_cancel(''12b00000-0000-4000-8000-000000000009'', ''wrong store'')::text') as c959 \gset
update public.so_credit set status = 'cancelled', cancelled_at = now(), cancelled_by = 'b2b2b2b2-0000-4000-8000-00000000000a', cancel_note = 'test' where id = '32c00000-0000-4000-8000-000000000008';
select pg_temp.mgw('select public.so_invoice_cancel(''12b00000-0000-4000-8000-000000000009'', ''wrong store'')::text') as c959b \gset
select pg_temp.chk('A5 959 — 발행 크레딧 CR-99908 이 가리키는 INV9 취소 거부(번호) · 그 크레딧을 취소하면(취소된 크레딧은 막지 않는다 · 결제 0) 통과 — cancelled · 오더 1 → shipped · CR8 일감은 skipped(취소 트리거)',
  :'c959' || ' | ' || (:'c959b'::jsonb->>'status') || ' ' || (:'c959b'::jsonb->>'orders_back_to_shipped') || ' ' || (select s.status from public.so s join public.so_invoice_order o on o.so_id = s.id where o.invoice_id = '12b00000-0000-4000-8000-000000000009')
  || ' | ' || (select j.state || ':' || left(j.note, 24) from public.qbo_job j where j.ims_id = '32c00000-0000-4000-8000-000000000008' and j.kind = 'credit'),
  'ERR P0001: Invoice 9990009 has credit note(s) CR-99908 — cancel those credit notes first — nothing was saved | cancelled 1 shipped | skipped:cancelled before sending');

-- ── B) 발행 트리거 · since · 채우기 ──
select pg_temp.chk('B1 발행 트리거 — CR1 ~ CR6 · CR8 queued(7) · CR7(10-31 발행 · since 전) 0 · ims_kind credit · by_staff 발행자',
  (select count(*)::text || ' ' || bool_and(j.ims_kind = 'credit' and j.by_staff = 'b2b2b2b2-0000-4000-8000-00000000000a')::text from public.qbo_job j where j.kind = 'credit' and j.ims_id like '32c00000%')
  || ' | ' || (select count(*)::text from public.qbo_job j where j.ims_id = '32c00000-0000-4000-8000-000000000007'), '7 true | 0');
delete from public.qbo_job where ims_id = '32c00000-0000-4000-8000-000000000006' and kind = 'credit';
select public.qbo_credit_backfill() as bf1 \gset
select public.qbo_credit_backfill() as bf2 \gset
select pg_temp.chk('B2 채우기(965) — CR6 일감을 지우고 부르면 1(queued · by_staff 발행자) · 다시 부르면 0(멱등) · CR7(since 전) · 취소된 CR8 은 안 채운다',
  :'bf1' || ' ' || (select j.state || ':' || (j.by_staff = 'b2b2b2b2-0000-4000-8000-00000000000a')::text from public.qbo_job j where j.ims_id = '32c00000-0000-4000-8000-000000000006' and j.kind = 'credit') || ' | ' || :'bf2'
  || ' | ' || (select count(*)::text from public.qbo_job j where j.ims_id = '32c00000-0000-4000-8000-000000000007'), '1 queued:true | 0 | 0');
select pg_temp.chk('B3 ims_rows charge(961) — 크레딧 other 줄의 계정 _6_ 행이 뜬다(짝 전) · _20_(비용 줄) · _99_ 없음 · 고정 넷 그대로',
  (select string_agg(r.ims_id || '=' || coalesce(r.ims_code, '-'), ' ' order by r.ims_id) from public.qbo_ims_rows('charge') r where r.ims_id in ('freight', 'discount', 'surcharge', 'freight_discount', 'acct:_6_', 'acct:_20_', 'acct:_99_')),
  'acct:_20_=_20_ acct:_6_=_6_ discount=- freight=- freight_discount=- surcharge=-');

-- ── C) claim · 몸 · 960 · 961 ──
select pg_temp.mgw('select public.qbo_link_set(''charge'', ''acct:_20_'', ''14735'')::text') as link20 \gset
select pg_temp.svc('select public.qbo_job_claim(20, array[''credit'', ''credit_void''])::text') as cl1 \gset
select pg_temp.chk('C1 claim(credit 만) — 7 잡음: CR1 failed(961 · acct:_6_ 짝 없음 · 글) · CR2 blocked_by INV4 일감(960 · blocked_for_invoice 1 · warning) · CR3 failed(INV8 skipped · 2a) · CR4 failed(INV10 일감 없음 · 2b) · CR5(참조) · CR6(since 전 인보이스) · 전액 크레딧(INV3 · 일감 sending → 몸 OK? INV3 은 매장 둘이라 인보이스 몸이 거부 — 크레딧은 기다린다) → jobs',
  (:'cl1'::jsonb->>'claimed') || ' ' || (:'cl1'::jsonb->>'body_failed') || ' ' || (:'cl1'::jsonb->>'blocked_for_needs') || ' ' || (:'cl1'::jsonb->>'blocked_for_invoice') || ' ' || jsonb_array_length(:'cl1'::jsonb->'jobs')::text
  || ' | ' || (select left(j.last_error, 106) from public.qbo_job j where j.ims_id = '32c00000-0000-4000-8000-000000000001' and j.kind = 'credit')
  || ' | ' || (select j.state || ' ' || (j.blocked_by = (select i.id from public.qbo_job i where i.ims_id = '12b00000-0000-4000-8000-000000000004' and i.kind = 'invoice'))::text || ' ' || j.warning from public.qbo_job j where j.ims_id = '32c00000-0000-4000-8000-000000000002' and j.kind = 'credit')
  || ' | ' || (select j.state || ' ' || left(j.last_error, 63) from public.qbo_job j where j.ims_id = '32c00000-0000-4000-8000-000000000003' and j.kind = 'credit')
  || ' | ' || (select j.state || ' ' || left(j.last_error, 66) from public.qbo_job j where j.ims_id = '32c00000-0000-4000-8000-000000000004' and j.kind = 'credit')
  || ' | ' || (select string_agg(j->>'doc_number', ' ' order by j->>'doc_number') from jsonb_array_elements(:'cl1'::jsonb->'jobs') j),
  '7 3 0 2 2 | Credit note line "Goodwill" on account _6_ has no QuickBooks item — link account item "acct:_6_" to a Quic'
  || ' | blocked true waiting for invoice 9990004 to reach QuickBooks first | failed Invoice 9990008 was skipped — skip this credit note too, or ret | failed Invoice 9990010 has no QuickBooks job — send the invoice first — n | CR-99905 CR-99906');
select pg_temp.chk('C2 참조 크레딧 CR5 몸(962 · 매장 B) — DocNumber · TxnDate · CustomerRef C-2B-B · CAD · BillAddr(이름 · 7 Bill Rd · Canada) · ShipAddr(매장 이름 · 8 Ship Rd) · BillEmail · 메모 둘(참조 번호 · Customer Reference = 옛 오더) · DueDate · SalesTermRef 없음 · 줄 2(제품 I-2B-1 · 1 × 5 · 운임 Item 4 · 2) · TaxCode 머리 규칙 · TxnTaxDetail 0.91 · NetAmountTaxable 7 · totals',
  (select (b->>'DocNumber') || ' ' || (b->>'TxnDate') || ' ' || (b->'CustomerRef'->>'value') || ' ' || (b->'CurrencyRef'->>'value') || ' | ' || (b->'BillAddr'->>'Line1') || ' · ' || (b->'BillAddr'->>'Line2') || ' · ' || (b->'BillAddr'->>'Country') || ' | ' || (b->'ShipAddr'->>'Line1') || ' · ' || (b->'ShipAddr'->>'Line2')
          || ' | ' || (b->'BillEmail'->>'Address') || ' | ' || (b->>'PrivateNote') || ' | ' || (b->'CustomerMemo'->>'value') || ' | ' || (b ? 'DueDate')::text || (b ? 'SalesTermRef')::text || (b ? 'ShipDate')::text
          || ' | ' || jsonb_array_length(b->'Line')::text || ' ' || (b->'Line'->0->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (b->'Line'->0->'SalesItemLineDetail'->>'Qty') || ' ' || (b->'Line'->0->'SalesItemLineDetail'->>'UnitPrice') || ' ' || (b->'Line'->0->>'Amount') || ' ' || (b->'Line'->0->'SalesItemLineDetail'->'TaxCodeRef'->>'value')
          || ' ' || (b->'Line'->1->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (b->'Line'->1->>'Amount') || ' | ' || (b->'TxnTaxDetail'->>'TotalTax') || ' ' || (b->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->>'NetAmountTaxable') || ' ' || (b->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->'TaxRateRef'->>'value')
          || ' | ' || (j->'totals'->>'total') || ' ' || (j->'totals'->>'tax') || ' ' || jsonb_array_length(b->'Line')::text
   from jsonb_array_elements(:'cl1'::jsonb->'jobs') j, lateral (select j->'body' b) x where j->>'doc_number' = 'CR-99905'),
  'CR-99905 2026-11-02 C-2B-B CAD | QBO2C Store B · 7 Bill Rd · Canada | QBO2C Store B · 8 Ship Rd | ap-b-2c@asung.invalid | Credit for invoice 48160 · Customer Reference: SO-OLD-1 | Credit for invoice 48160 · Customer Reference: SO-OLD-1, QBO2C Store B | falsefalsefalse'
  || ' | 2 I-2B-1 1 5 5 ' || :'hst_qbo' || ' ' || :'freight_qbo' || ' 2 | 0.91 7 12 | 7.91 0.91 2');
select pg_temp.chk('C3 CR6(since 전 인보이스 INV6 · 10-31) — 기다리지 않는다 · 주소 = 인보이스 bill_to(1 Any St) · ship_to 첫 오더(Ship · 5 St) · 메모 = 인보이스 번호 + 오더 ref · TaxCode = 그 오더 규칙',
  (select (b->'BillAddr'->>'Line1') || ' · ' || (b->'BillAddr'->>'Line2') || ' | ' || (b->'ShipAddr'->>'Line1') || ' · ' || (b->'ShipAddr'->>'Line2') || ' | ' || (b->>'PrivateNote') || ' | ' || (b->'Line'->0->'SalesItemLineDetail'->'TaxCodeRef'->>'value') || ' ' || (j->'warnings')::text
   from jsonb_array_elements(:'cl1'::jsonb->'jobs') j, lateral (select j->'body' b) x where j->>'doc_number' = 'CR-99906'),
  'QBO2C Store B · 1 Any St | Ship · 5 St | Credit for invoice 9990006 · Customer Reference: PO-' || (select o.so_number from public.so_invoice_order o where o.invoice_id = '12b00000-0000-4000-8000-000000000006') || ' | ' || :'hst_qbo' || ' []');
-- 961 짝 → retry → 다시 claim: CR1 몸(줄 셋 · 카드 수수료 14735 · other acct:_6_ · 합계 8.59) · INV4 일감을 보낸 셈 → CR2 풀림
select pg_temp.mgw('select public.qbo_link_set(''charge'', ''acct:_6_'', ''I-2C-6'')::text') as link6 \gset
select pg_temp.mgw(format('select public.qbo_job_retry(%L)::text', (select id from public.qbo_job where ims_id = '32c00000-0000-4000-8000-000000000001' and kind = 'credit'))) as r1 \gset
select pg_temp.svc('select public.qbo_job_claim(20, array[''invoice''])::text') as cli \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''INV-2C-4'', ''9990004'', ''0'', ''tid-inv4'', null, null, 2.26, 0.26)::text', (select id from public.qbo_job where ims_id = '12b00000-0000-4000-8000-000000000004' and kind = 'invoice'))) as d4 \gset
select pg_temp.svc('select public.qbo_job_claim(20, array[''credit'', ''credit_void''])::text') as cl2 \gset
select pg_temp.chk('C4 acct:_6_ 짝 + retry · INV4 done(자식 CR2 풀림 1) → claim 2(CR1 · CR2) — CR1 몸: CustomerRef C-2B-A · BillAddr 인보이스 · ShipAddr SO-99901 · 줄 3(I-2B-1 2 × 1.8 = 3.6 · 14735 3 · I-2C-6 1) · TaxLine 1(7.6 · 0.99) · totals 8.59 · CR2 몸 OK(TaxCode INV4 오더)',
  (:'d4'::jsonb->>'unblocked') || ' ' || (:'cl2'::jsonb->>'claimed') || ' ' || (:'cl2'::jsonb->>'blocked_for_invoice') || ' ' || jsonb_array_length(:'cl2'::jsonb->'jobs')::text
  || ' | ' || (select (b->'CustomerRef'->>'value') || ' ' || (b->'BillAddr'->>'Line2') || ' ' || (b->'ShipAddr'->>'Line2') || ' | ' || (b->'Line'->0->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (b->'Line'->0->'SalesItemLineDetail'->>'Qty') || ' ' || (b->'Line'->0->'SalesItemLineDetail'->>'UnitPrice') || ' ' || (b->'Line'->0->>'Amount')
              || ' ' || (b->'Line'->1->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (b->'Line'->1->>'Amount') || ' ' || (b->'Line'->2->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (b->'Line'->2->>'Amount')
              || ' | ' || jsonb_array_length(b->'TxnTaxDetail'->'TaxLine')::text || ' ' || (b->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->>'NetAmountTaxable') || ' ' || (b->'TxnTaxDetail'->>'TotalTax') || ' | ' || (j->'totals'->>'total')
      from jsonb_array_elements(:'cl2'::jsonb->'jobs') j, lateral (select j->'body' b) x where j->>'doc_number' = 'CR-99901')
  || ' | ' || (select (b->'Line'->0->'SalesItemLineDetail'->'TaxCodeRef'->>'value') || ' ' || (b->>'DocNumber') from jsonb_array_elements(:'cl2'::jsonb->'jobs') j, lateral (select j->'body' b) x where j->>'doc_number' = 'CR-99902'),
  '1 2 0 2 | C-2B-A 1 Store St 1 Store St | I-2B-1 2 1.8 3.60 14735 3 I-2C-6 1 | 1 7.60 0.99 | 8.59 | ' || :'hst_qbo' || ' CR-99902');
select pg_temp.chk('C5 몸 거부 — 취소된 CR8 · 없는 id · void 몸(보낸 적 없음) · 콤보 구성품 줄(0 원 · combo_credit_line_id)은 줄에서 빠진다',
  left(pg_temp.pg('select public.qbo_credit_body(''32c00000-0000-4000-8000-000000000008'')::text'), 51) || ' | ' || left(pg_temp.pg('select public.qbo_credit_body(''32c00000-0000-4000-8000-0000000000ff'')::text'), 34) || ' | ' || left(pg_temp.pg('select public.qbo_credit_void_body(''32c00000-0000-4000-8000-000000000002'')::text'), 69)
  || ' | ' || (select coalesce(pg_temp.pg(format('insert into public.so_credit_line (credit_id, line_no, kind, combo_credit_line_id, combo_qty, product_id, sku, description, qty_returned, not_restocked_reason, unit_price, amount, rate_pct, tax_amount, account_code) values (%L, 9, ''product'', %L, 1, %L, ''QBO2C-002'', ''part'', 1, ''not_returned'', 0, 0, 13, 0, ''_98_'') returning line_no::text',
                    '32c00000-0000-4000-8000-000000000005', (select id from public.so_credit_line where credit_id = '32c00000-0000-4000-8000-000000000005' and line_no = 1), 'd2b00000-0000-4000-8000-000000000002')), 'x'))
  || ' ' || (select (j->>'line_count') || ' ' || jsonb_array_length(j->'needs')::text from (select public.qbo_credit_body('32c00000-0000-4000-8000-000000000005') j) x),
  'ERR P0001: Credit note CR-99908 is cancelled — only | ERR P0001: No IMS credit note 32c0 | ERR P0001: Credit note CR-99902 was never sent to QuickBooks — nothin | 9 2 0');

-- ── D) done · 942 · 취소 → void · list · txn_of ──
select pg_temp.svc(format('select public.qbo_job_done(%L, ''CM-2C-1'', ''CR-99901'', ''0'', ''tid-cm1'', null, null, 8.59, 0.99)::text', (select id from public.qbo_job where ims_id = '32c00000-0000-4000-8000-000000000001' and kind = 'credit'))) as dc1 \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''CM-2C-2'', ''CR-99902'', ''0'', ''tid-cm2'', null, null, 2.25, 0.25)::text', (select id from public.qbo_job where ims_id = '32c00000-0000-4000-8000-000000000002' and kind = 'credit'))) as dc2 \gset
select pg_temp.chk('D1 done CR1(합계 같음) → sent · qbo_txn CreditMemo CM-2C-1 · doc_number · sync_token · mismatch null · CR2(합계 다름 942) → sent + mismatch 글 · 일감 warning',
  (:'dc1'::jsonb->>'state') || ' ' || coalesce(:'dc1'::jsonb->>'mismatch', 'null') || ' | ' || (select t.qbo_type || ' ' || t.qbo_id || ' ' || t.doc_number || ' ' || t.sync_token || ' ' || t.total_amt || ' ' || t.total_tax || ' ' || coalesce(t.mismatch, 'null') from public.qbo_txn t where t.ims_kind = 'credit' and t.ims_id = '32c00000-0000-4000-8000-000000000001')
  || ' | ' || (:'dc2'::jsonb->>'state') || ' ' || (:'dc2'::jsonb->>'mismatch') || ' ' || (select (j.warning like '%(942)')::text from public.qbo_job j where j.ims_id = '32c00000-0000-4000-8000-000000000002' and j.kind = 'credit'),
  'sent null | CreditMemo CM-2C-1 CR-99901 0 8.59 0.99 null | sent QuickBooks total 2.25 / tax 0.25 differs from IMS 2.26 / 0.26 — check credit note CR-99902 in QuickBooks (942) true');
-- 취소 셋 — CR1(sent → credit_void queued) · CR5(sending → credit_void blocked_by) · CR6 queued 상태가 아니라 sending 이라 … CR4 는 failed → skipped
update public.so_credit set status = 'cancelled', cancelled_at = now(), cancelled_by = 'b2b2b2b2-0000-4000-8000-00000000000a', cancel_note = 'wrong qty' where id in ('32c00000-0000-4000-8000-000000000001', '32c00000-0000-4000-8000-000000000005', '32c00000-0000-4000-8000-000000000004');
select pg_temp.chk('D2 취소 트리거(963) — CR1(보내짐) → credit_void queued(note) · CR5(sending) → credit_void blocked_by 그 일감 · CR4(failed) → skipped(note) · 취소된 크레딧의 qbo_credit_backfill 0',
  (select string_agg(right(j.ims_id, 1) || ':' || j.kind || ':' || j.state || ':' || coalesce(left(j.note, 24), '-'), ' ' order by j.ims_id, j.kind) from public.qbo_job j where j.ims_id in ('32c00000-0000-4000-8000-000000000001', '32c00000-0000-4000-8000-000000000005', '32c00000-0000-4000-8000-000000000004'))
  || ' | ' || (select (v.blocked_by = i.id)::text from public.qbo_job v join public.qbo_job i on i.ims_id = v.ims_id and i.kind = 'credit' where v.kind = 'credit_void' and v.ims_id = '32c00000-0000-4000-8000-000000000005') || ' | ' || public.qbo_credit_backfill()::text,
  '1:credit:sent:- 1:credit_void:queued:cancelled: wrong qty 4:credit:skipped:cancelled before sending 5:credit:sending:- 5:credit_void:blocked:cancelled while sending: | true | 0');
select pg_temp.svc('select public.qbo_job_claim(20, array[''credit'', ''credit_void''])::text') as cl3 \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''CM-2C-1'', ''CR-99901'', ''1'', ''tid-void1'')::text', (select id from public.qbo_job where ims_id = '32c00000-0000-4000-8000-000000000001' and kind = 'credit_void'))) as dv1 \gset
select pg_temp.chk('D3 claim → CR1 void 몸(Id CM-2C-1 · SyncToken 0 · doc_number · qbo_id) · done void → sent · qbo_txn.voided_at · sync_token 1 · void 몸 다시 → already voided',
  (select (j->>'kind') || ' ' || (j->'body'->>'Id') || ' ' || (j->'body'->>'SyncToken') || ' ' || (j->>'doc_number') || ' ' || (j->>'qbo_id') from jsonb_array_elements(:'cl3'::jsonb->'jobs') j where j->>'kind' = 'credit_void')
  || ' | ' || (:'dv1'::jsonb->>'state') || ' ' || (select (t.voided_at is not null)::text || ' ' || t.sync_token from public.qbo_txn t where t.ims_kind = 'credit' and t.ims_id = '32c00000-0000-4000-8000-000000000001')
  || ' | ' || left(pg_temp.pg('select public.qbo_credit_void_body(''32c00000-0000-4000-8000-000000000001'')::text'), 70),
  'credit_void CM-2C-1 0 CR-99901 CM-2C-1 | sent true 1 | ERR P0001: Credit note CR-99901 (QuickBooks #CM-2C-1) is already voide');
select pg_temp.chk('D4 list(북키퍼) — CR2 sent 행 ims_name(번호 · 청구처 · 통화 총액) · txn 칸(qbo_id · mismatch) · CR1 txn_voided_at · txn_of(credit · worker) — CR2 qbo_id · mismatch · job_state · CR3 일감만(txn null · failed)',
  (select (r->>'ims_name') || ' | ' || (r->>'txn_qbo_id') || ' ' || left(r->>'txn_mismatch', 16) from jsonb_array_elements(pg_temp.mgw('select public.qbo_job_list(''sent'')::text')::jsonb->'rows') r where r->>'ims_id' = '32c00000-0000-4000-8000-000000000002' and r->>'kind' = 'credit')
  || ' | ' || (select (r->>'txn_voided_at' is not null)::text from jsonb_array_elements(pg_temp.mgw('select public.qbo_job_list(''sent'')::text')::jsonb->'rows') r where r->>'ims_id' = '32c00000-0000-4000-8000-000000000001' and r->>'kind' = 'credit')
  || ' | ' || (select (j->>'qbo_id') || ' ' || left(j->>'mismatch', 10) || ' ' || (j->>'job_state') from (select pg_temp.wrk('select public.qbo_txn_of(''credit'', ''32c00000-0000-4000-8000-000000000002'')::text')::jsonb j) x)
  || ' | ' || (select coalesce(j->>'qbo_id', 'null') || ' ' || (j->>'job_state') from (select pg_temp.wrk('select public.qbo_txn_of(''credit'', ''32c00000-0000-4000-8000-000000000003'')::text')::jsonb j) x),
  'CR-99902 · QBO2C Store B · CAD 2.26 | CM-2C-2 QuickBooks total | true | CM-2C-2 QuickBooks sent | null failed');
select pg_temp.chk('D5 표 제약 — 열린 credit_void 둘 23505 · kind credit + ims_kind invoice 23514 · 트리거는 발행을 막지 않는다(연결 realm 을 비운 셈 — qbo_job insert 가 실패해도 so_credit 은 선다)',
  left(pg_temp.pg(format('insert into public.qbo_job (realm_id, kind, ims_kind, ims_id) values (%L, ''credit_void'', ''credit'', ''32c00000-0000-4000-8000-000000000005'') returning id::text', :'realm')), 9)
  || ' ' || left(pg_temp.pg(format('insert into public.qbo_job (realm_id, kind, ims_kind, ims_id) values (%L, ''credit'', ''invoice'', ''x'') returning id::text', :'realm')), 9)
  || ' | ' || left(pg_temp.pg(format('insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state) values (%L, ''credit'', ''credit'', ''32c00000-0000-4000-8000-000000000007'', ''sending'') returning state', :'realm')), 9),
  'ERR 23505 ERR 23514 | ERR 23514');

-- ── L) REST 두 겹 ① — 새 · 재발행 함수의 update · delete 는 전부 깊이 0 WHERE · 다른 함수 md5 무변 ──
select pg_temp.chk('L1 nowhere 스캐너 = 0(새 5 + 재발행 6)', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('qbo_credit_body', 'qbo_credit_void_body', 'qbo_job_on_credit_issue', 'qbo_job_on_credit_cancel', 'qbo_credit_backfill', 'so_invoice_cancel', 'so_credit_issue', 'qbo_ims_rows', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_list')),
  'qbo_credit_backfill=0 qbo_credit_body=0 qbo_credit_void_body=0 qbo_ims_rows=0 qbo_job_claim=0 qbo_job_done=0 qbo_job_list=0 qbo_job_on_credit_cancel=0 qbo_job_on_credit_issue=0 so_credit_issue=0 so_invoice_cancel=0');
\if :{?mig}
select pg_temp.chk('L2 기존 함수 md5 — 재발행 6(so_invoice_cancel · so_credit_issue · ims_rows · job_claim · job_done · job_list) 빼고 전부 begin 앞과 같다', (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5)
  || ' ' || (select string_agg(t.proname, ' ' order by t.proname) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5), (:n_fn - 6)::text || ' qbo_ims_rows qbo_job_claim qbo_job_done qbo_job_list so_credit_issue so_invoice_cancel');
\endif
select pg_temp.chk('L3 scanner 자기 시험', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text, '101');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.ims_staff where email like 'qbo-sync-2c1-%') = 0 as fake_staff_gone,
       (select count(*) from public.customer) = :n_cust0 as customer_same, (select count(*) from public.product) = :n_prod0 as product_same, (select count(*) from public.so) = :n_so0 as so_same,
       (select count(*) from public.so_invoice) = :n_inv0 as invoice_same, (select count(*) from public.so_credit) = :n_cr0 as credit_same, (select count(*) from public.so_payment) = :n_pay0 as payment_same,
       (select count(*) from public.qbo_job) = :n_job0 as job_same, (select count(*) from public.qbo_txn) = :n_txn0 as txn_same,
       (select count(*) from public.qbo_link) = :n_link0 as link_same, (select count(*) from public.qbo_entity) = :n_ent0 as entity_same,
       (select coalesce(value, '') from public.inv_config where key = 'qbo_send_since') = :'since0' as since_same,
       (select coalesce(to_jsonb(e)->>'detail', '') from public.qbo_entity e where e.qbo_type = 'TaxCode' and e.qbo_id = '6') = coalesce(:'tc6_detail0', '') as tc6_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
\if :{?mig}
select (select count(*) from pg_trigger where tgname = 'so_credit_qbo_job') = 0 as trigger_gone_as_expected, (select count(*) from pg_proc where proname = 'qbo_credit_body') = 0 as fn_gone_as_expected;
\else
select (select count(*) from pg_trigger where tgname = 'so_credit_qbo_job') = 1 as trigger_present, (select count(*) from pg_proc where proname = 'qbo_credit_body') = 1 as fn_present;
\endif
