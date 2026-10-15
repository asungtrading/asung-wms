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
-- 20261014234811_bo_1a_demand_flag.sql — bo-1a (2026-10-14 밤 · 집 PC · Fable)
--   판정 464 · 475 ~ 478 · 483(so-module §63-a · 다음 문서 차수) — 백오더 수요 셈 + 「진짜 수요 아님」 표식
--   ① 표 so_demand_flag(줄 하나에 표식 한 번 · 떼면 지우지 않고 unflagged_at/by · 활성 한 줄 = active_line_id 생성 칸 + 유니크 · 규칙 29 · so_backorder_close.active_line_id 와 같은 장치)
--   ② 속 함수 so_demand_line(줄 하나의 셈 · 읽기 함수와 표식 창구가 같은 식을 쓴다)
--   ③ 읽기 so_backorder_demand(p_filters) — 단위 = 손님 × 재고 제품의 「연결 덩어리」(bo-0 이견 6 · 연결 셋 split_from_line_id · taken_by_line_id(활성 장부만) · so_line_merge_source 를 한 edges 로 · 재귀 · 병합을 두 번 세지 않는다)
--      칸 다섯(판정 477) demand_then = sold + lost + in_progress + open_backorder(표식 뒤 숫자 · 항등식) · lost_by(unwanted · expired · cancelled · removed) · flagged
--   ④ 창구 so_demand_flag_set · so_demand_flag_clear — 문 두 줄 선례 so_backorder_proceed(ims_require_write sales · so_require_role manager) · 여러 줄 한 번에 · 하나라도 거부면 아무것도 안 쓴다
--      ⚠️ so · so_line · so_reserve · so_backorder_close 무접촉(판정 478 — shop_order_cancelled 가 max(so_line.updated_at) 을 견준다)
--   ⭐ 덧붙임(Caleb 2026-10-14 밤 · 지시서 md5 bdec348b…): 확정 되돌리기(so_unconfirm)로 없어진 백오더는 없었던 것 — so_demand_so_excluded(되돌린 뒤 초안이거나 취소된 오더 = draft | cancelled ∧ confirmed_at null ∧ unconfirmed_at 있음 · 되돌리기가 도로 붙인 형제 = cancelled ∧ merged ∧ merged_into_id = split_from_id · so_unconfirm 20261006204146:85 · 94)의 줄은 덩어리에 들지 않는다 · 표식도 거부
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/bo-1a-verify.sql · 화면은 bo v4(대화 Claude · 다음)

-- ═══ ① 표 so_demand_flag ═══
create table public.so_demand_flag (
  id              uuid primary key default gen_random_uuid(),
  so_line_id      uuid not null references public.so_line (id) on delete no action,     -- 표식을 단 수요 줄(콤보 줄이면 콤보 줄 · 구성품 줄 아님)
  reason          text not null,                                                        -- staff_error · duplicate · test · other
  note            text,
  flagged_at      timestamptz not null default now(),
  flagged_by      uuid not null references public.ims_staff (id) on delete no action,
  unflagged_at    timestamptz,                                                          -- 뗀 시각 · 지우지 않는다(다시 달면 새 행)
  unflagged_by    uuid references public.ims_staff (id) on delete no action,
  active_line_id  uuid generated always as (case when unflagged_at is null then so_line_id end) stored,   -- 줄당 활성 한 줄(규칙 29 · 부분 유니크 금지)
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.ims_staff (id) on delete no action,
  constraint so_demand_flag_reason_ck      check (reason in ('staff_error', 'duplicate', 'test', 'other')),
  constraint so_demand_flag_note_ck        check (reason <> 'other' or nullif(trim(note), '') is not null),
  constraint so_demand_flag_unflag_pair_ck check ((unflagged_at is null) = (unflagged_by is null)),
  constraint so_demand_flag_active_uq      unique (active_line_id)
);
create index so_demand_flag_line_idx on public.so_demand_flag (so_line_id);
create index so_demand_flag_flagged_by_idx on public.so_demand_flag (flagged_by);
create index so_demand_flag_unflagged_by_idx on public.so_demand_flag (unflagged_by);
create index so_demand_flag_updated_by_idx on public.so_demand_flag (updated_by);
comment on table public.so_demand_flag is
  '⭐ 「진짜 수요 아님」 표식(bo-1a · 판정 464 ③ · 478) — 수요 줄(so_line) 하나에 표식 한 번 · 매니저가 달고 뗀다(so_demand_flag_set · _clear) · 떼면 지우지 않고 unflagged_at/by · 다시 달면 새 행 · 활성 한 줄 = active_line_id 유니크 · 수요 셈(so_backorder_demand)에서 그 줄의 잃은 판매 몫을 수요 · 잃은 판매 둘에서 함께 뺀다(flagged 칸) · 오더 · 재고 · Shopify 무영향(so · so_line 무접촉 — shop_order_cancelled 가 so_line.updated_at 을 견준다)';
