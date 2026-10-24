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
-- ═══ drive-1 — IMS → 구글 공유 드라이브 「IMS Documents」 · DB 쪽 (2026-10-24 · 판정 688 ~ 708 · 미룬 260) ═══
--   ① 설정 키 셋 drive_enabled(on|off · 기본 off) · drive_since(YYYY-MM-DD · 빈 값 = 아무것도 넣지 않는다) · drive_root_id(공유 드라이브 id) — 바꾸기 admin(판정 707) · 값 검사 drive_config_guard(누가 쓰든) · ims_config_set 재발행(허용 목록 + 등급 줄)
--   ② doc_file.reason 에 archive(판정 692 보관본) · 문서마다 하나(부분 유니크 doc_file_archive_uq)
--   ③ 표 넷 — drive_folder(폴더 짝 · 693) · po_doc(올린 서류 · 691 · 697 · 703 · 708) · drive_shortcut(바로가기 · 698 · 706) · drive_job(보낼 일 · 상태 waiting_pdf → queued → sending → done | failed | skipped)
--   ④ 버킷 po-documents(비공개 · pdf · jpeg · png · 10 MB · 판정 708) + 정책(insert · update = purchasing 쓰기 · select = purchasing 보기 — 서명 URL · delete 없음)
--   ⑤ 트리거 — so_invoice · so_credit after insert(지연 · 커밋 때 · 발행을 막지 않는다 · 자동 메일 트리거와 같은 꼴) → 보관 일 · after update of status(취소) → 이름 바꾸기 일(704) · po_charge · po_invoice after update of status(confirmed) → 바로가기(698 · 706 · 트랜스퍼 몫 없음 705 · 뺀 PO 의 옛 바로가기 REMOVED_)
--   ⑥ 창구 — 직원: po_doc_add · po_doc_remove · po_doc_list · drive_status / 일꾼(service · doc_is_service): drive_job_claim · drive_job_pdf_set · drive_job_done · drive_job_failed · drive_folder_set
--   파일 이름은 DB 가 만든다(drive_name_clean · 날짜_접두_번호 · 같은 이름 _2 · 701 · 703) · 폴더 자리도 DB 가 정한다(target_scope · target_ref · 694 · 695 · 697 · 698) · 일꾼(drive-2)은 받은 대로 쓴다
--   ⚠️ 보관본 PDF 는 발행 직후 만든다(Due 는 찍는 순간 · 528) — PDF 만들기는 drive_enabled 와 무관 · 드라이브 올리기만 drive_enabled 가 막는다 · drive_since 전 문서는 일을 만들지 않는다
--   기본 권한(판정 615): 새 표 넷은 revoke all 뒤 service_role select 만 · 쓰기는 창구로만 · 무접촉: so_invoice_issue · so_credit_issue · po_charge_confirm · po_invoice_confirm · 메일 기계 · 화면 · 운영 DB
--   앞 차수: doc-2(doc_file · doc_is_service) · doc-3a(자동 메일) · rls-2(ims_config_set) 가 적용되어 있어야 한다 · 검증 ~/asung/prompts/drive-1-verify.sql

do $$
declare v_md5 text;
begin
  if to_regclass('public.doc_file') is null or to_regclass('public.po_charge_alloc') is null or to_regclass('public.shop_order') is null then
    raise exception using errcode = 'IM511', message = 'STOP - doc-2 · po_charge · shop_order must exist before drive-1 - nothing was changed';
  end if;
  if not exists (select 1 from pg_proc where proname = 'doc_is_service' and pronamespace = 'public'::regnamespace) then
    raise exception using errcode = 'IM511', message = 'STOP - doc_is_service (doc-2) is missing - nothing was changed';
  end if;
  select md5(prosrc) into v_md5 from pg_proc where proname = 'ims_config_set' and pronamespace = 'public'::regnamespace;
  if v_md5 is null then raise exception using errcode = 'IM511', message = 'STOP - ims_config_set (rls-2) is missing - nothing was changed'; end if;
  if left(v_md5, 8) <> 'bfaa7491' then
    raise exception using errcode = 'IM511', message = format('STOP - ims_config_set body md5 %s is not the rls-2 body (bfaa7491) this file re-issues - nothing was changed', left(v_md5, 8));
  end if;
  if to_regclass('public.po_doc') is not null or to_regclass('public.drive_job') is not null then
    raise exception using errcode = 'IM511', message = 'STOP - drive-1 tables already exist - nothing was changed';
  end if;
end $$;

-- ═══ ① 설정 키 셋 — 판정 707(셋 다 admin) ═══
create or replace function public.ims_drive_config_keys() returns text[]
  language sql immutable
  set search_path = public, pg_temp
as $$ select array['drive_enabled', 'drive_since', 'drive_root_id']; $$;
revoke all on function public.ims_drive_config_keys() from public, anon;
comment on function public.ims_drive_config_keys() is 'drive-1 판정 707 — 드라이브 설정 키 셋(drive_enabled on|off · drive_since YYYY-MM-DD 또는 빈 값 · drive_root_id) · 바꾸기 admin(ims_config_set) · 값 검사 drive_config_guard';

insert into public.inv_config (key, value, note) values
  ('drive_enabled', 'off',                 'drive-1 판정 688 · 707 — 구글 공유 드라이브 올리기 켜기(on|off · 기본 off · 컷오버 며칠 뒤 Caleb 이 켠다 · 521) · 보관본 PDF 만들기는 이 값과 무관 · 바꾸기 admin'),
  ('drive_since',   '',                    'drive-1 판정 521 · 707 — 이 날짜(YYYY-MM-DD · 토론토) 뒤에 발행 · 올린 문서만 드라이브로 간다 · 빈 값 = 아무것도 넣지 않는다(시험 문서 막기) · 켜는 날 2026-11-01 을 넣는다 · 바꾸기 admin'),
  ('drive_root_id', '0AM8jftaU51hyUk9PVA', 'drive-1 판정 688 · 707 — 공유 드라이브 IMS Documents 의 id(Caleb 2026-10-24) · ims@asung.ca = Contributor · 바꾸기 admin')
  on conflict (key) do nothing;

-- 값 검사 — 누가 쓰든(postgres · service_role · 창구 뒤의 definer 포함) · 지우기는 거부 · inv_config_guard 는 무접촉(같은 표의 둘째 트리거 · 이 키 셋만 본다)
create or replace function public.drive_date_ok(p text) returns boolean
  language plpgsql immutable
  set search_path = public, pg_temp
as $$
begin
  if p is null then return false; end if;
  if p = '' then return true; end if;
  if p !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return false; end if;
  return p::date::text = p;                                                                                            -- 2026-13-40 같은 값은 예외 → false
exception when others then
  return false;
end;
$$;
revoke all on function public.drive_date_ok(text) from public, anon;

create or replace function public.drive_config_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare v_key text := coalesce(new.key, old.key);
begin
  if not (v_key = any (public.ims_drive_config_keys())) and not (tg_op = 'UPDATE' and old.key = any (public.ims_drive_config_keys())) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'DELETE' then raise exception 'inv_config.% cannot be deleted — change its value instead — nothing was deleted', v_key; end if;
  if tg_op = 'UPDATE' and new.key is distinct from old.key then raise exception 'inv_config key % cannot be renamed — nothing was saved', old.key; end if;
  if v_key = 'drive_enabled' and (new.value is null or new.value not in ('on', 'off')) then
    raise exception 'inv_config.drive_enabled must be on or off (got %) — nothing was saved', coalesce(new.value, 'null');
  end if;
  if v_key = 'drive_since' and not public.drive_date_ok(new.value) then
    raise exception 'inv_config.drive_since must be a date YYYY-MM-DD or empty (got %) — nothing was saved', coalesce(new.value, 'null');
  end if;
  if v_key = 'drive_root_id' and (new.value is null or new.value !~ '^[A-Za-z0-9_-]{10,64}$') then
    raise exception 'inv_config.drive_root_id must be a Google Drive id (got %) — nothing was saved', coalesce(new.value, 'null');
  end if;
  return new;
end;
$$;
revoke all on function public.drive_config_guard() from public, anon;
drop trigger if exists drive_config_guard on public.inv_config;
create trigger drive_config_guard before insert or update or delete on public.inv_config for each row execute function public.drive_config_guard();
comment on function public.drive_config_guard() is 'drive-1 판정 707 — 드라이브 키 셋의 값 검사(on|off · 날짜 또는 빈 값 · Drive id 꼴) · 지우기 · 이름 바꾸기 거부 · 다른 키는 그대로 지나간다(inv_config_guard 무접촉)';

