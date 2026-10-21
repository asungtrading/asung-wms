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

-- ═══ crn-1 — 인보이스 없는 크레딧(참조 번호 크레딧) 손질 (2026-10-21 · 판정 602 · 609 · 610 · crn-0 조사 · 정본 so-module §19 · §22-c · §69 뒤) ═══
--   계기: Caleb 「컷오버 이후에 cin7에서 발행된 인보이스 내역에 대한 크레딧 노트를 발행할 수가 없어」 — 길은 이미 있었다(so_credit_issue 의 cin7{…} 갈래 · crn-0 이견 1) · 이름 · 세금 · 원가 · 경고만 손질한다.
--   ① 이름(판정 609 · IMS 는 Cin7 을 주어로 쓰지 않는다 · 실데이터 0): so_credit.cin7_invoice_number → ref_invoice_number · cin7_order_number → ref_order_number · cin7_invoice_date → ref_invoice_date(rename · CHECK so_credit_origin_ck 는 따라온다 · comment 다시)
--      · 입력 열쇠 cin7{…} → ref{invoice_number, order_number, invoice_date}(옛 열쇠 cin7 은 분명한 글로 거부) · 거부 · 경고 글에서 「Cin7」 을 뺀다 · 반환 origin 의 열쇠 ref_* · 원장 raw.header 열쇠 ref_invoice_number
--      · 뷰 so_credit_list 는 drop + create(출력 칸 이름을 바꾸려면 replace 로는 안 된다) — 칸 둘 이름만 · 식 · 순서 · ACL · security_invoker · comment 그대로 · so_credit_detail 은 to_jsonb(행) · 뷰 행이라 열쇠가 저절로 따라온다(재발행 없음)
--   ② 세금 기본(판정 610): tax_rule 을 안 보내면 손님 기본 배송지(customer_address · Shipping · is_default_for_type)의 나라 · 주 → so_tax_rule_for(…, 크레딧 날짜, 'sale') · 보내면 보낸 것 · 배송지가 없거나 규칙을 못 찾으면 거부(직원이 고른다) · origin.tax_rule_source = 'given' | 'ship_to'
--   ③ 원가(판정 602 · 되짚지 않는다): inv_post_credit 이 원 판매로 so_line → so 의 번호만 넘긴다(참조 크레딧은 so_line 이 없어 null → inv_layer_post_credit ② 가중평균 → ③ 최근 → ④ unknown) · ref_order_number 는 기록만 · 경고 origin_sale_unknown 은 인보이스 크레딧에만
--   ④ 경고: 참조 크레딧 미리 보기 · 발행에 늘 manual_unit_price · 같은 손님 · 같은 참조 번호(대소문자 · 앞뒤 공백 무시) · 같은 SKU 의 앞선 발행 크레딧이 있으면 reference_seen:<CR 번호들>(막지 않음) · 옛 경고 origin_sale_unknown(so_credit_issue 의 것)은 뺀다(되짚지 않으니 뜻이 없다)
--   ⑤ 문 그대로(발행 · 취소 manager · 붙이기 sales) · 인보이스 크레딧 갈래는 바이트 그대로(이름 바꾼 변수 · 열쇠 말고는 줄 0 — 동일성 시험 I1) · 운영에는 닿지 않는다(가드).

