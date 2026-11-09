-- supabase/migrations/20261109230000_qbo_sync_4_5a_supplier_payment_jobs.sql — qbo-sync-4-5a: 공급처 결제(BillPayment) DB — 일감 · 몸 · 지문 맞추기 · 1124 · 환율 입력 길 (2026-11-09 · 지시서 ~/asung/prompts/qbo-sync-4-5a.md · §0 이견 1 ~ 20 Caleb 답 · 판정 1122 ~ 1125 · 1130 · 1132 ~ 1134 · 정본 qbo-integration §15-l · §15-m)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied 20261109230000 --yes · supabase db push 금지 · ⚠️ po_payment · po_payment_alloc 트리거 생성 + qbo_job · qbo_txn CHECK 교체(ACCESS EXCLUSIVE) — 토론토 17:00 뒤 또는 08:30 전
-- 설계 요지(§0 답):
--   · 이름 kind bill_payment · bill_payment_void · ims_kind po_payment · ims_id = po_payment.id · qbo_txn po_payment ↔ BillPayment(이견 1: qbo_txn CHECK 셋) · 일감은 queued 로 서되 자동으로 나가지 않는다(EF SEND_KINDS 밖 — 4-5b · cron 61 · 62 무접촉)
--   · 1132 ①②③ · 환율 · 계좌 · 거울(1133 · 없으면 Refresh list 안내 · 열쇠 detail->>'AccountType' · detail->'CurrencyRef'->>'value') 은 몸이 raise(사람 글) · 1134 PrivateNote 「IMS supplier payment <id>」 · lookup 에 열쇠 재료(EF 가 qbo_name 한 칸으로)
--   · 붙임 0 = 지문 null(이견 8) · 1132 ② 출구 = Retry(이견 9) · 트리거는 표에 deferred constraint(이견 10) · 환율 CHECK > 0 만(이견 11) · p_exchange_rate 는 맨 뒤(이견 12) · 1124 = 문서 공급처 둘 이상이면 거부 · p_supplier_id 어긋남은 경고 그대로(이견 13)
--   · CurrencyRef 늘(이견 14) · since 전 문서에 붙은 결제는 사람에게(이견 15) · bill_delete_manual 은 뗀 결제의 void 뒤(이견 6 안 ㄱ · void 일감 note 「detached from <ims_kind> <id>」)
--   · 새 표 0 · 거래 표 FK 0 · 시퀀스 0 · 자동 재시도 없음 · EF · 화면 · cron 무변 · 지시서 밖 재발행 1 = qbo_entity_upsert(Account 거울 detail 에 AccountType · CurrencyRef 를 받아 두는 자리 — 없으면 4-5b 의 pull 이 거울을 못 채운다)
-- 재발행 열하나(원본 = DB prosrc · pg_get_functiondef · 2026-11-09 · 끼운 줄 + 값 목록 줄 넷): qbo_job_claim 3add6d1e · qbo_job_done d95f2cca · qbo_job_preview 206d8b90 · qbo_job_retry af2b71ad · qbo_job_doc 31e53655 · qbo_job_list 63ba6c94 · qbo_job_on_po_doc_status 8942a51d · po_payment_alloc_guard f43a18bc · po_payment_create f9d01d6f(drop → create · p_exchange_rate) · po_payment_alloc_set 64c2c53a · qbo_entity_upsert 5bda00b0
-- ⚠️ 공개 레포 — 손님 · 공급처 상호 없음 · UI 글자는 영어 · jsonb_build_object 안에 「--」 줄 주석을 두지 않는다
-- 검증 supabase/tests/qbo_sync_4_5a_check.sql(운영 메인 begin → rollback · 가짜 재료만) · 적용은 Caleb

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

-- ═══════════════ ⓪ 재발행 원본 가드 — 열하나의 DB prosrc md5 · 아직 미적용 ═══════════════
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_claim') is distinct from '3add6d1e0842a768956f22e079c83788' then v_bad := v_bad || ' qbo_job_claim'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_done') is distinct from 'd95f2cca0029183689ad8e2a3da958a1' then v_bad := v_bad || ' qbo_job_done'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_preview') is distinct from '206d8b903c15e1c0fa3421c0db72c0b0' then v_bad := v_bad || ' qbo_job_preview'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_retry') is distinct from 'af2b71ad8bfff9dab76c0f726cd92299' then v_bad := v_bad || ' qbo_job_retry'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_doc') is distinct from '31e5365505740fe9c43ae85cd1613811' then v_bad := v_bad || ' qbo_job_doc'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_list') is distinct from '63ba6c946b28b589ccc2f38ecf7553c7' then v_bad := v_bad || ' qbo_job_list'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_on_po_doc_status') is distinct from '8942a51dc4c40dc8badf7c26ebaebd69' then v_bad := v_bad || ' qbo_job_on_po_doc_status'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_payment_alloc_guard') is distinct from 'f43a18bcb99341fc21f6b0b65d60cb32' then v_bad := v_bad || ' po_payment_alloc_guard'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_payment_create') is distinct from 'f9d01d6f3d932f47a69802fa5b0c970c' then v_bad := v_bad || ' po_payment_create'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_payment_alloc_set') is distinct from '64c2c53ae7a3daa3f4106a33a65513dc' then v_bad := v_bad || ' po_payment_alloc_set'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_entity_upsert') is distinct from '5bda00b06b7c6d6e32d601f3c4f6896f' then v_bad := v_bad || ' qbo_entity_upsert'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('po_payment_create', 'po_payment_alloc_set', 'qbo_job_claim', 'qbo_job_done')) <> 4 then v_bad := v_bad || ' (duplicate signatures)'; end if;
  if to_regprocedure('public.qbo_bill_payment_body(uuid)') is not null or exists (select 1 from pg_constraint where conname = 'qbo_job_kind_ck' and pg_get_constraintdef(oid) like '%bill_payment%')
     or exists (select 1 from pg_trigger where tgname in ('po_payment_qbo', 'po_payment_alloc_qbo')) then v_bad := v_bad || ' (4-5a already applied?)'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current bodies first — nothing was changed', v_bad; end if;
end $$;

-- ═══════════════ ① CHECK — qbo_job kind 25 · ims_kind 15 · 짝 명시 가지 · qbo_txn po_payment ↔ BillPayment · po_payment.exchange_rate > 0 ═══════════════
alter table public.qbo_job
  drop constraint qbo_job_kind_ck,
  add  constraint qbo_job_kind_ck check (kind in ('customer', 'item', 'invoice', 'credit', 'invoice_void', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void',
                                                  'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day', 'vendor', 'bill', 'vendor_credit', 'bill_delete_manual', 'bill_payment', 'bill_payment_void')),
  drop constraint qbo_job_ims_kind_ck,
  add  constraint qbo_job_ims_kind_ck check (ims_kind in ('customer', 'product', 'charge', 'invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund', 'cost_sheet', 'supplier', 'po_invoice', 'po_credit', 'po_charge', 'po_payment')),
  drop constraint qbo_job_pair_ck,
  add  constraint qbo_job_pair_ck check (ims_kind = case kind when 'customer' then 'customer' when 'invoice' then 'invoice' when 'invoice_void' then 'invoice' when 'credit' then 'credit' when 'credit_void' then 'credit'
                                                                                        when 'payment' then 'payment' when 'payment_void' then 'payment' when 'credit_apply' then 'credit_alloc' when 'credit_apply_void' then 'credit_alloc'
                                                                                        when 'opening_credit' then 'opening_alloc' when 'opening_credit_void' then 'opening_alloc' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc'
                                                                                        when 'refund' then 'refund' when 'refund_void' then 'refund' when 'refund_apply' then 'refund' when 'refund_apply_void' then 'refund'
                                                                                        when 'cost_day' then 'cost_sheet' when 'vendor' then 'supplier' when 'vendor_credit' then 'po_credit'
                                                                                        when 'bill_payment' then 'po_payment' when 'bill_payment_void' then 'po_payment' else ims_kind end
                                                and (kind <> 'item' or ims_kind in ('product', 'charge'))
                                                and (kind <> 'bill' or ims_kind in ('po_invoice', 'po_charge'))
                                                and (kind <> 'bill_delete_manual' or ims_kind in ('po_invoice', 'po_credit', 'po_charge')));
