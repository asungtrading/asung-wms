-- supabase/tests/so_del_1.sql — so-del-1 so.first_confirmed_at · 트리거 so_first_confirmed · so_delete 재발행 검증 (2026-10-28 · 판정 865 · pos-reopen-1 이견 5 · 6)
-- [테스트 · Asung-IMS] 시험 적용 장치 — begin → (-v mig 면 \i) → 가짜 재료 → 갈래 → rollback → 가짜 흔적 0 · 시퀀스 되돌림 · 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029020000_so_del_1.sql -f supabase/tests/so_del_1.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK = 시험 OK − 시험 전용(G0 · B0 · Z2 시험 갈래) + Z2 확인 갈래 — 머리의 EXPECT 줄 참조
--   ⚠️ 무거운 기준값(실제 so 의 updated_at 지문 · 흔적 수)은 begin 앞에서 받는다(잠금 규칙 ①) · 마이그레이션은 alter table so add column(ACCESS EXCLUSIVE · 짧다) + 트리거 + 채우기 update(177 행) — 회차마다 begin ~ rollback 시간을 찍는다
--   재료(전부 가짜 · SD1): 직원 넷(SW worker sales · SM manager sales · SV supervisor sales · W0 열쇠 없음) · 손님 SD1 Customer · 제품 SD1-A · SD1-B 장부 50 씩 · POS 판매 S1 · S2 · S5 · 초안 S0 · warehouse S3 · S4(선결제)
--   ⚠️ so_create 가 so_number_seq 를 당긴다 → 끝에 greatest(실제 최대, 머리) 로 되돌린다 · 인보이스 번호는 당기지 않는다(Finish 없음)
--   EXPECT: 시험(-v mig) OK 31 · 확인(-v mig 없음) OK 29(G0 · B0 빠짐 · Z2 는 확인 갈래 줄) — 회차 2 통과 출력에서 받아 적음 · OK 줄 꼴 = 앞 빈칸 하나 + "OK " (psql 열 출력 · grep -cE "^ OK ")
\set ON_ERROR_STOP on
\pset pager off
\echo '── db_role · schema_migrations · 칸 · so_delete md5 · 무접촉 여덟 md5 · 시퀀스 머리 · 실제 행 수 · so updated_at 지문 · 흔적 수'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261029020000' \gset
select count(*) as col_before from information_schema.columns where table_schema = 'public' and table_name = 'so' and column_name = 'first_confirmed_at' \gset
select count(*) as so_cols0 from information_schema.columns where table_schema = 'public' and table_name = 'so' \gset
select (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') as md5_delete0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_cancel') as md5_cancel0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_reopen') as md5_reopen0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') as md5_unconfirm0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_confirm') as md5_confirm0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_confirm') as md5_posconfirm0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_service_confirm') as md5_svcconfirm0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_remove') as md5_remove0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_clear') as md5_clear0,
       (select array_to_string(proacl, ',') from pg_proc where oid = to_regprocedure('public.so_delete(uuid)')) as acl_delete0 \gset
select :n_applied as schema_migrations_rows_for_20261029020000, :col_before as col_before, :'md5_delete0' as md5_delete0;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select :so_seq_last as so_seq_head, :'so_seq_called' as so_called, (select max(substring(so_number from '[0-9]+')::bigint) from public.so) as so_max_head, :inv_seq_last as inv_seq_head, :'inv_seq_called' as inv_called;
select (select count(*) from public.so) as w_so, (select count(*) from public.so_line) as w_line, (select count(*) from public.so_reserve) as w_res, (select count(*) from public.so_payment) as w_pay, (select count(*) from public.so_payment_order) as w_po,
       (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.customer) as w_cust, (select count(*) from public.product) as w_prod, (select count(*) from public.inv_ledger) as w_ledger \gset
