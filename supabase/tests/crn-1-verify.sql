-- crn-1-verify.sql — 인보이스 없는 크레딧(참조 번호 크레딧) 손질(판정 602 · 609 · 610):
--   ① 인보이스 크레딧 동일성(I1 — 물건 오더 Ship & invoice → 반품 2 재입고 + 운임 50 · 미리 보기 · 발행 · 상세 · 문서 · 원장 raw · 레이어 return_restore — \i 앞 · 뒤 같은 재료 · 다른 점은 열쇠 이름뿐)
--   ② 결함 판(S0 · 시험 전용 — 옛 열쇠 cin7 · 세금 규칙 필수 · 「Cin7」 글) · ③ 새 길(N1 ~ N8) · 무접촉(G0 · G1 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261021194405_crn_1_reference_credit.sql -f supabase/tests/crn-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · I1 셋은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 OK 수 − 2 · MISMATCH 0
--   가짜 재료는 전부 CRN1(손님 셋: ON 기본 배송지 · AB 기본 배송지 · 배송지 없음 · 제품 + 칸 재고 50 + 레이어 2.5 · 직원 둘: M sales manager · W sales worker) · 번호는 창구가 당긴다(so · so_invoice · so_credit 머리 → rollback 뒤 greatest)
--   ⚠️ 동일성은 pg_temp.scn 이 서브트랜잭션 안에서 재료를 만들고 끝까지 돌린 뒤 결과를 예외 메시지로 꺼내고 되감는다(쓰기 0) · 번호 · uuid · 시각 · 숫자 id 는 norm 으로 지운다 · 옛 열쇠 이름은 새 이름으로 바꿔 비교(그 차이가 전부여야 한다)

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261021194405' \gset
select :n_applied as schema_migrations_rows_for_20261021194405;
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
-- 옛 열쇠 이름 → 새 이름(동일성 비교용 · 이 셋이 유일한 차이여야 한다)
create function pg_temp.renm(p text) returns text language sql immutable as $$
  select replace(replace(replace(p, 'cin7_invoice_number', 'ref_invoice_number'), 'cin7_order_number', 'ref_order_number'), 'cin7_invoice_date', 'ref_invoice_date') $$;
create function pg_temp.canon(p text) returns text language sql immutable as $$ select (pg_temp.norm(pg_temp.renm(p))::jsonb)::text $$;
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 크레딧 자취 — 머리 · 줄 · 원장(raw.header 열쇠 · cost_source) · 레이어
create function pg_temp.cr_trace(p_cr uuid) returns text language sql security definer as $$
  select 'cr[' || c.status || '|' || trim_scale(c.lines_amount) || '|' || trim_scale(c.tax_amount) || '|' || trim_scale(c.total) || '|' || c.warehouse_name || '|' || coalesce(c.tax_rule, '-') || '|' || (c.invoice_id is not null) || ']'
      || ' lines[' || coalesce((select string_agg(l.kind || '|' || coalesce(trim_scale(l.qty_returned)::text, '-') || '|' || coalesce(trim_scale(l.unit_price)::text, '-') || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount) || '|' || coalesce(l.restock_bin, '-') || '|' || coalesce(l.account_code, '-'), ',' order by l.line_no) from public.so_credit_line l where l.credit_id = c.id), '-') || ']'
      || ' ledger[' || coalesce((select string_agg(trim_scale(g.qty_delta) || '|' || g.bin || '|' || (select string_agg(replace(k, 'cin7_', 'ref_'), '+' order by replace(k, 'cin7_', 'ref_')) from jsonb_object_keys(g.raw->'header') k) || '|' || coalesce(g.raw->'header'->>'order_number', '-') || '|' || coalesce(g.raw->'cost'->'remainder'->>'cost_source', 'traced'), ',' order by g.id) from public.inv_ledger g where g.doc_number = c.credit_number and g.source = 'ims'), '-') || ']'
      || ' layers[' || coalesce((select string_agg(trim_scale(y.qty) || '@' || trim_scale(y.unit_cost) || '|' || y.cost_source, ',' order by y.id) from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = c.credit_number), '-') || ']'
  from public.so_credit c where c.id = p_cr $$;
