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

-- ═══ pur-1b — pur_sales_daily 「공급처 비우면 전부」 (2026-10-22 · 판정 604 · 616 · pur-1 뒤) ═══
--   발주앱 loadSalesDataFromBQ 는 전 공급처의 판매를 한 번에 읽는다(aduSQL · seaSQL · deadSQL 에 공급처 거르기 없음) — pur-1 의 pur_sales_daily 는 p_supplier_id null 을 거부했다 ⇒ 화면이 공급처마다 부르게 된다(맞지 않다)
--   재발행 하나: p_supplier_id null = 공급처로 거르지 않는다(모든 낱개 · 세트 × 계수 · 콤보 구성품 · 기본 공급처 없는 낱개 포함 = aduSQL 과 같은 뜻) · 값이 있는데 없는 공급처면 그대로 거부 · 서명 · grant · 나머지 바이트 무변
--   원본 = 20261022133010_pur_1_purchasing_db.sql:121 (DB prosrc md5 ba77908a49cf561a2d2d100340db81c3) · 바뀐 줄 둘 + 머리말 한 줄 · 새 md5 c295855d253d95549dfcbd515a9ac831
create or replace function public.pur_sales_daily(p_supplier_id uuid, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer as $$
-- 판정 604 · 605: IMS 판매(경계 날짜부터) · 일별 · 낱개 · aduSQL 모양 {sku, sale_date, qty} · qty > 0 줄만 · 기준 = 발행된(취소 안 된) 인보이스의 제품 줄 · 날짜 = 발행일(BigQuery 뷰 sale_date = invoice_date 와 같은 축) ·
--   세트 줄 = qty × 그 줄의 pack_factor → 낱개 · 콤보 줄 = combo_components 구성품마다(구성품이 세트면 또 × 계수) · 반품 · 크레딧은 안 뺀다(BigQuery Quantity > 0 과 같다) · 서비스 · 운임 · 세금 줄은 kind 로 빠진다 ·
--   공급처 거르기 = 낱개의 기본 공급처(is_default · 활성 줄) = pur_supplier_skus 와 같은 뜻 · p_supplier_id null = 전부(pur-1b · 기본 공급처 없는 낱개 포함) · 구간 [from, to) · from 은 경계 밑으로 못 내려간다(경계 전은 BigQuery 몫) · to 기본 = 오늘 + 1(오늘 포함 · aduSQL 의 < 오늘 은 화면이 건다)
declare
  v_bound date;  v_from date;  v_to date;  v_rows jsonb;  v_n int;
begin
  perform public.pur_staff(false);
  if p_supplier_id is not null and not exists (select 1 from public.supplier s where s.id = p_supplier_id) then raise exception 'Supplier not found — nothing was read'; end if;   -- pur-1b: null = 공급처로 거르지 않는다(발주앱 aduSQL · seaSQL · deadSQL 은 전 공급처를 한 번에 읽는다)
  select c.value::date into v_bound from public.inv_config c where c.key = 'pur_ims_sales_from';
  if v_bound is null then raise exception 'inv_config.pur_ims_sales_from is missing — a migration seeds it — nothing was read'; end if;
  v_from := greatest(coalesce(p_from, v_bound), v_bound);
  v_to := coalesce(p_to, public.ims_today() + 1);                                                      -- 기본 = 오늘까지(오늘 포함) · 화면이 창(90 일 · 작년 철 · 365 · 3 년)을 건다
  with il as (
    select il.qty, il.pack_factor, il.combo_components, i.issued_on, coalesce(sl.product_id, (select p.id from public.product p where p.sku = il.sku)) as product_id
    from public.so_invoice_line il
    join public.so_invoice i on i.id = il.invoice_id and i.status = 'issued' and i.cancelled_at is null
    join public.so_invoice_order io on io.id = il.invoice_order_id and io.cancelled_at is null
    left join public.so_line sl on sl.id = il.so_line_id
    where il.kind = 'product' and il.qty > 0 and i.issued_on >= v_from and i.issued_on < v_to
  ),
  ex as (
    select il.issued_on, b.base_product_id, b.base_sku, il.qty * case when b.factor <> 1 then coalesce(il.pack_factor, b.factor) else 1 end as qty
    from il cross join lateral public.pur_base(il.product_id) b where il.combo_components is null
    union all
    select il.issued_on, b.base_product_id, b.base_sku, (c->>'qty')::numeric * b.factor
    from il cross join lateral jsonb_array_elements(il.combo_components) c cross join lateral public.pur_base((c->>'product_id')::uuid) b
    where il.combo_components is not null
  ),
  d as (
    select ex.base_sku as sku, ex.issued_on as sale_date, sum(ex.qty) as qty
    from ex
    where p_supplier_id is null or exists (select 1 from public.product_supplier ps where ps.product_id = ex.base_product_id and ps.supplier_id = p_supplier_id and ps.is_active and ps.is_default)   -- pur-1b: null 이면 기본 공급처 없는 낱개도(aduSQL 과 같은 뜻)
    group by ex.base_sku, ex.issued_on having sum(ex.qty) > 0
  )
  select coalesce(jsonb_agg(jsonb_build_object('sku', d.sku, 'sale_date', d.sale_date, 'qty', d.qty) order by d.sku, d.sale_date), '[]'::jsonb), count(*) into v_rows, v_n from d;
  return jsonb_build_object('supplier_id', p_supplier_id, 'from', v_from, 'to', v_to, 'boundary', v_bound, 'row_count', v_n, 'rows', v_rows);
end $$;
comment on function public.pur_sales_daily(uuid, date, date) is 'pur-1 판정 604 · 605 — 발주앱 판매(IMS · 경계 날짜부터) · 일별 · 낱개 · {sku, sale_date, qty} · p_supplier_id null = 전부(pur-1b) · 문 = purchasing 보기';

-- ═══ 착지 — 몸 md5 · 오버로드 하나 · ACL 무변(authenticated · service_role X · anon 없음) ═══
do $$
declare v_bad text := '';  v_acl text;
begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_sales_daily') <> 1 then v_bad := v_bad || ' overloads'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_sales_daily') <> 'c295855d253d95549dfcbd515a9ac831' then v_bad := v_bad || ' body'; end if;
  select p.proacl::text into v_acl from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_sales_daily';
  if not has_function_privilege('authenticated', 'public.pur_sales_daily(uuid, date, date)', 'execute') or not has_function_privilege('service_role', 'public.pur_sales_daily(uuid, date, date)', 'execute')
     or has_function_privilege('anon', 'public.pur_sales_daily(uuid, date, date)', 'execute') or v_acl ~ 'anon=' then v_bad := v_bad || ' acl:' || coalesce(v_acl, '-'); end if;
  if not (select p.prosecdef from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_sales_daily') then v_bad := v_bad || ' not_definer'; end if;
  if v_bad <> '' then raise exception 'pur-1b landing check failed:%', v_bad; end if;
end $$;
