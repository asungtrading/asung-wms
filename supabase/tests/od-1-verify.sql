-- od-1-verify.sql — 손으로 정한 줄(M 줄)은 오더 할인을 안 받는다(판정 532 · 542 · 543 · 544) · 마스터 이름 잠금(판정 538) (Asung-IMS · 2026-10-19 밤)
--   기대: 시험 갈래 OK 50 · 확인 갈래(G0 여덟 없음) OK 42 · MISMATCH 0 (시험 적용 5회차 통과 · 2026-10-19 밤 · 1회차 = 글자 이어 붙이기 `'a' :'b'` → `||` · 2회차 = G5 도우미 `x.line_no` → `(x).line_no` · 3 · 4회차 = 통과했으나 savepoint 안의 chk 셋(S2 · S4 · S5)이 rollback to 로 t_res 에서 빠져 요약 47 — chk 를 rollback to 뒤로 · 전부 검증 파일 쪽 · 마이그레이션 무변)
--   ⚠️ savepoint 안에서는 chk 를 부르지 않는다 — 값은 \gset 으로 받아 rollback to savepoint 뒤에 chk(안 그러면 요약에서 빠진다 · 알림만 남는다)
--   재료는 가짜만(SO-7998x · OD1-* · 가짜 손님 · 직원 · 딜 · 쿠폰 · 마스터 행 다섯) · 실제 오더 · 인보이스 · 크레딧 · 마스터 무접촉(Z 검사)
--   ⚠️ so_invoice_issue · so_credit_issue 가 시퀀스 둘을 당긴다 — 머리에서 읽고 rollback 뒤 greatest(실제 최대, 머리)로 되돌린다(§4 · §49-d 3) · so_number_seq 는 안 당긴다(번호 직접)
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020010711_od_1_manual_lines_order_discount_name_lock.sql -f supabase/tests/od-1-verify.sql 2>&1 | tee /tmp/od-1.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다(R 절의 「전 = 후」는 확인 갈래에서 둘 다 새 함수 — 같은 입력 → 같은 출력)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select max(invoice_number)::bigint as inv_max_head from public.so_invoice \gset
select coalesce(max(substr(credit_number, 4))::bigint, 0) as cr_max_head from public.so_credit \gset
\echo '== seq head so' :so_seq_last :so_seq_called '· inv' :inv_seq_last :inv_seq_called '(max' :inv_max_head ') · cr' :cr_seq_last :cr_seq_called '(max' :cr_max_head ')'
select count(*) as n_inv from public.so_invoice \gset
select count(*) as n_cr from public.so_credit \gset
select count(*) as n_fake_before from public.so where so_number like 'SO-7998%' \gset
\echo '== invoices' :n_inv '· credits' :n_cr '· SO-7998x already present (must be 0):' :n_fake_before

-- 입력(예상값은 전부 이 수에서 식으로 센다 · 손으로 치지 않는다)
\set qa 5
\set pa 100
\set qb 4
\set pb 100
\set qm 2
\set pm 100
\set qn 1
\set ln 100
\set dn 20
\set p1 30
\set p2 45
\set t2min 1000
\set pm_od 10
\set pc 50
\set sa_ord 10
\set sa_shp 6
\set sa_p 100
\set sm_ord 3
\set sm_shp 3
\set sm_p 50
\set sn_ord 2
\set sn_shp 1
\set rate 13

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'no-error'; exception when others then return sqlstate || '|' || sqlerrm; end $$;
create function pg_temp.n(p numeric) returns text language sql immutable as $$ select trim_scale(coalesce(p, 0))::text $$;
create temp table t_pre as
  select p.proname as n, p.prosrc as src from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public'
   and p.proname in ('so_tax_preview', 'so_detail', 'so_totals_many', 'so_credit_issue', 'doc_data_invoice', 'doc_data_invoice_fmt', 'doc_data_so', 'so_invoice_preview',
                     'so_invoice_issue', 'so_proforma', 'so_order_discount', 'so_lines_total', 'so_coupon_pct', 'so_line_total', 'doc_unit_prices', 'so_order_discount_apply', 'so_line_order_discount_repick', 'so_credit_prepare');
-- R 전(前) — 실제 열린 오더(가짜 제외)의 totals 를 \i 앞에서 담는다(200 개씩 · so_totals_many 한도)
create temp table t_ids as select s.id, s.so_number, s.status, s.order_discount_pct,
  exists (select 1 from public.so_line l where l.so_id = s.id and (l.price_override or l.discount_source in ('manual', 'shopify'))) as has_m
  from public.so s where s.status not in ('cancelled', 'fulfilled') and s.so_number not like 'SO-799%';
create temp table t_tot_pre as select * from public.so_totals_many(array[]::uuid[]) where false;
do $$
declare v_ids uuid[]; v_i int;
begin
  select array_agg(id order by id) into v_ids from t_ids;
  for v_i in 1 .. coalesce(cardinality(v_ids), 0) by 200 loop
    insert into t_tot_pre select * from public.so_totals_many(v_ids[v_i : v_i + 199]);
  end loop;
