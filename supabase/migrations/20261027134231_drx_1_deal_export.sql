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
-- 20261027134231_drx_1_deal_export.sql — drx-1 (2026-10-27 · 회사 PC · Caleb 지시서 ~/asung/prompts/drx-1.md)
--   Caleb 「Discount Rules 에서 두 가지 CSV」(판정 790 ~ 792 짐작 번호 · 문서 차수가 정한다):
--     ⓐ deal_rule    — 규칙 정의: 딜 줄(대상 + %) 하나 = 한 줄(762) · 줄 없는 딜(오더 딜 · 줄 없음)도 한 줄 · 꺼진 줄도 낸다(Line on 칸 · 판정 342 · 이견 8)
--                      딜 머리 칸(이름 · 종류 · 상태 · 기간 · 쿠폰 · 손님 조건 글자 · 오더 단계 글자)은 줄마다 되풀이 · 제외 대상은 같은 줄의 Except 칸(이견 7)
--     ⓑ deal_product — 풀린 제품: (규칙 × 제품 × 줄) 한 줄(이견 1 · 같은 제품이 두 줄에 걸리면 두 줄 — UOM 식 수량 단계가 살아야 한다) · 대상 식은 so_deal_products_all 한 곳(판정 361)
--                      켜진 줄만 · 활성 제품만(이견 5 가 · Active 칸 없음) · 세트는 낱개를 거쳐 함께(판정 302 · 이견 6 · Kind · Set of · Pack factor 칸) · 고른 규칙이 꺼졌든 끝났든 그대로 + Status 칸(이견 9) · 오더 딜은 0 줄
--                      ⚠️ 「Rule %」 = 그 규칙의 % — 오더에서 손님 기본 할인 · 다른 규칙과 겨루는 셈(greatest)은 넣지 않는다(손님마다 다르다) · 손님 조건은 「Customer rules」 Yes/No 한 칸(내용은 ⓐ 에만)
--     가격 칸(판정 792) — sale 등급마다 List · After rule %(이견 3 · compare 등급은 오더가 쓰지 않는다 · reference 는 760) · 고르면 나온다(기본 꺼짐)
--     ⭐⭐ 할인가 셈 = so_line_quote 의 가격 식(이견 2) — so_price_for 는 set_calc 세트 정가에 set_discount_pct 를 미리 넣어 Price check(so_quote_preview → so_line_quote)와 어긋난다 · so_quote_preview 를 줄마다 부르면 36,745 회 ≈ 5 분(실측)
--        ⚠️⚠️ so_line_quote 의 가격 식을 고치면 deal_export 도 같이 고친다 · 검증 supabase/tests/drx_1_check.sql 의 so_quote_preview 대조(Q 갈래)가 그 증명이다 — 아래 머리 do 블록이 so_line_quote 의 DB md5 를 dsc-2 원본과 대조한다
--        할인가 = round(list × (1 − greatest(줄 %, set_calc 면 set_discount_pct)/100), 4) — 오더 단가는 자르지 않고(판정 3 · 284) Price check 화면은 4 자리
--   창구 하나 deal_export(p_deal_ids, p_kind, p_columns) — 규칙 상세(id 하나) · 규칙 목록(지금 보이는 규칙 전부)이 같은 창구(판정 791) · definer · stable · 반환 {kind, total, row_count, truncated, columns, rows} · 한도 20,000(exp-1 과 같다)
--   문(이견 11) = so_deal_list 와 같은 식 — sales 보기 ∨ master 쓰기(「그 규칙을 화면에서 볼 수 있는 사람」 = 화면을 채우는 창구가 허락하는 사람) · 원가 칸 없음(759) · 가격 칸 gate all(product 의 price_* 와 같다)
--   재발행 셋(더한 줄만 · create or replace 라 ACL 보존): export_catalog(exp-3 20261026180000 본문 바이트 + deal 칸 + sale 등급 갈래 둘) · export_door(+2 갈래) · export_columns(+2 kind · 거부 문장의 이름)
--   무접촉: export_pick · export_gate_ok · product_export · customer_export · supplier_export · so_deal_* · so_line_quote · so_quote_preview · 표 · 정책 · 시퀀스 0 · 화면(discount-rules.html 단추 둘 · ims-export.js kind 둘은 대화 Claude)
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 supabase/tests/drx_1_check.sql(-v mig)
--   실측(테스트 DB 2026-10-27 · 켜진 줄 딜 11): ⓑ 7,349 줄(활성 6,309) · 가격 10 칸 켜고 0.9 s · 3.2 MB · ⓐ 55 줄 · authenticated statement_timeout 8 s


