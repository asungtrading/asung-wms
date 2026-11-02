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
-- qbo-sync-2b1 — 인보이스 보내기 DB 몸 · 발행 · 취소 트리거 · 일감 창구 재발행 · 거래 짝 채우기 (2026-11-01 · 판정 935 ~ 946 · 951 · 지시서 ~/asung/prompts/qbo-sync-2b.md · 이견 1 ~ 16 답 반영)
--   경계(이견 1): 2b1 = DB 가 몸 · 상태 · 거래 짝을 다 만든다 / 2b2 = EF 가 나른다(invoice POST · DocNumber 멱등 · 응답 합계 · void · cron send) · 같은 밤에 이어 적용
--   ⚠️ EF 배포 전 가드: qbo_job_claim(p_limit, p_kinds) 의 p_kinds 기본값 = {customer, item} — 2a′ EF 는 p_limit 만 보내므로 invoice 일감을 잡지 않는다 · 2b2 EF 가 {customer, item, invoice, invoice_void} 를 명시한다(설정 키 없음 · EF 가 아는 kind 만)
--   A 표 · 칸: qbo_entity.detail jsonb(TaxCode 의 SalesTaxRateList — TxnTaxDetail 의 TaxRateRef 를 DB 가 안다 · 이견 8 안 A · 2b2 EF pull 이 TaxCode 칸 목록에 SalesTaxRateList 를 더한다) · qbo_txn.mismatch text(942 — QBO 응답 합계가 IMS 와 다르면 sent + 여기에 글 · 자동 void 없음)
--     qbo_entity_upsert 재발행 = 1a 바이트 그대로 + detail(SalesTaxRateList 가 온 행만 · 안 오면 옛 값 유지)
--   B 속 함수: qbo_send_since_ok(date)(drive_since_ok 바이트 꼴 · inv_config qbo_send_since) · qbo_invoice_body(p_invoice_id)(935 ~ 946 · 951 · needs[] · warnings[] · totals) · qbo_void_body(p_invoice_id)(qbo_txn 의 Id · SyncToken) · qbo_job_open_or_add(kind, ims_id, by)(2a qbo_job_add 의 몸 — 문 없이 · claim 의 needs 가 부른다)
--     인보이스 몸: CustomerRef = 매장(so_invoice_order.customer_id · 둘 이상이면 실패 「cancel and reissue per store」 · 이견 4) · SalesTermRef(qbo_link payment_term · 없으면 실패 · 결제조건 없으면 생략 + 경고) · CurrencyRef · BillAddr(so_invoice.bill_to_* · Line1 = 이름 · 946) · ShipAddr(첫 오더 ship_to_* · 다른 오더와 다르면 경고) · BillEmail(doc_mail_recipient(청구처) · 없으면 생략 + 경고 · 이견 5)
--             PrivateNote = 「Customer Reference: <ref…>」(ref 없는 오더는 so_number) · CustomerMemo = 같은 것 + 「, <매장 이름>」(939 · 이견 13) · ShipDate · TrackingNum(첫 오더) · GlobalTaxCalculation TaxExcluded
--             줄 = so_invoice_line 순서 그대로: product → qbo_link product(없으면 needs item) · Description = 이름 + 「 (list x, y% off)」(이견 6) / surcharge → qbo_link charge surcharge(없으면 needs item 'surcharge' · 944) / order_discount → charge discount(2170 · 음수 · 없으면 실패) / charge → service_id 면 qbo_link service · 계정 _99_ 면 charge freight · 그 밖 계정은 charge 'acct:<code>'(951 · 사람 짝 · 없으면 실패 + 안내) / charge_discount → 그 운임 줄과 같은 Item · 음수(943) · 0 원 줄 그대로(938) · TaxCodeRef = 그 오더 세금 규칙 → qbo_link tax_rule(없으면 실패)
--             TxnTaxDetail = TotalTax(so_invoice.tax_amount) + TaxLine(세금 규칙마다 · TaxRateRef = qbo_entity.detail 의 첫 TaxRateDetail · PercentBased · TaxPercent · NetAmountTaxable = 그 규칙 오더들의 taxable 합 · Amount = tax 합 · detail 없으면 실패 「Refresh list」) — ⚠️ QBO 캐나다판이 보낸 TaxLine 을 존중하는지는 짐작(2b2 첫 실물 ③ 에서 확인 · 다르면 응답 대조가 mismatch 로 잡는다)
--   C 트리거 둘: so_invoice_qbo_job(AFTER INSERT DEFERRABLE INITIALLY DEFERRED · drive_archive_on_issue 꼴 · kind opening · 같은 트랜잭션 취소 · since 전 · 연결 없음 은 조용히 return · 오류는 삼켜 발행을 막지 않는다) → qbo_job(invoice · queued · by_staff = issued_by)
--                so_invoice_qbo_cancel(AFTER UPDATE OF status · drive_rename_on_cancel 꼴) → 열린 invoice 일감이 queued · blocked · failed 면 skipped(note 「cancelled before sending: …」) · sending · unknown 이면 invoice_void 일감 blocked_by 그 일감(이견 3) · 열린 일감 없고 qbo_txn 이 있으면(보내졌다) invoice_void queued · 둘 다 없으면 아무것도(since 전 · 이월)
--   D 창구 재발행: qbo_job_claim(p_limit, p_kinds) — drop(int) + create · 몸 = 2a 바이트 + p_kinds 거르기 + invoice · invoice_void 몸 + needs(이견 11: need 일감을 전부 쌓고(open_or_add · 부모 손님은 그 안에서) 인보이스 일감은 blocked(blocked_by = 마지막 need) · 다음 바퀴 ② 가 풀면 ④ 가 몸을 다시 만들어 남은 need 가 있으면 또 blocked · need 몸이 거부하면(941 비활성 Item · 활성 Sku 사람 짝) 인보이스 일감 failed + 그 까닭)
--                 qbo_job_done(+ p_total_amt · p_total_tax) — drop(7) + create(9) · invoice → qbo_txn insert … on conflict(ims 키) do update(unknown 을 조회로 푼 뒤에도) · 합계 대조(942 · total · tax_amount 1 센트라도 다르면 mismatch + 일감 warning · 상태는 sent) · QBO Id 가 이미 다른 IMS 인보이스의 짝이면 failed + 사람 말 / invoice_void → qbo_txn.voided_at · sync_token / 자식 풀기는 kind 무관(void 일감이 invoice 일감에 blocked)
--                 qbo_job_add 재발행 = 문 + 검사 + open_or_add · qbo_job_list 재발행 = 2a 바이트 + invoice · credit 의 ims_name(번호 · 청구처 · 통화 · 총액) + 거래 짝 칸(txn_qbo_id · txn_total_amt · txn_total_tax · txn_mismatch · txn_voided_at)(이견 16)
--   E 읽기 창구: qbo_txn_of(p_kind, p_ims_id) — 로그인한 활성 직원 누구나(인보이스 화면 꼬리표 · 화면은 대화 Claude) · 거래 짝 + 마지막 일감 상태 · 없으면 null
--   무접촉: qbo_customer_body · qbo_item_body · qbo_job_fail · qbo_job_unknown(2a′) · qbo_job_retry · qbo_job_skip · 1a 창구 · 화면 · EF(2b2) · so_invoice_issue · so_invoice_cancel(트리거만 얹는다) · 첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사(G0) · 새 함수 grant 명시
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261102040000_qbo_sync_2b1_invoice_jobs.sql && supabase migration repair --status applied 20261102040000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=supabase/migrations/20261102040000_qbo_sync_2b1_invoice_jobs.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2b1_check.sql

