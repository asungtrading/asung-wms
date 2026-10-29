-- supabase/tests/pos_pay_1.sql — pos-pay-1 so_pos_payment_cancel · so_pos_payment_list 검증 (2026-10-28 · 판정 863 · 이견 1 ~ 12)
-- [테스트 · Asung-IMS] 시험 적용 장치 — begin → (-v mig 면 \i) → 가짜 재료 → 갈래 → rollback → 가짜 흔적 0 · 시퀀스 되돌림 · 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029005830_pos_pay_1.sql -f supabase/tests/pos_pay_1.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK = 시험 OK − G0(시험 전용 1) — 머리의 EXPECT 줄 참조(통과한 실행에서 받아 적는다)
--   재료(전부 가짜 · PP1): 직원 넷(SW worker sales · SM manager sales · SX worker sales + 다른 창고만 · W0 열쇠 없음) · 손님 PP1 Customer(CAD · 브랜치 = 첫 창고) · 제품 PP1-P 장부 50 · POS 판매 S1 · S2 · S4(fulfilled 로 적음) · warehouse 초안 S3 · 가짜 인보이스 99986001
--   ⚠️ so_create 가 so_number_seq 를 당긴다 → 끝에 greatest(실제 최대, 머리) 로 되돌린다 · 인보이스 번호는 당기지 않는다(fulfilled 는 replica 로 적는다 · 가짜 인보이스는 번호를 명시)
--   EXPECT: 시험(-v mig) OK 35(G0 포함) · 확인(-v mig 없음) OK 34(G0 빠짐 · Z2 는 확인 갈래 줄) — 회차 3 통과 출력에서 받아 적음
\set ON_ERROR_STOP on
\pset pager off
\echo '── db_role · schema_migrations · 창구 둘 · 시퀀스 머리 · 실제 행 수'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261029005830' \gset
select count(*) as fn_before from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_pos_payment_cancel', 'so_pos_payment_list') \gset
select :n_applied as schema_migrations_rows_for_20261029005830, :fn_before as fn_before;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select :so_seq_last as so_seq_head, :'so_seq_called' as so_called, (select max(substring(so_number from '[0-9]+')::bigint) from public.so) as so_max_head,
       :inv_seq_last as inv_seq_head, :'inv_seq_called' as inv_called, (select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$') as inv_max_head;
select (select count(*) from public.so) as w_so, (select count(*) from public.so_payment) as w_pay, (select count(*) from public.so_payment_order) as w_po, (select count(*) from public.so_payment_alloc) as w_pa,
       (select count(*) from public.so_invoice) as w_inv, (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.customer) as w_cust, (select count(*) from public.product) as w_prod \gset
select (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_void') as md5_void0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_add') as md5_add0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_complete') as md5_complete0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_finish') as md5_finish0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_attach') as md5_attach0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_alloc_add') as md5_alloc0 \gset
select count(*) as w_paycols from information_schema.columns where table_schema = 'public' and table_name = 'so_payment' \gset
\echo '── 기준: so' :w_so '· so_payment' :w_pay '· staff' :w_staff '· customer' :w_cust '· void md5' :md5_void0
-- chk 는 트랜잭션 밖에서 만든다 — rollback 뒤의 Z1 · Z2 도 부른다(트랜잭션 안의 pg_temp 함수는 rollback 으로 사라진다)
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

\echo '── 도우미'
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 가짜 직원 신원으로 한 문장(definer 창구는 auth.uid() 를 claims 에서 읽는다) · 거부는 'ERR <code>: <글>' 로 돌려준다
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- POS 판매 하나: 초안 → 줄 → 세금 규칙(replica · 가짜 손님은 주소가 없다 · svc-1b 와 같다) → so_pos_confirm
create function pg_temp.mk_pos(p_claims text, p_cust uuid, p_pid uuid, p_wh uuid, p_rule uuid, p_rule_name text, p_qty numeric, p_price numeric, p_note text) returns uuid language plpgsql as $$
declare v_x jsonb; v_so uuid;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  v_x := public.so_create(p_cust, 'pos', 'pos', p_wh, p_note);  v_so := (v_x->>'id')::uuid;
  v_x := public.so_line_add(v_so, p_pid, p_qty, p_price, null, null, null, false);
  execute 'set local session_replication_role = replica';
  update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
  execute 'set local session_replication_role = origin';
  v_x := public.so_pos_confirm(v_so);
  return v_so;
