-- prod-4a — 상품 고치기 창구 product_update(첫 조각: 상품 칸 · SKU · 활성 · 계수 · 부모 · family) + 판정 190 을 family 창구에 (2026-10-01 · 판정 187 ~ 190 · 135 ~ 145 · 174 ~ 186 · so-module §31-a · §33-a · po-module §3-h)
--   판정 187  고치기 창구는 하나 · 바꿀 것을 목록으로(한 줄 = SKU · 무엇을 · 새 값 · 옛 값) · prod-3 와 같은 두 번 부르기(판정 176) · 한 트랜잭션 · 막기 하나면 아무것도 안 바뀜 — 판정 135 「줄마다 작은 창구」는 목록의 줄로 지킨다
--   판정 189  세트가 딸린 낱개의 SKU 를 고치면 세트 SKU 도 창구가 함께(<새 낱개 SKU>-<계수> · 판정 177 규칙) · 세트 하나라도 기록이 붙으면 전체 막기 · 세트 이름은 건드리지 않는다(알리기만)
--   판정 190  옵션 축 이름이 대소문자만 다른 더 흔한 이름이 있으면 알리기(option_name_case · 철자 차이는 안 잡는다) — 검사가 사는 곳 둘: product_family_create 머리(새 family · 재발행) · product_update family_head_set(축 이름 고치기) · 둘 다 도우미 product_axis_case_hint 하나
--   묶음 2    옛 값 대조 — 줄마다 화면이 본 옛 값(old)을 함께 · 저장 때 지금 값과 다르면 그 줄 막기 changed_elsewhere(「Someone just changed … — check again」) · set · family_leave · family_option · family_head_set 은 old 필수(old_missing) · family_join 은 old 없음
--   묶음 3    set 의 칸: name · brand_id · category_id · unit_id · weight · weight_unit · note · is_discontinued · set_discount_pct(세트만) · sku · is_active · pack_factor(세트만) · parent_sku(세트만) · 이름 칸 복사(판정 143 ①) · 세트 단위 ≠ 계수면 알리기(판정 139)
--   묶음 4    sku: 원장 · 레이어 있으면 창구가 먼저 문장으로 막는다(sku_locked · 트리거 IM136 은 마지막 문) · 공백 · 소문자 · 이미 있는 SKU · 같은 호출 중복 · 세트 따라 고침(set_renamed 알리기 · 세트에 기록이면 sku_locked_set)
--   묶음 5    is_active false: 재고(ims_inv_balance 합) · 열린 SO 줄(so.status draft · confirmed · at_wms · picking · packed · 20260923133042:128) · 열린 PO 줄(po.status draft · confirmed · 20260916144201:83) · 켜진 세트 수 — 0 이 아닌 것만 알리기(판정 139) · true 는 경고 없음
--   묶음 6    pack_factor · parent_sku: 「사건」 = 원장 · 레이어(sku) 또는 거래 줄(so_line · so_credit_line · po_line(product_id · entered_unit_product_id) · po_invoice_line(entered_unit_product_id) · po_receipt_diff · inv_adjust_line · inv_move_line · inv_transfer_line) 하나라도 — 모든 줄(열린 줄만이 아니다 · 판정 137 이 「지난 기록이면 허용」을 기각) → set_locked · 없으면 허용 · SKU 는 창구가 따라 고침 · 새 부모는 활성 낱개
--   묶음 10   family: family_join(있는 상품을 family 에 · 옵션 규칙은 prod-3b 와 같다 · 세트는 못 넣는다) · family_leave · family_option · family_head_set(이름 · 브랜드 · 분류 · 단위 · 메모 · 활성 · 축 이름 바꾸기만 — 축 수 변경은 axis_count_change 막기 · ⬜6)
--   묶음 11   둘째 조각 prod-4b = 바코드(barcode_add · barcode_off · barcode_primary · 판정 179 · 188) · 판매가(price_set · price_off) · 공급처(supplier_set · supplier_off · supplier_default) — 같은 창구에 op 를 더한다(모양 · 열쇠 · 두 번 부르기 그대로)
--   막기 code  op_unknown(raise) · sku_unknown · field_unknown · old_missing · changed_elsewhere · field_duplicate_in_call · name_missing · brand_unknown · category_unknown · unit_unknown · not_a_set · set_discount_invalid
--              sku_space · sku_lowercase · sku_exists · sku_duplicate_in_call · sku_locked · sku_locked_set · set_sku_managed · set_sku_exists · set_locked · set_factor_invalid · parent_unknown · parent_not_single
--              family_unknown · not_in_family · already_in_family · set_not_family_member · option_count · option_exists · option_duplicate_in_call · axis_count_change · weight_invalid · value_invalid
--   알리기 code set_renamed(판정 189) · sku_open_lines(⬜5) · set_unit_mismatch(판정 139) · set_unit_unknown · inactive_stock · inactive_open_so · inactive_open_po · inactive_sets_on(판정 139) · option_inactive_exists · option_name_unusual · option_name_case(판정 190) · inactive_variants_on
--   열쇠      <SKU>:<code>(set 의 칸 code 는 :<field> 까지 · 값으로 갈라야 하면 :<값>) · family_head_set 은 <family SKU>:<code>:<field>
--   반환      { committed, changes:[{i, sku, op, field, applied}], blocks:[{key, sku, code, message}], warnings:[…], unacked:[key…] } · raise 는 문 · 모양(배열 아님 · 0 · 1,000 초과 · 모르는 op) · 23505 셋
--   검증: ~/asung/prompts/prod-4a-verify.sql (시험 적용 장치 · 테스트 DB · rollback · R 절 = product_family_create 재발행 증명)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 의 바이트 복사 — 운영에서는 멈춘다(컷오버 전 운영 적용 금지 · ims-principles)

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

