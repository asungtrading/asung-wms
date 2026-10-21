-- crn-2-verify.sql — 크레딧 가격 조정 줄(판정 603 · 611 · 612 · 613 · 614):
--   T1 ~ T12 는 지시서 §3 의 표 그대로(인보이스 A 20 @ 9.99 · B 20 @ 9.99 + 오더 할인 5% · C 5 @ 9.99 동일성용 · 참조 크레딧) · T13 동일성(가격 조정 없는 인보이스 크레딧 · 참조 크레딧 · 준비 창구 — \i 앞 · 뒤 같다 · 새 열쇠만 다름) · 무접촉(G0 · G1 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261021201400_crn_2_price_adjustment.sql -f supabase/tests/crn-2-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · T13 셋은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 OK 수 − 2 · MISMATCH 0
--   가짜 재료는 전부 CRN2(손님 · 제품 + 칸 재고 60 + 레이어 · 티어 가격 9.99 · 직원 M sales manager · W sales worker) · 번호는 창구가 당긴다(so · so_invoice · so_credit 머리 → rollback 뒤 greatest)
--   ⚠️ 동일성(T13)은 pg_temp.scn 이 서브트랜잭션 안에서 재료를 만들고 끝까지 돌린 뒤 결과를 예외 메시지로 꺼내고 되감는다(쓰기 0) · 번호 · uuid · 시각 · 숫자 id 는 norm 으로 지운다 · 준비 창구의 새 열쇠(adjust · vocab)는 떼고 비교

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261021201400' \gset
select :n_applied as schema_migrations_rows_for_20261021201400;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
select :so_seq_last as so_seq_head, :inv_seq_last as inv_seq_head, :cr_seq_last as cr_seq_head,
       (select max(substring(so_number from '[0-9]+')::bigint) from public.so) as so_max_head, (select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$') as inv_max_head,
       (select max(substring(credit_number from '[0-9]+')::bigint) from public.so_credit) as cr_max_head;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.norm(p text) returns text language sql immutable as $$
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''),
           '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '#', 'g'),
           '"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]+"', '"T"', 'g'),
           'SO-[0-9]{5,}', 'SO-#', 'g'),
           '("(invoice_number|number|credit_number|credit_note_number)": ")[A-Z-]*[0-9]+"', '\1#"', 'g'),
           'CR-[0-9]+', 'CR-#', 'g'),
           '("[a-z_]*id"): [0-9]+', '\1: 0', 'g'),
           '"printed_at": "[^"]*"', '"printed_at": "T"', 'g') $$;
-- 준비 창구의 새 열쇠를 떼고(adjust · vocab) 정규화해 jsonb 로 다시 읽는다(열쇠 순서)
create function pg_temp.canon_prep(p text) returns text language sql immutable as $$
  select case when p is null or left(p, 1) <> '{' then p else ((pg_temp.norm(p)::jsonb - 'vocab') || jsonb_build_object('lines', (select coalesce(jsonb_agg(l - 'adjust'), '[]'::jsonb) from jsonb_array_elements(pg_temp.norm(p)::jsonb->'lines') l)))::text end $$;
create function pg_temp.canon(p text) returns text language sql immutable as $$ select case when p is null or left(p, 1) not in ('{', '[') then p else (pg_temp.norm(p)::jsonb)::text end $$;
-- 상세(so_credit_detail · 무변)는 to_jsonb(l) 이라 이주 뒤 줄에 새 칸 셋이 null 열쇠로 붙는다 — 동일성 비교에서만 그 셋을 벗긴다
create function pg_temp.canon_det(p jsonb) returns jsonb language sql immutable as $$
  select case when p is null then null else jsonb_set(p, '{lines}', (select coalesce(jsonb_agg(l - 'qty_adjusted' - 'unit_price_before' - 'unit_price_after'), '[]'::jsonb) from jsonb_array_elements(p->'lines') l)) end $$;
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 크레딧 자취 — 머리 · 줄(kind|qty_returned|qty_adjusted|before|after|unit|amount|tax|account) · 원장 행 수 · 레이어
create function pg_temp.cr_trace(p_cr uuid) returns text language plpgsql security definer as $$
begin
  return (select 'cr[' || c.status || '|' || c.reason || '|' || trim_scale(c.lines_amount) || '|' || trim_scale(c.order_discount_amount) || '|' || trim_scale(c.fee_amount) || '|' || trim_scale(c.surcharge_amount) || '|' || trim_scale(c.tax_amount) || '|' || trim_scale(c.total) || ']'
      || ' lines[' || coalesce((select string_agg(l.kind || '|' || coalesce(trim_scale(l.qty_returned)::text, '-') || '|' || coalesce(trim_scale(l.qty_adjusted)::text, '-') || '|' || coalesce(trim_scale(l.unit_price_before)::text, '-') || '|' || coalesce(trim_scale(l.unit_price_after)::text, '-') || '|' || coalesce(trim_scale(l.unit_price)::text, '-') || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount) || '|' || coalesce(l.account_code, '-'), ',' order by l.line_no) from public.so_credit_line l where l.credit_id = c.id), '-') || ']'
      || ' ledger=' || (select count(*) from public.inv_ledger g where g.doc_number = c.credit_number and g.source = 'ims')
      || ' layers=' || (select count(*) from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = c.credit_number)
  from public.so_credit c where c.id = p_cr);
