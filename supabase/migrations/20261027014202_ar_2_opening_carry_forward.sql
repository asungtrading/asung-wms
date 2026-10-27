-- ar-2 (2026-10-26 · 판정 775 · 783 ~ 786 · ar-0 조사 · ar-1 프로브 위에) — 컷오버 미수 · 받아 둔 돈 이월: DB 몫(화면 ar-4 · 적재 스크립트 ar-3 는 따로)
--   판정 775 [Caleb 「B로 가자」]: 열린 옛 인보이스마다 이월 인보이스(옛 번호 · 발행일 · 기한 · 금액만 — 줄 · 재고 · 원가 없음) · 오버페이 · 열린 크레딧은 손님별 받아 둔 돈 · 컷오버 날 스크립트로 적재
--   판정 783 [Caleb 「A」]: 이월 인보이스 금액 = 원래 합계 + 이전에 받은 돈(prior_settled) → 남은 금액 — 손님 종이 · QuickBooks 의 합계와 같은 숫자가 보인다
--   판정 784 [Caleb 「A」]: 이월 인보이스는 취소 불가(so_invoice_cancel 거부) — 남은 금액은 결제 · 크레딧 붙임으로만 준다 · 적재가 틀렸으면 IMS 붙임이 생기기 전에만 적재를 다시 돌려 고친다(옛 열쇠로 덮어쓰기 · 붙임이 있으면 거부)
--   판정 785 [Caleb 「A」]: 이월 인보이스는 인쇄 · 메일 없음 — doc_data_invoice 한 곳에서 거부(화면 인쇄 · 미리 보기 · 서버 PDF · 메일 자리표 전부) · 메일 큐 · 드라이브 보관 트리거는 지나간다
--   판정 786 [Caleb 「A」]: 받아 둔 돈 이월(손님 크레딧 + 오버페이)은 손님 · 통화별 so_payment 한 줄 · method 'opening' · 계정 _1150040009_(Customer Credits) · 손님 자기 브랜치(customer.default_location_id) · QuickBooks 로 다시 보내지 않는다
--   ① so_invoice 칸 다섯 — kind(sale | opening) · prior_settled(≥ 0 · opening 만) · store_customer_id(Cin7 에 찍힌 매장 · sale 은 null — 매장은 so_invoice_order 에) · legacy_sale_id · legacy_invoice_id(옛 열쇠 · opening 만 · 유니크) · 옛 번호 정규화 색인 lower(btrim(invoice_number))
--      ⚠️ CHECK 는 그대로 — 적재가 lines_amount = Total − Tax 로 넣어 total = taxable + tax 가 저절로 선다(TotalBeforeTax 와 다르면 before_tax_adjusted 로 보고)
--   ② so_invoice_remaining 재발행(+1 바뀐 줄) — total − prior_settled − 결제 붙임 − 크레딧 붙임 · 「식은 한 곳」(목록 뷰 · 잔액 · 연체 · 제안 · 붙이기 한도가 전부 이 함수를 부른다 · 복사 식 0)
--   ③ 트리거 가드 둘 — doc_mail_auto_invoice · drive_archive_on_issue 에 opening 이면 지나가는 줄 하나씩
--   ④ so_invoice_cancel(opening 거부) · so_payment_void(method opening 거부) · doc_data_invoice(opening 거부 글 — 화면이 이 글로 안내)
--   ⑤ so_payment — method CHECK 에 'opening' · 유니크(customer_id, currency_id) where method = 'opening' · 사람 창구 so_payment_add 의 method 목록에는 없다(사람이 못 만든다)
--   ⑥ 뷰 so_invoice_list 재발행(fr-2 바이트 위 · 끝에 열 여섯 kind · prior_settled · store_customer_id · store_name · legacy_sale_id · legacy_invoice_id · so_invoice_detail 은 to_jsonb(v) 라 따라온다)
--   ⑦ 적재 창구 so_opening_load(p jsonb, p_dry boolean default true) — service_role 만 · 멱등 · Dry 는 같은 판단 · 쓰기 0 · 반환 jsonb(넣음 · 바뀜 · 같음 · 거부(이유) · 통화별 합 · 못 찾음)
--   ⚠️ 무접촉: so_credit* · hist_*(hcr-1 창) · so_customer_balance · so_customer_overdue · so_payment_propose · so_payment_alloc_add · so_payment_add · so_invoice_issue · so_payment_list · 인보이스 시퀀스(이월은 옛 번호를 명시로 넣는다 — 기본값은 평가되지 않는다)
--   컷오버 날 지우기(cutover-delete ③): 새 표 · 시퀀스 없음 · 칸만(D 표 so_invoice · so_payment) · FK store_customer_id → customer(K) 는 지움 → 남김 방향 — 분류 D 79 · K 73 · R 20 그대로
--   재발행 원본 md5(DB prosrc · 2026-10-26 테스트 DB = 마지막 정의 파일과 일치): so_invoice_remaining f9555d3c9f4b3b4745d5ceb67b5d92b5 · so_invoice_cancel 9107f7f408613ed6ac8d4c84217c25f7 · so_payment_void 82accf2f64856d5aabc798d818845ba6
--     · doc_mail_auto_invoice 949df77673430c07974d9ab691fb7b16 · drive_archive_on_issue 95086bef30c6c8e53c0186e6a5242414 · doc_data_invoice 1ba3b5148de65436aae947af78b15736 — 앞 do 블록이 단언한다(다르면 멈춘다)
--   검증: supabase/tests/ar_2_check.sql(시험 적용 begin → rollback · 가짜 손님 · 이월 인보이스 셋 · 받아 둔 돈 둘 · 다시 돌리기 · 붙임 뒤 거부 · 트리거 · 인쇄 거부 · 권한 · 시퀀스 무변)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -1 -v ON_ERROR_STOP=1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261027014202_ar_2_opening_carry_forward.sql && supabase migration repair --status applied 20261027014202 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ 0) 재발행 원본이 지금 DB 의 마지막 정의인가 — 다르면 멈춘다(다른 창이 먼저 바꿨을 때 그 줄을 잃지 않게) ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_invoice_remaining') is distinct from 'f9555d3c9f4b3b4745d5ceb67b5d92b5' then v_bad := v_bad || ' so_invoice_remaining'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_invoice_cancel') is distinct from '9107f7f408613ed6ac8d4c84217c25f7' then v_bad := v_bad || ' so_invoice_cancel'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_void') is distinct from '82accf2f64856d5aabc798d818845ba6' then v_bad := v_bad || ' so_payment_void'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_auto_invoice') is distinct from '949df77673430c07974d9ab691fb7b16' then v_bad := v_bad || ' doc_mail_auto_invoice'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'drive_archive_on_issue') is distinct from '95086bef30c6c8e53c0186e6a5242414' then v_bad := v_bad || ' drive_archive_on_issue'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_data_invoice') is distinct from '1ba3b5148de65436aae947af78b15736' then v_bad := v_bad || ' doc_data_invoice'; end if;
  if not exists (select 1 from public.ref_account a where a.code = '_1150040009_' and a.is_active) then v_bad := v_bad || ' ref_account(_1150040009_ missing or inactive — 판정 786)'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM783', message = format('STOP - ar-2 expects the last definitions as of 2026-10-26; these differ:%s - nothing was changed', v_bad); end if;
end $$;