end $$;
select count(*) as real_flag_before from public.so where reprice_suggested_at is not null \gset
select (select count(*) from public.ref_brand) || '/' || (select count(*) from public.ref_category) || '/' || (select count(*) from public.ref_unit) || '/' || (select count(*) from public.ref_payment_term) || '/' || (select count(*) from public.ref_bin) as ref_counts_before \gset
\if :{?mig}
select pg_temp.chk('G0a so_tax_preview last def = 20261019155731:150 (DB prosrc md5)', (select md5(src) from t_pre where n = 'so_tax_preview'), '22d4d43edca7ff4644b289b12e29340b');
select pg_temp.chk('G0b so_detail last def = 20261007171939:577', (select md5(src) from t_pre where n = 'so_detail'), 'bf88869fcd36a30de04a163746dba7aa');
select pg_temp.chk('G0c so_totals_many last def = 20261007171939:688', (select md5(src) from t_pre where n = 'so_totals_many'), '173963bdd9c7efe6871fef07a428dac9');
select pg_temp.chk('G0d so_credit_issue last def = 20261007181109:56', (select md5(src) from t_pre where n = 'so_credit_issue'), 'f8e29cd9cb653d37f90621433c1021d2');
select pg_temp.chk('G0e doc_data_invoice last def = 20261019172034:57', (select md5(src) from t_pre where n = 'doc_data_invoice'), '70988e5d397eba668bcab987953b6767');
select pg_temp.chk('G0f doc_data_invoice_fmt last def = 20261019172034:95', (select md5(src) from t_pre where n = 'doc_data_invoice_fmt'), '29d32a63876a32b3aef47a6e2a7deb84');
select pg_temp.chk('G0g doc_data_so last def = 20261019172034:131', (select md5(src) from t_pre where n = 'doc_data_so'), '3ae93f892769f783aa9f51475ae171aa');
select pg_temp.chk('G0h so_invoice_preview last def = 20261019155731:471', (select md5(src) from t_pre where n = 'so_invoice_preview'), '0312fb2437e64ebf115fe977c4f139bd');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ═══ 재료 — 직원(manager · sales · master) · 손님 · 제품 넷 · HST ON 13% · 오더 딜(꺼진 채 → 손님 걸기 → 켜기 · 단계 둘 0:p1 · t2min:p2) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'od1-manager@test.invalid', 'OD1 Manager', 'manager', '["sales","master"]'::jsonb) returning id::text as m_id, auth_user_id::text as m_uid \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as tier, name as tier_name from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' limit 1 \gset
select id::text as whx, name as whx_name from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as whe from public.ref_warehouse where name = 'Asung - Edmonton' \gset
select id::text as r13, name as r13_name from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
insert into public.ref_brand (name, source) values ('OD1 Brand', 'manual') returning id::text as br \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('OD1 Customer', 'manual', :'tier_name', :'whx'::uuid, 0) returning id::text as cust \gset
insert into public.product (sku, name, source, brand_id) values ('OD1-A', 'OD1 Product A', 'manual', :'br'::uuid) returning id::text as pa_id \gset
insert into public.product (sku, name, source, brand_id) values ('OD1-B', 'OD1 Product B', 'manual', :'br'::uuid) returning id::text as pb_id \gset
insert into public.product (sku, name, source, brand_id) values ('OD1-M', 'OD1 Product M (hand price)', 'manual', :'br'::uuid) returning id::text as pm_id \gset
insert into public.product (sku, name, source, brand_id) values ('OD1-N', 'OD1 Product N (hand discount)', 'manual', :'br'::uuid) returning id::text as pn_id \gset
insert into public.so_deal (name, source, is_active, is_order_level, kind) values ('OD1 Order Deal', 'manual', false, true, 'pct') returning id::text as deal \gset
insert into public.so_deal_customer_rule (deal_id, kind, target, customer_id) values (:'deal'::uuid, 'include', 'customer', :'cust'::uuid);
insert into public.so_deal_tier (deal_id, tier_no, min_amount, pct) values (:'deal'::uuid, 1, 0, :p1), (:'deal'::uuid, 2, :t2min, :p2);
update public.so_deal set is_active = true where id = :'deal'::uuid;
select pg_temp.chk('Z1 real orders flagged (reprice_suggested_at) unchanged by the fake deal', (select count(*)::text from public.so where reprice_suggested_at is not null), :'real_flag_before');

-- ═══ D 초안 — S 줄 둘(A qa×pa · B qb×pb) + 손 단가 줄 M(qm×pm · price_override) → 문턱 = 전부 · 할인 바탕 = S 만 (판정 542 · 543) ═══
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name)
  values ('SO-79981', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'OD1 Customer') returning id::text as d1 \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, list_price, unit_price) values (:'d1'::uuid, 1, :'pa_id'::uuid, 'OD1-A', 'OD1 Product A', 'EA', 1, :qa, :pa, :pa);
insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, list_price, unit_price) values (:'d1'::uuid, 2, :'pb_id'::uuid, 'OD1-B', 'OD1 Product B', 'EA', 1, :qb, :pb, :pb);
insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, list_price, unit_price, price_override) values (:'d1'::uuid, 3, :'pm_id'::uuid, 'OD1-M', 'OD1 Product M (hand price)', 'EA', 1, :qm, :pm, :pm, true) returning id::text as l_m \gset
select public.so_detail(:'d1'::uuid) as d \gset d1_
select public.so_tax_preview(:'d1'::uuid) as t \gset d1_
select pg_temp.chk('D1 threshold counts every line (qa·pa + qb·pb + qm·pm ≥ t2min) → tier 2 picked · source deal', (select trim_scale(s.order_discount_pct)::text || '/' || s.order_discount_source from public.so s where s.id = :'d1'::uuid), pg_temp.n(:p2) || '/deal');
select pg_temp.chk('D2 so_detail order_discount_amount = round(S × p2 / 100, 2) — M line excluded · discount_basis_amount = S', pg_temp.n((:'d1_d'::jsonb->'totals'->>'order_discount_amount')::numeric) || '/' || pg_temp.n((:'d1_d'::jsonb->'totals'->>'discount_basis_amount')::numeric) || '/' || pg_temp.n((:'d1_d'::jsonb->'totals'->>'lines_total')::numeric),
       pg_temp.n(round((:qa * :pa + :qb * :pb) * :p2 / 100.0, 2)) || '/' || pg_temp.n(:qa * :pa + :qb * :pb) || '/' || pg_temp.n(:qa * :pa + :qb * :pb + :qm * :pm));