create temp table crn1_before as
select (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname in ('so_credit_prepare', 'so_credit_cancel', 'so_credit_detail', 'so_credit_attach', 'so_credit_detach', 'so_credit_alloc_add', 'so_credit_remaining', 'so_customer_balance', 'inv_layer_post_credit', 'inv_layer_apply_credit', 'so_detail', 'doc_data', 'doc_data_common')) as others,
       (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_credit_issue', 'inv_post_credit', 'doc_data_credit')) as acls,
       (select coalesce(c.relacl::text, '-') || '|' || coalesce(c.reloptions::text, '-') || '|' || coalesce(obj_description(c.oid), '-') from pg_class c where c.oid = 'public.so_credit_list'::regclass) as view_meta,
       (select string_agg(attname, ',' order by attnum) from pg_attribute where attrelid = 'public.so_credit_list'::regclass and attnum > 0 and not attisdropped) as view_cols,
       (select string_agg(conname || ':' || pg_get_constraintdef(oid), ' ' order by conname) from pg_constraint where conrelid = 'public.so_credit'::regclass and contype = 'c' and conname <> 'so_credit_origin_ck') as other_checks,
       (select count(*) from public.so_credit) as n_credits,
       (select count(*) from public.so_credit where cin7_invoice_number is not null or cin7_order_number is not null or cin7_invoice_date is not null) as n_ref_rows;

-- ═══ ① 칸 이름(판정 609) ═══
alter table public.so_credit rename column cin7_invoice_number to ref_invoice_number;
alter table public.so_credit rename column cin7_order_number   to ref_order_number;
alter table public.so_credit rename column cin7_invoice_date   to ref_invoice_date;
comment on column public.so_credit.ref_invoice_number is 'crn-1 판정 602 · 609 — 참조 번호: 인보이스 없는 크레딧(컷오버 전 종이 인보이스 · IMS 에서 특정할 수 없는 판매)의 옛 인보이스 번호 · 글자 · 필수(so_credit_origin_ck: invoice_id 와 정확히 하나) · 옛 이름 cin7_invoice_number';
comment on column public.so_credit.ref_order_number   is 'crn-1 판정 602 · 609 — 참조 오더 번호(선택 · 기록만) · 원가는 되짚지 않는다(inv_post_credit 은 so_line 의 오더만 넘긴다 → 참조 크레딧은 inv_layer_post_credit ② 가중평균 → ③ 최근 → ④ unknown) · 옛 이름 cin7_order_number · ~~판정 6 되짚기 열쇠~~';
comment on column public.so_credit.ref_invoice_date   is 'crn-1 판정 609 — 참조 인보이스 날짜(선택 · origin_invoice_on 에 복사 · 리스탁킹 피 알림 창의 기준) · 옛 이름 cin7_invoice_date';

-- ═══ ① 뷰 so_credit_list — 칸 둘 이름만(출력 칸 이름은 replace 로 못 바꾼다 → drop + create · 식 · 순서 · ACL · security_invoker · comment 그대로) ═══
drop view public.so_credit_list;
create view public.so_credit_list with (security_invoker = true) as
 WITH al AS (
         SELECT a.credit_id,
            sum(a.amount) FILTER (WHERE a.invoice_id IS NOT NULL) AS applied_to_invoices,
            sum(a.amount) FILTER (WHERE a.refund_payment_id IS NOT NULL) AS refunded,
            string_agg(i_1.invoice_number, ', '::text ORDER BY i_1.invoice_number) FILTER (WHERE a.invoice_id IS NOT NULL) AS invoice_numbers_applied
           FROM so_credit_alloc a
             LEFT JOIN so_invoice i_1 ON i_1.id = a.invoice_id
          WHERE a.voided_at IS NULL
          GROUP BY a.credit_id
        )
 SELECT c.id,
    c.credit_number,
    c.status,
    c.issued_on,
    c.customer_id,
    cu.name AS customer_name,
    c.currency_id,
    c.currency_code,
    c.reason,
    c.note,
    c.warehouse_id,
    c.warehouse_name,
    c.invoice_id,
    i.invoice_number,
    c.ref_invoice_number,
    c.ref_order_number,
    c.origin_invoice_on,
    c.lines_amount,
    c.fee_amount,
    c.tax_amount,
    c.total,
    COALESCE(al.applied_to_invoices, 0::numeric) AS applied_to_invoices,
    COALESCE(al.refunded, 0::numeric) AS refunded,
    r.remaining,
    al.invoice_numbers_applied,
    c.cancelled_at,
    c.cancel_note,
    c.created_at,
    ( SELECT s.name
           FROM ims_staff s
          WHERE s.id = c.issued_by) AS issued_by_name,
    (((((((((((c.credit_number || ' '::text) || COALESCE(cu.name, ''::text)) || ' '::text) || COALESCE(i.invoice_number, ''::text)) || ' '::text) || COALESCE(c.ref_invoice_number, ''::text)) || ' '::text) || COALESCE(al.invoice_numbers_applied, ''::text)) || ' '::text) || c.reason) || ' '::text) || COALESCE(c.note, ''::text) AS search_text,
    c.surcharge_amount
   FROM so_credit c
     LEFT JOIN customer cu ON cu.id = c.customer_id
     LEFT JOIN so_invoice i ON i.id = c.invoice_id
     LEFT JOIN al ON al.credit_id = c.id
     CROSS JOIN LATERAL ( SELECT so_credit_remaining(c.id) AS remaining) r;
revoke all on public.so_credit_list from public, anon, authenticated, service_role;                          -- 기본 권한(pg_default_acl)이 anon · authenticated 에 전부를 준다(rls-3a 이견 7) → 비우고 원본 ACL 만 · 순서까지(postgres · service_role · authenticated)
grant select, insert, update, delete, truncate, references, trigger, maintain on public.so_credit_list to service_role;   -- arwdDxtm(원본과 같은 비트 · maintain 까지)
grant select on public.so_credit_list to authenticated;
comment on view public.so_credit_list is '⭐ 크레딧 노트 목록(so-credit-read-1 R1 · surcharge-2b 열 하나 끝에) — 한 장 한 행 · security_invoker · applied_to_invoices · refunded · remaining = so_credit_remaining(id) · applied + refunded + remaining = total(issued) · ⭐ surcharge_amount(자동 surcharge 줄 합 · lines_amount 밖 · total 에는 들어 있다) · invoice_number(원판매) · search_text · crn-1 판정 609: cin7_invoice_number · cin7_order_number → ref_invoice_number · ref_order_number(참조 크레딧 · 인보이스 없음)';

-- ═══ so_credit_issue 재발행 — 원본 20261020010711_od_1_manual_lines_order_discount_name_lock.sql:306 바이트 + 더한 · 바꾼 줄만 · crn-1 ═══
CREATE OR REPLACE FUNCTION public.so_credit_issue(p jsonb, p_commit boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_reasons   constant text[] := array['customer_return','damaged','billing_error','other'];
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
  elsif p ? 'cin7' then
    raise exception 'The cin7 key is gone — send ref {invoice_number, order_number, invoice_date} for a credit without an IMS invoice — nothing was saved';   -- crn-1 판정 609
  elsif p->'ref' is not null and jsonb_typeof(p->'ref') = 'object' then
    v_ref := true;
    v_ref_inv := nullif(trim(p->'ref'->>'invoice_number'), '');  v_ref_ord := nullif(trim(p->'ref'->>'order_number'), '');  v_ref_date := nullif(p->'ref'->>'invoice_date', '')::date;
    if v_ref_inv is null then raise exception 'A reference credit needs ref.invoice_number (the number on the paper invoice) — nothing was saved'; end if;
    if nullif(p->>'customer_id', '') is null then raise exception 'A reference credit needs customer_id — nothing was saved'; end if;
    v_cust := (p->>'customer_id')::uuid;  v_origin_on := v_ref_date;
    if not exists (select 1 from public.customer c where c.id = v_cust) then raise exception 'Customer not found — nothing was saved'; end if;
    select * into v_cur from public.ref_currency c
     where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), (select c3.currency_id from public.customer c3 where c3.id = v_cust));
    if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
    if nullif(trim(p->>'tax_rule'), '') is not null then                                                  -- 보낸 규칙 그대로(활성 판매 규칙 검사 그대로)
      select * into v_rule from public.ref_tax_rule r where r.name = trim(p->>'tax_rule') and r.direction = 'sale' and r.is_active;
      if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', trim(p->>'tax_rule'); end if;
      v_tax_src := 'given';
    else                                                                                                  -- crn-1 판정 610: 손님 기본 배송지의 주 → so_tax_rule_for(IMS 인보이스와 같은 식) · 없으면 거부(직원이 고른다)
      select * into v_sa from public.customer_address a where a.customer_id = v_cust and a.type = 'Shipping' and a.is_active and a.is_default_for_type limit 1;
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

  -- 줄 — 첫 바퀴: product · freight · tax · other(수수료는 둘째 바퀴 · 제품 합이 먼저 필요하다)
  for x in select t from jsonb_array_elements(p->'lines') t loop
    v_kind := nullif(trim(x->>'kind'), '');
    if v_kind = 'surcharge' then raise exception 'Surcharge lines are added automatically from the returned product lines — do not send them — nothing was saved'; end if;   -- surcharge-2b(D-3 · 자동만)
    if v_kind = 'freight_discount' then raise exception 'Freight discount lines are added automatically from the returned freight line — do not send them — nothing was saved'; end if;   -- fr-3 판정 355(자동만)
    if v_kind is null or v_kind not in ('product','freight','tax','other','restocking_fee') then raise exception 'Line kind must be one of product, freight, tax, other, restocking_fee — nothing was saved'; end if;
    if v_kind = 'restocking_fee' then v_fee_lines := v_fee_lines + 1; continue; end if;
    v_il := null;  v_io := null;  v_pr := null;  v_bin := null;  v_acct := null;  v_fd := null;  v_fd_line := 0;                                                           -- fr-3
    v_qty := null;  v_unit := null;  v_rate := null;  v_bin_id := null;  v_bin_name := null;  v_nr := null;  v_nr_note := null;  v_product_id := null;  v_so_line_id := null;  v_sku := null;  v_il_id := null;  v_desc := null;  v_est := null;
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
        select coalesce(sum(cl.qty_returned), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id
         where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        select coalesce(sum((t->>'qty_returned')::numeric), 0) into v_ask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(t->>'so_invoice_line_id', '')::uuid = v_il.id;
        if v_already + v_ask > v_il.qty then
          raise exception 'Invoice % line % (%): % of % already credited and % asked now — only % can still be returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, v_already, v_il.qty, v_ask, v_il.qty - v_already;
        end if;
        v_unit := v_il.unit_price;  v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
        select * into v_pr from public.product pr where pr.id = v_product_id;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      v_amount := round(v_qty * coalesce(v_unit, 0), 2);  v_tax := public.so_tax_amount(v_amount, v_rate);
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
    elsif v_kind = 'tax' then
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null or v_amount < 0 then raise exception 'A tax line needs amount ≥ 0 (the tax being returned) — nothing was saved'; end if;
      v_rate := null;  v_tax := 0;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Tax');
      if v_acct.id is null then
        select * into v_acct from public.ref_account a where a.id = (case when v_ref then v_rule.account_id else (select r.account_id from public.ref_tax_rule r where r.id = v_first_io.tax_rule_id) end);
      end if;
    else   -- other
      v_amount := nullif(x->>'amount', '')::numeric;  v_desc := nullif(trim(x->>'description'), '');
      if v_amount is null or v_amount < 0 then raise exception 'An other line needs amount ≥ 0 — nothing was saved'; end if;
      if v_desc is null then raise exception 'An other line needs a description — nothing was saved'; end if;
      if v_acct.id is null then raise exception 'An other line needs account_id (no default) — nothing was saved'; end if;
      v_rate := case when v_ref then v_rule.rate_pct else v_first_io.rate_pct end;  v_tax := public.so_tax_amount(v_amount, v_rate);
    end if;
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);  v_parent_ln := v_ln;
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

  -- crn-1 판정 602 · crn-0 §2-5: 참조 크레딧 경고 — 늘 manual_unit_price(인보이스 없이 넣은 단가 · 화면이 크게) · 같은 손님 · 같은 참조 번호(대소문자 · 앞뒤 공백 무시) · 같은 SKU 의 앞선 발행 크레딧이 있으면 reference_seen:<CR 번호들>(막지 않는다)
  if v_ref then
    v_warn := array_append(v_warn, 'manual_unit_price');
    select string_agg(distinct c2.credit_number, ', ') into v_seen
      from public.so_credit c2 join public.so_credit_line l2 on l2.credit_id = c2.id
     where c2.customer_id = v_cust and c2.status = 'issued' and lower(trim(c2.ref_invoice_number)) = lower(v_ref_inv)
       and l2.kind = 'product' and l2.sku in (select le->>'sku' from jsonb_array_elements(v_lines) le where le->>'kind' = 'product');
    if v_seen is not null then v_warn := array_append(v_warn, 'reference_seen:' || v_seen); end if;
  end if;

  -- dsc-3b 판정 325 · 316: 인보이스 거울 — 인보이스-오더마다 오더 할인 % 가 있으면 그 오더의 제품 환불액에 음수 줄 하나(세금 따로 · 계정 = 그 인보이스의 order_discount 줄) · surcharge 는 기준 밖(인보이스와 같다) · Cin7 크레딧은 해당 없음
  if not v_ref then
    for v_od in
      select io.id as io_id, io.so_number, io.order_discount_pct as pct, io.rate_pct, sum((le->>'amount')::numeric) as amt
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
                                       unit_price, amount, rate_pct, tax_amount, account_id, account_code, updated_by, combo_credit_line_id, combo_qty, combo_components)
    values (v_cr.id, (e->>'line_no')::int, e->>'kind', nullif(e->>'so_invoice_line_id', '')::uuid, nullif(e->>'so_line_id', '')::uuid, nullif(e->>'product_id', '')::uuid, e->>'sku', e->>'description',
            nullif(e->>'qty_returned', '')::numeric, nullif(e->>'restock_bin_id', '')::uuid, e->>'restock_bin', e->>'not_restocked_reason', e->>'not_restocked_note',
            nullif(e->>'unit_price', '')::numeric, (e->>'amount')::numeric, nullif(e->>'rate_pct', '')::numeric, (e->>'tax_amount')::numeric, nullif(e->>'account_id', '')::uuid, e->>'account_code', v_staff,
            (v_idmap->>(e->>'combo_parent_line_no'))::uuid, nullif(e->>'combo_qty', '')::numeric, nullif(e->'combo_components', 'null'::jsonb))                   -- asm-2b2: 구성품 줄은 앞서 넣은 콤보 줄(line_no → id)에 매단다 · 콤보 줄은 includes 를 든다
    returning id into v_il_id;
    v_idmap := v_idmap || jsonb_build_object((e->>'line_no'), v_il_id);
  end loop;
  if v_restock_n > 0 then
    v_ledger := public.inv_post_credit(v_cr.id, v_on);
    v_warn := v_warn || coalesce((select array_agg(t.w) from jsonb_array_elements_text(coalesce(v_ledger->'warnings', '[]'::jsonb)) as t(w)), '{}');
  end if;

  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', v_cr.status, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code,
                            'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                            'origin', case when v_ref then jsonb_build_object('ref_invoice_number', v_ref_inv, 'ref_order_number', v_ref_ord, 'ref_invoice_date', v_ref_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src)
                                           else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'order_discount_amount', v_cr.order_discount_amount, 'freight_discount_amount', v_cr.freight_discount_amount, 'fee_amount', v_cr.fee_amount, 'surcharge_amount', v_cr.surcharge_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ inv_post_credit 재발행 — 원본 20261020201002_rls_1_ledger_layer_write_gate.sql:632 바이트 + 더한 · 바꾼 줄만 · crn-1 ═══
