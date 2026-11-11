-- supabase/tests/fc_track_4_check.sql — fc-track-4 검증 (2026-11-10 밤 토론토 · 판정 1167 · 1168 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] 기준(begin 앞) → begin(lock_timeout 3s) → 가짜 재료(직원 일곱 · 예약 여섯 — 실제 booked 토론토 예약 하나를 복제 · 계정 ZZT) → (-v mig 면 \i) → 시나리오 → 구조 · 정적 검사 → 집계 → rollback
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111042906_fc_track_4_board_money_gate_close_tables.sql -f supabase/tests/fc_track_4_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(갈래마다 같다)
--   ⚠️ 실물 예약 수는 cron 과 함께 변한다 — 수는 박지 않고 같은 트랜잭션 안에서 표를 직접 세어 견준다 · 실물을 박은 곳은 둘: B5 의 SO-21106(from 2026-11-01 로 고정) · B7 의 예약 32eee6e1…(이벤트 8 이상)
\set ON_ERROR_STOP on
\pset pager off
\set EXPECT_OK 27
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fc\_%' and p.proname not in ('fc_add_business_days', 'fc_board_row', 'fc_board', 'fc_board_detail');
create temp table t_ids (k text primary key, v text);
create temp table t_res (n serial, label text, got text, want text, ok boolean);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns void language sql as $$ insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want); $$;
create function pg_temp.id(p_k text) returns text language sql as $$ select v from t_ids where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_ids values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
declare v text; v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
  execute format('set local role %I', p_role);
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return coalesce(v, '(null)');
end $$;
create function pg_temp.svc(p_sql text) returns text language sql as $$ select pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, p_sql) $$;
create function pg_temp.anon(p_sql text) returns text language sql as $$ select pg_temp.as_conn('anon', '{"role":"anon"}'::jsonb, p_sql) $$;
create function pg_temp.usr(p_k text, p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', jsonb_build_object('role', 'authenticated', 'sub', pg_temp.id('auth_' || p_k)), p_sql) $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  return coalesce(v, '(null)');
end $$;
create function pg_temp.err(p_v text, p_like text) returns text language sql as $$ select case when p_v like 'ERR %' and p_v like p_like then 'refused' else left(p_v, 200) end $$;
-- 창구 답(글자)에 SQL 한 줄을 돌린다($1 = jsonb) — 거부면 그 글을 그대로
create function pg_temp.jq(p_v text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  if p_v like 'ERR %' or p_v = '(null)' then return left(p_v, 200); end if;
  begin execute p_sql into v using p_v::jsonb; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  return coalesce(v, '(null)');
end $$;
-- 보드 · 상세를 그 사람으로 — 답을 t_out 에 담아 여러 번 본다
create temp table t_out (k text primary key, v text, ms numeric);
create function pg_temp.run(p_k text, p_who text, p_sql text) returns void language plpgsql as $$
declare v text; t0 timestamptz := clock_timestamp();
begin
  v := pg_temp.usr(p_who, p_sql);
  insert into t_out values (p_k, v, round(extract(epoch from clock_timestamp() - t0)::numeric * 1000, 1)) on conflict (k) do update set v = excluded.v, ms = excluded.ms;
end $$;
create function pg_temp.o(p_k text) returns text language sql as $$ select v from t_out where k = p_k $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g'); exit when v_chunk = v_prev; end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
-- 가짜 예약 하나 — 실제 booked 예약(src_b)을 복제하고 칸을 덮는다(같은 발송 · attempt 9401 ~ · 계정 ZZT · 청구 문서 없음)
create function pg_temp.mkb(p_k text, p_attempt int, p_over jsonb default '{}'::jsonb) returns void language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.fc_booking
  select (jsonb_populate_record(null::public.fc_booking, to_jsonb(b) || jsonb_build_object(
            'id', v_id, 'attempt', p_attempt, 'unique_id', 'zzfc4-' || p_k, 'freightcom_shipment_id', 'fcShipBoard' || p_k, 'transaction_number', 'ZZTN' || p_k, 'account', 'ZZT', 'status', 'booked', 'state', 'in-transit',
            'tracking_number', 'ZZTRK-' || p_k, 'tracking_numbers', jsonb_build_array('ZZTRK-' || p_k, 'ZZ2ND-' || p_k), 'pickup_confirmation', 'ZZCONF', 'schedule_status', null, 'schedule_error', null,
            'request', (b.request #- '{pickup_details,date}' #- '{dispatch_details,date}'),
            'so_written', '[]'::jsonb, 'labels', null, 'error', null, 'cancel_error', null, 'cancelled_at', null, 'cancelled_by', null, 'cancel_source', null, 'cancel_note', null, 'failed_at', null,
            'delivered_at', null, 'track_done_at', null, 'booked_at', now() - interval '1 hour') || p_over)).*
    from public.fc_booking b where b.id = pg_temp.id('src_b')::uuid;
  perform pg_temp.put(p_k, v_id::text);
end $$;
-- 기준(begin 앞 · 실물 읽기)
select (select count(*) from public.fc_booking) as n_bk0, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from t_pre) as n_fn0,
       (select max(version) from supabase_migrations.schema_migrations) as ver0, (select count(*) from pg_policies where schemaname = 'public' and tablename like 'fc\_%') as n_pol0 \gset
\echo '── 기준: 예약' :n_bk0 '· 직원' :n_staff0 '· 기존 fc_ 함수' :n_fn0 '· 마지막 마이그레이션' :ver0 '· fc_ 정책' :n_pol0

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
-- ── 가짜 재료 ──
do $$
declare
  v_tor uuid := '045e4ca6-b7a9-446e-9e6a-a5a0db56d456'; v_edm uuid := '95caece3-cf3e-4832-a583-e233254feadc';
  v_src public.fc_booking%rowtype;
begin
  select b.* into v_src from public.fc_booking b join public.fc_shipment f on f.id = b.shipment_id
   where b.status = 'booked' and f.origin_warehouse_id = v_tor and f.booking_id = b.id and (b.response#>>'{shipment,rate,transit_time_days}') ~ '^[1-9]$' order by b.booked_at, b.id limit 1;
  if v_src.id is null then raise exception 'fc_track_4_check: no booked Toronto booking to clone'; end if;
  perform pg_temp.put('src_b', v_src.id::text), pg_temp.put('src_f', v_src.shipment_id::text);
  perform pg_temp.put('src_so', (select f.charge_so_id::text from public.fc_shipment f where f.id = v_src.shipment_id));
  perform pg_temp.put('label', (select l.id::text from public.fc_label l order by l.fetched_at desc limit 1));
  perform pg_temp.put('edm_b', (select b.id::text from public.fc_booking b join public.fc_shipment f on f.id = b.shipment_id where f.origin_warehouse_id = v_edm order by b.booked_at desc limit 1));
  perform pg_temp.put('tor', v_tor::text), pg_temp.put('edm', v_edm::text);
  insert into public.ims_staff (id, auth_user_id, email, name, role, perms, warehouse_access) values
    ('f1c40000-0000-4000-8000-0000000000a1', 'f1c40000-0000-4000-8000-000000000001', 'fc-track-4-b@asung.invalid', 'ZZFC4 Booker',     'manager', '["freight_booking"]', '{}'),
    ('f1c40000-0000-4000-8000-0000000000a2', 'f1c40000-0000-4000-8000-000000000002', 'fc-track-4-p@asung.invalid', 'ZZFC4 Purchasing', 'manager', '["purchasing"]', '{}'),
    ('f1c40000-0000-4000-8000-0000000000a3', 'f1c40000-0000-4000-8000-000000000003', 'fc-track-4-s@asung.invalid', 'ZZFC4 Sales',      'manager', '["sales"]', '{}'),
    ('f1c40000-0000-4000-8000-0000000000a4', 'f1c40000-0000-4000-8000-000000000004', 'fc-track-4-n@asung.invalid', 'ZZFC4 Nobody',     'manager', '["master"]', '{}'),
    ('f1c40000-0000-4000-8000-0000000000a5', 'f1c40000-0000-4000-8000-000000000005', 'fc-track-4-e@asung.invalid', 'ZZFC4 Edmonton',   'manager', '["freight_booking"]', array[v_edm]),
    ('f1c40000-0000-4000-8000-0000000000a6', 'f1c40000-0000-4000-8000-000000000006', 'fc-track-4-f@asung.invalid', 'ZZFC4 Floor',      'worker',  '["wms", "fulfillment"]', '{}'),
    ('f1c40000-0000-4000-8000-0000000000a7', 'f1c40000-0000-4000-8000-000000000007', 'fc-track-4-r@asung.invalid', 'ZZFC4 ReadOnly',   'manager', '["sales", "purchasing:read"]', '{}');
  perform pg_temp.put('auth_B', 'f1c40000-0000-4000-8000-000000000001'), pg_temp.put('auth_P', 'f1c40000-0000-4000-8000-000000000002'), pg_temp.put('auth_S', 'f1c40000-0000-4000-8000-000000000003'),
          pg_temp.put('auth_N', 'f1c40000-0000-4000-8000-000000000004'), pg_temp.put('auth_E', 'f1c40000-0000-4000-8000-000000000005'), pg_temp.put('auth_F', 'f1c40000-0000-4000-8000-000000000006'),
          pg_temp.put('auth_R', 'f1c40000-0000-4000-8000-000000000007');
  -- X1 모르는 state(예외) · X2 늦음(20 일 전 · 운송 중) · X3 Freightcom 취소(인정 전) · X4 픽업 안 잡힘 · X5 60 일 전 배송 끝(기본 창 밖) · X6 60 일 전인데 아직 운송 중(늘 포함)
  perform pg_temp.mkb('X1', 9401, '{"state": "held-at-customs"}');
  perform pg_temp.mkb('X2', 9402, jsonb_build_object('booked_at', now() - interval '20 days'));
  perform pg_temp.mkb('X3', 9403, '{"state": "cancelled"}');
  perform pg_temp.mkb('X4', 9404, jsonb_build_object('pickup_confirmation', null, 'schedule_status', 'error', 'schedule_error', 'zz no driver', 'schedule_checked_at', now(),
                                                      'request', jsonb_build_object('pickup_details', jsonb_build_object('pre_scheduled_pickup', false))));
  perform pg_temp.mkb('X5', 9405, jsonb_build_object('booked_at', now() - interval '60 days', 'state', 'delivered', 'delivered_at', now() - interval '55 days'));
  perform pg_temp.mkb('X6', 9406, jsonb_build_object('booked_at', now() - interval '60 days'));
end $$;
\if :{?mig}
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset

-- ── 창구를 부른다(답은 t_out) ──
select pg_temp.run('B_all',  'B', $q$ select public.fc_board(p_limit => 200)::text $q$),
       pg_temp.run('B_50',   'B', $q$ select public.fc_board(p_limit => 50)::text $q$),
       pg_temp.run('S_all',  'S', $q$ select public.fc_board(p_limit => 200)::text $q$),
       pg_temp.run('P_all',  'P', $q$ select public.fc_board(p_limit => 200)::text $q$),
       pg_temp.run('R_all',  'R', $q$ select public.fc_board(p_limit => 200)::text $q$),
       pg_temp.run('F_all',  'F', $q$ select public.fc_board(p_limit => 200)::text $q$),
       pg_temp.run('E_all',  'E', $q$ select public.fc_board(p_limit => 200)::text $q$),
       pg_temp.run('B_prob', 'B', $q$ select public.fc_board(p_view => 'problems', p_limit => 200)::text $q$),
       pg_temp.run('S_prob', 'S', $q$ select public.fc_board(p_view => 'problems', p_limit => 200)::text $q$),
       pg_temp.run('B_so',   'B', $q$ select public.fc_board(p_from => '2026-11-01', p_q => 'so-21106', p_limit => 200)::text $q$),
       pg_temp.run('B_trk',  'B', $q$ select public.fc_board(p_q => 'zz2nd-x2')::text $q$),
       pg_temp.run('B_tn',   'B', $q$ select public.fc_board(p_q => 'ZZTNX4')::text $q$),
       pg_temp.run('B_pct',  'B', $q$ select public.fc_board(p_q => '%')::text $q$),
       pg_temp.run('B_det',  'B', $q$ select public.fc_board_detail('32eee6e1-936a-4c9c-a8cf-b7b1181a1119')::text $q$),
       pg_temp.run('S_det',  'S', $q$ select public.fc_board_detail('32eee6e1-936a-4c9c-a8cf-b7b1181a1119')::text $q$);
\echo '── T1 시간(ms · 가짜 직원 freight_booking · 창구 한 번):'
select k, ms, pg_temp.jq(v, $q$ select ($1->>'total') $q$) as total from t_out where k in ('B_all', 'B_50', 'S_all', 'B_prob', 'B_det') order by k;

-- ── 시나리오 ──
select pg_temp.chk('B1a freight_booking — 창 안의 예약 전부(표를 직접 센 수와 같다) · total = rows · can_see_money t',
         pg_temp.jq(pg_temp.o('B_all'), $q$ select concat_ws(' ', $1->>'can_see_money', ($1->>'total')::int = jsonb_array_length($1->'rows'),
              ($1->>'total')::int = (select count(*) from public.fc_booking b where b.status in ('booked', 'cancelled') and nullif(btrim(b.freightcom_shipment_id), '') is not null
                                       and ((b.booked_at at time zone 'America/Toronto')::date between public.ims_today() - 30 and public.ims_today() or (b.status = 'booked' and public.fc_state_kind(b.state) = 'open'))),
              ($1->>'total')::int >= 50) $q$), 'true t t t'),
       pg_temp.chk('B1b accounts 둘(EDM · TOR · 요약 칸 · warehouses) · 모든 줄에 money · 금액은 정수',
         pg_temp.jq(pg_temp.o('B_all'), $q$ select concat_ws(' ', (select string_agg(a->>'account', ',' order by a->>'account') from jsonb_array_elements($1->'accounts') a),
              (select bool_and(a ? 'available_cents' and a ? 'limit_cents' and a ? 'used_cents' and a ? 'invoices_owing' and jsonb_array_length(a->'warehouses') = 1 and not a ? 'uninvoiced_ims') from jsonb_array_elements($1->'accounts') a),
              (select count(*) from jsonb_array_elements($1->'rows') r where jsonb_typeof(r->'money') <> 'object'),
              (select bool_and(jsonb_typeof(r#>'{money,booked_total}') in ('number', 'null') and jsonb_typeof(r#>'{money,billed_total}') in ('number', 'null') and r->'money' ? 'charge_state' and jsonb_typeof(r#>'{money,warnings}') = 'array') from jsonb_array_elements($1->'rows') r)) $q$),
         'EDM,TOR t 0 t'),
       pg_temp.chk('B1c 줄의 꼴 — 칸 이름 · 원문 칸(request · response · labels · schedule_response)은 없다',
         pg_temp.jq(pg_temp.o('B_all'), $q$ select concat_ws(' ', (select bool_and(r ?& array['booking_id', 'shipment_id', 'attempt', 'status', 'cancel_source', 'account', 'warehouse_id', 'warehouse_name', 'booked_at', 'pickup_date', 'so_numbers', 'charge_so_id', 'charge_so_number',
                'customer_id', 'customer_name', 'carrier_name', 'service_name', 'tracking_number', 'tracking_numbers', 'tracking_url', 'state', 'state_kind', 'state_checked_at', 'delivered_at', 'track_last', 'transit_days', 'expected_by', 'late', 'pickup', 'fc_cancelled', 'flags', 'money',
                'transaction_number', 'moving', 'exception', 'cancelled_at', 'cancel_note']) from jsonb_array_elements($1->'rows') r),
              (select bool_or(r ?| array['request', 'response', 'labels', 'schedule_response', 'pickup', 'unique_id'] and (r ?| array['request', 'response', 'labels', 'schedule_response', 'unique_id'])) from jsonb_array_elements($1->'rows') r),
              $1::text like '%s3.%amazonaws%' or $1::text like '%X-Amz-%') $q$), 't f f'),
       pg_temp.chk('B2 sales 만 — 줄은 같다 · can_see_money f · accounts [] · money 는 전부 null · counts.extra · cancelled_billed null · 깃발에 돈 것이 없다',
         pg_temp.jq(pg_temp.o('S_all'), $q$ select concat_ws(' ', $1->>'can_see_money', $1->>'accounts', (select count(*) from jsonb_array_elements($1->'rows') r where r->'money' <> 'null'::jsonb),
              jsonb_typeof($1#>'{counts,extra}'), jsonb_typeof($1#>'{counts,cancelled_billed}'), (select count(*) from jsonb_array_elements($1->'rows') r where r->'flags' ?| array['extra', 'cancelled_billed'])) $q$) || ' ' ||
         (pg_temp.jq(pg_temp.o('S_all'), $q$ select (select string_agg(r->>'booking_id', ',' order by r->>'booking_id') from jsonb_array_elements($1->'rows') r) $q$) = pg_temp.jq(pg_temp.o('B_all'), $q$ select (select string_agg(r->>'booking_id', ',' order by r->>'booking_id') from jsonb_array_elements($1->'rows') r) $q$))::text,
         'false [] 0 null null 0 true'),
       pg_temp.chk('B2b 돈 문 — purchasing 쓰기만 = 보드를 열고 돈을 본다 · purchasing:read + sales = 돈 못 봄 · fulfillment 직원 = 돈 못 봄',
         concat_ws(' ', pg_temp.jq(pg_temp.o('P_all'), $q$ select concat_ws(',', $1->>'can_see_money', jsonb_array_length($1->'accounts')) $q$), pg_temp.jq(pg_temp.o('R_all'), $q$ select concat_ws(',', $1->>'can_see_money', jsonb_array_length($1->'accounts')) $q$),
                   pg_temp.jq(pg_temp.o('F_all'), $q$ select concat_ws(',', $1->>'can_see_money', jsonb_array_length($1->'accounts'), ($1->>'total')::int > 0) $q$)), 'true,2 false,0 false,0,t'),
       pg_temp.chk('B3 권한 없음(master 만) · anon — 보드 · 상세 거부',
         concat_ws(' ', pg_temp.err(pg_temp.usr('N', $q$ select public.fc_board()::text $q$), '%You cannot see freight shipments — ask an admin for the ''sales'', ''fulfillment'' or ''freight_booking'' permission%'),
                   pg_temp.err(pg_temp.usr('N', format('select public.fc_board_detail(%L)::text', pg_temp.id('X1'))), '%You cannot see freight shipments%'),
                   pg_temp.err(pg_temp.anon($q$ select public.fc_board()::text $q$), 'ERR 42501%'), pg_temp.err(pg_temp.anon(format('select public.fc_board_detail(%L)::text', pg_temp.id('X1'))), 'ERR 42501%')), 'refused refused refused refused'),
       pg_temp.chk('B3b 창고 경계 — 에드먼턴만 보는 직원: 줄은 전부 에드먼턴 · accounts 는 EDM 하나 · 토론토 창고를 고르면 거부 · 토론토 예약 상세 거부 · 에드먼턴 상세는 열림',
         concat_ws(' ', pg_temp.jq(pg_temp.o('E_all'), $q$ select concat_ws(',', (select coalesce(bool_and(r->>'warehouse_id' = '95caece3-cf3e-4832-a583-e233254feadc'), true) from jsonb_array_elements($1->'rows') r), ($1->>'total')::int > 0,
                          (select string_agg(a->>'account', '+') from jsonb_array_elements($1->'accounts') a)) $q$),
                   pg_temp.err(pg_temp.usr('E', format('select public.fc_board(p_warehouse_id => %L)::text', pg_temp.id('tor'))), '%outside your warehouse access%'),
                   pg_temp.err(pg_temp.usr('E', format('select public.fc_board_detail(%L)::text', pg_temp.id('X1'))), '%belongs to another warehouse%'),
                   pg_temp.jq(pg_temp.usr('E', format('select public.fc_board_detail(%L)::text', pg_temp.id('edm_b'))), $q$ select $1#>>'{row,warehouse_name}' $q$)), 't,t,EDM refused refused Asung - Edmonton'),
       pg_temp.chk('B3c 창고 고르기 — 토론토만: 줄 전부 토론토 · accounts 는 TOR 하나 · 없는 창고는 거부',
         concat_ws(' ', pg_temp.jq(pg_temp.usr('B', format('select public.fc_board(p_warehouse_id => %L, p_limit => 200)::text', pg_temp.id('tor'))), $q$ select concat_ws(',', (select bool_and(r->>'warehouse_id' = '045e4ca6-b7a9-446e-9e6a-a5a0db56d456') from jsonb_array_elements($1->'rows') r),
                          (select string_agg(a->>'account', '+') from jsonb_array_elements($1->'accounts') a), $1->>'warehouse') $q$),
                   pg_temp.err(pg_temp.usr('B', $q$ select public.fc_board(p_warehouse_id => '00000000-0000-4000-8000-000000000000')::text $q$), '%Warehouse not found%')), 't,TOR,Asung Trading Inc. refused'),
       pg_temp.chk('B4a 깃발 — X1 exception · X2 late · X3 fc_cancelled · X4 pickup_not_scheduled · X6(60 일 전 · 운송 중) late',
         pg_temp.jq(pg_temp.o('B_all'), format($q$ select (select string_agg((r->>'tracking_number') || '=' || (r->>'flags'), ' ' order by r->>'tracking_number') from jsonb_array_elements($1->'rows') r where r->>'tracking_number' like 'ZZTRK-%%') $q$)),
         'ZZTRK-X1=["exception"] ZZTRK-X2=["late"] ZZTRK-X3=["fc_cancelled"] ZZTRK-X4=["pickup_not_scheduled"] ZZTRK-X6=["late"]'),
       pg_temp.chk('B4b problems — 줄마다 깃발이 있다 · total = counts.problems · cancelled_billed 수 = fc_charge_check 로 직접 센 수(창 안) · Freightcom 취소(인정 전)는 실물까지 전부 들어 있다',
         pg_temp.jq(pg_temp.o('B_prob'), $q$ select concat_ws(' ', (select bool_and(jsonb_array_length(r->'flags') > 0) from jsonb_array_elements($1->'rows') r), ($1->>'total') = ($1#>>'{counts,problems}'),
              ($1#>>'{counts,cancelled_billed}')::int = (select count(*) from public.fc_booking b where b.status = 'cancelled' and (b.booked_at at time zone 'America/Toronto')::date between public.ims_today() - 30 and public.ims_today() and public.fc_charge_check(b.id)->>'state' = 'cancelled_billed'),
              ($1#>>'{counts,cancelled_billed}')::int >= 2,
              ($1#>>'{counts,fc_cancelled}')::int = (select count(*) from public.fc_booking b where b.status = 'booked' and public.fc_state_kind(b.state) = 'cancelled' and (b.booked_at at time zone 'America/Toronto')::date between public.ims_today() - 30 and public.ims_today()),
              (select count(*) from jsonb_array_elements($1->'rows') r where r->'flags' ? 'fc_cancelled') = ($1#>>'{counts,fc_cancelled}')::int) $q$), 't t t t t t'),
       pg_temp.chk('B4c sales 의 problems — 돈 깃발만 있는 줄(cancelled_billed)은 빠진다 · 나머지 문제는 같다',
         concat_ws(' ', pg_temp.jq(pg_temp.o('S_prob'), $q$ select (select count(*) from jsonb_array_elements($1->'rows') r where r->'flags' ?| array['extra', 'cancelled_billed'])::text $q$),
                   (pg_temp.jq(pg_temp.o('S_prob'), $q$ select $1->>'total' $q$)::int = pg_temp.jq(pg_temp.o('B_prob'), $q$ select (select count(*) from jsonb_array_elements($1->'rows') r where (r->'flags') - 'extra' - 'cancelled_billed' <> '[]'::jsonb)::text $q$)::int)::text), '0 true'),
       pg_temp.chk('B4d counts — all = moving + delivered + cancelled · 보기마다 total = 그 counts',
         concat_ws(' ', pg_temp.jq(pg_temp.o('B_all'), $q$ select (($1#>>'{counts,all}')::int = ($1#>>'{counts,moving}')::int + ($1#>>'{counts,delivered}')::int + ($1#>>'{counts,cancelled}')::int and ($1#>>'{counts,all}') = ($1->>'total'))::text $q$),
                   pg_temp.jq(pg_temp.usr('B', $q$ select public.fc_board(p_view => 'moving', p_limit => 1)::text $q$), $q$ select (($1->>'total') = ($1#>>'{counts,moving}') and ($1#>>'{rows,0,moving}') = 'true')::text $q$),
                   pg_temp.jq(pg_temp.usr('B', $q$ select public.fc_board(p_view => 'delivered', p_limit => 1)::text $q$), $q$ select (($1->>'total') = ($1#>>'{counts,delivered}') and ($1#>>'{rows,0,state_kind}') = 'delivered')::text $q$),
                   pg_temp.jq(pg_temp.usr('B', $q$ select public.fc_board(p_view => 'Cancelled', p_limit => 200)::text $q$), $q$ select (($1->>'total') = ($1#>>'{counts,cancelled}') and (select bool_and(r->>'status' = 'cancelled' or (r->>'fc_cancelled')::boolean) from jsonb_array_elements($1->'rows') r))::text $q$),
                   pg_temp.err(pg_temp.usr('B', $q$ select public.fc_board(p_view => 'late')::text $q$), '%view must be one of%')), 'true true true true refused'),
       pg_temp.chk('B5a q = so-21106(대소문자 무시 · from 11-01) — 그 SO 의 예약 둘(49250480 취소 · 49253023 다시 예약)만',
         pg_temp.jq(pg_temp.o('B_so'), $q$ select concat_ws(' ', (select string_agg(r->>'transaction_number', ',' order by r->>'transaction_number') from jsonb_array_elements($1->'rows') r), $1->>'total', $1->>'from', $1->>'q') $q$), '49250480,49253023 2 2026-11-01 so-21106'),
       pg_temp.chk('B5b q = 둘째 운송장(tracking_numbers) · 거래 번호 — 그 예약 하나 · % 는 글자 그대로(0 줄) · 너무 긴 글은 거부',
         concat_ws(' ', pg_temp.jq(pg_temp.o('B_trk'), $q$ select concat_ws(',', $1->>'total', $1#>>'{rows,0,tracking_number}', $1#>>'{counts,all}') $q$), pg_temp.jq(pg_temp.o('B_tn'), $q$ select concat_ws(',', $1->>'total', $1#>>'{rows,0,tracking_number}') $q$),
                   pg_temp.jq(pg_temp.o('B_pct'), $q$ select $1->>'total' $q$), pg_temp.err(pg_temp.usr('B', format('select public.fc_board(p_q => %L)::text', repeat('x', 101))), '%too long%')), '1,ZZTRK-X2,1 1,ZZTRK-X4 0 refused'),
       pg_temp.chk('B5c q = 손님 이름 일부 — 복제 원본의 손님으로 찾으면 그 손님 줄만',
         pg_temp.jq(pg_temp.usr('B', format('select public.fc_board(p_q => %L, p_limit => 200)::text', (select left(cu.name, 8) from public.fc_shipment f join public.customer cu on cu.id = f.customer_id where f.id = pg_temp.id('src_f')::uuid))),
                    format($q$ select concat_ws(' ', ($1->>'total')::int >= 6, (select bool_and(r->>'customer_name' ilike %L) from jsonb_array_elements($1->'rows') r)) $q$, (select left(cu.name, 8) || '%' from public.fc_shipment f join public.customer cu on cu.id = f.customer_id where f.id = pg_temp.id('src_f')::uuid))), 't t'),
       pg_temp.chk('B6 쪽 넘김 — limit 7 로 끝까지 넘긴 줄 = limit 200 의 줄(순서까지) · 겹침 0 · total 은 쪽마다 같다 · limit 은 1 ~ 200 으로 다듬는다',
         (select concat_ws(' ', (string_agg(x.ids, ',' order by x.pg) = pg_temp.jq(pg_temp.o('B_all'), $q$ select (select string_agg(r->>'booking_id', ',' order by ord) from jsonb_array_elements($1->'rows') with ordinality t(r, ord)) $q$))::text, count(distinct x.total), bool_and(x.n <= 7))
            from (select g as pg, pg_temp.jq(v.v, $q$ select (select string_agg(r->>'booking_id', ',' order by ord) from jsonb_array_elements($1->'rows') with ordinality t(r, ord)) $q$) as ids, pg_temp.jq(v.v, $q$ select $1->>'total' $q$) as total, pg_temp.jq(v.v, $q$ select jsonb_array_length($1->'rows')::text $q$)::int as n
                    from generate_series(0, (pg_temp.jq(pg_temp.o('B_all'), $q$ select $1->>'total' $q$)::int - 1) / 7) g, lateral (select pg_temp.usr('B', format('select public.fc_board(p_limit => 7, p_offset => %s)::text', g * 7)) as v) v) x) || ' ' ||
         pg_temp.jq(pg_temp.usr('B', $q$ select public.fc_board(p_limit => 100000, p_offset => -5)::text $q$), $q$ select concat_ws(',', $1->>'limit', $1->>'offset') $q$) || ' ' || pg_temp.jq(pg_temp.usr('B', $q$ select public.fc_board(p_limit => 0)::text $q$), $q$ select concat_ws(',', $1->>'limit', jsonb_array_length($1->'rows')) $q$),
         'true 1 t 200,0 1,1'),
       pg_temp.chk('B7a 상세(32eee6e1…) freight_booking — 이벤트 8 이상 · 최신 먼저 · 칸 다섯 · money{charge · documents · lines} · row 는 보드와 같은 꼴',
         pg_temp.jq(pg_temp.o('B_det'), $q$ select concat_ws(' ', jsonb_array_length($1->'events') >= 8,
              (select bool_and(e->>'at' >= coalesce(nx->>'at', '')) from (select e, lead(e) over (order by ord) as nx from jsonb_array_elements($1->'events') with ordinality t(e, ord)) q),
              (select bool_and((select count(*) from jsonb_object_keys(e)) = 5 and e ?& array['type', 'at', 'city', 'region', 'message']) from jsonb_array_elements($1->'events') e),
              $1->>'can_see_money', $1#>>'{money,charge,state}', jsonb_array_length($1#>'{money,documents}') >= 1, jsonb_array_length($1#>'{money,lines}') >= 1,
              (select bool_and(d ?& array['id', 'type', 'number', 'doc_date', 'amount_cents', 'owing_cents']) from jsonb_array_elements($1#>'{money,documents}') d),
              (select bool_and(l ?& array['document_id', 'type', 'sub_type', 'amount_cents', 'message']) from jsonb_array_elements($1#>'{money,lines}') l),
              $1#>>'{row,transaction_number}', $1#>>'{row,money,charge_state}') $q$), 't t t true billed t t t t 49195658 billed'),
       pg_temp.chk('B7b 상세 sales — 이벤트는 같다 · money null · row.money null · 없는 예약은 거부',
         concat_ws(' ', pg_temp.jq(pg_temp.o('S_det'), $q$ select concat_ws(',', $1->>'can_see_money', jsonb_typeof($1->'money'), jsonb_typeof($1#>'{row,money}')) $q$),
                   (pg_temp.jq(pg_temp.o('S_det'), $q$ select ($1->'events')::text $q$) = pg_temp.jq(pg_temp.o('B_det'), $q$ select ($1->'events')::text $q$))::text,
                   pg_temp.err(pg_temp.usr('S', $q$ select public.fc_board_detail('00000000-0000-4000-8000-000000000000')::text $q$), '%not found%')), 'false,null,null true refused'),
       pg_temp.chk('W1 기본 창(⬜4) — from = 오늘 − 30 · to = 오늘 · X5(60 일 전 배송 끝)는 없다 · X6(60 일 전 · 운송 중)은 있다 · from 을 넓히면 X5 가 나온다 · from > to 는 거부',
         concat_ws(' ', pg_temp.jq(pg_temp.o('B_all'), $q$ select concat_ws(',', ($1->>'from')::date = public.ims_today() - 30, ($1->>'to')::date = public.ims_today(),
                          (select count(*) from jsonb_array_elements($1->'rows') r where r->>'tracking_number' = 'ZZTRK-X5'), (select count(*) from jsonb_array_elements($1->'rows') r where r->>'tracking_number' = 'ZZTRK-X6')) $q$),
                   pg_temp.jq(pg_temp.usr('B', format('select public.fc_board(p_from => %L, p_q => %L)::text', (public.ims_today() - 90)::text, 'ZZTRK-X5')), $q$ select concat_ws(',', $1->>'total', $1#>>'{rows,0,state_kind}', $1#>>'{rows,0,late}') $q$),
                   pg_temp.err(pg_temp.usr('B', $q$ select public.fc_board(p_from => '2026-12-01', p_to => '2026-11-01')::text $q$), '%must not be after%')), 't,t,0,1 1,delivered,false refused'),
       pg_temp.chk('L1 늦음(⬜1 · 짐작) — 영업일: 금 + 1 = 월 · 금 + 3 = 수 · 토 + 1 = 월 · 0 = 그날 · null · 61 = null / X2 의 expected_by = 예약일 + transit 영업일 · 방금 예약(X1)은 late f',
         concat_ws(' ', public.fc_add_business_days('2026-11-06', 1), public.fc_add_business_days('2026-11-06', 3), public.fc_add_business_days('2026-11-07', 1), public.fc_add_business_days('2026-11-06', 0),
                   coalesce(public.fc_add_business_days(null, 1)::text, 'n'), coalesce(public.fc_add_business_days('2026-11-06', 61)::text, 'n'),
                   pg_temp.jq(pg_temp.o('B_all'), $q$ select (select concat_ws(',', (r->>'expected_by')::date = public.fc_add_business_days(((r->>'booked_at')::timestamptz at time zone 'America/Toronto')::date, (r->>'transit_days')::int), r->>'pickup_date' is null, r->>'late')
                                                              from jsonb_array_elements($1->'rows') r where r->>'tracking_number' = 'ZZTRK-X2') $q$),
                   pg_temp.jq(pg_temp.o('B_all'), $q$ select (select r->>'late' from jsonb_array_elements($1->'rows') r where r->>'tracking_number' = 'ZZTRK-X1') $q$)), '2026-11-09 2026-11-11 2026-11-09 2026-11-06 n n t,t,true false'),
       pg_temp.chk('B8a 닫은 표 일곱 — 로그인한 직원(sales) · anon 은 못 읽는다(42501)',
         (select string_agg(pg_temp.err(pg_temp.usr('S', format('select count(*)::text from public.%I', t)), 'ERR 42501%') || '/' || pg_temp.err(pg_temp.anon(format('select count(*)::text from public.%I', t)), 'ERR 42501%'), ' ' order by t)
            from unnest(array['fc_booking', 'fc_call_log', 'fc_label', 'fc_quote', 'fc_quote_rate', 'fc_shipment', 'fc_shipment_so']) t),
         'refused/refused refused/refused refused/refused refused/refused refused/refused refused/refused refused/refused'),
       pg_temp.chk('B8b service_role 은 그대로 읽는다(EF sbGet) · fc_call_log 쓰기 그대로 · 돈 표 · 이벤트 표는 전부터 닫혀 있다',
         concat_ws(' ', (select string_agg(pg_temp.svc(format('select (count(*) >= 0)::text from public.%I', t)), ',' order by t) from unnest(array['fc_booking', 'fc_call_log', 'fc_label', 'fc_quote', 'fc_quote_rate', 'fc_shipment', 'fc_shipment_so']) t),
                   has_table_privilege('service_role', 'public.fc_call_log', 'insert'), has_table_privilege('service_role', 'public.fc_call_log', 'delete'),
                   pg_temp.err(pg_temp.usr('B', 'select count(*)::text from public.fc_track_event'), 'ERR 42501%'), pg_temp.err(pg_temp.usr('B', 'select count(*)::text from public.fc_document'), 'ERR 42501%')), 'true,true,true,true,true,true,true t t refused refused'),
       pg_temp.chk('B9 기존 창구는 닫은 뒤에도 그대로 — sales · fulfillment 직원: fc_booking_for_shipment · fc_shipment_for_so · fc_label_get · fc_pickup_attention_list',
         (select string_agg(concat_ws(',',
                   pg_temp.jq(pg_temp.usr(w, format('select public.fc_booking_for_shipment(%L)::text', pg_temp.id('src_f'))), format($q$ select (($1#>>'{current,id}') = %L and jsonb_array_length($1->'attempts') >= 1 and ($1->>'can_book') = 'false')::text $q$, pg_temp.id('src_b'))),
                   pg_temp.jq(pg_temp.usr(w, format('select public.fc_shipment_for_so(%L)::text', pg_temp.id('src_so'))), format($q$ select (($1#>>'{shipment,id}') = %L and jsonb_typeof($1->'orders') = 'array')::text $q$, pg_temp.id('src_f'))),
                   pg_temp.jq(pg_temp.usr(w, format('select public.fc_label_get(%L)::text', pg_temp.id('label'))), $q$ select ($1->>'path' like 'fc_label/%')::text $q$),
                   pg_temp.jq(pg_temp.usr(w, 'select public.fc_pickup_attention_list()::text'), $q$ select (($1->>'count')::int >= 0 and jsonb_typeof($1->'rows') = 'array')::text $q$)), ' ' order by w) from unnest(array['F', 'S']) w),
         'true,true,true,true true,true,true,true'),
       pg_temp.chk('S1 fc_ 표 열하나 — RLS 켬 · 정책 0 · anon · authenticated 권한 0 · service_role 권한 그대로',
         pg_temp.try($q$ select string_agg(c.relname || ' ' || c.relrowsecurity || ' ' || (select count(*) from pg_policy p where p.polrelid = c.oid) || ' ' ||
              (select coalesce(string_agg(g.grantee || ':' || g.privilege_type, ',' order by g.grantee, g.privilege_type), '-') from information_schema.role_table_grants g where g.table_schema = 'public' and g.table_name = c.relname and g.grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')), ' · ' order by c.relname)
              from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname like 'fc\_%' $q$),
         'fc_balance true 0 service_role:SELECT · fc_booking true 0 service_role:SELECT · fc_call_log true 0 service_role:DELETE,service_role:INSERT,service_role:SELECT · fc_document true 0 service_role:SELECT · fc_document_line true 0 service_role:SELECT · fc_label true 0 service_role:SELECT · fc_quote true 0 service_role:SELECT · fc_quote_rate true 0 service_role:SELECT · fc_shipment true 0 service_role:SELECT · fc_shipment_so true 0 service_role:SELECT · fc_track_event true 0 service_role:SELECT'),
       pg_temp.chk('S2 함수 권한(service_role · authenticated · anon) — 보드 · 상세는 authenticated(+ service_role 기본) · 속 함수 둘은 아무도 · 넷 다 정의 하나 · 보드 셋은 security definer',
         pg_temp.try($q$ select string_agg(p.proname || ' ' || has_function_privilege('authenticated', p.oid, 'execute')::text || has_function_privilege('anon', p.oid, 'execute')::text || has_function_privilege('public', p.oid, 'execute')::text || ' ' || p.prosecdef, ' · ' order by p.proname)
              from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fc_add_business_days', 'fc_board_row', 'fc_board', 'fc_board_detail') $q$),
         'fc_add_business_days falsefalsefalse false · fc_board truefalsefalse true · fc_board_detail truefalsefalse true · fc_board_row falsefalsefalse true'),
       pg_temp.chk('R1 REST 겹 ① — 새 함수 넷의 깊이 0 WHERE 없는 update · delete = 0 · 넷 다 쓰지 않는다(stable · immutable)',
         pg_temp.try($q$ select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc)::text || p.provolatile::text, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fc_add_business_days', 'fc_board_row', 'fc_board', 'fc_board_detail') $q$),
         'fc_add_business_days=0i,fc_board=0s,fc_board_detail=0s,fc_board_row=0s'),
       pg_temp.chk('G2 무접촉 — begin 앞의 fc_ 함수 49 개는 하나도 안 바뀌었다 · fc_ 함수는 53 · fc_booking 칸 수 그대로(41)',
         pg_temp.try($q$ select (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5 where p.oid is null) || ' ' ||
              (select count(*) from t_pre) || ' ' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fc\_%') || ' ' || (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'fc_booking') $q$), '(none) 49 53 41');

-- ── 보드 화면이 쓸 꼴(예 한 줄씩 · 실물) ──
\echo '── 꼴: fc_board (rows 는 첫 줄만 · accounts 는 첫 계정만)'
select jsonb_pretty((v::jsonb - 'rows' - 'accounts') || jsonb_build_object('rows', jsonb_build_array(v::jsonb#>'{rows,0}'), 'accounts', jsonb_build_array(v::jsonb#>'{accounts,0}'))) from t_out where k = 'B_50' and v not like 'ERR %';
\echo '── 꼴: fc_board_detail (events · documents · lines 는 첫 줄만 · row 는 위와 같은 꼴이라 뺐다)'
select jsonb_pretty((v::jsonb - 'row' - 'events' - 'money') || jsonb_build_object('events', jsonb_build_array(v::jsonb#>'{events,0}'),
         'money', jsonb_build_object('charge', v::jsonb#>'{money,charge}', 'documents', jsonb_build_array(v::jsonb#>'{money,documents,0}'), 'lines', jsonb_build_array(v::jsonb#>'{money,lines,0}')))) from t_out where k = 'B_det' and v not like 'ERR %';
\echo '── 꼴: counts(freight_booking · 가짜 여섯 포함) / counts(sales)'
select k, v::jsonb->'counts' as counts from t_out where k in ('B_all', 'S_all') and v not like 'ERR %' order by k;

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(가짜 행 모두 rollback) ──'
select n, case when ok then 'OK  ' else 'FAIL' end as r, label, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' · want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, (count(*) filter (where not ok) > 0 or count(*) filter (where ok) <> :EXPECT_OK) as bad from t_res \gset
\echo 'OK' :ok '· FAIL' :fail '· total' :total '· expect_ok' :EXPECT_OK
select round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — t 여야 한다(-v mig 로 돌렸을 때: 정책 수 · 함수 수가 begin 앞과 같다)'
select (select count(*) from public.fc_booking) = :n_bk0 and (select count(*) from public.ims_staff) = :n_staff0
   and (select max(version) from supabase_migrations.schema_migrations) = :'ver0'
   and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fc\_%' and p.proname not in ('fc_add_business_days', 'fc_board_row', 'fc_board', 'fc_board_detail')) = :n_fn0
   and (select count(*) from pg_policies where schemaname = 'public' and tablename like 'fc\_%') = :n_pol0 as rolled_back_clean;
\if :bad
do $$ begin raise exception 'fc_track_4_check: FAIL or OK count differs from EXPECT_OK — see the result table above'; end $$;
\endif
