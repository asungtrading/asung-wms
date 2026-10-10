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

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- stock-1a — Shopify 연동 ③ 재고 올리기 · DB (2026-10-10 · 판정 421 ~ 425 · stock-0 ⓑ · 정본 docs/design/shopify-integration.md §3-d · 2a2 20261009204650 위에)
--   ① 표 shop_stock_sent(스토어 × 변형 × 창고 — 마지막으로 보낸 숫자 · 판정 422) · shop_stock_queue(스토어 × 변형 — 재고 전용 줄 · 상품 줄과 따로 · 판정 422)
--   ② 대상 한 곳 shop_stock_targets(store, pids) — 켜진 listing 의 변형만(낱개 · family 구성원 · sellable 세트 · 판정 425: 꺼진 listing 은 안 낸다)
--   ③ 보낼 숫자 shop_stock_payload(store, pids) — 변형 × 위치 · 위치별 IMS 가용(inv_available_base · 판정 421) · 꺼진 구성원 0(판정 425) · 세트 ⌊낱개 ÷ pack_factor⌋ · 음수 0 · 버퍼 없음
--   ④ 큐 넣기 shop_stock_queue_add(store, pids, reason, force) — 낱개 → 그 sellable 세트로 펼침 · 열린 줄 하나(not exists · 규칙 29) · force 는 올리기만
--   ⑤ 트리거(AFTER STATEMENT · transition table) 10: inv_ledger i·u·d(sku → product · 창고 이름 무관 — 둘 다 보낸다) · so_reserve i·u·d(so_line.product_id) · inv_transfer u(status 가 바뀐 문서의 줄) · inv_transfer_line i·u·d · product u(is_active · sellable · pack_factor · parent 가 바뀐 행) · shop_listing i·u(켜진 것 → force)
--   ⑥ 낮 비교 shop_stock_queue_diff(store) — 지금 가용 vs 마지막으로 보낸 숫자 · 다른 것만(판정 423 낮) · 새벽 덮기 shop_stock_queue_all(store) — 전부 force(판정 423 새벽)
--   ⑦ 상품 새벽 맞추기 shop_queue_all 재발행(마지막 정의 20261009204650:321 ~ 333 · 판정 424 ①) — payload hash ≠ shop_product.last_hash 인 대상만 줄에
--   ⑧ 뷰 shop_stock_list(security_invoker · 화면 stock-1c 가 읽는다)
--   ⭐ 두 표 모두 authenticated select 만(revoke all + grant select · 2a1 모양) · 쓰기는 트리거(definer) 와 EF(service_role · stock-1b) · 함수는 전부 service_role 몫(revoke authenticated)
--   ⚠️ 판정 424 ②(skipped 줄을 20 칸에 안 셈)는 EF 몫(stock-1b) — 여기 없음 · cron 등록도 stock-1b
--   적용: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f <이 파일> && supabase migration repair --status applied <버전> --db-url "$(cat ~/.asung-testdb-url)"
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ═══ 1) 표 둘 ═══
-- 1-a shop_stock_sent — 마지막으로 보낸 숫자(판정 422 「기억해 같으면 보내지 않는다」) · 쓰기는 EF(service_role) 만
create table public.shop_stock_sent (
  id             uuid primary key default gen_random_uuid(),
  store_id       uuid not null references public.shop_store (id) on delete no action,
  product_id     uuid not null references public.product (id) on delete no action,          -- Shopify 변형이 가리키는 IMS 상품(낱개 · family 구성원 · sellable 세트)
  warehouse_id   uuid not null references public.ref_warehouse (id) on delete no action,    -- shop_location.warehouse_id 와 같은 창고
  quantity       numeric not null,                                                          -- 마지막으로 보낸 Available(음수 없음)
  sent_at        timestamptz not null default now(),
  last_status    text not null default 'ok',                                                -- ok · error
  last_error     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.ims_staff (id) on delete no action,
  constraint shop_stock_sent_qty_ck     check (quantity >= 0),
  constraint shop_stock_sent_status_ck  check (last_status in ('ok', 'error')),
  constraint shop_stock_sent_uk         unique (store_id, product_id, warehouse_id)
);
create index shop_stock_sent_product_id_idx   on public.shop_stock_sent (product_id);
create index shop_stock_sent_warehouse_id_idx on public.shop_stock_sent (warehouse_id);
create index shop_stock_sent_updated_by_idx   on public.shop_stock_sent (updated_by);
create trigger shop_stock_sent_touch before update on public.shop_stock_sent for each row execute function public.ims_touch();
comment on table public.shop_stock_sent is 'stock-1a 판정 422: 스토어 × 변형(IMS 상품) × 창고 — Shopify 에 마지막으로 보낸 Available 숫자 · sent_at · last_status ok | error · 쓰기는 EF(service_role · stock-1b) 만 · 낮 비교(shop_stock_queue_diff)가 지금 가용과 대조한다';

