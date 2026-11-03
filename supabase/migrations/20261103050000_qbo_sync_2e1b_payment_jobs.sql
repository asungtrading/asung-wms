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
-- qbo-sync-2e-1b — QuickBooks 결제 보내기(DB): 일감 · 몸 · 트리거 · 지문 · claim · done · preview · list · retry · 백필 · (가) Balance 가드 자리 (판정 978 ~ 983 · 988 · 991 · 992′ · 2026-11-02 밤 집 · 지시서 ~/asung/prompts/qbo-sync-2e-1.md · §0 이견 답 A-1 ~ A-16 · B ① ~ ④ Caleb · sandbox B-4 980 (나) · B-6 void 꼴)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용 + supabase migration repair --status applied 20261103050000 · ⚠️ db push 쓰지 않는다 · 1a(20261103020000) · 1a2(20261103040000) 뒤
-- 무엇:
--   ⓪ 재발행 원본 가드 — claim · done · preview · doc · list · retry 의 DB prosrc md5 가 마지막 정의 파일(2d1 · 2c1)과 다르면 멈춘다(11-02 밤 대조 · 1a · perf ① · ②-a 뒤에도 같음)
--   ① 표: qbo_job kind(+ payment · payment_void) · ims_kind(+ payment) · pair · 칸 fingerprint / qbo_txn kind(+ payment) · type(+ Payment) · pair · 칸 fingerprint · source(sent | matched — matched 는 1d 이월 짝이 쓴다) · inv_config qbo_send_payments_enabled off(스위치 · cron 62 는 1c 뒤 Caleb 등록)
--   ② 지문 qbo_payment_fingerprint — md5(amount · paid_on · method · account_code · currency · 정렬한 (invoice_id, amount)) · 활성 · kind payment · opening 아님 · 붙임 ≥ 1 아니면 null(= 「QBO 에 없어야 한다」)
--   ③ 몸 qbo_payment_body(978 · 980 (나) · 983 · 984 · 986 · 988 · 991) — CustomerRef = 청구처(so_payment.customer_id) 짝(없으면 needs 손님 일감) · TxnDate paid_on(미래 그대로) · TotalAmt amount · CurrencyRef · PaymentMethodRef(짝 없으면 failed — credit_card 는 사람 짝 전까지) · DepositToAccountRef = account_code 짝 · PaymentRefNum left(reference, 21) · PrivateNote 「IMS payment <uuid>」 · Line = 활성 붙임마다 LinkedTxn(QBO Invoice Id 는 qbo_txn 에서만 · 열린 인보이스 일감이면 wait_job · 일감 없음 · skipped · 이월 · since 전 짝 없음은 failed 글) · 일부만 붙었으면 UnappliedAmt(경고) · check_lines(= (가) EF 가 POST 직전 Invoice Balance 를 읽는다 · 1c) · lookup(unknown 열쇠 · 1c)
--      qbo_payment_void_body — qbo_txn 의 Id · SyncToken · sparse true(EF 는 payment?operation=update&include=void · 1c)
--   ④ qbo_payment_sync(결제 · 사람) — A-10 상태 표: 보낸 적 없음(fp 있으면 queued · 열린 일감 queued · blocked 는 그대로 · failed 는 fp 바뀌면 되살림 · fp 없으면 skipped · sending · unknown 이면 void 를 그 일감 뒤에 blocked(2b1 꼴) · 다시 보내기는 done 의 reconcile 이) / QBO 에 서 있음(fp 같으면 아무것도 · 다르면 payment_void queued + fp 있으면 payment blocked_by void) / QBO 쪽 void 됨(fp 있으면 payment queued)
--      트리거 둘: so_payment_alloc AFTER INSERT OR UPDATE OF voided_at — DEFERRABLE INITIALLY DEFERRED(발행 안의 auto_deposit · auto_balance · 취소 때 void 가 커밋 때 한 번에) · so_payment AFTER UPDATE OF status(void · POS 취소) · opening · 연결 없음 조용히 · 오류 삼킴(failed 일감 흔적)
--   ⑤ qbo_payment_requeue(p_invoice_id) — 1d 이월 짝이 선 인보이스의 결제 일감을 만들고 failed 를 되살린다 · qbo_payment_backfill() — 활성 · opening 아님 · 붙임 ≥ 1 · 붙은 인보이스 전부 sale ∧ since 뒤 · 일감 · 거래 짝 없음 → queued(A-3 · 이월에 붙은 3 건은 1d 의 requeue) · 이 파일 끝에서 한 번(NOTICE)
--   ⑥ 재발행: claim(kinds 8 · 몸 둘 · 지문을 일감에 · jobs 에 fingerprint · check_lines · lookup) · preview(몸 둘 · check_lines) · doc(payment 행) · list(kinds 8 · ims_name · txn 짝) · retry(A-4: payment 는 활성 · 붙임 ≥ 1 · void 는 QBO 에 서 있을 때만) · done(옛 9 인자 drop → 10 인자 p_unapplied_amt · payment → qbo_txn Payment + 지문 + 대조 · payment_void → voided_at · 끝에 reconcile)
--   ⑦ grant: 새 함수 전부 grant 0(claim · done 이 부른다 · 트리거) · done 은 service_role · claim · preview · list · retry 는 create or replace 라 ACL 그대로
-- 안 하는 것: EF(1c — WRITE_ENTITIES payment · include=void 가지 · SEND_KINDS 8 · kinds 인자 · (가) Balance 읽기 · unknown 풀기 · deno) · cron 62 등록(1c 뒤 · ops/cron.sql 기록은 1c) · 이월 짝 · matched 행(1d) · 크레딧 붙임(2e-2) · 환불 · 받아 둔 돈만 있는 결제(2e-3) · 화면(qbo-send.html payments 탭 · Preview Line · 대화 Claude)
-- 거래 표 FK: 0(ims_id 다형) — 컷오버 지우는 순서 무변 · 검증: supabase/tests/qbo_sync_2e1b_check.sql(-v mig 시험 · 적용 뒤 -v mig 없이)