alter table public.qbo_txn
  drop constraint qbo_txn_kind_ck,
  add  constraint qbo_txn_kind_ck check (ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_credit', 'opening_alloc', 'refund', 'refund_apply', 'cost_sheet', 'po_invoice', 'po_credit', 'po_charge', 'po_payment')),
  drop constraint qbo_txn_type_ck,
  add  constraint qbo_txn_type_ck check (qbo_type in ('Invoice', 'CreditMemo', 'Payment', 'Purchase', 'JournalEntry', 'Bill', 'VendorCredit', 'BillPayment')),
  drop constraint qbo_txn_pair_ck,
  add  constraint qbo_txn_pair_ck check (qbo_type = case ims_kind when 'invoice' then 'Invoice' when 'credit' then 'CreditMemo' when 'opening_credit' then 'CreditMemo' when 'refund' then 'Purchase' when 'cost_sheet' then 'JournalEntry'
                                                                  when 'po_invoice' then 'Bill' when 'po_charge' then 'Bill' when 'po_credit' then 'VendorCredit' when 'po_payment' then 'BillPayment' else 'Payment' end);
alter table public.po_payment
  add constraint po_payment_exchange_rate_ck check (exchange_rate is null or exchange_rate > 0);   -- §0 이견 11: 통화 조건은 CHECK 에 못 넣는다 · CAD 결제의 환율은 몸이 안 싣고 지문에서도 뺀다(1 이 아니면 경고)

-- ═══════════════ ② 지문 · 몸 · void 몸 ═══════════════
create function public.qbo_bill_payment_fingerprint(p_payment_id uuid) returns text
  language sql stable security definer set search_path = public, pg_temp
as $$
  select case when exists (select 1 from public.po_payment_alloc a where a.po_payment_id = p.id)
              then md5(concat_ws('|', trim_scale(p.amount)::text, p.paid_on::text, trim_scale(p.discount_taken)::text, coalesce(p.account_id::text, ''), c.code,
                                 case when c.code <> coalesce(nullif(btrim((select x.value from public.inv_config x where x.key = 'base_currency')), ''), 'CAD') then coalesce(trim_scale(p.exchange_rate)::text, '') else '' end,
                                 coalesce(btrim(p.reference), ''),
                                 (select string_agg(coalesce(a.po_invoice_id, a.po_charge_id)::text || ':' || trim_scale(a.amount)::text || ':' || trim_scale(a.discount_amount)::text, ',' order by coalesce(a.po_invoice_id, a.po_charge_id))
                                    from public.po_payment_alloc a where a.po_payment_id = p.id)))
         end
    from public.po_payment p join public.ref_currency c on c.id = p.currency_id where p.id = p_payment_id;
$$;
comment on function public.qbo_bill_payment_fingerprint(uuid) is '[qbo-sync-4-5a · grant 0] 공급처 결제의 QuickBooks 지문 — 몸을 만드는 값 전부(금액 · 결제일 · 할인 · 계좌 · 통화 · 외화면 환율 · reference · 붙임마다 문서:금액:할인) · 붙임 0 이면 null(= 보낼 줄 없음 · 보낸 장은 void · §0 이견 8) · 결제 행이 없으면 null · 바뀌면 qbo_bill_payment_sync 가 void + 다시 보내기';

create function public.qbo_bill_payment_body(p_payment_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_realm text := public.qbo_realm_of(); v_home text := coalesce(nullif(btrim((select c.value from public.inv_config c where c.key = 'base_currency')), ''), 'CAD');
  v_p public.po_payment%rowtype; v_s public.supplier%rowtype; v_a public.ref_account%rowtype; v_label text; v_cur text; v_acur text; v_sup_id uuid; v_sup_n int; v_n int;
  v_vendor text; v_ap text; v_ap_cur text; v_acct text; v_mirror jsonb; v_mtype text; v_mcur text; v_doc text; v_cut boolean := false; v_ref text; v_note text; v_applied numeric := 0; v_disc numeric := 0; v_gap numeric; v_credit_docs text;
  v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_lines jsonb := '[]'::jsonb; v_checks jsonb := '[]'::jsonb; v_wait uuid; v_wait_doc text; v_pay jsonb; v_body jsonb;
  a record; v_t public.qbo_txn%rowtype; v_bj public.qbo_job%rowtype;
  c_hand constant text := 'Enter this payment in QuickBooks by hand, then press Skip on this job';
begin
  select * into v_p from public.po_payment p where p.id = p_payment_id;
  if v_p.id is null then raise exception 'No IMS supplier payment % — nothing was sent', p_payment_id; end if;
  v_label := coalesce(nullif(btrim(coalesce(v_p.reference, '')), ''), 'of ' || v_p.paid_on::text || ' ' || trim_scale(v_p.amount)::text);
  select c.code into v_cur from public.ref_currency c where c.id = v_p.currency_id;
  if v_cur is null then raise exception 'Supplier payment % has no currency — nothing was sent', v_label; end if;
  -- 붙임 집계 — 0 이면 보낼 줄이 없다(지문 null · §0 이견 8) · 공급처 둘 이상이면 1124
  select count(*), count(distinct coalesce(i.supplier_id, c.supplier_id)), coalesce(sum(x.amount), 0), coalesce(sum(x.discount_amount), 0), (array_agg(coalesce(i.supplier_id, c.supplier_id)))[1]
    into v_n, v_sup_n, v_applied, v_disc, v_sup_id
    from public.po_payment_alloc x left join public.po_invoice i on i.id = x.po_invoice_id left join public.po_charge c on c.id = x.po_charge_id where x.po_payment_id = v_p.id;
  if v_n = 0 then raise exception 'Supplier payment % has no document applied — nothing to send (if it was sent, a void job takes care of QuickBooks) — nothing was sent', v_label; end if;
  if v_sup_n > 1 then raise exception 'Supplier payment % is applied to documents of % suppliers — one payment, one supplier (1124); split it into one payment per supplier — nothing was sent', v_label, v_sup_n; end if;
  -- 판정 1132 ① ② ③ — QuickBooks 에 그대로 옮길 수 없는 결제는 사람에게(검사 순서 §0 이견 4: 1132 → 환율 → 계좌 → 거울)
  if v_p.discount_taken > 0 or v_disc > 0 then
    raise exception '% (1132 ①: supplier payment % takes an early-payment discount of % %) — or remove the discount in IMS and it is sent again — nothing was sent', c_hand, v_label, trim_scale(greatest(v_p.discount_taken, v_disc)), v_cur;
  end if;
  select string_agg(i.invoice_number, ', ' order by i.invoice_number) into v_credit_docs
    from public.po_payment_alloc x join public.po_invoice i on i.id = x.po_invoice_id
   where x.po_payment_id = v_p.id and exists (select 1 from public.po_invoice cr where cr.credit_for_invoice_id = i.id and cr.doc_kind = 'credit' and cr.status = 'confirmed');
  if v_credit_docs is not null then
    raise exception '% (1132 ②: invoice % has a supplier credit applied to it in IMS, so the amount paid is not the bill amount) — or detach the credit in IMS, then press Retry — nothing was sent', c_hand, v_credit_docs;
  end if;
  v_gap := round(v_p.amount + v_p.discount_taken - v_applied, 2);
  if v_gap <> 0 then
    raise exception '% (1132 ③: the amounts applied to documents add up to % but the payment is % %, gap %) — or fix the lines in IMS and it is sent again — nothing was sent', c_hand, trim_scale(v_applied), trim_scale(v_p.amount), v_cur, trim_scale(v_gap);
  end if;
  -- 환율(1123 · 1118) — 외화만 · CAD 의 환율은 안 싣는다
  if v_cur <> v_home and (v_p.exchange_rate is null or v_p.exchange_rate <= 0) then
    raise exception 'Supplier payment % is in % but has no exchange rate — enter the MTFX rate of the day the money was bought (1123) on the payment and it is sent again (1118) — nothing was sent', v_label, v_cur;
  end if;
  if v_cur = v_home and v_p.exchange_rate is not null and v_p.exchange_rate <> 1 then v_warn := array_append(v_warn, format('exchange rate %s on a %s payment is ignored', trim_scale(v_p.exchange_rate), v_home)); end if;
  -- 계좌(1133 · 1122) — BANK → Check · CREDITCARD → CreditCard · 통화 = 결제 통화 · QBO 짝 · 거울 대조
  if v_p.account_id is null then raise exception 'Supplier payment % has no bank or card account — choose the account on the payment and it is sent again — nothing was sent', v_label; end if;
  select * into v_a from public.ref_account ra where ra.id = v_p.account_id;
  if coalesce(v_a.account_type, '') not in ('BANK', 'CREDITCARD') then
    raise exception 'Supplier payment % is paid from % (%) which is a % account — a supplier payment goes out of a BANK or CREDITCARD account (1133); choose another account — nothing was sent', v_label, v_a.code, v_a.name, coalesce(v_a.account_type, '?');
  end if;
  v_acur := public.ims_account_currency(v_a.id);
  if v_acur is distinct from v_cur then raise exception '%', public.ims_account_currency_msg('Payment', v_label, 'bank', v_a.code, v_acur, v_cur); end if;
  v_acct := public.qbo_account_ref(v_a.code, 'payment account ' || v_a.code);
  select e.detail into v_mirror from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'Account' and e.qbo_id = v_acct;
  v_mtype := v_mirror->>'AccountType'; v_mcur := v_mirror->'CurrencyRef'->>'value';
  if v_mtype is null or v_mcur is null then
    raise exception 'QuickBooks account #% (IMS %) has no account type or currency on file yet — Settings → QuickBooks matching → Refresh list (accounts), then retry (1133) — nothing was sent', v_acct, v_a.code;
  end if;
  if lower(replace(v_mtype, ' ', '')) <> lower(replace(v_a.account_type, ' ', '')) then
    raise exception 'IMS account % is % but QuickBooks account #% is "%" — fix the account type in IMS or the match under Settings → QuickBooks matching, then retry (1133) — nothing was sent', v_a.code, v_a.account_type, v_acct, v_mtype;
  end if;
  if upper(btrim(v_mcur)) <> v_cur then
    raise exception 'IMS account % is a % account but QuickBooks account #% is in % — fix the account currency in IMS or the match under Settings → QuickBooks matching, then retry (1133) — nothing was sent', v_a.code, v_cur, v_acct, v_mcur;
  end if;
  -- 공급처 · Vendor 짝(1128 · 없으면 need) · APAccountRef(bill 몸 규칙 · 통화 = 결제 통화)
  select * into v_s from public.supplier s where s.id = v_sup_id;
  select l.qbo_id into v_vendor from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'supplier' and l.ims_id = v_s.id::text;
  if v_vendor is null then v_needs := v_needs || jsonb_build_object('kind', 'vendor', 'ims_id', v_s.id::text, 'name', v_s.name); end if;
  v_ap := public.qbo_account_ref(v_s.account_payable_code, 'supplier payable account');
  select public.ims_account_currency(ra.id) into v_ap_cur from public.ref_account ra where ra.code = v_s.account_payable_code;
  if v_ap_cur is distinct from v_cur then raise exception 'Supplier payment % is in % but the supplier payable account % is a % account — fix the supplier (Suppliers → payable account) and retry — nothing was sent', v_label, v_cur, v_s.account_payable_code, coalesce(v_ap_cur, '?'); end if;
  -- 줄 = 붙임마다 · LinkedTxn = 그 문서의 Bill(qbo_txn · 청구서 Bill 포함) · Bill 이 아직 안 갔으면 그 첫 일감 뒤(wait_job) · since 전 문서는 사람에게
  for a in select x.amount, case when x.po_invoice_id is not null then 'po_invoice' else 'po_charge' end as ims_kind, coalesce(x.po_invoice_id, x.po_charge_id) as doc_id,
                  coalesce(i.invoice_number, c.charge_number) as number, coalesce(i.status, c.status) as status, coalesce(i.created_at, c.created_at) as created_at, case when x.po_invoice_id is not null then 'Invoice' else 'Charge' end as label
             from public.po_payment_alloc x left join public.po_invoice i on i.id = x.po_invoice_id left join public.po_charge c on c.id = x.po_charge_id
            where x.po_payment_id = v_p.id order by coalesce(i.invoice_number, c.charge_number), x.created_at, x.id loop
    if a.status <> 'confirmed' then raise exception '% % is % — only a confirmed document is paid in QuickBooks — nothing was sent', a.label, a.number, a.status; end if;
    select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = a.ims_kind and t.ims_id = a.doc_id::text and t.voided_at is null;
    if v_t.id is not null then
      v_lines := v_lines || jsonb_build_object('Amount', a.amount, 'LinkedTxn', jsonb_build_array(jsonb_build_object('TxnId', v_t.qbo_id, 'TxnType', 'Bill')));
      v_checks := v_checks || jsonb_build_object('doc_number', a.number, 'qbo_bill_id', v_t.qbo_id, 'amount', a.amount);
    elsif not public.qbo_po_since_ok(a.created_at) then
      raise exception '% (% % was created in IMS before the QuickBooks start date — its bill did not come from IMS) — nothing was sent', c_hand, a.label, a.number;
    else
      select * into v_bj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'bill' and j.ims_kind = a.ims_kind and j.ims_id = a.doc_id::text order by j.created_at desc, j.id desc limit 1;
      if v_bj.id is null then raise exception '% % has no QuickBooks bill job — confirm and send the bill first — nothing was sent', a.label, a.number; end if;
      if v_bj.state = 'skipped' then raise exception 'The bill job of % % was skipped — skip this payment too, or retry the bill first — nothing was sent', lower(a.label), a.number; end if;
      if v_bj.state = 'sent' then raise exception 'The bill job of % % is sent but no QuickBooks bill is on file — check qbo_txn by hand — nothing was sent', lower(a.label), a.number; end if;
      if v_wait is null then v_wait := v_bj.id; v_wait_doc := a.number; end if;
    end if;
  end loop;
  -- DocNumber = reference(21 자 · 1130 꼴 · 전체는 PrivateNote) · PrivateNote 표지(1134)
  v_ref := nullif(btrim(coalesce(v_p.reference, '')), '');
  if v_ref is not null and length(v_ref) > 21 then v_cut := true; v_warn := array_append(v_warn, format('reference "%s" cut to 21 characters for QuickBooks (1130) — the full reference is in the private note', v_ref)); end if;
  v_doc := case when v_ref is null then null else public.qbo_doc_number_21(v_ref) end;
  v_note := 'IMS supplier payment ' || v_p.id::text || case when v_cut then ' · full reference: ' || v_ref else '' end;
  if v_p.paid_on > public.ims_today() then v_warn := array_append(v_warn, format('post-dated: QuickBooks bill payment dated %s', v_p.paid_on)); end if;
  v_pay := case v_a.account_type when 'BANK' then jsonb_build_object('PayType', 'Check', 'CheckPayment', jsonb_build_object('BankAccountRef', jsonb_build_object('value', v_acct), 'PrintStatus', 'NotSet'))
                                 else jsonb_build_object('PayType', 'CreditCard', 'CreditCardPayment', jsonb_build_object('CCAccountRef', jsonb_build_object('value', v_acct))) end;
  v_body := jsonb_strip_nulls(jsonb_build_object(
    'DocNumber', v_doc, 'TxnDate', to_char(v_p.paid_on, 'YYYY-MM-DD'), 'TotalAmt', v_p.amount,
    'VendorRef', case when v_vendor is not null then jsonb_build_object('value', v_vendor) end,
    'APAccountRef', jsonb_build_object('value', v_ap),
    'CurrencyRef', jsonb_build_object('value', v_cur), 'ExchangeRate', case when v_cur <> v_home then trim_scale(v_p.exchange_rate) end,
    'PrivateNote', left(v_note, 4000), 'Line', v_lines)) || v_pay;
  return jsonb_build_object('kind', 'bill_payment', 'ims_kind', 'po_payment', 'ims_id', v_p.id::text, 'name', coalesce(v_ref, 'Supplier payment ' || v_p.paid_on::text || ' ' || trim_scale(v_p.amount)::text), 'doc_number', v_doc, 'supplier_id', v_s.id,
    'body', v_body, 'needs', v_needs, 'wait_job', v_wait, 'wait_invoice', v_wait_doc, 'wait_reason', case when v_wait is not null then format('waiting for bill %s to reach QuickBooks first — send it too', v_wait_doc) end,
    'warnings', to_jsonb(v_warn), 'line_count', jsonb_array_length(v_lines),
    'totals', jsonb_build_object('amount', v_p.amount, 'applied', v_applied, 'currency', v_cur, 'exchange_rate', case when v_cur <> v_home then v_p.exchange_rate end),
    'fingerprint', public.qbo_bill_payment_fingerprint(v_p.id), 'check_lines', v_checks,
    'lookup', jsonb_build_object('entity', 'BillPayment', 'vendor_ref', v_vendor, 'txn_date', to_char(v_p.paid_on, 'YYYY-MM-DD'), 'total_amt', v_p.amount, 'total_cents', round(v_p.amount * 100)::bigint, 'currency', v_cur,
                                 'private_note', 'IMS supplier payment ' || v_p.id::text, 'account_ref', v_acct, 'pay_type', v_pay->>'PayType'));
end;
$$;
comment on function public.qbo_bill_payment_body(uuid) is '[qbo-sync-4-5a · 판정 1122 ~ 1125 · 1130 · 1132 ~ 1134 · 4-2b 규칙 · grant 0] 공급처 결제 → QuickBooks BillPayment 몸 — 막기 = raise(사람 글) · 먼저 만들 것 = needs(Vendor) · Bill 이 아직 안 갔으면 wait_job · 검사 순서 1132 ①②③ → 환율(외화) → 계좌(BANK · CREDITCARD · 통화 · 짝) → 거울 AccountType · CurrencyRef(없으면 Refresh list 안내) · 줄 = 붙임마다 LinkedTxn Bill · PayType Check(+PrintStatus NotSet) | CreditCard · CurrencyRef 늘 · ExchangeRate 외화만 · DocNumber = reference 21 자 · PrivateNote 「IMS supplier payment <id>」(1134 열쇠) · 공급처 상호는 몸에 없다';

create function public.qbo_bill_payment_void_body(p_payment_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_t public.qbo_txn%rowtype; v_label text;
begin
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'po_payment' and t.ims_id = p_payment_id::text;
  v_label := coalesce(nullif(btrim(coalesce(v_t.doc_number, '')), ''), 'Supplier payment ' || p_payment_id::text);
  if v_t.id is null then raise exception 'Supplier payment % was never sent to QuickBooks — nothing to void', v_label; end if;
  if v_t.voided_at is not null then raise exception 'Supplier payment % (QuickBooks bill payment #%) is already voided — nothing was sent', v_label, v_t.qbo_id; end if;
  return jsonb_build_object('kind', 'bill_payment_void', 'ims_kind', 'po_payment', 'ims_id', p_payment_id::text, 'name', v_label, 'doc_number', v_t.doc_number, 'qbo_id', v_t.qbo_id,
    'body', jsonb_strip_nulls(jsonb_build_object('Id', v_t.qbo_id, 'SyncToken', v_t.sync_token, 'sparse', true)), 'needs', '[]'::jsonb,
    'warnings', case when v_t.sync_token is null then '["no SyncToken on file — the sender reads the bill payment first"]'::jsonb else '[]'::jsonb end,
    'lookup', jsonb_build_object('entity', 'BillPayment', 'qbo_id', v_t.qbo_id, 'private_note', 'IMS supplier payment ' || p_payment_id::text));
end;
$$;
comment on function public.qbo_bill_payment_void_body(uuid) is '[qbo-sync-4-5a · 판정 1125 · 4-2b E-13 · grant 0] 공급처 결제 void 몸 — qbo_txn(qbo_id · sync_token)만으로 {Id, SyncToken, sparse} · 결제 행은 이미 지워졌을 수 있다(po_doc_delete · 직접 DELETE) · EF(4-5b)가 billpayment?operation=update&include=void 로 보낸다';

-- ═══════════════ ③ 맞추기 · 표 트리거 · 백필 ═══════════════
create function public.qbo_bill_payment_sync(p_payment_id uuid, p_by uuid, p_detached text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton); v_p public.po_payment%rowtype; v_fp text; v_t public.qbo_txn%rowtype; v_pj public.qbo_job%rowtype; v_vj public.qbo_job%rowtype; v_act text := 'none'; v_vid uuid;
begin
  if v_realm is null then return jsonb_build_object('action', 'no_connection'); end if;
  select * into v_p from public.po_payment p where p.id = p_payment_id;                                                                 -- 행이 없으면(지워짐) 지문 null = void 만(§1-C)
  if v_p.id is not null and not public.qbo_po_since_ok(v_p.created_at) then return jsonb_build_object('action', 'not_applicable'); end if;   -- since 전에 만든 결제는 아무것도(4 건은 모두 since 뒤)
  v_fp := public.qbo_bill_payment_fingerprint(p_payment_id);
  select * into v_t  from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'po_payment' and t.ims_id = p_payment_id::text;
  select * into v_pj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'bill_payment'      and j.ims_kind = 'po_payment' and j.ims_id = p_payment_id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_vj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'bill_payment_void' and j.ims_kind = 'po_payment' and j.ims_id = p_payment_id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  if v_vj.id is not null and p_detached is not null and v_vj.note not like '%' || p_detached || '%' then                              -- §0 이견 6 안 ㄱ: 뗀 문서를 void 일감 note 에(bill_delete_manual 이 찾는다)
    update public.qbo_job j set note = left(concat_ws(' · ', j.note, 'detached from ' || p_detached), 2000) where j.id = v_vj.id;
  end if;
  if v_t.id is null then                                                                                                               -- 보낸 적 없다
    if v_pj.id is null then
      if v_fp is not null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'bill_payment', 'po_payment', p_payment_id::text, 'queued', p_by)
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'queued';
      end if;
    elsif v_pj.state in ('queued', 'blocked', 'failed') then
      if v_fp is null then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'supplier payment deleted or fully detached before sending'), 2000), updated_by = p_by where j.id = v_pj.id;
        v_act := 'skipped';
      elsif v_pj.state = 'failed' and v_fp is distinct from v_pj.fingerprint then
        update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: the payment changed after it failed'), 2000), updated_by = p_by where j.id = v_pj.id;
        v_act := 'requeued';
      end if;                                                                                                                          -- queued · blocked 는 그대로(claim 이 그때의 상태로 몸을 다시 만든다)
    elsif v_pj.state in ('sending', 'unknown') then                                                                                   -- 닿았는지 모른다 → void 를 그 일감 뒤에 · 다시 보내기는 done 의 reconcile 이 쌓는다
      if v_fp is distinct from v_pj.fingerprint and v_vj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'bill_payment_void', 'po_payment', p_payment_id::text, 'blocked', v_pj.id, p_by, concat_ws(' · ', 'changed while sending — void after the send settles', 'detached from ' || p_detached))
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'void_after_send';
      end if;
    end if;
  elsif v_t.voided_at is null then                                                                                                     -- QBO 에 서 있다
    if v_fp is not distinct from v_t.fingerprint then                                                                                 -- IMS = QBO 그대로 → 아직 안 나간 void 는 거둔다 · 나가는 중이면 다시 보내기를 그 뒤에
      if v_vj.id is not null and v_vj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'payment restored to what QuickBooks has — void not needed'), 2000), updated_by = p_by where j.id = v_vj.id;
        if v_pj.id is not null and v_pj.state in ('queued', 'blocked', 'failed') then                                              -- 그 void 뒤에 섰던 다시 보내기도 거둔다(skipped 부모는 claim ② 가 못 푼다 · 시험 S7b)
          update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'payment restored to what QuickBooks has — nothing to send again'), 2000), updated_by = p_by where j.id = v_pj.id;
        end if;
        return jsonb_build_object('action', 'void_cancelled', 'fingerprint', v_fp);
      elsif v_vj.id is not null and v_pj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'bill_payment', 'po_payment', p_payment_id::text, 'blocked', v_vj.id, p_by, 'sent again after the void that is under way')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        return jsonb_build_object('action', 'resend_after_void', 'fingerprint', v_fp);
      end if;
      return jsonb_build_object('action', 'same', 'fingerprint', v_fp);
    end if;
    if v_vj.id is null then
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note)
      values (v_realm, 'bill_payment_void', 'po_payment', p_payment_id::text, 'queued', p_by,
              concat_ws(' · ', case when v_fp is null then 'supplier payment deleted or fully detached — void in QuickBooks' else 'supplier payment changed — void, then send again' end, 'detached from ' || p_detached))
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_vid;
      if v_vid is null then select j.id into v_vid from public.qbo_job j where j.realm_id = v_realm and j.kind = 'bill_payment_void' and j.ims_kind = 'po_payment' and j.ims_id = p_payment_id::text and j.state not in ('sent', 'skipped') order by j.created_at desc limit 1; end if;
    else v_vid := v_vj.id; end if;
    if v_fp is not null then
      if v_pj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'bill_payment', 'po_payment', p_payment_id::text, 'blocked', v_vid, p_by, 'sent again after the void')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      elsif v_pj.state in ('queued', 'failed', 'blocked') and v_pj.blocked_by is distinct from v_vid then                        -- blocked 도 이 void 뒤로 옮긴다(claim 이 void 뒤에 몸을 다시 만든다)
        update public.qbo_job j set state = 'blocked', blocked_by = v_vid, claimed_at = null, next_at = now(), request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'waits for the void of the earlier QuickBooks bill payment'), 2000), updated_by = p_by where j.id = v_pj.id;
      end if;
      v_act := 'void_and_resend';
    else
      if v_pj.id is not null and v_pj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'supplier payment deleted or fully detached — only the void goes'), 2000), updated_by = p_by where j.id = v_pj.id;
      end if;
      v_act := 'void';
    end if;
  else                                                                                                                                 -- QBO 쪽은 void 됐다
    if v_fp is not null then
      if v_pj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'bill_payment', 'po_payment', p_payment_id::text, 'queued', p_by, 'sent again after the void')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'resend';
      elsif v_pj.state = 'failed' and v_fp is distinct from v_pj.fingerprint then
        update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: the payment changed after it failed'), 2000), updated_by = p_by where j.id = v_pj.id;
        v_act := 'requeued';
      end if;
    elsif v_pj.id is not null and v_pj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'supplier payment deleted or fully detached before sending'), 2000), updated_by = p_by where j.id = v_pj.id;
      v_act := 'skipped';
    end if;
  end if;
  return jsonb_build_object('action', v_act, 'fingerprint', v_fp);
