-- dsc-4a-verify.sql — 딜 통째 저장 창구 so_deal_save · 딜 줄 끄기 · 직접 쓰기 닫기 (Asung-IMS · 2026-10-06)
--   기대: OK 58 · MISMATCH 0(시험 적용 4회차 통과 · 2026-10-06) · 실제 행(TEST POS SALE 15 딜 · 줄 · 대상) md5 전후 같음 · 시퀀스 무변
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261007001229_dsc_4a_deal_save.sql -f supabase/tests/dsc-4a-verify.sql 2>&1 | tee /tmp/dsc-4a.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료는 가짜만(DSC4A-* · SO-7990x · 2031년) · 실제 행은 읽기만 · 끝은 rollback
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
\echo '== seq head so' :so_seq_last :so_seq_called 'inv' :inv_seq_last :inv_seq_called 'cr' :cr_seq_last :cr_seq_called
select md5(string_agg(x, '|' order by x)) as real_md5_head from (
  select d::text as x from public.so_deal d where d.id = '7a6b411a-b2e4-4a7f-8735-d74f24b0c8c3'
  union all select l::text from public.so_deal_line l where l.id = '28447237-8d1e-40e4-8b26-777600b50090'
  union all select t::text from public.so_deal_target t where t.id = 'fa1d5e67-2068-40ba-9f23-cf567455a115') s \gset
\echo '== real rows md5 head' :real_md5_head

begin;
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create function pg_temp.real_md5() returns text language sql as $$
  select md5(string_agg(x, '|' order by x)) from (
    select row(d.id, d.name, d.is_active, d.source, d.note, d.date_from, d.date_to, d.is_order_level, d.coupon_code, d.kind, d.coupon_required, d.updated_at, d.updated_by, d.created_at)::text as x from public.so_deal d where d.id = '7a6b411a-b2e4-4a7f-8735-d74f24b0c8c3'
    union all select row(l.id, l.deal_id, l.line_no, l.pct, l.min_qty_mode, l.min_qty, l.source, l.note, l.updated_at)::text from public.so_deal_line l where l.id = '28447237-8d1e-40e4-8b26-777600b50090'
    union all select row(t.id, t.line_id, t.kind, t.target, t.tag, t.brand_id, t.product_id, t.category_id, t.source, t.updated_at)::text from public.so_deal_target t where t.id = 'fa1d5e67-2068-40ba-9f23-cf567455a115') s
$$;
select pg_temp.real_md5() as real_in_before \gset

-- ═══ 재료(postgres) — 직원 둘 · 손님 · 제품 둘 · 태그 · 참조 ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'dsc4a-master@test.invalid', 'DSC4A Master', 'manager', '["master","sales"]'::jsonb) returning auth_user_id::text as m_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'dsc4a-sales@test.invalid',  'DSC4A Sales',  'manager', '["sales"]'::jsonb)          returning auth_user_id::text as s_uid \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
\set s_claims '{"sub":"' :s_uid '","role":"authenticated"}'
select id::text as wh1 from public.ref_warehouse order by name limit 1 \gset
select id::text as tier, name as tier_name from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' limit 1 \gset
select id::text as brand1 from public.ref_brand order by name limit 1 \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('DSC4A Customer', 'manual', :'tier_name', :'wh1'::uuid, 0) returning id::text as cust \gset
insert into public.product (sku, name, source) values ('DSC4A-A', 'DSC4A Product A', 'manual') returning id::text as pa \gset
insert into public.product (sku, name, source) values ('DSC4A-B', 'DSC4A Product B', 'manual') returning id::text as pb \gset
insert into public.product_tag (product_id, tag, source) values (:'pa'::uuid, 'DSC4A-Clearance', 'manual');
select count(*) as deals0 from public.so_deal \gset

