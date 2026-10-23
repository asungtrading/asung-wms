-- bgr-1a-verify.sql — B급 칸 ① 칸 표시 · 「팔 수 있는 잔고」 한 곳 · 가용 · 자동 칸(판정 629 · 635 · 636 · 637 · 641):
--   S0 결함 판(칸 · 창구 없음) · G0 손대지 않은 함수 md5 무변 · T 옛 = 새(B급 칸이 없을 때 · 실물 · 아홉 갈래) ·
--   S4 창구 · 트리거(문 · 켜기 · 끄기 · 무해 · 직접 update 거부) · S1 가용(18 · bgrade 2 · B급만 있는 줄) · S2 정상 줄(픽 계획 · 칸 기본 · 피커 칸 저장 · 선반) ·
--   S3 B급 줄(그 칸 하나 · 할당이 정상 가용을 깎지 않음 · stk_reserved 같은 조건) · S4g 열린 B급 줄 끄기 거부 · S5 착지(ims_inv_balance · inv_balance 를 읽고 bgrade 를 안 보는 함수 = 허락 목록) · Z1 실제 행 무접촉
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261023131028_bgr_1a_bgrade_bins.sql -f supabase/tests/bgr-1a-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · T 셋은 없고 P0c 한 줄이 찍힌다(확인 갈래 OK 수는 아래 「기대」)
--   기대(2026-10-23 시험 통과 실행 · 찍힌 OK 줄을 셈): 시험 갈래 OK 15(M0 S0 G0 T G1 S4 S4b S1 S2·S3 S2b S2c S3b S4g S5 Z1) · MISMATCH 0 / 확인 갈래 OK 13(M0 P0c G1 S4 S4b S1 S2·S3 S2b S2c S3b S4g S5 Z1 — S0 · G0 · T 빠지고 P0c 하나) · MISMATCH 0 · 실행 약 5 분(옛 = 새 두 번 · 각 140 s)
--   가짜 재료 = 직원 셋 · 토론토 칸 넷(BGR1-N · BGR1-B · BGR1-E · BGR1-X 비활성) · 제품 둘(BGR1-P · BGR1-Q) · 손님 하나 · 원장 가짜 사건 · 오더 하나 — 모두 되감긴다 · so_number_seq 는 끝에서 되돌린다
--   ⚠️ 트랜잭션은 repeatable read — 옛 = 새 비교 사이에 Shopify cron 이 실제 오더를 넣어도 같은 스냅샷을 본다

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261023131028' \gset
select :n_applied as schema_migrations_rows_for_20261023131028;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset

begin isolation level repeatable read;
set local statement_timeout = '900s';
select now() as t0 \gset

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_role(p_role text, p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  if p_claims is not null then perform set_config('request.jwt.claims', p_claims, true); end if;
  execute p_sql into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then
  reset role;
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.alen(p jsonb) returns int language sql immutable as $$ select case when jsonb_typeof(p) = 'array' then jsonb_array_length(p) else 0 end $$;
-- 손대지 않는 함수(서명이 바뀌면 안 되는 것 · inv_available_base 를 부르는 것 · 칸 표시를 안 보는 쪽)
create function pg_temp.fns() returns text language sql security definer as $$
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('stk_bins', 'stk_bins_many', 'stk_availability_export', 'ims_ref_name_lock', 'pur_stock', 'shop_stock_payload', 'so_available_many', 'so_backorder_arrivals',
                     'so_backorder_fill', 'so_backorder_waiting', 'po_receipt_post_now_by', 'so_lines_available', 'inv_move_bin_contents', 'inv_stock_master', 'stk_movements', 'stk_value_many') $$;
-- stk_availability_export 의 by_warehouse 에서 새 열쇠 bgrade 를 걷는다(옛 = 새 비교용 · 나머지 바이트 그대로)
create function pg_temp.strip_bg(p jsonb) returns jsonb language sql immutable as $$
  select case when p is null or jsonb_typeof(p->'rows') <> 'array' then p else jsonb_set(p, '{rows}', coalesce((
    select jsonb_agg(case when jsonb_typeof(r->'by_warehouse') = 'array'
                          then jsonb_set(r, '{by_warehouse}', coalesce((select jsonb_agg(b - 'bgrade' order by o) from jsonb_array_elements(r->'by_warehouse') with ordinality t(b, o)), '[]'::jsonb))
                          else r end order by o2)
      from jsonb_array_elements(p->'rows') with ordinality t2(r, o2)), '[]'::jsonb)) end $$;
-- 옛 = 새 — 재발행 · 따라가는 함수의 출력(실물 · 전 창고)을 갈래마다 md5 로(표본은 아래 주석 · 같은 스냅샷)
--   iab_*: inv_available_base(창고 · null 키) 첫 넷 칸 · export: stk_availability_export(Both · include_zero false / true · 한 창고) bgrade 걷고 · plan: 열린 SO 최근 30 + 열린 트랜스퍼 최근 5 의 so_pick_plan ·
--   last_bin: 창고마다 잔고 있는 모든 product_id 한 번 · pick_lines: 최근 픽 과제 50 · shelf: 창고마다 칸 있는 SKU 200 · reserved: 열린 할당이 있는 (제품, 창고) 40 · pur_stock 전체
create function pg_temp.ident(p_tor uuid, p_edm uuid) returns jsonb language plpgsql as $$
declare v jsonb := '{}'::jsonb;  v_t text;
begin
  for v_t in select unnest(array['iab_tor', 'iab_edm', 'export_both', 'export_zero', 'export_tor', 'plan', 'last_bin', 'pick_lines', 'shelf', 'reserved', 'pur_stock']) loop
    begin
      v := v || jsonb_build_object(v_t, case v_t
        when 'iab_tor' then (select count(*) || '/' || md5(coalesce(string_agg(b.stock_pid || ':' || b.qty_ea || ':' || b.sales_alloc_ea || ':' || b.transfer_alloc_ea, ',' order by b.stock_pid), '')) from public.inv_available_base(p_tor, null) b)
        when 'iab_edm' then (select count(*) || '/' || md5(coalesce(string_agg(b.stock_pid || ':' || b.qty_ea || ':' || b.sales_alloc_ea || ':' || b.transfer_alloc_ea, ',' order by b.stock_pid), '')) from public.inv_available_base(p_edm, null) b)
        when 'export_both' then (select (x->>'row_count') || '/' || md5(pg_temp.strip_bg(x)::text) from public.stk_availability_export(null, null, null, null, false, false, null) x)
        when 'export_zero' then (select (x->>'row_count') || '/' || md5(pg_temp.strip_bg(x)::text) from public.stk_availability_export(null, null, null, null, true, false, null) x)
        when 'export_tor' then (select (x->>'row_count') || '/' || md5(pg_temp.strip_bg(x)::text) from public.stk_availability_export(p_tor, null, null, null, false, false, null) x)
        when 'plan' then (select count(*) || '/' || md5(coalesce(string_agg(public.so_pick_plan(d.doc_id)::text, ',' order by d.doc_id), '')) from (
                            (select d1.doc_id from public.wms_order_doc d1 where d1.doc_kind = 'so' and d1.status in ('draft', 'confirmed', 'at_wms', 'picking') and d1.warehouse_id is not null and d1.created_at < now() order by d1.created_at desc limit 30)
                            union all
                            (select d2.doc_id from public.wms_order_doc d2 where d2.doc_kind = 'transfer' and d2.status in ('confirmed', 'at_wms', 'picking') and d2.warehouse_id is not null order by d2.created_at desc limit 5)) d)
        when 'last_bin' then (select md5(public.ims_last_bin(array(select distinct v1.product_id from public.ims_inv_balance v1 where v1.warehouse_id = p_tor and v1.product_id is not null), p_tor)::text)
                                || '/' || md5(public.ims_last_bin(array(select distinct v2.product_id from public.ims_inv_balance v2 where v2.warehouse_id = p_edm and v2.product_id is not null), p_edm)::text))
        when 'pick_lines' then (select jsonb_array_length(x) || '/' || md5(x::text) from (select public.wms_pick_lines(array(select t.id from public.wms_pick_tasks t order by t.id desc limit 50)) as x) y)
        when 'shelf' then (select md5(public.wms_pick_shelf(p_tor, array(select distinct b.sku from public.inv_balance b where b.warehouse = (select name from public.ref_warehouse where id = p_tor) and b.bin <> '' and b.qty <> 0 order by b.sku limit 200))::text)
                             || '/' || md5(public.wms_pick_shelf(p_edm, array(select distinct b.sku from public.inv_balance b where b.warehouse = (select name from public.ref_warehouse where id = p_edm) and b.bin <> '' and b.qty <> 0 order by b.sku limit 200))::text))
        when 'reserved' then (select count(*) || '/' || md5(coalesce(string_agg(public.stk_reserved(k.pid, k.wh)::text, ',' order by k.pid, k.wh), '')) from (
                                select distinct coalesce(p.parent_product_id, p.id) as pid, s.location_id as wh from public.so_reserve r join public.so_line l on l.id = r.so_line_id join public.so s on s.id = l.so_id join public.product p on p.id = l.product_id
                                 where r.released_at is null and r.kind = 'allocated' and s.location_id in (p_tor, p_edm) order by 1, 2 limit 40) k)
        when 'pur_stock' then (select (x->>'row_count') || '/' || md5(x::text) from public.pur_stock() x)
      end);
    exception when others then
      v := v || jsonb_build_object(v_t, 'ERR ' || sqlstate || ': ' || sqlerrm);
    end;
  end loop;
  return v;
end $$;
-- 실제 행(스냅샷 때 있던 것만) — so · 원장 · 실제 칸 · 실제 줄
create function pg_temp.real_rows(p_t0 timestamptz) returns text language plpgsql security definer as $$
declare v text;  v_bg text;
begin
  v := 'so=' || (select count(*) || '/' || md5(coalesce(string_agg(s.id::text || s.status || coalesce(s.updated_at::text, ''), ',' order by s.id), '')) from public.so s where s.created_at < p_t0)
    || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where created_at < p_t0)
    || ' reserve=' || (select count(*) || '/' || md5(coalesce(string_agg(r.id::text || coalesce(r.released_at::text, ''), ',' order by r.id), '')) from public.so_reserve r where r.created_at < p_t0)
    || ' bins=' || (select count(*) || '/' || md5(coalesce(string_agg(b.id::text || b.name || b.is_active || coalesce(b.updated_at::text, ''), ',' order by b.id), '')) from public.ref_bin b where b.created_at < p_t0);
  begin
    execute 'select ''/bg='' || count(*) filter (where is_bgrade) from public.ref_bin where created_at < $1' into v_bg using p_t0;  v := v || coalesce(v_bg, '');
  exception when undefined_column then null;
  end;
  return v;