-- 동일성 한 경우(인보이스 크레딧) — 재료를 만들고 끝까지 돌린 뒤 되감는다
create function pg_temp.scn(p_claims text, p_cust uuid, p_pid uuid, p_wh uuid, p_bin text, p_rule uuid, p_rule_name text) returns jsonb language plpgsql as $$
declare v_so uuid; v_l uuid; v_x jsonb; v_inv uuid; v_ilp uuid; v_ilc uuid; v_p jsonb; v_prev jsonb; v_iss jsonb; v_cr uuid; v_det jsonb; v_doc jsonb;
begin
  begin
    perform set_config('request.jwt.claims', p_claims, true);
    v_x := public.so_create(p_cust, 'warehouse', 'manual', p_wh, 'crn-1 ident');  v_so := (v_x->>'id')::uuid;
    v_x := public.so_line_add(v_so, p_pid, 5, 9.00, null, null, null, false);  v_l := (v_x->'line'->>'id')::uuid;
    v_x := public.so_charge_set(p_so_id => v_so, p_name => 'Freight', p_amount => 50);
    execute 'set local session_replication_role = replica';
    update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
    execute 'set local session_replication_role = origin';
    v_x := public.so_confirm(v_so, null, false, true);
    execute 'set local session_replication_role = replica';
    update public.so set status = 'packed' where id = v_so and status = 'confirmed';
    execute 'set local session_replication_role = origin';
    v_x := public.so_finalize(jsonb_build_array(jsonb_build_object('so_id', v_so, 'picks', jsonb_build_array(jsonb_build_object('line_id', v_l, 'bin', p_bin, 'qty', 5)))), true, null);
    select i.id into v_inv from public.so_invoice i join public.so_invoice_order o on o.invoice_id = i.id where o.so_id = v_so and o.cancelled_at is null;
    select l.id into v_ilp from public.so_invoice_line l where l.invoice_id = v_inv and l.kind = 'product';
    select l.id into v_ilc from public.so_invoice_line l where l.invoice_id = v_inv and l.kind = 'charge';
    v_p := jsonb_build_object('invoice_id', v_inv, 'reason', 'customer_return', 'warehouse_id', p_wh,
                              'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', v_ilp, 'qty_returned', 2, 'restock_bin', p_bin), jsonb_build_object('kind', 'freight', 'so_invoice_line_id', v_ilc, 'amount', 50)));
    v_prev := public.so_credit_issue(v_p, false);
    v_iss := public.so_credit_issue(v_p, true);  v_cr := (v_iss->>'credit_id')::uuid;
    v_det := public.so_credit_detail(v_cr);
    v_doc := public.doc_data('credit_note', jsonb_build_object('credit_id', v_cr));
    raise exception using errcode = 'P7777', message = jsonb_build_object('prev', v_prev, 'iss', v_iss, 'det', v_det, 'doc', v_doc, 'trace', pg_temp.cr_trace(v_cr))::text;
  exception when sqlstate 'P7777' then
    return sqlerrm::jsonb;
  when others then
    return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
  end;