-- ═══ A) 표 · 칸 ═══
alter table public.qbo_entity add column detail jsonb;
comment on column public.qbo_entity.detail is 'qbo-sync-2b1: 종류별 덧붙임 — TaxCode 만 SalesTaxRateList(TaxRateDetail[] · TaxRateRef) · 몸 함수가 TxnTaxDetail 의 TaxRateRef 를 여기서 읽는다 · pull 이 SalesTaxRateList 를 받은 행만 채운다(안 오면 옛 값 유지) · 연락처 · 금액 없음(933 · 934 그대로)';
alter table public.qbo_txn add column mismatch text;
alter table public.qbo_txn add column updated_by uuid references public.ims_staff (id);                                                 -- ⚠️ 2a 잠복 결함: qbo_txn_touch(ims_touch) 가 new.updated_by 를 쓰는데 칸이 없어 모든 UPDATE 가 「record new has no field updated_by」 로 죽었다(2a 검사는 insert 만) — 2b1 시험 D9 가 잡음
comment on column public.qbo_txn.updated_by is 'qbo-sync-2b1: ims_touch 트리거가 채운다(2a 에 빠져 있어 UPDATE 가 전부 실패하던 칸) · service_role 길에서는 null';
comment on column public.qbo_txn.mismatch is 'qbo-sync-2b1 판정 942: QBO 가 돌려준 TotalAmt · TotalTax 가 IMS 총액 · 세금과 1 센트라도 다르면 그 글(상태는 sent · 자동 void 없음 · 사람이 QBO 에서 확인) · 같으면 null';

create or replace function public.qbo_entity_upsert(p_realm text, p_type text, p_rows jsonb, p_next_start int default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
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
         coalesce((r->>'Active')::boolean, true), r->>'SyncToken', now(), null, case when p_type = 'TaxCode' and r ? 'SalesTaxRateList' then r->'SalesTaxRateList' end
  from jsonb_array_elements(p_rows) r
  on conflict (realm_id, qbo_type, qbo_id) do update set name = excluded.name, sku = excluded.sku, parent_id = excluded.parent_id, fully_qualified_name = excluded.fully_qualified_name,
    active = excluded.active, sync_token = excluded.sync_token, fetched_at = now(), gone_at = null, detail = coalesce(excluded.detail, public.qbo_entity.detail);
  get diagnostics v_n = row_count;
  update public.qbo_pull_state s set received = s.received + v_n, pages = s.pages + 1, next_start = coalesce(p_next_start, s.next_start), updated_at = now()
    where s.realm_id = p_realm and s.qbo_type = p_type returning * into v_s;
  return jsonb_build_object('qbo_type', p_type, 'received_now', v_n, 'received', v_s.received, 'pages', v_s.pages, 'next_start', v_s.next_start);
end;
$$;
comment on function public.qbo_entity_upsert(text, text, jsonb, int) is 'qbo-sync-1a: 받기 한 쪽 upsert(EF pull · 사용자 JWT · 문 qbo_sync_gate) — Id · Name(DisplayName) 필수 · gone_at null 로 되살림 · [2b1] TaxCode 행의 SalesTaxRateList 를 detail 에(안 오면 옛 값 유지)';

-- 951 사람 짝 자리: 짝 화면 · qbo_link_set 은 qbo_ims_rows 가 아는 ims_id 만 받는다(1a) → charge 종류에 「acct:<code>」 행(계정 비용 줄 · 비용 줄이 실제로 쓴 계정 또는 이미 짝인 것만 · _99_ 운임 제외) — 1a 바이트 그대로 + union 한 줄
create or replace function public.qbo_ims_rows(p_kind text) returns table (ims_id text, ims_name text, ims_code text, ims_active boolean)
  language sql stable security definer rows 20000 set search_path = public, pg_temp
as $$
  select a.id::text, a.name, a.code, a.is_active from public.ref_account a where p_kind = 'account'
  union all select t.id::text, t.name, t.direction, t.is_active from public.ref_tax_rule t where p_kind = 'tax_rule'
  union all select pt.id::text, pt.name, null, pt.is_active from public.ref_payment_term pt where p_kind = 'payment_term'
  union all select m.v, m.v, m.q, true from (values ('cheque', 'Cheque'), ('debit_card', 'Debit'), ('e_transfer', 'E-Transfer'), ('wire', 'Wire'), ('cash', 'Cash'), ('shopify', 'Shopify'), ('direct_deposit', 'EFT (ACH)'), ('credit_card', null)) m(v, q) where p_kind = 'payment_method'
  union all select c.id::text, c.name, null, c.is_active from public.customer c where p_kind = 'customer'
  union all select s.id::text, s.name, null, s.is_active from public.supplier s where p_kind = 'supplier'
  union all select p.id::text, p.name, p.sku, p.is_active from public.product p where p_kind = 'product'
  union all select v, v, null, true from unnest(array['freight', 'discount', 'surcharge', 'freight_discount']) v where p_kind = 'charge'
  union all select 'acct:' || a.code, 'Charge on account ' || a.code || ' ' || a.name, a.code, a.is_active from public.ref_account a
             where p_kind = 'charge' and a.code <> '_99_'
               and (exists (select 1 from public.so_charge c where c.account_code = a.code and c.service_id is null)
                    or exists (select 1 from public.qbo_link l where l.ims_kind = 'charge' and l.ims_id = 'acct:' || a.code))
  union all select r.id::text, r.name, null, r.is_active from public.ref_service r where p_kind = 'service'
$$;
comment on function public.qbo_ims_rows(text) is 'qbo-sync-1a(속 · grant 0): 종류별 IMS 행(ims_id · 이름 · 코드 · 활성) — 짝 화면 · 자동 짝 · qbo_link_set 이 본다 · [2b1 판정 951] charge 에 「acct:<code>」 행(비용 줄이 쓴 계정 · 또는 이미 짝인 것 · _99_ 운임 제외) — 카드 수수료 같은 계정 비용 줄의 Item 짝 자리';

-- ═══ B) 속 함수 — since · 인보이스 몸 · void 몸 · 일감 쌓기(문 없이) ═══
create function public.qbo_send_since_ok(p_date date) returns boolean
  language sql stable security definer set search_path = public, pg_temp
