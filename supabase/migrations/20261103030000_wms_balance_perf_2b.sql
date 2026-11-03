-- ─────────────────────────────────────────────────────────────
-- wms-balance-perf-2b ②-b — stk_availability 의 by_warehouse jsonb 를 페이지 줄에만(Asung-IMS · 2026-11-02 밤 · ② 측정 보고 → Caleb 「③ → ②-b → ②-c」 · deferred 450 · ① afdd8ec · ②-a 6107e23 · ③ 20261103023000)
--   측정(Both · 따뜻한 캐시 · ②-a 뒤): 본체 약 1,400 ms 중 뼈대(product × whs 25,644 행 → agg → 조인 → window → 정렬) 523 ms · 그중 by_warehouse jsonb_agg 가 425 ms — 100 줄을 돌려주면서 12,822 제품 전부의 창고별 jsonb 를 만들었다.
--   고침(결과 그대로 — 반환 열 · 값 · 순서 무변):
--     agg 는 합계(on_hand · 예약 · 온주문 · 운송 · last_event · B급)만 · rows_all · rows_kept(거르기)는 그대로 · 새 CTE page = rows_kept 에서 count(*) over() · order by sku, id · limit · offset(옛 끝 문장과 같다) ·
--     새 CTE bw = page 와 pw 를 조인해 그 줄들에만 jsonb_agg(키 · 값 · whname 순서 옛 그대로) · 끝 문장은 page left join bw · order by sku, id.
--     pw 는 agg · bw 둘이 읽어 한 번 물질화된다(25,644 행 · 숫자만 · 싸다). 본문 그 밖은 DB prosrc 바이트 그대로(검증 E 가 「태그 줄 뺀 본문 = 옛 본문에서 바뀐 줄 뺀 것 + 닫는 괄호 한 줄」 로 잰다).
--   stk_availability_export 는 이 함수를 (…, 20000, 0, …) 으로 부르는 껍데기(stkx-1) — 본문 무변 · 20,000 줄은 page = 전수라 jsonb 몫은 그대로(내보내기는 어차피 전부 필요).
--   화면이 쓰는 칸(grep · stock.html · wms-stock.html): 줄 = product_id · sku · name · brand_name · category_name · is_active · on_hand · sales_allocated · transfer_reserved · available · on_order · in_transit · last_event_on ·
--     matched_set_sku · matched_set_pack_factor · matched_set_count · sale_pct · sale_conditional · total · by_warehouse — by_warehouse[] 는 warehouse_id 로 찾아(순서 아님) warehouse · on_hand · sales_allocated · transfer_reserved · available · on_order · in_transit · last_event_on · bgrade 를 읽는다. 전부 그대로.
--   마지막 정의: stk_availability 20261103010000_wms_balance_perf_2a.sql(그 전 20261023131028_bgr_1a_bgrade_bins.sql).
--   권한 그대로: create or replace(acl · definer · stable · search_path · 소유자 · 반환형 무변).
--   무접촉: inv_available_base · so_sale_now(②-c 는 따로) · stk_availability_export · stk_value_total(rows_all 의 where 와 짝 — 안 건드림) · 뷰 · 화면.
--   틀리면: 재고 화면 목록 · 상세의 창고별 숫자 · 내보내기 — 읽기만. 검증: 옛 vs 새 jsonb 같음(Both · 한 창고 · 검색 · Zero stock 켬 · 2 쪽 · 세일만 · 내보내기 20,000).
--   적용: Caleb 이 psql -1 -f + supabase migration repair --status applied 20261103030000 · db push 금지 · 토론토 07:00 전.
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) stk_availability — agg 에서 jsonb 를 빼고 page · bw 로 · 그 밖 바이트 그대로 ═══
-- 마지막 정의 md5(바꾸기 전 DB prosrc · ②-a 뒤) d5bc13a4f75c85686527bdf3c8573a9c
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
comment on function public.stk_availability(uuid,text,uuid,uuid,boolean,integer,integer,boolean,uuid) is $c$⭐ 브랜치별 재고 가용표 한 쪽(stk-1 · 판정 257 ~ 262 · 266 ~ 268 · sale-1 판정 361 · ⭐ stk-av-1 재발행 판정 570 · 571 · 575 · 2026-10-20) — 줄 = 재고 키(낱개 · 세트 · 콤보 줄 없음) × 고른 창고(활성만 · ⭐ p_warehouse_id null = Both = 활성 창고 전부 · 평평한 열은 합 · by_warehouse jsonb [{warehouse_id · warehouse · on_hand · sales_allocated · transfer_reserved · available · on_order · in_transit · last_event_on}] 창고 이름 순 · 한 창고면 원소 하나) · on_hand · sales_allocated · transfer_reserved · available · on_order · in_transit · last_event_on · 세트 sku 검색 → 낱개 줄(matched_set_*) · ⭐ p_q 가 활성 바코드와 정확히 같으면 그 제품(세트 바코드 → 낱개 줄 + 세트 표시 · 여러 제품이면 전부) · ⭐ p_supplier_id = 그 공급처의 활성 줄이 있는 제품 전부(기본 아니어도 · 세트 줄은 낱개로) · p_include_zero 거짓이면 다섯 숫자(Both 는 합) 모두 0 인 줄만 뺀다 · sale_pct · sale_conditional(so_sale_now) · p_sale_only · total = 거른 뒤 전체 수 · 문 = 로그인 + 활성 직원(열쇠 안 봄 · 판정 268) · definer · limit ≤ 500 · ⭐ 원가 열 없음(판정 262 · 575 — 금액은 stk_value_many · stk_value_total · 원가 열쇠) · rows_all 의 where 는 stk_value_total 의 keys 와 서로 같은 조건 · wms-balance-perf-2a(2026-11-02 · deferred 450 ②-a): lastev 는 뷰 대신 inv_ledger 직접 max(occurred_on)(창고마다 334 → 123 ms · 집합 무변) · av 는 inv_available_base 가 같은 차수에서 직접 읽는다 · ②-b(by_warehouse 를 페이지에만) · ②-c(sale) 는 따로 · wms-balance-perf-2b(2026-11-02 · deferred 450 ②-b): by_warehouse jsonb 는 전수가 아니라 페이지 줄(limit 뒤)에만 만든다(page → bw) · 합계 · 거르기 · 정렬 · total 은 전수 그대로 · 반환 열 · 값 · 순서 무변(Both 1,409 → 약 1,000 ms · 뼈대 523 → 97) · stk_availability_export 는 이 함수를 20,000 으로 부르는 껍데기라 무변$c$;

