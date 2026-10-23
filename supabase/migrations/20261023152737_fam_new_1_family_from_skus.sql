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

-- ═══ fam-new-1 — 기존 SKU 들로 새 family 만들기(다른 family 에서 옮기기 포함) (2026-10-23 · 판정 652 · 653 B) ═══
--   ① 머리 검사 product_family_head_ctx · 머리 insert product_family_head_insert — product_family_create · product_create_core 에서 바이트 그대로 떼어 한 곳(「한 곳만 고친다」 재발 막기) · 두 함수 재발행(호출 한 줄 · 출력 동일 N5)
--   ② 새 창구 product_family_from_skus(p_family, p_items[{sku, options[]}], p_commit, p_ack) — 검사 → 확인 → 저장 꼴 · 반환 꼴 = product_family_create(runWindow 가 그대로 그린다)
--      문 master · 머리 검사는 ① · 구성원 검사는 family_join 과 같은 식(sku_unknown · sku_inactive · set_not_family_member · field_duplicate_in_call · option_count · option_duplicate_in_call)
--      653: 구성원이 다른 family 에 있으면 경고 moves_from_family(ack) · 옛 family 가 구성원 0 이 되면 경고 old_family_emptied(ack · 빈 머리는 그대로 — family_leave 와 같다 · 지우지 않는다)
--      원장 · 가격 · 바코드 · 공급처 · 재고 · 판매 줄 · Shopify 연결은 건드리지 않는다(product 의 family_id · option 값만 · Shopify 큐는 product 트리거가 옛 · 새 family 를 함께 올린다)
--   새 표 · 시퀀스 0

create function public.product_family_head_ctx(p_family jsonb, p_items jsonb) returns jsonb
language plpgsql set search_path = public, pg_temp as $function$
-- fam-new-1: family 머리 검사 한 곳 — product_family_create(prod-3b · 판정 181 ~ 185 · 190)의 머리 블록을 바이트 그대로 옮겼다 · product_family_from_skus 가 같이 쓴다
--   반환 = product_create_core 가 받는 family_ctx(mode · family_id · family_sku · name · note · brand_id · category_id · unit_id · option_names · head_blocks · head_warnings) + key
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
begin
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

  return jsonb_build_object('mode', v_mode, 'family_id', v_fam.id, 'family_sku', v_famsku, 'key', v_key, 'name', v_name, 'note', v_f->>'note',
                            'brand_id',    case when v_mode = 'new' then v_f->>'brand_id'    else v_fam.brand_id::text    end,
                            'category_id', case when v_mode = 'new' then v_f->>'category_id' else v_fam.category_id::text end,
                            'unit_id',     case when v_mode = 'new' then v_f->>'unit_id'     else v_fam.unit_id::text     end,
                            'option_names', to_jsonb(v_names), 'head_blocks', v_blocks, 'head_warnings', v_warns);
end
$function$;
revoke all on function public.product_family_head_ctx(jsonb, jsonb) from public, anon, authenticated, service_role;
comment on function public.product_family_head_ctx(jsonb, jsonb) is 'fam-new-1 — family 머리 검사 한 곳(product_family_create 에서 옮김 · 바이트 그대로) · definer 사슬 전용(실행권 없음)';

create function public.product_family_head_insert(p_ctx jsonb) returns uuid
language plpgsql set search_path = public, pg_temp as $function$
-- fam-new-1: family 머리 행 한 곳 — product_create_core(prod-3b)의 insert 를 바이트 그대로 옮겼다(v_fx → p_ctx) · product_family_from_skus 가 같이 쓴다 · unique 23505 는 부르는 쪽이 문장으로
declare v_famid uuid;  v_fx jsonb := p_ctx;
begin
      insert into public.product_family (sku, name, source, note, brand_id, brand_name, category_id, category_name, unit_id, uom_name, option1_name, option2_name, option3_name)
      values (v_fx->>'family_sku', v_fx->>'name', 'manual', nullif(trim(v_fx->>'note'), ''),
              (v_fx->>'brand_id')::uuid,    (select b.name from public.ref_brand b    where b.id = (v_fx->>'brand_id')::uuid),
              (v_fx->>'category_id')::uuid, (select c.name from public.ref_category c where c.id = (v_fx->>'category_id')::uuid),
              (v_fx->>'unit_id')::uuid,     (select u.name from public.ref_unit u     where u.id = (v_fx->>'unit_id')::uuid),
              v_fx->'option_names'->>0, v_fx->'option_names'->>1, v_fx->'option_names'->>2)
      returning id into v_famid;
  return v_famid;
end
$function$;
revoke all on function public.product_family_head_insert(jsonb) from public, anon, authenticated, service_role;
comment on function public.product_family_head_insert(jsonb) is 'fam-new-1 — family 머리 insert 한 곳(product_create_core 에서 옮김 · 바이트 그대로) · definer 사슬 전용(실행권 없음)';