end $$;
-- 결제 하나(POS 화면 꼴 · so_payment_add · target_so_ids) → payment id
create function pg_temp.pay(p_claims text, p_cust uuid, p_amount numeric, p_method text, p_cur uuid, p_wh uuid, p_targets uuid[], p_ref text) returns uuid language plpgsql as $$
declare v_x jsonb;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  v_x := public.so_payment_add(jsonb_build_object('customer_id', p_cust, 'amount', p_amount, 'paid_on', public.ims_today(), 'method', p_method, 'reference', p_ref,
                                                   'currency_id', p_cur, 'warehouse_id', p_wh, 'target_so_ids', to_jsonb(coalesce(p_targets, '{}'::uuid[]))));
  return (v_x->>'payment_id')::uuid;   -- so_payment_add 반환 열쇠 = payment_id(회차 1 에서 잡음 · payment.id 가 아니다)
end $$;
-- 가짜 인보이스(ovd_1_check mk_inv 꼴 · 오더 없음 · 번호 명시 · 시퀀스 무접촉)
create function pg_temp.mk_inv(p_number text, p_cust uuid, p_cur uuid, p_total numeric) returns uuid language sql as $$
  insert into public.so_invoice (invoice_number, status, bill_to_customer_id, issued_on, due_on, payment_term_name, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due)
  values (p_number, 'issued', p_cust, public.ims_today(), public.ims_today() + 30, 'pp1 fake', p_cur, (select rc.code from public.ref_currency rc where rc.id = p_cur), p_total, p_total, 0, p_total, p_total)
  returning id $$;
create function pg_temp.pstate(p_id uuid) returns text language sql security definer as $$
  select p.status || '|' || coalesce((select s.name from public.ims_staff s where s.id = p.voided_by), '-') || '|' || coalesce(p.void_note, '-') || '|' || (p.voided_at is not null)::text from public.so_payment p where p.id = p_id $$;

\if :{?mig}
select pg_temp.chk('G0 시험에서만: 적용 전(schema_migrations 0 행 · 창구 둘 없음) → 시험 적용 뒤 둘 있음',
  :n_applied = 0 and :fn_before = 0 and to_regprocedure('public.so_pos_payment_cancel(uuid, text)') is not null and to_regprocedure('public.so_pos_payment_list(uuid)') is not null,
  format('applied %s fn_before %s', :n_applied, :fn_before));
\endif