CREATE OR REPLACE FUNCTION public.inv_post_credit(p_credit_id uuid, p_occurred_on date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_version  constant text := 'inv_post_credit@2026-09-25.1';
  v_cr       public.so_credit%rowtype;
  v_existing int;
  v_alloc    jsonb;
  v_costs    jsonb := '{}'::jsonb;
  v_rows     int := 0;
  v_qty      numeric := 0;
  v_warn     text[] := '{}';
  k          record;
  b          record;
begin
  perform public.ims_require_write('sales', 'posted');        -- ⭐ 첫 줄 — 호출자(auth.uid())의 sales 쓰기

  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if not found then raise exception 'Credit note not found — nothing was posted to the ledger'; end if;
  if v_cr.status <> 'issued' then raise exception 'Credit note % is % — the ledger takes issued credit notes only — nothing was posted to the ledger', v_cr.credit_number, v_cr.status; end if;
  if v_cr.warehouse_name is null then raise exception 'Credit note % has no warehouse — nothing was posted to the ledger', v_cr.credit_number; end if;

  select count(*) into v_existing from public.inv_ledger l where l.doc_type = 'creditnote' and l.doc_number = v_cr.credit_number and l.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["already_posted"]'::jsonb);
  end if;
  if p_occurred_on > public.ims_today() then v_warn := array_append(v_warn, 'credited_on_in_future'); end if;

  -- restock 줄 모으기 — 판매 단위 → EA(pack_factor) · 낱개 SKU(세트는 parent) · 원 판매 오더 번호(IMS so_line → so) · crn-1 판정 602: 참조 크레딧(invoice_id null)은 되짚지 않는다 — so_line 이 없어 null → inv_layer_post_credit 이 ② 가중평균부터 · ref_order_number 는 기록만
  with a as (
    select cl.id as line_id, cl.line_no, cl.product_id, cl.sku as credited_sku, cl.qty_returned, cl.unit_price, cl.restock_bin as bin,
           coalesce(pp.sku, pr.sku) as base_sku, coalesce(pr.pack_factor, 1) as pack_factor, cl.qty_returned * coalesce(pr.pack_factor, 1) as qty_ea,
           s.so_number as origin_sale
      from public.so_credit_line cl
      join public.product pr on pr.id = cl.product_id
      left join public.product pp on pp.id = pr.parent_product_id
      left join public.so_line sl on sl.id = cl.so_line_id
      left join public.so s on s.id = sl.so_id
     where cl.credit_id = p_credit_id and cl.kind = 'product' and cl.restock_bin_id is not null
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no), '[]'::jsonb) into v_alloc from a;
  if jsonb_array_length(v_alloc) = 0 then
    return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'already_posted', false, 'existing_rows', 0, 'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["nothing_restocked"]'::jsonb);
  end if;

  -- ⭐ 레이어 먼저 — 낱개 SKU 키마다 한 번(창고 하나 · 줄 여럿은 접는다 · line_ref = 첫 줄 · 원 판매는 첫 줄의 것 — 재생성 키 (doc, sku, wh) 와 같다)
  for k in
    select t.base_sku, sum(t.qty_ea) as qty_ea, (array_agg(t.line_id::text order by t.line_no))[1] as line_ref, (array_agg(t.origin_sale order by t.line_no))[1] as origin_sale,
           count(distinct t.origin_sale) as n_origin
      from jsonb_to_recordset(v_alloc) as t(base_sku text, qty_ea numeric, line_id uuid, line_no int, origin_sale text)
     group by t.base_sku order by t.base_sku
  loop
    if k.n_origin > 1 then v_warn := array_append(v_warn, 'mixed_origin_sales:' || k.base_sku); end if;
    if k.origin_sale is null and v_cr.invoice_id is not null then v_warn := array_append(v_warn, 'origin_sale_unknown:' || k.base_sku); end if;   -- crn-1: 참조 크레딧에는 뜻이 없는 경고(되짚지 않으니까)
    v_costs := v_costs || jsonb_build_object(k.base_sku, public.inv_layer_post_credit(v_cr.credit_number, k.line_ref, k.base_sku, v_cr.warehouse_name, k.qty_ea, p_occurred_on, k.origin_sale, null));
    if (v_costs -> k.base_sku ->> 'traced_qty')::numeric < k.qty_ea then v_warn := array_append(v_warn, 'origin_sale_untraced:' || k.base_sku || ':' || ((v_costs -> k.base_sku -> 'remainder' ->> 'cost_source'))); end if;
  end loop;

  -- 원장 행 — 줄(= 칸 하나) · raw.header 는 수집 축 credit_in 과 같은 모양(order_number · credit_note_number · credit_note_date — 두 축을 같은 식으로 되짚는다 · crn-1: ref_invoice_number 열쇠) · raw.cost.remainder 가 재생성 hint
  for b in
    select * from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, credited_sku text, qty_returned numeric, unit_price numeric, bin text,
                                                   base_sku text, pack_factor numeric, qty_ea numeric, origin_sale text)
     order by line_no
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (p_occurred_on, 1, b.base_sku, v_cr.warehouse_name, b.bin, b.qty_ea, 'credit_in', 'creditnote', v_cr.credit_number, v_cr.id::text, b.line_id::text, null, 'ims',
      jsonb_build_object(
        'kind', 'credit_in', 'poster', c_version,
        'header', jsonb_build_object('order_number', b.origin_sale, 'credit_note_number', v_cr.credit_number, 'credit_note_date', p_occurred_on, 'invoice_id', v_cr.invoice_id, 'ref_invoice_number', v_cr.ref_invoice_number),
        'credit_id', v_cr.id, 'credit_line_id', b.line_id, 'line_no', b.line_no,
        'product_id', b.product_id, 'sku', b.credited_sku, 'base_sku', b.base_sku, 'pack_factor', b.pack_factor,
        'qty', b.qty_returned, 'qty_ea', b.qty_ea, 'unit_price', b.unit_price,
        'warehouse_id', v_cr.warehouse_id, 'warehouse', v_cr.warehouse_name, 'bin', b.bin,
        'customer_id', v_cr.customer_id, 'credited_on', p_occurred_on, 'issued_by', v_cr.issued_by,
        'cost', v_costs -> b.base_sku));
    v_rows := v_rows + 1;  v_qty := v_qty + b.qty_ea;
  end loop;

  return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'already_posted', false, 'existing_rows', 0,
                            'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_costs, 'poster', c_version, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Credit note % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_cr.credit_number, sqlerrm;
