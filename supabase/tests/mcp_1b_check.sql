-- supabase/tests/mcp_1b_check.sql — mcp-1b 검증: hist_line_kind 재정의(SET 없음 · 본문 · hist_credit_lines 무변) · mcp_name_pick · mcp_sales_cell · 도구 ⑥ mcp_sales(925 ~ 930 · 919 · 928 · 경계 · opening · 통화 · 권한 · 시간) (2026-11-01 UTC · 판정 918 ~ 930)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4 · 잠금 규칙) — 기준(begin 앞) → 시간 재기(시험 갈래: 짧은 트랜잭션 둘 · 각 \i → 재기 → rollback · 10 초 규칙 / 확인 갈래: begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i) → 가짜 재료 → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): MIG=supabase/migrations/20261101014251_mcp_1b_sales_summary.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/mcp_1b_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다(MIG= 도 필요 없다) — 두 갈래의 차이는 G0(시험만 · echo 줄 · t_res 밖) · 시간 재기 자리 · 기대 OK 수는 같다
--   쓰기: 가짜 직원 4 · 손님 3(본사 · 지점 · 단독) · 브랜드 1 · 공급처 2 · 서비스 1 · 제품 3 · hist 오더 4(줄 11) · IMS SO 3 · 인보이스 3(sale CAD · sale USD · opening) · 크레딧 1 · 레이어 5 · 소비 5 · ⚠️ mcp_config 한 줄의 claude_client_id 를 시험 값으로(rollback 으로 되돌아간다) · 시퀀스 무접촉(번호 명시) · 실제 행 0 변경
--   REST 두 겹: ① 아래 L1 nowhere 정적 셈 ② 실호출은 배포 뒤 Caleb 이 Claude 에서 질문 셋
\set ON_ERROR_STOP on
\set EXPECT_OK 50
\set cid mcp-test-client-79b
\pset pager off
select (select count(*) from public.hist_so) as n_hist, (select count(*) from public.hist_so_line) as n_hist_line, (select count(*) from public.inv_layer) as n_layer, (select count(*) from public.inv_layer_consume) as n_consume,
       (select count(*) from public.so_invoice) as n_inv, (select count(*) from public.so_credit) as n_credit, (select count(*) from public.product) as n_product, (select count(*) from public.customer) as n_cust,
       (select count(*) from public.ims_staff) as n_staff, (select count(*) from public.ref_brand) as n_brand, (select count(*) from public.supplier) as n_sup, (select count(*) from public.so) as n_so,
       (select claude_client_id from public.mcp_config where singleton) as cid0 \gset
select md5(string_agg(x::text, '|' order by x.seq)) as hcl_pre from public.hist_credit_lines('45215') x \gset
select md5(p.prosrc) as hlk_pre_md5, coalesce(p.proconfig::text, '(none)') as hlk_pre_cfg, coalesce(p.proacl::text, '(null)') as hlk_pre_acl from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'hist_line_kind' \gset
\echo '── 기준: hist_so' :n_hist '· hist_so_line' :n_hist_line '· inv_layer' :n_layer '· consume' :n_consume '· so_invoice' :n_inv '· so_credit' :n_credit '· product' :n_product '· customer' :n_cust '· staff' :n_staff '· hist_credit_lines(45215) md5' :hcl_pre '· hist_line_kind md5' :hlk_pre_md5 'cfg' :hlk_pre_cfg
-- ── 도우미(세션 임시 스키마 — 트랜잭션 밖에서 만들어 rollback 에 안 사라진다) ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
-- 역할 · claims 를 바꿔 한 문장을 돌린다(끝나면 되돌린다 · 오류는 'ERR sqlstate: msg' 글로) — mcp_1a_check 의 as_conn 그대로
create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
declare v text; v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERR ' || sqlstate || ': ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return coalesce(v, '(null)');
end $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  return coalesce(v, '(null)');
end $$;
create function pg_temp.cl(p_uid text, p_cid text) returns jsonb language sql as $$ select jsonb_strip_nulls(jsonb_build_object('sub', p_uid, 'role', 'ims_connector', 'aud', 'authenticated', 'client_id', p_cid)) $$;
create function pg_temp.keys(j jsonb) returns setof text language plpgsql as $$
declare r record;
begin
  if jsonb_typeof(j) = 'object' then
    for r in select key, value from jsonb_each(j) loop
      return next r.key;
      if jsonb_typeof(r.value) in ('object', 'array') then return query select pg_temp.keys(r.value); end if;
    end loop;
  elsif jsonb_typeof(j) = 'array' then
    for r in select value from jsonb_array_elements(j) loop
      if jsonb_typeof(r.value) in ('object', 'array') then return query select pg_temp.keys(r.value); end if;
    end loop;
  end if;
end $$;
create function pg_temp.st(v text, p text) returns text language sql as $$ select case when v like p || '%' then p else left(v, 120) end $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop
      v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g');
      exit when v_chunk = v_prev;
    end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
-- 가짜 admin 직원(claude · 원가는 역할로) + mcp_config 시험 값 — 시간 재기 트랜잭션마다 · 본 트랜잭션에서도(전부 rollback)
create function pg_temp.setup_admin() returns text language plpgsql as $$
declare v_uid uuid := gen_random_uuid();
begin
  insert into public.ims_staff (id, auth_user_id, email, name, role, perms, is_active) values ('79b00000-0000-4000-8000-000000000001', v_uid, 'mcp79b-a@test.invalid', 'MCP1b Fake Admin', 'admin', '["claude"]'::jsonb, true);
  update public.mcp_config set claude_client_id = 'mcp-test-client-79b' where singleton;
  return v_uid::text;
end $$;
create function pg_temp.timed(p_uid text, p_group text) returns numeric language plpgsql as $$
declare t timestamptz; v text;
begin
  t := clock_timestamp();
  v := pg_temp.as_conn('ims_connector', pg_temp.cl(p_uid, 'mcp-test-client-79b'), format($q$select public.mcp_sales('2025-11-01', '2026-10-31', %L, null, null, null, null, 50)->'totals'->>'sales'$q$, p_group));
  if left(v, 4) = 'ERR ' then raise exception 'timed % failed: %', p_group, v; end if;
  return round(extract(epoch from clock_timestamp() - t) * 1000);
end $$;

