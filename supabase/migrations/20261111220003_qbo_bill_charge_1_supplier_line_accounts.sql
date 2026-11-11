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

-- qbo-bill-charge-1: 공급처 인보이스의 charge · other 줄을 QuickBooks Bill 로(설정 계정 · 기본 _95_) · 돈 안 내는 줄은 Bill 에서 뺀다 (2026-11-11 · 지시서 ~/asung/prompts/qbo-bill-charge-1.md · 판정 1189 ~ 1192 · §0 이견 1 ~ 7)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — PGCONNECT_TIMEOUT=10 psql -X -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied · supabase db push 금지
-- 무엇:
--   · 1189 charge 줄 계정 = 설정 한 줄(inv_config qbo_supplier_line_charge_account_code · 기본 _95_ Purchase Non Stock - COS) · 1190 other 줄은 따로 한 줄(qbo_supplier_line_other_account_code · 기본 _95_)
--   · 1191 돈 안 내는 줄(is_payable false)은 Bill · VendorCredit 에서 뺀다 — 줄 · 할인 줄 · 세금 묶음 · 합계 · 지문 · lookup 모두 낼 돈 기준(po_tax_group.payable_* · po_invoice_money.payable_net) ⇒ QBO 미지급 = IMS 미지급
--   · 1192 찍힌 합계 대조(diff ≠ 0 막음)는 그대로 — 1 센트 규칙은 다음 판정
--   · 설정은 IMS 계정 코드를 담는다 — QBO id 는 qbo_account_ref 가 계정 짝(qbo_link account)으로 푼다(realm 이 바뀌어도 설정은 그대로) · qbo_link 무접촉(ims_kind charge 는 손님 쪽 것 · §15-m ②)
--   · 창구 둘(열쇠 QUICKBOOKS): 읽기 qbo_supplier_line_accounts() = qbo_key_gate(false) · 쓰기 qbo_supplier_line_account_set(kind, code, old) = qbo_key_gate(true) — ims_config_set 무접촉(그 창구는 새 키 둘을 「a migration or psql changes this」 로 거부한다 · 판정 572 그대로)
--   · 고를 수 있는 계정 = 켜짐 ∧ QBO 짝 ∧ 종류 COSTOFGOODSSOLD · EXPENSE
-- 재발행 하나: qbo_bill_body(원본 = DB prosrc md5 00a956505d62b34fb7f1de2a40d8e482 · 마지막 정의 20261109103000 4-3a · 생성기가 바꾼 줄만) — 서명 무변 · create or replace(grant 0 · 그대로)
-- 무변: 원가 레이어(inv_layer_post_receipt 는 goods 만) · Landed(po_charge · qbo_charge_bill_body) · 하루 원가 장 · BillPayment · 할인 VC · 손님 matching · EF(몸은 DB · 줄 · 계정을 보지 않는다) · cron
-- 새 표 0 · FK 0 → 컷오버 날 지우는 순서 영향 없음 · 시퀀스 0 · 이미 보낸 Bill 은 다시 보내지 않는다(몸은 claim · preview 때만 만든다 · Bill 지문으로 다시 보내는 길 없음)
-- ⚠️ 공개 레포 — 공급처 상호 없음 · UI 글자는 영어 · jsonb_build_object 안에 「--」 줄 주석을 두지 않는다
-- 검증 supabase/tests/qbo_bill_charge_1_check.sql(운영 메인 begin → rollback · 가짜 재료만) · 적용은 Caleb

