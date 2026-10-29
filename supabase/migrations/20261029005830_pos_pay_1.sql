-- pos-pay-1 (2026-10-28 · 판정 863 · 지시서 ~/asung/prompts/pos-pay-1.md · 이견 1 ~ 12 Caleb 「그대로」) — POS 에서 받은 돈을 계산대 직원이 Finish 전에 취소하는 창구 + 그 판매의 결제 목록 읽기
--   왜: 동료 요청(2026-10-28) 「POS 에서 캐시나 기타 방식으로 돈을 받을 때 실수로 잘못 넣는 경우가 있는데 뒤로 돌아갈 방법이 없다 · 부분 결제(캐시 얼마 + debit 얼마)인데 전액 결제로 보인다 · 결제한 내역이 다 보였으면」
--   판정 863 [Caleb 「A」]: POS 계산대 직원(sales 쓰기가 있는 사람 누구나)이 Finish 전의 그 판매에 받은 결제를 취소할 수 있다 → 다시 받기
--     · Finish 뒤(인보이스가 나간 뒤)의 결제 · POS 밖의 결제는 지금처럼 so_payment_void(manager · 사유 필수 · §17 판정 6) — 이 창구는 그 길을 넓히지 않는다
--     · 기각 B(지금처럼 manager 만 · 화면에 단추만): 바쁜 시간에 매니저가 없으면 계산대가 멈춘다 · 취소 기록(누가 · 언제 · 사유)은 남긴다
--   ① so_pos_payment_cancel(p_payment_id uuid, p_note text default null) returns jsonb — definer · 첫 줄 ims_require_write(sales) · 역할 문 없음(863) · 창고 문 없음(이견 3 · Caleb 「경계를 두지 않는다」 · 돈을 넣는 so_payment_add 와 같은 문)
--      문 · 잠금 순서(손님 행 → 결제 행 for update) · 거부(이미 취소 · opening · refund · 대상 판매가 정확히 하나가 아님 · pos·counter 아님 · Finish 뒤(fulfilled · cancelled) · 살아 있는 alloc(인보이스 번호 함께) · 손님 잔액 0 밑) · 쓰기 한 줄(status voided · voided_at · voided_by · void_note · updated_by · row_count 1)은 so_payment_void 의 몸을 복사(이견 4 · so_payment_void 는 무접촉)
--      Finish 전 = so.status in (draft, confirmed)(이견 2 · so_pos_reopen 이 confirmed → draft 로 되돌려도 결제는 남는다 · POS 길은 draft → confirmed → fulfilled)
--      사유 = void_note 에 'POS: ' || 글 · 비면 'Cancelled at POS before Finish'(이견 8 · 별도 칸 없음 — Payments 화면이 void_note 로 「계산대 취소」 를 읽는다)
--      ⚠️ 살아 있는 alloc 은 실제로 생길 수 있다(이견 6): so_payment_attach(sales) 가 POS 예치금을 그 손님의 다른 열린 인보이스에 손으로 붙일 수 있다 — 거부 글에 인보이스 번호를 넣어 매니저가 Payments 에서 바로 뗀다
--   ② so_pos_payment_list(p_so_id uuid) returns jsonb — stable · definer · 첫 줄 ims_can_view(sales) 또는 ims_can_write(master)(so_backorder_ready 꼴) · 그 판매를 대상으로 한 결제 전부(취소된 것도 · 화면이 회색으로) · 줄마다 paid_on · created_at · method · amount · reference · created_by_name · status · voided_at · voided_by_name · void_note · kind · currency_code(이견 7 · 10 — 화면이 「Cash 20 · Debit 30」 을 이 줄로 그린다)
--   「같은 날만」 제한 없음(이견 5 · 판정에 없는 막기를 더하지 않는다 · 묵은 Park 판매는 so_pos_open_list 의 stale 이 보인다)
--   ⚠️ 무접촉: so_payment_void · so_payment_add · so_pos_complete · so_pos_finish · so_payment_attach · so_payment_alloc_add(끝 do 블록이 prosrc md5 를 단언) · 표 · 칸 · 정책 변화 없음
--   컷오버 날 지우기(cutover-delete): 새 표 · 시퀀스 · 칸 없음 → 지우는 순서 변화 없음(함수만)
--   원본 md5(DB prosrc · 2026-10-28 테스트 DB · 마지막 정의 파일과 바이트 일치): so_payment_void 48097c4f430652d14e95522ec6ca2269(ar-2 재발행 판 · ar-2 머리의 82accf2f… 는 그 이전 판) · so_payment_add 8e10ba47e637922f368ce8aad6e72a60 · so_pos_complete 0b4e2e4b81ca44d7174dab51e2097cde · so_pos_finish 8b2a18c847d5a7d51ca75013a3da4373 · so_payment_attach 6be722c21b47de19129f7f6544e8244f · so_payment_alloc_add 9779fc2a60b6e110c00e2990b875e5ab
--   검증: supabase/tests/pos_pay_1.sql(시험 적용 begin → rollback · 가짜 손님 · 제품 · 직원 넷 · POS 판매 둘(cash + debit) · 다른 판매 · fulfilled · warehouse · 두 판매에 걸친 결제 · refund · opening · alloc · 권한 · 미리 보기 deposit · so_payment_void 그대로 · 시퀀스 되돌림)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261029005830_pos_pay_1.sql && supabase migration repair --status applied 20261029005830 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ 0) 기대는 마지막 정의인가 — 다르면 멈춘다(이 창구는 so_payment_void 의 몸을 복사했다 · 그쪽이 바뀌었으면 복사본도 다시 본다) ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_void') is distinct from '48097c4f430652d14e95522ec6ca2269' then v_bad := v_bad || ' so_payment_void'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_add') is distinct from '8e10ba47e637922f368ce8aad6e72a60' then v_bad := v_bad || ' so_payment_add'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_complete') is distinct from '0b4e2e4b81ca44d7174dab51e2097cde' then v_bad := v_bad || ' so_pos_complete'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_finish') is distinct from '8b2a18c847d5a7d51ca75013a3da4373' then v_bad := v_bad || ' so_pos_finish'; end if;
  if to_regprocedure('public.so_pos_payment_cancel(uuid, text)') is not null or to_regprocedure('public.so_pos_payment_list(uuid)') is not null then v_bad := v_bad || ' (so_pos_payment_cancel or so_pos_payment_list already exists)'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM863', message = format('STOP - pos-pay-1 expects the last definitions as of 2026-10-28; these differ:%s - nothing was changed', v_bad); end if;
