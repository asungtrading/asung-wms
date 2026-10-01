-- prod-3 — 상품 만들기 한 벌 창구 product_create (2026-10-01 · 판정 134 ~ 146 · 176 ~ 179 · so-module §31-a · po-module §3-h)
--   판정 135  한 벌 창구 하나 — 낱개 + 바코드 + 판매가 + 공급처 + 세트를 한 트랜잭션 · 막기가 하나라도 있으면 아무것도 저장하지 않는다
--   판정 140  security definer + 첫 줄 ims_require_write('master') — prod-2 가 여덟 표의 직접 쓰기를 닫았으므로 이 창구가 유일한 만들기 길
--   판정 143  brand_name · category_name · uom_name 은 id 의 이름을 복사 · cin7_ 칸 · 회계 계정 · 세금 규칙 · costing_method 는 비운다 · source 'manual'(판정 133) · registered_on = ims_today()
--   판정 146  낱개 여럿을 한 번에(p_items 배열 · 최대 200) · 각 낱개 안에 세트 목록 · family 는 받지 않는다(prod-3b)
--   판정 176  미리 보기 → 경고 → 확인은 서버가 지킨다 — 같은 창구를 두 번(p_commit false = 검사만 · true = 저장) · 저장 직전에 다시 검사해 확인(p_ack)받지 않은 경고 열쇠가 하나라도 있으면 저장하지 않는다(unacked)
--   판정 177  세트 SKU 는 창구가 짓는다 — <낱개 SKU>-<계수> · 단위도 계수 이름(ref_unit 에 그 이름이 있으면 id 까지) · 사람은 계수만
--   판정 178  낱개의 바코드 · 판매가 · 공급처 빠짐은 알리기(막지 않는다)
--   판정 180  세트 이름을 사람이 비워 두면 <낱개 이름>-<계수>(공백 없이 · 예 PRD3 clean item-6 · 2026 등록 세트의 96% 가 이 모양) · 넣으면 그대로
--   판정 179  넣은 바코드가 활성 상품에 이미 있으면 막기 · 비활성 상품에만 있으면 알리기 · 지금 있는 행은 건드리지 않는다
--   막기(code)  sku_missing · sku_space · sku_lowercase · sku_exists · sku_duplicate_in_call · name_missing · brand_unknown · category_unknown · unit_unknown
--               barcode_empty · barcode_duplicate_in_call · barcode_active_elsewhere · tier_invalid · tier_duplicate · price_not_positive
--               supplier_unknown · supplier_duplicate · supplier_default_many · currency_unknown · set_factor_invalid · set_factor_duplicate · set_sku_exists · set_discount_invalid
--   알리기(code) sku_prefix(R1) · barcode_digits(R2 · 낱개만) · barcode_check_digit(R4 · 12 · 13자리) · barcode_shape(숫자 아님 · 길이 8 · 12 · 13 · 14 밖 · ⬜2) · barcode_missing · price_missing · supplier_missing(판정 178)
--               barcode_inactive_elsewhere(판정 179) · brand_missing · set_unit_unknown(계수 이름의 ref_unit 이 없다)
--   경고 열쇠 = <SKU>:<code> · 바코드에 붙는 것은 <SKU>:<code>:<barcode>(한 상품에 바코드가 여럿이라 열쇠가 겹치지 않게)
--   동시 생성 — 검사와 저장 사이에 남이 같은 SKU · 바코드를 만들면 unique 23505 를 받아 문장으로 바꿔 raise(전부 되돌아간다)
--   반환 { committed, items:[{sku, product_id, sets:[{sku, pack_factor, product_id}]}], blocks:[{key, sku, code, message}], warnings:[…], unacked:[key…] }
--   검증: ~/asung/prompts/prod-3-verify.sql (시험 적용 장치 · 테스트 DB · rollback)
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

-- ═══ A) GTIN 체크 디짓(R4) — 8 · 12 · 13 · 14 자리 숫자만 판정 · 그 밖은 null(판정 안 함) ═══════════════════════════════
create or replace function public.product_gtin_ok(p_barcode text) returns boolean
  language sql immutable
  set search_path = public, pg_temp
as $$
  select case
           when p_barcode !~ '^[0-9]{8}$' and p_barcode !~ '^[0-9]{12,14}$' then null
           else (select (10 - (sum(t.d::int * case when (t.n % 2) = 1 then 3 else 1 end) % 10)) % 10
                   from unnest(string_to_array(reverse(left(p_barcode, length(p_barcode) - 1)), null)) with ordinality as t(d, n))
                = right(p_barcode, 1)::int
         end;
$$;
comment on function public.product_gtin_ok(text) is 'GTIN mod 10 체크 디짓(R4 · 판정 138-4) — 8 · 12 · 13 · 14 자리 숫자면 true/false · 그 밖은 null(판정 안 함). 오른쪽 자료 자리부터 3 · 1 · 3 … · Caleb 예 075724199125 · 8809640737251 = true';
revoke all on function public.product_gtin_ok(text) from public, anon;
grant execute on function public.product_gtin_ok(text) to authenticated;