end $$;
create function pg_temp.cr_trace0(p_cr uuid) returns text language plpgsql security definer as $$
begin
  return (select 'cr[' || c.status || '|' || c.reason || '|' || trim_scale(c.lines_amount) || '|' || trim_scale(c.tax_amount) || '|' || trim_scale(c.total) || ']'
      || ' lines[' || coalesce((select string_agg(l.kind || '|' || coalesce(trim_scale(l.qty_returned)::text, '-') || '|' || coalesce(trim_scale(l.unit_price)::text, '-') || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount) || '|' || coalesce(l.account_code, '-'), ',' order by l.line_no) from public.so_credit_line l where l.credit_id = c.id), '-') || ']'
      || ' ledger=' || (select count(*) from public.inv_ledger g where g.doc_number = c.credit_number and g.source = 'ims') || ' layers=' || (select count(*) from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = c.credit_number)
  from public.so_credit c where c.id = p_cr);
end $$;
create function pg_temp.st(p_il uuid) returns text language plpgsql security definer as $$
begin
  return (select 'paid=' || trim_scale((s->>'paid_unit_price')::numeric) || ' ret=' || trim_scale((s->>'qty_returned')::numeric) || ' returnable=' || trim_scale((s->>'qty_returnable')::numeric) || ' adjustable=' || trim_scale((s->>'qty_adjustable')::numeric) || ' adj_open=' || trim_scale((s->>'qty_adjusted_open')::numeric)
      || ' tiers=' || coalesce((select string_agg(trim_scale((t->>'qty')::numeric) || '@' || trim_scale((t->>'unit_price')::numeric) || case when (t->>'paid')::boolean then 'p' else '' end, ',') from jsonb_array_elements(s->'tiers') t), '') || ' adjs=' || jsonb_array_length(s->'adjustments')
  from public.so_credit_line_state(p_il) s);