-- 1-b shop_stock_queue — 「보낼 재고 있음」 한 줄 = 스토어 × 변형(위치는 보낼 때 둘 다) · 상품 줄(shop_push_queue)과 따로(판정 422)
create table public.shop_stock_queue (
  id          bigint generated always as identity primary key,
  store_id    uuid not null references public.shop_store (id) on delete no action,
  product_id  uuid not null references public.product (id) on delete no action,
  reason      text not null,                                                                -- inv_ledger · so_reserve · inv_transfer · product · listing_on · diff · nightly · manual
  force       boolean not null default false,                                               -- 판정 423 새벽 덮기: 마지막으로 보낸 숫자와 같아도 보낸다
  queued_at   timestamptz not null default now(),
  started_at  timestamptz,
  done_at     timestamptz,
  result      text,                                                                         -- ok · skipped_same · skipped_off · error
  error       text,
  constraint shop_stock_queue_result_ck check (result is null or result in ('ok', 'skipped_same', 'skipped_off', 'error')),
  constraint shop_stock_queue_done_ck   check ((done_at is null) = (result is null))
);
create index shop_stock_queue_open_idx    on public.shop_stock_queue (store_id, queued_at) where done_at is null;   -- 열린 줄 찾기(유니크 아님 · 규칙 29 는 유니크 부분 인덱스만 금지)
create index shop_stock_queue_product_idx on public.shop_stock_queue (product_id);
comment on table public.shop_stock_queue is 'stock-1a 판정 422: 재고 전용 큐 — 한 줄 = 스토어 × 변형(IMS 상품) · 위치는 보낼 때 shop_location 전부 · 열린 줄(done_at null)은 대상마다 하나(shop_stock_queue_add 가 not exists 로 지킨다 · 규칙 29) · force = 새벽 덮기(같아도 보냄 · 판정 423) · result ok | skipped_same(마지막 숫자와 같음) | skipped_off(보낼 때 listing 이 꺼져 있음 · 판정 425) | error · 비우는 EF 는 stock-1b';

do $$ declare t text; begin
  foreach t in array array['shop_stock_sent', 'shop_stock_queue'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- ═══ 2) 대상 한 곳 — 켜진 listing 의 변형(판정 425: 꺼진 listing · ARCHIVED 는 안 낸다) ═══
--   낱개 listing → 그 상품 · family listing → 그 family 의 낱개 구성원(세트는 family 로 안 보낸다 · 2a1) · sellable 세트 listing → 그 세트
create function public.shop_stock_targets(p_store_id uuid, p_product_ids uuid[] default null)
  returns table (store_id uuid, product_id uuid)
  language sql stable
  set search_path = public, pg_temp
as $$
  select l.store_id, p.id
    from public.shop_listing l
    join public.shop_store s on s.id = l.store_id and s.is_active
    join public.product p on (l.product_id = p.id) or (l.family_id is not null and p.family_id = l.family_id and p.parent_product_id is null)
   where l.is_on
     and (p_store_id is null or l.store_id = p_store_id)
     and (p_product_ids is null or p.id = any(p_product_ids));
$$;
revoke all on function public.shop_stock_targets(uuid, uuid[]) from public, anon, authenticated;
comment on function public.shop_stock_targets(uuid, uuid[]) is 'stock-1a: 재고를 보낼 변형 한 곳 — 켜진 listing(스토어 하나 또는 전부)의 변형 = 낱개 listing 의 상품 · family listing 의 낱개 구성원 · sellable 세트 listing 의 세트 · p_product_ids 로 좁힌다(null = 전부) · 판정 425 꺼진 listing 의 변형은 안 낸다';

