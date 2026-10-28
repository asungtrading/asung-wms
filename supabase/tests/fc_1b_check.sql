-- supabase/tests/fc_1b_check.sql — fc-1b 판정 845(주소 기억 필요 — 오피스 확인) · 견적 pending 줄 · fc_quote_save p_request 검증 (2026-10-28)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4 · 잠금 규칙 ①~⑥) — begin → (-v mig 면 \i) → ⭐ fc_1a_check 의 속(76 · 확인 갈래 사본 · 가짜 재료 FCX- 와 도우미를 그대로 이어 쓴다) → B 갈래(845 · pending) → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028170402_fc_1b_address_review_quote_pending.sql -f supabase/tests/fc_1b_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험 · 확인 둘 다 **99** = fc-1a 확인 갈래 76 + fc-1b 23 (옛 = 새 대조 없음 · 시험 전용 줄 없음) · Z1(실제 행 무변 · t_res 밖)
--   fc_1a_check 사본: \! awk 로 begin · \if … \endif 셋 · 「── 결과 ──」 부터 끝을 뗀다(bo-1c 꼴) — 4e 의 경고 기대(address_not_found 만)는 fc-1b 뒤에도 그대로다(새 경고 열쇠 없음 · 반환 address_review 로 알린다)
\set ON_ERROR_STOP on
\set EXPECT_OK 99
\pset pager off
\! awk 'BEGIN{skip=0;done=0} /^\\if :\{\?mig\}/{skip=1;next} /^\\endif/{if(skip){skip=0;next}} /^-- ── 결과 ──/{done=1} done{next} skip{next} /^begin;$/{next} /^set local lock_timeout/{next} {print}' supabase/tests/fc_1a_check.sql > /tmp/fc_1a-inner.sql
select (select count(*) from public.so) as n_so0, (select count(*) from public.customer_address) as n_addr0, (select count(*) from public.fc_shipment) as n_fc0, (select count(*) from public.fc_quote) as n_q0, (select count(*) from public.ims_staff) as n_staff0 \gset
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
\echo '── fc_1a_check 속(확인 갈래 사본 · 76)'
\i /tmp/fc_1a-inner.sql
select count(*) as n_1a from t_res \gset
\echo '── fc-1a inner done: rows' :n_1a