select pg_temp.chk('D3 so_totals_many order_discount_amount = same number', (select pg_temp.n(t.order_discount_amount) from public.so_totals_many(array[:'d1'::uuid]) t), pg_temp.n(round((:qa * :pa + :qb * :pb) * :p2 / 100.0, 2)));
select pg_temp.chk('D4 so_tax_preview order_discount.amount (negative) · basis · totals.discount_basis_amount · manual_lines_amount · lines[].manual count', pg_temp.n((:'d1_t'::jsonb->'order_discount'->>'amount')::numeric) || '/' || pg_temp.n((:'d1_t'::jsonb->'order_discount'->>'basis')::numeric) || '/' || pg_temp.n((:'d1_t'::jsonb->'totals'->>'discount_basis_amount')::numeric) || '/' || pg_temp.n((:'d1_t'::jsonb->'totals'->>'manual_lines_amount')::numeric) || '/' || (select count(*) filter (where (l->>'manual')::boolean) || '-' || count(*) from jsonb_array_elements(:'d1_t'::jsonb->'lines') l),
       pg_temp.n(-round((:qa * :pa + :qb * :pb) * :p2 / 100.0, 2)) || '/' || pg_temp.n(:qa * :pa + :qb * :pb) || '/' || pg_temp.n(:qa * :pa + :qb * :pb) || '/' || pg_temp.n(:qm * :pm) || '/1-3');
select pg_temp.chk('D5 so_detail lines[].manual: M true · A B false', (select string_agg(l->>'sku' || '=' || (l->>'manual'), ',' order by (l->>'line_no')::int) from jsonb_array_elements(:'d1_d'::jsonb->'lines') l), 'OD1-A=false,OD1-B=false,OD1-M=true');
select pg_temp.chk('D6 order discount tax = so_tax_amount(amount, 13) · totals.tax = Σ line tax + od tax', pg_temp.n((:'d1_t'::jsonb->'order_discount'->>'tax')::numeric) || '/' || pg_temp.n((:'d1_t'::jsonb->'totals'->>'tax')::numeric),
       pg_temp.n(public.so_tax_amount(-round((:qa * :pa + :qb * :pb) * :p2 / 100.0, 2), :rate)) || '/' || pg_temp.n(public.so_tax_amount(:qa * :pa, :rate) + public.so_tax_amount(:qb * :pb, :rate) + public.so_tax_amount(:qm * :pm, :rate) + public.so_tax_amount(-round((:qa * :pa + :qb * :pb) * :p2 / 100.0, 2), :rate)));

-- ═══ S2 손 단가 줄을 지우면 문턱이 내려간다(다시 고르기 트리거 · 판정 543) — savepoint 로 되돌린다 ═══
savepoint sp;
delete from public.so_line where id = :'l_m'::uuid;
select public.so_detail(:'d1'::uuid) as d \gset s2_
select trim_scale(s.order_discount_pct)::text as s2_pct from public.so s where s.id = :'d1'::uuid \gset
rollback to savepoint sp;
select pg_temp.chk('S2 without M: threshold S < t2min → tier 1 (p1) · amount = round(S × p1 / 100, 2)', :'s2_pct' || '/' || pg_temp.n((:'s2_d'::jsonb->'totals'->>'order_discount_amount')::numeric),
       pg_temp.n(:p1) || '/' || pg_temp.n(round((:qa * :pa + :qb * :pb) * :p1 / 100.0, 2)));
select pg_temp.chk('S2b rolled back: M line back · tier 2 again', (select count(*)::text from public.so_line where id = :'l_m'::uuid) || '/' || (select trim_scale(s.order_discount_pct)::text from public.so s where s.id = :'d1'::uuid), '1/' || pg_temp.n(:p2));

-- ═══ S3 손 할인 % 줄 N(discount_source manual · dn%) 도 M (판정 544) ═══
insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, list_price, discount_pct, unit_price, discount_source) values (:'d1'::uuid, 4, :'pn_id'::uuid, 'OD1-N', 'OD1 Product N (hand discount)', 'EA', 1, :qn, :ln, :dn, round(:ln * (1 - :dn / 100.0), 7), 'manual') returning id::text as l_n \gset
select public.so_detail(:'d1'::uuid) as d \gset s3_
select pg_temp.chk('S3 manual-% line: tier stays p2 · amount still round(S × p2 / 100, 2) · basis S · manual lines 2 of 4', (select trim_scale(s.order_discount_pct)::text from public.so s where s.id = :'d1'::uuid) || '/' || pg_temp.n((:'s3_d'::jsonb->'totals'->>'order_discount_amount')::numeric) || '/' || pg_temp.n((:'s3_d'::jsonb->'totals'->>'discount_basis_amount')::numeric) || '/' || (select count(*) filter (where (l->>'manual')::boolean) || '-' || count(*) from jsonb_array_elements(:'s3_d'::jsonb->'lines') l),
       pg_temp.n(:p2) || '/' || pg_temp.n(round((:qa * :pa + :qb * :pb) * :p2 / 100.0, 2)) || '/' || pg_temp.n(:qa * :pa + :qb * :pb) || '/2-4');

