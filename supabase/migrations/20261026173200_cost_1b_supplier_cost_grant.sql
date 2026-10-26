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

-- ═══ cost-1b — product_supplier 의 cost · fixed_cost 를 authenticated 에서 회수 (2026-10-26 · 판정 759 · 764 · cost-1 이견 1 · deferred 339) ═══
--   ⚠️⚠️ 적용은 화면 일곱(products · product-sheet · supplier-products · po · purchasing · receiving · system-check)이 새 길(product_supplier_costs)로 배포된 뒤 — 그 전에 이 두 칸을 이름 · `*` · or() 안 · head count `*` 로 읽는 화면이 0 인지 다시 센다:
--     cd ~/asung/asung-ims && grep -nE 'product_supplier' *.html *.js | grep -vE '^\S+:[0-9]+:\s*(//|/\*|\*)' ; grep -nE '\bcost\b|fixed_cost' po.html products.html product-sheet.html supplier-products.html purchasing.html receiving.html system-check.html
--   꼴(이견 1 · 테스트 DB 실측 rollback): 표 단위 SELECT 가 남아 있으면 칸 revoke 는 효과가 없다 ⇒ 표 select 회수 + 원가 아닌 15 칸 grant · 그 뒤 cost · `*` · where cost 셋 다 42501 · 15 칸 읽기는 그대로
--   ⚠️ 함정: 앞으로 이 표에 칸을 더하면 authenticated 에 자동으로 안 보인다 — 그 마이그레이션이 grant select (새 칸) 을 적는다(comment 에도)
--   무변: 정책 product_supplier_select(purchasing ∨ master ∨ cost · rls-3b) · REFERENCES · TRIGGER · MAINTAIN 비트(xtm) · service_role 전권 · anon 없음(relacl 에 없다) · 함수 · 뷰 0 · FK 0 · 시퀀스 0
--   앞 조건: cost-1a · 1a2 착지(창구 · 재발행 넷 md5) · relacl 이 아직 rxtm · 검증 supabase/tests/cost_1_check.sql(-v mig3 로 읽는다 · 회수 뒤 갈래)

do $$
declare v_bad text := '';
begin
  if to_regprocedure('public.product_supplier_costs(uuid[], uuid, boolean)') is null then v_bad := v_bad || ' cost_1a_not_landed'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste') is distinct from 'ce2b79dec5b2a1bc7d5555a611b35acb' then v_bad := v_bad || ' po_lines_paste_not_cost_1a'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'price_formula_preview') is distinct from 'f77403f8b55aed98e9bbdd77651637e9' then v_bad := v_bad || ' price_formula_preview_not_cost_1a'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_update') is distinct from '6d7ec9ff7e086aecc9a73799b326ddbf' then v_bad := v_bad || ' product_update_not_cost_1a2'; end if;
  if (select relacl::text from pg_class where oid = 'public.product_supplier'::regclass) <> '{postgres=arwdDxtm/postgres,authenticated=rxtm/postgres,service_role=arwdDxtm/postgres}' then v_bad := v_bad || ' table_acl_unexpected'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM514', message = format('STOP - cost-1b needs%s - nothing was changed', v_bad); end if;
end $$;

revoke select on public.product_supplier from authenticated;
grant select (id, cin7_id, is_active, source, note, created_at, updated_at, product_id, supplier_id, supplier_sku, currency_id, last_supplied, is_default, updated_by, price_formula_id) on public.product_supplier to authenticated;
comment on table public.product_supplier is 'IMS ④ 제품↔공급처(Cin7 Suppliers[] 대응 · 캐시 아님 · 우리 키 id · cin7_id=ProductSupplierID 가 충돌 키). 낱개에 붙는다(세트는 부모의 것을 pack_factor 로 환산 · 콤보는 사지 않는다). 비활성 공급처 줄도 담는다 — 읽는 쪽이 supplier.is_active 를 건다. 정본 po-module §3-g · 2026-09-14 신설 · [2026-10-26 cost-1b 판정 759] cost · fixed_cost 는 authenticated 에 SELECT 없음(표 select 회수 + 원가 아닌 15 칸 grant) — 읽기는 product_supplier_costs(원가 열쇠)로만 · ⚠️ 이 표에 칸을 더하는 마이그레이션은 grant select (새 칸) on product_supplier to authenticated 를 함께 적어야 한다(표 select 가 없으니 새 칸은 authenticated 에 자동으로 안 보인다)';

-- ═══ 착지 — authenticated 가 cost · fixed_cost 를 select 못 한다(0) · 15 칸은 된다 · relacl xtm · anon 0 · service_role 그대로 · 정책 그대로 ═══
do $$
declare v_bad text := '';  v_n int;
begin
  select count(*) into v_n from information_schema.column_privileges where table_schema = 'public' and table_name = 'product_supplier' and grantee = 'authenticated' and privilege_type = 'SELECT' and column_name in ('cost', 'fixed_cost');
  if v_n <> 0 then v_bad := v_bad || format(' cost_columns_still_selectable_%s', v_n); end if;
  select count(*) into v_n from information_schema.column_privileges where table_schema = 'public' and table_name = 'product_supplier' and grantee = 'authenticated' and privilege_type = 'SELECT';
  if v_n <> 15 then v_bad := v_bad || format(' other_columns_%s_not_15', v_n); end if;
  if has_column_privilege('authenticated', 'public.product_supplier', 'cost', 'SELECT') or has_column_privilege('authenticated', 'public.product_supplier', 'fixed_cost', 'SELECT') then v_bad := v_bad || ' has_column_privilege_cost'; end if;
  if not has_column_privilege('authenticated', 'public.product_supplier', 'supplier_sku', 'SELECT') or not has_column_privilege('authenticated', 'public.product_supplier', 'is_default', 'SELECT') then v_bad := v_bad || ' lost_other_column'; end if;
  if has_table_privilege('authenticated', 'public.product_supplier', 'SELECT') then v_bad := v_bad || ' table_select_still_there'; end if;
  if (select relacl::text from pg_class where oid = 'public.product_supplier'::regclass) <> '{postgres=arwdDxtm/postgres,authenticated=xtm/postgres,service_role=arwdDxtm/postgres}' then v_bad := v_bad || ' relacl'; end if;
  if has_table_privilege('anon', 'public.product_supplier', 'SELECT') or has_column_privilege('anon', 'public.product_supplier', 'supplier_sku', 'SELECT') then v_bad := v_bad || ' anon'; end if;
  if not has_table_privilege('service_role', 'public.product_supplier', 'SELECT') then v_bad := v_bad || ' service_role'; end if;
  select count(*) into v_n from pg_policies where schemaname = 'public' and tablename = 'product_supplier';
  if v_n <> 1 or (select qual from pg_policies where schemaname = 'public' and tablename = 'product_supplier') !~ 'ims_can_view_cost\(\)' then v_bad := v_bad || ' policy'; end if;
  if v_bad <> '' then raise exception 'cost-1b landing check failed:%', v_bad; end if;
end $$;