-- ── 실물 시간(1 년 × 묶음 다섯 · ims_connector · 8 초 예산) ──
\if :{?mig}
\echo '── 시간 재기(시험 갈래 · 트랜잭션 둘 · rollback 됨):' :mig
begin;
set local lock_timeout = '3s';
\i :mig
select pg_temp.setup_admin() as t_uid \gset
select pg_temp.timed(:'t_uid', 'brand') as ms_brand, pg_temp.timed(:'t_uid', 'month') as ms_month, pg_temp.timed(:'t_uid', 'customer') as ms_customer \gset
rollback;
begin;
set local lock_timeout = '3s';
\i :mig
select pg_temp.setup_admin() as t_uid \gset
select pg_temp.timed(:'t_uid', 'sku') as ms_sku, pg_temp.timed(:'t_uid', 'supplier') as ms_supplier \gset
select round(extract(epoch from clock_timestamp() - t) * 1000) as a5_ms from (select clock_timestamp() as t) s, lateral (select count(*) from (select upper(hl.sku), sum(hl.sale) from public.hist_so h join public.hist_so_line hl on hl.hist_so_id = h.id where h.invoice_date between '2025-11-01' and '2026-10-31' and hl.doc_type = 'invoice' and public.hist_line_kind(hl.sku) = 'product' group by 1) x) c \gset
rollback;
\else
\echo '── 시간 재기(확인 갈래 · begin 앞 · 가짜 직원은 트랜잭션 안 · rollback 됨)'
begin;
set local lock_timeout = '3s';
select pg_temp.setup_admin() as t_uid \gset
select pg_temp.timed(:'t_uid', 'brand') as ms_brand, pg_temp.timed(:'t_uid', 'month') as ms_month, pg_temp.timed(:'t_uid', 'customer') as ms_customer \gset
rollback;
begin;
set local lock_timeout = '3s';
select pg_temp.setup_admin() as t_uid \gset
select pg_temp.timed(:'t_uid', 'sku') as ms_sku, pg_temp.timed(:'t_uid', 'supplier') as ms_supplier \gset
select round(extract(epoch from clock_timestamp() - t) * 1000) as a5_ms from (select clock_timestamp() as t) s, lateral (select count(*) from (select upper(hl.sku), sum(hl.sale) from public.hist_so h join public.hist_so_line hl on hl.hist_so_id = h.id where h.invoice_date between '2025-11-01' and '2026-10-31' and hl.doc_type = 'invoice' and public.hist_line_kind(hl.sku) = 'product' group by 1) x) c \gset
rollback;
\endif
\echo '── 1 년 × 묶음(ms): brand' :ms_brand '· month' :ms_month '· customer' :ms_customer '· sku' :ms_sku '· supplier' :ms_supplier '· A5 hist_line_kind WHERE' :a5_ms

-- ── 본 트랜잭션 ──
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
select pg_temp.chk('S1 시간: 1 년 × 묶음 다섯 전부 8 초 안(brand ' || :'ms_brand' || ' · month ' || :'ms_month' || ' · customer ' || :'ms_customer' || ' · sku ' || :'ms_sku' || ' · supplier ' || :'ms_supplier' || ')',
  (greatest(:ms_brand, :ms_month, :ms_customer, :ms_sku, :ms_supplier) < 8000)::text, 'true');

-- ── A) hist_line_kind 재정의(이견 1) ──
select pg_temp.chk('A1 hist_line_kind: SET 없음 · 본문 md5 그대로(앞 ' || :'hlk_pre_cfg' || ')', (select coalesce(p.proconfig::text, '(none)') || ' ' || (md5(p.prosrc) = :'hlk_pre_md5')::text || ' ' || md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'hist_line_kind'), '(none) true c098f08cc8a0d588d1cb87836d257c2d');
select pg_temp.chk('A2 hist_credit_lines(45215) 결과 md5 재정의 전후 같음', (select md5(string_agg(x::text, '|' order by x.seq)) from public.hist_credit_lines('45215') x), :'hcl_pre');
select pg_temp.chk('A3 hist_line_kind 값 그대로(_4_ · Shipping - X · Discount · Order total discount · Customer Credit Write-off · CREDIT-01 · AAL10850 · null)',
  (select string_agg(public.hist_line_kind(s), ' ') from unnest(array['_4_', 'Shipping - Standard', 'Discount', 'Order total discount', 'Customer Credit Write-off', 'CREDIT-01', 'AAL10850', null]) s), 'freight freight discount discount hidden hidden product product');
select pg_temp.chk('A5 인라인 증거(시간): 1 년 sku 묶음에 hist_line_kind 를 WHERE 로 — 3 초 안(SET 있던 때 5.9 초 · 잰 값 ' || :'a5_ms' || ' ms)', (:a5_ms < 3000)::text, 'true');