comment on column public.so_demand_flag.reason is 'staff_error(직원 실수) · duplicate(중복 입력 · 483 의 「고치려고 다시 넣은 오더」) · test(시험) · other(note 필수 · CHECK)';
comment on column public.so_demand_flag.active_line_id is '생성 칸 — unflagged_at 이 null 이면 so_line_id · 유니크 so_demand_flag_active_uq(줄당 활성 한 줄 · 뗀 줄은 비운다) · 부분 유니크 인덱스 금지(규칙 29)';
alter table public.so_demand_flag enable row level security;
create policy so_demand_flag_select on public.so_demand_flag for select to authenticated using (true);
create trigger so_demand_flag_touch before update on public.so_demand_flag for each row execute function public.ims_touch();
revoke all on public.so_demand_flag from public, anon, authenticated;
grant select on public.so_demand_flag to authenticated;

-- ═══ ②′ 속 함수 so_demand_so_excluded — 확정 되돌리기(so_unconfirm)로 정리된 오더는 수요 셈 밖(Caleb 덧붙임 2026-10-14) ═══
--   so_unconfirm 의 흔적(20261006204146:85 · 94 · 정의로 확인): 원래 오더 → status draft · confirmed_at null · unconfirmed_at now() ⇒ 그 뒤 so_cancel 하면 cancelled ∧ confirmed_at null ∧ unconfirmed_at 있음(다시 확정했으면 confirmed_at 이 다시 찍혀 셈에 든다)
--                                                           형제(stock_short · preorder) → cancelled · closed_reason merged · merged_into_id = split_from_id(제 부모로 도로) · split_from_line_id 가 있던 줄 행은 이력으로 남는다 ⇒ 그 줄도 뺀다(so_merge 의 merged 는 새 오더라 merged_into_id ≠ split_from_id)
create function public.so_demand_so_excluded(p_so_id uuid) returns boolean
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.so s where s.id = p_so_id
      and ((s.confirmed_at is null and s.unconfirmed_at is not null and s.status in ('draft', 'cancelled'))                                    -- 되돌린 뒤 아직 초안이거나 취소됨(다시 확정하면 confirmed_at 이 찍힌다)
           or (s.status = 'cancelled' and s.closed_reason = 'merged' and s.merged_into_id is not null and s.merged_into_id = s.split_from_id))
  )
$$;
comment on function public.so_demand_so_excluded(uuid) is 'bo-1a 속 함수 — 확정 되돌리기(so_unconfirm)로 없어진 백오더는 없었던 것(Caleb 2026-10-14): 되돌린 뒤 아직 초안이거나 취소된 오더(draft | cancelled ∧ confirmed_at null ∧ unconfirmed_at) · 되돌리기가 도로 붙인 형제(cancelled ∧ merged ∧ merged_into_id = split_from_id) — 그 줄은 so_backorder_demand 의 덩어리에 들지 않고 so_demand_flag_set 도 거부한다';
revoke all on function public.so_demand_so_excluded(uuid) from public, anon;
grant execute on function public.so_demand_so_excluded(uuid) to authenticated;

