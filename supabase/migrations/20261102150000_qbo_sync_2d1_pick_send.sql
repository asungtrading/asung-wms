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
-- qbo-sync-2d1 — 북키퍼가 골라 보내는 QuickBooks 보내기(판정 971): claim 에 일감 id 고르기 · 미리 보기 창구 · 목록 재발행(거르기 · 쪽 · 칸) · retry 가 skipped 도 (2026-11-02 · 지시서 ~/asung/prompts/qbo-sync-2d-1.md · Fable · 이견 ① ~ ⑤ 답 반영)
--   경계: 2d1 = DB(이 파일) + EF qbo(같은 커밋 · _shared/qbo.ts send { job_ids } · 바퀴 최대 5 · 한도 10 · 30 s) · 화면(qbo-send.html · Sales 묶음 「QuickBooks」 · ims-auth.js 한 줄)은 대화 Claude
--   ⚠️ 적용 순서 한 덩이: 이 마이그레이션 → repair → EF 배포 — 옛 EF 는 claim(p_limit, p_kinds) 두 인자로 부르고 새 서명은 p_job_ids 기본 null 이라 옛 EF 도 그대로 돈다 · 새 EF 는 p_job_ids 를 보내므로 DB 가 먼저여야 한다
--   A claim(p_limit, p_kinds, p_job_ids uuid[] default null) — drop(int, text[]) + create(int, text[], uuid[]) · 몸 = 2c1 바이트 + ③ 이 p_job_ids 가 있으면 그 id 만(한도 없음 · ≤ 200 개) · ④ 의 needs 가 만든 need 일감을 need_jobs 로 돌려준다(blocked_by 는 손님 need 를 우선 — 부모 → 손님 두 바퀴 뒤에 풀리게) · requested[] = 고른 id 마다 결과(not_found · not_queued(state) · wrong_kind · not_due · locked · claimed · blocked(reason) · failed(error))
--   B qbo_job_preview(p_job) — 열쇠 qbo 또는 qbo:read(이견 ② 답) · 몸 함수 여섯을 kind 로 부르고 예외를 잡는다 · need 일감을 만들지 않는다(claim 과 다른 점) · needs 마다 열린 일감(있으면 id · state) · wait(960 크레딧) · blocked_by 부모 · error(사람 짝 글 그대로) · sendable · QBO 호출 0
--   C qbo_job_list(p_state, p_kinds, p_from, p_to, p_q, p_limit, p_offset) — drop(text, int, int) + create · 쓰는 화면 0(grep) · 날짜 = 일감 created_at 의 토론토 날짜(이견 ③ 답) · 행에 doc_number · name · currency · total · doc_date · doc_status · blocked_kind · blocked_name · blocked_state · 정렬 unknown → failed → sending → queued(오래된 것 먼저) → blocked(오래된 것 먼저) → 그 밖(최신순) · limit ≤ 200 · counts
--     속 함수 qbo_job_doc(p_ims_kind, p_ims_id)(grant 0) — 문서 · 손님 · 제품의 번호 · 이름 · 통화 · 총액 · 날짜 · 상태 한 줄(목록 · 미리 보기 · 부모 줄이 같이 쓴다)
--   D qbo_job_retry 재발행 — skipped 도 받는다(이견 ④ 답 · note 필수 · invoice · credit 은 문서가 issued · invoice_void · credit_void 는 cancelled 일 때만 · 같은 열쇠의 열린 일감이 있으면 거부) · failed · unknown 갈래는 바이트 그대로 · skipped → queued 는 blocked_by 를 비운다(claim ④ 가 needs 를 다시 센다)
--   무접촉: 몸 함수 여섯 · qbo_job_done · fail · unknown · unknown_list · skip · add · open_or_add · 트리거 넷 · qbo_txn_of · cron 61 · qbo_send_enabled(off 그대로) · 화면
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261102150000_qbo_sync_2d1_pick_send.sql && supabase migration repair --status applied 20261102150000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=supabase/migrations/20261102150000_qbo_sync_2d1_pick_send.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2d1_check.sql