-- ═══ ims_config_set 재발행 — 원본 20261020210026_rls_2_config_write_gate.sql:46 ~ 102 바이트 그대로 · 바뀐 줄 1(admin 등급에 드라이브 키 셋) · 더한 줄 1(주석) · 옛 md5 bfaa7491 → 새 3f7bca65 ═══
create or replace function public.ims_config_set(p_key text, p_value text, p_old text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
-- rls-2 · 판정 572 ~ 574 — 화면(settings.html)이 설정 한 키를 저장하는 유일한 길.
--   열쇠 식 한 곳: mail_enabled · mail_redirect_to = admin · 잠긴 3(ims_config_locked_keys) = supervisor 이상 · 나머지 메일 8 · 문서 7 · so_invoice_unit_display = master(mail_settings().edit_level · doc_config().can_edit_text 와 같은 식).
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
  if p_key in ('mail_enabled', 'mail_redirect_to') or p_key = any (public.ims_drive_config_keys()) then v_level := 'admin';
  elsif p_key = any (public.ims_config_locked_keys()) then v_level := 'supervisor';
  elsif p_key = any (public.ims_mail_config_keys()) or (p_key = any (public.ims_doc_config_keys()) and p_key <> 'doc_public_base_url') or p_key = 'so_invoice_unit_display' then v_level := 'master';
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
$$;
comment on function public.ims_config_set(text, text, text) is 'rls-2 판정 572 ~ 574 — 설정 한 키 저장 창구(definer): 허용 21 + 드라이브 3(drive-1 판정 707 · admin)(메일 10 · 문서 7 · so_invoice_unit_display · 잠긴 3) · 등급 admin | supervisor | master · p_old 로 changed_elsewhere · 값 검사는 guard';
revoke all on function public.ims_config_set(text, text, text) from public, anon, service_role;
grant execute on function public.ims_config_set(text, text, text) to authenticated;

-- ═══ ② doc_file.reason 에 archive(판정 692) · 문서마다 보관본 하나 ═══
alter table public.doc_file drop constraint doc_file_reason_ck;
alter table public.doc_file add constraint doc_file_reason_ck check (reason in ('print', 'send', 'reprint', 'preview', 'archive'));
create unique index doc_file_archive_uq on public.doc_file (kind, ref) where reason = 'archive';
comment on index public.doc_file_archive_uq is 'drive-1 판정 692 — 발행 때 모습 한 장(reason archive)은 문서(kind · ref)마다 하나';

-- ═══ ③ 표 넷 ═══
-- 폴더 짝 — 손님 · 공급처 · PO · 비용 빌 · aonebeauty 달 ↔ 드라이브 폴더 id(처음 만들 때 이름 made_name · 이름이 바뀌어도 같은 폴더 · 693)
create table public.drive_folder (
  id            uuid primary key default gen_random_uuid(),
  scope         text not null,
  ref           text not null,
  folder_id     text not null,
  made_name     text not null,
  parent_scope  text,
  parent_ref    text,
  created_at    timestamptz not null default now(),
  constraint drive_folder_scope_ck   check (scope in ('customer', 'supplier', 'po', 'charge', 'aone', 'aone_month')),
  constraint drive_folder_scope_uq   unique (scope, ref),
  constraint drive_folder_id_uq      unique (folder_id),
  constraint drive_folder_id_ck      check (folder_id ~ '^[A-Za-z0-9_-]{10,128}$')
);
comment on table public.drive_folder is 'drive-1 판정 693 — IMS 가 기억하는 드라이브 폴더 짝: customer(ref customer.id · Customers/<이름>) · supplier(supplier.id · Suppliers/<이름>) · po(po.id · Suppliers/<공급처>/<PO 번호>) · charge(po_charge.id · Suppliers/<경비처>/CHARGE-<charge_number>) · aone(고정 ref root · aonebeauty) · aone_month(YYYY-MM · aonebeauty/<YYYY-MM>) · 일꾼이 만들고 drive_folder_set 으로 적는다';
revoke all on public.drive_folder from public, anon, authenticated, service_role;
grant select on public.drive_folder to service_role;

-- 올린 서류 — PO 화면(po_id) 또는 비용 빌 화면(po_charge_id)에서 올린 PDF · 사진 한 장 = 한 행 · 공급처 인보이스(kind invoice)는 po_invoice_id 로 잇는다(706)
create table public.po_doc (
  id             uuid primary key default gen_random_uuid(),
  po_id          uuid references public.po(id),
  po_charge_id   uuid references public.po_charge(id),
  po_invoice_id  uuid references public.po_invoice(id),
  kind           text not null,
  description    text,
  doc_date       date not null default public.ims_today(),
  doc_number     text,
  original_name  text not null,
  path           text not null,
  bytes          int  not null,
  sha256         text not null,
  mime           text not null,
  uploaded_by    uuid not null references public.ims_staff(id),
  uploaded_at    timestamptz not null default now(),
  is_active      boolean not null default true,
  removed_at     timestamptz,
  removed_by     uuid references public.ims_staff(id),
  removed_note   text,
  drive_file_id  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.ims_staff(id),
  constraint po_doc_target_ck      check ((po_id is null) <> (po_charge_id is null)),
  constraint po_doc_kind_ck        check (kind in ('invoice', 'bol', 'coo', 'packing', 'b3', 'other')),
  constraint po_doc_other_ck       check (kind <> 'other' or nullif(btrim(coalesce(description, '')), '') is not null),
  constraint po_doc_desc_ck        check (description is null or length(description) <= 200),
  constraint po_doc_number_ck      check (doc_number is null or (doc_number = btrim(doc_number) and doc_number <> '' and length(doc_number) <= 80)),
  constraint po_doc_invoice_ck     check (po_invoice_id is null or kind = 'invoice'),
  constraint po_doc_path_ck        check (path ~ '^(po|charge)/[0-9a-f-]{36}/[A-Za-z0-9._-]+\.(pdf|jpg|jpeg|png)$'
                                          and path like case when po_id is not null then 'po/' || po_id::text || '/%' else 'charge/' || po_charge_id::text || '/%' end),
  constraint po_doc_path_uq        unique (path),
  constraint po_doc_bytes_ck       check (bytes > 0 and bytes <= 10485760),
  constraint po_doc_sha_ck         check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint po_doc_mime_ck        check (mime in ('application/pdf', 'image/jpeg', 'image/png')),
  constraint po_doc_removed_ck     check (is_active = (removed_at is null) and (removed_at is null) = (removed_by is null))
);
create index po_doc_po_idx     on public.po_doc (po_id) where po_id is not null;
create index po_doc_charge_idx on public.po_doc (po_charge_id) where po_charge_id is not null;
create index po_doc_inv_idx    on public.po_doc (po_invoice_id) where po_invoice_id is not null;
comment on table public.po_doc is 'drive-1 판정 691 · 697 · 698 · 703 · 708 — PO · 비용 빌 화면에서 올린 서류(pdf · jpeg · png · 10 MB · 버킷 po-documents · path po/<po_id>/… | charge/<charge_id>/…) · 종류 여섯(invoice INV_ · bol BOL_ · coo COO_ · packing PACKING_ · b3 B3_ · other OTHER_<설명>_ · Other 는 설명 필수) · 치우기 = is_active false(파일은 둔다 · 드라이브는 REMOVED_ · 704) · 공급처 인보이스는 po_invoice_id 로 이어 확정 때 걸친 PO 폴더에 바로가기(706)';
revoke all on public.po_doc from public, anon, authenticated, service_role;
grant select on public.po_doc to service_role;

-- 바로가기 — (올린 서류, 대상 PO) 짝마다 한 번(698 · 706) · 트랜스퍼 몫 없음(705)
create table public.drive_shortcut (
  id                 uuid primary key default gen_random_uuid(),
  po_doc_id          uuid not null references public.po_doc(id),
  po_id              uuid not null references public.po(id),
  drive_shortcut_id  text,
  created_at         timestamptz not null default now(),
  constraint drive_shortcut_uq unique (po_doc_id, po_id)
);
comment on table public.drive_shortcut is 'drive-1 판정 698 · 706 — 빌(po_charge) 확정 때 배분된 PO 폴더마다 · 공급처 인보이스 확정 때 걸친 다른 PO 폴더마다 두는 드라이브 바로가기 · 짝마다 한 번(확정을 풀었다 다시 확정해도 둘이 안 된다) · 뺀 PO 의 옛 바로가기는 REMOVED_ 로 이름만 바꾼다(Contributor 는 못 지운다 · 시험 A 실측 403)';
revoke all on public.drive_shortcut from public, anon, authenticated, service_role;
grant select on public.drive_shortcut to service_role;

-- 보낼 일 — archive(보관본 PDF 만들기 → 올리기) · upload(올린 서류) · shortcut · rename(CANCELLED_ · REMOVED_)
create table public.drive_job (
  id               uuid primary key default gen_random_uuid(),
  kind             text not null,
  status           text not null default 'queued',
  doc_kind         text,
  doc_ref          jsonb,
  doc_file_id      uuid references public.doc_file(id),
  po_doc_id        uuid references public.po_doc(id),
  shortcut_id      uuid references public.drive_shortcut(id),
  target_scope     text,
  target_ref       text,
  file_name        text,
  rename_to        text,
  description      text,
  drive_file_id    text,
  attempts         int  not null default 0,
  next_attempt_at  timestamptz,
  claimed_at       timestamptz,
  last_error       text,
  note             text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  updated_by       uuid references public.ims_staff(id),
  done_at          timestamptz,
  constraint drive_job_kind_ck    check (kind in ('archive', 'upload', 'shortcut', 'rename')),
  constraint drive_job_status_ck  check (status in ('waiting_pdf', 'queued', 'sending', 'done', 'failed', 'skipped')),
  constraint drive_job_doc_kind_ck check (doc_kind is null or doc_kind in ('final_invoice', 'credit_note')),
  constraint drive_job_scope_ck   check (target_scope is null or target_scope in ('customer', 'po', 'charge', 'aone_month')),
  constraint drive_job_shape_ck   check (case kind
                                           when 'archive'  then doc_kind is not null and doc_ref is not null and po_doc_id is null and shortcut_id is null and target_scope is not null and file_name is not null
                                           when 'upload'   then po_doc_id is not null and doc_kind is null and shortcut_id is null and target_scope is not null and file_name is not null
                                           when 'shortcut' then shortcut_id is not null and po_doc_id is not null and target_scope = 'po' and file_name is not null
                                           when 'rename'   then rename_to is not null and (doc_file_id is not null or po_doc_id is not null or shortcut_id is not null)
                                         end),
  constraint drive_job_waiting_ck check (status <> 'waiting_pdf' or kind = 'archive')
);
create unique index drive_job_archive_uq  on public.drive_job (doc_kind, doc_ref) where kind = 'archive';
create unique index drive_job_upload_uq   on public.drive_job (po_doc_id) where kind = 'upload';
create unique index drive_job_shortcut_uq on public.drive_job (shortcut_id) where kind = 'shortcut';
create unique index drive_job_name_uq     on public.drive_job (target_scope, target_ref, file_name) where kind in ('archive', 'upload') and status <> 'skipped';
create index drive_job_open_idx on public.drive_job (status, next_attempt_at, created_at) where status in ('waiting_pdf', 'queued', 'sending');
comment on table public.drive_job is 'drive-1 — 드라이브로 보낼 일 한 줄 = 파일 하나(또는 바로가기 · 이름 바꾸기): archive(발행 보관본 · waiting_pdf 에서 EF doc 이 PDF 를 만들어 drive_job_pdf_set → queued) · upload(po_doc) · shortcut · rename(CANCELLED_ · REMOVED_) · 상태 queued → sending(claim) → done | failed(3 번 · 10 분 뒤 다시) | skipped · 폴더 자리 target_scope · target_ref · 파일 이름 file_name(DB 가 만든다 · 같은 이름 _2) · 일꾼 drive-2 는 drive_job_claim 으로 받아 쓴다';
revoke all on public.drive_job from public, anon, authenticated, service_role;
grant select on public.drive_job to service_role;

drop trigger if exists po_doc_touch on public.po_doc;
create trigger po_doc_touch before update on public.po_doc for each row execute function public.ims_touch();
drop trigger if exists drive_job_touch on public.drive_job;
create trigger drive_job_touch before update on public.drive_job for each row execute function public.ims_touch();

-- ═══ ④ 버킷 po-documents — 비공개 · pdf · jpeg · png · 10 MB(판정 708) · 쓰기 purchasing · 읽기(서명 URL) purchasing 보기 · 지우기 없음 ═══
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('po-documents', 'po-documents', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists po_documents_insert on storage.objects;
drop policy if exists po_documents_update on storage.objects;
drop policy if exists po_documents_select on storage.objects;
create policy po_documents_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'po-documents' and (select public.ims_can_write('purchasing')));
create policy po_documents_update on storage.objects for update to authenticated
  using (bucket_id = 'po-documents' and (select public.ims_can_write('purchasing')))
  with check (bucket_id = 'po-documents' and (select public.ims_can_write('purchasing')));
create policy po_documents_select on storage.objects for select to authenticated
  using (bucket_id = 'po-documents' and (select public.ims_can_view('purchasing')));

-- ═══ ⑤ 도우미 — 이름 · 자리 · 일 넣기 ═══
-- 파일 · 폴더 이름에 못 쓰는 글자(/ \ : * ? " < > | #)와 공백 묶음을 - 로 · 앞뒤 - 제거 · 80 자
create or replace function public.drive_name_clean(p text) returns text
  language sql immutable
  set search_path = public, pg_temp
as $$ select left(btrim(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''), '[/\\:*?"<>|#]+', '-', 'g'), '\s+', '-', 'g'), '-+', '-', 'g'), '-'), 80); $$;
revoke all on function public.drive_name_clean(text) from public, anon;

