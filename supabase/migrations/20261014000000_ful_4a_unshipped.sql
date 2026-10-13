-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- ful-4a — Shopify ⑤ 나가지 않을 몫 · DB 차수 (2026-10-13 · 판정 439 · 441 · 442 · 457 ~ 462 · ful-4a §0 · ful-1c 20261013230000 위에)
--   ① 표 shop_order_queue(shop_order × kind order_edit | mark_paid · unique · 큐 = Shopify 오더 열쇠 — shop_fulfill_queue 는 SO 열쇠라 따로 · 판정 462) · shop_order_requeue
--   ② 표 shop_order_line_unshipped(Shopify 줄마다 장부 — can_ship · sent · removed_qty(Shopify 가 더는 안 싣는 수량 · EF 가 적는다) · warned_qty(refund_due 로 알린 수량 · 판정 461) · restore_warned_qty(판정 460))
--   ③ shop_order.last_push_at — 오더 고치기(EF ful-4b)가 쓴 시각 · ingest 의 메아리 ⓑ 가 shop_fulfillment 와 함께 본다(재발행 한 줄)
--   ④ 함수 shop_so_family(so) — 웹 SO 와 그 형제(split_from_id 자손) · 합쳐 들어간 오더(so_line_merge_source) · so_line_can_ship(line) — IMS 줄이 아직 나갈 수 있는 몫 · shop_order_can_ship(order) — Shopify 줄마다 계보(shop_fulfill_trace)로 합산
--   ⑤ shop_unshipped_scan(limit) — 15 분 cron · created 웹 오더마다 「보낸 수량 + can_ship < Shopify 수량 − removed」 면: 돈 받음(PAID · PARTIALLY_PAID · PARTIALLY_REFUNDED · 판정 457) → 경고 refund_due(수량이 커질 때만 · 461) ·
--      안 받음 → 큐 order_edit(payload 줄 · gap_total · 같은 gap 의 done 행이 있으면 다시 안 연다 — 5 회 실패 뒤 매번 되살리지 않게) · can_ship 이 removed 를 넘어 되살아나면 경고 shopify_qty_removed 한 번(460) · 취소된 Shopify 오더(456 · 434)는 건너뜀
--   ⑥ shop_order_warn 재발행 — 코드 셋 더함 refund_due · order_edit_failed · shopify_qty_removed
--   ⚠️ 무접촉: 창구 전부(so_finalize · so_backorder_* · so_cancel · so_line_*) · EF(ful-4b) · 화면 · cron 등록(Caleb · cron.sql 블록) · 운영
--   적용: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f <이 파일> && supabase migration repair --status applied <버전> --db-url "$(cat ~/.asung-testdb-url)"
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

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


-- ═══ 1) 표 둘 · 칸 하나 ═══
create table public.shop_order_queue (
  id             bigint generated always as identity primary key,
  shop_order_id  uuid not null references public.shop_order (id) on delete no action,
  kind           text not null,                                                          -- order_edit(441 · ful-4b) · mark_paid(449 · 다음 차수)
  payload        jsonb not null default '{}'::jsonb,                                      -- order_edit: {gap_total, lines[{shop_order_line_id, line_gid, quantity, sent, removed, can_ship, gap}]}
  queued_at      timestamptz not null default now(),
  started_at     timestamptz,
  done_at        timestamptz,
  attempts       int not null default 0,
  result         text,
  error          text,
  constraint shop_order_queue_uk        unique (shop_order_id, kind),
  constraint shop_order_queue_kind_ck   check (kind in ('order_edit', 'mark_paid')),
  constraint shop_order_queue_result_ck check (result is null or result in ('ok', 'skipped', 'error')),
  constraint shop_order_queue_done_ck   check ((done_at is null) = (result is null))
);
create index shop_order_queue_open_idx on public.shop_order_queue (queued_at) where done_at is null;
create index shop_order_queue_shop_order_id_idx on public.shop_order_queue (shop_order_id);
comment on table public.shop_order_queue is 'ful-4a 판정 462: Shopify 오더 열쇠의 큐 — order_edit(441 나가지 않을 몫을 Shopify 오더에서 지운다 · EF order_drain · ful-4b) · mark_paid(449 · 다음 차수) · unique(shop_order_id, kind) · 다시 열기는 shop_order_requeue · 발송 큐(shop_fulfill_queue · SO 열쇠)와 따로';

