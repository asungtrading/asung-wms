-- stk-av-1-verify.sql — Stock Availability 넓히기 DB: 원가 열쇠 cost · ims_can_view_cost · stk_reserved(목록 합 = 타일) · stk_availability 재발행(옛 인자 무변 · Both · 공급처 · 바코드) · stk_value_many · stk_value_total(열쇠 · inv_layer_open 합) · 판정 262 그대로
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020232704_stk_av_1_reserved_value_cost_key.sql -f supabase/tests/stk-av-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 G0 · S0(옛 서명 · 옛 반환 md5)는 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더
--   재료는 가짜만(직원 넷 · SO-79590 세트 줄 예약 · TRF-79590 세트 줄 · 세트 공급처 줄 하나) · 실제 행 무변 = 스냅샷 때 있던 id 집합 · rollback
--   이 차수 밖(판정 576): 레이어 읽기 가리기 · 열쇠 없는 직원 쓰기 길은 rls-3 검증으로 — 대신 「열쇠 없는 직원 → stk_value_* 거부(원문) · stk_availability 반환에 원가 자리 0」

\echo '── db_role · schema_migrations'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261020232704' \gset
select :n_applied as schema_migrations_rows_for_20261020232704;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return v;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 옛 열 21 개만으로 md5 — 옛 함수(21 열)와 새 함수(22 열) 양쪽에서 같은 식
create function pg_temp.md5_av(p_wh uuid, p_q text, p_zero boolean) returns text language plpgsql as $$
declare v text;
begin
  execute format($q$ select md5(coalesce(string_agg(r.product_id || '|' || r.sku || '|' || r.name || '|' || coalesce(r.brand_id::text, '') || '|' || coalesce(r.brand_name, '') || '|' || coalesce(r.category_id::text, '') || '|' || coalesce(r.category_name, '') || '|' || r.is_active || '|' || trim_scale(r.on_hand) || '|' || trim_scale(r.sales_allocated) || '|' || trim_scale(r.transfer_reserved) || '|' || trim_scale(r.available) || '|' || trim_scale(r.on_order) || '|' || trim_scale(r.in_transit) || '|' || coalesce(r.last_event_on::text, '') || '|' || coalesce(r.matched_set_sku, '') || '|' || coalesce(trim_scale(r.matched_set_pack_factor)::text, '') || '|' || coalesce(r.matched_set_count::text, '') || '|' || coalesce(trim_scale(r.sale_pct)::text, '') || '|' || coalesce(r.sale_conditional::text, '') || '|' || r.total, ',' order by r.sku, r.product_id), ''))
                   from public.stk_availability(%L::uuid, %L, null, null, %L, 500, 0, false) r $q$, p_wh, p_q, p_zero) into v;
  return v;
end $$;
-- V2 — 화면처럼 쪽마다(500) stk_availability → stk_value_many 를 끝까지 더한다
create function pg_temp.value_by_pages(p_wh uuid, p_brand uuid) returns table(n int, s numeric) language plpgsql as $$
declare v_off int := 0; v_ids uuid[]; v_n int := 0; v_s numeric := 0;
begin
  loop
    select array_agg(a.product_id) into v_ids from public.stk_availability(p_wh, null, p_brand, null, true, 500, v_off, false) a;
    exit when v_ids is null;
    v_n := v_n + cardinality(v_ids);
    select v_s + coalesce(sum(v.remaining_value), 0) into v_s from public.stk_value_many(v_ids, p_wh) v;
    v_off := v_off + 500;
  end loop;
  return query select v_n, v_s;
end $$;
-- R1 — 모든 재고 키 × 창고(예약이 있는 것 전부)에서 stk_reserved 의 so_total · trf_total = inv_available_base 의 sales_alloc_ea · transfer_alloc_ea
create function pg_temp.sum_eq_tile(p_wh uuid) returns table(checked int, mismatched int, with_sets int, sample text) language plpgsql as $$
declare r record; v jsonb; v_n int := 0; v_bad int := 0; v_sets int := 0; v_sample text := '';
begin
  for r in select b.stock_pid, b.sales_alloc_ea, b.transfer_alloc_ea from public.inv_available_base(p_wh, null) b where b.sales_alloc_ea <> 0 or b.transfer_alloc_ea <> 0 loop
    v := public.stk_reserved(r.stock_pid, p_wh);
    v_n := v_n + 1;
    if exists (select 1 from jsonb_array_elements(v->'so') e where (e->>'pack_factor')::numeric > 1) or exists (select 1 from jsonb_array_elements(v->'trf') e where (e->>'pack_factor')::numeric > 1) then v_sets := v_sets + 1; end if;
    if (v->>'so_total')::numeric <> r.sales_alloc_ea or (v->>'trf_total')::numeric <> r.transfer_alloc_ea then
      v_bad := v_bad + 1;
      if v_bad <= 3 then v_sample := v_sample || format(' [%s so %s/%s trf %s/%s]', v->>'sku', v->>'so_total', r.sales_alloc_ea, v->>'trf_total', r.transfer_alloc_ea); end if;
    end if;
  end loop;
  return query select v_n, v_bad, v_sets, nullif(v_sample, '');
end $$;

