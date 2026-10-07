-- fr-1-verify.sql — 운임 할인(판정 352 ~ 358 · 오더 안) · 무변 · 같음 · 354 수 · 356 막기 · finalize 미리 보기 · 357-4 · 발행 가드 (Asung-IMS · 2026-10-07)
--   기대: 시험 갈래 OK 42 · 확인 갈래(G0 여섯 없음) OK 36 · MISMATCH 0(시험 적용 1회차 통과 · 2026-10-07) · 재료는 가짜만(SO-7995x · FR1-* · 가짜 손님 · 직원) · 실제 오더 무접촉 · 번호를 당기는 창구 없음(가짜 인보이스는 번호를 직접 준다) · 끝은 rollback
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261007171939_fr_1_freight_discount.sql -f supabase/tests/fr-1-verify.sql 2>&1 | tee /tmp/fr-1.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다(D-pre 는 확인 갈래에서 새 함수 — 무변 비교는 옛 열쇠만 보므로 두 갈래 같은 식)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
\echo '== seq head so' :so_seq_last :so_seq_called 'inv' :inv_seq_last :inv_seq_called 'cr' :cr_seq_last :cr_seq_called
select count(*) as n_so from public.so \gset
select count(*) as n_chg from public.so_charge \gset
\echo '== orders' :n_so '· charges' :n_chg

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create temp table t_pre as
  select p.proname as n, p.prosrc as src, pg_get_function_result(p.oid) as res, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public'
   and p.proname in ('so_charge_set', 'so_finalize', 'so_tax_preview', 'so_detail', 'so_totals_many', 'so_proforma', 'so_invoice_issue', 'so_credit_issue', 'so_credit_prepare', 'so_charge_remove', 'so_lines_total');
-- D-pre 셋(시험 갈래 = 옛 함수 · 확인 갈래 = 새 함수)
do $$
declare v_src text; v_res text;
begin
  select src into v_src from t_pre where n = 'so_detail';
  execute format('create function public.fr1_pre_detail(p_so_id uuid) returns jsonb language plpgsql stable security invoker set search_path = public, pg_temp as %L', v_src);
  select src into v_src from t_pre where n = 'so_tax_preview';
  execute format('create function public.fr1_pre_tax(p_so_id uuid, p_on date default null, p_rule_id uuid default null, p_basis text default ''ordered'') returns jsonb language plpgsql stable security invoker set search_path = public, pg_temp as %L', v_src);
  select src, res into v_src, v_res from t_pre where n = 'so_totals_many';
  execute format('create function public.fr1_pre_many(p_so_ids uuid[]) returns %s language plpgsql stable security invoker set search_path = public, pg_temp as %L', v_res, v_src);
end $$;
\if :{?mig}
select pg_temp.chk('G0a so_charge_set last def = 20260924175014:751~830', (select md5(src) from t_pre where n = 'so_charge_set'), '6cd0e066b783eb1c429dddf71d4b5071');
select pg_temp.chk('G0b so_finalize last def = 20261006000805:73~373', (select md5(src) from t_pre where n = 'so_finalize'), 'cf7375c836e8af929a1e0ec6c2a1fbba');
select pg_temp.chk('G0c so_tax_preview last def = 20261006000805:884~963', (select md5(src) from t_pre where n = 'so_tax_preview'), '497207d8659cfa115a560f04fd1f4e85');
select pg_temp.chk('G0d so_detail last def = 20261006204146:956~1060', (select md5(src) from t_pre where n = 'so_detail'), '50677b573390a9fab65f0185ee17661e');
select pg_temp.chk('G0e so_totals_many last def = 20261007161321:35~67', (select md5(src) from t_pre where n = 'so_totals_many'), '70f7d890dc002b55a1a12945eec35dab');
select pg_temp.chk('G0f so_proforma last def = 20261006000805:1224~1310', (select md5(src) from t_pre where n = 'so_proforma'), 'c5a9938795fefd4993f82baeaa8d17ce');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
-- 정규형 — 옛 열쇠만(새 열쇠 · 할인 칸은 빼고) · 세 함수 · 모든 오더 · 한 문장에서 둘을 받는다(같은 스냅샷)
create function pg_temp.strip_tax(p_j jsonb) returns jsonb language sql as $$
  select (p_j - 'charge_discounts')
         || jsonb_build_object('totals', (p_j->'totals') - 'charges_discount_amount' - 'charges_discount_tax' - 'charges_net_amount')
         || jsonb_build_object('charges', coalesce((select jsonb_agg(c - 'discount_pct' - 'discount_amount' - 'discount' - 'discount_tax' - 'net' order by ord) from jsonb_array_elements(p_j->'charges') with ordinality as t(c, ord)), '[]'::jsonb))