end $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'cols=' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_credit_line' and column_name in ('qty_adjusted', 'unit_price_before', 'unit_price_after'))::text
      || ' kind_ck=' || ((select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so_credit_line'::regclass and conname = 'so_credit_line_kind_ck') ~ 'price_adjustment')::text
      || ' reason_ck=' || ((select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so_credit'::regclass and conname = 'so_credit_reason_ck') ~ 'price_adjustment')::text
      || ' state_fn=' || (to_regprocedure('public.so_credit_line_state(uuid)') is not null)::text
      || ' issue_adj=' || (select (p.prosrc ~ 'price_adjustment')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_issue') $$;
create function pg_temp.real_rows() returns text language sql security definer as $$
  select 'cr=' || (select count(*) || '/' || md5(coalesce(string_agg(c.id::text || c.status || c.total, ',' order by c.id), '')) from public.so_credit c where c.customer_id not in (select id from public.customer where name like 'CRN2 %'))
      || ' crl=' || (select count(*) from public.so_credit_line l join public.so_credit c on c.id = l.credit_id where c.customer_id not in (select id from public.customer where name like 'CRN2 %'))
      || ' inv=' || (select count(*) from public.so_invoice i where i.bill_to_customer_id not in (select id from public.customer where name like 'CRN2 %'))
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where sku not like 'CRN2-%')
      || ' fns=' || (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('inv_post_credit', 'so_credit_detail', 'so_credit_attach', 'so_credit_alloc_add', 'so_credit_remaining', 'so_customer_balance', 'inv_layer_post_credit', 'so_detail', 'doc_data', 'so_tax_amount', 'so_line_manual', 'so_invoice_issue')) $$;
-- 물건 오더 하나 → 인보이스(p_qty @ 티어 가격 · p_od = 오더 할인 % 또는 null) → {so_id, invoice_id, invoice_line_id}
create function pg_temp.mk_invoice(p_claims text, p_cust uuid, p_pid uuid, p_wh uuid, p_bin text, p_rule uuid, p_rule_name text, p_qty numeric, p_od numeric, p_note text) returns jsonb language plpgsql as $$
declare v_so uuid; v_l uuid; v_x jsonb; v_inv uuid; v_il uuid;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  v_x := public.so_create(p_cust, 'warehouse', 'manual', p_wh, p_note);  v_so := (v_x->>'id')::uuid;
  if p_od is not null then v_x := public.so_header_update(v_so, jsonb_build_object('order_discount_pct', p_od)); end if;
  v_x := public.so_line_add(v_so, p_pid, p_qty, null, null, null, null, false);  v_l := (v_x->'line'->>'id')::uuid;      -- 단가 안 줌 → 티어 가격(손으로 정한 줄 아님 · 오더 할인을 받는다)
  execute 'set local session_replication_role = replica';
  update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
  execute 'set local session_replication_role = origin';
  v_x := public.so_confirm(v_so, null, false, true);
  execute 'set local session_replication_role = replica';
  update public.so set status = 'packed' where id = v_so and status = 'confirmed';
  execute 'set local session_replication_role = origin';
  v_x := public.so_finalize(jsonb_build_array(jsonb_build_object('so_id', v_so, 'picks', jsonb_build_array(jsonb_build_object('line_id', v_l, 'bin', p_bin, 'qty', p_qty)))), true, null);
  select i.id into v_inv from public.so_invoice i join public.so_invoice_order o on o.invoice_id = i.id where o.so_id = v_so and o.cancelled_at is null;
  select l.id into v_il from public.so_invoice_line l where l.invoice_id = v_inv and l.kind = 'product';
  return jsonb_build_object('so_id', v_so, 'invoice_id', v_inv, 'invoice_line_id', v_il, 'line', (select trim_scale(l.qty) || '@' || trim_scale(l.unit_price) || '|' || (select coalesce(trim_scale(o.order_discount_pct)::text, '-') from public.so_invoice_order o where o.id = l.invoice_order_id) from public.so_invoice_line l where l.id = v_il));
exception when others then
  return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
end $$;
-- 동일성 한 경우(가격 조정 없음): 인보이스 C 의 반품 2 미리 보기 · 발행 · 상세 · 문서 · 준비 창구 + 참조 크레딧 미리 보기
create function pg_temp.scn(p_claims text, p_cust uuid, p_pid uuid, p_wh uuid, p_bin text, p_rule uuid, p_rule_name text) returns jsonb language plpgsql as $$
declare v_mk jsonb; v_inv uuid; v_il uuid; v_p jsonb; v_prep jsonb; v_prev jsonb; v_iss jsonb; v_cr uuid; v_det jsonb; v_doc jsonb; v_ref jsonb;
begin
  begin
    v_mk := pg_temp.mk_invoice(p_claims, p_cust, p_pid, p_wh, p_bin, p_rule, p_rule_name, 5, null, 'crn-2 ident C');
    if v_mk ? 'err' then raise exception 'mk: %', v_mk->>'err'; end if;
    v_inv := (v_mk->>'invoice_id')::uuid;  v_il := (v_mk->>'invoice_line_id')::uuid;
    perform set_config('request.jwt.claims', p_claims, true);
    v_prep := public.so_credit_prepare(v_inv);
    v_p := jsonb_build_object('invoice_id', v_inv, 'reason', 'customer_return', 'warehouse_id', p_wh, 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', v_il, 'qty_returned', 2, 'restock_bin', p_bin)));
    v_prev := public.so_credit_issue(v_p, false);
    v_iss := public.so_credit_issue(v_p, true);  v_cr := (v_iss->>'credit_id')::uuid;
    v_det := public.so_credit_detail(v_cr);
    v_doc := public.doc_data('credit_note', jsonb_build_object('credit_id', v_cr));
    v_ref := public.so_credit_issue(jsonb_build_object('customer_id', p_cust, 'reason', 'customer_return', 'tax_rule', p_rule_name, 'ref', jsonb_build_object('invoice_number', 'INV-OLD-C'),
                                                       'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN2-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'not_returned'))), false);
    raise exception using errcode = 'P7777', message = jsonb_build_object('prep', v_prep, 'prev', v_prev, 'iss', v_iss, 'det', v_det, 'doc', v_doc, 'ref', v_ref, 'trace', pg_temp.cr_trace0(v_cr))::text;
  exception when sqlstate 'P7777' then
    return sqlerrm::jsonb;
  when others then
    return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
  end;
end $$;

\echo '── M0) 가짜 직원 둘(M sales manager · W sales worker) · 손님 · 제품 + 칸 재고 60 + 레이어 60 @ 2.5 · 티어 가격 9.99 · 세율 · 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'crn2-m@test.invalid', 'CRN2 M', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as m_uid, id::text as m_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'crn2-w@test.invalid', 'CRN2 W', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as w_uid \gset
\set m '{"sub":"' :m_uid '","role":"authenticated"}'
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.name as bina from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select rt.id::text as tier_id, rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as r13, name as r13_name, rate_pct as r13_rate from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('CRN2 Customer', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as cust \gset
insert into public.product (sku, name, source) values ('CRN2-P', 'CRN2 Product', 'manual') returning id::text as pid \gset
insert into public.product_price (product_id, tier_id, price, source) values (:'pid'::uuid, :'tier_id'::uuid, 9.99, 'manual');
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values (public.ims_today() - 3, 1, 'CRN2-P', :'whname', :'bina', 60, 'po_in', 'purchase', 'PO-CRN2', 'crn2-1', 'manual');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values ('CRN2-P', :'whname', 'purchase', 'PO-CRN2', 'crn2-1', public.ims_today() - 3, true, 60, 2.5, 'po_line');
set local session_replication_role = origin;
select pg_temp.real_rows() as real_before, pg_temp.gate_state() as gate_before \gset
select pg_temp.chk(format('M0 staff ×2 · customer (tier %s) · product CRN2-P 9.99 · stock 60 in %s · tax %s %s%% · snapshots taken', :'tier_name', :'bina', :'r13_name', trim_scale(:'r13_rate'::numeric)),
  :'m_uid' <> '' and :'cust' <> '' and :'pid' <> '' and :'r13' <> '' and :'real_before' <> '', 'see M0');

create temp table t_ident (phase text, prep text, prev text, iss text, det text, doc text, ref text, trace text, err text);

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — price_adjustment 줄 종류 · 사유 없음 · 칸 없음 · 도우미 없음'
select pg_temp.chk('S0 before the trial: no qty_adjusted column · kind CHECK without price_adjustment · reason CHECK without price_adjustment · no so_credit_line_state · not in schema_migrations',
  :'gate_before' = 'cols=0 kind_ck=false reason_ck=false state_fn=false issue_adj=false' and :n_applied = 0, :'gate_before');
\echo '── I0) 동일성 — 옛 판(되감김)'
insert into t_ident select 'old', pg_temp.canon_prep((v->'prep')::text), pg_temp.canon((v->'prev')::text), pg_temp.canon((v->'iss')::text), pg_temp.canon((v->'det')::text), pg_temp.canon((v->'doc')::text), pg_temp.canon((v->'ref')::text), v->>'trace', v->>'err'
  from (select pg_temp.scn(:'m', :'cust'::uuid, :'pid'::uuid, :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name') as v) x;
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: untouched functions same md5 · real credits · invoices · ledger unchanged', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));
\echo '── T13) 동일성 — 새 판으로 같은 경우 · 비교'
insert into t_ident select 'new', pg_temp.canon_prep((v->'prep')::text), pg_temp.canon((v->'prev')::text), pg_temp.canon((v->'iss')::text), pg_temp.canon((v->'det')::text), pg_temp.canon((v->'doc')::text), pg_temp.canon((v->'ref')::text), v->>'trace', v->>'err'
  from (select pg_temp.scn(:'m', :'cust'::uuid, :'pid'::uuid, :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name') as v) x;
select coalesce(o.prep = n.prep, false) as same_prep, coalesce(o.prev = n.prev, false) as same_prev, coalesce(o.iss = n.iss, false) as same_iss, coalesce(pg_temp.canon_det(pg_temp.j(o.det) #- '{credit_row,search_text}') = pg_temp.canon_det(pg_temp.j(n.det) #- '{credit_row,search_text}'), false) as same_det, coalesce(o.doc = n.doc, false) as same_doc, coalesce(o.ref = n.ref, false) as same_ref,
       coalesce(o.trace = n.trace, false) as same_trace, coalesce(o.err, '-') as old_err, coalesce(n.err, '-') as new_err, coalesce(o.trace, '-') as old_trace, coalesce(n.trace, '-') as new_trace,
       coalesce((select string_agg(coalesce(a.k, b.k) || ': ' || left(coalesce(a.v::text, '∅'), 200) || ' ≠ ' || left(coalesce(b.v::text, '∅'), 200), ' || ') from jsonb_each(coalesce(pg_temp.j(o.prep), '{}'::jsonb)) a(k, v) full join jsonb_each(coalesce(pg_temp.j(n.prep), '{}'::jsonb)) b(k, v) on b.k = a.k where a.v is distinct from b.v), '-') as prep_diff
  from t_ident o join t_ident n on n.phase = 'new' where o.phase = 'old' \gset
select pg_temp.chk('T13 no-adjustment credit: prepare (minus adjust · vocab) · preview · issue · detail (minus the three new null keys) · credit_note doc · reference preview · trace identical before and after · both ran without error',
  :'same_prep' = 't' and :'same_prev' = 't' and :'same_iss' = 't' and :'same_det' = 't' and :'same_doc' = 't' and :'same_ref' = 't' and :'same_trace' = 't' and :'old_err' = '-' and :'new_err' = '-',
  format('prep %s | prev %s | iss %s | det %s | doc %s | ref %s | trace %s | errs %s / %s | prep_diff %s | old %s | new %s', :'same_prep', :'same_prev', :'same_iss', :'same_det', :'same_doc', :'same_ref', :'same_trace', :'old_err', :'new_err', left(:'prep_diff', 600), left(:'old_trace', 300), left(:'new_trace', 300)));
\else
select pg_temp.chk('P0c confirm run: migration 20261021201400 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() = 'cols=3 kind_ck=true reason_ck=true state_fn=true issue_adj=true') as landed \gset
\if :landed
\echo '── G1) 실물'
select pg_temp.chk('G1 columns ×3 · kind CHECK + price_adjustment · adjust CHECK · reason CHECK · helpers (state authenticated yes · anon no · tiers_* authenticated no) · so_credit_issue takes price_adjustment',
  pg_temp.gate_state() = 'cols=3 kind_ck=true reason_ck=true state_fn=true issue_adj=true'
  and exists (select 1 from pg_constraint where conrelid = 'public.so_credit_line'::regclass and conname = 'so_credit_line_adjust_ck')
  and has_function_privilege('authenticated', 'public.so_credit_line_state(uuid)', 'execute') and not has_function_privilege('anon', 'public.so_credit_line_state(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.so_credit_tiers_take(jsonb, numeric, numeric)', 'execute') and not has_function_privilege('authenticated', 'public.so_credit_tiers_add(jsonb, numeric, numeric)', 'execute'), pg_temp.gate_state());

\echo '── 재료 — 인보이스 A(20 @ 9.99) · B(20 @ 9.99 · 오더 할인 5%)'
select pg_temp.mk_invoice(:'m', :'cust'::uuid, :'pid'::uuid, :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', 20, null, 'crn-2 A')::text as mka \gset
select pg_temp.mk_invoice(:'m', :'cust'::uuid, :'pid'::uuid, :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', 20, 5, 'crn-2 B')::text as mkb \gset
select coalesce(pg_temp.j(:'mka')->>'invoice_id', '00000000-0000-0000-0000-000000000000') as inva, coalesce(pg_temp.j(:'mka')->>'invoice_line_id', '00000000-0000-0000-0000-000000000000') as ila,
       coalesce(pg_temp.j(:'mkb')->>'invoice_id', '00000000-0000-0000-0000-000000000000') as invb, coalesce(pg_temp.j(:'mkb')->>'invoice_line_id', '00000000-0000-0000-0000-000000000000') as ilb \gset
select pg_temp.chk(format('M1 invoices: A line %s · B line %s (order discount 5%% · line not manual) · B state paid 9.49', pg_temp.j(:'mka')->>'line', pg_temp.j(:'mkb')->>'line'),
  :'mka' not like '%"err"%' and :'mkb' not like '%"err"%' and pg_temp.j(:'mka')->>'line' = '20@9.99|-' and pg_temp.j(:'mkb')->>'line' = '20@9.99|5' and pg_temp.st(:'ilb'::uuid) like 'paid=9.49 ret=0 returnable=20 adjustable=20 adj_open=0 tiers=20@9.49p adjs=0',
  format('a %s | b %s | st_b %s', left(:'mka', 200), left(:'mkb', 200), pg_temp.st(:'ilb'::uuid)));

\echo '── T1) A: 12 개를 7.99 로 조정 → 24.00 + 3.12 · 원장 0 · 반품 가능 20 · 조정 가능 8 · 계정 = 인보이스 줄 · 경고 reason_not_price_adjustment(사유 customer_return)'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', :'inva', 'reason', 'customer_return', 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'ila', 'qty', 12, 'new_unit_price', 7.99)))::text)) as t1 \gset
reset role;
select coalesce(pg_temp.j(:'t1')->>'credit_id', '00000000-0000-0000-0000-000000000000') as cr_t1 \gset
select pg_temp.chk(format('T1 trace %s · state %s', pg_temp.cr_trace(:'cr_t1'::uuid), pg_temp.st(:'ila'::uuid)),
  :'t1' not like 'ERR%' and pg_temp.cr_trace(:'cr_t1'::uuid) = 'cr[issued|customer_return|24|0|0|0|3.12|27.12] lines[price_adjustment|-|12|9.99|7.99|2|24|3.12|-] ledger=0 layers=0'
  and pg_temp.st(:'ila'::uuid) = 'paid=9.99 ret=0 returnable=20 adjustable=8 adj_open=12 tiers=8@9.99p,12@7.99 adjs=1'
  and (pg_temp.j(:'t1')->'warnings') ? 'reason_not_price_adjustment' and pg_temp.j(:'t1')->'lines'->0->>'description' = 'Price adjustment 9.99 → 7.99 — CRN2 Product',
  left(:'t1', 700));

\echo '── T2) A: 5 개 반품 → 5 × 7.99 = 39.95(조정 몫부터) · 남은 조정 몫 7'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', :'inva', 'reason', 'customer_return', 'warehouse_id', :'wh', 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', :'ila', 'qty_returned', 5, 'restock_bin', :'bina')))::text)) as t2 \gset
reset role;
select coalesce(pg_temp.j(:'t2')->>'credit_id', '00000000-0000-0000-0000-000000000000') as cr_t2 \gset
select pg_temp.chk(format('T2 trace %s · state %s', pg_temp.cr_trace(:'cr_t2'::uuid), pg_temp.st(:'ila'::uuid)),
  :'t2' not like 'ERR%' and pg_temp.cr_trace(:'cr_t2'::uuid) like 'cr[issued|customer_return|39.95|0|0|0|5.19|45.14] lines[product|5|-|-|-|7.99|39.95|5.19|-] ledger=1 layers=%'
  and pg_temp.st(:'ila'::uuid) = 'paid=9.99 ret=5 returnable=15 adjustable=8 adj_open=7 tiers=8@9.99p,7@7.99 adjs=1' and pg_temp.j(:'t2')->'lines'->0->>'description' like '% (5 × 7.99)',
  left(:'t2', 700));

\echo '── T3) A: 10 개 더 반품 → 7 × 7.99 + 3 × 9.99 = 85.90'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', :'inva', 'reason', 'customer_return', 'warehouse_id', :'wh', 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', :'ila', 'qty_returned', 10, 'restock_bin', :'bina')))::text)) as t3 \gset
reset role;
select coalesce(pg_temp.j(:'t3')->>'credit_id', '00000000-0000-0000-0000-000000000000') as cr_t3 \gset
select pg_temp.chk(format('T3 trace %s · state %s', pg_temp.cr_trace(:'cr_t3'::uuid), pg_temp.st(:'ila'::uuid)),
  :'t3' not like 'ERR%' and pg_temp.cr_trace(:'cr_t3'::uuid) like 'cr[issued|customer_return|85.9|0|0|0|11.17|97.07] lines[product|10|-|-|-|8.59|85.9|11.17|-] ledger=1 layers=%'
  and pg_temp.st(:'ila'::uuid) = 'paid=9.99 ret=15 returnable=5 adjustable=5 adj_open=0 tiers=5@9.99p adjs=1' and pg_temp.j(:'t3')->'lines'->0->>'description' like '% (7 × 7.99 + 3 × 9.99)',
  left(:'t3', 700));

\echo '── T4) A: 남은 5 개 반품 → 49.95 · 총 환급 24.00 + 39.95 + 85.90 + 49.95 = 199.80 = 20 × 9.99'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', :'inva', 'reason', 'customer_return', 'warehouse_id', :'wh', 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', :'ila', 'qty_returned', 5, 'restock_bin', :'bina')))::text)) as t4 \gset
reset role;
select coalesce(pg_temp.j(:'t4')->>'credit_id', '00000000-0000-0000-0000-000000000000') as cr_t4 \gset
select (select trim_scale(sum(c.lines_amount)) from public.so_credit c where c.invoice_id = :'inva'::uuid and c.status = 'issued') as t4_sum \gset
select pg_temp.chk(format('T4 trace %s · Σ lines_amount over A = %s · state %s', pg_temp.cr_trace(:'cr_t4'::uuid), :'t4_sum', pg_temp.st(:'ila'::uuid)),
  :'t4' not like 'ERR%' and pg_temp.cr_trace(:'cr_t4'::uuid) like 'cr[issued|customer_return|49.95|0|0|0|6.49|56.44] lines[product|5|-|-|-|9.99|49.95|6.49|-] ledger=1 layers=%'
  and :'t4_sum' = '199.8' and pg_temp.st(:'ila'::uuid) = 'paid=9.99 ret=20 returnable=0 adjustable=0 adj_open=0 tiers= adjs=1',
  left(:'t4', 400));

\echo '── T5 · T12) B(5%): 12 개를 7.99 로 · 사유 price_adjustment → 낸 단가 9.49 · 1.50 × 12 = 18.00 · 거울 없음 · 문서 제품 표 「Price adjustment 9.49 → 7.99 — …」 · 수량 12 · 단가 1.50 · 금액 18.00 · charges 없음'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', :'invb', 'reason', 'price_adjustment', 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'ilb', 'qty', 12, 'new_unit_price', 7.99)))::text)) as t5 \gset
reset role;
select coalesce(pg_temp.j(:'t5')->>'credit_id', '00000000-0000-0000-0000-000000000000') as cr_t5 \gset
set local role authenticated;
select pg_temp.as_user(:'m', format('select (public.doc_data(''credit_note'', %L::jsonb)->''docs''->0)::text', json_build_object('credit_id', :'cr_t5')::text)) as t5_doc \gset
reset role;
select pg_temp.chk(format('T5 · T12 trace %s · state %s · doc lines[0] %s · charges %s', pg_temp.cr_trace(:'cr_t5'::uuid), pg_temp.st(:'ilb'::uuid), pg_temp.j(:'t5_doc')->'lines'->0, pg_temp.j(:'t5_doc')->'charges'),
  :'t5' not like 'ERR%' and pg_temp.cr_trace(:'cr_t5'::uuid) = 'cr[issued|price_adjustment|18|0|0|0|2.34|20.34] lines[price_adjustment|-|12|9.49|7.99|1.5|18|2.34|-] ledger=0 layers=0'
  and pg_temp.st(:'ilb'::uuid) = 'paid=9.49 ret=0 returnable=20 adjustable=8 adj_open=12 tiers=8@9.49p,12@7.99 adjs=1'
  and not ((pg_temp.j(:'t5')->'warnings') ? 'reason_not_price_adjustment') and :'t5_doc' not like 'ERR%'
  and pg_temp.j(:'t5_doc')->'lines'->0->>'description' = 'Price adjustment 9.49 → 7.99 — CRN2 Product' and pg_temp.j(:'t5_doc')->'lines'->0->>'qty' = '12' and pg_temp.j(:'t5_doc')->'lines'->0->>'unit_price' = '1.50' and pg_temp.j(:'t5_doc')->'lines'->0->>'amount' = '18.00'
  and jsonb_array_length(pg_temp.j(:'t5_doc')->'charges') = 0 and pg_temp.j(:'t5_doc')->'totals'->>'total' = '20.34',
  format('t5 %s | doc %s', left(:'t5', 500), left(:'t5_doc', 600)));

\echo '── T6) B: 1 개 반품 → 순 환급 7.99 + 1.04(제품 줄 7.99 · 오더 할인 거울 0 — 조정된 몫은 거울 기준 밖)'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', :'invb', 'reason', 'customer_return', 'warehouse_id', :'wh', 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', :'ilb', 'qty_returned', 1, 'restock_bin', :'bina')))::text)) as t6 \gset
reset role;
select coalesce(pg_temp.j(:'t6')->>'credit_id', '00000000-0000-0000-0000-000000000000') as cr_t6 \gset
select pg_temp.chk(format('T6 trace %s · state %s', pg_temp.cr_trace(:'cr_t6'::uuid), pg_temp.st(:'ilb'::uuid)),
  :'t6' not like 'ERR%' and pg_temp.cr_trace(:'cr_t6'::uuid) like 'cr[issued|customer_return|7.99|0|0|0|1.04|9.03] lines[product|1|-|-|-|7.99|7.99|1.04|-,order_discount|-|-|-|-|-|0|0|%] ledger=1 layers=%'
  and pg_temp.st(:'ilb'::uuid) = 'paid=9.49 ret=1 returnable=19 adjustable=8 adj_open=11 tiers=8@9.49p,11@7.99 adjs=1',
  left(:'t6', 700));