end $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'ref_cols=' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_credit' and column_name in ('ref_invoice_number', 'ref_order_number', 'ref_invoice_date'))::text
      || ' cin7_cols=' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_credit' and column_name like 'cin7%')::text
      || ' issue_ref=' || (select (p.prosrc ~ '''ref'' then' or p.prosrc ~ 'p->''ref''')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_issue')
      || ' post_no_trace=' || (select (p.prosrc ~ 's\.so_number as origin_sale')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_post_credit')
      || ' view_ref=' || (pg_get_viewdef('public.so_credit_list'::regclass) ~ 'ref_invoice_number')::text $$;
create function pg_temp.real_rows() returns text language sql security definer as $$
  select 'cr=' || (select count(*) || '/' || md5(coalesce(string_agg(c.id::text || c.status || c.total || coalesce(c.invoice_id::text, '-'), ',' order by c.id), '')) from public.so_credit c where c.customer_id not in (select id from public.customer where name like 'CRN1 %'))
      || ' crl=' || (select count(*) from public.so_credit_line l join public.so_credit c on c.id = l.credit_id where c.customer_id not in (select id from public.customer where name like 'CRN1 %'))
      || ' inv=' || (select count(*) from public.so_invoice i where i.bill_to_customer_id not in (select id from public.customer where name like 'CRN1 %'))
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where sku not like 'CRN1-%')
      || ' layers=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_layer where sku not like 'CRN1-%')
      || ' fns=' || (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('so_credit_prepare', 'so_credit_cancel', 'so_credit_detail', 'so_credit_attach', 'so_credit_detach', 'so_credit_alloc_add', 'so_credit_remaining', 'so_customer_balance', 'inv_layer_post_credit', 'inv_layer_apply_credit', 'so_detail', 'doc_data', 'so_tax_rule_for')) $$;

\echo '── M0) 가짜 직원 둘(M sales manager · W sales worker) · 손님 셋(ON · AB 기본 배송지 · 없음) · 제품 + 칸 재고 50 + 레이어 50 @ 2.5 · 세율 · 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'crn1-m@test.invalid', 'CRN1 M', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as m_uid, id::text as m_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'crn1-w@test.invalid', 'CRN1 W', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as w_uid \gset
\set m '{"sub":"' :m_uid '","role":"authenticated"}'
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.name as bina from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as r13, name as r13_name, rate_pct as r13_rate from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('CRN1 Customer ON', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as c_on \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('CRN1 Customer AB', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as c_ab \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('CRN1 Customer NOADDR', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as c_no \gset
insert into public.customer_address (customer_id, type, is_default_for_type, line1, city, state_province, postal_code, country, source, is_active) values (:'c_on'::uuid, 'Shipping', true, '1 Test St', 'Toronto', 'ON', 'M1M 1M1', 'Canada', 'manual', true);
insert into public.customer_address (customer_id, type, is_default_for_type, line1, city, state_province, postal_code, country, source, is_active) values (:'c_ab'::uuid, 'Shipping', true, '2 Test Ave', 'Calgary', 'Alberta', 'T1T 1T1', 'Canada', 'manual', true);
insert into public.product (sku, name, source) values ('CRN1-P', 'CRN1 Product', 'manual') returning id::text as pid \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values (public.ims_today() - 3, 1, 'CRN1-P', :'whname', :'bina', 50, 'po_in', 'purchase', 'PO-CRN1', 'crn1-1', 'manual');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values ('CRN1-P', :'whname', 'purchase', 'PO-CRN1', 'crn1-1', public.ims_today() - 3, true, 50, 2.5, 'po_line');
set local session_replication_role = origin;
select pg_temp.real_rows() as real_before, pg_temp.gate_state() as gate_before \gset
select pg_temp.chk(format('M0 staff ×2 · customers ON / AB / none · product CRN1-P stock 50 in %s · layer 50 @ 2.5 · tax %s %s%% · snapshots taken', :'bina', :'r13_name', trim_scale(:'r13_rate'::numeric)),
  :'m_uid' <> '' and :'c_on' <> '' and :'c_ab' <> '' and :'c_no' <> '' and :'pid' <> '' and :'r13' <> '' and :'real_before' <> '', 'see M0');

create temp table t_ident (phase text, prev text, iss text, det text, doc text, trace text, err text);

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — 옛 열쇠 cin7 이 통하고 세금 규칙은 필수(「A Cin7 credit needs tax_rule」) · ref 열쇠는 거부 · 칸 이름 cin7_*'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_on', 'reason', 'customer_return', 'cin7', jsonb_build_object('invoice_number', 'INV-OLD-1'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 2, 'unit_price', 9.99, 'not_restocked_reason', 'not_returned')))::text)) as s0_notax \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_on', 'reason', 'customer_return', 'tax_rule', :'r13_name', 'cin7', jsonb_build_object('invoice_number', 'INV-OLD-1'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 2, 'unit_price', 9.99, 'not_restocked_reason', 'not_returned')))::text)) as s0_old \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_on', 'reason', 'customer_return', 'tax_rule', :'r13_name', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-1'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 2, 'unit_price', 9.99, 'not_restocked_reason', 'not_returned')))::text)) as s0_ref \gset
reset role;
select pg_temp.chk('S0 before the trial: cin7 key without tax_rule → "A Cin7 credit needs tax_rule" · with tax_rule → preview with origin.cin7_invoice_number · ref key → refused ("or cin7 {…}") · columns cin7_* · not in schema_migrations',
  :'s0_notax' like 'ERR%' and :'s0_notax' like '%A Cin7 credit needs tax_rule%' and :'s0_old' not like 'ERR%' and pg_temp.j(:'s0_old')->'origin'->>'cin7_invoice_number' = 'INV-OLD-1'
  and :'s0_ref' like 'ERR%' and :'s0_ref' like '%or cin7 {%' and :'gate_before' = 'ref_cols=0 cin7_cols=3 issue_ref=false post_no_trace=false view_ref=false' and :n_applied = 0,
  format('notax %s | old %s | ref %s | gate %s', left(:'s0_notax', 160), left(:'s0_old', 200), left(:'s0_ref', 160), :'gate_before'));
