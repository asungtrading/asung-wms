-- bo-pre-1-verify.sql — 프리오더를 Backorders 목록에(판정 351) · 백오더 쪽 무변 · 프리오더 행 · 거르기 kind · 판정 9 · 콤보 프리오더 · 비용 (Asung-IMS · 2026-10-07)
--   기대: 시험 갈래 OK 26 · 확인 갈래(G0 하나 없음) OK 25 · MISMATCH 0(시험 적용 2회차 통과 · 2026-10-07) · 재료는 가짜만(SO-7994x · BOPRE1-* · 가짜 손님 · 직원) · 실제 오더 · 예약 무접촉 · 시퀀스 무접촉 · 끝은 rollback
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261007163823_bo_pre_1_preorder_list.sql -f supabase/tests/bo-pre-1-verify.sql 2>&1 | tee /tmp/bo-pre-1.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다(D-pre 는 확인 갈래에서 새 함수 — 백오더 행 정규형은 kind 를 빼고 비교하므로 두 갈래 같은 식)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
\echo '== seq head so' :so_seq_last :so_seq_called 'inv' :inv_seq_last :inv_seq_called 'cr' :cr_seq_last :cr_seq_called
select count(*) filter (where kind = 'backorder' and released_at is null) as n_bo_open, count(*) filter (where kind = 'preorder' and released_at is null) as n_pre_open from public.so_reserve \gset
\echo '== open reserves on this DB: backorder' :n_bo_open '· preorder' :n_pre_open

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create temp table t_pre as
  select p.proname as n, p.prosrc as src from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname in ('so_backorder_list', 'so_backorder_proceed', 'so_backorder_sweep', 'so_backorder_supersede');
-- D-pre: 지금 DB 의 so_backorder_list 를 다른 이름으로(시험 갈래 = 옛 함수 · 확인 갈래 = 새 함수)
do $$
declare v_src text;
begin
  select src into v_src from t_pre where n = 'so_backorder_list';
  execute format('create function public.bopre1_pre_list(p_filters jsonb default ''{}''::jsonb) returns jsonb language plpgsql stable security invoker set search_path = public, pg_temp as %L', v_src);
end $$;
\if :{?mig}
select pg_temp.chk('G0 so_backorder_list last def = 20261006000805:622~792', (select md5(src) from t_pre where n = 'so_backorder_list'), 'ceda1928071e37a76a99b22bad4b54bb');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
-- 정규형: 백오더 행만(kind 없거나 backorder) · kind 열쇠를 뺀 행의 배열(순서 = 함수의 순서) · 머리 넷은 프리오더 몫을 뺀 값
create function pg_temp.canon_rows(p_j jsonb) returns text language sql as $$
  select md5(coalesce((select jsonb_agg(r - 'kind' order by ord) from jsonb_array_elements(p_j->'rows') with ordinality as t(r, ord) where coalesce(r->>'kind', 'backorder') = 'backorder')::text, '[]'))
$$;
create function pg_temp.canon_head(p_j jsonb) returns text language sql as $$
  select ((p_j->>'total')::int - coalesce((p_j->>'open_preorder')::int, 0))::text || '/' || ((p_j->>'open')::int - coalesce((p_j->>'open_preorder')::int, 0))::text || '/' || (p_j->>'ended') || '/'
         || ((p_j->>'open_owed')::int - (select count(*) from jsonb_array_elements(p_j->'rows') r where r->>'kind' = 'preorder' and (r->>'owed')::boolean))::text
$$;
create function pg_temp.both(p_f jsonb) returns text language sql as $$
  select case when pg_temp.canon_rows(public.bopre1_pre_list(p_f)) = pg_temp.canon_rows(public.so_backorder_list(p_f)) then 'rows-same' else 'ROWS-DIFFER' end
         || '/' || case when pg_temp.canon_head(public.bopre1_pre_list(p_f)) = pg_temp.canon_head(public.so_backorder_list(p_f)) then 'head-same' else 'HEAD-DIFFER' end
         || '/' || jsonb_array_length(public.so_backorder_list(p_f)->'rows')
$$;