-- ═══ B) 만들기 창구 ═══════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function public.product_create(p_items jsonb, p_commit boolean default false, p_ack text[] default '{}')
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
begin
  perform public.ims_require_write('master', 'saved');                                        -- ⭐ 유일한 문 — 첫 줄(판정 140)
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

  -- ② 막기 · 알리기 — 전부 모은다(첫 막기에서 멈추지 않는다 · 화면이 한 번에 보이게)
  for v_it in select x from jsonb_array_elements(p_items) as x loop
    v_sku  := trim(coalesce(v_it->>'sku', ''));
    v_name := trim(coalesce(v_it->>'name', ''));
    v_brand := null; v_cat := null; v_unit := null;
    v_bcs := '{}'; v_factors := '{}'; v_tiers := '{}'; v_sups := '{}'; v_ndef := 0;

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
    if v_name = '' then
      v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':name_missing', 'sku', v_sku, 'code', 'name_missing', 'message', format('SKU %s has no name — nothing was saved', v_sku));
    end if;

    -- 브랜드 · 분류 · 단위(id 는 목록에서 고른다 · 판정 143 ①)
    if v_it->>'brand_id' is null then
      v_warns := v_warns || jsonb_build_object('key', v_sku || ':brand_missing', 'sku', v_sku, 'code', 'brand_missing', 'message', format('SKU %s has no brand', v_sku));
    else
      select * into v_brand from public.ref_brand b where b.id = (v_it->>'brand_id')::uuid and b.is_active;
      if not found then
        v_blocks := v_blocks || jsonb_build_object('key', v_sku || ':brand_unknown', 'sku', v_sku, 'code', 'brand_unknown', 'message', format('SKU %s: the brand does not exist or is inactive — nothing was saved', v_sku));
      else
        -- R1 — 그 브랜드가 이미 쓰는 앞글자(활성 낱개) 집합에 없으면 알림 · 브랜드 상품이 없으면 검사 안 함
        v_prefix := substring(v_sku from '^[A-Z]+');
        if exists (select 1 from public.product p where p.brand_id = v_brand.id and p.is_active and p.parent_product_id is null)
           and not exists (select 1 from public.product p where p.brand_id = v_brand.id and p.is_active and p.parent_product_id is null
                             and substring(p.sku from '^[A-Z]+') is not distinct from v_prefix) then
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
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ④ 저장 — 낱개 → 바코드 → 가격 → 공급처 → 세트 → 세트 바코드 · 세트 고정가 · 한 트랜잭션(판정 135) · unique 23505 는 문장으로(동시 생성)
  begin
    for v_it in select x from jsonb_array_elements(p_items) as x loop
      v_sku  := trim(v_it->>'sku');
      select * into v_brand from public.ref_brand    where id = (v_it->>'brand_id')::uuid;
      select * into v_cat   from public.ref_category where id = (v_it->>'category_id')::uuid;
      select * into v_unit  from public.ref_unit     where id = (v_it->>'unit_id')::uuid;
      insert into public.product (sku, name, source, note, brand_id, brand_name, category_id, category_name, unit_id, uom_name, weight, weight_unit, registered_on)
      values (v_sku, trim(v_it->>'name'), 'manual', nullif(trim(v_it->>'note'), ''), v_brand.id, v_brand.name, v_cat.id, v_cat.name, v_unit.id, v_unit.name,
              (v_it->>'weight')::numeric, nullif(trim(v_it->>'weight_unit'), ''), public.ims_today())
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
        v_setname := coalesce(nullif(trim(v_st->>'name'), ''), trim(v_it->>'name') || '-' || v_factor::int::text);        -- 판정 180 — 사람이 안 넣으면 <낱개 이름>-<계수>(붙여 · 2026 등록의 96%) · 넣으면 그대로
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

  return jsonb_build_object('committed', true, 'items', v_items, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.product_create(jsonb, boolean, text[]) from public, anon;
grant execute on function public.product_create(jsonb, boolean, text[]) to authenticated;
comment on function public.product_create(jsonb, boolean, text[]) is
  '⭐ 상품 만들기 한 벌 창구(판정 134 · 135 · 146 · 176 ~ 179 · 2026-10-01 prod-3) — security definer · 첫 줄 ims_require_write(master)(판정 140 · prod-2 로 여덟 표의 직접 쓰기가 닫혀 이 창구가 유일한 길). p_items = 낱개 배열(최대 200) · 낱개 {sku, name, brand_id, category_id, unit_id, barcodes[], prices[{tier_id, price}], suppliers[{supplier_id, supplier_sku, cost, fixed_cost, currency_id, is_default}], weight, weight_unit, note, sets[{pack_factor, name?, barcodes[], prices[], set_discount_pct}]}. p_commit false = 검사만(저장 0) · true = 저장 — 저장 직전에 다시 검사해 p_ack 에 없는 경고 열쇠가 하나라도 있으면 committed false + unacked(판정 176). 막기가 하나라도 있으면 아무것도 저장하지 않는다(판정 135 · raise 가 아니라 blocks 로 돌려 화면이 한 번에 보인다). 세트 SKU = <낱개>-<계수> · 단위 = 계수 이름(판정 177) · 이름 칸 셋은 id 의 이름 복사 · cin7_ 칸 · 계정 · 세금 · costing 비움 · source manual · registered_on ims_today(판정 143 · 133). 경고 열쇠 <SKU>:<code>(바코드 것은 :<barcode> 까지). 동시 생성의 23505 는 문장으로 raise(전부 되돌아간다). 막기 · 알리기 code 목록은 파일 머리';
