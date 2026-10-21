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

-- ═══ pset-1 — 이미 있는 낱개에 세트를 더하는 창구 product_set_add · 세트 규칙을 도우미 둘로(한 곳) · 세트 판매 기본 false(판정 586) · 손으로 만든 세트 7 개 고침(판정 585) (2026-10-21 · 판정 585 ~ 589 · pset-0 조사 · 정본 so-module §47 · po-module 1383 ~ 1386 뒤) ═══
--   계기: Caleb 「신제품을 만들때는 셋을 만들 수가 있는데, 나중에 추가하려니까 못찾겠네」 — 세트를 만드는 길은 product_create 의 sets 배열(새 낱개와 함께)뿐이었다.
--   결함(pset-0 이견 1): product_create_core 의 세트 insert 가 sellable 칸을 보내지 않아 칸 기본 true 가 들어갔다 — 트리거 product_sellable_default 는 명시 null 일 때만 종류 기본(세트 false)을 넣는다(판정 291) ⇒ 10-06 뒤 만든 세트 7 개가 「따로 파는 세트」가 됐다.
--   ① 도우미 product_set_check · product_set_insert — core 의 세트 검사 고리(253 ~ 319 행) · 넣기 고리(376 ~ 395 행)를 바이트 그대로 옮기고(바뀐 줄은 머리 주석에) 두 창구가 함께 쓴다 · 문 없음 · authenticated 실행 불가.
--   ② product_create_core 재발행 — 두 고리를 도우미 호출로(검사 3 줄 · 넣기 1 줄) · 그 밖의 줄 0 · 동작 차이는 둘뿐: 세트 sellable true → false(판정 586) · 같은 SKU 세트가 꺼진 채 있으면 set_sku_exists → set_sku_inactive_exists + existing_product_id(판정 587 · 두 경로 모두).
--   ③ product_set_add(p_parent_id, p_sets, p_commit, p_ack) — 첫 줄 ims_require_write('master') · 부모: 없음 · 꺼짐 · 세트 · 콤보 부모는 막기 · 단종 · 판매 안 함은 경고(ack · 판정 588) · 같은 계수의 다른 SKU 세트(AMP41108-12 가 계수 6 인 꼴)도 막기(set_factor_exists) ·
--      세트 칸 = pack_factor · barcodes · set_discount_pct · name · prices 를 보내면 막기 set_prices_not_here(판정 589 — 고정가는 Edit 에서만) · 반환은 product_create 꼴 + 세트마다 name · sellable false · scan_adds(판정 586 · 미리 보기에도).
--   ④ 데이터(판정 585): AS85203-72 · AS85203-6 · TBR43447-6 · TBR00182-12 · TBR16260-6 · TBR63096-6 · TBR39231-12 → sellable false · sellable_source 'ims'(사람의 결정 · 미룬 113 의 적재 고침이 ims 행을 건너뛰게 될 때를 대비) · 7 개가 정확히 「manual · 세트 · sellable true · sellable_source null · Shopify listing 0」 이 아니면 멈춘다.
--   ⚠️ 운영에는 닿지 않는다(가드) · 화면(Add set 창 · New product 창의 기본 글)은 대화 Claude 차수.

-- ═══ 무접촉 증거 — product_create · product_update 의 몸 md5 · 이 일곱 밖 세트의 sellable 집계 ═══
create temp table pset1_before as
select (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create') as md5_create,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_update') as md5_update,
       (select count(*) from public.product x where x.parent_product_id is not null and x.sellable
           and x.sku not in ('AS85203-72', 'AS85203-6', 'TBR43447-6', 'TBR00182-12', 'TBR16260-6', 'TBR63096-6', 'TBR39231-12')) as other_sets_sellable,
       (select count(*) from public.product x where x.parent_product_id is null and x.sellable) as singles_sellable,
       (select count(*) from public.shop_push_queue) as push_q, (select count(*) from public.shop_stock_queue) as stock_q;

