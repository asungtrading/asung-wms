-- ─────────────────────────────────────────────────────────────
-- wms-balance-perf-2a ②-a — 창고 전체 꼴 두 조각을 뷰 대신 직접 읽기(Asung-IMS · 2026-11-02 밤 · 지시서 wms-balance-perf-1 ② 측정 보고 → Caleb 「②-a 만」 · deferred 450 · ① 은 afdd8ec)
--   측정(Both · 따뜻한 캐시): stk_availability 1,850 ms = av(inv_available_base × 2) 580 + lastev(뷰) 334 + sale 235 + onord · intr 38 + 뼈대 523.
--   범인(②-a 몫): 뷰 ims_inv_balance 는 키로 걸어도 last_ev(원장 62k 행 GROUP BY) · baseline_at(스냅샷 13.8k 행) · product Seq Scan 을 창고 단위로 늘 다시 센다.
--        inv_available_base 의 bal(창고 전체 · pids null) 251 → 직접 161 ms · stk_availability 의 lastev 334 → 원장 직접 123 ms(창고 둘). 본체 가정 실험 1,850 → 1,350 ~ 1,450 ms.
--   고침(결과 그대로 — 집합 무변):
--     1) inv_available_base bal CTE — ims_inv_balance → inv_balance + product(sku 유니크) + ref_bin(warehouse_id = p_location_id · name = bin · bin <> '') · 술어 · 합 · group 그대로. 허브(stk_availability · so_available_many · stk_reserved · shop_stock_payload · so_backorder_* · pur_stock · po_receipt_post_now_by) 무접촉 · 서명 · 반환 무변.
--     2) stk_availability lastev — ims_inv_balance 창고 전체 max(last_event_on) → inv_ledger 직접 max(occurred_on) group by product(뷰의 last_event_on 정의 = 그 키 원장 행의 max(occurred_on)).
--     본문 그 밖은 DB prosrc 바이트 그대로(md5 는 각 절 머리 · 검증 E 가 「태그 줄 뺀 본문 = 옛 본문에서 바뀐 줄 뺀 것」 으로 잰다).
--   마지막 정의: inv_available_base 20261102100000_tf_combo_1a_lines.sql · stk_availability 20261023131028_bgr_1a_bgrade_bins.sql.
--   권한 그대로: 둘 다 create or replace(acl · definer · stable · search_path · 소유자 무변).
--   무접촉: 뷰 ims_inv_balance · ims_ledger_unlinked · inv_balance · ims_inv_balance_of(①) · ②-b(by_warehouse 를 페이지에만) · ②-c(sale · so_sale_now) · ③ · 화면.
--   틀리면: 가용(재고 화면 · SO 확정 · 백오더 · 트랜스퍼) · Shopify 재고(shop_stock_payload) · 재고 화면 last_event — 재고 쓰기에는 닿지 않는다. 검증: 직접 식 vs 뷰 식 except 양방향 0 · 옛 창구 vs 새 창구 jsonb 같음(inv_available_base 두 길 · so_available_many · shop_stock_payload · stk_availability).
--   적용: 두 창고가 멈춘 뒤 Caleb 이 psql -1 -f + supabase migration repair --status applied 20261103010000 · db push 금지.
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) inv_available_base — bal CTE 만 직접 읽기 · 그 밖 바이트 그대로(허브 — 부르는 9 함수 무접촉) ═══
-- 마지막 정의 md5(바꾸기 전 DB prosrc) 878dc25016f54889a597fb6ce41f52b6
create or replace function public.inv_available_base(p_location_id uuid, p_stock_pids uuid[] DEFAULT NULL::uuid[])
 RETURNS TABLE(stock_pid uuid, qty_ea numeric, sales_alloc_ea numeric, transfer_alloc_ea numeric, bgrade_ea numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with wh as (                                                                            -- 창고 이름 — 뷰는 warehouse(이름) · sku 로 걸러야 inv_ledger (sku, warehouse) 인덱스로 내려간다(warehouse_id · product_id 로 거르면 뷰 전체 18k 행을 센다)
    select w.name from public.ref_warehouse w where w.id = p_location_id
  ),
  skus as (                                                                              -- 부른 키의 sku 들 — p_stock_pids 가 null 이면 null(= 전부)
    select case when p_stock_pids is null then null else (select array_agg(p.sku) from public.product p where p.id = any(p_stock_pids)) end as arr
  ),
  bal as (                                                                               -- 장부 — 창고의 모든 bin 합(ims_inv_balance · product 에 없는 sku 는 재고 키가 아니다)
    select p.id as stock_pid, sum(b.qty) filter (where not coalesce(rb.is_bgrade, false)) as qty, sum(b.qty) filter (where coalesce(rb.is_bgrade, false)) as bg   -- wms-balance-perf-2a(deferred 450 ②-a): 뷰 대신 inv_balance + product + ref_bin 직접(뷰의 last_ev 62k 행 · baseline_at · product Seq Scan 을 안 센다 · 집합 무변) · bgr-1a 판정 641: 팔 수 있는 장부 = B급 칸을 뺀 합 · B급 칸 합은 bg 로 따로
    from public.inv_balance b                                                             -- wms-balance-perf-2a: 스냅샷(baseline_snapshot_key) + 원장 전 행 · sku · warehouse · bin 합 — 창고 이름 · sku 술어가 두 갈래로 내려간다
    join public.product p on p.sku = b.sku                                                -- wms-balance-perf-2a: 뷰의 product_id is not null 과 같은 집합(product_sku_key 유니크)
    left join public.ref_bin rb on rb.warehouse_id = p_location_id and rb.name = b.bin and b.bin <> ''   -- wms-balance-perf-2a: 뷰의 bin_is_bgrade = coalesce(rb.is_bgrade, false) · 뷰는 ref_warehouse(name = b.warehouse).id 로 붙이는데 그것이 p_location_id 다(ref_warehouse_name_key 유니크)
    where b.warehouse = (select name from wh)                                             -- wms-balance-perf-2a
      and ((select k.arr from skus k) is null or b.sku = any((select k.arr from skus k)::text[]))   -- 스칼라 서브쿼리(InitPlan 상수)라 뷰 안 인덱스 조건으로 내려간다 · 괄호만 쓰면 서브쿼리 꼴(text = text[])로 읽힌다
    group by p.id                                                                         -- wms-balance-perf-2a
  ),
  alloc as (                                                                             -- 판매 예약 — 열린 allocated 예약 × 줄의 pack_factor · 오더 창고 · 재고 키 = 낱개(세트는 parent)
    select coalesce(p.parent_product_id, p.id) as stock_pid, sum(r.qty_allocated * l.pack_factor) as ea
    from public.so_reserve r
    join public.so_line l on l.id = r.so_line_id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    where r.released_at is null and r.kind = 'allocated'
      and s.location_id = p_location_id
      and (p_stock_pids is null or coalesce(p.parent_product_id, p.id) = any(p_stock_pids))
      and l.bgrade_bin_id is null                                                       -- bgr-1a(bgr-0 이견 2): B급 줄의 할당은 정상 가용을 깎지 않는다(stk_reserved 와 같은 조건)
    group by 1
  ),
  talloc as (                                                                            -- 트랜스퍼 예약(tr-1a 묶음 2) — 확정된 문서(창고로 보내기 · 픽 중 포함 · 출발 전)의 줄 자체 · 출발 창고 · 낱개 EA
    select coalesce(p.parent_product_id, p.id) as stock_pid, sum(l.qty * l.pack_factor) as ea
    from public.inv_transfer_line l
    join public.inv_transfer t on t.id = l.transfer_id
    join public.product p on p.id = l.product_id
    where t.status in ('confirmed', 'at_wms', 'picking')
      and t.from_warehouse_id = p_location_id
      and (p_stock_pids is null or coalesce(p.parent_product_id, p.id) = any(p_stock_pids))
      and not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = l.id)   -- tf-combo-1a(판정 952 · 566 짝): 콤보 줄은 예약이 아니다 — 구성품 줄이 센다(stk_reserved trf · inv_transfer_shortage 와 같은 조건)
    group by 1
  ),
  keys as (
    select stock_pid from bal union select stock_pid from alloc union select stock_pid from talloc
  )
  select k.stock_pid,
         coalesce(bal.qty, 0),
         coalesce(alloc.ea, 0),
         coalesce(talloc.ea, 0),
         coalesce(bal.bg, 0)                                                              -- bgr-1a: bgrade_ea(그 창고 B급 칸 잔고 합 · 수량만)
  from keys k
  left join bal    on bal.stock_pid    = k.stock_pid
  left join alloc  on alloc.stock_pid  = k.stock_pid
  left join talloc on talloc.stock_pid = k.stock_pid;
