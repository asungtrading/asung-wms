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
-- 20261016123721_mail_1a_base.sql — mail-1a (2026-10-16 · 회사 PC · Fable · IMS 메일 기계의 바닥 · 첫 사용자 = 백오더 입고 알림)
--   판정 493 ~ 511(Caleb 2026-10-15 ~ 16) · mail-1a §0 이견 1 ~ 11 (Caleb 2026-10-16 「모두 받는다」)
--   ① ims_mail_address_ok(text) — 주소 하나 모양(한 정의 · guard · mail_outbox CHECK · mail-1b 연락처 고르기가 함께 쓴다 · 이견 4)
--   ② mail_run(회차 · kind × 창고 × 그 창고 날짜에 한 번) · mail_outbox(보낼 메일 한 통 = 한 행) · mail_backorder_line(어느 메일에 어느 줄 · 줄마다 한 번 = 판정 497 · 505)
--      ⚠️ 알림 기록은 so_line 칸이 아니라 따로 표(mail-0 이견 11 — so_line 을 쓰면 ims_touch 가 updated_at 을 바꿔 so_unconfirm 형제 검사가 그 오더를 영영 막는다 · 판정 478 과 같은 뿌리)
--      판정 509(나뉜 줄은 원래 줄의 기록을 이어받는다)는 읽는 쪽(mail-1b)이 so_line.split_from_line_id 를 거슬러 본다 — 이 표에 계보 칸 없음
--   ③ customer.backorder_mail(판정 507 · 칸만 — 바꾸는 창구 customer_update 목록 재발행 · 「누가」는 mail-4 · 이견 8)
--   ④ 메일 설정 키 일곱 시드(on conflict do nothing · mail_enabled = off) · ims_mail_config_keys() · ims_mail_config_problem(key, value, delete)
--   ⑤ inv_config_guard 재발행(20261006201443:1151 바이트 + 더한 줄만) — 이름 바꾸기 거부(이견 2) · db_role 은 postgres 만(이견 1) · 메일 키 갈래(admin 키 둘 · master 키 다섯 · 삭제 금지 · 시험 DB 엮인 규칙 = 이견 11)
--   ⑥ revoke truncate on inv_config from authenticated, anon(mail-0 이견 14) · 새 표 셋 RLS 켬 · 정책 없음 · anon · authenticated 표 권한 0(읽기 · 쓰기는 뒤 차수 definer 창구)
--   무접촉: so · so_line(backorder_notified_at 칸 포함) · so_reserve · ims_config_locked_keys · 다른 표의 TRUNCATE(기본 권한 뿌리는 미룬 거리)
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/mail-1a-verify.sql

-- ═══ ① 주소 하나 모양 ═══
create function public.ims_mail_address_ok(p_address text) returns boolean
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$
  select p_address is not null and p_address ~ '^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$';
$$;
comment on function public.ims_mail_address_ok(text) is 'mail-1a 이견 4 — 메일 주소 하나 모양(@ 하나 · 점 있는 도메인 · 공백 · 쉼표 · 세미콜론 없음). 한 정의: inv_config_guard 의 메일 키 · mail_outbox 주소 CHECK · mail-1b 연락처 고르기(「INVOICE ONLY: …」 류는 모양 틀림)';
revoke all on function public.ims_mail_address_ok(text) from public, anon;
grant execute on function public.ims_mail_address_ok(text) to authenticated, service_role;

-- ═══ ② 표 셋 ═══
create table public.mail_run (
  id             uuid primary key default gen_random_uuid(),
  kind           text not null,
  location_id    uuid not null references public.ref_warehouse(id),
  run_on         date not null,
  started_at     timestamptz not null default now(),
  mails          int not null default 0,
  lines          int not null default 0,
  no_email       jsonb not null default '[]'::jsonb,
  params         jsonb not null default '{}'::jsonb,
  chat_posted_at timestamptz,
  chat_error     text,
  constraint mail_run_kind_ck     check (kind in ('backorder_ready')),
  constraint mail_run_counts_ck   check (mails >= 0 and lines >= 0),
  constraint mail_run_no_email_ck check (jsonb_typeof(no_email) = 'array'),
  constraint mail_run_params_ck   check (jsonb_typeof(params) = 'object'),
  constraint mail_run_once_uq     unique (kind, location_id, run_on)
);
comment on table public.mail_run is 'mail-1a — 메일 회차 하나(판정 503: 창고마다 월 · 목 아침 그 창고 시각). unique(kind, location_id, run_on) = 「이 아침 이미 돌았다」 · run_on 은 그 창고 시각의 날짜';
comment on column public.mail_run.no_email is '보내지 못한 손님 목록(판정 498 「이메일 없음」 · 모양 틀림 · 스위치 끔 등) — 원소 모양은 mail-1b 가 정한다 · 배열';
comment on column public.mail_run.params is 'mail-1a 이견 7 — 그 회차가 쓴 설정(절반 기준 · 일정 등)의 사본 · 설정이 뒤에 바뀌어도 「그때 왜 이 줄이 실렸나」를 설명한다';

