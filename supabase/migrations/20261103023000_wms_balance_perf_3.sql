-- ─────────────────────────────────────────────────────────────
-- wms-balance-perf-3 ③ — 나머지 장부 호출자 넷(Asung-IMS · 2026-11-02 밤 · 지시서 wms-balance-perf-1 §0 ③ · Caleb 「③ → ②-b → ②-c · 마감 토론토 07:00」 · deferred 450 · ① afdd8ec · ②-a 6107e23)
--   측정(따뜻한 캐시): wms_pick_shelf 의 bk(req 와 sku 조인 + 창고 변수) 110 ms — 조인 키만으로는 planner 가 창고 전체(67k 행)를 집계 · InitPlan 상수를 한 번 더 걸면 1.2 ms.
--        bgrade_stock 의 x(B급 칸 CTE 와 창고 · 칸 이름 조인) 195 ms — 장부 전체 111k 행 집계(5 batches 디스크).
--        inv_move_bin_contents · ref_bin_bgrade_set(창고 이름 + 칸 이름 · plpgsql 변수 = 파라미터) 229 ms — 술어는 이미 집계 안으로 들어가지만 (warehouse, bin) 인덱스가 없어 스냅샷 7,523 행 · 원장 97,583 행을 훑는다.
--        뷰 · 함수의 bin 은 coalesce(bin, '') 라 보통 (warehouse, bin) 인덱스는 못 탄다 — 식 인덱스 (warehouse, coalesce(bin, ''), sku) 로 0.3 ms(트랜잭션 안 시험 · 두 인덱스 만들기 1.7 s).
--   고침(결과 그대로 — 집합 무변):
--     1) 인덱스 둘 — inv_ledger_wh_bin_sku_idx (warehouse, coalesce(bin, ''), sku) · inv_snapshot_key_wh_bin_sku_idx (snapshot_key, warehouse, coalesce(bin, ''), sku). ⚠️ create index(concurrently 아님 · psql -1 안) — 만드는 1 ~ 2 초 동안 두 표에 쓰기가 기다린다(두 창고 멈춤 · 원장 쓰기는 출고 · 입고뿐).
--     2) wms_pick_shelf — bk 에 「b.sku = any(req 의 sku 배열)」 한 줄(조인 조건 r.sku 와 같은 값 · 중복 술어 · 집합 무변).
--     3) bgrade_stock — x 조인에 「ib.warehouse = any(b 의 wh 배열) and ib.bin = any(b 의 name 배열)」 한 줄(조인 조건과 같은 값 · 집합 무변 · 새 인덱스로).
--     4) inv_move_bin_contents · ref_bin_bgrade_set — 본문 무변(바꿀 것이 없다 · 술어가 이미 파라미터로 들어간다) · 새 인덱스만으로 229 → 0.3 ms. 검증 E 가 두 함수 md5 무변을 잰다.
--     본문 그 밖은 DB prosrc 바이트 그대로(md5 는 각 절 머리 · 검증 E 가 「태그 줄 뺀 본문 = 옛 본문에서 바뀐 줄 뺀 것」 으로 잰다).
--   마지막 정의: wms_pick_shelf · ref_bin_bgrade_set 20261023131028_bgr_1a_bgrade_bins.sql · bgrade_stock · inv_move_bin_contents 20261023135121_bgr_1b_bgrade_price_moves.sql.
--   권한 그대로: create or replace(acl · definer · 속성 · 소유자 무변 — bgrade_stock 은 authenticated 만 · 나머지 service_role 도).
--   무접촉: 뷰 ims_inv_balance · inv_balance · ims_inv_balance_of · ① · ②-a 함수 · 그 밖 장부 호출자(wms_health_check · inv_stock_master · inv_adjust_ledger · product_update · stk_bins · stk_bins_many) · 화면.
--   틀리면: 픽 선반 보기 · B급 재고 화면 · 칸 비우기(mover) 목록 · B급 표시 켜기 · 끄기 거부 — 재고 쓰기에는 닿지 않는다(ref_bin_bgrade_set 의 쓰기는 is_bgrade 표시 하나 · 장부 읽기 결과로 거부만 정한다).
--   적용: 두 창고가 멈춘 뒤 Caleb 이 psql -1 -f + supabase migration repair --status applied 20261103023000 · db push 금지 · 토론토 07:00 전.
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) 식 인덱스 둘 — 창고 + 칸 이름(coalesce(bin, '')) 키 · sku 를 뒤에(집계 키 셋이 인덱스 안에서 끝난다) ═══
create index inv_ledger_wh_bin_sku_idx on public.inv_ledger (warehouse, (coalesce(bin, '')), sku);
create index inv_snapshot_key_wh_bin_sku_idx on public.inv_snapshot (snapshot_key, warehouse, (coalesce(bin, '')), sku);
comment on index public.inv_ledger_wh_bin_sku_idx is 'wms-balance-perf-3(2026-11-02 · deferred 450 ③) — 창고 + 칸 이름으로 장부를 읽는 호출자(inv_move_bin_contents · ref_bin_bgrade_set · bgrade_stock · 화면의 칸 조회)용 · 뷰 inv_balance 의 bin 이 coalesce(bin, '') 라 식 인덱스';
comment on index public.inv_snapshot_key_wh_bin_sku_idx is 'wms-balance-perf-3(2026-11-02 · deferred 450 ③) — 기초 스냅샷 갈래의 짝(snapshot_key 가 앞 · inv_balance 는 baseline_snapshot_key 하나만 읽는다)';

