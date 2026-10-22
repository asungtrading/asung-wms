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

-- ═══ pur-1 — 발주앱 이식 · DB(읽기 창구 · 경계 날짜 · 설정 표) (2026-10-22 · 판정 604 ~ 606 · 608 · 615 · pur-0) ═══
--   ① 경계 날짜 inv_config.pur_ims_sales_from(기본 2026-11-01 · 마이그레이션 · psql 만 바꾼다 — ims_config_set 은 이 키를 모르니 「a migration or psql changes this」 로 거부 · 화면은 읽기만)
--   ② 읽기 창구 넷(definer · 첫 줄 문 = ims_can_view('purchasing') · 판정 582):
--      pur_sales_daily(supplier, from, to)  발행된 인보이스 제품 줄 → 낱개(base) · 일별 · qty > 0 · [from, to) · from 은 경계 밑으로 못 내려간다 · 세트 × 계수 · 콤보 = 구성품(판정 605) · 반품(크레딧)은 안 뺀다(BigQuery 뷰 Quantity > 0 과 같은 기준)
--      pur_backorders(supplier)             열린 백오더(so_reserve backorder · 미해제) · 창고 채널 · 무상 줄 제외 · 「진짜 수요 아님」 표식(so_demand_flag) · 되돌린 오더(so_demand_so_excluded) 제외 · 오더 날 90 일 · 손님 × 낱개 SKU 최신 1 건 · 0-30 · 30-60 · 60-90(boSQL 과 같은 뜻)
--      pur_supplier_skus(supplier)          활성 제품 + 기본 공급처(is_default · 활성 줄) — supplierSkuSQL 모양 + supplier_id
--      pur_set_map()                        세트(parent_product_id · pack_factor) · 콤보(product_bom 구성품마다 × 수량 × 구성품 계수) · 활성 · 비활성 모두 — 화면이 경계 전 BigQuery 판매를 낱개로 접는다
--   ③ 설정 표 넷(판정 606 · 615: 권한은 여기서 직접 · anon · authenticated 에게 아무것도 안 준다 · 창구로만): pur_supplier_setting · pur_setting(wma) · pur_sku_link · pur_override_history
--      읽기 pur_settings(supplier) = purchasing 보기 · 쓰기 다섯 = purchasing 쓰기 · 기본값(30 · 60 · 30 · 0 · 3 · 2 · 1)은 창구가 돌려준다 · 옮겨 담기 pur_settings_import(p, commit) = localStorage 네 열쇠 JSON 그대로(공급처 이름 → id · 못 찾은 이름은 목록으로 · 두 번 불러도 같다)
--   재고(⑥)는 새 창구 없음 · 원가(608)는 stk_value_many 가 열쇠 없는 사람을 거부한다(판정 567 · 575 그대로)

-- ═══ ① 경계 날짜 ═══
insert into public.inv_config (key, value) values ('pur_ims_sales_from', '2026-11-01') on conflict (key) do nothing;

-- ═══ ③ 설정 표 넷 ═══
create table public.pur_supplier_setting (
  supplier_id uuid primary key references public.supplier(id),
  lead_time   int not null check (lead_time >= 0),
  target      int not null check (target >= 0),
  cycle       int not null check (cycle >= 1),
  lt_sigma    int not null default 0 check (lt_sigma >= 0),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.ims_staff(id)
);
comment on table public.pur_supplier_setting is 'pur-1 판정 606 — 발주앱 공급처 설정(리드타임 · 목표 일수 · 주기 · 리드타임 편차 · 옛 localStorage asung_po_v5) · 창구로만(pur_settings · pur_supplier_setting_set · pur_settings_import) · 행이 없으면 창구가 기본 30 · 60 · 30 · 0 을 돌려준다';
create table public.pur_setting (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.ims_staff(id)
);
comment on table public.pur_setting is 'pur-1 판정 606 — 발주앱 회사 설정(key wma = {"w1","w2","w3"} 가중치 1 ~ 10 · 옛 localStorage asung_wma) · 창구로만 · 행이 없으면 기본 3 · 2 · 1';
create table public.pur_sku_link (
  id         uuid primary key default gen_random_uuid(),
  old_sku    text not null check (old_sku = upper(btrim(old_sku)) and old_sku <> ''),
  new_sku    text not null check (new_sku = upper(btrim(new_sku)) and new_sku <> ''),
  created_at timestamptz not null default now(),
  created_by uuid references public.ims_staff(id),
  unique (old_sku, new_sku),
  check (old_sku <> new_sku)
);
comment on table public.pur_sku_link is 'pur-1 판정 606 — 발주앱 SKU 연결(옛 SKU 의 판매를 새 SKU 에 더한다 · 옛 localStorage asung_sku_links) · 대문자 · 앞뒤 공백 없음 · 창구로만';
create table public.pur_override_history (
  id          uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.supplier(id),
  key         text not null check (key in ('sea', 'trd')),
  value       numeric,                                                   -- null = auto(초기화)
  set_on      date not null default public.ims_today(),
  set_by      uuid references public.ims_staff(id),
  created_at  timestamptz not null default clock_timestamp()                           -- 같은 트랜잭션 안의 두 건도 순서가 갈리게(now() 는 트랜잭션 안에서 같다)
);
create index pur_override_history_sup_key_idx on public.pur_override_history (supplier_id, key, set_on desc, created_at desc);
comment on table public.pur_override_history is 'pur-1 판정 606 — 발주앱 오버라이드(계절 sea · 트렌드 trd) 변경 이력 · 공급처마다 · value null = auto · 옛 localStorage asung_ov_history({공급처: {sea: [{v, d}], trd: [...]}}) · 창구가 최근 10 건을 돌려준다';