$$;
create function pg_temp.canon_all(p_detail text, p_tax text, p_many text, p_only_real boolean) returns text language plpgsql stable as $$
declare v_out text := ''; v_r record; v_t jsonb; v_x jsonb; v_ids uuid[]; v_m text;
begin
  for v_r in select s.id, s.status, s.so_number from public.so s where (not p_only_real or s.so_number not like 'SO-799%') order by s.id loop
    execute format('select public.%I($1)->''totals''', p_detail) into v_t using v_r.id;
    execute format('select pg_temp.strip_tax(public.%I($1, null, null, $2))', p_tax) into v_x using v_r.id, case when v_r.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;
    v_out := v_out || v_r.id::text || '|' || (v_t - 'charges_discount_amount' - 'charges_net_total')::text || '|' || v_x::text || E'\n';
  end loop;
  select array_agg(s.id order by s.id) into v_ids from public.so s where (not p_only_real or s.so_number not like 'SO-799%');
  execute format('select string_agg(m.so_id::text || ''|'' || m.basis || ''|'' || trim_scale(m.lines_total) || ''|'' || trim_scale(m.order_discount_amount) || ''|'' || trim_scale(m.charges_total) || ''|'' || trim_scale(m.surcharge_amount) || ''|'' || coalesce(trim_scale(m.tax)::text, ''∅'') || ''|'' || trim_scale(m.order_total) || ''|'' || coalesce(trim_scale(m.order_total_with_tax)::text, ''∅''), E''\n'' order by m.so_id) from public.%I($1) m', p_many) into v_m using v_ids[1:200];
  return md5(v_out) || '/' || md5(coalesce(v_m, ''));
end $$;
-- 같음(so-tot-1 식): so_detail.totals 아홉 열쇠 = so_totals_many 아홉 열(모든 오더)
create function pg_temp.same_detail_many() returns text language plpgsql stable as $$
declare v_d text := ''; v_m text; v_r record; v_t jsonb; v_ids uuid[];
begin
  for v_r in select s.id from public.so s order by s.id loop
    v_t := public.so_detail(v_r.id)->'totals';
    v_d := v_d || v_r.id::text || '|' || (v_t->>'basis') || '|' || trim_scale((v_t->>'lines_total')::numeric) || '|' || trim_scale((v_t->>'order_discount_amount')::numeric) || '|' || trim_scale((v_t->>'charges_total')::numeric) || '|' || trim_scale((v_t->>'charges_discount_amount')::numeric) || '|' || trim_scale((v_t->>'surcharge_amount')::numeric) || '|' || coalesce(trim_scale((v_t->>'tax')::numeric)::text, '∅') || '|' || trim_scale((v_t->>'order_total')::numeric) || '|' || coalesce(trim_scale((v_t->>'order_total_with_tax')::numeric)::text, '∅') || E'\n';
  end loop;
  select array_agg(s.id order by s.id) into v_ids from public.so s;
  select string_agg(m.so_id::text || '|' || m.basis || '|' || trim_scale(m.lines_total) || '|' || trim_scale(m.order_discount_amount) || '|' || trim_scale(m.charges_total) || '|' || trim_scale(m.charges_discount_amount) || '|' || trim_scale(m.surcharge_amount) || '|' || coalesce(trim_scale(m.tax)::text, '∅') || '|' || trim_scale(m.order_total) || '|' || coalesce(trim_scale(m.order_total_with_tax)::text, '∅'), E'\n' order by m.so_id) || E'\n' into v_m from public.so_totals_many(v_ids[1:200]) m;
  return case when v_d = v_m then 'same' else 'DIFFER' end || '/' || array_length(string_to_array(rtrim(v_d, E'\n'), E'\n'), 1);
end $$;

-- ═══ U 무변 — 실제 오더 전부 · so_detail.totals(옛 열쇠) · so_tax_preview(새 열쇠 뺀 전체) · so_totals_many(옛 아홉 열) · 옛 함수 = 새 함수 ═══
select clock_timestamp() as t0 \gset
select pg_temp.canon_all('fr1_pre_detail', 'fr1_pre_tax', 'fr1_pre_many', true) as c_pre \gset
select clock_timestamp() as t1 \gset
select pg_temp.canon_all('so_detail', 'so_tax_preview', 'so_totals_many', true) as c_new \gset
select clock_timestamp() as t2 \gset
select pg_temp.chk('U1 real orders: detail totals · tax_preview · totals_many unchanged (old keys · no order has a discount yet)', (:'c_pre' = :'c_new')::text || '/' || :'n_so', 'true/' || :'n_so');
select 'T cost (all ' || :'n_so' || ' orders · detail + tax_preview + totals_many · ms): before=' || round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000) || ' · after=' || round(extract(epoch from (:'t2'::timestamptz - :'t1'::timestamptz)) * 1000);
select pg_temp.chk('U2 so_detail.totals = so_totals_many (nine keys · all orders · before fake material)', pg_temp.same_detail_many(), 'same/' || :'n_so');