as $$
  select p_date is not null and nullif((select c.value from public.inv_config c where c.key = 'qbo_send_since'), '') is not null
         and p_date >= to_date((select c.value from public.inv_config c where c.key = 'qbo_send_since'), 'YYYY-MM-DD');
$$;
comment on function public.qbo_send_since_ok(date) is 'qbo-sync-2b1: inv_config qbo_send_since(YYYY-MM-DD) 가 있고 발행일이 그 날 이후면 true — 비어 있으면 늘 false(아무것도 안 쌓는다) · drive_since_ok 와 같은 꼴';

create function public.qbo_invoice_body(p_invoice_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_realm text := public.qbo_realm_of();
  v_i public.so_invoice%rowtype; v_o public.so_invoice_order%rowtype; v_store public.customer%rowtype; v_so public.so%rowtype;
  v_n_orders int; v_n_stores int; v_cust_ref text; v_term_ref text; v_tax_ref text; v_rate_ref text; v_item text; v_cur text;
  v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_lines jsonb := '[]'::jsonb; v_tax_lines jsonb := '[]'::jsonb;
  v_refs text; v_email text; v_bill jsonb; v_ship jsonb; v_detail jsonb; v_desc text; v_qty numeric; v_up numeric; v_need jsonb;
  v_l record; v_t record;
begin
  select * into v_i from public.so_invoice i where i.id = p_invoice_id;
  if v_i.id is null then raise exception 'No IMS invoice % — nothing was sent', p_invoice_id; end if;
  if v_i.kind = 'opening' then raise exception 'Invoice % was carried forward from the previous system — it is already in QuickBooks (786) — nothing was sent', v_i.invoice_number; end if;
  if v_i.status <> 'issued' then raise exception 'Invoice % is % — only an issued invoice is sent to QuickBooks — nothing was sent', v_i.invoice_number, v_i.status; end if;
  select count(*), count(distinct o.customer_id) into v_n_orders, v_n_stores from public.so_invoice_order o where o.invoice_id = v_i.id and o.cancelled_at is null;
  if v_n_orders = 0 then raise exception 'Invoice % has no orders — nothing was sent', v_i.invoice_number; end if;
  if v_n_stores > 1 then raise exception 'Invoice % covers % stores — cancel and reissue per store (one QuickBooks customer per invoice) — nothing was sent', v_i.invoice_number, v_n_stores; end if;
  select * into v_o from public.so_invoice_order o where o.invoice_id = v_i.id and o.cancelled_at is null order by o.so_number limit 1;
  select * into v_so from public.so s where s.id = v_o.so_id;
  select * into v_store from public.customer c where c.id = v_o.customer_id;
  if v_store.id is null then raise exception 'Invoice % — the store (order customer) is missing — nothing was sent', v_i.invoice_number; end if;
  -- 935 CustomerRef = 매장 · 짝 없으면 need(손님 일감 · 부모는 open_or_add 가)
  select l.qbo_id into v_cust_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_store.id::text;
  if v_cust_ref is null then v_needs := v_needs || jsonb_build_object('kind', 'customer', 'ims_id', v_store.id::text, 'name', v_store.name); end if;
  -- 결제조건 · 기한
  if v_i.payment_term_id is not null then
    select l.qbo_id into v_term_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'payment_term' and l.ims_id = v_i.payment_term_id::text;
    if v_term_ref is null then raise exception 'Payment term "%" has no QuickBooks match — link it under Settings → QuickBooks matching — nothing was sent', v_i.payment_term_name; end if;
  else
    v_warn := array_append(v_warn, 'no payment term on the invoice — QuickBooks default terms');
  end if;
  if v_i.due_on is null then v_warn := array_append(v_warn, 'no due date on the invoice'); end if;
  v_cur := coalesce(nullif(btrim(coalesce(v_i.currency_code, '')), ''), (select c.code from public.ref_currency c where c.id = v_i.currency_id));
  if v_cur is null then raise exception 'Invoice % has no currency code — nothing was sent', v_i.invoice_number; end if;
  -- 936 · 946 주소 · 이메일(값은 문서에 찍힌 그대로)
  v_bill := jsonb_strip_nulls(jsonb_build_object('Line1', nullif(btrim(coalesce(v_i.bill_to_name, '')), ''), 'Line2', nullif(btrim(coalesce(v_i.bill_to_line1, '')), ''), 'Line3', nullif(btrim(coalesce(v_i.bill_to_line2, '')), ''),
                                                 'City', nullif(btrim(coalesce(v_i.bill_to_city, '')), ''), 'CountrySubDivisionCode', nullif(btrim(coalesce(v_i.bill_to_state_province, '')), ''), 'PostalCode', nullif(btrim(coalesce(v_i.bill_to_postal_code, '')), ''),
                                                 'Country', public.qbo_country_name(v_i.bill_to_country)));
  if nullif(btrim(coalesce(v_i.bill_to_line1, '')), '') is null then v_warn := array_append(v_warn, 'no billing address on the invoice'); end if;
  if public.qbo_country_name(v_i.bill_to_country) is not null and public.qbo_country_name(v_i.bill_to_country) not in ('Canada', 'USA') then v_warn := array_append(v_warn, format('billing country "%s" sent as is', public.qbo_country_name(v_i.bill_to_country))); end if;
  v_ship := jsonb_strip_nulls(jsonb_build_object('Line1', nullif(btrim(coalesce(v_o.ship_to_company, '')), ''), 'Line2', nullif(btrim(coalesce(v_o.ship_to_line1, '')), ''), 'Line3', nullif(btrim(coalesce(v_o.ship_to_line2, '')), ''),
                                                 'City', nullif(btrim(coalesce(v_o.ship_to_city, '')), ''), 'CountrySubDivisionCode', nullif(btrim(coalesce(v_o.ship_to_state_province, '')), ''), 'PostalCode', nullif(btrim(coalesce(v_o.ship_to_postal_code, '')), ''),
                                                 'Country', public.qbo_country_name(v_o.ship_to_country)));
  if v_ship = '{}'::jsonb then v_ship := null; v_warn := array_append(v_warn, 'no ship-to address on the first order'); end if;
  if v_n_orders > 1 and exists (select 1 from public.so_invoice_order o where o.invoice_id = v_i.id and o.cancelled_at is null and o.id <> v_o.id
                                  and (o.ship_to_company, o.ship_to_line1, o.ship_to_line2, o.ship_to_city, o.ship_to_state_province, o.ship_to_postal_code, o.ship_to_country)
                                      is distinct from (v_o.ship_to_company, v_o.ship_to_line1, v_o.ship_to_line2, v_o.ship_to_city, v_o.ship_to_state_province, v_o.ship_to_postal_code, v_o.ship_to_country)) then
    v_warn := array_append(v_warn, 'ship-to differs between orders — first order (' || v_o.so_number || ') used');
  end if;
  v_email := public.doc_mail_recipient(v_i.bill_to_customer_id)->>'to';
  if v_email is null then v_warn := array_append(v_warn, 'no email on file for the bill-to customer'); end if;
  -- 939 메모 — ref 없는 오더는 so_number
  select string_agg(coalesce(nullif(btrim(s.ref), ''), o.so_number), ', ' order by o.so_number) into v_refs
    from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_i.id and o.cancelled_at is null;
  -- 942 세금 — 규칙마다 TaxLine(TaxRateRef 는 거울 detail)
  for v_t in select o.tax_rule_id, o.tax_rule, max(o.rate_pct) as rate, sum(o.taxable_amount) as taxable, sum(o.tax_amount) as tax
               from public.so_invoice_order o where o.invoice_id = v_i.id and o.cancelled_at is null group by o.tax_rule_id, o.tax_rule order by o.tax_rule loop
    select l.qbo_id into v_tax_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = v_t.tax_rule_id::text;
    if v_tax_ref is null then raise exception 'Tax rule "%" has no QuickBooks tax code — link it under Settings → QuickBooks matching — nothing was sent', v_t.tax_rule; end if;
    select e.detail into v_detail from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'TaxCode' and e.qbo_id = v_tax_ref;
    v_rate_ref := nullif(btrim(coalesce(v_detail->'TaxRateDetail'->0->'TaxRateRef'->>'value', '')), '');
    if v_rate_ref is null then raise exception 'QuickBooks tax code #% ("%") has no tax rate on file — Settings → QuickBooks matching → Refresh list (tax codes), then retry — nothing was sent', v_tax_ref, v_t.tax_rule; end if;
    if jsonb_array_length(coalesce(v_detail->'TaxRateDetail', '[]'::jsonb)) > 1 then v_warn := array_append(v_warn, format('tax code #%s has %s rates — first rate #%s used', v_tax_ref, jsonb_array_length(v_detail->'TaxRateDetail'), v_rate_ref)); end if;
    v_tax_lines := v_tax_lines || jsonb_build_object('DetailType', 'TaxLineDetail', 'Amount', v_t.tax,
                     'TaxLineDetail', jsonb_build_object('TaxRateRef', jsonb_build_object('value', v_rate_ref), 'PercentBased', true, 'TaxPercent', trim_scale(v_t.rate), 'NetAmountTaxable', v_t.taxable));
  end loop;
  -- 줄 — so_invoice_line 순서 그대로
  for v_l in select l.*, o.tax_rule_id, sl.product_id, c.service_id, c.account_code as charge_acct, c.name as charge_name
               from public.so_invoice_line l join public.so_invoice_order o on o.id = l.invoice_order_id
               left join public.so_line sl on sl.id = l.so_line_id left join public.so_charge c on c.id = l.so_charge_id
              where l.invoice_id = v_i.id and o.cancelled_at is null order by l.line_no loop
    select l.qbo_id into v_tax_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = v_l.tax_rule_id::text;
    v_item := null; v_need := null; v_desc := v_l.description; v_qty := 1; v_up := v_l.amount;
    if v_l.kind = 'product' then
      if v_l.product_id is null then raise exception 'Invoice % line % has no product — nothing was sent', v_i.invoice_number, v_l.line_no; end if;
      select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'product' and l.ims_id = v_l.product_id::text;
      if v_item is null then v_need := jsonb_build_object('kind', 'item', 'ims_id', v_l.product_id::text, 'name', v_l.sku); end if;
      if coalesce(v_l.discount_pct, 0) <> 0 and v_l.list_price is not null then v_desc := coalesce(v_desc, v_l.sku) || format(' (list %s, %s%% off)', trim_scale(v_l.list_price), trim_scale(v_l.discount_pct)); end if;
      v_qty := v_l.qty; v_up := coalesce(v_l.unit_price, 0);
    elsif v_l.kind = 'surcharge' then
      select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'surcharge';
      if v_item is null then v_need := jsonb_build_object('kind', 'item', 'ims_id', 'surcharge', 'name', 'Tariff Surcharge'); end if;
      v_qty := v_l.qty; v_up := coalesce(v_l.unit_price, 0);
    elsif v_l.kind = 'order_discount' then
      select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'discount';
      if v_item is null then raise exception 'IMS order discount has no QuickBooks item — link "discount" to the Discount item under Settings → QuickBooks matching — nothing was sent'; end if;
    elsif v_l.kind in ('charge', 'charge_discount') then
      if v_l.service_id is not null then
        select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'service' and l.ims_id = v_l.service_id::text;
        if v_item is null then raise exception 'Service "%" has no QuickBooks item — link it under Settings → QuickBooks matching — nothing was sent', v_l.charge_name; end if;
      elsif nullif(btrim(coalesce(v_l.charge_acct, '')), '') is null then
        raise exception 'Charge "%" has no account — nothing was sent', v_l.charge_name;
      elsif v_l.charge_acct = '_99_' then
        select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'freight';
        if v_item is null then raise exception 'IMS freight has no QuickBooks item — link "freight" to the Freight item under Settings → QuickBooks matching — nothing was sent'; end if;
      else
        select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'acct:' || v_l.charge_acct;
        if v_item is null then raise exception 'Charge "%" on account % has no QuickBooks item — link account item "acct:%" to a QuickBooks item under Settings → QuickBooks matching (951) — nothing was sent', v_l.charge_name, v_l.charge_acct, v_l.charge_acct; end if;
      end if;
      if v_l.kind = 'charge' and v_l.qty is not null then v_qty := v_l.qty; v_up := v_l.unit_price; end if;
    else
      raise exception 'Invoice % line % has unknown kind % — nothing was sent', v_i.invoice_number, v_l.line_no, v_l.kind;
    end if;
    if v_need is not null and not (v_needs @> jsonb_build_array(v_need)) then v_needs := v_needs || v_need; end if;
    v_lines := v_lines || jsonb_build_object('DetailType', 'SalesItemLineDetail', 'LineNum', v_l.line_no, 'Amount', v_l.amount, 'Description', left(coalesce(v_desc, ''), 4000),
                 'SalesItemLineDetail', jsonb_strip_nulls(jsonb_build_object('ItemRef', case when v_item is not null then jsonb_build_object('value', v_item) end, 'Qty', trim_scale(v_qty), 'UnitPrice', trim_scale(v_up),
                                                                             'TaxCodeRef', case when v_tax_ref is not null then jsonb_build_object('value', v_tax_ref) end)));
  end loop;
  if jsonb_array_length(v_lines) = 0 then raise exception 'Invoice % has no lines — nothing was sent', v_i.invoice_number; end if;
  return jsonb_build_object('kind', 'invoice', 'ims_kind', 'invoice', 'ims_id', p_invoice_id::text, 'name', v_i.invoice_number, 'doc_number', v_i.invoice_number, 'store_customer_id', v_store.id,
    'body', jsonb_strip_nulls(jsonb_build_object(
      'DocNumber', v_i.invoice_number, 'TxnDate', to_char(v_i.issued_on, 'YYYY-MM-DD'), 'DueDate', to_char(v_i.due_on, 'YYYY-MM-DD'),
      'CustomerRef', case when v_cust_ref is not null then jsonb_build_object('value', v_cust_ref) end,
      'SalesTermRef', case when v_term_ref is not null then jsonb_build_object('value', v_term_ref) end,
      'CurrencyRef', jsonb_build_object('value', v_cur),
      'BillAddr', case when v_bill <> '{}'::jsonb then v_bill end, 'ShipAddr', v_ship, 'BillEmail', case when v_email is not null then jsonb_build_object('Address', v_email) end,
      'PrivateNote', 'Customer Reference: ' || v_refs, 'CustomerMemo', jsonb_build_object('value', 'Customer Reference: ' || v_refs || ', ' || v_store.name),
      'ShipDate', to_char((v_so.shipped_at at time zone 'America/Toronto')::date, 'YYYY-MM-DD'), 'TrackingNum', nullif(btrim(coalesce(v_so.tracking_number, '')), ''),
      'GlobalTaxCalculation', 'TaxExcluded', 'Line', v_lines,
      'TxnTaxDetail', jsonb_build_object('TotalTax', v_i.tax_amount, 'TaxLine', v_tax_lines))),
    'needs', v_needs, 'warnings', to_jsonb(v_warn), 'line_count', jsonb_array_length(v_lines),
    'totals', jsonb_build_object('taxable', v_i.taxable_amount, 'tax', v_i.tax_amount, 'total', v_i.total));
end;
$$;
comment on function public.qbo_invoice_body(uuid) is 'qbo-sync-2b1 판정 935 ~ 946 · 951: IMS 인보이스 → QBO Invoice 만들기 몸 — CustomerRef = 매장(so_invoice_order.customer_id · 둘 이상이면 실패) · SalesTermRef · CurrencyRef · BillAddr · ShipAddr(첫 오더) · BillEmail(doc_mail_recipient) · 메모 둘(939) · 줄 = so_invoice_line 그대로(ItemRef 는 qbo_link product · charge(surcharge · discount · freight · acct:<code>) · service · TaxCodeRef = 오더 규칙) · TxnTaxDetail(TotalTax + TaxLine · TaxRateRef 는 qbo_entity.detail) · 돌려주는 것 = { body · needs[{kind customer|item · ims_id}] · warnings · totals · line_count } · 짝이 없어 만들어야 하면 needs(claim 이 일감으로) · 사람 짝이 필요하면 예외(failed)';

create function public.qbo_void_body(p_invoice_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_t public.qbo_txn%rowtype; v_i public.so_invoice%rowtype;
begin
  select * into v_i from public.so_invoice i where i.id = p_invoice_id;
  if v_i.id is null then raise exception 'No IMS invoice % — nothing was sent', p_invoice_id; end if;
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = p_invoice_id::text;
  if v_t.id is null then raise exception 'Invoice % was never sent to QuickBooks — nothing to void', v_i.invoice_number; end if;
  if v_t.voided_at is not null then raise exception 'Invoice % (QuickBooks #%) is already voided — nothing was sent', v_i.invoice_number, v_t.qbo_id; end if;
  return jsonb_build_object('kind', 'invoice_void', 'ims_kind', 'invoice', 'ims_id', p_invoice_id::text, 'name', v_i.invoice_number, 'doc_number', v_t.doc_number, 'qbo_id', v_t.qbo_id,
    'body', jsonb_strip_nulls(jsonb_build_object('Id', v_t.qbo_id, 'SyncToken', v_t.sync_token)), 'needs', '[]'::jsonb,
    'warnings', case when v_t.sync_token is null then '["no SyncToken on file — the sender reads the invoice first"]'::jsonb else '[]'::jsonb end);
end;
$$;
comment on function public.qbo_void_body(uuid) is 'qbo-sync-2b1: 취소된 IMS 인보이스 → QBO Invoice void 몸 — qbo_txn 의 Id · SyncToken(없으면 경고 · EF 가 DocNumber 로 읽어 채운다) · 보내진 적 없으면 · 이미 void 면 예외(failed)';

create function public.qbo_job_open_or_add(p_kind text, p_ims_id text, p_by uuid) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_b jsonb; v_ims_kind text; v_j public.qbo_job%rowtype; v_parent jsonb; v_state text := 'queued'; v_blocked uuid;
begin
  if p_kind not in ('customer', 'item') then raise exception 'kind must be customer or item (invoice and credit jobs are queued by issuing) — nothing was saved'; end if;
  if nullif(btrim(coalesce(p_ims_id, '')), '') is null then raise exception 'ims_id is required — nothing was saved'; end if;
  if p_kind = 'customer' then
    begin v_b := public.qbo_customer_body(p_ims_id::uuid); exception when invalid_text_representation then raise exception 'ims_id must be a customer id (got %) — nothing was saved', p_ims_id; end;
    if exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = p_ims_id) then raise exception 'IMS customer is already linked to a QuickBooks customer — nothing was saved'; end if;
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
$$;
comment on function public.qbo_job_open_or_add(text, text, uuid) is 'qbo-sync-2b1(속 · grant 0): 손님 · Item 만들기 일감 — 2a qbo_job_add 의 몸을 문 없이(열쇠 창구 qbo_job_add 와 claim 의 needs 가 부른다) · 열린 일감이 있으면 그것(existing true) · 부모 손님 짝이 없으면 부모 일감 먼저 + blocked · 몸이 거부하면 예외';

-- ═══ C) 트리거 둘 — 발행(DEFERRED · 삼킴) · 취소(status 갱신) ═══
create function public.qbo_job_on_invoice_issue() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_realm text; v_status text;
begin
  if new.kind = 'opening' then return null; end if;                                                                                      -- 786 · 341: 이월 인보이스는 보내지 않는다
  select i.status into v_status from public.so_invoice i where i.id = new.id;
  if v_status is distinct from 'issued' then return null; end if;                                                                        -- 같은 트랜잭션에서 취소됐으면 아무것도
  if not public.qbo_send_since_ok(new.issued_on) then return null; end if;                                                               -- qbo_send_since 비었거나 그 전이면 아무것도
  select c.realm_id into v_realm from public.qbo_connection c where c.singleton;
  if v_realm is null then return null; end if;                                                                                           -- 연결 없음 — 조용히
  begin
    insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'invoice', 'invoice', new.id::text, 'queued', new.issued_by)
    on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
  exception when others then                                                                                                             -- 발행을 막지 않는다 — 흔적을 failed 일감으로
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff) values (v_realm, 'invoice', 'invoice', new.id::text, 'failed', left('could not queue: ' || sqlerrm, 2000), new.issued_by)
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$$;
comment on function public.qbo_job_on_invoice_issue() is 'qbo-sync-2b1: so_invoice AFTER INSERT DEFERRABLE INITIALLY DEFERRED — 발행 커밋 때 qbo_job(invoice · queued) 하나 · kind opening · 같은 트랜잭션 취소 · qbo_send_since 전 · 연결 없음은 조용히 · 오류는 삼켜 발행을 막지 않는다(failed 일감으로 흔적)';