create table public.shop_order_line_unshipped (
  shop_order_line_id  uuid primary key references public.shop_order_line (id) on delete cascade,
  shop_order_id       uuid not null references public.shop_order (id) on delete cascade,
  quantity            numeric not null,                                                  -- Shopify 줄 수량(그 순간 복사)
  sent                numeric not null default 0,                                        -- 우리가 보낸(보내는 중인) 수량 — shop_fulfillment_line coalesce(quantity_sent, quantity) · skipped 는 0
  can_ship            numeric not null default 0,                                        -- IMS 에서 아직 나갈 수 있는 몫(shop_order_can_ship)
  removed_qty         numeric not null default 0,                                        -- Shopify 가 더는 안 싣는 수량(우리가 지웠거나 Shopify 에서 지워진 것 · EF 가 실시간으로 맞춘다)
  gap                 numeric not null default 0,                                        -- quantity − sent − removed_qty − can_ship (> 0 = 나가지 않을 몫이 Shopify 에 남아 있다)
  warned_qty          numeric not null default 0,                                        -- refund_due 로 알린 수량(판정 461 · 커질 때만 다시)
  restore_warned_qty  numeric not null default 0,                                        -- shopify_qty_removed 로 알린 수량(판정 460 · 되살아난 몫)
  computed_at         timestamptz not null default now(),
  constraint shop_order_line_unshipped_qty_ck check (quantity >= 0 and sent >= 0 and can_ship >= 0 and removed_qty >= 0 and warned_qty >= 0 and restore_warned_qty >= 0)
);
create index shop_order_line_unshipped_order_idx on public.shop_order_line_unshipped (shop_order_id);
comment on table public.shop_order_line_unshipped is 'ful-4a: Shopify 줄마다 「나가지 않을 몫」 장부 — shop_unshipped_scan 이 15 분마다 다시 센다 · removed_qty 는 EF(ful-4b)가 Shopify 실시간 남은 수량으로 맞춘다 · warned_qty(판정 461) · restore_warned_qty(판정 460)';

alter table public.shop_order add column last_push_at timestamptz;
comment on column public.shop_order.last_push_at is 'ful-4a 판정 447 ⓑ: EF 가 이 오더 자체에 마지막으로 쓴 시각(orderEditCommit · 449 markAsPaid) — ingest 가 shop_fulfillment.last_push_at 과 함께 메아리 창(−5 s ~ +2 min)으로 본다';

do $$ declare t text; begin
  foreach t in array array['shop_order_queue', 'shop_order_line_unshipped'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- ═══ 2) shop_order_requeue — 큐 행을 넣거나 다시 연다(shop_fulfill_requeue 와 같은 꼴 · payload 갱신) ═══
create function public.shop_order_requeue(p_shop_order_id uuid, p_kind text, p_payload jsonb default '{}'::jsonb) returns bigint
  language sql volatile security invoker
  set search_path = public, pg_temp
as $$
  insert into public.shop_order_queue (shop_order_id, kind, payload) values (p_shop_order_id, p_kind, coalesce(p_payload, '{}'::jsonb))
  on conflict (shop_order_id, kind) do update set payload = excluded.payload, queued_at = now(), started_at = null, done_at = null, result = null, error = null, attempts = 0
  returning id;
$$;
revoke all on function public.shop_order_requeue(uuid, text, jsonb) from public, anon, authenticated;
comment on function public.shop_order_requeue(uuid, text, jsonb) is 'ful-4a: shop_order_queue 에 (오더, kind) 행을 넣거나 있으면 다시 연다(attempts 0 · payload 갱신) — shop_unshipped_scan · 449 창구가 부른다 · 직접 호출 불가';

-- ═══ 3) shop_order_warn 재발행(ful-1c 의 몸 + 코드 셋) ═══
create or replace function public.shop_order_warn(p_shop_order_id uuid, p_code text, p_message text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_w jsonb;
begin
  if p_code not in ('fulfill_failed', 'fulfill_cut', 'fulfill_location_mismatch', 'fulfill_nothing_left', 'pickup_failed', 'tracking_fix_failed', 'pickup_not_sent', 'refund_due', 'order_edit_failed', 'shopify_qty_removed') then
    raise exception 'shop_order_warn: code % is not one of fulfill_failed, fulfill_cut, fulfill_location_mismatch, fulfill_nothing_left, pickup_failed, tracking_fix_failed, pickup_not_sent, refund_due, order_edit_failed, shopify_qty_removed — nothing was saved', p_code;
  end if;
  update public.shop_order set warnings = warnings || jsonb_build_array(jsonb_build_object('code', p_code, 'message', nullif(btrim(coalesce(p_message, '')), ''), 'at', now()))
   where id = p_shop_order_id
  returning warnings into v_w;
  if not found then raise exception 'shop_order_warn: shop_order % not found — nothing was saved', p_shop_order_id; end if;
  return jsonb_build_object('shop_order_id', p_shop_order_id, 'code', p_code, 'warnings', jsonb_array_length(v_w));
end;
$$;
comment on function public.shop_order_warn(uuid, text, text) is 'ful-2a · 1b · 1c · 4a: shop_order.warnings 에 경고 한 줄 {code, message, at} 을 더한다 — 한 문장(warnings || …) · 코드 열(fulfill_failed · fulfill_cut · fulfill_location_mismatch · fulfill_nothing_left · pickup_failed · tracking_fix_failed · pickup_not_sent · refund_due · order_edit_failed · shopify_qty_removed) · service_role 만(EF) · definer 창구 안에서도';

-- ═══ 4) 계보 가족 · 나갈 수 있는 몫 ═══
-- 4-a 웹 SO 의 가족 — 자기 · split_from_id 자손(백오더 · 부족분 형제) · 그 줄이 합쳐 들어간 오더(so_line_merge_source) · 깊이 32
create function public.shop_so_family(p_so_id uuid) returns setof uuid
  language sql stable
  set search_path = public, pg_temp
