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

-- ═══ rls-3a — 원가 · 기준선 · 수집기 · 기록 표 열다섯 + inv_bin_notes 의 「누구나 쓰기」 닫기 · 문 없는 쓰기 함수의 실행권 회수 (2026-10-21 · 판정 579 · rls-3 조사 · rls-3a 이견 · 정본 so-module §68 뒤) ═══
--   결함(rls-3 조사 · 2026-10-21 실측): 표 열다섯의 정책이 auth_all(ALL · true · true)이고 authenticated 에 INSERT(· UPDATE · DELETE · TRUNCATE) grant 가 있어 로그인한 직원 누구나 PostgREST 로
--     기준선(inv_snapshot 206,240 행 → ims_inv_balance 의 수량) · Cin7 원가(inv_cost 3,619 · inv_doc_cost) · 수집기 상태(inv_sync_state 커서 · inv_sku_types non-inventory gate · inv_doc_state · inv_voided_docs — inv-collect 가 다음 회차에 무엇을 원장에 넣을지 정한다) · 기록 표 여덟을 쓰거나 지울 수 있었다.
--     inv_bin_notes 는 auth_insert(INSERT with check true) + 쓰기 grant · 쓰는 쪽 0(화면 · 함수 · EF · GAS).
--   고침 ①: 열다섯 표 auth_all → `<표>_select`(select to authenticated using (true) — 읽기 범위는 그대로 · 원가 읽기 가리기는 rls-3b) · authenticated 의 insert · update · delete · truncate 회수(anon 은 grant 0 — 실측 · 회수는 빈 동작) · service_role · postgres 무접촉(EF inv-collect · inv-cost · inv-doc-cost · inv-snapshot · inv-sku-types 는 전부 SUPABASE_SERVICE_ROLE_KEY — RLS 를 지난다 · cron 은 postgres)
--   고침 ②: inv_bin_notes auth_insert drop(auth_read 그대로) · authenticated 쓰기 grant 회수
--   고침 ③: 문 없는 쓰기 함수의 EXECUTE 회수 — inv_layer_carry · inv_layer_cost_add_settle(definer · 문 없음 · 부르는 8 개가 전부 definer 라 열어 둔 까닭(cogs_2_cost_split.sql:218 · 판정 31 · 118 「부르는 쪽이 invoker」)이 rls-1 뒤 사라졌다) ·
--             inv_snap_balance_diffs(definer · 문 없음 · cron 이 postgres 로 부른다 · cron.sql 449) · inv_compare_run(invoker · inv_snapshot 에서 delete · cron.sql 344 · 부르는 화면 · EF · GAS 0) · inv_ack_diff(invoker · inv_balance_diffs 쓰기 · ①이 닫으면 직원 호출은 어차피 42501 · 부르는 곳 0 — 안 B · definer 로 바꾸지 않는다) — 각각 public · anon · authenticated 회수 · service_role · postgres 그대로
--             tf_charge_* 6: public · anon 회수만(transfer_4.sql:349 … 495 가 grant 만 하고 public 회수를 안 해 기본 권한의 =X 가 남았다 · authenticated 는 그대로 — transfers.html 이 부른다)
--   ⚠️ 이 차수는 쓰기만 닫는다 — select 정책 using (true) · 원가 읽기(판정 576 · 580)는 rls-3b · WMS 작업 표 17 + wms_rollback_archive(판정 569 · 581)는 무접촉 · 기본 권한(alter default privileges)은 짓지 않는다(보고만)
--   ⚠️ 운영에는 닿지 않는다 — 첫 문장의 가드가 테스트 DB(db_role = test) 만 통과시킨다 · 운영의 같은 구멍(수집기 표)은 Caleb 이 rls-3-prod-census 를 돌린 뒤 정한다

