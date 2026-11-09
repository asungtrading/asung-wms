-- supabase/migrations/20261109103000_qbo_sync_4_3a_supplier_bill_jobs.sql — qbo-sync-4-3a: 공급처 Bill · VendorCredit 일감 · 몸 · 트리거 · 백필 (2026-11-09 · 지시서 ~/asung/prompts/qbo-sync-4-3.md · §0 이견 1 ~ 20 · 정본 so-module §108-a 판정 1115 ~ 1130 · qbo-integration §15-l)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied 20261109103000 --yes · supabase db push 금지 · ⚠️ po_invoice · po_charge 트리거 생성(SHARE ROW EXCLUSIVE) — 토론토 08:30 전 또는 17:00 뒤
-- 4-3a = A 일감 종류 · 짝 / B 몸 넷 / C 트리거 · 백필 / D unknown 열쇠 재료(lookup) + qbo_entity_upsert(PurchaseTaxRateList) — E(입고 보류 풀기 · CADJ) · F(은행 계좌 통화)는 4-3b(§0 이견 1)
-- 설계 요지(§0 답):
--   · 이견 2 since = created_at(토론토 날짜) ≥ qbo_send_since — invoice_date 가 아니다(AST261028 10-28 · 생성 11-02) · 이견 3 ims_kind 넷 supplier · po_invoice · po_credit · po_charge(qbo_txn pair 1:1)
--   · 이견 4 · 5 사건 넷 — 확정 · 복원(→ confirmed) = bill | vendor_credit queued(열린 bill_delete_manual 뒤면 blocked) · 취소 · 다시 열기(confirmed → cancelled | draft) = 안 나갔으면 skipped · sending | unknown 이면 bill_delete_manual blocked · 보냈으면 bill_delete_manual queued + qbo_txn.voided_at
--   · 이견 6 bill_delete_manual 은 queued(EF 는 모른다 · claim kinds 밖 · retry 거부 · Skip 으로 닫는다) · claim ② 는 bill · vendor_credit 의 부모 bill_delete_manual 이 skipped 면 푼다
--   · 이견 7 TaxLine 의 매입 세율 = 거울 detail.PurchaseTaxRateList(2b1 은 SalesTaxRateList 만) — 세금 > 0 이면 막음 · 세금 0 은 TotalTax 0 만 · qbo_entity_upsert 가 PurchaseTaxRateList 를 받아 둔다(EF PULL_FIELDS 는 4-4)
--   · 이견 8 ~ 13 몸 규칙 — TotalAmt = 줄 합 + 세금(diff ≠ 0 막음) · AccountBasedExpenseLineDetail(Amount + Description · 상호 없음) · goods 아닌 줄 · not payable 줄 막음 · duty = #134 + #125(M10) · Vendor 몸 DisplayName + CurrencyRef · APAccountRef 통화 = 문서 통화
--   · 이견 19 VendorCredit 은 자기 인보이스를 기다리지 않는다 · 이견 20 qbo_job_add(열쇠 창구)는 customer · item 그대로 — vendor 는 claim 의 needs 가 qbo_job_open_or_add 로
--   · 새 표 0 · 거래 표 FK 0(ims_id 다형) → 컷오버 날 지우는 순서 영향 없음 · 시퀀스 0 · 자동 재시도 없음(2a 원칙) · EF(4-4) · 화면 · cron 무변 — SEND_KINDS 19 에 새 kind 없음 → claim 은 못 집고 화면 Send 는 wrong_kind
-- 재발행 여덟(원본 = DB prosrc · pg_get_functiondef · 2026-11-09 · 끼운 줄만): qbo_job_open_or_add 47e7512f · qbo_job_claim f108aaa1 · qbo_job_done 79674624 · qbo_job_preview edfed63a · qbo_job_list 9f357ea4 · qbo_job_retry 263592d5 · qbo_job_doc ddc7cff5 · qbo_entity_upsert 11503e39
-- ⚠️ 공개 레포 — 손님 · 공급처 상호 없음 · UI 글자는 영어 · jsonb_build_object 안에 「--」 줄 주석을 두지 않는다
-- 검증 supabase/tests/qbo_sync_4_3a_check.sql(운영 메인 begin → rollback · 가짜 재료만) · 적용은 Caleb

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

-- ═══════════════ ⓪ 재발행 원본 가드 — 여덟의 DB prosrc md5 · 무변 둘 · 같은 이름 하나씩 · 아직 미적용 ═══════════════
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_open_or_add') is distinct from '47e7512fc6b1ef607951970a5be54cf0' then v_bad := v_bad || ' qbo_job_open_or_add'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_claim')       is distinct from 'f108aaa14d6236f830b5c698a56702f1' then v_bad := v_bad || ' qbo_job_claim'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_done')        is distinct from '79674624e98480ab0e0d1628e33a7ae6' then v_bad := v_bad || ' qbo_job_done'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_preview')     is distinct from 'edfed63ae62bdbdbba46aff23babe0d0' then v_bad := v_bad || ' qbo_job_preview'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_list')        is distinct from '9f357ea49f9740535a4b4a7298f606d4' then v_bad := v_bad || ' qbo_job_list'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_retry')       is distinct from '263592d5ff7e649afbb35897906170c4' then v_bad := v_bad || ' qbo_job_retry'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_doc')         is distinct from 'ddc7cff50886a3df67f28c814623e7c4' then v_bad := v_bad || ' qbo_job_doc'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_entity_upsert')   is distinct from '11503e39859c04deac82c791a825b6ef' then v_bad := v_bad || ' qbo_entity_upsert'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_skip')        is distinct from 'da0159236db83940236385b25ca803d2' then v_bad := v_bad || ' qbo_job_skip'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_fail')        is distinct from 'fdd230fa5b4de73c7345b32836ef8439' then v_bad := v_bad || ' qbo_job_fail'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_open_or_add', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_list', 'qbo_job_retry', 'qbo_job_doc', 'qbo_entity_upsert')) <> 8 then v_bad := v_bad || ' (a re-issued name is not unique)'; end if;
  if to_regprocedure('public.qbo_cost_charge_account(text)') is null or to_regprocedure('public.qbo_account_ref(text, text)') is null or to_regprocedure('public.ims_account_currency(uuid)') is null then v_bad := v_bad || ' (3-1 · 3-2a missing)'; end if;
  if to_regprocedure('public.qbo_bill_body(uuid, text)') is not null or exists (select 1 from pg_constraint where conname = 'qbo_job_kind_ck' and pg_get_constraintdef(oid) like '%vendor_credit%')
     or exists (select 1 from pg_trigger where tgname in ('po_invoice_qbo_job', 'po_charge_qbo_job')) then v_bad := v_bad || ' (4-3a already applied?)'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current bodies first — nothing was changed', v_bad; end if;
