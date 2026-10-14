-- pay-2a (2026-10-14 · 판정 449 · 469 · ful-4a 20261014000000 · pay-1a 20261014154103 위에) — 「다 결제」를 알아보고 mark_paid 큐에 넣는다
--   판정 449(정본 §61): Net 오더가 IMS 에서 다 결제되는 순간 IMS 가 Shopify 오더를 Paid 로 바꾼다(orderMarkAsPaid · 남은 금액 전부) — 까닭 = 손님이 asung.ca 계정에서 오더 상태를 본다
--   판정 469 [Caleb · 2026-10-14 · 안 1]: 「다 결제」 = 웹 오더의 SO 뭉치(shop_so_family — 처음 SO · 백오더 · 부족분 형제 · 합쳐 들어간 오더)에 열린 오더가 없고(모두 fulfilled 또는 cancelled) 살아 있는 인보이스(status ≠ cancelled)의 남은 돈이 모두 0 · 0 이 된 길(결제 · 크레딧 · 받아 둔 돈 · 보증금)은 묻지 않는다
--     기각: 안 2(열린 백오더가 있어도 Paid — 판정 457 이 거짓 refund_due 를 내고 Shopify 를 되돌릴 길이 없다) · 안 3(orderCreateManualPayment — 금액 칸은 Shopify Plus 전용 · 메모 · 멱등 · 지우기 없음 · pay-0)
--   ⭐ 구현: ① shop_order_paid_state(오더) — 읽기만 · {family, open_sos, invoices, remaining_total, all_closed, all_paid, ready} · ready = 열린 오더 없음 and 살아 있는 인보이스 ≥ 1 and 남은 돈 합 ≤ 0(인보이스가 없는 전부 취소 뭉치는 ready 아님 — 돈을 받은 적이 없다 · Shopify 취소는 434 길) · 화면도 쓴다(authenticated 실행)
--     ② shop_paid_scan(limit · store) — cron 용(pay-2b 에서 등록) · 대상 = created · so 있음 · Shopify 취소 아님 · 켜진 스토어 · Shopify 결제 상태가 PENDING · PARTIALLY_PAID · EXPIRED · 없음(PAID · REFUNDED · PARTIALLY_REFUNDED · VOIDED · AUTHORIZED 는 대상 아님 — AUTHORIZED 는 카드 승인이라 Paid 로 바꾸면 Shopify 가 카드를 잡아 두 번 받는다)
--        ready 면 shop_order_requeue(mark_paid · {remaining_total 0, family, invoices, scanned_at}) — done ok 행은 다시 안 연다 · done error · skipped 행은 family · invoices 가 같으면 다시 안 연다(5 회는 EF 가 닫는다 · ful-4b 와 같은 모양) · 열린 행은 그대로
--        되돌아온 미수(따로 보는 갈래): Shopify PAID · paid_push_at 있음(IMS 가 Paid 로 바꾼 오더 · pay-2b 의 EF 가 적는다) · 지금 남은 돈 > 0 → 경고 shopify_paid_ims_owed(원소에 owed · 커질 때만 · 판정 461 모양) — Shopify 는 되돌릴 명령이 없다(pay-0 · 직원이 손님 연락을 판단) · paid_push_at 이 없는 PAID(직원이 Shopify 에서 표시)는 468 의 paid_in_shopify 몫이라 여기서 안 본다
--     ③ shop_order_warn 재발행 — 코드 목록에 shopify_paid_ims_owed ④ cron 등록 없음(pay-2b 에서 EF 가 mark_paid 를 집게 된 뒤 같이 — 지금 ims-order-drain 의 거름 조건은 kind 를 안 보고 EF 는 order_edit 만 집어 mark_paid 열린 줄이 있으면 5 분마다 헛걸음)
--   ⚠️ 무접촉: EF · 화면(이름표 WARN_LBL · WEB_WARN 은 대화 Claude) · cron · shop_order_queue 표 · shop_order_requeue · shop_unshipped_scan · shop_order_ingest · IMS 결제 · 인보이스 · 실물 #1001 ~ #1012 · 60058 ~ 60065(스캔은 적용 뒤 cron 이 등록될 때까지 돌지 않는다)
--   검증: ~/asung/prompts/pay-2a-verify.sql(시험 적용 begin → rollback · 가짜 스토어 · so · 인보이스 · 결제 · 크레딧 · 직원 · 시퀀스 무접촉 · 전체 스캔은 savepoint 안에서 실제 행 md5 전후로)
--   적용: psql "$(cat ~/.asung-testdb-url)" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261014162538_pay_2a_mark_paid_scan.sql && supabase migration repair --status applied 20261014162538 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ ① 판정 함수 — 읽기만 · 화면 · 스캔이 같이 쓴다 ═══
create function public.shop_order_paid_state(p_shop_order_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_o    record;
  v_fam  uuid[];
  v_open text[];
  v_inv  jsonb;
  v_rem  numeric;
  v_n    int;
begin
  select o.id, o.so_id into v_o from public.shop_order o where o.id = p_shop_order_id;
  if v_o.id is null then raise exception 'Shop order not found'; end if;
  if v_o.so_id is null then
    return jsonb_build_object('family', '[]'::jsonb, 'open_sos', '[]'::jsonb, 'invoices', '[]'::jsonb, 'remaining_total', null, 'all_closed', false, 'all_paid', false, 'ready', false);
  end if;
  select coalesce(array_agg(f.id), '{}') into v_fam from public.shop_so_family(v_o.so_id) as f(id);
  select coalesce(array_agg(s.so_number order by s.so_number), '{}') into v_open from public.so s where s.id = any(v_fam) and s.status not in ('fulfilled', 'cancelled');
  select coalesce(jsonb_agg(jsonb_build_object('invoice_number', l.invoice_number, 'remaining', l.remaining) order by l.invoice_number), '[]'::jsonb), sum(l.remaining), count(*)
    into v_inv, v_rem, v_n
    from public.so_invoice_list l where l.so_ids && v_fam and l.status <> 'cancelled';
  return jsonb_build_object('family', to_jsonb(v_fam), 'open_sos', to_jsonb(v_open), 'invoices', v_inv, 'remaining_total', v_rem,
                            'all_closed', coalesce(array_length(v_open, 1), 0) = 0,
                            'all_paid', v_n > 0 and v_rem <= 0,
                            'ready', coalesce(array_length(v_open, 1), 0) = 0 and v_n > 0 and v_rem <= 0);
end;
$$;
revoke all on function public.shop_order_paid_state(uuid) from public, anon;
grant execute on function public.shop_order_paid_state(uuid) to authenticated;
comment on function public.shop_order_paid_state(uuid) is 'pay-2a 판정 449 · 469: 웹 오더가 「다 결제」인가 — 읽기만 · {family(shop_so_family so_id 들), open_sos(fulfilled · cancelled 아닌 so_number), invoices([{invoice_number, remaining}] · 살아 있는 인보이스 · so_invoice_list so_ids 겹침 · status ≠ cancelled), remaining_total(합 · 인보이스 없으면 null), all_closed, all_paid(인보이스 ≥ 1 이고 합 ≤ 0), ready(둘 다)} · 0 이 된 길은 묻지 않는다 · so 없으면 전부 false · 화면이 「왜 아직 Paid 가 아닌가」를 그릴 때도 쓴다(authenticated 실행 · definer · 읽기만)';

-- ═══ ② 스캔 — cron 용(등록은 pay-2b) · p_store_id 는 시험용 좁히기(null = 켜진 스토어 전부) ═══
create function public.shop_paid_scan(p_limit int default 200, p_store_id uuid default null) returns jsonb
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
       and exists (select 1 from public.shop_store st where st.id = so.store_id and st.is_active)
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
       and exists (select 1 from public.shop_store st where st.id = so.store_id and st.is_active)
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
revoke all on function public.shop_paid_scan(int, uuid) from public, anon, authenticated;
comment on function public.shop_paid_scan(int, uuid) is 'pay-2a 판정 449 · 469: cron 용 스캔(등록은 pay-2b · postgres · service_role) — created · so 있음 · Shopify 취소 아님 · 켜진 스토어 · Shopify 결제 상태 PENDING · PARTIALLY_PAID · EXPIRED · 없음인 오더마다 shop_order_paid_state 가 ready 면 shop_order_requeue(mark_paid · {remaining_total 0, family, invoices, scanned_at}) — done ok 는 다시 안 열고 done error · skipped 는 family · invoices 가 같으면 안 연다 · 열린 행은 그대로 · 따로: Shopify PAID 이고 paid_push_at 있는 오더의 남은 돈이 0 을 넘으면 경고 shopify_paid_ims_owed(원소 owed · 커질 때만) · p_store_id 는 시험용 좁히기(null = 전부) · 반환 {scanned, queued, warned_owed_again, nothing, at}';

-- ═══ ③ shop_order_warn 재발행 — ful-4a 20261014000000:104 ~ 120 바이트 복사 · 바꾼 줄 3(코드 목록 · 거부 문구 · comment) ═══
create or replace function public.shop_order_warn(p_shop_order_id uuid, p_code text, p_message text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_w jsonb;
begin
  if p_code not in ('fulfill_failed', 'fulfill_cut', 'fulfill_location_mismatch', 'fulfill_nothing_left', 'pickup_failed', 'tracking_fix_failed', 'pickup_not_sent', 'refund_due', 'order_edit_failed', 'shopify_qty_removed', 'shopify_paid_ims_owed') then
    raise exception 'shop_order_warn: code % is not one of fulfill_failed, fulfill_cut, fulfill_location_mismatch, fulfill_nothing_left, pickup_failed, tracking_fix_failed, pickup_not_sent, refund_due, order_edit_failed, shopify_qty_removed, shopify_paid_ims_owed — nothing was saved', p_code;
  end if;
  update public.shop_order set warnings = warnings || jsonb_build_array(jsonb_build_object('code', p_code, 'message', nullif(btrim(coalesce(p_message, '')), ''), 'at', now()))
   where id = p_shop_order_id
  returning warnings into v_w;
  if not found then raise exception 'shop_order_warn: shop_order % not found — nothing was saved', p_shop_order_id; end if;
  return jsonb_build_object('shop_order_id', p_shop_order_id, 'code', p_code, 'warnings', jsonb_array_length(v_w));
end;
$$;
comment on function public.shop_order_warn(uuid, text, text) is 'ful-2a · 1b · 1c · 4a · pay-2a: shop_order.warnings 에 경고 한 줄 {code, message, at} 을 더한다 — 한 문장(warnings || …) · 코드 열(fulfill_failed · fulfill_cut · fulfill_location_mismatch · fulfill_nothing_left · pickup_failed · tracking_fix_failed · pickup_not_sent · refund_due · order_edit_failed · shopify_qty_removed · shopify_paid_ims_owed) · service_role 만(EF) · definer 창구 안에서도';

-- ═══ 자기 검사 — 설계대로 들어앉았는지(아니면 멈춘다 · 트랜잭션 안이라 되돌아간다) ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if to_regprocedure('public.shop_order_paid_state(uuid)') is null then v_bad := v_bad || ' paid_state'; end if;
  if to_regprocedure('public.shop_paid_scan(int, uuid)') is null then v_bad := v_bad || ' scan'; end if;
  if not has_function_privilege('authenticated', 'public.shop_order_paid_state(uuid)', 'execute') or has_function_privilege('anon', 'public.shop_order_paid_state(uuid)', 'execute') then v_bad := v_bad || ' paid_state(acl)'; end if;
  if has_function_privilege('authenticated', 'public.shop_paid_scan(int, uuid)', 'execute') or has_function_privilege('anon', 'public.shop_paid_scan(int, uuid)', 'execute') or has_function_privilege('public', 'public.shop_paid_scan(int, uuid)', 'execute') then v_bad := v_bad || ' scan(acl)'; end if;
  select p.prosrc into v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_order_warn';
  if v_src not like '%''shopify_paid_ims_owed''%' or v_src not like '%shopify_qty_removed, shopify_paid_ims_owed — nothing was saved%' then v_bad := v_bad || ' warn(body)'; end if;
  if has_function_privilege('authenticated', 'public.shop_order_warn(uuid, text, text)', 'execute') or has_function_privilege('anon', 'public.shop_order_warn(uuid, text, text)', 'execute') then v_bad := v_bad || ' warn(acl)'; end if;
  if (select count(*) from pg_constraint where conname = 'shop_order_queue_kind_ck' and pg_get_constraintdef(oid) like '%mark_paid%') <> 1 then v_bad := v_bad || ' queue_kind'; end if;
  if to_regprocedure('public.shop_order_requeue(uuid, text, jsonb)') is null or to_regprocedure('public.shop_so_family(uuid)') is null then v_bad := v_bad || ' helpers'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_order' and column_name = 'paid_push_at') <> 1 then v_bad := v_bad || ' paid_push_at(pay-1a)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM469', message = format('STOP - pay-2a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
