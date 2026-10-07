-- fr-2-verify.sql — 운임 할인 인보이스(판정 352 · 354 · 358) · 무변 · 두 줄 펼치기 · 계정 키 · 취소 · 재발행 · 가드 둘 · CHECK (Asung-IMS · 2026-10-07)
--   기대: 시험 갈래 OK 22 · 확인 갈래(G0 둘 없음) OK 20 · MISMATCH 0(시험 적용 1회차 통과 · 2026-10-07) · 재료는 가짜만(SO-7996x · FR2-* · 가짜 손님 · 직원 · 가짜 크레딧 CR-7999x 는 번호 직접) · 실제 인보이스 · 오더 무접촉
--   ⚠️ 발행은 so_invoice_number_seq 를 당긴다 — 머리에서 읽고 rollback 뒤 greatest(실제 최대, 머리)로 되돌린다(asung-workflow §4 · §49-d 3)
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261007173939_fr_2_freight_discount_invoice.sql -f supabase/tests/fr-2-verify.sql 2>&1 | tee /tmp/fr-2.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다(D-pre 는 확인 갈래에서 새 함수)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
select max(invoice_number)::bigint as inv_max_head from public.so_invoice \gset
\echo '== seq head so' :so_seq_last :so_seq_called 'inv' :inv_seq_last :inv_seq_called '(max invoice' :inv_max_head ') cr' :cr_seq_last :cr_seq_called
select count(*) as n_inv from public.so_invoice \gset
\echo '== invoices on this DB' :n_inv

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create temp table t_pre as
  select p.proname as n, p.prosrc as src from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public'
   and p.proname in ('so_invoice_issue', 'so_invoice_reissue', 'so_invoice_cancel', 'so_invoice_detail', 'so_credit_issue', 'so_credit_prepare', 'so_tax_preview', 'inv_config_guard', 'so_charge_discount');
do $$
declare v_src text;
begin
  select src into v_src from t_pre where n = 'so_invoice_issue';
  execute format('create function public.fr2_pre_issue(p_so_ids uuid[], p_staff uuid, p_issued_on date default null) returns jsonb language plpgsql volatile security invoker set search_path = public, pg_temp as %L', v_src);
end $$;
\if :{?mig}
select pg_temp.chk('G0a so_invoice_issue last def = 20261006000805:966~1221', (select md5(src) from t_pre where n = 'so_invoice_issue'), 'a898a99f4bc4ad49f7f7b2168c8bdc5a');
select pg_temp.chk('G0b fr-1 guard present before trial', (to_regprocedure('public.so_invoice_order_freight_discount_guard()') is not null)::text, 'true');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
-- 정규형: 인보이스 줄(kind|설명|금액|세금|계정|운임 줄) · 머리 합계 · 오더 합계 — 번호 · id · 시각은 뺀다
create function pg_temp.canon_inv(p_inv uuid) returns text language sql as $$
  select coalesce((select string_agg(l.kind || '|' || l.description || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount) || '|' || coalesce(l.account_code, '-') || '|' || coalesce(l.so_charge_id::text, '-'), E'\n' order by l.line_no) from public.so_invoice_line l where l.invoice_id = p_inv), '')
         || E'\nH|' || (select trim_scale(i.lines_amount) || '|' || trim_scale(i.order_discount_amount) || '|' || trim_scale(i.charges_amount) || '|' || trim_scale(i.surcharge_amount) || '|' || trim_scale(i.taxable_amount) || '|' || trim_scale(i.tax_amount) || '|' || trim_scale(i.total) || '|' || trim_scale(i.amount_due) from public.so_invoice i where i.id = p_inv)
         || E'\nO|' || (select string_agg(trim_scale(o.lines_amount) || '|' || trim_scale(o.order_discount_amount) || '|' || trim_scale(o.charges_amount) || '|' || trim_scale(o.surcharge_amount) || '|' || trim_scale(o.taxable_amount) || '|' || trim_scale(o.tax_amount) || '|' || trim_scale(o.total), ';' order by o.so_number) from public.so_invoice_order o where o.invoice_id = p_inv)
$$;
create function pg_temp.lines(p_inv uuid) returns text language sql as $$
  select string_agg(l.line_no || ':' || l.kind || '|' || l.description || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount) || '|' || coalesce(l.account_code, '-'), ' ‖ ' order by l.line_no) from public.so_invoice_line l where l.invoice_id = p_inv