-- ═══ 재료 — 직원(manager · sales) · 손님 · 제품 · 세금 규칙 HST ON 13% · GST 5% · 초안 넷 D1 ~ D4 · 가짜 packed P1 · 초안 D5(할인 없음 · 가드 대조) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'fr1-manager@test.invalid', 'FR1 Manager', 'manager', '["sales"]'::jsonb) returning auth_user_id::text as m_uid \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as tier, name as tier_name from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' limit 1 \gset
select id::text as whx, name as whx_name from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as r13, name as r13_name from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as r5, name as r5_name from public.ref_tax_rule where name = 'GST (Sale)' and is_active \gset
insert into public.ref_brand (name) values ('FR1 Brand') returning id::text as br \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('FR1 Customer', 'manual', :'tier_name', :'whx'::uuid, 0) returning id::text as cust \gset
insert into public.product (sku, name, source, brand_id) values ('FR1-P', 'FR1 Product P', 'manual', :'br'::uuid) returning id::text as pp \gset
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name) values ('SO-79951', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name') returning id::text as d1 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name) values ('SO-79952', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', public.ims_today(), :'tier'::uuid, 0, :'r5'::uuid, :'r5_name', true, :'whx'::uuid, :'whx_name') returning id::text as d2 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name) values ('SO-79953', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name') returning id::text as d3 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, order_discount_pct, order_discount_source) values ('SO-79954', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', 10, 'manual') returning id::text as d4 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, confirmed_at) values ('SO-79955', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'packed', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, now()) returning id::text as p1 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name) values ('SO-79956', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name') returning id::text as d5 \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, list_price, unit_price) values (:'d4'::uuid, 1, :'pp'::uuid, 'FR1-P', 'FR1 Product P', 1, 1, 100, 100);
insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, list_price, unit_price) values (:'p1'::uuid, 1, :'pp'::uuid, 'FR1-P', 'FR1 Product P', 1, 1, 100, 100) returning id::text as p1_line \gset
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_code, discount_amount) values (:'p1'::uuid, 1, 'Freight', 100, :'r13_name', '_99_', 30) returning id::text as p1_chg \gset
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_code) values (:'d5'::uuid, 1, 'Freight', 20, :'r13_name', '_99_');
set local session_replication_role = origin;
create function pg_temp.tt(p_so uuid) returns jsonb language sql as $$ select public.so_tax_preview(p_so, null, null, 'ordered')->'totals' $$;
create function pg_temp.dt(p_so uuid) returns jsonb language sql as $$ select public.so_detail(p_so)->'totals' $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'no-error'; exception when others then return sqlerrm; end $$;