create or replace function public.drive_since_ok(p_date date) returns boolean
  language sql stable
  set search_path = public, pg_temp
as $$ select p_date is not null and nullif((select c.value from public.inv_config c where c.key = 'drive_since'), '') is not null
          and p_date >= to_date((select c.value from public.inv_config c where c.key = 'drive_since'), 'YYYY-MM-DD'); $$;
revoke all on function public.drive_since_ok(date) from public, anon;
comment on function public.drive_since_ok(date) is 'drive-1 판정 521 — drive_since 가 비어 있으면 false · 그 날짜(포함) 뒤면 true · 트리거 · po_doc_add 가 일을 만들지 결정';

-- 같은 폴더(scope · ref) 안 같은 이름이면 _2 · _3 을 붙인다(일 표 기준 · skipped 는 안 센다)
create or replace function public.drive_unique_name(p_scope text, p_ref text, p_base text, p_ext text) returns text
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare v_name text; v_n int := 1;
begin
  v_name := p_base || p_ext;
  while exists (select 1 from public.drive_job j where j.kind in ('archive', 'upload') and j.status <> 'skipped' and j.target_scope = p_scope and j.target_ref = p_ref and j.file_name = v_name) loop
    v_n := v_n + 1;
    v_name := p_base || '_' || v_n || p_ext;
  end loop;
  return v_name;
end;
$$;
revoke all on function public.drive_unique_name(text, text, text, text) from public, anon;

-- 인보이스의 자리(694 · 695): aonebeauty 오더(shop_order → shop_store.kind aone)면 aone_month/<YYYY-MM>(발행 달) + 이름에 손님 · 아니면 오더 손님(so_invoice_order.customer_id · 하나) · 손님 둘 이상(지금 0)이면 청구처 + note
create or replace function public.drive_target_invoice(p_invoice_id uuid) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare v_inv public.so_invoice%rowtype; v_aone boolean; v_cust uuid; v_n int; v_name text; v_note text;
begin
  select * into v_inv from public.so_invoice i where i.id = p_invoice_id;
  if v_inv.id is null then raise exception 'Invoice % not found', p_invoice_id; end if;
  select exists (select 1 from public.so_invoice_order o join public.shop_order so on so.so_id = o.so_id join public.shop_store st on st.id = so.store_id where o.invoice_id = p_invoice_id and st.kind = 'aone') into v_aone;
  select count(distinct coalesce(o.customer_id, s.customer_id)), (array_agg(coalesce(o.customer_id, s.customer_id) order by o.so_number))[1] into v_n, v_cust
    from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = p_invoice_id;
  if v_n = 0 then v_cust := v_inv.bill_to_customer_id; v_note := 'no order on the invoice — bill-to folder';
  elsif v_n > 1 then v_cust := v_inv.bill_to_customer_id; v_note := 'orders of ' || v_n || ' customers on one invoice — bill-to folder';
  end if;
  select c.name into v_name from public.customer c where c.id = v_cust;
  if v_aone then
    return jsonb_build_object('scope', 'aone_month', 'ref', to_char(v_inv.issued_on, 'YYYY-MM'), 'customer_id', v_cust, 'customer_name', v_name, 'note', v_note);
  end if;
  return jsonb_build_object('scope', 'customer', 'ref', v_cust::text, 'customer_id', v_cust, 'customer_name', v_name, 'note', v_note);
end;
$$;
revoke all on function public.drive_target_invoice(uuid) from public, anon;

-- 보관 일 한 줄(692) — 발행 트리거 · drive_since 전이면 아무것도 · 같은 문서 둘이면 둘째는 조용히 지나간다
create or replace function public.drive_archive_enqueue(p_kind text, p_id uuid) returns uuid
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_tgt jsonb; v_date date; v_base text; v_name text; v_ref jsonb; v_job uuid; v_cred public.so_credit%rowtype; v_num text; v_desc text;
begin
  if p_kind = 'final_invoice' then
    select i.issued_on, i.invoice_number into v_date, v_num from public.so_invoice i where i.id = p_id;
    if not public.drive_since_ok(v_date) then return null; end if;
    v_tgt := public.drive_target_invoice(p_id);
    v_ref := jsonb_build_object('invoice_id', p_id);
    v_base := to_char(v_date, 'YYYYMMDD') || '_INV_' || v_num;                                                   -- 판정 701
    v_desc := 'Invoice ' || v_num;
  elsif p_kind = 'credit_note' then
    select * into v_cred from public.so_credit c where c.id = p_id;
    if not public.drive_since_ok(v_cred.issued_on) then return null; end if;
    if v_cred.invoice_id is not null then v_tgt := public.drive_target_invoice(v_cred.invoice_id);                -- 695 크레딧은 원래 오더를 따른다
    else v_tgt := jsonb_build_object('scope', 'customer', 'ref', v_cred.customer_id::text, 'customer_id', v_cred.customer_id, 'customer_name', (select c.name from public.customer c where c.id = v_cred.customer_id)); end if;
    v_date := v_cred.issued_on; v_num := v_cred.credit_number;
    v_ref := jsonb_build_object('credit_id', p_id);
    v_base := to_char(v_date, 'YYYYMMDD') || '_' || v_num;                                                        -- CR-01007 꼴 그대로(701)
    v_desc := 'Credit note ' || v_num || coalesce(' for invoice ' || v_cred.ref_invoice_number, '');
  else
    raise exception 'drive_archive_enqueue: kind % is not archived', p_kind;
  end if;
  if v_tgt->>'scope' = 'aone_month' then v_base := v_base || '_' || public.drive_name_clean(v_tgt->>'customer_name'); end if;
  if exists (select 1 from public.drive_job j where j.kind = 'archive' and j.doc_kind = p_kind and j.doc_ref = v_ref) then return null; end if;
  v_name := public.drive_unique_name(v_tgt->>'scope', v_tgt->>'ref', v_base, '.pdf');
  insert into public.drive_job (kind, status, doc_kind, doc_ref, target_scope, target_ref, file_name, description, note, next_attempt_at)
  values ('archive', 'waiting_pdf', p_kind, v_ref, v_tgt->>'scope', v_tgt->>'ref', v_name, v_desc, v_tgt->>'note', now())
  returning id into v_job;
  return v_job;