-- ═══ 3) 보낼 숫자 — 변형 × 위치(판정 421 · 425) ═══
--   quantity = 꺼진 구성원(not (is_active and sellable)) → 0 · 세트 → ⌊낱개 가용 ÷ pack_factor⌋ · 그 밖 → inv_available_base(창고 · 재고 키) · 모두 max(0, …) · 버퍼 없음
--   blocks = no_inventory_item(shop_variant.inventory_item_gid 가 아직 없다 — 상품 보내기가 먼저) · 보낼 수 있는 줄은 blocks '[]'
create function public.shop_stock_payload(p_store_id uuid, p_product_ids uuid[] default null)
  returns table (store_id uuid, product_id uuid, sku text, inventory_item_gid text, warehouse_id uuid, location_gid text, quantity numeric, is_off boolean, blocks jsonb)
  language sql stable
  set search_path = public, pg_temp
as $$
  with tg as (                                                                              -- 대상 변형(켜진 listing 만)
    select t.store_id, p.id, p.sku, p.is_active, p.sellable, p.parent_product_id, p.pack_factor, coalesce(p.parent_product_id, p.id) as stock_pid
      from public.shop_stock_targets(p_store_id, p_product_ids) t join public.product p on p.id = t.product_id
  ),
  keys as (                                                                                 -- 재고 키 배열 — 좁혔을 때만(null = 창고 전부 · stk_availability 와 같은 길)
    select case when p_product_ids is null then null else (select array_agg(distinct x.stock_pid) from tg x) end as arr
  ),
  av as (                                                                                   -- 위치마다 inv_available_base 한 번(식 한 곳 · 장부 − 판매 예약 − 트랜스퍼 예약)
    select sl.store_id, sl.warehouse_id, sl.shopify_location_gid, b.stock_pid, b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea as avail_ea
      from public.shop_location sl
      cross join lateral public.inv_available_base(sl.warehouse_id, (select k.arr from keys k)) b
     where sl.is_active and (p_store_id is null or sl.store_id = p_store_id)
  )
  select tg.store_id, tg.id, tg.sku, v.inventory_item_gid, sl.warehouse_id, sl.shopify_location_gid,
         case when not (tg.is_active and tg.sellable) then 0                                                                 -- 판정 406 · 425: 꺼진 구성원 = DENY + 0
              when tg.parent_product_id is not null then greatest(0, floor(coalesce(av.avail_ea, 0) / nullif(tg.pack_factor, 0)))   -- 세트 ⌊낱개 가용 ÷ 계수⌋
              else greatest(0, floor(coalesce(av.avail_ea, 0))) end as quantity,
         not (tg.is_active and tg.sellable) as is_off,
         case when v.inventory_item_gid is null then '["no_inventory_item"]'::jsonb else '[]'::jsonb end as blocks
    from tg
    join public.shop_location sl on sl.store_id = tg.store_id and sl.is_active
    left join public.shop_variant v on v.store_id = tg.store_id and v.product_id = tg.id
    left join av on av.store_id = tg.store_id and av.warehouse_id = sl.warehouse_id and av.stock_pid = tg.stock_pid
   order by tg.sku, sl.warehouse_id;
$$;
revoke all on function public.shop_stock_payload(uuid, uuid[]) from public, anon, authenticated;
comment on function public.shop_stock_payload(uuid, uuid[]) is 'stock-1a 판정 421 · 425: 보낼 재고 — 켜진 listing 의 변형 × 스토어의 활성 위치(shop_location)마다 한 줄 {store_id · product_id · sku · inventory_item_gid · warehouse_id · location_gid · quantity · is_off · blocks} · quantity = 꺼진 구성원 0 · 세트 ⌊낱개 가용 ÷ pack_factor⌋ · 그 밖 inv_available_base(장부 − 판매 예약 − 트랜스퍼 예약) · 음수 0 · 버퍼 없음 · blocks no_inventory_item = 상품 보내기가 먼저 · 읽기만(sql stable · 위치마다 inv_available_base 한 번) · EF 가 Available 로 직접 보낸다(changeFromQuantity null)';

