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

-- ═══ exp-1 — 내보내기 창구: 칸 목록 + 제품 · 손님 · 공급처 내보내기 (2026-10-26 · 판정 699 · 700 · 759 ~ 764 · deferred 300) ═══
--   화면(products · customers · suppliers.html)이 「지금 목록의 거르기 + 고른 칸」 을 넘기면 창구가 그 직원이 볼 수 있는 칸만 담아 한 번에 돌려준다(763 · 기각: 화면이 1,000 씩 모음)
--   ① export_catalog(kind)   — 칸 목록 정본(키 · 영어 이름 · 묶음 · 기본 켜짐 · 문 · 글자 칸) · 속 함수
--   ② export_door(kind)      — 창구 문: product = master 보기 · customer = sales 보기 · supplier = master 보기 ∨ purchasing 보기(exp-1 이견 4) · ims_can_view 가 활성 직원까지 본다
--   ③ export_gate_ok(gate)   — 칸 문: all · cost(원가 열쇠 · 759 · 764) · contact(sales 쓰기 ∨ master 쓰기 · 761)
--   ④ export_pick(kind, cols) — 고른 칸 검사(빈 목록 · 겹침 · 모르는 칸 · 고를 수 없는 칸 → 거부) · 고른 순서 그대로
--   ⑤ export_columns(kind) · product_export · customer_export · supplier_export — authenticated 가 부르는 넷(definer · stable · 쓰기 0)
--   ⭐ 고를 수 없는 칸은 목록에 없다(700) · 억지로 넣으면 거부 · 가격 등급 reference(REFERENCECOST USD)는 누구에게도 없다(760 · 정책은 그대로)
--   ⭐ 한 제품(손님 · 공급처) = 한 줄(762) — 가격 = 등급마다 칸 · 바코드 · 태그 · 모든 공급처 = 「; 」(대표 · 기본 먼저) · 손님 주소 = 기본 Billing · 기본 Shipping · 연락처 = 기본 · 공급처 주소 = Billing → Business → Shipping 첫 줄(기본 표시가 없는 표) · 할인 = 「이름 n%」
--   ⭐ 행 = 지금 목록의 거르기 그대로(700) — 제품 = product_list 의 거르기 일곱 · 순서 sku · 손님 = customers.html baseQuery · 순서 name · 공급처 = suppliers.html baseQuery · 읽기 직원(master · purchasing 쓰기 없음)은 켜짐 · purchasable · 단종 아님을 창구가 강제
--   ⭐ 한도 20,000 행(stk_availability_export 와 같다 · 제품 전체 18,741) · 넘으면 truncated
--   ⚠️ 759 의 DB 전체 가림(product_supplier 칸 grant · po_lines_paste · price_formula_preview · 화면 다섯)은 이 파일 밖 — 다음 차수 cost-1(deferred 339 후보)
--   새 표 · 칸 · 시퀀스 0 · 무접촉: product_list · stk_availability(_export) · 정책 · 화면 · 검증 supabase/tests/exp_1_check.sql

do $$
declare v_bad text := '';
begin
  if to_regprocedure('public.ims_can_view(text)') is null then v_bad := v_bad || ' ims_can_view'; end if;
  if to_regprocedure('public.ims_can_write(text)') is null then v_bad := v_bad || ' ims_can_write'; end if;
  if to_regprocedure('public.ims_can_view_cost()') is null then v_bad := v_bad || ' ims_can_view_cost'; end if;
  if to_regprocedure('public.so_sale_now(uuid[], date)') is null then v_bad := v_bad || ' so_sale_now'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - exp-1 needs%s - nothing was changed', v_bad); end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname in ('export_catalog', 'export_door', 'export_gate_ok', 'export_pick', 'export_columns', 'product_export', 'customer_export', 'supplier_export')) then
    raise exception using errcode = 'IM511', message = 'STOP - exp-1 functions already exist (applied?) - nothing was changed';
  end if;
end $$;

