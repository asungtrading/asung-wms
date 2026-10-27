-- shop-live-1 — 실제 스토어 「연결됐지만 잠든」 통로: shop_store.live · auth_mode · 창구 store_live · 일하는 SQL 길 전부 is_active and live (2026-10-27 · 판정 809 · 811 ~ 816 · 조사 shop-real-0 · 지시서 ~/asung/prompts/shop-live-1.md)
--   왜: is_active 하나가 읽기 · 쓰기를 함께 켜고 껐다(shop-real-0 이견 1) — 꺼진 스토어는 ping · 잇기도 막히고, 켜진 스토어는 15 분 안에 실제 오더를 SO 로 받고(cron 48 · 47) 실제 오더에 orderEdit(51) · markAsPaid(53) 까지 간다 · 컷오버(2026-11-01) 전에 실제 두 스토어(asung.ca · aonebeauty.com)를 「읽기만」 으로 붙여 두려면 두 번째 상태가 필요하다
--   뜻(판정 811): is_active = 「연결 살아 있음 · 들여다보기만」(ping · link_read · link_poll · link_plan · link_apply · order_read · webhooks_list) · live = 「일한다」(상품 · 재고 · 오더 · 발송 · 결제 쓰기 · 웹훅 받기 · 주기 확인) — 일하는 길은 전부 is_active and live
--   새 스토어는 live false 로 들어오고(store_set) · 켜기는 관리자의 store_live {code, live true, orders_from}(판정 814: orders_from = Cin7 의 Shopify 연결을 끊은 컷 시각 → orders_polled_at · 그 전 오더는 Cin7 적재로) · 켜는 순간 그 스토어 재고 전부 force(판정 815 · shop_stock_queue_all(store)) · 시험 스토어는 live true 로 시작(지금 동작 그대로)
--   auth_mode(판정 813): client_credentials(조직 안 스토어 · 지금 그대로) | stored_token(조직 밖 aonebeauty.com · 판정 809 · 812 — 전용 앱 · secret_prefix SHOPIFY_AONE · EF 가 <PREFIX>_ACCESS_TOKEN 을 읽기만 · 없으면 사람 말로 멈춤) — 열쇠 값은 표에 없다(EF 비밀)
--   shop_stock_targets 는 live 전 스토어의 변형을 대상에서 뺀다(큐 0 · 대기 줄이 쌓이지 않는다 — 켜는 순간 store_live 가 전부 force 하므로 결과는 같다 · Claude Code 판단) · 상품 큐(shop_queue_add · 트리거 · listing_on)는 그대로 쌓이고 EF drain 이 live 전엔 열어 둔다(판정 815 · EF 쪽)
--   shop_link_apply 는 무접촉(is_active 만 · 판정 815 — live 전에도 잇는다 · 보냄 켜기 · hash 심기 그대로 · 재고 트리거는 targets 가 0 을 돌려 줄 0) · shop_link_push_batch 는 commit 만 live 필요(미리 보기는 된다)
--   거래 표에 새 FK 없음(컷오버 날 지우는 순서 무관) · 뷰 shop_store_list 끝에 live · auth_mode
--   전수(shop-real-0 1 절 + grep): 바꿈 = shop_stock_targets · shop_queue_all · shop_stock_queue_all · shop_stock_queue_diff · shop_unshipped_scan · shop_paid_scan(2 곳) · shop_link_push_batch · shop_store_save / 그대로(읽기 길 · 또는 EF 가 앞에서 가른다) = shop_link_apply · shop_link_plan · shop_listing_set(is_active 막기 · 큐는 대기) · shop_order_ingest(is_active raise · EF 가 live 를 앞에서) · shop_order_process · so_charge_gate · drive_target_invoice(kind 만 읽음)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20261027190714_shop_live_1.sql && supabase migration repair --status applied 20261027190714 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027190714_shop_live_1.sql -f supabase/tests/shop_live_1.sql
do $$
begin
  if coalesce((select value from public.inv_config where key = 'db_role'), '') <> 'test' then
    raise exception using errcode = 'WM501', message = 'STOP - inv_config.db_role is not test - this migration runs on the Asung-IMS project only. Nothing was changed.';
  end if;
end $$;

-- ═══ 1) 칸 둘 — live(기본 false) · auth_mode(기본 client_credentials) ═══
alter table public.shop_store add column if not exists live boolean not null default false;
alter table public.shop_store add column if not exists auth_mode text not null default 'client_credentials';
alter table public.shop_store drop constraint if exists shop_store_auth_mode_ck;
alter table public.shop_store add constraint shop_store_auth_mode_ck check (auth_mode in ('client_credentials', 'stored_token'));
comment on column public.shop_store.live is 'shop-live-1 판정 811: 일하는 길 스위치 — 상품 · 재고 · 오더 · 발송 · 결제 쓰기 · 웹훅 받기 · 주기 확인은 is_active and live 일 때만 · false = 연결은 살아 있고(ping · 잇기 읽기 · 판정 · 적용) 쓰지 않는다 · 새 스토어 false · 켜기 · 끄기는 shop_store_save op store_live(admin) · 켤 때 orders_polled_at = orders_from(판정 814) + 재고 전부 force(판정 815)';
comment on column public.shop_store.auth_mode is 'shop-live-1 판정 813: EF 열쇠 방식 — client_credentials(조직 안 스토어 · 토큰 24 h · <PREFIX>_CLIENT_ID · _CLIENT_SECRET) | stored_token(조직 밖 스토어 · 판정 809 · 설치 때 한 번 바꾼 영구 토큰 <PREFIX>_ACCESS_TOKEN 을 EF 가 읽기만 · 401 에 다시 받지 않는다) · 값은 전부 EF 비밀(표에 없다)';
-- 시험 스토어는 live true(지금 동작 보존) — 트리거 shop_store_shop_queue_u 는 oos_policy · send_tags · 두 tier 만 보므로 이 update 로 큐가 차지 않는다(시험 파일 ① 이 증명)
update public.shop_store set live = true where code = 'test';

