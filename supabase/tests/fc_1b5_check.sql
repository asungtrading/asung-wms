-- supabase/tests/fc_1b5_check.sql — fc-1b5 테일게이트 · 인사이드는 팔렛 발송에만(판정 850) · 849 말만 검증 (2026-10-28)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — begin → (-v mig 면 \i) → ⭐ fc_1b4_check 사본(127 = 1a 76 + 1b 23 + 1b2 7 + 1b3 13 + 1b4 8 · 1a 4c · 4d · 1b B2 · B14 는 상자 재료라 850 기대로 고쳤다) → F 갈래 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028192341_fc_1b5_tailgate_pallet_only.sql -f supabase/tests/fc_1b5_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험 · 확인 둘 다 **137** = 127 + 10 (시험 전용 줄 없음) · Z1 은 t_res 밖(y_ 접두 · 사본의 z_ · n_*0 기준에 안 덮인다)
--   재료: 사본이 만든 가짜(FCX) — addr_a(100 Fcx Street · c_a) · S1 · S2 = 상자 · S4 = 팔렛(안에 상자 둘) · 셋 다 같은 주소 · u_off(sales · master) · u_wms(창고)
\set ON_ERROR_STOP on
\set EXPECT_OK 137
\pset pager off
\! awk 'BEGIN{skip=0;done=0} /^\\if :\{\?mig\}/{skip=1;next} /^\\endif/{if(skip){skip=0;next}} /^-- ── 결과 ──/{done=1} done{next} skip{next} /^begin;$/{next} /^set local lock_timeout/{next} /^\\set EXPECT_OK/{next} {print}' supabase/tests/fc_1b4_check.sql > /tmp/fc_1b4-inner.sql
select (select count(*) from public.so) as y_so, (select count(*) from public.customer_address) as y_addr, (select count(*) from public.fc_shipment) as y_fc, (select count(*) from public.fc_quote) as y_q, (select count(*) from public.ims_staff) as y_staff, (select count(*) from public.ref_carrier) as y_car, (select count(*) from public.ref_warehouse) as y_wh \gset
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
\echo '── fc_1b4_check 속(사본 · 127)'
\i /tmp/fc_1b4-inner.sql
select count(*) as n_1b4 from t_res \gset
\echo '── fc-1b4 inner done: rows' :n_1b4

