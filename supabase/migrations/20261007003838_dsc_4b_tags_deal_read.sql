-- ─────────────────────────────────────────────────────────────
-- 태그 붙이기 · 떼기(product_update op) · so_deal_save 「모든 손님으로 넓어짐」 알림 · 걸리는 제품 · 손님 집합 · 딜 목록 · 상세 읽기 창구 (Asung-IMS · dsc-4b · 2026-10-06)
--   정본(뒤에 적는다): so-module 판정 336 · 337 · 342 · 343(dsc-4b 지시서 B · 2026-10-06 저녁) · 후보 344(제품 속성 변경의 열린 오더 표시 — 이번엔 안 만든다)
--   판정 336  태그 쓰기 길 = product_update 의 op tag_add {sku, tag} · tag_off {sku, tag} — 제품 문은 하나(판정 140) · barcode_add/off 결 · btrim 만 · tag_case_conflict(제품 태그 전체 · 딜 대상 · 같은 호출) · 떼기는 행 삭제
--   판정 337  목록 셈은 새 집합 함수(so_deal_products · so_deal_customers)로 따로 · so_deal_candidates · so_deal_customer_ok(가격의 심장)는 무접촉 · 같음은 검증이 증명
--   판정 342  꺼진 딜 줄도 line_no 를 쥔다 — 그대로(DB 변경 없음 · 새 번호는 화면이 꺼진 줄 포함 최대 + 1)
--   판정 343  덩이 계약(없는 열쇠 = 그대로 · [] = 전부 지움/끔 · is_active false 줄 = 없는 줄 · 읽기 전용 칸 통과 · 모르는 열쇠 field_unknown) + 걸기 조건 ≥ 1 → 0 이면 ack rules_open_to_all{n_before}(만들기 제외)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 둘은 마지막 정의 바이트 복사 + 더한 줄만(product_update 20261006183851:487~1358 · so_deal_save 20261007001229:158~784) · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다
--   원칙 1: IMS 는 Cin7 없이 돈다 — 태그 · 딜은 IMS 에서 붙이고 고친다 · cin7 출처 행의 source 는 그대로(판정 339 는 아직)
-- ─────────────────────────────────────────────────────────────
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

