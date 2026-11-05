-- supabase/tests/qbo_sync_2e1d_1_check.sql — qbo-sync-2e-1d-1 검증: 착지(칸 · CHECK · 표 · ACL · nowhere · 무변) · 자동 짝(다섯 조건 · 까닭 여섯 · 부모 CustomerRef · 두 번 적힘 경고) · 되살리기(「모두 섰을 때만」 · 남은 장 글 · 일감 없는 결제 · 크레딧 붙임 blocked) · 멱등 · 사람 짝(p_ack · 같은 QBO Id 거부) · 풀기(보낸 것 거부 · sent 행 거부 · queued → failed · 다시 짝) · 수단 되살리기(속 · 판정 1039) · 목록 · 권한(열쇠 셋 · anon · service_role) · link_set 재발행 (2026-11-05)
-- [테스트 · Asung-IMS = IMS 메인] 시험 적용 장치 틀 — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback · ⚠️ 토론토 17:00 뒤 · 10 초 안 · 결제 · 붙임 트리거는 DEFERRED — `set constraints all immediate` 로 당겨 쏜다
--   Claude Code(시험): MIG=supabase/migrations/<번호>_qbo_sync_2e1d_1_opening_match.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2e1d_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 차이는 G0 만 · 기대 OK 수는 EXPECT_OK
--   쓰기: 가짜 직원 3(bk qbo · ro qbo:read · nn 없음) · 손님 4(A 짝 · P 부모 짝 · K 자식 짝(QBO 부모 P) · U 짝 없음) · qbo_entity Customer 4 · 이월 인보이스 17(9980001 ~ 17 · 번호 시퀀스 무접촉) · 결제 5(so_payment_add) · 크레딧 1(CR-99801 직접) · 붙임 1 · 전부 rollback · QBO 호출 0 · 실물 행 무접촉(수단 짝 실물 링크는 건드리지 않는다 — 수단 되살리기는 속 함수 qbo_payment_method_requeue 로)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 28
\else
\set EXPECT_OK 28
\endif
\pset pager off
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo\_%' or p.proname like 'so\_%');
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.so_invoice) as n_inv0,
       (select count(*) from public.so_payment) as n_pay0, (select count(*) from public.so_payment_alloc) as n_palloc0, (select count(*) from public.so_credit) as n_cr0, (select count(*) from public.so_credit_alloc) as n_calloc0,
       (select count(*) from public.qbo_job) as n_job0, (select count(*) from public.qbo_txn) as n_txn0, (select count(*) from public.qbo_link) as n_link0, (select count(*) from public.qbo_entity) as n_ent0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as tor_id, (select id::text from public.ref_currency where code = 'CAD') as cad_id, public.ims_today()::text as today \gset
\if :{?mig}
\set n_rv0 0
\else
select count(*) as n_rv0 from public.qbo_opening_review \gset
\endif
\echo '── 기준: 함수' :n_fn '· job' :n_job0 '· txn' :n_txn0 '· link' :n_link0 '· review' :n_rv0 '· realm' :realm
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
create function pg_temp.bk(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"e1d00000-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
create function pg_temp.ro(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"e1d00000-0000-4000-8000-000000000002"}'::jsonb, p_sql) $$;
create function pg_temp.nn(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"e1d00000-0000-4000-8000-000000000003"}'::jsonb, p_sql) $$;
create function pg_temp.svc(p_sql text) returns text language sql as $$ select pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, p_sql) $$;
create function pg_temp.an(p_sql text) returns text language sql as $$ select pg_temp.as_conn('anon', '{"role":"anon"}'::jsonb, p_sql) $$;
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
create function pg_temp.jst(p_kind text, p_ims text) returns text language sql as $$ select coalesce((select j.state || ' | ' || coalesce(j.last_error, '-') || ' | ' || coalesce(j.note, '-') from public.qbo_job j where j.kind = p_kind and j.ims_id = p_ims order by j.created_at desc, j.id desc limit 1), '(none)') $$;
create function pg_temp.txn(p_inv text) returns text language sql as $$ select coalesce((select t.source || ' ' || t.match_how || ' ' || t.qbo_id || ' ' || coalesce(t.doc_number, '-') || ' ' || t.total_amt::text || ' bal=' || coalesce(t.match_snapshot->>'Balance', '-') || ' cust=' || coalesce(t.match_snapshot->>'CustomerRef', '-') || ' job=' || coalesce(t.job_id::text, 'null') || ' fp=' || coalesce(t.fingerprint, 'null') from public.qbo_txn t where t.ims_kind = 'invoice' and t.ims_id = p_inv and t.voided_at is null), '(none)') $$;
create function pg_temp.rv(p_inv text) returns text language sql as $$ select coalesce((select coalesce(r.reason, 'null') || ' | ' || coalesce(r.warning, '-') || ' | rows=' || jsonb_array_length(r.qbo_rows)::text || ' | unmatched=' || (r.unmatched_at is not null)::text from public.qbo_opening_review r where r.invoice_id = p_inv::uuid), '(none)') $$;
-- ── 가짜 직원 셋 · 손님 넷 · QBO 거울 넷 · 짝 셋 ──
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('e1d00000-0000-4000-8000-00000000000a', 'e1d00000-0000-4000-8000-000000000001', 'qbo-1d-bk@asung.invalid', 'QBO 1D Bookkeeper', 'manager', '["qbo", "sales"]'),
  ('e1d00000-0000-4000-8000-00000000000b', 'e1d00000-0000-4000-8000-000000000002', 'qbo-1d-ro@asung.invalid', 'QBO 1D Reader', 'manager', '["qbo:read", "sales"]'),
  ('e1d00000-0000-4000-8000-00000000000c', 'e1d00000-0000-4000-8000-000000000003', 'qbo-1d-nn@asung.invalid', 'QBO 1D Nobody', 'manager', '["sales"]');
insert into public.customer (id, name, is_active, source, currency_code) values
  ('c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', true, 'manual', 'CAD'), ('c1d00000-0000-4000-8000-000000000010', 'QBO1D Parent', true, 'manual', 'CAD'), ('c1d00000-0000-4000-8000-000000000012', 'QBO1D Unlinked', true, 'manual', 'CAD');
insert into public.customer (id, name, is_active, source, currency_code, parent_id, parent_source, default_bill_to_customer_id) values
  ('c1d00000-0000-4000-8000-000000000011', 'QBO1D Kid Store', true, 'manual', 'CAD', 'c1d00000-0000-4000-8000-000000000010', 'ims', 'c1d00000-0000-4000-8000-000000000010');
insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, parent_id, active, sync_token) values
  (:'realm', 'Customer', 'C-1D-A', 'QBO1D Store A', null, true, '0'), (:'realm', 'Customer', 'C-1D-P', 'QBO1D Parent', null, true, '0'), (:'realm', 'Customer', 'C-1D-K', 'QBO1D Kid Store', 'C-1D-P', true, '0'), (:'realm', 'Customer', 'C-1D-NEW', 'QBO1D New', null, true, '0');
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values
  (:'realm', 'customer', 'c1d00000-0000-4000-8000-00000000000a', 'Customer', 'C-1D-A', 'manual', 'QBO1D Store A'), (:'realm', 'customer', 'c1d00000-0000-4000-8000-000000000010', 'Customer', 'C-1D-P', 'manual', 'QBO1D Parent'),
  (:'realm', 'customer', 'c1d00000-0000-4000-8000-000000000011', 'Customer', 'C-1D-K', 'manual', 'QBO1D Kid Store');
create function pg_temp.mk_open(p_n int, p_bill uuid, p_bill_name text, p_store uuid, p_total numeric, p_prior numeric) returns void language plpgsql as $$
begin
  insert into public.so_invoice (id, invoice_number, kind, status, bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country, issued_on, store_customer_id, legacy_sale_id, legacy_invoice_id, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due, prior_settled)
  values (('11d00000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid, '99800' || lpad(p_n::text, 2, '0'), 'opening', 'issued', p_bill, p_bill_name, '1 Any St', 'Toronto', 'ON', 'M1M 1M1', 'CA', '2026-10-01', p_store, 'test-sale-1d-' || p_n, 'test-inv-1d-' || p_n,
          (select id from public.ref_currency where code = 'CAD'), 'CAD', p_total, p_total, 0, p_total, p_total, p_prior);   -- amount_due = total(so_invoice_due_ck · 실물 이월 17 장 모두 같다) · prior_settled 는 따로 · remaining 이 뺀다
end $$;
-- O1 ~ O3 A(결제 P1 셋) · O4 A prior 10.21(balance) · O5 A(QBO 두 장) · O6 K 매장 · 청구처 P(QBO CustomerRef = 부모 P) · O7 U 짝 없음 · O8 A(크레딧 붙임) · O9 A(사람 · DocNumber 다름) · O10 A(P10 sent → 풀기 거부) · O11 A(QBO total 36) · O12 A(P12 일감 없음) · O13 A(P13 queued → 풀기 → 다시 짝) · O14 A(같은 QBO Id 둘째) · O15 A(P15 credit_card 수단) · O16 A(CustomerRef 남) · O17 A(sent 행 풀기 거부)
select pg_temp.mk_open(1, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 100, 0), pg_temp.mk_open(2, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 50, 0), pg_temp.mk_open(3, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 30, 0),
       pg_temp.mk_open(4, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 40, 10.21), pg_temp.mk_open(5, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 60, 0),
       pg_temp.mk_open(6, 'c1d00000-0000-4000-8000-000000000010', 'QBO1D Parent', 'c1d00000-0000-4000-8000-000000000011', 70, 0), pg_temp.mk_open(7, 'c1d00000-0000-4000-8000-000000000012', 'QBO1D Unlinked', 'c1d00000-0000-4000-8000-000000000012', 20, 0),
       pg_temp.mk_open(8, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 80, 0), pg_temp.mk_open(9, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 15, 0),
       pg_temp.mk_open(10, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 25, 0), pg_temp.mk_open(11, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 35, 0),
       pg_temp.mk_open(12, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 45, 0), pg_temp.mk_open(13, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 55, 0),
       pg_temp.mk_open(14, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 65, 0), pg_temp.mk_open(15, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 75, 0),
       pg_temp.mk_open(16, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 85, 0), pg_temp.mk_open(17, 'c1d00000-0000-4000-8000-00000000000a', 'QBO1D Store A', 'c1d00000-0000-4000-8000-00000000000a', 95, 0);
insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, sent_at) values (:'realm', 'invoice', '11d00000-0000-4000-8000-000000000017', 'Invoice', 'INV-1D-17', '9980017', '0', 95, 0, now());
set constraints all immediate;
-- 결제 다섯(bk · so_payment_add · 트리거가 payment 일감 queued) · P12 는 일감을 지워 「일감 없음」 꼴 · 크레딧 CR-99801 → O8 붙임(credit_apply queued · 부모 credit 일감 queued)
create function pg_temp.pay(p_amount numeric, p_method text, p_ref text, p_allocs jsonb) returns text language sql as $$
  select pg_temp.bk(format($q$ select (public.so_payment_add(%L::jsonb))->>'payment_id' $q$, jsonb_build_object('customer_id', 'c1d00000-0000-4000-8000-00000000000a', 'amount', p_amount, 'method', p_method, 'reference', p_ref, 'currency_code', 'CAD', 'warehouse_id', current_setting('t.tor', true), 'allocations', p_allocs)::text)) $$;
