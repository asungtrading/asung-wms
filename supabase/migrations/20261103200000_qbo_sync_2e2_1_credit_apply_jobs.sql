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
-- qbo-sync-2e-2-1 — 크레딧 붙임을 QBO 에 금액 0 Payment 로(DB): CHECK · 몸 둘 · 상태 맞추기 · 트리거 · 백필 · requeue 넓힘 · claim · preview · doc · list · retry · done 재발행 (판정 995 · 1009 ~ 1017 · 2026-11-03 · 지시서 ~/asung/prompts/qbo-sync-2e-2-1.md · §0 이견 1 ~ 14 Caleb 답 · sandbox C-5″ · C-6)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied 20261103200000 · ⚠️ db push 쓰지 않는다 · 2e-1b(20261103050000) · cr-store-1a(20261103090000) 뒤
-- 무엇:
--   ⓪ 재발행 원본 가드 — claim · done · preview · doc · list · retry 의 DB prosrc md5 가 마지막 정의 파일(2e-1b)과 다르면 멈춘다 · 결제 몸 · void 몸 · 지문 · sync 도 2e-1b 그대로여야 한다(이 차수는 건드리지 않는다)
--   ① 표: qbo_job kind(+ credit_apply · credit_apply_void) · ims_kind(+ credit_alloc · ims_id = so_credit_alloc.id) · pair / qbo_txn kind(+ credit_alloc · pair 의 ELSE 가 이미 Payment)
--   ② 몸 qbo_credit_apply_body(alloc)(1009 · 1011 · 1012 · 1013 · 1014 · 1017 · 이견 1 ~ 5 · 12) — CustomerRef = 인보이스 매장(so_invoice_store) 짝(크레딧 매장과 다르면 failed · 짝 없으면 needs) · TxnDate = 붙임 created_at 토론토 · TotalAmt 0 · CurrencyRef · PaymentMethodRef · DepositToAccountRef · PaymentRefNum 없음(C-5″)
--      · PrivateNote 「IMS credit applied <alloc uuid>」 · Line 둘(Invoice · CreditMemo · 같은 금액) · 기다림 = 크레딧 메모 → 인보이스 → 같은 인보이스의 열린 void 일감(payment_void · credit_apply_void · 1013) 차례로 wait_job + wait_reason · 일감 없음 · skipped · 이월 · since 전은 failed 글 · check_lines 두 줄(txn_type) · lookup(unknown 열쇠)
--      qbo_credit_apply_void_body(alloc) — qbo_txn credit_alloc 의 Id · SyncToken · sparse true(EF 는 payment?operation=update&include=void · C-6)
--   ③ qbo_credit_alloc_sync(alloc · 사람) — 환불 대상 · 연결 없음 · 붙임 created_at 이 since 전이면 조용히 / 보낸 적 없음: 활성 → credit_apply queued(열린 것 있으면 그대로) · void 됨 → 열린 queued · blocked · failed 는 skipped · sending · unknown 이면 void 를 그 일감 뒤에 blocked / QBO 에 서 있음: 활성 → 아무것도(1011 행은 안 바뀐다) · void 됨 → credit_apply_void queued / QBO 쪽 void 됨: 열린 credit_apply 는 skipped
--   ④ 트리거 so_credit_alloc_qbo — so_credit_alloc AFTER INSERT OR UPDATE OF voided_at DEFERRABLE INITIALLY DEFERRED(발행 안의 auto · 취소 void 가 커밋 때 한 번에 · 결제 트리거와 같은 커밋 끝) → sync · 오류는 삼킨다(failed 일감 흔적)
--   ⑤ qbo_credit_apply_backfill()(1017 · 적용 때 한 번 · 활성 · 인보이스 대상 · 인보이스 sale ∧ since 뒤 · 붙임 created_at since 뒤 · 일감 · 거래 짝 없음) · qbo_payment_requeue(p_invoice_id) 재발행(그 인보이스의 활성 크레딧 붙임도 sync + failed credit_apply 되살림 · 1016 · 반환 = 결제 수 + 붙임 수)
--   ⑥ 재발행(2e-1b 바이트 + 가지): claim(kinds 10 · 몸 둘 · wait_reason coalesce) · preview(몸 둘 · wait_reason) · doc(credit_alloc 행) · list(kinds 10 · ims_name · txn 짝) · retry(이견 9 규칙 넷) · done(credit_apply → qbo_txn credit_alloc · Payment · TotalAmt 0 · UnappliedAmt 0 대조 · credit_apply_void → voided_at · 끝에 sync)
--   ⑦ grant: 새 함수 전부 grant 0(claim · done · 트리거가 부른다) · done · requeue 는 create or replace 라 ACL 그대로 · ⑧ 착지(ACL · 결제 넷 md5 무변) · 백필 NOTICE
-- 안 하는 것: EF(2e-2-1b — SEND_KINDS 10 · entityKeyOf 명시 가지 · 가드 Invoice Balance ≥ a ∧ CreditMemo RemainingCredit ≥ a · unknown 풀기 PrivateNote 접두 둘 · void) · cron 62 등록(명령 글만 supabase/ops/cron.sql) · N1 · N2 void 순서 · 환불 대상 붙임(2e-3) · 화면(qbo-send.html · 대화 Claude) · so_credit 삭제 cascade(길 0)
-- 거래 표 FK: 0(ims_id 다형) · 검증: supabase/tests/qbo_sync_2e2_1_check.sql(-v mig 시험 · 적용 뒤 -v mig 없이)