-- ═══ A) claim — 고른 id 만 · need_jobs · requested ═══
drop function public.qbo_job_claim(int, text[]);
create function public.qbo_job_claim(p_limit int default 15, p_kinds text[] default array['customer', 'item'], p_job_ids uuid[] default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_stale int; v_unblocked int; v_ids uuid[]; v_j public.qbo_job%rowtype; v_open public.qbo_job%rowtype; v_b jsonb; v_rows jsonb := '[]'::jsonb; v_failed int := 0; v_blocked int := 0; v_waiting int := 0; v_last uuid; v_cust uuid; v_nj jsonb; e jsonb;
  v_kinds text[] := coalesce(p_kinds, array['customer', 'item']);
  v_pick uuid[] := (select array_agg(distinct x) from unnest(p_job_ids) x where x is not null);                                       -- 2d1: 고른 id(중복 · null 제거) · null 이면 옛 길(가장 오래된 것부터 p_limit)
  v_needs jsonb := '[]'::jsonb; v_req jsonb := '[]'::jsonb; v_r record;
begin
  if not public.doc_is_service() then raise exception 'qbo_job_claim is for the send worker only — nothing was read'; end if;
  if not (v_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void']) or coalesce(array_length(v_kinds, 1), 0) = 0 then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void (got %)', v_kinds; end if;
  if p_job_ids is not null and coalesce(array_length(v_pick, 1), 0) = 0 then raise exception 'job_ids must name at least one job — nothing was read'; end if;
  if coalesce(array_length(v_pick, 1), 0) > 200 then raise exception 'job_ids may name at most 200 jobs in one call (got %) — nothing was read', array_length(v_pick, 1); end if;
  -- ① 멈춘 sending(EF 가 도중에 죽었다 · QBO 에 닿았는지 모른다) → unknown(mail_claim 꼴 · 자동 재전송 금지 · 다음 send 가 이름 · DocNumber 로 조회해 푼다)
  update public.qbo_job j set state = 'unknown', claimed_at = null,
         last_error = left(coalesce(j.last_error || ' · ', '') || format('stale: still sending %s after claim (attempt %s) — QuickBooks may or may not have it', date_trunc('second', now() - j.claimed_at), j.attempts), 2000)
   where j.realm_id = v_realm and j.state = 'sending' and j.claimed_at < now() - interval '10 minutes';
  get diagnostics v_stale = row_count;
  -- ② 부모가 보내졌으면 자식을 연다(손님 → 자식 손님 · need → 인보이스 · 인보이스 → void · 인보이스 → 크레딧)
  update public.qbo_job j set state = 'queued', next_at = now() from public.qbo_job p where j.realm_id = v_realm and j.state = 'blocked' and p.id = j.blocked_by and p.state = 'sent';
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
                           when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid) end;   -- 2c1 credit · credit_void
      if v_b is null then raise exception 'kind % has no body', v_j.kind; end if;
      if v_b->>'parent_customer_id' is not null then raise exception 'parent customer is not in QuickBooks yet — send the parent first (job was not blocked: parent link removed?)'; end if;
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
               warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')) || array[format('waiting for invoice %s to reach QuickBooks first', coalesce(v_b->>'wait_invoice', '?'))], ' · '), '')
         where j.id = v_j.id;
        v_waiting := v_waiting + 1;
        continue;
      end if;
      update public.qbo_job j set warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')), ' · '), '') where j.id = v_j.id;
      v_rows := v_rows || jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'ims_kind', v_j.ims_kind, 'ims_id', v_j.ims_id, 'attempt', v_j.attempts, 'request_id', v_j.request_id,
                                             'name', coalesce(v_b->>'display_name', v_b->>'name'), 'name_alt', v_b->>'name_alt', 'sku', v_b->>'sku', 'doc_number', v_b->>'doc_number', 'qbo_id', v_b->>'qbo_id',
                                             'body', v_b->'body', 'warnings', v_b->'warnings', 'totals', v_b->'totals');
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
                               when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid) end;
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
  return jsonb_build_object('realm_id', v_realm, 'kinds', to_jsonb(v_kinds), 'picked', case when v_pick is null then null else to_jsonb(v_pick) end, 'recovered_unknown', v_stale, 'unblocked', v_unblocked, 'claimed', coalesce(array_length(v_ids, 1), 0), 'body_failed', v_failed, 'blocked_for_needs', v_blocked, 'blocked_for_invoice', v_waiting,
                            'need_jobs', v_needs, 'requested', v_req, 'jobs', v_rows);
end;
$$;
comment on function public.qbo_job_claim(int, text[], uuid[]) is 'qbo-sync-2a · [2b1 p_kinds] · [2c1 credit · credit_void · wait_job] · [2d1 p_job_ids · need_jobs · requested]: EF send 가 service_role 로 부른다 — ① sending 10 분 넘음 → unknown ② blocked → queued(부모 sent) ③ queued · next_at 지남 · kind = any(p_kinds) → sending(p_job_ids 가 있으면 그 id 만 · 한도 없음 · ≤ 200) ④ 일감마다 몸 · needs 가 있으면 need 일감을 쌓고 이 일감은 blocked(blocked_by = 손님 need 우선 · need_jobs[] 로 돌려준다) · 몸 실패는 그 일감만 failed ⑤ requested[] = 고른 id 마다 result(not_found · not_queued · wrong_kind · not_due · locked · claimed · blocked · failed) + reason · 이미 blocked 인 id 는 기다리는 열린 일감을 need_jobs 에(existing true · 다시 고르면 이어진다) · 돌려주는 것 = jobs[{job_id · kind · ims_kind · ims_id · attempt · request_id · name · name_alt · sku · doc_number · qbo_id · body · warnings · totals}]';