-- ═══ 4) 큐 넣기 — 한 곳 ═══
create function public.shop_stock_queue_add(p_store_id uuid, p_product_ids uuid[], p_reason text, p_force boolean default false) returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_pids uuid[] := coalesce(p_product_ids, '{}');
  v_n    int := 0;
  v_m    int := 0;
begin
  if cardinality(v_pids) = 0 then return 0; end if;
  -- 낱개가 바뀌면 그것을 쓰는 sellable 세트도(세트 가용 = 낱개 ÷ 계수) · 세트가 바뀌면 그 낱개는 아니다
  select v_pids || coalesce(array_agg(x.id), '{}') into v_pids from public.product x where x.parent_product_id = any(v_pids) and x.sellable;
  if p_force then
    update public.shop_stock_queue q set force = true
      from public.shop_stock_targets(p_store_id, v_pids) t
     where q.store_id = t.store_id and q.product_id = t.product_id and q.done_at is null and not q.force;
    get diagnostics v_m = row_count;
  end if;
  insert into public.shop_stock_queue (store_id, product_id, reason, force)
  select t.store_id, t.product_id, p_reason, p_force
    from public.shop_stock_targets(p_store_id, v_pids) t
   where not exists (select 1 from public.shop_stock_queue q where q.store_id = t.store_id and q.product_id = t.product_id and q.done_at is null);
  get diagnostics v_n = row_count;
  return v_n + v_m;
end;
$$;
revoke all on function public.shop_stock_queue_add(uuid, uuid[], text, boolean) from public, anon, authenticated;
comment on function public.shop_stock_queue_add(uuid, uuid[], text, boolean) is 'stock-1a: 재고 큐 넣기 한 곳 — 상품 id 들(재고 키든 변형이든) → 그것을 쓰는 sellable 세트를 더해 → 켜진 listing 의 변형(shop_stock_targets · 스토어 하나 또는 전부)마다 열린 줄 하나(not exists · 규칙 29) · p_force 는 열린 줄이 있으면 force 를 true 로 올리기만 · 돌려주는 값 = 넣은 줄 + 올린 줄';

-- ═══ 5) 트리거 — AFTER STATEMENT · transition table · 함수 하나(tg_argv[0] = 종류) ═══
--   inv_ledger 는 product_id 가 없다 — sku 로 product 를 찾는다(ims_inv_balance 와 같은 join · 창고는 안 본다: 위치 둘 다 보낸다)
--   so_reserve 는 창고가 없다(so_line → so.location_id) — 상품만 모은다 · inv_transfer 는 status 가 바뀐 문서의 줄 · product 는 재고 숫자에 드는 칸이 바뀐 행만
--   shop_listing 은 켜진 행(insert is_on · update off → on)의 변형 전부를 force 로(판정 425 「다시 켜면 그때 전부」) · 끄기는 아무것도 안 넣는다(끄는 순간에도 안 보냄)
create function public.shop_stock_queue_trigger() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_kind text := tg_argv[0];
  v_pids uuid[] := '{}';
  v_sids uuid[] := '{}';
  v_n    int;