end;
$$;
revoke all on function public.drive_archive_enqueue(text, uuid) from public, anon;

-- 발행 트리거(지연 · 커밋 때 · 자동 메일 트리거와 같은 꼴 · 발행을 막지 않는다 — 실패는 skipped 한 줄)
create or replace function public.drive_archive_on_issue() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare v_kind text := case tg_table_name when 'so_invoice' then 'final_invoice' else 'credit_note' end; v_status text;
begin
  select case tg_table_name when 'so_invoice' then (select i.status from public.so_invoice i where i.id = new.id) else (select c.status from public.so_credit c where c.id = new.id) end into v_status;
  if v_status is distinct from 'issued' then return null; end if;                                                     -- 같은 트랜잭션에서 취소됐으면 아무것도
  begin
    perform public.drive_archive_enqueue(v_kind, new.id);
  exception when others then
    insert into public.drive_job (kind, status, doc_kind, doc_ref, target_scope, target_ref, file_name, last_error)
    values ('archive', 'skipped', v_kind, case v_kind when 'final_invoice' then jsonb_build_object('invoice_id', new.id) else jsonb_build_object('credit_id', new.id) end, 'customer', '-', 'error', left(sqlerrm, 500))
    on conflict do nothing;
  end;
  return null;
end;
$$;
revoke all on function public.drive_archive_on_issue() from public, anon;
drop trigger if exists so_invoice_drive_archive on public.so_invoice;
create constraint trigger so_invoice_drive_archive after insert on public.so_invoice deferrable initially deferred for each row execute function public.drive_archive_on_issue();
drop trigger if exists so_credit_drive_archive on public.so_credit;
create constraint trigger so_credit_drive_archive after insert on public.so_credit deferrable initially deferred for each row execute function public.drive_archive_on_issue();
comment on function public.drive_archive_on_issue() is 'drive-1 판정 692 — 인보이스 · 크레딧이 issued 로 생기면(커밋 때 · 지연 트리거) 보관 일 한 줄(waiting_pdf · drive_since 전이면 없음) · 실패는 skipped 한 줄 · 발행(so_invoice_issue · so_credit_issue)은 무접촉';

-- 취소 → 이름 바꾸기(704): 보관 일이 done 이면 rename 한 줄 · 아니면 올릴 때 지금 status 를 보고 CANCELLED_ 를 붙인다(drive_job_claim)
create or replace function public.drive_rename_on_cancel() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare v_kind text := case tg_table_name when 'so_invoice' then 'final_invoice' else 'credit_note' end; v_ref jsonb; v_j public.drive_job%rowtype;
begin
  if new.status <> 'cancelled' or old.status = 'cancelled' then return null; end if;
  v_ref := case v_kind when 'final_invoice' then jsonb_build_object('invoice_id', new.id) else jsonb_build_object('credit_id', new.id) end;
  select * into v_j from public.drive_job j where j.kind = 'archive' and j.doc_kind = v_kind and j.doc_ref = v_ref and j.status = 'done';
  if v_j.id is null then return null; end if;
  if v_j.file_name like 'CANCELLED\_%' or exists (select 1 from public.drive_job r where r.kind = 'rename' and r.doc_file_id = v_j.doc_file_id and r.status not in ('failed', 'skipped')) then return null; end if;
  insert into public.drive_job (kind, status, doc_kind, doc_ref, doc_file_id, drive_file_id, rename_to, description, next_attempt_at)
  values ('rename', 'queued', v_kind, v_ref, v_j.doc_file_id, v_j.drive_file_id, 'CANCELLED_' || v_j.file_name, 'cancelled in IMS', now());
  return null;
end;
$$;
revoke all on function public.drive_rename_on_cancel() from public, anon;
drop trigger if exists so_invoice_drive_rename on public.so_invoice;
create trigger so_invoice_drive_rename after update of status on public.so_invoice for each row execute function public.drive_rename_on_cancel();
drop trigger if exists so_credit_drive_rename on public.so_credit;
create trigger so_credit_drive_rename after update of status on public.so_credit for each row execute function public.drive_rename_on_cancel();

-- 바로가기 짝 넣기(698 · 706) — (서류, PO) 짝마다 한 번 · 트랜스퍼 몫 없음(705) · 일은 upload 일이 있을 때만(drive_since 전 서류는 없다)
create or replace function public.drive_shortcut_enqueue(p_doc_id uuid, p_po_id uuid) returns uuid
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_sc uuid; v_up public.drive_job%rowtype; v_sj public.drive_job%rowtype; v_doc public.po_doc%rowtype;
begin
  select * into v_doc from public.po_doc d where d.id = p_doc_id;
  if v_doc.id is null or not v_doc.is_active then return null; end if;
  if v_doc.po_id = p_po_id then return null; end if;                                                                 -- 원본이 있는 폴더에는 바로가기 없음
  insert into public.drive_shortcut (po_doc_id, po_id) values (p_doc_id, p_po_id) on conflict (po_doc_id, po_id) do nothing;
  select s.id into v_sc from public.drive_shortcut s where s.po_doc_id = p_doc_id and s.po_id = p_po_id;
  select * into v_up from public.drive_job j where j.kind = 'upload' and j.po_doc_id = p_doc_id;
  if v_up.id is null or v_up.status = 'skipped' then return v_sc; end if;
  select * into v_sj from public.drive_job j where j.kind = 'shortcut' and j.shortcut_id = v_sc;
  if v_sj.id is null then
    insert into public.drive_job (kind, status, po_doc_id, shortcut_id, target_scope, target_ref, file_name, description, next_attempt_at)
    values ('shortcut', 'queued', p_doc_id, v_sc, 'po', p_po_id::text, v_up.file_name, v_up.description, now());
  elsif v_sj.status = 'skipped' then                                                                                  -- 풀었다 다시 확정 — 아직 안 만든 바로가기는 다시 줄을 선다
    update public.drive_job set status = 'queued', note = null, next_attempt_at = now() where id = v_sj.id;
  elsif v_sj.status = 'done' and v_sj.file_name like 'REMOVED\_%'
        and not exists (select 1 from public.drive_job x where x.kind = 'rename' and x.shortcut_id = v_sc and x.status not in ('failed', 'skipped', 'done')) then   -- 뺐다 다시 넣은 PO — 이름을 되돌린다
    insert into public.drive_job (kind, status, po_doc_id, shortcut_id, drive_file_id, rename_to, description, next_attempt_at)
    values ('rename', 'queued', p_doc_id, v_sc, v_sj.drive_file_id, v_up.file_name, 'PO back in the allocation', now());
  end if;
  return v_sc;
end;
$$;
revoke all on function public.drive_shortcut_enqueue(uuid, uuid) from public, anon;

-- 서류 하나의 바로가기를 지금 상태로 맞춘다 — 빌: 확정이면 배분 PO 마다 · 인보이스: 확정이면 줄의 PO(올린 PO 빼고) 마다 · 빠진 PO 의 옛 바로가기(drive id 있음)는 REMOVED_ rename
create or replace function public.drive_shortcut_sync_doc(p_doc_id uuid) returns int
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_doc public.po_doc%rowtype; v_want uuid[] := '{}'; v_n int := 0; r record;
begin
  select * into v_doc from public.po_doc d where d.id = p_doc_id;
  if v_doc.id is null or not v_doc.is_active then return 0; end if;                                                -- 치운 서류는 po_doc_remove 가 처리했다
  if v_doc.po_charge_id is not null then
    if (select c.status from public.po_charge c where c.id = v_doc.po_charge_id) <> 'confirmed' then return 0; end if;   -- 확정 전 · 풀린 동안은 손대지 않는다(698 — 바로가기는 확정 때 맞춘다)
    select coalesce(array_agg(distinct a.po_id), '{}') into v_want from public.po_charge_alloc a where a.po_charge_id = v_doc.po_charge_id and a.po_id is not null;   -- 705 트랜스퍼 몫 없음
  elsif v_doc.po_invoice_id is not null then
    if (select i.status from public.po_invoice i where i.id = v_doc.po_invoice_id) <> 'confirmed' then return 0; end if;
    select coalesce(array_agg(distinct pl.po_id), '{}') into v_want from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id where il.po_invoice_id = v_doc.po_invoice_id and pl.po_id <> v_doc.po_id;
  else
    return 0;
  end if;
  for r in select unnest(v_want) as po_id loop
    perform public.drive_shortcut_enqueue(p_doc_id, r.po_id); v_n := v_n + 1;
  end loop;
  -- 빠진 PO 의 옛 바로가기 — 드라이브에 이미 있으면 REMOVED_ 로(Contributor 는 못 지운다) · 아직 안 만들었으면 그 일을 skipped
  for r in select s.id, s.drive_shortcut_id, j.id as job_id, j.status, j.file_name from public.drive_shortcut s left join public.drive_job j on j.kind = 'shortcut' and j.shortcut_id = s.id
            where s.po_doc_id = p_doc_id and not (s.po_id = any (v_want)) loop
    if r.job_id is not null and r.status in ('queued', 'sending') then
      update public.drive_job set status = 'skipped', note = 'allocation changed before the shortcut was made' where id = r.job_id;
    elsif r.drive_shortcut_id is not null and r.file_name not like 'REMOVED\_%'
          and not exists (select 1 from public.drive_job x where x.kind = 'rename' and x.shortcut_id = r.id and x.status not in ('failed', 'skipped')) then
      insert into public.drive_job (kind, status, po_doc_id, shortcut_id, drive_file_id, rename_to, description, next_attempt_at)
      values ('rename', 'queued', p_doc_id, r.id, r.drive_shortcut_id, 'REMOVED_' || r.file_name, 'PO dropped from the allocation', now());
    end if;
  end loop;
  return v_n;
