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
-- qbo-sync-2c1 — QuickBooks 크레딧 노트 보내기 DB 몸 · 발행 · 취소 트리거 · 채우기 · 일감 창구 재발행 + IMS 문 둘(959 · 968 인보이스 취소 거부 · 966 세금 줄 거부) (2026-11-02 · 판정 959 ~ 966 · 968 · 지시서 ~/asung/prompts/qbo-sync-2c-1.md · Fable)
--   경계: 2c1 = DB(이 파일) + EF qbo(같은 커밋 · _shared/qbo.ts SEND_KINDS 에 credit · credit_void · CreditMemo POST · void · DocNumber 멱등 · unknown 풀기) · 화면(so-credits.html 꼬리표 · settings.html 탭 이름)은 대화 Claude
--   ⚠️ 적용 순서 한 덩이: 이 마이그레이션 → repair → EF 배포 — 트리거가 먼저 서고 EF 가 옛 SEND_KINDS 면 queued credit 일감이 cron 61 의 where 를 통과해 빈 claim 을 부른다(qbo_send_enabled off 면 호출 0 · 켜는 것은 Caleb · 2b ⑥)
--   A 판정 968 · 969 · 959 — so_invoice_cancel 재발행(마지막 정의 20261027014202 · md5 689061bf…): 손으로 넣은 결제(manual) 충당이 살아 있으면 거부(글 968) · auto_deposit · auto_balance 는 옛 동작 그대로 취소와 함께 void(969 · 손님 계정으로) · issued 크레딧이 invoice_id 로 가리키면 거부(번호 나열)
--   B 판정 966 — so_credit_issue 재발행(마지막 정의 20261027010153 · md5 1530f29b…): kind tax 를 받는 목록에서 뺀다(이견 1 (나) · 글 「A tax-only credit note is not allowed — credit the invoice in full and issue a corrected invoice instead」) · tax 갈래 본문 제거 · CHECK · 옛 행 그대로 · 화면은 이미 tax 를 보내지 않는다
--   C 몸: qbo_credit_body(p_credit_id)(935 · 936 · 939 · 942 · 951 · 960 ~ 962) — CustomerRef = coalesce(store_customer_id, customer_id) · 주소 = 크레딧 노트 PDF 와 같은 규칙(doc_data_credit: 인보이스 크레딧은 그 인보이스 bill_to + 첫 오더 ship_to · 참조 크레딧은 청구처 기본 Billing + 매장 기본 Shipping · 962)
--        BillEmail = doc_mail_recipient(customer_id)(이견 4) · PrivateNote = 「Credit for invoice <번호> · Customer Reference: <refs>」 · CustomerMemo = 같은 글 + 「, <매장>」(939 꼴) · TxnDate = issued_on · DueDate · SalesTermRef · ShipDate · TrackingNum 없음
--        줄 = so_credit_line(line_no 순 · 콤보 구성품 줄(combo_credit_line_id · 0 원)은 보내지 않는다 · 이견 6) · product · price_adjustment → qbo_link product(없으면 needs item · 937) · surcharge → charge surcharge(needs) · order_discount → charge discount · freight · freight_discount → 그 인보이스 줄의 so_charge(service · _99_ freight · acct:<code> · 951) · 참조 크레딧 freight → charge freight
--        other · restocking_fee → charge acct:<account_code>(961 · 없으면 예외 = failed + 「link account item …」 · _99_ 면 freight) · tax 줄(옛 행만) → 예외 · TaxCodeRef = 인보이스 줄 → 그 so_invoice_order 의 규칙 / 참조 크레딧 머리 규칙 / 첫 오더 규칙 · TxnTaxDetail = 규칙마다 TaxLine(TaxRateRef = qbo_entity.detail) · 942 totals
--        960: invoice_id 가 있고 그 인보이스가 since 이후 발행(이월 아님)인데 qbo_txn 이 없으면 — 인보이스 일감 없음 → 예외 「Invoice N has no QuickBooks job — send the invoice first」(이견 2b) · skipped → 예외 「… was skipped — skip this credit note too, or retry the invoice first」(2a) · 열린 일감 → wait_job(claim 이 blocked_by) · sent → 간다
--        qbo_credit_void_body(p_credit_id) — qbo_txn(credit) 의 Id · SyncToken(없으면 경고 · EF 가 읽는다) · 보낸 적 없음 · 이미 void 면 예외
--   D 트리거 둘(so_credit · 인보이스 꼴): so_credit_qbo_job(AFTER INSERT DEFERRABLE INITIALLY DEFERRED · 같은 트랜잭션 취소 · since 전 · 연결 없음 조용히 · 오류 삼킴 → failed 일감) · so_credit_qbo_cancel(AFTER UPDATE OF status → 안 나갔으면 skipped · sending · unknown 이면 credit_void blocked_by · 보냈으면 credit_void queued)
--      채우기 qbo_credit_backfill()(965 · grant 0): since 이후 발행 · 일감 · 거래 짝 없는 크레딧을 queued 로 — 이 파일 끝에서 한 번 부르고 NOTICE 로 수를 찍는다(채운 일감도 claim 때 960 대로 자기 인보이스를 기다린다)
--   E 짝 열쇠 961 = 951 과 같은 qbo_link(charge · acct:<code>) — qbo_ims_rows('charge') 의 acct: 행 조건에 so_credit_line(other · restocking_fee)이 쓴 계정을 더한다(2b1 바이트 + or exists 한 줄) · 화면 반환 꼴 무변(qbo_link_page 그대로)
--   F 창구 재발행: qbo_job_claim(2b1 바이트 + credit · credit_void 몸 + wait_job → blocked_by 인보이스 일감(blocked_for_invoice 셈) · 「not sendable yet (2c)」 글 제거) · qbo_job_done(credit → qbo_txn CreditMemo + 942 대조 so_credit.total · tax_amount · credit_void → voided_at) · qbo_job_list(credit ims_name = 번호 · 청구처 · 통화 총액)
--   무접촉: qbo_invoice_body · qbo_void_body · qbo_job_open_or_add · 인보이스 트리거 둘 · qbo_txn_of(이미 credit 을 받는다) · qbo_job_add · retry · skip · fail · unknown · so_credit_cancel · 화면 · cron 61(where 는 kind 를 보지 않는다)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261102130000_qbo_sync_2c1_credit_jobs.sql && supabase migration repair --status applied 20261102130000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=supabase/migrations/20261102130000_qbo_sync_2c1_credit_jobs.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2c1_check.sql

-- ═══ A) 판정 968 · 969 · 959 — so_invoice_cancel 재발행(원본 바이트 + 검사 둘 · manual 거부 글을 968 로 · auto void 갈래 그대로) ═══
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
  v_pay    int;     v_cr_open text;                      -- qbo-sync-2c1 판정 968 · 959
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

  -- [qbo-sync-2c1 · 판정 968 · 969] 손으로 넣은 결제(manual)가 하나라도 적용된 인보이스는 취소를 거부한다(글만 968 로) · 발행 때 자동으로 붙은 것(auto_deposit · auto_balance)은 옛 동작 그대로 취소와 함께 void(손님 계정으로 돌아간다 · ⓑ2 판정 7)
  select count(*) into v_pay from public.so_payment_alloc a where a.invoice_id = p_invoice_id and a.voided_at is null and a.source = 'manual';
  if v_pay > 0 then
    raise exception 'Invoice % has payments — settle it with a credit note instead — nothing was saved', v_inv.invoice_number;
  end if;
  -- [qbo-sync-2c1 · 판정 959] 발행된 크레딧 노트가 이 인보이스를 가리키면 취소를 거부한다 — 먼저 그 크레딧을 취소하라(지금까지는 so_credit.invoice_id 를 보지 않아 같은 반품을 두 번 깎아 줄 수 있었다)
  select string_agg(c.credit_number, ', ' order by c.credit_number) into v_cr_open from public.so_credit c where c.invoice_id = p_invoice_id and c.status = 'issued';
  if v_cr_open is not null then
    raise exception 'Invoice % has credit note(s) % — cancel those credit notes first — nothing was saved', v_inv.invoice_number, v_cr_open;
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