create function public.qbo_job_on_invoice_cancel() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_realm text; v_j public.qbo_job%rowtype; v_t public.qbo_txn%rowtype;
begin
  if new.status <> 'cancelled' or old.status = 'cancelled' then return null; end if;
  if new.kind = 'opening' then return null; end if;
  select c.realm_id into v_realm from public.qbo_connection c where c.singleton;
  if v_realm is null then return null; end if;
  begin
    select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'invoice' and j.ims_kind = 'invoice' and j.ims_id = new.id::text and j.state not in ('sent', 'skipped') for update;
    if v_j.id is not null and v_j.state in ('queued', 'blocked', 'failed') then                                                          -- 아직 안 나갔다 — 건너뛴다(이견 3)
      update public.qbo_job j set state = 'skipped', claimed_at = null, note = left('cancelled before sending: ' || coalesce(new.cancel_note, ''), 2000), updated_by = new.cancelled_by where j.id = v_j.id;
    elsif v_j.id is not null then                                                                                                        -- sending · unknown — 닿았는지 모른다 → void 일감을 그 뒤에
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'invoice_void', 'invoice', new.id::text, 'blocked', v_j.id, new.cancelled_by, left('cancelled while sending: ' || coalesce(new.cancel_note, ''), 2000))
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    else
      select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = new.id::text and t.voided_at is null;
      if v_t.id is not null then                                                                                                         -- 보내졌다 → void
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'invoice_void', 'invoice', new.id::text, 'queued', new.cancelled_by, left('cancelled: ' || coalesce(new.cancel_note, ''), 2000))
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      end if;                                                                                                                            -- 둘 다 없으면(since 전 · 보낸 적 없음) 아무것도
    end if;
  exception when others then
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff) values (v_realm, 'invoice_void', 'invoice', new.id::text, 'failed', left('could not queue void: ' || sqlerrm, 2000), new.cancelled_by)
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$$;
comment on function public.qbo_job_on_invoice_cancel() is 'qbo-sync-2b1: so_invoice AFTER UPDATE OF status(issued → cancelled) — 열린 invoice 일감이 queued · blocked · failed 면 skipped(note) · sending · unknown 이면 invoice_void 일감 blocked_by 그 일감 · 열린 일감 없고 qbo_txn 이 있으면 invoice_void queued · 둘 다 없으면 아무것도 · 오류는 삼킨다';