-- ═══════════════ ⓪ 원본 가드 — 재발행 원본 md5 · 이름 하나 · 아직 미적용 · 기본 계정 _95_ 가 켜져 있고 QBO 짝이 있다 ═══════════════
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_bill_body') is distinct from '00a956505d62b34fb7f1de2a40d8e482' then v_bad := v_bad || ' qbo_bill_body(md5)'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_bill_body') <> 1 then v_bad := v_bad || ' qbo_bill_body(count)'; end if;
  if to_regprocedure('public.qbo_account_ref(text, text)') is null or to_regprocedure('public.qbo_key_gate(boolean)') is null or to_regprocedure('public.qbo_realm_of()') is null then v_bad := v_bad || ' (2a missing)'; end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_supplier_line_account', 'qbo_supplier_line_account_row', 'qbo_supplier_line_accounts', 'qbo_supplier_line_account_set'))
     or exists (select 1 from public.inv_config where key in ('qbo_supplier_line_charge_account_code', 'qbo_supplier_line_other_account_code')) then v_bad := v_bad || ' (qbo-bill-charge-1 already applied?)'; end if;
  if not exists (select 1 from public.ref_account a where a.code = '_95_' and a.is_active and a.account_type in ('COSTOFGOODSSOLD', 'EXPENSE')) then v_bad := v_bad || ' (account _95_ missing, off or not a cost account)'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'po_tax_group' and column_name = 'payable_discount')
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'po_invoice_money' and column_name = 'payable_net') then v_bad := v_bad || ' (payable view columns missing)'; end if;
  if v_bad <> '' then raise exception 'qbo-bill-charge-1 STOP —%. Nothing was changed.', v_bad; end if;
end $$;

-- ═══════════════ ① 설정 두 줄 — 기본 _95_(1189 · 1190) ═══════════════
insert into public.inv_config (key, value, note) values
  ('qbo_supplier_line_charge_account_code', '_95_', '[qbo-bill-charge-1 · 판정 1189] 공급처 인보이스 charge 줄(공급처가 상품 인보이스 안에 넣은 운임 등)의 QuickBooks Bill 계정 — IMS 계정 코드 · Settings → QuickBooks matching 에서 바꾼다(qbo_supplier_line_account_set · 열쇠 QUICKBOOKS) · Landed 아님'),
  ('qbo_supplier_line_other_account_code',  '_95_', '[qbo-bill-charge-1 · 판정 1190] 공급처 인보이스 other 줄의 QuickBooks Bill 계정 — IMS 계정 코드 · Settings → QuickBooks matching 에서 바꾼다(qbo_supplier_line_account_set · 열쇠 QUICKBOOKS)');

-- ═══════════════ ② 속 함수 둘(grant 0) — 몸이 읽는 계정 · 화면 한 줄 ═══════════════
create function public.qbo_supplier_line_account(p_line_kind text) returns text
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_key  text := case p_line_kind when 'charge' then 'qbo_supplier_line_charge_account_code' when 'other' then 'qbo_supplier_line_other_account_code' end;
  v_code text; v_acc public.ref_account%rowtype;
begin
  if v_key is null then raise exception 'Supplier line kind % has no QuickBooks account setting — nothing was sent', coalesce(p_line_kind, 'null'); end if;
  select nullif(btrim(c.value), '') into v_code from public.inv_config c where c.key = v_key;
  if v_code is null then raise exception 'No QuickBooks account is chosen for supplier invoice % lines — choose one under Settings → QuickBooks matching, then retry — nothing was sent', p_line_kind; end if;
  select * into v_acc from public.ref_account a where a.code = v_code;
  if v_acc.id is null then raise exception 'Account % (chosen for supplier invoice % lines) does not exist in IMS — choose another under Settings → QuickBooks matching, then retry — nothing was sent', v_code, p_line_kind; end if;
  if not v_acc.is_active then raise exception 'Account % % (chosen for supplier invoice % lines) is switched off in IMS — choose another under Settings → QuickBooks matching, then retry — nothing was sent', v_code, v_acc.name, p_line_kind; end if;
  return public.qbo_account_ref(v_code, format('supplier invoice %s lines', p_line_kind));
end;
$$;
comment on function public.qbo_supplier_line_account(text) is '[qbo-bill-charge-1 · 판정 1189 · 1190 · grant 0] 공급처 인보이스 charge | other 줄의 QuickBooks 계정 Id — inv_config 의 IMS 계정 코드 → 켜짐 확인 → qbo_account_ref(계정 짝) · 비었거나 · 없거나 · 꺼졌거나 · 짝이 없으면 까닭 글로 거부(nothing was sent) · qbo_bill_body 만 부른다';