end;
$$;
comment on function public.qbo_bill_payment_sync(uuid, uuid, text) is '[qbo-sync-4-5a · 판정 1125 · §0 이견 6 · 8 · 10 · grant 0] 공급처 결제 ↔ QuickBooks BillPayment 맞추기(손님 qbo_payment_sync 꼴) — 보낸 장 없음 → 새 일감 · 지문 다름 → void + 새 장은 void 뒤 blocked · 결제 지워짐 · 붙임 0 → void 만 · 안 나간 일감은 갈아 끼우거나 skip · 멱등(표 트리거가 행마다 부른다) · p_detached = 「po_invoice <id>」 꼴을 void 일감 note 에(bill_delete_manual 이 그 뒤에 선다)';

create function public.qbo_job_on_po_payment() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_pid uuid; v_by uuid; v_det text;
begin
  if tg_table_name = 'po_payment' then
    if tg_op = 'DELETE' then v_pid := old.id; v_by := coalesce(old.updated_by, old.paid_by); else v_pid := new.id; v_by := coalesce(new.updated_by, new.paid_by); end if;
  else
    if tg_op = 'DELETE' then v_pid := old.po_payment_id; v_by := old.updated_by; v_det := case when old.po_invoice_id is not null then 'po_invoice ' || old.po_invoice_id::text else 'po_charge ' || old.po_charge_id::text end;
    else v_pid := new.po_payment_id; v_by := new.updated_by; end if;
    if v_by is null then select coalesce(p.updated_by, p.paid_by) into v_by from public.po_payment p where p.id = v_pid; end if;   -- 붙임 줄에는 사람 칸이 없다 → 결제의 사람(by_staff 가 화면에 보인다)
  end if;
  begin
    perform public.qbo_bill_payment_sync(v_pid, v_by, v_det);
  exception when others then                                                                                                           -- 결제 저장 · 고치기 · 지우기를 막지 않는다 — failed 일감으로 흔적
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff)
      select c.realm_id, 'bill_payment', 'po_payment', v_pid::text, 'failed', left('could not queue: ' || sqlerrm, 2000), v_by from public.qbo_connection c where c.singleton
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$$;
comment on function public.qbo_job_on_po_payment() is '[qbo-sync-4-5a · §0 이견 10 · grant 0] po_payment(UPDATE · DELETE) · po_payment_alloc(INSERT · UPDATE · DELETE) 표 트리거 — 지우기 · 고치기 길이 넷(창구 둘 · 직접 둘)이라 함수가 아니라 표에 건다 · deferred constraint trigger 라 트랜잭션 끝에 행마다 돈다 · sync 가 멱등이라 일감은 하나 · 붙임 DELETE 는 뗀 문서 id 를 넘긴다 · 예외는 삼킨다(failed 일감)';
create constraint trigger po_payment_qbo       after update or delete           on public.po_payment       deferrable initially deferred for each row execute function public.qbo_job_on_po_payment();
create constraint trigger po_payment_alloc_qbo after insert or update or delete on public.po_payment_alloc deferrable initially deferred for each row execute function public.qbo_job_on_po_payment();

create function public.qbo_bill_payment_backfill() returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton); v_r record; v_n int := 0; v_seen int := 0; v_s jsonb;
begin
  if v_realm is null then return jsonb_build_object('skipped', 'QuickBooks is not connected', 'queued', 0, 'seen', 0); end if;
  for v_r in select p.id, p.paid_by from public.po_payment p
              where public.qbo_po_since_ok(p.created_at) and exists (select 1 from public.po_payment_alloc a where a.po_payment_id = p.id)
                and not exists (select 1 from public.qbo_job j where j.realm_id = v_realm and j.ims_kind = 'po_payment' and j.ims_id = p.id::text)
                and not exists (select 1 from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'po_payment' and t.ims_id = p.id::text)
              order by p.created_at, p.id loop
    v_seen := v_seen + 1;
    v_s := public.qbo_bill_payment_sync(v_r.id, v_r.paid_by, null);
    if v_s->>'action' = 'queued' then v_n := v_n + 1; end if;
  end loop;
  return jsonb_build_object('realm_id', v_realm, 'seen', v_seen, 'queued', v_n);
end;
$$;
comment on function public.qbo_bill_payment_backfill() is '[qbo-sync-4-5a · grant 0] since 뒤에 만든 붙임 ≥ 1 인 공급처 결제에 일감을 한 번(멱등 · 일감 · txn 이 있으면 건너뜀) — queued 로만 서고 자동으로 나가지 않는다(EF SEND_KINDS 밖 · 4-5b) · 밀린 4 건: CAD 1 은 거울 값 없음 · USD 3 은 환율 없음으로 claim 때 failed 가 정상(4-5b 배포 + Refresh list · 환율 입력 뒤 다시)';

-- ═══════════════ ④ 재발행 열하나 — DB prosrc 그대로 + 끼운 줄(머리 · 서명 · definer · search_path 그대로 · ACL 그대로 · po_payment_create 만 drop → create) ═══════════════