-- ═══ ⓪ 재발행 원본 가드 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_claim')   is distinct from '5b0939eaab6b20932533ef7836ae606c' then v_bad := v_bad || ' qbo_job_claim'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_done')    is distinct from 'fadf6ff42a63cb7b941d43c27dd448c7' then v_bad := v_bad || ' qbo_job_done'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_preview') is distinct from '4b9ca19b989d929aba2a81bccdb9f899' then v_bad := v_bad || ' qbo_job_preview'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_doc')     is distinct from 'a50ee4ecca48555c0b3eb15d7b3defdc' then v_bad := v_bad || ' qbo_job_doc'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_list')    is distinct from '93ffb77ba0554c042a32b717492636bf' then v_bad := v_bad || ' qbo_job_list'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_retry')   is distinct from 'e97db1c0d2d8508a7f9a81ec50273a98' then v_bad := v_bad || ' qbo_job_retry'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_done') <> 1 then v_bad := v_bad || ' qbo_job_done(overloads)'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'so_payment_method_ck') !~ '''paypal''' then v_bad := v_bad || ' so_payment_method_ck(1a not applied)'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current bodies first — nothing was changed', v_bad; end if;
end $$;

-- ═══ ① 표 · 설정 키 ═══
alter table public.qbo_job drop constraint qbo_job_kind_ck;
alter table public.qbo_job add  constraint qbo_job_kind_ck check (kind in ('customer', 'item', 'invoice', 'credit', 'invoice_void', 'credit_void', 'payment', 'payment_void'));
alter table public.qbo_job drop constraint qbo_job_ims_kind_ck;
alter table public.qbo_job add  constraint qbo_job_ims_kind_ck check (ims_kind in ('customer', 'product', 'charge', 'invoice', 'credit', 'payment'));
alter table public.qbo_job drop constraint qbo_job_pair_ck;
alter table public.qbo_job add  constraint qbo_job_pair_ck check (ims_kind = case kind when 'customer' then 'customer' when 'invoice' then 'invoice' when 'invoice_void' then 'invoice' when 'credit' then 'credit' when 'credit_void' then 'credit'
                                                                                        when 'payment' then 'payment' when 'payment_void' then 'payment' else ims_kind end
                                                                and (kind <> 'item' or ims_kind in ('product', 'charge')));
alter table public.qbo_job add column fingerprint text;
comment on column public.qbo_job.fingerprint is 'qbo-sync-2e-1b: 결제 일감 — claim 이 몸을 만들 때의 IMS 지문(qbo_payment_fingerprint) · done 이 qbo_txn.fingerprint 로 옮긴다 · 다른 kind 는 null';
alter table public.qbo_txn drop constraint qbo_txn_kind_ck;
alter table public.qbo_txn add  constraint qbo_txn_kind_ck check (ims_kind in ('invoice', 'credit', 'payment'));
alter table public.qbo_txn drop constraint qbo_txn_type_ck;
alter table public.qbo_txn add  constraint qbo_txn_type_ck check (qbo_type in ('Invoice', 'CreditMemo', 'Payment'));
alter table public.qbo_txn drop constraint qbo_txn_pair_ck;
alter table public.qbo_txn add  constraint qbo_txn_pair_ck check (qbo_type = case ims_kind when 'invoice' then 'Invoice' when 'credit' then 'CreditMemo' else 'Payment' end);
alter table public.qbo_txn add column fingerprint text, add column source text not null default 'sent' constraint qbo_txn_source_ck check (source in ('sent', 'matched'));
comment on column public.qbo_txn.fingerprint is 'qbo-sync-2e-1b: 결제 짝 — QBO Payment 를 만들 때의 IMS 지문(claim → qbo_job.fingerprint → done) · 트리거가 현재 지문과 견줘 다르면 void + 다시 보내기(978) · 인보이스 · 크레딧은 null';
comment on column public.qbo_txn.source is 'qbo-sync-2e-1b: sent = IMS 가 보냈다 · matched = 1d 이월 짝(Cin7 이 보낸 QBO Invoice 를 IMS 이월 인보이스에 짝 지음 · 982) — 결제 줄 · 크레딧 960 이 둘을 같이 본다';
insert into public.inv_config (key, value, note) values
  ('qbo_send_payments_enabled', 'off', 'qbo-sync-2e-1b 판정 988: 결제(payment · payment_void) 자동 보내기 cron 62 ims-qbo-send-payments 의 스위치 on | off — qbo_send_enabled(971 · 인보이스 · 크레딧은 북키퍼가 고른다)와 별개 · 켜는 것은 Caleb(credit_card 짝 → 첫 결제 손 Send → on)')
on conflict (key) do nothing;

-- ═══ ② 지문 ═══
create function public.qbo_payment_fingerprint(p_payment_id uuid) returns text
  language sql stable security definer set search_path = public, pg_temp
as $$
  select case when p.status = 'active' and p.kind = 'payment' and p.method <> 'opening'
                   and exists (select 1 from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null)
              then md5(concat_ws('|', p.amount::text, p.paid_on::text, p.method, p.account_code, p.currency_code,
                                 (select string_agg(a.invoice_id::text || ':' || a.amount::text, ',' order by a.invoice_id) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null)))
         end
    from public.so_payment p where p.id = p_payment_id;
$$;
comment on function public.qbo_payment_fingerprint(uuid) is 'qbo-sync-2e-1b 판정 978(속 · grant 0): 결제의 IMS 지문 — md5(amount · paid_on · method · account_code · currency · 정렬한 (invoice_id, amount)) · 활성 · kind payment · opening 아님 · 활성 붙임 ≥ 1 일 때만 · 아니면 null = 「QuickBooks 에 없어야 한다」(void) · claim 이 일감에 · done 이 qbo_txn 에 · 트리거가 견준다';

-- ═══ ③ 몸 둘 ═══
create function public.qbo_payment_body(p_payment_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_p public.so_payment%rowtype; v_c public.customer%rowtype; v_cust_ref text; v_meth text; v_dep text; v_ref text; v_label text;
        v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_lines jsonb := '[]'::jsonb; v_checks jsonb := '[]'::jsonb; v_applied numeric := 0; v_n int := 0;
        v_wait uuid; v_wait_inv text; a record; v_t public.qbo_txn%rowtype; v_ij public.qbo_job%rowtype; v_body jsonb;
begin
  select * into v_p from public.so_payment p where p.id = p_payment_id;
  if v_p.id is null then raise exception 'No IMS payment % — nothing was sent', p_payment_id; end if;
  v_label := coalesce(nullif(btrim(coalesce(v_p.reference, '')), ''), 'of ' || v_p.paid_on::text || ' ' || v_p.amount::text);
  if v_p.kind <> 'payment' then raise exception 'Payment % is a refund — refunds go to QuickBooks in a later step (2e-3) — nothing was sent', v_label; end if;
  if v_p.method = 'opening' then raise exception 'Payment % is money carried forward from the previous system — it is already in QuickBooks (786) — nothing was sent', v_label; end if;
  if v_p.status <> 'active' then raise exception 'Payment % is voided — nothing to send (a void job takes care of QuickBooks) — nothing was sent', v_label; end if;
  if nullif(btrim(coalesce(v_p.currency_code, '')), '') is null then raise exception 'Payment % has no currency code — nothing was sent', v_label; end if;
  select * into v_c from public.customer c where c.id = v_p.customer_id;
  -- 980 (나) · sandbox B-4: CustomerRef = 청구처(so_payment.customer_id) 짝 · 짝 없으면 need(손님 일감 · 부모는 open_or_add 가) · 자식 매장 인보이스는 Line 으로 붙는다
  select l.qbo_id into v_cust_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_p.customer_id::text;
  if v_cust_ref is null then v_needs := v_needs || jsonb_build_object('kind', 'customer', 'ims_id', v_p.customer_id::text, 'name', v_c.name); end if;
  -- 983 · 986: 수단 짝(credit_card 는 사람이 Settings → QuickBooks matching 에서 하나로 짝 짓기 전까지 failed)
  select l.qbo_id into v_meth from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'payment_method' and l.ims_id = v_p.method;
  if v_meth is null then raise exception 'Payment method "%" has no QuickBooks match — link it under Settings → QuickBooks matching → Payment methods — nothing was sent', v_p.method; end if;
  -- 984 · 986 · 993: Deposit To = 결제에 적힌 계좌 그대로(qbo_account_ref 가 거부 글) · 늘 보낸다(안 보내면 QBO 가 Undeposited Funds 로 채운다 — sandbox B-4)
  v_dep := public.qbo_account_ref(v_p.account_code, 'deposit account of payment ' || v_label);
  -- 줄 = 활성 붙임마다 · 인보이스의 QBO Id 는 qbo_txn(sent · matched)에서만 · 988: 붙은 인보이스가 모두 QBO 에 간 뒤에 간다
  for a in select x.invoice_id, x.amount, i.invoice_number, i.kind as inv_kind, i.issued_on
             from public.so_payment_alloc x join public.so_invoice i on i.id = x.invoice_id where x.payment_id = v_p.id and x.voided_at is null order by i.invoice_number, x.created_at loop
    select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = a.invoice_id::text and t.voided_at is null;
    if v_t.id is not null then
      v_lines := v_lines || jsonb_build_object('Amount', a.amount, 'LinkedTxn', jsonb_build_array(jsonb_build_object('TxnId', v_t.qbo_id, 'TxnType', 'Invoice')));
      v_checks := v_checks || jsonb_build_object('invoice_number', a.invoice_number, 'qbo_invoice_id', v_t.qbo_id, 'amount', a.amount);
      v_applied := v_applied + a.amount; v_n := v_n + 1;
    elsif a.inv_kind = 'opening' then
      raise exception 'Invoice % was carried over from the previous system and has no QuickBooks match yet — match it under Settings → QuickBooks → Opening invoices; this payment then goes by itself — nothing was sent', a.invoice_number;
    elsif not public.qbo_send_since_ok(a.issued_on) then
      raise exception 'Invoice % was issued before the QuickBooks start date and has no QuickBooks match — match it under Settings → QuickBooks → Opening invoices — nothing was sent', a.invoice_number;
    else
      select * into v_ij from public.qbo_job j where j.realm_id = v_realm and j.kind = 'invoice' and j.ims_kind = 'invoice' and j.ims_id = a.invoice_id::text order by j.created_at desc, j.id desc limit 1;
      if v_ij.id is null then raise exception 'Invoice % has no QuickBooks job — send the invoice first — nothing was sent', a.invoice_number; end if;
      if v_ij.state = 'skipped' then raise exception 'Invoice % was skipped — skip this payment too, or retry the invoice first — nothing was sent', a.invoice_number; end if;
      if v_ij.state = 'sent' then raise exception 'Invoice % job is sent but no QuickBooks transaction is on file — check qbo_txn by hand — nothing was sent', a.invoice_number; end if;
      if v_wait is null then v_wait := v_ij.id; v_wait_inv := a.invoice_number; end if;                                                   -- 첫 미발송 인보이스 하나에 blocked(② 가 풀면 다음 바퀴에 다시 본다)
    end if;
  end loop;
  if v_n = 0 and v_wait is null then raise exception 'Payment % has no invoice applied — money on account goes to QuickBooks in a later step (2e-3) — nothing was sent', v_label; end if;
  v_ref := nullif(btrim(coalesce(v_p.reference, '')), '');
  if v_ref is not null and length(v_ref) > 21 then v_warn := array_append(v_warn, format('reference "%s" cut to 21 characters for QuickBooks', v_ref)); v_ref := left(v_ref, 21); end if;
  if v_wait is null and v_p.amount - v_applied > 0 then v_warn := array_append(v_warn, format('%s %s not applied to an invoice — stays on the customer account in QuickBooks (UnappliedAmt)', v_p.currency_code, v_p.amount - v_applied)); end if;
  if v_p.paid_on > public.ims_today() then v_warn := array_append(v_warn, format('post-dated: QuickBooks payment dated %s (991)', v_p.paid_on)); end if;
  v_body := jsonb_strip_nulls(jsonb_build_object(
    'CustomerRef', case when v_cust_ref is null then null else jsonb_build_object('value', v_cust_ref) end,
    'TxnDate', v_p.paid_on, 'TotalAmt', v_p.amount, 'CurrencyRef', jsonb_build_object('value', v_p.currency_code),
    'PaymentMethodRef', jsonb_build_object('value', v_meth), 'DepositToAccountRef', jsonb_build_object('value', v_dep),
    'PaymentRefNum', v_ref, 'PrivateNote', 'IMS payment ' || v_p.id::text, 'Line', v_lines));
  return jsonb_build_object('kind', 'payment', 'ims_kind', 'payment', 'ims_id', v_p.id::text, 'name', coalesce(v_ref, 'Payment ' || v_p.paid_on::text || ' ' || v_p.amount::text), 'doc_number', v_ref, 'customer_id', v_p.customer_id,
    'body', v_body, 'needs', v_needs, 'wait_job', v_wait, 'wait_invoice', v_wait_inv, 'warnings', to_jsonb(v_warn), 'line_count', v_n,
    'totals', jsonb_build_object('amount', v_p.amount, 'applied', v_applied, 'unapplied', v_p.amount - v_applied),
    'fingerprint', public.qbo_payment_fingerprint(v_p.id), 'check_lines', v_checks,
    'lookup', jsonb_build_object('customer_ref', v_cust_ref, 'txn_date', v_p.paid_on, 'total_amt', v_p.amount, 'private_note', 'IMS payment ' || v_p.id::text));
end;
$$;
comment on function public.qbo_payment_body(uuid) is 'qbo-sync-2e-1b 판정 978 · 980 (나) · 983 · 984 · 986 · 988 · 991(속 · grant 0 · claim · preview 가 부른다): IMS 결제 → QBO Payment 만들기 몸 — CustomerRef = 청구처 짝(없으면 needs) · TxnDate paid_on · TotalAmt amount · CurrencyRef · PaymentMethodRef(짝 없으면 예외 = failed) · DepositToAccountRef(account_code 짝) · PaymentRefNum left(reference, 21) · PrivateNote 「IMS payment <uuid>」 · Line = 활성 붙임 → LinkedTxn Invoice(qbo_txn 의 Id · 열린 인보이스 일감이면 wait_job · 일감 없음 · skipped · 이월 · since 전 짝 없음은 예외) · 돌려주는 것 = { body · needs · wait_job · wait_invoice · warnings · totals{amount · applied · unapplied} · fingerprint · check_lines[{invoice_number · qbo_invoice_id · amount}](= (가) EF 가 POST 직전 Balance 를 읽는 줄) · lookup(unknown 열쇠) }';

create function public.qbo_payment_void_body(p_payment_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_t public.qbo_txn%rowtype; v_p public.so_payment%rowtype; v_label text;
begin
  select * into v_p from public.so_payment p where p.id = p_payment_id;
  if v_p.id is null then raise exception 'No IMS payment % — nothing was sent', p_payment_id; end if;
  v_label := coalesce(nullif(btrim(coalesce(v_p.reference, '')), ''), 'of ' || v_p.paid_on::text || ' ' || v_p.amount::text);
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'payment' and t.ims_id = p_payment_id::text;
  if v_t.id is null then raise exception 'Payment % was never sent to QuickBooks — nothing to void', v_label; end if;
  if v_t.voided_at is not null then raise exception 'Payment % (QuickBooks #%) is already voided — nothing was sent', v_label, v_t.qbo_id; end if;
  return jsonb_build_object('kind', 'payment_void', 'ims_kind', 'payment', 'ims_id', p_payment_id::text, 'name', coalesce(nullif(btrim(coalesce(v_p.reference, '')), ''), 'Payment ' || v_p.paid_on::text || ' ' || v_p.amount::text), 'doc_number', v_t.doc_number, 'qbo_id', v_t.qbo_id,
    'body', jsonb_strip_nulls(jsonb_build_object('Id', v_t.qbo_id, 'SyncToken', v_t.sync_token, 'sparse', true)), 'needs', '[]'::jsonb,
    'warnings', case when v_t.sync_token is null then '["no SyncToken on file — the sender reads the payment first"]'::jsonb else '[]'::jsonb end,
    'lookup', jsonb_build_object('qbo_id', v_t.qbo_id, 'private_note', 'IMS payment ' || p_payment_id::text));
end;
$$;
comment on function public.qbo_payment_void_body(uuid) is 'qbo-sync-2e-1b 판정 978 · sandbox B-6(속 · grant 0): QBO Payment void 몸 — qbo_txn 의 Id · SyncToken · sparse true(EF 1c 는 POST payment?operation=update&include=void · SyncToken 없으면 읽는다) · 보낸 적 없음 · 이미 void 면 예외(failed)';

-- ═══ ④ 상태 맞추기(트리거 · done 의 reconcile · 백필 · requeue 가 부른다) · 트리거 둘 ═══
create function public.qbo_payment_sync(p_payment_id uuid, p_by uuid) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton); v_p public.so_payment%rowtype; v_fp text; v_t public.qbo_txn%rowtype; v_pj public.qbo_job%rowtype; v_vj public.qbo_job%rowtype; v_act text := 'none'; v_vid uuid;
begin
  if v_realm is null then return jsonb_build_object('action', 'no_connection'); end if;
  select * into v_p from public.so_payment p where p.id = p_payment_id;
  if v_p.id is null or v_p.kind <> 'payment' or v_p.method = 'opening' then return jsonb_build_object('action', 'not_applicable'); end if;   -- 환불은 2e-3 · 이월 받아 둔 돈은 보내지 않는다(341 · A-8)
  v_fp := public.qbo_payment_fingerprint(v_p.id);
  select * into v_t  from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'payment' and t.ims_id = v_p.id::text;
  select * into v_pj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'payment'      and j.ims_kind = 'payment' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_vj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'payment_void' and j.ims_kind = 'payment' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  if v_t.id is null then                                                                                                               -- 보낸 적 없다
    if v_pj.id is null then
      if v_fp is not null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'payment', 'payment', v_p.id::text, 'queued', p_by)
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'queued';
      end if;
    elsif v_pj.state in ('queued', 'blocked', 'failed') then
      if v_fp is null then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'payment voided or fully detached before sending'), 2000), updated_by = p_by where j.id = v_pj.id;
        v_act := 'skipped';
      elsif v_pj.state = 'failed' and v_fp is distinct from v_pj.fingerprint then
        update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: the payment changed after it failed'), 2000), updated_by = p_by where j.id = v_pj.id;
        v_act := 'requeued';
      end if;                                                                                                                          -- queued · blocked 는 그대로(claim 이 그때의 상태로 몸을 다시 만든다)
    elsif v_pj.state in ('sending', 'unknown') then                                                                                   -- 닿았는지 모른다 → void 를 그 일감 뒤에(2b1 cancel 꼴) · 다시 보내기는 done 의 reconcile 이 쌓는다
      if v_fp is distinct from v_pj.fingerprint and v_vj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'payment_void', 'payment', v_p.id::text, 'blocked', v_pj.id, p_by, 'changed while sending — void after the send settles')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'void_after_send';
      end if;
    end if;
  elsif v_t.voided_at is null then                                                                                                     -- QBO 에 서 있다
    if v_fp is not distinct from v_t.fingerprint then                                                                                 -- IMS = QBO 그대로(떼었다가 똑같이 다시 붙인 경우) → 아직 안 나간 void 는 거둔다 · 나가는 중이면 다시 보내기를 그 뒤에
      if v_vj.id is not null and v_vj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'payment restored to what QuickBooks has — void not needed'), 2000), updated_by = p_by where j.id = v_vj.id;
        return jsonb_build_object('action', 'void_cancelled', 'fingerprint', v_fp);
      elsif v_vj.id is not null and v_pj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'payment', 'payment', v_p.id::text, 'blocked', v_vj.id, p_by, 'sent again after the void that is under way')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        return jsonb_build_object('action', 'resend_after_void', 'fingerprint', v_fp);
      end if;
      return jsonb_build_object('action', 'same', 'fingerprint', v_fp);
    end if;
    if v_vj.id is null then
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note)
      values (v_realm, 'payment_void', 'payment', v_p.id::text, 'queued', p_by, case when v_fp is null then 'payment voided or fully detached — void in QuickBooks' else 'payment changed — void, then send again' end)
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_vid;
      if v_vid is null then select j.id into v_vid from public.qbo_job j where j.realm_id = v_realm and j.kind = 'payment_void' and j.ims_kind = 'payment' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc limit 1; end if;
    else v_vid := v_vj.id; end if;
    if v_fp is not null then
      if v_pj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'payment', 'payment', v_p.id::text, 'blocked', v_vid, p_by, 'sent again after the void')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      elsif v_pj.state in ('queued', 'failed') then
        update public.qbo_job j set state = 'blocked', blocked_by = v_vid, claimed_at = null, next_at = now(), request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'waits for the void of the earlier QuickBooks payment'), 2000), updated_by = p_by where j.id = v_pj.id;
      end if;
      v_act := 'void_and_resend';
    else
      if v_pj.id is not null and v_pj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'payment voided or fully detached — only the void goes'), 2000), updated_by = p_by where j.id = v_pj.id;
      end if;
      v_act := 'void';
    end if;
  else                                                                                                                                 -- QBO 쪽은 void 됐다
    if v_fp is not null then
      if v_pj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'payment', 'payment', v_p.id::text, 'queued', p_by, 'sent again after the void')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'resend';
      elsif v_pj.state = 'failed' and v_fp is distinct from v_pj.fingerprint then
        update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: the payment changed after it failed'), 2000), updated_by = p_by where j.id = v_pj.id;
        v_act := 'requeued';
      end if;
    elsif v_pj.id is not null and v_pj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'payment voided or fully detached before sending'), 2000), updated_by = p_by where j.id = v_pj.id;
      v_act := 'skipped';
    end if;
  end if;
  return jsonb_build_object('action', v_act, 'fingerprint', v_fp);
end;
$$;
comment on function public.qbo_payment_sync(uuid, uuid) is 'qbo-sync-2e-1b 판정 978 · 988 · A-10(속 · grant 0): 결제 하나의 QBO 일감을 IMS 상태(지문)에 맞춘다 — 보낸 적 없음: fp 있으면 payment queued · 열린 queued · blocked 그대로 · failed 는 fp 바뀌면 되살림 · fp 없으면 skipped · sending · unknown 이면 payment_void 를 그 일감 뒤에(2b1 꼴) / QBO 에 서 있음: fp 같으면 아무것도(안 나간 void 일감이 있으면 거둔다 · 나가는 중이면 다시 보내기를 그 뒤에) · 다르면 payment_void queued + fp 있으면 payment blocked_by void(없으면 void 만 · 열린 payment 는 skipped) / QBO 쪽 void 됨: fp 있으면 payment queued · 환불 · 이월 받아 둔 돈 · 연결 없음은 not_applicable · 돌려주는 것 = { action · fingerprint } · 부르는 곳 = 트리거 둘 · done 의 reconcile · 백필 · requeue';

create function public.qbo_job_on_payment_alloc() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_by uuid := coalesce(new.voided_by, new.updated_by, new.created_by);
begin
  begin
    perform public.qbo_payment_sync(new.payment_id, v_by);
  exception when others then                                                                                                           -- 붙이기 · 떼기 · 발행 · 취소를 막지 않는다 — failed 일감으로 흔적
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff)
      select c.realm_id, 'payment', 'payment', new.payment_id::text, 'failed', left('could not queue: ' || sqlerrm, 2000), v_by from public.qbo_connection c where c.singleton
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$$;
comment on function public.qbo_job_on_payment_alloc() is 'qbo-sync-2e-1b: so_payment_alloc AFTER INSERT OR UPDATE OF voided_at — DEFERRABLE INITIALLY DEFERRED(발행 안의 auto_deposit · auto_balance · 취소 때 void 가 커밋 때 한 번에 보인다 · 행마다 불리지만 일감 넣기는 on conflict 로 한 번) → qbo_payment_sync · 오류는 삼켜 창구를 막지 않는다(failed 일감 흔적) · opening · 연결 없음은 sync 가 조용히';
create function public.qbo_job_on_payment_status() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_by uuid := coalesce(new.voided_by, new.updated_by);
begin
  if new.status is not distinct from old.status then return null; end if;
  begin
    perform public.qbo_payment_sync(new.id, v_by);
  exception when others then
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff)
      select c.realm_id, 'payment', 'payment', new.id::text, 'failed', left('could not queue: ' || sqlerrm, 2000), v_by from public.qbo_connection c where c.singleton
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$$;
comment on function public.qbo_job_on_payment_status() is 'qbo-sync-2e-1b: so_payment AFTER UPDATE OF status(so_payment_void · so_pos_payment_cancel — 붙임이 먼저 떼이므로 떼기 트리거가 이미 void 를 쌓았고 여기는 지문 같음으로 조용하다) → qbo_payment_sync · 오류는 삼킨다';
create constraint trigger so_payment_alloc_qbo after insert or update of voided_at on public.so_payment_alloc deferrable initially deferred for each row execute function public.qbo_job_on_payment_alloc();
create trigger so_payment_qbo_status after update of status on public.so_payment for each row execute function public.qbo_job_on_payment_status();

-- ═══ ⑤ requeue(1d 가 부른다) · 백필 ═══
create function public.qbo_payment_requeue(p_invoice_id uuid) returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare r record; v_n int := 0; v_num text;
begin
  select i.invoice_number into v_num from public.so_invoice i where i.id = p_invoice_id;
  for r in select distinct a.payment_id, p.created_by from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
            where a.invoice_id = p_invoice_id and a.voided_at is null and p.status = 'active' and p.kind = 'payment' and p.method <> 'opening' loop
    perform public.qbo_payment_sync(r.payment_id, r.created_by);
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: invoice ' || coalesce(v_num, '?') || ' is now matched in QuickBooks'), 2000)
     where j.kind = 'payment' and j.ims_kind = 'payment' and j.ims_id = r.payment_id::text and j.state = 'failed';
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function public.qbo_payment_requeue(uuid) is 'qbo-sync-2e-1b A-3(속 · grant 0 · 1d 이월 짝이 부른다): 이 인보이스에 붙은 활성 결제마다 qbo_payment_sync(일감 없으면 만든다) + failed 결제 일감을 queued 로(「no QuickBooks match」 로 실패했던 것) · 돌려주는 것 = 결제 수';

create function public.qbo_payment_backfill() returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare r record; v_n int := 0; v_r jsonb;
begin
  if not exists (select 1 from public.qbo_connection c where c.singleton) then return 0; end if;
  for r in select p.id, p.created_by from public.so_payment p
            where p.status = 'active' and p.kind = 'payment' and p.method <> 'opening'
              and exists (select 1 from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null)
              and not exists (select 1 from public.so_payment_alloc a join public.so_invoice i on i.id = a.invoice_id where a.payment_id = p.id and a.voided_at is null and (i.kind = 'opening' or not public.qbo_send_since_ok(i.issued_on)))
              and not exists (select 1 from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id = p.id::text)
              and not exists (select 1 from public.qbo_txn t where t.ims_kind = 'payment' and t.ims_id = p.id::text)
            order by p.paid_on, p.created_at loop
    v_r := public.qbo_payment_sync(r.id, r.created_by);
    if v_r->>'action' = 'queued' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end;
$$;
comment on function public.qbo_payment_backfill() is 'qbo-sync-2e-1b A-3 · 판정 981(속 · grant 0): 적용 때 한 번 — 활성 · opening 아님 · 활성 붙임 ≥ 1 · 붙은 인보이스 전부 sale ∧ since 뒤 · 일감(어느 상태든) · 거래 짝 없는 결제를 queued 로 · 이월 인보이스에 붙은 결제는 1d 의 qbo_payment_requeue 가 · 연결 없으면 0';


-- ═══ ⑥ 재발행 — claim · preview · doc · list · retry(2d1 바이트 + 바뀐 줄) · done(2c1 바이트 + payment 가지 · 옛 9 인자 drop → 10 인자) ═══
create or replace function public.qbo_job_claim(p_limit int default 15, p_kinds text[] default array['customer', 'item'], p_job_ids uuid[] default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_stale int; v_unblocked int; v_ids uuid[]; v_j public.qbo_job%rowtype; v_open public.qbo_job%rowtype; v_b jsonb; v_rows jsonb := '[]'::jsonb; v_failed int := 0; v_blocked int := 0; v_waiting int := 0; v_last uuid; v_cust uuid; v_nj jsonb; e jsonb;
  v_kinds text[] := coalesce(p_kinds, array['customer', 'item']);
  v_pick uuid[] := (select array_agg(distinct x) from unnest(p_job_ids) x where x is not null);                                       -- 2d1: 고른 id(중복 · null 제거) · null 이면 옛 길(가장 오래된 것부터 p_limit)
  v_needs jsonb := '[]'::jsonb; v_req jsonb := '[]'::jsonb; v_r record;
begin
  if not public.doc_is_service() then raise exception 'qbo_job_claim is for the send worker only — nothing was read'; end if;
  if not (v_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void']) or coalesce(array_length(v_kinds, 1), 0) = 0 then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void (got %)', v_kinds; end if;
  if p_job_ids is not null and coalesce(array_length(v_pick, 1), 0) = 0 then raise exception 'job_ids must name at least one job — nothing was read'; end if;
  if coalesce(array_length(v_pick, 1), 0) > 200 then raise exception 'job_ids may name at most 200 jobs in one call (got %) — nothing was read', array_length(v_pick, 1); end if;
  -- ① 멈춘 sending(EF 가 도중에 죽었다 · QBO 에 닿았는지 모른다) → unknown(mail_claim 꼴 · 자동 재전송 금지 · 다음 send 가 이름 · DocNumber 로 조회해 푼다)
  update public.qbo_job j set state = 'unknown', claimed_at = null,
         last_error = left(coalesce(j.last_error || ' · ', '') || format('stale: still sending %s after claim (attempt %s) — QuickBooks may or may not have it', date_trunc('second', now() - j.claimed_at), j.attempts), 2000)
   where j.realm_id = v_realm and j.state = 'sending' and j.claimed_at < now() - interval '10 minutes';
  get diagnostics v_stale = row_count;
  -- ② 부모가 보내졌으면 자식을 연다(손님 → 자식 손님 · need → 인보이스 · 인보이스 → void · 인보이스 → 크레딧)
  update public.qbo_job j set state = 'queued', next_at = now() from public.qbo_job p where j.realm_id = v_realm and j.state = 'blocked' and p.id = j.blocked_by and p.state = 'sent';
  get diagnostics v_unblocked = row_count;
  -- ③ 잡기 — queued → sending(for update skip locked · 10 분 임대) · EF 가 아는 kind 만 · [2d1] p_job_ids 가 있으면 그 id 만(한도는 id 수)
  with pick as (
    select j.id from public.qbo_job j where j.realm_id = v_realm and j.state = 'queued' and j.next_at <= now() and j.kind = any (v_kinds) and (v_pick is null or j.id = any (v_pick))
     order by j.created_at, j.id limit case when v_pick is null then greatest(1, least(coalesce(p_limit, 15), 50)) else array_length(v_pick, 1) end for update skip locked),
  upd as (update public.qbo_job j set state = 'sending', claimed_at = now(), attempts = j.attempts + 1 from pick where j.id = pick.id returning j.id)
  select coalesce(array_agg(u.id), '{}') into v_ids from upd u;
  -- ④ 몸은 다음 문장에서 일감마다(같은 문장 안의 읽기는 update 전 행을 본다) · 몸이 안 만들어지면 그 일감만 failed · needs 가 있으면 need 일감을 쌓고 이 일감은 blocked(이견 11) · [2d1] need 일감을 need_jobs 로 돌려준다 · blocked_by 는 손님 need 우선
  for v_j in select * from public.qbo_job j where j.id = any (v_ids) order by j.created_at, j.id loop
    begin
      v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                           when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                           when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid)
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid) end;   -- 2e-1b payment · payment_void   -- 2c1 credit · credit_void
      if v_b is null then raise exception 'kind % has no body', v_j.kind; end if;
      if v_b->>'parent_customer_id' is not null then raise exception 'parent customer is not in QuickBooks yet — send the parent first (job was not blocked: parent link removed?)'; end if;
      if jsonb_array_length(coalesce(v_b->'needs', '[]'::jsonb)) > 0 then
        v_last := null; v_cust := null;
        for e in select x from jsonb_array_elements(v_b->'needs') x loop
          v_nj := public.qbo_job_open_or_add(e->>'kind', e->>'ims_id', v_j.by_staff);                                                 -- 몸이 거부하면(941 · 활성 Sku 사람 짝 …) 예외 → 이 일감 failed + 그 까닭
          v_last := (v_nj->>'id')::uuid;
          if e->>'kind' = 'customer' then v_cust := v_last; end if;
          v_needs := v_needs || jsonb_build_object('job_id', v_nj->>'id', 'kind', v_nj->>'kind', 'ims_kind', v_nj->>'ims_kind', 'ims_id', v_nj->>'ims_id', 'state', v_nj->>'state', 'name', e->>'name', 'existing', coalesce((v_nj->>'existing')::boolean, false), 'for_job', v_j.id, 'parent_job', v_nj->'parent_job'->>'id');
          if v_nj->'parent_job'->>'id' is not null then
            v_needs := v_needs || jsonb_build_object('job_id', v_nj->'parent_job'->>'id', 'kind', 'customer', 'ims_kind', 'customer', 'ims_id', v_nj->'parent_job'->>'ims_id', 'state', v_nj->'parent_job'->>'state', 'name', null, 'existing', coalesce((v_nj->'parent_job'->>'existing')::boolean, false), 'for_job', v_nj->>'id', 'parent_job', null);
          end if;
        end loop;
        update public.qbo_job j set state = 'blocked', blocked_by = coalesce(v_cust, v_last), claimed_at = null,
               warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')) || array[format('waiting for %s QuickBooks record(s) to be created first', jsonb_array_length(v_b->'needs'))], ' · '), '')
         where j.id = v_j.id;
        v_blocked := v_blocked + 1;
        continue;
      end if;
      if nullif(v_b->>'wait_job', '') is not null then                                                                                 -- 2c1 판정 960: 크레딧은 자기 IMS 인보이스가 QBO 에 들어간 뒤 — 그 인보이스 일감 뒤에 선다(② 가 sent 때 푼다)
        update public.qbo_job j set state = 'blocked', blocked_by = (v_b->>'wait_job')::uuid, claimed_at = null,
               warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')) || array[format('waiting for invoice %s to reach QuickBooks first', coalesce(v_b->>'wait_invoice', '?'))], ' · '), '')
         where j.id = v_j.id;
        v_waiting := v_waiting + 1;
        continue;
      end if;
      update public.qbo_job j set warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')), ' · '), ''), fingerprint = v_b->>'fingerprint' where j.id = v_j.id;   -- 2e-1b: 보낼 때의 IMS 상태(지문)를 일감에 · done 이 qbo_txn 으로 옮긴다
      v_rows := v_rows || jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'ims_kind', v_j.ims_kind, 'ims_id', v_j.ims_id, 'attempt', v_j.attempts, 'request_id', v_j.request_id,
                                             'name', coalesce(v_b->>'display_name', v_b->>'name'), 'name_alt', v_b->>'name_alt', 'sku', v_b->>'sku', 'doc_number', v_b->>'doc_number', 'qbo_id', v_b->>'qbo_id',
                                             'body', v_b->'body', 'warnings', v_b->'warnings', 'totals', v_b->'totals',
                                             'fingerprint', v_b->>'fingerprint', 'check_lines', v_b->'check_lines', 'lookup', v_b->'lookup');   -- 2e-1b: 결제 = (가) Balance 가드 줄 · unknown 열쇠
    exception when others then
      update public.qbo_job j set state = 'failed', claimed_at = null, last_error = left(sqlerrm, 2000) where j.id = v_j.id;
      v_failed := v_failed + 1;
    end;
  end loop;
  -- ⑤ [2d1] 고른 id 마다 결과 — 잡힌 것은 ④ 뒤의 상태로(sending = claimed · blocked = 까닭 · failed = 글) · 못 잡은 것은 왜
  if v_pick is not null then
    for v_r in select x.id, j.state, j.kind, j.warning, j.last_error, j.next_at, j.realm_id from unnest(v_pick) x(id) left join public.qbo_job j on j.id = x.id loop
      if v_r.state = 'blocked' and v_r.realm_id = v_realm and not (v_r.id = any (v_ids)) then                                       -- 이미 blocked 인 일감을 다시 골랐다 → 기다리는 열린 일감(부모 blocked_by + 몸의 needs)을 need_jobs 로(EF 가 다음 바퀴에 같이 잡는다 · 거래 종류는 EF 가 안 잡는다 = 960)
        select * into v_j from public.qbo_job j where j.id = v_r.id;
        select * into v_open from public.qbo_job j where j.id = v_j.blocked_by and j.state not in ('sent', 'skipped');
        if v_open.id is not null then v_needs := v_needs || jsonb_build_object('job_id', v_open.id, 'kind', v_open.kind, 'ims_kind', v_open.ims_kind, 'ims_id', v_open.ims_id, 'state', v_open.state, 'name', null, 'existing', true, 'for_job', v_j.id, 'parent_job', null); end if;
        begin
          v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                               when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                               when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid)
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid) end;   -- 2e-1b payment · payment_void
          for e in select x from jsonb_array_elements(coalesce(v_b->'needs', '[]'::jsonb)) x
                   union all select jsonb_build_object('kind', 'customer', 'ims_id', v_b->>'parent_customer_id', 'name', null) where v_b->>'parent_customer_id' is not null loop
            select * into v_open from public.qbo_job j where j.realm_id = v_realm and j.kind = e->>'kind' and j.ims_id = e->>'ims_id' and j.state not in ('sent', 'skipped') and j.id is distinct from v_j.blocked_by order by j.created_at limit 1;
            if v_open.id is not null then v_needs := v_needs || jsonb_build_object('job_id', v_open.id, 'kind', v_open.kind, 'ims_kind', v_open.ims_kind, 'ims_id', v_open.ims_id, 'state', v_open.state, 'name', e->>'name', 'existing', true, 'for_job', v_j.id, 'parent_job', null); end if;
            v_open := null;
          end loop;
        exception when others then null;                                                                                           -- 몸이 거부해도 requested 의 까닭(warning)은 그대로 · needs 만 모른다
        end;
      end if;
      v_req := v_req || jsonb_build_object('job_id', v_r.id, 'kind', v_r.kind, 'state', v_r.state,
        'result', case when v_r.state is null or v_r.realm_id is distinct from v_realm then 'not_found'
                       when v_r.id = any (v_ids) then case v_r.state when 'sending' then 'claimed' when 'blocked' then 'blocked' when 'failed' then 'failed' else v_r.state end
                       when v_r.state <> 'queued' then 'not_queued'
                       when not (v_r.kind = any (v_kinds)) then 'wrong_kind'
                       when v_r.next_at > now() then 'not_due' else 'locked' end,
        'reason', case when v_r.state is null or v_r.realm_id is distinct from v_realm then 'no such job'
                       when v_r.id = any (v_ids) then case v_r.state when 'blocked' then v_r.warning when 'failed' then v_r.last_error end
                       when v_r.state <> 'queued' then format('the job is %s — not sent', v_r.state) || case v_r.state when 'blocked' then ' (' || coalesce(v_r.warning, 'waiting for another job') || ')' when 'failed' then ' — retry it first' when 'unknown' then ' — retry it with a note after checking QuickBooks' when 'skipped' then ' — retry it first' when 'sending' then ' (another send is working on it)' else '' end
                       when not (v_r.kind = any (v_kinds)) then format('kind %s is not sent by this worker', v_r.kind)
                       when v_r.next_at > now() then format('the job is scheduled for %s', v_r.next_at) else 'another send holds the job — try again in a moment' end);
    end loop;
  end if;
  return jsonb_build_object('realm_id', v_realm, 'kinds', to_jsonb(v_kinds), 'picked', case when v_pick is null then null else to_jsonb(v_pick) end, 'recovered_unknown', v_stale, 'unblocked', v_unblocked, 'claimed', coalesce(array_length(v_ids, 1), 0), 'body_failed', v_failed, 'blocked_for_needs', v_blocked, 'blocked_for_invoice', v_waiting,
                            'need_jobs', v_needs, 'requested', v_req, 'jobs', v_rows);
end;
$$;
create or replace function public.qbo_job_preview(p_job uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_j public.qbo_job%rowtype; v_b jsonb; v_err text; v_needs jsonb := '[]'::jsonb; e jsonb; v_open public.qbo_job%rowtype; v_wait public.qbo_job%rowtype; v_parent public.qbo_job%rowtype; v_blocked jsonb; v_wait_j jsonb;
begin
  select * into v_j from public.qbo_job j where j.id = p_job and j.realm_id = v_realm;
  if v_j.id is null then raise exception 'Job % not found — nothing to preview', p_job; end if;
  begin
    v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                         when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                         when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid)
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid) end;   -- 2e-1b payment · payment_void
    if v_b is null then raise exception 'kind % has no body', v_j.kind; end if;
  exception when others then
    v_err := left(sqlerrm, 2000); v_b := null;
  end;
  -- needs(손님 · Item 을 먼저 만들어야 한다) — 열린 일감이 있으면 그 id · state · 없으면 null(send 가 만든다) · 손님 몸의 부모(parent_customer_id)도 need 로
  if v_b is not null then
    for e in select x from jsonb_array_elements(coalesce(v_b->'needs', '[]'::jsonb)) x
             union all select jsonb_build_object('kind', 'customer', 'ims_id', v_b->>'parent_customer_id', 'name', (select c.name from public.customer c where c.id::text = v_b->>'parent_customer_id')) where v_b->>'parent_customer_id' is not null loop
      select * into v_open from public.qbo_job j where j.realm_id = v_realm and j.kind = e->>'kind' and j.ims_id = e->>'ims_id' and j.state not in ('sent', 'skipped') order by j.created_at limit 1;
      v_needs := v_needs || jsonb_build_object('kind', e->>'kind', 'ims_id', e->>'ims_id', 'name', e->>'name', 'job_id', v_open.id, 'job_state', v_open.state, 'job_error', v_open.last_error);
      v_open := null;
    end loop;
    if nullif(v_b->>'wait_job', '') is not null then
      select * into v_wait from public.qbo_job j where j.id = (v_b->>'wait_job')::uuid;
      v_wait_j := jsonb_build_object('job_id', v_wait.id, 'kind', v_wait.kind, 'state', v_wait.state, 'invoice', v_b->>'wait_invoice', 'reason', format('waiting for invoice %s to reach QuickBooks first — send it too', coalesce(v_b->>'wait_invoice', '?')));
    end if;
  end if;
  if v_j.blocked_by is not null then
    select * into v_parent from public.qbo_job j where j.id = v_j.blocked_by;
    v_blocked := jsonb_build_object('job_id', v_parent.id, 'kind', v_parent.kind, 'state', v_parent.state, 'doc', public.qbo_job_doc(v_parent.ims_kind, v_parent.ims_id), 'last_error', v_parent.last_error);
  end if;
  return jsonb_build_object(
    'job', jsonb_build_object('id', v_j.id, 'kind', v_j.kind, 'ims_kind', v_j.ims_kind, 'ims_id', v_j.ims_id, 'state', v_j.state, 'attempts', v_j.attempts, 'qbo_id', v_j.qbo_id, 'qbo_name', v_j.qbo_name, 'last_error', v_j.last_error, 'warning', v_j.warning, 'note', v_j.note, 'created_at', v_j.created_at, 'sent_at', v_j.sent_at, 'by_name', (select s.name from public.ims_staff s where s.id = v_j.by_staff)),
    'doc', public.qbo_job_doc(v_j.ims_kind, v_j.ims_id),
    'name', coalesce(v_b->>'display_name', v_b->>'name'), 'doc_number', v_b->>'doc_number', 'body', v_b->'body', 'totals', v_b->'totals', 'warnings', coalesce(v_b->'warnings', '[]'::jsonb), 'line_count', (v_b->>'line_count')::int,
    'needs', v_needs, 'wait', v_wait_j, 'blocked_by', v_blocked, 'error', v_err, 'check_lines', v_b->'check_lines', 'fingerprint', v_b->>'fingerprint',   -- 2e-1b
    'sendable', (v_err is null and jsonb_array_length(v_needs) = 0 and v_wait_j is null and v_j.state = 'queued'),
    'preview_only', true);
end;
$$;
create or replace function public.qbo_job_doc(p_ims_kind text, p_ims_id text) returns jsonb
  language sql stable security definer set search_path = public, pg_temp
as $$
  select case p_ims_kind
    when 'invoice' then (select jsonb_build_object('doc_number', i.invoice_number, 'name', i.bill_to_name, 'customer_id', i.bill_to_customer_id, 'currency', i.currency_code, 'total', i.total, 'doc_date', i.issued_on, 'doc_status', i.status)
                           from public.so_invoice i where i.id::text = p_ims_id)
    when 'credit' then (select jsonb_build_object('doc_number', c.credit_number, 'name', (select cu.name from public.customer cu where cu.id = c.customer_id), 'customer_id', c.customer_id, 'currency', c.currency_code, 'total', c.total, 'doc_date', c.issued_on, 'doc_status', c.status)
                          from public.so_credit c where c.id::text = p_ims_id)
    when 'customer' then (select jsonb_build_object('doc_number', null, 'name', c.name, 'customer_id', c.id, 'currency', c.currency_code, 'total', null, 'doc_date', null, 'doc_status', case when c.is_active then 'active' else 'inactive' end)
                            from public.customer c where c.id::text = p_ims_id)
    when 'product' then (select jsonb_build_object('doc_number', p.sku, 'name', p.name, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', case when p.is_active then 'active' else 'inactive' end)
                           from public.product p where p.id::text = p_ims_id)
    when 'payment' then (select jsonb_build_object('doc_number', p.reference, 'name', (select cu.name from public.customer cu where cu.id = p.customer_id), 'customer_id', p.customer_id, 'currency', p.currency_code, 'total', p.amount, 'doc_date', p.paid_on, 'doc_status', p.status)
                           from public.so_payment p where p.id::text = p_ims_id)   -- 2e-1b: 결제 = reference · 청구처 · 통화 · 금액 · 받은 날 · active | voided
    else jsonb_build_object('doc_number', p_ims_id, 'name', p_ims_id, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', null) end;
$$;
create or replace function public.qbo_job_list(p_state text default null, p_kinds text[] default null, p_from date default null, p_to date default null, p_q text default null, p_limit int default 50, p_offset int default 0) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if p_state is not null and p_state not in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped', 'open') then raise exception 'state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open (got %)', p_state; end if;
  if p_kinds is not null and (not (p_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void']) or coalesce(array_length(p_kinds, 1), 0) = 0) then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void (got %)', p_kinds; end if;
  if p_from is not null and p_to is not null and p_from > p_to then raise exception 'from % is after to % — nothing was read', p_from, p_to; end if;
  return (with base as (
      select j.id, j.kind, j.ims_kind, j.ims_id, j.state, j.attempts, j.next_at, j.claimed_at, j.blocked_by, j.qbo_id, j.qbo_name, j.sent_at, j.last_error, j.last_intuit_tid, j.warning, j.note, j.by_staff, j.created_at, j.updated_at,
             (j.created_at at time zone 'America/Toronto')::date as job_date,
             d.doc->>'doc_number' as doc_number, d.doc->>'name' as name, d.doc->>'currency' as currency, (d.doc->>'total')::numeric as total, (d.doc->>'doc_date')::date as doc_date, d.doc->>'doc_status' as doc_status,
             case j.ims_kind when 'invoice' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'credit' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'payment' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-1b
                             when 'product' then coalesce(d.doc->>'doc_number', '') || ' ' || coalesce(d.doc->>'name', '')
                             else coalesce(d.doc->>'name', j.ims_id) end as ims_name,
             (select s.name from public.ims_staff s where s.id = j.by_staff) as by_name,
             p.kind as blocked_kind, p.state as blocked_state, coalesce(pd.doc->>'doc_number', pd.doc->>'name', p.ims_id) as blocked_name,
             t.qbo_id as txn_qbo_id, t.total_amt as txn_total_amt, t.total_tax as txn_total_tax, t.mismatch as txn_mismatch, t.voided_at as txn_voided_at
      from public.qbo_job j
      cross join lateral (select public.qbo_job_doc(j.ims_kind, j.ims_id) as doc) d
      left join public.qbo_job p on p.id = j.blocked_by
      left join lateral (select public.qbo_job_doc(p.ims_kind, p.ims_id) as doc) pd on p.id is not null
      left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_kind = j.ims_kind and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit', 'payment')
      where j.realm_id = v_realm and (p_state is null or (p_state = 'open' and j.state not in ('sent', 'skipped')) or j.state = p_state)
        and (p_kinds is null or j.kind = any (p_kinds))
        and (p_from is null or (j.created_at at time zone 'America/Toronto')::date >= p_from) and (p_to is null or (j.created_at at time zone 'America/Toronto')::date <= p_to)),
    hit as (select b.* from base b where v_q is null or b.ims_name ilike '%' || v_q || '%' or coalesce(b.qbo_id, '') ilike '%' || v_q || '%' or coalesce(b.qbo_name, '') ilike '%' || v_q || '%')
    select jsonb_build_object('state', p_state, 'kinds', to_jsonb(p_kinds), 'from', p_from, 'to', p_to, 'q', v_q, 'total', (select count(*) from hit), 'limit', v_lim, 'offset', v_off,
      'counts', (select coalesce(jsonb_object_agg(x.state, x.n), '{}'::jsonb) from (select j.state, count(*) as n from public.qbo_job j where j.realm_id = v_realm group by j.state) x),
      'rows', coalesce((select jsonb_agg((to_jsonb(b) - 'rk' - 'k_old') order by b.rk, b.k_old, b.created_at desc) from (
                select h.*, case h.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end as rk, case when h.state in ('queued', 'blocked') then h.created_at end as k_old
                  from hit h order by 
                    case h.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end,
                    case when h.state in ('queued', 'blocked') then h.created_at end asc nulls last, h.created_at desc
                  limit v_lim offset v_off) b), '[]'::jsonb)));
end;
$$;
create or replace function public.qbo_job_retry(p_job uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_j public.qbo_job%rowtype; v_doc jsonb; v_open uuid;
begin
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('failed', 'unknown', 'skipped') then raise exception 'Only a failed or skipped job, or one whose result is unknown, can be sent again (this one is %) — nothing was saved', v_j.state; end if;
  if v_j.state = 'unknown' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say what you checked in QuickBooks (a note is required when the result was unknown) — nothing was saved'; end if;
  if v_j.kind = 'payment' and public.qbo_payment_fingerprint(v_j.ims_id::uuid) is null then                                             -- 2e-1b A-4: 결제 retry = 활성 · 붙임 ≥ 1 일 때만
    raise exception 'Payment % is voided or has no invoice applied — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce((select p.reference from public.so_payment p where p.id = v_j.ims_id::uuid), v_j.ims_id);
  end if;
  if v_j.kind = 'payment_void' and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = 'payment' and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-1b A-4: void retry = QBO 에 서 있을 때만
    raise exception 'Payment % is not standing in QuickBooks — nothing to void — nothing was saved', coalesce((select p.reference from public.so_payment p where p.id = v_j.ims_id::uuid), v_j.ims_id);
  end if;
  if v_j.state = 'skipped' then                                                                                                        -- 2d1 이견 ④: 되돌리기 — note 필수 · 문서 상태 · 같은 열쇠의 열린 일감 없음
    if nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say why this skipped job should be sent after all (a note is required) — nothing was saved'; end if;
    v_doc := public.qbo_job_doc(v_j.ims_kind, v_j.ims_id);
    if v_j.kind in ('invoice', 'credit') and coalesce(v_doc->>'doc_status', '') <> 'issued' then
      raise exception '% % is % — a skipped job can only be sent again while the document is issued — nothing was saved', case v_j.kind when 'invoice' then 'Invoice' else 'Credit note' end, coalesce(v_doc->>'doc_number', v_j.ims_id), coalesce(v_doc->>'doc_status', 'missing');
    end if;
    if v_j.kind in ('invoice_void', 'credit_void') and coalesce(v_doc->>'doc_status', '') <> 'cancelled' then
      raise exception '% % is % — a skipped void can only be sent again while the document is cancelled — nothing was saved', case v_j.kind when 'invoice_void' then 'Invoice' else 'Credit note' end, coalesce(v_doc->>'doc_number', v_j.ims_id), coalesce(v_doc->>'doc_status', 'missing');
    end if;
    select j.id into v_open from public.qbo_job j where j.realm_id = v_j.realm_id and j.kind = v_j.kind and j.ims_kind = v_j.ims_kind and j.ims_id = v_j.ims_id and j.state not in ('sent', 'skipped') and j.id <> v_j.id limit 1;
    if v_open is not null then raise exception 'Another open job (%) already exists for this % — send or skip that one instead — nothing was saved', v_open, v_j.kind; end if;
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, blocked_by = null, request_id = gen_random_uuid(), note = btrim(p_note), updated_by = v_staff where j.id = v_j.id;
    return jsonb_build_object('job_id', v_j.id, 'state', 'queued', 'attempts', v_j.attempts, 'was', 'skipped');
  end if;
  update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = coalesce(nullif(btrim(p_note), ''), j.note), updated_by = v_staff where j.id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'state', 'queued', 'attempts', v_j.attempts, 'was', v_j.state);
end;
$$;
drop function public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric);
create function public.qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text default null, p_intuit_tid text default null, p_note text default null, p_sku text default null, p_total_amt numeric default null, p_total_tax numeric default null, p_unapplied_amt numeric default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_j public.qbo_job%rowtype; v_type text; v_link_err text; v_unblocked int := 0; v_i public.so_invoice%rowtype; v_c public.so_credit%rowtype; v_mismatch text; v_n int; v_p public.so_payment%rowtype; v_applied numeric; v_sync jsonb;   -- 2e-1b v_p · v_applied · v_sync
begin
  if not public.doc_is_service() then raise exception 'qbo_job_done is for the send worker only — nothing was saved'; end if;
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('sending', 'unknown') then raise exception 'Only a job being sent, or one whose result is unknown, can be finished (this one is %) — nothing was saved', v_j.state; end if;
  if nullif(btrim(coalesce(p_qbo_id, '')), '') is null or nullif(btrim(coalesce(p_qbo_name, '')), '') is null then raise exception 'qbo_id and qbo_name are required — nothing was saved'; end if;
  update public.qbo_job j set state = 'sent', sent_at = now(), claimed_at = null, qbo_id = btrim(p_qbo_id), qbo_name = btrim(p_qbo_name), sync_token = p_sync_token, last_intuit_tid = coalesce(p_intuit_tid, j.last_intuit_tid),
         last_error = case when p_note is not null then left(coalesce(j.last_error || ' · ', '') || p_note, 2000) else j.last_error end, attempts = j.attempts + case when p_note is not null then 1 else 0 end
   where j.id = v_j.id;
  if v_j.kind in ('customer', 'item') then
    v_type := case v_j.ims_kind when 'customer' then 'Customer' else 'Item' end;
    insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, active, sync_token, fetched_at, gone_at)
    values (v_j.realm_id, v_type, btrim(p_qbo_id), btrim(p_qbo_name), nullif(btrim(coalesce(p_sku, '')), ''), true, p_sync_token, now(), null)
    on conflict (realm_id, qbo_type, qbo_id) do update set name = excluded.name, sku = coalesce(excluded.sku, public.qbo_entity.sku), active = true, sync_token = excluded.sync_token, fetched_at = now(), gone_at = null;
    begin
      insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match, by_staff)
      values (v_j.realm_id, v_j.ims_kind, v_j.ims_id, v_type, btrim(p_qbo_id), 'created', btrim(p_qbo_name), v_j.by_staff)
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_type = excluded.qbo_type, qbo_id = excluded.qbo_id, matched_by = 'created', qbo_name_at_match = excluded.qbo_name_at_match, matched_at = now(), updated_at = now(), updated_by = excluded.by_staff;
    exception when unique_violation then                                                              -- QBO 쪽 부분 유일(이미 다른 IMS 행의 짝) — QBO 레코드는 생겼다 · 사람이 짝을 바로잡는다
      v_link_err := format('QuickBooks %s #%s was created but is already linked to another IMS row — fix the link by hand under Settings → QuickBooks matching', v_type, btrim(p_qbo_id));
    end;
  elsif v_j.kind = 'invoice' then                                                                      -- 2b1: 거래 짝 + 942 합계 대조(상태는 sent · 다르면 mismatch · 자동 void 없음)
    select * into v_i from public.so_invoice i where i.id = v_j.ims_id::uuid;
    v_mismatch := case when p_total_amt is null or p_total_tax is null then 'QuickBooks did not return TotalAmt / TotalTax — check invoice ' || coalesce(v_i.invoice_number, v_j.ims_id) || ' in QuickBooks'
                       when p_total_amt <> v_i.total or p_total_tax <> v_i.tax_amount then format('QuickBooks total %s / tax %s differs from IMS %s / %s — check invoice %s in QuickBooks (942)', p_total_amt, p_total_tax, v_i.total, v_i.tax_amount, v_i.invoice_number) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at)
      values (v_j.realm_id, 'invoice', v_j.ims_id, 'Invoice', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null)
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, updated_at = now();
    exception when unique_violation then                                                              -- (realm, Invoice, qbo_id) 가 이미 다른 IMS 인보이스의 짝
      v_link_err := format('QuickBooks Invoice #%s is already recorded for another IMS invoice — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'invoice_void' then                                                                 -- 2b1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'invoice' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent invoice on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'credit' then                                                                       -- 2c1: 거래 짝(CreditMemo) + 942 대조(so_credit.total · tax_amount · 상태는 sent · 자동 void 없음)
    select * into v_c from public.so_credit c where c.id = v_j.ims_id::uuid;
    v_mismatch := case when p_total_amt is null or p_total_tax is null then 'QuickBooks did not return TotalAmt / TotalTax — check credit note ' || coalesce(v_c.credit_number, v_j.ims_id) || ' in QuickBooks'
                       when p_total_amt <> v_c.total or p_total_tax <> v_c.tax_amount then format('QuickBooks total %s / tax %s differs from IMS %s / %s — check credit note %s in QuickBooks (942)', p_total_amt, p_total_tax, v_c.total, v_c.tax_amount, v_c.credit_number) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at)
      values (v_j.realm_id, 'credit', v_j.ims_id, 'CreditMemo', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null)
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, updated_at = now();
    exception when unique_violation then                                                              -- (realm, CreditMemo, qbo_id) 가 이미 다른 IMS 크레딧의 짝
      v_link_err := format('QuickBooks CreditMemo #%s is already recorded for another IMS credit note — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'credit_void' then                                                                  -- 2c1 판정 963: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'credit' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent credit note on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'payment' then                                                                      -- 2e-1b: 거래 짝(Payment) + 지문(claim 이 일감에 적은 것) + 942 꼴 대조(TotalAmt = amount · UnappliedAmt = amount − Σ붙임 · 상태는 sent · 자동 void 없음)
    select * into v_p from public.so_payment p where p.id = v_j.ims_id::uuid;
    select coalesce(sum(a.amount), 0) into v_applied from public.so_payment_alloc a where a.payment_id = v_p.id and a.voided_at is null;
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check payment ' || coalesce(v_p.reference, v_j.ims_id) || ' in QuickBooks'
                       when p_total_amt <> v_p.amount then format('QuickBooks total %s differs from IMS %s — check payment %s in QuickBooks (942)', p_total_amt, v_p.amount, coalesce(v_p.reference, v_j.ims_id))
                       when p_unapplied_amt is not null and p_unapplied_amt <> v_p.amount - v_applied then format('QuickBooks unapplied %s differs from IMS %s — check payment %s in QuickBooks (942)', p_unapplied_amt, v_p.amount - v_applied, coalesce(v_p.reference, v_j.ims_id)) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'payment', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, v_j.fingerprint, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = excluded.fingerprint, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 결제의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS payment — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'payment_void' then                                                                 -- 2e-1b 978: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'payment' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent payment on file to mark — check qbo_txn by hand'; end if;
  end if;
  if v_link_err is not null then
    update public.qbo_job j set state = 'failed', sent_at = null, last_error = left(coalesce(j.last_error || ' · ', '') || v_link_err, 2000) where j.id = v_j.id;
  else
    update public.qbo_job j set state = 'queued', next_at = now() where j.state = 'blocked' and j.blocked_by = v_j.id;
    get diagnostics v_unblocked = row_count;
  end if;
  if v_j.kind in ('payment', 'payment_void') and v_link_err is null then                              -- 2e-1b A-10: 보낸 뒤 reconcile — 보내는 동안 붙임이 바뀌었으면 void · 다시 보내기 일감을 지금 쌓는다(in-flight 중에는 열린 payment 일감 자리가 하나라 못 쌓는다)
    begin v_sync := public.qbo_payment_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  return jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'state', case when v_link_err is null then 'sent' else 'failed' end, 'reconcile', v_sync, 'qbo_id', btrim(p_qbo_id), 'qbo_name', btrim(p_qbo_name), 'linked', v_link_err is null, 'link_error', v_link_err, 'unblocked', v_unblocked, 'mismatch', v_mismatch);
end;
$$;
comment on function public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric, numeric) is 'qbo-sync-2a · [2b1 합계] · [2c1 credit · credit_void] · [2e-1b payment → qbo_txn Payment(지문 = 일감의 fingerprint · source sent · doc_number = PaymentRefNum) + 942 꼴 대조(TotalAmt = amount · UnappliedAmt = amount − Σ붙임 → mismatch + warning · 상태는 sent) · payment_void → voided_at · 둘 다 끝에 qbo_payment_sync 로 reconcile(보내는 동안 바뀐 붙임) · 옛 9 인자 서명은 drop — EF 는 이름 붙인 인자로 부른다]: 보내기 성공(service_role) — sending · unknown → sent · customer · item 이면 qbo_entity upsert + qbo_link(created) · invoice · credit 면 qbo_txn + 942 대조 · void 면 voided_at · QBO Id 가 이미 다른 IMS 행의 짝이면 failed + 사람 말 · 자식(blocked_by) 풀기는 kind 무관';

-- ═══ ⑦ grant — 새 함수 전부 grant 0(claim · done · 트리거가 부른다) · done 은 service_role · claim · preview · list · retry 는 create or replace 라 ACL 그대로 ═══
revoke all on function public.qbo_payment_fingerprint(uuid), public.qbo_payment_body(uuid), public.qbo_payment_void_body(uuid), public.qbo_payment_sync(uuid, uuid),
  public.qbo_job_on_payment_alloc(), public.qbo_job_on_payment_status(), public.qbo_payment_requeue(uuid), public.qbo_payment_backfill(),
  public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric, numeric) from public, anon, authenticated, service_role;
grant execute on function public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric, numeric) to service_role;
do $$
begin
  execute format('comment on table public.qbo_job is %L', coalesce(obj_description('public.qbo_job'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-2e-1b: kind payment · payment_void(ims_kind payment · ims_id so_payment.id · 트리거 so_payment_alloc_qbo · so_payment_qbo_status · 지문 fingerprint)');
  execute format('comment on table public.qbo_txn is %L', coalesce(obj_description('public.qbo_txn'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-2e-1b: ims_kind payment ↔ QBO Payment(doc_number = PaymentRefNum · total_tax null · fingerprint · source sent | matched)');
end $$;

-- ═══ ⑧ 착지 · 백필 ═══
do $$
declare v text; v_n int;
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname, p.oid) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_job_done', 'qbo_payment_body', 'qbo_payment_sync');
  if v <> 'qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text, p_intuit_tid text, p_note text, p_sku text, p_total_amt numeric, p_total_tax numeric, p_unapplied_amt numeric)={postgres=X/postgres,service_role=X/postgres} qbo_payment_body(p_payment_id uuid)={postgres=X/postgres} qbo_payment_sync(p_payment_id uuid, p_by uuid)={postgres=X/postgres}' then
    raise exception '⑧ ACL unexpected: %', v;
  end if;
  v_n := public.qbo_payment_backfill();
  raise notice '⑧ payment backfill: % job(s) queued (sale invoices since % · opening-linked payments wait for 1d)', v_n, coalesce((select c.value from public.inv_config c where c.key = 'qbo_send_since'), '?');
end $$;
-- 끝 — 적용 뒤: supabase/tests/qbo_sync_2e1b_check.sql(-v mig 없이) → 1c(EF) 배포 → cron 62 등록 · qbo_send_payments_enabled 는 Caleb 이 켠다