create table public.mail_outbox (
  id                  uuid primary key default gen_random_uuid(),
  kind                text not null,
  category            text not null,
  status              text not null default 'queued',
  from_address        text not null,
  from_name           text,
  reply_to            text,
  to_address          text not null,
  original_to         text,
  subject             text,
  body_text           text,
  body_html           text,
  payload             jsonb not null default '{}'::jsonb,
  customer_id         uuid references public.customer(id),
  location_id         uuid references public.ref_warehouse(id),
  run_id              uuid references public.mail_run(id),
  attempts            int not null default 0,
  next_attempt_at     timestamptz,
  last_error          text,
  claimed_at          timestamptz,
  sent_at             timestamptz,
  provider_message_id text,
  dedupe_key          text not null,
  created_at          timestamptz not null default now(),
  created_by          uuid references public.ims_staff(id),
  constraint mail_outbox_kind_ck          check (kind in ('backorder_ready')),
  constraint mail_outbox_category_ck      check (category in ('transactional', 'marketing')),
  constraint mail_outbox_kind_category_ck check (kind <> 'backorder_ready' or category = 'transactional'),
  constraint mail_outbox_status_ck        check (status in ('queued', 'sending', 'sent', 'failed', 'unknown', 'cancelled')),
  constraint mail_outbox_from_ck          check (public.ims_mail_address_ok(from_address)),
  constraint mail_outbox_to_ck            check (public.ims_mail_address_ok(to_address)),
  constraint mail_outbox_reply_to_ck      check (reply_to is null or public.ims_mail_address_ok(reply_to)),
  constraint mail_outbox_original_to_ck   check (original_to is null or public.ims_mail_address_ok(original_to)),
  constraint mail_outbox_payload_ck       check (jsonb_typeof(payload) = 'object'),
  constraint mail_outbox_attempts_ck      check (attempts >= 0),
  constraint mail_outbox_sent_ck          check ((status = 'sent') = (sent_at is not null)),
  constraint mail_outbox_sending_ck       check (status <> 'sending' or claimed_at is not null),
  constraint mail_outbox_error_ck         check (status not in ('failed', 'unknown') or last_error is not null),
  constraint mail_outbox_dedupe_ck        check (dedupe_key <> ''),
  constraint mail_outbox_dedupe_uq        unique (dedupe_key)
);
comment on table public.mail_outbox is 'mail-1a — 보낼 메일 한 통 = 한 행(판정 493 회사 Gmail · 첫 kind = backorder_ready). 생산(mail-1b)이 queued 로 넣고 EF(mail-2b)가 sending → sent · failed · unknown(요청은 갔는데 응답 못 받음 — 자동 재시도 안 함). 짝 CHECK: sent ⇔ sent_at · sending ⇒ claimed_at(한 방향 — 다시 보낼 때 claimed_at 기록을 지우지 않는다) · failed · unknown ⇒ last_error';
comment on column public.mail_outbox.category is 'mail-0 이견 10 — transactional(거래 · 동의 없이 보낸다) · marketing(동의 true 만 · so-module 1735) · backorder_ready 는 transactional 만(mail_outbox_kind_category_ck)';
comment on column public.mail_outbox.original_to is '돌려 보내기 전 받는 이(시험 DB 의 mail_redirect_to) — 운영은 null';
comment on column public.mail_outbox.payload is '생산 함수가 만든 재료(줄 · 수량의 사본) — subject · body_* 는 EF 가 그린 결과(「무엇을 보냈나」)';
comment on column public.mail_outbox.dedupe_key is '멱등 열쇠 — 같은 열쇠 두 번째 insert 거부 · 모양은 생산 쪽(mail-1b)이 정한다';
create index mail_outbox_queued_idx  on public.mail_outbox (next_attempt_at) where status = 'queued';
create index mail_outbox_sending_idx on public.mail_outbox (claimed_at) where status = 'sending';
create index mail_outbox_run_idx      on public.mail_outbox (run_id);
create index mail_outbox_customer_idx on public.mail_outbox (customer_id);