-- ═══ 도우미 ① product_set_check — product_create_core 의 세트 검사 고리(원본 prod-3b 본문 253 ~ 319 행 바이트 그대로) + 판정 587 · 문 없음 · authenticated 실행 불가(겉 창구가 문을 든다) ═══
create function public.product_set_check(p_parent jsonb, p_sets jsonb, p_seen jsonb) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_sku      text    := p_parent->>'sku';
  v_blocks   jsonb   := '[]'::jsonb;
  v_warns    jsonb   := '[]'::jsonb;
  v_seen_sku text[]  := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_seen->'sku', '[]'::jsonb)) as x), '{}');
  v_seen_bc  jsonb   := coalesce(p_seen->'bc', '{}'::jsonb);
  v_factors  numeric[] := '{}';
  v_bcs      text[];
  v_tiers    uuid[];
  v_st       jsonb;
  v_bc       text;
  v_pr       jsonb;
  v_factor   numeric;
  v_setsku   text;
  v_tier     public.ref_price_tier%rowtype;
  v_owner    record;
  v_ex       record;
begin
    for v_st in select x from jsonb_array_elements(coalesce(p_sets, '[]'::jsonb)) as x loop
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
      select p.id, p.is_active into v_ex from public.product p where p.sku = v_setsku;                                        -- pset-1(판정 587): 같은 SKU 가 꺼진 채 있으면 다시 만들지 않고 Edit 로 안내
      if found and v_ex.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':set_sku_exists', 'sku', v_setsku, 'code', 'set_sku_exists', 'message', format('Set SKU %s already exists — nothing was saved', v_setsku));
      elsif found then
        v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':set_sku_inactive_exists', 'sku', v_setsku, 'code', 'set_sku_inactive_exists', 'existing_product_id', v_ex.id, 'message', format('Set SKU %s already exists but is inactive — open it in Products and switch Active on in Edit instead of making it again — nothing was saved', v_setsku));
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
  return jsonb_build_object('blocks', v_blocks, 'warns', v_warns, 'seen', jsonb_build_object('sku', to_jsonb(v_seen_sku), 'bc', v_seen_bc));
end $$;
revoke all on function public.product_set_check(jsonb, jsonb, jsonb) from public, anon, authenticated;
comment on function public.product_set_check(jsonb, jsonb, jsonb) is 'pset-1(2026-10-21 · 판정 177 · 179 · 587) — 세트 묶음의 검사(계수 · SKU · 바코드 · 할인 · 고정가 티어) · product_create_core 와 product_set_add 가 함께 쓴다 · p_parent {sku} · p_seen {sku:[…], bc:{…}}(같은 호출에서 먼저 본 SKU · 바코드) → {blocks, warns, seen} · 같은 SKU 가 꺼진 채 있으면 set_sku_inactive_exists + existing_product_id(판정 587 · 두 경로 모두) · 문 없음 — 겉 창구가 든다';