create function public.qbo_supplier_line_account_row(p_line_kind text) returns jsonb
  language sql stable security definer set search_path = public, pg_temp
as $$
  select jsonb_build_object(
           'line_kind', k.line_kind, 'key', k.key, 'code', nullif(btrim(c.value), ''), 'name', a.name, 'account_type', a.account_type, 'is_active', a.is_active,
           'linked', l.qbo_id is not null, 'qbo_id', l.qbo_id,
           'problem', case when nullif(btrim(c.value), '') is null then 'No account chosen — supplier invoices with these lines cannot be sent'
                           when a.id is null then 'This account does not exist in IMS'
                           when not a.is_active then 'This account is switched off in IMS'
                           when l.qbo_id is null then 'This account has no QuickBooks match' end,
           'updated_at', c.updated_at, 'updated_by_name', s.name)
    from (values ('charge', 'qbo_supplier_line_charge_account_code'), ('other', 'qbo_supplier_line_other_account_code')) k(line_kind, key)
    left join public.inv_config c on c.key = k.key
    left join public.ref_account a on a.code = nullif(btrim(c.value), '')
    left join public.qbo_link l on l.realm_id = public.qbo_realm_of() and l.ims_kind = 'account' and l.ims_id = a.id::text
    left join public.ims_staff s on s.id = c.updated_by
   where k.line_kind = p_line_kind
$$;
comment on function public.qbo_supplier_line_account_row(text) is '[qbo-bill-charge-1 · grant 0] 설정 한 줄의 지금 모습(계정 코드 · 이름 · 종류 · 켜짐 · QBO 짝 · 문제 글 · 고친 사람) — 읽기 · 쓰기 창구가 같은 꼴로 돌려준다';

-- ═══════════════ ③ 창구 둘(열쇠 QUICKBOOKS) — Settings → QuickBooks matching ═══════════════
create function public.qbo_supplier_line_accounts() returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_can boolean;
begin
  select coalesce(s.perms, '[]'::jsonb) ? 'qbo' into v_can from public.ims_staff s where s.id = v_staff;
  return jsonb_build_object(
    'can_edit', coalesce(v_can, false),
    'lines', jsonb_build_array(public.qbo_supplier_line_account_row('charge'), public.qbo_supplier_line_account_row('other')),
    'accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name', a.name, 'account_type', a.account_type) order by a.name, a.code), '[]'::jsonb)
                   from public.ref_account a
                  where a.is_active and a.account_type in ('COSTOFGOODSSOLD', 'EXPENSE')
                    and exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'account' and l.ims_id = a.id::text)));
end;
$$;
comment on function public.qbo_supplier_line_accounts() is '[qbo-bill-charge-1 · 판정 1189 · 1190 · 열쇠 QUICKBOOKS 보기] 공급처 인보이스 charge · other 줄의 QuickBooks 계정 설정 읽기 — can_edit(열쇠 qbo 쓰기) · lines 둘(지금 계정 · 문제 글 · 고친 사람) · accounts(고를 수 있는 계정 = 켜짐 ∧ QBO 짝 ∧ COSTOFGOODSSOLD · EXPENSE · 이름 순)';