\echo '── M) 재료'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pp1-sw@test.invalid', 'PP1 SW', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as sw_uid, id::text as sw_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pp1-sm@test.invalid', 'PP1 SM', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as sm_uid, id::text as sm_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pp1-w0@test.invalid', 'PP1 W0', 'worker', '[]', '{}') returning auth_user_id::text as w0_uid \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select id::text as wh2, name as wh2name from public.ref_warehouse where is_active and id <> :'wh'::uuid order by name limit 1 \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pp1-sx@test.invalid', 'PP1 SX', 'worker', '["ims","sales"]', array[:'wh2'::uuid]) returning auth_user_id::text as sx_uid \gset
\set sw '{"sub":"' :sw_uid '","role":"authenticated"}'
\set sm '{"sub":"' :sm_uid '","role":"authenticated"}'
\set sx '{"sub":"' :sx_uid '","role":"authenticated"}'
\set w0 '{"sub":"' :w0_uid '","role":"authenticated"}'
select b.name as bina from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as r13, name as r13_name from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('PP1 Customer', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as cust \gset
insert into public.product (sku, name, source) values ('PP1-P', 'PP1 Product', 'manual') returning id::text as pid \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values (public.ims_today() - 3, 1, 'PP1-P', :'whname', :'bina', 50, 'po_in', 'purchase', 'PO-PP1', 'pp1-1', 'manual');
set local session_replication_role = origin;
select pg_temp.chk(format('M0 staff ×4 · customer (branch %s) · PP1-P stock 50 · other warehouse %s · tax %s · cash + debit_card defaults for %s CAD', :'whname', :'wh2name', :'r13_name', :'whname'),
  :'sw_uid' <> '' and :'sm_uid' <> '' and :'sx_uid' <> '' and :'w0_uid' <> '' and :'cust' <> '' and :'pid' <> '' and :'r13' <> '' and :'wh2' <> ''
  and (select count(*) from public.so_payment_account_default d where d.warehouse_id = :'wh'::uuid and d.currency_code = 'CAD' and d.method in ('cash', 'debit_card')) = 2, 'see M0');

\echo '── S1) POS 판매 S1(2 × 10.00) · 결제 둘(cash 5 · debit 12) · 목록 · 미리 보기 deposit'
select pg_temp.mk_pos(:'sw', :'cust'::uuid, :'pid'::uuid, :'wh'::uuid, :'r13'::uuid, :'r13_name', 2, 10.00, 'pp1 S1')::text as so1 \gset
select s.so_number as so1_num, s.status as so1_status from public.so s where s.id = :'so1'::uuid \gset
select pg_temp.pay(:'sw', :'cust'::uuid, 5.00, 'cash', :'cad'::uuid, :'wh'::uuid, array[:'so1'::uuid], 'pp1 cash 5')::text as pc \gset
select pg_temp.pay(:'sw', :'cust'::uuid, 12.00, 'debit_card', :'cad'::uuid, :'wh'::uuid, array[:'so1'::uuid], 'pp1 debit 12')::text as pd \gset
select pg_temp.chk('S1a S1 confirmed · two active payments tied to S1 (cash 5 + debit 12)', :'so1_status' = 'confirmed'
  and (select count(*) from public.so_payment_order o join public.so_payment p on p.id = o.payment_id where o.so_id = :'so1'::uuid and p.status = 'active') = 2, :'so1_status');
select pg_temp.as_user(:'sw', format('select public.so_pos_payment_list(%L)::text', :'so1')) as l1 \gset
select pg_temp.chk('S1b list(S1): 2 rows · methods cash,debit_card · created_by_name PP1 SW · status active · targets 1 · active_total 17',
  jsonb_array_length(pg_temp.j(:'l1')->'payments') = 2
  and (select string_agg(x->>'method', ',' order by x->>'method') from jsonb_array_elements(pg_temp.j(:'l1')->'payments') x) = 'cash,debit_card'
  and (select bool_and(x->>'created_by_name' = 'PP1 SW' and x->>'status' = 'active' and (x->>'targets')::int = 1 and x->>'voided_by_name' is null) from jsonb_array_elements(pg_temp.j(:'l1')->'payments') x)
  and trim_scale((pg_temp.j(:'l1')->>'active_total')::numeric) = 17, left(:'l1', 400));
select pg_temp.as_user(:'sw', format('select public.so_pos_finish(%L, false)::text', :'so1')) as pv1 \gset
select coalesce(trim_scale((pg_temp.j(:'pv1')#>>'{estimate,deposit}')::numeric), -1) as dep1, coalesce(trim_scale((pg_temp.j(:'pv1')#>>'{estimate,total}')::numeric), -1) as tot1 \gset
select pg_temp.chk('S1c preview before cancel: deposit 17 (= cash 5 + debit 12 · total ≥ 20)', :dep1 = 17 and :tot1 >= 20, format('deposit %s total %s | %s', :dep1, :tot1, left(:'pv1', 300)));

\echo '── C1) worker(sales) 가 cash 취소 → OK · 기록 · 목록 회색 · 미리 보기 deposit − 5 · debit 그대로'
select pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'pc')) as c1 \gset
select pg_temp.chk('C1a cancel by sales worker: returns so_number · amount 5 · method cash · status voided · note default',
  pg_temp.j(:'c1')->>'so_number' = :'so1_num' and trim_scale((pg_temp.j(:'c1')->>'amount')::numeric) = 5 and pg_temp.j(:'c1')->>'method' = 'cash' and pg_temp.j(:'c1')->>'status' = 'voided'
  and pg_temp.j(:'c1')->>'note' = 'Cancelled at POS before Finish' and pg_temp.j(:'c1')->>'so_id' = :'so1' and (pg_temp.j(:'c1')->'balance') ? 'received', left(:'c1', 400));
select pg_temp.chk('C1b row: status voided · voided_by PP1 SW · void_note default · voided_at set', pg_temp.pstate(:'pc'::uuid) = 'voided|PP1 SW|Cancelled at POS before Finish|true', pg_temp.pstate(:'pc'::uuid));
select pg_temp.as_user(:'sw', format('select public.so_pos_payment_list(%L)::text', :'so1')) as l2 \gset
select pg_temp.chk('C1c list after cancel: still 2 rows · cash voided with voided_by_name + void_note · debit active · active_total 12',
  jsonb_array_length(pg_temp.j(:'l2')->'payments') = 2
  and (select (x->>'status') || '/' || (x->>'voided_by_name') || '/' || (x->>'void_note') from jsonb_array_elements(pg_temp.j(:'l2')->'payments') x where x->>'method' = 'cash') = 'voided/PP1 SW/Cancelled at POS before Finish'
  and (select x->>'status' from jsonb_array_elements(pg_temp.j(:'l2')->'payments') x where x->>'method' = 'debit_card') = 'active'
  and trim_scale((pg_temp.j(:'l2')->>'active_total')::numeric) = 12, left(:'l2', 500));
select pg_temp.as_user(:'sw', format('select public.so_pos_finish(%L, false)::text', :'so1')) as pv2 \gset
select coalesce(trim_scale((pg_temp.j(:'pv2')#>>'{estimate,deposit}')::numeric), -1) as dep2 \gset
select pg_temp.chk('C1d preview after cancel: deposit = before − 5 · debit payment untouched (active · remaining 12)', :dep2 = :dep1 - 5
  and (select p.status || '/' || trim_scale(public.so_payment_remaining(p.id)) from public.so_payment p where p.id = :'pd'::uuid) = 'active/12', format('deposit %s (before %s)', :dep2, :dep1));
select pg_temp.chk('C1e same payment again → refused (already cancelled)', pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'pc')) = 'ERR P0001: This payment was already cancelled — nothing was saved',
  pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'pc')));

\echo '── C2) 사유 있는 취소 → void_note POS: … · 빈 사유는 기본 글'
select pg_temp.pay(:'sw', :'cust'::uuid, 3.00, 'cash', :'cad'::uuid, :'wh'::uuid, array[:'so1'::uuid], 'pp1 cash 3')::text as pc3 \gset
select pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, %L)::text', :'pc3', '  wrong amount  ')) as c2 \gset
select pg_temp.chk('C2a note given → void_note ''POS: wrong amount'' (trimmed)', pg_temp.j(:'c2')->>'note' = 'POS: wrong amount' and pg_temp.pstate(:'pc3'::uuid) = 'voided|PP1 SW|POS: wrong amount|true', coalesce(left(:'c2', 300), '(null)'));
select pg_temp.pay(:'sw', :'cust'::uuid, 1.00, 'cash', :'cad'::uuid, :'wh'::uuid, array[:'so1'::uuid], 'pp1 cash 1')::text as pc1 \gset
select pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, %L)::text', :'pc1', '   ')) as c2b \gset
select pg_temp.chk('C2b blank note → default note', pg_temp.j(:'c2b')->>'note' = 'Cancelled at POS before Finish', coalesce(left(:'c2b', 300), '(null)'));

