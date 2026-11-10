-- supabase/migrations/20261110034500_qbo_sync_4_7a_discount_credit_due_date.sql — qbo-sync-4-7a: 조기 결제 할인 공급처 결제 DB — 할인 VendorCredit 일감 · 결제 몸에 크레딧 줄 · 원가 장 할인 줄 풀기 · (B) 지급 기한 자동 (2026-11-09 토론토 밤 · 지시서 ~/asung/prompts/qbo-sync-4-7a.md · §0 이견 1 ~ 23 · 판정 1143 ~ 1149 · E-8 sandbox · 정본 qbo-integration §15-n)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied 20261110034500 --yes · supabase db push 금지 · ⚠️ qbo_job · qbo_txn CHECK 교체 + po_invoice 칸 · 트리거(ACCESS EXCLUSIVE) — 토론토 17:00 뒤 또는 08:30 전
-- 설계 요지:
--   · 1143 할인 VendorCredit = 따로 일감: kind vendor_credit(재사용) + ims_kind po_discount · ims_id = po_payment_alloc.id · qbo_txn po_discount ↔ VendorCredit · EF 는 kind 로만 가른다(무변) · claim · preview 몸 CASE 만 ims_kind 로 가른다
--   · 몸 qbo_discount_credit_body: 줄 하나 = 할인 → GINR(_1150040012_ · A/P 와 짝) · TxnDate = 결제일 · 통화 · 환율 = 인보이스(1148) · DocNumber 「D<결제일 yymmdd>-<인보이스 번호>」 21 자 · PrivateNote 「IMS early-payment discount <alloc id>」 · 지문 「<센트>|<통화>」(bill 몸 꼴 — done 대조 · EF 가드 · unknown 풀기 무변) · 자기 인보이스 Bill 뒤(wait_job)
--   · 막기(사람 글): 청구서(po_charge) 할인(이견 1 · 계정 미정) · 세금 몫 > 0(1145) · goods 밖 몫 · 세금 있는 인보이스(이견 2 · 세금 코드 미정) — 결제 몸과 VC 몸 둘 다
--   · 맞추기 qbo_discount_credit_sync(alloc, by, payment): 표 트리거 함수가 결제 sync 뒤에 부른다(지워진 붙임은 OLD.id) · 선 VC 와 같은 할인 = 무변(1146 다시 쓰기) · 바뀜 · 사라짐 = qbo_txn.voided_at + bill_delete_manual(po_discount · 열린 결제 void 뒤 blocked) + 새 할인이면 새 VC 일감(그 뒤 blocked) · 되돌림(손 삭제 일감이 아직 결제 void 뒤 blocked) = 거두고 VC 를 다시 인정 · VC 가 sending · unknown 인 동안 바뀜 = 손 삭제 일감을 그 뒤에 · done 뒤에도 한 번
--   · 결제 몸: 1132 ① 을 풀고 붙임마다 Bill 줄(alloc.amount) + 할인이면 VendorCredit 줄(alloc.discount_amount · 선 VC 의 QBO Id) · TotalAmt = 낸 돈(E-8) · VC 아직이면 wait_job · VC 일감 skipped 면 raise · check_lines 에 txn_type · qbo_txn_id(VC 줄에는 qbo_bill_id 가 없다 → 4-7b 전 EF 는 failed 로 세운다 = 안전문) · 1147 ② 는 unpaid 와 같은 조건(cancelled 만 빼고) · 지문 무변(이견 5)
--   · 1149 원가 장 settlement_discount CADJ → send · 보류 글 지움(지금 보류 열쇠 0 · 할인 붙임 0 — 2026-11-09 실측)
--   · (B) 1144 po_invoice.due_date_manual + BEFORE 트리거 po_invoice_due_auto(인보이스 · draft 만): 기한 = 문서 날짜 + ref_payment_term.net_days · 사람이 셈값과 다르게 넣으면 manual(지킨다) · 비우면 다시 셈 · 기존 장은 값 무변 · 기한이 셈값과 다른 장에 manual 표지만 · po_invoice_confirm 경고 due_date_missing · due_date_differs_from_term(막지 않음)
--   · 새 표 0 · 거래 표 FK 0 · 시퀀스 0 · 자동 재시도 없음 · EF · 화면 · cron 무변
-- 재발행 열(원본 = DB pg_get_functiondef · 2026-11-09 · md5 는 ⓪): qbo_job_claim · qbo_job_preview · qbo_job_done · qbo_job_retry · qbo_job_doc · qbo_job_list · qbo_job_on_po_payment · qbo_bill_payment_body · qbo_cost_expected · po_invoice_confirm
-- ⚠️ 공개 레포 — 손님 · 공급처 상호 없음 · UI 글자는 영어 · jsonb_build_object 안에 「--」 줄 주석을 두지 않는다
-- 검증 supabase/tests/qbo_sync_4_7a_check.sql(운영 메인 begin → rollback · 가짜 재료만) · 적용은 Caleb

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

-- ═══════════════ ⓪ 재발행 원본 가드 — 열의 DB prosrc md5 · 아직 미적용 ═══════════════
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_claim') is distinct from 'fe4080ada051129cebc50138c1e1729b' then v_bad := v_bad || ' qbo_job_claim'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_preview') is distinct from 'dfaab4d381d9af200c6998fcb7b35fa0' then v_bad := v_bad || ' qbo_job_preview'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_done') is distinct from '51aec9faf2ca5e5093c4a2004be6d832' then v_bad := v_bad || ' qbo_job_done'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_retry') is distinct from '86af2b7a054f6964dfba395b2a9c38db' then v_bad := v_bad || ' qbo_job_retry'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_doc') is distinct from 'aa796d51c273bff8d9eb0d1185a40f13' then v_bad := v_bad || ' qbo_job_doc'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_list') is distinct from 'bf3dc70b5fc711e950512222b006a9d9' then v_bad := v_bad || ' qbo_job_list'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_on_po_payment') is distinct from '0385e3a329019bde99fbf6108acd22d3' then v_bad := v_bad || ' qbo_job_on_po_payment'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_bill_payment_body') is distinct from 'ec4ea2cac64930fc02598c03a08e69cf' then v_bad := v_bad || ' qbo_bill_payment_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_cost_expected') is distinct from '6d6d5c4d5a74940281b7270f0ab1c9cd' then v_bad := v_bad || ' qbo_cost_expected'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_invoice_confirm') is distinct from 'daa5c51ab707d51a7b184a1b6e3cb04b' then v_bad := v_bad || ' po_invoice_confirm'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_preview', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_doc', 'qbo_job_list', 'qbo_job_on_po_payment', 'qbo_bill_payment_body', 'qbo_cost_expected', 'po_invoice_confirm')) <> 10 then v_bad := v_bad || ' (duplicate signatures)'; end if;
  if to_regprocedure('public.qbo_discount_credit_body(uuid)') is not null or exists (select 1 from pg_constraint where conname = 'qbo_job_ims_kind_ck' and pg_get_constraintdef(oid) like '%po_discount%')
     or exists (select 1 from pg_attribute where attrelid = 'public.po_invoice'::regclass and attname = 'due_date_manual' and not attisdropped) then v_bad := v_bad || ' (4-7a already applied?)'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current bodies first — nothing was changed', v_bad; end if;
end $$;

-- ═══════════════ ① CHECK — qbo_job ims_kind 16(po_discount) · 짝(vendor_credit ↔ po_credit | po_discount · bill_delete_manual + po_discount) · qbo_txn po_discount ↔ VendorCredit ═══════════════
alter table public.qbo_job
  drop constraint qbo_job_ims_kind_ck,
  add  constraint qbo_job_ims_kind_ck check (ims_kind in ('customer', 'product', 'charge', 'invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund', 'cost_sheet', 'supplier', 'po_invoice', 'po_credit', 'po_charge', 'po_payment', 'po_discount')),
  drop constraint qbo_job_pair_ck,
  add  constraint qbo_job_pair_ck check (ims_kind = case kind when 'customer' then 'customer' when 'invoice' then 'invoice' when 'invoice_void' then 'invoice' when 'credit' then 'credit' when 'credit_void' then 'credit'
                                                                                        when 'payment' then 'payment' when 'payment_void' then 'payment' when 'credit_apply' then 'credit_alloc' when 'credit_apply_void' then 'credit_alloc'
                                                                                        when 'opening_credit' then 'opening_alloc' when 'opening_credit_void' then 'opening_alloc' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc'
                                                                                        when 'refund' then 'refund' when 'refund_void' then 'refund' when 'refund_apply' then 'refund' when 'refund_apply_void' then 'refund'
                                                                                        when 'cost_day' then 'cost_sheet' when 'vendor' then 'supplier'
                                                                                        when 'bill_payment' then 'po_payment' when 'bill_payment_void' then 'po_payment' else ims_kind end
                                                and (kind <> 'item' or ims_kind in ('product', 'charge'))
                                                and (kind <> 'bill' or ims_kind in ('po_invoice', 'po_charge'))
                                                and (kind <> 'vendor_credit' or ims_kind in ('po_credit', 'po_discount'))
                                                and (kind <> 'bill_delete_manual' or ims_kind in ('po_invoice', 'po_credit', 'po_charge', 'po_discount')));
