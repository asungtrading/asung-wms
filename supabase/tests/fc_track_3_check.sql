-- supabase/tests/fc_track_3_check.sql — fc-track-3 검증 (2026-11-10 밤 토론토 · 판정 1163 ~ 1166 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] 기준(begin 앞) → begin(lock_timeout 3s) → 가짜 재료(직원 넷 · 예약 여섯 — 실제 booked 예약 하나를 복제해 표에 직접 · 계정은 가짜 ZZT) → (-v mig 면 \i) → 시나리오 → 구조 · 정적 검사 → 집계 → rollback
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111034018_fc_track_3_finance_documents_balance.sql -f supabase/tests/fc_track_3_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(갈래마다 같다)
--   ⚠️ 레포 루트에서 돌린다 — fixture 다섯(supabase/functions/freightcom/fixtures/finance-*.json)을 psql 이 읽는다(deno 시험과 같은 파일 · 지시서 📌 의 실물 꼴을 다시 적은 것 · id 는 지어낸 값)
--   ⚠️ 문서 · 잔액은 가짜 계정 ZZT 로만 쓴다 — 실제 TOR · EDM 행(적용 뒤 cron 이 쌓는 것)과 섞이지 않는다 · 실물을 읽는 곳은 둘: 복제할 booked 예약 하나 · D3b 의 견적 줄(취소된 실제 예약 49250480 의 rate_id — fc_quote_rate.raw)
\set ON_ERROR_STOP on
\pset pager off
\set EXPECT_OK 33
\set fx_docs `cat supabase/functions/freightcom/fixtures/finance-documents.json`
\set fx_sod `cat supabase/functions/freightcom/fixtures/finance-document-sod.json`
\set fx_inv `cat supabase/functions/freightcom/fixtures/finance-document-invoice.json`
\set fx_bal `cat supabase/functions/freightcom/fixtures/finance-balance.json`
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fc\_%';
create temp table t_fx (k text primary key, v jsonb);
insert into t_fx values ('docs', :'fx_docs'), ('sod', :'fx_sod'), ('inv', :'fx_inv'), ('bal', :'fx_bal');
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
create function pg_temp.usr(p_k text, p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', jsonb_build_object('role', 'authenticated', 'sub', pg_temp.id('auth_' || p_k)), p_sql) $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  return coalesce(v, '(null)');
end $$;
create function pg_temp.j(p_v text, p_key text default null) returns text language sql as $$ select case when p_v like 'ERR %' or p_v = '(null)' then p_v when p_key is null then (p_v::jsonb)::text else coalesce(p_v::jsonb->>p_key, '(null)') end $$;
create function pg_temp.err(p_v text, p_like text) returns text language sql as $$ select case when p_v like 'ERR %' and p_v like p_like then 'refused' else left(p_v, 200) end $$;
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
create function pg_temp.fx(p_k text) returns jsonb language sql as $$ select v from t_fx where k = p_k $$;
-- 견적 꼴(예약 응답의 shipment.rate) · 문서 꼴(줄 = [type, sub_type, cents] 목록 · 한 쉽먼트)
create function pg_temp.rate(p_base int, p_sur jsonb, p_tax jsonb, p_total int) returns jsonb language sql as $$
  select jsonb_build_object('shipment', jsonb_build_object('rate', jsonb_build_object('base', jsonb_build_object('value', p_base::text, 'currency', 'CAD'), 'total', jsonb_build_object('value', p_total::text, 'currency', 'CAD'),
    'surcharges', coalesce((select jsonb_agg(jsonb_build_object('type', e->>0, 'amount', jsonb_build_object('value', e->>1, 'currency', 'CAD'))) from jsonb_array_elements(p_sur) e), '[]'::jsonb),
    'taxes', coalesce((select jsonb_agg(jsonb_build_object('type', e->>0, 'amount', jsonb_build_object('value', e->>1, 'currency', 'CAD'))) from jsonb_array_elements(p_tax) e), '[]'::jsonb)))) $$;
create function pg_temp.doc(p_id text, p_ship text, p_amount int, p_lines jsonb, p_cur text default 'CAD') returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'amount', jsonb_build_object('value', p_amount::text, 'currency', p_cur), 'urls', jsonb_build_object('default', 'https://files.freightcom.example/x.pdf'),
    'payments', jsonb_build_array(jsonb_build_object('id', 'p1', 'type', 'net-terms', 'amount', jsonb_build_object('value', p_amount::text, 'currency', p_cur), 'data', null)),
    'line_items', (select jsonb_agg(jsonb_build_object('id', p_id || '-' || ord, 'type', e->>0, 'sub_type', e->>1, 'payment_id', 'pl1', 'shipment_id', p_ship, 'amount', jsonb_build_object('value', e->>2, 'currency', p_cur), 'message', '')) from jsonb_array_elements(p_lines) with ordinality x(e, ord))) $$;
create function pg_temp.docs(p_acc text, p_docs jsonb, p_limit int default 25) returns text language sql as $$ select pg_temp.svc(format('select public.fc_finance_docs_save(%L, %L::jsonb, %s)::text', p_acc, p_docs, p_limit)) $$;
create function pg_temp.lines(p_acc text, p_doc jsonb) returns text language sql as $$ select pg_temp.svc(format('select public.fc_finance_lines_save(%L, %L::jsonb)::text', p_acc, p_doc)) $$;
create function pg_temp.bal(p_acc text, p_bal jsonb) returns text language sql as $$ select pg_temp.svc(format('select public.fc_finance_balance_save(%L, %L, %L::jsonb)::text', p_acc, 'net-terms', p_bal)) $$;
create function pg_temp.cc(p_k text, p_keys text[]) returns text language sql as $$
  select case when v like 'ERR %' then v else (select string_agg(coalesce(v::jsonb->>k, '(null)'), ' | ' order by ord) from unnest(p_keys) with ordinality u(k, ord)) end
    from (select pg_temp.svc(format('select public.fc_charge_check(%L)::text', pg_temp.id(p_k))) as v) q $$;