\echo '── C3) 이견 2 — Reopen(draft) 한 판매의 결제도 취소된다 · 다시 확정'
select pg_temp.as_user(:'sw', format('select public.so_pos_reopen(%L)::text', :'so1')) as ro \gset
select s.status as so1_status2 from public.so s where s.id = :'so1'::uuid \gset
select pg_temp.pay(:'sw', :'cust'::uuid, 4.00, 'cash', :'cad'::uuid, :'wh'::uuid, array[:'so1'::uuid], 'pp1 cash 4 draft')::text as pc4 \gset
select pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'pc4')) as c3 \gset
select pg_temp.chk('C3 S1 reopened → draft · payment on the draft cancelled OK', :'so1_status2' = 'draft' and pg_temp.j(:'c3')->>'status' = 'voided', format('status %s | %s', :'so1_status2', left(:'c3', 200)));
select pg_temp.as_user(:'sw', format('select public.so_pos_confirm(%L)::text', :'so1')) as rc \gset
select pg_temp.chk('C3b S1 confirmed again', (select s.status from public.so s where s.id = :'so1'::uuid) = 'confirmed', left(:'rc', 200));

\echo '── R) 거부 갈래 — 두 판매에 걸침 · 대상 0 · POS 밖 채널 · Finish 뒤 · refund · opening · 살아 있는 alloc'
select pg_temp.mk_pos(:'sw', :'cust'::uuid, :'pid'::uuid, :'wh'::uuid, :'r13'::uuid, :'r13_name', 1, 10.00, 'pp1 S2')::text as so2 \gset
select pg_temp.pay(:'sw', :'cust'::uuid, 6.00, 'cash', :'cad'::uuid, :'wh'::uuid, array[:'so1'::uuid, :'so2'::uuid], 'pp1 two sales')::text as p2s \gset
select pg_temp.chk('R1 payment tied to two sales → refused (2 sale(s))', pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p2s')) = 'ERR P0001: This payment is not tied to exactly one sale (2 sale(s)) — a manager voids it on the Payments screen — nothing was saved',
  pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p2s')));
select pg_temp.pay(:'sw', :'cust'::uuid, 2.00, 'cash', :'cad'::uuid, :'wh'::uuid, null, 'pp1 no target')::text as p0 \gset
select pg_temp.chk('R2 payment with no target sale → refused (0 sale(s))', pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p0')) = 'ERR P0001: This payment is not tied to exactly one sale (0 sale(s)) — a manager voids it on the Payments screen — nothing was saved',
  pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p0')));
select pg_temp.as_user(:'sw', format('select (public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''pp1 S3''))->>''id''', :'cust', :'wh')) as so3 \gset
select pg_temp.pay(:'sw', :'cust'::uuid, 2.00, 'cash', :'cad'::uuid, :'wh'::uuid, array[:'so3'::uuid], 'pp1 warehouse')::text as p3 \gset
select pg_temp.chk('R3 payment on a warehouse order → refused (not a POS sale)', pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p3')) like 'ERR P0001: Sale SO-% is a warehouse order, not a POS sale — a manager voids the payment on the Payments screen — nothing was saved',
  pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p3')));
select pg_temp.mk_pos(:'sw', :'cust'::uuid, :'pid'::uuid, :'wh'::uuid, :'r13'::uuid, :'r13_name', 1, 10.00, 'pp1 S4')::text as so4 \gset
select pg_temp.pay(:'sw', :'cust'::uuid, 2.00, 'cash', :'cad'::uuid, :'wh'::uuid, array[:'so4'::uuid], 'pp1 S4 cash')::text as p4 \gset
set local session_replication_role = replica;
update public.so set status = 'fulfilled', closed_at = now() where id = :'so4'::uuid;
set local session_replication_role = origin;
select pg_temp.chk('R4 payment on a fulfilled sale (after Finish) → refused', pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p4')) like 'ERR P0001: Sale SO-% is fulfilled — after Finish, a manager voids the payment on the Payments screen — nothing was saved',
  pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p4')));
set local session_replication_role = replica;
insert into public.so_payment (kind, amount, paid_on, method, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, created_by)
  select 'refund', 1.00, public.ims_today(), 'cash', :'cust'::uuid, :'cad'::uuid, 'CAD', p.account_id, p.account_code, :'wh'::uuid, :'whname', :'sw_id'::uuid from public.so_payment p where p.id = :'pd'::uuid returning id::text as prf \gset
insert into public.so_payment_order (payment_id, so_id) values (:'prf'::uuid, :'so1'::uuid);
insert into public.so_payment (kind, amount, paid_on, method, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, created_by)
  select 'payment', 9.00, public.ims_today(), 'opening', :'cust'::uuid, :'cad'::uuid, 'CAD', p.account_id, p.account_code, :'wh'::uuid, :'whname', :'sw_id'::uuid from public.so_payment p where p.id = :'pd'::uuid returning id::text as pop \gset
insert into public.so_payment_order (payment_id, so_id) values (:'pop'::uuid, :'so1'::uuid);
set local session_replication_role = origin;
select pg_temp.chk('R5 refund → refused', pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'prf')) = 'ERR P0001: This is a refund, not a payment — a manager voids it on the Payments screen — nothing was saved',
  pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'prf')));
