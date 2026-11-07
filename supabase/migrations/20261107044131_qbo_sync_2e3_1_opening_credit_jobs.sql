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
-- qbo-sync-2e-3-1 — 이월 받아 둔 돈(so_payment method opening)을 컷 뒤 인보이스에 쓴 것을 QuickBooks 로(DB): CHECK · 몸 넷 · 상태 맞추기 · 트리거 가지 · 백필 · requeue · link_set · ims_rows · credit_apply 1013 · claim · preview · doc · list · retry · done 재발행 (판정 786 · 998′ · 1009 · 1010 · 1013 · 1016 · 1017 · 2026-11-07 · 지시서 ~/asung/prompts/qbo-sync-2e-3-1.md · §0 이견 1 ~ 18 Caleb 답)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '2s'" -f 로 적용 + supabase migration repair --status applied <이 파일 번호> · ⚠️ db push 쓰지 않는다 · 2e-2-1(20261103200000) · 1d-1(20261105184613) 뒤
-- ⭐ 786 · 341 과 부딪치지 않는다 — 돈 자체(이월 줄 · 6,628.40 · 계정 _1150040009_)는 그대로 보내지 않는다 · 보내는 것은 「컷 뒤 IMS 가 그 돈을 인보이스에 쓴 일」(붙임 한 줄) 뿐이다 (998′ 「이월 받아 둔 돈 쓰기도 같은 길」 · 1009 「두 장 길은 이월 돈만」)
-- 무엇:
--   ⓪ 재발행 원본 가드 — 재발행 열둘(claim · done · preview · doc · list · retry · payment_requeue · link_set · ims_rows · credit_apply_body · job_on_payment_alloc)과 무변이어야 하는 결제 넷의 DB prosrc md5 가 마지막 정의 파일과 다르면 멈춘다
--   ① 표(⚠️ 파일 끝 · ⑤ 뒤 — 잠금 구간을 짧게): qbo_job kind(+ opening_credit · opening_credit_void · opening_apply · opening_apply_void) · ims_kind(+ opening_alloc · ims_id = so_payment_alloc.id) · pair / qbo_txn ims_kind(+ opening_credit ↔ CreditMemo · opening_alloc ↔ Payment · 이견 3: 한 붙임에 장이 둘이라 ims_kind 둘)
--   ② 몸 넷: qbo_opening_credit_body(붙임) = 「쓰기」 CreditMemo(DocNumber OC-<인보이스>-<n> · 이견 5 · CustomerRef = 돈의 주인 so_payment.customer_id · 이견 4 · 매장과 다르면 failed · 빠져나오는 길 = QBO 하위 손님(qbo_entity.parent_id) → retry · Line 한 줄 = qbo_link charge acct:<결제 계정> Item · 이견 7 · 세금 = Out of Scope(Sale) 짝 + TaxLine 0 · 2c 꼴 · 이견 6 · PrivateNote 「IMS opening credit used <uuid>」 · 인보이스 뒤에 선다 · 이견 8)
--      qbo_opening_credit_void_body(2c void 꼴 · Id · SyncToken) · qbo_opening_apply_body(붙임) = 0 원 Payment(Line 둘 Invoice + CreditMemo · 2e-2 꼴 · 기다림 = 자기 CreditMemo → 인보이스 → 같은 인보이스의 열린 void 셋 · 1013 · PrivateNote 「IMS opening credit applied <uuid>」 · check_lines · lookup) · qbo_opening_apply_void_body(sparse)
--   ③ qbo_opening_alloc_sync(붙임 · 사람) — 상태표(이견 12): 보낸 적 없음 · 활성 → opening_credit queued + opening_apply blocked_by 그것 / 떼임 → 열린 것 skipped · sending · unknown 이면 void 를 그 뒤에 / CreditMemo 서 있음 · Payment 아직 → apply queued · 떼임 → credit_void queued(apply 가 나가는 중이면 apply_void → credit_void 차례) / 둘 다 서 있음 · 떼임 → apply_void queued → credit_void blocked_by / QBO 쪽 void 됨 → 열린 것 skipped
--      qbo_job_on_payment_alloc() 재발행(이견 1) — 트리거 so_payment_alloc_qbo 는 그대로 · opening 이면 이 sync · 아니면 qbo_payment_sync(무변) · 새 트리거 없음 = so_payment_alloc 잠금 0
--   ④ qbo_opening_apply_backfill()(적용 때 한 번 · 활성 · opening · 인보이스 sale ∧ since · 일감 · 거래 없음) · qbo_opening_credit_requeue(계정 · 사람)(이견 7: acct: 짝이 서면 그 계정의 failed opening_credit → queued) · 재발행: qbo_payment_requeue(+ 이월 돈 붙임 루프 · 1016 꼴) · qbo_link_set(+ charge acct: 가지 · 1039 꼴) · qbo_ims_rows(+ 이월 결제 계정 행) · qbo_credit_apply_body(1013 루프에 opening_apply_void)
--   ⑤ 재발행(DB 바이트 + 가지): claim(kinds 14 · 몸 넷) · preview · doc(opening_alloc) · list(kinds 14 · ims_name · ⚠️ txn join 을 kind 로 갈라 잇는다 — 한 붙임에 txn 둘) · retry(규칙 넷 × 2) · done(opening_credit → qbo_txn CreditMemo · TotalAmt = 금액 ∧ TotalTax 0 대조 · opening_apply → qbo_txn opening_alloc · 0 대조 · void 둘 → voided_at · 끝에 sync)
--   ⑥ grant · comment · 착지 · 백필 NOTICE
-- 안 하는 것: EF(2e-3-1b — SEND_KINDS 14 · entityKeyOf 명시 가지 · void 길 둘 · 가드 · unknown 풀기 접두 · cron 62 kinds 8) · 환불(2e-3-2) · 화면 · qbo_link 에 Item 5624 짝 넣기(Caleb 이 Settings → QuickBooks matching 에서) · 이월 줄 자체 보내기(786)
-- 거래 표 FK: 0(ims_id 다형) · 검증: supabase/tests/qbo_sync_2e3_1_check.sql(-v mig 시험 · 적용 뒤 -v mig 없이)

-- ═══ ⓪ 재발행 원본 가드 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_claim')            is distinct from '9c7890b8833396d63568e056965d8a3c' then v_bad := v_bad || ' qbo_job_claim'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_done')             is distinct from 'fc2d42c04bd2c0b9689dae6111cd3a55' then v_bad := v_bad || ' qbo_job_done'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_preview')          is distinct from '76ed9a1f02e1df3314b55ac4dc534230' then v_bad := v_bad || ' qbo_job_preview'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_doc')              is distinct from '53c1547da5e6bdc6e95a062593989aa2' then v_bad := v_bad || ' qbo_job_doc'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_list')             is distinct from '54f25d9e68ced97302c67a1f04d355a7' then v_bad := v_bad || ' qbo_job_list'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_retry')            is distinct from '69a07a5ac531bc908d4f6d695fef48d7' then v_bad := v_bad || ' qbo_job_retry'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_requeue')      is distinct from '2c7734148ab65950ec8869a2b9ece9b0' then v_bad := v_bad || ' qbo_payment_requeue'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_link_set')             is distinct from 'd32494ebd40e31bce431fff872bba2cc' then v_bad := v_bad || ' qbo_link_set'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_ims_rows')             is distinct from '74628b928cffa621da8f36ff70ca1861' then v_bad := v_bad || ' qbo_ims_rows'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_credit_apply_body')    is distinct from '08b17e793b3ec596b8b077de0ae719bc' then v_bad := v_bad || ' qbo_credit_apply_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_on_payment_alloc') is distinct from '004ec605b0da85b39d068a6964593bdf' then v_bad := v_bad || ' qbo_job_on_payment_alloc'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_body')         is distinct from 'e1aea51849844cc5898351daaa3ef533' then v_bad := v_bad || ' qbo_payment_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_void_body')    is distinct from '4ddb45cd728222d7b676d1e0bd169a54' then v_bad := v_bad || ' qbo_payment_void_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_sync')         is distinct from '9efb5d9f6007048692d13cd00623c4b8' then v_bad := v_bad || ' qbo_payment_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_fingerprint')  is distinct from 'd6da0342942ef68345b9432e0e84da23' then v_bad := v_bad || ' qbo_payment_fingerprint'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_credit_alloc_sync')    is distinct from '44419d3b499a33299e010e33671b26fa' then v_bad := v_bad || ' qbo_credit_alloc_sync'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_done', 'qbo_job_claim', 'qbo_payment_requeue', 'qbo_link_set', 'qbo_ims_rows', 'qbo_credit_apply_body', 'qbo_job_on_payment_alloc')) <> 7 then v_bad := v_bad || ' overloads'; end if;
  if to_regprocedure('public.so_invoice_store(uuid)') is null or to_regprocedure('public.qbo_payment_requeue_one(uuid, uuid, text)') is null or to_regprocedure('public.qbo_send_since_ok(date)') is null then v_bad := v_bad || ' prerequisites(cr-store-1a · 1d-1 · 2b1)'; end if;
  if (select count(*) from pg_trigger where tgname = 'so_payment_alloc_qbo' and tgrelid = 'public.so_payment_alloc'::regclass and tgdeferrable and tginitdeferred) <> 1 then v_bad := v_bad || ' trigger so_payment_alloc_qbo'; end if;
  if exists (select 1 from pg_constraint where conname = 'qbo_job_kind_ck' and pg_get_constraintdef(oid) like '%opening_credit%') then v_bad := v_bad || ' already-applied'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current bodies first — nothing was changed', v_bad; end if;