create function pg_temp.summ(p_acc text, p_keys text[]) returns text language sql as $$
  select case when v like 'ERR %' then v else (select string_agg(coalesce(v::jsonb->>k, '(null)'), ' | ' order by ord) from unnest(p_keys) with ordinality u(k, ord)) end
    from (select pg_temp.svc(format('select public.fc_finance_account_summary(%L)::text', p_acc)) as v) q $$;
-- 가짜 예약 하나 — 실제 booked 예약(src_b)을 복제하고 칸을 덮는다(같은 발송 · attempt 9001 ~ · 계정 ZZT)
create function pg_temp.mkb(p_k text, p_attempt int, p_tn text, p_response jsonb, p_over jsonb default '{}'::jsonb) returns void language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.fc_booking
  select (jsonb_populate_record(null::public.fc_booking, to_jsonb(b) || jsonb_build_object(
            'id', v_id, 'attempt', p_attempt, 'unique_id', 'zzfc3-' || p_k, 'freightcom_shipment_id', 'fcShipFin' || p_k, 'transaction_number', p_tn, 'account', 'ZZT', 'status', 'booked', 'state', 'in-transit',
            'response', p_response, 'so_written', '[]'::jsonb, 'labels', null, 'error', null, 'cancel_error', null, 'cancelled_at', null, 'cancelled_by', null, 'failed_at', null, 'booked_at', now() - interval '1 hour') || p_over)).*
    from public.fc_booking b where b.id = pg_temp.id('src_b')::uuid;
  perform pg_temp.put(p_k, v_id::text);
end $$;
-- 기준(begin 앞 · 실물 읽기)
select (select count(*) from public.fc_booking) as n_bk0, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.inv_config) as n_cfg0, (select count(*) from t_pre) as n_fn0,
       (select max(version) from supabase_migrations.schema_migrations) as ver0, coalesce(pg_temp.try('select count(*)::text from public.fc_document'), '-') as n_doc0 \gset
\echo '── 기준: 예약' :n_bk0 '· 직원' :n_staff0 '· inv_config' :n_cfg0 '· fc_ 함수' :n_fn0 '· 마지막 마이그레이션' :ver0 '· fc_document' :n_doc0

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
-- ── 가짜 재료 ──
do $$
declare
  v_tor uuid := '045e4ca6-b7a9-446e-9e6a-a5a0db56d456'; v_edm uuid := '95caece3-cf3e-4832-a583-e233254feadc';
  v_src uuid;
begin
  select b.id into v_src from public.fc_booking b join public.fc_shipment f on f.id = b.shipment_id where b.status = 'booked' and f.origin_warehouse_id = v_tor order by b.booked_at, b.id limit 1;
  if v_src is null then raise exception 'fc_track_3_check: no booked Toronto booking to clone'; end if;
  perform pg_temp.put('src_b', v_src::text);
  perform pg_temp.put('real_rate', (select b.rate_id::text from public.fc_booking b where b.transaction_number = '49250480' and b.status = 'cancelled' limit 1));
  insert into public.ims_staff (id, auth_user_id, email, name, role, perms, warehouse_access) values
    ('f1c30000-0000-4000-8000-0000000000a1', 'f1c30000-0000-4000-8000-000000000001', 'fc-track-3-p@asung.invalid', 'ZZFC3 Purchasing', 'manager', '["purchasing"]', '{}'),
    ('f1c30000-0000-4000-8000-0000000000a2', 'f1c30000-0000-4000-8000-000000000002', 'fc-track-3-w@asung.invalid', 'ZZFC3 Booker', 'manager', '["freight_booking"]', array[v_tor]),
    ('f1c30000-0000-4000-8000-0000000000a3', 'f1c30000-0000-4000-8000-000000000003', 'fc-track-3-e@asung.invalid', 'ZZFC3 Edmonton', 'manager', '["freight_booking"]', array[v_edm]),
    ('f1c30000-0000-4000-8000-0000000000a4', 'f1c30000-0000-4000-8000-000000000004', 'fc-track-3-n@asung.invalid', 'ZZFC3 Nobody', 'manager', '["sales"]', '{}');
  perform pg_temp.put('auth_P', 'f1c30000-0000-4000-8000-000000000001'), pg_temp.put('auth_W', 'f1c30000-0000-4000-8000-000000000002'), pg_temp.put('auth_E', 'f1c30000-0000-4000-8000-000000000003'), pg_temp.put('auth_N', 'f1c30000-0000-4000-8000-000000000004');
  -- A: 청구 = 견적(1228) · B: 두 판(17439 → 25675 · other-charge-1) · U: UPS 꼴(견적에 surcharge 없음 · 청구는 fuel 을 쪼갬) · N: 문서 없음 · RtJtQ: 묶음 인보이스에만 · X: Freightcom 에서 취소(문서 없음)
  perform pg_temp.mkb('A', 9001, '49137509', pg_temp.rate(719, '[["fuel","368"]]', '[["tax-hst-on","141"]]', 1228));
  perform pg_temp.mkb('B', 9002, '49250480', pg_temp.rate(8332, '[["liftgate-delivery","2833"],["fuel","4268"]]', '[["tax-hst-on","2006"]]', 17439));
  perform pg_temp.mkb('U', 9003, '48000002', pg_temp.rate(3548, '[]', '[["tax-hst-on","461"]]', 4009));
  perform pg_temp.mkb('N', 9004, '49999999', pg_temp.rate(4425, '[]', '[["tax-hst-on","575"]]', 5000));
  perform pg_temp.mkb('RtJtQ', 9005, '49139248', pg_temp.rate(18071, '[["fuel","3500"],["liftgate-delivery","2833"],["liftgate-pick-up","2500"]]', '[["tax-hst-on","3497"]]', 30401));
  perform pg_temp.mkb('X', 9006, '49999998', pg_temp.rate(1000, '[]', '[]', 1000), '{"state":"cancelled"}');