-- ═══ 2) 일하는 SQL 길 — is_active and live ═══
create or replace function public.shop_stock_targets(p_store_id uuid, p_product_ids uuid[] default null)
  returns table (store_id uuid, product_id uuid)
  language sql stable
  set search_path = public, pg_temp
as $$
  select l.store_id, p.id
    from public.shop_listing l
    join public.shop_store s on s.id = l.store_id and s.is_active and s.live        -- shop-live-1 판정 811 · 815: live 전 스토어의 변형은 대상이 아니다(큐 0 · 켜는 순간 store_live 가 전부 force)
    join public.product p on (l.product_id = p.id) or (l.family_id is not null and p.family_id = l.family_id and p.parent_product_id is null)
   where l.is_on
     and (p_store_id is null or l.store_id = p_store_id)
     and (p_product_ids is null or p.id = any(p_product_ids));

$$;
comment on function public.shop_stock_targets(uuid, uuid[]) is 'stock-1a: 재고를 보낼 변형 한 곳 — 켜진 listing(스토어 하나 또는 전부)의 변형 = 낱개 listing 의 상품 · family listing 의 낱개 구성원 · sellable 세트 listing 의 세트 · p_product_ids 로 좁힌다(null = 전부) · 판정 425 꺼진 listing 의 변형은 안 낸다 · ⭐ shop-live-1 판정 811 · 815: 스토어가 is_active and live 일 때만(live 전 스토어는 큐 0 · 켜는 순간 store_live 가 전부 force)';

create or replace function public.shop_queue_all(p_store_id uuid default null) returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_fids uuid[] := '{}'; v_pids uuid[] := '{}'; v_n int := 0; v_l record;
begin
  for v_l in
    select l.store_id, l.family_id, l.product_id
      from public.shop_listing l join public.shop_store s on s.id = l.store_id and s.is_active and s.live   -- shop-live-1 판정 811
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
comment on function public.shop_queue_all(uuid) is 'shop-2a2 설계 §3-e 새벽 전체 맞추기 · stock-1a 재발행(판정 424 ①): 켜진 listing(스토어 하나 또는 전부)마다 shop_product_payload 의 hash 를 shop_product.last_hash 와 대조해 다른 대상만 큐에(reason nightly) · 같은 대상은 줄 0 · 열린 줄이 있으면 건너뜀 · ⭐ shop-live-1 판정 811: is_active and live 스토어만 · 실행권 service_role · cron jobid 43';

create or replace function public.shop_stock_queue_all(p_store_id uuid default null) returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_pids uuid[]; v_n int := 0; v_s record;
begin
  for v_s in select s.id from public.shop_store s where s.is_active and s.live and (p_store_id is null or s.id = p_store_id) loop
    select coalesce(array_agg(distinct t.product_id), '{}') into v_pids from public.shop_stock_targets(v_s.id, null) t;
    v_n := v_n + public.shop_stock_queue_add(v_s.id, v_pids, 'nightly', true);
  end loop;
  return v_n;
end;

$$;
comment on function public.shop_stock_queue_all(uuid) is 'stock-1a 판정 423 새벽: 켜진 변형 전부를 force 로 큐에(reason nightly · Shopify 쪽 어긋남을 IMS 값으로 덮는 안전망) · 열린 줄이 있으면 force 만 올린다 · ⭐ shop-live-1 판정 811 · 815: is_active and live 스토어만 · store_live 켜기가 그 스토어 하나로 부른다 · cron jobid 46';

create or replace function public.shop_stock_queue_diff(p_store_id uuid default null) returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_pids uuid[]; v_n int := 0; v_s record;
begin
  for v_s in select s.id from public.shop_store s where s.is_active and s.live and (p_store_id is null or s.id = p_store_id) loop
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
comment on function public.shop_stock_queue_diff(uuid) is 'stock-1a 판정 423 낮: 켜진 변형 전부의 지금 가용(shop_stock_payload)을 마지막으로 보낸 숫자(shop_stock_sent)와 대조해 다른 변형만 큐에(reason diff) · ⭐ shop-live-1 판정 811: is_active and live 스토어만 · cron jobid 45';

create or replace function public.shop_unshipped_scan(p_limit int default 200) returns jsonb
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
       and exists (select 1 from public.shop_store st where st.id = so.store_id and st.is_active and st.live)   -- shop-live-1 판정 811
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
comment on function public.shop_unshipped_scan(int) is 'ful-4a 판정 457 ~ 462: 15 분 cron(ims-unshipped-scan · jobid 50 · postgres) — created 웹 오더마다 Shopify 줄의 「나가지 않을 몫」 gap = quantity − sent − removed_qty − can_ship 을 장부에 다시 세고 · 돈 받음이면 경고 refund_due(커질 때만) · 아니면 큐 order_edit · 되살아난 몫은 경고 shopify_qty_removed 한 번 · 취소된 Shopify 오더 · 꺼진 스토어는 건너뜀 · ⭐ shop-live-1 판정 811: is_active and live 스토어만 · 반환 {scanned, queued, warned_refund_due, warned_restored, nothing}';