alter table public.qbo_txn
  drop constraint qbo_txn_kind_ck,
  add  constraint qbo_txn_kind_ck check (ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_credit', 'opening_alloc', 'refund', 'refund_apply', 'cost_sheet', 'po_invoice', 'po_credit', 'po_charge', 'po_payment', 'po_discount')),
  drop constraint qbo_txn_pair_ck,
  add  constraint qbo_txn_pair_ck check (qbo_type = case ims_kind when 'invoice' then 'Invoice' when 'credit' then 'CreditMemo' when 'opening_credit' then 'CreditMemo' when 'refund' then 'Purchase' when 'cost_sheet' then 'JournalEntry'
                                                                  when 'po_invoice' then 'Bill' when 'po_charge' then 'Bill' when 'po_credit' then 'VendorCredit' when 'po_discount' then 'VendorCredit' when 'po_payment' then 'BillPayment' else 'Payment' end);

-- ═══════════════ ② 할인 VendorCredit 몸 · 맞추기 ═══════════════
create function public.qbo_discount_credit_body(p_alloc_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_realm text := public.qbo_realm_of(); v_home text := coalesce(nullif(btrim((select c.value from public.inv_config c where c.key = 'base_currency')), ''), 'CAD');
  c_ginr constant text := '_1150040012_';
  c_hand constant text := 'Enter this discount in QuickBooks by hand (a vendor credit, applied on the bill payment), then press Skip on this job';
  v_al public.po_payment_alloc%rowtype; v_p public.po_payment%rowtype; v_i public.po_invoice%rowtype; v_m public.po_invoice_money%rowtype; v_s public.supplier%rowtype;
  v_pt record; v_cur text; v_vendor text; v_ap text; v_ap_cur text; v_ginr text; v_rule uuid; v_tx jsonb; v_raw text; v_doc text; v_note text; v_cents bigint; v_pref text;
  v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_t public.qbo_txn%rowtype; v_bj public.qbo_job%rowtype; v_wait uuid;
begin
  select * into v_al from public.po_payment_alloc x where x.id = p_alloc_id;
  if v_al.id is null then raise exception 'The payment line of this early-payment discount no longer exists in IMS — nothing to send; skip this job — nothing was sent'; end if;
  select * into v_p from public.po_payment p where p.id = v_al.po_payment_id;
  if v_al.po_invoice_id is null then
    raise exception '% (the discount is on a charge, and the QuickBooks account for a discount on a charge bill is not decided yet) — nothing was sent', c_hand;
  end if;
  select * into v_i from public.po_invoice i where i.id = v_al.po_invoice_id;
  select * into v_m from public.po_invoice_money m where m.id = v_al.po_invoice_id;
  if v_al.discount_amount <= 0 then raise exception 'Invoice % has no early-payment discount on this payment any more — nothing to send; skip this job — nothing was sent', v_i.invoice_number; end if;
  if v_i.status <> 'confirmed' then raise exception 'Invoice % is % — only a confirmed invoice takes an early-payment discount in QuickBooks — nothing was sent', v_i.invoice_number, v_i.status; end if;
  if not public.qbo_po_since_ok(v_i.created_at) then
    raise exception '% (invoice % was created in IMS before the QuickBooks start date — its bill did not come from IMS) — nothing was sent', c_hand, v_i.invoice_number;
  end if;
  select c.code into v_cur from public.ref_currency c where c.id = v_i.currency_id;
  if v_cur is null then raise exception 'Invoice % has no currency — nothing was sent', v_i.invoice_number; end if;
  -- 판정 1145 · 이견 2: 세금 몫 · goods 밖 몫 · 세금 있는 인보이스는 사람에게(저장 칸을 믿지 않고 다시 셈한다)
  select pp.tax_part, pp.other_part into v_pt from public.po_invoice_discount_parts(v_i.id, v_al.discount_amount, null) pp;
  if coalesce(v_pt.tax_part, 0) <> 0 or v_al.discount_tax_part <> 0 then
    raise exception '% (1145: the discount of % % on invoice % includes a tax share of % — IMS sends a before-tax discount only) — nothing was sent', c_hand, trim_scale(v_al.discount_amount), v_cur, v_i.invoice_number, trim_scale(greatest(coalesce(v_pt.tax_part, 0), v_al.discount_tax_part));
  end if;
  if coalesce(v_pt.other_part, 0) <> 0 or v_al.discount_other_part <> 0 then
    raise exception '% (the discount of % % on invoice % falls partly on lines that are not goods) — nothing was sent', c_hand, trim_scale(v_al.discount_amount), v_cur, v_i.invoice_number;
  end if;
  if coalesce(v_m.tax_amount, 0) <> 0 then
    raise exception '% (invoice % carries tax, and the tax code of an early-payment discount on a taxed invoice is not decided yet) — nothing was sent', c_hand, v_i.invoice_number;
  end if;
  -- 공급처 · Vendor(없으면 need) · A/P(통화 = 문서 통화) · GINR · 환율 = 인보이스(1148)
  select * into v_s from public.supplier s where s.id = v_i.supplier_id;
  select l.qbo_id into v_vendor from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'supplier' and l.ims_id = v_s.id::text;
  if v_vendor is null then v_needs := v_needs || jsonb_build_object('kind', 'vendor', 'ims_id', v_s.id::text, 'name', v_s.name); end if;
  v_ap := public.qbo_account_ref(v_s.account_payable_code, 'supplier payable account');
  select public.ims_account_currency(ra.id) into v_ap_cur from public.ref_account ra where ra.code = v_s.account_payable_code;
  if v_ap_cur is distinct from v_cur then raise exception 'Invoice % is in % but the supplier payable account % is a % account — fix the supplier (Suppliers → payable account) and retry — nothing was sent', v_i.invoice_number, v_cur, v_s.account_payable_code, coalesce(v_ap_cur, '?'); end if;
  v_ginr := public.qbo_account_ref(c_ginr, 'goods invoiced not received');
  if v_cur <> v_home and (v_i.exchange_rate is null or v_i.exchange_rate <= 0) then raise exception 'Invoice % is in % but has no exchange rate — enter the rate on the invoice and retry (1118 · 1148) — nothing was sent', v_i.invoice_number, v_cur; end if;
  -- 세금 코드 = 인보이스 규칙(세금 0 인 인보이스만 여기 온다) · 머리 규칙이 없으면 첫 줄의 규칙
  v_rule := coalesce(v_i.tax_rule_id, (select l.tax_rule_id from public.po_invoice_line l where l.po_invoice_id = v_i.id and l.tax_rule_id is not null order by l.line_no limit 1));
  if v_rule is null then raise exception 'Invoice % has no tax rule — set the tax rule on the invoice and retry — nothing was sent', v_i.invoice_number; end if;
  v_tx := public.qbo_purchase_tax(v_rule);
  if v_tx->>'tax_code' is null then raise exception 'The tax rule of invoice % has no QuickBooks tax code — match it under Settings → QuickBooks matching, then retry — nothing was sent', v_i.invoice_number; end if;
  -- 자기 인보이스의 Bill 이 먼저(이견 14) — Bill 이 안 가면 VC 만 고아로 남는다
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'po_invoice' and t.ims_id = v_i.id::text and t.voided_at is null;
  if v_t.id is null then
    select * into v_bj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'bill' and j.ims_kind = 'po_invoice' and j.ims_id = v_i.id::text order by j.created_at desc, j.id desc limit 1;
    if v_bj.id is null then raise exception 'Invoice % has no QuickBooks bill job — confirm and send the bill first — nothing was sent', v_i.invoice_number; end if;
    if v_bj.state = 'skipped' then raise exception 'The bill job of invoice % was skipped — skip this discount credit too, or retry the bill first — nothing was sent', v_i.invoice_number; end if;
    if v_bj.state = 'sent' then raise exception 'The bill job of invoice % is sent but no QuickBooks bill is on file — check qbo_txn by hand — nothing was sent', v_i.invoice_number; end if;
    v_wait := v_bj.id;
  end if;
  -- DocNumber 「D<결제일 yymmdd>-<인보이스 번호>」(21 자 · 1130 꼴) · PrivateNote 표지
  v_raw := 'D' || to_char(v_p.paid_on, 'YYMMDD') || '-' || btrim(v_i.invoice_number);
  v_doc := public.qbo_doc_number_21(v_raw);
  if length(v_raw) > 21 then v_warn := array_append(v_warn, format('number "%s" cut to 21 characters for QuickBooks — the full number is in the private note (1130)', v_raw)); end if;
  v_pref := nullif(btrim(coalesce(v_p.reference, '')), '');
  v_note := 'IMS early-payment discount ' || v_al.id::text || ' · invoice ' || v_i.invoice_number || ' · paid ' || v_p.paid_on::text || coalesce(' · payment ' || v_pref, '') || case when length(v_raw) > 21 then ' · full number: ' || v_raw else '' end;
  v_cents := round(v_al.discount_amount * 100)::bigint;
  return jsonb_build_object('kind', 'vendor_credit', 'ims_kind', 'po_discount', 'ims_id', v_al.id::text, 'name', v_raw, 'doc_number', v_doc, 'supplier_id', v_s.id,
    'body', jsonb_strip_nulls(jsonb_build_object(
      'DocNumber', v_doc, 'TxnDate', to_char(v_p.paid_on, 'YYYY-MM-DD'),
      'VendorRef', case when v_vendor is not null then jsonb_build_object('value', v_vendor) end,
      'APAccountRef', jsonb_build_object('value', v_ap),
      'CurrencyRef', jsonb_build_object('value', v_cur), 'ExchangeRate', case when v_cur <> v_home then trim_scale(v_i.exchange_rate) end,
      'PrivateNote', left(v_note, 4000), 'GlobalTaxCalculation', 'TaxExcluded',
      'Line', jsonb_build_array(jsonb_build_object('DetailType', 'AccountBasedExpenseLineDetail', 'LineNum', 1, 'Amount', v_al.discount_amount,
                'Description', left('Early-payment discount · invoice ' || v_i.invoice_number || ' · paid ' || v_p.paid_on::text, 4000),
                'AccountBasedExpenseLineDetail', jsonb_build_object('AccountRef', jsonb_build_object('value', v_ginr), 'TaxCodeRef', jsonb_build_object('value', v_tx->>'tax_code')))),
      'TxnTaxDetail', jsonb_build_object('TotalTax', 0))),
    'needs', v_needs, 'wait_job', v_wait, 'wait_invoice', v_i.invoice_number,
    'wait_reason', case when v_wait is not null then format('waiting for bill %s to reach QuickBooks first — send it too', v_i.invoice_number) end,
    'warnings', to_jsonb(v_warn), 'line_count', 1,
    'totals', jsonb_build_object('taxable', v_al.discount_amount, 'tax', 0, 'total', v_al.discount_amount, 'currency', v_cur, 'exchange_rate', case when v_cur <> v_home then v_i.exchange_rate end),
    'fingerprint', v_cents::text || '|' || v_cur,
    'lookup', jsonb_build_object('entity', 'VendorCredit', 'doc_number', v_doc, 'vendor_ref', v_vendor, 'total_cents', v_cents, 'currency', v_cur));
end;
$$;
comment on function public.qbo_discount_credit_body(uuid) is '[qbo-sync-4-7a · 판정 1143 · 1145 · 1148 · grant 0] 조기 결제 할인 → QuickBooks VendorCredit 몸(kind vendor_credit · ims_kind po_discount · ims_id = po_payment_alloc.id) — 줄 하나 = 할인 → GINR · TxnDate = 결제일 · 통화 · 환율 = 인보이스 · DocNumber 「D<yymmdd>-<인보이스 번호>」 21 자 · PrivateNote 「IMS early-payment discount <alloc id>」 · 지문 「<센트>|<통화>」(bill 몸 꼴) · 자기 인보이스 Bill 뒤(wait_job) · 막기 = raise(사람 글): 청구서 할인 · 세금 몫(1145) · goods 밖 몫 · 세금 있는 인보이스 · since 전 인보이스';

create function public.qbo_discount_credit_sync(p_alloc_id uuid, p_by uuid, p_payment_id uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare
  v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton);
  v_al public.po_payment_alloc%rowtype; v_pid uuid; v_want text; v_inv text; v_lbl text;
  v_t public.qbo_txn%rowtype; v_cj public.qbo_job%rowtype; v_dj public.qbo_job%rowtype; v_par public.qbo_job%rowtype; v_void uuid; v_did uuid; v_act text := 'none';
begin
  if v_realm is null then return jsonb_build_object('action', 'no_connection'); end if;
  select * into v_al from public.po_payment_alloc x where x.id = p_alloc_id;
  v_pid := coalesce(v_al.po_payment_id, p_payment_id);
  -- 원하는 모습 = 「<할인 센트>|<통화>」(VC 몸의 지문과 같은 꼴) · 붙임이 없거나 · 청구서 붙임이거나 · 할인 0 이거나 · since 전 인보이스면 null(= VC 없음)
  if v_al.id is not null and v_al.po_invoice_id is not null and v_al.discount_amount > 0 then
    select round(v_al.discount_amount * 100)::bigint::text || '|' || c.code, i.invoice_number into v_want, v_inv
      from public.po_invoice i join public.ref_currency c on c.id = i.currency_id where i.id = v_al.po_invoice_id and public.qbo_po_since_ok(i.created_at);
  end if;
  select * into v_t  from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'po_discount' and t.ims_id = p_alloc_id::text;
  select * into v_cj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'vendor_credit'      and j.ims_kind = 'po_discount' and j.ims_id = p_alloc_id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_dj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'bill_delete_manual' and j.ims_kind = 'po_discount' and j.ims_id = p_alloc_id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  if v_t.id is null and v_cj.id is null and v_dj.id is null and v_want is null then return jsonb_build_object('action', 'none'); end if;
  v_lbl := coalesce(v_inv, (select i.invoice_number from public.po_invoice i where i.id = v_al.po_invoice_id), v_t.doc_number, p_alloc_id::text);

  if v_t.id is not null and v_t.voided_at is null then                                                                                 -- QBO 에 VC 가 서 있다
    if v_want is not distinct from v_t.fingerprint then return jsonb_build_object('action', 'same', 'fingerprint', v_want); end if;    -- 같은 붙임 · 같은 할인 = 그 VC 를 다음 BillPayment 에 다시 붙인다(1146)
    if v_pid is not null then                                                                                                          -- 그 VC 를 쓴 결제의 void 가 아직 안 나갔으면 그 뒤에서 기다린다(QBO 에서 VC 를 지우기 전에 BillPayment 가 void 되어야 한다)
      select j.id into v_void from public.qbo_job j where j.realm_id = v_realm and j.kind = 'bill_payment_void' and j.ims_kind = 'po_payment' and j.ims_id = v_pid::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
    end if;
    update public.qbo_txn t set voided_at = now(), updated_at = now() where t.id = v_t.id;                                             -- IMS 는 그 장을 더는 인정하지 않는다(po_doc_status 꼴 · API delete 없음 1126)
    insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note)
    values (v_realm, 'bill_delete_manual', 'po_discount', p_alloc_id::text, case when v_void is null then 'queued' else 'blocked' end, v_void, p_by,
            left(format('Early-payment discount on invoice %s was %s in IMS — delete QuickBooks vendor credit #%s (%s) by hand, then press Skip on this job (1146 · 1126)%s', v_lbl, case when v_want is null then 'removed' else 'changed' end, v_t.qbo_id, coalesce(v_t.doc_number, ''),
                        case when v_void is not null then ' · waits until the bill payment that used it is voided in QuickBooks' else '' end), 2000))
    on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_did;
    if v_did is null then                                                                                                              -- 이미 열린 손 삭제 일감(VC 가 나가는 동안 바뀐 길) — 이제 아는 QBO 번호를 적는다
      v_did := v_dj.id;
      update public.qbo_job j set note = left(concat_ws(' · ', j.note, format('it reached QuickBooks as vendor credit #%s (%s)', v_t.qbo_id, coalesce(v_t.doc_number, ''))), 2000) where j.id = v_did;
    end if;
    if v_want is not null and v_did is not null then
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, warning)
      values (v_realm, 'vendor_credit', 'po_discount', p_alloc_id::text, 'blocked', v_did, p_by, 'waiting until the earlier vendor credit is deleted from QuickBooks by hand and that job is skipped (1146 · 1126)')
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      return jsonb_build_object('action', 'delete_and_resend', 'fingerprint', v_want, 'delete_job', v_did);
    end if;
    return jsonb_build_object('action', 'delete', 'fingerprint', v_want, 'delete_job', v_did);
  end if;

  -- VC 가 없거나 IMS 가 이미 버린 장(voided_at)
  if v_t.id is not null and v_want is not distinct from v_t.fingerprint and v_dj.id is not null and v_dj.state = 'blocked' then      -- 되돌림(이견 11): 할인이 버린 VC 와 같아졌고 손 삭제 일감이 아직 결제 void 뒤에서 기다린다(사람이 지웠을 수 없다) → 거두고 그 VC 를 다시 인정
    select * into v_par from public.qbo_job j where j.id = v_dj.blocked_by;
    if v_par.kind = 'bill_payment_void' then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'discount restored to what QuickBooks has — the vendor credit is kept, nothing to delete'), 2000), updated_by = p_by where j.id = v_dj.id;
      update public.qbo_txn t set voided_at = null, updated_at = now() where t.id = v_t.id;
      if v_cj.id is not null and v_cj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'discount restored to what QuickBooks has — nothing to send again'), 2000), updated_by = p_by where j.id = v_cj.id;
      end if;
      return jsonb_build_object('action', 'restored', 'fingerprint', v_want);
    end if;
  end if;
  if v_want is null then                                                                                                               -- 할인이 사라졌다
    if v_cj.id is not null and v_cj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'early-payment discount removed before sending'), 2000), updated_by = p_by where j.id = v_cj.id;
      v_act := 'skipped';
    elsif v_cj.id is not null and v_dj.id is null then                                                                                 -- sending · unknown — 닿았는지 모른다 → 손 삭제 일감을 그 뒤에(이견 12)
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note)
      values (v_realm, 'bill_delete_manual', 'po_discount', p_alloc_id::text, 'blocked', v_cj.id, p_by, left(format('Early-payment discount on invoice %s was removed in IMS while its vendor credit was being sent — if it reached QuickBooks, delete it there by hand, then press Skip on this job (1146 · 1126)', v_lbl), 2000))
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      v_act := 'delete_after_send';
    end if;
    return jsonb_build_object('action', v_act, 'fingerprint', null);
  end if;
  if v_cj.id is null then                                                                                                              -- 새 VC 일감 — 열린 손 삭제 일감이 있으면 그 뒤(claim ② 가 skipped 때 푼다)
    insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, warning)
    values (v_realm, 'vendor_credit', 'po_discount', p_alloc_id::text, case when v_dj.id is null then 'queued' else 'blocked' end, v_dj.id, p_by,
            case when v_dj.id is null then null else 'waiting until the earlier vendor credit is deleted from QuickBooks by hand and that job is skipped (1146 · 1126)' end)
    on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    v_act := 'queued';
  elsif v_cj.state in ('sending', 'unknown') and v_cj.fingerprint is distinct from v_want and v_dj.id is null then                    -- 나가는 동안 할인이 바뀌었다 → 손 삭제 일감을 그 뒤에 · 새 VC 는 done 뒤 맞추기가 쌓는다
    insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note)
    values (v_realm, 'bill_delete_manual', 'po_discount', p_alloc_id::text, 'blocked', v_cj.id, p_by, left(format('Early-payment discount on invoice %s was changed in IMS while its vendor credit was being sent — if it reached QuickBooks, delete it there by hand, then press Skip on this job (1146 · 1126)', v_lbl), 2000))
    on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    v_act := 'delete_after_send';
  end if;                                                                                                                              -- queued · blocked · failed 는 그대로(claim 이 그때의 할인으로 몸을 다시 만든다)
  return jsonb_build_object('action', v_act, 'fingerprint', v_want);