begin
  if v_kind = 'inv_ledger' then
    if tg_op = 'INSERT' then
      select coalesce(array_agg(distinct p.id), '{}') into v_pids from n join public.product p on p.sku = n.sku;
    elsif tg_op = 'DELETE' then
      select coalesce(array_agg(distinct p.id), '{}') into v_pids from o join public.product p on p.sku = o.sku;
    else
      select coalesce(array_agg(distinct p.id), '{}') into v_pids from (select n.sku from n union select o.sku from o) x join public.product p on p.sku = x.sku;
    end if;
  elsif v_kind = 'so_reserve' then
    if tg_op = 'INSERT' then
      select coalesce(array_agg(distinct l.product_id), '{}') into v_pids from n join public.so_line l on l.id = n.so_line_id;
    elsif tg_op = 'DELETE' then
      select coalesce(array_agg(distinct l.product_id), '{}') into v_pids from o join public.so_line l on l.id = o.so_line_id;
    else
      select coalesce(array_agg(distinct l.product_id), '{}') into v_pids
        from (select n.so_line_id from n join o on o.id = n.id where (o.qty_allocated, o.kind, o.released_at, o.so_line_id) is distinct from (n.qty_allocated, n.kind, n.released_at, n.so_line_id)) x
        join public.so_line l on l.id = x.so_line_id;
    end if;
  elsif v_kind = 'inv_transfer' then
    select coalesce(array_agg(distinct tl.product_id), '{}') into v_pids
      from n join o on o.id = n.id join public.inv_transfer_line tl on tl.transfer_id = n.id
     where (o.status, o.from_warehouse_id) is distinct from (n.status, n.from_warehouse_id);
  elsif v_kind = 'inv_transfer_line' then
    if tg_op = 'INSERT' then
      select coalesce(array_agg(distinct n.product_id), '{}') into v_pids from n;
    elsif tg_op = 'DELETE' then
      select coalesce(array_agg(distinct o.product_id), '{}') into v_pids from o;
    else
      select coalesce(array_agg(distinct x.product_id), '{}') into v_pids
        from (select n.product_id from n join o on o.id = n.id where (o.qty, o.pack_factor, o.product_id) is distinct from (n.qty, n.pack_factor, n.product_id)
              union select o.product_id from n join o on o.id = n.id where o.product_id is distinct from n.product_id) x;
    end if;
  elsif v_kind = 'product' then
    select coalesce(array_agg(distinct n.id), '{}') into v_pids
      from n join o on o.id = n.id
     where (o.is_active, o.sellable, o.pack_factor, o.parent_product_id) is distinct from (n.is_active, n.sellable, n.pack_factor, n.parent_product_id);
  elsif v_kind = 'shop_listing' then
    if tg_op = 'INSERT' then
      select coalesce(array_agg(distinct x.id), '{}') into v_sids from n x where x.is_on;
    else
      select coalesce(array_agg(distinct n.id), '{}') into v_sids from n join o on o.id = n.id where n.is_on and not o.is_on;
    end if;
    if cardinality(v_sids) > 0 then
      select coalesce(array_agg(distinct p.id), '{}') into v_pids
        from public.shop_listing l
        join public.product p on (l.product_id = p.id) or (l.family_id is not null and p.family_id = l.family_id and p.parent_product_id is null)
       where l.id = any(v_sids);
      perform public.shop_stock_queue_add(null, v_pids, 'listing_on', true);
    end if;
    return null;
  end if;
  v_n := public.shop_stock_queue_add(null, v_pids, v_kind, false);
  return null;
end;
$$;
revoke all on function public.shop_stock_queue_trigger() from public, anon, authenticated;
comment on function public.shop_stock_queue_trigger() is 'stock-1a: 가용을 바꾸는 표의 AFTER STATEMENT 트리거 함수(tg_argv[0] = inv_ledger | so_reserve | inv_transfer | inv_transfer_line | product | shop_listing) — transition table 에서 상품을 모아 shop_stock_queue_add 한 번(대상마다 한 줄 · 행 수만큼이 아니다) · inv_ledger 는 sku → product · so_reserve 는 so_line.product_id · inv_transfer 는 status · from 창고가 바뀐 문서의 줄 · product 는 is_active · sellable · pack_factor · parent 가 바뀐 행 · shop_listing 은 켜진 행의 변형 전부 force(판정 425)';