create constraint trigger so_invoice_qbo_job after insert on public.so_invoice deferrable initially deferred for each row execute function public.qbo_job_on_invoice_issue();
create trigger so_invoice_qbo_cancel after update of status on public.so_invoice for each row execute function public.qbo_job_on_invoice_cancel();

-- ═══ D) 일감 창구 — add 재발행 · claim(drop + create · p_kinds) · done(drop + create · 합계) · list 재발행 ═══
create or replace function public.qbo_job_add(p_kind text, p_ims_id text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true);
begin
  if p_kind not in ('customer', 'item') then raise exception 'kind must be customer or item (invoice and credit jobs are queued by issuing) — nothing was saved'; end if;
  return public.qbo_job_open_or_add(p_kind, p_ims_id, v_staff);
end;
$$;
comment on function public.qbo_job_add(text, text) is 'qbo-sync-2a: 손님 · Item 만들기 일감을 미리 쌓는다(열쇠 qbo) — [2b1] 몸은 qbo_job_open_or_add(claim 의 needs 와 같은 길) · 몸을 미리 만들어 거부 사유를 바로 돌려준다 · 열린 일감이 있으면 그것(existing true) · 부모 손님 짝이 없으면 부모 일감 먼저 + blocked · 돌려주는 것 = 일감 한 줄 + preview(몸)';