-- ═══ product_family_create 재발행 — 원본 DB 바이트(md5 cab0fe577fa9bc0210c38fcbb8cae052) · 도우미로 뗀 블록은 호출 한 줄로(줄 끝 「fam-new-1」) · 서명 · 권한 · comment 그대로 ═══
CREATE OR REPLACE FUNCTION public.product_family_create(p_family jsonb, p_items jsonb, p_commit boolean DEFAULT false, p_ack text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  v_ctx := public.product_family_head_ctx(v_f, p_items);                                       -- fam-new-1: 머리 검사는 도우미 한 곳(product_family_from_skus 와 함께) · 아래 no_variants 가 읽는 넷
  v_mode := v_ctx->>'mode';  v_famsku := v_ctx->>'family_sku';  v_key := v_ctx->>'key';  v_fam.id := nullif(v_ctx->>'family_id', '')::uuid;   -- fam-new-1
  v_blocks := v_ctx->'head_blocks';  v_warns := v_ctx->'head_warnings';                                                                        -- fam-new-1

  if jsonb_array_length(p_items) = 0 then                                                    -- ⬜5 안 — 변형 없는 family 는 만들지 않는다(팔 수 없는 빈 군)
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':no_variants', 'sku', v_famsku, 'code', 'no_variants', 'message', 'A family needs at least one variant — nothing was saved');
    return jsonb_build_object('committed', false, 'items', '[]'::jsonb, 'blocks', v_blocks, 'warnings', v_warns, 'unacked', '[]'::jsonb,
                              'family', jsonb_build_object('id', v_fam.id, 'sku', v_famsku, 'created', false));
  end if;

  return public.product_create_core(p_items, v_ctx, p_commit, p_ack);
end;
$function$;