create or replace function public.shop_paid_scan(p_limit int default 200, p_store_id uuid default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  o        record;
  q        record;
  v_st     jsonb;
  v_pay    jsonb;
  v_rem    numeric;
  v_owed   numeric;
  v_n      int := 0;  v_queued int := 0;  v_warned int := 0;  v_nothing int := 0;
begin
  -- 대상: created · so 있음 · Shopify 취소 아님 · 켜진 스토어 · Shopify 결제 상태가 아직 Paid 가 아닌 것(PENDING · PARTIALLY_PAID · EXPIRED · 없음)
  for o in
    select so.id, so.name, so.financial_status
      from public.shop_order so
     where so.status = 'created' and so.so_id is not null and so.shopify_cancelled_at is null
       and (p_store_id is null or so.store_id = p_store_id)
       and exists (select 1 from public.shop_store st where st.id = so.store_id and st.is_active and st.live)   -- shop-live-1 판정 811
       and upper(coalesce(so.financial_status, '')) in ('PENDING', 'PARTIALLY_PAID', 'EXPIRED', '')
     order by so.received_at
     limit p_limit
  loop
    v_n := v_n + 1;
    v_st := public.shop_order_paid_state(o.id);
    if not (v_st->>'ready')::boolean then v_nothing := v_nothing + 1; continue; end if;
    v_pay := jsonb_build_object('remaining_total', 0, 'family', v_st->'family', 'invoices', v_st->'invoices', 'scanned_at', now());
    select * into q from public.shop_order_queue x where x.shop_order_id = o.id and x.kind = 'mark_paid';
    if q.id is null then
      perform public.shop_order_requeue(o.id, 'mark_paid', v_pay);
      v_queued := v_queued + 1;
    elsif q.done_at is not null and q.result <> 'ok' and (q.payload->'family' is distinct from v_st->'family' or q.payload->'invoices' is distinct from v_st->'invoices') then
      perform public.shop_order_requeue(o.id, 'mark_paid', v_pay);                                                                             -- 실패 · 건너뜀으로 닫힌 행 — 뭉치나 인보이스가 달라졌을 때만 다시 연다(같은 payload 는 안 연다 · 5 회는 EF 가 닫는다)
      v_queued := v_queued + 1;
    end if;                                                                                                                                      -- done ok 는 다시 안 연다 · 열린 행은 그대로(EF 가 집는다)
  end loop;

  -- 되돌아온 미수(따로): Shopify PAID · IMS 가 Paid 로 바꾼 오더(paid_push_at) · 지금 남은 돈 > 0 → 경고(원소 owed · 커질 때만 · 판정 461 모양) — 직원이 Shopify 에서 표시한 것(paid_push_at null)은 468 의 몫
  for o in
    select so.id, so.name, so.paid_push_at
      from public.shop_order so
     where so.status = 'created' and so.so_id is not null and so.shopify_cancelled_at is null
       and (p_store_id is null or so.store_id = p_store_id)
       and exists (select 1 from public.shop_store st where st.id = so.store_id and st.is_active and st.live)   -- shop-live-1 판정 811
       and upper(coalesce(so.financial_status, '')) = 'PAID' and so.paid_push_at is not null
     order by so.received_at
     limit p_limit
  loop
    v_st := public.shop_order_paid_state(o.id);
    v_rem := coalesce((v_st->>'remaining_total')::numeric, 0);
    if v_rem <= 0 then continue; end if;
    select coalesce(max((w->>'owed')::numeric), 0) into v_owed from public.shop_order x, jsonb_array_elements(x.warnings) w where x.id = o.id and w->>'code' = 'shopify_paid_ims_owed';
    if v_rem > v_owed then
      perform public.shop_order_warn(o.id, 'shopify_paid_ims_owed',
                                     format('Shopify order %s shows Paid (IMS marked it on %s), but IMS has %s owed again — Shopify cannot be set back to unpaid; tell the customer if needed',
                                            o.name, to_char(o.paid_push_at at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI'), v_rem));
      update public.shop_order x set warnings = jsonb_set(x.warnings, array[(jsonb_array_length(x.warnings) - 1)::text], (x.warnings->-1) || jsonb_build_object('owed', v_rem, 'paid_push_at', o.paid_push_at))
       where x.id = o.id;                                                                                                                      -- 방금 더한 마지막 원소에 owed 를 붙인다(다음 스캔의 「커질 때만」 기준)
      v_warned := v_warned + 1;
    end if;
  end loop;
  return jsonb_build_object('scanned', v_n, 'queued', v_queued, 'warned_owed_again', v_warned, 'nothing', v_nothing, 'at', now());
end;

$$;
comment on function public.shop_paid_scan(int, uuid) is 'pay-2a 판정 449 · 469: cron 용 스캔(ims-paid-scan · jobid 52 · postgres) — created · so 있음 · Shopify 취소 아님 · Shopify 결제 상태 PENDING · PARTIALLY_PAID · EXPIRED · 없음인 오더마다 shop_order_paid_state 가 ready 면 shop_order_requeue(mark_paid) · 따로: Shopify PAID 이고 paid_push_at 있는 오더의 남은 돈이 0 을 넘으면 경고 shopify_paid_ims_owed · ⭐ shop-live-1 판정 811: is_active and live 스토어만(두 고리 다) · p_store_id 는 시험용 좁히기 · 반환 {scanned, queued, warned_owed_again, nothing, at}';

create or replace function public.shop_link_push_batch(p_store_id uuid, p_filter jsonb default '{}'::jsonb, p_commit boolean default false, p_limit int default 200) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_s      public.shop_store%rowtype;
  v_brands uuid[];  v_cats uuid[];  v_tags text[];  v_like text;  v_kind text;
  v_fids   uuid[] := '{}';  v_pids uuid[] := '{}';
  v_items  jsonb;
  v_n      int := 0;  v_queued int := 0;  v_total int;
begin
  perform public.ims_require_write('shopify', 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_s from public.shop_store where id = p_store_id;
  if v_s.id is null then raise exception 'Store % not found — nothing was saved', p_store_id; end if;
  if p_commit and not (v_s.is_active and v_s.live) then raise exception 'Store "%" is not live — only a live store sends products to Shopify (Settings → Shopify Stores → Go live) — nothing was queued', v_s.code; end if;   -- shop-live-1 판정 811 · 815(미리 보기는 된다)
  if p_limit is null or p_limit < 1 or p_limit > 200 then raise exception 'p_limit must be 1 ~ 200 (the drain sends 20 a minute) — nothing was saved'; end if;
  if p_filter is not null and jsonb_typeof(p_filter) <> 'object' then raise exception 'p_filter must be a JSON object — nothing was saved'; end if;
  select array_agg((e)::uuid) into v_brands from jsonb_array_elements_text(coalesce(p_filter->'brand_id', '[]'::jsonb)) e;
  select array_agg((e)::uuid) into v_cats   from jsonb_array_elements_text(coalesce(p_filter->'category_id', '[]'::jsonb)) e;
  select array_agg(e) into v_tags           from jsonb_array_elements_text(coalesce(p_filter->'tag', '[]'::jsonb)) e;
  v_like := nullif(trim(coalesce(p_filter->>'sku_like', '')), '');
  v_kind := nullif(trim(coalesce(p_filter->>'kind', '')), '');
  if v_kind is not null and v_kind not in ('family', 'product') then raise exception 'p_filter.kind must be family or product — nothing was saved'; end if;

  create temp table if not exists t_link_push (family_id uuid, product_id uuid, kind text, sku text, name text, brand_id uuid, brand_name text, gid text) on commit drop;
  truncate t_link_push;
  insert into t_link_push
  select sp.family_id, sp.product_id, case when sp.family_id is not null then 'family' else 'product' end,
         coalesce(f.sku, p.sku), coalesce(f.name, p.name), coalesce(f.brand_id, p.brand_id), coalesce(f.brand_name, p.brand_name), sp.shopify_product_gid
    from public.shop_product sp
    join public.shop_listing l on l.store_id = sp.store_id and l.family_id is not distinct from sp.family_id and l.product_id is not distinct from sp.product_id and l.is_on
    left join public.product_family f on f.id = sp.family_id
    left join public.product p on p.id = sp.product_id
   where sp.store_id = p_store_id and sp.last_pushed_at is null and sp.shopify_product_gid <> 'gid://shopify/Product/0'
     and (v_kind is null or (v_kind = 'family') = (sp.family_id is not null))
     and (v_brands is null or coalesce(f.brand_id, p.brand_id) = any(v_brands))
     and (v_cats is null or coalesce(f.category_id, p.category_id) = any(v_cats))
     and (v_like is null or coalesce(f.sku, p.sku) ilike v_like)
     and (v_tags is null or exists (select 1 from public.product_tag t join public.product x on x.id = t.product_id
                                     where t.tag = any(v_tags) and (x.id = sp.product_id or (sp.family_id is not null and x.family_id = sp.family_id))))
   order by coalesce(f.sku, p.sku)
   limit p_limit;
  select count(*) into v_n from t_link_push;
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'sku', sku, 'name', name, 'brand_name', brand_name, 'gid', gid) order by sku), '[]'::jsonb) into v_items from t_link_push;
  select count(*) into v_total from public.shop_product sp join public.shop_listing l on l.store_id = sp.store_id and l.family_id is not distinct from sp.family_id and l.product_id is not distinct from sp.product_id and l.is_on
   where sp.store_id = p_store_id and sp.last_pushed_at is null and sp.shopify_product_gid <> 'gid://shopify/Product/0';

  if p_commit and v_n > 0 then
    select coalesce(array_agg(family_id), '{}') into v_fids from t_link_push where family_id is not null;
    select coalesce(array_agg(product_id), '{}') into v_pids from t_link_push where product_id is not null;
    update public.shop_product sp set last_hash = null, last_status = 'pending', updated_by = v_staff
     where sp.store_id = p_store_id and ((sp.family_id is not null and sp.family_id = any(v_fids)) or (sp.product_id is not null and sp.product_id = any(v_pids)));
    v_queued := public.shop_queue_add(v_fids, v_pids, 'link_push', p_store_id);                       -- 한 곳 · 열린 줄이 있으면 건너뛴다
  end if;
  return jsonb_build_object('committed', p_commit, 'store_code', v_s.code, 'picked', v_n, 'queued', v_queued, 'remaining_before', v_total,
                            'remaining_after', case when p_commit then v_total - v_n else v_total end, 'limit', p_limit, 'items', v_items);
end;

$$;
comment on function public.shop_link_push_batch(uuid, jsonb, boolean, integer) is 'link-1a(판정 555 · 564) — 이었지만 아직 안 보낸 상품(gid 있음 · last_pushed_at null · Product/0 제외)을 거르기(brand_id[] · category_id[] · tag[] · sku_like · kind)로 골라 p_limit(1 ~ 200)개를 상품 큐에(last_hash 를 비우고 shop_queue_add reason link_push) · p_commit false 는 미리 보기 · 반환 {picked, queued, remaining_before, remaining_after, items} · ⭐ shop-live-1 판정 811 · 815: commit 은 is_active and live 스토어만(미리 보기는 live 전에도) · 문 ims_require_write(shopify)';

-- ═══ 3) 창구 shop_store_save 재발행 — store_set(auth_mode · 새 행 live false · 있는 행 live 무접촉) · store_off(live 도 끔) · 새 op store_live ═══
create or replace function public.shop_store_save(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_n        int;
  v_i        int := 0;
  v_c        jsonb;
  v_op       text;
  v_code     text;
  v_key      text;
  v_gid      text;
  v_seen     text[] := '{}';
  v_keys     text[] := '{}';
  v_unacked  text[] := '{}';
  v_s        public.shop_store%rowtype;
  v_l        public.shop_location%rowtype;
  v_sale     public.ref_price_tier%rowtype;
  v_cmp      public.ref_price_tier%rowtype;
  v_wh       public.ref_warehouse%rowtype;
  v_old      jsonb;
  v_cur      jsonb;
  v_prefix   text;
  v_cnt      bigint;
  v_from     timestamptz;
  v_mode     text;
  v_nq       int;
  c_ops      constant text[] := array['store_set', 'store_off', 'store_live', 'location_set', 'location_off'];
begin
  perform public.ims_require_admin('Shopify stores');                                             -- ⭐ 유일한 문 — 첫 줄(shop-0 이견 5)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;

  -- ① 모양
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    raise exception 'p_changes must be a JSON array of changes — nothing was saved';
  end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then raise exception 'No changes given — nothing was saved'; end if;
  if v_n > 200 then raise exception 'Too many changes in one call (% — the limit is 200) — nothing was saved', v_n; end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    if not (coalesce(v_c->>'op', '') = any(c_ops)) then
      raise exception 'Unknown op "%" — store_set, store_off, store_live, location_set or location_off — nothing was saved', coalesce(v_c->>'op', '(none)');
    end if;
  end loop;

  -- ② 줄마다 막기 · 알리기 — 전부 모은다
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_s := null; v_l := null; v_sale := null; v_cmp := null; v_wh := null;
    v_code := lower(trim(coalesce(v_c->>(case when v_op like 'store_%' then 'code' else 'store_code' end), '')));
    v_key := case when v_code = '' then '(blank)' else v_code end;
    v_changes := v_changes || jsonb_build_object('i', v_i, 'op', v_op, 'code', v_code, 'applied', false);
    if v_code !~ '^[a-z0-9_]{1,20}$' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':code_invalid', 'code', 'code_invalid', 'message', format('Store code "%s" must be 1-20 lowercase letters, digits or _ — nothing was saved', v_code));
      continue;
    end if;
    select * into v_s from public.shop_store s where s.code = v_code;

    if v_op = 'store_set' then
      if (v_code || '|store') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Store %s appears twice in this call — nothing was saved', v_code));
        continue;
      end if;
      v_seen := v_seen || (v_code || '|store');
      -- old: 새 스토어는 null · 있는 스토어는 화면이 본 여섯 칸
      if v_s.id is not null then
        if coalesce(jsonb_typeof(v_c->'old'), 'none') <> 'object' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('Store %s exists — the old values the screen saw are missing — nothing was saved', v_code));
          continue;
        end if;
        v_old := v_c->'old';
        v_cur := jsonb_build_object('shop_domain', v_s.shop_domain, 'label', v_s.label, 'kind', v_s.kind,
                                    'sale_tier', (select t.name from public.ref_price_tier t where t.id = v_s.sale_tier_id),
                                    'compare_tier', (select t.name from public.ref_price_tier t where t.id = v_s.compare_tier_id),
                                    'secret_prefix', v_s.secret_prefix, 'oos_policy', v_s.oos_policy, 'auth_mode', v_s.auth_mode);
        if (v_cur->>'shop_domain') is distinct from nullif(v_old->>'shop_domain', '') or (v_cur->>'label') is distinct from nullif(v_old->>'label', '') or (v_cur->>'kind') is distinct from nullif(v_old->>'kind', '')
           or (v_cur->>'sale_tier') is distinct from nullif(v_old->>'sale_tier', '') or (v_cur->>'compare_tier') is distinct from nullif(v_old->>'compare_tier', '') or (v_cur->>'secret_prefix') is distinct from nullif(v_old->>'secret_prefix', '')
           or ((v_old ? 'oos_policy') and (v_cur->>'oos_policy') is distinct from nullif(v_old->>'oos_policy', ''))   -- shop-pol: old 에 oos_policy 가 있을 때만 대조(옛 화면 ss v1a 는 여섯 칸만 보낸다)
           or ((v_old ? 'auth_mode') and (v_cur->>'auth_mode') is distinct from nullif(v_old->>'auth_mode', '')) then   -- shop-live-1: auth_mode 도 old 에 있을 때만(ss v3a 는 안 보낸다)
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Someone just changed store %s — check again — nothing was saved', v_code));
          continue;
        end if;
      elsif coalesce(jsonb_typeof(v_c->'old'), 'null') <> 'null' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_unknown', 'code', 'store_unknown', 'message', format('Store %s does not exist — to create it send old as null — nothing was saved', v_code));
        continue;
      end if;
      -- 칸 검사
      if coalesce(v_c->>'shop_domain', '') !~ '^[a-z0-9][a-z0-9-]*\.myshopify\.com$' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':domain_invalid', 'code', 'domain_invalid', 'message', format('Store %s: the domain must look like name.myshopify.com (lowercase) — nothing was saved', v_code));
      elsif exists (select 1 from public.shop_store x where x.shop_domain = v_c->>'shop_domain' and x.code <> v_code) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':domain_taken', 'code', 'domain_taken', 'message', format('Store %s: %s is already used by another store — nothing was saved', v_code, v_c->>'shop_domain'));
      end if;
      if nullif(trim(coalesce(v_c->>'label', '')), '') is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':label_missing', 'code', 'label_missing', 'message', format('Store %s needs a label — nothing was saved', v_code));
      end if;
      if coalesce(v_c->>'kind', '') not in ('asung', 'aone') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':kind_invalid', 'code', 'kind_invalid', 'message', format('Store %s: kind must be asung or aone — nothing was saved', v_code));
      end if;
      if (v_c ? 'oos_policy') and coalesce(v_c->>'oos_policy', '') not in ('continue', 'deny') then          -- shop-pol 판정 427: 품절 판매 continue | deny · 없으면 새 스토어 continue · 있는 스토어는 그대로
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':oos_policy_invalid', 'code', 'oos_policy_invalid', 'message', format('Store %s: sell when out of stock must be continue or deny — nothing was saved', v_code));
      end if;
      if (v_c ? 'auth_mode') and coalesce(v_c->>'auth_mode', '') not in ('client_credentials', 'stored_token') then   -- shop-live-1 판정 813: 열쇠 방식 · 없으면 새 스토어 client_credentials · 있는 스토어는 그대로
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':auth_mode_invalid', 'code', 'auth_mode_invalid', 'message', format('Store %s: the token mode must be client_credentials or stored_token — nothing was saved', v_code));
      end if;
      v_prefix := coalesce(nullif(trim(coalesce(v_c->>'secret_prefix', '')), ''), 'SHOPIFY_IMS');
      if v_prefix !~ '^[A-Z][A-Z0-9_]*$' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':prefix_invalid', 'code', 'prefix_invalid', 'message', format('Store %s: the secret prefix must be CAPITALS, digits or _ (e.g. SHOPIFY_IMS) — nothing was saved', v_code));
      end if;
      -- 티어 — 이름으로 받는다 · Price 는 sale 만 · Compare-at 은 sale 또는 compare(같아도 됨 · 비워도 됨) · reference 는 어디에도 안 된다(판정 403 고침)
      select * into v_sale from public.ref_price_tier t where t.name = trim(coalesce(v_c->>'sale_tier', '')) and t.is_active;
      if v_sale.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sale_tier_unknown', 'code', 'sale_tier_unknown', 'message', format('Store %s: there is no active price tier named "%s" for Price — nothing was saved', v_code, coalesce(v_c->>'sale_tier', '')));
      elsif v_sale.purpose <> 'sale' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sale_tier_not_sale', 'code', 'sale_tier_not_sale', 'message', format('Store %s: Price must be a sale tier — %s is a %s tier — nothing was saved', v_code, v_sale.name, v_sale.purpose));
      end if;
      if nullif(trim(coalesce(v_c->>'compare_tier', '')), '') is not null then
        select * into v_cmp from public.ref_price_tier t where t.name = trim(v_c->>'compare_tier') and t.is_active;
        if v_cmp.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':compare_tier_unknown', 'code', 'compare_tier_unknown', 'message', format('Store %s: there is no active price tier named "%s" for Compare-at — nothing was saved', v_code, v_c->>'compare_tier'));
        elsif v_cmp.purpose not in ('sale', 'compare') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':compare_tier_reference', 'code', 'compare_tier_reference', 'message', format('Store %s: Compare-at cannot be a %s tier (%s) — use a sale or compare tier, or leave it empty — nothing was saved', v_code, v_cmp.purpose, v_cmp.name));
        end if;
      end if;
      -- 알리기: 같은 kind 의 다른 활성 스토어(시험 + 실제가 같은 kind 일 수 있다 — 막지 않는다) · 꺼진 스토어를 다시 켬
      select count(*) into v_cnt from public.shop_store x where x.kind = coalesce(v_c->>'kind', '') and x.is_active and x.code <> v_code;
      if v_cnt > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':kind_active_dup', 'code', 'kind_active_dup', 'count', v_cnt, 'message', format('Store %s: %s other active store(s) already have kind %s — fine for a test store next to the real one, check it is what you mean', v_code, v_cnt, v_c->>'kind'));
      end if;
      if v_s.id is not null and not v_s.is_active then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':store_reactivated', 'code', 'store_reactivated', 'message', format('Store %s is off — saving turns it back on (it stays not live)', v_code));
      end if;
      if v_s.id is not null and v_s.live and (v_s.shop_domain is distinct from v_c->>'shop_domain' or v_s.secret_prefix is distinct from v_prefix or ((v_c ? 'auth_mode') and v_s.auth_mode is distinct from v_c->>'auth_mode')) then   -- shop-live-1: live 스토어의 연결 칸
        v_warns := v_warns || jsonb_build_object('key', v_key || ':live_connection_change', 'code', 'live_connection_change', 'message', format('Store %s is live — changing its domain, key prefix or token mode changes which real store IMS writes to from the next minute', v_code));
      end if;

    elsif v_op = 'store_off' then
      if v_s.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_unknown', 'code', 'store_unknown', 'message', format('Store %s does not exist — nothing was saved', v_code));
        continue;
      end if;
      if (v_code || '|store') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Store %s appears twice in this call — nothing was saved', v_code));
        continue;
      end if;
      v_seen := v_seen || (v_code || '|store');
      if not v_s.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':already_off', 'code', 'already_off', 'message', format('Store %s is already off — nothing was saved', v_code));
        continue;
      end if;
      if not (v_c ? 'old') or (v_c->>'old') is distinct from v_s.shop_domain then                  -- old = 화면이 본 shop_domain(스토어 확인용)
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Store %s: the domain the screen saw does not match — check again — nothing was saved', v_code));
        continue;
      end if;
      select count(*) into v_cnt from public.shop_location l where l.store_id = v_s.id and l.is_active;
      if v_cnt > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':locations_stay', 'code', 'locations_stay', 'count', v_cnt, 'message', format('Store %s has %s active location pair(s) — they stay as they are (the store is only switched off)', v_code, v_cnt));
      end if;

    elsif v_op = 'store_live' then                                                                 -- shop-live-1 판정 811 · 814 · 815: 일하는 길 켜기 · 끄기 {code, live, orders_from}
      if v_s.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_unknown', 'code', 'store_unknown', 'message', format('Store %s does not exist — nothing was saved', v_code));
        continue;
      end if;
      if (v_code || '|live') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Store %s: go live / stop appears twice in this call — nothing was saved', v_code));
        continue;
      end if;
      v_seen := v_seen || (v_code || '|live');
      if jsonb_typeof(v_c->'live') <> 'boolean' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':live_missing', 'code', 'live_missing', 'message', format('Store %s: live must be true or false — nothing was saved', v_code));
        continue;
      end if;
      if (v_c->>'live')::boolean then
        if not v_s.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_off', 'code', 'store_off', 'message', format('Store %s is switched off — save it (turn it on) before going live — nothing was saved', v_code));
          continue;
        end if;
        if v_s.live then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':already_live', 'code', 'already_live', 'message', format('Store %s is already live — nothing was saved', v_code));
          continue;
        end if;
        begin v_from := nullif(trim(coalesce(v_c->>'orders_from', '')), '')::timestamptz; exception when others then v_from := null; end;
        if v_from is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':orders_from_missing', 'code', 'orders_from_missing', 'message', format('Store %s: give orders_from — the moment Cin7 stopped reading this store (orders updated after it are read by IMS) — nothing was saved', v_code));
          continue;
        end if;
        if v_from > now() + interval '1 day' then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':orders_from_future', 'code', 'orders_from_future', 'message', format('Store %s: orders_from %s is in the future — orders before it will never be read by IMS', v_code, to_char(v_from at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI')));
        elsif v_from < now() - interval '7 days' then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':orders_from_old', 'code', 'orders_from_old', 'message', format('Store %s: orders_from %s is more than 7 days ago — every order updated since then will come into IMS (duplicates if Cin7 already loaded them)', v_code, to_char(v_from at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI')));
        end if;
        select count(*) into v_cnt from public.shop_location l where l.store_id = v_s.id and l.is_active;
        if v_cnt = 0 then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':no_location_pair', 'code', 'no_location_pair', 'message', format('Store %s has no active location pair — no stock will be sent and web orders cannot be placed at a warehouse until a pair is set', v_code));
        end if;
        select count(*) into v_cnt from public.shop_listing l where l.store_id = v_s.id and l.is_on;
        v_warns := v_warns || jsonb_build_object('key', v_key || ':going_live', 'code', 'going_live', 'count', v_cnt, 'message', format('Store %s goes LIVE: IMS starts writing to the real Shopify store %s — stock for all %s listed product(s) is sent now (IMS values overwrite Shopify), orders updated after %s are read into IMS, and product · fulfillment · payment updates follow from the next minute', v_code, v_s.shop_domain, v_cnt, to_char(v_from at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI')));
      else
        if not v_s.live then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':already_not_live', 'code', 'already_not_live', 'message', format('Store %s is not live — nothing was saved', v_code));
          continue;
        end if;
        v_warns := v_warns || jsonb_build_object('key', v_key || ':going_dark', 'code', 'going_dark', 'message', format('Store %s stops writing to Shopify: queued products · stock · orders wait (not failed) until it goes live again; orders placed meanwhile are not read', v_code));
      end if;

    else                                                                                            -- location_set · location_off
      if v_s.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_unknown', 'code', 'store_unknown', 'message', format('Store %s does not exist — nothing was saved', v_code));
        continue;
      end if;
      v_gid := trim(coalesce(v_c->>'shopify_location_gid', ''));
      v_key := v_code || ':' || (case when v_gid = '' then '(blank)' else v_gid end);
      if v_gid !~ '^gid://shopify/Location/[0-9]+$' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':gid_invalid', 'code', 'gid_invalid', 'message', format('Store %s: the Shopify location id must look like gid://shopify/Location/123 — nothing was saved', v_code));
        continue;
      end if;
      if (v_code || '|gid|' || v_gid) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Store %s: location %s appears twice in this call — nothing was saved', v_code, v_gid));
        continue;
      end if;
      v_seen := v_seen || (v_code || '|gid|' || v_gid);
      select * into v_l from public.shop_location l where l.store_id = v_s.id and l.shopify_location_gid = v_gid;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('Store %s location %s: the old warehouse the screen saw is missing (null for a new pair) — nothing was saved', v_code, v_gid));
        continue;
      end if;
      if (case when v_l.id is not null and v_l.is_active then v_l.warehouse_id::text end) is distinct from nullif(v_c->>'old', '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Someone just changed the warehouse of location %s on store %s — check again — nothing was saved', v_gid, v_code));
        continue;
      end if;
      if v_op = 'location_set' then
        if coalesce(v_c->>'warehouse_id', '') ~ '^[0-9a-fA-F-]{36}$' then
          select * into v_wh from public.ref_warehouse w where w.id = (v_c->>'warehouse_id')::uuid and w.is_active;
        end if;
        if v_wh.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_unknown', 'code', 'warehouse_unknown', 'message', format('Store %s location %s: the warehouse is missing or inactive — nothing was saved', v_code, v_gid));
          continue;
        end if;
        if (v_code || '|wh|' || v_wh.id::text) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_duplicate_in_call', 'code', 'warehouse_duplicate_in_call', 'message', format('Store %s: warehouse %s is given to two locations in this call — nothing was saved', v_code, v_wh.name));
          continue;
        end if;
        v_seen := v_seen || (v_code || '|wh|' || v_wh.id::text);
        if exists (select 1 from public.shop_location x where x.store_id = v_s.id and x.warehouse_id = v_wh.id and x.is_active and x.shopify_location_gid <> v_gid) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_already_mapped', 'code', 'warehouse_already_mapped', 'message', format('Store %s: warehouse %s is already paired with another Shopify location — switch that pair off first — nothing was saved', v_code, v_wh.name));
          continue;
        end if;
      else
        if v_l.id is null or not v_l.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':location_unknown', 'code', 'location_unknown', 'message', format('Store %s has no active pair for location %s — nothing was saved', v_code, v_gid));
          continue;
        end if;
      end if;
    end if;
  end loop;

  -- ③ 판정
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ④ 저장 — 줄 순서대로 · 한 트랜잭션
  v_i := 0;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_code := lower(trim(coalesce(v_c->>(case when v_op like 'store_%' then 'code' else 'store_code' end), '')));
    select * into v_s from public.shop_store s where s.code = v_code;
    if v_op = 'store_set' then
      select t.id into v_sale from public.ref_price_tier t where t.name = trim(v_c->>'sale_tier') and t.is_active;
      v_cmp := null;
      if nullif(trim(coalesce(v_c->>'compare_tier', '')), '') is not null then
        select t.id into v_cmp from public.ref_price_tier t where t.name = trim(v_c->>'compare_tier') and t.is_active;
      end if;
      v_prefix := coalesce(nullif(trim(coalesce(v_c->>'secret_prefix', '')), ''), 'SHOPIFY_IMS');
      v_mode := nullif(trim(coalesce(v_c->>'auth_mode', '')), '');
      if v_s.id is null then
        insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, compare_tier_id, secret_prefix, oos_policy, auth_mode, live, is_active, updated_by)
        values (v_code, v_c->>'shop_domain', trim(v_c->>'label'), v_c->>'kind', v_sale.id, v_cmp.id, v_prefix, coalesce(v_c->>'oos_policy', 'continue'), coalesce(v_mode, 'client_credentials'), false, true, v_staff);   -- shop-live-1 판정 811: 새 스토어는 live false
      else
        update public.shop_store set shop_domain = v_c->>'shop_domain', label = trim(v_c->>'label'), kind = v_c->>'kind', sale_tier_id = v_sale.id, compare_tier_id = v_cmp.id, secret_prefix = v_prefix, oos_policy = coalesce(v_c->>'oos_policy', v_s.oos_policy), auth_mode = coalesce(v_mode, v_s.auth_mode), is_active = true
         where id = v_s.id;                                                                       -- live 는 건드리지 않는다(store_live 만)
      end if;
    elsif v_op = 'store_off' then
      update public.shop_store set is_active = false, live = false where id = v_s.id;             -- shop-live-1: 끄면 live 도 끈다(다시 켜도 잠든 채)
    elsif v_op = 'store_live' then
      if (v_c->>'live')::boolean then
        update public.shop_store set live = true, orders_polled_at = (v_c->>'orders_from')::timestamptz where id = v_s.id;   -- 판정 814: 컷 시각 = 여기서부터 읽기
        v_nq := public.shop_stock_queue_all(v_s.id);                                               -- 판정 815: 켜는 순간 그 스토어 재고 전부 force(상품 큐 · 오더 큐는 대기하던 줄이 다음 회차에 나간다)
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'stock_queued'], to_jsonb(v_nq));
      else
        update public.shop_store set live = false where id = v_s.id;
      end if;
    elsif v_op = 'location_set' then
      v_gid := trim(v_c->>'shopify_location_gid');
      select * into v_l from public.shop_location l where l.store_id = v_s.id and l.shopify_location_gid = v_gid;
      if v_l.id is not null then
        update public.shop_location set warehouse_id = (v_c->>'warehouse_id')::uuid, is_active = true where id = v_l.id;
      elsif exists (select 1 from public.shop_location x where x.store_id = v_s.id and x.warehouse_id = (v_c->>'warehouse_id')::uuid and not x.is_active) then
        update public.shop_location set shopify_location_gid = v_gid, shopify_name = null, checked_at = null, is_active = true     -- 꺼진 같은 창고 짝을 되살려 새 GID 로(유니크 둘을 지킨다)
         where store_id = v_s.id and warehouse_id = (v_c->>'warehouse_id')::uuid and not is_active;
      else
        insert into public.shop_location (store_id, shopify_location_gid, warehouse_id, is_active, updated_by) values (v_s.id, v_gid, (v_c->>'warehouse_id')::uuid, true, v_staff);
      end if;
    elsif v_op = 'location_off' then
      update public.shop_location set is_active = false where store_id = v_s.id and shopify_location_gid = trim(v_c->>'shopify_location_gid');
    end if;
    v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
  end loop;
  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;