-- ═══ B 백오더 쪽 무변 — 실물(실제 백오더 · 실제 프리오더 1) · 거르기 다섯 · 옛 함수 대 새 함수 ═══
select pg_temp.chk('B1 {} — backorder rows and heads unchanged', pg_temp.both('{}'::jsonb), 'rows-same/head-same/' || (public.so_backorder_list('{}'::jsonb)->>'total'));
select pg_temp.chk('B2 state open', pg_temp.both('{"state":"open"}'::jsonb), 'rows-same/head-same/' || (public.so_backorder_list('{"state":"open"}'::jsonb)->>'open'));
select pg_temp.chk('B3 state ended (no preorder rows here)', pg_temp.both('{"state":"ended"}'::jsonb) || '/' || (public.so_backorder_list('{"state":"ended"}'::jsonb)->>'open_preorder'), 'rows-same/head-same/' || (public.so_backorder_list('{"state":"ended"}'::jsonb)->>'ended') || '/0');
select pg_temp.chk('B4 arrived true', pg_temp.both('{"arrived":true}'::jsonb), 'rows-same/head-same/' || jsonb_array_length(public.so_backorder_list('{"arrived":true}'::jsonb)->'rows'));
select r->>'customer_id' as bo_cust from jsonb_array_elements(public.so_backorder_list('{"state":"open"}'::jsonb)->'rows') r where coalesce(r->>'kind', 'backorder') = 'backorder' limit 1 \gset
select pg_temp.chk('B5 one customer with open backorders', pg_temp.both(jsonb_build_object('customer_id', :'bo_cust')), 'rows-same/head-same/' || jsonb_array_length(public.so_backorder_list(jsonb_build_object('customer_id', :'bo_cust'))->'rows'));
select pg_temp.chk('B6 real open preorder reservations all listed as kind preorder · open_preorder = that count · open_backorder + open_preorder = open', (public.so_backorder_list('{}'::jsonb)->>'open_preorder') || '/' || ((public.so_backorder_list('{}'::jsonb)->>'open_backorder')::int + (public.so_backorder_list('{}'::jsonb)->>'open_preorder')::int = (public.so_backorder_list('{}'::jsonb)->>'open')::int)::text, :'n_pre_open' || '/true');

-- ═══ T 비용 — 빈 거르기 · 옛 함수 대 새 함수(실물 · 뜨거운 판) ═══
select length(public.bopre1_pre_list('{}'::jsonb)::text), length(public.so_backorder_list('{}'::jsonb)::text);
select clock_timestamp() as t0 \gset
select length(public.bopre1_pre_list('{}'::jsonb)::text);
select clock_timestamp() as t1 \gset
select length(public.so_backorder_list('{}'::jsonb)::text);
select clock_timestamp() as t2 \gset
select 'T cost ({} · ms · warm): before(pre)=' || round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000) || ' · after(new)=' || round(extract(epoch from (:'t2'::timestamptz - :'t1'::timestamptz)) * 1000) || ' · rows=' || (public.so_backorder_list('{}'::jsonb)->>'total');