$$;
create function pg_temp.head(p_inv uuid) returns text language sql as $$
  select trim_scale(i.lines_amount) || '/' || trim_scale(i.order_discount_amount) || '/' || trim_scale(i.charges_amount) || '/' || trim_scale(i.charges_discount_amount) || '/' || trim_scale(i.taxable_amount) || '/' || trim_scale(i.tax_amount) || '/' || trim_scale(i.total) from public.so_invoice i where i.id = p_inv
$$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'no-error'; exception when others then return sqlerrm; end $$;

-- ═══ 재료 — 직원(manager · sales) · 손님 · 제품 · HST ON 13% · shipped 가짜 오더 A(할인 없음) · B(174.26 · 50%) · C(100 · 100%) · D(100 · 금액 30) · E(제품 100 + 오더 할인 10% + 운임 100 · 50%) · F(= B · 계정 키 시험) · A2(할인 없음 · 키 시험) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'fr2-manager@test.invalid', 'FR2 Manager', 'manager', '["sales"]'::jsonb) returning id::text as m_id, auth_user_id::text as m_uid \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as tier, name as tier_name from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' limit 1 \gset
select id::text as whx, name as whx_name from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as r13, name as r13_name from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as acc99 from public.ref_account where code = '_99_' \gset
insert into public.ref_brand (name) values ('FR2 Brand') returning id::text as br \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('FR2 Customer', 'manual', :'tier_name', :'whx'::uuid, 0) returning id::text as cust \gset
insert into public.product (sku, name, source, brand_id) values ('FR2-P', 'FR2 Product P', 'manual', :'br'::uuid) returning id::text as pp \gset
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79961', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR2 Customer', now(), now(), null, null) returning id::text as o_a \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79962', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR2 Customer', now(), now(), null, null) returning id::text as o_b \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79963', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR2 Customer', now(), now(), null, null) returning id::text as o_c \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79964', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR2 Customer', now(), now(), null, null) returning id::text as o_d \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79965', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR2 Customer', now(), now(), 10, 'manual') returning id::text as o_e \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79966', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR2 Customer', now(), now(), null, null) returning id::text as o_f \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79967', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR2 Customer', now(), now(), null, null) returning id::text as o_a2 \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, list_price, unit_price) values (:'o_a'::uuid, 1, :'pp'::uuid, 'FR2-P', 'FR2 Product P', 1, 1, 1, 100, 100);
insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, list_price, unit_price) values (:'o_e'::uuid, 1, :'pp'::uuid, 'FR2-P', 'FR2 Product P', 1, 1, 1, 100, 100);
insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, list_price, unit_price) values (:'o_a2'::uuid, 1, :'pp'::uuid, 'FR2-P', 'FR2 Product P', 1, 1, 1, 100, 100);
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code) values (:'o_a'::uuid, 1, 'Freight', 50, :'r13_name', :'acc99'::uuid, '_99_') returning id::text as ch_a \gset
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code, discount_pct) values (:'o_b'::uuid, 1, 'Freight', 174.26, :'r13_name', :'acc99'::uuid, '_99_', 50) returning id::text as ch_b \gset
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code, discount_pct) values (:'o_c'::uuid, 1, 'Freight', 100, :'r13_name', :'acc99'::uuid, '_99_', 100);
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code, discount_amount) values (:'o_d'::uuid, 1, 'Freight', 100, :'r13_name', :'acc99'::uuid, '_99_', 30);
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code, discount_pct) values (:'o_e'::uuid, 1, 'Freight', 100, :'r13_name', :'acc99'::uuid, '_99_', 50);
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code, discount_pct) values (:'o_f'::uuid, 1, 'Freight', 174.26, :'r13_name', :'acc99'::uuid, '_99_', 50);
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code) values (:'o_a2'::uuid, 1, 'Freight', 20, :'r13_name', :'acc99'::uuid, '_99_');
set local session_replication_role = origin;