-- ═══ N 판정 354 수 — D1 174.26 · 13% · 50% / D2 110.50 · 5% · 50% / D3 100 · 13% · 50% → 100% → 금액 30 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select (public.so_charge_set(:'d1'::uuid, 'Freight', 174.26)->'charge'->>'id') as c1 \gset
select public.so_charge_set(:'d1'::uuid, 'Freight', 174.26, :'c1'::uuid, null, null, null, 50, null) as r \gset n1_
select (public.so_charge_set(:'d2'::uuid, 'Freight', 110.50, null, null, null, null, 50, null)->'charge'->>'id') as c2 \gset
select (public.so_charge_set(:'d3'::uuid, 'Freight', 100, null, null, null, null, 50, null)->'charge'->>'id') as c3 \gset
reset role;
select pg_temp.chk('N1 D1 174.26 · 13% · 50%: charge row discount 87.13 · net 87.13 · tax totals charges_amount 174.26 · charges_tax 22.65 · discount 87.13 · discount_tax 11.33 · tax 11.32 · net 87.13', (:'n1_r'::jsonb->'charge'->>'discount') || '/' || (:'n1_r'::jsonb->'charge'->>'net') || '/' || (pg_temp.tt(:'d1'::uuid)->>'charges_amount') || '/' || (pg_temp.tt(:'d1'::uuid)->>'charges_tax') || '/' || (pg_temp.tt(:'d1'::uuid)->>'charges_discount_amount') || '/' || (pg_temp.tt(:'d1'::uuid)->>'charges_discount_tax') || '/' || (pg_temp.tt(:'d1'::uuid)->>'tax') || '/' || (pg_temp.tt(:'d1'::uuid)->>'charges_net_amount'), '87.13/87.13/174.26/22.65/87.13/11.33/11.32/87.13');
select pg_temp.chk('N1b D1 charge_discounts row: kind charge_discount · amount −87.13 · tax −11.33 · pct 50 · taxable 87.13 · total 98.45', (select (c->>'kind') || '/' || (c->>'amount') || '/' || (c->>'tax') || '/' || (c->>'discount_pct') from jsonb_array_elements(public.so_tax_preview(:'d1'::uuid, null, null, 'ordered')->'charge_discounts') c) || '/' || (pg_temp.tt(:'d1'::uuid)->>'taxable_amount') || '/' || (pg_temp.tt(:'d1'::uuid)->>'total'), 'charge_discount/-87.13/-11.33/50/87.13/98.45');
select pg_temp.chk('N1c D1 so_detail totals: charges_total 174.26 (gross) · charges_discount_amount 87.13 · charges_net_total 87.13 · order_total 87.13 · with tax 98.45 · charges[0].discount/net', (pg_temp.dt(:'d1'::uuid)->>'charges_total') || '/' || (pg_temp.dt(:'d1'::uuid)->>'charges_discount_amount') || '/' || (pg_temp.dt(:'d1'::uuid)->>'charges_net_total') || '/' || (pg_temp.dt(:'d1'::uuid)->>'order_total') || '/' || (pg_temp.dt(:'d1'::uuid)->>'order_total_with_tax') || '/' || (public.so_detail(:'d1'::uuid)->'charges'->0->>'discount') || '/' || (public.so_detail(:'d1'::uuid)->'charges'->0->>'net'), '174.26/87.13/87.13/87.13/98.45/87.13/87.13');
select pg_temp.chk('N1d D1 so_totals_many row: charges_total · charges_discount_amount · tax · order_total · with tax', (select trim_scale(charges_total) || '/' || trim_scale(charges_discount_amount) || '/' || trim_scale(tax) || '/' || trim_scale(order_total) || '/' || trim_scale(order_total_with_tax) from public.so_totals_many(array[:'d1'::uuid])), '174.26/87.13/11.32/87.13/98.45');
select pg_temp.chk('N2 D2 110.50 · 5% · 50%: charges_tax 5.53 · discount_tax 2.76 · tax 2.77 (net would be 2.76)', (pg_temp.tt(:'d2'::uuid)->>'charges_tax') || '/' || (pg_temp.tt(:'d2'::uuid)->>'charges_discount_tax') || '/' || (pg_temp.tt(:'d2'::uuid)->>'tax'), '5.53/2.76/2.77');
select pg_temp.chk('N3 D3 100 · 13% · 50%: tax 6.50 · discount 50', (pg_temp.tt(:'d3'::uuid)->>'tax') || '/' || (pg_temp.tt(:'d3'::uuid)->>'charges_discount_amount'), '6.50/50.00');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_charge_set(:'d3'::uuid, 'Freight', 100, :'c3'::uuid, null, null, null, 100, null) as r \gset n3b_
reset role;
select pg_temp.chk('N3b D3 100% = free shipping: net 0 · tax 0 · charges_tax 13.00 − discount_tax 13.00 · taxable 0 · total 0', (:'n3b_r'::jsonb->'charge'->>'net') || '/' || (pg_temp.tt(:'d3'::uuid)->>'tax') || '/' || (pg_temp.tt(:'d3'::uuid)->>'charges_tax') || '/' || (pg_temp.tt(:'d3'::uuid)->>'charges_discount_tax') || '/' || (pg_temp.tt(:'d3'::uuid)->>'taxable_amount') || '/' || (pg_temp.tt(:'d3'::uuid)->>'total'), '0.00/0.00/13.00/13.00/0.00/0.00');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_charge_set(:'d3'::uuid, 'Freight', 100, :'c3'::uuid, null, null, null, null, 30) as r \gset n3c_
reset role;
select pg_temp.chk('N3c D3 amount form 30: discount 30 · net 70 · tax 13.00 − 3.90 = 9.10 · pct null', (:'n3c_r'::jsonb->'charge'->>'discount') || '/' || (:'n3c_r'::jsonb->'charge'->>'net') || '/' || (pg_temp.tt(:'d3'::uuid)->>'tax') || '/' || coalesce(:'n3c_r'::jsonb->'charge'->>'discount_pct', 'null'), '30/70/9.10/null');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_charge_set(:'d3'::uuid, 'Freight', 100, :'c3'::uuid) as r \gset n3d_
reset role;
select pg_temp.chk('N3d so_charge_set without discount args = discount removed (whole-shape update)', coalesce(:'n3d_r'::jsonb->'charge'->>'discount_amount', 'null') || '/' || (:'n3d_r'::jsonb->'charge'->>'discount') || '/' || (pg_temp.tt(:'d3'::uuid)->>'tax'), 'null/0/13.00');