-- 잠금 규칙 ①: 무거운 기준값은 begin 앞 — 실제 so 177 행의 (id · updated_at · updated_by) 지문(채우기가 so_touch 를 지나지 않았는지) · 확정 흔적이 있는 행 수
select sum(('x' || left(md5(s.id::text || '|' || s.updated_at::text || '|' || coalesce(s.updated_by::text, '-')), 15))::bit(60)::bigint) as fp_touch0 from public.so s \gset
select count(*) as n_trace0 from public.so s where s.confirmed_at is not null or s.unconfirmed_at is not null or exists (select 1 from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = s.id) \gset
select count(*) as n_nondraft0 from public.so s where s.status not in ('draft', 'cancelled') \gset
\echo '── 기준: so' :w_so '· 흔적 있는 행' :n_trace0 '· 초안·취소 아님' :n_nondraft0 '· touch 지문' :fp_touch0
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
select pg_temp.chk('G0 시험에서만: 적용 전 schema_migrations 0 행 · 칸 없음 → 적용 뒤 칸 · 트리거 있음 · so_delete md5 바뀜 · so 칸 수 +1',
  :n_applied = 0 and :col_before = 0
  and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so' and column_name = 'first_confirmed_at')
  and exists (select 1 from pg_trigger where tgrelid = 'public.so'::regclass and tgname = 'so_first_confirmed')
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') <> :'md5_delete0'
  and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so') = :so_cols0 + 1, format('applied %s col_before %s', :n_applied, :col_before));
select pg_temp.chk(format('B0 시험에서만: 채우기 = 흔적 있는 행 수 그대로(%s) · 흔적 없는 행은 null', :n_trace0),
  (select count(*) from public.so where first_confirmed_at is not null) = :n_trace0
  and (select count(*) from public.so s where s.first_confirmed_at is not null and not (s.confirmed_at is not null or s.unconfirmed_at is not null or exists (select 1 from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = s.id))) = 0,
  format('marked %s expected %s', (select count(*) from public.so where first_confirmed_at is not null), :n_trace0));
\endif

\echo '── B) 채우기 정합(시험 · 확인 공통) — 흔적 있는 행은 전부 표시 · 표시 ≤ confirmed_at · 초안·취소 아님은 전부 표시 · updated_at 지문 무변 · SO-25082 null'
select pg_temp.chk('B1 every order with a confirm trace has first_confirmed_at · first_confirmed_at ≤ confirmed_at · every non-draft non-cancelled order has it · backfill did not touch updated_at/updated_by (fingerprint equal)',
  (select count(*) from public.so s where s.first_confirmed_at is null and (s.confirmed_at is not null or s.unconfirmed_at is not null or exists (select 1 from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = s.id))) = 0
  and (select count(*) from public.so s where s.first_confirmed_at is not null and s.confirmed_at is not null and s.first_confirmed_at > s.confirmed_at) = 0
  and (select count(*) from public.so s where s.status not in ('draft', 'cancelled') and s.first_confirmed_at is null) = 0
  and (select sum(('x' || left(md5(s.id::text || '|' || s.updated_at::text || '|' || coalesce(s.updated_by::text, '-')), 15))::bit(60)::bigint) from public.so s) = :fp_touch0
  and (select first_confirmed_at is null from public.so where so_number = 'SO-25082') is not false,
  format('untraced-marked %s · marker>confirmed %s · nondraft-null %s', (select count(*) from public.so s where s.first_confirmed_at is null and s.confirmed_at is not null), (select count(*) from public.so s where s.first_confirmed_at > s.confirmed_at), (select count(*) from public.so s where s.status not in ('draft', 'cancelled') and s.first_confirmed_at is null)));
select pg_temp.chk('B2 real example SO-25237 (POS · reopened twice · 8 history rows): first_confirmed_at = earliest allocated_at (2026-10-29 00:53:35 UTC) · confirmed_at null',
  (select s.first_confirmed_at = (select min(r.allocated_at) from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = s.id) and s.confirmed_at is null from public.so s where s.so_number = 'SO-25237') is not false,
  (select s.first_confirmed_at::text from public.so s where s.so_number = 'SO-25237'));

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
create function pg_temp.mk(p_claims text, p_cust uuid, p_channel text, p_intake text, p_pid_a uuid, p_qa numeric, p_pid_b uuid, p_qb numeric, p_wh uuid, p_rule uuid, p_rule_name text, p_note text) returns uuid language plpgsql as $$
declare v_x jsonb; v_so uuid;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  v_x := public.so_create(p_cust, p_channel, p_intake, p_wh, p_note);  v_so := (v_x->>'id')::uuid;
  v_x := public.so_line_add(v_so, p_pid_a, p_qa, 10.00, null, null, null, false);
  if p_pid_b is not null then v_x := public.so_line_add(v_so, p_pid_b, p_qb, 20.00, null, null, null, false); end if;
  execute 'set local session_replication_role = replica';
  update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
  execute 'set local session_replication_role = origin';
  return v_so;
end $$;
-- 오더 지문: status|first_confirmed_at 있음|confirmed_at 있음|unconfirmed_at 있음|줄 수|예약 행 수
create function pg_temp.st(p_so uuid) returns text language sql security definer as $$
  select s.status || '|' || (s.first_confirmed_at is not null)::text || '|' || (s.confirmed_at is not null)::text || '|' || (s.unconfirmed_at is not null)::text || '|'
         || (select count(*) from public.so_line l where l.so_id = s.id) || '|' || (select count(*) from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = s.id)
  from public.so s where s.id = p_so $$;
create function pg_temp.line_of(p_so uuid, p_pid uuid) returns uuid language sql security definer as $$
  select l.id from public.so_line l where l.so_id = p_so and l.product_id = p_pid order by l.line_no limit 1 $$;

\echo '── M) 재료'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'sd1-sw@test.invalid', 'SD1 SW', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as sw_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'sd1-sm@test.invalid', 'SD1 SM', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as sm_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'sd1-w0@test.invalid', 'SD1 W0', 'worker', '[]', '{}') returning auth_user_id::text as w0_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'sd1-sv@test.invalid', 'SD1 SV', 'supervisor', '["ims","sales"]', '{}') returning auth_user_id::text as sv_uid \gset
\set sw '{"sub":"' :sw_uid '","role":"authenticated"}'
\set sm '{"sub":"' :sm_uid '","role":"authenticated"}'
\set w0 '{"sub":"' :w0_uid '","role":"authenticated"}'
\set sv '{"sub":"' :sv_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.name as bina from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as r13, name as r13_name from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('SD1 Customer', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as cust \gset
insert into public.product (sku, name, source) values ('SD1-A', 'SD1 Product A', 'manual') returning id::text as pa \gset
insert into public.product (sku, name, source) values ('SD1-B', 'SD1 Product B', 'manual') returning id::text as pb \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
  values (public.ims_today() - 3, 1, 'SD1-A', :'whname', :'bina', 50, 'po_in', 'purchase', 'PO-SD1', 'sd1-1', 'manual'),
         (public.ims_today() - 3, 2, 'SD1-B', :'whname', :'bina', 50, 'po_in', 'purchase', 'PO-SD1', 'sd1-2', 'manual');
set local session_replication_role = origin;
select pg_temp.chk(format('M0 staff ×4 · customer (branch %s) · SD1-A · SD1-B stock 50 · tax %s', :'whname', :'r13_name'),
  :'sw_uid' <> '' and :'sm_uid' <> '' and :'sv_uid' <> '' and :'w0_uid' <> '' and :'cust' <> '' and :'pa' <> '' and :'pb' <> '' and :'r13' <> '', 'see M0');

\echo '── S1) C3 재현 — POS Confirm → Reopen → 다시 Confirm → Reopen → 줄 전부 ✕ → Delete draft 거부(판정 865)'
select pg_temp.mk(:'sw', :'cust'::uuid, 'pos', 'pos', :'pa'::uuid, 1, :'pb'::uuid, 1, :'wh'::uuid, :'r13'::uuid, :'r13_name', 'sd1 S1')::text as so1 \gset
select s.so_number as so1_num from public.so s where s.id = :'so1'::uuid \gset
select pg_temp.chk('S1a draft before confirm: first_confirmed_at null (draft|f|f|f|2|0)', pg_temp.st(:'so1'::uuid) = 'draft|false|false|false|2|0', pg_temp.st(:'so1'::uuid));
select pg_temp.as_user(:'sw', format('select public.so_pos_confirm(%L)::text', :'so1')) as c1 \gset
select s.first_confirmed_at::text as fc1, s.confirmed_at::text as ca1 from public.so s where s.id = :'so1'::uuid \gset
select pg_temp.chk('S1b so_pos_confirm → confirmed · first_confirmed_at stamped by the trigger = confirmed_at (confirmed|t|t|f|2|2)',
  pg_temp.j(:'c1')->>'status' = 'confirmed' and pg_temp.st(:'so1'::uuid) = 'confirmed|true|true|false|2|2' and :'fc1' = :'ca1', format('%s | fc %s ca %s', pg_temp.st(:'so1'::uuid), :'fc1', :'ca1'));
select pg_temp.as_user(:'sw', format('select public.so_pos_reopen(%L)::text', :'so1')) as r1 \gset
select pg_temp.chk('S1c Reopen → draft · confirmed_at cleared · first_confirmed_at stays (draft|t|f|f|2|2 · same value)',
  pg_temp.j(:'r1')->>'status' = 'draft' and pg_temp.st(:'so1'::uuid) = 'draft|true|false|false|2|2' and (select s.first_confirmed_at::text from public.so s where s.id = :'so1'::uuid) = :'fc1', pg_temp.st(:'so1'::uuid));
select pg_temp.chk('S1d Delete draft right after Reopen → refused with the 865 text (first gate · before the history gate)',
  pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so1')) = format('ERR P0001: Order %s was confirmed before — it cannot be deleted. Ask a manager to cancel it (so_cancel), which keeps a record — nothing was deleted', :'so1_num'),
  pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so1')));
select pg_temp.as_user(:'sw', format('select public.so_pos_confirm(%L)::text', :'so1')) as c2 \gset
select pg_temp.chk('S1e Confirm again → confirmed · first_confirmed_at unchanged (= first value · confirmed_at set again — in one transaction now() is the same instant, so equal here)',
  pg_temp.j(:'c2')->>'status' = 'confirmed' and (select s.first_confirmed_at::text = :'fc1' and s.confirmed_at is not null and s.confirmed_at >= s.first_confirmed_at from public.so s where s.id = :'so1'::uuid),
  (select s.first_confirmed_at::text || ' / ' || s.confirmed_at::text from public.so s where s.id = :'so1'::uuid));
select pg_temp.as_user(:'sw', format('select public.so_pos_reopen(%L)::text', :'so1')) as r2 \gset
select pg_temp.as_user(:'sw', format('select public.so_line_remove(%L)::text', pg_temp.line_of(:'so1'::uuid, :'pa'::uuid)::text)) as x1 \gset
select pg_temp.as_user(:'sw', format('select public.so_line_remove(%L)::text', pg_temp.line_of(:'so1'::uuid, :'pb'::uuid)::text)) as x2 \gset
select pg_temp.chk('S1f Reopen → both lines removed (history rows went with them · pos-reopen-1) → draft|t|f|f|0|0',
  pg_temp.j(:'r2')->>'status' = 'draft' and (pg_temp.j(:'x1')->>'reserve_history_removed')::int = 2 and (pg_temp.j(:'x2')->>'reserve_history_removed')::int = 2 and pg_temp.st(:'so1'::uuid) = 'draft|true|false|false|0|0',
  format('%s | %s | %s', left(:'x1', 160), left(:'x2', 160), pg_temp.st(:'so1'::uuid)));
select pg_temp.chk('S1g C3 shape: Delete draft with no lines and no history → still refused (865) · order stays',
  pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so1')) = format('ERR P0001: Order %s was confirmed before — it cannot be deleted. Ask a manager to cancel it (so_cancel), which keeps a record — nothing was deleted', :'so1_num')
  and (select count(*) from public.so s where s.id = :'so1'::uuid) = 1, pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so1')));
select pg_temp.chk('S1h manager so_cancel of that reopened draft → cancelled (the path 865 prescribes) · first_confirmed_at still there',
  (pg_temp.j(pg_temp.as_user(:'sm', format('select public.so_cancel(%L, ''sd1 cancel'')::text', :'so1')))->>'cancelled')::int = 1 and pg_temp.st(:'so1'::uuid) = 'cancelled|true|false|false|0|0', pg_temp.st(:'so1'::uuid));

\echo '── S5) so_lines_clear 길 — Confirm → Reopen → Clear lines → Delete draft 거부'
select pg_temp.mk(:'sw', :'cust'::uuid, 'pos', 'pos', :'pa'::uuid, 1, :'pb'::uuid, 1, :'wh'::uuid, :'r13'::uuid, :'r13_name', 'sd1 S5')::text as so5 \gset
select pg_temp.as_user(:'sw', format('select public.so_pos_confirm(%L)::text', :'so5')) as c5 \gset
select pg_temp.as_user(:'sw', format('select public.so_pos_reopen(%L)::text', :'so5')) as r5 \gset
select pg_temp.as_user(:'sw', format('select public.so_lines_clear(%L, true)::text', :'so5')) as cl5 \gset
select pg_temp.chk('S5 clear lines after Reopen (history removed 2 · lines 0) → Delete draft refused (865)',
  (pg_temp.j(:'cl5')->>'reserve_history_removed')::int = 2 and pg_temp.st(:'so5'::uuid) = 'draft|true|false|false|0|0'
  and pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so5')) like 'ERR P0001: Order SO-% was confirmed before — it cannot be deleted. Ask a manager to cancel it (so_cancel), which keeps a record — nothing was deleted',
  format('%s | %s', left(:'cl5', 200), pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so5'))));

\echo '── S0 · S2) 한 번도 확정 안 된 초안 → Delete draft OK(그대로) · 결제 없는 POS 초안 둘'
select pg_temp.mk(:'sw', :'cust'::uuid, 'pos', 'pos', :'pa'::uuid, 1, null, null, :'wh'::uuid, :'r13'::uuid, :'r13_name', 'sd1 S0')::text as so0 \gset
select s.so_number as so0_num from public.so s where s.id = :'so0'::uuid \gset
select pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so0')) as d0 \gset
select pg_temp.chk('S0 never-confirmed POS draft (first_confirmed_at null) → so_delete OK · gone', pg_temp.j(:'d0')->>'deleted' = :'so0_num' and (select count(*) from public.so s where s.id = :'so0'::uuid) = 0, :'d0');
select pg_temp.chk('S2 so_delete by someone without the sales key → first gate unchanged',
  pg_temp.as_user(:'w0', format('select public.so_delete(%L)::text', :'so5')) = 'ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was deleted',
  pg_temp.as_user(:'w0', format('select public.so_delete(%L)::text', :'so5')));

\echo '── S3) warehouse 길 — so_confirm(manager) → so_unconfirm → 줄 ✕ → Delete draft 거부'
select pg_temp.mk(:'sw', :'cust'::uuid, 'warehouse', 'manual', :'pa'::uuid, 1, null, null, :'wh'::uuid, :'r13'::uuid, :'r13_name', 'sd1 S3')::text as so3 \gset
select pg_temp.as_user(:'sm', format('select public.so_confirm(%L, ''{}''::uuid[], false, true)::text', :'so3')) as wc \gset
select s.first_confirmed_at::text as fc3 from public.so s where s.id = :'so3'::uuid \gset
-- so_unconfirm 은 supervisor 이상 · manager 는 그 아래(회차 1 「This needs a supervisor or above (you are manager)」) · so_confirm 은 manager 이상 — 둘을 다른 사람이 누른다
select pg_temp.as_user(:'sv', format('select public.so_unconfirm(%L)::text', :'so3')) as wu \gset
select pg_temp.as_user(:'sw', format('select public.so_line_remove(%L)::text', pg_temp.line_of(:'so3'::uuid, :'pa'::uuid)::text)) as wr \gset
select pg_temp.chk('S3a warehouse: confirmed (stamp) → unconfirmed (confirmed_at cleared · unconfirmed_at set · stamp stays) → line removed → draft|t|f|t|0|0',
  (pg_temp.j(:'wc')->>'committed')::boolean and :'fc3' <> '' and pg_temp.j(:'wu')->>'status' = 'draft' and (pg_temp.j(:'wr')->>'reserve_history_removed')::int = 1
  and pg_temp.st(:'so3'::uuid) = 'draft|true|false|true|0|0' and (select s.first_confirmed_at::text from public.so s where s.id = :'so3'::uuid) = :'fc3',
  format('confirm %s | unconfirm %s | remove %s | %s', left(:'wc', 120), left(:'wu', 160), left(:'wr', 160), pg_temp.st(:'so3'::uuid)));
select pg_temp.chk('S3b Delete draft of the unconfirmed warehouse order → refused (865)',
  pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so3')) like 'ERR P0001: Order SO-% was confirmed before — it cannot be deleted. Ask a manager to cancel it (so_cancel), which keeps a record — nothing was deleted',
  pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so3')));

\echo '── S4) 결제가 붙은 「한 번도 확정 안 된」 초안(warehouse 선결제 · so_payment_add target_so_ids 는 초안 상태를 묻지 않는다) → 읽을 수 있는 거부 → so_cancel OK'
select pg_temp.mk(:'sw', :'cust'::uuid, 'warehouse', 'manual', :'pa'::uuid, 1, null, null, :'wh'::uuid, :'r13'::uuid, :'r13_name', 'sd1 S4')::text as so4 \gset
select s.so_number as so4_num from public.so s where s.id = :'so4'::uuid \gset
select pg_temp.as_user(:'sw', format('select (public.so_payment_add(%L::jsonb))->>''payment_id''', jsonb_build_object('customer_id', :'cust', 'amount', 7, 'paid_on', public.ims_today(), 'method', 'cash', 'reference', 'sd1 prepay',
                                                   'currency_id', :'cad', 'warehouse_id', :'wh', 'target_so_ids', jsonb_build_array(:'so4'))::text)) as p4 \gset
select pg_temp.chk('S4a prepayment 7 tied to the never-confirmed draft S4 (so_payment_order 1 · first_confirmed_at null)',
  :'p4' not like 'ERR %' and (select count(*) from public.so_payment_order o where o.so_id = :'so4'::uuid) = 1 and pg_temp.st(:'so4'::uuid) = 'draft|false|false|false|1|0', format('%s | %s', :'p4', pg_temp.st(:'so4'::uuid)));
select pg_temp.chk('S4b Delete draft → refused with the payment text (1 payment · not 23503) · S4 stays',
  pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so4')) = format('ERR P0001: Order %s has 1 payment(s) tied to it — it cannot be deleted. Ask a manager to cancel it (so_cancel); the money stays on the customer''s balance — nothing was deleted', :'so4_num')
  and (select count(*) from public.so s where s.id = :'so4'::uuid) = 1, pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so4')));
select pg_temp.as_user(:'sw', format('select public.so_pos_payment_cancel(%L, null)::text', :'p4')) as pc4 \gset
select pg_temp.chk('S4c payment cancelled at POS? → refused (warehouse order · pos-pay-1 unchanged) · manager so_payment_void → voided · so_payment_order row stays → Delete draft still refused (status-blind)',
  :'pc4' like 'ERR P0001: Sale SO-% is a warehouse order, not a POS sale%'
  and (pg_temp.j(pg_temp.as_user(:'sm', format('select public.so_payment_void(%L, ''sd1 void'')::text', :'p4')))->>'status') = 'voided'
  and (select count(*) from public.so_payment_order o where o.so_id = :'so4'::uuid) = 1
  and pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so4')) like 'ERR P0001: Order SO-% has 1 payment(s) tied to it%',
  format('%s | %s', left(:'pc4', 120), pg_temp.as_user(:'sw', format('select public.so_delete(%L)::text', :'so4'))));
select pg_temp.chk('S4d manager so_cancel of S4 (draft · payment tied) → cancelled · so_payment_order row kept (money back to the balance when all targets end)',
  (pg_temp.j(pg_temp.as_user(:'sm', format('select public.so_cancel(%L, ''sd1 cancel prepay'')::text', :'so4')))->>'cancelled')::int = 1
  and pg_temp.st(:'so4'::uuid) = 'cancelled|false|false|false|1|0' and (select count(*) from public.so_payment_order o where o.so_id = :'so4'::uuid) = 1, pg_temp.st(:'so4'::uuid));

\echo '── T) 표시 지키기 — 비우기 · 바꾸기 거부 · 초안 → 취소(확정 없이)는 안 찍힘 · replica 채우기 꼴은 지나간다'
select pg_temp.chk('T1 clearing first_confirmed_at by a plain update → refused by the trigger · changing it → refused',
  pg_temp.as_user(:'sm', format('update public.so set first_confirmed_at = null where id = %L returning so_number', :'so5')) like 'ERR P0001: Order SO-% was first confirmed at % — that mark cannot be changed or cleared — nothing was saved'
  and pg_temp.as_user(:'sm', format('update public.so set first_confirmed_at = now() + interval ''1 hour'' where id = %L returning so_number', :'so5')) like 'ERR P0001: Order SO-% was first confirmed at % — that mark cannot be changed or cleared — nothing was saved'
  and pg_temp.st(:'so5'::uuid) = 'draft|true|false|false|0|0', pg_temp.as_user(:'sm', format('update public.so set first_confirmed_at = null where id = %L returning so_number', :'so5')));
select pg_temp.mk(:'sw', :'cust'::uuid, 'pos', 'pos', :'pa'::uuid, 1, null, null, :'wh'::uuid, :'r13'::uuid, :'r13_name', 'sd1 S6')::text as so6 \gset
select pg_temp.chk('T2 draft → cancelled without ever confirming (so_cancel on a draft) → first_confirmed_at stays null',
  (pg_temp.j(pg_temp.as_user(:'sm', format('select public.so_cancel(%L, ''sd1 draft cancel'')::text', :'so6')))->>'cancelled')::int = 1 and pg_temp.st(:'so6'::uuid) = 'cancelled|false|false|false|1|0', pg_temp.st(:'so6'::uuid));
select pg_temp.chk('T3 so_detail of S5 carries first_confirmed_at (to_jsonb(so) · the screen can hide Delete draft)',
  (pg_temp.j(pg_temp.as_user(:'sw', format('select public.so_detail(%L)::text', :'so5')))#>>'{so,first_confirmed_at}') is not null, 'see T3');

\echo '── P) 착지'
select pg_temp.chk('P1 so_delete acl unchanged · definer · volatile · so_first_confirmed not executable by anon · so triggers 5',
  (select array_to_string(proacl, ',') from pg_proc where oid = to_regprocedure('public.so_delete(uuid)')) = :'acl_delete0'
  and (select prosecdef and provolatile = 'v' from pg_proc where oid = to_regprocedure('public.so_delete(uuid)'))
  and not has_function_privilege('anon', 'public.so_first_confirmed()', 'execute')
  and (select count(*) from pg_trigger where tgrelid = 'public.so'::regclass and not tgisinternal) = 5, :'acl_delete0');
select pg_temp.chk('P2 session_replication_role is origin · column readable by authenticated · comment carries 865',
  current_setting('session_replication_role') = 'origin' and has_column_privilege('authenticated', 'public.so', 'first_confirmed_at', 'select')
  and col_description('public.so'::regclass, (select attnum from pg_attribute where attrelid = 'public.so'::regclass and attname = 'first_confirmed_at')) like '%865%', current_setting('session_replication_role'));

\echo '── Z) 무접촉'
select pg_temp.chk('Z0 untouched prosrc md5: so_cancel · so_pos_reopen · so_unconfirm · so_confirm · so_pos_confirm · so_service_confirm · so_line_remove · so_lines_clear',
  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_cancel') = :'md5_cancel0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_reopen') = :'md5_reopen0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') = :'md5_unconfirm0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_confirm') = :'md5_confirm0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_confirm') = :'md5_posconfirm0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_service_confirm') = :'md5_svcconfirm0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_remove') = :'md5_remove0'
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_clear') = :'md5_clear0'
  and :'md5_cancel0' = '818b2dd98a8c6159af4701d1de11e1fb' and :'md5_reopen0' = 'a4cbbc54bab27e288795bb997f62aef5' and :'md5_remove0' = 'b69af1efb47676f7d5bc9f27635c3332', :'md5_cancel0');
select pg_temp.chk('Z0b so_delete differs from the 2026-10-28 original (a98f0396…) · exactly one', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') <> 'a98f03969aba10e19fa0972897a87505' and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') = 1, 'see Z0b');
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_here \gset
\echo '── begin ~ here:' :begin_to_here
rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 실제 행 무변 · 시퀀스 되돌리기'
select pg_temp.chk('Z1 real rows unchanged after rollback (so · so_line · so_reserve · so_payment · so_payment_order · staff · customer · product · inv_ledger) · fake traces 0 · touch fingerprint equal',
  (select count(*) from public.so) = :w_so and (select count(*) from public.so_line) = :w_line and (select count(*) from public.so_reserve) = :w_res and (select count(*) from public.so_payment) = :w_pay and (select count(*) from public.so_payment_order) = :w_po
  and (select count(*) from public.ims_staff) = :w_staff and (select count(*) from public.customer) = :w_cust and (select count(*) from public.product) = :w_prod and (select count(*) from public.inv_ledger) = :w_ledger
  and (select count(*) from public.customer where name = 'SD1 Customer') + (select count(*) from public.product where sku like 'SD1-%') + (select count(*) from public.ims_staff where email like 'sd1-%') + (select count(*) from public.inv_ledger where sku like 'SD1-%') = 0
  and (select sum(('x' || left(md5(s.id::text || '|' || s.updated_at::text || '|' || coalesce(s.updated_by::text, '-')), 15))::bit(60)::bigint) from public.so s) = :fp_touch0,
  format('so %s/%s line %s/%s staff %s/%s', (select count(*) from public.so), :w_so, (select count(*) from public.so_line), :w_line, (select count(*) from public.ims_staff), :w_staff));
\if :{?mig}
select pg_temp.chk('Z2 (trial only) rollback restored: column gone · trigger gone · so_delete md5 back to a98f0396…',
  not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so' and column_name = 'first_confirmed_at')
  and not exists (select 1 from pg_trigger where tgrelid = 'public.so'::regclass and tgname = 'so_first_confirmed')
  and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') = 'a98f03969aba10e19fa0972897a87505', 'see Z2');
\else
select pg_temp.chk('Z2 (confirm) column · trigger in the DB · so_delete md5 ≠ original · schema_migrations has 20261029020000',
  :col_before = 1 and exists (select 1 from pg_trigger where tgrelid = 'public.so'::regclass and tgname = 'so_first_confirmed') and :'md5_delete0' <> 'a98f03969aba10e19fa0972897a87505' and :n_applied = 1,
  format('col %s applied %s md5 %s', :col_before, :n_applied, :'md5_delete0'));
\endif
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
select (select last_value || '|' || is_called from public.so_number_seq) as so_seq_after, (select last_value || '|' || is_called from public.so_invoice_number_seq) as inv_seq_after;