-- ═══ S1 만들기 — 미리 보기(아무 행도 안 생김) → 쓰기 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4A Line Deal', 'date_from', '2031-01-01', 'date_to', '2031-01-31', 'note', 'fake',
  'lines', jsonb_build_array(
     jsonb_build_object('line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pa'), jsonb_build_object('kind', 'include', 'target', 'brand', 'brand_id', :'brand1'))),
     jsonb_build_object('line_no', 2, 'pct', 20, 'min_qty_mode', 'qty', 'min_qty', 12, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4A-Clearance')))),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), null, false) as r \gset s1p_
select public.so_deal_save(jsonb_build_object('name', 'DSC4A Line Deal', 'date_from', '2031-01-01', 'date_to', '2031-01-31', 'note', 'fake',
  'lines', jsonb_build_array(
     jsonb_build_object('line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pa'), jsonb_build_object('kind', 'include', 'target', 'brand', 'brand_id', :'brand1'))),
     jsonb_build_object('line_no', 2, 'pct', 20, 'min_qty_mode', 'qty', 'min_qty', 12, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4A-Clearance')))),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), null, true) as r \gset s1c_
reset role;
select pg_temp.chk('S1a preview not committed', :'s1p_r'::jsonb->>'committed', 'false');
select pg_temp.chk('S1b preview blocks 0 · unacked 0', (jsonb_array_length(:'s1p_r'::jsonb->'blocks') || '/' || jsonb_array_length(:'s1p_r'::jsonb->'unacked')), '0/0');
select pg_temp.chk('S1c preview changes = head added + line 2 + target 3 + rule 1', (select string_agg(x->>'part' || ':' || (x->>'action'), ',' order by x->>'part', x->>'action') from jsonb_array_elements(:'s1p_r'::jsonb->'changes') x), 'head:added,line:added,line:added,rule:added,target:added,target:added,target:added');
select pg_temp.chk('S1d commit committed', :'s1c_r'::jsonb->>'committed', 'true');
select pg_temp.chk('S1e commit changes = preview changes', ((:'s1c_r'::jsonb->'changes') = (:'s1p_r'::jsonb->'changes'))::text, 'true');
select (:'s1c_r'::jsonb->>'deal_id') as d1, (:'s1c_r'::jsonb->>'updated_at') as u1 \gset
select pg_temp.chk('S1f rows: deal manual · lines 2 manual · targets 3 · rules 1', (select d.source || '/' || (select count(*) || '-' || count(*) filter (where source = 'manual') from public.so_deal_line l where l.deal_id = d.id) || '/' || (select count(*) from public.so_deal_target t join public.so_deal_line l on l.id = t.line_id where l.deal_id = d.id) || '/' || (select count(*) from public.so_deal_customer_rule r where r.deal_id = d.id) from public.so_deal d where d.id = :'d1'::uuid), 'manual/2-2/3/1');
select pg_temp.chk('S1g returned updated_at = row updated_at', (select (:'u1'::timestamptz = d.updated_at)::text from public.so_deal d where d.id = :'d1'::uuid), 'true');
select pg_temp.chk('S1h deal is_active true · deals +1', (select (d.is_active)::text from public.so_deal d where d.id = :'d1'::uuid) || '/' || ((select count(*) from public.so_deal) - :deals0), 'true/1');
select l.id::text as l1 from public.so_deal_line l where l.deal_id = :'d1'::uuid and l.line_no = 1 \gset
select l.id::text as l2 from public.so_deal_line l where l.deal_id = :'d1'::uuid and l.line_no = 2 \gset

-- 가짜 오더 셋(2031 · 가짜 손님 · 트리거 없이) + 줄 2 를 가리키는 오더 줄 하나
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct) values ('SO-79901', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', '2031-01-15', :'tier'::uuid, 0) returning id::text as so1 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct) values ('SO-79902', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', '2031-01-15', :'tier'::uuid, 0) returning id::text as so2 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, confirmed_at) values ('SO-79903', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'confirmed', '2031-01-15', :'tier'::uuid, 0, now()) returning id::text as so3 \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, discount_pct, unit_price, discount_source, deal_line_id) values (:'so1'::uuid, 1, :'pa'::uuid, 'DSC4A-A', 1, 12, 10, 20, 8, 'deal', :'l2'::uuid);
set local session_replication_role = origin;
select pg_temp.chk('S1i fake orders 3 · none flagged', (select count(*) || '/' || count(*) filter (where reprice_suggested_at is not null) from public.so where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid)), '3/0');

-- ═══ S2 판 대조 — 틀린 p_old → changed_elsewhere · 없음 → old_missing · 아무것도 안 바뀜 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'name', 'DSC4A Renamed'), '"2020-01-01T00:00:00+00:00"'::jsonb, true) as r \gset s2a_
select public.so_deal_save(jsonb_build_object('id', :'d1', 'name', 'DSC4A Renamed'), null, true) as r \gset s2b_
reset role;
select pg_temp.chk('S2a wrong p_old → changed_elsewhere', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s2a_r'::jsonb->'blocks') x), 'changed_elsewhere');
select pg_temp.chk('S2b no p_old → old_missing', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s2b_r'::jsonb->'blocks') x), 'old_missing');
select pg_temp.chk('S2c name unchanged', (select d.name from public.so_deal d where d.id = :'d1'::uuid), 'DSC4A Line Deal');

-- ═══ S3 자식만 고침 → 머리 판 오름 · 옛 p_old 로 다시 → changed_elsewhere · S12 미리 보기 표시 수 = 실제 ═══
set local session_replication_role = replica;
update public.so_deal set updated_at = now() - interval '1 hour' where id = :'d1'::uuid;
set local session_replication_role = origin;
select to_json(d.updated_at)::text as u_old from public.so_deal d where d.id = :'d1'::uuid \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(
     jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pa'))),
     jsonb_build_object('id', :'l2', 'line_no', 2, 'pct', 20, 'min_qty_mode', 'qty', 'min_qty', 12))), jsonb_build_object('updated_at', :'u_old'::jsonb), false) as r \gset s3p_
