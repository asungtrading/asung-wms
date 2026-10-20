-- po-cn-1-verify.sql — 크레딧 노트 줄의 「크레딧 뒤 남은 차이」(판정 554): 열쇠 셋 · 0 → 확정 뒤 0 → 둘째 크레딧 −1 → 취소 뒤 0 · price_difference · reason 없음 · 다른 draft 는 안 센다 · qty_diff 무변 · 인보이스 반환 바이트 무변
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020161648_po_cn_1_qty_diff_after_credits.sql -f supabase/tests/po-cn-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0(옛 반환 포착) · G0 는 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더
--   재료는 가짜만(직원 · 공급처 · 제품 POCN1-P1 · PO-79600 70 @2 · 인보이스 POCN1-I1 70 확정 · RCV-79600 confirmed + 입고 줄 69 · 크레딧은 실제 창구 po_invoice_create 로) · rollback
--   ⚠️ \gset 줄 끝에 주석 금지 · 변수 이름 접두어(det…)

\echo '── 시퀀스 · db_role · schema_migrations'
select last_value as po_seq_last from public.po_number_seq \gset
select :po_seq_last as po_seq, (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261020161648' \gset
select :n_applied as schema_migrations_rows_for_20261020161648;

begin;
set local statement_timeout = '300s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return v;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 새 열쇠 셋을 뺀 detail(옛 모양과 대조용) · 시각 칸(updated_at 류)은 재료가 같은 트랜잭션이라 같다
create function pg_temp.strip(p jsonb) returns jsonb language sql as $$
  select p - 'lines' || jsonb_build_object('lines', coalesce((select jsonb_agg((e - 'qty_diff_after_credits' - 'credited_not_received_qty' - 'credit_billed_qty') order by (e->>'line_no')::int) from jsonb_array_elements(p->'lines') e), '[]'::jsonb)) $$;
create function pg_temp.l0(p jsonb, k text) returns text language sql as $$ select p->'lines'->0->>k $$;

\echo '── M0) 직원(purchasing + receiving) · 참조 · 실제 인보이스 행 스냅샷(id 집합)'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pocn1@test.invalid', 'POCN1 office', 'manager', '["ims","purchasing","receiving"]', '{}') returning auth_user_id::text as g_uid, id::text as st \gset
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bina from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
create temp table t_real_inv as select i.id from public.po_invoice i;
select count(*) as n_real_inv, md5(coalesce(string_agg(i.id::text || ':' || i.status || ':' || i.invoice_number, '|' order by i.id), '')) as md5_real_inv from public.po_invoice i join t_real_inv t on t.id = i.id \gset
select pg_temp.chk(format('M0 staff · CAD · warehouse · bin · %s real invoice rows snapshotted', :n_real_inv), :'g_uid' <> '' and :'cad' <> '' and :'bina' <> '' and :n_real_inv > 0, 'see M0');

\echo '── M1) 가짜 재료 — PO-79600(70 @2.00 · confirmed) · 인보이스 POCN1-I1 70 @2.00 confirmed · RCV-79600 confirmed · 입고 줄 69'
set local session_replication_role = replica;
insert into public.supplier (name, payment_term_name, account_payable_code) values ('POCN1 Supplier', 'Net 30', '2000') returning id::text as sup \gset
insert into public.product (sku, name, source) values ('POCN1-P1', 'POCN1 P1', 'manual') returning id::text as p1 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79600', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, public.ims_today() - 5, :'wh'::uuid, now()) returning id::text as po \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po'::uuid, 11, :'p1'::uuid, 70, 2.00) returning id::text as l1 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'POCN1-I1', public.ims_today() - 5, :'cad'::uuid, null, 140, 'confirmed', 'invoice', now()) returning id::text as i1 \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (:'i1'::uuid, 1, 'goods', :'l1'::uuid, 70, 2.00, true);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at, created_by) values ('RCV-79600', :'po'::uuid, :'wh'::uuid, public.ims_today() - 2, 'confirmed', now(), :'st'::uuid) returning id::text as r1 \gset
insert into public.po_receipt_line (po_line_id, received_on, received_by, bin_id, qty_ea, receipt_id) values (:'l1'::uuid, public.ims_today() - 2, :'st'::uuid, :'bina'::uuid, 69, :'r1'::uuid);
set local session_replication_role = origin;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
-- 첫 크레딧은 실제 창구로(자동 줄 = 청구 70 − 입고 69 = 1 · not_received) — \i 앞에 만들어 두 갈래 모두 「전」 반환을 잡는다
select pg_temp.run(format('select public.po_invoice_create(''credit'', null, %L::uuid, %L::uuid, %L::uuid, public.ims_today(), null, null, false, true, null)::text', :'po', :'i1', :'sup')) as cr1 \gset
select coalesce(pg_temp.j(:'cr1')->>'id', '00000000-0000-0000-0000-000000000000') as c1 \gset
select pg_temp.chk('M1 fixtures: PO-79600 line #11 70 · invoice 70 confirmed · received 69 · credit CN-PO-79600 draft with one not_received line of 1 (auto-filled by po_invoice_create)',
  :'cr1' not like 'ERR%' and (select count(*) from public.po_invoice_line il where il.po_invoice_id = :'c1'::uuid and il.line_kind = 'goods' and il.qty_ea = 1 and il.credit_reason = 'not_received') = 1
  and (select invoice_number from public.po_invoice where id = :'c1'::uuid) = 'CN-PO-79600' and (select status from public.po_invoice where id = :'c1'::uuid) = 'draft',
  left(:'cr1', 500));

