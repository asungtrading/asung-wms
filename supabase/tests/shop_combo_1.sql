do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;
-- supabase/tests/shop_combo_1.sql — shop-combo-1 검증: Shopify 로 보내는 콤보 재고 = 구성품으로 만들 수 있는 수(판정 831 · 2026-10-27)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4 · 잠금 규칙) — 기준(begin 앞 · 잠금 없음 · 옛 payload 전체를 임시 표로) → begin(lock_timeout 3s) → (-v mig 면 \i) → 검사 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027235949_shop_combo_1.sql -f supabase/tests/shop_combo_1.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK = 시험 = 확인 = EXPECT_OK(확인 갈래 전용 줄 없음 · A1 은 적용 뒤에는 새 = 새)
--   쓰기: 가짜 직원 1 · 가짜 상품 9(낱개 A B C E F · 세트 C-6 · 콤보 X Y Z W U V) · bom 줄 · 가짜 원장 줄(doc SHOPCOMBO1) · 실물 콤보 17 의 listing(test 스토어) · shop_variant 1 · sent 2 · 큐 줄 — 전부 rollback · 시퀀스는 당기지 않는다(큐 id bigserial 은 insert 로 당겨진다 — 번호 뜻 없음 · 허용)
--   갈래: A0 객체 · A1 콤보 아닌 변형 옛 = 새 · A2 실물 콤보 = so_available_many 로 흉내 낸 SO 셈 · A3 가짜 재료 · A4 큐(원장 · 세트 · bom · Release · live 꺼진 스토어 0) · A5 diff · A6 시간
--   실제 값(2026-10-28 00:10 UTC · 3 회차 통과 · 테스트 DB): OK 38 / 38 · begin~end 8.7 s(잠금 규칙 10 s 안) · payload 전체 42 줄 옛 0.678 s → 새 0.474 s
--     (av 를 대상 스토어의 위치로 좁히기 전엔 1.10 s — av 를 둘이 읽어 CTE 가 물질화되며 live 전 스토어 위치 셋까지 셌다) · 실물 콤보 17(cin7 65 줄 + manual 4 · 구성품 세트 0 · 전부 켜짐) × 위치 2 = 34 줄 전부 SO 셈과 같음
--     1 회차 A3j 불리언 캐스트 · 2 회차 A5d(같은 문장 안 서브쿼리가 함수의 insert 를 못 본다) + 12.3 s(A2d 좁힌 호출 17 → 3) 을 고쳤다
\set ON_ERROR_STOP on
\set EXPECT_OK 38
\pset pager off
-- 기준(begin 앞 · 잠금 없음) — 옛 payload 전체(모든 스토어)를 임시 표로 · 시간은 두 번 재어 짧은 쪽
select (select count(*) from public.shop_stock_queue where done_at is null) as sq0, (select coalesce(max(id), 0) from public.shop_stock_queue) as sq_max,
       (select count(*) from public.product) as n_prod0, (select count(*) from public.product_bom) as n_bom0, (select count(*) from public.product_bom where is_active) as n_bom_act0,
       (select count(*) from public.shop_listing) as n_list0, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.inv_ledger) as n_led0,
       (select count(*) from public.shop_variant) as n_var0, (select count(*) from public.shop_stock_sent) as n_sent0,
       (select id from public.shop_store where code = 'test') as test_id, (select id from public.shop_store where code = 'asung') as asung_id, (select id from public.shop_store where code = 'aone') as aone_id,
       (select id from public.ref_warehouse where name = 'Asung Trading Inc.') as wh_to, (select id from public.ref_warehouse where name = 'Asung - Edmonton') as wh_ed \gset
select value as db_role from public.inv_config where key = 'db_role' \gset
-- 도우미가 읽을 기준값(psql 변수는 $$ 본문 안에서 안 바뀐다 — 임시 표로)
create temp table t_base as select :sq_max::bigint as sq_max, :'wh_to'::uuid as wh_to, :'wh_ed'::uuid as wh_ed;
select clock_timestamp() as t_o0 \gset
create temp table t_old as select * from public.shop_stock_payload(null, null);
select clock_timestamp() as t_o1 \gset
drop table t_old;
create temp table t_old as select * from public.shop_stock_payload(null, null);
select clock_timestamp() as t_o2 \gset
select least(extract(epoch from (:'t_o1'::timestamptz - :'t_o0'::timestamptz)), extract(epoch from (:'t_o2'::timestamptz - :'t_o1'::timestamptz)))::numeric(10,3) as old_s, (select count(*) from t_old) as n_old \gset
\echo '── 기준: db_role' :db_role '· open stock q' :sq0 '· payload 옛 전체' :n_old '줄' :old_s 's · 상품' :n_prod0 '· bom' :n_bom0 '(켜짐' :n_bom_act0 ') · listings' :n_list0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
grant insert on t_res to authenticated; grant usage on sequence t_res_n_seq to authenticated;
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 이 시험이 만든 열린 큐 줄(id > 기준 max · 가짜 SKU 만 — 실물 listing 의 diff · nightly 줄은 섞이지 않게) — 「sku:reason:force」 sku 순 · 스토어 하나
create function pg_temp.open_q(p_store uuid) returns text language sql security definer as $$
  select coalesce(string_agg(p.sku || ':' || q.reason || ':' || q.force::text, ',' order by p.sku), '') from public.shop_stock_queue q join public.product p on p.id = q.product_id
   where q.store_id = p_store and q.done_at is null and q.id > (select b.sq_max from t_base b) and p.sku like 'SHOPCOMBO1-%';
