-- dsc-4e-verify.sql — 깃발(so.reprice_suggested_at)은 초안에만(판정 349) · 초안을 떠나면 지움(트리거) · 남은 깃발 정리 (Asung-IMS · 2026-10-07)
--   기대: 시험 갈래 OK 21 · 확인 갈래(G0 하나 없음 · E5 는 \if 로 가름) OK 20 · MISMATCH 0(시험 적용 2회차 통과 · 2026-10-07) · 실제 행(TEST POS SALE 15) md5 전후 같음 · 시퀀스 무변
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261007142513_dsc_4e_reprice_flag_draft_only.sql -f supabase/tests/dsc-4e-verify.sql 2>&1 | tee /tmp/dsc-4e.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료는 가짜만(DSC4E-* · SO-7993x · 2031년 · 가짜 손님 · 제품 · 직원) · 실제 오더 · 딜은 읽기만(상태별 깃발 수는 실제 행을 세어 보고만) · 번호를 당기는 창구는 쓰지 않는다(상태 변경은 표 직접 update — 트리거는 표에 붙어 어느 창구로 가든 같은 길) · 끝은 rollback
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
select coalesce(string_agg(s.status || '=' || s.n, ' · ' order by s.status), '-') as real_flags_head from (select status, count(*) n from public.so where reprice_suggested_at is not null and so_number not like 'SO-799%' group by status) s \gset
select count(*) as real_draft_flags from public.so where reprice_suggested_at is not null and status = 'draft' and so_number not like 'SO-799%' \gset
select count(*) as real_nondraft_flags from public.so where reprice_suggested_at is not null and status <> 'draft' and so_number not like 'SO-799%' \gset
\echo '== real flags by status (before):' :real_flags_head '· draft' :real_draft_flags '· non-draft' :real_nondraft_flags

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create temp table t_pre as
  select p.proname as n, p.prosrc as src from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public'
   and p.proname in ('so_deal_flag_open_orders', 'so_reprice', 'so_header_update', 'so_merge', 'so_confirm', 'so_unconfirm', 'so_cancel', 'so_pos_confirm', 'so_status_guard', 'so_product_flag_open_orders', 'so_deal_changed', 'so_deal_part_changed', 'product_tag_deal_hit_changed', 'so_deal_save');
-- E5 재료(시험 적용 전): 깃발이 선 가짜 Confirmed 오더 Cp · 깃발이 선 가짜 초안 Dp — 손님 2 · 제품 Y 라 E1 · E2 의 딜 · 태그 길에 걸리지 않는다(1회차: 같은 손님 · 제품이라 Dp 가 함께 찍혀 9 MISMATCH — 검증 쪽 결함)
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'dsc4e-master@test.invalid', 'DSC4E Master', 'manager', '["master","sales"]'::jsonb) returning auth_user_id::text as m_uid \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as wh1 from public.ref_warehouse order by name limit 1 \gset
select id::text as tier, name as tier_name from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' limit 1 \gset
insert into public.ref_brand (name) values ('DSC4E Brand') returning id::text as br \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('DSC4E Customer', 'manual', :'tier_name', :'wh1'::uuid, 0) returning id::text as cust \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('DSC4E Customer 2 (E5 only)', 'manual', :'tier_name', :'wh1'::uuid, 0) returning id::text as cust2 \gset
insert into public.product (sku, name, source, brand_id) values ('DSC4E-X', 'DSC4E Product X', 'manual', :'br'::uuid) returning id::text as px \gset
insert into public.product (sku, name, source, brand_id) values ('DSC4E-Y', 'DSC4E Product Y (E5 only · no deal targets it)', 'manual', :'br'::uuid) returning id::text as py \gset
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, reprice_suggested_at) values ('SO-79931', :'cust2'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', '2031-01-15', :'tier'::uuid, 0, now() - interval '1 hour') returning id::text as odp \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, confirmed_at, reprice_suggested_at) values ('SO-79932', :'cust2'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'confirmed', '2031-01-15', :'tier'::uuid, 0, now(), now() - interval '1 hour') returning id::text as ocp \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, unit_price) values (:'odp'::uuid, 1, :'py'::uuid, 'DSC4E-Y', 1, 1, 10, 10);
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, unit_price) values (:'ocp'::uuid, 1, :'py'::uuid, 'DSC4E-Y', 1, 1, 10, 10);
set local session_replication_role = origin;
select to_json(s.updated_at)::text as ocp_upd from public.so s where s.id = :'ocp'::uuid \gset
\if :{?mig}
select pg_temp.chk('G0 so_deal_flag_open_orders last def = 20261007005851:42~57', (select md5(src) from t_pre where n = 'so_deal_flag_open_orders'), '4e54213c1d24b2dc861ba952b685dde6');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\set applied true
\else
\set applied false
\endif
create function pg_temp.real_md5() returns text language sql as $$
  select md5(string_agg(x, '|' order by x)) from (
    select row(d.id, d.name, d.is_active, d.source, d.note, d.date_from, d.date_to, d.is_order_level, d.coupon_code, d.kind, d.coupon_required, d.updated_at, d.updated_by, d.created_at)::text as x from public.so_deal d where d.id = '7a6b411a-b2e4-4a7f-8735-d74f24b0c8c3'
    union all select row(l.id, l.deal_id, l.line_no, l.pct, l.min_qty_mode, l.min_qty, l.source, l.note, l.updated_at, l.is_active)::text from public.so_deal_line l where l.id = '28447237-8d1e-40e4-8b26-777600b50090'
    union all select row(t.id, t.line_id, t.kind, t.target, t.tag, t.brand_id, t.product_id, t.category_id, t.source, t.updated_at)::text from public.so_deal_target t where t.id = 'fa1d5e67-2068-40ba-9f23-cf567455a115') s
