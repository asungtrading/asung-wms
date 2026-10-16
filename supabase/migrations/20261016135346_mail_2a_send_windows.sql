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
-- 20261016135346_mail_2a_send_windows.sql — mail-2a (2026-10-16 · 회사 PC · Fable · mail-1c 5e782fa 위에) · 이 차수도 보내지 않는다 — 보내는 EF(mail-2b)가 부를 창구와 직원이 누를 창구
--   판정 497 · 505 · 502 · 510 · 511 · 514(Caleb 「1」 — unknown 은 자동으로 손대지 않는다 · 직원이 보냄으로 닫기 · 다시 보내기 · 취소) · mail-2a §0 이견 1 ~ 9(보고에)
--   ① mail_outbox_event — 메일 한 통의 상태가 바뀔 때마다 한 행(EF · 시스템 · 직원 · 누가 · 언제 · 메모 · 이견 6)
--      mail_run.chat_attempts — Chat 요약 실패 횟수(다섯 번까지 다시 · 이견 7)
--   ② EF 창구(service_role 만 — shopify EF 선례: SUPABASE_SERVICE_ROLE_KEY 로 rest/v1/rpc · shop_order_ingest 등 {postgres, service_role}):
--      mail_claim(p_limit) — 멈춘 sending(10 분)은 unknown(514 · 꺼져 있어도 · 이견 2) · mail_enabled on 이면 queued 를 skip locked 로 sending · 판단 재료 {enabled, redirect_to, db_role}
--      mail_mark(p_id, p_attempt, p_result, …) — sending 이고 시도 번호가 맞을 때만(늦게 온 결과 · 다른 EF 의 결과 막기 · 이견 3) · 멈춤으로 unknown 이 된 같은 시도의 sent · failed 는 받는다
--        sent(보낸 것 기록) · failed(줄 표지 풀림) · unknown(표지 그대로) · retry(5 · 15 · 60 · 60 분 · 다섯 번째 시도면 failed · 이견 4)
--      mail_run_chat_due() · mail_run_chat_mark(p_run_id, p_ok, p_error) — 메일이 다 끝난 회차(0 통 회차 포함 — tick 은 손님 0 이어도 회차를 만든다)
--   ③ 직원 창구(판정 514 · 지금은 admin 만 — 누가 누를 수 있나는 mail-4 에서 Caleb 판정 뒤 넓힌다 · 메모 필수 · 이견 8):
--      mail_outbox_close_sent(unknown → sent · sent_at = 그 시도의 claimed_at) · mail_outbox_retry(unknown → queued · 시도 수 0 으로 · 이견 5) · mail_outbox_cancel(queued | unknown → cancelled · 표지 그대로)
--   무접촉: 앞 차수 함수 전부(tick 재발행 없음) · 템플릿 · Gmail · Chat 호출(mail-2b) · cron(mail-3) · 화면(mail-4)
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/mail-2a-verify.sql

-- ═══ ① 이력 표 · Chat 시도 칸 ═══
create table public.mail_outbox_event (
  id          bigint generated always as identity primary key,
  outbox_id   uuid not null references public.mail_outbox(id),
  at          timestamptz not null default now(),
  action      text not null,
  from_status text not null,
  to_status   text not null,
  attempts    int,
  staff_id    uuid references public.ims_staff(id),
  note        text,
  constraint mail_outbox_event_action_ck check (action in ('claim', 'stale', 'mark_sent', 'mark_failed', 'mark_unknown', 'mark_retry', 'close_sent', 'retry', 'cancel')),
  constraint mail_outbox_event_staff_ck  check ((action in ('close_sent', 'retry', 'cancel')) = (staff_id is not null))
);
create index mail_outbox_event_outbox_idx on public.mail_outbox_event (outbox_id, at);
comment on table public.mail_outbox_event is 'mail-2a 이견 6 — 메일 한 통의 상태가 바뀔 때마다 한 행: claim(EF 가 집음) · stale(멈춘 sending → unknown) · mark_*(EF 결과) · close_sent · retry · cancel(직원 · 판정 514 · staff_id · note 필수). 직원 처리의 누가 · 언제 · 메모는 여기에 · 쓰기는 창구만';
alter table public.mail_outbox_event enable row level security;
revoke all on public.mail_outbox_event from anon, authenticated;

