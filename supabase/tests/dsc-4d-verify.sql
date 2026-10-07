-- dsc-4d-verify.sql — 줄 딜 표시를 그 제품이 든 오더로 좁힘(판정 346 · 창구가 센다) · deal_off_with_coupons 는 넘어가는 순간만(판정 347) · line_no_targets 오표시(c) · min_qty 문구(d) (Asung-IMS · 2026-10-07)
--   기대: 시험 갈래 OK 51 · 확인 갈래(G0 다섯 없음) OK 46 · MISMATCH 0(시험 적용 1회차 통과 · 2026-10-07) · 실제 행(TEST POS SALE 15) md5 전후 같음 · 시퀀스 무변
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261007125617_dsc_4d_deal_flag_narrow.sql -f supabase/tests/dsc-4d-verify.sql 2>&1 | tee /tmp/dsc-4d.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다(G0 는 시험 갈래에서만 · D-pre 는 확인 갈래에서 새 함수라 「옛 = 넓게」 기대는 \if 로 가른다)
--   재료는 가짜만(DSC4D-* · SO-7992x · 2031년 · 가짜 브랜드 · 손님 둘 · 직원) · 실제 딜 · 오더는 읽기만 · 끝은 rollback
--   「덜 찍지 않음」 = 같은 저장을 옛 함수(D-pre · savepoint 에서 되돌림)와 새 함수로 돌려 새 ⊆ 옛 ∧ 새 = 기대(트리거가 찍었을 오더 ∩ 전 ∪ 뒤 제품) · 세는 것은 가짜 오더 A · B · C 만
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
select 'dsc-4c applied on this DB: ' || (to_regprocedure('public.so_deal_flag_open_orders(uuid, date, date, boolean, uuid[])') is not null)::text;

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
-- D-pre: 지금 DB 의 so_deal_save 를 다른 이름으로 복사(시험 갈래 = 옛 함수 · 확인 갈래 = 새 함수) · 무접촉 함수 · 트리거 정의도 담아 둔다
create temp table t_pre as
  select p.proname as n, p.prosrc as src from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname in ('so_deal_save', 'so_deal_changed', 'so_deal_part_changed', 'so_deal_products', 'so_deal_flag_open_orders', 'so_deal_list', 'so_deal_detail');
create temp table t_pre_trg as
  select tgname as n, pg_get_triggerdef(oid) as def from pg_trigger where not tgisinternal and tgrelid::regclass::text in ('so_deal', 'so_deal_tier', 'so_deal_line', 'so_deal_target', 'so_deal_customer_rule');
do $$
declare v_src text;
begin
  select src into v_src from t_pre where n = 'so_deal_save';
  execute format('create function public.dsc4d_pre_save(p_deal jsonb, p_old jsonb default null, p_commit boolean default false, p_ack text[] default ''{}'') returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as %L', v_src);
end $$;
grant execute on function public.dsc4d_pre_save(jsonb, jsonb, boolean, text[]) to authenticated;
\if :{?mig}
select pg_temp.chk('G0a so_deal_save last def = 20261007003838:962~1595', (select md5(src) from t_pre where n = 'so_deal_save'), '799b2deffbcc89387c87f3e440d401e9');
select pg_temp.chk('G0b so_deal_changed last def = 20261006201443:255~268', (select md5(src) from t_pre where n = 'so_deal_changed'), '72b63abada84946b74abadc37f208710');
select pg_temp.chk('G0c so_deal_part_changed last def = 20261006201443:275~295', (select md5(src) from t_pre where n = 'so_deal_part_changed'), '2e7572c833e94e435f6462ef88f9c862');
select pg_temp.chk('G0d so_deal_products last def = 20261007003838:1600~', (select md5(src) from t_pre where n = 'so_deal_products'), '243b8fce2d6136460bf7c0550a4e1c14');
select pg_temp.chk('G0e so_deal_flag_open_orders last def = 20261007005851:42~57', (select md5(src) from t_pre where n = 'so_deal_flag_open_orders'), '4e54213c1d24b2dc861ba952b685dde6');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\set pre_broad true
\else
\set pre_broad false
\endif
create function pg_temp.real_md5() returns text language sql as $$
  select md5(string_agg(x, '|' order by x)) from (
    select row(d.id, d.name, d.is_active, d.source, d.note, d.date_from, d.date_to, d.is_order_level, d.coupon_code, d.kind, d.coupon_required, d.updated_at, d.updated_by, d.created_at)::text as x from public.so_deal d where d.id = '7a6b411a-b2e4-4a7f-8735-d74f24b0c8c3'
    union all select row(l.id, l.deal_id, l.line_no, l.pct, l.min_qty_mode, l.min_qty, l.source, l.note, l.updated_at, l.is_active)::text from public.so_deal_line l where l.id = '28447237-8d1e-40e4-8b26-777600b50090'
    union all select row(t.id, t.line_id, t.kind, t.target, t.tag, t.brand_id, t.product_id, t.category_id, t.source, t.updated_at)::text from public.so_deal_target t where t.id = 'fa1d5e67-2068-40ba-9f23-cf567455a115') s