-- ═══ A) 도우미 둘 — 축 이름 대소문자 힌트(판정 190) · 사건 유무(판정 137 ①) ═══════════════════════════════════════════════
create or replace function public.product_axis_case_hint(p_name text) returns table (common_name text, n_families bigint)
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  with n as (
    select f.option1_name as nm from public.product_family f where f.is_active
    union all select f.option2_name from public.product_family f where f.is_active
    union all select f.option3_name from public.product_family f where f.is_active
  )
  select n.nm, count(*)
    from n
   where n.nm is not null and lower(n.nm) = lower(p_name) and n.nm <> p_name
   group by n.nm
  having count(*) > (select count(*) from n where n.nm = p_name)
   order by 2 desc, 1 limit 1;
$$;
comment on function public.product_axis_case_hint(text) is '판정 190(prod-4a) — 활성 family 가 쓰는 옵션 축 이름 중 대소문자만 다르고 더 흔한 철자가 있으면 (그 철자, family 수) 한 행 · 없으면 0 행 · 철자 차이(Flavor/Flavour)는 안 본다 · product_family_create 머리 검사와 product_update family_head_set 이 같이 쓴다';
revoke all on function public.product_axis_case_hint(text) from public, anon;
grant execute on function public.product_axis_case_hint(text) to authenticated;

create or replace function public.product_has_events(p_id uuid, p_sku text) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select exists (select 1 from public.inv_ledger e where e.sku = p_sku)
      or exists (select 1 from public.inv_layer l where l.sku = p_sku)
      or exists (select 1 from public.so_line x where x.product_id = p_id)
      or exists (select 1 from public.so_credit_line x where x.product_id = p_id)
      or exists (select 1 from public.po_line x where x.product_id = p_id or x.entered_unit_product_id = p_id)
      or exists (select 1 from public.po_invoice_line x where x.entered_unit_product_id = p_id)
      or exists (select 1 from public.po_receipt_diff x where x.product_id = p_id)
      or exists (select 1 from public.inv_adjust_line x where x.product_id = p_id)
      or exists (select 1 from public.inv_move_line x where x.product_id = p_id)
      or exists (select 1 from public.inv_transfer_line x where x.product_id = p_id);