-- ═══ 1) product_update 재발행 — tag_add · tag_off(판정 336) · 마지막 정의 20261006183851:487~1358(DB md5 는 검증 G0 이 대조) · 더한 줄: declare 둘 · op 목록 · 검사 가지 · 저장 가지 넷 ═══
create or replace function public.product_update(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_n        int;
  v_i        int := 0;
  v_c        jsonb;
  v_op       text;
  v_field    text;
  v_sku      text;
  v_key      text;
  v_val      jsonb;
  v_vtxt     text;
  v_old      jsonb;
  v_cur      text;
  p          public.product%rowtype;
  v_par      public.product%rowtype;
  v_fam      public.product_family%rowtype;
  v_brand    public.ref_brand%rowtype;
  v_cat      public.ref_category%rowtype;
  v_unit     public.ref_unit%rowtype;
  v_seen     text[] := '{}';          -- '<product id>|<field>' · family_head: 'F<family id>|<field>'
  v_newsku   text[] := '{}';          -- 이 호출이 짓는 SKU 전부(낱개 새 SKU · 따라 바뀌는 세트 SKU)
  v_seenopt  text[] := '{}';          -- '<family id>|<옵션 열쇠>'
  v_idmap    jsonb := '{}'::jsonb;    -- 검사 때 푼 SKU → product id · family SKU → family id (저장은 이 id 로 — 앞 줄이 SKU 를 바꿔도 뒤 줄은 화면이 본 옛 SKU 로 가리킨다 · ⬜2)
  v_axes     int;
  v_opts     text[];
  v_optkey   text;
  v_ex       record;
  v_set      record;
  v_num      numeric;
  v_cnt      bigint;
  v_cnt2     bigint;
  v_cnt3     bigint;
  v_cnt4     bigint;
  v_hn       text;
  v_hc       bigint;
  v_bc       text;                                                                             -- prod-4b: 바코드 · 가격 · 공급처 op
  v_tag      text;                                                                             -- dsc-4b 판정 336: 태그 op
  v_tagseen  text[] := '{}';                                                                   -- dsc-4b: 이 호출이 붙이는 태그(대소문자 충돌 · 같은 호출)
  v_tier     public.ref_price_tier%rowtype;
  v_sup      public.supplier%rowtype;
  v_row      record;
  v_calc     numeric;
  v_fol      bigint;
  v_stay     bigint;
  v_oldv     jsonb;
  v_img      record;                                                                           -- img-1: 사진 op
  v_ids      uuid[];
  v_path     text;
  v_keys     text[];
  v_unacked  text[];
  v_newname  text;
  v_fml      jsonb;                                                                            -- price-1: price_set 의 formula 재계산(price_formula_calc 반환)
  v_fver     jsonb := '{}'::jsonb;                                                             -- price-1: 줄 번호 → {source, formula_id, supplier_id} — 검사가 정하고 저장이 읽는다(저장 직전 재검사가 다시 정한다 · 판정 176)
  v_fcost    numeric;
  v_fsup     uuid;
  v_grp      public.so_surcharge_group%rowtype;                                                -- surcharge-4a: op surcharge_group_set
  v_fprice   numeric;
  v_src      text;
  v_fields   constant text[] := array['name', 'brand_id', 'category_id', 'unit_id', 'weight', 'weight_unit', 'note', 'is_discontinued', 'set_discount_pct', 'sku', 'is_active', 'pack_factor', 'parent_sku', 'sellable'];   -- dsc-1 판정 281-4 · 294: sellable(boolean · master · 끄기 경고 sellable_off_open_lines)
  v_hfields  constant text[] := array['name', 'brand_id', 'category_id', 'unit_id', 'note', 'is_active', 'option1_name', 'option2_name', 'option3_name'];
  v_open_so  constant text[] := array['draft', 'confirmed', 'at_wms', 'picking', 'packed'];
  v_open_po  constant text[] := array['draft', 'confirmed'];
begin
  perform public.ims_require_write('master', 'saved');                                        -- ⭐ 유일한 문 — 첫 줄(판정 140)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;

  -- ① 모양
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    raise exception 'p_changes must be a JSON array of changes — nothing was saved';
  end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then
    raise exception 'No changes given — nothing was saved';
  end if;
  if v_n > 1000 then
    raise exception 'Too many changes in one call (% — the limit is 1000) — split the paste — nothing was saved', v_n;
  end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    if coalesce(v_c->>'op', '') not in ('set', 'family_join', 'family_leave', 'family_option', 'family_head_set',
                                         'barcode_add', 'barcode_off', 'barcode_primary', 'price_set', 'price_off', 'supplier_set', 'supplier_default', 'supplier_off',   -- prod-4b 여덟
                                         'image_add', 'image_off', 'image_primary', 'image_order',                                                                              -- img-1 넷
                                         'surcharge_group_set',                                                                                                                -- surcharge-4a 하나
                                         'tag_add', 'tag_off') then                                                                                                               -- dsc-4b 둘(판정 336)
      raise exception 'Unknown op "%" — set, family_join, family_leave, family_option, family_head_set, barcode_add, barcode_off, barcode_primary, price_set, price_off, supplier_set, supplier_default, supplier_off, image_add, image_off, image_primary, image_order, surcharge_group_set, tag_add or tag_off — nothing was saved', coalesce(v_c->>'op', '(none)');
    end if;
  end loop;

  -- ② 줄마다 막기 · 알리기 — 전부 모은다(첫 막기에서 멈추지 않는다)
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_field := v_c->>'field';
    v_val := v_c->'value';
    v_vtxt := nullif(trim(coalesce(v_c->>'value', '')), '');
    v_old := v_c->'old';
    p := null; v_fam := null;

    if v_op = 'family_head_set' then
      -- ── family 머리 칸 ─────────────────────────────────────────────────────────────────────────────────
      v_sku := trim(coalesce(v_c->>'family_sku', ''));
      v_key := case when v_sku = '' then '(family)' else v_sku end;
      v_changes := v_changes || jsonb_build_object('i', v_i, 'sku', v_sku, 'op', v_op, 'field', v_field, 'applied', false);
      select * into v_fam from public.product_family f where f.sku = v_sku;
      if v_fam.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_unknown', 'sku', v_sku, 'code', 'family_unknown', 'message', format('Family %s does not exist — nothing was saved', v_sku));
        continue;
      end if;
      v_idmap := v_idmap || jsonb_build_object('F' || v_sku, v_fam.id);
      if v_field is null or not (v_field = any(v_hfields)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || coalesce(v_field, '(none)'), 'sku', v_sku, 'code', 'field_unknown', 'message', format('Family %s: "%s" is not a field this window changes — nothing was saved', v_sku, coalesce(v_field, '(none)')));
        continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_field, 'sku', v_sku, 'code', 'old_missing', 'message', format('Family %s %s: the old value the screen saw is missing — nothing was saved', v_sku, v_field));
        continue;
      end if;
      if ('F' || v_fam.id::text || '|' || v_field) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_field, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Family %s %s is changed twice in this paste — nothing was saved', v_sku, v_field));
        continue;
      end if;
      v_seen := v_seen || ('F' || v_fam.id::text || '|' || v_field);
      v_cur := case v_field when 'name' then v_fam.name when 'brand_id' then v_fam.brand_id::text when 'category_id' then v_fam.category_id::text when 'unit_id' then v_fam.unit_id::text
                            when 'note' then v_fam.note when 'is_active' then v_fam.is_active::text when 'option1_name' then v_fam.option1_name when 'option2_name' then v_fam.option2_name else v_fam.option3_name end;
      if v_cur is distinct from nullif(v_c->>'old', '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_field, 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of family %s (now "%s") — check again — nothing was saved', v_field, v_sku, coalesce(v_cur, '')));
        continue;
      end if;
      if v_field = 'name' and v_vtxt is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'sku', v_sku, 'code', 'name_missing', 'message', format('Family %s cannot have an empty name — nothing was saved', v_sku));
      elsif v_field = 'brand_id' and v_vtxt is not null and not exists (select 1 from public.ref_brand b where b.id = v_vtxt::uuid and b.is_active) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':brand_unknown', 'sku', v_sku, 'code', 'brand_unknown', 'message', format('Family %s: the brand does not exist or is inactive — nothing was saved', v_sku));
      elsif v_field = 'category_id' and v_vtxt is not null and not exists (select 1 from public.ref_category c where c.id = v_vtxt::uuid and c.is_active) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':category_unknown', 'sku', v_sku, 'code', 'category_unknown', 'message', format('Family %s: the category does not exist or is inactive — nothing was saved', v_sku));
      elsif v_field = 'unit_id' and v_vtxt is not null and not exists (select 1 from public.ref_unit u where u.id = v_vtxt::uuid and u.is_active) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':unit_unknown', 'sku', v_sku, 'code', 'unit_unknown', 'message', format('Family %s: the unit does not exist or is inactive — nothing was saved', v_sku));
      elsif v_field = 'is_active' and jsonb_typeof(v_val) <> 'boolean' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:is_active', 'sku', v_sku, 'code', 'value_invalid', 'message', format('Family %s is_active must be true or false — nothing was saved', v_sku));
      elsif v_field = 'is_active' and not (v_val)::boolean then
        select count(*) into v_cnt from public.product x where x.family_id = v_fam.id and x.is_active;
        if v_cnt > 0 then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_variants_on', 'sku', v_sku, 'code', 'inactive_variants_on', 'message', format('Family %s still has %s active variant(s) — they stay active', v_sku, v_cnt));
        end if;
      elsif v_field like 'option%\_name' then
        if (v_cur is null) <> (v_vtxt is null) then                                          -- ⬜6: 축을 더하거나 빼는 것은 변형마다 값이 필요하다 — 이 차수는 이름 바꾸기만
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':axis_count_change:' || v_field, 'sku', v_sku, 'code', 'axis_count_change', 'message', format('Family %s: adding or removing an option axis is not done here (every variant needs a value) — rename only — nothing was saved', v_sku));
        elsif v_vtxt is not null then
          if not exists (select 1 from public.product_family f where f.is_active and v_vtxt in (f.option1_name, f.option2_name, f.option3_name)) then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':option_name_unusual:' || v_vtxt, 'sku', v_sku, 'code', 'option_name_unusual', 'message', format('Option axis "%s" is not used by any active family yet — check the spelling (e.g. Color vs Colour)', v_vtxt));
          else
            select h.common_name, h.n_families into v_hn, v_hc from public.product_axis_case_hint(v_vtxt) h;
            if v_hn is not null then
              v_warns := v_warns || jsonb_build_object('key', v_key || ':option_name_case:' || v_vtxt, 'sku', v_sku, 'code', 'option_name_case', 'message', format('Option axis "%s" — %s active families spell it "%s" — use that spelling unless this is on purpose', v_vtxt, v_hc, v_hn));
            end if;
          end if;
        end if;
      end if;
      if v_field in ('brand_id', 'category_id', 'unit_id')                                     -- prod-4b 판정 191 · 192: 옛 머리 값과 같던 변형만 따라간다(null 끼리도 같다) · 수를 열쇠에(⬜5)
         and (v_vtxt is null or (v_field = 'brand_id' and exists (select 1 from public.ref_brand b where b.id = v_vtxt::uuid and b.is_active))
                              or (v_field = 'category_id' and exists (select 1 from public.ref_category c where c.id = v_vtxt::uuid and c.is_active))
                              or (v_field = 'unit_id' and exists (select 1 from public.ref_unit u where u.id = v_vtxt::uuid and u.is_active))) then
        select count(*) filter (where (case v_field when 'brand_id' then x.brand_id when 'category_id' then x.category_id else x.unit_id end) is not distinct from v_cur::uuid),
               count(*) filter (where (case v_field when 'brand_id' then x.brand_id when 'category_id' then x.category_id else x.unit_id end) is distinct from v_cur::uuid)
          into v_fol, v_stay from public.product x where x.family_id = v_fam.id;
        if v_fol > 0 then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':variants_follow:' || v_field || ':' || v_fol, 'sku', v_sku, 'code', 'variants_follow', 'message', format('Family %s: %s variant(s) that still carry the old %s will follow the family — %s with their own value stay as they are', v_sku, v_fol, replace(v_field, '_id', ''), v_stay));
        end if;
      end if;
      continue;
    end if;

    -- ── 상품 줄 공통: SKU 로 찾는다(이 호출이 SKU 를 바꾸는 줄이 있어도 다른 줄은 화면이 본 옛 SKU 로 가리킨다 · ⬜2) ─────────────
    v_sku := trim(coalesce(v_c->>'sku', ''));
    v_key := case when v_sku = '' then '(blank)' else v_sku end;
    v_changes := v_changes || jsonb_build_object('i', v_i, 'sku', v_sku, 'op', v_op, 'field', v_field, 'applied', false);
    select * into p from public.product x where x.sku = v_sku;
    if p.id is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_unknown', 'sku', v_sku, 'code', 'sku_unknown', 'message', format('SKU %s does not exist — nothing was saved', v_sku));
      continue;
    end if;
    v_idmap := v_idmap || jsonb_build_object('P' || v_sku, p.id);

    if v_op = 'set' then
      if v_field is null or not (v_field = any(v_fields)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || coalesce(v_field, '(none)'), 'sku', v_sku, 'code', 'field_unknown', 'message', format('SKU %s: "%s" is not a field this window changes — nothing was saved', v_sku, coalesce(v_field, '(none)')));
        continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_field, 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s %s: the old value the screen saw is missing — nothing was saved', v_sku, v_field));
        continue;
      end if;
      if (p.id::text || '|' || v_field) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_field, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s %s is changed twice in this paste — nothing was saved', v_sku, v_field));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|' || v_field);
      v_cur := case v_field
                 when 'name' then p.name when 'brand_id' then p.brand_id::text when 'category_id' then p.category_id::text when 'unit_id' then p.unit_id::text
                 when 'weight' then p.weight::text when 'weight_unit' then p.weight_unit when 'note' then p.note when 'is_discontinued' then p.is_discontinued::text
                 when 'set_discount_pct' then p.set_discount_pct::text when 'sku' then p.sku when 'is_active' then p.is_active::text when 'pack_factor' then p.pack_factor::text
                 when 'sellable' then p.sellable::text
                 when 'parent_sku' then (select x.sku from public.product x where x.id = p.parent_product_id) end;
      if v_cur is distinct from nullif(v_c->>'old', '') and not (v_field in ('weight', 'set_discount_pct', 'pack_factor') and v_cur is not null and nullif(v_c->>'old', '') is not null and v_cur::numeric = (v_c->>'old')::numeric) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_field, 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of %s (now "%s") — check again — nothing was saved', v_field, v_sku, coalesce(v_cur, '')));
        continue;
      end if;

      case v_field
      when 'name' then
        if v_vtxt is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'sku', v_sku, 'code', 'name_missing', 'message', format('SKU %s cannot have an empty name — nothing was saved', v_sku));
        end if;
      when 'brand_id' then
        if v_vtxt is not null and not exists (select 1 from public.ref_brand b where b.id = v_vtxt::uuid and b.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':brand_unknown', 'sku', v_sku, 'code', 'brand_unknown', 'message', format('SKU %s: the brand does not exist or is inactive — nothing was saved', v_sku));
        end if;
      when 'category_id' then
        if v_vtxt is not null and not exists (select 1 from public.ref_category c where c.id = v_vtxt::uuid and c.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':category_unknown', 'sku', v_sku, 'code', 'category_unknown', 'message', format('SKU %s: the category does not exist or is inactive — nothing was saved', v_sku));
        end if;
      when 'unit_id' then
        if v_vtxt is not null and not exists (select 1 from public.ref_unit u where u.id = v_vtxt::uuid and u.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':unit_unknown', 'sku', v_sku, 'code', 'unit_unknown', 'message', format('SKU %s: the unit does not exist or is inactive — nothing was saved', v_sku));
        elsif p.parent_product_id is not null and v_vtxt is not null and (select u.name from public.ref_unit u where u.id = v_vtxt::uuid) is distinct from p.pack_factor::int::text then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':set_unit_mismatch', 'sku', v_sku, 'code', 'set_unit_mismatch', 'message', format('Set %s: unit "%s" differs from its pack factor %s', v_sku, (select u.name from public.ref_unit u where u.id = v_vtxt::uuid), p.pack_factor::int));
        end if;
      when 'weight' then
        if v_vtxt is not null and (v_vtxt !~ '^[0-9]+(\.[0-9]+)?$') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':weight_invalid', 'sku', v_sku, 'code', 'weight_invalid', 'message', format('SKU %s: weight must be a number of 0 or more — nothing was saved', v_sku));
        end if;
      when 'is_discontinued' then
        if jsonb_typeof(v_val) <> 'boolean' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:is_discontinued', 'sku', v_sku, 'code', 'value_invalid', 'message', format('SKU %s is_discontinued must be true or false — nothing was saved', v_sku));
        end if;
      when 'set_discount_pct' then
        if p.parent_product_id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':not_a_set', 'sku', v_sku, 'code', 'not_a_set', 'message', format('SKU %s is not a set — the set discount belongs to sets only — nothing was saved', v_sku));
        elsif v_vtxt is not null and (v_vtxt !~ '^[0-9]+(\.[0-9]+)?$' or v_vtxt::numeric > 100) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_discount_invalid', 'sku', v_sku, 'code', 'set_discount_invalid', 'message', format('Set %s: the set discount must be between 0 and 100 — nothing was saved', v_sku));
        end if;
      when 'sellable' then                                                                       -- dsc-1 판정 281-4 · 294
        if jsonb_typeof(v_val) <> 'boolean' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:sellable', 'sku', v_sku, 'code', 'value_invalid', 'message', format('SKU %s sellable must be true or false — nothing was saved', v_sku));
        elsif not (v_val)::boolean then
          select count(*) into v_cnt from public.so_line l join public.so s on s.id = l.so_id where l.product_id = p.id and s.status = any(v_open_so);
          if v_cnt > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':sellable_off_open_lines', 'sku', v_sku, 'code', 'sellable_off_open_lines', 'count', v_cnt, 'message', format('SKU %s is on %s open order line(s) — they keep their prices; new lines will be refused once it is not for sale. Confirm to turn Sellable off', v_sku, v_cnt));
          end if;
        end if;
      when 'is_active' then
        if jsonb_typeof(v_val) <> 'boolean' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:is_active', 'sku', v_sku, 'code', 'value_invalid', 'message', format('SKU %s is_active must be true or false — nothing was saved', v_sku));
        elsif not (v_val)::boolean then                                                        -- 끄기 — 0 이 아닌 것만 알린다(판정 139 · ⬜4)
          select coalesce(sum(b.qty), 0) into v_num from public.ims_inv_balance b where b.sku = p.sku;
          select count(*) into v_cnt  from public.so_line l join public.so s on s.id = l.so_id where l.product_id = p.id and s.status = any(v_open_so);
          select count(*) into v_cnt2 from public.po_line l join public.po o on o.id = l.po_id where (l.product_id = p.id or l.entered_unit_product_id = p.id) and o.status = any(v_open_po);
          select count(*) into v_cnt3 from public.product x where x.parent_product_id = p.id and x.is_active;
          if v_num <> 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_stock', 'sku', v_sku, 'code', 'inactive_stock', 'message', format('SKU %s still has stock on hand (%s) — it stays in the ledger after it is turned off', v_sku, v_num));
          end if;
          if v_cnt > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_so', 'sku', v_sku, 'code', 'inactive_open_so', 'message', format('SKU %s is on %s open sales order line(s)', v_sku, v_cnt));
          end if;
          if v_cnt2 > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_po', 'sku', v_sku, 'code', 'inactive_open_po', 'message', format('SKU %s is on %s open purchase order line(s)', v_sku, v_cnt2));
          end if;
          if v_cnt3 > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_sets_on', 'sku', v_sku, 'code', 'inactive_sets_on', 'message', format('SKU %s has %s active set(s) — they are not turned off with it', v_sku, v_cnt3));
          end if;
        end if;
      when 'sku' then
        v_newname := v_vtxt;
        if p.parent_product_id is not null then                                                 -- 세트 SKU 는 창구가 짓는다(판정 177 · 189) — 부모나 계수를 바꾼다
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_sku_managed', 'sku', v_sku, 'code', 'set_sku_managed', 'message', format('Set %s: a set SKU is built from its parent SKU and pack factor — change the parent or the pack factor instead — nothing was saved', v_sku));
        elsif v_newname is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_space', 'sku', v_sku, 'code', 'sku_space', 'message', format('SKU %s: the new SKU is empty — nothing was saved', v_sku));
        else
          if v_newname ~ '\s' then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_space', 'sku', v_sku, 'code', 'sku_space', 'message', format('New SKU "%s" contains a space — nothing was saved', v_newname));
          end if;
          if v_newname ~ '[a-z]' then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_lowercase', 'sku', v_sku, 'code', 'sku_lowercase', 'message', format('New SKU %s has lowercase letters — use capitals — nothing was saved', v_newname));
          end if;
          if v_newname <> p.sku and exists (select 1 from public.product x where x.sku = v_newname) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_exists:' || v_newname, 'sku', v_sku, 'code', 'sku_exists', 'message', format('SKU %s already exists (active or inactive) — nothing was saved', v_newname));
          end if;
          if v_newname = any(v_newsku) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_duplicate_in_call:' || v_newname, 'sku', v_sku, 'code', 'sku_duplicate_in_call', 'message', format('SKU %s is produced twice in this paste — nothing was saved', v_newname));
          end if;
          v_newsku := v_newsku || v_newname;
          if exists (select 1 from public.inv_ledger e where e.sku = p.sku) or exists (select 1 from public.inv_layer l where l.sku = p.sku) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_locked', 'sku', v_sku, 'code', 'sku_locked', 'message', format('SKU %s has stock or cost history and cannot be renamed — create a new product instead — nothing was saved', v_sku));
          end if;
          -- 세트 따라 고침(판정 189) — 하나라도 기록이면 전체 막기 · 새 세트 SKU 가 이미 있으면 막기 · 이름은 그대로(알리기)
          v_cnt := 0;
          for v_set in select x.id, x.sku, x.pack_factor from public.product x where x.parent_product_id = p.id order by x.sku loop
            v_cnt := v_cnt + 1;
            if exists (select 1 from public.inv_ledger e where e.sku = v_set.sku) or exists (select 1 from public.inv_layer l where l.sku = v_set.sku) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_locked_set:' || v_set.sku, 'sku', v_sku, 'code', 'sku_locked_set', 'message', format('Set %s has stock or cost history — its parent SKU cannot be renamed — nothing was saved', v_set.sku));
            end if;
            if exists (select 1 from public.product x where x.sku = v_newname || '-' || v_set.pack_factor::int::text and x.id <> v_set.id) or (v_newname || '-' || v_set.pack_factor::int::text) = any(v_newsku) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_sku_exists:' || v_newname || '-' || v_set.pack_factor::int::text, 'sku', v_sku, 'code', 'set_sku_exists', 'message', format('Set SKU %s already exists — nothing was saved', v_newname || '-' || v_set.pack_factor::int::text));
            end if;
            v_newsku := v_newsku || (v_newname || '-' || v_set.pack_factor::int::text);
          end loop;
          if v_cnt > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':set_renamed', 'sku', v_sku, 'code', 'set_renamed', 'message', format('%s set SKU(s) of %s will be renamed to %s-<factor> too — their names are not changed', v_cnt, v_sku, v_newname));
          end if;
          if public.product_has_events(p.id, p.sku) and not exists (select 1 from public.inv_ledger e where e.sku = p.sku) and not exists (select 1 from public.inv_layer l where l.sku = p.sku) then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':sku_open_lines', 'sku', v_sku, 'code', 'sku_open_lines', 'message', format('SKU %s is already on order or document lines — they keep pointing at the product, but printed line text still shows %s', v_sku, v_sku));
          end if;
        end if;
      when 'pack_factor' then
        if p.parent_product_id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':not_a_set', 'sku', v_sku, 'code', 'not_a_set', 'message', format('SKU %s is not a set — pack factor belongs to sets only — nothing was saved', v_sku));
        elsif v_vtxt is null or v_vtxt !~ '^[0-9]+$' or v_vtxt::numeric < 2 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_factor_invalid', 'sku', v_sku, 'code', 'set_factor_invalid', 'message', format('Set %s: the pack factor must be a whole number of 2 or more (got %s) — nothing was saved', v_sku, coalesce(v_vtxt, 'nothing')));
        else
          select * into v_par from public.product x where x.id = p.parent_product_id;
          if public.product_has_events(p.id, p.sku) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_locked', 'sku', v_sku, 'code', 'set_locked', 'message', format('Set %s already has stock, cost or document lines — its pack factor cannot change — make a new set instead — nothing was saved', v_sku));
          end if;
          v_newname := v_par.sku || '-' || v_vtxt::numeric::int::text;
          if exists (select 1 from public.product x where x.sku = v_newname and x.id <> p.id) or v_newname = any(v_newsku) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_sku_exists:' || v_newname, 'sku', v_sku, 'code', 'set_sku_exists', 'message', format('Set SKU %s already exists — nothing was saved', v_newname));
          end if;
          v_newsku := v_newsku || v_newname;
          if not exists (select 1 from public.ref_unit u where u.name = v_vtxt::numeric::int::text and u.is_active) then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':set_unit_unknown', 'sku', v_sku, 'code', 'set_unit_unknown', 'message', format('Set %s: there is no unit named %s — the set keeps uom %s but no unit id', v_sku, v_vtxt::numeric::int, v_vtxt::numeric::int));
          end if;
        end if;
      when 'parent_sku' then
        if p.parent_product_id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':not_a_set', 'sku', v_sku, 'code', 'not_a_set', 'message', format('SKU %s is not a set — a parent belongs to sets only — nothing was saved', v_sku));
        else
          select * into v_par from public.product x where x.sku = v_vtxt;
          if v_par.id is null or not v_par.is_active then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'sku', v_sku, 'code', 'parent_unknown', 'message', format('Set %s: the new parent %s does not exist or is inactive — nothing was saved', v_sku, coalesce(v_vtxt, '(none)')));
          elsif v_par.parent_product_id is not null then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_not_single', 'sku', v_sku, 'code', 'parent_not_single', 'message', format('Set %s: the new parent %s is itself a set — a parent must be a single — nothing was saved', v_sku, v_par.sku));
          else
            if public.product_has_events(p.id, p.sku) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_locked', 'sku', v_sku, 'code', 'set_locked', 'message', format('Set %s already has stock, cost or document lines — its parent cannot change — make a new set instead — nothing was saved', v_sku));
            end if;
            v_newname := v_par.sku || '-' || p.pack_factor::int::text;
            if exists (select 1 from public.product x where x.sku = v_newname and x.id <> p.id) or v_newname = any(v_newsku) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_sku_exists:' || v_newname, 'sku', v_sku, 'code', 'set_sku_exists', 'message', format('Set SKU %s already exists — nothing was saved', v_newname));
            end if;
            v_newsku := v_newsku || v_newname;
          end if;
        end if;
      else null;
      end case;

    elsif v_op = 'family_join' then
      select * into v_fam from public.product_family f where f.sku = trim(coalesce(v_c->>'family_sku', ''));
      if v_fam.id is null or not v_fam.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_unknown', 'sku', v_sku, 'code', 'family_unknown', 'message', format('SKU %s: family %s does not exist or is inactive — nothing was saved', v_sku, coalesce(nullif(trim(v_c->>'family_sku'), ''), '(none)')));
        continue;
      end if;
      if p.parent_product_id is not null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_not_family_member', 'sku', v_sku, 'code', 'set_not_family_member', 'message', format('SKU %s is a set — sets follow their single and are not family members — nothing was saved', v_sku));
        continue;
      end if;
      if p.family_id is not null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':already_in_family', 'sku', v_sku, 'code', 'already_in_family', 'message', format('SKU %s is already in family %s — leave it first — nothing was saved', v_sku, (select f.sku from public.product_family f where f.id = p.family_id)));
        continue;
      end if;
      if (p.id::text || '|family') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:family', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s family membership is changed twice in this paste — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|family');
      v_axes := (v_fam.option1_name is not null)::int + (v_fam.option2_name is not null)::int + (v_fam.option3_name is not null)::int;
      select coalesce(array_agg(trim(t.x) order by t.o), '{}') into v_opts from jsonb_array_elements_text(coalesce(v_c->'options', '[]'::jsonb)) with ordinality as t(x, o);
      if cardinality(v_opts) <> v_axes or exists (select 1 from unnest(v_opts) o where o = '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_count', 'sku', v_sku, 'code', 'option_count', 'message', format('SKU %s needs %s option value(s) for family %s — got %s — nothing was saved', v_sku, v_axes, v_fam.sku, coalesce(nullif(array_to_string(v_opts, ' / '), ''), 'none')));
        continue;
      end if;
      v_optkey := lower(array_to_string(v_opts, '|'));
      if (v_fam.id::text || '|' || v_optkey) = any(v_seenopt) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_duplicate_in_call', 'sku', v_sku, 'code', 'option_duplicate_in_call', 'message', format('SKU %s repeats the option values %s already used in this paste for family %s — nothing was saved', v_sku, array_to_string(v_opts, ' / '), v_fam.sku));
      end if;
      v_seenopt := v_seenopt || (v_fam.id::text || '|' || v_optkey);
      select x.sku, x.is_active into v_ex from public.product x
       where x.family_id = v_fam.id and x.id <> p.id and lower(array_to_string((array[trim(x.option1_value), trim(x.option2_value), trim(x.option3_value)])[1:v_axes], '|')) = v_optkey
       order by x.is_active desc, x.sku limit 1;
      if found then
        if v_ex.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_exists', 'sku', v_sku, 'code', 'option_exists', 'message', format('Family %s already has %s as %s — nothing was saved', v_fam.sku, array_to_string(v_opts, ' / '), v_ex.sku));
        else
          v_warns := v_warns || jsonb_build_object('key', v_key || ':option_inactive_exists', 'sku', v_sku, 'code', 'option_inactive_exists', 'message', format('Family %s has an inactive variant %s with %s — reactivating it may be the right move', v_fam.sku, v_ex.sku, array_to_string(v_opts, ' / ')));
        end if;
      end if;

    elsif v_op = 'family_leave' then
      if p.family_id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':not_in_family', 'sku', v_sku, 'code', 'not_in_family', 'message', format('SKU %s is not in a family — nothing was saved', v_sku));
        continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:family', 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s family_leave: the family the screen saw is missing — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|family') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:family', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s family membership is changed twice in this paste — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|family');
      v_cur := (select f.sku from public.product_family f where f.id = p.family_id);
      if v_cur is distinct from nullif(v_c->>'old', '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:family', 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the family of %s (now %s) — check again — nothing was saved', v_sku, coalesce(v_cur, '')));
      end if;

    elsif v_op = 'family_option' then
      if p.family_id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':not_in_family', 'sku', v_sku, 'code', 'not_in_family', 'message', format('SKU %s is not in a family — nothing was saved', v_sku));
        continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:options', 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s family_option: the old option values the screen saw are missing — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|options') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:options', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s option values are changed twice in this paste — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|options');
      select * into v_fam from public.product_family f where f.id = p.family_id;
      v_axes := (v_fam.option1_name is not null)::int + (v_fam.option2_name is not null)::int + (v_fam.option3_name is not null)::int;
      v_cur := array_to_string((array[p.option1_value, p.option2_value, p.option3_value])[1:v_axes], '|');
      if v_cur is distinct from (select string_agg(coalesce(t.x, ''), '|' order by t.o) from jsonb_array_elements_text(coalesce(v_c->'old', '[]'::jsonb)) with ordinality as t(x, o)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:options', 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the option values of %s (now %s) — check again — nothing was saved', v_sku, replace(coalesce(v_cur, ''), '|', ' / ')));
        continue;
      end if;
      select coalesce(array_agg(trim(t.x) order by t.o), '{}') into v_opts from jsonb_array_elements_text(coalesce(v_c->'options', '[]'::jsonb)) with ordinality as t(x, o);
      if cardinality(v_opts) <> v_axes or exists (select 1 from unnest(v_opts) o where o = '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_count', 'sku', v_sku, 'code', 'option_count', 'message', format('SKU %s needs %s option value(s) for family %s — got %s — nothing was saved', v_sku, v_axes, v_fam.sku, coalesce(nullif(array_to_string(v_opts, ' / '), ''), 'none')));
        continue;
      end if;
      v_optkey := lower(array_to_string(v_opts, '|'));
      if (v_fam.id::text || '|' || v_optkey) = any(v_seenopt) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_duplicate_in_call', 'sku', v_sku, 'code', 'option_duplicate_in_call', 'message', format('SKU %s repeats the option values %s already used in this paste for family %s — nothing was saved', v_sku, array_to_string(v_opts, ' / '), v_fam.sku));
      end if;
      v_seenopt := v_seenopt || (v_fam.id::text || '|' || v_optkey);
      select x.sku, x.is_active into v_ex from public.product x
       where x.family_id = v_fam.id and x.id <> p.id and lower(array_to_string((array[trim(x.option1_value), trim(x.option2_value), trim(x.option3_value)])[1:v_axes], '|')) = v_optkey
       order by x.is_active desc, x.sku limit 1;
      if found then
        if v_ex.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_exists', 'sku', v_sku, 'code', 'option_exists', 'message', format('Family %s already has %s as %s — nothing was saved', v_fam.sku, array_to_string(v_opts, ' / '), v_ex.sku));
        else
          v_warns := v_warns || jsonb_build_object('key', v_key || ':option_inactive_exists', 'sku', v_sku, 'code', 'option_inactive_exists', 'message', format('Family %s has an inactive variant %s with %s — reactivating it may be the right move', v_fam.sku, v_ex.sku, array_to_string(v_opts, ' / ')));
        end if;
      end if;

    -- ── prod-4b: 바코드(판정 179 · 188 · 138 — R2 는 안 본다) ───────────────────────────────────────────────────
    elsif v_op in ('barcode_add', 'barcode_off', 'barcode_primary') then
      v_bc := trim(coalesce(v_c->>'barcode', ''));
      if v_bc = '' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':barcode_empty', 'sku', v_sku, 'code', 'barcode_empty', 'message', format('SKU %s has an empty barcode — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|bc|' || v_bc) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_bc, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Barcode %s of %s is changed twice in this paste — nothing was saved', v_bc, v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|bc|' || v_bc);
      select pb.id, pb.is_active, pb.is_primary into v_row from public.product_barcode pb where pb.product_id = p.id and pb.barcode = v_bc;
      if v_op = 'barcode_add' then
        if v_row.id is not null and v_row.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':barcode_exists:' || v_bc, 'sku', v_sku, 'code', 'barcode_exists', 'message', format('Barcode %s is already on %s — nothing was saved', v_bc, v_sku));
        end if;
        if ('B|' || v_bc) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':barcode_duplicate_in_call:' || v_bc, 'sku', v_sku, 'code', 'barcode_duplicate_in_call', 'message', format('Barcode %s is added to two products in this paste — nothing was saved', v_bc));
        end if;
        v_seen := v_seen || ('B|' || v_bc);
        select x.sku, (x.is_active and pb.is_active) as active into v_ex
          from public.product_barcode pb join public.product x on x.id = pb.product_id
         where pb.barcode = v_bc and pb.product_id <> p.id order by (x.is_active and pb.is_active) desc, x.sku limit 1;
        if found then
          if v_ex.active then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':barcode_active_elsewhere:' || v_bc, 'sku', v_sku, 'code', 'barcode_active_elsewhere', 'message', format('Barcode %s already belongs to active product %s — a scan would pick the wrong product — nothing was saved', v_bc, v_ex.sku));
          else
            v_warns := v_warns || jsonb_build_object('key', v_key || ':barcode_inactive_elsewhere:' || v_bc, 'sku', v_sku, 'code', 'barcode_inactive_elsewhere', 'message', format('Barcode %s is also on inactive product %s', v_bc, v_ex.sku));
          end if;
        end if;
        if v_bc !~ '^[0-9]+$' or length(v_bc) not in (8, 12, 13, 14) then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':barcode_shape:' || v_bc, 'sku', v_sku, 'code', 'barcode_shape', 'message', format('Barcode %s is not 8, 12, 13 or 14 digits', v_bc));
        elsif length(v_bc) in (12, 13) and not public.product_gtin_ok(v_bc) then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':barcode_check_digit:' || v_bc, 'sku', v_sku, 'code', 'barcode_check_digit', 'message', format('Barcode %s fails the check digit — a typo is likely', v_bc));
        end if;
      else
        if v_row.id is null or not v_row.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':barcode_not_found:' || v_bc, 'sku', v_sku, 'code', 'barcode_not_found', 'message', format('SKU %s has no active barcode %s — nothing was saved', v_sku, v_bc));
          continue;
        end if;
        if v_op = 'barcode_off' then
          if v_row.is_primary then                                                               -- ⬜1: 대표를 끄면 대표 없음 — 올리지 않고 알린다
            v_warns := v_warns || jsonb_build_object('key', v_key || ':primary_off:' || v_bc, 'sku', v_sku, 'code', 'primary_off', 'message', format('Barcode %s is the primary barcode of %s — after it is turned off the product has no primary — pick another one', v_bc, v_sku));
          end if;
          if (select count(*) from public.product_barcode pb where pb.product_id = p.id and pb.is_active) = 1 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':barcode_missing', 'sku', v_sku, 'code', 'barcode_missing', 'message', format('SKU %s has no barcode — it cannot be scanned in picking, packing or receiving', v_sku));
          end if;
        end if;
      end if;

    -- ── dsc-4b: 태그(판정 336 · 332 의 짝 — btrim 만 · 대소문자만 다른 태그는 막는다 · 떼기는 행 삭제) ──────────────────────────
    elsif v_op in ('tag_add', 'tag_off') then
      v_tag := btrim(coalesce(v_c->>'tag', ''));
      if v_tag = '' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_empty', 'sku', v_sku, 'code', 'tag_empty', 'message', format('SKU %s has an empty tag — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|tag|' || lower(v_tag)) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_tag, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Tag %s of %s is changed twice in this paste — nothing was saved', v_tag, v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|tag|' || lower(v_tag));
      if v_op = 'tag_add' then
        if exists (select 1 from public.product_tag pt where pt.product_id = p.id and pt.tag = v_tag) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_exists:' || v_tag, 'sku', v_sku, 'code', 'tag_exists', 'message', format('Tag %s is already on %s — nothing was saved', v_tag, v_sku));
          continue;
        end if;
        select min(pt.tag) into v_cur from public.product_tag pt where lower(pt.tag) = lower(v_tag) and pt.tag <> v_tag;                                          -- 판정 332 의 짝: 제품 태그 전체
        if v_cur is null then select min(x.tag) into v_cur from public.so_deal_target x where lower(x.tag) = lower(v_tag) and x.tag <> v_tag; end if;              -- 딜 대상
        if v_cur is null then select min(g) into v_cur from unnest(v_tagseen) g where lower(g) = lower(v_tag) and g <> v_tag; end if;                               -- 같은 호출
        if v_cur is not null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_case_conflict:' || v_tag, 'sku', v_sku, 'code', 'tag_case_conflict', 'message', format('Tag "%s" differs only by case from "%s" — use the existing spelling — nothing was saved', v_tag, v_cur));
          continue;
        end if;
        v_tagseen := v_tagseen || v_tag;
      else
        if not exists (select 1 from public.product_tag pt where pt.product_id = p.id and pt.tag = v_tag) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_not_found:' || v_tag, 'sku', v_sku, 'code', 'tag_not_found', 'message', format('SKU %s does not carry tag %s — nothing was saved', v_sku, v_tag));
          continue;
        end if;
        if (select count(*) from public.product_tag pt where pt.tag = v_tag) = 1 then                                                                               -- ⬜ 알리기: 켜진 딜의 켜진 줄이 이 태그로 걸고 · 떼면 이 태그의 제품이 0
          select string_agg(distinct d.name, ', ') into v_cur
            from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id join public.so_deal d on d.id = l.deal_id
           where x.target = 'tag' and x.tag = v_tag and l.is_active and d.is_active;
          if v_cur is not null then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':tag_off_used_by_deal:' || v_tag, 'sku', v_sku, 'code', 'tag_off_used_by_deal', 'deals', v_cur, 'message', format('Tag %s is the last one of its kind and active deal(s) %s target it — after this they match nothing on this tag', v_tag, v_cur));
            v_keys := array_append(v_keys, v_key || ':tag_off_used_by_deal:' || v_tag);
          end if;
        end if;
      end if;
    -- ── prod-4b: 판매가(판정 178 · source manual ⬜2) ──────────────────────────────────────────────────────────
    elsif v_op in ('price_set', 'price_off') then
      select * into v_tier from public.ref_price_tier t where t.id = (v_c->>'tier_id')::uuid and t.is_active and t.purpose = 'sale';
      if v_c->>'tier_id' is null or v_tier.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_invalid', 'sku', v_sku, 'code', 'tier_invalid', 'message', format('SKU %s: a price tier is missing, inactive or not a sale tier — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|pr|' || v_tier.id::text) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_tier.code, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s price for tier %s is changed twice in this paste — nothing was saved', v_sku, v_tier.name));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|pr|' || v_tier.id::text);
      select pp.id, pp.is_active, pp.price into v_row from public.product_price pp where pp.product_id = p.id and pp.tier_id = v_tier.id;
      if v_op = 'price_set' then
        if (v_c->>'price') is null or (v_c->>'price') !~ '^[0-9]+(\.[0-9]+)?$' or (v_c->>'price')::numeric <= 0 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':price_not_positive:' || v_tier.code, 'sku', v_sku, 'code', 'price_not_positive', 'message', format('SKU %s: a price must be greater than 0 (leave the tier out for no price) — nothing was saved', v_sku));
          continue;
        end if;
        if v_row.id is not null and v_row.is_active then                                        -- 있는 켜진 줄 고치기 — old 필수 · 숫자 비교
          if not (v_c ? 'old') then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:price:' || v_tier.code, 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s price (%s): the old value the screen saw is missing — nothing was saved', v_sku, v_tier.name));
          elsif nullif(v_c->>'old', '') is null or (v_c->>'old') !~ '^[0-9]+(\.[0-9]+)?$' or v_row.price <> (v_c->>'old')::numeric then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:price:' || v_tier.code, 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the %s price of %s (now %s) — check again — nothing was saved', v_tier.name, v_sku, v_row.price));
          end if;
        end if;
        if v_c ? 'formula' then                                                                 -- price-1(묶음 6 · 판정 222 · 223): 식 표시 → 그 식의 공급처 줄의 지금 Latest 로 다시 계산해 같을 때만 formula
          if p.parent_product_id is not null then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':formula_on_set:' || v_tier.code, 'sku', v_sku, 'code', 'formula_on_set', 'message', format('Set %s: a price formula applies to singles only — sets take the calculated price or a fixed price — nothing was saved', v_sku));
            continue;
          end if;
          v_fml := public.price_formula_calc(v_c->'formula', null);
          if coalesce(jsonb_typeof(v_fml->'formula'), 'null') = 'null' then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':formula_invalid:' || v_tier.code, 'sku', v_sku, 'code', 'formula_invalid', 'message', format('SKU %s: %s — nothing was saved', v_sku, coalesce(v_fml->'blocks'->0->>'message', 'the price formula is invalid')));
            continue;
          end if;
          v_fsup := (v_fml->'formula'->>'supplier_id')::uuid;
          v_fcost := null; v_fprice := null;
          select ps.cost into v_fcost from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = v_fsup and ps.is_active;
          if v_fcost is not null and v_fcost > 0 then
            v_fml := public.price_formula_calc(v_c->'formula', v_fcost);
            select (t->>'price')::numeric into v_fprice from jsonb_array_elements(coalesce(v_fml->'tiers', '[]'::jsonb)) as t where (t->>'tier_id')::uuid = v_tier.id;
          end if;
          if v_fprice is not null and v_fprice = (v_c->>'price')::numeric then
            v_fver := v_fver || jsonb_build_object(v_i::text, jsonb_build_object('source', 'formula', 'formula_id', v_fml->'formula'->>'id', 'supplier_id', v_fsup));
            if (v_fml->'formula'->>'id') is null then
              v_warns := v_warns || jsonb_build_object('key', v_key || ':formula_unsaved:' || v_tier.code, 'sku', v_sku, 'code', 'formula_unsaved', 'message', format('SKU %s %s: the price comes from a one-off formula that is not saved — it is stored as a formula price but the product will not remember which formula', v_sku, v_tier.name));
            end if;
          else
            v_warns := v_warns || jsonb_build_object('key', v_key || ':formula_mismatch:' || v_tier.code, 'sku', v_sku, 'code', 'formula_mismatch', 'message',
              format('SKU %s %s: %s is not what the formula gives now (%s from cost %s) — it will be saved as a manual price', v_sku, v_tier.name, (v_c->>'price')::numeric, coalesce(v_fprice::text, 'nothing'), coalesce(v_fcost::text, 'none')));
          end if;
        end if;
      else
        if v_row.id is null or not v_row.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':price_not_found:' || v_tier.code, 'sku', v_sku, 'code', 'price_not_found', 'message', format('SKU %s has no active %s price — nothing was saved', v_sku, v_tier.name));
          continue;
        end if;
        if not (v_c ? 'old') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:price:' || v_tier.code, 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s price (%s): the old value the screen saw is missing — nothing was saved', v_sku, v_tier.name));
          continue;
        elsif nullif(v_c->>'old', '') is null or (v_c->>'old') !~ '^[0-9]+(\.[0-9]+)?$' or v_row.price <> (v_c->>'old')::numeric then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:price:' || v_tier.code, 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the %s price of %s (now %s) — check again — nothing was saved', v_tier.name, v_sku, v_row.price));
          continue;
        end if;
        if p.parent_product_id is not null then                                                 -- 세트 고정가 끄기 → 계산 가격으로(값까지)
          select round(pp.price * p.pack_factor * (1 - coalesce(p.set_discount_pct, 0) / 100), 2) into v_calc
            from public.product_price pp where pp.product_id = p.parent_product_id and pp.tier_id = v_tier.id and pp.is_active;
          v_warns := v_warns || jsonb_build_object('key', v_key || ':price_set_calc:' || v_tier.code, 'sku', v_sku, 'code', 'price_set_calc', 'message',
            case when v_calc is null then format('Set %s: without its fixed %s price it has no price at all — its single has no %s price to calculate from', v_sku, v_tier.name, v_tier.name)
                 else format('Set %s: without its fixed %s price it goes back to the calculated price %s (single price × %s%s)', v_sku, v_tier.name, v_calc, p.pack_factor::int, case when coalesce(p.set_discount_pct, 0) > 0 then format(' − %s%%', p.set_discount_pct) else '' end) end);
        elsif (select count(*) from public.product_price pp join public.ref_price_tier t on t.id = pp.tier_id where pp.product_id = p.id and pp.is_active and t.purpose = 'sale' and t.is_active) = 1 then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':price_missing', 'sku', v_sku, 'code', 'price_missing', 'message', format('SKU %s has no sale price — order lines will have no price', v_sku));
        end if;
      end if;

    -- ── prod-4b: 공급처(판정 178 · 세트는 알리기 ⬜3 · source manual ⬜2) ────────────────────────────────────────
    elsif v_op in ('supplier_set', 'supplier_default', 'supplier_off') then
      select * into v_sup from public.supplier s where s.id = (v_c->>'supplier_id')::uuid and s.is_active;
      if v_c->>'supplier_id' is null or v_sup.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':supplier_unknown', 'sku', v_sku, 'code', 'supplier_unknown', 'message', format('SKU %s: a supplier is missing, unknown or inactive — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|sp|' || v_sup.id::text) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_sup.name, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s supplier %s is changed twice in this paste — nothing was saved', v_sku, v_sup.name));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|sp|' || v_sup.id::text);
      select ps.id, ps.is_active, ps.is_default, ps.supplier_sku, ps.cost, ps.fixed_cost, ps.currency_id into v_row from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = v_sup.id;
      if v_op = 'supplier_set' then
        if v_c->>'currency_id' is not null and not exists (select 1 from public.ref_currency c where c.id = (v_c->>'currency_id')::uuid and c.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':currency_unknown:' || v_sup.name, 'sku', v_sku, 'code', 'currency_unknown', 'message', format('SKU %s: a supplier currency does not exist or is inactive — nothing was saved', v_sku));
        end if;
        if (v_c ? 'cost' and v_c->>'cost' is not null and (v_c->>'cost') !~ '^[0-9]+(\.[0-9]+)?$') or (v_c ? 'fixed_cost' and v_c->>'fixed_cost' is not null and (v_c->>'fixed_cost') !~ '^[0-9]+(\.[0-9]+)?$') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_sup.name, 'sku', v_sku, 'code', 'value_invalid', 'message', format('SKU %s supplier %s: cost and fixed cost must be numbers of 0 or more — nothing was saved', v_sku, v_sup.name));
        end if;
        if p.parent_product_id is not null then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':set_supplier:' || v_sup.name, 'sku', v_sku, 'code', 'set_supplier', 'message', format('Set %s gets its own supplier %s — sets are normally bought as their single', v_sku, v_sup.name));
        end if;
        if v_row.id is not null and v_row.is_active then                                        -- 있는 켜진 줄 고치기 — 바꾸는 칸마다 old
          v_oldv := coalesce(v_c->'old', '{}'::jsonb);
          if jsonb_typeof(v_oldv) <> 'object' or (v_c ? 'supplier_sku' and not (v_oldv ? 'supplier_sku')) or (v_c ? 'cost' and not (v_oldv ? 'cost')) or (v_c ? 'fixed_cost' and not (v_oldv ? 'fixed_cost')) or (v_c ? 'currency_id' and not (v_oldv ? 'currency_id')) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:supplier:' || v_sup.name, 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s supplier %s: the old value the screen saw is missing for a field being changed — nothing was saved', v_sku, v_sup.name));
          elsif (v_c ? 'supplier_sku' and v_row.supplier_sku is distinct from nullif(v_oldv->>'supplier_sku', ''))
             or (v_c ? 'cost' and v_row.cost is distinct from nullif(v_oldv->>'cost', '')::numeric)
             or (v_c ? 'fixed_cost' and v_row.fixed_cost is distinct from nullif(v_oldv->>'fixed_cost', '')::numeric)
             or (v_c ? 'currency_id' and v_row.currency_id::text is distinct from nullif(v_oldv->>'currency_id', '')) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:supplier:' || v_sup.name, 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed supplier %s of %s (now sku %s · cost %s · fixed %s) — check again — nothing was saved', v_sup.name, v_sku, coalesce(v_row.supplier_sku, '-'), coalesce(v_row.cost::text, '-'), coalesce(v_row.fixed_cost::text, '-')));
          end if;
        end if;
      else
        if v_row.id is null or not v_row.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':supplier_not_found:' || v_sup.name, 'sku', v_sku, 'code', 'supplier_not_found', 'message', format('SKU %s has no active supplier %s — nothing was saved', v_sku, v_sup.name));
          continue;
        end if;
        if v_op = 'supplier_off' then
          if v_row.is_default then                                                               -- ⬜1: 기본을 끄면 기본 없음 — 올리지 않고 알린다
            v_warns := v_warns || jsonb_build_object('key', v_key || ':default_off:' || v_sup.name, 'sku', v_sku, 'code', 'default_off', 'message', format('%s is the default supplier of %s — after it is turned off the product has no default — pick another one', v_sup.name, v_sku));
          end if;
          if (select count(*) from public.product_supplier ps where ps.product_id = p.id and ps.is_active) = 1 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':supplier_missing', 'sku', v_sku, 'code', 'supplier_missing', 'message', format('SKU %s has no supplier — it will not appear as a purchase order candidate', v_sku));
          end if;
        end if;
      end if;

    -- ── surcharge-4a(판정 231 · 232 · 묶음 2): 상품의 관세 그룹 — {sku, group_id | null, old} · 그룹은 켜진 것만 · 세트는 막기(SO 줄은 낱개) · old 는 지금 그룹 id(없으면 빈 값) ──
    elsif v_op = 'surcharge_group_set' then
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:surcharge_group', 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s surcharge group: the old value the screen saw is missing — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|surcharge_group') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:surcharge_group', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s surcharge group is changed twice in this paste — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|surcharge_group');
      if p.surcharge_group_id::text is distinct from nullif(v_c->>'old', '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:surcharge_group', 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the surcharge group of %s (now %s) — check again — nothing was saved', v_sku, coalesce((select g.name from public.so_surcharge_group g where g.id = p.surcharge_group_id), '(none)')));
        continue;
      end if;
      if p.parent_product_id is not null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':surcharge_on_set', 'sku', v_sku, 'code', 'surcharge_on_set', 'message', format('Set %s cannot carry a surcharge group — sales order lines are singles, put the group on the single — nothing was saved', v_sku));
        continue;
      end if;
      if nullif(v_c->>'group_id', '') is not null then
        v_grp := null;
        if (v_c->>'group_id') ~ '^[0-9a-fA-F-]{36}$' then select * into v_grp from public.so_surcharge_group g where g.id = (v_c->>'group_id')::uuid; end if;
        if v_grp.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':surcharge_group_unknown', 'sku', v_sku, 'code', 'surcharge_group_unknown', 'message', format('SKU %s: that surcharge group does not exist — nothing was saved', v_sku));
          continue;
        end if;
        if not v_grp.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':surcharge_group_inactive', 'sku', v_sku, 'code', 'surcharge_group_inactive', 'message', format('SKU %s: surcharge group "%s" is off — turn it on first or pick another — nothing was saved', v_sku, v_grp.name));
          continue;
        end if;
      end if;

    -- ── img-1: 사진(판정 193 · 188 모양 — 끄기 · 파일은 지우지 않는다 · 경로는 <상품 id>/… · 저장소에 실재해야 등록) ──────────
    elsif v_op = 'image_add' then
      v_path := trim(coalesce(v_c->>'storage_path', ''));
      if v_path = '' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_path_missing', 'sku', v_sku, 'code', 'image_path_missing', 'message', format('SKU %s: the image has no storage path — nothing was saved', v_sku));
        continue;
      end if;
      if ('I|' || v_path) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_path, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Image %s appears twice in this paste — nothing was saved', v_path));
        continue;
      end if;
      v_seen := v_seen || ('I|' || v_path);
      if left(v_path, 37) <> p.id::text || '/' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_path_mismatch:' || v_path, 'sku', v_sku, 'code', 'image_path_mismatch', 'message', format('Image %s is not stored under the folder of %s (%s/…) — nothing was saved', v_path, v_sku, p.id));
      end if;
      if coalesce(v_c->>'content_type', '') not in ('image/jpeg', 'image/png', 'image/webp') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_type_invalid:' || v_path, 'sku', v_sku, 'code', 'image_type_invalid', 'message', format('Image %s: only JPEG, PNG and WebP are accepted (got %s) — nothing was saved', v_path, coalesce(v_c->>'content_type', 'nothing')));
      end if;
      if not exists (select 1 from storage.objects o where o.bucket_id = 'product-images' and o.name = v_path) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_object_missing:' || v_path, 'sku', v_sku, 'code', 'image_object_missing', 'message', format('Image %s is not in the product-images bucket — upload it first — nothing was saved', v_path));
      end if;
      select i.id, i.is_active, i.product_id into v_img from public.product_image i where i.storage_path = v_path;
      if v_img.id is not null and (v_img.is_active or v_img.product_id <> p.id) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_exists:' || v_path, 'sku', v_sku, 'code', 'image_exists', 'message', format('Image %s is already registered — nothing was saved', v_path));
      end if;
      if v_c ? 'byte_size' and v_c->>'byte_size' is not null and ((v_c->>'byte_size') !~ '^[0-9]+$' or (v_c->>'byte_size')::bigint <= 0) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_path, 'sku', v_sku, 'code', 'value_invalid', 'message', format('Image %s: byte_size must be a whole number above 0 — nothing was saved', v_path));
      end if;

    elsif v_op in ('image_off', 'image_primary') then
      select i.id, i.is_active, i.is_primary into v_img from public.product_image i where i.product_id = p.id and i.id = nullif(trim(coalesce(v_c->>'image_id', '')), '')::uuid;
      if v_img.id is null or not v_img.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_not_found:' || coalesce(v_c->>'image_id', '(none)'), 'sku', v_sku, 'code', 'image_not_found', 'message', format('SKU %s has no active image %s — nothing was saved', v_sku, coalesce(v_c->>'image_id', '(none)')));
        continue;
      end if;
      if (p.id::text || '|img|' || v_img.id::text) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_img.id::text, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Image %s of %s is changed twice in this paste — nothing was saved', v_img.id, v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|img|' || v_img.id::text);
      if v_op = 'image_off' and v_img.is_primary then                                          -- prod-4b primary_off 와 같은 태도 — 올리지 않고 알린다
        v_warns := v_warns || jsonb_build_object('key', v_key || ':image_primary_off:' || v_img.id::text, 'sku', v_sku, 'code', 'image_primary_off', 'message', format('Image %s is the primary image of %s — after it is turned off the product has no primary image — pick another one', v_img.id, v_sku));
      end if;

    elsif v_op = 'image_order' then
      select coalesce(array_agg(nullif(trim(x), '')::uuid order by o), '{}') into v_ids from jsonb_array_elements_text(coalesce(v_c->'image_ids', '[]'::jsonb)) with ordinality as t(x, o);
      if cardinality(v_ids) = 0 then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_not_found:(none)', 'sku', v_sku, 'code', 'image_not_found', 'message', format('SKU %s: image_order needs at least one image id — nothing was saved', v_sku));
        continue;
      end if;
      if (select count(distinct u) from unnest(v_ids) u) <> cardinality(v_ids) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:order', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s: image_order lists an image twice — nothing was saved', v_sku));
        continue;
      end if;
      if (select count(*) from public.product_image i where i.product_id = p.id and i.is_active and i.id = any(v_ids)) <> cardinality(v_ids) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_not_found:order', 'sku', v_sku, 'code', 'image_not_found', 'message', format('SKU %s: image_order names an image that is not an active image of this product — nothing was saved', v_sku));
      end if;
    end if;
  end loop;

  -- ③ 판정
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ④ 저장 — 줄 순서대로 · 한 트랜잭션 · unique 23505 는 문장으로
  begin
    v_i := 0;
    for v_c in select x from jsonb_array_elements(p_changes) as x loop
      v_i := v_i + 1;
      v_op := v_c->>'op'; v_field := v_c->>'field'; v_val := v_c->'value'; v_vtxt := nullif(trim(coalesce(v_c->>'value', '')), '');
      if v_op = 'family_head_set' then
        select * into v_fam from public.product_family f where f.id = (v_idmap->>('F' || trim(coalesce(v_c->>'family_sku', ''))))::uuid;
        case v_field
        when 'name' then update public.product_family set name = v_vtxt where id = v_fam.id;
        when 'brand_id' then
          update public.product x set brand_id = v_vtxt::uuid, brand_name = (select b.name from public.ref_brand b where b.id = v_vtxt::uuid) where x.family_id = v_fam.id and x.brand_id is not distinct from v_fam.brand_id;   -- 판정 191
          update public.product_family set brand_id = v_vtxt::uuid, brand_name = (select b.name from public.ref_brand b where b.id = v_vtxt::uuid) where id = v_fam.id;
        when 'category_id' then
          update public.product x set category_id = v_vtxt::uuid, category_name = (select c.name from public.ref_category c where c.id = v_vtxt::uuid) where x.family_id = v_fam.id and x.category_id is not distinct from v_fam.category_id;   -- 판정 191
          update public.product_family set category_id = v_vtxt::uuid, category_name = (select c.name from public.ref_category c where c.id = v_vtxt::uuid) where id = v_fam.id;
        when 'unit_id' then
          update public.product x set unit_id = v_vtxt::uuid, uom_name = (select u.name from public.ref_unit u where u.id = v_vtxt::uuid) where x.family_id = v_fam.id and x.unit_id is not distinct from v_fam.unit_id;   -- 판정 192
          update public.product_family set unit_id = v_vtxt::uuid, uom_name = (select u.name from public.ref_unit u where u.id = v_vtxt::uuid) where id = v_fam.id;
        when 'note' then update public.product_family set note = v_vtxt where id = v_fam.id;
        when 'is_active' then update public.product_family set is_active = (v_val)::boolean where id = v_fam.id;
        when 'option1_name' then update public.product_family set option1_name = v_vtxt where id = v_fam.id;
        when 'option2_name' then update public.product_family set option2_name = v_vtxt where id = v_fam.id;
        when 'option3_name' then update public.product_family set option3_name = v_vtxt where id = v_fam.id;
        end case;
      else
        select * into p from public.product x where x.id = (v_idmap->>('P' || trim(coalesce(v_c->>'sku', ''))))::uuid;   -- 옛 SKU → id(⬜2)
        if v_op = 'set' then
          case v_field
          when 'name' then update public.product set name = v_vtxt where id = p.id;
          when 'brand_id' then update public.product set brand_id = v_vtxt::uuid, brand_name = (select b.name from public.ref_brand b where b.id = v_vtxt::uuid) where id = p.id;
          when 'category_id' then update public.product set category_id = v_vtxt::uuid, category_name = (select c.name from public.ref_category c where c.id = v_vtxt::uuid) where id = p.id;
          when 'unit_id' then update public.product set unit_id = v_vtxt::uuid, uom_name = (select u.name from public.ref_unit u where u.id = v_vtxt::uuid) where id = p.id;
          when 'weight' then update public.product set weight = v_vtxt::numeric where id = p.id;
          when 'weight_unit' then update public.product set weight_unit = v_vtxt where id = p.id;
          when 'note' then update public.product set note = v_vtxt where id = p.id;
          when 'is_discontinued' then update public.product set is_discontinued = (v_val)::boolean where id = p.id;
          when 'set_discount_pct' then update public.product set set_discount_pct = v_vtxt::numeric where id = p.id;
          when 'is_active' then update public.product set is_active = (v_val)::boolean where id = p.id;
          when 'sellable' then update public.product set sellable = (v_val)::boolean, sellable_source = 'ims' where id = p.id;   -- dsc-1 판정 294: 창구가 바꾸면 ims
          when 'sku' then
            update public.product set sku = v_vtxt where id = p.id;                           -- 트리거 product_sku_lock 이 마지막 문(IM136)
            update public.product x set sku = v_vtxt || '-' || x.pack_factor::int::text where x.parent_product_id = p.id;   -- 판정 189 · 이름은 그대로
          when 'pack_factor' then
            select * into v_par from public.product x where x.id = p.parent_product_id;
            update public.product set pack_factor = v_vtxt::numeric, sku = v_par.sku || '-' || v_vtxt::numeric::int::text, uom_name = v_vtxt::numeric::int::text,
                   unit_id = (select u.id from public.ref_unit u where u.name = v_vtxt::numeric::int::text and u.is_active) where id = p.id;
          when 'parent_sku' then
            select * into v_par from public.product x where x.sku = v_vtxt;
            update public.product set parent_product_id = v_par.id, sku = v_par.sku || '-' || p.pack_factor::int::text where id = p.id;
          end case;
        elsif v_op = 'family_join' then
          select * into v_fam from public.product_family f where f.sku = trim(v_c->>'family_sku');
          select coalesce(array_agg(trim(t.x) order by t.o), '{}') into v_opts from jsonb_array_elements_text(coalesce(v_c->'options', '[]'::jsonb)) with ordinality as t(x, o);
          update public.product set family_id = v_fam.id, option1_value = v_opts[1], option2_value = v_opts[2], option3_value = v_opts[3] where id = p.id;
        elsif v_op = 'family_leave' then
          update public.product set family_id = null, option1_value = null, option2_value = null, option3_value = null where id = p.id;
        elsif v_op = 'family_option' then
          select coalesce(array_agg(trim(t.x) order by t.o), '{}') into v_opts from jsonb_array_elements_text(coalesce(v_c->'options', '[]'::jsonb)) with ordinality as t(x, o);
          update public.product set option1_value = v_opts[1], option2_value = v_opts[2], option3_value = v_opts[3] where id = p.id;
        elsif v_op = 'barcode_add' then                                                        -- prod-4b: 꺼진 같은 줄이 있으면 켠다(행 수 그대로 · 판정 188) · 켜진 바코드가 없으면 대표
          v_bc := trim(v_c->>'barcode');
          if exists (select 1 from public.product_barcode pb where pb.product_id = p.id and pb.barcode = v_bc) then
            update public.product_barcode set is_active = true, source = 'manual', is_primary = (is_primary or not exists (select 1 from public.product_barcode q where q.product_id = p.id and q.is_active)) where product_id = p.id and barcode = v_bc;
          else
            insert into public.product_barcode (product_id, barcode, is_primary, source) values (p.id, v_bc, not exists (select 1 from public.product_barcode q where q.product_id = p.id and q.is_active), 'manual');
          end if;
        elsif v_op = 'barcode_off' then
          update public.product_barcode set is_active = false, is_primary = false, source = 'manual' where product_id = p.id and barcode = trim(v_c->>'barcode');
        elsif v_op = 'barcode_primary' then
          update public.product_barcode set is_primary = (barcode = trim(v_c->>'barcode')) where product_id = p.id and (is_primary or barcode = trim(v_c->>'barcode'));
        elsif v_op = 'tag_add' then                                                            -- dsc-4b 판정 336: 태그는 행 하나 · 떼기는 삭제(관계 표 규약)
          insert into public.product_tag (product_id, tag, source, updated_by) values (p.id, btrim(v_c->>'tag'), 'manual', v_staff);
        elsif v_op = 'tag_off' then
          delete from public.product_tag where product_id = p.id and tag = btrim(v_c->>'tag');
        elsif v_op = 'price_set' then
          v_src := coalesce(v_fver->(v_i::text)->>'source', 'manual');                                                                   -- price-1: 검사가 정한 출처(formula 는 다시 계산해 같았을 때만 · 아니면 지금처럼 manual)
          if exists (select 1 from public.product_price pp where pp.product_id = p.id and pp.tier_id = (v_c->>'tier_id')::uuid) then
            update public.product_price set price = (v_c->>'price')::numeric, is_active = true, source = v_src, price_set_at = now(), price_set_by = v_staff, updated_by = v_staff where product_id = p.id and tier_id = (v_c->>'tier_id')::uuid;
          else
            insert into public.product_price (product_id, tier_id, price, source, price_set_by, updated_by) values (p.id, (v_c->>'tier_id')::uuid, (v_c->>'price')::numeric, v_src, v_staff, v_staff);
          end if;
          if v_src = 'formula' and (v_fver->(v_i::text)->>'formula_id') is not null then                                                 -- price-1(판정 223): 상품의 공급처 줄이 어느 식인지 기억(통째 식은 id 가 없다)
            update public.product_supplier set price_formula_id = (v_fver->(v_i::text)->>'formula_id')::uuid where product_id = p.id and supplier_id = (v_fver->(v_i::text)->>'supplier_id')::uuid and is_active;
          end if;
        elsif v_op = 'price_off' then
          update public.product_price set is_active = false, source = 'manual', updated_by = v_staff where product_id = p.id and tier_id = (v_c->>'tier_id')::uuid;
        elsif v_op = 'supplier_set' then
          if exists (select 1 from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = (v_c->>'supplier_id')::uuid) then
            update public.product_supplier set is_active = true, source = 'manual',
                   supplier_sku = case when v_c ? 'supplier_sku' then nullif(trim(v_c->>'supplier_sku'), '') else supplier_sku end,
                   cost         = case when v_c ? 'cost' then (v_c->>'cost')::numeric else cost end,
                   fixed_cost   = case when v_c ? 'fixed_cost' then (v_c->>'fixed_cost')::numeric else fixed_cost end,
                   currency_id  = case when v_c ? 'currency_id' then (v_c->>'currency_id')::uuid else currency_id end,
                   is_default   = is_default or not exists (select 1 from public.product_supplier q where q.product_id = p.id and q.is_active)
             where product_id = p.id and supplier_id = (v_c->>'supplier_id')::uuid;
          else
            insert into public.product_supplier (product_id, supplier_id, supplier_sku, cost, fixed_cost, currency_id, is_default, source)
            values (p.id, (v_c->>'supplier_id')::uuid, nullif(trim(v_c->>'supplier_sku'), ''), (v_c->>'cost')::numeric, (v_c->>'fixed_cost')::numeric, (v_c->>'currency_id')::uuid,
                    not exists (select 1 from public.product_supplier q where q.product_id = p.id and q.is_active), 'manual');
          end if;
        elsif v_op = 'supplier_default' then
          update public.product_supplier set is_default = (supplier_id = (v_c->>'supplier_id')::uuid) where product_id = p.id and (is_default or supplier_id = (v_c->>'supplier_id')::uuid);
        elsif v_op = 'supplier_off' then
          update public.product_supplier set is_active = false, is_default = false, source = 'manual' where product_id = p.id and supplier_id = (v_c->>'supplier_id')::uuid;
        elsif v_op = 'surcharge_group_set' then                                                -- surcharge-4a(묶음 2): 그룹 달기 · 떼기(null) — 줄에는 손대지 않는다(묶음 5 · 새로 들어오는 줄부터)
          update public.product set surcharge_group_id = nullif(v_c->>'group_id', '')::uuid where id = p.id;
        elsif v_op = 'image_add' then                                                          -- img-1: 첫 켜진 사진이면 대표 · primary:true 면 대표(다른 대표는 내린다) · 꺼진 같은 경로는 켠다
          v_path := trim(v_c->>'storage_path');
          if coalesce((v_c->>'primary')::boolean, false) then
            update public.product_image set is_primary = false where product_id = p.id and is_primary;
          end if;
          if exists (select 1 from public.product_image i where i.storage_path = v_path) then
            update public.product_image set is_active = true, source = 'manual', content_type = v_c->>'content_type', byte_size = (v_c->>'byte_size')::bigint, width = (v_c->>'width')::int, height = (v_c->>'height')::int,
                   file_name = nullif(trim(v_c->>'file_name'), ''), updated_by = v_staff,
                   is_primary = coalesce((v_c->>'primary')::boolean, false) or not exists (select 1 from public.product_image q where q.product_id = p.id and q.is_active)
             where storage_path = v_path;
          else
            insert into public.product_image (product_id, storage_path, content_type, byte_size, width, height, file_name, source, updated_by, is_primary, sort_order)
            values (p.id, v_path, v_c->>'content_type', (v_c->>'byte_size')::bigint, (v_c->>'width')::int, (v_c->>'height')::int, nullif(trim(v_c->>'file_name'), ''), 'manual', v_staff,
                    coalesce((v_c->>'primary')::boolean, false) or not exists (select 1 from public.product_image q where q.product_id = p.id and q.is_active),
                    coalesce((select max(q.sort_order) + 1 from public.product_image q where q.product_id = p.id), 1));
          end if;
        elsif v_op = 'image_off' then
          update public.product_image set is_active = false, is_primary = false, updated_by = v_staff where product_id = p.id and id = (v_c->>'image_id')::uuid;
        elsif v_op = 'image_primary' then
          update public.product_image set is_primary = (id = (v_c->>'image_id')::uuid), updated_by = v_staff where product_id = p.id and (is_primary or id = (v_c->>'image_id')::uuid);
        elsif v_op = 'image_order' then
          select coalesce(array_agg(nullif(trim(x), '')::uuid order by o), '{}') into v_ids from jsonb_array_elements_text(coalesce(v_c->'image_ids', '[]'::jsonb)) with ordinality as t(x, o);
          update public.product_image i set sort_order = u.o, updated_by = v_staff from unnest(v_ids) with ordinality as u(id, o) where i.id = u.id and i.product_id = p.id;
        end if;
      end if;
      v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
    end loop;
  exception when unique_violation then
    raise exception 'Someone just created one of these SKUs (%) — check again — nothing was saved', coalesce(sqlerrm, '');
  end;

  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