end $$;

\echo '── M0) 가짜 직원 셋 · 토론토 칸 넷 · 제품 둘 · 손님 · 원장(N 에 18) · 스냅샷'
select id::text as tor, name as torname from public.ref_warehouse where id = '045e4ca6-b7a9-446e-9e6a-a5a0db56d456' and is_active \gset
select id::text as edm from public.ref_warehouse where is_active and name ilike '%edmonton%' \gset
select pg_temp.real_rows(:'t0'::timestamptz) as real_before, pg_temp.fns() as fns_before \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'bgr1-w@test.invalid', 'BGR1 W', 'manager', '["ims","sales","purchasing","picking"]', '{}') returning auth_user_id::text as w_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'bgr1-m@test.invalid', 'BGR1 M', 'manager', '["ims","master"]', '{}') returning auth_user_id::text as m_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'bgr1-n@test.invalid', 'BGR1 N', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as n_uid \gset
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
\set m '{"sub":"' :m_uid '","role":"authenticated"}'
\set n '{"sub":"' :n_uid '","role":"authenticated"}'
select set_config('request.jwt.claims', :'w', true) as claims_w;
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select rt.id::text as tier_id, rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGR1-N', :'tor'::uuid, 'manual', true) returning id::text as bin_n \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGR1-B', :'tor'::uuid, 'manual', true) returning id::text as bin_b \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGR1-E', :'tor'::uuid, 'manual', true) returning id::text as bin_e \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGR1-X', :'tor'::uuid, 'manual', false) returning id::text as bin_x \gset
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name)
  values ('BGR1 C1', 'manual', :'tier_name', :'tor'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as c1 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('BGR1-P', 'BGR1 Product', 'manual', true, true) returning id::text as pid_p \gset
insert into public.product (sku, name, source, is_active, sellable) values ('BGR1-Q', 'BGR1 B-grade only', 'manual', true, true) returning id::text as pid_q \gset
insert into public.product_price (product_id, tier_id, price, source) values (:'pid_p'::uuid, :'tier_id'::uuid, 9.99, 'manual'), (:'pid_q'::uuid, :'tier_id'::uuid, 4.99, 'manual');
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values
  (public.ims_today() - 30, 1, 'BGR1-P', :'torname', 'BGR1-N', 18, 'po_in', 'purchase', 'PO-BGR1', 'bgr1-p-n', 'manual');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values
  ('BGR1-P', :'torname', 'purchase', 'PO-BGR1', 'bgr1-p-n', public.ims_today() - 30, true, 18, 2.5, 'po_line');
set local session_replication_role = origin;
select pg_temp.chk(format('M0 staff W · M(master) · N(no master) · bins BGR1-N/B/E/X in %s · products BGR1-P · BGR1-Q · customer · ledger BGR1-P 18 in BGR1-N · snapshots', :'torname'),
  :'w_uid' <> '' and :'m_uid' <> '' and :'n_uid' <> '' and :'bin_x' <> '' and :'pid_q' <> '' and :'c1' <> '' and :'edm' <> '' and :'real_before' <> '' and :'fns_before' <> '', 'see M0');

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — 칸 · 창구 · 반환 칸 없음 · 옛 출력 담기'
select (select count(*) from information_schema.columns where table_schema = 'public' and ((table_name = 'ref_bin' and column_name = 'is_bgrade') or (table_name = 'so_line' and column_name = 'bgrade_bin_id'))) as s0_cols,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ref_bin_bgrade_set') as s0_win,
       (select pg_get_function_result(oid) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_available_base') as s0_iab \gset
select clock_timestamp() as tp0 \gset
select pg_temp.ident(:'tor'::uuid, :'edm'::uuid)::text as pre \gset
select round(extract(epoch from clock_timestamp() - :'tp0'::timestamptz)::numeric, 1) as pre_s \gset
select pg_temp.chk(format('S0 before the trial: no is_bgrade · bgrade_bin_id · window · inv_available_base has 4 columns · old outputs captured (%s s · %s)', :pre_s, :'pre'),
  :s0_cols = 0 and :s0_win = 0 and :'s0_iab' = 'TABLE(stock_pid uuid, qty_ea numeric, sales_alloc_ea numeric, transfer_alloc_ea numeric)' and :n_applied = 0 and :'pre' not like '%ERR%',
  format('cols %s win %s iab %s | %s', :s0_cols, :s0_win, :'s0_iab', :'pre'));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: functions not re-issued (stk_bins · stk_bins_many · export · callers of inv_available_base · inv_balance readers kept as they are) md5 unchanged', pg_temp.fns() = :'fns_before', format('before %s | after %s', :'fns_before', pg_temp.fns()));
\echo '── T) 옛 = 새 — B급 칸이 하나도 없을 때 · 실물'
select clock_timestamp() as tp1 \gset
select pg_temp.ident(:'tor'::uuid, :'edm'::uuid)::text as post \gset
select round(extract(epoch from clock_timestamp() - :'tp1'::timestamptz)::numeric, 1) as post_s \gset
select pg_temp.chk(format('T old = new with no B-grade bin: %s (%s s)', (select string_agg(k || '=' || split_part(pg_temp.j(:'post')->>k, '/', 1), ' ' order by k) from jsonb_object_keys(pg_temp.j(:'post')) k), :post_s),
  pg_temp.j(:'pre') = pg_temp.j(:'post') and (select count(*) from jsonb_object_keys(pg_temp.j(:'post'))) = 11,
  (select string_agg(k || ': ' || (pg_temp.j(:'pre')->>k) || ' vs ' || (pg_temp.j(:'post')->>k), ' | ') from jsonb_object_keys(pg_temp.j(:'post')) k where pg_temp.j(:'pre')->k is distinct from pg_temp.j(:'post')->k));
\else
select pg_temp.chk('P0c confirm run: migration 20261023131028 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'ref_bin' and column_name = 'is_bgrade') as landed \gset
\if :landed
\echo '── G1) 모양 — 칸 둘 · 뷰 끝 칸 · inv_available_base 다섯 칸 · 창구 · 트리거 · 주인 postgres · 권한'
select pg_temp.chk('G1 ref_bin.is_bgrade default false · so_line.bgrade_bin_id → ref_bin · view last column bin_is_bgrade (security_invoker) · inv_available_base 5 columns (anon no) · window authenticated only · guard trigger · both owned by postgres',
  (select column_default from information_schema.columns where table_schema = 'public' and table_name = 'ref_bin' and column_name = 'is_bgrade') = 'false'
  and exists (select 1 from pg_constraint c where c.conrelid = 'public.so_line'::regclass and c.contype = 'f' and c.confrelid = 'public.ref_bin'::regclass and c.conkey = array[(select attnum from pg_attribute where attrelid = 'public.so_line'::regclass and attname = 'bgrade_bin_id')])
  and (select attname from pg_attribute where attrelid = 'public.ims_inv_balance'::regclass and attnum > 0 and not attisdropped order by attnum desc limit 1) = 'bin_is_bgrade'
  and (select array_to_string(reloptions, ',') from pg_class where oid = 'public.ims_inv_balance'::regclass) = 'security_invoker=true'
  and (select pg_get_function_result(oid) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_available_base') like '%bgrade_ea numeric)'
  and not has_function_privilege('anon', 'public.inv_available_base(uuid, uuid[])', 'execute') and has_function_privilege('authenticated', 'public.inv_available_base(uuid, uuid[])', 'execute')
  and has_function_privilege('authenticated', 'public.ref_bin_bgrade_set(uuid, boolean)', 'execute') and not has_function_privilege('anon', 'public.ref_bin_bgrade_set(uuid, boolean)', 'execute') and not has_function_privilege('service_role', 'public.ref_bin_bgrade_set(uuid, boolean)', 'execute')
  and exists (select 1 from pg_trigger where tgrelid = 'public.ref_bin'::regclass and tgname = 'ref_bin_bgrade_guard' and not tgisinternal and tgenabled = 'O')
  and (select string_agg(proowner::regrole::text, ',' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('ref_bin_bgrade_set', 'ref_bin_bgrade_guard')) = 'postgres,postgres',
  'see G1');

\echo '── S4) 창구 · 트리거'
select pg_temp.as_user(:'n', format('select public.ref_bin_bgrade_set(%L::uuid, true)::text', :'bin_e')) as s4a \gset
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, true)::text', :'bin_n')) as s4b \gset
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, true)::text', :'bin_b')) as s4c1 \gset
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, true)::text', :'bin_b')) as s4c2 \gset
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, true)::text', :'bin_x')) as s4d1 \gset
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, true)::text', gen_random_uuid())) as s4d2 \gset
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, null)::text', :'bin_e')) as s4d3 \gset
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, true)::text', :'bin_e')) as s4e1 \gset
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, false)::text', :'bin_e')) as s4e2 \gset
select pg_temp.as_role('authenticated', :'m', format('with u as (update public.ref_bin set is_bgrade = true where id = %L::uuid returning 1) select count(*)::text from u', :'bin_e')) as s4f1 \gset
select pg_temp.as_role('authenticated', :'m', format('with u as (update public.ref_bin set note = ''bgr-1a note'' where id = %L::uuid returning 1) select count(*)::text from u', :'bin_e')) as s4f2 \gset
select pg_temp.as_role('service_role', null, format('with u as (update public.ref_bin set is_bgrade = true where id = %L::uuid returning 1) select count(*)::text from u', :'bin_e')) as s4f3 \gset
select pg_temp.as_role('service_role', null, format('with u as (insert into public.ref_bin (name, warehouse_id, source) values (''BGR1-S1'', %L::uuid, ''cin7'') returning is_bgrade) select string_agg(is_bgrade::text, '','') from u', :'tor')) as s4f4 \gset
select pg_temp.as_role('service_role', null, format('with u as (insert into public.ref_bin (name, warehouse_id, source, is_bgrade) values (''BGR1-S2'', %L::uuid, ''cin7'', true) returning 1) select count(*)::text from u', :'tor')) as s4f5 \gset
select (select string_agg(name || '=' || is_bgrade, ',' order by name) from public.ref_bin where name like 'BGR1-%') as s4_state \gset
select pg_temp.chk(format('S4 window: non-master refused · stocked bin refused · empty bin on (changed) · again no-op (changed false) · inactive · unknown · null refused · on/off · direct update by authenticated (master) and service_role refused IM636 · other columns still editable · loader-style insert default false · insert true refused (%s)', :'s4_state'),
  :'s4a' like 'ERR P0001: You cannot change master data%'
  and :'s4b' like 'ERR P0001: Bin BGR1-N in % holds stock (18 EA in 1 SKU line(s)) — move the stock out first%'
  and (pg_temp.j(:'s4c1')->>'changed')::boolean and (pg_temp.j(:'s4c1')->>'is_bgrade')::boolean and not (pg_temp.j(:'s4c2')->>'changed')::boolean and (pg_temp.j(:'s4c2')->>'is_bgrade')::boolean
  and :'s4d1' like 'ERR P0001: Bin BGR1-X is switched off%' and :'s4d2' like 'ERR P0001: Bin % not found%' and :'s4d3' like 'ERR P0001: p_on must be true or false%'
  and (pg_temp.j(:'s4e1')->>'changed')::boolean and (pg_temp.j(:'s4e2')->>'changed')::boolean and not (pg_temp.j(:'s4e2')->>'is_bgrade')::boolean
  and :'s4f1' like 'ERR IM636: B-grade is set with Mark as B-grade%' and :'s4f2' = '1' and :'s4f3' like 'ERR IM636:%' and :'s4f4' = 'false' and :'s4f5' like 'ERR IM636:%'
  and :'s4_state' = 'BGR1-B=true,BGR1-E=false,BGR1-N=false,BGR1-S1=false,BGR1-X=false',
  format('a %s | b %s | c %s / %s | d %s / %s / %s | e %s / %s | f %s / %s / %s / %s / %s | %s', :'s4a', :'s4b', :'s4c1', :'s4c2', :'s4d1', :'s4d2', :'s4d3', :'s4e1', :'s4e2', :'s4f1', :'s4f2', :'s4f3', :'s4f4', :'s4f5', :'s4_state'));

