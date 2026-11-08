-- supabase/tests/qbo_sync_3_2b_check.sql — qbo-sync-3-2b 검증 (2026-11-08 밤 · 판정 1092 · 1093 · 1097 · 1098 · 1101 · 1103 · §0 이견 1 ~ 10 · ⬜1 ~ ⬜8 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] begin → (-v mig 면 \i) → 가짜 재료(DO 하나) → S 구조 · S1 장 → 일감 → claim → 몸(JE) → done → sent · S2 늦은 사건 · S9 보류 · S3 fail → 뒤 장 blocked → retry → done(mismatch) · S6 skip → void → 뒤 장 차액 · S5 재생성 hold → preview → release → rebuild 장 · S8 Entity 짝 없음 → needs → blocked → 손님 done → 풀림 · S4 unknown → resolve 두 갈래 · S7 다른 kind 의 claim 은 cost_day 를 안 집는다 · K 열쇠 · W WHERE 정적 · G grant · md5 · 시퀀스 → rollback → Z
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261108224000_qbo_sync_3_2b_cost_day_jobs.sql -f supabase/tests/qbo_sync_3_2b_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(시험 · 확인 같다 · S0b 한 검사만 갈래마다 다르게 본다)
--   ⚠️ 가짜 재료만 — inv_config qbo_cost_since 를 트랜잭션 안에서 2026-01-05 로 옮긴다(실제 사건은 전부 2026-08-21 뒤 → 셈에 0 · 실제 장 · 일감 · 사건 무접촉) · 가짜 레이어 2 · 소진 9 · 원장 3 · 조정 2 · 손님 1 · 인보이스 1(replica · FK 끔) · 직원 2 — 전부 explicit id(overriding system value) → 시퀀스 무접촉 · 전부 rollback
--   ⚠️ 공개 레포 — 상호를 찍지 않는다 · S5 hold_all 은 realm 의 pending 장 전부를 hold 로 둔다(지금 실제 장 0 · cron 등록 뒤 확인 갈래를 돌리면 실제 pending 장도 rollback 안에서 hold → pending 을 지난다 — 쓰기 결과는 rollback)
\set ON_ERROR_STOP on
\pset pager off
\set EXPECT_OK 60
select (select value from public.inv_config where key = 'db_role') as db_role;
select (select realm_id from public.qbo_connection where singleton) as realm \gset

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create temp table t_ids (k text primary key, v text);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns text language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
  return case when p_got is not distinct from p_want then 'OK   ' else 'FAIL ' end || p_label || case when p_got is not distinct from p_want then '' else format(' — got %s · want %s', coalesce(p_got, '(null)'), coalesce(p_want, '(null)')) end;