\echo '── T7) B: 두 번째 조정 7.99 → 6.99 · 5 개 → 실효 단가 7.99 기준 1.00 × 5 · 층 8@9.49 · 6@7.99 · 5@6.99 · 그 뒤 2 개 반품 → 6.99 층부터(2 × 6.99 = 13.98)'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', :'invb', 'reason', 'price_adjustment', 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'ilb', 'qty', 5, 'new_unit_price', 6.99)))::text)) as t7 \gset
reset role;
select coalesce(pg_temp.j(:'t7')->>'credit_id', '00000000-0000-0000-0000-000000000000') as cr_t7 \gset
select pg_temp.st(:'ilb'::uuid) as t7_st \gset
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', :'invb', 'reason', 'customer_return', 'warehouse_id', :'wh', 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', :'ilb', 'qty_returned', 2, 'restock_bin', :'bina')))::text)) as t7_ret \gset
reset role;
select pg_temp.chk(format('T7 trace %s · state %s · preview return 2 → %s', pg_temp.cr_trace(:'cr_t7'::uuid), :'t7_st', pg_temp.j(:'t7_ret')->'lines'->0->>'amount'),
  :'t7' not like 'ERR%' and pg_temp.cr_trace(:'cr_t7'::uuid) = 'cr[issued|price_adjustment|5|0|0|0|0.65|5.65] lines[price_adjustment|-|5|7.99|6.99|1|5|0.65|-] ledger=0 layers=0'
  and :'t7_st' = 'paid=9.49 ret=1 returnable=19 adjustable=8 adj_open=11 tiers=8@9.49p,6@7.99,5@6.99 adjs=2'
  and :'t7_ret' not like 'ERR%' and (pg_temp.j(:'t7_ret')->'lines'->0->>'amount')::numeric = 13.98 and pg_temp.j(:'t7_ret')->'lines'->0->>'description' like '% (2 × 6.99)',
  format('t7 %s | ret %s', left(:'t7', 400), left(:'t7_ret', 500)));