reset role;
select pg_temp.chk('S3b preview open_orders_to_flag = 3 fake orders · not committed · nothing flagged yet', (:'s3p_r'::jsonb->>'open_orders_to_flag') || '/' || (:'s3p_r'::jsonb->>'committed') || '/' || (select count(*) from public.so where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid) and reprice_suggested_at is not null), '3/false/0');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(
     jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pa'))),
     jsonb_build_object('id', :'l2', 'line_no', 2, 'pct', 20, 'min_qty_mode', 'qty', 'min_qty', 12))), jsonb_build_object('updated_at', :'u_old'::jsonb), true, array['deal:' || :'d1' || ':open_orders_flagged']) as r \gset s3c_
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(
     jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pa'))),
     jsonb_build_object('id', :'l2', 'line_no', 2, 'pct', 20, 'min_qty_mode', 'qty', 'min_qty', 12))), jsonb_build_object('updated_at', :'u_old'::jsonb), true) as r \gset s3d_
reset role;
select pg_temp.chk('S3a preview: head unchanged · target removed · lines unchanged', (select string_agg(x->>'part' || ':' || (x->>'action'), ',' order by x->>'part', x->>'action') from jsonb_array_elements(:'s3p_r'::jsonb->'changes') x where (x->>'action') <> 'unchanged'), 'target:removed');
select pg_temp.chk('S3c commit with ack committed · flagged = preview count', (:'s3c_r'::jsonb->>'committed') || '/' || (select count(*) from public.so where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid) and reprice_suggested_at is not null) || '/' || (:'s3c_r'::jsonb->>'open_orders_to_flag'), 'true/3/3');
select pg_temp.chk('S3d head updated_at rose (child-only change)', (select (d.updated_at > :'u_old'::timestamptz and d.updated_at = (:'s3c_r'::jsonb->>'updated_at')::timestamptz)::text from public.so_deal d where d.id = :'d1'::uuid), 'true');
select pg_temp.chk('S3e targets of line 1 now 1 (brand removed)', (select count(*)::text from public.so_deal_target t where t.line_id = :'l1'::uuid), '1');
select pg_temp.chk('S3f old p_old again → changed_elsewhere', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s3d_r'::jsonb->'blocks') x), 'changed_elsewhere');
select (:'s3c_r'::jsonb->>'updated_at') as u1 \gset
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid);
set local session_replication_role = origin;

-- ═══ S5 맞바꾸기 — 줄 번호 1↔2 · 단계 금액(오더 딜) · 겹치는 최종 모양은 막기 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(
     jsonb_build_object('id', :'l1', 'line_no', 2, 'pct', 10),
     jsonb_build_object('id', :'l2', 'line_no', 1, 'pct', 20, 'min_qty_mode', 'qty', 'min_qty', 12))), to_jsonb(:'u1'::text), true, array['deal:' || :'d1' || ':open_orders_flagged']) as r \gset s5a_
reset role;
select pg_temp.chk('S5a line numbers swapped', (:'s5a_r'::jsonb->>'committed') || '/' || (select string_agg(l.id::text || '=' || l.line_no, ',' order by l.line_no) from public.so_deal_line l where l.deal_id = :'d1'::uuid), 'true/' || :'l2' || '=1,' || :'l1' || '=2');
select (:'s5a_r'::jsonb->>'updated_at') as u1 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(
     jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10),
     jsonb_build_object('id', :'l2', 'line_no', 2, 'pct', 20, 'min_qty_mode', 'qty', 'min_qty', 12))), to_jsonb(:'u1'::text), true, array['deal:' || :'d1' || ':open_orders_flagged']) as r \gset s5b_
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(
     jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10),
     jsonb_build_object('id', :'l2', 'line_no', 1, 'pct', 20, 'min_qty_mode', 'qty', 'min_qty', 12))), :'s5b_r'::jsonb->'updated_at', true) as r \gset s5c_