end $$;

-- ═══ 1) so_pos_payment_cancel — 계산대 취소(판정 863) ═══
create function public.so_pos_payment_cancel(p_payment_id uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_p       public.so_payment%rowtype;
  v_so      public.so%rowtype;
  v_note    text;
  v_n       int;
  v_targets int;
  v_so_id   uuid;
  v_recv    numeric;
  v_inv     text;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 863 · 역할 문 없음 · 창고 문 없음(so_payment_add 와 같은 문)
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  v_note := case when v_note is null then 'Cancelled at POS before Finish' else 'POS: ' || v_note end;
  select * into v_p from public.so_payment p where p.id = p_payment_id;
  if not found then raise exception 'Payment not found — nothing was saved'; end if;
  perform 1 from public.customer c where c.id = v_p.customer_id for update;   -- 손님 행 잠금(so_payment_void 와 같은 순서)
  select * into v_p from public.so_payment p where p.id = p_payment_id for update;
  if v_p.status <> 'active' then raise exception 'This payment was already cancelled — nothing was saved'; end if;
  if v_p.method = 'opening' then raise exception 'This is the opening balance carried forward from the previous system — it cannot be cancelled here — nothing was saved'; end if;
  if v_p.kind <> 'payment' then raise exception 'This is a refund, not a payment — a manager voids it on the Payments screen — nothing was saved'; end if;
  select count(*) into v_targets from public.so_payment_order o where o.payment_id = v_p.id;
  if v_targets <> 1 then raise exception 'This payment is not tied to exactly one sale (% sale(s)) — a manager voids it on the Payments screen — nothing was saved', v_targets; end if;
  select o.so_id into v_so_id from public.so_payment_order o where o.payment_id = v_p.id;
  select * into v_so from public.so s where s.id = v_so_id;
  if v_so.channel not in ('pos', 'counter') then raise exception 'Sale % is a % order, not a POS sale — a manager voids the payment on the Payments screen — nothing was saved', v_so.so_number, v_so.channel; end if;
  if v_so.status not in ('draft', 'confirmed') then raise exception 'Sale % is % — after Finish, a manager voids the payment on the Payments screen — nothing was saved', v_so.so_number, v_so.status; end if;
  select string_agg(i.invoice_number, ', ' order by i.invoice_number) into v_inv
    from public.so_payment_alloc a join public.so_invoice i on i.id = a.invoice_id
   where a.payment_id = v_p.id and a.voided_at is null;
  if v_inv is not null then raise exception 'Part of this payment was applied to invoice % on the Payments screen — a manager detaches it there first — nothing was saved', v_inv; end if;
  select b.received into v_recv from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id;   -- 활성 alloc 0 이므로 남은 금액 = amount(so_payment_void 와 같은 검사)
  if coalesce(v_recv, 0) - v_p.amount < 0 then
    raise exception 'Cancelling this payment would put the customer''s % balance below zero (% on account, refunds already paid out) — nothing was saved', v_p.currency_code, coalesce(v_recv, 0);
  end if;
  update public.so_payment set status = 'voided', voided_at = now(), voided_by = v_staff, void_note = v_note, updated_by = v_staff where id = v_p.id and status = 'active';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Payment was not cancelled — it may have been changed by someone else just now — nothing was saved'; end if;
  return jsonb_build_object('payment_id', v_p.id, 'so_id', v_so.id, 'so_number', v_so.so_number, 'amount', v_p.amount, 'method', v_p.method, 'status', 'voided', 'note', v_note,
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id));
end;
$$;
comment on function public.so_pos_payment_cancel(uuid, text) is '⭐ POS 결제 취소(판정 863 · pos-pay-1) — definer · 첫 줄 ims_require_write(sales) · 역할 문 없음 · 창고 문 없음(so_payment_add 와 같은 문) · 그 결제가 대상으로 한 판매가 정확히 하나이고 channel pos|counter 이고 status draft|confirmed(Finish 전)일 때만 · 거부: 이미 취소 · opening · refund · 대상 0 또는 둘 이상 · POS 밖 채널 · Finish 뒤(fulfilled · cancelled) · 살아 있는 alloc(인보이스 번호 안내) · 손님 잔액 0 밑 → 「Payments 화면에서 manager 가 void」 안내 · 쓰기 = so_payment_void 와 같은 update 한 줄(status voided · voided_at · voided_by · void_note · updated_by) · void_note = ''POS: '' || p_note · 비면 ''Cancelled at POS before Finish'' · 반환 {payment_id, so_id, so_number, amount, method, status, note, balance} — 화면은 판매를 다시 읽는다(so_detail · so_pos_finish 미리 보기)';
revoke all on function public.so_pos_payment_cancel(uuid, text) from public, anon, service_role;
grant execute on function public.so_pos_payment_cancel(uuid, text) to authenticated;