drop function public.qbo_job_claim(int);
create function public.qbo_job_claim(p_limit int default 15, p_kinds text[] default array['customer', 'item']) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_stale int; v_unblocked int; v_ids uuid[]; v_j public.qbo_job%rowtype; v_b jsonb; v_rows jsonb := '[]'::jsonb; v_failed int := 0; v_blocked int := 0; v_last uuid; v_nj jsonb; e jsonb;
  v_kinds text[] := coalesce(p_kinds, array['customer', 'item']);
begin
  if not public.doc_is_service() then raise exception 'qbo_job_claim is for the send worker only — nothing was read'; end if;
  if not (v_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void']) or coalesce(array_length(v_kinds, 1), 0) = 0 then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void (got %)', v_kinds; end if;
  -- ① 멈춘 sending(EF 가 도중에 죽었다 · QBO 에 닿았는지 모른다) → unknown(mail_claim 꼴 · 자동 재전송 금지 · 다음 send 가 이름 · DocNumber 로 조회해 푼다)
  update public.qbo_job j set state = 'unknown', claimed_at = null,
         last_error = left(coalesce(j.last_error || ' · ', '') || format('stale: still sending %s after claim (attempt %s) — QuickBooks may or may not have it', date_trunc('second', now() - j.claimed_at), j.attempts), 2000)
   where j.realm_id = v_realm and j.state = 'sending' and j.claimed_at < now() - interval '10 minutes';
  get diagnostics v_stale = row_count;
  -- ② 부모가 보내졌으면 자식을 연다(손님 → 자식 손님 · need → 인보이스 · 인보이스 → void)
  update public.qbo_job j set state = 'queued', next_at = now() from public.qbo_job p where j.realm_id = v_realm and j.state = 'blocked' and p.id = j.blocked_by and p.state = 'sent';
  get diagnostics v_unblocked = row_count;
  -- ③ 잡기 — queued → sending(for update skip locked · 10 분 임대) · EF 가 아는 kind 만(2b1: 2a′ EF 는 customer · item 만)
  with pick as (
    select j.id from public.qbo_job j where j.realm_id = v_realm and j.state = 'queued' and j.next_at <= now() and j.kind = any (v_kinds)
     order by j.created_at, j.id limit greatest(1, least(coalesce(p_limit, 15), 50)) for update skip locked),
  upd as (update public.qbo_job j set state = 'sending', claimed_at = now(), attempts = j.attempts + 1 from pick where j.id = pick.id returning j.id)
  select coalesce(array_agg(u.id), '{}') into v_ids from upd u;
  -- ④ 몸은 다음 문장에서 일감마다(같은 문장 안의 읽기는 update 전 행을 본다) · 몸이 안 만들어지면 그 일감만 failed · needs 가 있으면 need 일감을 쌓고 이 일감은 blocked(이견 11)
  for v_j in select * from public.qbo_job j where j.id = any (v_ids) order by j.created_at, j.id loop
    begin
      v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                           when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid) end;
      if v_b is null then raise exception 'kind % is not sendable yet (2c)', v_j.kind; end if;
      if v_b->>'parent_customer_id' is not null then raise exception 'parent customer is not in QuickBooks yet — send the parent first (job was not blocked: parent link removed?)'; end if;
      if jsonb_array_length(coalesce(v_b->'needs', '[]'::jsonb)) > 0 then
        v_last := null;
        for e in select x from jsonb_array_elements(v_b->'needs') x loop
          v_nj := public.qbo_job_open_or_add(e->>'kind', e->>'ims_id', v_j.by_staff);                                                 -- 몸이 거부하면(941 · 활성 Sku 사람 짝 …) 예외 → 이 일감 failed + 그 까닭
          v_last := (v_nj->>'id')::uuid;
        end loop;
        update public.qbo_job j set state = 'blocked', blocked_by = v_last, claimed_at = null,
               warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')) || array[format('waiting for %s QuickBooks record(s) to be created first', jsonb_array_length(v_b->'needs'))], ' · '), '')
         where j.id = v_j.id;
        v_blocked := v_blocked + 1;
        continue;
      end if;
      update public.qbo_job j set warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')), ' · '), '') where j.id = v_j.id;
      v_rows := v_rows || jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'ims_kind', v_j.ims_kind, 'ims_id', v_j.ims_id, 'attempt', v_j.attempts, 'request_id', v_j.request_id,
                                             'name', coalesce(v_b->>'display_name', v_b->>'name'), 'name_alt', v_b->>'name_alt', 'sku', v_b->>'sku', 'doc_number', v_b->>'doc_number', 'qbo_id', v_b->>'qbo_id',
                                             'body', v_b->'body', 'warnings', v_b->'warnings', 'totals', v_b->'totals');
    exception when others then
      update public.qbo_job j set state = 'failed', claimed_at = null, last_error = left(sqlerrm, 2000) where j.id = v_j.id;
      v_failed := v_failed + 1;
    end;
  end loop;
  return jsonb_build_object('realm_id', v_realm, 'kinds', to_jsonb(v_kinds), 'recovered_unknown', v_stale, 'unblocked', v_unblocked, 'claimed', coalesce(array_length(v_ids, 1), 0), 'body_failed', v_failed, 'blocked_for_needs', v_blocked, 'jobs', v_rows);
