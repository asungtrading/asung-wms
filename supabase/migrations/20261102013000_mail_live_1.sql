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
-- mail-live-1 — 운영 DB 인데 「test」 표지 때문에 손님 메일이 Caleb 에게 돌아가는 문제 — mail_live 운영 선언 (2026-11-01 밤 · 판정 617 · 947 · 지시서 ~/asung/prompts/mail-live-1.md · EF mail(_shared/mail.ts · index.ts · mail_test.ts) 같은 커밋 · 재배포 필요)
--   왜: 이 DB(Asung-IMS · fazgmyvzzhqybtvtktyg)는 617 로 11-01 부터 운영인데 inv_config.db_role = 'test' 는 그대로다(cutdel-1 이견 3 — 「IMS 프로젝트」 표지 · 마이그레이션 가드 215 + EF 가드 셋(freightcom · shopify · ims-product-images)이 본다 · 바꾸면 전부 멈춘다).
--       메일만 그 표지를 「시험」 으로 읽어 ims_mail_config_problem 이 돌려 보내기 없는 켜짐을 거부하고, EF mail 의 safety() 가 TEST_REF 를 시험으로 박아 @asung.ca 돌려 보내기를 강제했다(mail-1a 이견 1 · 11).
--       ⇒ 새 키 mail_live(on | off · 처음 off · admin) 하나 — 「손님 메일의 운영은 이 키가 선언한다」. db_role · guard-test-only · Freightcom · Shopify · 이미지 EF 무접촉((가) 표지 값 바꾸기는 deferred).
--   ① ims_mail_config_keys 재발행(마지막 정의 20261019184432 · prosrc md5 875d9603912c17acf3d43bb20546a5e5) — 11 키(mail_live 셋째) · guard 의 이름 바꾸기 거부 · 메일 갈래가 자동으로 읽는다
--   ② ims_mail_config_problem 재발행(마지막 정의 20261019184432 · md5 9e53418fd7ca5f3811e83a999eba451c) — v_test = 표지 test 이고 mail_live 아님 · mail_live 값 on | off · off 로 돌릴 때 · 지울 때(표지 test · mail_enabled on)는 @asung.ca 돌려 보낼 곳이 있어야 한다
--   ③ doc_mail_send 재발행(마지막 정의 20261019184432 · md5 98f93aaa243f111befdad7eeb9a0eb1e) — 미리 보기의 redirect_to 는 db_role 과 무관하게 「돌려 보낼 주소가 있으면 그 주소」(EF addressFor 와 같은 뜻 · 운영 [REDIRECT →] 도 손님에게 안 간다)
--   ④ mail_claim 재발행(마지막 정의 20261016135346 · md5 ba20e9f3a8a797a75f256b1da50b81fe) — 반환에 mail_live boolean(EF safety 의 재료)
--   ⑤ mail_settings 재발행(마지막 정의 20261016152757 · md5 c6addae465058b460b4074557188a3be) — mail_live 의 edit_level · can_edit = admin
--   ⑥ ims_config_set 재발행(마지막 정의 20261028162209 · md5 1ae6db956ec8962064bb4fece08a552f) — admin 갈래에 mail_live(REST 로 불린다 · 화면 줄은 settings.html 에 대화 Claude 가)
--   ⑦ inv_config mail_live = off 시드(note 에 표지와 선언의 뜻) ⑧ 착지 확인
--   ⚠️ inv_config_guard 는 안 바꾼다 — 지키는 키 · 메일 갈래는 ims_mail_config_keys() 로 읽고, 「화면에서 admin」 가지(authenticated 직접 update)는 rls-2 뒤 닿지 않는다(authenticated 에 UPDATE grant 없음 · 창구는 definer = postgres)
--   ⚠️ 적용은 Caleb: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261102013000_mail_live_1.sql && supabase migration repair --status applied 20261102013000 · 그 뒤 supabase functions deploy mail --project-ref fazgmyvzzhqybtvtktyg · db push 금지
--   시험: supabase/tests/mail_live_1_check.sql(begin → \i → A ~ E 갈래 → rollback)