end $$;
\if :{?mig}
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset
select pg_temp.try($q$ insert into public.inv_config (key, value, note) values ('fc_credit_limit_ZZT', '5000', 'fc_track_3_check') returning key $q$) as limit_fixture;

-- ── D1 · D2: 머리 저장 · 다시 저장 ──
select pg_temp.put('d1', pg_temp.docs('ZZT', pg_temp.fx('docs')));
select pg_temp.chk('D1a 머리 9 저장 · need_lines = IMS 예약(상태 무관)의 판 중 같은 금액의 가장 늦은 것 + 인보이스 전부 · 날짜 늦은 것부터(A1 · A2 옛 판 · IMS 밖 X1 은 빠진다)', pg_temp.j(pg_temp.id('d1')),
         '{"added": 9, "saved": 9, "account": "ZZT", "skipped": 0, "received": 9, "need_lines": ["fxDocSodB2", "fxDocInv1", "fxDocSodA3", "fxDocSodB1", "fxDocInv2", "fxDocSodX2"], "need_total": 6, "other_account": 0}'),
       pg_temp.chk('D1b 행 — 센트 · 날짜 · type · number · 통화 · 인보이스 만기', pg_temp.try($q$ select string_agg(d.id || ' ' || d.type || ' ' || d.number || ' ' || d.doc_date || ' ' || d.due_date || ' ' || d.amount_cents || ' ' || d.owing_cents || ' ' || d.currency || ' ' || (d.lines_fetched_at is null), ' · ' order by d.id) from public.fc_document d where d.id in ('fxDocSodB2', 'fxDocInv1') $q$),
         'fxDocInv1 net-terms-invoice FC17947704 2026-11-08 2026-12-08 73924 0 CAD true · fxDocSodB2 shipment-order-details 49250480 2026-11-10 2026-11-10 25675 0 CAD true');
select pg_temp.put('d2', pg_temp.docs('ZZT', pg_temp.fx('docs'), 2));
select pg_temp.chk('D2 같은 것 다시 — 늘지 않는다 · first_seen_at 그대로 · fetched_at 만 새로 · limit 2 는 앞의 둘(need_total 은 6)', pg_temp.j(pg_temp.id('d2'), 'added') || ' ' || pg_temp.j(pg_temp.id('d2'), 'saved') || ' ' || pg_temp.j(pg_temp.id('d2'), 'need_lines') || ' ' || pg_temp.j(pg_temp.id('d2'), 'need_total') || ' ' ||
         pg_temp.try($q$ select count(*) || ' ' || count(*) filter (where d.first_seen_at = now()) || ' ' || count(*) filter (where d.fetched_at > d.first_seen_at) from public.fc_document d where d.account = 'ZZT' $q$), '0 9 ["fxDocSodB2", "fxDocInv1"] 6 9 9 9'),
       pg_temp.chk('D1c 못 읽는 원소 — id 없음 · 금액 글자 · 글자 원소 · 겹친 id(뒤의 것) 는 세고 지나간다 · type 없으면 unknown', pg_temp.j(pg_temp.docs('ZZT', '[{"id":"","amount":{"value":"1"}},{"id":"fxBad2","amount":{"value":"abc"}},"junk",{"id":"fxDup","amount":{"value":"5"}},{"id":"fxDup","amount":{"value":"7"},"date":{"year":2026,"month":2,"day":30}}]'), 'skipped') || ' ' ||
         pg_temp.try($q$ select d.amount_cents || ' ' || d.type || ' ' || coalesce(d.doc_date::text, 'nodate') || ' ' || coalesce(d.owing_cents::text, 'noowing') from public.fc_document d where d.id = 'fxDup' $q$), '4 7 unknown nodate noowing'),
       pg_temp.chk('D1d 다른 계정에 이미 있는 id 는 덮지 않는다(other_account) · 직원은 못 부른다 · 계정 꼴 · 목록 아님 거부', pg_temp.j(pg_temp.docs('ZZU', '[{"id":"fxDup","amount":{"value":"999"}}]'), 'other_account') || ' ' || pg_temp.try($q$ select d.account || ' ' || d.amount_cents from public.fc_document d where d.id = 'fxDup' $q$) || ' ' ||
         pg_temp.err(pg_temp.usr('P', $q$ select public.fc_finance_docs_save('ZZT', '[]'::jsonb)::text $q$), 'ERR 42501%') || ' ' || pg_temp.err(pg_temp.docs('zz t', '[]'), '%2–10 upper-case%') || ' ' || pg_temp.err(pg_temp.docs('ZZT', '{"a":1}'), '%must be a JSON list%'), '1 ZZT 7 refused refused refused');