create table public.mail_backorder_line (
  id              uuid primary key default gen_random_uuid(),
  outbox_id       uuid not null references public.mail_outbox(id),
  so_line_id      uuid not null references public.so_line(id),
  basis           text not null,
  qty_open        numeric not null,
  can_fill_units  numeric not null,
  available_units numeric,
  released_at     timestamptz,
  created_at      timestamptz not null default now(),
  constraint mail_backorder_line_basis_ck     check (basis in ('receipt', 'full')),
  constraint mail_backorder_line_qty_ck       check (qty_open > 0 and can_fill_units > 0 and (available_units is null or available_units >= 0)),
  constraint mail_backorder_line_full_ck      check (basis <> 'full' or can_fill_units >= qty_open)
);
create unique index mail_backorder_line_once_uq on public.mail_backorder_line (so_line_id) where released_at is null;
create index mail_backorder_line_outbox_idx on public.mail_backorder_line (outbox_id);
comment on table public.mail_backorder_line is 'mail-1a — 어느 메일에 어느 백오더 줄이 실렸나 = 판정 497 · 505 의 「줄마다 한 번」 자리(mail_backorder_line_once_uq: 풀리지 않은 행은 줄마다 하나). 판정 509: 나뉜 줄은 읽는 쪽이 split_from_line_id 를 거슬러 본다. so_line 칸(backorder_notified_at)이 아니라 따로 표 — mail-0 이견 11';
comment on column public.mail_backorder_line.basis is '판정 504 — receipt: 입고(po_in · 다른 창고에서 온 transfer_in)로 그 손님 몫이 qty_open 의 mail_backorder_min_fill_pct 이상 · full: 입고 아닌 재고로 그 줄이 다 채워짐(can_fill_units ≥ qty_open)';
comment on column public.mail_backorder_line.qty_open is '그때 값 — qty_open · can_fill_units 는 같은 단위(콤보 줄은 콤보 수) · available_units = 그 창고 전체 가용(판정 501)';
comment on column public.mail_backorder_line.released_at is '메일이 failed 로 끝나 풀었을 때 — 풀린 줄은 다음 회차에 다시 실린다(unknown 은 풀지 않는다)';

-- ═══ ③ 손님 스위치(판정 507) ═══
alter table public.customer add column backorder_mail boolean not null default true;
comment on column public.customer.backorder_mail is '판정 507 — 「백오더 알림 받기」(기본 켜짐) · 끄면 백오더 알림만 안 간다(다른 메일과 무관) · 손님 적재(ImsLoadCustomer)는 고정 칸 목록이라 보내지 않는다 · 화면에서 바꾸는 길(customer_update 목록)과 누가는 mail-4';

-- ═══ ④ 메일 설정 키 ═══
create function public.ims_mail_config_keys() returns text[]
  language sql immutable
  set search_path = public, pg_temp
as $$
  select array['mail_enabled', 'mail_redirect_to', 'mail_backorder_from', 'mail_backorder_reply_to', 'mail_backorder_from_name', 'mail_backorder_schedule', 'mail_backorder_min_fill_pct'];
$$;
comment on function public.ims_mail_config_keys() is 'mail-1a — inv_config 의 메일 키 일곱(inv_config_guard 의 메일 갈래 · 이름 바꾸기 거부가 읽는다). admin 키 = mail_enabled · mail_redirect_to · 나머지 다섯은 master. ims_config_locked_keys(양의 정수 · supervisor) 와 뜻이 달라 따로 둔다 — 이견 4';
revoke all on function public.ims_mail_config_keys() from public, anon;
grant execute on function public.ims_mail_config_keys() to authenticated, service_role;

create function public.ims_mail_config_problem(p_key text, p_value text, p_delete boolean default false) returns text
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_test boolean := coalesce((select c.value = 'test' from public.inv_config c where c.key = 'db_role'), false);
  v_j    jsonb;
  v_wh   text;
  v_e    jsonb;