\echo '── M0) 직원 넷(cost: manager ims+sales+cost · read: manager ims+cost:read · wms: worker wms+picking · sup: supervisor perms []) · 창고 둘 · 실제 행 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'stkav-cost@test.invalid', 'STKAV cost', 'manager', '["ims","sales","cost"]', '{}') returning auth_user_id::text as g_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'stkav-read@test.invalid', 'STKAV read', 'manager', '["ims","cost:read"]', '{}') returning auth_user_id::text as g_uid2 \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'stkav-wms@test.invalid', 'STKAV wms', 'worker', '["wms","picking"]', '{}') returning auth_user_id::text as g_uid3 \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'stkav-sup@test.invalid', 'STKAV sup', 'supervisor', '[]', '{}') returning auth_user_id::text as g_uid4 \gset
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
\set g_claims2 '{"sub":"' :g_uid2 '","role":"authenticated"}'
\set g_claims3 '{"sub":"' :g_uid3 '","role":"authenticated"}'
\set g_claims4 '{"sub":"' :g_uid4 '","role":"authenticated"}'
select id::text as wh1, name as wh1name from public.ref_warehouse where name = 'Asung Trading Inc.' and is_active \gset
select id::text as wh2, name as wh2name from public.ref_warehouse where name = 'Asung - Edmonton' and is_active \gset
select count(*) as n_active_wh from public.ref_warehouse where is_active \gset
select count(*) as n_res, md5(string_agg(id::text, ',' order by id)) as md5_res from public.so_reserve \gset
select count(*) as n_trl, md5(string_agg(id::text, ',' order by id)) as md5_trl from public.inv_transfer_line \gset
select count(*) as n_ps, md5(string_agg(id::text, ',' order by id)) as md5_ps from public.product_supplier \gset
select pg_temp.chk(format('M0 staff ×4 · warehouses %s + %s (active %s) · snapshots so_reserve %s · transfer_line %s · product_supplier %s', :'wh1name', :'wh2name', :n_active_wh, :n_res, :n_trl, :n_ps),
  :'g_uid' <> '' and :'g_uid4' <> '' and :'wh1' <> '' and :'wh2' <> '' and :n_active_wh = 2 and :n_res > 0, 'see M0');

\echo '── M1) 가짜 재료 — SO-79590(확정 · 세트 ABC83712-96 2개 allocated → 낱개 192 EA) · TRF-79590(confirmed · 세트 AS91761-24 3개 → 72 EA · 출발 창고 1) · 공급처 줄(세트 AS91761-24 · 기본 아님) · 바코드 둘'
select s.id::text as set1, s.sku as set1sku, s.pack_factor::text as set1pf, s.parent_product_id::text as par1, p.sku as par1sku from public.product s join public.product p on p.id = s.parent_product_id where s.sku = 'ABC83712-96' \gset
select s.id::text as set2, s.sku as set2sku, s.pack_factor::text as set2pf, s.parent_product_id::text as par2, p.sku as par2sku from public.product s join public.product p on p.id = s.parent_product_id where s.sku = 'AS91761-24' \gset
select id::text as cust from public.customer where is_active order by name limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset
-- 공급처: 기본 아닌 활성 줄이 가장 많은 공급처 · 그 공급처에 낱개 AS91761 의 줄이 없어야 세트 줄 시험이 선다
select ps.supplier_id::text as sup from public.product_supplier ps join public.product p on p.id = ps.product_id
 where ps.is_active and not ps.is_default and not exists (select 1 from public.product_supplier z where z.supplier_id = ps.supplier_id and z.is_active and z.product_id = :'par2'::uuid)
 group by 1 order by count(*) desc limit 1 \gset
