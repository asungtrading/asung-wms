-- pay-2b (2026-10-14 · 판정 449 · 469 · pay-2a 20261014162538 위에) — mark_paid 큐를 집어 Shopify 를 Paid 로(EF paid_drain) · DB 는 경고 코드 하나
--   EF shopify action paid_drain(_shared/shopify-paid.ts): 큐 kind mark_paid 행마다 Shopify 읽기 → 가르기(취소 · PAID · AUTHORIZED · REFUNDED 류 skipped) → rpc shop_order_paid_state 다시 판정 → shop_order.paid_push_at 을 보내기 전에 적고(판정 468 창) → orderMarkAsPaid → PAID 확인
--     실패 5 회(권한으로 보이는 오류는 1 회)면 큐 done error + 경고 mark_paid_failed — 이 마이그레이션은 shop_order_warn 의 코드 목록에 mark_paid_failed 를 더한다(pay-2a 판 바이트 복사 위 · 목록 · 거부 문구 · comment)
--   ⚠️ cron 은 여기 없다 — supabase/ops/cron.sql pay-2b 절(ims-paid-scan · ims-paid-drain · 51 의 거름 조건 kind = order_edit)을 Caleb 이 테스트 DB 에서 돌린다 · EF 배포도 Caleb(supabase functions deploy shopify --project-ref fazgmyvzzhqybtvtktyg)
--   ⚠️ 무접촉: 표 · 큐 · 스캔 · paid_state · ingest · 화면(이름표 mark_paid_failed · shopify_paid_ims_owed 는 대화 Claude) · 실물 #1001 ~ #1012
--   검증: ~/asung/prompts/pay-2b-verify.sql(시험 적용 begin → rollback · 가짜 스토어 · 가짜 오더 · 시퀀스 무접촉)
--   적용: psql "$(cat ~/.asung-testdb-url)" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261014164407_pay_2b_mark_paid_warn.sql && supabase migration repair --status applied 20261014164407 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ shop_order_warn 재발행 — pay-2a 20261014162538:144 ~ 160 바이트 복사 · 바꾼 줄 3(코드 목록 · 거부 문구 · comment) ═══
create or replace function public.shop_order_warn(p_shop_order_id uuid, p_code text, p_message text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_w jsonb;
begin
  if p_code not in ('fulfill_failed', 'fulfill_cut', 'fulfill_location_mismatch', 'fulfill_nothing_left', 'pickup_failed', 'tracking_fix_failed', 'pickup_not_sent', 'refund_due', 'order_edit_failed', 'shopify_qty_removed', 'shopify_paid_ims_owed', 'mark_paid_failed') then
    raise exception 'shop_order_warn: code % is not one of fulfill_failed, fulfill_cut, fulfill_location_mismatch, fulfill_nothing_left, pickup_failed, tracking_fix_failed, pickup_not_sent, refund_due, order_edit_failed, shopify_qty_removed, shopify_paid_ims_owed, mark_paid_failed — nothing was saved', p_code;
  end if;
  update public.shop_order set warnings = warnings || jsonb_build_array(jsonb_build_object('code', p_code, 'message', nullif(btrim(coalesce(p_message, '')), ''), 'at', now()))
   where id = p_shop_order_id
  returning warnings into v_w;
  if not found then raise exception 'shop_order_warn: shop_order % not found — nothing was saved', p_shop_order_id; end if;
  return jsonb_build_object('shop_order_id', p_shop_order_id, 'code', p_code, 'warnings', jsonb_array_length(v_w));
end;
$$;
comment on function public.shop_order_warn(uuid, text, text) is 'ful-2a · 1b · 1c · 4a · pay-2a · pay-2b: shop_order.warnings 에 경고 한 줄 {code, message, at} 을 더한다 — 한 문장(warnings || …) · 코드 열(fulfill_failed · fulfill_cut · fulfill_location_mismatch · fulfill_nothing_left · pickup_failed · tracking_fix_failed · pickup_not_sent · refund_due · order_edit_failed · shopify_qty_removed · shopify_paid_ims_owed · mark_paid_failed) · service_role 만(EF) · definer 창구 안에서도';

-- ═══ 자기 검사 — 설계대로 들어앉았는지(아니면 멈춘다 · 트랜잭션 안이라 되돌아간다) ═══
do $$
declare v_bad text := ''; v_src text;
begin
  select p.prosrc into v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_order_warn';
  if v_src not like '%''mark_paid_failed''%' or v_src not like '%shopify_paid_ims_owed, mark_paid_failed — nothing was saved%' or v_src not like '%''shopify_paid_ims_owed''%' then v_bad := v_bad || ' warn(body)'; end if;
  if has_function_privilege('authenticated', 'public.shop_order_warn(uuid, text, text)', 'execute') or has_function_privilege('anon', 'public.shop_order_warn(uuid, text, text)', 'execute') or has_function_privilege('public', 'public.shop_order_warn(uuid, text, text)', 'execute') then v_bad := v_bad || ' warn(acl)'; end if;
  if to_regprocedure('public.shop_paid_scan(int, uuid)') is null or to_regprocedure('public.shop_order_paid_state(uuid)') is null then v_bad := v_bad || ' pay-2a'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_order' and column_name = 'paid_push_at') <> 1 then v_bad := v_bad || ' paid_push_at(pay-1a)'; end if;
  if (select count(*) from pg_constraint where conname = 'shop_order_queue_kind_ck' and pg_get_constraintdef(oid) like '%mark_paid%') <> 1 then v_bad := v_bad || ' queue_kind'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM470', message = format('STOP - pay-2b did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