end $$;

-- ═══════════════ ① 꼴 셋 — since(IMS 에서 만든 날) · 21 자 · 매입 세율 ═══════════════
create function public.qbo_po_since_ok(p_created timestamptz) returns boolean
  language sql stable security definer set search_path = public, pg_temp
as $$
  select p_created is not null and nullif((select c.value from public.inv_config c where c.key = 'qbo_send_since'), '') is not null
         and (p_created at time zone 'America/Toronto')::date >= to_date((select c.value from public.inv_config c where c.key = 'qbo_send_since'), 'YYYY-MM-DD');
$$;
comment on function public.qbo_po_since_ok(timestamptz) is '[qbo-sync-4-3a · §0 이견 2] 공급처 문서의 since 가드 — 문서 날짜(invoice_date)가 아니라 IMS 에서 만든 시각(created_at · 토론토 날짜)이 inv_config qbo_send_since 이후면 true · 비면 늘 false(아무것도 안 쌓는다) · AST261028(10-28 · 11-02 생성)이 들어온다 · 컷 전 생성 0(§15-l ④)';

create function public.qbo_doc_number_21(p_number text) returns text
  language sql immutable
as $$ select left(btrim(coalesce(p_number, '')), 21); $$;
comment on function public.qbo_doc_number_21(text) is '[qbo-sync-4-3a · 판정 1130 · sandbox E-6] Bill · VendorCredit DocNumber = 앞 21 자(QuickBooks 상한 · 25 자 → 2050 「Max:21」) · 전체 번호는 PrivateNote · IMS 번호는 그대로';