comment on function public.product_update(jsonb, boolean, text[]) is
  '⭐ 상품 고치기 창구(판정 187 ~ 194 · 222 · 223 · 231 · 232 · 2026-10-01 prod-4a + 4b + img-1 + price-1 · 2026-10-02 surcharge-4a · 2026-10-06 dsc-1 판정 281-4 · 294 sellable · ⭐ 2026-10-06 dsc-4b 판정 336: 태그 op 둘) — security definer · 첫 줄 ims_require_write(master). p_changes = 바꿀 것 목록(최대 1,000 줄) · 줄 = {sku, op, …, old} · op 스물: set(칸 하나 — name · brand_id · category_id · unit_id · weight · weight_unit · note · is_discontinued · set_discount_pct · sku · is_active · pack_factor · parent_sku · sellable) · family_join {sku, family_sku, options[]} · family_leave {sku, old} · family_option {sku, options[], old[]} · family_head_set {family_sku, field, value, old} · barcode_add/barcode_off/barcode_primary {sku, barcode} · price_set {sku, tier_id, price, old?, formula?} · price_off {sku, tier_id, old} · supplier_set {sku, supplier_id, supplier_sku?, cost?, fixed_cost?, currency_id?, old{}?} · supplier_default/supplier_off {sku, supplier_id} · image_add {sku, storage_path, content_type, byte_size?, width?, height?, file_name?, primary?} · image_off/image_primary {sku, image_id} · image_order {sku, image_ids[]} · surcharge_group_set {sku, group_id | null, old} · ⭐ tag_add {sku, tag} · tag_off {sku, tag}(dsc-4b 판정 336 · 332 의 짝 — btrim 만 · 대소문자 바꾸지 않음 · 막기 tag_empty · tag_exists · tag_not_found · tag_case_conflict(제품 태그 전체 · 딜 대상 so_deal_target.tag · 같은 호출) · field_duplicate_in_call · 알리기 tag_off_used_by_deal{deals}(ack — 이 태그의 마지막 제품에서 떼는데 켜진 딜의 켜진 줄이 그 태그로 건다) · 떼기는 행 삭제(관계 표 규약) · 붙인 행은 source manual). old = 화면이 본 옛 값 — 다르면 changed_elsewhere. 검사만(p_commit false) → 저장(p_commit true + p_ack) · 저장 직전 재검사(판정 176) · 막기 하나면 아무것도 안 바뀐다. 바코드 · 판매가 · 공급처 · 사진 빼기는 끄기(판정 188) · IMS 가 손댄 줄은 source manual(판정 133). code 목록은 20261001143142 · 20261001145316 · 20261001152712 · 20261002012641 · 20261002155201 · 20261006183851 · 이 파일(dsc-4b)의 머리';