-- ═══ ② 속 함수 so_demand_line — 줄 하나의 셈(판매 단위 · 콤보 줄은 구성품 예약을 콤보 수로 · asm-2b2 와 같은 식) ═══
--   demand(이 줄이 덩어리 수요에 더하는 몫) = ordered − transferred   ⋯ transferred = 이어받긴 몫(superseded.qty_taken) + 병합으로 옮긴 몫(closed_reason merged 오더의 남은 몫 — so_merge 는 모든 줄을 옮긴다 · 장부 merged 행은 백오더 줄에만 서므로 그 행은 세지 않는다) — 그 수량은 새 줄의 ordered 에 다시 있다
--   lost = unwanted(superseded.qty_unwanted) + expired(qty_open) + cancelled(장부 cancelled.qty_open + 취소 오더(voided)의 남은 몫 · 판정 476) + removed(qty_removed · 판정 475)
--   in_progress = 취소 아닌 오더의 남은 몫(ordered − sold − removed − taken − lost_ledger − open_backorder · 판정 477 — 잡혔거나 창고에 있거나 아직 초안) · 항등식 demand = sold + lost + in_progress + open_backorder
--   장부는 reopened_at 이 null 인 행만(되돌려진 끝은 없던 일) · proceeded 는 끝이 아니다(줄이 이어진다 — 더하지도 빼지도 않는다)
create function public.so_demand_line(p_line_id uuid)
returns table (ordered numeric, sold numeric, removed numeric, transferred numeric, open_backorder numeric,
               lost_unwanted numeric, lost_expired numeric, lost_cancelled numeric, lost_removed numeric, lost numeric,
               in_progress numeric, demand numeric, so_status text, end_kinds text)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with l as (
    select l.qty_ordered, l.qty_shipped, l.qty_removed, s.status as so_status, s.closed_reason
    from public.so_line l join public.so s on s.id = l.so_id where l.id = p_line_id
  ),
  c as (
    select coalesce(sum(case when c.end_kind = 'superseded' then c.qty_taken else 0 end), 0) as taken,
           coalesce(sum(case when c.end_kind = 'superseded' then c.qty_unwanted else 0 end), 0) as unwanted,
           coalesce(sum(case when c.end_kind = 'expired'    then c.qty_open else 0 end), 0) as expired,
           coalesce(sum(case when c.end_kind = 'cancelled'  then c.qty_open else 0 end), 0) as cancelled_ledger,
           string_agg(c.end_kind, ',' order by c.ended_at, c.id) as end_kinds
    from public.so_backorder_close c where c.so_line_id = p_line_id and c.reopened_at is null
  ),
  r as (
    select coalesce(min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))), 0) as open_bo
    from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
    where (cp.id = p_line_id or cp.combo_line_id = p_line_id) and res.kind = 'backorder' and res.released_at is null
  ),
  x as (
    select l.*, c.*, r.open_bo,
           l.qty_ordered - l.qty_shipped - l.qty_removed - c.taken - c.unwanted - c.expired - c.cancelled_ledger - r.open_bo as resid
    from l, c, r
  ),
  y as (
    select x.*,
           case when x.so_status = 'cancelled' and x.closed_reason = 'merged' then x.resid else 0 end as merged_out,     -- 병합으로 옮겨 간 남은 몫(새 오더의 줄이 다시 센다)
           case when x.so_status = 'cancelled' and x.closed_reason is distinct from 'merged' then x.resid else 0 end as cancelled_rest,   -- 판정 476: 취소된 몫 전체(할당 몫 포함)
           case when x.so_status = 'cancelled' then 0 else x.resid end as in_prog
    from x
  )
  select y.qty_ordered, y.qty_shipped, y.qty_removed, y.taken + y.merged_out, y.open_bo,
         y.unwanted, y.expired, y.cancelled_ledger + y.cancelled_rest, y.qty_removed,
         y.unwanted + y.expired + y.cancelled_ledger + y.cancelled_rest + y.qty_removed,
         y.in_prog,
         y.qty_ordered - y.taken - y.merged_out,
         y.so_status, y.end_kinds
  from y
$$;
comment on function public.so_demand_line(uuid) is
  'bo-1a 속 함수 — 수요 줄 하나의 셈(판매 단위): ordered · sold(qty_shipped) · removed(qty_removed) · transferred(이어받긴 qty_taken + 병합(closed_reason merged) 오더의 남은 몫 · 새 줄이 다시 센다) · open_backorder(열린 backorder 예약 · 콤보 줄은 구성품 예약 ÷ combo_qty 의 최소) · lost_* · in_progress(취소 아닌 오더의 남은 몫) · demand = ordered − transferred · 항등식 demand = sold + lost + in_progress + open_backorder · 장부는 reopened_at null 행만 · so_backorder_demand 와 so_demand_flag_set 이 같은 식을 쓴다';
revoke all on function public.so_demand_line(uuid) from public, anon;
grant execute on function public.so_demand_line(uuid) to authenticated;