select public.so_deal_save(jsonb_build_object('name', 'DSC4A Order Deal', 'is_order_level', true, 'date_from', '2031-01-01', 'date_to', '2031-01-31',
  'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 500, 'pct', 5), jsonb_build_object('tier_no', 2, 'min_amount', 1000, 'pct', 7)),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), null, true, array['deal:new:open_orders_flagged']) as r \gset s5d_
reset role;
select pg_temp.chk('S5b swapped back', (:'s5b_r'::jsonb->>'committed') || '/' || (select string_agg(l.id::text || '=' || l.line_no, ',' order by l.line_no) from public.so_deal_line l where l.deal_id = :'d1'::uuid), 'true/' || :'l1' || '=1,' || :'l2' || '=2');
select pg_temp.chk('S5c two lines on 1 → line_no_duplicate', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s5c_r'::jsonb->'blocks') x), 'line_no_duplicate');
select pg_temp.chk('S5d order deal created · tiers 2 · flagged 3', (:'s5d_r'::jsonb->>'committed') || '/' || (select count(*) from public.so_deal_tier t where t.deal_id = (:'s5d_r'::jsonb->>'deal_id')::uuid) || '/' || (:'s5d_r'::jsonb->>'open_orders_to_flag'), 'true/2/3');
select (:'s5d_r'::jsonb->>'deal_id') as d2, (:'s5d_r'::jsonb->>'updated_at') as u2 \gset
select (:'s5b_r'::jsonb->>'updated_at') as u1 \gset
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid);
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d2', 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 1000, 'pct', 5), jsonb_build_object('tier_no', 2, 'min_amount', 500, 'pct', 7))), to_jsonb(:'u2'::text), true, array['deal:' || :'d2' || ':open_orders_flagged']) as r \gset s5e_
select public.so_deal_save(jsonb_build_object('id', :'d2', 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 500, 'pct', 5), jsonb_build_object('tier_no', 2, 'min_amount', 500, 'pct', 7))), :'s5e_r'::jsonb->'updated_at', true) as r \gset s5f_
reset role;
select pg_temp.chk('S5e tier amounts swapped', (:'s5e_r'::jsonb->>'committed') || '/' || (select string_agg(t.tier_no || ':' || t.min_amount || '/' || t.pct, ',' order by t.tier_no) from public.so_deal_tier t where t.deal_id = :'d2'::uuid), 'true/1:1000/5,2:500/7');
select pg_temp.chk('S5f two tiers at 500 → tier_amount_duplicate', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s5f_r'::jsonb->'blocks') x), 'tier_amount_duplicate');
select (:'s5e_r'::jsonb->>'updated_at') as u2 \gset
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid);
set local session_replication_role = origin;