-- ═══ qbo_job_claim — kinds 24 · 몸 CASE 둘에 bill_payment · bill_payment_void ═══
CREATE OR REPLACE FUNCTION public.qbo_job_claim(p_limit integer DEFAULT 15, p_kinds text[] DEFAULT ARRAY['customer'::text, 'item'::text], p_job_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_realm text := public.qbo_realm_of(); v_stale int; v_unblocked int; v_ids uuid[]; v_j public.qbo_job%rowtype; v_open public.qbo_job%rowtype; v_b jsonb; v_rows jsonb := '[]'::jsonb; v_failed int := 0; v_blocked int := 0; v_waiting int := 0; v_last uuid; v_cust uuid; v_nj jsonb; e jsonb;
  v_kinds text[] := coalesce(p_kinds, array['customer', 'item']);
  v_pick uuid[] := (select array_agg(distinct x) from unnest(p_job_ids) x where x is not null);                                       -- 2d1: 고른 id(중복 · null 제거) · null 이면 옛 길(가장 오래된 것부터 p_limit)
  v_needs jsonb := '[]'::jsonb; v_req jsonb := '[]'::jsonb; v_r record;
  v_held int := 0; v_emptied int := 0;   -- 3-2b: 재생성 hold · 줄 0 empty 수
begin
  if not public.doc_is_service() then raise exception 'qbo_job_claim is for the send worker only — nothing was read'; end if;
  if not (v_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day', 'vendor', 'bill', 'vendor_credit', 'bill_payment', 'bill_payment_void']) or coalesce(array_length(v_kinds, 1), 0) = 0 then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void, refund, refund_void, refund_apply, refund_apply_void, cost_day, vendor, bill, vendor_credit, bill_payment, bill_payment_void (got %)', v_kinds; end if;   -- 4-5a kinds 24(bill_payment · bill_payment_void · EF 4-5b 전에는 SEND_KINDS 밖 → 화면 Send 는 wrong_kind)   -- 4-3a kinds 22(bill_delete_manual 은 보내는 kind 가 아니다 · 1126)   -- 2e-3-2-1 kinds 18 · 3-2b cost_day 19
  if p_job_ids is not null and coalesce(array_length(v_pick, 1), 0) = 0 then raise exception 'job_ids must name at least one job — nothing was read'; end if;
  if coalesce(array_length(v_pick, 1), 0) > 200 then raise exception 'job_ids may name at most 200 jobs in one call (got %) — nothing was read', array_length(v_pick, 1); end if;
  -- ① 멈춘 sending(EF 가 도중에 죽었다 · QBO 에 닿았는지 모른다) → unknown(mail_claim 꼴 · 자동 재전송 금지 · 다음 send 가 이름 · DocNumber 로 조회해 푼다)
  update public.qbo_job j set state = 'unknown', claimed_at = null,
         last_error = left(coalesce(j.last_error || ' · ', '') || format('stale: still sending %s after claim (attempt %s) — QuickBooks may or may not have it', date_trunc('second', now() - j.claimed_at), j.attempts), 2000)
   where j.realm_id = v_realm and j.state = 'sending' and j.claimed_at < now() - interval '10 minutes';
  get diagnostics v_stale = row_count;
  -- ② 부모가 보내졌으면 자식을 연다(손님 → 자식 손님 · need → 인보이스 · 인보이스 → void · 인보이스 → 크레딧)
  update public.qbo_job j set state = 'queued', next_at = now() from public.qbo_job p where j.realm_id = v_realm and j.state = 'blocked' and p.id = j.blocked_by and (p.state = 'sent' or (j.kind = 'cost_day' and p.state = 'skipped') or (j.kind in ('bill', 'vendor_credit') and p.kind = 'bill_delete_manual' and p.state = 'skipped'));   -- 4-3a: 복원된 문서의 새 Bill 은 옛 Bill 을 QBO 에서 손으로 지운 뒤(bill_delete_manual skipped) 나간다(1126)   -- 3-2b ⬜3: 하루 원가 장은 앞 장 skip(void)도 푼다 — 보낸 몫 0 이라 뒤 장 차액이 그 몫을 담는다(1092)
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
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'refund' then public.qbo_refund_body(v_j.ims_id::uuid) when 'refund_void' then public.qbo_refund_void_body(v_j.ims_id::uuid) when 'refund_apply' then public.qbo_refund_apply_body(v_j.ims_id::uuid) when 'refund_apply_void' then public.qbo_refund_apply_void_body(v_j.ims_id::uuid)   -- 2e-3-2-1 refund · refund_void · refund_apply · refund_apply_void
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid)
                           when 'cost_day' then public.qbo_cost_day_body(public.qbo_cost_sheet_id_for_job(v_j.id))
                           when 'bill_payment' then public.qbo_bill_payment_body(v_j.ims_id::uuid) when 'bill_payment_void' then public.qbo_bill_payment_void_body(v_j.ims_id::uuid)   -- 4-5a 공급처 결제(1124 · 1132 · 1133 · 1134 · ims_kind po_payment)
                           when 'vendor' then public.qbo_vendor_body(v_j.ims_id::uuid) when 'bill' then case v_j.ims_kind when 'po_charge' then public.qbo_charge_bill_body(v_j.ims_id::uuid) else public.qbo_bill_body(v_j.ims_id::uuid, 'bill') end when 'vendor_credit' then public.qbo_vendor_credit_body(v_j.ims_id::uuid) end;   -- 4-3a vendor(1128) · bill(po_invoice 1115 ~ 1118 · po_charge 1129) · vendor_credit(1121)   -- 3-2b cost_day(하루 원가 장 · 몸은 장 id 로)   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void   -- 2c1 credit · credit_void
      if v_b is null then raise exception 'kind % has no body', v_j.kind; end if;
      if v_b->>'parent_customer_id' is not null then raise exception 'parent customer is not in QuickBooks yet — send the parent first (job was not blocked: parent link removed?)'; end if;
      if v_b->>'hold' is not null then                                                                                                 -- 3-2b ⬜4 · 판정 1093: 재생성 세대가 바뀌었다 → realm 의 미보낸 장 전부 hold · 일감 failed(풀어 주는 길은 last_error 에 · retry 는 거부 · release 가 연다)
        perform public.qbo_cost_hold_all(v_realm, v_b->>'hold');
        update public.qbo_job j set state = 'failed', claimed_at = null, last_error = left(v_b->>'hold', 2000) where j.id = v_j.id;
        v_held := v_held + 1;
        continue;
      end if;
      if coalesce((v_b->>'empty')::boolean, false) then                                                                                 -- 3-2b 이견 4: claim 때 보낼 줄 0 → 장 empty · 일감 skipped(note 자동 · skipped_ck) — 트리거는 empty 장을 void 로 바꾸지 않는다
        update public.qbo_cost_sheet s set state = 'empty', note = left(concat_ws(' · ', s.note, 'nothing to send at claim time'), 2000) where s.id = (v_b->>'sheet_id')::uuid;
        update public.qbo_job j set state = 'skipped', claimed_at = null, note = 'nothing to send at claim time — the cost day has no lines left (sheet marked empty)' where j.id = v_j.id;
        v_emptied := v_emptied + 1;
        continue;
      end if;
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
      if v_j.kind = 'cost_day' and v_b->>'sheet_kind' = 'day' then                                                                       -- 3-2b ⬜2 · 이견 9: 줄은 claim 때 굳는다 — 보낸 몫 행을 지금 넣는다(장은 트리거로 이미 sending · calc 는 이 순간부터 이 장을 보낸 몫으로 센다 · done 은 다시 셈하지 않는다 · rebuild 장의 행은 release 때 굳었다)
        insert into public.qbo_cost_sent (sheet_id, realm_id, wh, key_kind, doc_key, acct_a, acct_b, cents)
        select (v_b->>'sheet_id')::uuid, v_realm, v_b->>'wh', x.key_kind, x.doc_key, x.acct_a, x.acct_b, x.cents
          from jsonb_to_recordset(v_b->'lines') as x(key_kind text, doc_key text, acct_a text, acct_b text, cents bigint);
      end if;
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
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'refund' then public.qbo_refund_body(v_j.ims_id::uuid) when 'refund_void' then public.qbo_refund_void_body(v_j.ims_id::uuid) when 'refund_apply' then public.qbo_refund_apply_body(v_j.ims_id::uuid) when 'refund_apply_void' then public.qbo_refund_apply_void_body(v_j.ims_id::uuid)   -- 2e-3-2-1 refund · refund_void · refund_apply · refund_apply_void
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid)
                           when 'cost_day' then public.qbo_cost_day_body(public.qbo_cost_sheet_id_for_job(v_j.id))
                           when 'bill_payment' then public.qbo_bill_payment_body(v_j.ims_id::uuid) when 'bill_payment_void' then public.qbo_bill_payment_void_body(v_j.ims_id::uuid)   -- 4-5a 공급처 결제(1124 · 1132 · 1133 · 1134 · ims_kind po_payment)
                           when 'vendor' then public.qbo_vendor_body(v_j.ims_id::uuid) when 'bill' then case v_j.ims_kind when 'po_charge' then public.qbo_charge_bill_body(v_j.ims_id::uuid) else public.qbo_bill_body(v_j.ims_id::uuid, 'bill') end when 'vendor_credit' then public.qbo_vendor_credit_body(v_j.ims_id::uuid) end;   -- 4-3a vendor(1128) · bill(po_invoice 1115 ~ 1118 · po_charge 1129) · vendor_credit(1121)   -- 3-2b cost_day(하루 원가 장 · 몸은 장 id 로)   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
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
  return jsonb_build_object('realm_id', v_realm, 'kinds', to_jsonb(v_kinds), 'picked', case when v_pick is null then null else to_jsonb(v_pick) end, 'recovered_unknown', v_stale, 'unblocked', v_unblocked, 'claimed', coalesce(array_length(v_ids, 1), 0), 'body_failed', v_failed, 'blocked_for_needs', v_blocked, 'blocked_for_invoice', v_waiting, 'held', v_held, 'emptied', v_emptied,
                            'need_jobs', v_needs, 'requested', v_req, 'jobs', v_rows);
end;
$function$
;

-- ═══ qbo_job_preview — 몸 CASE ═══
CREATE OR REPLACE FUNCTION public.qbo_job_preview(p_job uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_j public.qbo_job%rowtype; v_b jsonb; v_err text; v_needs jsonb := '[]'::jsonb; e jsonb; v_open public.qbo_job%rowtype; v_wait public.qbo_job%rowtype; v_parent public.qbo_job%rowtype; v_blocked jsonb; v_wait_j jsonb;
begin
  select * into v_j from public.qbo_job j where j.id = p_job and j.realm_id = v_realm;
  if v_j.id is null then raise exception 'Job % not found — nothing to preview', p_job; end if;
  begin
    v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                         when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                         when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid)
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid)
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'refund' then public.qbo_refund_body(v_j.ims_id::uuid) when 'refund_void' then public.qbo_refund_void_body(v_j.ims_id::uuid) when 'refund_apply' then public.qbo_refund_apply_body(v_j.ims_id::uuid) when 'refund_apply_void' then public.qbo_refund_apply_void_body(v_j.ims_id::uuid)   -- 2e-3-2-1 refund · refund_void · refund_apply · refund_apply_void
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid)
                           when 'cost_day' then public.qbo_cost_day_body(public.qbo_cost_sheet_id_for_job(v_j.id))
                           when 'bill_payment' then public.qbo_bill_payment_body(v_j.ims_id::uuid) when 'bill_payment_void' then public.qbo_bill_payment_void_body(v_j.ims_id::uuid)   -- 4-5a 공급처 결제(1124 · 1132 · 1133 · 1134 · ims_kind po_payment)
                           when 'vendor' then public.qbo_vendor_body(v_j.ims_id::uuid) when 'bill' then case v_j.ims_kind when 'po_charge' then public.qbo_charge_bill_body(v_j.ims_id::uuid) else public.qbo_bill_body(v_j.ims_id::uuid, 'bill') end when 'vendor_credit' then public.qbo_vendor_credit_body(v_j.ims_id::uuid) end;   -- 4-3a vendor(1128) · bill(po_invoice 1115 ~ 1118 · po_charge 1129) · vendor_credit(1121)   -- 3-2b cost_day(하루 원가 장 · 몸은 장 id 로)   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
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
    'hold', v_b->>'hold', 'empty', coalesce((v_b->>'empty')::boolean, false),   -- 3-2b: 재생성 hold 글 · 줄 0
    'sendable', (v_err is null and jsonb_array_length(v_needs) = 0 and v_wait_j is null and v_j.state = 'queued' and v_b->>'hold' is null and not coalesce((v_b->>'empty')::boolean, false)),
    'preview_only', true);
end;
$function$
;

-- ═══ qbo_job_done — bill_payment(qbo_txn BillPayment · 942 대조) · bill_payment_void(voided_at) · 보낸 뒤 맞추기 ═══
CREATE OR REPLACE FUNCTION public.qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text DEFAULT NULL::text, p_intuit_tid text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_sku text DEFAULT NULL::text, p_total_amt numeric DEFAULT NULL::numeric, p_total_tax numeric DEFAULT NULL::numeric, p_unapplied_amt numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_j public.qbo_job%rowtype; v_type text; v_link_err text; v_unblocked int := 0; v_i public.so_invoice%rowtype; v_c public.so_credit%rowtype; v_mismatch text; v_n int; v_p public.so_payment%rowtype; v_applied numeric; v_sync jsonb;   -- 2e-1b v_p · v_applied · v_sync
        v_alabel text;   -- 2e-2-1
        v_oa public.so_payment_alloc%rowtype;   -- 2e-3-1
        v_cs public.qbo_cost_sheet%rowtype;   -- 3-2b
        v_pp public.po_payment%rowtype;   -- 4-5a
