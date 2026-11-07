-- supabase/tests/qbo_sync_2e3_1_check.sql — qbo-sync-2e-3-1 검증: 표 · 트리거 가지(opening → 두 일감 · 결제 길 무변 · 2e-2 무변) · 몸 넷(DocNumber · Item 짝 · 세금 · CustomerRef · 매장 다름 + 하위 손님 길 · wait · failed 글) · Item 짝 없음 → failed → qbo_link_set 되살림 · claim · done(두 장 · 대조 · void 둘 차례 · reconcile) · 떼기 셋 · 인보이스 취소 · 1013(크레딧 붙임 ↔ 이월 void) · requeue · retry · list(txn 짝 kind 로) · doc · preview · 백필(실물 10) · 실물 claim · 권한 · nowhere (2026-11-07)
-- [테스트 · Asung-IMS = IMS 메인] 시험 적용 장치 틀 — 기준(begin 앞) → begin(lock_timeout 2s) → 가짜 바탕(잠금 밖) → (-v mig 면 \i + G0 · 표 CHECK 는 파일 끝이라 잠금은 거기부터) → 검증은 DO 블록 넷(왕복 최소) → rollback · ⚠️ 잠금 구간 10 초 안 · ⚠️ 붙임 트리거는 DEFERRED — `set constraints all immediate` 로 당겨 쏜다
--   Claude Code(시험): MIG=supabase/migrations/20261107044131_qbo_sync_2e3_1_opening_credit_jobs.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2e3_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 차이는 G0 · B1(시험 = 파일 안 백필 · 확인 = 이미 적용된 수) · B2(실물 claim 은 시험만) · 기대 OK 수는 EXPECT_OK(시험 34 · 확인 33)
--   쓰기: 가짜 직원 1(qbo · sales) · 손님 4(A 짝 · B 짝 없음 · H 짝 · S 매장 짝 · 청구처 H) · 제품 1 · 인보이스 8 · 이월 결제 3(opening · _1150040009_) · 일반 결제 1 · 크레딧 2 · 붙임 ≈ 13 · qbo_link charge acct:_1150040009_ → Item 5624(실물 Item · 짝은 이 시험 안에서만) · 전부 rollback · QBO 호출 0
--   실물: B1 백필이 이월 돈 붙임 10 건에 opening_credit queued + opening_apply blocked 를 만들고(새 행) B2 가 가장 오래된 붙임의 opening_credit 하나만 claim 한다(for update skip locked = 새 행만 · 기존 실물 행은 읽기만) → rollback
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 34
\set MIGFLAG true
\else
\set EXPECT_OK 33
\set MIGFLAG false
\endif
\pset pager off
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo\_%' or p.proname like 'so\_%' or p.proname like 'shop\_%');
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.product) as n_prod0,
       (select count(*) from public.so) as n_so0, (select count(*) from public.so_invoice) as n_inv0, (select count(*) from public.so_credit) as n_cr0, (select count(*) from public.so_payment_alloc) as n_palloc0, (select count(*) from public.so_payment) as n_pay0,
       (select count(*) from public.qbo_job) as n_job0, (select count(*) from public.qbo_txn) as n_txn0, (select count(*) from public.qbo_link) as n_link0, (select count(*) from public.qbo_entity) as n_ent0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as tor_id, (select id::text from public.ref_currency where code = 'CAD') as cad_id, (select id::text from public.ref_account where code = '_1150040009_') as acct_cc,
       (select count(*) from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id join public.so_invoice i on i.id = a.invoice_id
         where a.voided_at is null and p.status = 'active' and p.kind = 'payment' and p.method = 'opening' and i.kind = 'sale' and public.qbo_send_since_ok(i.issued_on) and public.qbo_send_since_ok((a.created_at at time zone 'America/Toronto')::date)
           and not exists (select 1 from public.qbo_job j where j.ims_kind = 'opening_alloc' and j.ims_id = a.id::text) and not exists (select 1 from public.qbo_txn t where t.ims_kind in ('opening_credit', 'opening_alloc') and t.ims_id = a.id::text)) as n_scope,
       (select count(*) from public.qbo_job j where j.kind in ('payment', 'payment_void')) as n_payjob0, (select count(*) from public.qbo_job j where j.kind in ('credit_apply', 'credit_apply_void')) as n_cajob0, (select count(*) from public.qbo_job where ims_kind = 'opening_alloc') as n_oajob0,
       (select l.qbo_id from public.qbo_link l join public.ref_tax_rule r on r.id::text = l.ims_id where l.ims_kind = 'tax_rule' and r.direction = 'sale' and r.name ilike 'Out of Scope%' limit 1) as tax_oos,
       public.ims_today()::text as today \gset
select a.id::text as real_alloc, i.invoice_number as real_inv, trim_scale(a.amount)::text as real_amt, t.qbo_id as real_inv_qbo,
       (select l.qbo_id from public.qbo_link l where l.ims_kind = 'customer' and l.ims_id = p.customer_id::text) as real_cust_ref,
       'OC-' || i.invoice_number || '-' || (select count(*) from public.so_payment_alloc a2 join public.so_payment p2 on p2.id = a2.payment_id where a2.invoice_id = a.invoice_id and p2.method = 'opening' and (a2.created_at, a2.id) <= (a.created_at, a.id))::text as real_doc
  from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id join public.so_invoice i on i.id = a.invoice_id join public.qbo_txn t on t.ims_kind = 'invoice' and t.ims_id = i.id::text and t.voided_at is null
 where p.method = 'opening' and a.voided_at is null and i.kind = 'sale' order by a.created_at, a.id limit 1 \gset
\echo '── 기준: 함수' :n_fn '· job' :n_job0 '· opening_alloc jobs' :n_oajob0 '· payment jobs' :n_payjob0 '· credit_apply jobs' :n_cajob0 '· txn' :n_txn0 '· 백필 범위' :n_scope '· 실물 붙임' :real_alloc '→' :real_inv :real_amt '(' :real_doc ') · tax Out of Scope' :tax_oos '· realm' :realm
begin;
set local lock_timeout = '2s';
select clock_timestamp() as t_begin \gset
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create temp table t_kv (k text primary key, v text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$ insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want); $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_kv(k, v) values (p_k, p_v) on conflict (k) do update set v = excluded.v; $$;
create function pg_temp.get(p_k text) returns text language sql stable as $$ select v from t_kv where k = p_k $$;
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
create function pg_temp.bk(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"e3e30000-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
create function pg_temp.svc(p_sql text) returns text language sql as $$ select pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, p_sql) $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  return coalesce(v, '(null)');
end $$;
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
create function pg_temp.job(p_kind text, p_ims text) returns uuid language sql as $$ select j.id from public.qbo_job j where j.kind = p_kind and j.ims_id = p_ims and j.state not in ('sent', 'skipped') order by j.created_at desc limit 1 $$;
create function pg_temp.anyjob(p_kind text, p_ims text) returns uuid language sql as $$ select j.id from public.qbo_job j where j.kind = p_kind and j.ims_id = p_ims order by j.created_at desc limit 1 $$;
create function pg_temp.jobs(p_ims text) returns text language sql as $$ select coalesce(string_agg(j.kind || ':' || j.state, ',' order by j.created_at, coalesce(array_position(array['opening_credit', 'opening_apply', 'opening_apply_void', 'opening_credit_void', 'invoice', 'invoice_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void'], j.kind), 99), j.kind), '(none)') from public.qbo_job j where j.ims_id = p_ims $$;   -- 같은 트랜잭션 = 같은 created_at(now()) 라 kind 차례로
create function pg_temp.attach(p_pay text, p_inv text, p_amt numeric) returns text language sql as $$
  select pg_temp.bk(format($q$ select (public.so_payment_attach(%L, %L::jsonb))->'allocations'->0->>'alloc_id' $q$, p_pay, jsonb_build_array(jsonb_build_object('invoice_id', p_inv, 'amount', p_amt))::text)) $$;
create function pg_temp.detach(p_alloc text) returns text language sql as $$ select pg_temp.bk(format($q$ select (public.so_payment_detach(%L, 'test detach'))->>'payment_id' $q$, p_alloc)) $$;
create function pg_temp.claim(p_kinds text, p_job uuid) returns jsonb language sql as $$ select pg_temp.svc(format($q$ select public.qbo_job_claim(50, array[%s], array[%L]::uuid[])::text $q$, p_kinds, p_job))::jsonb $$;
create function pg_temp.done(p_job uuid, p_id text, p_name text, p_amt numeric, p_tax numeric, p_unapplied numeric) returns jsonb language sql as $$
  select pg_temp.svc(format('select public.qbo_job_done(%L, %L, %L, ''0'', ''tid'', null, null, %s, %s, %s)::text', p_job, p_id, p_name, coalesce(p_amt::text, 'null'), coalesce(p_tax::text, 'null'), coalesce(p_unapplied::text, 'null')))::jsonb $$;