-- ═══ ⓪ 재발행 원본 가드 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_claim')   is distinct from '492dc6ca7d26ff37249098b277b00c35' then v_bad := v_bad || ' qbo_job_claim'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_done')    is distinct from '6e3837d89f37d490c3f7d89ebb352382' then v_bad := v_bad || ' qbo_job_done'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_preview') is distinct from 'f5ac5ecdda3e5ee78d9b5966e358f034' then v_bad := v_bad || ' qbo_job_preview'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_doc')     is distinct from '7ccb853f3d3d8ad8c9b7a7a1b0e5a1ac' then v_bad := v_bad || ' qbo_job_doc'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_list')    is distinct from '8b89a3122cbd9abfacd7c9ca3cf30651' then v_bad := v_bad || ' qbo_job_list'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_retry')   is distinct from '5d5752d1bb88a07ff46e89af828c006b' then v_bad := v_bad || ' qbo_job_retry'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_body')      is distinct from 'e1aea51849844cc5898351daaa3ef533' then v_bad := v_bad || ' qbo_payment_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_void_body') is distinct from '4ddb45cd728222d7b676d1e0bd169a54' then v_bad := v_bad || ' qbo_payment_void_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_sync')      is distinct from '9efb5d9f6007048692d13cd00623c4b8' then v_bad := v_bad || ' qbo_payment_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_requeue')   is distinct from '3d0a3f078e00b669c3af2c88364e83ba' then v_bad := v_bad || ' qbo_payment_requeue'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_done', 'qbo_job_claim', 'qbo_payment_requeue')) <> 3 then v_bad := v_bad || ' overloads'; end if;
  if to_regprocedure('public.so_invoice_store(uuid)') is null or to_regprocedure('public.so_credit_store(uuid)') is null then v_bad := v_bad || ' so_invoice_store/so_credit_store(cr-store-1a not applied)'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current bodies first — nothing was changed', v_bad; end if;
end $$;

