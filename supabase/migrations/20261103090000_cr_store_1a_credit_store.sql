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
-- cr-store-1a — 크레딧은 낸 매장(손님)의 인보이스에만 · DB 규칙(2026-11-03 · 판정 1010 · 1030 · 1031 · 1032 · 1022′ · 1025′ · 1026′ · 1033 의 한 곳 · 이견 1 ~ 12 답)
--   바탕: Caleb 「돈만 본사에서 내는 거야. 모든 트랜잭션은 차일드 스토어와 우리 사이야. 크레딧 노트가 발행이 되면 그 크레딧은 해당 스토어의 크레딧으로만 잡히고 … 본사는 본사의 크레딧만 보이면 돼」 · 북키퍼 「크레딧은 무조건 해당 스토어와만 연동」
--   실제로 바뀌는 곳 = 본사 다섯(Clore 13 · Rex 8 · Regina 3 · BMG 1 · Lowe 1) 아래 매장 26 · 나머지 9,972 손님은 매장 = 청구처 = 자기라 아무것도 안 바뀐다 · 활성 붙임 1(CR-01008 → 60026 · 같은 매장)은 새 문을 지난다
--   A 판정 1030(이견 1 · 2) 매장 열쇠 함수 둘(새 · stable · invoker · execute authenticated · service_role):
--        so_credit_store(credit_id) = coalesce(so_credit.store_customer_id, customer_id)(qbo_credit_body · doc_data_credit 가 이미 쓰는 식)
--        so_invoice_store(invoice_id) = coalesce(so_invoice.store_customer_id(이월), 활성 so_invoice_order.customer_id 가 하나면 그것) · 둘 이상이면 null(매장 둘 인보이스 · 지금 0 장)
--   B 판정 1010 · 1022′ · 1026′(이견 3) so_credit_alloc_add 재발행(마지막 정의 20260925205011 · md5 3e9a25de…): 인보이스 갈래의 청구처 검사 뒤에 매장 문 — 인보이스 열쇠 null 이면 매장 수를 세어 둘 이상 「covers N stores」 · 0 「no store on record」 · 다르면 「belongs to store A — invoice is for store B」 · 환불 갈래 무접촉(1025′)
--   C 판정 1026′ · 1022′(이견 5) so_invoice_apply_plan 재발행(마지막 정의 20261019155731 · md5 6eb27944…): ② 크레딧 단계가 담긴 오더(p_so_ids)의 손님 하나를 매장으로 두고 so_credit_store 로 거른다 · 손님 둘 이상이면 단계 통째로 건너뜀 · 반환에 credit_skipped(null | 'multi_store') 키 하나 더함
--        부르는 곳 셋(so_invoice_issue · so_invoice_preview(Ship Ready PROFORMA credits[]) · so_service_invoice(array[p_so_id]))은 무변 — 같은 계획을 읽으므로 미리 보기도 같이 바뀐다 · 발행이 크레딧 때문에 롤백되는 길은 없다(계획 = 문 열쇠)
--   D 판정 1031 · 1032 (가)(이견 1 · 4) so_credit_issue 재발행(마지막 정의 20261102130000 · md5 0f86d160…): 인보이스 갈래 매장 = coalesce(so_invoice_store, 첫 오더 손님) + 매장 둘이면 warnings store_ambiguous ·
--        참조 갈래 — customer_id 가 매장(default_bill_to 있음)이면 거부(이견 4) · 청구처에 매장이 있으면 store_customer_id 필수(본사 자신도 됨 · 1032) · 매장 없는 손님은 지금처럼 「비면 청구처 자신」 · 미리 보기 · 발행 반환에 store_customer_id 키 더함
--   E 판정 1033 (나) 의 한 곳(1023′ (가)) so_credit_detail 재발행(마지막 정의 20261027010153 · md5 66041c90…): open_invoices(Attach 후보)를 매장으로 거른다 · 나머지 키 무변
--   무접촉: so_invoice_issue(md5 7a031482… 착지에서 단언) · so_credit_attach · so_payment_refund(환불 갈래) · so_customer_balance(청구처 합계 그대로 · cr-store-2) · so_payment_alloc_add(판정 980) · 화면 전부(cr-store-1b)
--   적용 순서: cr-store-1a → qbo-sync-2e-2(0 원 Payment 는 CreditMemo 손님 = Invoice 손님을 전제 · 1009 · 1014)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261103090000_cr_store_1a_credit_store.sql && supabase migration repair --status applied 20261103090000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=supabase/migrations/20261103090000_cr_store_1a_credit_store.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/cr_store_1a_check.sql

