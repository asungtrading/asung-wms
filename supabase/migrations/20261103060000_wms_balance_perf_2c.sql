-- ─────────────────────────────────────────────────────────────
-- wms-balance-perf-2c ②-c — so_sale_now 에 p_with_deals(Asung-IMS · 2026-11-02 밤 · ②-c 측정 보고 → Caleb 「추천 1 · 오늘 밤」 · deferred 450 · ① afdd8ec · ②-a 6107e23 · ③ 545d8bb · ②-b 9775e67)
--   측정: so_sale_now(null, null) 246 ~ 276 ms = so_deal_products_all(딜 7 · 줄 38 · 대상 629 → 8,126 행) 54 ~ 70 + 제품 5,814 개의 deals jsonb_agg(정렬 포함) 약 170. 재고 화면(stk_availability 의 sale CTE)은 product_id · best_pct · conditional 셋만 쓴다.
--   고침(결과 그대로):
--     1) so_sale_now(p_product_ids, p_on, p_with_deals boolean default true) — deals 는 jsonb_agg(…) filter (where p_with_deals) 에 coalesce '[]'. filter 가 거짓이면 집계가 행을 받지 않아 jsonb 를 만들지 않는다.
--        세일 식(d · j · so_deal_products_all) · best_pct · deal_count · conditional 은 글자 그대로(식 한 곳 · 판정 361). 기본 true = 옛 값 그대로(그룹마다 행이 있어 jsonb_agg 가 null 이 아니다).
--        ⚠️ 서명이 바뀐다 — 옛 2 인자 판을 drop 하고 3 인자로 새로 만든다(둘 다 두면 overload 라 「not unique」). grant · comment · 속성(invoker · stable · search_path · #variable_conflict) 그대로.
--     2) stk_availability 의 sale CTE 만 so_sale_now(null, null, false). 본문 그 밖은 ②-b 판 바이트 그대로.
--   호출자 전수(2026-11-02 밤 · DB pg_proc prosrc · 뷰 0 · 트리거 0 · 화면 grep): product_export · product_list · stk_value_total · stk_availability — 전부 위치 인자 (null, null) · 화면 products.html:292 · :299 · stock.html:319 — 전부 이름 인자 p_product_ids · p_on(deals 를 쓴다). 기본 true 라 이들 결과 무변(검증 C 가 기본 호출 옛 = 새를 잰다).
--     product_list · product_export · stk_value_total 도 deals 를 안 쓰므로 false 로 바꾸면 같은 몫이 줄지만 이번 범위 밖(Caleb 지시 · stk_availability 만).
--   마지막 정의: so_sale_now 20261007202707_sale_1_sale_now.sql · stk_availability 20261103030000_wms_balance_perf_2b.sql.
--   무접촉: so_deal_products_all · so_deal* 표 · product_list · product_export · stk_value_total · stk_availability_export(껍데기) · 화면.
--   틀리면: 세일 라벨(sale_pct · *) · 세일만 거르기 · Products · Stock 의 딜 말풍선(deals) — 읽기만. 검증: 기본 호출 옛 = 새(null·null · 제품 몇 · 조건부 딜 제품 · 날짜) · false 의 세 칸 = 옛 같은 칸 · deals '[]' · stk_availability 옛 = 새(②-b 꼴 · 줄 · 순서 · sale_pct · sale_conditional).
--   적용: Caleb 이 psql -1 -f + supabase migration repair --status applied 20261103060000 · db push 금지 · 토론토 07:00 전.
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) so_sale_now — 서명이 바뀐다(셋째 인자) → 옛 2 인자 판 drop 후 3 인자로 새로(overload 금지 · 2e-1b qbo_job_done 과 같은 꼴) · 본문은 deals 줄 셋 말고 바이트 그대로 ═══
-- 마지막 정의 md5(바꾸기 전 DB prosrc) 7391d9d3436ad22edda0a75a99fc904a · 옛 ACL {postgres,authenticated,service_role} · invoker · stable · search_path public, pg_temp · #variable_conflict use_column 그대로
drop function public.so_sale_now(uuid[], date);
create function public.so_sale_now(p_product_ids uuid[] default null, p_on date default null, p_with_deals boolean default true)
 RETURNS TABLE(product_id uuid, best_pct numeric, deal_count integer, conditional boolean, deals jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
declare v_on date := coalesce(p_on, public.ims_today());
begin
  return query
  with d as (                                                                                  -- 판정 361: 켜진 줄 할인 딜 · 쿠폰 아님 · 오늘 기간 안
    select x.id, x.name, x.date_from, x.date_to,
           exists (select 1 from public.so_deal_customer_rule r where r.deal_id = x.id) as customer_limited
    from public.so_deal x
    where x.is_active and not x.is_order_level and not x.coupon_required and x.kind = 'pct'
      and (x.date_from is null or x.date_from <= v_on) and (x.date_to is null or x.date_to >= v_on)
  ),
  j as (
    select a.product_id, a.deal_id, d.name, l.pct, l.line_no, l.min_qty_mode, l.min_qty, d.date_from, d.date_to, d.customer_limited, a.matched_by
    from public.so_deal_products_all((select array_agg(d2.id) from d d2)) a                                    -- 식 한 곳 · 켜진 줄만(세트는 낱개를 거쳐 · 판정 302)
    join d on d.id = a.deal_id
    join public.so_deal_line l on l.id = a.line_id
    where p_product_ids is null or a.product_id = any (p_product_ids)
  )
  select j.product_id,
         max(j.pct)                                                     as best_pct,
         count(distinct j.deal_id)::int                                 as deal_count,
         bool_or(j.min_qty_mode <> 'none' or j.customer_limited)        as conditional,
         coalesce(jsonb_agg(jsonb_build_object('deal_id', j.deal_id, 'name', j.name, 'pct', j.pct, 'line_no', j.line_no, 'date_from', j.date_from, 'date_to', j.date_to,   -- wms-balance-perf-2c(deferred 450 ②-c): p_with_deals false 면 deals 를 만들지 않는다(filter 가 거짓이면 집계가 행을 받지 않는다 · 세일 식 · best_pct · conditional 은 같은 j 그대로)
                                      'min_qty_mode', j.min_qty_mode, 'min_qty', j.min_qty, 'customer_limited', j.customer_limited, 'matched_by', j.matched_by)             -- wms-balance-perf-2c
                   order by j.pct desc, j.name, j.line_no) filter (where p_with_deals), '[]'::jsonb) as deals                                                                  -- wms-balance-perf-2c: 기본 true = 옛 값 그대로(그룹마다 행이 있어 null 이 아니다) · false = '[]'
  from j
  where (select count(*) from d) > 0
  group by j.product_id;
end $function$;
revoke all on function public.so_sale_now(uuid[], date, boolean) from public, anon;
grant execute on function public.so_sale_now(uuid[], date, boolean) to authenticated, service_role;
comment on function public.so_sale_now(uuid[], date, boolean) is $c$⭐ 지금 세일하는 제품(sale-1 · 판정 361 · 2026-10-07) — 세일 = p_on(null = ims_today · 토론토) 기간 안 · 켜진 딜의 켜진 줄 · 쿠폰이 필요 없는 줄 할인 딜(오더 딜 · 쿠폰 딜은 뺀다) · 대상 판정은 so_deal_products_all 한 곳(세트는 낱개를 거쳐) · 행 = 제품마다 best_pct(가장 큰 %) · deal_count(딜 수) · conditional(최소 수량 또는 손님 조건이 있는 줄이 하나라도) · deals[{deal_id · name · pct · line_no · date_from · date_to · min_qty_mode · min_qty · customer_limited · matched_by}](% 큰 순 · 줄마다 한 항목) · p_product_ids null = 세일 제품 전부 · 제품 켜짐은 보지 않는다(화면이 거른다) · invoker · stable · Stock availability · Products 화면이 라벨 · 거르기에 쓴다(stk_availability · product_list 가 안에서 부른다) · wms-balance-perf-2c(2026-11-02 · deferred 450 ②-c): 셋째 인자 p_with_deals boolean default true — false 면 deals = [](만들지 않는다 · 약 −170 ms · 제품 5,814 개의 jsonb) · best_pct · deal_count · conditional 은 같은 식 그대로 · 2 인자 호출(product_list · product_export · stk_value_total · 화면 products · stock 의 rpc)은 기본 true 라 값 무변 · 옛 2 인자 판은 drop(overload 면 이름 호출이 not unique)$c$;

-- ═══ 2) stk_availability — sale CTE 한 줄(false) · 그 밖 바이트 그대로(②-b 뒤 판) ═══
-- 마지막 정의 md5(바꾸기 전 DB prosrc · ②-b 뒤) 6437737076aa77aed997eab50a5c4786
create or replace function public.stk_availability(p_warehouse_id uuid, p_q text DEFAULT NULL::text, p_brand_id uuid DEFAULT NULL::uuid, p_category_id uuid DEFAULT NULL::uuid, p_include_zero boolean DEFAULT false, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0, p_sale_only boolean DEFAULT false, p_supplier_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(product_id uuid, sku text, name text, brand_id uuid, brand_name text, category_id uuid, category_name text, is_active boolean, on_hand numeric, sales_allocated numeric, transfer_reserved numeric, available numeric, on_order numeric, in_transit numeric, last_event_on date, matched_set_sku text, matched_set_pack_factor numeric, matched_set_count integer, sale_pct numeric, sale_conditional boolean, total bigint, by_warehouse jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff  uuid;
  v_q      text := nullif(btrim(p_q), '');
  v_limit  int  := least(greatest(coalesce(p_limit, 100), 1), 20000);                                 -- stkx-1 판정 628: 내보내기가 한 번에 전부(500 → 20000 · 재고 키 ≈ 12,400 · 화면 목록은 100 그대로)
  v_offset int  := greatest(coalesce(p_offset, 0), 0);
  v_whs    uuid[];
begin
  -- 문(판정 268) — 로그인 + 활성 직원 · 열쇠는 보지 않는다(판정 258)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  if p_warehouse_id is null then                                                           -- 판정 571 「B」 Both = 활성 창고 전부 · 평평한 열은 합 · by_warehouse 에 창고별
    select coalesce(array_agg(w.id order by w.name), '{}'::uuid[]) into v_whs from public.ref_warehouse w where w.is_active;
    if cardinality(v_whs) = 0 then raise exception 'No active warehouse — nothing was read'; end if;
  else
    if not exists (select 1 from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active) then
      raise exception 'Warehouse not found or inactive — pick an active branch';
    end if;
    v_whs := array[p_warehouse_id];
  end if;
  return query
  with whs as (select w.id, w.name from public.ref_warehouse w where w.id = any(v_whs)),
  av as (                                                                                  -- 장부 · 판매 예약 · 트랜스퍼 예약 — 식 한 곳(inv_available_base) · 창고마다 한 번(lateral)
    select x.id as wh, b.stock_pid, b.qty_ea, b.sales_alloc_ea, b.transfer_alloc_ea, b.bgrade_ea from whs x cross join lateral public.inv_available_base(x.id, null) b   -- bgr-1a: bgrade_ea
  ),
  lastev as (                                                                              -- 뷰는 warehouse(이름)로 걸러야 인덱스로 내려간다 — lateral 의 x.name 은 파라미터라 밀어넣어진다(stk-1 교훈)
    select x.id as wh, le.product_id, le.last_event_on
    from whs x cross join lateral (select p.id as product_id, max(l.occurred_on) as last_event_on from public.inv_ledger l join public.product p on p.sku = l.sku where l.warehouse = x.name group by 1) le   -- wms-balance-perf-2a(deferred 450 ②-a): 뷰 대신 원장 직접 — 뷰의 last_event_on 은 그 키 원장 행의 max(occurred_on) · 칸 합의 max = sku × 창고 원장 전 행의 max · product 없는 sku 는 뷰에서도 product_id null 로 빠졌다 · 집합 무변(없는 제품은 left join 이라 null 그대로)
  ),
  onord as (                                                                               -- 판정 260 — 확정 발주 줄 − 확정 입고 줄 · 줄마다 0 아래는 0 · 발주의 배송 창고
    select po.ship_to_warehouse_id as wh, coalesce(pr.parent_product_id, pr.id) as stock_pid, sum(greatest(l.qty_ea - coalesce(rc.recv, 0), 0)) as ea
    from public.po po
    join public.po_line l on l.po_id = po.id
    join public.product pr on pr.id = l.product_id
    left join (select rl.po_line_id, sum(rl.qty_ea) as recv
                 from public.po_receipt_line rl join public.po_receipt r on r.id = rl.receipt_id
                where r.status = 'confirmed' group by 1) rc on rc.po_line_id = l.id
    where po.status = 'confirmed' and po.ship_to_warehouse_id = any(v_whs)
    group by 1, 2
  ),
  intr as (                                                                                -- 운송 중 — 출발했고 아직 도착 창고에 다 들어오지 않은 트랜스퍼 줄 · 도착 창고
    select t.to_warehouse_id as wh, coalesce(pr.parent_product_id, pr.id) as stock_pid,
           sum(greatest(coalesce(l.qty_sent, 0) - coalesce(l.qty_received, 0) - coalesce(l.qty_lost, 0) - coalesce(l.qty_returned, 0), 0) * l.pack_factor) as ea
    from public.inv_transfer t
    join public.inv_transfer_line l on l.transfer_id = t.id
    join public.product pr on pr.id = l.product_id
    where t.status in ('in_transit', 'receiving') and t.to_warehouse_id = any(v_whs)
    group by 1, 2
  ),
  pw as (                                                                                  -- 재고 키 × 고른 창고 — 창고별 한 줄
    select p.id as pid, x.id as wh, x.name as whname,
           coalesce(av.qty_ea, 0) as on_hand, coalesce(av.sales_alloc_ea, 0) as sales_allocated, coalesce(av.transfer_alloc_ea, 0) as transfer_reserved,
           coalesce(onord.ea, 0) as on_order, coalesce(intr.ea, 0) as in_transit, lastev.last_event_on, coalesce(av.bgrade_ea, 0) as bgrade   -- bgr-1a: B급 수량(옆 칸 · 판정 641)
    from public.product p
    cross join whs x
    left join av     on av.wh = x.id     and av.stock_pid = p.id
    left join lastev on lastev.wh = x.id and lastev.product_id = p.id
    left join onord  on onord.wh = x.id  and onord.stock_pid = p.id
    left join intr   on intr.wh = x.id   and intr.stock_pid = p.id
    where p.parent_product_id is null
  ),
  agg as (                                                                                 -- 평평한 열 = 고른 창고들의 합 · by_warehouse = 창고별(이름 순 · 한 창고면 원소 하나)
    select pw.pid,
           sum(pw.on_hand) as on_hand, sum(pw.sales_allocated) as sales_allocated, sum(pw.transfer_reserved) as transfer_reserved,
           sum(pw.on_order) as on_order, sum(pw.in_transit) as in_transit, max(pw.last_event_on) as last_event_on, sum(pw.bgrade) as bgrade    -- bgr-1a   -- wms-balance-perf-2b(deferred 450 ②-b): by_warehouse jsonb 는 여기(전수 12,822 제품 × 창고)가 아니라 끝의 bw 에서 페이지 줄에만 만든다(뼈대 523 → 97 ms)
    from pw group by pw.pid
  ),
  sale as (                                                                                -- sale-1 판정 361: 오늘 세일(so_sale_now · 식 한 곳) — 낱개 줄에 붙인다
    select z.product_id, z.best_pct, z.conditional from public.so_sale_now(null, null, false) z                                                   -- wms-balance-perf-2c(deferred 450 ②-c): deals jsonb 는 안 쓴다 — 만들지 않는 갈래(약 −170 ms · 식 한 곳 그대로)
  ),
  bc as (                                                                                  -- ⑥ 바코드 정확 일치(product_barcode · 활성) → 그 제품의 재고 키 · 여러 제품이면 전부 · 세트 바코드는 setm 에서 세트 표시
    select coalesce(s.parent_product_id, s.id) as stock_pid
    from public.product_barcode b join public.product s on s.id = b.product_id
    where v_q is not null and b.is_active and b.barcode = v_q
    group by 1
  ),
  setm as (                                                                                -- 판정 261 · 267 — 세트 sku 검색(또는 세트 바코드 정확 일치) → 낱개 줄 · 첫 세트(sku 순) + 개수
    select s.parent_product_id as stock_pid,
           (array_agg(s.sku order by s.sku))[1]         as matched_set_sku,
           (array_agg(s.pack_factor order by s.sku))[1] as matched_set_pack_factor,
           count(*)::int                                as matched_set_count
    from public.product s
    where v_q is not null and s.parent_product_id is not null
      and (s.sku ilike '%' || v_q || '%' or exists (select 1 from public.product_barcode b where b.product_id = s.id and b.is_active and b.barcode = v_q))
    group by 1
  ),
  sup as (                                                                                 -- 판정 570 「A」 — 그 공급처의 활성 줄이 있는 제품 전부(기본 아니어도) · 세트 줄은 낱개로(짐작 확인 8) · 비활성 줄 제외
    select distinct coalesce(sp.parent_product_id, sp.id) as stock_pid
    from public.product_supplier ps join public.product sp on sp.id = ps.product_id
    where p_supplier_id is not null and ps.supplier_id = p_supplier_id and ps.is_active
  ),
  rows_all as (                                                                            -- ⭐ 이 where 는 stk_value_total 의 keys 와 서로 같은 조건 — 한쪽을 고치면 다른 쪽도
    select p.id, p.sku, p.name, p.brand_id, p.brand_name, p.category_id, p.category_name, p.is_active,
           coalesce(agg.on_hand, 0)            as on_hand,
           coalesce(agg.sales_allocated, 0)    as sales_allocated,
           coalesce(agg.transfer_reserved, 0)  as transfer_reserved,
           coalesce(agg.on_hand, 0) - coalesce(agg.sales_allocated, 0) - coalesce(agg.transfer_reserved, 0) as available,
           coalesce(agg.on_order, 0)           as on_order,
           coalesce(agg.in_transit, 0)         as in_transit,
           agg.last_event_on,
           setm.matched_set_sku, setm.matched_set_pack_factor, setm.matched_set_count,
           sale.best_pct as sale_pct, sale.conditional as sale_conditional,
           coalesce(agg.bgrade, 0)             as bgrade                                   -- bgr-1a: rows_kept 가 본다(반환 칸 아님) · wms-balance-perf-2b: by_warehouse 는 끝의 bw 에서
    from public.product p                                                                -- 줄 = 재고 키 = 낱개(세트 · 콤보 줄 없음 · 판정 261)
    left join agg    on agg.pid          = p.id
    left join setm   on setm.stock_pid   = p.id
    left join sale   on sale.product_id  = p.id
    left join bc     on bc.stock_pid     = p.id
    left join sup    on sup.stock_pid    = p.id
    where p.parent_product_id is null
      and (not p_sale_only or sale.product_id is not null)                                                             -- sale-1 판정 361: 세일 제품만
      and not exists (select 1 from public.product_bom bm where bm.parent_product_id = p.id and bm.is_active)
      and (p_brand_id is null or p.brand_id = p_brand_id)
      and (p_category_id is null or p.category_id = p_category_id)
      and (p_supplier_id is null or sup.stock_pid is not null)
      and (v_q is null or p.sku ilike '%' || v_q || '%' or p.name ilike '%' || v_q || '%' or p.brand_name ilike '%' || v_q || '%' or setm.stock_pid is not null or bc.stock_pid is not null)
  ),
  rows_kept as (
    select r.* from rows_all r
    where p_include_zero
       or r.on_hand <> 0 or r.sales_allocated <> 0 or r.transfer_reserved <> 0 or r.on_order <> 0 or r.in_transit <> 0   -- 판정 266 — 다섯 숫자(Both 는 합) 모두 0 인 줄만 뺀다
       or r.bgrade <> 0                                                                                                  -- bgr-1a 판정 637: B급만 있는 줄도 보인다
  )
  , page as (                                                                              -- wms-balance-perf-2b(deferred 450 ②-b): 전수(rows_kept)에서 total · 정렬 · 쪽을 먼저 정한다 — 옛 끝 문장과 같은 window · order · limit · offset
    select r.*, count(*) over () as total                                                  -- wms-balance-perf-2b
    from rows_kept r                                                                       -- wms-balance-perf-2b
    order by r.sku, r.id                                                                   -- wms-balance-perf-2b
    limit v_limit offset v_offset                                                          -- wms-balance-perf-2b
  ), bw as (                                                                               -- wms-balance-perf-2b: 창고별 jsonb 는 페이지 줄에만(pw 와 page 를 해시 조인 · pw 는 두 번 읽혀 한 번 물질화) · 키 · 값 · 순서(whname) 옛 agg 그대로
    select pw.pid,                                                                         -- wms-balance-perf-2b
           jsonb_agg(jsonb_build_object('warehouse_id', pw.wh, 'warehouse', pw.whname,                                                           -- wms-balance-perf-2b
                                        'on_hand', pw.on_hand, 'sales_allocated', pw.sales_allocated, 'transfer_reserved', pw.transfer_reserved,   -- wms-balance-perf-2b
                                        'available', pw.on_hand - pw.sales_allocated - pw.transfer_reserved,                                       -- wms-balance-perf-2b
                                        'on_order', pw.on_order, 'in_transit', pw.in_transit, 'last_event_on', pw.last_event_on, 'bgrade', pw.bgrade) order by pw.whname) as by_warehouse   -- wms-balance-perf-2b · bgr-1a: bgrade(수량만 · 판정 262 · 575)
    from pw join page on page.id = pw.pid                                                  -- wms-balance-perf-2b
    group by pw.pid                                                                        -- wms-balance-perf-2b
  )
  select r.id, r.sku, r.name, r.brand_id, r.brand_name, r.category_id, r.category_name, r.is_active,
         r.on_hand, r.sales_allocated, r.transfer_reserved, r.available, r.on_order, r.in_transit, r.last_event_on,
         r.matched_set_sku, r.matched_set_pack_factor, r.matched_set_count,
         r.sale_pct, r.sale_conditional,
         r.total,                                                                          -- wms-balance-perf-2b: page 가 센 total(전수 · 옛 count(*) over () 와 같은 값)
         bw.by_warehouse                                                                   -- wms-balance-perf-2b
  from page r                                                                              -- wms-balance-perf-2b
  left join bw on bw.pid = r.id                                                            -- wms-balance-perf-2b
  order by r.sku, r.id;                                                                    -- wms-balance-perf-2b: 쪽 안 순서 그대로
end;
$function$;
comment on function public.stk_availability(uuid,text,uuid,uuid,boolean,integer,integer,boolean,uuid) is $c$⭐ 브랜치별 재고 가용표 한 쪽(stk-1 · 판정 257 ~ 262 · 266 ~ 268 · sale-1 판정 361 · ⭐ stk-av-1 재발행 판정 570 · 571 · 575 · 2026-10-20) — 줄 = 재고 키(낱개 · 세트 · 콤보 줄 없음) × 고른 창고(활성만 · ⭐ p_warehouse_id null = Both = 활성 창고 전부 · 평평한 열은 합 · by_warehouse jsonb [{warehouse_id · warehouse · on_hand · sales_allocated · transfer_reserved · available · on_order · in_transit · last_event_on}] 창고 이름 순 · 한 창고면 원소 하나) · on_hand · sales_allocated · transfer_reserved · available · on_order · in_transit · last_event_on · 세트 sku 검색 → 낱개 줄(matched_set_*) · ⭐ p_q 가 활성 바코드와 정확히 같으면 그 제품(세트 바코드 → 낱개 줄 + 세트 표시 · 여러 제품이면 전부) · ⭐ p_supplier_id = 그 공급처의 활성 줄이 있는 제품 전부(기본 아니어도 · 세트 줄은 낱개로) · p_include_zero 거짓이면 다섯 숫자(Both 는 합) 모두 0 인 줄만 뺀다 · sale_pct · sale_conditional(so_sale_now) · p_sale_only · total = 거른 뒤 전체 수 · 문 = 로그인 + 활성 직원(열쇠 안 봄 · 판정 268) · definer · limit ≤ 500 · ⭐ 원가 열 없음(판정 262 · 575 — 금액은 stk_value_many · stk_value_total · 원가 열쇠) · rows_all 의 where 는 stk_value_total 의 keys 와 서로 같은 조건 · wms-balance-perf-2a(2026-11-02 · deferred 450 ②-a): lastev 는 뷰 대신 inv_ledger 직접 max(occurred_on)(창고마다 334 → 123 ms · 집합 무변) · av 는 inv_available_base 가 같은 차수에서 직접 읽는다 · ②-b(by_warehouse 를 페이지에만) · ②-c(sale) 는 따로 · wms-balance-perf-2b(2026-11-02 · deferred 450 ②-b): by_warehouse jsonb 는 전수가 아니라 페이지 줄(limit 뒤)에만 만든다(page → bw) · 합계 · 거르기 · 정렬 · total 은 전수 그대로 · 반환 열 · 값 · 순서 무변(Both 1,409 → 약 1,000 ms · 뼈대 523 → 97) · stk_availability_export 는 이 함수를 20,000 으로 부르는 껍데기라 무변 · wms-balance-perf-2c(2026-11-02 · deferred 450 ②-c): sale CTE 는 so_sale_now(null, null, false) — deals jsonb 를 안 쓰므로 만들지 않는다(sale_pct · sale_conditional 값 무변)$c$;

-- ═══ 3) 자기 검사 — so_sale_now 하나(3 인자 · 셋째 default) · 권한 · 속성 · stk_availability 가 false 로 부른다 ═══
do $$
declare v_bad text := '';  v_oid oid;
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_sale_now') <> 1 then v_bad := v_bad || ' overloads'; end if;
  select oid into v_oid from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_sale_now';
  if pg_get_function_identity_arguments(v_oid) <> 'p_product_ids uuid[], p_on date, p_with_deals boolean' then v_bad := v_bad || ' signature'; end if;
  if (select pronargdefaults from pg_proc where oid = v_oid) <> 3 then v_bad := v_bad || ' defaults'; end if;
  if (select pg_get_function_result(oid) from pg_proc where oid = v_oid) <> 'TABLE(product_id uuid, best_pct numeric, deal_count integer, conditional boolean, deals jsonb)' then v_bad := v_bad || ' result'; end if;
  if (select prosecdef or provolatile <> 's' or coalesce(proconfig::text, '') <> '{"search_path=public, pg_temp"}' from pg_proc where oid = v_oid) then v_bad := v_bad || ' attrs'; end if;
  if (select prosrc from pg_proc where oid = v_oid) !~ '#variable_conflict use_column' then v_bad := v_bad || ' variable_conflict'; end if;
  if not has_function_privilege('authenticated', v_oid, 'execute') or not has_function_privilege('service_role', v_oid, 'execute') or has_function_privilege('anon', v_oid, 'execute') then v_bad := v_bad || ' acl'; end if;
  if (select prosrc from pg_proc where oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure) !~ 'public\.so_sale_now\(null, null, false\)' then v_bad := v_bad || ' stk_call'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('product_list', 'product_export', 'stk_value_total') and prosrc ~ 'public\.so_sale_now\(null, null\)') <> 3 then v_bad := v_bad || ' other_callers_changed'; end if;
  if v_bad <> '' then raise exception 'wms-balance-perf-2c self-check failed:%', v_bad; end if;
end $$;
-- 검증 E 상수(태그 줄을 뺀 새 본문 md5 / 태그 줄 수): so_sale_now=93599e5201075393a8d07c6f4ad9c47a/3 stk_availability=ece94fa8f71c55a2f956443599a3d74a/1