alter table public.mail_run add column chat_attempts int not null default 0;
alter table public.mail_run add constraint mail_run_chat_attempts_ck check (chat_attempts >= 0);
comment on column public.mail_run.chat_attempts is 'mail-2a 이견 7 — Chat 요약을 올리다 실패한 횟수 · 다섯 번이면 mail_run_chat_due 가 더 내지 않는다(chat_error 에 마지막 까닭)';

-- ═══ ② EF 창구(service_role 만) ═══
create function public.mail_claim(p_limit int default 10) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_limit   int := least(greatest(coalesce(p_limit, 10), 1), 50);
  v_enabled boolean := coalesce((select c.value from public.inv_config c where c.key = 'mail_enabled'), 'off') = 'on';
  v_stale   int;
  v_mails   jsonb;
begin
  -- 멈춘 sending — EF 가 도중에 죽었다 · 요청이 Gmail 에 갔는지 모른다 → unknown(판정 514 · 자동 재전송 금지) · 꺼져 있어도 한다(이견 2)
  with s as (
    update public.mail_outbox o
       set status = 'unknown',
           last_error = left(coalesce(o.last_error || ' · ', '') || format('stale: still sending %s after claim (attempt %s) — the request may or may not have reached Gmail', date_trunc('second', now() - o.claimed_at), o.attempts), 2000)
     where o.status = 'sending' and o.claimed_at < now() - interval '10 minutes'
    returning o.id, o.attempts
  )
  insert into public.mail_outbox_event (outbox_id, action, from_status, to_status, attempts, note)
  select s.id, 'stale', 'sending', 'unknown', s.attempts, 'sending for over 10 minutes' from s;
  get diagnostics v_stale = row_count;

  if not v_enabled then
    return jsonb_build_object('enabled', false, 'redirect_to', nullif((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), ''),
                              'db_role', (select c.value from public.inv_config c where c.key = 'db_role'), 'recovered_unknown', v_stale, 'mails', '[]'::jsonb);
  end if;

  with c as (
    select o.id from public.mail_outbox o
    where o.status = 'queued' and coalesce(o.next_attempt_at, '-infinity') <= now()
    order by o.next_attempt_at nulls first, o.created_at, o.id
    limit v_limit
    for update skip locked
  ),
  u as (
    update public.mail_outbox o set status = 'sending', claimed_at = now(), attempts = o.attempts + 1
    from c where o.id = c.id
    returning o.*
  ),
  e as (
    insert into public.mail_outbox_event (outbox_id, action, from_status, to_status, attempts)
    select u.id, 'claim', 'queued', 'sending', u.attempts from u
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'kind', u.kind, 'category', u.category, 'from_address', u.from_address, 'from_name', u.from_name, 'reply_to', u.reply_to,
                                               'to_address', u.to_address, 'subject', u.subject, 'payload', u.payload, 'attempt', u.attempts, 'claimed_at', u.claimed_at,
                                               'customer_id', u.customer_id, 'location_id', u.location_id, 'run_id', u.run_id) order by u.next_attempt_at nulls first, u.created_at, u.id), '[]'::jsonb)
    into v_mails from u;

  return jsonb_build_object('enabled', true, 'redirect_to', nullif((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), ''),
                            'db_role', (select c.value from public.inv_config c where c.key = 'db_role'), 'recovered_unknown', v_stale, 'mails', v_mails);