-- ═══ 2) so_deal_save 재발행 — rules_open_to_all(판정 343) · 마지막 정의 20261007001229:158~784 · 더한 줄 일곱(⑦ 알리기) ═══
create or replace function public.so_deal_save(p_deal jsonb, p_old jsonb default null, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_uuid    constant text   := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  c_num     constant text   := '^-?[0-9]+(\.[0-9]+)?$';
  c_int     constant text   := '^[0-9]+$';
  c_date    constant text   := '^[0-9]{4}-[0-9]{2}-[0-9]{2}$';
  c_head    constant text[] := array['id', 'name', 'is_active', 'date_from', 'date_to', 'is_order_level', 'kind', 'coupon_required', 'note', 'tiers', 'lines', 'rules'];
  c_skip    constant text[] := array['cin7_id', 'source', 'created_at', 'updated_at', 'updated_by', 'coupon_code', 'deal_id', 'line_id'];   -- 화면이 읽은 행을 그대로 돌려보내도 되게 — 읽기 전용 칸은 지나친다
  c_tier    constant text[] := array['id', 'tier_no', 'min_amount', 'pct', 'note'];
  c_line    constant text[] := array['id', 'line_no', 'pct', 'min_qty_mode', 'min_qty', 'note', 'is_active', 'targets'];
  c_target  constant text[] := array['id', 'kind', 'target', 'tag', 'brand_id', 'product_id', 'category_id', 'note'];
  c_rule    constant text[] := array['id', 'kind', 'target', 'customer_id', 'warehouse_id', 'tier_id', 'note'];
  v_staff   uuid;
  v_blocks  jsonb := '[]'::jsonb;
  v_warns   jsonb := '[]'::jsonb;
  v_changes jsonb := '[]'::jsonb;
  v_keys    text[] := '{}';
  v_unacked text[] := '{}';
  v_key     text;
  v_id      uuid;
  v_create  boolean;
  d         public.so_deal%rowtype;
  v_k       text;
  v_txt     text;
  v_e       jsonb;
  v_t       jsonb;
  v_i       int;
  v_j       int;
  v_name    text;  v_active boolean;  v_from date;  v_to date;  v_order boolean;  v_kind text;  v_coupon boolean;  v_note text;
  v_bool    boolean;
  v_head_changed  boolean := false;
  v_child_changed boolean := false;
  v_tiers_given boolean := false;  v_lines_given boolean := false;  v_rules_given boolean := false;
  v_tiers   jsonb := '[]'::jsonb;
  v_lines   jsonb := '[]'::jsonb;
  v_rules   jsonb := '[]'::jsonb;
  v_targets jsonb;
  v_tags    text[] := '{}';
  v_seen    text[] := '{}';
  v_seen_l  text[] := '{}';
  v_amts    numeric[] := '{}';
  v_line_ids uuid[] := '{}';
  v_line_nos int[] := '{}';
  v_nk      text;
  v_val     text;
  v_r       record;
  v_cnt     bigint;
  v_cur_lines int := 0;
  v_cur_tiers int := 0;
  v_off_so  bigint := 0;
  v_off_n   int := 0;
  v_unused  text[] := '{}';
  v_coupons bigint := 0;
  v_f0      bigint;  v_f1 bigint;  v_flagged int := 0;
  v_rolled  boolean := false;
  v_idmap   jsonb := '{}'::jsonb;
  v_lid     uuid;
  v_new_updated timestamptz;
  v_tn int;  v_amt numeric;  v_pct numeric;  v_ln int;  v_mode text;  v_mq numeric;
  v_act     text;
  v_oldv    jsonb;
begin
  perform public.ims_require_write('master', 'saved');                                                              -- ⭐ 유일한 문 — 첫 줄(판정 140 · 285)
  v_staff := public.so_current_staff();

  -- ① 모양 · 머리 잠금 · 판 대조(판정 331)
  if p_deal is null or jsonb_typeof(p_deal) <> 'object' then
    raise exception 'p_deal must be a JSON object — nothing was saved';
  end if;
  v_txt := nullif(trim(coalesce(p_deal->>'id', '')), '');
  v_create := v_txt is null;
  v_key := 'deal:' || coalesce(v_txt, 'new');
  if not v_create then
    if v_txt !~ c_uuid then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':deal_unknown', 'code', 'deal_unknown', 'message', format('Deal id "%s" is not a valid id — nothing was saved', v_txt));
    else
      v_id := v_txt::uuid;
      select * into d from public.so_deal where id = v_id for update;
      if not found then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':deal_unknown', 'code', 'deal_unknown', 'message', format('Deal %s does not exist — nothing was saved', v_id));
      end if;
    end if;
    if jsonb_array_length(v_blocks) > 0 then
      return jsonb_build_object('committed', false, 'deal_id', null, 'updated_at', null, 'changes', '[]'::jsonb, 'blocks', v_blocks, 'warnings', '[]'::jsonb, 'unacked', '[]'::jsonb, 'open_orders_to_flag', 0);
    end if;
    v_txt := case when jsonb_typeof(p_old) = 'string' then p_old #>> '{}' when jsonb_typeof(p_old) = 'object' then p_old->>'updated_at' else null end;
    if nullif(trim(coalesce(v_txt, '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('Deal %s: the version the screen saw (updated_at) is missing — reload and try again — nothing was saved', d.name));
    else
      begin
        if v_txt::timestamptz <> d.updated_at then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Someone just changed deal %s (now %s) — check again — nothing was saved', d.name, to_json(d.updated_at)::text), 'updated_at', to_jsonb(d.updated_at));
        end if;
      exception when others then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('Deal %s: the version the screen saw ("%s") is not a timestamp — reload and try again — nothing was saved', d.name, v_txt));
      end;
    end if;
  end if;
  for v_k in select jsonb_object_keys(p_deal) loop
    if not (v_k = any(c_head)) and not (v_k = any(c_skip)) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || v_k, 'code', 'field_unknown', 'message', format('Unknown field "%s" on the deal — nothing was saved', v_k));
    end if;
  end loop;

  -- ② 머리 칸 — 있는 열쇠만 바뀐다(없는 열쇠 = 그대로 · 만들기면 기본값)
  v_name := case when p_deal ? 'name' then nullif(btrim(coalesce(p_deal->>'name', '')), '') else d.name end;
  if v_name is null then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'code', 'name_missing', 'message', 'A deal needs a name — nothing was saved');
  end if;
  foreach v_k in array array['is_active', 'is_order_level', 'coupon_required'] loop
    if p_deal ? v_k then
      v_txt := lower(trim(coalesce(p_deal->>v_k, '')));
      if v_txt not in ('true', 'false') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_k, 'code', 'value_invalid', 'message', format('%s must be true or false (got "%s") — nothing was saved', v_k, coalesce(p_deal->>v_k, '')));
        v_bool := null;
      else
        v_bool := v_txt = 'true';
      end if;
    else
      v_bool := null;
    end if;
    case v_k
      when 'is_active'       then v_active := coalesce(v_bool, d.is_active, true);
      when 'is_order_level'  then v_order  := coalesce(v_bool, d.is_order_level, false);
      when 'coupon_required' then v_coupon := coalesce(v_bool, d.coupon_required, false);
    end case;
  end loop;
  v_kind := case when p_deal ? 'kind' then nullif(trim(coalesce(p_deal->>'kind', '')), '') else coalesce(d.kind, 'pct') end;
  if v_kind is distinct from 'pct' then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':kind_invalid', 'code', 'kind_invalid', 'message', format('Deal kind must be pct (got "%s") — nothing was saved', coalesce(v_kind, '')));
  end if;
  v_note := case when p_deal ? 'note' then nullif(trim(coalesce(p_deal->>'note', '')), '') else d.note end;
  v_from := d.date_from;  v_to := d.date_to;
  foreach v_k in array array['date_from', 'date_to'] loop
    if p_deal ? v_k then
      v_txt := nullif(trim(coalesce(p_deal->>v_k, '')), '');
      if v_txt is not null and v_txt !~ c_date then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':dates_invalid:' || v_k, 'code', 'dates_invalid', 'message', format('%s must be a date YYYY-MM-DD (got "%s") — nothing was saved', v_k, v_txt));
      else
        begin
          if v_k = 'date_from' then v_from := v_txt::date; else v_to := v_txt::date; end if;
        exception when others then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':dates_invalid:' || v_k, 'code', 'dates_invalid', 'message', format('%s is not a real date (got "%s") — nothing was saved', v_k, v_txt));
        end;
      end if;
    end if;
  end loop;
  if v_from is not null and v_to is not null and v_from > v_to then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':dates_invalid', 'code', 'dates_invalid', 'message', format('date_from %s is after date_to %s — nothing was saved', v_from, v_to));
  end if;
  if v_create then
    v_changes := v_changes || jsonb_build_object('part', 'head', 'action', 'added', 'name', v_name, 'is_active', v_active, 'is_order_level', v_order, 'coupon_required', v_coupon, 'date_from', v_from, 'date_to', v_to);
    v_head_changed := true;
  else
    for v_r in
      select * from (values ('name', to_jsonb(d.name), to_jsonb(v_name)), ('is_active', to_jsonb(d.is_active), to_jsonb(v_active)), ('date_from', to_jsonb(d.date_from), to_jsonb(v_from)), ('date_to', to_jsonb(d.date_to), to_jsonb(v_to)),
                           ('is_order_level', to_jsonb(d.is_order_level), to_jsonb(v_order)), ('kind', to_jsonb(d.kind), to_jsonb(v_kind)), ('coupon_required', to_jsonb(d.coupon_required), to_jsonb(v_coupon)), ('note', to_jsonb(d.note), to_jsonb(v_note))) as f(field, oldv, newv)
    loop
      if v_r.oldv is distinct from v_r.newv then
        v_changes := v_changes || jsonb_build_object('part', 'head', 'action', 'changed', 'field', v_r.field, 'old', v_r.oldv, 'new', v_r.newv);
        v_head_changed := true;
      end if;
    end loop;
    if not v_head_changed then v_changes := v_changes || jsonb_build_object('part', 'head', 'action', 'unchanged'); end if;
    select count(*) into v_cur_lines from public.so_deal_line l where l.deal_id = v_id and l.is_active;
    select count(*) into v_cur_tiers from public.so_deal_tier t where t.deal_id = v_id;
  end if;

  -- ③ 단계(짝 = tier_no · 판정 340)
  if p_deal ? 'tiers' then
    if jsonb_typeof(p_deal->'tiers') <> 'array' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tiers_invalid', 'code', 'tiers_invalid', 'message', 'tiers must be a list of {tier_no, min_amount, pct} — nothing was saved');
    else
      v_tiers_given := true;
      v_i := 0;
      for v_e in select x from jsonb_array_elements(p_deal->'tiers') x loop
        v_i := v_i + 1;
        if jsonb_typeof(v_e) <> 'object' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tiers_invalid:' || v_i, 'code', 'tiers_invalid', 'message', format('Tier %s is not {tier_no, min_amount, pct} — nothing was saved', v_i));
          continue;
        end if;
        for v_k in select jsonb_object_keys(v_e) loop
          if not (v_k = any(c_tier)) and not (v_k = any(c_skip)) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:tier.' || v_k, 'code', 'field_unknown', 'message', format('Unknown field "%s" on tier %s — nothing was saved', v_k, v_i));
          end if;
        end loop;
        v_txt := trim(coalesce(v_e->>'tier_no', ''));
        if v_txt !~ c_int or v_txt::int < 1 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_no_invalid:' || v_i, 'code', 'tier_no_invalid', 'message', format('Tier %s: tier_no must be a whole number from 1 (got "%s") — nothing was saved', v_i, v_txt));
          continue;
        end if;
        v_tn := v_txt::int;
        v_txt := coalesce(nullif(trim(coalesce(v_e->>'min_amount', '')), ''), '0');
        if v_txt !~ c_num or v_txt::numeric < 0 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':min_amount_invalid:' || v_tn, 'code', 'min_amount_invalid', 'message', format('Tier %s: min_amount must be 0 or more (got "%s") — nothing was saved', v_tn, v_txt));
          continue;
        end if;
        v_amt := v_txt::numeric;
        v_txt := trim(coalesce(v_e->>'pct', ''));
        if v_txt !~ c_num or not (v_txt::numeric > 0 and v_txt::numeric < 100) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':pct_invalid:tier.' || v_tn, 'code', 'pct_invalid', 'message', format('Tier %s: pct must be above 0 and below 100 (got "%s") — nothing was saved', v_tn, v_txt));
          continue;
        end if;
        v_pct := v_txt::numeric;
        if ('T|' || v_tn) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_no_duplicate:' || v_tn, 'code', 'tier_no_duplicate', 'message', format('Tier number %s appears twice — nothing was saved', v_tn));
          continue;
        end if;
        if v_amt = any(v_amts) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_amount_duplicate:' || v_tn, 'code', 'tier_amount_duplicate', 'message', format('Two tiers start at the same amount %s — nothing was saved', v_amt));
          continue;
        end if;
        v_seen := v_seen || ('T|' || v_tn);  v_amts := v_amts || v_amt;
        v_tiers := v_tiers || jsonb_build_object('tier_no', v_tn, 'min_amount', v_amt, 'pct', v_pct, 'note', nullif(trim(coalesce(v_e->>'note', '')), ''));
      end loop;
    end if;
  end if;

  -- ④ 줄(짝 = id · 판정 340 · 없는 id = 새 줄 · is_active false 로 보낸 줄은 덩이에 없는 것과 같다) + 대상(짝 = 내용 전체)
  if p_deal ? 'lines' then
    if jsonb_typeof(p_deal->'lines') <> 'array' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_invalid', 'code', 'lines_invalid', 'message', 'lines must be a list of {id, line_no, pct, min_qty_mode, min_qty, targets[]} — nothing was saved');
    else
      v_lines_given := true;
      v_i := 0;
      for v_e in select x from jsonb_array_elements(p_deal->'lines') x loop
        v_i := v_i + 1;
        if jsonb_typeof(v_e) <> 'object' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_invalid:' || v_i, 'code', 'lines_invalid', 'message', format('Line %s is not {line_no, pct, …} — nothing was saved', v_i));
          continue;
        end if;
        if lower(trim(coalesce(v_e->>'is_active', 'true'))) = 'false' then continue; end if;                            -- 꺼진 채 돌아온 줄 = 덩이에 없는 줄(그대로 꺼져 있거나 꺼진다)
        for v_k in select jsonb_object_keys(v_e) loop
          if not (v_k = any(c_line)) and not (v_k = any(c_skip)) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:line.' || v_k, 'code', 'field_unknown', 'message', format('Unknown field "%s" on line %s — nothing was saved', v_k, v_i));
          end if;
        end loop;
        v_lid := null;
        v_txt := nullif(trim(coalesce(v_e->>'id', '')), '');
        if v_txt is not null then
          if v_txt !~ c_uuid or v_create or not exists (select 1 from public.so_deal_line l where l.id = v_txt::uuid and l.deal_id = v_id) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_unknown:' || v_i, 'code', 'line_unknown', 'message', format('Line %s: id "%s" is not a line of this deal — nothing was saved', v_i, v_txt));
            continue;
          end if;
          v_lid := v_txt::uuid;
          if v_lid = any(v_line_ids) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_duplicate_in_call:' || v_i, 'code', 'line_duplicate_in_call', 'message', format('Line id %s appears twice — nothing was saved', v_lid));
            continue;
          end if;
        end if;
        v_txt := trim(coalesce(v_e->>'line_no', ''));
        if v_txt !~ c_int or v_txt::int < 1 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_no_invalid:' || v_i, 'code', 'line_no_invalid', 'message', format('Line %s: line_no must be a whole number from 1 (got "%s") — nothing was saved', v_i, v_txt));
          continue;
        end if;
        v_ln := v_txt::int;
        v_txt := trim(coalesce(v_e->>'pct', ''));
        if v_txt !~ c_num or not (v_txt::numeric > 0 and v_txt::numeric < 100) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':pct_invalid:line.' || v_ln, 'code', 'pct_invalid', 'message', format('Line %s: pct must be above 0 and below 100 (got "%s") — nothing was saved', v_ln, v_txt));
          continue;
        end if;
        v_pct := v_txt::numeric;
        v_mode := coalesce(nullif(trim(coalesce(v_e->>'min_qty_mode', '')), ''), 'none');
        if v_mode not in ('none', 'qty', 'case') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':min_qty_mode_invalid:' || v_ln, 'code', 'min_qty_mode_invalid', 'message', format('Line %s: min_qty_mode must be none, qty or case (got "%s") — nothing was saved', v_ln, v_mode));
          continue;
        end if;
        v_txt := nullif(trim(coalesce(v_e->>'min_qty', '')), '');
        if v_mode = 'qty' then
          if v_txt is null or v_txt !~ c_num or v_txt::numeric <= 0 then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':min_qty_invalid:' || v_ln, 'code', 'min_qty_invalid', 'message', format('Line %s: min_qty must be above 0 when min_qty_mode is qty (got "%s") — nothing was saved', v_ln, coalesce(v_txt, '')));
            continue;
          end if;
          v_mq := v_txt::numeric;
        else
          if v_txt is not null then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':min_qty_invalid:' || v_ln, 'code', 'min_qty_invalid', 'message', format('Line %s: min_qty must be empty when min_qty_mode is %s — nothing was saved', v_ln, v_mode));
            continue;
          end if;
          v_mq := null;
        end if;
        if v_ln = any(v_line_nos) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_no_duplicate:' || v_ln, 'code', 'line_no_duplicate', 'message', format('Line number %s appears twice — nothing was saved', v_ln));
          continue;
        end if;
        v_line_nos := v_line_nos || v_ln;
        if v_lid is not null then v_line_ids := v_line_ids || v_lid; end if;
        -- 대상 — targets 열쇠가 없으면(기존 줄) 그대로 · 있으면 내용 전체가 최종 모양 · 새 줄은 빈 목록
        v_targets := null;
        if v_e ? 'targets' then
          if jsonb_typeof(v_e->'targets') <> 'array' then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':targets_invalid:' || v_ln, 'code', 'targets_invalid', 'message', format('Line %s: targets must be a list — nothing was saved', v_ln));
            continue;
          end if;
          v_targets := '[]'::jsonb;  v_seen_l := '{}';  v_j := 0;
          for v_t in select x from jsonb_array_elements(v_e->'targets') x loop
            v_j := v_j + 1;
            if jsonb_typeof(v_t) <> 'object' then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':target_value_invalid:' || v_ln || '.' || v_j, 'code', 'target_value_invalid', 'message', format('Line %s target %s is not {kind, target, value} — nothing was saved', v_ln, v_j));
              continue;
            end if;
            for v_k in select jsonb_object_keys(v_t) loop
              if not (v_k = any(c_target)) and not (v_k = any(c_skip)) then
                v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:target.' || v_k, 'code', 'field_unknown', 'message', format('Unknown field "%s" on line %s target %s — nothing was saved', v_k, v_ln, v_j));
              end if;
            end loop;
            v_val := null;
            if coalesce(v_t->>'kind', '') not in ('include', 'exclude') or coalesce(v_t->>'target', '') not in ('tag', 'brand', 'product', 'category') then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':target_value_invalid:' || v_ln || '.' || v_j, 'code', 'target_value_invalid', 'message', format('Line %s target %s: kind must be include|exclude and target tag|brand|product|category (got "%s" · "%s") — nothing was saved', v_ln, v_j, coalesce(v_t->>'kind', ''), coalesce(v_t->>'target', '')));
              continue;
            end if;
            -- 값 칸은 target 에 맞는 하나만(나머지는 비어 있어야) — so_deal_target_value_ck 를 어휘로
            if (nullif(trim(coalesce(v_t->>'tag', '')), '') is not null)::int + (nullif(trim(coalesce(v_t->>'brand_id', '')), '') is not null)::int + (nullif(trim(coalesce(v_t->>'product_id', '')), '') is not null)::int + (nullif(trim(coalesce(v_t->>'category_id', '')), '') is not null)::int <> 1
               or nullif(trim(coalesce(v_t->>(case v_t->>'target' when 'tag' then 'tag' else (v_t->>'target') || '_id' end), '')), '') is null then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':target_value_invalid:' || v_ln || '.' || v_j, 'code', 'target_value_invalid', 'message', format('Line %s target %s: a %s target needs exactly its %s value — nothing was saved', v_ln, v_j, v_t->>'target', case v_t->>'target' when 'tag' then 'tag' else (v_t->>'target') || '_id' end));
              continue;
            end if;
            if v_t->>'target' = 'tag' then
              v_val := btrim(v_t->>'tag');
              if exists (select 1 from public.product_tag pt where lower(pt.tag) = lower(v_val) and pt.tag <> v_val) then
                v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_case_conflict:' || v_ln || '.' || v_j, 'code', 'tag_case_conflict', 'message', format('Line %s: tag "%s" differs only by case from a product tag "%s" — use the existing spelling — nothing was saved', v_ln, v_val, (select min(pt.tag) from public.product_tag pt where lower(pt.tag) = lower(v_val) and pt.tag <> v_val)));
                continue;
              end if;
              if exists (select 1 from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id where l.deal_id is distinct from v_id and lower(x.tag) = lower(v_val) and x.tag <> v_val) then
                v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_case_conflict:' || v_ln || '.' || v_j, 'code', 'tag_case_conflict', 'message', format('Line %s: tag "%s" differs only by case from a tag another deal uses ("%s") — use the same spelling — nothing was saved', v_ln, v_val, (select min(x.tag) from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id where l.deal_id is distinct from v_id and lower(x.tag) = lower(v_val) and x.tag <> v_val)));
                continue;
              end if;
              if exists (select 1 from unnest(v_tags) g where lower(g) = lower(v_val) and g <> v_val) then
                v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_case_conflict:' || v_ln || '.' || v_j, 'code', 'tag_case_conflict', 'message', format('Line %s: tag "%s" differs only by case from another tag in this deal — use one spelling — nothing was saved', v_ln, v_val));
                continue;
              end if;
              v_tags := v_tags || v_val;
              if not exists (select 1 from public.product_tag pt where pt.tag = v_val) and not (v_val = any(v_unused)) then v_unused := v_unused || v_val; end if;
            else
              v_val := trim(v_t->>((v_t->>'target') || '_id'));
              if v_val !~ c_uuid
                 or (v_t->>'target' = 'brand'    and not exists (select 1 from public.ref_brand b    where b.id = v_val::uuid))
                 or (v_t->>'target' = 'product'  and not exists (select 1 from public.product p     where p.id = v_val::uuid))
                 or (v_t->>'target' = 'category' and not exists (select 1 from public.ref_category c where c.id = v_val::uuid)) then
                v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || (v_t->>'target') || '_unknown:' || v_ln || '.' || v_j, 'code', (v_t->>'target') || '_unknown', 'message', format('Line %s target %s: %s "%s" does not exist — nothing was saved', v_ln, v_j, v_t->>'target', v_val));
                continue;
              end if;
            end if;
            v_nk := (v_t->>'kind') || '|' || (v_t->>'target') || '|' || v_val;
            if v_nk = any(v_seen_l) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':target_duplicate_in_call:' || v_ln || '.' || v_j, 'code', 'target_duplicate_in_call', 'message', format('Line %s: target %s %s "%s" appears twice — nothing was saved', v_ln, v_t->>'kind', v_t->>'target', v_val));
              continue;
            end if;
            v_seen_l := v_seen_l || v_nk;
            v_targets := v_targets || jsonb_build_object('kind', v_t->>'kind', 'target', v_t->>'target', 'value', v_val, 'nk', v_nk, 'note', nullif(trim(coalesce(v_t->>'note', '')), ''));
          end loop;
        elsif v_lid is null then
          v_targets := '[]'::jsonb;
        end if;
        v_lines := v_lines || jsonb_build_object('idx', v_i, 'id', v_lid, 'line_no', v_ln, 'pct', v_pct, 'min_qty_mode', v_mode, 'min_qty', v_mq, 'note', nullif(trim(coalesce(v_e->>'note', '')), ''), 'targets', v_targets);
      end loop;
    end if;
  end if;

  -- ⑤ 손님 조건(짝 = 내용 전체 · 판정 340)
  if p_deal ? 'rules' then
    if jsonb_typeof(p_deal->'rules') <> 'array' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':rules_invalid', 'code', 'rules_invalid', 'message', 'rules must be a list of {kind, target, value} — nothing was saved');
    else
      v_rules_given := true;  v_seen_l := '{}';  v_i := 0;
      for v_t in select x from jsonb_array_elements(p_deal->'rules') x loop
        v_i := v_i + 1;
        if jsonb_typeof(v_t) <> 'object' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':rule_value_invalid:' || v_i, 'code', 'rule_value_invalid', 'message', format('Customer rule %s is not {kind, target, value} — nothing was saved', v_i));
          continue;
        end if;
        for v_k in select jsonb_object_keys(v_t) loop
          if not (v_k = any(c_rule)) and not (v_k = any(c_skip)) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:rule.' || v_k, 'code', 'field_unknown', 'message', format('Unknown field "%s" on customer rule %s — nothing was saved', v_k, v_i));
          end if;
        end loop;
        if coalesce(v_t->>'kind', '') not in ('include', 'exclude') or coalesce(v_t->>'target', '') not in ('customer', 'branch', 'tier') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':rule_value_invalid:' || v_i, 'code', 'rule_value_invalid', 'message', format('Customer rule %s: kind must be include|exclude and target customer|branch|tier (got "%s" · "%s") — nothing was saved', v_i, coalesce(v_t->>'kind', ''), coalesce(v_t->>'target', '')));
          continue;
        end if;
        v_k := case v_t->>'target' when 'customer' then 'customer_id' when 'branch' then 'warehouse_id' else 'tier_id' end;
        if (nullif(trim(coalesce(v_t->>'customer_id', '')), '') is not null)::int + (nullif(trim(coalesce(v_t->>'warehouse_id', '')), '') is not null)::int + (nullif(trim(coalesce(v_t->>'tier_id', '')), '') is not null)::int <> 1
           or nullif(trim(coalesce(v_t->>v_k, '')), '') is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':rule_value_invalid:' || v_i, 'code', 'rule_value_invalid', 'message', format('Customer rule %s: a %s rule needs exactly its %s value — nothing was saved', v_i, v_t->>'target', v_k));
          continue;
        end if;
        v_val := trim(v_t->>v_k);
        if v_val !~ c_uuid
           or (v_k = 'customer_id'  and not exists (select 1 from public.customer c       where c.id = v_val::uuid))
           or (v_k = 'warehouse_id' and not exists (select 1 from public.ref_warehouse w  where w.id = v_val::uuid))
           or (v_k = 'tier_id'      and not exists (select 1 from public.ref_price_tier t where t.id = v_val::uuid)) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || replace(v_k, '_id', '') || '_unknown:' || v_i, 'code', replace(v_k, '_id', '') || '_unknown', 'message', format('Customer rule %s: %s "%s" does not exist — nothing was saved', v_i, replace(v_k, '_id', ''), v_val));
          continue;
        end if;
        v_nk := (v_t->>'kind') || '|' || (v_t->>'target') || '|' || v_val;
        if v_nk = any(v_seen_l) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':rule_duplicate_in_call:' || v_i, 'code', 'rule_duplicate_in_call', 'message', format('Customer rule %s %s "%s" appears twice — nothing was saved', v_t->>'kind', v_t->>'target', v_val));
          continue;
        end if;
        v_seen_l := v_seen_l || v_nk;
        v_rules := v_rules || jsonb_build_object('kind', v_t->>'kind', 'target', v_t->>'target', 'value', v_val, 'nk', v_nk, 'note', nullif(trim(coalesce(v_t->>'note', '')), ''));
      end loop;
    end if;
  end if;

  -- ⑥ 최종 모양의 문지기(트리거 셋을 어휘로 · 판정 309 · 330)
  if v_order then
    if v_lines_given and jsonb_array_length(v_lines) > 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_on_order_deal', 'code', 'line_on_order_deal', 'message', 'An order-level deal has no lines (its amount tiers are the discount) — remove the lines or turn off order-level — nothing was saved');
    elsif not v_lines_given and v_cur_lines > 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_block_order_level_on', 'code', 'lines_block_order_level_on', 'message', format('Deal %s has %s active line(s) — turn them off before making it an order-level deal — nothing was saved', v_name, v_cur_lines));
    end if;
  else
    if v_tiers_given and jsonb_array_length(v_tiers) > 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_on_line_deal', 'code', 'tier_on_line_deal', 'message', 'Amount tiers belong to an order-level deal — remove the tiers or turn on order-level — nothing was saved');
    elsif not v_tiers_given and v_cur_tiers > 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tiers_block_order_level_off', 'code', 'tiers_block_order_level_off', 'message', format('Deal %s has %s amount tier(s) — remove them before turning off order-level — nothing was saved', v_name, v_cur_tiers));
    end if;
  end if;
  if v_lines_given and not v_create then                                                                             -- 꺼진 줄(이 저장이 끄는 줄 포함)도 번호를 쥔다 — 최종 모양에서 겹치면 막는다
    for v_r in select l.line_no from public.so_deal_line l where l.deal_id = v_id and not (l.id = any(v_line_ids)) and l.line_no = any(v_line_nos) loop
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_no_duplicate:' || v_r.line_no, 'code', 'line_no_duplicate', 'message', format('Line number %s is held by a turned-off line — give the new line another number — nothing was saved', v_r.line_no));
    end loop;
  end if;

  -- ⑦ 변경 목록(미리 보기 · 쓰기 같다) · 알리기
  if v_tiers_given then
    for v_r in
      select coalesce(n.tier_no, c.tier_no) as tier_no, n.min_amount as new_amt, n.pct as new_pct, n.note as new_note, c.min_amount as old_amt, c.pct as old_pct, c.note as old_note, n.tier_no is not null as in_new, c.id is not null as in_cur
        from (select (x->>'tier_no')::int as tier_no, (x->>'min_amount')::numeric as min_amount, (x->>'pct')::numeric as pct, x->>'note' as note from jsonb_array_elements(v_tiers) x) n
        full join (select t.* from public.so_deal_tier t where t.deal_id = v_id) c on c.tier_no = n.tier_no
       order by 1
    loop
      v_act := case when not v_r.in_cur then 'added' when not v_r.in_new then 'removed' when v_r.new_amt <> v_r.old_amt or v_r.new_pct <> v_r.old_pct or v_r.new_note is distinct from v_r.old_note then 'changed' else 'unchanged' end;
      v_changes := v_changes || jsonb_build_object('part', 'tier', 'action', v_act, 'tier_no', v_r.tier_no, 'old', case when v_r.in_cur then jsonb_build_object('min_amount', v_r.old_amt, 'pct', v_r.old_pct) end, 'new', case when v_r.in_new then jsonb_build_object('min_amount', v_r.new_amt, 'pct', v_r.new_pct) end);
      if v_act <> 'unchanged' then v_child_changed := true; end if;
    end loop;
  end if;
  if v_lines_given then
    for v_e in select x from jsonb_array_elements(v_lines) x order by (x->>'line_no')::int loop
      v_lid := (v_e->>'id')::uuid;
      if v_lid is null then
        v_changes := v_changes || jsonb_build_object('part', 'line', 'action', 'added', 'line_id', null, 'line_no', (v_e->>'line_no')::int, 'new', v_e - 'targets' - 'idx');
        v_child_changed := true;
        for v_t in select x from jsonb_array_elements(v_e->'targets') x loop
          v_changes := v_changes || jsonb_build_object('part', 'target', 'action', 'added', 'line_id', null, 'line_no', (v_e->>'line_no')::int, 'kind', v_t->>'kind', 'target', v_t->>'target', 'value', v_t->>'value');
        end loop;
        if jsonb_array_length(v_e->'targets') = 0 then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':line_no_targets:' || (v_e->>'line_no'), 'code', 'line_no_targets', 'message', format('Line %s has no targets — it will match no product until a target is added', v_e->>'line_no'));
          v_keys := array_append(v_keys, v_key || ':line_no_targets:' || (v_e->>'line_no'));
        end if;
      else
        select * into v_r from public.so_deal_line l where l.id = v_lid;
        v_act := case when not v_r.is_active then 'turned_on'
                      when v_r.line_no <> (v_e->>'line_no')::int or v_r.pct <> (v_e->>'pct')::numeric or v_r.min_qty_mode <> (v_e->>'min_qty_mode') or v_r.min_qty is distinct from (v_e->>'min_qty')::numeric or v_r.note is distinct from (v_e->>'note') then 'changed'
                      else 'unchanged' end;
        v_changes := v_changes || jsonb_build_object('part', 'line', 'action', v_act, 'line_id', v_lid, 'line_no', (v_e->>'line_no')::int,
                                                     'old', jsonb_build_object('line_no', v_r.line_no, 'pct', v_r.pct, 'min_qty_mode', v_r.min_qty_mode, 'min_qty', v_r.min_qty, 'note', v_r.note, 'is_active', v_r.is_active), 'new', v_e - 'targets' - 'idx');
        if v_act <> 'unchanged' then v_child_changed := true; end if;
        if v_e ? 'targets' and jsonb_typeof(v_e->'targets') = 'array' then
          for v_r in
            select coalesce(n.nk, c.nk) as nk, coalesce(n.kind, c.kind) as kind, coalesce(n.target, c.target) as target, coalesce(n.value, c.value) as value, n.nk is not null as in_new, c.nk is not null as in_cur
              from (select x->>'nk' as nk, x->>'kind' as kind, x->>'target' as target, x->>'value' as value from jsonb_array_elements(v_e->'targets') x) n
              full join (select x.kind || '|' || x.target || '|' || coalesce(x.tag, x.brand_id::text, x.product_id::text, x.category_id::text) as nk, x.kind, x.target, coalesce(x.tag, x.brand_id::text, x.product_id::text, x.category_id::text) as value
                           from public.so_deal_target x where x.line_id = v_lid) c on c.nk = n.nk
             order by 1
          loop
            v_act := case when not v_r.in_cur then 'added' when not v_r.in_new then 'removed' else 'unchanged' end;
            v_changes := v_changes || jsonb_build_object('part', 'target', 'action', v_act, 'line_id', v_lid, 'line_no', (v_e->>'line_no')::int, 'kind', v_r.kind, 'target', v_r.target, 'value', v_r.value);
            if v_act <> 'unchanged' then v_child_changed := true; end if;
          end loop;
          if jsonb_array_length(v_e->'targets') = 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':line_no_targets:' || (v_e->>'line_no'), 'code', 'line_no_targets', 'message', format('Line %s has no targets — it will match no product until a target is added', v_e->>'line_no'));
            v_keys := array_append(v_keys, v_key || ':line_no_targets:' || (v_e->>'line_no'));
          end if;
        end if;
      end if;
    end loop;
    if not v_create then
      for v_r in select l.id, l.line_no, (select count(*) from public.so_line s where s.deal_line_id = l.id) as so_lines from public.so_deal_line l where l.deal_id = v_id and l.is_active and not (l.id = any(v_line_ids)) order by l.line_no loop
        v_changes := v_changes || jsonb_build_object('part', 'line', 'action', 'turned_off', 'line_id', v_r.id, 'line_no', v_r.line_no, 'so_lines', v_r.so_lines);
        v_child_changed := true;  v_off_n := v_off_n + 1;  v_off_so := v_off_so + v_r.so_lines;
      end loop;
      if v_off_so > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':line_off_with_order_lines', 'code', 'line_off_with_order_lines', 'n', v_off_so, 'message', format('%s order line(s) got their discount from the %s line(s) being turned off — they keep what they have; the lines stay on record', v_off_so, v_off_n));
        v_keys := array_append(v_keys, v_key || ':line_off_with_order_lines');
      end if;
    end if;
  end if;
  if v_rules_given then
    for v_r in
      select coalesce(n.nk, c.nk) as nk, coalesce(n.kind, c.kind) as kind, coalesce(n.target, c.target) as target, coalesce(n.value, c.value) as value, n.nk is not null as in_new, c.nk is not null as in_cur
        from (select x->>'nk' as nk, x->>'kind' as kind, x->>'target' as target, x->>'value' as value from jsonb_array_elements(v_rules) x) n
        full join (select x.kind || '|' || x.target || '|' || coalesce(x.customer_id::text, x.warehouse_id::text, x.tier_id::text) as nk, x.kind, x.target, coalesce(x.customer_id::text, x.warehouse_id::text, x.tier_id::text) as value
                     from public.so_deal_customer_rule x where x.deal_id = v_id) c on c.nk = n.nk
       order by 1
    loop
      v_act := case when not v_r.in_cur then 'added' when not v_r.in_new then 'removed' else 'unchanged' end;
      v_changes := v_changes || jsonb_build_object('part', 'rule', 'action', v_act, 'kind', v_r.kind, 'target', v_r.target, 'value', v_r.value);
      if v_act <> 'unchanged' then v_child_changed := true; end if;
    end loop;
  end if;
  if not v_create and v_rules_given then                                                                           -- dsc-4b 판정 343: 걸기 조건이 1 이상이다가 0 이 되면 「모든 손님」 — 묻는다(만들기는 해당 없음)
    select count(*) into v_cnt from public.so_deal_customer_rule x where x.deal_id = v_id and x.kind = 'include';
    if v_cnt > 0 and not exists (select 1 from jsonb_array_elements(v_rules) y where y->>'kind' = 'include') then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':rules_open_to_all', 'code', 'rules_open_to_all', 'n_before', v_cnt, 'message', format('This save removes all %s include rule(s) — deal %s will apply to every customer', v_cnt, v_name));
      v_keys := array_append(v_keys, v_key || ':rules_open_to_all');
    end if;
  end if;
  if cardinality(v_unused) > 0 then
    v_warns := v_warns || jsonb_build_object('key', v_key || ':tag_unused', 'code', 'tag_unused', 'tags', to_jsonb(v_unused), 'message', format('No product carries the tag(s) %s yet — the deal saves, but matches nothing on them until products get the tag', array_to_string(v_unused, ', ')));
    v_keys := array_append(v_keys, v_key || ':tag_unused');
  end if;
  if not v_create and ((d.is_active and not v_active) or (d.coupon_required and not v_coupon)) then                   -- 판정 334
    select count(*) into v_coupons from public.so_coupon c where c.deal_id = v_id and c.used_so_id is null and c.voided_at is null;
    if v_coupons > 0 then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':deal_off_with_coupons', 'code', 'deal_off_with_coupons', 'n', v_coupons, 'message', format('%s unused coupon(s) are issued on deal %s — they stop working while the deal is off or not a coupon deal; they are not voided', v_coupons, d.name));
      v_keys := array_append(v_keys, v_key || ':deal_off_with_coupons');
    end if;
  end if;
  if jsonb_array_length(v_blocks) = 0 and not v_head_changed and not v_child_changed then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':no_change', 'code', 'no_change', 'message', format('Deal %s already looks exactly like this — nothing to change — nothing was saved', v_name));
  end if;
  if jsonb_array_length(v_blocks) > 0 then
    return jsonb_build_object('committed', false, 'deal_id', v_id, 'updated_at', to_jsonb(d.updated_at), 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns, 'unacked', '[]'::jsonb, 'open_orders_to_flag', 0);
  end if;

  -- ⑧ 쓰기 — 서브트랜잭션: 미리 보기(p_commit false)와 ack 안 된 저장은 쓰고 센 뒤 되돌린다(⬜1 나 · 표시 수는 트리거가 실제로 센 값)
  --    순서(판정 340 · 문지기): 자식 지우기 · 줄 끄기 → 머리 → 단계 · 줄 고치기 · 넣기 → 대상 · 손님 조건 넣기 → 제약 즉시 검사 → (만들기) 켜기 → (자식만) 머리 판 올리기
  select count(*) into v_f0 from public.so s where s.reprice_suggested_at = now();
  begin
    set constraints public.so_deal_tier_amount_uq, public.so_deal_line_deal_line_no_key deferred;
    if v_create then
      insert into public.so_deal (name, is_active, source, note, updated_by, date_from, date_to, is_order_level, kind, coupon_required)
      values (v_name, false, 'manual', v_note, v_staff, v_from, v_to, v_order, v_kind, v_coupon) returning id into v_id;                 -- 꺼진 채 만들고 끝에 켠다(손님 조건이 들어간 뒤 표시 트리거가 돌게)
    else
      if v_rules_given then
        delete from public.so_deal_customer_rule x where x.deal_id = v_id
           and not ((x.kind || '|' || x.target || '|' || coalesce(x.customer_id::text, x.warehouse_id::text, x.tier_id::text)) = any(coalesce((select array_agg(y->>'nk') from jsonb_array_elements(v_rules) y), '{}'::text[])));
      end if;
      if v_lines_given then
        for v_e in select x from jsonb_array_elements(v_lines) x where (x->>'id') is not null and jsonb_typeof(x->'targets') = 'array' loop
          delete from public.so_deal_target x where x.line_id = (v_e->>'id')::uuid
             and not ((x.kind || '|' || x.target || '|' || coalesce(x.tag, x.brand_id::text, x.product_id::text, x.category_id::text)) = any(coalesce((select array_agg(y->>'nk') from jsonb_array_elements(v_e->'targets') y), '{}'::text[])));
        end loop;
        update public.so_deal_line l set is_active = false, updated_by = v_staff where l.deal_id = v_id and l.is_active and not (l.id = any(v_line_ids));
      end if;
      if v_tiers_given then
        delete from public.so_deal_tier t where t.deal_id = v_id and not (t.tier_no = any(coalesce((select array_agg((y->>'tier_no')::int) from jsonb_array_elements(v_tiers) y), '{}'::int[])));
      end if;
      if v_head_changed then
        update public.so_deal set name = v_name, is_active = v_active, date_from = v_from, date_to = v_to, is_order_level = v_order, kind = v_kind, coupon_required = v_coupon, note = v_note, updated_by = v_staff where id = v_id;
      end if;
    end if;
    if v_tiers_given then
      for v_e in select x from jsonb_array_elements(v_tiers) x loop
        update public.so_deal_tier t set min_amount = (v_e->>'min_amount')::numeric, pct = (v_e->>'pct')::numeric, note = v_e->>'note', updated_by = v_staff
         where t.deal_id = v_id and t.tier_no = (v_e->>'tier_no')::int
           and (t.min_amount <> (v_e->>'min_amount')::numeric or t.pct <> (v_e->>'pct')::numeric or t.note is distinct from (v_e->>'note'));
        if not found and not exists (select 1 from public.so_deal_tier t where t.deal_id = v_id and t.tier_no = (v_e->>'tier_no')::int) then
          insert into public.so_deal_tier (deal_id, tier_no, min_amount, pct, note, source, updated_by) values (v_id, (v_e->>'tier_no')::int, (v_e->>'min_amount')::numeric, (v_e->>'pct')::numeric, v_e->>'note', 'manual', v_staff);
        end if;
      end loop;
    end if;
    if v_lines_given then
      for v_e in select x from jsonb_array_elements(v_lines) x loop
        if (v_e->>'id') is not null then
          v_lid := (v_e->>'id')::uuid;
          update public.so_deal_line l set line_no = (v_e->>'line_no')::int, pct = (v_e->>'pct')::numeric, min_qty_mode = v_e->>'min_qty_mode', min_qty = (v_e->>'min_qty')::numeric, note = v_e->>'note', is_active = true, updated_by = v_staff
           where l.id = v_lid
             and (not l.is_active or l.line_no <> (v_e->>'line_no')::int or l.pct <> (v_e->>'pct')::numeric or l.min_qty_mode <> (v_e->>'min_qty_mode') or l.min_qty is distinct from (v_e->>'min_qty')::numeric or l.note is distinct from (v_e->>'note'));
        else
          insert into public.so_deal_line (deal_id, line_no, pct, min_qty_mode, min_qty, note, source, updated_by)
          values (v_id, (v_e->>'line_no')::int, (v_e->>'pct')::numeric, v_e->>'min_qty_mode', (v_e->>'min_qty')::numeric, v_e->>'note', 'manual', v_staff) returning id into v_lid;
        end if;
        if jsonb_typeof(v_e->'targets') = 'array' then
          for v_t in select x from jsonb_array_elements(v_e->'targets') x loop
            if not exists (select 1 from public.so_deal_target x where x.line_id = v_lid and (x.kind || '|' || x.target || '|' || coalesce(x.tag, x.brand_id::text, x.product_id::text, x.category_id::text)) = (v_t->>'nk')) then
              insert into public.so_deal_target (line_id, kind, target, tag, brand_id, product_id, category_id, note, source, updated_by)
              values (v_lid, v_t->>'kind', v_t->>'target',
                      case when v_t->>'target' = 'tag' then v_t->>'value' end,
                      case when v_t->>'target' = 'brand' then (v_t->>'value')::uuid end,
                      case when v_t->>'target' = 'product' then (v_t->>'value')::uuid end,
                      case when v_t->>'target' = 'category' then (v_t->>'value')::uuid end,
                      v_t->>'note', 'manual', v_staff);
            end if;
          end loop;
        end if;
      end loop;
    end if;
    if v_rules_given then
      for v_t in select x from jsonb_array_elements(v_rules) x loop
        if not exists (select 1 from public.so_deal_customer_rule x where x.deal_id = v_id and (x.kind || '|' || x.target || '|' || coalesce(x.customer_id::text, x.warehouse_id::text, x.tier_id::text)) = (v_t->>'nk')) then
          insert into public.so_deal_customer_rule (deal_id, kind, target, customer_id, warehouse_id, tier_id, note, source, updated_by)
          values (v_id, v_t->>'kind', v_t->>'target',
                  case when v_t->>'target' = 'customer' then (v_t->>'value')::uuid end,
                  case when v_t->>'target' = 'branch'   then (v_t->>'value')::uuid end,
                  case when v_t->>'target' = 'tier'     then (v_t->>'value')::uuid end,
                  v_t->>'note', 'manual', v_staff);
        end if;
      end loop;
    end if;
    set constraints all immediate;                                                                                  -- 맞바꾸기가 끝난 최종 모양을 지금 검사(어긋나면 23505 — 어휘 검사가 놓친 것)
    if v_create and v_active then
      update public.so_deal set is_active = true, updated_by = v_staff where id = v_id;
    elsif not v_create and v_child_changed and not v_head_changed then
      update public.so_deal set updated_by = v_staff where id = v_id;                                                -- 판정 331: 자식이 바뀌면 머리 판도 오른다(ims_touch)
    end if;
    select s.updated_at into v_new_updated from public.so_deal s where s.id = v_id;
    select count(*) into v_f1 from public.so s where s.reprice_suggested_at = now();
    v_flagged := v_f1 - v_f0;
    if v_flagged > 0 then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':open_orders_flagged', 'code', 'open_orders_flagged', 'n', v_flagged, 'message', format('%s open order(s) will be marked "reprice suggested" by this change', v_flagged));
      v_keys := array_append(v_keys, v_key || ':open_orders_flagged');
    end if;
    select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
    if not p_commit or cardinality(v_unacked) > 0 then
      raise exception using errcode = 'ZZ990', message = 'preview-rollback';
    end if;
  exception when sqlstate 'ZZ990' then
    v_rolled := true;
  end;

  if v_rolled then
    return jsonb_build_object('committed', false, 'deal_id', case when v_create then null else v_id end, 'updated_at', case when v_create then null else to_jsonb(d.updated_at) end,
                              'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', case when not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end, 'open_orders_to_flag', v_flagged);
  end if;
  return jsonb_build_object('committed', true, 'deal_id', v_id, 'updated_at', to_jsonb(v_new_updated), 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb, 'open_orders_to_flag', v_flagged);