\echo '── T8) 거부 — 새 단가 ≥ 실효 단가(9.49 on B) · 조정 수량 > 그 층(10 @ 7.00 — 7.99 층은 6) · 다 반품된 줄(A) · 새 단가 0 · worker 발행 · 콤보가 아닌 줄의 invoice 짝 틀림'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', :'invb', 'reason', 'price_adjustment', 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'ilb', 'qty', 1, 'new_unit_price', 9.49)))::text)) as t8_a \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', :'invb', 'reason', 'price_adjustment', 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'ilb', 'qty', 10, 'new_unit_price', 7.00)))::text)) as t8_b \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', :'inva', 'reason', 'price_adjustment', 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'ila', 'qty', 1, 'new_unit_price', 5)))::text)) as t8_c \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', :'invb', 'reason', 'price_adjustment', 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'ilb', 'qty', 1, 'new_unit_price', 0)))::text)) as t8_d \gset
select pg_temp.as_user(:'w', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', :'invb', 'reason', 'price_adjustment', 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'ilb', 'qty', 1, 'new_unit_price', 5)))::text)) as t8_e \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', :'invb', 'reason', 'price_adjustment', 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'ila', 'qty', 1, 'new_unit_price', 5)))::text)) as t8_f \gset
reset role;
select pg_temp.chk('T8 refusals: 9.49 on B → "not below the current unit price 6.99" · 10 @ 7.00 → "only 6 can be adjusted at 7.99 — split" · all returned (A) → "nothing left to adjust" · 0 → "above 0" · worker → manager · line of another invoice → "not a product line of invoice"',
  :'t8_a' like 'ERR%' and :'t8_a' like '%not below the current unit price 6.99%' and :'t8_b' like 'ERR%' and :'t8_b' like '%only 6 can be adjusted at 7.99%' and :'t8_c' like 'ERR%' and :'t8_c' like '%nothing left to adjust%'
  and :'t8_d' like 'ERR%' and :'t8_d' like '%above 0%' and :'t8_e' like 'ERR%' and :'t8_e' like '%manager or above%' and :'t8_f' like 'ERR%' and :'t8_f' like '%not a product line of invoice%',
  format('a %s | b %s | c %s | d %s | e %s | f %s', left(:'t8_a', 160), left(:'t8_b', 200), left(:'t8_c', 160), left(:'t8_d', 160), left(:'t8_e', 120), left(:'t8_f', 160)));