$$;
comment on function public.product_has_events(uuid, text) is '판정 137 ① 의 「사건이 붙은 상품」(prod-4a 묶음 6 · ⬜3) — 원장 · 레이어(sku 글자) 또는 거래 줄 아홉 자리(product.id 를 무는 FK 중 거래 표 · so_deal_target 은 거래가 아니라 제외) 하나라도 · 모든 줄(열린 줄만이 아니다) · 세트 계수 · 부모 잠금에 쓴다 · SKU 잠금(판정 136)은 원장 · 레이어만(트리거 그대로)';
revoke all on function public.product_has_events(uuid, text) from public, anon, authenticated;

-- ═══ B) product_family_create 재발행 — 머리 축 이름 검사에 판정 190 한 갈래(옮긴 줄은 20261001134426 본문 그대로 · 더한 줄은 「prod-4a」 표시) ═══
create or replace function public.product_family_create(p_family jsonb, p_items jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_f       jsonb := coalesce(p_family, '{}'::jsonb);
  v_fam     public.product_family%rowtype;
  v_mode    text;
  v_famsku  text;
  v_key     text;
  v_name    text;
  v_names   text[] := '{}';
  v_n1      text; v_n2 text; v_n3 text;
  v_nm      text;
  v_hn      text;                                                                              -- prod-4a 판정 190: 대소문자만 다른 더 흔한 축 이름
  v_hc      bigint;
  v_blocks  jsonb := '[]'::jsonb;
  v_warns   jsonb := '[]'::jsonb;
  v_ctx     jsonb;
begin
  perform public.ims_require_write('master', 'saved');                                        -- ⭐ 유일한 문 — 첫 줄(판정 140)
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'p_items must be a JSON array of products — nothing was saved';
  end if;
  if jsonb_typeof(v_f) <> 'object' then
    raise exception 'p_family must be a JSON object — nothing was saved';
  end if;

  if v_f ? 'id' then
    -- 변형 더하기 — 있는 family 를 가리킨다 · 머리 칸이 함께 오면 모호하다
    v_mode := 'existing';
    select * into v_fam from public.product_family f where f.id = (v_f->>'id')::uuid;
    v_famsku := coalesce(v_fam.sku, '');
    v_key := case when v_famsku = '' then '(family)' else v_famsku end;
    if (select count(*) from jsonb_object_keys(v_f)) > 1 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_head_ambiguous', 'sku', v_famsku, 'code', 'family_head_ambiguous', 'message', 'p_family has both an id and head fields — point at a family or describe a new one, not both — nothing was saved');
    end if;
    if v_fam.id is null or not v_fam.is_active then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_unknown', 'sku', v_famsku, 'code', 'family_unknown', 'message', 'The family does not exist or is inactive — nothing was saved');
    else
      v_name  := v_fam.name;
      v_names := array_remove(array[nullif(trim(v_fam.option1_name), ''), nullif(trim(v_fam.option2_name), ''), nullif(trim(v_fam.option3_name), '')], null);
    end if;
  else
    -- 새 family — 머리 이름 필수 · SKU 는 판정 182 · 브랜드 · 분류 · 단위 id · 옵션 축 이름 1 ~ 3
    v_mode := 'new';
    v_name := trim(coalesce(v_f->>'name', ''));
    v_famsku := trim(coalesce(v_f->>'sku', ''));
    if v_famsku = '' then
      v_famsku := trim(coalesce(p_items->0->>'sku', '')) || 'FAM';                             -- 판정 182 — 첫 변형(배열 순서) + FAM · 그 SKU 가 막혀도 지어 보여 준다
    end if;
    v_key := case when v_famsku = 'FAM' then '(family)' else v_famsku end;
    if v_name = '' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_name_missing', 'sku', v_famsku, 'code', 'family_name_missing', 'message', 'The family has no name — nothing was saved');
    end if;
    if v_famsku = 'FAM' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_sku_missing', 'sku', v_famsku, 'code', 'family_sku_missing', 'message', 'The family has no SKU and the first variant has none to build it from — nothing was saved');
    end if;
    if v_famsku !~ 'FAM$' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_sku_suffix', 'sku', v_famsku, 'code', 'family_sku_suffix', 'message', format('Family SKU %s must end with FAM — nothing was saved', v_famsku));
    end if;
    if v_famsku ~ '\s' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_sku_space', 'sku', v_famsku, 'code', 'family_sku_space', 'message', format('Family SKU "%s" contains a space — nothing was saved', v_famsku));
    end if;
    if v_famsku ~ '[a-z]' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_sku_lowercase', 'sku', v_famsku, 'code', 'family_sku_lowercase', 'message', format('Family SKU %s has lowercase letters — use capitals — nothing was saved', v_famsku));
    end if;
    if exists (select 1 from public.product_family f where f.sku = v_famsku) or exists (select 1 from public.product p where p.sku = v_famsku) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_sku_exists', 'sku', v_famsku, 'code', 'family_sku_exists', 'message', format('Family SKU %s already exists — nothing was saved', v_famsku));
    end if;
    if v_f->>'brand_id' is null then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':brand_missing', 'sku', v_famsku, 'code', 'brand_missing', 'message', format('Family %s has no brand', v_famsku));
    elsif not exists (select 1 from public.ref_brand b where b.id = (v_f->>'brand_id')::uuid and b.is_active) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':brand_unknown', 'sku', v_famsku, 'code', 'brand_unknown', 'message', format('Family %s: the brand does not exist or is inactive — nothing was saved', v_famsku));
    end if;
    if v_f->>'category_id' is not null and not exists (select 1 from public.ref_category c where c.id = (v_f->>'category_id')::uuid and c.is_active) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':category_unknown', 'sku', v_famsku, 'code', 'category_unknown', 'message', format('Family %s: the category does not exist or is inactive — nothing was saved', v_famsku));
    end if;
    if v_f->>'unit_id' is not null and not exists (select 1 from public.ref_unit u where u.id = (v_f->>'unit_id')::uuid and u.is_active) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':unit_unknown', 'sku', v_famsku, 'code', 'unit_unknown', 'message', format('Family %s: the unit does not exist or is inactive — nothing was saved', v_famsku));
    end if;
    v_n1 := nullif(trim(coalesce(v_f->>'option1_name', '')), '');
    v_n2 := nullif(trim(coalesce(v_f->>'option2_name', '')), '');
    v_n3 := nullif(trim(coalesce(v_f->>'option3_name', '')), '');
    if v_n1 is null and v_n2 is null and v_n3 is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_names_missing', 'sku', v_famsku, 'code', 'option_names_missing', 'message', format('Family %s needs at least one option axis (option1_name, e.g. Color) — nothing was saved', v_famsku));
    elsif (v_n1 is null and (v_n2 is not null or v_n3 is not null)) or (v_n2 is null and v_n3 is not null) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_names_gap', 'sku', v_famsku, 'code', 'option_names_gap', 'message', format('Family %s: option axes must be filled in order (option1, then option2, then option3) — nothing was saved', v_famsku));
    else
      v_names := array_remove(array[v_n1, v_n2, v_n3], null);
      foreach v_nm in array v_names loop
        if not exists (select 1 from public.product_family f where f.is_active and v_nm in (f.option1_name, f.option2_name, f.option3_name)) then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':option_name_unusual:' || v_nm, 'sku', v_famsku, 'code', 'option_name_unusual', 'message', format('Option axis "%s" is not used by any active family yet — check the spelling (e.g. Color vs Colour)', v_nm));
        else                                                                                   -- prod-4a 판정 190: 쓰는 이름이지만 대소문자만 다른 더 흔한 철자가 있으면 알린다
          select h.common_name, h.n_families into v_hn, v_hc from public.product_axis_case_hint(v_nm) h;
          if v_hn is not null then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':option_name_case:' || v_nm, 'sku', v_famsku, 'code', 'option_name_case', 'message', format('Option axis "%s" — %s active families spell it "%s" — use that spelling unless this is on purpose', v_nm, v_hc, v_hn));
          end if;
        end if;
      end loop;
    end if;
  end if;

  if jsonb_array_length(p_items) = 0 then                                                    -- ⬜5 안 — 변형 없는 family 는 만들지 않는다(팔 수 없는 빈 군)
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':no_variants', 'sku', v_famsku, 'code', 'no_variants', 'message', 'A family needs at least one variant — nothing was saved');
    return jsonb_build_object('committed', false, 'items', '[]'::jsonb, 'blocks', v_blocks, 'warnings', v_warns, 'unacked', '[]'::jsonb,
                              'family', jsonb_build_object('id', v_fam.id, 'sku', v_famsku, 'created', false));
  end if;

  v_ctx := jsonb_build_object('mode', v_mode, 'family_id', v_fam.id, 'family_sku', v_famsku, 'name', v_name, 'note', v_f->>'note',
                              'brand_id',    case when v_mode = 'new' then v_f->>'brand_id'    else v_fam.brand_id::text    end,
                              'category_id', case when v_mode = 'new' then v_f->>'category_id' else v_fam.category_id::text end,
                              'unit_id',     case when v_mode = 'new' then v_f->>'unit_id'     else v_fam.unit_id::text     end,
                              'option_names', to_jsonb(v_names), 'head_blocks', v_blocks, 'head_warnings', v_warns);
  return public.product_create_core(p_items, v_ctx, p_commit, p_ack);
