-- supabase/tests/fc_1b2_check.sql — fc-1b2 fc_quote.seq 「최신」 열쇠 검증 (2026-10-28)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — begin → (-v mig 면 \i) → ⭐ fc_1b_check 의 속(99 = fc_1a 76 + fc_1b 23 · 사본 · 가짜 재료 · 도우미 이어 씀) → C 갈래(동점 셋 · 마지막 done · pending 찾기) → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028171641_fc_1b2_quote_seq.sql -f supabase/tests/fc_1b2_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험 · 확인 둘 다 **106** = 99 + 7 (시험 전용 줄 없음) · Z1 은 t_res 밖 · ⚠️ B17 이 시험 · 확인 둘 다에서 같은 답이 나오는 것이 이 차수의 뜻
\set ON_ERROR_STOP on
\set EXPECT_OK 106
\pset pager off
\! awk 'BEGIN{skip=0;done=0} /^\\if :\{\?mig\}/{skip=1;next} /^\\endif/{if(skip){skip=0;next}} /^-- ── 결과 ──/{done=1} done{next} skip{next} /^begin;$/{next} /^set local lock_timeout/{next} /^\\set EXPECT_OK/{next} {print}' supabase/tests/fc_1b_check.sql > /tmp/fc_1b-inner.sql
select (select count(*) from public.so) as n_so0, (select count(*) from public.customer_address) as n_addr0, (select count(*) from public.fc_shipment) as n_fc0, (select count(*) from public.fc_quote) as n_q0, (select count(*) from public.ims_staff) as n_staff0 \gset
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
\echo '── fc_1b_check 속(사본 · 99 — 그 안의 fc_1a 76 포함)'
\i /tmp/fc_1b-inner.sql
select count(*) as n_1b from t_res \gset
\echo '── fc-1b inner done: rows' :n_1b

-- ── C seq 가 「최신」 을 하나로 정한다 — 같은 트랜잭션(같은 now()) 안의 견적들 ──
select pg_temp.chk('C1 fc_quote.seq identity · index (shipment_id, seq desc) · three functions order by seq · none by requested_at',
  (select is_identity from information_schema.columns where table_schema = 'public' and table_name = 'fc_quote' and column_name = 'seq') || '/' || (to_regclass('public.fc_quote_shipment_seq_idx') is not null)::text || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_shipment_for_so', 'fc_quote_save', 'fc_quote_select') and prosrc like '%order by q.seq desc%') || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_shipment_for_so', 'fc_quote_save', 'fc_quote_select') and prosrc like '%requested_at desc%'), 'YES/true/3/0');
select pg_temp.chk('C2 all quotes of r9b made in this txn share requested_at (the tie that broke B17)', (select (count(distinct q.requested_at) = 1 and count(*) >= 4)::text from public.fc_quote q where q.shipment_id = (:'r9b'::jsonb->>'shipment_id')::uuid), 'true');
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_quote_pending((:'r9b'::jsonb->>'shipment_id')::uuid, 'req-c1', '{"n": 1}'::jsonb) as c1 \gset
select public.fc_quote_pending((:'r9b'::jsonb->>'shipment_id')::uuid, 'req-c2', '{"n": 2}'::jsonb) as c2 \gset
select public.fc_quote_pending((:'r9b'::jsonb->>'shipment_id')::uuid, 'req-c3', '{"n": 3}'::jsonb) as c3 \gset
select pg_temp.chk('C3 latest = highest seq regardless of uuid order: for_so shows req-c3 (pending · 0 rates) — repeatable in both branches', ((public.fc_shipment_for_so(:'s1'::uuid))#>>'{quote,request_id}') || '/' || ((public.fc_shipment_for_so(:'s1'::uuid))#>>'{quote,status}') || '/' || (select (q1.seq < q2.seq and q2.seq < q3.seq)::text from public.fc_quote q1, public.fc_quote q2, public.fc_quote q3 where q1.id = (:'c1'::jsonb->>'quote_id')::uuid and q2.id = (:'c2'::jsonb->>'quote_id')::uuid and q3.id = (:'c3'::jsonb->>'quote_id')::uuid), 'req-c3/pending/true');
select public.fc_quote_save((:'r9b'::jsonb->>'shipment_id')::uuid, 'req-c1', :'rates'::jsonb) as s1q \gset
select public.fc_quote_save((:'r9b'::jsonb->>'shipment_id')::uuid, 'req-c2', :'rates'::jsonb) as s2q \gset
select pg_temp.chk('C4 fc_quote_save finds the pending row by request_id (same quote ids) · both done', ((:'s1q'::jsonb->>'quote_id') = (:'c1'::jsonb->>'quote_id'))::text || '/' || ((:'s2q'::jsonb->>'quote_id') = (:'c2'::jsonb->>'quote_id'))::text || '/' || (:'s1q'::jsonb->>'status') || (:'s2q'::jsonb->>'status'), 'true/true/donedone');
select pg_temp.as_user(:'u_off');
select pg_temp.chk('C5 fc_quote_select: a rate of the older done quote (req-c1) is refused · latest done = req-c2 by seq (req-c3 pending is skipped)',
  (pg_temp.try(format('select public.fc_quote_select(%L, (select r.id from public.fc_quote_rate r where r.quote_id = %L and r.service_id = ''fcxalpha.std''))::text', :'r9b'::jsonb->>'shipment_id', :'s1q'::jsonb->>'quote_id')) like 'ERR P0001: That rate is not on the latest quote of this shipment — quote again%')::text || '/' ||
  ((pg_temp.try(format('select public.fc_quote_select(%L, (select r.id from public.fc_quote_rate r where r.quote_id = %L and r.service_id = ''fcxalpha.std''))::text', :'r9b'::jsonb->>'shipment_id', :'s2q'::jsonb->>'quote_id'))::jsonb->>'selected_rate_id') is not null)::text, 'true/true');
select pg_temp.chk('C6 for_so after saves: latest is still req-c3 (pending · newest seq) — the office sees the newer request is still running', ((public.fc_shipment_for_so(:'s1'::uuid))#>>'{quote,request_id}') || '/' || ((public.fc_shipment_for_so(:'s1'::uuid))#>>'{quote,status}'), 'req-c3/pending');
select pg_temp.chk('C7 so_finalize untouched', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize'), :'fin_md5_0');

-- ── 결과 ──
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res where n > :n_1b or not ok order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok, :n_1b as from_fc_1b from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :n_so0 and (select count(*) from public.customer_address) = :n_addr0 and (select count(*) from public.fc_shipment) = :n_fc0 and (select count(*) from public.fc_quote) = :n_q0 and (select count(*) from public.ims_staff) = :n_staff0
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