as $$
  with recursive fam(id, depth) as (
    select p_so_id, 0
    union
    select x.id, f.depth + 1
      from fam f
      join lateral (select s.id from public.so s where s.split_from_id = f.id
                    union
                    select l2.so_id from public.so_line l1 join public.so_line_merge_source m on m.from_line_id = l1.id join public.so_line l2 on l2.id = m.line_id where l1.so_id = f.id) x on true
     where f.depth < 32                                                                  -- 재귀 가지는 하나(split 자손 ∪ 합쳐 들어간 오더 · PG 는 recursive term 하나만)
  )
  select distinct id from fam;
$$;
revoke all on function public.shop_so_family(uuid) from public, anon, authenticated;
comment on function public.shop_so_family(uuid) is 'ful-4a: 웹 SO 하나의 가족 SO 들 — 자기 · split 자손(백오더 · pick_short 형제) · 합쳐 들어간 오더(so_line_merge_source) · 재귀 32 — 이 가족의 줄만 계보(shop_fulfill_trace)로 Shopify 줄에 닿는다';

-- 4-b IMS 줄 하나가 아직 나갈 수 있는 몫 — draft = qty_ordered − qty_removed · confirmed ~ packed = 열린 예약(allocated · backorder · preorder · hold · released_at null · 콤보는 구성품 예약의 min(floor(qty / combo_qty))) · shipped · fulfilled · cancelled = 0(나간 것은 발송 줄 · 덜 나간 것은 형제 줄)
create function public.so_line_can_ship(p_line_id uuid) returns numeric
  language sql stable
  set search_path = public, pg_temp
as $$
  select case
    when s.status = 'draft' then greatest(coalesce(l.qty_ordered, 0) - coalesce(l.qty_removed, 0), 0)
    when s.status in ('confirmed', 'at_wms', 'picking', 'packed') then coalesce((
      select min(q.units) from (
        select cp.id, floor(coalesce(sum(r.qty_allocated), 0) / coalesce(cp.combo_qty, 1)) as units
          from public.so_line cp left join public.so_reserve r on r.so_line_id = cp.id and r.released_at is null
         where cp.id = l.id or cp.combo_line_id = l.id
         group by cp.id, cp.combo_qty
         having cp.combo_line_id is not null or not exists (select 1 from public.so_line c2 where c2.combo_line_id = l.id)   -- 콤보면 구성품 줄만 · 아니면 자기 줄
      ) q), 0)
    else 0 end
  from public.so_line l join public.so s on s.id = l.so_id where l.id = p_line_id;
$$;
revoke all on function public.so_line_can_ship(uuid) from public, anon, authenticated;
comment on function public.so_line_can_ship(uuid) is 'ful-4a ⬜2: IMS 줄이 아직 나갈 수 있는 몫 — draft 는 qty_ordered − qty_removed · confirmed ~ packed 는 열린 예약(kind 넷 · released_at null · 콤보는 구성품 예약의 min(floor(qty / combo_qty))) · shipped · fulfilled · cancelled 는 0 · 이어받기 · 만료 · 취소 · 뺀 몫 · 초안 수량 줄이기 · 되돌리기가 전부 여기 한 수로 보인다';

-- 4-c Shopify 오더의 줄마다 can_ship — 가족 줄(콤보 구성품 제외)의 can_ship 을 계보로 올려 합산
create function public.shop_order_can_ship(p_shop_order_id uuid)
  returns table (shop_order_line_id uuid, can_ship numeric)
  language sql stable
  set search_path = public, pg_temp
as $$
  select sol.id, coalesce(sum(t.quantity), 0)
    from public.shop_order o
    join public.shop_order_line sol on sol.shop_order_id = o.id
    left join lateral (
      select t.quantity
        from public.shop_so_family(o.so_id) f
        join public.so_line l on l.so_id = f and l.combo_line_id is null
        cross join lateral public.shop_fulfill_trace(l.id, public.so_line_can_ship(l.id), 0) t
       where t.shop_order_line_id = sol.id
    ) t on true
   where o.id = p_shop_order_id and o.so_id is not null
   group by sol.id, sol.line_no
   order by sol.line_no;