end;
$$;
comment on function public.so_deal_save(jsonb, jsonb, boolean, text[]) is
  '⭐ 딜 통째 저장 창구(dsc-4a · 판정 285 · 330 ~ 334 · 340 · dsc-4b 판정 343 · 2026-10-06) — security definer · 첫 줄 ims_require_write(master). p_deal = 딜 하나 {id(null = 만들기) · name · is_active · date_from · date_to · is_order_level · kind(pct) · coupon_required · note · tiers[{tier_no, min_amount, pct, note}] · lines[{id(null = 새 줄), line_no, pct, min_qty_mode, min_qty, note, targets[{kind, target, tag|brand_id|product_id|category_id, note}]}] · rules[{kind, target, customer_id|warehouse_id|tier_id, note}]} · 계약(판정 343): 없는 열쇠 = 그대로(만들기면 기본값) · [] = 전부 지움(줄은 끔) · is_active false 로 돌아온 줄 = 없는 줄 · 읽기 전용 칸(cin7_id · source · created_at · updated_at · updated_by · coupon_code · deal_id · line_id · 자식 id)은 지나친다 · 모르는 열쇠는 field_unknown · so_deal_detail 의 deal 덩이를 그대로 되돌리면 no_change. p_old = 화면이 읽은 updated_at 글자({updated_at} 또는 글자 하나) — 다르면 changed_elsewhere · 기존 딜인데 없으면 old_missing(판정 331). 짝(판정 340): 줄 = id(덩이에 없는 기존 줄은 끈다 · 꺼진 줄도 line_no 를 쥔다 · 판정 342) · 단계 = tier_no · 대상 · 손님 조건 = 내용 전체. 검사만(p_commit false) → 저장(p_commit true + p_ack) · 막기 하나면 아무것도 안 바뀐다 · 미리 보기도 실제로 쓰고 표시 수를 센 뒤 되돌린다(open_orders_to_flag). blocks: deal_unknown · old_missing · changed_elsewhere · field_unknown · name_missing · value_invalid · kind_invalid · dates_invalid · tiers_invalid · tier_no_invalid · min_amount_invalid · pct_invalid · tier_no_duplicate · tier_amount_duplicate · lines_invalid · line_unknown · line_duplicate_in_call · line_no_invalid · min_qty_mode_invalid · min_qty_invalid · line_no_duplicate · targets_invalid · target_value_invalid · tag_case_conflict · brand_unknown · product_unknown · category_unknown · target_duplicate_in_call · rules_invalid · rule_value_invalid · customer_unknown · warehouse_unknown · tier_unknown · rule_duplicate_in_call · line_on_order_deal · lines_block_order_level_on · tier_on_line_deal · tiers_block_order_level_off · no_change. warnings(ack): open_orders_flagged{n} · line_off_with_order_lines{n} · tag_unused{tags} · deal_off_with_coupons{n} · line_no_targets · ⭐ rules_open_to_all{n_before}(dsc-4b 판정 343 — 걸기 조건 ≥ 1 이던 딜이 이 저장으로 0 이 되면 · 만들기 제외). changes[{part head|tier|line|target|rule · action added|changed|removed|turned_off|turned_on|unchanged}] 는 미리 보기 · 쓰기 같다. 반환 {committed · deal_id · updated_at(다음 저장의 p_old) · changes · blocks · warnings · unacked · open_orders_to_flag}. 새 행은 source manual · 고친 행의 source 는 그대로(판정 339 는 아직). 자식만 바뀌어도 머리 updated_at 이 오른다(판정 331)';