\echo '── 재료 — B 에 BGR1-P 2(N 보다 최근) · BGR1-Q 3(B급만)'
set local session_replication_role = replica;
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values
  (public.ims_today() - 1, 1, 'BGR1-P', :'torname', 'BGR1-B', 2, 'po_in', 'purchase', 'PO-BGR1B', 'bgr1-p-b', 'manual'),
  (public.ims_today() - 1, 1, 'BGR1-Q', :'torname', 'BGR1-B', 3, 'po_in', 'purchase', 'PO-BGR1B', 'bgr1-q-b', 'manual');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values
  ('BGR1-P', :'torname', 'purchase', 'PO-BGR1B', 'bgr1-p-b', public.ims_today() - 1, true, 2, 2.5, 'po_line'),
  ('BGR1-Q', :'torname', 'purchase', 'PO-BGR1B', 'bgr1-q-b', public.ims_today() - 1, true, 3, 1.5, 'po_line');
set local session_replication_role = origin;
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, false)::text', :'bin_b')) as s4g0 \gset
select pg_temp.chk('S4b turning off a B-grade bin that holds stock is refused (move it back first)',
  :'s4g0' like 'ERR P0001: Bin BGR1-B in % still holds B-grade stock (5 EA in 2 SKU line(s)) — move it back to a regular bin first%', :'s4g0');