create trigger inv_ledger_shop_stock_i        after insert on public.inv_ledger        referencing new table as n                for each statement execute function public.shop_stock_queue_trigger('inv_ledger');
create trigger inv_ledger_shop_stock_u        after update on public.inv_ledger        referencing old table as o new table as n for each statement execute function public.shop_stock_queue_trigger('inv_ledger');
create trigger inv_ledger_shop_stock_d        after delete on public.inv_ledger        referencing old table as o                for each statement execute function public.shop_stock_queue_trigger('inv_ledger');
create trigger so_reserve_shop_stock_i        after insert on public.so_reserve        referencing new table as n                for each statement execute function public.shop_stock_queue_trigger('so_reserve');
create trigger so_reserve_shop_stock_u        after update on public.so_reserve        referencing old table as o new table as n for each statement execute function public.shop_stock_queue_trigger('so_reserve');
create trigger so_reserve_shop_stock_d        after delete on public.so_reserve        referencing old table as o                for each statement execute function public.shop_stock_queue_trigger('so_reserve');
create trigger inv_transfer_shop_stock_u      after update on public.inv_transfer      referencing old table as o new table as n for each statement execute function public.shop_stock_queue_trigger('inv_transfer');
create trigger inv_transfer_line_shop_stock_i after insert on public.inv_transfer_line referencing new table as n                for each statement execute function public.shop_stock_queue_trigger('inv_transfer_line');
create trigger inv_transfer_line_shop_stock_u after update on public.inv_transfer_line referencing old table as o new table as n for each statement execute function public.shop_stock_queue_trigger('inv_transfer_line');
create trigger inv_transfer_line_shop_stock_d after delete on public.inv_transfer_line referencing old table as o                for each statement execute function public.shop_stock_queue_trigger('inv_transfer_line');
create trigger product_shop_stock_u           after update on public.product           referencing old table as o new table as n for each statement execute function public.shop_stock_queue_trigger('product');
create trigger shop_listing_shop_stock_i      after insert on public.shop_listing      referencing new table as n                for each statement execute function public.shop_stock_queue_trigger('shop_listing');
create trigger shop_listing_shop_stock_u      after update on public.shop_listing      referencing old table as o new table as n for each statement execute function public.shop_stock_queue_trigger('shop_listing');

-- ═══ 6) 낮 비교 · 새벽 덮기(판정 423) ═══
create function public.shop_stock_queue_diff(p_store_id uuid default null) returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_pids uuid[]; v_n int := 0; v_s record;
begin
  for v_s in select s.id from public.shop_store s where s.is_active and (p_store_id is null or s.id = p_store_id) loop
    select coalesce(array_agg(distinct x.product_id), '{}') into v_pids
      from public.shop_stock_payload(v_s.id, null) x
      left join public.shop_stock_sent st on st.store_id = x.store_id and st.product_id = x.product_id and st.warehouse_id = x.warehouse_id
     where x.blocks = '[]'::jsonb                                                                 -- inventory_item_gid 가 없는 변형은 상품 보내기가 먼저(큐에 안 넣는다)
       and (st.id is null or st.quantity is distinct from x.quantity or st.last_status <> 'ok');
    v_n := v_n + public.shop_stock_queue_add(v_s.id, v_pids, 'diff', false);
  end loop;
  return v_n;
end;
$$;
revoke all on function public.shop_stock_queue_diff(uuid) from public, anon, authenticated;
comment on function public.shop_stock_queue_diff(uuid) is 'stock-1a 판정 423 낮: 켜진 변형 전부의 지금 가용(shop_stock_payload)을 마지막으로 보낸 숫자(shop_stock_sent)와 대조해 다른 변형만 큐에(reason diff · 보낸 적 없음 · error 도 다름으로) · 스토어 하나 또는 전부 · 돌려주는 값 = 넣은 줄 수 · cron 은 stock-1b';

create function public.shop_stock_queue_all(p_store_id uuid default null) returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_pids uuid[]; v_n int := 0; v_s record;
begin
  for v_s in select s.id from public.shop_store s where s.is_active and (p_store_id is null or s.id = p_store_id) loop
    select coalesce(array_agg(distinct t.product_id), '{}') into v_pids from public.shop_stock_targets(v_s.id, null) t;
    v_n := v_n + public.shop_stock_queue_add(v_s.id, v_pids, 'nightly', true);
  end loop;
  return v_n;
end;
$$;
revoke all on function public.shop_stock_queue_all(uuid) from public, anon, authenticated;
comment on function public.shop_stock_queue_all(uuid) is 'stock-1a 판정 423 새벽: 켜진 변형 전부를 force 로 큐에(reason nightly · 같아도 보낸다 — Shopify 쪽 어긋남을 IMS 값으로 덮는 안전망) · 열린 줄이 있으면 force 만 올린다 · 돌려주는 값 = 넣은 줄 + 올린 줄 · cron 은 stock-1b';