end;
$$;
revoke all on function public.drive_shortcut_sync_doc(uuid) from public, anon;

-- 확정 트리거(po_charge · po_invoice · after update of status · 확정 창구 무접촉)
create or replace function public.drive_shortcut_on_confirm() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare r record;
begin
  if new.status = old.status or new.status <> 'confirmed' then return null; end if;                                  -- confirmed 로 들어올 때만(풀 때는 손대지 않는다 · 698)
  for r in select d.id from public.po_doc d where (tg_table_name = 'po_charge' and d.po_charge_id = new.id) or (tg_table_name = 'po_invoice' and d.po_invoice_id = new.id) loop
    perform public.drive_shortcut_sync_doc(r.id);
  end loop;
  return null;
end;
$$;
revoke all on function public.drive_shortcut_on_confirm() from public, anon;
drop trigger if exists po_charge_drive_shortcut on public.po_charge;
create trigger po_charge_drive_shortcut after update of status on public.po_charge for each row execute function public.drive_shortcut_on_confirm();
drop trigger if exists po_invoice_drive_shortcut on public.po_invoice;
create trigger po_invoice_drive_shortcut after update of status on public.po_invoice for each row execute function public.drive_shortcut_on_confirm();
comment on function public.drive_shortcut_on_confirm() is 'drive-1 판정 698 · 706 — 빌 · 공급처 인보이스가 confirmed 로 바뀔 때 그 서류의 바로가기를 지금 배분 · 줄의 PO 에 맞춘다(풀 때는 손대지 않는다) · 짝마다 한 번 · 빠진 PO 는 REMOVED_ · 확정 창구(po_charge_confirm · po_invoice_confirm)는 무접촉';

-- ═══ ⑥ 창구 — 직원 ═══
-- 서류 올리기(697 · 703): 화면이 버킷 po-documents 에 올린 뒤 부른다 — {po_id | po_charge_id, po_invoice_id?, kind, description?, doc_date?, doc_number?, original_name, path, sha256}
--   크기 · 형식은 storage.objects 의 메타데이터에서 읽는다(화면 값을 믿지 않는다) · 없으면 거부 · purchasing 쓰기
create or replace function public.po_doc_add(p jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid; v_po public.po%rowtype; v_chg public.po_charge%rowtype; v_inv public.po_invoice%rowtype;
  v_kind text; v_path text; v_obj record; v_doc public.po_doc%rowtype; v_date date; v_num text; v_desc text;
  v_prefix text; v_base text; v_scope text; v_ref text; v_ext text; v_name text; v_job uuid; v_mime text; v_bytes bigint;
begin
  perform public.ims_require_write('purchasing', 'add a document');                                                 -- void · 문만(실패면 예외)
  select st.id into v_staff from public.ims_staff st where st.auth_user_id = auth.uid() and st.is_active;
  if v_staff is null then raise exception 'You are not registered as active staff — nothing was saved'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'p must be a JSON object — nothing was saved'; end if;
  if (nullif(p->>'po_id', '') is null) = (nullif(p->>'po_charge_id', '') is null) then raise exception 'Give exactly one of po_id or po_charge_id — nothing was saved'; end if;
  v_kind := lower(btrim(coalesce(p->>'kind', '')));
  if v_kind not in ('invoice', 'bol', 'coo', 'packing', 'b3', 'other') then raise exception 'kind must be one of invoice, bol, coo, packing, b3, other (got %) — nothing was saved', coalesce(p->>'kind', '(null)'); end if;
  v_desc := nullif(btrim(coalesce(p->>'description', '')), '');
  if v_kind = 'other' and v_desc is null then raise exception 'Other needs a short description — nothing was saved'; end if;
  if v_desc is not null and length(v_desc) > 200 then raise exception 'The description must be at most 200 characters — nothing was saved'; end if;
  v_num := nullif(btrim(coalesce(p->>'doc_number', '')), '');
  if v_num is not null and length(v_num) > 80 then raise exception 'The document number must be at most 80 characters — nothing was saved'; end if;
  v_date := coalesce(nullif(p->>'doc_date', '')::date, public.ims_today());
  if nullif(p->>'po_id', '') is not null then
    select * into v_po from public.po o where o.id = (p->>'po_id')::uuid;
    if v_po.id is null then raise exception 'PO not found — nothing was saved'; end if;
    v_scope := 'po'; v_ref := v_po.id::text;
  else
    select * into v_chg from public.po_charge c where c.id = (p->>'po_charge_id')::uuid;
    if v_chg.id is null then raise exception 'Charge not found — nothing was saved'; end if;
    v_scope := 'charge'; v_ref := v_chg.id::text;
  end if;
  if nullif(p->>'po_invoice_id', '') is not null then
    if v_kind <> 'invoice' then raise exception 'Only an Invoice document can be linked to a supplier invoice — nothing was saved'; end if;
    if v_po.id is null then raise exception 'A supplier invoice document is uploaded from the PO page — nothing was saved'; end if;
    select * into v_inv from public.po_invoice i where i.id = (p->>'po_invoice_id')::uuid;
    if v_inv.id is null then raise exception 'Supplier invoice not found — nothing was saved'; end if;
    if v_inv.supplier_id <> v_po.supplier_id then raise exception 'Supplier invoice % belongs to another supplier — nothing was saved', v_inv.invoice_number; end if;
    if v_num is null then v_num := v_inv.invoice_number; end if;
  end if;
  v_path := p->>'path';
  if v_path is null or v_path !~ '^(po|charge)/[0-9a-f-]{36}/[A-Za-z0-9._-]+\.(pdf|jpg|jpeg|png)$' or v_path not like v_scope || '/' || v_ref || '/%' then
    raise exception 'path must be %/<id>/<file>.pdf|jpg|jpeg|png under this document''s folder (got %) — nothing was saved', v_scope, coalesce(v_path, '(null)');
  end if;
  select o.metadata into v_obj from storage.objects o where o.bucket_id = 'po-documents' and o.name = v_path;
  if v_obj is null then raise exception 'The file % is not in the po-documents bucket — upload it first — nothing was saved', v_path; end if;
  v_mime := v_obj.metadata->>'mimetype'; v_bytes := (v_obj.metadata->>'size')::bigint;
  if v_mime not in ('application/pdf', 'image/jpeg', 'image/png') then raise exception 'The file is % — only PDF, JPEG and PNG are accepted — nothing was saved', coalesce(v_mime, '(unknown)'); end if;
  if v_bytes is null or v_bytes <= 0 or v_bytes > 10485760 then raise exception 'The file is % bytes — it must be 1 byte to 10 MB — nothing was saved', coalesce(v_bytes::text, '?'); end if;
  if coalesce(p->>'sha256', '') !~ '^[0-9a-fA-F]{64}$' then raise exception 'sha256 is required (64 hex) — nothing was saved'; end if;
  if nullif(btrim(coalesce(p->>'original_name', '')), '') is null then raise exception 'original_name is required — nothing was saved'; end if;
  insert into public.po_doc (po_id, po_charge_id, po_invoice_id, kind, description, doc_date, doc_number, original_name, path, bytes, sha256, mime, uploaded_by)
  values (v_po.id, v_chg.id, v_inv.id, v_kind, v_desc, v_date, v_num, left(btrim(p->>'original_name'), 200), v_path, v_bytes::int, lower(p->>'sha256'), v_mime, v_staff)
  returning * into v_doc;
  -- 드라이브 일(697 · 701 · 703): 날짜_접두[_번호 | _설명].확장자 · drive_since 전(또는 빈 값)이면 일 없음
  if public.drive_since_ok(public.ims_today()) then
    v_prefix := case v_kind when 'invoice' then 'INV' when 'bol' then 'BOL' when 'coo' then 'COO' when 'packing' then 'PACKING' when 'b3' then 'B3' else 'OTHER_' || public.drive_name_clean(v_desc) end;
    v_base := to_char(v_date, 'YYYYMMDD') || '_' || v_prefix || case when v_num is null then '' else '_' || public.drive_name_clean(v_num) end;
    v_ext := case v_mime when 'application/pdf' then '.pdf' when 'image/jpeg' then '.jpg' else '.png' end;
    v_name := public.drive_unique_name(v_scope, v_ref, v_base, v_ext);
    insert into public.drive_job (kind, status, po_doc_id, target_scope, target_ref, file_name, description, next_attempt_at)
    values ('upload', 'queued', v_doc.id, v_scope, v_ref, v_name, initcap(replace(v_kind, '_', ' ')) || coalesce(' ' || v_num, '') || coalesce(' — ' || v_desc, '') || ' · uploaded as ' || v_doc.original_name, now())
    returning id into v_job;
  end if;
  perform public.drive_shortcut_sync_doc(v_doc.id);                                                                 -- 이미 확정된 빌 · 인보이스면 바로가기 지금(698 · 706)
  return jsonb_build_object('doc_id', v_doc.id, 'kind', v_doc.kind, 'path', v_doc.path, 'bytes', v_doc.bytes, 'mime', v_doc.mime, 'doc_date', v_doc.doc_date, 'doc_number', v_doc.doc_number,
                            'drive_job_id', v_job, 'drive_file_name', v_name, 'drive_pending', v_job is not null,
                            'shortcuts', (select count(*) from public.drive_shortcut s where s.po_doc_id = v_doc.id));
end;
$$;
comment on function public.po_doc_add(jsonb) is 'drive-1 판정 691 · 697 · 703 · 708 — 올린 서류 한 줄(purchasing 쓰기): {po_id | po_charge_id, po_invoice_id?, kind, description?(other 필수), doc_date?(기본 오늘), doc_number?, original_name, path, sha256} · 크기 · 형식은 버킷 메타데이터 · drive_since 뒤면 upload 일 + 파일 이름(YYYYMMDD_접두_번호 · 같은 이름 _2) · 확정된 빌 · 인보이스면 바로가기';
revoke all on function public.po_doc_add(jsonb) from public, anon, service_role;
grant execute on function public.po_doc_add(jsonb) to authenticated;

-- 치우기(704): is_active false · 파일은 둔다 · 드라이브에 이미 있으면 REMOVED_ rename · 아직이면 그 일을 skipped · 바로가기도 같은 처리
create or replace function public.po_doc_remove(p_doc_id uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_doc public.po_doc%rowtype; v_up public.drive_job%rowtype; v_renamed int := 0; v_skipped int := 0; r record;
begin
  perform public.ims_require_write('purchasing', 'remove a document');
  select st.id into v_staff from public.ims_staff st where st.auth_user_id = auth.uid() and st.is_active;
  if v_staff is null then raise exception 'You are not registered as active staff — nothing was saved'; end if;
  select * into v_doc from public.po_doc d where d.id = p_doc_id for update;
  if v_doc.id is null then raise exception 'Document not found — nothing was saved'; end if;
  if not v_doc.is_active then raise exception 'Document % is already removed — nothing was saved', v_doc.original_name; end if;
  update public.po_doc set is_active = false, removed_at = now(), removed_by = v_staff, removed_note = nullif(btrim(coalesce(p_note, '')), '') where id = p_doc_id;
  select * into v_up from public.drive_job j where j.kind = 'upload' and j.po_doc_id = p_doc_id;
  if v_up.id is not null then
    if v_up.status in ('queued', 'sending') then update public.drive_job set status = 'skipped', note = 'removed in IMS before upload' where id = v_up.id; v_skipped := v_skipped + 1;
    elsif v_up.status = 'done' and not exists (select 1 from public.drive_job x where x.kind = 'rename' and x.po_doc_id = p_doc_id and x.shortcut_id is null and x.status not in ('failed', 'skipped')) then
      insert into public.drive_job (kind, status, po_doc_id, drive_file_id, rename_to, description, next_attempt_at) values ('rename', 'queued', p_doc_id, v_up.drive_file_id, 'REMOVED_' || v_up.file_name, 'removed in IMS', now());
      v_renamed := v_renamed + 1;
    end if;
  end if;
  for r in select s.id, s.drive_shortcut_id, j.id as job_id, j.status, j.file_name from public.drive_shortcut s left join public.drive_job j on j.kind = 'shortcut' and j.shortcut_id = s.id where s.po_doc_id = p_doc_id loop
    if r.job_id is not null and r.status in ('queued', 'sending') then update public.drive_job set status = 'skipped', note = 'removed in IMS before the shortcut was made' where id = r.job_id; v_skipped := v_skipped + 1;
    elsif r.drive_shortcut_id is not null and not exists (select 1 from public.drive_job x where x.kind = 'rename' and x.shortcut_id = r.id and x.status not in ('failed', 'skipped')) then
      insert into public.drive_job (kind, status, po_doc_id, shortcut_id, drive_file_id, rename_to, description, next_attempt_at) values ('rename', 'queued', p_doc_id, r.id, r.drive_shortcut_id, 'REMOVED_' || r.file_name, 'removed in IMS', now());
      v_renamed := v_renamed + 1;
    end if;
  end loop;
  return jsonb_build_object('doc_id', p_doc_id, 'removed', true, 'drive_renames', v_renamed, 'drive_jobs_skipped', v_skipped);
end;
$$;
comment on function public.po_doc_remove(uuid, text) is 'drive-1 판정 704 — 올린 서류 치우기(purchasing 쓰기): is_active false · 저장소 파일은 둔다 · 드라이브에 간 것은 REMOVED_ 이름 바꾸기 일 · 아직이면 그 일을 skipped · 바로가기도 같이';
revoke all on function public.po_doc_remove(uuid, text) from public, anon, service_role;
grant execute on function public.po_doc_remove(uuid, text) to authenticated;

-- 목록 — PO 하나 또는 빌 하나의 서류(치운 것 포함 · 드라이브 상태 함께) · purchasing 보기
create or replace function public.po_doc_list(p_po_id uuid default null, p_charge_id uuid default null) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  if public.doc_staff_or_service() is not null and not public.ims_can_view('purchasing') then raise exception 'Viewing documents needs the purchasing permission — nothing was read'; end if;
  if (p_po_id is null) = (p_charge_id is null) then raise exception 'Give exactly one of p_po_id or p_charge_id — nothing was read'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'description', d.description, 'doc_date', d.doc_date, 'doc_number', d.doc_number, 'original_name', d.original_name,
                                                        'path', d.path, 'bytes', d.bytes, 'mime', d.mime, 'uploaded_at', d.uploaded_at, 'uploaded_by_name', (select s.name from public.ims_staff s where s.id = d.uploaded_by),
                                                        'is_active', d.is_active, 'removed_at', d.removed_at, 'removed_note', d.removed_note, 'po_invoice_id', d.po_invoice_id,
                                                        'drive', jsonb_build_object('file_id', d.drive_file_id, 'file_name', j.file_name, 'status', j.status, 'last_error', j.last_error),
                                                        'shortcuts', (select coalesce(jsonb_agg(jsonb_build_object('po_id', s.po_id, 'po_number', o.po_number, 'drive_shortcut_id', s.drive_shortcut_id) order by o.po_number), '[]'::jsonb)
                                                                        from public.drive_shortcut s join public.po o on o.id = s.po_id where s.po_doc_id = d.id))
                                     order by d.uploaded_at desc)
                     from public.po_doc d left join public.drive_job j on j.kind = 'upload' and j.po_doc_id = d.id
                    where (p_po_id is not null and d.po_id = p_po_id) or (p_charge_id is not null and d.po_charge_id = p_charge_id)), '[]'::jsonb);