\echo '── S1) 가용 — 팔 수 있는 장부 18 · bgrade 2 · B급만 있는 줄(Q) · Stock 화면 · Reorder Planner'
select string_agg(format('%s:%s/%s/%s/%s', p.sku, trim_scale(b.qty_ea), trim_scale(b.sales_alloc_ea), trim_scale(b.transfer_alloc_ea), trim_scale(b.bgrade_ea)), ' ' order by p.sku) as s1a
  from public.inv_available_base(:'tor'::uuid, array[:'pid_p'::uuid, :'pid_q'::uuid]) b join public.product p on p.id = b.stock_pid \gset
select pg_temp.as_user(:'w', 'select public.stk_availability_export(null, ''BGR1-'', null, null, false, false, null)::text') as s1b \gset
select pg_temp.as_user(:'w', 'select public.pur_stock()::text') as s1c_all \gset
select (select r::text from jsonb_array_elements(pg_temp.j(:'s1c_all')->'rows') r where r->>'sku' = 'BGR1-P') as s1c,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'s1c_all')->'rows') r where r->>'sku' = 'BGR1-Q') as s1c_q \gset
select (select string_agg(format('%s on_hand %s avail %s | %s', r->>'sku', r->>'on_hand', r->>'available',
          (select string_agg(format('%s:%s/%s', b->>'warehouse', b->>'on_hand', b->>'bgrade'), ',' order by b->>'warehouse') from jsonb_array_elements(r->'by_warehouse') b)), ' ; ' order by r->>'sku')
          from jsonb_array_elements(pg_temp.j(:'s1b')->'rows') r) as s1b_t \gset
