-- svc-1c-verify.sql — 서비스 인보이스 줄에 수량 · 단가 · 서비스 크레딧 · 판(판정 590 · 593 ~ 597):
--   ① 동일성(물건 길 셋 — A warehouse Ship & invoice(운임 50 · 할인 50%) → 취소 → 재발행 → 운임 크레딧 + 상품 크레딧(재입고) · B counter(운임 20) · C 물건 오더 둘 한 장 — \i 앞 · 뒤 같은 재료 · I1)
--   ② 결함 판(S0 · 시험 전용 — 서비스 줄이 금액만) · ③ 새 길(N1 · N4) · CHECK(N2) · ④ 크레딧(N3) · 무접촉(G0 · G1 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261021183044_svc_1c_service_invoice_lines.sql -f supabase/tests/svc-1c-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · I1 셋은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 OK 수 − 2 · MISMATCH 0
--   가짜 재료는 전부 SVC1C(손님 · 제품 + 칸 재고 · 서비스 둘 · 직원 S sales manager) · 번호는 창구가 당긴다(so_number_seq · so_invoice_number_seq · so_credit_number_seq 머리 → rollback 뒤 greatest)
--   ⚠️ 동일성의 각 경우는 pg_temp.scn 이 서브트랜잭션 안에서 재료를 만들고 끝까지 돌린 뒤 결과를 예외 메시지로 꺼내고 되감는다(쓰기 0) · 번호 · uuid · 시각 · 숫자 id 는 norm 으로 지운다 · doc_data 는 직원 신원이 있어야 읽힌다(claims)

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261021183044' \gset
select :n_applied as schema_migrations_rows_for_20261021183044;
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
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''),
           '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '#', 'g'),
           '"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]+"', '"T"', 'g'),
           'SO-[0-9]{5,}', 'SO-#', 'g'),
           '("(invoice_number|number|credit_number)": ")[A-Z-]*[0-9]+"', '\1#"', 'g'),
           'CR-[0-9]+', 'CR-#', 'g'),
           '("[a-z_]*id"): [0-9]+', '\1: 0', 'g') $$;
create function pg_temp.norm2(p text) returns text language sql immutable as $$ select regexp_replace(pg_temp.norm(p), '"printed_at": "[^"]*"', '"printed_at": "T"', 'g') $$;
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 인보이스 자취(줄 · 머리 · 문서 데이터) — 오더 묶음의 살아 있는 인보이스 전부
create function pg_temp.inv_trace(p_ids uuid[]) returns text language plpgsql as $$
declare v text := ''; i record;
begin
  for i in select distinct x.* from public.so_invoice x join public.so_invoice_order o on o.invoice_id = x.id where o.so_id = any(p_ids) order by x.invoice_number loop
    v := v || 'inv[' || i.status || '|' || trim_scale(i.lines_amount) || '|' || trim_scale(i.charges_amount) || '|' || trim_scale(i.charges_discount_amount) || '|' || trim_scale(i.tax_amount) || '|' || trim_scale(i.total) || '|' || (i.due_on - i.issued_on) || '] lines['
      || coalesce((select string_agg(l.kind || '|' || coalesce(trim_scale(l.qty)::text, '-') || '|' || coalesce(trim_scale(l.unit_price)::text, '-') || '|' || coalesce(trim_scale(l.discount_pct)::text, '-') || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount) || '|' || coalesce(l.account_code, '-'), ',' order by l.line_no) from public.so_invoice_line l where l.invoice_id = i.id), '-')
      || '] doc=' || pg_temp.norm2(public.doc_data('final_invoice', jsonb_build_object('invoice_id', i.id))::text) || ' ;; ';
  end loop;
  return v;
end $$;
create function pg_temp.cr_trace(p_inv uuid) returns text language plpgsql as $$
declare v text := ''; c record;
begin
  for c in select * from public.so_credit x where x.invoice_id = p_inv order by x.credit_number loop
    v := v || 'cr[' || c.status || '|' || trim_scale(c.lines_amount) || '|' || trim_scale(c.freight_discount_amount) || '|' || trim_scale(c.tax_amount) || '|' || trim_scale(c.total) || '|' || c.warehouse_name || '] lines['
      || coalesce((select string_agg(l.kind || '|' || coalesce(trim_scale(l.qty_returned)::text, '-') || '|' || coalesce(trim_scale(l.unit_price)::text, '-') || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount) || '|' || coalesce(l.restock_bin, '-'), ',' order by l.line_no) from public.so_credit_line l where l.credit_id = c.id), '-')
      || '] ledger=' || (select count(*) || '/' || coalesce(trim_scale(sum(qty_delta))::text, '0') from public.inv_ledger where doc_number = c.credit_number)
      || ' doc=' || pg_temp.norm2(public.doc_data('credit_note', jsonb_build_object('credit_id', c.id))::text) || ' ;; ';
  end loop;
  return v;
