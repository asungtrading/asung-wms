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

-- ═══ hist-1c — product 에 upper(sku) 색인 (2026-10-23 · 지난 이력 적재의 시간 초과 고침 · 판정 664 · 665 의 연습 적재가 PO-01382 에서 섰다) ═══
--   까닭: hist_so_load · hist_po_load 의 제품 풀기 둘째 갈래 `(select p.id from product p where upper(p.sku) = upper(…) order by p.sku limit 1)` 이 색인 없이 18,741 행을 훑어 한 번 27 ~ 31 ms ·
--         안 풀리는 SKU 400 줄이 몰린 PO(L.A. COLORS 신제품 405 SKU) 한 쪽이 REST 역할의 statement_timeout 8 s 를 넘겼다(57014)
--   고침: 복합 식 색인 (upper(sku), sku) — 식 조건과 `order by p.sku limit 1` 을 둘 다 색인이 받아 창구는 무변 · 실측(테스트 DB · 18,741 행): 만들기 0.083 s · 없는 SKU 한 번 0.088 ms(ANALYZE 없이도 색인을 쓴다 — 단일 upper(sku) 색인은 통계 전엔 안 쓰고 쓰더라도 Sort 가 남는다)
--   유니크로 두지 않는다(대소문자만 다른 새 SKU 를 막을지는 판정 거리 · upper 겹침 무리는 지금 0) · 같은 꼴을 쓰는 다른 창구(po_lines_paste · so_lines_paste · inv_transfer_lines_paste)도 이 색인을 쓸 수 있다(그쪽 계획은 안 봤다)
--   ⚠️ CREATE INDEX 는 그동안 product 쓰기를 막는다(트랜잭션 안이라 CONCURRENTLY 불가) — 실측 0.083 s
create index product_sku_upper_idx on public.product (upper(sku), sku);
comment on index public.product_sku_upper_idx is 'hist-1c — SKU 대소문자 무시 풀기(hist_so_load · hist_po_load · 붙여 넣기 창구들의 upper(p.sku) = upper(…) order by p.sku limit 1) · 식 조건 + 정렬을 한 색인이 받는다 · 유니크 아님(판정 거리)';

do $$
declare v_def text;
begin
  select indexdef into v_def from pg_indexes where schemaname = 'public' and tablename = 'product' and indexname = 'product_sku_upper_idx';
  if v_def is distinct from 'CREATE INDEX product_sku_upper_idx ON public.product USING btree (upper(sku), sku)' then raise exception 'hist-1c landing check failed: indexdef %', coalesce(v_def, '(none)'); end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('hist_so_load', 'hist_po_load') and p.prosrc ~ 'upper\(p\.sku\) = upper\(trim\(l->>''sku''\)\) order by p\.sku limit 1') <> 2 then
    raise exception 'hist-1c landing check failed: the windows no longer carry the upper/order-by shape this index serves'; end if;
end $$;