-- ═══ 2) wms_pick_shelf — bk 에 sku 집합 InitPlan 술어 한 줄 · 그 밖 바이트 그대로 ═══
-- 마지막 정의 md5(바꾸기 전 DB prosrc) 8c6f9ffdc3f90561256cba8c0a439110
create or replace function public.wms_pick_shelf(p_warehouse_id uuid, p_skus text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_wh public.ref_warehouse%rowtype; v_items jsonb;
begin
  perform public.ims_require_write('picking', 'saved');                                   -- ⭐ 첫 줄(wms_pick_line_save 와 같다 · 판정 39 · fail-closed)
  if p_warehouse_id is null or not public.ims_can_warehouse(p_warehouse_id) then           -- ⭐ 둘째(같은 문장)
    raise exception 'This task is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  select * into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if not found then raise exception 'Warehouse not found or inactive — nothing was saved'; end if;
  if p_skus is null or cardinality(array_remove(p_skus, null)) = 0 then raise exception 'p_skus must be a list of SKUs — nothing was saved'; end if;
  with req as (                                                                            -- 입력 SKU → 낱개 상품(세트는 parent 로 접는다) · 모르는 SKU 는 글자 그대로 · 같은 낱개로 접히면 한 줄
    select distinct on (coalesce(sp.sku, btrim(s.sku))) coalesce(sp.sku, btrim(s.sku)) as sku, sp.id as product_id, sp.name as product_name
      from unnest(p_skus) as s(sku)
      left join public.product p  on p.sku = btrim(s.sku)
      left join public.product sp on sp.id = coalesce(p.parent_product_id, p.id)
     where btrim(coalesce(s.sku, '')) <> ''
  ), bk as (                                                                               -- 장부 — 그 창고 · 칸 있는 행 · qty ≠ 0
    select r.sku, b.bin, b.qty as book
      from req r join public.inv_balance b on b.sku = r.sku and b.warehouse = v_wh.name
     where b.sku = any((select array_agg(r2.sku) from req r2)::text[])                   -- wms-balance-perf-3(deferred 450 ③): 같은 sku 집합을 InitPlan 상수로 한 번 더 걸어 inv_balance 의 집계 안(inv_ledger_sku_wh_on_idx · inv_snapshot_uq)으로 내려보낸다 — CTE 조인 키만으로는 planner 가 장부 전체(창고 67k 행)를 집계했다 · 집합 무변(r.sku 와 같은 조건)
       and b.bin <> '' and b.qty <> 0                                                     -- wms-balance-perf-3
       and not exists (select 1 from public.ref_bin rb0 where rb0.warehouse_id = v_wh.id and rb0.name = b.bin and rb0.is_bgrade)   -- bgr-1a 판정 635: 선반 보기에 B급 칸 없음
  ), pl as (                                                                               -- 열린 픽 계획 칸(이 창고 · 이 상품들)
    select distinct coalesce(pr.parent_product_id, pr.id) as product_id, pb.bin_id, pb.bin
      from public.wms_pick_line_bins pb
      join public.wms_pick_task_lines l on l.id = pb.pick_task_line_id
      join public.wms_pick_tasks t on t.id = l.pick_task_id
      join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
      join public.wms_order_doc_line ol on ol.line_id = coalesce(l.order_line_id, l.transfer_line_id)
      join public.product pr on pr.id = ol.product_id
     where pb.planned and t.status in ('pending', 'in_progress') and d.warehouse_id = v_wh.id and d.wms_stage in ('at_wms', 'picking')
       and coalesce(pr.parent_product_id, pr.id) in (select q.product_id from req q where q.product_id is not null)
  ), pk as (                                                                               -- P — inv_adjust_picked 와 같은 술어 · (칸, 낱개 상품) 으로 한 번에
    select pb.bin_id, coalesce(pr.parent_product_id, pr.id) as product_id, sum(pb.qty_base) as picked
      from public.wms_pick_line_bins pb
      join public.wms_pick_task_lines l on l.id = pb.pick_task_line_id
      join public.wms_pick_tasks t on t.id = l.pick_task_id
      join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
      join public.wms_order_doc_line ol on ol.line_id = coalesce(l.order_line_id, l.transfer_line_id)
      join public.product pr on pr.id = ol.product_id
     where not pb.planned and d.warehouse_id = v_wh.id and d.status in ('picking', 'packed')
       and coalesce(pr.parent_product_id, pr.id) in (select q.product_id from req q where q.product_id is not null)
     group by 1, 2
  ), bins as (                                                                             -- 장부 칸(이름 → ref_bin id) ∪ 계획 칸(장부에 없는 것만 · book 0)
    select r.sku, r.product_id, rb.id as bin_id, bk.bin, bk.book
      from bk join req r on r.sku = bk.sku
      left join public.ref_bin rb on rb.warehouse_id = v_wh.id and rb.name = bk.bin
    union
    select r.sku, r.product_id, pl.bin_id, pl.bin, 0::numeric
      from pl join req r on r.product_id = pl.product_id
     where not exists (select 1 from bk where bk.sku = r.sku and bk.bin = pl.bin)
  ), x as (
    select b.sku, b.product_id, b.bin_id, b.bin, b.book, coalesce(pk.picked, 0) as picked,
           exists (select 1 from pl where pl.product_id = b.product_id and pl.bin_id = b.bin_id) as planned
      from bins b
      left join pk on pk.bin_id = b.bin_id and pk.product_id = b.product_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'product_id', r.product_id, 'sku', r.sku, 'product_name', r.product_name,
           'bins', coalesce((select jsonb_agg(jsonb_build_object('bin_id', x.bin_id, 'bin', x.bin, 'book', x.book, 'picked', x.picked, 'on_shelf', x.book - x.picked, 'planned', x.planned) order by x.bin)
                              from x where x.sku = r.sku), '[]'::jsonb)) order by r.sku), '[]'::jsonb)
    into v_items from req r;
  return jsonb_build_object('warehouse_id', v_wh.id, 'warehouse', v_wh.name, 'items', v_items);