-- ═══ 재료 — 직원(manager · sales) · 손님 · 제품 P(낱개 · 장부 없음) · 콤보 C + 구성품 P2 · 창고 X = Asung Trading Inc. · 오더 셋: 프리오더 PRE(P × 3) · 백오더 BO(P2 × 2 · kind 거르기용) · 콤보 프리오더 CPRE(C × 2 · 구성품 P2 예약) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'bopre1-manager@test.invalid', 'BOPRE1 Manager', 'manager', '["sales"]'::jsonb) returning auth_user_id::text as m_uid \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as whx, name as whx_name from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as tier, name as tier_name from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' limit 1 \gset
insert into public.ref_brand (name) values ('BOPRE1 Brand') returning id::text as br \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('BOPRE1 Customer', 'manual', :'tier_name', :'whx'::uuid, 0) returning id::text as cust \gset
insert into public.product (sku, name, source, brand_id) values ('BOPRE1-P', 'BOPRE1 Product P', 'manual', :'br'::uuid) returning id::text as pp \gset
insert into public.product (sku, name, source, brand_id) values ('BOPRE1-P2', 'BOPRE1 Product P2', 'manual', :'br'::uuid) returning id::text as pp2 \gset
insert into public.product (sku, name, source, brand_id) values ('BOPRE1-C', 'BOPRE1 Combo C', 'manual', :'br'::uuid) returning id::text as pc \gset
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, location_id, location_name, confirmed_at) values ('SO-79941', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'confirmed', '2031-01-10', :'tier'::uuid, 0, :'whx'::uuid, :'whx_name', now() - interval '2 days') returning id::text as o_pre \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, location_id, location_name, confirmed_at) values ('SO-79942', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'confirmed', '2031-01-10', :'tier'::uuid, 0, :'whx'::uuid, :'whx_name', now() - interval '2 days') returning id::text as o_bo \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, location_id, location_name, confirmed_at) values ('SO-79943', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'confirmed', '2031-01-10', :'tier'::uuid, 0, :'whx'::uuid, :'whx_name', now() - interval '2 days') returning id::text as o_cpre \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, list_price, unit_price) values (:'o_pre'::uuid, 1, :'pp'::uuid, 'BOPRE1-P', 'BOPRE1 Product P', 1, 3, 10, 10) returning id::text as l_pre \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, list_price, unit_price) values (:'o_bo'::uuid, 1, :'pp2'::uuid, 'BOPRE1-P2', 'BOPRE1 Product P2', 1, 2, 10, 10) returning id::text as l_bo \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, list_price, unit_price) values (:'o_cpre'::uuid, 1, :'pc'::uuid, 'BOPRE1-C', 'BOPRE1 Combo C', 1, 2, 30, 30) returning id::text as l_c \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, list_price, unit_price, combo_line_id, combo_qty) values (:'o_cpre'::uuid, 2, :'pp2'::uuid, 'BOPRE1-P2', 'BOPRE1 Product P2', 1, 2, null, 0, :'l_c'::uuid, 1) returning id::text as l_cc \gset
insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_at) values (:'l_pre'::uuid, 3, 'preorder', now() - interval '2 days');
insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_at) values (:'l_bo'::uuid, 2, 'backorder', now() - interval '2 days');
insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_at) values (:'l_cc'::uuid, 2, 'preorder', now() - interval '2 days');
set local session_replication_role = origin;
create function pg_temp.row_of(p_so text, p_f jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select r from jsonb_array_elements(public.so_backorder_list(p_f || '{"sku":"BOPRE1"}'::jsonb)->'rows') r where r->>'so_number' = p_so
$$;

-- ═══ P 프리오더 행 — kind preorder · arrived false · available 0 · 판정 9 칸 null → po_in → arrived true · available_here 5 → proceed 미리 보기 ═══
select pg_temp.chk('P1 fake rows listed: PRE preorder · BO backorder · CPRE preorder(combo) · heads open_preorder 2 · open_backorder 1 within sku filter', (pg_temp.row_of('SO-79941')->>'kind') || '/' || (pg_temp.row_of('SO-79942')->>'kind') || '/' || (pg_temp.row_of('SO-79943')->>'kind') || '/' || (pg_temp.row_of('SO-79943')->>'is_combo') || '/' || (public.so_backorder_list('{"sku":"BOPRE1"}'::jsonb)->>'open_preorder') || '/' || (public.so_backorder_list('{"sku":"BOPRE1"}'::jsonb)->>'open_backorder'), 'preorder/backorder/preorder/true/2/1');
select pg_temp.chk('P2 PRE before stock: arrived false · available_here 0 · qty_open 3 · days_waiting = today − order_date · backorder_since = reservation time', (pg_temp.row_of('SO-79941')->>'arrived') || '/' || (pg_temp.row_of('SO-79941')->>'available_here') || '/' || (pg_temp.row_of('SO-79941')->>'qty_open') || '/' || ((pg_temp.row_of('SO-79941')->>'days_waiting')::int = (public.ims_today() - '2031-01-10'::date))::text || '/' || ((pg_temp.row_of('SO-79941')->>'backorder_since')::timestamptz = (select allocated_at from public.so_reserve where so_line_id = :'l_pre'::uuid))::text, 'false/0/3/true/true');
select pg_temp.chk('P3 ruling 9 columns null on the preorder row: notified_at · end_kind · qty_taken · qty_unwanted · taken_by_so_id · taken_by_so_number · ended_at (7 nulls) · notified_state unknown_pre_ims', (select count(*) from unnest(array['notified_at', 'end_kind', 'qty_taken', 'qty_unwanted', 'taken_by_so_id', 'taken_by_so_number', 'ended_at']) k where jsonb_typeof(pg_temp.row_of('SO-79941')->k) = 'null')::text || '/' || (pg_temp.row_of('SO-79941')->>'notified_state'), '7/unknown_pre_ims');
set local session_replication_role = replica;
update public.so_line set backorder_notified_at = now() where id in (:'l_pre'::uuid, :'l_bo'::uuid);
set local session_replication_role = origin;
select pg_temp.chk('P3b even with backorder_notified_at set on the line: preorder row still notified_at null · backorder row shows it', (jsonb_typeof(pg_temp.row_of('SO-79941')->'notified_at')) || '/' || (pg_temp.row_of('SO-79942')->>'notified_state'), 'null/sent');
-- 입고(po_in · 장부 직접 · 창고 X · 오늘)
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values (public.ims_today(), 1, 'BOPRE1-P', :'whx_name', '', 5, 'po_in', 'purchase', 'PO-BOPRE1', 'bopre1-1', 'manual');
select pg_temp.chk('P4 after po_in 5 at warehouse X: PRE arrived true · available_here 5 · other warehouse 0', (pg_temp.row_of('SO-79941')->>'arrived') || '/' || (pg_temp.row_of('SO-79941')->>'available_here') || '/' || (pg_temp.row_of('SO-79941')->'available_other'->>'Asung - Edmonton'), 'true/5/0');
select pg_temp.chk('P4b arrived filter: true lists PRE · false does not', (select count(*) from jsonb_array_elements(public.so_backorder_list('{"sku":"BOPRE1","arrived":true}'::jsonb)->'rows') r where r->>'so_number' = 'SO-79941')::text || '/' || (select count(*) from jsonb_array_elements(public.so_backorder_list('{"sku":"BOPRE1","arrived":false}'::jsonb)->'rows') r where r->>'so_number' = 'SO-79941'), '1/0');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_backorder_proceed(:'o_pre'::uuid, false) as r \gset pr_
reset role;
select 'P5 proceed preview raw: ' || left(:'pr_r', 600);
select pg_temp.chk('P5 so_backorder_proceed preview on PRE: lines_released 1 · backorder_lines_ended 0 (no record for preorder) · reservation still open after preview', (:'pr_r'::jsonb->>'lines_released') || '/' || (:'pr_r'::jsonb->>'backorder_lines_ended') || '/' || (select (released_at is null)::text from public.so_reserve where so_line_id = :'l_pre'::uuid), '1/0/true');

-- ═══ C 콤보 프리오더 — 구성품 예약 · 콤보 줄 하나 · qty_open 2 · 구성품 P2 입고 → arrived · available_here ═══
select pg_temp.chk('C1 combo preorder before stock: kind preorder · is_combo · qty_open 2 · components has BOPRE1-P2 · arrived false · available_here 0', (pg_temp.row_of('SO-79943')->>'kind') || '/' || (pg_temp.row_of('SO-79943')->>'is_combo') || '/' || (pg_temp.row_of('SO-79943')->>'qty_open') || '/' || (pg_temp.row_of('SO-79943')->'components'->0->>'sku') || '/' || (pg_temp.row_of('SO-79943')->>'arrived') || '/' || (pg_temp.row_of('SO-79943')->>'available_here'), 'preorder/true/2/BOPRE1-P2/false/0');
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values (public.ims_today(), 1, 'BOPRE1-P2', :'whx_name', '', 4, 'po_in', 'purchase', 'PO-BOPRE1', 'bopre1-2', 'manual');
select pg_temp.chk('C2 after po_in 4 of P2: combo preorder arrived true · available_here 4 (whole combos) · backorder BO (same P2) arrived true · available 4', (pg_temp.row_of('SO-79943')->>'arrived') || '/' || (pg_temp.row_of('SO-79943')->>'available_here') || '/' || (pg_temp.row_of('SO-79942')->>'arrived') || '/' || (pg_temp.row_of('SO-79942')->>'available_here'), 'true/4/true/4');

-- ═══ K 거르기 kind ═══
select pg_temp.chk('K1 kind backorder → BO only', (select string_agg(r->>'so_number', ',' order by r->>'so_number') from jsonb_array_elements(public.so_backorder_list('{"sku":"BOPRE1","kind":"backorder"}'::jsonb)->'rows') r), 'SO-79942');
select pg_temp.chk('K2 kind preorder → PRE · CPRE', (select string_agg(r->>'so_number', ',' order by r->>'so_number') from jsonb_array_elements(public.so_backorder_list('{"sku":"BOPRE1","kind":"preorder"}'::jsonb)->'rows') r), 'SO-79941,SO-79943');
select pg_temp.chk('K3 no kind → all three · kind "" → all three', (select count(*) from jsonb_array_elements(public.so_backorder_list('{"sku":"BOPRE1"}'::jsonb)->'rows'))::text || '/' || (select count(*) from jsonb_array_elements(public.so_backorder_list('{"sku":"BOPRE1","kind":""}'::jsonb)->'rows')), '3/3');
do $$ begin perform public.so_backorder_list('{"kind":"hold"}'::jsonb); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlerrm, true); end $$;
select pg_temp.chk('K4 kind hold → refused', current_setting('app.out', true), 'kind must be backorder or preorder');
do $$ begin perform public.so_backorder_list('{"kinds":"preorder"}'::jsonb); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlerrm, true); end $$;
select pg_temp.chk('K5 unknown key still refused', current_setting('app.out', true), 'Unknown filter kinds');
select pg_temp.chk('K6 state ended + kind preorder → 0 rows (preorders are open only)', (public.so_backorder_list('{"state":"ended","kind":"preorder"}'::jsonb)->>'total'), '0');

