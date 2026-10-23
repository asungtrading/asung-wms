-- bgr-1e-verify.sql — 크레딧 「안 돌아옴」 사유 b_grade 를 새로 못 쓰게(판정 651 A):
--   S0 결함 판(b_grade 미리 보기가 통과) · G0 손대지 않은 함수 무변 · T 옛 = 새(prepare 는 사유 목록만 · 정상 미리 보기 그대로) ·
--   E1 새 줄 b_grade 거부(미리 보기 · 발행 — 번호를 당기기 전) · 콤보 구성품 자리도 · damaged · not_returned · other(메모) 통과 · 표에 직접 insert(service_role) 거부 ·
--   E2 옛 b_grade 줄(실제 크레딧 하나를 replica 로 복사한 가짜 · 되감긴다)의 메모 고치기 · 다른 사유로 바꾸기 통과 · 다른 사유 줄을 b_grade 로 → 거부 · E3 1a ~ 1d 착지 · Z1
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261023144550_bgr_1e_retire_bgrade_reason.sql -f supabase/tests/bgr-1e-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · T 셋은 없고 P0c 한 줄
--   기대(2026-10-23 시험 통과 실행 · 찍힌 OK 줄을 셈): 시험 갈래 OK 8(M0 S0 G0 T E1 E2 E3 Z1) · MISMATCH 0 · begin ~ rollback 약 1.5 초 / 확인 갈래 OK 6(M0 P0c E1 E2 E3 Z1) · MISMATCH 0
--   ⭐ 잠금 규칙: 첫 줄 lock_timeout 3s · 가짜 재료만 · 끝에 begin ~ rollback 초 · alter · lock · truncate · drop 없음 · ⭐ 번호를 당기지 않는다(참조 크레딧 미리 보기 · 거부되는 발행 — 크레딧 번호를 셈해 보인다)

\echo '── db_role · schema_migrations'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261023144550' \gset
select :n_applied as schema_migrations_rows_for_20261023144550;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as tb, now() as t0 \gset

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
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
create function pg_temp.as_role(p_role text, p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  if p_claims is not null then perform set_config('request.jwt.claims', p_claims, true); end if;
  execute p_sql into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then
  reset role;
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.try_undo(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  begin
    execute p_sql into v;
    raise exception using errcode = 'P7777', message = coalesce(v, '(null)');
  exception when sqlstate 'P7777' then return 'PASS: ' || sqlerrm;
  end;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.fns() returns text language sql security definer as $$
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('so_credit_cancel', 'inv_post_credit', 'so_credit_line_state', 'ims_bin_bgrade_refuse', 'inv_ledger_bgrade_guard', 'doc_data_credit') $$;
create function pg_temp.real_rows(p_t0 timestamptz) returns text language plpgsql security definer as $$
begin
  return 'cr=' || (select count(*) || '/' || md5(coalesce(string_agg(c.id::text || c.status, ',' order by c.id), '')) from public.so_credit c where c.created_at < p_t0)
      || ' crl=' || (select count(*) || '/' || md5(coalesce(string_agg(l.id::text || coalesce(l.not_restocked_reason, '-') || coalesce(l.not_restocked_note, '-') || coalesce(l.restock_bin_id::text, '-'), ',' order by l.id), '')) from public.so_credit_line l join public.so_credit c on c.id = l.credit_id where c.created_at < p_t0)
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where created_at < p_t0);
end $$;
-- 참조 크레딧 미리 보기 입력(번호 없음 · 인보이스 없음)
create function pg_temp.ref_p(p_cust uuid, p_rule text, p_line jsonb) returns jsonb language sql as $$
  select jsonb_build_object('customer_id', p_cust, 'reason', 'customer_return', 'tax_rule', p_rule, 'ref', jsonb_build_object('invoice_number', 'INV-BGRE-1', 'order_number', 'SO-BGRE-1', 'invoice_date', public.ims_today() - 10), 'lines', jsonb_build_array(p_line)) $$;

\echo '── M0) 가짜 직원 · 손님(ON) · 제품 · 실제 인보이스 하나(읽기만) · 크레딧 번호 시작'
select pg_temp.real_rows(:'t0'::timestamptz) as real_before, pg_temp.fns() as fns_before,
       (select last_value || '|' || is_called from public.so_credit_number_seq) as cr_seq0 \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'bgre-m@test.invalid', 'BGRE M', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as m_uid \gset
\set m '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as tor from public.ref_warehouse where id = '045e4ca6-b7a9-446e-9e6a-a5a0db56d456' \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
select name as r13_name from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name)
  values ('BGRE Customer ON', 'manual', 'Wholesale', :'tor'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as c_on \gset
insert into public.customer_address (customer_id, type, is_default_for_type, line1, city, state_province, postal_code, country, source, is_active) values (:'c_on'::uuid, 'Shipping', true, '1 Test St', 'Toronto', 'ON', 'M1M 1M1', 'Canada', 'manual', true);
insert into public.product (sku, name, source, is_active, sellable) values ('BGRE-P', 'BGRE Product', 'manual', true, true) returning id::text as pid \gset
set local session_replication_role = origin;
select (select i.id::text from public.so_invoice i where i.status = 'issued' and exists (select 1 from public.so_invoice_line l where l.invoice_id = i.id and l.kind = 'product') order by i.issued_on desc, i.id limit 1) as inv_real \gset
select pg_temp.chk(format('M0 staff M (manager · sales) · customer ON · product BGRE-P · a real issued invoice to read (prepare only) · credit number sequence %s', :'cr_seq0'),
  :'m_uid' <> '' and :'c_on' <> '' and :'pid' <> '' and :'inv_real' ~ '^[0-9a-f-]{36}$' and :'real_before' <> '', :'inv_real');

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — b_grade 미리 보기가 통과한다 · 옛 출력 담기'
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', pg_temp.ref_p(:'c_on'::uuid, :'r13_name', jsonb_build_object('kind', 'product', 'sku', 'BGRE-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'b_grade')))) as s0b,
       pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', pg_temp.ref_p(:'c_on'::uuid, :'r13_name', jsonb_build_object('kind', 'product', 'sku', 'BGRE-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'damaged')))) as o_iss,
       pg_temp.as_user(:'m', format('select public.so_credit_prepare(%L::uuid)::text', :'inv_real')) as o_prep \gset