-- ── R) 실물 단언(928 · 929 · 경계) ──
select pg_temp.chk('R1 928: inv_layer_consume sale_out 첫 날 = 2026-08-21(mcp_sales 의 c_cost_from)', (select min(occurred_on)::text from public.inv_layer_consume where event_type = 'sale_out'), '2026-08-21');
select pg_temp.chk('R2 929: 손님 parent 사슬 깊이 1(부모의 부모 0)', (select count(*) from public.customer c join public.customer p on p.id = c.parent_id where p.parent_id is not null)::text, '0');
select pg_temp.chk('R3 경계: IMS so 번호 ∩ hist 오더 번호 = 0 · kind sale 인보이스 번호 ∩ hist invoice_number = 0', (select count(*) from public.so s where exists (select 1 from public.hist_so h where h.order_number = s.so_number))::text || ' ' || (select count(*) from public.so_invoice i where i.kind = 'sale' and exists (select 1 from public.hist_so h where h.invoice_number = i.invoice_number))::text, '0 0');
select pg_temp.chk('R4 권한: mcp_sales = postgres + ims_connector · 도우미 둘 = postgres 만 · PUBLIC EXECUTE 0',
  (select string_agg(p.proname || '=' || p.proacl::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_sales', 'mcp_name_pick', 'mcp_sales_cell')) || ' ' ||
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'))::text,
  'mcp_name_pick={postgres=X/postgres} mcp_sales={postgres=X/postgres,ims_connector=X/postgres} mcp_sales_cell={postgres=X/postgres} 0');
select pg_temp.chk('R5 mcp_sales · mcp_name_pick: definer · stable · search_path 고정(+ work_mem) · mcp_sales_cell: immutable · hist_line_kind: immutable · SET 없음',
  (select string_agg(p.proname || ':' || p.prosecdef::text || p.provolatile::text || coalesce(p.proconfig::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_sales', 'mcp_name_pick', 'mcp_sales_cell', 'hist_line_kind')),
  'hist_line_kind:falsei- mcp_name_pick:trues{"search_path=public, pg_temp"} mcp_sales:trues{"search_path=public, pg_temp",work_mem=32MB} mcp_sales_cell:falsei-');
select pg_temp.chk('L1 REST 정적: 새 함수 넷의 깊이 0 WHERE 없는 update · delete 0', (select sum(pg_temp.nowhere(p.prosrc))::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_sales', 'mcp_name_pick', 'mcp_sales_cell', 'hist_line_kind')), '0');

-- ── 가짜 재료(79b · 메모 · 이메일 · 전화를 일부러 채운다 — 923) ──
create temp table t_f as select
  '79b00000-0000-4000-8000-000000000001'::uuid as a_id, '79b00000-0000-4000-8000-000000000002'::uuid as b_id, '79b00000-0000-4000-8000-000000000003'::uuid as c_id, '79b00000-0000-4000-8000-000000000004'::uuid as d_id,
  '79b00000-0000-4000-8000-000000000011'::uuid as hq_id, '79b00000-0000-4000-8000-000000000012'::uuid as br_id, '79b00000-0000-4000-8000-000000000013'::uuid as solo_id,
  '79b00000-0000-4000-8000-000000000021'::uuid as brand_id, '79b00000-0000-4000-8000-000000000031'::uuid as s79_id, '79b00000-0000-4000-8000-000000000032'::uuid as s78_id, '79b00000-0000-4000-8000-000000000041'::uuid as svc_id,
  '79b00000-0000-4000-8000-000000000051'::uuid as p1_id, '79b00000-0000-4000-8000-000000000052'::uuid as p2_id, '79b00000-0000-4000-8000-000000000053'::uuid as p3_id,
  '79b00000-0000-4000-8000-000000000061'::uuid as h1_id, '79b00000-0000-4000-8000-000000000062'::uuid as h2_id, '79b00000-0000-4000-8000-000000000063'::uuid as h3_id, '79b00000-0000-4000-8000-000000000064'::uuid as h4_id,
  '79b00000-0000-4000-8000-000000000071'::uuid as so5_id, '79b00000-0000-4000-8000-000000000072'::uuid as so6_id, '79b00000-0000-4000-8000-000000000075'::uuid as so7_id, '79b00000-0000-4000-8000-000000000073'::uuid as l1_id, '79b00000-0000-4000-8000-000000000074'::uuid as l2_id,
  '79b00000-0000-4000-8000-000000000081'::uuid as inv1_id, '79b00000-0000-4000-8000-000000000082'::uuid as inv2_id, '79b00000-0000-4000-8000-000000000083'::uuid as inv0_id,
  '79b00000-0000-4000-8000-000000000084'::uuid as io1_id, '79b00000-0000-4000-8000-000000000085'::uuid as io2_id, '79b00000-0000-4000-8000-000000000086'::uuid as io0_id,
  '79b00000-0000-4000-8000-000000000087'::uuid as il1_id, '79b00000-0000-4000-8000-000000000091'::uuid as ch1_id, '79b00000-0000-4000-8000-000000000092'::uuid as ch2_id, '79b00000-0000-4000-8000-000000000095'::uuid as cr_id,
  '045e4ca6-b7a9-446e-9e6a-a5a0db56d456'::uuid as wh_tor, 'e6f5d46f-b345-47e2-916c-f7f64aeb78b7'::uuid as cad, '74a32987-8bc5-4f9e-a2c7-6479ed483766'::uuid as usd, '70c5fc7f-c640-4181-83b9-01fd67427a83'::uuid as tax_exempt,
  'mcp-test-client-79b'::text as cid;
select pg_temp.setup_admin() as a_uid \gset
select set_config('mcp.a_uid', :'a_uid', true);
insert into public.ims_staff (id, auth_user_id, email, name, role, perms, is_active)
select b_id, gen_random_uuid(), 'mcp79b-b@test.invalid', 'MCP1b Fake B', 'manager', '["ims","claude","sales"]'::jsonb, true from t_f union all
select c_id, gen_random_uuid(), 'mcp79b-c@test.invalid', 'MCP1b Fake C', 'manager', '["ims","sales"]'::jsonb, true from t_f union all
select d_id, gen_random_uuid(), 'mcp79b-d@test.invalid', 'MCP1b Fake D', 'manager', '["ims","claude"]'::jsonb, true from t_f;
select s.auth_user_id as b_uid from public.ims_staff s where s.id = (select b_id from t_f) \gset
select s.auth_user_id as c_uid from public.ims_staff s where s.id = (select c_id from t_f) \gset
select s.auth_user_id as d_uid from public.ims_staff s where s.id = (select d_id from t_f) \gset
insert into public.ref_brand (id, name, source) select brand_id, 'MCP Brand 79', 'manual' from t_f;
insert into public.supplier (id, name, payment_term_name, account_payable_code, source) select s79_id, 'MCP Supplier 79', 'Net 30', '2000', 'manual' from t_f union all select s78_id, 'MCP Supplier 78', 'Net 30', '2000', 'manual' from t_f;
insert into public.ref_service (id, name, unit_price) select svc_id, 'MCP Service 79', 5 from t_f;
insert into public.product (id, name, sku, brand_id, brand_name, source) select p1_id, 'MCP Product One', 'MCP79001', brand_id, 'MCP Brand 79', 'manual' from t_f union all select p2_id, 'MCP Product Two', 'MCP79002', brand_id, 'MCP Brand 79', 'manual' from t_f union all select p3_id, 'MCP Product Three', 'MCP79003', null, null, 'manual' from t_f;
insert into public.product_supplier (product_id, supplier_id, is_default, is_active, source) select p1_id, s79_id, true, true, 'manual' from t_f union all select p2_id, s79_id, true, true, 'manual' from t_f union all select p2_id, s78_id, true, true, 'manual' from t_f;
insert into public.customer (id, name, source, currency_id, currency_code, note) select hq_id, 'MCP HQ 79', 'manual', cad, 'CAD', 'MCP-MEMO-79B-HQ' from t_f union all select solo_id, 'MCP Solo 79', 'manual', cad, 'CAD', 'MCP-MEMO-79B-SOLO' from t_f;
insert into public.customer (id, name, source, currency_id, currency_code, parent_id, parent_source) select br_id, 'MCP Branch 79', 'manual', cad, 'CAD', hq_id, 'ims' from t_f;
insert into public.customer_contact (customer_id, name, email, phone, source, is_default) select hq_id, 'MCP Contact 79B', 'mcp79b@test.invalid', '416-555-7979', 'manual', true from t_f;
-- ⚠️ 가짜 날짜는 실자료가 없는 2026-11 ~ 12(hist 는 10-31 까지 · IMS 실제 인보이스 0) — 같은 기간에 두면 실자료와 섞여 합이 안 맞는다(첫 판 실수) · 원가 전(H3 08-10)은 가짜 손님 거르기로 가둔다
-- 이력: H1 본사(11-10 · 제품 둘 · 운임 · 오더 할인 · 숨은 줄 · _10_ · 크레딧 10-05 제품 + 운임) · H2 지점(09-20 · 브랜드 없는 제품) · H3 단독(08-10 · 원가 전) · H4 단독(10-31 · 경계)
insert into public.hist_so (id, era, order_number, customer_id, customer_name, invoice_date, invoice_number, source, line_count)
select h1_id, 'core', 'SO-79101', hq_id, 'MCP HQ 79', '2026-11-10'::date, '79101', 'bq_confirmed', 8 from t_f union all
select h2_id, 'core', 'SO-79102', br_id, 'MCP Branch 79', '2026-11-20', '79102', 'bq_confirmed', 1 from t_f union all
select h3_id, 'core', 'SO-79103', solo_id, 'MCP Solo 79', '2026-08-10', '79103', 'bq_confirmed', 1 from t_f union all
select h4_id, 'core', 'SO-79104', solo_id, 'MCP Solo 79', '2026-12-31', '79104', 'bq_confirmed', 1 from t_f;
insert into public.hist_so_line (hist_so_id, seq, doc_type, doc_number, doc_date, sku, product_id, product_name, brand, quantity, unit_price, sale, is_return)
select h1_id, 1, 'invoice', '79101', '2026-11-10'::date, 'MCP79001', p1_id, 'MCP Product One', 'MCP Brand 79', 10::numeric, 10::numeric, 100::numeric, false from t_f union all
select h1_id, 2, 'invoice', '79101', '2026-11-10', 'MCP79002', p2_id, 'MCP Product Two', 'MCP Brand 79', 5, 10, 50, false from t_f union all
select h1_id, 3, 'invoice', '79101', '2026-11-10', '_4_', null, 'Freight', null, 1, 15, 15, false from t_f union all
select h1_id, 4, 'invoice', '79101', '2026-11-10', 'Order total discount', null, 'Order total discount', null, 1, -10, -10, false from t_f union all
select h1_id, 5, 'invoice', '79101', '2026-11-10', 'Customer Credit', null, 'Customer Credit', null, 1, -5, -5, false from t_f union all
select h1_id, 6, 'invoice', '79101', '2026-11-10', '_10_', null, 'Package Cost', null, 1, 3, 3, false from t_f union all
select h1_id, 7, 'credit', 'CR-79101', '2026-12-05', 'MCP79001', p1_id, 'MCP Product One', 'MCP Brand 79', -2, 10, -20, true from t_f union all
select h1_id, 8, 'credit', 'CR-79101', '2026-12-05', '_4_', null, 'Freight', null, -1, 3, -3, true from t_f union all
select h2_id, 1, 'invoice', '79102', '2026-11-20', 'MCP79003', p3_id, 'MCP Product Three', null, 4, 10, 40, false from t_f union all
select h3_id, 1, 'invoice', '79103', '2026-08-10', 'MCP79001', p1_id, 'MCP Product One', 'MCP Brand 79', 1, 12, 12, false from t_f union all
select h4_id, 1, 'invoice', '79104', '2026-12-31', 'MCP79001', p1_id, 'MCP Product One', 'MCP Brand 79', 2, 10, 20, false from t_f;
-- IMS: SO-79105(단독 · CAD · 인보이스 79901 10-15: 제품 33 · 운임 8 · 서비스 5 · 오더 할인 -2 · 할증 1.5) · SO-79106(USD · 인보이스 79902 · 제품 99 → 제외) · opening 79101(= hist 번호 · 제품 999 → 제외) · 크레딧 CR-79901 10-20(제품 11 · other 2)
insert into public.so (id, so_number, customer_id, channel, intake, status, currency_id, currency_code, location_id, location_name, order_date, comments)   -- so_status_guard: 새 오더는 draft 로만(mcp_sales 는 so.status 를 보지 않는다 · 인보이스가 기준)
select so5_id, 'SO-79105', solo_id, 'warehouse', 'manual', 'draft', cad, 'CAD', wh_tor, 'Asung Trading Inc.', '2026-12-14'::date, 'MCP-MEMO-79B-SO' from t_f union all
select so6_id, 'SO-79106', solo_id, 'warehouse', 'manual', 'draft', usd, 'USD', wh_tor, 'Asung Trading Inc.', '2026-12-14', null from t_f union all
select so7_id, 'SO-79107', solo_id, 'warehouse', 'manual', 'draft', cad, 'CAD', wh_tor, 'Asung Trading Inc.', '2026-11-10', null from t_f;   -- opening 인보이스 자리(active_so_id 유니크 · SO 하나에 산 인보이스 하나)
insert into public.so_line (id, so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, unit_price)
select l1_id, so5_id, 1, p1_id, 'MCP79001', 'MCP Product One', 1::numeric, 3::numeric, 3::numeric, 11::numeric from t_f union all select l2_id, so6_id, 1, p1_id, 'MCP79001', 'MCP Product One', 1, 9, 9, 11 from t_f;
insert into public.so_charge (id, so_id, line_no, name, amount, qty, unit_price, service_id) select ch1_id, so5_id, 1, 'Standard', 8::numeric, null::numeric, null::numeric, null::uuid from t_f union all select ch2_id, so5_id, 2, 'MCP Service 79', 5, 1, 5, svc_id from t_f;
insert into public.so_invoice (id, invoice_number, bill_to_customer_id, issued_on, currency_id, currency_code, lines_amount, order_discount_amount, charges_amount, surcharge_amount, taxable_amount, tax_amount, total, amount_due, kind, note)
select inv1_id, '79901', solo_id, '2026-12-15'::date, cad, 'CAD', 33::numeric, -2::numeric, 13::numeric, 1.5::numeric, 45.5::numeric, 0::numeric, 45.5::numeric, 45.5::numeric, 'sale', 'MCP-MEMO-79B-INV' from t_f union all
select inv2_id, '79902', solo_id, '2026-12-16', usd, 'USD', 99, 0, 0, 0, 99, 0, 99, 99, 'sale', null from t_f;
insert into public.so_invoice (id, invoice_number, bill_to_customer_id, issued_on, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due, kind, legacy_sale_id, legacy_invoice_id, store_customer_id)
select inv0_id, '79101', solo_id, '2026-11-10', cad, 'CAD', 999, 999, 0, 999, 999, 'opening', 'legacy-79b', 'legacy-inv-79b', solo_id from t_f;
insert into public.so_invoice_order (id, invoice_id, so_id, so_number, customer_id, tax_rule_id, tax_rule, rate_pct, tax_source, lines_amount, order_discount_amount, charges_amount, surcharge_amount, taxable_amount, tax_amount, total)
select io1_id, inv1_id, so5_id, 'SO-79105', solo_id, tax_exempt, 'Exempt (Sale)', 0::numeric, 'manual', 33::numeric, -2::numeric, 13::numeric, 1.5::numeric, 45.5::numeric, 0::numeric, 45.5::numeric from t_f union all
select io2_id, inv2_id, so6_id, 'SO-79106', solo_id, tax_exempt, 'Exempt (Sale)', 0, 'manual', 99, 0, 0, 0, 99, 0, 99 from t_f union all
select io0_id, inv0_id, so7_id, 'SO-79107', solo_id, tax_exempt, 'Exempt (Sale)', 0, 'manual', 999, 0, 0, 0, 999, 0, 999 from t_f;
insert into public.so_invoice_line (id, invoice_id, invoice_order_id, line_no, kind, so_line_id, so_charge_id, sku, qty, unit_price, amount)
select il1_id, inv1_id, io1_id, 1, 'product', l1_id, null::uuid, 'MCP79001', 3::numeric, 11::numeric, 33::numeric from t_f union all
select gen_random_uuid(), inv1_id, io1_id, 2, 'charge', null, ch1_id, null, null, null, 8 from t_f union all
select gen_random_uuid(), inv1_id, io1_id, 3, 'charge', null, ch2_id, null, 1, 5, 5 from t_f union all
select gen_random_uuid(), inv1_id, io1_id, 4, 'order_discount', null, null, null, null, null, -2 from t_f union all
select gen_random_uuid(), inv1_id, io1_id, 5, 'surcharge', l1_id, null, 'MCP79001', 3, 0.5, 1.5 from t_f union all
select gen_random_uuid(), inv2_id, io2_id, 1, 'product', l2_id, null, 'MCP79001', 9, 11, 99 from t_f union all
select gen_random_uuid(), inv0_id, io0_id, 1, 'product', l1_id, null, 'MCP79001', 1, 999, 999 from t_f;
insert into public.so_credit (id, credit_number, customer_id, currency_id, currency_code, invoice_id, reason, warehouse_id, warehouse_name, issued_on, lines_amount, total, note)
select cr_id, 'CR-79901', solo_id, cad, 'CAD', inv1_id, 'customer_return', wh_tor, 'Asung Trading Inc.', '2026-12-20'::date, 13::numeric, 13::numeric, 'MCP-MEMO-79B-CR' from t_f;
insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, so_line_id, product_id, sku, qty_returned, not_restocked_reason, unit_price, amount)
select cr_id, 1, 'product', il1_id, l1_id, p1_id, 'MCP79001', 1::numeric, 'damaged', 11::numeric, 11::numeric from t_f union all
select cr_id, 2, 'other', null::uuid, null::uuid, null::uuid, null::text, null::numeric, null::text, null::numeric, 2::numeric from t_f;
-- 원가: 레이어 셋(단가 4 · 3 · 2) · 소비 다섯(이력 오더 × SKU · IMS so_line.id · 못 맞는 하나) · 재입고 복원 둘(크레딧 번호 × SKU)
create temp table t_l as select * from (values ('MCP79001', 4::numeric), ('MCP79002', 3), ('MCP79003', 2)) v(sku, uc);
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source)
select sku, 'Asung Trading Inc.', 'purchase', 'PO-79B', 'mcp79b', '2026-08-01', true, 100, uc, 'manual' from t_l;
insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason)
select l.id, 'sale', x.doc, x.ref, 'sale_out', x.d, x.q, l.unit_cost, x.q * l.unit_cost, 'sale'
  from (values ('SO-79101', 'cin7-ref:p1', 'MCP79001', '2026-11-09'::date, 10::numeric), ('SO-79101', 'cin7-ref:p2', 'MCP79002', '2026-11-09', 5), ('SO-79101', 'cin7-ref:p3', 'MCP79003', '2026-11-09', 1),
               ('SO-79104', 'cin7-ref:p1', 'MCP79001', '2026-12-30', 2), ('SO-79105', (select l1_id::text from t_f), 'MCP79001', '2026-12-14', 3)) x(doc, ref, sku, d, q)
  join public.inv_layer l on l.sku = x.sku and l.doc_number = 'PO-79B' and l.origin_type = 'purchase';
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source)
values ('MCP79001', 'Asung Trading Inc.', 'creditnote', 'CR-79101', 'mcp79b', '2026-12-05', true, 2, 4, 'return_restore'), ('MCP79001', 'Asung Trading Inc.', 'creditnote', 'CR-79901', 'mcp79b', '2026-12-20', true, 1, 4, 'return_restore');

-- ── T) 도구 ⑥ — ⓐ admin(claude · 원가는 역할로) · 역할 ims_connector ──
create temp table t_out (k text primary key, j jsonb, ms numeric);
do $$
declare v_t timestamptz; v text; v_k text; v_sql text; v_claims jsonb := pg_temp.cl(current_setting('mcp.a_uid'), 'mcp-test-client-79b');
begin
  for v_k, v_sql in select * from (values
      ('brand',  $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'brand')::text$q$),
      ('month',  $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'month')::text$q$),
      ('cust',   $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'customer')::text$q$),
      ('cust_br', $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'customer', null, 'MCP Branch 79')::text$q$),
      ('cust_hq', $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'month', null, 'mcp hq 79')::text$q$),
      ('sup',    $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'supplier')::text$q$),
      ('sup_78', $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'sku', null, null, null, 'Supplier 78')::text$q$),
      ('sup_amb', $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'sku', null, null, null, 'MCP Supplier 7')::text$q$),
      ('sku2',   $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'sku', null, null, null, null, 2)::text$q$),
      ('sku_p1', $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'month', null, null, 'mcp79001')::text$q$),
      ('brand_f', $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'sku', 'MCP Bra')::text$q$),
      ('brand_x', $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'sku', 'ZZZNOBRAND79')::text$q$),
      ('aug',    $q$select public.mcp_sales('2026-08-01', '2026-08-31', 'brand', null, 'MCP Solo 79')::text$q$),
      ('pre',    $q$select public.mcp_sales('2026-07-01', '2026-08-15', 'brand', null, 'MCP Solo 79')::text$q$)) t(k, s) loop
    v_t := clock_timestamp();
    v := pg_temp.as_conn('ims_connector', v_claims, v_sql);
    if left(v, 4) = 'ERR ' then raise exception 'tool % failed: %', v_k, v; end if;
    insert into t_out values (v_k, v::jsonb, round(extract(epoch from clock_timestamp() - v_t) * 1000, 1));
  end loop;
