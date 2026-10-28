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
-- fc-2b2 — fc_book_pending_set: 202 를 받은 순간 Freightcom 발송 id 를 pending 행에 (2026-10-28 · fc-2c 를 짓다 드러난 빈자리)
--   왜: EF book 은 POST /shipment → 202 {id} → GET /shipment/{id} 다시 묻기 → fc_book_save 순서인데, 25 초 안에 끝나지 않으면 book_poll {booking_id} 가 이어 받아야 한다 —
--      Freightcom 발송 id 가 DB 에 없으면 화면이 들고 다녀야 하고(잃으면 돈이 든 예약이 IMS 에 안 남는다 · 10 분 뒤 abandoned) · fc_booking 은 service_role 에 select 만이라 EF 가 REST 로 못 쓴다 ⇒ 창구 하나
--   fc_book_pending_set(p_booking_id, p_freightcom_shipment_id, p_request) — service_role 만 · pending 행만 · id 와 실제 보낸 몸(payment_method_id 가 든 것)을 적는다 · fc_book_save(2b) 는 그대로(응답의 id 로 덮는다 · 같다)
--   무접촉: fc_booking 표 · 2b 창구 일곱 · 첫 문장 = guard-test-only.sql 바이트 복사 · 컷오버 변화 없음
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261028233000_fc_2b2_book_pending_set.sql && supabase migration repair --status applied 20261028233000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028233000_fc_2b2_book_pending_set.sql -f supabase/tests/fc_2b2_check.sql  (안에서 fc_2b 사본 193)
create function public.fc_book_pending_set(p_booking_id uuid, p_freightcom_shipment_id text, p_request jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_b public.fc_booking%rowtype;
begin
  if not public.doc_is_service() then raise exception 'fc_book_pending_set is for the freight service only — nothing was saved'; end if;
  select * into v_b from public.fc_booking b where b.id = p_booking_id for update;
  if not found then raise exception 'Booking % not found — nothing was saved', p_booking_id; end if;
  if v_b.status <> 'pending' then raise exception 'Booking #% is already % — nothing was saved', v_b.attempt, v_b.status; end if;
  if nullif(btrim(p_freightcom_shipment_id), '') is null then raise exception 'Freightcom shipment id is empty — nothing was saved'; end if;
  update public.fc_booking set freightcom_shipment_id = btrim(p_freightcom_shipment_id), request = coalesce(p_request, request) where id = v_b.id returning * into v_b;
  return jsonb_build_object('booking_id', v_b.id, 'attempt', v_b.attempt, 'status', v_b.status, 'freightcom_shipment_id', v_b.freightcom_shipment_id, 'account', v_b.account);
end;
$$;
revoke all on function public.fc_book_pending_set(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.fc_book_pending_set(uuid, text, jsonb) to service_role;
comment on function public.fc_book_pending_set(uuid, text, jsonb) is 'fc-2b2: EF book 이 POST /shipment 202 {id} 를 받은 순간 — pending 행에 Freightcom 발송 id 와 실제 보낸 몸(payment_method_id 포함)을 적는다(service_role 만 · pending 만) · book_poll {booking_id} 가 이 id 로 GET /shipment/{id} 를 이어 묻는다 · fc_book_save 가 응답의 id 로 덮는다(같다)';
do $$
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_book_pending_set') <> 1 then raise exception 'fc-2b2 landing check failed: function count'; end if;
  if has_function_privilege('authenticated', 'public.fc_book_pending_set(uuid, text, jsonb)', 'execute') or has_function_privilege('anon', 'public.fc_book_pending_set(uuid, text, jsonb)', 'execute') or not has_function_privilege('service_role', 'public.fc_book_pending_set(uuid, text, jsonb)', 'execute') then raise exception 'fc-2b2 landing check failed: acl'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_book_prepare', 'fc_book_save', 'fc_book_cancel_prepare', 'fc_book_cancel_save', 'fc_label_add', 'fc_label_get', 'fc_booking_for_shipment')) <> 7 then raise exception 'fc-2b2 landing check failed: 2b windows'; end if;
  raise notice 'fc-2b2 landing OK — fc_book_pending_set (service_role)';
end $$;
