-- ─────────────────────────────────────────────────────────────
-- shop-stock-perf-1 — shop_stock_targets 재발행(Asung-IMS · 2026-11-02 · 운영 장애 hotfix · wms-timeout-hotfix 진단 §2)
--   경위: 11-01 23:52(토론토) Shopify 오더 AS-7389(227 줄) · 11-02 09:34 AS-7393(99 줄)이 shop_order_process 에서 8 s statement_timeout 으로 끊기고
--        ims-orders-drain 이 매분 같은 오더를 다시 불러(시간당 60 → 120 회) DB 를 눌렀다 · 창고 창구(Release · 팩 Start verify · Finalize)가 같은 timeout 으로 쓰러졌다.
--   범인: shop_stock_targets(SQL 함수)가 so_reserve · inv_transfer_line 의 문장 트리거(shop_stock_queue_trigger → shop_stock_queue_add)에서 매개변수로 불릴 때
--        generic plan 이 되어 「(p_store_id is null or …) · (p_product_ids is null or …)」 를 가지치기 못한다 → shop_listing 9,496 행 × product OR 조인 = 호출당 70 ~ 80 ms
--        (literal 이면 1 ms) · 99 줄 오더 = so_reserve insert 110 문장 × 82 ms = 9.1 s. pg_stat_statements 그 insert 평균 81.8 ms · 최대 267 ms.
--   고침(결과 집합은 그대로 — 옛 ⊖ 새 · 새 ⊖ 옛 = 0 · 전부 16,780 행 · pid 700 · store+pid · 세트 400 네 번 확인):
--     plpgsql 로 바꿔 p_product_ids null 갈래(전부)는 옛 문장 그대로 · pid 갈래는 product 에서 출발해 OR 조인을 union 둘(낱개 listing · family listing)로 가른다
--     ⇒ 매개변수 plan 에서도 product_pkey → shop_listing_store_prod_uk · shop_listing_family_id_idx 로 내려간다 · 호출 2.5 ms · shop_order_process AS-7393 11.2 s → 2.1 s · AS-7389 3.4 s
--   마지막 정의: 20261027190714_shop_live_1.sql:44(DB prosrc md5 81a93a747ce3b17ae3388c9cf8eb0228 · 바이트 동일 확인) · 권한 그대로(revoke public · postgres · service_role 만 — create or replace 는 ACL 을 보존)
--   무접촉: shop_stock_queue_add · shop_stock_queue_trigger · 큐 표 · 화면 · 콤보 판정 952 ~ 957 · tf-combo-1a · 1b 객체
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음
--   ⚠️ 따로 볼 것(이 파일 밖): 실패한 Shopify 오더를 매분 같은 꼴로 재시도하는 drain(뒤로 미루기 · 횟수 한도) · 연결 60 소진 때 무엇이 먼저 죽는가
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

-- ═══ 1) shop_stock_targets 재발행 — 원본 shop_live_1:44 ~ 54 · null 갈래 바이트 복사 · pid 갈래 새로(shop-stock-perf-1) ═══
create or replace function public.shop_stock_targets(p_store_id uuid, p_product_ids uuid[] default null)
  returns table (store_id uuid, product_id uuid)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
begin
  if p_product_ids is null then                                                      -- shop-stock-perf-1: 전부 갈래 — 옛 문장 그대로(nightly · store_live 가 쓴다)
    return query
      select l.store_id, p.id
        from public.shop_listing l
        join public.shop_store s on s.id = l.store_id and s.is_active and s.live        -- shop-live-1 판정 811 · 815: live 전 스토어의 변형은 대상이 아니다(큐 0 · 켜는 순간 store_live 가 전부 force)
        join public.product p on (l.product_id = p.id) or (l.family_id is not null and p.family_id = l.family_id and p.parent_product_id is null)
       where l.is_on
         and (p_store_id is null or l.store_id = p_store_id);
  else                                                                               -- shop-stock-perf-1: pid 갈래 — product 에서 출발 · OR 조인을 union 둘로(generic plan 에서도 인덱스)
    return query
      select l.store_id, p.id                                                        -- ① 낱개 · 세트 listing: l.product_id = p.id
        from public.product p
        join public.shop_listing l on l.product_id = p.id
        join public.shop_store s on s.id = l.store_id and s.is_active and s.live
       where p.id = any(p_product_ids)
         and l.is_on
         and (p_store_id is null or l.store_id = p_store_id)
      union
      select l.store_id, p.id                                                        -- ② family listing 의 낱개 구성원: p.family_id = l.family_id · parent 없는 것
        from public.product p
        join public.shop_listing l on l.family_id = p.family_id
        join public.shop_store s on s.id = l.store_id and s.is_active and s.live
       where p.id = any(p_product_ids)
         and p.parent_product_id is null
         and l.is_on
         and (p_store_id is null or l.store_id = p_store_id);
  end if;
end $$;
comment on function public.shop_stock_targets(uuid, uuid[]) is 'stock-1a: 재고를 보낼 변형 한 곳 — 켜진 listing(스토어 하나 또는 전부)의 변형 = 낱개 listing 의 상품 · family listing 의 낱개 구성원 · sellable 세트 listing 의 세트 · p_product_ids 로 좁힌다(null = 전부) · 판정 425 꺼진 listing 의 변형은 안 낸다 · ⭐ shop-live-1 판정 811 · 815: 스토어가 is_active and live 일 때만(live 전 스토어는 큐 0 · 켜는 순간 store_live 가 전부 force) · ⭐ shop-stock-perf-1(2026-11-02 장애): plpgsql · pid 갈래는 product 에서 출발 · union 둘 — 트리거(so_reserve · inv_transfer_line 문장마다)에서 매개변수로 불릴 때 generic plan 이 전체를 훑던 70 ms 를 2 ms 로 · 결과 집합은 옛 것과 같다';