-- ═══ ① 표 ═══
alter table public.qbo_job drop constraint qbo_job_kind_ck;
alter table public.qbo_job add  constraint qbo_job_kind_ck check (kind in ('customer', 'item', 'invoice', 'credit', 'invoice_void', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void'));
alter table public.qbo_job drop constraint qbo_job_ims_kind_ck;
alter table public.qbo_job add  constraint qbo_job_ims_kind_ck check (ims_kind in ('customer', 'product', 'charge', 'invoice', 'credit', 'payment', 'credit_alloc'));
alter table public.qbo_job drop constraint qbo_job_pair_ck;
alter table public.qbo_job add  constraint qbo_job_pair_ck check (ims_kind = case kind when 'customer' then 'customer' when 'invoice' then 'invoice' when 'invoice_void' then 'invoice' when 'credit' then 'credit' when 'credit_void' then 'credit'
                                                                                        when 'payment' then 'payment' when 'payment_void' then 'payment' when 'credit_apply' then 'credit_alloc' when 'credit_apply_void' then 'credit_alloc' else ims_kind end
                                                                and (kind <> 'item' or ims_kind in ('product', 'charge')));
alter table public.qbo_txn drop constraint qbo_txn_kind_ck;
alter table public.qbo_txn add  constraint qbo_txn_kind_ck check (ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc'));

-- ═══ ② 몸 둘 ═══
create function public.qbo_credit_apply_body(p_alloc_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_a public.so_credit_alloc%rowtype; v_c public.so_credit%rowtype; v_i public.so_invoice%rowtype; v_store public.customer%rowtype; v_is uuid; v_cs uuid; v_cust_ref text;
        v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_label text; v_date date; v_ti public.qbo_txn%rowtype; v_tc public.qbo_txn%rowtype; v_j public.qbo_job%rowtype;
        v_wait uuid; v_wait_doc text; v_wait_reason text; v_body jsonb; v_lines jsonb := '[]'::jsonb; v_checks jsonb := '[]'::jsonb; r record;
begin
  select * into v_a from public.so_credit_alloc a where a.id = p_alloc_id;
  if v_a.id is null then raise exception 'No IMS credit application % — nothing was sent', p_alloc_id; end if;
  select * into v_c from public.so_credit c where c.id = v_a.credit_id;
  if v_a.refund_payment_id is not null then raise exception 'Credit note % pays a refund — refunds go to QuickBooks in a later step (2e-3) — nothing was sent', v_c.credit_number; end if;
  select * into v_i from public.so_invoice i where i.id = v_a.invoice_id;
  v_label := v_c.credit_number || ' → ' || v_i.invoice_number;
  if v_a.voided_at is not null then raise exception 'Credit application % was detached — nothing to send (a void job takes care of QuickBooks) — nothing was sent', v_label; end if;
  if nullif(btrim(coalesce(v_c.currency_code, '')), '') is null then raise exception 'Credit note % has no currency code — nothing was sent', v_c.credit_number; end if;
  -- 1014 · 이견 2: CustomerRef = 인보이스 매장(so_invoice_store · 2b1 935 의 Invoice 손님과 같다) · 크레딧 매장(so_credit_store)과 다르면 failed(cr-store-1a 전 붙임 자리 · 지금 0) · 짝 없으면 needs(두 문서가 QBO 에 섰으면 짝은 있다)
  v_is := public.so_invoice_store(v_i.id); v_cs := public.so_credit_store(v_c.id);
  if v_is is null then raise exception 'Invoice % has no store on record — nothing was sent', v_i.invoice_number; end if;
  if v_is <> v_cs then
    raise exception 'Credit note % belongs to store % but invoice % is for store % — detach it (a credit note applies only to invoices of its own store) — nothing was sent',
      v_c.credit_number, (select c.name from public.customer c where c.id = v_cs), v_i.invoice_number, (select c.name from public.customer c where c.id = v_is);
  end if;
  select * into v_store from public.customer c where c.id = v_is;
  select l.qbo_id into v_cust_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_is::text;
  if v_cust_ref is null then v_needs := v_needs || jsonb_build_object('kind', 'customer', 'ims_id', v_is::text, 'name', v_store.name); end if;
  -- 1012 · 이견 5: 부모 둘 — 크레딧 메모 먼저 · 인보이스 다음 · 첫 미발송 하나에 wait(claim ② 가 sent 때 풀면 다음 바퀴에 다시 본다)
  select * into v_tc from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'credit' and t.ims_id = v_c.id::text and t.voided_at is null;
  if v_tc.id is null then
    select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'credit' and j.ims_kind = 'credit' and j.ims_id = v_c.id::text order by j.created_at desc, j.id desc limit 1;
    if v_j.id is null then raise exception 'Credit note % has no QuickBooks job — send it first — nothing was sent', v_c.credit_number; end if;
    if v_j.state = 'skipped' then raise exception 'Credit note % was skipped — skip this credit application too, or retry the credit note first — nothing was sent', v_c.credit_number; end if;
    if v_j.state = 'sent' then raise exception 'Credit note % job is sent but no QuickBooks transaction is on file — check qbo_txn by hand — nothing was sent', v_c.credit_number; end if;
    v_wait := v_j.id; v_wait_doc := v_c.credit_number; v_wait_reason := format('waiting for credit note %s to reach QuickBooks first', v_c.credit_number);
  end if;
  select * into v_ti from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = v_i.id::text and t.voided_at is null;
  if v_ti.id is null then
    if v_i.kind = 'opening' then raise exception 'Invoice % was carried over from the previous system and has no QuickBooks match yet — match it under Settings → QuickBooks → Opening invoices; this credit application then goes by itself — nothing was sent', v_i.invoice_number; end if;
    if not public.qbo_send_since_ok(v_i.issued_on) then raise exception 'Invoice % was issued before the QuickBooks start date and has no QuickBooks match — match it under Settings → QuickBooks → Opening invoices — nothing was sent', v_i.invoice_number; end if;
    select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'invoice' and j.ims_kind = 'invoice' and j.ims_id = v_i.id::text order by j.created_at desc, j.id desc limit 1;
    if v_j.id is null then raise exception 'Invoice % has no QuickBooks job — send the invoice first — nothing was sent', v_i.invoice_number; end if;
    if v_j.state = 'skipped' then raise exception 'Invoice % was skipped — skip this credit application too, or retry the invoice first — nothing was sent', v_i.invoice_number; end if;
    if v_j.state = 'sent' then raise exception 'Invoice % job is sent but no QuickBooks transaction is on file — check qbo_txn by hand — nothing was sent', v_i.invoice_number; end if;
    if v_wait is null then v_wait := v_j.id; v_wait_doc := v_i.invoice_number; v_wait_reason := format('waiting for invoice %s to reach QuickBooks first', v_i.invoice_number); end if;
  end if;
  -- 1013 · 이견 3: 새 0 Payment 만 같은 인보이스의 열린 void 일감 뒤에 선다(payment_void = 그 결제의 붙임(void 포함)에 이 인보이스가 있으면 · credit_apply_void = 그 붙임 행의 invoice_id) — EF 가드(Invoice Balance ≥ a)가 void 뒤에 통과하도록 · failed 인 void 면 글에 그 일감을 적어 사람이 Retry · Skip 할 곳이 보이게
  if v_wait is null then
    for r in select j.id, j.kind, j.state,
                    case j.kind when 'payment_void' then coalesce((select nullif(btrim(coalesce(p.reference, '')), '') from public.so_payment p where p.id::text = j.ims_id), 'payment ' || left(j.ims_id, 8))
                                else (select c2.credit_number from public.so_credit_alloc a2 join public.so_credit c2 on c2.id = a2.credit_id where a2.id::text = j.ims_id) end as doc
               from public.qbo_job j
              where j.realm_id = v_realm and j.state not in ('sent', 'skipped')
                and ((j.kind = 'payment_void' and exists (select 1 from public.so_payment_alloc pa where pa.payment_id::text = j.ims_id and pa.invoice_id = v_i.id))
                  or (j.kind = 'credit_apply_void' and j.ims_id <> v_a.id::text and exists (select 1 from public.so_credit_alloc a2 where a2.id::text = j.ims_id and a2.invoice_id = v_i.id)))
              order by j.created_at, j.id limit 1 loop
      v_wait := r.id; v_wait_doc := r.doc;
      v_wait_reason := format('waiting for the void of %s %s on invoice %s to reach QuickBooks first (that job is %s%s)', case r.kind when 'payment_void' then 'payment' else 'credit note' end, r.doc, v_i.invoice_number, r.state,
                              case when r.state = 'failed' then ' — retry or skip it first' when r.state = 'unknown' then ' — check QuickBooks and retry it with a note' else '' end);
    end loop;
  end if;
  v_date := (v_a.created_at at time zone 'America/Toronto')::date;                                                                     -- 1017: 붙인 날(토론토)
  if v_wait is null then
    v_lines := jsonb_build_array(jsonb_build_object('Amount', v_a.amount, 'LinkedTxn', jsonb_build_array(jsonb_build_object('TxnId', v_ti.qbo_id, 'TxnType', 'Invoice'))),
                                 jsonb_build_object('Amount', v_a.amount, 'LinkedTxn', jsonb_build_array(jsonb_build_object('TxnId', v_tc.qbo_id, 'TxnType', 'CreditMemo'))));   -- C-5″ 순: Invoice · CreditMemo
    v_checks := jsonb_build_array(jsonb_build_object('txn_type', 'Invoice', 'invoice_number', v_i.invoice_number, 'qbo_invoice_id', v_ti.qbo_id, 'amount', v_a.amount),
                                  jsonb_build_object('txn_type', 'CreditMemo', 'credit_number', v_c.credit_number, 'qbo_creditmemo_id', v_tc.qbo_id, 'amount', v_a.amount));   -- 이견 11: 인보이스 줄은 결제 열쇠 그대로(화면) · 1b 는 txn_type 으로 가른다
  end if;
  v_body := jsonb_strip_nulls(jsonb_build_object(
    'CustomerRef', case when v_cust_ref is null then null else jsonb_build_object('value', v_cust_ref) end,
    'TxnDate', v_date, 'TotalAmt', 0, 'CurrencyRef', jsonb_build_object('value', v_c.currency_code),
    'PrivateNote', 'IMS credit applied ' || v_a.id::text, 'Line', v_lines));                                                               -- PaymentMethodRef · DepositToAccountRef · PaymentRefNum 없음(C-5″)
  return jsonb_build_object('kind', 'credit_apply', 'ims_kind', 'credit_alloc', 'ims_id', v_a.id::text, 'name', v_label, 'doc_number', v_label, 'customer_id', v_is,
    'body', v_body, 'needs', v_needs, 'wait_job', v_wait, 'wait_invoice', v_wait_doc, 'wait_reason', v_wait_reason, 'warnings', to_jsonb(v_warn), 'line_count', jsonb_array_length(v_lines),
    'totals', jsonb_build_object('amount', 0, 'applied', v_a.amount, 'unapplied', 0, 'credit_number', v_c.credit_number, 'invoice_number', v_i.invoice_number),
    'fingerprint', null, 'check_lines', v_checks,
    'lookup', jsonb_build_object('customer_ref', v_cust_ref, 'txn_date', v_date, 'total_amt', 0, 'private_note', 'IMS credit applied ' || v_a.id::text));
end;
$$;
comment on function public.qbo_credit_apply_body(uuid) is 'qbo-sync-2e-2-1 판정 1009 · 1011 ~ 1014 · 1017(속 · grant 0 · claim · preview 가 부른다): IMS 크레딧 붙임 → QBO 0 원 Payment 만들기 몸 — CustomerRef = 인보이스 매장 짝(크레딧 매장과 다르면 예외 · 짝 없으면 needs) · TxnDate 붙인 날(토론토) · TotalAmt 0 · CurrencyRef · PaymentMethodRef · DepositToAccountRef · PaymentRefNum 없음 · PrivateNote 「IMS credit applied <uuid>」 · Line = Invoice + CreditMemo(qbo_txn 의 Id · 같은 금액) · 기다림 = 크레딧 메모 → 인보이스 → 같은 인보이스의 열린 void 일감(1013) 차례로 wait_job + wait_reason · 일감 없음 · skipped · 이월 · since 전 짝 없음 · 환불 대상 · 떼인 붙임은 예외(failed) · 돌려주는 것 = { body · needs · wait_job · wait_invoice · wait_reason · warnings · totals · check_lines[{txn_type Invoice|CreditMemo …}] · lookup(unknown 열쇠) · fingerprint null }';

create function public.qbo_credit_apply_void_body(p_alloc_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_t public.qbo_txn%rowtype; v_label text;
begin
  v_label := public.qbo_job_doc('credit_alloc', p_alloc_id::text)->>'doc_number';
  if v_label is null then raise exception 'No IMS credit application % — nothing was sent', p_alloc_id; end if;
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'credit_alloc' and t.ims_id = p_alloc_id::text;
  if v_t.id is null then raise exception 'Credit application % was never sent to QuickBooks — nothing to void', v_label; end if;
  if v_t.voided_at is not null then raise exception 'Credit application % (QuickBooks payment #%) is already voided — nothing was sent', v_label, v_t.qbo_id; end if;
  return jsonb_build_object('kind', 'credit_apply_void', 'ims_kind', 'credit_alloc', 'ims_id', p_alloc_id::text, 'name', v_label, 'doc_number', v_t.doc_number, 'qbo_id', v_t.qbo_id,
    'body', jsonb_strip_nulls(jsonb_build_object('Id', v_t.qbo_id, 'SyncToken', v_t.sync_token, 'sparse', true)), 'needs', '[]'::jsonb,
    'warnings', case when v_t.sync_token is null then '["no SyncToken on file — the sender reads the payment first"]'::jsonb else '[]'::jsonb end,
    'lookup', jsonb_build_object('qbo_id', v_t.qbo_id, 'private_note', 'IMS credit applied ' || p_alloc_id::text));
end;
$$;
comment on function public.qbo_credit_apply_void_body(uuid) is 'qbo-sync-2e-2-1 판정 1011 · sandbox C-6(속 · grant 0): 0 원 Payment void 몸 — qbo_txn credit_alloc 의 Id · SyncToken · sparse true(EF 는 payment?operation=update&include=void · 결제 void 와 같은 길) · 보낸 적 없음 · 이미 void 면 예외(failed)';

-- ═══ ③ 상태 맞추기(트리거 · done 의 reconcile · 백필 · requeue 가 부른다) · ④ 트리거 ═══
create function public.qbo_credit_alloc_sync(p_alloc_id uuid, p_by uuid) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton); v_a public.so_credit_alloc%rowtype; v_active boolean; v_t public.qbo_txn%rowtype; v_pj public.qbo_job%rowtype; v_vj public.qbo_job%rowtype; v_act text := 'none';
begin
  if v_realm is null then return jsonb_build_object('action', 'no_connection'); end if;
  select * into v_a from public.so_credit_alloc a where a.id = p_alloc_id;
  if v_a.id is null or v_a.invoice_id is null then return jsonb_build_object('action', 'not_applicable'); end if;                     -- 환불 대상은 2e-3
  if not public.qbo_send_since_ok((v_a.created_at at time zone 'America/Toronto')::date) then return jsonb_build_object('action', 'before_since'); end if;   -- 이견 1: QBO 시대 전 사건은 조용히
  v_active := v_a.voided_at is null;
  select * into v_t  from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'credit_alloc' and t.ims_id = v_a.id::text;
  select * into v_pj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'credit_apply'      and j.ims_kind = 'credit_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_vj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'credit_apply_void' and j.ims_kind = 'credit_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  if v_t.id is null then                                                                                                               -- 보낸 적 없다
    if v_active then
      if v_pj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'credit_apply', 'credit_alloc', v_a.id::text, 'queued', p_by)
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'queued';
      end if;                                                                                                                          -- 열린 일감은 그대로(claim 이 그때의 상태로 몸을 다시 만든다 · failed 는 사람 Retry · requeue)
    elsif v_pj.id is not null and v_pj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'credit application detached before sending'), 2000), updated_by = p_by where j.id = v_pj.id;
      v_act := 'skipped';
    elsif v_pj.id is not null and v_pj.state in ('sending', 'unknown') and v_vj.id is null then                                       -- 닿았는지 모른다 → void 를 그 일감 뒤에(결제 꼴)
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'credit_apply_void', 'credit_alloc', v_a.id::text, 'blocked', v_pj.id, p_by, 'detached while sending — void after the send settles')
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      v_act := 'void_after_send';
    end if;
  elsif v_t.voided_at is null then                                                                                                     -- QBO 에 서 있다
    if v_active then
      v_act := 'same';                                                                                                                 -- 1011: 붙임 행은 바뀌지 않는다 — 지문 · 다시 보내기 없음
    else
      if v_vj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'credit_apply_void', 'credit_alloc', v_a.id::text, 'queued', p_by, 'credit application detached — void the zero payment in QuickBooks')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      end if;
      if v_pj.id is not null and v_pj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'credit application detached — only the void goes'), 2000), updated_by = p_by where j.id = v_pj.id;
      end if;
      v_act := 'void';
    end if;
  else                                                                                                                                 -- QBO 쪽은 void 됐다(붙임은 되살지 않는다 · 다시 붙이면 새 행 = 새 일감)
    if v_pj.id is not null and v_pj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'already voided in QuickBooks'), 2000), updated_by = p_by where j.id = v_pj.id;
      v_act := 'skipped';
    end if;
  end if;
  return jsonb_build_object('action', v_act);