end;
$$;
revoke all on function public.po_doc_list(uuid, uuid) from public, anon;
grant execute on function public.po_doc_list(uuid, uuid) to authenticated, service_role;

-- 상태 읽기(system-check · Settings): 켜짐 · since · root · 일 수(상태 · 종류) · failed 머리 10
create or replace function public.drive_status() returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  perform public.doc_staff_or_service();
  return jsonb_build_object(
    'enabled', (select c.value from public.inv_config c where c.key = 'drive_enabled') = 'on',
    'since', nullif((select c.value from public.inv_config c where c.key = 'drive_since'), ''),
    'root_id', (select c.value from public.inv_config c where c.key = 'drive_root_id'),
    'counts', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb) from (select j.kind || ':' || j.status as k, count(*) as n from public.drive_job j group by 1) x),
    'pending', (select count(*) from public.drive_job j where j.status in ('waiting_pdf', 'queued', 'sending')),
    'failed', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'file_name', coalesce(j.rename_to, j.file_name), 'last_error', j.last_error, 'attempts', j.attempts, 'updated_at', j.updated_at) order by j.updated_at desc), '[]'::jsonb)
                 from (select * from public.drive_job where status = 'failed' order by updated_at desc limit 10) j),
    'folders', (select count(*) from public.drive_folder));
end;
$$;
revoke all on function public.drive_status() from public, anon;
grant execute on function public.drive_status() to authenticated, service_role;

-- ═══ ⑦ 창구 — 일꾼(drive-2 EF · service_role · doc_is_service) ═══
-- 집기: archive 의 waiting_pdf 는 늘(PDF 는 발행 직후) · 나머지는 drive_enabled on 일 때만 · 오래된 것부터 · 10 분 안에 집힌 줄은 건너뜀 · 상태 sending(waiting_pdf 는 그대로)
--   돌려주는 것: 일 · 문서(지금 status · 번호) · 저장소 파일(path · bytes · sha256 · mime) · 바로가기 대상 · 폴더 사슬(root 부터 · folder_id 는 있으면) · 올릴 이름(지금 취소됐으면 CANCELLED_)
create or replace function public.drive_job_claim(p_limit integer default 5) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_on boolean; v_root text; v_rows jsonb; v_ids uuid[];
begin
  if not public.doc_is_service() then raise exception 'drive_job_claim is for the drive worker only — nothing was read'; end if;
  v_on := (select c.value from public.inv_config c where c.key = 'drive_enabled') = 'on';
  v_root := (select c.value from public.inv_config c where c.key = 'drive_root_id');
  with pick as (
    select j.id from public.drive_job j
     where ((j.kind = 'archive' and j.status = 'waiting_pdf') or (v_on and j.status = 'queued'))
       and coalesce(j.next_attempt_at, '-infinity') <= now()
       and (j.claimed_at is null or j.claimed_at < now() - interval '10 minutes')
     order by j.created_at, j.id
     limit greatest(1, least(coalesce(p_limit, 5), 20))
     for update skip locked),
  upd as (update public.drive_job j set claimed_at = now(), status = case when j.status = 'queued' then 'sending' else j.status end from pick where j.id = pick.id returning j.id)
  select coalesce(array_agg(u.id), '{}') into v_ids from upd u;
  -- ⚠️ 꾸러미는 다음 문장에서 — 같은 문장 안의 읽기는 update 전 행을 본다(queued 로 찍힌다)
  select coalesce(jsonb_agg(public.drive_job_payload(j.id, v_root) order by j.created_at, j.id), '[]'::jsonb) into v_rows from public.drive_job j where j.id = any (v_ids);
  return v_rows;