-- ═══ product_create_core 재발행 — 원본 DB 바이트(md5 8775929fdf788611336976badf41a4c6) · 도우미로 뗀 블록은 호출 한 줄로(줄 끝 「fam-new-1」) · 서명 · 권한 · comment 그대로 ═══
CREATE OR REPLACE FUNCTION public.product_create_core(p_items jsonb, p_family_ctx jsonb, p_commit boolean, p_ack text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_items    jsonb := '[]'::jsonb;
  v_sets_out jsonb;
  v_n        int;
  v_it       jsonb;
  v_st       jsonb;
  v_bc       text;
  v_pr       jsonb;
  v_sp       jsonb;
  v_sku      text;
  v_name     text;
  v_setsku   text;
  v_setname  text;
  v_factor   numeric;
  v_digits   text;
  v_prefix   text;
  v_brand    public.ref_brand%rowtype;
  v_cat      public.ref_category%rowtype;
  v_unit     public.ref_unit%rowtype;
  v_setunit  public.ref_unit%rowtype;
  v_tier     public.ref_price_tier%rowtype;
  v_seen_sku text[] := '{}';
  v_seen_bc  jsonb := '{}'::jsonb;
  v_bcs      text[];
  v_factors  numeric[];
  v_tiers    uuid[];
  v_sups     uuid[];
  v_ndef     int;
  v_r2_ok    boolean;
  v_r2_seen  boolean;
  v_owner    record;
  v_pid      uuid;
  v_sid      uuid;
  v_i        int;
  v_unacked  text[];
  v_keys     text[];
  v_ok       boolean;
  v_fx       jsonb := p_family_ctx;                                                            -- prod-3b: family 머리(없으면 prod-3 와 같은 동작)
  v_axes     int;
  v_opts     text[];
  v_optkey   text;
  v_seen_opt text[] := '{}';
  v_famid    uuid;
  v_fam_new  boolean := false;
  v_ex       record;
begin
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;

  -- ① 모양
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'p_items must be a JSON array of products — nothing was saved';
  end if;
  v_n := jsonb_array_length(p_items);
  if v_n = 0 then
    raise exception 'No products given — nothing was saved';
  end if;
  if v_n > 200 then
    raise exception 'Too many products in one call (% — the limit is 200) — split the paste — nothing was saved', v_n;
  end if;
  if v_fx is not null then                                                                     -- prod-3b: 머리의 막기 · 알리기를 앞에 싣고 축 수 · family id 를 받는다
    v_famid  := (v_fx->>'family_id')::uuid;
    v_axes   := jsonb_array_length(coalesce(v_fx->'option_names', '[]'::jsonb));
    v_blocks := coalesce(v_fx->'head_blocks', '[]'::jsonb);
    v_warns  := coalesce(v_fx->'head_warnings', '[]'::jsonb);
  end if;

  -- ② 막기 · 알리기 — 전부 모은다(첫 막기에서 멈추지 않는다 · 화면이 한 번에 보이게)
  for v_it in select x from jsonb_array_elements(p_items) as x loop
    v_sku  := trim(coalesce(v_it->>'sku', ''));
    v_name := trim(coalesce(v_it->>'name', ''));
    v_brand := null; v_cat := null; v_unit := null;
    v_bcs := '{}'; v_factors := '{}'; v_tiers := '{}'; v_sups := '{}'; v_ndef := 0;
    v_opts := null;
    if v_fx is not null then                                                                   -- prod-3b: 변형 — 머리를 물려받고(묶음 5) 옵션 값 · 이름(판정 183)
      if v_it->>'brand_id' is not null and v_fx->>'brand_id' is not null and v_it->>'brand_id' <> v_fx->>'brand_id' then
        v_warns := v_warns || jsonb_build_object('key', v_sku || ':brand_differs_from_family', 'sku', v_sku, 'code', 'brand_differs_from_family', 'message', format('SKU %s has a different brand from its family %s', v_sku, v_fx->>'family_sku'));
      end if;
      if v_it->>'category_id' is not null and v_fx->>'category_id' is not null and v_it->>'category_id' <> v_fx->>'category_id' then
        v_warns := v_warns || jsonb_build_object('key', v_sku || ':category_differs_from_family', 'sku', v_sku, 'code', 'category_differs_from_family', 'message', format('SKU %s has a different category from its family %s', v_sku, v_fx->>'family_sku'));
      end if;
      v_it := v_it || jsonb_build_object('brand_id', coalesce(v_it->>'brand_id', v_fx->>'brand_id'), 'category_id', coalesce(v_it->>'category_id', v_fx->>'category_id'), 'unit_id', coalesce(v_it->>'unit_id', v_fx->>'unit_id'));
      select coalesce(array_agg(trim(t.x) order by t.o), '{}') into v_opts from jsonb_array_elements_text(coalesce(v_it->'options', '[]'::jsonb)) with ordinality as t(x, o);
      if v_axes = 0 then                                                                       -- 머리가 없거나 비활성(family_unknown)이라 축을 모른다 — 옵션 검사는 머리가 선 뒤에
        v_opts := null;
      elsif cardinality(v_opts) <> v_axes or exists (select 1 from unnest(v_opts) o where o = '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':option_count', 'sku', v_sku, 'code', 'option_count', 'message', format('SKU %s needs %s option value(s) for %s — got %s — nothing was saved', v_sku, v_axes, (select string_agg(n, ' · ') from jsonb_array_elements_text(v_fx->'option_names') n), coalesce(nullif(array_to_string(v_opts, ' / '), ''), 'none')));
        v_opts := null;
      else
        v_optkey := lower(array_to_string(v_opts, '|'));
        if v_optkey = any(v_seen_opt) then
          v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':option_duplicate_in_call', 'sku', v_sku, 'code', 'option_duplicate_in_call', 'message', format('SKU %s repeats the option values %s already used in this paste — nothing was saved', v_sku, array_to_string(v_opts, ' / ')));
        end if;
        v_seen_opt := v_seen_opt || v_optkey;
        if v_famid is not null then
          select p.sku, p.is_active into v_ex from public.product p
           where p.family_id = v_famid and lower(array_to_string((array[trim(p.option1_value), trim(p.option2_value), trim(p.option3_value)])[1:v_axes], '|')) = v_optkey
           order by p.is_active desc, p.sku limit 1;
          if found then
            if v_ex.is_active then
              v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':option_exists', 'sku', v_sku, 'code', 'option_exists', 'message', format('Family %s already has %s as %s — nothing was saved', v_fx->>'family_sku', array_to_string(v_opts, ' / '), v_ex.sku));
            else
              v_warns := v_warns || jsonb_build_object('key', v_sku || ':option_inactive_exists', 'sku', v_sku, 'code', 'option_inactive_exists', 'message', format('Family %s has an inactive variant %s with %s — reactivating it may be the right move', v_fx->>'family_sku', v_ex.sku, array_to_string(v_opts, ' / ')));
            end if;
          end if;
        end if;
        if v_name = '' then
          v_name := (v_fx->>'name') || ' - ' || array_to_string(v_opts, ' - ');                   -- 판정 183 · 축 둘 · 셋은 판정 184 — 같은 규칙을 늘린다(<fam> - V1 - V2( - V3))
        end if;
      end if;
    end if;

    -- SKU
    if v_sku = '' then
      v_blocks := v_blocks || jsonb_build_object('key', '(blank):sku_missing', 'sku', v_sku, 'code', 'sku_missing', 'message', 'A product has no SKU — nothing was saved');
    else
      if v_sku ~ '\s' then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':sku_space', 'sku', v_sku, 'code', 'sku_space', 'message', format('SKU "%s" contains a space — nothing was saved', v_sku));
      end if;
      if v_sku ~ '[a-z]' then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':sku_lowercase', 'sku', v_sku, 'code', 'sku_lowercase', 'message', format('SKU %s has lowercase letters — use capitals — nothing was saved', v_sku));
      end if;
      if exists (select 1 from public.product p where p.sku = v_sku) then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':sku_exists', 'sku', v_sku, 'code', 'sku_exists', 'message', format('SKU %s already exists (active or inactive) — nothing was saved', v_sku));
      end if;
      if v_sku = any(v_seen_sku) then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':sku_duplicate_in_call', 'sku', v_sku, 'code', 'sku_duplicate_in_call', 'message', format('SKU %s appears twice in this paste — nothing was saved', v_sku));
      end if;
      v_seen_sku := v_seen_sku || v_sku;
    end if;
    if v_name = '' and v_fx is null then                                                       -- prod-3b: 변형 이름은 판정 183 으로 짓는다(옵션이 틀리면 option_count 가 이미 막는다)
      v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':name_missing', 'sku', v_sku, 'code', 'name_missing', 'message', format('SKU %s has no name — nothing was saved', v_sku));
    end if;

    -- 브랜드 · 분류 · 단위(id 는 목록에서 고른다 · 판정 143 ①)
    if v_it->>'brand_id' is null then
      if not (v_fx is not null and v_fx->>'mode' = 'new') then                                 -- 판정 185: 새 family 의 머리에 브랜드가 없으면 머리 한 줄만(변형은 물려받아 함께 풀린다) · 변형 더하기는 변형 쪽 그대로
        v_warns := v_warns || jsonb_build_object('key', v_sku || ':brand_missing', 'sku', v_sku, 'code', 'brand_missing', 'message', format('SKU %s has no brand', v_sku));
      end if;
    else
      select * into v_brand from public.ref_brand b where b.id = (v_it->>'brand_id')::uuid and b.is_active;
      if not found then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':brand_unknown', 'sku', v_sku, 'code', 'brand_unknown', 'message', format('SKU %s: the brand does not exist or is inactive — nothing was saved', v_sku));
      else
        -- R1 — 그 브랜드가 이미 쓰는 앞글자(활성 낱개) 집합에 없으면 알림 · 브랜드 상품이 없으면 검사 안 함
        v_prefix := substring(v_sku from '^[A-Z]+');
        if exists (select 1 from public.product p where p.brand_id = v_brand.id and p.is_active and p.parent_product_id is null)
           and not exists (select 1 from public.product p where p.brand_id = v_brand.id and p.is_active and p.parent_product_id is null
                             and substring(p.sku from '^[A-Z]+') is not distinct from v_prefix)
           and not (v_famid is not null and exists (select 1 from public.product p where p.family_id = v_famid and substring(p.sku from '^[A-Z]+') is not distinct from v_prefix)) then   -- prod-3b ⬜4
          v_warns := v_warns || jsonb_build_object('key', v_sku || ':sku_prefix', 'sku', v_sku, 'code', 'sku_prefix',
            'message', format('SKU %s starts with %s but %s products start with %s', v_sku, coalesce(v_prefix, '(no letters)'), v_brand.name,
              (select string_agg(q.pfx, ', ' order by q.n desc, q.pfx) from (select substring(p.sku from '^[A-Z]+') as pfx, count(*) as n from public.product p where p.brand_id = v_brand.id and p.is_active and p.parent_product_id is null group by 1) q)));
        end if;
      end if;
    end if;
    if v_it->>'category_id' is not null then
      select * into v_cat from public.ref_category c where c.id = (v_it->>'category_id')::uuid and c.is_active;
      if not found then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':category_unknown', 'sku', v_sku, 'code', 'category_unknown', 'message', format('SKU %s: the category does not exist or is inactive — nothing was saved', v_sku));
      end if;
    end if;
    if v_it->>'unit_id' is not null then
      select * into v_unit from public.ref_unit u where u.id = (v_it->>'unit_id')::uuid and u.is_active;
      if not found then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':unit_unknown', 'sku', v_sku, 'code', 'unit_unknown', 'message', format('SKU %s: the unit does not exist or is inactive — nothing was saved', v_sku));
      end if;
    end if;

    -- 바코드(낱개) — 빈값 · 같은 호출 중복 · 활성 상품 막기 · 비활성 상품 알리기(판정 179) · R4 · 모양 · R2(낱개만)
    v_r2_seen := false; v_r2_ok := false;
    v_digits := substring(v_sku from '[0-9]+');
    for v_bc in select trim(x) from jsonb_array_elements_text(coalesce(v_it->'barcodes', '[]'::jsonb)) as x loop
      if v_bc = '' then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':barcode_empty', 'sku', v_sku, 'code', 'barcode_empty', 'message', format('SKU %s has an empty barcode — nothing was saved', v_sku));
        continue;
      end if;
      if v_bc = any(v_bcs) or (v_seen_bc ? v_bc) then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':barcode_duplicate_in_call:' || v_bc, 'sku', v_sku, 'code', 'barcode_duplicate_in_call', 'message', format('Barcode %s appears twice in this paste (%s and %s) — nothing was saved', v_bc, coalesce(v_seen_bc->>v_bc, v_sku), v_sku));
      end if;
      v_bcs := v_bcs || v_bc;
      v_seen_bc := v_seen_bc || jsonb_build_object(v_bc, v_sku);
      select p.sku, (p.is_active and pb.is_active) as active into v_owner
        from public.product_barcode pb join public.product p on p.id = pb.product_id
       where pb.barcode = v_bc order by (p.is_active and pb.is_active) desc, p.sku limit 1;
      if found then
        if v_owner.active then
          v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':barcode_active_elsewhere:' || v_bc, 'sku', v_sku, 'code', 'barcode_active_elsewhere', 'message', format('Barcode %s already belongs to active product %s — a scan would pick the wrong product — nothing was saved', v_bc, v_owner.sku));
        else
          v_warns := v_warns || jsonb_build_object('key', v_sku || ':barcode_inactive_elsewhere:' || v_bc, 'sku', v_sku, 'code', 'barcode_inactive_elsewhere', 'message', format('Barcode %s is also on inactive product %s', v_bc, v_owner.sku));
        end if;
      end if;
      if v_bc !~ '^[0-9]+$' or length(v_bc) not in (8, 12, 13, 14) then
        v_warns := v_warns || jsonb_build_object('key', v_sku || ':barcode_shape:' || v_bc, 'sku', v_sku, 'code', 'barcode_shape', 'message', format('Barcode %s is not 8, 12, 13 or 14 digits', v_bc));
      elsif length(v_bc) in (12, 13) then
        if not public.product_gtin_ok(v_bc) then
          v_warns := v_warns || jsonb_build_object('key', v_sku || ':barcode_check_digit:' || v_bc, 'sku', v_sku, 'code', 'barcode_check_digit', 'message', format('Barcode %s fails the check digit — a typo is likely', v_bc));
        end if;
        v_r2_seen := true;
        if v_digits is not null and substr(v_bc, length(v_bc) - 5, 5) = v_digits then
          v_r2_ok := true;
        end if;
      end if;
    end loop;
    if cardinality(v_bcs) = 0 then
      v_warns := v_warns || jsonb_build_object('key', v_sku || ':barcode_missing', 'sku', v_sku, 'code', 'barcode_missing', 'message', format('SKU %s has no barcode — it cannot be scanned in picking, packing or receiving', v_sku));
    elsif v_r2_seen and not v_r2_ok then
      v_warns := v_warns || jsonb_build_object('key', v_sku || ':barcode_digits', 'sku', v_sku, 'code', 'barcode_digits', 'message', format('SKU %s: no 12 or 13 digit barcode ends with %s + check digit', v_sku, coalesce(v_digits, '(no digits in SKU)')));
    end if;

    -- 판매가(낱개) — 티어 sale · 활성 · 중복 · 가격 > 0 · 빠짐 알림
    for v_pr in select x from jsonb_array_elements(coalesce(v_it->'prices', '[]'::jsonb)) as x loop
      select * into v_tier from public.ref_price_tier t where t.id = (v_pr->>'tier_id')::uuid and t.is_active and t.purpose = 'sale';
      if v_pr->>'tier_id' is null or not found then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':tier_invalid', 'sku', v_sku, 'code', 'tier_invalid', 'message', format('SKU %s: a price tier is missing, inactive or not a sale tier — nothing was saved', v_sku));
      elsif v_tier.id = any(v_tiers) then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':tier_duplicate', 'sku', v_sku, 'code', 'tier_duplicate', 'message', format('SKU %s has two prices for tier %s — nothing was saved', v_sku, v_tier.name));
      else
        v_tiers := v_tiers || v_tier.id;
      end if;
      if (v_pr->>'price') is null or (v_pr->>'price')::numeric <= 0 then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':price_not_positive', 'sku', v_sku, 'code', 'price_not_positive', 'message', format('SKU %s: a price must be greater than 0 (leave the tier out for no price) — nothing was saved', v_sku));
      end if;
    end loop;
    if cardinality(v_tiers) = 0 then
      v_warns := v_warns || jsonb_build_object('key', v_sku || ':price_missing', 'sku', v_sku, 'code', 'price_missing', 'message', format('SKU %s has no sale price — order lines will have no price', v_sku));
    end if;

    -- 공급처(낱개) — 있음 · 활성 · 중복 · 통화 · 기본 하나 · 빠짐 알림
    for v_sp in select x from jsonb_array_elements(coalesce(v_it->'suppliers', '[]'::jsonb)) as x loop
      if v_sp->>'supplier_id' is null or not exists (select 1 from public.supplier s where s.id = (v_sp->>'supplier_id')::uuid and s.is_active) then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':supplier_unknown', 'sku', v_sku, 'code', 'supplier_unknown', 'message', format('SKU %s: a supplier is missing, unknown or inactive — nothing was saved', v_sku));
      elsif (v_sp->>'supplier_id')::uuid = any(v_sups) then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':supplier_duplicate', 'sku', v_sku, 'code', 'supplier_duplicate', 'message', format('SKU %s lists the same supplier twice — nothing was saved', v_sku));
      else
        v_sups := v_sups || (v_sp->>'supplier_id')::uuid;
      end if;
      if v_sp->>'currency_id' is not null and not exists (select 1 from public.ref_currency c where c.id = (v_sp->>'currency_id')::uuid and c.is_active) then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':currency_unknown', 'sku', v_sku, 'code', 'currency_unknown', 'message', format('SKU %s: a supplier currency does not exist or is inactive — nothing was saved', v_sku));
      end if;
      if coalesce((v_sp->>'is_default')::boolean, false) then v_ndef := v_ndef + 1; end if;
    end loop;
    if cardinality(v_sups) = 0 then
      v_warns := v_warns || jsonb_build_object('key', v_sku || ':supplier_missing', 'sku', v_sku, 'code', 'supplier_missing', 'message', format('SKU %s has no supplier — it will not appear as a purchase order candidate', v_sku));
    elsif v_ndef > 1 then
      v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':supplier_default_many', 'sku', v_sku, 'code', 'supplier_default_many', 'message', format('SKU %s marks more than one supplier as default — nothing was saved', v_sku));
    end if;

    -- 세트 — 계수만 필수 · SKU 는 창구가 짓는다(판정 177) · 바코드(R4 · 모양 · 판정 179 · R2 는 안 본다) · 고정가 · 할인 %
    v_sets_out := public.product_set_check(jsonb_build_object('sku', v_sku), v_it->'sets', jsonb_build_object('sku', to_jsonb(v_seen_sku), 'bc', v_seen_bc));   -- pset-1: 세트 검사는 도우미 한 곳(product_set_add 와 함께) · v_sets_out 은 여기서 잠깐 빌려 쓴다(넣기 고리에서 다시 채운다)
    v_blocks := v_blocks || (v_sets_out->'blocks');  v_warns := v_warns || (v_sets_out->'warns');
    select coalesce(array_agg(x), '{}') into v_seen_sku from jsonb_array_elements_text(v_sets_out->'seen'->'sku') as x;  v_seen_bc := v_sets_out->'seen'->'bc';
  end loop;

  -- ③ 판정 — 막기 있음 → 저장 안 함 · 검사만 → 반환 · 확인 안 받은 경고 → 저장 안 함(판정 176)
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'items', '[]'::jsonb, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end)
           || case when v_fx is null then '{}'::jsonb else jsonb_build_object('family', jsonb_build_object('id', v_famid, 'sku', v_fx->>'family_sku', 'created', false)) end;
  end if;

  -- ④ 저장 — 낱개 → 바코드 → 가격 → 공급처 → 세트 → 세트 바코드 · 세트 고정가 · 한 트랜잭션(판정 135) · unique 23505 는 문장으로(동시 생성)
  begin
    if v_fx is not null and v_fx->>'mode' = 'new' then                                          -- prod-3b: family 머리 먼저(변형이 family_id 로 문다)
      v_famid := public.product_family_head_insert(v_fx);                                  -- fam-new-1: 머리 insert 는 도우미 한 곳(product_family_from_skus 와 함께)
      v_fam_new := true;
    end if;
    for v_it in select x from jsonb_array_elements(p_items) as x loop
      v_sku  := trim(v_it->>'sku');
      v_name := trim(coalesce(v_it->>'name', ''));
      v_opts := null;
      if v_fx is not null then                                                                 -- prod-3b: 검사 때와 같은 물려받기 · 옵션 · 이름
        v_it := v_it || jsonb_build_object('brand_id', coalesce(v_it->>'brand_id', v_fx->>'brand_id'), 'category_id', coalesce(v_it->>'category_id', v_fx->>'category_id'), 'unit_id', coalesce(v_it->>'unit_id', v_fx->>'unit_id'));
        select coalesce(array_agg(trim(t.x) order by t.o), '{}') into v_opts from jsonb_array_elements_text(coalesce(v_it->'options', '[]'::jsonb)) with ordinality as t(x, o);
        if v_name = '' then
          v_name := (v_fx->>'name') || ' - ' || array_to_string(v_opts, ' - ');
        end if;
      end if;
      select * into v_brand from public.ref_brand    where id = (v_it->>'brand_id')::uuid;
      select * into v_cat   from public.ref_category where id = (v_it->>'category_id')::uuid;
      select * into v_unit  from public.ref_unit     where id = (v_it->>'unit_id')::uuid;
      insert into public.product (sku, name, source, note, brand_id, brand_name, category_id, category_name, unit_id, uom_name, weight, weight_unit, registered_on, family_id, option1_value, option2_value, option3_value)
      values (v_sku, v_name, 'manual', nullif(trim(v_it->>'note'), ''), v_brand.id, v_brand.name, v_cat.id, v_cat.name, v_unit.id, v_unit.name,
              (v_it->>'weight')::numeric, nullif(trim(v_it->>'weight_unit'), ''), public.ims_today(), v_famid, v_opts[1], v_opts[2], v_opts[3])
      returning id into v_pid;
      v_i := 0;
      for v_bc in select trim(x) from jsonb_array_elements_text(coalesce(v_it->'barcodes', '[]'::jsonb)) as x loop
        v_i := v_i + 1;
        insert into public.product_barcode (product_id, barcode, is_primary, source) values (v_pid, v_bc, v_i = 1, 'manual');
      end loop;
      for v_pr in select x from jsonb_array_elements(coalesce(v_it->'prices', '[]'::jsonb)) as x loop
        insert into public.product_price (product_id, tier_id, price, source, price_set_by, updated_by)
        values (v_pid, (v_pr->>'tier_id')::uuid, (v_pr->>'price')::numeric, 'manual', v_staff, v_staff);
      end loop;
      v_i := jsonb_array_length(coalesce(v_it->'suppliers', '[]'::jsonb));
      for v_sp in select x from jsonb_array_elements(coalesce(v_it->'suppliers', '[]'::jsonb)) as x loop
        insert into public.product_supplier (product_id, supplier_id, supplier_sku, cost, fixed_cost, currency_id, is_default, source)
        values (v_pid, (v_sp->>'supplier_id')::uuid, nullif(trim(v_sp->>'supplier_sku'), ''), (v_sp->>'cost')::numeric, (v_sp->>'fixed_cost')::numeric,
                (v_sp->>'currency_id')::uuid, coalesce((v_sp->>'is_default')::boolean, v_i = 1), 'manual');   -- 공급처가 하나면 기본(⬜7 안)
      end loop;
      v_sets_out := (public.product_set_insert(jsonb_build_object('sku', v_sku, 'name', v_name, 'product_id', v_pid, 'brand_id', v_brand.id, 'brand_name', v_brand.name, 'category_id', v_cat.id, 'category_name', v_cat.name), v_it->'sets', v_staff))->'sets';   -- pset-1: 세트 넣기는 도우미 한 곳 · 세트 sellable false(판정 586)
      v_items := v_items || jsonb_build_object('sku', v_sku, 'product_id', v_pid, 'sets', v_sets_out);
    end loop;
  exception when unique_violation then
    raise exception 'Someone just created one of these SKUs or barcodes (%) — check again — nothing was saved', coalesce(sqlerrm, '');
  end;

  return jsonb_build_object('committed', true, 'items', v_items, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb)
         || case when v_fx is null then '{}'::jsonb else jsonb_build_object('family', jsonb_build_object('id', v_famid, 'sku', v_fx->>'family_sku', 'created', v_fam_new)) end;