end $$;

-- ═══ ② 몸 넷 · 번호 ═══
create function public.qbo_opening_doc_number(p_alloc_id uuid) returns text
  language sql stable security definer set search_path = public, pg_temp
as $$
  select 'OC-' || i.invoice_number || '-' || (select count(*) from public.so_payment_alloc a2 join public.so_payment p2 on p2.id = a2.payment_id
                                                 where a2.invoice_id = a.invoice_id and p2.method = 'opening' and (a2.created_at, a2.id) <= (a.created_at, a.id))::text
    from public.so_payment_alloc a join public.so_invoice i on i.id = a.invoice_id where a.id = p_alloc_id;
$$;
comment on function public.qbo_opening_doc_number(uuid) is 'qbo-sync-2e-3-1 이견 5(속 · grant 0): 「쓰기」 CreditMemo 의 DocNumber = OC-<인보이스 번호>-<n> · n = 그 인보이스에 생긴 이월 돈 붙임의 순번(void 된 것도 센다 — void 는 QBO 에 DocNumber 를 남기므로 재붙임은 새 번호) · 21 자 넘으면 몸이 자르고 경고';

create function public.qbo_opening_credit_body(p_alloc_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_a public.so_payment_alloc%rowtype; v_p public.so_payment%rowtype; v_i public.so_invoice%rowtype; v_cust public.customer%rowtype; v_is uuid; v_cust_ref text; v_store_ref text; v_store_parent text;
        v_item text; v_rule public.ref_tax_rule%rowtype; v_tax_ref text; v_detail jsonb; v_rate_ref text; v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_doc text; v_label text; v_date date; v_desc text;
        v_ti public.qbo_txn%rowtype; v_j public.qbo_job%rowtype; v_wait uuid; v_wait_doc text; v_wait_reason text; v_line jsonb; v_tax_line jsonb;
begin
  select * into v_a from public.so_payment_alloc a where a.id = p_alloc_id;
  if v_a.id is null then raise exception 'No IMS payment application % — nothing was sent', p_alloc_id; end if;
  select * into v_p from public.so_payment p where p.id = v_a.payment_id;
  if v_p.kind <> 'payment' or v_p.method <> 'opening' then raise exception 'Payment % is not money carried over from the previous system — it goes to QuickBooks as a Payment, not as an opening credit — nothing was sent', coalesce(v_p.reference, left(v_p.id::text, 8)); end if;
  select * into v_i from public.so_invoice i where i.id = v_a.invoice_id;
  v_doc := public.qbo_opening_doc_number(v_a.id); v_label := v_doc || ' → ' || v_i.invoice_number;
  if v_a.voided_at is not null then raise exception 'Opening credit % was detached — nothing to send (a void job takes care of QuickBooks) — nothing was sent', v_label; end if;
  if v_p.status <> 'active' then raise exception 'The carried-over money behind opening credit % is voided — nothing was sent', v_label; end if;
  if nullif(btrim(coalesce(v_p.currency_code, '')), '') is null then raise exception 'Opening credit % has no currency code — nothing was sent', v_label; end if;
  if length(v_doc) > 21 then v_warn := array_append(v_warn, format('document number %s is longer than 21 characters — sent as %s', v_doc, left(v_doc, 21))); v_doc := left(v_doc, 21); end if;
  -- 이견 4: CustomerRef = 돈의 주인(so_payment.customer_id · 786 손님 브랜치) · 짝 없으면 needs · 인보이스 매장(so_invoice_store)과 다르면 failed — 빠져나오는 길 = QBO 에서 매장이 그 손님의 하위 손님(qbo_entity.parent_id · 482 꼴)이면 경고만 · 아니면 글대로 묶고 Retry
  select * into v_cust from public.customer c where c.id = v_p.customer_id;
  v_is := public.so_invoice_store(v_i.id);
  if v_is is null then raise exception 'Invoice % has no store on record — nothing was sent', v_i.invoice_number; end if;
  select l.qbo_id into v_cust_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_p.customer_id::text;
  if v_cust_ref is null then
    v_needs := v_needs || jsonb_build_object('kind', 'customer', 'ims_id', v_p.customer_id::text, 'name', v_cust.name);
  elsif v_is <> v_p.customer_id then
    select l.qbo_id into v_store_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_is::text;
    select e.parent_id into v_store_parent from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'Customer' and e.qbo_id = v_store_ref;
    if v_store_parent is null or v_store_parent <> v_cust_ref then
      raise exception 'Opening credit % belongs to customer % but invoice % is for store % — the opening credit belongs to another customer than the invoice store: detach it, or in QuickBooks make the store a sub-customer (bill with parent) of that customer, refresh the customer list under Settings → QuickBooks matching, then retry — nothing was sent',
        v_label, v_cust.name, v_i.invoice_number, (select c.name from public.customer c where c.id = v_is);
    end if;
    v_warn := array_append(v_warn, format('invoice %s is for store %s, a QuickBooks sub-customer of %s — the credit memo is written on the parent customer', v_i.invoice_number, (select c.name from public.customer c where c.id = v_is), v_cust.name));
  end if;
  -- 이견 7: Item = qbo_link charge 「acct:<결제 계정>」(951 · 961 과 같은 열쇠 · Settings → QuickBooks matching) · 없으면 failed · 짝이 서면 qbo_link_set → qbo_opening_credit_requeue 가 되살린다
  if nullif(btrim(coalesce(v_p.account_code, '')), '') is null then raise exception 'The carried-over money behind opening credit % has no account — nothing was sent', v_label; end if;
  select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'acct:' || v_p.account_code;
  if v_item is null then raise exception 'Opening credits on account % have no QuickBooks item — link account item "acct:%" to the Customer Credit item under Settings → QuickBooks matching; this opening credit then goes by itself — nothing was sent', v_p.account_code, v_p.account_code; end if;
  -- 이견 6: 세금 = Out of Scope(Sale) 규칙의 짝(TaxCodeRef) + TaxLine 0(2c 꼴 · TaxRateRef 는 거울 detail)
  select * into v_rule from public.ref_tax_rule r where r.direction = 'sale' and r.name ilike 'Out of Scope%' order by r.is_active desc, r.name limit 1;
  if v_rule.id is null then raise exception 'IMS has no "Out of Scope" sale tax rule — add it under Settings → Reference Book first — nothing was sent'; end if;
  select l.qbo_id into v_tax_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = v_rule.id::text;
  if v_tax_ref is null then raise exception 'Tax rule "%" has no QuickBooks tax code — link it under Settings → QuickBooks matching — nothing was sent', v_rule.name; end if;
  select e.detail into v_detail from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'TaxCode' and e.qbo_id = v_tax_ref;
  v_rate_ref := nullif(btrim(coalesce(v_detail->'TaxRateDetail'->0->'TaxRateRef'->>'value', '')), '');
  if v_rate_ref is null then raise exception 'QuickBooks tax code #% ("%") has no tax rate on file — Settings → QuickBooks matching → Refresh list (tax codes), then retry — nothing was sent', v_tax_ref, v_rule.name; end if;
  -- 이견 8: 인보이스 뒤에 선다(인보이스가 skipped · 취소되면 CreditMemo 만 서서 손님 잔액을 줄인다) · 이월 · since 전 · 일감 없음 · skipped 는 failed 글
  select * into v_ti from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = v_i.id::text and t.voided_at is null;
  if v_ti.id is null then
    if v_i.kind = 'opening' then raise exception 'Invoice % was carried over from the previous system and has no QuickBooks match yet — match it under Settings → QuickBooks → Opening invoices; this opening credit then goes by itself — nothing was sent', v_i.invoice_number; end if;
    if not public.qbo_send_since_ok(v_i.issued_on) then raise exception 'Invoice % was issued before the QuickBooks start date and has no QuickBooks match — match it under Settings → QuickBooks → Opening invoices — nothing was sent', v_i.invoice_number; end if;
    select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'invoice' and j.ims_kind = 'invoice' and j.ims_id = v_i.id::text order by j.created_at desc, j.id desc limit 1;
    if v_j.id is null then raise exception 'Invoice % has no QuickBooks job — send the invoice first — nothing was sent', v_i.invoice_number; end if;
    if v_j.state = 'skipped' then raise exception 'Invoice % was skipped — skip this opening credit too, or retry the invoice first — nothing was sent', v_i.invoice_number; end if;
    if v_j.state = 'sent' then raise exception 'Invoice % job is sent but no QuickBooks transaction is on file — check qbo_txn by hand — nothing was sent', v_i.invoice_number; end if;
    v_wait := v_j.id; v_wait_doc := v_i.invoice_number; v_wait_reason := format('waiting for invoice %s to reach QuickBooks first', v_i.invoice_number);
  end if;
  v_date := (v_a.created_at at time zone 'America/Toronto')::date;                                                                     -- 1017 꼴: 붙인 날(토론토)
  v_desc := 'Credit on account applied to invoice ' || v_i.invoice_number;
  v_line := jsonb_build_object('DetailType', 'SalesItemLineDetail', 'LineNum', 1, 'Amount', v_a.amount, 'Description', v_desc,
              'SalesItemLineDetail', jsonb_build_object('ItemRef', jsonb_build_object('value', v_item), 'Qty', 1, 'UnitPrice', trim_scale(v_a.amount), 'TaxCodeRef', jsonb_build_object('value', v_tax_ref)));
  v_tax_line := jsonb_build_object('DetailType', 'TaxLineDetail', 'Amount', 0, 'TaxLineDetail', jsonb_build_object('TaxRateRef', jsonb_build_object('value', v_rate_ref), 'PercentBased', true, 'TaxPercent', 0, 'NetAmountTaxable', v_a.amount));
  return jsonb_build_object('kind', 'opening_credit', 'ims_kind', 'opening_alloc', 'ims_id', v_a.id::text, 'name', v_label, 'doc_number', v_doc, 'customer_id', v_p.customer_id,
    'body', jsonb_strip_nulls(jsonb_build_object(
      'DocNumber', v_doc, 'TxnDate', to_char(v_date, 'YYYY-MM-DD'),
      'CustomerRef', case when v_cust_ref is not null then jsonb_build_object('value', v_cust_ref) end,
      'CurrencyRef', jsonb_build_object('value', v_p.currency_code),
      'PrivateNote', 'IMS opening credit used ' || v_a.id::text, 'CustomerMemo', jsonb_build_object('value', v_desc),
      'GlobalTaxCalculation', 'TaxExcluded', 'Line', jsonb_build_array(v_line),
      'TxnTaxDetail', jsonb_build_object('TotalTax', 0, 'TaxLine', jsonb_build_array(v_tax_line)))),
    'needs', v_needs, 'wait_job', v_wait, 'wait_invoice', v_wait_doc, 'wait_reason', v_wait_reason, 'warnings', to_jsonb(v_warn), 'line_count', 1,
    'totals', jsonb_build_object('taxable', v_a.amount, 'tax', 0, 'total', v_a.amount, 'invoice_number', v_i.invoice_number, 'doc_number', v_doc), 'fingerprint', null);
end;
$$;
comment on function public.qbo_opening_credit_body(uuid) is 'qbo-sync-2e-3-1 판정 998′ · 1009 · 이견 4 ~ 8(속 · grant 0 · claim · preview 가 부른다): 이월 받아 둔 돈의 붙임 → 「쓰기」 CreditMemo 만들기 몸 — DocNumber OC-<인보이스>-<n> · TxnDate 붙인 날(토론토) · CustomerRef = 돈의 주인(so_payment.customer_id · 짝 없으면 needs · 인보이스 매장과 다르면 failed · QBO 하위 손님이면 경고만) · Line 한 줄 = qbo_link charge acct:<결제 계정> Item · Qty 1 · 금액 = 붙임 금액 · TaxCodeRef = Out of Scope(Sale) 짝 · TaxExcluded · TxnTaxDetail 0 · PrivateNote 「IMS opening credit used <uuid>」 · CustomerMemo 「Credit on account applied to invoice N」 · 인보이스가 QBO 에 선 뒤(wait_job) · 이월 · since 전 · 일감 없음 · skipped · Item 짝 없음 · 떼인 붙임은 예외(failed) · 돌려주는 것 = { body · needs · wait_job · wait_invoice · wait_reason · warnings · totals · line_count 1 · fingerprint null } · unknown 열쇠는 DocNumber(2c 꼴)';

create function public.qbo_opening_credit_void_body(p_alloc_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_t public.qbo_txn%rowtype; v_label text;
begin
  v_label := public.qbo_job_doc('opening_alloc', p_alloc_id::text)->>'doc_number';
  if v_label is null then raise exception 'No IMS payment application % — nothing was sent', p_alloc_id; end if;
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'opening_credit' and t.ims_id = p_alloc_id::text;
  if v_t.id is null then raise exception 'Opening credit % was never sent to QuickBooks — nothing to void', v_label; end if;
  if v_t.voided_at is not null then raise exception 'Opening credit % (QuickBooks credit memo #%) is already voided — nothing was sent', v_label, v_t.qbo_id; end if;
  return jsonb_build_object('kind', 'opening_credit_void', 'ims_kind', 'opening_alloc', 'ims_id', p_alloc_id::text, 'name', v_label, 'doc_number', v_t.doc_number, 'qbo_id', v_t.qbo_id,
    'body', jsonb_strip_nulls(jsonb_build_object('Id', v_t.qbo_id, 'SyncToken', v_t.sync_token)), 'needs', '[]'::jsonb,
    'warnings', case when v_t.sync_token is null then '["no SyncToken on file — the sender reads the credit memo first"]'::jsonb else '[]'::jsonb end);
end;
$$;
comment on function public.qbo_opening_credit_void_body(uuid) is 'qbo-sync-2e-3-1 이견 2 · 12(속 · grant 0): 「쓰기」 CreditMemo void 몸 — qbo_txn opening_credit 의 Id · SyncToken(2c credit_void 꼴 · EF 는 creditmemo?operation=void) · 보낸 적 없음 · 이미 void 면 예외(failed) · 순서 = 0 원 Payment void 뒤(sync 가 blocked_by 로 세운다)';

create function public.qbo_opening_apply_body(p_alloc_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_a public.so_payment_alloc%rowtype; v_p public.so_payment%rowtype; v_i public.so_invoice%rowtype; v_cust public.customer%rowtype; v_is uuid; v_cust_ref text; v_store_ref text; v_store_parent text;
        v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_doc text; v_label text; v_date date; v_ti public.qbo_txn%rowtype; v_tc public.qbo_txn%rowtype; v_j public.qbo_job%rowtype;
        v_wait uuid; v_wait_doc text; v_wait_reason text; v_body jsonb; v_lines jsonb := '[]'::jsonb; v_checks jsonb := '[]'::jsonb; r record;
begin
  select * into v_a from public.so_payment_alloc a where a.id = p_alloc_id;
  if v_a.id is null then raise exception 'No IMS payment application % — nothing was sent', p_alloc_id; end if;
  select * into v_p from public.so_payment p where p.id = v_a.payment_id;
  if v_p.kind <> 'payment' or v_p.method <> 'opening' then raise exception 'Payment % is not money carried over from the previous system — it goes to QuickBooks as a Payment, not as an opening credit — nothing was sent', coalesce(v_p.reference, left(v_p.id::text, 8)); end if;
  select * into v_i from public.so_invoice i where i.id = v_a.invoice_id;
  v_doc := left(public.qbo_opening_doc_number(v_a.id), 21); v_label := v_doc || ' → ' || v_i.invoice_number;
  if v_a.voided_at is not null then raise exception 'Opening credit % was detached — nothing to send (a void job takes care of QuickBooks) — nothing was sent', v_label; end if;
  if nullif(btrim(coalesce(v_p.currency_code, '')), '') is null then raise exception 'Opening credit % has no currency code — nothing was sent', v_label; end if;
  -- 이견 4: CustomerRef = 돈의 주인(CreditMemo 와 같은 손님이어야 QBO 가 둘을 잇는다) · 매장 다름은 credit 몸과 같은 울타리
  select * into v_cust from public.customer c where c.id = v_p.customer_id;
  v_is := public.so_invoice_store(v_i.id);
  if v_is is null then raise exception 'Invoice % has no store on record — nothing was sent', v_i.invoice_number; end if;
  select l.qbo_id into v_cust_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_p.customer_id::text;
  if v_cust_ref is null then
    v_needs := v_needs || jsonb_build_object('kind', 'customer', 'ims_id', v_p.customer_id::text, 'name', v_cust.name);
  elsif v_is <> v_p.customer_id then
    select l.qbo_id into v_store_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_is::text;
    select e.parent_id into v_store_parent from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'Customer' and e.qbo_id = v_store_ref;
    if v_store_parent is null or v_store_parent <> v_cust_ref then
      raise exception 'Opening credit % belongs to customer % but invoice % is for store % — the opening credit belongs to another customer than the invoice store: detach it, or in QuickBooks make the store a sub-customer (bill with parent) of that customer, refresh the customer list under Settings → QuickBooks matching, then retry — nothing was sent',
        v_label, v_cust.name, v_i.invoice_number, (select c.name from public.customer c where c.id = v_is);
    end if;
    v_warn := array_append(v_warn, format('invoice %s is for store %s, a QuickBooks sub-customer of %s', v_i.invoice_number, (select c.name from public.customer c where c.id = v_is), v_cust.name));
  end if;
  -- 이견 2 · 8: 자기 CreditMemo(opening_credit 일감) 먼저 · 인보이스 다음 · 첫 미발송 하나에 wait(claim ② 가 sent 때 풀면 다음 바퀴에 다시 본다)
  select * into v_tc from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'opening_credit' and t.ims_id = v_a.id::text and t.voided_at is null;
  if v_tc.id is null then
    select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_credit' and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text order by j.created_at desc, j.id desc limit 1;
    if v_j.id is null then raise exception 'Opening credit % has no QuickBooks job for its credit memo — check qbo_job by hand — nothing was sent', v_label; end if;
    if v_j.state = 'skipped' then raise exception 'The credit memo of opening credit % was skipped — skip this one too, or retry that job first — nothing was sent', v_label; end if;
    if v_j.state = 'sent' then raise exception 'The credit memo job of opening credit % is sent but no QuickBooks transaction is on file — check qbo_txn by hand — nothing was sent', v_label; end if;
    v_wait := v_j.id; v_wait_doc := v_doc; v_wait_reason := format('waiting for credit memo %s to reach QuickBooks first', v_doc);
  end if;
  select * into v_ti from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = v_i.id::text and t.voided_at is null;
  if v_ti.id is null then
    if v_i.kind = 'opening' then raise exception 'Invoice % was carried over from the previous system and has no QuickBooks match yet — match it under Settings → QuickBooks → Opening invoices; this opening credit then goes by itself — nothing was sent', v_i.invoice_number; end if;
    if not public.qbo_send_since_ok(v_i.issued_on) then raise exception 'Invoice % was issued before the QuickBooks start date and has no QuickBooks match — match it under Settings → QuickBooks → Opening invoices — nothing was sent', v_i.invoice_number; end if;
    select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'invoice' and j.ims_kind = 'invoice' and j.ims_id = v_i.id::text order by j.created_at desc, j.id desc limit 1;
    if v_j.id is null then raise exception 'Invoice % has no QuickBooks job — send the invoice first — nothing was sent', v_i.invoice_number; end if;
    if v_j.state = 'skipped' then raise exception 'Invoice % was skipped — skip this opening credit too, or retry the invoice first — nothing was sent', v_i.invoice_number; end if;
    if v_j.state = 'sent' then raise exception 'Invoice % job is sent but no QuickBooks transaction is on file — check qbo_txn by hand — nothing was sent', v_i.invoice_number; end if;
    if v_wait is null then v_wait := v_j.id; v_wait_doc := v_i.invoice_number; v_wait_reason := format('waiting for invoice %s to reach QuickBooks first', v_i.invoice_number); end if;
  end if;
  -- 1013 · 이견 8: 새 0 원 Payment 만 같은 인보이스의 열린 void 일감 뒤에 선다(payment_void · credit_apply_void · 다른 붙임의 opening_apply_void) — EF 가드(Invoice Balance ≥ a)가 void 뒤에 통과하도록
  if v_wait is null then
    for r in select j.id, j.kind, j.state,
                    case j.kind when 'payment_void' then coalesce((select nullif(btrim(coalesce(p.reference, '')), '') from public.so_payment p where p.id::text = j.ims_id), 'payment ' || left(j.ims_id, 8))
                                when 'credit_apply_void' then (select c2.credit_number from public.so_credit_alloc a2 join public.so_credit c2 on c2.id = a2.credit_id where a2.id::text = j.ims_id)
                                else (select public.qbo_opening_doc_number(a3.id) from public.so_payment_alloc a3 where a3.id::text = j.ims_id) end as doc
               from public.qbo_job j
              where j.realm_id = v_realm and j.state not in ('sent', 'skipped')
                and ((j.kind = 'payment_void' and exists (select 1 from public.so_payment_alloc pa where pa.payment_id::text = j.ims_id and pa.invoice_id = v_i.id))
                  or (j.kind = 'credit_apply_void' and exists (select 1 from public.so_credit_alloc a2 where a2.id::text = j.ims_id and a2.invoice_id = v_i.id))
                  or (j.kind = 'opening_apply_void' and j.ims_id <> v_a.id::text and exists (select 1 from public.so_payment_alloc a3 where a3.id::text = j.ims_id and a3.invoice_id = v_i.id)))
              order by j.created_at, j.id limit 1 loop
      v_wait := r.id; v_wait_doc := r.doc;
      v_wait_reason := format('waiting for the void of %s %s on invoice %s to reach QuickBooks first (that job is %s%s)', case r.kind when 'payment_void' then 'payment' when 'credit_apply_void' then 'credit note' else 'opening credit' end, r.doc, v_i.invoice_number, r.state,
                              case when r.state = 'failed' then ' — retry or skip it first' when r.state = 'unknown' then ' — check QuickBooks and retry it with a note' else '' end);
    end loop;
  end if;
  v_date := (v_a.created_at at time zone 'America/Toronto')::date;
  if v_wait is null then
    v_lines := jsonb_build_array(jsonb_build_object('Amount', v_a.amount, 'LinkedTxn', jsonb_build_array(jsonb_build_object('TxnId', v_ti.qbo_id, 'TxnType', 'Invoice'))),
                                 jsonb_build_object('Amount', v_a.amount, 'LinkedTxn', jsonb_build_array(jsonb_build_object('TxnId', v_tc.qbo_id, 'TxnType', 'CreditMemo'))));   -- C-5″ 순: Invoice · CreditMemo
    v_checks := jsonb_build_array(jsonb_build_object('txn_type', 'Invoice', 'invoice_number', v_i.invoice_number, 'qbo_invoice_id', v_ti.qbo_id, 'amount', v_a.amount),
                                  jsonb_build_object('txn_type', 'CreditMemo', 'credit_number', v_doc, 'qbo_creditmemo_id', v_tc.qbo_id, 'amount', v_a.amount));   -- 2e-2-1b 가드 열쇠 그대로(Invoice Balance ≥ a ∧ CreditMemo RemainingCredit ≥ a)
  end if;
  v_body := jsonb_strip_nulls(jsonb_build_object(
    'CustomerRef', case when v_cust_ref is null then null else jsonb_build_object('value', v_cust_ref) end,
    'TxnDate', v_date, 'TotalAmt', 0, 'CurrencyRef', jsonb_build_object('value', v_p.currency_code),
    'PrivateNote', 'IMS opening credit applied ' || v_a.id::text, 'Line', v_lines));                                                       -- PaymentMethodRef · DepositToAccountRef · PaymentRefNum 없음(C-5″)
  return jsonb_build_object('kind', 'opening_apply', 'ims_kind', 'opening_alloc', 'ims_id', v_a.id::text, 'name', v_label, 'doc_number', v_label, 'customer_id', v_p.customer_id,
    'body', v_body, 'needs', v_needs, 'wait_job', v_wait, 'wait_invoice', v_wait_doc, 'wait_reason', v_wait_reason, 'warnings', to_jsonb(v_warn), 'line_count', jsonb_array_length(v_lines),
    'totals', jsonb_build_object('amount', 0, 'applied', v_a.amount, 'unapplied', 0, 'credit_number', v_doc, 'invoice_number', v_i.invoice_number),
    'fingerprint', null, 'check_lines', v_checks,
    'lookup', jsonb_build_object('customer_ref', v_cust_ref, 'txn_date', v_date, 'total_amt', 0, 'private_note', 'IMS opening credit applied ' || v_a.id::text));
end;
$$;
comment on function public.qbo_opening_apply_body(uuid) is 'qbo-sync-2e-3-1 판정 998′ · 1011 ~ 1013 · 이견 2 · 4 · 8(속 · grant 0 · claim · preview 가 부른다): 이월 받아 둔 돈의 붙임 → QBO 0 원 Payment 만들기 몸 — CustomerRef = 돈의 주인 짝(needs · 매장 다름은 credit 몸과 같은 울타리) · TxnDate 붙인 날(토론토) · TotalAmt 0 · CurrencyRef · 수단 · 입금 계좌 · PaymentRefNum 없음 · PrivateNote 「IMS opening credit applied <uuid>」 · Line = Invoice + CreditMemo(qbo_txn invoice · opening_credit 의 Id · 같은 금액) · 기다림 = 자기 CreditMemo → 인보이스 → 같은 인보이스의 열린 void(payment_void · credit_apply_void · opening_apply_void) 차례로 wait_job + wait_reason · 돌려주는 것 = { body · needs · wait_job · wait_invoice · wait_reason · warnings · totals · check_lines[{txn_type Invoice|CreditMemo …}] · lookup(unknown 열쇠) · fingerprint null }';

create function public.qbo_opening_apply_void_body(p_alloc_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_t public.qbo_txn%rowtype; v_label text;
begin
  v_label := public.qbo_job_doc('opening_alloc', p_alloc_id::text)->>'doc_number';
  if v_label is null then raise exception 'No IMS payment application % — nothing was sent', p_alloc_id; end if;
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'opening_alloc' and t.ims_id = p_alloc_id::text;
  if v_t.id is null then raise exception 'Opening credit application % was never sent to QuickBooks — nothing to void', v_label; end if;
  if v_t.voided_at is not null then raise exception 'Opening credit application % (QuickBooks payment #%) is already voided — nothing was sent', v_label, v_t.qbo_id; end if;
  return jsonb_build_object('kind', 'opening_apply_void', 'ims_kind', 'opening_alloc', 'ims_id', p_alloc_id::text, 'name', v_label, 'doc_number', v_t.doc_number, 'qbo_id', v_t.qbo_id,
    'body', jsonb_strip_nulls(jsonb_build_object('Id', v_t.qbo_id, 'SyncToken', v_t.sync_token, 'sparse', true)), 'needs', '[]'::jsonb,
    'warnings', case when v_t.sync_token is null then '["no SyncToken on file — the sender reads the payment first"]'::jsonb else '[]'::jsonb end,
    'lookup', jsonb_build_object('qbo_id', v_t.qbo_id, 'private_note', 'IMS opening credit applied ' || p_alloc_id::text));
end;
$$;
comment on function public.qbo_opening_apply_void_body(uuid) is 'qbo-sync-2e-3-1 판정 1011 · 이견 12(속 · grant 0): 0 원 Payment void 몸 — qbo_txn opening_alloc 의 Id · SyncToken · sparse true(EF 는 payment?operation=update&include=void · 2e-2 credit_apply_void 와 같은 길) · 보낸 적 없음 · 이미 void 면 예외(failed) · 순서 = CreditMemo void 보다 먼저';

-- ═══ ③ 상태 맞추기(트리거 가지 · done 의 reconcile · 백필 · requeue 가 부른다) · 트리거 함수 재발행(이견 1) ═══
create function public.qbo_opening_alloc_sync(p_alloc_id uuid, p_by uuid) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton); v_a public.so_payment_alloc%rowtype; v_p public.so_payment%rowtype; v_active boolean;
        v_tc public.qbo_txn%rowtype; v_ta public.qbo_txn%rowtype; v_cj public.qbo_job%rowtype; v_cvj public.qbo_job%rowtype; v_aj public.qbo_job%rowtype; v_avj public.qbo_job%rowtype; v_id uuid; v_act text := 'none';
begin
  if v_realm is null then return jsonb_build_object('action', 'no_connection'); end if;
  select * into v_a from public.so_payment_alloc a where a.id = p_alloc_id;
  if v_a.id is null then return jsonb_build_object('action', 'not_applicable'); end if;
  select * into v_p from public.so_payment p where p.id = v_a.payment_id;
  if v_p.id is null or v_p.kind <> 'payment' or v_p.method <> 'opening' then return jsonb_build_object('action', 'not_applicable'); end if;      -- 이월 아닌 결제는 qbo_payment_sync 의 몫(무변)
  if not public.qbo_send_since_ok((v_a.created_at at time zone 'America/Toronto')::date) then return jsonb_build_object('action', 'before_since'); end if;   -- QBO 시대 전 사건은 조용히
  v_active := v_a.voided_at is null;
  select * into v_tc from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'opening_credit' and t.ims_id = v_a.id::text;
  select * into v_ta from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'opening_alloc'  and t.ims_id = v_a.id::text;
  select * into v_cj  from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_credit'      and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_cvj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_credit_void' and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_aj  from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_apply'       and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_avj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_apply_void'  and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  if v_tc.id is null then                                                                                                               -- CreditMemo 를 보낸 적 없다
    if v_active then
      if v_cj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'opening_credit', 'opening_alloc', v_a.id::text, 'queued', p_by)
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_id;
        if v_id is null then select j.id into v_id from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_credit' and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1; end if;
        v_cj.id := v_id; v_act := 'queued';
        if v_aj.id is not null and v_aj.state = 'blocked' then update public.qbo_job j set blocked_by = v_cj.id where j.id = v_aj.id; end if;   -- apply 가 옛(끝난) 일감 뒤에 서 있었다면 새 일감 뒤로
      end if;
      if v_aj.id is null then                                                                                                           -- 이견 2: 0 원 Payment 는 만들 때부터 CreditMemo 일감 뒤(claim ② 가 sent 때 푼다)
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'opening_apply', 'opening_alloc', v_a.id::text, 'blocked', v_cj.id, p_by, 'waits for the credit memo of this opening credit to reach QuickBooks first')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        if v_act = 'none' then v_act := 'queued'; end if;
      end if;
    else
      if v_cj.id is not null and v_cj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'opening credit detached before sending'), 2000), updated_by = p_by where j.id = v_cj.id;
        v_act := 'skipped';
      end if;
      if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'opening credit detached before sending'), 2000), updated_by = p_by where j.id = v_aj.id;
        v_act := 'skipped';
      end if;
      if v_cj.id is not null and v_cj.state in ('sending', 'unknown') and v_cvj.id is null then                                       -- 닿았는지 모른다 → void 를 그 일감 뒤에(결제 꼴)
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'opening_credit_void', 'opening_alloc', v_a.id::text, 'blocked', v_cj.id, p_by, 'detached while sending — void after the send settles')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'void_after_send';
      end if;
    end if;
  elsif v_tc.voided_at is null then                                                                                                     -- CreditMemo 가 QBO 에 서 있다
    if v_ta.id is null then                                                                                                             -- 0 원 Payment 는 아직
      if v_active then
        if v_aj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'opening_apply', 'opening_alloc', v_a.id::text, 'queued', p_by)
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
          v_act := 'queued';
        end if;
      else
        if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
          update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'opening credit detached — only the void goes'), 2000), updated_by = p_by where j.id = v_aj.id;
        end if;
        if v_aj.id is not null and v_aj.state in ('sending', 'unknown') then                                                          -- 0 원 Payment 가 나가는 중 → 그 뒤에 apply_void → 그 뒤에 credit_void
          if v_avj.id is null then
            insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'opening_apply_void', 'opening_alloc', v_a.id::text, 'blocked', v_aj.id, p_by, 'detached while sending — void after the send settles')
            on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_id;
            if v_id is null then select j.id into v_id from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_apply_void' and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1; end if;
            v_avj.id := v_id;
          end if;
          if v_cvj.id is null then
            insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'opening_credit_void', 'opening_alloc', v_a.id::text, 'blocked', v_avj.id, p_by, 'void the credit memo after the zero payment is voided')
            on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
          end if;
          v_act := 'void_after_send';
        else
          if v_cvj.id is null then
            insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'opening_credit_void', 'opening_alloc', v_a.id::text, 'queued', p_by, 'opening credit detached — void the credit memo in QuickBooks')
            on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
          end if;
          v_act := 'void';
        end if;
      end if;
    elsif v_ta.voided_at is null then                                                                                                   -- 둘 다 서 있다
      if v_active then
        v_act := 'same';                                                                                                                -- 1011 꼴: 붙임 행은 바뀌지 않는다 — 지문 · 다시 보내기 없음
      else                                                                                                                              -- 이견 12: 0 원 Payment void 먼저 → CreditMemo void(blocked_by)
        if v_avj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'opening_apply_void', 'opening_alloc', v_a.id::text, 'queued', p_by, 'opening credit detached — void the zero payment in QuickBooks')
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_id;
          if v_id is null then select j.id into v_id from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_apply_void' and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1; end if;
          v_avj.id := v_id;
        end if;
        if v_cvj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'opening_credit_void', 'opening_alloc', v_a.id::text, 'blocked', v_avj.id, p_by, 'void the credit memo after the zero payment is voided')
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        end if;
        v_act := 'void';
      end if;
    else                                                                                                                                -- 0 원 Payment 는 QBO 쪽 void 됨 · CreditMemo 는 서 있다
      if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'already voided in QuickBooks'), 2000), updated_by = p_by where j.id = v_aj.id;
        v_act := 'skipped';
      end if;
      if not v_active then
        if v_cvj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'opening_credit_void', 'opening_alloc', v_a.id::text, 'queued', p_by, 'opening credit detached — void the credit memo in QuickBooks')
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        end if;
        v_act := 'void';
      end if;
    end if;
  else                                                                                                                                  -- CreditMemo 가 QBO 쪽 void 됨(붙임은 되살지 않는다 · 다시 붙이면 새 행 = 새 두 장)
    if v_cj.id is not null and v_cj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'already voided in QuickBooks'), 2000), updated_by = p_by where j.id = v_cj.id;
      v_act := 'skipped';
    end if;
    if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'already voided in QuickBooks'), 2000), updated_by = p_by where j.id = v_aj.id;
      v_act := 'skipped';
    end if;
  end if;
  return jsonb_build_object('action', v_act);