select pg_temp.chk('S0 before the trial: a b_grade line previews (committed false) · no reason guard trigger · old outputs captured',
  pg_temp.j(:'s0b')->>'committed' = 'false' and not exists (select 1 from pg_trigger where tgname = 'so_credit_line_reason_guard') and :n_applied = 0 and :'o_iss' like '{%' and pg_temp.j(:'o_prep')->'vocab'->'not_restocked_reasons' ? 'b_grade',
  format('%s | %s', left(:'s0b', 300), left(:'o_iss', 200)));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: credit posting · cancel · line state · B-grade guards · credit doc data unchanged', pg_temp.fns() = :'fns_before', format('before %s | after %s', :'fns_before', pg_temp.fns()));
\echo '── T) 옛 = 새 — 사유 목록만 바뀌었다'
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', pg_temp.ref_p(:'c_on'::uuid, :'r13_name', jsonb_build_object('kind', 'product', 'sku', 'BGRE-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'damaged')))) as n_iss,
       pg_temp.as_user(:'m', format('select public.so_credit_prepare(%L::uuid)::text', :'inv_real')) as n_prep \gset
select pg_temp.chk(format('T old = new: damaged preview identical · prepare identical except vocab not_restocked_reasons %s + not_restocked_reasons_retired %s', pg_temp.j(:'n_prep')->'vocab'->'not_restocked_reasons', pg_temp.j(:'n_prep')->'vocab'->'not_restocked_reasons_retired'),
  pg_temp.j(:'n_iss') = pg_temp.j(:'o_iss') and (pg_temp.j(:'n_prep') - 'vocab') = (pg_temp.j(:'o_prep') - 'vocab')
  and ((pg_temp.j(:'n_prep')->'vocab') - 'not_restocked_reasons' - 'not_restocked_reasons_retired') = ((pg_temp.j(:'o_prep')->'vocab') - 'not_restocked_reasons')
  and pg_temp.j(:'n_prep')->'vocab'->'not_restocked_reasons' = '["damaged","not_returned","other"]'::jsonb and pg_temp.j(:'n_prep')->'vocab'->'not_restocked_reasons_retired' = '["b_grade"]'::jsonb,
  format('%s || %s', left(:'n_iss', 200), pg_temp.j(:'n_prep')->'vocab'));