select pg_temp.chk(format('S1 inv_available_base %s · Stock export %s · pur_stock BGR1-P tor %s (BGR1-Q rows %s)', :'s1a', :'s1b_t', pg_temp.j(:'s1c')->'tor', :s1c_q),
  :'s1a' = 'BGR1-P:18/0/0/2 BGR1-Q:0/0/0/3'
  and (select count(*) from jsonb_array_elements(pg_temp.j(:'s1b')->'rows')) = 2
  and exists (select 1 from jsonb_array_elements(pg_temp.j(:'s1b')->'rows') r where r->>'sku' = 'BGR1-P' and (r->>'on_hand')::numeric = 18
                and exists (select 1 from jsonb_array_elements(r->'by_warehouse') b where b->>'warehouse' = :'torname' and (b->>'on_hand')::numeric = 18 and (b->>'bgrade')::numeric = 2))
  and exists (select 1 from jsonb_array_elements(pg_temp.j(:'s1b')->'rows') r where r->>'sku' = 'BGR1-Q' and (r->>'on_hand')::numeric = 0
                and exists (select 1 from jsonb_array_elements(r->'by_warehouse') b where b->>'warehouse' = :'torname' and (b->>'bgrade')::numeric = 3))
  and (pg_temp.j(:'s1c')->'tor'->>'qoh')::numeric = 18 and (pg_temp.j(:'s1c')->'tor'->>'avail')::numeric = 18 and :s1c_q = 0,
  format('%s | %s | %s', :'s1a', left(:'s1b', 1500), :'s1c'));