end;
$$;
comment on function public.mail_claim(int) is 'mail-2a — 보내는 EF(mail-2b)가 부른다(service_role 만). ① 10 분 넘게 sending 인 메일은 unknown(판정 514 — 요청이 갔는지 모른다 · 자동 재전송 안 함 · 꺼져 있어도) ② mail_enabled on 이면 queued 이고 next_attempt_at ≤ now() 인 메일을 오래된 것부터 p_limit(1 ~ 50)통 for update skip locked 로 sending · claimed_at · attempts + 1 ③ 반환 {enabled, redirect_to(비면 null), db_role, recovered_unknown, mails[{id, kind, category, from_address, from_name, reply_to, to_address, subject, payload, attempt, claimed_at, customer_id, location_id, run_id}]} — 돌려 보내기 · 켜짐 판단은 EF 가 보내기 직전에';
revoke all on function public.mail_claim(int) from public, anon, authenticated;
grant execute on function public.mail_claim(int) to service_role;

create function public.mail_mark(p_id uuid, p_attempt int, p_result text, p_provider_message_id text default null, p_error text default null, p_rendered jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_o        public.mail_outbox%rowtype;
  v_r        jsonb := coalesce(p_rendered, '{}'::jsonb);
  v_status   text;
  v_action   text;
  v_released int := 0;
  v_late     boolean;
  c_max      constant int := 5;                                                                    -- 이견 4: 다섯 번째 시도의 retry 는 failed
begin
  if p_result is null or p_result not in ('sent', 'failed', 'unknown', 'retry') then
    raise exception 'mail_mark result must be sent, failed, unknown or retry (got %) — nothing was saved', coalesce(p_result, 'null');
  end if;
  select * into v_o from public.mail_outbox o where o.id = p_id for update;
  if not found then
    raise exception 'Mail % not found — nothing was saved', p_id;
  end if;
  -- 이견 3: 이 시도의 결과만 받는다 — sending 이고 시도 번호가 같을 때 · 멈춤으로 unknown 이 된 같은 시도(직원 손 전)의 sent · failed 는 늦게 와도 받는다(진짜 결과가 짐작보다 낫다)
  v_late := v_o.status = 'unknown' and p_result in ('sent', 'failed')
            and (select ev.action from public.mail_outbox_event ev where ev.outbox_id = p_id order by ev.at desc, ev.id desc limit 1) = 'stale';
  if v_o.attempts is distinct from p_attempt or not (v_o.status = 'sending' or v_late) then
    raise exception 'Mail % is % at attempt % — a % result for attempt % is not applied (late or duplicate) — nothing was saved', p_id, v_o.status, v_o.attempts, p_result, coalesce(p_attempt::text, 'null');
  end if;

  if p_result = 'retry' and v_o.attempts >= c_max then
    v_status := 'failed';
    v_action := 'mark_retry';
  else
    v_status := case p_result when 'retry' then 'queued' else p_result end;
    v_action := 'mark_' || p_result;
  end if;

  if v_status = 'sent' then
    update public.mail_outbox
       set status = 'sent', sent_at = now(), provider_message_id = p_provider_message_id,
           subject = coalesce(v_r->>'subject', subject), body_text = coalesce(v_r->>'body_text', body_text), body_html = coalesce(v_r->>'body_html', body_html),
           to_address = coalesce(v_r->>'to_address', to_address), original_to = coalesce(v_r->>'original_to', original_to)
     where id = p_id;
  elsif v_status = 'queued' then
    update public.mail_outbox
       set status = 'queued', last_error = left(coalesce(p_error, 'retry'), 2000),
           next_attempt_at = now() + case v_o.attempts when 1 then interval '5 minutes' when 2 then interval '15 minutes' else interval '60 minutes' end
     where id = p_id;
  else                                                                                              -- failed · unknown
    update public.mail_outbox
       set status = v_status,
           last_error = left(coalesce(p_error, v_status) || case when p_result = 'retry' then format(' · gave up after %s attempts', v_o.attempts) else '' end, 2000)
     where id = p_id;
    if v_status = 'failed' then                                                                     -- 줄 표지를 풀어 다음 회차에 다시 실린다
      update public.mail_backorder_line set released_at = now() where outbox_id = p_id and released_at is null;
      get diagnostics v_released = row_count;
    end if;
  end if;
  insert into public.mail_outbox_event (outbox_id, action, from_status, to_status, attempts, note)
  values (p_id, v_action, v_o.status, v_status, v_o.attempts, left(coalesce(p_error, p_provider_message_id), 2000));
  return jsonb_build_object('id', p_id, 'status', v_status, 'released_lines', v_released, 'late', v_late);
end;
$$;
comment on function public.mail_mark(uuid, int, text, text, text, jsonb) is 'mail-2a — 보내는 EF 가 시도 하나의 결과를 적는다(service_role 만). p_attempt = mail_claim 이 준 attempt(같아야 적는다 — 늦은 결과 · 두 번 적기 · 다른 EF 의 결과를 막는다). sent: sent_at · provider_message_id · p_rendered{subject, body_text, body_html, to_address, original_to}(돌려 보냈으면 to_address = 돌려 보낸 주소 · original_to = 손님) · failed: last_error · 그 메일의 mail_backorder_line 을 풀어 다음 회차에 다시 · unknown: last_error · 표지 그대로(판정 514) · retry(5xx · 429): queued · 5 · 15 · 60 · 60 분 뒤 · 다섯 번째 시도면 failed. 멈춤으로 unknown 이 된 같은 시도의 sent · failed 는 직원이 손대기 전이면 받는다';
revoke all on function public.mail_mark(uuid, int, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.mail_mark(uuid, int, text, text, text, jsonb) to service_role;

create function public.mail_run_chat_due() returns jsonb
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'run_id', r.id, 'kind', r.kind, 'location_id', r.location_id, 'location_name', w.name, 'run_on', r.run_on, 'started_at', r.started_at,
           'mails', r.mails, 'lines', r.lines, 'chat_attempts', r.chat_attempts, 'chat_error', r.chat_error,
           'by_status', coalesce((select jsonb_object_agg(x.status, x.n) from (select o.status, count(*) as n from public.mail_outbox o where o.run_id = r.id group by o.status) x), '{}'::jsonb),
           'skipped', coalesce((select jsonb_object_agg(x.reason, x.n) from (select e->>'reason' as reason, count(*) as n from jsonb_array_elements(r.no_email) e group by 1) x), '{}'::jsonb))
         order by r.started_at, r.id), '[]'::jsonb)
  from (select * from public.mail_run rr
        where rr.chat_posted_at is null and rr.chat_attempts < 5
          and not exists (select 1 from public.mail_outbox o where o.run_id = rr.id and o.status in ('queued', 'sending'))
        order by rr.started_at, rr.id limit 20) r
  join public.ref_warehouse w on w.id = r.location_id;
