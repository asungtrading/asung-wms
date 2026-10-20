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

-- ═══ link-1b — Shopify 잇기 EF 의 DB 몫 (2026-10-20 · 판정 420 · 555 ~ 563 · link-1a 20261020173401 뒤 · so-module §67 미룬 261) ═══
--   ① shop_link_run 칸 넷 — EF link_read · link_poll 이 bulk 의 상태 · 결과 주소 · 오류 · 적재 진행을 적는 자리(bulk_url · bulk_status · bulk_error · loaded_count)
--   ② 제약 shop_product_gid_real_ck — 첫 보내기 실패 때 EF 가 적던 자리표시 gid://shopify/Product/0 을 막는다(EF 고침 errorMark 와 같은 묶음 · 1a 보고 「1b 에 넣을 문장 3」) · 테스트 DB 에 그런 행 0 을 착지 확인이 본다
--   무접촉: link-1a 의 창구 넷 · shop_* 다른 표 · EF 의 다른 액션

alter table public.shop_link_run
  add column bulk_url     text,                                                               -- bulk 결과 JSONL 주소(7 일 · COMPLETED 때)
  add column bulk_status  text,                                                               -- Shopify BulkOperation.status 그대로(CREATED · RUNNING · COMPLETED · FAILED · CANCELED · EXPIRED) · NOT_STARTED(시작 실패) · DROPPED(restart 로 버림)
  add column bulk_error   text,                                                               -- 실패 · 적재 오류 글(400 자)
  add column loaded_count int not null default 0;                                             -- shop_link_item 에 든 상품 수(이어 적재 · 멱등)
comment on column public.shop_link_run.bulk_url is 'link-1b — bulk 결과 JSONL 주소(COMPLETED 때 EF 가 적는다 · 7 일 뒤 만료 · 다시 읽으려면 link_read 부터)';
comment on column public.shop_link_run.bulk_status is 'link-1b — Shopify BulkOperation.status 그대로 · NOT_STARTED(시작 거부) · DROPPED(restart 로 버린 판)';
comment on column public.shop_link_run.loaded_count is 'link-1b — 적재된 상품 수(link_poll 이 40 초 예산마다 이어 적는다 · item_count 와 같아지면 read)';

alter table public.shop_product add constraint shop_product_gid_real_ck check (shopify_product_gid <> 'gid://shopify/Product/0');
comment on constraint shop_product_gid_real_ck on public.shop_product is 'link-1b — 자리표시 gid://shopify/Product/0 금지: 첫 보내기 실패 때 EF 가 이것을 적어 다음 보내기가 가짜 id 로 고치기를 시도하고 둘째 실패는 유니크에 걸려 기록도 못 했다(shop-link-0 결함) · EF errorMark 는 gid 가 없으면 적지 않는다';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int;
begin
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and table_name = 'shop_link_run' and column_name in ('bulk_url', 'bulk_status', 'bulk_error', 'loaded_count');
  if v_n <> 4 then v_bad := v_bad || format(' columns_%s_of_4', v_n); end if;
  if not exists (select 1 from pg_constraint where conname = 'shop_product_gid_real_ck' and conrelid = 'public.shop_product'::regclass) then v_bad := v_bad || ' no_constraint'; end if;
  if exists (select 1 from public.shop_product where shopify_product_gid = 'gid://shopify/Product/0') then v_bad := v_bad || ' product0_rows_exist'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_link_plan', 'shop_link_apply', 'shop_link_push_batch', 'shop_link_remaining')) <> 4 then v_bad := v_bad || ' link_1a_missing'; end if;
  if v_bad <> '' then raise exception 'link-1b landing check failed:%', v_bad; end if;
end $$;