-- ═══ 0) 착지 전 확인 — 재발행 원본이 DB 에 그대로 있나(바뀌었으면 이 파일의 「더한 줄만」 전제가 깨진다) · 세 kind 의 칸 목록을 끝 확인용으로 담아 둔다 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'export_catalog') is distinct from 'bf108de21d64b2fb8e4ae93ed7c87c06' then v_bad := v_bad || ' export_catalog_not_exp_3'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'export_door')    is distinct from 'e87f7f39c77b6272648d1254c8d57914' then v_bad := v_bad || ' export_door_not_exp_1'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'export_columns') is distinct from '35e6bfea5eedf468d5d8c29a6ecaa317' then v_bad := v_bad || ' export_columns_not_exp_1'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_line_quote')  is distinct from '84366f59d10e4f140bda924e40beec4f' then v_bad := v_bad || ' so_line_quote_not_dsc_2(price formula copied below may be stale)'; end if;
  if to_regprocedure('public.so_deal_products_all(uuid[])') is null or to_regprocedure('public.export_pick(text, text[])') is null or to_regprocedure('public.ims_today()') is null then v_bad := v_bad || ' prerequisites'; end if;
  if to_regprocedure('public.deal_export(uuid[], text, text[])') is not null then v_bad := v_bad || ' deal_export_already_there'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM790', message = format('STOP - drx-1 needs%s - nothing was changed', v_bad); end if;
end $$;
create temp table drx1_before on commit drop as
  select x.k as kind, c.* from (select 'product' as k union all select 'customer' union all select 'supplier') x, lateral public.export_catalog(x.k) c;