$$;
select pg_temp.real_md5() as real_in_before \gset
-- 가짜 오더만 센다: Dp = SO-79931 · Cp = SO-79932 · D = SO-79933(초안) · C = SO-79934(Confirmed) · 깃발 있는 것의 글자
create function pg_temp.flags() returns text language sql as $$
  select coalesce(string_agg(x.k, ',' order by x.k), '-') from (values ('Dp', 'SO-79931'), ('Cp', 'SO-79932'), ('D', 'SO-79933'), ('C', 'SO-79934')) x(k, n) join public.so s on s.so_number = x.n where s.reprice_suggested_at is not null
$$;

-- ═══ E5 데이터 정리 — 시험 적용 뒤 Cp(Confirmed) 는 null · Dp(초안) 는 그대로 · Cp 의 updated_at 도 그대로(touch 를 비꼈다) · 실제 행도 초안 깃발만 남음(확인 갈래: 적용 전 값과 같다) ═══
select pg_temp.chk('E5a fake rows after trial: Cp cleared · Dp kept (confirm branch: both kept — cleanup ran at apply time)', pg_temp.flags() || '/' || (select (to_json(s.updated_at)::text = :'ocp_upd')::text from public.so s where s.id = :'ocp'::uuid), case when :applied then 'Dp/true' else 'Cp,Dp/true' end);
select pg_temp.chk('E5b real rows: draft flags unchanged · non-draft flags 0 after trial (confirm branch: as before)', (select count(*) from public.so where reprice_suggested_at is not null and status = 'draft' and so_number not like 'SO-799%') || '/' || (select count(*) from public.so where reprice_suggested_at is not null and status <> 'draft' and so_number not like 'SO-799%'), :'real_draft_flags' || '/' || case when :applied then '0' else :'real_nondraft_flags' end);
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79931', 'SO-79932');
set local session_replication_role = origin;

-- ═══ E1 가짜 초안 D · 가짜 Confirmed C(같은 손님 · 같은 제품 X) → 줄 딜 켜기(창구 so_deal_save · 꺼진 채 만들고 손님 조건 뒤 켠다) → D 만 ═══
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct) values ('SO-79933', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', '2031-01-15', :'tier'::uuid, 0) returning id::text as od \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, confirmed_at) values ('SO-79934', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'confirmed', '2031-01-15', :'tier'::uuid, 0, now()) returning id::text as oc \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, unit_price) values (:'od'::uuid, 1, :'px'::uuid, 'DSC4E-X', 1, 1, 10, 10);
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, list_price, unit_price) values (:'oc'::uuid, 1, :'px'::uuid, 'DSC4E-X', 1, 1, 10, 10);
set local session_replication_role = origin;
select pg_temp.chk('E0 D draft · C confirmed · none flagged', pg_temp.flags() || '/' || (select status from public.so where id = :'od'::uuid) || '/' || (select status from public.so where id = :'oc'::uuid), '-/draft/confirmed');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4E Line Deal', 'date_from', '2031-01-01', 'date_to', '2031-12-31',
  'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 10, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'product', 'product_id', :'px')))),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), null, true, array['deal:new:open_orders_flagged']) as r \gset e1_