$$;
select pg_temp.real_md5() as real_in_before \gset
-- 가짜 오더 셋만 센다: A = SO-79921(제품 X) · B = SO-79922(제품 Y) · C = SO-79923(X 의 세트 Xs) · 표시된 것의 글자를 모은다('-' = 없음)
create function pg_temp.flags() returns text language sql as $$
  select coalesce(string_agg(x.k, ',' order by x.k), '-') from (values ('A', 'SO-79921'), ('B', 'SO-79922'), ('C', 'SO-79923')) x(k, n) join public.so s on s.so_number = x.n where s.reprice_suggested_at is not null
$$;
create function pg_temp.subset(p_small text, p_big text) returns boolean language sql as $$
  select coalesce((select bool_and(a = any(string_to_array(p_big, ','))) from unnest(string_to_array(nullif(p_small, '-'), ',')) a), true)
$$;
create function pg_temp.codes(p_r jsonb, p_part text) returns text language sql as $$
  select coalesce(string_agg(w->>'code', ',' order by w->>'code'), '-') from jsonb_array_elements(p_r->p_part) w
$$;
create function pg_temp.door_setting() returns text language sql as $$
  select coalesce(nullif(current_setting('ims.deal_flag_door', true), ''), '<empty>')
$$;
select case when :pre_broad then 'A,B,C' else 'A,C' end as e_pre_narrow \gset
select case when :pre_broad then 'A,B,C' else '-' end as e_pre_off \gset

-- ═══ 재료 — 직원(master) · 창고 · 티어 · 손님 둘 · 브랜드 · 제품 X · Xs(X 의 세트) · Y · 오더 셋(draft · 2031-01-15 · 손님 1) · X 의 태그(C1 용) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'dsc4d-master@test.invalid', 'DSC4D Master', 'manager', '["master","sales"]'::jsonb) returning auth_user_id::text as m_uid \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as wh1 from public.ref_warehouse order by name limit 1 \gset
select id::text as tier, name as tier_name from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' limit 1 \gset
insert into public.ref_brand (name) values ('DSC4D Brand') returning id::text as br \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('DSC4D Customer 1', 'manual', :'tier_name', :'wh1'::uuid, 0) returning id::text as cust1 \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('DSC4D Customer 2', 'manual', :'tier_name', :'wh1'::uuid, 0) returning id::text as cust2 \gset
insert into public.product (sku, name, source, brand_id) values ('DSC4D-X', 'DSC4D Product X', 'manual', :'br'::uuid) returning id::text as px \gset
insert into public.product (sku, name, source, parent_product_id, pack_factor) values ('DSC4D-X-12', 'DSC4D Product X x12', 'manual', :'px'::uuid, 12) returning id::text as pxs \gset
insert into public.product (sku, name, source, brand_id) values ('DSC4D-Y', 'DSC4D Product Y', 'manual', :'br'::uuid) returning id::text as py \gset
insert into public.product_tag (product_id, tag, source) values (:'px'::uuid, 'DSC4D-Tag', 'manual');
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct) values ('SO-79921', :'cust1'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', '2031-01-15', :'tier'::uuid, 0) returning id::text as oa \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct) values ('SO-79922', :'cust1'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', '2031-01-15', :'tier'::uuid, 0) returning id::text as ob \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct) values ('SO-79923', :'cust1'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', '2031-01-15', :'tier'::uuid, 0) returning id::text as oc \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, unit_price) values (:'oa'::uuid, 1, :'px'::uuid, 'DSC4D-X', 1, 1, 10, 10);
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, unit_price) values (:'ob'::uuid, 1, :'py'::uuid, 'DSC4D-Y', 1, 1, 10, 10);
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, unit_price) values (:'oc'::uuid, 1, :'pxs'::uuid, 'DSC4D-X-12', 12, 1, 120, 120);
set local session_replication_role = origin;
select pg_temp.chk('M0 orders A(X) · B(Y) · C(Xs) draft · none flagged · door setting empty', pg_temp.flags() || '/' || pg_temp.door_setting(), '-/<empty>');

-- ═══ N1 줄 딜 「X 10%」 만들기 — 미리 보기 수 = 저장 수(N9a) · 옛 함수 넓게(A·B·C) · 새 함수 A·C ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4D Line Deal', 'date_from', '2031-01-01', 'date_to', '2031-12-31',
  'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'px')))),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust1'))), null, false) as r \gset n1p_
reset role;
select pg_temp.chk('N9a preview (create) counts 2 · nothing flagged after rollback · door setting reverted by ZZ990', (:'n1p_r'::jsonb->>'open_orders_to_flag') || '/' || (:'n1p_r'::jsonb->>'committed') || '/' || pg_temp.flags() || '/' || pg_temp.door_setting(), '2/false/-/<empty>');
savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select clock_timestamp() as t0 \gset
select public.dsc4d_pre_save(jsonb_build_object('name', 'DSC4D Line Deal', 'date_from', '2031-01-01', 'date_to', '2031-12-31',
  'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'px')))),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust1'))), null, true, array['deal:new:open_orders_flagged']) as r \gset n1pre_