-- ═══ 2) 자기 검사 — 서명 · 반환 열 · 속성 · page · bw 가 있다 · agg 에 jsonb 없다 ═══
do $$
declare v_bad text := '';  v_src text;
begin
  select prosrc into v_src from pg_proc where oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure;
  if v_src is null then v_bad := v_bad || ' missing'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'stk_availability') <> 1 then v_bad := v_bad || ' overloads'; end if;
  if v_src !~ ', page as \(' or v_src !~ '\), bw as \(' then v_bad := v_bad || ' no_page_bw'; end if;
  if (select count(*) from regexp_matches(v_src, 'jsonb_agg\(jsonb_build_object\(''warehouse_id''', 'g')) <> 1 then v_bad := v_bad || ' jsonb_count'; end if;
  if v_src ~ 'agg\.by_warehouse' then v_bad := v_bad || ' agg_by_warehouse_left'; end if;
  if (select pg_get_function_result(oid) from pg_proc where oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure)
     !~ 'total bigint, by_warehouse jsonb\)$' then v_bad := v_bad || ' result_cols'; end if;
  if (select provolatile::text || prosecdef::text from pg_proc where oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure) <> 'strue' then v_bad := v_bad || ' attrs'; end if;
  if v_bad <> '' then raise exception 'wms-balance-perf-2b self-check failed:%', v_bad; end if;
end $$;
-- 검증 E 상수(태그 줄을 뺀 새 본문 md5 / 태그 줄 수): 3da1cb178caa2a7f187e34854807e768/20
