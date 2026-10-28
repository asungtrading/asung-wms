-- supabase/tests/fc_1b3_check.sql — fc-1b3 운송사 이름 여럿(판정 847) · LTL 운송사(846) 검증 (2026-10-28)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — begin → (-v mig 면 \i) → ⭐ fc_1b2_check 사본(106 = fc_1a 76 + fc_1b 23 + fc_1b2 7 · 가짜 재료 · 도우미 이어 씀 · fc_1a_check 의 F6 · 12g · 재료 줄은 이름 표 꼴로 고쳤다) → D 갈래 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028173935_fc_1b3_carrier_fc_names.sql -f supabase/tests/fc_1b3_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험 · 확인 둘 다 **119** = 106 + 13 (시험 전용 줄 없음) · Z1 은 t_res 밖
--   fixtures: 팔렛 견적 응답 원문(supabase/functions/freightcom/fixtures/rate-pallet-tailgate-false-true.json · False 갈래)을 \set 백틱으로 읽어 fc_quote_save 에 넣는다
\set ON_ERROR_STOP on
\set EXPECT_OK 119
\pset pager off
\! awk 'BEGIN{skip=0;done=0} /^\\if :\{\?mig\}/{skip=1;next} /^\\endif/{if(skip){skip=0;next}} /^-- ── 결과 ──/{done=1} done{next} skip{next} /^begin;$/{next} /^set local lock_timeout/{next} /^\\set EXPECT_OK/{next} {print}' supabase/tests/fc_1b2_check.sql > /tmp/fc_1b2-inner.sql
\set palfix `cat supabase/functions/freightcom/fixtures/rate-pallet-tailgate-false-true.json`
-- Z1 기준은 사본들이 안에서 다시 받는 n_*0 과 이름을 달리한다(z_ 접두 — 사본의 기준이 마이그레이션 뒤 값(운송사 15)으로 덮어 Z1 이 틀렸다 · 2회차)
select (select count(*) from public.so) as z_so, (select count(*) from public.customer_address) as z_addr, (select count(*) from public.fc_shipment) as z_fc, (select count(*) from public.fc_quote) as z_q, (select count(*) from public.ims_staff) as z_staff, (select count(*) from public.ref_carrier) as z_car, (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname = 'ref_carrier_fc_name') as z_name \gset
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
\echo '── fc_1b2_check 속(사본 · 106)'
\i /tmp/fc_1b2-inner.sql
select count(*) as n_1b2 from t_res \gset
\echo '── fc-1b2 inner done: rows' :n_1b2

-- ── D 847 이름 표 · 옛 칸 · 옮긴 값 · 새 운송사 ──
select pg_temp.chk('D1 old column · old index gone · name table with unique(name_norm) · no function reads freightcom_carrier',
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'ref_carrier' and column_name = 'freightcom_carrier')::text || '/' || (to_regclass('public.ref_carrier_freightcom_uq') is null)::text || '/' ||
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'ref_carrier_fc_name_uk') || '/' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prosrc like '%freightcom_carrier%'), '0/true/UNIQUE (name_norm)/0');
select pg_temp.chk('D2 migrated names: UPS · Purolator · Canada Post on their carriers · 12 carriers · ≥ 14 names · seven new LTL carriers kind carrier · shopify_company null',
  (select string_agg(c.name || '=' || n.name, ',' order by c.name) from public.ref_carrier_fc_name n join public.ref_carrier c on c.id = n.carrier_id where c.name in ('UPS', 'Purolator', 'Canada Post')) || '/' ||
  (select count(*) from public.ref_carrier c where c.name in ('UPS', 'Purolator', 'Canada Post', 'FedEx', 'Canpar', 'Purolator Freight', 'Vitran', 'Apex', 'Kindersley', 'WCE', 'Fastfrate', 'Maritime') and c.kind = 'carrier') || '/' ||
  (select (count(*) >= 14)::text from public.ref_carrier_fc_name) || '/' || (select count(*) from public.ref_carrier c where c.name in ('Purolator Freight', 'Vitran', 'Apex', 'Kindersley', 'WCE', 'Fastfrate', 'Maritime') and c.shopify_company is null and c.is_active),
  'Canada Post=Canada Post,Purolator=Purolator,UPS=UPS/12/true/7');
select pg_temp.chk('D3 Kindersley has two names · Maritime two · Apex = Apex Motor Express · FedEx = FedEx Courier (짐작) · Canpar = Canpar (짐작)',
  (select string_agg(c.name || '=' || n.name, ',' order by c.name, n.name) from public.ref_carrier_fc_name n join public.ref_carrier c on c.id = n.carrier_id where c.name in ('Kindersley', 'Maritime', 'Apex', 'FedEx', 'Canpar')),
  'Apex=Apex Motor Express,Canpar=Canpar,FedEx=FedEx Courier,Kindersley=Kindersley,Kindersley=Kindersley Transport,Maritime=Maritime,Maritime=Maritime-Ontario');