-- ═══ K 판정 356 막기 — so_charge_set · 표 CHECK ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Freight'', 100, %L::uuid, null, null, null, 50, 30)', :'d3', :'c3')) as k1 \gset
select pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Freight'', 100, %L::uuid, null, null, null, 0, null)', :'d3', :'c3')) as k2 \gset
select pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Freight'', 100, %L::uuid, null, null, null, 150, null)', :'d3', :'c3')) as k3 \gset
select pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Freight'', 100, %L::uuid, null, null, null, null, 120)', :'d3', :'c3')) as k4 \gset
select pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Freight'', 100, %L::uuid, null, null, null, null, 0)', :'d3', :'c3')) as k5 \gset
select pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Freight'', 20, %L::uuid, null, null, null, null, 30)', :'d3', :'c3')) as k6 \gset
reset role;
select pg_temp.chk('K1 both → refused', :'k1', 'Give a discount % or an amount, not both — nothing was saved');
select pg_temp.chk('K2 pct 0 · K3 pct 150 → refused', :'k2' || ' | ' || :'k3', 'Discount % must be above 0 and at most 100 — nothing was saved | Discount % must be above 0 and at most 100 — nothing was saved');
select pg_temp.chk('K4 amount 120 > charge 100 · K6 charge lowered to 20 under a 30 discount → refused', :'k4' || ' | ' || :'k6', 'The discount cannot be more than the charge — nothing was saved | The discount cannot be more than the charge — nothing was saved');
select pg_temp.chk('K5 amount 0 → refused', :'k5', 'The discount amount must be above 0 — nothing was saved');
savepoint sp;
select pg_temp.try(format('update public.so_charge set discount_pct = 0 where id = %L::uuid', :'c3')) as k7 \gset
rollback to savepoint sp;
savepoint sp;
select pg_temp.try(format('update public.so_charge set discount_pct = 10, discount_amount = 5 where id = %L::uuid', :'c3')) as k8 \gset
rollback to savepoint sp;
savepoint sp;
select pg_temp.try(format('update public.so_charge set discount_amount = 500 where id = %L::uuid', :'c3')) as k9 \gset
rollback to savepoint sp;
select pg_temp.chk('K7-9 table CHECKs catch direct writes (pct 0 · both · amount > charge)', (:'k7' like '%so_charge_discount_pct_ck%')::text || '/' || (:'k8' like '%so_charge_discount_pair_ck%')::text || '/' || (:'k9' like '%so_charge_discount_amount_ck%')::text, 'true/true/true');
select pg_temp.chk('K10 D3 charge unchanged after the refusals (amount 100 · no discount)', (select trim_scale(amount)::text || '/' || coalesce(discount_pct::text, 'null') || '/' || coalesce(discount_amount::text, 'null') from public.so_charge where id = :'c3'::uuid), '100/null/null');

