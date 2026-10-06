-- ─────────────────────────────────────────────────────────────
-- 브랜치별 재고 가용 읽기 창구 — 가용 식을 속 함수로 · so_available_many 껍데기 · stk_availability · stk_bins (Asung-IMS · stk-1 · 2026-10-06)
--   정본(뒤에 적는다): so-module §46 — 판정 257 ~ 268 · stk-0 조사 · stk-1 이견 1 ~ 11(전부 채택) · 2-d · 5-f(가용 식 한 곳) · §27 묶음 2(트랜스퍼 예약)
--   판정 264  가용 속 함수는 definer — transfer 열쇠 없는 직원도 트랜스퍼 예약을 뺀 같은 가용을 본다(20260924020852 「definer 로 바꾸지 않는다」의 정정 · 트랜스퍼 표가 09-28 에 생겨 생긴 결함 · 실측: sales 만 가진 직원에게 allocated_ea 2 → 0)
--   판정 265  속 함수 이름 inv_available_base(p_location_id, p_stock_pids default null) → (stock_pid · qty_ea · sales_alloc_ea · transfer_alloc_ea) · null = 창고의 모든 재고 키(조인 한 문장 · 7,663 키 ~170 ms) · 배열 = 그 키만(장부는 sku = any 로 뷰 안 인덱스에 밀어넣는다 · 1 키 ~56 ms · 100 키 ~62 ms · 줄마다 부르는 inv_transfer_lines_paste · transfers.html 에 회귀 없음) · 식 셋(장부 · 판매 예약 · 트랜스퍼 예약)은 여기 한 곳
--   판정 258  stk_* 보기 = 로그인한 직원 누구나 · 판정 268 문 = 로그인 + 활성 직원 · 판정 262 원가(inv_ledger.amount · 발주 단가)는 절대 내지 않는다
--   판정 259  접두 stk_ · 판정 260 on_order = 확정 발주 줄 qty_ea − 확정 입고 줄 qty_ea(0 아래 0 · po.ship_to_warehouse_id) · 판정 261 세트 sku 검색 → 낱개 줄(matched_set_sku · matched_set_pack_factor) · 콤보 줄 없음
--   판정 266  p_include_zero = false 는 다섯 숫자(on_hand · sales · transfer · on_order · in_transit)가 모두 0 인 줄만 뺀다 · 판정 267 세트 여러 개가 맞는 낱개 줄은 첫 세트(sku 순) + matched_set_count
--   in_transit = inv_transfer status in (in_transit · receiving) 줄의 (qty_sent − qty_received − qty_lost − qty_returned) × pack_factor · 0 아래 0 · to_warehouse_id(stk-0 정의 · 실물 0 · 가짜 문서로 시험)
--   재발행 하나 — so_available_many(마지막 정의 20260928201753:425 ~ 468 · DB prosrc md5 4d2cf12e… 와 일치 확인 · 본문만 · 시그니처 · invoker · grant · 바뀐 줄은 본문 전부 = 껍데기 · 원본 diff 는 보고) · 부르는 곳 8 함수 + 화면 2 는 무접촉(같은 값 — 소유자 · transfer 열쇠 있는 직원 · transfer 열쇠 없는 직원만 트랜스퍼 예약만큼 달라진다 = 판정 264)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 표 · 행 · 정책 무접촉 · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다
-- ─────────────────────────────────────────────────────────────
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

-- ═══ 1) 속 함수 inv_available_base — 가용 식 한 곳(판정 264 · 265) ═══
create function public.inv_available_base(p_location_id uuid, p_stock_pids uuid[] default null)
  returns table (stock_pid uuid, qty_ea numeric, sales_alloc_ea numeric, transfer_alloc_ea numeric)
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  with wh as (                                                                            -- 창고 이름 — 뷰는 warehouse(이름) · sku 로 걸러야 inv_ledger (sku, warehouse) 인덱스로 내려간다(warehouse_id · product_id 로 거르면 뷰 전체 18k 행을 센다)
    select w.name from public.ref_warehouse w where w.id = p_location_id
  ),
  skus as (                                                                              -- 부른 키의 sku 들 — p_stock_pids 가 null 이면 null(= 전부)
    select case when p_stock_pids is null then null else (select array_agg(p.sku) from public.product p where p.id = any(p_stock_pids)) end as arr
  ),
  bal as (                                                                               -- 장부 — 창고의 모든 bin 합(ims_inv_balance · product 에 없는 sku 는 재고 키가 아니다)
    select b.product_id as stock_pid, sum(b.qty) as qty
    from public.ims_inv_balance b
    where b.warehouse = (select name from wh) and b.product_id is not null
      and ((select k.arr from skus k) is null or b.sku = any((select k.arr from skus k)::text[]))   -- 스칼라 서브쿼리(InitPlan 상수)라 뷰 안 인덱스 조건으로 내려간다 · 괄호만 쓰면 서브쿼리 꼴(text = text[])로 읽힌다
    group by b.product_id
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
    group by 1
  ),
  keys as (
    select stock_pid from bal union select stock_pid from alloc union select stock_pid from talloc
  )
  select k.stock_pid,
         coalesce(bal.qty, 0),
         coalesce(alloc.ea, 0),
         coalesce(talloc.ea, 0)
  from keys k
  left join bal    on bal.stock_pid    = k.stock_pid
  left join alloc  on alloc.stock_pid  = k.stock_pid
  left join talloc on talloc.stock_pid = k.stock_pid;
