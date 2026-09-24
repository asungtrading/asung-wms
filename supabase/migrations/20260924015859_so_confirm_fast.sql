-- SO 쓰기 ②a′ — 가용 읽기를 한 문장으로: so_available_many(속 · 식 한 곳) · so_available · so_allocate_run 재발행 (2026-09-24 UTC · 토론토 2026-09-23 밤)
-- 계기(Caleb 실측 2026-09-23 · 집): ②a 검증 1) 이 제품마다 ims_inv_balance 를 다시 계산해 statement timeout(2분) · so_available 한 번은 빠르다(ABC59130 16 · 194.8ms / AAL10850 23 · 167.6ms · 네트워크 포함)
--   ⇒ 뷰(inv_balance 위 ims_inv_balance)는 한 번 계산이 ~150ms 라 「몇 번 부르나」가 시간이다 · 줄마다 부르던 so_allocate_run 을 한 문장으로 · 검증도 후보를 좁힌 뒤 한 문장으로
-- 판정(Caleb): 잠금 순서(⬜4)는 그대로 · 잠금 뒤 한 번 읽는다 · so_available 은 화면용 창구로 남긴다 · 식이 두 곳이 되면 안 된다 ⇒ 속 함수 so_available_many 하나를 둘이 부른다
-- 바탕: 20260924014219_so_confirm.sql(so_available :113 · so_allocate_run :232 — 마지막 정의 · 여기서 create or replace) · 그 밖 무접촉
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
--
-- ⭐ so_available_many(p_stock_pids uuid[], p_location_id) → (stock_pid · qty_ea · allocated_ea · available_ea) — ⭐ 가용 식은 여기 한 곳
--    창고 잔고 = ims_inv_balance 그 창고 · product_id = any(pids) · 모든 bin 합 · − Σ 열린 allocated 예약(qty_allocated × pack_factor · 그 창고 오더 · 같은 낱개) · 부른 pid 마다 한 행(없으면 0 − 할당)
--    ⚠️ 낱개(stock_pid)를 받는다 — 세트→낱개 환산(coalesce(parent_product_id, id))은 부르는 쪽(so_available · so_allocate_run 의 잠금 루프)이 한다
-- ⭐ so_available(product, location) — 같은 시그니처 · 본문만 so_available_many 호출로(세트를 물으면 낱개로) · grant·comment 유지
-- ⭐ so_allocate_run — 잠금 루프에서 낱개 제품 배열을 모으고 · 잠금 뒤 so_available_many 한 문장으로 v_avail 을 채운다 · 줄 루프의 so_available 호출 삭제 · p_hold 면 읽지 않는다 · 그 밖 한 글자 그대로
-- 검증 ~/asung/prompts/so-write-2a-verify.sql(덮어씀) — 후보를 싸게 좁힌 뒤(활성 낱개 · 티어 가격 · sku 순 300) so_available_many 한 문장 · explain analyze 둘(so_available 한 번 · 30줄 미리 보기) · Execution Time 회신