end $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
$$;
create function pg_temp.svc(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb; v_claims text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute p_sql into v;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return v;
end $$;
create function pg_temp.id(p_k text) returns text language sql as $$ select v from t_ids where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_ids values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
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

-- ── 기준(begin 앞) ──
select (select count(*) from public.ims_staff) as pre_staff, (select count(*) from public.inv_config) as pre_cfg, (select value from public.inv_config where key = 'qbo_cost_since') as pre_since, (select value from public.inv_config where key = 'qbo_cost_adjust_hold_over') as pre_thr,
       (select count(*) from public.inv_layer) as pre_layer, (select count(*) from public.inv_layer_consume) as pre_cons, (select count(*) from public.inv_ledger) as pre_ledger, (select count(*) from public.inv_adjust) as pre_adj,
       (select coalesce(min(id), 0) from public.inv_layer_consume) as pre_epoch,
       (select last_value || ':' || is_called from public.inv_layer_consume_id_seq) as pre_seq_cons, (select last_value || ':' || is_called from public.inv_layer_id_seq) as pre_seq_layer, (select last_value || ':' || is_called from public.inv_ledger_id_seq) as pre_seq_ledger,
       (select count(*) from public.qbo_job) as pre_jobs, (select count(*) from public.qbo_cost_sheet) as pre_sheets, (select count(*) from public.qbo_cost_sent) as pre_sent,
       (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc')) as pre_six,
       (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_fail', 'qbo_job_skip', 'qbo_job_unknown', 'qbo_job_unknown_list')) as pre_four,
       clock_timestamp() as t_begin \gset
\echo '── 기준: staff' :pre_staff '· inv_layer' :pre_layer '· consume' :pre_cons '(min id' :pre_epoch ') · ledger' :pre_ledger '· jobs' :pre_jobs '· sheets' :pre_sheets '· realm' :realm

begin;
set local statement_timeout = '600s';
set local lock_timeout = '5s';
\if :{?mig}
\echo '── 시험 적용:' :mig
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset

-- ── 가짜 재료(DO 하나) — since 2026-01-05 · 문턱 100 · 레이어 2 · 소진 6(+2 뒤에) · 원장 3 · 조정 2 · 손님 1 · 인보이스 1 · 직원 2 ──
do $$
declare v_l bigint := (select max(id) from public.inv_layer); v_c bigint := (select max(id) from public.inv_layer_consume); v_g bigint := (select max(id) from public.inv_ledger);
        v_tor uuid := (select id from public.ref_warehouse where name = 'Asung Trading Inc.'); v_edm uuid := (select id from public.ref_warehouse where name = 'Asung - Edmonton');
        v_cad uuid := (select id from public.ref_currency where code = 'CAD'); v_cust uuid := gen_random_uuid(); v_inv uuid := gen_random_uuid(); v_st uuid := gen_random_uuid(); v_nk uuid := gen_random_uuid();
begin
  update public.inv_config set value = '2026-01-05' where key = 'qbo_cost_since';
  update public.inv_config set value = '100' where key = 'qbo_cost_adjust_hold_over';
  perform pg_temp.put('l_tor', (v_l + 1)::text); perform pg_temp.put('l_edm', (v_l + 2)::text); perform pg_temp.put('c_base', v_c::text); perform pg_temp.put('g_base', v_g::text);
  insert into public.inv_layer (id, sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source) overriding system value values
    (v_l + 1, 'ZZ-SKU-32B', 'Asung Trading Inc.', 'baseline', null, null, null, date '2026-01-01', false, 10000, 1, 'manual'),
    (v_l + 2, 'ZZ-SKU-32B', 'Asung - Edmonton',   'baseline', null, null, null, date '2026-01-01', false, 10000, 1, 'manual');
  insert into public.inv_layer_consume (id, layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) overriding system value values
    (v_c + 1, v_l + 1, 'sale',       'SO-20008',  'zz-1', 'sale_out',        date '2026-01-05', 25,  1, 25,  'sale'),
    (v_c + 2, v_l + 1, 'sale',       'SO-20009',  'zz-2', 'sale_out',        date '2026-01-05', 10,  1, 10,  'sale'),
    (v_c + 3, v_l + 1, 'adjustment', 'ADJ-ZZ001', 'zz-3', 'adjust_existing', date '2026-01-05', 150, 1, 150, 'adjust_out'),
    (v_c + 4, v_l + 2, 'adjustment', 'ADJ-ZZ002', 'zz-4', 'adjust_existing', date '2026-01-05', 20,  1, 20,  'adjust_out'),
    (v_c + 5, v_l + 1, 'sale',       'SO-ZZ008',  'zz-5', 'sale_out',        date '2026-01-06', 7,   1, 7,   'sale'),
    (v_c + 6, v_l + 2, 'adjustment', 'ADJ-ZZ002', 'zz-6', 'adjust_existing', date '2026-01-06', 3,   1, 3,   'adjust_out');
  insert into public.inv_ledger (id, occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, amount, source) overriding system value values
    (v_g + 1, date '2026-01-06', 2, 'ZZ-SKU-32B', 'Asung Trading Inc.', '', -7,   'sale_out',        'sale',       'SO-ZZ008',  'zz-5', null, 'ims'),
    (v_g + 2, date '2026-01-05', 1, 'ZZ-SKU-32B', 'Asung Trading Inc.', '', -150, 'adjust_existing', 'adjustment', 'ADJ-ZZ001', 'zz-3', null, 'ims'),
    (v_g + 3, date '2026-01-05', 1, 'ZZ-SKU-32B', 'Asung - Edmonton',   '', -20,  'adjust_existing', 'adjustment', 'ADJ-ZZ002', 'zz-4', null, 'ims');
  insert into public.inv_adjust (adjust_number, status, warehouse_id, warehouse, note) values ('ADJ-ZZ001', 'draft', v_tor, 'Asung Trading Inc.', 'ZZ 3-2b test'), ('ADJ-ZZ002', 'draft', v_edm, 'Asung - Edmonton', 'ZZ 3-2b test');
  set local session_replication_role = replica;
  insert into public.customer (id, name, source, is_active, currency_id, currency_code) values (v_cust, 'ZZ Cost Customer 3-2b', 'manual', true, v_cad, 'CAD');
  insert into public.so_invoice (id, invoice_number, status, bill_to_customer_id, issued_on, currency_id, kind) values (v_inv, '99999901', 'issued', v_cust, date '2026-01-06', v_cad, 'sale');
  insert into public.so_invoice_order (invoice_id, so_id, so_number, customer_id, tax_rule_id, tax_rule, rate_pct, tax_source) values (v_inv, gen_random_uuid(), 'SO-ZZ008', v_cust, gen_random_uuid(), 'ZZ', 0, 'manual');
  set local session_replication_role = origin;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (v_st, 'zz-qbo-sync-3-2b@test.invalid', 'ZZ qbo-sync-3-2b bookkeeper', 'manager', '["ims", "qbo"]', '{}'), (v_nk, 'zz-qbo-sync-3-2b-nokey@test.invalid', 'ZZ qbo-sync-3-2b no key', 'worker', '["ims"]', '{}');
  perform pg_temp.put('cust', v_cust::text); perform pg_temp.put('st_uid', v_st::text); perform pg_temp.put('nk_uid', v_nk::text);
end $$;
select pg_temp.id('st_uid') as st_uid, pg_temp.id('nk_uid') as nk_uid \gset

-- ── S 구조 ──
do $$
declare v_realm text := (select realm_id from public.qbo_connection where singleton);
begin
  perform pg_temp.chk('S1 qbo_job CHECK: kind + cost_day · ims_kind + cost_sheet · pair cost_day → cost_sheet · qbo_txn kind + cost_sheet · type + JournalEntry · pair',
    (select pg_get_constraintdef(oid) like '%''cost_day''%' from pg_constraint where conname = 'qbo_job_kind_ck')::text || (select pg_get_constraintdef(oid) like '%''cost_sheet''%' from pg_constraint where conname = 'qbo_job_ims_kind_ck')::text
    || (select pg_get_constraintdef(oid) like '%''cost_day''::text THEN ''cost_sheet''%' from pg_constraint where conname = 'qbo_job_pair_ck')::text
    || (select pg_get_constraintdef(oid) like '%''cost_sheet''%' from pg_constraint where conname = 'qbo_txn_kind_ck')::text || (select pg_get_constraintdef(oid) like '%''JournalEntry''%' from pg_constraint where conname = 'qbo_txn_type_ck')::text
    || (select pg_get_constraintdef(oid) like '%''cost_sheet''::text THEN ''JournalEntry''%' from pg_constraint where conname = 'qbo_txn_pair_ck')::text, 'truetruetruetruetruetrue');
  perform pg_temp.chk('S2 트리거 qbo_job_cost_sheet_sync: AFTER UPDATE OF state · FOR EACH ROW · WHEN kind = cost_day',
    (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.qbo_job'::regclass and tgname = 'qbo_job_cost_sheet_sync'),
    'CREATE TRIGGER qbo_job_cost_sheet_sync AFTER UPDATE OF state ON public.qbo_job FOR EACH ROW WHEN ((new.kind = ''cost_day''::text)) EXECUTE FUNCTION qbo_job_cost_sheet_sync()');
  perform pg_temp.chk('S3 새 함수 12 · 재발행 여섯 같은 이름 하나씩',
    (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_cost_sheet_ims_id', 'qbo_cost_sheet_id_for_job', 'qbo_cost_day_body', 'qbo_cost_sheet_queue_one', 'qbo_cost_sheet_queue', 'qbo_cost_queue_due', 'qbo_job_cost_sheet_sync', 'qbo_cost_hold_all', 'qbo_cost_rebuild_calc', 'qbo_cost_rebuild_preview', 'qbo_cost_rebuild_release', 'qbo_cost_sheet_resolve'))
    || ' ' || (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc')), '12 6');
  perform pg_temp.chk('S4 ims_id 꼴: day 「2026-01-05|TOR」 · rebuild 「2026-01-05|TOR|rebuild」', public.qbo_cost_sheet_ims_id(date '2026-01-05', 'TOR', 'day') || ' ' || public.qbo_cost_sheet_ims_id(date '2026-01-05', 'TOR', 'rebuild'), '2026-01-05|TOR 2026-01-05|TOR|rebuild');
  perform pg_temp.chk('S5 재료: since 2026-01-05 → 기대값에 실제 사건 0 · 가짜 열쇠만(TOR 01-05: SO 2 send + ADJ 1 hold · EDM 01-05: ADJ 1 send)',
    (select string_agg(e.wh_code || ':' || e.key_kind || ':' || e.doc_key || ':' || e.status || ':' || e.cents::text, ' ' order by e.wh_code, e.doc_key) from public.qbo_cost_expected(date '2026-01-05', null, v_realm) e),
    'EDM:ADJ:ADJ-ZZ002:send:2000 TOR:ADJ:ADJ-ZZ001:hold:15000 TOR:SO:SO-20008:send:2500 TOR:SO:SO-20009:send:1000');
end $$;

-- ── S1 장 → 일감 → claim → 몸(JE) → done → sent · S2 늦은 사건 · S9 보류 ──
do $$
declare v_realm text := (select realm_id from public.qbo_connection where singleton); v_b jsonb; v_q jsonb; v_c jsonb; v_j jsonb; v_s public.qbo_cost_sheet%rowtype; v_job public.qbo_job%rowtype; v_p jsonb; v_d jsonb; v_l jsonb;
begin
  v_b := public.qbo_cost_sheet_build(date '2026-01-05', 'TOR', v_realm);
  perform pg_temp.chk('S1a 장 만들기(3-2a 그대로): built · 열쇠 2 · 줄 2 · 보류 1 · 차변 3500 · pending', (v_b->>'built') || ' ' || (v_b->>'keys') || ' ' || (v_b->>'lines') || ' ' || (v_b->>'hold_keys') || ' ' || (v_b->>'debit_cents') || ' ' || (v_b->>'state'), 'true 2 2 1 3500 pending');
  perform pg_temp.put('tor05', v_b->>'sheet_id');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  perform pg_temp.chk('S1b 일감 세우기 거부: 장 없는 날 · 창고 틀림', (pg_temp.try($q$select public.qbo_cost_sheet_queue(date '2026-01-04', 'TOR')::text$q$) ~ 'There is no cost day sheet')::text || ' ' || (pg_temp.try($q$select public.qbo_cost_sheet_queue(date '2026-01-05', 'XX')::text$q$) ~ 'TOR \| EDM')::text, 'true true');
  v_q := public.qbo_cost_sheet_queue(date '2026-01-05', 'TOR');
  perform pg_temp.put('tor05_job', v_q->>'job_id');
  select * into v_job from public.qbo_job j where j.id = (v_q->>'job_id')::uuid;
  select * into v_s from public.qbo_cost_sheet s where s.id = (v_q->>'sheet_id')::uuid;
  perform pg_temp.chk('S1c 일감: kind cost_day · ims_kind cost_sheet · ims_id 2026-01-05|TOR · queued · 장.job_id 잇김 · 다시 부르면 existing', v_job.kind || ' ' || v_job.ims_kind || ' ' || v_job.ims_id || ' ' || v_job.state || ' ' || (v_s.job_id = v_job.id)::text || ' ' || (public.qbo_cost_sheet_queue(date '2026-01-05', 'TOR')->>'existing'), 'cost_day cost_sheet 2026-01-05|TOR queued true true');
  v_p := public.qbo_job_preview(v_job.id);
  perform pg_temp.chk('S1d preview(열쇠): sendable true · doc_number · 줄 3 · hold null · empty false · needs 0', (v_p->>'sendable') || ' ' || (v_p->>'doc_number') || ' ' || (v_p->>'line_count') || ' ' || coalesce(v_p->>'hold', 'null') || ' ' || (v_p->>'empty') || ' ' || jsonb_array_length(v_p->'needs')::text, 'true COGS-20260105-TOR 3 null false 0');
  perform pg_temp.as_user(null);
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  v_j := v_c->'jobs'->0;
  perform pg_temp.chk('S1e claim(kinds cost_day): claimed 1 · 몸 DocNumber · TxnDate · PrivateNote · 줄 3 · 차 = 대 3500 · 보낸 몫 행 2 · 지문 3500|…',
    (v_c->>'claimed') || ' ' || (v_j->'body'->>'DocNumber') || ' ' || (v_j->'body'->>'TxnDate') || ' ' || (v_j->'body'->>'PrivateNote') || ' ' || jsonb_array_length(v_j->'body'->'Line')::text || ' ' || (v_j->'totals'->>'debit_cents') || '=' || (v_j->'totals'->>'credit_cents') || ' ' || (v_j->'totals'->>'line_count') || ' ' || split_part(v_j->>'fingerprint', '|', 1),
    '1 COGS-20260105-TOR 2026-01-05 IMS cost day 2026-01-05 TOR 3 3500=3500 3 3500');
  v_l := v_j->'body'->'Line';
  perform pg_temp.chk('S1f JE 줄(1097 · 1103): #58 Debit 25.00 Entity Customer 1889 「SO-20008」 · #58 Debit 10.00 Entity 10739 · #59 Credit 35.00 「Inventory TOR」 · AccountRef 는 qbo_link 번호 · DepartmentRef 없음',
    (select string_agg((l->>'Description') || ':' || (l->'JournalEntryLineDetail'->>'PostingType') || ':' || (l->>'Amount') || ':' || coalesce(l->'JournalEntryLineDetail'->'Entity'->'EntityRef'->>'value', '-') || ':' || coalesce(l->'JournalEntryLineDetail'->'Entity'->>'Type', '-'), ' ' order by o) from jsonb_array_elements(v_l) with ordinality as x(l, o))
    || ' ' || (select bool_and((l->'JournalEntryLineDetail'->'AccountRef'->>'value') ~ '^[0-9]+$' and l->'JournalEntryLineDetail' ? 'DepartmentRef' = false and l->>'DetailType' = 'JournalEntryLineDetail') from jsonb_array_elements(v_l) l)::text,
    'SO-20008:Debit:25.00:1889:Customer SO-20009:Debit:10.00:10739:Customer Inventory TOR:Credit:35.00:-:- true');
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('tor05')::uuid;
  perform pg_temp.chk('S1g 장 sending(트리거) · 행 2(2500 + 1000 · ADJ 없음 = 보류는 몸에 안 실림 · S9) · 일감 sending · claim 결과에 cost_day 가 need_jobs 없이',
    v_s.state || ' ' || (select count(*)::text || ':' || sum(t.cents)::text || ':' || count(*) filter (where t.key_kind = 'ADJ')::text from public.qbo_cost_sent t where t.sheet_id = v_s.id) || ' ' || (select j.state from public.qbo_job j where j.id = v_s.job_id) || ' ' || jsonb_array_length(v_c->'need_jobs')::text, 'sending 2:3500:0 sending 0');
  -- S2 늦은 사건: claim 뒤 · done 전에 같은 날(01-05) SO-20008 에 5.00 이 더 적힌다
  insert into public.inv_layer_consume (id, layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) overriding system value
  values (pg_temp.id('c_base')::bigint + 7, pg_temp.id('l_tor')::bigint, 'sale', 'SO-20008', 'zz-7', 'sale_out', date '2026-01-05', 5, 1, 5, 'sale');
  v_d := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'ZZ-JE-1', 'COGS-20260105-TOR', null, null, null, null, 35.00)$q$, v_job.id));
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('tor05')::uuid;
  perform pg_temp.chk('S2a done(TotalAmt 35.00): sent · mismatch null · 장 sent · qbo_id ZZ-JE-1 · sent_at · 행 그대로 2(늦은 5.00 은 안 섞임 · 이견 9) · qbo_txn JournalEntry COGS-20260105-TOR 35.00',
    (v_d->>'state') || ' ' || coalesce(v_d->>'mismatch', 'null') || ' ' || v_s.state || ' ' || v_s.qbo_id || ' ' || (v_s.sent_at is not null)::text || ' ' || (select count(*)::text || ':' || sum(t.cents)::text from public.qbo_cost_sent t where t.sheet_id = v_s.id)
    || ' ' || (select t.qbo_type || ':' || t.doc_number || ':' || t.total_amt::text || ':' || coalesce(t.mismatch, 'null') from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'cost_sheet' and t.ims_id = '2026-01-05|TOR'),
    'sent null sent ZZ-JE-1 true 2:3500 JournalEntry:COGS-20260105-TOR:35.00:null');
  perform pg_temp.chk('S2b 다음 날(01-06 TOR) 셈: baseline sent · SO-20008 차액 +500 「(adj. of 2026-01-05)」 first_sent_on 01-05 · SO-ZZ008 700(손님 있음 · QBO 짝 없음) · ADJ-ZZ001 hold 15000',
    (select string_agg(c.key_kind || ':' || c.doc_key || ':' || c.status || ':' || c.diff_cents::text || ':' || c.label || ':' || coalesce(c.first_sent_on::text, '-') || ':' || (c.entity_customer_id is not null)::text || ':' || coalesce(c.entity_qbo_id, '-') || ':' || c.baseline, ' ' order by c.key_kind, c.doc_key) from public.qbo_cost_sheet_calc(date '2026-01-06', 'TOR', v_realm) c),
    'ADJ:ADJ-ZZ001:hold:15000:ADJ-ZZ001:-:false:-:sent SO:SO-20008:send:500:SO-20008 (adj. of 2026-01-05):2026-01-05:true:1889:sent SO:SO-ZZ008:send:700:SO-ZZ008:-:true:-:sent');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_l := public.qbo_job_list('sent', array['cost_day'], null, null, null, 50, 0);
  perform pg_temp.chk('S2c qbo_job_list(kinds cost_day · sent): total 1 · ims_name 「COGS-20260105-TOR · Cost day 2026-01-05 TOR」 · doc_status sent · txn ZZ-JE-1 35.00', (v_l->>'total') || ' ' || (v_l->'rows'->0->>'ims_name') || ' ' || (v_l->'rows'->0->>'doc_status') || ' ' || (v_l->'rows'->0->>'txn_qbo_id') || ' ' || (v_l->'rows'->0->>'txn_total_amt'), '1 COGS-20260105-TOR · Cost day 2026-01-05 TOR sent ZZ-JE-1 35.00');
  -- S9 보류(1099 · 문턱 100): 결정 send → 다음 장(01-06)에 보통 줄로
  perform public.qbo_cost_hold_decide('ADJ', 'ADJ-ZZ001', 'send', 'ZZ 3-2b: counted, send it');
  perform pg_temp.as_user(null);
  perform pg_temp.chk('S9 hold_decide send → 01-06 TOR 셈에서 ADJ-ZZ001 send 15000(_1150040010_/_59_)', (select c.status || ':' || c.diff_cents::text || ':' || c.acct_a || '/' || c.acct_b from public.qbo_cost_sheet_calc(date '2026-01-06', 'TOR', v_realm) c where c.doc_key = 'ADJ-ZZ001'), 'send:15000:_1150040010_/_59_');
end $$;

-- ── S3 fail → 뒤 장 blocked(차례) → retry → done(mismatch 경고) → 뒤 장 풀림 · S6 skip → void → 뒤 장 차액 ──
do $$
declare v_realm text := (select realm_id from public.qbo_connection where singleton); v_b jsonb; v_q jsonb; v_c jsonb; v_d jsonb; v_r jsonb; v_s public.qbo_cost_sheet%rowtype; v_j05 uuid; v_j06 uuid; v_req1 uuid; v_req2 uuid;
begin
  v_b := public.qbo_cost_sheet_build(date '2026-01-05', 'EDM', v_realm);
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_q := public.qbo_cost_sheet_queue(date '2026-01-05', 'EDM'); v_j05 := (v_q->>'job_id')::uuid; perform pg_temp.put('edm05', v_q->>'sheet_id'); perform pg_temp.put('edm05_job', v_j05::text);
  perform pg_temp.as_user(null);
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  perform pg_temp.chk('S3a EDM 01-05: 장 열쇠 1 차변 2000 · claim → 줄 2(_1150040010_ Debit 20.00 · #59 Credit 20.00) · 행 1',
    (v_b->>'keys') || ' ' || (v_b->>'debit_cents') || ' ' || (v_c->>'claimed') || ' ' || (select string_agg((l->'JournalEntryLineDetail'->>'PostingType') || ':' || (l->>'Amount') || ':' || (l->>'Description'), ' ' order by o) from jsonb_array_elements(v_c->'jobs'->0->'body'->'Line') with ordinality as x(l, o)) || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = pg_temp.id('edm05')::uuid),
    '1 2000 1 Debit:20.00:ADJ-ZZ002 Credit:20.00:Inventory EDM 1');
  v_d := pg_temp.svc(format($q$select public.qbo_job_fail(%L::uuid, 'ZZ 3-2b: simulated 400 from QuickBooks')$q$, v_j05));
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('edm05')::uuid;
  perform pg_temp.chk('S3b fail: 일감 failed · 장 failed(트리거) · 행 0(지움) · qbo_id null', (v_d->>'state') || ' ' || v_s.state || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = v_s.id) || ' ' || coalesce(v_s.qbo_id, 'null'), 'failed failed 0 null');
  v_b := public.qbo_cost_sheet_build(date '2026-01-06', 'EDM', v_realm);
  perform pg_temp.chk('S3c EDM 01-06 장: baseline pending:2026-01-05(앞 장 failed = P) → 열쇠 1 차액 300(2300 − 2000)', (v_b->>'keys') || ' ' || (v_b->>'debit_cents') || ' ' || (select min(c.baseline) from public.qbo_cost_sheet_calc(date '2026-01-06', 'EDM', v_realm) c), '1 300 pending:2026-01-05');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_q := public.qbo_cost_sheet_queue(date '2026-01-06', 'EDM'); v_j06 := (v_q->>'job_id')::uuid; perform pg_temp.put('edm06', v_q->>'sheet_id'); perform pg_temp.put('edm06_job', v_j06::text);
  perform pg_temp.as_user(null);
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('edm06')::uuid;
  perform pg_temp.chk('S3d 뒤 장 claim: 앞 장 failed → blocked_for_invoice 1 · 보낸 줄 0 · 일감 blocked · blocked_by = 앞 장 일감 · warning 글 · 장 pending(트리거) · TOR 는 무관(sent 그대로)',
    (v_c->>'blocked_for_invoice') || ' ' || jsonb_array_length(v_c->'jobs')::text || ' ' || (select j.state || ' ' || (j.blocked_by = v_j05)::text || ' ' || (j.warning ~ '^waiting for COGS-20260105-EDM \(failed\) to reach QuickBooks first')::text from public.qbo_job j where j.id = v_j06) || ' ' || v_s.state || ' ' || (select s.state from public.qbo_cost_sheet s where s.id = pg_temp.id('tor05')::uuid),
    '1 0 blocked true true pending sent');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  select j.request_id into v_req1 from public.qbo_job j where j.id = v_j05;
  v_r := public.qbo_job_retry(v_j05, null);
  select j.request_id into v_req2 from public.qbo_job j where j.id = v_j05;
  perform pg_temp.chk('S3e retry(failed · note 없이 됨): queued · was failed · request_id 새로 · 장 pending', (v_r->>'state') || ' ' || (v_r->>'was') || ' ' || (v_req1 <> v_req2)::text || ' ' || (select s.state from public.qbo_cost_sheet s where s.id = pg_temp.id('edm05')::uuid), 'queued failed true pending');
  perform pg_temp.as_user(null);
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  perform pg_temp.chk('S3f claim: 앞 장만 잡힘(1 · 뒤 장은 아직 blocked · unblocked 0)', (v_c->>'claimed') || ' ' || jsonb_array_length(v_c->'jobs')::text || ' ' || (v_c->>'unblocked') || ' ' || (v_c->'jobs'->0->>'doc_number'), '1 1 0 COGS-20260105-EDM');
  v_d := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'ZZ-JE-E5', 'COGS-20260105-EDM', null, null, null, null, 20.01)$q$, v_j05));
  perform pg_temp.chk('S3g done(TotalAmt 20.01 ≠ 20.00): sent 이되 mismatch 글(942 꼴) · warning 에 · qbo_txn mismatch · done 이 뒤 장을 푼다(unblocked 1)', (v_d->>'state') || ' ' || (v_d->>'unblocked') || ' ' || ((v_d->>'mismatch') ~ '^QuickBooks total 20.01 differs from IMS 20.00 — check journal entry COGS-20260105-EDM')::text || ' ' || (select (j.warning ~ 'differs')::text from public.qbo_job j where j.id = v_j05) || ' ' || (select (t.mismatch is not null)::text from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'cost_sheet' and t.ims_id = '2026-01-05|EDM'), 'sent 1 true true true');
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('edm06')::uuid;
  perform pg_temp.chk('S3h claim: 풀린 뒤 장을 잡는다(unblocked 0 — done 이 이미 풀었다) · 차변 300 · 장 sending · 행 1(ADJ-ZZ002 300 · 「(adj. of 2026-01-05)」)',
    (v_c->>'unblocked') || ' ' || (v_c->>'claimed') || ' ' || (v_c->'jobs'->0->'totals'->>'debit_cents') || ' ' || v_s.state || ' ' || (select count(*)::text || ':' || sum(t.cents)::text from public.qbo_cost_sent t where t.sheet_id = v_s.id) || ' ' || (v_c->'jobs'->0->'body'->'Line'->0->>'Description'), '0 1 300 sending 1:300 ADJ-ZZ002 (adj. of 2026-01-05)');
  -- 뒤 장 EDM 01-07(가짜 사건 2.00 @01-07)을 지금 세운다 — 앞 장 EDM 01-06 이 sending 이라 claim 은 wait_job → blocked(② 확장 시험의 바탕)
  insert into public.inv_layer_consume (id, layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) overriding system value
  values (pg_temp.id('c_base')::bigint + 8, pg_temp.id('l_edm')::bigint, 'adjustment', 'ADJ-ZZ002', 'zz-8', 'adjust_existing', date '2026-01-07', 2, 1, 2, 'adjust_out');
  v_b := public.qbo_cost_sheet_build(date '2026-01-07', 'EDM', v_realm);
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_q := public.qbo_cost_sheet_queue(date '2026-01-07', 'EDM'); perform pg_temp.put('edm07_job', v_q->>'job_id'); perform pg_temp.put('edm07', v_q->>'sheet_id');
  perform pg_temp.as_user(null);
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  perform pg_temp.chk('S3i EDM 01-07 장(앞 장 sending 이라 보낸 몫으로 셈 → 차액 200 = 2500 − 2300) · claim → 앞 장(sending) 뒤에 선다(blocked_by = EDM 01-06 일감)',
    (v_b->>'keys') || ' ' || (v_b->>'debit_cents') || ' ' || (v_c->>'blocked_for_invoice') || ' ' || (select j.state || ':' || (j.blocked_by = v_j06)::text from public.qbo_job j where j.id = pg_temp.id('edm07_job')::uuid), '1 200 1 blocked:true');
  -- S6 skip: fail 뒤 skip → void · 행 0 · 뒤 장(01-07) 차액이 그 몫을 담는다 · ② 확장이 skipped 부모의 cost_day 자식을 푼다
  v_d := pg_temp.svc(format($q$select public.qbo_job_fail(%L::uuid, 'ZZ 3-2b: simulated 400')$q$, v_j06));
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  perform pg_temp.chk('S6a retry 거부: skipped 아닌 failed 일감은 되돌리기 note 불필요지만 뒤 장 규칙은 통과 · skip 은 note 필수', (pg_temp.try(format($q$select public.qbo_job_skip(%L::uuid, '')::text$q$, v_j06)) ~ 'note is required')::text, 'true');
  v_r := public.qbo_job_skip(v_j06, 'ZZ 3-2b: QuickBooks has nothing for this day — let the next day carry it');
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('edm06')::uuid;
  perform pg_temp.chk('S6b skip: 일감 skipped · 장 void(트리거) · 행 0 · resolved_at · note 「skipped: …」', (v_r->>'state') || ' ' || v_s.state || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = v_s.id) || ' ' || (v_s.resolved_at is not null)::text || ' ' || (v_s.note ~ 'skipped: ZZ 3-2b')::text, 'skipped void 0 true true');
  perform pg_temp.chk('S6c retry(skipped cost_day) 는 note 필수', (pg_temp.try(format($q$select public.qbo_job_retry(%L::uuid, null)::text$q$, v_j06)) ~ 'note is required')::text, 'true');
  perform pg_temp.as_user(null);
  perform pg_temp.chk('S6d 뒤 장(01-07 EDM) 셈: void 는 P 도 보낸 몫도 아니다 → baseline sent · ADJ-ZZ002 차액 500(= 2500 − 2000 · void 의 300 을 담는다) 「(adj. of 2026-01-05)」',
    (select string_agg(c.doc_key || ':' || c.diff_cents::text || ':' || c.label || ':' || c.baseline, ' ') from public.qbo_cost_sheet_calc(date '2026-01-07', 'EDM', v_realm) c), 'ADJ-ZZ002:500:ADJ-ZZ002 (adj. of 2026-01-05):sent');
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('edm07')::uuid;
  perform pg_temp.chk('S6e claim: ② 확장(cost_day · 부모 skipped)이 EDM 01-07 을 푼다(unblocked 1) · 몸은 void 장을 건너뛰고 01-05(sent) 뒤로 → 잡힘 · 차변 500 · 행 1 · 장 sending',
    (v_c->>'unblocked') || ' ' || (v_c->>'claimed') || ' ' || (v_c->'jobs'->0->'totals'->>'debit_cents') || ' ' || (select count(*)::text || ':' || sum(t.cents)::text from public.qbo_cost_sent t where t.sheet_id = v_s.id) || ' ' || v_s.state, '1 1 500 1:500 sending');
  v_d := pg_temp.svc(format($q$select public.qbo_job_fail(%L::uuid, 'ZZ 3-2b: put back for S7')$q$, pg_temp.id('edm07_job')));
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_r := public.qbo_job_retry(pg_temp.id('edm07_job')::uuid, null);
  perform pg_temp.as_user(null);
  perform pg_temp.chk('S6f EDM 01-07 fail → retry → queued(S7 재료) · 행 0', (v_r->>'state') || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = pg_temp.id('edm07')::uuid), 'queued 0');
