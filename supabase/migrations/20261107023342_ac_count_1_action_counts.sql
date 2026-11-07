-- 20261107023342_ac_count_1_action_counts.sql — ac-count-1: Action Centre 할 일 숫자를 한 번에 세는 창구 ims_action_counts (2026-11-06 · Caleb 판정 「그렇게 가자」 · 지시서 ~/asung/prompts/ac-count-1.md · 이견 1 ~ 8 답 「모두 그대로」)
-- [운영 메인 · Asung-IMS] 적용은 qbo-trk-1(20261107021000) 다음에 Caleb 이 한다 · fc-pickup-4(20261107020808 · fc_pickup_attention_list) 뒤
--
-- 왜: Action Centre 탭 배지(manager-list.html ml v1.4)와 바깥 메뉴 「Action Centre」 빨간 배지(ims-auth.js · 2 분 sessionStorage)가 **같은 함수**로 같은 숫자를 본다 — 규칙이 둘로 갈리지 않게.
--     화면은 지금 넷을 따로 부른다(왕복 넷 · 각 ~350 ms) → 한 왕복(~400 ms · 서버 계산 합 ~31 ms 실측 2026-11-06).
-- 무엇: ims_action_counts(p_warehouse_id uuid default null) returns jsonb
--     {warehouse_id, warehouse, short, unpaid, pos, new_customers, pickups, total, at}
--     ① short         = so_stock_short_list({unchecked_only:true [, warehouse_id]}).unchecked_count   — 화면 원문 그대로(창구를 부른다 · 규칙을 다시 쓰지 않는다)
--     ② unpaid        = so_invoice_list · is_open ∧ [warehouse_id = p] ∧ payment_term_name ∈ {ref_payment_term.name | net_days = 0}
--                       (이견 2 · 3: `= any(array(select …))` 꼴 — 같은 집합 · planner 가 결제조건 거르기를 so_invoice_remaining 앞에 둔다(21 → 12.6 ms) · 빈 집합이면 0 = 화면의 '__none__' · 화면처럼 is_active 를 안 본다)
--     ③ pos           = so_pos_open_list(p).stale_count                                               — invoker 창구를 definer 안에서 부른다 · 아래 표 select 정책이 전부 true 라 직원이 부른 값과 같다(이견 6)
--     ④ new_customers = customer_review_list · [default_location_name = ref_warehouse.name of p]      — 화면처럼 이름으로 거른다(ml v1.3)
--     ⑤ pickups       = fc_pickup_attention_list(p).count                                             — fc-pickup-4 · 이것만 창고 두 겹(p ∧ ims_can_warehouse · 이견 4)
--     total = 다섯 합(null 은 0) · at = now()
-- 문: 첫 줄 ims_can_view('sales') = Action Centre 메뉴 열쇠(ims-auth.js:97)와 같다 · definer · authenticated 만(service_role 회수 · fc-pickup-4 와 같다)
--     항목별 문 → null(이견 1): short 는 sales · pickups 는 sales ∨ fulfillment ∨ freight_booking 쓰기 — 첫 줄 문이 sales 라 **지금은 비어 있는 길**(sales 를 통과한 사람은 다섯을 다 본다) · 나중에 문이 갈려도 화면 규칙(null = 안 보임)이 안 바뀌게 둔다
-- 새 표 · 칸 · FK 없음 · 쓰기 없음(stable)