create function public.qbo_supplier_line_account_set(p_line_kind text, p_code text, p_old text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare
  v_staff uuid := public.qbo_key_gate(true); v_realm text := public.qbo_realm_of();
  v_key  text := case p_line_kind when 'charge' then 'qbo_supplier_line_charge_account_code' when 'other' then 'qbo_supplier_line_other_account_code' end;
  v_code text := nullif(btrim(coalesce(p_code, '')), '');
  v_cur public.inv_config%rowtype; v_acc public.ref_account%rowtype; v_by_name text; v_changed boolean := false;
begin
  if v_key is null then raise exception 'line_kind must be charge or other (got %) — nothing was saved', coalesce(p_line_kind, 'null'); end if;
  if v_code is null then raise exception 'Choose an account — this setting cannot be empty — nothing was saved'; end if;
  select * into v_acc from public.ref_account a where a.code = v_code;
  if v_acc.id is null then raise exception 'Account % does not exist in IMS — nothing was saved', v_code; end if;
  if not v_acc.is_active then raise exception 'Account % % is switched off — choose an active account — nothing was saved', v_code, v_acc.name; end if;
  if coalesce(v_acc.account_type, '') not in ('COSTOFGOODSSOLD', 'EXPENSE') then
    raise exception 'Account % % is a % account — supplier charge and other lines go to a cost of goods sold or expense account — nothing was saved', v_code, v_acc.name, coalesce(v_acc.account_type, '(no type)');
  end if;
  if not exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'account' and l.ims_id = v_acc.id::text) then
    raise exception 'Account % % has no QuickBooks match — link it under Settings → QuickBooks matching first — nothing was saved', v_code, v_acc.name;
  end if;
  select * into v_cur from public.inv_config c where c.key = v_key for update;
  if not found then raise exception 'Setting % has no row — a migration seeds it first — nothing was saved', v_key; end if;
  if p_old is not null and p_old is distinct from v_cur.value then
    select s.name into v_by_name from public.ims_staff s where s.id = v_cur.updated_by;
    raise exception 'changed_elsewhere: the % line account was changed by % at % to "%" since this page loaded — reload and try again — nothing was saved',
      p_line_kind, coalesce(v_by_name, '(unknown)'), coalesce(to_char(v_cur.updated_at, 'YYYY-MM-DD HH24:MI'), '?'), left(v_cur.value, 80);
  end if;
  if v_cur.value is distinct from v_code then
    update public.inv_config set value = v_code, updated_at = now(), updated_by = v_staff where key = v_key;
    v_changed := true;
  end if;
  return public.qbo_supplier_line_account_row(p_line_kind) || jsonb_build_object('changed', v_changed, 'old_code', v_cur.value);
end;
$$;
comment on function public.qbo_supplier_line_account_set(text, text, text) is '[qbo-bill-charge-1 · 판정 1189 · 1190 · 열쇠 QUICKBOOKS 쓰기] 공급처 인보이스 charge | other 줄의 QuickBooks 계정 바꾸기 — 계정은 켜짐 ∧ QBO 짝 ∧ COSTOFGOODSSOLD · EXPENSE 만 · p_old = 화면이 본 값(다르면 changed_elsewhere · null 이면 검사 안 함) · 같은 값은 쓰지 않는다(changed false) · 이미 보낸 Bill 은 그대로 · 다음에 만드는 몸부터 새 계정';

