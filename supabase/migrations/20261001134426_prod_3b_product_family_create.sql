-- prod-3b — family 창구: 새 family + 변형 함께 만들기 · 있는 family 에 변형 더하기 (2026-10-01 · 판정 181 ~ 183 · 134 ~ 146 · 176 ~ 180 · so-module §31-a · po-module §3-h)
--   판정 181  두 길을 같은 창구로 — 머리를 새로 주면 「새 family + 변형」 · 있는 family 를 가리키면 「변형 더하기」 · 변형마다 세트 · 바코드 · 가격 · 공급처는 prod-3 와 같은 규칙 · 같은 검사 · 한 트랜잭션 · 막기 하나면 family 도 변형도 저장 안 함
--   판정 182  family SKU 를 비워 두면 <첫 변형 SKU>FAM · 넣으면 그대로 · FAM 으로 끝나지 않으면 · 공백 · 소문자 막기
--   판정 183  변형 이름을 비워 두면 <family 이름> - <옵션 값>(띄고 · 띄고) · 변형의 세트 이름은 판정 180 그대로 <변형 이름>-<계수>
--   판정 184  축 둘 · 셋도 같은 규칙을 늘린다 — <family 이름> - <V1> - <V2>( - <V3>) · 넣으면 그대로(실물 2축 이름은 15 가지 넘게 흩어져 1 위도 3 분의 1 이 안 된다 · 규칙 하나가 예측 가능)
--   판정 185  새 family 의 머리에 브랜드가 없으면 머리 한 줄(<family SKU>:brand_missing)만 알린다 · 변형 쪽은 접는다(원인이 머리 하나 · 머리에 넣으면 변형이 물려받아 함께 풀린다) · 변형 더하기(있는 family)에서 그 family 에 브랜드가 없으면 변형 쪽 경고를 그대로 둔다(머리 경고가 없으니 접으면 사라진다)
--   묶음 2    검사 규칙은 한 곳 — product_create 의 검사 · 저장 몸통을 속 함수 product_create_core 로 떼어 두 창구가 같이 쓴다 · product_create 는 문 + 속 함수 호출로 다시 낸다(겉모양 · 동작 그대로 · 검증 R 절이 jsonb 등호로 증명)
--   묶음 5    변형이 브랜드 · 분류 · 단위를 비워 두면 머리 것 · 넣었는데 머리와 다르면 알리기(brand_differs_from_family · category_differs_from_family)
--   묶음 6    막기 — family_name_missing · family_sku_suffix · family_sku_space · family_sku_lowercase · family_sku_exists(product_family · product 양쪽) · option_names_missing · option_names_gap · family_unknown(없거나 비활성) · family_head_ambiguous(id 와 머리 칸이 함께)
--             no_variants(변형 하나도 없는 새 family · ⬜5 안) · 변형 쪽 option_count(축 수 ≠ 값 수 · 빈 값) · option_duplicate_in_call · option_exists(같은 조합의 활성 변형 · 대소문자 · 앞뒤 공백 접어 비교 · ⬜3)
--   알리기    option_name_unusual(지금 활성 family 가 쓰는 축 이름에 없다 · 글자 그대로 비교 · ⬜2) · option_inactive_exists(같은 조합의 비활성 변형 · 되살리기가 맞을 수 있다 · ⬜3) · brand_missing(머리)
--   ⬜4       변형 더하기 때 R1 앞글자 기준에 그 family 의 변형 앞글자도 넣는다
--   열쇠      머리는 <family SKU>:<code>(SKU 가 비면 (family):<code>) · 변형은 prod-3 그대로 <SKU>:<code>(바코드 것은 :<barcode>)
--   반환      prod-3 모양 + family {id, sku, created} (product_create 의 반환에는 family 가 붙지 않는다)
--   속 함수   product_create_core(p_items, p_family_ctx, p_commit, p_ack) — definer · 문 없음(문은 겉 창구 둘) · execute 는 public · anon · authenticated 에서 회수(판정 31 선례) · 옮긴 줄은 20261001130106 의 product_create 본문 그대로 · 더한 줄은 「prod-3b」 표시
--   검증: ~/asung/prompts/prod-3b-verify.sql (시험 적용 장치 · 테스트 DB · rollback · R 절 = 재발행 증명)
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

