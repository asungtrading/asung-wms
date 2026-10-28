-- supabase/tests/fc_1b4_check.sql — fc-1b4 창고마다 Freightcom 계정(판정 848) 검증 (2026-10-28)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — begin → (-v mig 면 \i) → ⭐ fc_1b3_check 사본(119 = 1a 76 + 1b 23 + 1b2 7 + 1b3 13 · 가짜 창고에 계정 FCX · FCX2 를 줬다) → E 갈래 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028180558_fc_1b4_warehouse_account.sql -f supabase/tests/fc_1b4_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험 · 확인 둘 다 **127** = 119 + 8 (시험 전용 줄 없음) · Z1 은 t_res 밖(z_ 접두 · 사본의 기준에 안 덮인다)
\set ON_ERROR_STOP on
\set EXPECT_OK 127
\pset pager off
\! awk 'BEGIN{skip=0;done=0} /^\\if :\{\?mig\}/{skip=1;next} /^\\endif/{if(skip){skip=0;next}} /^-- ── 결과 ──/{done=1} done{next} skip{next} /^begin;$/{next} /^set local lock_timeout/{next} /^\\set EXPECT_OK/{next} {print}' supabase/tests/fc_1b3_check.sql > /tmp/fc_1b3-inner.sql
select (select count(*) from public.so) as z_so, (select count(*) from public.customer_address) as z_addr, (select count(*) from public.fc_shipment) as z_fc, (select count(*) from public.fc_quote) as z_q, (select count(*) from public.ims_staff) as z_staff, (select count(*) from public.ref_carrier) as z_car, (select count(*) from public.ref_warehouse) as z_wh \gset
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
\echo '── fc_1b3_check 속(사본 · 119)'
\i /tmp/fc_1b3-inner.sql
select count(*) as n_1b3 from t_res \gset
\echo '── fc-1b3 inner done: rows' :n_1b3

-- ── E 848 ──
select pg_temp.chk('E1 columns: ref_warehouse.freightcom_account(CHECK) · fc_shipment.freightcom_account · fc_call_log.account', (select count(*) from information_schema.columns where table_schema = 'public' and ((table_name = 'ref_warehouse' and column_name = 'freightcom_account') or (table_name = 'fc_shipment' and column_name = 'freightcom_account') or (table_name = 'fc_call_log' and column_name = 'account')))::text || '/' || (select pg_get_constraintdef(oid) from pg_constraint where conname = 'ref_warehouse_fc_account_ck'), '3/CHECK (((freightcom_account IS NULL) OR (freightcom_account ~ ''^[A-Z0-9]{2,10}$''::text)))');
select pg_temp.chk('E2 CHECK: lower-case · too long · one char refused · null allowed · two warehouses may share one account (no unique)',
  (pg_temp.try(format('update public.ref_warehouse set freightcom_account = ''tor'' where id = %L returning name', :'wh')) like 'ERR 23514:%')::text || '/' || (pg_temp.try(format('update public.ref_warehouse set freightcom_account = ''ABCDEFGHIJK'' where id = %L returning name', :'wh')) like 'ERR 23514:%')::text || '/' || (pg_temp.try(format('update public.ref_warehouse set freightcom_account = ''T'' where id = %L returning name', :'wh')) like 'ERR 23514:%')::text || '/' ||
  pg_temp.try(format('update public.ref_warehouse set freightcom_account = null where id = %L returning coalesce(freightcom_account, ''(null)'')', :'wh2')) || '/' || pg_temp.try(format('update public.ref_warehouse set freightcom_account = ''FCX'' where id = %L returning freightcom_account', :'wh2')), 'true/true/true/(null)/FCX');
select pg_temp.as_user(:'u_off');
select public.fc_shipment_prepare(array[:'s1'::uuid], '{}'::jsonb, false) as e3 \gset
select pg_temp.chk('E3 prepare returns the warehouse account (FCX) · the live shipment of S1 carries the snapshot · for_so shows it', (:'e3'::jsonb->>'freightcom_account') || '/' || (select f.freightcom_account from public.fc_shipment_so l join public.fc_shipment f on f.id = l.shipment_id where l.so_id = :'s1'::uuid and l.live) || '/' || ((public.fc_shipment_for_so(:'s1'::uuid))#>>'{shipment,freightcom_account}'), 'FCX/FCX/FCX');
set local session_replication_role = replica;
update public.ref_warehouse set freightcom_account = null where id = :'wh2'::uuid;
set local session_replication_role = origin;
select pg_temp.chk('E4 warehouse without an account → prepare refused with the Settings sentence · nothing saved', (pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', true)::text', :'s11')) like 'ERR P0001: Warehouse FCX Warehouse 2 has no Freightcom account — set it under Settings → Warehouses (e.g. TOR) — nothing was saved')::text || '/' || (select count(*) from public.fc_shipment_so l where l.so_id = :'s11'::uuid), 'true/0');
set local session_replication_role = replica;
update public.ref_warehouse set freightcom_account = 'FCX9' where id = :'wh'::uuid;
set local session_replication_role = origin;
select public.fc_shipment_prepare(array[:'s1'::uuid], '{}'::jsonb, true) as e5 \gset
select pg_temp.chk('E5 replace (same set · warehouse account changed to FCX9) → snapshot follows the warehouse', (:'e5'::jsonb->>'action') || '/' || (select f.freightcom_account from public.fc_shipment f where f.id = (:'e5'::jsonb->>'shipment_id')::uuid), 'replace/FCX9');
select public.fc_shipment_prepare(array[:'s1'::uuid, :'s2'::uuid], '{}'::jsonb, true) as e6 \gset
select pg_temp.chk('E6 new shipment (supersede · S1 + S2) carries FCX9 too · superseded one keeps its old snapshot', (:'e6'::jsonb->>'action') || '/' || (select f.freightcom_account from public.fc_shipment f where f.id = (:'e6'::jsonb->>'shipment_id')::uuid) || '/' || (select f.freightcom_account from public.fc_shipment f where f.id = (:'e5'::jsonb->>'shipment_id')::uuid), 'supersede/FCX9/FCX9');
select pg_temp.chk('E7 old shipments (before fc-1b4) may have null account · real rows unchanged by this test (count of null = count before + 0 of ours)', (select count(*) from public.fc_shipment f where f.freightcom_account is null and f.charge_so_id in (select id from public.so where so_number like 'SO-79900%'))::text, '0');
select pg_temp.chk('E8 so_finalize untouched', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize'), :'fin_md5_0');

-- ── 결과 ──
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res where n > :n_1b3 or not ok order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok, :n_1b3 as from_fc_1b3 from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :z_so and (select count(*) from public.customer_address) = :z_addr and (select count(*) from public.fc_shipment) = :z_fc and (select count(*) from public.fc_quote) = :z_q and (select count(*) from public.ims_staff) = :z_staff and (select count(*) from public.ref_carrier) = :z_car and (select count(*) from public.ref_warehouse) = :z_wh
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