end $$;
-- 동일성 한 경우 — 재료를 만들고 끝까지 돌린 뒤 되감는다 · 결과 = {ret, trace}
create function pg_temp.scn(p_code text, p_claims text, p_st uuid, p_cust uuid, p_pid uuid, p_wh uuid, p_bin text, p_rule uuid, p_rule_name text) returns jsonb language plpgsql as $$
declare v_so uuid; v_so2 uuid; v_l uuid; v_l2 uuid; v_x jsonb; v_ret jsonb := '{}'::jsonb; v_ids uuid[]; v_inv uuid; v_ilp uuid; v_ilc uuid; v_tr text := '';
begin
  begin
    perform set_config('request.jwt.claims', p_claims, true);
    if p_code = 'A' then
      v_x := public.so_create(p_cust, 'warehouse', 'manual', p_wh, 'svc-1c ident A');  v_so := (v_x->>'id')::uuid;
      v_x := public.so_line_add(v_so, p_pid, 5, 9.00, null, null, null, false);  v_l := (v_x->'line'->>'id')::uuid;
      v_x := public.so_charge_set(p_so_id => v_so, p_name => 'Freight', p_amount => 50, p_discount_pct => 50);
      execute 'set local session_replication_role = replica';
      update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
      execute 'set local session_replication_role = origin';
      v_x := public.so_confirm(v_so, null, false, true);
      execute 'set local session_replication_role = replica';
      update public.so set status = 'packed' where id = v_so and status = 'confirmed';
      execute 'set local session_replication_role = origin';
      v_ret := v_ret || jsonb_build_object('fin', public.so_finalize(jsonb_build_array(jsonb_build_object('so_id', v_so, 'picks', jsonb_build_array(jsonb_build_object('line_id', v_l, 'bin', p_bin, 'qty', 5)))), true, null));
      v_tr := 'FIN1 ' || pg_temp.inv_trace(array[v_so]);
      select i.id into v_inv from public.so_invoice i join public.so_invoice_order o on o.invoice_id = i.id where o.so_id = v_so and o.cancelled_at is null;
      v_ret := v_ret || jsonb_build_object('cancel', public.so_invoice_cancel(v_inv, 'svc-1c ident A'));
      v_ret := v_ret || jsonb_build_object('reissue', public.so_invoice_reissue(array[v_so], null));
      v_tr := v_tr || ' FIN2 ' || pg_temp.inv_trace(array[v_so]);
      select i.id into v_inv from public.so_invoice i join public.so_invoice_order o on o.invoice_id = i.id where o.so_id = v_so and o.cancelled_at is null;
      select l.id into v_ilp from public.so_invoice_line l where l.invoice_id = v_inv and l.kind = 'product';
      select l.id into v_ilc from public.so_invoice_line l where l.invoice_id = v_inv and l.kind = 'charge';
      v_ret := v_ret || jsonb_build_object('credit', public.so_credit_issue(jsonb_build_object('invoice_id', v_inv, 'reason', 'customer_return', 'warehouse_id', p_wh,
        'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', v_ilp, 'qty_returned', 2, 'restock_bin', p_bin), jsonb_build_object('kind', 'freight', 'so_invoice_line_id', v_ilc, 'amount', 50))), true));
      v_tr := v_tr || ' CR ' || pg_temp.cr_trace(v_inv);
    elsif p_code = 'B' then
      v_x := public.so_create(p_cust, 'counter', 'manual', p_wh, 'svc-1c ident B');  v_so := (v_x->>'id')::uuid;
      v_x := public.so_line_add(v_so, p_pid, 3, 9.00, null, null, null, false);  v_l := (v_x->'line'->>'id')::uuid;
      v_x := public.so_charge_set(p_so_id => v_so, p_name => 'Freight', p_amount => 20);
      execute 'set local session_replication_role = replica';
      update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
      execute 'set local session_replication_role = origin';
      v_x := public.so_pos_confirm(v_so);
      v_ret := v_ret || jsonb_build_object('ship', public.so_counter_ship(v_so, jsonb_build_array(jsonb_build_object('line_id', v_l, 'bin', p_bin, 'qty', 3)), true));
      v_tr := pg_temp.inv_trace(array[v_so]);
    else
      v_x := public.so_create(p_cust, 'warehouse', 'manual', p_wh, 'svc-1c ident C1');  v_so := (v_x->>'id')::uuid;
      v_x := public.so_line_add(v_so, p_pid, 2, 9.00, null, null, null, false);  v_l := (v_x->'line'->>'id')::uuid;
      v_x := public.so_charge_set(p_so_id => v_so, p_name => 'Freight', p_amount => 15);
      v_x := public.so_create(p_cust, 'warehouse', 'manual', p_wh, 'svc-1c ident C2');  v_so2 := (v_x->>'id')::uuid;
      v_x := public.so_line_add(v_so2, p_pid, 1, 9.00, null, null, null, false);  v_l2 := (v_x->'line'->>'id')::uuid;
      execute 'set local session_replication_role = replica';
      update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id in (v_so, v_so2);
      execute 'set local session_replication_role = origin';
      v_x := public.so_confirm(v_so, null, false, true);  v_x := public.so_confirm(v_so2, null, false, true);
      execute 'set local session_replication_role = replica';
      update public.so set status = 'packed' where id in (v_so, v_so2) and status = 'confirmed';
      execute 'set local session_replication_role = origin';
      v_ret := v_ret || jsonb_build_object('fin', public.so_finalize(jsonb_build_array(jsonb_build_object('so_id', v_so, 'picks', jsonb_build_array(jsonb_build_object('line_id', v_l, 'bin', p_bin, 'qty', 2))),
                                                                                       jsonb_build_object('so_id', v_so2, 'picks', jsonb_build_array(jsonb_build_object('line_id', v_l2, 'bin', p_bin, 'qty', 1)))), true, null));
      v_tr := pg_temp.inv_trace(array[v_so, v_so2]);
    end if;
    raise exception using errcode = 'P7777', message = jsonb_build_object('ret', v_ret, 'trace', v_tr)::text;
  exception when sqlstate 'P7777' then
    return sqlerrm::jsonb;
  when others then
    return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
  end;
