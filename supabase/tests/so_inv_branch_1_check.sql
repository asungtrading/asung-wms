-- supabase/tests/so_inv_branch_1_check.sql — so-inv-branch-1 뷰 so_invoice_list 창고 칸 셋(warehouse_id · warehouse_name · warehouse_source) 검증 (2026-11-03 · 판정 994)
-- [테스트 · Asung-IMS] 시험 적용 장치 — db_role = test 가드 → 기준(begin 앞: 함수 8 md5 · acl · 뷰 acl · reloptions · 칸 수 · 실제 행 수) → begin → (-v mig 면 \i) → 옛 본문(ar-2 바이트)을 temp view 로 → 검사 → rollback → Z1
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261103070000_so_inv_branch_1.sql -f supabase/tests/so_inv_branch_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   결과 줄 꼴 | OK | / | MISMATCH | · 쓰기 0(temp view · temp table 만) · lock_timeout 3s · begin ~ rollback 시간을 끝에 찍는다(10 초 안)
\set ON_ERROR_STOP on
\pset pager off
select coalesce((select value from public.inv_config where key = 'db_role'), '(missing)') as db_role \gset
select (:'db_role' = 'test') as is_test \gset
\echo '── db_role' :db_role
\if :is_test
\else
\echo 'STOP — inv_config.db_role is not test — nothing was run'
\quit
\endif
-- ── 기준(begin 앞) ──
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5, p.proacl::text as acl
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('doc_data_invoice', 'shop_order_ingest', 'shop_order_paid_state', 'so_credit_detail', 'so_customer_overdue', 'so_invoice_ar_summary', 'so_invoice_detail', 'so_payment_detail');
select (select count(*) from t_pre) as fn_n0 \gset
select relacl::text as view_acl0, reloptions::text as view_opt0 from pg_class where relname = 'so_invoice_list' and relnamespace = 'public'::regnamespace \gset
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice_list') as cols0 \gset
select (select count(*) from public.so_invoice) as w_inv, (select count(*) from public.so_invoice_order) as w_io, (select count(*) from public.customer) as w_cust, (select count(*) from public.so) as w_so, (select count(*) from public.ref_warehouse) as w_wh \gset
\echo '── 기준: 함수' :fn_n0 '· 뷰 칸' :cols0 '· acl' :view_acl0 '· opt' :view_opt0 '· so_invoice' :w_inv '· so_invoice_order' :w_io '· customer' :w_cust '· so' :w_so '· ref_warehouse' :w_wh
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin0 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;

-- ── 옛 본문 = 20261027014202(ar-2) 330 ~ 377 행 바이트 그대로(temp view · 옛 43 칸) ──
create temp view t_old as
with ord as (
  select o.invoice_id,
         string_agg(o.so_number, ', ' order by o.so_number) filter (where o.cancelled_at is null)  as so_numbers,
         array_agg(o.so_id order by o.so_number)             filter (where o.cancelled_at is null)  as so_ids,
         count(*)                                             filter (where o.cancelled_at is null)  as order_count,
         case when count(distinct s.channel) filter (where o.cancelled_at is null) > 1 then 'mixed'
              else min(s.channel) filter (where o.cancelled_at is null) end                          as channel,
         string_agg(o.so_number || coalesce(' ' || s.ref, ''), ' ' order by o.so_number) filter (where o.cancelled_at is null) as order_text
  from public.so_invoice_order o
  join public.so s on s.id = o.so_id
  group by o.invoice_id
),
pay as (   -- 살아 있는 결제 붙임(so_invoice_remaining 과 같은 조건)
  select a.invoice_id, sum(a.amount) as paid
  from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
  where a.voided_at is null and p.status = 'active'
  group by a.invoice_id
),
cred as (  -- 살아 있는 크레딧 붙임(issued 크레딧만)
  select a.invoice_id, sum(a.amount) as credited
  from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id
  where a.invoice_id is not null and a.voided_at is null and c.status = 'issued'
  group by a.invoice_id
)
select i.id, i.invoice_number, i.status, i.issued_on, i.due_on, i.payment_term_name, i.currency_id, i.currency_code,
       i.bill_to_customer_id, i.bill_to_name, cu.name as customer_name,
       o.so_numbers, o.so_ids, coalesce(o.order_count, 0)::int as order_count, o.channel,
       i.lines_amount, i.order_discount_amount, i.charges_amount, i.tax_amount, i.total,
       i.deposit_applied, i.credit_applied, i.balance_forward, i.amount_due,
       coalesce(pay.paid, 0)       as paid,
       coalesce(cred.credited, 0)  as credited,
       r.remaining,
       (i.due_on is null)          as due_unknown,
       case when i.status = 'issued' and r.remaining > 0 and i.due_on is not null and i.due_on < public.ims_today()
            then (public.ims_today() - i.due_on) else 0 end::int as days_overdue,
       (i.status = 'issued' and r.remaining > 0) as is_open,
       i.cancelled_at, i.cancel_note, i.note, i.created_at,
       (i.invoice_number || ' ' || coalesce(i.bill_to_name, '') || ' ' || coalesce(cu.name, '') || ' ' || coalesce(o.order_text, '')) as search_text,
       i.surcharge_amount,                                                                                                     -- surcharge-2b(끝에 — create or replace view 는 열을 끝에만 더할 수 있다)
       i.charges_discount_amount,                                                                                              -- fr-2 판정 352(끝에 — 같은 이유)
       i.kind, i.prior_settled, i.store_customer_id, st.name as store_name, i.legacy_sale_id, i.legacy_invoice_id                      -- ar-2 판정 783(끝에 — 같은 이유 · so_invoice_detail 의 invoice 행이 이 뷰)