-- ═══ A) 판정 1030 — 매장 열쇠 함수 둘(새) ═══
create or replace function public.so_credit_store(p_credit_id uuid)
returns uuid
language sql
stable
set search_path to 'public', 'pg_temp'
as $$
  select coalesce(c.store_customer_id, c.customer_id) from public.so_credit c where c.id = p_credit_id;
$$;
comment on function public.so_credit_store(uuid) is 'cr-store-1a(판정 1030): 크레딧의 매장 = coalesce(store_customer_id, customer_id) — 크레딧 붙이기 문 · 발행 계획 · Attach 후보가 같은 열쇠를 읽는다 · 매장 없는 손님은 청구처 자신';

create or replace function public.so_invoice_store(p_invoice_id uuid)
returns uuid
language sql
stable
set search_path to 'public', 'pg_temp'
as $$
  select coalesce(i.store_customer_id,
                  (select (array_agg(distinct o.customer_id))[1] from public.so_invoice_order o where o.invoice_id = i.id and o.cancelled_at is null having count(distinct o.customer_id) = 1))
    from public.so_invoice i where i.id = p_invoice_id;
$$;
comment on function public.so_invoice_store(uuid) is 'cr-store-1a(판정 1030): 인보이스의 매장 = coalesce(so_invoice.store_customer_id(이월), 활성 so_invoice_order.customer_id 가 하나면 그것) · 매장 둘 이상이면 null(크레딧이 안 붙는다 · 1022′) · 오더 손님 = so_invoice_order.customer_id(= so.customer_id · 이견 2)';