-- ═══ ① so_available_many — 가용 식 한 곳(속 함수) ═══
create function public.so_available_many(p_stock_pids uuid[], p_location_id uuid)
  returns table (stock_pid uuid, qty_ea numeric, allocated_ea numeric, available_ea numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with pids as (
    select distinct u.pid as stock_pid from unnest(coalesce(p_stock_pids, '{}'::uuid[])) as u(pid)
  ),
  bal as (
    select b.product_id, sum(b.qty) as qty
    from public.ims_inv_balance b
    where b.warehouse_id = p_location_id and b.product_id = any(p_stock_pids)
    group by b.product_id
  ),
  alloc as (
    select coalesce(p.parent_product_id, p.id) as stock_pid, sum(r.qty_allocated * l.pack_factor) as ea
    from public.so_reserve r
    join public.so_line l on l.id = r.so_line_id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    where r.released_at is null and r.kind = 'allocated'
      and s.location_id = p_location_id
      and coalesce(p.parent_product_id, p.id) = any(p_stock_pids)
    group by 1
  )
  select pids.stock_pid,
         coalesce(bal.qty, 0),
         coalesce(alloc.ea, 0),
         coalesce(bal.qty, 0) - coalesce(alloc.ea, 0)
  from pids
  left join bal   on bal.product_id  = pids.stock_pid
  left join alloc on alloc.stock_pid = pids.stock_pid;
$$;
comment on function public.so_available_many(uuid[], uuid) is
  '⭐⭐ 가용 재고 식 한 곳(②a′ · 5-f · 2-d) — 낱개 제품 배열 × 창고 → 행마다 (stock_pid · qty_ea 창고 잔고(ims_inv_balance 모든 bin 합) · allocated_ea Σ 열린 allocated 예약 × pack_factor · available_ea 차) · 부른 pid 마다 한 행(잔고 없으면 0) · 음수 그대로(엔진이 0 으로 본다) · preorder·hold·backorder 는 빼지 않는다 · 뷰를 한 번만 계산한다(제품마다 부르면 ~150ms × n · 2026-09-23 실측) · so_available(화면 창구)·so_allocate_run(엔진)이 이것을 부른다 — 식이 두 곳이 되지 않게 · ⚠️ 낱개를 받는다(세트→낱개 환산은 부르는 쪽) · 속 함수';
revoke all on function public.so_available_many(uuid[], uuid) from public, anon, authenticated;

-- ═══ ② so_available 재발행 — 마지막 정의 20260924014219:113 · 시그니처 그대로 · 본문을 so_available_many 호출로 · grant·comment 유지(comment 는 아래에서 갈아 쓴다) ═══
create or replace function public.so_available(p_product_id uuid, p_location_id uuid) returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select m.available_ea
  from public.product p,
       lateral public.so_available_many(array[coalesce(p.parent_product_id, p.id)], p_location_id) m
  where p.id = p_product_id;
$$;

comment on function public.so_available(uuid, uuid) is
  '⭐ 가용 재고 창구(화면용 · 5-f · 2-d · ②a′) — 낱개(EA) · 식은 so_available_many 한 곳(창고 잔고 모든 bin 합 − Σ 열린 allocated × pack_factor) · 세트를 물으면 낱개 잔고 · 음수·0 그대로 · 화면은 다시 짜지 않는다 · 엔진(so_allocate_run)은 오더 제품 전부를 so_available_many 한 문장으로 읽는다 · ⚠️ 창고 조인은 ims_inv_balance 가 ref_warehouse.name 텍스트로 잇는다(원장 정본 ⬜)';

-- ═══ ③ so_allocate_run 재발행 — 마지막 정의 20260924014219:232 · 바뀐 줄: 선언 1 · 잠금 루프에 pid 모으기 1 · 잠금 뒤 한 문장 읽기 5 · 줄 루프의 so_available 호출 3줄 → 1줄 · 그 밖 그대로 ═══
create or replace function public.so_allocate_run(p_so_id uuid, p_location_id uuid, p_preorder_line_ids uuid[], p_hold boolean, p_confirm boolean, p_commit boolean, p_staff uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so      public.so%rowtype;
  l         record;
  v_key     text;
  v_rem     numeric;
  v_alloc   numeric;
  v_avail   jsonb := '{}'::jsonb;                    -- 낱개 제품 → 남은 가용(EA) · 이번 실행 안에서만 · 잠금 뒤 so_available_many 한 문장으로 채운다
  v_pids    uuid[] := '{}';                          -- 이 오더의 낱개 제품(잠금 순서대로)
  v_plan    jsonb := '[]'::jsonb;
  a_ids     uuid[] := '{}';  a_qty numeric[] := '{}';       -- A 할당(줄 · 잡는 수량)
  b_moves   jsonb := '[]'::jsonb;  b_n int := 0;             -- B 백오더 [{line_id, qty}]
  p_moves   jsonb := '[]'::jsonb;  p_n int := 0;             -- P 프리오더
  v_keep    text;
  v_sib_b   public.so%rowtype;  v_sib_p public.so%rowtype;
  v_sibs    jsonb := '[]'::jsonb;
  v_n       int;
  i         int;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if p_location_id is null then raise exception 'Order % has no warehouse — set one before confirming — nothing was saved', v_so.so_number; end if;

  -- 잠금 — (창고, 낱개 제품) 오름차순 · 줄마다(5-f) · 두 매니저가 같은 제품을 반대 순서로 잡을 수 없다(⬜4)
  for l in
    select x.id, coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_line x join public.product p on p.id = x.product_id
    where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
    order by 2, 1
  loop
    perform pg_advisory_xact_lock(hashtext('so_avail:' || p_location_id::text || ':' || l.stock_pid::text));
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || l.id::text));
    v_pids := array_append(v_pids, l.stock_pid);
  end loop;

  -- 가용 — 잠금 뒤 한 번 · 오더의 낱개 제품 전부를 한 문장으로(so_available_many · 뷰를 한 번만 계산한다) · 음수는 0
  if not p_hold and coalesce(array_length(v_pids, 1), 0) > 0 then
    select coalesce(jsonb_object_agg(m.stock_pid::text, greatest(m.available_ea, 0)), '{}'::jsonb) into v_avail
    from public.so_available_many(v_pids, p_location_id) m;
  end if;

  -- 줄마다 판정(모체 line_no 순 — 같은 제품이 두 줄이면 앞 줄이 먼저 잡는다)
  for l in
    select x.*, coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_line x join public.product p on p.id = x.product_id
    where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
    order by x.line_no
  loop
    if p_hold then
      v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                             'kind', 'hold', 'allocated', 0, 'backordered', 0, 'preorder', 0);
      a_ids := array_append(a_ids, l.id);  a_qty := array_append(a_qty, l.qty_ordered);
      continue;
    end if;
    if l.id = any(coalesce(p_preorder_line_ids, '{}'::uuid[])) then
      v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                             'kind', 'preorder', 'allocated', 0, 'backordered', 0, 'preorder', l.qty_ordered);
      p_moves := p_moves || jsonb_build_object('line_id', l.id, 'qty', l.qty_ordered);  p_n := p_n + 1;
      continue;
    end if;
    v_key := l.stock_pid::text;
    v_rem   := coalesce((v_avail->>v_key)::numeric, 0);
    v_alloc := least(l.qty_ordered, floor(v_rem / l.pack_factor));
    v_avail := v_avail || jsonb_build_object(v_key, v_rem - v_alloc * l.pack_factor);
    v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                           'available_ea_before', v_rem,
                                           'kind', case when v_alloc = l.qty_ordered then 'allocated' when v_alloc = 0 then 'backorder' else 'partial' end,
                                           'allocated', v_alloc, 'backordered', l.qty_ordered - v_alloc, 'preorder', 0);
    if v_alloc > 0 then a_ids := array_append(a_ids, l.id);  a_qty := array_append(a_qty, v_alloc); end if;
    if v_alloc < l.qty_ordered then
      b_moves := b_moves || jsonb_build_object('line_id', l.id, 'qty', l.qty_ordered - v_alloc);  b_n := b_n + 1;
    end if;
  end loop;

  if coalesce(array_length(a_ids, 1), 0) = 0 and b_n = 0 and p_n = 0 then
    raise exception 'Order % has no lines to allocate — nothing was saved', v_so.so_number;
  end if;

  -- 어느 무리가 원래 번호를 지키나(이견 1) — hold 는 전부 원래(나누지 않는다)
  v_keep := case when p_hold then 'hold'
                 when coalesce(array_length(a_ids, 1), 0) > 0 then 'allocated'
                 when b_n > 0 then 'backorder'
                 else 'preorder' end;

  if not p_commit then
    return jsonb_build_object('so_number', v_so.so_number, 'committed', false, 'keeps', v_keep, 'lines', v_plan,
      'siblings', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
         select jsonb_build_object('split_reason', 'stock_short', 'lines', b_n) as x where b_n > 0 and v_keep <> 'backorder' and not p_hold
         union all
         select jsonb_build_object('split_reason', 'preorder', 'lines', p_n) where p_n > 0 and v_keep <> 'preorder' and not p_hold) z));
  end if;

  -- 확정(so_confirm) — 원래를 draft → confirmed 로 먼저 올린다(형제가 확정 흔적을 물려받는다)
  if p_confirm then
    update public.so set status = 'confirmed', confirmed_at = now(), confirmed_by = p_staff, updated_by = p_staff
    where id = p_so_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not confirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;
  end if;

  -- 형제 — 원래가 지키지 않는 무리만(빈 문서 없음) · B 가 앞 글자
  if b_n > 0 and v_keep <> 'backorder' then
    v_sib_b := public.so_split(p_so_id, 'stock_short', b_moves, 'confirmed', p_staff);
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'backorder', null from public.so_line x where x.so_id = v_sib_b.id;
    v_sibs := v_sibs || jsonb_build_object('so_id', v_sib_b.id, 'so_number', v_sib_b.so_number, 'split_reason', 'stock_short', 'lines', b_n);
  end if;
  if p_n > 0 and v_keep <> 'preorder' then
    v_sib_p := public.so_split(p_so_id, 'preorder', p_moves, 'confirmed', p_staff);
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'preorder', p_staff from public.so_line x where x.so_id = v_sib_p.id;
    v_sibs := v_sibs || jsonb_build_object('so_id', v_sib_p.id, 'so_number', v_sib_p.so_number, 'split_reason', 'preorder', 'lines', p_n);
  end if;

  -- 원래에 남은 줄의 예약
  if v_keep = 'hold' then
    for i in 1 .. coalesce(array_length(a_ids, 1), 0) loop
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (a_ids[i], a_qty[i], 'hold', p_staff);
    end loop;
  elsif v_keep = 'allocated' then
    for i in 1 .. array_length(a_ids, 1) loop                                          -- a_qty = 잡는 수량 = so_split 뒤 그 줄의 qty_ordered
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (a_ids[i], a_qty[i], 'allocated', null);
    end loop;
  elsif v_keep = 'backorder' then
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'backorder', null from public.so_line x where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null);
  else
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'preorder', p_staff from public.so_line x where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null);
  end if;

  select * into v_so from public.so where id = p_so_id;
  return jsonb_build_object('so_number', v_so.so_number, 'status', v_so.status, 'committed', true, 'keeps', v_keep, 'lines', v_plan, 'siblings', v_sibs);
end;
$$;