$$;
revoke all on function public.inv_available_base(uuid, uuid[]) from public, anon;
grant execute on function public.inv_available_base(uuid, uuid[]) to authenticated;   -- invoker 껍데기(so_available_many · so_available · so_lines_available …)가 직원 신원으로 부른다 — revoke 하면 42501(2026-09-23 실사고)
comment on function public.inv_available_base(uuid, uuid[]) is
  '⭐⭐ 가용 재고 식 한 곳(stk-1 · 판정 264 · 265 · 2026-10-06 · 종전 so_available_many 본문) — 창고 하나의 재고 키(낱개 · 세트는 parent · p_stock_pids null = 전부 · 배열 = 그 키만 — 장부는 sku = any 로 뷰 안 인덱스에 밀어넣어 1 키 ~56 ms · 전부 ~170 ms · 배열 7,663 은 쓰지 마라(null 로)) → (stock_pid · qty_ea 창고 잔고 = ims_inv_balance 모든 bin 합 · sales_alloc_ea Σ 열린 allocated 예약 × pack_factor(오더 창고) · transfer_alloc_ea Σ 확정 · at_wms · picking 트랜스퍼 줄 qty × pack_factor(출발 창고)) · available = qty_ea − sales_alloc_ea − transfer_alloc_ea 는 부르는 쪽이 뺀다(so_available_many · stk_availability) · 조인 한 문장(= any 는 sku 밀어넣기에만 · product_id = any 는 뷰 전체를 센다) · ⭐ definer(판정 264): inv_transfer 의 select 정책은 transfer · WMS 열쇠인데 가용은 모든 직원에게 같아야 한다 — invoker 였던 so_available_many 는 sales 만 가진 직원에게 트랜스퍼 예약을 0 으로 보였다 · 원가 열 없음(판정 262) · authenticated execute(invoker 껍데기들이 부른다) · 음수 그대로 · preorder · hold · backorder 는 빼지 않는다';