end;
$function$;

-- ═══ doc_data_credit 재발행 — 원본 20261019152102_doc_1b1_data.sql:282 바이트 + 더한 · 바꾼 줄만 · crn-1 ═══
CREATE OR REPLACE FUNCTION public.doc_data_credit(p_credit_id uuid, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cr   public.so_credit%rowtype;
  v_inv  public.so_invoice%rowtype;
  v_fmt  text := p_cfg->>'date_format';
  v_bill jsonb;  v_ship jsonb;  v_lines jsonb;  v_charges jsonb;  v_refunds jsonb;
  v_lines_amt numeric;  v_lines_tax numeric;  v_chg_amt numeric;  v_chg_tax numeric;  v_applied numeric;  v_ref text;
begin
  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if v_cr.id is null then raise exception 'Credit note not found'; end if;
  if v_cr.invoice_id is not null then
    select * into v_inv from public.so_invoice i where i.id = v_cr.invoice_id;
    v_bill := jsonb_build_object('name', v_inv.bill_to_name, 'line1', v_inv.bill_to_line1, 'line2', v_inv.bill_to_line2, 'city', v_inv.bill_to_city, 'state_province', v_inv.bill_to_state_province, 'postal_code', v_inv.bill_to_postal_code, 'country', v_inv.bill_to_country);
    select jsonb_build_object('company', o.ship_to_company, 'contact', o.ship_to_contact, 'phone', o.ship_to_phone, 'line1', o.ship_to_line1, 'line2', o.ship_to_line2, 'city', o.ship_to_city, 'state_province', o.ship_to_state_province, 'postal_code', o.ship_to_postal_code, 'country', o.ship_to_country)
      into v_ship
    from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;                                                   -- 여러 오더면 첫 오더(so_number 순)의 배송지
    select string_agg(s.ref, ', ' order by o.so_number) into v_ref from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id and s.ref is not null and s.ref <> '';
  else
    select jsonb_build_object('name', c.name, 'line1', a.line1, 'line2', a.line2, 'city', a.city, 'state_province', a.state_province, 'postal_code', a.postal_code, 'country', a.country) into v_bill
    from public.customer c left join public.customer_address a on a.customer_id = c.id and a.is_active and a.type = 'Billing' and a.is_default_for_type where c.id = v_cr.customer_id;
    select jsonb_build_object('company', c.name, 'contact', '', 'phone', '', 'line1', a.line1, 'line2', a.line2, 'city', a.city, 'state_province', a.state_province, 'postal_code', a.postal_code, 'country', a.country) into v_ship
    from public.customer c left join public.customer_address a on a.customer_id = c.id and a.is_active and a.type = 'Shipping' and a.is_default_for_type where c.id = v_cr.customer_id;
  end if;
  -- 제품 줄(콤보 구성품 줄은 뺀다 — 손님 문서 · amount 0) · 그 밖(freight · tax · other · surcharge · order_discount · freight_discount)은 charges · restocking_fee 는 totals
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'upc', public.doc_upc(x.product_id), 'sku', coalesce(x.sku, ''), 'description', coalesce(x.description, ''), 'comment', '', 'unit', coalesce(x.unit, ''),
                                               'qty', public.doc_fmt_qty(x.qty_returned), 'list_price', '', 'discount_pct', '', 'unit_price', public.doc_fmt_money(x.unit_price), 'net_unit_price', '',
                                               'amount', public.doc_fmt_money(x.amount), 'tax_amount', public.doc_fmt_money(x.tax_amount), 'is_free', false, 'no_price', false) order by x.no), '[]'::jsonb),
         coalesce(sum(x.amount), 0), coalesce(sum(x.tax_amount), 0)
    into v_lines, v_lines_amt, v_lines_tax
  from (select l.*, coalesce(sl.unit, p.uom_name) as unit, row_number() over (order by l.line_no) as no
        from public.so_credit_line l left join public.so_line sl on sl.id = l.so_line_id left join public.product p on p.id = l.product_id
        where l.credit_id = v_cr.id and l.kind = 'product' and l.combo_credit_line_id is null) x;
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'so_number', '', 'code', coalesce(x.account_code, ''), 'description', coalesce(x.description, ''), 'comment', '', 'qty', public.doc_fmt_qty(x.qty_returned),
                                               'unit_price', public.doc_fmt_money(x.unit_price), 'discount_pct', '', 'amount', public.doc_fmt_money(x.amount), 'tax_amount', public.doc_fmt_money(x.tax_amount)) order by x.no), '[]'::jsonb),
         coalesce(sum(x.amount), 0), coalesce(sum(x.tax_amount), 0)
    into v_charges, v_chg_amt, v_chg_tax
  from (select l.*, row_number() over (order by l.line_no) as no from public.so_credit_line l where l.credit_id = v_cr.id and l.kind not in ('product', 'restocking_fee')) x;
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'reference', coalesce(x.reference, ''), 'date', public.doc_fmt_date(x.paid_on, v_fmt), 'method', public.doc_method_label(x.method), 'amount', public.doc_fmt_money(x.amount)) order by x.no), '[]'::jsonb)
    into v_refunds
  from (select a.amount, p.reference, p.paid_on, p.method, row_number() over (order by p.paid_on, p.created_at, a.created_at) as no
        from public.so_credit_alloc a join public.so_payment p on p.id = a.refund_payment_id
        where a.credit_id = v_cr.id and a.refund_payment_id is not null and a.voided_at is null and p.status = 'active') x;
  select coalesce(sum(a.amount), 0) into v_applied from public.so_credit_alloc a where a.credit_id = v_cr.id and a.invoice_id is not null and a.voided_at is null;
  return jsonb_build_object(
    'credit', jsonb_build_object('number', v_cr.credit_number, 'date', public.doc_fmt_date(v_cr.issued_on, v_fmt), 'invoice_number', coalesce(v_inv.invoice_number, v_cr.ref_invoice_number, ''),   -- crn-1 판정 609: 참조 번호(옛 이름은 판정 609 앞의 것)
                                 'reference', coalesce(v_ref, ''), 'reason', coalesce(v_cr.reason, ''), 'currency', coalesce(v_cr.currency_code, ''), 'memo', coalesce(v_cr.note, '')),
    'ship_to', jsonb_build_object('company', coalesce(v_ship->>'company', ''), 'contact', coalesce(v_ship->>'contact', ''), 'phone', coalesce(v_ship->>'phone', ''), 'line1', coalesce(v_ship->>'line1', ''), 'line2', coalesce(v_ship->>'line2', ''),
                                  'city', coalesce(v_ship->>'city', ''), 'state_province', coalesce(v_ship->>'state_province', ''), 'postal_code', coalesce(v_ship->>'postal_code', ''), 'country', coalesce(v_ship->>'country', '')),
    'lines', v_lines, 'charges', v_charges, 'refunds', v_refunds,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money(v_lines_amt), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money(v_lines_amt + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'restocking_fee', public.doc_fmt_money(v_cr.fee_amount), 'before_tax', public.doc_fmt_money(v_cr.total - v_cr.tax_amount), 'tax', public.doc_fmt_money(v_cr.tax_amount), 'total', public.doc_fmt_money(v_cr.total),
                                 'applied', public.doc_fmt_money(v_applied), 'remaining', public.doc_fmt_money(public.so_credit_remaining(v_cr.id))))
    || public.doc_data_common('credit_note', p_cfg, coalesce(v_bill, '{}'::jsonb) || public.doc_contact(v_cr.customer_id));