-- ═══ 1) ims_mail_config_keys — 11 키(mail_live 셋째) ═══
CREATE OR REPLACE FUNCTION public.ims_mail_config_keys()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select array['mail_enabled', 'mail_redirect_to', 'mail_live', 'mail_backorder_from', 'mail_backorder_reply_to', 'mail_backorder_from_name', 'mail_backorder_schedule', 'mail_backorder_min_fill_pct', 'mail_doc_from', 'mail_doc_from_name', 'mail_doc_reply_to'];   -- doc-3a 판정 530: 문서 메일 보내는 주소 셋 · mail-live-1 판정 947: mail_live(손님 메일 운영 선언 · admin)
$function$;
comment on function public.ims_mail_config_keys() is 'mail-1a — inv_config 의 메일 키(inv_config_guard 의 메일 갈래 · 이름 바꾸기 거부가 읽는다). admin 키 = mail_enabled · mail_redirect_to · mail_live(mail-live-1 판정 947) · 나머지는 master. ims_config_locked_keys(양의 정수 · supervisor) 와 뜻이 달라 따로 둔다 — 이견 4';

-- ═══ 2) ims_mail_config_problem — v_test = 표지 test 이고 mail_live 아님 · mail_live 값 규칙 ═══
CREATE OR REPLACE FUNCTION public.ims_mail_config_problem(p_key text, p_value text, p_delete boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_live boolean := coalesce((select c.value = 'on' from public.inv_config c where c.key = 'mail_live'), false);   -- mail-live-1 판정 947: 손님 메일의 운영 선언 — 이 DB 의 db_role 'test' 는 IMS 프로젝트 표지(617 · cutdel-1 이견 3)
  v_test boolean := coalesce((select c.value = 'test' from public.inv_config c where c.key = 'db_role'), false) and not v_live;   -- 시험 엮인 규칙(이견 11)은 「표지 test 이고 운영 선언 없음」 일 때만
  v_j    jsonb;
  v_wh   text;
  v_e    jsonb;
begin
  -- 시험 DB 엮인 규칙(이견 11) — 켜진 동안 돌려 보낼 주소를 지우지 못한다
  if p_delete then
    if p_key = 'mail_redirect_to' and v_test and (select c.value from public.inv_config c where c.key = 'mail_enabled') = 'on' then
      return 'cannot be removed while mail_enabled is on in the test database — turn mail_enabled off first';
    end if;
    if p_key = 'mail_live' and (select c.value from public.inv_config c where c.key = 'db_role') = 'test'                                   -- 947: 운영 선언을 지우면 시험 규칙으로 돌아간다 — 그때 돌려 보낼 곳이 있어야 한다
       and (select c.value from public.inv_config c where c.key = 'mail_enabled') = 'on'
       and lower(coalesce((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), '')) !~ '@asung\.ca$' then
      return 'cannot be removed while mail_enabled is on and mail_redirect_to is not an @asung.ca address — set mail_redirect_to or turn mail_enabled off first';
    end if;
    return null;
  end if;
  if p_value is null then
    return 'cannot be empty (null)';
  end if;
  case p_key
  when 'mail_enabled' then
    if p_value not in ('on', 'off') then
      return format('must be on or off (got %s)', p_value);
    end if;
    if p_value = 'on' and v_test and coalesce((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), '') = '' then
      return 'cannot be on in the test database while mail_redirect_to is empty — set mail_redirect_to (an @asung.ca address) first';
    end if;
  when 'mail_redirect_to' then
    if p_value <> '' and not public.ims_mail_address_ok(p_value) then
      return format('must be empty or one email address (got %s)', p_value);
    end if;
    if v_test and p_value = '' and (select c.value from public.inv_config c where c.key = 'mail_enabled') = 'on' then
      return 'cannot be emptied while mail_enabled is on in the test database — turn mail_enabled off first';
    end if;
    if v_test and p_value <> '' and lower(p_value) !~ '@asung\.ca$' then
      return format('must be an @asung.ca address in the test database (got %s)', p_value);
    end if;
  when 'mail_live' then                                                                           -- mail-live-1 판정 947: on · off · off 로 돌릴 때(표지 test · 켜짐)는 @asung.ca 돌려 보낼 곳이 있어야 한다
    if p_value not in ('on', 'off') then
      return format('must be on or off (got %s)', p_value);
    end if;
    if p_value = 'off' and (select c.value from public.inv_config c where c.key = 'db_role') = 'test'
       and (select c.value from public.inv_config c where c.key = 'mail_enabled') = 'on'
       and lower(coalesce((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), '')) !~ '@asung\.ca$' then
      return 'cannot be off while mail_enabled is on and mail_redirect_to is not an @asung.ca address — set mail_redirect_to (an @asung.ca address) or turn mail_enabled off first';
    end if;
  when 'mail_backorder_from' then
    if not public.ims_mail_address_ok(p_value) then
      return format('must be one email address (got %s)', p_value);
    end if;
  when 'mail_backorder_reply_to' then
    if p_value <> '' and not public.ims_mail_address_ok(p_value) then
      return format('must be empty or one email address (got %s)', p_value);
    end if;
  when 'mail_backorder_from_name' then
    if btrim(p_value) = '' then
      return 'must not be empty';
    end if;
  when 'mail_backorder_min_fill_pct' then
    if p_value !~ '^[0-9]{1,3}$' or p_value::int not between 1 and 100 then
      return format('must be a whole number from 1 to 100 (got %s)', p_value);
    end if;
  when 'mail_backorder_schedule' then
    begin
      v_j := p_value::jsonb;
    exception when others then
      return 'must be JSON like {"<warehouse id>": {"tz": "America/Toronto", "days": [1, 4], "hour": 9}}';
    end;
    if jsonb_typeof(v_j) <> 'object' or v_j = '{}'::jsonb then
      return 'must be a JSON object keyed by warehouse id (a warehouse left out gets no mail)';
    end if;
    for v_wh, v_e in select x.key, x.value from jsonb_each(v_j) x loop
      if v_wh !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
         or not exists (select 1 from public.ref_warehouse w where w.id = v_wh::uuid and w.is_active) then
        return format('key %s is not an active warehouse id', v_wh);
      end if;
      if jsonb_typeof(v_e) <> 'object' or not (v_e ? 'tz' and v_e ? 'days' and v_e ? 'hour')
         or exists (select 1 from jsonb_object_keys(v_e) k where k not in ('tz', 'days', 'hour')) then
        return format('warehouse %s needs exactly tz, days, hour', v_wh);
      end if;
      if jsonb_typeof(v_e->'tz') <> 'string' or not exists (select 1 from pg_timezone_names z where z.name = v_e->>'tz') then
        return format('warehouse %s: tz %s is not a known time zone name', v_wh, v_e->'tz');
      end if;
      if jsonb_typeof(v_e->'days') <> 'array' or jsonb_array_length(v_e->'days') = 0
         or exists (select 1 from jsonb_array_elements(v_e->'days') d where jsonb_typeof(d) <> 'number' or d::text !~ '^[1-7]$')
         or (select count(distinct d::text) from jsonb_array_elements(v_e->'days') d) <> jsonb_array_length(v_e->'days') then
        return format('warehouse %s: days must be a non-empty list of different whole numbers 1 (Mon) to 7 (Sun) (got %s)', v_wh, v_e->'days');
      end if;
      if jsonb_typeof(v_e->'hour') <> 'number' or (v_e->'hour')::text !~ '^([0-9]|1[0-9]|2[0-3])$' then
        return format('warehouse %s: hour must be a whole number 0 to 23 (got %s)', v_wh, v_e->'hour');
      end if;
    end loop;
  when 'mail_doc_from' then                                                                 -- doc-3a 판정 530: 문서 메일 보내는 주소(ims@ 의 Send mail as 에 등록된 것 · 등록 전이면 Gmail 이 거부한다)
    if not public.ims_mail_address_ok(p_value) then
      return format('must be one email address (got %s)', p_value);
    end if;
  when 'mail_doc_reply_to' then
    if p_value <> '' and not public.ims_mail_address_ok(p_value) then
      return format('must be empty or one email address (got %s)', p_value);
    end if;
  when 'mail_doc_from_name' then
    if btrim(p_value) = '' then
      return 'must not be empty';
    end if;
  else
    return 'is not a mail setting';
  end case;
  return null;
end;
$function$;
comment on function public.ims_mail_config_problem(text, text, boolean) is 'mail-1a — 메일 키 값 검사(inv_config_guard 가 부른다 · 누가 쓰든): null = 통과 · 아니면 거부 문장. 시험 엮인 규칙(이견 11)은 db_role = test 이고 mail_live <> on 일 때만(mail-live-1 판정 947 — 이 DB 의 db_role test 는 IMS 프로젝트 표지 · 손님 메일의 운영은 mail_live 가 선언한다): 돌려 보낼 주소 없이 mail_enabled = on 거부 · 켜진 동안 돌려 보낼 주소 비우기 · 지우기 거부 · 돌려 보낼 주소는 @asung.ca 만. mail_live = on | off · off 로 돌리거나 지울 때(표지 test · mail_enabled on)는 @asung.ca 돌려 보낼 곳이 있어야 한다. 일정 = {창고 id: {tz, days(ISO 1 = 월 ~ 7 = 일), hour(그 창고 시각 0 ~ 23)}} · 빠진 창고는 보내지 않는다(이견 10)';

-- ═══ 3) doc_mail_send — 미리 보기 redirect_to 는 돌려 보낼 주소가 있으면 그 주소(db_role 무관) ═══
CREATE OR REPLACE FUNCTION public.doc_mail_send(p_kind text, p_ref jsonb, p_to text DEFAULT NULL::text, p_subject text DEFAULT NULL::text, p_body text DEFAULT NULL::text, p_commit boolean DEFAULT false, p_doc_file_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff uuid;  v_cust uuid;  v_rcpt jsonb;  v_to text;  v_doc jsonb;  v_subject text;  v_body text;
  v_redirect text := nullif((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), '');
begin
  perform public.ims_require_write('sales', 'sent');                                              -- ⭐ 첫 줄(문서를 보는 문은 doc_data 가 또 묻는다)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if p_kind not in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready') then raise exception 'Only final_invoice, credit_note, sales_order or ship_ready can be mailed (internal_receipt is not sent to customers) — nothing was saved'; end if;
  if p_ref is null or jsonb_typeof(p_ref) <> 'object' then raise exception 'p_ref must be a JSON object — nothing was saved'; end if;
  v_cust := public.doc_mail_customer(p_kind, p_ref);
  if v_cust is null then raise exception 'Document not found — nothing was saved'; end if;
  if p_commit and p_kind = 'ship_ready' and p_doc_file_id is null then raise exception 'A Ship Ready mail needs the PDF made first (doc_file_id) — nothing was saved'; end if;   -- 판정 744(srm-1): 보낼 때(commit true)만 — 미리 보기는 번호 없이 통과 · doc_data(so_finalize 미리 보기)보다 먼저 — 싼 문부터
  if p_commit and p_kind = 'ship_ready' and exists (select 1 from public.doc_file f where f.id = p_doc_file_id and f.kind = 'ship_ready' and f.ref->'orders' is distinct from p_ref->'orders') then
    raise exception 'That Ship Ready PDF is for a different order — make the PDF for this order and send again — nothing was saved';   -- 판정 745(srm-1): 넘겨받은 PDF 가 이 오더의 것인가 — EF 는 doc_file.ref 를 {창의 ref(orders …), group, so_ids} 로 남기므로 orders 끼리 비교(없는 파일 · 다른 kind 는 doc_mail_enqueue 가 거절)
  end if;
  v_doc := public.doc_data(p_kind, p_ref)->'docs'->0;                                             -- 문 · 값 — 자리표 채우기 재료(ship_ready 는 so_finalize 미리 보기 · sales)
  v_rcpt := public.doc_mail_recipient(v_cust);
  v_to := lower(btrim(coalesce(nullif(p_to, ''), v_rcpt->>'to')));
  if v_to is null then raise exception 'This customer has no email address — add a contact with an email, or type one — nothing was saved'; end if;
  if not public.ims_mail_address_ok(v_to) then raise exception 'Not one email address: % — nothing was saved', v_to; end if;
  v_subject := btrim(public.doc_mail_fill(coalesce(p_subject, (select d.value from public.doc_setting d where d.kind = p_kind and d.key = 'mail_subject')), v_doc));
  v_body := public.doc_mail_fill(coalesce(p_body, (select d.value from public.doc_setting d where d.kind = p_kind and d.key = 'mail_body')), v_doc);
  if v_subject = '' then raise exception 'The mail subject is empty — set it in Settings → Documents or type one — nothing was saved'; end if;
  if v_subject ~ '[\r\n]' or length(v_subject) > 300 then raise exception 'The subject must be one line of at most 300 characters — nothing was saved'; end if;
  if length(coalesce(v_body, '')) > 20000 then raise exception 'The mail body must be at most 20000 characters — nothing was saved'; end if;
  if not p_commit then                                                                            -- mail-live-1 판정 947: redirect_to 는 EF addressFor 와 같은 뜻 — 돌려 보낼 주소가 있으면 시험이든 운영([REDIRECT →])이든 그 주소로 간다 · 없으면 null(손님에게)
    return jsonb_build_object('committed', false, 'kind', p_kind, 'customer_id', v_cust, 'to', v_to, 'to_default', v_rcpt->>'to', 'to_how', v_rcpt->>'how', 'subject', v_subject, 'body', v_body,
                              'from', (select c.value from public.inv_config c where c.key = 'mail_doc_from'), 'from_name', (select c.value from public.inv_config c where c.key = 'mail_doc_from_name'), 'reply_to', (select c.value from public.inv_config c where c.key = 'mail_doc_reply_to'),
                              'redirect_to', v_redirect, 'would_status', case when p_doc_file_id is null then 'waiting_pdf' else 'queued' end, 'doc_file_id', p_doc_file_id);
  end if;
  return jsonb_build_object('committed', true) || public.doc_mail_enqueue(p_kind, p_ref, v_to, v_subject, v_body, v_cust, v_staff, p_doc_file_id, false);
end;
$function$;

-- ═══ 4) mail_claim — 반환에 mail_live ═══
CREATE OR REPLACE FUNCTION public.mail_claim(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                              'db_role', (select c.value from public.inv_config c where c.key = 'db_role'), 'mail_live', coalesce((select c.value = 'on' from public.inv_config c where c.key = 'mail_live'), false), 'recovered_unknown', v_stale, 'mails', '[]'::jsonb);
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
                            'db_role', (select c.value from public.inv_config c where c.key = 'db_role'), 'mail_live', coalesce((select c.value = 'on' from public.inv_config c where c.key = 'mail_live'), false), 'recovered_unknown', v_stale, 'mails', v_mails);
