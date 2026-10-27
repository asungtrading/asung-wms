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

-- ─────────────────────────────────────────────────────────────
-- combo-1b — New combo 에서 sku_prefix 알림 빼기 (Asung-IMS · 2026-10-27 · 판정 826 ~ 828 · so-module §44 combo-1b)
--   계기: combo-1 이견 5 — core R1 은 substring(sku from '^[A-Z]+') 를 앞글자로 삼는다 · 콤보 SKU 는 TBRCOMBO9 꼴이라 앞글자가 TBRCOMBO 가 되어
--         브랜드 제품(TBR…)과 늘 다르다 → New combo 에서는 sku_prefix 알림이 거의 늘 뜬다 · Caleb 「A」(판정 826): New combo 에서만 뺀다 · 일반 New product 는 그대로
--   든 것: product_combo_create 재발행 하나 — supplier_missing 을 거르는 두 곳에 sku_prefix 를 같이(combo-1 ③ 과 같은 방식 · core 무접촉)
--     (a) ③ 미리 보기 — core warnings 에서 code 가 supplier_missing · sku_prefix 인 줄을 건너뛴다(키 목록에도 안 든다)
--     (b) ⑤ 저장 — core commit 의 p_ack 에 <SKU>:supplier_missing · <SKU>:sku_prefix 를 더한다(core 가 저장 직전 재검사에서 다시 내는 알림을 여기서 확인된 것으로 친다)
--     그 밖의 줄 0(주석 한 줄 · comment 문구) — combo-1 파일 대 이 파일 diff 가 증거 · create → create or replace
--   판정 827: 적재 스크립트(ipr_loadBom_) 무접촉 · 판정 828: components_missing 그대로
--   ⚠️ product_create_core · product_create · product_list · product_bom_set · product_bom_check_lines · product_combo_list 무접촉(md5 로 확인) · 표 · 정책 · 권한 · 데이터 무접촉
--      · 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · combo-1(ad702b96…) 위에서만 선다
--   시험: supabase/tests/combo_1b_check.sql(-v mig 로 시험 · 적용 뒤 -v mig 없이 확인) · combo_1_check.sql 은 적용 뒤 -v mig 없이 54 그대로
-- ─────────────────────────────────────────────────────────────

-- ═══ 무접촉 증거(적용 전 md5 · 권한 · 행 수) ═══
create temp table combo1b_before as
select (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create') as md5_combo_create,
       (select p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create') as acl_combo_create,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create_core') as md5_core,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create') as md5_create,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_list') as md5_list,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_set') as md5_bom_set,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_check_lines') as md5_check_lines,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_list') as md5_combo_list,
       (select count(*) from public.product_bom) as n_bom, (select count(*) from public.product_bom where is_active) as n_bom_act,
       (select count(*) from public.product) as n_product;