$$;
revoke all on function public.shop_order_can_ship(uuid) from public, anon, authenticated;
comment on function public.shop_order_can_ship(uuid) is 'ful-4a ⬜2: Shopify 오더의 줄마다 IMS 에서 아직 나갈 수 있는 몫 — 가족(shop_so_family)의 줄(콤보 구성품 제외)마다 so_line_can_ship 을 계보(shop_fulfill_trace)로 Shopify 줄에 올려 합산 · so_id 없는 오더는 0 행';

-- ═══ 5) shop_unshipped_scan — 15 분 cron · 판정 457 ~ 461 ═══
create function public.shop_unshipped_scan(p_limit int default 200) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  o        record;
  r        record;
  q        record;
  v_lines  jsonb;
  v_gap    numeric;
  v_paid   boolean;
  v_n      int := 0;  v_queued int := 0;  v_warned int := 0;  v_restored int := 0;  v_skipped int := 0;
  v_warn_q numeric;  v_rest_q numeric;
  v_msg    text;
begin
  for o in
    select so.id, so.name, so.financial_status, so.so_id
      from public.shop_order so
     where so.status = 'created' and so.so_id is not null and so.shopify_cancelled_at is null
       and exists (select 1 from public.shop_store st where st.id = so.store_id and st.is_active)
     order by so.received_at
     limit p_limit
  loop
    v_n := v_n + 1;
    -- 줄마다 다시 센다(장부 upsert · removed · warned · restore_warned 는 남긴다)
    insert into public.shop_order_line_unshipped as u (shop_order_line_id, shop_order_id, quantity, sent, can_ship, gap, computed_at)
    select sol.id, o.id, sol.quantity,
           coalesce((select sum(case when f.status = 'skipped' then coalesce(fl.quantity_sent, 0) else coalesce(fl.quantity_sent, fl.quantity) end)
                       from public.shop_fulfillment_line fl join public.shop_fulfillment f on f.id = fl.fulfillment_id
                      where fl.shop_order_line_id = sol.id and f.status in ('pending', 'sent', 'error', 'skipped')), 0),
           coalesce(c.can_ship, 0), 0, now()
      from public.shop_order_line sol left join public.shop_order_can_ship(o.id) c on c.shop_order_line_id = sol.id
     where sol.shop_order_id = o.id
    on conflict (shop_order_line_id) do update set quantity = excluded.quantity, sent = excluded.sent, can_ship = excluded.can_ship, computed_at = now();
    update public.shop_order_line_unshipped u set gap = u.quantity - u.sent - u.removed_qty - u.can_ship where u.shop_order_id = o.id;

    -- 판정 460: 지운 뒤 되살아난 몫(can_ship 이 남은 자리를 넘는다) — 경고 한 번(커질 때만) · Shopify 는 안 되살린다
    select coalesce(sum(greatest(-u.gap, 0)), 0) into v_rest_q from public.shop_order_line_unshipped u where u.shop_order_id = o.id and u.removed_qty > 0 and u.gap < 0;
    if v_rest_q > (select coalesce(sum(u.restore_warned_qty), 0) from public.shop_order_line_unshipped u where u.shop_order_id = o.id) then
      select string_agg(sol.sku || ' ×' || greatest(-u.gap, 0), ', ' order by sol.line_no) into v_msg
        from public.shop_order_line_unshipped u join public.shop_order_line sol on sol.id = u.shop_order_line_id where u.shop_order_id = o.id and u.removed_qty > 0 and u.gap < 0;
      perform public.shop_order_warn(o.id, 'shopify_qty_removed', format('IMS can ship again %s, but that quantity was already removed from Shopify order %s — add it back in Shopify by hand if the customer still wants it', v_msg, o.name));
      update public.shop_order_line_unshipped u set restore_warned_qty = greatest(-u.gap, 0) where u.shop_order_id = o.id and u.removed_qty > 0 and u.gap < 0;
      v_restored := v_restored + 1;
    end if;

    select coalesce(sum(u.gap), 0),
           coalesce(jsonb_agg(jsonb_build_object('shop_order_line_id', u.shop_order_line_id, 'line_gid', sol.line_gid, 'sku', sol.sku, 'quantity', u.quantity, 'sent', u.sent, 'removed', u.removed_qty, 'can_ship', u.can_ship, 'gap', u.gap) order by sol.line_no) filter (where u.gap > 0), '[]'::jsonb)
      into v_gap, v_lines
      from public.shop_order_line_unshipped u join public.shop_order_line sol on sol.id = u.shop_order_line_id
     where u.shop_order_id = o.id and u.gap > 0;
    if v_gap <= 0 then v_skipped := v_skipped + 1; continue; end if;

    v_paid := upper(coalesce(o.financial_status, '')) in ('PAID', 'PARTIALLY_PAID', 'PARTIALLY_REFUNDED');   -- 판정 457
    if v_paid then
      -- 판정 439 · 461: 돈 받은 오더 — 고치지 않고 「환불할 몫」 경고(알린 수량보다 커질 때만)
      select coalesce(sum(u.warned_qty), 0) into v_warn_q from public.shop_order_line_unshipped u where u.shop_order_id = o.id;
      if v_gap > v_warn_q then
        select string_agg(sol.sku || ' ×' || u.gap || ' (' || coalesce(round(u.gap * coalesce(sol.unit_price, 0), 2)::text, '?') || ')', ', ' order by sol.line_no) into v_msg
          from public.shop_order_line_unshipped u join public.shop_order_line sol on sol.id = u.shop_order_line_id where u.shop_order_id = o.id and u.gap > 0;
        perform public.shop_order_warn(o.id, 'refund_due', format('Shopify order %s was paid, but IMS will not ship %s — refund that in Shopify (the IMS order is not touched)', o.name, v_msg));
        update public.shop_order_line_unshipped u set warned_qty = u.gap where u.shop_order_id = o.id and u.gap > 0;
        v_warned := v_warned + 1;
      end if;
    else
      -- 판정 441 · 462: 돈 안 받은 오더 — 큐 order_edit(같은 gap 의 done 행이 있으면 다시 안 연다)
      select * into q from public.shop_order_queue x where x.shop_order_id = o.id and x.kind = 'order_edit';
      if q.id is null or (q.done_at is not null and (q.payload->>'gap_total')::numeric is distinct from v_gap) then
        perform public.shop_order_requeue(o.id, 'order_edit', jsonb_build_object('gap_total', v_gap, 'lines', v_lines, 'scanned_at', now()));
        v_queued := v_queued + 1;
      elsif q.done_at is null and (q.payload->>'gap_total')::numeric is distinct from v_gap then
        update public.shop_order_queue set payload = jsonb_build_object('gap_total', v_gap, 'lines', v_lines, 'scanned_at', now()) where id = q.id;   -- 열린 행은 payload 만 새로
      end if;
    end if;
  end loop;
  return jsonb_build_object('scanned', v_n, 'queued', v_queued, 'warned_refund_due', v_warned, 'warned_restored', v_restored, 'nothing', v_skipped, 'at', now());