-- 가짜 바탕(잠금 밖): 직원 · 손님 넷(A 짝 · B 짝 없음 · H 짝 · S 매장 짝 · 청구처 H) · QBO 손님 거울 둘(S 의 parent_id 는 처음엔 없음) · 제품 · 인보이스 여덟 · 이월 결제 셋 · 크레딧 하나
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('e3e30000-0000-4000-8000-00000000000a', 'e3e30000-0000-4000-8000-000000000001', 'qbo-sync-2e3-bk@asung.invalid', 'QBO 2e3 Bookkeeper', 'manager', '["qbo", "sales"]');
insert into public.customer (id, name, is_active, source, currency_code) values
  ('c3e30000-0000-4000-8000-00000000000a', 'QBO2E3 Store A', true, 'manual', 'CAD'), ('c3e30000-0000-4000-8000-00000000000b', 'QBO2E3 Store B', true, 'manual', 'CAD'), ('c3e30000-0000-4000-8000-000000000010', 'QBO2E3 Head H', true, 'manual', 'CAD');
insert into public.customer (id, name, is_active, source, currency_code, parent_id, parent_source, default_bill_to_customer_id) values
  ('c3e30000-0000-4000-8000-000000000011', 'QBO2E3 Store S', true, 'manual', 'CAD', 'c3e30000-0000-4000-8000-000000000010', 'ims', 'c3e30000-0000-4000-8000-000000000010');
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values
  (:'realm', 'customer', 'c3e30000-0000-4000-8000-00000000000a', 'Customer', 'C-2E3-A', 'manual', 'QBO2E3 Store A'), (:'realm', 'customer', 'c3e30000-0000-4000-8000-000000000010', 'Customer', 'C-2E3-H', 'manual', 'QBO2E3 Head H'),
  (:'realm', 'customer', 'c3e30000-0000-4000-8000-000000000011', 'Customer', 'C-2E3-S', 'manual', 'QBO2E3 Store S');
insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, parent_id, active, fetched_at) values (:'realm', 'Customer', 'C-2E3-H', 'QBO2E3 Head H', null, true, now()), (:'realm', 'Customer', 'C-2E3-S', 'QBO2E3 Store S', null, true, now());
insert into public.product (id, name, sku, is_active, source, sellable, revenue_account_code) values ('d3e30000-0000-4000-8000-000000000001', 'QBO2E3 Widget', 'QBO2E3-001', true, 'manual', true, '_98_');
create temp sequence s_so start 99960;
create function pg_temp.mk_inv(p_id uuid, p_num text, p_kind text, p_bill uuid, p_bill_name text, p_on date, p_cust uuid[]) returns void language plpgsql as $$
declare i int; v_oid uuid; v_so uuid; v_sl uuid; v_num text; v_n int := coalesce(array_length(p_cust, 1), 0); v_prod uuid := 'd3e30000-0000-4000-8000-000000000001';
begin
  insert into public.so_invoice (id, invoice_number, kind, status, bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country, issued_on, issued_by, store_customer_id, legacy_sale_id, legacy_invoice_id, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due)
  values (p_id, p_num, p_kind, 'issued', p_bill, p_bill_name, '1 Any St', 'Toronto', 'ON', 'M1M 1M1', 'CA', p_on, case when p_kind = 'sale' then 'e3e30000-0000-4000-8000-00000000000a'::uuid end, coalesce(p_cust[1], p_bill), case when p_kind = 'opening' then 'test-sale-' || p_num end, case when p_kind = 'opening' then 'test-inv-' || p_num end, (select id from public.ref_currency where code = 'CAD'), 'CAD', 10 * greatest(v_n, 1), 10 * greatest(v_n, 1), 0, 10 * greatest(v_n, 1), 10 * greatest(v_n, 1));
  for i in 1 .. v_n loop
    v_so := gen_random_uuid(); v_sl := gen_random_uuid(); v_oid := gen_random_uuid(); v_num := 'SO-' || nextval('s_so')::text;
    insert into public.so (id, so_number, customer_id, bill_to_customer_id, channel, intake, currency_id, currency_code, order_date, ref, shipped_at, ship_to_company, ship_to_line1, ship_to_city, ship_to_country)
    values (v_so, v_num, p_cust[i], p_bill, 'pos', 'manual', (select id from public.ref_currency where code = 'CAD'), 'CAD', p_on, 'PO-' || v_num, now(), 'Ship', '5 St', 'Toronto', 'CA');
    insert into public.so_line (id, so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, unit_price) values (v_sl, v_so, 1, v_prod, 'QBO2E3-001', 'QBO2E3 Widget', 1, 1, 1, 10);
    insert into public.so_invoice_order (id, invoice_id, so_id, so_number, customer_id, ship_to_company, ship_to_line1, ship_to_city, ship_to_country, tax_rule_id, tax_rule, rate_pct, tax_source, lines_amount, taxable_amount, tax_amount, total)
    values (v_oid, p_id, v_so, v_num, p_cust[i], 'Ship', '5 St', 'Toronto', 'CA', (select id from public.ref_tax_rule where name = 'HST ON (Sale)'), 'HST ON (Sale)', 0, 'ship_to', 10, 10, 0, 10);
    insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, qty, unit_price, amount, tax_amount, account_code) values (p_id, v_oid, i, 'product', v_sl, 'QBO2E3-001', 'QBO2E3 Widget', 1, 10, 10, 0, '_98_');
  end loop;
end $$;
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
-- INV1 A sale(일감 queued) · INV2 A sale(txn) · INV3 A opening · INV4 A sale(txn · 취소용) · INV5 S 매장 · 청구처 H(txn) · INV6 A sale since 전(10-31) · INV7 A sale(txn · 1013 · 대조) · INV8 B sale(txn · 짝 없음)
select pg_temp.mk_inv('13e30000-0000-4000-8000-000000000001', '9973001', 'sale', 'c3e30000-0000-4000-8000-00000000000a', 'QBO2E3 Store A', :'today'::date, array['c3e30000-0000-4000-8000-00000000000a'::uuid]);
select pg_temp.mk_inv('13e30000-0000-4000-8000-000000000002', '9973002', 'sale', 'c3e30000-0000-4000-8000-00000000000a', 'QBO2E3 Store A', :'today'::date, array['c3e30000-0000-4000-8000-00000000000a'::uuid]);
select pg_temp.mk_inv('13e30000-0000-4000-8000-000000000003', '9973003', 'opening', 'c3e30000-0000-4000-8000-00000000000a', 'QBO2E3 Store A', '2026-10-01', '{}'::uuid[]);
select pg_temp.mk_inv('13e30000-0000-4000-8000-000000000004', '9973004', 'sale', 'c3e30000-0000-4000-8000-00000000000a', 'QBO2E3 Store A', :'today'::date, array['c3e30000-0000-4000-8000-00000000000a'::uuid]);
select pg_temp.mk_inv('13e30000-0000-4000-8000-000000000005', '9973005', 'sale', 'c3e30000-0000-4000-8000-000000000010', 'QBO2E3 Head H', :'today'::date, array['c3e30000-0000-4000-8000-000000000011'::uuid]);
select pg_temp.mk_inv('13e30000-0000-4000-8000-000000000006', '9973006', 'sale', 'c3e30000-0000-4000-8000-00000000000a', 'QBO2E3 Store A', '2026-10-31', array['c3e30000-0000-4000-8000-00000000000a'::uuid]);
select pg_temp.mk_inv('13e30000-0000-4000-8000-000000000007', '9973007', 'sale', 'c3e30000-0000-4000-8000-00000000000a', 'QBO2E3 Store A', :'today'::date, array['c3e30000-0000-4000-8000-00000000000a'::uuid]);
select pg_temp.mk_inv('13e30000-0000-4000-8000-000000000008', '9973008', 'sale', 'c3e30000-0000-4000-8000-00000000000b', 'QBO2E3 Store B', :'today'::date, array['c3e30000-0000-4000-8000-00000000000b'::uuid]);
set constraints all immediate;
update public.qbo_job set state = 'sent', qbo_id = 'INV-2E3-' || right(ims_id, 1), qbo_name = '997300' || right(ims_id, 1), sent_at = now() where kind = 'invoice' and ims_id in ('13e30000-0000-4000-8000-000000000002', '13e30000-0000-4000-8000-000000000004', '13e30000-0000-4000-8000-000000000005', '13e30000-0000-4000-8000-000000000007', '13e30000-0000-4000-8000-000000000008');
insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, sent_at)
  select :'realm', 'invoice', x, 'Invoice', 'INV-2E3-' || right(x, 1), '997300' || right(x, 1), '0', 10, 0, now() from unnest(array['13e30000-0000-4000-8000-000000000002', '13e30000-0000-4000-8000-000000000004', '13e30000-0000-4000-8000-000000000005', '13e30000-0000-4000-8000-000000000007', '13e30000-0000-4000-8000-000000000008']) x;