\echo '── T9) 참조 크레딧 가격 조정 — paid 9.99 · new 7.99 · 12 → 24.00 + 13% · manual_unit_price · 계정 _98_ · new ≥ paid 거부'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'cust', 'reason', 'price_adjustment', 'tax_rule', :'r13_name', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-9'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'sku', 'CRN2-P', 'qty', 12, 'paid_unit_price', 9.99, 'new_unit_price', 7.99)))::text)) as t9 \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'cust', 'reason', 'price_adjustment', 'tax_rule', :'r13_name', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-9'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'sku', 'CRN2-P', 'qty', 12, 'paid_unit_price', 7.99, 'new_unit_price', 7.99)))::text)) as t9_r \gset
reset role;
select pg_temp.chk('T9 reference adjustment preview: line price_adjustment 12 · 9.99 → 7.99 · 24.00 + 3.12 · account _98_ · warnings ∋ manual_unit_price · new = paid refused',
  :'t9' not like 'ERR%' and pg_temp.j(:'t9')->'lines'->0->>'kind' = 'price_adjustment' and (pg_temp.j(:'t9')->'lines'->0->>'amount')::numeric = 24 and (pg_temp.j(:'t9')->'lines'->0->>'tax_amount')::numeric = 3.12
  and pg_temp.j(:'t9')->'lines'->0->>'account_code' = '_98_' and (pg_temp.j(:'t9')->'totals'->>'total')::numeric = 27.12 and (pg_temp.j(:'t9')->'warnings') ? 'manual_unit_price'
  and :'t9_r' like 'ERR%' and :'t9_r' like '%not below the paid unit price%',
  format('t9 %s | r %s', left(:'t9', 500), left(:'t9_r', 160)));

