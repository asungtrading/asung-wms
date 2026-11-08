-- supabase/migrations/20261108224000_qbo_sync_3_2b_cost_day_jobs.sql — qbo-sync-3-2b: 하루 원가 장 DB 뒤 절반 (2026-11-08 밤 · 지시서 ~/asung/prompts/qbo-sync-3-2b.md · §0 이견 1 ~ 10 · ⬜1 ~ ⬜8 Caleb 답 전부 받음 · 정본 qbo-integration §15-h ⑥ · so-module §105-a 1092 · 1093 · 1097 · 1098 · 1101 · 1103)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied 20261108224000 --yes · ⚠️ db push 쓰지 않는다 · 3-2a(20261108170000) 뒤
-- 3-2b = 일감 kind cost_day(ims_kind cost_sheet · ims_id 「YYYY-MM-DD|TOR」 · rebuild 는 「|rebuild」 · 이견 13) · 몸(JE JSON) · claim / done / retry / doc / list / preview 재발행 여섯 · 장 state 트리거 · 차례(wait_job) · 재생성 hold · release(미리 보기) · resolve · 사람 창구 queue
-- 설계 요지(§0 답):
--   · ⬜1 (가) 장 하나 = 일감 하나 — qbo_job_open_idx 가 장마다 열린 일감 하나 · 장 state 는 qbo_job AFTER UPDATE OF state 트리거(kind cost_day)가 따라간다(이견 2): queued · blocked → pending · sending → sending · sent → sent(qbo_id · sent_at) · failed → failed(장이 hold 면 유지 · sent 에서 떨어지면 unknown) · unknown → unknown · skipped → void(empty 면 유지)
--   · ⬜2 줄은 claim 때 굳는다 — 몸 qbo_cost_day_body(stable · preview 도 부른다)가 calc 로 줄 · JE JSON · 보낸 몫 행을 돌려주고 claim 이 qbo_cost_sent 에 넣는다 · done 은 다시 셈하지 않는다(TotalAmt ↔ 지문의 차변 센트 대조 · qbo_txn JournalEntry) · 행 불변식: day 장의 행은 sending · unknown · sent 에만 있다(트리거가 queued · failed · skipped 에서 지운다) · rebuild 장의 행은 release 때 굳고 void 에서만 지운다
--   · ⬜3 차례 — 몸이 같은 창고의 가장 가까운 앞 장(날짜 앞 day · 또는 미보낸 rebuild)을 보고 sent · empty · void 가 아니면 wait_job(그 일감) → blocked · 앞 장에 일감이 없으면 failed 「queue the earlier sheet first」 · queue 는 날짜 순으로만 · skip 은 sent 로 안 친다(void · 행 0 · 뒤 장 차액이 담는다 · 1092) · claim ② 는 cost_day 에 한해 부모 skipped 도 푼다
--   · ⬜4 재생성(1093) — claim 때 min(inv_layer_consume.id) > 장 epoch 면 realm 의 미보낸 장 전부 hold(두 창고) · 일감 failed(풀어 주는 길은 last_error) · qbo_cost_rebuild_preview → qbo_cost_rebuild_release(note): 창고마다 「기대_new(≤ 마지막 보낸 날) − Σ보낸」 을 이미 보낸 열쇠에 한해 열쇠 행으로 굳히고 JE 는 계정 짝당 한 줄 「IMS cost rebuild」 · kind rebuild · COGS-<풀어 준 날>-TOR-R · TxnDate = 풀어 준 날 · 0 이면 장 없이 epoch 만 갱신 · 멈춘 장 pending + queued(request_id 새로) · 새 열쇠(보낸 적 없음)는 뒤 day 장이 보통 줄로
--   · ⬜5 resolve(1101 · 이견 3) — unknown 장만 · in_qbo(QBO Id · 장 sent · qbo_txn) | not_in_qbo(행 삭제 · pending · 일감 queued · request_id 새로) · 「QBO 에 하나 남김 = in_qbo · 하나도 안 남김 = skip(void)」
--   · ⬜6 (나′) Entity 짝 없는 손님은 needs → claim ④ 가 customer 일감을 세우거나 재사용하고 장은 blocked · 빠져나오는 길 셋 = ① 화면 손 Send(sendPicked · isNeedKind customer · EF 무변) ② 3-3 원가 cron kinds [cost_day, customer] ③ 그 인보이스가 먼저 나가도 ② 가 푼다
--   · ⬜7 자동으로 일감을 세우는 곳 0 — 사람 창구 qbo_cost_sheet_queue(날 · 창고) · qbo_cost_queue_due()(일감 없는 pending 장 · 날짜 순) · cron · build 에 잇는 것은 3-3 · EF SEND_KINDS 에 cost_day 가 없어 cron 61 · 62 · 손 Send 는 cost_day 를 집지 못한다(Q4 · S7)
--   · JE 몸(1097 · 1102 · 1103): DocNumber COGS-YYYYMMDD-TOR(-R) · TxnDate 장 날 · PrivateNote 「IMS cost day …」 · Line = 열쇠마다 #59 아닌 계정 한 줄(Description 열쇠 + 차액 꼬리 · 손님 이름 글자 없음) + 그 창고 #59 순액 한 줄 · #58 줄 Entity{Customer} = qbo_link 손님 · DepartmentRef 없음 · AccountRef 는 qbo_account_ref(짝 없으면 예외 → failed)
--   · 새 표 0 · 거래 표 FK 0(ims_id 다형) → 컷오버 날 지우는 순서 영향 없음 · 시퀀스 0 · 자동 재시도 없음(2a 원칙)
-- 하지 않는 것: EF(3-3 · SEND_KINDS 19 · journalentry 쓰기 · DocNumber 멱등 · unknown 풀기 · cron kinds) · 화면(3-4) · cron 등록(ims-qbo-cost-build 는 적용 뒤 Caleb · supabase/ops/cron.sql) · 3-2a 함수 무변 · qbo_job_fail · skip · unknown · unknown_list 무변(md5 가드만)
-- ⚠️ 공개 레포 — 손님 · 공급처 상호 없음 · UI 글자는 영어 · jsonb_build_object 안에 「--」 줄 주석을 두지 않는다
-- 검증 supabase/tests/qbo_sync_3_2b_check.sql(운영 메인 begin → rollback · 가짜 재료만 · since 를 2026-01-05 로 옮겨 실제 사건 0 · 10 초 안) · 적용은 Caleb

-- ═══════════════ ⓪ 재발행 원본 가드 — 여섯의 DB prosrc md5 · 무변 넷 · 같은 이름 하나씩 · 3-2a 있음 · 아직 미적용 ═══════════════
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_claim')        is distinct from 'de6a6fec2c7925ca9be82b1db6e612c3' then v_bad := v_bad || ' qbo_job_claim'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_done')         is distinct from 'bfde1f1087164fbd9f57695fa63d1ddd' then v_bad := v_bad || ' qbo_job_done'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_retry')        is distinct from '004924bca6930c77b34457b6446f7d57' then v_bad := v_bad || ' qbo_job_retry'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_list')         is distinct from 'd72b4c8edbbfec4fdbe45fa04c618cbf' then v_bad := v_bad || ' qbo_job_list'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_preview')      is distinct from '07c73ffda11366b176fabd6115280c8d' then v_bad := v_bad || ' qbo_job_preview'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_doc')          is distinct from '4291e46d184438d3463e2ad99b7a679f' then v_bad := v_bad || ' qbo_job_doc'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_fail')         is distinct from 'fdd230fa5b4de73c7345b32836ef8439' then v_bad := v_bad || ' qbo_job_fail(unchanged-by-design)'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_skip')         is distinct from 'da0159236db83940236385b25ca803d2' then v_bad := v_bad || ' qbo_job_skip(unchanged-by-design)'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_unknown')      is distinct from 'e6ada9ef69cb2f0f739a969623966466' then v_bad := v_bad || ' qbo_job_unknown(unchanged-by-design)'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_unknown_list') is distinct from '32df84b1e10bb8241daedb4918462697' then v_bad := v_bad || ' qbo_job_unknown_list(unchanged-by-design)'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc')) <> 6 then v_bad := v_bad || ' overloads'; end if;
  if to_regprocedure('public.qbo_cost_sheet_calc(date, text, text)') is null or to_regprocedure('public.qbo_cost_sheet_build(date, text, text)') is null or to_regprocedure('public.qbo_account_ref(text, text)') is null or to_regclass('public.qbo_cost_sent') is null then v_bad := v_bad || ' prerequisites(3-2a 20261108170000 · 2a)'; end if;
  if to_regprocedure('public.qbo_cost_day_body(uuid)') is not null or exists (select 1 from pg_constraint where conname = 'qbo_job_kind_ck' and pg_get_constraintdef(oid) like '%cost_day%') or exists (select 1 from pg_trigger where tgname = 'qbo_job_cost_sheet_sync') then v_bad := v_bad || ' already-applied'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current bodies first — nothing was changed', v_bad; end if;
end $$;

-- ═══════════════ ① 이름 · 장 찾기 — ims_id 꼴 · 일감 → 장 ═══════════════
create function public.qbo_cost_sheet_ims_id(p_date date, p_wh text, p_kind text) returns text
  language sql immutable
as $$
  select to_char(p_date, 'YYYY-MM-DD') || '|' || p_wh || case when p_kind = 'rebuild' then '|rebuild' else '' end;
$$;
comment on function public.qbo_cost_sheet_ims_id(date, text, text) is '[qbo-sync-3-2b · 이견 13 · ⬜1] 하루 원가 장 일감의 ims_id — 「YYYY-MM-DD|TOR」 · rebuild 장은 「YYYY-MM-DD|TOR|rebuild」(ims_kind cost_sheet · kind cost_day)';

create function public.qbo_cost_sheet_id_for_job(p_job uuid) returns uuid
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v uuid := (select s.id from public.qbo_cost_sheet s where s.job_id = p_job);
begin
  if v is null then raise exception 'No cost day sheet is attached to job % — queue the sheet with qbo_cost_sheet_queue first', p_job; end if;
  return v;
end;
$$;
comment on function public.qbo_cost_sheet_id_for_job(uuid) is '[qbo-sync-3-2b] 일감 → 장 id(qbo_cost_sheet.job_id · 장 하나 = 일감 하나 · 없으면 예외 → claim 은 그 일감을 failed 로) · grant 0(claim · preview 가 부른다)';