from public.so_invoice i
left join public.customer cu on cu.id = i.bill_to_customer_id
left join public.customer st on st.id = i.store_customer_id                                                                       -- ar-2: 이월 인보이스의 매장(sale 은 null)
left join ord o on o.invoice_id   = i.id
left join pay  on pay.invoice_id  = i.id
left join cred on cred.invoice_id = i.id
cross join lateral (select public.so_invoice_remaining(i.id) as remaining) r;   -- 읽기 함수(stable)를 lateral 에서 한 번만 — 쓰기 창구가 아니다

-- ── A 칸 모양 ──
select pg_temp.chk('A1 column count 46 (43 old + 3 new)', (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice_list'), '46');
select pg_temp.chk('A2 new columns at the end · names · types · order',
  (select string_agg(column_name || ':' || data_type, ',' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice_list' and ordinal_position > 43),
  'warehouse_id:uuid,warehouse_name:text,warehouse_source:text');
select pg_temp.chk('A3 old 43 columns · names · order unchanged (= t_old)',
  (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice_list' and ordinal_position <= 43),
  (select string_agg(attname, ',' order by attnum) from pg_attribute where attrelid = 't_old'::regclass and attnum > 0 and not attisdropped));

-- ── B 옛 칸 값 무변(양방향 except 0 · 옛 43 칸만) ──
create temp table t_new43 as select id, invoice_number, status, issued_on, due_on, payment_term_name, currency_id, currency_code, bill_to_customer_id, bill_to_name, customer_name, so_numbers, so_ids, order_count, channel, lines_amount, order_discount_amount, charges_amount, tax_amount, total, deposit_applied, credit_applied, balance_forward, amount_due, paid, credited, remaining, due_unknown, days_overdue, is_open, cancelled_at, cancel_note, note, created_at, search_text, surcharge_amount, charges_discount_amount, kind, prior_settled, store_customer_id, store_name, legacy_sale_id, legacy_invoice_id from public.so_invoice_list;
select pg_temp.chk('B1 new − old = 0 rows (old 43 columns)', (select count(*)::text from (select * from t_new43 except select * from t_old) x), '0');
select pg_temp.chk('B2 old − new = 0 rows (old 43 columns)', (select count(*)::text from (select * from t_old except select * from t_new43) x), '0');
select pg_temp.chk('B3 row count new = old = so_invoice', (select count(*) from public.so_invoice_list)::text || '/' || (select count(*) from t_old)::text || '/' || (select count(*) from public.so_invoice)::text,
  (select count(*) from public.so_invoice)::text || '/' || (select count(*) from public.so_invoice)::text || '/' || (select count(*) from public.so_invoice)::text);

-- ── S 판정 994 — 새 칸 값 ──
create temp table t_exp as
  with ord as (select o.invoice_id, (array_agg(s.location_id order by o.so_number) filter (where o.cancelled_at is null))[1] as wh_id, count(*) filter (where o.cancelled_at is null) as n
               from public.so_invoice_order o join public.so s on s.id = o.so_id group by o.invoice_id)
  select i.id,
         case when coalesce(o.n, 0) > 0 then o.wh_id else coalesce(st.default_location_id, cu.default_location_id) end as exp_id,
         case when coalesce(o.n, 0) > 0 then 'so' when st.default_location_id is not null then 'store' when cu.default_location_id is not null then 'bill_to' end as exp_src,
         coalesce(o.n, 0) as n
  from public.so_invoice i left join ord o on o.invoice_id = i.id
  left join public.customer st on st.id = i.store_customer_id left join public.customer cu on cu.id = i.bill_to_customer_id;
select pg_temp.chk('S1 invoices with live orders: warehouse_id = first SO (so_number order) location_id · source so — mismatches',
  (select count(*)::text from public.so_invoice_list l join t_exp e on e.id = l.id where e.n > 0 and (l.warehouse_id is distinct from e.exp_id or l.warehouse_source is distinct from case when e.exp_id is null then null else 'so' end)), '0');
select pg_temp.chk('S2 invoices without live orders: warehouse_id = store default_location_id → bill_to default_location_id · source store | bill_to | null — mismatches',
  (select count(*)::text from public.so_invoice_list l join t_exp e on e.id = l.id where e.n = 0 and (l.warehouse_id is distinct from e.exp_id or l.warehouse_source is distinct from case when e.exp_id is null then null else e.exp_src end)), '0');
select pg_temp.chk('S3 warehouse_name = ref_warehouse.name (null ↔ null) — mismatches',
  (select count(*)::text from public.so_invoice_list l left join public.ref_warehouse w on w.id = l.warehouse_id where l.warehouse_name is distinct from w.name), '0');
select pg_temp.chk('S4 warehouse_source null ↔ warehouse_id null · values ⊆ {so, store, bill_to} — violations',
  (select count(*)::text from public.so_invoice_list where (warehouse_id is null) <> (warehouse_source is null) or warehouse_source not in ('so', 'store', 'bill_to')), '0');
select pg_temp.chk('S5 open opening (carried-over) invoices with warehouse_id null (would show under All branches only)',
  (select count(*)::text from public.so_invoice_list where kind = 'opening' and is_open and warehouse_id is null), '0');
select pg_temp.chk('S6 store ≠ bill_to default branch among open opening invoices → view follows the store',
  (select count(*)::text from public.so_invoice_list l join public.customer st on st.id = l.store_customer_id join public.customer cu on cu.id = l.bill_to_customer_id
    where l.kind = 'opening' and l.is_open and st.default_location_id is distinct from cu.default_location_id and st.default_location_id is not null and l.warehouse_id <> st.default_location_id), '0');
select pg_temp.chk('S7 sample 60005 (sale · SO-20061): warehouse = so.location_id of SO-20061 · source so',
  (select l.warehouse_id::text || '|' || l.warehouse_source from public.so_invoice_list l where l.invoice_number = '60005'),
  (select s.location_id::text || '|so' from public.so s where s.so_number = 'SO-20061'));
select pg_temp.chk('S8 sample 50663 (opening · NAOCIE · Edmonton store): warehouse = store default · source store',
  (select l.warehouse_id::text || '|' || l.warehouse_name || '|' || l.warehouse_source from public.so_invoice_list l where l.invoice_number = '50663'),
  (select st.default_location_id::text || '|' || st.default_location_name || '|store' from public.so_invoice i join public.customer st on st.id = i.store_customer_id where i.invoice_number = '50663'));
select pg_temp.chk('S9 Unpaid at hand-over rows (is_open · pay-now term): per-branch counts add up to the whole (All branches = 전부)',
  (select (count(*) filter (where warehouse_id is not null) + count(*) filter (where warehouse_id is null))::text || '/' || count(*)::text from public.so_invoice_list where is_open and payment_term_name in (select name from public.ref_payment_term where net_days = 0)),
  (select count(*)::text || '/' || count(*)::text from public.so_invoice_list where is_open and payment_term_name in (select name from public.ref_payment_term where net_days = 0)));
\echo '── 정보: Unpaid at hand-over 줄 — 브랜치 · 출처별'
select coalesce(warehouse_name, '(null → All branches only)') as branch, warehouse_source, count(*) from public.so_invoice_list where is_open and payment_term_name in (select name from public.ref_payment_term where net_days = 0) group by 1, 2 order by 1, 2;
\echo '── 정보: 전체 인보이스 — 출처별'
select coalesce(warehouse_source, '(null)') as source, count(*) from public.so_invoice_list group by 1 order by 1;

-- ── M 무접촉 · 권한 · comment · 의존 함수 ──
select pg_temp.chk('M1 security_invoker = true', (select reloptions::text from pg_class where relname = 'so_invoice_list' and relnamespace = 'public'::regnamespace), '{security_invoker=true}');
select pg_temp.chk('M2 view acl = begin 앞 (authenticated r only)', (select relacl::text from pg_class where relname = 'so_invoice_list' and relnamespace = 'public'::regnamespace), :'view_acl0');
select pg_temp.chk('M3 authenticated select · no insert · anon none',
  (select (has_table_privilege('authenticated', 'public.so_invoice_list', 'select') and not has_table_privilege('authenticated', 'public.so_invoice_list', 'insert') and not has_table_privilege('anon', 'public.so_invoice_list', 'select'))::text), 'true');
select pg_temp.chk('M4 comment carries 판정 994 and the three column names',
  (select (c like '%판정 994%' and c like '%warehouse_id%' and c like '%warehouse_name%' and c like '%warehouse_source%')::text from (select obj_description('public.so_invoice_list'::regclass, 'pg_class') as c) x), 'true');
select pg_temp.chk('M5 dependent functions 8 untouched (prosrc md5 · acl = begin 앞)',
  (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5 and p.proacl::text is not distinct from t.acl), '8');
select pg_temp.chk('M6 so_invoice_detail(60005) → invoice JSON gains the three keys (additive · to_jsonb(v))',
  (select ((d->'invoice') ? 'warehouse_id' and (d->'invoice') ? 'warehouse_name' and (d->'invoice') ? 'warehouse_source')::text from (select public.so_invoice_detail(id) as d from public.so_invoice where invoice_number = '60005') x), 'true');
select pg_temp.chk('M7 no other view depends on so_invoice_list (pg_depend)',
  (select count(*)::text from pg_depend d join pg_rewrite r on r.oid = d.objid join pg_class dc on dc.oid = r.ev_class where d.refobjid = 'public.so_invoice_list'::regclass and dc.oid <> 'public.so_invoice_list'::regclass and dc.relpersistence <> 't'), '0');

-- ── T 시간(Unpaid at hand-over 꼴 · 전 = §0 조사 37 ms) ──
select clock_timestamp() as t_q0 \gset
select count(*) as unpaid_n from public.so_invoice_list where is_open and payment_term_name in (select name from public.ref_payment_term where net_days = 0) and warehouse_id = (select id from public.ref_warehouse where name = 'Asung Trading Inc.') \gset
select clock_timestamp() - :'t_q0'::timestamptz as t_unpaid \gset
\echo '── 시간: Unpaid 꼴(Toronto 거르기 · 줄' :unpaid_n ')' :t_unpaid

-- ── 결과 ──
select clock_timestamp() - :'t_begin0'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, count(*) as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice_list') = :cols0
            and (select relacl::text from pg_class where relname = 'so_invoice_list' and relnamespace = 'public'::regnamespace) = :'view_acl0'
            and (select count(*) from public.so_invoice) = :w_inv and (select count(*) from public.so_invoice_order) = :w_io and (select count(*) from public.customer) = :w_cust and (select count(*) from public.so) = :w_so and (select count(*) from public.ref_warehouse) = :w_wh
            and (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :fn_n0
       then 'Z1 OK after rollback: view columns · acl · functions · real rows (so_invoice · so_invoice_order · customer · so · ref_warehouse) = begin 앞'
       else 'Z1 MISMATCH after rollback' end as z1;
