-- supabase/tests/qbo_sync_2e1a_check.sql — qbo-sync-2e-1a 검증: CHECK 둘 + paypal · 기본 계좌(cheque CAD → _105_ · paypal → _124_ · USD 무변 · 24 행) · qbo_ims_rows · qbo_link paypal → 7 · so_payment_add(paypal · 미래 1 년 · 거부 글) · 환불은 미래 거부 그대로 · 받기 두 함수 본문 · 그 밖 함수 무변 (2026-11-02 밤)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback · ⚠️ begin ~ rollback 10 초 안
--   Claude Code(시험): MIG=supabase/migrations/20261103020000_qbo_sync_2e1a_paypal_cheque_105.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2e1a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 차이는 G0 · 기대 OK 수는 EXPECT_OK
--   쓰기: 가짜 직원 1(manager · sales) · 결제 3(rollback) · QBO 호출 0 · 받기 두 함수는 본문 글자만 본다(Shopify 오더 실물은 안 만든다 — 못 본 것)
\set ON_ERROR_STOP on
\set EXPECT_OK 27
\pset pager off
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo\_%' or p.proname like 'so\_%' or p.proname like 'shop\_%');
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.so_payment) as n_pay0,
       (select count(*) from public.so_payment_account_default) as n_def0, (select count(*) from public.qbo_link) as n_link0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as tor_id,
       (select id::text from public.ref_warehouse where name = 'Asung - Edmonton') as edm_id,
       (select id::text from public.ref_currency where code = 'CAD') as cad_id,
       (select id::text from public.ref_account where code = '_124_') as a124_id,
       (select id::text from public.ref_account where code = '_104_') as a104_id,
       (select c.id::text from public.customer c where c.is_active order by c.created_at limit 1) as cust_id,
       public.ims_today()::text as today \gset