begin
  -- 시험 DB 엮인 규칙(이견 11) — 켜진 동안 돌려 보낼 주소를 지우지 못한다
  if p_delete then
    if p_key = 'mail_redirect_to' and v_test and (select c.value from public.inv_config c where c.key = 'mail_enabled') = 'on' then
      return 'cannot be removed while mail_enabled is on in the test database — turn mail_enabled off first';
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
  else
    return 'is not a mail setting';
  end case;
  return null;
end;
$$;
comment on function public.ims_mail_config_problem(text, text, boolean) is 'mail-1a — 메일 키 값 검사(inv_config_guard 가 부른다 · 누가 쓰든): null = 통과 · 아니면 거부 문장. 시험 DB(db_role = test) 엮인 규칙(이견 11): 돌려 보낼 주소 없이 mail_enabled = on 거부 · 켜진 동안 돌려 보낼 주소 비우기 · 지우기 거부 · 돌려 보낼 주소는 @asung.ca 만. 일정 = {창고 id: {tz, days(ISO 1 = 월 ~ 7 = 일), hour(그 창고 시각 0 ~ 23)}} · 빠진 창고는 보내지 않는다(이견 10)';
revoke all on function public.ims_mail_config_problem(text, text, boolean) from public, anon;
grant execute on function public.ims_mail_config_problem(text, text, boolean) to authenticated, service_role;

-- ═══ ⑤ inv_config_guard 재발행 — 원본 20261006201443_dsc_3a_order_discount.sql:1151 바이트 + 더한 줄(mail-1a)만 ═══
create or replace function public.inv_config_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  v_key   text := coalesce(new.key, old.key);
  v_staff public.ims_staff%rowtype;
  v_guarded text[] := public.ims_config_locked_keys() || public.ims_mail_config_keys() || array['so_invoice_unit_display', 'db_role'];   -- mail-1a 이견 2: 지키는 키 전부
  v_problem text;                                                       -- mail-1a: 메일 키 검사의 거부 문장(null = 통과)
begin
  -- mail-1a 이견 2: 지키는 키는 옛 이름 · 새 이름을 둘 다 본다 — 직원(authenticated)은 key 이름을 못 바꾼다(바꾸면 새 이름만 읽혀 잠금 밖 키가 되었다)
  if tg_op = 'UPDATE' and current_user = 'authenticated' and new.key is distinct from old.key and (old.key = any (v_guarded) or new.key = any (v_guarded)) then
    raise exception 'inv_config key % cannot be renamed from the app — nothing was saved', old.key;
  end if;
  -- mail-1a 이견 1: db_role(시험 DB 표지 — 테스트 가드 · EF 가 읽는다)은 postgres(마이그레이션)만 넣고 · 바꾸고 · 지운다
  if v_key = 'db_role' or (tg_op = 'UPDATE' and old.key = 'db_role') then
    if current_user <> 'postgres' then
      raise exception 'inv_config.db_role marks which database this is — only a migration can change it — nothing was saved';
    end if;
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  -- mail-1a: 메일 키 일곱 — 값 검사는 누가 쓰든(시험 DB 엮인 규칙 포함 · 이견 11) · 화면에서는 admin 키(mail_enabled · mail_redirect_to) · 나머지는 master · 삭제 금지
  if v_key = any (public.ims_mail_config_keys()) then
    v_problem := public.ims_mail_config_problem(v_key, new.value, tg_op = 'DELETE');
    if v_problem is not null then
      raise exception 'inv_config.% % — nothing was saved', v_key, v_problem;
    end if;
    if current_user = 'authenticated' then
      if v_key in ('mail_enabled', 'mail_redirect_to') then
        if not public.ims_is_admin() then
          raise exception 'Changing % needs an admin — it decides whether and where customer mail goes — nothing was saved', v_key;
        end if;
      elsif not public.ims_can_write('master') then
        raise exception 'Changing % needs the master permission — nothing was saved', v_key;
      end if;
      if tg_op = 'DELETE' then
        raise exception 'inv_config.% cannot be deleted from the app — change its value instead — nothing was deleted', v_key;
      end if;
      new.updated_at := now();
      new.updated_by := (select s.id from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active);
    end if;
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  -- dsc-3a 판정 314: 키마다 규칙 — 설정 키(so_invoice_unit_display)는 어휘 검사 + master · 잠긴 키 셋은 아래 종전 규칙(양의 정수 · supervisor)
  if v_key = 'so_invoice_unit_display' then
    if tg_op in ('INSERT', 'UPDATE') and (new.value is null or new.value not in ('both', 'discounted', 'net')) then
      raise exception 'inv_config.so_invoice_unit_display must be one of both, discounted, net (got %) — nothing was saved', coalesce(new.value, 'null');
    end if;
    if current_user = 'authenticated' then
      if not public.ims_can_write('master') then
        raise exception 'Changing % needs the master permission — nothing was saved', v_key;
      end if;
      if tg_op = 'DELETE' then
        raise exception 'inv_config.% cannot be deleted from the app — set it to both instead — nothing was deleted', v_key;
      end if;
      new.updated_at := now();
      new.updated_by := (select s.id from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active);
    end if;
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if not (v_key = any (public.ims_config_locked_keys())) then
    return case when tg_op = 'DELETE' then old else new end;     -- 잠기지 않은 키 — 종전 그대로(아무것도 안 바꾼다)
  end if;

  -- 값 — 양의 정수만(누가 쓰든 · 스윕은 숫자 아니면 멈추지만 쓰는 순간 막는 편이 낫다)
  if tg_op in ('INSERT', 'UPDATE') then
    if new.value is null or new.value !~ '^[0-9]{1,4}$' or new.value::int <= 0 then
      raise exception 'inv_config.% must be a positive whole number of days (got %) — nothing was saved', v_key, coalesce(new.value, 'null');
    end if;
  end if;

  -- 누가 — authenticated(화면·PostgREST)만 묻는다 · postgres(psql seed · cron) · service_role(GAS · EF) 은 통과
  if current_user = 'authenticated' then
    select * into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff.id is null then
      raise exception 'You are not registered as active staff — nothing was saved';
    end if;
    if coalesce(public.ims_role_rank(v_staff.role), 0) < public.ims_role_rank('supervisor') then
      raise exception 'Changing % needs a supervisor or above (you are %) — this value closes backorder orders for good — nothing was saved', v_key, v_staff.role;
    end if;
    if tg_op = 'DELETE' then
      raise exception 'inv_config.% cannot be deleted from the app — ask an admin to change its value instead — nothing was deleted', v_key;
    end if;
    new.updated_at := now();
    new.updated_by := v_staff.id;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