end;
$$;
comment on function public.qbo_opening_alloc_sync(uuid, uuid) is 'qbo-sync-2e-3-1 이견 2 · 12(속 · grant 0): 이월 받아 둔 돈 붙임 하나의 QBO 일감(두 장)을 IMS 상태에 맞춘다 — 이월 아닌 결제 · 연결 없음 · since 전이면 조용히 / CreditMemo 보낸 적 없음: 활성 → opening_credit queued + opening_apply blocked_by 그것 · 떼임 → 열린 것 skipped · sending · unknown 이면 credit_void 를 그 뒤에 / CreditMemo 서 있음 · Payment 아직: 활성 → opening_apply queued · 떼임 → credit_void queued(apply 가 나가는 중이면 apply_void → credit_void 차례) / 둘 다 서 있음: 활성 → same · 떼임 → opening_apply_void queued + opening_credit_void blocked_by / Payment 만 QBO 쪽 void: 열린 apply skipped · 떼임이면 credit_void / CreditMemo QBO 쪽 void: 열린 것 skipped · 돌려주는 것 = { action } · 부르는 곳 = 트리거 가지(qbo_job_on_payment_alloc) · done 의 reconcile · 백필 · requeue';

create or replace function public.qbo_job_on_payment_alloc() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_by uuid := coalesce(new.voided_by, new.updated_by, new.created_by); v_opening boolean := false;
begin
  begin
    v_opening := exists (select 1 from public.so_payment p where p.id = new.payment_id and p.method = 'opening');                     -- 2e-3-1 이견 1: 이월 받아 둔 돈의 붙임은 opening 가지(두 장) · 새 트리거 없음 · 그 밖은 결제 길 그대로
    if v_opening then perform public.qbo_opening_alloc_sync(new.id, v_by); else perform public.qbo_payment_sync(new.payment_id, v_by); end if;
  exception when others then                                                                                                           -- 붙이기 · 떼기 · 발행 · 취소를 막지 않는다 — failed 일감으로 흔적
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff)
      select c.realm_id, case when v_opening then 'opening_credit' else 'payment' end, case when v_opening then 'opening_alloc' else 'payment' end, case when v_opening then new.id::text else new.payment_id::text end, 'failed', left('could not queue: ' || sqlerrm, 2000), v_by from public.qbo_connection c where c.singleton
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$$;