-- ═══ G 무접촉 · 권한 · 백오더 쪽 무변 다시(가짜 재료가 든 뒤) ═══
select pg_temp.chk('G1 so_backorder_proceed · sweep · supersede md5 unchanged', (select count(*)::text from t_pre t join pg_proc p on p.proname = t.n join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public' where t.n <> 'so_backorder_list' and md5(p.prosrc) = md5(t.src)), '3');
select pg_temp.chk('G2 so_backorder_list: one def · invoker · stable · authenticated yes · anon no', (select count(*)::text from pg_proc where proname = 'so_backorder_list') || '/' || (select (not p.prosecdef)::text || '/' || p.provolatile::text from pg_proc p where p.proname = 'so_backorder_list') || '/' || has_function_privilege('authenticated', 'public.so_backorder_list(jsonb)', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_backorder_list(jsonb)', 'execute')::text, '1/true/s/true/false');
select pg_temp.chk('G3 head texts mention pre-orders', ((public.so_backorder_list('{}'::jsonb)->>'notify_tracking') like '%pre-order%')::text || '/' || ((public.so_backorder_list('{}'::jsonb)->>'arrived_rule') like '%ruling 351%')::text, 'true/true');
select pg_temp.chk('Z backorder rows and heads still equal to the old function with the fake material in place ({} · sku BOPRE1)', pg_temp.both('{}'::jsonb) || '/' || pg_temp.both('{"sku":"BOPRE1"}'::jsonb), 'rows-same/head-same/' || (public.so_backorder_list('{}'::jsonb)->>'total') || '/rows-same/head-same/3');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select 'seq tail so ' || last_value || ' ' || is_called from public.so_number_seq;
select 'seq tail inv ' || last_value || ' ' || is_called from public.so_invoice_number_seq;
select 'seq tail cr ' || last_value || ' ' || is_called from public.so_credit_number_seq;