-- ═══ B) 속 함수 qbo_job_doc + 미리 보기 창구 ═══
create function public.qbo_job_doc(p_ims_kind text, p_ims_id text) returns jsonb
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
    else jsonb_build_object('doc_number', p_ims_id, 'name', p_ims_id, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', null) end;
$$;
comment on function public.qbo_job_doc(text, text) is 'qbo-sync-2d1(속 · grant 0): 일감이 가리키는 IMS 행 한 줄 — invoice(번호 · 청구처 · 통화 · 총액 · 발행일 · 상태) · credit · customer(이름) · product(sku · 이름) · 그 밖(ims_id) · 목록 · 미리 보기 · 부모 줄이 같이 쓴다 · 행이 없으면 null';

create function public.qbo_job_preview(p_job uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_j public.qbo_job%rowtype; v_b jsonb; v_err text; v_needs jsonb := '[]'::jsonb; e jsonb; v_open public.qbo_job%rowtype; v_wait public.qbo_job%rowtype; v_parent public.qbo_job%rowtype; v_blocked jsonb; v_wait_j jsonb;
begin
  select * into v_j from public.qbo_job j where j.id = p_job and j.realm_id = v_realm;
  if v_j.id is null then raise exception 'Job % not found — nothing to preview', p_job; end if;
  begin
    v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                         when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                         when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid) end;
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
      v_wait_j := jsonb_build_object('job_id', v_wait.id, 'kind', v_wait.kind, 'state', v_wait.state, 'invoice', v_b->>'wait_invoice', 'reason', format('waiting for invoice %s to reach QuickBooks first — send it too', coalesce(v_b->>'wait_invoice', '?')));
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
    'needs', v_needs, 'wait', v_wait_j, 'blocked_by', v_blocked, 'error', v_err,
    'sendable', (v_err is null and jsonb_array_length(v_needs) = 0 and v_wait_j is null and v_j.state = 'queued'),
    'preview_only', true);
end;
$$;
comment on function public.qbo_job_preview(uuid) is 'qbo-sync-2d1 판정 971: 미리 보기(열쇠 qbo 또는 qbo:read) — 일감의 몸을 지금 IMS 값으로 다시 만들어 돌려준다(QBO 호출 0 · need 일감을 만들지 않는다) · job · doc(qbo_job_doc) · body · totals · warnings · needs[{kind · ims_id · name · job_id · job_state}] · wait(960 크레딧 → 인보이스) · blocked_by(부모 일감) · error(몸이 거부한 글 = 사람 짝 · 상태) · sendable(error 없음 · needs 0 · wait 없음 · queued)';