-- ── F 850 재료: addr_a 를 residential false · tailgate true · threshold true 로(가짜 주소 · replica 로 트리거 없이) ──
set local session_replication_role = replica;
update public.customer_address set residential = false, tailgate_required = true, threshold_delivery = true where id = :'addr_a'::uuid;
set local session_replication_role = origin;
select pg_temp.as_user(:'u_off');
select public.fc_shipment_prepare(array[:'s1'::uuid], '{}'::jsonb, false) as f1 \gset
select pg_temp.chk('F1 box preview (S1 · address remembers tailgate true · threshold true) → payload destination has no tailgate_required · residential kept · no pallet_service_details · package · options tailgate · threshold = null (keys present)',
  ((:'f1'::jsonb#>'{request,details,destination}') ? 'tailgate_required')::text || '/' || (:'f1'::jsonb#>>'{request,details,destination,residential}') || '/' || ((:'f1'::jsonb#>'{request,details,packaging_properties}') ? 'pallet_service_details')::text || '/' || (:'f1'::jsonb->>'packaging_type') || '/' ||
  (:'f1'::jsonb->'options' ? 'tailgate_required')::text || '/' || coalesce(:'f1'::jsonb#>>'{options,tailgate_required}', '(null)') || '/' || (:'f1'::jsonb->'options' ? 'threshold_delivery')::text || '/' || coalesce(:'f1'::jsonb#>>'{options,threshold_delivery}', '(null)'),
  'false/false/false/package/true/(null)/true/(null)');
select public.fc_shipment_prepare(array[:'s4'::uuid], '{}'::jsonb, false) as f2 \gset
select pg_temp.chk('F2 pallet preview (S4 · same address) → destination tailgate_required true · pallet_service_details.threshold_delivery true · options true/true · pallet (rule unchanged)',
  (:'f2'::jsonb#>>'{request,details,destination,tailgate_required}') || '/' || (:'f2'::jsonb#>>'{request,details,packaging_properties,pallet_service_details,threshold_delivery}') || '/' || (:'f2'::jsonb#>>'{options,tailgate_required}') || '/' || (:'f2'::jsonb#>>'{options,threshold_delivery}') || '/' || (:'f2'::jsonb->>'packaging_type'), 'true/true/true/true/pallet');
select pg_temp.chk('F3 box with explicit p_options tailgate true · threshold true (old screen) → not refused · ignored (payload without the key · options null · residential from options still honoured)',
  (select ((o#>'{request,details,destination}') ? 'tailgate_required')::text || '/' || coalesce(o#>>'{options,tailgate_required}', '(null)') || '/' || coalesce(o#>>'{options,threshold_delivery}', '(null)') || '/' || (o#>>'{options,residential}') || '/' || (o#>>'{request,details,destination,residential}')
     from (select pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{"tailgate_required": true, "threshold_delivery": true, "residential": true}'', false)::text', :'s1'))::jsonb as o) t), 'false/(null)/(null)/true/true');
select public.fc_shipment_prepare(array[:'s1'::uuid], '{"residential": true, "tailgate_required": false, "threshold_delivery": false, "remember": true}'::jsonb, true) as f4 \gset
select pg_temp.chk('F4 box remember (office · address matched · hidden checks sent as false) → residential written · tailgate · threshold stay true · no review · no warning · row options tailgate · threshold = JSON null · residential true',
  (select a.residential::text || '/' || a.tailgate_required::text || '/' || a.threshold_delivery::text from public.customer_address a where a.id = :'addr_a'::uuid) || '/' || (:'f4'::jsonb->'address_review')::text || '/' || (:'f4'::jsonb->'warnings')::text || '/' ||
  (select (f.options->'tailgate_required')::text || '/' || (f.options->'threshold_delivery')::text || '/' || (f.options->>'residential') || '/' || f.packaging_type from public.fc_shipment f where f.id = (:'f4'::jsonb->>'shipment_id')::uuid), 'true/true/true/null/[]/null/null/true/package');
select public.fc_shipment_for_so(:'s1'::uuid) as f5 \gset
select pg_temp.chk('F5 for_so(S1) shows package · options.tailgate_required JSON null (key present) · destination without the key · request destination residential true',
  (:'f5'::jsonb#>>'{shipment,packaging_type}') || '/' || (:'f5'::jsonb#>'{shipment,options,tailgate_required}')::text || '/' || ((:'f5'::jsonb#>'{shipment,destination}') ? 'tailgate_required')::text || '/' || (:'f5'::jsonb#>>'{shipment,request,details,destination,residential}'), 'package/null/false/true');
select public.fc_shipment_prepare(array[:'s4'::uuid], '{"residential": true, "tailgate_required": false, "threshold_delivery": false, "remember": true}'::jsonb, true) as f6 \gset
select pg_temp.chk('F6 pallet remember (office) → all three written true/false/false (rule unchanged) · replace path · row options false/false · payload destination tailgate false · threshold false',
  (:'f6'::jsonb->>'action') || '/' || (select a.residential::text || '/' || a.tailgate_required::text || '/' || a.threshold_delivery::text from public.customer_address a where a.id = :'addr_a'::uuid) || '/' ||
  (select (f.options->>'tailgate_required') || '/' || (f.options->>'threshold_delivery') || '/' || (f.request#>>'{details,destination,tailgate_required}') || '/' || (f.request#>>'{details,packaging_properties,pallet_service_details,threshold_delivery}') from public.fc_shipment f where f.id = (:'f6'::jsonb->>'shipment_id')::uuid), 'replace/true/false/false/false/false/false/false');
select (select a.residential::text || '/' || a.tailgate_required::text || '/' || a.threshold_delivery::text from public.customer_address a where a.id = :'addr_a'::uuid) as f7_before \gset
select pg_temp.as_user(:'u_wms');
select public.fc_shipment_prepare(array[:'s2'::uuid], '{"residential": false, "tailgate_required": true, "threshold_delivery": true, "remember": true}'::jsonb, true) as f7 \gset
select pg_temp.chk('F7 warehouse remember on a box (S2) → address_review reason wms · residential false · tailgate · threshold keys present as JSON null · address untouched · for_so shows null',
  (:'f7'::jsonb->>'mode') || '/' || (:'f7'::jsonb#>>'{address_review,reason}') || '/' || (:'f7'::jsonb#>>'{address_review,residential}') || '/' || (:'f7'::jsonb->'address_review' ? 'tailgate_required')::text || '/' || (:'f7'::jsonb#>'{address_review,tailgate_required}')::text || '/' || (:'f7'::jsonb#>'{address_review,threshold_delivery}')::text || '/' ||
  (select a.residential::text || '/' || a.tailgate_required::text || '/' || a.threshold_delivery::text from public.customer_address a where a.id = :'addr_a'::uuid) || '/' || ((public.fc_shipment_for_so(:'s2'::uuid))#>'{shipment,address_review,tailgate_required}')::text,
  'wms/wms/false/true/null/null/' || :'f7_before' || '/null');
select public.fc_shipment_prepare(array[:'s4'::uuid], '{"residential": false, "tailgate_required": true, "threshold_delivery": true, "remember": true}'::jsonb, true) as f8 \gset
select pg_temp.chk('F8 warehouse remember on a pallet (S4) → review carries all three false/true/true · address untouched (F6 values)',
  (:'f8'::jsonb#>>'{address_review,reason}') || '/' || (:'f8'::jsonb#>>'{address_review,residential}') || '/' || (:'f8'::jsonb#>>'{address_review,tailgate_required}') || '/' || (:'f8'::jsonb#>>'{address_review,threshold_delivery}') || '/' ||
  (select a.residential::text || '/' || a.tailgate_required::text || '/' || a.threshold_delivery::text from public.customer_address a where a.id = :'addr_a'::uuid), 'wms/false/true/true/' || :'f7_before');
select pg_temp.as_user(:'u_off');
-- 849(말만): Billing 주소는 견적이 안 본다 — 같은 거리 · 우편번호의 Billing(tailgate true · threshold true)을 더해도 팔렛 미리 보기는 addr_a(false/false)를 맞춘다
insert into public.customer_address (customer_id, source, type, is_default_for_type, line1, city, state_province, postal_code, country, residential, tailgate_required, threshold_delivery) values (:'c_a'::uuid, 'manual', 'Billing', false, '100 Fcx Street', 'Toronto', 'ON', 'M5V 1A1', 'Canada', true, true, true);
select pg_temp.chk('F9 849: a Billing address at the same street · postal (tailgate true · threshold true) is not read → pallet preview still matches addr_a · tailgate false · threshold false · residential true (F6) · no ambiguity warning',
  (select ((o->>'address_id') = :'addr_a')::text || '/' || (o#>>'{options,tailgate_required}') || '/' || (o#>>'{options,threshold_delivery}') || '/' || (o#>>'{options,residential}') || '/' || (o->'warnings')::text
     from (select pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{"remember": true}'', false)::text', :'s4'))::jsonb as o) t), 'true/false/false/true/[]');
select pg_temp.chk('F10 fc_shipment_prepare reissued (md5 · exactly one) · fc_shipment_for_so · fc_address_review_close · so_finalize untouched',
  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_prepare') || '/' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_prepare') || '/' ||
  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_for_so') || '/' || (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_address_review_close') || '/' || (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize'),
  '2a2a0206f9f2b12320dd93f6467fa8fc/1/83b5e899f8fd8ebcbe5d654a20b20c4a/c1d1ef93039219c31d36bcdf47275b74/' || :'fin_md5_0');

-- ── 결과 ──
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res where n > :n_1b4 or not ok order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok, :n_1b4 as from_fc_1b4 from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :y_so and (select count(*) from public.customer_address) = :y_addr and (select count(*) from public.fc_shipment) = :y_fc and (select count(*) from public.fc_quote) = :y_q and (select count(*) from public.ims_staff) = :y_staff and (select count(*) from public.ref_carrier) = :y_car and (select count(*) from public.ref_warehouse) = :y_wh
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