-- ═══ U 무변 — 할인 없는 A: 옛 함수와 새 함수의 발행 결과(줄 · 머리 · 오더 · 번호 뺌)가 같다(savepoint 로 옛 것은 되돌림) ═══
savepoint sp;
select (public.fr2_pre_issue(array[:'o_a'::uuid], :'m_id'::uuid)->>'invoice_id') as inv_pre \gset
select pg_temp.canon_inv(:'inv_pre'::uuid) as c_pre \gset
rollback to savepoint sp;
select public.so_invoice_issue(array[:'o_a'::uuid], :'m_id'::uuid) as r \gset ia_
select (:'ia_r'::jsonb->>'invoice_id') as inv_a \gset
select pg_temp.chk('U1 order A (no discount): new issue = old issue (lines · header · order totals · ids/numbers excluded) · charges_discount_amount 0', (pg_temp.canon_inv(:'inv_a'::uuid) = :'c_pre')::text || '/' || (select trim_scale(charges_discount_amount) from public.so_invoice where id = :'inv_a'::uuid), 'true/0');
select pg_temp.chk('U1b A lines: product 100/13 · charge 50/6.50 · header 100/0/50/0/150/19.50/169.50', pg_temp.lines(:'inv_a'::uuid) || ' » ' || pg_temp.head(:'inv_a'::uuid), '1:product|FR2 Product P|100|13|- ‖ 2:charge|Freight|50|6.5|_99_ » 100/0/50/0/150/19.5/169.5');

-- ═══ N 판정 354 수 그대로 인보이스에 — B · C · D · E ═══
select public.so_invoice_issue(array[:'o_b'::uuid], :'m_id'::uuid) as r \gset ib_
select (:'ib_r'::jsonb->>'invoice_id') as inv_b \gset
select pg_temp.chk('N1 B 174.26 · 13% · 50%: line1 charge 174.26/22.65 _99_ · line2 charge_discount "Freight discount 50%" −87.13/−11.33 _6_ · right after the charge line · same so_charge_id', pg_temp.lines(:'inv_b'::uuid) || ' » ' || (select (count(*) = 2 and bool_and(so_charge_id = :'ch_b'::uuid))::text from public.so_invoice_line where invoice_id = :'inv_b'::uuid), '1:charge|Freight|174.26|22.65|_99_ ‖ 2:charge_discount|Freight discount 50%|-87.13|-11.33|_6_ » true');
select pg_temp.chk('N1b B header: lines 0 · od 0 · charges 174.26 · charges_discount 87.13 · taxable 87.13 · tax 11.32 · total 98.45 · return totals.charges_discount_amount · order row', pg_temp.head(:'inv_b'::uuid) || ' » ' || (:'ib_r'::jsonb->'totals'->>'charges_discount_amount') || ' » ' || (select trim_scale(o.charges_amount) || '/' || trim_scale(o.charges_discount_amount) || '/' || trim_scale(o.taxable_amount) || '/' || trim_scale(o.tax_amount) || '/' || trim_scale(o.total) from public.so_invoice_order o where o.invoice_id = :'inv_b'::uuid), '0/0/174.26/87.13/87.13/11.32/98.45 » 87.13 » 174.26/87.13/87.13/11.32/98.45');
select public.so_invoice_issue(array[:'o_c'::uuid], :'m_id'::uuid) as r \gset ic_
select (:'ic_r'::jsonb->>'invoice_id') as inv_c \gset
select pg_temp.chk('N2 C 100% free shipping: charge 100/13 · discount −100/−13 · header taxable 0 · tax 0 · total 0', pg_temp.lines(:'inv_c'::uuid) || ' » ' || pg_temp.head(:'inv_c'::uuid), '1:charge|Freight|100|13|_99_ ‖ 2:charge_discount|Freight discount 100%|-100|-13|_6_ » 0/0/100/100/0/0/0');
select public.so_invoice_issue(array[:'o_d'::uuid], :'m_id'::uuid) as r \gset id_
select (:'id_r'::jsonb->>'invoice_id') as inv_d \gset
select pg_temp.chk('N3 D amount 30: discount line "Freight discount" −30/−3.90 · total 100 − 30 + 13 − 3.90 = 79.10', pg_temp.lines(:'inv_d'::uuid) || ' » ' || pg_temp.head(:'inv_d'::uuid), '1:charge|Freight|100|13|_99_ ‖ 2:charge_discount|Freight discount|-30|-3.9|_6_ » 0/0/100/30/70/9.1/79.1');
select public.so_invoice_issue(array[:'o_e'::uuid], :'m_id'::uuid) as r \gset ie_
select (:'ie_r'::jsonb->>'invoice_id') as inv_e \gset
select pg_temp.chk('N4 E (357-4): product 100/13 · order_discount −10/−1.30 unchanged · charge 100/13 · charge_discount −50/−6.50 · header 100/−10/100/50/140/18.20/158.20', pg_temp.lines(:'inv_e'::uuid) || ' » ' || pg_temp.head(:'inv_e'::uuid), '1:product|FR2 Product P|100|13|- ‖ 2:order_discount|Order discount 10%|-10|-1.3|- ‖ 3:charge|Freight|100|13|_99_ ‖ 4:charge_discount|Freight discount 50%|-50|-6.5|_6_ » 100/-10/100/50/140/18.2/158.2');
select pg_temp.chk('N5 orders B · C · D · E now fulfilled (invoice CHECKs held)', (select count(*) filter (where status = 'fulfilled') || '/' || count(*) from public.so where id in (:'o_b'::uuid, :'o_c'::uuid, :'o_d'::uuid, :'o_e'::uuid)), '4/4');