end;
$$;

-- 일 한 줄을 일꾼이 쓸 꼴로(claim 과 다시 읽기가 같은 식)
create or replace function public.drive_job_payload(p_job_id uuid, p_root text) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_j public.drive_job%rowtype; v_doc jsonb; v_file jsonb; v_chain jsonb; v_cancelled boolean := false; v_name text; v_inv public.so_invoice%rowtype; v_cred public.so_credit%rowtype; v_pd public.po_doc%rowtype;
  v_sup uuid; v_sup_name text; v_po public.po%rowtype; v_chg public.po_charge%rowtype; v_cust uuid;
begin
  select * into v_j from public.drive_job j where j.id = p_job_id;
  if v_j.id is null then raise exception 'Job % not found', p_job_id; end if;
  if v_j.kind = 'archive' then
    if v_j.doc_kind = 'final_invoice' then
      select * into v_inv from public.so_invoice i where i.id = (v_j.doc_ref->>'invoice_id')::uuid;
      v_cancelled := v_inv.status = 'cancelled';
      v_doc := jsonb_build_object('kind', 'final_invoice', 'ref', v_j.doc_ref, 'number', v_inv.invoice_number, 'status', v_inv.status, 'issued_on', v_inv.issued_on);
    else
      select * into v_cred from public.so_credit c where c.id = (v_j.doc_ref->>'credit_id')::uuid;
      v_cancelled := v_cred.status = 'cancelled';
      v_doc := jsonb_build_object('kind', 'credit_note', 'ref', v_j.doc_ref, 'number', v_cred.credit_number, 'status', v_cred.status, 'issued_on', v_cred.issued_on);
    end if;
    if v_j.doc_file_id is not null then
      select jsonb_build_object('doc_file_id', f.id, 'bucket', 'documents', 'path', f.path, 'bytes', f.bytes, 'sha256', f.sha256, 'mime', 'application/pdf') into v_file from public.doc_file f where f.id = v_j.doc_file_id;
    end if;
  elsif v_j.kind in ('upload', 'shortcut') then
    select * into v_pd from public.po_doc d where d.id = v_j.po_doc_id;
    v_cancelled := not v_pd.is_active;
    v_file := jsonb_build_object('po_doc_id', v_pd.id, 'bucket', 'po-documents', 'path', v_pd.path, 'bytes', v_pd.bytes, 'sha256', v_pd.sha256, 'mime', v_pd.mime, 'drive_file_id', v_pd.drive_file_id);
    v_doc := jsonb_build_object('kind', v_pd.kind, 'doc_number', v_pd.doc_number, 'doc_date', v_pd.doc_date, 'original_name', v_pd.original_name);
  end if;
  -- 폴더 사슬(root → … → target) · 이름은 처음 만들 때 이름(drive_folder.made_name) · 없으면 지금 이름으로 만들라고 준다
  if v_j.target_scope = 'customer' then
    v_cust := v_j.target_ref::uuid;
    v_chain := jsonb_build_array(
      jsonb_build_object('scope', 'customer', 'ref', v_j.target_ref, 'name', coalesce((select f.made_name from public.drive_folder f where f.scope = 'customer' and f.ref = v_j.target_ref), public.drive_name_clean((select c.name from public.customer c where c.id = v_cust))),
                         'folder_id', (select f.folder_id from public.drive_folder f where f.scope = 'customer' and f.ref = v_j.target_ref), 'under', 'Customers'));
  elsif v_j.target_scope = 'aone_month' then
    v_chain := jsonb_build_array(
      jsonb_build_object('scope', 'aone', 'ref', 'root', 'name', 'aonebeauty', 'folder_id', (select f.folder_id from public.drive_folder f where f.scope = 'aone' and f.ref = 'root'), 'under', null),
      jsonb_build_object('scope', 'aone_month', 'ref', v_j.target_ref, 'name', v_j.target_ref, 'folder_id', (select f.folder_id from public.drive_folder f where f.scope = 'aone_month' and f.ref = v_j.target_ref), 'under', 'aone'));
  elsif v_j.target_scope in ('po', 'charge') then
    if v_j.target_scope = 'po' then select * into v_po from public.po o where o.id = v_j.target_ref::uuid; v_sup := v_po.supplier_id;
    else select * into v_chg from public.po_charge c where c.id = v_j.target_ref::uuid; v_sup := v_chg.supplier_id; end if;
    select s.name into v_sup_name from public.supplier s where s.id = v_sup;
    v_chain := jsonb_build_array(
      jsonb_build_object('scope', 'supplier', 'ref', v_sup::text, 'name', coalesce((select f.made_name from public.drive_folder f where f.scope = 'supplier' and f.ref = v_sup::text), public.drive_name_clean(v_sup_name)),
                         'folder_id', (select f.folder_id from public.drive_folder f where f.scope = 'supplier' and f.ref = v_sup::text), 'under', 'Suppliers'),
      jsonb_build_object('scope', v_j.target_scope, 'ref', v_j.target_ref,
                         'name', coalesce((select f.made_name from public.drive_folder f where f.scope = v_j.target_scope and f.ref = v_j.target_ref), case when v_j.target_scope = 'po' then v_po.po_number else 'CHARGE-' || public.drive_name_clean(v_chg.charge_number) end),
                         'folder_id', (select f.folder_id from public.drive_folder f where f.scope = v_j.target_scope and f.ref = v_j.target_ref), 'under', 'supplier'));
  end if;
  v_name := coalesce(v_j.rename_to, case when v_cancelled and v_j.kind <> 'rename' then (case when v_j.kind = 'archive' then 'CANCELLED_' else 'REMOVED_' end) || v_j.file_name else v_j.file_name end);
  return jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'status', v_j.status, 'attempts', v_j.attempts, 'created_at', v_j.created_at,
                            'root_id', p_root, 'target', jsonb_build_object('scope', v_j.target_scope, 'ref', v_j.target_ref), 'folders', coalesce(v_chain, '[]'::jsonb),
                            'file_name', v_name, 'description', v_j.description, 'doc', v_doc, 'file', v_file,
                            'drive_file_id', v_j.drive_file_id, 'shortcut_id', v_j.shortcut_id,
                            'shortcut_target_drive_file_id', case when v_j.kind = 'shortcut' then (select d.drive_file_id from public.po_doc d where d.id = v_j.po_doc_id) end);
end;
$$;
revoke all on function public.drive_job_payload(uuid, text) from public, anon, authenticated;
grant execute on function public.drive_job_payload(uuid, text) to service_role;
revoke all on function public.drive_job_claim(integer) from public, anon, authenticated;
grant execute on function public.drive_job_claim(integer) to service_role;
comment on function public.drive_job_claim(integer) is 'drive-1 — 일꾼(drive-2 EF): 보낼 일을 집는다(archive waiting_pdf 는 늘 · 그 밖은 drive_enabled on 일 때 · 오래된 것부터 · claimed_at 10 분 · 최대 20 · queued → sending) → [{job_id, kind, status, root_id, target, folders[{scope, ref, name, folder_id, under}], file_name(취소면 CANCELLED_ · 치움이면 REMOVED_), description, doc, file{bucket, path, bytes, sha256, mime}, drive_file_id, shortcut_id, shortcut_target_drive_file_id}]';

-- 보관본 PDF 가 생겼다(EF doc render reason archive → doc_file) — waiting_pdf → queued · 같은 문서의 archive PDF 만
create or replace function public.drive_job_pdf_set(p_job_id uuid, p_doc_file_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_j public.drive_job%rowtype; v_f public.doc_file%rowtype;
begin
  if not public.doc_is_service() then raise exception 'drive_job_pdf_set is for the drive worker only — nothing was saved'; end if;
  select * into v_j from public.drive_job j where j.id = p_job_id for update;
  if v_j.id is null then raise exception 'Job not found — nothing was saved'; end if;
  if v_j.kind <> 'archive' or v_j.status <> 'waiting_pdf' then raise exception 'Only an archive job still waiting for its PDF can get one (this one is % %) — nothing was saved', v_j.kind, v_j.status; end if;
  select * into v_f from public.doc_file f where f.id = p_doc_file_id;
  if v_f.id is null then raise exception 'Stored PDF not found — nothing was saved'; end if;
  if v_f.kind <> v_j.doc_kind or v_f.ref <> v_j.doc_ref or v_f.reason <> 'archive' then raise exception 'That PDF is % % (%), not the archive of % % — nothing was saved', v_f.kind, v_f.ref, v_f.reason, v_j.doc_kind, v_j.doc_ref; end if;
  update public.drive_job set doc_file_id = v_f.id, status = 'queued', claimed_at = null, next_attempt_at = now(), last_error = null where id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'status', 'queued', 'doc_file_id', v_f.id, 'path', v_f.path);
end;
$$;
revoke all on function public.drive_job_pdf_set(uuid, uuid) from public, anon, authenticated;
grant execute on function public.drive_job_pdf_set(uuid, uuid) to service_role;