\else
select pg_temp.chk('P0c confirm run: migration 20261023144550 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select exists (select 1 from pg_trigger where tgname = 'so_credit_line_reason_guard') as landed \gset
\if :landed
\echo '── E1) 새 줄 b_grade 거부 · 다른 사유 통과 · 표 직접 insert 거부'
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', pg_temp.ref_p(:'c_on'::uuid, :'r13_name', jsonb_build_object('kind', 'product', 'sku', 'BGRE-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'b_grade')))) as e1a,
       pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, true)::text', pg_temp.ref_p(:'c_on'::uuid, :'r13_name', jsonb_build_object('kind', 'product', 'sku', 'BGRE-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', ' b_grade ')))) as e1b,
       pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', pg_temp.ref_p(:'c_on'::uuid, :'r13_name', jsonb_build_object('kind', 'product', 'sku', 'BGRE-P', 'qty_returned', 1, 'unit_price', 9.99, 'components', jsonb_build_array(jsonb_build_object('sku', 'X', 'not_restocked_reason', 'b_grade')))))) as e1c,
       pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)->>''committed''', pg_temp.ref_p(:'c_on'::uuid, :'r13_name', jsonb_build_object('kind', 'product', 'sku', 'BGRE-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'damaged')))) as e1d,
       pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)->>''committed''', pg_temp.ref_p(:'c_on'::uuid, :'r13_name', jsonb_build_object('kind', 'product', 'sku', 'BGRE-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'not_returned')))) as e1e,
       pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)->>''committed''', pg_temp.ref_p(:'c_on'::uuid, :'r13_name', jsonb_build_object('kind', 'product', 'sku', 'BGRE-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'other', 'not_restocked_note', 'kept for display')))) as e1f,
       pg_temp.as_role('service_role', null, 'insert into public.so_credit_line (not_restocked_reason) values (''b_grade'') returning 1') as e1g,
       pg_temp.as_role('service_role', null, 'insert into public.so_credit_line (not_restocked_reason) values (''damaged'') returning 1') as e1h,
       (select last_value || '|' || is_called from public.so_credit_number_seq) as cr_seq1 \gset
select pg_temp.chk(format('E1 b_grade refused (preview · commit with spaces · combo component) · damaged %s · not_returned %s · other with note %s · direct insert: b_grade IM651 · damaged passes the guard (%s) · credit numbers untouched %s = %s', :'e1d', :'e1e', :'e1f', left(:'e1h', 40), :'cr_seq0', :'cr_seq1'),
  :'e1a' like 'ERR P0001: B-grade goods go back into a B-grade bin now — pick a B-grade bin as the restock bin, or use damaged if it is thrown out%' and :'e1b' like 'ERR P0001: B-grade goods go back%' and :'e1c' like 'ERR P0001: B-grade goods go back%'
  and :'e1d' = 'false' and :'e1e' = 'false' and :'e1f' = 'false' and :'e1g' like 'ERR IM651: B-grade goods go back%' and :'e1h' like 'ERR 23502%' and :'cr_seq0' = :'cr_seq1',
  format('%s | %s | %s | %s | %s', :'e1a', :'e1b', :'e1c', :'e1g', :'e1h'));

\echo '── E2) 옛 b_grade 줄 — 실제 크레딧 하나를 replica 로 복사한 가짜(트리거 건넘 · 되감긴다)'
select (select c.id::text from public.so_credit c where exists (select 1 from public.so_credit_line l where l.credit_id = c.id and l.kind = 'product' and l.combo_components is null) order by c.created_at, c.id limit 1) as cr_src \gset
select gen_random_uuid()::text as cr_new, gen_random_uuid()::text as l_old, gen_random_uuid()::text as l_dmg \gset
set local session_replication_role = replica;
insert into public.so_credit select * from jsonb_populate_record(null::public.so_credit, (select to_jsonb(c) || jsonb_build_object('id', :'cr_new', 'credit_number', 'CR-90000001', 'created_at', now()) from public.so_credit c where c.id = :'cr_src'::uuid));
insert into public.so_credit_line select * from jsonb_populate_record(null::public.so_credit_line, (select to_jsonb(l) || jsonb_build_object('id', :'l_old', 'credit_id', :'cr_new', 'restock_bin_id', null, 'restock_bin', null, 'not_restocked_reason', 'b_grade', 'not_restocked_note', null)
  from public.so_credit_line l where l.credit_id = :'cr_src'::uuid and l.kind = 'product' and l.combo_components is null order by l.line_no limit 1));
insert into public.so_credit_line select * from jsonb_populate_record(null::public.so_credit_line, (select to_jsonb(l) || jsonb_build_object('id', :'l_dmg', 'credit_id', :'cr_new', 'line_no', 99, 'restock_bin_id', null, 'restock_bin', null, 'not_restocked_reason', 'damaged', 'not_restocked_note', null)
  from public.so_credit_line l where l.credit_id = :'cr_src'::uuid and l.kind = 'product' and l.combo_components is null order by l.line_no limit 1));
set local session_replication_role = origin;
select pg_temp.try_undo(format('update public.so_credit_line set not_restocked_note = ''old note'' where id = %L::uuid returning not_restocked_reason', :'l_old')) as e2a,
       pg_temp.try_undo(format('update public.so_credit_line set not_restocked_reason = ''b_grade'', not_restocked_note = ''same'' where id = %L::uuid returning not_restocked_reason', :'l_old')) as e2b,
       pg_temp.try_undo(format('update public.so_credit_line set not_restocked_reason = ''damaged'' where id = %L::uuid returning not_restocked_reason', :'l_old')) as e2c,
       pg_temp.try_undo(format('update public.so_credit_line set not_restocked_reason = ''b_grade'' where id = %L::uuid returning not_restocked_reason', :'l_dmg')) as e2d,
       pg_temp.as_role('service_role', null, format('with u as (update public.so_credit_line set not_restocked_reason = ''b_grade'' where id = %L::uuid returning 1) select count(*)::text from u', :'l_dmg')) as e2e \gset
select pg_temp.chk(format('E2 old b_grade line: note edit %s · same value %s · to damaged %s · damaged line to b_grade refused (postgres and service_role)', :'e2a', :'e2b', :'e2c'),
  :'cr_src' ~ '^[0-9a-f-]{36}$' and :'e2a' = 'PASS: b_grade' and :'e2b' = 'PASS: b_grade' and :'e2c' = 'PASS: damaged' and :'e2d' like 'ERR IM651: B-grade goods go back%' and :'e2e' like 'ERR IM651:%',
  format('%s | %s | %s | %s | %s', :'e2a', :'e2b', :'e2c', :'e2d', :'e2e'));

\echo '── E3) 1a ~ 1d 착지 유지'
create temp table bgr_src on commit drop as
  select p.proname, regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as s from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
select (select string_agg(proname, ',' order by proname) from bgr_src where (s ~ '\mims_inv_balance\M' or s ~ '\minv_balance\M') and s !~ 'bgrade') as l_blind,
       (select string_agg(proname, ',' order by proname) from bgr_src where s ~* 'insert\s+into\s+(public\.)?inv_ledger') as l_writers,
       (select count(*) from pg_constraint c where c.contype = 'f' and c.confrelid = 'public.ref_bin'::regclass) as l_fk,
       (select count(*) from pg_trigger where not tgisinternal and tgenabled = 'O' and tgname in ('so_credit_line_bgrade_refuse', 'inv_ledger_bgrade_guard', 'so_line_bgrade_guard', 'so_bgrade_header_guard', 'so_credit_line_reason_guard')) as l_trg,
       (select pg_get_constraintdef(oid) from pg_constraint where conname = 'so_credit_line_reason_ck') as l_ck \gset
select pg_temp.chk(format('E3 1a allowlist of eight · ledger writers twelve · bin FK %s · B-grade triggers %s · CHECK vocabulary kept (%s)', :l_fk, :l_trg, :'l_ck'),
  :'l_blind' = 'inv_adjust_ledger,inv_stock_master,inv_stock_master_sku,product_bom_set,product_update,stk_bins,stk_bins_many,wms_health_check'
  and :'l_writers' = 'inv_post_adjust,inv_post_credit,inv_post_move,inv_post_receipt,inv_post_receipt_off_po,inv_post_receipt_over,inv_post_sale,inv_post_transfer_arrive,inv_post_transfer_depart,so_credit_cancel,tf_over_decide,tf_settle'
  and :l_fk = 12 and :l_trg = 5 and :'l_ck' like '%''b_grade''%', format('%s || %s', :'l_blind', :'l_writers'));
\else
select pg_temp.chk('E1 ~ E3 skipped: bgr-1e not landed', false, 'so_credit_line_reason_guard missing');
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real credits · credit lines · ledger that existed at the snapshot untouched', pg_temp.real_rows(:'t0'::timestamptz) = :'real_before',
  format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));
select round(extract(epoch from clock_timestamp() - :'tb'::timestamptz)::numeric, 2) as tx_seconds_begin_to_rollback;
rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 크레딧 번호 시퀀스(당기지 않았다)'
select (select count(*) from public.product where sku like 'BGRE-%') + (select count(*) from public.ims_staff where email like 'bgre-%') + (select count(*) from public.customer where name like 'BGRE %') + (select count(*) from public.so_credit where credit_number = 'CR-90000001') as leftovers;
select last_value || '|' || is_called as so_credit_number_seq_after from public.so_credit_number_seq;