-- ═══ ⓪ 무접촉 증거 — WMS 18 · rls-1 · rls-2 다섯의 정책 · grant 를 글 하나로 적어 둔다(끝 블록이 같은지 본다) ═══
create temp table rls3a_before as
select md5(string_agg(k, ',' order by k)) as untouched
from (
  select 'pol:' || tablename || ':' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-') as k
    from pg_policies where schemaname = 'public' and (tablename like 'wms\_%' or tablename in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume', 'inv_config'))
  union all
  select 'grant:' || table_name || ':' || grantee || ':' || privilege_type
    from information_schema.role_table_grants where table_schema = 'public' and (table_name like 'wms\_%' or table_name in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume', 'inv_config'))
) s;

-- ═══ ① 표 열다섯 — select 정책만 · 쓰기 grant 회수 ═══
do $$ declare t text; begin
  foreach t in array array['inv_snapshot', 'inv_cost', 'inv_doc_cost', 'inv_sync_state', 'inv_sku_types', 'inv_doc_state', 'inv_voided_docs',
                           'inv_missing_docs', 'inv_missing_lines', 'inv_conflicts', 'inv_collect_runs', 'inv_snapshot_runs', 'inv_compare', 'inv_compare_runs', 'inv_balance_diffs'] loop
    execute format('drop policy if exists auth_all on public.%I', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated, anon', t);
    execute format('comment on policy %I on public.%I is %L', t || '_select', t,
      'rls-3a(판정 579 · 2026-10-21) — 직원은 읽기만 · 쓰기는 service_role(EF inv-collect · inv-cost · inv-doc-cost · inv-snapshot · inv-sku-types) · postgres(cron · 마이그레이션)만 · 원가 읽기 가리기는 rls-3b');
  end loop;
end $$;

-- ═══ ② inv_bin_notes — 넣기 정책 drop · 쓰기 grant 회수(쓰는 쪽 0) ═══
drop policy if exists auth_insert on public.inv_bin_notes;
revoke insert, update, delete, truncate on public.inv_bin_notes from authenticated, anon;

-- ═══ ③ 함수 실행권 회수 ═══
revoke execute on function public.inv_layer_carry(bigint)                            from public, anon, authenticated;
revoke execute on function public.inv_layer_cost_add_settle(bigint)                  from public, anon, authenticated;
revoke execute on function public.inv_snap_balance_diffs()                           from public, anon, authenticated;
revoke execute on function public.inv_compare_run(text)                              from public, anon, authenticated;
revoke execute on function public.inv_ack_diff(text, text, text, text, text)         from public, anon, authenticated;
revoke execute on function public.tf_charge_confirm(uuid, boolean)                   from public, anon;
revoke execute on function public.tf_charge_update(uuid, jsonb)                      from public, anon;
revoke execute on function public.tf_charge_delete(uuid)                             from public, anon;
revoke execute on function public.tf_charge_alloc_add(uuid, uuid, numeric)           from public, anon;
revoke execute on function public.tf_charge_alloc_update(uuid, numeric)              from public, anon;
revoke execute on function public.tf_charge_alloc_delete(uuid)                       from public, anon;

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare
  v_bad   text   := '';
  v_n     int;
  v_t     text;
  v_f     text;
  v_tabs  text[] := array['inv_snapshot', 'inv_cost', 'inv_doc_cost', 'inv_sync_state', 'inv_sku_types', 'inv_doc_state', 'inv_voided_docs',
                          'inv_missing_docs', 'inv_missing_lines', 'inv_conflicts', 'inv_collect_runs', 'inv_snapshot_runs', 'inv_compare', 'inv_compare_runs', 'inv_balance_diffs'];
  v_none  text[] := array['public.inv_layer_carry(bigint)', 'public.inv_layer_cost_add_settle(bigint)', 'public.inv_snap_balance_diffs()', 'public.inv_compare_run(text)', 'public.inv_ack_diff(text,text,text,text,text)'];
  v_tf    text[] := array['public.tf_charge_confirm(uuid,boolean)', 'public.tf_charge_update(uuid,jsonb)', 'public.tf_charge_delete(uuid)', 'public.tf_charge_alloc_add(uuid,uuid,numeric)', 'public.tf_charge_alloc_update(uuid,numeric)', 'public.tf_charge_alloc_delete(uuid)'];
begin
  foreach v_t in array v_tabs || array['inv_bin_notes'] loop
    select count(*) into v_n from pg_policies where schemaname = 'public' and tablename = v_t and cmd <> 'SELECT';
    if v_n <> 0 then v_bad := v_bad || format(' %s_write_policies_%s', v_t, v_n); end if;
    select count(*) into v_n from pg_policies where schemaname = 'public' and tablename = v_t and cmd = 'SELECT' and roles::text ~ 'authenticated' and qual = 'true';
    if v_n <> 1 then v_bad := v_bad || format(' %s_select_policies_%s', v_t, v_n); end if;
    select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name = v_t and grantee in ('authenticated', 'anon') and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
    if v_n <> 0 then v_bad := v_bad || format(' %s_auth_write_grants_%s', v_t, v_n); end if;
    select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name = v_t and grantee = 'authenticated' and privilege_type = 'SELECT';
    if v_n <> 1 then v_bad := v_bad || format(' %s_auth_select_%s', v_t, v_n); end if;
    select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name = v_t and grantee = 'service_role' and privilege_type in ('INSERT', 'UPDATE', 'DELETE');
    if v_n <> 3 then v_bad := v_bad || format(' %s_service_role_write_%s_of_3', v_t, v_n); end if;
  end loop;
  select count(*) into v_n from pg_policies where schemaname = 'public' and tablename = 'inv_bin_notes' and policyname = 'auth_read';
  if v_n <> 1 then v_bad := v_bad || ' inv_bin_notes_auth_read_gone'; end if;
  foreach v_f in array v_none loop
    if has_function_privilege('authenticated', v_f, 'execute') or has_function_privilege('anon', v_f, 'execute') or not has_function_privilege('postgres', v_f, 'execute') or not has_function_privilege('service_role', v_f, 'execute') then
      v_bad := v_bad || ' ' || v_f || '_acl';
    end if;
  end loop;
  foreach v_f in array v_tf loop
    if has_function_privilege('anon', v_f, 'execute') or not has_function_privilege('authenticated', v_f, 'execute') then v_bad := v_bad || ' ' || v_f || '_acl'; end if;
  end loop;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')
     and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* '(insert\s+into|update|delete\s+from|truncate)\s+(public\.)?inv_(snapshot|cost|doc_cost|sync_state|sku_types|doc_state|voided_docs|missing_docs|missing_lines|conflicts|collect_runs|snapshot_runs|compare|compare_runs|balance_diffs|bin_notes)\M';
  if v_n <> 0 then v_bad := v_bad || format(' invoker_writers_callable_%s', v_n); end if;
  select count(*) into v_n from (
    select md5(string_agg(k, ',' order by k)) as untouched from (
      select 'pol:' || tablename || ':' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-') as k
        from pg_policies where schemaname = 'public' and (tablename like 'wms\_%' or tablename in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume', 'inv_config'))
      union all
      select 'grant:' || table_name || ':' || grantee || ':' || privilege_type
        from information_schema.role_table_grants where table_schema = 'public' and (table_name like 'wms\_%' or table_name in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume', 'inv_config'))
    ) s) a join rls3a_before b on b.untouched = a.untouched;
  if v_n <> 1 then v_bad := v_bad || ' untouched_set_changed(wms_18_or_rls_1_2_five)'; end if;
  if v_bad <> '' then raise exception 'rls-3a landing check failed:%', v_bad; end if;
end $$;
drop table rls3a_before;
