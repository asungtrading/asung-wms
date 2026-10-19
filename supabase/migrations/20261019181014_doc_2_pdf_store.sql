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
-- 20261019181014_doc_2_pdf_store.sql — doc-2 (2026-10-19 · 회사 PC · Fable · 문서 ④ 서버 PDF 의 DB 쪽 — 비공개 버킷 documents · 남긴 PDF 표 doc_file · 창구)
--   판정 521(드라이브는 며칠 뒤 — drive_file_id 칸만) · 523(서버 PDF = Gotenberg · EF doc 이 만든다) · doc-0 Q5(남긴다 · 발행 때의 판으로 다시 · 정말 같은 종이 = 남긴 PDF)
--   ① 버킷 documents — 비공개 · application/pdf · 10 MB · storage.objects 정책 없음(직원은 직접 못 읽고 못 쓴다 · EF 가 service_role 로 올리고 짧은 서명 URL 을 낸다)
--   ② 표 doc_file — 만든 PDF 한 장 = 한 행 · path · sha256 · template_id 는 쓴 뒤 못 바꾸고 지우지 않는다(doc_file_guard) · drive_file_id 는 비어 있을 때 한 번만 채운다
--   ③ 창구 doc_file_add(service_role 만 · EF) · doc_file_drive_set(service_role 만 · 뒤 차수의 드라이브 올리기) · doc_file_list(kind, ref) · doc_file_get(id)(활성 직원 · service_role — EF 가 이것으로 문을 확인한 뒤 서명 URL 을 낸다)
--      ⚠️ 서명 URL 은 SQL 로 못 만든다(storage 스키마에 서명 함수 없음 — 실측) → EF doc 의 action url(이견)
--   무접촉: doc_template · doc_data · 메일 · 화면 · 운영 DB · 첫 문장 = guard-test-only.sql 바이트 복사 · 검증 ~/asung/prompts/doc-2-verify.sql