end $$;
select k, ms, left(j::text, 100) as head from t_out order by k;
create function pg_temp.row_of(p_k text, p_key text) returns jsonb language sql as $$ select x from t_out, jsonb_array_elements(j->'rows') x where k = p_k and x->>'key' = p_key $$;
create function pg_temp.cell(j jsonb) returns text language sql as $$
  select concat_ws(' ', j->>'sales', j->>'credits', j->>'net', j->>'qty', j->>'qty_credited', coalesce(j->>'cogs', '-'), coalesce(j->>'gp', '-'), coalesce(j->>'gp_pct', '-'), coalesce(j->>'net_costed', '-'), coalesce(j->>'uncosted_sales', '-')) $$;
-- 식으로 계산한 기대값(가짜 재료 · 주석의 셈)
--   브랜드 MCP Brand 79: 판매 100 + 50 + 20 + 33 = 203 · 크레딧 20 + 11 = 31 · 순 172 · 수량 10 + 5 + 2 + 3 = 20 · 크레딧 수량 3 · COGS (40 + 15 + 8 + 12) − (8 + 4) = 63 · 전부 원가 있음 → net_costed 172 · GP 109 · 63.4 %
--   (no brand): 판매 40(H2 · 원가 없음) · COGS 2(SO-79101 × MCP79003 못 맞춘 원가 → 오더의 손님 · 달 · 제품의 브랜드 없음) · net_costed 0 · uncosted 40 · GP −2 · % null
select pg_temp.chk('T1 brand: 행 2 · MCP Brand 79 = 203 31 172 20 3 63 109 63.4 172 0', (select jsonb_array_length(j->'rows')::text from t_out where k = 'brand') || ' | ' || pg_temp.cell(pg_temp.row_of('brand', 'MCP Brand 79')), '2 | 203.00 31.00 172.00 20 3 63.00 109.00 63.4 172.00 0.00');
select pg_temp.chk('T1b brand: (no brand) = 40 0 40 4 0 2 -2 null 0 40(927 · 못 맞춘 원가 · uncosted)', pg_temp.cell(pg_temp.row_of('brand', '(no brand)')), '40.00 0.00 40.00 4 0 2.00 -2.00 - 0.00 40.00');
select pg_temp.chk('T2 totals = 243 31 212 24 3 65 107 62.2 172 40 · cogs_unmatched 2 · gp_from 2026-11-01', (select pg_temp.cell(j->'totals') || ' ' || (j->'totals'->>'cogs_unmatched') || ' ' || (j->>'gp_from') from t_out where k = 'brand'), '243.00 31.00 212.00 24 3 65.00 107.00 62.2 172.00 40.00 2.00 2026-11-01');
select pg_temp.chk('T3 925 · 926 · 이견 7 ~ 9 · 11: other = freight 23 · services 9.5 · order_discount -12 · adjustments -5 · invoice_total_pretax 258.5 · other_credits 5 · excluded_non_cad {1, 99}',
  (select (j->'other'->>'freight') || ' ' || (j->'other'->>'services') || ' ' || (j->'other'->>'order_discount') || ' ' || (j->'other'->>'adjustments') || ' ' || (j->'other'->>'invoice_total_pretax') || ' ' || (j->'other'->>'other_credits') || ' ' || (j->'other'->'excluded_non_cad'->>'count') || ' ' || (j->'other'->'excluded_non_cad'->>'amount') from t_out where k = 'brand'),
  '23.00 9.50 -12.00 -5.00 258.50 5.00 1 99.00');
