-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- ful-2a — Shopify ⑤ 오더 상태 · EF 발송(fulfill_drain)을 위한 작은 DB 차수 (2026-10-13 · 판정 453 · ful-2 이견 4 · 5 · ful-1a 20261013170000 위에)
--   ① shop_fulfillment_line.quantity_sent — Shopify 남은 수량으로 자른 뒤 실제 보낸 수량(미룬 201 b · null = 아직 · 0 = 남은 것이 없었다 · < quantity 면 경고 fulfill_cut)
--   ② shop_fulfillment.status 에 skipped(보낼 것이 없었고 받아 적을 발송도 없다 · 경고 fulfill_nothing_left) · sent_ck 넓힘: sent = fulfillment GID 또는 ready_at(「Ready for pickup」 은 발송을 만들지 않는다 — userErrors 만)
--   ③ shop_order_warn(definer · service_role 만) — EF 가 shop_order.warnings 에 경고 한 줄을 더한다(jsonb || 한 문장 · REST 읽고-쓰기면 ingest 의 경고와 겹쳐 지워진다) · 코드 넷만
--   적용: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f <이 파일> && supabase migration repair --status applied <버전> --db-url "$(cat ~/.asung-testdb-url)"  — ⚠️ EF shopify 배포보다 먼저
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


-- ═══ 1) quantity_sent ═══
alter table public.shop_fulfillment_line add column quantity_sent numeric;
alter table public.shop_fulfillment_line add constraint shop_fulfillment_line_sent_ck check (quantity_sent is null or (quantity_sent >= 0 and quantity_sent <= quantity));
comment on column public.shop_fulfillment_line.quantity_sent is 'ful-2a 미룬 201 b: EF 가 Shopify 의 remainingQuantity 로 자른 뒤 실제 보낸 수량 · null = 아직 · 0 = 남은 것이 없었다(skipped 또는 받아 적음) · quantity 보다 작으면 shop_order 경고 fulfill_cut';

-- ═══ 2) status skipped · sent 의 짝 ═══
alter table public.shop_fulfillment drop constraint shop_fulfillment_status_ck;
alter table public.shop_fulfillment add constraint shop_fulfillment_status_ck check (status in ('pending', 'sent', 'error', 'skipped'));
alter table public.shop_fulfillment drop constraint shop_fulfillment_sent_ck;
alter table public.shop_fulfillment add constraint shop_fulfillment_sent_ck check ((status = 'sent') = (shopify_fulfillment_gid is not null or ready_at is not null));
comment on column public.shop_fulfillment.status is 'pending(큐에 넣음) · sent(fulfillmentCreate 가 돌려준 GID 또는 「Ready for pickup」 ready_at) · error(시도 수 · last_error · 큐가 다시 돈다) · skipped(Shopify 에 보낼 것이 없었고 받아 적을 발송도 없다 · 경고 fulfill_nothing_left · ful-2a)';

-- ═══ 3) shop_order_warn — 경고 한 줄 더하기(EF 전용) ═══
create function public.shop_order_warn(p_shop_order_id uuid, p_code text, p_message text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_w jsonb;
begin
  if p_code not in ('fulfill_failed', 'fulfill_cut', 'fulfill_location_mismatch', 'fulfill_nothing_left') then
    raise exception 'shop_order_warn: code % is not one of fulfill_failed, fulfill_cut, fulfill_location_mismatch, fulfill_nothing_left — nothing was saved', p_code;
  end if;
  update public.shop_order set warnings = warnings || jsonb_build_array(jsonb_build_object('code', p_code, 'message', nullif(btrim(coalesce(p_message, '')), ''), 'at', now()))
   where id = p_shop_order_id
  returning warnings into v_w;
  if not found then raise exception 'shop_order_warn: shop_order % not found — nothing was saved', p_shop_order_id; end if;
  return jsonb_build_object('shop_order_id', p_shop_order_id, 'code', p_code, 'warnings', jsonb_array_length(v_w));
end;
$$;
revoke all on function public.shop_order_warn(uuid, text, text) from public, anon, authenticated;
comment on function public.shop_order_warn(uuid, text, text) is 'ful-2a: EF fulfill_drain 이 shop_order.warnings 에 경고 한 줄 {code, message, at} 을 더한다 — 한 문장(warnings || …)이라 ingest 의 경고와 겹쳐도 안 지워진다 · 코드 넷(fulfill_failed · fulfill_cut · fulfill_location_mismatch · fulfill_nothing_left) · service_role 만 · 화면은 Web Orders 상세가 warnings 를 그대로 보인다';
