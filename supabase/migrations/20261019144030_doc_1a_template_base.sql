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
-- 20261019144030_doc_1a_template_base.sql — doc-1a (2026-10-19 · 회사 PC · Fable · 문서 템플릿 ① 판 · 글 · 열쇠 · 로고)
--   판정 521 ~ 525(Caleb 2026-10-19) · doc-0 조사 회신(이견 3 · 6 · 7 · Q3) · doc-1a §0 이견(회신)
--   ① 표 넷 doc_template(판 · 쓴 뒤 body · kind · version 못 바꿈 · 안 지움) · doc_template_active(kind 마다 쓰는 판 하나) · doc_template_event(판 쓰기 · 되돌리기 이력) · doc_setting(문서마다 글 · 켜고 끄기)
--      문지기 doc_rows_guard — 판 행 고치기 · 지우기 거부 · 이력 고치기 · 지우기 거부 · 글 지우기 거부(postgres 포함 · 되돌리기는 publish 로)
--   ② 회사 글 inv_config 키 여섯(doc_company_name · doc_hst · doc_website · doc_terms · doc_branches · doc_logo_path · 판정 524 · 525) · ims_doc_config_keys() · ims_doc_config_problem() · inv_config_guard 재발행(20261016123721:257 바이트 + 더한 줄만 · 화면 쓰기 = master)
--   ③ 판 쓰기 열쇠 doc_template(판정 522) — ims_perm_catalog 재발행(20261009170919:121 바이트 + 한 줄) · ims_can_doc_template()(admin 역할 · supervisor 는 열쇠 켠 사람만 · manager · worker 는 열쇠가 있어도 false)
--      ⚠️ ims_can_write('doc_template') 은 supervisor 전원에게 true 다(ims_can_write 는 admin · supervisor 를 역할로 통과시킨다) — 판 쓰기 문은 ims_can_doc_template 만 쓴다(doc-0 이견 3 · 판정 42 와 같은 틈)
--   ④ 공개 버킷 doc-brand(png · jpeg · 2 MB · svg 는 받지 않는다 — 스크립트를 품는다) · 쓰기 정책 master · 읽기 공개(/object/public/)
--   ⑤ 자리표 목록 doc_field_catalog(kind) — 판과 doc-1b 데이터 창구의 계약(allowed · sections · required · 경로 꼴 orders.lines.sku)
--   ⑥ 검사기 doc_template_check(kind, body, mode) — Mustache 꼬리표({{x}} · {{#s}} · {{^s}} · {{/s}} · {{! }} 만) · {{{ }}} · {{& }} · {{> }} · {{= =}} 거부 · 섹션 짝 · 경로 해석(안쪽 → 바깥) · 필수 · 금지 HTML(script · on…= · javascript: · iframe · object · embed · form · meta · link · base · @import · 바깥 주소) · 200 KB
--      ⚠️ 판정 402 는 「거르고 넣는다」 · 판은 거부한다(대화 Claude 가 고쳐 다시 올린다 · doc-0 Q3)
--   ⑦ 창구 doc_template_upload(검사 · 저장) · doc_template_publish(쓰기 · 되돌리기 · 같은 판이면 아무것도 안 함) · doc_setting_set(master) · 읽기 doc_template_list · doc_template_get · doc_config(활성 직원 · service_role)
--   ⑧ doc_setting 시드 30(다섯 × 여섯) · ⑨ RLS 켬 · 정책 없음 · anon · authenticated 표 권한 0(TRUNCATE 포함 · 미룬 247) · ⑩ 실물 확인
--   무접촉: so_* · customer · mail_* · ims_staff · 화면 파일 · 운영 DB · PDF 저장(doc_file · documents 버킷)은 doc-2
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/doc-1a-verify.sql

-- ═══ ① 표 넷 ═══
create table public.doc_template (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null,
  version      int  not null,
  body         text not null,
  check_result jsonb not null,
  note         text,
  uploaded_by  uuid references public.ims_staff(id),
  uploaded_at  timestamptz not null default now(),
  constraint doc_template_kind_ck    check (kind in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt')),
  constraint doc_template_version_ck check (version >= 1),
  constraint doc_template_body_ck    check (body <> ''),
  constraint doc_template_check_ck   check (jsonb_typeof(check_result) = 'object' and (check_result->>'ok') in ('true', 'false')),
  constraint doc_template_kind_version_uq unique (kind, version)
);
comment on table public.doc_template is 'doc-1a 안 A — 문서 판(배치) 한 벌 = 한 행 · kind 다섯 × version(1, 2, …) · body = Mustache 꼴 HTML(대화 Claude 가 통째로 쓴다) · check_result = 올릴 때 검사(doc_template_check) 결과 · ⚠️ 쓴 뒤 body · kind · version · check_result 는 못 바꾸고 지우지 않는다(doc_rows_guard — 「발행 때의 판으로 다시 찍기」 doc-2 가 이 행을 믿는다) · 쓰는 판은 doc_template_active · 쓰기는 doc_template_upload 로만 · 검사를 통과한 판만 저장된다';
create index doc_template_uploaded_by_idx on public.doc_template (uploaded_by);

create table public.doc_template_active (
  kind        text primary key,
  template_id uuid not null references public.doc_template(id),
  set_by      uuid references public.ims_staff(id),
  set_at      timestamptz not null default now(),
  constraint doc_template_active_kind_ck check (kind in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt'))
);
comment on table public.doc_template_active is 'doc-1a — kind 마다 지금 쓰는 판 하나(없으면 그 문서는 아직 못 찍는다) · 바꾸기는 doc_template_publish 로만(옛 판으로 되돌리기도 같은 창구 · 이력은 doc_template_event)';
create index doc_template_active_template_idx on public.doc_template_active (template_id);
create index doc_template_active_set_by_idx   on public.doc_template_active (set_by);

create table public.doc_template_event (
  id               bigint generated always as identity primary key,
  kind             text not null,
  from_template_id uuid references public.doc_template(id),
  to_template_id   uuid not null references public.doc_template(id),
  changed_by       uuid references public.ims_staff(id),
  changed_at       timestamptz not null default now(),
  constraint doc_template_event_kind_ck check (kind in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt')),
  constraint doc_template_event_move_ck check (from_template_id is distinct from to_template_id)
);
comment on table public.doc_template_event is 'doc-1a — 판 쓰기 · 되돌리기 한 번 = 한 줄(from → to · 처음 쓰기는 from null) · 고치지도 지우지도 않는다(doc_rows_guard) · 같은 판을 다시 쓰면 줄이 안 생긴다';
create index doc_template_event_kind_idx on public.doc_template_event (kind, changed_at);
create index doc_template_event_from_idx on public.doc_template_event (from_template_id);
create index doc_template_event_to_idx   on public.doc_template_event (to_template_id);
create index doc_template_event_by_idx   on public.doc_template_event (changed_by);

create table public.doc_setting (
  kind       text not null,
  key        text not null,
  value      text not null,
  updated_by uuid references public.ims_staff(id),
  updated_at timestamptz not null default now(),
  primary key (kind, key),
  constraint doc_setting_kind_ck check (kind in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt')),
  constraint doc_setting_key_ck  check (key in ('title', 'mail_subject', 'mail_body', 'show_upc', 'show_comment', 'show_charge_code')),
  constraint doc_setting_bool_ck check (key not like 'show\_%' or value in ('true', 'false'))
);
comment on table public.doc_setting is 'doc-1a 안 A · 판정 525 — 문서마다 직원이 고치는 글과 켜고 끄기(kind × key · 어휘 여섯: title · mail_subject · mail_body · show_upc · show_comment · show_charge_code) · show_* 는 true | false 글자 · 쓰기는 doc_setting_set(master)로만 · 지우지 않는다(doc_rows_guard) · 회사 공통 글은 inv_config 의 doc_* 키(ims_doc_config_keys)';
create index doc_setting_updated_by_idx on public.doc_setting (updated_by);
create trigger doc_setting_touch before update on public.doc_setting for each row execute function public.ims_touch();

create function public.doc_rows_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  if tg_table_name = 'doc_template' then
    if tg_op = 'DELETE' then raise exception 'A document layout version is never deleted (version % of %) — publish another version instead — nothing was deleted', old.version, old.kind; end if;
    if new.kind <> old.kind or new.version <> old.version or new.body <> old.body or new.check_result <> old.check_result or new.uploaded_by is distinct from old.uploaded_by or new.uploaded_at <> old.uploaded_at then
      raise exception 'A document layout version cannot be changed once saved (version % of %) — upload a new version — nothing was saved', old.version, old.kind;
    end if;
    return new;
  elsif tg_table_name = 'doc_template_event' then
    raise exception 'Document layout history is never changed or deleted — nothing was %', case when tg_op = 'DELETE' then 'deleted' else 'saved' end;
  else
    raise exception 'Document text settings are never deleted (% of %) — change the value instead — nothing was deleted', old.key, old.kind;
  end if;
end;
$$;
comment on function public.doc_rows_guard() is 'doc-1a — doc_template(body · kind · version · check_result · 올린 사람 · 시각 못 바꿈 · 안 지움 · note 만 바뀐다) · doc_template_event(고치기 · 지우기 거부) · doc_setting(지우기 거부) BEFORE 트리거 · postgres 가 돌려도 막는다(되돌리기는 doc_template_publish 가 옛 판을 다시 쓰는 것)';
revoke all on function public.doc_rows_guard() from public, anon;
create trigger doc_template_guard       before update or delete on public.doc_template       for each row execute function public.doc_rows_guard();
create trigger doc_template_event_guard before update or delete on public.doc_template_event for each row execute function public.doc_rows_guard();
create trigger doc_setting_guard        before delete           on public.doc_setting        for each row execute function public.doc_rows_guard();

-- ═══ ② 회사 글 — inv_config 키 여섯 · 검사 · inv_config_guard 재발행 · 시드 ═══
create function public.ims_doc_config_keys() returns text[]
  language sql immutable
  set search_path = public, pg_temp
as $$
  select array['doc_company_name', 'doc_hst', 'doc_website', 'doc_terms', 'doc_branches', 'doc_logo_path'];
$$;
comment on function public.ims_doc_config_keys() is 'doc-1a 판정 524 · 525 — inv_config 의 회사 글 키 여섯(모든 문서의 머리 · 꼬리가 읽는다 · doc_config) · inv_config_guard 의 문서 갈래(값 검사 누가 쓰든 · 화면 쓰기는 master · 삭제 · 이름 바꾸기 거부)가 읽는다 · 메일 키(ims_mail_config_keys)와 같은 꼴';
revoke all on function public.ims_doc_config_keys() from public, anon;
grant execute on function public.ims_doc_config_keys() to authenticated, service_role;

create function public.ims_doc_config_problem(p_key text, p_value text, p_delete boolean default false) returns text
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_j jsonb;
  v_e jsonb;
  v_codes text[] := '{}';
begin
  if p_delete then return 'cannot be removed — change its value instead'; end if;
  if p_value is null then return 'cannot be empty (null)'; end if;
  case p_key
  when 'doc_company_name' then
    if btrim(p_value) = '' or length(p_value) > 120 then return 'must be the company name (1 to 120 characters)'; end if;
  when 'doc_hst' then
    if length(p_value) > 40 then return 'must be at most 40 characters'; end if;
  when 'doc_website' then
    if length(p_value) > 100 or p_value ~ '[[:space:]<>"'']' then return 'must be a web address like asung.ca (at most 100 characters · no spaces or quotes)'; end if;
  when 'doc_terms' then
    if length(p_value) > 10000 then return 'must be at most 10000 characters'; end if;
    if p_value ~* '<script[[:space:]>/]' or p_value ~* '<[^>]*[[:space:]]on[a-z]+[[:space:]]*=' then return 'must not contain script or on…= attributes'; end if;
  when 'doc_branches' then
    begin
      v_j := p_value::jsonb;
    exception when others then
      return 'must be JSON like [{"code":"TOR","label":"Toronto","line1":"…","line2":"…","phone":"…","email":"…"}, {"code":"EDM", …}]';
    end;
    if jsonb_typeof(v_j) <> 'array' or jsonb_array_length(v_j) <> 2 then return 'must be a JSON list of exactly two branches (TOR and EDM — ruling 524: both are printed on every document)'; end if;
    for v_e in select x from jsonb_array_elements(v_j) x loop
      if jsonb_typeof(v_e) <> 'object' or coalesce((select array_agg(k order by k) from jsonb_object_keys(v_e) k), '{}') <> array['code', 'email', 'label', 'line1', 'line2', 'phone']
         or exists (select 1 from jsonb_each(v_e) t where jsonb_typeof(t.value) <> 'string') then
        return 'each branch needs exactly code, label, line1, line2, phone, email — all text (empty allowed)';
      end if;
      if v_e->>'code' not in ('TOR', 'EDM') then return format('branch code must be TOR or EDM (got %s)', v_e->>'code'); end if;
      if exists (select 1 from jsonb_each_text(v_e) t where length(t.value) > 200) then return format('branch %s: a value is longer than 200 characters', v_e->>'code'); end if;
      v_codes := array_append(v_codes, v_e->>'code');
    end loop;
    if (select array_agg(c order by c) from unnest(v_codes) c) <> array['EDM', 'TOR'] then return 'must have one TOR branch and one EDM branch'; end if;
  when 'doc_logo_path' then
    if p_value <> '' then
      if p_value !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$' or p_value ~ '\.\.' then return format('must be empty or a file path inside the doc-brand bucket (got %s)', p_value); end if;
      if not exists (select 1 from storage.objects o where o.bucket_id = 'doc-brand' and o.name = p_value) then return format('%s is not in the doc-brand bucket — upload the logo first', p_value); end if;
    end if;
  else
    return 'is not a document setting';
  end case;
  return null;
end;
$$;
comment on function public.ims_doc_config_problem(text, text, boolean) is 'doc-1a — 회사 글 키 여섯의 값 검사(inv_config_guard 가 부른다 · 누가 쓰든): null = 통과 · 아니면 거부 문장. doc_branches = 지점 둘(TOR · EDM 고정 · 칸 여섯 전부 글자 · 빈 칸 허용 · 창고 id 와 엮지 않는다 — 판정 524 「두 지점을 늘 함께」) · doc_logo_path = 빈 값 또는 doc-brand 버킷에 실재하는 경로 · doc_terms 는 글(script · on…= 만 막는다 · 판은 따로 거부) · 지우기 거부';
revoke all on function public.ims_doc_config_problem(text, text, boolean) from public, anon;
grant execute on function public.ims_doc_config_problem(text, text, boolean) to authenticated, service_role;

-- inv_config_guard 재발행 — 원본 20261016123721_mail_1a_base.sql:257 바이트 + 더한 줄(doc-1a · 지키는 키에 문서 키 여섯 · 문서 갈래 = 값 검사 누가 쓰든 · 화면은 master · 삭제 금지)만
create or replace function public.inv_config_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  v_key   text := coalesce(new.key, old.key);
  v_staff public.ims_staff%rowtype;
  v_guarded text[] := public.ims_config_locked_keys() || public.ims_mail_config_keys() || public.ims_doc_config_keys() || array['so_invoice_unit_display', 'db_role'];   -- mail-1a 이견 2: 지키는 키 전부 · doc-1a: 문서 키 여섯
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
  -- doc-1a 판정 525: 회사 글 키 여섯 — 값 검사는 누가 쓰든(ims_doc_config_problem · 지우기 거부 포함) · 화면에서는 master · updated_by 채움
  if v_key = any (public.ims_doc_config_keys()) then
    v_problem := public.ims_doc_config_problem(v_key, new.value, tg_op = 'DELETE');
    if v_problem is not null then
      raise exception 'inv_config.% % — nothing was saved', v_key, v_problem;
    end if;
    if current_user = 'authenticated' then
      if not public.ims_can_write('master') then
        raise exception 'Changing % needs the master permission — nothing was saved', v_key;
      end if;
      new.updated_at := now();
      new.updated_by := (select s.id from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active);
    end if;
    return new;
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
comment on function public.inv_config_guard() is 'inv_config BEFORE INSERT · UPDATE · DELETE — 키마다 규칙(dsc-3a · 판정 314 · mail-1a · doc-1a): 지키는 키(잠긴 키 셋 · so_invoice_unit_display · 메일 키 일곱 · 문서 키 여섯 · db_role)는 화면에서 이름 바꾸기 거부(옛 이름 · 새 이름 둘 다 본다) · db_role 은 postgres(마이그레이션)만 · 메일 키 일곱(ims_mail_config_keys)은 ims_mail_config_problem 검사(누가 쓰든) + 화면에서는 mail_enabled · mail_redirect_to 는 admin · 나머지는 master · 삭제 금지 · 문서 키 여섯(ims_doc_config_keys)은 ims_doc_config_problem 검사(누가 쓰든 · 삭제 거부 포함) + 화면에서는 master(판정 525) · so_invoice_unit_display 는 both · discounted · net 만 + 화면에서는 master 만 · 잠긴 키 셋(ims_config_locked_keys · 백오더 만료 · 재입고 수수료)은 양의 정수 + supervisor 이상 + 삭제 금지 · 그 밖의 키는 종전 그대로';

-- 시드 — 이미 있으면 안 덮는다 · 값은 Caleb 이 올린 Cin7 양식의 원문 그대로(doc-1a 📌 · 고치기는 Settings) · 에드먼튼은 비움
insert into public.inv_config (key, value, note) values
  ('doc_company_name', 'Asung Trading Inc.', 'doc-1a 판정 525 — 문서 머리의 회사 이름 · 바꾸기 master'),
  ('doc_hst',          '80097 4511 RT0001', 'doc-1a — HST 번호(다섯 문서가 한 값을 읽는다 · Cin7 양식에는 따로 박혀 있었다) · 바꾸기 master'),
  ('doc_website',      'asung.ca',          'doc-1a — 문서 머리의 웹 주소 · 바꾸기 master'),
  ('doc_terms',        '(1) All claims must be made within 3 days of receipt of shipment. (2) Returns will be accepted within 15days of receipt of shipment with return notice. (3) 20% of the restocking fee will be applied for returns after 15 days of receipt of shipment. (4) Returns will not be accepted over 30 days of receipt of shipment. (5) No returns or exchanges on final sale / wigs / ponytails / braids / weaves / PPE / customized items. (6) $20 will be charged for all returned checks. (7) All past due invoices subject to 2% per month maximum finance charge. (8) All prices are subject to change without prior notice. (9) Asung Trading, Inc., reserves the right to limit order quantities.',
                                            'doc-1a — Terms & Conditions 아홉 줄(Cin7 양식 원문 그대로 · 「15days」 띄어쓰기 포함 · 고치기는 Settings) · 바꾸기 master'),
  ('doc_branches',     '[{"code":"TOR","label":"Toronto","line1":"35 Suntract Rd","line2":"North York ON M9N 2V8","phone":"+1 (416) 792-2298","email":"info@asung.ca"},{"code":"EDM","label":"Edmonton","line1":"","line2":"","phone":"","email":""}]',
                                            'doc-1a 판정 524 — 지점 둘(TOR · EDM)을 모든 문서 머리에 함께 찍는다 · 창고와 엮지 않는다 · 에드먼튼은 Caleb 이 Settings 에서 채운다 · 바꾸기 master'),
  ('doc_logo_path',    '',                  'doc-1a — doc-brand 버킷 안 로고 경로(빈 값 = 로고 없음 · 화면 · EF 가 /storage/v1/object/public/doc-brand/<경로> 로 읽는다) · 바꾸기 master')
  on conflict (key) do nothing;

-- ═══ ③ 판 쓰기 열쇠 — ims_perm_catalog 재발행(원본 20261009170919_shop_1a_store.sql:121 바이트 + doc_template 한 줄) · ims_can_doc_template ═══
create or replace function public.ims_perm_catalog() returns jsonb
  language sql immutable
  set search_path = public, pg_temp
as $$
  select '{
    "modes": ["wms", "ims"],
    "screens": {
      "shopify":    {"room": "ims", "min_role": "manager", "label": "Shopify stores, product push, stock sync (manager and above · shop-1a)"},
      "purchasing": {"room": "ims", "label": "Purchase orders, invoices, charges, payments"},
      "master":     {"room": "ims", "label": "Settings, suppliers, products, families, supplier products, prices, product tags, deals"},
      "receiving":  {"room": "ims", "label": "Receiving and putaway"},
      "staff":      {"room": "ims", "label": "Adding and editing people (below your own rank)"},
      "sales":      {"room": "ims", "label": "Sales orders, customer addresses and contacts"},
      "picking":     {"room": "wms", "label": "Picking — pick tasks, waves, holds"},
      "packing":     {"room": "wms", "label": "Packing — pack tasks, pallets, boxes"},
      "fulfillment": {"room": "wms", "label": "Fulfillment — finalize, shipping, manager review"},
      "wms_manage":  {"room": "wms", "min_role": "manager", "label": "Warehouse management — batches, waves, rollbacks (manager and above)"},
      "wms_receiving":         {"room": "wms", "label": "Warehouse receiving — count, put away, hold, off-PO"},
      "wms_receiving_confirm": {"room": "wms", "min_role": "manager", "label": "Warehouse receiving — confirm a receipt (manager and above · off until switched on)"},
      "stock_adjust":          {"room": "ims", "min_role": "manager", "label": "Stock adjustments — draft and confirm (manager and above · off until switched on)"},
      "stock_move":            {"room": "wms", "label": "Bin moves — move stock between bins in one warehouse (person by person · off until switched on)"},
      "transfer":              {"room": "ims", "label": "Transfers — warehouse to warehouse (person by person · off until switched on)"},
      "doc_template":          {"room": "ims", "min_role": "supervisor", "label": "Document templates — publish a layout version (admin always · supervisor only when switched on · off until switched on)"}
    }
  }'::jsonb;
$$;
comment on function public.ims_perm_catalog() is
  '권한 카탈로그 — modes · screens(room · min_role · label) · ⭐ [2026-10-19 doc-1a] screens.doc_template(ims 방 · supervisor 이상 · 판 올리기 · 쓰기 — 문은 ims_can_doc_template 하나 · ⚠️ ims_can_write(doc_template) 은 supervisor 전원 true 라 쓰지 않는다 · 판정 522) · [2026-10-09 shop-1a] screens.shopify(ims 방 · manager 이상 · Shopify 스토어 설정 · 상품 보내기 · 재고 올리기 — 창구 shop_store_save 는 admin 문 · EF shopify 의 직원 길은 ims_can_write(shopify)) · 그 앞 이력은 20260928201753 의 comment';

create function public.ims_can_doc_template() returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case when s.role = 'admin' then true
                when s.role = 'supervisor' then s.perms ? 'doc_template'     -- 판정 522 — Staff 에서 그 사람에게 켰을 때만
                else false end                                               -- manager · worker 는 열쇠가 있어도 못 한다(ims_can_adjust 와 다르다 — doc-0 이견 3)
    from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active), false);
$$;
comment on function public.ims_can_doc_template() is '판 올리기 · 쓰기(doc_template_upload · doc_template_publish)의 문 — admin 은 역할로 · supervisor 는 perms ? doc_template(직접 켠 사람만 · 판정 522) · manager · worker 는 늘 false · ⚠️ ims_can_write(doc_template) 을 대신 쓰면 supervisor 전원에게 열린다(doc-0 이견 3)';
revoke all on function public.ims_can_doc_template() from public, anon;
grant execute on function public.ims_can_doc_template() to authenticated, service_role;

-- ═══ ④ 로고 버킷 doc-brand — 공개 읽기 · png · jpeg · 2 MB · 쓰기 master(product-images 선례 20261001152712:80) ═══
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('doc-brand', 'doc-brand', true, 2097152, array['image/png', 'image/jpeg'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists doc_brand_insert on storage.objects;
drop policy if exists doc_brand_update on storage.objects;
drop policy if exists doc_brand_delete on storage.objects;
create policy doc_brand_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'doc-brand' and (select public.ims_can_write('master')));
create policy doc_brand_update on storage.objects for update to authenticated
  using (bucket_id = 'doc-brand' and (select public.ims_can_write('master')))
  with check (bucket_id = 'doc-brand' and (select public.ims_can_write('master')));
create policy doc_brand_delete on storage.objects for delete to authenticated
  using (bucket_id = 'doc-brand' and (select public.ims_can_write('master')));

-- ═══ ⑤ 자리표 목록 — 판과 doc-1b 데이터 창구의 계약 ═══
create function public.doc_field_catalog(p_kind text) returns jsonb
  language plpgsql immutable
  set search_path = public, pg_temp
as $$
declare
  v_common   text[] := array['company.name', 'company.hst', 'company.website', 'company.logo_url', 'company.terms',
                             'branches.code', 'branches.label', 'branches.line1', 'branches.line2', 'branches.phone', 'branches.email',
                             'doc.kind', 'doc.title', 'doc.printed_at', 'show.upc', 'show.comment', 'show.charge_code',
                             'bill_to.name', 'bill_to.line1', 'bill_to.line2', 'bill_to.city', 'bill_to.state_province', 'bill_to.postal_code', 'bill_to.country', 'bill_to.email', 'bill_to.phone'];
  v_ship     text[] := array['company', 'contact', 'phone', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country'];
  v_line     text[] := array['no', 'upc', 'sku', 'description', 'comment', 'unit', 'qty', 'list_price', 'discount_pct', 'unit_price', 'net_unit_price', 'amount', 'tax_amount', 'is_free', 'no_price'];
  v_charge   text[] := array['no', 'so_number', 'code', 'description', 'comment', 'qty', 'unit_price', 'discount_pct', 'amount', 'tax_amount'];
  v_money    text[] := array['no', 'reference', 'date', 'method', 'amount'];
  v_tot_inv  text[] := array['lines_before_tax', 'lines_tax', 'lines_total', 'charges_before_tax', 'charges_tax', 'charges_total', 'order_discount', 'surcharge', 'charges_discount',
                             'before_tax', 'tax', 'total', 'deposit_applied', 'credit_applied', 'balance_forward', 'paid', 'due_label', 'due_amount'];
  v_tot_cr   text[] := array['lines_before_tax', 'lines_tax', 'lines_total', 'charges_before_tax', 'charges_tax', 'charges_total', 'restocking_fee', 'before_tax', 'tax', 'total', 'applied', 'remaining'];
  v_tot_so   text[] := array['lines_before_tax', 'lines_tax', 'lines_total', 'charges_before_tax', 'charges_tax', 'charges_total', 'order_discount', 'surcharge', 'charges_discount',
                             'before_tax', 'tax', 'total', 'prepaid', 'due_amount'];
  v_allowed  text[];
  v_sections text[] := array['branches'];
  v_required text[];
  v_x text;
begin
  if p_kind not in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt') then
    raise exception 'Unknown document kind % — final_invoice, credit_note, sales_order, ship_ready or internal_receipt', coalesce(p_kind, '(null)');
  end if;
  v_allowed := v_common;
  if p_kind in ('final_invoice', 'ship_ready', 'internal_receipt') then
    v_allowed := v_allowed || array['invoice.date', 'invoice.due_date', 'invoice.terms', 'invoice.currency', 'invoice.memo', 'invoice.total_qty'];
    v_allowed := v_allowed || case when p_kind = 'ship_ready' then array['invoice.calc_at'] else array['invoice.number'] end;
    v_allowed := v_allowed || array['orders.so_number', 'orders.reference', 'orders.carrier', 'orders.tracking', 'orders.tax_rule'];
    foreach v_x in array v_ship   loop v_allowed := v_allowed || ('orders.ship_to.' || v_x); end loop;
    foreach v_x in array v_line   loop v_allowed := v_allowed || ('orders.lines.' || v_x); end loop;
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('charges.' || v_x); end loop;
    foreach v_x in array v_money  loop v_allowed := v_allowed || ('payments.' || v_x); end loop;
    foreach v_x in array v_tot_inv loop v_allowed := v_allowed || ('totals.' || v_x); end loop;
    v_sections := v_sections || array['orders', 'orders.lines', 'charges', 'payments'];
    v_required := case p_kind when 'final_invoice'    then array['invoice.number', 'orders.lines', 'totals.tax', 'totals.total', 'totals.due_amount']
                              when 'ship_ready'       then array['invoice.calc_at', 'orders.lines', 'totals.tax', 'totals.total', 'totals.due_amount']
                              else                         array['invoice.number', 'invoice.total_qty', 'totals.total', 'totals.due_amount'] end;
  elsif p_kind = 'credit_note' then
    v_allowed := v_allowed || array['credit.number', 'credit.date', 'credit.invoice_number', 'credit.reference', 'credit.reason', 'credit.currency', 'credit.memo'];
    foreach v_x in array v_ship   loop v_allowed := v_allowed || ('ship_to.' || v_x); end loop;
    foreach v_x in array v_line   loop v_allowed := v_allowed || ('lines.' || v_x); end loop;
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('charges.' || v_x); end loop;
    foreach v_x in array v_money  loop v_allowed := v_allowed || ('refunds.' || v_x); end loop;
    foreach v_x in array v_tot_cr loop v_allowed := v_allowed || ('totals.' || v_x); end loop;
    v_sections := v_sections || array['lines', 'charges', 'refunds'];
    v_required := array['credit.number', 'lines', 'totals.tax', 'totals.total'];
  else
    v_allowed := v_allowed || array['so.number', 'so.date', 'so.status', 'so.required_by', 'so.terms', 'so.reference', 'so.currency', 'so.memo'];
    foreach v_x in array v_ship   loop v_allowed := v_allowed || ('ship_to.' || v_x); end loop;
    foreach v_x in array v_line   loop v_allowed := v_allowed || ('lines.' || v_x); end loop;
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('charges.' || v_x); end loop;
    foreach v_x in array v_money  loop v_allowed := v_allowed || ('prepayments.' || v_x); end loop;
    foreach v_x in array v_tot_so loop v_allowed := v_allowed || ('totals.' || v_x); end loop;
    v_sections := v_sections || array['lines', 'charges', 'prepayments'];
    v_required := array['so.number', 'lines', 'totals.tax', 'totals.total'];
  end if;
  return jsonb_build_object('kind', p_kind, 'allowed', to_jsonb(v_allowed), 'sections', to_jsonb(v_sections), 'required', to_jsonb(v_required));
end;
$$;
comment on function public.doc_field_catalog(text) is 'doc-1a ⑥ — 문서 kind 마다 판이 쓸 수 있는 자리표(allowed · 경로 꼴 orders.lines.sku = {{#orders}}{{#lines}}{{sku}}) · 목록 섹션(sections · 스코프를 미는 것 — 그 밖의 자리표도 {{#x}}…{{/x}} 조건으로 쓸 수 있으나 스코프를 밀지 않는다) · 필수(required · 섹션 이름은 섹션으로 써야 한다) · ⭐ doc-1b 데이터 창구는 이 목록과 똑같은 열쇠를 내야 한다(doc-1b 검증이 대조) · doc-0 Q2 와 다른 곳: bill_to · ship_to 에 city · state_province · postal_code · country(IMS 칸이 따로다) · charges.so_number · *.method · 크레딧 · SO 의 totals 는 제 것(deposit · balance_forward 없음)';
revoke all on function public.doc_field_catalog(text) from public, anon;
grant execute on function public.doc_field_catalog(text) to authenticated, service_role;

-- ═══ ⑥ 검사기 — mode template(판 · 필수 검사) | text(제목 · 메일 글 · 필수 없음) ═══
create function public.doc_template_check(p_kind text, p_body text, p_mode text default 'template') returns jsonb
  language plpgsql immutable
  set search_path = public, pg_temp
as $$
declare
  v_cat      jsonb := public.doc_field_catalog(p_kind);
  v_allowed  text[];
  v_scopes   text[];
  v_required text[];
  v_problems jsonb := '[]'::jsonb;
  v_fields   text[] := '{}';
  v_sections text[] := '{}';
  v_stk_name text[] := '{}';     -- 열린 섹션의 이름(쓴 그대로 · 닫기 짝)
  v_stk_path text[] := '{}';     -- 열린 섹션의 해석 경로 · 스코프를 안 미는 조건 섹션은 ''
  v_m        text[];
  v_raw      text;
  v_inner    text;
  v_name     text;
  v_path     text;
  v_k        int;
  v_tag      text;
  v_i        int := 0;
  v_fb       text;
  c_max      constant int := 204800;
begin
  if p_mode not in ('template', 'text') then raise exception 'p_mode must be template or text'; end if;
  select array_agg(x) into v_allowed  from jsonb_array_elements_text(v_cat->'allowed')  x;
  select array_agg(x) into v_scopes   from jsonb_array_elements_text(v_cat->'sections') x;
  select array_agg(x) into v_required from jsonb_array_elements_text(v_cat->'required') x;
  if p_body is null or btrim(p_body) = '' then
    return jsonb_build_object('ok', false, 'problems', jsonb_build_array(jsonb_build_object('code', 'empty', 'message', 'The template is empty')), 'warnings', '[]'::jsonb, 'fields', '[]'::jsonb, 'sections', '[]'::jsonb, 'bytes', 0);
  end if;
  if octet_length(p_body) > c_max then
    v_problems := v_problems || jsonb_build_object('code', 'too_large', 'message', format('The template is %s bytes — the limit is %s', octet_length(p_body), c_max));
  end if;
  -- 금지 HTML(판정 402 의 목록에서 iframe 은 통째로 거부 · + @import · 바깥 주소 · 거르지 않고 거부한다)
  foreach v_fb in array array['script', 'iframe', 'object', 'embed', 'form', 'meta', 'link', 'base'] loop
    if p_body ~* ('<' || v_fb || '[[:space:]>/]') then v_problems := v_problems || jsonb_build_object('code', 'forbidden_' || v_fb, 'message', format('<%s> is not allowed in a document template', v_fb)); end if;
  end loop;
  if p_body ~* '<[^>]*[[:space:]]on[a-z]+[[:space:]]*='                          then v_problems := v_problems || jsonb_build_object('code', 'event_attr',      'message', 'on…= attributes (onload, onclick, …) are not allowed'); end if;
  if p_body ~* 'javascript[[:space:]]*:'                                        then v_problems := v_problems || jsonb_build_object('code', 'javascript_link', 'message', 'javascript: is not allowed'); end if;
  if p_body ~* '@import'                                                        then v_problems := v_problems || jsonb_build_object('code', 'style_import',    'message', '@import is not allowed — put the CSS in the template'); end if;
  if p_body ~* '(src|href|action|poster|data|background)[[:space:]]*=[[:space:]]*["'']?[[:space:]]*(https?:)?//' or p_body ~* 'url[[:space:]]*\([[:space:]]*["'']?[[:space:]]*(https?:)?//' then
    v_problems := v_problems || jsonb_build_object('code', 'external_url', 'message', 'Outside addresses (http://, https://, //) are not allowed — the logo comes from {{company.logo_url}}');
  end if;
  -- Mustache 꼬리표 — {{{ · {{& · {{> · {{= 거부 · 나머지 훑기
  if p_body ~ '\{\{\{' then v_problems := v_problems || jsonb_build_object('code', 'unescaped_triple', 'message', '{{{ … }}} (unescaped) is not allowed — use {{ … }}'); end if;
  for v_m in select regexp_matches(p_body, '\{\{([^}]*)\}\}', 'g') loop
    v_i := v_i + 1;
    v_raw := v_m[1];
    v_inner := btrim(v_raw);
    v_tag := '{{' || v_raw || '}}';
    if v_inner = '' then v_problems := v_problems || jsonb_build_object('code', 'empty_tag', 'message', 'An empty {{ }} tag', 'tag', v_tag); continue; end if;
    case left(v_inner, 1)
    when '!' then continue;                                                                                          -- 주석
    when '&' then v_problems := v_problems || jsonb_build_object('code', 'unescaped_amp', 'message', '{{& … }} (unescaped) is not allowed', 'tag', v_tag); continue;
    when '>' then v_problems := v_problems || jsonb_build_object('code', 'partial',       'message', '{{> … }} (partials) are not allowed', 'tag', v_tag); continue;
    when '=' then v_problems := v_problems || jsonb_build_object('code', 'delimiter',     'message', '{{= … =}} (changing delimiters) is not allowed', 'tag', v_tag); continue;
    when '{' then continue;                                                                                          -- 위 unescaped_triple 이 이미 적었다
    when '/' then
      v_name := btrim(substr(v_inner, 2));
      v_k := cardinality(v_stk_name);
      if v_k = 0 or v_stk_name[v_k] <> v_name then
        v_problems := v_problems || jsonb_build_object('code', 'section_mismatch', 'message', format('{{/%s}} closes nothing that is open%s', v_name, case when v_k > 0 then format(' (expected {{/%s}})', v_stk_name[v_k]) else '' end), 'tag', v_tag);
        continue;
      end if;
      v_stk_name := v_stk_name[1:v_k - 1];  v_stk_path := v_stk_path[1:v_k - 1];
      continue;
    else
      null;
    end case;
    if left(v_inner, 1) in ('#', '^') then v_name := btrim(substr(v_inner, 2)); else v_name := v_inner; end if;
    if v_name !~ '^[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)*$' then
      v_problems := v_problems || jsonb_build_object('code', 'bad_name', 'message', format('"%s" is not a placeholder name (letters, digits, _ and . only)', v_name), 'tag', v_tag);
      if left(v_inner, 1) in ('#', '^') then v_stk_name := v_stk_name || v_name; v_stk_path := v_stk_path || ''::text; end if;
      continue;
    end if;
    -- 경로 해석 — 안쪽 스코프부터 바깥으로(Mustache 가 문맥을 거슬러 찾는 것과 같다)
    v_path := null;
    for v_k in reverse cardinality(v_stk_path)..0 loop
      v_fb := case when v_k = 0 then v_name else case when v_stk_path[v_k] = '' then null else v_stk_path[v_k] || '.' || v_name end end;
      if v_fb is not null and (v_fb = any (v_allowed) or v_fb = any (v_scopes)) then v_path := v_fb; exit; end if;
    end loop;
    if v_path is null then
      v_problems := v_problems || jsonb_build_object('code', 'unknown_field', 'message', format('"%s" is not a placeholder of %s%s', v_name, p_kind, case when cardinality(v_stk_path) > 0 then format(' inside {{#%s}}', v_stk_name[cardinality(v_stk_name)]) else '' end), 'tag', v_tag);
      if left(v_inner, 1) in ('#', '^') then v_stk_name := v_stk_name || v_name; v_stk_path := v_stk_path || ''::text; end if;
      continue;
    end if;
    if left(v_inner, 1) = '#' then
      v_stk_name := v_stk_name || v_name;
      v_stk_path := v_stk_path || case when v_path = any (v_scopes) then v_path else ''::text end;
      if v_path = any (v_scopes) then v_sections := v_sections || v_path; else v_fields := v_fields || v_path; end if;
    elsif left(v_inner, 1) = '^' then
      v_stk_name := v_stk_name || v_name;  v_stk_path := v_stk_path || ''::text;
      if not (v_path = any (v_scopes)) then v_fields := v_fields || v_path; end if;
    else
      if v_path = any (v_scopes) then
        v_problems := v_problems || jsonb_build_object('code', 'section_as_value', 'message', format('"%s" is a list — use {{#%s}} … {{/%s}}', v_name, v_name, v_name), 'tag', v_tag);
      else
        v_fields := v_fields || v_path;
      end if;
    end if;
  end loop;
  if cardinality(v_stk_name) > 0 then
    v_problems := v_problems || jsonb_build_object('code', 'section_unclosed', 'message', format('{{#%s}} is never closed', v_stk_name[cardinality(v_stk_name)]));
  end if;
  if v_i = 0 then v_problems := v_problems || jsonb_build_object('code', 'no_placeholders', 'message', 'The template has no {{ }} placeholders at all'); end if;
  select coalesce(array_agg(distinct f order by f), '{}') into v_fields   from unnest(v_fields)   f;
  select coalesce(array_agg(distinct s order by s), '{}') into v_sections from unnest(v_sections) s;
  if p_mode = 'template' then
    foreach v_fb in array v_required loop
      if not (v_fb = any (v_fields) or v_fb = any (v_sections)) then
        v_problems := v_problems || jsonb_build_object('code', 'required_missing', 'message', format('Required placeholder %s is missing%s', v_fb, case when v_fb = any (v_scopes) then format(' (as a section {{#%s}} … {{/%s}})', v_fb, v_fb) else '' end));
      end if;
    end loop;
  end if;
  return jsonb_build_object('ok', jsonb_array_length(v_problems) = 0, 'problems', v_problems, 'warnings', '[]'::jsonb,
                            'fields', to_jsonb(v_fields), 'sections', to_jsonb(v_sections), 'bytes', octet_length(p_body), 'tags', v_i);
end;
$$;
comment on function public.doc_template_check(text, text, text) is 'doc-1a ⑦ — 판(mode template) · 글(mode text · 제목 · 메일 글)의 검사: 크기 200 KB · 금지 HTML(script · iframe · object · embed · form · meta · link · base · on…= · javascript: · @import · 바깥 주소 — 거르지 않고 거부) · Mustache 꼬리표는 {{x}} · {{#x}} · {{^x}} · {{/x}} · {{! }} 만({{{ }}} · {{& }} · {{> }} · {{= =}} 거부) · 섹션 열고 닫기 짝 · 이름은 doc_field_catalog 의 경로로 해석(안쪽 스코프 → 바깥 · 목록 섹션만 스코프를 민다) · 목록을 값으로 쓰면 거부 · template 이면 필수 자리표 · 반환 {ok, problems[{code, message, tag?}], warnings, fields, sections, bytes, tags} · 통과 = problems 0 · ⚠️ 엔티티 인코딩 · 속성 값 안 > 같은 우회는 안 잡는다(올리는 사람은 열쇠를 가진 직원 · 화면은 sandbox iframe 으로 그린다)';
revoke all on function public.doc_template_check(text, text, text) from public, anon;
grant execute on function public.doc_template_check(text, text, text) to authenticated, service_role;

-- ═══ ⑦ 창구 ═══
create function public.doc_staff_or_service() returns uuid
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if coalesce(current_setting('request.jwt.claims', true), '') <> '' and (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'service_role' then return null; end if;
  select s.id into v_id from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_id is null then raise exception 'You are not registered as active staff — nothing was read'; end if;
  return v_id;
end;
$$;
comment on function public.doc_staff_or_service() is 'doc-1a 읽기 창구의 문 — 활성 직원이면 그 id · service_role(EF doc-2)이면 null · 아니면 거부';
revoke all on function public.doc_staff_or_service() from public, anon, authenticated;

create function public.doc_template_upload(p_kind text, p_body text, p_note text default null, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_check jsonb;
  v_t     public.doc_template%rowtype;
begin
  if not public.ims_can_doc_template() then
    raise exception 'Publishing document layouts needs the doc_template key (an admin, or a supervisor with the key switched on) — nothing was saved';
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if p_kind not in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt') then
    raise exception 'Unknown document kind % — nothing was saved', coalesce(p_kind, '(null)');
  end if;
  v_check := public.doc_template_check(p_kind, p_body, 'template');
  if not p_commit or not (v_check->>'ok')::boolean then
    return jsonb_build_object('committed', false, 'kind', p_kind, 'check', v_check, 'next_version', (select coalesce(max(t.version), 0) + 1 from public.doc_template t where t.kind = p_kind));
  end if;
  perform 1 from public.doc_template_active a where a.kind = p_kind for update;                 -- 같은 kind 의 번호 매기기를 줄 세운다(없으면 아무 행도 안 잠긴다 — 아래 유니크가 마지막 벽)
  insert into public.doc_template (kind, version, body, check_result, note, uploaded_by)
  values (p_kind, (select coalesce(max(t.version), 0) + 1 from public.doc_template t where t.kind = p_kind), p_body, v_check, nullif(btrim(coalesce(p_note, '')), ''), v_staff)
  returning * into v_t;
  return jsonb_build_object('committed', true, 'kind', p_kind, 'template_id', v_t.id, 'version', v_t.version, 'check', v_check);
end;
$$;
comment on function public.doc_template_upload(text, text, text, boolean) is 'doc-1a — 판 올리기(문 = ims_can_doc_template · 판정 522): p_commit false = 검사만(check · next_version) · true = 검사를 통과하면 version max + 1 로 저장(통과 못 하면 아무 행도 안 남고 check 를 돌려준다) · 올린 판은 아직 쓰이지 않는다(doc_template_publish 가 쓴다) · 화면은 먼저 false 로 검사 → 실제 오더로 미리 보기 → true';
revoke all on function public.doc_template_upload(text, text, text, boolean) from public, anon, service_role;
grant execute on function public.doc_template_upload(text, text, text, boolean) to authenticated;

create function public.doc_template_publish(p_template_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_t     public.doc_template%rowtype;
  v_a     public.doc_template_active%rowtype;
begin
  if not public.ims_can_doc_template() then
    raise exception 'Publishing document layouts needs the doc_template key (an admin, or a supervisor with the key switched on) — nothing was saved';
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  select * into v_t from public.doc_template t where t.id = p_template_id;
  if v_t.id is null then raise exception 'Layout version not found — nothing was saved'; end if;
  if not (v_t.check_result->>'ok')::boolean then
    raise exception 'Version % of % did not pass its checks and cannot be used — nothing was saved', v_t.version, v_t.kind;
  end if;
  select * into v_a from public.doc_template_active a where a.kind = v_t.kind for update;
  if v_a.template_id = v_t.id then
    return jsonb_build_object('changed', false, 'kind', v_t.kind, 'template_id', v_t.id, 'version', v_t.version);
  end if;
  insert into public.doc_template_active (kind, template_id, set_by, set_at) values (v_t.kind, v_t.id, v_staff, now())
  on conflict (kind) do update set template_id = excluded.template_id, set_by = excluded.set_by, set_at = excluded.set_at;
  insert into public.doc_template_event (kind, from_template_id, to_template_id, changed_by) values (v_t.kind, v_a.template_id, v_t.id, v_staff);
  return jsonb_build_object('changed', true, 'kind', v_t.kind, 'template_id', v_t.id, 'version', v_t.version,
                            'from_template_id', v_a.template_id, 'from_version', (select t.version from public.doc_template t where t.id = v_a.template_id));
end;
$$;
comment on function public.doc_template_publish(uuid) is 'doc-1a — 「이 판 쓰기」(문 = ims_can_doc_template · 판정 522): 그 kind 의 쓰는 판을 바꾸고 doc_template_event 에 한 줄 · 옛 판으로 되돌리기도 이 창구(옛 id) · 검사를 통과하지 못한 판은 거부 · 같은 판을 다시 쓰면 changed false · 이력 없음';
revoke all on function public.doc_template_publish(uuid) from public, anon, service_role;
grant execute on function public.doc_template_publish(uuid) to authenticated;

create function public.doc_setting_set(p_kind text, p_key text, p_value text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_check jsonb;
  v_r     public.doc_setting%rowtype;
begin
  perform public.ims_require_write('master', 'saved');                                           -- 판정 525 — 문 하나 · 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if p_kind not in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt') then raise exception 'Unknown document kind % — nothing was saved', coalesce(p_kind, '(null)'); end if;
  if p_key not in ('title', 'mail_subject', 'mail_body', 'show_upc', 'show_comment', 'show_charge_code') then raise exception 'Unknown document setting % — title, mail_subject, mail_body, show_upc, show_comment or show_charge_code — nothing was saved', coalesce(p_key, '(null)'); end if;
  if p_value is null then raise exception 'The value cannot be empty (null) — nothing was saved'; end if;
  if p_key like 'show\_%' then
    if p_value not in ('true', 'false') then raise exception '% must be true or false (got %) — nothing was saved', p_key, p_value; end if;
  elsif p_key = 'title' then
    if btrim(p_value) = '' or length(p_value) > 120 or p_value ~ '[\r\n]' then raise exception 'The title must be one line of 1 to 120 characters — nothing was saved'; end if;
  elsif p_key = 'mail_subject' then
    if length(p_value) > 300 or p_value ~ '[\r\n]' then raise exception 'The mail subject must be one line of at most 300 characters — nothing was saved'; end if;
  else
    if length(p_value) > 20000 then raise exception 'The mail body must be at most 20000 characters — nothing was saved'; end if;
  end if;
  if p_key in ('title', 'mail_subject', 'mail_body') and p_value <> '' then
    v_check := public.doc_template_check(p_kind, p_value, 'text');
    if not (v_check->>'ok')::boolean and (v_check->'problems'->0->>'code') <> 'no_placeholders' then
      raise exception '% of %: % — nothing was saved', p_key, p_kind, v_check->'problems'->0->>'message';
    end if;
  end if;
  insert into public.doc_setting (kind, key, value, updated_by) values (p_kind, p_key, p_value, v_staff)
  on conflict (kind, key) do update set value = excluded.value, updated_by = excluded.updated_by
  returning * into v_r;
  return jsonb_build_object('kind', v_r.kind, 'key', v_r.key, 'value', v_r.value, 'updated_at', v_r.updated_at, 'updated_by', v_r.updated_by);
end;
$$;
comment on function public.doc_setting_set(text, text, text) is 'doc-1a 판정 525 — 문서마다 글 · 켜고 끄기 고치기(문 = ims_require_write(master)): kind 다섯 · key 여섯 어휘 · show_* 는 true | false · title 한 줄 120 · mail_subject 한 줄 300(빈 값 = 메일 제목 없음) · mail_body 20000 · 글 안의 {{ }} 는 doc_template_check(text) 로 검사(모르는 이름 · 금지 HTML 거부 · 자리표 없음은 됨)';
revoke all on function public.doc_setting_set(text, text, text) from public, anon, service_role;
grant execute on function public.doc_setting_set(text, text, text) to authenticated;

create function public.doc_template_list(p_kind text default null) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  perform public.doc_staff_or_service();
  if p_kind is not null and p_kind not in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt') then raise exception 'Unknown document kind %', p_kind; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'kind', t.kind, 'version', t.version, 'note', t.note, 'ok', (t.check_result->>'ok')::boolean, 'bytes', t.check_result->'bytes',
                                                       'uploaded_at', t.uploaded_at, 'uploaded_by', t.uploaded_by, 'uploaded_by_name', s.name,
                                                       'is_active', a.template_id is not null, 'set_at', a.set_at)
                                    order by t.kind, t.version desc)
                   from public.doc_template t
                   left join public.ims_staff s on s.id = t.uploaded_by
                   left join public.doc_template_active a on a.template_id = t.id
                   where p_kind is null or t.kind = p_kind), '[]'::jsonb);
end;
$$;
comment on function public.doc_template_list(text) is 'doc-1a 읽기 — 판 목록(kind 하나 또는 전부 · 최신 번호부터 · body 없음 · is_active = 지금 쓰는 판) · 활성 직원 · service_role';
revoke all on function public.doc_template_list(text) from public, anon;
grant execute on function public.doc_template_list(text) to authenticated, service_role;

create function public.doc_template_get(p_template_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  perform public.doc_staff_or_service();
  return (select to_jsonb(t) || jsonb_build_object('is_active', exists (select 1 from public.doc_template_active a where a.template_id = t.id))
          from public.doc_template t where t.id = p_template_id);
end;
$$;
comment on function public.doc_template_get(uuid) is 'doc-1a 읽기 — 판 한 벌(body 포함 · 없는 id → null) · 활성 직원(인쇄 화면) · service_role(EF doc-2)';
revoke all on function public.doc_template_get(uuid) from public, anon;
grant execute on function public.doc_template_get(uuid) to authenticated, service_role;

create function public.doc_config() returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  perform public.doc_staff_or_service();
  return jsonb_build_object(
    'company',  jsonb_build_object('name', (select c.value from public.inv_config c where c.key = 'doc_company_name'), 'hst', (select c.value from public.inv_config c where c.key = 'doc_hst'),
                                    'website', (select c.value from public.inv_config c where c.key = 'doc_website'), 'terms', (select c.value from public.inv_config c where c.key = 'doc_terms'),
                                    'logo_path', (select c.value from public.inv_config c where c.key = 'doc_logo_path')),
    'branches', (select coalesce(c.value::jsonb, '[]'::jsonb) from public.inv_config c where c.key = 'doc_branches'),
    'settings', (select coalesce(jsonb_object_agg(x.kind, x.kv), '{}'::jsonb) from (select d.kind, jsonb_object_agg(d.key, d.value) kv from public.doc_setting d group by d.kind) x),
    'active',   (select coalesce(jsonb_object_agg(a.kind, jsonb_build_object('template_id', a.template_id, 'version', t.version, 'set_at', a.set_at)), '{}'::jsonb)
                 from public.doc_template_active a join public.doc_template t on t.id = a.template_id),
    'can_publish', public.ims_can_doc_template(), 'can_edit_text', public.ims_can_write('master'),
    'unit_display', (select c.value from public.inv_config c where c.key = 'so_invoice_unit_display'));
end;
$$;
comment on function public.doc_config() is 'doc-1a 읽기 — 화면 · doc-1b 데이터 창구 · doc-2 EF 가 같은 것을 읽는다: company(name · hst · website · terms · logo_path — 공개 주소는 읽는 쪽이 <프로젝트>/storage/v1/object/public/doc-brand/<logo_path> 로 짓는다 · 운영 · 테스트 주소가 다르다) · branches(판정 524 둘) · settings{kind: {key: value}} · active{kind: {template_id, version, set_at}} · can_publish(판정 522) · can_edit_text(판정 525) · unit_display(판정 314) · 활성 직원 · service_role';
revoke all on function public.doc_config() from public, anon;
grant execute on function public.doc_config() to authenticated, service_role;

-- ═══ ⑧ doc_setting 시드 — 다섯 × 여섯 · 이미 있으면 안 덮는다 · 제목은 Cin7 양식의 제목 · 메일 제목은 final_invoice 만 Cin7 원문 · 나머지는 대화 Claude 안(internal_receipt 는 메일 없음 = 빈 값) ═══
insert into public.doc_setting (kind, key, value) values
  ('final_invoice',    'title',            'FINAL INVOICE'),
  ('final_invoice',    'mail_subject',     'FINAL INVOICE {{invoice.number}} - Asung Trading Inc.'),
  ('final_invoice',    'mail_body',        'Dear {{bill_to.name}},' || chr(10) || chr(10) || 'Please find attached your final invoice {{invoice.number}}.' || chr(10) || chr(10) || 'Thank you for your business.'),
  ('credit_note',      'title',            'CUSTOMER CREDIT NOTE'),
  ('credit_note',      'mail_subject',     'CREDIT NOTE {{credit.number}} - Asung Trading Inc.'),
  ('credit_note',      'mail_body',        'Dear {{bill_to.name}},' || chr(10) || chr(10) || 'Please find attached credit note {{credit.number}}.' || chr(10) || chr(10) || 'Thank you for your business.'),
  ('sales_order',      'title',            'SALES ORDER'),
  ('sales_order',      'mail_subject',     'SALES ORDER {{so.number}} - Asung Trading Inc.'),
  ('sales_order',      'mail_body',        'Dear {{bill_to.name}},' || chr(10) || chr(10) || 'Please find attached your sales order {{so.number}}.' || chr(10) || chr(10) || 'Thank you for your business.'),
  ('ship_ready',       'title',            'PROFORMA'),
  ('ship_ready',       'mail_subject',     'PROFORMA INVOICE - Asung Trading Inc.'),
  ('ship_ready',       'mail_body',        'Dear {{bill_to.name}},' || chr(10) || chr(10) || 'Your order is packed and ready to ship. Please find the proforma invoice attached.' || chr(10) || chr(10) || 'Thank you for your business.'),
  ('internal_receipt', 'title',            'INTERNAL USE ONLY INVOICE'),
  ('internal_receipt', 'mail_subject',     ''),
  ('internal_receipt', 'mail_body',        ''),
  ('final_invoice',    'show_upc', 'true'), ('final_invoice',    'show_comment', 'true'), ('final_invoice',    'show_charge_code', 'false'),
  ('credit_note',      'show_upc', 'true'), ('credit_note',      'show_comment', 'true'), ('credit_note',      'show_charge_code', 'false'),
  ('sales_order',      'show_upc', 'true'), ('sales_order',      'show_comment', 'true'), ('sales_order',      'show_charge_code', 'false'),
  ('ship_ready',       'show_upc', 'true'), ('ship_ready',       'show_comment', 'false'), ('ship_ready',       'show_charge_code', 'false'),
  ('internal_receipt', 'show_upc', 'false'), ('internal_receipt', 'show_comment', 'false'), ('internal_receipt', 'show_charge_code', 'false')
  on conflict (kind, key) do nothing;

-- ═══ ⑨ 권한 — RLS 켬 · 정책 없음 · anon · authenticated 표 권한 0(TRUNCATE 포함 · 미룬 247) · 읽기 · 쓰기는 definer 창구로만 ═══
alter table public.doc_template        enable row level security;
alter table public.doc_template_active enable row level security;
alter table public.doc_template_event  enable row level security;
alter table public.doc_setting         enable row level security;
revoke all on public.doc_template, public.doc_template_active, public.doc_template_event, public.doc_setting from anon, authenticated;

-- ═══ ⑩ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from pg_class where oid in ('public.doc_template'::regclass, 'public.doc_template_active'::regclass, 'public.doc_template_event'::regclass, 'public.doc_setting'::regclass) and relrowsecurity) <> 4 then v_bad := v_bad || ' rls'; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('doc_template', 'doc_template_active', 'doc_template_event', 'doc_setting')) <> 0 then v_bad := v_bad || ' policies'; end if;
  if exists (select 1 from information_schema.role_table_grants where table_schema = 'public' and table_name in ('doc_template', 'doc_template_active', 'doc_template_event', 'doc_setting') and grantee in ('anon', 'authenticated')) then v_bad := v_bad || ' table-grants'; end if;
  if (select count(*) from pg_trigger where tgrelid in ('public.doc_template'::regclass, 'public.doc_template_event'::regclass, 'public.doc_setting'::regclass) and not tgisinternal) <> 4 then v_bad := v_bad || ' triggers'; end if;
  if (select count(*) from public.inv_config where key = any (public.ims_doc_config_keys())) <> 6 then v_bad := v_bad || ' config-seed'; end if;
  if (select count(*) from public.inv_config where key = any (public.ims_doc_config_keys()) and public.ims_doc_config_problem(key, value) is not null) <> 0 then v_bad := v_bad || ' config-values'; end if;
  if (select count(*) from public.doc_setting) < 30 then v_bad := v_bad || ' setting-seed'; end if;
  if not (public.ims_perm_catalog()->'screens' ? 'doc_template') or (public.ims_perm_catalog()->'screens'->'doc_template'->>'min_role') <> 'supervisor' then v_bad := v_bad || ' catalog'; end if;
  if (select prosrc from pg_proc where oid = 'public.inv_config_guard()'::regprocedure) !~ 'ims_doc_config_keys' then v_bad := v_bad || ' guard-body'; end if;
  if not exists (select 1 from storage.buckets b where b.id = 'doc-brand' and b.public and b.file_size_limit = 2097152 and b.allowed_mime_types = array['image/png', 'image/jpeg']) then v_bad := v_bad || ' bucket'; end if;
  if (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'doc\_brand\_%') <> 3 then v_bad := v_bad || ' bucket-policies'; end if;
  if (select count(*) from (select k, (public.doc_template_check(k, '<p>{{company.name}}</p>', 'text')->>'ok')::boolean ok from unnest(array['final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt']) k) x where not ok) <> 0 then v_bad := v_bad || ' checker'; end if;
  if has_function_privilege('anon', 'public.doc_template_upload(text, text, text, boolean)', 'execute') or has_function_privilege('anon', 'public.doc_config()', 'execute')
     or has_function_privilege('authenticated', 'public.doc_staff_or_service()', 'execute') or has_function_privilege('service_role', 'public.doc_template_upload(text, text, text, boolean)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM511', message = format('STOP - doc-1a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