end;
$$;
comment on function public.qbo_credit_alloc_sync(uuid, uuid) is 'qbo-sync-2e-2-1 판정 1011 · 1016 · 이견 1(속 · grant 0): 크레딧 붙임 하나의 QBO 일감을 IMS 상태에 맞춘다 — 환불 대상 · 연결 없음 · 붙임 created_at 이 since 전이면 조용히 / 보낸 적 없음: 활성 → credit_apply queued(열린 것 있으면 그대로) · void 됨 → 열린 queued · blocked · failed 는 skipped · sending · unknown 이면 void 를 그 일감 뒤에 blocked / QBO 에 서 있음: 활성 → same · void 됨 → credit_apply_void queued / QBO 쪽 void 됨: 열린 credit_apply 는 skipped · 돌려주는 것 = { action } · 부르는 곳 = 트리거 · done 의 reconcile · 백필 · requeue';

create function public.qbo_job_on_credit_alloc() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_by uuid := coalesce(new.voided_by, new.updated_by, new.created_by);
begin
  begin
    perform public.qbo_credit_alloc_sync(new.id, v_by);
  exception when others then                                                                                                           -- 발행 · 붙이기 · 떼기 · 취소를 막지 않는다 — failed 일감으로 흔적
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff)
      select c.realm_id, 'credit_apply', 'credit_alloc', new.id::text, 'failed', left('could not queue: ' || sqlerrm, 2000), v_by from public.qbo_connection c where c.singleton
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$$;
comment on function public.qbo_job_on_credit_alloc() is 'qbo-sync-2e-2-1: so_credit_alloc AFTER INSERT OR UPDATE OF voided_at — DEFERRABLE INITIALLY DEFERRED(발행 안의 auto 붙임 · 인보이스 취소의 void 가 커밋 때 한 번에 · 결제 트리거와 같은 커밋 끝 · 여섯 길(A-2) 전부 표에서 잡힌다) → qbo_credit_alloc_sync · 오류는 삼켜 창구를 막지 않는다(failed 일감 흔적) · 환불 대상 · since 전 · 연결 없음은 sync 가 조용히';
create constraint trigger so_credit_alloc_qbo after insert or update of voided_at on public.so_credit_alloc deferrable initially deferred for each row execute function public.qbo_job_on_credit_alloc();