-- ═══ B) 판정 966 — so_credit_issue 재발행(원본 바이트 + tax 줄 거부 · tax 갈래 제거) ═══
CREATE OR REPLACE FUNCTION public.so_credit_issue(p jsonb, p_commit boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_reasons   constant text[] := array['customer_return','damaged','billing_error','other','price_adjustment'];   -- crn-2 판정 612
  c_nr        constant text[] := array['damaged','b_grade','not_returned','other'];
  v_staff     uuid;
  v_on        date;
  v_reason    text;
  v_inv       public.so_invoice%rowtype;
  v_c         public.customer%rowtype;
  v_cur       public.ref_currency%rowtype;
  v_w         public.ref_warehouse%rowtype;
  v_rule      public.ref_tax_rule%rowtype;
  v_cr        public.so_credit%rowtype;
  v_il        public.so_invoice_line%rowtype;
  v_io        public.so_invoice_order%rowtype;
  v_pr        public.product%rowtype;
  v_bin       public.ref_bin%rowtype;
  v_acct      public.ref_account%rowtype;
  v_ref       boolean := false;                                                                        -- crn-1 판정 602 · 609: 참조 크레딧(인보이스 없음 · 옛 이름 cin7)
  v_ref_inv   text;  v_ref_ord text;  v_ref_date date;
  v_tax_src   text;  v_sa public.customer_address%rowtype;  v_tr jsonb;  v_seen text;                  -- crn-1 판정 610: 세금 기본 = 손님 기본 배송지의 규칙 · 경고 reference_seen
  v_cust      uuid;
  v_origin_on date;
  v_wh        uuid;
  v_bgb       uuid;                                                                   -- bgr-1d: 반품하는 인보이스 줄의 B급 칸(정상 줄 · 참조 크레딧은 null)
  v_first_io  public.so_invoice_order%rowtype;
  v_fee_days  int;  v_fee_pct numeric;  v_fee_acct_code text;
  v_lines     jsonb := '[]'::jsonb;
  v_ln        int := 0;
  v_kind      text;
  v_qty       numeric;  v_already numeric;  v_unit numeric;  v_amount numeric;  v_rate numeric;  v_tax numeric;
  v_bin_name  text;  v_bin_id uuid;  v_nr text;  v_nr_note text;  v_desc text;  v_acct_id uuid;  v_acct_code text;
  v_product_id uuid;  v_so_line_id uuid;  v_sku text;  v_il_id uuid;
  v_lines_amt numeric := 0;  v_fee_amt numeric := 0;  v_tax_amt numeric := 0;  v_product_amt numeric := 0;
  v_od_amt    numeric := 0;  v_od record;  v_od_il public.so_invoice_line%rowtype;                                      -- dsc-3b 판정 325 — 오더 할인 몫(인보이스-오더마다 음수 줄 하나)
  v_sc        public.so_invoice_line%rowtype;  v_sc_amt numeric := 0;  v_sc_line numeric;  v_sc_tax numeric;  v_sc_already numeric;   -- surcharge-2b(묶음 7)
  v_fd        public.so_invoice_line%rowtype;  v_fd_amt numeric := 0;  v_fd_line numeric := 0;  v_fd_tax numeric;  v_fd_already numeric;  v_fd_inv numeric;   -- fr-3 판정 355: 운임 할인 되돌림(인보이스 charge_discount 줄 · 같은 비율 · 끝수는 마지막에)
  v_rates     numeric[] := '{}';  v_first_rate numeric;
  v_fee_lines int := 0;  v_restock_n int := 0;
  v_fee_sugg  jsonb;
  v_warn      text[] := '{}';
  v_ledger    jsonb;
  v_est       numeric;  v_est_qty numeric;
  v_ask       numeric;
  x           jsonb;
  e           jsonb;
  -- asm-2b2(묶음 7 · 판정 245): 콤보 인보이스 줄의 반품 — 콤보 크레딧 줄(금액 · qty = 콤보 수 · 칸 · 사유 없음 · combo_components) + 구성품 크레딧 줄(금액 0 · qty = n × combo_qty · 제 칸 또는 사유 · combo_credit_line_id) · 구성품 하나만의 상품 줄은 거부
  v_combo     jsonb;  cj jsonb;  v_cov jsonb;  v_def_bin text;  v_def_nr text;  v_def_note text;  v_cpr public.product%rowtype;  v_cq numeric;  v_idmap jsonb := '{}'::jsonb;  v_parent_ln int;
  -- crn-2(판정 603 · 611 · 613 · 614): 인보이스 줄마다 가격 층(tiers · so_credit_line_state) — 이 호출 안의 반품 · 조정이 차례로 깎는다 · v_odb = 줄 번호 → 오더 할인 거울의 기준 금액(조정된 몫은 뺀다)
  v_tiers     jsonb := '{}'::jsonb;  v_take jsonb;  v_tier jsonb;  v_odb jsonb := '{}'::jsonb;  v_od_base numeric;  v_before numeric;  v_after numeric;  v_adj_n int := 0;  v_ret_n int := 0;
  -- hcr-1(판정 774 · 778 · 779 · 781): 참조 크레딧이 이력(hist_)을 읽기만 한다 — 매장 칸(v_store) · 778 반영 단가 · 남은 수량 경고 · 781 세금 제안 · 경고를 기록(so_credit.warnings)에 남긴다
  v_store     uuid;  v_hl jsonb := '{}'::jsonb;  v_hist_found boolean := false;  v_hist_manual boolean := false;  v_hist_tax jsonb;  v_hu numeric;  v_hrem numeric;  v_hask numeric;  v_wt text;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 발행은 manager 이상(판정 3)
  v_staff := public.so_current_staff();
  v_on := coalesce(nullif(p->>'issued_on', '')::date, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Credit date % is in the future — nothing was saved', v_on; end if;
  v_reason := nullif(trim(p->>'reason'), '');
  if v_reason is null or v_reason <> all (c_reasons) then raise exception 'reason must be one of customer_return, damaged, billing_error, other — nothing was saved'; end if;
  if v_reason = 'other' and nullif(trim(p->>'note'), '') is null then raise exception 'reason other needs a note — nothing was saved'; end if;
  if p->'lines' is null or jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;
  if exists (select 1 from jsonb_array_elements(p->'lines') bx                                                          -- bgr-1e 판정 651: 「안 돌아옴 · b_grade」 는 새로 못 쓴다(줄 · 콤보 구성품 · 미리 보기도)
              where nullif(trim(bx->>'not_restocked_reason'), '') = 'b_grade'
                 or exists (select 1 from jsonb_array_elements(case when jsonb_typeof(bx->'components') = 'array' then bx->'components' else '[]'::jsonb end) bc
                             where nullif(trim(bc->>'not_restocked_reason'), '') = 'b_grade')) then
    raise exception 'B-grade goods go back into a B-grade bin now — pick a B-grade bin as the restock bin, or use damaged if it is thrown out — nothing was saved';
  end if;

  -- 설정(판정 5·7)
  select nullif(k.value, '')::int into v_fee_days from public.inv_config k where k.key = 'so_credit_restock_fee_days';
  select nullif(k.value, '')::numeric into v_fee_pct from public.inv_config k where k.key = 'so_credit_restock_fee_pct';
  select nullif(k.value, '') into v_fee_acct_code from public.inv_config k where k.key = 'so_credit_restock_fee_account_code';

  -- 원본 — IMS 인보이스 또는 참조 번호(옛 인보이스 종이 번호 · 판정 602 · 609 — 옛 열쇠 cin7 은 거부)
  if nullif(p->>'invoice_id', '') is not null then
    select * into v_inv from public.so_invoice i where i.id = (p->>'invoice_id')::uuid for update;
    if not found then raise exception 'Invoice not found — nothing was saved'; end if;
    if v_inv.status <> 'issued' then raise exception 'Invoice % is % — credit the live invoice, not a cancelled one — nothing was saved', v_inv.invoice_number, v_inv.status; end if;
    v_cust := v_inv.bill_to_customer_id;  v_origin_on := v_inv.issued_on;
    select * into v_cur from public.ref_currency c where c.id = v_inv.currency_id;
    select o.* into v_first_io from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;
    select s.location_id into v_wh from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id order by o.so_number limit 1;
    select s.customer_id into v_store from public.so s where s.id = v_first_io.so_id;                                                                   -- hcr-1 판정 779: 인보이스 크레딧의 매장 = 첫 오더(so_number 순)의 손님
  elsif p ? 'cin7' then
    raise exception 'The cin7 key is gone — send ref {invoice_number, order_number, invoice_date} for a credit without an IMS invoice — nothing was saved';   -- crn-1 판정 609
  elsif p->'ref' is not null and jsonb_typeof(p->'ref') = 'object' then
    v_ref := true;
    v_ref_inv := nullif(trim(p->'ref'->>'invoice_number'), '');  v_ref_ord := nullif(trim(p->'ref'->>'order_number'), '');  v_ref_date := nullif(p->'ref'->>'invoice_date', '')::date;
    if v_ref_inv is null then raise exception 'A reference credit needs ref.invoice_number (the number on the paper invoice) — nothing was saved'; end if;
    if nullif(p->>'customer_id', '') is null then raise exception 'A reference credit needs customer_id — nothing was saved'; end if;
    v_cust := (p->>'customer_id')::uuid;  v_origin_on := v_ref_date;
    if not exists (select 1 from public.customer c where c.id = v_cust) then raise exception 'Customer not found — nothing was saved'; end if;
    v_store := nullif(p->>'store_customer_id', '')::uuid;                                                                                       -- hcr-1 판정 779: 매장(종이 · 목록의 이름) · 돈(customer_id)은 매장의 청구처 coalesce(default_bill_to_customer_id, id) 여야 한다
    if v_store is not null then
      if not exists (select 1 from public.customer c where c.id = v_store) then raise exception 'Store customer not found — nothing was saved'; end if;
      if v_cust <> (select coalesce(c.default_bill_to_customer_id, c.id) from public.customer c where c.id = v_store) then
        raise exception 'customer_id must be the bill-to of store % — the money goes to the bill-to, the paper and the list show the store — nothing was saved', (select c.name from public.customer c where c.id = v_store);
      end if;
    else
      v_store := v_cust;
    end if;
    v_hist_found := exists (select 1 from public.hist_so_line hl where hl.doc_type = 'invoice' and lower(trim(hl.doc_number)) = lower(v_ref_inv));          -- hcr-1 판정 774: 옛 인보이스가 이력에 있으면 읽는다(없으면 옛 동작 그대로)
    if v_hist_found then                                                                                                                            -- 한 곳(hist_credit_lines)의 778 단가 · 남은 수량 — 창구 hist_credit_source 와 같은 식
      select coalesce(jsonb_object_agg(k.key, jsonb_build_object('unit', k.unit, 'rem', k.rem)), '{}'::jsonb) into v_hl
        from (select coalesce(h.product_id::text, upper(h.sku)) as key, min(h.unit_price_adj) as unit, sum(h.qty_remaining) as rem from public.hist_credit_lines(v_ref_inv) h where h.kind = 'product' group by 1) k;
    end if;
    select * into v_cur from public.ref_currency c
     where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), (select c3.currency_id from public.customer c3 where c3.id = v_cust));
    if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
    if nullif(trim(p->>'tax_rule'), '') is not null then                                                  -- 보낸 규칙 그대로(활성 판매 규칙 검사 그대로)
      select * into v_rule from public.ref_tax_rule r where r.name = trim(p->>'tax_rule') and r.direction = 'sale' and r.is_active;
      if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', trim(p->>'tax_rule'); end if;
      v_tax_src := 'given';
    elsif v_hist_found then                                                                               -- hcr-1 판정 781: 이력의 세율 = 매장 지금 규칙이면 그 규칙 · 다르면 같은 세율의 규칙(하나면 제안 · 여럿 · 없음이면 거부 글로 고르라) · 「다르다」 는 경고
      v_hist_tax := public.hist_credit_tax(v_ref_inv, v_store, v_on);
      if nullif(v_hist_tax->'suggested'->>'rule_id', '') is null then
        raise exception 'Pick a tax rule — invoice % was taxed at % percent and % active sale rule(s) have that rate (%) — nothing was saved', v_ref_inv, trim_scale(coalesce((v_hist_tax->>'old_rate_pct')::numeric, 0)),
          jsonb_array_length(coalesce(v_hist_tax->'candidates', '[]'::jsonb)), coalesce((select string_agg(cx->>'rule', ', ') from jsonb_array_elements(coalesce(v_hist_tax->'candidates', '[]'::jsonb)) cx), '-');
      end if;
      select * into v_rule from public.ref_tax_rule r where r.id = (v_hist_tax->'suggested'->>'rule_id')::uuid;
      v_tax_src := 'history';
      if coalesce((v_hist_tax->>'differs')::boolean, false) then v_warn := array_append(v_warn, 'tax_rule_differs:' || coalesce(v_hist_tax->'current_rule'->>'rule', '-')); end if;
    else                                                                                                  -- crn-1 판정 610: 손님 기본 배송지의 주 → so_tax_rule_for(IMS 인보이스와 같은 식) · 없으면 거부(직원이 고른다)
      select * into v_sa from public.customer_address a where a.customer_id = coalesce(v_store, v_cust) and a.type = 'Shipping' and a.is_active and a.is_default_for_type limit 1;
      if v_sa.id is null then raise exception 'Pick a tax rule — the customer has no default ship-to address to suggest one from — nothing was saved'; end if;
      v_tr := public.so_tax_rule_for(v_sa.country, v_sa.state_province, v_on, 'sale');
      if nullif(v_tr->>'rule_id', '') is null then raise exception 'Pick a tax rule — no sale tax rule is linked to the customer''s default ship-to (% / %) — nothing was saved', coalesce(v_sa.country, '?'), coalesce(v_sa.state_province, '?'); end if;
      select * into v_rule from public.ref_tax_rule r where r.id = (v_tr->>'rule_id')::uuid;
      v_tax_src := 'ship_to';
    end if;
    select c.default_location_id into v_wh from public.customer c where c.id = v_cust;
  else
    raise exception 'Give invoice_id (an IMS invoice) or ref {invoice_number, order_number, invoice_date} (a credit without an IMS invoice) — nothing was saved';
  end if;
  select * into v_c from public.customer c where c.id = v_cust for update;         -- 청구처 손님 행 잠금(잔액 직렬화 · ⓑ 와 같은 자물쇠)
  if not found then raise exception 'Customer not found — nothing was saved'; end if;

  -- 창고(반품을 받은 창고 · ⬜4) — 지정 → 원 판매 창고 → 손님 기본 창고 → 거부
  v_wh := coalesce(nullif(p->>'warehouse_id', '')::uuid, v_wh);
  if v_wh is null then raise exception 'warehouse_id is required — where were the goods returned to? — nothing was saved'; end if;
  select * into v_w from public.ref_warehouse w where w.id = v_wh;
  if not found then raise exception 'Warehouse not found — nothing was saved'; end if;
  if not v_w.is_active then raise exception 'Warehouse % is inactive — nothing was saved', v_w.name; end if;

  -- 줄 — 첫 바퀴: product · freight · other(수수료는 둘째 바퀴 · 제품 합이 먼저 필요하다) · [qbo-sync-2c1 · 판정 966] tax 줄은 받지 않는다(세금이 틀렸으면 전액 크레딧으로 상쇄 → 바른 새 인보이스 · CHECK · 옛 행은 그대로)
  for x in select t from jsonb_array_elements(p->'lines') t loop
    v_kind := nullif(trim(x->>'kind'), '');
    if v_kind = 'surcharge' then raise exception 'Surcharge lines are added automatically from the returned product lines — do not send them — nothing was saved'; end if;   -- surcharge-2b(D-3 · 자동만)
    if v_kind = 'freight_discount' then raise exception 'Freight discount lines are added automatically from the returned freight line — do not send them — nothing was saved'; end if;   -- fr-3 판정 355(자동만)
    if v_kind = 'tax' then raise exception 'A tax-only credit note is not allowed — credit the invoice in full and issue a corrected invoice instead — nothing was saved'; end if;   -- qbo-sync-2c1 판정 966
    if v_kind is null or v_kind not in ('product','freight','other','restocking_fee','price_adjustment') then raise exception 'Line kind must be one of product, freight, other, restocking_fee, price_adjustment — nothing was saved'; end if;
    if v_kind = 'restocking_fee' then v_fee_lines := v_fee_lines + 1; continue; end if;
    if v_kind = 'price_adjustment' then v_adj_n := v_adj_n + 1; continue; end if;                       -- crn-2: 가격 조정은 둘째 바퀴(반품이 먼저 낮은 층을 가져간다 · §2-2)
    v_il := null;  v_io := null;  v_pr := null;  v_bin := null;  v_acct := null;  v_fd := null;  v_fd_line := 0;                                                           -- fr-3
    v_qty := null;  v_unit := null;  v_rate := null;  v_bin_id := null;  v_bin_name := null;  v_nr := null;  v_nr_note := null;  v_product_id := null;  v_so_line_id := null;  v_sku := null;  v_il_id := null;  v_desc := null;  v_est := null;
    v_bgb := null;                                                                                                                                                         -- bgr-1d
    v_take := null;  v_od_base := null;                                                                                                                                                -- crn-2
    v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;

    if v_kind = 'product' then
      v_qty := nullif(x->>'qty_returned', '')::numeric;
      if v_qty is null or v_qty <= 0 then raise exception 'A product line needs qty_returned > 0 — nothing was saved'; end if;
      if v_ref then
        v_sku := nullif(trim(x->>'sku'), '');
        if v_sku is null then raise exception 'A reference credit product line needs sku — nothing was saved'; end if;
        select * into v_pr from public.product pr where pr.sku = v_sku;
        if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
        v_unit := nullif(x->>'unit_price', '')::numeric;
        if v_unit is null or v_unit < 0 then raise exception 'A reference credit product line needs unit_price (the price on the paper invoice) — nothing was saved'; end if;
        v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_pr.name);
        if v_hist_found then                                                                                                  -- hcr-1 판정 774 · 778 · 기술 3: 이력 줄(778 반영 단가 · 남은 수량)과 견준다 — 막지 않는다 · 경고만
          v_hu := (v_hl->(v_pr.id::text)->>'unit')::numeric;  v_hrem := (v_hl->(v_pr.id::text)->>'rem')::numeric;
          if v_hu is null then
            v_hist_manual := true;  v_wt := 'not_on_invoice:' || v_pr.sku;  if not (v_wt = any (v_warn)) then v_warn := array_append(v_warn, v_wt); end if;
          else
            if abs(v_unit - v_hu) >= 0.005 then v_hist_manual := true; end if;                                                                           -- 한 푼(0.005) 이상 다르면 「손으로 넣은 단가」
            select coalesce(sum(nullif(t->>'qty_returned', '')::numeric), 0) into v_hask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(trim(t->>'sku'), '') = v_sku;
            if v_hask > v_hrem then v_wt := format('qty_over_sold:%s:%s/%s', v_pr.sku, trim_scale(v_hask), trim_scale(v_hrem));  if not (v_wt = any (v_warn)) then v_warn := array_append(v_warn, v_wt); end if; end if;
          end if;
        end if;
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then
          if exists (select 1 from public.so_line cl2 join public.so_invoice_order io2 on io2.so_id = cl2.so_id                                  -- asm-2b2(판정 245): 구성품은 인보이스 줄이 없다 — 하나만 돌려받는 길은 「other」 금액 줄
                      where io2.invoice_id = v_inv.id and cl2.combo_line_id is not null and (cl2.id = nullif(x->>'so_line_id', '')::uuid or cl2.sku = nullif(trim(x->>'sku'), ''))) then
            raise exception 'Line % is a component of a combo on invoice % — a combo is credited whole (credit the combo line); for one component use an other line (amount only, no stock) — nothing was saved', coalesce(nullif(trim(x->>'sku'), ''), x->>'so_line_id'), v_inv.invoice_number;
          end if;
          raise exception 'An IMS product line needs so_invoice_line_id (the invoice line being returned) — nothing was saved';
        end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
        if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        v_already := (public.so_credit_line_state(v_il.id)->>'qty_returned')::numeric;                   -- crn-2: 「이미 반품」 식은 so_credit_line_state 한 곳(§22-f ⬜ 복사 식 닫힘 · 값은 같다)
        select coalesce(sum((t->>'qty_returned')::numeric), 0) into v_ask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(t->>'so_invoice_line_id', '')::uuid = v_il.id;
        if v_already + v_ask > v_il.qty then
          raise exception 'Invoice % line % (%): % of % already credited and % asked now — only % can still be returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, v_already, v_il.qty, v_ask, v_il.qty - v_already;
        end if;
        v_unit := v_il.unit_price;  v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        -- crn-2 판정 611: 반품은 조정된 몫(낮은 층)부터 — 이 줄의 층을 가져와(이 호출의 앞선 줄이 깎은 것 포함) 낮은 값부터 v_qty 만큼 뗀다
        if not (v_tiers ? v_il.id::text) then v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_line_state(v_il.id)->'tiers'); end if;
        v_take := public.so_credit_tiers_take(v_tiers->(v_il.id::text), v_qty, null);
        v_tiers := v_tiers || jsonb_build_object(v_il.id::text, v_take->'tiers');
        select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
        select sl.bgrade_bin_id into v_bgb from public.so_line sl where sl.id = v_il.so_line_id;                                  -- bgr-1d 판정 640
        if v_bgb is not null then v_warn := array_append(v_warn, 'final_sale:' || v_sku); end if;                                -- bgr-1d: 경고만(노 리턴 · 발행은 막지 않는다)
        select * into v_pr from public.product pr where pr.id = v_product_id;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      if v_take is null then
        v_amount := round(v_qty * coalesce(v_unit, 0), 2);  v_od_base := v_amount;
      else                                                                                                      -- crn-2 판정 611: 낸 단가 층은 인보이스 단가(오더 할인 거울이 따로 뺀다) · 조정 층은 새 단가 그대로(거울 기준에서 뺀다)
        select coalesce(sum(case when (pt->>'paid')::boolean then round((pt->>'qty')::numeric * coalesce(v_unit, 0), 2) else round((pt->>'qty')::numeric * (pt->>'unit_price')::numeric, 2) end), 0),
               coalesce(sum(case when (pt->>'paid')::boolean then round((pt->>'qty')::numeric * coalesce(v_unit, 0), 2) else 0 end), 0)
          into v_amount, v_od_base from jsonb_array_elements(v_take->'parts') pt;
        if exists (select 1 from jsonb_array_elements(v_take->'parts') pt where not (pt->>'paid')::boolean) then
          v_unit := round(v_amount / v_qty, 6);
          v_desc := v_desc || ' (' || (select string_agg(trim_scale((pt->>'qty')::numeric) || ' × ' || trim_scale(case when (pt->>'paid')::boolean then coalesce(v_il.unit_price, 0) else (pt->>'unit_price')::numeric end), ' + ' order by ord) from jsonb_array_elements(v_take->'parts') with ordinality t(pt, ord)) || ')';
        end if;
      end if;
      v_tax := public.so_tax_amount(v_amount, v_rate);
      v_product_amt := v_product_amt + v_amount;  v_rates := array_append(v_rates, v_rate);
      -- 돌아오나(판정 1) — not_restocked_reason 이 있으면 안 돌아옴 · 아니면 칸(지정 → ims_last_bin → 거부 · '' 불허 · ⬜4)
      v_combo := case when v_ref then null else nullif(v_il.combo_components, 'null'::jsonb) end;
      v_nr := nullif(trim(x->>'not_restocked_reason'), '');
      if v_combo is not null then                                                                                 -- asm-2b2: 콤보 줄 자체는 칸 · 사유가 없다 — 줄에 적은 칸 · 사유는 구성품 전부의 기본값(components[] 가 덮는다)
        v_def_nr := v_nr;  v_def_note := nullif(trim(x->>'not_restocked_note'), '');  v_def_bin := nullif(trim(x->>'restock_bin'), '');  v_nr := null;
        if v_def_nr is not null and v_def_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        if v_def_nr = 'other' and v_def_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        if exists (select 1 from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where not exists (select 1 from jsonb_array_elements(v_combo) cy where cy->>'sku' = nullif(trim(cx->>'sku'), ''))) then
          raise exception 'components[] of combo % names a sku that is not part of that combo on invoice % — nothing was saved', v_sku, v_inv.invoice_number;
        end if;
      elsif v_nr is not null then
        if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        v_nr_note := nullif(trim(x->>'not_restocked_note'), '');
        if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
      else
        v_bin_name := nullif(trim(x->>'restock_bin'), '');
        if v_bin_name is null and v_bgb is not null then                                                                         -- bgr-1d 판정 649: B급 줄의 반품 = 팔려 나간 그 B급 칸
          select rb.name into v_bin_name from public.ref_bin rb where rb.id = v_bgb and rb.is_bgrade and rb.is_active and rb.warehouse_id = v_w.id;
          if v_bin_name is null then v_warn := array_append(v_warn, 'bgrade_bin_gone:' || v_sku); end if;                     -- 꺼졌거나 · 비활성 · 다른 창고 → 정상 기본(ims_last_bin)
        end if;
        if v_bin_name is null then
          v_bin_name := public.ims_last_bin(array[coalesce(v_pr.parent_product_id, v_pr.id)], v_w.id) -> coalesce(v_pr.parent_product_id, v_pr.id)::text ->> 'bin';
          if v_bin_name is null then raise exception 'No bin known for % in % — pick a restock bin (or mark the line not restocked) — nothing was saved', v_sku, v_w.name; end if;
        end if;
        select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
        if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
        if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
        v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
        -- 원가 복원 예상(미리 보기 · 원 판매의 소비 기록 평균 × EA · 없으면 null)
        select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0), sum(cs.qty) into v_est, v_est_qty
          from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
         where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_pr.parent_product_id), v_pr.sku)
           and cs.doc_number = case when v_ref then null else (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id)) end;   -- crn-1 판정 602: 참조 크레딧은 되짚지 않는다(예상 null · 실제 원가는 inv_layer_post_credit ② 가중평균부터)
      end if;
    elsif v_kind = 'freight' then
      if v_ref then
        v_amount := nullif(x->>'amount', '')::numeric;  v_rate := v_rule.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Freight');
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_99_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then raise exception 'An IMS freight line needs so_invoice_line_id (the charge line) — nothing was saved'; end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'charge';
        if v_il.id is null then raise exception 'Invoice line % is not a charge line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        v_amount := coalesce(nullif(x->>'amount', '')::numeric, v_il.amount);  v_rate := v_io.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select coalesce(sum(cl.amount), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        if v_already + v_amount > v_il.amount then raise exception 'Invoice % charge % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_already, v_il.amount, v_il.amount - v_already; end if;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      if v_amount is null or v_amount < 0 then raise exception 'A freight line needs amount ≥ 0 — nothing was saved'; end if;
      v_tax := public.so_tax_amount(v_amount, v_rate);
      if not v_ref then                                                                                             -- fr-3 판정 355: 그 운임 줄에 할인 줄(charge_discount · 같은 so_charge_id)이 있으면 같은 비율로 되돌린다
        select * into v_fd from public.so_invoice_line d where d.invoice_id = v_inv.id and d.kind = 'charge_discount' and d.so_charge_id = v_il.so_charge_id;
        if v_fd.id is not null then
          v_fd_inv := -v_fd.amount;                                                                                    -- 인보이스 할인(양수)
          select coalesce(-sum(cl.amount), 0) into v_fd_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_fd.id and c.status = 'issued';   -- 이미 돌려준 할인(양수)
          v_fd_line := case when v_already + v_amount = v_il.amount then v_fd_inv - v_fd_already                             -- 끝수 규칙: 정가를 다 돌려주는 마지막 줄은 남은 할인 전부(합 = 인보이스 할인 · 정확히)
                            else least(round(v_amount * v_fd_inv / v_il.amount, 2), v_fd_inv - v_fd_already) end;                 -- 그 밖은 round(x × 비율, 2) · 남은 할인을 넘지 않는다
          if (v_already - v_fd_already) + (v_amount - v_fd_line) > v_il.amount - v_fd_inv or v_fd_line > v_amount then         -- 순액 한도: 돌려준 순액 합 ≤ 손님이 낸 순액 · 남은 할인이 이번 운임보다 크면(앞 크레딧이 할인 없이 정가를 가져간 옛 모양) 음수 순액이 되므로 거부(정가 한도 검사는 위에 그대로)
            raise exception 'Invoice % charge % : the customer paid % net (% less % discount) — % net already credited and % asked now — only % left — nothing was saved',
              v_inv.invoice_number, v_il.line_no, v_il.amount - v_fd_inv, v_il.amount, v_fd_inv, v_already - v_fd_already, v_amount - v_fd_line, (v_il.amount - v_fd_inv) - (v_already - v_fd_already);
          end if;
        end if;
      end if;
    else   -- other
      v_amount := nullif(x->>'amount', '')::numeric;  v_desc := nullif(trim(x->>'description'), '');
      if v_amount is null or v_amount < 0 then raise exception 'An other line needs amount ≥ 0 — nothing was saved'; end if;
      if v_desc is null then raise exception 'An other line needs a description — nothing was saved'; end if;
      if v_acct.id is null then raise exception 'An other line needs account_id (no default) — nothing was saved'; end if;
      v_rate := case when v_ref then v_rule.rate_pct else v_first_io.rate_pct end;  v_tax := public.so_tax_amount(v_amount, v_rate);
    end if;
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);  v_parent_ln := v_ln;
    if v_kind = 'product' then v_odb := v_odb || jsonb_build_object(v_ln::text, v_od_base); v_ret_n := v_ret_n + 1; end if;                                      -- crn-2: 거울 기준(조정된 몫 제외)
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', v_kind, 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku, 'description', v_desc,
                                             'qty_returned', v_qty, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                             'unit_price', v_unit, 'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code,
                                             'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_qty * coalesce(v_pr.pack_factor, 1), 6) end,
                                             'combo_components', case when v_kind = 'product' then v_combo end);                                           -- asm-2b2: 콤보 크레딧 줄에 includes(인보이스 줄 사본)
    if v_kind = 'freight' and not v_ref and v_fd.id is not null and v_fd_line > 0 then                                   -- fr-3 판정 355 · 352 · 354 · 358: 운임 줄 바로 뒤 할인 되돌림 줄 · 음수 · 세금 따로(줄마다) · 계정 = 인보이스 할인 줄 것
      v_fd_tax := public.so_tax_amount(-v_fd_line, v_io.rate_pct);
      v_ln := v_ln + 1;  v_fd_amt := v_fd_amt - v_fd_line;  v_tax_amt := v_tax_amt + coalesce(v_fd_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'freight_discount', 'so_invoice_line_id', v_fd.id, 'description', v_fd.description,
                                               'amount', -v_fd_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_fd_tax, 0), 'account_id', v_fd.account_id, 'account_code', v_fd.account_code);
    end if;
    if v_kind = 'product' and not v_ref then                                                                  -- surcharge-2b(묶음 7): 그 상품의 인보이스 surcharge 줄이 있으면 크레딧 surcharge 줄을 자동으로 · 개당은 인보이스 줄의 것(문서는 문서에서) · 세금은 그 줄 세율로 따로 · 계정 복사 · 물건값(v_lines_amt) · 리스탁킹 피 바탕(v_product_amt) 밖
      select * into v_sc from public.so_invoice_line il where il.invoice_id = v_inv.id and il.kind = 'surcharge' and il.so_line_id = v_il.so_line_id;
      if v_sc.id is not null then
        v_sc_line := public.so_line_surcharge_total(v_sc.unit_price, v_qty);
        select coalesce(sum(cl.amount), 0) into v_sc_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_sc.id and c.status = 'issued';
        if v_sc_already + v_sc_line > v_sc.amount then raise exception 'Invoice % surcharge of line % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_sc_already, v_sc.amount, v_sc.amount - v_sc_already; end if;
        v_sc_tax := public.so_tax_amount(v_sc_line, v_io.rate_pct);
        v_ln := v_ln + 1;  v_sc_amt := v_sc_amt + v_sc_line;  v_tax_amt := v_tax_amt + coalesce(v_sc_tax, 0);
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'surcharge', 'so_invoice_line_id', v_sc.id, 'so_line_id', v_sc.so_line_id, 'product_id', v_product_id, 'sku', v_sc.sku, 'description', v_sc.description,
                                                 'qty_returned', v_qty, 'unit_price', v_sc.unit_price, 'amount', v_sc_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_sc_tax, 0), 'account_id', v_sc.account_id, 'account_code', v_sc.account_code);
      end if;
    end if;
    if v_kind = 'product' and v_combo is not null then                                                             -- asm-2b2(묶음 7 · 판정 245): 구성품 크레딧 줄 — 콤보 n 개 ⇒ 구성품마다 n × combo_qty 가 재고로(제 칸 · 또는 안 돌아온 사유) · 금액 0 · 원장(credit_in)은 이 줄들만 · 원가 갈래 ① 은 구성품 SKU 의 소비 기록으로
      for cj in select c2.v from jsonb_array_elements(v_combo) with ordinality c2(v, ord) order by c2.ord loop
        select * into v_cpr from public.product pr where pr.id = nullif(cj->>'product_id', '')::uuid;
        if v_cpr.id is null then select * into v_cpr from public.product pr where pr.sku = cj->>'sku'; end if;
        if v_cpr.id is null then raise exception 'Component % of combo % is not a product any more — nothing was saved', cj->>'sku', v_sku; end if;
        select cx into v_cov from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where nullif(trim(cx->>'sku'), '') = cj->>'sku' limit 1;
        v_cq := v_qty * (cj->>'qty_per_combo')::numeric;
        v_bin := null;  v_bin_id := null;  v_bin_name := null;  v_est := null;  v_nr_note := null;
        v_nr := coalesce(nullif(trim(v_cov->>'not_restocked_reason'), ''), v_def_nr);
        if v_nr is not null then
          if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
          v_nr_note := coalesce(nullif(trim(v_cov->>'not_restocked_note'), ''), v_def_note);
          if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        else
          v_bin_name := coalesce(nullif(trim(v_cov->>'restock_bin'), ''), v_def_bin);
          if v_bin_name is null then
            v_bin_name := public.ims_last_bin(array[coalesce(v_cpr.parent_product_id, v_cpr.id)], v_w.id) -> coalesce(v_cpr.parent_product_id, v_cpr.id)::text ->> 'bin';
            if v_bin_name is null then raise exception 'No bin known for % (component of combo %) in % — pick a restock bin for it in components[] (or mark it not restocked) — nothing was saved', v_cpr.sku, v_sku, v_w.name; end if;
          end if;
          select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
          if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
          if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
          v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
          select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0) into v_est
            from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
           where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_cpr.parent_product_id), v_cpr.sku)
             and cs.doc_number = (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id));
        end if;
        v_ln := v_ln + 1;
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'product', 'so_invoice_line_id', null, 'so_line_id', nullif(cj->>'so_line_id', '')::uuid, 'product_id', v_cpr.id, 'sku', v_cpr.sku, 'description', coalesce(cj->>'description', v_cpr.name),
                                                 'qty_returned', v_cq, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                                 'unit_price', 0, 'amount', 0, 'rate_pct', v_rate, 'tax_amount', 0, 'account_id', v_acct.id, 'account_code', v_acct.code,
                                                 'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_cq * coalesce(v_cpr.pack_factor, 1), 6) end,
                                                 'combo_parent_line_no', v_parent_ln, 'combo_qty', (cj->>'qty_per_combo')::numeric, 'combo_sku', v_sku);
      end loop;
    end if;
  end loop;

  -- ═══ crn-2 판정 603 · 611 · 613 · 614: 가격 조정 줄(둘째 바퀴) — 인보이스 줄: 층(낸 단가 = 오더 할인 뒤 · 앞선 조정이 있으면 그 단가)에서 새 단가보다 비싼 가장 낮은 층 하나 · 수량은 그 층 안에서만(넘치면 나눠 보내라) ·
  --     참조 크레딧: 낸 단가 · 새 단가 · 수량을 손으로 · 금액 = (낸 − 새) × 수량 · 세율 = 그 줄(또는 규칙) · 계정 = 그 인보이스 줄(614 · 참조는 _98_) · 재고 0 · 거울 · surcharge · 운임 할인 · 피 기준에 안 들어간다 ═══
  for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'price_adjustment' loop
    v_il := null;  v_io := null;  v_pr := null;  v_acct := null;  v_tier := null;  v_il_id := null;  v_so_line_id := null;  v_product_id := null;  v_sku := null;  v_desc := null;
    v_qty := nullif(x->>'qty', '')::numeric;  v_after := nullif(x->>'new_unit_price', '')::numeric;  v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_qty is null or v_qty <= 0 then raise exception 'A price adjustment line needs qty > 0 — nothing was saved'; end if;
    if v_after is null or v_after <= 0 then raise exception 'A price adjustment line needs new_unit_price above 0 — to write the goods off entirely use a product line marked not returned, or an other line — nothing was saved'; end if;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;
    if v_ref then
      v_sku := nullif(trim(x->>'sku'), '');
      if v_sku is null then raise exception 'A reference credit price adjustment line needs sku — nothing was saved'; end if;
      select * into v_pr from public.product pr where pr.sku = v_sku;
      if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
      v_before := nullif(x->>'paid_unit_price', '')::numeric;
      if v_before is null or v_before < 0 then raise exception 'A reference credit price adjustment line needs paid_unit_price (the price on the paper invoice) — nothing was saved'; end if;
      if v_after >= v_before then raise exception 'New unit price % is not below the paid unit price % — nothing was saved', trim_scale(v_after), trim_scale(v_before); end if;
      v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := v_pr.name;
      if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
    else
      v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
      if v_il_id is null then raise exception 'A price adjustment line needs so_invoice_line_id (the invoice line being adjusted) — nothing was saved'; end if;
      select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
      if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
      if v_il.combo_components is not null then raise exception 'Invoice % line % (%) is a combo — a price adjustment on a combo is not supported; use an other line — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku; end if;
      if exists (select 1 from public.so_line sl where sl.id = v_il.so_line_id and sl.bgrade_bin_id is not null) then v_warn := array_append(v_warn, 'final_sale:' || v_il.sku); end if;   -- bgr-1d: 가격 조정도 같은 경고
      select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
      if not (v_tiers ? v_il.id::text) then v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_line_state(v_il.id)->'tiers'); end if;
      if not exists (select 1 from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0) then
        raise exception 'Invoice % line % (%): nothing left to adjust — all % were returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale(v_il.qty);
      end if;
      select t into v_tier from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0 and (t->>'unit_price')::numeric > v_after order by (t->>'unit_price')::numeric limit 1;
      if v_tier is null then
        raise exception 'Invoice % line % (%): new unit price % is not below the current unit price % — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale(v_after),
          trim_scale((select min((t->>'unit_price')::numeric) from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0));
      end if;
      v_before := (v_tier->>'unit_price')::numeric;
      if v_qty > (v_tier->>'qty')::numeric then
        raise exception 'Invoice % line % (%): only % can be adjusted at % — split the adjustment (% at %%s%, the rest at the next price level) — nothing was saved',
          v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale((v_tier->>'qty')::numeric), trim_scale(v_before), trim_scale((v_tier->>'qty')::numeric), trim_scale(v_before);
      end if;
      v_take := public.so_credit_tiers_take(v_tiers->(v_il.id::text), v_qty, v_after);
      v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_tiers_add(v_take->'tiers', v_qty, v_after));
      v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := v_il.description;
      select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
      if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;   -- 판정 614: 그 판매 줄의 매출 계정
    end if;
    v_amount := round((v_before - v_after) * v_qty, 2);  v_tax := public.so_tax_amount(v_amount, v_rate);
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'price_adjustment', 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku,
                                             'description', format('Price adjustment %s → %s', trim_scale(v_before), trim_scale(v_after)) || coalesce(' — ' || v_desc, ''),
                                             'qty_adjusted', v_qty, 'unit_price_before', v_before, 'unit_price_after', v_after, 'unit_price', v_before - v_after,
                                             'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code);
  end loop;
  if v_adj_n > 0 and v_ret_n = 0 and v_reason <> 'price_adjustment' then v_warn := array_append(v_warn, 'reason_not_price_adjustment'); end if;          -- crn-2 §2-4: 경고만
  if v_reason = 'price_adjustment' and v_ret_n > 0 then v_warn := array_append(v_warn, 'reason_price_adjustment_with_returns'); end if;

  -- crn-1 판정 602 · crn-0 §2-5: 참조 크레딧 경고 — 늘 manual_unit_price(인보이스 없이 넣은 단가 · 화면이 크게) · 같은 손님 · 같은 참조 번호(대소문자 · 앞뒤 공백 무시) · 같은 SKU 의 앞선 발행 크레딧이 있으면 reference_seen:<CR 번호들>(막지 않는다)
  if v_ref then
    if not v_hist_found or v_hist_manual then                                                                                 -- hcr-1 기술 3: 이력이 있으면 단가가 이력(778 반영)과 다를 때 · 인보이스에 없는 제품일 때만
    v_warn := array_append(v_warn, 'manual_unit_price');
    end if;
    if not v_hist_found then v_warn := array_append(v_warn, 'reference_not_in_history'); end if;                                              -- hcr-1: 이력에 없는 번호 — 수량 · 단가를 견주지 못했다
    select string_agg(distinct c2.credit_number, ', ') into v_seen
      from public.so_credit c2 join public.so_credit_line l2 on l2.credit_id = c2.id
     where c2.customer_id = v_cust and c2.status = 'issued' and lower(trim(c2.ref_invoice_number)) = lower(v_ref_inv)
       and l2.kind = 'product' and l2.sku in (select le->>'sku' from jsonb_array_elements(v_lines) le where le->>'kind' = 'product');
    if v_seen is not null then v_warn := array_append(v_warn, 'reference_seen:' || v_seen); end if;
  end if;

  -- dsc-3b 판정 325 · 316: 인보이스 거울 — 인보이스-오더마다 오더 할인 % 가 있으면 그 오더의 제품 환불액에 음수 줄 하나(세금 따로 · 계정 = 그 인보이스의 order_discount 줄) · surcharge 는 기준 밖(인보이스와 같다) · Cin7 크레딧은 해당 없음
  if not v_ref then
    for v_od in
      select io.id as io_id, io.so_number, io.order_discount_pct as pct, io.rate_pct, sum(coalesce((v_odb->>(le->>'line_no'))::numeric, (le->>'amount')::numeric)) as amt   -- crn-2 판정 611 · 613: 조정된 몫은 거울 기준에서 뺀다(그 몫은 새 단가 그대로)
      from jsonb_array_elements(v_lines) le join public.so_invoice_line il on il.id = nullif(le->>'so_invoice_line_id', '')::uuid join public.so_invoice_order io on io.id = il.invoice_order_id join public.so_line sl on sl.id = il.so_line_id   -- od-1
      where le->>'kind' = 'product' and coalesce(io.order_discount_pct, 0) > 0 and not public.so_line_manual(sl)   -- od-1 판정 542 · 544: 손으로 정한 줄은 오더 할인을 받지 않았으니 되돌릴 몫도 없다
      group by io.id, io.so_number, io.order_discount_pct, io.rate_pct order by io.so_number
    loop
      v_amount := -round(v_od.amt * v_od.pct / 100, 2);  v_tax := public.so_tax_amount(v_amount, v_od.rate_pct);
      select * into v_od_il from public.so_invoice_line il where il.invoice_order_id = v_od.io_id and il.kind = 'order_discount' limit 1;
      v_ln := v_ln + 1;  v_od_amt := v_od_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'order_discount', 'so_invoice_line_id', v_od_il.id, 'description', format('Order discount %s%% (%s)', v_od.pct, v_od.so_number),
                                               'amount', v_amount, 'rate_pct', v_od.rate_pct, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_od_il.account_id, 'account_code', v_od_il.account_code);
    end loop;
  end if;

  -- 둘째 바퀴 — Restocking fee(판정 4·5·7 · 0-8): 기본 −round(Σ제품 × pct/100, 2) · 계정 = 지정 → 설정 → 거부 · 세율 = 첫 제품 줄(섞이면 경고) · 세금도 음수 · dsc-3b 판정 325: 기준 = 제품 환불액 − 오더 할인 몫(손님이 실제 낸 값)
  v_first_rate := case when v_ref then v_rule.rate_pct else v_rates[1] end;
  if v_fee_lines > 0 then
    if v_fee_lines > 1 then raise exception 'Only one restocking_fee line per credit note — nothing was saved'; end if;
    if (select count(distinct r) from unnest(v_rates) r) > 1 then v_warn := array_append(v_warn, 'fee_rate_mixed'); end if;
    for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'restocking_fee' loop
      v_acct := null;  v_acct_id := nullif(x->>'account_id', '')::uuid;
      if v_acct_id is not null then select * into v_acct from public.ref_account a where a.id = v_acct_id;
      elsif v_fee_acct_code is not null then select * into v_acct from public.ref_account a where a.code = v_fee_acct_code; end if;
      if v_acct.id is null then raise exception 'A restocking fee line needs account_id — no default account is set (inv_config so_credit_restock_fee_account_code) — nothing was saved'; end if;
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null then v_amount := -round((v_product_amt + v_od_amt) * coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct, 0) / 100, 2); end if;   -- dsc-3b 판정 325: v_od_amt 는 음수
      if v_amount > 0 then raise exception 'A restocking fee reduces the credit — amount must be ≤ 0 (got %) — nothing was saved', v_amount; end if;
      v_tax := public.so_tax_amount(v_amount, v_first_rate);
      v_ln := v_ln + 1;  v_fee_amt := v_fee_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'restocking_fee', 'description', coalesce(nullif(trim(x->>'description'), ''), format('Restocking fee %s%%', coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct))),
                                               'amount', v_amount, 'rate_pct', v_first_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code);
    end loop;
  end if;
  -- 알림(판정 5) — 원 인보이스 발행일 + N일이 지났고 수수료 줄이 없으면 「대상」만 알린다(자동으로 붙이지 않는다)
  if v_origin_on is null then v_warn := array_append(v_warn, 'fee_window_unknown');
  elsif v_fee_days is not null and v_on - v_origin_on > v_fee_days and v_fee_lines = 0 and v_product_amt > 0 then
    v_warn := array_append(v_warn, 'restock_fee_window:' || (v_on - v_origin_on)::text);
    v_fee_sugg := jsonb_build_object('days_since_invoice', v_on - v_origin_on, 'pct', v_fee_pct, 'amount', -round((v_product_amt + v_od_amt) * coalesce(v_fee_pct, 0) / 100, 2), 'account_code', v_fee_acct_code);   -- dsc-3b 판정 325
  end if;
  if v_ln = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  if not p_commit then
    return jsonb_build_object('committed', false, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code, 'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                              'origin', case when v_ref then jsonb_build_object('ref_invoice_number', v_ref_inv, 'ref_order_number', v_ref_ord, 'ref_invoice_date', v_ref_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src)
                                             else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                              'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_lines_amt, 'order_discount_amount', v_od_amt, 'freight_discount_amount', v_fd_amt, 'fee_amount', v_fee_amt, 'surcharge_amount', v_sc_amt, 'tax_amount', v_tax_amt, 'total', v_lines_amt + v_od_amt + v_fd_amt + v_fee_amt + v_sc_amt + v_tax_amt, 'restock_lines', v_restock_n),
                              'fee_suggested', v_fee_sugg, 'ledger', null, 'warnings', to_jsonb(v_warn));
  end if;

  insert into public.so_credit (customer_id, currency_id, currency_code, invoice_id, ref_invoice_number, ref_order_number, ref_invoice_date, origin_invoice_on, reason, note,
                                warehouse_id, warehouse_name, tax_rule_id, tax_rule, rate_pct, issued_on, issued_by, lines_amount, order_discount_amount, freight_discount_amount, fee_amount, surcharge_amount, tax_amount, total, created_by, updated_by)   -- fr-3
  values (v_cust, v_cur.id, v_cur.code, v_inv.id, v_ref_inv, v_ref_ord, v_ref_date, v_origin_on, v_reason, nullif(trim(p->>'note'), ''),
          v_w.id, v_w.name, v_rule.id, v_rule.name, v_rule.rate_pct, v_on, v_staff, v_lines_amt, v_od_amt, v_fd_amt, v_fee_amt, v_sc_amt, v_tax_amt, v_lines_amt + v_od_amt + v_fd_amt + v_fee_amt + v_sc_amt + v_tax_amt, v_staff, v_staff)   -- fr-3
  returning * into v_cr;
  for e in select t from jsonb_array_elements(v_lines) t loop
    insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, so_line_id, product_id, sku, description, qty_returned, restock_bin_id, restock_bin, not_restocked_reason, not_restocked_note,
                                       unit_price, amount, rate_pct, tax_amount, account_id, account_code, updated_by, combo_credit_line_id, combo_qty, combo_components,
                                       qty_adjusted, unit_price_before, unit_price_after)                                                                                                -- crn-2
    values (v_cr.id, (e->>'line_no')::int, e->>'kind', nullif(e->>'so_invoice_line_id', '')::uuid, nullif(e->>'so_line_id', '')::uuid, nullif(e->>'product_id', '')::uuid, e->>'sku', e->>'description',
            nullif(e->>'qty_returned', '')::numeric, nullif(e->>'restock_bin_id', '')::uuid, e->>'restock_bin', e->>'not_restocked_reason', e->>'not_restocked_note',
            nullif(e->>'unit_price', '')::numeric, (e->>'amount')::numeric, nullif(e->>'rate_pct', '')::numeric, (e->>'tax_amount')::numeric, nullif(e->>'account_id', '')::uuid, e->>'account_code', v_staff,
            (v_idmap->>(e->>'combo_parent_line_no'))::uuid, nullif(e->>'combo_qty', '')::numeric, nullif(e->'combo_components', 'null'::jsonb),                   -- asm-2b2: 구성품 줄은 앞서 넣은 콤보 줄(line_no → id)에 매단다 · 콤보 줄은 includes 를 든다
            nullif(e->>'qty_adjusted', '')::numeric, nullif(e->>'unit_price_before', '')::numeric, nullif(e->>'unit_price_after', '')::numeric)                                              -- crn-2
    returning id into v_il_id;
    v_idmap := v_idmap || jsonb_build_object((e->>'line_no'), v_il_id);
  end loop;
  if v_restock_n > 0 then
    v_ledger := public.inv_post_credit(v_cr.id, v_on);
    v_warn := v_warn || coalesce((select array_agg(t.w) from jsonb_array_elements_text(coalesce(v_ledger->'warnings', '[]'::jsonb)) as t(w)), '{}');
  end if;

  update public.so_credit c set store_customer_id = v_store, warnings = to_jsonb(v_warn) where c.id = v_cr.id;                               -- hcr-1 판정 779 · 기술 3: 매장 · 경고를 기록에(원장 경고까지 합친 뒤 · 상태는 안 건드린다)
  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', v_cr.status, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code,
                            'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                            'origin', case when v_ref then jsonb_build_object('ref_invoice_number', v_ref_inv, 'ref_order_number', v_ref_ord, 'ref_invoice_date', v_ref_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src)
                                           else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'order_discount_amount', v_cr.order_discount_amount, 'freight_discount_amount', v_cr.freight_discount_amount, 'fee_amount', v_cr.fee_amount, 'surcharge_amount', v_cr.surcharge_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ C) 속 함수 — 크레딧 몸 · void 몸 ═══
