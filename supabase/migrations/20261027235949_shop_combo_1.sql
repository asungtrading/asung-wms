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
-- shop-combo-1 — Shopify 로 보내는 콤보 재고 = 구성품으로 만들 수 있는 수(판정 831 · 2026-10-27 · 지시서 ~/asung/prompts/shop-combo-1.md)
--   왜: 콤보는 재고를 두지 않고 팔 때 구성품을 뺀다(판정 244 · so-module §44) — 콤보 SKU 는 원장에 닿지 않으므로 지금 shop_stock_payload(stock-1a 20261010194732)는
--       콤보를 낱개로 보아 늘 0 을 보낸다 · asung.ca · aonebeauty.com 에서 콤보 SKU 가 팔리고 있다(Caleb 2026-10-27) ⇒ 재고 0 이 나가면 웹에서 못 판다(aone Don't allow) · 백오더만 쌓인다(asung Allow)
--   판정 831: Shopify 로 보내는 콤보 재고 = SO 화면 가용과 같은 셈 — 위치마다 min(구성품 재고 키마다 ⌊가용 ÷ 콤보 하나에 드는 낱개⌋) · Cin7 화면(맥시멈 콤보 수)과 같은 셈
--     · 구성품 하나라도 꺼졌거나(is_active false · sellable false) 가용 0 이면 콤보 0 · 구성품 재고가 움직이면 그 구성품이 든 콤보도 큐에 · 콤보 정의를 고치거나 Release 해도 그 콤보를 큐에
--   ① shop_stock_payload 재발행(시그니처 · 반환 꼴 · 낱개 · 세트 · 꺼짐 갈래 그대로) — 콤보 갈래 하나 더
--      · 콤보 = product_bom 에 is_active 줄이 있는 부모 · 구성품을 재고 키(coalesce(parent_product_id, id))마다 묶어 need_ea = sum(quantity × 구성품 pack_factor(낱개는 null → 1))
--        (같은 낱개를 낱개 · 세트로 둘 다 쓰는 콤보가 한 키로 묶이는 까닭 — so_lines_available combo CTE 와 같다)
--      · 위치마다 quantity = min over 재고 키 ⌊가용 ÷ need_ea⌋ · 음수 0 · 잔고 행이 없는 키는 left join + coalesce 0(bo-2b 함정 · asung-so 4-n)
--      · 가용 식은 그대로 inv_available_base(장부 − 판매 예약 − 트랜스퍼 예약 · 위치마다 한 번) — SO 의 so_available_many 는 inv_available_base 의 껍데기(stk-1 20261006143300)라 같은 수
--      · 좁힌 호출(p_product_ids)에서는 keys 배열에 구성품 재고 키를 더한다(빠지면 0 이 나간다)
--      · 구성품 가운데 하나라도 is_active false 또는 sellable false → 그 콤보 quantity 0 · is_off 는 콤보 자신 기준 그대로(EF planRows 는 is_off 를 읽지 않는다 — _shared/shopify-stock.ts :34 ~ 58)
--      · Release 한 콤보(켜진 bom 줄 0)는 콤보가 아니다 → 낱개 갈래(자기 가용 · 보통 0) · 판정 819
--      · 콤보 자신의 장부 잔고는 보지 않는다(UNF18155 처럼 잔고가 남은 콤보도 구성품 셈 — 판정 244 · product_bom_set 의 parent_stock 알림이 치우라고 한다)
--   ② shop_stock_queue_add 재발행 — 세트 펼치기 뒤에 「이 상품(또는 그 재고 키)을 구성품으로 가진 켜진 bom 의 부모」 를 더한다
--      · 재고 키 단위: 낱개가 바뀌면 그 낱개의 세트를 구성품으로 쓰는 콤보도 · 세트가 바뀌면 그 낱개를 쓰는 콤보도 · 콤보 안 콤보는 없다(product_bom_set parent_is_component · component_is_combo)
--      · 트리거 여섯(inv_ledger · so_reserve · inv_transfer · inv_transfer_line · product · shop_listing)과 diff · nightly 가 모두 이 한 곳을 지나므로 다 따라온다
--   ③ shop_stock_queue_trigger 재발행 — tg_argv 'product_bom' 갈래 하나(기존 꼴) + product_bom 에 AFTER STATEMENT 트리거 셋(i · u · d · transition table)
--      · 그 부모(콤보)를 force 로 큐에(reason product_bom) · update 는 parent · component · quantity · is_active 가 바뀐 행만(product 갈래와 같은 결 — 적재 ipr_loadBom_ 의 같은 값 upsert 는 0 줄)
--      · 창구 product_bom_set(update · insert · Release = is_active false) · product_combo_create(insert) 는 모두 이 표를 직접 쓴다(본문 확인) — 창구는 안 고친다
--      · 적재 ipr_loadBom_(service_role REST upsert)도 이 트리거를 탄다 — live 전 스토어는 shop_stock_targets 가 0(shop-live-1 판정 815) · live 스토어는 바뀐 콤보만 force(맞는 값이 다시 나간다)
--   안전망 둘은 그대로 따라온다 — shop_stock_queue_diff(낮 · payload 와 sent 대조) · shop_stock_queue_all(새벽 force) 은 payload · targets 를 읽는다(shop-live-1 20261027190714 :73 ~ 106 확인)
--   새 표 없음 · product_bom 은 거래 표가 아님 — 컷오버 날 지우는 순서 해당 없음
--   권한: 셋 다 revoke authenticated 그대로(service_role · 트리거 몫) · 시험 supabase/tests/shop_combo_1.sql
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20261027235949_shop_combo_1.sql -c "set local lock_timeout = '5s'" && supabase migration repair --status applied 20261027235949 --db-url "$(cat ~/.asung-testdb-url)"
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ═══ 1) 보낼 숫자 — 변형 × 위치(판정 421 · 425 · ⭐ 831 콤보) ═══
--   quantity = 꺼진 변형(not (is_active and sellable)) → 0 · 콤보 → min over 구성품 재고 키 ⌊가용 ÷ need_ea⌋(구성품 하나라도 꺼지면 0) · 세트 → ⌊낱개 가용 ÷ pack_factor⌋ · 그 밖 → inv_available_base(창고 · 재고 키) · 모두 max(0, …) · 버퍼 없음
--   blocks = no_inventory_item(shop_variant.inventory_item_gid 가 아직 없다 — 상품 보내기가 먼저) · 보낼 수 있는 줄은 blocks '[]'
create or replace function public.shop_stock_payload(p_store_id uuid, p_product_ids uuid[] default null)
  returns table (store_id uuid, product_id uuid, sku text, inventory_item_gid text, warehouse_id uuid, location_gid text, quantity numeric, is_off boolean, blocks jsonb)
  language sql stable
  set search_path = public, pg_temp