\echo '── 기준: 함수' :n_fn '· staff' :n_staff0 '· payments' :n_pay0 '· defaults' :n_def0 '· links' :n_link0 '· realm' :realm '· today' :today
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
create function pg_temp.mgr(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"e1e1e1e1-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('e1e1e1e1-0000-4000-8000-00000000000a', 'e1e1e1e1-0000-4000-8000-000000000001', 'qbo-sync-2e1a-mgr@asung.invalid', 'QBO 2e1a Manager', 'manager', '["sales"]');

-- ── A. CHECK 둘 ──
select pg_temp.chk('A1 so_payment_method_ck has paypal + opening', (select (pg_get_constraintdef(oid) ~ '''paypal''' and pg_get_constraintdef(oid) ~ '''opening''')::text from pg_constraint where conname = 'so_payment_method_ck'), 'true');
select pg_temp.chk('A2 so_payment_account_default_method_ck has paypal (no opening)', (select (pg_get_constraintdef(oid) ~ '''paypal''' and pg_get_constraintdef(oid) !~ '''opening''')::text from pg_constraint where conname = 'so_payment_account_default_method_ck'), 'true');

-- ── B. 기본 계좌 ──
select pg_temp.chk('B1 cheque CAD TOR · EDM → _105_', (select string_agg(d.account_code, ',' order by w.name) from public.so_payment_account_default d join public.ref_warehouse w on w.id = d.warehouse_id where d.method = 'cheque' and d.currency_code = 'CAD'), '_105_,_105_');
select pg_temp.chk('B2 cheque USD unchanged _106_', (select string_agg(d.account_code, ',' order by w.name) from public.so_payment_account_default d join public.ref_warehouse w on w.id = d.warehouse_id where d.method = 'cheque' and d.currency_code = 'USD'), '_106_,_106_');
select pg_temp.chk('B3 paypal CAD TOR · EDM → _124_', (select string_agg(d.account_code, ',' order by w.name) from public.so_payment_account_default d join public.ref_warehouse w on w.id = d.warehouse_id where d.method = 'paypal' and d.currency_code = 'CAD'), '_124_,_124_');
select pg_temp.chk('B4 account_id matches account_code on every row', (select count(*)::text from public.so_payment_account_default d join public.ref_account a on a.id = d.account_id where a.code <> d.account_code), '0');
select pg_temp.chk('B5 rows = 24 (22 + paypal 2)', (select count(*)::text from public.so_payment_account_default), '24');
select pg_temp.chk('B6 other rows untouched (shopify _104_ · e_transfer _1150040028_ · cash TOR _137_)', (select string_agg(d.method || ':' || d.account_code, ',' order by d.method) from public.so_payment_account_default d join public.ref_warehouse w on w.id = d.warehouse_id where w.name = 'Asung Trading Inc.' and d.currency_code = 'CAD' and d.method in ('shopify', 'e_transfer', 'cash')), 'cash:_137_,e_transfer:_1150040028_,shopify:_104_');
select pg_temp.chk('B7 so_payment_default_account(paypal, TOR, CAD) = _124_', (select public.so_payment_default_account('paypal', :'tor_id'::uuid, :'cad_id'::uuid)::text), :'a124_id');
select pg_temp.chk('B8 so_payment_default_account(cheque, EDM, CAD) = _105_', (select a.code from public.ref_account a where a.id = public.so_payment_default_account('cheque', :'edm_id'::uuid, :'cad_id'::uuid)), '_105_');

-- ── C. qbo_ims_rows · qbo_link ──
select pg_temp.chk('C1 qbo_ims_rows(payment_method) = 9 rows · paypal → PayPal', (select count(*)::text || ' ' || coalesce(max(r.ims_code) filter (where r.ims_id = 'paypal'), '-') from public.qbo_ims_rows('payment_method') r), '9 PayPal');
select pg_temp.chk('C2 qbo_ims_rows(payment_method) credit_card still unmapped (null code)', (select (r.ims_code is null)::text from public.qbo_ims_rows('payment_method') r where r.ims_id = 'credit_card'), 'true');
select pg_temp.chk('C3 qbo_link payment_method paypal → PaymentMethod 7 (auto_map)', (select l.qbo_type || ' ' || l.qbo_id || ' ' || l.matched_by from public.qbo_link l where l.realm_id = :'realm' and l.ims_kind = 'payment_method' and l.ims_id = 'paypal'), 'PaymentMethod 7 auto_map');
select pg_temp.chk('C4 qbo_link payment_method rows = 8 (7 + paypal)', (select count(*)::text from public.qbo_link l where l.realm_id = :'realm' and l.ims_kind = 'payment_method'), '8');

-- ── D. so_payment_add — paypal · 미래 날짜(991 (가)) · 거부 글 ──
create temp table t_bal as select coalesce((select b.received from public.so_customer_balance(:'cust_id'::uuid) b where b.currency_id = :'cad_id'::uuid), 0) as r0;
select pg_temp.chk('D1 add method paypal · TOR · CAD → account _124_ (default)', pg_temp.mgr(format($q$ select (public.so_payment_add(%L::jsonb))->>'account_code' $q$,
       jsonb_build_object('customer_id', :'cust_id', 'amount', 12.34, 'method', 'paypal', 'reference', '2e1a-D1', 'currency_code', 'CAD', 'warehouse_id', :'tor_id')::text)), '_124_');
select pg_temp.chk('D2 add paid_on today + 30 accepted · paid_on echoed', pg_temp.mgr(format($q$ select (public.so_payment_add(%L::jsonb))->>'paid_on' $q$,
       jsonb_build_object('customer_id', :'cust_id', 'amount', 20, 'method', 'cheque', 'reference', '2e1a-D2 post-dated', 'currency_code', 'CAD', 'warehouse_id', :'tor_id', 'paid_on', (:'today'::date + 30)::text)::text)), (:'today'::date + 30)::text);
select pg_temp.chk('D3 add paid_on today + 365 accepted (boundary)', pg_temp.mgr(format($q$ select (public.so_payment_add(%L::jsonb))->>'paid_on' $q$,
       jsonb_build_object('customer_id', :'cust_id', 'amount', 5, 'method', 'cheque', 'reference', '2e1a-D3', 'currency_code', 'CAD', 'warehouse_id', :'tor_id', 'paid_on', (:'today'::date + 365)::text)::text)), (:'today'::date + 365)::text);
select pg_temp.chk('D4 add paid_on today + 366 rejected (more than a year ahead)', (select (pg_temp.mgr(format($q$ select (public.so_payment_add(%L::jsonb))->>'paid_on' $q$,
       jsonb_build_object('customer_id', :'cust_id', 'amount', 5, 'method', 'cheque', 'reference', '2e1a-D4', 'currency_code', 'CAD', 'warehouse_id', :'tor_id', 'paid_on', (:'today'::date + 366)::text)::text)) ~ 'more than a year ahead')::text), 'true');
select pg_temp.chk('D5 add unknown method lists paypal in the refusal', (select (pg_temp.mgr(format($q$ select (public.so_payment_add(%L::jsonb))->>'paid_on' $q$,
       jsonb_build_object('customer_id', :'cust_id', 'amount', 5, 'method', 'bitcoin', 'currency_code', 'CAD', 'warehouse_id', :'tor_id')::text)) ~ 'direct_deposit, shopify, paypal — nothing was saved')::text), 'true');
select pg_temp.chk('D6 cheque CAD default now _105_ through the add path', pg_temp.mgr(format($q$ select (public.so_payment_add(%L::jsonb))->>'account_code' $q$,
       jsonb_build_object('customer_id', :'cust_id', 'amount', 7, 'method', 'cheque', 'reference', '2e1a-D6', 'currency_code', 'CAD', 'warehouse_id', :'edm_id')::text)), '_105_');
select pg_temp.chk('D7 post-dated payments count as received now (991 meaning unchanged · received grew by 12.34 + 20 + 5 + 7)', (select (coalesce((select b.received from public.so_customer_balance(:'cust_id'::uuid) b where b.currency_id = :'cad_id'::uuid), 0) - (select r0 from t_bal))::text), '44.34');
select pg_temp.chk('D8 the four test payments exist · method mix', (select string_agg(p.method || ':' || p.account_code, ',' order by p.reference) from public.so_payment p where p.reference like '2e1a-D%'), 'paypal:_124_,cheque:_105_,cheque:_105_,cheque:_105_');
select pg_temp.chk('D9 refund paid_on tomorrow still rejected (so_payment_refund unchanged)', (select (pg_temp.mgr(format($q$ select (public.so_payment_refund(%L::jsonb))->>'paid_on' $q$,
       jsonb_build_object('customer_id', :'cust_id', 'amount', 1, 'method', 'cash', 'account_id', :'a104_id', 'currency_code', 'CAD', 'warehouse_id', :'tor_id', 'paid_on', (:'today'::date + 1)::text)::text)) ~ 'Refund date .* is in the future')::text), 'true');

-- ── E. 받기 두 함수 본문(글자) ──
select pg_temp.chk('E1 shop_order_ingest: paypal case 1 · literal shopify method 0', (select (length(prosrc) - length(replace(prosrc, $x$case when v_gw = 'paypal' then 'paypal' else 'shopify' end$x$, ''))) / length($x$case when v_gw = 'paypal' then 'paypal' else 'shopify' end$x$) || ' ' || (length(prosrc) - length(replace(prosrc, $x$'method', 'shopify'$x$, ''))) / length($x$'method', 'shopify'$x$) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest'), '1 0');
select pg_temp.chk('E2 shop_order_process: v_gws declared · paypal case 1 · literal shopify method 0', (select (prosrc ~ 'v_gws +text\[\];')::text || ' ' || (length(prosrc) - length(replace(prosrc, $x$case when v_gws = array['paypal'] then 'paypal' else 'shopify' end$x$, ''))) / length($x$case when v_gws = array['paypal'] then 'paypal' else 'shopify' end$x$) || ' ' || (length(prosrc) - length(replace(prosrc, $x$'method', 'shopify'$x$, ''))) / length($x$'method', 'shopify'$x$) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_process'), 'true 1 0');
select pg_temp.chk('E3 shop_order_process: gateway aggregate reads CAPTURE · SALE · SUCCESS only', (select (prosrc ~ $x$array_agg\(distinct lower\(trim\(t->>'gateway'\)\)\) into v_gws[\s\S]*in \('CAPTURE', 'SALE'\) and upper\(coalesce\(t->>'status', ''\)\) = 'SUCCESS';$x$)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_process'), 'true');

-- ── F. 그 밖 함수 무변 — 다섯만 바뀌었다 ──
select pg_temp.chk('F1 changed function bodies = exactly the four (qbo_ims_rows · shop_order_ingest · shop_order_process · so_payment_add) · none else (after apply: none)', (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5), case when :{?mig} then 'qbo_ims_rows,shop_order_ingest,shop_order_process,so_payment_add' else '(none)' end);

\echo '── 결과'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.ims_staff where email like 'qbo-sync-2e1a-%') = 0 as fake_staff_gone,
       (select count(*) from public.so_payment) = :n_pay0 as payment_same, (select count(*) from public.so_payment where reference like '2e1a-D%') = 0 as test_payments_gone,
       (select count(*) from public.so_payment_account_default) = :n_def0 as defaults_same, (select count(*) from public.qbo_link) = :n_link0 as link_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