-- ═══ 1) so_invoice — kind · prior_settled · store_customer_id · 옛 열쇠 둘 · CHECK · 색인 ═══
alter table public.so_invoice add column if not exists kind              text    not null default 'sale';
alter table public.so_invoice add column if not exists prior_settled     numeric not null default 0;
alter table public.so_invoice add column if not exists store_customer_id uuid    references public.customer(id);
alter table public.so_invoice add column if not exists legacy_sale_id    text;
alter table public.so_invoice add column if not exists legacy_invoice_id text;
alter table public.so_invoice drop constraint if exists so_invoice_kind_ck;
alter table public.so_invoice add  constraint so_invoice_kind_ck          check (kind in ('sale', 'opening'));
alter table public.so_invoice drop constraint if exists so_invoice_prior_settled_ck;
alter table public.so_invoice add  constraint so_invoice_prior_settled_ck check (prior_settled >= 0 and (kind = 'opening' or prior_settled = 0));
alter table public.so_invoice drop constraint if exists so_invoice_opening_ck;
alter table public.so_invoice add  constraint so_invoice_opening_ck       check ((kind = 'opening') = (legacy_sale_id is not null and legacy_invoice_id is not null and store_customer_id is not null));
create unique index if not exists so_invoice_legacy_invoice_uq on public.so_invoice (legacy_invoice_id) where kind = 'opening';
create index if not exists so_invoice_legacy_sale_idx on public.so_invoice (legacy_sale_id) where kind = 'opening';
create index if not exists so_invoice_store_customer_idx on public.so_invoice (store_customer_id);
create index if not exists so_invoice_number_norm_idx on public.so_invoice (lower(btrim(invoice_number)));
comment on column public.so_invoice.kind              is 'ar-2 판정 775: sale(IMS 발행 · 기본) · opening(이전 시스템에서 이월한 열린 인보이스 — 옛 번호 · 발행일 · 기한 · 금액만 · 줄 · 오더 · 재고 · 원가 없음 · issued_by null) · 취소 불가(784) · 인쇄 · 메일 없음(785) · so_opening_load 만 만든다';
comment on column public.so_invoice.prior_settled     is 'ar-2 판정 783: 이월 전 이미 받은 돈(이전 시스템의 Paid) · opening 만 > 0 · 남은 금액 = total − prior_settled − 결제 붙임 − 크레딧 붙임(so_invoice_remaining 한 곳) · 종이의 합계(total)는 손님 종이 · QuickBooks 와 같은 숫자';
comment on column public.so_invoice.store_customer_id is 'ar-2: 이월 인보이스의 손님 = 이전 시스템에 찍힌 매장(opening 만 · sale 은 null — 매장은 so_invoice_order.customer_id) · 청구처(bill_to_customer_id)는 그 손님의 coalesce(default_bill_to_customer_id, id)(판정 779 · 780 과 같은 방식) ⇒ 매장의 옛 미수가 본사 잔액 · 연체 창에 뜬다';
comment on column public.so_invoice.legacy_sale_id    is 'ar-2: 옛 시스템 열쇠(이전 시스템의 sale id · 글자) · opening 만 · 다시 돌릴 때 legacy_invoice_id 로 같은 줄을 찾는다 · 조회용 색인';
comment on column public.so_invoice.legacy_invoice_id is 'ar-2: 옛 시스템 열쇠(이전 시스템의 인보이스 id · 한 sale 에 인보이스가 여럿일 수 있어 인보이스 하나에 하나) · opening 만 · 유니크 so_invoice_legacy_invoice_uq · so_opening_load 의 덮어쓰기 열쇠';
comment on index public.so_invoice_number_norm_idx is 'ar-2: 옛 번호로 찾기(hcr-2 화면 「남은 $X — 크레딧을 거기에 붙여라」) — lower(btrim(invoice_number)) 로 조회하면 이 색인을 탄다';

-- ═══ 2) so_payment — method 'opening' · 손님 · 통화별 하나 ═══
alter table public.so_payment drop constraint if exists so_payment_method_ck;
alter table public.so_payment add  constraint so_payment_method_ck check (method in ('cheque', 'credit_card', 'debit_card', 'e_transfer', 'wire', 'cash', 'direct_deposit', 'shopify', 'opening'));
create unique index if not exists so_payment_opening_uq on public.so_payment (customer_id, currency_id) where method = 'opening';
comment on column public.so_payment.method is '판정 2 여덟 — cheque · credit_card · debit_card · e_transfer · wire · cash · direct_deposit · shopify(AONE 온라인 결제 · 유입 차수가 넣는다) · CHECK so_payment_method_ck · + ar-2 판정 786 opening(이월한 받아 둔 돈 — 손님 · 통화별 한 줄 · 계정 _1150040009_ · 손님 자기 브랜치 · so_opening_load 만 만든다 · void 불가 · 사람 창구 so_payment_add 는 거부 · QuickBooks 로 다시 보내지 않는다)';

-- ═══ 3) so_invoice_remaining 재발행 — 원본 DB 바이트(md5 f9555d3c9f4b3b4745d5ceb67b5d92b5) + 바뀐 줄 1(prior_settled) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.so_invoice_remaining(p_invoice_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when i.status = 'cancelled' then 0
              else i.total - i.prior_settled - coalesce((select sum(a.amount) from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
                                        where a.invoice_id = i.id and a.voided_at is null and p.status = 'active'), 0)
                           - coalesce((select sum(ca.amount) from public.so_credit_alloc ca join public.so_credit c on c.id = ca.credit_id
                                        where ca.invoice_id = i.id and ca.voided_at is null and c.status = 'issued'), 0) end   -- ⓒ2: 크레딧 붙임도 뺀다 · ar-2 판정 783: 이전에 받은 돈(prior_settled · opening 만 > 0)도 뺀다 — 식은 한 곳
  from public.so_invoice i where i.id = p_invoice_id;
$function$;

-- ═══ 4) 트리거 가드 둘 — 원본 DB 바이트 + 더한 줄 1 씩(begin 바로 뒤) ═══
-- doc_mail_auto_invoice 원본 md5 949df77673430c07974d9ab691fb7b16
CREATE OR REPLACE FUNCTION public.doc_mail_auto_invoice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_on boolean; v_rcpt jsonb; v_doc jsonb; v_ref jsonb := jsonb_build_object('invoice_id', new.id); v_subject text; v_body text; v_staff uuid;
begin
  if new.kind = 'opening' then return null; end if;                                                                                      -- ar-2 판정 785: 이월 인보이스(이전 시스템)는 메일 없음
  select c.final_invoice_mail into v_on from public.customer c where c.id = new.bill_to_customer_id;
  if not coalesce(v_on, false) then return null; end if;
  if (select i.status from public.so_invoice i where i.id = new.id) is distinct from 'issued' then return null; end if;             -- 같은 트랜잭션에서 취소됐으면 아무것도
  if exists (select 1 from public.so_invoice_order o1 join public.so_invoice_order o2 on o2.so_id = o1.so_id and o2.invoice_id <> o1.invoice_id where o1.invoice_id = new.id) then
    insert into public.doc_mail_skip (kind, ref, customer_id, reason, detail) values ('final_invoice', v_ref, new.bill_to_customer_id, 'reissue', 'an earlier invoice exists for the same order — not mailed automatically');
    return null;
  end if;
  v_rcpt := public.doc_mail_recipient(new.bill_to_customer_id);
  if v_rcpt->>'to' is null then
    insert into public.doc_mail_skip (kind, ref, customer_id, reason, detail) values ('final_invoice', v_ref, new.bill_to_customer_id, 'no_email', 'the customer has no contact with an email address');
    return null;
  end if;
  begin
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    v_doc := public.doc_data('final_invoice', v_ref)->'docs'->0;
    v_subject := btrim(public.doc_mail_fill((select d.value from public.doc_setting d where d.kind = 'final_invoice' and d.key = 'mail_subject'), v_doc));
    v_body := public.doc_mail_fill((select d.value from public.doc_setting d where d.kind = 'final_invoice' and d.key = 'mail_body'), v_doc);
    if v_subject = '' then raise exception 'mail_subject of final_invoice is empty (Settings → Documents)'; end if;
    perform public.doc_mail_enqueue('final_invoice', v_ref, v_rcpt->>'to', v_subject, v_body, new.bill_to_customer_id, v_staff, null, true);
  exception when others then                                                                                                             -- 발행을 막지 않는다 — 남기고 지나간다
    insert into public.doc_mail_skip (kind, ref, customer_id, reason, detail) values ('final_invoice', v_ref, new.bill_to_customer_id, 'error', left(sqlerrm, 500));
  end;
  return null;
end;
$function$;