as $$
  with tg as (                                                                              -- 대상 변형(켜진 listing 만)
    select t.store_id, p.id, p.sku, p.is_active, p.sellable, p.parent_product_id, p.pack_factor, coalesce(p.parent_product_id, p.id) as stock_pid,
           exists (select 1 from public.product_bom b where b.parent_product_id = p.id and b.is_active) as is_combo         -- shop-combo-1: 켜진 bom 줄이 있는 부모 = 콤보(Release 한 것은 콤보가 아니다 · 판정 819)
      from public.shop_stock_targets(p_store_id, p_product_ids) t join public.product p on p.id = t.product_id
  ),
  cb as (                                                                                   -- shop-combo-1 판정 831: 콤보 × 구성품 재고 키 — need_ea = 콤보 하나에 드는 낱개(sum(quantity × 구성품 pack_factor · 낱개 1)) · comps_on = 그 키의 구성품이 전부 켜짐
    select tg.store_id, tg.id as combo_id, coalesce(c.parent_product_id, c.id) as stock_pid,
           sum(b.quantity * coalesce(c.pack_factor, 1)) as need_ea,
           bool_and(c.is_active and c.sellable) as comps_on
      from tg
      join public.product_bom b on b.parent_product_id = tg.id and b.is_active
      join public.product c on c.id = b.component_product_id
     where tg.is_combo
     group by 1, 2, 3
  ),
  keys as (                                                                                 -- 재고 키 배열 — 좁혔을 때만(null = 창고 전부 · stk_availability 와 같은 길) · 콤보의 구성품 키를 더한다(빠지면 0 이 나간다)
    select case when p_product_ids is null then null
                else (select array_agg(distinct k.stock_pid) from (select x.stock_pid from tg x union select y.stock_pid from cb y) k) end as arr
  ),
  av as (                                                                                   -- 위치마다 inv_available_base 한 번(식 한 곳 · 장부 − 판매 예약 − 트랜스퍼 예약)
    select sl.store_id, sl.warehouse_id, sl.shopify_location_gid, b.stock_pid, b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea as avail_ea
      from public.shop_location sl
      cross join lateral public.inv_available_base(sl.warehouse_id, (select k.arr from keys k)) b
     where sl.is_active and (p_store_id is null or sl.store_id = p_store_id)
       and sl.store_id in (select distinct x.store_id from tg x)                                                   -- shop-combo-1: av 를 둘(본문 · cq)이 읽어 CTE 가 물질화된다 — 대상이 있는 스토어의 위치만(live 전 스토어 위치 셋이 빠져 0.66 → 1.07 s 가 되던 것을 막는다 · 결과 같다)
  ),
  cq as (                                                                                   -- shop-combo-1: 콤보 × 위치 — 구성품 하나라도 꺼졌으면 0 · 아니면 min over 재고 키 ⌊가용 ÷ need_ea⌋ · 잔고 행 없는 키 = 0(left join + coalesce · bo-2b) · 음수 0
    select cb.store_id, cb.combo_id, sl.warehouse_id,
           case when bool_and(cb.comps_on) then greatest(0, min(floor(coalesce(av.avail_ea, 0) / cb.need_ea))) else 0 end as qty
      from cb
      join public.shop_location sl on sl.store_id = cb.store_id and sl.is_active
      left join av on av.store_id = cb.store_id and av.warehouse_id = sl.warehouse_id and av.stock_pid = cb.stock_pid
     group by 1, 2, 3
  )
  select tg.store_id, tg.id, tg.sku, v.inventory_item_gid, sl.warehouse_id, sl.shopify_location_gid,
         case when not (tg.is_active and tg.sellable) then 0                                                                 -- 판정 406 · 425: 꺼진 구성원 = DENY + 0
              when tg.is_combo then coalesce(cq.qty, 0)                                                                      -- 판정 831: 콤보 = 구성품으로 만들 수 있는 수
              when tg.parent_product_id is not null then greatest(0, floor(coalesce(av.avail_ea, 0) / nullif(tg.pack_factor, 0)))   -- 세트 ⌊낱개 가용 ÷ 계수⌋
              else greatest(0, floor(coalesce(av.avail_ea, 0))) end as quantity,
         not (tg.is_active and tg.sellable) as is_off,
         case when v.inventory_item_gid is null then '["no_inventory_item"]'::jsonb else '[]'::jsonb end as blocks
    from tg
    join public.shop_location sl on sl.store_id = tg.store_id and sl.is_active
    left join public.shop_variant v on v.store_id = tg.store_id and v.product_id = tg.id
    left join av on av.store_id = tg.store_id and av.warehouse_id = sl.warehouse_id and av.stock_pid = tg.stock_pid
    left join cq on cq.store_id = tg.store_id and cq.combo_id = tg.id and cq.warehouse_id = sl.warehouse_id
   order by tg.sku, sl.warehouse_id;