delete from public.qbo_link l where l.ims_kind = 'charge' and l.ims_id = 'acct:_1150040009_';   -- 확인(적용 뒤) 때 Settings 에서 이미 5624 를 이었어도 C2(짝 없음 → failed) · C3(link_set 되살림)가 서도록 — 이 트랜잭션 안에서만 · rollback 됨
-- 이월 결제 셋(method opening · 계정 _1150040009_ · 10-31 · 실물 꼴) — OPA(A 50) · OPB(B 10 · 손님 짝 없음) · OPH(H 20 · 청구처 → 매장 S 인보이스)
insert into public.so_payment (id, kind, amount, paid_on, method, reference, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, status, note) values
  ('43e30000-0000-4000-8000-00000000000a', 'payment', 50, '2026-10-31', 'opening', 'OPEN-2E3-A', 'c3e30000-0000-4000-8000-00000000000a', :'cad_id', 'CAD', :'acct_cc', '_1150040009_', :'tor_id', 'Asung Trading Inc.', 'active', 'test opening'),
  ('43e30000-0000-4000-8000-00000000000b', 'payment', 10, '2026-10-31', 'opening', 'OPEN-2E3-B', 'c3e30000-0000-4000-8000-00000000000b', :'cad_id', 'CAD', :'acct_cc', '_1150040009_', :'tor_id', 'Asung Trading Inc.', 'active', 'test opening'),
  ('43e30000-0000-4000-8000-000000000010', 'payment', 20, '2026-10-31', 'opening', 'OPEN-2E3-H', 'c3e30000-0000-4000-8000-000000000010', :'cad_id', 'CAD', :'acct_cc', '_1150040009_', :'tor_id', 'Asung Trading Inc.', 'active', 'test opening');
-- 크레딧 CR1(A · INV2 의 크레딧 · txn) — 2e-2 길 무변 · CR2(A · txn) — 1013 확인용
insert into public.so_credit (id, credit_number, status, customer_id, store_customer_id, currency_id, currency_code, invoice_id, reason, warehouse_id, warehouse_name, issued_on, issued_by, lines_amount, fee_amount, tax_amount, total, order_discount_amount, freight_discount_amount, surcharge_amount)
values ('33e30000-0000-4000-8000-000000000001', 'CR-99931', 'issued', 'c3e30000-0000-4000-8000-00000000000a', 'c3e30000-0000-4000-8000-00000000000a', :'cad_id', 'CAD', '13e30000-0000-4000-8000-000000000002', 'customer_return', :'tor_id', 'Asung Trading Inc.', :'today'::date, 'e3e30000-0000-4000-8000-00000000000a', 20, 0, 0, 20, 0, 0, 0);
insert into public.so_credit (id, credit_number, status, customer_id, store_customer_id, currency_id, currency_code, invoice_id, reason, warehouse_id, warehouse_name, issued_on, issued_by, lines_amount, fee_amount, tax_amount, total, order_discount_amount, freight_discount_amount, surcharge_amount)
values ('33e30000-0000-4000-8000-000000000002', 'CR-99932', 'issued', 'c3e30000-0000-4000-8000-00000000000a', 'c3e30000-0000-4000-8000-00000000000a', :'cad_id', 'CAD', '13e30000-0000-4000-8000-000000000002', 'customer_return', :'tor_id', 'Asung Trading Inc.', :'today'::date, 'e3e30000-0000-4000-8000-00000000000a', 5, 0, 0, 5, 0, 0, 0);   -- CR2(1013 용 · 한 크레딧은 한 인보이스에 한 번만 붙는다)
update public.qbo_job set state = 'sent', qbo_id = 'CM-2E3-CR' || right(ims_id, 1), qbo_name = 'CR-9993' || right(ims_id, 1), sent_at = now() where kind = 'credit' and ims_id in ('33e30000-0000-4000-8000-000000000001', '33e30000-0000-4000-8000-000000000002');
insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, sent_at)
  select :'realm', 'credit', x, 'CreditMemo', 'CM-2E3-CR' || right(x, 1), 'CR-9993' || right(x, 1), '0', case right(x, 1) when '1' then 20 else 5 end, 0, now() from unnest(array['33e30000-0000-4000-8000-000000000001', '33e30000-0000-4000-8000-000000000002']) x;
select pg_temp.put('jinv1', pg_temp.job('invoice', '13e30000-0000-4000-8000-000000000001')::text);
select pg_temp.put('mig', :'MIGFLAG'), pg_temp.put('n_scope', :'n_scope'), pg_temp.put('n_oajob0', :'n_oajob0'), pg_temp.put('n_payjob0', :'n_payjob0'), pg_temp.put('n_cajob0', :'n_cajob0'), pg_temp.put('realm', :'realm'), pg_temp.put('tor_id', :'tor_id'), pg_temp.put('today', :'today'), pg_temp.put('tax_oos', :'tax_oos'),
       pg_temp.put('real_alloc', :'real_alloc'), pg_temp.put('real_inv', :'real_inv'), pg_temp.put('real_amt', :'real_amt'), pg_temp.put('real_doc', :'real_doc'), pg_temp.put('real_cust_ref', :'real_cust_ref');   -- ⚠️ psql 변수는 $$ 안(DO 블록)에서 안 바뀐다 — t_kv 로 넘긴다
create function pg_temp.fake_oa_jobs() returns bigint language sql stable as $$ select count(*) from public.qbo_job j where j.ims_kind = 'opening_alloc' and j.ims_id in (select a.id::text from public.so_payment_alloc a where a.payment_id in ('43e30000-0000-4000-8000-00000000000a', '43e30000-0000-4000-8000-00000000000b', '43e30000-0000-4000-8000-000000000010')) $$;
select clock_timestamp() as t_fixtures \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
select clock_timestamp() as t_mig \gset

