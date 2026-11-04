-- ─────────────────────────────────────────────────────────────
-- perf-rpc-1 — inv_available_base 의 bal 을 키 갈래 · 창고 전체 갈래 둘로(Asung-IMS · 2026-11-04 · 판정 1035 「화면 RPC 넷 가볍게」 첫 차수 · perf-rpc-0 조사 → 이견 답 1 ~ 4)
--   까닭(perf-rpc-0 실측 11-04 · 운영 메인): so_available_many 하루 1,128 회 · 평균 124 ms · 호출 수 1 위. SO-21021 꼴(63 키 → Edmonton) 함수 64 ms 중 bal CTE 56 ms —
--        원문 `Index Scan using inv_ledger_wh_bin_sku_idx … Index Cond: (warehouse = …) Filter: (((InitPlan 5).col1 IS NULL) OR (sku = ANY …)) Rows Removed by Filter: 18332 · shared hit=18589`.
--   진단(perf-rpc-1 §0 이견 1 · 실측): 범인은 뷰도 GROUP BY 순서도 아니라 `(… is null or b.sku = any(…))` 의 OR — planner 가 OR 를 색인 조건으로 못 써 warehouse 만 타고 sku 는 Filter.
--        같은 뷰 · 같은 GROUP BY 에서 OR 만 빼면 inv_snapshot_uq · inv_ledger_sku_wh_on_idx 로 56 + 354 행만 읽는다(bal 61.0 → 2.4 ms · 직접 UNION ALL 2.7 ms · 집합 같음).
--   고침(bal 하나 · 결과 그대로): 같은 뷰 inv_balance 로 두 갈래 UNION ALL — ① 키 갈래 = 옛 줄에 OR 자리만 `arr is not null and sku = any(…)` · ② 창고 전체 갈래 = 옛 줄 바이트 그대로 + 문 `arr is null` 한 줄.
--        문은 옛 식 그대로 `(select k.arr from skus k) is null`(p_stock_pids 가 아니다) — 빈 배열 · 모르는 pid 만이면 옛처럼 창고 전체(이견 답 2 · 옛 버릇 유지).
--        에뮬레이션(generic plan · 63 키 Edmonton): 함수 60.4 → 6.4 ms · shared hit 21,105 → 2,222 · null 길 Edmonton 88 ~ 93 → 88 ~ 90 ms · Toronto 142 ~ 145 → 145 ~ 146 ms(무변) · 옛 = 새 6 입력(63 키 두 창고 · null 두 창고 · 빈 배열 · 모르는 pid) 집합 차 0.
--   무변: 서명 · 반환 · sql stable · security definer · search_path · acl · 소유자 · comment(손대지 않는다 — 안의 「1 키 ~56 ms」 는 낡은 숫자 · 보고에) · wh · skus · alloc · talloc · keys · 반환 select 바이트 그대로 · null 길 무변(결과 · 색인 · 시간).
--        뷰 inv_balance · ims_inv_balance · ims_inv_balance_of · so_available_many(껍데기) · 호출자 8 함수 · 화면 무접촉.
--   마지막 정의: 20261103010000_wms_balance_perf_2a.sql — 파일 본문 md5 = DB prosrc md5 = 3cacac3195fb93afb99a794a91cfbdf9(11-04 15:4x 대조). 머리(create or replace … AS $function$)는 그 파일 바이트 그대로.
--   틀리면: 가용(SO · 재고 화면 · 백오더 · 트랜스퍼 · POS) · Shopify 재고(shop_stock_payload) — 재고 쓰기에는 닿지 않는다. 검증: supabase/tests/perf_rpc_1_check.sql(G1 ~ G8 · 옛 = 새 같은 트랜잭션 · 적용 전 기준).
--   적용: 토론토 17:00 뒤 Caleb 이 psql -1 -f + supabase migration repair --status applied 20261104205654 · db push 금지.
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) inv_available_base — bal CTE 두 갈래 · 그 밖 바이트 그대로(허브 — 부르는 8 함수 무접촉 · comment 무변 = create or replace 가 지킨다) ═══
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
      and (select k.arr from skus k) is not null                                          -- perf-rpc-1(판정 1035): 키 갈래 — arr 가 있으면(배열 · 모르는 pid 만이거나 빈 배열은 arr null = 아래 창고 전체 갈래 · 옛 버릇 그대로) OR 없이 sku 술어만 — InitPlan 상수라 One-Time Filter
      and b.sku = any((select k.arr from skus k)::text[])                                 -- perf-rpc-1: OR 를 빼야 뷰 안 inv_snapshot_uq · inv_ledger_sku_wh_on_idx 로 내려간다(「is null or …」 는 planner 가 색인 조건으로 못 써 warehouse 만 타고 sku 는 Filter · 63 키 bal 56 → 2.4 ms · 집합 무변)
    group by p.id                                                                         -- wms-balance-perf-2a
    union all                                                                             -- perf-rpc-1: 창고 전체 갈래(아래) = 옛 줄 바이트 그대로 + 문 한 줄 · 두 갈래는 InitPlan 상수 문이라 한쪽만 돈다(never executed) · 뷰 inv_balance 그대로(잔고 정의 한 곳 · asung-inv-ledger 「같은 식을 다시 쓰지 마라」)
    select p.id as stock_pid, sum(b.qty) filter (where not coalesce(rb.is_bgrade, false)) as qty, sum(b.qty) filter (where coalesce(rb.is_bgrade, false)) as bg   -- wms-balance-perf-2a(deferred 450 ②-a): 뷰 대신 inv_balance + product + ref_bin 직접(뷰의 last_ev 62k 행 · baseline_at · product Seq Scan 을 안 센다 · 집합 무변) · bgr-1a 판정 641: 팔 수 있는 장부 = B급 칸을 뺀 합 · B급 칸 합은 bg 로 따로
    from public.inv_balance b                                                             -- wms-balance-perf-2a: 스냅샷(baseline_snapshot_key) + 원장 전 행 · sku · warehouse · bin 합 — 창고 이름 · sku 술어가 두 갈래로 내려간다
    join public.product p on p.sku = b.sku                                                -- wms-balance-perf-2a: 뷰의 product_id is not null 과 같은 집합(product_sku_key 유니크)
    left join public.ref_bin rb on rb.warehouse_id = p_location_id and rb.name = b.bin and b.bin <> ''   -- wms-balance-perf-2a: 뷰의 bin_is_bgrade = coalesce(rb.is_bgrade, false) · 뷰는 ref_warehouse(name = b.warehouse).id 로 붙이는데 그것이 p_location_id 다(ref_warehouse_name_key 유니크)
    where b.warehouse = (select name from wh)                                             -- wms-balance-perf-2a
      and ((select k.arr from skus k) is null or b.sku = any((select k.arr from skus k)::text[]))   -- 스칼라 서브쿼리(InitPlan 상수)라 뷰 안 인덱스 조건으로 내려간다 · 괄호만 쓰면 서브쿼리 꼴(text = text[])로 읽힌다
      and (select k.arr from skus k) is null                                              -- perf-rpc-1: 창고 전체 갈래 문(stk_availability · pur_stock 의 null 길 · 시간 · plan 무변 — 위 OR 줄을 남겨야 추정 행이 옛과 같아 Merge 조인 그대로)
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