select pg_temp.as_user(:'u_off');
select (public.ref_carrier_fc_names_set(:'car_a'::uuid, array['Fcx Alpha', ' Fcx Alpha Express ', 'Fcx Alpha LTL', '']))->'names' as d4 \gset
select pg_temp.chk('D4 window (master): three names on FCX Alpha · trimmed · blank dropped · returned sorted · rows = 3', :'d4' || '/' || (select count(*) from public.ref_carrier_fc_name n where n.carrier_id = :'car_a'::uuid), '["Fcx Alpha", "Fcx Alpha Express", "Fcx Alpha LTL"]/3');
select pg_temp.chk('D5 same name twice (case differs) → refused', (pg_temp.try(format('select public.ref_carrier_fc_names_set(%L, array[''Fcx X'', ''FCX X''])::text', :'car_a')) like 'ERR P0001: The same name is given twice (case differs) — nothing was saved')::text, 'true');
select pg_temp.chk('D6 a name that belongs to another carrier → refused naming both', (pg_temp.try(format('select public.ref_carrier_fc_names_set(%L, array[''Fcx Beta'', ''fcx alpha ltl''])::text', :'car_b')) like 'ERR P0001: Name(s) already belong to another carrier: Fcx Alpha LTL → FCX Alpha Carrier — a Freightcom name maps to one carrier — nothing was saved')::text, 'true');
select pg_temp.chk('D7 set again with one name → the other two rows are removed · D6 left Beta unchanged (1 name)', ((public.ref_carrier_fc_names_set(:'car_a'::uuid, array['Fcx Alpha']))->'names')::text || '/' || (select count(*) from public.ref_carrier_fc_name n where n.carrier_id = :'car_b'::uuid), '["Fcx Alpha"]/1');
select pg_temp.chk('D8 pickup kind refused · unknown carrier refused', (pg_temp.try('select public.ref_carrier_fc_names_set((select id from public.ref_carrier where kind = ''pickup'' limit 1), array[''x''])::text') like 'ERR P0001: Only a carrier (not Pickup · Delivery) can have Freightcom names%')::text || '/' || (pg_temp.try('select public.ref_carrier_fc_names_set(gen_random_uuid(), array[''x''])::text') like 'ERR P0001: Carrier % not found — nothing was saved')::text, 'true/true');
select pg_temp.as_user(:'u_wms');
select pg_temp.chk('D9 warehouse worker (no master) cannot set names', (pg_temp.try(format('select public.ref_carrier_fc_names_set(%L, array[''x''])::text', :'car_a')) like 'ERR P0001: You cannot change master data — ask an admin to add the ''master'' permission%')::text, 'true');
select pg_temp.as_user(:'u_off');
select pg_temp.chk('D10 prepare.carriers = every name of every active carrier (count matches the table) · has Kindersley Transport and Fcx Alpha',
  (select (jsonb_array_length(o->'carriers') = (select count(*) from public.ref_carrier_fc_name n join public.ref_carrier c on c.id = n.carrier_id where c.is_active))::text || '/' || (o->'carriers' ? 'Kindersley Transport')::text || '/' || (o->'carriers' ? 'Fcx Alpha')::text
     from (select pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s1'))::jsonb as o) t), 'true/true/true');
-- 팔렛 응답 원문(fixtures · False 갈래) → fc_quote_save: Maritime · fastfrate · Vitran · WCE · Purolator Freight 가 짝 · CCT · CSA · Day & Ross · FedEx Freight · GLS · TST 는 null(846 표식)
select public.fc_shipment_prepare(array[:'s4'::uuid], '{}'::jsonb, true) as p4 \gset
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_quote_save((:'p4'::jsonb->>'shipment_id')::uuid, 'req-pal', :'palfix'::jsonb->'False') as q4 \gset
select pg_temp.as_user(:'u_off');
select pg_temp.chk('D11 pallet fixture → 15 rates · paired (carrier_id) = fastfrate.standard,maritime.dry,purolatorfreight.standard,vitran.maxx,vitran.regular,wce.standard · 9 unpaired',
  (:'q4'::jsonb->>'rates') || '/' || (select string_agg(r.service_id, ',' order by r.service_id) from public.fc_quote_rate r where r.quote_id = (:'q4'::jsonb->>'quote_id')::uuid and r.carrier_id is not null) || '/' || (select count(*) from public.fc_quote_rate r where r.quote_id = (:'q4'::jsonb->>'quote_id')::uuid and r.carrier_id is null),
  '15/fastfrate.standard,maritime.dry,purolatorfreight.standard,vitran.maxx,vitran.regular,wce.standard/9');
select pg_temp.chk('D12 paired lines land on the right IMS carriers (lowercase fastfrate → Fastfrate) · preselected is a paired line · an unpaired CCT line cannot be selected (846 marker)',
  (select string_agg(distinct c.name, ',') from public.fc_quote_rate r join public.ref_carrier c on c.id = r.carrier_id where r.quote_id = (:'q4'::jsonb->>'quote_id')::uuid) || '/' ||
  (select (r.carrier_id is not null)::text from public.fc_quote_rate r where r.quote_id = (:'q4'::jsonb->>'quote_id')::uuid and r.preselected) || '/' ||
  (pg_temp.try(format('select public.fc_quote_select(%L, (select id from public.fc_quote_rate where quote_id = %L and service_id = ''cct.expedited''))::text', :'p4'::jsonb->>'shipment_id', :'q4'::jsonb->>'quote_id')) like 'ERR P0001: Carrier "CCT" is not on the IMS carrier list — add it in Settings%')::text,
  'Fastfrate,Maritime,Purolator Freight,Vitran,WCE/true/true');
select pg_temp.chk('D13 so_finalize untouched', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize'), :'fin_md5_0');

-- ── 결과 ──
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res where n > :n_1b2 or not ok order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok, :n_1b2 as from_fc_1b2 from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :z_so and (select count(*) from public.customer_address) = :z_addr and (select count(*) from public.fc_shipment) = :z_fc and (select count(*) from public.fc_quote) = :z_q and (select count(*) from public.ims_staff) = :z_staff and (select count(*) from public.ref_carrier) = :z_car and (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname = 'ref_carrier_fc_name') = :z_name
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