-- 판정 615: 기본 권한에 기대지 않는다 — 넷 다 anon · authenticated · public 에게 아무것도 · service_role 전부 · RLS 켬(정책 없음 = authenticated 는 창구로만)
do $$
declare t text;
begin
  foreach t in array array['pur_supplier_setting', 'pur_setting', 'pur_sku_link', 'pur_override_history'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant select, insert, update, delete, truncate, references, trigger, maintain on table public.%I to service_role', t);
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ═══ ② 도우미 — 낱개(base) 찾기 · 기본값 · 직원 ═══
create function public.pur_base(p_product_id uuid) returns table (base_product_id uuid, base_sku text, factor numeric)
language sql stable as $$
  select coalesce(b.id, p.id), coalesce(b.sku, p.sku), case when p.parent_product_id is not null then coalesce(p.pack_factor, 1) else 1 end
  from public.product p left join public.product b on b.id = p.parent_product_id
  where p.id = p_product_id
$$;
revoke all on function public.pur_base(uuid) from public, anon, authenticated;
comment on function public.pur_base(uuid) is 'pur-1 — 제품 → 낱개(base) 제품 · SKU · 계수(세트면 parent_product_id · pack_factor · 아니면 자기 자신 · 1) · 속 도우미(실행권 없음)';

create function public.pur_defaults() returns jsonb language sql immutable as $$
  select '{"leadtime": 30, "target": 60, "cycle": 30, "lt_sigma": 0, "w1": 3, "w2": 2, "w3": 1}'::jsonb
$$;
revoke all on function public.pur_defaults() from public, anon;
grant execute on function public.pur_defaults() to authenticated, service_role;

create function public.pur_staff(p_write boolean) returns uuid language plpgsql stable as $$
declare v_id uuid;
begin
  select s.id into v_id from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_id is null then raise exception 'You are not registered as active staff — nothing was %', case when p_write then 'saved' else 'read' end; end if;
  if p_write and not public.ims_can_write('purchasing') then raise exception 'You cannot change purchasing settings — ask an admin for the ''purchasing'' permission — nothing was saved'; end if;
  if not p_write and not public.ims_can_view('purchasing') then raise exception 'You cannot view purchasing data — ask an admin for the ''purchasing'' permission — nothing was read'; end if;
  return v_id;
end $$;
revoke all on function public.pur_staff(boolean) from public, anon, authenticated;

-- ═══ ② 읽기 창구 넷 ═══
create function public.pur_sales_daily(p_supplier_id uuid, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer as $$
-- 판정 604 · 605: IMS 판매(경계 날짜부터) · 일별 · 낱개 · aduSQL 모양 {sku, sale_date, qty} · qty > 0 줄만 · 기준 = 발행된(취소 안 된) 인보이스의 제품 줄 · 날짜 = 발행일(BigQuery 뷰 sale_date = invoice_date 와 같은 축) ·
--   세트 줄 = qty × 그 줄의 pack_factor → 낱개 · 콤보 줄 = combo_components 구성품마다(구성품이 세트면 또 × 계수) · 반품 · 크레딧은 안 뺀다(BigQuery Quantity > 0 과 같다) · 서비스 · 운임 · 세금 줄은 kind 로 빠진다 ·
--   공급처 거르기 = 낱개의 기본 공급처(is_default · 활성 줄) = pur_supplier_skus 와 같은 뜻 · 구간 [from, to) · from 은 경계 밑으로 못 내려간다(경계 전은 BigQuery 몫) · to 기본 = 오늘 + 1(오늘 포함 · aduSQL 의 < 오늘 은 화면이 건다)
declare
  v_bound date;  v_from date;  v_to date;  v_rows jsonb;  v_n int;
begin
  perform public.pur_staff(false);
  if p_supplier_id is null or not exists (select 1 from public.supplier s where s.id = p_supplier_id) then raise exception 'Supplier not found — nothing was read'; end if;
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
    where exists (select 1 from public.product_supplier ps where ps.product_id = ex.base_product_id and ps.supplier_id = p_supplier_id and ps.is_active and ps.is_default)
    group by ex.base_sku, ex.issued_on having sum(ex.qty) > 0
  )
  select coalesce(jsonb_agg(jsonb_build_object('sku', d.sku, 'sale_date', d.sale_date, 'qty', d.qty) order by d.sku, d.sale_date), '[]'::jsonb), count(*) into v_rows, v_n from d;
  return jsonb_build_object('supplier_id', p_supplier_id, 'from', v_from, 'to', v_to, 'boundary', v_bound, 'row_count', v_n, 'rows', v_rows);
end $$;
revoke all on function public.pur_sales_daily(uuid, date, date) from public, anon;
grant execute on function public.pur_sales_daily(uuid, date, date) to authenticated, service_role;
comment on function public.pur_sales_daily(uuid, date, date) is 'pur-1 판정 604 · 605 — 발주앱 판매(IMS · 경계 날짜부터) · 일별 · 낱개 · {sku, sale_date, qty} · 문 = purchasing 보기';

create function public.pur_backorders(p_supplier_id uuid default null) returns jsonb
language plpgsql stable security definer as $$
-- 판정 604 · 605 · 464: 열린 백오더(so_reserve kind backorder · released_at null) · 창고 채널 · 무상 줄 제외 · 「진짜 수요 아님」 표식(so_demand_flag.active_line_id — 줄 또는 콤보 부모) · 되돌린 오더 제외 · 오더 날 90 일 ·
--   낱개 = 세트 줄 × pack_factor · 콤보는 예약이 구성품 줄에 있어 구성품 그대로 · 손님 × 낱개 SKU 최신 1 건(오더 날 · 번호 순) · 버킷 0-30 · 30-60 · 60-90 = boSQL 과 같다
declare
  v_today date := public.ims_today();  v_rows jsonb;  v_n int;
begin
  perform public.pur_staff(false);
  if p_supplier_id is not null and not exists (select 1 from public.supplier s where s.id = p_supplier_id) then raise exception 'Supplier not found — nothing was read'; end if;
  with bo as (
    select s.customer_id, s.order_date, s.so_number, l.line_no, b.base_product_id, b.base_sku,
           r.qty * case when b.factor <> 1 then coalesce(l.pack_factor, b.factor) else 1 end as qty
    from public.so_line l
    join public.so s on s.id = l.so_id
    join lateral (select sum(r.qty_allocated) as qty from public.so_reserve r where r.so_line_id = l.id and r.kind = 'backorder' and r.released_at is null) r on r.qty > 0
    cross join lateral public.pur_base(l.product_id) b
    where s.channel = 'warehouse' and s.status <> 'cancelled' and l.free_reason is null and l.removed_at is null
      and s.order_date >= v_today - 90
      and not public.so_demand_so_excluded(s.id)
      and not exists (select 1 from public.so_demand_flag f where f.active_line_id in (l.id, l.combo_line_id))
  ),
  latest as (
    select bo.*, row_number() over (partition by bo.customer_id, bo.base_product_id order by bo.order_date desc, bo.so_number desc, bo.line_no desc) as rn from bo
  ),
  agg as (
    select l.base_sku as sku,
           sum(case when l.order_date >= v_today - 30 then l.qty else 0 end) as bo_0_30,
           sum(case when l.order_date >= v_today - 60 and l.order_date < v_today - 30 then l.qty else 0 end) as bo_30_60,
           sum(case when l.order_date >= v_today - 90 and l.order_date < v_today - 60 then l.qty else 0 end) as bo_60_90,
           sum(l.qty) as bo_qty
    from latest l
    where l.rn = 1
      and (p_supplier_id is null or exists (select 1 from public.product_supplier ps where ps.product_id = l.base_product_id and ps.supplier_id = p_supplier_id and ps.is_active and ps.is_default))
    group by l.base_sku
  )
  select coalesce(jsonb_agg(jsonb_build_object('sku', a.sku, 'bo_0_30', a.bo_0_30, 'bo_30_60', a.bo_30_60, 'bo_60_90', a.bo_60_90, 'bo_qty', a.bo_qty) order by a.sku), '[]'::jsonb), count(*) into v_rows, v_n from agg a;
  return jsonb_build_object('supplier_id', p_supplier_id, 'as_of', v_today, 'row_count', v_n, 'rows', v_rows);
end $$;
revoke all on function public.pur_backorders(uuid) from public, anon;
grant execute on function public.pur_backorders(uuid) to authenticated, service_role;
comment on function public.pur_backorders(uuid) is 'pur-1 판정 604 · 605 · 464 — 발주앱 백오더(IMS 열린 백오더 · 낱개 · 손님 × SKU 최신 1 건 · 0-30 · 30-60 · 60-90 · bo_qty) · 문 = purchasing 보기';

create function public.pur_supplier_skus(p_supplier_id uuid default null) returns jsonb
language plpgsql stable security definer as $$
-- supplierSkuSQL 모양 {sku, product_name, supplier_name, brand} + supplier_id · product_id · 활성 제품 · 기본 공급처(is_default · 활성 줄) 있는 것 · brand 없으면 '—'(화면 COALESCE 와 같다)
declare v_rows jsonb;  v_n int;
begin
  perform public.pur_staff(false);
  select coalesce(jsonb_agg(jsonb_build_object('sku', p.sku, 'product_name', p.name, 'supplier_name', s.name, 'supplier_id', s.id, 'product_id', p.id, 'brand', coalesce(nullif(p.brand_name, ''), '—')) order by p.sku), '[]'::jsonb), count(*)
    into v_rows, v_n
  from public.product p
  join public.product_supplier ps on ps.product_id = p.id and ps.is_active and ps.is_default
  join public.supplier s on s.id = ps.supplier_id
  where p.is_active and (p_supplier_id is null or s.id = p_supplier_id);
  return jsonb_build_object('supplier_id', p_supplier_id, 'row_count', v_n, 'rows', v_rows);
end $$;
revoke all on function public.pur_supplier_skus(uuid) from public, anon;
grant execute on function public.pur_supplier_skus(uuid) to authenticated, service_role;
comment on function public.pur_supplier_skus(uuid) is 'pur-1 — 발주앱 공급처 목록(활성 제품 · 기본 공급처 · supplierSkuSQL 모양 + supplier_id) · 문 = purchasing 보기';

create function public.pur_set_map() returns jsonb
language plpgsql stable security definer as $$
-- 판정 605: 경계 전 BigQuery 판매를 낱개로 접는 지도 · 세트(parent_product_id · pack_factor = BOM Quantity) · 콤보(product_bom 구성품마다 · factor = 수량 × 구성품 계수 · 콤보 한 줄이 여러 줄로) · 활성 · 비활성 모두
declare v_rows jsonb;  v_sets int;  v_combos int;
begin
  perform public.pur_staff(false);
  with sets as (
    select p.sku as set_sku, b.sku as base_sku, coalesce(p.pack_factor, 1) as factor, 'set'::text as kind, p.is_active
    from public.product p join public.product b on b.id = p.parent_product_id
  ),
  combos as (
    select c.sku as set_sku, x.base_sku, bom.quantity * x.factor as factor, 'combo'::text as kind, c.is_active
    from public.product_bom bom join public.product c on c.id = bom.parent_product_id
    cross join lateral public.pur_base(bom.component_product_id) x
    where bom.is_active and c.parent_product_id is null
  ),
  u as (select * from sets union all select * from combos)
  select coalesce(jsonb_agg(jsonb_build_object('set_sku', u.set_sku, 'base_sku', u.base_sku, 'factor', u.factor, 'kind', u.kind, 'is_active', u.is_active) order by u.set_sku, u.base_sku), '[]'::jsonb),
         count(*) filter (where u.kind = 'set'), count(distinct u.set_sku) filter (where u.kind = 'combo')
    into v_rows, v_sets, v_combos from u;
  return jsonb_build_object('sets', v_sets, 'combos', v_combos, 'rows', v_rows);
end $$;
revoke all on function public.pur_set_map() from public, anon;
grant execute on function public.pur_set_map() to authenticated, service_role;
comment on function public.pur_set_map() is 'pur-1 판정 605 — 세트 · 콤보 → 낱개 지도 {set_sku, base_sku, factor, kind, is_active} · 문 = purchasing 보기';

-- ═══ ③ 설정 창구 — 읽기 하나 · 쓰기 다섯 · 옮겨 담기 하나 ═══
create function public.pur_settings(p_supplier_id uuid default null) returns jsonb
language plpgsql stable security definer as $$
-- 화면이 한 번에 읽는 것: 경계 날짜 · 기본값 · 가중치 · 공급처 설정 전부(공급처 이름 · id) · 고른 공급처의 실효값(행 없으면 기본 · is_default true) · SKU 연결 · 고른 공급처의 오버라이드 이력(sea · trd 최근 10 · 새것부터 · {v, d} · v 'auto' = 초기화)
declare v_def jsonb := public.pur_defaults();  v_w jsonb;  v_sup jsonb;  v_bound date;
begin
  perform public.pur_staff(false);
  if p_supplier_id is not null and not exists (select 1 from public.supplier s where s.id = p_supplier_id) then raise exception 'Supplier not found — nothing was read'; end if;
  select c.value::date into v_bound from public.inv_config c where c.key = 'pur_ims_sales_from';
  select ps.value into v_w from public.pur_setting ps where ps.key = 'wma';
  if p_supplier_id is not null then
    select jsonb_build_object('supplier_id', s.id, 'name', s.name, 'leadtime', coalesce(x.lead_time, (v_def->>'leadtime')::int), 'target', coalesce(x.target, (v_def->>'target')::int), 'cycle', coalesce(x.cycle, (v_def->>'cycle')::int),
                              'lt_sigma', coalesce(x.lt_sigma, (v_def->>'lt_sigma')::int), 'is_default', x.supplier_id is null, 'updated_at', x.updated_at, 'updated_by_name', (select st.name from public.ims_staff st where st.id = x.updated_by))
      into v_sup from public.supplier s left join public.pur_supplier_setting x on x.supplier_id = s.id where s.id = p_supplier_id;
  end if;
  return jsonb_build_object(
    'boundary_date', v_bound,
    'defaults', v_def,
    'weights', jsonb_build_object('w1', coalesce((v_w->>'w1')::int, (v_def->>'w1')::int), 'w2', coalesce((v_w->>'w2')::int, (v_def->>'w2')::int), 'w3', coalesce((v_w->>'w3')::int, (v_def->>'w3')::int), 'is_default', v_w is null),
    'supplier', v_sup,
    'supplier_settings', (select coalesce(jsonb_agg(jsonb_build_object('supplier_id', x.supplier_id, 'name', s.name, 'leadtime', x.lead_time, 'target', x.target, 'cycle', x.cycle, 'lt_sigma', x.lt_sigma, 'updated_at', x.updated_at) order by s.name), '[]'::jsonb)
                           from public.pur_supplier_setting x join public.supplier s on s.id = x.supplier_id),
    'sku_links', (select coalesce(jsonb_agg(jsonb_build_object('oldSku', k.old_sku, 'newSku', k.new_sku) order by k.new_sku, k.old_sku), '[]'::jsonb) from public.pur_sku_link k),
    'override_history', case when p_supplier_id is null then null else jsonb_build_object(
        'sea', (select coalesce(jsonb_agg(jsonb_build_object('v', coalesce(h.value::text, 'auto'), 'd', h.set_on) order by h.set_on desc, h.created_at desc), '[]'::jsonb) from (select * from public.pur_override_history h where h.supplier_id = p_supplier_id and h.key = 'sea' order by h.set_on desc, h.created_at desc limit 10) h),
        'trd', (select coalesce(jsonb_agg(jsonb_build_object('v', coalesce(h.value::text, 'auto'), 'd', h.set_on) order by h.set_on desc, h.created_at desc), '[]'::jsonb) from (select * from public.pur_override_history h where h.supplier_id = p_supplier_id and h.key = 'trd' order by h.set_on desc, h.created_at desc limit 10) h)) end
  );
end $$;
revoke all on function public.pur_settings(uuid) from public, anon;
grant execute on function public.pur_settings(uuid) to authenticated, service_role;
comment on function public.pur_settings(uuid) is 'pur-1 판정 606 — 발주앱 설정 읽기(경계 날짜 · 기본값 · 가중치 · 공급처 설정 · SKU 연결 · 오버라이드 이력) · 문 = purchasing 보기';

create function public.pur_supplier_setting_set(p_supplier_id uuid, p jsonb) returns jsonb
language plpgsql security definer as $$
-- p = {leadtime?, target?, cycle?, lt_sigma?} 일부만 와도 된다 — 없는 칸은 지금 값 · 없으면 기본값 · 정수가 아니면 거부(화면 parseInt 와 같은 뜻은 화면이)
declare v_staff uuid;  v_def jsonb := public.pur_defaults();  r public.pur_supplier_setting%rowtype;  k text;
begin
  v_staff := public.pur_staff(true);
  if not exists (select 1 from public.supplier s where s.id = p_supplier_id) then raise exception 'Supplier not found — nothing was saved'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Settings must be an object like {"leadtime": 30} — nothing was saved'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('leadtime', 'target', 'cycle', 'lt_sigma') then raise exception 'Unknown setting % — leadtime, target, cycle, lt_sigma only — nothing was saved', k; end if;
    if (p->>k) !~ '^[0-9]{1,5}$' then raise exception '% must be a whole number of days (got %) — nothing was saved', k, coalesce(p->>k, 'null'); end if;
  end loop;
  select * into r from public.pur_supplier_setting x where x.supplier_id = p_supplier_id for update;
  insert into public.pur_supplier_setting (supplier_id, lead_time, target, cycle, lt_sigma, updated_at, updated_by)
  values (p_supplier_id, coalesce((p->>'leadtime')::int, r.lead_time, (v_def->>'leadtime')::int), coalesce((p->>'target')::int, r.target, (v_def->>'target')::int),
          coalesce((p->>'cycle')::int, r.cycle, (v_def->>'cycle')::int), coalesce((p->>'lt_sigma')::int, r.lt_sigma, (v_def->>'lt_sigma')::int), now(), v_staff)
  on conflict (supplier_id) do update set lead_time = excluded.lead_time, target = excluded.target, cycle = excluded.cycle, lt_sigma = excluded.lt_sigma, updated_at = now(), updated_by = excluded.updated_by
  returning * into r;
  return jsonb_build_object('supplier_id', r.supplier_id, 'leadtime', r.lead_time, 'target', r.target, 'cycle', r.cycle, 'lt_sigma', r.lt_sigma, 'is_default', false, 'updated_at', r.updated_at);
end $$;
revoke all on function public.pur_supplier_setting_set(uuid, jsonb) from public, anon;
grant execute on function public.pur_supplier_setting_set(uuid, jsonb) to authenticated, service_role;

create function public.pur_weights_set(p jsonb) returns jsonb
language plpgsql security definer as $$
-- p = {w1, w2, w3} 1 ~ 10 정수(화면이 1 ~ 10 으로 자르는 것과 같은 울타리 — 밖이면 거부)
declare v_staff uuid;  k text;  v jsonb;
begin
  v_staff := public.pur_staff(true);
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Weights must be an object like {"w1": 3, "w2": 2, "w3": 1} — nothing was saved'; end if;
  foreach k in array array['w1', 'w2', 'w3'] loop
    if (p->>k) !~ '^(10|[1-9])$' then raise exception '% must be a whole number from 1 to 10 (got %) — nothing was saved', k, coalesce(p->>k, 'null'); end if;
  end loop;
  v := jsonb_build_object('w1', (p->>'w1')::int, 'w2', (p->>'w2')::int, 'w3', (p->>'w3')::int);
  insert into public.pur_setting (key, value, updated_at, updated_by) values ('wma', v, now(), v_staff)
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = excluded.updated_by;
  return v || jsonb_build_object('is_default', false);
end $$;
revoke all on function public.pur_weights_set(jsonb) from public, anon;
grant execute on function public.pur_weights_set(jsonb) to authenticated, service_role;

create function public.pur_sku_link_add(p_old_sku text, p_new_sku text) returns jsonb
language plpgsql security definer as $$
declare v_staff uuid;  v_old text := upper(btrim(coalesce(p_old_sku, '')));  v_new text := upper(btrim(coalesce(p_new_sku, '')));  v_id uuid;
begin
  v_staff := public.pur_staff(true);
  if v_old = '' or v_new = '' then raise exception 'Both the old SKU and the new SKU are needed — nothing was saved'; end if;
  if v_old = v_new then raise exception 'A SKU cannot be linked to itself — nothing was saved'; end if;
  if exists (select 1 from public.pur_sku_link k where k.old_sku = v_old and k.new_sku = v_new) then raise exception 'SKU link % → % already exists — nothing was saved', v_old, v_new; end if;
  insert into public.pur_sku_link (old_sku, new_sku, created_by) values (v_old, v_new, v_staff) returning id into v_id;
  return jsonb_build_object('id', v_id, 'oldSku', v_old, 'newSku', v_new);
end $$;
revoke all on function public.pur_sku_link_add(text, text) from public, anon;
grant execute on function public.pur_sku_link_add(text, text) to authenticated, service_role;

create function public.pur_sku_link_remove(p_old_sku text, p_new_sku text) returns jsonb
language plpgsql security definer as $$
declare v_n int;
begin
  perform public.pur_staff(true);
  delete from public.pur_sku_link k where k.old_sku = upper(btrim(coalesce(p_old_sku, ''))) and k.new_sku = upper(btrim(coalesce(p_new_sku, '')));
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'SKU link % → % not found — nothing was removed', upper(btrim(coalesce(p_old_sku, ''))), upper(btrim(coalesce(p_new_sku, ''))); end if;
  return jsonb_build_object('removed', v_n);
end $$;
revoke all on function public.pur_sku_link_remove(text, text) from public, anon;
grant execute on function public.pur_sku_link_remove(text, text) to authenticated, service_role;

create function public.pur_override_record(p_supplier_id uuid, p_key text, p_value numeric) returns jsonb
language plpgsql security definer as $$
-- 오버라이드를 바꿀 때 한 건 — value null = auto(초기화) · 같은 날 같은 값이 마지막이면 다시 안 적는다(화면 recordOvHistory 와 같다) · 돌려주는 것 = 그 열쇠의 최근 10 건(새것부터)
declare v_staff uuid;  v_last public.pur_override_history%rowtype;  v_changed boolean := false;
begin
  v_staff := public.pur_staff(true);
  if not exists (select 1 from public.supplier s where s.id = p_supplier_id) then raise exception 'Supplier not found — nothing was saved'; end if;
  if p_key is null or p_key not in ('sea', 'trd') then raise exception 'Override key must be sea or trd — nothing was saved'; end if;
  select * into v_last from public.pur_override_history h where h.supplier_id = p_supplier_id and h.key = p_key order by h.set_on desc, h.created_at desc limit 1;
  if v_last.id is null or v_last.set_on <> public.ims_today() or v_last.value is distinct from p_value then
    insert into public.pur_override_history (supplier_id, key, value, set_by) values (p_supplier_id, p_key, p_value, v_staff);
    v_changed := true;
  end if;
  return jsonb_build_object('changed', v_changed, 'history', (select coalesce(jsonb_agg(jsonb_build_object('v', coalesce(h.value::text, 'auto'), 'd', h.set_on) order by h.set_on desc, h.created_at desc), '[]'::jsonb)
                                                               from (select * from public.pur_override_history h where h.supplier_id = p_supplier_id and h.key = p_key order by h.set_on desc, h.created_at desc limit 10) h));
end $$;
revoke all on function public.pur_override_record(uuid, text, numeric) from public, anon;
grant execute on function public.pur_override_record(uuid, text, numeric) to authenticated, service_role;

create function public.pur_settings_import(p jsonb, p_commit boolean default false) returns jsonb
language plpgsql security definer as $$
-- 판정 606: Caleb PC 의 localStorage 네 열쇠 JSON 을 그대로 받는다 — {"asung_po_v5": {공급처 이름: {leadtime, target, cycle, lt_sigma}}, "asung_ov_history": {공급처 이름: {sea: [{v, d}], trd: [...]}}, "asung_sku_links": [{oldSku, newSku}], "asung_wma": {w1, w2, w3}}
--   공급처 이름 → id(그대로 · 안 되면 대소문자 · 앞뒤 공백 무시) · 못 찾은 이름은 거부하지 않고 unknown 목록으로 · 미리 보기(commit false) = 같은 모양 · 다시 불러도 같다(설정 덮어쓰기 · 이력은 같은 공급처 · 열쇠 · 값 · 날짜가 있으면 안 넣음 · 연결은 있으면 건너뜀 · 가중치 덮어쓰기)
declare
  v_staff uuid;  v_def jsonb := public.pur_defaults();
  v_po jsonb := p->'asung_po_v5';  v_ov jsonb := p->'asung_ov_history';  v_links jsonb := p->'asung_sku_links';  v_w jsonb := p->'asung_wma';
  v_name text;  v_sid uuid;  v_set jsonb;  e jsonb;  k text;
  v_unknown text[] := '{}';  v_unknown_h text[] := '{}';  v_settings int := 0;  v_hist int := 0;  v_hist_dup int := 0;  v_hist_bad int := 0;
  v_links_n int := 0;  v_links_new int := 0;  v_links_bad int := 0;  v_old text;  v_new text;  v_val numeric;  v_on date;  v_weights jsonb;  v_bad_settings text[] := '{}';
begin
  v_staff := public.pur_staff(true);
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Give an object with the localStorage keys asung_po_v5, asung_ov_history, asung_sku_links, asung_wma — nothing was saved'; end if;
  -- ① 공급처 설정
  if v_po is not null and jsonb_typeof(v_po) = 'object' then
    for v_name, v_set in select * from jsonb_each(v_po) loop
      select s.id into v_sid from public.supplier s where s.name = v_name;
      if v_sid is null then select s.id into v_sid from public.supplier s where lower(btrim(s.name)) = lower(btrim(v_name)) order by s.is_active desc, s.name limit 1; end if;
      if v_sid is null then v_unknown := array_append(v_unknown, v_name); continue; end if;
      if jsonb_typeof(v_set) <> 'object' or exists (select 1 from jsonb_each_text(v_set) x where x.key in ('leadtime', 'target', 'cycle', 'lt_sigma') and x.value !~ '^[0-9]{1,5}$') then
        v_bad_settings := array_append(v_bad_settings, v_name); continue;
      end if;
      v_settings := v_settings + 1;
      if p_commit then
        insert into public.pur_supplier_setting (supplier_id, lead_time, target, cycle, lt_sigma, updated_at, updated_by)
        values (v_sid, coalesce((v_set->>'leadtime')::int, (v_def->>'leadtime')::int), coalesce((v_set->>'target')::int, (v_def->>'target')::int), coalesce((v_set->>'cycle')::int, (v_def->>'cycle')::int), coalesce((v_set->>'lt_sigma')::int, (v_def->>'lt_sigma')::int), now(), v_staff)
        on conflict (supplier_id) do update set lead_time = excluded.lead_time, target = excluded.target, cycle = excluded.cycle, lt_sigma = excluded.lt_sigma, updated_at = now(), updated_by = excluded.updated_by;
      end if;
    end loop;
  end if;
  -- ② 오버라이드 이력
  if v_ov is not null and jsonb_typeof(v_ov) = 'object' then
    for v_name, v_set in select * from jsonb_each(v_ov) loop
      select s.id into v_sid from public.supplier s where s.name = v_name;
      if v_sid is null then select s.id into v_sid from public.supplier s where lower(btrim(s.name)) = lower(btrim(v_name)) order by s.is_active desc, s.name limit 1; end if;
      if v_sid is null then v_unknown_h := array_append(v_unknown_h, v_name); continue; end if;
      foreach k in array array['sea', 'trd'] loop
        if jsonb_typeof(v_set->k) <> 'array' then continue; end if;
        for e in select * from jsonb_array_elements(v_set->k) loop
          begin
            v_val := case when e->>'v' = 'auto' then null else (e->>'v')::numeric end;
            v_on := (e->>'d')::date;
          exception when others then v_hist_bad := v_hist_bad + 1; continue; end;
          if exists (select 1 from public.pur_override_history h where h.supplier_id = v_sid and h.key = k and h.value is not distinct from v_val and h.set_on = v_on) then v_hist_dup := v_hist_dup + 1; continue; end if;
          v_hist := v_hist + 1;
          if p_commit then insert into public.pur_override_history (supplier_id, key, value, set_on, set_by) values (v_sid, k, v_val, v_on, v_staff); end if;
        end loop;
      end loop;
    end loop;
  end if;
  -- ③ SKU 연결
  if v_links is not null and jsonb_typeof(v_links) = 'array' then
    for e in select * from jsonb_array_elements(v_links) loop
      v_links_n := v_links_n + 1;
      v_old := upper(btrim(coalesce(e->>'oldSku', '')));  v_new := upper(btrim(coalesce(e->>'newSku', '')));
      if v_old = '' or v_new = '' or v_old = v_new then v_links_bad := v_links_bad + 1; continue; end if;
      if exists (select 1 from public.pur_sku_link x where x.old_sku = v_old and x.new_sku = v_new) then continue; end if;
      v_links_new := v_links_new + 1;
      if p_commit then insert into public.pur_sku_link (old_sku, new_sku, created_by) values (v_old, v_new, v_staff) on conflict do nothing; end if;
    end loop;
  end if;
  -- ④ 가중치
  if v_w is not null and jsonb_typeof(v_w) = 'object' then
    if (v_w->>'w1') ~ '^(10|[1-9])$' and (v_w->>'w2') ~ '^(10|[1-9])$' and (v_w->>'w3') ~ '^(10|[1-9])$' then
      v_weights := jsonb_build_object('w1', (v_w->>'w1')::int, 'w2', (v_w->>'w2')::int, 'w3', (v_w->>'w3')::int);
      if p_commit then
        insert into public.pur_setting (key, value, updated_at, updated_by) values ('wma', v_weights, now(), v_staff)
        on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = excluded.updated_by;
      end if;
    else
      v_weights := jsonb_build_object('invalid', v_w);
    end if;
  end if;
  return jsonb_build_object('committed', p_commit,
    'supplier_settings', jsonb_build_object('written', v_settings, 'unknown_suppliers', to_jsonb(v_unknown), 'invalid', to_jsonb(v_bad_settings)),
    'override_history', jsonb_build_object('new', v_hist, 'already_there', v_hist_dup, 'invalid', v_hist_bad, 'unknown_suppliers', to_jsonb(v_unknown_h)),
    'sku_links', jsonb_build_object('given', v_links_n, 'new', v_links_new, 'already_there', v_links_n - v_links_new - v_links_bad, 'invalid', v_links_bad),
    'weights', v_weights);
end $$;
revoke all on function public.pur_settings_import(jsonb, boolean) from public, anon;
grant execute on function public.pur_settings_import(jsonb, boolean) to authenticated, service_role;
comment on function public.pur_settings_import(jsonb, boolean) is 'pur-1 판정 606 — localStorage 네 열쇠(asung_po_v5 · asung_ov_history · asung_sku_links · asung_wma)를 그대로 받아 설정 표 넷에 옮겨 담는다 · 미리 보기(commit false) → 실행 · 못 찾은 공급처 이름은 목록으로 · 다시 불러도 같다 · 문 = purchasing 쓰기';

-- ═══ 착지 — 표 넷 ACL · RLS · 함수 열넷 ACL · 설정 키 ═══
do $$
declare
  v_bad text := '';  t text;  f text;  v_acl text;
  c_open  constant text[] := array['pur_defaults()', 'pur_sales_daily(uuid, date, date)', 'pur_backorders(uuid)', 'pur_supplier_skus(uuid)', 'pur_set_map()', 'pur_settings(uuid)',
                                   'pur_supplier_setting_set(uuid, jsonb)', 'pur_weights_set(jsonb)', 'pur_sku_link_add(text, text)', 'pur_sku_link_remove(text, text)', 'pur_override_record(uuid, text, numeric)', 'pur_settings_import(jsonb, boolean)'];
  c_inner constant text[] := array['pur_base(uuid)', 'pur_staff(boolean)'];
begin
  if (select c.value from public.inv_config c where c.key = 'pur_ims_sales_from') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then v_bad := v_bad || ' boundary_key'; end if;
  foreach t in array array['pur_supplier_setting', 'pur_setting', 'pur_sku_link', 'pur_override_history'] loop
    select c.relacl::text into v_acl from pg_class c where c.oid = ('public.' || t)::regclass;
    if not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass) then v_bad := v_bad || ' ' || t || '_rls'; end if;
    if v_acl ~ 'anon=' or v_acl ~ 'authenticated=' or v_acl !~ 'service_role=arwdDxtm' then v_bad := v_bad || ' ' || t || '_acl:' || coalesce(v_acl, '-'); end if;
  end loop;
  foreach f in array c_open loop
    if to_regprocedure('public.' || f) is null then v_bad := v_bad || ' missing_' || f; continue; end if;
    if not has_function_privilege('authenticated', 'public.' || f, 'execute') or has_function_privilege('anon', 'public.' || f, 'execute') or not has_function_privilege('service_role', 'public.' || f, 'execute') then v_bad := v_bad || ' acl_' || f; end if;
  end loop;
  foreach f in array c_inner loop
    if to_regprocedure('public.' || f) is null then v_bad := v_bad || ' missing_' || f; continue; end if;
    if has_function_privilege('authenticated', 'public.' || f, 'execute') or has_function_privilege('anon', 'public.' || f, 'execute') then v_bad := v_bad || ' acl_' || f; end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'pur\_%') <> 14 then v_bad := v_bad || format(' pur_functions_%s_of_14', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'pur\_%')); end if;
  if v_bad <> '' then raise exception 'pur-1 landing check failed:%', v_bad; end if;
end $$;