-- ═══ product_combo_create 재발행 — combo-1 본문에서 바뀐 줄: ③ 거르기 한 줄 · ⑤ ack 한 줄(+ 주석 한 줄) ═══
create or replace function public.product_combo_create(p_item jsonb, p_lines jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_sku      text;
  v_key      text;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_keys     text[] := '{}';
  v_unacked  text[] := '{}';
  v_chk      jsonb;
  v_core     jsonb;
  v_new      jsonb := '[]'::jsonb;            -- 도우미를 지난 구성품 [{component_id, sku, qty}]
  v_w        jsonb;
  v_x        jsonb;
  v_pid      uuid;
  v_r        record;
  v_n        int := 0;
  v_preview  jsonb;
begin
  perform public.ims_require_write('master', 'saved');                                                              -- ⭐ 유일한 문 — 첫 줄(판정 140 · product_create · product_bom_set 과 같다)
  v_staff := public.so_current_staff();
  if p_item is null or jsonb_typeof(p_item) <> 'object' then
    raise exception 'p_item must be a JSON object {sku, name, brand_id, category_id, unit_id, barcodes[], prices[{tier_id, price}]} — nothing was saved';
  end if;
  v_sku := trim(coalesce(p_item->>'sku', ''));
  v_key := 'combo:' || v_sku;

  -- ① 받지 않는 칸(판정 821) — 세트(콤보는 재고가 없다 · product_set_add 도 parent_is_combo 로 막는다) · 공급처(콤보는 사 오지 않는다) · 가족(콤보는 변형이 아니다)
  v_x := p_item->'sets';
  if v_x is not null and jsonb_typeof(v_x) <> 'null' and not (jsonb_typeof(v_x) = 'array' and jsonb_array_length(v_x) = 0) then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':combo_no_sets', 'sku', v_sku, 'code', 'combo_no_sets', 'message', format('Combo %s cannot have sets — a combo has no stock of its own — nothing was saved', v_sku));
  end if;
  v_x := p_item->'suppliers';
  if v_x is not null and jsonb_typeof(v_x) <> 'null' and not (jsonb_typeof(v_x) = 'array' and jsonb_array_length(v_x) = 0) then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':combo_no_suppliers', 'sku', v_sku, 'code', 'combo_no_suppliers', 'message', format('Combo %s cannot have suppliers — a combo is not bought, its components are — nothing was saved', v_sku));
  end if;
  if nullif(trim(coalesce(p_item->>'family_id', '')), '') is not null or nullif(trim(coalesce(p_item->>'family_sku', '')), '') is not null
     or (p_item->'family' is not null and jsonb_typeof(p_item->'family') <> 'null')
     or (p_item->'options' is not null and jsonb_typeof(p_item->'options') <> 'null' and not (jsonb_typeof(p_item->'options') = 'array' and jsonb_array_length(p_item->'options') = 0)) then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':combo_no_family', 'sku', v_sku, 'code', 'combo_no_family', 'message', format('Combo %s cannot be a family variant — leave family and options out — nothing was saved', v_sku));
  end if;

  -- ② 구성품 — 도우미(부모 id 없음 · 새 SKU 글자) · 막기 · component_is_set 알림 · 구성품 0 은 막는다(구성품 없는 SKU 가 생기면 콤보가 아니라 낱개다)
  v_chk := public.product_bom_check_lines(null, v_sku, p_lines, v_blocks, v_warns, v_keys);
  v_blocks := v_chk->'blocks';  v_warns := v_chk->'warns';  v_new := v_chk->'new';
  select coalesce(array_agg(x), '{}') into v_keys from jsonb_array_elements_text(v_chk->'keys') as x;
  if jsonb_array_length(v_new) = 0 and jsonb_array_length(v_blocks) = 0 then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':components_missing', 'sku', v_sku, 'code', 'components_missing', 'message', format('Combo %s needs at least two components — nothing was saved', v_sku));
  end if;
  v_preview := (select coalesce(jsonb_agg(jsonb_build_object('sku', x->>'sku', 'qty', (x->>'qty')::numeric) order by x->>'sku'), '[]'::jsonb) from jsonb_array_elements(v_new) x);

  -- ③ 낱개 검사 — product_create_core 미리 보기(p_family_ctx null · prod-3 와 같은 규칙) · 알림에서 supplier_missing(판정 821) · sku_prefix(판정 826) 를 뺀다
  v_core := public.product_create_core(jsonb_build_array(p_item), null, false, '{}');
  v_blocks := v_blocks || coalesce(v_core->'blocks', '[]'::jsonb);
  for v_w in select x from jsonb_array_elements(coalesce(v_core->'warnings', '[]'::jsonb)) as x loop
    if v_w->>'code' in ('supplier_missing', 'sku_prefix') then continue; end if;                                        -- combo-1b(판정 826): sku_prefix 도 뺀다 — core R1 은 ^[A-Z]+ 를 앞글자로 삼아 콤보 SKU(TBRCOMBO9 → TBRCOMBO)가 거의 늘 걸린다
    v_warns := v_warns || v_w;
    v_keys := array_append(v_keys, v_w->>'key');
  end loop;

  -- ④ 판정 — 막기 있음 → 저장 안 함 · 검사만 → 반환 · 확인 안 받은 경고 → 저장 안 함(판정 176 · product_create · product_bom_set 과 같은 꼴)
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'sku', v_sku, 'product_id', null, 'items', '[]'::jsonb, 'components', v_preview,
                              'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ⑤ 저장 — 낱개(core · 바코드 · 가격 · 한 트랜잭션 · 23505 는 core 가 문장으로) → 구성품 줄 · 둘 다 되거나 둘 다 안 된다(판정 818)
  v_core := public.product_create_core(jsonb_build_array(p_item), null, true, coalesce(p_ack, '{}') || array[v_sku || ':supplier_missing', v_sku || ':sku_prefix']);   -- core 의 supplier_missing · sku_prefix 는 콤보에 뜻이 없다 — 여기서만 확인된 것으로 친다(판정 821 · 826)
  if not coalesce((v_core->>'committed')::boolean, false) then                                                      -- 저장 직전 재검사에서 막혔다(있을 수 없지만 — 있으면 그대로 돌려주고 bom 은 넣지 않는다)
    return v_core || jsonb_build_object('sku', v_sku, 'product_id', null, 'components', v_preview);
  end if;
  v_pid := (v_core->'items'->0->>'product_id')::uuid;
  for v_r in select (x->>'component_id')::uuid as component_id, (x->>'qty')::numeric as qty from jsonb_array_elements(v_new) x loop
    insert into public.product_bom (parent_product_id, component_product_id, quantity, source, is_active, updated_by)
    values (v_pid, v_r.component_id, v_r.qty, 'manual', true, v_staff);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('committed', true, 'sku', v_sku, 'product_id', v_pid, 'items', v_core->'items', 'added', v_n,
                            'components', (select coalesce(jsonb_agg(jsonb_build_object('sku', c.sku, 'qty', b.quantity) order by c.sku), '[]'::jsonb) from public.product_bom b join public.product c on c.id = b.component_product_id where b.parent_product_id = v_pid and b.is_active),
                            'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.product_combo_create(jsonb, jsonb, boolean, text[]) from public, anon, service_role;
grant execute on function public.product_combo_create(jsonb, jsonb, boolean, text[]) to authenticated;
comment on function public.product_combo_create(jsonb, jsonb, boolean, text[]) is
  'combo-1(2026-10-27 · 판정 810 · 817 · 818 · 821) · combo-1b(판정 826) — New combo: a new combo SKU and its components in one transaction (both or neither) · p_item {sku, name, brand_id, category_id, unit_id, barcodes[], prices[{tier_id, price}], weight, weight_unit, note} (sets · suppliers · family/options are refused: combo_no_sets · combo_no_suppliers · combo_no_family) · p_lines = the whole component list [{sku, qty}] (2 or more · components_missing · component_single) · single-product checks = product_create_core (blocks 22 · warnings minus supplier_missing · sku_prefix) · component checks = product_bom_check_lines (shared with product_bom_set) · preview with p_commit=false, save with true · ack keys <sku>:<code> (product) and combo:<sku>:<code>[:<component>] (components) · master only · the only way a combo is born (product_bom_set refuses parent_not_combo)';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int; v_b record; v_src text; v_md5 text;
begin
  select * into v_b from combo1b_before;
  if v_b.md5_combo_create is distinct from 'ad702b9688307091fa737c2f46db62fd' then v_bad := v_bad || ' combo_create_before_not_combo1'; end if;
  if v_b.acl_combo_create is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then v_bad := v_bad || ' combo_create_acl_before'; end if;
  select md5(p.prosrc), p.prosrc into v_md5, v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create';
  if v_md5 is not distinct from v_b.md5_combo_create then v_bad := v_bad || ' combo_create_unchanged'; end if;
  if v_src !~ 'public\.product_bom_check_lines\(' or v_src !~ 'public\.product_create_core\(' or v_src !~ 'insert into public\.product_bom'
     or v_src !~ $r$in \('supplier_missing', 'sku_prefix'\) then continue$r$
     or v_src !~ $r$array\[v_sku \|\| ':supplier_missing', v_sku \|\| ':sku_prefix'\]$r$ then v_bad := v_bad || ' combo_create_body'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create_core') is distinct from v_b.md5_core
     or (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create') is distinct from v_b.md5_create
     or (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_list') is distinct from v_b.md5_list
     or (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_set') is distinct from v_b.md5_bom_set
     or (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_check_lines') is distinct from v_b.md5_check_lines
     or (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_list') is distinct from v_b.md5_combo_list then v_bad := v_bad || ' other_functions_changed'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create';
  if v_n <> 1 then v_bad := v_bad || format(' overloads_%s_of_1', v_n); end if;
  if coalesce((select p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create'), '-') <> '{postgres=X/postgres,authenticated=X/postgres}' then v_bad := v_bad || ' combo_create_acl_after'; end if;
  if not has_function_privilege('authenticated', 'public.product_combo_create(jsonb, jsonb, boolean, text[])', 'execute') or has_function_privilege('anon', 'public.product_combo_create(jsonb, jsonb, boolean, text[])', 'execute') then v_bad := v_bad || ' window_acl'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.proconfig::text ~ 'search_path=public, pg_temp' and p.proname = 'product_combo_create';
  if v_n <> 1 then v_bad := v_bad || ' definer'; end if;
  if left(coalesce(obj_description(to_regprocedure('public.product_combo_create(jsonb, jsonb, boolean, text[])'), 'pg_proc'), ''), 7) <> 'combo-1' then v_bad := v_bad || ' comment_head'; end if;
  if has_table_privilege('authenticated', 'public.product_bom', 'insert') or has_table_privilege('authenticated', 'public.product_bom', 'update') or has_table_privilege('authenticated', 'public.product_bom', 'delete') then v_bad := v_bad || ' product_bom-opened'; end if;
  if (select count(*) from public.product_bom) <> v_b.n_bom or (select count(*) from public.product_bom where is_active) <> v_b.n_bom_act or (select count(*) from public.product) <> v_b.n_product then v_bad := v_bad || ' data_changed'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM826', message = format('STOP - combo-1b did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
drop table combo1b_before;