end;
$$;

-- ═══ C) 고치기 창구 ═══════════════════════════════════════════════════════════════════════════════════════════════════
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
  v_keys     text[];
  v_unacked  text[];
  v_newname  text;
  v_fields   constant text[] := array['name', 'brand_id', 'category_id', 'unit_id', 'weight', 'weight_unit', 'note', 'is_discontinued', 'set_discount_pct', 'sku', 'is_active', 'pack_factor', 'parent_sku'];
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
    if coalesce(v_c->>'op', '') not in ('set', 'family_join', 'family_leave', 'family_option', 'family_head_set') then
      raise exception 'Unknown op "%" — set, family_join, family_leave, family_option or family_head_set — nothing was saved', coalesce(v_c->>'op', '(none)');
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
        when 'brand_id' then update public.product_family set brand_id = v_vtxt::uuid, brand_name = (select b.name from public.ref_brand b where b.id = v_vtxt::uuid) where id = v_fam.id;
        when 'category_id' then update public.product_family set category_id = v_vtxt::uuid, category_name = (select c.name from public.ref_category c where c.id = v_vtxt::uuid) where id = v_fam.id;
        when 'unit_id' then update public.product_family set unit_id = v_vtxt::uuid, uom_name = (select u.name from public.ref_unit u where u.id = v_vtxt::uuid) where id = v_fam.id;
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
revoke all on function public.product_update(jsonb, boolean, text[]) from public, anon;
grant execute on function public.product_update(jsonb, boolean, text[]) to authenticated;
comment on function public.product_update(jsonb, boolean, text[]) is
  '⭐ 상품 고치기 창구(판정 187 ~ 190 · 2026-10-01 prod-4a · 첫 조각) — security definer · 첫 줄 ims_require_write(master). p_changes = 바꿀 것 목록(최대 1,000 줄) · 줄 = {sku, op, field, value, old} · op: set(칸 하나 — name · brand_id · category_id · unit_id · weight · weight_unit · note · is_discontinued · set_discount_pct · sku · is_active · pack_factor · parent_sku) · family_join {sku, family_sku, options[]} · family_leave {sku, old: family sku} · family_option {sku, options[], old: [옛 값]} · family_head_set {family_sku, field, value, old}. old = 화면이 본 옛 값 — 지금 값과 다르면 changed_elsewhere 막기(두 사람이 같은 상품을 고칠 때 뒤 사람이 모르고 덮지 않게). 검사만(p_commit false) → 저장(p_commit true + p_ack) 두 번 부르기 · 저장 직전 재검사(판정 176) · 막기 하나면 아무것도 안 바뀐다 · 줄 순서대로 저장 · 이 호출의 다른 줄은 화면이 본 옛 SKU 로 가리킨다. SKU 를 바꾸면 세트 SKU 도 따라(판정 189) · 세트 계수 · 부모는 사건 없을 때만(판정 137 ① · product_has_events) · is_active 끄기는 재고 · 열린 SO · PO 줄 · 켜진 세트 수를 알린다(판정 139). 바코드 · 판매가 · 공급처 op 는 prod-4b. code 목록은 파일 머리';