-- ═══ 2) so_available_many 재발행 — 마지막 정의 20260928201753:425 ~ 468 · 시그니처 · invoker · grant 그대로 · 본문 = 껍데기(판정 264 · 265) ═══
create or replace function public.so_available_many(p_stock_pids uuid[], p_location_id uuid)
  returns table (stock_pid uuid, qty_ea numeric, allocated_ea numeric, available_ea numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  -- stk-1(2026-10-06 · 판정 264 · 265) — 식은 inv_available_base(definer · 배열을 그대로 넘긴다 · 장부는 sku 밀어넣기) 한 곳으로 갔다 · 이 껍데기는 부른 pid 마다 한 행을 내고 옛 세 칸 모양(allocated_ea = 판매 + 트랜스퍼)을 그대로 낸다 · 원본 20260928201753:425 ~ 468
  with pids as (
    select distinct u.pid as stock_pid from unnest(coalesce(p_stock_pids, '{}'::uuid[])) as u(pid)
  )
  select pids.stock_pid,
         coalesce(b.qty_ea, 0),
         coalesce(b.sales_alloc_ea, 0) + coalesce(b.transfer_alloc_ea, 0),
         coalesce(b.qty_ea, 0) - coalesce(b.sales_alloc_ea, 0) - coalesce(b.transfer_alloc_ea, 0)
  from pids
  left join public.inv_available_base(p_location_id, p_stock_pids) b on b.stock_pid = pids.stock_pid;
$$;
comment on function public.so_available_many(uuid[], uuid) is
  '⭐⭐ 가용 재고(②a′ · 5-f · 2-d) — 낱개 제품 배열 × 창고 → 행마다 (stock_pid · qty_ea 창고 잔고(ims_inv_balance 모든 bin 합) · allocated_ea Σ 열린 allocated 예약 × pack_factor + 트랜스퍼 예약(tr-1a 묶음 2) · available_ea 차) · 부른 pid 마다 한 행(잔고 없으면 0) · 음수 그대로(엔진이 0 으로 본다) · preorder·hold·backorder 는 빼지 않는다 · ⭐ stk-1(2026-10-06 · 판정 264 · 265): 식은 inv_available_base(definer · 창고 전체 한 문장)로 갔고 이 함수는 pid 로 거르는 껍데기다(반환 모양 · 값 무변 · transfer 열쇠 없는 직원만 트랜스퍼 예약만큼 달라진다 = 결함 정정) · so_available(화면 창구 · invoker · 직원이 부른다 ⇒ authenticated execute · 2026-09-24 ②a″)·so_allocate_run(엔진)·so_lines_available·so_detail·so_backorder_list·inv_transfer_shortage·inv_transfer_lines_paste·so.html·transfers.html 이 이것을 부른다 — 식이 두 곳이 되지 않게 · ⚠️ 낱개를 받는다(세트→낱개 환산은 부르는 쪽) · invoker(읽기만 · 속만 definer)';

-- ═══ 3) stk_availability — 가용표 한 쪽(판정 257 ~ 262 · 266 · 267 · 268) ═══
create function public.stk_availability(
  p_warehouse_id uuid,
  p_q            text    default null,
  p_brand_id     uuid    default null,
  p_category_id  uuid    default null,
  p_include_zero boolean default false,
  p_limit        int     default 100,
  p_offset       int     default 0
) returns table (
  product_id uuid, sku text, name text, brand_id uuid, brand_name text, category_id uuid, category_name text, is_active boolean,
  on_hand numeric, sales_allocated numeric, transfer_reserved numeric, available numeric, on_order numeric, in_transit numeric, last_event_on date,
  matched_set_sku text, matched_set_pack_factor numeric, matched_set_count int, total bigint
)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_q      text := nullif(btrim(p_q), '');
  v_limit  int  := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_offset int  := greatest(coalesce(p_offset, 0), 0);