\echo '── S2 · S3) 오더 — 정상 줄 20(N 18 뿐 · 모자람) · B급 줄 3(B 에 2 뿐 · bgrade_bin_id 직접)'
select pg_temp.as_user(:'w', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''bgr-1a S2'')->>''id''', :'c1', :'tor')) as so1 \gset
select pg_temp.as_user(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 20, null, null, null, null, true)->''line''->>''id''', :'so1', :'pid_p')) as l1 \gset
select pg_temp.as_user(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 3, null, null, null, null, true)->''line''->>''id''', :'so1', :'pid_p')) as l2 \gset
set local session_replication_role = replica;
update public.so_line set bgrade_bin_id = :'bin_b'::uuid where id = :'l2'::uuid;
set local session_replication_role = origin;
select pg_temp.as_user(:'w', format('select public.so_pick_plan(%L::uuid)::text', :'so1')) as s2a \gset
select (select string_agg(format('L%s %s:%s:%s', x->>'line_no', p->>'bin', p->>'qty', p->>'from'), ' ' order by (x->>'line_no')::int, o)
          from jsonb_array_elements(pg_temp.j(:'s2a')->'lines') x, jsonb_array_elements(x->'picks') with ordinality t(p, o)) as s2a_t,
       (select string_agg(format('L%s wh %s short %s', x->>'line_no', x->>'warehouse_qty_ea', x->>'short_ea'), ' ' order by (x->>'line_no')::int) from jsonb_array_elements(pg_temp.j(:'s2a')->'lines') x) as s2a_s \gset
select pg_temp.chk(format('S2 · S3 so_pick_plan: %s · %s · short total %s — the normal line never takes BGR1-B (falls back to BGR1-N) · the B-grade line takes BGR1-B only (falls back to BGR1-B)', :'s2a_t', :'s2a_s', pg_temp.j(:'s2a')->>'short_ea_total'),
  :'s2a_t' = 'L1 BGR1-N:18:usual L1 BGR1-N:2:fallback L2 BGR1-B:2:usual L2 BGR1-B:1:fallback'
  and :'s2a_s' = 'L1 wh 18 short 2 L2 wh 2 short 1' and (pg_temp.j(:'s2a')->>'short_ea_total')::numeric = 3,
  :'s2a');
select pg_temp.as_user(:'w', format('select public.ims_last_bin(array[%L::uuid], %L::uuid)::text', :'pid_p', :'tor')) as s2b \gset
select (select string_agg(v.bin || '@' || v.last_seen_on, ',' order by v.bin) from public.ims_inv_balance v where v.product_id = :'pid_p'::uuid and v.warehouse_id = :'tor'::uuid) as s2b_bal \gset
select pg_temp.chk(format('S2b ims_last_bin = %s although BGR1-B is the most recent (%s)', pg_temp.j(:'s2b')->:'pid_p'->>'bin', :'s2b_bal'),
  pg_temp.j(:'s2b')->:'pid_p'->>'bin' = 'BGR1-N' and :'s2b_bal' = format('BGR1-B@%s,BGR1-N@%s', public.ims_today() - 1, public.ims_today() - 30), :'s2b');
select pg_temp.as_user(:'w', format('select public.wms_pick_line_bins_write(-1::bigint, 1, %L::jsonb, %L::uuid, null, now())::text', jsonb_build_array(jsonb_build_object('bin_id', :'bin_b', 'qty_base', 1)), :'tor')) as s2c1 \gset
select pg_temp.as_user(:'w', format('select public.wms_pick_line_bins_write(-1::bigint, 1, %L::jsonb, %L::uuid, null, now())::text', jsonb_build_array(jsonb_build_object('bin', 'BGR1-B', 'qty_base', 1)), :'tor')) as s2c2 \gset
select pg_temp.as_user(:'w', format('select public.wms_pick_line_bins_write(-1::bigint, 1, %L::jsonb, %L::uuid, null, now())::text', jsonb_build_array(jsonb_build_object('bin_id', :'bin_n', 'qty_base', 1)), :'tor')) as s2c3 \gset
select pg_temp.as_user(:'w', format('select public.wms_pick_shelf(%L::uuid, array[''BGR1-P'', ''BGR1-Q''])::text', :'tor')) as s2d \gset
select (select string_agg((i->>'sku') || '[' || coalesce((select string_agg(b->>'bin', ',' order by b->>'bin') from jsonb_array_elements(i->'bins') b), '') || ']', ' ' order by i->>'sku') from jsonb_array_elements(pg_temp.j(:'s2d')->'items') i) as s2d_t \gset
select pg_temp.chk(format('S2c picker bin save with BGR1-B refused (by id and by name) · BGR1-N passes the B-grade check (%s) · shelf view %s', left(:'s2c3', 90), :'s2d_t'),
  :'s2c1' like 'ERR P0001: Line -1: bin BGR1-B is a B-grade bin — B-grade stock is sold at POS only%' and :'s2c2' like 'ERR P0001: Line -1: bin BGR1-B is a B-grade bin%'
  and :'s2c3' not like '%B-grade%' and :'s2d_t' = 'BGR1-P[BGR1-N] BGR1-Q[]',
  format('%s | %s | %s | %s', :'s2c1', :'s2c2', :'s2c3', :'s2d'));

\echo '── S3b) 할당 — 정상 줄 5 · B급 줄 3(직접 · 확정 오더) → 정상 가용은 정상 줄 할당만 깎는다'
set local session_replication_role = replica;
update public.so set status = 'confirmed' where id = :'so1'::uuid;
insert into public.so_reserve (so_line_id, qty_allocated, kind) values (:'l1'::uuid, 5, 'allocated'), (:'l2'::uuid, 3, 'allocated');
set local session_replication_role = origin;
select string_agg(format('%s/%s/%s/%s', trim_scale(b.qty_ea), trim_scale(b.sales_alloc_ea), trim_scale(b.transfer_alloc_ea), trim_scale(b.bgrade_ea)), ' ') as s3a from public.inv_available_base(:'tor'::uuid, array[:'pid_p'::uuid]) b \gset
select pg_temp.as_user(:'w', format('select public.stk_reserved(%L::uuid, %L::uuid)::text', :'pid_p', :'tor')) as s3b \gset
select pg_temp.as_user(:'w', 'select public.stk_availability_export(null, ''BGR1-P'', null, null, false, false, null)::text') as s3c \gset
select (select string_agg(format('on_hand %s alloc %s avail %s', r->>'on_hand', r->>'sales_allocated', r->>'available'), ',') from jsonb_array_elements(pg_temp.j(:'s3c')->'rows') r) as s3c_t \gset
select pg_temp.chk(format('S3b inv_available_base %s (qty/sales/transfer/bgrade) · stk_reserved so_total %s (%s lines) · Stock %s — the B-grade line''s allocation does not cut normal availability', :'s3a', pg_temp.j(:'s3b')->>'so_total', pg_temp.alen(pg_temp.j(:'s3b')->'so'), :'s3c_t'),
  :'s3a' = '18/5/0/2' and (pg_temp.j(:'s3b')->>'so_total')::numeric = 5 and pg_temp.alen(pg_temp.j(:'s3b')->'so') = 1 and :'s3c_t' = 'on_hand 18 alloc 5 avail 13',
  format('%s | %s | %s', :'s3a', :'s3b', :'s3c'));

\echo '── S4g) 열린 B급 줄이 가리키는 칸은 끌 수 없다'
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, true)::text', :'bin_e')) as s4g1 \gset
set local session_replication_role = replica;
update public.so_line set bgrade_bin_id = :'bin_e'::uuid where id = :'l2'::uuid;
set local session_replication_role = origin;
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, false)::text', :'bin_e')) as s4g2 \gset
set local session_replication_role = replica;
update public.so set status = 'fulfilled', closed_at = now() where id = :'so1'::uuid;
set local session_replication_role = origin;
select pg_temp.as_user(:'m', format('select public.ref_bin_bgrade_set(%L::uuid, false)::text', :'bin_e')) as s4g3 \gset
select pg_temp.chk('S4g empty B-grade bin on an open B-grade line: off refused · once the order is fulfilled: off passes',
  (pg_temp.j(:'s4g1')->>'changed')::boolean and :'s4g2' like 'ERR P0001: Bin BGR1-E is on 1 open B-grade sale line(s)%' and (pg_temp.j(:'s4g3')->>'changed')::boolean,
  format('%s | %s | %s', :'s4g1', :'s4g2', :'s4g3'));

\echo '── S5) 착지 — ims_inv_balance · inv_balance 를 읽고 bgrade 를 안 보는 함수 = 허락 목록(주석 걷고)'
create temp table bgr_src on commit drop as
  select p.proname, regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as s from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
select (select string_agg(proname, ',' order by proname) from bgr_src where s ~ '\mims_inv_balance\M') as s5_iib,
       (select string_agg(proname, ',' order by proname) from bgr_src where s ~ '\minv_balance\M') as s5_ib,
       (select string_agg(proname, ',' order by proname) from bgr_src where s ~ '\minv_available_base\M' and proname <> 'inv_available_base') as s5_iab,
       (select string_agg(proname, ',' order by proname) from bgr_src where (s ~ '\mims_inv_balance\M' or s ~ '\minv_balance\M') and s !~ 'bgrade') as s5_blind \gset
\echo :s5_iib
\echo :s5_ib
\echo :s5_iab
select pg_temp.chk(format('S5 readers that do not look at bgrade = allowlist (%s)', :'s5_blind'),
  :'s5_blind' = 'inv_adjust_ledger,inv_move_bin_contents,inv_stock_master,inv_stock_master_sku,product_bom_set,product_update,stk_bins,stk_bins_many,wms_health_check',
  format('blind %s | iib %s | ib %s', :'s5_blind', :'s5_iib', :'s5_ib'));
\else
select pg_temp.chk('G1 ~ S5 skipped: bgr-1a not landed', false, 'ref_bin.is_bgrade missing');
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real so · ledger · reservations · bins that existed at the snapshot untouched (no real bin is B-grade)', pg_temp.real_rows(:'t0'::timestamptz) like :'real_before' || '%' and pg_temp.real_rows(:'t0'::timestamptz) !~ '/bg=[1-9]',
  format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · so_number_seq 되돌리기'
select (select count(*) from public.customer where name like 'BGR1 %') + (select count(*) from public.product where sku like 'BGR1-%') + (select count(*) from public.ims_staff where email like 'bgr1-%')
     + (select count(*) from public.ref_bin where name like 'BGR1-%') + (select count(*) from public.inv_ledger where sku like 'BGR1-%') as leftovers;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select (select last_value || '|' || is_called from public.so_number_seq) as so_seq_after;