-- ═══ 1) export_catalog 재발행 — exp-3 본문 바이트 그대로 + 앞에 deal_rule · deal_product 칸(값 목록 머리에 넣어 기존 줄을 한 바이트도 바꾸지 않는다) + sale 등급 갈래 둘 ═══
--   키는 화면 localStorage ims_export_cols_<kind> 가 기억하므로 바꾸지 않는다(763) · 기본 켜짐 = 판정 792 「기본 칸은 % 까지」
create or replace function public.export_catalog(p_kind text)
returns table(ord int, key text, label text, grp text, dflt boolean, gate text, is_text boolean)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.ord, c.key, c.label, c.grp, c.dflt, c.gate, c.is_text from (values
    -- drx-1 ⓐ 규칙 정의 — 딜 머리(줄마다 되풀이) + 줄
    ('deal_rule',     1, 'rule_name',        'Rule',             'Rule',     true,  'all', false),
    ('deal_rule',     2, 'rule_type',        'Type',             'Rule',     true,  'all', false),
    ('deal_rule',     3, 'status',           'Status',           'Rule',     true,  'all', false),
    ('deal_rule',     4, 'is_active',        'Turned on',        'Rule',     false, 'all', false),
    ('deal_rule',     5, 'date_from',        'From',             'Rule',     true,  'all', false),
    ('deal_rule',     6, 'date_to',          'To',               'Rule',     true,  'all', false),
    ('deal_rule',     7, 'coupon_required',  'Coupon required',  'Rule',     true,  'all', false),
    ('deal_rule',     8, 'customer_rules',   'Customers',        'Rule',     true,  'all', false),
    ('deal_rule',     9, 'tiers',            'Order tiers',      'Rule',     true,  'all', false),
    ('deal_rule',    10, 'note',             'Note',             'Rule',     false, 'all', false),
    ('deal_rule',    11, 'source',           'Added in',         'Rule',     false, 'all', false),
    ('deal_rule',    12, 'updated_at',       'Last changed',     'Rule',     false, 'all', false),
    ('deal_rule',    20, 'line_no',          'Line',             'Line',     true,  'all', false),
    ('deal_rule',    21, 'line_on',          'Line on',          'Line',     false, 'all', false),
    ('deal_rule',    22, 'pct',              'Rule %',           'Line',     true,  'all', false),
    ('deal_rule',    23, 'min_qty_rule',     'Min qty rule',     'Line',     false, 'all', false),
    ('deal_rule',    24, 'min_qty',          'Min qty (each)',   'Line',     true,  'all', false),
    ('deal_rule',    25, 'include_targets',  'Applies to',       'Line',     true,  'all', false),
    ('deal_rule',    26, 'exclude_targets',  'Except',           'Line',     true,  'all', false),
    ('deal_rule',    27, 'line_note',        'Line note',        'Line',     false, 'all', false),
    -- drx-1 ⓑ 풀린 제품 — (규칙 × 제품 × 줄) · 가격 칸은 아래 등급 갈래
    ('deal_product',  1, 'rule_name',        'Rule',             'Rule',     true,  'all', false),
    ('deal_product',  2, 'status',           'Status',           'Rule',     false, 'all', false),
    ('deal_product',  3, 'date_from',        'From',             'Rule',     false, 'all', false),
    ('deal_product',  4, 'date_to',          'To',               'Rule',     false, 'all', false),
    ('deal_product',  5, 'coupon_required',  'Coupon required',  'Rule',     false, 'all', false),
    ('deal_product',  6, 'customer_limited', 'Customer rules',   'Rule',     true,  'all', false),
    ('deal_product',  7, 'line_no',          'Line',             'Rule',     true,  'all', false),
    ('deal_product', 10, 'sku',              'SKU',              'Product',  true,  'all', true),
    ('deal_product', 11, 'name',             'Name',             'Product',  true,  'all', false),
    ('deal_product', 12, 'brand',            'Brand',            'Product',  true,  'all', false),
    ('deal_product', 13, 'category',         'Category',         'Product',  true,  'all', false),
    ('deal_product', 14, 'kind',             'Kind',             'Product',  false, 'all', false),
    ('deal_product', 15, 'parent_sku',       'Set of',           'Product',  false, 'all', true),
    ('deal_product', 16, 'pack_factor',      'Pack factor',      'Product',  false, 'all', false),
    ('deal_product', 17, 'matched_by',       'Picked by',        'Product',  false, 'all', false),
    ('deal_product', 20, 'pct',              'Rule %',           'Discount', true,  'all', false),
    ('deal_product', 21, 'min_qty_rule',     'Min qty rule',     'Discount', false, 'all', false),
    ('deal_product', 22, 'min_qty',          'Min qty (each)',   'Discount', true,  'all', false),
    ('product',  1, 'sku',                  'SKU',                          'Product',  true,  'all',     true),
    ('product',  2, 'name',                 'Name',                         'Product',  true,  'all',     false),
    ('product',  3, 'kind',                 'Kind',                         'Product',  false, 'all',     false),
    ('product',  4, 'parent_sku',           'Set of',                       'Product',  false, 'all',     true),
    ('product',  5, 'pack_factor',          'Pack factor',                  'Product',  false, 'all',     false),
    ('product',  6, 'family_sku',           'Family',                       'Product',  false, 'all',     true),
    ('product',  7, 'option1',              'Option 1',                     'Product',  false, 'all',     false),
    ('product',  8, 'option2',              'Option 2',                     'Product',  false, 'all',     false),
    ('product',  9, 'option3',              'Option 3',                     'Product',  false, 'all',     false),
    ('product', 10, 'brand',                'Brand',                        'Product',  true,  'all',     false),
    ('product', 11, 'category',             'Category',                     'Product',  true,  'all',     false),
    ('product', 12, 'unit',                 'Unit',                         'Product',  false, 'all',     false),
    ('product', 13, 'is_active',            'Active',                       'Product',  true,  'all',     false),
    ('product', 14, 'sellable',             'Sold on its own',              'Product',  false, 'all',     false),
    ('product', 15, 'is_discontinued',      'Discontinued',                 'Product',  false, 'all',     false),
    ('product', 16, 'sale_pct',             'On sale %',                    'Product',  false, 'all',     false),
    ('product', 17, 'surcharge_group',      'Surcharge group',              'Product',  false, 'all',     false),
    ('product', 18, 'weight',               'Weight',                       'Product',  false, 'all',     false),
    ('product', 19, 'weight_unit',          'Weight unit',                  'Product',  false, 'all',     false),
    ('product', 20, 'hs_code',              'HS code',                      'Product',  false, 'all',     true),
    ('product', 21, 'country_of_origin',    'Country of origin',            'Product',  false, 'all',     false),
    ('product', 22, 'sale_tax_rule',        'Sale tax rule',                'Product',  false, 'all',     false),
    ('product', 23, 'purchase_tax_rule',    'Purchase tax rule',            'Product',  false, 'all',     false),
    ('product', 24, 'source',               'Added in',                     'Product',  false, 'all',     false),
    ('product', 25, 'created_at',           'Added on',                     'Product',  false, 'all',     false),
    ('product', 26, 'description',          'Description',                  'Product',  false, 'all',     false),
    ('product', 30, 'barcodes',             'Barcodes',                     'Barcodes', true,  'all',     true),
    ('product', 31, 'tags',                 'Tags',                         'Tags',     false, 'all',     false),
    ('product', 32, 'photo_count',          'Photos',                       'Photos',   false, 'all',     false),
    ('product', 40, 'default_supplier',     'Default supplier',             'Supplier', true,  'all',     false),
    ('product', 41, 'default_supplier_sku', 'Default supplier SKU',         'Supplier', false, 'all',     true),
    ('product', 42, 'default_currency',     'Default supplier currency',    'Supplier', false, 'all',     false),
    ('product', 43, 'default_fixed_cost',   'Fixed cost (default supplier)',  'Cost',   false, 'cost',    false),
    ('product', 44, 'default_latest_cost',  'Latest cost (default supplier)', 'Cost',   false, 'cost',    false),
    ('product', 45, 'all_suppliers',        'All suppliers',                'Supplier', false, 'all',     false),
    ('customer',  1, 'name',                   'Name',                   'Customer', true,  'all',     false),
    ('customer',  2, 'display_name',           'Display name',           'Customer', false, 'all',     false),
    ('customer',  3, 'is_active',              'Active',                 'Customer', true,  'all',     false),
    ('customer',  4, 'price_tier',             'Price tier',             'Customer', true,  'all',     false),
    ('customer',  5, 'payment_term',           'Payment term',           'Customer', true,  'all',     false),
    ('customer',  6, 'currency',               'Currency',               'Customer', true,  'all',     false),
    ('customer',  7, 'discount_pct',           'Discount %',             'Customer', false, 'all',     false),
    ('customer',  8, 'tax_rule',               'Tax rule',               'Customer', false, 'all',     false),
    ('customer',  9, 'default_warehouse',      'Default warehouse',      'Customer', true,  'all',     false),
    ('customer', 10, 'parent',                 'Parent',                 'Customer', false, 'all',     false),
    ('customer', 11, 'invoices_to',            'Invoices go to',         'Customer', false, 'all',     false),
    ('customer', 12, 'carrier',                'Carrier',                'Customer', false, 'all',     false),
    ('customer', 13, 'tax_number',             'Tax number',             'Customer', false, 'all',     true),
    ('customer', 14, 'tags',                   'Tags',                   'Customer', false, 'all',     false),
    ('customer', 15, 'invoice_split_by_store', 'Split invoice by store', 'Customer', false, 'all',     false),
    ('customer', 16, 'backorder_mail',         'Backorder emails',       'Customer', false, 'all',     false),
    ('customer', 17, 'invoice_mail',           'Invoice emails',         'Customer', false, 'all',     false),
    ('customer', 18, 'source',                 'Added in',               'Customer', false, 'all',     false),
    ('customer', 19, 'created_at',             'Added on',               'Customer', false, 'all',     false),
    ('customer', 20, 'reviewed_at',            'Reviewed',               'Customer', false, 'all',     false),
    ('customer', 30, 'billing_line1',          'Billing line 1',         'Billing address',  false, 'contact', false),
    ('customer', 31, 'billing_line2',          'Billing line 2',         'Billing address',  false, 'contact', false),
    ('customer', 32, 'billing_city',           'Billing city',           'Billing address',  false, 'contact', false),
    ('customer', 33, 'billing_province',       'Billing province',       'Billing address',  false, 'contact', false),
    ('customer', 34, 'billing_postal',         'Billing postal code',    'Billing address',  false, 'contact', true),
    ('customer', 35, 'billing_country',        'Billing country',        'Billing address',  false, 'contact', false),
    ('customer', 40, 'shipping_line1',         'Shipping line 1',        'Shipping address', false, 'contact', false),
    ('customer', 41, 'shipping_line2',         'Shipping line 2',        'Shipping address', false, 'contact', false),
    ('customer', 42, 'shipping_city',          'Shipping city',          'Shipping address', false, 'contact', false),
    ('customer', 43, 'shipping_province',      'Shipping province',      'Shipping address', false, 'contact', false),
    ('customer', 44, 'shipping_postal',        'Shipping postal code',   'Shipping address', false, 'contact', true),
    ('customer', 45, 'shipping_country',       'Shipping country',       'Shipping address', false, 'contact', false),
    ('customer', 50, 'contact_name',           'Contact name',           'Contact',  false, 'contact', false),
    ('customer', 51, 'contact_phone',          'Contact phone',          'Contact',  false, 'contact', true),
    ('customer', 52, 'contact_mobile',         'Contact mobile',         'Contact',  false, 'contact', true),
    ('customer', 53, 'contact_email',          'Contact email',          'Contact',  false, 'contact', false),
    ('customer', 54, 'contact_marketing',      'Marketing email',        'Contact',  false, 'contact', false),
    ('supplier',  1, 'name',            'Name',               'Supplier', true,  'all', false),
    ('supplier',  2, 'is_active',       'Active',             'Supplier', true,  'all', false),
    ('supplier',  3, 'purchasable',     'Purchasable',        'Supplier', true,  'all', false),
    ('supplier',  4, 'is_discontinued', 'Discontinued',       'Supplier', false, 'all', false),
    ('supplier',  5, 'currency',        'Currency',           'Supplier', true,  'all', false),
    ('supplier',  6, 'payment_term',    'Payment term',       'Supplier', true,  'all', false),
    ('supplier',  7, 'account_payable', 'Account payable',    'Supplier', false, 'all', true),
    ('supplier',  8, 'tax_rule',        'Tax rule',           'Supplier', false, 'all', false),
    ('supplier',  9, 'discounts',       'Discounts',          'Supplier', false, 'all', false),
    ('supplier', 10, 'source',          'Added in',           'Supplier', false, 'all', false),
    ('supplier', 11, 'created_at',      'Added on',           'Supplier', false, 'all', false),
    ('supplier', 20, 'address_line1',   'Address line 1',     'Address',  false, 'all', false),
    ('supplier', 21, 'address_line2',   'Address line 2',     'Address',  false, 'all', false),
    ('supplier', 22, 'address_city',    'City',               'Address',  false, 'all', false),
    ('supplier', 23, 'address_province','Province',           'Address',  false, 'all', false),
    ('supplier', 24, 'address_postal',  'Postal code',        'Address',  false, 'all', true),
    ('supplier', 25, 'address_country', 'Country',            'Address',  false, 'all', false),
    ('supplier', 30, 'contact_name',    'Contact name',       'Contact',  false, 'all', false),
    ('supplier', 31, 'contact_phone',   'Contact phone',      'Contact',  false, 'all', true),
    ('supplier', 32, 'contact_mobile',  'Contact mobile',     'Contact',  false, 'all', true),
    ('supplier', 33, 'contact_email',   'Contact email',      'Contact',  false, 'all', false)
  ) as c(kind, ord, key, label, grp, dflt, gate, is_text)
  where c.kind = p_kind
  union all
  -- 가격 등급마다 칸 하나(762) · 키는 코드로(이름이 바뀌어도 화면이 기억한 키가 산다) · reference 는 누구에게도 없다(760)
  select 100 + t.code, 'price_' || t.code, 'Price: ' || t.name, 'Price', t.code = 1, 'all', false
  from public.ref_price_tier t
  where p_kind = 'product' and t.is_active and t.purpose in ('sale', 'compare')
  union all
  -- drx-1 ⓑ 가격 칸 — sale 등급마다 List · After rule %(이견 3 · 판정 792 · 기본 꺼짐)
  select 200 + t.code, 'list_' || t.code, 'List: ' || t.name, 'Price', false, 'all', false
  from public.ref_price_tier t
  where p_kind = 'deal_product' and t.is_active and t.purpose = 'sale'
  union all
  select 300 + t.code, 'after_' || t.code, 'After rule %: ' || t.name, 'Price', false, 'all', false
  from public.ref_price_tier t
  where p_kind = 'deal_product' and t.is_active and t.purpose = 'sale'