\echo '── I0) 동일성 — 옛 판으로 인보이스 크레딧 한 경우(되감김)'
insert into t_ident select 'old', pg_temp.canon((v->'prev')::text), pg_temp.canon((v->'iss')::text), pg_temp.canon((v->'det')::text), pg_temp.canon((v->'doc')::text), pg_temp.norm(pg_temp.renm(v->>'trace')), v->>'err'
  from (select pg_temp.scn(:'m', :'c_on'::uuid, :'pid'::uuid, :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name') as v) x;
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: untouched credit · ledger · doc · tax functions same md5 · real credits · invoices · ledger · layers unchanged', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));
\echo '── I1) 동일성 — 새 판으로 같은 경우 · 비교(옛 열쇠 이름을 새 이름으로 바꾼 뒤 같아야 한다)'
insert into t_ident select 'new', pg_temp.canon((v->'prev')::text), pg_temp.canon((v->'iss')::text), pg_temp.canon((v->'det')::text), pg_temp.canon((v->'doc')::text), pg_temp.norm(pg_temp.renm(v->>'trace')), v->>'err'
  from (select pg_temp.scn(:'m', :'c_on'::uuid, :'pid'::uuid, :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name') as v) x;
select (o.prev = n.prev) as same_prev, (o.iss = n.iss) as same_iss, ((o.det::jsonb #- '{credit_row,search_text}') = (n.det::jsonb #- '{credit_row,search_text}')) as same_det, (o.doc = n.doc) as same_doc, (o.trace = n.trace) as same_trace,
       (o.det::jsonb #>> '{credit_row,search_text}') as old_st, (n.det::jsonb #>> '{credit_row,search_text}') as new_st, coalesce(o.err, '-') as old_err, coalesce(n.err, '-') as new_err, o.trace as old_trace, n.trace as new_trace,
       (o.det like '%ref_invoice_number%') as det_has_ref, (o.trace like '%ref_invoice_number%') as trace_has_ref,
       coalesce((select string_agg(coalesce(a.k, b.k) || ': ' || left(coalesce(a.v::text, '∅'), 300) || ' ≠ ' || left(coalesce(b.v::text, '∅'), 300), ' || ') from jsonb_each(o.det::jsonb) a(k, v) full join jsonb_each(n.det::jsonb) b(k, v) on b.k = a.k where a.v is distinct from b.v), '-') as det_diff
  from t_ident o join t_ident n on n.phase = 'new' where o.phase = 'old' \gset
select pg_temp.chk('I1 invoice credit: preview · issue · detail · credit_note doc · trace (lines · ledger raw.header keys · origin · cost_source · return_restore layers) identical after renaming the three keys (credit_row.search_text set aside — it carries the new invoice number) · both ran without error · the raw.header/detail did carry the renamed key',
  :'same_prev' = 't' and :'same_iss' = 't' and :'same_det' = 't' and :'same_doc' = 't' and :'same_trace' = 't' and :'old_err' = '-' and :'new_err' = '-' and :'det_has_ref' = 't' and :'trace_has_ref' = 't' and :'old_trace' like '%return_restore%',
  format('prev %s | iss %s | det %s | doc %s | trace %s | errs %s / %s | det_diff %s | search_text %s ≠ %s | old %s | new %s', :'same_prev', :'same_iss', :'same_det', :'same_doc', :'same_trace', :'old_err', :'new_err', :'det_diff', :'old_st', :'new_st', left(:'old_trace', 300), left(:'new_trace', 300)));
\else
select pg_temp.chk('P0c confirm run: migration 20261021194405 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() = 'ref_cols=3 cin7_cols=0 issue_ref=true post_no_trace=true view_ref=true') as landed \gset
\if :landed
\echo '── G1) 실물'
select pg_temp.chk('G1 so_credit.ref_* ×3 · no cin7_* · so_credit_origin_ck on ref_invoice_number · so_credit_list has ref_invoice_number · ref_order_number · issue takes ref · post does not trace · ACLs (issue authenticated yes · anon no)',
  pg_temp.gate_state() = 'ref_cols=3 cin7_cols=0 issue_ref=true post_no_trace=true view_ref=true'
  and (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so_credit'::regclass and conname = 'so_credit_origin_ck') ~ 'ref_invoice_number'
  and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_credit_list' and column_name in ('ref_invoice_number', 'ref_order_number')) = 2
  and has_function_privilege('authenticated', 'public.so_credit_issue(jsonb, boolean)', 'execute') and not has_function_privilege('anon', 'public.so_credit_issue(jsonb, boolean)', 'execute')
  and has_table_privilege('authenticated', 'public.so_credit_list', 'select'), pg_temp.gate_state());

\echo '── N1) ON 손님 · tax_rule 안 보냄 → HST ON 13% 제안(ship_to) · 경고 manual_unit_price · origin.ref_* · 9.99 × 2 = 19.98 + 2.60 · cost_estimate null · reference_seen 없음'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-1', 'order_number', 'SO-OLD-1', 'invoice_date', (public.ims_today() - 40)::text), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 2, 'unit_price', 9.99, 'restock_bin', :'bina')))::text)) as n1 \gset
reset role;
select pg_temp.chk('N1 ON customer · no tax_rule → origin.tax_rule HST ON (Sale) · rate 13 · tax_rule_source ship_to · ref_invoice_number INV-OLD-1 · ref_order_number SO-OLD-1 · totals 19.98 + 2.60 = 22.58 · warnings ∋ manual_unit_price · ∌ origin_sale_unknown · ∌ reference_seen · line cost_estimate null',
  :'n1' not like 'ERR%' and pg_temp.j(:'n1')->'origin'->>'tax_rule' = 'HST ON (Sale)' and (pg_temp.j(:'n1')->'origin'->>'rate_pct')::numeric = 13 and pg_temp.j(:'n1')->'origin'->>'tax_rule_source' = 'ship_to'
  and pg_temp.j(:'n1')->'origin'->>'ref_invoice_number' = 'INV-OLD-1' and pg_temp.j(:'n1')->'origin'->>'ref_order_number' = 'SO-OLD-1' and not (pg_temp.j(:'n1')->'origin' ? 'cin7_invoice_number')
  and (pg_temp.j(:'n1')->'totals'->>'lines_amount')::numeric = 19.98 and (pg_temp.j(:'n1')->'totals'->>'tax_amount')::numeric = 2.60 and (pg_temp.j(:'n1')->'totals'->>'total')::numeric = 22.58
  and (pg_temp.j(:'n1')->'warnings') ? 'manual_unit_price' and not ((pg_temp.j(:'n1')->'warnings') ? 'origin_sale_unknown') and not exists (select 1 from jsonb_array_elements_text(pg_temp.j(:'n1')->'warnings') w where w like 'reference_seen%')
  and pg_temp.j(:'n1')->'lines'->0->>'cost_estimate' is null and pg_temp.j(:'n1')->'lines'->0->>'restock_bin' = :'bina',
  left(:'n1', 900));

\echo '── N2) AB 손님(주 이름 Alberta 로 적힘) → GST (Sale) 5% · 배송지 없는 손님 → 거부 · tax_rule 보냄 → given · 옛 열쇠 cin7 → 거부 · 참조 번호 없음 → 거부 · 손님 없음 → 거부'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_ab', 'reason', 'damaged', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-2'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 1, 'unit_price', 20, 'not_restocked_reason', 'damaged')))::text)) as n2_ab \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_no', 'reason', 'damaged', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-3'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 1, 'unit_price', 20, 'not_restocked_reason', 'damaged')))::text)) as n2_none \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_no', 'reason', 'damaged', 'tax_rule', 'GST (Sale)', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-3'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 1, 'unit_price', 20, 'not_restocked_reason', 'damaged')))::text)) as n2_given \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_on', 'reason', 'damaged', 'cin7', jsonb_build_object('invoice_number', 'INV-OLD-1'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 1, 'unit_price', 20, 'not_restocked_reason', 'damaged')))::text)) as n2_cin7 \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_on', 'reason', 'damaged', 'ref', jsonb_build_object('invoice_number', '  '), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 1, 'unit_price', 20, 'not_restocked_reason', 'damaged')))::text)) as n2_noref \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', '00000000-0000-0000-0000-000000000001', 'reason', 'damaged', 'ref', jsonb_build_object('invoice_number', 'X'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 1, 'unit_price', 20, 'not_restocked_reason', 'damaged')))::text)) as n2_nocust \gset
reset role;
select pg_temp.chk('N2 AB → GST (Sale) 5% (ship_to · 20 + 1.00) · no default ship-to → "Pick a tax rule" · tax_rule given → given · old cin7 key → "The cin7 key is gone" · blank ref.invoice_number → refused · unknown customer → "Customer not found"',
  :'n2_ab' not like 'ERR%' and pg_temp.j(:'n2_ab')->'origin'->>'tax_rule' = 'GST (Sale)' and (pg_temp.j(:'n2_ab')->'origin'->>'rate_pct')::numeric = 5 and pg_temp.j(:'n2_ab')->'origin'->>'tax_rule_source' = 'ship_to' and (pg_temp.j(:'n2_ab')->'totals'->>'tax_amount')::numeric = 1.00
  and :'n2_none' like 'ERR%' and :'n2_none' like '%Pick a tax rule%no default ship-to%' and :'n2_given' not like 'ERR%' and pg_temp.j(:'n2_given')->'origin'->>'tax_rule_source' = 'given' and pg_temp.j(:'n2_given')->'origin'->>'tax_rule' = 'GST (Sale)'
  and :'n2_cin7' like 'ERR%' and :'n2_cin7' like '%The cin7 key is gone%' and :'n2_noref' like 'ERR%' and :'n2_noref' like '%needs ref.invoice_number%' and :'n2_nocust' like 'ERR%' and :'n2_nocust' like '%Customer not found%',
  format('ab %s | none %s | given %s | cin7 %s | noref %s | nocust %s', left(:'n2_ab', 300), left(:'n2_none', 160), left(:'n2_given', 200), left(:'n2_cin7', 160), left(:'n2_noref', 160), left(:'n2_nocust', 120)));