select clock_timestamp() as t1 \gset
reset role;
select pg_temp.flags() as f_n1pre \gset
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select clock_timestamp() as t2 \gset
select public.so_deal_save(jsonb_build_object('name', 'DSC4D Line Deal', 'date_from', '2031-01-01', 'date_to', '2031-12-31',
  'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'px')))),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust1'))), null, true, array['deal:new:open_orders_flagged']) as r \gset n1_
select clock_timestamp() as t3 \gset
reset role;
select pg_temp.flags() as f_n1 \gset
select pg_temp.chk('N1 create line deal X 10% → new = A,C (B has only Y) · pre = broad in trial · new ⊆ pre · counts preview = save', :'f_n1' || '/' || :'f_n1pre' || '/' || pg_temp.subset(:'f_n1', :'f_n1pre')::text || '/' || (:'n1_r'::jsonb->>'open_orders_to_flag') || '/' || (:'n1_r'::jsonb->>'committed') || '/' || pg_temp.door_setting(), 'A,C/' || :'e_pre_narrow' || '/true/2/true/<empty>');
select 'T N1 create (ms): pre=' || round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000) || ' new=' || round(extract(epoch from (:'t3'::timestamptz - :'t2'::timestamptz)) * 1000);
select (:'n1_r'::jsonb->>'deal_id') as d1, (:'n1_r'::jsonb->>'updated_at') as u1 \gset
select l.id::text as l1 from public.so_deal_line l where l.deal_id = :'d1'::uuid and l.line_no = 1 \gset
select ('{deal:' || :'d1' || ':open_orders_flagged,deal:' || :'d1' || ':line_off_with_order_lines,deal:' || :'d1' || ':deal_off_with_coupons,deal:' || :'d1' || ':rules_open_to_all,deal:' || :'d1' || ':tag_unused}') as ack1 \gset
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;

-- ═══ N2 같은 딜의 % 10 → 12 → A·C ═══
savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.dsc4d_pre_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 12))), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n2pre_
reset role;
select pg_temp.flags() as f_n2pre \gset
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 12))), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n2_
reset role;
select pg_temp.flags() as f_n2 \gset
select pg_temp.chk('N2 pct 10 → 12 → new = A,C · pre broad in trial · new ⊆ pre', :'f_n2' || '/' || :'f_n2pre' || '/' || pg_temp.subset(:'f_n2', :'f_n2pre')::text || '/' || (:'n2_r'::jsonb->>'committed'), 'A,C/' || :'e_pre_narrow' || '/true/true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;

-- ═══ N3 대상 X → Y + % 12 → 15 한 저장 → 전 ∪ 뒤 = A·B·C · A 가 빠지면 판정 346 의 사고 · 미리 보기 수 = 저장 수(N9b) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 15, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'py'))))), to_jsonb(:'u1'::text), false) as r \gset n3p_
reset role;
select pg_temp.chk('N9b preview (X → Y + pct) counts 3 · nothing flagged · setting reverted', (:'n3p_r'::jsonb->>'open_orders_to_flag') || '/' || pg_temp.flags() || '/' || pg_temp.door_setting(), '3/-/<empty>');
savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select clock_timestamp() as t0 \gset
select public.dsc4d_pre_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 15, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'py'))))), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n3pre_
select clock_timestamp() as t1 \gset
reset role;
select pg_temp.flags() as f_n3pre \gset
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select clock_timestamp() as t2 \gset
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 15, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'py'))))), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n3_
select clock_timestamp() as t3 \gset
reset role;
select pg_temp.flags() as f_n3 \gset
select pg_temp.chk('N3 target X → Y + pct in one save → new = A,B,C (before ∪ after) · A present · pre = A,B,C · counts preview = save', :'f_n3' || '/' || (position('A' in :'f_n3') > 0)::text || '/' || :'f_n3pre' || '/' || (:'n3_r'::jsonb->>'open_orders_to_flag') || '/' || (:'n3_r'::jsonb->>'committed'), 'A,B,C/true/A,B,C/3/true');
select 'T N3 retarget (ms): pre=' || round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000) || ' new=' || round(extract(epoch from (:'t3'::timestamptz - :'t2'::timestamptz)) * 1000);
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;
-- 되돌리기: 대상을 X 로(전 Y ∪ 뒤 X = A·B·C · 세지 않고 지운다)
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 15, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'px'))))), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n3b_
reset role;
select pg_temp.chk('N3b restore target Y → X → A,B,C · committed', pg_temp.flags() || '/' || (:'n3b_r'::jsonb->>'committed'), 'A,B,C/true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;

-- ═══ N4 줄 끄기(대상 X · lines []) → 전 제품만 = A·C · 다시 켜기 → 뒤 제품 = A·C ═══
savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.dsc4d_pre_save(jsonb_build_object('id', :'d1', 'lines', '[]'::jsonb), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n4pre_
reset role;
select pg_temp.flags() as f_n4pre \gset
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', '[]'::jsonb), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n4_
reset role;
select pg_temp.flags() as f_n4 \gset
select pg_temp.chk('N4 line off (target X) → new = A,C (before products only) · pre broad in trial · new ⊆ pre · line turned_off', :'f_n4' || '/' || :'f_n4pre' || '/' || pg_temp.subset(:'f_n4', :'f_n4pre')::text || '/' || (select count(*) from jsonb_array_elements(:'n4_r'::jsonb->'changes') c where c->>'part' = 'line' and c->>'action' = 'turned_off'), 'A,C/' || :'e_pre_narrow' || '/true/1');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 15))), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n4b_
reset role;
select pg_temp.chk('N4b line turned on again → A,C (after products)', pg_temp.flags() || '/' || (select count(*) from jsonb_array_elements(:'n4b_r'::jsonb->'changes') c where c->>'part' = 'line' and c->>'action' = 'turned_on'), 'A,C/1');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;

