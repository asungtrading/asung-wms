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
-- qbo-sync-2e-1a2 — Shopify 결제의 Deposit To = Clearing - Shopify (판정 993 (가) · 2026-11-02 밤 집 · 47 장 대조 · Cin7 꼴)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용 + supabase migration repair --status applied 20261103040000 · ⚠️ db push 쓰지 않는다
-- 무엇:
--   ① so_payment_account_default 의 shopify 행(TOR · EDM · CAD) _104_ TD CAD CHEQUING → _1150040029_ Clearing - Shopify(Cin7 이 보내던 계좌 · 북키퍼가 수수료 뗀 묶음 입금을 거기서 맞춘다)
--      USD shopify 행은 없다(판정 2 「USD 없음 → 계좌를 요구」 그대로 · 이 파일은 만들지 않는다) · paypal(_124_) · cheque(_105_) · 그 밖 무변
--   ② _1150040029_ 의 QBO 짝(qbo_link account)을 확인만(NOTICE · 없으면 멈추지 않는다 — 보내기 몸이 거부한다)
-- 안 하는 것: 이미 적힌 shopify 결제 34 건(_104_)은 supabase/ops/shopify-clearing-fix.sql(dry-run 기본) · 함수 재발행 0 · 화면 0
-- 검증: supabase/tests/qbo_sync_2e1a2_check.sql (-v mig 로 시험 · 적용 뒤에는 -v mig 없이) · 거래 표 FK 를 거는 새 표 없음

do $$
declare v_tor uuid; v_edm uuid; v_029 public.ref_account%rowtype; v_n int; v_total int; v_link text;
begin
  select w.id into v_tor from public.ref_warehouse w where w.name = 'Asung Trading Inc.';
  select w.id into v_edm from public.ref_warehouse w where w.name = 'Asung - Edmonton';
  if v_tor is null or v_edm is null then raise exception '① warehouse "Asung Trading Inc." / "Asung - Edmonton" not found in ref_warehouse — nothing was saved'; end if;
  select * into v_029 from public.ref_account a where a.code = '_1150040029_';
  if v_029.id is null or not (v_029.is_active and v_029.account_type = 'BANK') then raise exception '① account _1150040029_ (Clearing - Shopify) missing or not an active BANK account — nothing was saved'; end if;
  update public.so_payment_account_default d set account_id = v_029.id, account_code = v_029.code, note = concat_ws(' · ', d.note, 'qbo-sync-2e-1a2 판정 993: _104_ → _1150040029_'), updated_at = now()
   where d.method = 'shopify' and d.currency_code = 'CAD' and d.warehouse_id in (v_tor, v_edm) and d.account_code = '_104_';
  get diagnostics v_n = row_count;
  if v_n <> 2 then raise exception '① expected to move exactly 2 shopify CAD rows from _104_ to _1150040029_ (moved %) — nothing was saved', v_n; end if;
  select count(*) into v_n from public.so_payment_account_default d where d.method = 'shopify' and d.currency_code <> 'CAD';
  select count(*) into v_total from public.so_payment_account_default;
  select l.qbo_id into v_link from public.qbo_link l where l.ims_kind = 'account' and l.ims_id = v_029.id::text and l.realm_id = (select c.realm_id from public.qbo_connection c where c.singleton);
  raise notice '① so_payment_account_default: shopify CAD TOR · EDM → _1150040029_ (2) · shopify non-CAD rows % (expected 0 · untouched) · rows now % · QBO account link %', v_n, v_total, coalesce(v_link, 'NONE — link it under Settings → QuickBooks matching before sending payments');
end $$;
comment on column public.so_payment_account_default.method is '결제 방법(so_payment.method 와 같은 어휘 · opening 없음) · + qbo-sync-2e-1a paypal(TOR · EDM CAD → _124_) · cheque CAD 는 판정 984 로 _105_ BMO CAD CHEQUING(옛 _5_ Undeposited Funds) · + qbo-sync-2e-1a2 판정 993: shopify CAD → _1150040029_ Clearing - Shopify(옛 _104_ · Cin7 꼴 · 수수료 뗀 묶음 입금을 북키퍼가 거기서 맞춘다)';
-- 끝 — 적용 뒤: supabase/tests/qbo_sync_2e1a2_check.sql(-v mig 없이) · supabase/ops/shopify-clearing-fix.sql dry-run → apply