-- drive_archive_on_issue 원본 md5 95086bef30c6c8e53c0186e6a5242414
CREATE OR REPLACE FUNCTION public.drive_archive_on_issue()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_kind text := case tg_table_name when 'so_invoice' then 'final_invoice' else 'credit_note' end; v_status text;
begin
  if tg_table_name = 'so_invoice' and (select i.kind from public.so_invoice i where i.id = new.id) = 'opening' then return null; end if;   -- ar-2 판정 785: 이월 인보이스는 드라이브 보관 없음(so_credit 행은 kind 칸이 없어 서브쿼리로)
  select case tg_table_name when 'so_invoice' then (select i.status from public.so_invoice i where i.id = new.id) else (select c.status from public.so_credit c where c.id = new.id) end into v_status;
  if v_status is distinct from 'issued' then return null; end if;                                                     -- 같은 트랜잭션에서 취소됐으면 아무것도
  begin
    perform public.drive_archive_enqueue(v_kind, new.id);
  exception when others then
    insert into public.drive_job (kind, status, doc_kind, doc_ref, target_scope, target_ref, file_name, last_error)
    values ('archive', 'skipped', v_kind, case v_kind when 'final_invoice' then jsonb_build_object('invoice_id', new.id) else jsonb_build_object('credit_id', new.id) end, 'customer', '-', 'error', left(sqlerrm, 500))
    on conflict do nothing;
  end;
  return null;
end;
$function$;

