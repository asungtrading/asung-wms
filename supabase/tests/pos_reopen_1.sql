-- supabase/tests/pos_reopen_1.sql — pos-reopen-1 so_line_remove · so_lines_clear 재발행 검증 (2026-10-28 · 판정 863 줄기 · 실물 SO-25237 · 이견 1 ~ 9)
-- [테스트 · Asung-IMS] 시험 적용 장치 — begin → 가짜 재료 → (-v mig 면 재현 X0 → \i) → 갈래 → rollback → 가짜 흔적 0 · 시퀀스 되돌림 · 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029014000_pos_reopen_1.sql -f supabase/tests/pos_reopen_1.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK = 시험 OK − 시험 전용(X0 · X0b · G0 · Z2 시험 갈래) + Z2 확인 갈래 — 머리의 EXPECT 줄 참조(통과한 실행에서 받아 적는다)
--   ⚠️ \i 가 머리가 아니라 S1 뒤에 있다 — 고치기 전의 실물 벽(23503)을 같은 재료로 먼저 재현하고(X0 · X0b · 시험 갈래만) 그 다음 적용해 같은 줄이 OK 가 되는 것을 본다 · 마이그레이션은 create or replace function + comment 뿐(표 잠금 없음)
--   재료(전부 가짜 · PR1): 직원 넷(SW worker sales · SV supervisor sales · SM manager sales · W0 열쇠 없음) · 손님 PR1 Customer(CAD · 브랜치 = 첫 창고) · 제품 PR1-A · PR1-B 장부 50 씩 · POS 판매 S1 · S2 · S3 · 초안 S0 · warehouse 오더 S4
--   ⚠️ so_create 가 so_number_seq 를 당긴다 → 끝에 greatest(실제 최대, 머리) 로 되돌린다 · 인보이스 번호는 당기지 않는다(Finish 는 p_commit false 미리 보기만)
--   EXPECT: 시험(-v mig) OK 28 · 확인(-v mig 없음) OK 25(X0 · X0b · G0 빠짐 · Z2 는 확인 갈래 줄) — 회차 4 통과 출력에서 받아 적음
\set ON_ERROR_STOP on
\pset pager off
\echo '── db_role · schema_migrations · 재발행 둘 · 무접촉 일곱 md5 · FK · 시퀀스 머리 · 실제 행 수'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261029014000' \gset
select (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_remove') as md5_remove0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_clear') as md5_clear0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_reopen') as md5_reopen0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') as md5_delete0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_confirm') as md5_posconfirm0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_allocate_all') as md5_allocall0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') as md5_unconfirm0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_update') as md5_lineupdate0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_cancel') as md5_cancel0,
       (select array_to_string(proacl, ',') from pg_proc where oid = to_regprocedure('public.so_line_remove(uuid)')) as acl_remove0,
       (select array_to_string(proacl, ',') from pg_proc where oid = to_regprocedure('public.so_lines_clear(uuid, boolean)')) as acl_clear0,
       (select pg_get_constraintdef(oid) from pg_constraint where conname = 'so_reserve_so_line_id_fkey' and conrelid = 'public.so_reserve'::regclass) as fk0 \gset
select :n_applied as schema_migrations_rows_for_20261029014000, :'md5_remove0' as md5_remove0, :'md5_clear0' as md5_clear0, :'fk0' as fk0;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select :so_seq_last as so_seq_head, :'so_seq_called' as so_called, (select max(substring(so_number from '[0-9]+')::bigint) from public.so) as so_max_head,
       :inv_seq_last as inv_seq_head, :'inv_seq_called' as inv_called;
select (select count(*) from public.so) as w_so, (select count(*) from public.so_line) as w_line, (select count(*) from public.so_reserve) as w_res, (select count(*) from public.so_payment) as w_pay,
       (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.customer) as w_cust, (select count(*) from public.product) as w_prod, (select count(*) from public.inv_ledger) as w_ledger \gset
\echo '── 기준: so' :w_so '· so_line' :w_line '· so_reserve' :w_res '· staff' :w_staff '· remove md5' :md5_remove0 '· clear md5' :md5_clear0
-- chk 는 트랜잭션 밖에서 만든다 — rollback 뒤의 Z1 · Z2 도 부른다
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset

\echo '── 도우미'
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- POS 판매 하나: 초안 → 줄 둘(A · B) → 세금 규칙(replica · 가짜 손님은 주소가 없다 · pos_pay_1 과 같다) → so_pos_confirm
create function pg_temp.mk_pos(p_claims text, p_cust uuid, p_pid_a uuid, p_qa numeric, p_pid_b uuid, p_qb numeric, p_wh uuid, p_rule uuid, p_rule_name text, p_note text) returns uuid language plpgsql as $$
declare v_x jsonb; v_so uuid;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  v_x := public.so_create(p_cust, 'pos', 'pos', p_wh, p_note);  v_so := (v_x->>'id')::uuid;
  v_x := public.so_line_add(v_so, p_pid_a, p_qa, 10.00, null, null, null, false);
  if p_pid_b is not null then v_x := public.so_line_add(v_so, p_pid_b, p_qb, 20.00, null, null, null, false); end if;
  execute 'set local session_replication_role = replica';
  update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
  execute 'set local session_replication_role = origin';
  v_x := public.so_pos_confirm(v_so);
  return v_so;
end $$;
-- 그 오더의 예약 행 지문: open|released  (열린 행 수 · 풀린 행 수)
create function pg_temp.res(p_so uuid) returns text language sql security definer as $$
  select count(*) filter (where r.released_at is null) || '|' || count(*) filter (where r.released_at is not null)
  from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = p_so $$;
-- 가용 지문: 창고 × 제품 → sales_alloc_ea · (qty − alloc)
create function pg_temp.av(p_wh uuid, p_pid uuid) returns text language sql security definer as $$
  select trim_scale(coalesce(b.sales_alloc_ea, 0)) || '|' || trim_scale(coalesce(b.qty_ea, 0) - coalesce(b.sales_alloc_ea, 0) - coalesce(b.transfer_alloc_ea, 0))
  from public.inv_available_base(p_wh, array[p_pid]) b where b.stock_pid = p_pid $$;
create function pg_temp.line_of(p_so uuid, p_pid uuid) returns uuid language sql security definer as $$
  select l.id from public.so_line l where l.so_id = p_so and l.product_id = p_pid order by l.line_no limit 1 $$;