-- ═══ K 계정 키 — 비움 · 없는 코드 · 꺼진 계정 → 할인 운임 오더(F)만 막힘 · 할인 없는 오더(A2)는 통과 ═══
savepoint sp;
update public.inv_config set value = '' where key = 'so_freight_discount_account_code';
select pg_temp.try(format('select public.so_invoice_issue(array[%L::uuid], %L::uuid)', :'o_f', :'m_id')) as k1 \gset
select pg_temp.try(format('select public.so_invoice_issue(array[%L::uuid], %L::uuid)', :'o_a2', :'m_id')) as k1b \gset
rollback to savepoint sp;
savepoint sp;
update public.inv_config set value = '_ZZ_' where key = 'so_freight_discount_account_code';
select pg_temp.try(format('select public.so_invoice_issue(array[%L::uuid], %L::uuid)', :'o_f', :'m_id')) as k2 \gset
rollback to savepoint sp;
savepoint sp;
update public.ref_account set is_active = false where code = '_6_';
select pg_temp.try(format('select public.so_invoice_issue(array[%L::uuid], %L::uuid)', :'o_f', :'m_id')) as k3 \gset
rollback to savepoint sp;
select pg_temp.chk('K1 key blank → discounted order refused · undiscounted order passes', :'k1' || ' | ' || :'k1b', 'Freight discount account is not set — set inv_config so_freight_discount_account_code (e.g. _6_ Sales Discounts) before invoicing an order with a freight discount — nothing was saved | no-error');
select pg_temp.chk('K2 unknown code · K3 inactive account → refused', :'k2' || ' | ' || :'k3', 'Freight discount account _ZZ_ (inv_config so_freight_discount_account_code) is not in the chart of accounts — nothing was saved | Freight discount account _6_ (Sales Discounts) is inactive — pick an active account in inv_config so_freight_discount_account_code — nothing was saved');
select pg_temp.chk('K4 inv_config key present = _6_ · F still shipped (refusals wrote nothing)', (select value from public.inv_config where key = 'so_freight_discount_account_code') || '/' || (select status from public.so where id = :'o_f'::uuid), '_6_/shipped');