create function public.qbo_credit_body(p_credit_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_realm text := public.qbo_realm_of();
  v_c public.so_credit%rowtype; v_inv public.so_invoice%rowtype; v_o public.so_invoice_order%rowtype; v_store public.customer%rowtype; v_ij public.qbo_job%rowtype;
  v_il public.so_invoice_line%rowtype; v_ch public.so_charge%rowtype; v_sa public.customer_address%rowtype;
  v_cust_ref text; v_tax_ref text; v_rate_ref text; v_item text; v_cur text; v_rule uuid; v_rule_name text; v_refs text; v_note text; v_email text; v_bill jsonb; v_ship jsonb; v_detail jsonb;
  v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_lines jsonb := '[]'::jsonb; v_tax_lines jsonb := '[]'::jsonb; v_tx jsonb := '[]'::jsonb; v_need jsonb; v_wait uuid; v_wait_inv text;
  v_desc text; v_qty numeric; v_up numeric; v_n int := 0;
  v_l record; v_t record;
begin
  select * into v_c from public.so_credit c where c.id = p_credit_id;
  if v_c.id is null then raise exception 'No IMS credit note % — nothing was sent', p_credit_id; end if;
  if v_c.status <> 'issued' then raise exception 'Credit note % is % — only an issued credit note is sent to QuickBooks — nothing was sent', v_c.credit_number, v_c.status; end if;
  -- 960 — IMS 인보이스를 가리키면 그 인보이스가 QBO 에 들어간 뒤(qbo_txn) · 열린 일감이면 wait_job · 일감 없음 · skipped 는 예외(이견 2a · 2b) · since 전 · 이월 인보이스는 기다리지 않는다(Cin7 이 보냈다)
  if v_c.invoice_id is not null then
    select * into v_inv from public.so_invoice i where i.id = v_c.invoice_id;
    if v_inv.id is null then raise exception 'Credit note % — its invoice is missing — nothing was sent', v_c.credit_number; end if;
    if v_inv.kind <> 'opening' and public.qbo_send_since_ok(v_inv.issued_on)
       and not exists (select 1 from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = v_inv.id::text) then
      select * into v_ij from public.qbo_job j where j.realm_id = v_realm and j.kind = 'invoice' and j.ims_kind = 'invoice' and j.ims_id = v_inv.id::text order by j.created_at desc, j.id desc limit 1;
      if v_ij.id is null then raise exception 'Invoice % has no QuickBooks job — send the invoice first — nothing was sent', v_inv.invoice_number; end if;
      if v_ij.state = 'skipped' then raise exception 'Invoice % was skipped — skip this credit note too, or retry the invoice first — nothing was sent', v_inv.invoice_number; end if;
      if v_ij.state = 'sent' then v_warn := array_append(v_warn, format('invoice %s job is sent but no QuickBooks transaction is on file', v_inv.invoice_number));
      else v_wait := v_ij.id; v_wait_inv := v_inv.invoice_number; end if;
    end if;
    select * into v_o from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;
  end if;
  -- 935 CustomerRef = 매장(store_customer_id · 참조 크레딧에서 매장을 안 고르면 발행이 청구처를 넣는다) · 짝 없으면 needs(손님 일감 · 부모는 open_or_add 가)
  select * into v_store from public.customer c where c.id = coalesce(v_c.store_customer_id, v_c.customer_id);
  if v_store.id is null then raise exception 'Credit note % — the store customer is missing — nothing was sent', v_c.credit_number; end if;
  select l.qbo_id into v_cust_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_store.id::text;
  if v_cust_ref is null then v_needs := v_needs || jsonb_build_object('kind', 'customer', 'ims_id', v_store.id::text, 'name', v_store.name); end if;
  v_cur := coalesce(nullif(btrim(coalesce(v_c.currency_code, '')), ''), (select c.code from public.ref_currency c where c.id = v_c.currency_id));
  if v_cur is null then raise exception 'Credit note % has no currency code — nothing was sent', v_c.credit_number; end if;
  -- 962 주소 = 크레딧 노트 PDF(doc_data_credit)와 같은 규칙 · 946 나라 이름
  if v_inv.id is not null then
    v_bill := jsonb_strip_nulls(jsonb_build_object('Line1', nullif(btrim(coalesce(v_inv.bill_to_name, '')), ''), 'Line2', nullif(btrim(coalesce(v_inv.bill_to_line1, '')), ''), 'Line3', nullif(btrim(coalesce(v_inv.bill_to_line2, '')), ''),
                                                   'City', nullif(btrim(coalesce(v_inv.bill_to_city, '')), ''), 'CountrySubDivisionCode', nullif(btrim(coalesce(v_inv.bill_to_state_province, '')), ''), 'PostalCode', nullif(btrim(coalesce(v_inv.bill_to_postal_code, '')), ''),
                                                   'Country', public.qbo_country_name(v_inv.bill_to_country)));
    v_ship := jsonb_strip_nulls(jsonb_build_object('Line1', nullif(btrim(coalesce(v_o.ship_to_company, '')), ''), 'Line2', nullif(btrim(coalesce(v_o.ship_to_line1, '')), ''), 'Line3', nullif(btrim(coalesce(v_o.ship_to_line2, '')), ''),
                                                   'City', nullif(btrim(coalesce(v_o.ship_to_city, '')), ''), 'CountrySubDivisionCode', nullif(btrim(coalesce(v_o.ship_to_state_province, '')), ''), 'PostalCode', nullif(btrim(coalesce(v_o.ship_to_postal_code, '')), ''),
                                                   'Country', public.qbo_country_name(v_o.ship_to_country)));
  else
    select a.* into v_sa from public.customer_address a where a.customer_id = v_c.customer_id and a.is_active and a.type = 'Billing' and a.is_default_for_type order by a.created_at, a.id limit 1;
    v_bill := jsonb_strip_nulls(jsonb_build_object('Line1', (select nullif(btrim(c.name), '') from public.customer c where c.id = v_c.customer_id), 'Line2', nullif(btrim(coalesce(v_sa.line1, '')), ''), 'Line3', nullif(btrim(coalesce(v_sa.line2, '')), ''),
                                                   'City', nullif(btrim(coalesce(v_sa.city, '')), ''), 'CountrySubDivisionCode', nullif(btrim(coalesce(v_sa.state_province, '')), ''), 'PostalCode', nullif(btrim(coalesce(v_sa.postal_code, '')), ''),
                                                   'Country', public.qbo_country_name(v_sa.country)));
    v_sa := null;
    select a.* into v_sa from public.customer_address a where a.customer_id = v_store.id and a.is_active and a.type = 'Shipping' and a.is_default_for_type order by a.created_at, a.id limit 1;
    v_ship := jsonb_strip_nulls(jsonb_build_object('Line1', nullif(btrim(v_store.name), ''), 'Line2', nullif(btrim(coalesce(v_sa.line1, '')), ''), 'Line3', nullif(btrim(coalesce(v_sa.line2, '')), ''),
                                                   'City', nullif(btrim(coalesce(v_sa.city, '')), ''), 'CountrySubDivisionCode', nullif(btrim(coalesce(v_sa.state_province, '')), ''), 'PostalCode', nullif(btrim(coalesce(v_sa.postal_code, '')), ''),
                                                   'Country', public.qbo_country_name(v_sa.country)));
  end if;
  if v_bill->>'Line2' is null then v_warn := array_append(v_warn, 'no billing address on the credit note'); end if;
  if (v_bill->>'Country') is not null and (v_bill->>'Country') not in ('Canada', 'USA') then v_warn := array_append(v_warn, format('billing country "%s" sent as is', v_bill->>'Country')); end if;
  if v_ship->>'Line2' is null then v_ship := null; v_warn := array_append(v_warn, 'no ship-to address on the credit note'); end if;
  v_email := public.doc_mail_recipient(v_c.customer_id)->>'to';
  if v_email is null then v_warn := array_append(v_warn, 'no email on file for the bill-to customer'); end if;
  -- 939 메모 — 「Credit for invoice <번호> · Customer Reference: <refs>」 · 같은 글 + 매장
  if v_inv.id is not null then
    select string_agg(coalesce(nullif(btrim(s.ref), ''), o.so_number), ', ' order by o.so_number) into v_refs
      from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id and o.cancelled_at is null;
    v_note := 'Credit for invoice ' || v_inv.invoice_number || coalesce(' · Customer Reference: ' || v_refs, '');
  else
    v_note := 'Credit for invoice ' || v_c.ref_invoice_number || coalesce(' · Customer Reference: ' || nullif(btrim(coalesce(v_c.ref_order_number, '')), ''), '');
  end if;
  -- 줄 — so_credit_line 순서 · 콤보 구성품 줄(0 원)은 건너뛴다 · 줄마다 세금 규칙(인보이스 줄 → 그 오더 · 참조 크레딧 → 머리 · 그 밖 → 첫 오더)
  for v_l in select l.* from public.so_credit_line l where l.credit_id = v_c.id and l.combo_credit_line_id is null order by l.line_no loop
    v_il := null; v_ch := null; v_item := null; v_need := null; v_rule := null; v_rule_name := null; v_desc := v_l.description; v_qty := 1; v_up := v_l.amount;
    if v_l.so_invoice_line_id is not null then
      select * into v_il from public.so_invoice_line il where il.id = v_l.so_invoice_line_id;
      select o.tax_rule_id, o.tax_rule into v_rule, v_rule_name from public.so_invoice_order o where o.id = v_il.invoice_order_id;
      if v_il.so_charge_id is not null then select * into v_ch from public.so_charge c where c.id = v_il.so_charge_id; end if;
    elsif v_c.tax_rule_id is not null then v_rule := v_c.tax_rule_id; v_rule_name := v_c.tax_rule;
    elsif v_o.id is not null then v_rule := v_o.tax_rule_id; v_rule_name := v_o.tax_rule;
    end if;
    if v_rule is null then raise exception 'Credit note % line % has no tax rule to send — nothing was sent', v_c.credit_number, v_l.line_no; end if;
    select l.qbo_id into v_tax_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = v_rule::text;
    if v_tax_ref is null then raise exception 'Tax rule "%" has no QuickBooks tax code — link it under Settings → QuickBooks matching — nothing was sent', v_rule_name; end if;
    if v_l.kind in ('product', 'price_adjustment') then
      if v_l.product_id is null then raise exception 'Credit note % line % has no product — nothing was sent', v_c.credit_number, v_l.line_no; end if;
      select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'product' and l.ims_id = v_l.product_id::text;
      if v_item is null then v_need := jsonb_build_object('kind', 'item', 'ims_id', v_l.product_id::text, 'name', v_l.sku); end if;
      v_qty := case when v_l.kind = 'product' then v_l.qty_returned else v_l.qty_adjusted end; v_up := coalesce(v_l.unit_price, 0);
      if v_l.amount <> round(v_qty * v_up, 2) then v_warn := array_append(v_warn, format('line %s amount %s is not qty × unit price (%s × %s) — QuickBooks may recompute it (942)', v_l.line_no, v_l.amount, trim_scale(v_qty), trim_scale(v_up))); end if;
    elsif v_l.kind = 'surcharge' then
      select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'surcharge';
      if v_item is null then v_need := jsonb_build_object('kind', 'item', 'ims_id', 'surcharge', 'name', 'Tariff Surcharge'); end if;
      v_qty := v_l.qty_returned; v_up := coalesce(v_l.unit_price, 0);
    elsif v_l.kind = 'order_discount' then
      select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'discount';
      if v_item is null then raise exception 'IMS order discount has no QuickBooks item — link "discount" to the Discount item under Settings → QuickBooks matching — nothing was sent'; end if;
    elsif v_l.kind in ('freight', 'freight_discount') then
      if v_ch.id is not null then                                                                                                       -- 인보이스의 비용 줄(운임 · 카드 수수료 · 서비스)을 되돌린다 — 인보이스와 같은 짝(951)
        if v_ch.service_id is not null then
          select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'service' and l.ims_id = v_ch.service_id::text;
          if v_item is null then raise exception 'Service "%" has no QuickBooks item — link it under Settings → QuickBooks matching — nothing was sent', v_ch.name; end if;
        elsif nullif(btrim(coalesce(v_ch.account_code, '')), '') is null then
          raise exception 'Charge "%" has no account — nothing was sent', v_ch.name;
        elsif v_ch.account_code = '_99_' then
          select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'freight';
          if v_item is null then raise exception 'IMS freight has no QuickBooks item — link "freight" to the Freight item under Settings → QuickBooks matching — nothing was sent'; end if;
        else
          select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'acct:' || v_ch.account_code;
          if v_item is null then raise exception 'Charge "%" on account % has no QuickBooks item — link account item "acct:%" to a QuickBooks item under Settings → QuickBooks matching (951) — nothing was sent', v_ch.name, v_ch.account_code, v_ch.account_code; end if;
        end if;
      else                                                                                                                              -- 참조 크레딧의 운임 줄(인보이스 줄 없음) → Freight
        select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'freight';
        if v_item is null then raise exception 'IMS freight has no QuickBooks item — link "freight" to the Freight item under Settings → QuickBooks matching — nothing was sent'; end if;
      end if;
    elsif v_l.kind in ('other', 'restocking_fee') then                                                                                   -- 961: 계정 줄은 사람 짝(acct:<code> · 951 과 같은 열쇠)
      if nullif(btrim(coalesce(v_l.account_code, '')), '') is null then raise exception 'Credit note % line % (%) has no account — nothing was sent', v_c.credit_number, v_l.line_no, v_l.kind; end if;
      if v_l.account_code = '_99_' then
        select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'freight';
        if v_item is null then raise exception 'IMS freight has no QuickBooks item — link "freight" to the Freight item under Settings → QuickBooks matching — nothing was sent'; end if;
      else
        select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'acct:' || v_l.account_code;
        if v_item is null then raise exception 'Credit note line "%" on account % has no QuickBooks item — link account item "acct:%" to a QuickBooks item under Settings → QuickBooks matching (961) — nothing was sent', coalesce(v_l.description, v_l.kind), v_l.account_code, v_l.account_code; end if;
      end if;
    elsif v_l.kind = 'tax' then
      raise exception 'Credit note % line % is a tax line — tax-only credits are not sent to QuickBooks (966); cancel it and credit the invoice in full instead — nothing was sent', v_c.credit_number, v_l.line_no;
    else
      raise exception 'Credit note % line % has unknown kind % — nothing was sent', v_c.credit_number, v_l.line_no, v_l.kind;
    end if;
    if v_need is not null and not (v_needs @> jsonb_build_array(v_need)) then v_needs := v_needs || v_need; end if;
    v_n := v_n + 1;
    v_lines := v_lines || jsonb_build_object('DetailType', 'SalesItemLineDetail', 'LineNum', v_n, 'Amount', v_l.amount, 'Description', left(coalesce(v_desc, ''), 4000),
                 'SalesItemLineDetail', jsonb_strip_nulls(jsonb_build_object('ItemRef', case when v_item is not null then jsonb_build_object('value', v_item) end, 'Qty', trim_scale(v_qty), 'UnitPrice', trim_scale(v_up),
                                                                             'TaxCodeRef', jsonb_build_object('value', v_tax_ref))));
    v_tx := v_tx || jsonb_build_object('rule', v_rule::text, 'name', v_rule_name, 'qbo', v_tax_ref, 'amount', v_l.amount, 'tax', v_l.tax_amount, 'rate', v_l.rate_pct);
  end loop;
  if v_n = 0 then raise exception 'Credit note % has no lines — nothing was sent', v_c.credit_number; end if;
  -- 942 세금 — 규칙마다 TaxLine(TaxRateRef 는 거울 detail · 2b1 과 같은 식)
  for v_t in select x->>'rule' as rule, x->>'name' as name, x->>'qbo' as qbo, sum((x->>'amount')::numeric) as taxable, sum((x->>'tax')::numeric) as tax, max(coalesce((x->>'rate')::numeric, r.rate_pct)) as rate
               from jsonb_array_elements(v_tx) x left join public.ref_tax_rule r on r.id = (x->>'rule')::uuid group by 1, 2, 3 order by 2 loop
    select e.detail into v_detail from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'TaxCode' and e.qbo_id = v_t.qbo;
    v_rate_ref := nullif(btrim(coalesce(v_detail->'TaxRateDetail'->0->'TaxRateRef'->>'value', '')), '');
    if v_rate_ref is null then raise exception 'QuickBooks tax code #% ("%") has no tax rate on file — Settings → QuickBooks matching → Refresh list (tax codes), then retry — nothing was sent', v_t.qbo, v_t.name; end if;
    if jsonb_array_length(coalesce(v_detail->'TaxRateDetail', '[]'::jsonb)) > 1 then v_warn := array_append(v_warn, format('tax code #%s has %s rates — first rate #%s used', v_t.qbo, jsonb_array_length(v_detail->'TaxRateDetail'), v_rate_ref)); end if;
    v_tax_lines := v_tax_lines || jsonb_build_object('DetailType', 'TaxLineDetail', 'Amount', v_t.tax,
                     'TaxLineDetail', jsonb_build_object('TaxRateRef', jsonb_build_object('value', v_rate_ref), 'PercentBased', true, 'TaxPercent', trim_scale(coalesce(v_t.rate, 0)), 'NetAmountTaxable', v_t.taxable));
  end loop;
  return jsonb_build_object('kind', 'credit', 'ims_kind', 'credit', 'ims_id', p_credit_id::text, 'name', v_c.credit_number, 'doc_number', v_c.credit_number, 'store_customer_id', v_store.id,
    'body', jsonb_strip_nulls(jsonb_build_object(
      'DocNumber', v_c.credit_number, 'TxnDate', to_char(v_c.issued_on, 'YYYY-MM-DD'),
      'CustomerRef', case when v_cust_ref is not null then jsonb_build_object('value', v_cust_ref) end,
      'CurrencyRef', jsonb_build_object('value', v_cur),
      'BillAddr', case when v_bill <> '{}'::jsonb then v_bill end, 'ShipAddr', v_ship, 'BillEmail', case when v_email is not null then jsonb_build_object('Address', v_email) end,
      'PrivateNote', v_note, 'CustomerMemo', jsonb_build_object('value', v_note || ', ' || v_store.name),
      'GlobalTaxCalculation', 'TaxExcluded', 'Line', v_lines,
      'TxnTaxDetail', jsonb_build_object('TotalTax', v_c.tax_amount, 'TaxLine', v_tax_lines))),
    'needs', v_needs, 'wait_job', v_wait, 'wait_invoice', v_wait_inv, 'warnings', to_jsonb(v_warn), 'line_count', v_n,
    'totals', jsonb_build_object('taxable', v_c.total - v_c.tax_amount, 'tax', v_c.tax_amount, 'total', v_c.total));
end;
$$;
comment on function public.qbo_credit_body(uuid) is 'qbo-sync-2c1 판정 935 · 936 · 939 · 942 · 951 · 960 ~ 962: IMS 크레딧 노트 → QBO CreditMemo 만들기 몸 — CustomerRef = 매장 · 주소 = 크레딧 노트 PDF 규칙(인보이스 bill_to + 첫 오더 ship_to / 참조는 손님 기본 주소) · BillEmail = doc_mail_recipient · 메모 둘 · 줄 = so_credit_line(콤보 구성품 줄 제외 · ItemRef 는 product · charge(surcharge · discount · freight · acct:<code>) · service · TaxCodeRef = 인보이스 줄의 오더 규칙 / 머리 규칙 / 첫 오더) · TxnTaxDetail · 돌려주는 것 = { body · needs · wait_job(960 · 열린 인보이스 일감) · wait_invoice · warnings · totals · line_count } · 인보이스 일감 없음 · skipped · 사람 짝 필요는 예외(failed)';

create function public.qbo_credit_void_body(p_credit_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_t public.qbo_txn%rowtype; v_c public.so_credit%rowtype;
begin
  select * into v_c from public.so_credit c where c.id = p_credit_id;
  if v_c.id is null then raise exception 'No IMS credit note % — nothing was sent', p_credit_id; end if;
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'credit' and t.ims_id = p_credit_id::text;
  if v_t.id is null then raise exception 'Credit note % was never sent to QuickBooks — nothing to void', v_c.credit_number; end if;
  if v_t.voided_at is not null then raise exception 'Credit note % (QuickBooks #%) is already voided — nothing was sent', v_c.credit_number, v_t.qbo_id; end if;
  return jsonb_build_object('kind', 'credit_void', 'ims_kind', 'credit', 'ims_id', p_credit_id::text, 'name', v_c.credit_number, 'doc_number', v_t.doc_number, 'qbo_id', v_t.qbo_id,
    'body', jsonb_strip_nulls(jsonb_build_object('Id', v_t.qbo_id, 'SyncToken', v_t.sync_token)), 'needs', '[]'::jsonb,
    'warnings', case when v_t.sync_token is null then '["no SyncToken on file — the sender reads the credit memo first"]'::jsonb else '[]'::jsonb end);
end;
$$;
comment on function public.qbo_credit_void_body(uuid) is 'qbo-sync-2c1 판정 963: 취소된 IMS 크레딧 노트 → QBO CreditMemo void 몸 — qbo_txn(credit) 의 Id · SyncToken(없으면 경고 · EF 가 DocNumber 로 읽어 채운다) · 보내진 적 없으면 · 이미 void 면 예외(failed) · Intuit 이 void 를 거부하면 EF 가 failed + 이유(사람이 QBO 에서) · delete 없음';

-- ═══ D) 트리거 둘(so_credit · 인보이스 꼴) + 채우기(965) ═══
create function public.qbo_job_on_credit_issue() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_realm text; v_status text;
begin
  select c.status into v_status from public.so_credit c where c.id = new.id;
  if v_status is distinct from 'issued' then return null; end if;                                                                        -- 같은 트랜잭션에서 취소됐으면 아무것도
  if not public.qbo_send_since_ok(new.issued_on) then return null; end if;                                                               -- qbo_send_since 비었거나 그 전이면 아무것도
  select c.realm_id into v_realm from public.qbo_connection c where c.singleton;
  if v_realm is null then return null; end if;                                                                                           -- 연결 없음 — 조용히
  begin
    insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'credit', 'credit', new.id::text, 'queued', new.issued_by)
    on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
  exception when others then                                                                                                             -- 발행을 막지 않는다 — 흔적을 failed 일감으로
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff) values (v_realm, 'credit', 'credit', new.id::text, 'failed', left('could not queue: ' || sqlerrm, 2000), new.issued_by)
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$$;
comment on function public.qbo_job_on_credit_issue() is 'qbo-sync-2c1: so_credit AFTER INSERT DEFERRABLE INITIALLY DEFERRED — 발행 커밋 때 qbo_job(credit · queued) 하나(960 의 기다림은 claim 때 몸이 wait_job 으로) · 같은 트랜잭션 취소 · qbo_send_since 전 · 연결 없음은 조용히 · 오류는 삼켜 발행을 막지 않는다(failed 일감으로 흔적)';