-- ═══ 5) so_invoice_cancel(판정 784) · so_payment_void(짝) — 원본 DB 바이트 + 더한 줄 1 씩 ═══
-- so_invoice_cancel 원본 md5 9107f7f408613ed6ac8d4c84217c25f7
CREATE OR REPLACE FUNCTION public.so_invoice_cancel(p_invoice_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff uuid;
  v_inv   public.so_invoice%rowtype;
  v_note  text;
  v_n     int;
  v_orders int;
  v_manual int;
  v_auto   int;
  v_auto_amt numeric;
  v_cr_manual int;  v_cr_auto int;  v_cr_amt numeric;   -- ⓒ2 크레딧 붙임
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 인보이스 취소는 manager 이상(6-g · 8-h · 판정 8)
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'A cancel needs a reason (p_note) — nothing was saved'; end if;

  select * into v_inv from public.so_invoice i where i.id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found — nothing was saved'; end if;
  if v_inv.status <> 'issued' then raise exception 'Invoice % is already % — nothing was saved', v_inv.invoice_number, v_inv.status; end if;
  if v_inv.kind = 'opening' then raise exception 'Invoice % was carried forward from the previous system and cannot be cancelled — what is left comes down only by a payment or a credit note (billing error, other) — nothing was saved', v_inv.invoice_number; end if;   -- ar-2 판정 784
  perform 1 from public.customer c where c.id = v_inv.bill_to_customer_id for update;   -- 청구처 손님 행 잠금

  -- ⓑ2 판정 7 — 사람이 붙인 결제(manual)가 있으면 거부 · 발행 때 자동으로 붙은 것(auto_deposit · auto_balance)은 취소와 함께 void(흔적)
  select count(*) into v_manual from public.so_payment_alloc a where a.invoice_id = p_invoice_id and a.voided_at is null and a.source = 'manual';
  if v_manual > 0 then
    raise exception 'Invoice % has % payment allocation(s) applied by hand — detach them first (or issue a credit note instead, 8-h) — nothing was saved', v_inv.invoice_number, v_manual;
  end if;
  -- ⓒ2 8-h 「크레딧이 붙기 전에만」 — 판정 7 과 같은 규칙: 사람이 붙인 크레딧(manual)이 있으면 거부 · 발행 때 자동으로 붙은 크레딧(auto)은 취소와 함께 void(진 빚으로 돌아간다)
  select count(*) into v_cr_manual from public.so_credit_alloc ca where ca.invoice_id = p_invoice_id and ca.voided_at is null and ca.source = 'manual';
  if v_cr_manual > 0 then
    raise exception 'Invoice % has % credit note allocation(s) applied by hand — detach them first (so_credit_detach) — nothing was saved', v_inv.invoice_number, v_cr_manual;
  end if;
  select count(*), coalesce(sum(ca.amount), 0) into v_cr_auto, v_cr_amt from public.so_credit_alloc ca where ca.invoice_id = p_invoice_id and ca.voided_at is null and ca.source = 'auto';
  update public.so_credit_alloc set voided_at = now(), voided_by = v_staff, void_note = 'Invoice ' || v_inv.invoice_number || ' cancelled: ' || v_note, updated_by = v_staff
  where invoice_id = p_invoice_id and voided_at is null and source = 'auto';
  get diagnostics v_n = row_count;
  if v_n <> v_cr_auto then raise exception 'Invoice % — % of % automatic credit allocations could not be released — nothing was saved', v_inv.invoice_number, v_n, v_cr_auto; end if;
  select count(*), coalesce(sum(a.amount), 0) into v_auto, v_auto_amt from public.so_payment_alloc a where a.invoice_id = p_invoice_id and a.voided_at is null and a.source in ('auto_deposit', 'auto_balance');
  update public.so_payment_alloc set voided_at = now(), voided_by = v_staff, void_note = 'Invoice ' || v_inv.invoice_number || ' cancelled: ' || v_note, updated_by = v_staff
  where invoice_id = p_invoice_id and voided_at is null and source in ('auto_deposit', 'auto_balance');
  get diagnostics v_n = row_count;
  if v_n <> v_auto then raise exception 'Invoice % — % of % automatic allocations could not be released — nothing was saved', v_inv.invoice_number, v_n, v_auto; end if;

  update public.so_invoice set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff, cancel_note = v_note, updated_by = v_staff
  where id = p_invoice_id and status = 'issued';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Invoice % was not cancelled — it may have been changed by someone else just now — nothing was saved', v_inv.invoice_number; end if;
  update public.so_invoice_order set cancelled_at = now(), updated_by = v_staff where invoice_id = p_invoice_id and cancelled_at is null;   -- active_so_id 가 풀린다 → 다시 발행 가능
  get diagnostics v_orders = row_count;
  update public.so s set status = 'shipped', invoiced_at = null, closed_at = null, updated_by = v_staff                                   -- 문지기 짝 fulfilled→shipped(8-h 하향 · closed_at 짝 비움)
  from public.so_invoice_order o where o.invoice_id = p_invoice_id and s.id = o.so_id and s.status = 'fulfilled';
  get diagnostics v_n = row_count;
  if v_n <> v_orders then raise exception 'Invoice % — % of % orders could not be set back to shipped — nothing was saved', v_inv.invoice_number, v_n, v_orders; end if;

  return jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'status', 'cancelled', 'orders_back_to_shipped', v_orders, 'cancelled_by', v_staff, 'note', v_note,
                            'auto_allocations_released', v_auto, 'released_amount', v_auto_amt,
                            'auto_credit_allocations_released', v_cr_auto, 'released_credit_amount', v_cr_amt,
                            'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id));
end;
$function$;

-- so_payment_void 원본 md5 82accf2f64856d5aabc798d818845ba6
CREATE OR REPLACE FUNCTION public.so_payment_void(p_payment_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff uuid;
  v_p     public.so_payment%rowtype;
  v_note  text;
  v_n     int;
  v_rem   numeric;
  v_recv  numeric;
  v_cr    int := 0;   -- ⓒ2 환불에 붙은 크레딧
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄(판정 6)
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'Voiding needs a reason (p_note) — nothing was saved'; end if;
  select * into v_p from public.so_payment p where p.id = p_payment_id;
  if not found then raise exception 'Payment not found — nothing was saved'; end if;
  perform 1 from public.customer c where c.id = v_p.customer_id for update;   -- 손님 행 잠금
  select * into v_p from public.so_payment p where p.id = p_payment_id for update;
  if v_p.status <> 'active' then raise exception 'Payment is already voided — nothing was saved'; end if;
  if v_p.method = 'opening' then raise exception 'This is the opening balance carried forward from the previous system — it cannot be voided; if the amount is wrong, run the opening load again — nothing was saved'; end if;   -- ar-2 판정 784 의 짝(받아 둔 돈 이월)
  select count(*) into v_n from public.so_payment_alloc a where a.payment_id = v_p.id and a.voided_at is null;
  if v_n > 0 then raise exception 'Payment has % allocation(s) applied to invoices — detach them first — nothing was saved', v_n; end if;
  if v_p.kind = 'payment' then
    v_rem := v_p.amount;   -- 활성 alloc 0 이므로 남은 금액 = amount
    select b.received into v_recv from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id;
    if coalesce(v_recv, 0) - v_rem < 0 then
      raise exception 'Voiding this payment would put the customer''s % balance below zero (% on account, refunds already paid out) — nothing was saved', v_p.currency_code, coalesce(v_recv, 0);
    end if;
  end if;
  if v_p.kind = 'refund' then   -- ⓒ2: 이 환불이 갚은 크레딧 몫은 함께 풀린다(void · 진 빚으로 돌아간다)
    update public.so_credit_alloc set voided_at = now(), voided_by = v_staff, void_note = 'Refund voided: ' || v_note, updated_by = v_staff where refund_payment_id = v_p.id and voided_at is null;
    get diagnostics v_cr = row_count;
  end if;
  update public.so_payment set status = 'voided', voided_at = now(), voided_by = v_staff, void_note = v_note, updated_by = v_staff where id = v_p.id and status = 'active';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Payment was not voided — it may have been changed by someone else just now — nothing was saved'; end if;
  return jsonb_build_object('payment_id', v_p.id, 'kind', v_p.kind, 'amount', v_p.amount, 'status', 'voided', 'note', v_note, 'credit_allocations_released', v_cr,
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id));
end;
$function$;

-- ═══ 6) doc_data_invoice(판정 785) — 원본 DB 바이트 + 더한 줄 1(Invoice not found 바로 뒤) ═══
-- doc_data_invoice 원본 md5 1ba3b5148de65436aae947af78b15736
CREATE OR REPLACE FUNCTION public.doc_data_invoice(p_kind text, p_invoice_id uuid, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_inv public.so_invoice%rowtype;
  v_n   jsonb;
begin
  select * into v_inv from public.so_invoice i where i.id = p_invoice_id;
  if v_inv.id is null then raise exception 'Invoice not found'; end if;
  if v_inv.kind = 'opening' then raise exception 'Invoice % was carried forward from the previous system — the original is in QuickBooks. It cannot be printed or mailed from IMS', v_inv.invoice_number; end if;   -- ar-2 판정 785: doc_data 한 곳(화면 인쇄 · 미리 보기 · 서버 PDF · 메일 자리표 전부)
  v_n := jsonb_build_object(
    'header', jsonb_build_object('number', v_inv.invoice_number, 'issued_on', v_inv.issued_on, 'due_on', v_inv.due_on, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code, 'memo', v_inv.note,
                                 'bill_to_customer_id', v_inv.bill_to_customer_id,
                                 'bill_to', jsonb_build_object('name', v_inv.bill_to_name, 'line1', v_inv.bill_to_line1, 'line2', v_inv.bill_to_line2, 'city', v_inv.bill_to_city, 'state_province', v_inv.bill_to_state_province, 'postal_code', v_inv.bill_to_postal_code, 'country', v_inv.bill_to_country)),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object(
                 'so_number', o.so_number, 'reference', s.ref, 'carrier', s.carrier, 'tracking', s.tracking_number, 'tax_rule', o.tax_rule, 'order_discount_pct', o.order_discount_pct,
                 'ship_to', jsonb_build_object('company', o.ship_to_company, 'contact', o.ship_to_contact, 'phone', o.ship_to_phone, 'line1', o.ship_to_line1, 'line2', o.ship_to_line2, 'city', o.ship_to_city, 'state_province', o.ship_to_state_province, 'postal_code', o.ship_to_postal_code, 'country', o.ship_to_country),
                 'lines', (select coalesce(jsonb_agg(jsonb_build_object('product_id', sl.product_id, 'sku', l.sku, 'description', l.description, 'comment', sl.comments, 'unit', l.unit, 'qty', l.qty, 'list_price', l.list_price, 'discount_pct', l.discount_pct,
                                                                        'unit_price', l.unit_price, 'amount', l.amount, 'tax_amount', l.tax_amount, 'is_free', sl.free_reason is not null, 'no_price', l.unit_price is null, 'manual', coalesce(public.so_line_manual(sl), false), 'final_sale', coalesce(sl.bgrade_bin_id is not null, false)) order by l.line_no), '[]'::jsonb)
                           from public.so_invoice_line l left join public.so_line sl on sl.id = l.so_line_id where l.invoice_order_id = o.id and l.kind = 'product')) order by o.so_number), '[]'::jsonb)
               from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id),
    'charges', (select coalesce(jsonb_agg(jsonb_build_object('so_number', o.so_number, 'kind', l.kind, 'account_code', l.account_code, 'description', l.description, 'comment', case when l.kind = 'charge' then c.description end,
                                                             'qty', l.qty, 'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'amount', l.amount, 'tax_amount', l.tax_amount) order by o.so_number, l.line_no), '[]'::jsonb)
                from public.so_invoice_line l join public.so_invoice_order o on o.id = l.invoice_order_id left join public.so_charge c on c.id = l.so_charge_id
                where l.invoice_id = v_inv.id and l.kind <> 'product'),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('reference', p.reference, 'paid_on', p.paid_on, 'method', p.method, 'amount', a.amount) order by p.paid_on, p.created_at, a.created_at), '[]'::jsonb)
                 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
                 where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment'),
    'totals', jsonb_build_object('order_discount', v_inv.order_discount_amount, 'surcharge', v_inv.surcharge_amount, 'taxable', v_inv.taxable_amount, 'tax', v_inv.tax_amount, 'total', v_inv.total,
                                 'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward,
                                 'paid', (select coalesce(sum(a.amount), 0) from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment'),
                                 'amount_due', v_inv.amount_due,
                                 'remaining', public.so_invoice_remaining(v_inv.id)));                                                                                     -- doc-1c 판정 528 ①: 찍는 순간 지금 남은 금액(발행 때 종이 값 amount_due 는 doc-2 의 남긴 PDF 가 지킨다)
  return public.doc_data_invoice_fmt(p_kind, p_cfg, v_n);
end;
$function$;

-- ═══ 7) 뷰 so_invoice_list 재발행 — 20261007173939(fr-2) 바이트 그대로 + 매장 조인 1 + 끝에 열 여섯(so_invoice_detail 의 invoice 행이 이 뷰 · 권한 · security_invoker 유지) ═══
create or replace view public.so_invoice_list
  with (security_invoker = true) as