-- ═══ R 취소 · 재발행 — B: 취소하면 줄은 취소된 인보이스에 남는다 · 오더는 shipped 로 · 재발행하면 새 인보이스에 할인 줄 다시 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_invoice_cancel(:'inv_b'::uuid, 'fr-2 verify') as r \gset rc_
select public.so_invoice_reissue(array[:'o_b'::uuid]) as r \gset rr_
select public.so_invoice_detail((:'rr_r'::jsonb->>'invoice_id')::uuid) as d \gset rd_
reset role;
select pg_temp.chk('R1 cancel B: status cancelled · its 2 lines still there (charge + charge_discount) · order back to shipped', (:'rc_r'::jsonb->>'status') || '/' || (select count(*) || '-' || count(*) filter (where kind = 'charge_discount') from public.so_invoice_line where invoice_id = :'inv_b'::uuid) || '/' || (:'rc_r'::jsonb->>'orders_back_to_shipped'), 'cancelled/2-1/1');
select pg_temp.chk('R2 reissue B: new invoice · lines identical to the first issue · header 87.13 discount', (:'rr_r'::jsonb->>'invoice_id' <> :'inv_b')::text || '/' || (pg_temp.lines((:'rr_r'::jsonb->>'invoice_id')::uuid) = pg_temp.lines(:'inv_b'::uuid))::text || '/' || pg_temp.head((:'rr_r'::jsonb->>'invoice_id')::uuid), 'true/true/0/0/174.26/87.13/87.13/11.32/98.45');
select pg_temp.chk('R3 so_invoice_detail (as staff · invoker): invoice.charges_discount_amount 87.13 via the view · lines kinds charge,charge_discount · discount line so_charge_id = the charge', (:'rd_d'::jsonb->'invoice'->>'charges_discount_amount') || '/' || (select string_agg(l->>'kind', ',' order by (l->>'line_no')::int) from jsonb_array_elements(:'rd_d'::jsonb->'lines') l) || '/' || (select (l->>'so_charge_id' = :'ch_b')::text from jsonb_array_elements(:'rd_d'::jsonb->'lines') l where l->>'kind' = 'charge_discount'), '87.13/charge,charge_discount/true');
select (:'rr_r'::jsonb->>'invoice_id') as inv_b2 \gset

-- ═══ V 가드 — fr-1 발행 가드 없음 · 크레딧 가드: 할인 운임 줄 freight 크레딧 거부 · 할인 없는 인보이스(A)의 운임 크레딧 통과(가짜 크레딧 · 번호 직접) ═══
select pg_temp.chk('V1 fr-1 guard gone (function · trigger)', (to_regprocedure('public.so_invoice_order_freight_discount_guard()') is null)::text || '/' || (select count(*) from pg_trigger where tgname = 'so_invoice_order_freight_discount_guard'), 'true/0');
select l.id::text as il_b from public.so_invoice_line l where l.invoice_id = :'inv_b2'::uuid and l.kind = 'charge' \gset
select l.id::text as il_a from public.so_invoice_line l where l.invoice_id = :'inv_a'::uuid and l.kind = 'charge' \gset
savepoint sp;
insert into public.so_credit (credit_number, customer_id, currency_id, reason, warehouse_id, issued_on, invoice_id) values ('CR-79999', :'cust'::uuid, :'cad'::uuid, 'other', :'whx'::uuid, public.ims_today(), :'inv_b2'::uuid) returning id::text as cr_b \gset
select pg_temp.try(format('insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, amount, tax_amount) values (%L::uuid, 1, ''freight'', %L::uuid, 10, 1.30)', :'cr_b', :'il_b')) as v2 \gset
rollback to savepoint sp;
savepoint sp;
insert into public.so_credit (credit_number, customer_id, currency_id, reason, warehouse_id, issued_on, invoice_id) values ('CR-79998', :'cust'::uuid, :'cad'::uuid, 'other', :'whx'::uuid, public.ims_today(), :'inv_a'::uuid) returning id::text as cr_a \gset
select pg_temp.try(format('insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, amount, tax_amount) values (%L::uuid, 1, ''freight'', %L::uuid, 10, 1.30)', :'cr_a', :'il_a')) as v3 \gset
rollback to savepoint sp;
select pg_temp.chk('V2 freight credit line on a discounted charge line → refused by the credit guard · V3 on an undiscounted one → passes', (:'v2' like 'Invoice line % is a freight line that carries a freight discount%')::text || '/' || :'v3', 'true/no-error');