create function public.qbo_purchase_tax(p_tax_rule_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_t public.ref_tax_rule%rowtype; v_code text; v_detail jsonb;
begin
  if p_tax_rule_id is null then raise exception 'A supplier document line has no tax rule — set the tax rule on the document and retry — nothing was sent'; end if;
  select * into v_t from public.ref_tax_rule t where t.id = p_tax_rule_id;
  if v_t.id is null then raise exception 'Tax rule % does not exist — nothing was sent', p_tax_rule_id; end if;
  select l.qbo_id into v_code from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = v_t.id::text;
  if v_code is null then raise exception 'Tax rule "%" has no QuickBooks tax code — link it under Settings → QuickBooks matching — nothing was sent', v_t.name; end if;
  select e.detail into v_detail from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'TaxCode' and e.qbo_id = v_code;
  return jsonb_build_object('tax_code', v_code, 'name', v_t.name, 'rate_pct', v_t.rate_pct,
                            'rate_ref', nullif(btrim(coalesce(v_detail->'PurchaseTaxRateList'->'TaxRateDetail'->0->'TaxRateRef'->>'value', '')), ''),
                            'rates', jsonb_array_length(coalesce(v_detail->'PurchaseTaxRateList'->'TaxRateDetail', '[]'::jsonb)));
end;
$$;
comment on function public.qbo_purchase_tax(uuid) is '[qbo-sync-4-3a · §0 이견 7] 매입 쪽 세금 짝 — IMS 세금 규칙 → qbo_link tax_rule 의 TaxCode(없으면 예외 · 사람 짝) · rate_ref = 거울 detail 의 PurchaseTaxRateList 첫 TaxRateRef(2b1 거울은 SalesTaxRateList 만이라 4-4 EF 가 PurchaseTaxRateList 를 당겨 Refresh 하기 전에는 null → 세금 > 0 인 Bill 은 몸이 막는다 · 세금 0 은 TaxLine 없이 나간다)';

-- ═══════════════ ② 몸 넷 — Vendor(1128) · Bill(1115 ~ 1118 · 1130) · VendorCredit(1121) · 비용 Bill(1129 · M10) ═══════════════
create function public.qbo_vendor_body(p_supplier_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_s public.supplier%rowtype; v_name text; v_dup text; v_cur text; v_warn text[] := '{}';
begin
  select * into v_s from public.supplier s where s.id = p_supplier_id;
  if v_s.id is null then raise exception 'No IMS supplier % — nothing was sent', p_supplier_id; end if;
  if not v_s.is_active then raise exception 'IMS supplier % is inactive — not sent to QuickBooks', v_s.name; end if;
  v_name := left(btrim(v_s.name), 100);
  if v_name = '' then raise exception 'IMS supplier % has an empty name — nothing was sent', p_supplier_id; end if;
  if length(btrim(v_s.name)) > 100 then v_warn := array_append(v_warn, 'name cut to 100 characters: ' || v_name); end if;
  select e.qbo_type || ' #' || e.qbo_id || ' ' || e.name into v_dup from public.qbo_entity e
    where e.realm_id = v_realm and e.qbo_type in ('Customer', 'Vendor') and e.gone_at is null and lower(btrim(e.name)) = lower(v_name) order by e.active desc, e.qbo_type, e.qbo_id limit 1;
  if v_dup is not null then raise exception 'QuickBooks already has a customer or supplier named "%" (%) — link the IMS supplier to it under Settings → QuickBooks matching, or rename one of them — nothing was sent', v_name, v_dup; end if;
  select c.code into v_cur from public.ref_currency c where c.id = v_s.currency_id;
  if v_cur is null then raise exception 'IMS supplier % has no currency — set it under Suppliers and retry — nothing was sent', v_s.name; end if;
  return jsonb_build_object('kind', 'vendor', 'ims_kind', 'supplier', 'ims_id', p_supplier_id::text, 'display_name', v_name,
                            'body', jsonb_build_object('DisplayName', v_name, 'CurrencyRef', jsonb_build_object('value', v_cur)), 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.qbo_vendor_body(uuid) is '[qbo-sync-4-3a · 판정 1128 · grant 0] QuickBooks Vendor 만들기 몸 — DisplayName(100 자) + CurrencyRef(공급처 통화)만 · A/P 는 싣지 않는다 · Customer · Vendor 거울과 이름이 같으면 실패(자동 개명 없음 · 사람 짝 · Employee 는 거울에 없어 실제 쓰기의 6240 이 남는다) · 비활성 · 통화 없음은 실패 · claim 의 needs(bill · vendor_credit 몸)가 qbo_job_open_or_add 로 세운다';

create function public.qbo_bill_body(p_invoice_id uuid, p_kind text default null) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_realm text := public.qbo_realm_of(); v_home text := coalesce(nullif(btrim((select c.value from public.inv_config c where c.key = 'base_currency')), ''), 'CAD');
  c_ginr constant text := '_1150040012_';
  v_i public.po_invoice%rowtype; v_m public.po_invoice_money%rowtype; v_s public.supplier%rowtype; v_for public.po_invoice%rowtype;
  v_kind text; v_ims_kind text; v_label text; v_cur text; v_vendor text; v_ap text; v_ap_cur text; v_ginr text; v_term text; v_doc text; v_due date; v_disc text; v_pos text; v_note text;
  v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_lines jsonb := '[]'::jsonb; v_tax_lines jsonb := '[]'::jsonb; v_tx jsonb; v_n int := 0; v_bad int; v_cut boolean := false; v_cents bigint;
  v_l record; v_g record;
begin
  select * into v_i from public.po_invoice i where i.id = p_invoice_id;
  if v_i.id is null then raise exception 'No IMS supplier document % — nothing was sent', p_invoice_id; end if;
  v_label := case v_i.doc_kind when 'credit' then 'Credit note' else 'Invoice' end;
  v_kind := case v_i.doc_kind when 'credit' then 'vendor_credit' else 'bill' end;
  v_ims_kind := case v_i.doc_kind when 'credit' then 'po_credit' else 'po_invoice' end;
  if p_kind is not null and p_kind <> v_kind then raise exception '% % is a supplier % — this job is a % — nothing was sent', v_label, v_i.invoice_number, v_i.doc_kind, p_kind; end if;
  if v_i.status <> 'confirmed' then raise exception '% % is % — only a confirmed supplier document is sent to QuickBooks — nothing was sent', v_label, v_i.invoice_number, v_i.status; end if;
  select * into v_m from public.po_invoice_money m where m.id = p_invoice_id;
  if coalesce(v_m.line_count, 0) = 0 then raise exception '% % has no lines — nothing was sent', v_label, v_i.invoice_number; end if;
  select count(*) into v_bad from public.po_invoice_line l where l.po_invoice_id = p_invoice_id and (l.line_kind <> 'goods' or not l.is_payable);
  if v_bad > 0 then raise exception '% % has % line(s) that are not payable goods lines — the QuickBooks account for charge, other or non-payable supplier lines is not decided yet — nothing was sent', v_label, v_i.invoice_number, v_bad; end if;
  if v_m.tax_rule_missing then raise exception '% % has a line without a tax rule — set the tax rule and retry — nothing was sent', v_label, v_i.invoice_number; end if;
  if v_m.diff <> 0 then raise exception '% %: the lines add up to % but the printed total is % — fix the lines or the total first — nothing was sent', v_label, v_i.invoice_number, v_m.computed_total, v_m.total_amount; end if;
  select * into v_s from public.supplier s where s.id = v_i.supplier_id;
  select l.qbo_id into v_vendor from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'supplier' and l.ims_id = v_s.id::text;
  if v_vendor is null then v_needs := v_needs || jsonb_build_object('kind', 'vendor', 'ims_id', v_s.id::text, 'name', v_s.name); end if;   -- 1128: Vendor 먼저(claim ④ 가 세운다)
  select c.code into v_cur from public.ref_currency c where c.id = v_i.currency_id;
  if v_cur is null then raise exception '% % has no currency — nothing was sent', v_label, v_i.invoice_number; end if;
  -- APAccountRef(4-2a E-1 · 반드시) — 공급처 A/P · 그 계정 통화 = 문서 통화(1091 은 공급처 통화만 본다 · §0 이견 13)
  v_ap := public.qbo_account_ref(v_s.account_payable_code, 'supplier payable account');
  select public.ims_account_currency(a.id) into v_ap_cur from public.ref_account a where a.code = v_s.account_payable_code;
  if v_ap_cur is distinct from v_cur then raise exception '% % is in % but the supplier payable account % is a % account — fix the supplier (Suppliers → payable account) and retry — nothing was sent', v_label, v_i.invoice_number, v_cur, v_s.account_payable_code, coalesce(v_ap_cur, '?'); end if;
  v_ginr := public.qbo_account_ref(c_ginr, 'goods invoiced not received');
  if v_cur <> v_home and (v_i.exchange_rate is null or v_i.exchange_rate <= 0) then raise exception '% % is in % but has no exchange rate — enter the rate on the document and retry (1118) — nothing was sent', v_label, v_i.invoice_number, v_cur; end if;
  if v_i.doc_kind = 'invoice' then
    if v_i.payment_term_id is not null then
      select l.qbo_id into v_term from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'payment_term' and l.ims_id = v_i.payment_term_id::text;
      if v_term is null then v_warn := array_append(v_warn, format('payment term "%s" has no QuickBooks match — SalesTermRef not sent', coalesce(v_i.payment_term_name, '?'))); end if;
    end if;
    v_due := coalesce(v_i.due_date, v_i.invoice_date);                                                     -- DueDate 반드시(sandbox: 빼면 QBO 가 TxnDate 로)
    if v_i.due_date is null then v_warn := array_append(v_warn, 'no due date on the invoice — invoice date sent as DueDate'); end if;
  end if;
  v_doc := public.qbo_doc_number_21(v_i.invoice_number);
  if length(btrim(v_i.invoice_number)) > 21 then v_cut := true; v_warn := array_append(v_warn, format('number "%s" cut to 21 characters for QuickBooks — the full number is in the private note (1130)', v_i.invoice_number)); end if;
  -- 줄 = goods 줄마다(1116) · Amount + Description(SKU × 수량 @ 단가 · PO · 크레딧 사유 · 상호 없음) · 계정 GINR(1115) · 세금 코드 = 줄 규칙(없으면 문서 규칙)
  for v_l in select l.qty_ea, l.unit_price, round(l.qty_ea * l.unit_price, 2) as amt, coalesce(l.tax_rule_id, v_i.tax_rule_id) as rule_id, l.credit_reason, pr.sku, p.po_number
               from public.po_invoice_line l join public.po_line pl on pl.id = l.po_line_id join public.po p on p.id = pl.po_id join public.product pr on pr.id = pl.product_id
              where l.po_invoice_id = p_invoice_id order by l.line_no loop
    v_tx := public.qbo_purchase_tax(v_l.rule_id);
    v_n := v_n + 1;
    v_lines := v_lines || jsonb_build_object('DetailType', 'AccountBasedExpenseLineDetail', 'LineNum', v_n, 'Amount', v_l.amt,
                 'Description', left(v_l.sku || ' × ' || trim_scale(v_l.qty_ea) || ' @ ' || trim_scale(v_l.unit_price) || ' · PO ' || v_l.po_number
                                     || case v_l.credit_reason when 'not_received' then ' · not received' when 'price_difference' then ' · price difference' else '' end, 4000),
                 'AccountBasedExpenseLineDetail', jsonb_build_object('AccountRef', jsonb_build_object('value', v_ginr), 'TaxCodeRef', jsonb_build_object('value', v_tx->>'tax_code')));
  end loop;
  -- 인보이스 할인 = 음수 줄 따로(1117) · 세율 묶음마다 하나(po_tax_group.discount_amount · 세금이 묶음별로 셈해진다) · 이름 = 할인 이름들
  select string_agg(d.name || ' ' || trim_scale(d.percent) || '%', ' · ' order by d.seq) into v_disc from public.po_invoice_discount d where d.po_invoice_id = p_invoice_id;
  for v_g in select g.tax_rule_id, g.discount_amount from public.po_tax_group g where g.doc_kind = 'invoice' and g.doc_id = p_invoice_id and g.discount_amount <> 0 order by g.tax_rule loop
    v_tx := public.qbo_purchase_tax(v_g.tax_rule_id);
    v_n := v_n + 1;
    v_lines := v_lines || jsonb_build_object('DetailType', 'AccountBasedExpenseLineDetail', 'LineNum', v_n, 'Amount', -v_g.discount_amount, 'Description', left('Discount ' || coalesce(v_disc, ''), 4000),
                 'AccountBasedExpenseLineDetail', jsonb_build_object('AccountRef', jsonb_build_object('value', v_ginr), 'TaxCodeRef', jsonb_build_object('value', v_tx->>'tax_code')));
  end loop;
  -- 세금(E-15: QBO 는 보낸 세금을 그대로 받는다) — 묶음마다 TaxLine(매입 세율 ref · 2b1 거울엔 없다 → 4-4 Refresh 뒤) · 세금 0 묶음은 TaxLine 없음
  for v_g in select g.tax_rule_id, g.tax_rule, g.rate_pct, g.taxable_amount, g.tax_amount from public.po_tax_group g where g.doc_kind = 'invoice' and g.doc_id = p_invoice_id and coalesce(g.tax_amount, 0) <> 0 order by g.tax_rule loop
    v_tx := public.qbo_purchase_tax(v_g.tax_rule_id);
    if v_tx->>'rate_ref' is null then raise exception 'QuickBooks tax code #% ("%") has no purchase tax rate on file — Settings → QuickBooks matching → Refresh list (tax codes), then retry — nothing was sent', v_tx->>'tax_code', v_g.tax_rule; end if;
    if (v_tx->>'rates')::int > 1 then v_warn := array_append(v_warn, format('tax code #%s has %s purchase rates — first rate #%s used', v_tx->>'tax_code', v_tx->>'rates', v_tx->>'rate_ref')); end if;
    v_tax_lines := v_tax_lines || jsonb_build_object('DetailType', 'TaxLineDetail', 'Amount', v_g.tax_amount,
                     'TaxLineDetail', jsonb_build_object('TaxRateRef', jsonb_build_object('value', v_tx->>'rate_ref'), 'PercentBased', true, 'TaxPercent', trim_scale(v_g.rate_pct), 'NetAmountTaxable', v_g.taxable_amount));
  end loop;
  select string_agg(distinct p.po_number, ', ' order by p.po_number) into v_pos from public.po_invoice_line l join public.po_line pl on pl.id = l.po_line_id join public.po p on p.id = pl.po_id where l.po_invoice_id = p_invoice_id;
  if v_i.doc_kind = 'credit' and v_i.credit_for_invoice_id is not null then select * into v_for from public.po_invoice f where f.id = v_i.credit_for_invoice_id; end if;
  v_note := 'IMS supplier ' || lower(v_label) || ' ' || v_i.invoice_number || coalesce(' · PO ' || v_pos, '') || coalesce(' · for invoice ' || v_for.invoice_number, '') || case when v_cut then ' · full number: ' || v_i.invoice_number else '' end;
  v_cents := round(v_m.computed_total * 100)::bigint;
  return jsonb_build_object('kind', v_kind, 'ims_kind', v_ims_kind, 'ims_id', p_invoice_id::text, 'name', v_i.invoice_number, 'doc_number', v_doc, 'supplier_id', v_s.id,
    'body', jsonb_strip_nulls(jsonb_build_object(
      'DocNumber', v_doc, 'TxnDate', to_char(v_i.invoice_date, 'YYYY-MM-DD'), 'DueDate', case when v_due is not null then to_char(v_due, 'YYYY-MM-DD') end,
      'VendorRef', case when v_vendor is not null then jsonb_build_object('value', v_vendor) end,
      'APAccountRef', jsonb_build_object('value', v_ap),
      'SalesTermRef', case when v_term is not null then jsonb_build_object('value', v_term) end,
      'CurrencyRef', jsonb_build_object('value', v_cur), 'ExchangeRate', case when v_cur <> v_home then trim_scale(v_i.exchange_rate) end,
      'PrivateNote', left(v_note, 4000), 'GlobalTaxCalculation', 'TaxExcluded', 'Line', v_lines,
      'TxnTaxDetail', jsonb_build_object('TotalTax', coalesce(v_m.tax_amount, 0)) || case when jsonb_array_length(v_tax_lines) > 0 then jsonb_build_object('TaxLine', v_tax_lines) else '{}'::jsonb end)),
    'needs', v_needs, 'warnings', to_jsonb(v_warn), 'line_count', jsonb_array_length(v_lines),
    'totals', jsonb_build_object('taxable', v_m.taxable_amount, 'tax', coalesce(v_m.tax_amount, 0), 'total', v_m.computed_total, 'currency', v_cur),
    'fingerprint', v_cents::text || '|' || v_cur,
    'lookup', jsonb_build_object('entity', case v_kind when 'bill' then 'Bill' else 'VendorCredit' end, 'doc_number', v_doc, 'vendor_ref', v_vendor, 'total_cents', v_cents, 'currency', v_cur));
end;
$$;
comment on function public.qbo_bill_body(uuid, text) is '[qbo-sync-4-3a · 판정 1115 ~ 1118 · 1121 · 1127 · 1130 · grant 0] 공급처 인보이스 → Bill · 크레딧(doc_kind credit) → VendorCredit 의 몸(p_kind 가 있으면 doc_kind 와 맞는지 검사) — confirmed 만 · 줄 = goods 줄마다 AccountBasedExpenseLineDetail(계정 GINR _1150040012_ · Amount · Description 「SKU × 수량 @ 단가 · PO」 · 상호 없음) · 할인 = 세율 묶음마다 음수 줄 · APAccountRef(공급처 A/P · 통화 = 문서 통화 아니면 막음) · DueDate(인보이스만 · 없으면 invoice_date + 경고) · USD ExchangeRate = po_invoice.exchange_rate(없으면 막음) · TxnTaxDetail = IMS 세금(묶음마다 TaxLine · 매입 세율 없으면 막음 · 세금 0 은 TotalTax 0 만) · DocNumber 21 자(전체는 PrivateNote) · 막는 것: goods 아닌 줄 · not payable 줄 · 세금 규칙 없음 · 줄 합 ≠ 찍힌 총액(diff) · Vendor 짝 없음 = needs(vendor) · 지문 「<총액 센트>|<통화>」 · lookup = 보내기 직전 가드 · unknown 열쇠 재료(DocNumber · VendorRef · 센트)';

create function public.qbo_vendor_credit_body(p_credit_id uuid) returns jsonb
  language sql stable security definer set search_path = public, pg_temp
as $$ select public.qbo_bill_body(p_credit_id, 'vendor_credit'); $$;
comment on function public.qbo_vendor_credit_body(uuid) is '[qbo-sync-4-3a · 판정 1121 · grant 0] 공급처 크레딧(po_invoice doc_kind credit) → VendorCredit — qbo_bill_body 와 같은 몸(차 A/P / 대 GINR · DueDate · SalesTermRef 없음) · 원가 사건(price_adjust → 원가 장 CADJ)은 원가 장 몫 · 자기 인보이스를 기다리지 않는다(§0 이견 19)';

create function public.qbo_charge_bill_body(p_charge_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_realm text := public.qbo_realm_of(); v_home text := coalesce(nullif(btrim((select c.value from public.inv_config c where c.key = 'base_currency')), ''), 'CAD');
  c_import_gst constant text := '_125_'; c_oos constant text := 'Out of Scope (Purchase)';
  v_c public.po_charge%rowtype; v_s public.supplier%rowtype; v_cur text; v_vendor text; v_ap text; v_ap_cur text; v_acct_code text; v_acct text; v_gst text; v_oos text; v_doc text; v_due date; v_refs text; v_desc text; v_note text; v_total numeric; v_tax numeric := 0; v_cents bigint;
  v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_lines jsonb := '[]'::jsonb; v_tax_lines jsonb := '[]'::jsonb; v_tx jsonb; v_n int := 0; v_cut boolean := false;
begin
  select * into v_c from public.po_charge c where c.id = p_charge_id;
  if v_c.id is null then raise exception 'No IMS charge % — nothing was sent', p_charge_id; end if;
  if v_c.status <> 'confirmed' then raise exception 'Charge % is % — only a confirmed charge is sent to QuickBooks — nothing was sent', v_c.charge_number, v_c.status; end if;
  v_acct_code := public.qbo_cost_charge_account(v_c.kind);
  if v_acct_code is null then raise exception 'Charge % is of kind % — it has no QuickBooks cost account (1089: freight, duty, brokerage only) — nothing was sent', v_c.charge_number, v_c.kind; end if;
  v_acct := public.qbo_account_ref(v_acct_code, v_c.kind || ' cost account');
  select * into v_s from public.supplier s where s.id = v_c.supplier_id;
  select l.qbo_id into v_vendor from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'supplier' and l.ims_id = v_s.id::text;
  if v_vendor is null then v_needs := v_needs || jsonb_build_object('kind', 'vendor', 'ims_id', v_s.id::text, 'name', v_s.name); end if;
  select c.code into v_cur from public.ref_currency c where c.id = v_c.currency_id;
  if v_cur is null then raise exception 'Charge % has no currency — nothing was sent', v_c.charge_number; end if;
  v_ap := public.qbo_account_ref(v_s.account_payable_code, 'supplier payable account');
  select public.ims_account_currency(a.id) into v_ap_cur from public.ref_account a where a.code = v_s.account_payable_code;
  if v_ap_cur is distinct from v_cur then raise exception 'Charge % is in % but the supplier payable account % is a % account — fix the supplier (Suppliers → payable account) and retry — nothing was sent', v_c.charge_number, v_cur, v_s.account_payable_code, coalesce(v_ap_cur, '?'); end if;
  if v_cur <> v_home and (v_c.exchange_rate is null or v_c.exchange_rate <= 0) then raise exception 'Charge % is in % but has no exchange rate — enter the rate on the charge and retry — nothing was sent', v_c.charge_number, v_cur; end if;
  v_tx := public.qbo_purchase_tax(v_c.tax_rule_id);
  select string_agg(distinct coalesce(p.po_number, t.transfer_number), ', ' order by coalesce(p.po_number, t.transfer_number)) into v_refs
    from public.po_charge_alloc a left join public.po p on p.id = a.po_id left join public.inv_transfer t on t.id = a.transfer_id where a.po_charge_id = p_charge_id;
  v_desc := initcap(v_c.kind) || ' ' || v_c.charge_number || coalesce(' · ' || v_refs, '');
  if v_c.kind = 'duty' then                                                                                  -- 1089 · M10: 관세 #134(세금 0) + 수입 GST #125 줄(Out of Scope) · TotalTax 0 · 「0 + 세금」 도 정상 꼴
    if v_c.total_amount <> 0 then
      v_n := v_n + 1;
      v_lines := v_lines || jsonb_build_object('DetailType', 'AccountBasedExpenseLineDetail', 'LineNum', v_n, 'Amount', v_c.total_amount, 'Description', left(v_desc, 4000),
                   'AccountBasedExpenseLineDetail', jsonb_build_object('AccountRef', jsonb_build_object('value', v_acct), 'TaxCodeRef', jsonb_build_object('value', v_tx->>'tax_code')));
    end if;
    if v_c.tax_amount <> 0 then
      select l.qbo_id into v_oos from public.ref_tax_rule t join public.qbo_link l on l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = t.id::text where t.name = c_oos order by t.is_active desc limit 1;
      if v_oos is null then raise exception 'Tax rule "%" has no QuickBooks tax code — the GST-on-import line needs it — link it under Settings → QuickBooks matching — nothing was sent', c_oos; end if;
      v_gst := public.qbo_account_ref(c_import_gst, 'GST paid on import');
      v_n := v_n + 1;
      v_lines := v_lines || jsonb_build_object('DetailType', 'AccountBasedExpenseLineDetail', 'LineNum', v_n, 'Amount', v_c.tax_amount, 'Description', left('GST on import · ' || v_desc, 4000),
                   'AccountBasedExpenseLineDetail', jsonb_build_object('AccountRef', jsonb_build_object('value', v_gst), 'TaxCodeRef', jsonb_build_object('value', v_oos)));
    end if;
    if coalesce((v_tx->>'rate_pct')::numeric, 0) > 0 then v_warn := array_append(v_warn, format('duty charge has tax rule "%s" — its tax is sent as a GST-on-import line, not as sales tax', v_tx->>'name')); end if;
    v_total := v_c.total_amount + v_c.tax_amount;
  else                                                                                                       -- 운임 #136 · 통관 #135: 계정 줄 + 그 charge 의 세금 코드 · TotalTax = IMS 세금
    v_n := 1;
    v_lines := jsonb_build_array(jsonb_build_object('DetailType', 'AccountBasedExpenseLineDetail', 'LineNum', 1, 'Amount', v_c.total_amount, 'Description', left(v_desc, 4000),
                 'AccountBasedExpenseLineDetail', jsonb_build_object('AccountRef', jsonb_build_object('value', v_acct), 'TaxCodeRef', jsonb_build_object('value', v_tx->>'tax_code'))));
    if v_c.tax_amount <> 0 then
      if v_tx->>'rate_ref' is null then raise exception 'QuickBooks tax code #% ("%") has no purchase tax rate on file — Settings → QuickBooks matching → Refresh list (tax codes), then retry — nothing was sent', v_tx->>'tax_code', v_tx->>'name'; end if;
      if (v_tx->>'rates')::int > 1 then v_warn := array_append(v_warn, format('tax code #%s has %s purchase rates — first rate #%s used', v_tx->>'tax_code', v_tx->>'rates', v_tx->>'rate_ref')); end if;
      v_tax_lines := jsonb_build_array(jsonb_build_object('DetailType', 'TaxLineDetail', 'Amount', v_c.tax_amount,
                       'TaxLineDetail', jsonb_build_object('TaxRateRef', jsonb_build_object('value', v_tx->>'rate_ref'), 'PercentBased', true, 'TaxPercent', trim_scale((v_tx->>'rate_pct')::numeric), 'NetAmountTaxable', v_c.total_amount)));
    end if;
    v_tax := v_c.tax_amount;
    v_total := v_c.total_amount + v_c.tax_amount;
  end if;
  if jsonb_array_length(v_lines) = 0 then raise exception 'Charge % has no amount and no tax — nothing to send', v_c.charge_number; end if;
  v_doc := public.qbo_doc_number_21(v_c.charge_number);
  if length(btrim(v_c.charge_number)) > 21 then v_cut := true; v_warn := array_append(v_warn, format('number "%s" cut to 21 characters for QuickBooks — the full number is in the private note (1130)', v_c.charge_number)); end if;
  v_due := coalesce(v_c.due_date, v_c.charge_date);
  if v_c.due_date is null then v_warn := array_append(v_warn, 'no due date on the charge — charge date sent as DueDate'); end if;
  v_note := 'IMS charge ' || v_c.charge_number || ' (' || v_c.kind || ')' || coalesce(' · ' || v_refs, '') || case when v_cut then ' · full number: ' || v_c.charge_number else '' end;
  v_cents := round(v_total * 100)::bigint;
  return jsonb_build_object('kind', 'bill', 'ims_kind', 'po_charge', 'ims_id', p_charge_id::text, 'name', v_c.charge_number, 'doc_number', v_doc, 'supplier_id', v_s.id,
    'body', jsonb_strip_nulls(jsonb_build_object(
      'DocNumber', v_doc, 'TxnDate', to_char(v_c.charge_date, 'YYYY-MM-DD'), 'DueDate', to_char(v_due, 'YYYY-MM-DD'),
      'VendorRef', case when v_vendor is not null then jsonb_build_object('value', v_vendor) end,
      'APAccountRef', jsonb_build_object('value', v_ap),
      'CurrencyRef', jsonb_build_object('value', v_cur), 'ExchangeRate', case when v_cur <> v_home then trim_scale(v_c.exchange_rate) end,
      'PrivateNote', left(v_note, 4000), 'GlobalTaxCalculation', 'TaxExcluded', 'Line', v_lines,
      'TxnTaxDetail', jsonb_build_object('TotalTax', v_tax) || case when jsonb_array_length(v_tax_lines) > 0 then jsonb_build_object('TaxLine', v_tax_lines) else '{}'::jsonb end)),
    'needs', v_needs, 'warnings', to_jsonb(v_warn), 'line_count', jsonb_array_length(v_lines),
    'totals', jsonb_build_object('taxable', v_c.total_amount, 'tax', v_tax, 'total', v_total, 'currency', v_cur),
    'fingerprint', v_cents::text || '|' || v_cur,
    'lookup', jsonb_build_object('entity', 'Bill', 'doc_number', v_doc, 'vendor_ref', v_vendor, 'total_cents', v_cents, 'currency', v_cur));
end;
$$;
comment on function public.qbo_charge_bill_body(uuid) is '[qbo-sync-4-3a · 판정 1129 · 1089 · M10 · grant 0] 비용 문서(po_charge) → Bill 의 몸 — confirmed 만(배분과 무관) · 계정 = qbo_cost_charge_account(kind)(#134 · #135 · #136 · other 는 막음) · duty = 관세 줄 + 수입 GST #125 줄(Out of Scope 코드 · TotalTax 0 · 「0 + 세금」 정상) · freight · brokerage = 계정 줄 + 그 charge 의 세금 코드 + TaxLine(매입 세율 없으면 막음) · APAccountRef(통화 검사) · DueDate(없으면 charge_date + 경고) · 설명 「Kind 번호 · PO/TR」 · 상호 없음 · 지문 「<총액 센트>|<통화>」';

-- ═══════════════ ③ 트리거 — po_invoice · po_charge 상태 변화 → 일감(확정 · 복원 · 취소 · 다시 열기 · 1126 · §0 이견 4 · 5) ═══════════════
create function public.qbo_job_on_po_doc_status() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_realm text; v_kind text; v_ims_kind text; v_label text; v_number text; v_by uuid; v_j public.qbo_job%rowtype; v_t public.qbo_txn%rowtype; v_del uuid; v_what text;
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
$$;
comment on function public.qbo_job_on_po_doc_status() is '[qbo-sync-4-3a · 판정 1126 · 1128 · §0 이견 2 · 4 · 5] po_invoice · po_charge AFTER UPDATE OF status — → confirmed(확정 · 복원): since(created_at) 뒤면 bill(invoice · charge) | vendor_credit(credit) queued · 열린 bill_delete_manual 이 있으면 그 뒤 blocked · confirmed → cancelled | draft(취소 · 다시 열기): 안 나갔으면 skipped · sending · unknown 이면 bill_delete_manual blocked · 보냈으면(qbo_txn) bill_delete_manual queued + qbo_txn.voided_at · Vendor 짝은 claim 의 needs 가 · 오류는 삼킨다(failed 일감으로 흔적)';
create trigger po_invoice_qbo_job after update of status on public.po_invoice for each row execute function public.qbo_job_on_po_doc_status();
create trigger po_charge_qbo_job  after update of status on public.po_charge  for each row execute function public.qbo_job_on_po_doc_status();

-- ═══════════════ ④ 백필 — 지금 confirmed 인 문서에 일감을 한 번(멱등) ═══════════════
create function public.qbo_po_backfill() returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton); v_inv int := 0; v_cr int := 0; v_chg int := 0;
begin
  if v_realm is null then return jsonb_build_object('skipped', 'QuickBooks is not connected', 'bills', 0, 'vendor_credits', 0, 'charge_bills', 0); end if;
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff)
  select v_realm, 'bill', 'po_invoice', i.id::text, 'queued', i.confirmed_by from public.po_invoice i
   where i.doc_kind = 'invoice' and i.status = 'confirmed' and public.qbo_po_since_ok(i.created_at)
     and not exists (select 1 from public.qbo_job j where j.realm_id = v_realm and j.ims_kind = 'po_invoice' and j.ims_id = i.id::text)
     and not exists (select 1 from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'po_invoice' and t.ims_id = i.id::text)
   order by i.confirmed_at, i.id;
  get diagnostics v_inv = row_count;
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff)
  select v_realm, 'vendor_credit', 'po_credit', i.id::text, 'queued', i.confirmed_by from public.po_invoice i
   where i.doc_kind = 'credit' and i.status = 'confirmed' and public.qbo_po_since_ok(i.created_at)
     and not exists (select 1 from public.qbo_job j where j.realm_id = v_realm and j.ims_kind = 'po_credit' and j.ims_id = i.id::text)
     and not exists (select 1 from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'po_credit' and t.ims_id = i.id::text)
   order by i.confirmed_at, i.id;
  get diagnostics v_cr = row_count;
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff)
  select v_realm, 'bill', 'po_charge', c.id::text, 'queued', c.confirmed_by from public.po_charge c
   where c.status = 'confirmed' and public.qbo_po_since_ok(c.created_at)
     and not exists (select 1 from public.qbo_job j where j.realm_id = v_realm and j.ims_kind = 'po_charge' and j.ims_id = c.id::text)
     and not exists (select 1 from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'po_charge' and t.ims_id = c.id::text)
   order by c.confirmed_at, c.id;
  get diagnostics v_chg = row_count;
  return jsonb_build_object('realm_id', v_realm, 'bills', v_inv, 'vendor_credits', v_cr, 'charge_bills', v_chg);