end;
$$;
comment on function public.qbo_job_claim(int, text[]) is 'qbo-sync-2a · [2b1 p_kinds]: EF send 가 service_role 로 부른다 — ① sending 10 분 넘음 → unknown ② blocked → queued(부모 sent) ③ queued · next_at 지남 · kind = any(p_kinds · 기본 customer · item — 2b2 EF 가 invoice · invoice_void 를 더해 보낸다) → sending ④ 일감마다 몸(customer · item · invoice · invoice_void) · needs 가 있으면 need 일감을 쌓고 이 일감은 blocked(blocked_for_needs) · 몸 실패는 그 일감만 failed · 돌려주는 것 = jobs[{job_id · kind · ims_kind · ims_id · attempt · request_id · name · name_alt · sku · doc_number · qbo_id · body · warnings · totals}]';

drop function public.qbo_job_done(uuid, text, text, text, text, text, text);
create function public.qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text default null, p_intuit_tid text default null, p_note text default null, p_sku text default null, p_total_amt numeric default null, p_total_tax numeric default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_j public.qbo_job%rowtype; v_type text; v_link_err text; v_unblocked int := 0; v_i public.so_invoice%rowtype; v_mismatch text; v_n int;
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
  end if;
  if v_link_err is not null then
    update public.qbo_job j set state = 'failed', sent_at = null, last_error = left(coalesce(j.last_error || ' · ', '') || v_link_err, 2000) where j.id = v_j.id;
  else
    update public.qbo_job j set state = 'queued', next_at = now() where j.state = 'blocked' and j.blocked_by = v_j.id;
    get diagnostics v_unblocked = row_count;
  end if;
  return jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'state', case when v_link_err is null then 'sent' else 'failed' end, 'qbo_id', btrim(p_qbo_id), 'qbo_name', btrim(p_qbo_name), 'linked', v_link_err is null, 'link_error', v_link_err, 'unblocked', v_unblocked, 'mismatch', v_mismatch);
end;
$$;
comment on function public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric) is 'qbo-sync-2a · [2b1 합계]: 보내기 성공(service_role) — sending · unknown → sent · customer · item 이면 qbo_entity upsert + qbo_link(created) · invoice 면 qbo_txn insert … on conflict(ims 키) + 942 대조(p_total_amt · p_total_tax ≠ so_invoice.total · tax_amount → mismatch + warning · 상태는 sent) · invoice_void 면 qbo_txn.voided_at · QBO Id 가 이미 다른 IMS 행의 짝이면 failed + 사람 말 · 자식(blocked_by) 풀기는 kind 무관';