-- ═══ 도우미 ② product_set_insert — product_create_core 의 세트 넣기 고리(원본 prod-3b 본문 376 ~ 395 행 바이트 그대로) + sellable false 명시(판정 586) + detail · 문 없음 · authenticated 실행 불가 ═══
create function public.product_set_insert(p_parent jsonb, p_sets jsonb, p_staff uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_sku      text := p_parent->>'sku';
  v_name     text := p_parent->>'name';
  v_pid      uuid := (p_parent->>'product_id')::uuid;
  v_staff    uuid := p_staff;
  v_brand    public.ref_brand%rowtype;
  v_cat      public.ref_category%rowtype;
  v_setunit  public.ref_unit%rowtype;
  v_sets_out jsonb;
  v_detail   jsonb := '[]'::jsonb;
  v_st       jsonb;
  v_bc       text;
  v_pr       jsonb;
  v_factor   numeric;
  v_setsku   text;
  v_setname  text;
  v_sid      uuid;
  v_i        int;
begin
  v_brand.id := (p_parent->>'brand_id')::uuid;  v_brand.name := p_parent->>'brand_name';
  v_cat.id   := (p_parent->>'category_id')::uuid;  v_cat.name := p_parent->>'category_name';
      v_sets_out := '[]'::jsonb;
      for v_st in select x from jsonb_array_elements(coalesce(p_sets, '[]'::jsonb)) as x loop
        v_factor  := (v_st->>'pack_factor')::numeric;
        v_setsku  := v_sku || '-' || v_factor::int::text;
        v_setname := coalesce(nullif(trim(v_st->>'name'), ''), v_name || '-' || v_factor::int::text);                     -- 판정 180 — 사람이 안 넣으면 <낱개 이름>-<계수>(붙여 · 2026 등록의 96%) · 넣으면 그대로 · 변형은 지은 이름 위에(판정 183)
        select * into v_setunit from public.ref_unit u where u.name = v_factor::int::text and u.is_active;
        insert into public.product (sku, name, source, parent_product_id, pack_factor, set_discount_pct, brand_id, brand_name, category_id, category_name, unit_id, uom_name, registered_on, sellable)
        values (v_setsku, v_setname, 'manual', v_pid, v_factor, (v_st->>'set_discount_pct')::numeric, v_brand.id, v_brand.name, v_cat.id, v_cat.name, v_setunit.id, v_factor::int::text, public.ims_today(), false)   -- pset-1(판정 586 · 291): 세트는 따로 팔지 않는다 — 명시 false(칸 기본 true 가 트리거의 종류 기본을 가렸다)
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
        v_detail := v_detail || jsonb_build_object('sku', v_setsku, 'name', v_setname, 'pack_factor', v_factor, 'product_id', v_sid, 'sellable', false, 'scan_adds', v_sku || ' × ' || v_factor::int::text,   -- pset-1(판정 586): 화면이 그릴 재료
                                                  'set_discount_pct', (v_st->>'set_discount_pct')::numeric, 'barcodes', coalesce(v_st->'barcodes', '[]'::jsonb));
      end loop;
  return jsonb_build_object('sets', v_sets_out, 'detail', v_detail);
end $$;
revoke all on function public.product_set_insert(jsonb, jsonb, uuid) from public, anon, authenticated;
comment on function public.product_set_insert(jsonb, jsonb, uuid) is 'pset-1(2026-10-21 · 판정 177 · 180 · 586) — 세트 묶음을 넣는다(product · 바코드 · 고정가) · product_create_core 와 product_set_add 가 함께 쓴다 · p_parent {sku, name, product_id, brand_id, brand_name, category_id, category_name} → {sets:[{sku, pack_factor, product_id}](product_create 의 옛 모양 그대로), detail:[+ name · sellable false · scan_adds · set_discount_pct · barcodes]} · 세트는 sellable false 명시(판정 586 · 291) · sellable_source 는 null(IMS 기본) · 문 없음 — 겉 창구가 든다';

-- ═══ product_create_core 재발행 — 원본 20261001134426_prod_3b_product_family_create.sql:47 바이트 + 세트 검사 고리(253 ~ 319 행) → product_set_check 호출 3 줄 · 세트 넣기 고리(376 ~ 395 행) → product_set_insert 호출 1 줄 · 그 밖의 줄 0 · ACL · 머리 그대로 ═══
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

-- ═══ ③ product_set_add — 이미 있는 낱개에 세트를 더한다 ═══
create function public.product_set_add(p_parent_id uuid, p_sets jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_p       public.product%rowtype;
  v_blocks  jsonb := '[]'::jsonb;
  v_warns   jsonb := '[]'::jsonb;
  v_preview jsonb := '[]'::jsonb;
  v_chk     jsonb;
  v_ins     jsonb;
  v_st      jsonb;
  v_factor  numeric;
  v_setsku  text;
  v_key     text;
  v_ex      record;
  v_keys    text[];
  v_unacked text[];
begin
  perform public.ims_require_write('master', 'saved');                                         -- ⭐ 유일한 문 — 첫 줄(product_create 와 같음 · 판정 140)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if p_sets is null or jsonb_typeof(p_sets) <> 'array' or jsonb_array_length(p_sets) = 0 then
    raise exception 'p_sets must be a JSON array of sets like [{"pack_factor": 6, "barcodes": [], "set_discount_pct": null, "name": null}] — nothing was saved';
  end if;
  if jsonb_array_length(p_sets) > 20 then raise exception 'Too many sets in one call (% — the limit is 20) — nothing was saved', jsonb_array_length(p_sets); end if;
  select * into v_p from public.product p where p.id = p_parent_id;
  v_key := coalesce(v_p.sku, coalesce(p_parent_id::text, '(none)'));
  -- 부모 — 막기 넷 · 경고 둘(판정 588)
  if v_p.id is null then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'sku', v_key, 'code', 'parent_unknown', 'message', 'The product to add sets to was not found — nothing was saved');
  elsif not v_p.is_active then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_inactive', 'sku', v_p.sku, 'code', 'parent_inactive', 'message', format('SKU %s is inactive — switch it on in Edit before adding sets — nothing was saved', v_p.sku));
  elsif v_p.parent_product_id is not null then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_is_set', 'sku', v_p.sku, 'code', 'parent_is_set', 'message', format('SKU %s is itself a set — sets are added to the single unit, not to a set — nothing was saved', v_p.sku));
  elsif exists (select 1 from public.product_bom b where b.parent_product_id = v_p.id and b.is_active) then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_is_combo', 'sku', v_p.sku, 'code', 'parent_is_combo', 'message', format('SKU %s is a combo — a combo has no stock of its own, so it cannot have sets — nothing was saved', v_p.sku));
  else
    if v_p.is_discontinued then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':parent_discontinued', 'sku', v_p.sku, 'code', 'parent_discontinued', 'message', format('SKU %s is discontinued — the new set(s) can still be scanned, but check that is what you want', v_p.sku));
    end if;
    if not v_p.sellable then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':parent_not_sellable', 'sku', v_p.sku, 'code', 'parent_not_sellable', 'message', format('SKU %s is not for sale — a scan of the new set(s) adds the single × pack, which orders will refuse until Sellable is switched on', v_p.sku));
    end if;
  end if;
  -- 세트마다 — 고정가는 여기서 안 받는다(판정 589) · 같은 계수의 다른 SKU 세트(옛 Cin7 세트 꼴) · 미리 보기 재료(판정 586)
  for v_st in select x from jsonb_array_elements(p_sets) as x loop
    v_factor := case when (v_st->>'pack_factor') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (v_st->>'pack_factor')::numeric end;
    v_setsku := case when v_factor is not null and v_factor >= 2 and v_factor = trunc(v_factor) then coalesce(v_p.sku, '?') || '-' || v_factor::int::text end;
    if v_st ? 'prices' then
      v_blocks := v_blocks || jsonb_build_object('key', coalesce(v_setsku, v_key) || ':set_prices_not_here', 'sku', coalesce(v_setsku, v_key), 'code', 'set_prices_not_here', 'message', format('Set %s: a fixed set price is set later in Edit — leave prices out here (the set price is calculated from the single) — nothing was saved', coalesce(v_setsku, v_key)));
    end if;
    if v_setsku is not null and v_p.id is not null then
      select x.sku, x.id, x.is_active into v_ex from public.product x where x.parent_product_id = v_p.id and x.pack_factor = v_factor and x.sku <> v_setsku order by x.is_active desc, x.sku limit 1;
      if found then
        v_blocks := v_blocks || jsonb_build_object('key', v_setsku || ':set_factor_exists', 'sku', v_setsku, 'code', 'set_factor_exists', 'existing_product_id', v_ex.id, 'existing_sku', v_ex.sku,
                                                    'message', format('SKU %s already has a set of %s (%s%s) — open that set in Products instead of making another — nothing was saved', v_p.sku, v_factor::int, v_ex.sku, case when v_ex.is_active then '' else ', inactive' end));
      end if;
    end if;
    v_preview := v_preview || jsonb_build_object('sku', v_setsku, 'name', case when v_setsku is null then null else coalesce(nullif(trim(v_st->>'name'), ''), v_p.name || '-' || v_factor::int::text) end,
                                                 'pack_factor', v_factor, 'barcodes', coalesce(v_st->'barcodes', '[]'::jsonb), 'set_discount_pct', nullif(v_st->>'set_discount_pct', '')::numeric,
                                                 'sellable', false, 'scan_adds', case when v_setsku is null then null else v_p.sku || ' × ' || v_factor::int::text end);
  end loop;
  if v_p.id is not null then
    v_chk := public.product_set_check(jsonb_build_object('sku', v_p.sku), p_sets, '{}'::jsonb);
    v_blocks := v_blocks || (v_chk->'blocks');  v_warns := v_warns || (v_chk->'warns');
  end if;
  -- 판정 — product_create 와 같다(판정 176): 막기 있음 → 저장 안 함 · 검사만 → 반환 · 확인 안 받은 경고 → 저장 안 함
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'items', jsonb_build_array(jsonb_build_object('sku', v_p.sku, 'product_id', v_p.id, 'sets', v_preview)), 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;
  begin
    v_ins := public.product_set_insert(jsonb_build_object('sku', v_p.sku, 'name', v_p.name, 'product_id', v_p.id, 'brand_id', v_p.brand_id, 'brand_name', v_p.brand_name, 'category_id', v_p.category_id, 'category_name', v_p.category_name), p_sets, v_staff);
  exception when unique_violation then
    raise exception 'Someone just created one of these SKUs or barcodes (%) — check again — nothing was saved', coalesce(sqlerrm, '');
  end;
  return jsonb_build_object('committed', true, 'items', jsonb_build_array(jsonb_build_object('sku', v_p.sku, 'product_id', v_p.id, 'sets', v_ins->'detail')), 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end $$;
revoke all on function public.product_set_add(uuid, jsonb, boolean, text[]) from public, anon;
grant execute on function public.product_set_add(uuid, jsonb, boolean, text[]) to authenticated;
comment on function public.product_set_add(uuid, jsonb, boolean, text[]) is
  'pset-1(2026-10-21 · 판정 585 ~ 589) — 이미 있는 낱개에 세트를 더한다 · p_sets [{pack_factor, barcodes[], set_discount_pct, name}](고정가는 Edit 에서만 · prices 를 보내면 set_prices_not_here) · 문 = master 쓰기(product_create 와 같음) · 부모 없음 · 꺼짐 · 세트 · 콤보 부모는 막기 · 단종 · 판매 안 함은 경고(ack · 판정 588) · 같은 SKU 가 꺼진 채 있으면 set_sku_inactive_exists + existing_product_id(판정 587) · 같은 계수의 다른 SKU 세트는 set_factor_exists + existing_product_id · existing_sku · 새 세트는 sellable false(판정 586 · 스캔 · 붙여넣기는 낱개 × 계수로) · 반환 {committed, items:[{sku, product_id, sets:[{sku, name, pack_factor, product_id, sellable:false, scan_adds, set_discount_pct, barcodes}]}], blocks, warnings, unacked} · 미리 보기(p_commit false)에도 지을 세트 SKU · 이름 · scan_adds 가 나온다 · 검사 · 넣기는 product_set_check · product_set_insert(product_create 와 한 곳)';

-- ═══ ④ 데이터 — 손으로 만든 세트 7 개를 판매 안 함으로(판정 585) ═══
do $$
declare v_n int; v_list text;
begin
  select count(*), string_agg(x.sku, ', ' order by x.sku) into v_n, v_list from public.product x
   where x.parent_product_id is not null and x.source = 'manual' and x.sellable;
  if v_n <> 7 or v_list <> 'AS85203-6, AS85203-72, TBR00182-12, TBR16260-6, TBR39231-12, TBR43447-6, TBR63096-6' then
    raise exception 'pset-1 (판정 585): expected exactly the 7 hand-made sets with sellable true, found % (%) — nothing was changed', v_n, coalesce(v_list, '-');
  end if;
  select count(*) into v_n from public.product x where x.sku in ('AS85203-72', 'AS85203-6', 'TBR43447-6', 'TBR00182-12', 'TBR16260-6', 'TBR63096-6', 'TBR39231-12')
     and (x.sellable_source is not null or exists (select 1 from public.shop_listing l where l.product_id = x.id));
  if v_n <> 0 then raise exception 'pset-1 (판정 585): % of the 7 sets have sellable_source set or a Shopify listing — look first — nothing was changed', v_n; end if;
  update public.product set sellable = false, sellable_source = 'ims'
   where sku in ('AS85203-72', 'AS85203-6', 'TBR43447-6', 'TBR00182-12', 'TBR16260-6', 'TBR63096-6', 'TBR39231-12');
  get diagnostics v_n = row_count;
  if v_n <> 7 then raise exception 'pset-1 (판정 585): updated % rows, expected 7 — nothing was changed', v_n; end if;
end $$;

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int; v_b record;
begin
  select * into v_b from pset1_before;
  if to_regprocedure('public.product_set_check(jsonb, jsonb, jsonb)') is null or to_regprocedure('public.product_set_insert(jsonb, jsonb, uuid)') is null
     or to_regprocedure('public.product_set_add(uuid, jsonb, boolean, text[])') is null then v_bad := v_bad || ' functions_missing'; end if;
  if has_function_privilege('authenticated', 'public.product_set_check(jsonb, jsonb, jsonb)', 'execute') or has_function_privilege('anon', 'public.product_set_check(jsonb, jsonb, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.product_set_insert(jsonb, jsonb, uuid)', 'execute') or has_function_privilege('anon', 'public.product_set_insert(jsonb, jsonb, uuid)', 'execute') then v_bad := v_bad || ' helper_acl'; end if;
  if not has_function_privilege('authenticated', 'public.product_set_add(uuid, jsonb, boolean, text[])', 'execute') or has_function_privilege('anon', 'public.product_set_add(uuid, jsonb, boolean, text[])', 'execute') then v_bad := v_bad || ' set_add_acl'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.proconfig::text ~ 'search_path=public, pg_temp' and p.proname in ('product_set_check', 'product_set_insert', 'product_set_add', 'product_create_core');
  if v_n <> 4 then v_bad := v_bad || format(' definer_%s_of_4', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create_core' and md5(p.prosrc) = '8775929fdf788611336976badf41a4c6'
     and p.prosrc ~ 'public\.product_set_check\(' and p.prosrc ~ 'public\.product_set_insert\(' and p.prosrc !~ 'insert into public\.product \(sku, name, source, parent_product_id'
     and coalesce(p.proacl::text, '-') = '{postgres=X/postgres,service_role=X/postgres}';
  if v_n <> 1 then v_bad := v_bad || ' core_body_or_acl'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create') is distinct from v_b.md5_create
     or (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_update') is distinct from v_b.md5_update then v_bad := v_bad || ' create_or_update_changed'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_set_check', 'product_set_insert')
     and p.prosrc ~ 'set_sku_exists' and p.prosrc ~ 'set_sku_inactive_exists' and p.prosrc ~ 'existing_product_id';
  if v_n <> 1 then v_bad := v_bad || format(' check_587_%s_of_1', v_n); end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_set_insert' and p.prosrc ~ 'registered_on, sellable\)' and p.prosrc ~ 'public\.ims_today\(\), false\)') <> 1 then v_bad := v_bad || ' insert_586'; end if;
  select count(*) into v_n from public.product x where x.sku in ('AS85203-72', 'AS85203-6', 'TBR43447-6', 'TBR00182-12', 'TBR16260-6', 'TBR63096-6', 'TBR39231-12') and not x.sellable and x.sellable_source = 'ims';
  if v_n <> 7 then v_bad := v_bad || format(' seven_fixed_%s_of_7', v_n); end if;
  select count(*) into v_n from public.product x where x.parent_product_id is not null and x.sellable
     and x.sku not in ('AS85203-72', 'AS85203-6', 'TBR43447-6', 'TBR00182-12', 'TBR16260-6', 'TBR63096-6', 'TBR39231-12');
  if v_n <> v_b.other_sets_sellable then v_bad := v_bad || format(' other_sets_sellable_%s_vs_%s', v_n, v_b.other_sets_sellable); end if;
  select count(*) into v_n from public.product x where x.parent_product_id is null and x.sellable;
  if v_n <> v_b.singles_sellable then v_bad := v_bad || format(' singles_sellable_%s_vs_%s', v_n, v_b.singles_sellable); end if;
  if (select count(*) from public.shop_push_queue) <> v_b.push_q or (select count(*) from public.shop_stock_queue) <> v_b.stock_q then v_bad := v_bad || ' shop_queues_grew(the 7 have no listing — nothing should be queued)'; end if;
  if v_bad <> '' then raise exception 'pset-1 landing check failed:%', v_bad; end if;
end $$;
drop table pset1_before;