-- ═══ B) 판정 1010 · 1022′ · 1026′ — so_credit_alloc_add 재발행(DB 바이트 + 선언 1 줄 + 매장 문 12 줄 · 환불 갈래 무접촉) ═══
CREATE OR REPLACE FUNCTION public.so_credit_alloc_add(p_credit_id uuid, p_invoice_id uuid, p_amount numeric, p_source text, p_staff uuid, p_refund_payment_id uuid DEFAULT NULL::uuid)
 RETURNS so_credit_alloc
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_c   public.so_credit%rowtype;
  v_i   public.so_invoice%rowtype;
  v_p   public.so_payment%rowtype;
  v_rem numeric;
  v_row public.so_credit_alloc%rowtype;
  v_is  uuid;  v_cs uuid;  v_ns int;                                                                                                   -- cr-store-1a(판정 1010 · 1030): 인보이스 매장 · 크레딧 매장 · 인보이스의 매장 수
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Credit allocation amount must be positive — nothing was saved'; end if;
  if p_amount <> round(p_amount, 2) then raise exception 'Amounts have at most two decimals (got %) — nothing was saved', p_amount; end if;
  if p_source not in ('manual', 'auto') then raise exception 'Unknown credit allocation source % — nothing was saved', p_source; end if;
  if (p_invoice_id is null) = (p_refund_payment_id is null) then raise exception 'A credit allocation targets exactly one of an invoice or a refund — nothing was saved'; end if;
  select * into v_c from public.so_credit c where c.id = p_credit_id for update;
  if not found then raise exception 'Credit note not found — nothing was saved'; end if;
  if v_c.status <> 'issued' then raise exception 'Credit note % is % — nothing was saved', v_c.credit_number, v_c.status; end if;
  v_rem := public.so_credit_remaining(v_c.id);                                                                                    -- so-credit-read-1 C1
  if p_amount > v_rem then raise exception 'Credit note % has only % left (asked %) — nothing was saved', v_c.credit_number, v_rem, p_amount; end if;
  if p_invoice_id is not null then
    select * into v_i from public.so_invoice i where i.id = p_invoice_id for update;
    if not found then raise exception 'Invoice not found — nothing was saved'; end if;
    if v_i.status <> 'issued' then raise exception 'Invoice % is % — nothing was saved', v_i.invoice_number, v_i.status; end if;
    if v_i.bill_to_customer_id <> v_c.customer_id then raise exception 'Invoice % bills a different customer than credit note % — nothing was saved', v_i.invoice_number, v_c.credit_number; end if;
    if v_i.currency_id <> v_c.currency_id then raise exception 'Invoice % is in % but credit note % is in % — same currency only — nothing was saved', v_i.invoice_number, v_i.currency_code, v_c.credit_number, v_c.currency_code; end if;
    -- cr-store-1a(판정 1010 · 1022′ · 1026′ · 1030 · 이견 3): 크레딧은 낸 매장의 인보이스에만 — auto(발행 계획) · manual(Attach) 둘 다 이 문을 지난다 · 계획이 같은 열쇠로 미리 거르므로 발행이 여기서 막히는 길은 없다(마지막 울타리)
    v_is := public.so_invoice_store(v_i.id);
    if v_is is null then
      select count(distinct o.customer_id) into v_ns from public.so_invoice_order o where o.invoice_id = v_i.id and o.cancelled_at is null;
      if v_ns > 1 then raise exception 'Invoice % covers % stores — a credit note applies to one store''s invoice only — split the invoice (cancel and reissue per store) — nothing was saved', v_i.invoice_number, v_ns; end if;
      raise exception 'Invoice % has no store on record — nothing was saved', v_i.invoice_number;
    end if;
    v_cs := public.so_credit_store(v_c.id);
    if v_is <> v_cs then
      raise exception 'Credit note % belongs to store % — invoice % is for store % — a credit note applies only to invoices of the store it was issued to — nothing was saved',
        v_c.credit_number, (select c.name from public.customer c where c.id = v_cs), v_i.invoice_number, (select c.name from public.customer c where c.id = v_is);
    end if;
    if exists (select 1 from public.so_credit_alloc a where a.credit_id = v_c.id and a.active_target = v_i.id) then
      raise exception 'Credit note % is already applied to invoice % — detach that first — nothing was saved', v_c.credit_number, v_i.invoice_number;
    end if;
    if p_amount > public.so_invoice_remaining(v_i.id) then raise exception 'Invoice % has only % left to pay (asked %) — nothing was saved', v_i.invoice_number, public.so_invoice_remaining(v_i.id), p_amount; end if;
  else
    select * into v_p from public.so_payment p where p.id = p_refund_payment_id;
    if not found or v_p.kind <> 'refund' or v_p.status <> 'active' then raise exception 'Refund payment not found or not an active refund — nothing was saved'; end if;
    if v_p.customer_id <> v_c.customer_id or v_p.currency_id <> v_c.currency_id then raise exception 'Refund and credit note % differ in customer or currency — nothing was saved', v_c.credit_number; end if;
  end if;
  insert into public.so_credit_alloc (credit_id, invoice_id, refund_payment_id, amount, source, created_by, updated_by)
  values (v_c.id, p_invoice_id, p_refund_payment_id, p_amount, p_source, p_staff, p_staff) returning * into v_row;
  return v_row;
end;
$function$;