select public.po_invoice_detail(:'i1'::uuid)::text as det_inv_before \gset
select public.po_invoice_detail(:'c1'::uuid)::text as det_c1_before \gset
\if :{?mig}
select pg_temp.chk('S0 (old · trial only) old detail: credit line qty_diff −68 (1 − 69) · no new keys · invoice line qty_diff 1',
  pg_temp.l0(pg_temp.j(:'det_c1_before'), 'qty_diff')::numeric = -68 and not (pg_temp.j(:'det_c1_before')->'lines'->0 ? 'qty_diff_after_credits') and pg_temp.l0(pg_temp.j(:'det_inv_before'), 'qty_diff')::numeric = 1,
  format('c1 %s | inv %s', left(:'det_c1_before', 300), left(:'det_inv_before', 200)));
select pg_temp.chk('G0 before the trial: po_invoice_detail has no qty_diff_after_credits · not in schema_migrations',
  (select prosrc from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure) !~ 'qty_diff_after_credits' and :n_applied = 0, format('n_applied %s', :n_applied));
\echo '── \i 시험 적용'
\i :mig
\else
select pg_temp.chk('P0c confirm run: migration 20261020161648 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

\echo '── G1) 실물'
select pg_temp.chk('G1 po_invoice_detail carries the three keys · calls po_credit_reason_suggest with p_exclude_line_id null · qty_diff expression byte-identical · one overload · authenticated may execute · po_invoice_create · po_credit_reason_suggest untouched (no po-cn-1 marker)',
  (select prosrc from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure) ~ 'qty_diff_after_credits'
  and (select prosrc from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure) ~ 'po_credit_reason_suggest\(p_invoice_id, il\.po_line_id, il\.qty_ea, null\)'
  and (select prosrc from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure) ~ '''qty_diff'', case when line_kind = ''goods'' then qty_ea - received_qty end'
  and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_invoice_detail') = 1
  and coalesce((select proacl::text from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure), '') ~ 'authenticated'
  and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('po_invoice_create', 'po_credit_reason_suggest') and prosrc ~ 'po-cn-1') = 0, 'see G1');

\echo '── S1) draft 크레딧 1: qty_diff_after_credits 0 · credited 1 · billed 70 · qty_diff 그대로 −68 · 인보이스 줄은 셋 다 null · qty_diff 1'
select public.po_invoice_detail(:'c1'::uuid)::text as det1 \gset
select public.po_invoice_detail(:'i1'::uuid)::text as det_inv1 \gset
select pg_temp.chk('S1 draft credit: qty_diff_after_credits 0 · credited_not_received_qty 1 · credit_billed_qty 70 · qty_diff still −68 · received_qty 69 · invoice line: three keys null · qty_diff 1',
  pg_temp.l0(pg_temp.j(:'det1'), 'qty_diff_after_credits')::numeric = 0 and pg_temp.l0(pg_temp.j(:'det1'), 'credited_not_received_qty')::numeric = 1 and pg_temp.l0(pg_temp.j(:'det1'), 'credit_billed_qty')::numeric = 70
  and pg_temp.l0(pg_temp.j(:'det1'), 'qty_diff')::numeric = -68 and pg_temp.l0(pg_temp.j(:'det1'), 'received_qty')::numeric = 69
  and (pg_temp.j(:'det_inv1')->'lines'->0 ? 'qty_diff_after_credits') and pg_temp.l0(pg_temp.j(:'det_inv1'), 'qty_diff_after_credits') is null and pg_temp.l0(pg_temp.j(:'det_inv1'), 'credited_not_received_qty') is null and pg_temp.l0(pg_temp.j(:'det_inv1'), 'credit_billed_qty') is null
  and pg_temp.l0(pg_temp.j(:'det_inv1'), 'qty_diff')::numeric = 1,
  format('c1 %s | inv %s', left(:'det1', 400), left(:'det_inv1', 300)));

\echo '── S2) 확정 → 0 그대로'
select pg_temp.run(format('select public.po_invoice_confirm(%L::uuid, true)::text', :'c1')) as cf1 \gset
select public.po_invoice_detail(:'c1'::uuid)::text as det2 \gset
select pg_temp.chk('S2 confirmed credit: still 0 · credited 1', :'cf1' not like 'ERR%' and (select status from public.po_invoice where id = :'c1'::uuid) = 'confirmed'
  and pg_temp.l0(pg_temp.j(:'det2'), 'qty_diff_after_credits')::numeric = 0 and pg_temp.l0(pg_temp.j(:'det2'), 'credited_not_received_qty')::numeric = 1, format('cf1 %s | %s', left(:'cf1', 200), left(:'det2', 300)));

\echo '── S3) 둘째 크레딧 1(draft) → 둘째 줄 −1(이 문서 + 확정 첫째 = 2 · 과한 크레딧이 드러난다) · 첫째(확정)는 다른 draft 를 안 세어 0 · 둘째 확정은 po_invoice_confirm 이 이미 막는다(「only 0 EA are still unreceived」 · 확정 문서끼리는 −1 이 생기지 않는다)'
select pg_temp.run(format('select public.po_invoice_create(''credit'', null, %L::uuid, %L::uuid, %L::uuid, public.ims_today(), null, null, false, true, null)::text', :'po', :'i1', :'sup')) as cr2 \gset
select coalesce(pg_temp.j(:'cr2')->>'id', '00000000-0000-0000-0000-000000000000') as c2 \gset
select public.po_invoice_detail(:'c2'::uuid)::text as det3b \gset
select public.po_invoice_detail(:'c1'::uuid)::text as det3a \gset
select pg_temp.run(format('select public.po_invoice_confirm(%L::uuid, true)::text', :'c2')) as cf2 \gset
select public.po_invoice_detail(:'c2'::uuid)::text as det3d \gset
select public.po_invoice_detail(:'c1'::uuid)::text as det3c \gset
select pg_temp.chk('S3 second credit of 1: as draft its line reads −1 (credited 2 = itself + confirmed first) while the confirmed first still reads 0 (other drafts are not counted) · confirming the second is refused by the existing check ("only 0 EA are still unreceived") so both stay (−1 draft · 0 confirmed) · qty_diff on the second still −68',
  :'cr2' not like 'ERR%' and (select count(*) from public.po_invoice_line il where il.po_invoice_id = :'c2'::uuid and il.line_kind = 'goods' and il.qty_ea = 1 and il.credit_reason = 'not_received') = 1
  and pg_temp.l0(pg_temp.j(:'det3b'), 'qty_diff_after_credits')::numeric = -1 and pg_temp.l0(pg_temp.j(:'det3b'), 'credited_not_received_qty')::numeric = 2
  and pg_temp.l0(pg_temp.j(:'det3a'), 'qty_diff_after_credits')::numeric = 0 and pg_temp.l0(pg_temp.j(:'det3a'), 'credited_not_received_qty')::numeric = 1
  and :'cf2' like 'ERR %still unreceived%' and (select status from public.po_invoice where id = :'c2'::uuid) = 'draft'
  and pg_temp.l0(pg_temp.j(:'det3d'), 'qty_diff_after_credits')::numeric = -1 and pg_temp.l0(pg_temp.j(:'det3c'), 'qty_diff_after_credits')::numeric = 0
  and pg_temp.l0(pg_temp.j(:'det3b'), 'qty_diff')::numeric = -68,
  format('cr2 %s | c2 draft %s %s | c1 %s %s | cf2 %s | after refused confirm c2 %s · c1 %s', left(:'cr2', 120), pg_temp.l0(pg_temp.j(:'det3b'), 'qty_diff_after_credits'), pg_temp.l0(pg_temp.j(:'det3b'), 'credited_not_received_qty'), pg_temp.l0(pg_temp.j(:'det3a'), 'qty_diff_after_credits'), pg_temp.l0(pg_temp.j(:'det3a'), 'credited_not_received_qty'), left(:'cf2', 200), pg_temp.l0(pg_temp.j(:'det3d'), 'qty_diff_after_credits'), pg_temp.l0(pg_temp.j(:'det3c'), 'qty_diff_after_credits')));

\echo '── S4) 둘째(draft)를 취소 → 첫 크레딧 0 · 취소된 것은 안 센다'
select pg_temp.run(format('select public.po_doc_cancel(''invoice'', %L::uuid, true)::text', :'c2')) as cx2 \gset
select public.po_invoice_detail(:'c1'::uuid)::text as det4 \gset
select pg_temp.chk('S4 cancelled credit not counted: first credit stays 0 · credited 1 · the cancelled second reads its own line only against confirmed ones', :'cx2' not like 'ERR%' and (select status from public.po_invoice where id = :'c2'::uuid) = 'cancelled'
  and pg_temp.l0(pg_temp.j(:'det4'), 'qty_diff_after_credits')::numeric = 0 and pg_temp.l0(pg_temp.j(:'det4'), 'credited_not_received_qty')::numeric = 1, format('cx2 %s | %s %s', left(:'cx2', 200), pg_temp.l0(pg_temp.j(:'det4'), 'qty_diff_after_credits'), pg_temp.l0(pg_temp.j(:'det4'), 'credited_not_received_qty')));

\echo '── S5) 셋째 draft 크레딧 — 그 줄을 price_difference 로 → 그 줄 0(안 센다 · credited 1 = 첫 크레딧만) · reason null → 같음 · 첫 크레딧은 다른 draft 를 안 센다(0)'
select pg_temp.run(format('select public.po_invoice_create(''credit'', null, %L::uuid, %L::uuid, %L::uuid, public.ims_today(), null, null, false, true, null)::text', :'po', :'i1', :'sup')) as cr3 \gset
select coalesce(pg_temp.j(:'cr3')->>'id', '00000000-0000-0000-0000-000000000000') as c3 \gset
update public.po_invoice_line set credit_reason = 'price_difference' where po_invoice_id = :'c3'::uuid and line_kind = 'goods';
select public.po_invoice_detail(:'c3'::uuid)::text as det5a \gset
update public.po_invoice_line set credit_reason = null where po_invoice_id = :'c3'::uuid and line_kind = 'goods';
select public.po_invoice_detail(:'c3'::uuid)::text as det5b \gset
select public.po_invoice_detail(:'c1'::uuid)::text as det5c \gset
select pg_temp.chk('S5 price_difference line: 0 (credited 1 · not this line) · reason null: 0 (credited 1) · first credit ignores the other draft: 0 (credited 1)',
  :'cr3' not like 'ERR%' and pg_temp.l0(pg_temp.j(:'det5a'), 'qty_diff_after_credits')::numeric = 0 and pg_temp.l0(pg_temp.j(:'det5a'), 'credited_not_received_qty')::numeric = 1
  and pg_temp.l0(pg_temp.j(:'det5b'), 'qty_diff_after_credits')::numeric = 0 and pg_temp.l0(pg_temp.j(:'det5b'), 'credited_not_received_qty')::numeric = 1
  and pg_temp.l0(pg_temp.j(:'det5c'), 'qty_diff_after_credits')::numeric = 0 and pg_temp.l0(pg_temp.j(:'det5c'), 'credited_not_received_qty')::numeric = 1,
  format('c3 pd %s | c3 null %s | c1 %s', left(:'det5a', 260), left(:'det5b', 260), left(:'det5c', 260)));

\echo '── S6) 바이트 무변 — 인보이스 detail(새 열쇠 null 셋을 빼면 전과 같음) · 첫 크레딧 detail(새 열쇠 셋을 빼면 전과 같음 · 같은 상태로 되돌려 대조: draft 때 잡은 것과 S1 의 것)'
select pg_temp.chk('S6 invoice detail unchanged apart from the three null keys · credit detail (draft · before vs after) unchanged apart from the three keys',
  pg_temp.strip(pg_temp.j(:'det_inv_before')) = pg_temp.strip(pg_temp.j(:'det_inv1')) and pg_temp.strip(pg_temp.j(:'det_c1_before')) = pg_temp.strip(pg_temp.j(:'det1')),
  format('inv eq %s | c1 eq %s', pg_temp.strip(pg_temp.j(:'det_inv_before')) = pg_temp.strip(pg_temp.j(:'det_inv1')), pg_temp.strip(pg_temp.j(:'det_c1_before')) = pg_temp.strip(pg_temp.j(:'det1'))));

\echo '── Z1) 실제 인보이스 행 무접촉(스냅샷 id 집합)'
select pg_temp.chk(format('Z1 %s real invoice rows untouched', :n_real_inv),
  (select md5(coalesce(string_agg(i.id::text || ':' || i.status || ':' || i.invoice_number, '|' order by i.id), '')) from public.po_invoice i join t_real_inv t on t.id = i.id) = :'md5_real_inv', 'see Z1');

rollback;
\echo '── rollback 뒤 — 시퀀스 · 가짜 흔적 0'
select (select last_value from public.po_number_seq) as po_seq_now, :po_seq_last as po_seq_head,
       (select count(*) from public.po where po_number = 'PO-79600') + (select count(*) from public.po_invoice where invoice_number like '%79600%' or invoice_number like 'POCN1%') + (select count(*) from public.ims_staff where email like 'pocn1%') + (select count(*) from public.product where sku like 'POCN1-%') as fake_traces_left;