begin
  -- 문(판정 268) — 로그인 + 활성 직원 · 열쇠는 보지 않는다(판정 258)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  if not exists (select 1 from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active) then
    raise exception 'Warehouse not found or inactive — pick an active branch';
  end if;
  return query
  with av as (                                                                           -- 장부 · 판매 예약 · 트랜스퍼 예약 — 식 한 곳(inv_available_base)
    select b.stock_pid, b.qty_ea, b.sales_alloc_ea, b.transfer_alloc_ea from public.inv_available_base(p_warehouse_id, null) b
  ),
  lastev as (
    select b.product_id, max(b.last_event_on) as last_event_on from public.ims_inv_balance b where b.warehouse = (select w.name from public.ref_warehouse w where w.id = p_warehouse_id) and b.product_id is not null group by 1
  ),
  onord as (                                                                             -- 판정 260 — 확정 발주 줄 − 확정 입고 줄 · 줄마다 0 아래는 0 · 발주의 배송 창고
    select coalesce(pr.parent_product_id, pr.id) as stock_pid, sum(greatest(l.qty_ea - coalesce(rc.recv, 0), 0)) as ea
    from public.po po
    join public.po_line l on l.po_id = po.id
    join public.product pr on pr.id = l.product_id
    left join (select rl.po_line_id, sum(rl.qty_ea) as recv
                 from public.po_receipt_line rl join public.po_receipt r on r.id = rl.receipt_id
                where r.status = 'confirmed' group by 1) rc on rc.po_line_id = l.id
    where po.status = 'confirmed' and po.ship_to_warehouse_id = p_warehouse_id
    group by 1
  ),
  intr as (                                                                              -- 운송 중 — 출발했고 아직 도착 창고에 다 들어오지 않은 트랜스퍼 줄 · 도착 창고
    select coalesce(pr.parent_product_id, pr.id) as stock_pid,
           sum(greatest(coalesce(l.qty_sent, 0) - coalesce(l.qty_received, 0) - coalesce(l.qty_lost, 0) - coalesce(l.qty_returned, 0), 0) * l.pack_factor) as ea
    from public.inv_transfer t
    join public.inv_transfer_line l on l.transfer_id = t.id
    join public.product pr on pr.id = l.product_id
    where t.status in ('in_transit', 'receiving') and t.to_warehouse_id = p_warehouse_id
    group by 1
  ),
  setm as (                                                                              -- 판정 261 · 267 — 세트 sku 검색 → 낱개 줄 · 첫 세트(sku 순) + 개수
    select s.parent_product_id as stock_pid,
           (array_agg(s.sku order by s.sku))[1]         as matched_set_sku,
           (array_agg(s.pack_factor order by s.sku))[1] as matched_set_pack_factor,
           count(*)::int                                as matched_set_count
    from public.product s
    where v_q is not null and s.parent_product_id is not null and s.sku ilike '%' || v_q || '%'
    group by 1
  ),
  rows_all as (
    select p.id, p.sku, p.name, p.brand_id, p.brand_name, p.category_id, p.category_name, p.is_active,
           coalesce(av.qty_ea, 0)            as on_hand,
           coalesce(av.sales_alloc_ea, 0)    as sales_allocated,
           coalesce(av.transfer_alloc_ea, 0) as transfer_reserved,
           coalesce(av.qty_ea, 0) - coalesce(av.sales_alloc_ea, 0) - coalesce(av.transfer_alloc_ea, 0) as available,
           coalesce(onord.ea, 0)             as on_order,
           coalesce(intr.ea, 0)              as in_transit,
           lastev.last_event_on,
           setm.matched_set_sku, setm.matched_set_pack_factor, setm.matched_set_count
    from public.product p                                                                -- 줄 = 재고 키 = 낱개(세트 · 콤보 줄 없음 · 판정 261)
    left join av     on av.stock_pid     = p.id
    left join lastev on lastev.product_id = p.id
    left join onord  on onord.stock_pid  = p.id
    left join intr   on intr.stock_pid   = p.id
    left join setm   on setm.stock_pid   = p.id
    where p.parent_product_id is null
      and not exists (select 1 from public.product_bom bm where bm.parent_product_id = p.id and bm.is_active)
      and (p_brand_id is null or p.brand_id = p_brand_id)
      and (p_category_id is null or p.category_id = p_category_id)
      and (v_q is null or p.sku ilike '%' || v_q || '%' or p.name ilike '%' || v_q || '%' or p.brand_name ilike '%' || v_q || '%' or setm.stock_pid is not null)
  ),
  rows_kept as (
    select r.* from rows_all r
    where p_include_zero
       or r.on_hand <> 0 or r.sales_allocated <> 0 or r.transfer_reserved <> 0 or r.on_order <> 0 or r.in_transit <> 0   -- 판정 266 — 다섯 숫자 모두 0 인 줄만 뺀다
  )
  select r.id, r.sku, r.name, r.brand_id, r.brand_name, r.category_id, r.category_name, r.is_active,
         r.on_hand, r.sales_allocated, r.transfer_reserved, r.available, r.on_order, r.in_transit, r.last_event_on,
         r.matched_set_sku, r.matched_set_pack_factor, r.matched_set_count,
         count(*) over () as total
  from rows_kept r
  order by r.sku, r.id
  limit v_limit offset v_offset;
end;
$$;
revoke all on function public.stk_availability(uuid, text, uuid, uuid, boolean, int, int) from public, anon;
grant execute on function public.stk_availability(uuid, text, uuid, uuid, boolean, int, int) to authenticated;
comment on function public.stk_availability(uuid, text, uuid, uuid, boolean, int, int) is
  '⭐ 브랜치별 재고 가용표 한 쪽(stk-1 · 판정 257 ~ 262 · 266 ~ 268 · 2026-10-06) — 줄 = 재고 키(낱개 · 세트 · 콤보 줄 없음) × 고른 창고(활성만) · on_hand · sales_allocated · transfer_reserved · available = on_hand − sales − transfer(식은 inv_available_base 한 곳) · on_order = 확정 발주 − 확정 입고(0 아래 0 · ship_to_warehouse_id · 판정 260) · in_transit = in_transit · receiving 트랜스퍼 줄의 (sent − received − lost − returned) × pack_factor(to_warehouse_id) · last_event_on(ims_inv_balance) · p_q = sku · 이름 · 브랜드 이름 ilike + 세트 sku 가 맞으면 그 낱개 줄(matched_set_sku · matched_set_pack_factor = 첫 세트 sku 순 · matched_set_count · 판정 261 · 267) · p_include_zero=false 는 다섯 숫자 모두 0 인 줄만 뺀다(판정 266 · 재고 0 인데 들어올 발주가 있는 줄은 보인다) · total = 거른 뒤 전체 수(모든 줄 같은 값) · 정렬 sku · p_limit 1 ~ 500(기본 100) · 문 = 로그인 + 활성 직원(판정 268 · 열쇠 안 봄 · 판정 258) · definer(inv_transfer 정책을 비껴 모든 직원에게 같은 숫자 · §39-d 1) · 원가 열 없음(판정 262) · 사진은 화면이 product_image_primary(p_skus) 로 따로';

