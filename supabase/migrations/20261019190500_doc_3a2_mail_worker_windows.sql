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

-- ═══ doc-3a2 — 문서 메일 ⑦b: 3b 일꾼(EF · service 길)의 DB 창구 셋 (2026-10-19 · doc-3a 에서 떼어 냄 — 3a 가 900 행을 넘겨서 · 판정 529 · 530 · doc-0 Q4) ═══
--   앞 차수: doc-3a(20261019184432 — mail_outbox.attachments · 상태 waiting_pdf · kind doc_* · doc_mail_send · 자동 트리거 · doc_mail_list · doc_mail_cancel) 가 먼저 적용되어 있어야 한다(아래 문지기)
--   창구 셋 = doc_mail_pdf_claim(집기) · doc_mail_attach(PDF 붙이기 → queued · 메일 기계가 이어받는다) · doc_mail_pdf_failed(세 번까지 10 분 뒤 다시 · 세 번째는 failed)
--   mail_outbox_event 의 action 어휘 + pdf_attached · pdf_failed(둘 다 사람 없이 · staff_ck 무접촉)
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace)
     or (select pg_get_constraintdef(oid) from pg_constraint where conname = 'mail_outbox_status_ck') !~ 'waiting_pdf' then
    raise exception using errcode = 'IM511', message = 'STOP - doc-3a (20261019184432) must be applied before doc-3a2 - nothing was changed';
  end if;
end $$;

-- ═══ ⑦b 3b 일꾼(EF · service 길)의 창구 셋 — PDF 기다리는 줄 집기 · PDF 붙이기 · PDF 실패 적기 (doc_is_service · 직원은 못 부른다) ═══
--   mail_outbox_event 의 action 어휘에 pdf_attached · pdf_failed 둘을 더한다(mail-2a 의 목록 그대로 + 둘 · staff_ck 는 무접촉 — 둘 다 사람 없이)
alter table public.mail_outbox_event drop constraint mail_outbox_event_action_ck;
alter table public.mail_outbox_event add constraint mail_outbox_event_action_ck check (action in ('claim', 'stale', 'mark_sent', 'mark_failed', 'mark_unknown', 'mark_retry', 'close_sent', 'retry', 'cancel', 'pdf_attached', 'pdf_failed'));

-- PDF 기다리는 줄을 집는다(오래된 것부터 · next_attempt_at 지난 것 · 10 분 안에 집힌 줄은 건너뛴다 · for update skip locked) — 상태는 그대로 waiting_pdf · claimed_at 만 찍는다
create function public.doc_mail_pdf_claim(p_limit integer default 5) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_rows jsonb;
begin
  if not public.doc_is_service() then raise exception 'doc_mail_pdf_claim is for the mail worker only — nothing was read'; end if;
  with pick as (
    select o.id from public.mail_outbox o
     where o.status = 'waiting_pdf' and o.kind like 'doc\_%'
       and coalesce(o.next_attempt_at, '-infinity') <= now()
       and (o.claimed_at is null or o.claimed_at < now() - interval '10 minutes')
     order by o.created_at, o.id
     limit greatest(1, least(coalesce(p_limit, 5), 20))
     for update skip locked),
  upd as (update public.mail_outbox o set claimed_at = now() from pick where o.id = pick.id
          returning o.id, o.payload, o.attempts, o.to_address, o.subject, o.created_at)
  select coalesce(jsonb_agg(jsonb_build_object('outbox_id', u.id, 'doc_kind', u.payload->>'doc_kind', 'ref', u.payload->'ref', 'attempts', u.attempts, 'to', u.to_address, 'subject', u.subject, 'created_at', u.created_at) order by u.created_at, u.id), '[]'::jsonb)
    into v_rows from upd u;
  return v_rows;
end;
$$;
revoke all on function public.doc_mail_pdf_claim(integer) from public, anon, authenticated;
grant execute on function public.doc_mail_pdf_claim(integer) to service_role;
comment on function public.doc_mail_pdf_claim(integer) is 'doc-3a ⑦b — 3b 일꾼: PDF 기다리는 문서 메일을 집는다(waiting_pdf · 오래된 것부터 · claimed_at 10 분 · 최대 20) → [{outbox_id, doc_kind, ref, attempts, to, subject, created_at}]';