end;
$$;
revoke all on function public.shop_unshipped_scan(int) from public, anon, authenticated;
comment on function public.shop_unshipped_scan(int) is 'ful-4a 판정 457 ~ 462: 15 분 cron(ims-unshipped-scan · postgres) — created 웹 오더마다 Shopify 줄의 「나가지 않을 몫」 gap = quantity − sent − removed_qty − can_ship 을 장부에 다시 세고 · 돈 받음(PAID · PARTIALLY_PAID · PARTIALLY_REFUNDED)이면 경고 refund_due(커질 때만) · 아니면 큐 order_edit(같은 gap 의 done 행은 다시 안 연다) · 되살아난 몫은 경고 shopify_qty_removed 한 번 · 취소된 Shopify 오더 · 꺼진 스토어는 건너뜀 · 반환 {scanned, queued, warned_refund_due, warned_restored, nothing}';

-- ═══ 6) shop_order_ingest 재발행 — ful-1b 20261013210000:76 ~ 194 바이트 복사 · 바꾼 줄 1(메아리 ⓑ 에 shop_order.last_push_at) ═══
create or replace function public.shop_order_ingest(p_store_id uuid, p_order jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_s       public.shop_store%rowtype;
  v_gid     text;
  v_o       public.shop_order%rowtype;
  v_action  text;
  v_ship    jsonb := p_order->'shippingAddress';
  v_fl      jsonb;
  v_li      jsonb;
  v_i       int := 0;
  v_n       int := 0;
  v_warn    jsonb;
  v_prep    jsonb := null;
  v_cancel  timestamptz := nullif(p_order->>'cancelledAt', '')::timestamptz;
  v_cres    jsonb := null;                                                                                                                   -- ord-1b2: 이번 받기의 shop_order_cancelled 결과
  v_auto    boolean := false;                                                                                                                -- ord-1b2: 자동 취소(auto_cancelled · closed_before_so)로 끝났나
  v_newcan  boolean := false;                                                                                                                -- ord-1b2: 이번 받기에서 처음 본 취소인가
  v_moved   boolean := false;                                                                                                                -- ord-1b2: Shopify updatedAt 이 바뀌었나
  v_dlv     record;                                                                                                                          -- ful-1b 판정 454: 배송 방식(shop_order_delivery)
  v_oldf    text[];  v_newf text[];  v_unk text[];  v_oldr text[];  v_push timestamptz;  v_echo boolean := false;  v_spec jsonb := '[]'::jsonb;  r jsonb;   -- ful-1b 판정 447: 메아리 · 구체 경고
begin
  select * into v_s from public.shop_store s where s.id = p_store_id;
  if v_s.id is null then raise exception 'shop_order_ingest: store % not found — nothing was saved', p_store_id; end if;
  if not v_s.is_active then raise exception 'shop_order_ingest: store % is off — nothing was saved', v_s.code; end if;
  if p_order is null or jsonb_typeof(p_order) <> 'object' then raise exception 'shop_order_ingest: p_order must be the GraphQL order object — nothing was saved'; end if;
  v_gid := p_order->>'id';
  if v_gid !~ '^gid://shopify/Order/[0-9]+$' then raise exception 'shop_order_ingest: order id % is not a Shopify Order GID — nothing was saved', coalesce(v_gid, '(none)'); end if;
  if nullif(p_order->>'name', '') is null then raise exception 'shop_order_ingest: order % has no name — nothing was saved', v_gid; end if;
  if coalesce(jsonb_typeof(p_order->'lineItems'->'nodes'), '') <> 'array' then raise exception 'shop_order_ingest: order % has no lineItems.nodes — nothing was saved', v_gid; end if;   -- coalesce: 칸이 없으면 jsonb_typeof 가 null 이라 if 가 조용히 지나간다(1회차 T8)
  v_fl := p_order->'shippingLines'->'nodes'->0;
  select * into v_dlv from public.shop_order_delivery(p_order);                                                                              -- ful-1b: SHIPPING · PICK_UP · MIXED · 픽업 위치

  select * into v_o from public.shop_order o where o.shopify_order_gid = v_gid for update;
  if v_o.id is null then
    insert into public.shop_order (store_id, shopify_order_gid, name, shopify_created_at, shopify_updated_at, shopify_cancelled_at, is_test, financial_status, source_name, email, shopify_customer_gid,
                                   ship_province_code, ship_country_code, currency_code, subtotal, total_discounts, total_shipping, total_tax, total, freight_amount, freight_title, raw, status, delivery_method, pickup_location_gid)
    values (v_s.id, v_gid, p_order->>'name', nullif(p_order->>'createdAt', '')::timestamptz, nullif(p_order->>'updatedAt', '')::timestamptz, v_cancel, coalesce((p_order->>'test')::boolean, false),
            p_order->>'displayFinancialStatus', p_order->>'sourceName', nullif(lower(trim(coalesce(p_order->>'email', p_order->'customer'->'defaultEmailAddress'->>'emailAddress'))), ''), nullif(p_order->'customer'->>'id', ''),
            nullif(upper(trim(v_ship->>'provinceCode')), ''), nullif(upper(trim(v_ship->>'countryCodeV2')), ''), p_order->>'currencyCode',
            (p_order->'subtotalPriceSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalDiscountsSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalShippingPriceSet'->'shopMoney'->>'amount')::numeric,
            (p_order->'totalTaxSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalPriceSet'->'shopMoney'->>'amount')::numeric,
            (v_fl->'discountedPriceSet'->'shopMoney'->>'amount')::numeric, v_fl->>'title', p_order, 'received', v_dlv.method, v_dlv.location_gid)
    returning * into v_o;
    v_action := 'inserted';
  else
    if v_o.status in ('received', 'needs_review') then
      update public.shop_order set name = p_order->>'name', shopify_created_at = nullif(p_order->>'createdAt', '')::timestamptz, shopify_updated_at = nullif(p_order->>'updatedAt', '')::timestamptz, shopify_cancelled_at = v_cancel,
             is_test = coalesce((p_order->>'test')::boolean, false), financial_status = p_order->>'displayFinancialStatus', source_name = p_order->>'sourceName',
             email = nullif(lower(trim(coalesce(p_order->>'email', p_order->'customer'->'defaultEmailAddress'->>'emailAddress'))), ''), shopify_customer_gid = nullif(p_order->'customer'->>'id', ''),
             ship_province_code = nullif(upper(trim(v_ship->>'provinceCode')), ''), ship_country_code = nullif(upper(trim(v_ship->>'countryCodeV2')), ''), currency_code = p_order->>'currencyCode',
             subtotal = (p_order->'subtotalPriceSet'->'shopMoney'->>'amount')::numeric, total_discounts = (p_order->'totalDiscountsSet'->'shopMoney'->>'amount')::numeric, total_shipping = (p_order->'totalShippingPriceSet'->'shopMoney'->>'amount')::numeric,
             total_tax = (p_order->'totalTaxSet'->'shopMoney'->>'amount')::numeric, total = (p_order->'totalPriceSet'->'shopMoney'->>'amount')::numeric,
             freight_amount = (v_fl->'discountedPriceSet'->'shopMoney'->>'amount')::numeric, freight_title = v_fl->>'title', raw = p_order, status = 'received', reasons = '[]'::jsonb, error = null,
             delivery_method = v_dlv.method, pickup_location_gid = v_dlv.location_gid
       where id = v_o.id returning * into v_o;
      delete from public.shop_order_line where shop_order_id = v_o.id;                                                                          -- 줄은 다시 푼다(SO 가 없으니 자유)
      v_action := 'updated';
    else                                                                                                                                       -- created · cancelled · error: 원문만 갱신 · SO · 줄 무접촉(판정 372)
      v_warn := jsonb_build_object('code', case when v_o.status = 'created' then 'updated_after_so' else 'updated_after_' || v_o.status end, 'at', now(),
                                   'message', format('Shopify order %s changed after IMS %s it (Shopify updatedAt %s) — check the Shopify order and the IMS order by hand', p_order->>'name', v_o.status, p_order->>'updatedAt'));
      v_action := 'updated_after_' || v_o.status;                                                                                            -- ord-1b2: 받기 전 상태로(취소가 상태를 바꿔도 action 은 그대로)
      v_newcan := v_cancel is not null and v_o.shopify_cancelled_at is null;
      v_moved  := nullif(p_order->>'updatedAt', '')::timestamptz is distinct from v_o.shopify_updated_at;
      -- ful-1b 판정 447: 메아리 — ⓐ 새로 보인 fulfillment GID(이전 raw 에 없던 것)가 모두 우리 결과 표(shop_fulfillment)에 있다 · ⓑ updatedAt 이 우리 마지막 Shopify 쓰기(last_push_at) 뒤 2 분 안(앞 5 초 여유) → updated_after_so 를 안 붙인다
      --   모르는 GID → fulfilled_in_shopify · 새 환불 GID → refunded_in_shopify(원문은 raw 가 그대로 담는다 · 판정 440) · 구체 경고가 있으면 일반 경고(updated_after_so)는 안 붙인다 · 배포 뒤 첫 재읽기는 이전 raw 에 목록이 없어 전부 「새것」(우리 것은 걸러지고 모르는 것은 한 번만)
      select coalesce(array_agg(f->>'id'), '{}') into v_oldf from jsonb_array_elements(coalesce(v_o.raw->'fulfillments', '[]'::jsonb)) f;
      select coalesce(array_agg(f->>'id'), '{}') into v_newf from jsonb_array_elements(coalesce(p_order->'fulfillments', '[]'::jsonb)) f where not (f->>'id' = any(v_oldf));
      select coalesce(array_agg(g), '{}') into v_unk from unnest(v_newf) g where not exists (select 1 from public.shop_fulfillment sf where sf.shop_order_id = v_o.id and sf.shopify_fulfillment_gid = g);
      select coalesce(array_agg(f->>'id'), '{}') into v_oldr from jsonb_array_elements(coalesce(v_o.raw->'refunds', '[]'::jsonb)) f;
      select greatest(max(sf.last_push_at), v_o.last_push_at) into v_push from public.shop_fulfillment sf where sf.shop_order_id = v_o.id;   -- ful-4a: 오더 고치기(shop_order.last_push_at)도 메아리 ⓑ
      v_echo := (coalesce(array_length(v_newf, 1), 0) > 0 and coalesce(array_length(v_unk, 1), 0) = 0)
             or (v_push is not null and nullif(p_order->>'updatedAt', '')::timestamptz between v_push - interval '5 seconds' and v_push + interval '2 minutes');
      if coalesce(array_length(v_unk, 1), 0) > 0 then
        v_spec := v_spec || jsonb_build_object('code', 'fulfilled_in_shopify', 'at', now(), 'gids', to_jsonb(v_unk),
                                               'message', format('Shopify order %s was fulfilled in Shopify, not by IMS (%s fulfillment(s): %s) — the IMS order was not touched; check it by hand', p_order->>'name', array_length(v_unk, 1), array_to_string(v_unk, ', ')));
      end if;
      for r in select f from jsonb_array_elements(coalesce(p_order->'refunds', '[]'::jsonb)) f where not (f->>'id' = any(v_oldr)) loop
        v_spec := v_spec || jsonb_build_object('code', 'refunded_in_shopify', 'at', now(), 'refund_gid', r->>'id', 'amount', (r->'totalRefundedSet'->'shopMoney'->>'amount')::numeric, 'note', nullif(trim(coalesce(r->>'note', '')), ''),
                                               'message', format('Shopify order %s was refunded in Shopify (%s %s · %s) — make the credit note in IMS by hand if stock came back (judge restocking there)', p_order->>'name', r->'totalRefundedSet'->'shopMoney'->>'amount', coalesce(r->'totalRefundedSet'->'shopMoney'->>'currencyCode', ''), coalesce(nullif(trim(coalesce(r->>'note', '')), ''), 'no note')));
      end loop;
      update public.shop_order set shopify_updated_at = nullif(p_order->>'updatedAt', '')::timestamptz, shopify_cancelled_at = v_cancel, financial_status = p_order->>'displayFinancialStatus', raw = p_order,
             delivery_method = v_dlv.method, pickup_location_gid = v_dlv.location_gid
       where id = v_o.id;                                                                                                                    -- ord-1b2: 원문 · 취소 시각 먼저(shop_order_cancelled 가 읽는다) · 경고는 취소 판정 뒤에
      if v_newcan and v_o.status in ('created', 'error') and not exists (select 1 from jsonb_array_elements(v_o.warnings) w where w->>'code' in ('auto_cancelled', 'cancel_needs_review', 'cancel_failed')) then
        v_cres := public.shop_order_cancelled(v_o.id);                                                                                       -- ord-1a2 판정 434: SO 가 있는 오더의 취소 — 한 번만 · ord-1b2: error(SO 없음)도 닫는다(closed_before_so)
      end if;
      v_auto := coalesce(v_cres->>'action', '') in ('auto_cancelled', 'closed_before_so');
      update public.shop_order set
             warnings = warnings || (case when v_moved and not v_auto and not v_echo and jsonb_array_length(v_spec) = 0 then jsonb_build_array(v_warn) else '[]'::jsonb end)   -- ord-1b2: 자동 취소로 끝난 받기는 「손으로 확인」 경고(updated_after_so · cancelled_in_shopify)를 남기지 않는다 · ful-1b: 메아리 · 구체 경고가 있으면 안 붙인다
                                 || (case when not v_auto then v_spec else '[]'::jsonb end)                                                 -- ful-1b 판정 447 · 440: fulfilled_in_shopify · refunded_in_shopify
                                 || (case when v_newcan and not v_auto
                                          then jsonb_build_array(jsonb_build_object('code', 'cancelled_in_shopify', 'at', now(), 'message', format('Shopify order %s was cancelled in Shopify (%s) but the IMS order was not cancelled automatically — check it by hand (see cancel_needs_review / cancel_failed)', p_order->>'name', v_cancel)))
                                          else '[]'::jsonb end)
       where id = v_o.id returning * into v_o;
    end if;
  end if;

  if v_action in ('inserted', 'updated') then
    for v_li in select x from jsonb_array_elements(p_order->'lineItems'->'nodes') as x loop
      v_i := v_i + 1;
      if coalesce((v_li->>'quantity')::numeric, 0) <= 0 then continue; end if;
      insert into public.shop_order_line (shop_order_id, line_gid, line_no, sku, name, quantity, list_price, discount_amount, unit_price)
      values (v_o.id, coalesce(nullif(v_li->>'id', ''), 'line-' || v_i), v_i, nullif(trim(coalesce(v_li->>'sku', v_li->'variant'->>'sku')), ''), v_li->>'name', (v_li->>'quantity')::numeric,
              (v_li->'originalUnitPriceSet'->'shopMoney'->>'amount')::numeric, (v_li->'totalDiscountSet'->'shopMoney'->>'amount')::numeric, (v_li->'discountedUnitPriceAfterAllDiscountsSet'->'shopMoney'->>'amount')::numeric);
      v_n := v_n + 1;
    end loop;
    v_prep := public.shop_order_prepare(v_o.id);
    if v_cancel is not null then perform public.shop_order_cancelled(v_o.id); end if;                                   -- ord-1a2 판정 434: SO 가 생기기 전에 취소됐으면 그냥 cancelled
    select * into v_o from public.shop_order o where o.id = v_o.id;
  end if;

  return jsonb_build_object('shop_order_id', v_o.id, 'action', v_action, 'status', v_o.status, 'name', v_o.name, 'lines', v_n,
                            'customer_id', v_o.customer_id, 'location_id', v_o.location_id, 'reasons', v_o.reasons, 'warnings', v_o.warnings, 'prepare', v_prep, 'cancel', v_cres,   -- ord-1b2: cancel = 이번 받기의 shop_order_cancelled 결과(없으면 null)
                            'echo', v_echo, 'new_fulfillments', to_jsonb(v_newf), 'unknown_fulfillments', to_jsonb(v_unk), 'delivery_method', v_dlv.method);                    -- ful-1b
end;
$$;
revoke all on function public.shop_order_ingest(uuid, jsonb) from public, anon, authenticated;
do $$ begin
  execute format('comment on function public.shop_order_ingest(uuid, jsonb) is %L', coalesce(obj_description('public.shop_order_ingest(uuid, jsonb)'::regprocedure, 'pg_proc'), '') || ' · ⭐ ful-4a: 메아리 ⓑ 는 shop_fulfillment.last_push_at 과 shop_order.last_push_at(오더 고치기 · 449) 중 늦은 것으로');
end $$;