end $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'qty_ck_charge=' || ((select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so_invoice_line'::regclass and conname = 'so_invoice_line_qty_ck') ~ '''charge''::text\) THEN true')::text
      || ' pair_ck=' || (exists (select 1 from pg_constraint where conrelid = 'public.so_invoice_line'::regclass and conname = 'so_invoice_line_charge_qty_ck'))::text
      || ' issue_carries_qty=' || (select (p.prosrc ~ 'v_cq, v_cup')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_invoice_issue') $$;
create function pg_temp.real_rows() returns text language sql security definer as $$
  select 'invl=' || (select count(*) || '/' || md5(coalesce(string_agg(l.id::text || l.kind || coalesce(l.qty::text, '-') || coalesce(l.unit_price::text, '-') || l.amount, ',' order by l.id), '')) from public.so_invoice_line l join public.so_invoice i on i.id = l.invoice_id where i.bill_to_customer_id not in (select id from public.customer where name = 'SVC1C Customer'))
      || ' inv=' || (select count(*) from public.so_invoice i where i.bill_to_customer_id not in (select id from public.customer where name = 'SVC1C Customer'))
      || ' cr=' || (select count(*) from public.so_credit c where c.customer_id not in (select id from public.customer where name = 'SVC1C Customer'))
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where sku not like 'SVC1C-%')
      || ' fns=' || (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('so_invoice_reissue', 'so_invoice_cancel', 'so_invoice_preview', 'so_credit_issue', 'so_credit_prepare', 'doc_data', 'doc_data_invoice', 'doc_data_invoice_fmt', 'doc_data_credit', 'so_tax_preview', 'so_finalize', 'so_service_invoice', 'so_service_confirm', 'so_charge_set')) $$;

\echo '── M0) 가짜 직원(S sales manager) · 손님(기본 브랜치 · CAD · Net 30) · 제품 + 칸 재고 50 · 서비스 둘(Prep 0.45 · Label 1.20) · 세율 · 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'svc1c-s@test.invalid', 'SVC1C S', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as s_uid, id::text as s_id \gset
\set s '{"sub":"' :s_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.name as bina from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as r13, name as r13_name, rate_pct as r13_rate from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('SVC1C Customer', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as cust \gset
insert into public.product (sku, name, source) values ('SVC1C-P', 'SVC1C Product', 'manual') returning id::text as pid \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values (public.ims_today() - 3, 1, 'SVC1C-P', :'whname', :'bina', 50, 'po_in', 'purchase', 'PO-SVC1C', 'svc1c-1', 'manual');
insert into public.ref_service (name, unit_price) values ('SVC1C Prep service', 0.45) returning id::text as svc \gset
insert into public.ref_service (name, unit_price) values ('SVC1C Label service', 1.20) returning id::text as svc2 \gset
set local session_replication_role = origin;
select pg_temp.real_rows() as real_before, pg_temp.gate_state() as gate_before \gset
select pg_temp.chk(format('M0 staff · customer (branch %s · %s) · product SVC1C-P stock 50 in %s · services 0.45 / 1.20 · tax %s %s%% · snapshots taken', :'whname', :'pt30_name', :'bina', :'r13_name', trim_scale(:'r13_rate'::numeric)),
  :'s_uid' <> '' and :'cust' <> '' and :'pid' <> '' and :'svc' <> '' and :'svc2' <> '' and :'r13' <> '' and :'pt30' <> '' and :'real_before' <> '', 'see M0');

-- 서비스 오더 하나: 만들기 → 서비스 줄들(p_lines: [{qty, unit_price?, service_id, discount_pct?}]) → 세율 → 확정 → 발행 → {so_id, invoice_id}
create function pg_temp.svc_order(p_claims text, p_lines jsonb, p_rule uuid, p_rule_name text, p_cust uuid) returns jsonb language plpgsql as $$
declare v_so uuid; v_x jsonb; e jsonb; v_inv jsonb;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  v_x := public.so_create(p_cust, 'service', 'manual', null, 'svc-1c service');  v_so := (v_x->>'id')::uuid;
  for e in select t from jsonb_array_elements(p_lines) t loop
    v_x := public.so_charge_set(p_so_id => v_so, p_name => null, p_amount => null, p_qty => (e->>'qty')::numeric, p_unit_price => nullif(e->>'unit_price', '')::numeric, p_service_id => (e->>'service_id')::uuid, p_discount_pct => nullif(e->>'discount_pct', '')::numeric);
  end loop;
  execute 'set local session_replication_role = replica';
  update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
  execute 'set local session_replication_role = origin';
  v_x := public.so_service_confirm(v_so);
  v_inv := public.so_service_invoice(v_so, null, true);
  return jsonb_build_object('so_id', v_so, 'invoice_id', v_inv->>'invoice_id', 'invoice_number', v_inv->>'invoice_number', 'total', v_inv->'totals'->'total');
exception when others then
  return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
end $$;
create function pg_temp.lines_of(p_inv uuid) returns text language sql security definer as $$
  select coalesce(string_agg(l.kind || '|' || coalesce(trim_scale(l.qty)::text, '-') || '|' || coalesce(trim_scale(l.unit_price)::text, '-') || '|' || coalesce(trim_scale(l.discount_pct)::text, '-') || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount), ',' order by l.line_no), '-') from public.so_invoice_line l where l.invoice_id = p_inv $$;
create temp table t_ident (phase text, c text, ret text, trace text);
create function pg_temp.ident(p_phase text, p_claims text, p_st uuid, p_cust uuid, p_pid uuid, p_wh uuid, p_bin text, p_rule uuid, p_rule_name text) returns int language plpgsql as $$
declare v jsonb; c record; v_n int := 0;
begin
  for c in select * from (values ('A', 'A warehouse: line 5 @9 · Freight 50 −50% · Ship & invoice → cancel → reissue → credit (product 2 restocked + freight 50)'), ('B', 'B counter: line 3 · Freight 20 · counter ship + invoice'), ('C', 'C two warehouse orders (one with Freight 15) → so_finalize → one invoice')) t(code, name) loop
    v := pg_temp.scn(c.code, p_claims, p_st, p_cust, p_pid, p_wh, p_bin, p_rule, p_rule_name);
    insert into t_ident values (p_phase, c.name, pg_temp.norm(coalesce((v->'ret')::text, v->>'err')), coalesce(v->>'trace', v->>'err'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — 서비스 오더 1200 × 0.45 발행 → 인보이스 줄 charge 에 qty · unit_price 없음 · doc_data charges 의 qty · unit_price 빈 글자 · CHECK 가 charge 의 qty 를 막는다'
select pg_temp.svc_order(:'s', format('[{"qty":1200,"service_id":"%s"}]', :'svc')::jsonb, :'r13'::uuid, :'r13_name', :'cust'::uuid)::text as s0 \gset
select coalesce(pg_temp.j(:'s0')->>'invoice_id', '00000000-0000-0000-0000-000000000000') as s0_inv \gset
select pg_temp.as_user(:'s', format('select (public.doc_data(''final_invoice'', %L::jsonb)->''docs''->0->''charges''->0)::text', json_build_object('invoice_id', :'s0_inv')::text)) as s0_doc \gset
select pg_temp.as_user(:'s', format('insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, qty, unit_price, amount, tax_amount, updated_by) select l.invoice_id, l.invoice_order_id, 99, ''charge'', l.so_charge_id, ''try'', 1200, 0.45, 540, 0, l.updated_by from public.so_invoice_line l where l.invoice_id = %L::uuid and l.kind = ''charge'' returning id::text', :'s0_inv')) as s0_ck \gset
select pg_temp.chk('S0 before the trial: service invoice line charge|-|-|-|540|70.2 (amount only) · doc charges[0] qty "" unit_price "" amount "540.00" · inserting a charge line with qty refused by so_invoice_line_qty_ck · not in schema_migrations',
  :'s0' not like '%"err"%' and pg_temp.lines_of(:'s0_inv'::uuid) = 'charge|-|-|-|540|70.2'
  and pg_temp.j(:'s0_doc')->>'qty' = '' and pg_temp.j(:'s0_doc')->>'unit_price' = '' and pg_temp.j(:'s0_doc')->>'amount' = '540.00' and pg_temp.j(:'s0_doc')->>'description' = 'SVC1C Prep service'
  and :'s0_ck' like 'ERR 23514%' and :'s0_ck' like '%so_invoice_line_qty_ck%'
  and :'gate_before' = 'qty_ck_charge=false pair_ck=false issue_carries_qty=false' and :n_applied = 0,
  format('s0 %s | lines %s | doc %s | ck %s | gate %s', left(:'s0', 200), pg_temp.lines_of(:'s0_inv'::uuid), left(:'s0_doc', 300), left(:'s0_ck', 160), :'gate_before'));
\echo '── I0) 동일성 — 옛 판으로 세 경우(되감김)'
select pg_temp.ident('old', :'s', :'s_id'::uuid, :'cust'::uuid, :'pid'::uuid, :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name') as old_n \gset
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: untouched functions same md5 · real invoice lines · invoices · credits · ledger unchanged', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));
\echo '── I1) 동일성 — 새 판으로 같은 세 경우 · 비교'
select pg_temp.ident('new', :'s', :'s_id'::uuid, :'cust'::uuid, :'pid'::uuid, :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name') as new_n \gset
select count(*) as n_cases, count(*) filter (where o.ret = n.ret and o.trace = n.trace) as same, count(*) filter (where o.ret like '%"err"%' or o.trace like '%ERR%' or o.trace = '') as n_err,
       coalesce(string_agg(o.c || ': RET ' || left(o.ret, 400) || ' ≠ ' || left(n.ret, 400) || ' // TRACE ' || left(o.trace, 1500) || ' ≠ ' || left(n.trace, 1500), ' || ') filter (where o.ret <> n.ret or o.trace <> n.trace), '-') as diff_detail,
       coalesce(string_agg(o.c || ': ' || left(o.trace, 600), ' || ' order by o.c), '-') as traces
  from t_ident o join t_ident n on n.c = o.c and n.phase = 'new' where o.phase = 'old' \gset
select pg_temp.chk(format('I1 old paths A ~ C (Ship & invoice with discounted freight → cancel → reissue → freight + product credit · counter · bundle): %s of %s cases same return and same trace (invoice lines kind|qty|unit_price|discount|amount|tax|account · headers · doc_data final_invoice · credit lines · credit ledger · doc_data credit_note) · none errored', :same, :n_cases),
  :n_cases = 3 and :same = 3 and :n_err = 0, format('diff %s | traces %s', :'diff_detail', :'traces'));
\else
select pg_temp.chk('P0c confirm run: migration 20261021183044 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() = 'qty_ck_charge=true pair_ck=true issue_carries_qty=true') as landed \gset
\if :landed
\echo '── G1) 실물'
select pg_temp.chk('G1 so_invoice_line_qty_ck allows charge · so_invoice_line_charge_qty_ck pair · so_invoice_issue carries qty · unit_price · one definition · ACL unchanged (postgres · service_role only)',
  pg_temp.gate_state() = 'qty_ck_charge=true pair_ck=true issue_carries_qty=true'
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_invoice_issue') = 1
  and not has_function_privilege('authenticated', 'public.so_invoice_issue(uuid[], uuid, date)', 'execute') and not has_function_privilege('anon', 'public.so_invoice_issue(uuid[], uuid, date)', 'execute'), pg_temp.gate_state());

\echo '── N1) 서비스 오더 — Prep 1200 × 0.45(목록) · Prep 500 × 0.38(손 단가) · Label 10 × 1.20 · Prep 100 × 0.45 −10% → 발행 → 인보이스 줄 qty · unit_price · amount · 할인 줄 · doc_data charges 꼴(1200 · 0.45 · 540.00) · 합계 식'
select pg_temp.svc_order(:'s', format('[{"qty":1200,"service_id":"%s"},{"qty":500,"unit_price":0.38,"service_id":"%s"},{"qty":10,"service_id":"%s"},{"qty":100,"service_id":"%s","discount_pct":10}]', :'svc', :'svc', :'svc2', :'svc')::jsonb, :'r13'::uuid, :'r13_name', :'cust'::uuid)::text as n1 \gset
select coalesce(pg_temp.j(:'n1')->>'invoice_id', '00000000-0000-0000-0000-000000000000') as inv1 \gset
select pg_temp.as_user(:'s', format('select (public.doc_data(''final_invoice'', %L::jsonb)->''docs''->0->''charges'')::text', json_build_object('invoice_id', :'inv1')::text)) as n1_doc \gset
select (select trim_scale(i.charges_amount) || '|' || trim_scale(i.charges_discount_amount) || '|' || trim_scale(i.taxable_amount) || '|' || trim_scale(i.tax_amount) || '|' || trim_scale(i.total) || '|' || (i.taxable_amount + i.tax_amount = i.total) || '|' || (i.tax_amount = (select sum(l.tax_amount) from public.so_invoice_line l where l.invoice_id = i.id)) from public.so_invoice i where i.id = :'inv1'::uuid) as n1_hdr \gset
select pg_temp.chk(format('N1 service invoice lines = %s · header charges|discount|taxable|tax|total|sum-ok = %s · doc charges[0] qty 1200 unit_price 0.45 amount 540.00 · [1] 500 × 0.38 · [2] 10 × 1.20 · [3] 100 × 0.45 then discount line −4.50 with qty ""', pg_temp.lines_of(:'inv1'::uuid), :'n1_hdr'),
  :'n1' not like '%"err"%' and pg_temp.lines_of(:'inv1'::uuid) = 'charge|1200|0.45|-|540|70.2,charge|500|0.38|-|190|24.7,charge|10|1.2|-|12|1.56,charge|100|0.45|-|45|5.85,charge_discount|-|-|10|-4.5|-0.59'
  and :'n1_hdr' like '787|4.5|782.5|%|true|true'
  and pg_temp.j(:'n1_doc')->0->>'qty' = '1200' and pg_temp.j(:'n1_doc')->0->>'unit_price' = '0.45' and pg_temp.j(:'n1_doc')->0->>'amount' = '540.00' and pg_temp.j(:'n1_doc')->0->>'description' = 'SVC1C Prep service'
  and pg_temp.j(:'n1_doc')->1->>'qty' = '500' and pg_temp.j(:'n1_doc')->1->>'unit_price' = '0.38' and pg_temp.j(:'n1_doc')->2->>'qty' = '10' and pg_temp.j(:'n1_doc')->2->>'unit_price' = '1.20' and pg_temp.j(:'n1_doc')->2->>'description' = 'SVC1C Label service'
  and pg_temp.j(:'n1_doc')->3->>'qty' = '100' and pg_temp.j(:'n1_doc')->4->>'qty' = '' and pg_temp.j(:'n1_doc')->4->>'amount' = '-4.50' and pg_temp.j(:'n1_doc')->4->>'discount_pct' = '10%',
  format('n1 %s | lines %s | hdr %s | doc %s', left(:'n1', 200), pg_temp.lines_of(:'inv1'::uuid), :'n1_hdr', left(:'n1_doc', 1200)));

\echo '── N2) CHECK — charge 줄: qty 만 · 금액 ≠ qty × 단가 거부 · 둘 다 null 허용(옛 꼴) · product 줄 qty 없음은 여전히 거부'
select pg_temp.as_user(:'s', format('insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, qty, amount, tax_amount, updated_by) select l.invoice_id, l.invoice_order_id, 91, ''charge'', l.so_charge_id, ''try'', 10, 4.5, 0, l.updated_by from public.so_invoice_line l where l.invoice_id = %L::uuid and l.line_no = 1 returning id::text', :'inv1')) as n2_a \gset
select pg_temp.as_user(:'s', format('insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, qty, unit_price, amount, tax_amount, updated_by) select l.invoice_id, l.invoice_order_id, 92, ''charge'', l.so_charge_id, ''try'', 10, 0.45, 5, 0, l.updated_by from public.so_invoice_line l where l.invoice_id = %L::uuid and l.line_no = 1 returning id::text', :'inv1')) as n2_b \gset
select pg_temp.as_user(:'s', format('insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, amount, tax_amount, updated_by) select l.invoice_id, l.invoice_order_id, 93, ''charge'', l.so_charge_id, ''try old shape'', 5, 0, l.updated_by from public.so_invoice_line l where l.invoice_id = %L::uuid and l.line_no = 1 returning id::text', :'inv1')) as n2_c \gset
select pg_temp.as_user(:'s', format('insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, description, amount, tax_amount, updated_by) select l.invoice_id, l.invoice_order_id, 94, ''product'', l.so_charge_id, ''try'', 5, 0, l.updated_by from public.so_invoice_line l where l.invoice_id = %L::uuid and l.line_no = 1 returning id::text', :'inv1')) as n2_d \gset
delete from public.so_invoice_line where invoice_id = :'inv1'::uuid and line_no = 93;
select pg_temp.chk('N2 CHECK: qty without unit_price refused (charge_qty_ck) · amount ≠ qty × unit_price refused (charge_qty_ck) · amount-only charge line accepted (old shape) · product line without qty refused (qty_ck)',
  :'n2_a' like 'ERR 23514%' and :'n2_a' like '%so_invoice_line_charge_qty_ck%' and :'n2_b' like 'ERR 23514%' and :'n2_b' like '%so_invoice_line_charge_qty_ck%'
  and :'n2_c' not like 'ERR%' and :'n2_d' like 'ERR 23514%' and :'n2_d' like '%so_invoice_line_qty_ck%',
  format('a %s | b %s | c %s | d %s', left(:'n2_a', 160), left(:'n2_b', 160), left(:'n2_c', 80), left(:'n2_d', 160)));

\echo '── N3) 크레딧 — N1 인보이스의 Prep 1200 줄에서 90(= 200 × 0.45) 일부 → 크레딧 90 + 11.70 · 줄 freight · 금액만(qty 없음) · 재입고 0 · 원장 0 · 창고 = 서비스 오더 창고 · 손님 잔액 · 문서 · 나머지 450 전부 → 한도 끝 → 1 더 거부'
select l.id::text as il_540 from public.so_invoice_line l where l.invoice_id = :'inv1'::uuid and l.line_no = 1 \gset
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_credit_issue(%L::jsonb, true)::text', json_build_object('invoice_id', :'inv1', 'reason', 'billing_error', 'lines', json_build_array(json_build_object('kind', 'freight', 'so_invoice_line_id', :'il_540', 'amount', 90)))::text)) as n3_a \gset
reset role;
select coalesce(pg_temp.j(:'n3_a')->>'credit_id', '00000000-0000-0000-0000-000000000000') as cr1, coalesce(pg_temp.j(:'n3_a')->>'credit_number', '?') as cr1_no \gset
select (select trim_scale(c.lines_amount) || '|' || trim_scale(c.tax_amount) || '|' || trim_scale(c.total) || '|' || (c.warehouse_id = :'wh'::uuid) || '|' || c.status from public.so_credit c where c.id = :'cr1'::uuid) as n3_hdr,
       (select string_agg(l.kind || '|' || coalesce(trim_scale(l.qty_returned)::text, '-') || '|' || coalesce(trim_scale(l.unit_price)::text, '-') || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount) || '|' || coalesce(l.restock_bin, '-') || '|' || l.description, ',' order by l.line_no) from public.so_credit_line l where l.credit_id = :'cr1'::uuid) as n3_lines,
       (select count(*) from public.inv_ledger where doc_number = :'cr1_no') as n3_ledger,
       (select trim_scale(b.owed_credit) from public.so_customer_balance(:'cust'::uuid) b where b.currency_id = :'cad'::uuid) as n3_owed \gset
select pg_temp.as_user(:'s', format('select (public.doc_data(''credit_note'', %L::jsonb)->''docs''->0)::text', json_build_object('credit_id', :'cr1')::text)) as n3_doc \gset
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_credit_issue(%L::jsonb, true)::text', json_build_object('invoice_id', :'inv1', 'reason', 'billing_error', 'lines', json_build_array(json_build_object('kind', 'freight', 'so_invoice_line_id', :'il_540', 'amount', 450)))::text)) as n3_b \gset
select pg_temp.as_user(:'s', format('select public.so_credit_issue(%L::jsonb, true)::text', json_build_object('invoice_id', :'inv1', 'reason', 'billing_error', 'lines', json_build_array(json_build_object('kind', 'freight', 'so_invoice_line_id', :'il_540', 'amount', 1)))::text)) as n3_c \gset
reset role;
select pg_temp.chk(format('N3 partial credit 90: header %s · lines %s · ledger rows %s · owed_credit %s · credit_note doc charges[0] description Prep · qty "" · unit_price "" · amount 90.00 · lines [] · then 450 OK · then 1 refused (only 0 left)', :'n3_hdr', :'n3_lines', :n3_ledger, :'n3_owed'),
  :'n3_a' not like 'ERR%' and :'n3_hdr' = format('90|11.7|101.7|true|issued') and :'n3_lines' = 'freight|-|-|90|11.7|-|SVC1C Prep service' and :n3_ledger = 0 and :'n3_owed'::numeric >= 101.7
  and :'n3_doc' not like 'ERR%' and pg_temp.j(:'n3_doc')->'charges'->0->>'description' = 'SVC1C Prep service' and pg_temp.j(:'n3_doc')->'charges'->0->>'qty' = '' and pg_temp.j(:'n3_doc')->'charges'->0->>'unit_price' = '' and pg_temp.j(:'n3_doc')->'charges'->0->>'amount' = '90.00'
  and jsonb_array_length(pg_temp.j(:'n3_doc')->'lines') = 0 and pg_temp.j(:'n3_doc')->'totals'->>'total' = '101.70'
  and :'n3_b' not like 'ERR%' and (pg_temp.j(:'n3_b')->'totals'->>'lines_amount')::numeric = 450 and :'n3_c' like 'ERR%' and :'n3_c' like '%only 0.00 left%',
  format('a %s | doc %s | b %s | c %s', left(:'n3_a', 300), left(:'n3_doc', 700), left(:'n3_b', 200), left(:'n3_c', 200)));

\echo '── N4) 물건 오더에 수량 × 단가 줄(Prep 10 × 0.45) — 마무리가 금액을 안 고치면 인보이스 줄에 10 · 0.45 · 마무리 화면이 금액을 5 로 고치려 하면 so_charge 의 짝 CHECK(svc-1a so_charge_qty_amount_ck)가 먼저 거부한다(수량 × 단가 줄은 금액으로 못 고친다 — 수량으로)'
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''svc-1c N4 a'')::text', :'cust', :'wh')) as n4_ca \gset
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''svc-1c N4 b'')::text', :'cust', :'wh')) as n4_cb \gset
reset role;
select coalesce(pg_temp.j(:'n4_ca')->>'id', '00000000-0000-0000-0000-000000000000') as so4a, coalesce(pg_temp.j(:'n4_cb')->>'id', '00000000-0000-0000-0000-000000000000') as so4b \gset
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_line_add(%L::uuid, %L::uuid, 1, 9.00, null, null, null, false)::text', :'so4a', :'pid')) as n4_la \gset
select pg_temp.as_user(:'s', format('select public.so_line_add(%L::uuid, %L::uuid, 1, 9.00, null, null, null, false)::text', :'so4b', :'pid')) as n4_lb \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 10, p_service_id => %L::uuid)::text', :'so4a', :'svc')) as n4_cha \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 10, p_service_id => %L::uuid)::text', :'so4b', :'svc')) as n4_chb \gset
reset role;
select coalesce(pg_temp.j(:'n4_la')->'line'->>'id', '00000000-0000-0000-0000-000000000000') as l4a, coalesce(pg_temp.j(:'n4_lb')->'line'->>'id', '00000000-0000-0000-0000-000000000000') as l4b,
       coalesce(pg_temp.j(:'n4_chb')->'charge'->>'id', '00000000-0000-0000-0000-000000000000') as ch4b \gset