\echo '── T10) 섞이지 않음 — T1 · T5 · T7 크레딧: 줄 하나뿐(거울 · surcharge · 운임 할인 없음) · 원장 0 · 레이어 0 · 피 미리 보기(pct 20) 의 기준 0 → 0'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', :'invb', 'reason', 'price_adjustment', 'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'ilb', 'qty', 1, 'new_unit_price', 5), jsonb_build_object('kind', 'restocking_fee', 'pct', 20, 'account_id', (select id from public.ref_account where code = '_98_'))))::text)) as t10 \gset
reset role;
select pg_temp.chk('T10 adjustment-only credits have exactly one line each · ledger 0 · layers 0 · a restocking fee on an adjustment-only preview is 0 (base excludes adjustments)',
  (select count(*) from public.so_credit_line l where l.credit_id in (:'cr_t1'::uuid, :'cr_t5'::uuid, :'cr_t7'::uuid)) = 3
  and (select count(*) from public.inv_ledger g join public.so_credit c on c.credit_number = g.doc_number where c.id in (:'cr_t1'::uuid, :'cr_t5'::uuid, :'cr_t7'::uuid)) = 0
  and :'t10' not like 'ERR%' and (pg_temp.j(:'t10')->'totals'->>'fee_amount')::numeric = 0 and (pg_temp.j(:'t10')->'totals'->>'order_discount_amount')::numeric = 0 and (pg_temp.j(:'t10')->'totals'->>'surcharge_amount')::numeric = 0,
  left(:'t10', 500));