end;
$function$;
comment on function public.mail_claim(int) is 'mail-2a — 보내는 EF(mail-2b)가 부른다(service_role 만). ① 10 분 넘게 sending 인 메일은 unknown(판정 514 — 요청이 갔는지 모른다 · 자동 재전송 안 함 · 꺼져 있어도) ② mail_enabled on 이면 queued 이고 next_attempt_at ≤ now() 인 메일을 오래된 것부터 p_limit(1 ~ 50)통 for update skip locked 로 sending · claimed_at · attempts + 1 ③ 반환 {enabled, redirect_to(비면 null), db_role, mail_live(boolean · mail-live-1 판정 947), recovered_unknown, mails[{id, kind, category, from_address, from_name, reply_to, to_address, subject, payload, attempt, claimed_at, customer_id, location_id, run_id}]} — 돌려 보내기 · 켜짐 판단은 EF 가 보내기 직전에';

-- ═══ 5) mail_settings — mail_live 는 admin ═══
CREATE OR REPLACE FUNCTION public.mail_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (public.ims_can_view('sales') or public.ims_can_view('master')) then raise exception 'Mail settings need the sales or master permission — nothing was read'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'key', k.key, 'value', c.value, 'note', c.note, 'updated_at', c.updated_at, 'updated_by_name', s.name,
      'edit_level', case when k.key in ('mail_enabled', 'mail_redirect_to', 'mail_live') then 'admin' else 'master' end,
      'can_edit', case when k.key in ('mail_enabled', 'mail_redirect_to', 'mail_live') then public.ims_is_admin() else public.ims_can_write('master') end)
    order by k.ord), '[]'::jsonb)
    from unnest(public.ims_mail_config_keys()) with ordinality k(key, ord)
    left join public.inv_config c on c.key = k.key
    left join public.ims_staff s on s.id = c.updated_by);