-- ═══ 4) stk_bins — 제품 하나 × 창고 하나의 bin 별 잔고 ═══
create function public.stk_bins(p_product_id uuid, p_warehouse_id uuid)
  returns table (bin_id uuid, bin text, bin_zone text, bin_is_active boolean, qty numeric, last_event_on date)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_sku   text;
  v_wh    text;
begin
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  -- 뷰는 sku · warehouse(이름)로 걸러야 inv_ledger (sku, warehouse) 인덱스로 내려간다 — product_id · warehouse_id 로 거르면 뷰 전체(18k 행)를 센다(327 ms → 25 ms · stk-1 실측)
  select p.sku into v_sku from public.product p where p.id = p_product_id;
  select w.name into v_wh from public.ref_warehouse w where w.id = p_warehouse_id;
  if v_sku is null or v_wh is null then return; end if;
  return query
  select b.bin_id, b.bin, b.bin_zone, b.bin_is_active, b.qty, b.last_event_on
  from public.ims_inv_balance b
  where b.sku = v_sku and b.warehouse = v_wh and b.qty <> 0
  order by b.bin, b.bin_id;
end;
$$;
revoke all on function public.stk_bins(uuid, uuid) from public, anon;
grant execute on function public.stk_bins(uuid, uuid) to authenticated;
comment on function public.stk_bins(uuid, uuid) is
  '⭐ 제품 하나 × 창고 하나의 bin 별 잔고(stk-1 · 판정 257 · 2026-10-06) — ims_inv_balance 를 sku · 창고 이름으로 걸러(인덱스 밀어넣기 · 25 ms) 그대로(bin_id · bin · bin_zone · bin_is_active · qty · last_event_on) · bin 없는 줄(창고 단위 재고)은 bin = '''' · bin_id null 한 줄 · 0 줄은 뺀다 · 정렬 bin 이름 · 합 = stk_availability.on_hand · 문 = 로그인 + 활성 직원(판정 268) · definer · 원가 없음(판정 262)';

-- ═══ 5) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if to_regprocedure('public.inv_available_base(uuid, uuid[])') is null or to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int)') is null or to_regprocedure('public.stk_bins(uuid, uuid)') is null then v_bad := v_bad || ' functions'; end if;
  if not (select bool_and(p.prosecdef) from pg_proc p where p.oid in (to_regprocedure('public.inv_available_base(uuid, uuid[])'), to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int)'), to_regprocedure('public.stk_bins(uuid, uuid)'))) then v_bad := v_bad || ' definer'; end if;
  if (select p.prosecdef from pg_proc p where p.oid = to_regprocedure('public.so_available_many(uuid[], uuid)')) then v_bad := v_bad || ' so_available_many(must stay invoker)'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.so_available_many(uuid[], uuid)');
  if v_src not like '%inv_available_base(p_location_id, p_stock_pids)%' or v_src like '%so_reserve%' or v_src like '%inv_transfer_line%' then v_bad := v_bad || ' so_available_many(body)'; end if;
  if not has_function_privilege('authenticated', to_regprocedure('public.so_available_many(uuid[], uuid)'), 'execute') or not has_function_privilege('authenticated', to_regprocedure('public.inv_available_base(uuid, uuid[])'), 'execute') then v_bad := v_bad || ' grants'; end if;
  if exists (select 1 from pg_proc p where p.oid in (to_regprocedure('public.inv_available_base(uuid, uuid[])'), to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int)'), to_regprocedure('public.stk_bins(uuid, uuid)'))
               and (pg_get_function_result(p.oid) ~* '(amount|unit_price|cost)')) then v_bad := v_bad || ' cost_column'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM264', message = format('STOP - stk-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