$$;
comment on function public.shop_store_save(jsonb, boolean, text[]) is
  '⭐ Shopify 스토어 설정 창구(shop-1a · 판정 362 · 403 · shop-0 이견 5 · ⭐ shop-live-1 판정 811 · 813 · 814 · 815) — definer · 첫 줄 ims_require_admin · p_changes = 바꿀 것 목록(최대 200) · op 다섯: store_set {code, shop_domain, label, kind, sale_tier, compare_tier, secret_prefix?, oos_policy?, auth_mode?, old}(새 스토어는 old null · live false · auth_mode 없으면 client_credentials / 있는 스토어는 old = 화면이 본 여섯 칸 {shop_domain, label, kind, sale_tier, compare_tier, secret_prefix} + oos_policy · auth_mode 는 old 에 있을 때만 대조 · live 는 건드리지 않는다 · 꺼진 스토어는 다시 켠다(live 는 그대로 false)) · store_off {code, old = shop_domain}(is_active · live 둘 다 끔) · store_live {code, live true|false, orders_from}(켜기 = is_active 필요 · orders_from(timestamptz · 필수 · 판정 814 컷 시각) → orders_polled_at · live true · 그 스토어 재고 전부 force(shop_stock_queue_all · 판정 815 · changes[i].stock_queued) / 끄기 = live false 만) · location_set {store_code, shopify_location_gid, warehouse_id, old} · location_off {store_code, shopify_location_gid, old}. 막기 code_invalid · oos_policy_invalid · auth_mode_invalid · domain_invalid · domain_taken · label_missing · kind_invalid · prefix_invalid · sale_tier_unknown · sale_tier_not_sale · compare_tier_unknown · compare_tier_reference · store_unknown · already_off · old_missing · changed_elsewhere · field_duplicate_in_call · live_missing · store_off · already_live · already_not_live · orders_from_missing · gid_invalid · warehouse_unknown · warehouse_duplicate_in_call · warehouse_already_mapped · location_unknown. 알리기(ack) kind_active_dup{count} · store_reactivated · live_connection_change · locations_stay{count} · going_live{count}(⚠️ 실제 스토어에 쓰기 시작) · orders_from_future · orders_from_old · no_location_pair · going_dark. 검사만(p_commit false) → 저장(p_commit true + p_ack) · 막기 하나면 아무것도 안 바뀐다';