-- ═══ C CHECK 셋 + 머리 · 오더 — 직접 쓰기 ═══
savepoint sp;
select pg_temp.try(format('insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, amount, tax_amount) values (%L::uuid, (select id from public.so_invoice_order where invoice_id = %L::uuid), 99, ''charge_discount'', %L::uuid, ''x'', 5, 0)', :'inv_b2', :'inv_b2', :'ch_b')) as c1 \gset
rollback to savepoint sp;
savepoint sp;
select pg_temp.try(format('insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, description, amount, tax_amount) values (%L::uuid, (select id from public.so_invoice_order where invoice_id = %L::uuid), 99, ''charge_discount'', ''x'', -5, 0)', :'inv_b2', :'inv_b2')) as c2 \gset
rollback to savepoint sp;
savepoint sp;
select pg_temp.try(format('insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, description, amount, tax_amount) values (%L::uuid, (select id from public.so_invoice_order where invoice_id = %L::uuid), 99, ''bogus'', ''x'', 5, 0)', :'inv_b2', :'inv_b2')) as c3 \gset
rollback to savepoint sp;
savepoint sp;
select pg_temp.try(format('update public.so_invoice set charges_discount_amount = charges_discount_amount + 1 where id = %L::uuid', :'inv_b2')) as c4 \gset
rollback to savepoint sp;
savepoint sp;
select pg_temp.try(format('update public.so_invoice_order set charges_discount_amount = charges_discount_amount + 1 where invoice_id = %L::uuid', :'inv_b2')) as c5 \gset
rollback to savepoint sp;
select pg_temp.chk('C1 positive charge_discount → amount_ck · C2 without so_charge_id → charge_ck · C3 unknown kind → kind_ck · C4 header taxable_ck · C5 order taxable_ck', (:'c1' like '%so_invoice_line_amount_ck%')::text || '/' || (:'c2' like '%so_invoice_line_charge_ck%')::text || '/' || (:'c3' like '%so_invoice_line_kind_ck%')::text || '/' || (:'c4' like '%so_invoice_taxable_ck%')::text || '/' || (:'c5' like '%so_invoice_order_taxable_ck%')::text, 'true/true/true/true/true');

-- ═══ G 무접촉 · 모양 · 권한 ═══
select pg_temp.chk('G1 untouched md5 (so_invoice_reissue · cancel · detail · so_credit_issue · so_credit_prepare · so_tax_preview · inv_config_guard · so_charge_discount = 8) · so_invoice_issue carries fr-2', (select count(*)::text from t_pre t join pg_proc p on p.proname = t.n join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public' where t.n <> 'so_invoice_issue' and md5(p.prosrc) = md5(t.src)) || '/' || (select (p.prosrc like '%fr-2%')::text from pg_proc p where p.proname = 'so_invoice_issue'), '8/true');
select pg_temp.chk('G2 so_invoice_issue acl unchanged (authenticated no · anon no) · credit guard function nobody · view security_invoker · view last column charges_discount_amount', has_function_privilege('authenticated', 'public.so_invoice_issue(uuid[], uuid, date)', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_invoice_issue(uuid[], uuid, date)', 'execute')::text || '/' || (has_function_privilege('authenticated', 'public.so_credit_line_freight_discount_guard()', 'execute') or has_function_privilege('anon', 'public.so_credit_line_freight_discount_guard()', 'execute') or has_function_privilege('public', 'public.so_credit_line_freight_discount_guard()', 'execute'))::text || '/' || (select ('security_invoker=true' = any(reloptions))::text from pg_class where relname = 'so_invoice_list') || '/' || (select attname from pg_attribute where attrelid = 'public.so_invoice_list'::regclass and attnum = (select max(attnum) from pg_attribute where attrelid = 'public.so_invoice_list'::regclass and not attisdropped)), 'false/false/false/true/charges_discount_amount');
select pg_temp.chk('G3 so_credit_prepare of invoice B2 lists the charge line but not the discount line (its kind filter · fr-3 decides)', (select string_agg(l->>'kind', ',' order by (l->>'line_no')::int) from jsonb_array_elements(public.so_credit_prepare(:'inv_b2'::uuid)->'lines') l), 'charge');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
select 'inv seq inside (before rollback) ' || last_value || ' ' || is_called from public.so_invoice_number_seq;
rollback;
select setval('public.so_invoice_number_seq', greatest((select max(invoice_number)::bigint from public.so_invoice), :inv_seq_last), true);
select 'seq tail so ' || last_value || ' ' || is_called from public.so_number_seq;
select 'seq tail inv ' || last_value || ' ' || is_called || ' (max invoice ' || (select max(invoice_number) from public.so_invoice) || ' · head ' || :inv_seq_last || ')' from public.so_invoice_number_seq;
select 'seq tail cr ' || last_value || ' ' || is_called from public.so_credit_number_seq;
select 'invoices tail ' || count(*) from public.so_invoice;