-- ═══════════════ ② 몸 — JE JSON · 줄 · 보낸 몫 행 · needs · wait_job · hold · empty (stable · claim · preview 가 부른다 · 쓰지 않는다) ═══════════════
-- 돌려주는 것: hold(재생성 글) | wait_job + wait_reason(차례) | empty true(보낼 줄 0) | 몸 = kind · ims_kind · ims_id · sheet_id · sheet_kind · wh · doc_number · name · body(JournalEntry) · lines(보낸 몫 행) · line_count · totals · fingerprint 「<차변 센트>|<줄 md5>」 · needs(짝 없는 손님) · warnings · lookup
create function public.qbo_cost_day_body(p_sheet_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_s public.qbo_cost_sheet%rowtype; v_prev public.qbo_cost_sheet%rowtype; v_epoch bigint; v_nb int; v_blocks text; v_rows jsonb; v_je jsonb; v_dr bigint; v_cr bigint; v_inv bigint; v_n int; v_needs jsonb; v_ims_id text; v_note text;
begin
  select * into v_s from public.qbo_cost_sheet s where s.id = p_sheet_id;
  if v_s.id is null then raise exception 'Cost day sheet % not found — nothing was read', p_sheet_id; end if;
  if v_s.state in ('sent', 'empty', 'void') then raise exception 'Cost day % is % — nothing to send', v_s.doc_number, v_s.state; end if;
  v_ims_id := public.qbo_cost_sheet_ims_id(v_s.sheet_date, v_s.wh, v_s.kind);
  -- 재생성(1093 · ⬜4): 소진 표가 통째로 다시 섰으면 min(id) 가 커진다 → claim 이 realm 의 미보낸 장 전부를 hold 로
  select coalesce(min(c.id), 0) into v_epoch from public.inv_layer_consume c;
  if v_epoch > v_s.epoch then
    return jsonb_build_object('hold', format('cost rebuild detected (consume epoch %s → %s): the cost layers were rebuilt after this sheet was prepared — every unsent cost day is on hold · review Cost days → rebuild preview (qbo_cost_rebuild_preview) and release it (qbo_cost_rebuild_release) · Retry is refused until then', v_s.epoch, v_epoch),
                              'sheet_id', v_s.id, 'doc_number', v_s.doc_number, 'ims_id', v_ims_id);
  end if;
  -- 차례(1098 · ⬜3): 같은 창고의 가장 가까운 앞 장(미보낸 rebuild 장 먼저 · 그 다음 날짜 앞 day 장) 이 sent · empty · void 가 아니면 그 일감 뒤에 선다
  select * into v_prev from public.qbo_cost_sheet s
   where s.realm_id = v_s.realm_id and s.wh = v_s.wh and s.id <> v_s.id and s.state not in ('sent', 'empty', 'void')
     and ((s.kind = 'rebuild' and v_s.kind = 'day') or (s.kind = 'day' and v_s.kind = 'day' and s.sheet_date < v_s.sheet_date))
   order by (s.kind = 'rebuild') desc, s.sheet_date desc, s.created_at desc limit 1;
  if v_prev.id is not null then
    if v_prev.job_id is null then raise exception 'Earlier cost day % (%) is not queued yet — cost days go to QuickBooks in date order · queue the earlier sheet first', v_prev.doc_number, v_prev.state; end if;
    return jsonb_build_object('wait_job', v_prev.job_id, 'wait_reason', format('waiting for %s (%s) to reach QuickBooks first — cost days go in date order', v_prev.doc_number, v_prev.state),
                              'sheet_id', v_s.id, 'doc_number', v_s.doc_number, 'ims_id', v_ims_id, 'warnings', '[]'::jsonb);
  end if;
  if v_s.kind = 'rebuild' then
    -- rebuild 장: 줄 = release 때 굳힌 보낸 몫 행을 계정 짝으로 모은다 · 짝마다 두 줄 「IMS cost rebuild」 · Entity 없음
    with p as (select t.acct_a, t.acct_b, sum(t.cents)::bigint as c from public.qbo_cost_sent t where t.sheet_id = v_s.id group by t.acct_a, t.acct_b having sum(t.cents) <> 0),
    k as (select p.acct_a as acct, p.c as signed from p union all select p.acct_b, -p.c from p)
    select coalesce(jsonb_agg(jsonb_build_object('Description', 'IMS cost rebuild', 'Amount', round(abs(k.signed) / 100.0, 2), 'DetailType', 'JournalEntryLineDetail',
                                                 'JournalEntryLineDetail', jsonb_build_object('PostingType', case when k.signed > 0 then 'Debit' else 'Credit' end, 'AccountRef', jsonb_build_object('value', public.qbo_account_ref(k.acct, 'cost rebuild line'))))
                              order by k.signed < 0, k.acct), '[]'::jsonb),
           coalesce(sum(k.signed) filter (where k.signed > 0), 0), coalesce(-sum(k.signed) filter (where k.signed < 0), 0), count(*)::int
      into v_je, v_dr, v_cr, v_n
    from k;
    if v_n = 0 then raise exception 'Rebuild sheet % has no lines on file — release the rebuild again under Cost days', v_s.doc_number; end if;
    select coalesce(jsonb_agg(jsonb_build_object('key_kind', t.key_kind, 'doc_key', t.doc_key, 'acct_a', t.acct_a, 'acct_b', t.acct_b, 'cents', t.cents) order by t.key_kind, t.doc_key, t.acct_a, t.acct_b), '[]'::jsonb) into v_rows from public.qbo_cost_sent t where t.sheet_id = v_s.id;
    v_needs := '[]'::jsonb;
    v_note := 'IMS cost rebuild released ' || v_s.sheet_date::text || ' ' || v_s.wh;
  else
    if exists (select 1 from public.qbo_cost_sent t where t.sheet_id = v_s.id) then raise exception 'Cost day % (%) already has lines on file — resolve it by hand (qbo_cost_sheet_resolve) before sending again', v_s.doc_number, v_s.state; end if;
    -- 한 번의 calc(CTE 는 한 번만 돈다): 막힘 · 보낸 몫 행 · 열쇠 줄(1097: #59 아닌 계정 · 부호 = 그 계정이 차변이면 +) · #59 순액 · needs(Entity 짝 없는 손님 · 1103 · ⬜6)
    with c as (select * from public.qbo_cost_sheet_calc(v_s.sheet_date, v_s.wh, v_s.realm_id)),
    snd as (select * from c where c.status = 'send' and c.diff_cents <> 0),
    k as (
      select s.label, s.key_kind, s.doc_key, s.entity_qbo_id, s.acct_a as acct, s.diff_cents as signed from snd s where s.acct_a <> '_59_'
      union all
      select s.label, s.key_kind, s.doc_key, s.entity_qbo_id, s.acct_b, -s.diff_cents from snd s where s.acct_b <> '_59_'
    ),
    need as (select s.entity_customer_id as cid, min(s.doc_key) as k from snd s where s.entity_customer_id is not null and s.entity_qbo_id is null and '_58_' in (s.acct_a, s.acct_b) group by s.entity_customer_id)
    select (select count(*) from c where c.status = 'block'),
           (select string_agg(left(x.reason, 160), ' · ' order by x.doc_key) from (select c.doc_key, c.reason, row_number() over (order by c.doc_key) as rn from c where c.status = 'block') x where x.rn <= 5),
           (select coalesce(jsonb_agg(jsonb_build_object('key_kind', s.key_kind, 'doc_key', s.doc_key, 'acct_a', s.acct_a, 'acct_b', s.acct_b, 'cents', s.diff_cents) order by s.key_kind, s.doc_key, s.acct_a, s.acct_b), '[]'::jsonb) from snd s),
           (select coalesce(jsonb_agg(jsonb_build_object('Description', left(k.label, 4000), 'Amount', round(abs(k.signed) / 100.0, 2), 'DetailType', 'JournalEntryLineDetail',
                                                         'JournalEntryLineDetail', jsonb_build_object('PostingType', case when k.signed > 0 then 'Debit' else 'Credit' end, 'AccountRef', jsonb_build_object('value', public.qbo_account_ref(k.acct, 'cost day line ' || k.doc_key)))
                                                           || case when k.acct = '_58_' and k.entity_qbo_id is not null then jsonb_build_object('Entity', jsonb_build_object('Type', 'Customer', 'EntityRef', jsonb_build_object('value', k.entity_qbo_id))) else '{}'::jsonb end)
                                      order by k.key_kind, k.doc_key, k.acct), '[]'::jsonb) from k),
           (select coalesce(sum(k.signed) filter (where k.signed > 0), 0) from k), (select coalesce(-sum(k.signed) filter (where k.signed < 0), 0) from k),
           (select coalesce(sum(case when s.acct_a = '_59_' then s.diff_cents else 0 end) + sum(case when s.acct_b = '_59_' then -s.diff_cents else 0 end), 0) from snd s),
           (select count(*)::int from k),
           (select coalesce(jsonb_agg(jsonb_build_object('kind', 'customer', 'ims_id', n.cid::text, 'name', 'customer of ' || n.k) order by n.k), '[]'::jsonb) from need n)
      into v_nb, v_blocks, v_rows, v_je, v_dr, v_cr, v_inv, v_n, v_needs;
    if v_nb > 0 then raise exception 'Cost day % %: % event(s) cannot be mapped to a QuickBooks line — fix or decide them first: %', v_s.sheet_date, v_s.wh, v_nb, v_blocks; end if;
    if v_n = 0 then return jsonb_build_object('empty', true, 'sheet_id', v_s.id, 'doc_number', v_s.doc_number, 'ims_id', v_ims_id); end if;
    if v_inv <> 0 then
      v_je := v_je || jsonb_build_object('Description', 'Inventory ' || v_s.wh, 'Amount', round(abs(v_inv) / 100.0, 2), 'DetailType', 'JournalEntryLineDetail',
                                         'JournalEntryLineDetail', jsonb_build_object('PostingType', case when v_inv > 0 then 'Debit' else 'Credit' end, 'AccountRef', jsonb_build_object('value', public.qbo_account_ref('_59_', 'inventory ' || v_s.wh))));
      if v_inv > 0 then v_dr := v_dr + v_inv; else v_cr := v_cr - v_inv; end if;
      v_n := v_n + 1;
    end if;
    v_note := 'IMS cost day ' || v_s.sheet_date::text || ' ' || v_s.wh;
  end if;
  if v_dr <> v_cr then raise exception 'Cost day % does not balance (debit % · credit % cents) — nothing was sent', v_s.doc_number, v_dr, v_cr; end if;
  return jsonb_build_object('kind', 'cost_day', 'ims_kind', 'cost_sheet', 'ims_id', v_ims_id, 'sheet_id', v_s.id, 'sheet_kind', v_s.kind, 'wh', v_s.wh, 'doc_number', v_s.doc_number, 'name', v_s.doc_number,
    'body', jsonb_build_object('DocNumber', v_s.doc_number, 'TxnDate', v_s.sheet_date, 'PrivateNote', v_note, 'Line', v_je),
    'lines', v_rows, 'line_count', v_n,
    'totals', jsonb_build_object('debit_cents', v_dr, 'credit_cents', v_cr, 'debit', round(v_dr / 100.0, 2), 'credit', round(v_cr / 100.0, 2), 'line_count', v_n, 'balanced', true),
    'fingerprint', v_dr::text || '|' || md5(v_rows::text),
    'needs', v_needs, 'warnings', '[]'::jsonb,
    'lookup', jsonb_build_object('doc_number', v_s.doc_number, 'txn_date', v_s.sheet_date, 'total_amt', round(v_dr / 100.0, 2)),
    'epoch', v_s.epoch);
end;
$$;
comment on function public.qbo_cost_day_body(uuid) is '[qbo-sync-3-2b · 판정 1092 · 1093 · 1097 · 1098 · 1103 · ⬜2 ~ ⬜6] 하루 원가 장 일감의 몸(stable · grant 0 · claim · preview 가 부른다) — ① epoch 가 커졌으면 {hold: 글}(claim 이 realm 전부 hold) ② 같은 창고 앞 장이 sent · empty · void 가 아니면 {wait_job} · 앞 장에 일감이 없으면 예외 ③ day: calc 한 번 → block 이면 예외 · 보낼 줄 0 이면 {empty} · JournalEntry(DocNumber · TxnDate · PrivateNote · Line = 열쇠마다 #59 아닌 계정 줄 + #59 순액 한 줄 · #58 줄 Entity Customer) · lines(보낸 몫 행 · claim 이 넣는다) · fingerprint 「<차변 센트>|<줄 md5>」 · needs(Entity 짝 없는 손님 → claim 이 customer 일감 세우고 blocked · 빠져나오는 길 = 손 Send 가 손님을 같이 보냄 · 3-3 cron kinds [cost_day, customer] · 인보이스가 먼저 나가면 ② 가 푼다) ④ rebuild: 행을 계정 짝으로 모아 「IMS cost rebuild」 두 줄씩 · 차대 다르면 예외';

-- ═══════════════ ③ 사람 창구 — 일감 세우기(날짜 순 · 자동 0 · ⬜7) ═══════════════
create function public.qbo_cost_sheet_queue_one(p_sheet_id uuid, p_by uuid) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_s public.qbo_cost_sheet%rowtype; v_prev public.qbo_cost_sheet%rowtype; v_job uuid;
begin
  select * into v_s from public.qbo_cost_sheet s where s.id = p_sheet_id for update;
  if v_s.id is null then raise exception 'Cost day sheet % not found — nothing was saved', p_sheet_id; end if;
  if v_s.job_id is not null then return jsonb_build_object('sheet_id', v_s.id, 'doc_number', v_s.doc_number, 'job_id', v_s.job_id, 'existing', true, 'state', v_s.state); end if;
  if v_s.state <> 'pending' then raise exception 'Cost day % is % — only a pending sheet can be queued — nothing was saved', v_s.doc_number, v_s.state; end if;
  if v_s.kind = 'day' then
    select * into v_prev from public.qbo_cost_sheet s where s.realm_id = v_s.realm_id and s.wh = v_s.wh and s.kind = 'day' and s.sheet_date < v_s.sheet_date and s.state not in ('empty', 'void') and s.job_id is null order by s.sheet_date limit 1;
    if v_prev.id is not null then raise exception 'Earlier cost day % (%) is not queued yet — cost days go to QuickBooks in date order · queue the earlier sheet first — nothing was saved', v_prev.doc_number, v_prev.state; end if;
  end if;
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff)
  values (v_s.realm_id, 'cost_day', 'cost_sheet', public.qbo_cost_sheet_ims_id(v_s.sheet_date, v_s.wh, v_s.kind), 'queued', p_by) returning id into v_job;
  update public.qbo_cost_sheet s set job_id = v_job, updated_by = p_by where s.id = v_s.id;
  return jsonb_build_object('sheet_id', v_s.id, 'doc_number', v_s.doc_number, 'job_id', v_job, 'existing', false, 'state', 'pending');
end;
$$;
comment on function public.qbo_cost_sheet_queue_one(uuid, uuid) is '[qbo-sync-3-2b · ⬜3 · ⬜7] 장 하나에 cost_day 일감을 세운다(속 · grant 0) — pending 장만 · 이미 있으면 그대로(existing) · day 장은 같은 창고 앞 장(empty · void 아님)에 일감이 없으면 거부(날짜 순) · ims_id = qbo_cost_sheet_ims_id · 장.job_id 에 잇는다';

create function public.qbo_cost_sheet_queue(p_date date, p_wh text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_realm text := public.qbo_realm_of(); v_id uuid;
begin
  if p_date is null or p_wh is null or p_wh not in ('TOR', 'EDM') then raise exception 'date and warehouse (TOR | EDM) are required — nothing was saved'; end if;
  select s.id into v_id from public.qbo_cost_sheet s where s.realm_id = v_realm and s.sheet_date = p_date and s.wh = p_wh and s.kind = 'day';
  if v_id is null then raise exception 'There is no cost day sheet for % % — build it first (Build sheets) — nothing was saved', p_date, p_wh; end if;
  return public.qbo_cost_sheet_queue_one(v_id, v_staff) || jsonb_build_object('by_staff', v_staff);
end;
$$;
comment on function public.qbo_cost_sheet_queue(date, text) is '[qbo-sync-3-2b · ⬜7] 사람이 날 · 창고의 장에 보내기 일감을 세운다(열쇠 qbo 쓰기) — 자동으로 세우는 곳은 없다(cron · build 에 잇는 것은 3-3) · 날짜 순만 · 화면(3-4) 「Queue」';

create function public.qbo_cost_queue_due() returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_realm text := public.qbo_realm_of(); r record; v_out jsonb := '[]'::jsonb; v_err jsonb := '[]'::jsonb;
begin
  for r in select s.id, s.doc_number from public.qbo_cost_sheet s where s.realm_id = v_realm and s.kind = 'day' and s.state = 'pending' and s.job_id is null order by s.wh, s.sheet_date loop
    begin
      v_out := v_out || public.qbo_cost_sheet_queue_one(r.id, v_staff);
    exception when others then
      v_err := v_err || jsonb_build_object('doc_number', r.doc_number, 'error', left(sqlerrm, 1000));
    end;
  end loop;
  return jsonb_build_object('queued', v_out, 'count', jsonb_array_length(v_out), 'errors', v_err, 'by_staff', v_staff);
end;
$$;
comment on function public.qbo_cost_queue_due() is '[qbo-sync-3-2b · ⬜7] 일감 없는 pending day 장 전부에 일감을 세운다(열쇠 qbo 쓰기 · 창고 · 날짜 순 · 하나가 거부돼도 다음으로) — 3-3 이 만들기 cron(ims-qbo-cost-build) 뒤에 잇는다 · 지금은 사람만';

-- ═══════════════ ④ 장 state 트리거 — 일감 state 를 따라간다(이견 2 · ⬜1) · 행 불변식 ═══════════════
create function public.qbo_job_cost_sheet_sync() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_s public.qbo_cost_sheet%rowtype;
begin
  select * into v_s from public.qbo_cost_sheet s where s.job_id = new.id for update;
  if v_s.id is null then return null; end if;
  if new.state in ('queued', 'blocked') then
    if v_s.state <> 'hold' then
      update public.qbo_cost_sheet s set state = 'pending', sent_at = null, qbo_id = null where s.id = v_s.id;
      if v_s.kind = 'day' then delete from public.qbo_cost_sent t where t.sheet_id = v_s.id; end if;
    end if;
  elsif new.state = 'sending' then
    update public.qbo_cost_sheet s set state = 'sending' where s.id = v_s.id;
  elsif new.state = 'sent' then
    update public.qbo_cost_sheet s set state = 'sent', qbo_id = new.qbo_id, sent_at = coalesce(new.sent_at, now()), resolved_at = null where s.id = v_s.id;
  elsif new.state = 'failed' then
    if v_s.state = 'hold' then
      null;
    elsif old.state = 'sent' then
      update public.qbo_cost_sheet s set state = 'unknown', sent_at = null, qbo_id = null where s.id = v_s.id;
    else
      update public.qbo_cost_sheet s set state = 'failed', sent_at = null, qbo_id = null where s.id = v_s.id;
      if v_s.kind = 'day' then delete from public.qbo_cost_sent t where t.sheet_id = v_s.id; end if;
    end if;
  elsif new.state = 'unknown' then
    update public.qbo_cost_sheet s set state = 'unknown', sent_at = null, qbo_id = null where s.id = v_s.id;
  elsif new.state = 'skipped' then
    if v_s.state <> 'empty' then
      update public.qbo_cost_sheet s set state = 'void', hold_reason = null, sent_at = null, qbo_id = null, resolved_at = now(), resolved_by = new.updated_by, note = left(concat_ws(' · ', s.note, 'skipped: ' || coalesce(new.note, '')), 2000) where s.id = v_s.id;
      delete from public.qbo_cost_sent t where t.sheet_id = v_s.id;
    end if;
  end if;
  return null;
end;
$$;
comment on function public.qbo_job_cost_sheet_sync() is '[qbo-sync-3-2b · 이견 2 · ⬜1] qbo_job(kind cost_day) state 가 바뀌면 그 장(qbo_cost_sheet.job_id)이 따라간다 — queued · blocked → pending(hold 면 유지 · day 행 삭제) · sending → sending · sent → sent(qbo_id · sent_at) · failed → failed(hold 면 유지 · sent 에서 떨어지면 unknown = QBO 에 있을 수 있다 · day 행 삭제) · unknown → unknown(행 유지) · skipped → void(empty 면 유지 · 행 삭제 · 뒤 장 차액이 담는다) · 행 불변식: day 장의 행은 sending · unknown · sent 에만 · rebuild 장의 행은 void 에서만 지운다';

-- ═══════════════ ⑤ 재생성 hold · 미리 보기 · release (판정 1093 · ⬜4) ═══════════════
create function public.qbo_cost_hold_all(p_realm text, p_reason text) returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_n int;
begin
  update public.qbo_cost_sheet s set state = 'hold', hold_reason = left(p_reason, 2000) where s.realm_id = p_realm and s.state in ('pending', 'failed', 'sending');
  get diagnostics v_n = row_count;
  delete from public.qbo_cost_sent t using public.qbo_cost_sheet s where s.id = t.sheet_id and s.realm_id = p_realm and s.state = 'hold' and s.kind = 'day';
  update public.qbo_job j set state = 'failed', claimed_at = null, last_error = left(p_reason, 2000) from public.qbo_cost_sheet s where s.job_id = j.id and s.realm_id = p_realm and s.state = 'hold' and j.state in ('queued', 'blocked', 'sending');
  return v_n;
end;
$$;
comment on function public.qbo_cost_hold_all(text, text) is '[qbo-sync-3-2b · 판정 1093 · ⬜4] 재생성이 보이면 realm 의 미보낸 장(pending · failed · sending · 두 창고 · day · rebuild) 전부 hold(hold_reason = 글) · day 행 삭제 · 그 일감은 failed(last_error = 글 · 트리거는 hold 장을 그대로 둔다) · grant 0(claim 이 부른다) · 돌려주는 것 = hold 로 바뀐 장 수';

create function public.qbo_cost_rebuild_calc(p_realm text, p_wh text default null)
  returns table (wh text, as_of date, key_kind text, doc_key text, acct_a text, acct_b text, cents bigint, expected_cents bigint, sent_cents bigint, first_sent_on date)
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_wh text; v_p date;
begin
  foreach v_wh in array array['TOR', 'EDM'] loop
    if p_wh is not null and v_wh <> p_wh then continue; end if;
    select max(s.sheet_date) into v_p from public.qbo_cost_sheet s where s.realm_id = p_realm and s.wh = v_wh and s.kind = 'day' and s.state in ('sent', 'sending', 'unknown');
    if v_p is null then continue; end if;
    return query
      select v_wh, v_p, c.key_kind, c.doc_key, c.acct_a, c.acct_b, c.diff_cents, c.expected_cents, c.sent_cents, c.first_sent_on
      from public.qbo_cost_sheet_calc(v_p, v_wh, p_realm) c
      where c.status = 'send' and c.diff_cents <> 0 and c.sent_cents <> 0;
  end loop;
end;
$$;
comment on function public.qbo_cost_rebuild_calc(text, text) is '[qbo-sync-3-2b · 판정 1093 · ⬜4] 재생성 차액 — 창고마다 마지막으로 보낸 날 P(sent · sending · unknown day 장) 까지의 「기대_new(≤ P) − Σ보낸」 을 **이미 보낸 열쇠**(sent_cents ≠ 0)에 한해 열쇠 · 짝 · 센트로 돌려준다 · 보낸 적 없는 새 열쇠는 뒤 day 장이 보통 줄로 담는다 · 보낸 장이 없는 창고는 비움 · p_wh 로 한 창고만(calc 한 번) · grant 0(preview · release 가 부른다)';

create function public.qbo_cost_rebuild_preview() returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_wh jsonb;
begin
  with x as (select * from public.qbo_cost_rebuild_calc(v_realm)),
  p as (select x.wh, x.acct_a, x.acct_b, sum(x.cents)::bigint as c from x group by x.wh, x.acct_a, x.acct_b having sum(x.cents) <> 0),
  w as (select x.wh, min(x.as_of) as as_of,
               jsonb_agg(jsonb_build_object('key_kind', x.key_kind, 'doc_key', x.doc_key, 'acct_a', x.acct_a, 'acct_b', x.acct_b, 'cents', x.cents, 'expected_cents', x.expected_cents, 'sent_cents', x.sent_cents, 'first_sent_on', x.first_sent_on) order by x.key_kind, x.doc_key, x.acct_a) as keys
        from x group by x.wh)
  select coalesce(jsonb_agg(jsonb_build_object('wh', w.wh, 'as_of', w.as_of, 'doc_number', 'COGS-' || to_char(public.ims_today(), 'YYYYMMDD') || '-' || w.wh || '-R', 'txn_date', public.ims_today(), 'keys', w.keys,
                                               'pairs', (select coalesce(jsonb_agg(jsonb_build_object('acct_a', p.acct_a, 'acct_b', p.acct_b, 'cents', p.c) order by p.acct_a, p.acct_b), '[]'::jsonb) from p where p.wh = w.wh),
                                               'debit_cents', (select coalesce(sum(abs(p.c)), 0) from p where p.wh = w.wh),
                                               'line_count', (select count(*) * 2 from p where p.wh = w.wh)) order by w.wh), '[]'::jsonb)
    into v_wh from w;
  return jsonb_build_object(
    'epoch_now', (select min(c.id) from public.inv_layer_consume c),
    'held', coalesce((select jsonb_agg(jsonb_build_object('sheet_id', s.id, 'doc_number', s.doc_number, 'kind', s.kind, 'wh', s.wh, 'sheet_date', s.sheet_date, 'epoch', s.epoch, 'hold_reason', s.hold_reason, 'job_id', s.job_id) order by s.wh, s.sheet_date) from public.qbo_cost_sheet s where s.realm_id = v_realm and s.state = 'hold'), '[]'::jsonb),
    'warehouses', v_wh,
    'note', 'release (qbo_cost_rebuild_release) posts one rebuild sheet per warehouse with the pairs above as lines "IMS cost rebuild" dated today, then re-queues the held cost days · a warehouse with no pairs gets no sheet · keys never sent before stay in the next cost day as normal lines',
    'preview_only', true);
end;
$$;
comment on function public.qbo_cost_rebuild_preview() is '[qbo-sync-3-2b · 판정 1093 · ⬜4] 재생성 뒤 풀기 전 미리 보기(열쇠 qbo · qbo:read) — epoch_now · hold 장 목록 · 창고마다 as_of(마지막 보낸 날) · 열쇠별 차액 · 계정 짝별 합(= rebuild 장 줄) · 차변 센트 · DocNumber COGS-<오늘>-<창고>-R · QBO 호출 0 · 아무것도 쓰지 않는다';

create function public.qbo_cost_rebuild_release(p_note text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_realm text := public.qbo_realm_of(); v_epoch bigint; v_today date := public.ims_today(); v_wh text; v_id uuid; v_doc text; v_keys int; v_debit bigint; v_pairs int;
        v_sheets jsonb := '[]'::jsonb; v_void jsonb := '[]'::jsonb; r record; v_held int; v_q jsonb;
begin
  if nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say what you checked (a note is required to release a cost rebuild) — nothing was saved'; end if;
  if not exists (select 1 from public.qbo_cost_sheet s where s.realm_id = v_realm and s.state = 'hold') then raise exception 'Nothing is on hold — no cost rebuild to release — nothing was saved'; end if;
  select coalesce(min(c.id), 0) into v_epoch from public.inv_layer_consume c;
  -- 멈춘 rebuild 장(옛 세대의 행)은 void — 새 rebuild 장이 다시 센다
  for r in select s.id, s.doc_number, s.job_id from public.qbo_cost_sheet s where s.realm_id = v_realm and s.state = 'hold' and s.kind = 'rebuild' loop
    update public.qbo_job j set state = 'skipped', claimed_at = null, note = left('voided by a later cost rebuild release: ' || btrim(p_note), 2000), updated_by = v_staff where j.id = r.job_id and j.state <> 'sent';
    update public.qbo_cost_sheet s set state = 'void', hold_reason = null, resolved_at = now(), resolved_by = v_staff, note = left(concat_ws(' · ', s.note, 'voided by a later rebuild release'), 2000) where s.id = r.id and s.state = 'hold';
    delete from public.qbo_cost_sent t where t.sheet_id = r.id;
    v_void := v_void || to_jsonb(r.doc_number);
  end loop;
  -- 창고마다 rebuild 장 하나 — 장을 먼저 세우고 행(이미 보낸 열쇠의 차액 · calc 한 번)을 넣은 뒤 행으로 짝 · 차변을 센다 · 짝이 0 이면 장을 거둔다 · JE 줄은 몸이 짝으로 모은다
  foreach v_wh in array array['TOR', 'EDM'] loop
    v_doc := 'COGS-' || to_char(v_today, 'YYYYMMDD') || '-' || v_wh || '-R';
    if exists (select 1 from public.qbo_cost_sheet s where s.realm_id = v_realm and s.doc_number = v_doc) then raise exception 'A rebuild sheet % was already released today — send or skip it first — nothing was saved', v_doc; end if;
    insert into public.qbo_cost_sheet (realm_id, sheet_date, wh, kind, doc_number, state, epoch, built_keys, built_lines, built_hold_keys, built_debit_cents, note, updated_by)
    values (v_realm, v_today, v_wh, 'rebuild', v_doc, 'pending', v_epoch, 0, 0, 0, 0, left('rebuild release: ' || btrim(p_note), 2000), v_staff) returning id into v_id;
    insert into public.qbo_cost_sent (sheet_id, realm_id, wh, key_kind, doc_key, acct_a, acct_b, cents)
    select v_id, v_realm, v_wh, x.key_kind, x.doc_key, x.acct_a, x.acct_b, x.cents from public.qbo_cost_rebuild_calc(v_realm, v_wh) x;
    select count(*), coalesce(sum(abs(p.c)), 0) into v_pairs, v_debit from (select sum(t.cents) as c from public.qbo_cost_sent t where t.sheet_id = v_id group by t.acct_a, t.acct_b having sum(t.cents) <> 0) p;
    select count(distinct t.doc_key) into v_keys from public.qbo_cost_sent t where t.sheet_id = v_id;
    if v_pairs = 0 then
      delete from public.qbo_cost_sent t where t.sheet_id = v_id;
      delete from public.qbo_cost_sheet s where s.id = v_id;
      continue;
    end if;
    update public.qbo_cost_sheet s set built_keys = v_keys, built_lines = v_pairs * 2, built_debit_cents = v_debit where s.id = v_id;
    v_q := public.qbo_cost_sheet_queue_one(v_id, v_staff);
    v_sheets := v_sheets || jsonb_build_object('sheet_id', v_id, 'doc_number', v_doc, 'wh', v_wh, 'keys', v_keys, 'pairs', v_pairs, 'debit_cents', v_debit, 'job_id', v_q->>'job_id');
  end loop;
  -- 멈춘 day 장: pending · epoch 갱신 · 일감 queued(request_id 새로) — 트리거가 장을 pending 으로 본다(이미 pending)
  update public.qbo_cost_sheet s set state = 'pending', hold_reason = null, epoch = v_epoch, note = left(concat_ws(' · ', s.note, 'released after cost rebuild: ' || btrim(p_note)), 2000), updated_by = v_staff where s.realm_id = v_realm and s.state = 'hold' and s.kind = 'day';
  get diagnostics v_held = row_count;
  update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, blocked_by = null, request_id = gen_random_uuid(), last_error = null, note = left(concat_ws(' · ', j.note, 'released after cost rebuild'), 2000), updated_by = v_staff
    from public.qbo_cost_sheet s where s.job_id = j.id and s.realm_id = v_realm and s.kind = 'day' and s.state = 'pending' and j.state = 'failed' and j.kind = 'cost_day';
  return jsonb_build_object('released_days', v_held, 'epoch', v_epoch, 'rebuild_sheets', v_sheets, 'voided_rebuilds', v_void, 'by_staff', v_staff);
end;
$$;
comment on function public.qbo_cost_rebuild_release(text) is '[qbo-sync-3-2b · 판정 1093 · ⬜4] 재생성 hold 를 푼다(열쇠 qbo 쓰기 · note 필수) — ① 멈춘 옛 rebuild 장은 void ② 창고마다 짝이 있으면 rebuild 장(kind rebuild · COGS-<오늘>-<창고>-R · TxnDate 오늘 · 행 = 이미 보낸 열쇠의 차액 · 줄 = 계정 짝당 「IMS cost rebuild」) + 일감 ③ 멈춘 day 장 pending · epoch 갱신 · 일감 queued(request_id 새로) — day 장은 몸의 차례 규칙으로 rebuild 장 뒤에 선다 · 같은 날 두 번째 release 는 거부(먼저 보내거나 skip)';

-- ═══════════════ ⑥ resolve — unknown 장을 사람이 푼다 (판정 1101 · 이견 3 · ⬜5) ═══════════════
create function public.qbo_cost_sheet_resolve(p_sheet uuid, p_outcome text, p_note text, p_qbo_id text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_realm text := public.qbo_realm_of(); v_s public.qbo_cost_sheet%rowtype; v_j public.qbo_job%rowtype; v_total numeric;
begin
  if nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say what you checked in QuickBooks (a note is required) — nothing was saved'; end if;
  if p_outcome is null or p_outcome not in ('in_qbo', 'not_in_qbo') then raise exception 'outcome must be in_qbo or not_in_qbo (got %) — nothing was saved', p_outcome; end if;
  select * into v_s from public.qbo_cost_sheet s where s.id = p_sheet and s.realm_id = v_realm for update;
  if v_s.id is null then raise exception 'Cost day sheet % not found — nothing was saved', p_sheet; end if;
  if v_s.state <> 'unknown' then raise exception 'Only a cost day whose result is unknown can be resolved (% is %) — nothing was saved', v_s.doc_number, v_s.state; end if;
  select * into v_j from public.qbo_job j where j.id = v_s.job_id for update;
  if v_j.id is null or v_j.state <> 'unknown' then raise exception 'The job of % is % — only an unknown job can be resolved — nothing was saved', v_s.doc_number, coalesce(v_j.state, 'missing'); end if;
  if p_outcome = 'in_qbo' then
    if nullif(btrim(coalesce(p_qbo_id, '')), '') is null then raise exception 'The QuickBooks journal entry Id is required for in_qbo — nothing was saved'; end if;
    v_total := round(coalesce(nullif(split_part(coalesce(v_j.fingerprint, ''), '|', 1), '')::bigint, 0) / 100.0, 2);
    update public.qbo_job j set state = 'sent', sent_at = now(), claimed_at = null, qbo_id = btrim(p_qbo_id), qbo_name = v_s.doc_number, note = left(concat_ws(' · ', j.note, 'resolved in_qbo: ' || btrim(p_note)), 2000), updated_by = v_staff where j.id = v_j.id;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_realm, 'cost_sheet', v_j.ims_id, 'JournalEntry', btrim(p_qbo_id), v_s.doc_number, null, v_total, null, null, v_j.id, now(), null, v_j.fingerprint, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, total_amt = excluded.total_amt, mismatch = null, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = excluded.fingerprint, source = 'sent', updated_at = now();
    exception when unique_violation then
      raise exception 'QuickBooks JournalEntry #% is already recorded for another IMS record — check both in QuickBooks — nothing was saved', btrim(p_qbo_id);
    end;
    update public.qbo_cost_sheet s set resolved_at = now(), resolved_by = v_staff, note = left(concat_ws(' · ', s.note, 'resolved in_qbo: ' || btrim(p_note)), 2000) where s.id = v_s.id;
    return jsonb_build_object('sheet_id', v_s.id, 'doc_number', v_s.doc_number, 'outcome', 'in_qbo', 'state', 'sent', 'qbo_id', btrim(p_qbo_id), 'total_amt', v_total, 'by_staff', v_staff);
  end if;
  update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, blocked_by = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'resolved not_in_qbo: ' || btrim(p_note)), 2000), updated_by = v_staff where j.id = v_j.id;
  update public.qbo_cost_sheet s set resolved_at = now(), resolved_by = v_staff, note = left(concat_ws(' · ', s.note, 'resolved not_in_qbo: ' || btrim(p_note)), 2000) where s.id = v_s.id;
  return jsonb_build_object('sheet_id', v_s.id, 'doc_number', v_s.doc_number, 'outcome', 'not_in_qbo', 'state', 'pending', 'job_state', 'queued', 'by_staff', v_staff);
end;
$$;
comment on function public.qbo_cost_sheet_resolve(uuid, text, text, text) is '[qbo-sync-3-2b · 판정 1101 · 이견 3 · ⬜5] unknown 장을 사람이 푼다(열쇠 qbo 쓰기 · note 필수) — in_qbo(QBO JournalEntry Id 필수) = 일감 sent(트리거로 장 sent) + qbo_txn JournalEntry(total = 지문의 차변) / not_in_qbo = 일감 queued(request_id 새로 · 트리거로 장 pending · day 행 삭제 → 다음 claim 이 다시 셈) · QBO 에 같은 장이 둘이면 하나 지우고 남은 Id 로 in_qbo · 하나도 안 남기면 Skip(void) · EF 의 DocNumber 조회로 먼저 푸는 길은 3-3';

-- ═══════════════ ⑦ 재발행 여섯 — 원본 DB prosrc md5(⓪ 가드) · 더한 줄만(3-2b 표시) · 시그니처 무변 ═══════════════
-- qbo_job_claim de6a6fec2c7925ca9be82b1db6e612c3 → kinds 19 · ② cost_day 부모 skipped 풀기 · 몸 switch cost_day(④ · ⑤) · hold · empty 가지 · 보낸 몫 행 insert · held · emptied
create or replace function public.qbo_job_claim (p_limit int default 15, p_kinds text[] default array['customer', 'item'], p_job_ids uuid[] default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_stale int; v_unblocked int; v_ids uuid[]; v_j public.qbo_job%rowtype; v_open public.qbo_job%rowtype; v_b jsonb; v_rows jsonb := '[]'::jsonb; v_failed int := 0; v_blocked int := 0; v_waiting int := 0; v_last uuid; v_cust uuid; v_nj jsonb; e jsonb;
  v_kinds text[] := coalesce(p_kinds, array['customer', 'item']);
  v_pick uuid[] := (select array_agg(distinct x) from unnest(p_job_ids) x where x is not null);                                       -- 2d1: 고른 id(중복 · null 제거) · null 이면 옛 길(가장 오래된 것부터 p_limit)
  v_needs jsonb := '[]'::jsonb; v_req jsonb := '[]'::jsonb; v_r record;
  v_held int := 0; v_emptied int := 0;   -- 3-2b: 재생성 hold · 줄 0 empty 수
begin
  if not public.doc_is_service() then raise exception 'qbo_job_claim is for the send worker only — nothing was read'; end if;
  if not (v_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day']) or coalesce(array_length(v_kinds, 1), 0) = 0 then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void, refund, refund_void, refund_apply, refund_apply_void, cost_day (got %)', v_kinds; end if;   -- 2e-3-2-1 kinds 18 · 3-2b cost_day 19
  if p_job_ids is not null and coalesce(array_length(v_pick, 1), 0) = 0 then raise exception 'job_ids must name at least one job — nothing was read'; end if;
  if coalesce(array_length(v_pick, 1), 0) > 200 then raise exception 'job_ids may name at most 200 jobs in one call (got %) — nothing was read', array_length(v_pick, 1); end if;
  -- ① 멈춘 sending(EF 가 도중에 죽었다 · QBO 에 닿았는지 모른다) → unknown(mail_claim 꼴 · 자동 재전송 금지 · 다음 send 가 이름 · DocNumber 로 조회해 푼다)
  update public.qbo_job j set state = 'unknown', claimed_at = null,
         last_error = left(coalesce(j.last_error || ' · ', '') || format('stale: still sending %s after claim (attempt %s) — QuickBooks may or may not have it', date_trunc('second', now() - j.claimed_at), j.attempts), 2000)
   where j.realm_id = v_realm and j.state = 'sending' and j.claimed_at < now() - interval '10 minutes';
  get diagnostics v_stale = row_count;
  -- ② 부모가 보내졌으면 자식을 연다(손님 → 자식 손님 · need → 인보이스 · 인보이스 → void · 인보이스 → 크레딧)
  update public.qbo_job j set state = 'queued', next_at = now() from public.qbo_job p where j.realm_id = v_realm and j.state = 'blocked' and p.id = j.blocked_by and (p.state = 'sent' or (j.kind = 'cost_day' and p.state = 'skipped'));   -- 3-2b ⬜3: 하루 원가 장은 앞 장 skip(void)도 푼다 — 보낸 몫 0 이라 뒤 장 차액이 그 몫을 담는다(1092)
  get diagnostics v_unblocked = row_count;
  -- ③ 잡기 — queued → sending(for update skip locked · 10 분 임대) · EF 가 아는 kind 만 · [2d1] p_job_ids 가 있으면 그 id 만(한도는 id 수)
  with pick as (
    select j.id from public.qbo_job j where j.realm_id = v_realm and j.state = 'queued' and j.next_at <= now() and j.kind = any (v_kinds) and (v_pick is null or j.id = any (v_pick))
     order by j.created_at, j.id limit case when v_pick is null then greatest(1, least(coalesce(p_limit, 15), 50)) else array_length(v_pick, 1) end for update skip locked),
  upd as (update public.qbo_job j set state = 'sending', claimed_at = now(), attempts = j.attempts + 1 from pick where j.id = pick.id returning j.id)
  select coalesce(array_agg(u.id), '{}') into v_ids from upd u;
  -- ④ 몸은 다음 문장에서 일감마다(같은 문장 안의 읽기는 update 전 행을 본다) · 몸이 안 만들어지면 그 일감만 failed · needs 가 있으면 need 일감을 쌓고 이 일감은 blocked(이견 11) · [2d1] need 일감을 need_jobs 로 돌려준다 · blocked_by 는 손님 need 우선
  for v_j in select * from public.qbo_job j where j.id = any (v_ids) order by j.created_at, j.id loop
    begin
      v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                           when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                           when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid)
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid)
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'refund' then public.qbo_refund_body(v_j.ims_id::uuid) when 'refund_void' then public.qbo_refund_void_body(v_j.ims_id::uuid) when 'refund_apply' then public.qbo_refund_apply_body(v_j.ims_id::uuid) when 'refund_apply_void' then public.qbo_refund_apply_void_body(v_j.ims_id::uuid)   -- 2e-3-2-1 refund · refund_void · refund_apply · refund_apply_void
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid)
                           when 'cost_day' then public.qbo_cost_day_body(public.qbo_cost_sheet_id_for_job(v_j.id)) end;   -- 3-2b cost_day(하루 원가 장 · 몸은 장 id 로)   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void   -- 2c1 credit · credit_void
      if v_b is null then raise exception 'kind % has no body', v_j.kind; end if;
      if v_b->>'parent_customer_id' is not null then raise exception 'parent customer is not in QuickBooks yet — send the parent first (job was not blocked: parent link removed?)'; end if;
      if v_b->>'hold' is not null then                                                                                                 -- 3-2b ⬜4 · 판정 1093: 재생성 세대가 바뀌었다 → realm 의 미보낸 장 전부 hold · 일감 failed(풀어 주는 길은 last_error 에 · retry 는 거부 · release 가 연다)
        perform public.qbo_cost_hold_all(v_realm, v_b->>'hold');
        update public.qbo_job j set state = 'failed', claimed_at = null, last_error = left(v_b->>'hold', 2000) where j.id = v_j.id;
        v_held := v_held + 1;
        continue;
      end if;
      if coalesce((v_b->>'empty')::boolean, false) then                                                                                 -- 3-2b 이견 4: claim 때 보낼 줄 0 → 장 empty · 일감 skipped(note 자동 · skipped_ck) — 트리거는 empty 장을 void 로 바꾸지 않는다
        update public.qbo_cost_sheet s set state = 'empty', note = left(concat_ws(' · ', s.note, 'nothing to send at claim time'), 2000) where s.id = (v_b->>'sheet_id')::uuid;
        update public.qbo_job j set state = 'skipped', claimed_at = null, note = 'nothing to send at claim time — the cost day has no lines left (sheet marked empty)' where j.id = v_j.id;
        v_emptied := v_emptied + 1;
        continue;
      end if;
      if jsonb_array_length(coalesce(v_b->'needs', '[]'::jsonb)) > 0 then
        v_last := null; v_cust := null;
        for e in select x from jsonb_array_elements(v_b->'needs') x loop
          v_nj := public.qbo_job_open_or_add(e->>'kind', e->>'ims_id', v_j.by_staff);                                                 -- 몸이 거부하면(941 · 활성 Sku 사람 짝 …) 예외 → 이 일감 failed + 그 까닭
          v_last := (v_nj->>'id')::uuid;
          if e->>'kind' = 'customer' then v_cust := v_last; end if;
          v_needs := v_needs || jsonb_build_object('job_id', v_nj->>'id', 'kind', v_nj->>'kind', 'ims_kind', v_nj->>'ims_kind', 'ims_id', v_nj->>'ims_id', 'state', v_nj->>'state', 'name', e->>'name', 'existing', coalesce((v_nj->>'existing')::boolean, false), 'for_job', v_j.id, 'parent_job', v_nj->'parent_job'->>'id');
          if v_nj->'parent_job'->>'id' is not null then
            v_needs := v_needs || jsonb_build_object('job_id', v_nj->'parent_job'->>'id', 'kind', 'customer', 'ims_kind', 'customer', 'ims_id', v_nj->'parent_job'->>'ims_id', 'state', v_nj->'parent_job'->>'state', 'name', null, 'existing', coalesce((v_nj->'parent_job'->>'existing')::boolean, false), 'for_job', v_nj->>'id', 'parent_job', null);
          end if;
        end loop;
        update public.qbo_job j set state = 'blocked', blocked_by = coalesce(v_cust, v_last), claimed_at = null,
               warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')) || array[format('waiting for %s QuickBooks record(s) to be created first', jsonb_array_length(v_b->'needs'))], ' · '), '')
         where j.id = v_j.id;
        v_blocked := v_blocked + 1;
        continue;
      end if;
      if nullif(v_b->>'wait_job', '') is not null then                                                                                 -- 2c1 판정 960: 크레딧은 자기 IMS 인보이스가 QBO 에 들어간 뒤 — 그 인보이스 일감 뒤에 선다(② 가 sent 때 푼다)
        update public.qbo_job j set state = 'blocked', blocked_by = (v_b->>'wait_job')::uuid, claimed_at = null,
               warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')) || array[coalesce(v_b->>'wait_reason', format('waiting for invoice %s to reach QuickBooks first', coalesce(v_b->>'wait_invoice', '?')))], ' · '), '')
         where j.id = v_j.id;
        v_waiting := v_waiting + 1;
        continue;
      end if;
      update public.qbo_job j set warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')), ' · '), ''), fingerprint = v_b->>'fingerprint' where j.id = v_j.id;   -- 2e-1b: 보낼 때의 IMS 상태(지문)를 일감에 · done 이 qbo_txn 으로 옮긴다
      if v_j.kind = 'cost_day' and v_b->>'sheet_kind' = 'day' then                                                                       -- 3-2b ⬜2 · 이견 9: 줄은 claim 때 굳는다 — 보낸 몫 행을 지금 넣는다(장은 트리거로 이미 sending · calc 는 이 순간부터 이 장을 보낸 몫으로 센다 · done 은 다시 셈하지 않는다 · rebuild 장의 행은 release 때 굳었다)
        insert into public.qbo_cost_sent (sheet_id, realm_id, wh, key_kind, doc_key, acct_a, acct_b, cents)
        select (v_b->>'sheet_id')::uuid, v_realm, v_b->>'wh', x.key_kind, x.doc_key, x.acct_a, x.acct_b, x.cents
          from jsonb_to_recordset(v_b->'lines') as x(key_kind text, doc_key text, acct_a text, acct_b text, cents bigint);
      end if;
      v_rows := v_rows || jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'ims_kind', v_j.ims_kind, 'ims_id', v_j.ims_id, 'attempt', v_j.attempts, 'request_id', v_j.request_id,
                                             'name', coalesce(v_b->>'display_name', v_b->>'name'), 'name_alt', v_b->>'name_alt', 'sku', v_b->>'sku', 'doc_number', v_b->>'doc_number', 'qbo_id', v_b->>'qbo_id',
                                             'body', v_b->'body', 'warnings', v_b->'warnings', 'totals', v_b->'totals',
                                             'fingerprint', v_b->>'fingerprint', 'check_lines', v_b->'check_lines', 'lookup', v_b->'lookup');   -- 2e-1b: 결제 = (가) Balance 가드 줄 · unknown 열쇠
    exception when others then
      update public.qbo_job j set state = 'failed', claimed_at = null, last_error = left(sqlerrm, 2000) where j.id = v_j.id;
      v_failed := v_failed + 1;
    end;
  end loop;
  -- ⑤ [2d1] 고른 id 마다 결과 — 잡힌 것은 ④ 뒤의 상태로(sending = claimed · blocked = 까닭 · failed = 글) · 못 잡은 것은 왜
  if v_pick is not null then
    for v_r in select x.id, j.state, j.kind, j.warning, j.last_error, j.next_at, j.realm_id from unnest(v_pick) x(id) left join public.qbo_job j on j.id = x.id loop
      if v_r.state = 'blocked' and v_r.realm_id = v_realm and not (v_r.id = any (v_ids)) then                                       -- 이미 blocked 인 일감을 다시 골랐다 → 기다리는 열린 일감(부모 blocked_by + 몸의 needs)을 need_jobs 로(EF 가 다음 바퀴에 같이 잡는다 · 거래 종류는 EF 가 안 잡는다 = 960)
        select * into v_j from public.qbo_job j where j.id = v_r.id;
        select * into v_open from public.qbo_job j where j.id = v_j.blocked_by and j.state not in ('sent', 'skipped');
        if v_open.id is not null then v_needs := v_needs || jsonb_build_object('job_id', v_open.id, 'kind', v_open.kind, 'ims_kind', v_open.ims_kind, 'ims_id', v_open.ims_id, 'state', v_open.state, 'name', null, 'existing', true, 'for_job', v_j.id, 'parent_job', null); end if;
        begin
          v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                               when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                               when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid)
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid)
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'refund' then public.qbo_refund_body(v_j.ims_id::uuid) when 'refund_void' then public.qbo_refund_void_body(v_j.ims_id::uuid) when 'refund_apply' then public.qbo_refund_apply_body(v_j.ims_id::uuid) when 'refund_apply_void' then public.qbo_refund_apply_void_body(v_j.ims_id::uuid)   -- 2e-3-2-1 refund · refund_void · refund_apply · refund_apply_void
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid)
                           when 'cost_day' then public.qbo_cost_day_body(public.qbo_cost_sheet_id_for_job(v_j.id)) end;   -- 3-2b cost_day(하루 원가 장 · 몸은 장 id 로)   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
          for e in select x from jsonb_array_elements(coalesce(v_b->'needs', '[]'::jsonb)) x
                   union all select jsonb_build_object('kind', 'customer', 'ims_id', v_b->>'parent_customer_id', 'name', null) where v_b->>'parent_customer_id' is not null loop
            select * into v_open from public.qbo_job j where j.realm_id = v_realm and j.kind = e->>'kind' and j.ims_id = e->>'ims_id' and j.state not in ('sent', 'skipped') and j.id is distinct from v_j.blocked_by order by j.created_at limit 1;
            if v_open.id is not null then v_needs := v_needs || jsonb_build_object('job_id', v_open.id, 'kind', v_open.kind, 'ims_kind', v_open.ims_kind, 'ims_id', v_open.ims_id, 'state', v_open.state, 'name', e->>'name', 'existing', true, 'for_job', v_j.id, 'parent_job', null); end if;
            v_open := null;
          end loop;
        exception when others then null;                                                                                           -- 몸이 거부해도 requested 의 까닭(warning)은 그대로 · needs 만 모른다
        end;
      end if;
      v_req := v_req || jsonb_build_object('job_id', v_r.id, 'kind', v_r.kind, 'state', v_r.state,
        'result', case when v_r.state is null or v_r.realm_id is distinct from v_realm then 'not_found'
                       when v_r.id = any (v_ids) then case v_r.state when 'sending' then 'claimed' when 'blocked' then 'blocked' when 'failed' then 'failed' else v_r.state end
                       when v_r.state <> 'queued' then 'not_queued'
                       when not (v_r.kind = any (v_kinds)) then 'wrong_kind'
                       when v_r.next_at > now() then 'not_due' else 'locked' end,
        'reason', case when v_r.state is null or v_r.realm_id is distinct from v_realm then 'no such job'
                       when v_r.id = any (v_ids) then case v_r.state when 'blocked' then v_r.warning when 'failed' then v_r.last_error end
                       when v_r.state <> 'queued' then format('the job is %s — not sent', v_r.state) || case v_r.state when 'blocked' then ' (' || coalesce(v_r.warning, 'waiting for another job') || ')' when 'failed' then ' — retry it first' when 'unknown' then ' — retry it with a note after checking QuickBooks' when 'skipped' then ' — retry it first' when 'sending' then ' (another send is working on it)' else '' end
                       when not (v_r.kind = any (v_kinds)) then format('kind %s is not sent by this worker', v_r.kind)
                       when v_r.next_at > now() then format('the job is scheduled for %s', v_r.next_at) else 'another send holds the job — try again in a moment' end);
    end loop;
  end if;
  return jsonb_build_object('realm_id', v_realm, 'kinds', to_jsonb(v_kinds), 'picked', case when v_pick is null then null else to_jsonb(v_pick) end, 'recovered_unknown', v_stale, 'unblocked', v_unblocked, 'claimed', coalesce(array_length(v_ids, 1), 0), 'body_failed', v_failed, 'blocked_for_needs', v_blocked, 'blocked_for_invoice', v_waiting, 'held', v_held, 'emptied', v_emptied,
                            'need_jobs', v_needs, 'requested', v_req, 'jobs', v_rows);