$function$;
comment on function public.inv_available_base(uuid,uuid[]) is $c$⭐⭐ 가용 재고 식 한 곳(stk-1 · 판정 264 · 265 · 2026-10-06 · 종전 so_available_many 본문) — 창고 하나의 재고 키(낱개 · 세트는 parent · p_stock_pids null = 전부 · 배열 = 그 키만 — 장부는 sku = any 로 뷰 안 인덱스에 밀어넣어 1 키 ~56 ms · 전부 ~170 ms · 배열 7,663 은 쓰지 마라(null 로)) → (stock_pid · qty_ea 창고 잔고 = ims_inv_balance 모든 bin 합 · sales_alloc_ea Σ 열린 allocated 예약 × pack_factor(오더 창고) · transfer_alloc_ea Σ 확정 · at_wms · picking 트랜스퍼 줄 qty × pack_factor(출발 창고)) · available = qty_ea − sales_alloc_ea − transfer_alloc_ea 는 부르는 쪽이 뺀다(so_available_many · stk_availability) · 조인 한 문장(= any 는 sku 밀어넣기에만 · product_id = any 는 뷰 전체를 센다) · ⭐ definer(판정 264): inv_transfer 의 select 정책은 transfer · WMS 열쇠인데 가용은 모든 직원에게 같아야 한다 — invoker 였던 so_available_many 는 sales 만 가진 직원에게 트랜스퍼 예약을 0 으로 보였다 · 원가 열 없음(판정 262) · authenticated execute(invoker 껍데기들이 부른다) · 음수 그대로 · preorder · hold · backorder 는 빼지 않는다 · ⭐ [2026-10-20 stk-av-1 판정 566] alloc · talloc 의 조건은 stk_reserved(목록)와 서로 같은 조건 — 한쪽을 고치면 다른 쪽도(시험: 모든 키 × 창고에서 목록 합 = 타일) · ⭐ [2026-10-23 bgr-1a 판정 641] qty_ea = 팔 수 있는 장부(B급 칸 is_bgrade 제외) · bgrade_ea = 그 창고 B급 칸 잔고 합(새 다섯째 칸) · alloc 은 B급 줄(so_line.bgrade_bin_id)의 할당을 뺀다(stk_reserved 와 같은 조건) · ⭐ [2026-11-02 tf-combo-1a 판정 952] talloc 은 콤보 줄(구성품 줄이 달린 inv_transfer_line)을 빼고 구성품 줄로 센다(stk_reserved trf 와 같은 조건) · wms-balance-perf-2a(2026-11-02 · deferred 450 ②-a): bal 은 뷰 ims_inv_balance 대신 inv_balance + product + ref_bin 을 직접(창고 이름 · sku 술어 · 집합 무변 — (창고, null) 창고 전체 251 → 161 ms · 뷰는 last_ev 62k 행 · baseline_at · product Seq Scan 을 호출마다 더 셌다)$c$;

