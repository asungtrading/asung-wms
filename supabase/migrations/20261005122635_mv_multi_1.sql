-- ─────────────────────────────────────────────────────────────
-- 칸 옮기기 · 여러 SKU 한 번에 — 읽기 창구 하나 inv_move_bin_contents (Asung-IMS · mv-multi-1 · 2026-10-05)
--   정본(뒤에 적는다): so-module §39 — 판정 234(2026-10-02 Caleb 「다로」 · 목록에 담아 한 번에 옮기기 + 「이 칸 전부 담기」) · mv-multi 묶음 1 ~ 7 · §26 판정 62 · 63 · 묶음 열 3
--   든 것: 읽기 창구 하나 — (창고, 칸) 의 장부 상품마다 book · picked · waiting · max · plans · follow 를 한 번에(상품 30 가지 = 지금 화면이면 창구 90 번 · 이 창구는 1 번)
--   ⭐ max 는 inv_move_eval 이 inv_move_confirm(= inv_move_now 의 끝)에서 막는 셈과 같은 값 — 같은 조각(inv_adjust_picked · inv_move_open_plans)을 같은 인자로 부르고,
--      장부(book)는 inv_adjust_ledger 가 읽는 ims_inv_balance.qty 의 원문 inv_balance.qty 를 (창고 이름, 칸 이름) 으로 한 번에 읽는다(ims_inv_balance 는 inv_balance 의 qty 를 바꾸지 않고 열쇠만 붙인다 · 20260919151601)
--      · 창구가 definer 라 inv_move_confirm(definer) 과 같은 눈으로 센다 — 화면이 invoker 로 부르던 세 조각은 transfer 픽을 RLS(inv_transfer_select_warehouse)로 못 보는 직원에게 더 큰 max 를 보일 수 있었다(mv-multi-1 보고 이견 2)
--   ⚠️ 쓰기 없음 · 기존 함수 재발행 없음 · 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 이 창구는 IMS 안에서만 선다(판정 51 · 60)
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

-- ═══ 1) 읽기 창구 — 칸 안의 상품과 「옮길 수 있는 최대」 (묶음 1 · 판정 62 · 63) ═══
--   문: inv_move_require(창고) 첫 줄 — 옮기기 열쇠(stock_move · 역할 또는 사람마다) + 그 창고 접근 + 활성 직원 · 읽기 창구라도 문장은 「— nothing was saved」 모양(inv_move_* 와 같다)
--   definer 인 까닭: ① inv_move_require 는 authenticated 에서 회수돼 invoker 창구가 못 부른다 ② inv_move_confirm 이 definer 로 세는 값과 같은 눈이어야 한다(위 머리)
--   한 상품 = 한 줄 · 장부(inv_balance · 그 창고 이름 · 그 칸 이름)에 qty ≠ 0 인 SKU 만(음수 포함 — 음수면 max 0) · 장부 0 인데 기다리는 계획만 있는 상품은 넣지 않는다(옮길 것이 없다 · planned_bin_short 가 잡는다)
--   blocked: null = 옮길 수 있는 상품 · 'not in product master' | 'inactive' | 'set or pack' = inv_move_line_set 이 줄 자체를 거부하는 상품(max 0 · 화면은 회색)
--   max = greatest(book − picked − waiting, 0) — eval 의 max_qty 와 같은 식(eval 은 음수를 그대로 돌려주고 화면이 0 으로 보인다 · 여기서는 0 으로 접는다) · plans = eval 의 plans 와 같은 객체 · follow = Σ movable(확정 때 도착 칸으로 따라갈 계획 수량)
create function public.inv_move_bin_contents(p_warehouse_id uuid, p_bin_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_wh public.ref_warehouse%rowtype; v_b public.ref_bin%rowtype; v_items jsonb;
begin
  perform public.inv_move_require(p_warehouse_id);                                        -- ⭐ 첫 줄 문(판정 63 · 창고 접근 · 활성 직원)
  select * into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if not found then raise exception 'Warehouse not found or inactive — nothing was saved'; end if;
  if p_bin_id is null then raise exception 'Bin not found in this warehouse — nothing was saved'; end if;
  select * into v_b from public.ref_bin b where b.id = p_bin_id;
  if not found then raise exception 'Bin not found in this warehouse (%) — nothing was saved', p_bin_id; end if;
  if v_b.warehouse_id <> v_wh.id then raise exception 'Bin % is in another warehouse — nothing was saved', v_b.name; end if;
  if not v_b.is_active then raise exception 'Bin % is inactive — nothing was saved', v_b.name; end if;
  with bal as (
    select b.sku, b.qty as book from public.inv_balance b where b.warehouse = v_wh.name and b.bin = v_b.name and b.qty <> 0
  ), x as (
    select bal.sku, bal.book, p.id as product_id, p.name as product_name,
           case when p.id is null then 'not in product master' when not p.is_active then 'inactive' when p.parent_product_id is not null then 'set or pack' end as blocked,
           case when p.id is null then 0 else public.inv_adjust_picked(v_wh.id, v_b.id, p.id) end as picked,
           op.waiting, op.movable, op.plans
      from bal
      left join public.product p on p.sku = bal.sku
      cross join lateral (
        select coalesce(sum(q.blocking_qty), 0) as waiting, coalesce(sum(q.movable_qty), 0) as movable,
               coalesce(jsonb_agg(jsonb_build_object('task_id', q.task_id, 'batch_label', q.batch_label, 'so_number', q.so_number, 'status', q.task_status,
                                                     'planned', q.planned_qty, 'blocking', q.blocking_qty, 'movable', q.movable_qty) order by q.task_id, q.row_id), '[]'::jsonb) as plans
          from public.inv_move_open_plans(v_wh.id, v_b.id, p.id) q) op
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'book', x.book, 'picked', x.picked, 'waiting', x.waiting,
           'max', case when x.blocked is not null then 0 else greatest(x.book - x.picked - x.waiting, 0) end,
           'plans', x.plans, 'follow', x.movable, 'blocked', x.blocked) order by x.sku), '[]'::jsonb)
    into v_items from x;
  return jsonb_build_object('warehouse_id', v_wh.id, 'warehouse', v_wh.name, 'bin_id', v_b.id, 'bin_name', v_b.name, 'item_count', jsonb_array_length(v_items), 'items', v_items);
end;
$$;
revoke all on function public.inv_move_bin_contents(uuid, uuid) from public, anon;   grant execute on function public.inv_move_bin_contents(uuid, uuid) to authenticated;
comment on function public.inv_move_bin_contents(uuid, uuid) is
  'mv-multi-1 · 판정 234 — (창고, 칸) 안의 장부 상품마다 book(inv_balance 그 칸) · picked(inv_adjust_picked) · waiting(Σ inv_move_open_plans.blocking) · max = greatest(book − picked − waiting, 0) = inv_move_eval 이 confirm 에서 막는 셈 · plans(eval 의 plans 와 같은 객체) · follow(Σ movable) · blocked(null | not in product master | inactive | set or pack → max 0) 를 한 번에. 문 inv_move_require(stock_move + 창고). stable · definer(confirm 과 같은 눈) · 쓰기 없음. 2026-10-05';