-- ── A) 착지 · B) 백필(실물) — 한 블록 ──
do $$
declare v text; v_scope int := pg_temp.get('n_scope')::int;
begin
  perform pg_temp.chk('A1 CHECK — qbo_job kind 14 · ims_kind opening_alloc · pair 넷 · qbo_txn kind 둘 · pair opening_credit → CreditMemo · ELSE Payment',
    (select string_agg((pg_get_constraintdef(oid) ~* 'opening_credit_void' and pg_get_constraintdef(oid) ~* 'opening_apply_void')::text, ',' order by conname) from pg_constraint where conname in ('qbo_job_kind_ck', 'qbo_job_pair_ck'))
    || ' | ' || (select (pg_get_constraintdef(oid) ~ 'opening_alloc')::text from pg_constraint where conname = 'qbo_job_ims_kind_ck')
    || ' | ' || (select (pg_get_constraintdef(oid) ~ 'opening_credit' and pg_get_constraintdef(oid) ~ 'opening_alloc')::text from pg_constraint where conname = 'qbo_txn_kind_ck')
    || ' | ' || (select (pg_get_constraintdef(oid) ~ 'WHEN ''opening_credit''::text THEN ''CreditMemo''' and pg_get_constraintdef(oid) ~ 'ELSE ''Payment''')::text from pg_constraint where conname = 'qbo_txn_pair_ck'),
    'true,true | true | true | true');
  perform pg_temp.chk('A2 트리거 — so_payment_alloc 에 트리거 둘 그대로(qbo deferred + touch) · 새 트리거 없음 · 함수 본문에 opening 가지 · so_credit_alloc_qbo 그대로',
    (select string_agg(t.tgname || ':' || case when t.tgdeferrable and t.tginitdeferred then 'deferred' else 'immediate' end, ',' order by t.tgname) from pg_trigger t where t.tgrelid = 'public.so_payment_alloc'::regclass and not t.tgisinternal)
    || ' | ' || (select (prosrc like '%qbo_opening_alloc_sync(new.id%' and prosrc like '%qbo_payment_sync(new.payment_id%')::text from pg_proc where proname = 'qbo_job_on_payment_alloc' and pronamespace = 'public'::regnamespace)
    || ' | ' || (select count(*)::text from pg_trigger where tgname = 'so_credit_alloc_qbo' and tgdeferrable and tginitdeferred),
    'so_payment_alloc_qbo:deferred,so_payment_alloc_touch:immediate | true | 1');
  perform pg_temp.chk('A3 nowhere — 새 함수 여덟 · 재발행 열하나의 깊이 0 WHERE 없는 update · delete = 0',
    (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_opening_doc_number', 'qbo_opening_credit_body', 'qbo_opening_credit_void_body', 'qbo_opening_apply_body', 'qbo_opening_apply_void_body', 'qbo_opening_alloc_sync', 'qbo_opening_apply_backfill', 'qbo_opening_credit_requeue',
                                                                                                                                             'qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc', 'qbo_payment_requeue', 'qbo_link_set', 'qbo_ims_rows', 'qbo_credit_apply_body', 'qbo_job_on_payment_alloc')),
    'qbo_credit_apply_body=0 qbo_ims_rows=0 qbo_job_claim=0 qbo_job_doc=0 qbo_job_done=0 qbo_job_list=0 qbo_job_on_payment_alloc=0 qbo_job_preview=0 qbo_job_retry=0 qbo_link_set=0 qbo_opening_alloc_sync=0 qbo_opening_apply_backfill=0 qbo_opening_apply_body=0 qbo_opening_apply_void_body=0 qbo_opening_credit_body=0 qbo_opening_credit_requeue=0 qbo_opening_credit_void_body=0 qbo_opening_doc_number=0 qbo_payment_requeue=0');
  perform pg_temp.chk('A4 ACL — 새 함수 여덟 grant 0 · 재발행은 그대로(claim · done service_role · list · preview · retry · link_set authenticated · 그 밖 grant 0)',
    (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_opening_doc_number', 'qbo_opening_credit_body', 'qbo_opening_credit_void_body', 'qbo_opening_apply_body', 'qbo_opening_apply_void_body', 'qbo_opening_alloc_sync', 'qbo_opening_apply_backfill', 'qbo_opening_credit_requeue',
                                                                                                                                              'qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc', 'qbo_payment_requeue', 'qbo_link_set', 'qbo_ims_rows', 'qbo_credit_apply_body', 'qbo_job_on_payment_alloc')),
    'qbo_credit_apply_body={postgres=X/postgres} qbo_ims_rows={postgres=X/postgres} qbo_job_claim={postgres=X/postgres,service_role=X/postgres} qbo_job_doc={postgres=X/postgres} qbo_job_done={postgres=X/postgres,service_role=X/postgres} qbo_job_list={postgres=X/postgres,authenticated=X/postgres} qbo_job_on_payment_alloc={postgres=X/postgres} qbo_job_preview={postgres=X/postgres,authenticated=X/postgres} qbo_job_retry={postgres=X/postgres,authenticated=X/postgres} qbo_link_set={postgres=X/postgres,authenticated=X/postgres} qbo_opening_alloc_sync={postgres=X/postgres} qbo_opening_apply_backfill={postgres=X/postgres} qbo_opening_apply_body={postgres=X/postgres} qbo_opening_apply_void_body={postgres=X/postgres} qbo_opening_credit_body={postgres=X/postgres} qbo_opening_credit_requeue={postgres=X/postgres} qbo_opening_credit_void_body={postgres=X/postgres} qbo_opening_doc_number={postgres=X/postgres} qbo_payment_requeue={postgres=X/postgres}');
  perform pg_temp.chk('A5 무변 — 결제 넷(2e-1b md5) · qbo_credit_alloc_sync(2e-2-1 md5)', (select string_agg(left(md5(p.prosrc), 8), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_payment_body', 'qbo_payment_fingerprint', 'qbo_payment_sync', 'qbo_payment_void_body', 'qbo_credit_alloc_sync')), '44419d3b e1aea518 d6da0342 9efb5d9f 4ddb45cd');
  if pg_temp.get('mig') = 'true' then
    perform pg_temp.chk('B1 백필(실물 · 파일 안) — opening_credit queued = 백필 범위 · opening_apply blocked = 범위 · 모두 자기 credit 일감 뒤 · 가짜 0',
      (select count(*) filter (where j.kind = 'opening_credit' and j.state = 'queued')::text || ' ' || count(*) filter (where j.kind = 'opening_apply' and j.state = 'blocked')::text || ' ' || count(*) filter (where j.kind = 'opening_apply' and exists (select 1 from public.qbo_job c where c.id = j.blocked_by and c.kind = 'opening_credit' and c.ims_id = j.ims_id))::text || ' ' || count(*) filter (where j.ims_id like '%-0000-4000-8000-%')::text
         from public.qbo_job j where j.ims_kind = 'opening_alloc'),
      v_scope::text || ' ' || v_scope::text || ' ' || v_scope::text || ' 0');
  else
    perform pg_temp.chk('B1 (적용 뒤) 실물 붙임 ' || pg_temp.get('real_alloc') || ' 의 opening_alloc 일감 둘(credit · apply)이 있다', (select count(*)::text from public.qbo_job j where j.ims_kind = 'opening_alloc' and j.ims_id = pg_temp.get('real_alloc') and j.kind in ('opening_credit', 'opening_apply')), '2');
  end if;
  perform pg_temp.chk('B3 기존 결제 · 크레딧 붙임 일감 수 무변(백필은 새 kind 만)', (select count(*) filter (where j.kind in ('payment', 'payment_void'))::text || ' ' || count(*) filter (where j.kind in ('credit_apply', 'credit_apply_void'))::text from public.qbo_job j where j.ims_id not like '%-0000-4000-8000-%'), pg_temp.get('n_payjob0') || ' ' || pg_temp.get('n_cajob0'));
end $$;

-- ── C) 붙임 넣기(창구 · 트리거 가지) · Item 짝 없음 → failed → qbo_link_set 되살림 · D) 실물 claim ──
do $$
declare al1 text; al2 text; al3 text; al4 text; al5 text; al6 text; al7 text; al9 text; p1 text; ca public.so_payment_alloc%rowtype; v jsonb; v_t text; v_r jsonb; v_real text := pg_temp.get('real_alloc');
begin
  al1 := pg_temp.attach('43e30000-0000-4000-8000-00000000000a', '13e30000-0000-4000-8000-000000000002', 3);   -- OPA → INV2(txn)
  al2 := pg_temp.attach('43e30000-0000-4000-8000-00000000000a', '13e30000-0000-4000-8000-000000000001', 1);   -- OPA → INV1(일감 queued)
  al3 := pg_temp.attach('43e30000-0000-4000-8000-00000000000a', '13e30000-0000-4000-8000-000000000003', 1);   -- OPA → INV3(이월)
  al4 := pg_temp.attach('43e30000-0000-4000-8000-00000000000a', '13e30000-0000-4000-8000-000000000006', 1);   -- OPA → INV6(since 전)
  al5 := pg_temp.attach('43e30000-0000-4000-8000-00000000000b', '13e30000-0000-4000-8000-000000000008', 2);   -- OPB → INV8(손님 짝 없음)
  al6 := pg_temp.attach('43e30000-0000-4000-8000-000000000010', '13e30000-0000-4000-8000-000000000005', 2);   -- OPH → INV5(매장 S · 청구처 H)
  al7 := pg_temp.attach('43e30000-0000-4000-8000-00000000000a', '13e30000-0000-4000-8000-000000000007', 1);   -- OPA → INV7(대조 · 떼기)
  ca  := public.so_payment_alloc_add('43e30000-0000-4000-8000-00000000000a'::uuid, '13e30000-0000-4000-8000-000000000004'::uuid, 2, 'auto_balance', 'e3e30000-0000-4000-8000-00000000000a'::uuid);   -- OPA → INV4(auto · 취소용)
  al9 := ca.id::text;
  update public.so_payment_alloc a set created_at = a.created_at - interval '1 minute' where a.id in (al1::uuid, al9::uuid);   -- 같은 트랜잭션은 created_at 이 같다 — 재붙임 번호(OC-…-2)를 결정적으로
  p1  := pg_temp.bk(format($q$ select (public.so_payment_add(%L::jsonb))->>'payment_id' $q$, jsonb_build_object('customer_id', 'c3e30000-0000-4000-8000-00000000000a', 'amount', 4, 'method', 'cash', 'reference', '2E3-P1', 'currency_code', 'CAD', 'warehouse_id', pg_temp.get('tor_id'), 'allocations', jsonb_build_array(jsonb_build_object('invoice_id', '13e30000-0000-4000-8000-000000000007', 'amount', 4)))::text));
  perform public.so_credit_alloc_add('33e30000-0000-4000-8000-000000000001'::uuid, '13e30000-0000-4000-8000-000000000002'::uuid, 1, 'auto', 'e3e30000-0000-4000-8000-00000000000a'::uuid, null);   -- CR1 → INV2(2e-2 길)
  perform pg_temp.put('al1', al1); perform pg_temp.put('al2', al2); perform pg_temp.put('al3', al3); perform pg_temp.put('al4', al4); perform pg_temp.put('al5', al5); perform pg_temp.put('al6', al6); perform pg_temp.put('al7', al7); perform pg_temp.put('al9', al9); perform pg_temp.put('p1', p1);
  perform pg_temp.chk('C1 트리거 가지 — 이월 붙임 여덟 모두 opening_credit:queued + opening_apply:blocked(자기 credit 뒤) · 일반 결제 P1 → payment:queued(기존 길) · CR1 → credit_apply:queued(2e-2 길) · 이월 결제엔 payment 일감 0',
    (select string_agg(pg_temp.jobs(x), ' / ' order by x) from unnest(array[al1, al2, al3, al4, al5, al6, al7, al9]) x)
    || ' | ' || (select count(*)::text from public.qbo_job j where j.kind = 'opening_apply' and j.ims_id in (al1, al2, al3, al4, al5, al6, al7, al9) and j.state = 'blocked' and exists (select 1 from public.qbo_job c where c.id = j.blocked_by and c.kind = 'opening_credit' and c.ims_id = j.ims_id))
    || ' | ' || pg_temp.jobs(p1) || ' | ' || (select pg_temp.jobs(a.id::text) from public.so_credit_alloc a where a.credit_id = '33e30000-0000-4000-8000-000000000001' and a.voided_at is null)
    || ' | ' || (select count(*)::text from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id in ('43e30000-0000-4000-8000-00000000000a', '43e30000-0000-4000-8000-00000000000b', '43e30000-0000-4000-8000-000000000010')),
    (select string_agg('opening_credit:queued,opening_apply:blocked', ' / ' order by x) from unnest(array[al1, al2, al3, al4, al5, al6, al7, al9]) x) || ' | 8 | payment:queued | credit_apply:queued | 0');
  -- Item 짝 없음 → 몸 거부 · claim 하면 failed · qbo_ims_rows('charge') 에 acct: 행 · qbo_link_set 이 되살린다(requeued 1)
  v_t := pg_temp.try(format('select public.qbo_opening_credit_body(%L)::text', al1));
  v := pg_temp.claim($k$'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void'$k$, pg_temp.job('opening_credit', al1));
  perform pg_temp.chk('C2 Item 짝 없음 — 몸 거부 글 · claim 은 failed(body_failed 1 · last_error 같은 글) · qbo_ims_rows(charge) 에 acct:_1150040009_ 행(이름 · 계정 코드)',
    v_t || ' | ' || (v->>'claimed') || ' ' || (v->>'body_failed') || ' ' || (select j.state || ' ' || (j.last_error = replace(v_t, 'ERR P0001: ', ''))::text from public.qbo_job j where j.id = pg_temp.job('opening_credit', al1))
    || ' | ' || (select r.ims_name || ' ' || r.ims_code from public.qbo_ims_rows('charge') r where r.ims_id = 'acct:_1150040009_'),
    'ERR P0001: Opening credits on account _1150040009_ have no QuickBooks item — link account item "acct:_1150040009_" to the Customer Credit item under Settings → QuickBooks matching; this opening credit then goes by itself — nothing was sent | 1 1 failed true | Charge on account _1150040009_ Customer Credits _1150040009_');
  v_t := pg_temp.bk($q$ select public.qbo_link_set('charge', 'acct:_1150040009_', '5624')::text $q$);
  perform pg_temp.chk('C3 qbo_link_set(charge acct:_1150040009_ → Item 5624 Customer Credit) — 짝 행 · requeued 1 · al1 credit 일감 queued + note',
    (v_t::jsonb->>'ims_kind') || ' ' || (v_t::jsonb->>'ims_id') || ' ' || (v_t::jsonb->>'qbo_id') || ' ' || (v_t::jsonb->>'qbo_name') || ' ' || (v_t::jsonb->>'requeued') || ' | ' || (select j.state || ' ' || (j.note like '%sent again: account item "acct:_1150040009_" is now matched%')::text from public.qbo_job j where j.id = pg_temp.job('opening_credit', al1)),
    'charge acct:_1150040009_ 5624 Customer Credit 1 | queued true');
  if pg_temp.get('mig') = 'true' then                                                                                                  -- D) 실물 claim(가장 오래된 붙임의 opening_credit · 짝이 섰으니 몸이 선다 · rollback 됨)
    v := pg_temp.claim($k$'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void'$k$, pg_temp.job('opening_credit', v_real));
    perform pg_temp.chk('B2 실물 claim ' || pg_temp.get('real_doc') || ' → ' || pg_temp.get('real_inv') || ' — claimed 1 · kind · doc_number · body DocNumber · CustomerRef(실물 짝) · Line ItemRef 5624 · Amount ' || pg_temp.get('real_amt') || ' · TaxCodeRef ' || pg_temp.get('tax_oos') || ' · TotalTax 0 · PrivateNote · 인보이스 일감 sent 라 wait 없음',
      (v->>'claimed') || ' ' || (v->>'body_failed') || ' ' || (v->>'blocked_for_invoice') || ' | ' || (v->'jobs'->0->>'kind') || ' ' || (v->'jobs'->0->>'doc_number') || ' ' || (v->'jobs'->0->'body'->>'DocNumber') || ' ' || (v->'jobs'->0->'body'->'CustomerRef'->>'value') || ' ' || (v->'jobs'->0->'body'->'Line'->0->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (v->'jobs'->0->'body'->'Line'->0->>'Amount') || ' ' || (v->'jobs'->0->'body'->'Line'->0->'SalesItemLineDetail'->'TaxCodeRef'->>'value') || ' ' || (v->'jobs'->0->'body'->'TxnTaxDetail'->>'TotalTax') || ' ' || (v->'jobs'->0->'body'->>'PrivateNote' = 'IMS opening credit used ' || v_real)::text,
      '1 0 0 | opening_credit ' || pg_temp.get('real_doc') || ' ' || pg_temp.get('real_doc') || ' ' || pg_temp.get('real_cust_ref') || ' 5624 ' || pg_temp.get('real_amt') || ' ' || pg_temp.get('tax_oos') || ' 0 true');
  end if;
end $$;

-- ── E) 몸 넷 ──
do $$
declare al1 text := pg_temp.get('al1'); al2 text := pg_temp.get('al2'); al3 text := pg_temp.get('al3'); al4 text := pg_temp.get('al4'); al5 text := pg_temp.get('al5'); al6 text := pg_temp.get('al6'); p1 text := pg_temp.get('p1'); b jsonb; b2 jsonb; v_t text; v_t2 text; p1a text;
begin
  b := public.qbo_opening_credit_body(al1::uuid);
  perform pg_temp.chk('E1 al1 credit 몸(OPA → INV2 · txn) — DocNumber OC-9973002-1 · TxnDate 오늘 · CustomerRef C-2E3-A · CAD · Line 한 줄(ItemRef 5624 · Qty 1 · UnitPrice 3 · Amount 3 · TaxCodeRef ' || pg_temp.get('tax_oos') || ') · TaxExcluded · TxnTaxDetail(0 · TaxLine rate · NetAmountTaxable 3) · PrivateNote · CustomerMemo · wait null · needs 0 · name · fingerprint null · totals',
    (b->'body'->>'DocNumber') || ' ' || (b->'body'->>'TxnDate') || ' ' || (b->'body'->'CustomerRef'->>'value') || ' ' || (b->'body'->'CurrencyRef'->>'value') || ' | ' || jsonb_array_length(b->'body'->'Line')::text || ' ' || (b->'body'->'Line'->0->'SalesItemLineDetail'->'ItemRef'->>'value') || ' ' || (b->'body'->'Line'->0->'SalesItemLineDetail'->>'Qty') || ' ' || (b->'body'->'Line'->0->'SalesItemLineDetail'->>'UnitPrice') || ' ' || (b->'body'->'Line'->0->>'Amount') || ' ' || (b->'body'->'Line'->0->'SalesItemLineDetail'->'TaxCodeRef'->>'value') || ' ' || (b->'body'->'Line'->0->>'Description')
    || ' | ' || (b->'body'->>'GlobalTaxCalculation') || ' ' || (b->'body'->'TxnTaxDetail'->>'TotalTax') || ' ' || (b->'body'->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->'TaxRateRef'->>'value') || ' ' || (b->'body'->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->>'NetAmountTaxable') || ' ' || (b->'body'->'TxnTaxDetail'->'TaxLine'->0->>'Amount')
    || ' | ' || (b->'body'->>'PrivateNote' = 'IMS opening credit used ' || al1)::text || ' ' || (b->'body'->'CustomerMemo'->>'value') || ' | ' || coalesce(b->>'wait_job', 'null') || ' ' || jsonb_array_length(b->'needs')::text || ' ' || (b->>'name') || ' ' || (b->>'doc_number') || ' ' || (b->'fingerprint')::text || ' ' || (b->'totals'->>'total') || ' ' || (b->'totals'->>'tax'),
    'OC-9973002-1 ' || pg_temp.get('today') || ' C-2E3-A CAD | 1 5624 1 3 3 ' || pg_temp.get('tax_oos') || ' Credit on account applied to invoice 9973002 | TaxExcluded 0 ' || (select coalesce(e.detail->'TaxRateDetail'->0->'TaxRateRef'->>'value', '?') from public.qbo_entity e where e.qbo_type = 'TaxCode' and e.qbo_id = pg_temp.get('tax_oos')) || ' 3 0 | true Credit on account applied to invoice 9973002 | null 0 OC-9973002-1 → 9973002 OC-9973002-1 null 3 0');
  b := public.qbo_opening_credit_body(al2::uuid); b2 := public.qbo_opening_credit_body(al5::uuid);
  perform pg_temp.chk('E2 wait · needs — al2(INV1 일감 queued) wait_job = INV1 일감 · 글 · al5(손님 B 짝 없음) needs 1 customer · CustomerRef 없음',
    (b->>'wait_job' = pg_temp.get('jinv1'))::text || ' ' || (b->>'wait_reason') || ' | ' || jsonb_array_length(b2->'needs')::text || ' ' || (b2->'needs'->0->>'kind') || ' ' || (b2->'needs'->0->>'ims_id') || ' ' || (b2->'body' ? 'CustomerRef')::text,
    'true waiting for invoice 9973001 to reach QuickBooks first | 1 customer c3e30000-0000-4000-8000-00000000000b false');
  perform pg_temp.chk('E3 몸 거부 글 — al3 이월 인보이스 · al4 since 전 · al6 매장 다름(청구처 H 의 돈 · 매장 S 인보이스 · QBO 하위 손님 아님)',
    pg_temp.try(format('select public.qbo_opening_credit_body(%L)::text', al3)) || ' | ' || pg_temp.try(format('select public.qbo_opening_credit_body(%L)::text', al4)) || ' | ' || pg_temp.try(format('select public.qbo_opening_credit_body(%L)::text', al6)),
    'ERR P0001: Invoice 9973003 was carried over from the previous system and has no QuickBooks match yet — match it under Settings → QuickBooks → Opening invoices; this opening credit then goes by itself — nothing was sent | ERR P0001: Invoice 9973006 was issued before the QuickBooks start date and has no QuickBooks match — match it under Settings → QuickBooks → Opening invoices — nothing was sent | ERR P0001: Opening credit OC-9973005-1 → 9973005 belongs to customer QBO2E3 Head H but invoice 9973005 is for store QBO2E3 Store S — the opening credit belongs to another customer than the invoice store: detach it, or in QuickBooks make the store a sub-customer (bill with parent) of that customer, refresh the customer list under Settings → QuickBooks matching, then retry — nothing was sent');
  update public.qbo_entity e set parent_id = 'C-2E3-H' where e.realm_id = pg_temp.get('realm') and e.qbo_type = 'Customer' and e.qbo_id = 'C-2E3-S';                   -- 빠져나오는 길: QBO 에서 S 를 H 의 하위 손님으로 → 목록 새로 받음
  b := public.qbo_opening_credit_body(al6::uuid); b2 := public.qbo_opening_apply_body(al6::uuid);
  perform pg_temp.chk('E4 하위 손님 길 — S 의 parent_id = C-2E3-H 가 되면 al6 credit 몸은 CustomerRef C-2E3-H + 경고 · apply 몸도 같은 울타리(경고 · wait 는 자기 CreditMemo)',
    (b->'body'->'CustomerRef'->>'value') || ' ' || (b->'warnings'->>0) || ' | ' || (b2->'body'->'CustomerRef'->>'value') || ' ' || (b2->'warnings'->>0) || ' ' || (b2->>'wait_reason'),
    'C-2E3-H invoice 9973005 is for store QBO2E3 Store S, a QuickBooks sub-customer of QBO2E3 Head H — the credit memo is written on the parent customer | C-2E3-H invoice 9973005 is for store QBO2E3 Store S, a QuickBooks sub-customer of QBO2E3 Head H waiting for credit memo OC-9973005-1 to reach QuickBooks first');
  b := public.qbo_opening_apply_body(al1::uuid);
  perform pg_temp.chk('E5 al1 apply 몸(CreditMemo 아직) — wait_job = al1 opening_credit 일감 · 글 · Line 0 · void 몸 둘은 「never sent」',
    (b->>'wait_job' = pg_temp.job('opening_credit', al1)::text)::text || ' ' || (b->>'wait_reason') || ' ' || (b->>'line_count') || ' | ' || pg_temp.try(format('select public.qbo_opening_apply_void_body(%L)::text', al1)) || ' | ' || pg_temp.try(format('select public.qbo_opening_credit_void_body(%L)::text', al1)),
    'true waiting for credit memo OC-9973002-1 to reach QuickBooks first 0 | ERR P0001: Opening credit application OC-9973002-1 → 9973002 was never sent to QuickBooks — nothing to void | ERR P0001: Opening credit OC-9973002-1 → 9973002 was never sent to QuickBooks — nothing to void');
  select a.id::text into p1a from public.so_payment_alloc a where a.payment_id = p1::uuid and a.voided_at is null;
  perform pg_temp.chk('E6 이월 아닌 결제 붙임은 이 갈래를 안 탄다 — sync not_applicable · 몸 거부 · 결제 지문(2e-1b) 그대로',
    (public.qbo_opening_alloc_sync(p1a::uuid, null)->>'action') || ' | ' || pg_temp.try(format('select public.qbo_opening_credit_body(%L)::text', p1a)) || ' | ' || (public.qbo_payment_fingerprint(p1::uuid) is not null)::text,
    'not_applicable | ERR P0001: Payment 2E3-P1 is not money carried over from the previous system — it goes to QuickBooks as a Payment, not as an opening credit — nothing was sent | true');