-- ═══ 2) stk_availability — lastev 만 직접 읽기 · 그 밖 바이트 그대로 ═══
-- 마지막 정의 md5(바꾸기 전 DB prosrc) 6eda5898b7f8b8213f53eb732f38de30
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
           sum(pw.on_order) as on_order, sum(pw.in_transit) as in_transit, max(pw.last_event_on) as last_event_on, sum(pw.bgrade) as bgrade,   -- bgr-1a
           jsonb_agg(jsonb_build_object('warehouse_id', pw.wh, 'warehouse', pw.whname,
                                        'on_hand', pw.on_hand, 'sales_allocated', pw.sales_allocated, 'transfer_reserved', pw.transfer_reserved,
                                        'available', pw.on_hand - pw.sales_allocated - pw.transfer_reserved,
                                        'on_order', pw.on_order, 'in_transit', pw.in_transit, 'last_event_on', pw.last_event_on, 'bgrade', pw.bgrade) order by pw.whname) as by_warehouse   -- bgr-1a: bgrade(수량만 · 판정 262 · 575)
    from pw group by pw.pid
  ),
  sale as (                                                                                -- sale-1 판정 361: 오늘 세일(so_sale_now · 식 한 곳) — 낱개 줄에 붙인다
    select z.product_id, z.best_pct, z.conditional from public.so_sale_now(null, null) z
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
           coalesce(agg.bgrade, 0)             as bgrade,                                  -- bgr-1a: rows_kept 가 본다(반환 칸 아님)
           agg.by_warehouse
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
  select r.id, r.sku, r.name, r.brand_id, r.brand_name, r.category_id, r.category_name, r.is_active,
         r.on_hand, r.sales_allocated, r.transfer_reserved, r.available, r.on_order, r.in_transit, r.last_event_on,
         r.matched_set_sku, r.matched_set_pack_factor, r.matched_set_count,
         r.sale_pct, r.sale_conditional,
         count(*) over () as total,
         r.by_warehouse
  from rows_kept r
  order by r.sku, r.id
  limit v_limit offset v_offset;
end;
$function$;
comment on function public.stk_availability(uuid,text,uuid,uuid,boolean,integer,integer,boolean,uuid) is $c$⭐ 브랜치별 재고 가용표 한 쪽(stk-1 · 판정 257 ~ 262 · 266 ~ 268 · sale-1 판정 361 · ⭐ stk-av-1 재발행 판정 570 · 571 · 575 · 2026-10-20) — 줄 = 재고 키(낱개 · 세트 · 콤보 줄 없음) × 고른 창고(활성만 · ⭐ p_warehouse_id null = Both = 활성 창고 전부 · 평평한 열은 합 · by_warehouse jsonb [{warehouse_id · warehouse · on_hand · sales_allocated · transfer_reserved · available · on_order · in_transit · last_event_on}] 창고 이름 순 · 한 창고면 원소 하나) · on_hand · sales_allocated · transfer_reserved · available · on_order · in_transit · last_event_on · 세트 sku 검색 → 낱개 줄(matched_set_*) · ⭐ p_q 가 활성 바코드와 정확히 같으면 그 제품(세트 바코드 → 낱개 줄 + 세트 표시 · 여러 제품이면 전부) · ⭐ p_supplier_id = 그 공급처의 활성 줄이 있는 제품 전부(기본 아니어도 · 세트 줄은 낱개로) · p_include_zero 거짓이면 다섯 숫자(Both 는 합) 모두 0 인 줄만 뺀다 · sale_pct · sale_conditional(so_sale_now) · p_sale_only · total = 거른 뒤 전체 수 · 문 = 로그인 + 활성 직원(열쇠 안 봄 · 판정 268) · definer · limit ≤ 500 · ⭐ 원가 열 없음(판정 262 · 575 — 금액은 stk_value_many · stk_value_total · 원가 열쇠) · rows_all 의 where 는 stk_value_total 의 keys 와 서로 같은 조건 · wms-balance-perf-2a(2026-11-02 · deferred 450 ②-a): lastev 는 뷰 대신 inv_ledger 직접 max(occurred_on)(창고마다 334 → 123 ms · 집합 무변) · av 는 inv_available_base 가 같은 차수에서 직접 읽는다 · ②-b(by_warehouse 를 페이지에만) · ②-c(sale) 는 따로$c$;

-- ═══ 3) 자기 검사 — 둘 다 뷰를 더는 읽지 않는다 · 서명 · 속성 · 뷰 무접촉 ═══
do $$
declare v_bad text := '';  v_n text;
begin
  for v_n in select proname from pg_proc where pronamespace = 'public'::regnamespace and proname in ('inv_available_base', 'stk_availability') and prosrc ~ 'public\.ims_inv_balance\M' loop
    v_bad := v_bad || ' view_still_used:' || v_n;
  end loop;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('inv_available_base', 'stk_availability')) <> 2 then v_bad := v_bad || ' overloads'; end if;
  if (select pg_get_function_identity_arguments(oid) from pg_proc where oid = 'public.inv_available_base(uuid, uuid[])'::regprocedure) <> 'p_location_id uuid, p_stock_pids uuid[]' then v_bad := v_bad || ' iab_signature'; end if;
  if (select string_agg(proname || ':' || provolatile::text || prosecdef::text, ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('inv_available_base', 'stk_availability'))
     <> 'inv_available_base:strue stk_availability:strue' then v_bad := v_bad || ' attrs'; end if;
  if not has_function_privilege('authenticated', 'public.inv_available_base(uuid, uuid[])', 'execute') or not has_function_privilege('authenticated', 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)', 'execute') then v_bad := v_bad || ' acl'; end if;
  if (select reloptions::text from pg_class where relname = 'ims_inv_balance' and relnamespace = 'public'::regnamespace) <> '{security_invoker=true}' then v_bad := v_bad || ' view_options'; end if;
  if v_bad <> '' then raise exception 'wms-balance-perf-2a self-check failed:%', v_bad; end if;
end $$;
-- 검증 E 상수(태그 줄을 뺀 새 본문 md5 / 태그 줄 수): inv_available_base=69b29679f6a5c41ade618f77e3290600/6 stk_availability=e9795444d37d245dfbd837833dbfe2c5/1