end;
$$;
comment on function public.qbo_po_backfill() is '[qbo-sync-4-3a · grant 0] 지금 confirmed 인 공급처 인보이스 · 크레딧 · 비용 문서에 일감을 한 번 쌓는다(since = created_at · 어떤 상태든 일감이 있거나 qbo_txn 이 있으면 건너뜀 → 두 번 돌려도 하나) · 마이그레이션이 한 번 부른다(11-09 실측: 인보이스 7 · 크레딧 0 · 비용 0)';

-- ═══════════════ ⑤ CHECK — kind 23 · ims_kind 14 · 짝 명시 가지(ELSE 함정 · §15-l ④) · qbo_txn Bill · VendorCredit ═══════════════
alter table public.qbo_job
  drop constraint qbo_job_kind_ck,
  add  constraint qbo_job_kind_ck check (kind in ('customer', 'item', 'invoice', 'credit', 'invoice_void', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day', 'vendor', 'bill', 'vendor_credit', 'bill_delete_manual')),
  drop constraint qbo_job_ims_kind_ck,
  add  constraint qbo_job_ims_kind_ck check (ims_kind in ('customer', 'product', 'charge', 'invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund', 'cost_sheet', 'supplier', 'po_invoice', 'po_credit', 'po_charge')),
  drop constraint qbo_job_pair_ck,
  add  constraint qbo_job_pair_ck check (ims_kind = case kind when 'customer' then 'customer' when 'invoice' then 'invoice' when 'invoice_void' then 'invoice' when 'credit' then 'credit' when 'credit_void' then 'credit'
                                                                                        when 'payment' then 'payment' when 'payment_void' then 'payment' when 'credit_apply' then 'credit_alloc' when 'credit_apply_void' then 'credit_alloc'
                                                                                        when 'opening_credit' then 'opening_alloc' when 'opening_credit_void' then 'opening_alloc' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc'
                                                                                        when 'refund' then 'refund' when 'refund_void' then 'refund' when 'refund_apply' then 'refund' when 'refund_apply_void' then 'refund'
                                                                                        when 'cost_day' then 'cost_sheet' when 'vendor' then 'supplier' when 'vendor_credit' then 'po_credit' else ims_kind end
                                                and (kind <> 'item' or ims_kind in ('product', 'charge'))
                                                and (kind <> 'bill' or ims_kind in ('po_invoice', 'po_charge'))
                                                and (kind <> 'bill_delete_manual' or ims_kind in ('po_invoice', 'po_credit', 'po_charge')));
alter table public.qbo_txn
  drop constraint qbo_txn_kind_ck,
  add  constraint qbo_txn_kind_ck check (ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_credit', 'opening_alloc', 'refund', 'refund_apply', 'cost_sheet', 'po_invoice', 'po_credit', 'po_charge')),
  drop constraint qbo_txn_type_ck,
  add  constraint qbo_txn_type_ck check (qbo_type in ('Invoice', 'CreditMemo', 'Payment', 'Purchase', 'JournalEntry', 'Bill', 'VendorCredit')),
  drop constraint qbo_txn_pair_ck,
  add  constraint qbo_txn_pair_ck check (qbo_type = case ims_kind when 'invoice' then 'Invoice' when 'credit' then 'CreditMemo' when 'opening_credit' then 'CreditMemo' when 'refund' then 'Purchase' when 'cost_sheet' then 'JournalEntry'
                                                                  when 'po_invoice' then 'Bill' when 'po_charge' then 'Bill' when 'po_credit' then 'VendorCredit' else 'Payment' end);

-- ═══════════════ ⑥ 재발행 여덟 — DB prosrc 그대로 + 끼운 줄(머리 · 서명 · definer · search_path 그대로 · ACL 그대로) ═══════════════

-- ═══ qbo_entity_upsert — TaxCode detail 에 PurchaseTaxRateList(이견 7) · 병합 ═══
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
         coalesce((r->>'Active')::boolean, true), r->>'SyncToken', now(), null, case when p_type = 'TaxCode' and (r ? 'SalesTaxRateList' or r ? 'PurchaseTaxRateList') then coalesce(r->'SalesTaxRateList', '{}'::jsonb) || case when r ? 'PurchaseTaxRateList' then jsonb_build_object('PurchaseTaxRateList', r->'PurchaseTaxRateList') else '{}'::jsonb end end
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

-- ═══ qbo_job_open_or_add — kind vendor(1128) ═══
CREATE OR REPLACE FUNCTION public.qbo_job_open_or_add(p_kind text, p_ims_id text, p_by uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_realm text := public.qbo_realm_of(); v_b jsonb; v_ims_kind text; v_j public.qbo_job%rowtype; v_parent jsonb; v_state text := 'queued'; v_blocked uuid;
begin
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
$function$
;

-- ═══ qbo_job_doc — po_invoice · po_credit · po_charge · supplier 가지 ═══
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
    else jsonb_build_object('doc_number', p_ims_id, 'name', p_ims_id, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', null) end;
$function$
;

-- ═══ qbo_job_claim — kinds 22 · ② bill_delete_manual skipped 풀기 · 몸 가지 셋(두 곳) ═══
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
  if not (v_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day', 'vendor', 'bill', 'vendor_credit']) or coalesce(array_length(v_kinds, 1), 0) = 0 then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void, refund, refund_void, refund_apply, refund_apply_void, cost_day, vendor, bill, vendor_credit (got %)', v_kinds; end if;   -- 4-3a kinds 22(bill_delete_manual 은 보내는 kind 가 아니다 · 1126)   -- 2e-3-2-1 kinds 18 · 3-2b cost_day 19
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

-- ═══ qbo_job_done — vendor(Vendor 거울 + qbo_link supplier) · bill · vendor_credit(qbo_txn Bill · VendorCredit · 지문 대조) ═══
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
  if v_j.kind in ('refund', 'refund_void', 'refund_apply', 'refund_apply_void') and v_link_err is null then   -- 2e-3-2-1 이견 15: 보낸 뒤 상태 맞추기 — 보내는 동안 void 됐으면 void 일감을 쌓는다 · Purchase 가 서면 apply 는 ② 가 푼다
    begin v_sync := public.qbo_refund_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  return jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'state', case when v_link_err is null then 'sent' else 'failed' end, 'reconcile', v_sync, 'qbo_id', btrim(p_qbo_id), 'qbo_name', btrim(p_qbo_name), 'linked', v_link_err is null, 'link_error', v_link_err, 'unblocked', v_unblocked, 'mismatch', v_mismatch);
end;
$function$
;

-- ═══ qbo_job_preview — 몸 가지 셋 ═══
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

-- ═══ qbo_job_list — kinds 23(bill_delete_manual 포함) · 라벨 넷 · qbo_txn 잇기 셋 ═══
CREATE OR REPLACE FUNCTION public.qbo_job_list(p_state text DEFAULT NULL::text, p_kinds text[] DEFAULT NULL::text[], p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_q text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if p_state is not null and p_state not in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped', 'open') then raise exception 'state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open (got %)', p_state; end if;
  if p_kinds is not null and (not (p_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day', 'vendor', 'bill', 'vendor_credit', 'bill_delete_manual']) or coalesce(array_length(p_kinds, 1), 0) = 0) then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void, refund, refund_void, refund_apply, refund_apply_void, cost_day, vendor, bill, vendor_credit, bill_delete_manual (got %)', p_kinds; end if;   -- 2e-3-2-1 kinds 18 · 3-2b cost_day 19
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
      left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund', 'cost_sheet', 'po_invoice', 'po_credit', 'po_charge')   -- 2e-3-2-1 + refund · 3-2b + cost_sheet(JournalEntry)
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

-- ═══ qbo_job_retry — bill_delete_manual 거부 · skipped bill · vendor_credit 은 confirmed 일 때만 ═══
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

-- ═══════════════ ⑦ grant · 주석 · 백필 한 번 ═══════════════
revoke all on function public.qbo_po_since_ok(timestamptz), public.qbo_doc_number_21(text), public.qbo_purchase_tax(uuid), public.qbo_vendor_body(uuid), public.qbo_bill_body(uuid, text), public.qbo_vendor_credit_body(uuid), public.qbo_charge_bill_body(uuid),
  public.qbo_job_on_po_doc_status(), public.qbo_po_backfill() from public, anon, authenticated, service_role;   -- 속 함수 아홉 · grant 0(claim · preview · 트리거 · 마이그레이션이 definer 로 부른다) · 재발행 여덟은 create or replace 라 ACL 그대로

do $$
begin
  execute format('comment on table public.qbo_job is %L', coalesce(obj_description('public.qbo_job'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-4-3a: 공급처 쪽 kind vendor(ims_kind supplier · 1128) · bill(po_invoice 1115 ~ 1118 · po_charge 1129) · vendor_credit(po_credit · 1121) · bill_delete_manual(사람이 QBO 에서 지운 뒤 Skip · EF 는 보내지 않는다 · 1126) · 트리거 qbo_job_on_po_doc_status(po_invoice · po_charge AFTER UPDATE OF status) · since = created_at · 지문 「<총액 센트>|<통화>」 · unknown 열쇠 재료 lookup(DocNumber · VendorRef · 센트) · EF 는 4-4');
  execute format('comment on table public.qbo_txn is %L', coalesce(obj_description('public.qbo_txn'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-4-3a: ims_kind po_invoice · po_charge ↔ Bill · po_credit ↔ VendorCredit(doc_number = DocNumber 21 자 · total_amt = 문서 통화 TotalAmt · fingerprint = 지문) · 취소 · 다시 열기면 voided_at(IMS 가 더는 그 장을 인정하지 않는다 · 삭제는 북키퍼 손)');
  execute format('comment on table public.qbo_entity is %L', coalesce(obj_description('public.qbo_entity'::regclass, 'pg_class'), '') || ' · [4-3a] TaxCode detail 에 PurchaseTaxRateList 도(EF pull 이 그 칸을 당기면 · 4-4) — Bill TaxLine 의 매입 세율 ref · 옛 키는 지우지 않는다(병합)');
end $$;

do $$
declare v jsonb;
begin
  v := public.qbo_po_backfill();
  raise notice '4-3a backfill: %', v;
end $$;