-- ═══ S4 줄 끄기 — 오더 줄이 가리키는 줄 2 를 덩이에서 뺌 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10))), to_jsonb(:'u1'::text), false) as r \gset s4p_
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10))), to_jsonb(:'u1'::text), true) as r \gset s4n_
reset role;
select pg_temp.chk('S4c commit without ack → not committed · unacked 2 · line 2 still on', (:'s4n_r'::jsonb->>'committed') || '/' || jsonb_array_length(:'s4n_r'::jsonb->'unacked') || '/' || (select l.is_active::text from public.so_deal_line l where l.id = :'l2'::uuid), 'false/2/true');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10))), to_jsonb(:'u1'::text), true, array['deal:' || :'d1' || ':open_orders_flagged', 'deal:' || :'d1' || ':line_off_with_order_lines']) as r \gset s4c_
reset role;
select pg_temp.chk('S4a preview: line 2 turned_off with 1 order line', (select string_agg(x->>'action' || ':' || (x->>'so_lines'), ',') from jsonb_array_elements(:'s4p_r'::jsonb->'changes') x where x->>'part' = 'line' and x->>'line_id' = :'l2'), 'turned_off:1');
select pg_temp.chk('S4b preview warnings line_off_with_order_lines n=1 + open_orders_flagged 3', (select string_agg(x->>'code' || '=' || (x->>'n'), ',' order by x->>'code') from jsonb_array_elements(:'s4p_r'::jsonb->'warnings') x), 'line_off_with_order_lines=1,open_orders_flagged=3');
select pg_temp.chk('S4d commit with ack → line 2 off · row kept · order line still points', (:'s4c_r'::jsonb->>'committed') || '/' || (select l.is_active::text from public.so_deal_line l where l.id = :'l2'::uuid) || '/' || (select count(*) from public.so_line s where s.deal_line_id = :'l2'::uuid), 'true/false/1');
select pg_temp.chk('S4e candidates: line 2 lost line_inactive · line 1 won', (select string_agg(c.line_no || ':' || c.status || ':' || c.reason, ',' order by c.line_no) from public.so_deal_candidates(:'pa'::uuid, :'cust'::uuid, :'tier'::uuid, 12, '2031-01-15') c where c.deal_id = :'d1'::uuid), '1:won:won,2:lost:line_inactive');
select pg_temp.chk('S4f open fake orders flagged 3', (select count(*)::text from public.so where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid) and reprice_suggested_at is not null), '3');
select (:'s4c_r'::jsonb->>'updated_at') as u1 \gset
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid);
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10), jsonb_build_object('line_no', 2, 'pct', 5, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pb'))))), to_jsonb(:'u1'::text), true) as r \gset s4g_
reset role;
select pg_temp.chk('S4g new line on number 2 (held by off line) → line_no_duplicate', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s4g_r'::jsonb->'blocks') x), 'line_no_duplicate');

-- ═══ S6 대상 · 손님 조건 — 빠지면 지워짐 · 같은 호출 안 겹침 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'), jsonb_build_object('kind', 'include', 'target', 'tier', 'tier_id', :'tier'))), to_jsonb(:'u1'::text), true, array['deal:' || :'d1' || ':open_orders_flagged']) as r \gset s6a_
reset role;
select pg_temp.chk('S6a rule added → 2 rules', (:'s6a_r'::jsonb->>'committed') || '/' || (select count(*) from public.so_deal_customer_rule r where r.deal_id = :'d1'::uuid), 'true/2');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), :'s6a_r'::jsonb->'updated_at', true, array['deal:' || :'d1' || ':open_orders_flagged']) as r \gset s6b_
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pa'), jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pa')))),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'), jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), :'s6b_r'::jsonb->'updated_at', true) as r \gset s6c_
reset role;
select pg_temp.chk('S6b rule removed → 1 rule · change rule:removed', (:'s6b_r'::jsonb->>'committed') || '/' || (select count(*) from public.so_deal_customer_rule r where r.deal_id = :'d1'::uuid) || '/' || (select string_agg(x->>'action', ',') from jsonb_array_elements(:'s6b_r'::jsonb->'changes') x where x->>'part' = 'rule' and x->>'action' <> 'unchanged'), 'true/1/removed');
select pg_temp.chk('S6c duplicates in call → target_duplicate_in_call + rule_duplicate_in_call', (select string_agg(x->>'code', ',' order by x->>'code') from jsonb_array_elements(:'s6c_r'::jsonb->'blocks') x), 'rule_duplicate_in_call,target_duplicate_in_call');
select (:'s6b_r'::jsonb->>'updated_at') as u1 \gset
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid);
set local session_replication_role = origin;