\echo '── M) 재료'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pr1-sw@test.invalid', 'PR1 SW', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as sw_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pr1-sv@test.invalid', 'PR1 SV', 'supervisor', '["ims","sales"]', '{}') returning auth_user_id::text as sv_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pr1-w0@test.invalid', 'PR1 W0', 'worker', '[]', '{}') returning auth_user_id::text as w0_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pr1-sm@test.invalid', 'PR1 SM', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as sm_uid \gset
\set sw '{"sub":"' :sw_uid '","role":"authenticated"}'
\set sv '{"sub":"' :sv_uid '","role":"authenticated"}'
\set w0 '{"sub":"' :w0_uid '","role":"authenticated"}'
\set sm '{"sub":"' :sm_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.name as bina from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as r13, name as r13_name from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('PR1 Customer', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as cust \gset
insert into public.product (sku, name, source) values ('PR1-A', 'PR1 Product A', 'manual') returning id::text as pa \gset
insert into public.product (sku, name, source) values ('PR1-B', 'PR1 Product B', 'manual') returning id::text as pb \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
  values (public.ims_today() - 3, 1, 'PR1-A', :'whname', :'bina', 50, 'po_in', 'purchase', 'PO-PR1', 'pr1-1', 'manual'),
         (public.ims_today() - 3, 2, 'PR1-B', :'whname', :'bina', 50, 'po_in', 'purchase', 'PO-PR1', 'pr1-2', 'manual');
set local session_replication_role = origin;
select (select count(*) from public.shop_stock_queue q where q.product_id in (:'pa'::uuid, :'pb'::uuid)) as q0 \gset
select pg_temp.chk(format('M0 staff ×4 · customer (branch %s) · PR1-A · PR1-B stock 50 each (avail 0|50) · tax %s', :'whname', :'r13_name'),
  :'sw_uid' <> '' and :'sv_uid' <> '' and :'sm_uid' <> '' and :'w0_uid' <> '' and :'cust' <> '' and :'pa' <> '' and :'pb' <> '' and :'r13' <> ''
  and pg_temp.av(:'wh'::uuid, :'pa'::uuid) = '0|50' and pg_temp.av(:'wh'::uuid, :'pb'::uuid) = '0|50', format('avA %s avB %s', pg_temp.av(:'wh'::uuid, :'pa'::uuid), pg_temp.av(:'wh'::uuid, :'pb'::uuid)));

\echo '── S1) POS 판매 S1(A×2 · B×3) → Confirm → 결제 cash 5 → 계산대 취소 → Reopen — 실물 SO-25237 의 순서'
select pg_temp.mk_pos(:'sw', :'cust'::uuid, :'pa'::uuid, 2, :'pb'::uuid, 3, :'wh'::uuid, :'r13'::uuid, :'r13_name', 'pr1 S1')::text as so1 \gset
select s.so_number as so1_num from public.so s where s.id = :'so1'::uuid \gset
select pg_temp.line_of(:'so1'::uuid, :'pa'::uuid)::text as l1a, pg_temp.line_of(:'so1'::uuid, :'pb'::uuid)::text as l1b \gset
select pg_temp.chk('S1a S1 confirmed · reserve open 2 (A 2 · B 3 allocated) · availability A 2|48 · B 3|47',
  (select s.status from public.so s where s.id = :'so1'::uuid) = 'confirmed' and pg_temp.res(:'so1'::uuid) = '2|0'
  and pg_temp.av(:'wh'::uuid, :'pa'::uuid) = '2|48' and pg_temp.av(:'wh'::uuid, :'pb'::uuid) = '3|47',
  format('res %s avA %s avB %s', pg_temp.res(:'so1'::uuid), pg_temp.av(:'wh'::uuid, :'pa'::uuid), pg_temp.av(:'wh'::uuid, :'pb'::uuid)));
select pg_temp.as_user(:'sw', format('select (public.so_payment_add(%L::jsonb))->>''payment_id''', jsonb_build_object('customer_id', :'cust', 'amount', 5, 'paid_on', public.ims_today(), 'method', 'cash', 'reference', 'pr1 cash 5',
                                                   'currency_id', :'cad', 'warehouse_id', :'wh', 'target_so_ids', jsonb_build_array(:'so1'))::text)) as pc \gset
select pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'pc')) as c1 \gset
select pg_temp.as_user(:'sw', format('select public.so_pos_reopen(%L)::text', :'so1')) as ro1 \gset
select pg_temp.chk('S1b cash 5 taken then cancelled at POS (voided) · Reopen → draft · reservations_released 2 · reserve 0 open | 2 released · availability back to 0|50 (released rows do not count)',
  pg_temp.j(:'c1')->>'status' = 'voided' and pg_temp.j(:'ro1')->>'status' = 'draft' and (pg_temp.j(:'ro1')->>'reservations_released')::int = 2
  and (select s.status from public.so s where s.id = :'so1'::uuid) = 'draft' and pg_temp.res(:'so1'::uuid) = '0|2'
  and pg_temp.av(:'wh'::uuid, :'pa'::uuid) = '0|50' and pg_temp.av(:'wh'::uuid, :'pb'::uuid) = '0|50',
  format('cancel %s | reopen %s | res %s', left(:'c1', 120), left(:'ro1', 200), pg_temp.res(:'so1'::uuid)));

\if :{?mig}
\echo '── X) 시험에서만 — 고치기 전 재현(실물 SO-25237 과 같은 벽)'
select pg_temp.chk('X0 (trial only · before the fix) remove line A of the reopened draft → 23503 so_reserve_so_line_id_fkey (the screen''s alert)',
  pg_temp.as_user(:'sw', format('select public.so_line_remove(%L)::text', :'l1a')) = 'ERR 23503: update or delete on table "so_line" violates foreign key constraint "so_reserve_so_line_id_fkey" on table "so_reserve"',
  pg_temp.as_user(:'sw', format('select public.so_line_remove(%L)::text', :'l1a')));