-- PDF 를 붙인다 — waiting_pdf → queued(메일 기계 mail_claim 이 이제 집는다 · next_attempt_at = now) · 첨부 꼴은 doc_mail_enqueue 와 같다 · 같은 kind 의 PDF 만
create function public.doc_mail_attach(p_outbox_id uuid, p_doc_file_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_o public.mail_outbox%rowtype; v_f public.doc_file%rowtype; v_att jsonb;
begin
  if not public.doc_is_service() then raise exception 'doc_mail_attach is for the mail worker only — nothing was saved'; end if;
  select * into v_o from public.mail_outbox o where o.id = p_outbox_id for update;
  if v_o.id is null then raise exception 'Mail not found — nothing was saved'; end if;
  if v_o.status <> 'waiting_pdf' then raise exception 'Only a mail still waiting for its PDF can get one (this one is %) — nothing was saved', v_o.status; end if;
  select * into v_f from public.doc_file f where f.id = p_doc_file_id;
  if v_f.id is null then raise exception 'Stored PDF not found — nothing was saved'; end if;
  if 'doc_' || v_f.kind <> v_o.kind then raise exception 'That PDF is a % document, not % — nothing was saved', v_f.kind, v_o.payload->>'doc_kind'; end if;
  v_att := jsonb_build_array(jsonb_build_object('doc_file_id', v_f.id, 'path', v_f.path, 'filename', regexp_replace(v_f.path, '^.*/', ''), 'bytes', v_f.bytes, 'sha256', v_f.sha256));
  update public.mail_outbox set attachments = v_att, payload = payload || jsonb_build_object('doc_file_id', v_f.id), status = 'queued', claimed_at = null, next_attempt_at = now(), last_error = null where id = v_o.id;
  insert into public.mail_outbox_event (outbox_id, action, from_status, to_status, attempts, staff_id, note) values (v_o.id, 'pdf_attached', 'waiting_pdf', 'queued', v_o.attempts, null, v_f.path);
  return jsonb_build_object('outbox_id', v_o.id, 'status', 'queued', 'attachments', v_att);
end;
$$;
revoke all on function public.doc_mail_attach(uuid, uuid) from public, anon, authenticated;
grant execute on function public.doc_mail_attach(uuid, uuid) to service_role;
comment on function public.doc_mail_attach(uuid, uuid) is 'doc-3a ⑦b — 3b 일꾼: 만든 PDF(doc_file)를 문서 메일에 붙인다(waiting_pdf → queued · attachments [{doc_file_id, path, filename, bytes, sha256}] · payload.doc_file_id · event pdf_attached)';

-- PDF 를 못 만들었다 — 세 번까지 10 분 뒤 다시(waiting_pdf 그대로 · attempts + 1 · last_error) · 세 번째는 failed(사람이 doc_mail_list 에서 본다 · 저절로 다시 안 한다)
create function public.doc_mail_pdf_failed(p_outbox_id uuid, p_error text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_o public.mail_outbox%rowtype; v_n integer; v_err text := left(coalesce(nullif(btrim(p_error), ''), 'PDF could not be made'), 500); v_to text;
begin
  if not public.doc_is_service() then raise exception 'doc_mail_pdf_failed is for the mail worker only — nothing was saved'; end if;
  select * into v_o from public.mail_outbox o where o.id = p_outbox_id for update;
  if v_o.id is null then raise exception 'Mail not found — nothing was saved'; end if;
  if v_o.status <> 'waiting_pdf' then raise exception 'Only a mail still waiting for its PDF can fail there (this one is %) — nothing was saved', v_o.status; end if;
  v_n := v_o.attempts + 1;
  v_to := case when v_n >= 3 then 'failed' else 'waiting_pdf' end;
  update public.mail_outbox set attempts = v_n, last_error = v_err, status = v_to, claimed_at = null, next_attempt_at = case when v_to = 'waiting_pdf' then now() + interval '10 minutes' end where id = v_o.id;
  insert into public.mail_outbox_event (outbox_id, action, from_status, to_status, attempts, staff_id, note) values (v_o.id, 'pdf_failed', 'waiting_pdf', v_to, v_n, null, v_err);
  return jsonb_build_object('outbox_id', v_o.id, 'status', v_to, 'attempts', v_n, 'last_error', v_err);
end;
$$;
revoke all on function public.doc_mail_pdf_failed(uuid, text) from public, anon, authenticated;
grant execute on function public.doc_mail_pdf_failed(uuid, text) to service_role;
comment on function public.doc_mail_pdf_failed(uuid, text) is 'doc-3a ⑦b — 3b 일꾼: PDF 만들기 실패(attempts + 1 · last_error · 10 분 뒤 다시 · 세 번째는 failed · event pdf_failed)';

-- ═══ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'mail_outbox_event_action_ck') !~ 'pdf_attached' then v_bad := v_bad || ' event-ck'; end if;
  if has_function_privilege('authenticated', 'public.doc_mail_pdf_claim(integer)', 'execute') or has_function_privilege('authenticated', 'public.doc_mail_attach(uuid, uuid)', 'execute') or has_function_privilege('authenticated', 'public.doc_mail_pdf_failed(uuid, text)', 'execute')
     or not has_function_privilege('service_role', 'public.doc_mail_attach(uuid, uuid)', 'execute') then v_bad := v_bad || ' worker-acl'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('doc_mail_pdf_claim', 'doc_mail_attach', 'doc_mail_pdf_failed')) <> 3 then v_bad := v_bad || ' fns'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - doc-3a2 did not land as designed:%s - nothing was changed', v_bad); end if;
end $$;