-- ═══ C) 판정 1026′ · 1022′ — so_invoice_apply_plan 재발행(DB 바이트 + 선언 1 줄 + 매장 셈 3 줄 + where 1 줄 + 반환 키 1) ═══
CREATE OR REPLACE FUNCTION public.so_invoice_apply_plan(p_customer_id uuid, p_currency_id uuid, p_so_ids uuid[], p_total numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_left    numeric := p_total;
  v_recv    numeric;
  v_avail   numeric;
  v_take    numeric;
  v_deposit numeric := 0;  v_credit numeric := 0;  v_balance numeric := 0;
  v_steps   jsonb := '[]'::jsonb;
  v_used    jsonb := '{}'::jsonb;                                                       -- 결제마다 이 계획이 이미 쓴 몫(① 뒤 ③ 의 남은 금액 = 남은 금액 − 쓴 몫)
  pay       record;
  cr        record;
  v_store   uuid;  v_nst int;  v_skip text;                                            -- cr-store-1a(판정 1010 · 1022′ · 1026′): 담긴 오더의 매장(손님) · 그 수 · 크레딧 단계를 건너뛴 까닭
begin
  -- ⓑ2 ① 담긴 오더를 대상으로 한 선결제(판정 4 · auto_deposit) — 받은 날 순 · 한도 = 결제 남은 금액 · 인보이스 남은 돈 · 받아 둔 돈(received — 붙일 때마다 그만큼 준다)
  select b.received into v_recv from public.so_customer_balance(p_customer_id) b where b.currency_id = p_currency_id;
  v_recv := coalesce(v_recv, 0);
  for pay in
    select p.id, p.paid_on, p.method, p.reference, p.created_at, public.so_payment_remaining(p.id) as remaining
      from public.so_payment p
     where p.customer_id = p_customer_id and p.currency_id = p_currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o where o.payment_id = p.id and o.so_id = any(p_so_ids))
     order by p.paid_on, p.created_at, p.id
  loop
    exit when v_left <= 0;
    if pay.remaining <= 0 then continue; end if;
    v_take := least(pay.remaining, v_left, v_recv);
    if v_take <= 0 then continue; end if;
    v_deposit := v_deposit + v_take;  v_left := v_left - v_take;  v_recv := v_recv - v_take;
    v_used := v_used || jsonb_build_object(pay.id::text, v_take);
    v_steps := v_steps || jsonb_build_object('step', 'auto_deposit', 'payment_id', pay.id, 'amount', v_take, 'paid_on', pay.paid_on, 'method', pay.method, 'reference', pay.reference, 'created_at', pay.created_at);
  end loop;
  -- ⓒ2 ② 크레딧(진 빚 · 8-e 「크레딧부터」 · 판정 5) — issued 크레딧을 발행일 순으로 인보이스만큼만
  --   cr-store-1a(판정 1010 · 1022′ · 1026′ · 1030): 낸 매장의 크레딧만 — 매장 = 담긴 오더의 손님(so.customer_id · 하나여야 한다) · 둘 이상이면 이 단계를 통째로 건너뛴다(credit_skipped = 'multi_store' · 문 so_credit_alloc_add 와 같은 열쇠 so_credit_store)
  select count(distinct s.customer_id), (array_agg(distinct s.customer_id))[1] into v_nst, v_store from public.so s where s.id = any(p_so_ids);
  v_skip := case when v_nst > 1 then 'multi_store' end;
  if v_left > 0 and v_nst = 1 then
    for cr in
      select c.id, c.credit_number, c.issued_on, public.so_credit_remaining(c.id) as remaining
        from public.so_credit c
       where c.customer_id = p_customer_id and c.currency_id = p_currency_id and c.status = 'issued'
         and public.so_credit_store(c.id) = v_store
       order by c.issued_on, c.created_at, c.id
    loop
      exit when v_left <= 0;
      if cr.remaining <= 0 then continue; end if;
      v_take := least(cr.remaining, v_left);
      v_credit := v_credit + v_take;  v_left := v_left - v_take;
      v_steps := v_steps || jsonb_build_object('step', 'auto_credit', 'credit_id', cr.id, 'credit_number', cr.credit_number, 'amount', v_take, 'issued_on', cr.issued_on);
    end loop;
  end if;
  -- ⓑ2 ③ 손님의 받아 둔 돈(판정 5 · auto_balance) — 다른 오더 예약분 제외 · 인보이스만큼만 · 받은 날 순
  --   예약분 = 아직 열린(fulfilled · cancelled 아님 · 살아 있는 인보이스 없음) 다른 오더를 대상으로 한 결제의 남은 금액 — 담긴 오더(p_so_ids)는 뺀다(발행 때는 이미 fulfilled 라 so_payment_is_reserved 가 저절로 뺐다 · 미리 보기는 아직 packed)
  if v_left > 0 then
    select greatest(v_recv - coalesce(sum(public.so_payment_remaining(p.id) - coalesce((v_used->>(p.id::text))::numeric, 0)), 0), 0) into v_avail
      from public.so_payment p
     where p.customer_id = p_customer_id and p.currency_id = p_currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o join public.so s on s.id = o.so_id
                    where o.payment_id = p.id and s.status not in ('fulfilled', 'cancelled') and not (s.id = any(p_so_ids))
                      and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id));
    v_avail := coalesce(v_avail, 0);
    for pay in
      select p.id, p.paid_on, p.method, p.reference, p.created_at, public.so_payment_remaining(p.id) - coalesce((v_used->>(p.id::text))::numeric, 0) as remaining
        from public.so_payment p
       where p.customer_id = p_customer_id and p.currency_id = p_currency_id and p.status = 'active' and p.kind = 'payment'
         and not exists (select 1 from public.so_payment_order o join public.so s on s.id = o.so_id
                          where o.payment_id = p.id and s.status not in ('fulfilled', 'cancelled') and not (s.id = any(p_so_ids))
                            and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id))
       order by p.paid_on, p.created_at, p.id
    loop
      exit when v_left <= 0 or v_avail <= 0;
      if pay.remaining <= 0 then continue; end if;
      v_take := least(pay.remaining, v_left, v_avail);
      if v_take <= 0 then continue; end if;
      v_balance := v_balance + v_take;  v_left := v_left - v_take;  v_avail := v_avail - v_take;
      v_steps := v_steps || jsonb_build_object('step', 'auto_balance', 'payment_id', pay.id, 'amount', v_take, 'paid_on', pay.paid_on, 'method', pay.method, 'reference', pay.reference, 'created_at', pay.created_at);
    end loop;
  end if;
  return jsonb_build_object('deposit', v_deposit, 'credit', v_credit, 'balance', v_balance, 'left', v_left, 'steps', v_steps, 'credit_skipped', v_skip);   -- cr-store-1a(이견 5): 키 하나 더하기만(null | 'multi_store')