-- ═══ ① 버킷 ═══
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('documents', 'documents', false, 10485760, array['application/pdf'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- ═══ ② 표 ═══
create table public.doc_file (
  id               uuid primary key default gen_random_uuid(),
  kind             text not null,
  ref              jsonb not null,
  doc_number       text,
  template_id      uuid not null references public.doc_template(id),
  template_version int not null,
  path             text not null,
  bytes            int not null,
  sha256           text not null,
  pages            int,
  reason           text not null,
  made_by          uuid references public.ims_staff(id),
  made_at          timestamptz not null default now(),
  drive_file_id    text,
  note             text,
  constraint doc_file_kind_ck     check (kind in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt')),
  constraint doc_file_ref_ck      check (jsonb_typeof(ref) = 'object'),
  constraint doc_file_reason_ck   check (reason in ('print', 'send', 'reprint', 'preview')),
  constraint doc_file_path_ck     check (path ~ '^(final_invoice|credit_note|sales_order|ship_ready|internal_receipt)/[A-Za-z0-9._-]+\.pdf$'),
  constraint doc_file_path_uq     unique (path),
  constraint doc_file_bytes_ck    check (bytes > 0 and bytes <= 10485760),
  constraint doc_file_sha_ck      check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint doc_file_pages_ck    check (pages is null or pages > 0),
  constraint doc_file_version_ck  check (template_version >= 1)
);
comment on table public.doc_file is 'doc-2 — 서버(Gotenberg)가 만든 PDF 한 장 = 한 행(doc-0 Q5): 어느 문서(kind · ref · doc_number)를 어느 판(template_id · version)으로 언제 누가(made_by · service 면 null) 왜(reason print | send | reprint | preview) 만들었나 · 파일은 비공개 버킷 documents 의 path(<kind>/<이름>.pdf) · sha256 · bytes · ⚠️ 지우지 않는다 · path · sha256 · template_id 는 못 바꾼다(doc_file_guard) · drive_file_id 는 비어 있을 때 한 번만(판정 521 — 며칠 뒤 「null 인 것 전부 올리기」) · 같은 문서를 또 만들면 또 한 줄(두 장 다 남는다)';
create index doc_file_kind_ref_idx on public.doc_file (kind, made_at desc);
create index doc_file_ref_gin on public.doc_file using gin (ref jsonb_path_ops);
create index doc_file_template_idx on public.doc_file (template_id);
create index doc_file_made_by_idx on public.doc_file (made_by);
create index doc_file_drive_null_idx on public.doc_file (made_at) where drive_file_id is null;

create function public.doc_file_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then raise exception 'A stored document PDF is never deleted (%) — nothing was deleted', old.path; end if;
  if new.kind <> old.kind or new.ref <> old.ref or new.doc_number is distinct from old.doc_number or new.template_id <> old.template_id or new.template_version <> old.template_version
     or new.path <> old.path or new.bytes <> old.bytes or new.sha256 <> old.sha256 or new.pages is distinct from old.pages or new.reason <> old.reason
     or new.made_by is distinct from old.made_by or new.made_at <> old.made_at then
    raise exception 'A stored document PDF cannot be changed (%) — only drive_file_id (once) and note — nothing was saved', old.path;
  end if;
  if new.drive_file_id is distinct from old.drive_file_id and old.drive_file_id is not null then
    raise exception 'drive_file_id of % is already set — it is written once — nothing was saved', old.path;
  end if;
  return new;
end;
$$;
revoke all on function public.doc_file_guard() from public, anon;
create trigger doc_file_guard before update or delete on public.doc_file for each row execute function public.doc_file_guard();

-- ═══ ③ 창구 ═══
create function public.doc_is_service() returns boolean
  language sql stable
  set search_path = public, pg_temp
as $$ select coalesce(current_setting('request.jwt.claims', true), '') <> '' and (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'service_role'; $$;
revoke all on function public.doc_is_service() from public, anon, authenticated;

create function public.doc_file_add(p jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_t public.doc_template%rowtype;
  v_r public.doc_file%rowtype;
begin
  if not public.doc_is_service() then raise exception 'doc_file_add is for the document service only — nothing was saved'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'p must be a JSON object — nothing was saved'; end if;
  if nullif(p->>'template_id', '') is null then raise exception 'template_id is required — nothing was saved'; end if;
  select * into v_t from public.doc_template t where t.id = (p->>'template_id')::uuid;
  if v_t.id is null then raise exception 'Layout version % not found — nothing was saved', p->>'template_id'; end if;
  if v_t.kind <> coalesce(p->>'kind', '') then raise exception 'Layout version is for % but the document is % — nothing was saved', v_t.kind, coalesce(p->>'kind', '(null)'); end if;
  if jsonb_typeof(p->'ref') <> 'object' then raise exception 'ref must be a JSON object — nothing was saved'; end if;
  if nullif(p->>'made_by', '') is not null and not exists (select 1 from public.ims_staff s where s.id = (p->>'made_by')::uuid) then raise exception 'made_by is not a staff id — nothing was saved'; end if;
  insert into public.doc_file (kind, ref, doc_number, template_id, template_version, path, bytes, sha256, pages, reason, made_by, note)
  values (p->>'kind', p->'ref', nullif(p->>'doc_number', ''), v_t.id, v_t.version, p->>'path', (p->>'bytes')::int, lower(p->>'sha256'), nullif(p->>'pages', '')::int, p->>'reason', nullif(p->>'made_by', '')::uuid, nullif(p->>'note', ''))
  returning * into v_r;
  return to_jsonb(v_r);
end;
$$;
comment on function public.doc_file_add(jsonb) is 'doc-2 — EF doc 이 PDF 를 버킷에 올린 뒤 한 줄 남긴다(service_role 만 · 직원 로그인은 거부): {kind, ref, doc_number?, template_id, path, bytes, sha256, pages?, reason, made_by?, note?} · template_version 은 판에서 · 어긴 값은 CHECK 가 제 이름으로 거부';
revoke all on function public.doc_file_add(jsonb) from public, anon, authenticated;
grant execute on function public.doc_file_add(jsonb) to service_role;

create function public.doc_file_drive_set(p_id uuid, p_drive_file_id text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_r public.doc_file%rowtype;
begin
  if not public.doc_is_service() then raise exception 'doc_file_drive_set is for the document service only — nothing was saved'; end if;
  if nullif(btrim(coalesce(p_drive_file_id, '')), '') is null then raise exception 'drive_file_id is required — nothing was saved'; end if;
  update public.doc_file f set drive_file_id = btrim(p_drive_file_id) where f.id = p_id returning * into v_r;
  if v_r.id is null then raise exception 'Stored PDF not found — nothing was saved'; end if;
  return to_jsonb(v_r);
end;
$$;
comment on function public.doc_file_drive_set(uuid, text) is 'doc-2 판정 521 — 드라이브에 올린 뒤 그 id 를 한 번 적는다(service_role 만 · 이미 적혀 있으면 doc_file_guard 가 거부) · 올리는 일꾼은 뒤 차수';
revoke all on function public.doc_file_drive_set(uuid, text) from public, anon, authenticated;
grant execute on function public.doc_file_drive_set(uuid, text) to service_role;

create function public.doc_file_list(p_kind text, p_ref jsonb) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  perform public.doc_staff_or_service();
  if p_kind not in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt') then raise exception 'Unknown document kind %', coalesce(p_kind, '(null)'); end if;
  if p_ref is null or jsonb_typeof(p_ref) <> 'object' then raise exception 'p_ref must be a JSON object like {"invoice_id": "…"}'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'doc_number', f.doc_number, 'template_version', f.template_version, 'bytes', f.bytes, 'pages', f.pages, 'reason', f.reason,
                                                       'made_at', f.made_at, 'made_by', f.made_by, 'made_by_name', s.name, 'drive_file_id', f.drive_file_id, 'note', f.note) order by f.made_at desc)
                   from public.doc_file f left join public.ims_staff s on s.id = f.made_by
                   where f.kind = p_kind and f.ref @> p_ref), '[]'::jsonb);
end;
$$;
comment on function public.doc_file_list(text, jsonb) is 'doc-2 읽기 — 그 문서(kind · ref 포함)로 만든 PDF 목록(최신부터 · path 없음 — 파일은 EF doc 의 url 로만) · 활성 직원 · service_role';
revoke all on function public.doc_file_list(text, jsonb) from public, anon;
grant execute on function public.doc_file_list(text, jsonb) to authenticated, service_role;

create function public.doc_file_get(p_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_r public.doc_file%rowtype;
begin
  perform public.doc_staff_or_service();
  select * into v_r from public.doc_file f where f.id = p_id;
  if v_r.id is null then raise exception 'Stored PDF not found'; end if;
  return to_jsonb(v_r);
end;
$$;
comment on function public.doc_file_get(uuid) is 'doc-2 읽기 — PDF 한 줄(path 포함) · 활성 직원 · service_role — EF doc 은 직원 JWT 로 이것을 불러 문을 확인한 뒤 service_role 로 짧은 서명 URL 을 낸다';
revoke all on function public.doc_file_get(uuid) from public, anon;
grant execute on function public.doc_file_get(uuid) to authenticated, service_role;

-- ═══ ④ 권한 · 실물 확인 ═══
alter table public.doc_file enable row level security;
revoke all on public.doc_file from anon, authenticated;
do $$
declare v_bad text := '';
begin
  if not exists (select 1 from storage.buckets b where b.id = 'documents' and not b.public and b.file_size_limit = 10485760 and b.allowed_mime_types = array['application/pdf']) then v_bad := v_bad || ' bucket'; end if;
  if (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and (qual like '%documents%' or with_check like '%documents%')) <> 0 then v_bad := v_bad || ' bucket-policies'; end if;
  if (select count(*) from pg_class where oid = 'public.doc_file'::regclass and relrowsecurity) <> 1 or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'doc_file') <> 0 then v_bad := v_bad || ' rls'; end if;
  if exists (select 1 from information_schema.role_table_grants where table_schema = 'public' and table_name = 'doc_file' and grantee in ('anon', 'authenticated')) then v_bad := v_bad || ' table-grants'; end if;
  if has_function_privilege('authenticated', 'public.doc_file_add(jsonb)', 'execute') or has_function_privilege('anon', 'public.doc_file_get(uuid)', 'execute') or not has_function_privilege('service_role', 'public.doc_file_add(jsonb)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - doc-2 did not land as designed:%s - nothing was changed', v_bad); end if;
end $$;