select set_config('t.tor', :'tor_id', true);
select pg_temp.pay(180, 'cash', '1D-P1', jsonb_build_array(jsonb_build_object('invoice_id', '11d00000-0000-4000-8000-000000000001', 'amount', 100), jsonb_build_object('invoice_id', '11d00000-0000-4000-8000-000000000002', 'amount', 50), jsonb_build_object('invoice_id', '11d00000-0000-4000-8000-000000000003', 'amount', 30))) as p1 \gset
select pg_temp.pay(25, 'cash', '1D-P10', jsonb_build_array(jsonb_build_object('invoice_id', '11d00000-0000-4000-8000-000000000010', 'amount', 25))) as p10 \gset
select pg_temp.pay(45, 'cash', '1D-P12', jsonb_build_array(jsonb_build_object('invoice_id', '11d00000-0000-4000-8000-000000000012', 'amount', 45))) as p12 \gset
select pg_temp.pay(55, 'cash', '1D-P13', jsonb_build_array(jsonb_build_object('invoice_id', '11d00000-0000-4000-8000-000000000013', 'amount', 55))) as p13 \gset
select pg_temp.pay(75, 'credit_card', '1D-P15', jsonb_build_array(jsonb_build_object('invoice_id', '11d00000-0000-4000-8000-000000000015', 'amount', 75))) as p15 \gset
delete from public.qbo_job where ims_kind = 'payment' and ims_id = :'p12';
insert into public.so_credit (id, credit_number, status, customer_id, store_customer_id, currency_id, currency_code, invoice_id, ref_invoice_number, ref_order_number, reason, warehouse_id, warehouse_name, issued_on, issued_by, lines_amount, fee_amount, tax_amount, total, order_discount_amount, freight_discount_amount, surcharge_amount)
values ('31d00000-0000-4000-8000-000000000001', 'CR-99801', 'issued', 'c1d00000-0000-4000-8000-00000000000a', 'c1d00000-0000-4000-8000-00000000000a', :'cad_id', 'CAD', null, 'OLD-8', 'SO-OLD-8', 'customer_return', :'tor_id', 'Asung Trading Inc.', public.ims_today(), 'e1d00000-0000-4000-8000-00000000000a', 10, 0, 0, 10, 0, 0, 0);
select pg_temp.bk($q$ select (public.so_credit_attach('31d00000-0000-4000-8000-000000000001', '[{"invoice_id":"11d00000-0000-4000-8000-000000000008","amount":5}]'::jsonb))->'allocations'->0->>'alloc_id' $q$) as al8 \gset
select pg_temp.svc(format($q$ select (public.qbo_job_claim(50, array['payment', 'credit_apply'], array[%L, %L, %L, %L, %L]::uuid[]))->>'claimed' $q$, pg_temp.job('payment', :'p1'), pg_temp.job('payment', :'p10'), pg_temp.job('payment', :'p13'), pg_temp.job('payment', :'p15'), pg_temp.job('credit_apply', :'al8'))) as cl0 \gset
select pg_temp.chk('S0 준비 — 결제 넷 · 붙임 하나 claim(' || :'cl0' || ') → 몸이 이월 글로 failed · failed 넷의 일감 지문 null(실물 failed 11 장 꼴 — claim 은 몸이 성공할 때만 적는다) · 결제 지문은 있다 · P12 는 일감 없음 · credit 부모 일감 queued · 가짜 이월 17 장', (select string_agg(j.state, ',' order by j.ims_id) from public.qbo_job j where j.ims_id in (:'p1', :'p10', :'p13', :'p15', :'al8')) || ' | ' || pg_temp.jst('payment', :'p12') || ' | ' || (select j.state from public.qbo_job j where j.kind = 'credit' and j.ims_id = '31d00000-0000-4000-8000-000000000001')
  || ' | ' || (select left(j.last_error, 41) from public.qbo_job j where j.kind = 'payment' and j.ims_id = :'p1') || ' | ' || (select count(*)::text from public.so_invoice i where i.kind = 'opening' and i.invoice_number like '99800%')
  || ' | ' || (select string_agg((j.fingerprint is null)::text || '/' || (public.qbo_payment_fingerprint(j.ims_id::uuid) is not null)::text, ',' order by j.ims_id) from public.qbo_job j where j.kind = 'payment' and j.ims_id in (:'p1', :'p10', :'p13', :'p15')),
  'failed,failed,failed,failed,failed | (none) | queued | Invoice 9980001 was carried over from the | 17 | true/true,true/true,true/true,true/true');

-- ── A) 착지 ──
select pg_temp.chk('A1 qbo_txn.match_how · match_snapshot · qbo_txn_match_ck · qbo_opening_review(PK · reason CHECK · RLS · ACL 창구만 · touch) · UNIQUE 둘 그대로',
  (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum) from pg_attribute a where a.attrelid = 'public.qbo_txn'::regclass and a.attname in ('match_how', 'match_snapshot') and not a.attisdropped)
  || ' | ' || (select (pg_get_constraintdef(oid) ~ 'matched.*match_how.*auto.*manual.*match_snapshot IS NOT NULL.*job_id IS NULL')::text from pg_constraint where conname = 'qbo_txn_match_ck')
  || ' | ' || (select string_agg(conname || ':' || pg_get_constraintdef(oid), ' ' order by conname) from pg_constraint where conrelid = 'public.qbo_opening_review'::regclass and contype in ('p', 'c'))
  || ' | ' || (select relacl::text || ' rls=' || relrowsecurity::text from pg_class where oid = 'public.qbo_opening_review'::regclass) || ' | ' || (select count(*)::text from pg_trigger where tgrelid = 'public.qbo_opening_review'::regclass and tgname = 'qbo_opening_review_touch')
  || ' | ' || (select string_agg(conname, ',' order by conname) from pg_constraint where conrelid = 'public.qbo_txn'::regclass and contype = 'u'),
  'match_how:text,match_snapshot:jsonb | true | qbo_opening_review_pkey:PRIMARY KEY (realm_id, invoice_id) qbo_opening_review_reason_ck:CHECK (((reason IS NULL) OR (reason = ANY (ARRAY[''not_found''::text, ''many''::text, ''unlinked''::text, ''customer''::text, ''total''::text, ''balance''::text, ''docnumber''::text, ''taken''::text, ''unmatched''::text])))) | {postgres=arwdDxtm/postgres} rls=true | 1 | qbo_txn_ims_key,qbo_txn_qbo_key');