create function public.qbo_job_on_credit_cancel() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_realm text; v_j public.qbo_job%rowtype; v_t public.qbo_txn%rowtype;
begin
  if new.status <> 'cancelled' or old.status = 'cancelled' then return null; end if;
  select c.realm_id into v_realm from public.qbo_connection c where c.singleton;
  if v_realm is null then return null; end if;
  begin
    select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'credit' and j.ims_kind = 'credit' and j.ims_id = new.id::text and j.state not in ('sent', 'skipped') for update;
    if v_j.id is not null and v_j.state in ('queued', 'blocked', 'failed') then                                                          -- 아직 안 나갔다 — 건너뛴다
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left('cancelled before sending: ' || coalesce(new.cancel_note, ''), 2000), updated_by = new.cancelled_by where j.id = v_j.id;
    elsif v_j.id is not null then                                                                                                        -- sending · unknown — 닿았는지 모른다 → void 일감을 그 뒤에
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'credit_void', 'credit', new.id::text, 'blocked', v_j.id, new.cancelled_by, left('cancelled while sending: ' || coalesce(new.cancel_note, ''), 2000))
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    else
      select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'credit' and t.ims_id = new.id::text and t.voided_at is null;
      if v_t.id is not null then                                                                                                         -- 보내졌다 → void(963)
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'credit_void', 'credit', new.id::text, 'queued', new.cancelled_by, left('cancelled: ' || coalesce(new.cancel_note, ''), 2000))
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      end if;                                                                                                                            -- 둘 다 없으면(since 전 · 보낸 적 없음) 아무것도
    end if;
  exception when others then
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff) values (v_realm, 'credit_void', 'credit', new.id::text, 'failed', left('could not queue void: ' || sqlerrm, 2000), new.cancelled_by)
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$$;
comment on function public.qbo_job_on_credit_cancel() is 'qbo-sync-2c1 판정 963: so_credit AFTER UPDATE OF status(issued → cancelled) — 열린 credit 일감이 queued · blocked · failed 면 skipped(note · blocked_by 비움) · sending · unknown 이면 credit_void 일감 blocked_by 그 일감 · 열린 일감 없고 qbo_txn 이 있으면 credit_void queued · 둘 다 없으면 아무것도 · 오류는 삼킨다';