-- ═══ S4 manual 오더 할인 pm_od% + M 줄 → 같은 규칙 · 규칙 쪽(p2)이 더 크면 경고 ═══
savepoint sp;
update public.so set order_discount_pct = :pm_od, order_discount_source = 'manual', order_discount_deal_id = null where id = :'d1'::uuid;
select public.so_detail(:'d1'::uuid) as d \gset s4_
rollback to savepoint sp;
select pg_temp.chk('S4 manual order discount: amount = round(S × pm_od / 100, 2) · warning order_discount_rule_now_better · rule_pct p2', pg_temp.n((:'s4_d'::jsonb->'totals'->>'order_discount_amount')::numeric) || '/' || (:'s4_d'::jsonb->'warnings' ? 'order_discount_rule_now_better')::text || '/' || pg_temp.n((:'s4_d'::jsonb->'order_discount_rule'->>'rule_pct')::numeric),
       pg_temp.n(round((:qa * :pa + :qb * :pb) * :pm_od / 100.0, 2)) || '/true/' || pg_temp.n(:p2));

-- ═══ S5 쿠폰 오더 할인(pc% · 쿠폰 딜 · 가짜 손님에게 발행) + M 줄 → 같은 규칙 ═══
savepoint sp;
insert into public.so_deal (name, source, is_active, is_order_level, kind, coupon_required) values ('OD1 Coupon Deal', 'manual', false, true, 'pct', true) returning id::text as cdeal \gset
insert into public.so_deal_customer_rule (deal_id, kind, target, customer_id) values (:'cdeal'::uuid, 'include', 'customer', :'cust'::uuid);
insert into public.so_deal_tier (deal_id, tier_no, min_amount, pct) values (:'cdeal'::uuid, 1, 0, :pc);
update public.so_deal set is_active = true where id = :'cdeal'::uuid;
insert into public.so_coupon (code, code_key, deal_id, customer_id) values ('OD1COUPON', public.so_coupon_key('OD1COUPON'), :'cdeal'::uuid, :'cust'::uuid) returning id::text as cp \gset
update public.so set coupon_id = :'cp'::uuid where id = :'d1'::uuid;
select r.order_discount_pct::text as s5_pct, r.order_discount_source as s5_src from public.so_order_discount_apply(:'d1'::uuid, null, false) r \gset
select public.so_detail(:'d1'::uuid) as d \gset s5_
rollback to savepoint sp;
select pg_temp.chk('S5 coupon wins (pc > p2) · source coupon · amount = round(S × pc / 100, 2)', trim_scale(:'s5_pct'::numeric)::text || '/' || :'s5_src' || '/' || pg_temp.n((:'s5_d'::jsonb->'totals'->>'order_discount_amount')::numeric), pg_temp.n(:pc) || '/coupon/' || pg_temp.n(round((:qa * :pa + :qb * :pb) * :pc / 100.0, 2)));

-- ═══ S6 모든 줄이 M → 단계는 걸리고(문턱) 금액은 0 (판정 542 · 543) ═══
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name)
  values ('SO-79982', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'OD1 Customer') returning id::text as d2 \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, list_price, unit_price, price_override) values (:'d2'::uuid, 1, :'pm_id'::uuid, 'OD1-M', 'OD1 Product M (hand price)', 'EA', 1, :qm, :pm, :pm, true);
insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, list_price, discount_pct, unit_price, discount_source) values (:'d2'::uuid, 2, :'pn_id'::uuid, 'OD1-N', 'OD1 Product N (hand discount)', 'EA', 1, :qn, :ln, :dn, round(:ln * (1 - :dn / 100.0), 7), 'manual');
select public.so_detail(:'d2'::uuid) as d \gset s6_
select pg_temp.chk('S6 all lines M: tier 1 picked (threshold > 0) · order_discount_amount 0 · basis 0 · lines_total = M sum', (select trim_scale(s.order_discount_pct)::text from public.so s where s.id = :'d2'::uuid) || '/' || pg_temp.n((:'s6_d'::jsonb->'totals'->>'order_discount_amount')::numeric) || '/' || pg_temp.n((:'s6_d'::jsonb->'totals'->>'discount_basis_amount')::numeric) || '/' || pg_temp.n((:'s6_d'::jsonb->'totals'->>'lines_total')::numeric),
       pg_temp.n(:p1) || '/0/0/' || pg_temp.n(:qm * :pm + round(:ln * (1 - :dn / 100.0), 2) * :qn));

-- ═══ P 문서(sales_order) — 줄별 net unit(판정 528 ④): S 줄 = unit × (1 − p2/100) · M 줄은 빈칸 ═══
select public.doc_data_so(:'d1'::uuid, '{"unit_display":"both","date_format":"YYYY-MM-DD"}'::jsonb) as d \gset p_
select pg_temp.chk('P1 doc_data_so net_unit_price: A = fmt(pa × (1 − p2/100)) · M empty · N empty', (select string_agg(l->>'sku' || '=' || coalesce(l->>'net_unit_price', '?'), ',' order by (l->>'no')::int) from jsonb_array_elements(:'p_d'::jsonb->'lines') l),
       'OD1-A=' || public.doc_fmt_money(:pa * (1 - :p2 / 100.0)) || ',OD1-B=' || public.doc_fmt_money(:pb * (1 - :p2 / 100.0)) || ',OD1-M=,OD1-N=');