select pg_temp.chk('T3b 이견 9 항등식: sales + freight + services + order_discount + adjustments = invoice_total_pretax', (select (((j->'totals'->>'sales')::numeric + (j->'other'->>'freight')::numeric + (j->'other'->>'services')::numeric + (j->'other'->>'order_discount')::numeric + (j->'other'->>'adjustments')::numeric) = (j->'other'->>'invoice_total_pretax')::numeric)::text from t_out where k = 'brand'), 'true');
select pg_temp.chk('T4 926 month: 2026-09 = 190 판매 · 0 크레딧 / 2026-10 = 53 판매 · 31 크레딧(크레딧은 낸 달) · 날짜순', (select string_agg((x->>'key') || ':' || (x->>'sales') || '/' || (x->>'credits'), ' ' order by o) from t_out, jsonb_array_elements(j->'rows') with ordinality a(x, o) where k = 'month'), '2026-11:190.00/0.00 2026-12:53.00/31.00');
select pg_temp.chk('T5 929 customer: 본사 MCP HQ 79 = 190 / 20 / 170 + accounts [HQ 150/20, Branch 40/0] · MCP Solo 79 = 53 / 11 / 42 · accounts 없음 · 순매출 큰 순',
  (select string_agg((x->>'key') || ':' || (x->>'sales') || '/' || (x->>'credits') || '/' || (x->>'net') || coalesce(' [' || (select string_agg((a->>'name') || ' ' || (a->>'sales') || '/' || (a->>'credits'), ', ' order by (a->>'net')::numeric desc) from jsonb_array_elements(x->'accounts') a) || ']', ''), ' | ' order by o) from t_out, jsonb_array_elements(j->'rows') with ordinality q(x, o) where k = 'cust'),
  'MCP HQ 79:190.00/20.00/170.00 [MCP HQ 79 150.00/20.00, MCP Branch 79 40.00/0.00] | MCP Solo 79:53.00/11.00/42.00');