-- 끝났다 — 드라이브 id 를 적는다(archive: doc_file.drive_file_id 한 번 · upload: po_doc.drive_file_id · shortcut: drive_shortcut.drive_shortcut_id · rename: 없음)
create or replace function public.drive_job_done(p_job_id uuid, p_drive_file_id text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_j public.drive_job%rowtype; v_id text := nullif(btrim(coalesce(p_drive_file_id, '')), '');
begin
  if not public.doc_is_service() then raise exception 'drive_job_done is for the drive worker only — nothing was saved'; end if;
  select * into v_j from public.drive_job j where j.id = p_job_id for update;
  if v_j.id is null then raise exception 'Job not found — nothing was saved'; end if;
  if v_j.status <> 'sending' then raise exception 'Only a job being sent can be finished (this one is %) — nothing was saved', v_j.status; end if;
  if v_j.kind <> 'rename' and v_id is null then raise exception 'drive_file_id is required — nothing was saved'; end if;
  if v_j.kind = 'archive' then update public.doc_file set drive_file_id = v_id where id = v_j.doc_file_id and drive_file_id is null;
  elsif v_j.kind = 'upload' then update public.po_doc set drive_file_id = v_id where id = v_j.po_doc_id;
  elsif v_j.kind = 'shortcut' then update public.drive_shortcut set drive_shortcut_id = v_id where id = v_j.shortcut_id;
  end if;
  update public.drive_job set status = 'done', done_at = now(), claimed_at = null, last_error = null, drive_file_id = coalesce(v_id, drive_file_id) where id = v_j.id;
  -- rename 이 끝나면 원본 일의 이름도 새 이름으로(다음 rename 이 두 번 붙지 않게)
  if v_j.kind = 'rename' then
    update public.drive_job set file_name = v_j.rename_to where kind in ('archive', 'upload', 'shortcut') and status = 'done'
       and ((v_j.doc_file_id is not null and doc_file_id = v_j.doc_file_id) or (v_j.shortcut_id is not null and shortcut_id = v_j.shortcut_id) or (v_j.shortcut_id is null and v_j.doc_file_id is null and po_doc_id = v_j.po_doc_id and kind = 'upload'));
  end if;
  return jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'status', 'done', 'drive_file_id', coalesce(v_id, v_j.drive_file_id));
end;
$$;
revoke all on function public.drive_job_done(uuid, text) from public, anon, authenticated;
grant execute on function public.drive_job_done(uuid, text) to service_role;

-- 실패 — 세 번까지 10 분 뒤 다시 · 세 번째는 failed(사람이 drive_status 로 본다)
create or replace function public.drive_job_failed(p_job_id uuid, p_error text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_j public.drive_job%rowtype; v_n int; v_err text := left(coalesce(nullif(btrim(p_error), ''), 'drive step failed'), 500); v_to text; v_back text;
begin
  if not public.doc_is_service() then raise exception 'drive_job_failed is for the drive worker only — nothing was saved'; end if;
  select * into v_j from public.drive_job j where j.id = p_job_id for update;
  if v_j.id is null then raise exception 'Job not found — nothing was saved'; end if;
  if v_j.status not in ('waiting_pdf', 'sending') then raise exception 'Only a job being worked on can fail (this one is %) — nothing was saved', v_j.status; end if;
  v_n := v_j.attempts + 1;
  v_back := case when v_j.status = 'waiting_pdf' then 'waiting_pdf' else 'queued' end;
  v_to := case when v_n >= 3 then 'failed' else v_back end;
  update public.drive_job set attempts = v_n, last_error = v_err, status = v_to, claimed_at = null, next_attempt_at = case when v_to <> 'failed' then now() + interval '10 minutes' end where id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'status', v_to, 'attempts', v_n, 'last_error', v_err);
end;
$$;
revoke all on function public.drive_job_failed(uuid, text) from public, anon, authenticated;
grant execute on function public.drive_job_failed(uuid, text) to service_role;

-- 폴더를 만들었다 — 짝을 적는다(이미 있으면 그 줄 · 693)
create or replace function public.drive_folder_set(p_scope text, p_ref text, p_folder_id text, p_name text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_f public.drive_folder%rowtype; v_parent_scope text; v_parent_ref text;
begin
  if not public.doc_is_service() then raise exception 'drive_folder_set is for the drive worker only — nothing was saved'; end if;
  if p_scope not in ('customer', 'supplier', 'po', 'charge', 'aone', 'aone_month') then raise exception 'scope must be customer, supplier, po, charge, aone or aone_month — nothing was saved'; end if;
  if p_scope = 'po' then select 'supplier', o.supplier_id::text into v_parent_scope, v_parent_ref from public.po o where o.id = p_ref::uuid;
  elsif p_scope = 'charge' then select 'supplier', c.supplier_id::text into v_parent_scope, v_parent_ref from public.po_charge c where c.id = p_ref::uuid;
  elsif p_scope = 'aone_month' then v_parent_scope := 'aone'; v_parent_ref := 'root'; end if;
  insert into public.drive_folder (scope, ref, folder_id, made_name, parent_scope, parent_ref) values (p_scope, p_ref, btrim(p_folder_id), left(coalesce(p_name, ''), 200), v_parent_scope, v_parent_ref)
  on conflict (scope, ref) do nothing;
  select * into v_f from public.drive_folder f where f.scope = p_scope and f.ref = p_ref;
  return to_jsonb(v_f);
end;
$$;
revoke all on function public.drive_folder_set(text, text, text, text) from public, anon, authenticated;
grant execute on function public.drive_folder_set(text, text, text, text) to service_role;

-- ═══ 착지 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_acl text; v_md5 text; v_n int;
begin
  if (select count(*) from pg_class where relname in ('drive_folder', 'po_doc', 'drive_shortcut', 'drive_job') and relnamespace = 'public'::regnamespace) <> 4 then v_bad := v_bad || ' tables'; end if;
  foreach v_acl in array array['drive_folder', 'po_doc', 'drive_shortcut', 'drive_job'] loop
    if (select relacl::text from pg_class where relname = v_acl and relnamespace = 'public'::regnamespace) <> '{postgres=arwdDxtm/postgres,service_role=r/postgres}' then v_bad := v_bad || ' acl-' || v_acl; end if;
  end loop;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'doc_file_reason_ck') !~ 'archive' then v_bad := v_bad || ' reason-ck'; end if;
  if not exists (select 1 from pg_indexes where indexname = 'doc_file_archive_uq') then v_bad := v_bad || ' archive-uq'; end if;
  if (select count(*) from public.inv_config where key in ('drive_enabled', 'drive_since', 'drive_root_id')) <> 3 then v_bad := v_bad || ' keys'; end if;
  if (select value from public.inv_config where key = 'drive_enabled') <> 'off' then v_bad := v_bad || ' enabled-default'; end if;
  select md5(prosrc) into v_md5 from pg_proc where proname = 'ims_config_set' and pronamespace = 'public'::regnamespace;
  if left(v_md5, 8) <> '3f7bca65' then v_bad := v_bad || ' config-set-md5(' || left(v_md5, 8) || ')'; end if;
  if not exists (select 1 from storage.buckets b where b.id = 'po-documents' and not b.public and b.file_size_limit = 10485760 and b.allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png']) then v_bad := v_bad || ' bucket'; end if;
  if (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname in ('po_documents_insert', 'po_documents_update', 'po_documents_select')) <> 3 then v_bad := v_bad || ' policies'; end if;
  if (select count(*) from pg_trigger where tgname in ('so_invoice_drive_archive', 'so_credit_drive_archive') and tgdeferrable and tginitdeferred) <> 2 then v_bad := v_bad || ' archive-triggers'; end if;
  if (select count(*) from pg_trigger where tgname in ('so_invoice_drive_rename', 'so_credit_drive_rename', 'po_charge_drive_shortcut', 'po_invoice_drive_shortcut', 'drive_config_guard', 'po_doc_touch', 'drive_job_touch')) <> 7 then v_bad := v_bad || ' triggers'; end if;
  foreach v_acl in array array['drive_job_claim(integer)', 'drive_job_pdf_set(uuid, uuid)', 'drive_job_done(uuid, text)', 'drive_job_failed(uuid, text)', 'drive_folder_set(text, text, text, text)', 'drive_job_payload(uuid, text)'] loop
    if has_function_privilege('authenticated', 'public.' || v_acl, 'execute') or has_function_privilege('anon', 'public.' || v_acl, 'execute') or not has_function_privilege('service_role', 'public.' || v_acl, 'execute') then v_bad := v_bad || ' worker-acl-' || v_acl; end if;
  end loop;
  foreach v_acl in array array['po_doc_add(jsonb)', 'po_doc_remove(uuid, text)'] loop
    if not has_function_privilege('authenticated', 'public.' || v_acl, 'execute') or has_function_privilege('anon', 'public.' || v_acl, 'execute') or has_function_privilege('service_role', 'public.' || v_acl, 'execute') then v_bad := v_bad || ' staff-acl-' || v_acl; end if;
  end loop;
  if has_function_privilege('anon', 'public.po_doc_list(uuid, uuid)', 'execute') or has_function_privilege('anon', 'public.drive_status()', 'execute') then v_bad := v_bad || ' read-acl'; end if;
  select count(*) into v_n from public.drive_job; if v_n <> 0 then v_bad := v_bad || ' jobs-not-empty'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - drive-1 did not land as designed:%s - nothing was changed', v_bad); end if;
  raise notice 'drive-1 landed: tables 4 (service_role select only) · doc_file reason archive + archive_uq · keys 3 (drive_enabled off) · ims_config_set md5 % · bucket po-documents + policies 3 · triggers 9 · worker windows 5 (service_role) · staff windows 4', left(v_md5, 8);
end $$;