select pg_temp.chk('A2 ACL — 창구 넷 authenticated · 속 일곱 grant 0 · requeue grant 0 · link_set 그대로', (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_opening_candidates', 'qbo_opening_match', 'qbo_opening_unmatch', 'qbo_opening_list', 'qbo_opening_check', 'qbo_opening_record', 'qbo_opening_remaining', 'qbo_opening_slim', 'qbo_opening_num', 'qbo_payment_requeue_one', 'qbo_payment_method_requeue', 'qbo_payment_requeue', 'qbo_link_set')),
  'qbo_link_set={postgres=X/postgres,authenticated=X/postgres} qbo_opening_candidates={postgres=X/postgres,authenticated=X/postgres} qbo_opening_check={postgres=X/postgres} qbo_opening_list={postgres=X/postgres,authenticated=X/postgres} qbo_opening_match={postgres=X/postgres,authenticated=X/postgres} qbo_opening_num={postgres=X/postgres} qbo_opening_record={postgres=X/postgres} qbo_opening_remaining={postgres=X/postgres} qbo_opening_slim={postgres=X/postgres} qbo_opening_unmatch={postgres=X/postgres,authenticated=X/postgres} qbo_payment_method_requeue={postgres=X/postgres} qbo_payment_requeue={postgres=X/postgres} qbo_payment_requeue_one={postgres=X/postgres}');
select pg_temp.chk('A3 nowhere — 새 · 재발행 열셋의 깊이 0 WHERE 없는 update · delete = 0 · 스캐너 자기 시험', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_opening_candidates', 'qbo_opening_match', 'qbo_opening_unmatch', 'qbo_opening_list', 'qbo_opening_check', 'qbo_opening_record', 'qbo_opening_remaining', 'qbo_opening_slim', 'qbo_opening_num', 'qbo_payment_requeue_one', 'qbo_payment_method_requeue', 'qbo_payment_requeue', 'qbo_link_set'))
  || ' | ' || pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then delete from t where id = 1; end if;')::text,
  'qbo_link_set=0 qbo_opening_candidates=0 qbo_opening_check=0 qbo_opening_list=0 qbo_opening_match=0 qbo_opening_num=0 qbo_opening_record=0 qbo_opening_remaining=0 qbo_opening_slim=0 qbo_opening_unmatch=0 qbo_payment_method_requeue=0 qbo_payment_requeue=0 qbo_payment_requeue_one=0 | 1010');
select pg_temp.chk('A4 무변 — 결제 몸 · sync · 크레딧 붙임 몸 · sync · claim · done 의 md5 · 재발행 둘은 바뀌고 새 가지가 든다 · 서명 하나씩', (select string_agg(left(md5(p.prosrc), 8), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_credit_alloc_sync', 'qbo_credit_apply_body', 'qbo_job_claim', 'qbo_job_done', 'qbo_payment_body', 'qbo_payment_sync'))
  || ' | ' || (select (md5(p.prosrc) <> '9a691814b021d4927d5d9b17179ab78d' and p.prosrc like '%qbo_payment_requeue_one(r.payment_id, r.created_by%' and p.prosrc like '%qbo_credit_alloc_sync(r.id, r.created_by)%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_payment_requeue')
  || ' ' || (select (md5(p.prosrc) <> '0fce741132f19fb9e76fb45ac56ff7e3' and p.prosrc like '%if p_kind = ''payment_method'' then v_rq := public.qbo_payment_method_requeue(p_ims_id, v_staff); end if;%' and p.prosrc like '%''requeued'', v_rq%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_link_set')
  || ' ' || (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_payment_requeue', 'qbo_link_set', 'qbo_opening_candidates', 'qbo_opening_match', 'qbo_opening_unmatch', 'qbo_opening_list')),
  '44419d3b 08b17e79 9c7890b8 fc2d42c0 e1aea518 9efb5d9f | true true 6');

-- ── B) 자동 짝 1 회차 — O1 · O4 · O5 · O6 · O7 · O9 · O11 · O16 ──
create function pg_temp.qrow(p_id text, p_num text, p_total numeric, p_bal numeric, p_cust text) returns jsonb language sql immutable as $$
  select jsonb_build_object('Id', p_id, 'DocNumber', p_num, 'TxnDate', '2026-10-01', 'TotalAmt', p_total, 'Balance', p_bal, 'CustomerRef', jsonb_build_object('value', p_cust, 'name', 'x'), 'SyncToken', '0', 'BillEmail', jsonb_build_object('Address', 'pii@asung.invalid')) $$;
select jsonb_build_array(pg_temp.qrow('Q-1D-1', '9980001', 100, 100, 'C-1D-A'), pg_temp.qrow('Q-1D-4', '9980004', 40, 40, 'C-1D-A'), pg_temp.qrow('Q-1D-5a', '9980005', 60, 60, 'C-1D-A'), pg_temp.qrow('Q-1D-5b', '9980005', 60, 60, 'C-1D-A'),
                        pg_temp.qrow('Q-1D-6', '9980006', 70, 70, 'C-1D-P'), pg_temp.qrow('Q-1D-7', '9980007', 20, 20, 'C-1D-A'), pg_temp.qrow('Q-1D-11', '9980011', 36, 36, 'C-1D-A'), pg_temp.qrow('Q-1D-16', '9980016', 85, 85, 'C-1D-K'))::text as r1 \gset
select pg_temp.bk(format($q$ select public.qbo_opening_candidates(%L::text[], %L::jsonb)::text $q$, '{9980001,9980004,9980005,9980006,9980007,9980009,9980011,9980016}', :'r1')) as c1 \gset
select pg_temp.chk('B1 candidates 1 회차 — checked 8 · matched 2(O1 · O6 부모 CustomerRef) · review_changed 6 · already 0 · same 0 · unknown 0', (:'c1'::jsonb->>'checked') || ' ' || (:'c1'::jsonb->>'matched') || ' ' || (:'c1'::jsonb->>'review_changed') || ' ' || (:'c1'::jsonb->>'already') || ' ' || (:'c1'::jsonb->>'review_same') || ' ' || (:'c1'::jsonb->>'unknown_numbers') || ' ' || (:'c1'::jsonb->>'taken'), '8 2 6 0 0 0 0');
select pg_temp.chk('B2 O1 qbo_txn — matched auto Q-1D-1 · doc_number · total 100 · snapshot Balance 100 · CustomerRef · job null · fp null · PII 칸 없음 · review reason null', pg_temp.txn('11d00000-0000-4000-8000-000000000001') || ' | ' || (select (t.match_snapshot ? 'BillEmail')::text || ' ' || (t.updated_by = 'e1d00000-0000-4000-8000-00000000000a')::text from public.qbo_txn t where t.ims_id = '11d00000-0000-4000-8000-000000000001') || ' | ' || pg_temp.rv('11d00000-0000-4000-8000-000000000001'),
  'matched auto Q-1D-1 9980001 100 bal=100 cust=C-1D-A job=null fp=null | false true | null | - | rows=1 | unmatched=false');
select pg_temp.chk('B3 O6 — CustomerRef = 청구처 P 자체 · (K 매장 짝 C-1D-K 의 qbo_entity 부모도 C-1D-P) → matched auto', pg_temp.txn('11d00000-0000-4000-8000-000000000006'), 'matched auto Q-1D-6 9980006 70 bal=70 cust=C-1D-P job=null fp=null');
select pg_temp.chk('B4 사람 목록 여섯 — O4 balance(두 번 적힘 경고) · O5 many · O7 unlinked · O9 not_found(rows 0) · O11 total · O16 customer', (select string_agg(i.invoice_number || ':' || r.reason || ':' || jsonb_array_length(r.qbo_rows)::text, ' ' order by i.invoice_number) from public.qbo_opening_review r join public.so_invoice i on i.id = r.invoice_id where i.invoice_number like '99800%')
  || ' | ' || (select (r.warning like '%balance 40 differs from what IMS expects (29.79)%twice%')::text from public.qbo_opening_review r where r.invoice_id = '11d00000-0000-4000-8000-000000000004')
  || ' | ' || (select r.warning from public.qbo_opening_review r where r.invoice_id = '11d00000-0000-4000-8000-000000000016'),
  '9980004:balance:1 9980005:many:2 9980007:unlinked:1 9980009:not_found:0 9980011:total:1 9980016:customer:1 | true | QuickBooks invoice #Q-1D-16 belongs to customer C-1D-K — not this invoice''s store, bill-to customer, or their parent');
select pg_temp.chk('B5 P1(이월 셋 중 한 장 짝) — failed 그대로 · 글 「2 carried-over invoice(s) …」 · remaining 2', pg_temp.jst('payment', :'p1') || ' | ' || public.qbo_opening_remaining(:'p1'::uuid)::text,
  'failed | 2 carried-over invoice(s) on this payment still have no QuickBooks match — match them under Settings → QuickBooks → Opening invoices and the payment then goes by itself | - | 2');
select pg_temp.chk('B6 수단 되살리기(cash) — P1 은 남은 장 > 0 이라 건너뛴다(0) · failed 그대로', public.qbo_payment_method_requeue('cash', 'e1d00000-0000-4000-8000-00000000000a')::text || ' ' || (select j.state from public.qbo_job j where j.kind = 'payment' and j.ims_id = :'p1'), '0 failed');

-- ── C) 자동 짝 2 회차 — O2 · O3 · O8 · O10 · O12 · O13 · O15 → 되살리기(O14 는 짝 없이 둔다 — C7 taken · D2 거부) ──
select jsonb_build_array(pg_temp.qrow('Q-1D-2', '9980002', 50, 50, 'C-1D-A'), pg_temp.qrow('Q-1D-3', '9980003', 30, 30, 'C-1D-A'), pg_temp.qrow('Q-1D-8', '9980008', 80, 80, 'C-1D-A'), pg_temp.qrow('Q-1D-10', '9980010', 25, 25, 'C-1D-A'),
                        pg_temp.qrow('Q-1D-12', '9980012', 45, 45, 'C-1D-A'), pg_temp.qrow('Q-1D-13', '9980013', 55, 55, 'C-1D-A'), pg_temp.qrow('Q-1D-15', '9980015', 75, 75, 'C-1D-A'))::text as r2 \gset
select pg_temp.bk(format($q$ select public.qbo_opening_candidates(%L::text[], %L::jsonb)::text $q$, '{9980002,9980003,9980008,9980010,9980012,9980013,9980015}', :'r2')) as c2 \gset
select pg_temp.chk('C1 candidates 2 회차 — matched 7(O14 는 C7 · D2 를 위해 남긴다) · 변화 0 그 밖', (:'c2'::jsonb->>'checked') || ' ' || (:'c2'::jsonb->>'matched') || ' ' || (:'c2'::jsonb->>'review_changed') || ' ' || (:'c2'::jsonb->>'already'), '7 7 0 0');
select pg_temp.chk('C2 P1 — 셋 다 섰다 → queued · last_error 는 마지막 failed 글(1 carried-over) 그대로 · note 「sent again: invoice 9980003 is now matched」 · remaining 0', pg_temp.jst('payment', :'p1') || ' | ' || public.qbo_opening_remaining(:'p1'::uuid)::text,
  'queued | 1 carried-over invoice(s) on this payment still have no QuickBooks match — match them under Settings → QuickBooks → Opening invoices and the payment then goes by itself | sent again: invoice 9980003 is now matched in QuickBooks | 0');
select pg_temp.chk('C3 P12(일감 없음) — 짝 뒤 sync 가 새 일감 queued · P13 · P15 queued', pg_temp.jst('payment', :'p12') || ' | ' || (select j.state from public.qbo_job j where j.kind = 'payment' and j.ims_id = :'p13') || ' ' || (select j.state from public.qbo_job j where j.kind = 'payment' and j.ims_id = :'p15'), 'queued | - | - | queued queued');
select pg_temp.svc(format($q$ select public.qbo_job_claim(50, array['credit_apply'], array[%L]::uuid[])::text $q$, pg_temp.job('credit_apply', :'al8'))) as cl8 \gset
select pg_temp.chk('C4 크레딧 붙임 O8 — requeue 로 queued → claim → blocked(부모 credit 일감 queued · 「waiting for credit note CR-99801」) — queued 아님', (:'cl8'::jsonb->>'claimed') || ' ' || (:'cl8'::jsonb->>'blocked_for_invoice') || ' | ' || (select j.state || ' ' || (j.blocked_by = pg_temp.job('credit', '31d00000-0000-4000-8000-000000000001'))::text || ' ' || j.warning from public.qbo_job j where j.id = pg_temp.job('credit_apply', :'al8')),
  '1 1 | blocked true waiting for credit note CR-99801 to reach QuickBooks first');
-- 수단 되살리기(판정 1039): P15 를 수단 글로 failed 로 두고(claim 의 실패 꼴) → credit_card 되살리기 1 · P13(cash) 그대로
update public.qbo_job j set state = 'failed', claimed_at = null, last_error = 'Payment method "credit_card" has no QuickBooks match — link it under Settings → QuickBooks matching → Payment methods — nothing was sent' where j.id = pg_temp.job('payment', :'p15');
select pg_temp.chk('C5 수단 되살리기(credit_card) — 1 · P15 queued · note 「payment method "credit_card" is now matched」 · P13(cash) queued 그대로 · cash 되살리기 0', public.qbo_payment_method_requeue('credit_card', 'e1d00000-0000-4000-8000-00000000000a')::text || ' | ' || pg_temp.jst('payment', :'p15') || ' | ' || (select j.state from public.qbo_job j where j.kind = 'payment' and j.ims_id = :'p13') || ' | ' || public.qbo_payment_method_requeue('cash', 'e1d00000-0000-4000-8000-00000000000a')::text,
  '1 | queued | Payment method "credit_card" has no QuickBooks match — link it under Settings → QuickBooks matching → Payment methods — nothing was sent | sent again: invoice 9980015 is now matched in QuickBooks · sent again: payment method "credit_card" is now matched in QuickBooks | queued | 0');
-- 멱등: 같은 묶음 둘 다 다시 → 변화 0 · review 실물 글자 그대로
select string_agg(r.invoice_id::text || ':' || coalesce(r.reason, '-') || ':' || coalesce(r.warning, '-') || ':' || r.qbo_rows::text || ':' || r.updated_at::text, '|' order by r.invoice_id) as rv_before from public.qbo_opening_review r where r.invoice_id::text like '11d00000-%' \gset
select pg_temp.bk(format($q$ select public.qbo_opening_candidates(%L::text[], %L::jsonb)::text $q$, '{9980001,9980004,9980005,9980006,9980007,9980009,9980011,9980016}', :'r1')) as c1b \gset
select pg_temp.bk(format($q$ select public.qbo_opening_candidates(%L::text[], %L::jsonb)::text $q$, '{9980002,9980003,9980008,9980010,9980012,9980013,9980015}', :'r2')) as c2b \gset
select pg_temp.chk('C6 멱등 — 1 회차 다시: already 2 · same 6 · changed 0 · matched 0 / 2 회차 다시: already 7 · review 행 글자 그대로 · 빈 묶음 = checked 0', (:'c1b'::jsonb->>'already') || ' ' || (:'c1b'::jsonb->>'review_same') || ' ' || (:'c1b'::jsonb->>'review_changed') || ' ' || (:'c1b'::jsonb->>'matched') || ' | ' || (:'c2b'::jsonb->>'already') || ' ' || (:'c2b'::jsonb->>'matched')
  || ' | ' || (:'rv_before' = (select string_agg(r.invoice_id::text || ':' || coalesce(r.reason, '-') || ':' || coalesce(r.warning, '-') || ':' || r.qbo_rows::text || ':' || r.updated_at::text, '|' order by r.invoice_id) from public.qbo_opening_review r where r.invoice_id::text like '11d00000-%'))::text
  || ' | ' || pg_temp.bk($q$ select (public.qbo_opening_candidates('{}'::text[], '[]'::jsonb))->>'checked' $q$) || ' ' || pg_temp.bk($q$ select (public.qbo_opening_candidates(null, null))->>'checked' $q$) || ' | ' || pg_temp.bk($q$ select (public.qbo_opening_candidates('{9980001}'::text[], '{"a":1}'::jsonb))::text $q$),
  '2 6 0 0 | 7 0 | true | 0 0 | ERR P0001: rows must be a JSON array of QuickBooks Invoice rows');
select pg_temp.chk('C7 unknown_numbers — 모르는 번호 · 실물 번호가 아닌 것은 세기만(변화 0) · taken: O14 가 Q-1D-13(O13 의 짝)을 받으면 review taken + 글', pg_temp.bk($q$ select (public.qbo_opening_candidates('{NOPE-1,9980099}'::text[], '[]'::jsonb))->>'unknown_numbers' $q$)
  || ' | ' || pg_temp.bk(format($q$ select (public.qbo_opening_candidates('{9980014}'::text[], %L::jsonb))->>'taken' $q$, jsonb_build_array(pg_temp.qrow('Q-1D-13', '9980014', 65, 65, 'C-1D-A'))::text)) || ' ' || pg_temp.rv('11d00000-0000-4000-8000-000000000014'),
  '2 | 1 taken | QuickBooks invoice #Q-1D-13 is already matched to IMS invoice 9980013 — unmatch that one first | rows=1 | unmatched=false');

-- ── D) 사람 짝 ──
select pg_temp.qrow('Q-1D-9', 'OLD-9 | X', 15, 15, 'C-1D-A')::text as r9 \gset
select pg_temp.chk('D1 match O9 without ack — docnumber 경고로 거부 · Id ≠ p_qbo_id 거부 · 이미 선 O1 거부 · 빈 Id 거부', pg_temp.bk(format($q$ select public.qbo_opening_match('11d00000-0000-4000-8000-000000000009', 'Q-1D-9', %L::jsonb, false)::text $q$, :'r9'))
  || ' | ' || pg_temp.bk(format($q$ select public.qbo_opening_match('11d00000-0000-4000-8000-000000000009', 'Q-1D-99', %L::jsonb, true)::text $q$, :'r9')) || ' | ' || pg_temp.bk(format($q$ select public.qbo_opening_match('11d00000-0000-4000-8000-000000000001', 'Q-1D-9', %L::jsonb, true)::text $q$, :'r9'))
  || ' | ' || pg_temp.bk($q$ select public.qbo_opening_match('11d00000-0000-4000-8000-000000000009', ' ', '{}'::jsonb, true)::text $q$),
  'ERR P0001: QuickBooks Invoice #Q-1D-9 does not look like IMS invoice 9980009: QuickBooks invoice #Q-1D-9 is numbered "OLD-9 | X", not 9980009 — confirm to match it anyway — nothing was saved | ERR P0001: The row given is QuickBooks Invoice #Q-1D-9 — not #Q-1D-99 — read it again | ERR P0001: Invoice 9980001 is already matched to QuickBooks Invoice #Q-1D-1 — unmatch it first — nothing was saved | ERR P0001: Pick the QuickBooks invoice to match — nothing was saved');
select pg_temp.bk(format($q$ select public.qbo_opening_match('11d00000-0000-4000-8000-000000000009', 'Q-1D-9', %L::jsonb, true)::text $q$, :'r9')) as m9 \gset
select pg_temp.chk('D2 match O9 with ack — matched manual · acked · review warning 남음 · 같은 QBO Id 를 O14 에 → 거부(사람 글) · sent 행(INV-1D-17)을 O14 에 → 거부', (:'m9'::jsonb->>'result') || ' ' || (:'m9'::jsonb->>'match_how') || ' ' || (:'m9'::jsonb->>'acked') || ' | ' || pg_temp.txn('11d00000-0000-4000-8000-000000000009') || ' | ' || pg_temp.rv('11d00000-0000-4000-8000-000000000009')
  || ' | ' || pg_temp.bk(format($q$ select public.qbo_opening_match('11d00000-0000-4000-8000-000000000014', 'Q-1D-9', %L::jsonb, true)::text $q$, :'r9')) || ' | ' || pg_temp.bk(format($q$ select public.qbo_opening_match('11d00000-0000-4000-8000-000000000014', 'INV-1D-17', %L::jsonb, true)::text $q$, pg_temp.qrow('INV-1D-17', '9980014', 65, 65, 'C-1D-A')::text)),
  'matched manual true | matched manual Q-1D-9 OLD-9 | X 15 bal=15 cust=C-1D-A job=null fp=null | null | QuickBooks invoice #Q-1D-9 is numbered "OLD-9 | X", not 9980009 | rows=1 | unmatched=false | ERR P0001: QuickBooks Invoice #Q-1D-9 is already matched to IMS invoice 9980009 — unmatch that one first — nothing was saved | ERR P0001: QuickBooks Invoice #INV-1D-17 is already the one IMS sent for IMS invoice 9980017 — it cannot be matched again — nothing was saved');

-- ── E) 풀기 ──
select pg_temp.svc(format($q$ select (public.qbo_job_claim(50, array['payment'], array[%L]::uuid[]))->>'claimed' $q$, pg_temp.job('payment', :'p10'))) as cl10 \gset
select pg_temp.svc(format('select (public.qbo_job_done(%L, ''PAY-1D-10'', ''1D-P10'', ''0'', ''tid-10'', null, null, 25, null, 0))->>''state''', pg_temp.job('payment', :'p10'))) as d10 \gset
select pg_temp.chk('E1 풀기 거부 — O10(P10 sent ' || :'cl10' || ' ' || :'d10' || ') · O17(sent 행) · O4(짝 없음) · 모르는 id', pg_temp.bk($q$ select public.qbo_opening_unmatch('11d00000-0000-4000-8000-000000000010', null)::text $q$) || ' | ' || pg_temp.bk($q$ select public.qbo_opening_unmatch('11d00000-0000-4000-8000-000000000017', null)::text $q$)
  || ' | ' || pg_temp.bk($q$ select public.qbo_opening_unmatch('11d00000-0000-4000-8000-000000000004', null)::text $q$) || ' | ' || pg_temp.bk($q$ select public.qbo_opening_unmatch('11d00000-0000-4000-8000-0000000000ff', null)::text $q$),
  'ERR P0001: A payment or credit application on invoice 9980010 is already in QuickBooks (Payment #PAY-1D-10) — undo it in IMS and let the void reach QuickBooks first — nothing was changed | ERR P0001: Invoice 9980017 was sent to QuickBooks by IMS (#INV-1D-17) — that link is not undone here — nothing was changed | ERR P0001: Invoice 9980004 has no QuickBooks match — nothing to undo | ERR P0001: No IMS invoice 11d00000-0000-4000-8000-0000000000ff — nothing was changed');
select pg_temp.svc(format($q$ select (public.qbo_job_claim(50, array['payment'], array[%L]::uuid[]))->>'claimed' $q$, pg_temp.job('payment', :'p13'))) as cl13 \gset
select pg_temp.chk('E2 풀기 거부 — O13 의 P13 이 sending 중(' || :'cl13' || ')', pg_temp.bk($q$ select public.qbo_opening_unmatch('11d00000-0000-4000-8000-000000000013', null)::text $q$), 'ERR P0001: A payment or credit application on invoice 9980013 is being sent to QuickBooks right now — wait until it settles, then try again — nothing was changed');
update public.qbo_job j set state = 'queued', claimed_at = null where j.id = pg_temp.job('payment', :'p13');
select pg_temp.bk($q$ select public.qbo_opening_unmatch('11d00000-0000-4000-8000-000000000013', 'wrong one')::text $q$) as u13 \gset
select pg_temp.chk('E3 풀기 O13 — jobs_failed 1 · P13 failed 「was unmatched」 · 행 삭제 · review unmatched + snapshot(Q-1D-13 · auto) + note', (:'u13'::jsonb->>'qbo_id') || ' ' || (:'u13'::jsonb->>'jobs_failed') || ' | ' || pg_temp.jst('payment', :'p13') || ' | ' || pg_temp.txn('11d00000-0000-4000-8000-000000000013') || ' | ' || pg_temp.rv('11d00000-0000-4000-8000-000000000013')
  || ' | ' || (select (r.unmatched_snapshot->>'qbo_id') || ' ' || (r.unmatched_snapshot->>'match_how') || ' ' || r.unmatched_note || ' ' || (r.unmatched_by = 'e1d00000-0000-4000-8000-00000000000a')::text from public.qbo_opening_review r where r.invoice_id = '11d00000-0000-4000-8000-000000000013'),
  'Q-1D-13 1 | failed | Invoice 9980013 was unmatched from QuickBooks — match it again under Settings → QuickBooks → Opening invoices and this job then goes by itself | sent again: invoice 9980013 is now matched in QuickBooks | (none) | unmatched | - | rows=1 | unmatched=true | Q-1D-13 auto wrong one true');
select pg_temp.bk(format($q$ select public.qbo_opening_candidates('{9980013}'::text[], %L::jsonb)::text $q$, :'r2')) as c13 \gset
select pg_temp.chk('E4 다시 짝 O13 — matched 1 · P13 queued 다시 · review reason null · 풀림 흔적은 남는다', (:'c13'::jsonb->>'matched') || ' | ' || (select j.state from public.qbo_job j where j.kind = 'payment' and j.ims_id = :'p13') || ' | ' || pg_temp.txn('11d00000-0000-4000-8000-000000000013') || ' | ' || pg_temp.rv('11d00000-0000-4000-8000-000000000013'),
  '1 | queued | matched auto Q-1D-13 9980013 55 bal=55 cust=C-1D-A job=null fp=null | null | - | rows=1 | unmatched=true');

-- ── F) 목록 · 권한 · link_set ──
select pg_temp.ro($q$ select public.qbo_opening_list()::text $q$) as ls \gset
select pg_temp.chk('F1 list(qbo:read) — 가짜 17 줄 · O1(auto · Q-1D-1 · 결제 1 · 100 · jobs queued 1 · remaining 0 · 누가) · O4(none · balance · 경고) · O9(manual) · O12(payments[0] queued) · O8(credits[0] blocked) · O13 unmatched_at · summary 꼴',
  (select count(*)::text from jsonb_array_elements(:'ls'::jsonb->'rows') x where x->>'invoice_number' like '99800%')
  || ' | ' || (select (x->>'match') || ' ' || (x->>'qbo_id') || ' ' || (x->>'pay_count') || ' ' || trim_scale((x->>'pay_amount')::numeric)::text || ' ' || (x->'jobs')::text || ' ' || (x->'payments'->0->>'remaining') || ' ' || (x->>'matched_by_name') || ' ' || trim_scale((x->>'remaining')::numeric)::text || ' ' || (x->>'store_name') from jsonb_array_elements(:'ls'::jsonb->'rows') x where x->>'invoice_number' = '9980001')
  || ' | ' || (select (x->>'match') || ' ' || coalesce(x->>'qbo_id', 'null') || ' ' || (x->>'reason') || ' ' || (x->>'warning' like '%twice%')::text || ' ' || jsonb_array_length(x->'candidates')::text || ' ' || (x->>'prior_settled') from jsonb_array_elements(:'ls'::jsonb->'rows') x where x->>'invoice_number' = '9980004')
  || ' | ' || (select (x->>'match') || ' ' || (x->>'warning' is not null)::text from jsonb_array_elements(:'ls'::jsonb->'rows') x where x->>'invoice_number' = '9980009')
  || ' | ' || (select (x->'payments'->0->>'job_state') || ' ' || (x->'payments'->0->>'method') from jsonb_array_elements(:'ls'::jsonb->'rows') x where x->>'invoice_number' = '9980012')
  || ' | ' || (select (x->'credits'->0->>'job_state') || ' ' || (x->'credits'->0->>'credit_number') || ' ' || trim_scale((x->>'credit_amount')::numeric)::text || ' ' || (x->'jobs')::text from jsonb_array_elements(:'ls'::jsonb->'rows') x where x->>'invoice_number' = '9980008')
  || ' | ' || (select (x->>'unmatched_at' is not null)::text || ' ' || (x->>'match') from jsonb_array_elements(:'ls'::jsonb->'rows') x where x->>'invoice_number' = '9980013')
  || ' | ' || (select string_agg(k, ',' order by k) from jsonb_object_keys(:'ls'::jsonb->'summary') k) || ' ' || ((:'ls'::jsonb->'summary'->>'invoices')::int >= 17)::text,
  '17 | auto Q-1D-1 1 100 {"queued": 1} 0 QBO 1D Bookkeeper 0 QBO1D Store A | none null balance true 1 10.21 | manual true | queued cash | blocked CR-99801 5 {"blocked": 1} | true auto | invoices,matched_auto,matched_manual,never_checked,review,unmatched,with_attachments,with_attachments_unmatched true');
select pg_temp.chk('F2 권한 — qbo:read 는 candidates · match · unmatch 거부(쓰기) · 열쇠 없는 staff 는 list 도 거부 · anon · service_role 42501', pg_temp.ro($q$ select (public.qbo_opening_candidates('{}'::text[], '[]'::jsonb))::text $q$) || ' | ' || pg_temp.ro($q$ select public.qbo_opening_match('11d00000-0000-4000-8000-000000000004', 'x', '{"Id":"x"}'::jsonb, true)::text $q$) || ' | ' || pg_temp.ro($q$ select public.qbo_opening_unmatch('11d00000-0000-4000-8000-000000000001', null)::text $q$)
  || ' | ' || pg_temp.nn($q$ select public.qbo_opening_list()::text $q$) || ' | ' || pg_temp.an($q$ select public.qbo_opening_list()::text $q$) || ' | ' || pg_temp.svc($q$ select public.qbo_opening_list()::text $q$) || ' | ' || pg_temp.svc($q$ select public.qbo_opening_candidates('{}'::text[], '[]'::jsonb)::text $q$) || ' | ' || pg_temp.an($q$ select count(*) from public.qbo_opening_review $q$),
  'ERR P0001: Your account does not have the ''qbo'' (write) permission — ask an admin to switch it on in Staff — nothing was changed | ERR P0001: Your account does not have the ''qbo'' (write) permission — ask an admin to switch it on in Staff — nothing was changed | ERR P0001: Your account does not have the ''qbo'' (write) permission — ask an admin to switch it on in Staff — nothing was changed | ERR P0001: Your account does not have the ''qbo'' permission — ask an admin to switch it on in Staff — nothing was changed | ERR 42501: permission denied for function qbo_opening_list | ERR 42501: permission denied for function qbo_opening_list | ERR 42501: permission denied for function qbo_opening_candidates | ERR 42501: permission denied for table qbo_opening_review');
select pg_temp.bk($q$ select public.qbo_link_set('customer', 'c1d00000-0000-4000-8000-000000000012', 'C-1D-NEW')::text $q$) as lk \gset
select pg_temp.chk('F3 qbo_link_set 재발행 — 다른 종류(customer · 가짜 U → C-1D-NEW)는 그대로 · requeued 0 · manual (수단 짝 실물은 안 건드린다 — 수단 길은 C5 의 속 함수)', (:'lk'::jsonb->>'ims_kind') || ' ' || (:'lk'::jsonb->>'qbo_id') || ' ' || (:'lk'::jsonb->>'matched_by') || ' ' || (:'lk'::jsonb->>'requeued') || ' ' || (:'lk'::jsonb->>'qbo_name'), 'customer C-1D-NEW manual 0 QBO1D New');
select pg_temp.chk('F4 바뀐 함수 = 재발행 둘(qbo_payment_requeue · qbo_link_set) + 새 함수(t_pre 에 없음) · 그 밖 무변', (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5), case when :{?mig} then 'qbo_link_set,qbo_payment_requeue' else '(none)' end);

\echo '── 결과'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.customer) = :n_cust0 as customer_same, (select count(*) from public.so_invoice) = :n_inv0 as invoice_same,
       (select count(*) from public.so_payment) = :n_pay0 as payment_same, (select count(*) from public.so_payment_alloc) = :n_palloc0 as palloc_same, (select count(*) from public.so_credit) = :n_cr0 as credit_same, (select count(*) from public.so_credit_alloc) = :n_calloc0 as calloc_same,
       (select count(*) from public.qbo_job) = :n_job0 as job_same, (select count(*) from public.qbo_txn) = :n_txn0 as txn_same, (select count(*) from public.qbo_link) = :n_link0 as link_same, (select count(*) from public.qbo_entity) = :n_ent0 as entity_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
\if :{?mig}
\echo '(시험 갈래: qbo_opening_review 는 rollback 으로 사라졌다 —' :n_rv0 ')'
\else
select (select count(*) from public.qbo_opening_review) = :n_rv0 as review_same;
\endif