select pg_temp.chk('R6 opening → refused', pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'pop')) = 'ERR P0001: This is the opening balance carried forward from the previous system — it cannot be cancelled here — nothing was saved',
  pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'pop')));
select pg_temp.chk('R7 unknown payment id → refused', pg_temp.as_user(:'sw', 'select public.so_pos_payment_cancel(gen_random_uuid(), null)::text') = 'ERR P0001: Payment not found — nothing was saved',
  pg_temp.as_user(:'sw', 'select public.so_pos_payment_cancel(gen_random_uuid(), null)::text'));
-- 이견 6: so_payment_attach(sales) 가 POS 예치금을 그 손님의 다른 열린 인보이스에 붙일 수 있다 — 살아 있는 alloc 이면 거부(인보이스 번호) · manager 가 떼면 취소된다
select pg_temp.mk_inv('99986001', :'cust'::uuid, :'cad'::uuid, 10.00)::text as inv1 \gset
select pg_temp.pay(:'sw', :'cust'::uuid, 8.00, 'cash', :'cad'::uuid, :'wh'::uuid, array[:'so1'::uuid], 'pp1 cash 8 alloc')::text as p8 \gset
select pg_temp.as_user(:'sw', format('select public.so_payment_attach(%L, %L::jsonb)::text', :'p8', jsonb_build_array(jsonb_build_object('invoice_id', :'inv1', 'amount', 3))::text)) as at1 \gset
select pg_temp.j(:'at1')#>>'{allocations,0,alloc_id}' as al1 \gset
select pg_temp.chk('R8a sales worker attached 3 of the POS deposit to invoice 99986001 (so_payment_attach · no manager gate) → cancel refused naming the invoice',
  :'al1' is not null and pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p8')) = 'ERR P0001: Part of this payment was applied to invoice 99986001 on the Payments screen — a manager detaches it there first — nothing was saved',
  format('attach %s | cancel %s', left(:'at1', 200), pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p8'))));
select pg_temp.as_user(:'sm', format('select public.so_payment_detach(%L, ''pp1 detach'')::text', :'al1')) as dt1 \gset
select pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p8')) as c8 \gset
select pg_temp.chk('R8b manager detached → cashier cancel OK', left(:'dt1', 4) <> 'ERR ' and pg_temp.j(:'c8')->>'status' = 'voided', format('detach %s | cancel %s', left(:'dt1', 200), left(:'c8', 200)));

\echo '── P) 권한 — sales 없는 사람 거부 · 다른 창고만 가진 sales worker OK(이견 3 · 경계 없음) · so_payment_void 는 manager 만 · acl'
select pg_temp.pay(:'sw', :'cust'::uuid, 2.00, 'cash', :'cad'::uuid, :'wh'::uuid, array[:'so1'::uuid], 'pp1 cash 2 perms')::text as pp \gset
select pg_temp.chk('P1 no sales key → refused (first gate · nothing else checked)', pg_temp.as_user(:'w0', format('select public.so_pos_payment_cancel(%L, null)::text', :'pp')) = 'ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved',
  pg_temp.as_user(:'w0', format('select public.so_pos_payment_cancel(%L, null)::text', :'pp')));
select pg_temp.chk('P1b no sales key → list refused', pg_temp.as_user(:'w0', format('select public.so_pos_payment_list(%L)::text', :'so1')) = 'ERR P0001: You cannot view sales data — ask an admin to add the ''sales'' permission',
  pg_temp.as_user(:'w0', format('select public.so_pos_payment_list(%L)::text', :'so1')));
select pg_temp.as_user(:'sx', format('select public.so_pos_payment_cancel(%L, null)::text', :'pp')) as cx \gset
select pg_temp.chk(format('P2 sales worker whose warehouse_access is only %s cancels a %s sale → OK (no warehouse gate · same gate as so_payment_add)', :'wh2name', :'whname'),
  pg_temp.j(:'cx')->>'status' = 'voided' and pg_temp.pstate(:'pp'::uuid) like 'voided|PP1 SX|%', coalesce(left(:'cx', 300), '(null)'));
select pg_temp.chk('P3 so_payment_void by sales worker → still manager only', pg_temp.as_user(:'sw', format('select public.so_payment_void(%L, ''pp1'')::text', :'pd')) = 'ERR P0001: This needs a manager or above (you are worker) — nothing was saved',
  pg_temp.as_user(:'sw', format('select public.so_payment_void(%L, ''pp1'')::text', :'pd')));
select pg_temp.as_user(:'sm', format('select public.so_payment_void(%L, ''pp1 manager void'')::text', :'pd')) as vd \gset
select pg_temp.chk('P4 so_payment_void by manager still works on the debit payment (status voided · note as given)', pg_temp.j(:'vd')->>'status' = 'voided' and pg_temp.pstate(:'pd'::uuid) = 'voided|PP1 SM|pp1 manager void|true', coalesce(left(:'vd', 300), '(null)'));
select pg_temp.as_user(:'sw', format('select public.so_pos_payment_list(%L)::text', :'so1')) as l3 \gset
select pg_temp.chk('P5 list(S1) now: 10 rows (cash5 · debit12 · cash3 · cash1 · cash4 · two-sales 6 · refund · opening 9 · cash8 · cash2) · debit voided_by PP1 SM · active_total 15 = two-sales 6 + opening 9',
  jsonb_array_length(pg_temp.j(:'l3')->'payments') = 10 and trim_scale((pg_temp.j(:'l3')->>'active_total')::numeric) = 15
  and (select x->>'voided_by_name' from jsonb_array_elements(pg_temp.j(:'l3')->'payments') x where x->>'method' = 'debit_card') = 'PP1 SM',
  format('rows %s active_total %s', jsonb_array_length(pg_temp.j(:'l3')->'payments'), pg_temp.j(:'l3')->>'active_total'));
select pg_temp.chk('P6 acl: authenticated execute · anon · service_role none (both functions)',
  has_function_privilege('authenticated', 'public.so_pos_payment_cancel(uuid, text)', 'execute') and not has_function_privilege('anon', 'public.so_pos_payment_cancel(uuid, text)', 'execute') and not has_function_privilege('service_role', 'public.so_pos_payment_cancel(uuid, text)', 'execute')
  and has_function_privilege('authenticated', 'public.so_pos_payment_list(uuid)', 'execute') and not has_function_privilege('anon', 'public.so_pos_payment_list(uuid)', 'execute') and not has_function_privilege('service_role', 'public.so_pos_payment_list(uuid)', 'execute'),
  (select array_to_string(proacl, ',') from pg_proc where oid = to_regprocedure('public.so_pos_payment_cancel(uuid, text)')));
select pg_temp.chk('P7 list of an unknown order → refused · list of S2 → 1 row (the two-sales payment · targets 2)',
  pg_temp.as_user(:'sw', 'select public.so_pos_payment_list(gen_random_uuid())::text') = 'ERR P0001: Order not found'
  and (select jsonb_array_length(j->'payments') || '/' || (j#>>'{payments,0,targets}') from pg_temp.j(pg_temp.as_user(:'sw', format('select public.so_pos_payment_list(%L)::text', :'so2'))) j) = '1/2',
  pg_temp.as_user(:'sw', format('select public.so_pos_payment_list(%L)::text', :'so2')));

\echo '── Z) 무접촉 · 착지'
select pg_temp.chk('Z0 untouched prosrc md5: so_payment_void · so_payment_add · so_pos_complete · so_pos_finish · so_payment_attach · so_payment_alloc_add',
  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_void') = :'md5_void0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_add') = :'md5_add0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_complete') = :'md5_complete0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_finish') = :'md5_finish0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_attach') = :'md5_attach0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_alloc_add') = :'md5_alloc0'
  and :'md5_void0' = '48097c4f430652d14e95522ec6ca2269', :'md5_void0');
select pg_temp.chk('Z0b exactly two new functions · both definer · list stable · cancel volatile · no table/column/policy added (so_payment columns unchanged)',
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_pos_payment_cancel', 'so_pos_payment_list')) = 2
  and (select bool_and(prosecdef) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_pos_payment_cancel', 'so_pos_payment_list'))
  and (select provolatile::text from pg_proc where oid = to_regprocedure('public.so_pos_payment_list(uuid)')) = 's'
  and (select provolatile::text from pg_proc where oid = to_regprocedure('public.so_pos_payment_cancel(uuid, text)')) = 'v'
  and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_payment') = :w_paycols, 'see Z0b');
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_here \gset
\echo '── begin ~ here:' :begin_to_here
rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 실제 행 무변 · 시퀀스 되돌리기'
select pg_temp.chk('Z1 real rows unchanged after rollback (so · so_payment · order · alloc · invoice · staff · customer · product) · fake traces 0',
  (select count(*) from public.so) = :w_so and (select count(*) from public.so_payment) = :w_pay and (select count(*) from public.so_payment_order) = :w_po and (select count(*) from public.so_payment_alloc) = :w_pa
  and (select count(*) from public.so_invoice) = :w_inv and (select count(*) from public.ims_staff) = :w_staff and (select count(*) from public.customer) = :w_cust and (select count(*) from public.product) = :w_prod
  and (select count(*) from public.customer where name = 'PP1 Customer') + (select count(*) from public.product where sku = 'PP1-P') + (select count(*) from public.ims_staff where email like 'pp1-%') + (select count(*) from public.inv_ledger where sku = 'PP1-P') + (select count(*) from public.so_invoice where invoice_number = '99986001') = 0,
  format('so %s/%s pay %s/%s staff %s/%s', (select count(*) from public.so), :w_so, (select count(*) from public.so_payment), :w_pay, (select count(*) from public.ims_staff), :w_staff));
\if :{?mig}
select pg_temp.chk('Z2 (trial only) rollback restored: the two functions are gone', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_pos_payment_cancel', 'so_pos_payment_list')) = 0, 'functions remain');
\else
select pg_temp.chk('Z2 (confirm) the two functions are in the DB · schema_migrations has 20261029005830', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_pos_payment_cancel', 'so_pos_payment_list')) = 2 and :n_applied = 1, format('fn %s applied %s', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_pos_payment_cancel', 'so_pos_payment_list')), :n_applied));
\endif
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
select (select last_value || '|' || is_called from public.so_number_seq) as so_seq_after, (select last_value || '|' || is_called from public.so_invoice_number_seq) as inv_seq_after;
