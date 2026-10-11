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

-- ════════════════════════════════════════════════════════════════════════════════════════════
-- ord-1b — Shopify ④ 오더 받기 · EF 의 받은 일 표 (2026-10-10 밤 · 판정 363 · 1a1 20261010233000 · 1a2 20261011003000 위에)
--   ① shop_order_inbox — 웹훅(orders/create · updated · cancelled) · 주기 확인이 「이 오더를 다시 읽어라」 를 적는 줄 · 몸은 담지 않는다(웹훅 몸은 REST 모양이라 ingest 가 받는 GraphQL 모양과 다르다 — drain 이 GraphQL 로 다시 읽는다)
--      열린 줄은 오더마다 하나(shop_order_inbox_add 가 not exists · 규칙 29: 유니크 부분 인덱스 없이) · webhook_id 는 배달마다 하나(unique · 중복 배달 건너뜀)
--   ② shop_store.orders_polled_at — 주기 확인(orders_poll)의 마지막 기준 시각(updated_at:> 이것 − 겹침)
--   ③ shop_order_inbox_add(store, gid, topic, webhook_id, event_id) → 넣은 줄 id | null(이미 열린 줄 · 같은 배달) · service_role 만(EF)
--   무접촉: ord-1a1 · 1a2 함수 · 표 · EF 는 ord-1b 가 같이 간다
-- ════════════════════════════════════════════════════════════════════════════════════════════

create table public.shop_order_inbox (
  id            bigint generated always as identity primary key,
  store_id      uuid not null references public.shop_store (id) on delete no action,
  order_gid     text not null,
  topic         text not null,                                                                  -- orders/create · orders/updated · orders/cancelled · poll · manual
  webhook_id    text,                                                                           -- X-Shopify-Webhook-Id(배달마다) · poll 은 null
  event_id      text,                                                                           -- X-Shopify-Event-Id(같은 일)
  received_at   timestamptz not null default now(),
  started_at    timestamptz,
  done_at       timestamptz,
  result        text,                                                                           -- ingest · process 가 돌려준 status(received · needs_review · created · cancelled · error) · dup · not_found · error
  error         text,
  constraint shop_order_inbox_gid_ck     check (order_gid ~ '^gid://shopify/Order/[0-9]+$'),
  constraint shop_order_inbox_webhook_uk unique (webhook_id),
  constraint shop_order_inbox_done_ck    check ((done_at is null) = (result is null))
);
create index shop_order_inbox_open_idx  on public.shop_order_inbox (received_at) where done_at is null;
create index shop_order_inbox_gid_idx   on public.shop_order_inbox (order_gid);
create index shop_order_inbox_store_idx on public.shop_order_inbox (store_id);
alter table public.shop_order_inbox enable row level security;
create policy shop_order_inbox_select on public.shop_order_inbox for select to authenticated using (true);
revoke all on public.shop_order_inbox from anon, authenticated;
grant select on public.shop_order_inbox to authenticated;
comment on table public.shop_order_inbox is 'ord-1b 판정 363: 받은 일 — 웹훅 · 주기 확인이 적는 「이 Shopify 오더(GID)를 다시 읽어 ingest 하라」 줄 · 몸 없음 · 열린 줄(done_at null)은 오더마다 하나 · webhook_id unique(중복 배달) · EF orders_drain 이 오래된 것부터 GraphQL 로 읽어 shop_order_ingest → process · result = 그 결과 status · 쓰기는 EF(service_role) · shop_order_inbox_add';

alter table public.shop_store add column if not exists orders_polled_at timestamptz;
comment on column public.shop_store.orders_polled_at is 'ord-1b: 주기 확인(EF orders_poll)이 마지막으로 본 Shopify updated_at 기준 — 다음 확인은 이것 − 겹침(5 분)부터 · null 이면 하루 전부터';

create function public.shop_order_inbox_add(p_store_id uuid, p_order_gid text, p_topic text, p_webhook_id text default null, p_event_id text default null) returns bigint
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_id bigint;
begin
  if p_webhook_id is not null and exists (select 1 from public.shop_order_inbox x where x.webhook_id = p_webhook_id) then return null; end if;          -- 같은 배달 두 번
  insert into public.shop_order_inbox (store_id, order_gid, topic, webhook_id, event_id)
  select p_store_id, p_order_gid, p_topic, p_webhook_id, p_event_id
   where not exists (select 1 from public.shop_order_inbox x where x.order_gid = p_order_gid and x.done_at is null)                                     -- 열린 줄은 오더마다 하나
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.shop_order_inbox_add(uuid, text, text, text, text) from public, anon, authenticated;
comment on function public.shop_order_inbox_add(uuid, text, text, text, text) is 'ord-1b: 받은 일 넣기 한 곳 — 같은 webhook_id 가 있거나 그 오더의 열린 줄이 있으면 null(넣지 않음) · 아니면 새 줄 id · service_role 만(EF webhook · orders_poll)';

do $$ begin
  if to_regclass('public.shop_order_inbox') is null or to_regprocedure('public.shop_order_inbox_add(uuid, text, text, text, text)') is null then raise exception 'ord-1b: inbox missing'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_store' and column_name = 'orders_polled_at') <> 1 then raise exception 'ord-1b: orders_polled_at missing'; end if;
  if has_function_privilege('authenticated', 'public.shop_order_inbox_add(uuid, text, text, text, text)', 'execute') then raise exception 'ord-1b: inbox_add must not be executable by authenticated'; end if;
end $$;