select public.doc_data_so(:'d1'::uuid, '{"unit_display":"net","date_format":"YYYY-MM-DD"}'::jsonb) as d \gset pn_
select pg_temp.chk('P2 doc_data_so unit_display net: A shows net unit · M shows its own price unchanged', (select string_agg(l->>'sku' || '=' || coalesce(l->>'unit_price', '?'), ',' order by (l->>'no')::int) from jsonb_array_elements(:'pn_d'::jsonb->'lines') l where l->>'sku' in ('OD1-A', 'OD1-M')),
       'OD1-A=' || public.doc_fmt_money(:pa * (1 - :p2 / 100.0)) || ',OD1-M=' || public.doc_fmt_money(:pm));

-- ═══ I 출고 · 발행 — 일부만 보낸 오더(ordered ≠ shipped) · pct p2 manual · A(S) · M(override) · N(manual %) → 바탕 = S 의 보낸 수량 × 단가 ═══
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source)
  values ('SO-79983', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'OD1 Customer', now(), now(), :p2, 'manual') returning id::text as s1 \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, qty_shipped, list_price, unit_price) values (:'s1'::uuid, 1, :'pa_id'::uuid, 'OD1-A', 'OD1 Product A', 'EA', 1, :sa_ord, :sa_shp, :sa_p, :sa_p) returning id::text as sl_a \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, qty_shipped, list_price, unit_price, price_override) values (:'s1'::uuid, 2, :'pm_id'::uuid, 'OD1-M', 'OD1 Product M (hand price)', 'EA', 1, :sm_ord, :sm_shp, :sa_p, :sm_p, true) returning id::text as sl_m \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, qty_shipped, list_price, discount_pct, unit_price, discount_source) values (:'s1'::uuid, 3, :'pn_id'::uuid, 'OD1-N', 'OD1 Product N (hand discount)', 'EA', 1, :sn_ord, :sn_shp, :ln, :dn, round(:ln * (1 - :dn / 100.0), 7), 'manual');
set local session_replication_role = origin;
select public.so_tax_preview(:'s1'::uuid, null, null, 'shipped') as t \gset i_
select pg_temp.chk('I1 so_tax_preview shipped: basis = sa_shp × sa_p · od = −round(basis × p2 / 100, 2) · lines_amount = all shipped', pg_temp.n((:'i_t'::jsonb->'totals'->>'discount_basis_amount')::numeric) || '/' || pg_temp.n((:'i_t'::jsonb->'totals'->>'order_discount_amount')::numeric) || '/' || pg_temp.n((:'i_t'::jsonb->'totals'->>'lines_amount')::numeric),
       pg_temp.n(:sa_shp * :sa_p) || '/' || pg_temp.n(-round(:sa_shp * :sa_p * :p2 / 100.0, 2)) || '/' || pg_temp.n(:sa_shp * :sa_p + :sm_shp * :sm_p + round(:sn_shp * round(:ln * (1 - :dn / 100.0), 7), 2)));
select public.so_tax_preview(:'s1'::uuid, null, null, 'shipped', jsonb_build_object('lines', jsonb_build_object(:'sl_a', jsonb_build_object('qty', 4)))) as t \gset io_
select pg_temp.chk('I2 so_tax_preview with p_over (doc-1b2 path · A qty 4): basis 4 × sa_p · M still excluded', pg_temp.n((:'io_t'::jsonb->'totals'->>'discount_basis_amount')::numeric) || '/' || pg_temp.n((:'io_t'::jsonb->'totals'->>'order_discount_amount')::numeric), pg_temp.n(4 * :sa_p) || '/' || pg_temp.n(-round(4 * :sa_p * :p2 / 100.0, 2)));
select (public.so_invoice_issue(array[:'s1'::uuid], :'m_id'::uuid)->>'invoice_id') as inv \gset
select pg_temp.chk('I3 invoice order_discount line amount · tax = so_tax_amount(od, 13) · one line', (select pg_temp.n(l.amount) || '/' || pg_temp.n(l.tax_amount) || '/' || count(*) over () from public.so_invoice_line l where l.invoice_id = :'inv'::uuid and l.kind = 'order_discount'),
       pg_temp.n(-round(:sa_shp * :sa_p * :p2 / 100.0, 2)) || '/' || pg_temp.n(public.so_tax_amount(-round(:sa_shp * :sa_p * :p2 / 100.0, 2), :rate)) || '/1');