end;
$function$;

-- ═══ D) 판정 1031 · 1032 — so_credit_issue 재발행(DB 바이트 + 인보이스 갈래 매장 2 줄 + 참조 갈래 검사 둘 + 반환 키 둘) ═══
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
    v_store := coalesce(public.so_invoice_store(v_inv.id), v_first_io.customer_id);                                                                         -- cr-store-1a(판정 1030 · 1031 · 이견 1 · 2): 인보이스 크레딧의 매장 = 인보이스의 매장 열쇠(이월은 store_customer_id · sale 은 오더 손님 so_invoice_order.customer_id) · 매장 둘 인보이스(열쇠 null)만 첫 오더(so_number 순)의 손님으로 + 경고
    if v_store is not null and public.so_invoice_store(v_inv.id) is null then v_warn := array_append(v_warn, 'store_ambiguous'); end if;
  elsif p ? 'cin7' then
    raise exception 'The cin7 key is gone — send ref {invoice_number, order_number, invoice_date} for a credit without an IMS invoice — nothing was saved';   -- crn-1 판정 609
  elsif p->'ref' is not null and jsonb_typeof(p->'ref') = 'object' then
    v_ref := true;
    v_ref_inv := nullif(trim(p->'ref'->>'invoice_number'), '');  v_ref_ord := nullif(trim(p->'ref'->>'order_number'), '');  v_ref_date := nullif(p->'ref'->>'invoice_date', '')::date;
    if v_ref_inv is null then raise exception 'A reference credit needs ref.invoice_number (the number on the paper invoice) — nothing was saved'; end if;
    if nullif(p->>'customer_id', '') is null then raise exception 'A reference credit needs customer_id — nothing was saved'; end if;
    v_cust := (p->>'customer_id')::uuid;  v_origin_on := v_ref_date;
    if not exists (select 1 from public.customer c where c.id = v_cust) then raise exception 'Customer not found — nothing was saved'; end if;
    if (select c.default_bill_to_customer_id from public.customer c where c.id = v_cust) is not null then                                           -- cr-store-1a(이견 4): customer_id 는 청구처여야 한다 — 매장을 보내면 그 크레딧은 어느 인보이스(청구처 이름)에도 못 붙는다
      raise exception 'Customer % bills to % — send customer_id = the bill-to and store_customer_id = this store — nothing was saved',
        (select c.name from public.customer c where c.id = v_cust), (select b.name from public.customer c join public.customer b on b.id = c.default_bill_to_customer_id where c.id = v_cust);
    end if;
    v_store := nullif(p->>'store_customer_id', '')::uuid;                                                                                       -- hcr-1 판정 779: 매장(종이 · 목록의 이름) · 돈(customer_id)은 매장의 청구처 coalesce(default_bill_to_customer_id, id) 여야 한다
    if v_store is not null then
      if not exists (select 1 from public.customer c where c.id = v_store) then raise exception 'Store customer not found — nothing was saved'; end if;
      if v_cust <> (select coalesce(c.default_bill_to_customer_id, c.id) from public.customer c where c.id = v_store) then
        raise exception 'customer_id must be the bill-to of store % — the money goes to the bill-to, the paper and the list show the store — nothing was saved', (select c.name from public.customer c where c.id = v_store);
      end if;
    else
      if exists (select 1 from public.customer s where s.default_bill_to_customer_id = v_cust) then                                                  -- cr-store-1a(판정 1032 (가)): 매장을 둔 청구처는 매장 필수(본사 자신도 고를 수 있다 · 본사도 독립적으로 오더한다) · 매장 없는 손님만 「비면 청구처 자신」
        raise exception 'Customer % has stores — pick the store this credit belongs to (or the head office itself) — nothing was saved', (select c.name from public.customer c where c.id = v_cust);
      end if;
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
    return jsonb_build_object('committed', false, 'issued_on', v_on, 'customer_id', v_cust, 'store_customer_id', v_store, 'currency_code', v_cur.code, 'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
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
  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', v_cr.status, 'issued_on', v_on, 'customer_id', v_cust, 'store_customer_id', v_store, 'currency_code', v_cur.code,
                            'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                            'origin', case when v_ref then jsonb_build_object('ref_invoice_number', v_ref_inv, 'ref_order_number', v_ref_ord, 'ref_invoice_date', v_ref_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src)
                                           else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'order_discount_amount', v_cr.order_discount_amount, 'freight_discount_amount', v_cr.freight_discount_amount, 'fee_amount', v_cr.fee_amount, 'surcharge_amount', v_cr.surcharge_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ E) 판정 1033 (나) 의 한 곳 — so_credit_detail 재발행(DB 바이트 + open_invoices where 1 줄) ═══