select count(distinct coalesce(p.parent_product_id, p.id)) as n_sup_keys, count(*) filter (where not ps.is_default) as n_sup_nondef from public.product_supplier ps join public.product p on p.id = ps.product_id where ps.supplier_id = :'sup'::uuid and ps.is_active \gset
select b.barcode as bc1, p.id::text as bc1pid, p.sku as bc1sku from public.product_barcode b join public.product p on p.id = b.product_id where b.is_active and p.parent_product_id is not null and p.sku = :'set2sku' limit 1 \gset
select b.barcode as bc2, p.id::text as bc2pid, p.sku as bc2sku from public.product_barcode b join public.product p on p.id = b.product_id where b.is_active and p.parent_product_id is null and not exists (select 1 from public.product_barcode z where z.barcode = b.barcode and z.product_id <> b.product_id) and exists (select 1 from public.ims_inv_balance i where i.product_id = p.id and i.warehouse = :'wh1name' and i.qty > 0) order by b.barcode limit 1 \gset
-- 타일 before(낱개 둘 × 창고 1)
select coalesce((select b.sales_alloc_ea from public.inv_available_base(:'wh1'::uuid, array[:'par1'::uuid]) b), 0)::text as alloc1_before \gset
select coalesce((select b.transfer_alloc_ea from public.inv_available_base(:'wh1'::uuid, array[:'par2'::uuid]) b), 0)::text as talloc2_before \gset
set local session_replication_role = replica;   -- 가짜 문서는 창구를 거치지 않는다(rcv-1b 틀) · 트리거 끔 · rollback
insert into public.so (so_number, customer_id, channel, intake, status, location_id, currency_id, confirmed_at) values ('SO-79590', :'cust'::uuid, 'warehouse', 'manual', 'confirmed', :'wh1'::uuid, :'cad'::uuid, now()) returning id::text as so1 \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, unit_price) values (:'so1'::uuid, 1, :'set1'::uuid, :'set1sku', :'set1pf'::numeric, 2, 1) returning id::text as sol1 \gset
insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_at) values (:'sol1'::uuid, 2, 'allocated', now()) returning id::text as res1 \gset
insert into public.inv_transfer (transfer_number, status, from_warehouse_id, to_warehouse_id, confirmed_at) values ('TRF-79590', 'confirmed', :'wh1'::uuid, :'wh2'::uuid, now()) returning id::text as trf1 \gset
insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (:'trf1'::uuid, 1, :'set2'::uuid, :'set2sku', 3, :'set2pf'::numeric) returning id::text as trl1 \gset
insert into public.product_supplier (product_id, supplier_id, is_active, is_default) values (:'set2'::uuid, :'sup'::uuid, true, false) returning id::text as ps1 \gset
set local session_replication_role = origin;
select coalesce((select b.sales_alloc_ea from public.inv_available_base(:'wh1'::uuid, array[:'par1'::uuid]) b), 0)::text as alloc1_after \gset
select coalesce((select b.transfer_alloc_ea from public.inv_available_base(:'wh1'::uuid, array[:'par2'::uuid]) b), 0)::text as talloc2_after \gset
select pg_temp.chk(format('M1 fixtures: SO-79590 set line ×%s → tile +%s EA (%s → %s) · TRF-79590 set line ×%s → tile +%s EA (%s → %s) · supplier %s (keys %s · non-default lines %s) · barcodes set %s / single %s', :'set1pf', :'alloc1_after'::numeric - :'alloc1_before'::numeric, :'alloc1_before', :'alloc1_after', :'set2pf', :'talloc2_after'::numeric - :'talloc2_before'::numeric, :'talloc2_before', :'talloc2_after', left(:'sup', 8), :n_sup_keys, :n_sup_nondef, :'bc1', :'bc2'),
  :'alloc1_after'::numeric - :'alloc1_before'::numeric = 2 * :'set1pf'::numeric and :'talloc2_after'::numeric - :'talloc2_before'::numeric = 3 * :'set2pf'::numeric
  and :'sup' <> '' and :n_sup_nondef > 0 and :'bc1' <> '' and :'bc2' <> '' and :'ps1' <> '', 'see M1');

select set_config('request.jwt.claims', :'g_claims4', true) as claims_sup;
\if :{?mig}
\echo '── S0) 옛 모양 — 옛 서명 · 옛 반환 md5(창고 1 · 0 포함 500 · q null / q 세트 sku) · catalog 에 cost 없음 · 함수 넷 없음'
select pg_temp.md5_av(:'wh1'::uuid, null, true) as m_av_old \gset
select pg_temp.md5_av(:'wh1'::uuid, :'set2sku', true) as m_avq_old \gset
select pg_temp.chk('G0 before the trial: old 8-arg signature · no stk_reserved · stk_value_* · ims_can_view_cost · catalog has no cost · not in schema_migrations',
  to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean)') is not null and to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean, uuid)') is null
  and to_regprocedure('public.stk_reserved(uuid, uuid)') is null and to_regprocedure('public.stk_value_many(uuid[], uuid)') is null and to_regprocedure('public.ims_can_view_cost()') is null
  and not (public.ims_perm_catalog()->'screens' ? 'cost') and :n_applied = 0 and :'m_av_old' <> '', format('n_applied %s', :n_applied));