-- ═══ S7 문지기 넷(어휘로) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'is_order_level', true), to_jsonb(:'u1'::text), true) as r \gset s7a_
select public.so_deal_save(jsonb_build_object('id', :'d1', 'is_order_level', true, 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10))), to_jsonb(:'u1'::text), true) as r \gset s7b_
select public.so_deal_save(jsonb_build_object('id', :'d2', 'is_order_level', false), to_jsonb(:'u2'::text), true) as r \gset s7c_
select public.so_deal_save(jsonb_build_object('id', :'d1', 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 5))), to_jsonb(:'u1'::text), true) as r \gset s7d_
reset role;
select pg_temp.chk('S7a order-level on with active lines → lines_block_order_level_on', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s7a_r'::jsonb->'blocks') x), 'lines_block_order_level_on');
select pg_temp.chk('S7b order-level on + lines given → line_on_order_deal', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s7b_r'::jsonb->'blocks') x), 'line_on_order_deal');
select pg_temp.chk('S7c order-level off with tiers → tiers_block_order_level_off', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s7c_r'::jsonb->'blocks') x), 'tiers_block_order_level_off');
select pg_temp.chk('S7d tiers on a line deal → tier_on_line_deal', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s7d_r'::jsonb->'blocks') x), 'tier_on_line_deal');

-- ═══ S8 태그 — 없는 태그 알림(ack) · 대소문자 충돌 셋 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pa'), jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4A-NoSuchTag'))))), to_jsonb(:'u1'::text), true, array['deal:' || :'d1' || ':open_orders_flagged']) as r \gset s8a_
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pa'), jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4A-NoSuchTag'))))), to_jsonb(:'u1'::text), true, array['deal:' || :'d1' || ':open_orders_flagged', 'deal:' || :'d1' || ':tag_unused']) as r \gset s8b_
select public.so_deal_save(jsonb_build_object('name', 'DSC4A Tag Deal 1', 'date_from', '2031-02-01', 'date_to', '2031-02-28', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 5, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'dsc4a-clearance'))))), null, true) as r \gset s8c_
select public.so_deal_save(jsonb_build_object('name', 'DSC4A Tag Deal 2', 'date_from', '2031-02-01', 'date_to', '2031-02-28', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 5, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'dsc4a-nosuchtag'))))), null, true) as r \gset s8d_
select public.so_deal_save(jsonb_build_object('name', 'DSC4A Tag Deal 3', 'date_from', '2031-02-01', 'date_to', '2031-02-28', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 5, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4A-Foo'), jsonb_build_object('kind', 'exclude', 'target', 'tag', 'tag', 'dsc4a-foo'))))), null, true) as r \gset s8e_
reset role;
select pg_temp.chk('S8a unused tag → warning tag_unused · unacked → not committed', (select string_agg(x->>'code', ',' order by x->>'code') from jsonb_array_elements(:'s8a_r'::jsonb->'warnings') x) || '/' || (:'s8a_r'::jsonb->>'committed') || '/' || (select string_agg(u, ',') from jsonb_array_elements_text(:'s8a_r'::jsonb->'unacked') u), 'open_orders_flagged,tag_unused/false/deal:' || :'d1' || ':tag_unused');
select pg_temp.chk('S8b acked → committed · tag target saved', (:'s8b_r'::jsonb->>'committed') || '/' || (select count(*) from public.so_deal_target t where t.line_id = :'l1'::uuid and t.tag = 'DSC4A-NoSuchTag'), 'true/1');
select pg_temp.chk('S8c case clash with product tag → tag_case_conflict', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s8c_r'::jsonb->'blocks') x), 'tag_case_conflict');
select pg_temp.chk('S8d case clash with another deal target → tag_case_conflict', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s8d_r'::jsonb->'blocks') x), 'tag_case_conflict');
select pg_temp.chk('S8e case clash inside the call → tag_case_conflict', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s8e_r'::jsonb->'blocks') x), 'tag_case_conflict');
select pg_temp.chk('S8f no new deals from the three refused saves', ((select count(*) from public.so_deal) - :deals0)::text, '2');
select (:'s8b_r'::jsonb->>'updated_at') as u1 \gset
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid);
set local session_replication_role = origin;

-- ═══ S9 쿠폰 — coupon_required 켬 → 표시(333) · 쓰지 않은 쿠폰 있는 딜 끔 → deal_off_with_coupons(334) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d2', 'coupon_required', true), to_jsonb(:'u2'::text), false) as r \gset s9p_
select public.so_deal_save(jsonb_build_object('id', :'d2', 'coupon_required', true), to_jsonb(:'u2'::text), true, array['deal:' || :'d2' || ':open_orders_flagged']) as r \gset s9a_
reset role;
select pg_temp.chk('S9a coupon_required on: preview to_flag 3 · commit flagged 3', (:'s9p_r'::jsonb->>'open_orders_to_flag') || '/' || (:'s9a_r'::jsonb->>'committed') || '/' || (select count(*) from public.so where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid) and reprice_suggested_at is not null), '3/true/3');
select (:'s9a_r'::jsonb->>'updated_at') as u2 \gset
insert into public.so_coupon (code, code_key, deal_id, customer_id) values ('DSC4A-ABCDEFGH', public.so_coupon_key('DSC4A-ABCDEFGH'), :'d2'::uuid, :'cust'::uuid) returning id::text as cp \gset
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid);
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d2', 'is_active', false), to_jsonb(:'u2'::text), true, array['deal:' || :'d2' || ':open_orders_flagged']) as r \gset s9b_
reset role;
select pg_temp.chk('S9b deal off with 1 unused coupon → warning n=1 · unacked', (select (x->>'n') from jsonb_array_elements(:'s9b_r'::jsonb->'warnings') x where x->>'code' = 'deal_off_with_coupons') || '/' || (:'s9b_r'::jsonb->>'committed') || '/' || (select d.is_active::text from public.so_deal d where d.id = :'d2'::uuid), '1/false/true');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d2', 'is_active', false), to_jsonb(:'u2'::text), true, array['deal:' || :'d2' || ':open_orders_flagged', 'deal:' || :'d2' || ':deal_off_with_coupons']) as r \gset s9c_
reset role;
select pg_temp.chk('S9c acked → deal off · coupon untouched', (:'s9c_r'::jsonb->>'committed') || '/' || (select d.is_active::text from public.so_deal d where d.id = :'d2'::uuid) || '/' || (select (c.voided_at is null and c.used_so_id is null)::text from public.so_coupon c where c.id = :'cp'::uuid), 'true/false/true');
select (:'s9c_r'::jsonb->>'updated_at') as u2 \gset
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where id in (:'so1'::uuid, :'so2'::uuid, :'so3'::uuid);
set local session_replication_role = origin;

-- ═══ S10 막기 하나면 아무것도 안 바뀜 · no_change ═══
select md5(string_agg(x, '|' order by x)) as d1_md5 from (select row(d.name, d.date_from, d.date_to, d.updated_at)::text as x from public.so_deal d where d.id = :'d1'::uuid union all select row(l.line_no, l.pct, l.is_active)::text from public.so_deal_line l where l.deal_id = :'d1'::uuid union all select row(t.kind, t.target, t.tag, t.product_id)::text from public.so_deal_target t join public.so_deal_line l on l.id = t.line_id where l.deal_id = :'d1'::uuid) s \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'name', '', 'date_to', '2031-03-31', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 15))), to_jsonb(:'u1'::text), true, array['deal:' || :'d1' || ':open_orders_flagged']) as r \gset s10a_
select public.so_deal_save(jsonb_build_object('id', :'d1', 'name', 'DSC4A Line Deal', 'date_from', '2031-01-01', 'date_to', '2031-01-31', 'is_order_level', false, 'coupon_required', false, 'note', 'fake',
  'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'pa'), jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4A-NoSuchTag')))),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), to_jsonb(:'u1'::text), true) as r \gset s10b_