\echo '── N3) 발행(p_commit true · 시퀀스) — 원장 credit_in 2 EA · raw.header 열쇠 ref_invoice_number · order_number null · 레이어 cost_source layer_avg(되짚기 없음 · 2.5) · 경고에 origin_sale_unknown 없음 · untraced:layer_avg · 상세 열쇠 ref_* · credit_row · 목록 행 · 문서 invoice_number = 참조 번호'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-1', 'order_number', 'SO-OLD-1', 'invoice_date', (public.ims_today() - 40)::text), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 2, 'unit_price', 9.99, 'restock_bin', :'bina')))::text)) as n3 \gset
reset role;
select coalesce(pg_temp.j(:'n3')->>'credit_id', '00000000-0000-0000-0000-000000000000') as cr1, coalesce(pg_temp.j(:'n3')->>'credit_number', '?') as cr1_no \gset
select pg_temp.cr_trace(:'cr1'::uuid) as n3_trace \gset
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_detail(%L::uuid)::text', :'cr1')) as n3_det \gset
select pg_temp.as_user(:'m', format('select (public.doc_data(''credit_note'', %L::jsonb)->''docs''->0->''credit'')::text', json_build_object('credit_id', :'cr1')::text)) as n3_doc \gset
reset role;
select (select l.ref_invoice_number || '|' || coalesce(l.ref_order_number, '-') || '|' || coalesce(c.ref_invoice_date::text, '-') || '|' || coalesce(l.invoice_number, '-') from public.so_credit_list l join public.so_credit c on c.id = l.id where l.id = :'cr1'::uuid) as n3_list \gset
select pg_temp.chk(format('N3 issued %s: trace %s · detail credit.ref_invoice_number INV-OLD-1 · credit_row.ref_order_number SO-OLD-1 · no cin7 keys in detail · list row %s · doc credit.invoice_number INV-OLD-1 · warnings ∌ origin_sale_unknown · ∋ origin_sale_untraced:CRN1-P:layer_avg', :'cr1_no', :'n3_trace', :'n3_list'),
  :'n3' not like 'ERR%' and :'cr1_no' ~ '^CR-[0-9]{5}$' and :'n3_trace' like 'cr[issued|19.98|2.6|22.58|%|HST ON (Sale)|false] lines[product|2|9.99|19.98|2.6|%|_98_] ledger[2|%|credit_note_date+credit_note_number+invoice_id+order_number+ref_invoice_number|-|layer_avg] layers[2@2.5|layer_avg]'
  and :'n3_det' not like 'ERR%' and pg_temp.j(:'n3_det')->'credit'->>'ref_invoice_number' = 'INV-OLD-1' and pg_temp.j(:'n3_det')->'credit_row'->>'ref_order_number' = 'SO-OLD-1' and :'n3_det' not like '%cin7_%'
  and :'n3_list' = format('INV-OLD-1|SO-OLD-1|%s|-', public.ims_today() - 40) and :'n3_doc' not like 'ERR%' and pg_temp.j(:'n3_doc')->>'invoice_number' = 'INV-OLD-1'
  and not exists (select 1 from jsonb_array_elements_text(pg_temp.j(:'n3')->'ledger'->'warnings') w where w like 'origin_sale_unknown%') and exists (select 1 from jsonb_array_elements_text(pg_temp.j(:'n3')->'ledger'->'warnings') w where w = 'origin_sale_untraced:CRN1-P:layer_avg'),
  format('n3 %s | det %s | doc %s', left(:'n3', 700), left(:'n3_det', 300), left(:'n3_doc', 200)));