-- ═══ ⑤ 백필(1017) · requeue 넓힘(1016 · 이견 7) ═══
create function public.qbo_credit_apply_backfill() returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare r record; v_n int := 0; v_r jsonb;
begin
  if not exists (select 1 from public.qbo_connection c where c.singleton) then return 0; end if;
  for r in select a.id, a.created_by from public.so_credit_alloc a join public.so_invoice i on i.id = a.invoice_id
            where a.voided_at is null and a.invoice_id is not null
              and i.kind = 'sale' and public.qbo_send_since_ok(i.issued_on) and public.qbo_send_since_ok((a.created_at at time zone 'America/Toronto')::date)
              and not exists (select 1 from public.qbo_job j where j.ims_kind = 'credit_alloc' and j.ims_id = a.id::text)
              and not exists (select 1 from public.qbo_txn t where t.ims_kind = 'credit_alloc' and t.ims_id = a.id::text)
            order by a.created_at, a.id loop
    v_r := public.qbo_credit_alloc_sync(r.id, r.created_by);
    if v_r->>'action' = 'queued' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end;
$$;
comment on function public.qbo_credit_apply_backfill() is 'qbo-sync-2e-2-1 판정 1017(속 · grant 0): 적용 때 한 번 — 활성 · 인보이스 대상 · 인보이스 sale ∧ since 뒤 · 붙임 created_at since 뒤 · 일감(어느 상태든) · 거래 짝 없는 붙임을 credit_apply queued 로 · 이월 인보이스에 붙은 것은 1d 의 qbo_payment_requeue 가 · 환불 대상은 2e-3 · 연결 없으면 0';