reset role;
select pg_temp.chk('S10a name_missing blocks · nothing changed', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s10a_r'::jsonb->'blocks') x) || '/' || (select (md5(string_agg(x, '|' order by x)) = :'d1_md5')::text from (select row(d.name, d.date_from, d.date_to, d.updated_at)::text as x from public.so_deal d where d.id = :'d1'::uuid union all select row(l.line_no, l.pct, l.is_active)::text from public.so_deal_line l where l.deal_id = :'d1'::uuid union all select row(t.kind, t.target, t.tag, t.product_id)::text from public.so_deal_target t join public.so_deal_line l on l.id = t.line_id where l.deal_id = :'d1'::uuid) s), 'name_missing/true');
select pg_temp.chk('S10b same shape again → no_change', (select string_agg(x->>'code', ',') from jsonb_array_elements(:'s10b_r'::jsonb->'blocks') x), 'no_change');

-- ═══ S11 권한 — sales 신원 거절 · authenticated 직접 쓰기 42501 · anon 읽기 · 실행 42501 · 335 실물 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'s_claims', true);
do $$ begin perform public.so_deal_save(jsonb_build_object('name', 'DSC4A Sales Try'), null, true); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
reset role;
select pg_temp.chk('S11a sales identity → master refusal', (select (current_setting('app.out', true) like '%cannot change master data%')::text), 'true');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
do $$ begin insert into public.so_deal (name, source) values ('DSC4A Direct', 'manual'); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as o1 \gset
do $$ begin update public.so_deal_line set pct = 1 where false; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as o2 \gset
do $$ begin delete from public.so_deal_target where false; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as o3 \gset
do $$ begin insert into public.so_deal_tier (deal_id, tier_no, pct) values (gen_random_uuid(), 1, 1); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as o4 \gset
do $$ begin delete from public.so_deal_customer_rule where false; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as o5 \gset
do $$ begin insert into public.product_tag (product_id, tag) values (gen_random_uuid(), 'x'); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as o6 \gset
do $$ begin update public.so_coupon set note = 'x' where false; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as o7 \gset
select count(*) as auth_sel from public.so_deal where id = :'d1'::uuid \gset
reset role;
select pg_temp.chk('S11b authenticated direct writes on 7 tables → 42501 ×7 · select still open', :'o1' || ',' || :'o2' || ',' || :'o3' || ',' || :'o4' || ',' || :'o5' || ',' || :'o6' || ',' || :'o7' || '/' || :auth_sel, '42501,42501,42501,42501,42501,42501,42501/1');
set local role anon;
do $$ begin perform count(*) from public.so_deal; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a1 \gset
do $$ begin perform count(*) from public.product_tag; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a2 \gset
do $$ begin perform count(*) from public.so_coupon; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a3 \gset
do $$ begin perform public.so_deal_save(jsonb_build_object('name', 'x'), null, false); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a4 \gset
do $$ begin perform public.so_coupon_key('x'); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as a5 \gset
reset role;
select pg_temp.chk('S11c anon: select 3 tables · so_deal_save · so_coupon_key → 42501 ×5', :'a1' || ',' || :'a2' || ',' || :'a3' || ',' || :'a4' || ',' || :'a5', '42501,42501,42501,42501,42501');
select pg_temp.chk('S11d 335: 7 tables policy = 1 SELECT each · authenticated no insert/update/delete/truncate · anon nothing', (select count(*)::text from unnest(array['so_deal', 'so_deal_tier', 'so_deal_line', 'so_deal_target', 'so_deal_customer_rule', 'product_tag', 'so_coupon']) t
  where (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = t) = 1
    and not has_table_privilege('authenticated', format('public.%I', t), 'insert') and not has_table_privilege('authenticated', format('public.%I', t), 'update') and not has_table_privilege('authenticated', format('public.%I', t), 'delete') and not has_table_privilege('authenticated', format('public.%I', t), 'truncate')
    and has_table_privilege('authenticated', format('public.%I', t), 'select')
    and not has_table_privilege('anon', format('public.%I', t), 'select') and not has_table_privilege('anon', format('public.%I', t), 'insert')), '7');
