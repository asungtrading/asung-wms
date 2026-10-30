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
-- combo-one-1 — 콤보에 「구성품 하나 + 수량 2 이상」 허락 (Asung-IMS · 2026-10-30 · 판정 885 · so-module §44 뒤에 적는다)
--   계기: 판정 885 Caleb — 세트 = 묶음 자체 바코드로 스캔해 파는 것 · 콤보 = 묶음 바코드 없이 낱개 바코드로만 이어지는 것(예 「A 2 개를 1 개 값에」)
--         ⇒ 콤보에 구성품 하나 + 수량 ≥ 2 를 허락한다 · 구성품 하나 + 수량 < 2(× 1 = 그 제품 자체 · 1.5 같은 2 밑도) 는 계속 component_single
--   든 것: 재발행 셋 + comment 넷
--     ① product_bom_check_lines(combo-1 :62 ~ 140) — 바뀐 줄 2 = component_single 의 조건 · 메시지(코드 이름 · 열쇠 그대로 — 화면 · ack 호환)
--     ② so_combo_children_insert(asm-2a :96 ~ 124) — 바뀐 줄 2 = 「구성품 2 개 밑이면 거부」 → 「켜진 구성품 0 이면 거부」(그대로 두면 한 구성품 콤보가 오더에 못 들어간다)
--     ③ product_combo_create(combo-1b :56 ~ 142) — 바뀐 줄 1 = components_missing 메시지(구성품 0 · 「at least two」 → 새 뜻 · 이견 4 Caleb)
--     ④ comment — product_bom_check_lines · product_bom_set · product_combo_create(함수) · public.product_bom(표 · 이견 6 Caleb)
--   ⚠️ product_bom_set 본문 무접촉(md5)
--      · 표 · 정책 · 권한 · 데이터 무접촉 · 새 표 · 새 FK 없음 · 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음
--   시험: supabase/tests/combo_one_1_check.sql(-v mig 로 시험 · 적용 뒤 -v mig 없이 확인)
-- ─────────────────────────────────────────────────────────────

-- ═══ 무접촉 증거(적용 전 md5 · 권한 · 행 수) ═══
create temp table comboone1_before as
select (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_check_lines') as md5_check_lines,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_combo_children_insert') as md5_children_insert,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_set') as md5_bom_set,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create') as md5_combo_create,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_combo_children_sync') as md5_children_sync,
       (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname in ('product_bom_check_lines', 'so_combo_children_insert', 'product_bom_set', 'product_combo_create')) as acls,
       (select count(*) from public.product_bom) as n_bom, (select count(*) from public.product_bom where is_active) as n_bom_act,
       (select count(*) from public.product) as n_product, (select count(*) from public.so_line) as n_so_line;

-- ═══ ① product_bom_check_lines 재발행 — combo-1 :62 ~ 140 바이트 그대로 + 바뀐 줄 2(component_single 조건 · 메시지) ═══
create or replace function public.product_bom_check_lines(p_parent_id uuid, p_parent_sku text, p_lines jsonb, p_blocks jsonb default '[]'::jsonb, p_warns jsonb default '[]'::jsonb, p_keys text[] default '{}') returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_blocks   jsonb := coalesce(p_blocks, '[]'::jsonb);
  v_warns    jsonb := coalesce(p_warns, '[]'::jsonb);
  v_keys     text[] := coalesce(p_keys, '{}');
  v_par      public.product%rowtype;             -- 부모(고치기 · id 로) · 새 SKU(New combo)면 비어 있다 — 그때 「부모 = 구성품」 은 글자로 견준다
  v_comp     public.product%rowtype;
  v_key      text := 'combo:' || coalesce(trim(p_parent_sku), '');
  v_e        jsonb;
  v_sku      text;
  v_qtxt     text;
  v_qty      numeric;
  v_seen     uuid[] := '{}';
  v_new      jsonb := '[]'::jsonb;            -- 검사를 지난 줄 [{component_id, sku, qty}]
  v_n        int := 0;