end;
$$;
-- qbo_job_preview 07c73ffda11366b176fabd6115280c8d → 몸 switch cost_day · hold · empty · sendable
create or replace function public.qbo_job_preview (p_job uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_j public.qbo_job%rowtype; v_b jsonb; v_err text; v_needs jsonb := '[]'::jsonb; e jsonb; v_open public.qbo_job%rowtype; v_wait public.qbo_job%rowtype; v_parent public.qbo_job%rowtype; v_blocked jsonb; v_wait_j jsonb;
begin
  select * into v_j from public.qbo_job j where j.id = p_job and j.realm_id = v_realm;
  if v_j.id is null then raise exception 'Job % not found — nothing to preview', p_job; end if;
  begin
    v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                         when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                         when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid)
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid)
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'refund' then public.qbo_refund_body(v_j.ims_id::uuid) when 'refund_void' then public.qbo_refund_void_body(v_j.ims_id::uuid) when 'refund_apply' then public.qbo_refund_apply_body(v_j.ims_id::uuid) when 'refund_apply_void' then public.qbo_refund_apply_void_body(v_j.ims_id::uuid)   -- 2e-3-2-1 refund · refund_void · refund_apply · refund_apply_void
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid)
                           when 'cost_day' then public.qbo_cost_day_body(public.qbo_cost_sheet_id_for_job(v_j.id)) end;   -- 3-2b cost_day(하루 원가 장 · 몸은 장 id 로)   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
    if v_b is null then raise exception 'kind % has no body', v_j.kind; end if;
  exception when others then
    v_err := left(sqlerrm, 2000); v_b := null;
  end;
  -- needs(손님 · Item 을 먼저 만들어야 한다) — 열린 일감이 있으면 그 id · state · 없으면 null(send 가 만든다) · 손님 몸의 부모(parent_customer_id)도 need 로
  if v_b is not null then
    for e in select x from jsonb_array_elements(coalesce(v_b->'needs', '[]'::jsonb)) x
             union all select jsonb_build_object('kind', 'customer', 'ims_id', v_b->>'parent_customer_id', 'name', (select c.name from public.customer c where c.id::text = v_b->>'parent_customer_id')) where v_b->>'parent_customer_id' is not null loop
      select * into v_open from public.qbo_job j where j.realm_id = v_realm and j.kind = e->>'kind' and j.ims_id = e->>'ims_id' and j.state not in ('sent', 'skipped') order by j.created_at limit 1;
      v_needs := v_needs || jsonb_build_object('kind', e->>'kind', 'ims_id', e->>'ims_id', 'name', e->>'name', 'job_id', v_open.id, 'job_state', v_open.state, 'job_error', v_open.last_error);
      v_open := null;
    end loop;
    if nullif(v_b->>'wait_job', '') is not null then
      select * into v_wait from public.qbo_job j where j.id = (v_b->>'wait_job')::uuid;
      v_wait_j := jsonb_build_object('job_id', v_wait.id, 'kind', v_wait.kind, 'state', v_wait.state, 'invoice', v_b->>'wait_invoice', 'reason', coalesce(v_b->>'wait_reason', format('waiting for invoice %s to reach QuickBooks first — send it too', coalesce(v_b->>'wait_invoice', '?'))));
    end if;
  end if;
  if v_j.blocked_by is not null then
    select * into v_parent from public.qbo_job j where j.id = v_j.blocked_by;
    v_blocked := jsonb_build_object('job_id', v_parent.id, 'kind', v_parent.kind, 'state', v_parent.state, 'doc', public.qbo_job_doc(v_parent.ims_kind, v_parent.ims_id), 'last_error', v_parent.last_error);
  end if;
  return jsonb_build_object(
    'job', jsonb_build_object('id', v_j.id, 'kind', v_j.kind, 'ims_kind', v_j.ims_kind, 'ims_id', v_j.ims_id, 'state', v_j.state, 'attempts', v_j.attempts, 'qbo_id', v_j.qbo_id, 'qbo_name', v_j.qbo_name, 'last_error', v_j.last_error, 'warning', v_j.warning, 'note', v_j.note, 'created_at', v_j.created_at, 'sent_at', v_j.sent_at, 'by_name', (select s.name from public.ims_staff s where s.id = v_j.by_staff)),
    'doc', public.qbo_job_doc(v_j.ims_kind, v_j.ims_id),
    'name', coalesce(v_b->>'display_name', v_b->>'name'), 'doc_number', v_b->>'doc_number', 'body', v_b->'body', 'totals', v_b->'totals', 'warnings', coalesce(v_b->'warnings', '[]'::jsonb), 'line_count', (v_b->>'line_count')::int,
    'needs', v_needs, 'wait', v_wait_j, 'blocked_by', v_blocked, 'error', v_err, 'check_lines', v_b->'check_lines', 'fingerprint', v_b->>'fingerprint',   -- 2e-1b
    'hold', v_b->>'hold', 'empty', coalesce((v_b->>'empty')::boolean, false),   -- 3-2b: 재생성 hold 글 · 줄 0
    'sendable', (v_err is null and jsonb_array_length(v_needs) = 0 and v_wait_j is null and v_j.state = 'queued' and v_b->>'hold' is null and not coalesce((v_b->>'empty')::boolean, false)),
    'preview_only', true);