-- ═══ ③ 읽기 so_backorder_demand — 손님 × 재고 제품의 연결 덩어리마다 칸 다섯 + 표식 ═══
--   덩어리에 드는 줄 = 씨앗(백오더가 한 번이라도 있었던 수요 줄 — so_reserve kind backorder 가 그 줄이나 구성품 줄에 한 행이라도(닫힌 것 포함) 있거나 장부 행이 있는 줄) + 연결된 줄(세 변을 양방향으로 재귀)
--   덩어리 id = 그 덩어리에서 가장 작은 line id · 뺀다 = 무상 줄 · pos·counter 오더 · 콤보 구성품 줄(콤보 줄이 수요 줄) · 되돌려진 장부 행(reopened_at) · 되돌려진 이어받기의 변
--   표식(so_demand_flag 활성 행): 그 줄의 lost 를 demand_then · lost 둘에서 함께 뺀다 → flagged 칸 · 판 것 · 진행 중 · 남은 백오더는 그대로
create function public.so_backorder_demand(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['customer_id','supplier_id','brand_id','sku','product_id','location_id','order_from','order_to','ended_from','ended_to','open','flagged','limit','offset'];
  v_bad    text;
  v_limit  int := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_out    jsonb;
begin
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;

  with recursive
  seed as (                                                                                        -- 백오더가 한 번이라도 있었던 수요 줄
    select l.id
    from public.so_line l join public.so s on s.id = l.so_id
    where l.combo_line_id is null and l.free_reason is null and s.channel = 'warehouse' and not public.so_demand_so_excluded(s.id)
      and (exists (select 1 from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id
                   where (cp.id = l.id or cp.combo_line_id = l.id) and r.kind = 'backorder')
           or exists (select 1 from public.so_backorder_close c where c.so_line_id = l.id))
  ),
  edge as (                                                                                        -- 연결 셋(양방향)
    select e.a, e.b from (
      select l.split_from_line_id as a, l.id as b from public.so_line l where l.split_from_line_id is not null
      union all select c.so_line_id, c.taken_by_line_id from public.so_backorder_close c where c.taken_by_line_id is not null and c.reopened_at is null
      union all select m.from_line_id, m.line_id from public.so_line_merge_source m
    ) e
    union
    select e.b, e.a from (
      select l.split_from_line_id as a, l.id as b from public.so_line l where l.split_from_line_id is not null
      union all select c.so_line_id, c.taken_by_line_id from public.so_backorder_close c where c.taken_by_line_id is not null and c.reopened_at is null
      union all select m.from_line_id, m.line_id from public.so_line_merge_source m
    ) e
  ),
  reach (seed_id, id) as (
    select s.id, s.id from seed s
    union
    select r.seed_id, e.b from reach r join edge e on e.a = r.id
  ),
  comp_of_seed as (select r.seed_id, min(r.id::text)::uuid as comp_id from reach r group by r.seed_id),   -- min(uuid) 집계가 없다 → text 로
  node as (select distinct r.id, cs.comp_id from reach r join comp_of_seed cs on cs.seed_id = r.seed_id),
  line as (                                                                                        -- 덩어리의 수요 줄 + 줄 셈 + 활성 표식
    select n.comp_id, l.id as line_id, l.so_id, s.so_number, s.channel, s.customer_id, s.location_id, s.location_name, s.order_date,
           l.line_no, l.product_id, l.sku, l.product_name, l.pack_factor,
           coalesce(p.parent_product_id, p.id) as stock_pid,
           d.*,
           fl.id as flag_id, fl.reason as flag_reason, fl.note as flag_note, fl.flagged_at, fl.flagged_by,
           case when fl.id is not null then d.lost else 0 end as flagged_qty,
           (select max(c.ended_at) from public.so_backorder_close c where c.so_line_id = l.id and c.reopened_at is null) as last_ended_at
    from node n
    join public.so_line l on l.id = n.id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    cross join lateral public.so_demand_line(l.id) d
    left join public.so_demand_flag fl on fl.active_line_id = l.id
    where l.combo_line_id is null and l.free_reason is null and s.channel = 'warehouse' and not public.so_demand_so_excluded(s.id)
  ),
  grp as (
    select x.comp_id,
           (array_agg(x.customer_id order by x.order_date, x.so_number, x.line_no))[1] as customer_id,
           (array_agg(x.stock_pid   order by x.order_date, x.so_number, x.line_no))[1] as stock_pid,
           (array_agg(x.location_id order by x.order_date, x.so_number, x.line_no))[1] as location_id,
           (array_agg(x.location_name order by x.order_date, x.so_number, x.line_no))[1] as location_name,
           count(distinct x.customer_id) as customer_n, count(distinct x.stock_pid) as product_n,
           min(x.order_date) as first_order_date, max(x.last_ended_at) as last_ended_at,
           count(*) as line_n,
           sum(x.demand) as demand_raw, sum(x.sold) as sold, sum(x.lost) as lost_raw, sum(x.in_progress) as in_progress, sum(x.open_backorder) as open_backorder,
           sum(x.flagged_qty) as flagged,
           sum(x.lost_unwanted) as lost_unwanted, sum(x.lost_expired) as lost_expired, sum(x.lost_cancelled) as lost_cancelled, sum(x.lost_removed) as lost_removed,
           sum(x.in_progress) filter (where x.so_status = 'draft') as ip_draft,
           sum(x.in_progress) filter (where x.so_status = 'confirmed') as ip_confirmed,
           sum(x.in_progress) filter (where x.so_status in ('at_wms', 'picking', 'packed')) as ip_warehouse,
           sum(x.in_progress) filter (where x.so_status not in ('draft', 'confirmed', 'at_wms', 'picking', 'packed')) as ip_other,
           count(*) filter (where x.flag_id is not null) as flagged_lines,
           jsonb_agg(jsonb_build_object(
             'line_id', x.line_id, 'so_id', x.so_id, 'so_number', x.so_number, 'so_status', x.so_status, 'order_date', x.order_date, 'line_no', x.line_no,
             'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'pack_factor', x.pack_factor, 'location_name', x.location_name,
             'ordered', x.ordered, 'sold', x.sold, 'removed', x.removed, 'transferred', x.transferred, 'demand', x.demand,
             'lost', x.lost, 'lost_by', jsonb_build_object('unwanted', x.lost_unwanted, 'expired', x.lost_expired, 'cancelled', x.lost_cancelled, 'removed', x.lost_removed),
             'in_progress', x.in_progress, 'open_backorder', x.open_backorder, 'end_kinds', x.end_kinds, 'last_ended_at', x.last_ended_at,
             'flag', case when x.flag_id is null then null else jsonb_build_object('id', x.flag_id, 'reason', x.flag_reason, 'note', x.flag_note, 'flagged_at', x.flagged_at, 'flagged_by', x.flagged_by, 'qty', x.flagged_qty) end
           ) order by x.order_date, x.so_number, x.line_no) as lines,
           array_agg(distinct x.so_number) as so_numbers
    from line x
    group by x.comp_id
  ),
  base as (
    select g.*, cu.name as customer_name, sp.id as product_id, sp.sku as stock_sku, sp.name as stock_name, sp.brand_id, sp.brand_name,
           ps.supplier_id, su.name as supplier_name,
           g.demand_raw - g.flagged as demand_then, g.lost_raw - g.flagged as lost
    from grp g
    join public.customer cu on cu.id = g.customer_id
    join public.product sp on sp.id = g.stock_pid
    left join public.product_supplier ps on ps.product_id = sp.id and ps.is_default and ps.is_active
    left join public.supplier su on su.id = ps.supplier_id
  ),
  filtered as (
    select * from base b
    where (f->>'customer_id' is null or b.customer_id = (f->>'customer_id')::uuid)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and b.supplier_id is null) or (f->>'supplier_id' <> 'none' and b.supplier_id = (f->>'supplier_id')::uuid))
      and (f->>'brand_id'    is null or b.brand_id = (f->>'brand_id')::uuid)
      and (f->>'sku'         is null or b.stock_sku ilike (f->>'sku') || '%' or exists (select 1 from jsonb_array_elements(b.lines) j where j->>'sku' ilike (f->>'sku') || '%'))
      and (f->>'product_id'  is null or b.product_id = (f->>'product_id')::uuid or exists (select 1 from jsonb_array_elements(b.lines) j where (j->>'product_id')::uuid = (f->>'product_id')::uuid))
      and (f->>'location_id' is null or b.location_id = (f->>'location_id')::uuid)
      and (f->>'order_from'  is null or b.first_order_date >= (f->>'order_from')::date)
      and (f->>'order_to'    is null or b.first_order_date <= (f->>'order_to')::date)
      and (f->>'ended_from'  is null or (b.last_ended_at at time zone 'America/Toronto')::date >= (f->>'ended_from')::date)
      and (f->>'ended_to'    is null or (b.last_ended_at at time zone 'America/Toronto')::date <= (f->>'ended_to')::date)
      and (f->>'open'        is null or (b.open_backorder > 0) = (f->>'open')::boolean)
      and (f->>'flagged'     is null or (b.flagged_lines > 0) = (f->>'flagged')::boolean)
  )
  select jsonb_build_object(
    'total', count(*), 'limit', v_limit, 'offset', v_offset, 'filters', f,
    'sums', jsonb_build_object('demand_then', coalesce(sum(demand_then), 0), 'sold', coalesce(sum(sold), 0), 'lost', coalesce(sum(lost), 0),
                               'in_progress', coalesce(sum(in_progress), 0), 'open_backorder', coalesce(sum(open_backorder), 0), 'flagged', coalesce(sum(flagged), 0)),
    'identity', 'demand_then = sold + lost + in_progress + open_backorder (after flags) · demand_then = Σ(ordered − transferred) − flagged · lost = unwanted + expired + cancelled(ledger + cancelled-order remainder) + removed − flagged',
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'comp_id', x.comp_id, 'customer_id', x.customer_id, 'customer_name', x.customer_name,
        'product_id', x.product_id, 'sku', x.stock_sku, 'product_name', x.stock_name, 'brand_id', x.brand_id, 'brand_name', x.brand_name,
        'supplier_id', x.supplier_id, 'supplier_name', x.supplier_name, 'location_id', x.location_id, 'location_name', x.location_name,
        'first_order_date', x.first_order_date, 'last_ended_at', x.last_ended_at, 'so_numbers', to_jsonb(x.so_numbers), 'line_n', x.line_n,
        'demand_then', x.demand_then, 'sold', x.sold, 'lost', x.lost, 'in_progress', x.in_progress, 'open_backorder', x.open_backorder, 'flagged', x.flagged,
        'demand_raw', x.demand_raw, 'lost_raw', x.lost_raw,
        'lost_by', jsonb_build_object('unwanted', x.lost_unwanted, 'expired', x.lost_expired, 'cancelled', x.lost_cancelled, 'removed', x.lost_removed),
        'in_progress_by', jsonb_build_object('draft', coalesce(x.ip_draft, 0), 'confirmed', coalesce(x.ip_confirmed, 0), 'warehouse', coalesce(x.ip_warehouse, 0), 'other', coalesce(x.ip_other, 0)),
        'flagged_lines', x.flagged_lines, 'customer_n', x.customer_n, 'product_n', x.product_n, 'lines', x.lines)
      order by x.customer_name, x.customer_id, x.stock_sku, x.first_order_date, x.comp_id)
      from (select * from filtered order by customer_name, customer_id, stock_sku, first_order_date, comp_id limit v_limit offset v_offset) x), '[]'::jsonb))
  into v_out
  from filtered;
  return v_out;
