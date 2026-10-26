-- supabase/tests/exp_3_check.sql — exp-3 내보내기 칸 이름(Made in → Added in · Created → Added on) 검증 (2026-10-26 · 판정 766 · 767)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준 스냅샷(begin 앞 · 잠금 없음) → begin → (-v mig 면 \i) → 가짜 직원 셋(rollback) → 이름 · 키 · 순서 · 묶음 · 기본 켜짐 · 문 · 열쇠 가림 · 창구 출력 → rollback
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261026180000_exp_3_export_labels.sql -f supabase/tests/exp_3_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 적용 전 마른 실행은 이름 · md5 · comment 가 MISMATCH 로 끝난다(정상 · 아직 옛 이름)
--   기대 OK: 시험 = 확인 = 아래 EXPECT_OK
--   쓰기 0 — export_catalog 는 stable · 가짜 직원 행은 rollback · ims_staff 행 수 전후 대조
\set ON_ERROR_STOP on
\set EXPECT_OK 41
\pset pager off
-- 기준(begin 앞 · 잠금 없음): 칸 목록 스냅샷 · 함수 꼴 · 시험 재료(옛 시스템에서 온 행 하나씩)
create temp table t_before as
  select k.kind, c.ord, c.key, c.label, c.grp, c.dflt, c.gate, c.is_text from (values ('product'), ('customer'), ('supplier')) k(kind), lateral public.export_catalog(k.kind) c;
select count(*) as n_before from t_before \gset
select coalesce(p.proacl::text, '-') as acl0, p.prosecdef::text as def0, p.provolatile as vol0, coalesce(array_to_string(p.proconfig, ','), '-') as cfg0,
       coalesce(obj_description(p.oid, 'pg_proc'), '') as cmt0
from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'export_catalog' \gset
select count(*) as n_staff from public.ims_staff \gset
select p.sku as m_sku, to_char(p.created_at at time zone 'America/Toronto', 'YYYY-MM-DD') as m_sku_d from public.product p where p.source = 'cin7' and p.is_active order by p.sku limit 1 \gset
select c.name as m_cust, to_char(c.created_at at time zone 'America/Toronto', 'YYYY-MM-DD') as m_cust_d from public.customer c where c.source = 'cin7' and c.is_active order by c.name limit 1 \gset
select s.name as m_sup, to_char(s.created_at at time zone 'America/Toronto', 'YYYY-MM-DD') as m_sup_d from public.supplier s where s.source = 'cin7' and s.is_active order by s.name limit 1 \gset
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create temp table t_after as
  select k.kind, c.ord, c.key, c.label, c.grp, c.dflt, c.gate, c.is_text from (values ('product'), ('customer'), ('supplier')) k(kind), lateral public.export_catalog(k.kind) c;

-- ── L 이름 여섯 · 옛 이름 0 ──
select pg_temp.chk('L1 product source = Added in',     (select label from t_after where kind = 'product'  and key = 'source'),     'Added in');
select pg_temp.chk('L2 product created_at = Added on', (select label from t_after where kind = 'product'  and key = 'created_at'), 'Added on');
select pg_temp.chk('L3 customer source = Added in',    (select label from t_after where kind = 'customer' and key = 'source'),     'Added in');
select pg_temp.chk('L4 customer created_at = Added on',(select label from t_after where kind = 'customer' and key = 'created_at'), 'Added on');
select pg_temp.chk('L5 supplier source = Added in',    (select label from t_after where kind = 'supplier' and key = 'source'),     'Added in');
select pg_temp.chk('L6 supplier created_at = Added on',(select label from t_after where kind = 'supplier' and key = 'created_at'), 'Added on');
select pg_temp.chk('L7 old labels Made in / Created = 0', (select count(*)::text from t_after where label in ('Made in', 'Created')), '0');

-- ── S 이름 빼고 전부 그대로(키 · 순서 · 묶음 · 기본 켜짐 · 문 · 글자 칸) · 다른 키의 이름 그대로 · 칸 수 그대로 ──
select pg_temp.chk('S1 non-label columns before = after',
  (select count(*)::text from ((select kind, ord, key, grp, dflt, gate, is_text from t_before except select kind, ord, key, grp, dflt, gate, is_text from t_after)
                     union all (select kind, ord, key, grp, dflt, gate, is_text from t_after except select kind, ord, key, grp, dflt, gate, is_text from t_before)) x), '0');
select pg_temp.chk('S2 labels of other keys unchanged',
  (select count(*)::text from t_before b join t_after a on a.kind = b.kind and a.key = b.key where a.label <> b.label and b.key not in ('source', 'created_at')), '0');
select pg_temp.chk('S3 row count before = after', (select count(*)::text from t_after), :'n_before');