CREATE OR REPLACE FUNCTION public.so_credit_detail(p_credit_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cr public.so_credit%rowtype;
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- rls-3b(판정 582): 첫 줄 문 = Credit Notes 의 열쇠(sales 보기) · definer 라 표 정책을 지나므로 여기서 거른다
  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if not found then raise exception 'Credit note not found'; end if;
  return jsonb_build_object(
    'credit', to_jsonb(v_cr),
    'customer_name', (select c.name from public.customer c where c.id = v_cr.customer_id),
    'store_name', (select c.name from public.customer c where c.id = v_cr.store_customer_id),                                           -- hcr-1 판정 779: 매장 이름(credit.store_customer_id 와 credit.warnings 는 to_jsonb 로 저절로)
    'invoice_number', (select i.invoice_number from public.so_invoice i where i.id = v_cr.invoice_id),
    'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.line_no), '[]'::jsonb) from public.so_credit_line l where l.credit_id = v_cr.id),
    'allocations', (select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at), '[]'::jsonb) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'applied', (select coalesce(sum(a.amount), 0) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'remaining', public.so_credit_remaining(v_cr.id),                                                                                   -- so-credit-read-1 C1: 식의 한 곳(옛 식은 C0 정의 그대로였다)
    -- so-credit-read-1 R2(2026-09-25) — 더한 키 넷(옛 키 아홉은 그대로 · 부르는 곳 0 이지만 규칙대로 더하기만)
    'credit_row', (select to_jsonb(v) from public.so_credit_list v where v.id = v_cr.id),
    'allocations_all', (select coalesce(jsonb_agg(jsonb_build_object('alloc_id', a.id, 'invoice_id', a.invoice_id, 'invoice_number', i.invoice_number, 'invoice_status', i.status,
                                                                     'refund_payment_id', a.refund_payment_id, 'refund_paid_on', p.paid_on, 'refund_method', p.method, 'refund_reference', p.reference, 'refund_status', p.status,
                                                                     'amount', a.amount, 'source', a.source, 'voided_at', a.voided_at, 'void_note', a.void_note, 'created_at', a.created_at) order by a.created_at), '[]'::jsonb)
                        from public.so_credit_alloc a left join public.so_invoice i on i.id = a.invoice_id left join public.so_payment p on p.id = a.refund_payment_id
                        where a.credit_id = v_cr.id),
    'open_invoices', (select coalesce(jsonb_agg(jsonb_build_object('invoice_id', l.id, 'invoice_number', l.invoice_number, 'issued_on', l.issued_on, 'due_on', l.due_on, 'due_unknown', l.due_unknown,
                                                                   'total', l.total, 'remaining', l.remaining, 'days_overdue', l.days_overdue, 'so_numbers', l.so_numbers,
                                                                   'attached_from_this_credit', coalesce((select sum(a.amount) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.invoice_id = l.id and a.voided_at is null), 0)) order by l.issued_on, l.invoice_number), '[]'::jsonb)
                      from public.so_invoice_list l
                      where l.is_open and l.bill_to_customer_id = v_cr.customer_id and l.currency_id = v_cr.currency_id
                        and public.so_invoice_store(l.id) = public.so_credit_store(v_cr.id)),                                                       -- cr-store-1a(판정 1033 (나) 의 한 곳 · 1023′ (가)): Attach 후보 = 크레딧을 낸 매장의 열린 인보이스만(문 so_credit_alloc_add 와 같은 열쇠)
    'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_cr.customer_id) b where b.currency_id = v_cr.currency_id),
    'ledger', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'occurred_on', g.occurred_on, 'sku', g.sku, 'warehouse', g.warehouse, 'bin', g.bin, 'qty_delta', g.qty_delta, 'line_ref', g.line_ref, 'cost', g.raw -> 'cost') order by g.id), '[]'::jsonb)
                 from public.inv_ledger g where g.doc_type = 'creditnote' and g.doc_number = v_cr.credit_number and g.source = 'ims'),
    'layers', (select coalesce(jsonb_agg(jsonb_build_object('id', y.id, 'sku', y.sku, 'warehouse', y.warehouse, 'qty', y.qty, 'unit_cost', case when (select public.ims_can_view_cost()) then y.unit_cost end /* rls-3b(판정 580): 원가 값만 열쇠로 */, 'cost_source', y.cost_source, 'parent_layer_id', y.parent_layer_id,
                                                            'consumed', (select coalesce(sum(k.qty), 0) from public.inv_layer_consume k where k.layer_id = y.id)) order by y.id), '[]'::jsonb)
               from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = v_cr.credit_number));