create or replace function public.qbo_job_list(p_state text default null, p_limit int default 50, p_offset int default 0) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0);
begin
  if p_state is not null and p_state not in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped', 'open') then raise exception 'state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open (got %)', p_state; end if;
  return (with base as (
      select j.*, case j.ims_kind when 'customer' then (select c.name from public.customer c where c.id::text = j.ims_id)
                                 when 'product' then (select p.sku || ' ' || p.name from public.product p where p.id::text = j.ims_id)
                                 when 'invoice' then (select i.invoice_number || ' · ' || coalesce(i.bill_to_name, '') || ' · ' || coalesce(i.currency_code, '') || ' ' || i.total from public.so_invoice i where i.id::text = j.ims_id)
                                 when 'credit' then (select c.credit_number || ' · ' || coalesce(c.total::text, '') from public.so_credit c where c.id::text = j.ims_id) else j.ims_id end as ims_name,
             (select s.name from public.ims_staff s where s.id = j.by_staff) as by_name,
             t.qbo_id as txn_qbo_id, t.total_amt as txn_total_amt, t.total_tax as txn_total_tax, t.mismatch as txn_mismatch, t.voided_at as txn_voided_at
      from public.qbo_job j left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_kind = j.ims_kind and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit')
      where j.realm_id = v_realm and (p_state is null or (p_state = 'open' and j.state not in ('sent', 'skipped')) or j.state = p_state))
    select jsonb_build_object('state', p_state, 'total', (select count(*) from base), 'limit', v_lim, 'offset', v_off,
      'counts', (select coalesce(jsonb_object_agg(x.state, x.n), '{}'::jsonb) from (select j.state, count(*) as n from public.qbo_job j where j.realm_id = v_realm group by j.state) x),
      'rows', coalesce((select jsonb_agg(to_jsonb(b) order by case b.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end, b.created_at desc) from (select * from base order by case state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end, created_at desc limit v_lim offset v_off) b), '[]'::jsonb)));
end;
$$;
comment on function public.qbo_job_list(text, int, int) is 'qbo-sync-2a · [2b1]: 일감 목록(열쇠 qbo 또는 qbo:read) — state 하나 · open · null = 전부 · counts · 행 = 일감 + ims_name(invoice = 번호 · 청구처 · 통화 총액) + by_name + 거래 짝 칸(txn_qbo_id · txn_total_amt · txn_total_tax · txn_mismatch · txn_voided_at) · unknown · failed 먼저 · limit ≤ 200';

-- ═══ E) 읽기 창구 — 인보이스 화면 꼬리표 ═══
create function public.qbo_txn_of(p_kind text, p_ims_id text) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text; v_t public.qbo_txn%rowtype; v_j public.qbo_job%rowtype;
begin
  if not exists (select 1 from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active) then raise exception 'You are not registered as active staff — nothing was read'; end if;
  if p_kind not in ('invoice', 'credit') then raise exception 'kind must be invoice or credit (got %)', p_kind; end if;
  select c.realm_id into v_realm from public.qbo_connection c where c.singleton;
  if v_realm is null then return null; end if;
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = p_kind and t.ims_id = p_ims_id;
  select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.ims_kind = p_kind and j.ims_id = p_ims_id order by j.created_at desc, j.id desc limit 1;
  if v_t.id is null and v_j.id is null then return null; end if;
  return jsonb_build_object('kind', p_kind, 'ims_id', p_ims_id,
    'qbo_id', v_t.qbo_id, 'doc_number', v_t.doc_number, 'total_amt', v_t.total_amt, 'total_tax', v_t.total_tax, 'mismatch', v_t.mismatch, 'sent_at', v_t.sent_at, 'voided_at', v_t.voided_at,
    'job_kind', v_j.kind, 'job_state', v_j.state, 'job_error', v_j.last_error, 'job_warning', v_j.warning, 'job_updated_at', v_j.updated_at);
end;
$$;
comment on function public.qbo_txn_of(text, text) is 'qbo-sync-2b1: 인보이스 · 크레딧 화면 꼬리표(로그인한 활성 직원 누구나) — 거래 짝(qbo_id · 합계 · mismatch · sent_at · voided_at) + 마지막 일감(kind · state · error · warning) · 연결 없거나 둘 다 없으면 null';

-- ═══ F) grant — 새 함수 명시(10-30 부터 자동 grant 없음) ═══
revoke all on function public.qbo_send_since_ok(date), public.qbo_invoice_body(uuid), public.qbo_void_body(uuid), public.qbo_job_open_or_add(text, text, uuid),
                       public.qbo_job_on_invoice_issue(), public.qbo_job_on_invoice_cancel(), public.qbo_job_claim(int, text[]),
                       public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric), public.qbo_txn_of(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.qbo_job_claim(int, text[]), public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric) to service_role;
grant execute on function public.qbo_txn_of(text, text) to authenticated;

-- ═══ 착지 검사 ═══
do $$
declare v text; v_n int;
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_send_since_ok', 'qbo_invoice_body', 'qbo_void_body', 'qbo_job_open_or_add', 'qbo_job_on_invoice_issue', 'qbo_job_on_invoice_cancel', 'qbo_job_claim', 'qbo_job_done', 'qbo_txn_of');
  if v <> 'qbo_invoice_body(p_invoice_id uuid)={postgres=X/postgres} qbo_job_claim(p_limit integer, p_kinds text[])={postgres=X/postgres,service_role=X/postgres} '
          || 'qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text, p_intuit_tid text, p_note text, p_sku text, p_total_amt numeric, p_total_tax numeric)={postgres=X/postgres,service_role=X/postgres} '
          || 'qbo_job_on_invoice_cancel()={postgres=X/postgres} qbo_job_on_invoice_issue()={postgres=X/postgres} qbo_job_open_or_add(p_kind text, p_ims_id text, p_by uuid)={postgres=X/postgres} '
          || 'qbo_send_since_ok(p_date date)={postgres=X/postgres} qbo_txn_of(p_kind text, p_ims_id text)={postgres=X/postgres,authenticated=X/postgres} qbo_void_body(p_invoice_id uuid)={postgres=X/postgres}' then
    raise exception 'qbo-sync-2b1 landing: %', v;
  end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_job_claim', 'qbo_job_done');
  if v_n <> 2 then raise exception 'qbo-sync-2b1 landing: qbo_job_claim / qbo_job_done overloads = % (want 2 — old signatures must be gone)', v_n; end if;
  select count(*) into v_n from pg_trigger t where t.tgrelid = 'public.so_invoice'::regclass and t.tgname in ('so_invoice_qbo_job', 'so_invoice_qbo_cancel');
  if v_n <> 2 then raise exception 'qbo-sync-2b1 landing: so_invoice triggers = % (want 2)', v_n; end if;
  select count(*) into v_n from information_schema.columns c where c.table_schema = 'public' and ((c.table_name = 'qbo_entity' and c.column_name = 'detail') or (c.table_name = 'qbo_txn' and c.column_name in ('mismatch', 'updated_by')));
  if v_n <> 3 then raise exception 'qbo-sync-2b1 landing: new columns = % (want 3)', v_n; end if;
  raise notice 'qbo-sync-2b1 landing OK — 함수 9 · 트리거 2 · 칸 3 · claim(p_kinds) · done(합계)';
end $$;