-- ── F 함수 꼴 그대로(ACL · definer · stable · search_path) · comment = 원문 + exp-3 꼬리 · md5 · overload 1 ──
select coalesce(p.proacl::text, '-') as acl1, p.prosecdef::text as def1, p.provolatile as vol1, coalesce(array_to_string(p.proconfig, ','), '-') as cfg1,
       coalesce(obj_description(p.oid, 'pg_proc'), '') as cmt1, md5(p.prosrc) as md5_1,
       (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = 'export_catalog') as n_ov
from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'export_catalog' \gset
\set cmt_tail ' · exp-3 판정 766 · 767 — source = Added in · created_at = Added on(옛 기록은 IMS 로 들어온 날)'
select pg_temp.chk('F1 acl unchanged (postgres only)', :'acl1', :'acl0');
select pg_temp.chk('F2 security definer', :'def1', 'true');
select pg_temp.chk('F3 stable', :'vol1', 's');
select pg_temp.chk('F4 search_path', :'cfg1', 'search_path=public, pg_temp');
select pg_temp.chk('F5 comment = exp-1 text + exp-3 tail', :'cmt1', replace(:'cmt0', :'cmt_tail', '') || :'cmt_tail');
select pg_temp.chk('F6 body md5 = exp-3', :'md5_1', 'bf108de21d64b2fb8e4ae93ed7c87c06');
select pg_temp.chk('F7 one export_catalog', :'n_ov', '1');

-- ── G 열쇠 가림 수 그대로 ──
select pg_temp.chk('G1 cost gate = 2',     (select count(*)::text from t_after where gate = 'cost'),    '2');
select pg_temp.chk('G2 contact gate = 17', (select count(*)::text from t_after where gate = 'contact'), '17');

-- ── E 창구 export_columns — 가짜 직원 셋(트랜잭션 안 · rollback) ──
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values
  (gen_random_uuid(), 'exp3-admin@test.invalid',  'exp3 admin',       'admin',  '[]', true),
  (gen_random_uuid(), 'exp3-master@test.invalid', 'exp3 master read', 'worker', '["master:read"]', true),
  (gen_random_uuid(), 'exp3-sales@test.invalid',  'exp3 sales read',  'worker', '["sales:read"]', true);
select max(auth_user_id::text) filter (where email = 'exp3-admin@test.invalid') as u_a, max(auth_user_id::text) filter (where email = 'exp3-master@test.invalid') as u_w,
       max(auth_user_id::text) filter (where email = 'exp3-sales@test.invalid') as u_s
from public.ims_staff where email like 'exp3-%@test.invalid' \gset
select set_config('request.jwt.claims', json_build_object('sub', :'u_a', 'role', 'authenticated')::text, true);
set local role authenticated;
create temp table t_cols as
  select k.kind, x.ord, x.c->>'key' as key, x.c->>'label' as label, x.c->>'group' as grp, (x.c->>'default')::boolean as dflt, (x.c->>'text')::boolean as is_text
  from (values ('product'), ('customer'), ('supplier')) k(kind), lateral jsonb_array_elements(public.export_columns(k.kind)->'columns') with ordinality x(c, ord);
select jsonb_array_length(public.export_columns('product')->'columns') as a_prod_n, jsonb_array_length(public.export_columns('customer')->'columns') as a_cust_n \gset
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'u_w', 'role', 'authenticated')::text, true);
set local role authenticated;
select jsonb_array_length(public.export_columns('product')->'columns') as w_prod_n \gset
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'u_s', 'role', 'authenticated')::text, true);
set local role authenticated;
select jsonb_array_length(public.export_columns('customer')->'columns') as s_cust_n \gset
reset role;
select pg_temp.chk('E1 admin product columns: source = Added in',      (select label from t_cols where kind = 'product'  and key = 'source'),     'Added in');
select pg_temp.chk('E2 admin product columns: created_at = Added on',  (select label from t_cols where kind = 'product'  and key = 'created_at'), 'Added on');
select pg_temp.chk('E3 admin customer columns: source = Added in',     (select label from t_cols where kind = 'customer' and key = 'source'),     'Added in');
select pg_temp.chk('E4 admin customer columns: created_at = Added on', (select label from t_cols where kind = 'customer' and key = 'created_at'), 'Added on');
select pg_temp.chk('E5 admin supplier columns: source = Added in',     (select label from t_cols where kind = 'supplier' and key = 'source'),     'Added in');
select pg_temp.chk('E6 admin supplier columns: created_at = Added on', (select label from t_cols where kind = 'supplier' and key = 'created_at'), 'Added on');
select pg_temp.chk('E7 admin product columns = catalog (nothing hidden)', :'a_prod_n', (select count(*)::text from t_after where kind = 'product'));
select pg_temp.chk('E8 master:read product columns = catalog - 2 (cost hidden)', :'w_prod_n', (select (count(*) - 2)::text from t_after where kind = 'product'));
select pg_temp.chk('E9 admin customer columns = catalog', :'a_cust_n', (select count(*)::text from t_after where kind = 'customer'));
select pg_temp.chk('E10 sales:read customer columns = catalog - 17 (contact hidden)', :'s_cust_n', (select (count(*) - 17)::text from t_after where kind = 'customer'));
select pg_temp.chk('E11 product: key · label · group · default · text in catalog order',
  (select string_agg(key || '|' || label || '|' || grp || '|' || dflt || '|' || is_text, ',' order by ord) from t_cols where kind = 'product'),
  (select string_agg(key || '|' || label || '|' || grp || '|' || dflt || '|' || is_text, ',' order by ord) from t_after where kind = 'product'));