end;
$function$;
-- ═══ ② 새 창구 ═══
create function public.product_family_from_skus(p_family jsonb, p_items jsonb, p_commit boolean default false, p_ack text[] default '{}'::text[]) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $function$
-- fam-new-1 판정 652 · 653 B: 있는 낱개 SKU 들로 새 family 를 만든다(머리 = p_family · 구성원 = p_items[{sku, options[]}] 1 개 이상 · 200 이하)
--   머리 검사 = product_family_head_ctx(판정 182 머리 SKU · 축 이름 · 190 대소문자 · 185 브랜드 없음) · 비운 brand_id · category_id · unit_id 는 첫 SKU 의 값
--   구성원 검사 = family_join 과 같은 식 · 다른 family 에 있으면 moves_from_family 경고(ack) · 옛 family 가 비면 old_family_emptied 경고(ack · 머리는 그대로)
--   저장 = 머리 insert(product_family_head_insert) + product.family_id · option1~3_value update(옛 family 에서 빠진다 = family_leave 와 같은 효과)
declare
  v_f        jsonb := coalesce(p_family, '{}'::jsonb);
  v_ctx      jsonb;
  v_famsku   text;  v_key text;  v_famid uuid;
  v_axes     int := 0;
  v_blocks   jsonb := '[]'::jsonb;  v_warns jsonb := '[]'::jsonb;  v_items jsonb := '[]'::jsonb;
  v_it       jsonb;  v_sku text;  v_ikey text;  p public.product%rowtype;  v_first public.product%rowtype;
  v_opts     text[];  v_optkey text;
  v_seen     uuid[] := '{}';  v_seenopt text[] := '{}';
  v_old      public.product_family%rowtype;  v_oldfams uuid[] := '{}';  v_moved uuid[] := '{}';  v_left int;
  v_keys     text[];  v_unacked text[];
  v_n        int;  v_i int := 0;