select pg_temp.chk('I4 so_invoice_order.order_discount_amount · so_invoice lines_amount · taxable · tax = Σ line tax + od tax', (select pg_temp.n(io.order_discount_amount) from public.so_invoice_order io where io.invoice_id = :'inv'::uuid) || '/' || (select pg_temp.n(i.lines_amount) || '/' || pg_temp.n(i.taxable_amount) || '/' || pg_temp.n(i.tax_amount) from public.so_invoice i where i.id = :'inv'::uuid),
       pg_temp.n(-round(:sa_shp * :sa_p * :p2 / 100.0, 2)) || '/' || pg_temp.n(:sa_shp * :sa_p + :sm_shp * :sm_p + round(:sn_shp * round(:ln * (1 - :dn / 100.0), 7), 2)) || '/' || pg_temp.n(:sa_shp * :sa_p + :sm_shp * :sm_p + round(:sn_shp * round(:ln * (1 - :dn / 100.0), 7), 2) - round(:sa_shp * :sa_p * :p2 / 100.0, 2))
       || '/' || pg_temp.n(public.so_tax_amount(:sa_shp * :sa_p, :rate) + public.so_tax_amount(:sm_shp * :sm_p, :rate) + public.so_tax_amount(round(:sn_shp * round(:ln * (1 - :dn / 100.0), 7), 2), :rate) + public.so_tax_amount(-round(:sa_shp * :sa_p * :p2 / 100.0, 2), :rate)));
select pg_temp.chk('I5 so_detail (shipped basis) order_discount_amount = invoice od (positive) · so_totals_many same', (select pg_temp.n((public.so_detail(:'s1'::uuid)->'totals'->>'order_discount_amount')::numeric)) || '/' || (select pg_temp.n(t.order_discount_amount) from public.so_totals_many(array[:'s1'::uuid]) t), pg_temp.n(round(:sa_shp * :sa_p * :p2 / 100.0, 2)) || '/' || pg_temp.n(round(:sa_shp * :sa_p * :p2 / 100.0, 2)));
select public.doc_data_invoice('final_invoice', :'inv'::uuid, '{"unit_display":"both","date_format":"YYYY-MM-DD"}'::jsonb) as d \gset pi_
select pg_temp.chk('P3 doc_data_invoice net_unit_price: A = fmt(sa_p × (1 − p2/100)) · M empty · N empty', (select string_agg(l->>'sku' || '=' || coalesce(l->>'net_unit_price', '?'), ',' order by (l->>'no')::int) from jsonb_array_elements(:'pi_d'::jsonb->'orders'->0->'lines') l), 'OD1-A=' || public.doc_fmt_money(:sa_p * (1 - :p2 / 100.0)) || ',OD1-M=,OD1-N=');

-- ═══ C 크레딧(인보이스 거울 · 판정 325 + od-1) — A 2 → 오더 할인 몫 · M 1 → 몫 없음 · A 1 + M 1 → A 몫만 ═══
select l.id::text as il_a from public.so_invoice_line l where l.invoice_id = :'inv'::uuid and l.kind = 'product' and l.sku = 'OD1-A' \gset
select l.id::text as il_m from public.so_invoice_line l where l.invoice_id = :'inv'::uuid and l.kind = 'product' and l.sku = 'OD1-M' \gset
\set p_ca '{"invoice_id":"' :inv '","reason":"customer_return","warehouse_id":"' :whx '","lines":[{"kind":"product","so_invoice_line_id":"' :il_a '","qty_returned":2,"not_restocked_reason":"not_returned"}]}'
\set p_cm '{"invoice_id":"' :inv '","reason":"customer_return","warehouse_id":"' :whx '","lines":[{"kind":"product","so_invoice_line_id":"' :il_m '","qty_returned":1,"not_restocked_reason":"not_returned"}]}'
\set p_cb '{"invoice_id":"' :inv '","reason":"customer_return","warehouse_id":"' :whx '","lines":[{"kind":"product","so_invoice_line_id":"' :il_a '","qty_returned":1,"not_restocked_reason":"not_returned"},{"kind":"product","so_invoice_line_id":"' :il_m '","qty_returned":1,"not_restocked_reason":"not_returned"}]}'
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select (public.so_credit_issue(:'p_ca'::jsonb, true)->>'credit_id') as cr_a \gset
select (public.so_credit_issue(:'p_cm'::jsonb, true)->>'credit_id') as cr_m \gset
select (public.so_credit_issue(:'p_cb'::jsonb, true)->>'credit_id') as cr_b \gset
reset role;
select pg_temp.chk('C1 credit A×2: order_discount_amount = −round(2 × sa_p × p2 / 100, 2) · kinds product,order_discount', (select pg_temp.n(c.order_discount_amount) from public.so_credit c where c.id = :'cr_a'::uuid) || '/' || (select string_agg(l.kind, ',' order by l.line_no) from public.so_credit_line l where l.credit_id = :'cr_a'::uuid),
       pg_temp.n(-round(2 * :sa_p * :p2 / 100.0, 2)) || '/product,order_discount');
select pg_temp.chk('C2 credit M×1 (hand price): order_discount_amount 0 · no order_discount line', (select pg_temp.n(c.order_discount_amount) from public.so_credit c where c.id = :'cr_m'::uuid) || '/' || (select string_agg(l.kind, ',' order by l.line_no) from public.so_credit_line l where l.credit_id = :'cr_m'::uuid), '0/product');
select pg_temp.chk('C3 credit A×1 + M×1: order_discount_amount = −round(sa_p × p2 / 100, 2) (A only)', (select pg_temp.n(c.order_discount_amount) from public.so_credit c where c.id = :'cr_b'::uuid), pg_temp.n(-round(:sa_p * :p2 / 100.0, 2)));