begin
  if p_parent_id is not null then
    select * into v_par from public.product p where p.id = p_parent_id;
  end if;

  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_invalid', 'sku', coalesce(v_par.sku, trim(p_parent_sku)), 'code', 'lines_invalid', 'message', 'Components must be a list of {sku, qty} — nothing was saved');
  else
    for v_e in select x from jsonb_array_elements(p_lines) x loop
      v_n := v_n + 1;
      if jsonb_typeof(v_e) <> 'object' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_invalid:' || v_n, 'sku', coalesce(v_par.sku, ''), 'code', 'lines_invalid', 'message', format('Component %s is not {sku, qty} — nothing was saved', v_n));
        continue;
      end if;
      v_sku := nullif(trim(v_e->>'sku'), '');
      v_qtxt := trim(coalesce(v_e->>'qty', ''));
      if v_sku is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_unknown:' || v_n, 'sku', '', 'code', 'component_unknown', 'message', format('Component %s has no SKU — nothing was saved', v_n));
        continue;
      end if;
      select * into v_comp from public.product p where p.sku = v_sku;
      if not found then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_unknown:' || v_sku, 'sku', v_sku, 'code', 'component_unknown', 'message', format('Component %s does not exist — nothing was saved', v_sku));
        continue;
      end if;
      if not v_comp.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_inactive:' || v_sku, 'sku', v_sku, 'code', 'component_inactive', 'message', format('Component %s is inactive — nothing was saved', v_sku));
      end if;
      if (v_par.id is not null and v_comp.id = v_par.id) or (v_par.id is null and v_comp.sku = trim(p_parent_sku)) then   -- combo-1: 부모 id 가 없으면(New combo 의 새 SKU) 글자로 견준다
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_is_parent:' || v_sku, 'sku', v_sku, 'code', 'component_is_parent', 'message', format('Combo %s cannot contain itself — nothing was saved', v_sku));
      end if;
      if exists (select 1 from public.product_bom b where b.parent_product_id = v_comp.id and b.is_active) then           -- 묶음 1: 콤보 안의 콤보
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_is_combo:' || v_sku, 'sku', v_sku, 'code', 'component_is_combo', 'message', format('Component %s is itself a combo — a combo cannot contain a combo — nothing was saved', v_sku));
      end if;
      if v_comp.id = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_duplicate_in_call:' || v_sku, 'sku', v_sku, 'code', 'component_duplicate_in_call', 'message', format('Component %s is listed twice — give it once with the total qty — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := array_append(v_seen, v_comp.id);
      if v_qtxt !~ '^[0-9]+(\.[0-9]+)?$' then                                                                    -- 글자 검사 먼저 — SQL 의 or 는 짧게 끊지 않아 'abc'::numeric 이 먼저 터진다
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':quantity_invalid:' || v_sku, 'sku', v_sku, 'code', 'quantity_invalid', 'message', format('Component %s needs a qty above 0 (got "%s") — nothing was saved', v_sku, v_qtxt));
        continue;
      end if;
      if v_qtxt::numeric <= 0 then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':quantity_invalid:' || v_sku, 'sku', v_sku, 'code', 'quantity_invalid', 'message', format('Component %s needs a qty above 0 (got "%s") — nothing was saved', v_sku, v_qtxt));
        continue;
      end if;
      v_qty := round(v_qtxt::numeric, 6);
      if v_comp.parent_product_id is not null then                                                                  -- ⬜ 세트를 구성품으로 — 막지 않는다 · 알린다(오더 길이 coalesce(parent, id) × pack_factor 로 낱개로 접는다)
        v_warns := v_warns || jsonb_build_object('key', v_key || ':component_is_set:' || v_sku, 'sku', v_sku, 'code', 'component_is_set', 'message', format('Component %s is a set (pack of %s) — the order will take %s × %s singles of its base product', v_sku, coalesce(v_comp.pack_factor::text, '?'), v_qty, coalesce(v_comp.pack_factor::text, '?')));
        v_keys := array_append(v_keys, v_key || ':component_is_set:' || v_sku);
      end if;
      v_new := v_new || jsonb_build_object('component_id', v_comp.id, 'sku', v_comp.sku, 'qty', v_qty);
    end loop;
    if jsonb_array_length(v_new) = 1 and (v_new->0->>'qty')::numeric < 2 and jsonb_array_length(v_blocks) = 0 then        -- combo-one-1 판정 885: 구성품 하나는 수량 2 이상만(× 1 = 그 제품 자체 · 2 밑 소수도 막는다) · 둘 이상은 그대로
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_single', 'sku', coalesce(v_par.sku, ''), 'code', 'component_single', 'message', format('A combo with one component needs a qty of 2 or more (%s × %s) — nothing was saved', v_new->0->>'sku', trim_scale((v_new->0->>'qty')::numeric)));
    end if;
  end if;
  return jsonb_build_object('blocks', v_blocks, 'warns', v_warns, 'keys', to_jsonb(v_keys), 'new', v_new);
end;
$$;
comment on function public.product_bom_check_lines(uuid, text, jsonb, jsonb, jsonb, text[]) is
  'combo-1(2026-10-27 · 판정 818) · combo-one-1(2026-10-30 · 판정 885) — 콤보 구성품 목록 검사 고리(asm-1 product_bom_set :98 ~ 150 바이트 그대로 · component_is_parent 만 새 SKU 글자도 본다) · component_single = 구성품 하나에 수량 2 밑(구성품 둘 이상 · 하나 × 2 이상은 통과 · 판정 885) · product_bom_set 과 product_combo_create 가 함께 쓴다 · p_parent_id 가 null 이면 새 SKU(p_parent_sku) · p_blocks · p_warns · p_keys 는 부르는 쪽이 모은 것(이어 붙여 돌려준다) → {blocks, warns, keys, new[{component_id, sku, qty}]} · 문 없음 — 겉 창구가 든다 · owner 만 실행';