-- ═══ A) 속 함수 — 검사 · 저장 몸통(20261001130106 product_create 본문 + prod-3b 줄) · 문 없음 · 직접 못 부른다 ═══════════════════════
create or replace function public.product_create_core(p_items jsonb, p_family_ctx jsonb, p_commit boolean, p_ack text[])
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
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
    for v_st in select x from jsonb_array_elements(coalesce(v_it->'sets', '[]'::jsonb)) as x loop
      v_factor := (v_st->>'pack_factor')::numeric;
      if v_factor is null or v_factor < 2 or v_factor <> trunc(v_factor) then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':set_factor_invalid', 'sku', v_sku, 'code', 'set_factor_invalid', 'message', format('SKU %s: a set needs a whole-number pack factor of 2 or more (got %s) — nothing was saved', v_sku, coalesce(v_st->>'pack_factor', 'nothing')));
        continue;
      end if;
      v_setsku := v_sku || '-' || v_factor::int::text;
      if v_factor = any(v_factors) then
        v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':set_factor_duplicate', 'sku', v_setsku, 'code', 'set_factor_duplicate', 'message', format('SKU %s has two sets with pack factor %s — nothing was saved', v_sku, v_factor::int));
        continue;                                                                             -- 같은 사실을 sku_duplicate_in_call 로 또 적지 않는다
      end if;
      v_factors := v_factors || v_factor;
      if exists (select 1 from public.product p where p.sku = v_setsku) then
        v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':set_sku_exists', 'sku', v_setsku, 'code', 'set_sku_exists', 'message', format('Set SKU %s already exists — nothing was saved', v_setsku));
      end if;
      if v_setsku = any(v_seen_sku) then
        v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':sku_duplicate_in_call', 'sku', v_setsku, 'code', 'sku_duplicate_in_call', 'message', format('SKU %s appears twice in this paste — nothing was saved', v_setsku));
      end if;
      v_seen_sku := v_seen_sku || v_setsku;
      if (v_st->>'set_discount_pct') is not null and ((v_st->>'set_discount_pct')::numeric < 0 or (v_st->>'set_discount_pct')::numeric > 100) then
        v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':set_discount_invalid', 'sku', v_setsku, 'code', 'set_discount_invalid', 'message', format('Set %s: the set discount must be between 0 and 100 — nothing was saved', v_setsku));
      end if;
      if not exists (select 1 from public.ref_unit u where u.name = v_factor::int::text and u.is_active) then
        v_warns := v_warns || jsonb_build_object('key', v_setsku || ':set_unit_unknown', 'sku', v_setsku, 'code', 'set_unit_unknown', 'message', format('Set %s: there is no unit named %s — the set is saved with uom %s but no unit id', v_setsku, v_factor::int, v_factor::int));
      end if;
      v_bcs := '{}';
      for v_bc in select trim(x) from jsonb_array_elements_text(coalesce(v_st->'barcodes', '[]'::jsonb)) as x loop
        if v_bc = '' then
          v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':barcode_empty', 'sku', v_setsku, 'code', 'barcode_empty', 'message', format('Set %s has an empty barcode — nothing was saved', v_setsku));
          continue;
        end if;
        if v_bc = any(v_bcs) or (v_seen_bc ? v_bc) then
          v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':barcode_duplicate_in_call:' || v_bc, 'sku', v_setsku, 'code', 'barcode_duplicate_in_call', 'message', format('Barcode %s appears twice in this paste (%s and %s) — nothing was saved', v_bc, coalesce(v_seen_bc->>v_bc, v_setsku), v_setsku));
        end if;
        v_bcs := v_bcs || v_bc;
        v_seen_bc := v_seen_bc || jsonb_build_object(v_bc, v_setsku);
        select p.sku, (p.is_active and pb.is_active) as active into v_owner
          from public.product_barcode pb join public.product p on p.id = pb.product_id
         where pb.barcode = v_bc order by (p.is_active and pb.is_active) desc, p.sku limit 1;
        if found then
          if v_owner.active then
            v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':barcode_active_elsewhere:' || v_bc, 'sku', v_setsku, 'code', 'barcode_active_elsewhere', 'message', format('Barcode %s already belongs to active product %s — a scan would pick the wrong product — nothing was saved', v_bc, v_owner.sku));
          else
            v_warns := v_warns || jsonb_build_object('key', v_setsku || ':barcode_inactive_elsewhere:' || v_bc, 'sku', v_setsku, 'code', 'barcode_inactive_elsewhere', 'message', format('Barcode %s is also on inactive product %s', v_bc, v_owner.sku));
          end if;
        end if;
        if v_bc !~ '^[0-9]+$' or length(v_bc) not in (8, 12, 13, 14) then
          v_warns := v_warns || jsonb_build_object('key', v_setsku || ':barcode_shape:' || v_bc, 'sku', v_setsku, 'code', 'barcode_shape', 'message', format('Barcode %s is not 8, 12, 13 or 14 digits', v_bc));
        elsif length(v_bc) in (12, 13) and not public.product_gtin_ok(v_bc) then
          v_warns := v_warns || jsonb_build_object('key', v_setsku || ':barcode_check_digit:' || v_bc, 'sku', v_setsku, 'code', 'barcode_check_digit', 'message', format('Barcode %s fails the check digit — a typo is likely', v_bc));
        end if;
      end loop;
      v_tiers := '{}';
      for v_pr in select x from jsonb_array_elements(coalesce(v_st->'prices', '[]'::jsonb)) as x loop
        select * into v_tier from public.ref_price_tier t where t.id = (v_pr->>'tier_id')::uuid and t.is_active and t.purpose = 'sale';
        if v_pr->>'tier_id' is null or not found then
          v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':tier_invalid', 'sku', v_setsku, 'code', 'tier_invalid', 'message', format('Set %s: a price tier is missing, inactive or not a sale tier — nothing was saved', v_setsku));
        elsif v_tier.id = any(v_tiers) then
          v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':tier_duplicate', 'sku', v_setsku, 'code', 'tier_duplicate', 'message', format('Set %s has two prices for tier %s — nothing was saved', v_setsku, v_tier.name));
        else
          v_tiers := v_tiers || v_tier.id;
        end if;
        if (v_pr->>'price') is null or (v_pr->>'price')::numeric <= 0 then
          v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':price_not_positive', 'sku', v_setsku, 'code', 'price_not_positive', 'message', format('Set %s: a fixed price must be greater than 0 (leave it out to use the calculated set price) — nothing was saved', v_setsku));
        end if;
      end loop;
    end loop;
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
      insert into public.product_family (sku, name, source, note, brand_id, brand_name, category_id, category_name, unit_id, uom_name, option1_name, option2_name, option3_name)
      values (v_fx->>'family_sku', v_fx->>'name', 'manual', nullif(trim(v_fx->>'note'), ''),
              (v_fx->>'brand_id')::uuid,    (select b.name from public.ref_brand b    where b.id = (v_fx->>'brand_id')::uuid),
              (v_fx->>'category_id')::uuid, (select c.name from public.ref_category c where c.id = (v_fx->>'category_id')::uuid),
              (v_fx->>'unit_id')::uuid,     (select u.name from public.ref_unit u     where u.id = (v_fx->>'unit_id')::uuid),
              v_fx->'option_names'->>0, v_fx->'option_names'->>1, v_fx->'option_names'->>2)
      returning id into v_famid;
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
      v_sets_out := '[]'::jsonb;
      for v_st in select x from jsonb_array_elements(coalesce(v_it->'sets', '[]'::jsonb)) as x loop
        v_factor  := (v_st->>'pack_factor')::numeric;
        v_setsku  := v_sku || '-' || v_factor::int::text;
        v_setname := coalesce(nullif(trim(v_st->>'name'), ''), v_name || '-' || v_factor::int::text);                     -- 판정 180 — 사람이 안 넣으면 <낱개 이름>-<계수>(붙여 · 2026 등록의 96%) · 넣으면 그대로 · 변형은 지은 이름 위에(판정 183)
        select * into v_setunit from public.ref_unit u where u.name = v_factor::int::text and u.is_active;
        insert into public.product (sku, name, source, parent_product_id, pack_factor, set_discount_pct, brand_id, brand_name, category_id, category_name, unit_id, uom_name, registered_on)
        values (v_setsku, v_setname, 'manual', v_pid, v_factor, (v_st->>'set_discount_pct')::numeric, v_brand.id, v_brand.name, v_cat.id, v_cat.name, v_setunit.id, v_factor::int::text, public.ims_today())
        returning id into v_sid;
        v_i := 0;
        for v_bc in select trim(x) from jsonb_array_elements_text(coalesce(v_st->'barcodes', '[]'::jsonb)) as x loop
          v_i := v_i + 1;
          insert into public.product_barcode (product_id, barcode, is_primary, source) values (v_sid, v_bc, v_i = 1, 'manual');
        end loop;
        for v_pr in select x from jsonb_array_elements(coalesce(v_st->'prices', '[]'::jsonb)) as x loop
          insert into public.product_price (product_id, tier_id, price, source, price_set_by, updated_by)
          values (v_sid, (v_pr->>'tier_id')::uuid, (v_pr->>'price')::numeric, 'manual', v_staff, v_staff);
        end loop;
        v_sets_out := v_sets_out || jsonb_build_object('sku', v_setsku, 'pack_factor', v_factor, 'product_id', v_sid);
      end loop;
      v_items := v_items || jsonb_build_object('sku', v_sku, 'product_id', v_pid, 'sets', v_sets_out);
    end loop;
  exception when unique_violation then
    raise exception 'Someone just created one of these SKUs or barcodes (%) — check again — nothing was saved', coalesce(sqlerrm, '');
  end;

  return jsonb_build_object('committed', true, 'items', v_items, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb)
         || case when v_fx is null then '{}'::jsonb else jsonb_build_object('family', jsonb_build_object('id', v_famid, 'sku', v_fx->>'family_sku', 'created', v_fam_new)) end;