$$;
revoke all on function public.shop_stock_payload(uuid, uuid[]) from public, anon, authenticated;
comment on function public.shop_stock_payload(uuid, uuid[]) is 'stock-1a 판정 421 · 425: 보낼 재고 — 켜진 listing 의 변형 × 스토어의 활성 위치(shop_location)마다 한 줄 {store_id · product_id · sku · inventory_item_gid · warehouse_id · location_gid · quantity · is_off · blocks} · quantity = 꺼진 구성원 0 · ⭐ shop-combo-1 판정 831: 콤보(product_bom 에 켜진 줄이 있는 부모) = min over 구성품 재고 키 ⌊가용 ÷ 콤보 하나에 드는 낱개(sum(quantity × pack_factor))⌋ · 구성품 하나라도 꺼지면 0 · 콤보 자신의 잔고는 보지 않는다 · is_off 는 콤보 자신 기준 · 세트 ⌊낱개 가용 ÷ pack_factor⌋ · 그 밖 inv_available_base(장부 − 판매 예약 − 트랜스퍼 예약) · 음수 0 · 버퍼 없음 · blocks no_inventory_item = 상품 보내기가 먼저 · 읽기만(sql stable · 위치마다 inv_available_base 한 번 · 좁힌 호출은 구성품 키를 keys 에 더한다) · EF 가 Available 로 직접 보낸다(changeFromQuantity null)';