set local session_replication_role = replica;
update public.so set tax_rule_id = :'r13'::uuid, tax_rule = :'r13_name', tax_rule_manual = true where id in (:'so4a'::uuid, :'so4b'::uuid);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_confirm(%L::uuid, null, false, true)::text', :'so4a')) as n4_cfa \gset
select pg_temp.as_user(:'s', format('select public.so_confirm(%L::uuid, null, false, true)::text', :'so4b')) as n4_cfb \gset
reset role;
set local session_replication_role = replica;
update public.so set status = 'packed' where id in (:'so4a'::uuid, :'so4b'::uuid) and status = 'confirmed';
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_finalize(%L::jsonb, true, null)::text', json_build_array(json_build_object('so_id', :'so4a', 'picks', json_build_array(json_build_object('line_id', :'l4a', 'bin', :'bina', 'qty', 1))))::text)) as n4_fa \gset
select pg_temp.as_user(:'s', format('select public.so_finalize(%L::jsonb, true, null)::text', json_build_array(json_build_object('so_id', :'so4b', 'picks', json_build_array(json_build_object('line_id', :'l4b', 'bin', :'bina', 'qty', 1)), 'charges', json_build_array(json_build_object('charge_id', :'ch4b', 'name', 'SVC1C Prep service', 'amount', 5))))::text)) as n4_fb \gset
reset role;
select coalesce((select i.id::text from public.so_invoice i join public.so_invoice_order o on o.invoice_id = i.id where o.so_id = :'so4a'::uuid and o.cancelled_at is null), '00000000-0000-0000-0000-000000000000') as inv4a,
       coalesce((select i.id::text from public.so_invoice i join public.so_invoice_order o on o.invoice_id = i.id where o.so_id = :'so4b'::uuid and o.cancelled_at is null), '00000000-0000-0000-0000-000000000000') as inv4b \gset