end;
$$;
comment on function public.qbo_discount_credit_sync(uuid, uuid, uuid) is '[qbo-sync-4-7a · 판정 1143 · 1146 · §0 이견 8 · 11 · 12 · grant 0] 조기 결제 할인 ↔ QuickBooks VendorCredit 맞추기 — 표 트리거 함수(qbo_job_on_po_payment)가 결제 sync 뒤에 붙임마다 · done 이 보낸 뒤 · 결제 retry 가 부른다 · 멱등 · 선 VC 와 같은 할인 = 무변(다음 BillPayment 에 다시 붙인다) · 바뀜 · 사라짐 = qbo_txn.voided_at + bill_delete_manual(po_discount · 열린 결제 void 뒤 blocked) + 새 할인이면 새 VC 일감(그 뒤 blocked) · 되돌림 = 결제 void 뒤에서 기다리던 손 삭제 일감을 거두고 VC 를 다시 인정 · sending · unknown 중 바뀜 = 손 삭제 일감을 그 뒤에';

-- ═══════════════ ③ (B) 지급 기한 자동 — 판정 1144 ═══════════════
alter table public.po_invoice add column due_date_manual boolean not null default false;
comment on column public.po_invoice.due_date_manual is '[qbo-sync-4-7a · 판정 1144] 지급 기한을 사람이 결제조건(문서 날짜 + ref_payment_term.net_days)과 다르게 넣었다 — true 면 트리거 po_invoice_due_auto 가 기한을 다시 셈하지 않는다 · 기한을 비우거나 셈값과 같게 넣으면 false · 트리거가 스스로 맞춘다(화면이 보낼 필요 없음)';
set local session_replication_role = replica;
update public.po_invoice i set due_date_manual = true
  from public.ref_payment_term t
 where t.id = i.payment_term_id and i.doc_kind = 'invoice' and i.due_date is not null and t.net_days is not null and i.due_date <> i.invoice_date + t.net_days;
update public.po_invoice i set due_date_manual = true
 where i.doc_kind = 'invoice' and i.due_date is not null and not exists (select 1 from public.ref_payment_term t where t.id = i.payment_term_id and t.net_days is not null);
set local session_replication_role = origin;

create function public.po_invoice_due_auto() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_net int; v_calc date;
begin
  if new.doc_kind <> 'invoice' or new.status <> 'draft' then return new; end if;                        -- 크레딧 · 확정 · 취소된 장은 건드리지 않는다
  select t.net_days into v_net from public.ref_payment_term t where t.id = new.payment_term_id;
  if v_net is not null and new.invoice_date is not null then v_calc := new.invoice_date + v_net; end if;
  if tg_op = 'INSERT' then
    if new.due_date is null then new.due_date := v_calc; new.due_date_manual := false;
    else new.due_date_manual := new.due_date is distinct from v_calc; end if;
  elsif new.due_date is distinct from old.due_date then                                                 -- 사람이 기한을 고쳤다 — 비웠으면 다시 셈 · 셈값과 다르면 사람 값
    if new.due_date is null then new.due_date := v_calc; new.due_date_manual := false;
    else new.due_date_manual := new.due_date is distinct from v_calc; end if;
  elsif new.due_date is null or not new.due_date_manual then                                            -- 기한은 그대로 — 비었거나 사람 값이 아니면 문서 날짜 · 결제조건에 맞춘다
    if v_calc is not null then new.due_date := v_calc; new.due_date_manual := false; end if;
  end if;
  return new;
end;
$$;
comment on function public.po_invoice_due_auto() is '[qbo-sync-4-7a · 판정 1144] po_invoice BEFORE INSERT · UPDATE — 인보이스 · draft 만: 지급 기한 = 문서 날짜 + ref_payment_term.net_days(Due on receipt · C.O.D = 0 · 분할 조건은 net_days 그대로 · 결제조건이 없으면 그대로 둔다) · 사람이 셈값과 다른 기한을 넣으면 due_date_manual true(지킨다) · 기한을 비우면 다시 셈 · 화면이 직접 PATCH 하므로 창구가 아니라 표에 건다';
create trigger po_invoice_due_auto before insert or update on public.po_invoice for each row execute function public.po_invoice_due_auto();

-- ═══════════════ ④ 재발행 열 — DB pg_get_functiondef 그대로 + 끼운 줄(머리 · 서명 · definer · search_path · ACL 그대로 · create or replace) ═══════════════
-- ═══ qbo_job_claim ═══
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
                           when 'vendor' then public.qbo_vendor_body(v_j.ims_id::uuid) when 'bill' then case v_j.ims_kind when 'po_charge' then public.qbo_charge_bill_body(v_j.ims_id::uuid) else public.qbo_bill_body(v_j.ims_id::uuid, 'bill') end when 'vendor_credit' then case v_j.ims_kind when 'po_discount' then public.qbo_discount_credit_body(v_j.ims_id::uuid) else public.qbo_vendor_credit_body(v_j.ims_id::uuid) end end;   -- 4-7a 할인 VC(ims_kind po_discount · ims_id = po_payment_alloc.id · 1143)     -- 4-3a vendor(1128) · bill(po_invoice 1115 ~ 1118 · po_charge 1129) · vendor_credit(1121)   -- 3-2b cost_day(하루 원가 장 · 몸은 장 id 로)   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void   -- 2c1 credit · credit_void
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
                           when 'vendor' then public.qbo_vendor_body(v_j.ims_id::uuid) when 'bill' then case v_j.ims_kind when 'po_charge' then public.qbo_charge_bill_body(v_j.ims_id::uuid) else public.qbo_bill_body(v_j.ims_id::uuid, 'bill') end when 'vendor_credit' then case v_j.ims_kind when 'po_discount' then public.qbo_discount_credit_body(v_j.ims_id::uuid) else public.qbo_vendor_credit_body(v_j.ims_id::uuid) end end;   -- 4-7a 할인 VC(ims_kind po_discount · ims_id = po_payment_alloc.id · 1143)     -- 4-3a vendor(1128) · bill(po_invoice 1115 ~ 1118 · po_charge 1129) · vendor_credit(1121)   -- 3-2b cost_day(하루 원가 장 · 몸은 장 id 로)   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
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

-- ═══ qbo_job_preview ═══
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
                           when 'vendor' then public.qbo_vendor_body(v_j.ims_id::uuid) when 'bill' then case v_j.ims_kind when 'po_charge' then public.qbo_charge_bill_body(v_j.ims_id::uuid) else public.qbo_bill_body(v_j.ims_id::uuid, 'bill') end when 'vendor_credit' then case v_j.ims_kind when 'po_discount' then public.qbo_discount_credit_body(v_j.ims_id::uuid) else public.qbo_vendor_credit_body(v_j.ims_id::uuid) end end;   -- 4-7a 할인 VC(ims_kind po_discount · ims_id = po_payment_alloc.id · 1143)     -- 4-3a vendor(1128) · bill(po_invoice 1115 ~ 1118 · po_charge 1129) · vendor_credit(1121)   -- 3-2b cost_day(하루 원가 장 · 몸은 장 id 로)   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
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