end $$;

-- ── S5 재생성 흉내(epoch 작게) → claim 거부 · hold · retry 거부 · preview → release → rebuild 장 → 멈춘 장 다시 · S8 Entity 짝 없음 → needs → blocked → 손님 done → 풀림 ──
do $$
declare v_realm text := (select realm_id from public.qbo_connection where singleton); v_b jsonb; v_q jsonb; v_c jsonb; v_d jsonb; v_p jsonb; v_rp jsonb; v_rl jsonb; v_s public.qbo_cost_sheet%rowtype; v_rs public.qbo_cost_sheet%rowtype; v_j06 uuid; v_jr uuid; v_jc uuid; v_epoch bigint := (select min(id) from public.inv_layer_consume); v_req1 uuid; v_req2 uuid; v_l jsonb;
begin
  v_b := public.qbo_cost_sheet_build(date '2026-01-06', 'TOR', v_realm);
  perform pg_temp.put('tor06', v_b->>'sheet_id');
  perform pg_temp.chk('S5a TOR 01-06 장: 열쇠 3(SO-20008 차액 500 · SO-ZZ008 700 · ADJ-ZZ001 15000) · 차변 16200', (v_b->>'keys') || ' ' || (v_b->>'lines') || ' ' || (v_b->>'debit_cents'), '3 3 16200');
  update public.qbo_cost_sheet s set epoch = v_epoch - 1 where s.id = (v_b->>'sheet_id')::uuid;   -- 가짜: 장을 만든 뒤 소진 표가 다시 선 것처럼(epoch 작게)
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_q := public.qbo_cost_sheet_queue(date '2026-01-06', 'TOR'); v_j06 := (v_q->>'job_id')::uuid; perform pg_temp.put('tor06_job', v_j06::text);
  v_p := public.qbo_job_preview(v_j06);
  perform pg_temp.chk('S5b preview: hold 글 · sendable false', ((v_p->>'hold') ~ ('^cost rebuild detected \(consume epoch ' || (v_epoch - 1)::text || ' → ' || v_epoch::text || '\)'))::text || ' ' || (v_p->>'sendable'), 'true false');
  perform pg_temp.as_user(null);
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('tor06')::uuid;
  perform pg_temp.chk('S5c claim: held 1(TOR 01-06 몸에서 감지) · 먼저 잡힌 EDM 01-07 은 줄까지 갔다가 hold_all 에 걸린다(realm 전체 · 두 창고 · 1093) → 장 hold · 행 0 · 일감 failed · TOR 01-06 장 hold + hold_reason · 일감 failed · last_error 에 풀어 주는 길(release) · 행 0 · sent · void 장은 그대로',
    (v_c->>'held') || ' ' || jsonb_array_length(v_c->'jobs')::text || ' ' || (select s.state || ':' || (select count(*) from public.qbo_cost_sent t where t.sheet_id = s.id)::text || ':' || (select j.state from public.qbo_job j where j.id = s.job_id) from public.qbo_cost_sheet s where s.id = pg_temp.id('edm07')::uuid) || ' ' || v_s.state || ' ' || (v_s.hold_reason ~ 'cost rebuild detected')::text || ' ' || (select j.state || ':' || (j.last_error ~ 'qbo_cost_rebuild_release')::text from public.qbo_job j where j.id = v_j06) || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = v_s.id)
    || ' ' || (select string_agg(s.state, ',' order by s.sheet_date) from public.qbo_cost_sheet s where s.realm_id = v_realm and s.wh = 'EDM' and s.sheet_date in ('2026-01-05', '2026-01-06')), '1 1 hold:0:failed hold true failed:true 0 sent,void');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  perform pg_temp.chk('S5d retry 거부(hold) · release 거부(note 없음) · 실제 사건 재생성 흉내 없이 preview 가 읽힌다',
    (pg_temp.try(format($q$select public.qbo_job_retry(%L::uuid, 'x')::text$q$, v_j06)) ~ 'is on hold after a cost rebuild')::text || ' ' || (pg_temp.try($q$select public.qbo_cost_rebuild_release('')::text$q$) ~ 'note is required')::text, 'true true');
  v_rp := public.qbo_cost_rebuild_preview();
  perform pg_temp.chk('S5e rebuild_preview: held 2(EDM 01-07 · TOR 01-06) · 창고 1(TOR · as_of 2026-01-05 · 열쇠 1 SO-20008 500 = 3000 − 2500 · 짝 (_58_,_59_) 500 · 줄 2 · DocNumber COGS-<오늘>-TOR-R) · EDM 은 차액 0 이라 없음',
    jsonb_array_length(v_rp->'held')::text || ':' || (v_rp->'held'->0->>'doc_number') || ':' || (v_rp->'held'->1->>'doc_number') || ' ' || jsonb_array_length(v_rp->'warehouses')::text || ' ' || (v_rp->'warehouses'->0->>'wh') || ' ' || (v_rp->'warehouses'->0->>'as_of') || ' ' || (v_rp->'warehouses'->0->'keys'->0->>'doc_key') || ':' || (v_rp->'warehouses'->0->'keys'->0->>'cents') || ':' || (v_rp->'warehouses'->0->'keys'->0->>'expected_cents') || ':' || (v_rp->'warehouses'->0->'keys'->0->>'sent_cents')
    || ' ' || (v_rp->'warehouses'->0->'pairs'->0->>'acct_a') || '/' || (v_rp->'warehouses'->0->'pairs'->0->>'acct_b') || ':' || (v_rp->'warehouses'->0->'pairs'->0->>'cents') || ' ' || (v_rp->'warehouses'->0->>'line_count') || ' ' || ((v_rp->'warehouses'->0->>'doc_number') = 'COGS-' || to_char(public.ims_today(), 'YYYYMMDD') || '-TOR-R')::text,
    '2:COGS-20260107-EDM:COGS-20260106-TOR 1 TOR 2026-01-05 SO-20008:500:3000:2500 _58_/_59_:500 2 true');
  select j.request_id into v_req1 from public.qbo_job j where j.id = v_j06;
  v_rl := public.qbo_cost_rebuild_release('ZZ 3-2b: checked the rebuild, release');
  select j.request_id into v_req2 from public.qbo_job j where j.id = v_j06;
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('tor06')::uuid;
  select * into v_rs from public.qbo_cost_sheet s where s.realm_id = v_realm and s.kind = 'rebuild' and s.wh = 'TOR';
  v_jr := v_rs.job_id; perform pg_temp.put('reb', v_rs.id::text); perform pg_temp.put('reb_job', v_jr::text);
  perform pg_temp.chk('S5f release: released_days 2 · rebuild 장 1(TOR · 열쇠 1 · 짝 1 · 차변 500) · 장 kind rebuild · 오늘 날짜 · -R · pending · epoch_now · 행 1 · 일감 queued ims_id |rebuild · 멈춘 장 pending · epoch 갱신 · hold_reason null · 일감 queued · request_id 새로 · last_error null',
    (v_rl->>'released_days') || ' ' || jsonb_array_length(v_rl->'rebuild_sheets')::text || ' ' || (v_rl->'rebuild_sheets'->0->>'wh') || ':' || (v_rl->'rebuild_sheets'->0->>'keys') || ':' || (v_rl->'rebuild_sheets'->0->>'pairs') || ':' || (v_rl->'rebuild_sheets'->0->>'debit_cents')
    || ' ' || v_rs.kind || ' ' || (v_rs.sheet_date = public.ims_today())::text || ' ' || (v_rs.doc_number ~ '-TOR-R$')::text || ' ' || v_rs.state || ' ' || (v_rs.epoch = v_epoch)::text || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = v_rs.id)
    || ' ' || (select j.state || ':' || j.ims_id from public.qbo_job j where j.id = v_jr) || ' ' || v_s.state || ' ' || (v_s.epoch = v_epoch)::text || ' ' || coalesce(v_s.hold_reason, 'null') || ' ' || (select j.state || ':' || (j.last_error is null)::text from public.qbo_job j where j.id = v_j06) || ' ' || (v_req1 <> v_req2)::text,
    '2 1 TOR:1:1:500 rebuild true true pending true 1 queued:' || to_char(public.ims_today(), 'YYYY-MM-DD') || '|TOR|rebuild pending true null queued:true true');
  perform pg_temp.chk('S5g 두 번째 release(hold 없음) 거부', (pg_temp.try($q$select public.qbo_cost_rebuild_release('x')::text$q$) ~ 'Nothing is on hold')::text, 'true');
  perform pg_temp.as_user(null);
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  v_l := (select x from jsonb_array_elements(v_c->'jobs') x where x->>'doc_number' = v_rs.doc_number);
  perform pg_temp.chk('S5h claim: 셋 잡힘(EDM 01-07 다시 · rebuild · TOR 01-06) · TOR day 장은 rebuild 장 뒤에 선다(blocked_for_invoice 1 · blocked_by = rebuild 일감) · rebuild 몸 = 「IMS cost rebuild」 #58 Debit 5.00 · #59 Credit 5.00 · Entity 없음 · PrivateNote 「IMS cost rebuild released …」',
    (v_c->>'claimed') || ' ' || jsonb_array_length(v_c->'jobs')::text || ' ' || (v_c->>'blocked_for_invoice') || ' ' || (select (j.blocked_by = v_jr)::text from public.qbo_job j where j.id = v_j06) || ' ' || (v_l is not null)::text
    || ' ' || (select string_agg((l->>'Description') || ':' || (l->'JournalEntryLineDetail'->>'PostingType') || ':' || (l->>'Amount') || ':' || (l->'JournalEntryLineDetail' ? 'Entity')::text, ' ' order by o) from jsonb_array_elements(v_l->'body'->'Line') with ordinality as x(l, o)) || ' ' || ((v_l->'body'->>'PrivateNote') ~ '^IMS cost rebuild released ')::text,
    '3 2 1 true true IMS cost rebuild:Debit:5.00:false IMS cost rebuild:Credit:5.00:false true');
  v_d := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'ZZ-JE-R', %L, null, null, null, null, 5.00)$q$, v_jr, v_rs.doc_number));
  select * into v_rs from public.qbo_cost_sheet s where s.id = pg_temp.id('reb')::uuid;
  perform pg_temp.chk('S5i rebuild done: sent · 뒤 day 장 풀림(unblocked 1) · 장 sent · 행 1 그대로 · 01-06 TOR 셈에서 SO-20008 사라짐(rebuild 가 담음) · 남은 열쇠 SO-ZZ008 700 · ADJ-ZZ001 15000',
    (v_d->>'state') || ' ' || (v_d->>'unblocked') || ' ' || v_rs.state || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = v_rs.id) || ' ' || (select string_agg(c.doc_key || ':' || c.diff_cents::text, ' ' order by c.doc_key) from public.qbo_cost_sheet_calc(date '2026-01-06', 'TOR', v_realm) c where c.status = 'send'), 'sent 1 sent 1 ADJ-ZZ001:15000 SO-ZZ008:700');
  -- S8 Entity 짝 없는 손님(SO-ZZ008) → needs → customer 일감 · 장 blocked
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('tor06')::uuid;
  v_jc := (v_c->'need_jobs'->0->>'job_id')::uuid; perform pg_temp.put('cust_job', v_jc::text);
  perform pg_temp.chk('S8a claim(풀린 장): unblocked 0(done 이 풀었다) · blocked_for_needs 1 · need_jobs 1(kind customer · 가짜 손님 · existing false · name 「customer of SO-ZZ008」) · 일감 blocked · blocked_by = 손님 일감 · 장 pending · 행 0',
    (v_c->>'unblocked') || ' ' || (v_c->>'blocked_for_needs') || ' ' || jsonb_array_length(v_c->'need_jobs')::text || ' ' || (v_c->'need_jobs'->0->>'kind') || ' ' || ((v_c->'need_jobs'->0->>'ims_id') = pg_temp.id('cust'))::text || ' ' || (v_c->'need_jobs'->0->>'existing') || ' ' || (v_c->'need_jobs'->0->>'name')
    || ' ' || (select j.state || ':' || (j.blocked_by = v_jc)::text from public.qbo_job j where j.id = v_j06) || ' ' || v_s.state || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = v_s.id), '0 1 1 customer true false customer of SO-ZZ008 blocked:true pending 0');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_p := public.qbo_job_preview(v_j06);
  perform pg_temp.chk('S8b preview(blocked 장): needs 1(job_state queued) · blocked_by 손님 일감 · sendable false', jsonb_array_length(v_p->'needs')::text || ' ' || (v_p->'needs'->0->>'job_state') || ' ' || (v_p->'blocked_by'->>'kind') || ' ' || (v_p->>'sendable'), '1 queued customer false');
  perform pg_temp.as_user(null);
  -- 빠져나오는 길: 손님 일감이 나가면(손 Send 의 need · 3-3 cron kinds [cost_day, customer] · 또는 그 인보이스가 먼저) ② 가 장을 푼다
  v_c := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['customer'], array[%L::uuid])$q$, v_jc));   -- EF 가 손님 일감을 잡듯(p_job_ids 로 실제 손님 일감 무접촉) · 몸 = qbo_customer_body(가짜 손님)
  perform pg_temp.chk('S8b2 손님 일감 claim(kinds customer · 그 id 만): claimed 1 · DisplayName 가짜 손님', (v_c->>'claimed') || ' ' || (v_c->'jobs'->0->>'name'), '1 ZZ Cost Customer 3-2b');
  v_d := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'ZZ-CUST-1', 'ZZ Cost Customer 3-2b')$q$, v_jc));
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('tor06')::uuid;
  v_l := v_c->'jobs'->0->'body'->'Line';
  perform pg_temp.chk('S8c 손님 done → qbo_link created · 장 풀림(done unblocked 1) · claim: claimed 1 · 줄 3(_1150040010_ Debit 150.00 「ADJ-ZZ001」 · #58 Debit 7.00 Entity ZZ-CUST-1 「SO-ZZ008」 · #59 Credit 157.00) · 차변 15700 · 장 sending · 행 2',
    (v_d->>'linked') || ' ' || (select l.matched_by from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = pg_temp.id('cust')) || ' ' || (v_d->>'unblocked') || ' ' || (v_c->>'claimed')
    || ' ' || (select string_agg((l->>'Description') || ':' || (l->'JournalEntryLineDetail'->>'PostingType') || ':' || (l->>'Amount') || ':' || coalesce(l->'JournalEntryLineDetail'->'Entity'->'EntityRef'->>'value', '-'), ' ' order by o) from jsonb_array_elements(v_l) with ordinality as x(l, o))
    || ' ' || (v_c->'jobs'->0->'totals'->>'debit_cents') || ' ' || v_s.state || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = v_s.id),
    'true created 1 1 ADJ-ZZ001:Debit:150.00:- SO-ZZ008:Debit:7.00:ZZ-CUST-1 Inventory TOR:Credit:157.00:- 15700 sending 2');