-- ═══ N5 딜 끄기 → 전 제품의 오더 A·C · 꺼진 딜에서 % 고치기 → 0 · 다시 켜기 → A·C ═══
savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.dsc4d_pre_save(jsonb_build_object('id', :'d1', 'is_active', false), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n5pre_
reset role;
select pg_temp.flags() as f_n5pre \gset
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'is_active', false), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n5_
reset role;
select pg_temp.flags() as f_n5 \gset
select pg_temp.chk('N5a deal off → new = A,C · pre broad in trial · new ⊆ pre', :'f_n5' || '/' || :'f_n5pre' || '/' || pg_temp.subset(:'f_n5', :'f_n5pre')::text || '/' || (:'n5_r'::jsonb->>'committed'), 'A,C/' || :'e_pre_narrow' || '/true/true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;
savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.dsc4d_pre_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 20))), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n5bpre_
reset role;
select pg_temp.flags() as f_n5bpre \gset
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 20))), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n5b_
reset role;
select pg_temp.chk('N5b pct change on an off deal → nothing (new and pre)', pg_temp.flags() || '/' || :'f_n5bpre' || '/' || (:'n5b_r'::jsonb->>'committed'), '-/-/true');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'is_active', true), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n5c_
reset role;
select pg_temp.chk('N5c deal on again → A,C (after products)', pg_temp.flags() || '/' || (:'n5c_r'::jsonb->>'committed'), 'A,C/true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;

-- ═══ N6 기간 옮기기(오더 2031 은 옛 기간 안 · 새 기간 2032 밖) → 옛 기간 갈래 A·C ═══
savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.dsc4d_pre_save(jsonb_build_object('id', :'d1', 'date_from', '2032-01-01', 'date_to', '2032-12-31'), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n6pre_
reset role;
select pg_temp.flags() as f_n6pre \gset
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'date_from', '2032-01-01', 'date_to', '2032-12-31'), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n6_
reset role;
select pg_temp.flags() as f_n6 \gset
select pg_temp.chk('N6 period 2031 → 2032 (orders only in the old period) → new = A,C · pre broad in trial · new ⊆ pre', :'f_n6' || '/' || :'f_n6pre' || '/' || pg_temp.subset(:'f_n6', :'f_n6pre')::text || '/' || (:'n6_r'::jsonb->>'committed'), 'A,C/' || :'e_pre_narrow' || '/true/true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'date_from', '2031-01-01', 'date_to', '2031-12-31'), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n6b_
reset role;
select pg_temp.chk('N6b period back to 2031 → A,C (new period branch)', pg_temp.flags() || '/' || (:'n6b_r'::jsonb->>'committed'), 'A,C/true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;
-- 이름 · 메모만 바꾼 저장 → 트리거처럼 표시 없음(새 · 옛 둘 다)
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'name', 'DSC4D Line Deal (renamed)', 'note', 'n'), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n6c_
reset role;
select pg_temp.chk('N6c name · note only → nothing flagged · committed', pg_temp.flags() || '/' || (:'n6c_r'::jsonb->>'committed') || '/' || (:'n6c_r'::jsonb->>'open_orders_to_flag'), '-/true/0');

-- ═══ N7 손님 조건 손님 1 → 손님 2 → 손님으로 거르지 않는다(오더는 손님 1 인데 표시) · 기간 · 제품만 = A·C ═══
savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.dsc4d_pre_save(jsonb_build_object('id', :'d1', 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust2'))), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n7pre_
reset role;
select pg_temp.flags() as f_n7pre \gset
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust2'))), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n7_
reset role;
select pg_temp.flags() as f_n7 \gset
select pg_temp.chk('N7 customer rule 1 → 2 → not filtered by customer (orders are customer 1) · products only = A,C · pre broad in trial', :'f_n7' || '/' || :'f_n7pre' || '/' || pg_temp.subset(:'f_n7', :'f_n7pre')::text || '/' || (:'n7_r'::jsonb->>'committed'), 'A,C/' || :'e_pre_narrow' || '/true/true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust1'))), to_jsonb(:'u1'::text), true, :'ack1'::text[]) as r \gset n7b_
reset role;
select pg_temp.chk('N7b rule back to customer 1 → A,C', pg_temp.flags() || '/' || (:'n7b_r'::jsonb->>'committed'), 'A,C/true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;

-- ═══ N8 오더 딜(단계) 만들기 · 단계 % 고치기 → 지금처럼 넓게(옛 = 새 = A·B·C) ═══
savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.dsc4d_pre_save(jsonb_build_object('name', 'DSC4D Order Deal', 'is_order_level', true, 'date_from', '2031-01-01', 'date_to', '2031-12-31',
  'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 5)),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust1'))), null, true, array['deal:new:open_orders_flagged']) as r \gset n8pre_