-- ═══ C) 목록 재발행 — 거르기(상태 · 종류 · 날짜 · 검색) · 쪽 · 칸 ═══
drop function public.qbo_job_list(text, int, int);
create function public.qbo_job_list(p_state text default null, p_kinds text[] default null, p_from date default null, p_to date default null, p_q text default null, p_limit int default 50, p_offset int default 0) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if p_state is not null and p_state not in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped', 'open') then raise exception 'state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open (got %)', p_state; end if;
  if p_kinds is not null and (not (p_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void']) or coalesce(array_length(p_kinds, 1), 0) = 0) then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void (got %)', p_kinds; end if;
  if p_from is not null and p_to is not null and p_from > p_to then raise exception 'from % is after to % — nothing was read', p_from, p_to; end if;
  return (with base as (
      select j.id, j.kind, j.ims_kind, j.ims_id, j.state, j.attempts, j.next_at, j.claimed_at, j.blocked_by, j.qbo_id, j.qbo_name, j.sent_at, j.last_error, j.last_intuit_tid, j.warning, j.note, j.by_staff, j.created_at, j.updated_at,
             (j.created_at at time zone 'America/Toronto')::date as job_date,
             d.doc->>'doc_number' as doc_number, d.doc->>'name' as name, d.doc->>'currency' as currency, (d.doc->>'total')::numeric as total, (d.doc->>'doc_date')::date as doc_date, d.doc->>'doc_status' as doc_status,
             case j.ims_kind when 'invoice' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'credit' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'product' then coalesce(d.doc->>'doc_number', '') || ' ' || coalesce(d.doc->>'name', '')
                             else coalesce(d.doc->>'name', j.ims_id) end as ims_name,
             (select s.name from public.ims_staff s where s.id = j.by_staff) as by_name,
             p.kind as blocked_kind, p.state as blocked_state, coalesce(pd.doc->>'doc_number', pd.doc->>'name', p.ims_id) as blocked_name,
             t.qbo_id as txn_qbo_id, t.total_amt as txn_total_amt, t.total_tax as txn_total_tax, t.mismatch as txn_mismatch, t.voided_at as txn_voided_at
      from public.qbo_job j
      cross join lateral (select public.qbo_job_doc(j.ims_kind, j.ims_id) as doc) d
      left join public.qbo_job p on p.id = j.blocked_by
      left join lateral (select public.qbo_job_doc(p.ims_kind, p.ims_id) as doc) pd on p.id is not null
      left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_kind = j.ims_kind and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit')
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
comment on function public.qbo_job_list(text, text[], date, date, text, int, int) is 'qbo-sync-2a · [2b1] · [2d1 거르기 · 칸]: 일감 목록(열쇠 qbo 또는 qbo:read) — state 하나 · open · null = 전부 · kinds 부분집합 · from · to = 일감 created_at 의 토론토 날짜 · q = 번호 · 이름 · QBO id · 이름 검색 · counts(전체) · total(거른 수) · 행 = 일감 + doc_number · name · currency · total · doc_date · doc_status · ims_name · by_name · blocked_kind · blocked_name · blocked_state · 거래 짝 칸(txn_*) · 정렬 unknown → failed → sending → queued(오래된 것 먼저) → blocked(오래된 것 먼저) → 그 밖(최신순) · limit ≤ 200';

-- ═══ D) retry 재발행 — skipped 도(note 필수 · 문서 상태 · 열린 일감 없을 때) ═══
create or replace function public.qbo_job_retry(p_job uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_j public.qbo_job%rowtype; v_doc jsonb; v_open uuid;
begin
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('failed', 'unknown', 'skipped') then raise exception 'Only a failed or skipped job, or one whose result is unknown, can be sent again (this one is %) — nothing was saved', v_j.state; end if;
  if v_j.state = 'unknown' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say what you checked in QuickBooks (a note is required when the result was unknown) — nothing was saved'; end if;
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
comment on function public.qbo_job_retry(uuid, text) is 'qbo-sync-2a · [2d1 skipped]: 다시 보내기(열쇠 qbo) — failed · unknown · skipped → queued · request_id 새로(같은 requestid 는 처음 응답을 되돌려 준다) · unknown · skipped 는 note 필수 · skipped 는 문서가 issued(void 는 cancelled)이고 같은 열쇠의 열린 일감이 없을 때만 · blocked_by 비움 · last_error 는 남긴다';

-- ═══ E) grant — 새 함수 명시(10-30 부터 자동 grant 없음) · retry 는 create or replace 라 옛 ACL 그대로 ═══
revoke all on function public.qbo_job_claim(int, text[], uuid[]), public.qbo_job_doc(text, text), public.qbo_job_preview(uuid), public.qbo_job_list(text, text[], date, date, text, int, int) from public, anon, authenticated, service_role;
grant execute on function public.qbo_job_claim(int, text[], uuid[]) to service_role;
grant execute on function public.qbo_job_preview(uuid), public.qbo_job_list(text, text[], date, date, text, int, int) to authenticated;

-- ═══ 착지 검사 ═══
do $$
declare v text;
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_job_claim', 'qbo_job_doc', 'qbo_job_preview', 'qbo_job_list', 'qbo_job_retry');
  if v <> 'qbo_job_claim(p_limit integer, p_kinds text[], p_job_ids uuid[])={postgres=X/postgres,service_role=X/postgres} qbo_job_doc(p_ims_kind text, p_ims_id text)={postgres=X/postgres} '
          || 'qbo_job_list(p_state text, p_kinds text[], p_from date, p_to date, p_q text, p_limit integer, p_offset integer)={postgres=X/postgres,authenticated=X/postgres} '
          || 'qbo_job_preview(p_job uuid)={postgres=X/postgres,authenticated=X/postgres} qbo_job_retry(p_job uuid, p_note text)={postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'qbo-sync-2d1 landing: %', v;
  end if;
  raise notice 'qbo-sync-2d1 landing OK — 새 함수 2(doc · preview) · 재발행 3(claim · list · retry)';
end $$;