end $$;

-- ── S4 unknown → 장 unknown(행 유지 = 보낸 몫) → resolve not_in_qbo → 다시 claim → unknown → resolve in_qbo · S7 다른 kind 의 claim 은 cost_day 를 안 집는다 ──
do $$
declare v_realm text := (select realm_id from public.qbo_connection where singleton); v_j06 uuid := pg_temp.id('tor06_job')::uuid; v_u jsonb; v_r jsonb; v_c jsonb; v_s public.qbo_cost_sheet%rowtype; v_b jsonb; v_q jsonb; v_j07 uuid;
begin
  v_u := pg_temp.svc(format($q$select public.qbo_job_unknown(%L::uuid, 'ZZ 3-2b: no answer from QuickBooks', null, 'COGS-20260106-TOR')$q$, v_j06));
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('tor06')::uuid;
  perform pg_temp.chk('S4a unknown: 일감 unknown · 장 unknown(트리거) · 행 2 유지(보낸 몫으로 센다) · 01-07 TOR 셈 0 줄(01-06 열쇠가 다시 나오지 않는다)',
    (v_u->>'state') || ' ' || v_s.state || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = v_s.id) || ' ' || (select count(*)::text from public.qbo_cost_sheet_calc(date '2026-01-07', 'TOR', v_realm) c), 'unknown unknown 2 0');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  perform pg_temp.chk('S4b resolve 거부: unknown 아닌 장 · in_qbo 에 Id 없음 · note 없음 · 모르는 outcome',
    (pg_temp.try(format($q$select public.qbo_cost_sheet_resolve(%L::uuid, 'in_qbo', 'x', 'ZZ-1')::text$q$, pg_temp.id('tor05'))) ~ 'Only a cost day whose result is unknown')::text
    || (pg_temp.try(format($q$select public.qbo_cost_sheet_resolve(%L::uuid, 'in_qbo', 'x')::text$q$, pg_temp.id('tor06'))) ~ 'Id is required')::text
    || (pg_temp.try(format($q$select public.qbo_cost_sheet_resolve(%L::uuid, 'in_qbo', '', 'ZZ-1')::text$q$, pg_temp.id('tor06'))) ~ 'note is required')::text
    || (pg_temp.try(format($q$select public.qbo_cost_sheet_resolve(%L::uuid, 'bogus', 'x')::text$q$, pg_temp.id('tor06'))) ~ 'outcome must be')::text, 'truetruetruetrue');
  v_r := public.qbo_cost_sheet_resolve(pg_temp.id('tor06')::uuid, 'not_in_qbo', 'ZZ 3-2b: searched DocNumber in QuickBooks, nothing there');
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('tor06')::uuid;
  perform pg_temp.chk('S4c resolve not_in_qbo: 일감 queued · 장 pending(트리거) · 행 0(지움 → 다음 claim 이 다시 셈) · resolved_at · note', (v_r->>'job_state') || ' ' || v_s.state || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = v_s.id) || ' ' || (v_s.resolved_at is not null)::text || ' ' || (v_s.note ~ 'resolved not_in_qbo')::text, 'queued pending 0 true true');
  perform pg_temp.as_user(null);
  v_c := pg_temp.svc($q$select public.qbo_job_claim(15, array['cost_day'])$q$);
  v_u := pg_temp.svc(format($q$select public.qbo_job_unknown(%L::uuid, 'ZZ 3-2b: timeout again', null, 'COGS-20260106-TOR')$q$, v_j06));
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_r := public.qbo_cost_sheet_resolve(pg_temp.id('tor06')::uuid, 'in_qbo', 'ZZ 3-2b: found COGS-20260106-TOR in QuickBooks', 'ZZ-JE-2');
  select * into v_s from public.qbo_cost_sheet s where s.id = pg_temp.id('tor06')::uuid;
  perform pg_temp.chk('S4d 다시 claim(차변 15700 · 행 2) → unknown → resolve in_qbo(ZZ-JE-2): 일감 sent · 장 sent · qbo_id · qbo_txn JournalEntry ZZ-JE-2 total 157.00 · 행 2',
    (v_c->>'claimed') || ' ' || (v_c->'jobs'->0->'totals'->>'debit_cents') || ' ' || (v_r->>'state') || ' ' || (v_r->>'total_amt') || ' ' || v_s.state || ' ' || v_s.qbo_id || ' ' || (select j.state from public.qbo_job j where j.id = v_j06)
    || ' ' || (select t.qbo_type || ':' || t.qbo_id || ':' || t.total_amt::text from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'cost_sheet' and t.ims_id = '2026-01-06|TOR') || ' ' || (select count(*)::text from public.qbo_cost_sent t where t.sheet_id = v_s.id),
    '1 15700 sent 157.00 sent ZZ-JE-2 sent JournalEntry:ZZ-JE-2:157.00 2');
  perform pg_temp.chk('S4e retry 거부(sent 장) · resolve 거부(이미 sent)', (pg_temp.try(format($q$select public.qbo_job_retry(%L::uuid, 'x')::text$q$, v_j06)) ~ 'Only a failed or skipped job')::text || ' ' || (pg_temp.try(format($q$select public.qbo_cost_sheet_resolve(%L::uuid, 'not_in_qbo', 'x')::text$q$, pg_temp.id('tor06'))) ~ 'Only a cost day whose result is unknown')::text, 'true true');
  perform pg_temp.as_user(null);
  -- S7: queued cost_day(EDM 01-07 · S6f) — cron 61 꼴(kinds 없음 = EF 가 18 전부) · cron 62 꼴(열둘) · DB 기본값(customer · item) 어느 것도 집지 않는다(p_job_ids 로 실제 일감 무접촉) · queue_due 는 TOR 01-07(가짜 사건 1.00) 로
  v_j07 := pg_temp.id('edm07_job')::uuid;
  perform pg_temp.svc(format($q$select public.qbo_job_fail(%L::uuid, 'ZZ 3-2b: put back for S7')$q$, v_j07));   -- S5h 에서 다시 잡혀 sending — fail → retry 로 queued 에 둔다
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  perform public.qbo_job_retry(v_j07, null);
  perform pg_temp.as_user(null);
  insert into public.inv_layer_consume (id, layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) overriding system value
  values (pg_temp.id('c_base')::bigint + 9, pg_temp.id('l_tor')::bigint, 'sale', 'SO-20009', 'zz-9', 'sale_out', date '2026-01-07', 1, 1, 1, 'sale');
  v_b := public.qbo_cost_sheet_build(date '2026-01-07', 'TOR', v_realm);
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_q := public.qbo_cost_queue_due();
  perform pg_temp.as_user(null);
  perform pg_temp.chk('S7a queue_due: 일감 없는 pending 장 1(TOR 01-07 · SO-20009 차액 100 「(adj. of 2026-01-05)」) → queued 1 · errors 0 · 다시 부르면 0', (v_b->>'keys') || ' ' || (v_b->>'debit_cents') || ' ' || (v_q->>'count') || ' ' || jsonb_array_length(v_q->'errors')::text || ' ' || (v_q->'queued'->0->>'doc_number') || ' ' || (select j.state from public.qbo_job j where j.id = (v_q->'queued'->0->>'job_id')::uuid) || ' ' || (select (public.qbo_cost_queue_due()->>'count') from (select pg_temp.as_user(pg_temp.id('st_uid'))) z), '1 100 1 0 COGS-20260107-TOR queued 0');
  perform pg_temp.as_user(null);
  perform pg_temp.chk('S7b 기존 kind 의 claim 은 cost_day 를 집지 않는다: cron 62 열둘 → wrong_kind · 기본값(customer · item) → wrong_kind · EF SEND_KINDS 18 → wrong_kind · 일감 queued 그대로 · 모르는 kind 거부',
    (pg_temp.svc(format($q$select public.qbo_job_claim(15, array['payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void'], array[%L::uuid])$q$, v_j07))->'requested'->0->>'result')
    || ' ' || (pg_temp.svc(format($q$select public.qbo_job_claim(15, null, array[%L::uuid])$q$, v_j07))->'requested'->0->>'result')
    || ' ' || (pg_temp.svc(format($q$select public.qbo_job_claim(15, array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void'], array[%L::uuid])$q$, v_j07))->'requested'->0->>'result')
    || ' ' || (select j.state from public.qbo_job j where j.id = v_j07) || ' ' || (pg_temp.try($q$select pg_temp.svc('select public.qbo_job_claim(15, array[''cost_dayz''])')::text$q$) ~ 'kinds must be among')::text, 'wrong_kind wrong_kind wrong_kind queued true');
  perform pg_temp.chk('S7c cost_day 로 고르면 잡힌다(p_job_ids) · 그 뒤 fail 로 되돌려 둔다(몸은 void 01-06 을 건너뛴다)', (pg_temp.svc(format($q$select public.qbo_job_claim(15, array['cost_day'], array[%L::uuid])$q$, v_j07))->'requested'->0->>'result') || ' ' || (pg_temp.svc(format($q$select public.qbo_job_fail(%L::uuid, 'ZZ 3-2b: put back')$q$, v_j07))->>'state'), 'claimed failed');
end $$;

-- ── K 열쇠 · W WHERE 정적(REST 두 겹 ①) · G grant · md5 · 시퀀스 · 실물 무접촉 ──
select pg_temp.as_user(:'nk_uid');
select pg_temp.chk('K1 열쇠 없는 직원: queue · queue_due · rebuild_preview · release · resolve 모두 거부(qbo 열쇠)',
  (pg_temp.try($q$select public.qbo_cost_sheet_queue(date '2026-01-05', 'TOR')::text$q$) ~ 'does not have the ''qbo''')::text || (pg_temp.try($q$select public.qbo_cost_queue_due()::text$q$) ~ 'does not have the ''qbo''')::text || (pg_temp.try($q$select public.qbo_cost_rebuild_preview()::text$q$) ~ 'does not have the ''qbo''')::text
  || (pg_temp.try($q$select public.qbo_cost_rebuild_release('x')::text$q$) ~ 'does not have the ''qbo''')::text || (pg_temp.try(format($q$select public.qbo_cost_sheet_resolve(%L::uuid, 'not_in_qbo', 'x')::text$q$, pg_temp.id('tor06'))) ~ 'does not have the ''qbo''')::text, 'truetruetruetruetrue');
select pg_temp.as_user(null);
select pg_temp.chk('K2 service 아닌 호출: claim 거부(send worker only)', (pg_temp.try($q$select public.qbo_job_claim(15, array['cost_day'])::text$q$) ~ 'send worker only')::text, 'true');
select pg_temp.chk('W1 WHERE 정적: 새 함수 12 + 재발행 여섯 + 3-2a 15 — 깊이 0 WHERE 없는 update · delete 0',
  (select string_agg(p.proname || ' ' || pg_temp.nowhere(p.prosrc)::text, ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo_cost_%' or p.proname in ('qbo_job_cost_sheet_sync', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc'))),
  (select string_agg(p.proname || ' 0', ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo_cost_%' or p.proname in ('qbo_job_cost_sheet_sync', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc'))));
select pg_temp.chk('G1 grant: 열쇠 창구 다섯 authenticated + service · ims_id 열림 · 속 일곱 grant 0 · 재발행 ACL 그대로(claim · done service · list · retry authenticated — 2a 때부터)',
  (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '(default)'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_cost_sheet_queue', 'qbo_cost_day_body', 'qbo_cost_hold_all', 'qbo_cost_sheet_ims_id', 'qbo_job_cost_sheet_sync', 'qbo_cost_sheet_resolve', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list')),
  'qbo_cost_day_body:{postgres=X/postgres} qbo_cost_hold_all:{postgres=X/postgres} qbo_cost_sheet_ims_id:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} qbo_cost_sheet_queue:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} qbo_cost_sheet_resolve:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} qbo_job_claim:{postgres=X/postgres,service_role=X/postgres} qbo_job_cost_sheet_sync:{postgres=X/postgres} qbo_job_done:{postgres=X/postgres,service_role=X/postgres} qbo_job_list:{postgres=X/postgres,authenticated=X/postgres} qbo_job_retry:{postgres=X/postgres,authenticated=X/postgres}');
select pg_temp.chk('G2 무변 넷(fail · skip · unknown · unknown_list) md5 = begin 앞 · 여섯은 cost_day 를 담는다',
  ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_fail', 'qbo_job_skip', 'qbo_job_unknown', 'qbo_job_unknown_list')) = :'pre_four')::text || ' ' || (select bool_and(prosrc like '%cost_%')::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc')), 'true true');