select pg_temp.chk('E12 customer: key · label · group · default · text in catalog order',
  (select string_agg(key || '|' || label || '|' || grp || '|' || dflt || '|' || is_text, ',' order by ord) from t_cols where kind = 'customer'),
  (select string_agg(key || '|' || label || '|' || grp || '|' || dflt || '|' || is_text, ',' order by ord) from t_after where kind = 'customer'));
select pg_temp.chk('E13 supplier: key · label · group · default · text in catalog order',
  (select string_agg(key || '|' || label || '|' || grp || '|' || dflt || '|' || is_text, ',' order by ord) from t_cols where kind = 'supplier'),
  (select string_agg(key || '|' || label || '|' || grp || '|' || dflt || '|' || is_text, ',' order by ord) from t_after where kind = 'supplier'));

-- ── X 창구 출력(admin) — columns 의 이름 · 옛 시스템에서 온 행의 값(Before IMS · 토론토 날짜) ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_a', 'role', 'authenticated')::text, true);
set local role authenticated;
select x->'columns'->1->>'label' as xp_l1, x->'columns'->2->>'label' as xp_l2,
       (select r->>1 || '|' || (r->>2) from jsonb_array_elements(x->'rows') r where r->>0 = :'m_sku' limit 1) as xp_row
from (select public.product_export(p_q => :'m_sku', p_columns => array['sku', 'source', 'created_at']) x) s \gset
select x->'columns'->1->>'label' as xc_l1, x->'columns'->2->>'label' as xc_l2,
       (select r->>1 || '|' || (r->>2) from jsonb_array_elements(x->'rows') r where r->>0 = :'m_cust' limit 1) as xc_row
from (select public.customer_export(p_q => :'m_cust', p_columns => array['name', 'source', 'created_at']) x) s \gset
select x->'columns'->1->>'label' as xs_l1, x->'columns'->2->>'label' as xs_l2,
       (select r->>1 || '|' || (r->>2) from jsonb_array_elements(x->'rows') r where r->>0 = :'m_sup' limit 1) as xs_row
from (select public.supplier_export(p_q => :'m_sup', p_columns => array['name', 'source', 'created_at']) x) s \gset
reset role;
select pg_temp.chk('X1 product_export columns: Added in',  :'xp_l1', 'Added in');
select pg_temp.chk('X2 product_export columns: Added on',  :'xp_l2', 'Added on');
select pg_temp.chk('X3 product_export row: Before IMS | load date', :'xp_row', 'Before IMS|' || :'m_sku_d');
select pg_temp.chk('X4 customer_export columns: Added in', :'xc_l1', 'Added in');
select pg_temp.chk('X5 customer_export columns: Added on', :'xc_l2', 'Added on');
select pg_temp.chk('X6 customer_export row: Before IMS | load date', :'xc_row', 'Before IMS|' || :'m_cust_d');
select pg_temp.chk('X7 supplier_export columns: Added in', :'xs_l1', 'Added in');
select pg_temp.chk('X8 supplier_export columns: Added on', :'xs_l2', 'Added on');
select pg_temp.chk('X9 supplier_export row: Before IMS | load date', :'xs_row', 'Before IMS|' || :'m_sup_d');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤)'
select (select count(*) from public.ims_staff) = :n_staff as staff_same,
       (select md5(string_agg(kind || ord || key || label || grp || dflt || gate || is_text, ',' order by kind, ord)) from t_before)
       = (select md5(string_agg(k.kind || c.ord || c.key || c.label || c.grp || c.dflt || c.gate || c.is_text, ',' order by k.kind, c.ord)) from (values ('product'), ('customer'), ('supplier')) k(kind), lateral public.export_catalog(k.kind) c) as catalog_same;