select pg_temp.chk('T5b 929: 본사 합 = 계정 합(sales · credits · cogs)', (select ((x->>'sales')::numeric = (select sum((a->>'sales')::numeric) from jsonb_array_elements(x->'accounts') a))::text || ' ' || ((x->>'credits')::numeric = (select sum((a->>'credits')::numeric) from jsonb_array_elements(x->'accounts') a))::text || ' ' || ((x->>'cogs')::numeric = (select sum((a->>'cogs')::numeric) from jsonb_array_elements(x->'accounts') a))::text from t_out, jsonb_array_elements(j->'rows') x where k = 'cust' and x->>'key' = 'MCP HQ 79'), 'true true true');
select pg_temp.chk('T6 929: 지점 이름 → 그 계정만(scope · 행 1 · 40 · accounts 없음)', (select (j->'filters'->>'customer') || ' / ' || (j->'filters'->>'customer_scope') || ' / ' || (j->'filters'->>'parent_name') || ' ' || jsonb_array_length(j->'rows') || ' ' || (j->'rows'->0->>'sales') || ' ' || (j->'rows'->0 ? 'accounts')::text from t_out where k = 'cust_br'), 'MCP Branch 79 / this account only / MCP HQ 79 1 40.00 false');
select pg_temp.chk('T6b 본사 이름(소문자) → 본사 + 지점 · 월 묶음 · other 는 손님 거르기(15 · 3 · -10 · -5 · 193 · 3)', (select (j->'filters'->>'customer') || ' / ' || (j->'filters'->>'customer_scope') || ' ' || (j->'totals'->>'sales') || ' ' || (j->'other'->>'freight') || ' ' || (j->'other'->>'services') || ' ' || (j->'other'->>'order_discount') || ' ' || (j->'other'->>'adjustments') || ' ' || (j->'other'->>'invoice_total_pretax') || ' ' || (j->'other'->>'other_credits') from t_out where k = 'cust_hq'), 'MCP HQ 79 / this customer and its accounts 190.00 15.00 3.00 -10.00 -5.00 193.00 3.00');
select pg_temp.chk('T7 930 supplier: MCP Supplier 79 = 153/31 · MCP Supplier 78 = 50(둘 다 기본 → 이름순 첫째) · (no supplier) = 40 · 순 큰 순', (select string_agg((x->>'key') || ':' || (x->>'sales') || '/' || (x->>'credits'), ' | ' order by o) from t_out, jsonb_array_elements(j->'rows') with ordinality q(x, o) where k = 'sup'), 'MCP Supplier 79:153.00/31.00 | MCP Supplier 78:50.00/0.00 | (no supplier):40.00/0.00');
select pg_temp.chk('T7b supplier 거르기(부분 · 유일) → sku 묶음 행 1 MCP79002 50 · other 없음 · other_note', (select (j->'filters'->>'supplier') || ' ' || jsonb_array_length(j->'rows') || ' ' || (j->'rows'->0->>'key') || ' ' || (j->'rows'->0->>'sales') || ' ' || (j ? 'other')::text || ' ' || (j ? 'other_note')::text from t_out where k = 'sup_78'), 'MCP Supplier 78 1 MCP79002 50.00 false true');
select pg_temp.chk('T7c supplier 못 풀면 {resolved:false, field supplier, matches 2, candidates 2}', (select (j->>'resolved') || ' ' || (j->>'field') || ' ' || (j->>'matches') || ' ' || jsonb_array_length(j->'candidates') from t_out where k = 'sup_amb'), 'false supplier 2 2');
select pg_temp.chk('T8 sku · limit 2: MCP79001 = 153 31 122 15 3 48 74 60.7 122 0 + name · MCP79002 = 50 … 15 35 70.0 · rows_truncated {1, 40}', (select pg_temp.cell(j->'rows'->0) || ' / ' || (j->'rows'->0->>'name') || ' | ' || pg_temp.cell(j->'rows'->1) || ' | ' || (j->'rows_truncated'->>'rows') || ' ' || (j->'rows_truncated'->>'net') from t_out where k = 'sku2'), '153.00 31.00 122.00 15 3 48.00 74.00 60.7 122.00 0.00 / MCP Product One | 50.00 0.00 50.00 5 0 15.00 35.00 70.0 50.00 0.00 | 1 40.00');
select pg_temp.chk('T9 sku 거르기(소문자 정확) + 경계 · opening 제외: MCP79001 월별 09 100 · 10 53(H4 10-31 + IMS 79901 33 · opening 79101 999 없음 · USD 99 없음) · 크레딧 10 월 31', (select (j->'filters'->>'sku') || ' ' || (select string_agg((x->>'key') || ':' || (x->>'sales') || '/' || (x->>'credits'), ' ' order by o) from jsonb_array_elements(j->'rows') with ordinality q(x, o)) from t_out where k = 'sku_p1'), 'MCP79001 2026-11:100.00/0.00 2026-12:53.00/31.00');
select pg_temp.chk('T10 brand 거르기(부분 · 유일) → sku 행 2(P1 · P2) · other 없음', (select (j->'filters'->>'brand') || ' ' || jsonb_array_length(j->'rows') || ' ' || (j ? 'other')::text from t_out where k = 'brand_f'), 'MCP Brand 79 2 false');
select pg_temp.chk('T10b brand 못 풀면 resolved false · field brand · matches 0', (select (j->>'resolved') || ' ' || (j->>'field') || ' ' || (j->>'matches') from t_out where k = 'brand_x'), 'false brand 0');
select pg_temp.chk('T11 928 경계(가짜 손님만): 8 월(08-01 ~ 08-31) → gp_from 2026-08-21 · H3 12 는 원가 구간 밖 → net_costed 0 · uncosted 0 · cogs 0 · gp 0 · % null', (select (j->>'gp_from') || ' ' || pg_temp.cell(j->'totals') from t_out where k = 'aug'), '2026-08-21 12.00 0.00 12.00 1 0 0.00 0.00 - 0.00 0.00');
select pg_temp.chk('T11b 928(가짜 손님만): 원가 전 기간(07-01 ~ 08-15) → gp_from null · cogs · gp · net_costed · uncosted 열쇠는 있되 null(비운다 · 지어내지 않음)', (select (j ? 'gp_from')::text || ' ' || coalesce(j->>'gp_from', 'null') || ' ' || jsonb_typeof(j->'totals'->'cogs') || ' ' || jsonb_typeof(j->'totals'->'gp') || ' ' || jsonb_typeof(j->'totals'->'net_costed') || ' ' || (j->'totals'->>'sales') from t_out where k = 'pre'), 'true null null null null 12.00');
select pg_temp.chk('T12 source_note · period · group', (select left(j->>'source_note', 33) || ' | ' || (j->'period'->>'from') || '~' || (j->'period'->>'to') || ' ' || (j->>'group') || ' ' || (position('totals are computed by IMS' in j->>'source_note') > 0)::text from t_out where k = 'brand'), 'Cin7 history: invoice dates 2025- | 2026-11-01~2026-12-31 brand true');
select pg_temp.chk('T13 923: 결과 글자에 메모 · 이메일 · 전화 0 · 열쇠에 note · email · phone · address 0', (select count(*) from t_out, unnest(array['MCP-MEMO', 'test.invalid', '416-555', 'MCP Contact']) s where j::text like '%' || s || '%')::text || ' ' || (select count(*) from t_out, lateral pg_temp.keys(j) ky where ky ~* '(note|comment|email|phone|line1|address|postal|contact)' and ky not in ('source_note', 'other_note'))::text, '0 0');
select pg_temp.chk('T14 시간: 가짜 호출 14 전부 8 초 안', (select (max(ms) < 8000)::text from t_out), 'true');

