-- supabase/migrations/20261108165000_pbc_1_product_search_barcode.sql — pbc-1: Products 검색에 바코드 (2026-11-08 밤 · 지시서 ~/asung/prompts/pbc-1.md · 판정 1111 · 동료 요청 「제품 검색에 바코드도」)
--   무엇: product_list · product_export 의 검색어 p_q 가 SKU · 이름(지금처럼 ilike %q%) **또는 활성 바코드와 통째로 같음**이면 맞는다 — 바코드 일부 일치는 하지 않는다(숫자 몇 자리로 수백 개가 섞이고 SKU 결과와 뒤엉킨다 · 스캐너는 늘 통째로)
--   케이스(세트) 바코드: 그 바코드가 세트(parent_product_id 있음)의 것이면 그 세트와 그 낱개(부모) 둘 다 후보 → p_kind 가 거른다 — 'single' 보기 = 낱개(부모) · 'set' = 세트 · 'all' = 둘 · 낱개 바코드는 그 낱개만(세트는 따라오지 않는다)
--   꼴: or p.id in (활성 바코드 = v_q 인 product_id ∪ 그 제품이 세트면 parent_product_id) — 색인 product_barcode_barcode_idx · hashed subplan 한 번(행마다 아님 · explain 실측 9 버퍼) · v_q null 이면 안 돈다(or 앞 가지 · 검색어 없는 첫 화면 시간 무변)
--   바코드 비교는 btrim 한 검색어 그대로(숫자 — 대소문자 무관 필요 없음 · 가운데 띄어쓰기가 든 바코드 27 줄은 그 글자 그대로만 맞는다)
--   무변: 시그니처 · 반환 꼴 · product_list invoker · product_export definer · stable · search_path · acl · comment(지시서 §0) · 거르기 나머지 여섯 · 순서 · 한도 — 끼운 것은 조건 한 가지(+ 주석) 뿐 · 마지막 정의 = product_list sale-1(20261007202707) · product_export exp-1(20261026162607)
--   번호: 다른 창의 mcp-conc-1 = 20261108160000(만들 때 schema_migrations 마지막 = 20261108160000 실측 · 적용됨) · qbo-sync-3-2a = 20261108170000(미적용) — 이 파일은 그 사이 165000(적용 순서 mcp-conc-1 → pbc-1 → 3-2a)
--   화면(products.html 안내 글)은 대화 Claude 가 DB 적용 뒤에 쓴다 — 이 파일은 DB 만
--   적용(Caleb · IMS 메인 fazgmyvzzhqybtvtktyg): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '2s'" -f supabase/migrations/20261108165000_pbc_1_product_search_barcode.sql && supabase migration repair --status applied 20261108165000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · begin → rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261108165000_pbc_1_product_search_barcode.sql -f supabase/tests/pbc_1_check.sql   (적용 뒤 · Caleb: -v mig 없이 같은 명령)

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

-- ═══ 0) 바탕 확인 — 지금 product_list 가 sale-1 판(본문 md5 b2c61a75fc163b6f45ac85ebe34fd53d) · product_export 가 exp-1 판(md5 4d5de98da5e0d57ad9cb0be8c7eed2d0) 한 벌씩인지 · 아니면 멈춘다(diff 의 바탕이 다르다) ═══
do $$
declare v_n int; v_md5 text;
begin
  select count(*), min(md5(p.prosrc)) into v_n, v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_list';
  if v_n <> 1 or v_md5 <> 'b2c61a75fc163b6f45ac85ebe34fd53d' then
    raise exception 'pbc-1: product_list is not the single sale-1 version (count %, md5 %) — stop, nothing was changed', v_n, coalesce(v_md5, '(none)');
  end if;
  select count(*), min(md5(p.prosrc)) into v_n, v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_export';
  if v_n <> 1 or v_md5 <> '4d5de98da5e0d57ad9cb0be8c7eed2d0' then
    raise exception 'pbc-1: product_export is not the single exp-1 version (count %, md5 %) — stop, nothing was changed', v_n, coalesce(v_md5, '(none)');
  end if;
end $$;