-- ═══ 3) so_deal_products — 「이 딜이 손댈 수 있는 제품」 집합(판정 337 · 속 함수) · 뜻 = so_deal_candidates 의 hit 과 같다(켜진 줄 · 걸기 ∧ ¬빼기(그 줄 안에서) · 제품 · 브랜드 · 카테고리 · 태그 · 세트는 낱개가 걸리면 같이 · 판정 302) · 수량 · 손님 · 기간 · 딜 켜짐은 보지 않는다 · 제품 필터 없음(candidates 와 같다 — 꺼진 제품도 든다 · 목록은 is_active 로 가른다) ═══
create function public.so_deal_products(p_deal_id uuid)
  returns table (product_id uuid, line_id uuid, line_no int, matched_by text[])
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  return query
  with l as (select x.id as line_id, x.line_no from public.so_deal_line x where x.deal_id = p_deal_id and x.is_active),
  t as (select x.line_id, x.kind, x.target, x.tag, x.brand_id, x.product_id, x.category_id from public.so_deal_target x join l on l.line_id = x.line_id),
  base as (                                                                                  -- 제품 자신이 대상에 맞는다(종류마다 인덱스 길)
    select t.line_id, t.kind, t.target, t.product_id                                  from t                                                                  where t.target = 'product'
    union all select t.line_id, t.kind, t.target, pr.id from t join public.product pr on pr.brand_id    = t.brand_id    where t.target = 'brand'
    union all select t.line_id, t.kind, t.target, pr.id from t join public.product pr on pr.category_id = t.category_id where t.target = 'category'
    union all select t.line_id, t.kind, t.target, pt.product_id from t join public.product_tag pt on pt.tag = t.tag      where t.target = 'tag'
  ),
  m as (                                                                                     -- 세트는 낱개가 걸리면 같이 걸린다(판정 302 · candidates 의 p 둘째 가지)
    select b.line_id, b.kind, b.target || '' as via, b.product_id from base b
    union all
    select b.line_id, b.kind, b.target || ':base', s.id from base b join public.product s on s.parent_product_id = b.product_id
  ),
  inc as (select m.line_id, m.product_id, array_agg(distinct m.via) as matched_by from m where m.kind = 'include' group by m.line_id, m.product_id),
  exc as (select distinct m.line_id, m.product_id from m where m.kind = 'exclude')
  select i.product_id, i.line_id, l.line_no, i.matched_by
    from inc i join l on l.line_id = i.line_id
    left join exc e on e.line_id = i.line_id and e.product_id = i.product_id
   where e.product_id is null;