-- ── 줄 저장 · D3 · D4 · D6 ──
select pg_temp.put('l_b1', pg_temp.lines('ZZT', pg_temp.doc('fxDocSodB1', 'fcShipFinB', 17439, '[["base","","8332"],["surcharge","liftgate-delivery","2833"],["surcharge","fuel","4268"],["tax","tax-hst-on","2006"]]')));
select pg_temp.chk('D3a 옛 판(17439)만 줄을 읽은 때 — billed 이지만 「더 늦은 판을 아직 못 읽음」 경고', pg_temp.cc('B', '{state,extra_cents,doc_count,document_id,warnings}'),
         'billed | 0 | 2 | fxDocSodB1 | ["newer_version_unread — a later version of this document has a different amount and its lines are not read yet"]');
select pg_temp.put('l_b2', pg_temp.lines('ZZT', pg_temp.fx('sod'))), pg_temp.put('l_a3', pg_temp.lines('ZZT', pg_temp.doc('fxDocSodA3', 'fcShipFinA', 1228, '[["base","","719"],["surcharge","fuel","368"],["tax","tax-hst-on","141"]]'))),
       pg_temp.put('l_x2', pg_temp.lines('ZZT', pg_temp.doc('fxDocSodX2', 'fcShipFinU', 4009, '[["base","","2900"],["surcharge","fuel","648"],["tax","tax-hst-on","461"]]'))), pg_temp.put('l_inv', pg_temp.lines('ZZT', jsonb_build_object('document', pg_temp.fx('inv'))));
select pg_temp.chk('D1e 줄 저장(실물 꼴 · 줄 5) — 반환에 금액 없음 · message btrim · base 는 sub_type null · payments 는 type · amount_cents 만 · 표 어디에도 http · 카드 없음', pg_temp.j(pg_temp.id('l_b2')) || ' | ' ||
         pg_temp.try($q$ select (select string_agg(l.type || ':' || coalesce(l.sub_type, '-') || ':' || l.amount_cents || ':' || coalesce(l.message, '-') || ':' || l.shipment_fc_id || ':' || l.currency, ',' order by l.line_id) from public.fc_document_line l where l.document_id = 'fxDocSodB2') || ' | ' || d.payments::text || ' | ' || d.lines_amount_cents || ' | ' ||
                           (select count(*) from public.fc_document x where x.account = 'ZZT' and (to_jsonb(x)::text ~* 'https?:|credit_card|mastercard')) || (select count(*) from public.fc_document_line x where x.document_id like 'fxDoc%' and to_jsonb(x)::text ~* 'https?:') from public.fc_document d where d.id = 'fxDocSodB2' $q$),
         '{"type": "shipment-order-details", "number": "49250480", "warnings": [], "shipments": 1, "document_id": "fxDocSodB2", "lines_saved": 5, "sum_matches": true, "lines_skipped": 0, "lines_received": 5, "linked_bookings": 1} | surcharge:other-charge-1:7288:Additional charge:fcShipFinB:CAD,surcharge:liftgate-delivery:2833:-:fcShipFinB:CAD,surcharge:fuel:4268:-:fcShipFinB:CAD,base:-:8332:-:fcShipFinB:CAD,tax:tax-hst-on:2954:-:fcShipFinB:CAD | [{"type": "net-terms", "amount_cents": 25675}] | 25675 | 00'),
       pg_temp.chk('D3 두 판(17439 · 25675) + 견적 — 판 = 늦은 것 · extra = other-charge-1 7288(세전) · 세금은 따로(2006 → 2954) · state extra', pg_temp.cc('B', '{state,rate_source,booked_pretax,billed_pretax,extra_cents,extra_lines,tax_booked,tax_billed,booked_total,billed_total,doc_count,last_doc_date,document_id,warnings}'),
         'extra | booking | 15433 | 22721 | 7288 | [{"delta": 7288, "billed": 7288, "booked": 0, "sub_type": "other-charge-1"}] | 2006 | 2954 | 17439 | 25675 | 2 | 2026-11-10 | fxDocSodB2 | []'),
       pg_temp.chk('D4 판 셋(같은 금액) · 금액 = 견적 — billed · extra 0 · 줄 차이 없음 · 판 수 3', pg_temp.cc('A', '{state,extra_cents,extra_lines,doc_count,last_doc_date,document_id,billed_total,warnings}'), 'billed | 0 | [] | 3 | 2026-11-08 | fxDocSodA3 | 1228 | []'),
       pg_temp.chk('D4b UPS 꼴(이견 4) — 견적에 surcharge 줄이 없고 청구가 fuel 을 쪼개 와도 세전 합계가 같으면 billed · extra_lines 는 설명용으로 남는다', pg_temp.cc('U', '{state,extra_cents,extra_lines}'),
         'billed | 0 | [{"delta": -648, "billed": 2900, "booked": 3548, "sub_type": "base"}, {"delta": 648, "billed": 648, "booked": 0, "sub_type": "fuel"}]'),
       pg_temp.chk('D5 문서 없음 — none · Freightcom 에서 취소된 예약도 none', pg_temp.cc('N', '{state,doc_count,extra_cents,billed_total,invoiced_cents,invoice_count}') || ' · ' || pg_temp.cc('X', '{state}'), 'none | 0 | (null) | (null) | (null) | 0 · none'),
       pg_temp.chk('D6 묶음 인보이스 줄 17 · 쉽먼트 넷 — 쉽먼트마다 갈림 · IMS 예약과 이어진 것은 하나 · 그 예약은 unread(판은 없고 인보이스 줄만) · invoiced_cents = 그 쉽먼트 줄 합', pg_temp.j(pg_temp.id('l_inv'), 'lines_saved') || ' ' || pg_temp.j(pg_temp.id('l_inv'), 'shipments') || ' ' || pg_temp.j(pg_temp.id('l_inv'), 'linked_bookings') || ' ' || pg_temp.j(pg_temp.id('l_inv'), 'sum_matches') || ' | ' ||
         pg_temp.try($q$ select string_agg(shipment_fc_id || '=' || n || '/' || c, ',' order by shipment_fc_id collate "C") from (select l.shipment_fc_id, count(*) n, sum(l.amount_cents) c from public.fc_document_line l where l.document_id = 'fxDocInv1' group by 1) q $q$) || ' | ' ||
         pg_temp.try($q$ select d.payments::text from public.fc_document d where d.id = 'fxDocInv1' $q$) || ' | ' || pg_temp.cc('RtJtQ', '{state,invoiced_cents,invoice_count,doc_count}'),
         '17 4 1 true | fcShipFin98siM=4/11813,fcShipFinRtJtQ=5/30401,fcShipFinfK3c8=4/18690,fcShipFinlPggb=4/13020 | [{"type": "credit-card", "amount_cents": 73924}] | unread | 30401 | 1 | 0');