-- ── P) 919 — 원가 열쇠 ──
select pg_temp.chk('P1 919: ⓑ(claude · sales · 원가 없음) → cogs · gp · gp_pct · net_costed · uncosted_sales · cogs_unmatched · gp_from 열쇠 0 · sales 는 같다',
  (select (count(*) filter (where ky ~ '^(cogs|gp|gp_pct|net_costed|uncosted_sales|cogs_unmatched|gp_from)$'))::text || ' ' || (r->'totals'->>'sales') from (select pg_temp.as_conn('ims_connector', pg_temp.cl(:'b_uid', 'mcp-test-client-79b'), $q$select public.mcp_sales('2026-11-01', '2026-12-31', 'brand')::text$q$)::jsonb as r) z, lateral pg_temp.keys(r) ky group by r), '0 243.00');
select pg_temp.chk('P2 919: ⓐ(원가 있음) → 그 열쇠가 행 · accounts · totals 에 있다(≥ 7 · gp_from 1)', (select (count(*) filter (where ky ~ '^(cogs|gp|gp_pct|net_costed|uncosted_sales)$') >= 7)::text || ' ' || (count(*) filter (where ky = 'gp_from'))::text from t_out, lateral pg_temp.keys(j) ky where k = 'cust'), 'true 1');

-- ── V) 인자 검사(이견 13) · 권한 ──
select pg_temp.chk('V1 날짜 꼴 틀림 → 한 문장', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', :'cid'), $q$select public.mcp_sales('2026/01/01', '2026-01-31', 'brand')::text$q$), 'ERR P0001: Give from and to as dates in YYYY-MM-DD form'), 'ERR P0001: Give from and to as dates in YYYY-MM-DD form');
select pg_temp.chk('V2 없는 날(2026-13-01) → 한 문장', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', :'cid'), $q$select public.mcp_sales('2026-13-01', '2026-01-31', 'brand')::text$q$), 'ERR P0001: from or to is not a real calendar date'), 'ERR P0001: from or to is not a real calendar date');
select pg_temp.chk('V3 from > to', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', :'cid'), $q$select public.mcp_sales('2026-02-01', '2026-01-31', 'brand')::text$q$), 'ERR P0001: from (2026-02-01) is after to (2026-01-31)'), 'ERR P0001: from (2026-02-01) is after to (2026-01-31)');
select pg_temp.chk('V4 3 년 넘음', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', :'cid'), $q$select public.mcp_sales('2023-01-01', '2026-01-02', 'brand')::text$q$), 'ERR P0001: The period is longer than 3 years'), 'ERR P0001: The period is longer than 3 years');
select pg_temp.chk('V5 group 밖 · limit 밖', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', :'cid'), $q$select public.mcp_sales('2026-01-01', '2026-01-31', 'week')::text$q$), 'ERR P0001: group must be one of brand, customer, month, sku, supplier') || ' | ' || pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', :'cid'), $q$select public.mcp_sales('2026-01-01', '2026-01-31', 'sku', null, null, null, null, 0)::text$q$), 'ERR P0001: limit must be between 1 and 200'), 'ERR P0001: group must be one of brand, customer, month, sku, supplier | ERR P0001: limit must be between 1 and 200');
select pg_temp.chk('V6 3 년 딱 맞음은 된다(2021-11-01 ~ 2024-10-31 · 자료 없음 · group 대소문자 · 빈칸)', (select (pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', :'cid'), $q$select public.mcp_sales('2021-11-01', '2024-10-31', ' Brand ')::text$q$)::jsonb)->>'group'), 'brand');
select pg_temp.chk('K1 ⓒ sales 만(claude 없음) → 거부', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'c_uid', :'cid'), $q$select public.mcp_sales('2026-09-01', '2026-10-31', 'brand')::text$q$), 'ERR P0001: Your account does not have the ''claude'' permission'), 'ERR P0001: Your account does not have the ''claude'' permission');
select pg_temp.chk('K2 ⓓ claude 만(sales 없음) → sales 거부', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'d_uid', :'cid'), $q$select public.mcp_sales('2026-09-01', '2026-10-31', 'brand')::text$q$), 'ERR P0001: You need the ''sales'' permission to use this tool'), 'ERR P0001: You need the ''sales'' permission to use this tool');
select pg_temp.chk('K3 다른 client_id → 거부', pg_temp.st(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', 'someone-else'), $q$select public.mcp_sales('2026-09-01', '2026-10-31', 'brand')::text$q$), 'ERR P0001: This OAuth client is not the registered Claude connector'), 'ERR P0001: This OAuth client is not the registered Claude connector');
select pg_temp.chk('C1 authenticated(ⓐ) · anon · service_role → EXECUTE 없음 42501 ×3', left(pg_temp.as_conn('authenticated', jsonb_build_object('sub', :'a_uid', 'role', 'authenticated'), $q$select public.mcp_sales('2026-09-01', '2026-10-31', 'brand')::text$q$), 9) || ' ' || left(pg_temp.as_conn('anon', '{"role":"anon"}', $q$select public.mcp_sales('2026-09-01', '2026-10-31', 'brand')::text$q$), 9) || ' ' || left(pg_temp.as_conn('service_role', '{"role":"service_role"}', $q$select public.mcp_sales('2026-09-01', '2026-10-31', 'brand')::text$q$), 9), 'ERR 42501 ERR 42501 ERR 42501');
select pg_temp.chk('C2 ims_connector 로 도우미 · 표 → 42501(mcp_name_pick · mcp_sales_cell · hist_line_kind · hist_so_line · inv_layer_consume)', (select string_agg(left(pg_temp.as_conn('ims_connector', pg_temp.cl(:'a_uid', :'cid'), s), 9), ' ') from unnest(array[$q$select public.mcp_name_pick('brand', 'a')::text$q$, $q$select public.mcp_sales_cell(1, 0, 1, 0, 0, 0, 0, 0, true, true)::text$q$, $q$select public.hist_line_kind('x')$q$, 'select count(*)::text from public.hist_so_line', 'select count(*)::text from public.inv_layer_consume']) s), 'ERR 42501 ERR 42501 ERR 42501 ERR 42501 ERR 42501');
select pg_temp.chk('C3 hist_line_kind 의 acl 은 전과 같다(authenticated 도 없음 — 정의자 창구 hist_credit_lines 가 postgres 로 부른다)', (select coalesce(p.proacl::text, '(null)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'hist_line_kind'), :'hlk_pre_acl');

-- ── N) mcp_name_pick(postgres 로 직접) ──
select pg_temp.chk('N1 brand 정확(대소문자) → id · name', (select (p->>'name') || ' ' || (p->>'matches') || ' ' || (p->>'id' is not null)::text from public.mcp_name_pick('brand', ' mcp brand 79 ') p), 'MCP Brand 79 1 true');
select pg_temp.chk('N2 supplier 부분 둘 → id null · candidates 2(이름만)', (select (p->>'id' is null)::text || ' ' || (p->>'matches') || ' ' || (p->'candidates')::text from public.mcp_name_pick('supplier', 'MCP Supplier 7') p), 'true 2 ["MCP Supplier 78", "MCP Supplier 79"]');
select pg_temp.chk('N3 빈 글 → matches 0 · id null / 모르는 kind → 오류 한 문장', (select (p->>'matches') || ' ' || (p->>'id' is null)::text from public.mcp_name_pick('brand', '  ') p) || ' | ' || pg_temp.try($q$select public.mcp_name_pick('warehouse', 'x')::text$q$), '0 true | ERR P0001: mcp_name_pick: unknown kind warehouse');
select p.proname, md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_sales', 'mcp_name_pick', 'mcp_sales_cell', 'hist_line_kind') order by 1;

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.hist_so) = :n_hist as hist_same, (select count(*) from public.hist_so_line) = :n_hist_line as hist_line_same, (select count(*) from public.inv_layer) = :n_layer as layer_same,
       (select count(*) from public.inv_layer_consume) = :n_consume as consume_same, (select count(*) from public.so_invoice) = :n_inv as inv_same, (select count(*) from public.so_credit) = :n_credit as credit_same,
       (select count(*) from public.product) = :n_product as product_same, (select count(*) from public.customer) = :n_cust as cust_same, (select count(*) from public.ims_staff) = :n_staff as staff_same,
       (select count(*) from public.ref_brand) = :n_brand as brand_same, (select count(*) from public.supplier) = :n_sup as sup_same, (select count(*) from public.so) = :n_so as so_same,
       (select claude_client_id is not distinct from nullif(:'cid0', '') from public.mcp_config where singleton) as cid_same,
       (select coalesce(p.proconfig::text, '(none)') = :'hlk_pre_cfg' and md5(p.prosrc) = :'hlk_pre_md5' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'hist_line_kind') as hlk_same;