-- ═══ 2) 큐 넣기 — 한 곳(⭐ 콤보 펼치기) ═══
create or replace function public.shop_stock_queue_add(p_store_id uuid, p_product_ids uuid[], p_reason text, p_force boolean default false) returns int
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
  -- shop-combo-1 판정 831: 구성품(그 재고 키 — 낱개든 세트든)이 바뀌면 그 구성품이 든 켜진 콤보도(세트 펼치기 뒤 · 콤보 안 콤보는 없다 · 콤보 가용 = min over 구성품 키)
  select v_pids || coalesce(array_agg(distinct b.parent_product_id), '{}') into v_pids
    from public.product_bom b
    join public.product c on c.id = b.component_product_id
   where b.is_active
     and coalesce(c.parent_product_id, c.id) in (select coalesce(p.parent_product_id, p.id) from public.product p where p.id = any(v_pids));
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
comment on function public.shop_stock_queue_add(uuid, uuid[], text, boolean) is 'stock-1a: 재고 큐 넣기 한 곳 — 상품 id 들(재고 키든 변형이든) → 그것을 쓰는 sellable 세트를 더해 → ⭐ shop-combo-1 판정 831: 그 재고 키를 구성품으로 가진 켜진 콤보(product_bom 부모)를 더해 → 켜진 listing 의 변형(shop_stock_targets · 스토어 하나 또는 전부)마다 열린 줄 하나(not exists · 규칙 29) · p_force 는 열린 줄이 있으면 force 를 true 로 올리기만 · 돌려주는 값 = 넣은 줄 + 올린 줄';

-- ═══ 3) 트리거 함수 — AFTER STATEMENT · transition table · 함수 하나(tg_argv[0] = 종류 · ⭐ product_bom 갈래) ═══
--   inv_ledger 는 product_id 가 없다 — sku 로 product 를 찾는다(ims_inv_balance 와 같은 join · 창고는 안 본다: 위치 둘 다 보낸다)
--   so_reserve 는 창고가 없다(so_line → so.location_id) — 상품만 모은다 · inv_transfer 는 status 가 바뀐 문서의 줄 · product 는 재고 숫자에 드는 칸이 바뀐 행만
--   shop_listing 은 켜진 행(insert is_on · update off → on)의 변형 전부를 force 로(판정 425 「다시 켜면 그때 전부」) · 끄기는 아무것도 안 넣는다(끄는 순간에도 안 보냄)
--   product_bom(shop-combo-1) 은 그 부모(콤보)를 force 로 — insert · delete 는 전부 · update 는 parent · component · quantity · is_active 가 바뀐 행만(같은 값 upsert · note · touch 는 0 줄)
create or replace function public.shop_stock_queue_trigger() returns trigger
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
  elsif v_kind = 'product_bom' then                                                        -- shop-combo-1 판정 831: 콤보 정의가 바뀌면(줄 더하기 · 수량 · 끄기 = Release · 지우기) 그 부모를 force 로
    if tg_op = 'INSERT' then
      select coalesce(array_agg(distinct n.parent_product_id), '{}') into v_pids from n;
    elsif tg_op = 'DELETE' then
      select coalesce(array_agg(distinct o.parent_product_id), '{}') into v_pids from o;
    else
      select coalesce(array_agg(distinct x.pid), '{}') into v_pids
        from (select n.parent_product_id as pid from n join o on o.id = n.id
               where (o.parent_product_id, o.component_product_id, o.quantity, o.is_active) is distinct from (n.parent_product_id, n.component_product_id, n.quantity, n.is_active)
              union select o.parent_product_id from n join o on o.id = n.id where o.parent_product_id is distinct from n.parent_product_id) x;
    end if;
    perform public.shop_stock_queue_add(null, v_pids, 'product_bom', true);
    return null;
  end if;
  v_n := public.shop_stock_queue_add(null, v_pids, v_kind, false);
  return null;
end;
$$;
revoke all on function public.shop_stock_queue_trigger() from public, anon, authenticated;
comment on function public.shop_stock_queue_trigger() is 'stock-1a: 가용을 바꾸는 표의 AFTER STATEMENT 트리거 함수(tg_argv[0] = inv_ledger | so_reserve | inv_transfer | inv_transfer_line | product | shop_listing | ⭐ product_bom) — transition table 에서 상품을 모아 shop_stock_queue_add 한 번(대상마다 한 줄 · 행 수만큼이 아니다) · inv_ledger 는 sku → product · so_reserve 는 so_line.product_id · inv_transfer 는 status · from 창고가 바뀐 문서의 줄 · product 는 is_active · sellable · pack_factor · parent 가 바뀐 행 · shop_listing 은 켜진 행의 변형 전부 force(판정 425) · shop-combo-1 판정 831: product_bom 은 그 부모(콤보)를 force(insert · delete 전부 · update 는 parent · component · quantity · is_active 가 바뀐 행만 — 적재의 같은 값 upsert 는 0 줄)';