\echo '── N4) 같은 손님 · 같은 참조 번호(대소문자 · 공백 다르게) · 같은 SKU 두 번째 미리 보기 → reference_seen:<CR> · 다른 SKU → 없음 · 다른 손님 → 없음'
set local session_replication_role = replica;
insert into public.product (sku, name, source) values ('CRN1-Q', 'CRN1 Product Q', 'manual');
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', '  inv-old-1 '), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'not_returned')))::text)) as n4_same \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-1'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-Q', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'not_returned')))::text)) as n4_other \gset
select pg_temp.as_user(:'m', format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('customer_id', :'c_ab', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-1'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'not_returned')))::text)) as n4_cust \gset
reset role;
select pg_temp.chk(format('N4 same customer · "  inv-old-1 " · CRN1-P → reference_seen:%s (not blocked) · other SKU → none · other customer → none', :'cr1_no'),
  :'n4_same' not like 'ERR%' and (pg_temp.j(:'n4_same')->'warnings') ? ('reference_seen:' || :'cr1_no') and :'n4_other' not like 'ERR%' and not exists (select 1 from jsonb_array_elements_text(pg_temp.j(:'n4_other')->'warnings') w where w like 'reference_seen%')
  and :'n4_cust' not like 'ERR%' and not exists (select 1 from jsonb_array_elements_text(pg_temp.j(:'n4_cust')->'warnings') w where w like 'reference_seen%'),
  format('same %s | other %s | cust %s', pg_temp.j(:'n4_same')->'warnings', pg_temp.j(:'n4_other')->'warnings', pg_temp.j(:'n4_cust')->'warnings'));

\echo '── N5) 붙이기 — ON 손님의 다음 IMS 인보이스(물건 오더 Ship & invoice)가 발행 순간 열린 참조 크레딧 22.58 을 자동으로 붙인다(ⓒ2 · invoice_id null 이어도) → 크레딧 남은 0 · 인보이스 남은 = 합계 − 22.58 · 상세 open_invoices 에 attached_from_this_credit 22.58 · 손 붙이기는 남은 0 이라 거부'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''crn-1 N5'')::text', :'c_on', :'wh')) as n5_so \gset
reset role;
select coalesce(pg_temp.j(:'n5_so')->>'id', '00000000-0000-0000-0000-000000000000') as so5 \gset
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_line_add(%L::uuid, %L::uuid, 3, 9.00, null, null, null, false)::text', :'so5', :'pid')) as n5_l \gset
reset role;
select coalesce(pg_temp.j(:'n5_l')->'line'->>'id', '00000000-0000-0000-0000-000000000000') as l5 \gset
set local session_replication_role = replica;
update public.so set tax_rule_id = :'r13'::uuid, tax_rule = :'r13_name', tax_rule_manual = true where id = :'so5'::uuid;
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_confirm(%L::uuid, null, false, true)::text', :'so5')) as n5_c \gset
reset role;
set local session_replication_role = replica;
update public.so set status = 'packed' where id = :'so5'::uuid and status = 'confirmed';
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_finalize(%L::jsonb, true, null)::text', json_build_array(json_build_object('so_id', :'so5', 'picks', json_build_array(json_build_object('line_id', :'l5', 'bin', :'bina', 'qty', 3))))::text)) as n5_f \gset
reset role;
select coalesce(pg_temp.j(:'n5_f')->'invoices'->0->>'invoice_id', '00000000-0000-0000-0000-000000000000') as inv5 \gset
select (select trim_scale(public.so_invoice_remaining(:'inv5'::uuid))) as n5_rem0 \gset
set local role authenticated;
select pg_temp.as_user(:'m', format('select (public.so_credit_detail(%L::uuid)->''open_invoices'')::text', :'cr1')) as n5_open \gset
select pg_temp.as_user(:'m', format('select public.so_credit_attach(%L::uuid, %L::jsonb)::text', :'cr1', json_build_array(json_build_object('invoice_id', :'inv5', 'amount', 22.58))::text)) as n5_att \gset
reset role;
select (select trim_scale(i.total) from public.so_invoice i where i.id = :'inv5'::uuid) as n5_total, (select trim_scale(public.so_credit_remaining(:'cr1'::uuid))) as n5_crrem, (select coalesce(string_agg(a.source || ':' || trim_scale(a.amount), ','), '-') from public.so_credit_alloc a where a.credit_id = :'cr1'::uuid and a.invoice_id = :'inv5'::uuid and a.voided_at is null) as n5_alloc \gset
select pg_temp.chk(format('N5 next invoice total %s · issue auto-applied the reference credit (alloc %s) · credit remaining %s · invoice remaining %s = total − 22.58 · open_invoices shows attached_from_this_credit 22.58 · manual attach refused (0.00 left)', :'n5_total', :'n5_alloc', :'n5_crrem', :'n5_rem0'),
  :'n5_f' not like 'ERR%' and :'inv5' <> '00000000-0000-0000-0000-000000000000' and :'n5_alloc' = 'auto:22.58' and :'n5_crrem'::numeric = 0 and :'n5_rem0'::numeric = :'n5_total'::numeric - 22.58
  and :'n5_open' not like 'ERR%' and exists (select 1 from jsonb_array_elements(pg_temp.j(:'n5_open')) i where i->>'invoice_id' = :'inv5' and (i->>'attached_from_this_credit')::numeric = 22.58)
  and :'n5_att' like 'ERR%' and :'n5_att' like '%has only 0.00 left%',
  format('f %s | open %s | att %s', left(:'n5_f', 200), left(:'n5_open', 300), left(:'n5_att', 300)));

\echo '── N6) 취소 — 붙인 것이 있으면 거부(so_credit_cancel 규칙 그대로) → 떼기(manager) → 취소 → 반대 credit_in(qty −2 · :reversal) · 상태 cancelled · 레이어 소진 reversal'
set local role authenticated;
select pg_temp.as_user(:'m', format('select public.so_credit_cancel(%L::uuid, ''crn-1 N6 try'')::text', :'cr1')) as n6_try \gset
select coalesce((select a.id::text from public.so_credit_alloc a where a.credit_id = :'cr1'::uuid and a.voided_at is null limit 1), '00000000-0000-0000-0000-000000000000') as al5 \gset
select pg_temp.as_user(:'m', format('select public.so_credit_detach(%L::uuid, ''crn-1 N6 detach'')::text', :'al5')) as n6_det \gset
select pg_temp.as_user(:'m', format('select public.so_credit_cancel(%L::uuid, ''crn-1 N6'')::text', :'cr1')) as n6_cancel \gset
reset role;
select pg_temp.cr_trace(:'cr1'::uuid) as n6_trace \gset
select pg_temp.chk('N6 cancel with a live allocation refused · detach → cancel OK · status cancelled · ledger has the reversal row (−2) · credit layer consumed by the reversal',
  :'n6_try' like 'ERR%' and :'n6_det' not like 'ERR%' and :'n6_cancel' not like 'ERR%' and :'n6_trace' like 'cr[cancelled|%' and :'n6_trace' like '%ledger[2|%,-2|%'
  and (select coalesce(sum(k.qty), 0) from public.inv_layer_consume k join public.inv_layer y on y.id = k.layer_id where y.origin_type = 'creditnote' and y.doc_number = :'cr1_no') = 2,
  format('try %s | det %s | cancel %s | trace %s', left(:'n6_try', 160), left(:'n6_det', 120), left(:'n6_cancel', 200), :'n6_trace'));

\echo '── N7) W(worker · sales): 미리 보기는 되고(문은 발행 때) 발행은 거부(manager)'
set local role authenticated;
select pg_temp.as_user(:'w', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('customer_id', :'c_on', 'reason', 'customer_return', 'ref', jsonb_build_object('invoice_number', 'INV-OLD-9'), 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', 'CRN1-P', 'qty_returned', 1, 'unit_price', 9.99, 'not_restocked_reason', 'not_returned')))::text)) as n7_w \gset
reset role;
select pg_temp.chk('N7 worker: issue refused (manager or above) — the gate is unchanged', :'n7_w' like 'ERR%' and :'n7_w' like '%manager or above%', left(:'n7_w', 200));
\else
select pg_temp.chk('G1 ~ N7 skipped: crn-1 not landed', false, pg_temp.gate_state());
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real rows untouched (credits · credit lines · invoices · ledger · layers · untouched function md5)', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 셋 되돌리기'
select (select count(*) from public.customer where name like 'CRN1 %') + (select count(*) from public.product where sku like 'CRN1-%') + (select count(*) from public.ims_staff where email like 'crn1-%') + (select count(*) from public.inv_ledger where sku like 'CRN1-%') + (select count(*) from public.inv_layer where sku like 'CRN1-%') as fake_traces_left;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
select setval('public.so_credit_number_seq', greatest(coalesce((select max(substring(credit_number from '[0-9]+')::bigint) from public.so_credit), 0), :cr_seq_last), :'cr_seq_called'::boolean) as so_credit_number_seq_reset_to;
select (select last_value || '|' || is_called from public.so_number_seq) as so_seq_after, (select last_value || '|' || is_called from public.so_invoice_number_seq) as inv_seq_after, (select last_value || '|' || is_called from public.so_credit_number_seq) as cr_seq_after;