end;
$function$;
comment on function public.mail_settings() is 'mail-4a — 메일 설정 키(ims_mail_config_keys)의 지금 값 · 메모 · 마지막으로 바꾼 사람 · edit_level(admin: mail_enabled · mail_redirect_to · mail_live(947) · 나머지 master) · can_edit(inv_config_guard 와 같은 판정 — ims_is_admin · ims_can_write(master)) · 바꾸기는 ims_config_set · sales 또는 master 보기';

-- ═══ 6) ims_config_set — admin 갈래에 mail_live ═══
CREATE OR REPLACE FUNCTION public.ims_config_set(p_key text, p_value text, p_old text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- rls-2 · 판정 572 ~ 574 — 화면(settings.html)이 설정 한 키를 저장하는 유일한 길.
--   열쇠 식 한 곳: mail_enabled · mail_redirect_to · mail_live(947) = admin · 잠긴 3(ims_config_locked_keys) = supervisor 이상 · 나머지 메일 8 · 문서 7 · so_invoice_unit_display = master(mail_settings().edit_level · doc_config().can_edit_text 와 같은 식).
--   drive-1 판정 707: 드라이브 키 셋(ims_drive_config_keys · drive_enabled · drive_since · drive_root_id) = admin.
--   거부 20(판정 572): db_role · doc_public_base_url · base_currency · baseline_snapshot_key · customer_default_* 7 · supplier_default_* 4 · po_inventory_account_code · 계정 코드 4 · so_direct_order_tier_code — 「a migration or psql changes this」. 없는 키는 「is not a setting」.
--   값 검사는 여기 없다 — update 가 guard(inv_config_guard)를 깨우고 guard 가 누가 쓰든 값을 본다(이견 2). guard 의 사람 문은 창구 뒤의 마지막 벽(판정 573 · definer 라 닿지 않는다 · 그래서 db_role 은 여기서 먼저 거부).
--   p_old(판정 574): 화면이 본 값 · 다르면 changed_elsewhere 예외 · null 이면 검사 안 함 · 같은 값은 쓰지 않고 changed false.
declare
  v_staff   public.ims_staff%rowtype;
  v_level   text;
  v_cur     public.inv_config%rowtype;
  v_old     text;
  v_by_name text;
  v_changed boolean := false;
begin
  if p_key is null or btrim(p_key) = '' then raise exception 'p_key is required — nothing was saved'; end if;
  -- 허용 21 · 열쇠 등급(판정 572)
  if p_key in ('mail_enabled', 'mail_redirect_to', 'mail_live') or p_key = any (public.ims_drive_config_keys()) then v_level := 'admin';   -- mail-live-1 판정 947: mail_live 도 admin
  elsif p_key = any (public.ims_config_locked_keys()) then v_level := 'supervisor';
  elsif p_key = any (public.ims_mail_config_keys()) or (p_key = any (public.ims_doc_config_keys()) and p_key <> 'doc_public_base_url') or p_key in ('so_invoice_unit_display', 'fc_markup_pct') then v_level := 'master';   -- fc-1a 판정 836: 운임 마크업 % 는 master
  elsif exists (select 1 from public.inv_config c where c.key = p_key) then
    raise exception 'Setting % is not changed from the app — a migration or psql changes this — nothing was saved', p_key;
  else
    raise exception 'Setting % is not a setting — nothing was saved', p_key;
  end if;
  -- 누가(열쇠 식 한 곳 · guard · mail_settings 와 같은 말)
  select * into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff.id is null then raise exception 'You are not registered as active staff — nothing was saved'; end if;
  if v_level = 'admin' and not public.ims_is_admin() then
    raise exception 'Changing % needs an admin — it decides whether and where customer mail goes — nothing was saved', p_key;
  elsif v_level = 'supervisor' and coalesce(public.ims_role_rank(v_staff.role), 0) < public.ims_role_rank('supervisor') then
    raise exception 'Changing % needs a supervisor or above (you are %) — this value closes backorder orders for good — nothing was saved', p_key, v_staff.role;
  elsif v_level = 'master' and not public.ims_can_write('master') then
    raise exception 'Changing % needs the master permission — nothing was saved', p_key;
  end if;
  if p_value is null then raise exception 'The value cannot be empty (null) — nothing was saved'; end if;
  if p_key = 'fc_markup_pct' and (p_value !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' or p_value::numeric > 100) then                                                   -- fc-1a: 0 ~ 100 · 소수 둘째 자리까지(guard 는 이 키를 모른다 — 창구가 유일한 앱 길)
    raise exception 'fc_markup_pct must be a percent from 0 to 100 (up to two decimals · got %) — nothing was saved', p_value;
  end if;
  select * into v_cur from public.inv_config c where c.key = p_key for update;
  if not found then raise exception 'Setting % has no row yet — a migration seeds it first — nothing was saved', p_key; end if;
  v_old := v_cur.value;
  -- 판정 574 — 화면이 본 값과 다르면 거부
  if p_old is not null and p_old is distinct from v_cur.value then
    select s.name into v_by_name from public.ims_staff s where s.id = v_cur.updated_by;
    raise exception 'changed_elsewhere: % was changed by % at % to "%" since this page loaded — reload and try again — nothing was saved',
      p_key, coalesce(v_by_name, '(unknown)'), coalesce(to_char(v_cur.updated_at, 'YYYY-MM-DD HH24:MI'), '?'), left(v_cur.value, 80);
  end if;
  if v_cur.value is distinct from p_value then
    update public.inv_config set value = p_value, updated_at = now(), updated_by = v_staff.id where key = p_key;   -- guard 가 값을 본다(값 틀리면 여기서 guard 의 문장으로 선다)
    v_changed := true;
    select * into v_cur from public.inv_config c where c.key = p_key;
  end if;
  select s.name into v_by_name from public.ims_staff s where s.id = v_cur.updated_by;
  return jsonb_build_object('key', p_key, 'value', v_cur.value, 'old_value', v_old, 'changed', v_changed,
                            'updated_at', v_cur.updated_at, 'updated_by_name', v_by_name, 'edit_level', v_level);
end;
$function$;
comment on function public.ims_config_set(text, text, text) is 'rls-2 판정 572 ~ 574 — 설정 한 키 저장 창구(definer): 허용 22(메일 11 · 문서 7 · so_invoice_unit_display · 잠긴 3) + 드라이브 3(drive-1 판정 707 · admin) + fc_markup_pct · 등급 admin | supervisor | master · admin = mail_enabled · mail_redirect_to · mail_live(mail-live-1 판정 947) · 드라이브 3 · p_old 로 changed_elsewhere · 값 검사는 guard';

-- ═══ 7) inv_config mail_live = off 시드(guard → ims_mail_config_problem 통과: 표지 test · mail_enabled on 이라도 지금 redirect 가 @asung.ca) ═══
insert into public.inv_config (key, value, note) values
  ('mail_live', 'off', 'mail-live-1 판정 947 — 손님 메일 운영 선언(on · off). db_role ''test'' 는 IMS 프로젝트 표지 · 손님 메일의 운영은 이 키가 선언한다(판정 617 · 947). on 이면 시험 규칙(@asung.ca 돌려 보내기 강제 · 비우기 거부)이 풀린다 — mail_redirect_to 가 있으면 [REDIRECT →] 로 그 주소에 · 비우면 손님에게. off 로 돌릴 때 mail_enabled on 이면 @asung.ca 돌려 보낼 곳이 있어야 한다 · 바꾸기 admin')
on conflict (key) do nothing;

-- ═══ 8) 착지 확인 ═══
do $$
declare v_bad text := ''; v_acl text; v_keys text[] := public.ims_mail_config_keys();
begin
  if array_length(v_keys, 1) <> 11 or v_keys[3] <> 'mail_live' then v_bad := v_bad || ' keys'; end if;
  if not exists (select 1 from public.inv_config c where c.key = 'mail_live' and c.value in ('on', 'off') and c.note ~ '947') then v_bad := v_bad || ' mail_live-row'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_mail_config_problem') = '9e53418fd7ca5f3811e83a999eba451c' then v_bad := v_bad || ' problem-not-reissued'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_mail_config_problem') !~ 'v_live' then v_bad := v_bad || ' problem-no-live'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send') = '98f93aaa243f111befdad7eeb9a0eb1e' then v_bad := v_bad || ' doc_mail_send-not-reissued'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send') ~ 'db_role' then v_bad := v_bad || ' doc_mail_send-still-db_role'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_claim') !~ 'mail_live' then v_bad := v_bad || ' mail_claim'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_settings') !~ 'mail_live' then v_bad := v_bad || ' mail_settings'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_config_set') !~ 'mail_live' then v_bad := v_bad || ' ims_config_set'; end if;
  select proacl::text into v_acl from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_config_set';
  if v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' then v_bad := v_bad || ' ims_config_set acl ' || coalesce(v_acl, 'null'); end if;
  select proacl::text into v_acl from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_claim';
  if v_acl <> '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' mail_claim acl ' || coalesce(v_acl, 'null'); end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('ims_mail_config_keys', 'ims_mail_config_problem', 'doc_mail_send', 'mail_claim', 'mail_settings', 'ims_config_set')) <> 6 then v_bad := v_bad || ' functions'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM947', message = format('STOP - mail-live-1 landing check failed:%s', v_bad); end if;
end $$;