select pg_temp.chk(format('N4 warehouse order with a 10 × 0.45 service line: plain finalize → %s (qty · unit_price carried) · finalize overriding that charge amount to 5 → refused by so_charge_qty_amount_ck (svc-1a: a qty × unit price line is changed by qty, not by amount) · order b still packed · no invoice', pg_temp.lines_of(:'inv4a'::uuid)),
  :'n4_fa' not like 'ERR%' and pg_temp.lines_of(:'inv4a'::uuid) = 'product|1|9|-|9|1.17,charge|10|0.45|-|4.5|0.59'
  and :'n4_fb' like 'ERR 23514%' and :'n4_fb' like '%so_charge_qty_amount_ck%' and :'inv4b' = '00000000-0000-0000-0000-000000000000' and (select status from public.so where id = :'so4b'::uuid) = 'packed',
  format('cha %s | chb %s | cfa %s | cfb %s | fa %s | fb %s', left(:'n4_cha', 120), left(:'n4_chb', 120), left(:'n4_cfa', 120), left(:'n4_cfb', 120), left(:'n4_fa', 400), left(:'n4_fb', 400)));
\else
select pg_temp.chk('G1 ~ N4 skipped: svc-1c not landed', false, pg_temp.gate_state());
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real rows untouched (invoice lines · invoices · credits · ledger · untouched function md5)', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 셋 되돌리기'
select (select count(*) from public.customer where name = 'SVC1C Customer') + (select count(*) from public.product where sku like 'SVC1C-%') + (select count(*) from public.ims_staff where email like 'svc1c-%') + (select count(*) from public.ref_service where name like 'SVC1C%') + (select count(*) from public.inv_ledger where sku like 'SVC1C-%') as fake_traces_left;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
select setval('public.so_credit_number_seq', greatest(coalesce((select max(substring(credit_number from '[0-9]+')::bigint) from public.so_credit), 0), :cr_seq_last), :'cr_seq_called'::boolean) as so_credit_number_seq_reset_to;
select (select last_value || '|' || is_called from public.so_number_seq) as so_seq_after, (select last_value || '|' || is_called from public.so_invoice_number_seq) as inv_seq_after, (select last_value || '|' || is_called from public.so_credit_number_seq) as cr_seq_after;