end;

$function$;

-- ═══ F) grant — 새 함수 둘 명시(10-30 부터 자동 grant 없음 · 부르는 창구 so_invoice_apply_plan · so_credit_alloc_add 가 invoker 라 직원 · 서비스 둘 다) · 재발행 넷은 옛 ACL 그대로(create or replace 는 ACL 을 지킨다) ═══
revoke all on function public.so_credit_store(uuid), public.so_invoice_store(uuid) from public, anon;
grant execute on function public.so_credit_store(uuid), public.so_invoice_store(uuid) to authenticated, service_role;

-- ═══ 착지 검사 — 열쇠 둘 · 무접촉 md5 · 권한 · 실물(issued 인보이스 · 크레딧 전부 열쇠 null 0 · 어긋난 활성 붙임 0 · 오더 손님 두 칸 같음) ═══
do $$
declare v text; v_n int; v_m int;
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-') || ':' || p.provolatile::text || ':' || p.prosecdef::text, ' ' order by p.proname) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_credit_store', 'so_invoice_store', 'so_credit_alloc_add', 'so_invoice_apply_plan', 'so_credit_issue', 'so_credit_detail');
  if v <> 'so_credit_alloc_add(p_credit_id uuid, p_invoice_id uuid, p_amount numeric, p_source text, p_staff uuid, p_refund_payment_id uuid)={postgres=X/postgres,service_role=X/postgres}:v:false '
          || 'so_credit_detail(p_credit_id uuid)={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}:s:true '
          || 'so_credit_issue(p jsonb, p_commit boolean)={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}:v:true '
          || 'so_credit_store(p_credit_id uuid)={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}:s:false '
          || 'so_invoice_apply_plan(p_customer_id uuid, p_currency_id uuid, p_so_ids uuid[], p_total numeric)={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}:s:false '
          || 'so_invoice_store(p_invoice_id uuid)={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}:s:false' then
    raise exception 'cr-store-1a landing (acl): %', v;
  end if;
  select md5(p.prosrc) into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_invoice_issue';
  if v <> '7a03148223048349d2b9d461969ca3f6' then raise exception 'cr-store-1a landing: so_invoice_issue body changed (md5 %) — it must stay the svc_1c body', v; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace
    and ((p.proname = 'so_credit_alloc_add' and p.prosrc like '%has no store on record%' and p.prosrc like '%covers % stores%' and p.prosrc like '%Refund and credit note % differ in customer or currency%')
      or (p.proname = 'so_invoice_apply_plan' and p.prosrc like '%credit_skipped%' and p.prosrc like '%so_credit_store(c.id) = v_store%')
      or (p.proname = 'so_credit_issue' and p.prosrc like '%store_ambiguous%' and p.prosrc like '%has stores — pick the store%' and p.prosrc like '%bills to % — send customer_id = the bill-to%')
      or (p.proname = 'so_credit_detail' and p.prosrc like '%so_invoice_store(l.id) = public.so_credit_store(v_cr.id)%'));
  if v_n <> 4 then raise exception 'cr-store-1a landing: reissued bodies carry the new text = % (want 4)', v_n; end if;
  select count(*) into v_n from public.so_invoice i where i.status = 'issued' and public.so_invoice_store(i.id) is null;
  select count(*) into v_m from public.so_invoice i where i.status = 'issued';
  if v_n <> 0 then raise exception 'cr-store-1a landing: % of % issued invoices have no store key (null) — look before applying', v_n, v_m; end if;
  select count(*) into v_n from public.so_credit c where public.so_credit_store(c.id) is null;
  if v_n <> 0 then raise exception 'cr-store-1a landing: % credit notes have no store key', v_n; end if;
  select count(*) into v_n from public.so_invoice_order o join public.so s on s.id = o.so_id where o.customer_id is distinct from s.customer_id;
  if v_n <> 0 then raise exception 'cr-store-1a landing: % so_invoice_order rows whose customer_id differs from so.customer_id (the two order-customer columns must agree · 이견 2)', v_n; end if;
  select count(*) into v_n from public.so_credit_alloc a join public.so_invoice i on i.id = a.invoice_id where a.voided_at is null and public.so_invoice_store(i.id) is distinct from public.so_credit_store(a.credit_id);
  if v_n <> 0 then raise exception 'cr-store-1a landing: % active credit allocation(s) cross stores (C-1) — detach and reattach per store (cr-store-0 §C-3) before applying', v_n; end if;
  raise notice 'cr-store-1a landing OK — 새 함수 2 · 재발행 4(alloc_add · apply_plan · credit_issue · credit_detail) · so_invoice_issue 무변 · issued 인보이스 % 전부 열쇠 있음 · 어긋난 붙임 0', v_m;
end $$;