reset role;
select pg_temp.flags() as f_n8pre \gset
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4D Order Deal', 'is_order_level', true, 'date_from', '2031-01-01', 'date_to', '2031-12-31',
  'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 5)),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust1'))), null, true, array['deal:new:open_orders_flagged']) as r \gset n8_
reset role;
select pg_temp.chk('N8a order deal create → broad A,B,C (new = pre)', pg_temp.flags() || '/' || :'f_n8pre' || '/' || (:'n8_r'::jsonb->>'committed'), 'A,B,C/A,B,C/true');
select (:'n8_r'::jsonb->>'deal_id') as d8, (:'n8_r'::jsonb->>'updated_at') as u8 \gset
select ('{deal:' || :'d8' || ':open_orders_flagged,deal:' || :'d8' || ':deal_off_with_coupons}') as ack8 \gset
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;
savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.dsc4d_pre_save(jsonb_build_object('id', :'d8', 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 6))), to_jsonb(:'u8'::text), true, :'ack8'::text[]) as r \gset n8bpre_
reset role;
select pg_temp.flags() as f_n8bpre \gset
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d8', 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 6))), to_jsonb(:'u8'::text), true, :'ack8'::text[]) as r \gset n8b_
reset role;
select pg_temp.chk('N8b tier pct 5 → 6 → broad A,B,C (new = pre)', pg_temp.flags() || '/' || :'f_n8bpre' || '/' || (:'n8b_r'::jsonb->>'committed'), 'A,B,C/A,B,C/true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;

-- ═══ N10 창구 밖 — 같은 트랜잭션에서 창구 호출 뒤 켜진 줄 딜의 줄을 직접 update → 넓게(신호가 새지 않음) ═══
select pg_temp.chk('N10a door setting is empty after the door calls', pg_temp.door_setting(), '<empty>');
update public.so_deal_line set pct = 21 where id = :'l1'::uuid;
select pg_temp.chk('N10b direct line update (outside the door) → broad A,B,C', pg_temp.flags(), 'A,B,C');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;

-- ═══ N11 다른 딜의 트리거는 안 눌림 — 설정 = 딜 1 인 채 딜 8(오더 딜) 단계를 직접 고치면 넓게 · 설정 = 딜 8 이면 건너뜀 · 설정 = 딜 1 이면 딜 1 줄은 건너뜀 · 비우면 다시 넓게 ═══
select set_config('ims.deal_flag_door', :'d1', true);
update public.so_deal_tier set pct = 7 where deal_id = :'d8'::uuid;
select pg_temp.chk('N11a setting = deal 1 · deal 8 tier changed directly → broad A,B,C (other deal not suppressed)', pg_temp.flags(), 'A,B,C');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;
update public.so_deal_line set pct = 22 where id = :'l1'::uuid;
select pg_temp.chk('N11b setting = deal 1 · deal 1 line changed directly → skipped (-)', pg_temp.flags(), '-');
select set_config('ims.deal_flag_door', :'d8', true);
update public.so_deal_tier set pct = 8 where deal_id = :'d8'::uuid;
select pg_temp.chk('N11c setting = deal 8 · deal 8 tier changed directly → skipped (-)', pg_temp.flags(), '-');
update public.so_deal set is_active = false where id = :'d8'::uuid;
select pg_temp.chk('N11d setting = deal 8 · deal 8 head off directly → skipped (-)', pg_temp.flags(), '-');
update public.so_deal set is_active = true where id = :'d8'::uuid;
select set_config('ims.deal_flag_door', '', true);
update public.so_deal_tier set pct = 9 where deal_id = :'d8'::uuid;
select pg_temp.chk('N11e setting cleared · deal 8 tier changed directly → broad A,B,C again', pg_temp.flags(), 'A,B,C');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;

-- ═══ K 판정 347 — 쿠폰 딜 넷(오더 딜 · coupon_required · 손님 1 조건 · 손님 1 · 2 에 쿠폰 발행) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4D Coupon Deal 1', 'is_order_level', true, 'coupon_required', true, 'date_from', '2031-01-01', 'date_to', '2031-12-31', 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 5)), 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust1'))), null, true, array['deal:new:open_orders_flagged']) as r \gset k1_
select public.so_deal_save(jsonb_build_object('name', 'DSC4D Coupon Deal 2', 'is_order_level', true, 'coupon_required', true, 'date_from', '2031-01-01', 'date_to', '2031-12-31', 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 5)), 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust1'))), null, true, array['deal:new:open_orders_flagged']) as r \gset k2_
select public.so_deal_save(jsonb_build_object('name', 'DSC4D Coupon Deal 3', 'is_order_level', true, 'coupon_required', true, 'date_from', '2031-01-01', 'date_to', '2031-12-31', 'tiers', jsonb_build_array(jsonb_build_object('tier_no', 1, 'min_amount', 0, 'pct', 5)), 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust1'))), null, true, array['deal:new:open_orders_flagged']) as r \gset k3_
select public.so_deal_save(jsonb_build_object('name', 'DSC4D Coupon Deal 4 (no tiers)', 'is_order_level', true, 'coupon_required', true, 'date_from', '2031-01-01', 'date_to', '2031-12-31', 'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust1'))), null, true, array['deal:new:open_orders_flagged']) as r \gset k4_
reset role;
select (:'k1_r'::jsonb->>'deal_id') as kd1, (:'k1_r'::jsonb->>'updated_at') as ku1, (:'k2_r'::jsonb->>'deal_id') as kd2, (:'k2_r'::jsonb->>'updated_at') as ku2, (:'k3_r'::jsonb->>'deal_id') as kd3, (:'k3_r'::jsonb->>'updated_at') as ku3, (:'k4_r'::jsonb->>'deal_id') as kd4, (:'k4_r'::jsonb->>'updated_at') as ku4 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_coupon_issue(:'kd1'::uuid, array[:'cust1'::uuid, :'cust2'::uuid], null, 'DSC4D') as r \gset ki1_
select public.so_coupon_issue(:'kd2'::uuid, array[:'cust1'::uuid], null, 'DSC4D') as r \gset ki2_
select public.so_coupon_issue(:'kd3'::uuid, array[:'cust1'::uuid], null, 'DSC4D') as r \gset ki3_
select public.so_coupon_issue(:'kd4'::uuid, array[:'cust1'::uuid], null, 'DSC4D') as r \gset ki4_
reset role;
select pg_temp.chk('K0 four coupon deals created · unused coupons 2/1/1/1', (:'k1_r'::jsonb->>'committed') || (:'k2_r'::jsonb->>'committed') || (:'k3_r'::jsonb->>'committed') || (:'k4_r'::jsonb->>'committed') || '/' || (select count(*) filter (where deal_id = :'kd1'::uuid) || '/' || count(*) filter (where deal_id = :'kd2'::uuid) || '/' || count(*) filter (where deal_id = :'kd3'::uuid) || '/' || count(*) filter (where deal_id = :'kd4'::uuid) from public.so_coupon where used_so_id is null and voided_at is null), 'truetruetruetrue/2/1/1/1');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;
-- K1 coupon_required 끄기 → 경고(n = 2) · 저장
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'kd1', 'coupon_required', false), to_jsonb(:'ku1'::text), true, array['deal:' || :'kd1' || ':open_orders_flagged', 'deal:' || :'kd1' || ':deal_off_with_coupons']) as r \gset k1a_
reset role;
select pg_temp.chk('K1 coupon_required off (deal on) → deal_off_with_coupons n=2 · committed', (select count(*) || '/' || coalesce(max(w->>'n'), '-') from jsonb_array_elements(:'k1a_r'::jsonb->'warnings') w where w->>'code' = 'deal_off_with_coupons') || '/' || (:'k1a_r'::jsonb->>'committed'), '1/2/true');
-- K2 이어서 Active 끄기 → 경고 없음(옛 함수는 또 낸다 — 시험 갈래에서만)
savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.dsc4d_pre_save(jsonb_build_object('id', :'kd1', 'is_active', false), to_jsonb(:'ku1'::text), true, array['deal:' || :'kd1' || ':open_orders_flagged', 'deal:' || :'kd1' || ':deal_off_with_coupons']) as r \gset k2pre_
reset role;
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'kd1', 'is_active', false), to_jsonb(:'ku1'::text), true, array['deal:' || :'kd1' || ':open_orders_flagged', 'deal:' || :'kd1' || ':deal_off_with_coupons']) as r \gset k2a_
reset role;
select pg_temp.chk('K2 then Active off → no deal_off_with_coupons (pre repeated it in trial) · committed', (select count(*) from jsonb_array_elements(:'k2a_r'::jsonb->'warnings') w where w->>'code' = 'deal_off_with_coupons') || '/' || (select count(*) from jsonb_array_elements(:'k2pre_r'::jsonb->'warnings') w where w->>'code' = 'deal_off_with_coupons') || '/' || (:'k2a_r'::jsonb->>'committed'), '0/' || case when :pre_broad then '1' else '0' end || '/true');
-- K3 둘을 한 저장에 끄기 → 경고 한 번
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'kd2', 'is_active', false, 'coupon_required', false), to_jsonb(:'ku2'::text), true, array['deal:' || :'kd2' || ':open_orders_flagged', 'deal:' || :'kd2' || ':deal_off_with_coupons']) as r \gset k3a_
reset role;
select pg_temp.chk('K3 Active + coupon_required off in one save → warning once (n=1)', (select count(*) || '/' || coalesce(max(w->>'n'), '-') from jsonb_array_elements(:'k3a_r'::jsonb->'warnings') w where w->>'code' = 'deal_off_with_coupons') || '/' || (:'k3a_r'::jsonb->>'committed'), '1/1/true');
-- K4 이미 꺼진 딜에서 이름 고치기 → 없음
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'kd2', 'name', 'DSC4D Coupon Deal 2 (renamed)'), to_jsonb(:'ku2'::text), true, array['deal:' || :'kd2' || ':open_orders_flagged', 'deal:' || :'kd2' || ':deal_off_with_coupons']) as r \gset k4a_
reset role;
select pg_temp.chk('K4 rename an already-off coupon deal → no warning · committed', (select count(*) from jsonb_array_elements(:'k4a_r'::jsonb->'warnings') w where w->>'code' = 'deal_off_with_coupons') || '/' || (:'k4a_r'::jsonb->>'committed'), '0/true');
-- K5 (덤) Active 만 끄기(coupon_required 켜진 채) → 경고
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'kd3', 'is_active', false), to_jsonb(:'ku3'::text), true, array['deal:' || :'kd3' || ':open_orders_flagged', 'deal:' || :'kd3' || ':deal_off_with_coupons']) as r \gset k5a_
reset role;
select pg_temp.chk('K5 Active only off (coupon_required stays) → warning n=1', (select count(*) || '/' || coalesce(max(w->>'n'), '-') from jsonb_array_elements(:'k5a_r'::jsonb->'warnings') w where w->>'code' = 'deal_off_with_coupons') || '/' || (:'k5a_r'::jsonb->>'committed'), '1/1/true');
-- K6 (확인한 조건) is_order_level 끄기(단계 없는 쿠폰 딜) → so_coupon_check 가 deal_not_coupon 으로 보므로 경고
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'kd4', 'is_order_level', false), to_jsonb(:'ku4'::text), true, array['deal:' || :'kd4' || ':open_orders_flagged', 'deal:' || :'kd4' || ':deal_off_with_coupons']) as r \gset k6a_
reset role;
select pg_temp.chk('K6 order-level off on a coupon deal (coupons stop: so_coupon_check deal_not_coupon) → warning n=1', (select count(*) || '/' || coalesce(max(w->>'n'), '-') from jsonb_array_elements(:'k6a_r'::jsonb->'warnings') w where w->>'code' = 'deal_off_with_coupons') || '/' || (:'k6a_r'::jsonb->>'committed'), '1/1/true');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79921', 'SO-79922', 'SO-79923');
set local session_replication_role = origin;