select pg_temp.chk('S11e invoker functions writing the 7 tables that authenticated can call = 0', (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute') and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?(so_deal|so_deal_tier|so_deal_line|so_deal_target|so_deal_customer_rule|product_tag|so_coupon)\M'), '0');
select pg_temp.chk('S11f so_coupon_key: authenticated yes · anon no · public no', has_function_privilege('authenticated', 'public.so_coupon_key(text)', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_coupon_key(text)', 'execute')::text || '/' || has_function_privilege('public', 'public.so_coupon_key(text)', 'execute')::text, 'true/false/false');
select pg_temp.chk('S11g triggers: line_changed_u WHEN has is_active · deal_changed_u WHEN has coupon_required · uniques deferrable 2', (select count(*) from pg_trigger where tgname = 'so_deal_line_changed_u' and pg_get_triggerdef(oid) like '%old.is_active IS DISTINCT FROM new.is_active%') || '/' || (select count(*) from pg_trigger where tgname = 'so_deal_changed_u' and pg_get_triggerdef(oid) like '%old.coupon_required IS DISTINCT FROM new.coupon_required%') || '/' || (select count(*) from pg_constraint where conname in ('so_deal_tier_amount_uq', 'so_deal_line_deal_line_no_key') and condeferrable), '1/1/2');

-- ═══ S7b 330 — 꺼진 줄만 남은 딜은 오더 딜로 바꿀 수 있다(줄 끄기 + 켜기 + 단계를 한 번에) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'is_order_level', true, 'lines', '[]'::jsonb, 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 3))), to_jsonb(:'u1'::text), true, array['deal:' || :'d1' || ':open_orders_flagged']) as r \gset s7e_
reset role;
select pg_temp.chk('S7e turn off last line + order-level on + tier in one save → committed · lines all off · tier 1', (:'s7e_r'::jsonb->>'committed') || '/' || (select count(*) || '-' || count(*) filter (where is_active) from public.so_deal_line l where l.deal_id = :'d1'::uuid) || '/' || (select count(*) from public.so_deal_tier t where t.deal_id = :'d1'::uuid) || '/' || (select d.is_order_level::text from public.so_deal d where d.id = :'d1'::uuid), 'true/2-0/1/true');

-- ═══ 끝 — 실제 행 무변 · 집계 ═══
select pg_temp.chk('Z real rows (TEST POS SALE 15) unchanged inside', pg_temp.real_md5(), :'real_in_before');
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select md5(string_agg(x, '|' order by x)) as real_md5_tail from (
  select d::text as x from public.so_deal d where d.id = '7a6b411a-b2e4-4a7f-8735-d74f24b0c8c3'
  union all select l::text from public.so_deal_line l where l.id = '28447237-8d1e-40e4-8b26-777600b50090'
  union all select t::text from public.so_deal_target t where t.id = 'fa1d5e67-2068-40ba-9f23-cf567455a115') s \gset
\echo '== real rows md5 tail' :real_md5_tail '(head' :real_md5_head ')'
select 'REAL_ROWS_SAME ' || (:'real_md5_head' = :'real_md5_tail')::text;
select 'seq tail so ' || last_value || ' ' || is_called from public.so_number_seq;
select 'seq tail inv ' || last_value || ' ' || is_called from public.so_invoice_number_seq;
select 'seq tail cr ' || last_value || ' ' || is_called from public.so_credit_number_seq;