select pg_temp.chk('X0b (trial only · before the fix) so_lines_clear commit on the reopened draft → same 23503',
  pg_temp.as_user(:'sw', format('select public.so_lines_clear(%L, true)::text', :'so1')) like 'ERR 23503: %so_reserve_so_line_id_fkey%',
  pg_temp.as_user(:'sw', format('select public.so_lines_clear(%L, true)::text', :'so1')));
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
select pg_temp.chk('G0 시험에서만: 적용 전 schema_migrations 0 행 → 시험 적용 뒤 재발행 둘의 md5 가 바뀌었다',
  :n_applied = 0
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_remove') <> :'md5_remove0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_clear') <> :'md5_clear0', format('applied %s', :n_applied));
\endif

\echo '── R) 고친 뒤 — 줄 ✕ OK → 수량 고치기 → 다시 Confirm → 예약은 남은 줄 몫만 → 미리 보기'
select pg_temp.as_user(:'sw', format('select public.so_line_remove(%L)::text', :'l1a')) as rm1 \gset
select pg_temp.chk('R1 remove line A → OK · reserve_history_removed 1 · lines_left 1 · S1 reserve 0 open | 1 released (line B only) · availability A 0|50',
  pg_temp.j(:'rm1')->>'so_number' = :'so1_num' and (pg_temp.j(:'rm1')->>'reserve_history_removed')::int = 1 and (pg_temp.j(:'rm1')->>'lines_left')::int = 1 and (pg_temp.j(:'rm1')->>'removed_components')::int = 0
  and pg_temp.res(:'so1'::uuid) = '0|1' and (select count(*) from public.so_reserve r where r.so_line_id = :'l1a'::uuid) = 0
  and pg_temp.av(:'wh'::uuid, :'pa'::uuid) = '0|50', format('%s | res %s', left(:'rm1', 300), pg_temp.res(:'so1'::uuid)));
select pg_temp.as_user(:'sw', format('select public.so_line_update(%L, ''{"qty_ordered": 4}'')::text', :'l1b')) as up1 \gset
select pg_temp.chk('R2 line B qty 3 → 4 → OK (so_line_update untouched)', (pg_temp.j(:'up1')#>>'{line,qty_ordered}')::numeric = 4 and (select l.qty_ordered from public.so_line l where l.id = :'l1b'::uuid) = 4, left(:'up1', 200));
select pg_temp.as_user(:'sw', format('select public.so_pos_confirm(%L)::text', :'so1')) as rc1 \gset
select pg_temp.chk('R3 Confirm again → confirmed · lines_allocated 1 · reserve 1 open (B · qty 4 · allocated) | 1 released · availability A 0|50 · B 4|46',
  pg_temp.j(:'rc1')->>'status' = 'confirmed' and (pg_temp.j(:'rc1')->>'lines_allocated')::int = 1 and pg_temp.res(:'so1'::uuid) = '1|1'
  and (select r.kind || '|' || trim_scale(r.qty_allocated) from public.so_reserve r where r.so_line_id = :'l1b'::uuid and r.released_at is null) = 'allocated|4'
  and pg_temp.av(:'wh'::uuid, :'pa'::uuid) = '0|50' and pg_temp.av(:'wh'::uuid, :'pb'::uuid) = '4|46',
  format('%s | res %s avA %s avB %s', left(:'rc1', 200), pg_temp.res(:'so1'::uuid), pg_temp.av(:'wh'::uuid, :'pa'::uuid), pg_temp.av(:'wh'::uuid, :'pb'::uuid)));
select pg_temp.as_user(:'sw', format('select public.so_pos_finish(%L, false)::text', :'so1')) as pv1 \gset
select pg_temp.chk('R4 Finish preview (p_commit false) → committed false · estimate.total ≥ 80 (4 × 20) · deposit 0 (cash cancelled) · still confirmed',
  (pg_temp.j(:'pv1')->>'committed')::boolean = false and (pg_temp.j(:'pv1')#>>'{estimate,total}')::numeric >= 80 and coalesce((pg_temp.j(:'pv1')#>>'{estimate,deposit}')::numeric, 0) = 0
  and (select s.status from public.so s where s.id = :'so1'::uuid) = 'confirmed', left(:'pv1', 400));
select pg_temp.as_user(:'sw', format('select public.so_pos_reopen(%L)::text', :'so1')) as ro2 \gset
select pg_temp.as_user(:'sw', format('select public.so_line_remove(%L)::text', :'l1b')) as rm2 \gset
select pg_temp.chk('R5 Reopen again → remove line B (two released rows: first confirm + second) → OK · reserve_history_removed 2 · lines_left 0 · S1 reserve rows 0',
  pg_temp.j(:'ro2')->>'status' = 'draft' and (pg_temp.j(:'rm2')->>'reserve_history_removed')::int = 2 and (pg_temp.j(:'rm2')->>'lines_left')::int = 0 and pg_temp.res(:'so1'::uuid) = '0|0',
  format('%s | %s', left(:'ro2', 120), left(:'rm2', 300)));
select pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so1')) as d1 \gset
select pg_temp.chk('R6 (이견 6 · 이 차수 밖 · 전부터) S1 had a payment (cancelled) → so_delete is no longer stopped by the history gate but by so_payment_order_so_id_fkey 23503 (unreadable · pre-existing for any draft with a payment) · S1 stays',
  :'d1' like 'ERR 23503: update or delete on table "so" violates foreign key constraint "so_payment_order_so_id_fkey"%' and (select count(*) from public.so s where s.id = :'so1'::uuid) = 1, :'d1');

\echo '── C) so_lines_clear — S3(A×1 · B×1) → Confirm → Reopen → 미리 보기 → 전부 지우기'
select pg_temp.mk_pos(:'sw', :'cust'::uuid, :'pa'::uuid, 1, :'pb'::uuid, 1, :'wh'::uuid, :'r13'::uuid, :'r13_name', 'pr1 S3')::text as so3 \gset
select pg_temp.as_user(:'sw', format('select public.so_pos_reopen(%L)::text', :'so3')) as ro3 \gset
select pg_temp.as_user(:'sw', format('select public.so_lines_clear(%L, false)::text', :'so3')) as cl0 \gset
select pg_temp.as_user(:'sw', format('select public.so_lines_clear(%L, true)::text', :'so3')) as cl1 \gset
select pg_temp.chk('C1 S3 reopened (0|2) → clear preview committed false · lines 2 → commit: lines 2 · reserve_history_removed 2 · so_line 0 · reserve rows 0 · availability 0|50 both',
  pg_temp.j(:'ro3')->>'status' = 'draft' and (pg_temp.j(:'cl0')->>'committed')::boolean = false and (pg_temp.j(:'cl0')->>'lines')::int = 2
  and (pg_temp.j(:'cl1')->>'committed')::boolean = true and (pg_temp.j(:'cl1')->>'lines')::int = 2 and (pg_temp.j(:'cl1')->>'reserve_history_removed')::int = 2
  and (select count(*) from public.so_line l where l.so_id = :'so3'::uuid) = 0 and pg_temp.res(:'so3'::uuid) = '0|0'
  and pg_temp.av(:'wh'::uuid, :'pa'::uuid) = '0|50' and pg_temp.av(:'wh'::uuid, :'pb'::uuid) = '0|50',
  format('preview %s | commit %s | res %s', left(:'cl0', 200), left(:'cl1', 300), pg_temp.res(:'so3'::uuid)));
select s.so_number as so3_num from public.so s where s.id = :'so3'::uuid \gset
select pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so3')) as d3 \gset
select pg_temp.chk('C3 (이견 5) S3 — no payment · lines cleared · history went with them → so_delete of a sale that WAS confirmed now succeeds (the history gate has nothing left to see) — Caleb decides whether that is wanted',
  pg_temp.j(:'d3')->>'deleted' = :'so3_num' and (select count(*) from public.so s where s.id = :'so3'::uuid) = 0, :'d3');
select pg_temp.chk('C2 preview (p_commit false) on a draft with released history does not delete anything (reserve rows still 0|2 before commit was checked above via lines 2) · clear on a confirmed order still refused',
  pg_temp.as_user(:'sw', format('select public.so_lines_clear(%L, true)::text', pg_temp.mk_pos(:'sw', :'cust'::uuid, :'pa'::uuid, 1, null, null, :'wh'::uuid, :'r13'::uuid, :'r13_name', 'pr1 S3b')::text)) like 'ERR P0001: Order SO-% is not a draft (status confirmed) — unconfirm it first%',
  'see C2');

\echo '── D) Delete draft — 이력 있는 Reopen 초안은 여전히 읽을 수 있는 글로 거부(so_delete 무접촉) · 확정된 적 없는 초안은 지워진다'
select pg_temp.mk_pos(:'sw', :'cust'::uuid, :'pa'::uuid, 1, :'pb'::uuid, 2, :'wh'::uuid, :'r13'::uuid, :'r13_name', 'pr1 S2')::text as so2 \gset
select pg_temp.as_user(:'sw', format('select public.so_pos_reopen(%L)::text', :'so2')) as ro2b \gset
select pg_temp.chk('D1 S2 reopened → so_delete refused: allocation history → so_cancel (not the FK error) · S2 still there (0|2)',
  pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so2')) = format('ERR P0001: Order %s has allocation history (it was confirmed before) — cancel it instead (so_cancel) — nothing was deleted', (select s.so_number from public.so s where s.id = :'so2'::uuid))
  and pg_temp.res(:'so2'::uuid) = '0|2', pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so2')));
select pg_temp.as_user(:'sw', format('select (public.so_create(%L::uuid, ''pos'', ''pos'', %L::uuid, ''pr1 S0''))->>''id''', :'cust', :'wh')) as so0 \gset
select pg_temp.as_user(:'sw', format('select (public.so_line_add(%L::uuid, %L::uuid, 1, 10.00, null, null, null, false))->>''line_no''', :'so0', :'pa')) as s0l \gset
select s.so_number as s0n from public.so s where s.id = :'so0'::uuid \gset
select pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so0')) as d0 \gset
select pg_temp.chk('D2 never-confirmed POS draft S0 (one line) → so_delete OK (unchanged path)',
  pg_temp.j(:'d0')->>'deleted' = :'s0n' and (select count(*) from public.so s where s.id = :'so0'::uuid) = 0, format('line_add %s | delete %s', :'s0l', :'d0'));
select pg_temp.chk('D3 remove a line that still has an OPEN allocation (S2 confirmed again) → refused by the gate, not by the FK · open row intact',
  (pg_temp.j(pg_temp.as_user(:'sw', format('select public.so_pos_confirm(%L)::text', :'so2')))->>'status') = 'confirmed'
  and pg_temp.as_user(:'sw', format('select public.so_line_remove(%L)::text', pg_temp.line_of(:'so2'::uuid, :'pa'::uuid)::text)) like 'ERR P0001: Order SO-% is not a draft (status confirmed) — nothing was deleted'
  and pg_temp.res(:'so2'::uuid) = '2|2', format('res %s', pg_temp.res(:'so2'::uuid)));
set local session_replication_role = replica;
update public.so set status = 'draft' where id = :'so2'::uuid;                                                      -- 중간 상태 재현: draft 인데 열린 예약이 남은 꼴(창구로는 못 만든다)
set local session_replication_role = origin;
select pg_temp.chk('D4 (middle state · replica) draft with an open allocation → so_line_remove refused ''has an open allocation'' · so_lines_clear refused ''has an open allocation'' · nothing deleted (gate order unchanged)',
  pg_temp.as_user(:'sw', format('select public.so_line_remove(%L)::text', pg_temp.line_of(:'so2'::uuid, :'pa'::uuid)::text)) like 'ERR P0001: Line 1 of SO-% has an open allocation — release it first — nothing was deleted'
  and pg_temp.as_user(:'sw', format('select public.so_lines_clear(%L, true)::text', :'so2')) like 'ERR P0001: Order SO-% has an open allocation — release it first — nothing was deleted'
  and pg_temp.res(:'so2'::uuid) = '2|2' and (select count(*) from public.so_line l where l.so_id = :'so2'::uuid) = 2,
  format('%s | res %s', pg_temp.as_user(:'sw', format('select public.so_line_remove(%L)::text', pg_temp.line_of(:'so2'::uuid, :'pa'::uuid)::text)), pg_temp.res(:'so2'::uuid)));

\echo '── W) warehouse 길 — so_confirm → so_unconfirm(supervisor) → 줄 ✕ (같은 벽 · 같은 고침)'
select pg_temp.as_user(:'sw', format('select (public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''pr1 S4''))->>''id''', :'cust', :'wh')) as so4 \gset
select pg_temp.as_user(:'sw', format('select (public.so_line_add(%L::uuid, %L::uuid, 1, 10.00, null, null, null, false))->>''so_number''', :'so4', :'pa')) as s4n \gset
set local session_replication_role = replica;
update public.so set tax_rule_id = :'r13'::uuid, tax_rule = :'r13_name', tax_rule_manual = true where id = :'so4'::uuid;
set local session_replication_role = origin;
-- so_confirm 은 manager 이상(회차 1 에서 잡음 · supervisor 로는 거부) · so_unconfirm 은 supervisor 이상
select pg_temp.as_user(:'sm', format('select public.so_confirm(%L, ''{}''::uuid[], false, true)::text', :'so4')) as wc \gset
select s.status as s4_confirmed, pg_temp.res(:'so4'::uuid) as s4_res_c from public.so s where s.id = :'so4'::uuid \gset
select pg_temp.as_user(:'sv', format('select public.so_unconfirm(%L)::text', :'so4')) as wu \gset
select pg_temp.as_user(:'sw', format('select public.so_line_remove(%L)::text', pg_temp.line_of(:'so4'::uuid, :'pa'::uuid)::text)) as wr \gset
select pg_temp.chk('W1 warehouse S4 confirmed by manager (1|0 allocated) → unconfirmed by supervisor (0|1 · unconfirmed_at set) → line removed by sales worker OK · reserve_history_removed 1 · rows 0',
  :'s4_confirmed' = 'confirmed' and :'s4_res_c' = '1|0'
  and (select s.status from public.so s where s.id = :'so4'::uuid) = 'draft' and pg_temp.j(:'wu')->>'status' = 'draft' and (pg_temp.j(:'wu')->>'reserves_released')::int = 1
  and (select s.unconfirmed_at is not null from public.so s where s.id = :'so4'::uuid)
  and (pg_temp.j(:'wr')->>'reserve_history_removed')::int = 1 and pg_temp.res(:'so4'::uuid) = '0|0',
  format('confirm %s | unconfirm %s | remove %s', left(:'wc', 150), left(:'wu', 200), left(:'wr', 200)));

\echo '── P) 권한 · 착지'
select pg_temp.chk('P1 no sales key → so_line_remove · so_lines_clear refused at the first gate (unchanged)',
  pg_temp.as_user(:'w0', format('select public.so_line_remove(%L)::text', pg_temp.line_of(:'so2'::uuid, :'pa'::uuid)::text)) = 'ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was deleted'
  and pg_temp.as_user(:'w0', format('select public.so_lines_clear(%L, true)::text', :'so2')) = 'ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was deleted',
  pg_temp.as_user(:'w0', format('select public.so_line_remove(%L)::text', pg_temp.line_of(:'so2'::uuid, :'pa'::uuid)::text)));
select pg_temp.chk('P2 acl unchanged for both (string equal to before) · definer · volatile',
  (select array_to_string(proacl, ',') from pg_proc where oid = to_regprocedure('public.so_line_remove(uuid)')) = :'acl_remove0'
  and (select array_to_string(proacl, ',') from pg_proc where oid = to_regprocedure('public.so_lines_clear(uuid, boolean)')) = :'acl_clear0'
  and (select bool_and(prosecdef and provolatile = 'v') from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_line_remove', 'so_lines_clear')), :'acl_remove0');
select pg_temp.chk('P3 FK so_reserve_so_line_id_fkey unchanged (no action) · so_reserve triggers 5 · no shop_stock_queue rows for the fake products (no listing)',
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'so_reserve_so_line_id_fkey' and conrelid = 'public.so_reserve'::regclass) = :'fk0'
  and (select count(*) from pg_trigger where tgrelid = 'public.so_reserve'::regclass and not tgisinternal) = 5
  and (select count(*) from public.shop_stock_queue q where q.product_id in (:'pa'::uuid, :'pb'::uuid)) = :q0,
  format('fk %s | queue rows %s', (select pg_get_constraintdef(oid) from pg_constraint where conname = 'so_reserve_so_line_id_fkey'), (select count(*) from public.shop_stock_queue q where q.product_id in (:'pa'::uuid, :'pb'::uuid))));
select pg_temp.chk('P4 column comment on so_reserve.so_line_id carries the pos-reopen-1 ruling', col_description('public.so_reserve'::regclass, (select attnum from pg_attribute where attrelid = 'public.so_reserve'::regclass and attname = 'so_line_id')) like '%pos-reopen-1%', 'comment');

\echo '── Z) 무접촉'
select pg_temp.chk('Z0 untouched prosrc md5: so_pos_reopen · so_delete · so_pos_confirm · so_allocate_all · so_unconfirm · so_line_update · so_cancel',
  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_reopen') = :'md5_reopen0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') = :'md5_delete0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_confirm') = :'md5_posconfirm0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_allocate_all') = :'md5_allocall0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') = :'md5_unconfirm0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_update') = :'md5_lineupdate0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_cancel') = :'md5_cancel0'
  and :'md5_reopen0' = 'a4cbbc54bab27e288795bb997f62aef5' and :'md5_delete0' = 'a98f03969aba10e19fa0972897a87505', :'md5_reopen0');
select pg_temp.chk('Z0b the two reissued functions differ from the 2026-10-28 originals (17cc8717… · a7be7e79…) · exactly one of each',
  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_remove') <> '17cc8717cffcbb04c9f69e69d95ec573'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_clear') <> 'a7be7e796330210bb738d378937c95af'
  and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_line_remove', 'so_lines_clear')) = 2, 'see Z0b');
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_here \gset
\echo '── begin ~ here:' :begin_to_here
rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 실제 행 무변 · 시퀀스 되돌리기'
select pg_temp.chk('Z1 real rows unchanged after rollback (so · so_line · so_reserve · so_payment · staff · customer · product · inv_ledger) · fake traces 0',
  (select count(*) from public.so) = :w_so and (select count(*) from public.so_line) = :w_line and (select count(*) from public.so_reserve) = :w_res and (select count(*) from public.so_payment) = :w_pay
  and (select count(*) from public.ims_staff) = :w_staff and (select count(*) from public.customer) = :w_cust and (select count(*) from public.product) = :w_prod and (select count(*) from public.inv_ledger) = :w_ledger
  and (select count(*) from public.customer where name = 'PR1 Customer') + (select count(*) from public.product where sku like 'PR1-%') + (select count(*) from public.ims_staff where email like 'pr1-%') + (select count(*) from public.inv_ledger where sku like 'PR1-%') = 0,
  format('so %s/%s line %s/%s res %s/%s staff %s/%s', (select count(*) from public.so), :w_so, (select count(*) from public.so_line), :w_line, (select count(*) from public.so_reserve), :w_res, (select count(*) from public.ims_staff), :w_staff));
\if :{?mig}
select pg_temp.chk('Z2 (trial only) rollback restored the two originals (md5 back to 17cc8717… · a7be7e79…)',
  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_remove') = :'md5_remove0' and :'md5_remove0' = '17cc8717cffcbb04c9f69e69d95ec573'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_clear') = :'md5_clear0' and :'md5_clear0' = 'a7be7e796330210bb738d378937c95af', :'md5_remove0');
\else
select pg_temp.chk('Z2 (confirm) the reissued pair is in the DB (md5 ≠ originals) · schema_migrations has 20261029014000',
  :'md5_remove0' <> '17cc8717cffcbb04c9f69e69d95ec573' and :'md5_clear0' <> 'a7be7e796330210bb738d378937c95af' and :n_applied = 1, format('remove %s clear %s applied %s', :'md5_remove0', :'md5_clear0', :n_applied));
\endif
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
select (select last_value || '|' || is_called from public.so_number_seq) as so_seq_after, (select last_value || '|' || is_called from public.so_invoice_number_seq) as inv_seq_after;