-- ═══ F so_finalize 미리 보기(p_commit false · picks 직접 · 번호 무접촉) — P1 packed · 운임 100 · 금액형 할인 30 ═══
\set picks '[{"line_id":"' :p1_line '","bin":"A","qty":1}]'
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_finalize(jsonb_build_array(jsonb_build_object('so_id', :'p1', 'picks', :'picks'::jsonb, 'charges', jsonb_build_array(jsonb_build_object('charge_id', :'p1_chg', 'name', 'Freight', 'amount', 100)))), false) as r \gset f1_
select public.so_finalize(jsonb_build_array(jsonb_build_object('so_id', :'p1', 'picks', :'picks'::jsonb, 'charges', jsonb_build_array(jsonb_build_object('charge_id', :'p1_chg', 'name', 'Freight', 'amount', 100, 'discount_pct', 50, 'discount_amount', '')))), false) as r \gset f2_
select public.so_finalize(jsonb_build_array(jsonb_build_object('so_id', :'p1', 'picks', :'picks'::jsonb, 'charges', jsonb_build_array(jsonb_build_object('charge_id', :'p1_chg', 'name', 'Freight', 'amount', 100, 'discount_amount', '')))), false) as r \gset f3_
select pg_temp.try(format('select public.so_finalize(jsonb_build_array(jsonb_build_object(''so_id'', %L, ''picks'', %L::jsonb, ''charges'', jsonb_build_array(jsonb_build_object(''charge_id'', %L, ''name'', ''Freight'', ''amount'', 20)))), false)', :'p1', :'picks', :'p1_chg')) as f4 \gset
select public.so_finalize(jsonb_build_array(jsonb_build_object('so_id', :'p1', 'picks', :'picks'::jsonb, 'charges', jsonb_build_array(jsonb_build_object('charge_id', :'p1_chg', 'name', 'Freight', 'amount', 100), jsonb_build_object('name', 'Extra freight', 'amount', 10, 'discount_pct', 10)))), false) as r \gset f5_
select pg_temp.try(format('select public.so_finalize(jsonb_build_array(jsonb_build_object(''so_id'', %L, ''picks'', %L::jsonb, ''charges'', jsonb_build_array(jsonb_build_object(''charge_id'', %L, ''name'', ''Freight'', ''amount'', 100, ''discount_pct'', 50, ''discount_amount'', 10)))), false)', :'p1', :'picks', :'p1_chg')) as f6 \gset
select pg_temp.try(format('select public.so_finalize(jsonb_build_array(jsonb_build_object(''so_id'', %L, ''picks'', %L::jsonb, ''charges'', jsonb_build_array(jsonb_build_object(''charge_id'', %L, ''name'', ''Freight'', ''amount'', 100, ''discount_pct'', ''abc'')))), false)', :'p1', :'picks', :'p1_chg')) as f7 \gset
reset role;
select pg_temp.chk('F1 no discount keys → existing kept: discount_amount 30 · discount 30 · net 70 · preview', (:'f1_r'::jsonb->'orders'->0->'charges'->0->>'discount_amount') || '/' || (:'f1_r'::jsonb->'orders'->0->'charges'->0->>'discount') || '/' || (:'f1_r'::jsonb->'orders'->0->'charges'->0->>'net') || '/' || (:'f1_r'::jsonb->'orders'->0->'charges'->0->>'preview') || '/' || (:'f1_r'::jsonb->>'committed'), '30/30/70/true/false');
select pg_temp.chk('F2 discount_pct 50 + discount_amount "" → pct 50 · amount null · discount 50 · net 50', (:'f2_r'::jsonb->'orders'->0->'charges'->0->>'discount_pct') || '/' || coalesce(:'f2_r'::jsonb->'orders'->0->'charges'->0->>'discount_amount', 'null') || '/' || (:'f2_r'::jsonb->'orders'->0->'charges'->0->>'discount') || '/' || (:'f2_r'::jsonb->'orders'->0->'charges'->0->>'net'), '50/null/50.00/50.00');
select pg_temp.chk('F3 discount_amount "" alone → cleared: discount 0 · net 100', (:'f3_r'::jsonb->'orders'->0->'charges'->0->>'discount') || '/' || (:'f3_r'::jsonb->'orders'->0->'charges'->0->>'net'), '0/100');
select pg_temp.chk('F4 amount lowered to 20 under the kept 30 discount → refused with order · charge prefix', :'f4', 'Order SO-79955: charge Freight: The discount cannot be more than the charge — nothing was saved');
select pg_temp.chk('F5 second charge without charge_id beside an existing one → warning charge_added_beside_existing · its own 10% preview discount 1.00', (select count(*) from jsonb_array_elements_text(:'f5_r'::jsonb->'warnings') w where w = 'charge_added_beside_existing:SO-79955')::text || '/' || (:'f5_r'::jsonb->'orders'->0->'charges'->1->>'discount') || '/' || (:'f5_r'::jsonb->'orders'->0->'charges'->1->>'net'), '1/1.00/9.00');
select pg_temp.chk('F6 both keys → refused · F7 non-number → refused', :'f6' || ' | ' || :'f7', 'Order SO-79955: charge Freight: Give a discount % or an amount, not both — nothing was saved | Order SO-79955: charge Freight discount needs a number — nothing was saved');
select pg_temp.chk('F8 previews wrote nothing: P1 charge still amount 100 · discount_amount 30 · one charge', (select trim_scale(amount)::text || '/' || trim_scale(discount_amount)::text || '/' || (select count(*) from public.so_charge where so_id = :'p1'::uuid) from public.so_charge where id = :'p1_chg'::uuid), '100/30/1');
select pg_temp.chk('F9 P1 shipped-basis totals via so_detail (packed → ordered basis): charges 100 · discount 30 · tax 13 − 3.90 + 13 (line) = 22.10 · with tax 192.10', (pg_temp.dt(:'p1'::uuid)->>'charges_total') || '/' || (pg_temp.dt(:'p1'::uuid)->>'charges_discount_amount') || '/' || (pg_temp.dt(:'p1'::uuid)->>'tax') || '/' || (pg_temp.dt(:'p1'::uuid)->>'order_total_with_tax'), '100/30/22.10/192.10');