create constraint trigger so_credit_qbo_job after insert on public.so_credit deferrable initially deferred for each row execute function public.qbo_job_on_credit_issue();
create trigger so_credit_qbo_cancel after update of status on public.so_credit for each row execute function public.qbo_job_on_credit_cancel();

create function public.qbo_credit_backfill() returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text; v_n int := 0;
begin
  select c.realm_id into v_realm from public.qbo_connection c where c.singleton;
  if v_realm is null then return 0; end if;
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff)
  select v_realm, 'credit', 'credit', c.id::text, 'queued', c.issued_by
    from public.so_credit c
   where c.status = 'issued' and public.qbo_send_since_ok(c.issued_on)
     and not exists (select 1 from public.qbo_job j where j.realm_id = v_realm and j.kind = 'credit' and j.ims_kind = 'credit' and j.ims_id = c.id::text)
     and not exists (select 1 from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'credit' and t.ims_id = c.id::text)
   order by c.issued_on, c.created_at;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
comment on function public.qbo_credit_backfill() is 'qbo-sync-2c1 판정 965(속 · grant 0): qbo_send_since 이후 발행된 issued 크레딧 중 credit 일감(어느 상태든)도 거래 짝도 없는 것을 queued 로 — 트리거가 INSERT 에만 걸려 적용 전 발행분이 영영 안 쌓이는 틈을 적용 때 한 번 메운다(이 파일 끝) · 연결 없으면 0';