-- ── B 845: 창고 remember → 쓰지 않고 표시 · 오피스 못 찾음 → 표시 · 오피스 찾음 → 씀 ──
select pg_temp.as_user(:'u_wms');
select pg_temp.chk('B1 fc_quote_save is one function with p_request (drop + create)', (select count(*)::text || '/' || max(pg_get_function_identity_arguments(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_save'), '1/p_shipment_id uuid, p_request_id text, p_response jsonb, p_error text, p_request jsonb');
select (select a.residential::text || '/' || a.tailgate_required::text from public.customer_address a where a.id = :'addr_a'::uuid) as addr_a_before \gset
select public.fc_shipment_prepare(array[:'s2'::uuid], '{"residential": true, "tailgate_required": true, "remember": true}'::jsonb, true) as w1 \gset
select pg_temp.chk('B2 warehouse remember → mode wms · address matched · address_review set (reason wms · values · requested_by) · no warning key added', (:'w1'::jsonb->>'mode') || '/' || ((:'w1'::jsonb->>'address_id') = :'addr_a')::text || '/' || (:'w1'::jsonb#>>'{address_review,reason}') || '/' || (:'w1'::jsonb#>>'{address_review,residential}') || '/' || (:'w1'::jsonb#>>'{address_review,tailgate_required}') || '/' || ((:'w1'::jsonb#>>'{address_review,requested_by}') is not null)::text || '/' || (:'w1'::jsonb->'warnings')::text, 'wms/true/wms/true/true/true/[]');
select pg_temp.chk('B3 warehouse remember wrote nothing to the address', (select a.residential::text || '/' || a.tailgate_required::text from public.customer_address a where a.id = :'addr_a'::uuid), :'addr_a_before');
select pg_temp.chk('B4 shipment row carries address_review · not closed · for_so shows it', (select (f.address_review->>'reason') || '/' || (f.address_review_closed_at is null)::text from public.fc_shipment f where f.id = (:'w1'::jsonb->>'shipment_id')::uuid) || '/' || ((public.fc_shipment_for_so(:'s2'::uuid))#>>'{shipment,address_review,reason}'), 'wms/true/wms');
select pg_temp.chk('B5 warehouse cannot close the review (sales only)', (pg_temp.try(format('select public.fc_address_review_close(%L, ''once'')::text', :'w1'::jsonb->>'shipment_id')) like 'ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission%')::text, 'true');
select pg_temp.chk('B6 warehouse prepare again without remember keeps the open review', (select (f.address_review->>'reason') from public.fc_shipment f where f.id = (pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', true)::text', :'s2'))::jsonb->>'shipment_id')::uuid), 'wms');
select pg_temp.as_user(:'u_off');
select pg_temp.chk('B7 office close action must be one of three', (pg_temp.try(format('select public.fc_address_review_close(%L, ''maybe'')::text', :'w1'::jsonb->>'shipment_id')) like 'ERR P0001: action must be one of added · default_changed · once — nothing was saved')::text, 'true');
select public.fc_address_review_close((:'w1'::jsonb->>'shipment_id')::uuid, 'default_changed') as c1 \gset
select pg_temp.chk('B8 office closes with default_changed → closed_at · by · action · address_id rematched (addr_a)', (select (f.address_review_closed_at is not null)::text || '/' || f.address_review_action || '/' || (f.address_id = :'addr_a'::uuid)::text || '/' || (f.address_review_closed_by is not null)::text from public.fc_shipment f where f.id = (:'w1'::jsonb->>'shipment_id')::uuid) || '/' || ((:'c1'::jsonb->>'address_id') = :'addr_a')::text, 'true/default_changed/true/true/true');
select pg_temp.chk('B9 closing twice → refused', (pg_temp.try(format('select public.fc_address_review_close(%L, ''once'')::text', :'w1'::jsonb->>'shipment_id')) like 'ERR P0001: Already confirmed (default_changed) — nothing was saved')::text, 'true');
select public.fc_shipment_prepare(array[:'s2'::uuid], '{"residential": false, "remember": true}'::jsonb, true) as o10 \gset
select pg_temp.chk('B10 office remember with a matched address → writes · no review (fc-1a 4c path unchanged)', (:'o10'::jsonb->'address_review')::text || '/' || (select a.residential::text from public.customer_address a where a.id = :'addr_a'::uuid), 'null/false');
select public.fc_shipment_prepare(array[:'s3'::uuid], '{"tailgate_required": true, "remember": true}'::jsonb, true) as o3 \gset
select pg_temp.chk('B11 office remember · address not found → warning + review reason address_not_found · address_id null', (:'o3'::jsonb->'warnings')::text || '/' || (:'o3'::jsonb#>>'{address_review,reason}') || '/' || ((:'o3'::jsonb->>'address_id') is null)::text, '["address_not_found"]/address_not_found/true');
select pg_temp.chk('B12 office close "added" before the address exists → refused (found 0)', (pg_temp.try(format('select public.fc_address_review_close(%L, ''added'')::text', :'o3'::jsonb->>'shipment_id')) like 'ERR P0001: The ship-to address (999 Other Rd · M9W9Z9) is still not exactly one of the customer''s addresses (found 0)%')::text, 'true');
select (public.customer_update(jsonb_build_array(jsonb_build_object('op', 'address_add', 'customer_id', :'c_a', 'values', jsonb_build_object('type', 'Shipping', 'line1', '999 Other Rd', 'city', 'Toronto', 'state_province', 'ON', 'postal_code', 'M9W 9Z9', 'country', 'CA', 'tailgate_required', 'true'))), true, array[:'c_a' || ':open_so_keep_old']))->>'committed' as added \gset
select public.fc_address_review_close((:'o3'::jsonb->>'shipment_id')::uuid, 'added') as c3 \gset
select pg_temp.chk('B13 after customer_update address_add (+ tailgate) the close "added" finds exactly one → address_id set · address has the flag', :'added' || '/' || (select (f.address_id = (:'c3'::jsonb->>'address_id')::uuid)::text || '/' || (select a.tailgate_required::text || '/' || a.line1 from public.customer_address a where a.id = f.address_id) from public.fc_shipment f where f.id = (:'o3'::jsonb->>'shipment_id')::uuid), 'true/true/true/999 Other Rd');
select pg_temp.chk('B14 next prepare for S3 without options picks the remembered tailgate from the new address · no review', (select (o#>>'{options,tailgate_required}') || '/' || (o->'address_review')::text || '/' || ((o->>'address_id') = (:'c3'::jsonb->>'address_id'))::text from (select pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s3'))::jsonb as o) t), 'true/null/true');
select pg_temp.chk('B15 close "once" on a shipment without a review → refused', (pg_temp.try(format('select public.fc_address_review_close(%L, ''once'')::text', :'r9b'::jsonb->>'shipment_id')) like 'ERR P0001: This shipment has no address to confirm — nothing was saved')::text, 'true');

-- ── B 견적 pending 줄 · p_request ──
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_quote_pending((:'r9b'::jsonb->>'shipment_id')::uuid, 'req-p1', '{"services": ["fcxalpha.std"], "details": {"packaging_type": "package"}}'::jsonb) as p1 \gset
select pg_temp.chk('B16 fc_quote_pending (service_role) → pending row with the sent body · shipment status unchanged', (:'p1'::jsonb->>'status') || '/' || (select q.status || '/' || (q.request->'services'->>0) || '/' || (q.response is null)::text from public.fc_quote q where q.id = (:'p1'::jsonb->>'quote_id')::uuid) || '/' || (select f.status from public.fc_shipment f where f.id = (:'r9b'::jsonb->>'shipment_id')::uuid), 'pending/pending/fcxalpha.std/true/quoted');
select pg_temp.chk('B17 pending shows in for_so as the latest quote with no rates', ((public.fc_shipment_for_so(:'s1'::uuid))#>>'{quote,status}') || '/' || jsonb_array_length((public.fc_shipment_for_so(:'s1'::uuid))#>'{quote,rates}'), 'pending/0');
select public.fc_quote_save((:'r9b'::jsonb->>'shipment_id')::uuid, 'req-p1', :'rates'::jsonb, null, '{"services": ["fcxalpha.std"], "details": {"packaging_type": "package", "sent": true}}'::jsonb) as sv \gset
select pg_temp.chk('B18 fc_quote_save with the same request_id updates the pending row (same quote_id) → done · 5 rates · request = p_request', ((:'sv'::jsonb->>'quote_id') = (:'p1'::jsonb->>'quote_id'))::text || '/' || (:'sv'::jsonb->>'status') || '/' || (:'sv'::jsonb->>'rates') || '/' || (select q.status || '/' || (q.request->'details'->>'sent') from public.fc_quote q where q.id = (:'p1'::jsonb->>'quote_id')::uuid), 'true/done/5/done/true');
select public.fc_quote_save((:'r9b'::jsonb->>'shipment_id')::uuid, 'req-old', :'rates'::jsonb, null) as o19 \gset
select pg_temp.chk('B19 four-argument call (fc-1a shape · no p_request) still works · new row · request = shipment payload', (:'o19'::jsonb->>'status') || '/' || (select (q.request = f.request)::text from public.fc_quote q join public.fc_shipment f on f.id = q.shipment_id where q.id = (:'o19'::jsonb->>'quote_id')::uuid), 'done/true');
select public.fc_quote_pending((:'r9b'::jsonb->>'shipment_id')::uuid, 'req-p2', '{"x": 1}'::jsonb) as p2 \gset
select public.fc_quote_save((:'r9b'::jsonb->>'shipment_id')::uuid, 'req-p2', null, 'HTTP 500 upstream') as o20 \gset
select pg_temp.chk('B20 error after pending → same row becomes error · request kept', ((:'o20'::jsonb->>'quote_id') = (:'p2'::jsonb->>'quote_id'))::text || '/' || (select q.status || '/' || q.error || '/' || (q.request->>'x') from public.fc_quote q where q.id = (:'p2'::jsonb->>'quote_id')::uuid), 'true/error/HTTP 500 upstream/1');
select pg_temp.chk('B21 pending needs a request_id · cancelled shipment refused', (pg_temp.try(format('select public.fc_quote_pending(%L, '''', ''{}'')::text', :'r9b'::jsonb->>'shipment_id')) like 'ERR P0001: request_id is required — nothing was saved')::text || '/' || (pg_temp.try(format('select public.fc_quote_pending(%L, ''r'', ''{}'')::text', :'r1'::jsonb->>'shipment_id')) like 'ERR P0001: Shipment is cancelled — no new quotes — nothing was saved')::text, 'true/true');
select pg_temp.as_user(:'u_none');
select pg_temp.chk('B22 fc_quote_pending by a staff user without the gate → refused', (pg_temp.try(format('select public.fc_quote_pending(%L, ''r'', ''{}'')::text', :'r9b'::jsonb->>'shipment_id')) like 'ERR P0001: You cannot work with freight quotes — ask an admin to add the ''sales'' or ''fulfillment'' permission%')::text, 'true');
select pg_temp.chk('B23 so_finalize untouched by fc-1b', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize'), :'fin_md5_0');

-- ── 결과 ──
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res where n > :n_1a or not ok order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok, :n_1a as from_fc_1a from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :n_so0 and (select count(*) from public.customer_address) = :n_addr0 and (select count(*) from public.fc_shipment) = :n_fc0 and (select count(*) from public.fc_quote) = :n_q0 and (select count(*) from public.ims_staff) = :n_staff0
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