-- 묶음 인보이스가 옛 금액(17439)만 싣고 있을 때 → invoiced_differs · 줄 합 ≠ 문서 금액 → lines_sum_differs · 그 다음 B 를 IMS 취소 꼴로(response 덮임 · 견적은 실제 49250480 의 fc_quote_rate)
select pg_temp.put('l_inv2', pg_temp.lines('ZZT', pg_temp.doc('fxDocInv2', 'fcShipFinB', 104500, '[["base","","8332"],["surcharge","liftgate-delivery","2833"],["surcharge","fuel","4268"],["tax","tax-hst-on","2006"]]')));
select pg_temp.chk('D6b 인보이스 줄 합(17439) ≠ 최신 판(25675) → warnings invoiced_differs · 줄 합 ≠ 문서 금액 → 저장은 되고 lines_sum_differs', pg_temp.cc('B', '{state,invoiced_cents,invoice_count,warnings}') || ' | ' || pg_temp.j(pg_temp.id('l_inv2'), 'sum_matches') || ' ' || pg_temp.j(pg_temp.id('l_inv2'), 'warnings'),
         'extra | 17439 | 1 | ["invoiced_differs — the net-terms invoice lines for this shipment do not add up to the latest order details"] | false ["lines_sum_differs — the lines do not add up to the document amount"]');
select pg_temp.try(format($q$ with u as (update public.fc_booking b set status = 'cancelled', cancelled_at = now(), response = '{"body": null, "http_status": 200}'::jsonb, rate_id = %L where b.id = %L returning 1) select count(*)::text from u $q$, pg_temp.id('real_rate'), pg_temp.id('B'))) as b_cancelled;
select pg_temp.chk('D3b 이견 1 — 취소한 예약에 청구(실물 49250480 꼴) → cancelled_billed · 견적은 고른 견적 줄에서(rate_source quote · 475) · 줄별 차이는 그대로', pg_temp.cc('B', '{state,status,rate_source,booked_pretax,booked_total,extra_cents,extra_lines}'),
         'cancelled_billed | cancelled | quote | 15433 | 17439 | 7288 | [{"delta": 7288, "billed": 7288, "booked": 0, "sub_type": "other-charge-1"}]'),
       pg_temp.chk('D3d 견적이 어디에도 없으면 unknown + no_booked_rate · 통화가 다르면 unknown + currency_differs(비교하지 않는다)',
         pg_temp.try(format($q$ with u as (update public.fc_booking b set response = '{}'::jsonb, rate_id = null where b.id = %L returning 1) select count(*)::text from u $q$, pg_temp.id('A'))) || ' ' || pg_temp.cc('A', '{state,booked_pretax,billed_pretax,warnings}') || ' · ' ||
         pg_temp.j(pg_temp.lines('ZZT', pg_temp.doc('fxDocSodX2', 'fcShipFinU', 4009, '[["base","","2900"],["surcharge","fuel","648"],["tax","tax-hst-on","461"]]', 'USD')), 'lines_saved') || ' ' || pg_temp.cc('U', '{state,warnings}'),
         '1 unknown | (null) | 1087 | ["no_booked_rate — neither the booking answer nor the selected quote has a rate"] · 3 unknown | ["currency_differs — the billed lines are not in the booked currency · not compared"]');

-- ── D7 · D8: 계정 요약 ──
select pg_temp.put('d7', pg_temp.docs('ZZT', '[{"id":"fxDocInvOwe","type":"net-terms-invoice","number":"FC17999999","date":{"year":2026,"month":11,"day":9},"due_date":{"year":2026,"month":12,"day":9},"amount":{"value":"9000","currency":"CAD"},"owing":{"value":"4200","currency":"CAD"}}]')),
       pg_temp.put('b1', pg_temp.bal('ZZT', pg_temp.fx('bal')));