$$;
create function pg_temp.close_q() returns void language sql security definer as $$
  update public.shop_stock_queue set started_at = now(), done_at = now(), result = 'ok' where done_at is null and id > (select b.sq_max from t_base b);
$$;
-- 위치별 payload 한 줄 「sku:TO qty:ED qty:is_off」
create function pg_temp.pl(p_store uuid, p_pids uuid[]) returns text language sql as $$
  select coalesce(string_agg(x.sku || ':' || to_q || ':' || ed_q || ':' || off, ',' order by x.sku), '')
    from (select p.sku, max(p.quantity::text) filter (where p.warehouse_id = (select b.wh_to from t_base b)) as to_q, max(p.quantity::text) filter (where p.warehouse_id = (select b.wh_ed from t_base b)) as ed_q, bool_or(p.is_off)::text as off
            from public.shop_stock_payload(p_store, p_pids) p group by p.sku) x;
$$;

-- ═══ A0 객체 · 권한 ═══
select pg_temp.chk('A0a functions 1 each · definer queue_add · trigger fn · payload signature · result shape unchanged',
  (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_stock_payload', 'shop_stock_queue_add', 'shop_stock_queue_trigger')) || '/' ||
  (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_stock_queue_add', 'shop_stock_queue_trigger') and prosecdef) || '/' ||
  (select pg_get_function_identity_arguments(oid) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_stock_payload') || '/' ||
  (select pg_get_function_result(oid) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_stock_payload'),
  '3/2/p_store_id uuid, p_product_ids uuid[]/TABLE(store_id uuid, product_id uuid, sku text, inventory_item_gid text, warehouse_id uuid, location_gid text, quantity numeric, is_off boolean, blocks jsonb)');
select pg_temp.chk('A0b stock triggers 16 · all AFTER STATEMENT · per table (product_bom 3 new)',
  (select count(*)::text from pg_trigger where not tgisinternal and tgname like '%\_shop\_stock\_%') || '/' || (select count(*)::text from pg_trigger where not tgisinternal and tgname like '%\_shop\_stock\_%' and (tgtype & 1) = 0) || '/' ||
  (select string_agg(c.relname || ':' || n, ',' order by c.relname) from (select tgrelid, count(*) n from pg_trigger where not tgisinternal and tgname like '%\_shop\_stock\_%' group by tgrelid) x join pg_class c on c.oid = x.tgrelid),
  '16/16/inv_ledger:3,inv_transfer:1,inv_transfer_line:3,product:1,product_bom:3,shop_listing:2,so_reserve:3');
select pg_temp.chk('A0c product_bom triggers call shop_stock_queue_trigger(product_bom) with transition tables',
  (select string_agg(tgname || ':' || (pg_get_triggerdef(oid) ~ 'REFERENCING' and pg_get_triggerdef(oid) ~ 'shop_stock_queue_trigger\(''product_bom''\)')::text, ',' order by tgname) from pg_trigger where not tgisinternal and tgrelid = 'public.product_bom'::regclass and tgname like 'product\_bom\_shop\_stock\_%'),
  'product_bom_shop_stock_d:true,product_bom_shop_stock_i:true,product_bom_shop_stock_u:true');
select pg_temp.chk('A0d authenticated · anon: no execute on payload · queue_add · trigger fn (revoke kept)',
  (has_function_privilege('authenticated', 'public.shop_stock_payload(uuid, uuid[])', 'execute') or has_function_privilege('authenticated', 'public.shop_stock_queue_add(uuid, uuid[], text, boolean)', 'execute') or has_function_privilege('authenticated', 'public.shop_stock_queue_trigger()', 'execute')
   or has_function_privilege('anon', 'public.shop_stock_payload(uuid, uuid[])', 'execute') or has_function_privilege('anon', 'public.shop_stock_queue_add(uuid, uuid[], text, boolean)', 'execute') or has_function_privilege('anon', 'public.shop_stock_queue_trigger()', 'execute'))::text, 'false');
select pg_temp.chk('A0e the migration itself queued nothing (open stock rows unchanged)', (select count(*)::text from public.shop_stock_queue where done_at is null), :'sq0');

-- ═══ A6 시간 — 새 payload 전체(가짜 재료 넣기 전 · 같은 대상) · 옛의 2 배 안 ═══
select clock_timestamp() as t_n0 \gset
create temp table t_new as select * from public.shop_stock_payload(null, null);
select clock_timestamp() as t_n1 \gset
drop table t_new;
create temp table t_new as select * from public.shop_stock_payload(null, null);
select clock_timestamp() as t_n2 \gset
select least(extract(epoch from (:'t_n1'::timestamptz - :'t_n0'::timestamptz)), extract(epoch from (:'t_n2'::timestamptz - :'t_n1'::timestamptz)))::numeric(10,3) as new_s \gset
\echo '── A6 payload 전체: 옛' :old_s 's → 새' :new_s 's'
select pg_temp.chk('A6 new full payload time ≤ 2 × old (old ' || :'old_s' || 's · new ' || :'new_s' || 's)', (:new_s <= greatest(2 * :old_s, 0.05))::text, 'true');

-- ═══ A1 콤보 아닌 변형은 옛 = 새 — 모든 스토어 payload · 콤보 부모를 빼고 줄마다(product_id · location · quantity · is_off · blocks) ═══
select pg_temp.chk('A1 non-combo rows: old − new = 0 · new − old = 0 · counts equal (' || :'n_old' || ')',
  (select count(*)::text from (select o.store_id, o.product_id, o.warehouse_id, o.location_gid, o.quantity, o.is_off, o.blocks from t_old o where not exists (select 1 from public.product_bom b where b.parent_product_id = o.product_id and b.is_active)
                                except select n.store_id, n.product_id, n.warehouse_id, n.location_gid, n.quantity, n.is_off, n.blocks from t_new n) x) || '/' ||
  (select count(*)::text from (select n.store_id, n.product_id, n.warehouse_id, n.location_gid, n.quantity, n.is_off, n.blocks from t_new n where not exists (select 1 from public.product_bom b where b.parent_product_id = n.product_id and b.is_active)
                                except select o.store_id, o.product_id, o.warehouse_id, o.location_gid, o.quantity, o.is_off, o.blocks from t_old o) x) || '/' ||
  (select count(*)::text from t_new) , '0/0/' || :'n_old');

-- ═══ A2 실물 콤보 전부 — test 스토어에 listing(rollback) → 새 payload quantity = so_lines_available 의 combo 셈을 식으로 흉내(so_available_many · 가짜 SO 없이) ═══
create temp table t_combo as
  select distinct b.parent_product_id as combo_id, p.sku from public.product_bom b join public.product p on p.id = b.parent_product_id where b.is_active;
insert into public.shop_listing (store_id, product_id, is_on, turned_on_at) select :'test_id'::uuid, c.combo_id, true, now() from t_combo c where not exists (select 1 from public.shop_listing l where l.store_id = :'test_id'::uuid and l.product_id = c.combo_id);
select count(*) as n_combo from t_combo \gset
select pg_temp.chk('A2a real combos listed on test (rollback) → listing_on force rows = combos (' || :'n_combo' || ')', (select count(*)::text from public.shop_stock_queue q where q.store_id = :'test_id'::uuid and q.done_at is null and q.id > :sq_max and q.force and q.reason = 'listing_on' and q.product_id in (select combo_id from t_combo)), :'n_combo');
select pg_temp.close_q();
-- SO 셈 흉내: 구성품을 재고 키마다 묶어 need_ea = sum(quantity × pack_factor(낱개 1)) · so_available_many(키들, 창고) · greatest(avail, 0) · min(floor(avail ÷ need))
create temp table t_exp as
  with cmp as (
    select b.parent_product_id as combo_id, coalesce(c.parent_product_id, c.id) as stock_pid, sum(b.quantity * coalesce(c.pack_factor, 1)) as need_ea, bool_and(c.is_active and c.sellable) as comps_on
      from public.product_bom b join public.product c on c.id = b.component_product_id where b.is_active group by 1, 2),
  loc as (select sl.warehouse_id from public.shop_location sl where sl.store_id = :'test_id'::uuid and sl.is_active),
  av as (select loc.warehouse_id, m.stock_pid, greatest(m.available_ea, 0) as available_ea from loc, lateral public.so_available_many((select array_agg(distinct x.stock_pid) from cmp x), loc.warehouse_id) m)
  select cmp.combo_id, loc.warehouse_id,
         case when bool_and(cmp.comps_on) then min(floor(coalesce(a.available_ea, 0) / cmp.need_ea)) else 0 end as want_qty,
         string_agg(sp.sku || '=' || coalesce(a.available_ea, 0)::text || '/' || cmp.need_ea::text, ' ' order by sp.sku) as detail
    from cmp cross join loc
    left join av a on a.warehouse_id = loc.warehouse_id and a.stock_pid = cmp.stock_pid
    join public.product sp on sp.id = cmp.stock_pid
   group by 1, 2;
create temp table t_got as select p.product_id, p.warehouse_id, p.quantity, p.is_off from public.shop_stock_payload(:'test_id'::uuid, null) p where p.product_id in (select combo_id from t_combo);
\echo '── A2 실물 콤보 원문: sku · 창고 · 구성품별 가용/need · SO 셈 · payload'
select c.sku, w.name as warehouse, e.detail as "component=avail/need", e.want_qty as so_calc, g.quantity as payload, (g.quantity = e.want_qty) as same
  from t_exp e join t_combo c on c.combo_id = e.combo_id join public.ref_warehouse w on w.id = e.warehouse_id left join t_got g on g.product_id = e.combo_id and g.warehouse_id = e.warehouse_id order by 1, 2;
select pg_temp.chk('A2b every real combo × location: payload quantity = SO calculation (rows ' || (:n_combo * 2)::text || ') · none missing',
  (select count(*)::text from t_exp e join t_got g on g.product_id = e.combo_id and g.warehouse_id = e.warehouse_id where g.quantity = e.want_qty) || '/' || (select count(*)::text from t_exp) || '/' || (select count(*)::text from t_got),
  (:n_combo * 2)::text || '/' || (:n_combo * 2)::text || '/' || (:n_combo * 2)::text);
select pg_temp.chk('A2c old payload would have sent 0 for every real combo (combo SKU never touches the ledger) · new payload > 0 somewhere',
  (select coalesce(max(o.quantity), 0)::text from t_old o where o.product_id in (select combo_id from t_combo)) || '/' || (select (max(g.quantity) > 0)::text from t_got g), '0/true');
-- 잠금 규칙(10 초): 좁힌 호출은 셋만(키 7 · need 1.000000 · 잔고 남은 콤보) — 17 개 다 부르면 약 4 초
create temp table t_combo3 as select * from t_combo where sku in ('AS-DSPLY', 'TDXCOMBO1', 'UNF18155');
select pg_temp.chk('A2d narrowed call (one combo id each · 3 combos) = full call for those combos (component keys are added to keys[] when narrowed)',
  ((select string_agg(pg_temp.pl(:'test_id'::uuid, array[c.combo_id]), ',' order by c.sku) from t_combo3 c)
   = (select string_agg(x, ',' order by split_part(x, ':', 1)) from unnest(string_to_array(pg_temp.pl(:'test_id'::uuid, null), ',')) x where split_part(x, ':', 1) in (select sku from t_combo3)))::text || '/' || (select count(*)::text from t_combo3), 'true/3');

-- ═══ A3 가짜 재료(위치 둘) ═══
--   낱개 A · B · C · E(sellable false) · F · 세트 C-6(pack 6 · sellable) · 콤보 X = A1 + B2 · Y = A1 + C-6 ×1 · Z = C1 + C-6 ×1(같은 낱개를 낱개 + 세트로 → 키 C need 7) · W = A1 + E1(꺼진 구성품) · U = A1 + F1(F 음수) · V = A1 + B1 · V 자신 sellable false
--   원장: TO A 10 · B 4 · C 13 · F −3 · ED A 0(줄 없음) · B 4 · C 13
insert into public.product (sku, name, source, is_active, sellable) values
  ('SHOPCOMBO1-A', 'shop-combo-1 A', 'manual', true, true), ('SHOPCOMBO1-B', 'shop-combo-1 B', 'manual', true, true), ('SHOPCOMBO1-C', 'shop-combo-1 C', 'manual', true, true),
  ('SHOPCOMBO1-E', 'shop-combo-1 E (off)', 'manual', true, false), ('SHOPCOMBO1-F', 'shop-combo-1 F (negative)', 'manual', true, true),
  ('SHOPCOMBO1-X', 'shop-combo-1 combo X', 'manual', true, true), ('SHOPCOMBO1-Y', 'shop-combo-1 combo Y', 'manual', true, true), ('SHOPCOMBO1-Z', 'shop-combo-1 combo Z', 'manual', true, true),
  ('SHOPCOMBO1-W', 'shop-combo-1 combo W', 'manual', true, true), ('SHOPCOMBO1-U', 'shop-combo-1 combo U', 'manual', true, true), ('SHOPCOMBO1-V', 'shop-combo-1 combo V (off)', 'manual', true, false);
select (select id from public.product where sku = 'SHOPCOMBO1-A') as pa, (select id from public.product where sku = 'SHOPCOMBO1-B') as pb, (select id from public.product where sku = 'SHOPCOMBO1-C') as pc,
       (select id from public.product where sku = 'SHOPCOMBO1-E') as pe, (select id from public.product where sku = 'SHOPCOMBO1-F') as pf,
       (select id from public.product where sku = 'SHOPCOMBO1-X') as px, (select id from public.product where sku = 'SHOPCOMBO1-Y') as py, (select id from public.product where sku = 'SHOPCOMBO1-Z') as pz,
       (select id from public.product where sku = 'SHOPCOMBO1-W') as pw, (select id from public.product where sku = 'SHOPCOMBO1-U') as pu, (select id from public.product where sku = 'SHOPCOMBO1-V') as pv \gset
insert into public.product (sku, name, source, is_active, sellable, parent_product_id, pack_factor) values ('SHOPCOMBO1-C-6', 'shop-combo-1 C set of 6', 'manual', true, true, :'pc'::uuid, 6);
select id as pc6 from public.product where sku = 'SHOPCOMBO1-C-6' \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values
  (public.ims_today(), 1, 'SHOPCOMBO1-A', 'Asung Trading Inc.', 'B061102', 10, 'adjust_existing', 'adjustment', 'SHOPCOMBO1', 'L1', 'manual'),
  (public.ims_today(), 1, 'SHOPCOMBO1-B', 'Asung Trading Inc.', 'B061102', 4,  'adjust_existing', 'adjustment', 'SHOPCOMBO1', 'L2', 'manual'),
  (public.ims_today(), 1, 'SHOPCOMBO1-C', 'Asung Trading Inc.', 'B061102', 13, 'adjust_existing', 'adjustment', 'SHOPCOMBO1', 'L3', 'manual'),
  (public.ims_today(), 1, 'SHOPCOMBO1-F', 'Asung Trading Inc.', 'B061102', -3, 'adjust_existing', 'adjustment', 'SHOPCOMBO1', 'L4', 'manual'),
  (public.ims_today(), 1, 'SHOPCOMBO1-B', 'Asung - Edmonton',   'EU060502', 4,  'adjust_existing', 'adjustment', 'SHOPCOMBO1', 'L5', 'manual'),
  (public.ims_today(), 1, 'SHOPCOMBO1-C', 'Asung - Edmonton',   'EU060502', 13, 'adjust_existing', 'adjustment', 'SHOPCOMBO1', 'L6', 'manual');
-- bom 줄은 직접 insert(창구 product_combo_create 는 낱개 만들기까지 한 덩이라 여기선 표만) — 트리거가 큐에 넣는 것은 A4 에서 센다
insert into public.product_bom (parent_product_id, component_product_id, quantity, source, is_active) values
  (:'px'::uuid, :'pa'::uuid, 1, 'manual', true), (:'px'::uuid, :'pb'::uuid, 2, 'manual', true),
  (:'py'::uuid, :'pa'::uuid, 1, 'manual', true), (:'py'::uuid, :'pc6'::uuid, 1, 'manual', true),
  (:'pz'::uuid, :'pc'::uuid, 1, 'manual', true), (:'pz'::uuid, :'pc6'::uuid, 1, 'manual', true),
  (:'pw'::uuid, :'pa'::uuid, 1, 'manual', true), (:'pw'::uuid, :'pe'::uuid, 1, 'manual', true),
  (:'pu'::uuid, :'pa'::uuid, 1, 'manual', true), (:'pu'::uuid, :'pf'::uuid, 1, 'manual', true),
  (:'pv'::uuid, :'pa'::uuid, 1, 'manual', true), (:'pv'::uuid, :'pb'::uuid, 1, 'manual', true);
select pg_temp.chk('A3a bom insert before any listing → queued 0 (not a target yet)', pg_temp.open_q(:'test_id'::uuid), '');
insert into public.shop_listing (store_id, product_id, is_on, turned_on_at) values
  (:'test_id'::uuid, :'pa'::uuid, true, now()), (:'test_id'::uuid, :'px'::uuid, true, now()), (:'test_id'::uuid, :'py'::uuid, true, now()), (:'test_id'::uuid, :'pz'::uuid, true, now()),
  (:'test_id'::uuid, :'pw'::uuid, true, now()), (:'test_id'::uuid, :'pu'::uuid, true, now()), (:'test_id'::uuid, :'pv'::uuid, true, now());
select pg_temp.chk('A3b listing on (A + 6 combos) → 7 force rows listing_on', pg_temp.open_q(:'test_id'::uuid),
  'SHOPCOMBO1-A:listing_on:true,SHOPCOMBO1-U:listing_on:true,SHOPCOMBO1-V:listing_on:true,SHOPCOMBO1-W:listing_on:true,SHOPCOMBO1-X:listing_on:true,SHOPCOMBO1-Y:listing_on:true,SHOPCOMBO1-Z:listing_on:true');
select pg_temp.close_q();
select pg_temp.chk('A3c X = A1 + B2 → TO min(10, ⌊4/2⌋) = 2 · ED A 0 (no ledger row) → 0 · is_off false', pg_temp.pl(:'test_id'::uuid, array[:'px'::uuid]), 'SHOPCOMBO1-X:2:0:false');
select pg_temp.chk('A3d Y = A1 + C-6 ×1 (set → key C need 6) → TO min(10, ⌊13/6⌋) = 2 · ED 0', pg_temp.pl(:'test_id'::uuid, array[:'py'::uuid]), 'SHOPCOMBO1-Y:2:0:false');
select pg_temp.chk('A3e Z = C1 + C-6 ×1 (same single as single + set → one key C need 7) → ⌊13/7⌋ = 1 both', pg_temp.pl(:'test_id'::uuid, array[:'pz'::uuid]), 'SHOPCOMBO1-Z:1:1:false');
select pg_temp.chk('A3f W = A1 + E1 (E sellable false) → 0 both · is_off false (combo itself on)', pg_temp.pl(:'test_id'::uuid, array[:'pw'::uuid]), 'SHOPCOMBO1-W:0:0:false');
select pg_temp.chk('A3g U = A1 + F1 (F −3) → 0 both (negative never divides into a count)', pg_temp.pl(:'test_id'::uuid, array[:'pu'::uuid]), 'SHOPCOMBO1-U:0:0:false');
select pg_temp.chk('A3h V (combo itself sellable false) → 0 · is_off true', pg_temp.pl(:'test_id'::uuid, array[:'pv'::uuid]), 'SHOPCOMBO1-V:0:0:true');
select pg_temp.chk('A3i single A listed → its own 10 / 0 (single branch untouched)', pg_temp.pl(:'test_id'::uuid, array[:'pa'::uuid]), 'SHOPCOMBO1-A:10:0:false');
select pg_temp.chk('A3j full call (null ids) gives the same six combo lines', (pg_temp.pl(:'test_id'::uuid, null) ~ 'SHOPCOMBO1-U:0:0:false,SHOPCOMBO1-V:0:0:true,SHOPCOMBO1-W:0:0:false,SHOPCOMBO1-X:2:0:false,SHOPCOMBO1-Y:2:0:false,SHOPCOMBO1-Z:1:1:false')::text, 'true');
select pg_temp.chk('A3k whole payload min ≥ 0 (every store)', (select (min(quantity) >= 0)::text from public.shop_stock_payload(null, null)), 'true');

-- ═══ A4 큐 ═══
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values
  (public.ims_today(), 1, 'SHOPCOMBO1-A', 'Asung Trading Inc.', 'B061102', 0, 'adjust_existing', 'adjustment', 'SHOPCOMBO1', 'L7', 'manual');
select pg_temp.chk('A4a ledger row for component A → A itself + every listed combo using A (U V W X Y) · reason inv_ledger · force false · Z (no A) not', pg_temp.open_q(:'test_id'::uuid),
  'SHOPCOMBO1-A:inv_ledger:false,SHOPCOMBO1-U:inv_ledger:false,SHOPCOMBO1-V:inv_ledger:false,SHOPCOMBO1-W:inv_ledger:false,SHOPCOMBO1-X:inv_ledger:false,SHOPCOMBO1-Y:inv_ledger:false');
select pg_temp.close_q();
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values
  (public.ims_today(), 1, 'SHOPCOMBO1-C', 'Asung - Edmonton', 'EU060502', 0, 'adjust_existing', 'adjustment', 'SHOPCOMBO1', 'L8', 'manual');
select pg_temp.chk('A4b ledger row for C (not listed) → combos using C or its set C-6: Y (via set) · Z (single + set) · nothing else', pg_temp.open_q(:'test_id'::uuid), 'SHOPCOMBO1-Y:inv_ledger:false,SHOPCOMBO1-Z:inv_ledger:false');
select pg_temp.close_q();
savepoint a4c;
update public.product set sellable = false where id = :'pc6'::uuid;
select pg_temp.open_q(:'test_id'::uuid) || '|' || pg_temp.pl(:'test_id'::uuid, array[:'py'::uuid, :'pz'::uuid]) as a4c \gset
rollback to savepoint a4c;
select pg_temp.chk('A4c set C-6 sellable off (product trigger) → Y · Z queued (reason product) · their quantity 0 (component off) · is_off false', :'a4c',
  'SHOPCOMBO1-Y:product:false,SHOPCOMBO1-Z:product:false|SHOPCOMBO1-Y:0:0:false,SHOPCOMBO1-Z:0:0:false');
select pg_temp.chk('A4d after rollback to savepoint: queue back to none · Y Z back to 2/0 · 1/1', pg_temp.open_q(:'test_id'::uuid) || '|' || pg_temp.pl(:'test_id'::uuid, array[:'py'::uuid, :'pz'::uuid]), '|SHOPCOMBO1-Y:2:0:false,SHOPCOMBO1-Z:1:1:false');
update public.product_bom set note = 'touch' where parent_product_id = :'px'::uuid;
select pg_temp.chk('A4e note-only bom update → 0 rows (filter on parent · component · quantity · is_active)', pg_temp.open_q(:'test_id'::uuid), '');
update public.product_bom set quantity = 3 where parent_product_id = :'px'::uuid and component_product_id = :'pb'::uuid;
select pg_temp.chk('A4f bom quantity B 2 → 3 → X force (reason product_bom) · X TO = min(10, ⌊4/3⌋) = 1', pg_temp.open_q(:'test_id'::uuid) || '|' || pg_temp.pl(:'test_id'::uuid, array[:'px'::uuid]), 'SHOPCOMBO1-X:product_bom:true|SHOPCOMBO1-X:1:0:false');
select pg_temp.close_q();
insert into public.product_bom (parent_product_id, component_product_id, quantity, source, is_active) values (:'px'::uuid, :'pc'::uuid, 20, 'manual', true);
select pg_temp.chk('A4g bom line added (X + C20) → X force · X TO = min(10, 1, ⌊13/20⌋) = 0', pg_temp.open_q(:'test_id'::uuid) || '|' || pg_temp.pl(:'test_id'::uuid, array[:'px'::uuid]), 'SHOPCOMBO1-X:product_bom:true|SHOPCOMBO1-X:0:0:false');
select pg_temp.close_q();
delete from public.product_bom where parent_product_id = :'px'::uuid and component_product_id = :'pc'::uuid;
select pg_temp.chk('A4h bom line deleted → X force · back to 1/0', pg_temp.open_q(:'test_id'::uuid) || '|' || pg_temp.pl(:'test_id'::uuid, array[:'px'::uuid]), 'SHOPCOMBO1-X:product_bom:true|SHOPCOMBO1-X:1:0:false');
select pg_temp.close_q();
-- Release 는 창구 product_bom_set(빈 목록)로 — 가짜 직원(master) · authenticated
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'shopcombo1-w@test.invalid', 'SHOPCOMBO1 master write', 'manager', '["ims","master"]', '{}');
select auth_user_id::text as uid from public.ims_staff where email = 'shopcombo1-w@test.invalid' \gset
select set_config('request.jwt.claims', json_build_object('sub', :'uid', 'role', 'authenticated')::text, true) \gset
set local role authenticated;
select pg_temp.run($q$select public.product_bom_set('SHOPCOMBO1-X', '[]'::jsonb, '[{"sku":"SHOPCOMBO1-A","qty":1},{"sku":"SHOPCOMBO1-B","qty":3}]'::jsonb, true, '{}')::text$q$) as r_rel \gset
reset role;
select pg_temp.chk('A4i Release via product_bom_set(empty list) committed · rows turned off (not deleted)', case when :'r_rel' like 'ERR%' then :'r_rel' else (:'r_rel'::jsonb->>'committed') || ' ' || (:'r_rel'::jsonb->>'removed') end || '/' || (select count(*)::text || ':' || count(*) filter (where is_active)::text from public.product_bom where parent_product_id = :'px'::uuid), 'true 2/2:0');
select pg_temp.chk('A4j Release → X force (product_bom) · X is no longer a combo → single branch · its own stock 0/0', pg_temp.open_q(:'test_id'::uuid) || '|' || pg_temp.pl(:'test_id'::uuid, array[:'px'::uuid]), 'SHOPCOMBO1-X:product_bom:true|SHOPCOMBO1-X:0:0:false');
select pg_temp.close_q();
select pg_temp.chk('A4k live-off stores (asung · aone) got 0 rows from everything above', (select count(*)::text from public.shop_stock_queue q where q.id > :sq_max and q.store_id in (:'asung_id'::uuid, :'aone_id'::uuid)), '0');
select pg_temp.chk('A4l shop_stock_targets(test) includes the listed combos · queue_add(null, [A]) alone reaches U V W Y (X released · Z no A) = 4 + A = 5',
  (select count(*)::text from public.shop_stock_targets(:'test_id'::uuid, null) t where t.product_id in (:'px'::uuid, :'py'::uuid, :'pz'::uuid, :'pw'::uuid, :'pu'::uuid, :'pv'::uuid)) || '/' || public.shop_stock_queue_add(null, array[:'pa'::uuid], 'test', false)::text || '/' || pg_temp.open_q(:'test_id'::uuid),
  '6/5/SHOPCOMBO1-A:test:false,SHOPCOMBO1-U:test:false,SHOPCOMBO1-V:test:false,SHOPCOMBO1-W:test:false,SHOPCOMBO1-Y:test:false');
select pg_temp.close_q();

-- ═══ A5 shop_stock_queue_diff(test) — 콤보 변형이 「다름」 으로 잡히는지(sent 없음 → 다름 · sent 같음 → 안 잡힘) · 숫자만 · 큐는 rollback ═══
insert into public.shop_variant (store_id, product_id, shopify_variant_gid, inventory_item_gid) values (:'test_id'::uuid, :'py'::uuid, 'gid://shopify/ProductVariant/990000001', 'gid://shopify/InventoryItem/990000001');
select public.shop_stock_queue_diff(:'test_id'::uuid) as n_diff1 \gset
select pg_temp.chk('A5a diff(test): combo Y (inventory item · never sent) is queued as diff · other fake combos have no inventory item → not queued', (:n_diff1 >= 1)::text || '/' || pg_temp.open_q(:'test_id'::uuid), 'true/SHOPCOMBO1-Y:diff:false');
select pg_temp.close_q();
insert into public.shop_stock_sent (store_id, product_id, warehouse_id, quantity, last_status) values (:'test_id'::uuid, :'py'::uuid, :'wh_to'::uuid, 2, 'ok'), (:'test_id'::uuid, :'py'::uuid, :'wh_ed'::uuid, 0, 'ok');
select public.shop_stock_queue_diff(:'test_id'::uuid) as n_diff2 \gset
select pg_temp.chk('A5b sent = 2 / 0 (the combo numbers) → diff no longer queues Y', (pg_temp.open_q(:'test_id'::uuid) !~ 'SHOPCOMBO1-Y')::text, 'true');
select pg_temp.close_q();
update public.shop_stock_sent set quantity = 0 where product_id = :'py'::uuid and warehouse_id = :'wh_to'::uuid;
select public.shop_stock_queue_diff(:'test_id'::uuid) as n_diff3 \gset
select pg_temp.chk('A5c sent 0 at Toronto (what the old payload sent) → diff queues Y again', (pg_temp.open_q(:'test_id'::uuid) ~ 'SHOPCOMBO1-Y:diff:false')::text, 'true');
select pg_temp.close_q();
select public.shop_stock_queue_all(:'test_id'::uuid) as n_all \gset
select pg_temp.chk('A5d shop_stock_queue_all(test) force-queues the listed combos too (called in the statement before — same-statement subqueries do not see its rows)', (:n_all > 0)::text || '/' || (select count(*)::text from public.shop_stock_queue q where q.id > :sq_max and q.done_at is null and q.force and q.product_id in (:'py'::uuid, :'pz'::uuid, :'pw'::uuid, :'pu'::uuid, :'pv'::uuid)), 'true/5');
select pg_temp.close_q();

-- ── 결과 ──
select clock_timestamp() as t_end \gset
select n, case when ok then 'OK  ' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok_n, count(*) filter (where not ok) as bad_n, count(*) as total from t_res \gset
\echo '── OK' :ok_n '/ ' :total '(expect' :EXPECT_OK ') · MISMATCH' :bad_n '· begin~end' :t_begin '→' :t_end
rollback;
select (select count(*) from public.product) as n_prod1, (select count(*) from public.product_bom) as n_bom1, (select count(*) from public.product_bom where is_active) as n_bom_act1,
       (select count(*) from public.shop_listing) as n_list1, (select count(*) from public.ims_staff) as n_staff1, (select count(*) from public.inv_ledger) as n_led1,
       (select count(*) from public.shop_variant) as n_var1, (select count(*) from public.shop_stock_sent) as n_sent1, (select count(*) from public.shop_stock_queue where done_at is null) as sq1 \gset
\echo '── rollback 뒤 실제 행: product' :n_prod0 '→' :n_prod1 '· bom' :n_bom0 '→' :n_bom1 '(켜짐' :n_bom_act0 '→' :n_bom_act1 ') · listings' :n_list0 '→' :n_list1 '· staff' :n_staff0 '→' :n_staff1 '· ledger' :n_led0 '→' :n_led1 '· variants' :n_var0 '→' :n_var1 '· sent' :n_sent0 '→' :n_sent1 '· open stock q' :sq0 '→' :sq1
