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
-- qbo-1b — 끊김 메일(869) · last_error 창구 (2026-10-29 · 판정 869 · 870 · 지시서 ~/asung/prompts/qbo-1b.md · EF qbo + _shared/qbo.ts 같은 커밋 · 앞 차수 qbo-1a 20261029160000)
--   왜: EF 가 invalid_grant 로 needs_reconnect 를 찍는 순간 caleb@asung.ca 한 사람에게 메일 한 번(869). 메일을 줄 세우는 창구가 없다(mail_outbox 의 kind CHECK 는 backorder_ready · doc_* 뿐 · 넣는 곳은 mail_backorder_tick · doc_mail_enqueue 안)
--       ⇒ DB 쪽에서 넣는다: 표시와 메일이 한 트랜잭션 · 「connected → needs_reconnect 로 바뀌는 순간」 을 for update 행에서 본다 — EF 둘이 같이 찍어도 한 번 · 이미 needs_reconnect 면 0
--   ① mail_outbox.kind 에 qbo_reconnect(원본 20261019184432:647-650 의 drop/add 서식 그대로 + 한 값) · category 는 transactional 만 · 그리기는 EF mail 의 _shared/mail.ts render(payload 의 subject · body_text · 같은 커밋 · EF mail 재배포 필요)
--   ② inv_config qbo_alert_to = caleb@asung.ca(869) — 코드에 박지 않는다(사람이 바뀌면 값만 · Settings 칸이 보일 수 있다) · 값 검사는 쓰는 순간(ims_mail_address_ok) · 비었거나 틀리면 메일만 건너뛰고 warning · 표시는 그대로
--   ③ qbo_mark_needs_reconnect 재발행(마지막 정의 = 20261029160000 하나 · prosrc md5 8ca12316bb32367f4a3d536e2260cdf8 를 확인하고 바꾼다) — 본문 그대로 + was · mailed · mail_to · mail_skipped · 메일 insert 는 서브트랜잭션(실패해도 표시는 남는다 · 토큰은 남긴다 · 끊기는 admin)
--   ④ qbo_last_error_set(p_error) service_role — 상태를 바꾸지 않고 last_error 만(갱신 경합으로 새 토큰을 잃었을 때 Settings 가 보이게 · EF)
--   ⑤ 착지 확인
--   보내는 주소 = mail_doc_from · mail_doc_from_name(문서 메일과 같은 info@ · 새 키 없음) · reply_to 없음 · 시험 DB 는 mail_redirect_to 로 돌려 보내진다(mail_claim · EF mail 의 안전 검사 그대로 · Gmail 직접 호출 없음) · mail_enabled off 면 queued 로 기다린다
--   ⚠️ 적용은 Caleb: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261029190000_qbo_1b_reconnect_mail.sql · 그 뒤 supabase migration repair --status applied 20261029190000
--   시험: supabase/tests/qbo_1b_check.sql(begin → \i → 검증 → rollback)

-- ═══ 1) mail_outbox.kind — qbo_reconnect 더함(원본 20261019184432:647-650 + 한 값) ═══
alter table public.mail_outbox drop constraint mail_outbox_kind_ck;
alter table public.mail_outbox add constraint mail_outbox_kind_ck check (kind in ('backorder_ready', 'doc_final_invoice', 'doc_credit_note', 'doc_sales_order', 'doc_ship_ready', 'qbo_reconnect'));
alter table public.mail_outbox drop constraint mail_outbox_kind_category_ck;
alter table public.mail_outbox add constraint mail_outbox_kind_category_ck check (kind not in ('backorder_ready', 'doc_final_invoice', 'doc_credit_note', 'doc_sales_order', 'doc_ship_ready', 'qbo_reconnect') or category = 'transactional');
comment on constraint mail_outbox_kind_ck on public.mail_outbox is 'mail-1a · doc-3a · qbo-1b: backorder_ready · doc_*(문서 메일) · qbo_reconnect(QuickBooks 끊김 알림 — payload 의 subject · body_text 를 EF mail 이 그대로 그린다 · 넣는 곳은 qbo_mark_needs_reconnect 하나)';