select pg_temp.chk('D7 owing > 0 인 묶음 인보이스 → 결제할 인보이스에 나온다(owing 0 은 안 나온다)', pg_temp.summ('ZZT', '{invoices_owing,owing_cents,owing_count}'),
         '[{"id": "fxDocInvOwe", "number": "FC17999999", "doc_date": "2026-11-09", "due_date": "2026-12-09", "owing_cents": 4200, "amount_cents": 9000}] | 4200 | 1'),
       pg_temp.chk('D8 잔액 756.78 · 한도 5000 → 사용 = 한도 − 잔액(설정 한도 기준 표지) · 저장 반환에 금액 없음', pg_temp.j(pg_temp.id('b1'), 'saved') || ' ' || (pg_temp.id('b1')::jsonb - 'checked_at')::text || ' | ' || pg_temp.summ('ZZT', '{available_cents,limit_cents,used_cents,limit_basis,used_basis,method_type}'),
         'true {"saved": true, "account": "ZZT"} | 75678 | 500000 | 424322 | setting | setting_limit_minus_available | net-terms'),
       pg_temp.chk('D5b 청구 전 예약 합계 — booked · 문서 머리도 줄도 없는 예약만(N 5000) · 인보이스 줄만 있는 것 · Freightcom 취소 · IMS 취소 · 청구된 것은 빠진다', pg_temp.summ('ZZT', '{unbilled_count,unbilled_cents,unbilled_no_rate}'), '1 | 5000 | 0'),
       pg_temp.chk('D8b 잔액 원소 둘 · 0 · 값이 글자 · 목록 아님 → 저장 0 + 경고(이견 5) · 행은 하나 그대로 · 배열 맨몸은 받는다',
         pg_temp.j(pg_temp.bal('ZZT', '{"available_balances":[{"value":"1","currency":"CAD"},{"value":"2","currency":"USD"}]}'), 'warning') || ' · ' || pg_temp.j(pg_temp.bal('ZZT', '{"available_balances":[]}'), 'saved') || ' · ' || pg_temp.j(pg_temp.bal('ZZT', '[{"value":"7.5"}]'), 'warning') || ' · ' ||
         pg_temp.j(pg_temp.bal('ZZT', '{"x":1}'), 'warning') || ' · ' || pg_temp.try($q$ select count(*)::text from public.fc_balance f where f.account = 'ZZT' $q$) || ' · ' || pg_temp.j(pg_temp.bal('ZZT', '[{"value":"60000","currency":""}]'), 'saved'),
         'balance_count — the answer has 2 balances (expected exactly 1) · nothing was saved · false · balance_value — the balance is not a whole number of cents · nothing was saved · balance_shape — the answer has no available_balances list · nothing was saved · 1 · true'),
       pg_temp.chk('D8c 가장 늦은 잔액이 지금 값 · 한도 설정이 소수 · 글자 · 없음 → 한도 · 사용만 null(남은 한도는 그대로) · 90 일 지난 잔액 행은 저장 때 지워진다',
         pg_temp.summ('ZZT', '{available_cents,used_cents}') || ' · ' ||
         pg_temp.try($q$ with u as (update public.inv_config c set value = '5000.50' where c.key = 'fc_credit_limit_ZZT' returning 1) select count(*)::text from u $q$) || ' ' || pg_temp.summ('ZZT', '{limit_cents,used_cents}') || ' · ' ||
         pg_temp.try($q$ with u as (update public.inv_config c set value = 'about 5k' where c.key = 'fc_credit_limit_ZZT' returning 1) select count(*)::text from u $q$) || ' ' || pg_temp.summ('ZZT', '{available_cents,limit_cents,used_cents}') || ' · ' || pg_temp.summ('ZZQ', '{available_cents,limit_cents,unbilled_count,invoices_owing}') || ' · ' ||
         pg_temp.try($q$ with u as (update public.fc_balance f set checked_at = now() - interval '100 days' where f.account = 'ZZT' and f.available_cents = 75678 returning 1) select count(*)::text from u $q$) || ' ' || pg_temp.j(pg_temp.bal('ZZT', '[{"value":"61000"}]'), 'saved') || ' ' ||
         pg_temp.try($q$ select string_agg(f.available_cents::text, ',' order by f.id) from public.fc_balance f where f.account = 'ZZT' $q$),
         '60000 | 440000 · 1 500050 | 440050 · 1 60000 | (null) | (null) · (null) | (null) | 0 | [] · 1 true 60000,61000');

-- ── D10: 줄 다시 읽기(이견 7) · 줄 저장 거부 ──
select pg_temp.chk('D10a 줄을 읽은 문서는 need 에서 빠진다(남은 것 0 — fxDocInvOwe 는 인보이스라 남는다)', pg_temp.try($q$ select coalesce(string_agg(d.document_id, ','), '(none)') || ' ' || coalesce(max(d.need_total), 0) from public.fc_finance_lines_due('ZZT', 25) d $q$), 'fxDocInvOwe 1');
select pg_temp.put('d10', pg_temp.docs('ZZT', jsonb_set(jsonb_build_array(pg_temp.fx('docs')->4), '{0,amount,value}', '"25700"')));
select pg_temp.chk('D10b 같은 id 의 머리 금액이 바뀌면 다시 읽을 문서가 된다 · 다시 읽으면 줄은 갈아 끼워지고(5 그대로) 빠진다 · 목록과 문서의 금액이 다르면 amount_differs(목록 값을 지킨다)', pg_temp.j(pg_temp.id('d10'), 'need_lines') || ' ' ||
         pg_temp.j(pg_temp.lines('ZZT', pg_temp.fx('sod')), 'warnings') || ' ' || pg_temp.try($q$ select (select count(*) from public.fc_document_line l where l.document_id = 'fxDocSodB2') || ' ' || d.amount_cents || ' ' || d.lines_amount_cents || ' ' || (select count(*) from public.fc_finance_lines_due('ZZT', 25) x where x.document_id = 'fxDocSodB2') from public.fc_document d where d.id = 'fxDocSodB2' $q$),
         '["fxDocSodB2", "fxDocInvOwe"] ["amount_differs — the document and the list give different amounts · the list value was kept"] 5 25700 25700 0'),
       pg_temp.chk('D10c 줄 저장 거부 — 목록에 없는 문서 · 다른 계정 · line_items 없음 · id 없음 · 직원 · id · 금액 없는 줄은 세고 지나간다',
         pg_temp.err(pg_temp.lines('ZZT', '{"id":"fxNope","line_items":[]}'), '%is not in the list yet%') || ' ' || pg_temp.err(pg_temp.lines('ZZU', pg_temp.fx('sod')), '%belongs to account ZZT%') || ' ' || pg_temp.err(pg_temp.lines('ZZT', '{"id":"fxDocSodX1"}'), '%no line_items list%') || ' ' ||
         pg_temp.err(pg_temp.lines('ZZT', '{"line_items":[]}'), '%has no id%') || ' ' || pg_temp.err(pg_temp.usr('W', format('select public.fc_finance_lines_save(%L, %L::jsonb)::text', 'ZZT', pg_temp.fx('sod'))), 'ERR 42501%') || ' ' ||
         pg_temp.j(pg_temp.lines('ZZT', '{"id":"fxDocSodX1","amount":{"value":"16918"},"line_items":[{"id":"a","type":"base","amount":{"value":"16918"}},{"id":"","amount":{"value":"1"}},{"id":"b","amount":{"value":"x"}},{"id":"a","amount":{"value":"2"}},"junk"]}'), 'lines_saved'),
         'refused refused refused refused refused 1');