-- ═══ 4) product_bom 트리거 셋(AFTER STATEMENT · transition table · 기존 꼴) ═══
drop trigger if exists product_bom_shop_stock_i on public.product_bom;
drop trigger if exists product_bom_shop_stock_u on public.product_bom;
drop trigger if exists product_bom_shop_stock_d on public.product_bom;
create trigger product_bom_shop_stock_i after insert on public.product_bom referencing new table as n                for each statement execute function public.shop_stock_queue_trigger('product_bom');
create trigger product_bom_shop_stock_u after update on public.product_bom referencing old table as o new table as n for each statement execute function public.shop_stock_queue_trigger('product_bom');
create trigger product_bom_shop_stock_d after delete on public.product_bom referencing old table as o                for each statement execute function public.shop_stock_queue_trigger('product_bom');

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int;
begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_stock_payload') <> 1 then v_bad := v_bad || ' payload_count'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_stock_queue_add') <> 1 then v_bad := v_bad || ' queue_add_count'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_stock_queue_trigger') <> 1 then v_bad := v_bad || ' trigger_fn_count'; end if;
  if (select pg_get_function_identity_arguments(p.oid) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_stock_payload') <> 'p_store_id uuid, p_product_ids uuid[]' then v_bad := v_bad || ' payload_signature'; end if;
  if (select pg_get_function_result(p.oid) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_stock_payload') !~ 'quantity numeric, is_off boolean, blocks jsonb' then v_bad := v_bad || ' payload_result'; end if;
  if not (select p.prosrc ~ 'product_bom' and p.prosrc ~ 'need_ea' and p.prosrc ~ 'comps_on' and p.prosrc ~ 'is_combo' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_stock_payload') then v_bad := v_bad || ' payload_body'; end if;
  if not (select p.prosrc ~ 'product_bom' and p.prosrc ~ 'x\.parent_product_id = any\(v_pids\) and x\.sellable' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_stock_queue_add') then v_bad := v_bad || ' queue_add_body'; end if;
  if not (select p.prosrc ~ 'v_kind = ''product_bom''' and p.prosrc ~ 'v_kind = ''shop_listing''' and p.prosrc ~ 'v_kind = ''inv_ledger''' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_stock_queue_trigger') then v_bad := v_bad || ' trigger_fn_body'; end if;
  if not (select p.prosecdef from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_stock_queue_add') or not (select p.prosecdef from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_stock_queue_trigger') then v_bad := v_bad || ' definer'; end if;
  select count(*) into v_n from pg_trigger t where not t.tgisinternal and t.tgrelid = 'public.product_bom'::regclass and t.tgname like 'product\_bom\_shop\_stock\_%';
  if v_n <> 3 then v_bad := v_bad || format(' product_bom_triggers_%s', v_n); end if;
  select count(*) into v_n from pg_trigger t where not t.tgisinternal and t.tgname like '%\_shop\_stock\_%';
  if v_n <> 16 then v_bad := v_bad || format(' stock_triggers_%s', v_n); end if;
  select count(*) into v_n from pg_trigger t where not t.tgisinternal and t.tgname like '%\_shop\_stock\_%' and (t.tgtype & 1) = 1;
  if v_n <> 0 then v_bad := v_bad || format(' row_level_%s', v_n); end if;
  if has_function_privilege('authenticated', 'public.shop_stock_payload(uuid, uuid[])', 'execute') or has_function_privilege('anon', 'public.shop_stock_payload(uuid, uuid[])', 'execute')
     or has_function_privilege('authenticated', 'public.shop_stock_queue_add(uuid, uuid[], text, boolean)', 'execute') or has_function_privilege('anon', 'public.shop_stock_queue_add(uuid, uuid[], text, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.shop_stock_queue_trigger()', 'execute') or has_function_privilege('anon', 'public.shop_stock_queue_trigger()', 'execute') then v_bad := v_bad || ' grants'; end if;
  if v_bad <> '' then raise exception 'shop-combo-1 landing check failed:%', v_bad; end if;
end $$;