\if :{?mig}
select pg_temp.chk('S0b(시험 갈래) 재발행 여섯 md5 가 begin 앞과 다르다', ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc')) <> :'pre_six')::text, 'true');
\else
select pg_temp.chk('S0b(확인 갈래) 재발행 여섯 md5 = begin 앞(이미 적용)', ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc')) = :'pre_six')::text, 'true');
\endif
select pg_temp.chk('G3 시퀀스 무접촉(소진 · 레이어 · 원장 last_value 그대로) · 가짜 행 수(레이어 +2 · 소진 +9 · 원장 +3 · 조정 +2) · min(consume id) 그대로 · 실제 일감은 안 건드림(cost_day 외 일감 상태 합 = begin 앞 수)',
  ((select last_value || ':' || is_called from public.inv_layer_consume_id_seq) = :'pre_seq_cons' and (select last_value || ':' || is_called from public.inv_layer_id_seq) = :'pre_seq_layer' and (select last_value || ':' || is_called from public.inv_ledger_id_seq) = :'pre_seq_ledger')::text
  || ' ' || ((select count(*) from public.inv_layer) - :pre_layer)::text || ' ' || ((select count(*) from public.inv_layer_consume) - :pre_cons)::text || ' ' || ((select count(*) from public.inv_ledger) - :pre_ledger)::text || ' ' || ((select count(*) from public.inv_adjust) - :pre_adj)::text
  || ' ' || ((select min(id) from public.inv_layer_consume) = :pre_epoch)::text || ' ' || ((select count(*) from public.qbo_job where kind <> 'cost_day' and not (kind = 'customer' and ims_id = pg_temp.id('cust'))) = :pre_jobs)::text, 'true 2 9 3 2 true true');
select pg_temp.chk('G4 거래 표 FK 0: qbo_job · qbo_txn · qbo_cost_* 에서 so · so_invoice · so_payment · inv_* 로 가는 FK 없음', (select coalesce(string_agg(c.conrelid::regclass::text || '→' || c.confrelid::regclass::text, ' ' order by 1), '') from pg_constraint c where c.contype = 'f' and c.conrelid in ('public.qbo_job'::regclass, 'public.qbo_txn'::regclass, 'public.qbo_cost_sheet'::regclass, 'public.qbo_cost_sent'::regclass, 'public.qbo_cost_hold'::regclass) and c.confrelid::regclass::text not in ('ims_staff', 'qbo_cost_sheet', 'qbo_job')), '');

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(상호 없음 · 가짜 행은 rollback) ──'
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, :EXPECT_OK as expect_ok from t_res;
select 'FAIL ' || label || format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) as fail_line from t_res where not ok order by n;
select round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
select (select count(*) from public.ims_staff) = :pre_staff and (select count(*) from public.inv_config) = :pre_cfg and (select value from public.inv_config where key = 'qbo_cost_since') = :'pre_since' and (select value from public.inv_config where key = 'qbo_cost_adjust_hold_over') = :'pre_thr'
   and (select count(*) from public.inv_layer_consume) = :pre_cons and (select count(*) from public.qbo_job) = :pre_jobs and (select count(*) from public.qbo_cost_sheet) = :pre_sheets and (select count(*) from public.qbo_cost_sent) = :pre_sent
   and not (:{?mig} and exists (select 1 from pg_constraint where conname = 'qbo_job_kind_ck' and pg_get_constraintdef(oid) like '%cost_day%')) as rolled_back_clean;