reset role;
select pg_temp.chk('E1 line deal on (deal path) → D only · C not · open_orders_to_flag 1', pg_temp.flags() || '/' || (:'e1_r'::jsonb->>'committed') || '/' || (:'e1_r'::jsonb->>'open_orders_to_flag'), 'D/true/1');
select (:'e1_r'::jsonb->>'deal_id') as d1, (:'e1_r'::jsonb->>'updated_at') as u1 \gset
select l.id::text as l1 from public.so_deal_line l where l.deal_id = :'d1'::uuid and l.line_no = 1 \gset
set local session_replication_role = replica;
update public.so set reprice_suggested_at = null where so_number in ('SO-79933', 'SO-79934');
set local session_replication_role = origin;

-- ═══ E2 제품 속성 길 — 태그 딜을 켜 두고 X 에 태그를 붙이면(product_tag 트리거 → so_product_flag_open_orders) D 만 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('name', 'DSC4E Tag Deal', 'date_from', '2031-01-01', 'date_to', '2031-12-31',
  'lines', jsonb_build_array(jsonb_build_object('line_no', 1, 'pct', 5, 'targets', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'tag', 'tag', 'DSC4E-Tag')))),
  'rules', jsonb_build_array(jsonb_build_object('kind', 'include', 'target', 'customer', 'customer_id', :'cust'))), null, true, array['deal:new:open_orders_flagged', 'deal:new:tag_unused']) as r \gset e2d_
select public.product_update(jsonb_build_array(jsonb_build_object('sku', 'DSC4E-X', 'op', 'tag_add', 'tag', 'DSC4E-Tag')), true) as r \gset e2_
reset role;
select pg_temp.chk('E2 tag_add on X (product attribute path) → D only · C not', pg_temp.flags() || '/' || (:'e2d_r'::jsonb->>'committed') || '/' || (:'e2_r'::jsonb->>'committed'), 'D/true/true');

-- ═══ E3 깃발 선 초안 D 를 Confirm(표 직접 update · 트리거 켜진 채 · so_status_guard 가 draft→confirmed 를 허락) → 깃발 null ═══
--   so_confirm 을 쓰지 않는 이유: 가짜 제품은 재고 0 이라 stock_short 분할(so_split)이 so_number 시퀀스를 당긴다 · 트리거는 so 표에 붙어 어느 창구로 떠나든 같은 길
update public.so set status = 'confirmed', confirmed_at = now() where id = :'od'::uuid;
select pg_temp.chk('E3 flagged draft → confirmed (status change) → flag cleared · status confirmed', pg_temp.flags() || '/' || (select status from public.so where id = :'od'::uuid), '-/confirmed');

-- ═══ E4 Unconfirm(표 직접 update · confirmed→draft 허락) → 초안으로 돌아와도 깃발은 다시 서지 않음 · 그 뒤 딜 % 를 바꾸면 초안이라 다시 선다 ═══
update public.so set status = 'draft', confirmed_at = null, unconfirmed_at = now() where id = :'od'::uuid;
select pg_temp.chk('E4a confirmed → draft (unconfirm shape) → no flag · status draft', pg_temp.flags() || '/' || (select status from public.so where id = :'od'::uuid), '-/draft');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_deal_save(jsonb_build_object('id', :'d1', 'lines', jsonb_build_array(jsonb_build_object('id', :'l1', 'line_no', 1, 'pct', 12))), to_jsonb(:'u1'::text), true, array['deal:' || :'d1' || ':open_orders_flagged']) as r \gset e4_
reset role;
select pg_temp.chk('E4b deal pct change after the round trip → D (draft again) flagged · C not', pg_temp.flags() || '/' || (:'e4_r'::jsonb->>'committed'), 'D/true');