end $$;

-- ── F) claim · done(두 장) · 대조 · 떼기 셋 · 1013 · 재붙임 번호 · 취소 ──
do $$
declare al1 text := pg_temp.get('al1'); al2 text := pg_temp.get('al2'); al7 text := pg_temp.get('al7'); al9 text := pg_temp.get('al9'); al10 text; ca2 public.so_credit_alloc%rowtype; v jsonb; d jsonb; b jsonb; v_t text; v_jc uuid;
begin
  -- F1 CreditMemo 보내기: claim al1 credit → done → txn opening_credit · apply 가 queued 로 풀린다
  v := pg_temp.claim($k$'opening_credit', 'opening_apply'$k$, pg_temp.job('opening_credit', al1));
  d := pg_temp.done(pg_temp.job('opening_credit', al1), 'CM-2E3-1', 'OC-9973002-1', 3, 0, null);
  perform pg_temp.chk('F1 al1 credit claim · done(TotalAmt 3 · tax 0) — claimed 1 · jobs[0] kind · doc_number · sent · txn opening_credit CreditMemo CM-2E3-1 OC-9973002-1 3 0 sent · mismatch null · unblocked 1 · reconcile none · apply queued',
    (v->>'claimed') || ' ' || (v->'jobs'->0->>'kind') || ' ' || (v->'jobs'->0->>'doc_number') || ' | ' || (d->>'state') || ' ' || coalesce(d->>'mismatch', 'null') || ' ' || (d->>'unblocked') || ' ' || (d->'reconcile'->>'action') || ' | ' || (select t.ims_kind || ' ' || t.qbo_type || ' ' || t.qbo_id || ' ' || t.doc_number || ' ' || trim_scale(t.total_amt)::text || ' ' || trim_scale(t.total_tax)::text || ' ' || t.source from public.qbo_txn t where t.ims_kind = 'opening_credit' and t.ims_id = al1) || ' | ' || pg_temp.jobs(al1),
    '1 opening_credit OC-9973002-1 | sent null 1 none | opening_credit CreditMemo CM-2E3-1 OC-9973002-1 3 0 sent | opening_credit:sent,opening_apply:queued');
  -- F2 0 원 Payment: 몸(Line 둘 · check_lines) → claim → done(0 · 0) → txn opening_alloc · reconcile same
  b := public.qbo_opening_apply_body(al1::uuid);
  v := pg_temp.claim($k$'opening_credit', 'opening_apply'$k$, pg_temp.job('opening_apply', al1));
  d := pg_temp.done(pg_temp.job('opening_apply', al1), 'PAY-2E3-1', 'OC-9973002-1 → 9973002', 0, null, 0);
  perform pg_temp.chk('F2 al1 apply 몸 · claim · done — wait null · Line 둘(Invoice INV-2E3-2 · CreditMemo CM-2E3-1 · 3) · check_lines(txn_type · credit_number OC · qbo_creditmemo_id) · lookup private_note · TotalAmt 0 · claimed 1 · sent · txn opening_alloc Payment PAY-2E3-1 0 · reconcile same',
    coalesce(b->>'wait_job', 'null') || ' ' || (b->'body'->'Line'->0->'LinkedTxn'->0->>'TxnId') || ' ' || (b->'body'->'Line'->0->'LinkedTxn'->0->>'TxnType') || ' ' || (b->'body'->'Line'->1->'LinkedTxn'->0->>'TxnId') || ' ' || (b->'body'->'Line'->1->'LinkedTxn'->0->>'TxnType') || ' ' || (b->'body'->'Line'->1->>'Amount') || ' | ' || (b->'check_lines'->1->>'txn_type') || ' ' || (b->'check_lines'->1->>'credit_number') || ' ' || (b->'check_lines'->1->>'qbo_creditmemo_id') || ' ' || (b->'check_lines'->0->>'qbo_invoice_id') || ' | ' || (b->'lookup'->>'private_note' = 'IMS opening credit applied ' || al1)::text || ' ' || (b->'body'->>'TotalAmt') || ' ' || (b->'body' ?| array['PaymentMethodRef', 'DepositToAccountRef', 'PaymentRefNum'])::text
    || ' | ' || (v->>'claimed') || ' ' || (d->>'state') || ' ' || (d->'reconcile'->>'action') || ' ' || (select t.ims_kind || ' ' || t.qbo_type || ' ' || t.qbo_id || ' ' || trim_scale(t.total_amt)::text || ' ' || t.doc_number from public.qbo_txn t where t.ims_kind = 'opening_alloc' and t.ims_id = al1),
    'null INV-2E3-2 Invoice CM-2E3-1 CreditMemo 3 | CreditMemo OC-9973002-1 CM-2E3-1 INV-2E3-2 | true 0 false | 1 sent same opening_alloc Payment PAY-2E3-1 0 OC-9973002-1 → 9973002');
  -- F3 대조: al7 credit done 에 TotalAmt 2(IMS 1) → sent + mismatch
  v := pg_temp.claim($k$'opening_credit'$k$, pg_temp.job('opening_credit', al7));
  d := pg_temp.done(pg_temp.job('opening_credit', al7), 'CM-2E3-7', 'OC-9973007-1', 2, 0, null);
  perform pg_temp.chk('F3 al7 credit done(TotalAmt 2 ≠ 1) — sent · mismatch 글 · warning = txn.mismatch', (d->>'state') || ' | ' || (d->>'mismatch') || ' | ' || (select (j.warning = t.mismatch)::text from public.qbo_job j join public.qbo_txn t on t.ims_kind = 'opening_credit' and t.ims_id = j.ims_id where j.ims_id = al7 and j.kind = 'opening_credit'),
    'sent | QuickBooks total 2 / tax 0 differs from IMS 1 / 0 — check opening credit OC-9973007-1 → 9973007 in QuickBooks (942) | true');
  -- F4 둘 다 sent 뒤 떼기 → apply_void queued → credit_void blocked_by · 1013(크레딧 붙임이 그 void 를 기다린다) · void 몸 둘 · claim · done 차례 · reconcile
  perform pg_temp.detach(al1);
  ca2 := public.so_credit_alloc_add('33e30000-0000-4000-8000-000000000002'::uuid, '13e30000-0000-4000-8000-000000000002'::uuid, 2, 'manual', 'e3e30000-0000-4000-8000-00000000000a'::uuid, null);   -- CR2 → INV2 새 붙임(1013 확인 · CR1 은 이미 INV2 에 붙어 있다)
  b := public.qbo_credit_apply_body(ca2.id);
  perform pg_temp.chk('F4 al1 떼기(둘 다 sent) — opening_apply_void queued(note) · opening_credit_void blocked_by 그것(note) · 1013: 새 크레딧 붙임 CR-99932 → INV2 의 몸은 그 apply_void 를 기다린다(글 「opening credit OC-9973002-1」)',
    pg_temp.jobs(al1) || ' | ' || (select (j.note like '%detached — void the zero payment%')::text from public.qbo_job j where j.id = pg_temp.job('opening_apply_void', al1)) || ' ' || (select (j.blocked_by = pg_temp.job('opening_apply_void', al1))::text || ' ' || j.note from public.qbo_job j where j.id = pg_temp.job('opening_credit_void', al1))
    || ' | ' || (b->>'wait_job' = pg_temp.job('opening_apply_void', al1)::text)::text || ' ' || (b->>'wait_reason'),
    'opening_credit:sent,opening_apply:sent,opening_apply_void:queued,opening_credit_void:blocked | true true void the credit memo after the zero payment is voided | true waiting for the void of opening credit OC-9973002-1 on invoice 9973002 to reach QuickBooks first (that job is queued)');
  b := public.qbo_opening_apply_void_body(al1::uuid);
  v := pg_temp.claim($k$'opening_apply_void', 'opening_credit_void'$k$, pg_temp.job('opening_apply_void', al1));
  d := pg_temp.done(pg_temp.job('opening_apply_void', al1), 'PAY-2E3-1', 'OC-9973002-1 → 9973002', null, null, null);
  perform pg_temp.chk('F5 apply_void 몸(Id PAY-2E3-1 · SyncToken 0 · sparse · lookup) · claim 1 · done — sent · txn opening_alloc voided · unblocked 1(credit_void → queued) · reconcile void',
    (b->'body'->>'Id') || ' ' || (b->'body'->>'SyncToken') || ' ' || (b->'body'->>'sparse') || ' ' || (b->'lookup'->>'private_note' = 'IMS opening credit applied ' || al1)::text || ' | ' || (v->>'claimed') || ' ' || (d->>'state') || ' ' || (d->>'unblocked') || ' ' || (d->'reconcile'->>'action') || ' | ' || (select (t.voided_at is not null)::text from public.qbo_txn t where t.ims_kind = 'opening_alloc' and t.ims_id = al1) || ' ' || pg_temp.jobs(al1),
    'PAY-2E3-1 0 true true | 1 sent 1 void | true opening_credit:sent,opening_apply:sent,opening_apply_void:sent,opening_credit_void:queued');
  b := public.qbo_opening_credit_void_body(al1::uuid);
  v := pg_temp.claim($k$'opening_apply_void', 'opening_credit_void'$k$, pg_temp.job('opening_credit_void', al1));
  d := pg_temp.done(pg_temp.job('opening_credit_void', al1), 'CM-2E3-1', 'OC-9973002-1', null, null, null);
  perform pg_temp.chk('F6 credit_void 몸(Id CM-2E3-1 · SyncToken 0 · sparse 없음 · 2c 꼴) · claim 1 · done — sent · txn opening_credit voided · reconcile none',
    (b->'body'->>'Id') || ' ' || (b->'body'->>'SyncToken') || ' ' || (b->'body' ? 'sparse')::text || ' ' || (b->>'doc_number') || ' | ' || (v->>'claimed') || ' ' || (d->>'state') || ' ' || (d->'reconcile'->>'action') || ' | ' || (select (t.voided_at is not null)::text from public.qbo_txn t where t.ims_kind = 'opening_credit' and t.ims_id = al1),
    'CM-2E3-1 0 false OC-9973002-1 | 1 sent none | true');
  -- F7 재붙임 → 새 행 = 새 번호 OC-9973002-2(void 된 1 을 센다) · 두 일감
  al10 := pg_temp.attach('43e30000-0000-4000-8000-00000000000a', '13e30000-0000-4000-8000-000000000002', 1);
  perform pg_temp.put('al10', al10);
  perform pg_temp.chk('F7 al1 떼고 다시 붙임(al10) — DocNumber OC-9973002-2 · 두 일감 새로', public.qbo_opening_doc_number(al10::uuid) || ' | ' || pg_temp.jobs(al10), 'OC-9973002-2 | opening_credit:queued,opening_apply:blocked');
  -- F8 안 보낸 붙임 떼기(al2) → 둘 다 skipped · F9 보내는 중 떼기(al9 credit sending) → credit_void blocked_by 그 일감 · apply skipped → done 이 void 를 푼다
  perform pg_temp.detach(al2);
  v := pg_temp.claim($k$'opening_credit'$k$, pg_temp.job('opening_credit', al9));
  perform pg_temp.detach(al9);
  v_jc := pg_temp.anyjob('opening_credit', al9);
  d := pg_temp.done(v_jc, 'CM-2E3-9', 'OC-9973004-1', 2, 0, null);
  perform pg_temp.chk('F8 · F9 — al2 떼기 → credit · apply skipped(「detached before sending」) / al9 sending 중 떼기 → credit_void blocked_by 그 일감 · apply skipped → done 뒤 credit sent · void queued · reconcile void',
    pg_temp.jobs(al2) || ' ' || (select count(*)::text from public.qbo_job j where j.ims_id = al2 and j.note like '%opening credit detached before sending%') || ' | ' || (v->>'claimed') || ' ' || (select (j.blocked_by = v_jc)::text || ' ' || j.note from public.qbo_job j where j.ims_id = al9 and j.kind = 'opening_credit_void') || ' | ' || (d->>'state') || ' ' || (d->>'unblocked') || ' ' || (d->'reconcile'->>'action') || ' ' || pg_temp.jobs(al9),
    'opening_credit:skipped,opening_apply:skipped 2 | 1 true detached while sending — void after the send settles | sent 1 void opening_credit:sent,opening_apply:skipped,opening_credit_void:queued');
  -- F10 CreditMemo sent · Payment 아직 → 떼기(al7): apply skipped 「only the void goes」 + credit_void queued
  perform pg_temp.detach(al7);
  perform pg_temp.chk('F10 al7(credit sent · apply 아직) 떼기 — apply skipped(「only the void goes」) · credit_void queued(note)', pg_temp.jobs(al7) || ' | ' || (select (j.note like '%only the void goes%')::text from public.qbo_job j where j.ims_id = al7 and j.kind = 'opening_apply') || ' ' || (select (j.note like '%void the credit memo in QuickBooks%')::text from public.qbo_job j where j.id = pg_temp.job('opening_credit_void', al7)),
    'opening_credit:sent,opening_apply:skipped,opening_credit_void:queued | true true');
  -- F11 인보이스 취소(INV4 · auto 붙임 al10? 아니 — al9 는 떼었다 · 새 auto 붙임 만들어 둘 다 보낸 뒤 취소) → 붙임 void → apply_void queued · credit_void blocked · invoice_void queued
  declare ca3 public.so_payment_alloc%rowtype; al11 text; begin
    ca3 := public.so_payment_alloc_add('43e30000-0000-4000-8000-00000000000a'::uuid, '13e30000-0000-4000-8000-000000000004'::uuid, 1, 'auto_balance', 'e3e30000-0000-4000-8000-00000000000a'::uuid); al11 := ca3.id::text;
    v := pg_temp.claim($k$'opening_credit'$k$, pg_temp.job('opening_credit', al11)); d := pg_temp.done(pg_temp.job('opening_credit', al11), 'CM-2E3-11', 'OC-9973004-2', 1, 0, null);
    v := pg_temp.claim($k$'opening_apply'$k$, pg_temp.job('opening_apply', al11)); d := pg_temp.done(pg_temp.job('opening_apply', al11), 'PAY-2E3-11', 'OC-9973004-2 → 9973004', 0, null, 0);
    perform pg_temp.fulfill('13e30000-0000-4000-8000-000000000004'::uuid);
    v_t := pg_temp.bk($q$ select (public.so_invoice_cancel('13e30000-0000-4000-8000-000000000004', 'test cancel'))->>'invoice_id' $q$);
    perform pg_temp.chk('F11 인보이스 취소(INV4 · auto 붙임 al11 둘 다 sent) — 붙임 void → apply_void queued · credit_void blocked · invoice_void queued · 인보이스 cancelled',
      v_t || ' | ' || pg_temp.jobs(al11) || ' | ' || pg_temp.jobs('13e30000-0000-4000-8000-000000000004') || ' | ' || (select i.status from public.so_invoice i where i.id = '13e30000-0000-4000-8000-000000000004') || ' ' || (select (a.voided_at is not null)::text from public.so_payment_alloc a where a.id = al11::uuid),
      '13e30000-0000-4000-8000-000000000004 | opening_credit:sent,opening_apply:sent,opening_apply_void:queued,opening_credit_void:blocked | invoice:sent,invoice_void:queued | cancelled true');
  end;