-- ═══ E) 판정 961 — qbo_ims_rows('charge') 의 acct:<code> 행에 크레딧 계정 줄(other · restocking_fee)이 쓴 계정을 더한다(2b1 바이트 + or exists 한 줄 · 짝 열쇠는 951 과 같은 charge · acct:<code>) ═══
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
                    or exists (select 1 from public.so_credit_line cl where cl.account_code = a.code and cl.kind in ('other', 'restocking_fee'))
                    or exists (select 1 from public.qbo_link l where l.ims_kind = 'charge' and l.ims_id = 'acct:' || a.code))
  union all select r.id::text, r.name, null, r.is_active from public.ref_service r where p_kind = 'service'
$$;
comment on function public.qbo_ims_rows(text) is 'qbo-sync-1a(속 · grant 0): 종류별 IMS 행(ims_id · 이름 · 코드 · 활성) — 짝 화면 · 자동 짝 · qbo_link_set 이 본다 · [2b1 판정 951] charge 에 「acct:<code>」 행(비용 줄이 쓴 계정 · 또는 이미 짝인 것 · _99_ 운임 제외) · [2c1 판정 961] 크레딧 노트의 other · restocking_fee 줄이 쓴 계정도 — 카드 수수료 · 잡수입 같은 계정 줄의 Item 짝 자리';

