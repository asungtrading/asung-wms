-- supabase/migrations/20261110040718_qbo_sync_4_7b_discount_credit_needs.sql — qbo-sync-4-7b(DB 몫 · 판정 1150 「가」): 할인 결제의 Send 한 번이 할인 VendorCredit 을 같은 보내기에서 먼저 보낸다
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied 20261110040718 --yes · supabase db push 금지
-- 무엇: 재발행 셋(원본 = DB prosrc · pg_get_functiondef · 2026-11-10 UTC · 시그니처 · ACL · definer · search_path 무변 · create or replace)
--   ① qbo_bill_payment_body(원본 md5 944d71f29e4e8456d38ade05afd9fbed) — 안 간 할인 VendorCredit 을 wait_job 이 아니라 needs 로(붙임마다 · 전부) · Bill 이 아직 안 갔으면 지금처럼 Bill 만 wait_job(VC 는 needs 에 싣지 않는다 · Bill 은 대신 보내지 않는다 960) · 경고 한 줄(「…is created in QuickBooks first, in the same send」)
--   ② qbo_job_open_or_add(원본 md5 57a4762cbcff42bda95539de213fc4bf) — kind vendor_credit 가지: 열린 po_discount 일감을 찾아 돌려주기만(existing true) · 만들지 않는다 · 없으면 raise(출구 = 결제 일감 Retry) · customer · item · vendor 가지 무변
--   ③ qbo_job_claim(원본 md5 e6b9bc07fa9ca94de911477dea4c94bd) — ② 풀기에 한 가지: 할인 VC 일감(vendor_credit + po_discount)이 skipped 면 그것을 기다리던 bill_payment 를 queued 로 → 다음 claim 에서 몸이 raise(「…was skipped — retry that job first, or enter this payment in QuickBooks by hand and press Skip on this job」) → failed + 출구 글
--        옛: 사람이 할인 VC 일감을 Skip 하면 결제 일감이 skipped 부모에 영구 blocked(② 는 sent 만 풀었다 · 몸의 raise 는 queued 로 잡혀야 닿는다 · qbo-pay-fix-1 과 같은 꼴) — 운영에 걸린 일감 0(2026-11-10 UTC 실측) · 데이터 고침 없음
-- 잠금: 함수 재발행(카탈로그)뿐 — 표 잠금 · 새 표 · 칸 · CHECK · 트리거 · 시퀀스 · cron 0 · 화면 무변 · EF 는 qbo-sync-4-7b 가 같이 나간다(isNeedJob · VC Balance 가드)
-- ⚠️ EF 옛 판(4-5b)과의 순서: 이 마이그레이션만 적용돼도 옛 EF 는 할인 VC need 를 대신 보내지 않고(isNeedKind) 결제는 1112 행 안전문에서 failed — 쓰기 0 · EF 배포 뒤에 1150 이 선다
-- ⚠️ 공개 레포 — 상호 없음 · UI 글자는 영어
-- 검증 supabase/tests/qbo_sync_4_7b_check.sql(운영 메인 begin → rollback · 가짜 재료만 · claim 은 일감 id 로만) · 적용은 Caleb

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
  v_dn jsonb := '[]'::jsonb;
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
        -- 4-7b 판정 1150: 안 간 할인 VendorCredit 은 wait_job 이 아니라 needs — 결제의 Send 한 번이 같은 보내기에서 VC 를 먼저 보낸다(일감은 이미 서 있다 · qbo_job_open_or_add 가 찾아 돌려준다)
        v_dn := v_dn || jsonb_build_object('kind', 'vendor_credit', 'ims_id', a.alloc_id::text, 'name', 'Discount credit D' || to_char(v_p.paid_on, 'YYMMDD') || '-' || btrim(a.number) || ' · ' || trim_scale(a.discount_amount)::text || ' ' || v_cur);
        v_warn := array_append(v_warn, format('the early-payment discount credit of invoice %s is created in QuickBooks first, in the same send (1150)', a.number));
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
    'body', v_body, 'needs', v_needs || case when v_wait is null then v_dn else '[]'::jsonb end, 'wait_job', v_wait, 'wait_invoice', v_wait_doc, 'wait_reason', case when v_wait is not null then coalesce(v_wait_why, format('waiting for bill %s to reach QuickBooks first — send it too', v_wait_doc)) end,
    'warnings', to_jsonb(v_warn), 'line_count', jsonb_array_length(v_lines),
    'totals', jsonb_build_object('amount', v_p.amount, 'applied', v_applied, 'discount', v_disc, 'currency', v_cur, 'exchange_rate', case when v_cur <> v_home then v_p.exchange_rate end),
    'fingerprint', public.qbo_bill_payment_fingerprint(v_p.id), 'check_lines', v_checks,
    'lookup', jsonb_build_object('entity', 'BillPayment', 'vendor_ref', v_vendor, 'txn_date', to_char(v_p.paid_on, 'YYYY-MM-DD'), 'total_amt', v_p.amount, 'total_cents', round(v_p.amount * 100)::bigint, 'currency', v_cur,
                                 'private_note', 'IMS supplier payment ' || v_p.id::text, 'account_ref', v_acct, 'pay_type', v_pay->>'PayType'));
end;
$function$;