-- ═══ ② so_combo_children_insert 재발행 — asm-2a :96 ~ 124 바이트 그대로 + 바뀐 줄 2(0 만 거부) ═══
create or replace function public.so_combo_children_insert(p_parent public.so_line, p_staff uuid) returns int
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_n int := 0; v_next int; v_bad text;
begin
  select string_agg(c.sku, ', ' order by c.sku) into v_bad
    from public.product_bom b join public.product c on c.id = b.component_product_id
   where b.parent_product_id = p_parent.product_id and b.is_active and not c.is_active;
  if v_bad is not null then
    raise exception 'Combo % has inactive component(s) (%) — fix the combo first — nothing was saved', p_parent.sku, v_bad;
  end if;
  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_parent.so_id;
  insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                              list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason, tax_rule, comments, updated_by,
                              surcharge_pct, surcharge_amount, surcharge_label, combo_line_id, combo_qty)
  select p_parent.so_id, (v_next + row_number() over (order by c.sku))::int, c.id, c.sku, c.name, coalesce((select u.name from public.ref_unit u where u.id = c.unit_id), c.uom_name), coalesce(c.pack_factor, 1),
         p_parent.qty_ordered * b.quantity,
         null, null, 0, false, null, null, null, p_parent.tax_rule, null, p_staff,
         null, null, null, p_parent.id, b.quantity
    from public.product_bom b join public.product c on c.id = b.component_product_id
   where b.parent_product_id = p_parent.product_id and b.is_active;
  get diagnostics v_n = row_count;
  if v_n < 1 then                                                                          -- combo-one-1 판정 885: 구성품 하나 콤보(수량 2 이상)가 있다 · 켜진 구성품 0 만 거부
    raise exception 'Combo % has no active components — fix the combo first — nothing was saved', p_parent.sku;
  end if;
  return v_n;
end;
$$;

-- ═══ ③ product_combo_create 재발행 — combo-1b :56 ~ 142 바이트 그대로 + 바뀐 줄 1(components_missing 메시지) ═══
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
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':components_missing', 'sku', v_sku, 'code', 'components_missing', 'message', 'A combo needs at least one component (a single component needs a qty of 2 or more) — nothing was saved');   -- combo-one-1 판정 885
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

-- ═══ ④ comment — product_bom_set · product_combo_create · 표 product_bom ═══
comment on function public.product_bom_set(text, jsonb, jsonb, boolean, text[]) is
  'asm-1(판정 244 · asm 묶음 1) · combo-1(판정 817 · 819 · 825) · combo-one-1(판정 885): change the components of an existing combo — the whole component list [{sku, qty}] for one combo SKU · two or more components, or one component with qty 2 or more · a SKU that is not a combo (0 active rows · released ones too) is refused with parent_not_combo — new combos are born only in product_combo_create · p_old = the list the screen saw (changed_elsewhere when it differs) · preview with p_commit=false, save with true · blocks: parent_unknown · parent_inactive · parent_is_set · parent_is_component · parent_not_combo · lines_invalid · component_unknown · component_inactive · component_is_parent · component_is_combo · component_duplicate_in_call · quantity_invalid · component_single (one component with qty under 2) · old_missing · changed_elsewhere · no_change · warnings (ack keys combo:<sku>:<code>): component_is_set · open_orders · parent_stock · empty list = release (rows turned off, never deleted · cannot be undone) · touched rows become source manual · master only';
comment on function public.product_combo_create(jsonb, jsonb, boolean, text[]) is
  'combo-1(2026-10-27 · 판정 810 · 817 · 818 · 821) · combo-1b(판정 826) · combo-one-1(판정 885) — New combo: a new combo SKU and its components in one transaction (both or neither) · p_item {sku, name, brand_id, category_id, unit_id, barcodes[], prices[{tier_id, price}], weight, weight_unit, note} (sets · suppliers · family/options are refused: combo_no_sets · combo_no_suppliers · combo_no_family) · p_lines = the whole component list [{sku, qty}] (two or more components, or one component with qty 2 or more · components_missing · component_single) · single-product checks = product_create_core (blocks 22 · warnings minus supplier_missing · sku_prefix) · component checks = product_bom_check_lines (shared with product_bom_set) · preview with p_commit=false, save with true · ack keys <sku>:<code> (product) and combo:<sku>:<code>[:<component>] (components) · master only · the only way a combo is born (product_bom_set refuses parent_not_combo)';