with ord as (
  select o.invoice_id,
         string_agg(o.so_number, ', ' order by o.so_number) filter (where o.cancelled_at is null)  as so_numbers,
         array_agg(o.so_id order by o.so_number)             filter (where o.cancelled_at is null)  as so_ids,
         count(*)                                             filter (where o.cancelled_at is null)  as order_count,
         case when count(distinct s.channel) filter (where o.cancelled_at is null) > 1 then 'mixed'
              else min(s.channel) filter (where o.cancelled_at is null) end                          as channel,
         string_agg(o.so_number || coalesce(' ' || s.ref, ''), ' ' order by o.so_number) filter (where o.cancelled_at is null) as order_text
  from public.so_invoice_order o
  join public.so s on s.id = o.so_id
  group by o.invoice_id
),
pay as (   -- 살아 있는 결제 붙임(so_invoice_remaining 과 같은 조건)
  select a.invoice_id, sum(a.amount) as paid
  from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
  where a.voided_at is null and p.status = 'active'
  group by a.invoice_id
),
cred as (  -- 살아 있는 크레딧 붙임(issued 크레딧만)
  select a.invoice_id, sum(a.amount) as credited
  from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id
  where a.invoice_id is not null and a.voided_at is null and c.status = 'issued'
  group by a.invoice_id
)
select i.id, i.invoice_number, i.status, i.issued_on, i.due_on, i.payment_term_name, i.currency_id, i.currency_code,
       i.bill_to_customer_id, i.bill_to_name, cu.name as customer_name,
       o.so_numbers, o.so_ids, coalesce(o.order_count, 0)::int as order_count, o.channel,
       i.lines_amount, i.order_discount_amount, i.charges_amount, i.tax_amount, i.total,
       i.deposit_applied, i.credit_applied, i.balance_forward, i.amount_due,
       coalesce(pay.paid, 0)       as paid,
       coalesce(cred.credited, 0)  as credited,
       r.remaining,
       (i.due_on is null)          as due_unknown,
       case when i.status = 'issued' and r.remaining > 0 and i.due_on is not null and i.due_on < public.ims_today()
            then (public.ims_today() - i.due_on) else 0 end::int as days_overdue,
       (i.status = 'issued' and r.remaining > 0) as is_open,
       i.cancelled_at, i.cancel_note, i.note, i.created_at,
       (i.invoice_number || ' ' || coalesce(i.bill_to_name, '') || ' ' || coalesce(cu.name, '') || ' ' || coalesce(o.order_text, '')) as search_text,
       i.surcharge_amount,                                                                                                     -- surcharge-2b(끝에 — create or replace view 는 열을 끝에만 더할 수 있다)
       i.charges_discount_amount,                                                                                              -- fr-2 판정 352(끝에 — 같은 이유)
       i.kind, i.prior_settled, i.store_customer_id, st.name as store_name, i.legacy_sale_id, i.legacy_invoice_id                      -- ar-2 판정 783(끝에 — 같은 이유 · so_invoice_detail 의 invoice 행이 이 뷰)
from public.so_invoice i
left join public.customer cu on cu.id = i.bill_to_customer_id
left join public.customer st on st.id = i.store_customer_id                                                                       -- ar-2: 이월 인보이스의 매장(sale 은 null)
left join ord o on o.invoice_id   = i.id
left join pay  on pay.invoice_id  = i.id
left join cred on cred.invoice_id = i.id
cross join lateral (select public.so_invoice_remaining(i.id) as remaining) r;   -- 읽기 함수(stable)를 lateral 에서 한 번만 — 쓰기 창구가 아니다