\echo '── T11) 취소 — T5(앞 조정 · 뒤에 T6 · T7 이 있다) 취소 → 거부 · T7(마지막) 취소 → OK · 층이 6.99 없이 되돌아온다(11@7.99) · 조정 가능 8 그대로'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_cancel(%L::uuid, ''crn-2 T11 a'')::text', :'cr_t5')) as t11_a \gset
select pg_temp.as_user(:'m', format('select public.so_credit_cancel(%L::uuid, ''crn-2 T11 b'')::text', :'cr_t7')) as t11_b \gset
reset role;
select pg_temp.chk(format('T11 cancel T5 refused (later credits priced on it) · cancel T7 OK · state %s', pg_temp.st(:'ilb'::uuid)),
  :'t11_a' like 'ERR%' and :'t11_a' like '%later credit notes%' and :'t11_b' not like 'ERR%' and pg_temp.j(:'t11_b')->>'status' = 'cancelled'
  and pg_temp.st(:'ilb'::uuid) = 'paid=9.49 ret=1 returnable=19 adjustable=8 adj_open=11 tiers=8@9.49p,11@7.99 adjs=1',
  format('a %s | b %s', left(:'t11_a', 200), left(:'t11_b', 200)));

\echo '── T12b) 준비 창구 — B 줄의 adjust{paid_unit_price · qty_adjustable · qty_adjusted_open · tiers · adjustments} · vocab 에 price_adjustment · qty_credited · qty_returnable 그대로'
set local role authenticated;
select pg_temp.as_user(:'m', format('select (public.so_credit_prepare(%L::uuid))::text', :'invb')) as t12 \gset
reset role;
select pg_temp.chk('T12b prepare: lines[0].adjust paid 9.49 · adjustable 8 · adjusted_open 11 · tiers 2 · adjustments 1 · qty_credited 1 · qty_returnable 19 · vocab reasons ∋ price_adjustment · line_kinds ∋ price_adjustment',
  :'t12' not like 'ERR%' and (pg_temp.j(:'t12')->'lines'->0->'adjust'->>'paid_unit_price')::numeric = 9.49 and (pg_temp.j(:'t12')->'lines'->0->'adjust'->>'qty_adjustable')::numeric = 8 and (pg_temp.j(:'t12')->'lines'->0->'adjust'->>'qty_adjusted_open')::numeric = 11
  and jsonb_array_length(pg_temp.j(:'t12')->'lines'->0->'adjust'->'tiers') = 2 and jsonb_array_length(pg_temp.j(:'t12')->'lines'->0->'adjust'->'adjustments') = 1
  and (pg_temp.j(:'t12')->'lines'->0->>'qty_credited')::numeric = 1 and (pg_temp.j(:'t12')->'lines'->0->>'qty_returnable')::numeric = 19
  and (pg_temp.j(:'t12')->'vocab'->'reasons') ? 'price_adjustment' and (pg_temp.j(:'t12')->'vocab'->'line_kinds') ? 'price_adjustment',
  left(:'t12', 900));
\else
select pg_temp.chk('G1 ~ T12 skipped: crn-2 not landed', false, pg_temp.gate_state());
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real rows untouched (credits · credit lines · invoices · ledger · untouched function md5)', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 셋 되돌리기'
select (select count(*) from public.customer where name like 'CRN2 %') + (select count(*) from public.product where sku like 'CRN2-%') + (select count(*) from public.ims_staff where email like 'crn2-%') + (select count(*) from public.inv_ledger where sku like 'CRN2-%') + (select count(*) from public.inv_layer where sku like 'CRN2-%') as fake_traces_left;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
select setval('public.so_credit_number_seq', greatest(coalesce((select max(substring(credit_number from '[0-9]+')::bigint) from public.so_credit), 0), :cr_seq_last), :'cr_seq_called'::boolean) as so_credit_number_seq_reset_to;
select (select last_value || '|' || is_called from public.so_number_seq) as so_seq_after, (select last_value || '|' || is_called from public.so_invoice_number_seq) as inv_seq_after, (select last_value || '|' || is_called from public.so_credit_number_seq) as cr_seq_after;