-- ═══ F) 일감 창구 재발행 — claim(2b1 바이트 + credit · credit_void 몸 + wait_job) · done(credit · credit_void) · list(credit ims_name) ═══
create or replace function public.qbo_job_claim(p_limit int default 15, p_kinds text[] default array['customer', 'item']) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_stale int; v_unblocked int; v_ids uuid[]; v_j public.qbo_job%rowtype; v_b jsonb; v_rows jsonb := '[]'::jsonb; v_failed int := 0; v_blocked int := 0; v_waiting int := 0; v_last uuid; v_nj jsonb; e jsonb;
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
                           when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                           when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid) end;   -- 2c1 credit · credit_void
      if v_b is null then raise exception 'kind % has no body', v_j.kind; end if;
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
      if nullif(v_b->>'wait_job', '') is not null then                                                                                 -- 2c1 판정 960: 크레딧은 자기 IMS 인보이스가 QBO 에 들어간 뒤 — 그 인보이스 일감 뒤에 선다(② 가 sent 때 푼다)
        update public.qbo_job j set state = 'blocked', blocked_by = (v_b->>'wait_job')::uuid, claimed_at = null,
               warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')) || array[format('waiting for invoice %s to reach QuickBooks first', coalesce(v_b->>'wait_invoice', '?'))], ' · '), '')
         where j.id = v_j.id;
        v_waiting := v_waiting + 1;
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
  return jsonb_build_object('realm_id', v_realm, 'kinds', to_jsonb(v_kinds), 'recovered_unknown', v_stale, 'unblocked', v_unblocked, 'claimed', coalesce(array_length(v_ids, 1), 0), 'body_failed', v_failed, 'blocked_for_needs', v_blocked, 'blocked_for_invoice', v_waiting, 'jobs', v_rows);