-- ═══ ④ 백필 · 계정 짝 되살리기 ═══
create function public.qbo_opening_apply_backfill() returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare r record; v_n int := 0; v_r jsonb;
begin
  if not exists (select 1 from public.qbo_connection c where c.singleton) then return 0; end if;
  for r in select a.id, coalesce(a.created_by, p.created_by) as by_staff from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id join public.so_invoice i on i.id = a.invoice_id
            where a.voided_at is null and p.status = 'active' and p.kind = 'payment' and p.method = 'opening'
              and i.kind = 'sale' and public.qbo_send_since_ok(i.issued_on) and public.qbo_send_since_ok((a.created_at at time zone 'America/Toronto')::date)
              and not exists (select 1 from public.qbo_job j where j.ims_kind = 'opening_alloc' and j.ims_id = a.id::text)
              and not exists (select 1 from public.qbo_txn t where t.ims_kind in ('opening_credit', 'opening_alloc') and t.ims_id = a.id::text)
            order by a.created_at, a.id loop
    v_r := public.qbo_opening_alloc_sync(r.id, r.by_staff);
    if v_r->>'action' = 'queued' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end;
$$;
comment on function public.qbo_opening_apply_backfill() is 'qbo-sync-2e-3-1 이견 10(속 · grant 0): 적용 때 한 번 — 활성 · 결제 opening ∧ active · 인보이스 sale ∧ since 뒤 · 붙임 created_at since 뒤 · 일감(어느 상태든) · 거래 짝 없는 붙임마다 opening_credit queued + opening_apply blocked · 이월 인보이스에 붙은 것은 1d 의 qbo_payment_requeue 가 · 연결 없으면 0 · 돌려주는 것 = 붙임 수(일감은 그 두 배)';