-- ═══ 7) 상품 새벽 맞추기 재발행 — shop_queue_all(판정 424 ①) · 마지막 정의 20261009204650_shop_2a2_listing_set.sql:321 ~ 333 · 시그니처 · 권한 그대로 ═══
--   바뀐 것: 켜진 대상 전부를 넣던 것 → 대상마다 shop_product_payload 의 hash 를 shop_product.last_hash 와 대조해 다른 것만(보낸 적 없는 대상 · last_status error 도 다름으로) · 판정 414 의 「IMS 쪽 놓침을 잡는 안전망」은 그대로
create or replace function public.shop_queue_all(p_store_id uuid default null) returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_fids uuid[] := '{}'; v_pids uuid[] := '{}'; v_n int := 0; v_l record;
begin
  for v_l in
    select l.store_id, l.family_id, l.product_id
      from public.shop_listing l join public.shop_store s on s.id = l.store_id and s.is_active
     where l.is_on and (p_store_id is null or l.store_id = p_store_id)
  loop
    if exists (select 1 from public.shop_product sp
                where sp.store_id = v_l.store_id and sp.family_id is not distinct from v_l.family_id and sp.product_id is not distinct from v_l.product_id
                  and sp.last_status = 'ok'
                  and sp.last_hash = (public.shop_product_payload(v_l.store_id, v_l.family_id, v_l.product_id)->>'hash')) then
      continue;                                                                                   -- 판정 424 ①: 보낸 것과 같으면 줄에 세우지 않는다
    end if;
    v_n := v_n + public.shop_queue_add(case when v_l.family_id is null then '{}'::uuid[] else array[v_l.family_id] end,
                                       case when v_l.product_id is null then '{}'::uuid[] else array[v_l.product_id] end,
                                       'nightly', v_l.store_id);
  end loop;
  return v_n;
end;
$$;
comment on function public.shop_queue_all(uuid) is 'shop-2a2 설계 §3-e 새벽 전체 맞추기 · ⭐ stock-1a 재발행(판정 424 ①): 켜진 listing(스토어 하나 또는 전부)마다 shop_product_payload 의 hash 를 shop_product.last_hash 와 대조해 **다른 대상만** 큐에(reason nightly · 보낸 적 없음 · last_status error 도) · 같은 대상은 줄 0 · 열린 줄이 있으면 건너뜀 · 돌려주는 값 = 넣은 줄 수 · 판정 414(안전망 · 되돌리지 않음)는 그대로 · 실행권 service_role · cron jobid 43';

-- ═══ 8) 뷰 — 화면 stock-1c 가 읽는다(security_invoker · select 만) ═══
create view public.shop_stock_list with (security_invoker = true) as
select st.id, st.store_id, s.code as store_code, st.product_id, p.sku, p.name,
       st.warehouse_id, w.name as warehouse_name, sl.shopify_name as location_name, sl.shopify_location_gid,
       st.quantity, st.sent_at, st.last_status, st.last_error,
       (select count(*) from public.shop_stock_queue q where q.store_id = st.store_id and q.product_id = st.product_id and q.done_at is null) as open_queue,
       (select max(q.done_at) from public.shop_stock_queue q where q.store_id = st.store_id and q.product_id = st.product_id) as last_queue_done_at
  from public.shop_stock_sent st
  join public.shop_store s on s.id = st.store_id
  join public.product p on p.id = st.product_id
  join public.ref_warehouse w on w.id = st.warehouse_id
  left join public.shop_location sl on sl.store_id = st.store_id and sl.warehouse_id = st.warehouse_id;
revoke all on public.shop_stock_list from anon, authenticated;
grant select on public.shop_stock_list to authenticated;
comment on view public.shop_stock_list is 'stock-1a: 화면용 — 스토어 × 변형 × 창고마다 마지막으로 보낸 Available · 시각 · 결과 · 열린 재고 큐 수 · security_invoker(shop_stock_sent select 정책) · 화면은 stock-1c';