-- ═══ qbo_job_done ═══
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
  if v_j.kind = 'vendor_credit' and v_j.ims_kind = 'po_discount' and v_link_err is null then               -- 4-7a: 보낸 뒤 맞추기 — 보내는 동안 할인이 바뀌었거나 사라졌으면 손으로 지우기 일감 · 새 VC 일감을 쌓는다(1146)
    begin v_sync := public.qbo_discount_credit_sync(v_j.ims_id::uuid, v_j.by_staff, null);
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

-- ═══ qbo_job_retry ═══
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
  if v_j.kind = 'bill_payment' then                                                                                                    -- 4-7a: 결제 retry 가 그 결제의 할인 VC 일감을 맞춘다(없으면 세운다 · 몸이 「press Retry」 로 안내하는 출구)
    perform public.qbo_discount_credit_sync(a.id, v_staff, a.po_payment_id) from public.po_payment_alloc a where a.po_payment_id = v_j.ims_id::uuid and a.discount_amount > 0;
  end if;
  if v_j.kind = 'vendor_credit' and v_j.ims_kind = 'po_discount' then                                                                  -- 4-7a: 할인 VC retry = 붙임에 할인이 있고 QBO 에 안 섰을 때만
    if not exists (select 1 from public.po_payment_alloc a where a.id::text = v_j.ims_id and a.po_invoice_id is not null and a.discount_amount > 0) then
      raise exception 'The early-payment discount of this job was removed in IMS — nothing to send — nothing was saved';
    end if;
    if exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = 'po_discount' and t.ims_id = v_j.ims_id and t.voided_at is null) then
      raise exception 'The vendor credit for this early-payment discount is already in QuickBooks — nothing to send — nothing was saved';
    end if;
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
    if v_j.kind in ('bill', 'vendor_credit') and v_j.ims_kind <> 'po_discount' and coalesce(v_doc->>'doc_status', '') <> 'confirmed' then                                   -- 4-3a: 공급처 문서는 confirmed 일 때만 다시
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

-- ═══ qbo_job_doc ═══
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
    when 'po_discount' then (select jsonb_build_object('doc_number', 'Discount · ' || i.invoice_number, 'name', (select s.name from public.supplier s where s.id = i.supplier_id), 'customer_id', null, 'currency', (select r.code from public.ref_currency r where r.id = i.currency_id), 'total', a.discount_amount, 'doc_date', p.paid_on, 'doc_status', case when a.discount_amount > 0 then 'active' else 'removed' end)
                               from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id join public.po_invoice i on i.id = a.po_invoice_id where a.id::text = p_ims_id)   -- 4-7a: 조기 결제 할인 VC = 「Discount · 인보이스」 · 공급처 · 통화 · 할인 · 결제일 · 붙임이 지워지면 null
    when 'po_payment' then (select jsonb_build_object('doc_number', coalesce(nullif(btrim(coalesce(p.reference, '')), ''), 'Supplier payment ' || p.paid_on::text || ' ' || trim_scale(p.amount)::text),
                                                      'name', (select string_agg(distinct s.name, ', ') from public.po_payment_alloc a left join public.po_invoice i on i.id = a.po_invoice_id left join public.po_charge c on c.id = a.po_charge_id join public.supplier s on s.id = coalesce(i.supplier_id, c.supplier_id) where a.po_payment_id = p.id),
                                                      'customer_id', null, 'currency', (select r.code from public.ref_currency r where r.id = p.currency_id), 'total', p.amount, 'doc_date', p.paid_on, 'doc_status', 'active')
                              from public.po_payment p where p.id::text = p_ims_id)   -- 4-5a: 공급처 결제 = reference(없으면 「Supplier payment <날> <금액>」) · 붙임의 공급처 · 통화 · 금액 · 결제일 · 상태 없음(지워지면 행이 없다 → null)
    else jsonb_build_object('doc_number', p_ims_id, 'name', p_ims_id, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', null) end;
$function$
;

-- ═══ qbo_job_list ═══
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
                             when 'po_discount' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 4-7a 조기 결제 할인 VendorCredit
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
      left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund', 'cost_sheet', 'po_invoice', 'po_credit', 'po_charge', 'po_payment', 'po_discount')   -- 4-7a + po_discount   -- 2e-3-2-1 + refund · 3-2b + cost_sheet(JournalEntry)
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

-- ═══ qbo_job_on_po_payment ═══
CREATE OR REPLACE FUNCTION public.qbo_job_on_po_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_pid uuid; v_by uuid; v_det text; v_aid uuid;
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
  if tg_table_name = 'po_payment_alloc' then                                                                                           -- 4-7a: 그 붙임의 할인 VC 를 맞춘다 — 결제 sync 뒤(방금 선 결제 void 일감 뒤에 손으로 지우기 일감을 건다 · 1146) · 붙임이 지워졌으면 OLD.id 로
    if tg_op = 'DELETE' then v_aid := old.id; else v_aid := new.id; end if;
    begin
      perform public.qbo_discount_credit_sync(v_aid, v_by, v_pid);
    exception when others then
      begin
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff)
        select c.realm_id, 'vendor_credit', 'po_discount', v_aid::text, 'failed', left('could not queue: ' || sqlerrm, 2000), v_by from public.qbo_connection c where c.singleton
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      exception when others then null;
      end;
    end;
  end if;
  return null;
end;
$function$
;

-- ═══ qbo_bill_payment_body ═══
CREATE OR REPLACE FUNCTION public.qbo_bill_payment_body(p_payment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_realm text := public.qbo_realm_of(); v_home text := coalesce(nullif(btrim((select c.value from public.inv_config c where c.key = 'base_currency')), ''), 'CAD');
  v_p public.po_payment%rowtype; v_s public.supplier%rowtype; v_a public.ref_account%rowtype; v_label text; v_cur text; v_acur text; v_sup_id uuid; v_sup_n int; v_n int;
  v_vendor text; v_ap text; v_ap_cur text; v_acct text; v_mirror jsonb; v_mtype text; v_mcur text; v_doc text; v_cut boolean := false; v_ref text; v_note text; v_applied numeric := 0; v_disc numeric := 0; v_gap numeric; v_credit_docs text;
  v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_lines jsonb := '[]'::jsonb; v_checks jsonb := '[]'::jsonb; v_wait uuid; v_wait_doc text; v_pay jsonb; v_body jsonb;
  a record; v_t public.qbo_txn%rowtype; v_bj public.qbo_job%rowtype;
  d record; v_pt record; v_dt public.qbo_txn%rowtype; v_dj public.qbo_job%rowtype; v_wait_why text;   -- 4-7a 할인 VC
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
  -- 4-7a 판정 1143 · 1145: 조기 결제 할인은 이제 보낸다(할인 VendorCredit 을 결제에 붙인다) — 못 보내는 할인만 사람에게: 청구서의 할인 · 세금 몫 · goods 밖 몫 · 세금 있는 인보이스
  for d in select x.discount_amount, x.discount_tax_part, x.discount_other_part, x.po_invoice_id, coalesce(i.invoice_number, c.charge_number) as number, coalesce(m.tax_amount, 0) as inv_tax
             from public.po_payment_alloc x left join public.po_invoice i on i.id = x.po_invoice_id left join public.po_invoice_money m on m.id = x.po_invoice_id left join public.po_charge c on c.id = x.po_charge_id
            where x.po_payment_id = v_p.id and x.discount_amount > 0 order by coalesce(i.invoice_number, c.charge_number), x.id loop
    if d.po_invoice_id is null then
      raise exception '% (early-payment discount % % on charge %: the QuickBooks account for a discount on a charge bill is not decided yet) — or remove the discount in IMS and it is sent again — nothing was sent', c_hand, trim_scale(d.discount_amount), v_cur, d.number;
    end if;
    select pp.tax_part, pp.other_part into v_pt from public.po_invoice_discount_parts(d.po_invoice_id, d.discount_amount, null) pp;
    if coalesce(v_pt.tax_part, 0) <> 0 or d.discount_tax_part <> 0 then
      raise exception '% (1145: early-payment discount % % on invoice % includes a tax share of % — IMS sends a before-tax discount only) — or change it to a before-tax discount in IMS and it is sent again — nothing was sent', c_hand, trim_scale(d.discount_amount), v_cur, d.number, trim_scale(greatest(coalesce(v_pt.tax_part, 0), d.discount_tax_part));
    end if;
    if coalesce(v_pt.other_part, 0) <> 0 or d.discount_other_part <> 0 then
      raise exception '% (early-payment discount % % on invoice % falls partly on lines that are not goods) — or remove the discount in IMS and it is sent again — nothing was sent', c_hand, trim_scale(d.discount_amount), v_cur, d.number;
    end if;
    if d.inv_tax <> 0 then
      raise exception '% (early-payment discount % % on invoice %: the invoice carries tax, and the tax code of a discount on a taxed invoice is not decided yet) — or remove the discount in IMS and it is sent again — nothing was sent', c_hand, trim_scale(d.discount_amount), v_cur, d.number;
    end if;
  end loop;
  select string_agg(i.invoice_number, ', ' order by i.invoice_number) into v_credit_docs
    from public.po_payment_alloc x join public.po_invoice i on i.id = x.po_invoice_id
   where x.po_payment_id = v_p.id and exists (select 1 from public.po_invoice cr where cr.credit_for_invoice_id = i.id and cr.doc_kind = 'credit' and cr.status <> 'cancelled');   -- 4-7a 판정 1147: unpaid 와 같은 조건(초안 크레딧도 뺀다)
  if v_credit_docs is not null then
    raise exception '% (1132 ② · 1147: invoice % has a supplier credit attached to it in IMS, draft or confirmed, so the amount paid is not the bill amount) — or cancel that credit in IMS, then press Retry — nothing was sent', c_hand, v_credit_docs;
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
  for a in select x.id as alloc_id, x.discount_amount, x.amount, case when x.po_invoice_id is not null then 'po_invoice' else 'po_charge' end as ims_kind, coalesce(x.po_invoice_id, x.po_charge_id) as doc_id,
                  coalesce(i.invoice_number, c.charge_number) as number, coalesce(i.status, c.status) as status, coalesce(i.created_at, c.created_at) as created_at, case when x.po_invoice_id is not null then 'Invoice' else 'Charge' end as label
             from public.po_payment_alloc x left join public.po_invoice i on i.id = x.po_invoice_id left join public.po_charge c on c.id = x.po_charge_id
            where x.po_payment_id = v_p.id order by coalesce(i.invoice_number, c.charge_number), x.created_at, x.id loop
    if a.status <> 'confirmed' then raise exception '% % is % — only a confirmed document is paid in QuickBooks — nothing was sent', a.label, a.number, a.status; end if;
    select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = a.ims_kind and t.ims_id = a.doc_id::text and t.voided_at is null;
    if v_t.id is not null then
      v_lines := v_lines || jsonb_build_object('Amount', a.amount, 'LinkedTxn', jsonb_build_array(jsonb_build_object('TxnId', v_t.qbo_id, 'TxnType', 'Bill')));
      v_checks := v_checks || jsonb_build_object('txn_type', 'Bill', 'doc_number', a.number, 'qbo_bill_id', v_t.qbo_id, 'qbo_txn_id', v_t.qbo_id, 'amount', a.amount);   -- 4-7a txn_type · qbo_txn_id(qbo_bill_id 는 4-5b EF 를 위해 남긴다)
    elsif not public.qbo_po_since_ok(a.created_at) then
      raise exception '% (% % was created in IMS before the QuickBooks start date — its bill did not come from IMS) — nothing was sent', c_hand, a.label, a.number;
    else
      select * into v_bj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'bill' and j.ims_kind = a.ims_kind and j.ims_id = a.doc_id::text order by j.created_at desc, j.id desc limit 1;
      if v_bj.id is null then raise exception '% % has no QuickBooks bill job — confirm and send the bill first — nothing was sent', a.label, a.number; end if;
      if v_bj.state = 'skipped' then raise exception 'The bill job of % % was skipped — skip this payment too, or retry the bill first — nothing was sent', lower(a.label), a.number; end if;
      if v_bj.state = 'sent' then raise exception 'The bill job of % % is sent but no QuickBooks bill is on file — check qbo_txn by hand — nothing was sent', lower(a.label), a.number; end if;
      if v_wait is null then v_wait := v_bj.id; v_wait_doc := a.number; end if;
    end if;
    if a.discount_amount > 0 then                                                                                                      -- 4-7a 판정 1143 · 1146: 할인 = 그 붙임의 할인 VendorCredit 줄(E-8 꼴) · 선 VC 를 다시 쓴다 · 아직이면 그 일감 뒤 · skipped 면 사람에게(영구 blocked 방지)
      select * into v_dt from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'po_discount' and t.ims_id = a.alloc_id::text and t.voided_at is null;
      if v_dt.id is not null then
        v_lines := v_lines || jsonb_build_object('Amount', a.discount_amount, 'LinkedTxn', jsonb_build_array(jsonb_build_object('TxnId', v_dt.qbo_id, 'TxnType', 'VendorCredit')));
        v_checks := v_checks || jsonb_build_object('txn_type', 'VendorCredit', 'doc_number', coalesce(v_dt.doc_number, a.number), 'qbo_txn_id', v_dt.qbo_id, 'amount', a.discount_amount);
      else
        select * into v_dj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'vendor_credit' and j.ims_kind = 'po_discount' and j.ims_id = a.alloc_id::text order by j.created_at desc, j.id desc limit 1;
        if v_dj.id is null or v_dj.state = 'sent' then
          raise exception 'The early-payment discount of invoice % has no QuickBooks vendor credit job yet — press Retry on this payment job and it is queued — nothing was sent', a.number;
        end if;
        if v_dj.state = 'skipped' then
          raise exception 'The vendor credit job for the early-payment discount of invoice % was skipped — retry that job first, or enter this payment in QuickBooks by hand and press Skip on this job — nothing was sent', a.number;
        end if;
        if v_wait is null then v_wait := v_dj.id; v_wait_doc := a.number; v_wait_why := format('waiting for the early-payment discount credit of invoice %s to reach QuickBooks first — send it too', a.number); end if;
      end if;
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
    'body', v_body, 'needs', v_needs, 'wait_job', v_wait, 'wait_invoice', v_wait_doc, 'wait_reason', case when v_wait is not null then coalesce(v_wait_why, format('waiting for bill %s to reach QuickBooks first — send it too', v_wait_doc)) end,
    'warnings', to_jsonb(v_warn), 'line_count', jsonb_array_length(v_lines),
    'totals', jsonb_build_object('amount', v_p.amount, 'applied', v_applied, 'discount', v_disc, 'currency', v_cur, 'exchange_rate', case when v_cur <> v_home then v_p.exchange_rate end),
    'fingerprint', public.qbo_bill_payment_fingerprint(v_p.id), 'check_lines', v_checks,
    'lookup', jsonb_build_object('entity', 'BillPayment', 'vendor_ref', v_vendor, 'txn_date', to_char(v_p.paid_on, 'YYYY-MM-DD'), 'total_amt', v_p.amount, 'total_cents', round(v_p.amount * 100)::bigint, 'currency', v_cur,
                                 'private_note', 'IMS supplier payment ' || v_p.id::text, 'account_ref', v_acct, 'pay_type', v_pay->>'PayType'));