end;
$$;
revoke all on function public.product_create_core(jsonb, jsonb, boolean, text[]) from public, anon, authenticated;
comment on function public.product_create_core(jsonb, jsonb, boolean, text[]) is
  '⭐ 상품 만들기의 몸통(prod-3b 묶음 2 · 2026-10-01) — product_create(p_family_ctx null · prod-3 와 같은 동작)와 product_family_create(p_family_ctx = {mode new|existing, family_id, family_sku, name, brand_id, category_id, unit_id, option_names[], note, head_blocks[], head_warnings[]})가 같이 쓴다. 문(ims_require_write)은 겉 창구 둘에 · 이 함수는 execute 회수(직접 못 부른다 · 판정 31 선례). 검사 · 알리기 · 저장 규칙은 product_create 의 comment 와 20261001130106 머리 그대로 + 변형 규칙(옵션 값 수 · 같은 조합 · 머리 물려받기 · 이름 판정 183 · R1 에 family 변형 앞글자). mode new 면 저장 때 product_family 행을 먼저 넣고 변형이 family_id 로 문다';

-- ═══ B) product_create 재발행 — 시그니처 · grant · comment 그대로 · 문 + 속 함수 ═══════════════════════════════════════════
create or replace function public.product_create(p_items jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
begin
  perform public.ims_require_write('master', 'saved');                                        -- ⭐ 유일한 문 — 첫 줄(판정 140)
  return public.product_create_core(p_items, null, p_commit, p_ack);
end;
$$;

-- ═══ C) family 창구 — 머리 검사(막기 6 · 판정 182 · 알리기 7) → 속 함수(변형 규칙 · 저장) ═══════════════════════════════════
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
revoke all on function public.product_family_create(jsonb, jsonb, boolean, text[]) from public, anon;
grant execute on function public.product_family_create(jsonb, jsonb, boolean, text[]) to authenticated;
comment on function public.product_family_create(jsonb, jsonb, boolean, text[]) is
  '⭐ family 창구(판정 181 ~ 183 · 2026-10-01 prod-3b) — security definer · 첫 줄 ims_require_write(master). 두 길: p_family = {id} 면 있는 family 에 변형 더하기(머리 칸이 함께 오면 family_head_ambiguous) · p_family = {sku?, name, brand_id, category_id, unit_id, option1_name, option2_name?, option3_name?, note?} 면 새 family + 변형. p_items = 변형 배열(prod-3 의 낱개 모양 + options[] = 축 순서의 값 · 최대 200) · 변형마다 바코드 · 가격 · 공급처 · 세트는 product_create 와 같은 규칙(속 함수 하나 · 묶음 2). family SKU 를 비우면 <첫 변형 SKU>FAM(판정 182) · 변형 이름을 비우면 <family 이름> - <옵션 값>(판정 183 · 축 여럿은 값을 '' - '' 로) · 브랜드 · 분류 · 단위를 비우면 머리 것(다르면 알리기). 검사만(p_commit false) → 저장(p_commit true + p_ack) 두 번 부르기 · 저장 직전 재검사(판정 176) · 막기 하나면 family 도 변형도 저장 안 함. 반환 = product_create 모양 + family {id, sku, created}. 막기 · 알리기 code 는 파일 머리';