-- ═══════════════ ④ 재발행 — qbo_bill_body(원본 DB prosrc 00a95650… · 바뀐 줄은 머리 주석 · 서명 무변) ═══════════════
create or replace function public.qbo_bill_body(p_invoice_id uuid, p_kind text default null) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_realm text := public.qbo_realm_of(); v_home text := coalesce(nullif(btrim((select c.value from public.inv_config c where c.key = 'base_currency')), ''), 'CAD');
  c_ginr constant text := '_1150040012_';
  v_i public.po_invoice%rowtype; v_m public.po_invoice_money%rowtype; v_s public.supplier%rowtype; v_for public.po_invoice%rowtype;
  v_kind text; v_ims_kind text; v_label text; v_cur text; v_vendor text; v_ap text; v_ap_cur text; v_ginr text; v_term text; v_doc text; v_due date; v_disc text; v_pos text; v_note text;
  v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_lines jsonb := '[]'::jsonb; v_tax_lines jsonb := '[]'::jsonb; v_tx jsonb; v_n int := 0; v_bad int; v_cut boolean := false; v_cents bigint;
  v_l record; v_g record;
  v_acct_charge text; v_acct_other text; v_skip int := 0;
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
  -- qbo-bill-charge-1(1189 ~ 1191): charge · other 줄은 설정 계정으로 보낸다 · 돈 안 내는 줄(is_payable false)은 뺀다 — 낼 줄이 없으면 보낼 것이 없다 · 설정 계정은 그 종류의 낼 줄이 있을 때만 읽는다
  select count(*) into v_skip from public.po_invoice_line l where l.po_invoice_id = p_invoice_id and not l.is_payable;
  if v_skip >= v_m.line_count then raise exception '% % has no payable lines — nothing is owed on it, so there is nothing to send to QuickBooks — nothing was sent', v_label, v_i.invoice_number; end if;
  if v_skip > 0 then v_warn := array_append(v_warn, format('%s line(s) marked not payable — left out of QuickBooks, which carries only the amount owed (1191)', v_skip)); end if;
  if exists (select 1 from public.po_invoice_line l where l.po_invoice_id = p_invoice_id and l.is_payable and l.line_kind = 'charge') then v_acct_charge := public.qbo_supplier_line_account('charge'); end if;
  if exists (select 1 from public.po_invoice_line l where l.po_invoice_id = p_invoice_id and l.is_payable and l.line_kind = 'other') then v_acct_other := public.qbo_supplier_line_account('other'); end if;
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
  -- 줄 = 낼 줄마다 · line_no 순(1116 · 1191) · goods: Description(SKU × 수량 @ 단가 · PO · 크레딧 사유 · 상호 없음) · 계정 GINR(1115) / charge · other: Description = 줄 글 · 계정 = 설정(1189 · 1190) · 세금 코드 = 줄 규칙(없으면 문서 규칙)
  for v_l in select l.line_kind, l.description, l.qty_ea, l.unit_price, round(l.qty_ea * l.unit_price, 2) as amt, coalesce(l.tax_rule_id, v_i.tax_rule_id) as rule_id, l.credit_reason, pr.sku, p.po_number
               from public.po_invoice_line l left join public.po_line pl on pl.id = l.po_line_id left join public.po p on p.id = pl.po_id left join public.product pr on pr.id = pl.product_id
              where l.po_invoice_id = p_invoice_id and l.is_payable order by l.line_no loop
    v_tx := public.qbo_purchase_tax(v_l.rule_id);
    v_n := v_n + 1;
    v_lines := v_lines || jsonb_build_object('DetailType', 'AccountBasedExpenseLineDetail', 'LineNum', v_n, 'Amount', v_l.amt,
                 'Description', left(case when v_l.line_kind = 'goods' then v_l.sku || ' × ' || trim_scale(v_l.qty_ea) || ' @ ' || trim_scale(v_l.unit_price) || ' · PO ' || v_l.po_number
                                     || case v_l.credit_reason when 'not_received' then ' · not received' when 'price_difference' then ' · price difference' else '' end else v_l.description end, 4000),
                 'AccountBasedExpenseLineDetail', jsonb_build_object('AccountRef', jsonb_build_object('value', case v_l.line_kind when 'goods' then v_ginr when 'charge' then v_acct_charge else v_acct_other end), 'TaxCodeRef', jsonb_build_object('value', v_tx->>'tax_code')));
  end loop;
  -- 인보이스 할인 = 음수 줄 따로(1117) · 세율 묶음마다 하나(po_tax_group.discount_amount · 세금이 묶음별로 셈해진다) · 이름 = 할인 이름들
  select string_agg(d.name || ' ' || trim_scale(d.percent) || '%', ' · ' order by d.seq) into v_disc from public.po_invoice_discount d where d.po_invoice_id = p_invoice_id;
  for v_g in select g.tax_rule_id, g.payable_discount as discount_amount from public.po_tax_group g where g.doc_kind = 'invoice' and g.doc_id = p_invoice_id and g.payable_discount <> 0 order by g.tax_rule loop
    v_tx := public.qbo_purchase_tax(v_g.tax_rule_id);
    v_n := v_n + 1;
    v_lines := v_lines || jsonb_build_object('DetailType', 'AccountBasedExpenseLineDetail', 'LineNum', v_n, 'Amount', -v_g.discount_amount, 'Description', left('Discount ' || coalesce(v_disc, ''), 4000),
                 'AccountBasedExpenseLineDetail', jsonb_build_object('AccountRef', jsonb_build_object('value', v_ginr), 'TaxCodeRef', jsonb_build_object('value', v_tx->>'tax_code')));
  end loop;
  -- 세금(E-15: QBO 는 보낸 세금을 그대로 받는다) — 묶음마다 TaxLine(매입 세율 ref · 2b1 거울엔 없다 → 4-4 Refresh 뒤) · 세금 0 묶음은 TaxLine 없음
  for v_g in select g.tax_rule_id, g.tax_rule, g.rate_pct, g.payable_taxable as taxable_amount, g.payable_tax as tax_amount from public.po_tax_group g where g.doc_kind = 'invoice' and g.doc_id = p_invoice_id and coalesce(g.payable_tax, 0) <> 0 order by g.tax_rule loop
    v_tx := public.qbo_purchase_tax(v_g.tax_rule_id);
    if v_tx->>'rate_ref' is null then raise exception 'QuickBooks tax code #% ("%") has no purchase tax rate on file — Settings → QuickBooks matching → Refresh list (tax codes), then retry — nothing was sent', v_tx->>'tax_code', v_g.tax_rule; end if;
    if (v_tx->>'rates')::int > 1 then v_warn := array_append(v_warn, format('tax code #%s has %s purchase rates — first rate #%s used', v_tx->>'tax_code', v_tx->>'rates', v_tx->>'rate_ref')); end if;
    v_tax_lines := v_tax_lines || jsonb_build_object('DetailType', 'TaxLineDetail', 'Amount', v_g.tax_amount,
                     'TaxLineDetail', jsonb_build_object('TaxRateRef', jsonb_build_object('value', v_tx->>'rate_ref'), 'PercentBased', true, 'TaxPercent', trim_scale(v_g.rate_pct), 'NetAmountTaxable', v_g.taxable_amount));
  end loop;
  select string_agg(distinct p.po_number, ', ' order by p.po_number) into v_pos from public.po_invoice_line l join public.po_line pl on pl.id = l.po_line_id join public.po p on p.id = pl.po_id where l.po_invoice_id = p_invoice_id;
  if v_i.doc_kind = 'credit' and v_i.credit_for_invoice_id is not null then select * into v_for from public.po_invoice f where f.id = v_i.credit_for_invoice_id; end if;
  v_note := 'IMS supplier ' || lower(v_label) || ' ' || v_i.invoice_number || coalesce(' · PO ' || v_pos, '') || coalesce(' · for invoice ' || v_for.invoice_number, '') || case when v_cut then ' · full number: ' || v_i.invoice_number else '' end;
  v_cents := round(v_m.payable_net * 100)::bigint;
  return jsonb_build_object('kind', v_kind, 'ims_kind', v_ims_kind, 'ims_id', p_invoice_id::text, 'name', v_i.invoice_number, 'doc_number', v_doc, 'supplier_id', v_s.id,
    'body', jsonb_strip_nulls(jsonb_build_object(
      'DocNumber', v_doc, 'TxnDate', to_char(v_i.invoice_date, 'YYYY-MM-DD'), 'DueDate', case when v_due is not null then to_char(v_due, 'YYYY-MM-DD') end,
      'VendorRef', case when v_vendor is not null then jsonb_build_object('value', v_vendor) end,
      'APAccountRef', jsonb_build_object('value', v_ap),
      'SalesTermRef', case when v_term is not null then jsonb_build_object('value', v_term) end,
      'CurrencyRef', jsonb_build_object('value', v_cur), 'ExchangeRate', case when v_cur <> v_home then trim_scale(v_i.exchange_rate) end,
      'PrivateNote', left(v_note, 4000), 'GlobalTaxCalculation', 'TaxExcluded', 'Line', v_lines,
      'TxnTaxDetail', jsonb_build_object('TotalTax', coalesce(v_m.payable_tax, 0)) || case when jsonb_array_length(v_tax_lines) > 0 then jsonb_build_object('TaxLine', v_tax_lines) else '{}'::jsonb end)),
    'needs', v_needs, 'warnings', to_jsonb(v_warn), 'line_count', jsonb_array_length(v_lines),
    'totals', jsonb_build_object('taxable', v_m.payable_taxable, 'tax', coalesce(v_m.payable_tax, 0), 'total', v_m.payable_net, 'currency', v_cur),
    'fingerprint', v_cents::text || '|' || v_cur,
    'lookup', jsonb_build_object('entity', case v_kind when 'bill' then 'Bill' else 'VendorCredit' end, 'doc_number', v_doc, 'vendor_ref', v_vendor, 'total_cents', v_cents, 'currency', v_cur));