-- ═══ 2) inv_config qbo_alert_to(869) ═══
insert into public.inv_config (key, value, note) values
  ('qbo_alert_to', 'caleb@asung.ca', 'qbo-1b 판정 869 — QuickBooks 연결이 끊기면(needs_reconnect 로 바뀌는 순간 한 번) 이 주소로 메일 · 한 사람(주소 하나 · 쉼표 없음) · 비었거나 주소 꼴이 아니면 메일만 건너뛴다(표시는 그대로) · 바꾸기는 지금은 마이그레이션 · 화면 칸은 뒤 차수')
  on conflict (key) do nothing;

-- ═══ 3) qbo_mark_needs_reconnect 재발행 — 원본 20261029160000(prosrc md5 8ca12316bb32367f4a3d536e2260cdf8) 확인 뒤 · 본문 그대로 + 메일 ═══
do $$
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_mark_needs_reconnect') is distinct from '8ca12316bb32367f4a3d536e2260cdf8' then
    raise exception using errcode = 'IM871', message = 'STOP - qbo_mark_needs_reconnect is not the qbo-1a definition (prosrc md5 differs) - read its last definition again before re-issuing - nothing was changed';
  end if;
end $$;
create or replace function public.qbo_mark_needs_reconnect(p_error text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_c      public.qbo_connection%rowtype;
  v_was    text;
  v_to     text := nullif(btrim(coalesce((select c.value from public.inv_config c where c.key = 'qbo_alert_to'), '')), '');
  v_from   text := nullif(btrim(coalesce((select c.value from public.inv_config c where c.key = 'mail_doc_from'), '')), '');
  v_name   text := nullif(btrim(coalesce((select c.value from public.inv_config c where c.key = 'mail_doc_from_name'), '')), '');
  v_mailed boolean := false;
  v_why    text;
  v_subject text;
  v_body   text;
begin
  if not public.doc_is_service() then raise exception 'qbo_mark_needs_reconnect is for the QuickBooks service only — nothing was changed'; end if;
  select * into v_c from public.qbo_connection for update;
  if not found then raise exception 'QuickBooks is not connected — nothing was changed'; end if;
  v_was := v_c.status;
  update public.qbo_connection set status = 'needs_reconnect', last_error = left(coalesce(nullif(btrim(p_error), ''), 'QuickBooks refused the token'), 400), last_error_at = now(),
    refreshing_until = null, refreshing_by = null, updated_at = now() returning * into v_c;
  if v_was = 'connected' then                                                                     -- 869: connected → needs_reconnect 로 바뀌는 순간 한 번만(이미 needs_reconnect 면 0)
    if v_to is null or not public.ims_mail_address_ok(v_to) then
      v_why := 'inv_config.qbo_alert_to is empty or not an email address';
    elsif v_from is null or not public.ims_mail_address_ok(v_from) then
      v_why := 'inv_config.mail_doc_from (the sender) is empty or not an email address';
    else
      v_subject := '[IMS] QuickBooks connection needs attention (' || v_c.env || ')';
      v_body := 'QuickBooks stopped accepting the IMS connection.' || E'\n\n'
             || 'Company:  ' || coalesce(v_c.company_name, '(name not read yet)') || ' (' || v_c.env || ', id ' || v_c.realm_id || ')' || E'\n'
             || 'When:     ' || to_char(now() at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI') || ' Toronto' || E'\n'
             || 'Reason:   ' || v_c.last_error || E'\n\n'
             || 'Nothing is sent to QuickBooks until it is reconnected.' || E'\n'
             || 'Open IMS -> Settings -> QuickBooks and click Reconnect (admin only).' || E'\n\n'
             || 'Asung IMS';
      begin
        insert into public.mail_outbox (kind, category, status, from_address, from_name, reply_to, to_address, subject, body_text, payload, dedupe_key)
        values ('qbo_reconnect', 'transactional', 'queued', v_from, v_name, null, v_to, v_subject, v_body,
                jsonb_build_object('env', v_c.env, 'realm_id', v_c.realm_id, 'company_name', v_c.company_name, 'error', v_c.last_error, 'at', now(), 'subject', v_subject, 'body_text', v_body),
                'qbo:reconnect:' || v_c.env || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'));
        v_mailed := true;
      exception when others then
        v_why := 'mail_outbox insert failed: ' || sqlerrm;                                        -- 메일이 표시를 막지 않는다
      end;
    end if;
    if not v_mailed then raise warning 'qbo_mark_needs_reconnect: alert mail (869) not queued — %', v_why; end if;
  end if;
  return jsonb_build_object('status', v_c.status, 'last_error', v_c.last_error, 'last_error_at', v_c.last_error_at,
                            'was', v_was, 'mailed', v_mailed, 'mail_to', case when v_mailed then v_to end, 'mail_skipped', v_why);
end;
$$;
comment on function public.qbo_mark_needs_reconnect(text) is 'qbo-1a · 1b: invalid_grant · 갱신 토큰 만료 · QBO 쪽에서 끊김 → needs_reconnect · last_error(EF 가 거른 글) · 임대 풀기 · 토큰은 남긴다(끊기는 admin 의 동작) · 1b 판정 869: connected 에서 바뀌는 순간에만 inv_config.qbo_alert_to 로 mail_outbox 한 줄(kind qbo_reconnect · 서브트랜잭션 · 실패해도 표시는 남는다) · 돌려주는 was · mailed · mail_to · mail_skipped';

-- ═══ 4) qbo_last_error_set — 상태 무변 · last_error 만(EF · 갱신 경합) ═══
create function public.qbo_last_error_set(p_error text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_c public.qbo_connection%rowtype;
begin
  if not public.doc_is_service() then raise exception 'qbo_last_error_set is for the QuickBooks service only — nothing was changed'; end if;
  update public.qbo_connection set last_error = left(coalesce(nullif(btrim(p_error), ''), 'QuickBooks call failed'), 400), last_error_at = now(), updated_at = now() returning * into v_c;
  if not found then raise exception 'QuickBooks is not connected — nothing was changed'; end if;
  return jsonb_build_object('status', v_c.status, 'last_error', v_c.last_error, 'last_error_at', v_c.last_error_at);
end;
$$;
revoke all on function public.qbo_last_error_set(text) from public, anon, authenticated, service_role;
grant execute on function public.qbo_last_error_set(text) to service_role;
comment on function public.qbo_last_error_set(text) is 'qbo-1b: EF 전용 — 상태는 그대로 두고 last_error · last_error_at 만(갱신 둘이 겹쳐 판 번호가 밀려 새 토큰을 잃었을 때 Settings 가 보이게) · 갱신 성공(qbo_refresh_save)이 비운다';

-- ═══ 5) 착지 확인 ═══
do $$
declare v_bad text := ''; v_acl text;
begin
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'mail_outbox_kind_ck' and conrelid = 'public.mail_outbox'::regclass) !~ 'qbo_reconnect' then v_bad := v_bad || ' kind_ck'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'mail_outbox_kind_category_ck' and conrelid = 'public.mail_outbox'::regclass) !~ 'qbo_reconnect' then v_bad := v_bad || ' kind_category_ck'; end if;
  if not exists (select 1 from public.inv_config c where c.key = 'qbo_alert_to' and public.ims_mail_address_ok(c.value)) then v_bad := v_bad || ' qbo_alert_to'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_mark_needs_reconnect') = '8ca12316bb32367f4a3d536e2260cdf8' then v_bad := v_bad || ' mark-not-reissued'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_mark_needs_reconnect') !~ 'qbo_reconnect' then v_bad := v_bad || ' mark-no-mail'; end if;
  select proacl::text into v_acl from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_mark_needs_reconnect';
  if v_acl <> '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' mark acl ' || coalesce(v_acl, 'null'); end if;
  select proacl::text into v_acl from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_last_error_set';
  if v_acl <> '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' last_error_set acl ' || coalesce(v_acl, 'null'); end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_mark_needs_reconnect', 'qbo_last_error_set')) <> 2 then v_bad := v_bad || ' functions'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM871', message = format('STOP - qbo-1b landing check failed:%s', v_bad); end if;
end $$;