-- ═══ C1 막힌 저장의 line_no_targets — 줄 1 대상 [] · 줄 2 대소문자만 다른 태그(막힘) → blocks tag_case_conflict · line_no_targets 는 줄 1 만(옛 함수는 둘 — 시험 갈래) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.dsc4d_pre_save(jsonb_build_object('name', 'DSC4D C1', 'lines', jsonb_build_array(
  jsonb_build_object('line_no', 1, 'pct', 5, 'targets', '[]'::jsonb),
  jsonb_build_object('line_no', 2, 'pct', 5, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'dsc4d-tag'))))), null, true) as r \gset c1pre_
select public.so_deal_save(jsonb_build_object('name', 'DSC4D C1', 'lines', jsonb_build_array(
  jsonb_build_object('line_no', 1, 'pct', 5, 'targets', '[]'::jsonb),
  jsonb_build_object('line_no', 2, 'pct', 5, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'dsc4d-tag'))))), null, true) as r \gset c1_
reset role;
select pg_temp.chk('C1 blocked save: blocks = tag_case_conflict · line_no_targets keys = line 1 only (pre: 1,2 in trial)', pg_temp.codes(:'c1_r'::jsonb, 'blocks') || '/' || (select coalesce(string_agg(w->>'key', ',' order by w->>'key'), '-') from jsonb_array_elements(:'c1_r'::jsonb->'warnings') w where w->>'code' = 'line_no_targets') || '/' || (select count(*) from jsonb_array_elements(:'c1pre_r'::jsonb->'warnings') w where w->>'code' = 'line_no_targets') || '/' || (:'c1_r'::jsonb->>'committed'), 'tag_case_conflict/deal:new:line_no_targets:1/' || case when :pre_broad then '2' else '1' end || '/false');
-- C1b 막히지 않은 저장에서는 그대로: 새 줄에 대상 없음 → 경고(ack) · 대상 있는 줄엔 없음
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4D C1b', 'is_active', false, 'lines', jsonb_build_array(
  jsonb_build_object('line_no', 1, 'pct', 5),
  jsonb_build_object('line_no', 2, 'pct', 5, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'px'))))), null, false) as r \gset c1b_