-- ═══ 8) 적재 창구 so_opening_load — service_role 만 · 멱등 · Dry 는 같은 판단 · 쓰기 0 ═══
create or replace function public.so_opening_load(p jsonb, p_dry boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- ar-2 판정 775 · 783 ~ 786: 컷오버 날 이월 적재 — Apps Script(ar-3)가 service_role 로 부른다(한 번에 invoices ≤ 500 · credits ≤ 500 · 실측 ar-2 회신) · 자리 = reload-procedure §P 12b(거래 지우기 5 뒤 · 마스터 8 뒤 · cron 13 앞)
-- 입력 p = {as_of?: date(기본 ims_today · 이월 결제의 paid_on · 발행일이 이 날 뒤면 거부), complete?: bool(true 면 「입력에 없는 기존 이월 줄」 도 보고 — 지우지는 않는다),
--           invoices?: [{legacy_sale_id!, legacy_invoice_id!, invoice_number!(숫자 5 자리 이상), cin7_customer_id!(customer.cin7_id), issued_on!, due_on?, payment_term_name?, currency!(code), total_before_tax!, tax!, total!, prior_settled?(기본 0)}],
--           credits?:  [{cin7_customer_id!, currency!(code), amount!(> 0), source!(credit | overpay), reference?}]}
-- 판단(Dry 와 Apply 가 같은 길): ① 풀기 — 손님 cin7_id · 통화 code · 결제조건 name(못 찾으면 이름만 · 기한은 입력값) · 계정 _1150040009_(없으면 전체 멈춤) · 브랜치 = 손님 default_location_id
--   ② 인보이스 — 옛 열쇠 legacy_invoice_id 로 기존 opening 줄을 찾는다 · 같으면 same · 다르면 update · 없으면 insert · IMS 붙임(활성 결제 · 크레딧 alloc)이 있으면 바뀐 줄은 거부(784)
--      금액 = lines_amount(= Total − Tax) · tax · total · amount_due = total · prior_settled(이전에 받은 돈) · 남은 금액 = total − prior_settled(so_invoice_remaining) · 번호는 옛 번호를 명시로(시퀀스 무변) · issued_by null · 오더 없음
--   ③ 받아 둔 돈 — 유효 줄을 (청구처 = coalesce(default_bill_to_customer_id, id), 통화) 로 합쳐 so_payment 한 줄(kind payment · method opening · paid_on as_of · 계정 _1150040009_ · 브랜치 = 매장의 위치 칸(없으면 청구처의) · note 에 출처 글 + 매장 이름) · 기존 줄은 금액 같으면 same · 다르면 update · IMS 붙임(alloc) · 그 손님 · 통화의 IMS 환불이 있으면 거부
--   ④ p_dry 면 판단 결과만 돌려주고 아무것도 쓰지 않는다(임시 표만) · 반환 jsonb: invoices{in, inserted, updated, same, rejected, rejects[], by_currency[], customer_unresolved, term_unresolved, before_tax_adjusted, existing_not_in_input} · credits{rows_in, groups, inserted, updated, same, rejected, rejects[], by_currency[], customer_unresolved, branch_unresolved, large[], existing_not_in_input} · account · ms
-- ⚠️ REST(authenticator · safeupdate): WHERE 없는 delete · update 없음 · 임시 표는 truncate
declare
  v_t0      timestamptz := clock_timestamp();
  v_as_of   date;
  v_complete boolean;
  v_acct    public.ref_account%rowtype;
  v_today   date := public.ims_today();
  x         jsonb;
  v_seq     int := 0;
  v_n       int;
  v_ids     text[];
  v_inv     record;
  v_cr      record;
  v_out     jsonb;
  v_inv_out jsonb;
  v_cr_out  jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'p must be a JSON object {as_of?, complete?, invoices?: [...], credits?: [...]} — nothing was saved'; end if;
  if p ? 'invoices' and jsonb_typeof(p->'invoices') <> 'array' then raise exception 'invoices must be a JSON array — nothing was saved'; end if;
  if p ? 'credits' and jsonb_typeof(p->'credits') <> 'array' then raise exception 'credits must be a JSON array — nothing was saved'; end if;
  if coalesce(jsonb_array_length(p->'invoices'), 0) > 500 then raise exception 'Too many invoices in one call (% — the limit is 500) — send pages of 500 — nothing was saved', jsonb_array_length(p->'invoices'); end if;
  if coalesce(jsonb_array_length(p->'credits'), 0) > 500 then raise exception 'Too many credits in one call (% — the limit is 500) — send pages of 500 — nothing was saved', jsonb_array_length(p->'credits'); end if;
  v_as_of := coalesce(nullif(p->>'as_of', '')::date, v_today);
  if v_as_of > v_today then raise exception 'as_of % is in the future — nothing was saved', v_as_of; end if;
  v_complete := coalesce((p->>'complete')::boolean, false);
  select * into v_acct from public.ref_account a where a.code = '_1150040009_';
  if v_acct.id is null or not v_acct.is_active then raise exception 'Account _1150040009_ (Customer Credits — 판정 786) is missing or inactive in ref_account — nothing was saved'; end if;

  -- 임시 표(세션 전용 · 트랜잭션 끝에 사라진다 · 쪽마다 truncate)
  if to_regclass('pg_temp.ar2_inv') is null then
    create temp table ar2_inv (seq int, legacy_sale_id text, legacy_invoice_id text, invoice_number text, cin7_customer_id uuid, store_id uuid, store_name text, bill_to_id uuid, bill_to_name text,
                               issued_on date, due_on date, term_name text, term_id uuid, currency_code text, currency_id uuid, before_tax numeric, tax numeric, total numeric, prior_settled numeric,
                               lines_amount numeric, btx_adj numeric, existing_id uuid, action text, reason text) on commit drop;
    create temp table ar2_cr  (seq int, cin7_customer_id uuid, store_id uuid, store_name text, store_warehouse_id uuid, customer_id uuid, customer_name text, currency_code text, currency_id uuid, amount numeric, source text, reference text, reason text) on commit drop;
    create temp table ar2_crg (customer_id uuid, customer_name text, currency_id uuid, currency_code text, amount numeric, n int, note text, warehouse_id uuid, warehouse_name text, existing_id uuid, action text, reason text) on commit drop;
  end if;
  truncate ar2_inv;  truncate ar2_cr;  truncate ar2_crg;

  -- ── ① 인보이스 줄 풀기 ──
  for x in select t from jsonb_array_elements(coalesce(p->'invoices', '[]'::jsonb)) t loop
    v_seq := v_seq + 1;
    insert into ar2_inv (seq, legacy_sale_id, legacy_invoice_id, invoice_number, cin7_customer_id, issued_on, due_on, term_name, currency_code, before_tax, tax, total, prior_settled)
    values (v_seq, nullif(btrim(x->>'legacy_sale_id'), ''), nullif(btrim(x->>'legacy_invoice_id'), ''), nullif(btrim(x->>'invoice_number'), ''),
            nullif(btrim(x->>'cin7_customer_id'), '')::uuid, nullif(x->>'issued_on', '')::date, nullif(x->>'due_on', '')::date, nullif(btrim(x->>'payment_term_name'), ''),
            upper(nullif(btrim(x->>'currency'), '')), nullif(x->>'total_before_tax', '')::numeric, nullif(x->>'tax', '')::numeric, nullif(x->>'total', '')::numeric, coalesce(nullif(x->>'prior_settled', '')::numeric, 0));
  end loop;
  update ar2_inv i set store_id = c.id, store_name = c.name, bill_to_id = coalesce(c.default_bill_to_customer_id, c.id) from public.customer c where c.cin7_id = i.cin7_customer_id;
  update ar2_inv i set bill_to_name = b.name from public.customer b where b.id = i.bill_to_id;
  update ar2_inv i set currency_id = rc.id from public.ref_currency rc where rc.code = i.currency_code and rc.is_active;
  update ar2_inv i set term_id = (select pt.id from public.ref_payment_term pt where lower(btrim(pt.name)) = lower(i.term_name) order by pt.is_active desc, pt.name, pt.id limit 1) where i.term_name is not null;   -- 이름 자연키 · 같은 이름이 여럿이면 활성 먼저
  update ar2_inv i set term_name = pt.name from public.ref_payment_term pt where pt.id = i.term_id;
  update ar2_inv i set due_on = i.issued_on + pt.net_days from public.ref_payment_term pt where pt.id = i.term_id and i.due_on is null and i.issued_on is not null and pt.net_days is not null;
  update ar2_inv i set lines_amount = round(i.total - i.tax, 2), btx_adj = round(i.total - i.tax, 2) - round(i.before_tax, 2) where i.total is not null and i.tax is not null and i.before_tax is not null;
  update ar2_inv i set existing_id = e.id from public.so_invoice e where e.kind = 'opening' and e.legacy_invoice_id = i.legacy_invoice_id;
  -- 거부 이유(첫 이유 하나만)
  update ar2_inv i set reason = case
    when i.legacy_sale_id is null or i.legacy_invoice_id is null then 'legacy_key_missing'
    when i.invoice_number is null or i.invoice_number !~ '^[0-9]{5,}$' then 'number_invalid'
    when i.cin7_customer_id is null then 'customer_id_missing'
    when i.store_id is null then 'customer_unresolved'
    when i.currency_id is null then 'currency_unresolved'
    when i.issued_on is null then 'issued_on_missing'
    when i.issued_on > v_as_of then 'issued_on_future'
    when i.before_tax is null or i.tax is null or i.total is null then 'amount_missing'
    when i.total <> round(i.total, 2) or i.tax <> round(i.tax, 2) or i.prior_settled <> round(i.prior_settled, 2) then 'amount_decimals'
    when i.total <= 0 then 'total_invalid'
    when i.prior_settled < 0 then 'prior_settled_negative'
    when i.prior_settled >= i.total then 'nothing_remaining'
    when abs(round(i.before_tax, 2) + round(i.tax, 2) - round(i.total, 2)) > 0.05 then 'total_mismatch'
    when exists (select 1 from ar2_inv d where d.legacy_invoice_id = i.legacy_invoice_id and d.seq < i.seq) then 'duplicate_in_input'
    when exists (select 1 from ar2_inv d where d.invoice_number = i.invoice_number and d.seq < i.seq) then 'number_duplicate_in_input'
    when exists (select 1 from public.so_invoice e where e.invoice_number = i.invoice_number and e.id is distinct from i.existing_id) then 'number_taken'
    end;
  -- 같음 · 바뀜 · 넣음 · IMS 붙임이 있는 바뀜은 거부
  update ar2_inv i set action = case
    when i.reason is not null then 'reject'
    when i.existing_id is null then 'insert'
    when exists (select 1 from public.so_invoice e where e.id = i.existing_id
                   and e.invoice_number = i.invoice_number and e.store_customer_id = i.store_id and e.bill_to_customer_id = i.bill_to_id
                   and e.issued_on = i.issued_on and e.due_on is not distinct from i.due_on and e.payment_term_id is not distinct from i.term_id and e.payment_term_name is not distinct from i.term_name
                   and e.currency_id = i.currency_id and e.lines_amount = i.lines_amount and e.tax_amount = i.tax and e.total = i.total and e.prior_settled = i.prior_settled
                   and e.legacy_sale_id = i.legacy_sale_id and e.status = 'issued') then 'same'
    else 'update' end;
  update ar2_inv i set action = 'reject', reason = 'has_ims_allocations' where i.action = 'update'
    and (exists (select 1 from public.so_payment_alloc a join public.so_payment pm on pm.id = a.payment_id where a.invoice_id = i.existing_id and a.voided_at is null and pm.status = 'active')
      or exists (select 1 from public.so_credit_alloc ca join public.so_credit c on c.id = ca.credit_id where ca.invoice_id = i.existing_id and ca.voided_at is null and c.status = 'issued'));
  update ar2_inv i set action = 'reject', reason = 'cancelled_in_ims' where i.action = 'update' and exists (select 1 from public.so_invoice e where e.id = i.existing_id and e.status <> 'issued');

  -- ── ② 받아 둔 돈 줄 풀기 → (손님, 통화) 묶기 ──
  v_seq := 0;
  for x in select t from jsonb_array_elements(coalesce(p->'credits', '[]'::jsonb)) t loop
    v_seq := v_seq + 1;
    insert into ar2_cr (seq, cin7_customer_id, currency_code, amount, source, reference)
    values (v_seq, nullif(btrim(x->>'cin7_customer_id'), '')::uuid, upper(nullif(btrim(x->>'currency'), '')), nullif(x->>'amount', '')::numeric, lower(nullif(btrim(x->>'source'), '')), nullif(btrim(x->>'reference'), ''));
  end loop;
  update ar2_cr r set store_id = c.id, store_name = c.name, store_warehouse_id = c.default_location_id, customer_id = coalesce(c.default_bill_to_customer_id, c.id) from public.customer c where c.cin7_id = r.cin7_customer_id;   -- 돈은 청구처 앞으로(결제의 손님 = 청구처 · 발행 때 자동 소진 · 잔액이 보는 손님) · 매장 이름은 note 에
  update ar2_cr r set customer_name = b.name from public.customer b where b.id = r.customer_id;
  update ar2_cr r set currency_id = rc.id from public.ref_currency rc where rc.code = r.currency_code and rc.is_active;
  update ar2_cr r set reason = case
    when r.cin7_customer_id is null then 'customer_id_missing'
    when r.customer_id is null then 'customer_unresolved'
    when r.currency_id is null then 'currency_unresolved'
    when r.amount is null or r.amount <= 0 then 'amount_invalid'
    when r.amount <> round(r.amount, 2) then 'amount_decimals'
    when r.source is null or r.source not in ('credit', 'overpay') then 'source_invalid'
    end;
  insert into ar2_crg (customer_id, customer_name, currency_id, currency_code, amount, n, note)
  select r.customer_id, r.customer_name, r.currency_id, r.currency_code, sum(r.amount), count(*)::int,
         left(string_agg(r.source || ' ' || r.amount::text || coalesce(' — ' || r.reference, '') || case when r.store_id <> r.customer_id then ' (' || r.store_name || ')' else '' end, ' | ' order by r.seq), 2000)
    from ar2_cr r where r.reason is null group by r.customer_id, r.customer_name, r.currency_id, r.currency_code;
  update ar2_crg g set warehouse_id = w.id, warehouse_name = w.name from public.ref_warehouse w where w.is_active and w.id = (select r.store_warehouse_id from ar2_cr r where r.customer_id = g.customer_id and r.currency_id = g.currency_id and r.reason is null and r.store_warehouse_id is not null order by r.seq limit 1);   -- 브랜치 = 매장(이전 시스템의 손님)의 위치 칸 · 첫 줄
  update ar2_crg g set warehouse_id = w.id, warehouse_name = w.name from public.customer c join public.ref_warehouse w on w.id = c.default_location_id and w.is_active where c.id = g.customer_id and g.warehouse_id is null;   -- 없으면 청구처의 위치 칸 · 그것도 없으면 거부
  update ar2_crg g set existing_id = pm.id from public.so_payment pm where pm.customer_id = g.customer_id and pm.currency_id = g.currency_id and pm.method = 'opening';
  update ar2_crg g set action = case
    when g.warehouse_id is null then 'reject'
    when g.existing_id is null then 'insert'
    when exists (select 1 from public.so_payment pm where pm.id = g.existing_id and pm.status = 'active' and pm.amount = g.amount and pm.note is not distinct from g.note and pm.paid_on = v_as_of) then 'same'
    else 'update' end,
    reason = case when g.warehouse_id is null then 'branch_unresolved' end;
  update ar2_crg g set action = 'reject', reason = 'has_ims_allocations' where g.action = 'update'
    and (exists (select 1 from public.so_payment_alloc a where a.payment_id = g.existing_id and a.voided_at is null)
      or exists (select 1 from public.so_payment pm where pm.customer_id = g.customer_id and pm.currency_id = g.currency_id and pm.kind = 'refund' and pm.status = 'active'));
  update ar2_crg g set action = 'reject', reason = 'voided_in_ims' where g.action = 'update' and exists (select 1 from public.so_payment pm where pm.id = g.existing_id and pm.status <> 'active');

  -- ── ③ 쓰기(Dry 가 아닐 때만 · 판단은 위에서 끝났다) ──
  if not p_dry then
    for v_inv in select * from ar2_inv i where i.action = 'insert' order by i.seq loop
      insert into public.so_invoice (invoice_number, status, kind, bill_to_customer_id, bill_to_name, store_customer_id, legacy_sale_id, legacy_invoice_id,
                                     issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code,
                                     lines_amount, order_discount_amount, charges_amount, charges_discount_amount, surcharge_amount, taxable_amount, tax_amount, total,
                                     deposit_applied, credit_applied, balance_forward, amount_due, prior_settled)
      values (v_inv.invoice_number, 'issued', 'opening', v_inv.bill_to_id, v_inv.bill_to_name, v_inv.store_id, v_inv.legacy_sale_id, v_inv.legacy_invoice_id,
              v_inv.issued_on, null, v_inv.term_id, v_inv.term_name, v_inv.due_on, v_inv.currency_id, v_inv.currency_code,
              v_inv.lines_amount, 0, 0, 0, 0, v_inv.lines_amount, v_inv.tax, v_inv.total,
              0, 0, null, v_inv.total, v_inv.prior_settled);
    end loop;
    for v_inv in select * from ar2_inv i where i.action = 'update' order by i.seq loop
      update public.so_invoice set invoice_number = v_inv.invoice_number, bill_to_customer_id = v_inv.bill_to_id, bill_to_name = v_inv.bill_to_name, store_customer_id = v_inv.store_id, legacy_sale_id = v_inv.legacy_sale_id,
                                   issued_on = v_inv.issued_on, payment_term_id = v_inv.term_id, payment_term_name = v_inv.term_name, due_on = v_inv.due_on, currency_id = v_inv.currency_id, currency_code = v_inv.currency_code,
                                   lines_amount = v_inv.lines_amount, taxable_amount = v_inv.lines_amount, tax_amount = v_inv.tax, total = v_inv.total, amount_due = v_inv.total, prior_settled = v_inv.prior_settled
      where id = v_inv.existing_id and kind = 'opening';
      get diagnostics v_n = row_count;
      if v_n <> 1 then raise exception 'Opening invoice % (legacy %) was not updated — nothing was saved', v_inv.invoice_number, v_inv.legacy_invoice_id; end if;
    end loop;
    for v_cr in select * from ar2_crg g where g.action = 'insert' loop
      insert into public.so_payment (kind, amount, paid_on, method, reference, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, note, created_by, updated_by)
      values ('payment', v_cr.amount, v_as_of, 'opening', 'Opening balance ' || v_as_of::text, v_cr.customer_id, v_cr.currency_id, v_cr.currency_code, v_acct.id, v_acct.code, v_cr.warehouse_id, v_cr.warehouse_name, v_cr.note, null, null);
    end loop;
    for v_cr in select * from ar2_crg g where g.action = 'update' loop
      update public.so_payment set amount = v_cr.amount, paid_on = v_as_of, reference = 'Opening balance ' || v_as_of::text, note = v_cr.note, account_id = v_acct.id, account_code = v_acct.code, warehouse_id = v_cr.warehouse_id, warehouse_name = v_cr.warehouse_name
      where id = v_cr.existing_id and method = 'opening' and status = 'active';
      get diagnostics v_n = row_count;
      if v_n <> 1 then raise exception 'Opening balance for customer % (%) was not updated — nothing was saved', v_cr.customer_name, v_cr.currency_code; end if;
    end loop;
  end if;

  -- ── ④ 반환 ──
  select array_agg(i.legacy_invoice_id) into v_ids from ar2_inv i where i.legacy_invoice_id is not null;
  v_inv_out := jsonb_build_object(
    'in',        (select count(*) from ar2_inv),
    'inserted',  (select count(*) from ar2_inv i where i.action = 'insert'),
    'updated',   (select count(*) from ar2_inv i where i.action = 'update'),
    'same',      (select count(*) from ar2_inv i where i.action = 'same'),
    'rejected',  (select count(*) from ar2_inv i where i.action = 'reject'),
    'rejects',   (select coalesce(jsonb_agg(jsonb_build_object('seq', i.seq, 'legacy_invoice_id', i.legacy_invoice_id, 'invoice_number', i.invoice_number, 'cin7_customer_id', i.cin7_customer_id, 'customer_name', i.store_name, 'reason', i.reason) order by i.seq), '[]'::jsonb) from ar2_inv i where i.action = 'reject'),
    'by_currency', (select coalesce(jsonb_agg(jsonb_build_object('currency_code', g.currency_code, 'count', g.n, 'total', g.tot, 'prior_settled', g.ps, 'remaining', g.tot - g.ps) order by g.currency_code), '[]'::jsonb)
                    from (select i.currency_code, count(*)::int n, sum(i.total) tot, sum(i.prior_settled) ps from ar2_inv i where i.action in ('insert', 'update', 'same') group by i.currency_code) g),
    'customer_unresolved', (select count(*) from ar2_inv i where i.reason = 'customer_unresolved'),
    'term_unresolved',     (select count(*) from ar2_inv i where i.action in ('insert', 'update', 'same') and i.term_id is null),
    'due_unknown',         (select count(*) from ar2_inv i where i.action in ('insert', 'update', 'same') and i.due_on is null),
    'before_tax_adjusted', jsonb_build_object('count', (select count(*) from ar2_inv i where i.action in ('insert', 'update', 'same') and i.btx_adj <> 0), 'sum_abs', (select coalesce(sum(abs(i.btx_adj)), 0) from ar2_inv i where i.action in ('insert', 'update', 'same') and i.btx_adj <> 0)),
    'existing_not_in_input', case when v_complete then (select jsonb_build_object('count', count(*), 'invoice_numbers', coalesce(jsonb_agg(e.invoice_number order by e.invoice_number) filter (where e.invoice_number is not null), '[]'::jsonb))
                                                         from (select e.invoice_number from public.so_invoice e where e.kind = 'opening' and not (e.legacy_invoice_id = any(coalesce(v_ids, '{}'::text[]))) order by e.invoice_number limit 50) e)
                             else null end);
  v_cr_out := jsonb_build_object(
    'rows_in',   (select count(*) from ar2_cr),
    'groups',    (select count(*) from ar2_crg),
    'inserted',  (select count(*) from ar2_crg g where g.action = 'insert'),
    'updated',   (select count(*) from ar2_crg g where g.action = 'update'),
    'same',      (select count(*) from ar2_crg g where g.action = 'same'),
    'rejected',  (select count(*) from ar2_cr r where r.reason is not null) + (select count(*) from ar2_crg g where g.action = 'reject'),
    'rejects',   (select coalesce(jsonb_agg(j order by (j->>'seq')::int nulls last), '[]'::jsonb) from (
                    select jsonb_build_object('seq', r.seq, 'cin7_customer_id', r.cin7_customer_id, 'customer_name', r.customer_name, 'currency_code', r.currency_code, 'amount', r.amount, 'reason', r.reason) j from ar2_cr r where r.reason is not null
                    union all
                    select jsonb_build_object('seq', null, 'customer_id', g.customer_id, 'customer_name', g.customer_name, 'currency_code', g.currency_code, 'amount', g.amount, 'reason', g.reason) from ar2_crg g where g.action = 'reject') u),
    'by_currency', (select coalesce(jsonb_agg(jsonb_build_object('currency_code', g.currency_code, 'count', g.n, 'amount', g.amt) order by g.currency_code), '[]'::jsonb)
                    from (select g.currency_code, count(*)::int n, sum(g.amount) amt from ar2_crg g where g.action in ('insert', 'update', 'same') group by g.currency_code) g),
    'customer_unresolved', (select count(*) from ar2_cr r where r.reason = 'customer_unresolved'),
    'branch_unresolved',   (select count(*) from ar2_crg g where g.reason = 'branch_unresolved'),
    'large', (select coalesce(jsonb_agg(jsonb_build_object('customer_name', g.customer_name, 'currency_code', g.currency_code, 'amount', g.amount, 'note', g.note) order by g.amount desc), '[]'::jsonb) from ar2_crg g where g.action in ('insert', 'update', 'same') and g.amount >= 1000),
    'existing_not_in_input', case when v_complete then (select jsonb_build_object('count', count(*), 'customers', coalesce(jsonb_agg(jsonb_build_object('customer_name', c.name, 'currency_code', pm.currency_code, 'amount', pm.amount) order by c.name), '[]'::jsonb))
                                                         from public.so_payment pm join public.customer c on c.id = pm.customer_id
                                                         where pm.method = 'opening' and not exists (select 1 from ar2_crg g where g.customer_id = pm.customer_id and g.currency_id = pm.currency_id))
                             else null end);
  v_out := jsonb_build_object('dry', p_dry, 'as_of', v_as_of, 'complete', v_complete,
                              'account', jsonb_build_object('id', v_acct.id, 'code', v_acct.code, 'name', v_acct.name),
                              'invoices', v_inv_out, 'credits', v_cr_out,
                              'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  return v_out;
end $fn$;
revoke all on function public.so_opening_load(jsonb, boolean) from public, anon, authenticated;
grant execute on function public.so_opening_load(jsonb, boolean) to service_role;
comment on function public.so_opening_load(jsonb, boolean) is 'ar-2 판정 775 · 783 ~ 786: 컷오버 날 이월 적재(service_role · Apps Script ar-3) — invoices[] → so_invoice kind opening(옛 번호 · 발행일 · 기한 · 금액 · prior_settled · 옛 열쇠) · credits[] → so_payment method opening(손님 · 통화별 한 줄 · 계정 _1150040009_ · 손님 브랜치) · 멱등(legacy_invoice_id · (customer, currency) 로 덮어쓰기 · IMS 붙임이 있으면 그 줄 거부) · p_dry true(기본) 는 같은 판단 · 쓰기 0 · 반환 jsonb 넣음 · 바뀜 · 같음 · 거부(이유) · 통화별 합 · 못 찾음(손님 · 결제조건 · 브랜치) · complete true 면 입력에 없는 기존 이월 줄도 보고(지우지 않는다)';

-- ═══ 9) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice' and column_name in ('kind', 'prior_settled', 'store_customer_id', 'legacy_sale_id', 'legacy_invoice_id')) <> 5 then v_bad := v_bad || ' so_invoice(columns)'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.so_invoice'::regclass and conname in ('so_invoice_kind_ck', 'so_invoice_prior_settled_ck', 'so_invoice_opening_ck')) <> 3 then v_bad := v_bad || ' so_invoice(checks)'; end if;
  if (select count(*) from pg_indexes where schemaname = 'public' and indexname in ('so_invoice_legacy_invoice_uq', 'so_invoice_legacy_sale_idx', 'so_invoice_store_customer_idx', 'so_invoice_number_norm_idx', 'so_payment_opening_uq')) <> 5 then v_bad := v_bad || ' indexes'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'so_payment_method_ck') not like '%''opening''%' then v_bad := v_bad || ' so_payment_method_ck'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.so_invoice'::regclass and conname in ('so_invoice_total_ck', 'so_invoice_taxable_ck', 'so_invoice_due_ck', 'so_invoice_number_ck')) <> 4 then v_bad := v_bad || ' so_invoice(old checks gone)'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_invoice_remaining';
  if v_src not like '%i.total - i.prior_settled - coalesce(%' then v_bad := v_bad || ' so_invoice_remaining'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_auto_invoice';
  if v_src not like '%if new.kind = ''opening'' then return null; end if;%' then v_bad := v_bad || ' doc_mail_auto_invoice'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'drive_archive_on_issue';
  if v_src not like '%= ''opening'' then return null; end if;%' then v_bad := v_bad || ' drive_archive_on_issue'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_invoice_cancel';
  if v_src not like '%cannot be cancelled%' then v_bad := v_bad || ' so_invoice_cancel'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_void';
  if v_src not like '%it cannot be voided%' then v_bad := v_bad || ' so_payment_void'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_data_invoice';
  if v_src not like '%the original is in QuickBooks%' then v_bad := v_bad || ' doc_data_invoice'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice_list' and column_name in ('kind', 'prior_settled', 'store_customer_id', 'store_name', 'legacy_sale_id', 'legacy_invoice_id')) <> 6 then v_bad := v_bad || ' so_invoice_list'; end if;
  if (select reloptions::text from pg_class where relname = 'so_invoice_list' and relnamespace = 'public'::regnamespace) not like '%security_invoker=true%' then v_bad := v_bad || ' so_invoice_list(invoker)'; end if;
  if to_regprocedure('public.so_opening_load(jsonb, boolean)') is null then v_bad := v_bad || ' so_opening_load(missing)';
  else
    if has_function_privilege('authenticated', 'public.so_opening_load(jsonb, boolean)', 'execute') or has_function_privilege('anon', 'public.so_opening_load(jsonb, boolean)', 'execute') or not has_function_privilege('service_role', 'public.so_opening_load(jsonb, boolean)', 'execute') then v_bad := v_bad || ' so_opening_load(grants)'; end if;
  end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM786', message = format('STOP - ar-2 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