create function public.qbo_opening_credit_requeue(p_account_code text, p_by uuid) returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_r record; v_n int := 0;
begin
  for v_r in select j.id from public.qbo_job j join public.so_payment_alloc a on a.id::text = j.ims_id join public.so_payment p on p.id = a.payment_id join public.qbo_connection c on c.singleton and c.realm_id = j.realm_id
              where j.kind = 'opening_credit' and j.ims_kind = 'opening_alloc' and j.state = 'failed' and a.voided_at is null and p.status = 'active' and p.kind = 'payment' and p.method = 'opening' and p.account_code = p_account_code
              order by j.created_at, j.id loop
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, format('sent again: account item "acct:%s" is now matched in QuickBooks', p_account_code)), 2000), updated_by = p_by
     where j.id = v_r.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function public.qbo_opening_credit_requeue(text, uuid) is 'qbo-sync-2e-3-1 이견 7(속 · grant 0 · qbo_link_set 이 charge acct:<code> 짝을 세울 때 부른다 · 1039 꼴): 그 계정의 이월 돈 뒤에 선 failed opening_credit 일감(붙임 활성 · 결제 active)을 queued 로 · 돌려주는 것 = 되살린 수';

-- ═══ ④′ 재발행 — qbo_payment_requeue(1d-1 바이트 + 이월 돈 붙임 루프) · qbo_link_set(1d-1 바이트 + charge acct: 가지) · qbo_ims_rows(2e-1a 바이트 + 이월 결제 계정 행) · qbo_credit_apply_body(2e-2-1 바이트 + 1013 에 opening_apply_void) ═══
create or replace function public.qbo_payment_requeue(p_invoice_id uuid) returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare r record; v_n int := 0; v_num text;
begin
  select i.invoice_number into v_num from public.so_invoice i where i.id = p_invoice_id;
  for r in select distinct a.payment_id, p.created_by from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
            where a.invoice_id = p_invoice_id and a.voided_at is null and p.status = 'active' and p.kind = 'payment' and p.method <> 'opening' loop
    perform public.qbo_payment_requeue_one(r.payment_id, r.created_by, 'sent again: invoice ' || coalesce(v_num, '?') || ' is now matched in QuickBooks');   -- 2e-1d-1 이견 6: 남은 이월 장 0 일 때만 sync + failed → queued · 아니면 failed 그대로(글 「N carried-over …」)
    v_n := v_n + 1;
  end loop;
  for r in select a.id, a.created_by from public.so_credit_alloc a where a.invoice_id = p_invoice_id and a.voided_at is null order by a.created_at, a.id loop   -- 2e-2-1 판정 1016: 이 인보이스에 붙은 활성 크레딧 붙임도(일감 없으면 만든다 · failed 는 되살린다)
    perform public.qbo_credit_alloc_sync(r.id, r.created_by);
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: invoice ' || coalesce(v_num, '?') || ' is now matched in QuickBooks'), 2000)
     where j.kind = 'credit_apply' and j.ims_kind = 'credit_alloc' and j.ims_id = r.id::text and j.state = 'failed';
    v_n := v_n + 1;
  end loop;
  for r in select a.id, coalesce(a.created_by, p.created_by) as by_staff from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
            where a.invoice_id = p_invoice_id and a.voided_at is null and p.status = 'active' and p.kind = 'payment' and p.method = 'opening' order by a.created_at, a.id loop   -- 2e-3-1 이견 11(1016 꼴): 이 인보이스에 붙은 이월 받아 둔 돈의 활성 붙임도(일감 없으면 두 장 만든다 · failed 는 되살린다)
    perform public.qbo_opening_alloc_sync(r.id, r.by_staff);
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: invoice ' || coalesce(v_num, '?') || ' is now matched in QuickBooks'), 2000)
     where j.kind in ('opening_credit', 'opening_apply') and j.ims_kind = 'opening_alloc' and j.ims_id = r.id::text and j.state = 'failed';
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
create or replace function public.qbo_link_set(p_kind text, p_ims_id text, p_qbo_id text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_realm text := public.qbo_realm_of(); v_type text := public.qbo_type_of(p_kind); v_ims record; v_ent public.qbo_entity%rowtype; v_other record; v_l public.qbo_link%rowtype; v_rq int := 0;
begin
  if v_type is null then raise exception 'kind must be one of account, tax_rule, payment_term, payment_method, customer, supplier, product, charge, service (got %)', p_kind; end if;
  select * into v_ims from public.qbo_ims_rows(p_kind) r where r.ims_id = p_ims_id;
  if v_ims.ims_id is null then raise exception 'No IMS % with id % — nothing was saved', p_kind, p_ims_id; end if;
  select * into v_ent from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = v_type and e.qbo_id = p_qbo_id;
  if v_ent.qbo_id is null then raise exception 'QuickBooks % % is not in the pulled list — pull the list first, or check the id', v_type, p_qbo_id; end if;
  if v_ent.gone_at is not null then raise exception 'QuickBooks % % (%) is no longer in QuickBooks (gone since %) — nothing was saved', v_type, p_qbo_id, v_ent.name, v_ent.gone_at::date; end if;
  if p_kind <> 'tax_rule' then
    select l.ims_kind, l.ims_id into v_other from public.qbo_link l where l.realm_id = v_realm and l.qbo_type = v_type and l.qbo_id = p_qbo_id and l.ims_kind <> 'tax_rule' and not (l.ims_kind = p_kind and l.ims_id = p_ims_id);
    if found then raise exception 'QuickBooks % % (%) is already linked to IMS % % — clear that link first', v_type, p_qbo_id, v_ent.name, v_other.ims_kind, coalesce((select r.ims_name from public.qbo_ims_rows(v_other.ims_kind) r where r.ims_id = v_other.ims_id), v_other.ims_id); end if;
  end if;
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match, by_staff)
  values (v_realm, p_kind, p_ims_id, v_type, p_qbo_id, 'manual', v_ent.name, v_staff)
  on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, matched_by = 'manual', qbo_name_at_match = excluded.qbo_name_at_match, by_staff = excluded.by_staff, matched_at = now(), updated_at = now(), updated_by = excluded.by_staff
  returning * into v_l;
  if p_kind = 'payment_method' then v_rq := public.qbo_payment_method_requeue(p_ims_id, v_staff); end if;
  if p_kind = 'charge' and p_ims_id like 'acct:%' then v_rq := v_rq + public.qbo_opening_credit_requeue(substr(p_ims_id, 6), v_staff); end if;   -- 2e-3-1 이견 7(1039 꼴): 계정 Item 짝이 서면 그 계정의 이월 돈 failed opening_credit 을 queued 로   -- 2e-1d-1 판정 1039: 수단 짝이 서면 그 수단의 failed 결제 일감을 queued 로(남은 이월 장 > 0 은 건너뛴다)
  return to_jsonb(v_l) || jsonb_build_object('ims_name', v_ims.ims_name, 'ims_code', v_ims.ims_code, 'qbo_name', v_ent.name, 'qbo_active', v_ent.active, 'requeued', v_rq);