-- ═══ 1) product_list — sale-1(20261007202707) 마지막 정의 그대로 + 끼운 조건(create or replace 라 acl · comment 는 남는다) ═══
create or replace function public.product_list(
  p_q           text    default null,                                                    -- sku 또는 name ilike %q%(화면 .or(sku.ilike,name.ilike)) · pbc-1: 또는 활성 바코드와 통째로 같음(판정 1111)
  p_brand_name  text    default null,                                                    -- 화면 .eq("brand_name")
  p_category_name text  default null,                                                    -- 화면 .eq("category_name")
  p_supplier_id uuid    default null,                                                    -- 화면 product_supplier!inner(supplier_id · is_active) — 판정 151
  p_kind        text    default null,                                                    -- 'single' = 낱개(parent null) · 'set' = 세트 · null · 'all' = 전부
  p_only_active boolean default false,                                                   -- 화면 .eq("is_active", true)
  p_sale_only   boolean default false,                                                   -- sale-1 판정 361: 오늘 세일하는 제품만
  p_limit       int     default 100,
  p_offset      int     default 0
) returns table (
  id uuid, sku text, name text, is_active boolean, parent_product_id uuid, pack_factor numeric, brand_name text, category_name text,   -- 화면 cols 그대로
  sale_pct numeric, sale_conditional boolean,                                                                                        -- sale-1
  total bigint
)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_q      text := nullif(btrim(p_q), '');
  v_limit  int  := least(greatest(coalesce(p_limit, 100), 1), 1000);
  v_offset int  := greatest(coalesce(p_offset, 0), 0);
begin
  if p_kind is not null and p_kind not in ('single', 'set', 'all') then raise exception 'p_kind must be single, set or all'; end if;
  return query
  with sale as (select z.product_id, z.best_pct, z.conditional from public.so_sale_now(null, null) z)
  select p.id, p.sku, p.name, p.is_active, p.parent_product_id, p.pack_factor, p.brand_name, p.category_name,
         sale.best_pct, sale.conditional,
         count(*) over () as total
  from public.product p
  left join sale on sale.product_id = p.id
  where (not p_only_active or p.is_active)
    and (p_kind is null or p_kind = 'all' or (p_kind = 'single' and p.parent_product_id is null) or (p_kind = 'set' and p.parent_product_id is not null))
    and (p_brand_name is null or p.brand_name = p_brand_name)
    and (p_category_name is null or p.category_name = p_category_name)
    and (v_q is null or p.sku ilike '%' || v_q || '%' or p.name ilike '%' || v_q || '%'
         -- pbc-1(판정 1111): 활성 바코드와 통째로 같음(일부 일치 없음 — 스캐너는 늘 통째로) · 세트 바코드면 그 세트와 그 낱개(부모) 둘 다 후보 → p_kind 가 거른다(single = 부모 · set = 세트 · all = 둘)
         --   v_q null 이면 안 돈다(or 앞 가지에서 끝) · 색인 product_barcode_barcode_idx · hashed subplan 한 번(행마다 아님) · 검색어는 btrim 만(숫자 — 대소문자 무관 필요 없음)
         or p.id in (select b.product_id from public.product_barcode b where b.is_active and b.barcode = v_q
                     union all
                     select s.parent_product_id from public.product_barcode b join public.product s on s.id = b.product_id
                      where b.is_active and b.barcode = v_q and s.parent_product_id is not null))
    and (p_supplier_id is null or exists (select 1 from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = p_supplier_id and ps.is_active))
    and (not p_sale_only or sale.product_id is not null)
  order by p.sku, p.id
  limit v_limit offset v_offset;
end $$;