-- ═══ E6 초안 → 초안(다른 칸 수정) 은 그대로 · 초안 → cancelled 는 지운다 · Confirmed 에 직접 세운 깃발(옛 자료 꼴)은 confirmed→draft 로 돌아와도 그대로(트리거는 초안을 떠날 때만) ═══
update public.so set comments = 'dsc-4e touch' where id = :'od'::uuid;
select pg_temp.chk('E6a draft → draft (other column) → flag kept', pg_temp.flags(), 'D');
update public.so set status = 'cancelled', closed_reason = 'voided', closed_at = now() where id = :'od'::uuid;
select pg_temp.chk('E6b draft → cancelled → flag cleared', pg_temp.flags() || '/' || (select status from public.so where id = :'od'::uuid), '-/cancelled');
set local session_replication_role = replica;
update public.so set reprice_suggested_at = now() where id = :'oc'::uuid;
set local session_replication_role = origin;
update public.so set status = 'draft', confirmed_at = null, unconfirmed_at = now() where id = :'oc'::uuid;
select pg_temp.chk('E6c flag set directly on confirmed C (legacy shape) · confirmed → draft → flag stays (trigger only when leaving draft)', pg_temp.flags() || '/' || (select status from public.so where id = :'oc'::uuid), 'C/draft');
update public.so set status = 'confirmed', confirmed_at = now(), unconfirmed_at = null where id = :'oc'::uuid;
select pg_temp.chk('E6d then draft → confirmed → cleared', pg_temp.flags(), '-');
-- E7 초안 insert 에 깃발을 실어 오는 꼴(so_merge 의 새 머리) 은 그대로 둔다 — 트리거는 UPDATE OF status 만
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, reprice_suggested_at) values ('SO-79935', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'draft', '2031-01-15', :'tier'::uuid, 0, now()) returning id::text as oe \gset
set local session_replication_role = origin;
select pg_temp.chk('E7 draft inserted with a flag (merge head shape) keeps it · non-draft flagged fake rows now 0', (select (reprice_suggested_at is not null)::text from public.so where id = :'oe'::uuid) || '/' || (select count(*) from public.so where so_number like 'SO-7993%' and status <> 'draft' and reprice_suggested_at is not null), 'true/0');

-- ═══ G 재발행 · 권한 · 트리거 · 무접촉 ═══
select pg_temp.chk('G1 flag function: status = draft only · no confirmed in body · 5-arg signature only', (select (p.prosrc like '%s.status = ''draft'' and s.reprice_suggested_at is null%' and p.prosrc not like '%''confirmed''%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_flag_open_orders') || '/' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_flag_open_orders') || '/' || (to_regprocedure('public.so_deal_flag_open_orders(uuid, date, date, boolean)') is null)::text, 'true/1/true');
select pg_temp.chk('G2 privileges: so_reprice_flag_draft_only · so_deal_flag_open_orders — no execute for authenticated · anon · public', (select count(*)::text from unnest(array['public.so_reprice_flag_draft_only()', 'public.so_deal_flag_open_orders(uuid, date, date, boolean, uuid[])']) f where has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') or has_function_privilege('public', f, 'execute')), '0');
select pg_temp.chk('G3 trigger attached (BEFORE UPDATE OF status · WHEN) · BEFORE UPDATE order on so', (select count(*)::text from pg_trigger where tgrelid = 'public.so'::regclass and tgname = 'so_reprice_flag_draft_only' and tgenabled <> 'D' and pg_get_triggerdef(oid) like 'CREATE TRIGGER so_reprice_flag_draft_only BEFORE UPDATE OF status ON public.so FOR EACH ROW WHEN %') || '/' || (select string_agg(tgname, '>' order by tgname) from pg_trigger where tgrelid = 'public.so'::regclass and not tgisinternal and tgtype & 2 = 2 and tgtype & 16 = 16), '1/so_reprice_flag_draft_only>so_status_guard>so_touch');
select pg_temp.chk('G4 untouched bodies same md5 (so_reprice · so_header_update · so_merge · so_confirm · so_unconfirm · so_cancel · so_pos_confirm · so_status_guard · so_product_flag_open_orders · so_deal_changed · so_deal_part_changed · product_tag_deal_hit_changed · so_deal_save = 13)', (select count(*)::text from t_pre t join pg_proc p on p.proname = t.n join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public' where t.n <> 'so_deal_flag_open_orders' and md5(p.prosrc) = md5(t.src)), '13');
select pg_temp.chk('G5 flag function callers unchanged (so_deal_changed · so_deal_part_changed · so_product_flag_open_orders still call it)', (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_deal_changed', 'so_deal_part_changed', 'so_product_flag_open_orders') and p.prosrc like '%so_deal_flag_open_orders(%'), '3');
select pg_temp.chk('G6 session_replication_role back to origin after the migration', current_setting('session_replication_role'), 'origin');

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
select coalesce(string_agg(s.status || '=' || s.n, ' · ' order by s.status), '-') as real_flags_tail from (select status, count(*) n from public.so where reprice_suggested_at is not null and so_number not like 'SO-799%' group by status) s \gset
\echo '== real flags by status (tail · rollback 뒤):' :real_flags_tail
select 'seq tail so ' || last_value || ' ' || is_called from public.so_number_seq;
select 'seq tail inv ' || last_value || ' ' || is_called from public.so_invoice_number_seq;
select 'seq tail cr ' || last_value || ' ' || is_called from public.so_credit_number_seq;