end;
$$;
create or replace function public.qbo_ims_rows(p_kind text) returns table (ims_id text, ims_name text, ims_code text, ims_active boolean)
  language sql stable security definer rows 20000 set search_path = public, pg_temp
as $$
  select a.id::text, a.name, a.code, a.is_active from public.ref_account a where p_kind = 'account'
  union all select t.id::text, t.name, t.direction, t.is_active from public.ref_tax_rule t where p_kind = 'tax_rule'
  union all select pt.id::text, pt.name, null, pt.is_active from public.ref_payment_term pt where p_kind = 'payment_term'
  union all select m.v, m.v, m.q, true from (values ('cheque', 'Cheque'), ('debit_card', 'Debit'), ('e_transfer', 'E-Transfer'), ('wire', 'Wire'), ('cash', 'Cash'), ('shopify', 'Shopify'), ('direct_deposit', 'EFT (ACH)'), ('credit_card', null), ('paypal', 'PayPal')) m(v, q) where p_kind = 'payment_method'
  union all select c.id::text, c.name, null, c.is_active from public.customer c where p_kind = 'customer'
  union all select s.id::text, s.name, null, s.is_active from public.supplier s where p_kind = 'supplier'
  union all select p.id::text, p.name, p.sku, p.is_active from public.product p where p_kind = 'product'
  union all select v, v, null, true from unnest(array['freight', 'discount', 'surcharge', 'freight_discount']) v where p_kind = 'charge'
  union all select 'acct:' || a.code, 'Charge on account ' || a.code || ' ' || a.name, a.code, a.is_active from public.ref_account a
             where p_kind = 'charge' and a.code <> '_99_'
               and (exists (select 1 from public.so_charge c where c.account_code = a.code and c.service_id is null)
                    or exists (select 1 from public.so_credit_line cl where cl.account_code = a.code and cl.kind in ('other', 'restocking_fee'))
                    or exists (select 1 from public.qbo_link l where l.ims_kind = 'charge' and l.ims_id = 'acct:' || a.code)
                    or exists (select 1 from public.so_payment p where p.method = 'opening' and p.account_code = a.code))   -- 2e-3-1 이견 7: 이월 받아 둔 돈이 선 계정(Customer Credits)의 Item 짝 자리
  union all select r.id::text, r.name, null, r.is_active from public.ref_service r where p_kind = 'service'