end;
$$;
comment on function public.so_backorder_demand(jsonb) is
  '⭐ 백오더 수요 읽기(bo-1a · 판정 464 · 475 ~ 478 · 483) — 단위 = 손님 × 재고 제품의 연결 덩어리(씨앗 = 백오더가 한 번이라도 있었던 수요 줄 · 변 셋 split_from_line_id · 활성 장부 taken_by_line_id · so_line_merge_source · 양방향 재귀 · 병합 겹셈 없음) · 덩어리마다 demand_then · sold · lost(lost_by) · in_progress(in_progress_by) · open_backorder · flagged · lines[] · 항등식 demand_then = sold + lost + in_progress + open_backorder · 뺀다 = 무상 줄 · pos·counter · 콤보 구성품 · 되돌려진 장부 행 · 필터 14(customer_id · supplier_id(none) · brand_id · sku · product_id · location_id(첫 오더 창고) · order_from/to(첫 주문일) · ended_from/to(마지막 끝난 날 · 토론토) · open · flagged · limit ≤ 1000 · offset) · invoker · stable · 임시 표 없음';
revoke all on function public.so_backorder_demand(jsonb) from public, anon;
grant execute on function public.so_backorder_demand(jsonb) to authenticated;

-- ═══ ④ 창구 so_demand_flag_set · so_demand_flag_clear ═══
create function public.so_demand_flag_set(p_line_ids uuid[], p_reason text, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_ids uuid[];  v_bad text;  v_rows jsonb;  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄(판정 478: 매니저가 달고 뗀다)
  v_staff := public.so_current_staff();
  if p_reason is null or p_reason not in ('staff_error', 'duplicate', 'test', 'other') then
    raise exception 'Reason must be staff_error, duplicate, test or other (got %) — nothing was saved', coalesce(p_reason, '(null)');
  end if;
  if p_reason = 'other' and v_note is null then raise exception 'Reason "other" needs a note — nothing was saved'; end if;
  select array_agg(distinct x) into v_ids from unnest(coalesce(p_line_ids, '{}'::uuid[])) x where x is not null;
  if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'No lines given — nothing was saved'; end if;
  select x::text into v_bad from unnest(v_ids) x where not exists (select 1 from public.so_line l where l.id = x) limit 1;
  if v_bad is not null then raise exception 'Line % not found — nothing was saved', v_bad; end if;
  select format('Line %s (%s) of %s %s — nothing was saved', l.line_no, l.sku, s.so_number,
                case when l.combo_line_id is not null then 'is a combo component — flag the combo line instead'
                     when l.free_reason is not null then 'is a free line — free lines are never counted as demand'
                     when s.channel <> 'warehouse' then 'belongs to a ' || s.channel || ' order — POS and counter orders are never counted as demand'
                     else 'belongs to an order that was unconfirmed and then cancelled — it is already outside the demand count, no flag is needed' end)
    into v_bad
  from public.so_line l join public.so s on s.id = l.so_id
  where l.id = any(v_ids) and (l.combo_line_id is not null or l.free_reason is not null or s.channel <> 'warehouse' or public.so_demand_so_excluded(s.id))
  order by s.so_number, l.line_no limit 1;
  if v_bad is not null then raise exception '%', v_bad; end if;
  select format('Line %s (%s) of %s already has an active not-real-demand flag (%s) — clear it first — nothing was saved', l.line_no, l.sku, s.so_number, fl.reason)
    into v_bad
  from public.so_demand_flag fl join public.so_line l on l.id = fl.so_line_id join public.so s on s.id = l.so_id
  where fl.active_line_id = any(v_ids) order by s.so_number, l.line_no limit 1;
  if v_bad is not null then raise exception '%', v_bad; end if;
  select format('Line %s (%s) of %s has no lost sale to exclude (lost 0) — the flag would not change the demand count — nothing was saved', l.line_no, l.sku, s.so_number)
    into v_bad
  from public.so_line l join public.so s on s.id = l.so_id cross join lateral public.so_demand_line(l.id) d
  where l.id = any(v_ids) and d.lost <= 0 order by s.so_number, l.line_no limit 1;
  if v_bad is not null then raise exception '%', v_bad; end if;

  perform pg_advisory_xact_lock(hashtext('so_demand_flag:' || x::text)) from unnest(v_ids) x;
  with ins as (
    insert into public.so_demand_flag (so_line_id, reason, note, flagged_by, updated_by)
    select x, p_reason, v_note, v_staff, v_staff from unnest(v_ids) x
    returning id, so_line_id, flagged_at
  )
  select jsonb_agg(jsonb_build_object('flag_id', i.id, 'line_id', i.so_line_id, 'so_number', s.so_number, 'line_no', l.line_no, 'sku', l.sku, 'lost', d.lost) order by s.so_number, l.line_no)
    into v_rows
  from ins i join public.so_line l on l.id = i.so_line_id join public.so s on s.id = l.so_id cross join lateral public.so_demand_line(l.id) d;
  return jsonb_build_object('flagged', v_rows, 'count', jsonb_array_length(v_rows), 'reason', p_reason, 'note', v_note, 'at', now(), 'by', v_staff);
exception
  when unique_violation then
    raise exception 'A line in this set was flagged by someone else just now — reload and try again — nothing was saved';
end;
$$;
comment on function public.so_demand_flag_set(uuid[], text, text) is
  '⭐ 「진짜 수요 아님」 표식 달기(bo-1a · 판정 478) — sales 쓰기 + manager 이상 · 여러 줄 한 번에 · 하나라도 거부면 아무것도 안 쓴다 · 거부: 없는 줄 · 콤보 구성품 · 무상 줄 · pos·counter 오더 · 이미 활성 표식 · 사유 틀림 · other 인데 메모 없음 · 잃은 판매 0 인 줄(표식이 셈을 바꾸지 않는다) · ⚠️ so · so_line · so_reserve · so_backorder_close 무접촉 · 반환 {flagged[] · count · reason · note · at · by}';
revoke all on function public.so_demand_flag_set(uuid[], text, text) from public, anon;
grant execute on function public.so_demand_flag_set(uuid[], text, text) to authenticated;

create function public.so_demand_flag_clear(p_line_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_ids uuid[];  v_bad text;  v_rows jsonb;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  select array_agg(distinct x) into v_ids from unnest(coalesce(p_line_ids, '{}'::uuid[])) x where x is not null;
  if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'No lines given — nothing was saved'; end if;
  select x::text into v_bad from unnest(v_ids) x where not exists (select 1 from public.so_line l where l.id = x) limit 1;
  if v_bad is not null then raise exception 'Line % not found — nothing was saved', v_bad; end if;
  select format('Line %s (%s) of %s has no active not-real-demand flag — nothing was saved', l.line_no, l.sku, s.so_number)
    into v_bad
  from public.so_line l join public.so s on s.id = l.so_id
  where l.id = any(v_ids) and not exists (select 1 from public.so_demand_flag fl where fl.active_line_id = l.id)
  order by s.so_number, l.line_no limit 1;
  if v_bad is not null then raise exception '%', v_bad; end if;
  perform pg_advisory_xact_lock(hashtext('so_demand_flag:' || x::text)) from unnest(v_ids) x;
  with upd as (
    update public.so_demand_flag fl set unflagged_at = now(), unflagged_by = v_staff, updated_by = v_staff
    where fl.active_line_id = any(v_ids)
    returning fl.id, fl.so_line_id, fl.reason
  )
  select jsonb_agg(jsonb_build_object('flag_id', u.id, 'line_id', u.so_line_id, 'so_number', s.so_number, 'line_no', l.line_no, 'sku', l.sku, 'reason', u.reason) order by s.so_number, l.line_no)
    into v_rows
  from upd u join public.so_line l on l.id = u.so_line_id join public.so s on s.id = l.so_id;
  return jsonb_build_object('cleared', v_rows, 'count', jsonb_array_length(v_rows), 'at', now(), 'by', v_staff);
end;
$$;
comment on function public.so_demand_flag_clear(uuid[]) is
  '⭐ 「진짜 수요 아님」 표식 떼기(bo-1a · 판정 478) — sales 쓰기 + manager 이상 · 여러 줄 한 번에 · 활성 표식이 없는 줄이 하나라도 있으면 아무것도 안 쓴다 · 행을 지우지 않고 unflagged_at/by · 반환 {cleared[] · count · at · by}';
revoke all on function public.so_demand_flag_clear(uuid[]) from public, anon;
grant execute on function public.so_demand_flag_clear(uuid[]) to authenticated;

-- ═══ ⑤ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if to_regclass('public.so_demand_flag') is null then v_bad := v_bad || ' table'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.so_demand_flag'::regclass and contype = 'c') <> 3
     or (select count(*) from pg_constraint where conrelid = 'public.so_demand_flag'::regclass and contype = 'u') <> 1 then v_bad := v_bad || ' constraints'; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.so_demand_flag'::regclass) then v_bad := v_bad || ' rls'; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'so_demand_flag') <> 1 then v_bad := v_bad || ' policy'; end if;
  if has_table_privilege('anon', 'public.so_demand_flag', 'select') or has_table_privilege('authenticated', 'public.so_demand_flag', 'insert')
     or has_table_privilege('authenticated', 'public.so_demand_flag', 'update') or has_table_privilege('authenticated', 'public.so_demand_flag', 'delete')
     or not has_table_privilege('authenticated', 'public.so_demand_flag', 'select') then v_bad := v_bad || ' table-acl'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_demand_so_excluded', 'so_demand_line', 'so_backorder_demand', 'so_demand_flag_set', 'so_demand_flag_clear')) <> 5 then v_bad := v_bad || ' functions'; end if;
  if has_function_privilege('anon', 'public.so_demand_line(uuid)', 'execute') or has_function_privilege('anon', 'public.so_demand_so_excluded(uuid)', 'execute') or has_function_privilege('anon', 'public.so_backorder_demand(jsonb)', 'execute')
     or has_function_privilege('anon', 'public.so_demand_flag_set(uuid[], text, text)', 'execute') or has_function_privilege('anon', 'public.so_demand_flag_clear(uuid[])', 'execute')
     or not has_function_privilege('authenticated', 'public.so_backorder_demand(jsonb)', 'execute') or not has_function_privilege('authenticated', 'public.so_demand_flag_set(uuid[], text, text)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if (select prosecdef or provolatile <> 's' from pg_proc where oid = 'public.so_backorder_demand(jsonb)'::regprocedure) then v_bad := v_bad || ' demand-invoker/stable'; end if;
  if (select not prosecdef or provolatile <> 'v' from pg_proc where oid = 'public.so_demand_flag_set(uuid[], text, text)'::regprocedure) then v_bad := v_bad || ' set-definer'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM464', message = format('STOP - bo-1a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