-- ═══ O 판정 357-4 — D4 오더 할인 10%(manual) + 제품 100 + 운임 100 할인 50 → 오더 할인 금액 10 그대로 · lines_total 100 · order_total 140 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select (public.so_charge_set(:'d4'::uuid, 'Freight', 100, null, null, null, null, 50, null)->'charge'->>'id') as c4 \gset
reset role;
select pg_temp.chk('O1 D4: order_discount_amount 10 · lines_total 100 · charges 100 · charges_discount 50 · order_total 140 · tax (90 + 50) × 13% = 11.70 + 6.50 = 18.20 · with tax 158.20', (pg_temp.dt(:'d4'::uuid)->>'order_discount_amount') || '/' || (pg_temp.dt(:'d4'::uuid)->>'lines_total') || '/' || (pg_temp.dt(:'d4'::uuid)->>'charges_total') || '/' || (pg_temp.dt(:'d4'::uuid)->>'charges_discount_amount') || '/' || (pg_temp.dt(:'d4'::uuid)->>'order_total') || '/' || (pg_temp.dt(:'d4'::uuid)->>'tax') || '/' || (pg_temp.dt(:'d4'::uuid)->>'order_total_with_tax'), '10.00/100.00/100/50.00/140.00/18.20/158.20');
select pg_temp.chk('O2 so_tax_preview order_discount amount −10 · tax −1.30 unchanged by the freight discount · lines_amount 100', (pg_temp.tt(:'d4'::uuid)->>'order_discount_amount') || '/' || (pg_temp.tt(:'d4'::uuid)->>'order_discount_tax') || '/' || (pg_temp.tt(:'d4'::uuid)->>'lines_amount'), '-10.00/-1.30/100.00');

-- ═══ P so_proforma — D1 (draft · not invoiced) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_proforma(array[:'d1'::uuid]) as r \gset pf_
reset role;
select pg_temp.chk('P1 proforma D1: charges_amount 174.26 · charges_discount_amount 87.13 · taxable 87.13 · tax 11.32 · total 98.45 · balance_due 98.45 · orders[0].charge_discounts 1 row', (:'pf_r'::jsonb->'totals'->>'charges_amount') || '/' || (:'pf_r'::jsonb->'totals'->>'charges_discount_amount') || '/' || (:'pf_r'::jsonb->'totals'->>'taxable_amount') || '/' || (:'pf_r'::jsonb->'totals'->>'tax') || '/' || (:'pf_r'::jsonb->'totals'->>'total') || '/' || (:'pf_r'::jsonb->'totals'->>'balance_due') || '/' || jsonb_array_length(:'pf_r'::jsonb->'orders'->0->'charge_discounts'), '174.26/87.13/87.13/11.32/98.45/98.45/1');

-- ═══ V 발행 틈 가드 — 가짜 인보이스(번호 직접 · 시퀀스 무접촉) 에 D1(할인 있음) 을 달면 거부 · D5(할인 없음) 는 통과 ═══
savepoint sp;
insert into public.so_invoice (invoice_number, bill_to_customer_id, issued_on, currency_id) values ('79999', :'cust'::uuid, public.ims_today(), :'cad'::uuid) returning id::text as inv \gset
select pg_temp.try(format('insert into public.so_invoice_order (invoice_id, so_id, so_number, tax_rule_id, tax_rule, rate_pct, tax_source) values (%L::uuid, %L::uuid, ''SO-79951'', %L::uuid, %L, 13, ''manual'')', :'inv', :'d1', :'r13', :'r13_name')) as v1 \gset
select pg_temp.try(format('insert into public.so_invoice_order (invoice_id, so_id, so_number, tax_rule_id, tax_rule, rate_pct, tax_source) values (%L::uuid, %L::uuid, ''SO-79956'', %L::uuid, %L, 13, ''manual'')', :'inv', :'d5', :'r13', :'r13_name')) as v2 \gset
rollback to savepoint sp;
select pg_temp.chk('V1 invoice-order link for an order with a freight discount → refused by the guard · V2 order without discount → passes', (:'v1' like 'Order SO-79951 has a freight discount%')::text || '/' || :'v2', 'true/no-error');