$$;
comment on function public.export_catalog(text) is 'exp-1 판정 700 · 759 · 760 · 761 · 762 — 내보내기 칸 목록 정본(속 함수 · 직원 판단 없음 · export_columns · export_pick 이 문으로 거른다) · gate all | cost(원가 열쇠) | contact(sales 쓰기 ∨ master 쓰기) · 가격 = price_<등급 코드>(sale · compare · reference 없음) · 키는 화면 localStorage 가 기억하므로 바꾸지 않는다 · exp-3 판정 766 · 767 — source = Added in · created_at = Added on(옛 기록은 IMS 로 들어온 날) · drx-1 kind deal_rule(규칙 정의 · 줄 하나 = 한 줄) · deal_product(규칙 × 제품 × 줄 · 가격 = list_<code> · after_<code> · sale 등급만 · 기본 꺼짐)';

-- ═══ 2) export_door 재발행 — 원본 exp-1 + 갈래 둘(이견 11: so_deal_list 와 같은 문) ═══
create or replace function public.export_door(p_kind text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select case p_kind
    when 'product'  then public.ims_can_view('master')
    when 'customer' then public.ims_can_view('sales')
    when 'supplier' then public.ims_can_view('master') or public.ims_can_view('purchasing')
    when 'deal_rule'    then public.ims_can_view('sales') or public.ims_can_write('master')    -- drx-1: so_deal_list · so_deal_detail · so_quote_preview 와 같은 문
    when 'deal_product' then public.ims_can_view('sales') or public.ims_can_write('master')    -- drx-1
    else false end
$$;
comment on function public.export_door(text) is 'exp-1 판정 763 · 이견 4 — 내보내기 창구 문(속 함수): product = master 보기 · customer = sales 보기 · supplier = master 보기 ∨ purchasing 보기 · ims_can_view 가 활성 직원까지 본다 · drx-1 deal_rule · deal_product = sales 보기 ∨ master 쓰기(so_deal_list 와 같다)';

-- ═══ 3) export_columns 재발행 — 원본 exp-1 + kind 둘 · 거부 문장의 이름(deal_rules 가 아니라 discount rules) ═══
create or replace function public.export_columns(p_kind text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if p_kind is null or p_kind not in ('product', 'customer', 'supplier', 'deal_rule', 'deal_product') then raise exception 'p_kind must be product, customer, supplier, deal_rule or deal_product'; end if;   -- drx-1: kind 둘
  if not public.export_door(p_kind) then
    raise exception 'You cannot export % — nothing was read', case p_kind when 'deal_rule' then 'discount rules' when 'deal_product' then 'discount rule products' else p_kind || 's' end;   -- drx-1: 이름
  end if;
  return jsonb_build_object('kind', p_kind, 'columns', coalesce((
    select jsonb_agg(jsonb_build_object('key', c.key, 'label', c.label, 'group', c.grp, 'default', c.dflt, 'text', c.is_text) order by c.ord)
    from public.export_catalog(p_kind) c where public.export_gate_ok(c.gate)), '[]'::jsonb));
end $$;
comment on function public.export_columns(text) is 'exp-1 판정 700 · 763 — 칸 고르기 창의 목록: {kind, columns:[{key, label, group, default, text}]} · 고를 수 없는 칸은 목록에 없다 · text = 엑셀이 숫자로 바꾸지 않게 ="…" 로 쓸 칸(SKU · 바코드 · 우편번호 …) · drx-1 kind deal_rule · deal_product';

-- ═══ 4) deal_export — 창구 하나(판정 791) · ⓐ deal_rule · ⓑ deal_product ═══
--   ⚠️⚠️ so_line_quote 의 가격 식을 고치면 deal_export 도 같이 고친다 · 검증 drx_1_check 의 so_quote_preview 대조가 그 증명 (아래 「so_line_quote 복사 시작 ~ 끝」 구간)
create function public.deal_export(p_deal_ids uuid[], p_kind text, p_columns text[] default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_cols jsonb; v_keys text[]; v_total bigint; v_rows jsonb; v_ids uuid[]; v_missing int;
begin
  if p_kind is null or p_kind not in ('deal_rule', 'deal_product') then raise exception 'p_kind must be deal_rule or deal_product — nothing was exported'; end if;
  if not public.export_door(p_kind) then                                                                                    -- 문을 먼저(export_pick 의 문장은 세 화면 이름이라 여기서 말한다)
    raise exception 'You cannot export discount rules — ask an admin for the sales permission — nothing was exported';
  end if;
  select jsonb_agg(jsonb_build_object('key', k.key, 'label', k.label, 'text', k.is_text) order by k.o), array_agg(k.key order by k.o)
    into v_cols, v_keys from public.export_pick(p_kind, p_columns) k;                                                       -- 빈 목록 · 겹침 · 모르는 칸 · 고를 수 없는 칸 → 거부(700)
  select array_agg(distinct u.id) into v_ids from unnest(p_deal_ids) u(id) where u.id is not null;                          -- 같은 id 두 번 = 한 번
  if v_ids is null or cardinality(v_ids) = 0 then raise exception 'Pick at least one rule — nothing was exported'; end if;
  select count(*) into v_missing from unnest(v_ids) u(id) where not exists (select 1 from public.so_deal d where d.id = u.id);
  if v_missing > 0 then raise exception '% of the picked rules no longer exist — reload the list — nothing was exported', v_missing; end if;

  if p_kind = 'deal_rule' then
    -- ⓐ 딜 줄 하나 = 한 줄(꺼진 줄 포함) · 줄 없는 딜도 한 줄 · 머리 칸은 줄마다 되풀이 · 순서 딜 이름 · 줄 번호
    with d as (
      select x.*, (x.date_to is not null and x.date_to < public.ims_today()) as ended from public.so_deal x where x.id = any (v_ids)
    ),
    rl as (                                                                                                                 -- 손님 조건 글자 — 빼기 먼저 · 종류 · 이름(so_deal_customer_ok: 같은 종류 OR · 다른 종류 AND · 빼기 우선)
      select r.deal_id,
             string_agg(case r.kind when 'exclude' then 'Except ' else '' end
                        || case r.target when 'customer' then 'customer = ' || coalesce(cu.name, '?') when 'branch' then 'branch = ' || coalesce(w.name, '?') when 'tier' then 'tier = ' || coalesce(t.name, '?') end,
                        '; ' order by r.kind, r.target, coalesce(cu.name, w.name, t.name)) as v
      from public.so_deal_customer_rule r
      left join public.customer cu on cu.id = r.customer_id left join public.ref_warehouse w on w.id = r.warehouse_id left join public.ref_price_tier t on t.id = r.tier_id
      where r.deal_id = any (v_ids) group by 1),
    tr as (                                                                                                                 -- 오더 금액 단계 글자 「≥ 500.00: 5%」
      select t.deal_id, string_agg('≥ ' || to_char(t.min_amount, 'FM999,999,990.00') || ': ' || (case when t.pct = trunc(t.pct) then trunc(t.pct)::text else rtrim(t.pct::text, '0') end) || '%', '; ' order by t.tier_no) as v
      from public.so_deal_tier t where t.deal_id = any (v_ids) group by 1),
    tg as (                                                                                                                 -- 줄의 대상 글자 「brand: Hera; tag: GM20UOM12」 — 걸기 · 빼기 따로
      select x.line_id, x.kind,
             string_agg(case x.target when 'brand' then 'brand: ' || coalesce(b.name, '?') when 'category' then 'category: ' || coalesce(c.name, '?')
                                      when 'product' then 'product: ' || coalesce(p.sku, '?') when 'tag' then 'tag: ' || x.tag end,
                        '; ' order by x.target, coalesce(b.name, c.name, p.sku, x.tag)) as v
      from public.so_deal_target x
      left join public.ref_brand b on b.id = x.brand_id left join public.ref_category c on c.id = x.category_id left join public.product p on p.id = x.product_id
      where x.line_id in (select l.id from public.so_deal_line l where l.deal_id = any (v_ids)) group by 1, 2),
    base as (
      select d.name, d.id, l.line_no, jsonb_build_object(
        'rule_name', d.name, 'rule_type', case when d.is_order_level then 'Order discount' else 'Line discount' end,
        'status', case when not d.is_active then 'Off' when d.ended then 'Ended' else 'Live' end, 'is_active', d.is_active,
        'date_from', d.date_from, 'date_to', d.date_to, 'coupon_required', d.coupon_required,
        'customer_rules', coalesce(rl.v, 'All customers'), 'tiers', tr.v, 'note', d.note,
        'source', case d.source when 'manual' then 'IMS' when 'cin7' then 'Before IMS' else d.source end,
        'updated_at', to_char(d.updated_at at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI'),
        'line_no', l.line_no, 'line_on', l.is_active, 'pct', l.pct,
        'min_qty_rule', case l.min_qty_mode when 'qty' then 'at least ' || (case when l.min_qty = trunc(l.min_qty) then trunc(l.min_qty)::text else rtrim(l.min_qty::text, '0') end) || ' each' when 'case' then 'full case' when 'none' then null end,
        'min_qty', l.min_qty,
        'include_targets', ti.v, 'exclude_targets', te.v, 'line_note', l.note) as j
      from d
      left join public.so_deal_line l on l.deal_id = d.id
      left join rl on rl.deal_id = d.id left join tr on tr.deal_id = d.id
      left join tg ti on ti.line_id = l.id and ti.kind = 'include' left join tg te on te.line_id = l.id and te.kind = 'exclude'
    ),
    pick as materialized (select * from base order by name, id, line_no nulls first limit 20000)
    select (select count(*) from base),
           coalesce(jsonb_agg((select jsonb_agg(f.j -> u.k order by u.o) from unnest(v_keys) with ordinality u(k, o)) order by f.name, f.id, f.line_no nulls first), '[]'::jsonb)
      into v_total, v_rows from pick f;
  else
    -- ⓑ (규칙 × 제품 × 줄) — so_deal_products_all(켜진 줄 · 걸기 ∧ ¬빼기 · 세트는 낱개를 거쳐) × 활성 제품 · 순서 딜 이름 · sku · 줄 번호
    with a as materialized (
      select z.deal_id, z.product_id, z.line_id, z.line_no, z.matched_by from public.so_deal_products_all(v_ids) z
    ),
    pr as materialized (                                                                                                    -- 제품(활성만 · 이견 5) + 세트 낱개 · 케이스 수량(낱개의 켜진 세트 중 최소 계수 — so_deal_candidates 의 case_qty 와 같다)
      select p.id, p.sku, p.name, p.brand_name, p.category_name, p.parent_product_id, p.pack_factor, coalesce(p.set_discount_pct, 0) as set_pct,
             (select x.sku from public.product x where x.id = p.parent_product_id) as parent_sku,
             (select min(s.pack_factor) from public.product s where s.parent_product_id = coalesce(p.parent_product_id, p.id) and s.is_active and s.pack_factor is not null) as case_qty
      from public.product p where p.is_active and p.id in (select product_id from a)
    ),
    px as materialized (                                                                                                    -- 가격(고른 칸에 등급 키가 있을 때만) · sale 등급마다 정가 · 출처
      -- ── so_line_quote 복사 시작(20261006193419_dsc_2_deal_rules.sql :242 ~ :249 · base CTE · 판정 298 — 줄마다 so_price_for 를 부르던 것을 집합으로 옮겼다 · 뜻 같음은 drx_1_check Q 갈래가 so_quote_preview 와 대조) ──
      --    row      = 제품 자신의 활성 가격 줄(so_price_for 'row')                       → list = 그 값 · set_pct 후보 없음
      --    set_calc = 낱개의 활성 줄 × pack_factor(so_price_for 'set_calc')              → list = round(낱개 × pack_factor, 2)(할인 전) · set_discount_pct 가 후보
      select pr.id as product_id, t.code,
             case when own.price is not null then own.price
                  when pr.parent_product_id is not null and base.price is not null then round(base.price * pr.pack_factor, 2) end as list_price,
             case when own.price is null and pr.parent_product_id is not null and base.price is not null then pr.set_pct else 0 end as set_pct
      from pr
      cross join (select t.id, t.code from public.ref_price_tier t where t.is_active and t.purpose = 'sale') t
      left join public.product_price own  on own.product_id  = pr.id                and own.tier_id  = t.id and own.is_active
      left join public.product_price base on base.product_id = pr.parent_product_id and base.tier_id = t.id and base.is_active and pr.pack_factor is not null
      where exists (select 1 from unnest(v_keys) k where k like 'list\_%' or k like 'after\_%')
      -- ── so_line_quote 복사 끝 ──
    ),
    pj as (select px.product_id, jsonb_object_agg(px.code::text, jsonb_build_array(px.list_price, px.set_pct)) as j from px group by 1),
    base as (
      select d.name, d.id as deal_id, pr.sku, l.line_no, jsonb_build_object(
        'rule_name', d.name, 'status', case when not d.is_active then 'Off' when d.date_to is not null and d.date_to < public.ims_today() then 'Ended' else 'Live' end,
        'date_from', d.date_from, 'date_to', d.date_to, 'coupon_required', d.coupon_required,
        'customer_limited', exists (select 1 from public.so_deal_customer_rule r where r.deal_id = d.id),
        'line_no', l.line_no, 'sku', pr.sku, 'name', pr.name, 'brand', pr.brand_name, 'category', pr.category_name,
        'kind', case when pr.parent_product_id is null then 'Single' else 'Set' end, 'parent_sku', pr.parent_sku, 'pack_factor', pr.pack_factor,
        'matched_by', array_to_string(a.matched_by, '; '),
        'pct', l.pct,
        'min_qty_rule', case l.min_qty_mode when 'qty' then 'at least ' || (case when l.min_qty = trunc(l.min_qty) then trunc(l.min_qty)::text else rtrim(l.min_qty::text, '0') end) || ' each' when 'case' then 'full case' when 'none' then null end,
        'min_qty', case l.min_qty_mode when 'qty' then l.min_qty when 'case' then pr.case_qty end)
        || coalesce((select jsonb_object_agg('list_' || e.k, e.v -> 0) || jsonb_object_agg('after_' || e.k,                  -- 할인가 = round(list × (1 − greatest(줄 %, set_pct)/100), 4) — so_line_quote 의 greatest(…, 딜 %, set_pct) 에서 손님 기본 할인만 뺀 것
                       case when (e.v ->> 0) is null then null else round((e.v ->> 0)::numeric * (1 - greatest(l.pct, (e.v ->> 1)::numeric) / 100), 4) end)
                     from jsonb_each(pj.j) e(k, v)), '{}'::jsonb) as j
      from a
      join public.so_deal d on d.id = a.deal_id
      join public.so_deal_line l on l.id = a.line_id
      join pr on pr.id = a.product_id
      left join pj on pj.product_id = a.product_id
    ),
    pick as materialized (select * from base order by name, deal_id, sku, line_no limit 20000)
    select (select count(*) from base),
           coalesce(jsonb_agg((select jsonb_agg(f.j -> u.k order by u.o) from unnest(v_keys) with ordinality u(k, o)) order by f.name, f.deal_id, f.sku, f.line_no), '[]'::jsonb)
      into v_total, v_rows from pick f;
  end if;
  return jsonb_build_object('kind', p_kind, 'total', v_total, 'row_count', jsonb_array_length(v_rows), 'truncated', v_total > 20000,
                            'columns', v_cols, 'rows', v_rows);
end $$;
revoke all on function public.deal_export(uuid[], text, text[]) from public, anon, service_role;
grant execute on function public.deal_export(uuid[], text, text[]) to authenticated;
comment on function public.deal_export(uuid[], text, text[]) is 'drx-1 판정 790 ~ 792(짐작 번호) — Discount Rules 내보내기 창구 하나(규칙 상세 = id 하나 · 규칙 목록 = 보이는 규칙 전부): p_kind deal_rule(ⓐ 규칙 정의 · 딜 줄 하나 = 한 줄 · 꺼진 줄 포함 · 줄 없는 딜도 한 줄 · 손님 조건 · 오더 단계는 글자 한 칸) | deal_product(ⓑ 풀린 제품 · (규칙 × 제품 × 줄) · so_deal_products_all · 켜진 줄 · 활성 제품만 · 세트 포함 · Rule % = 그 규칙의 % — 손님 기본 할인 · 다른 규칙과의 겨룸은 넣지 않는다 · 가격 list_<code> · after_<code> = round(list × (1 − greatest(줄 %, set_calc 세트의 set_discount_pct)/100), 4) · ⚠️ so_line_quote 의 가격 식 복사 — 그쪽을 고치면 여기도 · 검증 drx_1_check Q) + p_columns(export_columns 의 키) → {kind, total, row_count, truncated, columns:[{key,label,text}], rows:[[값…]]} · 한도 20,000 · 문 = sales 보기 ∨ master 쓰기(so_deal_list 와 같다) · 같은 id 두 번 = 한 번 · 없는 id · 빈 배열 거부 · definer · 원가 없음';

-- ═══ 5) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text; v_sale int;
begin
  select count(*) into v_sale from public.ref_price_tier t where t.is_active and t.purpose = 'sale';
  foreach v_t in array array['public.export_catalog(text)', 'public.export_door(text)', 'public.export_pick(text, text[])', 'public.export_gate_ok(text)'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') or has_function_privilege('service_role', v_t, 'execute') then v_bad := v_bad || format(' %s(open)', v_t); end if;
  end loop;
  foreach v_t in array array['public.export_columns(text)', 'public.deal_export(uuid[], text, text[])'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if not has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') or has_function_privilege('service_role', v_t, 'execute') then v_bad := v_bad || format(' %s(grants)', v_t); end if;
  end loop;
  if (select count(*) from public.export_catalog('deal_rule')) <> 20 then v_bad := v_bad || ' deal_rule(columns)'; end if;
  if (select count(*) from public.export_catalog('deal_product')) <> 18 + 2 * v_sale then v_bad := v_bad || ' deal_product(columns)'; end if;
  if (select count(*) from public.export_catalog('deal_product') c where c.key like 'after\_%' and c.key = 'after_8') <> 0 then v_bad := v_bad || ' reference_tier(760)'; end if;
  if (select count(*) from public.export_catalog('deal_product') c where c.dflt) <> 9 then v_bad := v_bad || ' deal_product(defaults)'; end if;
  if (select count(*) from public.export_catalog('deal_product') c where c.gate <> 'all') + (select count(*) from public.export_catalog('deal_rule') c where c.gate <> 'all') <> 0 then v_bad := v_bad || ' gate(not all)'; end if;
  -- 세 kind 의 칸 목록은 바이트 그대로(머리 do 블록이 담아 둔 것과 양방향 차집합 0)
  if (select count(*) from (select kind, ord, key, label, grp, dflt, gate, is_text from drx1_before
                             except select x.k, c.* from (select 'product' as k union all select 'customer' union all select 'supplier') x, lateral public.export_catalog(x.k) c) z) <> 0
     or (select count(*) from (select x.k, c.* from (select 'product' as k union all select 'customer' union all select 'supplier') x, lateral public.export_catalog(x.k) c
                                except select kind, ord, key, label, grp, dflt, gate, is_text from drx1_before) z) <> 0 then v_bad := v_bad || ' old_kinds(changed)'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('export_pick', 'export_gate_ok', 'product_export', 'customer_export', 'supplier_export', 'so_line_quote', 'so_quote_preview', 'so_deal_products_all') and p.prosrc like '%drx-1%') <> 0 then v_bad := v_bad || ' untouched(touched)'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('export_catalog', 'export_door', 'export_columns', 'deal_export')) <> 4 then v_bad := v_bad || ' count'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM791', message = format('STOP - drx-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