$$;
create or replace function public.qbo_credit_apply_body(p_alloc_id uuid) returns jsonb
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
                                when 'opening_apply_void' then (select public.qbo_opening_doc_number(a3.id) from public.so_payment_alloc a3 where a3.id::text = j.ims_id)   -- 2e-3-1 이견 8
                                else (select c2.credit_number from public.so_credit_alloc a2 join public.so_credit c2 on c2.id = a2.credit_id where a2.id::text = j.ims_id) end as doc
               from public.qbo_job j
              where j.realm_id = v_realm and j.state not in ('sent', 'skipped')
                and ((j.kind = 'payment_void' and exists (select 1 from public.so_payment_alloc pa where pa.payment_id::text = j.ims_id and pa.invoice_id = v_i.id))
                  or (j.kind = 'credit_apply_void' and j.ims_id <> v_a.id::text and exists (select 1 from public.so_credit_alloc a2 where a2.id::text = j.ims_id and a2.invoice_id = v_i.id))
                  or (j.kind = 'opening_apply_void' and exists (select 1 from public.so_payment_alloc a3 where a3.id::text = j.ims_id and a3.invoice_id = v_i.id)))   -- 2e-3-1 이견 8: 이월 돈 붙임의 0 원 Payment void 도 기다린다
              order by j.created_at, j.id limit 1 loop
      v_wait := r.id; v_wait_doc := r.doc;
      v_wait_reason := format('waiting for the void of %s %s on invoice %s to reach QuickBooks first (that job is %s%s)', case r.kind when 'payment_void' then 'payment' when 'opening_apply_void' then 'opening credit' else 'credit note' end, r.doc, v_i.invoice_number, r.state,
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

-- ═══ ⑤ 재발행 — claim · preview · doc · list · retry · done(2e-2-1 바이트 + 가지 · 같은 서명 · create or replace 라 ACL 그대로) ═══
create or replace function public.qbo_job_claim(p_limit int default 15, p_kinds text[] default array['customer', 'item'], p_job_ids uuid[] default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_stale int; v_unblocked int; v_ids uuid[]; v_j public.qbo_job%rowtype; v_open public.qbo_job%rowtype; v_b jsonb; v_rows jsonb := '[]'::jsonb; v_failed int := 0; v_blocked int := 0; v_waiting int := 0; v_last uuid; v_cust uuid; v_nj jsonb; e jsonb;
  v_kinds text[] := coalesce(p_kinds, array['customer', 'item']);
  v_pick uuid[] := (select array_agg(distinct x) from unnest(p_job_ids) x where x is not null);                                       -- 2d1: 고른 id(중복 · null 제거) · null 이면 옛 길(가장 오래된 것부터 p_limit)
  v_needs jsonb := '[]'::jsonb; v_req jsonb := '[]'::jsonb; v_r record;
begin
  if not public.doc_is_service() then raise exception 'qbo_job_claim is for the send worker only — nothing was read'; end if;
  if not (v_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void']) or coalesce(array_length(v_kinds, 1), 0) = 0 then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void (got %)', v_kinds; end if;
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
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid) end;   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void   -- 2c1 credit · credit_void
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
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid) end;   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
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
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid) end;   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
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
    when 'opening_alloc' then (select jsonb_build_object('doc_number', public.qbo_opening_doc_number(a.id) || ' → ' || i.invoice_number, 'name', (select cu.name from public.customer cu where cu.id = p.customer_id), 'customer_id', p.customer_id, 'currency', p.currency_code, 'total', a.amount, 'doc_date', (a.created_at at time zone 'America/Toronto')::date, 'doc_status', case when a.voided_at is null then 'active' else 'voided' end)
                                 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id join public.so_invoice i on i.id = a.invoice_id where a.id::text = p_ims_id)   -- 2e-3-1: 이월 돈 붙임 = 「OC-<인보이스>-<n> → 인보이스」 · 돈의 주인(이견 4) · 통화 · 붙임 금액 · 붙인 날(토론토) · active | voided
    else jsonb_build_object('doc_number', p_ims_id, 'name', p_ims_id, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', null) end;
$$;
create or replace function public.qbo_job_list(p_state text default null, p_kinds text[] default null, p_from date default null, p_to date default null, p_q text default null, p_limit int default 50, p_offset int default 0) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if p_state is not null and p_state not in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped', 'open') then raise exception 'state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open (got %)', p_state; end if;
  if p_kinds is not null and (not (p_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void']) or coalesce(array_length(p_kinds, 1), 0) = 0) then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void (got %)', p_kinds; end if;
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
                             when 'product' then coalesce(d.doc->>'doc_number', '') || ' ' || coalesce(d.doc->>'name', '')
                             else coalesce(d.doc->>'name', j.ims_id) end as ims_name,
             (select s.name from public.ims_staff s where s.id = j.by_staff) as by_name,
             p.kind as blocked_kind, p.state as blocked_state, coalesce(pd.doc->>'doc_number', pd.doc->>'name', p.ims_id) as blocked_name,
             t.qbo_id as txn_qbo_id, t.total_amt as txn_total_amt, t.total_tax as txn_total_tax, t.mismatch as txn_mismatch, t.voided_at as txn_voided_at
      from public.qbo_job j
      cross join lateral (select public.qbo_job_doc(j.ims_kind, j.ims_id) as doc) d
      left join public.qbo_job p on p.id = j.blocked_by
      left join lateral (select public.qbo_job_doc(p.ims_kind, p.ims_id) as doc) pd on p.id is not null
      left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc')
                               and t.ims_kind = case j.kind when 'opening_credit' then 'opening_credit' when 'opening_credit_void' then 'opening_credit' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc' else j.ims_kind end   -- 2e-3-1 이견 3: 한 붙임에 txn 둘 — kind 로 갈라 잇는다
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
        v_oa public.so_payment_alloc%rowtype;   -- 2e-3-1
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
  return jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'state', case when v_link_err is null then 'sent' else 'failed' end, 'reconcile', v_sync, 'qbo_id', btrim(p_qbo_id), 'qbo_name', btrim(p_qbo_name), 'linked', v_link_err is null, 'link_error', v_link_err, 'unblocked', v_unblocked, 'mismatch', v_mismatch);
end;
$$;
-- ═══ ① 표(⚠️ 일부러 끝에 — ACCESS EXCLUSIVE 잠금은 여기부터 끝까지만 · 함수는 표 CHECK 와 무관하게 먼저 선다) ═══
alter table public.qbo_job drop constraint qbo_job_kind_ck;
alter table public.qbo_job add  constraint qbo_job_kind_ck check (kind in ('customer', 'item', 'invoice', 'credit', 'invoice_void', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void'));
alter table public.qbo_job drop constraint qbo_job_ims_kind_ck;
alter table public.qbo_job add  constraint qbo_job_ims_kind_ck check (ims_kind in ('customer', 'product', 'charge', 'invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc'));
alter table public.qbo_job drop constraint qbo_job_pair_ck;
alter table public.qbo_job add  constraint qbo_job_pair_ck check (ims_kind = case kind when 'customer' then 'customer' when 'invoice' then 'invoice' when 'invoice_void' then 'invoice' when 'credit' then 'credit' when 'credit_void' then 'credit'
                                                                                        when 'payment' then 'payment' when 'payment_void' then 'payment' when 'credit_apply' then 'credit_alloc' when 'credit_apply_void' then 'credit_alloc'
                                                                                        when 'opening_credit' then 'opening_alloc' when 'opening_credit_void' then 'opening_alloc' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc' else ims_kind end
                                                                and (kind <> 'item' or ims_kind in ('product', 'charge')));
alter table public.qbo_txn drop constraint qbo_txn_kind_ck;
alter table public.qbo_txn add  constraint qbo_txn_kind_ck check (ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_credit', 'opening_alloc'));
alter table public.qbo_txn drop constraint qbo_txn_pair_ck;
alter table public.qbo_txn add  constraint qbo_txn_pair_ck check (qbo_type = case ims_kind when 'invoice' then 'Invoice' when 'credit' then 'CreditMemo' when 'opening_credit' then 'CreditMemo' else 'Payment' end);


-- ═══ ⑥ grant — 새 함수 전부 grant 0(claim · done · 트리거 · 백필 · link_set 이 부른다) · 재발행 열둘은 create or replace 라 ACL 그대로 ═══
revoke all on function public.qbo_opening_doc_number(uuid), public.qbo_opening_credit_body(uuid), public.qbo_opening_credit_void_body(uuid), public.qbo_opening_apply_body(uuid), public.qbo_opening_apply_void_body(uuid),
  public.qbo_opening_alloc_sync(uuid, uuid), public.qbo_opening_apply_backfill(), public.qbo_opening_credit_requeue(text, uuid)
  from public, anon, authenticated, service_role;
do $$
begin
  execute format('comment on table public.qbo_job is %L', coalesce(obj_description('public.qbo_job'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-2e-3-1: kind opening_credit · opening_credit_void(「쓰기」 CreditMemo) · opening_apply · opening_apply_void(0 원 Payment)(ims_kind opening_alloc · ims_id so_payment_alloc.id · 트리거 so_payment_alloc_qbo 의 opening 가지 · 지문 없음 — 이월 받아 둔 돈의 붙임 한 줄 = 두 장 · 998′ · 돈 자체는 안 보낸다 786)');
  execute format('comment on table public.qbo_txn is %L', coalesce(obj_description('public.qbo_txn'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-2e-3-1: ims_kind opening_credit ↔ QBO CreditMemo(DocNumber OC-<인보이스>-<n>) · opening_alloc ↔ QBO Payment(0 원 · doc_number = 「OC-… → 인보이스」) · 한 붙임(ims_id)에 둘 · fingerprint null · source sent');
  execute format('comment on function public.qbo_job_on_payment_alloc() is %L', coalesce(obj_description('public.qbo_job_on_payment_alloc()'::regprocedure, 'pg_proc'), '') || ' · [2e-3-1 이견 1] 결제가 opening 이면 qbo_opening_alloc_sync(new.id)(두 장) · 아니면 qbo_payment_sync 그대로 · 트리거 so_payment_alloc_qbo 무변(새 트리거 없음) · 실패 흔적은 가지에 맞춰 opening_credit | payment');
  execute format('comment on function public.qbo_payment_requeue(uuid) is %L', coalesce(obj_description('public.qbo_payment_requeue(uuid)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-1 이견 11] 이월 돈의 활성 붙임도 — qbo_opening_alloc_sync + failed opening_credit · opening_apply 를 queued 로');
  execute format('comment on function public.qbo_link_set(text, text, text) is %L', coalesce(obj_description('public.qbo_link_set(text, text, text)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-1 이견 7] charge acct:<code> 짝이 서면 qbo_opening_credit_requeue(그 계정의 failed opening_credit → queued · requeued 에 더한다)');
  execute format('comment on function public.qbo_ims_rows(text) is %L', coalesce(obj_description('public.qbo_ims_rows(text)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-1 이견 7] charge 에 이월 받아 둔 돈(so_payment method opening)이 선 계정의 acct:<code> 행도 — Item 5624 Customer Credit 의 짝 자리');
  execute format('comment on function public.qbo_credit_apply_body(uuid) is %L', coalesce(obj_description('public.qbo_credit_apply_body(uuid)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-1 이견 8] 1013 기다림에 같은 인보이스의 열린 opening_apply_void 도');
  execute format('comment on function public.qbo_job_claim(int, text[], uuid[]) is %L', coalesce(obj_description('public.qbo_job_claim(int, text[], uuid[])'::regprocedure, 'pg_proc'), '') || ' · [2e-3-1 kinds 14 · 몸 opening_credit · opening_credit_void · opening_apply · opening_apply_void]');
  execute format('comment on function public.qbo_job_preview(uuid) is %L', coalesce(obj_description('public.qbo_job_preview(uuid)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-1 몸 넷]');
  execute format('comment on function public.qbo_job_doc(text, text) is %L', coalesce(obj_description('public.qbo_job_doc(text, text)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-1 opening_alloc = 「OC-<인보이스>-<n> → 인보이스」 · 돈의 주인 · 통화 · 붙임 금액 · 붙인 날 · active | voided]');
  execute format('comment on function public.qbo_job_list(text, text[], date, date, text, int, int) is %L', coalesce(obj_description('public.qbo_job_list(text, text[], date, date, text, int, int)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-1 kinds 14 · ims_name opening_alloc · txn 짝은 kind 로 갈라 잇는다(opening_credit·_void ↔ txn opening_credit · opening_apply·_void ↔ txn opening_alloc — 한 붙임에 txn 둘)]');
  execute format('comment on function public.qbo_job_retry(uuid, text) is %L', coalesce(obj_description('public.qbo_job_retry(uuid, text)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-1 이견 13: opening_credit · opening_apply 는 붙임 활성 ∧ 그 장이 QBO 에 안 섰을 때만 · void 둘은 그 장이 서 있고 붙임이 떼였을 때만]');
  execute format('comment on function public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric, numeric) is %L', coalesce(obj_description('public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric, numeric)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-1 이견 14: opening_credit → qbo_txn opening_credit CreditMemo(TotalAmt = 붙임 금액 ∧ TotalTax 0 대조) · opening_apply → qbo_txn opening_alloc Payment(TotalAmt 0 · UnappliedAmt 0 대조) · void 둘 → voided_at · 끝에 qbo_opening_alloc_sync]');
end $$;

-- ═══ ⑦ 착지 · 백필 ═══
do $$
declare v text; v_n int; v_bad text := '';
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname, p.oid) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_opening_doc_number', 'qbo_opening_credit_body', 'qbo_opening_credit_void_body', 'qbo_opening_apply_body', 'qbo_opening_apply_void_body', 'qbo_opening_alloc_sync', 'qbo_opening_apply_backfill', 'qbo_opening_credit_requeue',
                                                                                        'qbo_job_done', 'qbo_job_claim', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc', 'qbo_payment_requeue', 'qbo_link_set', 'qbo_ims_rows', 'qbo_credit_apply_body', 'qbo_job_on_payment_alloc');
  if v <> 'qbo_credit_apply_body(p_alloc_id uuid)={postgres=X/postgres} qbo_ims_rows(p_kind text)={postgres=X/postgres} qbo_job_claim(p_limit integer, p_kinds text[], p_job_ids uuid[])={postgres=X/postgres,service_role=X/postgres} qbo_job_doc(p_ims_kind text, p_ims_id text)={postgres=X/postgres} qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text, p_intuit_tid text, p_note text, p_sku text, p_total_amt numeric, p_total_tax numeric, p_unapplied_amt numeric)={postgres=X/postgres,service_role=X/postgres} qbo_job_list(p_state text, p_kinds text[], p_from date, p_to date, p_q text, p_limit integer, p_offset integer)={postgres=X/postgres,authenticated=X/postgres} qbo_job_on_payment_alloc()={postgres=X/postgres} qbo_job_preview(p_job uuid)={postgres=X/postgres,authenticated=X/postgres} qbo_job_retry(p_job uuid, p_note text)={postgres=X/postgres,authenticated=X/postgres} qbo_link_set(p_kind text, p_ims_id text, p_qbo_id text)={postgres=X/postgres,authenticated=X/postgres} qbo_opening_alloc_sync(p_alloc_id uuid, p_by uuid)={postgres=X/postgres} qbo_opening_apply_backfill()={postgres=X/postgres} qbo_opening_apply_body(p_alloc_id uuid)={postgres=X/postgres} qbo_opening_apply_void_body(p_alloc_id uuid)={postgres=X/postgres} qbo_opening_credit_body(p_alloc_id uuid)={postgres=X/postgres} qbo_opening_credit_requeue(p_account_code text, p_by uuid)={postgres=X/postgres} qbo_opening_credit_void_body(p_alloc_id uuid)={postgres=X/postgres} qbo_opening_doc_number(p_alloc_id uuid)={postgres=X/postgres} qbo_payment_requeue(p_invoice_id uuid)={postgres=X/postgres}' then
    raise exception '⑦ ACL unexpected: %', v;
  end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_body')        is distinct from 'e1aea51849844cc5898351daaa3ef533' then v_bad := v_bad || ' qbo_payment_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_void_body')   is distinct from '4ddb45cd728222d7b676d1e0bd169a54' then v_bad := v_bad || ' qbo_payment_void_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_sync')        is distinct from '9efb5d9f6007048692d13cd00623c4b8' then v_bad := v_bad || ' qbo_payment_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_fingerprint') is distinct from 'd6da0342942ef68345b9432e0e84da23' then v_bad := v_bad || ' qbo_payment_fingerprint'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_credit_alloc_sync')   is distinct from '44419d3b499a33299e010e33671b26fa' then v_bad := v_bad || ' qbo_credit_alloc_sync'; end if;
  if v_bad <> '' then raise exception '⑦ functions changed by this migration (must not):%', v_bad; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_payment_alloc'::regclass and not tgisinternal) <> 2 or (select count(*) from pg_trigger where tgname = 'so_payment_alloc_qbo' and tgdeferrable and tginitdeferred) <> 1 then raise exception '⑦ so_payment_alloc triggers changed (must stay: so_payment_alloc_qbo deferred + so_payment_alloc_touch)'; end if;
  v_n := public.qbo_opening_apply_backfill();
  raise notice '⑦ opening credit backfill: % application(s) queued = % job(s) (opening_credit queued + opening_apply blocked · sale invoices since % · opening-linked applications wait for 1d)', v_n, v_n * 2, coalesce((select c.value from public.inv_config c where c.key = 'qbo_send_since'), '?');
end $$;
-- 끝 — 적용 뒤: supabase/tests/qbo_sync_2e3_1_check.sql(-v mig 없이) → Settings → QuickBooks matching 에서 charge 「acct:_1150040009_」 ↔ Item 5624 Customer Credit 짝(그 전까지 opening_credit 은 claim 때 failed · 짝이 서면 되살아난다) → 2e-3-1b(EF) 배포 → cron 62 kinds 8(supabase/ops/cron.sql)