end;
$function$
;

-- ═══ qbo_cost_expected ═══
CREATE OR REPLACE FUNCTION public.qbo_cost_expected(p_until date, p_since date DEFAULT NULL::date, p_realm text DEFAULT NULL::text)
 RETURNS TABLE(wh_code text, key_kind text, doc_key text, acct_a text, acct_b text, cents bigint, raw_amount numeric, status text, reason text, entity_customer_id uuid, first_on date, last_on date, n_events integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_since   date := coalesce(p_since, (select nullif(btrim(c.value), '')::date from public.inv_config c where c.key = 'qbo_cost_since'));
  v_realm   text := coalesce(p_realm, (select c.realm_id from public.qbo_connection c where c.singleton));
  v_thr     numeric := coalesce((select nullif(btrim(c.value), '')::numeric from public.inv_config c where c.key = 'qbo_cost_adjust_hold_over'), 1000);
  v_adj_def text := (select nullif(btrim(c.value), '') from public.inv_config c where c.key = 'inv_adjust_default_account_code');
  v_excl    text[] := public.qbo_cost_excluded_docs();
  c_inv     constant text := '_59_';
  c_transit constant text := '_1150040007_';
  c_cogs    constant text := '_58_';
  c_ginr    constant text := '_1150040012_';
begin
  if p_until is null then raise exception 'p_until is required — nothing was read'; end if;
  if v_since is null then raise exception 'inv_config qbo_cost_since is not set — a migration sets it — nothing was read'; end if;
  if v_adj_def is null then raise exception 'inv_config inv_adjust_default_account_code is not set — a migration sets it — nothing was read'; end if;
  return query
  with scope as (select distinct g.doc_number as d from public.inv_ledger g where g.source = 'ims'),
  fix as (select 'adj:' || a.id::text as lr from public.inv_cost_adjust a where a.kind = 'opening_fix'),
  -- ── 소진 ──
  -- ⚠️ cons_raw 는 materialized — planner 가 이 필터를 4 행으로 짐작해 inv_layer 38k 행을 바깥에 두고 7k × 38k 를 돌렸다(실측 35 s) · 먼저 굳히면 소진 7k 행마다 PK 조회(0.3 s)
  cons_raw as materialized (
    select c.id as cid, c.layer_id as clid, c.doc_type as cdt, c.doc_number as cdoc, c.line_ref as clr, c.reason as crs, c.occurred_on as con, c.amount as camt, c.split_basis as csb,
           (c.doc_number = any (v_excl)) as is_excl, (c.line_ref in (select f.lr from fix f)) as is_fix
    from public.inv_layer_consume c
    where c.occurred_on between v_since and p_until
      and (c.doc_number in (select s.d from scope s) or c.doc_number = any (v_excl) or c.line_ref in (select f.lr from fix f)
           or (c.doc_type = 'cost' and exists (select 1 from public.po_charge pc where pc.charge_number = c.doc_number)))
  ),
  cons as (
    select c.cid, c.cdt, c.cdoc, c.clr, c.crs, c.con, c.camt, c.csb, c.is_excl, c.is_fix,
           l.id as lid, l.warehouse as lwh, case when l.warehouse = 'IN_TRANSIT' then c_transit else c_inv end as lacct, public.qbo_cost_layer_wh(l.warehouse, l.doc_number) as lcode
    from cons_raw c join public.inv_layer l on l.id = c.clid
  ),
  ev_cons as (
    -- sale → SO · 차 #58 / 대 #59(창고)
    select x.lcode as e_wh, 'SO' as e_kind, x.cdoc as e_key, c_cogs as e_dr, x.lacct as e_cr, x.camt as e_amt, x.con as e_on,
           case when x.is_excl then 'excluded' when x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end as e_status,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end as e_reason
    from cons x where x.crs = 'sale'
    union all
    -- reversal(크레딧 취소) → CR · 차 #58 / 대 #59
    select x.lcode, 'CR', x.cdoc, c_cogs, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from cons x where x.crs = 'reversal'
    union all
    -- adjust_out → ADJ · 차 조정 계정(inv_adjust_account · 1087) / 대 #59
    select x.lcode, 'ADJ', x.cdoc, aa.code, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null or aa.code is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when aa.code is null then 'adjustment ' || x.cdoc || ' not found (account unknown)' end
    from cons x left join lateral (select y.account_code as code from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) y where a.adjust_number = x.cdoc) aa on true
    where x.crs = 'adjust_out'
    union all
    -- transfer 출발(보낸 창고 레이어) → TRF · 차 In Transit / 대 #59
    select x.lcode, 'TRF', x.cdoc, c_transit, c_inv, x.camt, x.con,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from cons x where x.crs = 'transfer' and x.lwh <> 'IN_TRANSIT'
    union all
    -- transfer 도착(IN_TRANSIT 레이어 소진 → 받는 창고의 장) → TRF · 차 #59 / 대 In Transit
    select tw.code, 'TRF', x.cdoc, c_inv, c_transit, x.camt, x.con,
           case when x.is_excl then 'excluded' when tw.code is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when tw.code is null then 'receiving warehouse unknown for transfer ' || x.cdoc end
    from cons x left join lateral (select public.qbo_cost_wh_code(w.name) as code from public.inv_transfer t join public.ref_warehouse w on w.id = t.to_warehouse_id where t.transfer_number = x.cdoc) tw on true
    where x.crs = 'transfer' and x.lwh = 'IN_TRANSIT'
    union all
    -- cost_late → items 로 나눈다: sale 몫 → SO · 차 #58(1084) / 대 #59 · adjust_out · lost 몫 → ADJ · 차 그 조정 계정(1095) / 대 #59 · 그 밖 → block
    select x.lcode,
           case when it->>'reason' = 'sale' then 'SO' when it->>'reason' in ('adjust_out', 'lost') then 'ADJ' else 'cost_late' end,
           coalesce(it->>'doc_number', x.cdoc),
           case when it->>'reason' = 'sale' then c_cogs when it->>'reason' in ('adjust_out', 'lost') then ia.code else null end,
           x.lacct,
           case when coalesce(sh.tot, 0) > 0 then x.camt * (it->>'share')::numeric / sh.tot else x.camt end,
           x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null then 'block' when it->>'reason' = 'sale' then 'send' when it->>'reason' in ('adjust_out', 'lost') and ia.code is not null then 'send' else 'block' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text
                when it->>'reason' = 'sale' then null when it->>'reason' in ('adjust_out', 'lost') and ia.code is not null then null
                else 'late cost ' || x.cdoc || ' has an item of kind ' || coalesce(it->>'reason', '?') || ' — not mapped' end
    from cons x
    cross join lateral (select coalesce(sum((i->>'share')::numeric), 0) as tot from jsonb_array_elements(coalesce(x.csb->'items', '[]'::jsonb)) i) sh
    cross join lateral jsonb_array_elements(case when jsonb_typeof(x.csb->'items') = 'array' and jsonb_array_length(x.csb->'items') > 0 then x.csb->'items' else '[{"reason":"no_items"}]'::jsonb end) it
    left join lateral (select y.account_code as code from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) y where a.adjust_number = it->>'doc_number' and it->>'reason' in ('adjust_out', 'lost')) ia on true
    where x.crs = 'cost_late'
    union all
    -- cost_moved → 자식(트랜스퍼) 레이어의 창고 계정 ↔ 제 계정 · 같으면 0(줄 없음) · 자식 창고가 둘이거나 없으면 block
    select x.lcode, case when x.cdt = 'cost' then 'CHG' else 'TRF' end, x.cdoc,
           case when ch.n = 1 then ch.acct else x.lacct end, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null or ch.n <> 1 then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when ch.n <> 1 then 'moved cost ' || x.cdoc || ' has ' || ch.n::text || ' child warehouses (expected 1)' end
    from cons x
    cross join lateral (select count(distinct y.warehouse) as n, min(case when y.warehouse = 'IN_TRANSIT' then c_transit else c_inv end) as acct from public.inv_layer y where y.parent_layer_id = x.lid and y.origin_type = 'transfer') ch
    where x.crs = 'cost_moved'
    union all
    -- assembly_in → FG · 같은 창고 #59 ↔ #59 = 0(줄 없음 · 값 차이는 아래 asm_check 가 막는다)
    select x.lcode, 'FG', x.cdoc, x.lacct, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from cons x where x.crs = 'assembly_in'
    union all
    -- lost → 막음(deferred 512) · 그 밖(제약이 넓어진 칸) → 막음
    select coalesce(x.lcode, 'TOR'), x.crs, x.cdoc, x.lacct, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' else 'block' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.crs = 'lost' then 'consume reason lost on ' || x.cdoc || ' — meaning not decided (deferred 512)' else 'consume reason ' || x.crs || ' on ' || x.cdoc || ' — not in the 22 cells' end
    from cons x where x.crs not in ('sale', 'reversal', 'adjust_out', 'transfer', 'cost_late', 'cost_moved', 'assembly_in')
  ),
  -- ── 레이어(생김) ──
  lay as (
    select l.id as lid, l.origin_type as lor, l.doc_number as ldoc, l.received_on as lon, l.qty * l.unit_cost as lamt, l.warehouse as lwh,
           case when l.warehouse = 'IN_TRANSIT' then c_transit else c_inv end as lacct, public.qbo_cost_layer_wh(l.warehouse, l.doc_number) as lcode, (l.doc_number = any (v_excl)) as is_excl
    from public.inv_layer l
    where l.origin_type not in ('baseline', 'transfer') and l.received_on between v_since and p_until
      and (l.doc_number in (select s.d from scope s) or l.doc_number = any (v_excl))
  ),
  ev_lay as (
    -- purchase(입고) → RCV · 차 #59 / 대 GINR · [4-3b · 판정 1119 · 1120] 보류를 푼다 — 무조건(그 Bill 이 QBO 에 갔는지와 무관) · 날짜 = 입고일(received_on) · Bill 이 늦으면 GINR 이 잠시 음수 = 「안 보낸 Bill 이 있다」 신호
    select x.lcode as e_wh, 'RCV' as e_kind, x.ldoc as e_key, x.lacct as e_dr, c_ginr as e_cr, x.lamt as e_amt, x.lon as e_on,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end as e_status,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end as e_reason
    from lay x where x.lor = 'purchase'
    union all
    -- creditnote(restock) → CR · 차 #59 / 대 #58
    select x.lcode, 'CR', x.ldoc, x.lacct, c_cogs, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from lay x where x.lor = 'creditnote'
    union all
    -- adjust_new · adjust_existing → ADJ · 차 #59 / 대 조정 계정(1087)
    select x.lcode, 'ADJ', x.ldoc, x.lacct, aa.code, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null or aa.code is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when aa.code is null then 'adjustment ' || x.ldoc || ' not found (account unknown)' end
    from lay x left join lateral (select y.account_code as code from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) y where a.adjust_number = x.ldoc) aa on true
    where x.lor in ('adjust_new', 'adjust_existing')
    union all
    -- sale_shortfall → SO · 차 #59 / 대 조정 기본 계정(1094 · 판매 원가 줄은 그대로)
    select x.lcode, 'SO', x.ldoc, x.lacct, v_adj_def, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from lay x where x.lor = 'sale_shortfall'
    union all
    -- assembly → FG · 같은 창고 #59 ↔ #59 = 0
    select x.lcode, 'FG', x.ldoc, x.lacct, x.lacct, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from lay x where x.lor = 'assembly'
    union all
    -- 그 밖(제약이 넓어진 칸) → 막음
    select coalesce(x.lcode, 'TOR'), x.lor, x.ldoc, x.lacct, x.lacct, x.lamt, x.lon, 'block', 'layer origin ' || x.lor || ' on ' || x.ldoc || ' — not in the 22 cells'
    from lay x where x.lor not in ('purchase', 'creditnote', 'adjust_new', 'adjust_existing', 'sale_shortfall', 'assembly')
  ),
  -- 조립 값 검산 — 문서마다 Σ소진(assembly_in) ≠ Σ레이어(assembly) 면 막음(같은 창고 #59 ↔ #59 라 줄은 없지만 값이 새면 안 된다)
  asm_check as (
    select coalesce(a.e_wh, b.e_wh) as e_wh, 'FG' as e_kind, coalesce(a.e_key, b.e_key) as e_key, c_inv as e_dr, c_inv as e_cr, coalesce(a.s, 0) - coalesce(b.s, 0) as e_amt, coalesce(a.o, b.o) as e_on,
           'block' as e_status, 'assembly ' || coalesce(a.e_key, b.e_key) || ' consumes ' || coalesce(a.s, 0)::text || ' but the finished layer is worth ' || coalesce(b.s, 0)::text as e_reason
    from (select e.e_wh, e.e_key, sum(e.e_amt) as s, min(e.e_on) as o from ev_cons e where e.e_kind = 'FG' and e.e_status = 'send' group by 1, 2) a
    full join (select e.e_wh, e.e_key, sum(e.e_amt) as s, min(e.e_on) as o from ev_lay e where e.e_kind = 'FG' and e.e_status = 'send' group by 1, 2) b on b.e_wh = a.e_wh and b.e_key = a.e_key
    where abs(coalesce(a.s, 0) - coalesce(b.s, 0)) > 0.005
  ),
  -- ── 얹기 ──
  adds_raw as materialized (
    select a.id as aid, a.layer_id as alid, a.kind as akd, a.doc_number as adoc, a.line_ref as alr, a.occurred_on as aon, a.amount as aamt,
           (a.line_ref in (select f.lr from fix f)) as is_fix, (a.doc_number in (select s.d from scope s)) as in_scope
    from public.inv_layer_cost_add a
    where a.kind <> 'carried' and a.occurred_on between v_since and p_until
  ),
  adds as (
    select a.aid, a.akd, a.adoc, a.alr, a.aon, a.aamt, a.is_fix, a.in_scope,
           l.id as lid, l.warehouse as lwh, case when l.warehouse = 'IN_TRANSIT' then c_transit else c_inv end as lacct, public.qbo_cost_layer_wh(l.warehouse, l.doc_number) as lcode,
           pc.kind as pckind, (pc.id is not null) as is_ims_charge, ca.source_number as ca_num
    from adds_raw a join public.inv_layer l on l.id = a.alid
    left join public.po_charge pc on a.akd = 'landed' and pc.charge_number = a.adoc
    left join public.inv_cost_adjust ca on a.akd in ('price_adjust', 'settlement_discount') and a.alr = 'adj:' || ca.id::text
  ),
  ev_add as (
    -- landed(IMS 비용 문서) → CHG · 차 #59(운송 중 레이어면 In Transit) / 대 비용 종류 계정(1089) · 날짜 = IMS 가 얹은 날(507) · Cin7 축 landed 는 범위 밖
    select x.lcode as e_wh, 'CHG' as e_kind, x.adoc as e_key, x.lacct as e_dr, public.qbo_cost_charge_account(x.pckind) as e_cr, x.aamt as e_amt, x.aon as e_on,
           case when x.is_fix then 'excluded' when x.lcode is null or public.qbo_cost_charge_account(x.pckind) is null then 'block' else 'send' end as e_status,
           case when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when public.qbo_cost_charge_account(x.pckind) is null then 'charge ' || x.adoc || ' kind ' || coalesce(x.pckind, '?') || ' has no cost account (1089)' end as e_reason
    from adds x where x.akd = 'landed' and (x.is_ims_charge or x.is_fix)
    union all
    -- transfer_freight(Cin7 축 꼴 · 문서가 범위 안일 때만) → TRF · 차 #59 / In Transit / 대 #136(1100 · 종류 없음)
    select x.lcode, 'TRF', x.adoc, x.lacct, '_136_', x.aamt, x.aon,
           case when x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from adds x where x.akd = 'transfer_freight' and (x.in_scope or x.is_fix)
    union all
    -- price_adjust · settlement_discount(원가 조정 사건) → CADJ · [4-3b · 판정 1121] 대 계정 = GINR(#59 · #58 은 원가 장만 · VendorCredit 은 A/P ↔ GINR) · 가격 크레딧(price_adjust)은 보낸다 · 조기 결제 할인(settlement_discount)은 결제 차수(4-5)까지 보류
    select x.lcode, 'CADJ', coalesce(x.ca_num, x.alr), x.lacct, c_ginr, x.aamt, x.aon,
           case when x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end,   -- 4-7a 판정 1149: settlement_discount 도 무조건 send(할인 VendorCredit 이 A/P ↔ GINR 로 짝을 맞춘다 · VC 가 늦으면 GINR 이 신호)
           case when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text else null end
    from adds x where x.akd in ('price_adjust', 'settlement_discount')
    union all
    -- opening_fix → 제외(932 · 1090) · 그 밖(제약이 넓어진 칸) → 막음
    select coalesce(x.lcode, 'TOR'), x.akd, x.adoc, x.lacct, x.lacct, x.aamt, x.aon,
           case when x.akd = 'opening_fix' or x.is_fix then 'excluded' else 'block' end,
           case when x.akd = 'opening_fix' or x.is_fix then 'opening_fix (1090)' else 'cost add kind ' || x.akd || ' on ' || x.adoc || ' — not in the 22 cells' end
    from adds x where x.akd not in ('landed', 'transfer_freight', 'price_adjust', 'settlement_discount')
  ),
  ev as (
    select * from ev_cons union all select * from ev_lay union all select * from asm_check union all select * from ev_add
  ),
  -- 문턱(1099): ADJ 문서마다 Σ|금액|(들어옴 · 나감) > 문턱이면 보류 · 결정 send → send · never → excluded
  adj_tot as (select e.e_key as k, sum(abs(e.e_amt)) as tot from ev e where e.e_kind = 'ADJ' and e.e_status = 'send' group by 1),
  ev2 as (
    select e.e_wh, e.e_kind, e.e_key, e.e_dr, e.e_cr, e.e_amt, e.e_on,
           case when e.e_kind = 'ADJ' and e.e_status = 'send' and t.tot > v_thr then
                  case h.decision when 'send' then 'send' when 'never' then 'excluded' else 'hold' end
                else e.e_status end as e_status,
           case when e.e_kind = 'ADJ' and e.e_status = 'send' and t.tot > v_thr then
                  case h.decision when 'send' then 'adjustment over threshold — decided: send' when 'never' then 'adjustment over threshold — decided: never send'
                       else 'adjustment ' || e.e_key || ' totals ' || round(t.tot, 2)::text || ' over the ' || v_thr::text || ' threshold — decide send / never first (1099)' end
                else e.e_reason end as e_reason
    from ev e
    left join adj_tot t on e.e_kind = 'ADJ' and t.k = e.e_key
    left join public.qbo_cost_hold h on v_realm is not null and h.realm_id = v_realm and h.key_kind = e.e_kind and h.doc_key = e.e_key
  ),
  agg as (
    select e.e_wh, e.e_kind, e.e_key,
           least(e.e_dr, coalesce(e.e_cr, e.e_dr)) as a, greatest(e.e_dr, coalesce(e.e_cr, e.e_dr)) as b,
           sum(case when e.e_dr = least(e.e_dr, coalesce(e.e_cr, e.e_dr)) then e.e_amt else -e.e_amt end) as raw,
           e.e_status, min(e.e_reason) as rs, min(e.e_on) as f_on, max(e.e_on) as l_on, count(*)::int as n,
           bool_or(e.e_cr is null) as cr_null
    from ev2 e
    group by e.e_wh, e.e_kind, e.e_key, least(e.e_dr, coalesce(e.e_cr, e.e_dr)), greatest(e.e_dr, coalesce(e.e_cr, e.e_dr)), e.e_status
  )
  select g.e_wh, g.e_kind, g.e_key, g.a, case when g.cr_null then null else g.b end, (round(g.raw, 2) * 100)::bigint, g.raw, g.e_status, g.rs,
         case when g.e_kind = 'SO' and c_cogs in (g.a, g.b) then (select io.customer_id from public.so_invoice_order io join public.so_invoice i on i.id = io.invoice_id where io.so_number = g.e_key and io.cancelled_at is null and i.status = 'issued' order by i.issued_on desc, i.created_at desc limit 1)
              when g.e_kind = 'CR' and c_cogs in (g.a, g.b) then (select coalesce(cr.store_customer_id, cr.customer_id) from public.so_credit cr where cr.credit_number = g.e_key) end,
         g.f_on, g.l_on, g.n
  from agg g
  where round(g.raw, 2) <> 0 or g.e_status = 'block'
  order by g.e_wh, g.e_kind, g.e_key, g.a, g.b;
end;
$function$
;

-- ═══ po_invoice_confirm ═══
CREATE OR REPLACE FUNCTION public.po_invoice_confirm(p_invoice_id uuid, p_confirm boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_num   text;                                                 -- ②-b: 0행 문장용 번호(returning 이 v_inv 를 null 로 덮는다)
  v_staff uuid;
  v_inv   public.po_invoice%rowtype;
  v_for   public.po_invoice%rowtype;
  v_m     record;
  v_cnt   int;
  v_cred  int;
  v_warn  text[] := '{}';
  v_label text;
  v_p     record;                                               -- inv-basis-2: 이 인보이스가 가리키는 발주(goods 줄 · 문서마다)
  v_po    public.po%rowtype;
  v_s     public.po%rowtype;                                    -- Reopen 되붙임: 이 확정이 만든 형제
  v_base  text;  v_max text;  v_b_num text;  v_b_id uuid;
  v_rem   int;   v_left numeric;  v_n int;  v_orig uuid;  v_orig_qty numeric;
  v_lines jsonb;  v_split jsonb := '[]'::jsonb;  v_reat jsonb := '[]'::jsonb;
  x       record;
  v_cev   jsonb;  v_crv jsonb;  v_sg record;                   -- po-disc-5a: 크레딧 원가 사건 · 되돌림 · 제안 식(⬜1 확정 거부)
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_inv from public.po_invoice where id = p_invoice_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_invoice_id; end if;
  v_label := case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  v_num := v_inv.invoice_number;
  select * into v_m from public.po_invoice_money where id = p_invoice_id;

  if p_confirm then
    if v_inv.status = 'confirmed' then raise exception '% % is already confirmed — nothing was saved', v_label, v_inv.invoice_number; end if;
    if v_inv.status = 'cancelled' then raise exception '% % is cancelled — a cancelled document cannot be confirmed — nothing was saved', v_label, v_inv.invoice_number; end if;
    select count(*) into v_cnt from public.po_invoice_line where po_invoice_id = p_invoice_id;
    if v_cnt = 0 then raise exception '% % has no lines — nothing to accept into the books — nothing was saved', v_label, v_inv.invoice_number; end if;
    if v_inv.credit_for_invoice_id is not null then                       -- 다른 행의 사실 — po_detail credits[].warnings 와 같은 셋을 여기서는 막는다
      select * into v_for from public.po_invoice where id = v_inv.credit_for_invoice_id;
      if v_for.doc_kind <> 'invoice' then raise exception 'Credit note % points at another credit note (%) — nothing was saved', v_inv.invoice_number, v_for.invoice_number; end if;
      if v_for.supplier_id <> v_inv.supplier_id then raise exception 'Credit note % points at an invoice of a different supplier (%) — nothing was saved', v_inv.invoice_number, v_for.invoice_number; end if;
    end if;
    if v_inv.total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;                 -- 샘플 인보이스 실물 · 막지 않는다
    if v_m.diff <> 0 then v_warn := array_append(v_warn, 'total_differs_from_lines'); end if;                   -- 반올림 · other 할인 미결 · 정본은 찍힌 값 · 막지 않는다
    if v_inv.doc_kind = 'invoice' then                                                                          -- 4-7a 판정 1144: 지급 기한이 비었거나 결제조건(문서 날짜 + net_days)과 다르면 경고 — 막지 않는다
      if v_inv.due_date is null then v_warn := array_append(v_warn, 'due_date_missing');
      elsif exists (select 1 from public.ref_payment_term pt where pt.id = v_inv.payment_term_id and pt.net_days is not null and v_inv.invoice_date + pt.net_days <> v_inv.due_date) then v_warn := array_append(v_warn, 'due_date_differs_from_term'); end if;
    end if;
    -- ═══ inv-basis-2 · 판정 88 ④ ⑤ · 92 · 96 — 인보이스 확정 = PO 분할: 발주마다 청구된 몫만 원래 번호에 남고, 덜 청구된 수량과 인보이스에 없는 줄은 형제(다음 글자 하나)로 ═══
    --   막는 것(판정 92 · 예외 없음): PO 가 confirmed 가 아님 · 그 PO 에 입고(초안이든 확정이든)가 있음 · 이 인보이스 줄이 PO 줄의 남은 수량(qty_ea − 다른 확정 인보이스 goods 합)을 넘음(판정 96)
    --   초안 인보이스는 아무 일 없음(이 갈래는 확정에만) · 크레딧은 갈라지지 않는다 · 비용 배분 · 크레딧 연결(credit_po_id)은 원래 번호에 남는다(판정 93 ⓛ) · 형제 = split_from_id 원래 PO · split_by_invoice_id 이 인보이스
    if v_inv.doc_kind = 'invoice' then
      for v_p in
        select distinct pl.po_id
        from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id
        where il.po_invoice_id = p_invoice_id and il.line_kind = 'goods'
        order by 1
      loop
        select * into v_po from public.po where id = v_p.po_id for update;
        v_base := regexp_replace(v_po.po_number, '[a-z]+$', '');
        perform pg_advisory_xact_lock(hashtext('po:' || v_base));                                              -- 형제 채번 · 입고 확정과 같은 열쇠
        if v_po.status <> 'confirmed' then
          raise exception 'PO % is % — an invoice can be confirmed only onto a confirmed order — nothing was saved', v_po.po_number, v_po.status;
        end if;
        if exists (select 1 from public.po_receipt r where r.po_id = v_po.id) then
          raise exception 'PO % already has a receipt — the warehouse has started on this order, so this invoice cannot be confirmed onto it; correct it with a credit note or an Off-invoice decision — nothing was saved', v_po.po_number;
        end if;
        v_rem := 0;
        for x in
          select pl.id, pl.line_no, pr.sku, pl.qty_ea,
                 coalesce((select sum(o.qty_ea) from public.po_invoice_line o join public.po_invoice oi on oi.id = o.po_invoice_id
                            where o.po_line_id = pl.id and o.line_kind = 'goods' and oi.doc_kind = 'invoice' and oi.status = 'confirmed' and oi.id <> p_invoice_id), 0) as billed_before,
                 coalesce((select sum(t.qty_ea) from public.po_invoice_line t where t.po_invoice_id = p_invoice_id and t.po_line_id = pl.id and t.line_kind = 'goods'), 0) as billed_here
          from public.po_line pl join public.product pr on pr.id = pl.product_id
          where pl.po_id = v_po.id
          order by pl.line_no
        loop
          if x.billed_here > x.qty_ea - x.billed_before then                                                  -- 판정 96
            raise exception 'Line % (%) of PO %: this invoice bills % EA but only % EA are left on the order line — raise the PO line first (Purchase Orders), then confirm the invoice — nothing was saved',
              x.line_no, x.sku, v_po.po_number, x.billed_here, x.qty_ea - x.billed_before;
          end if;
          if x.qty_ea - x.billed_before - x.billed_here > 0 then v_rem := v_rem + 1; end if;
        end loop;
        if v_rem > 0 then
          -- 번호 — base 의 접미 최댓값 다음 글자 하나(so_split 모양 · 옛 형제 a · b 뒤면 c) · 원래 번호는 그대로
          select max(substring(p.po_number from length(v_base) + 1)) into v_max
          from public.po p where p.po_number ~ ('^' || v_base || '[a-z]+$');
          if v_max is null then
            v_b_num := v_base || 'a';
          else
            if length(v_max) <> 1 or v_max >= 'y' then
              raise exception 'PO % has been split too many times (last suffix %) — split it by hand — nothing was saved', v_po.po_number, v_max;
            end if;
            v_b_num := v_base || chr(ascii(v_max) + 1);
          end if;
          v_b_id := gen_random_uuid();
          insert into public.po
          select * from jsonb_populate_record(null::public.po,
            to_jsonb(v_po) || jsonb_build_object('id', v_b_id, 'po_number', v_b_num, 'status', 'confirmed', 'split_from_id', v_po.id, 'split_by_invoice_id', p_invoice_id,
                                                 'closed_at', null, 'cancelled_at', null, 'cancelled_by', null,
                                                 'created_at', now(), 'updated_at', now(), 'updated_by', v_staff));
          insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id, note)
          select v_b_id, d.seq, d.name, d.percent, d.supplier_discount_id, d.note from public.po_discount d where d.po_id = v_po.id;
          v_lines := '[]'::jsonb;
          for x in
            select pl.*, pr.sku,
                   coalesce((select sum(o.qty_ea) from public.po_invoice_line o join public.po_invoice oi on oi.id = o.po_invoice_id
                              where o.po_line_id = pl.id and o.line_kind = 'goods' and oi.doc_kind = 'invoice' and oi.status = 'confirmed' and oi.id <> p_invoice_id), 0) as billed_before,
                   coalesce((select sum(t.qty_ea) from public.po_invoice_line t where t.po_invoice_id = p_invoice_id and t.po_line_id = pl.id and t.line_kind = 'goods'), 0) as billed_here
            from public.po_line pl join public.product pr on pr.id = pl.product_id
            where pl.po_id = v_po.id
            order by pl.line_no
          loop
            v_left := x.qty_ea - x.billed_before - x.billed_here;
            if v_left <= 0 then continue; end if;                                                              -- 다 청구됐다 — 원래 번호에 그대로
            if x.billed_before + x.billed_here = 0 then
              update public.po_line set po_id = v_b_id, updated_by = v_staff where id = x.id and po_id = v_po.id;   -- 인보이스에 없는 줄 — 행을 통째로(id 그대로 · 초안 인보이스가 가리켜도 따라간다)
              get diagnostics v_n = row_count;
              if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
              v_lines := v_lines || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', 'moved', 'qty_ea', v_left);
            else
              update public.po_line set qty_ea = x.qty_ea - v_left, entered_unit_product_id = null, entered_qty = null, entered_pack_factor = null, updated_by = v_staff
               where id = x.id and qty_ea = x.qty_ea;                                                              -- 덜 청구된 줄 — 원래 줄은 청구된 만큼으로(입력 단위 셋은 비운다)
              get diagnostics v_n = row_count;
              if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
              insert into public.po_line
              select * from jsonb_populate_record(null::public.po_line,
                to_jsonb(x) - 'sku' - 'billed_before' - 'billed_here' || jsonb_build_object('id', gen_random_uuid(), 'po_id', v_b_id, 'qty_ea', v_left,
                                                                                            'entered_unit_product_id', null, 'entered_qty', null, 'entered_pack_factor', null,
                                                                                            'created_at', now(), 'updated_at', now(), 'updated_by', v_staff));
              v_lines := v_lines || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', 'reduced', 'qty_ea', v_left);
            end if;
          end loop;
          v_split := v_split || jsonb_build_object('po_id', v_po.id, 'po_number', v_po.po_number, 'new_po_id', v_b_id, 'new_number', v_b_num, 'lines', v_lines);
          v_warn := array_append(v_warn, 'po_split');
        end if;
      end loop;
    end if;
    -- ═══ po-disc-5a(판정 400 · ⬜1) · 크레딧 확정 — goods 줄마다 뜻이 있어야 한다 · not_received 줄이 남은 안 온 수량을 넘으면 거부(줄을 나눈다) ═══
    if v_inv.doc_kind = 'credit' then
      for x in select cl.id, cl.line_no, cl.qty_ea, cl.credit_reason, cl.po_line_id, pr.sku
                 from public.po_invoice_line cl join public.po_line pl on pl.id = cl.po_line_id join public.product pr on pr.id = pl.product_id
                where cl.po_invoice_id = p_invoice_id and cl.line_kind = 'goods' order by cl.line_no loop
        if x.credit_reason is null then
          raise exception 'Credit note %: line % (%) has no reason — mark each goods line Not received or Price difference first — nothing was saved', v_inv.invoice_number, x.line_no, x.sku;
        end if;
        if x.credit_reason = 'not_received' then
          select * into v_sg from public.po_credit_reason_suggest(p_invoice_id, x.po_line_id, x.qty_ea, x.id);
          if x.qty_ea > v_sg.not_received_left then
            raise exception 'Credit note %: line % (%) marks % EA as Not received but only % EA are still unreceived on that PO line (billed % · received % · already credited %) — split the line; the rest is a price difference — nothing was saved',
              v_inv.invoice_number, x.line_no, x.sku, x.qty_ea, v_sg.not_received_left, v_sg.billed_qty, v_sg.received_qty, v_sg.credited_not_received_qty;
          end if;
        end if;
      end loop;
    end if;
    update public.po_invoice set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_invoice_id returning * into v_inv;
    if not found then raise exception '% % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_label, v_num; end if;   -- ②-b
    if v_inv.doc_kind = 'credit' then                                                                           -- po-disc-5a(판정 392 · 400): price_difference 줄마다 원가 사건 · 곧바로 얹는다(레이어 없으면 pending · 399 거부는 예외 = 확정 전체 안 저장)
      v_cev := public.po_credit_cost_events(p_invoice_id, true);
      v_warn := v_warn || array(select jsonb_array_elements_text(v_cev -> 'warnings'));
    end if;
  else
    if v_inv.status <> 'confirmed' then raise exception '% % is % — only a confirmed document can be reopened — nothing was saved', v_label, v_inv.invoice_number, v_inv.status; end if;
    if v_m.alloc_total > 0 then
      raise exception '% % has payments applied (%) — cannot reopen while paid/used; remove the payment allocation first — nothing was saved', v_label, v_inv.invoice_number, v_m.alloc_total;
    end if;
    select count(*) into v_cred from public.po_invoice c where c.credit_for_invoice_id = p_invoice_id and c.status <> 'cancelled';
    if v_cred > 0 then v_warn := array_append(v_warn, 'has_attached_credits'); end if;
    if v_inv.doc_kind = 'credit' then v_crv := public.po_credit_cost_reverse(p_invoice_id, 'credit note ' || v_inv.invoice_number || ' reopened'); end if;   -- po-disc-5a: 다시 열기 = 사건 되돌림(결제 검사 뒤 · 같은 트랜잭션)
    -- ═══ inv-basis-2 · 판정 88 ⑦ — Reopen = 되붙임: 창고가 아직 손대지 않았을 때만(그 PO 에 입고 0 · 이 확정이 만든 형제가 그대로) · 형제의 줄을 원래 줄에 되돌리고 형제를 지운다(번호는 빈다 · 판정 55) ═══
    if v_inv.doc_kind = 'invoice' then
      for v_p in
        select distinct pl.po_id
        from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id
        where il.po_invoice_id = p_invoice_id and il.line_kind = 'goods'
        order by 1
      loop
        select * into v_po from public.po where id = v_p.po_id for update;
        perform pg_advisory_xact_lock(hashtext('po:' || regexp_replace(v_po.po_number, '[a-z]+$', '')));
        if exists (select 1 from public.po_receipt r where r.po_id = v_po.id) then
          raise exception 'The warehouse has started on PO % — Reopen is not possible; correct it with a credit note or an Off-invoice decision — nothing was saved', v_po.po_number;
        end if;
        if v_po.status <> 'confirmed' then
          raise exception 'PO % is % — Reopen is not possible on a closed or cancelled order; correct it with a credit note — nothing was saved', v_po.po_number, v_po.status;
        end if;
        for v_s in select * from public.po s where s.split_from_id = v_po.id and s.split_by_invoice_id = p_invoice_id order by s.po_number loop
          if v_s.status <> 'confirmed'
             or exists (select 1 from public.po_receipt r where r.po_id = v_s.id)
             or exists (select 1 from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id where pl.po_id = v_s.id)
             or exists (select 1 from public.po_charge_alloc a where a.po_id = v_s.id)
             or exists (select 1 from public.po_invoice k where k.credit_po_id = v_s.id)
             or exists (select 1 from public.po c where c.split_from_id = v_s.id)
             or v_s.updated_at > v_s.created_at
             or exists (select 1 from public.po_line l where l.po_id = v_s.id and l.updated_at > v_s.created_at) then   -- 판정 103(inv-basis-8): 형제가 생긴 순간과 비교 — 통째로 옮긴 줄은 created_at 이 원래 PO 의 것이라 자기 created_at 과 비교하면 늘 「손댔다」였다
            raise exception 'PO % (split off by this invoice) has been worked on since — Reopen is not possible; correct it with a credit note or an Off-invoice decision — nothing was saved', v_s.po_number;
          end if;
          v_lines := '[]'::jsonb;
          for x in select pl.* from public.po_line pl where pl.po_id = v_s.id order by pl.line_no loop
            select l.id, l.qty_ea into v_orig, v_orig_qty from public.po_line l where l.po_id = v_po.id and l.line_no = x.line_no;
            if v_orig is not null then
              update public.po_line set qty_ea = v_orig_qty + x.qty_ea, updated_by = v_staff where id = v_orig and qty_ea = v_orig_qty;   -- 줄였던 줄 — 되돌려 더한다
              get diagnostics v_n = row_count;
              if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
              delete from public.po_line where id = x.id;
              v_lines := v_lines || jsonb_build_object('line_no', x.line_no, 'kind', 'restored', 'qty_ea', x.qty_ea);
            else
              update public.po_line set po_id = v_po.id, updated_by = v_staff where id = x.id;                    -- 옮겼던 줄 — 행이 돌아온다
              v_lines := v_lines || jsonb_build_object('line_no', x.line_no, 'kind', 'moved_back', 'qty_ea', x.qty_ea);
            end if;
            v_orig := null; v_orig_qty := null;
          end loop;
          delete from public.po_discount where po_id = v_s.id;
          delete from public.po where id = v_s.id;
          v_reat := v_reat || jsonb_build_object('po_id', v_po.id, 'po_number', v_po.po_number, 'removed_po_id', v_s.id, 'removed_number', v_s.po_number, 'lines', v_lines);
          v_warn := array_append(v_warn, 'po_reattached');
        end loop;
      end loop;
    end if;
    update public.po_invoice set status = 'draft', confirmed_by = null, confirmed_at = null where id = p_invoice_id returning * into v_inv;
    if not found then raise exception '% % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_label, v_num; end if;   -- ②-b
  end if;

  return jsonb_build_object(
    'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'confirmed_at', v_inv.confirmed_at,
    'money', jsonb_build_object('total_amount', v_m.total_amount, 'computed_total', v_m.computed_total, 'diff', v_m.diff, 'payable_net', v_m.payable_net,
                                'alloc_total', v_m.alloc_total, 'credit_total', v_m.credit_total, 'unpaid', v_m.unpaid, 'remaining', v_m.remaining),
    'split', v_split, 'reattached', v_reat,                       -- inv-basis-2: 확정이 가른 것 · Reopen 이 되붙인 것(화면 ⑱-3 이 확인 문장에 쓴다 · 판매 반환 키는 그대로)
    'cost_events', v_cev, 'cost_reversed', v_crv,                 -- po-disc-5a · 크레딧 확정의 사건 · 다시 열기의 되돌림(인보이스는 null)
    'warnings', to_jsonb(v_warn));
end;
$function$
;

-- ═══════════════ ⑤ grant · 주석 ═══════════════
revoke all on function public.qbo_discount_credit_body(uuid), public.qbo_discount_credit_sync(uuid, uuid, uuid), public.po_invoice_due_auto()
  from public, anon, authenticated, service_role;   -- 속 함수 셋 · grant 0(claim · preview · 트리거 · done · retry 가 definer 로 부른다 · 트리거 함수는 실행권이 필요 없다) · 재발행 열은 create or replace 라 ACL 그대로

do $$
begin
  execute format('comment on table public.qbo_job is %L', coalesce(obj_description('public.qbo_job'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-4-7a: 조기 결제 할인 VendorCredit = kind vendor_credit + ims_kind po_discount(ims_id = po_payment_alloc.id · 1143) · 결제 일감은 그 뒤에서 기다린다 · 할인이 바뀌거나 사라지면 bill_delete_manual(po_discount)이 결제 void 뒤에(1146)');
  execute format('comment on table public.qbo_txn is %L', coalesce(obj_description('public.qbo_txn'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-4-7a: ims_kind po_discount ↔ VendorCredit(ims_id = po_payment_alloc.id · fingerprint 「<할인 센트>|<통화>」 · voided_at = IMS 가 그 장을 버렸다 — 사람이 QBO 에서 지운다)');
  execute format('comment on function public.qbo_bill_payment_body(uuid) is %L', coalesce(obj_description('public.qbo_bill_payment_body(uuid)'::regprocedure, 'pg_proc'), '') || ' · ⭐ qbo-sync-4-7a(1143 ~ 1147): 조기 결제 할인을 보낸다 — 붙임마다 Bill 줄(alloc.amount) + 할인이면 VendorCredit 줄(alloc.discount_amount · 선 할인 VC 의 QBO Id) · TotalAmt = 낸 돈 · VC 아직이면 wait_job · VC 일감 skipped 면 raise · 막는 할인 = 청구서 · 세금 몫(1145) · goods 밖 몫 · 세금 있는 인보이스 · 1132 ② 는 cancelled 아닌 크레딧 모두(1147) · check_lines 에 txn_type · qbo_txn_id');
end $$;

-- ═══════════════ ⑥ 착지 검사 ═══════════════
do $$
declare v_bad text := '';
begin
  if not exists (select 1 from pg_constraint where conname = 'qbo_job_ims_kind_ck' and pg_get_constraintdef(oid) like '%po_discount%') then v_bad := v_bad || ' qbo_job_ims_kind_ck'; end if;
  if not exists (select 1 from pg_constraint where conname = 'qbo_job_pair_ck' and pg_get_constraintdef(oid) like $r$%'po_credit'::text, 'po_discount'::text%$r$) then v_bad := v_bad || ' qbo_job_pair_ck'; end if;
  if not exists (select 1 from pg_constraint where conname = 'qbo_txn_kind_ck' and pg_get_constraintdef(oid) like '%po_discount%') then v_bad := v_bad || ' qbo_txn_kind_ck'; end if;
  if not exists (select 1 from pg_constraint where conname = 'qbo_txn_pair_ck' and pg_get_constraintdef(oid) like $r$%'po_discount'::text THEN 'VendorCredit'%$r$) then v_bad := v_bad || ' qbo_txn_pair_ck'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_discount_credit_body', 'qbo_discount_credit_sync', 'po_invoice_due_auto')) <> 3 then v_bad := v_bad || ' new functions'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_preview', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_doc', 'qbo_job_list', 'qbo_job_on_po_payment', 'qbo_bill_payment_body', 'qbo_cost_expected', 'po_invoice_confirm') and prosrc like '%4-7a%') <> 10 then v_bad := v_bad || ' reissued bodies'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_preview', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_doc', 'qbo_job_list', 'qbo_job_on_po_payment', 'qbo_bill_payment_body', 'qbo_cost_expected', 'po_invoice_confirm')) <> 10 then v_bad := v_bad || ' duplicate signatures'; end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_cost_expected' and prosrc like '%opens with the supplier payment round%') then v_bad := v_bad || ' qbo_cost_expected(hold text)'; end if;
  if not exists (select 1 from pg_trigger t where t.tgname = 'po_invoice_due_auto' and t.tgrelid = 'public.po_invoice'::regclass and not t.tgisinternal) then v_bad := v_bad || ' po_invoice_due_auto trigger'; end if;
  if not exists (select 1 from pg_attribute where attrelid = 'public.po_invoice'::regclass and attname = 'due_date_manual' and attnotnull) then v_bad := v_bad || ' due_date_manual'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_discount_credit_body', 'qbo_discount_credit_sync') and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))) then v_bad := v_bad || ' grants'; end if;
  if v_bad <> '' then raise exception '⑥ landing check failed:%', v_bad; end if;
end $$;