-- ═══ S 같음(가짜 재료가 든 뒤 · 할인 있는 오더 넷 포함) · G 모양 · 권한 · 무접촉 ═══
select pg_temp.chk('S1 so_detail.totals = so_totals_many (nine keys · all orders incl. discounted fakes)', pg_temp.same_detail_many(), 'same/' || (select count(*) from public.so));
select pg_temp.chk('G1 so_charge: two columns · three CHECKs (+ amount_ck) · old so_charge_set signature gone · new one authenticated yes · anon no', (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_charge' and column_name in ('discount_pct', 'discount_amount'))::text || '/' || (select count(*) from pg_constraint where conrelid = 'public.so_charge'::regclass and conname in ('so_charge_discount_pair_ck', 'so_charge_discount_pct_ck', 'so_charge_discount_amount_ck', 'so_charge_amount_ck')) || '/' || (to_regprocedure('public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid)') is null)::text || '/' || has_function_privilege('authenticated', 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)', 'execute')::text, '2/4/true/true/false');
select pg_temp.chk('G2 helpers: so_charge_discount authenticated yes · anon no · so_charge_discount_check nobody · guard function nobody · guard trigger attached', has_function_privilege('authenticated', 'public.so_charge_discount(numeric, numeric, numeric)', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_charge_discount(numeric, numeric, numeric)', 'execute')::text || '/' || (has_function_privilege('authenticated', 'public.so_charge_discount_check(numeric, numeric, numeric)', 'execute') or has_function_privilege('anon', 'public.so_charge_discount_check(numeric, numeric, numeric)', 'execute') or has_function_privilege('public', 'public.so_charge_discount_check(numeric, numeric, numeric)', 'execute'))::text || '/' || (has_function_privilege('authenticated', 'public.so_invoice_order_freight_discount_guard()', 'execute') or has_function_privilege('anon', 'public.so_invoice_order_freight_discount_guard()', 'execute') or has_function_privilege('public', 'public.so_invoice_order_freight_discount_guard()', 'execute'))::text || '/' || (select count(*) from pg_trigger where tgrelid = 'public.so_invoice_order'::regclass and tgname = 'so_invoice_order_freight_discount_guard' and tgenabled <> 'D'), 'true/false/false/false/1');
select pg_temp.chk('G3 so_totals_many result has charges_discount_amount after charges_total · one def · invoker stable · authenticated yes · anon no', (pg_get_function_result('public.so_totals_many(uuid[])'::regprocedure) like '%charges_total numeric, charges_discount_amount numeric, surcharge_amount%')::text || '/' || (select count(*) from pg_proc where proname = 'so_totals_many') || '/' || (select (not prosecdef)::text || '/' || provolatile::text from pg_proc where proname = 'so_totals_many') || '/' || has_function_privilege('authenticated', 'public.so_totals_many(uuid[])', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_totals_many(uuid[])', 'execute')::text, 'true/1/true/s/true/false');
select pg_temp.chk('G4 untouched md5 (so_invoice_issue · so_credit_issue · so_credit_prepare · so_charge_remove · so_lines_total = 5) · reissued six all carry fr-1', (select count(*)::text from t_pre t join pg_proc p on p.proname = t.n join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public' where t.n in ('so_invoice_issue', 'so_credit_issue', 'so_credit_prepare', 'so_charge_remove', 'so_lines_total') and md5(p.prosrc) = md5(t.src)) || '/' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_charge_set', 'so_finalize', 'so_tax_preview', 'so_detail', 'so_totals_many', 'so_proforma') and p.prosrc like '%fr-1%'), '5/6');
select pg_temp.chk('G5 so_tax_preview old keys still present on a discounted order (charges_amount gross · charges_tax gross · charges[0] has amount 174.26 and tax 22.65)', (pg_temp.tt(:'d1'::uuid) ? 'charges_amount' and pg_temp.tt(:'d1'::uuid) ? 'charges_tax' and pg_temp.tt(:'d1'::uuid) ? 'taxable_amount')::text || '/' || (public.so_tax_preview(:'d1'::uuid, null, null, 'ordered')->'charges'->0->>'amount') || '/' || (public.so_tax_preview(:'d1'::uuid, null, null, 'ordered')->'charges'->0->>'tax'), 'true/174.26/22.65');
set local role anon;
select pg_temp.try('select public.so_charge_discount(100, 50, null)') as a1 \gset
reset role;
select pg_temp.chk('G6 anon cannot call so_charge_discount (42501 text)', (:'a1' like 'permission denied%')::text, 'true');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select 'seq tail so ' || last_value || ' ' || is_called from public.so_number_seq;
select 'seq tail inv ' || last_value || ' ' || is_called from public.so_invoice_number_seq;
select 'seq tail cr ' || last_value || ' ' || is_called from public.so_credit_number_seq;