-- ═══ ① 칸 목록 정본 ═══
create function public.export_catalog(p_kind text)
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
    ('product', 24, 'source',               'Made in',                      'Product',  false, 'all',     false),
    ('product', 25, 'created_at',           'Created',                      'Product',  false, 'all',     false),
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
    ('customer', 18, 'source',                 'Made in',                'Customer', false, 'all',     false),
    ('customer', 19, 'created_at',             'Created',                'Customer', false, 'all',     false),
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
    ('supplier', 10, 'source',          'Made in',            'Supplier', false, 'all', false),
    ('supplier', 11, 'created_at',      'Created',            'Supplier', false, 'all', false),
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
comment on function public.export_catalog(text) is 'exp-1 판정 700 · 759 · 760 · 761 · 762 — 내보내기 칸 목록 정본(속 함수 · 직원 판단 없음 · export_columns · export_pick 이 문으로 거른다) · gate all | cost(원가 열쇠) | contact(sales 쓰기 ∨ master 쓰기) · 가격 = price_<등급 코드>(sale · compare · reference 없음) · 키는 화면 localStorage 가 기억하므로 바꾸지 않는다';

-- ═══ ② ③ 문 ═══
create function public.export_door(p_kind text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select case p_kind
    when 'product'  then public.ims_can_view('master')
    when 'customer' then public.ims_can_view('sales')
    when 'supplier' then public.ims_can_view('master') or public.ims_can_view('purchasing')
    else false end
$$;
comment on function public.export_door(text) is 'exp-1 판정 763 · 이견 4 — 내보내기 창구 문(속 함수): product = master 보기 · customer = sales 보기 · supplier = master 보기 ∨ purchasing 보기 · ims_can_view 가 활성 직원까지 본다';

create function public.export_gate_ok(p_gate text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select case p_gate
    when 'all'     then true
    when 'cost'    then public.ims_can_view_cost()
    when 'contact' then public.ims_can_write('sales') or public.ims_can_write('master')
    else false end
$$;
comment on function public.export_gate_ok(text) is 'exp-1 판정 759 · 761 · 764 — 칸 문(속 함수): cost = ims_can_view_cost() · contact = sales 쓰기 ∨ master 쓰기 · 모르는 문 = false';

-- ═══ ④ 고른 칸 검사 ═══
create function public.export_pick(p_kind text, p_columns text[])
returns table(o bigint, key text, label text, is_text boolean)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_bad text;
begin
  if not public.export_door(p_kind) then
    raise exception 'You cannot export % — ask an admin for the % screen key — nothing was exported', p_kind || 's',
      case p_kind when 'product' then 'Products (master)' when 'customer' then 'Customers (sales)' else 'Suppliers (master or purchasing)' end;
  end if;
  if p_columns is null or cardinality(p_columns) = 0 then raise exception 'Pick at least one column — nothing was exported'; end if;
  select string_agg(distinct k, ', ') into v_bad from (select k from unnest(p_columns) k group by k having count(*) > 1) x;
  if v_bad is not null then raise exception 'These columns are picked twice: % — nothing was exported', v_bad; end if;
  select string_agg(k, ', ' order by k) into v_bad from unnest(p_columns) k
  where k is null or not exists (select 1 from public.export_catalog(p_kind) c where c.key = k);
  if v_bad is not null then raise exception 'Unknown columns: % — nothing was exported', v_bad; end if;
  select string_agg(c.key, ', ' order by c.ord) into v_bad from public.export_catalog(p_kind) c
  where c.key = any(p_columns) and not public.export_gate_ok(c.gate);
  if v_bad is not null then raise exception 'You cannot export these columns: % — nothing was exported', v_bad; end if;
  return query select u.o, c.key, c.label, c.is_text
    from unnest(p_columns) with ordinality u(k, o) join public.export_catalog(p_kind) c on c.key = u.k order by u.o;
end $$;
comment on function public.export_pick(text, text[]) is 'exp-1 판정 700 — 고른 칸 검사(속 함수): 문 → 빈 목록 → 겹침 → 모르는 칸 → 고를 수 없는 칸 순으로 거부(문장에 칸 이름) · 통과하면 고른 순서 그대로';

-- ═══ ⑤-1 칸 목록 — 이 직원이 고를 수 있는 칸만(700) ═══
create function public.export_columns(p_kind text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if p_kind is null or p_kind not in ('product', 'customer', 'supplier') then raise exception 'p_kind must be product, customer or supplier'; end if;
  if not public.export_door(p_kind) then
    raise exception 'You cannot export % — nothing was read', p_kind || 's';
  end if;
  return jsonb_build_object('kind', p_kind, 'columns', coalesce((
    select jsonb_agg(jsonb_build_object('key', c.key, 'label', c.label, 'group', c.grp, 'default', c.dflt, 'text', c.is_text) order by c.ord)
    from public.export_catalog(p_kind) c where public.export_gate_ok(c.gate)), '[]'::jsonb));
end $$;
comment on function public.export_columns(text) is 'exp-1 판정 700 · 763 — 칸 고르기 창의 목록: {kind, columns:[{key, label, group, default, text}]} · 고를 수 없는 칸은 목록에 없다 · text = 엑셀이 숫자로 바꾸지 않게 ="…" 로 쓸 칸(SKU · 바코드 · 우편번호 …)';

-- ═══ ⑤-2 제품 — product_list 의 거르기 일곱 그대로 · 순서 sku, id ═══
create function public.product_export(p_q text default null, p_brand_name text default null, p_category_name text default null, p_supplier_id uuid default null,
                                      p_kind text default null, p_only_active boolean default false, p_sale_only boolean default false, p_columns text[] default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_q text := nullif(btrim(p_q), ''); v_cols jsonb; v_keys text[]; v_total bigint; v_rows jsonb; v_expr text; v_join text := '';
begin
  if p_kind is not null and p_kind not in ('single', 'set', 'all') then raise exception 'p_kind must be single, set or all'; end if;
  select jsonb_agg(jsonb_build_object('key', k.key, 'label', k.label, 'text', k.is_text) order by k.o), array_agg(k.key order by k.o)
    into v_cols, v_keys from public.export_pick('product', p_columns) k;
  -- 고른 칸의 식만 · 필요한 짝 표만 잇는다(전 칸을 늘 만들면 고른 칸이 하나여도 2 초 · 전부면 8 초를 넘었다 — exp-1 시험 2 회차)
  -- ⚠️ 식은 아래 고정 목록에서만 온다 — 키는 export_pick 이 칸 목록과 대조했다(사용자 글자가 SQL 에 들어가지 않는다 · 가격 키는 %L)
  select string_agg(case k
      when 'sku' then 'p.sku' when 'name' then 'p.name' when 'kind' then 'case when p.parent_product_id is null then ''Single'' else ''Set'' end'
      when 'parent_sku' then '(select x.sku from public.product x where x.id = p.parent_product_id)' when 'pack_factor' then 'p.pack_factor'
      when 'family_sku' then '(select f.sku from public.product_family f where f.id = p.family_id)'
      when 'option1' then 'p.option1_value' when 'option2' then 'p.option2_value' when 'option3' then 'p.option3_value'
      when 'brand' then 'p.brand_name' when 'category' then 'p.category_name' when 'unit' then 'p.uom_name' when 'is_active' then 'p.is_active'
      when 'sellable' then 'p.sellable' when 'is_discontinued' then 'p.is_discontinued' when 'sale_pct' then 'p.best_pct'
      when 'surcharge_group' then '(select g.name from public.so_surcharge_group g where g.id = p.surcharge_group_id)'
      when 'weight' then 'p.weight' when 'weight_unit' then 'p.weight_unit' when 'hs_code' then 'p.hs_code' when 'country_of_origin' then 'p.country_of_origin'
      when 'sale_tax_rule' then 'p.sale_tax_rule' when 'purchase_tax_rule' then 'p.purchase_tax_rule'
      when 'source' then 'case p.source when ''manual'' then ''IMS'' when ''cin7'' then ''Before IMS'' else p.source end'
      when 'created_at' then 'to_char(p.created_at at time zone ''America/Toronto'', ''YYYY-MM-DD'')'
      when 'description' then 'coalesce(p.description_html, p.cin7_description)'
      when 'barcodes' then 'bc.v' when 'tags' then 'tg.v' when 'photo_count' then 'coalesce(im.v, 0)'
      when 'default_supplier' then 'su.d_name' when 'default_supplier_sku' then 'su.d_sku' when 'default_currency' then 'su.d_cur'
      when 'default_fixed_cost' then 'su.d_fixed' when 'default_latest_cost' then 'su.d_cost' when 'all_suppliers' then 'su.v_all'
      else format('(pr.v -> %L)', k) end, ', ' order by o) into v_expr
  from unnest(v_keys) with ordinality u(k, o);
  if v_keys && array['barcodes'] then
    v_join := v_join || ' left join (select b.product_id, string_agg(b.barcode, ''; '' order by b.is_primary desc, b.barcode) v from public.product_barcode b'
      || ' where b.is_active and b.product_id in (select id from pick) group by 1) bc on bc.product_id = p.id';
  end if;
  if v_keys && array['tags'] then
    v_join := v_join || ' left join (select t.product_id, string_agg(t.tag, ''; '' order by t.tag) v from public.product_tag t'
      || ' where t.product_id in (select id from pick) group by 1) tg on tg.product_id = p.id';
  end if;
  if v_keys && array['photo_count'] then
    v_join := v_join || ' left join (select i.product_id, count(*) v from public.product_image i'
      || ' where i.is_active and i.product_id in (select id from pick) group by 1) im on im.product_id = p.id';
  end if;
  if v_keys && array['default_supplier', 'default_supplier_sku', 'default_currency', 'default_fixed_cost', 'default_latest_cost', 'all_suppliers'] then
    v_join := v_join || ' left join (select ps.product_id, string_agg(s.name || coalesce('' ['' || ps.supplier_sku || '']'', ''''), ''; '' order by ps.is_default desc, s.name) v_all,'
      || ' max(s.name) filter (where ps.is_default) d_name, max(ps.supplier_sku) filter (where ps.is_default) d_sku, max(cu.code) filter (where ps.is_default) d_cur,'
      || ' max(ps.fixed_cost) filter (where ps.is_default) d_fixed, max(ps.cost) filter (where ps.is_default) d_cost'
      || ' from public.product_supplier ps join public.supplier s on s.id = ps.supplier_id left join public.ref_currency cu on cu.id = coalesce(ps.currency_id, s.currency_id)'
      || ' where ps.is_active and ps.product_id in (select id from pick) group by 1) su on su.product_id = p.id';
  end if;
  if exists (select 1 from unnest(v_keys) k where k like 'price\_%') then
    v_join := v_join || ' left join (select pp.product_id, jsonb_object_agg(''price_'' || t.code, pp.price) v from public.product_price pp join public.ref_price_tier t on t.id = pp.tier_id'
      || ' where pp.is_active and t.is_active and t.purpose in (''sale'', ''compare'') and pp.product_id in (select id from pick) group by 1) pr on pr.product_id = p.id';
  end if;
  execute format($q$
    with sale as (select z.product_id, z.best_pct from public.so_sale_now(null, null) z where $7 or $8),
    base as materialized (
      select p.*, sale.best_pct from public.product p left join sale on sale.product_id = p.id
      where (not $6 or p.is_active)
        and ($5 is null or $5 = 'all' or ($5 = 'single' and p.parent_product_id is null) or ($5 = 'set' and p.parent_product_id is not null))
        and ($2 is null or p.brand_name = $2)
        and ($3 is null or p.category_name = $3)
        and ($1 is null or p.sku ilike '%%' || $1 || '%%' or p.name ilike '%%' || $1 || '%%')
        and ($4 is null or exists (select 1 from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = $4 and ps.is_active))
        and (not $7 or sale.product_id is not null)
    ),
    pick as materialized (select * from base order by sku, id limit 20000)
    select (select count(*) from base), coalesce(jsonb_agg(jsonb_build_array(%s) order by p.sku, p.id), '[]'::jsonb)
    from pick p %s
  $q$, v_expr, v_join)
  into v_total, v_rows
  using v_q, p_brand_name, p_category_name, p_supplier_id, p_kind, coalesce(p_only_active, false), coalesce(p_sale_only, false), v_keys && array['sale_pct'];
  return jsonb_build_object('kind', 'product', 'total', v_total, 'row_count', jsonb_array_length(v_rows), 'truncated', v_total > 20000,
                            'columns', v_cols, 'rows', v_rows);
end $$;
comment on function public.product_export(text, text, text, uuid, text, boolean, boolean, text[]) is 'exp-1 판정 699 · 700 · 759 · 760 · 762 · 763 — 제품 내보내기: product_list 의 거르기 일곱(같은 이름 · 같은 뜻 · definer 라 공급처 거르기는 누구에게나 같은 행) + p_columns(export_columns 의 키 · 고른 순서) → {kind, total, row_count, truncated, columns:[{key,label,text}], rows:[[값…]]} · 순서 sku · 한도 20,000 · 원가 칸은 원가 열쇠일 때만(759)';

-- ═══ ⑤-3 손님 — customers.html baseQuery 의 거르기 그대로 · 순서 name ═══
create function public.customer_export(p_q text default null, p_only_active boolean default true, p_only_new boolean default false, p_columns text[] default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_q text := nullif(btrim(p_q), ''); v_cols jsonb; v_keys text[]; v_total bigint; v_rows jsonb;
begin
  select jsonb_agg(jsonb_build_object('key', k.key, 'label', k.label, 'text', k.is_text) order by k.o), array_agg(k.key order by k.o)
    into v_cols, v_keys from public.export_pick('customer', p_columns) k;
  with base as (
    select c.* from public.customer c
    where (not coalesce(p_only_active, false) or c.is_active)
      and (not coalesce(p_only_new, false) or (c.source = 'manual' and c.reviewed_at is null))
      and (v_q is null or c.name ilike '%' || v_q || '%' or c.display_name ilike '%' || v_q || '%')
  ),
  pick as materialized (select * from base order by name, id limit 20000),
  ad as materialized (                                   -- 손님마다 한 줄(기본 Billing · 기본 Shipping) — 같은 CTE 를 두 번 잇면 줄마다 다시 훑어 8 초를 넘었다(exp-1 시험 3 회차)
    select a.customer_id,
           max(a.line1) filter (where a.type = 'Billing') b_line1, max(a.line2) filter (where a.type = 'Billing') b_line2, max(a.city) filter (where a.type = 'Billing') b_city,
           max(a.state_province) filter (where a.type = 'Billing') b_prov, max(a.postal_code) filter (where a.type = 'Billing') b_postal, max(a.country) filter (where a.type = 'Billing') b_country,
           max(a.line1) filter (where a.type = 'Shipping') s_line1, max(a.line2) filter (where a.type = 'Shipping') s_line2, max(a.city) filter (where a.type = 'Shipping') s_city,
           max(a.state_province) filter (where a.type = 'Shipping') s_prov, max(a.postal_code) filter (where a.type = 'Shipping') s_postal, max(a.country) filter (where a.type = 'Shipping') s_country
    from public.customer_address a
    where a.is_active and a.is_default_for_type and a.type in ('Billing', 'Shipping') and a.customer_id in (select id from pick) group by 1),
  ct as materialized (select t.customer_id, t.name, t.phone, t.mobile_phone, t.email, t.marketing_consent from public.customer_contact t
         where t.is_active and t.is_default and t.customer_id in (select id from pick)),
  full_ as materialized (                -- 한 번만 만든다 — 그냥 두면 고른 칸마다 jsonb 를 다시 만들어 손님 전 칸이 16 초였다(exp-1 시험 3 회차)
    select c.name, c.id, jsonb_build_object(
      'name', c.name, 'display_name', c.display_name, 'is_active', c.is_active, 'price_tier', c.price_tier, 'payment_term', c.payment_term_name,
      'currency', c.currency_code, 'discount_pct', c.discount_pct, 'tax_rule', c.tax_rule, 'default_warehouse', c.default_location_name,
      'parent', par.name, 'invoices_to', bto.name, 'carrier', c.default_carrier, 'tax_number', c.tax_number, 'tags', c.tags,
      'invoice_split_by_store', c.invoice_split_by_store, 'backorder_mail', c.backorder_mail, 'invoice_mail', c.final_invoice_mail,
      'source', case c.source when 'manual' then 'IMS' when 'cin7' then 'Before IMS' else c.source end,
      'created_at', to_char(c.created_at at time zone 'America/Toronto', 'YYYY-MM-DD'), 'reviewed_at', to_char(c.reviewed_at at time zone 'America/Toronto', 'YYYY-MM-DD'))
      || jsonb_build_object(
      'billing_line1', a.b_line1, 'billing_line2', a.b_line2, 'billing_city', a.b_city, 'billing_province', a.b_prov, 'billing_postal', a.b_postal, 'billing_country', a.b_country,
      'shipping_line1', a.s_line1, 'shipping_line2', a.s_line2, 'shipping_city', a.s_city, 'shipping_province', a.s_prov, 'shipping_postal', a.s_postal, 'shipping_country', a.s_country,
      'contact_name', t.name, 'contact_phone', t.phone, 'contact_mobile', t.mobile_phone, 'contact_email', t.email,
      'contact_marketing', case t.marketing_consent when true then 'Opt in' when false then 'Opt out' else case when t.customer_id is null then null else 'Unknown' end end) as j
    from pick c
    left join public.customer par on par.id = c.parent_id
    left join public.customer bto on bto.id = c.default_bill_to_customer_id
    left join ad a on a.customer_id = c.id
    left join ct t on t.customer_id = c.id
  )
  select (select count(*) from base),
         coalesce(jsonb_agg((select jsonb_agg(f.j -> u.k order by u.o) from unnest(v_keys) with ordinality u(k, o)) order by f.name, f.id), '[]'::jsonb)
    into v_total, v_rows from full_ f;
  return jsonb_build_object('kind', 'customer', 'total', v_total, 'row_count', jsonb_array_length(v_rows), 'truncated', v_total > 20000,
                            'columns', v_cols, 'rows', v_rows);
end $$;
comment on function public.customer_export(text, boolean, boolean, text[]) is 'exp-1 판정 699 · 700 · 761 · 762 · 763 — 손님 내보내기: customers.html 의 거르기(검색 = 이름 · 표시 이름 · Active only · New — not reviewed) + p_columns → {kind, total, row_count, truncated, columns, rows} · 순서 name · 주소 = 기본 Billing · 기본 Shipping · 연락처 = 기본 · 주소 · 연락처 칸은 sales 쓰기 ∨ master 쓰기만(761)';

-- ═══ ⑤-4 공급처 — suppliers.html baseQuery 의 거르기 그대로 · 읽기 직원은 고정 거르기 · 순서 name ═══
create function public.supplier_export(p_q text default null, p_only_active boolean default true, p_hide_discontinued boolean default false,
                                       p_purchasable text default 'all', p_columns text[] default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_q text := nullif(btrim(p_q), ''); v_cols jsonb; v_keys text[]; v_total bigint; v_rows jsonb;
        v_writer boolean := public.ims_can_write('master') or public.ims_can_write('purchasing'); v_p text := coalesce(p_purchasable, 'all');
begin
  if v_p not in ('all', 'yes', 'no', 'unset') then raise exception 'p_purchasable must be all, yes, no or unset'; end if;
  select jsonb_agg(jsonb_build_object('key', k.key, 'label', k.label, 'text', k.is_text) order by k.o), array_agg(k.key order by k.o)
    into v_cols, v_keys from public.export_pick('supplier', p_columns) k;
  with base as (
    select s.* from public.supplier s
    where case when not v_writer then s.is_active and s.is_purchasable is true and s.is_discontinued is false        -- suppliers.html:161 과 같다 — 창구가 강제
               else (not coalesce(p_only_active, false) or s.is_active)
                and (not coalesce(p_hide_discontinued, false) or s.is_discontinued is false)
                and (v_p = 'all' or (v_p = 'yes' and s.is_purchasable is true) or (v_p = 'no' and s.is_purchasable is false) or (v_p = 'unset' and s.is_purchasable is null)) end
      and (v_q is null or s.name ilike '%' || v_q || '%')
  ),
  pick as materialized (select * from base order by name, id limit 20000),
  ad as (select distinct on (a.supplier_id) a.* from public.supplier_address a where a.is_active and a.supplier_id in (select id from pick)
         order by a.supplier_id, case a.type when 'Billing' then 1 when 'Business' then 2 else 3 end, a.created_at, a.id),
  ct as (select t.* from public.supplier_contact t where t.is_active and t.is_default and t.supplier_id in (select id from pick)),
  dc as (select d.supplier_id, string_agg(coalesce(d.name, 'Discount') || ' ' || trim(trailing '.' from trim(trailing '0' from d.percent::text)) || '%', '; ' order by d.seq) v
         from public.supplier_discount d where d.is_active and d.supplier_id in (select id from pick) group by 1),
  full_ as materialized (                -- 한 번만 만든다 — 그냥 두면 고른 칸마다 jsonb 를 다시 만들어 손님 전 칸이 16 초였다(exp-1 시험 3 회차)
    select s.name, s.id, jsonb_build_object(
      'name', s.name, 'is_active', s.is_active, 'purchasable', case s.is_purchasable when true then 'Yes' when false then 'No' else 'Not set' end,
      'is_discontinued', s.is_discontinued, 'currency', cu.code, 'payment_term', s.payment_term_name, 'account_payable', s.account_payable_code,
      'tax_rule', s.tax_rule, 'discounts', dc.v, 'source', case s.source when 'manual' then 'IMS' when 'cin7' then 'Before IMS' else s.source end,
      'created_at', to_char(s.created_at at time zone 'America/Toronto', 'YYYY-MM-DD'),
      'address_line1', a.line1, 'address_line2', a.line2, 'address_city', a.city, 'address_province', a.state_province, 'address_postal', a.postal_code, 'address_country', a.country,
      'contact_name', t.name, 'contact_phone', t.phone, 'contact_mobile', t.mobile_phone, 'contact_email', t.email) as j
    from pick s
    left join public.ref_currency cu on cu.id = s.currency_id
    left join ad a on a.supplier_id = s.id left join ct t on t.supplier_id = s.id left join dc on dc.supplier_id = s.id
  )
  select (select count(*) from base),
         coalesce(jsonb_agg((select jsonb_agg(f.j -> u.k order by u.o) from unnest(v_keys) with ordinality u(k, o)) order by f.name, f.id), '[]'::jsonb)
    into v_total, v_rows from full_ f;
  return jsonb_build_object('kind', 'supplier', 'total', v_total, 'row_count', jsonb_array_length(v_rows), 'truncated', v_total > 20000,
                            'forced_filter', not v_writer, 'columns', v_cols, 'rows', v_rows);
end $$;
comment on function public.supplier_export(text, boolean, boolean, text, text[]) is 'exp-1 판정 699 · 700 · 762 · 763 · 이견 4 — 공급처 내보내기: suppliers.html 의 거르기(검색 · Active only · Hide discontinued · Purchasable all|yes|no|unset) + p_columns → {kind, total, row_count, truncated, forced_filter, columns, rows} · 읽기 직원(master · purchasing 쓰기 없음)은 켜짐 · purchasable · 단종 아님 고정(forced_filter true · 넘긴 거르기는 무시) · 순서 name · 주소 = Billing → Business → Shipping 첫 줄 · 연락처 = 기본 · 할인 = 이름 n%';

-- ═══ 권한 — 속 함수 넷은 아무도 못 부른다 · 창구 넷은 authenticated 만 ═══
revoke all on function public.export_catalog(text) from public, anon, authenticated, service_role;
revoke all on function public.export_door(text) from public, anon, authenticated, service_role;
revoke all on function public.export_gate_ok(text) from public, anon, authenticated, service_role;
revoke all on function public.export_pick(text, text[]) from public, anon, authenticated, service_role;
revoke all on function public.export_columns(text) from public, anon, service_role;
revoke all on function public.product_export(text, text, text, uuid, text, boolean, boolean, text[]) from public, anon, service_role;
revoke all on function public.customer_export(text, boolean, boolean, text[]) from public, anon, service_role;
revoke all on function public.supplier_export(text, boolean, boolean, text, text[]) from public, anon, service_role;
grant execute on function public.export_columns(text) to authenticated;
grant execute on function public.product_export(text, text, text, uuid, text, boolean, boolean, text[]) to authenticated;
grant execute on function public.customer_export(text, boolean, boolean, text[]) to authenticated;
grant execute on function public.supplier_export(text, boolean, boolean, text, text[]) to authenticated;

-- ═══ 착지 ═══
do $$
declare v_bad text := ''; r record;
begin
  for r in select p.oid, p.proname, p.prosecdef, p.provolatile from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('export_catalog', 'export_door', 'export_gate_ok', 'export_pick', 'export_columns', 'product_export', 'customer_export', 'supplier_export') loop
    if not r.prosecdef then v_bad := v_bad || ' ' || r.proname || ':not_definer'; end if;
    if r.provolatile <> 's' then v_bad := v_bad || ' ' || r.proname || ':not_stable'; end if;
    if has_function_privilege('anon', r.oid, 'execute') then v_bad := v_bad || ' ' || r.proname || ':anon'; end if;
    if has_function_privilege('authenticated', r.oid, 'execute') <> (r.proname in ('export_columns', 'product_export', 'customer_export', 'supplier_export')) then
      v_bad := v_bad || ' ' || r.proname || ':authenticated'; end if;
  end loop;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('export_catalog', 'export_door', 'export_gate_ok', 'export_pick', 'export_columns', 'product_export', 'customer_export', 'supplier_export')) <> 8 then
    v_bad := v_bad || ' count'; end if;
  if exists (select 1 from public.export_catalog('product') c join public.ref_price_tier t on c.key = 'price_' || t.code where t.purpose = 'reference') then v_bad := v_bad || ' reference_tier'; end if;
  if (select count(*) from public.export_catalog('product') where gate = 'cost') <> 2 then v_bad := v_bad || ' cost_gate'; end if;
  if (select count(*) from public.export_catalog('customer') where gate = 'contact') <> 17 then v_bad := v_bad || ' contact_gate'; end if;
  if (select count(*) from (select key from public.export_catalog('product') union all select key from public.export_catalog('customer') union all select key from public.export_catalog('supplier')) x) <>
     (select count(*) from (select distinct 'p' || key from public.export_catalog('product') union all select distinct 'c' || key from public.export_catalog('customer') union all select distinct 's' || key from public.export_catalog('supplier')) y) then
    v_bad := v_bad || ' dup_key'; end if;
  if v_bad <> '' then raise exception 'exp-1 landing failed:%', v_bad; end if;
  raise notice 'exp-1 landed: 8 functions definer stable · 4 callable by authenticated · anon none · reference tier absent · cost gate 2 · contact gate 17';
end $$;