end $$;
revoke all on function public.so_deal_products(uuid) from public, anon, authenticated;
comment on function public.so_deal_products(uuid) is '딜이 손댈 수 있는 제품 집합(dsc-4b · 판정 337) — 켜진 줄마다 (제품 · 줄 · 걸린 까닭[product|brand|category|tag(:base = 낱개를 거쳐)]) · 뜻은 so_deal_candidates 의 hit 과 같다(걸기 ∧ ¬빼기 · 빼기는 그 줄 안에서 · 세트는 낱개가 걸리면 같이 · 판정 302) · 수량 · 손님 · 기간 · 딜 켜짐 · 제품 켜짐은 보지 않는다(candidates 도 제품을 거르지 않는다) · 오더 딜은 줄이 없어 빈 집합 · 같음은 검증 dsc-4b T4 가 candidates 와 대조 · 속 함수(so_deal_list · so_deal_detail 만 부른다) · definer';

-- ═══ 4) so_deal_customers — 딜의 손님 조건에 맞는 활성 손님 집합(판정 337 · 속 함수) · 식은 so_deal_customer_ok 와 같은 뜻(빼기 하나라도 맞으면 뺀다 · 걸기는 종류마다 AND · 같은 종류 안 OR · 걸기 줄 없으면 전체) · 티어는 so_deal_best 의 null 폴백과 같게(손님 price_tier 이름 → sale 티어) ═══
create function public.so_deal_customers(p_deal_id uuid)
  returns table (customer_id uuid)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  return query
  with r as (select x.kind, x.target, x.customer_id, x.warehouse_id, x.tier_id from public.so_deal_customer_rule x where x.deal_id = p_deal_id),
  k as (select count(distinct x.target) as n from r x where x.kind = 'include'),
  c as (select cu.id, cu.default_location_id as branch_id, rt.id as tier_id
          from public.customer cu
          left join lateral (select x.id from public.ref_price_tier x where x.name = cu.price_tier and x.purpose = 'sale' and x.is_active limit 1) rt on true
         where cu.is_active),
  h as (select c.id, r.kind, r.target
          from c join r on (r.target = 'customer' and r.customer_id = c.id)
                        or (r.target = 'branch'   and r.warehouse_id = c.branch_id)
                        or (r.target = 'tier'     and r.tier_id = c.tier_id)),
  ex as (select distinct h.id from h where h.kind = 'exclude'),
  ok as (select h.id from h where h.kind = 'include' group by h.id having count(distinct h.target) = (select k.n from k))
  select c.id
    from c cross join k
    left join ex on ex.id = c.id
    left join ok on ok.id = c.id
   where ex.id is null and (k.n = 0 or ok.id is not null);