\echo '── \i 시험 적용'
\i :mig
\else
select pg_temp.chk('P0c confirm run: migration 20261020232704 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

\echo '── G1) 실물 — 서명 · definer 5 · ACL · catalog cost(17) · 반환에 원가 자리 0(262) · by_warehouse 끝 · 같은 조건 표식(566) · 열쇠 문(567)'
select pg_temp.chk('G1 new 9-arg stk_availability only · stk_reserved · stk_value_many · stk_value_total · ims_can_view_cost · 5 definer · authenticated yes / anon no · catalog cost (17 screens) · no cost column in stk_availability / stk_reserved / inv_available_base · by_warehouse last · stk_reserved and inv_available_base carry the same markers · both value functions call ims_can_view_cost',
  to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean)') is null and to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean, uuid)') is not null
  and to_regprocedure('public.stk_reserved(uuid, uuid)') is not null and to_regprocedure('public.stk_value_many(uuid[], uuid)') is not null and to_regprocedure('public.stk_value_total(uuid, text, uuid, uuid, uuid, boolean)') is not null and to_regprocedure('public.ims_can_view_cost()') is not null
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stk_availability', 'stk_reserved', 'stk_value_many', 'stk_value_total', 'ims_can_view_cost') and p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')) = 5
  and (public.ims_perm_catalog()->'screens' ? 'cost') and (select count(*) from jsonb_object_keys(public.ims_perm_catalog()->'screens')) = 17 and public.ims_perm_catalog()->'screens'->'cost'->>'room' = 'ims'
  and not exists (select 1 from pg_proc p where p.oid in (to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean, uuid)'), to_regprocedure('public.stk_reserved(uuid, uuid)'), to_regprocedure('public.inv_available_base(uuid, uuid[])')) and pg_get_function_result(p.oid) ~* '(amount|unit_price|cost|value)')
  and pg_get_function_result(to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean, uuid)')) ~ 'by_warehouse jsonb\)$'
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stk_reserved', 'inv_available_base') and p.prosrc ~ 'r\.kind = ''allocated''' and p.prosrc ~ '\(''confirmed'', ''at_wms'', ''picking''\)') = 2
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stk_value_many', 'stk_value_total') and p.prosrc ~ 'ims_can_view_cost\(\)') = 2
  and obj_description(to_regprocedure('public.inv_available_base(uuid, uuid[])'), 'pg_proc') ~ 'stk_reserved', 'see G1');
select (to_regprocedure('public.stk_reserved(uuid, uuid)') is not null and to_regprocedure('public.stk_value_total(uuid, text, uuid, uuid, uuid, boolean)') is not null) as landed \gset

\if :landed
\echo '── K1) 열쇠 — cost(manager perms cost) t · read(cost:read) t · wms(worker) f · sup(supervisor · perms []) t'
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true) as c; select public.ims_can_view_cost()::text as k_cost \gset
select set_config('request.jwt.claims', :'g_claims2', true) as c; select public.ims_can_view_cost()::text as k_read \gset
select set_config('request.jwt.claims', :'g_claims3', true) as c; select public.ims_can_view_cost()::text as k_wms \gset
select set_config('request.jwt.claims', :'g_claims4', true) as c; select public.ims_can_view_cost()::text as k_sup \gset
select pg_temp.chk('K1 ims_can_view_cost: cost perm true · cost:read true · wms worker false · supervisor by role true', :'k_cost' = 'true' and :'k_read' = 'true' and :'k_wms' = 'false' and :'k_sup' = 'true', format('%s %s %s %s', :'k_cost', :'k_read', :'k_wms', :'k_sup'));
reset role;

\echo '── A1) 옛 인자 8개 호출(wms 직원) → 21 열 반환 무변(시험 갈래 · md5) · 22번째 열 by_warehouse 원소 하나 = 평평한 열'
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims3', true) as c;
\if :{?mig}
select pg_temp.md5_av(:'wh1'::uuid, null, true) as m_av_new \gset
select pg_temp.md5_av(:'wh1'::uuid, :'set2sku', true) as m_avq_new \gset
select pg_temp.chk('A1 old 8-arg call (q null · q set sku · include_zero · 500) returns the same 21 columns as before the trial', :'m_av_new' = :'m_av_old' and :'m_avq_new' = :'m_avq_old', format('%s vs %s · q %s vs %s', :'m_av_new', :'m_av_old', :'m_avq_new', :'m_avq_old'));
\endif
reset role;
select count(*) as a1_n, count(*) filter (where jsonb_array_length(r.by_warehouse) = 1 and (r.by_warehouse->0->>'warehouse_id')::uuid = :'wh1'::uuid
         and (r.by_warehouse->0->>'on_hand')::numeric = r.on_hand and (r.by_warehouse->0->>'available')::numeric = r.available and (r.by_warehouse->0->>'in_transit')::numeric = r.in_transit) as a1_ok
  from public.stk_availability(:'wh1'::uuid, null, null, null, false, 200, 0, false) r \gset
select pg_temp.chk(format('A1b single warehouse: by_warehouse has one element equal to the flat columns (%s rows)', :a1_n), :a1_n = 200 and :a1_ok = :a1_n, format('%s of %s', :a1_ok, :a1_n));

\echo '── A2) Both(p_warehouse_id null) — 0 포함 500 줄 = 창고 1 + 창고 2 를 따로 부른 값의 합 · by_warehouse 원소 둘(이름 순) = 따로 부른 값 · total 같음'
create temp table t_both as select * from public.stk_availability(null, null, null, null, true, 500, 0, false);
create temp table t_w1 as select * from public.stk_availability(:'wh1'::uuid, null, null, null, true, 500, 0, false);
create temp table t_w2 as select * from public.stk_availability(:'wh2'::uuid, null, null, null, true, 500, 0, false);
select count(*) as a2_n,
       count(*) filter (where b.on_hand = w1.on_hand + w2.on_hand and b.sales_allocated = w1.sales_allocated + w2.sales_allocated and b.transfer_reserved = w1.transfer_reserved + w2.transfer_reserved
                          and b.available = w1.available + w2.available and b.on_order = w1.on_order + w2.on_order and b.in_transit = w1.in_transit + w2.in_transit
                          and b.last_event_on is not distinct from greatest(w1.last_event_on, w2.last_event_on) and b.total = w1.total and b.total = w2.total) as a2_sum_ok,
       count(*) filter (where jsonb_array_length(b.by_warehouse) = 2 and b.by_warehouse->0->>'warehouse' = :'wh2name' and b.by_warehouse->1->>'warehouse' = :'wh1name'
                          and (b.by_warehouse->1->>'on_hand')::numeric = w1.on_hand and (b.by_warehouse->1->>'available')::numeric = w1.available and (b.by_warehouse->1->>'sales_allocated')::numeric = w1.sales_allocated and (b.by_warehouse->1->>'transfer_reserved')::numeric = w1.transfer_reserved and (b.by_warehouse->1->>'on_order')::numeric = w1.on_order and (b.by_warehouse->1->>'in_transit')::numeric = w1.in_transit
                          and (b.by_warehouse->0->>'on_hand')::numeric = w2.on_hand and (b.by_warehouse->0->>'available')::numeric = w2.available and (b.by_warehouse->0->>'sales_allocated')::numeric = w2.sales_allocated and (b.by_warehouse->0->>'transfer_reserved')::numeric = w2.transfer_reserved and (b.by_warehouse->0->>'on_order')::numeric = w2.on_order and (b.by_warehouse->0->>'in_transit')::numeric = w2.in_transit) as a2_bw_ok,
       count(*) filter (where b.on_hand <> 0 or b.sales_allocated <> 0 or b.transfer_reserved <> 0 or b.on_order <> 0 or b.in_transit <> 0) as a2_nonzero
  from t_both b join t_w1 w1 on w1.product_id = b.product_id join t_w2 w2 on w2.product_id = b.product_id \gset
select pg_temp.chk(format('A2 Both = sum of the two single calls (500 rows · %s non-zero) · by_warehouse [Edmonton, Toronto] = single calls · total equal', :a2_nonzero), :a2_n = 500 and :a2_sum_ok = 500 and :a2_bw_ok = 500 and :a2_nonzero > 0, format('n %s · sum ok %s · by_warehouse ok %s', :a2_n, :a2_sum_ok, :a2_bw_ok));
select set_config('request.jwt.claims', :'g_claims3', true) as c;
select count(*) filter (where r.on_hand = 0 and r.sales_allocated = 0 and r.transfer_reserved = 0 and r.on_order = 0 and r.in_transit = 0) as a3_zero_rows, max(r.total) as a3_total from public.stk_availability(null, null, null, null, false, 500, 0, false) r \gset
select max(r.total) as a3_total_zero from public.stk_availability(null, null, null, null, true, 1, 0, false) r \gset
select pg_temp.chk(format('A3 Both zero-hiding: no all-zero row when include_zero=false (total %s) · include_zero=true total %s is larger', :a3_total, :a3_total_zero), :a3_zero_rows = 0 and :a3_total_zero > :a3_total, format('zero rows %s', :a3_zero_rows));

\echo '── A4) 공급처 거르기 — 줄 수 = 그 공급처의 활성 줄이 있는 재고 키(기본 아니어도 · 세트 줄은 낱개로) · 낱개 AS91761 이 세트 줄로 들어온다 · 기본 아닌 줄만 있는 제품도'
select max(r.total) as a4_total, count(*) filter (where r.product_id = :'par2'::uuid) as a4_par2 from public.stk_availability(null, null, null, null, true, 500, 0, false, :'sup'::uuid) r \gset
select count(distinct coalesce(p.parent_product_id, p.id)) as a4_expect from public.product_supplier ps join public.product p on p.id = ps.product_id where ps.supplier_id = :'sup'::uuid and ps.is_active
  and not exists (select 1 from public.product_bom bm where bm.parent_product_id = coalesce(p.parent_product_id, p.id) and bm.is_active) \gset
select count(*) as a4_nondef_only from public.product_supplier ps join public.product p on p.id = ps.product_id where ps.supplier_id = :'sup'::uuid and ps.is_active and not ps.is_default and p.parent_product_id is null
  and not exists (select 1 from public.product_supplier z where z.product_id = p.id and z.supplier_id = ps.supplier_id and z.is_default) \gset
select count(*) as a4_nondef_seen from public.stk_availability(null, null, null, null, true, 500, 0, false, :'sup'::uuid) r
  where exists (select 1 from public.product_supplier ps where ps.product_id = r.product_id and ps.supplier_id = :'sup'::uuid and ps.is_active and not ps.is_default) \gset
select coalesce(max(r.total), 0) as a4_inactive from public.stk_availability(null, null, null, null, true, 1, 0, false, gen_random_uuid()) r \gset
select pg_temp.chk(format('A4 supplier filter: total %s = active-line stock keys %s · AS91761 arrives through its set line · non-default-only products %s seen (%s rows with non-default lines) · unknown supplier → 0', :a4_total, :a4_expect, :a4_nondef_only, :a4_nondef_seen),
  :a4_total = :a4_expect and :a4_par2 = 1 and :a4_nondef_seen >= :a4_nondef_only and :a4_nondef_only > 0 and :a4_inactive = 0, 'see A4');

\echo '── A5) 바코드 정확 일치 — 낱개 바코드 → 그 제품 한 줄 · 세트 바코드 → 낱개 줄 + matched_set_sku · 앞뒤 자른 바코드 → 0 · sku/name 검색은 그대로'
select max(r.total) as a5_n1, bool_or(r.product_id = :'bc2pid'::uuid) as a5_hit1 from public.stk_availability(:'wh1'::uuid, :'bc2', null, null, true, 10, 0, false) r \gset
select max(r.total) as a5_n2, bool_or(r.product_id = :'par2'::uuid and r.matched_set_sku = :'bc1sku') as a5_hit2 from public.stk_availability(:'wh1'::uuid, :'bc1', null, null, true, 10, 0, false) r \gset
select coalesce(max(r.total), 0) as a5_n3 from public.stk_availability(:'wh1'::uuid, left(:'bc2', length(:'bc2') - 1) || 'x', null, null, true, 10, 0, false) r \gset
select pg_temp.chk(format('A5 barcode %s → 1 row (%s) · set barcode %s → stock row AS91761 with matched_set_sku %s · altered barcode → 0', :'bc2', :'bc2sku', :'bc1', :'bc1sku'),
  :a5_n1 = 1 and :'a5_hit1' = 't' and :'a5_hit2' = 't' and :a5_n3 = 0, format('n1 %s hit1 %s · n2 %s hit2 %s · n3 %s', :a5_n1, :'a5_hit1', :a5_n2, :'a5_hit2', :a5_n3));

\echo '── R1) 목록 합 = 타일 — 예약이 있는 모든 재고 키 × 창고 둘(가짜 세트 줄 둘 포함) · so_total = sales_alloc_ea · trf_total = transfer_alloc_ea'
select set_config('request.jwt.claims', :'g_claims', true) as c;
select checked as r1_n1, mismatched as r1_bad1, with_sets as r1_sets1, coalesce(sample, '') as r1_s1 from pg_temp.sum_eq_tile(:'wh1'::uuid) \gset
select checked as r1_n2, mismatched as r1_bad2, with_sets as r1_sets2, coalesce(sample, '') as r1_s2 from pg_temp.sum_eq_tile(:'wh2'::uuid) \gset
select pg_temp.chk(format('R1 list sum = tile for every reserved key: %s keys (%s) + %s keys (%s) · 0 mismatches · rows with pack_factor>1 %s', :r1_n1, :'wh1name', :r1_n2, :'wh2name', :r1_sets1 + :r1_sets2),
  :r1_n1 > 0 and :r1_bad1 = 0 and :r1_bad2 = 0 and :r1_sets1 >= 2, format('bad %s %s · samples %s %s', :r1_bad1, :r1_bad2, :'r1_s1', :'r1_s2'));

\echo '── R2) 가짜 줄 상세 — SO-79590 2 × 96 = 192 · TRF-79590 3 × 24 = 72 · 세트 id 로 불러도 낱개와 같은 결과 · 창고 2 에서는 TRF 안 보임(출발 창고 몫)'
select public.stk_reserved(:'par1'::uuid, :'wh1'::uuid)::text as r2a \gset
select public.stk_reserved(:'set2'::uuid, :'wh1'::uuid)::text as r2b \gset
select public.stk_reserved(:'par2'::uuid, :'wh1'::uuid)::text as r2c \gset
select public.stk_reserved(:'par2'::uuid, :'wh2'::uuid)::text as r2d \gset
select pg_temp.chk('R2 SO-79590 row: sku ABC83712-96 · qty 2 · pack 96 · qty_ea 192 · status confirmed · customer_name shown (sales) · TRF-79590 row: qty 3 · pack 24 · qty_ea 72 · from Toronto to Edmonton · set id = parent id · Edmonton shows no TRF-79590',
  exists (select 1 from jsonb_array_elements(pg_temp.j(:'r2a')->'so') e where e->>'so_number' = 'SO-79590' and e->>'line_sku' = :'set1sku' and (e->>'qty')::numeric = 2 and (e->>'pack_factor')::numeric = 96 and (e->>'qty_ea')::numeric = 192 and e->>'status' = 'confirmed' and e->>'customer_name' is not null)
  and exists (select 1 from jsonb_array_elements(pg_temp.j(:'r2c')->'trf') e where e->>'transfer_number' = 'TRF-79590' and (e->>'qty')::numeric = 3 and (e->>'pack_factor')::numeric = 24 and (e->>'qty_ea')::numeric = 72 and e->>'from_warehouse' = :'wh1name' and e->>'to_warehouse' = :'wh2name' and e->>'status' = 'confirmed')
  and :'r2b' = :'r2c' and pg_temp.j(:'r2a')->>'product_id' = :'par1' and (pg_temp.j(:'r2a')->>'customer_name_visible')::boolean
  and not exists (select 1 from jsonb_array_elements(pg_temp.j(:'r2d')->'trf') e where e->>'transfer_number' = 'TRF-79590'), format('a %s | c %s | d %s', left(:'r2a', 300), left(:'r2c', 300), left(:'r2d', 200)));

\echo '── R3) 손님 이름 가리기 — wms 직원: so 줄은 보이고 customer_name 은 전부 null · customer_name_visible false · TRF 번호는 보인다 · 비활성 창고 · 모르는 제품 거부'
select set_config('request.jwt.claims', :'g_claims3', true) as c;
select public.stk_reserved(:'par1'::uuid, :'wh1'::uuid)::text as r3a \gset
select public.stk_reserved(:'par2'::uuid, :'wh1'::uuid)::text as r3b \gset
select pg_temp.run(format('select public.stk_reserved(%L::uuid, (select id from public.ref_warehouse where not is_active limit 1))::text', :'par1')) as r3c \gset
select pg_temp.run(format('select public.stk_reserved(gen_random_uuid(), %L::uuid)::text', :'wh1')) as r3d \gset
select pg_temp.chk('R3 wms worker: SO-79590 row present with customer_name null · customer_name_visible false · TRF-79590 visible with number · status · qty_ea · inactive warehouse and unknown product are refused',
  exists (select 1 from jsonb_array_elements(pg_temp.j(:'r3a')->'so') e where e->>'so_number' = 'SO-79590' and e->>'customer_name' is null)
  and not exists (select 1 from jsonb_array_elements(pg_temp.j(:'r3a')->'so') e where e->>'customer_name' is not null) and not (pg_temp.j(:'r3a')->>'customer_name_visible')::boolean
  and exists (select 1 from jsonb_array_elements(pg_temp.j(:'r3b')->'trf') e where e->>'transfer_number' = 'TRF-79590' and (e->>'qty_ea')::numeric = 72)
  and :'r3c' like 'ERR%Warehouse not found or inactive%' and :'r3d' like 'ERR%Product not found%', format('a %s | c %s | d %s', left(:'r3a', 200), :'r3c', :'r3d'));

\echo '── V1) stk_value_many(cost 직원) — 열린 레이어가 있는 sku 500 × 창고 1: remaining_value · layer_qty_ea = inv_layer_open 의 sku 합 · 세트 id → 낱개 · 레이어 없는 키 0 · 500 초과 거부'
select set_config('request.jwt.claims', :'g_claims', true) as c;
create temp table t_v1exp as select o.sku, p.id as product_id, sum(o.remaining_qty) as q, sum(o.remaining_cost) as v from public.inv_layer_open o join public.product p on p.sku = o.sku where o.warehouse = :'wh1name' and p.parent_product_id is null group by 1, 2 order by 1 limit 500;
select array_agg(product_id)::text as v1pids from t_v1exp \gset
select set_config('request.jwt.claims', :'g_claims', true) as c;
create temp table t_v1got as select * from public.stk_value_many(:'v1pids'::uuid[], :'wh1'::uuid);
select count(*) as v1_n, count(*) filter (where g.layer_qty_ea = e.q and g.remaining_value = e.v and g.warehouse_id = :'wh1'::uuid) as v1_ok, (select count(*) from t_v1got) as v1_rows from t_v1exp e join t_v1got g on g.product_id = e.product_id \gset
select set_config('request.jwt.claims', :'g_claims', true) as c;
select string_agg(product_id::text || ':' || trim_scale(layer_qty_ea) || ':' || trim_scale(remaining_value), ',') as v1_set from public.stk_value_many(array[:'set2'::uuid], :'wh1'::uuid) \gset
select string_agg(product_id::text || ':' || trim_scale(layer_qty_ea) || ':' || trim_scale(remaining_value), ',') as v1_par from public.stk_value_many(array[:'par2'::uuid], :'wh1'::uuid) \gset
select count(*) as v1_both, count(distinct warehouse_id) as v1_both_wh from public.stk_value_many(array[:'par2'::uuid], null) \gset
select pg_temp.run('select count(*)::text from public.stk_value_many((select array_agg(gen_random_uuid()) from generate_series(1, 501)), null)') as v1_501 \gset
select count(*) as v1_unknown from public.stk_value_many(array[gen_random_uuid()], :'wh1'::uuid) \gset
select pg_temp.chk(format('V1 stk_value_many = inv_layer_open sums for %s skus (%s rows) · set id gives the parent row · Both gives 2 rows · 501 ids refused · unknown id no row', :v1_n, :v1_rows),
  :v1_n = 500 and :v1_ok = 500 and :v1_rows = 500 and :'v1_set' = :'v1_par' and :v1_both = 2 and :v1_both_wh = 2 and :'v1_501' like 'ERR%Too many products%' and :v1_unknown = 0, format('ok %s of %s · set %s par %s · 501 %s', :v1_ok, :v1_n, :'v1_set', :'v1_par', :'v1_501'));

\echo '── V2) stk_value_total — 창고 1 전체 = inv_layer_open 의 재고 키 합 · Both 두 줄 · 브랜드 거르기 = 그 브랜드 stk_availability(0 포함) 줄의 stk_value_many 합 · 공급처 거르기 줄'
select r.products::text as v2_p, trim_scale(r.layer_qty_ea)::text as v2_q, trim_scale(r.remaining_value)::text as v2_v from public.stk_value_total(:'wh1'::uuid) r \gset
select count(distinct o.sku)::text as v2_ep, trim_scale(sum(o.remaining_qty))::text as v2_eq, trim_scale(sum(o.remaining_cost))::text as v2_ev
  from public.inv_layer_open o join public.product p on p.sku = o.sku
 where o.warehouse = :'wh1name' and p.parent_product_id is null and not exists (select 1 from public.product_bom bm where bm.parent_product_id = p.id and bm.is_active) \gset
select trim_scale(sum(o.remaining_cost))::text as v2_all from public.inv_layer_open o where o.warehouse = :'wh1name' \gset
select id::text as brand1, name as brand1name from public.ref_brand where name = 'Climax' limit 1 \gset
select set_config('request.jwt.claims', :'g_claims', true) as c;
select trim_scale(r.remaining_value)::text as v2_bv, r.products::text as v2_bp from public.stk_value_total(:'wh1'::uuid, null, :'brand1'::uuid) r \gset
select trim_scale(s)::text as v2_bexp, n::text as v2_brows from pg_temp.value_by_pages(:'wh1'::uuid, :'brand1'::uuid) \gset
select count(*) as v2_both, string_agg(r.warehouse, ' + ' order by r.warehouse) as v2_both_wh from public.stk_value_total(null) r \gset
select trim_scale(r.remaining_value)::text as v2_sv, r.products::text as v2_sp from public.stk_value_total(:'wh1'::uuid, null, null, null, :'sup'::uuid) r \gset
select pg_temp.chk(format('V2 total %s = inv_layer_open over stock keys (%s products · %s EA · all layers incl. non-stock-key skus %s) · brand %s %s = sum of stk_value_many over all its %s availability rows (500 a page) · Both 2 rows (%s) · supplier filter %s products %s', :'v2_v', :'v2_ep', :'v2_eq', :'v2_all', :'brand1name', :'v2_bv', :'v2_brows', :'v2_both_wh', :'v2_sp', :'v2_sv'),
  :'v2_v' = :'v2_ev' and :'v2_q' = :'v2_eq' and :'v2_p' = :'v2_ep' and :'v2_bv' = :'v2_bexp' and :v2_both = 2 and :'v2_sp'::int > 0 and :'v2_sv'::numeric <= :'v2_v'::numeric,
  format('got %s/%s/%s vs %s/%s/%s · brand %s vs %s', :'v2_p', :'v2_q', :'v2_v', :'v2_ep', :'v2_eq', :'v2_ev', :'v2_bv', :'v2_bexp'));

\echo '── V3) 열쇠 — wms 직원 → stk_value_many · stk_value_total 거부(원문) · stk_availability 는 됨(원가 자리 없음) · cost:read 직원 → 됨 · supervisor → 됨'
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims3', true) as c;
select pg_temp.run(format('select count(*)::text from public.stk_value_many(array[%L::uuid], %L::uuid)', :'par2', :'wh1')) as v3a \gset
select pg_temp.run(format('select count(*)::text from public.stk_value_total(%L::uuid)', :'wh1')) as v3b \gset
select pg_temp.run(format('select count(*)::text from public.stk_availability(%L::uuid, null, null, null, false, 5, 0, false)', :'wh1')) as v3c \gset
select set_config('request.jwt.claims', :'g_claims2', true) as c;
select pg_temp.run(format('select count(*)::text from public.stk_value_many(array[%L::uuid], %L::uuid)', :'par2', :'wh1')) as v3d \gset
select set_config('request.jwt.claims', :'g_claims4', true) as c;
select pg_temp.run(format('select count(*)::text from public.stk_value_total(%L::uuid)', :'wh1')) as v3e \gset
select pg_temp.chk('V3 wms worker: stk_value_many and stk_value_total refused with "You do not have the Inventory cost permission" · stk_availability works · cost:read manager ok · supervisor ok',
  :'v3a' like 'ERR%You do not have the Inventory cost permission%' and :'v3b' like 'ERR%You do not have the Inventory cost permission%' and :'v3c' = '5' and :'v3d' = '1' and :'v3e' = '1', format('%s | %s | %s | %s | %s', :'v3a', :'v3b', :'v3c', :'v3d', :'v3e'));
reset role;

\echo '── T1) 시간(ms · 정보) — stk_availability 한 창고 · Both · stk_value_many 200 · stk_value_total 한 창고 · Both · stk_reserved'
select set_config('request.jwt.claims', :'g_claims', true) as c;
select array_agg(product_id)::text as t1pids from public.stk_availability(:'wh1'::uuid, null, null, null, false, 200, 0, false) \gset
select clock_timestamp()::text as t0 \gset
select count(*) from public.stk_availability(:'wh1'::uuid, null, null, null, false, 100, 0, false) \gset
select clock_timestamp()::text as t1 \gset
select count(*) from public.stk_availability(null, null, null, null, false, 100, 0, false) \gset
select clock_timestamp()::text as t2 \gset
select count(*) from public.stk_value_many(:'t1pids'::uuid[], :'wh1'::uuid) \gset
select clock_timestamp()::text as t3 \gset
select count(*) from public.stk_value_total(:'wh1'::uuid) \gset
select clock_timestamp()::text as t4 \gset
select count(*) from public.stk_value_total(null) \gset
select clock_timestamp()::text as t5 \gset
select public.stk_reserved(:'par1'::uuid, :'wh1'::uuid) \gset
select clock_timestamp()::text as t6 \gset
select pg_temp.chk(format('T1 ms — availability single %s · Both %s · value_many 200 %s · value_total single %s · Both %s · reserved %s (all under the 8 s statement_timeout)',
    round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000), round(extract(epoch from (:'t2'::timestamptz - :'t1'::timestamptz)) * 1000), round(extract(epoch from (:'t3'::timestamptz - :'t2'::timestamptz)) * 1000),
    round(extract(epoch from (:'t4'::timestamptz - :'t3'::timestamptz)) * 1000), round(extract(epoch from (:'t5'::timestamptz - :'t4'::timestamptz)) * 1000), round(extract(epoch from (:'t6'::timestamptz - :'t5'::timestamptz)) * 1000)),
  extract(epoch from (:'t6'::timestamptz - :'t0'::timestamptz)) < 8 * 6, 'see T1');

\else
select pg_temp.chk('K1 ~ T1 skipped: stk-av-1 not landed (stk_reserved · stk_value_total missing)', false, 'not landed — nothing to exercise');
\endif

\echo '── Z1) 실제 행 무접촉(스냅샷 id 집합 · 가짜 행 제외)'
select pg_temp.chk(format('Z1 real rows untouched: so_reserve %s · inv_transfer_line %s · product_supplier %s', :n_res, :n_trl, :n_ps),
  (select md5(string_agg(id::text, ',' order by id)) from public.so_reserve where id <> :'res1'::uuid) = :'md5_res'
  and (select md5(string_agg(id::text, ',' order by id)) from public.inv_transfer_line where id <> :'trl1'::uuid) = :'md5_trl'
  and (select md5(string_agg(id::text, ',' order by id)) from public.product_supplier where id <> :'ps1'::uuid) = :'md5_ps', 'see Z1');

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0'
select (select count(*) from public.so where so_number = 'SO-79590') + (select count(*) from public.inv_transfer where transfer_number = 'TRF-79590') + (select count(*) from public.ims_staff where email like 'stkav-%')
     + (select count(*) from public.product_supplier ps join public.product p on p.id = ps.product_id where p.sku = 'AS91761-24' and ps.is_active) as fake_traces_left,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('stk_reserved', 'stk_value_many', 'stk_value_total', 'ims_can_view_cost')) as new_functions_present;