end $$;

-- ── G) requeue · retry · list · doc · preview · 기본 kinds ──
do $$
declare al1 text := pg_temp.get('al1'); al2 text := pg_temp.get('al2'); al3 text := pg_temp.get('al3'); al4 text := pg_temp.get('al4'); al5 text := pg_temp.get('al5'); al7 text := pg_temp.get('al7'); al10 text := pg_temp.get('al10'); p1 text := pg_temp.get('p1'); v jsonb; ls jsonb; pv jsonb; v_n int; v_t text;
begin
  v := pg_temp.claim($k$'opening_credit'$k$, pg_temp.job('opening_credit', al3));                                                     -- 이월 인보이스 → failed
  v_n := public.qbo_payment_requeue('13e30000-0000-4000-8000-000000000003'::uuid);
  perform pg_temp.chk('G1 requeue(INV3 이월) — al3 credit claim 은 failed(carried over) → requeue 1(결제 0 + 이월 붙임 1) · queued + note', (v->>'body_failed') || ' ' || v_n::text || ' ' || (select j.state || ' ' || (j.note like 'sent again: invoice 9973003 is now matched%')::text from public.qbo_job j where j.id = pg_temp.job('opening_credit', al3)), '1 1 queued true');
  v := pg_temp.claim($k$'opening_credit'$k$, pg_temp.job('opening_credit', al4));                                                     -- since 전 → failed
  perform pg_temp.chk('G2 retry 규칙 — al4 credit(failed · 활성) OK queued · al2 credit(skipped · 떼임) 거부 · al1 apply_void(sent) 는 상태로 거부 · al7 credit_void(queued) 상태로 거부 · al10 apply(blocked) 상태로 거부',
    pg_temp.bk(format('select (public.qbo_job_retry(%L, ''later''))->>''state''', pg_temp.job('opening_credit', al4))) || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', pg_temp.anyjob('opening_credit', al2))) || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', pg_temp.anyjob('opening_apply_void', al1))) || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', pg_temp.job('opening_credit_void', al7))) || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', pg_temp.job('opening_apply', al10))),
    'queued | ERR P0001: Opening credit OC-9973001-1 → 9973001 was detached — nothing to send (a void job takes care of QuickBooks) — nothing was saved | ERR P0001: Only a failed or skipped job, or one whose result is unknown, can be sent again (this one is sent) — nothing was saved | ERR P0001: Only a failed or skipped job, or one whose result is unknown, can be sent again (this one is queued) — nothing was saved | ERR P0001: Only a failed or skipped job, or one whose result is unknown, can be sent again (this one is blocked) — nothing was saved');
  update public.qbo_job set state = 'failed', last_error = 'test: refused' where id = pg_temp.job('opening_credit_void', al7);
  update public.qbo_job set state = 'failed', last_error = 'test: refused' where id = pg_temp.job('opening_apply', al10);
  perform pg_temp.chk('G3 retry 규칙(failed 로 만들고) — al7 credit_void(CreditMemo 서 있음 · 떼임) OK queued · al10 apply(CreditMemo 아직 · 활성) OK queued(몸이 기다린다)',
    pg_temp.bk(format('select (public.qbo_job_retry(%L, ''ok''))->>''state''', pg_temp.job('opening_credit_void', al7))) || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''ok''))->>''state''', pg_temp.job('opening_apply', al10))),
    'queued | queued');
  ls := pg_temp.bk($q$ select public.qbo_job_list(null, array['opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void'], null, null, 'OC-9973', 50, 0)::text $q$)::jsonb;
  perform pg_temp.chk('G4 list(kinds 넷 · q OC-9973) — 가짜 줄 수 = DB 일감 수 · al1 의 apply_void 줄 txn = PAY-2E3-1(voided) · credit_void 줄 txn = CM-2E3-1(voided)(kind 로 갈라 잇기 · 줄 중복 없음) · doc(번호 · 돈의 주인 · CAD 3 · 오늘 · voided) · ims_name',
    (select count(*)::text from jsonb_array_elements(ls->'rows') r) || '=' || pg_temp.fake_oa_jobs()::text
    || ' | ' || (select (r->>'txn_qbo_id') || ' ' || (r->>'txn_voided_at' is not null)::text from jsonb_array_elements(ls->'rows') r where r->>'ims_id' = al1 and r->>'kind' = 'opening_apply_void') || ' | ' || (select (r->>'txn_qbo_id') || ' ' || (r->>'txn_voided_at' is not null)::text from jsonb_array_elements(ls->'rows') r where r->>'ims_id' = al1 and r->>'kind' = 'opening_credit_void')
    || ' | ' || (select (r->>'doc_number') || ' ' || (r->>'name') || ' ' || (r->>'currency') || ' ' || (r->>'total') || ' ' || (r->>'doc_date') || ' ' || (r->>'doc_status') || ' | ' || (r->>'ims_name') from jsonb_array_elements(ls->'rows') r where r->>'ims_id' = al1 and r->>'kind' = 'opening_credit'),
    pg_temp.fake_oa_jobs()::text || '=' || pg_temp.fake_oa_jobs()::text
    || ' | PAY-2E3-1 true | CM-2E3-1 true | OC-9973002-1 → 9973002 QBO2E3 Store A CAD 3 ' || pg_temp.get('today') || ' voided | OC-9973002-1 → 9973002 · QBO2E3 Store A · CAD 3');
  pv := pg_temp.bk(format('select public.qbo_job_preview(%L)::text', pg_temp.job('opening_apply', al5)))::jsonb;
  perform pg_temp.chk('G5 doc · preview · kinds 검사 — qbo_job_doc(opening_alloc al1) · 모르는 id null · preview(al5 apply · blocked_by kind opening_credit · needs 1(손님 B) · sendable false · doc) · list kinds 검사 14 · claim 기본 kinds 그대로',
    (public.qbo_job_doc('opening_alloc', al1)->>'doc_number') || ' ' || (public.qbo_job_doc('opening_alloc', al1)->>'doc_status') || ' | ' || coalesce(public.qbo_job_doc('opening_alloc', gen_random_uuid()::text)::text, 'null') || ' | ' || (pv->'blocked_by'->>'kind') || ' ' || jsonb_array_length(pv->'needs')::text || ' ' || (pv->'needs'->0->>'ims_id') || ' ' || (pv->>'sendable') || ' ' || (pv->'doc'->>'doc_number') || ' | ' || pg_temp.bk($q$ select (public.qbo_job_list(null, array['bogus']))->>'kinds' $q$) || ' | ' || pg_temp.svc($q$ select (public.qbo_job_claim(5))->>'kinds' $q$),
    'OC-9973002-1 → 9973002 voided | null | opening_credit 1 c3e30000-0000-4000-8000-00000000000b false OC-9973008-1 → 9973008 | ERR P0001: kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void (got {bogus}) | ["customer", "item"]');
  perform pg_temp.chk('G6 qbo_link_set 의 다른 kind 는 그대로 — payment_method 가지 무변(cash → 실물 수단 짝이 있으면 requeued 숫자만) · charge 가 acct: 가 아니면 requeue 0', (select (prosrc like '%qbo_payment_method_requeue(p_ims_id, v_staff)%' and prosrc like '%qbo_opening_credit_requeue(substr(p_ims_id, 6), v_staff)%')::text from pg_proc where proname = 'qbo_link_set' and pronamespace = 'public'::regnamespace), 'true');
  perform pg_temp.chk('F1′ 바뀐 함수 = 재발행 열하나 + 새 함수(t_pre 에 없음) · 그 밖 무변', (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5), case when pg_temp.get('mig') = 'true' then 'qbo_credit_apply_body,qbo_ims_rows,qbo_job_claim,qbo_job_doc,qbo_job_done,qbo_job_list,qbo_job_on_payment_alloc,qbo_job_preview,qbo_job_retry,qbo_link_set,qbo_payment_requeue' else '(none)' end);
end $$;

\echo '── 결과'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback, :'t_fixtures'::timestamptz - :'t_begin'::timestamptz as fixtures, :'t_mig'::timestamptz - :'t_fixtures'::timestamptz as mig_file, clock_timestamp() - :'t_mig'::timestamptz as mig_end_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.customer) = :n_cust0 as customer_same, (select count(*) from public.product) = :n_prod0 as product_same,
       (select count(*) from public.so) = :n_so0 as so_same, (select count(*) from public.so_invoice) = :n_inv0 as invoice_same, (select count(*) from public.so_credit) = :n_cr0 as credit_same, (select count(*) from public.so_payment_alloc) = :n_palloc0 as palloc_same, (select count(*) from public.so_payment) = :n_pay0 as payment_same,
       (select count(*) from public.qbo_job) = :n_job0 as job_same, (select count(*) from public.qbo_txn) = :n_txn0 as txn_same, (select count(*) from public.qbo_link) = :n_link0 as link_same, (select count(*) from public.qbo_entity) = :n_ent0 as entity_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