create function public.ims_action_counts(p_warehouse_id uuid default null) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_wh    text;
  v_short int;
  v_unpaid int;
  v_pos   int;
  v_new   int;
  v_pick  int;
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot see the Action Centre — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- 첫 줄 문 = 메뉴 열쇠(sales) · so_stock_short_list 와 같은 열쇠
  if p_warehouse_id is not null then
    select w.name into v_wh from public.ref_warehouse w where w.id = p_warehouse_id;
    if v_wh is null then raise exception 'Warehouse not found'; end if;
  end if;

  -- ① Sold without stock — 화면: so_stock_short_list({unchecked_only:true [, warehouse_id]}) → unchecked_count · 항목 문 sales(지금은 첫 줄 문과 같아 늘 통과)
  if public.ims_can_view('sales') then
    v_short := (public.so_stock_short_list(jsonb_build_object('unchecked_only', true) || case when p_warehouse_id is null then '{}'::jsonb else jsonb_build_object('warehouse_id', p_warehouse_id) end)->>'unchecked_count')::int;
  end if;

  -- ② Unpaid at hand-over — 화면: so_invoice_list · is_open = true · [warehouse_id] · payment_term_name in IMMEDIATE(net_days = 0 의 name · 없으면 '__none__' → 0) · 로그인만(문 없음)
  select count(*)::int into v_unpaid
    from public.so_invoice_list l
   where l.is_open = true
     and (p_warehouse_id is null or l.warehouse_id = p_warehouse_id)
     and l.payment_term_name = any (array(select t.name from public.ref_payment_term t where t.net_days = 0));

  -- ③ POS not finished — 화면: so_pos_open_list(p_location_id) → stale_count · 로그인만(문 없음)
  v_pos := (public.so_pos_open_list(p_warehouse_id)->>'stale_count')::int;

  -- ④ New customers to review — 화면: customer_review_list · [default_location_name = 창고 이름] · 로그인만(문 없음)
  select count(*)::int into v_new
    from public.customer_review_list r
   where (v_wh is null or r.default_location_name = v_wh);

  -- ⑤ Pickups not scheduled — fc_pickup_attention_list(p) → count · 항목 문 = 그 창구의 첫 줄 문(sales ∨ fulfillment ∨ freight_booking 쓰기 · 지금은 sales 가 포함해 늘 통과)
  if public.ims_can_view('sales') or public.ims_can_view('fulfillment') or public.ims_can_write('freight_booking') then
    v_pick := (public.fc_pickup_attention_list(p_warehouse_id)->>'count')::int;
  end if;

  return jsonb_build_object(
    'warehouse_id', p_warehouse_id, 'warehouse', v_wh,
    'short', v_short, 'unpaid', v_unpaid, 'pos', v_pos, 'new_customers', v_new, 'pickups', v_pick,
    'total', coalesce(v_short, 0) + coalesce(v_unpaid, 0) + coalesce(v_pos, 0) + coalesce(v_new, 0) + coalesce(v_pick, 0),
    'at', now());
end;
$$;
revoke all on function public.ims_action_counts(uuid) from public, anon, service_role;
grant execute on function public.ims_action_counts(uuid) to authenticated;
comment on function public.ims_action_counts(uuid) is 'ac-count-1: Action Centre 할 일 숫자 한 번에(탭 배지 + 바깥 메뉴 배지가 같은 함수 · 2026-11-06) — {warehouse_id, warehouse, short, unpaid, pos, new_customers, pickups, total, at} · null 이면 전 창고(All branches) · short = so_stock_short_list(unchecked_only).unchecked_count · unpaid = so_invoice_list is_open ∧ [warehouse_id] ∧ payment_term_name ∈ ref_payment_term net_days 0(is_active 안 봄 · 화면과 같다 · 없으면 0) · pos = so_pos_open_list.stale_count · new_customers = customer_review_list [default_location_name = 창고 이름] · pickups = fc_pickup_attention_list.count(이것만 창고 두 겹 ims_can_warehouse) · total = 합(null 은 0) · 문 = ims_can_view(sales)(메뉴 열쇠와 같다) · definer · authenticated 만 · 항목별 문 → null(short: sales · pickups: sales ∨ fulfillment ∨ freight_booking) 은 지금은 비어 있는 길(첫 줄 문이 sales 라 통과한 사람은 다섯을 다 본다) · 화면은 2 분에 한 번(ims-auth.js sessionStorage) · 실측 2026-11-06 서버 ~31 ms';

-- ═══ 자기 검사 — 설계대로 안 섰으면 전체 되돌림 ═══
do $$
declare v_n int; v_acl text; v_def boolean; v_vol "char";
begin
  select count(*) into v_n from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_action_counts';
  if v_n <> 1 then raise exception 'ac-count-1 landing check failed: ims_action_counts count %', v_n; end if;
  select coalesce(p.proacl::text, '(null)'), p.prosecdef, p.provolatile into v_acl, v_def, v_vol from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'ims_action_counts';
  if v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' then raise exception 'ac-count-1 landing check failed: acl %', v_acl; end if;
  if not v_def or v_vol <> 's' then raise exception 'ac-count-1 landing check failed: definer % volatile %', v_def, v_vol; end if;
end $$;