begin
  if not public.doc_is_service() then raise exception 'qbo_job_done is for the send worker only — nothing was saved'; end if;
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('sending', 'unknown') then raise exception 'Only a job being sent, or one whose result is unknown, can be finished (this one is %) — nothing was saved', v_j.state; end if;
  if nullif(btrim(coalesce(p_qbo_id, '')), '') is null or nullif(btrim(coalesce(p_qbo_name, '')), '') is null then raise exception 'qbo_id and qbo_name are required — nothing was saved'; end if;
  update public.qbo_job j set state = 'sent', sent_at = now(), claimed_at = null, qbo_id = btrim(p_qbo_id), qbo_name = btrim(p_qbo_name), sync_token = p_sync_token, last_intuit_tid = coalesce(p_intuit_tid, j.last_intuit_tid),
         last_error = case when p_note is not null then left(coalesce(j.last_error || ' · ', '') || p_note, 2000) else j.last_error end, attempts = j.attempts + case when p_note is not null then 1 else 0 end
   where j.id = v_j.id;
  if v_j.kind in ('customer', 'item', 'vendor') then                                                    -- 4-3a vendor(1128): 거울 Vendor + qbo_link supplier created
    v_type := case v_j.ims_kind when 'customer' then 'Customer' when 'supplier' then 'Vendor' else 'Item' end;
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
  elsif v_j.kind = 'opening_credit' then                                                                -- 2e-3-1 이견 14: 거래 짝(opening_credit ↔ 「쓰기」 CreditMemo) + 대조(TotalAmt = 붙임 금액 ∧ TotalTax 0 · 상태는 sent · 자동 void 없음)
    select * into v_oa from public.so_payment_alloc a where a.id = v_j.ims_id::uuid;
    v_alabel := coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null or p_total_tax is null then 'QuickBooks did not return TotalAmt / TotalTax — check opening credit ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> v_oa.amount or p_total_tax <> 0 then format('QuickBooks total %s / tax %s differs from IMS %s / 0 — check opening credit %s in QuickBooks (942)', p_total_amt, p_total_tax, v_oa.amount, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'opening_credit', v_j.ims_id, 'CreditMemo', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, CreditMemo, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks CreditMemo #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'opening_credit_void' then                                                           -- 2e-3-1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'opening_credit' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent opening credit memo on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'opening_apply' then                                                                 -- 2e-3-1 이견 14: 거래 짝(opening_alloc ↔ 0 원 Payment · 지문 없음) + 대조(TotalAmt 0 · UnappliedAmt 0 · 상태는 sent)
    v_alabel := coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check opening credit application ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> 0 then format('QuickBooks total %s is not 0 — check opening credit application %s in QuickBooks (942)', p_total_amt, v_alabel)
                       when p_unapplied_amt is not null and p_unapplied_amt <> 0 then format('QuickBooks unapplied %s is not 0 — check opening credit application %s in QuickBooks (942)', p_unapplied_amt, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'opening_alloc', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'opening_apply_void' then                                                            -- 2e-3-1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'opening_alloc' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent opening credit application on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'refund' then                                                                       -- 2e-3-2-1 이견 15: 거래 짝(refund ↔ Purchase) + 대조(TotalAmt = 크레딧 몫 합 · TotalTax 0 · 상태는 sent · 자동 void 없음)
    select * into v_p from public.so_payment p where p.id = v_j.ims_id::uuid;
    select coalesce(sum(a.amount), 0) into v_applied from public.so_credit_alloc a where a.refund_payment_id = v_p.id and a.voided_at is null;
    v_alabel := public.qbo_refund_label(v_p);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check refund ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> v_applied then format('QuickBooks total %s differs from IMS %s (credit-note part of refund %s) — check it in QuickBooks (942)', p_total_amt, v_applied, v_alabel)
                       when p_total_tax is not null and p_total_tax <> 0 then format('QuickBooks tax %s is not 0 — check refund %s in QuickBooks (942)', p_total_tax, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'refund', v_j.ims_id, 'Purchase', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Purchase, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Purchase #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'refund_void' then                                                                  -- 2e-3-2-1 ⓖ-7: 거래 짝에 void 흔적(EF 는 TotalAmt 0 ∧ 「Voided - 」 로 done)
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'refund' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent refund expense on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'refund_apply' then                                                                 -- 2e-3-2-1 이견 15: 거래 짝(refund_apply ↔ 0 원 Payment · 지문 없음) + 대조(TotalAmt 0 · UnappliedAmt 0 · 상태는 sent)
    v_alabel := coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check the zero payment of refund ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> 0 then format('QuickBooks total %s is not 0 — check the zero payment of refund %s in QuickBooks (942)', p_total_amt, v_alabel)
                       when p_unapplied_amt is not null and p_unapplied_amt <> 0 then format('QuickBooks unapplied %s is not 0 — check the zero payment of refund %s in QuickBooks (942)', p_unapplied_amt, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'refund_apply', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'refund_apply_void' then                                                            -- 2e-3-2-1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'refund_apply' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent refund zero payment on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'cost_day' then                                                                     -- 3-2b: 거래 짝(cost_sheet ↔ JournalEntry · doc_number = DocNumber) + 대조(TotalAmt = 차변 센트 합 · 지문 「<차변 센트>|<줄 md5>」 는 claim 이 적었다) · 장은 트리거로 sent · 줄은 다시 셈하지 않는다(이견 9)
    select * into v_cs from public.qbo_cost_sheet s where s.job_id = v_j.id;
    v_alabel := coalesce(v_cs.doc_number, v_j.ims_id);
    v_mismatch := case when v_cs.id is null then 'IMS has no cost day sheet attached to this job — check qbo_cost_sheet by hand'
                       when p_total_amt is null then 'QuickBooks did not return TotalAmt — check journal entry ' || v_alabel || ' in QuickBooks'
                       when round(p_total_amt * 100) <> coalesce(nullif(split_part(coalesce(v_j.fingerprint, ''), '|', 1), '')::bigint, -1) then format('QuickBooks total %s differs from IMS %s — check journal entry %s in QuickBooks (942)', p_total_amt, round(coalesce(nullif(split_part(coalesce(v_j.fingerprint, ''), '|', 1), '')::bigint, 0) / 100.0, 2), v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'cost_sheet', v_j.ims_id, 'JournalEntry', btrim(p_qbo_id), coalesce(v_cs.doc_number, btrim(p_qbo_name)), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, v_j.fingerprint, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = excluded.fingerprint, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, JournalEntry, qbo_id) 가 이미 다른 IMS 행의 짝 → 일감 failed · 장은 트리거가 unknown 으로(행 유지 · 사람이 resolve)
      v_link_err := format('QuickBooks JournalEntry #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind in ('bill', 'vendor_credit') then                                                      -- 4-3a: 거래 짝(po_invoice · po_charge ↔ Bill · po_credit ↔ VendorCredit) + 대조(TotalAmt = 문서 통화 센트 · 지문 「<센트>|<통화>」 · 1127 · 942 꼴 · 상태는 sent · 자동 delete 없음 1126)
    v_alabel := coalesce(public.qbo_job_doc(v_j.ims_kind, v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_type := case v_j.kind when 'bill' then 'Bill' else 'VendorCredit' end;
    v_mismatch := case when p_total_amt is null then format('QuickBooks did not return TotalAmt — check %s %s in QuickBooks', lower(v_type), v_alabel)
                       when nullif(split_part(coalesce(v_j.fingerprint, ''), '|', 1), '') !~ '^-?[0-9]+$' then format('IMS has no expected total on this job — check %s %s in QuickBooks by hand', lower(v_type), v_alabel)
                       when round(p_total_amt * 100) <> split_part(v_j.fingerprint, '|', 1)::bigint then format('QuickBooks total %s differs from IMS %s — check %s %s in QuickBooks (942)', p_total_amt, round(split_part(v_j.fingerprint, '|', 1)::bigint / 100.0, 2), lower(v_type), v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, v_j.ims_kind, v_j.ims_id, v_type, btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null, v_j.fingerprint, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = excluded.fingerprint, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Bill | VendorCredit, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks %s #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', v_type, btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'bill_payment' then                                                                  -- 4-5a: 거래 짝(po_payment ↔ BillPayment) + 대조(TotalAmt = 결제 통화 금액 · 942 꼴) · 지문은 claim 이 적었다 · 결제가 그새 지워졌으면 글(reconcile 이 void 를 쌓는다)
    select * into v_pp from public.po_payment p where p.id = v_j.ims_id::uuid;
    v_alabel := coalesce(public.qbo_job_doc('po_payment', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when v_pp.id is null then 'the IMS supplier payment was deleted while it was being sent — check bill payment ' || v_alabel || ' in QuickBooks (a void job follows)'
                       when p_total_amt is null then 'QuickBooks did not return TotalAmt — check bill payment ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> v_pp.amount then format('QuickBooks total %s differs from IMS %s — check bill payment %s in QuickBooks (942)', p_total_amt, v_pp.amount, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'po_payment', v_j.ims_id, 'BillPayment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, v_j.fingerprint, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = excluded.fingerprint, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, BillPayment, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks BillPayment #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'bill_payment_void' then                                                             -- 4-5a: 거래 짝에 void 흔적(1125)
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'po_payment' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent bill payment on file to mark — check qbo_txn by hand'; end if;
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
  if v_j.kind in ('opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void') and v_link_err is null then   -- 2e-3-1 이견 14: 보낸 뒤 상태 맞추기 — 보내는 동안 떼였으면 void 일감을 쌓는다 · CreditMemo 가 서면 apply 는 ② 가 푼다
    begin v_sync := public.qbo_opening_alloc_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  if v_j.kind in ('bill_payment', 'bill_payment_void') and v_link_err is null then                     -- 4-5a: 보낸 뒤 맞추기 — 보내는 동안 붙임 · 머리가 바뀌었으면 void · 다시 보내기 일감을 쌓는다(손님 결제 2e-1b A-10 꼴)
    begin v_sync := public.qbo_bill_payment_sync(v_j.ims_id::uuid, v_j.by_staff, null);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  if v_j.kind in ('refund', 'refund_void', 'refund_apply', 'refund_apply_void') and v_link_err is null then   -- 2e-3-2-1 이견 15: 보낸 뒤 상태 맞추기 — 보내는 동안 void 됐으면 void 일감을 쌓는다 · Purchase 가 서면 apply 는 ② 가 푼다
    begin v_sync := public.qbo_refund_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  return jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'state', case when v_link_err is null then 'sent' else 'failed' end, 'reconcile', v_sync, 'qbo_id', btrim(p_qbo_id), 'qbo_name', btrim(p_qbo_name), 'linked', v_link_err is null, 'link_error', v_link_err, 'unblocked', v_unblocked, 'mismatch', v_mismatch);
end;
$function$
;

-- ═══ qbo_job_retry — bill_payment(지문 null 거부) · bill_payment_void(서 있을 때만) ═══
CREATE OR REPLACE FUNCTION public.qbo_job_retry(p_job uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_staff uuid := public.qbo_key_gate(true); v_j public.qbo_job%rowtype; v_doc jsonb; v_open uuid; v_cs public.qbo_cost_sheet%rowtype;   -- 3-2b v_cs
begin
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('failed', 'unknown', 'skipped') then raise exception 'Only a failed or skipped job, or one whose result is unknown, can be sent again (this one is %) — nothing was saved', v_j.state; end if;
  if v_j.state = 'unknown' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say what you checked in QuickBooks (a note is required when the result was unknown) — nothing was saved'; end if;
  if v_j.kind = 'bill_delete_manual' then raise exception 'This job asks for a QuickBooks record to be deleted by hand — it is closed with Skip after deleting, it is never sent — nothing was saved'; end if;   -- 4-3a 1126
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
  if v_j.kind in ('opening_credit', 'opening_apply') and not exists (select 1 from public.so_payment_alloc a where a.id::text = v_j.ims_id and a.voided_at is null) then   -- 2e-3-1 이견 13: 붙임 retry = 활성 ∧ 그 장이 QBO 에 안 섰을 때만
    raise exception 'Opening credit % was detached — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind in ('opening_credit', 'opening_apply') and exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'opening_credit' then 'opening_credit' else 'opening_alloc' end and t.ims_id = v_j.ims_id and t.voided_at is null) then
    raise exception 'Opening credit % (%) is already standing in QuickBooks — nothing to send — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'opening_credit' then 'credit memo' else 'zero payment' end;
  end if;
  if v_j.kind in ('opening_credit_void', 'opening_apply_void') and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'opening_credit_void' then 'opening_credit' else 'opening_alloc' end and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-3-1 이견 13: void retry = 그 장이 QBO 에 서 있을 때만
    raise exception 'Opening credit % (%) is not standing in QuickBooks — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'opening_credit_void' then 'credit memo' else 'zero payment' end;
  end if;
  if v_j.kind in ('opening_credit_void', 'opening_apply_void') and exists (select 1 from public.so_payment_alloc a where a.id::text = v_j.ims_id and a.voided_at is null) then
    raise exception 'Opening credit % is still applied in IMS — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind in ('refund', 'refund_apply') and not exists (select 1 from public.so_payment p where p.id::text = v_j.ims_id and p.kind = 'refund' and p.status = 'active') then   -- 2e-3-2-1 이견 14: 환불 retry = 활성 ∧ 그 장이 QBO 에 안 섰을 때만(컷은 보지 않는다 — ⓖ-4 의 「Retry」 = Send)
    raise exception 'Refund % is voided — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind in ('refund', 'refund_apply') and exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'refund' then 'refund' else 'refund_apply' end and t.ims_id = v_j.ims_id and t.voided_at is null) then
    raise exception 'Refund % (%) is already standing in QuickBooks — nothing to send — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'refund' then 'expense' else 'zero payment' end;
  end if;
  if v_j.kind in ('refund_void', 'refund_apply_void') and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'refund_void' then 'refund' else 'refund_apply' end and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-3-2-1 이견 14: void retry = 그 장이 QBO 에 서 있을 때만(ⓖ-5 알림 일감은 여기서 거부 → Skip)
    raise exception 'Refund % (%) is not standing in QuickBooks — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'refund_void' then 'expense' else 'zero payment' end;
  end if;
  if v_j.kind in ('refund_void', 'refund_apply_void') and exists (select 1 from public.so_payment p where p.id::text = v_j.ims_id and p.kind = 'refund' and p.status = 'active') then
    raise exception 'Refund % is still active in the IMS — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'bill_payment' and public.qbo_bill_payment_fingerprint(v_j.ims_id::uuid) is null then                                  -- 4-5a: 공급처 결제 retry = 결제가 있고 붙임 ≥ 1 일 때만(지워졌거나 전부 뗐으면 void 일감의 몫)
    raise exception 'Supplier payment % was deleted or has no document applied — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce(public.qbo_job_doc('po_payment', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'bill_payment_void' and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = 'po_payment' and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 4-5a: void retry = QBO 에 서 있을 때만
    raise exception 'Supplier payment % is not standing in QuickBooks — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('po_payment', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'cost_day' then                                                                                                        -- 3-2b: 하루 원가 장 retry = 장이 hold(재생성) 면 거부 → release 로 · sent 면 거부 · 같은 창고 뒤 장이 이미 나갔으면 거부(그 몫을 뒤 장이 담았다 · 1092) · skip 된 rebuild 장은 다시 못 보낸다(release 다시)
    select * into v_cs from public.qbo_cost_sheet s where s.job_id = v_j.id;
    if v_cs.id is null then raise exception 'No cost day sheet is attached to job % — nothing was saved', v_j.id; end if;
    if v_cs.state = 'hold' then raise exception 'Cost day % is on hold after a cost rebuild — review it under Cost days → rebuild preview and release it (qbo_cost_rebuild_release) — nothing was saved', v_cs.doc_number; end if;
    if v_cs.state = 'sent' then raise exception 'Cost day % is already in QuickBooks — nothing to send — nothing was saved', v_cs.doc_number; end if;
    if exists (select 1 from public.qbo_cost_sheet s where s.realm_id = v_cs.realm_id and s.wh = v_cs.wh and s.kind = 'day' and s.sheet_date > v_cs.sheet_date and s.state in ('sent', 'sending', 'unknown')) then
      raise exception 'A later cost day of % already went to QuickBooks and carried these amounts — % cannot be sent again — nothing was saved', v_cs.wh, v_cs.doc_number;
    end if;
    if v_j.state = 'skipped' then
      if v_cs.kind = 'rebuild' then raise exception 'A skipped rebuild sheet (%) cannot be sent again — release the rebuild again under Cost days — nothing was saved', v_cs.doc_number; end if;
      if nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say why this skipped job should be sent after all (a note is required) — nothing was saved'; end if;
      update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, blocked_by = null, request_id = gen_random_uuid(), note = btrim(p_note), updated_by = v_staff where j.id = v_j.id;
      return jsonb_build_object('job_id', v_j.id, 'state', 'queued', 'attempts', v_j.attempts, 'was', 'skipped');
    end if;
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
    if v_j.kind in ('bill', 'vendor_credit') and coalesce(v_doc->>'doc_status', '') <> 'confirmed' then                                   -- 4-3a: 공급처 문서는 confirmed 일 때만 다시
      raise exception '% % is % — a skipped job can only be sent again while the supplier document is confirmed — nothing was saved', case v_j.kind when 'bill' then 'Bill for' else 'Vendor credit for' end, coalesce(v_doc->>'doc_number', v_j.ims_id), coalesce(v_doc->>'doc_status', 'missing');
    end if;
    select j.id into v_open from public.qbo_job j where j.realm_id = v_j.realm_id and j.kind = v_j.kind and j.ims_kind = v_j.ims_kind and j.ims_id = v_j.ims_id and j.state not in ('sent', 'skipped') and j.id <> v_j.id limit 1;
    if v_open is not null then raise exception 'Another open job (%) already exists for this % — send or skip that one instead — nothing was saved', v_open, v_j.kind; end if;
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, blocked_by = null, request_id = gen_random_uuid(), note = btrim(p_note), updated_by = v_staff where j.id = v_j.id;
    return jsonb_build_object('job_id', v_j.id, 'state', 'queued', 'attempts', v_j.attempts, 'was', 'skipped');
  end if;
  update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = coalesce(nullif(btrim(p_note), ''), j.note), updated_by = v_staff where j.id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'state', 'queued', 'attempts', v_j.attempts, 'was', v_j.state);
end;
$function$
;

-- ═══ qbo_job_doc — po_payment ═══
CREATE OR REPLACE FUNCTION public.qbo_job_doc(p_ims_kind text, p_ims_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    when 'opening_alloc' then (select jsonb_build_object('doc_number', public.qbo_opening_doc_number(a.id) || ' → ' || i.invoice_number, 'name', (select cu.name from public.customer cu where cu.id = p.customer_id), 'customer_id', p.customer_id, 'currency', p.currency_code, 'total', a.amount, 'doc_date', (a.created_at at time zone 'America/Toronto')::date, 'doc_status', case when a.voided_at is null then 'active' else 'voided' end)
                                 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id join public.so_invoice i on i.id = a.invoice_id where a.id::text = p_ims_id)   -- 2e-3-1: 이월 돈 붙임 = 「OC-<인보이스>-<n> → 인보이스」 · 돈의 주인(이견 4) · 통화 · 붙임 금액 · 붙인 날(토론토) · active | voided
    when 'refund' then (select jsonb_build_object('doc_number', public.qbo_refund_label(p), 'name', (select cu.name from public.customer cu where cu.id = p.customer_id), 'customer_id', p.customer_id, 'currency', p.currency_code, 'total', p.amount, 'doc_date', p.paid_on, 'doc_status', p.status)
                          from public.so_payment p where p.id::text = p_ims_id and p.kind = 'refund')   -- 2e-3-2-1: 환불 = reference(없으면 「Refund <날> <금액>」) · 손님 · 통화 · 금액 · 결제일 · active | voided
    when 'cost_sheet' then (select jsonb_build_object('doc_number', s.doc_number, 'name', case s.kind when 'rebuild' then 'IMS cost rebuild ' else 'Cost day ' end || s.sheet_date::text || ' ' || s.wh, 'customer_id', null, 'currency', 'CAD', 'total', round(s.built_debit_cents / 100.0, 2), 'doc_date', s.sheet_date, 'doc_status', s.state)
                              from public.qbo_cost_sheet s where s.realm_id = public.qbo_realm_of() and s.sheet_date = split_part(p_ims_id, '|', 1)::date and s.wh = split_part(p_ims_id, '|', 2)
                               and s.kind = case when split_part(p_ims_id, '|', 3) = 'rebuild' then 'rebuild' else 'day' end)   -- 3-2b: 하루 원가 장 = ims_id 「YYYY-MM-DD|TOR[|rebuild]」 · 이름 「Cost day <날> <창고>」 · 금액 = 만들 때 차변 · 상태 = 장 state
    when 'po_invoice' then (select jsonb_build_object('doc_number', i.invoice_number, 'name', (select s.name from public.supplier s where s.id = i.supplier_id), 'customer_id', null, 'currency', (select c.code from public.ref_currency c where c.id = i.currency_id), 'total', m.computed_total, 'doc_date', i.invoice_date, 'doc_status', i.status)
                              from public.po_invoice i join public.po_invoice_money m on m.id = i.id where i.id::text = p_ims_id and i.doc_kind = 'invoice')   -- 4-3a: 공급처 인보이스 = 번호 · 공급처 · 통화 · 줄 합 + 세금 · 날짜 · draft | confirmed | cancelled
    when 'po_credit' then (select jsonb_build_object('doc_number', i.invoice_number, 'name', (select s.name from public.supplier s where s.id = i.supplier_id), 'customer_id', null, 'currency', (select c.code from public.ref_currency c where c.id = i.currency_id), 'total', m.computed_total, 'doc_date', i.invoice_date, 'doc_status', i.status)
                             from public.po_invoice i join public.po_invoice_money m on m.id = i.id where i.id::text = p_ims_id and i.doc_kind = 'credit')   -- 4-3a: 공급처 크레딧(doc_kind credit)
    when 'po_charge' then (select jsonb_build_object('doc_number', c.charge_number, 'name', (select s.name from public.supplier s where s.id = c.supplier_id), 'customer_id', null, 'currency', (select r.code from public.ref_currency r where r.id = c.currency_id), 'total', c.total_amount + c.tax_amount, 'doc_date', c.charge_date, 'doc_status', c.status)
                             from public.po_charge c where c.id::text = p_ims_id)   -- 4-3a: 비용 문서 = 번호 · 공급처 · 통화 · 금액 + 세금 · 날짜 · 상태
    when 'supplier' then (select jsonb_build_object('doc_number', null, 'name', s.name, 'customer_id', null, 'currency', (select r.code from public.ref_currency r where r.id = s.currency_id), 'total', null, 'doc_date', null, 'doc_status', case when s.is_active then 'active' else 'inactive' end)
                            from public.supplier s where s.id::text = p_ims_id)   -- 4-3a: 공급처(Vendor 일감)
    when 'po_payment' then (select jsonb_build_object('doc_number', coalesce(nullif(btrim(coalesce(p.reference, '')), ''), 'Supplier payment ' || p.paid_on::text || ' ' || trim_scale(p.amount)::text),
                                                      'name', (select string_agg(distinct s.name, ', ') from public.po_payment_alloc a left join public.po_invoice i on i.id = a.po_invoice_id left join public.po_charge c on c.id = a.po_charge_id join public.supplier s on s.id = coalesce(i.supplier_id, c.supplier_id) where a.po_payment_id = p.id),
                                                      'customer_id', null, 'currency', (select r.code from public.ref_currency r where r.id = p.currency_id), 'total', p.amount, 'doc_date', p.paid_on, 'doc_status', 'active')
                              from public.po_payment p where p.id::text = p_ims_id)   -- 4-5a: 공급처 결제 = reference(없으면 「Supplier payment <날> <금액>」) · 붙임의 공급처 · 통화 · 금액 · 결제일 · 상태 없음(지워지면 행이 없다 → null)
    else jsonb_build_object('doc_number', p_ims_id, 'name', p_ims_id, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', null) end;
$function$
;

-- ═══ qbo_job_list — kinds 25 · txn 잇기에 po_payment ═══
CREATE OR REPLACE FUNCTION public.qbo_job_list(p_state text DEFAULT NULL::text, p_kinds text[] DEFAULT NULL::text[], p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_q text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if p_state is not null and p_state not in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped', 'open') then raise exception 'state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open (got %)', p_state; end if;
  if p_kinds is not null and (not (p_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day', 'vendor', 'bill', 'vendor_credit', 'bill_delete_manual', 'bill_payment', 'bill_payment_void']) or coalesce(array_length(p_kinds, 1), 0) = 0) then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void, refund, refund_void, refund_apply, refund_apply_void, cost_day, vendor, bill, vendor_credit, bill_delete_manual, bill_payment, bill_payment_void (got %)', p_kinds; end if;   -- 4-5a kinds 25   -- 2e-3-2-1 kinds 18 · 3-2b cost_day 19
  if p_from is not null and p_to is not null and p_from > p_to then raise exception 'from % is after to % — nothing was read', p_from, p_to; end if;
  return (with base as (
      select j.id, j.kind, j.ims_kind, j.ims_id, j.state, j.attempts, j.next_at, j.claimed_at, j.blocked_by, j.qbo_id, j.qbo_name, j.sent_at, j.last_error, j.last_intuit_tid, j.warning, j.note, j.by_staff, j.created_at, j.updated_at,
             (j.created_at at time zone 'America/Toronto')::date as job_date,
             d.doc->>'doc_number' as doc_number, d.doc->>'name' as name, d.doc->>'currency' as currency, (d.doc->>'total')::numeric as total, (d.doc->>'doc_date')::date as doc_date, d.doc->>'doc_status' as doc_status,
             case j.ims_kind when 'invoice' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'credit' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'payment' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-1b
                             when 'credit_alloc' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-2-1
                             when 'opening_alloc' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-3-1
                             when 'refund' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-3-2-1
                             when 'po_payment' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 4-5a 공급처 결제 = 「reference · 공급처 · 통화 금액」
                             when 'cost_sheet' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '')   -- 3-2b 하루 원가 장 = 「COGS-… · Cost day <날> <창고>」
                             when 'po_invoice' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 4-3a 공급처 인보이스 Bill
                             when 'po_credit' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 4-3a 공급처 크레딧 VendorCredit
                             when 'po_charge' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 4-3a 비용 문서 Bill
                             when 'supplier' then coalesce(d.doc->>'name', j.ims_id)   -- 4-3a Vendor
                             when 'product' then coalesce(d.doc->>'doc_number', '') || ' ' || coalesce(d.doc->>'name', '')
                             else coalesce(d.doc->>'name', j.ims_id) end as ims_name,
             (select s.name from public.ims_staff s where s.id = j.by_staff) as by_name,
             p.kind as blocked_kind, p.state as blocked_state, coalesce(pd.doc->>'doc_number', pd.doc->>'name', p.ims_id) as blocked_name,
             t.qbo_id as txn_qbo_id, t.total_amt as txn_total_amt, t.total_tax as txn_total_tax, t.mismatch as txn_mismatch, t.voided_at as txn_voided_at
      from public.qbo_job j
      cross join lateral (select public.qbo_job_doc(j.ims_kind, j.ims_id) as doc) d
      left join public.qbo_job p on p.id = j.blocked_by
      left join lateral (select public.qbo_job_doc(p.ims_kind, p.ims_id) as doc) pd on p.id is not null
      left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund', 'cost_sheet', 'po_invoice', 'po_credit', 'po_charge', 'po_payment')   -- 2e-3-2-1 + refund · 3-2b + cost_sheet(JournalEntry)
                               and t.ims_kind = case j.kind when 'opening_credit' then 'opening_credit' when 'opening_credit_void' then 'opening_credit' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc'
                                                            when 'refund_apply' then 'refund_apply' when 'refund_apply_void' then 'refund_apply' else j.ims_kind end   -- 2e-3-1 이견 3: 한 붙임에 txn 둘 — kind 로 갈라 잇는다 · 2e-3-2-1 이견 8: 환불도(refund · refund_void ↔ txn refund(Purchase) · refund_apply · _void ↔ txn refund_apply(Payment))
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
$function$
;

-- ═══ qbo_job_on_po_doc_status — bill_delete_manual 이 뗀 결제의 void 뒤에서 기다린다(§1-D · 이견 6 안 ㄱ) ═══
CREATE OR REPLACE FUNCTION public.qbo_job_on_po_doc_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_realm text; v_kind text; v_ims_kind text; v_label text; v_number text; v_by uuid; v_j public.qbo_job%rowtype; v_t public.qbo_txn%rowtype; v_del uuid; v_what text;
        v_void uuid;   -- 4-5a: 이 문서에서 떼인 공급처 결제의 열린 void 일감(note 에 「detached from <ims_kind> <id>」 · §0 이견 6 안 ㄱ)
begin
  if new.status is not distinct from old.status then return null; end if;
  select c.realm_id into v_realm from public.qbo_connection c where c.singleton;
  if v_realm is null then return null; end if;                                                                                           -- 연결 없음 — 조용히
  if tg_table_name = 'po_charge' then v_kind := 'bill'; v_ims_kind := 'po_charge'; v_label := 'Bill'; v_number := new.charge_number;
  elsif new.doc_kind = 'credit' then v_kind := 'vendor_credit'; v_ims_kind := 'po_credit'; v_label := 'Vendor credit'; v_number := new.invoice_number;
  else v_kind := 'bill'; v_ims_kind := 'po_invoice'; v_label := 'Bill'; v_number := new.invoice_number; end if;
  v_by := coalesce(case new.status when 'confirmed' then new.confirmed_by when 'cancelled' then new.cancelled_by end, new.updated_by, new.confirmed_by, new.created_by);
  begin
    if new.status = 'confirmed' then                                                                                                     -- 확정 · 복원(확정 상태로) → bill | vendor_credit queued · 열린 bill_delete_manual 이 있으면 그 뒤(blocked)
      if not public.qbo_po_since_ok(new.created_at) then return null; end if;                                                            -- IMS 에서 since 전에 만든 문서(이월)는 아무것도
      select j.id into v_del from public.qbo_job j where j.realm_id = v_realm and j.kind = 'bill_delete_manual' and j.ims_kind = v_ims_kind and j.ims_id = new.id::text and j.state not in ('sent', 'skipped') order by j.created_at limit 1;
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, warning)
      values (v_realm, v_kind, v_ims_kind, new.id::text, case when v_del is null then 'queued' else 'blocked' end, v_del, v_by,
              case when v_del is null then null else format('waiting until the earlier %s is deleted from QuickBooks by hand and that job is skipped (1126)', lower(v_label)) end)
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    elsif old.status = 'confirmed' and new.status in ('cancelled', 'draft') then                                                          -- 취소 · 다시 열기(confirmed → draft)
      v_what := case new.status when 'cancelled' then 'cancelled' else 'reopened' end;
      select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = v_kind and j.ims_kind = v_ims_kind and j.ims_id = new.id::text and j.state not in ('sent', 'skipped') for update;
      if v_j.id is not null and v_j.state in ('queued', 'blocked', 'failed') then                                                        -- 아직 안 나갔다 — 건너뛴다
        update public.qbo_job j set state = 'skipped', claimed_at = null, note = left(v_what || ' before sending', 2000), updated_by = v_by where j.id = v_j.id;
      elsif v_j.id is not null then                                                                                                      -- sending · unknown — 닿았는지 모른다 → 손으로 지우기 일감을 그 뒤에
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note)
        values (v_realm, 'bill_delete_manual', v_ims_kind, new.id::text, 'blocked', v_j.id, v_by, left(format('%s %s was %s in IMS while it was being sent — if it reached QuickBooks, delete it there by hand, then press Skip on this job (1126)', v_label, v_number, v_what), 2000))
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      else
        select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = v_ims_kind and t.ims_id = new.id::text and t.voided_at is null;
        if v_t.id is not null then                                                                                                       -- 보내졌다 → 북키퍼가 QBO 에서 지운다(API delete 없음 · 1126) · IMS 는 그 장을 더는 인정하지 않는다(voided_at)
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note)
          values (v_realm, 'bill_delete_manual', v_ims_kind, new.id::text, 'queued', v_by, left(format('%s %s was %s in IMS — delete QuickBooks %s #%s (%s) by hand, then press Skip on this job (1126)', v_label, v_number, v_what, lower(v_label), v_t.qbo_id, coalesce(v_t.doc_number, '')), 2000))
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
          select j.id into v_void from public.qbo_job j where j.realm_id = v_realm and j.kind = 'bill_payment_void' and j.state not in ('sent', 'skipped') and j.note like '%' || v_ims_kind || ' ' || new.id::text || '%' order by j.created_at limit 1;   -- 4-5a §1-D: 이 문서에서 뗀 결제의 void 가 아직 안 나갔으면 그 뒤에서 기다린다(QBO 에서 Bill 을 지우기 전에 BillPayment 가 void 되어야 한다)
          if v_void is not null then
            update public.qbo_job j set state = 'blocked', blocked_by = v_void, note = left(concat_ws(' · ', j.note, 'waits until the bill payment that was applied to it is voided in QuickBooks'), 2000) where j.realm_id = v_realm and j.kind = 'bill_delete_manual' and j.ims_kind = v_ims_kind and j.ims_id = new.id::text and j.state = 'queued';
          end if;
          update public.qbo_txn t set voided_at = now(), updated_at = now() where t.id = v_t.id;
        end if;                                                                                                                          -- 둘 다 없으면(since 전 · 보낸 적 없음) 아무것도
      end if;
    end if;
  exception when others then                                                                                                             -- 확정 · 취소를 막지 않는다 — 흔적을 failed 일감으로
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff) values (v_realm, v_kind, v_ims_kind, new.id::text, 'failed', left('could not queue: ' || sqlerrm, 2000), v_by)
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$function$
;

-- ═══ po_payment_alloc_guard — 줄의 문서 · 결제 바꾸기 거부(1124) ═══
CREATE OR REPLACE FUNCTION public.po_payment_alloc_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(current_setting('po.payment_door', true), '') = '1' then return new; end if;
  if tg_op = 'INSERT' then
    raise exception 'A document is put on a payment through the payment window (Pay · Add a document), not by inserting a row — nothing was saved';
  end if;
  if new.amount is distinct from old.amount or new.discount_amount is distinct from old.discount_amount then
    -- ADJUST-DISCOUNT-BUTTON: 단추가 생기면 「delete this payment and enter it again」 → 「use Adjust discount」
    raise exception 'The amount (% → %) and discount (% → %) on this line are not edited here — change the amount in the On this payment column; to change the discount, delete this payment and enter it again — nothing was saved',
      old.amount, new.amount, old.discount_amount, new.discount_amount;
  end if;
  if new.po_payment_id is distinct from old.po_payment_id or new.po_invoice_id is distinct from old.po_invoice_id or new.po_charge_id is distinct from old.po_charge_id then   -- 4-5a 판정 1124: 줄의 문서 · 결제는 바꾸지 않는다(떼고 다시 붙인다 — po_payment_target_check 를 건너뛰지 못하게)
    raise exception 'The document on this payment line is not changed here — remove the line and add the document again (one payment, one supplier · 1124) — nothing was saved';
  end if;
  return new;
end;
$function$
;

-- ═══ po_payment_create — p_exchange_rate(맨 뒤 · 기본 null · 경고 exchange_rate_missing) · 1124 거부 · drop → create → grant(같은 이름 하나) ═══
drop function public.po_payment_create(uuid, date, numeric, uuid, numeric, uuid, text, text, jsonb, boolean);
CREATE OR REPLACE FUNCTION public.po_payment_create(p_supplier_id uuid, p_paid_on date, p_amount numeric, p_currency_id uuid, p_discount_taken numeric DEFAULT 0, p_account_id uuid DEFAULT NULL::uuid, p_reference text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_targets jsonb DEFAULT NULL::jsonb, p_commit boolean DEFAULT false, p_exchange_rate numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff      uuid;
  v_sup_id     uuid;
  v_sup_name   text;
  v_cur_code   text;
  v_acc_code   text;  v_acc_name text;
  v_pay_id     uuid;
  v_allocs     jsonb := '[]'::jsonb;
  v_sum        numeric := 0;
  v_gap        numeric;
  v_disc       numeric;
  v_warn       text[] := '{}';
  v_sups       uuid[] := '{}';
  v_seen       text[] := '{}';
  v_key        text;
  v_kind       text;  v_tid uuid;  v_amt numeric;  v_note text;
  t            record;
  r            jsonb;
  v_prev       text;                                           -- po-disc-4a1: 문지기 플래그 전 값
  v_eds        record;                                         -- po-disc-4a2: 이 문서의 조기 결제 할인(결제일 기준 · po_invoice_early_discount)
  v_dsc        numeric;  v_dsum numeric := 0;  v_dsrc text;    -- po-disc-4a2: 원소의 할인 · Σ · 출처(suggested | given | legacy)
  v_legacy     boolean;                                        -- po-disc-4a2(이견 ⓑ): 원소에 discount 열쇠가 하나도 없다 = 옛 모양(지금 화면) — p_discount_taken 이 사람의 선언
  v_pb         text;  v_pc numeric;  v_pt numeric;  v_po numeric;   -- po-disc-4a2: 할인의 세 몫(po_invoice_discount_parts)
  v_aid        uuid;  v_cost jsonb;  v_costs jsonb := '[]'::jsonb;  -- po-disc-4a2: 저장 순간의 원가 사건
  v_cb         text;                                           -- po-disc-4b: 비용 청구서 원소의 discount_basis(pre_tax | with_tax · 없으면 pre_tax)
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  if p_amount is null then raise exception 'Amount is required — nothing was saved'; end if;
  if p_amount <= 0 then raise exception 'Amount must be above 0 (got %) — nothing was saved', p_amount; end if;
  if p_currency_id is null then raise exception 'Currency is required — nothing was saved'; end if;
  select c.code into v_cur_code from public.ref_currency c where c.id = p_currency_id;
  if v_cur_code is null then raise exception 'Currency % not found — nothing was saved', p_currency_id; end if;
  if p_exchange_rate is not null and p_exchange_rate <= 0 then raise exception 'Exchange rate must be above 0 (got %) — nothing was saved', p_exchange_rate; end if;   -- 4-5a §1-E
  if v_cur_code <> coalesce(nullif(btrim((select c.value from public.inv_config c where c.key = 'base_currency')), ''), 'CAD') and p_exchange_rate is null then v_warn := array_append(v_warn, 'exchange_rate_missing'); end if;   -- 4-5a 판정 1123: 외화 결제의 환율은 QuickBooks 로 보낼 때 필수 — 저장은 받고 경고 · 보내기 몸이 막는다(화면 칸은 4-5c)
  v_disc := coalesce(p_discount_taken, 0);
  if v_disc < 0 then raise exception 'Discount taken cannot be negative (got %) — nothing was saved', v_disc; end if;
  v_sup_id := p_supplier_id;
  if v_sup_id is not null then
    select s.name into v_sup_name from public.supplier s where s.id = v_sup_id;
    if v_sup_name is null then raise exception 'Supplier % not found — nothing was saved', v_sup_id; end if;
  end if;
  if p_account_id is not null then
    select a.code, a.name into v_acc_code, v_acc_name from public.ref_account a where a.id = p_account_id;
    if v_acc_code is null then raise exception 'Account % not found — nothing was saved', p_account_id; end if;
  else
    v_warn := array_append(v_warn, 'account_missing');
  end if;
  if p_targets is not null and jsonb_typeof(p_targets) <> 'array' then
    raise exception 'p_targets must be a JSON array [{kind, id, amount, note}] — nothing was saved';
  end if;

  -- ── po-disc-4a2(이견 ⓑ) · 모양 가르기 — 옛 모양: 원소에 discount 열쇠 없음 → p_discount_taken 이 선언(대상 하나에만) · 새 모양: 원소마다 discount(null = 조건으로 제안) ──
  v_legacy := not exists (select 1 from jsonb_array_elements(coalesce(p_targets, '[]'::jsonb)) e where e ? 'discount');
  if v_legacy and v_disc > 0 and jsonb_array_length(coalesce(p_targets, '[]'::jsonb)) > 1 then
    raise exception 'Say which document the discount of % belongs to — a payment that settles % documents cannot carry one discount for all of them; give the discount per document, or pay the discounted document on its own payment — nothing was saved', v_disc, jsonb_array_length(coalesce(p_targets, '[]'::jsonb));
  end if;

  -- ── 대상 문서 검사(한 곳 · po_payment_target_check) — 미리 보기도 같은 판정 ──
  for r in select * from jsonb_array_elements(coalesce(p_targets, '[]'::jsonb)) loop
    v_kind := r->>'kind';
    v_tid  := nullif(r->>'id', '')::uuid;
    v_amt  := nullif(r->>'amount', '')::numeric;
    v_note := r->>'note';
    if v_tid is null then raise exception 'p_targets[] needs an id on every element — nothing was saved'; end if;
    v_key := coalesce(v_kind, '?') || ':' || v_tid::text;
    if v_key = any(v_seen) then raise exception 'Document % appears twice in p_targets — nothing was saved', v_tid; end if;
    v_seen := array_append(v_seen, v_key);
    if v_amt is not null and v_amt <= 0 then
      raise exception 'p_targets[] amount must be above 0 or omitted (got % for %) — nothing was saved', v_amt, v_tid;
    end if;
    select * into t from public.po_payment_target_check(v_kind, v_tid, v_amt, p_currency_id, null);
    if v_amt is null then v_amt := t.doc_unpaid; end if;                          -- 미지급 전액 제안
    if v_amt <= 0 then
      raise exception '% % has nothing unpaid (%) — nothing to allocate — nothing was saved', case v_kind when 'invoice' then 'Invoice' else 'Charge' end, t.target_number, t.doc_unpaid;
    end if;
    -- ── po-disc-4a2 · 이 문서의 할인(판정 391) — 비용 청구서는 ④-b(원소 discount 거부 · 옛 모양은 충당에만 + 경고) · 인보이스는 제안 · 경고 셋 · 세 몫 ──
    v_dsc := nullif(r->>'discount', '')::numeric;  v_dsrc := null;  v_pb := null;  v_pc := null;  v_pt := null;  v_po := null;
    if v_dsc is not null and v_dsc < 0 then raise exception 'p_targets[] discount cannot be negative (got % for %) — nothing was saved', v_dsc, t.target_number; end if;
    if v_kind = 'charge' then                                                                                -- po-disc-4b(판정 393): 비용 청구서 할인 — 원소 discount(+ discount_basis) · 옛 모양은 p_discount_taken · 조건 칸이 없어 제안 없음 · 사건은 저장 때(landed 없으면 보류)
      v_cb := nullif(r->>'discount_basis', '');
      if v_cb is not null and v_cb not in ('pre_tax', 'with_tax') then raise exception 'p_targets[] discount_basis must be pre_tax or with_tax (got % for %) — nothing was saved', v_cb, t.target_number; end if;
      if v_legacy then
        v_dsc := case when v_disc > 0 then v_disc else 0 end;
        if v_dsc > 0 then v_dsrc := 'legacy'; end if;
      elsif v_dsc is null then
        v_dsc := 0;
      else
        v_dsrc := 'given';
      end if;
      if v_dsc > v_amt then raise exception 'Charge %: discount % is larger than the amount allocated to it (%) — nothing was saved', t.target_number, v_dsc, v_amt; end if;
      if v_dsc > 0 then select basis, cost_part, tax_part, 0 into v_pb, v_pc, v_pt, v_po from public.po_charge_discount_parts(v_tid, v_dsc, v_cb); end if;
    else
      select * into v_eds from public.po_invoice_early_discount(v_tid, coalesce(p_paid_on, public.ims_today()));
      if v_legacy then
        v_dsc := case when v_disc > 0 then v_disc else 0 end;
        if v_dsc > 0 then v_dsrc := 'legacy'; end if;
        if v_dsc = 0 and v_eds.has_terms and v_eds.is_valid and v_eds.discount > 0 then v_warn := array_append(v_warn, 'discount_available:' || t.target_number || ':' || v_eds.discount::text); end if;
      elsif v_dsc is null then
        if v_eds.has_terms and v_eds.is_valid then v_dsc := v_eds.discount; v_dsrc := 'suggested'; v_warn := array_append(v_warn, 'discount_suggested:' || t.target_number);
        elsif v_eds.has_terms then v_dsc := 0; v_warn := array_append(v_warn, 'discount_expired:' || t.target_number);
        else v_dsc := 0; end if;
      else
        v_dsrc := 'given';
      end if;
      if v_dsc > 0 and v_dsrc <> 'suggested' then
        if v_eds.has_terms and not v_eds.is_valid then v_warn := array_append(v_warn, 'discount_after_deadline:' || t.target_number); end if;
        if not v_eds.has_terms then v_warn := array_append(v_warn, 'discount_without_terms:' || t.target_number); end if;
      end if;
      if v_dsc > v_amt then raise exception 'Invoice %: discount % is larger than the amount allocated to it (%) — nothing was saved', t.target_number, v_dsc, v_amt; end if;
      if v_dsc > 0 then select basis, cost_part, tax_part, other_part into v_pb, v_pc, v_pt, v_po from public.po_invoice_discount_parts(v_tid, v_dsc, null); end if;
    end if;
    v_dsum := v_dsum + v_dsc;
    v_sum := v_sum + v_amt;
    if not (t.supplier_id = any(v_sups)) then v_sups := array_append(v_sups, t.supplier_id); end if;
    v_allocs := v_allocs || jsonb_build_object('kind', v_kind, 'id', v_tid, 'number', t.target_number, 'supplier_name', t.supplier_name, 'currency_code', t.currency_code,
                                               'doc_total', t.doc_total, 'doc_paid_before', t.doc_paid, 'doc_unpaid_before', t.doc_unpaid, 'amount', v_amt, 'note', v_note, 'inserted', p_commit,
                                               'discount', v_dsc, 'discount_source', v_dsrc, 'discount_basis', v_pb, 'cost_part', v_pc, 'tax_part', v_pt, 'other_part', v_po);   -- po-disc-4a2 · 이 문서의 할인과 세 몫(판정 395)
  end loop;

  -- ── po-disc-4a2 · 검산의 할인 = Σ원소 할인 · 새 모양인데 p_discount_taken 도 왔으면 둘이 같아야 한다(어느 쪽이 맞는지 모른다 · 조용히 고르지 않는다) ──
  if not v_legacy and v_disc > 0 and round(v_disc - v_dsum, 2) <> 0 then
    raise exception 'Say the discount once — per document (p_targets[].discount, total %) or as p_discount_taken (%), not both with different totals — nothing was saved', v_dsum, v_disc;
  end if;
  v_disc := v_dsum;

  -- 공급처 — 강제하지 않는다(이견 1 · ⓑ) · 둘 이상이거나 p_supplier_id 와 다르면 경고
  if cardinality(v_sups) > 1 then                                                                            -- 4-5a 판정 1124: 결제 하나 = 공급처 하나 — 문서의 공급처가 둘 이상이면 거부(p_supplier_id 가 다른 것은 아래 경고 그대로)
    raise exception 'This payment is applied to documents of % suppliers (%) — one payment, one supplier (1124); make a separate payment per supplier — nothing was saved', cardinality(v_sups), (select string_agg(s.name, ', ' order by s.name) from public.supplier s where s.id = any (v_sups));
  end if;
  if cardinality(v_sups) > 1 or (v_sup_id is not null and cardinality(v_sups) = 1 and v_sups[1] <> v_sup_id) then
    v_warn := array_append(v_warn, 'mixed_supplier');
  end if;
  if v_sup_id is null and cardinality(v_sups) = 1 then
    v_sup_id := v_sups[1];
    select s.name into v_sup_name from public.supplier s where s.id = v_sup_id;
  end if;

  -- ⑤ 검산 — Σ충당 = amount + discount_taken · 거부(양쪽 다 우리가 넣는 숫자)
  v_gap := round(p_amount + v_disc - v_sum, 2);
  if v_gap <> 0 then
    raise exception 'Allocations % do not match amount % + discount % = % (gap %) — fix the amounts or the discount first — nothing was saved',
      v_sum, p_amount, v_disc, p_amount + v_disc, v_gap;
  end if;

  -- ── commit: 머리 한 행 + 충당 줄 ──
  if p_commit then
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
    v_prev := current_setting('po.payment_door', true);  perform set_config('po.payment_door', '1', true);   -- po-disc-4a1: 이 창구의 쓰기만 문지기를 지난다
    insert into public.po_payment (paid_on, amount, currency_id, account_id, reference, discount_taken, paid_by, note, exchange_rate)
    values (coalesce(p_paid_on, public.ims_today()), p_amount, p_currency_id, p_account_id, p_reference, v_disc, v_staff, p_note, p_exchange_rate)
    returning id into v_pay_id;
    for r in select * from jsonb_array_elements(v_allocs) loop
      insert into public.po_payment_alloc (po_payment_id, po_invoice_id, po_charge_id, amount, note, discount_amount)   -- po-disc-4a1 · 충당 할인(정본 · Σ 트리거가 discount_taken 을 맞춘다)
      values (v_pay_id,
              case when r->>'kind' = 'invoice' then (r->>'id')::uuid end,
              case when r->>'kind' = 'charge'  then (r->>'id')::uuid end,
              (r->>'amount')::numeric, r->>'note', coalesce((r->>'discount')::numeric, 0))   -- po-disc-4a2 · 원소의 할인
      returning id into v_aid;
      if coalesce((r->>'discount')::numeric, 0) > 0 then                                                   -- po-disc-4a2(판정 391) · po-disc-4b(393 비용도) · 저장 순간 원가 사건 — 레이어 없으면 pending · 399 거부는 예외 = 결제 전체 안 저장
        v_cost := public.po_payment_alloc_cost_events(v_aid, true, r->>'discount_basis');                   -- po-disc-4b · 비용은 원소의 basis(인보이스는 무시)
        v_costs := v_costs || v_cost;
      end if;
    end loop;
    perform set_config('po.payment_door', coalesce(v_prev, ''), true);                                       -- po-disc-4a1
  end if;

  return jsonb_build_object(
    'committed', p_commit, 'payment_id', v_pay_id, 'paid_on', coalesce(p_paid_on, public.ims_today()),
    'amount', p_amount, 'discount_taken', v_disc, 'currency_id', p_currency_id, 'currency_code', v_cur_code,
    'supplier_id', v_sup_id, 'supplier_name', v_sup_name,
    'exchange_rate', p_exchange_rate,   -- 4-5a
    'account_code', v_acc_code, 'account_name', v_acc_name,
    'alloc_sum', v_sum, 'gap', v_gap, 'allocs', v_allocs, 'cost_events', v_costs, 'legacy_shape', v_legacy, 'warnings', to_jsonb(v_warn));   -- po-disc-4a2 · cost_events[] = 충당마다 사건(저장 때만) · legacy_shape
end;
$function$
;
revoke all on function public.po_payment_create(uuid, date, numeric, uuid, numeric, uuid, text, text, jsonb, boolean, numeric) from public, anon;
grant execute on function public.po_payment_create(uuid, date, numeric, uuid, numeric, uuid, text, text, jsonb, boolean, numeric) to authenticated, service_role;   -- 원본 ACL 그대로(authenticated · service_role)

-- ═══ po_payment_alloc_set — 1124 거부(옛 경고 자리 앞) ═══
CREATE OR REPLACE FUNCTION public.po_payment_alloc_set(p_payment_id uuid, p_kind text, p_target_id uuid, p_amount numeric, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_n    int;                                                   -- ②-b: row_count
  v_pay    public.po_payment%rowtype;
  v_al     public.po_payment_alloc%rowtype;
  t        record;
  v_id     uuid;
  v_before numeric;
  v_sum    numeric;
  v_warn   text[] := '{}';
  v_prev   text;                                                -- po-disc-4a1: 문지기 플래그(po.payment_door) 전 값
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_pay from public.po_payment where id = p_payment_id;
  if not found then raise exception 'Payment % not found — nothing was saved', p_payment_id; end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'p_amount must be above 0 (got %) — to remove the line use po_payment_alloc_delete — nothing was saved', p_amount;
  end if;
  if p_kind not in ('invoice', 'charge') then raise exception 'p_kind must be invoice or charge — nothing was saved'; end if;

  -- 이미 있는 줄인가 — unique (po_payment_id, po_invoice_id) · (po_payment_id, po_charge_id) 가 축(null 은 서로 다르게 취급되어 종류가 다르면 안 겹친다)
  select * into v_al from public.po_payment_alloc a
  where a.po_payment_id = p_payment_id
    and ((p_kind = 'invoice' and a.po_invoice_id = p_target_id) or (p_kind = 'charge' and a.po_charge_id = p_target_id));
  if found then v_id := v_al.id; v_before := v_al.amount; end if;

  -- 만들기와 같은 검사 — 고치는 줄의 지금 금액은 미지급에 되돌려 놓고 본다
  select * into t from public.po_payment_target_check(p_kind, p_target_id, p_amount, v_pay.currency_id, v_id);
  if exists (select 1 from public.po_payment_alloc a                                                      -- 4-5a 판정 1124: 결제 하나 = 공급처 하나 — 다른 공급처의 문서는 거부(옛 경고 mixed_supplier 자리)
             left join public.po_invoice i on i.id = a.po_invoice_id left join public.po_charge c on c.id = a.po_charge_id
             where a.po_payment_id = p_payment_id and a.id is distinct from v_id and coalesce(i.supplier_id, c.supplier_id) <> t.supplier_id) then
    raise exception '% % belongs to another supplier than the documents already on this payment — one payment, one supplier (1124); make a separate payment — nothing was saved', case p_kind when 'invoice' then 'Invoice' else 'Charge' end, t.target_number;
  end if;

  v_prev := current_setting('po.payment_door', true);  perform set_config('po.payment_door', '1', true);   -- po-disc-4a1: 이 창구의 쓰기만 문지기를 지난다
  if v_id is not null then
    update public.po_payment_alloc set amount = p_amount, note = coalesce(p_note, note) where id = v_id;
    get diagnostics v_n = row_count;                            -- ②-b
    if v_n = 0 then raise exception 'Allocation line % on payment % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_id, coalesce(v_pay.reference, p_payment_id::text); end if;
  else
    insert into public.po_payment_alloc (po_payment_id, po_invoice_id, po_charge_id, amount, note)
    values (p_payment_id, case when p_kind = 'invoice' then p_target_id end, case when p_kind = 'charge' then p_target_id end, p_amount, p_note)
    returning id into v_id;
  end if;

  perform set_config('po.payment_door', coalesce(v_prev, ''), true);                                        -- po-disc-4a1
  select coalesce(sum(amount), 0) into v_sum from public.po_payment_alloc where po_payment_id = p_payment_id;
  if exists (select 1 from public.po_payment_alloc a
             left join public.po_invoice i on i.id = a.po_invoice_id left join public.po_charge c on c.id = a.po_charge_id
             where a.po_payment_id = p_payment_id and coalesce(i.supplier_id, c.supplier_id) <> t.supplier_id) then
    v_warn := array_append(v_warn, 'mixed_supplier');
  end if;
  return jsonb_build_object('alloc_id', v_id, 'payment_id', p_payment_id, 'kind', p_kind, 'target_id', p_target_id, 'target_number', t.target_number,
                            'amount_before', v_before, 'amount', p_amount,
                            'alloc_sum', v_sum, 'gap', round(v_pay.amount + v_pay.discount_taken - v_sum, 2), 'warnings', to_jsonb(v_warn));
end;
$function$
;

-- ═══ qbo_entity_upsert — Account 거울 detail 에 AccountType · CurrencyRef(EF PULL_FIELDS 는 4-5b · 지시서 밖 재발행 · 이유는 머리) ═══
CREATE OR REPLACE FUNCTION public.qbo_entity_upsert(p_realm text, p_type text, p_rows jsonb, p_next_start integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_staff uuid := public.qbo_sync_gate(); v_s public.qbo_pull_state%rowtype; v_n int;
begin
  if p_realm is distinct from public.qbo_realm_of() then raise exception 'QuickBooks company % is not the connected company — nothing was changed', p_realm; end if;
  select * into v_s from public.qbo_pull_state s where s.realm_id = p_realm and s.qbo_type = p_type;
  if v_s.realm_id is null or v_s.finished_at is not null then raise exception 'No pull in progress for % — call qbo_pull_begin first', p_type; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'rows must be a JSON array of QuickBooks % rows', p_type; end if;
  if exists (select 1 from jsonb_array_elements(p_rows) r where nullif(btrim(r->>'Id'), '') is null or nullif(btrim(coalesce(r->>'Name', r->>'DisplayName')), '') is null) then
    raise exception 'Every % row needs Id and Name (or DisplayName) — nothing was saved', p_type;
  end if;
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, parent_id, fully_qualified_name, active, sync_token, fetched_at, gone_at, detail)
  select p_realm, p_type, btrim(r->>'Id'), btrim(coalesce(r->>'Name', r->>'DisplayName')), nullif(btrim(r->>'Sku'), ''), nullif(btrim(r->'ParentRef'->>'value'), ''), r->>'FullyQualifiedName',
         coalesce((r->>'Active')::boolean, true), r->>'SyncToken', now(), null, case when p_type = 'TaxCode' and (r ? 'SalesTaxRateList' or r ? 'PurchaseTaxRateList') then coalesce(r->'SalesTaxRateList', '{}'::jsonb) || case when r ? 'PurchaseTaxRateList' then jsonb_build_object('PurchaseTaxRateList', r->'PurchaseTaxRateList') else '{}'::jsonb end when p_type = 'Account' and (r ? 'AccountType' or r ? 'CurrencyRef') then jsonb_strip_nulls(jsonb_build_object('AccountType', r->'AccountType', 'CurrencyRef', r->'CurrencyRef')) end   -- 4-5a 판정 1133: Account 거울 detail 에 AccountType · CurrencyRef(EF PULL_FIELDS 는 4-5b · 몸이 대조한다)
  from jsonb_array_elements(p_rows) r
  on conflict (realm_id, qbo_type, qbo_id) do update set name = excluded.name, sku = excluded.sku, parent_id = excluded.parent_id, fully_qualified_name = excluded.fully_qualified_name,
    active = excluded.active, sync_token = excluded.sync_token, fetched_at = now(), gone_at = null, detail = case when excluded.detail is null then public.qbo_entity.detail else coalesce(public.qbo_entity.detail, '{}'::jsonb) || excluded.detail end;   -- 4-3a: 옛 PurchaseTaxRateList 를 잃지 않는다(겹치는 키는 새 값)
  get diagnostics v_n = row_count;
  update public.qbo_pull_state s set received = s.received + v_n, pages = s.pages + 1, next_start = coalesce(p_next_start, s.next_start), updated_at = now()
    where s.realm_id = p_realm and s.qbo_type = p_type returning * into v_s;
  return jsonb_build_object('qbo_type', p_type, 'received_now', v_n, 'received', v_s.received, 'pages', v_s.pages, 'next_start', v_s.next_start);
end;
$function$
;

-- ═══════════════ ⑤ grant · 주석 · 백필 한 번 ═══════════════
revoke all on function public.qbo_bill_payment_fingerprint(uuid), public.qbo_bill_payment_body(uuid), public.qbo_bill_payment_void_body(uuid), public.qbo_bill_payment_sync(uuid, uuid, text), public.qbo_job_on_po_payment(), public.qbo_bill_payment_backfill()
  from public, anon, authenticated, service_role;   -- 속 함수 여섯 · grant 0(claim · preview · 트리거 · 마이그레이션이 definer 로 부른다) · 재발행 열은 create or replace 라 ACL 그대로 · po_payment_create 는 위에서 다시 줬다

do $$
begin
  execute format('comment on table public.qbo_job is %L', coalesce(obj_description('public.qbo_job'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-4-5a: 공급처 결제 kind bill_payment · bill_payment_void(ims_kind po_payment · ims_id = po_payment.id · 1124 · 1132 · 1133 · 1134) — queued 로 서되 EF SEND_KINDS 밖(4-5b 전에는 안 나간다) · bill_delete_manual 은 뗀 결제의 void 뒤');
  execute format('comment on table public.qbo_txn is %L', coalesce(obj_description('public.qbo_txn'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-4-5a: ims_kind po_payment ↔ BillPayment(doc_number = reference 21 자 · fingerprint = 보낼 때 지문 · voided_at = void 뒤)');
  execute format('comment on column public.po_payment.exchange_rate is %L', '[po §11-h · 4-5a 판정 1123] 외화 결제의 환율(그 돈을 산 날 MTFX) — po_payment_create p_exchange_rate(맨 뒤 · 기본 null · 외화인데 비면 경고 exchange_rate_missing) · 직접 update 열림(문지기가 안 막는다 · 4-5c 화면 칸) · QuickBooks 로 보낼 때 비면 몸이 막는다(1118 꼴) · CAD 결제는 안 싣는다 · CHECK > 0');
end $$;

do $$
declare v jsonb;
begin
  v := public.qbo_bill_payment_backfill();
  raise notice '4-5a backfill: %', v;
end $$;

-- ═══════════════ ⑥ 착지 검사 ═══════════════
do $$
declare v_bad text := '';
begin
  if not exists (select 1 from pg_constraint where conname = 'qbo_job_kind_ck' and pg_get_constraintdef(oid) like '%bill_payment_void%') then v_bad := v_bad || ' qbo_job_kind_ck'; end if;
  if not exists (select 1 from pg_constraint where conname = 'qbo_job_ims_kind_ck' and pg_get_constraintdef(oid) like '%po_payment%') then v_bad := v_bad || ' qbo_job_ims_kind_ck'; end if;
  if not exists (select 1 from pg_constraint where conname = 'qbo_job_pair_ck' and pg_get_constraintdef(oid) like $r$%'bill_payment_void'::text THEN 'po_payment'%$r$) then v_bad := v_bad || ' qbo_job_pair_ck'; end if;
  if not exists (select 1 from pg_constraint where conname = 'qbo_txn_kind_ck' and pg_get_constraintdef(oid) like '%po_payment%') then v_bad := v_bad || ' qbo_txn_kind_ck'; end if;
  if not exists (select 1 from pg_constraint where conname = 'qbo_txn_type_ck' and pg_get_constraintdef(oid) like '%BillPayment%') then v_bad := v_bad || ' qbo_txn_type_ck'; end if;
  if not exists (select 1 from pg_constraint where conname = 'qbo_txn_pair_ck' and pg_get_constraintdef(oid) like $r$%'po_payment'::text THEN 'BillPayment'%$r$) then v_bad := v_bad || ' qbo_txn_pair_ck'; end if;
  if not exists (select 1 from pg_constraint where conname = 'po_payment_exchange_rate_ck') then v_bad := v_bad || ' po_payment_exchange_rate_ck'; end if;
  if (select count(*) from pg_trigger t where t.tgname in ('po_payment_qbo', 'po_payment_alloc_qbo') and t.tgdeferrable and t.tginitdeferred and not t.tgisinternal) <> 2 then v_bad := v_bad || ' triggers'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_payment_create') <> 1 then v_bad := v_bad || ' po_payment_create(count)'; end if;
  if to_regprocedure('public.po_payment_create(uuid, date, numeric, uuid, numeric, uuid, text, text, jsonb, boolean, numeric)') is null then v_bad := v_bad || ' po_payment_create(signature)'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_bill_payment_fingerprint', 'qbo_bill_payment_body', 'qbo_bill_payment_void_body', 'qbo_bill_payment_sync', 'qbo_job_on_po_payment', 'qbo_bill_payment_backfill')) <> 6 then v_bad := v_bad || ' new functions'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_retry', 'qbo_job_doc', 'qbo_job_list', 'qbo_job_on_po_doc_status', 'po_payment_alloc_guard', 'po_payment_alloc_set', 'qbo_entity_upsert') and prosrc like '%4-5a%') <> 10 then v_bad := v_bad || ' reissued bodies'; end if;
  if v_bad <> '' then raise exception '⑥ landing check failed:%', v_bad; end if;
end $$;