CREATE OR REPLACE FUNCTION public.qbo_job_open_or_add(p_kind text, p_ims_id text, p_by uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_realm text := public.qbo_realm_of(); v_b jsonb; v_ims_kind text; v_j public.qbo_job%rowtype; v_parent jsonb; v_state text := 'queued'; v_blocked uuid;
begin
  -- 4-7b 판정 1150: 결제 몸의 needs 가 가리키는 할인 VendorCredit 일감(ims_kind po_discount · ims_id = po_payment_alloc.id) — 열린 일감을 찾아 돌려주기만 한다 · 만들지 않는다(일감은 표 트리거의 qbo_discount_credit_sync 가 세운다)
  if p_kind = 'vendor_credit' then
    if nullif(btrim(coalesce(p_ims_id, '')), '') is null then raise exception 'ims_id is required — nothing was saved'; end if;
    select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'vendor_credit' and j.ims_kind = 'po_discount' and j.ims_id = p_ims_id and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
    if v_j.id is null then raise exception 'The early-payment discount vendor credit has no open QuickBooks job — press Retry on the supplier payment job and it is queued — nothing was saved'; end if;
    return to_jsonb(v_j) || jsonb_build_object('existing', true);
  end if;
  if p_kind not in ('customer', 'item', 'vendor') then raise exception 'kind must be customer, item or vendor (invoice, credit and bill jobs are queued by issuing or confirming) — nothing was saved'; end if;   -- 4-3a vendor
  if nullif(btrim(coalesce(p_ims_id, '')), '') is null then raise exception 'ims_id is required — nothing was saved'; end if;
  if p_kind = 'customer' then
    begin v_b := public.qbo_customer_body(p_ims_id::uuid); exception when invalid_text_representation then raise exception 'ims_id must be a customer id (got %) — nothing was saved', p_ims_id; end;
    if exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = p_ims_id) then raise exception 'IMS customer is already linked to a QuickBooks customer — nothing was saved'; end if;
  elsif p_kind = 'vendor' then                                                                             -- 4-3a 1128: 공급처 Vendor — claim 의 needs 가 세운다(bill · vendor_credit 몸의 needs) · 이름 충돌은 몸이 거부(자동 개명 없음)
    begin v_b := public.qbo_vendor_body(p_ims_id::uuid); exception when invalid_text_representation then raise exception 'ims_id must be a supplier id (got %) — nothing was saved', p_ims_id; end;
    if exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'supplier' and l.ims_id = p_ims_id) then raise exception 'IMS supplier is already linked to a QuickBooks vendor — nothing was saved'; end if;
  else
    v_b := public.qbo_item_body(p_ims_id);
  end if;
  v_ims_kind := v_b->>'ims_kind';
  select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = p_kind and j.ims_kind = v_ims_kind and j.ims_id = p_ims_id and j.state not in ('sent', 'skipped');
  if v_j.id is not null then return to_jsonb(v_j) || jsonb_build_object('existing', true, 'preview', v_b); end if;
  if v_b->>'parent_customer_id' is not null then                                                           -- 부모 손님 먼저(깊이 하나 · customer_parent_guard) · 이 일감은 blocked
    v_parent := public.qbo_job_open_or_add('customer', v_b->>'parent_customer_id', p_by);
    v_blocked := (v_parent->>'id')::uuid; v_state := 'blocked';
  end if;
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, warning, by_staff)
  values (v_realm, p_kind, v_ims_kind, p_ims_id, v_state, v_blocked, nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')), ' · '), ''), p_by)
  returning * into v_j;
  return to_jsonb(v_j) || jsonb_build_object('existing', false, 'preview', v_b, 'parent_job', v_parent);
end;
$function$;

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
  update public.qbo_job j set state = 'queued', next_at = now() from public.qbo_job p where j.realm_id = v_realm and j.state = 'blocked' and p.id = j.blocked_by and (p.state = 'sent' or (j.kind = 'cost_day' and p.state = 'skipped') or (j.kind in ('bill', 'vendor_credit') and p.kind = 'bill_delete_manual' and p.state = 'skipped') or (j.kind = 'bill_payment' and p.kind = 'vendor_credit' and p.ims_kind = 'po_discount' and p.state = 'skipped'));   -- 4-3a: 복원된 문서의 새 Bill 은 옛 Bill 을 QBO 에서 손으로 지운 뒤(bill_delete_manual skipped) 나간다(1126)   -- 3-2b ⬜3: 하루 원가 장은 앞 장 skip(void)도 푼다 — 보낸 몫 0 이라 뒤 장 차액이 그 몫을 담는다(1092)
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
$function$;

-- 착지 — 재발행 셋의 prosrc md5 · 같은 이름 하나씩 · 실행권 그대로(body · open_or_add = postgres 만 · claim = service_role)
do $land$
declare v_bad text := ''; v_r record;
begin
  for v_r in select * from (values ('qbo_bill_payment_body', 'a109cb3b12572f1b8e530a885e949639'), ('qbo_job_open_or_add', '29a2a12c43412e15a61a4d120463e661'), ('qbo_job_claim', '9ab3a4d8fc92fa8fcc00cff9ccf77dcb')) as x(name, md5) loop
    if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = v_r.name) <> 1 then v_bad := v_bad || ' count:' || v_r.name; end if;
    if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = v_r.name) is distinct from v_r.md5 then v_bad := v_bad || ' md5:' || v_r.name; end if;
  end loop;
  if has_function_privilege('authenticated', 'public.qbo_bill_payment_body(uuid)', 'execute') or has_function_privilege('authenticated', 'public.qbo_job_open_or_add(text, text, uuid)', 'execute') or has_function_privilege('service_role', 'public.qbo_job_open_or_add(text, text, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.qbo_job_claim(integer, text[], uuid[])', 'execute') or not has_function_privilege('service_role', 'public.qbo_job_claim(integer, text[], uuid[])', 'execute') then v_bad := v_bad || ' acl'; end if;
  if v_bad <> '' then raise exception 'qbo-sync-4-7b landing check failed:%', v_bad; end if;
end $land$;