end;
$function$;

-- ═══ 착지 — 칸 셋 · CHECK · 뷰 · 재발행 셋 md5 · 옛 이름 0 · 다른 창구 무변 ═══
do $$
declare
  v_bad text := '';
  v_n   int;
  b     record;
  v_exp jsonb := '{"so_credit_issue": "3450b7478a054d6d4f7e799a066bec2f", "inv_post_credit": "d0866e4155cb4911b1dad6c8a4cf355d", "doc_data_credit": "afecf6fe5dd609583a4f1b4df2826f96"}'::jsonb;
  k     text;
begin
  select * into b from crn1_before;
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and table_name = 'so_credit' and column_name in ('ref_invoice_number', 'ref_order_number', 'ref_invoice_date');
  if v_n <> 3 then v_bad := v_bad || format(' ref_cols_%s_of_3', v_n); end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so_credit' and column_name like 'cin7%') then v_bad := v_bad || ' cin7_cols_left'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so_credit'::regclass and conname = 'so_credit_origin_ck') !~ 'ref_invoice_number' then v_bad := v_bad || ' origin_ck'; end if;
  if (select string_agg(conname || ':' || pg_get_constraintdef(oid), ' ' order by conname) from pg_constraint where conrelid = 'public.so_credit'::regclass and contype = 'c' and conname <> 'so_credit_origin_ck') is distinct from b.other_checks then v_bad := v_bad || ' other_checks'; end if;
  if (select count(*) from public.so_credit) <> b.n_credits or (select count(*) from public.so_credit where ref_invoice_number is not null or ref_order_number is not null or ref_invoice_date is not null) <> b.n_ref_rows then v_bad := v_bad || ' rows'; end if;
  if (select string_agg(attname, ',' order by attnum) from pg_attribute where attrelid = 'public.so_credit_list'::regclass and attnum > 0 and not attisdropped)
     is distinct from replace(replace(b.view_cols, 'cin7_invoice_number', 'ref_invoice_number'), 'cin7_order_number', 'ref_order_number') then v_bad := v_bad || ' view_cols'; end if;
  if (select coalesce(c.relacl::text, '-') || '|' || coalesce(c.reloptions::text, '-') from pg_class c where c.oid = 'public.so_credit_list'::regclass) is distinct from split_part(b.view_meta, '|', 1) || '|' || split_part(b.view_meta, '|', 2) then v_bad := v_bad || ' view_acl_or_options'; end if;
  if pg_get_viewdef('public.so_credit_list'::regclass) ~ 'cin7' then v_bad := v_bad || ' view_cin7'; end if;
  for k in select jsonb_object_keys(v_exp) loop
    select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = k;
    if v_n <> 1 then v_bad := v_bad || format(' %s_overloads_%s', k, v_n); end if;
    if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = k) is distinct from (v_exp->>k) then v_bad := v_bad || ' ' || k || '_body'; end if;
  end loop;
  if (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_credit_issue', 'inv_post_credit', 'doc_data_credit')) is distinct from b.acls then v_bad := v_bad || ' reissued_acls'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('so_credit_prepare', 'so_credit_cancel', 'so_credit_detail', 'so_credit_attach', 'so_credit_detach', 'so_credit_alloc_add', 'so_credit_remaining', 'so_customer_balance', 'inv_layer_post_credit', 'inv_layer_apply_credit', 'so_detail', 'doc_data', 'doc_data_common')) is distinct from b.others then v_bad := v_bad || ' others_changed'; end if;
  -- 옛 이름 전수 0 — 함수 본문 · 뷰(원가 · 수집기의 source = 'cin7' · product_bom_set 의 v_cin7_n 은 다른 뜻이라 세 칸 이름 · 변수 v_cin7* · 「Cin7 credit/product」 글만 센다)
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc ~ 'cin7_invoice_number|cin7_order_number|cin7_invoice_date|v_cin7(_inv|_ord|_date)?\M|[Cc]in7 (credit|product)';
  if v_n <> 0 then v_bad := v_bad || format(' old_tokens_in_%s_functions', v_n); end if;
  select count(*) into v_n from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'v' and pg_get_viewdef(c.oid) ~ 'cin7_invoice_number|cin7_order_number|cin7_invoice_date';
  if v_n <> 0 then v_bad := v_bad || format(' old_tokens_in_%s_views', v_n); end if;
  if v_bad <> '' then raise exception 'crn-1 landing check failed:%', v_bad; end if;
end $$;
drop table crn1_before;