-- ═══ 2) 자기 검사 — 서명 · 속성 · acl · 과부하 1 · 두 갈래 문 · 옛 줄 보존(태그 줄 넷 · 키 갈래를 빼면 옛 본문 md5) · comment 무변 · 뷰 무접촉 ═══
do $$
declare v_bad text := ''; v_src text; v_lines text[]; v_i int; v_bal int; v_k3 int; v_k4 int; v_rest text[] := '{}';
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_available_base') <> 1 then v_bad := v_bad || ' overloads'; end if;
  if (select pg_get_function_identity_arguments(oid) from pg_proc where oid = 'public.inv_available_base(uuid, uuid[])'::regprocedure) <> 'p_location_id uuid, p_stock_pids uuid[]' then v_bad := v_bad || ' signature'; end if;
  if (select pg_get_function_result(oid) from pg_proc where oid = 'public.inv_available_base(uuid, uuid[])'::regprocedure) <> 'TABLE(stock_pid uuid, qty_ea numeric, sales_alloc_ea numeric, transfer_alloc_ea numeric, bgrade_ea numeric)' then v_bad := v_bad || ' result'; end if;
  if (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '-') || (select l.lanname from pg_language l where l.oid = p.prolang) from pg_proc p where p.oid = 'public.inv_available_base(uuid, uuid[])'::regprocedure) <> 'strue{"search_path=public, pg_temp"}sql' then v_bad := v_bad || ' attrs'; end if;   -- 회차 1: prolang::regtype 은 언어 이름이 아니라 oid 글자(14)였다 → pg_language.lanname
  if not has_function_privilege('authenticated', 'public.inv_available_base(uuid, uuid[])', 'execute') or not has_function_privilege('service_role', 'public.inv_available_base(uuid, uuid[])', 'execute') or has_function_privilege('anon', 'public.inv_available_base(uuid, uuid[])', 'execute') then v_bad := v_bad || ' acl'; end if;
  if md5(coalesce(obj_description('public.inv_available_base(uuid, uuid[])'::regprocedure, 'pg_proc'), '')) <> '3e4be82f8818ab5bbe0b8b345e442d21' then v_bad := v_bad || ' comment_changed'; end if;
  select prosrc into v_src from pg_proc where oid = 'public.inv_available_base(uuid, uuid[])'::regprocedure;
  if v_src ~ 'public\.ims_inv_balance\M' then v_bad := v_bad || ' view_ims_inv_balance'; end if;
  if (select count(*) from regexp_matches(v_src, '-- perf-rpc-1', 'g')) <> 4 then v_bad := v_bad || ' tag_lines<>4'; end if;
  if (select count(*) from regexp_matches(v_src, '^\s*(update|delete)\s', 'gn')) <> 0 then v_bad := v_bad || ' write_stmt'; end if;
  -- 키 갈래(bal 머리 다음 줄 ~ union all 줄)와 문 한 줄을 빼면 옛 본문(perf-2a · 3cacac31…)과 바이트 같아야 한다
  v_lines := string_to_array(v_src, E'\n');
  for v_i in 1 .. array_length(v_lines, 1) loop
    if v_lines[v_i] like '  bal as (%' then v_bal := v_i; end if;
    if v_lines[v_i] like '    union all%-- perf-rpc-1%' then v_k3 := v_i; end if;
    if v_lines[v_i] like '      and (select k.arr from skus k) is null %-- perf-rpc-1%' then v_k4 := v_i; end if;
  end loop;
  if v_bal is null or v_k3 is null or v_k4 is null or not (v_bal < v_k3 and v_k3 < v_k4) then v_bad := v_bad || ' branch_markers'; end if;
  if v_bad = '' then
    for v_i in 1 .. array_length(v_lines, 1) loop
      if (v_i > v_bal and v_i <= v_k3) or v_i = v_k4 then continue; end if;
      v_rest := v_rest || v_lines[v_i];
    end loop;
    if md5(array_to_string(v_rest, E'\n')) <> '3cacac3195fb93afb99a794a91cfbdf9' then v_bad := v_bad || ' old_body_not_preserved'; end if;
  end if;
  if v_bad <> '' then raise exception 'perf-rpc-1 self-check failed:%', v_bad; end if;
end $$;