end;
$$;
comment on function public.qbo_job_claim(int, text[]) is 'qbo-sync-2a · [2b1 p_kinds] · [2c1 credit · credit_void · wait_job → blocked_by 인보이스 일감(blocked_for_invoice)]: EF send 가 service_role 로 부른다 — ① sending 10 분 넘음 → unknown ② blocked → queued(부모 sent) ③ queued · next_at 지남 · kind = any(p_kinds · 기본 customer · item — 2b2 EF 가 invoice · invoice_void 를 더해 보낸다) → sending ④ 일감마다 몸(customer · item · invoice · invoice_void · credit · credit_void) · needs 가 있으면 need 일감을 쌓고 이 일감은 blocked(blocked_for_needs) · 몸 실패는 그 일감만 failed · 돌려주는 것 = jobs[{job_id · kind · ims_kind · ims_id · attempt · request_id · name · name_alt · sku · doc_number · qbo_id · body · warnings · totals}]';

create or replace function public.qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text default null, p_intuit_tid text default null, p_note text default null, p_sku text default null, p_total_amt numeric default null, p_total_tax numeric default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_j public.qbo_job%rowtype; v_type text; v_link_err text; v_unblocked int := 0; v_i public.so_invoice%rowtype; v_c public.so_credit%rowtype; v_mismatch text; v_n int;
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
comment on function public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric) is 'qbo-sync-2a · [2b1 합계] · [2c1 credit → qbo_txn CreditMemo + 942 대조 so_credit · credit_void → voided_at]: 보내기 성공(service_role) — sending · unknown → sent · customer · item 이면 qbo_entity upsert + qbo_link(created) · invoice 면 qbo_txn insert … on conflict(ims 키) + 942 대조(p_total_amt · p_total_tax ≠ so_invoice.total · tax_amount → mismatch + warning · 상태는 sent) · invoice_void 면 qbo_txn.voided_at · QBO Id 가 이미 다른 IMS 행의 짝이면 failed + 사람 말 · 자식(blocked_by) 풀기는 kind 무관';

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
                                 when 'credit' then (select c.credit_number || ' · ' || coalesce((select cu.name from public.customer cu where cu.id = c.customer_id), '') || ' · ' || coalesce(c.currency_code, '') || ' ' || c.total from public.so_credit c where c.id::text = j.ims_id) else j.ims_id end as ims_name,   -- 2c1: 인보이스와 같은 꼴(번호 · 청구처 · 통화 총액)
             (select s.name from public.ims_staff s where s.id = j.by_staff) as by_name,
             t.qbo_id as txn_qbo_id, t.total_amt as txn_total_amt, t.total_tax as txn_total_tax, t.mismatch as txn_mismatch, t.voided_at as txn_voided_at
      from public.qbo_job j left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_kind = j.ims_kind and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit')
      where j.realm_id = v_realm and (p_state is null or (p_state = 'open' and j.state not in ('sent', 'skipped')) or j.state = p_state))
    select jsonb_build_object('state', p_state, 'total', (select count(*) from base), 'limit', v_lim, 'offset', v_off,
      'counts', (select coalesce(jsonb_object_agg(x.state, x.n), '{}'::jsonb) from (select j.state, count(*) as n from public.qbo_job j where j.realm_id = v_realm group by j.state) x),
      'rows', coalesce((select jsonb_agg(to_jsonb(b) order by case b.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end, b.created_at desc) from (select * from base order by case state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end, created_at desc limit v_lim offset v_off) b), '[]'::jsonb)));
end;
$$;
comment on function public.qbo_job_list(text, int, int) is 'qbo-sync-2a · [2b1]: 일감 목록(열쇠 qbo 또는 qbo:read) — state 하나 · open · null = 전부 · counts · 행 = 일감 + ims_name(invoice · credit = 번호 · 청구처 · 통화 총액) + by_name + 거래 짝 칸(txn_qbo_id · txn_total_amt · txn_total_tax · txn_mismatch · txn_voided_at) · unknown · failed 먼저 · limit ≤ 200';

-- ═══ G) grant — 새 함수 명시(10-30 부터 자동 grant 없음) · 재발행 셋은 옛 ACL 그대로(create or replace 는 ACL 을 지킨다) ═══
revoke all on function public.qbo_credit_body(uuid), public.qbo_credit_void_body(uuid), public.qbo_job_on_credit_issue(), public.qbo_job_on_credit_cancel(), public.qbo_credit_backfill()
  from public, anon, authenticated, service_role;

-- ═══ H) 채우기 한 번(965) — 적용 전에 발행된 since 이후 크레딧 ═══
do $$
declare v_n int;
begin
  v_n := public.qbo_credit_backfill();
  raise notice 'qbo-sync-2c1 backfill: % credit note job(s) queued (issued since qbo_send_since · no job · no QuickBooks transaction)', v_n;
end $$;

-- ═══ 착지 검사 ═══
do $$
declare v text; v_n int;
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_credit_body', 'qbo_credit_void_body', 'qbo_job_on_credit_issue', 'qbo_job_on_credit_cancel', 'qbo_credit_backfill', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_list', 'qbo_ims_rows');
  if v <> 'qbo_credit_backfill()={postgres=X/postgres} qbo_credit_body(p_credit_id uuid)={postgres=X/postgres} qbo_credit_void_body(p_credit_id uuid)={postgres=X/postgres} '
          || 'qbo_ims_rows(p_kind text)={postgres=X/postgres} qbo_job_claim(p_limit integer, p_kinds text[])={postgres=X/postgres,service_role=X/postgres} '
          || 'qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text, p_intuit_tid text, p_note text, p_sku text, p_total_amt numeric, p_total_tax numeric)={postgres=X/postgres,service_role=X/postgres} '
          || 'qbo_job_list(p_state text, p_limit integer, p_offset integer)={postgres=X/postgres,authenticated=X/postgres} qbo_job_on_credit_cancel()={postgres=X/postgres} qbo_job_on_credit_issue()={postgres=X/postgres}' then
    raise exception 'qbo-sync-2c1 landing: %', v;
  end if;
  select count(*) into v_n from pg_trigger t where t.tgrelid = 'public.so_credit'::regclass and t.tgname in ('so_credit_qbo_job', 'so_credit_qbo_cancel');
  if v_n <> 2 then raise exception 'qbo-sync-2c1 landing: so_credit triggers = % (want 2)', v_n; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_issue' and p.prosrc like '%elsif v_kind = ''tax'' then%';
  if v_n <> 0 then raise exception 'qbo-sync-2c1 landing: so_credit_issue still has the tax branch'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_invoice_cancel' and p.prosrc like '%cancel those credit notes first%' and p.prosrc like '%settle it with a credit note instead%';
  if v_n <> 1 then raise exception 'qbo-sync-2c1 landing: so_invoice_cancel lacks 959 · 968'; end if;
  raise notice 'qbo-sync-2c1 landing OK — 새 함수 5 · 재발행 6(so_invoice_cancel · so_credit_issue · qbo_ims_rows · claim · done · list) · 트리거 2';
end $$;
