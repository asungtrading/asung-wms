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

-- ═══ rls-2 — 설정 표 inv_config 쓰기 닫기 · 설정 저장 창구 (2026-10-20 · 판정 568 · 572 ~ 574 · rls-2 이견 1 ~ 9 · 정본 so-module §67 뒤) ═══
--   결함: inv_config 의 정책이 auth_all(ALL · true · true · 20260901163300:30)이고 authenticated 에 INSERT · UPDATE · DELETE grant 가 있어 로그인한 직원 누구나 PostgREST 로 설정을 쓸 수 있었다.
--         guard(inv_config_guard)는 메일 10 · 문서 8 · so_invoice_unit_display · 잠긴 3 · db_role 만 보고, 나머지 18 키(base_currency · baseline_snapshot_key · customer/supplier 기본값 · 계정 코드 …)는 「잠기지 않은 키 — 종전 그대로」로 그냥 통과시켰다.
--   고침 ②(이견 5): auth_all 을 지우고 select 정책만(읽기 범위는 그대로) · authenticated 의 insert · update · delete 회수(truncate 는 mail-1a 가 이미) · service_role · postgres 무접촉(EF mail · shopify 는 읽기만 · 마이그레이션 seed 는 postgres).
--   고침 ①(판정 572): 창구 ims_config_set(p_key, p_value, p_old) — definer · 사람 문이 있는 키 21 만(메일 10 · 문서 7 · so_invoice_unit_display · 잠긴 3) · 나머지 20 은 거부 · 열쇠 식은 창구 안 한 곳(admin 둘 · 잠긴 3 은 supervisor 이상 · 나머지 master).
--   ⚠️ 함정(이견 2): definer 창구는 postgres 로 돌아 guard 의 사람 문(current_user = 'authenticated' 가지)과 db_role 의 postgres 통과를 그대로 지난다 → 열쇠 문 · db_role 거부 · updated_at/updated_by 는 창구가 스스로. 값 검사(ims_mail_config_problem · ims_doc_config_problem · 어휘 · 양의 정수 · 시험 DB 메일 규칙)는 guard 에 그대로(창구는 부르지 않는다 · 누가 쓰든 한 곳).
--   판정 573: guard 의 authenticated 가지는 바이트 그대로 — grant 회수 뒤엔 닿지 않지만 누가 grant 를 되살려도 마지막 벽으로 다시 선다.
--   판정 574: p_old 가 지금 값과 다르면 changed_elsewhere 예외(지금 값 · 누가 · 언제) · null 이면 검사 안 함(psql · 도구) · 같은 값은 changed false.
--   쓰는 쪽 전수(rls-2 조사): DB 함수 0 · EF 읽기만 · cron 읽기만 · GAS 0 · 화면은 settings.html 462 · 534 두 줄(대화 Claude 가 rpc 로 바꾼다 — 적용과 화면 배포를 같은 때에).

-- ═══ ② inv_config — select 정책만 · 쓰기 grant 회수 ═══
drop policy if exists auth_all on public.inv_config;
create policy inv_config_select on public.inv_config for select to authenticated using (true);
revoke insert, update, delete on public.inv_config from authenticated;
alter table public.inv_config enable row level security;
comment on policy inv_config_select on public.inv_config is 'rls-2(판정 568 · 572) — 직원은 읽기만(범위는 그대로 · 41 키 전부) · 쓰기는 창구 ims_config_set(definer) · postgres(마이그레이션 seed) · service_role 만';

-- ═══ ① 창구 ims_config_set — 설정 한 키 저장 ═══
create or replace function public.ims_config_set(p_key text, p_value text, p_old text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
-- rls-2 · 판정 572 ~ 574 — 화면(settings.html)이 설정 한 키를 저장하는 유일한 길.
--   열쇠 식 한 곳: mail_enabled · mail_redirect_to = admin · 잠긴 3(ims_config_locked_keys) = supervisor 이상 · 나머지 메일 8 · 문서 7 · so_invoice_unit_display = master(mail_settings().edit_level · doc_config().can_edit_text 와 같은 식).
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
  if p_key in ('mail_enabled', 'mail_redirect_to') then v_level := 'admin';
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
comment on function public.ims_config_set(text, text, text) is 'rls-2 판정 572 ~ 574 — 설정 한 키 저장 창구(definer): 허용 21(메일 10 · 문서 7 · so_invoice_unit_display · 잠긴 3) · 열쇠 admin/supervisor/master 한 곳 · 거부 20(db_role · doc_public_base_url · base_currency · baseline_snapshot_key · 기본값 · 계정 코드) · p_old 다르면 changed_elsewhere · 값 검사는 guard 가(누가 쓰든 한 곳) · updated_at/by 는 창구가 채운다';
revoke all on function public.ims_config_set(text, text, text) from public, anon, service_role;
grant execute on function public.ims_config_set(text, text, text) to authenticated;

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int;
begin
  select count(*) into v_n from pg_policies where schemaname = 'public' and tablename = 'inv_config' and policyname = 'auth_all';
  if v_n <> 0 then v_bad := v_bad || format(' auth_all_left_%s', v_n); end if;
  select count(*) into v_n from pg_policies where schemaname = 'public' and tablename = 'inv_config' and cmd = 'SELECT' and roles::text ~ 'authenticated';
  if v_n <> 1 then v_bad := v_bad || format(' select_policies_%s_of_1', v_n); end if;
  select count(*) into v_n from pg_policies where schemaname = 'public' and tablename = 'inv_config' and cmd <> 'SELECT';
  if v_n <> 0 then v_bad := v_bad || format(' write_policies_%s', v_n); end if;
  select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name = 'inv_config' and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if v_n <> 0 then v_bad := v_bad || format(' auth_write_grants_%s', v_n); end if;
  select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name = 'inv_config' and grantee = 'authenticated' and privilege_type = 'SELECT';
  if v_n <> 1 then v_bad := v_bad || format(' auth_select_%s_of_1', v_n); end if;
  select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name = 'inv_config' and grantee = 'service_role' and privilege_type in ('INSERT', 'UPDATE', 'DELETE');
  if v_n <> 3 then v_bad := v_bad || format(' service_role_write_%s_of_3', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'ims_config_set' and p.prosecdef
     and coalesce(p.proacl::text, '') ~ 'authenticated' and coalesce(p.proacl::text, '') !~ 'service_role' and p.prosrc ~ 'changed_elsewhere';
  if v_n <> 1 then v_bad := v_bad || format(' ims_config_set_%s_of_1', v_n); end if;
  select count(*) into v_n from pg_trigger t where t.tgrelid = 'public.inv_config'::regclass and t.tgname = 'inv_config_guard' and not t.tgisinternal;
  if v_n <> 1 then v_bad := v_bad || format(' guard_trigger_%s_of_1', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_config_guard' and p.prosrc ~ 'current_user = ''authenticated''';
  if v_n <> 1 then v_bad := v_bad || format(' guard_body_%s_of_1', v_n); end if;
  if v_bad <> '' then raise exception 'rls-2 landing check failed:%', v_bad; end if;
end $$;