end;
$$;
-- qbo_job_doc 4291e46d184438d3463e2ad99b7a679f → cost_sheet 가지
create or replace function public.qbo_job_doc (p_ims_kind text, p_ims_id text) returns jsonb
  language sql stable security definer set search_path = public, pg_temp
as $$
  select case p_ims_kind
    when 'invoice' then (select jsonb_build_object('doc_number', i.invoice_number, 'name', i.bill_to_name, 'customer_id', i.bill_to_customer_id, 'currency', i.currency_code, 'total', i.total, 'doc_date', i.issued_on, 'doc_status', i.status)
                           from public.so_invoice i where i.id::text = p_ims_id)
    when 'credit' then (select jsonb_build_object('doc_number', c.credit_number, 'name', (select cu.name from public.customer cu where cu.id = c.customer_id), 'customer_id', c.customer_id, 'currency', c.currency_code, 'total', c.total, 'doc_date', c.issued_on, 'doc_status', c.status)
                          from public.so_credit c where c.id::text = p_ims_id)
    when 'customer' then (select jsonb_build_object('doc_number', null, 'name', c.name, 'customer_id', c.id, 'currency', c.currency_code, 'total', null, 'doc_date', null, 'doc_status', case when c.is_active then 'active' else 'inactive' end)
                            from public.customer c where c.id::text = p_ims_id)
    when 'product' then (select jsonb_build_object('doc_number', p.sku, 'name', p.name, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', case when p.is_active then 'active' else 'inactive' end)
                           from public.product p where p.id::text = p_ims_id)
    when 'payment' then (select jsonb_build_object('doc_number', p.reference, 'name', (select cu.name from public.customer cu where cu.id = p.customer_id), 'customer_id', p.customer_id, 'currency', p.currency_code, 'total', p.amount, 'doc_date', p.paid_on, 'doc_status', p.status)
                           from public.so_payment p where p.id::text = p_ims_id)   -- 2e-1b: 결제 = reference · 청구처 · 통화 · 금액 · 받은 날 · active | voided
    when 'credit_alloc' then (select jsonb_build_object('doc_number', c.credit_number || ' → ' || coalesce(i.invoice_number, 'refund'), 'name', (select cu.name from public.customer cu where cu.id = public.so_invoice_store(i.id)), 'customer_id', public.so_invoice_store(i.id), 'currency', c.currency_code, 'total', a.amount, 'doc_date', (a.created_at at time zone 'America/Toronto')::date, 'doc_status', case when a.voided_at is null then 'active' else 'voided' end)
                                from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id left join public.so_invoice i on i.id = a.invoice_id where a.id::text = p_ims_id)   -- 2e-2-1: 크레딧 붙임 = 「CR → 인보이스」 · 매장(1014) · 통화 · 붙임 금액 · 붙인 날(토론토) · active | voided
    when 'opening_alloc' then (select jsonb_build_object('doc_number', public.qbo_opening_doc_number(a.id) || ' → ' || i.invoice_number, 'name', (select cu.name from public.customer cu where cu.id = p.customer_id), 'customer_id', p.customer_id, 'currency', p.currency_code, 'total', a.amount, 'doc_date', (a.created_at at time zone 'America/Toronto')::date, 'doc_status', case when a.voided_at is null then 'active' else 'voided' end)
                                 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id join public.so_invoice i on i.id = a.invoice_id where a.id::text = p_ims_id)   -- 2e-3-1: 이월 돈 붙임 = 「OC-<인보이스>-<n> → 인보이스」 · 돈의 주인(이견 4) · 통화 · 붙임 금액 · 붙인 날(토론토) · active | voided
    when 'refund' then (select jsonb_build_object('doc_number', public.qbo_refund_label(p), 'name', (select cu.name from public.customer cu where cu.id = p.customer_id), 'customer_id', p.customer_id, 'currency', p.currency_code, 'total', p.amount, 'doc_date', p.paid_on, 'doc_status', p.status)
                          from public.so_payment p where p.id::text = p_ims_id and p.kind = 'refund')   -- 2e-3-2-1: 환불 = reference(없으면 「Refund <날> <금액>」) · 손님 · 통화 · 금액 · 결제일 · active | voided
    when 'cost_sheet' then (select jsonb_build_object('doc_number', s.doc_number, 'name', case s.kind when 'rebuild' then 'IMS cost rebuild ' else 'Cost day ' end || s.sheet_date::text || ' ' || s.wh, 'customer_id', null, 'currency', 'CAD', 'total', round(s.built_debit_cents / 100.0, 2), 'doc_date', s.sheet_date, 'doc_status', s.state)
                              from public.qbo_cost_sheet s where s.realm_id = public.qbo_realm_of() and s.sheet_date = split_part(p_ims_id, '|', 1)::date and s.wh = split_part(p_ims_id, '|', 2)
                               and s.kind = case when split_part(p_ims_id, '|', 3) = 'rebuild' then 'rebuild' else 'day' end)   -- 3-2b: 하루 원가 장 = ims_id 「YYYY-MM-DD|TOR[|rebuild]」 · 이름 「Cost day <날> <창고>」 · 금액 = 만들 때 차변 · 상태 = 장 state
    else jsonb_build_object('doc_number', p_ims_id, 'name', p_ims_id, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', null) end;
$$;
-- qbo_job_list d72b4c8edbbfec4fdbe45fa04c618cbf → kinds 19 · ims_name cost_sheet · txn join cost_sheet
create or replace function public.qbo_job_list (p_state text default null, p_kinds text[] default null, p_from date default null, p_to date default null, p_q text default null, p_limit int default 50, p_offset int default 0) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if p_state is not null and p_state not in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped', 'open') then raise exception 'state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open (got %)', p_state; end if;
  if p_kinds is not null and (not (p_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day']) or coalesce(array_length(p_kinds, 1), 0) = 0) then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void, refund, refund_void, refund_apply, refund_apply_void, cost_day (got %)', p_kinds; end if;   -- 2e-3-2-1 kinds 18 · 3-2b cost_day 19
  if p_from is not null and p_to is not null and p_from > p_to then raise exception 'from % is after to % — nothing was read', p_from, p_to; end if;
  return (with base as (
      select j.id, j.kind, j.ims_kind, j.ims_id, j.state, j.attempts, j.next_at, j.claimed_at, j.blocked_by, j.qbo_id, j.qbo_name, j.sent_at, j.last_error, j.last_intuit_tid, j.warning, j.note, j.by_staff, j.created_at, j.updated_at,
             (j.created_at at time zone 'America/Toronto')::date as job_date,
             d.doc->>'doc_number' as doc_number, d.doc->>'name' as name, d.doc->>'currency' as currency, (d.doc->>'total')::numeric as total, (d.doc->>'doc_date')::date as doc_date, d.doc->>'doc_status' as doc_status,
             case j.ims_kind when 'invoice' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'credit' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'payment' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-1b
                             when 'credit_alloc' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-2-1
                             when 'opening_alloc' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-3-1
                             when 'refund' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-3-2-1
                             when 'cost_sheet' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '')   -- 3-2b 하루 원가 장 = 「COGS-… · Cost day <날> <창고>」
                             when 'product' then coalesce(d.doc->>'doc_number', '') || ' ' || coalesce(d.doc->>'name', '')
                             else coalesce(d.doc->>'name', j.ims_id) end as ims_name,
             (select s.name from public.ims_staff s where s.id = j.by_staff) as by_name,
             p.kind as blocked_kind, p.state as blocked_state, coalesce(pd.doc->>'doc_number', pd.doc->>'name', p.ims_id) as blocked_name,
             t.qbo_id as txn_qbo_id, t.total_amt as txn_total_amt, t.total_tax as txn_total_tax, t.mismatch as txn_mismatch, t.voided_at as txn_voided_at
      from public.qbo_job j
      cross join lateral (select public.qbo_job_doc(j.ims_kind, j.ims_id) as doc) d
      left join public.qbo_job p on p.id = j.blocked_by
      left join lateral (select public.qbo_job_doc(p.ims_kind, p.ims_id) as doc) pd on p.id is not null
      left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund', 'cost_sheet')   -- 2e-3-2-1 + refund · 3-2b + cost_sheet(JournalEntry)
                               and t.ims_kind = case j.kind when 'opening_credit' then 'opening_credit' when 'opening_credit_void' then 'opening_credit' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc'
                                                            when 'refund_apply' then 'refund_apply' when 'refund_apply_void' then 'refund_apply' else j.ims_kind end   -- 2e-3-1 이견 3: 한 붙임에 txn 둘 — kind 로 갈라 잇는다 · 2e-3-2-1 이견 8: 환불도(refund · refund_void ↔ txn refund(Purchase) · refund_apply · _void ↔ txn refund_apply(Payment))
      where j.realm_id = v_realm and (p_state is null or (p_state = 'open' and j.state not in ('sent', 'skipped')) or j.state = p_state)
        and (p_kinds is null or j.kind = any (p_kinds))
        and (p_from is null or (j.created_at at time zone 'America/Toronto')::date >= p_from) and (p_to is null or (j.created_at at time zone 'America/Toronto')::date <= p_to)),
    hit as (select b.* from base b where v_q is null or b.ims_name ilike '%' || v_q || '%' or coalesce(b.qbo_id, '') ilike '%' || v_q || '%' or coalesce(b.qbo_name, '') ilike '%' || v_q || '%')
    select jsonb_build_object('state', p_state, 'kinds', to_jsonb(p_kinds), 'from', p_from, 'to', p_to, 'q', v_q, 'total', (select count(*) from hit), 'limit', v_lim, 'offset', v_off,
      'counts', (select coalesce(jsonb_object_agg(x.state, x.n), '{}'::jsonb) from (select j.state, count(*) as n from public.qbo_job j where j.realm_id = v_realm group by j.state) x),
      'rows', coalesce((select jsonb_agg((to_jsonb(b) - 'rk' - 'k_old') order by b.rk, b.k_old, b.created_at desc) from (
                select h.*, case h.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end as rk, case when h.state in ('queued', 'blocked') then h.created_at end as k_old
                  from hit h order by 
                    case h.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end,
                    case when h.state in ('queued', 'blocked') then h.created_at end asc nulls last, h.created_at desc
                  limit v_lim offset v_off) b), '[]'::jsonb)));
end;
$$;
-- qbo_job_retry 004924bca6930c77b34457b6446f7d57 → cost_day 규칙(hold · sent · 뒤 장 · skipped rebuild)
create or replace function public.qbo_job_retry (p_job uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_j public.qbo_job%rowtype; v_doc jsonb; v_open uuid; v_cs public.qbo_cost_sheet%rowtype;   -- 3-2b v_cs
begin
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('failed', 'unknown', 'skipped') then raise exception 'Only a failed or skipped job, or one whose result is unknown, can be sent again (this one is %) — nothing was saved', v_j.state; end if;
  if v_j.state = 'unknown' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say what you checked in QuickBooks (a note is required when the result was unknown) — nothing was saved'; end if;
  if v_j.kind = 'payment' and public.qbo_payment_fingerprint(v_j.ims_id::uuid) is null then                                             -- 2e-1b A-4: 결제 retry = 활성 · 붙임 ≥ 1 일 때만
    raise exception 'Payment % is voided or has no invoice applied — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce((select p.reference from public.so_payment p where p.id = v_j.ims_id::uuid), v_j.ims_id);
  end if;
  if v_j.kind = 'payment_void' and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = 'payment' and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-1b A-4: void retry = QBO 에 서 있을 때만
    raise exception 'Payment % is not standing in QuickBooks — nothing to void — nothing was saved', coalesce((select p.reference from public.so_payment p where p.id = v_j.ims_id::uuid), v_j.ims_id);
  end if;
  if v_j.kind = 'credit_apply' and not exists (select 1 from public.so_credit_alloc a where a.id::text = v_j.ims_id and a.voided_at is null and a.invoice_id is not null) then   -- 2e-2-1 이견 9: 붙임 retry = 활성 · 인보이스 대상 · QBO 에 안 섰을 때만
    raise exception 'Credit application % was detached (or pays a refund) — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'credit_apply' and exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = 'credit_alloc' and t.ims_id = v_j.ims_id and t.voided_at is null) then
    raise exception 'Credit application % is already standing in QuickBooks — nothing to send — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'credit_apply_void' and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = 'credit_alloc' and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-2-1 이견 9: void retry = QBO 에 서 있을 때만
    raise exception 'Credit application % is not standing in QuickBooks — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'credit_apply_void' and exists (select 1 from public.so_credit_alloc a where a.id::text = v_j.ims_id and a.voided_at is null) then
    raise exception 'Credit application % is still applied in IMS — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind in ('opening_credit', 'opening_apply') and not exists (select 1 from public.so_payment_alloc a where a.id::text = v_j.ims_id and a.voided_at is null) then   -- 2e-3-1 이견 13: 붙임 retry = 활성 ∧ 그 장이 QBO 에 안 섰을 때만
    raise exception 'Opening credit % was detached — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind in ('opening_credit', 'opening_apply') and exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'opening_credit' then 'opening_credit' else 'opening_alloc' end and t.ims_id = v_j.ims_id and t.voided_at is null) then
    raise exception 'Opening credit % (%) is already standing in QuickBooks — nothing to send — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'opening_credit' then 'credit memo' else 'zero payment' end;
  end if;
  if v_j.kind in ('opening_credit_void', 'opening_apply_void') and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'opening_credit_void' then 'opening_credit' else 'opening_alloc' end and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-3-1 이견 13: void retry = 그 장이 QBO 에 서 있을 때만
    raise exception 'Opening credit % (%) is not standing in QuickBooks — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'opening_credit_void' then 'credit memo' else 'zero payment' end;
  end if;
  if v_j.kind in ('opening_credit_void', 'opening_apply_void') and exists (select 1 from public.so_payment_alloc a where a.id::text = v_j.ims_id and a.voided_at is null) then
    raise exception 'Opening credit % is still applied in IMS — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind in ('refund', 'refund_apply') and not exists (select 1 from public.so_payment p where p.id::text = v_j.ims_id and p.kind = 'refund' and p.status = 'active') then   -- 2e-3-2-1 이견 14: 환불 retry = 활성 ∧ 그 장이 QBO 에 안 섰을 때만(컷은 보지 않는다 — ⓖ-4 의 「Retry」 = Send)
    raise exception 'Refund % is voided — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind in ('refund', 'refund_apply') and exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'refund' then 'refund' else 'refund_apply' end and t.ims_id = v_j.ims_id and t.voided_at is null) then
    raise exception 'Refund % (%) is already standing in QuickBooks — nothing to send — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'refund' then 'expense' else 'zero payment' end;
  end if;
  if v_j.kind in ('refund_void', 'refund_apply_void') and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'refund_void' then 'refund' else 'refund_apply' end and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-3-2-1 이견 14: void retry = 그 장이 QBO 에 서 있을 때만(ⓖ-5 알림 일감은 여기서 거부 → Skip)
    raise exception 'Refund % (%) is not standing in QuickBooks — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'refund_void' then 'expense' else 'zero payment' end;
  end if;
  if v_j.kind in ('refund_void', 'refund_apply_void') and exists (select 1 from public.so_payment p where p.id::text = v_j.ims_id and p.kind = 'refund' and p.status = 'active') then
    raise exception 'Refund % is still active in the IMS — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'cost_day' then                                                                                                        -- 3-2b: 하루 원가 장 retry = 장이 hold(재생성) 면 거부 → release 로 · sent 면 거부 · 같은 창고 뒤 장이 이미 나갔으면 거부(그 몫을 뒤 장이 담았다 · 1092) · skip 된 rebuild 장은 다시 못 보낸다(release 다시)
    select * into v_cs from public.qbo_cost_sheet s where s.job_id = v_j.id;
    if v_cs.id is null then raise exception 'No cost day sheet is attached to job % — nothing was saved', v_j.id; end if;
    if v_cs.state = 'hold' then raise exception 'Cost day % is on hold after a cost rebuild — review it under Cost days → rebuild preview and release it (qbo_cost_rebuild_release) — nothing was saved', v_cs.doc_number; end if;
    if v_cs.state = 'sent' then raise exception 'Cost day % is already in QuickBooks — nothing to send — nothing was saved', v_cs.doc_number; end if;
    if exists (select 1 from public.qbo_cost_sheet s where s.realm_id = v_cs.realm_id and s.wh = v_cs.wh and s.kind = 'day' and s.sheet_date > v_cs.sheet_date and s.state in ('sent', 'sending', 'unknown')) then
      raise exception 'A later cost day of % already went to QuickBooks and carried these amounts — % cannot be sent again — nothing was saved', v_cs.wh, v_cs.doc_number;
    end if;
    if v_j.state = 'skipped' then
      if v_cs.kind = 'rebuild' then raise exception 'A skipped rebuild sheet (%) cannot be sent again — release the rebuild again under Cost days — nothing was saved', v_cs.doc_number; end if;
      if nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say why this skipped job should be sent after all (a note is required) — nothing was saved'; end if;
      update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, blocked_by = null, request_id = gen_random_uuid(), note = btrim(p_note), updated_by = v_staff where j.id = v_j.id;
      return jsonb_build_object('job_id', v_j.id, 'state', 'queued', 'attempts', v_j.attempts, 'was', 'skipped');
    end if;
  end if;
  if v_j.state = 'skipped' then                                                                                                        -- 2d1 이견 ④: 되돌리기 — note 필수 · 문서 상태 · 같은 열쇠의 열린 일감 없음
    if nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say why this skipped job should be sent after all (a note is required) — nothing was saved'; end if;
    v_doc := public.qbo_job_doc(v_j.ims_kind, v_j.ims_id);
    if v_j.kind in ('invoice', 'credit') and coalesce(v_doc->>'doc_status', '') <> 'issued' then
      raise exception '% % is % — a skipped job can only be sent again while the document is issued — nothing was saved', case v_j.kind when 'invoice' then 'Invoice' else 'Credit note' end, coalesce(v_doc->>'doc_number', v_j.ims_id), coalesce(v_doc->>'doc_status', 'missing');
    end if;
    if v_j.kind in ('invoice_void', 'credit_void') and coalesce(v_doc->>'doc_status', '') <> 'cancelled' then
      raise exception '% % is % — a skipped void can only be sent again while the document is cancelled — nothing was saved', case v_j.kind when 'invoice_void' then 'Invoice' else 'Credit note' end, coalesce(v_doc->>'doc_number', v_j.ims_id), coalesce(v_doc->>'doc_status', 'missing');
    end if;
    select j.id into v_open from public.qbo_job j where j.realm_id = v_j.realm_id and j.kind = v_j.kind and j.ims_kind = v_j.ims_kind and j.ims_id = v_j.ims_id and j.state not in ('sent', 'skipped') and j.id <> v_j.id limit 1;
    if v_open is not null then raise exception 'Another open job (%) already exists for this % — send or skip that one instead — nothing was saved', v_open, v_j.kind; end if;
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, blocked_by = null, request_id = gen_random_uuid(), note = btrim(p_note), updated_by = v_staff where j.id = v_j.id;
    return jsonb_build_object('job_id', v_j.id, 'state', 'queued', 'attempts', v_j.attempts, 'was', 'skipped');
  end if;
  update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = coalesce(nullif(btrim(p_note), ''), j.note), updated_by = v_staff where j.id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'state', 'queued', 'attempts', v_j.attempts, 'was', v_j.state);
end;
$$;
-- qbo_job_done bfde1f1087164fbd9f57695fa63d1ddd → cost_day 가지(qbo_txn JournalEntry · TotalAmt 대조)
create or replace function public.qbo_job_done (p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text default null, p_intuit_tid text default null, p_note text default null, p_sku text default null, p_total_amt numeric default null, p_total_tax numeric default null, p_unapplied_amt numeric default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_j public.qbo_job%rowtype; v_type text; v_link_err text; v_unblocked int := 0; v_i public.so_invoice%rowtype; v_c public.so_credit%rowtype; v_mismatch text; v_n int; v_p public.so_payment%rowtype; v_applied numeric; v_sync jsonb;   -- 2e-1b v_p · v_applied · v_sync
        v_alabel text;   -- 2e-2-1
        v_oa public.so_payment_alloc%rowtype;   -- 2e-3-1
        v_cs public.qbo_cost_sheet%rowtype;   -- 3-2b
begin
  if not public.doc_is_service() then raise exception 'qbo_job_done is for the send worker only — nothing was saved'; end if;
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('sending', 'unknown') then raise exception 'Only a job being sent, or one whose result is unknown, can be finished (this one is %) — nothing was saved', v_j.state; end if;
  if nullif(btrim(coalesce(p_qbo_id, '')), '') is null or nullif(btrim(coalesce(p_qbo_name, '')), '') is null then raise exception 'qbo_id and qbo_name are required — nothing was saved'; end if;
  update public.qbo_job j set state = 'sent', sent_at = now(), claimed_at = null, qbo_id = btrim(p_qbo_id), qbo_name = btrim(p_qbo_name), sync_token = p_sync_token, last_intuit_tid = coalesce(p_intuit_tid, j.last_intuit_tid),
         last_error = case when p_note is not null then left(coalesce(j.last_error || ' · ', '') || p_note, 2000) else j.last_error end, attempts = j.attempts + case when p_note is not null then 1 else 0 end
   where j.id = v_j.id;
  if v_j.kind in ('customer', 'item') then
    v_type := case v_j.ims_kind when 'customer' then 'Customer' else 'Item' end;
    insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, active, sync_token, fetched_at, gone_at)
    values (v_j.realm_id, v_type, btrim(p_qbo_id), btrim(p_qbo_name), nullif(btrim(coalesce(p_sku, '')), ''), true, p_sync_token, now(), null)
    on conflict (realm_id, qbo_type, qbo_id) do update set name = excluded.name, sku = coalesce(excluded.sku, public.qbo_entity.sku), active = true, sync_token = excluded.sync_token, fetched_at = now(), gone_at = null;
    begin
      insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match, by_staff)
      values (v_j.realm_id, v_j.ims_kind, v_j.ims_id, v_type, btrim(p_qbo_id), 'created', btrim(p_qbo_name), v_j.by_staff)
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_type = excluded.qbo_type, qbo_id = excluded.qbo_id, matched_by = 'created', qbo_name_at_match = excluded.qbo_name_at_match, matched_at = now(), updated_at = now(), updated_by = excluded.by_staff;
    exception when unique_violation then                                                              -- QBO 쪽 부분 유일(이미 다른 IMS 행의 짝) — QBO 레코드는 생겼다 · 사람이 짝을 바로잡는다
      v_link_err := format('QuickBooks %s #%s was created but is already linked to another IMS row — fix the link by hand under Settings → QuickBooks matching', v_type, btrim(p_qbo_id));
    end;
  elsif v_j.kind = 'invoice' then                                                                      -- 2b1: 거래 짝 + 942 합계 대조(상태는 sent · 다르면 mismatch · 자동 void 없음)
    select * into v_i from public.so_invoice i where i.id = v_j.ims_id::uuid;
    v_mismatch := case when p_total_amt is null or p_total_tax is null then 'QuickBooks did not return TotalAmt / TotalTax — check invoice ' || coalesce(v_i.invoice_number, v_j.ims_id) || ' in QuickBooks'
                       when p_total_amt <> v_i.total or p_total_tax <> v_i.tax_amount then format('QuickBooks total %s / tax %s differs from IMS %s / %s — check invoice %s in QuickBooks (942)', p_total_amt, p_total_tax, v_i.total, v_i.tax_amount, v_i.invoice_number) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at)
      values (v_j.realm_id, 'invoice', v_j.ims_id, 'Invoice', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null)
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, updated_at = now();
    exception when unique_violation then                                                              -- (realm, Invoice, qbo_id) 가 이미 다른 IMS 인보이스의 짝
      v_link_err := format('QuickBooks Invoice #%s is already recorded for another IMS invoice — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'invoice_void' then                                                                 -- 2b1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'invoice' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent invoice on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'credit' then                                                                       -- 2c1: 거래 짝(CreditMemo) + 942 대조(so_credit.total · tax_amount · 상태는 sent · 자동 void 없음)
    select * into v_c from public.so_credit c where c.id = v_j.ims_id::uuid;
    v_mismatch := case when p_total_amt is null or p_total_tax is null then 'QuickBooks did not return TotalAmt / TotalTax — check credit note ' || coalesce(v_c.credit_number, v_j.ims_id) || ' in QuickBooks'
                       when p_total_amt <> v_c.total or p_total_tax <> v_c.tax_amount then format('QuickBooks total %s / tax %s differs from IMS %s / %s — check credit note %s in QuickBooks (942)', p_total_amt, p_total_tax, v_c.total, v_c.tax_amount, v_c.credit_number) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at)
      values (v_j.realm_id, 'credit', v_j.ims_id, 'CreditMemo', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null)
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, updated_at = now();
    exception when unique_violation then                                                              -- (realm, CreditMemo, qbo_id) 가 이미 다른 IMS 크레딧의 짝
      v_link_err := format('QuickBooks CreditMemo #%s is already recorded for another IMS credit note — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'credit_void' then                                                                  -- 2c1 판정 963: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'credit' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent credit note on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'payment' then                                                                      -- 2e-1b: 거래 짝(Payment) + 지문(claim 이 일감에 적은 것) + 942 꼴 대조(TotalAmt = amount · UnappliedAmt = amount − Σ붙임 · 상태는 sent · 자동 void 없음)
    select * into v_p from public.so_payment p where p.id = v_j.ims_id::uuid;
    select coalesce(sum(a.amount), 0) into v_applied from public.so_payment_alloc a where a.payment_id = v_p.id and a.voided_at is null;
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check payment ' || coalesce(v_p.reference, v_j.ims_id) || ' in QuickBooks'
                       when p_total_amt <> v_p.amount then format('QuickBooks total %s differs from IMS %s — check payment %s in QuickBooks (942)', p_total_amt, v_p.amount, coalesce(v_p.reference, v_j.ims_id))
                       when p_unapplied_amt is not null and p_unapplied_amt <> v_p.amount - v_applied then format('QuickBooks unapplied %s differs from IMS %s — check payment %s in QuickBooks (942)', p_unapplied_amt, v_p.amount - v_applied, coalesce(v_p.reference, v_j.ims_id)) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'payment', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, v_j.fingerprint, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = excluded.fingerprint, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 결제의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS payment — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'payment_void' then                                                                 -- 2e-1b 978: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'payment' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent payment on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'credit_apply' then                                                                  -- 2e-2-1 판정 1009 · 1011: 거래 짝(credit_alloc ↔ 0 원 Payment · 지문 없음) + 대조(TotalAmt 0 · UnappliedAmt 0 · 상태는 sent · 자동 void 없음)
    v_alabel := coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check credit application ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> 0 then format('QuickBooks total %s is not 0 — check credit application %s in QuickBooks (942)', p_total_amt, v_alabel)
                       when p_unapplied_amt is not null and p_unapplied_amt <> 0 then format('QuickBooks unapplied %s is not 0 — check credit application %s in QuickBooks (942)', p_unapplied_amt, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'credit_alloc', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'credit_apply_void' then                                                             -- 2e-2-1 1011: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'credit_alloc' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent credit application on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'opening_credit' then                                                                -- 2e-3-1 이견 14: 거래 짝(opening_credit ↔ 「쓰기」 CreditMemo) + 대조(TotalAmt = 붙임 금액 ∧ TotalTax 0 · 상태는 sent · 자동 void 없음)
    select * into v_oa from public.so_payment_alloc a where a.id = v_j.ims_id::uuid;
    v_alabel := coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null or p_total_tax is null then 'QuickBooks did not return TotalAmt / TotalTax — check opening credit ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> v_oa.amount or p_total_tax <> 0 then format('QuickBooks total %s / tax %s differs from IMS %s / 0 — check opening credit %s in QuickBooks (942)', p_total_amt, p_total_tax, v_oa.amount, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'opening_credit', v_j.ims_id, 'CreditMemo', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, CreditMemo, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks CreditMemo #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'opening_credit_void' then                                                           -- 2e-3-1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'opening_credit' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent opening credit memo on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'opening_apply' then                                                                 -- 2e-3-1 이견 14: 거래 짝(opening_alloc ↔ 0 원 Payment · 지문 없음) + 대조(TotalAmt 0 · UnappliedAmt 0 · 상태는 sent)
    v_alabel := coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check opening credit application ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> 0 then format('QuickBooks total %s is not 0 — check opening credit application %s in QuickBooks (942)', p_total_amt, v_alabel)
                       when p_unapplied_amt is not null and p_unapplied_amt <> 0 then format('QuickBooks unapplied %s is not 0 — check opening credit application %s in QuickBooks (942)', p_unapplied_amt, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'opening_alloc', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'opening_apply_void' then                                                            -- 2e-3-1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'opening_alloc' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent opening credit application on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'refund' then                                                                       -- 2e-3-2-1 이견 15: 거래 짝(refund ↔ Purchase) + 대조(TotalAmt = 크레딧 몫 합 · TotalTax 0 · 상태는 sent · 자동 void 없음)
    select * into v_p from public.so_payment p where p.id = v_j.ims_id::uuid;
    select coalesce(sum(a.amount), 0) into v_applied from public.so_credit_alloc a where a.refund_payment_id = v_p.id and a.voided_at is null;
    v_alabel := public.qbo_refund_label(v_p);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check refund ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> v_applied then format('QuickBooks total %s differs from IMS %s (credit-note part of refund %s) — check it in QuickBooks (942)', p_total_amt, v_applied, v_alabel)
                       when p_total_tax is not null and p_total_tax <> 0 then format('QuickBooks tax %s is not 0 — check refund %s in QuickBooks (942)', p_total_tax, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'refund', v_j.ims_id, 'Purchase', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Purchase, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Purchase #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'refund_void' then                                                                  -- 2e-3-2-1 ⓖ-7: 거래 짝에 void 흔적(EF 는 TotalAmt 0 ∧ 「Voided - 」 로 done)
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'refund' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent refund expense on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'refund_apply' then                                                                 -- 2e-3-2-1 이견 15: 거래 짝(refund_apply ↔ 0 원 Payment · 지문 없음) + 대조(TotalAmt 0 · UnappliedAmt 0 · 상태는 sent)
    v_alabel := coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check the zero payment of refund ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> 0 then format('QuickBooks total %s is not 0 — check the zero payment of refund %s in QuickBooks (942)', p_total_amt, v_alabel)
                       when p_unapplied_amt is not null and p_unapplied_amt <> 0 then format('QuickBooks unapplied %s is not 0 — check the zero payment of refund %s in QuickBooks (942)', p_unapplied_amt, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'refund_apply', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'refund_apply_void' then                                                            -- 2e-3-2-1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'refund_apply' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent refund zero payment on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'cost_day' then                                                                     -- 3-2b: 거래 짝(cost_sheet ↔ JournalEntry · doc_number = DocNumber) + 대조(TotalAmt = 차변 센트 합 · 지문 「<차변 센트>|<줄 md5>」 는 claim 이 적었다) · 장은 트리거로 sent · 줄은 다시 셈하지 않는다(이견 9)
    select * into v_cs from public.qbo_cost_sheet s where s.job_id = v_j.id;
    v_alabel := coalesce(v_cs.doc_number, v_j.ims_id);
    v_mismatch := case when v_cs.id is null then 'IMS has no cost day sheet attached to this job — check qbo_cost_sheet by hand'
                       when p_total_amt is null then 'QuickBooks did not return TotalAmt — check journal entry ' || v_alabel || ' in QuickBooks'
                       when round(p_total_amt * 100) <> coalesce(nullif(split_part(coalesce(v_j.fingerprint, ''), '|', 1), '')::bigint, -1) then format('QuickBooks total %s differs from IMS %s — check journal entry %s in QuickBooks (942)', p_total_amt, round(coalesce(nullif(split_part(coalesce(v_j.fingerprint, ''), '|', 1), '')::bigint, 0) / 100.0, 2), v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'cost_sheet', v_j.ims_id, 'JournalEntry', btrim(p_qbo_id), coalesce(v_cs.doc_number, btrim(p_qbo_name)), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, v_j.fingerprint, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = excluded.fingerprint, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, JournalEntry, qbo_id) 가 이미 다른 IMS 행의 짝 → 일감 failed · 장은 트리거가 unknown 으로(행 유지 · 사람이 resolve)
      v_link_err := format('QuickBooks JournalEntry #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  end if;
  if v_link_err is not null then
    update public.qbo_job j set state = 'failed', sent_at = null, last_error = left(coalesce(j.last_error || ' · ', '') || v_link_err, 2000) where j.id = v_j.id;
  else
    update public.qbo_job j set state = 'queued', next_at = now() where j.state = 'blocked' and j.blocked_by = v_j.id;
    get diagnostics v_unblocked = row_count;
  end if;
  if v_j.kind in ('payment', 'payment_void') and v_link_err is null then                              -- 2e-1b A-10: 보낸 뒤 reconcile — 보내는 동안 붙임이 바뀌었으면 void · 다시 보내기 일감을 지금 쌓는다(in-flight 중에는 열린 payment 일감 자리가 하나라 못 쌓는다)
    begin v_sync := public.qbo_payment_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  if v_j.kind in ('credit_apply', 'credit_apply_void') and v_link_err is null then                     -- 2e-2-1 이견 8: 보낸 뒤 상태 맞추기 — 보내는 동안 떼였으면 void 일감을 쌓는다
    begin v_sync := public.qbo_credit_alloc_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  if v_j.kind in ('opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void') and v_link_err is null then   -- 2e-3-1 이견 14: 보낸 뒤 상태 맞추기 — 보내는 동안 떼였으면 void 일감을 쌓는다 · CreditMemo 가 서면 apply 는 ② 가 푼다
    begin v_sync := public.qbo_opening_alloc_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  if v_j.kind in ('refund', 'refund_void', 'refund_apply', 'refund_apply_void') and v_link_err is null then   -- 2e-3-2-1 이견 15: 보낸 뒤 상태 맞추기 — 보내는 동안 void 됐으면 void 일감을 쌓는다 · Purchase 가 서면 apply 는 ② 가 푼다
    begin v_sync := public.qbo_refund_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  return jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'state', case when v_link_err is null then 'sent' else 'failed' end, 'reconcile', v_sync, 'qbo_id', btrim(p_qbo_id), 'qbo_name', btrim(p_qbo_name), 'linked', v_link_err is null, 'link_error', v_link_err, 'unblocked', v_unblocked, 'mismatch', v_mismatch);
end;
$$;

-- ═══════════════ ⑧ 표 CHECK · 트리거(⚠️ 일부러 끝에 — qbo_job · qbo_txn 잠금은 여기부터 끝까지만) · grant · comment ═══════════════
alter table public.qbo_job
  drop constraint qbo_job_kind_ck,
  add  constraint qbo_job_kind_ck check (kind in ('customer', 'item', 'invoice', 'credit', 'invoice_void', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day')),
  drop constraint qbo_job_ims_kind_ck,
  add  constraint qbo_job_ims_kind_ck check (ims_kind in ('customer', 'product', 'charge', 'invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund', 'cost_sheet')),
  drop constraint qbo_job_pair_ck,
  add  constraint qbo_job_pair_ck check (ims_kind = case kind when 'customer' then 'customer' when 'invoice' then 'invoice' when 'invoice_void' then 'invoice' when 'credit' then 'credit' when 'credit_void' then 'credit'
                                                                                        when 'payment' then 'payment' when 'payment_void' then 'payment' when 'credit_apply' then 'credit_alloc' when 'credit_apply_void' then 'credit_alloc'
                                                                                        when 'opening_credit' then 'opening_alloc' when 'opening_credit_void' then 'opening_alloc' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc'
                                                                                        when 'refund' then 'refund' when 'refund_void' then 'refund' when 'refund_apply' then 'refund' when 'refund_apply_void' then 'refund'
                                                                                        when 'cost_day' then 'cost_sheet' else ims_kind end
                                                                and (kind <> 'item' or ims_kind in ('product', 'charge')));
create trigger qbo_job_cost_sheet_sync after update of state on public.qbo_job for each row when (new.kind = 'cost_day') execute function public.qbo_job_cost_sheet_sync();
alter table public.qbo_txn
  drop constraint qbo_txn_kind_ck,
  add  constraint qbo_txn_kind_ck check (ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_credit', 'opening_alloc', 'refund', 'refund_apply', 'cost_sheet')),
  drop constraint qbo_txn_type_ck,
  add  constraint qbo_txn_type_ck check (qbo_type in ('Invoice', 'CreditMemo', 'Payment', 'Purchase', 'JournalEntry')),
  drop constraint qbo_txn_pair_ck,
  add  constraint qbo_txn_pair_ck check (qbo_type = case ims_kind when 'invoice' then 'Invoice' when 'credit' then 'CreditMemo' when 'opening_credit' then 'CreditMemo' when 'refund' then 'Purchase' when 'cost_sheet' then 'JournalEntry' else 'Payment' end);

revoke all on function public.qbo_cost_sheet_ims_id(date, text, text), public.qbo_cost_sheet_id_for_job(uuid), public.qbo_cost_day_body(uuid), public.qbo_cost_sheet_queue_one(uuid, uuid), public.qbo_cost_sheet_queue(date, text), public.qbo_cost_queue_due(),
  public.qbo_job_cost_sheet_sync(), public.qbo_cost_hold_all(text, text), public.qbo_cost_rebuild_calc(text, text), public.qbo_cost_rebuild_preview(), public.qbo_cost_rebuild_release(text), public.qbo_cost_sheet_resolve(uuid, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.qbo_cost_sheet_ims_id(date, text, text) to authenticated, service_role;   -- 이름 꼴은 열어 둔다(화면 꼬리표)
grant execute on function public.qbo_cost_sheet_queue(date, text), public.qbo_cost_queue_due(), public.qbo_cost_rebuild_preview(), public.qbo_cost_rebuild_release(text), public.qbo_cost_sheet_resolve(uuid, text, text, text) to authenticated, service_role;   -- 열쇠 창구 다섯(qbo_key_gate 가 가른다)

do $$
begin
  execute format('comment on table public.qbo_job is %L', coalesce(obj_description('public.qbo_job'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-3-2b: kind cost_day(ims_kind cost_sheet · ims_id 「YYYY-MM-DD|TOR[|rebuild]」 · 장 하나 = 일감 하나 · 사람 창구 qbo_cost_sheet_queue 가 세운다 · 자동 0 · 장 state 는 트리거 qbo_job_cost_sheet_sync 가 따라간다 · 지문 「<차변 센트>|<줄 md5>」 · EF 는 3-3)');
  execute format('comment on table public.qbo_txn is %L', coalesce(obj_description('public.qbo_txn'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-3-2b: ims_kind cost_sheet ↔ QBO JournalEntry(doc_number = COGS-YYYYMMDD-TOR(-R) · total_amt = 차변 합 · fingerprint = 지문 · source sent)');
  execute format('comment on table public.qbo_cost_sheet is %L', coalesce(obj_description('public.qbo_cost_sheet'::regclass, 'pg_class'), '') || ' · [3-2b] job_id = cost_day 일감(장 하나 = 일감 하나) · state 는 일감을 따라간다(트리거) · hold 는 claim 의 epoch 비교가 realm 전부에 · release 가 rebuild 장(kind rebuild · 오늘 날짜 · -R)을 만든다 · unknown 은 qbo_cost_sheet_resolve');
  execute format('comment on table public.qbo_cost_sent is %L', coalesce(obj_description('public.qbo_cost_sent'::regclass, 'pg_class'), '') || ' · [3-2b] day 장의 행은 claim 이 넣고(sending) 트리거가 queued · failed · skipped 에서 지운다 · rebuild 장의 행은 release 가 넣고 void 에서만 지운다');
end $$;