begin
  perform public.ims_require_write('master', 'saved');                                        -- ⭐ 유일한 문 — 첫 줄(판정 140 · product_family_create 와 같다)
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'p_items must be a JSON array of {sku, options[]} — nothing was saved';
  end if;
  if jsonb_typeof(v_f) <> 'object' then
    raise exception 'p_family must be a JSON object — nothing was saved';
  end if;
  v_n := jsonb_array_length(p_items);
  if v_n = 0 then
    raise exception 'No SKUs given — a family needs at least one member — nothing was saved';
  end if;
  if v_n > 200 then
    raise exception 'Too many SKUs in one call (% — the limit is 200) — split the paste — nothing was saved', v_n;
  end if;
  if v_f ? 'id' then
    raise exception 'This window makes a new family from existing SKUs — to add SKUs to an existing family use Add member (family_join) — nothing was saved';
  end if;
  -- 비운 머리 칸은 첫 SKU 의 값으로(첫 SKU 가 없으면 그대로 — 머리 검사가 brand_missing 을 낸다)
  select * into v_first from public.product x where x.sku = trim(coalesce(p_items->0->>'sku', ''));
  if v_first.id is not null then
    if nullif(v_f->>'brand_id', '') is null and v_first.brand_id is not null then v_f := v_f || jsonb_build_object('brand_id', v_first.brand_id); end if;
    if nullif(v_f->>'category_id', '') is null and v_first.category_id is not null then v_f := v_f || jsonb_build_object('category_id', v_first.category_id); end if;
    if nullif(v_f->>'unit_id', '') is null and v_first.unit_id is not null then v_f := v_f || jsonb_build_object('unit_id', v_first.unit_id); end if;
  end if;

  -- ① 머리 — 검사 한 곳
  v_ctx    := public.product_family_head_ctx(v_f, p_items);
  v_famsku := v_ctx->>'family_sku';  v_key := v_ctx->>'key';
  v_blocks := v_ctx->'head_blocks';  v_warns := v_ctx->'head_warnings';
  v_axes   := jsonb_array_length(coalesce(v_ctx->'option_names', '[]'::jsonb));

  -- ② 구성원 — family_join 과 같은 검사 · 653 옮기기 경고
  for v_it in select x from jsonb_array_elements(p_items) as x loop
    v_i := v_i + 1;
    v_sku := trim(coalesce(v_it->>'sku', ''));
    v_ikey := case when v_sku = '' then '(sku ' || v_i || ')' else v_sku end;
    p := null;
    if v_sku = '' then
      v_blocks := v_blocks || jsonb_build_object('key', v_ikey || ':sku_missing', 'sku', v_sku, 'code', 'sku_missing', 'message', format('Line %s has no SKU — nothing was saved', v_i));
      continue;
    end if;
    select * into p from public.product x where x.sku = v_sku;
    if p.id is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_ikey || ':sku_unknown', 'sku', v_sku, 'code', 'sku_unknown', 'message', format('SKU %s does not exist — nothing was saved', v_sku));
      continue;
    end if;
    if not p.is_active then
      v_blocks := v_blocks || jsonb_build_object('key', v_ikey || ':sku_inactive', 'sku', v_sku, 'code', 'sku_inactive', 'message', format('SKU %s is inactive — switch it on first or leave it out — nothing was saved', v_sku));
      continue;
    end if;
    if p.parent_product_id is not null then
      v_blocks := v_blocks || jsonb_build_object('key', v_ikey || ':set_not_family_member', 'sku', v_sku, 'code', 'set_not_family_member', 'message', format('SKU %s is a set — sets follow their single and are not family members — nothing was saved', v_sku));
      continue;
    end if;
    if p.id = any(v_seen) then
      v_blocks := v_blocks || jsonb_build_object('key', v_ikey || ':field_duplicate_in_call:family', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s is listed twice — nothing was saved', v_sku));
      continue;
    end if;
    v_seen := v_seen || p.id;
    select coalesce(array_agg(trim(t.x) order by t.o), '{}') into v_opts from jsonb_array_elements_text(coalesce(v_it->'options', '[]'::jsonb)) with ordinality as t(x, o);
    if v_axes > 0 then                                                                       -- 축을 모르면(머리가 막혔다) 옵션 검사는 머리가 선 뒤에(product_create_core 와 같다)
      if cardinality(v_opts) <> v_axes or exists (select 1 from unnest(v_opts) o where o = '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_ikey || ':option_count', 'sku', v_sku, 'code', 'option_count', 'message', format('SKU %s needs %s option value(s) for family %s — got %s — nothing was saved', v_sku, v_axes, v_famsku, coalesce(nullif(array_to_string(v_opts, ' / '), ''), '(none)')));
      else
        v_optkey := lower(array_to_string(v_opts, '|'));
        if v_optkey = any(v_seenopt) then
          v_blocks := v_blocks || jsonb_build_object('key', v_ikey || ':option_duplicate_in_call', 'sku', v_sku, 'code', 'option_duplicate_in_call', 'message', format('SKU %s repeats the option values %s already used in this paste for family %s — nothing was saved', v_sku, array_to_string(v_opts, ' / '), v_famsku));
        end if;
        v_seenopt := v_seenopt || v_optkey;
      end if;
    end if;
    if (v_ctx->>'brand_id') is not null and p.brand_id is distinct from (v_ctx->>'brand_id')::uuid then
      v_warns := v_warns || jsonb_build_object('key', v_ikey || ':brand_differs_from_family', 'sku', v_sku, 'code', 'brand_differs_from_family', 'message', format('SKU %s has a different brand from its family %s', v_sku, v_famsku));
    end if;
    if p.family_id is not null then                                                          -- 판정 653 B: 다른 family 에 있으면 옮긴다 — 경고(ack)
      select * into v_old from public.product_family f where f.id = p.family_id;
      v_warns := v_warns || jsonb_build_object('key', v_ikey || ':moves_from_family:' || coalesce(v_old.sku, ''), 'sku', v_sku, 'code', 'moves_from_family',
                                               'message', format('%s will move out of %s (%s) into %s', v_sku, coalesce(v_old.name, '?'), coalesce(v_old.sku, '?'), v_famsku), 'from_family_sku', v_old.sku, 'from_family_name', v_old.name);
      if not (p.family_id = any(v_oldfams)) then v_oldfams := v_oldfams || p.family_id; end if;
      v_moved := v_moved || p.id;
    end if;
    v_items := v_items || jsonb_build_object('sku', v_sku, 'product_id', p.id, 'options', to_jsonb(v_opts), 'moves_from_family', (select f.sku from public.product_family f where f.id = p.family_id));
  end loop;
  -- 옛 family 가 그로써 비면(구성원 0) — 경고(ack) · 머리는 그대로 둔다(지금 family_leave 도 마지막 구성원을 막지 않는다)
  for v_old in select f.* from public.product_family f where f.id = any(v_oldfams) order by f.sku loop
    select count(*) into v_left from public.product x where x.family_id = v_old.id and not (x.id = any(v_moved));
    if v_left = 0 then
      v_warns := v_warns || jsonb_build_object('key', v_old.sku || ':old_family_emptied', 'sku', v_old.sku, 'code', 'old_family_emptied',
                                               'message', format('Family %s (%s) will have no variants left — its head stays as an empty family (switch it off in Families if it is no longer used)', v_old.sku, v_old.name));
    end if;
  end loop;

  -- ③ 판정 — 막기 있음 → 저장 안 함 · 검사만 → 반환 · 확인 안 받은 경고 → 저장 안 함(판정 176 · product_create_core 와 같은 꼴)
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'items', v_items, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end,
                              'family', jsonb_build_object('id', null, 'sku', v_famsku, 'created', false));
  end if;

  -- ④ 저장 — 머리 → 구성원(옛 family 에서 빠지고 새 family 로 · 옵션 값) · 한 트랜잭션
  begin
    v_famid := public.product_family_head_insert(v_ctx);
    for v_it in select x from jsonb_array_elements(v_items) as x loop
      select coalesce(array_agg(t.x order by t.o), '{}') into v_opts from jsonb_array_elements_text(v_it->'options') with ordinality as t(x, o);
      update public.product set family_id = v_famid, option1_value = v_opts[1], option2_value = v_opts[2], option3_value = v_opts[3] where id = (v_it->>'product_id')::uuid;
    end loop;
  exception when unique_violation then
    raise exception 'Someone just created family SKU % — check again — nothing was saved', v_famsku;
  end;
  return jsonb_build_object('committed', true, 'items', v_items, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb,
                            'family', jsonb_build_object('id', v_famid, 'sku', v_famsku, 'created', true));
end
$function$;
revoke all on function public.product_family_from_skus(jsonb, jsonb, boolean, text[]) from public, anon, service_role;
grant execute on function public.product_family_from_skus(jsonb, jsonb, boolean, text[]) to authenticated;
comment on function public.product_family_from_skus(jsonb, jsonb, boolean, text[]) is 'fam-new-1 판정 652 · 653 — 있는 낱개 SKU 들로 새 family(머리 p_family{name, sku?, brand_id?, category_id?, unit_id?, option1_name, option2_name?, option3_name?, note?} · 구성원 p_items[{sku, options[]}]) · master · 검사 → p_commit · p_ack 확인 → 저장(반환 꼴 = product_family_create) · 다른 family 의 SKU 는 옮긴다(경고 moves_from_family · 옛 family 가 비면 old_family_emptied · 둘 다 ack)';

-- ═══ 착지 ═══
do $$
begin
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_family_create', 'product_create_core'))
     <> 'product_create_core=d780181b80545e88cac30fcf77d88a34 product_family_create=e95121e18705b7eddd1980ac005f0eeb' then raise exception 'fam-new-1 landing check failed: bodies'; end if;
  if (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('product_family_head_ctx', 'product_family_head_insert', 'product_family_from_skus', 'product_family_create', 'product_create_core'))
     <> 'product_create_core={postgres=X/postgres,service_role=X/postgres} product_family_create={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} product_family_from_skus={postgres=X/postgres,authenticated=X/postgres} product_family_head_ctx={postgres=X/postgres} product_family_head_insert={postgres=X/postgres}'
     then raise exception 'fam-new-1 landing check failed: acl'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_family_head_ctx', 'product_family_head_insert', 'product_family_from_skus', 'product_family_create', 'product_create_core')) <> 5 then
    raise exception 'fam-new-1 landing check failed: overloads'; end if;
  if not ((select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_family_create') ~ 'public\.product_family_head_ctx\('
          and (select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create_core') ~ 'public\.product_family_head_insert\(') then
    raise exception 'fam-new-1 landing check failed: callers'; end if;
end $$;