create or replace function public.qbo_payment_requeue(p_invoice_id uuid) returns int
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
  for r in select a.id, a.created_by from public.so_credit_alloc a where a.invoice_id = p_invoice_id and a.voided_at is null order by a.created_at, a.id loop   -- 2e-2-1 판정 1016: 이 인보이스에 붙은 활성 크레딧 붙임도(일감 없으면 만든다 · failed 는 되살린다)
    perform public.qbo_credit_alloc_sync(r.id, r.created_by);
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: invoice ' || coalesce(v_num, '?') || ' is now matched in QuickBooks'), 2000)
     where j.kind = 'credit_apply' and j.ims_kind = 'credit_alloc' and j.ims_id = r.id::text and j.state = 'failed';
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function public.qbo_payment_requeue(uuid) is 'qbo-sync-2e-1b A-3 · [2e-2-1 판정 1016: 활성 크레딧 붙임도 — qbo_credit_alloc_sync(일감 없으면 만든다) + failed credit_apply 를 queued 로](속 · grant 0 · 1d 이월 짝이 부른다): 이 인보이스에 붙은 활성 결제마다 qbo_payment_sync(일감 없으면 만든다) + failed 결제 일감을 queued 로(「no QuickBooks match」 로 실패했던 것) · 돌려주는 것 = 결제 수 + 크레딧 붙임 수';