-- ═══ 4) 뷰 shop_store_list 재발행 — 끝에 live · auth_mode ═══
create or replace view public.shop_store_list
  with (security_invoker = true) as
  select s.id, s.code, s.shop_domain, s.label, s.kind, s.is_active, s.secret_prefix, s.note, s.updated_at, s.updated_by,
         s.sale_tier_id,    ts.name as sale_tier_name,
         s.compare_tier_id, tc.name as compare_tier_name,
         coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'shopify_location_gid', l.shopify_location_gid, 'shopify_name', l.shopify_name,
                                                        'warehouse_id', l.warehouse_id, 'warehouse_name', w.name, 'is_active', l.is_active, 'checked_at', l.checked_at)
                                     order by l.is_active desc, w.name)
                     from public.shop_location l join public.ref_warehouse w on w.id = l.warehouse_id
                    where l.store_id = s.id), '[]'::jsonb) as locations,
         (select count(*) from public.shop_location l where l.store_id = s.id and l.is_active) as locations_active,
         p.ok as last_ping_ok, p.called_at as last_ping_at, p.error as last_ping_error,
         s.oos_policy, s.send_tags,
         s.live, s.auth_mode, s.orders_polled_at                                                     -- shop-live-1: 끝에 셋(create or replace 는 끝에만 더할 수 있다)
    from public.shop_store s
    join public.ref_price_tier ts on ts.id = s.sale_tier_id
    left join public.ref_price_tier tc on tc.id = s.compare_tier_id
    left join lateral (select g.ok, g.called_at, g.error from public.shop_call_log g where g.store_id = s.id and g.action = 'ping' order by g.called_at desc, g.id desc limit 1) p on true;
comment on view public.shop_store_list is 'shop-1a: Settings → Shopify Stores 화면의 목록 — 스토어 + 티어 이름 + locations jsonb + locations_active + 마지막 ping(shop_call_log action ping) + shop-pol: oos_policy · send_tags + ⭐ shop-live-1: live(판정 811) · auth_mode(판정 813) · orders_polled_at(판정 814 컷 시각) · security_invoker · select 만';