$$;
comment on function public.mail_run_chat_due() is 'mail-2a 판정 502 — Chat 요약을 올릴 회차(service_role 만): 그 회차 메일에 queued · sending 이 없고(전부 끝남 · 0 통 회차 포함) chat_posted_at 이 비었고 chat_attempts < 5 · 오래된 것부터 20 · 회차마다 {run_id, kind, location_id, location_name, run_on, started_at, mails, lines, chat_attempts, chat_error, by_status{상태: 수}, skipped{reason: 수}}';
revoke all on function public.mail_run_chat_due() from public, anon, authenticated;
grant execute on function public.mail_run_chat_due() to service_role;

create function public.mail_run_chat_mark(p_run_id uuid, p_ok boolean, p_error text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_r public.mail_run%rowtype;
begin
  select * into v_r from public.mail_run r where r.id = p_run_id for update;
  if not found then
    raise exception 'Mail run % not found — nothing was saved', p_run_id;
  end if;
  if v_r.chat_posted_at is not null then
    raise exception 'Mail run % already has its Chat summary (%) — nothing was saved', p_run_id, v_r.chat_posted_at;
  end if;
  if coalesce(p_ok, false) then
    update public.mail_run set chat_posted_at = now(), chat_error = null where id = p_run_id;
  else
    update public.mail_run set chat_attempts = chat_attempts + 1, chat_error = left(coalesce(p_error, 'chat post failed'), 2000) where id = p_run_id;
  end if;
  return (select jsonb_build_object('run_id', r.id, 'chat_posted_at', r.chat_posted_at, 'chat_attempts', r.chat_attempts, 'chat_error', r.chat_error) from public.mail_run r where r.id = p_run_id);
end;
$$;
comment on function public.mail_run_chat_mark(uuid, boolean, text) is 'mail-2a 판정 502 — EF 가 Chat 요약 결과를 적는다(service_role 만): 성공이면 chat_posted_at · 실패면 chat_attempts + 1 · chat_error(다섯 번이면 더 안 나온다) · 이미 올린 회차는 거부';
revoke all on function public.mail_run_chat_mark(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.mail_run_chat_mark(uuid, boolean, text) to service_role;

-- ═══ ③ 직원 창구(판정 514 · admin 만 · 메모 필수) ═══
create function public.mail_outbox_resolve(p_id uuid, p_action text, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_o     public.mail_outbox%rowtype;
  v_staff uuid;
  v_to    text;
begin
  perform public.ims_require_admin('a backorder mail that may not have gone out');                -- 판정 514 · 지금은 admin 만(mail-4 에서 넓힌다)
  v_staff := (select s.id from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active);
  if nullif(btrim(coalesce(p_note, '')), '') is null then
    raise exception 'Say what you checked (a note is required) — nothing was saved';
  end if;
  select * into v_o from public.mail_outbox o where o.id = p_id for update;
  if not found then
    raise exception 'Mail % not found — nothing was saved', p_id;
  end if;
  if p_action = 'close_sent' then
    if v_o.status <> 'unknown' then raise exception 'Only a mail whose result is unknown can be closed as sent (this one is %) — nothing was saved', v_o.status; end if;
    v_to := 'sent';
    update public.mail_outbox set status = 'sent', sent_at = coalesce(v_o.claimed_at, now()) where id = p_id;
  elsif p_action = 'retry' then
    if v_o.status <> 'unknown' then raise exception 'Only a mail whose result is unknown can be sent again (this one is %) — a failed mail goes again with the next run by itself — nothing was saved', v_o.status; end if;
    v_to := 'queued';
    update public.mail_outbox set status = 'queued', next_attempt_at = now(), attempts = 0 where id = p_id;
  elsif p_action = 'cancel' then
    if v_o.status not in ('queued', 'unknown') then raise exception 'Only a queued mail or one whose result is unknown can be cancelled (this one is %) — nothing was saved', v_o.status; end if;
    v_to := 'cancelled';
    update public.mail_outbox set status = 'cancelled' where id = p_id;                            -- 줄 표지는 그대로 — 다음 회차에 다시 안 실린다(1c 상태 cancelled)
  else
    raise exception 'Unknown action % — nothing was saved', coalesce(p_action, 'null');
  end if;
  insert into public.mail_outbox_event (outbox_id, action, from_status, to_status, attempts, staff_id, note)
  values (p_id, p_action, v_o.status, v_to, v_o.attempts, v_staff, btrim(p_note));
  return jsonb_build_object('id', p_id, 'status', v_to);
end;
$$;
comment on function public.mail_outbox_resolve(uuid, text, text) is 'mail-2a 판정 514 속 — 직원 처리 셋의 한 몸(admin 만 · 메모 필수 · mail_outbox_event 에 누가 · 언제 · 메모). 바깥 창구 셋이 부른다';
revoke all on function public.mail_outbox_resolve(uuid, text, text) from public, anon, authenticated, service_role;

create function public.mail_outbox_close_sent(p_id uuid, p_note text) returns jsonb
  language sql volatile security definer set search_path = public, pg_temp
as $$ select public.mail_outbox_resolve(p_id, 'close_sent', p_note); $$;
create function public.mail_outbox_retry(p_id uuid, p_note text) returns jsonb
  language sql volatile security definer set search_path = public, pg_temp
as $$ select public.mail_outbox_resolve(p_id, 'retry', p_note); $$;
create function public.mail_outbox_cancel(p_id uuid, p_note text) returns jsonb
  language sql volatile security definer set search_path = public, pg_temp
as $$ select public.mail_outbox_resolve(p_id, 'cancel', p_note); $$;
comment on function public.mail_outbox_close_sent(uuid, text) is 'mail-2a 판정 514 — 「보냈는지 모르는 메일」(unknown)을 보낸편지함에서 확인하고 보냄으로 닫는다: sent · sent_at = 그 시도의 claimed_at · 줄 표지 그대로(그 줄 알림 끝) · ⚠️ 지금은 admin 만 — 누가 누를 수 있나는 mail-4 에서 Caleb 판정 뒤 넓힌다 · 메모 필수';
comment on function public.mail_outbox_retry(uuid, text) is 'mail-2a 판정 514 — unknown 메일이 안 나간 것을 확인하고 같은 메일을 다시 큐에: queued · next_attempt_at = now() · 시도 수 0 · 줄 표지 그대로 · failed 는 안 된다(표지가 이미 풀려 다음 회차가 다시 싣는다) · ⚠️ 지금은 admin 만(mail-4 에서 넓힌다) · 메모 필수';
comment on function public.mail_outbox_cancel(uuid, text) is 'mail-2a 판정 514 — queued · unknown 메일을 취소(손님과 직접 연락함 등): cancelled · 줄 표지 그대로(그 줄 알림 끝 · 다음 회차에 다시 안 실림 · 상태 cancelled) · ⚠️ 지금은 admin 만(mail-4 에서 넓힌다) · 메모 필수';
revoke all on function public.mail_outbox_close_sent(uuid, text) from public, anon, service_role;
revoke all on function public.mail_outbox_retry(uuid, text) from public, anon, service_role;
revoke all on function public.mail_outbox_cancel(uuid, text) from public, anon, service_role;
grant execute on function public.mail_outbox_close_sent(uuid, text) to authenticated;
grant execute on function public.mail_outbox_retry(uuid, text) to authenticated;
grant execute on function public.mail_outbox_cancel(uuid, text) to authenticated;

-- ═══ ④ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if to_regclass('public.mail_outbox_event') is null or not (select relrowsecurity from pg_class where oid = 'public.mail_outbox_event'::regclass) then v_bad := v_bad || ' event-table'; end if;
  if exists (select 1 from information_schema.role_table_grants where table_schema = 'public' and table_name = 'mail_outbox_event' and grantee in ('anon', 'authenticated')) then v_bad := v_bad || ' event-grants'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'mail_run' and column_name = 'chat_attempts') then v_bad := v_bad || ' chat_attempts'; end if;
  if has_function_privilege('authenticated', 'public.mail_claim(int)', 'execute') or not has_function_privilege('service_role', 'public.mail_claim(int)', 'execute')
     or has_function_privilege('authenticated', 'public.mail_mark(uuid, int, text, text, text, jsonb)', 'execute') or not has_function_privilege('service_role', 'public.mail_mark(uuid, int, text, text, text, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.mail_run_chat_due()', 'execute') or has_function_privilege('authenticated', 'public.mail_run_chat_mark(uuid, boolean, text)', 'execute')
     or has_function_privilege('anon', 'public.mail_outbox_cancel(uuid, text)', 'execute') or not has_function_privilege('authenticated', 'public.mail_outbox_cancel(uuid, text)', 'execute')
     or has_function_privilege('authenticated', 'public.mail_outbox_resolve(uuid, text, text)', 'execute') or has_function_privilege('service_role', 'public.mail_outbox_cancel(uuid, text)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM515', message = format('STOP - mail-2a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