-- ═══ ⑥ 재발행 — claim · preview · doc · list · retry · done(2e-1b 바이트 + 가지 · 같은 서명 · create or replace 라 ACL 그대로) ═══
create or replace function public.qbo_job_claim(p_limit int default 15, p_kinds text[] default array['customer', 'item'], p_job_ids uuid[] default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_stale int; v_unblocked int; v_ids uuid[]; v_j public.qbo_job%rowtype; v_open public.qbo_job%rowtype; v_b jsonb; v_rows jsonb := '[]'::jsonb; v_failed int := 0; v_blocked int := 0; v_waiting int := 0; v_last uuid; v_cust uuid; v_nj jsonb; e jsonb;
  v_kinds text[] := coalesce(p_kinds, array['customer', 'item']);
  v_pick uuid[] := (select array_agg(distinct x) from unnest(p_job_ids) x where x is not null);                                       -- 2d1: 고른 id(중복 · null 제거) · null 이면 옛 길(가장 오래된 것부터 p_limit)
  v_needs jsonb := '[]'::jsonb; v_req jsonb := '[]'::jsonb; v_r record;
begin
  if not public.doc_is_service() then raise exception 'qbo_job_claim is for the send worker only — nothing was read'; end if;
  if not (v_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void']) or coalesce(array_length(v_kinds, 1), 0) = 0 then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void (got %)', v_kinds; end if;
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
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid)
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid) end;   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void   -- 2c1 credit · credit_void
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
               warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')) || array[coalesce(v_b->>'wait_reason', format('waiting for invoice %s to reach QuickBooks first', coalesce(v_b->>'wait_invoice', '?')))], ' · '), '')
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
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid)
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid) end;   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
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
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid)
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid) end;   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
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
      v_wait_j := jsonb_build_object('job_id', v_wait.id, 'kind', v_wait.kind, 'state', v_wait.state, 'invoice', v_b->>'wait_invoice', 'reason', coalesce(v_b->>'wait_reason', format('waiting for invoice %s to reach QuickBooks first — send it too', coalesce(v_b->>'wait_invoice', '?'))));
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
    when 'credit_alloc' then (select jsonb_build_object('doc_number', c.credit_number || ' → ' || coalesce(i.invoice_number, 'refund'), 'name', (select cu.name from public.customer cu where cu.id = public.so_invoice_store(i.id)), 'customer_id', public.so_invoice_store(i.id), 'currency', c.currency_code, 'total', a.amount, 'doc_date', (a.created_at at time zone 'America/Toronto')::date, 'doc_status', case when a.voided_at is null then 'active' else 'voided' end)
                                from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id left join public.so_invoice i on i.id = a.invoice_id where a.id::text = p_ims_id)   -- 2e-2-1: 크레딧 붙임 = 「CR → 인보이스」 · 매장(1014) · 통화 · 붙임 금액 · 붙인 날(토론토) · active | voided
    else jsonb_build_object('doc_number', p_ims_id, 'name', p_ims_id, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', null) end;
$$;
create or replace function public.qbo_job_list(p_state text default null, p_kinds text[] default null, p_from date default null, p_to date default null, p_q text default null, p_limit int default 50, p_offset int default 0) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if p_state is not null and p_state not in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped', 'open') then raise exception 'state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open (got %)', p_state; end if;
  if p_kinds is not null and (not (p_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void']) or coalesce(array_length(p_kinds, 1), 0) = 0) then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void (got %)', p_kinds; end if;
  if p_from is not null and p_to is not null and p_from > p_to then raise exception 'from % is after to % — nothing was read', p_from, p_to; end if;
  return (with base as (
      select j.id, j.kind, j.ims_kind, j.ims_id, j.state, j.attempts, j.next_at, j.claimed_at, j.blocked_by, j.qbo_id, j.qbo_name, j.sent_at, j.last_error, j.last_intuit_tid, j.warning, j.note, j.by_staff, j.created_at, j.updated_at,
             (j.created_at at time zone 'America/Toronto')::date as job_date,
             d.doc->>'doc_number' as doc_number, d.doc->>'name' as name, d.doc->>'currency' as currency, (d.doc->>'total')::numeric as total, (d.doc->>'doc_date')::date as doc_date, d.doc->>'doc_status' as doc_status,
             case j.ims_kind when 'invoice' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'credit' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'payment' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-1b
                             when 'credit_alloc' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-2-1
                             when 'product' then coalesce(d.doc->>'doc_number', '') || ' ' || coalesce(d.doc->>'name', '')
                             else coalesce(d.doc->>'name', j.ims_id) end as ims_name,
             (select s.name from public.ims_staff s where s.id = j.by_staff) as by_name,
             p.kind as blocked_kind, p.state as blocked_state, coalesce(pd.doc->>'doc_number', pd.doc->>'name', p.ims_id) as blocked_name,
             t.qbo_id as txn_qbo_id, t.total_amt as txn_total_amt, t.total_tax as txn_total_tax, t.mismatch as txn_mismatch, t.voided_at as txn_voided_at
      from public.qbo_job j
      cross join lateral (select public.qbo_job_doc(j.ims_kind, j.ims_id) as doc) d
      left join public.qbo_job p on p.id = j.blocked_by
      left join lateral (select public.qbo_job_doc(p.ims_kind, p.ims_id) as doc) pd on p.id is not null
      left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_kind = j.ims_kind and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc')
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
  if v_j.kind = 'credit_apply' and not exists (select 1 from public.so_credit_alloc a where a.id::text = v_j.ims_id and a.voided_at is null and a.invoice_id is not null) then   -- 2e-2-1 이견 9: 붙임 retry = 활성 · 인보이스 대상 · QBO 에 안 섰을 때만
    raise exception 'Credit application % was detached (or pays a refund) — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'credit_apply' and exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = 'credit_alloc' and t.ims_id = v_j.ims_id and t.voided_at is null) then
    raise exception 'Credit application % is already standing in QuickBooks — nothing to send — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'credit_apply_void' and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = 'credit_alloc' and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-2-1 이견 9: void retry = QBO 에 서 있을 때만
    raise exception 'Credit application % is not standing in QuickBooks — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'credit_apply_void' and exists (select 1 from public.so_credit_alloc a where a.id::text = v_j.ims_id and a.voided_at is null) then
    raise exception 'Credit application % is still applied in IMS — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
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
create or replace function public.qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text default null, p_intuit_tid text default null, p_note text default null, p_sku text default null, p_total_amt numeric default null, p_total_tax numeric default null, p_unapplied_amt numeric default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_j public.qbo_job%rowtype; v_type text; v_link_err text; v_unblocked int := 0; v_i public.so_invoice%rowtype; v_c public.so_credit%rowtype; v_mismatch text; v_n int; v_p public.so_payment%rowtype; v_applied numeric; v_sync jsonb;   -- 2e-1b v_p · v_applied · v_sync
        v_alabel text;   -- 2e-2-1
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
  elsif v_j.kind = 'credit_apply' then                                                                  -- 2e-2-1 판정 1009 · 1011: 거래 짝(credit_alloc ↔ 0 원 Payment · 지문 없음) + 대조(TotalAmt 0 · UnappliedAmt 0 · 상태는 sent · 자동 void 없음)
    v_alabel := coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check credit application ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> 0 then format('QuickBooks total %s is not 0 — check credit application %s in QuickBooks (942)', p_total_amt, v_alabel)
                       when p_unapplied_amt is not null and p_unapplied_amt <> 0 then format('QuickBooks unapplied %s is not 0 — check credit application %s in QuickBooks (942)', p_unapplied_amt, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'credit_alloc', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'credit_apply_void' then                                                             -- 2e-2-1 1011: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'credit_alloc' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent credit application on file to mark — check qbo_txn by hand'; end if;
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
  if v_j.kind in ('credit_apply', 'credit_apply_void') and v_link_err is null then                     -- 2e-2-1 이견 8: 보낸 뒤 상태 맞추기 — 보내는 동안 떼였으면 void 일감을 쌓는다
    begin v_sync := public.qbo_credit_alloc_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  return jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'state', case when v_link_err is null then 'sent' else 'failed' end, 'reconcile', v_sync, 'qbo_id', btrim(p_qbo_id), 'qbo_name', btrim(p_qbo_name), 'linked', v_link_err is null, 'link_error', v_link_err, 'unblocked', v_unblocked, 'mismatch', v_mismatch);
end;
$$;
comment on function public.qbo_job_claim(int, text[], uuid[]) is 'qbo-sync-2a · [2b1] · [2c1] · [2d1] · [2e-1b] · [2e-2-1 kinds 10 · 몸 credit_apply · credit_apply_void · wait 글은 몸의 wait_reason 우선(이견 4)]: 보내기 잡기(service_role) — ① 10 분 넘긴 sending → unknown ② 부모 sent 인 blocked → queued ③ queued → sending(kinds · job_ids) ④ 몸(실패 = failed · needs = blocked · wait_job = blocked) · jobs 에 body · check_lines · lookup · fingerprint ⑤ job_ids 결과';
comment on function public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric, numeric) is 'qbo-sync-2a · [2b1 합계] · [2c1 credit · credit_void] · [2e-1b payment · payment_void · 끝에 qbo_payment_sync] · [2e-2-1 credit_apply → qbo_txn credit_alloc ↔ Payment(doc_number = 일감 이름 · total_amt · fingerprint null · source sent) + 대조(TotalAmt 0 · UnappliedAmt 0 → mismatch + warning · 상태는 sent) · credit_apply_void → voided_at · 둘 다 끝에 qbo_credit_alloc_sync]: 보내기 성공(service_role) — sending · unknown → sent · customer · item 이면 qbo_entity upsert + qbo_link(created) · 거래면 qbo_txn + 대조 · void 면 voided_at · QBO Id 가 이미 다른 IMS 행의 짝이면 failed + 사람 말 · 자식(blocked_by) 풀기는 kind 무관';
comment on function public.qbo_job_retry(uuid, text) is 'qbo-sync-2a · [2d1 ④ skipped 되살리기] · [2e-1b A-4 결제 규칙] · [2e-2-1 이견 9: credit_apply 는 붙임 활성 · 인보이스 대상 · QBO 에 안 섰을 때만 · credit_apply_void 는 QBO 에 서 있고 붙임이 떼였을 때만]: failed · unknown(note 필수) · skipped(note 필수 · 문서 상태 · 같은 열쇠의 열린 일감 없음) → queued';

-- ═══ ⑦ grant — 새 함수 전부 grant 0(claim · done · 트리거 · 백필이 부른다) · done · requeue · claim · preview · doc · list · retry 는 create or replace 라 ACL 그대로 ═══
revoke all on function public.qbo_credit_apply_body(uuid), public.qbo_credit_apply_void_body(uuid), public.qbo_credit_alloc_sync(uuid, uuid), public.qbo_job_on_credit_alloc(), public.qbo_credit_apply_backfill()
  from public, anon, authenticated, service_role;
do $$
begin
  execute format('comment on table public.qbo_job is %L', coalesce(obj_description('public.qbo_job'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-2e-2-1: kind credit_apply · credit_apply_void(ims_kind credit_alloc · ims_id so_credit_alloc.id · 트리거 so_credit_alloc_qbo · 지문 없음 — 붙임 한 줄 = 0 원 Payment 한 장 · 1011)');
  execute format('comment on table public.qbo_txn is %L', coalesce(obj_description('public.qbo_txn'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-2e-2-1: ims_kind credit_alloc ↔ QBO Payment(0 원 · Invoice + CreditMemo 를 잇는다 · doc_number = 「CR → 인보이스」 · fingerprint null · source sent)');
end $$;

-- ═══ ⑧ 착지 · 백필 ═══
do $$
declare v text; v_n int; v_bad text := '';
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname, p.oid) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_job_done', 'qbo_job_claim', 'qbo_job_retry', 'qbo_credit_apply_body', 'qbo_credit_alloc_sync', 'qbo_payment_requeue', 'qbo_credit_apply_backfill');
  if v <> 'qbo_credit_alloc_sync(p_alloc_id uuid, p_by uuid)={postgres=X/postgres} qbo_credit_apply_backfill()={postgres=X/postgres} qbo_credit_apply_body(p_alloc_id uuid)={postgres=X/postgres} qbo_job_claim(p_limit integer, p_kinds text[], p_job_ids uuid[])={postgres=X/postgres,service_role=X/postgres} qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text, p_intuit_tid text, p_note text, p_sku text, p_total_amt numeric, p_total_tax numeric, p_unapplied_amt numeric)={postgres=X/postgres,service_role=X/postgres} qbo_job_retry(p_job uuid, p_note text)={postgres=X/postgres,authenticated=X/postgres} qbo_payment_requeue(p_invoice_id uuid)={postgres=X/postgres}' then
    raise exception '⑧ ACL unexpected: %', v;
  end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_body')        is distinct from 'e1aea51849844cc5898351daaa3ef533' then v_bad := v_bad || ' qbo_payment_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_void_body')   is distinct from '4ddb45cd728222d7b676d1e0bd169a54' then v_bad := v_bad || ' qbo_payment_void_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_sync')        is distinct from '9efb5d9f6007048692d13cd00623c4b8' then v_bad := v_bad || ' qbo_payment_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_fingerprint') is distinct from 'd6da0342942ef68345b9432e0e84da23' then v_bad := v_bad || ' qbo_payment_fingerprint'; end if;
  if v_bad <> '' then raise exception '⑧ payment functions changed by this migration (must not):%', v_bad; end if;
  if (select count(*) from pg_trigger where tgname = 'so_credit_alloc_qbo' and tgdeferrable and tginitdeferred) <> 1 then raise exception '⑧ trigger so_credit_alloc_qbo missing or not deferred'; end if;
  v_n := public.qbo_credit_apply_backfill();
  raise notice '⑧ credit application backfill: % job(s) queued (sale invoices since % · opening-linked applications wait for 1d)', v_n, coalesce((select c.value from public.inv_config c where c.key = 'qbo_send_since'), '?');
end $$;
-- 끝 — 적용 뒤: supabase/tests/qbo_sync_2e2_1_check.sql(-v mig 없이) → 2e-2-1b(EF) 배포 → cron 62 등록(kinds 넷 · supabase/ops/cron.sql) · qbo_send_payments_enabled 는 Caleb 이 켠다