-- ═══ 2) product_export — exp-1(20261026162607) 마지막 정의 그대로 + 끼운 조건($1 = v_q · format 안이라 %% 는 건드리지 않았다) ═══
create or replace function public.product_export(p_q text default null, p_brand_name text default null, p_category_name text default null, p_supplier_id uuid default null,
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
  -- pbc-1(판정 1111): $1 조건에 「활성 바코드와 통째로 같음」 — product_list 와 같은 규칙 · 같은 글(세트 바코드 → 세트 + 낱개 부모 둘 다 후보 · $5 가 거른다 · $1 null 이면 안 돈다 · 색인 product_barcode_barcode_idx)
  execute format($q$
    with sale as (select z.product_id, z.best_pct from public.so_sale_now(null, null) z where $7 or $8),
    base as materialized (
      select p.*, sale.best_pct from public.product p left join sale on sale.product_id = p.id
      where (not $6 or p.is_active)
        and ($5 is null or $5 = 'all' or ($5 = 'single' and p.parent_product_id is null) or ($5 = 'set' and p.parent_product_id is not null))
        and ($2 is null or p.brand_name = $2)
        and ($3 is null or p.category_name = $3)
        and ($1 is null or p.sku ilike '%%' || $1 || '%%' or p.name ilike '%%' || $1 || '%%'
             or p.id in (select b.product_id from public.product_barcode b where b.is_active and b.barcode = $1
                         union all
                         select s.parent_product_id from public.product_barcode b join public.product s on s.id = b.product_id where b.is_active and b.barcode = $1 and s.parent_product_id is not null))
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

-- ═══ 3) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; r record; v_t text;
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('product_list', 'product_export')) <> 2 then v_bad := v_bad || ' count'; end if;
  select p.prosecdef, p.proconfig, p.provolatile, p.proacl::text acl, obj_description(p.oid, 'pg_proc') cmt, p.prosrc, pg_get_function_result(p.oid) res, pg_get_function_identity_arguments(p.oid) args
    into r from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_list';
  if r.prosecdef then v_bad := v_bad || ' list(definer)'; end if;
  if r.provolatile <> 's' then v_bad := v_bad || ' list(not-stable)'; end if;
  if array_to_string(r.proconfig, ',') <> 'search_path=public, pg_temp' then v_bad := v_bad || ' list(search_path)'; end if;
  if r.args <> 'p_q text, p_brand_name text, p_category_name text, p_supplier_id uuid, p_kind text, p_only_active boolean, p_sale_only boolean, p_limit integer, p_offset integer' then v_bad := v_bad || ' list(args)'; end if;
  if r.res <> 'TABLE(id uuid, sku text, name text, is_active boolean, parent_product_id uuid, pack_factor numeric, brand_name text, category_name text, sale_pct numeric, sale_conditional boolean, total bigint)' then v_bad := v_bad || ' list(result)'; end if;
  if r.acl <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then v_bad := v_bad || format(' list(acl %s)', r.acl); end if;
  if r.cmt not like '⭐ 제품 목록 한 쪽(sale-1 · 판정 361 · 2026-10-07)%limit ≤ 1000' then v_bad := v_bad || ' list(comment)'; end if;
  if r.prosrc not like '%b.is_active and b.barcode = v_q%' or r.prosrc not like '%s.parent_product_id is not null))%' then v_bad := v_bad || ' list(body)'; end if;
  select p.prosecdef, p.proconfig, p.provolatile, p.proacl::text acl, obj_description(p.oid, 'pg_proc') cmt, p.prosrc, pg_get_function_result(p.oid) res, pg_get_function_identity_arguments(p.oid) args
    into r from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_export';
  if not r.prosecdef then v_bad := v_bad || ' export(invoker)'; end if;
  if r.provolatile <> 's' then v_bad := v_bad || ' export(not-stable)'; end if;
  if array_to_string(r.proconfig, ',') <> 'search_path=public, pg_temp' then v_bad := v_bad || ' export(search_path)'; end if;
  if r.args <> 'p_q text, p_brand_name text, p_category_name text, p_supplier_id uuid, p_kind text, p_only_active boolean, p_sale_only boolean, p_columns text[]' then v_bad := v_bad || ' export(args)'; end if;
  if r.res <> 'jsonb' then v_bad := v_bad || ' export(result)'; end if;
  if r.acl <> '{postgres=X/postgres,authenticated=X/postgres}' then v_bad := v_bad || format(' export(acl %s)', r.acl); end if;
  if r.cmt not like 'exp-1 판정 699 · 700 · 759 · 760 · 762 · 763%원가 열쇠일 때만(759)' then v_bad := v_bad || ' export(comment)'; end if;
  if r.prosrc not like '%b.is_active and b.barcode = $1%' or r.prosrc not like '%b.barcode = $1 and s.parent_product_id is not null))%' then v_bad := v_bad || ' export(body)'; end if;
  foreach v_t in array array['public.product_list(text, text, text, uuid, text, boolean, boolean, int, int)', 'public.product_export(text, text, text, uuid, text, boolean, boolean, text[])'] loop
    if has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(anon)', v_t); end if;
    if not has_function_privilege('authenticated', v_t, 'execute') then v_bad := v_bad || format(' %s(no-authenticated)', v_t); end if;
  end loop;
  if v_bad <> '' then
    raise exception using errcode = 'IM111', message = format('STOP - pbc-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