end $$;
revoke all on function public.so_deal_customers(uuid) from public, anon, authenticated;
comment on function public.so_deal_customers(uuid) is '딜의 손님 조건에 맞는 활성 손님 집합(dsc-4b · 판정 337) — so_deal_customer_ok(판정 299)와 같은 뜻을 집합 식으로(손님마다 함수를 부르면 느리다 · 검증 T5 가 같음을 증명) · 티어는 손님 price_tier 이름으로 찾은 sale 티어(so_deal_best 의 null 폴백 · 오더의 so.price_tier_id 가 아니다 — 목록은 오더가 없다) · 걸기 줄 없으면 활성 손님 전부 · 속 함수(so_deal_list · so_deal_detail 만 부른다) · definer';

-- ═══ 5) 읽기 창구 둘 — so_deal_list() · so_deal_detail(p_deal_id, p_limit) · 문은 so_quote_preview 와 같다(sales 보기 또는 master 쓰기) · 셈은 창구 안에서(판정 264) ═══
create function public.so_deal_list()
  returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_cust_all bigint;
  v_out jsonb;
  v_n int;
begin
  if not (public.ims_can_view('sales') or public.ims_can_write('master')) then
    raise exception 'You cannot view deals — ask an admin to add the ''sales'' permission — nothing was read';
  end if;
  select count(*) into v_cust_all from public.customer cu where cu.is_active;
  select coalesce(jsonb_agg(j order by (j->>'is_active')::boolean desc, (j->>'ended')::boolean, coalesce((j->>'date_from')::date, '1900-01-01') desc, (j->>'name') collate "C"), '[]'::jsonb), count(*)
    into v_out, v_n
    from (
      select jsonb_build_object(
               'id', d.id, 'name', d.name, 'source', d.source, 'kind', d.kind, 'is_order_level', d.is_order_level, 'is_active', d.is_active,
               'date_from', d.date_from, 'date_to', d.date_to, 'coupon_required', d.coupon_required, 'note', d.note,
               'ended', (d.date_to is not null and d.date_to < public.ims_today()),
               'lines_on',  (select count(*) from public.so_deal_line l where l.deal_id = d.id and l.is_active),
               'lines_off', (select count(*) from public.so_deal_line l where l.deal_id = d.id and not l.is_active),
               'tiers',     (select count(*) from public.so_deal_tier t where t.deal_id = d.id),
               'product_n',     case when d.is_order_level then null else (pc.n_active) end,
               'product_n_all', case when d.is_order_level then null else (pc.n_all) end,
               'all_customers', not exists (select 1 from public.so_deal_customer_rule x where x.deal_id = d.id),
               'customer_n',    case when exists (select 1 from public.so_deal_customer_rule x where x.deal_id = d.id) then (select count(*) from public.so_deal_customers(d.id)) else v_cust_all end,
               'coupons_unused', (select count(*) from public.so_coupon c where c.deal_id = d.id and c.used_so_id is null and c.voided_at is null),
               'open_orders_n', (select count(*) from public.so s where s.status in ('draft', 'confirmed', 'at_wms', 'picking', 'packed')
                                    and (s.order_discount_deal_id = d.id or exists (select 1 from public.so_line sl join public.so_deal_line l on l.id = sl.deal_line_id where sl.so_id = s.id and l.deal_id = d.id))),
               'updated_at', to_jsonb(d.updated_at)) as j
        from public.so_deal d
        left join lateral (select count(distinct p.product_id) filter (where pr.is_active) as n_active, count(distinct p.product_id) as n_all
                             from public.so_deal_products(d.id) p join public.product pr on pr.id = p.product_id
                            where not d.is_order_level) pc on true) z;
  return jsonb_build_object('count', v_n, 'active_customers', v_cust_all, 'today', public.ims_today(), 'deals', v_out);
end $$;
revoke all on function public.so_deal_list() from public, anon;
grant execute on function public.so_deal_list() to authenticated;
comment on function public.so_deal_list() is '⭐ 딜 목록 읽기 창구(dsc-4b · 판정 337 · 264) — definer · 문 sales 보기 또는 master 쓰기(so_quote_preview 와 같다) · 딜마다 {id · name · source · kind · is_order_level · is_active · date_from · date_to · coupon_required · note · ended(오늘 기준 끝남) · lines_on · lines_off · tiers · product_n(활성 제품 · 오더 딜은 null) · product_n_all(꺼진 제품 포함) · all_customers(조건 없음) · customer_n(활성 손님 · 조건 없으면 전부) · coupons_unused · open_orders_n(열린 오더 가운데 이 딜의 오더 할인 또는 이 딜 줄의 할인을 받은 것 — 「표시된」 수는 딜별로 기록되지 않는다) · updated_at(글자 · so_deal_save 의 p_old)} · 정렬 켜짐 → 안 끝남 → 최근 시작 → 이름 · 반환 {count · active_customers · today · deals[]} · 셈은 so_deal_products · so_deal_customers(속 함수) — 화면이 조각을 모으지 않는다';

create function public.so_deal_detail(p_deal_id uuid, p_limit int default 200)
  returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  d        public.so_deal%rowtype;
  v_deal   jsonb;
  v_labels jsonb;
  v_prod   jsonb;
  v_cust   jsonb;
  v_rules  boolean;
  v_lim    int := greatest(coalesce(p_limit, 200), 1);
begin
  if not (public.ims_can_view('sales') or public.ims_can_write('master')) then
    raise exception 'You cannot view deals — ask an admin to add the ''sales'' permission — nothing was read';
  end if;
  select * into d from public.so_deal where id = p_deal_id;
  if not found then raise exception 'Deal not found — nothing was read'; end if;
  -- ① 덩이 — so_deal_save 가 받는 모양 그대로(판정 343 계약 · 읽기 전용 칸 source · cin7_id · 자식 id 는 창구가 지나친다 · 꺼진 줄 포함 · 판정 342)
  v_deal := jsonb_build_object(
    'id', d.id, 'name', d.name, 'is_active', d.is_active, 'date_from', d.date_from, 'date_to', d.date_to, 'is_order_level', d.is_order_level,
    'kind', d.kind, 'coupon_required', d.coupon_required, 'note', d.note, 'source', d.source, 'cin7_id', d.cin7_id,
    'tiers', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'tier_no', t.tier_no, 'min_amount', t.min_amount, 'pct', t.pct, 'note', t.note) order by t.tier_no), '[]'::jsonb) from public.so_deal_tier t where t.deal_id = d.id),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'line_no', l.line_no, 'pct', l.pct, 'min_qty_mode', l.min_qty_mode, 'min_qty', l.min_qty, 'note', l.note, 'is_active', l.is_active, 'source', l.source,
                 'targets', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'target', x.target, 'tag', x.tag, 'brand_id', x.brand_id, 'product_id', x.product_id, 'category_id', x.category_id, 'note', x.note)
                                                      order by x.kind, x.target, coalesce(x.tag, x.brand_id::text, x.product_id::text, x.category_id::text)), '[]'::jsonb)
                               from public.so_deal_target x where x.line_id = l.id)) order by l.line_no), '[]'::jsonb)
              from public.so_deal_line l where l.deal_id = d.id),
    'rules', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'target', r.target, 'customer_id', r.customer_id, 'warehouse_id', r.warehouse_id, 'tier_id', r.tier_id, 'note', r.note)
                                        order by r.kind, r.target, coalesce(r.customer_id::text, r.warehouse_id::text, r.tier_id::text)), '[]'::jsonb)
              from public.so_deal_customer_rule r where r.deal_id = d.id));
  -- ② 이름표 — 덩이 밖에 따로(덩이에 섞으면 field_unknown) · 이 딜이 가리키는 id 만
  v_labels := jsonb_build_object(
    'brands',     (select coalesce(jsonb_object_agg(b.id, b.name), '{}'::jsonb) from public.ref_brand b where b.id in (select x.brand_id from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id where l.deal_id = d.id and x.brand_id is not null)),
    'categories', (select coalesce(jsonb_object_agg(c.id, c.name), '{}'::jsonb) from public.ref_category c where c.id in (select x.category_id from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id where l.deal_id = d.id and x.category_id is not null)),
    'products',   (select coalesce(jsonb_object_agg(p.id, jsonb_build_object('sku', p.sku, 'name', p.name, 'is_active', p.is_active)), '{}'::jsonb) from public.product p where p.id in (select x.product_id from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id where l.deal_id = d.id and x.product_id is not null)),
    'customers',  (select coalesce(jsonb_object_agg(cu.id, cu.name), '{}'::jsonb) from public.customer cu where cu.id in (select r.customer_id from public.so_deal_customer_rule r where r.deal_id = d.id and r.customer_id is not null)),
    'warehouses', (select coalesce(jsonb_object_agg(w.id, w.name), '{}'::jsonb) from public.ref_warehouse w where w.id in (select r.warehouse_id from public.so_deal_customer_rule r where r.deal_id = d.id and r.warehouse_id is not null)),
    'tiers',      (select coalesce(jsonb_object_agg(t.id, t.name), '{}'::jsonb) from public.ref_price_tier t where t.id in (select r.tier_id from public.so_deal_customer_rule r where r.deal_id = d.id and r.tier_id is not null)));
  -- ③ 걸리는 제품(활성 · p_limit 까지 + 전체 수) · 걸리는 손님
  if d.is_order_level then
    v_prod := jsonb_build_object('n', null, 'n_all', null, 'items', '[]'::jsonb);
  else
    select jsonb_build_object('n', count(*) filter (where z.is_active), 'n_all', count(*),
                              'items', coalesce(jsonb_agg(jsonb_build_object('product_id', z.id, 'sku', z.sku, 'name', z.name, 'is_active', z.is_active, 'is_set', z.parent_product_id is not null, 'line_nos', z.line_nos, 'matched_by', z.matched_by)
                                                 order by z.sku) filter (where z.rn <= v_lim), '[]'::jsonb))
      into v_prod
      from (select pr.id, pr.sku, pr.name, pr.is_active, pr.parent_product_id, g.line_nos, g.matched_by, row_number() over (order by pr.is_active desc, pr.sku) as rn
              from (select p.product_id, array_agg(distinct p.line_no order by p.line_no) as line_nos, array_agg(distinct m order by m) as matched_by
                      from public.so_deal_products(d.id) p cross join lateral unnest(p.matched_by) m group by p.product_id) g
              join public.product pr on pr.id = g.product_id) z;
  end if;
  v_rules := exists (select 1 from public.so_deal_customer_rule r where r.deal_id = d.id);
  select jsonb_build_object('all_customers', not v_rules, 'n', count(*),
                            'items', coalesce(jsonb_agg(jsonb_build_object('customer_id', z.id, 'name', z.name) order by z.name collate "C") filter (where z.rn <= v_lim), '[]'::jsonb))
    into v_cust
    from (select cu.id, cu.name, row_number() over (order by cu.name collate "C") as rn
            from public.customer cu
           where cu.is_active and (not v_rules or cu.id in (select c.customer_id from public.so_deal_customers(d.id) c))) z;
  return jsonb_build_object(
    'deal', v_deal, 'updated_at', to_jsonb(d.updated_at), 'labels', v_labels, 'products', v_prod, 'customers', v_cust,
    'coupons', (select jsonb_build_object('unused', count(*) filter (where c.used_so_id is null and c.voided_at is null), 'used', count(*) filter (where c.used_so_id is not null), 'voided', count(*) filter (where c.voided_at is not null)) from public.so_coupon c where c.deal_id = d.id),
    'open_orders_n', (select count(*) from public.so s where s.status in ('draft', 'confirmed', 'at_wms', 'picking', 'packed')
                         and (s.order_discount_deal_id = d.id or exists (select 1 from public.so_line sl join public.so_deal_line l on l.id = sl.deal_line_id where sl.so_id = s.id and l.deal_id = d.id))),
    'limit', v_lim);
end $$;
revoke all on function public.so_deal_detail(uuid, int) from public, anon;
grant execute on function public.so_deal_detail(uuid, int) to authenticated;
comment on function public.so_deal_detail(uuid, int) is '⭐ 딜 상세 읽기 창구(dsc-4b · 판정 337 · 343 · 264) — definer · 문 sales 보기 또는 master 쓰기 · 반환 {deal(⭐ so_deal_save 가 받는 덩이 그대로 — id · name · is_active · date_from · date_to · is_order_level · kind · coupon_required · note · tiers[] · lines[](꺼진 줄 포함 · is_active · 판정 342) · rules[] · 읽기 전용 source · cin7_id · 자식 id 는 창구가 지나친다 · 그대로 되돌리면 no_change) · updated_at(글자 · 다음 저장의 p_old) · labels{brands · categories · products · customers · warehouses · tiers — id → 이름 · 덩이 밖} · products{n(활성) · n_all · items[≤ p_limit · product_id · sku · name · is_active · is_set · line_nos · matched_by]} · customers{all_customers · n(활성) · items[≤ p_limit]} · coupons{unused · used · voided} · open_orders_n · limit} · 셈은 so_deal_products · so_deal_customers(속 함수)';

-- ═══ 6) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare
  v_t   text;
  v_bad text := '';
  v_n   int;
begin
  if to_regprocedure('public.so_deal_products(uuid)') is null or to_regprocedure('public.so_deal_customers(uuid)') is null or to_regprocedure('public.so_deal_list()') is null or to_regprocedure('public.so_deal_detail(uuid, int)') is null then v_bad := v_bad || ' functions'; end if;
  foreach v_t in array array['public.so_deal_products(uuid)', 'public.so_deal_customers(uuid)'] loop
    if has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(open)', v_t); end if;
  end loop;
  foreach v_t in array array['public.so_deal_list()', 'public.so_deal_detail(uuid, int)', 'public.product_update(jsonb, boolean, text[])', 'public.so_deal_save(jsonb, jsonb, boolean, text[])'] loop
    if not has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(grants)', v_t); end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'product_update') <> 1 then v_bad := v_bad || ' product_update(count)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'product_update' and p.prosrc like '%''tag_add''%' and p.prosrc like '%tag_case_conflict%' and p.prosrc like '%tag_off_used_by_deal%') <> 1 then v_bad := v_bad || ' product_update(tag ops)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_save' and p.prosrc like '%rules_open_to_all%') <> 1 then v_bad := v_bad || ' so_deal_save(rules_open_to_all)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_deal_candidates', 'so_deal_customer_ok') and p.prosrc like '%dsc-4b%') <> 0 then v_bad := v_bad || ' candidates/customer_ok(touched)'; end if;
  foreach v_t in array array['so_deal', 'so_deal_tier', 'so_deal_line', 'so_deal_target', 'so_deal_customer_rule', 'product_tag', 'so_coupon'] loop
    if (select count(*) from pg_policies where schemaname = 'public' and tablename = v_t) <> 1
       or has_table_privilege('authenticated', format('public.%I', v_t), 'insert') or has_table_privilege('authenticated', format('public.%I', v_t), 'update') or has_table_privilege('authenticated', format('public.%I', v_t), 'delete')
       or has_table_privilege('anon', format('public.%I', v_t), 'select') then
      v_bad := v_bad || format(' %s(still closed?)', v_t);
    end if;
  end loop;
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')
     and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?(so_deal|so_deal_tier|so_deal_line|so_deal_target|so_deal_customer_rule|product_tag|so_coupon)\M';
  if v_n <> 0 then v_bad := v_bad || format(' invoker-writers(%s)', v_n); end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM337', message = format('STOP - dsc-4b did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