end;
$function$;
comment on function public.wms_pick_shelf(uuid,text[]) is $c$pick-shelf-1 · 판정 235 — 픽 화면의 선반 기대량: (창고, 낱개 SKU 목록) → 상품마다 칸마다 book(inv_balance 그 칸) · picked(inv_adjust_picked 와 같은 술어 · 한 번에) · on_shelf = book − picked(판정 62 · 음수 그대로 · 기다리는 몫은 안 뺀다) · planned(열린 픽 계획 칸 · 장부 0 이어도 든다). 세트 SKU 는 낱개로 접는다 · 모르는 SKU 는 product_id null. 문 = wms_pick_line_save 와 같은 ims_require_write(picking) + ims_can_warehouse. stable · definer(§39-d 1) · 표시만 · 쓰기 없음. 2026-10-05 · wms-balance-perf-3(2026-11-02 · deferred 450 ③): 장부(bk)는 sku 집합을 InitPlan 상수로 한 번 더 걸어 인덱스로(110 → 1 ms · 집합 무변)$c$;

-- ═══ 3) bgrade_stock — x 조인에 창고 · 칸 집합 InitPlan 술어 한 줄 · 그 밖 바이트 그대로 ═══
-- 마지막 정의 md5(바꾸기 전 DB prosrc) 768feb98c548446556c0eb94a07b41bd
create or replace function public.bgrade_stock(p_warehouse_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_staff uuid;  v_rows jsonb;
begin
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- 문 = 로그인 + 활성 직원(stk_ 창구와 같다)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  with b as (
    select rb.id, rb.name, w.id as wh_id, w.name as wh from public.ref_bin rb join public.ref_warehouse w on w.id = rb.warehouse_id
     where rb.is_bgrade and w.is_active and (p_warehouse_id is null or w.id = p_warehouse_id)
  ), x as (
    select b.wh_id, b.wh, b.id as bin_id, b.name as bin, ib.sku, ib.qty, p.id as product_id, p.name as product_name,
           bp.price, bp.pct, bp.basis_price, bp.set_at, s.name as set_by,
           (select pp.price from public.product_price pp join public.ref_price_tier t on t.id = pp.tier_id where pp.product_id = p.id and t.code = 1 and t.purpose = 'sale') as wholesale_now
      from b join public.inv_balance ib on ib.warehouse = b.wh and ib.bin = b.name and ib.qty <> 0
                                        and ib.warehouse = any((select array_agg(b2.wh) from b b2)::text[]) and ib.bin = any((select array_agg(b2.name) from b b2)::text[])   -- wms-balance-perf-3(deferred 450 ③): 창고 · 칸 이름 집합을 InitPlan 상수로 한 번 더 걸어 집계 안으로(새 식 인덱스 inv_ledger_wh_bin_sku_idx · inv_snapshot_key_wh_bin_sku_idx) — CTE 조인 키만으로는 장부 전체 111k 행 집계(5 batches) · 집합 무변(조인 조건과 같은 값)
      left join public.product p on p.sku = ib.sku
      left join public.bgrade_price bp on bp.bin_id = b.id and bp.product_id = p.id
      left join public.ims_staff s on s.id = bp.set_by
  )
  select coalesce(jsonb_agg(jsonb_build_object('warehouse_id', x.wh_id, 'warehouse', x.wh, 'bin_id', x.bin_id, 'bin', x.bin, 'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name,
           'qty', x.qty, 'price', x.price, 'pct', x.pct, 'basis_price', x.basis_price, 'wholesale_now', x.wholesale_now, 'set_by', x.set_by, 'set_at', x.set_at,
           'has_price', x.price is not null) order by x.wh, x.bin, x.sku), '[]'::jsonb)
    into v_rows from x;
  return jsonb_build_object('row_count', jsonb_array_length(v_rows), 'no_price_count', (select count(*) from jsonb_array_elements(v_rows) r where not (r->>'has_price')::boolean and (r->>'qty')::numeric > 0), 'rows', v_rows);
end $function$;
comment on function public.bgrade_stock(uuid) is $c$bgr-1b 판정 637 · 644 — B급 칸 × 제품 잔고 · B급 값 · % · 그때 Wholesale · 지금 Wholesale · 정한 사람 · has_price(false 이고 qty > 0 = 「값 없음」 · POS 가 막는다) · 수량 · 값만(원가 칸 없음) · jsonb 한 행 · wms-balance-perf-3(2026-11-02 · deferred 450 ③): 장부는 창고 · 칸 이름 집합을 InitPlan 상수로 한 번 더 걸어 새 식 인덱스(warehouse · coalesce(bin, ''))로(195 → 1 ms · 집합 무변)$c$;

-- ═══ 4) 자기 검사 — 인덱스 둘 · 둘은 바뀌고 둘은 그대로 · 속성 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from pg_indexes where schemaname = 'public' and indexname in ('inv_ledger_wh_bin_sku_idx', 'inv_snapshot_key_wh_bin_sku_idx')) <> 2 then v_bad := v_bad || ' indexes'; end if;
  if (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'inv_ledger_wh_bin_sku_idx') !~ 'USING btree \(warehouse, COALESCE\(bin, ''''::text\), sku\)' then v_bad := v_bad || ' idx_ledger_def'; end if;
  if (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'inv_snapshot_key_wh_bin_sku_idx') !~ 'USING btree \(snapshot_key, warehouse, COALESCE\(bin, ''''::text\), sku\)' then v_bad := v_bad || ' idx_snapshot_def'; end if;
  if (select prosrc from pg_proc where oid = 'public.wms_pick_shelf(uuid, text[])'::regprocedure) !~ 'b\.sku = any\(\(select array_agg\(r2\.sku\) from req r2\)::text\[\]\)' then v_bad := v_bad || ' pick_shelf_initplan'; end if;
  if (select prosrc from pg_proc where oid = 'public.bgrade_stock(uuid)'::regprocedure) !~ 'ib\.warehouse = any\(\(select array_agg\(b2\.wh\) from b b2\)::text\[\]\)' then v_bad := v_bad || ' bgrade_initplan'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.inv_move_bin_contents(uuid, uuid)'::regprocedure) <> '5375991777c4816930a7bd8f3f5d6f8f' then v_bad := v_bad || ' move_changed'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.ref_bin_bgrade_set(uuid, boolean)'::regprocedure) <> '593485fbf46435b86690a85531de8000' then v_bad := v_bad || ' bgset_changed'; end if;
  if (select string_agg(proname || ':' || provolatile::text || prosecdef::text, ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_pick_shelf', 'bgrade_stock'))
     <> 'bgrade_stock:strue wms_pick_shelf:strue' then v_bad := v_bad || ' attrs'; end if;
  if v_bad <> '' then raise exception 'wms-balance-perf-3 self-check failed:%', v_bad; end if;
end $$;
-- 검증 E 상수(태그 줄을 뺀 새 본문 md5 / 태그 줄 수): wms_pick_shelf=35d15384b47501245d10437958581c8a/2 bgrade_stock=768feb98c548446556c0eb94a07b41bd/1