reset role;
select pg_temp.chk('C1b unblocked: new line without targets key → line_no_targets:1 only · no blocks', pg_temp.codes(:'c1b_r'::jsonb, 'blocks') || '/' || (select coalesce(string_agg(w->>'key', ',' order by w->>'key'), '-') from jsonb_array_elements(:'c1b_r'::jsonb->'warnings') w where w->>'code' = 'line_no_targets'), '-/deal:new:line_no_targets:1');

-- ═══ D1 min_qty 문구 — At least + 빈 수량 · At least + 0 · Full case + 수량 · None + 수량 (code min_qty_invalid 그대로) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4D D1', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 5, 'min_qty_mode', 'qty', 'targets', '[]'::jsonb))), null, false) as r \gset d1a_
select public.so_deal_save(jsonb_build_object('name', 'DSC4D D1', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 5, 'min_qty_mode', 'qty', 'min_qty', 0, 'targets', '[]'::jsonb))), null, false) as r \gset d1b_
select public.so_deal_save(jsonb_build_object('name', 'DSC4D D1', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 5, 'min_qty_mode', 'case', 'min_qty', 5, 'targets', '[]'::jsonb))), null, false) as r \gset d1c_
select public.so_deal_save(jsonb_build_object('name', 'DSC4D D1', 'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 5, 'min_qty_mode', 'none', 'min_qty', 5, 'targets', '[]'::jsonb))), null, false) as r \gset d1d_
reset role;
select pg_temp.chk('D1a At least + empty → new wording', (select b->>'code' || '|' || (b->>'message') from jsonb_array_elements(:'d1a_r'::jsonb->'blocks') b limit 1), 'min_qty_invalid|Line 1: "At least" needs a quantity above 0 — nothing was saved');
select pg_temp.chk('D1b At least + 0 → new wording with got', (select b->>'code' || '|' || (b->>'message') from jsonb_array_elements(:'d1b_r'::jsonb->'blocks') b limit 1), 'min_qty_invalid|Line 1: "At least" needs a quantity above 0 (got "0") — nothing was saved');
select pg_temp.chk('D1c Full case + quantity → new wording', (select b->>'code' || '|' || (b->>'message') from jsonb_array_elements(:'d1c_r'::jsonb->'blocks') b limit 1), 'min_qty_invalid|Line 1: a quantity is only used with "At least" (this line is "Full case") — nothing was saved');
select pg_temp.chk('D1d None + quantity → new wording', (select b->>'code' || '|' || (b->>'message') from jsonb_array_elements(:'d1d_r'::jsonb->'blocks') b limit 1), 'min_qty_invalid|Line 1: a quantity is only used with "At least" (this line is "None") — nothing was saved');
select pg_temp.chk('D1e key unchanged (deal:new:min_qty_invalid:1) · the blocked line sent no targets → line_no_targets still shown for it (C: [] was sent)', (select b->>'key' from jsonb_array_elements(:'d1a_r'::jsonb->'blocks') b limit 1) || '/' || (select count(*) from jsonb_array_elements(:'d1a_r'::jsonb->'warnings') w where w->>'code' = 'line_no_targets'), 'deal:new:min_qty_invalid:1/0');

-- ═══ G 재발행 · 개수 · 권한 · 무접촉 ═══
select pg_temp.chk('G1 one definition each: so_deal_save · so_deal_changed · so_deal_part_changed', (select string_agg(p.proname || '=' || c, ',' order by p.proname) from (select proname, count(*) c from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and proname in ('so_deal_save', 'so_deal_changed', 'so_deal_part_changed') group by 1) p), 'so_deal_changed=1,so_deal_part_changed=1,so_deal_save=1');
select pg_temp.chk('G2 trigger functions: no execute for authenticated · anon · public · so_deal_save: authenticated yes · anon no · public no', (select count(*)::text from unnest(array['public.so_deal_changed()', 'public.so_deal_part_changed()']) f where has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') or has_function_privilege('public', f, 'execute')) || '/' || has_function_privilege('authenticated', 'public.so_deal_save(jsonb, jsonb, boolean, text[])', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_deal_save(jsonb, jsonb, boolean, text[])', 'execute')::text || '/' || has_function_privilege('public', 'public.so_deal_save(jsonb, jsonb, boolean, text[])', 'execute')::text, '0/true/false/false');
select pg_temp.chk('G3 tag_unused branch untouched (old bytes found verbatim in the new body)', (select (position(substring(src from 'if cardinality\(v_unused\) > 0 then.*?v_keys := array_append\(v_keys, v_key \|\| '':tag_unused''\);\s*end if;') in (select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_save')) > 0)::text from t_pre where n = 'so_deal_save'), 'true');
select pg_temp.chk('G4 untouched functions same md5 (so_deal_products · so_deal_flag_open_orders · so_deal_list · so_deal_detail) · 10 flag triggers attached · trigger defs unchanged', (select count(*)::text from t_pre t join pg_proc p on p.proname = t.n join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public' where t.n in ('so_deal_products', 'so_deal_flag_open_orders', 'so_deal_list', 'so_deal_detail') and md5(p.prosrc) = md5(t.src)) || '/' || (select count(*) from pg_trigger where not tgisinternal and tgrelid::regclass::text in ('so_deal', 'so_deal_tier', 'so_deal_line', 'so_deal_target', 'so_deal_customer_rule') and tgfoid in (select oid from pg_proc where proname in ('so_deal_changed', 'so_deal_part_changed')) and tgenabled <> 'D') || '/' || (select count(*) from t_pre_trg t where t.def <> coalesce((select pg_get_triggerdef(g.oid) from pg_trigger g where g.tgname = t.n and not g.tgisinternal and g.tgrelid::regclass::text in ('so_deal', 'so_deal_tier', 'so_deal_line', 'so_deal_target', 'so_deal_customer_rule')), '')), '4/10/0');
select pg_temp.chk('G5 new bodies carry the door setting · so_deal_save carries v_nsent · "At least" · 347 condition', (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_deal_changed', 'so_deal_part_changed', 'so_deal_save') and p.prosrc like '%ims.deal_flag_door%') || '/' || (select (p.prosrc like '%v_nsent%' and p.prosrc like '%"At least"%' and p.prosrc like '%d.coupon_required and d.is_order_level%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_save'), '3/true');

-- ═══ 끝 ═══
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
