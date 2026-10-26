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

-- ═══ exp-3 — 내보내기 칸 이름: 「Made in」 → 「Added in」 · 「Created」 → 「Added on」 (2026-10-26 · 판정 766 · 767 · 재발행 419) ═══
--   source 칸(IMS · Before IMS = 그 기록이 IMS 에서 만들어졌나 옛 시스템에서 왔나)이 「Made in」 이라 Country of origin 과 함께 원산지 칸이 둘로 보였다(766) → 「Added in」(제품 · 손님 · 공급처 셋 다 · 값 · 키 그대로)
--   created_at 은 옛 시스템에서 온 기록(Before IMS)에 대해 IMS 로 적재된 날이다(767 · 테스트 DB 확인: product cin7 18,714 행 전부 2026-09-14 · customer cin7 9,469 행 전부 2026-09-22 · supplier cin7 259 행 = 09-12 · 09-14 · 10-05 — 적재일 · 옛 생성일은 product.cin7_created_on 에만) → 「Added on」
--   바뀐 줄 = 이름 여섯(product 24 · 25 · customer 18 · 19 · supplier 10 · 11) · 키 · 순서 · 묶음 · 기본 켜짐 · 문 · 글자 칸 그대로(키는 화면 localStorage ims_export_cols_<kind> 가 기억하므로 바꾸지 않는다)
--   원본: 20261026162607_exp_1_export_windows.sql(DB md5 a38b488dfac4cf51d83a493e4015fe41 · 본문 101 줄) · create or replace 라 ACL(postgres 만) 보존 · comment 는 원문 + exp-3 꼬리
--   무접촉: export_door · export_gate_ok · export_pick · export_columns · product_export · customer_export · supplier_export · 표 · 정책 · grant · 시퀀스 0 · 화면 0 · 검증 supabase/tests/exp_3_check.sql(-v mig)

do $$
declare v_bad text := '';
begin
  if to_regprocedure('public.export_catalog(text)') is null then v_bad := v_bad || ' exp_1_not_landed'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'export_catalog') is distinct from 'a38b488dfac4cf51d83a493e4015fe41' then v_bad := v_bad || ' export_catalog_not_exp_1'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM514', message = format('STOP - exp-3 needs%s - nothing was changed', v_bad); end if;
end $$;

-- ═══ export_catalog 재발행 — 원본 exp-1 바이트 + 이름 여섯 ═══
create or replace function public.export_catalog(p_kind text)
returns table(ord int, key text, label text, grp text, dflt boolean, gate text, is_text boolean)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.ord, c.key, c.label, c.grp, c.dflt, c.gate, c.is_text from (values
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
$$;
comment on function public.export_catalog(text) is 'exp-1 판정 700 · 759 · 760 · 761 · 762 — 내보내기 칸 목록 정본(속 함수 · 직원 판단 없음 · export_columns · export_pick 이 문으로 거른다) · gate all | cost(원가 열쇠) | contact(sales 쓰기 ∨ master 쓰기) · 가격 = price_<등급 코드>(sale · compare · reference 없음) · 키는 화면 localStorage 가 기억하므로 바꾸지 않는다 · exp-3 판정 766 · 767 — source = Added in · created_at = Added on(옛 기록은 IMS 로 들어온 날)';

-- ═══ 착지 — md5 · 이름 여섯 · 옛 이름 0 · 열쇠 가림(원가 2 · 연락처 17) · 칸 수(product 35+가격 · customer 37 · supplier 21) · ACL · definer · stable 그대로 ═══
do $$
declare v_bad text := '';  r record;
begin
  select md5(p.prosrc) as m, coalesce(p.proacl::text, '-') as acl, p.prosecdef as d, p.provolatile as v, coalesce(array_to_string(p.proconfig, ','), '-') as cfg,
         (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = 'export_catalog') as n
    into r from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'export_catalog';
  if r.m <> 'bf108de21d64b2fb8e4ae93ed7c87c06' then v_bad := v_bad || ' body_md5'; end if;
  if r.acl <> '{postgres=X/postgres}' then v_bad := v_bad || ' acl'; end if;
  if not r.d or r.v <> 's' or r.cfg <> 'search_path=public, pg_temp' or r.n <> 1 then v_bad := v_bad || ' security_or_overloads'; end if;
  if (select count(*) from (select 'product' k union all select 'customer' union all select 'supplier') x, lateral public.export_catalog(x.k) c
        where (c.key = 'source' and c.label = 'Added in') or (c.key = 'created_at' and c.label = 'Added on')) <> 6 then v_bad := v_bad || ' six_labels'; end if;
  if (select count(*) from (select 'product' k union all select 'customer' union all select 'supplier') x, lateral public.export_catalog(x.k) c
        where c.label in ('Made in', 'Created')) <> 0 then v_bad := v_bad || ' old_labels'; end if;
  if (select count(*) from public.export_catalog('product') where gate = 'cost') <> 2 then v_bad := v_bad || ' cost_gate'; end if;
  if (select count(*) from public.export_catalog('customer') where gate = 'contact') <> 17 then v_bad := v_bad || ' contact_gate'; end if;
  if (select count(*) from public.export_catalog('product') where key not like 'price\_%') <> 35 then v_bad := v_bad || ' product_count'; end if;
  if (select count(*) from public.export_catalog('customer')) <> 37 then v_bad := v_bad || ' customer_count'; end if;
  if (select count(*) from public.export_catalog('supplier')) <> 21 then v_bad := v_bad || ' supplier_count'; end if;
  if v_bad <> '' then raise exception 'exp-3 landing failed:%', v_bad; end if;
  raise notice 'exp-3 landed: export_catalog reissued · source = Added in · created_at = Added on (x3) · old labels 0 · cost gate 2 · contact gate 17 · acl postgres only';
end $$;