comment on function public.inv_config_guard() is 'inv_config BEFORE INSERT · UPDATE · DELETE — 키마다 규칙(dsc-3a · 판정 314 · mail-1a): 지키는 키(잠긴 키 셋 · so_invoice_unit_display · 메일 키 일곱 · db_role)는 화면에서 이름 바꾸기 거부(옛 이름 · 새 이름 둘 다 본다) · db_role 은 postgres(마이그레이션)만 · 메일 키 일곱(ims_mail_config_keys)은 ims_mail_config_problem 검사(누가 쓰든) + 화면에서는 mail_enabled · mail_redirect_to 는 admin · 나머지는 master · 삭제 금지 · so_invoice_unit_display 는 both · discounted · net 만 + 화면에서는 master 만 · 잠긴 키 셋(ims_config_locked_keys · 백오더 만료 · 재입고 수수료)은 양의 정수 + supervisor 이상 + 삭제 금지 · 그 밖의 키는 종전 그대로';

-- ═══ ⑥ 시드 — 이미 있으면 안 덮는다 · mail_enabled 는 off 로 시작 · 일정의 창고 id 는 이름으로 찾는다(못 찾으면 멈춘다) ═══
insert into public.inv_config (key, value, note) values
  ('mail_enabled',                'off',                    'mail-1a — IMS 메일 전체 켜기(on · off) · 켜는 순간 손님에게 나간다 · 바꾸기 admin · 시험 DB 는 mail_redirect_to 없이 켜지 못한다'),
  ('mail_redirect_to',            '',                       'mail-1a — 비어 있지 않으면 모든 메일을 이 주소로 돌려 보낸다(원래 받는 이는 mail_outbox.original_to) · 시험 DB 는 @asung.ca 만 · 켜진 동안 비우기 거부 · 바꾸기 admin'),
  ('mail_backorder_from',         'notifications@asung.ca', 'mail-1a 판정 511 — 백오더 알림의 보내는 주소(ims@asung.ca 의 사용자 별칭) · 바꾸기 master'),
  ('mail_backorder_reply_to',     'info@asung.ca',          'mail-1a 판정 511 — 백오더 알림의 답장 주소(Reply-To) · 빈 값이면 넣지 않는다 · 바꾸기 master'),
  ('mail_backorder_from_name',    'Asung Trading',          'mail-1a 판정 511 — 백오더 알림의 보내는 이름 · 바꾸기 master'),
  ('mail_backorder_min_fill_pct', '50',                     'mail-1a 판정 505 — 입고로 그 손님 몫이 그 줄 백오더 수량(qty_open)의 이 % 이상일 때 한 번 알린다(1 ~ 100) · 바꾸기 master')
  on conflict (key) do nothing;