comment on table public.product_bom is 'IMS ③ 콤보 구성. 다른 물건들을 묶은 것 — 구성품 2개 이상, 또는 구성품 하나 + 수량 2 이상(판정 885 · 2026-10-30: 콤보 = 묶음 바코드 없이 낱개 바코드로 파는 묶음 · 세트 = 묶음 자체 바코드로 파는 것). 실측 15건(2026-09-13 · Cin7 적재분). Cin7 의 구성품 1개 BOM(세트·대체 UPC)은 여기 없다 — product.parent_product_id·product_barcode. 정본 po-module §3-d';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_b record; v_src text; v_md5 text;
begin
  select * into v_b from comboone1_before;
  if v_b.md5_check_lines is distinct from '934a487a109d93e7ca67fc5c1b779065' then v_bad := v_bad || ' check_lines_before_not_combo1'; end if;
  if v_b.md5_children_insert is distinct from '608feb8d58d34f3160f6af92b3a8b6b9' then v_bad := v_bad || ' children_insert_before_not_asm2a'; end if;
  if v_b.md5_combo_create is distinct from '55de145a2a5f5530628fc05fc122faaa' then v_bad := v_bad || ' combo_create_before_not_combo1b'; end if;
  select md5(p.prosrc), p.prosrc into v_md5, v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create';
  if v_md5 is not distinct from v_b.md5_combo_create then v_bad := v_bad || ' combo_create_unchanged'; end if;
  if v_src !~ 'A combo needs at least one component \(a single component needs a qty of 2 or more\)' or v_src ~ 'needs at least two components'
     or v_src !~ 'public\.product_bom_check_lines\(' or v_src !~ 'insert into public\.product_bom' then v_bad := v_bad || ' combo_create_body'; end if;
  select md5(p.prosrc), p.prosrc into v_md5, v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_check_lines';
  if v_md5 is not distinct from v_b.md5_check_lines then v_bad := v_bad || ' check_lines_unchanged'; end if;
  if v_src !~ $r$jsonb_array_length\(v_new\) = 1 and \(v_new->0->>'qty'\)::numeric < 2 and jsonb_array_length\(v_blocks\) = 0 then$r$
     or v_src !~ 'A combo with one component needs a qty of 2 or more' or v_src ~ 'at least two components' then v_bad := v_bad || ' check_lines_body'; end if;
  select md5(p.prosrc), p.prosrc into v_md5, v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_combo_children_insert';
  if v_md5 is not distinct from v_b.md5_children_insert then v_bad := v_bad || ' children_insert_unchanged'; end if;
  if v_src !~ 'if v_n < 1 then' or v_src ~ 'v_n < 2' or v_src ~ 'fewer than two' then v_bad := v_bad || ' children_insert_body'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_set') is distinct from v_b.md5_bom_set
     or (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_combo_children_sync') is distinct from v_b.md5_children_sync then v_bad := v_bad || ' other_functions_changed'; end if;
  if (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('product_bom_check_lines', 'so_combo_children_insert', 'product_bom_set', 'product_combo_create')) is distinct from v_b.acls then v_bad := v_bad || ' acl_changed'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_bom_check_lines', 'so_combo_children_insert', 'product_bom_set', 'product_combo_create')) <> 4 then v_bad := v_bad || ' overloads'; end if;
  if obj_description(to_regprocedure('public.product_bom_check_lines(uuid, text, jsonb, jsonb, jsonb, text[])'), 'pg_proc') !~ '판정 885'
     or obj_description(to_regprocedure('public.product_bom_set(text, jsonb, jsonb, boolean, text[])'), 'pg_proc') !~ '판정 885'
     or obj_description(to_regprocedure('public.product_combo_create(jsonb, jsonb, boolean, text[])'), 'pg_proc') !~ '판정 885'
     or obj_description('public.product_bom'::regclass, 'pg_class') !~ '판정 885' then v_bad := v_bad || ' comments'; end if;
  if has_function_privilege('authenticated', 'public.product_bom_check_lines(uuid, text, jsonb, jsonb, jsonb, text[])', 'execute')
     or has_function_privilege('authenticated', 'public.so_combo_children_insert(public.so_line, uuid)', 'execute') then v_bad := v_bad || ' helper_opened'; end if;
  if (select count(*) from public.product_bom) <> v_b.n_bom or (select count(*) from public.product_bom where is_active) <> v_b.n_bom_act
     or (select count(*) from public.product) <> v_b.n_product or (select count(*) from public.so_line) <> v_b.n_so_line then v_bad := v_bad || ' data_changed'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM885', message = format('STOP - combo-one-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
drop table comboone1_before;