end;
$$;
comment on function public.qbo_bill_body(uuid, text) is '[qbo-sync-4-3a · qbo-bill-charge-1 · 판정 1115 ~ 1118 · 1121 · 1127 · 1130 · 1189 ~ 1192 · grant 0] 공급처 인보이스 → Bill · 크레딧(doc_kind credit) → VendorCredit 몸 — 낼 줄마다(line_no 순) · goods = GINR · charge · other = 설정 계정(qbo_supplier_line_account) · 돈 안 내는 줄은 뺀다(줄 · 할인 · 세금 · 합계 · 지문 모두 낼 돈 기준) · 찍힌 합계 ≠ 줄 합이면 막음(1192 그대로) · claim · preview 가 부른다';

-- ═══════════════ ⑤ 권한 — 새 함수는 public · anon 회수 · 창구 둘만 authenticated ═══════════════
revoke all on function public.qbo_supplier_line_account(text), public.qbo_supplier_line_account_row(text), public.qbo_supplier_line_accounts(), public.qbo_supplier_line_account_set(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.qbo_supplier_line_accounts(), public.qbo_supplier_line_account_set(text, text, text) to authenticated;

-- ═══════════════ ⑥ 착지 — 새 몸 md5 · 권한 · 설정 두 줄 ═══════════════
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_bill_body') is distinct from '289121b97c9daf6d87fc719c19cdf44a' then v_bad := v_bad || ' qbo_bill_body(new md5)'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_bill_body', 'qbo_supplier_line_account', 'qbo_supplier_line_account_row', 'qbo_supplier_line_accounts', 'qbo_supplier_line_account_set')) <> 5 then v_bad := v_bad || ' (function count)'; end if;
  if (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '(default)'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_bill_body', 'qbo_supplier_line_account', 'qbo_supplier_line_account_row', 'qbo_supplier_line_accounts', 'qbo_supplier_line_account_set'))
     is distinct from 'qbo_bill_body:{postgres=X/postgres} qbo_supplier_line_account:{postgres=X/postgres} qbo_supplier_line_account_row:{postgres=X/postgres} qbo_supplier_line_account_set:{postgres=X/postgres,authenticated=X/postgres} qbo_supplier_line_accounts:{postgres=X/postgres,authenticated=X/postgres}' then v_bad := v_bad || ' (acl)'; end if;
  if (select string_agg(c.key || '=' || c.value, ' ' order by c.key) from public.inv_config c where c.key in ('qbo_supplier_line_charge_account_code', 'qbo_supplier_line_other_account_code'))
     is distinct from 'qbo_supplier_line_charge_account_code=_95_ qbo_supplier_line_other_account_code=_95_' then v_bad := v_bad || ' (settings)'; end if;
  if v_bad <> '' then raise exception 'qbo-bill-charge-1 landing check failed —%. Nothing was changed.', v_bad; end if;
end $$;