-- ═══ N 이름 잠금(판정 538) — 다섯 표 · 이름 거부(IM538 · 글) · note · is_active 통과 · 같은 이름으로 update 통과(적재 upsert 모양) · ref_bin 창고 거부 ═══
insert into public.ref_category (name, source) values ('OD1 Category', 'manual') returning id::text as cat \gset
insert into public.ref_unit (name, source) values ('OD1U', 'manual') returning id::text as unit \gset
insert into public.ref_payment_term (name, source, net_days) values ('OD1 Net 7', 'manual', 7) returning id::text as pt \gset
insert into public.ref_bin (warehouse_id, name, source) values (:'whx'::uuid, 'OD1-BIN', 'manual') returning id::text as bin \gset
\set msg 'Names cannot be changed — switch this one off and add a new one.'
select pg_temp.chk('N1 ref_brand rename refused (IM538 + screen text)', pg_temp.try(format('update public.ref_brand set name = %L where id = %L::uuid', 'OD1 Brand X', :'br')), 'IM538|' || :'msg');
select pg_temp.chk('N2 ref_category rename refused', pg_temp.try(format('update public.ref_category set name = %L where id = %L::uuid', 'OD1 Category X', :'cat')), 'IM538|' || :'msg');
select pg_temp.chk('N3 ref_unit rename refused', pg_temp.try(format('update public.ref_unit set name = %L where id = %L::uuid', 'OD1UX', :'unit')), 'IM538|' || :'msg');
select pg_temp.chk('N4 ref_payment_term rename refused', pg_temp.try(format('update public.ref_payment_term set name = %L where id = %L::uuid', 'OD1 Net 8', :'pt')), 'IM538|' || :'msg');
select pg_temp.chk('N5 ref_bin rename refused · warehouse change refused', pg_temp.try(format('update public.ref_bin set name = %L where id = %L::uuid', 'OD1-BIN2', :'bin')) || ' ‖ ' || pg_temp.try(format('update public.ref_bin set warehouse_id = %L::uuid where id = %L::uuid', :'whe', :'bin')), 'IM538|' || :'msg' || ' ‖ IM538|' || :'msg');
select pg_temp.chk('N6 note · is_active · same-name update pass on all five (touch still runs)', pg_temp.try(format('update public.ref_brand set note = ''od1'', is_active = false, name = name where id = %L::uuid', :'br')) || '/' || pg_temp.try(format('update public.ref_category set note = ''od1'' where id = %L::uuid', :'cat')) || '/' || pg_temp.try(format('update public.ref_unit set is_active = false where id = %L::uuid', :'unit')) || '/' || pg_temp.try(format('update public.ref_payment_term set net_days = 10, name = %L where id = %L::uuid', 'OD1 Net 7', :'pt')) || '/' || pg_temp.try(format('update public.ref_bin set is_staging = true, zone = ''Z'' where id = %L::uuid', :'bin')),
       'no-error/no-error/no-error/no-error/no-error');
select pg_temp.chk('N7 values after: brand off + note · payment term net_days 10 · bin staging', (select (not b.is_active)::text || '/' || b.note from public.ref_brand b where b.id = :'br'::uuid) || '/' || (select t.net_days::text from public.ref_payment_term t where t.id = :'pt'::uuid) || '/' || (select b.is_staging::text from public.ref_bin b where b.id = :'bin'::uuid), 'true/od1/10/true');

-- ═══ R 회귀 — 실제 열린 오더: M 줄 없는 오더는 전 = 후 · M 줄 + 오더 할인 있는 오더는 목록으로 ═══
create temp table t_tot_post as select * from public.so_totals_many(array[]::uuid[]) where false;
do $$
declare v_ids uuid[]; v_i int;
begin
  select array_agg(id order by id) into v_ids from t_ids;
  for v_i in 1 .. coalesce(cardinality(v_ids), 0) by 200 loop
    insert into t_tot_post select * from public.so_totals_many(v_ids[v_i : v_i + 199]);
  end loop;
end $$;
select pg_temp.chk('R1 real open orders without M lines: pre = post (od · lines_total · order_total · tax) for every one · compared ≥ 1', (select count(*) filter (where a.order_discount_amount is not distinct from b.order_discount_amount and a.lines_total is not distinct from b.lines_total and a.order_total is not distinct from b.order_total and a.tax is not distinct from b.tax) || '/' || count(*) || '/' || (count(*) >= 1)::text
        from t_ids i join t_tot_pre a on a.so_id = i.id join t_tot_post b on b.so_id = i.id where not i.has_m), (select count(*) || '/' || count(*) || '/true' from t_ids where not has_m));
select pg_temp.chk('R2 real open orders with M lines and an order discount (amount changes on apply): count · list', (select count(*) || ':' || coalesce(string_agg(i.so_number || ' ' || pg_temp.n(a.order_discount_amount) || '→' || pg_temp.n(b.order_discount_amount), ', ' order by i.so_number), '-') from t_ids i join t_tot_pre a on a.so_id = i.id join t_tot_post b on b.so_id = i.id where i.has_m and coalesce(i.order_discount_pct, 0) > 0),
       (select count(*) || ':' || coalesce(string_agg(i.so_number || ' ' || pg_temp.n(a.order_discount_amount) || '→' || pg_temp.n(b.order_discount_amount), ', ' order by i.so_number), '-') from t_ids i join t_tot_pre a on a.so_id = i.id join t_tot_post b on b.so_id = i.id where i.has_m and coalesce(i.order_discount_pct, 0) > 0));