do $$
declare
  v_to uuid;
  v_ed uuid;
begin
  if (select count(*) from public.ref_warehouse w where w.name = 'Asung Trading Inc.' and w.is_active) <> 1
     or (select count(*) from public.ref_warehouse w where w.name = 'Asung - Edmonton' and w.is_active) <> 1 then
    raise exception using errcode = 'IM511',
      message = 'STOP - mail-1a could not find exactly one active warehouse named Asung Trading Inc. and one named Asung - Edmonton for mail_backorder_schedule - nothing was changed';
  end if;
  select w.id into v_to from public.ref_warehouse w where w.name = 'Asung Trading Inc.' and w.is_active;
  select w.id into v_ed from public.ref_warehouse w where w.name = 'Asung - Edmonton' and w.is_active;
  insert into public.inv_config (key, value, note) values
    ('mail_backorder_schedule',
     jsonb_build_object(v_to::text, jsonb_build_object('tz', 'America/Toronto', 'days', jsonb_build_array(1, 4), 'hour', 9),
                        v_ed::text, jsonb_build_object('tz', 'America/Edmonton', 'days', jsonb_build_array(1, 4), 'hour', 9))::text,
     'mail-1a 판정 503 — 창고마다 백오더 알림 일정 {창고 id: {tz, days(ISO 1 = 월 ~ 7 = 일), hour(그 창고 시각)}} · 빠진 창고는 보내지 않는다 · 매시 틱(mail-1b)이 견준다 · 바꾸기 master')
    on conflict (key) do nothing;
end $$;

-- ═══ ⑦ 권한 ═══
revoke truncate on public.inv_config from authenticated, anon;
alter table public.mail_run enable row level security;
alter table public.mail_outbox enable row level security;
alter table public.mail_backorder_line enable row level security;
revoke all on public.mail_run, public.mail_outbox, public.mail_backorder_line from anon, authenticated;

-- ═══ ⑧ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if to_regclass('public.mail_run') is null or to_regclass('public.mail_outbox') is null or to_regclass('public.mail_backorder_line') is null then v_bad := v_bad || ' tables'; end if;
  if (select count(*) from pg_class where oid in ('public.mail_run'::regclass, 'public.mail_outbox'::regclass, 'public.mail_backorder_line'::regclass) and relrowsecurity) <> 3 then v_bad := v_bad || ' rls'; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('mail_run', 'mail_outbox', 'mail_backorder_line')) <> 0 then v_bad := v_bad || ' policies'; end if;
  if exists (select 1 from information_schema.role_table_grants where table_schema = 'public' and table_name in ('mail_run', 'mail_outbox', 'mail_backorder_line') and grantee in ('anon', 'authenticated')) then v_bad := v_bad || ' table-grants'; end if;
  if has_table_privilege('authenticated', 'public.inv_config', 'truncate') or has_table_privilege('anon', 'public.inv_config', 'truncate') then v_bad := v_bad || ' inv_config-truncate'; end if;
  if (select count(*) from public.inv_config where key = any (public.ims_mail_config_keys())) <> 7 then v_bad := v_bad || ' seed'; end if;
  if (select value from public.inv_config where key = 'mail_enabled') <> 'off' then v_bad := v_bad || ' mail_enabled-not-off'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'customer' and column_name = 'backorder_mail' and is_nullable = 'NO' and column_default = 'true') then v_bad := v_bad || ' customer.backorder_mail'; end if;
  if (select prosrc from pg_proc where oid = 'public.inv_config_guard()'::regprocedure) !~ 'cannot be renamed from the app' then v_bad := v_bad || ' guard-body'; end if;
  if has_function_privilege('anon', 'public.ims_mail_address_ok(text)', 'execute') or has_function_privilege('anon', 'public.ims_mail_config_keys()', 'execute')
     or has_function_privilege('anon', 'public.ims_mail_config_problem(text, text, boolean)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM511', message = format('STOP - mail-1a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