-- ═══ 2) so_pos_payment_list — 그 판매의 결제 목록(취소된 것도) ═══
create function public.so_pos_payment_list(p_so_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_so public.so%rowtype;
begin
  if not (public.ims_can_view('sales') or public.ims_can_write('master')) then
    raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission';
  end if;
  select * into v_so from public.so s where s.id = p_so_id;
  if not found then raise exception 'Order not found'; end if;
  return jsonb_build_object(
    'so_id', v_so.id, 'so_number', v_so.so_number, 'status', v_so.status, 'channel', v_so.channel,
    'payments', (select coalesce(jsonb_agg(jsonb_build_object(
                   'payment_id', p.id, 'kind', p.kind, 'paid_on', p.paid_on, 'created_at', p.created_at, 'method', p.method, 'amount', p.amount, 'currency_code', p.currency_code,
                   'reference', p.reference, 'created_by_name', cs.name, 'status', p.status, 'voided_at', p.voided_at, 'voided_by_name', vs.name, 'void_note', p.void_note,
                   'targets', (select count(*) from public.so_payment_order o2 where o2.payment_id = p.id))
                   order by p.created_at, p.id), '[]'::jsonb)
                   from public.so_payment_order o
                   join public.so_payment p on p.id = o.payment_id
                   left join public.ims_staff cs on cs.id = p.created_by
                   left join public.ims_staff vs on vs.id = p.voided_by
                  where o.so_id = v_so.id),
    'active_total', (select coalesce(sum(p.amount), 0) from public.so_payment_order o join public.so_payment p on p.id = o.payment_id where o.so_id = v_so.id and p.status = 'active' and p.kind = 'payment'));
end;
$$;
comment on function public.so_pos_payment_list(uuid) is '⭐ POS 판매의 결제 목록(pos-pay-1 · 이견 7 · 10) — 읽기(stable · definer · 첫 줄 ims_can_view(sales) 또는 ims_can_write(master)) · 그 판매를 대상(so_payment_order)으로 한 결제 전부 — 취소된 것도 함께(화면이 회색으로) · 줄마다 paid_on · created_at · method · amount · currency_code · reference · created_by_name · status · voided_at · voided_by_name · void_note · targets(이 결제가 대상으로 한 판매 수 · 1 이 아니면 계산대 취소 불가) · active_total = 살아 있는 payment 금액 합(⚠️ 다른 인보이스에 붙은 몫은 빼지 않는다 — 「이 판매에 얼마 쓰이나」 는 so_pos_finish 미리 보기의 deposit)';
revoke all on function public.so_pos_payment_list(uuid) from public, anon, service_role;
grant execute on function public.so_pos_payment_list(uuid) to authenticated;

-- ═══ 착지 — 창구 둘 · acl · 무접촉 여섯 ═══
do $$
declare v_bad text := '';  v_acl text;
begin
  if to_regprocedure('public.so_pos_payment_cancel(uuid, text)') is null then v_bad := v_bad || ' so_pos_payment_cancel missing'; end if;
  if to_regprocedure('public.so_pos_payment_list(uuid)') is null then v_bad := v_bad || ' so_pos_payment_list missing'; end if;
  select array_to_string(proacl, ',') into v_acl from pg_proc where oid = to_regprocedure('public.so_pos_payment_cancel(uuid, text)');
  if v_acl is distinct from 'postgres=X/postgres,authenticated=X/postgres' then v_bad := v_bad || format(' cancel acl %s', coalesce(v_acl, '(null)')); end if;
  select array_to_string(proacl, ',') into v_acl from pg_proc where oid = to_regprocedure('public.so_pos_payment_list(uuid)');
  if v_acl is distinct from 'postgres=X/postgres,authenticated=X/postgres' then v_bad := v_bad || format(' list acl %s', coalesce(v_acl, '(null)')); end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_void') is distinct from '48097c4f430652d14e95522ec6ca2269' then v_bad := v_bad || ' so_payment_void touched'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_add') is distinct from '8e10ba47e637922f368ce8aad6e72a60' then v_bad := v_bad || ' so_payment_add touched'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_complete') is distinct from '0b4e2e4b81ca44d7174dab51e2097cde' then v_bad := v_bad || ' so_pos_complete touched'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_finish') is distinct from '8b2a18c847d5a7d51ca75013a3da4373' then v_bad := v_bad || ' so_pos_finish touched'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_attach') is distinct from '6be722c21b47de19129f7f6544e8244f' then v_bad := v_bad || ' so_payment_attach touched'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_alloc_add') is distinct from '9779fc2a60b6e110c00e2990b875e5ab' then v_bad := v_bad || ' so_payment_alloc_add touched'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM863', message = 'pos-pay-1 landing check failed:' || v_bad; end if;
  raise notice 'pos-pay-1 landed: so_pos_payment_cancel(uuid, text) · so_pos_payment_list(uuid) · authenticated only · six untouched';
end $$;