select pg_temp.chk('R3 real open orders with M lines but no order discount: pre = post', (select count(*) filter (where a.order_discount_amount is not distinct from b.order_discount_amount and a.order_total is not distinct from b.order_total) || '/' || count(*) from t_ids i join t_tot_pre a on a.so_id = i.id join t_tot_post b on b.so_id = i.id where i.has_m and coalesce(i.order_discount_pct, 0) = 0),
       (select count(*) || '/' || count(*) from t_ids where has_m and coalesce(order_discount_pct, 0) = 0));

-- ═══ G 무접촉 · 권한 · 트리거 · Z 실물 ═══
select pg_temp.chk('G1 untouched md5 (so_invoice_issue · so_proforma · so_order_discount · so_lines_total · so_coupon_pct · so_line_total · doc_unit_prices · so_order_discount_apply · so_line_order_discount_repick · so_credit_prepare = 10)',
       (select count(*)::text from t_pre t join pg_proc p on p.proname = t.n join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public' where t.n in ('so_invoice_issue', 'so_proforma', 'so_order_discount', 'so_lines_total', 'so_coupon_pct', 'so_line_total', 'doc_unit_prices', 'so_order_discount_apply', 'so_line_order_discount_repick', 'so_credit_prepare') and md5(p.prosrc) = md5(t.src)), '10');
select pg_temp.chk('G2 reissued eight: one definition each · so_totals_many return shape unchanged (10 cols)', (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_tax_preview', 'so_detail', 'so_totals_many', 'so_credit_issue', 'doc_data_invoice', 'doc_data_invoice_fmt', 'doc_data_so', 'so_invoice_preview')) || '/' || (select pronargs::text || '-' || array_length(proallargtypes, 1) from pg_proc where oid = 'public.so_totals_many(uuid[])'::regprocedure), '8/1-11');
select pg_temp.chk('G3 acl: so_line_manual authenticated yes · anon no · ims_ref_name_lock authenticated no · anon no · public no', has_function_privilege('authenticated', 'public.so_line_manual(public.so_line)', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_line_manual(public.so_line)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.ims_ref_name_lock()', 'execute')::text || '/' || has_function_privilege('anon', 'public.ims_ref_name_lock()', 'execute')::text || '/' || has_function_privilege('public', 'public.ims_ref_name_lock()', 'execute')::text, 'true/false/false/false/false');
select pg_temp.chk('G4 name-lock triggers: five · before update · row · fire before *_touch (name order)', (select count(*)::text || '/' || bool_and(pg_get_triggerdef(t.oid) like 'CREATE TRIGGER % BEFORE UPDATE ON public.% FOR EACH ROW EXECUTE FUNCTION ims_ref_name_lock()')::text || '/' || bool_and(t.tgname < replace(t.tgname, '_name_lock', '_touch'))::text from pg_trigger t where t.tgname in ('ref_brand_name_lock', 'ref_category_name_lock', 'ref_unit_name_lock', 'ref_payment_term_name_lock', 'ref_bin_name_lock') and not t.tgisinternal), '5/true/true');
select pg_temp.chk('G5 so_line_manual: override · manual · shopify true · customer · deal · set · null false', (select string_agg(public.so_line_manual(x)::text, ',' order by (x).line_no) from (select (jsonb_populate_record(null::public.so_line, jsonb_build_object('line_no', i, 'price_override', i = 1, 'discount_source', (array[null, 'manual', 'shopify', 'customer', 'deal', 'set', null])[i]))) as x from generate_series(1, 7) i) q), 'true,true,true,false,false,false,false');
select pg_temp.chk('Z2 real master rows untouched (five counts = before + 1 fake each)', (select count(*) - 1 from public.ref_brand) || '/' || (select count(*) - 1 from public.ref_category) || '/' || (select count(*) - 1 from public.ref_unit) || '/' || (select count(*) - 1 from public.ref_payment_term) || '/' || (select count(*) - 1 from public.ref_bin), :'ref_counts_before');
select pg_temp.chk('Z3 real orders flagged unchanged at the end', (select count(*)::text from public.so where reprice_suggested_at is not null and so_number not like 'SO-7998%'), :'real_flag_before');
select pg_temp.chk('Z4 session_replication_role back to origin', current_setting('session_replication_role'), 'origin');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
select 'inv seq inside ' || last_value || ' ' || is_called from public.so_invoice_number_seq;
select 'cr seq inside ' || last_value || ' ' || is_called from public.so_credit_number_seq;
rollback;
select setval('public.so_invoice_number_seq', greatest((select max(invoice_number)::bigint from public.so_invoice), :inv_seq_last), true);
select setval('public.so_credit_number_seq', greatest((select coalesce(max(substr(credit_number, 4))::bigint, 0) from public.so_credit), :cr_seq_last), true);
select 'seq tail so ' || last_value || ' ' || is_called || ' (head ' || :so_seq_last || ')' from public.so_number_seq;
select 'seq tail inv ' || last_value || ' ' || is_called || ' (max invoice ' || (select max(invoice_number) from public.so_invoice) || ' · head ' || :inv_seq_last || ')' from public.so_invoice_number_seq;
select 'seq tail cr ' || last_value || ' ' || is_called || ' (max credit ' || (select max(credit_number) from public.so_credit) || ' · head ' || :cr_seq_last || ')' from public.so_credit_number_seq;
select 'invoices tail ' || (select count(*) from public.so_invoice) || ' · credits tail ' || (select count(*) from public.so_credit) || ' · SO-7998x tail ' || (select count(*) from public.so where so_number like 'SO-7998%');