-- ── 문 · 권한 · 구조 ──
select pg_temp.chk('G1 사람 길의 문 — purchasing(창고 전부) · freight_booking + 그 창고는 통과 · 다른 창고 · 권한 없음(sales) · 모르는 계정 · 계정 꼴은 거부', pg_temp.j(pg_temp.usr('P', $q$ select public.fc_finance_gate('tor')::text $q$)) || ' ' || pg_temp.j(pg_temp.usr('W', $q$ select public.fc_finance_gate('TOR')::text $q$), 'account') || ' ' || pg_temp.j(pg_temp.usr('E', $q$ select public.fc_finance_gate('EDM')::text $q$), 'account') || ' ' ||
         pg_temp.err(pg_temp.usr('E', $q$ select public.fc_finance_gate('TOR')::text $q$), '%belongs to another warehouse%') || ' ' || pg_temp.err(pg_temp.usr('N', $q$ select public.fc_finance_gate('TOR')::text $q$), '%You cannot refresh Freightcom billing%') || ' ' ||
         pg_temp.err(pg_temp.usr('P', $q$ select public.fc_finance_gate('VAN')::text $q$), '%No warehouse uses%') || ' ' || pg_temp.err(pg_temp.usr('P', $q$ select public.fc_finance_gate('t o r')::text $q$), '%2–10 upper-case%'), '{"account": "TOR"} TOR EDM refused refused refused refused'),
       pg_temp.chk('D9a 1166 — 로그인한 직원(purchasing)은 새 표 셋을 못 읽는다', pg_temp.err(pg_temp.usr('P', 'select count(*)::text from public.fc_document'), 'ERR 42501%') || ' ' || pg_temp.err(pg_temp.usr('P', 'select count(*)::text from public.fc_document_line'), 'ERR 42501%') || ' ' || pg_temp.err(pg_temp.usr('P', 'select count(*)::text from public.fc_balance'), 'ERR 42501%'), 'refused refused refused'),
       pg_temp.chk('D9b 직원은 판정 · 요약 · 대상 · 저장 창구를 못 부른다(화면 창구는 fc-track-4)', pg_temp.err(pg_temp.usr('P', format('select public.fc_charge_check(%L)::text', pg_temp.id('N'))), 'ERR 42501%') || ' ' || pg_temp.err(pg_temp.usr('P', $q$ select public.fc_finance_account_summary('ZZT')::text $q$), 'ERR 42501%') || ' ' ||
         pg_temp.err(pg_temp.usr('P', $q$ select count(*)::text from public.fc_finance_lines_due('ZZT', 5) $q$), 'ERR 42501%') || ' ' || pg_temp.err(pg_temp.usr('P', $q$ select public.fc_finance_balance_save('ZZT', 'net-terms', '[{"value":"1"}]'::jsonb)::text $q$), 'ERR 42501%') || ' ' ||
         pg_temp.err(pg_temp.usr('P', format('select public.fc_booking_rate(b)::text from public.fc_booking b where b.id = %L', pg_temp.id('N'))), 'ERR 42501%'), 'refused refused refused refused refused'),
       pg_temp.chk('D9c service_role 은 읽기만 — 표에 직접 쓰기 · 지우기는 거부(쓰기는 창구로만) · 창구는 role 만으로는 안 되고 service_role JWT 여야 한다', pg_temp.svc('select (count(*) > 0)::text from public.fc_document') || ' ' ||
         pg_temp.err(pg_temp.svc($q$ insert into public.fc_balance (account, available_cents) values ('ZZT', 1) returning 'x' $q$), 'ERR 42501%') || ' ' || pg_temp.err(pg_temp.svc($q$ with d as (delete from public.fc_document_line where document_id = 'fxDocSodB2' returning 1) select count(*)::text from d $q$), 'ERR 42501%') || ' ' ||
         pg_temp.err(pg_temp.svc($q$ with u as (update public.fc_document set owing_cents = 1 where id = 'fxDocSodB2' returning 1) select count(*)::text from u $q$), 'ERR 42501%') || ' ' ||
         pg_temp.err(pg_temp.try($q$ select public.fc_finance_docs_save('ZZT', '[]'::jsonb)::text $q$), '%freight service only%'), 'true refused refused refused refused'),
       pg_temp.chk('S1 표 셋 — RLS 켬 · 정책 0 · authenticated · anon 권한 0 · service_role 은 select 만', pg_temp.try($q$ select string_agg(c.relname || ' ' || c.relrowsecurity || ' ' || (select count(*) from pg_policy p where p.polrelid = c.oid) || ' ' ||
              (select coalesce(string_agg(g.grantee || ':' || g.privilege_type, ',' order by g.grantee, g.privilege_type), '-') from information_schema.role_table_grants g where g.table_schema = 'public' and g.table_name = c.relname and g.grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')), ' · ' order by c.relname)
              from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('fc_document', 'fc_document_line', 'fc_balance') $q$),
         'fc_balance true 0 service_role:SELECT · fc_document true 0 service_role:SELECT · fc_document_line true 0 service_role:SELECT'),
       pg_temp.chk('S2 함수 권한 — 저장 셋 · 대상 · 판정 · 요약은 service_role 만 · 문은 authenticated · 속 함수 셋은 아무도', pg_temp.try($q$ select string_agg(p.proname || ' ' || has_function_privilege('service_role', p.oid, 'execute')::text || has_function_privilege('authenticated', p.oid, 'execute')::text || has_function_privilege('anon', p.oid, 'execute')::text, ' · ' order by p.proname)
              from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fc_doc_cents', 'fc_doc_date', 'fc_booking_rate', 'fc_finance_lines_due', 'fc_finance_docs_save', 'fc_finance_lines_save', 'fc_finance_balance_save', 'fc_charge_check', 'fc_finance_account_summary', 'fc_finance_gate') $q$),
         'fc_booking_rate falsefalsefalse · fc_charge_check truefalsefalse · fc_doc_cents falsefalsefalse · fc_doc_date falsefalsefalse · fc_finance_account_summary truefalsefalse · fc_finance_balance_save truefalsefalse · fc_finance_docs_save truefalsefalse · fc_finance_gate truetruefalse · fc_finance_lines_due truefalsefalse · fc_finance_lines_save truefalsefalse'),
       pg_temp.chk('S3 스위치 · 상한 · 한도 — fc_finance_poll_enabled 는 off 로 시작하거나 Caleb 이 켠 on · batch 는 수 · 한도 둘은 달러 수', pg_temp.try($q$ select ((select c.value from public.inv_config c where c.key = 'fc_finance_poll_enabled') in ('off', 'on'))::text || ' ' || ((select c.value from public.inv_config c where c.key = 'fc_finance_doc_batch') ~ '^[0-9]{1,3}$')::text || ' ' ||
              (select count(*) from public.inv_config c where c.key in ('fc_credit_limit_TOR', 'fc_credit_limit_EDM') and c.value ~ '^\d{1,9}(\.\d{1,2})?$') $q$), 'true true 2'),
       pg_temp.chk('S4 파서 — 센트(글자 · 수 · 음수 · 소수 · 글자 값 · 빈 것) · 날짜(없는 날 · 꼴 아님)', pg_temp.try($q$ select concat_ws(' ', public.fc_doc_cents('{"value":"16918"}'), public.fc_doc_cents('{"value":16918}'), public.fc_doc_cents('{"value":"-250"}'), coalesce(public.fc_doc_cents('{"value":"1.5"}')::text, 'n'), coalesce(public.fc_doc_cents('{"value":"abc"}')::text, 'n'), coalesce(public.fc_doc_cents('{}')::text, 'n'), coalesce(public.fc_doc_cents(null)::text, 'n'), coalesce(public.fc_doc_cents('"5"')::text, 'n'),
              public.fc_doc_date('{"year":2026,"month":11,"day":8}'), coalesce(public.fc_doc_date('{"year":2026,"month":2,"day":30}')::text, 'n'), coalesce(public.fc_doc_date('{"year":"x"}')::text, 'n'), coalesce(public.fc_doc_date(null)::text, 'n')) $q$), '16918 16918 -250 n n n n n 2026-11-08 n n n'),
       pg_temp.chk('R1 REST 겹 ① — 새 함수 열의 깊이 0 WHERE 없는 update · delete = 0', pg_temp.try($q$ select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc)::text, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'fc\_finance\_%' or p.proname in ('fc_doc_cents', 'fc_doc_date', 'fc_booking_rate', 'fc_charge_check')) $q$),
         'fc_booking_rate=0,fc_charge_check=0,fc_doc_cents=0,fc_doc_date=0,fc_finance_account_summary=0,fc_finance_balance_save=0,fc_finance_docs_save=0,fc_finance_gate=0,fc_finance_lines_due=0,fc_finance_lines_save=0'),
       pg_temp.chk('G2 무접촉 — begin 앞의 fc_ 함수는 하나도 안 바뀌었다 · fc_ 함수는 49 · fc_booking 칸 수 그대로(41)', pg_temp.try($q$ select (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5 where p.oid is null) || ' ' ||
              (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fc\_%') || ' ' || (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'fc_booking') $q$), '(none) 49 41');

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(가짜 행 모두 rollback) ──'
select n, case when ok then 'OK  ' else 'FAIL' end as r, label, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' · want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, (count(*) filter (where not ok) > 0 or count(*) filter (where ok) <> :EXPECT_OK) as bad from t_res \gset
\echo 'OK' :ok '· FAIL' :fail '· total' :total '· expect_ok' :EXPECT_OK
select round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — t 여야 한다'
select (select count(*) from public.fc_booking) = :n_bk0 and (select count(*) from public.ims_staff) = :n_staff0 and (select count(*) from public.inv_config) = :n_cfg0
   and (select max(version) from supabase_migrations.schema_migrations) = :'ver0' and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fc\_%') = :n_fn0
   and coalesce(pg_temp.try('select count(*)::text from public.fc_document'), '-') = :'n_doc0' as rolled_back_clean;
\if :bad
do $$ begin raise exception 'fc_track_3_check: FAIL or OK count differs from EXPECT_OK — see the result table above'; end $$;
\endif
