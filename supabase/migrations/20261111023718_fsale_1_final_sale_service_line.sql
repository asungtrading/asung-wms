-- supabase/migrations/20261111023718_fsale_1_final_sale_service_line.sql — fsale-1: 바코드 없는 떨이 물건을 서비스 줄 FINAL-SALE 로(판정 1161 · 1162 · 2026-11-10 · 지시서 ~/asung/prompts/fsale-1.md · 조사 fsale-0)
-- 요청(Caleb 11-10): 「없애는 제품들을 위해 그만한 시간과 노력을 들일 필요가 있나 … 손쉽게 판매할 수 있는 방법」 · 「final sale non inventory item하나만 만들어놓고, 가격은 그때그때 넣어서 팔았다」
-- 판정 1161(정정): 서비스 목록(ref_service)의 FINAL-SALE 한 줄 · 비용 줄(so_charge qty × unit_price) · 원가 0 · 매출만 — 재고 · 예약 · 픽 · 원장 · 원가 레이어 · Shopify 무접촉(판정 590 의 결)
-- 판정 1162 여섯: ① 서비스 한 줄 ② counter · POS · service 오더만(warehouse 거부) ③ 단가는 매번 손으로 · 0 원 금지 ④ 떨이 줄만 있는 counter · POS 오더도 확정 ⑤ 크레딧 = 「Final sale — Issue anyway?」 경고(640 과 같은 열쇠 final_sale:) ⑥ 매출 계정 = 상품 매출과 같은 _98_ Sales Account
-- 새 것: ref_service 칸 둘 — price_each_time(③) · final_sale(② · ④ · ⑤ · 보고) · 기준 데이터 한 줄 「FINAL SALE ITEM - No Return or Exchange」(단가 0 · _98_ · 두 칸 true · 이미 있으면 넣지 않는다)
-- 재발행 일곱(몸 = DB prosrc 원본 2026-11-10 밤 + 더한 줄 · 시그니처 · definer/invoker · volatility · search_path · acl 그대로 · create or replace · drop 없음):
--   so_charge_set(② ③ + 줄 할인 거부 · 서비스 떼기 거부 · 늘 price_set_by) · so_confirm_precheck(④) · so_pos_complete(④ 이견 1 — 확정만 풀면 Finish 가 「nothing to ship」: 상품 줄 0 갈래 = 픽 · so_ship · 원장 없이 나감 표시 → 발행)
--   so_credit_issue(⑤ charge 갈래 경고) · so_credit_prepare(charge 줄 final_sale) · mcp_sales(other.final_sale) · so_detail(charges[] 열쇠 final_sale · price_each_time)
-- 무접촉: so_confirm · so_pos_confirm · so_ship · so_invoice_issue · so_charge_gate · so_service_confirm · so_service_invoice · qbo_invoice_body(service_id → qbo_link 'service' — Item 8794 짝은 사람이 matching 화면에서) · 판 · 화면 · EF
-- 검증 supabase/tests/fsale_1_check.sql(begin → rollback · 가짜 행만 · 번호 함수는 시험 안에서 가짜로 덮는다) · 적용은 Caleb: psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f <이 파일> && supabase migration repair --status applied … · supabase db push 금지
-- ⚠️ ref_service 는 Settings 화면이 표에 직접 쓴다(RLS master) — 새 칸 둘도 master 가 REST 로 바꿀 수 있다(막지 않았다 · 화면은 그 칸을 안 보낸다)

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

-- ═══ 앞 검사 — 재발행 원본이 2026-11-10 밤에 읽은 DB prosrc 그대로인가 · 칸이 아직 없는가 · 매출 계정 _98_ 이 있는가 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric, numeric, numeric, uuid)'::regprocedure) <> 'ea448cecccf9427a360a6f4748a64426' then v_bad := v_bad || ' so_charge_set'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_confirm_precheck(public.so)'::regprocedure) <> 'b6ad6212447c0a678e9ab15e8ace0cb7' then v_bad := v_bad || ' so_confirm_precheck'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_pos_complete(uuid, jsonb, uuid, boolean)'::regprocedure) <> '0b4e2e4b81ca44d7174dab51e2097cde' then v_bad := v_bad || ' so_pos_complete'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_credit_issue(jsonb, boolean)'::regprocedure) <> '3c2029428b12d47cf7635b4198d44fa0' then v_bad := v_bad || ' so_credit_issue'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_credit_prepare(uuid)'::regprocedure) <> '12d9433453b0c06ba19a04776a885936' then v_bad := v_bad || ' so_credit_prepare'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.mcp_sales(text, text, text, text, text, text, text, integer, integer)'::regprocedure) <> '90347c6294eab4fde66592b0e911378d' then v_bad := v_bad || ' mcp_sales'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_detail(uuid)'::regprocedure) <> '3f70f44258a647a2af9a4477847bf925' then v_bad := v_bad || ' so_detail'; end if;
  if exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'ref_service' and c.column_name in ('price_each_time', 'final_sale')) then v_bad := v_bad || ' ref_service_columns_exist'; end if;
  if not exists (select 1 from public.ref_account a where a.code = '_98_' and a.name = 'Sales Account' and a.is_active) then v_bad := v_bad || ' account_98_missing'; end if;
  if v_bad <> '' then raise exception 'fsale-1 pre-check failed (functions changed since the migration was written — rebuild it from the current prosrc · or the columns / account are not as expected):%', v_bad; end if;
end $$;

-- ═══ ① ref_service 칸 둘(판정 1162-2 · 3 · 5 · 뜻별로 나눈다 — 「매번 단가」 만 필요한 서비스가 생길 수 있다) ═══
alter table public.ref_service
  add column price_each_time boolean not null default false,
  add column final_sale      boolean not null default false;
comment on column public.ref_service.price_each_time is 'fsale-1(판정 1162-3) — 목록 단가를 쓰지 않는다: 줄마다 단가를 손으로 넣어야 하고 0 원 · 줄 할인은 거부(so_charge_set) · 늘 so_charge.price_set_by 가 남는다';
comment on column public.ref_service.final_sale is 'fsale-1(판정 1161 · 1162-2 · 4 · 5) — 실물을 재고 없이 파는 떨이 줄(FINAL-SALE): counter · pos · service 오더만(warehouse 거부) · 이 줄만 있는 pos · counter 오더도 확정 · Finish · 크레딧 때 경고 final_sale:<이름> · mcp_sales other.final_sale';

-- ═══ ② 기준 데이터 한 줄 — FINAL-SALE(판정 1161 · 1162-6 · 멱등: 같은 이름이나 final_sale 줄이 이미 있으면 넣지 않는다) ═══
insert into public.ref_service (name, unit_price, account_id, price_each_time, final_sale, note)
select 'FINAL SALE ITEM - No Return or Exchange', 0, a.id, true, true, 'FINAL-SALE — old stock without a barcode, sold as is: type the price for each sale · counter, POS and service orders only · no return or exchange (fsale-1)'
  from public.ref_account a
 where a.code = '_98_'
   and not exists (select 1 from public.ref_service s where s.final_sale or lower(s.name) = lower('FINAL SALE ITEM - No Return or Exchange'));

-- ═══ 재발행 1/7 — so_charge_set(DB prosrc 원본 md5 ea448cec + 더한 줄 · fsale-1(판정 1162-2 · 3): final_sale 서비스는 counter · pos · service 오더만 · price_each_time 서비스는 단가를 손으로(> 0) · 할인 거부 · 늘 price_set_by · 그 줄의 서비스 떼기 · 바꾸기 거부) ═══
CREATE OR REPLACE FUNCTION public.so_charge_set(p_so_id uuid, p_name text, p_amount numeric, p_charge_id uuid DEFAULT NULL::uuid, p_description text DEFAULT NULL::text, p_tax_rule text DEFAULT NULL::text, p_account_id uuid DEFAULT NULL::uuid, p_discount_pct numeric DEFAULT NULL::numeric, p_discount_amount numeric DEFAULT NULL::numeric, p_qty numeric DEFAULT NULL::numeric, p_unit_price numeric DEFAULT NULL::numeric, p_service_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  v_name   text;
  v_acct   public.ref_account%rowtype;
  v_ch     public.so_charge%rowtype;
  v_next   int;
  v_warn   text[] := '{}';
  v_n      int;
  v_svc    public.ref_service%rowtype;                                                                           -- svc-1a(판정 590 · 596): 서비스 줄
  v_qmode  boolean := p_qty is not null or p_unit_price is not null or p_service_id is not null;                  -- svc-1a: 수량 · 단가 · 서비스 중 하나라도 오면 「수량 × 단가」 줄
  v_old    public.so_charge%rowtype;
  v_osvc   public.ref_service%rowtype;                                                                           -- fsale-1(판정 1162): 고치는 줄이 지금 든 서비스
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_charge_gate(p_so_id, 'saved');                                                                  -- ch-1 판정 539 · 540 · 549: draft 또는 packed(master 도 · aone 거부) · 오더 행 잠금
  -- ═══ svc-1a(판정 590 · 596) — 수량 × 단가 줄: 서비스 목록 단가 · 이름 · 계정을 채우고 금액은 창구가 짓는다 · 아래 옛 검사(이름 · 금액 · 할인 · 세금 · 계정)는 그대로 돈다 ═══
  if p_charge_id is not null and not v_qmode then
    select * into v_old from public.so_charge where id = p_charge_id and so_id = p_so_id;
    if found and v_old.qty is not null then
      raise exception 'Charge % is a quantity × unit price line — send qty and unit_price (or service_id) to change it — nothing was saved', v_old.name;
    end if;
  end if;
  if p_charge_id is not null then                                                                                  -- fsale-1(판정 1162-2 · 3): 떨이 · 손 단가 서비스 줄은 서비스를 떼거나 바꿔 규칙을 벗어나지 못한다(지우고 새로 넣는다)
    select s.* into v_osvc from public.so_charge c join public.ref_service s on s.id = c.service_id where c.id = p_charge_id and c.so_id = p_so_id;
    if found and (v_osvc.final_sale or v_osvc.price_each_time) and p_service_id is distinct from v_osvc.id then
      raise exception '% cannot be turned into another kind of line — remove the line and add a new one — nothing was saved', v_osvc.name;
    end if;
  end if;
  if v_qmode then
    if p_service_id is not null then
      select * into v_svc from public.ref_service where id = p_service_id;
      if not found then raise exception 'Service not found — nothing was saved'; end if;
      if not v_svc.is_active then raise exception 'Service % is switched off — pick an active service — nothing was saved', v_svc.name; end if;
      if v_svc.final_sale and v_so.channel not in ('counter', 'pos', 'service') then                                    -- fsale-1(판정 1162-2): 떨이 줄은 counter · POS · service 오더만 — WMS 화면이 비용 줄을 안 보여 피커가 모른다
        raise exception '% is sold over the counter — order % is a % order and the warehouse does not see this line: put it on a counter, POS or service order — nothing was saved', v_svc.name, v_so.so_number, v_so.channel;
      end if;
      if v_svc.price_each_time then                                                                                 -- fsale-1(판정 1162-3): 단가는 팔 때마다 손으로 · 0 원 금지 · 줄 할인으로 0 원 만드는 샛길도(낮춘 값을 단가로)
        if p_unit_price is null or p_unit_price <= 0 then
          raise exception '% has no list price — type the price for this sale (more than 0) — nothing was saved', v_svc.name;
        end if;
        if p_discount_pct is not null or p_discount_amount is not null then
          raise exception '% takes no discount — type the reduced price as the unit price instead — nothing was saved', v_svc.name;
        end if;
      end if;
      p_unit_price := coalesce(p_unit_price, v_svc.unit_price);
      p_name       := coalesce(nullif(trim(p_name), ''), v_svc.name);
      p_account_id := coalesce(p_account_id, v_svc.account_id);
    end if;
    if p_qty is null or p_unit_price is null then
      raise exception 'A quantity × unit price line needs both qty and unit_price (or a service for the price) — nothing was saved';
    end if;
    if p_qty <= 0 then raise exception 'Quantity must be more than 0 — nothing was saved'; end if;
    if p_unit_price < 0 then raise exception 'A unit price cannot be negative — use a credit note — nothing was saved'; end if;
    if p_amount is not null and p_amount <> round(p_qty * p_unit_price, 2) then
      raise exception 'Amount % does not match % × % — leave the amount out, it is worked out from quantity and unit price — nothing was saved', p_amount, trim_scale(p_qty), trim_scale(p_unit_price);
    end if;
    p_amount := round(p_qty * p_unit_price, 2);
  end if;

  v_name := nullif(trim(p_name), '');
  if v_name is null then
    raise exception 'A charge needs a name — nothing was saved';
  end if;
  if p_amount is null then
    raise exception 'A charge needs an amount — nothing was saved';
  end if;
  if p_amount < 0 then                                          -- ①c 판정(Caleb 2026-09-23) — 돌려줄 돈은 크레딧 노트(8-g) · CHECK so_charge_amount_ck 가 마지막 문
    raise exception 'A charge cannot be negative — use a credit note — nothing was saved';
  end if;
  perform public.so_charge_discount_check(p_amount, p_discount_pct, p_discount_amount);                              -- fr-1 판정 356: 한 곳의 검사(둘 다 · 0 · 100 초과 · 운임보다 큰 금액)
  if nullif(trim(p_tax_rule), '') is not null and nullif(trim(p_tax_rule), '') is distinct from v_so.tax_rule then   -- 세금 ② · 판정 8·9 — 운임 줄만 따로 바꾸는 길은 없다(조용히 무시하지 않고 거부)
    raise exception 'Freight and charges follow the order tax rule (%) — change it on the order, not on the charge — nothing was saved', coalesce(v_so.tax_rule, 'none yet');
  end if;

  if p_account_id is not null then
    select * into v_acct from public.ref_account where id = p_account_id;
    if not found then
      raise exception 'Account not found — nothing was saved';
    end if;
  end if;

  if p_charge_id is null then
    if p_account_id is null then
      select * into v_acct from public.ref_account where code = '_99_';          -- 기본 Freight Sales · 없으면 비우고 알린다(짐작 값을 박지 않는다)
      if not found then v_warn := array_append(v_warn, 'charge_account_unset'); end if;
    end if;
    select coalesce(max(line_no), 0) + 1 into v_next from public.so_charge where so_id = p_so_id;
    insert into public.so_charge (so_id, line_no, name, description, amount, tax_rule, account_id, account_code, updated_by, discount_pct, discount_amount)
    values (p_so_id, v_next, v_name, nullif(trim(p_description), ''), p_amount, v_so.tax_rule, v_acct.id, v_acct.code, v_staff, p_discount_pct, p_discount_amount)   -- 세금 ②: 오더 규칙을 기록 · fr-1 할인 칸 둘
    returning * into v_ch;
    if v_qmode then                                                                                                  -- svc-1a: 같은 문장 안에서 금액과 짝이 맞게(금액은 위에서 qty × 단가)
      update public.so_charge set qty = p_qty, unit_price = p_unit_price, service_id = p_service_id,
             price_set_by = case when p_service_id is not null and p_unit_price = v_svc.unit_price and not v_svc.price_each_time then null else v_staff end,
             price_set_at = case when p_service_id is not null and p_unit_price = v_svc.unit_price and not v_svc.price_each_time then null else now() end
       where id = v_ch.id returning * into v_ch;
    end if;
    return jsonb_build_object('action', 'added', 'so_number', v_so.so_number, 'status', v_so.status, 'charge', to_jsonb(v_ch) || jsonb_build_object('discount', public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount), 'net', v_ch.amount - public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount)), 'warnings', to_jsonb(v_warn));   -- fr-1: 할인액 · 순 운임
  end if;

  select * into v_ch from public.so_charge where id = p_charge_id and so_id = p_so_id;
  if not found then
    raise exception 'Charge not found on order % — nothing was saved', v_so.so_number;
  end if;
  if v_qmode then                                                                                                    -- svc-1a: 수량 · 단가 · 금액을 한 문장으로 먼저(아래 옛 update 는 같은 금액을 다시 쓴다)
    update public.so_charge c set qty = p_qty, unit_price = p_unit_price, amount = p_amount, service_id = p_service_id,
           price_set_by = case when p_service_id is not null and p_unit_price = v_svc.unit_price and not v_svc.price_each_time then null
                               when c.unit_price is not distinct from p_unit_price and c.service_id is not distinct from p_service_id then c.price_set_by else v_staff end,
           price_set_at = case when p_service_id is not null and p_unit_price = v_svc.unit_price and not v_svc.price_each_time then null
                               when c.unit_price is not distinct from p_unit_price and c.service_id is not distinct from p_service_id then c.price_set_at else now() end
     where c.id = p_charge_id;
  end if;
  update public.so_charge c set
    name         = v_name,
    description  = nullif(trim(p_description), ''),
    amount       = p_amount,
    discount_pct = p_discount_pct,  discount_amount = p_discount_amount,                               -- fr-1 판정 353: 고치기는 전체 모양(이름 · 설명 · 금액처럼) — 둘 다 null 이면 할인을 지운다
    tax_rule     = v_so.tax_rule,                             -- 세금 ②: 오더 규칙을 기록
    account_id   = case when p_account_id is not null then v_acct.id   else c.account_id end,
    account_code = case when p_account_id is not null then v_acct.code else c.account_code end,
    updated_by   = v_staff
  where c.id = p_charge_id
  returning * into v_ch;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Charge was not saved — it may have been removed by someone else just now — nothing was saved';
  end if;
  return jsonb_build_object('action', 'updated', 'so_number', v_so.so_number, 'status', v_so.status, 'charge', to_jsonb(v_ch) || jsonb_build_object('discount', public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount), 'net', v_ch.amount - public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount)), 'warnings', to_jsonb(v_warn));   -- fr-1
end;
$function$;

-- ═══ 재발행 2/7 — so_confirm_precheck(DB prosrc 원본 md5 b6ad6212 + 더한 줄 · fsale-1(판정 1162-4): 상품 줄 0 이어도 final_sale 서비스 줄이 있는 pos · counter 오더는 지나간다) ═══
CREATE OR REPLACE FUNCTION public.so_confirm_precheck(p_so so)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c        public.customer%rowtype;
  v_wh     public.ref_warehouse%rowtype;
  v_bad    text;
  v_n      int;
begin
  -- R6 막는 조건 — 손님 · 창고 · 줄
  select * into c from public.customer where id = p_so.customer_id;
  if not found or not c.is_active then
    raise exception 'Customer % is inactive — reactivate it first — nothing was saved', coalesce(c.name, '?');
  end if;
  if p_so.location_id is null then
    raise exception 'Order % has no warehouse — set one before confirming — nothing was saved', p_so.so_number;
  end if;
  select * into v_wh from public.ref_warehouse where id = p_so.location_id;
  if not found or not v_wh.is_active then                       -- IN_TRANSIT 은 is_active=false 로 들어 있어 여기서 걸린다(이견 11)
    raise exception 'Warehouse % is inactive — pick an active warehouse — nothing was saved', coalesce(v_wh.name, '?');
  end if;
  select count(*) into v_n from public.so_line where so_id = p_so.id;
  if v_n = 0 and not (p_so.channel in ('pos', 'counter') and exists (select 1 from public.so_charge fc join public.ref_service fs on fs.id = fc.service_id where fc.so_id = p_so.id and fs.final_sale)) then   -- fsale-1(판정 1162-4): 떨이 줄(final_sale 서비스)만 있는 counter · POS 오더는 지나간다 · 그 밖은 그대로
    raise exception 'Order % has no lines — nothing was saved', p_so.so_number;
  end if;
  select string_agg(l.sku, ', ' order by l.line_no) into v_bad from public.so_line l where l.so_id = p_so.id and l.unit_price is null;
  if v_bad is not null then
    raise exception 'Order % has lines without a price (%) — give them a price first — nothing was saved', p_so.so_number, v_bad;
  end if;
  select string_agg(l.sku, ', ' order by l.line_no) into v_bad
  from public.so_line l join public.product p on p.id = l.product_id where l.so_id = p_so.id and not p.is_active;
  if v_bad is not null then
    raise exception 'Order % has inactive products (%) — remove them first — nothing was saved', p_so.so_number, v_bad;
  end if;
  if p_so.tax_rule_id is null then                              -- 세금 ② R6 — 세금을 모르면 인보이스를 낼 수 없다(가격 없는 줄과 같은 이유) · 배송지 주를 채우거나 tax_rule 을 고른다
    raise exception 'Order % has no tax rule — set the ship-to province (or pick a tax rule) first — nothing was saved', p_so.so_number;
  end if;
end;
$function$;

-- ═══ 재발행 3/7 — so_pos_complete(DB prosrc 원본 md5 0b4e2e4b + 더한 줄 · fsale-1(판정 1162-4): 상품 줄 0 + final_sale 서비스 줄 — 픽 · so_ship · 원장 없이 confirmed → shipped → 발행(ship.no_goods true)) ═══
CREATE OR REPLACE FUNCTION public.so_pos_complete(p_so_id uuid, p_picks jsonb, p_staff uuid, p_commit boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_so       public.so%rowtype;
  v_plan     jsonb;
  v_picks    jsonb;
  v_prev     jsonb;
  v_total    numeric;
  v_left     numeric;
  v_dep      numeric := 0;  v_cred numeric := 0;  v_bal numeric := 0;
  v_recv     numeric;  v_owed numeric;  v_res_other numeric;  v_avail numeric;
  v_cust     uuid;
  v_take     numeric;
  v_dep_map  jsonb := '{}'::jsonb;                              -- payment_id → ① 에서 쓴 금액(③ 의 예약 몫 계산)
  pay        record;
  v_est      jsonb;
  v_ship     jsonb;  v_iss jsonb;
  v_inv_id   uuid;
  v_warn     text[] := '{}';
  v_tw       text[];
  v_goods    boolean;                                           -- fsale-1(판정 1162-4): 상품 줄이 있나 — 없으면 픽 · 출고 · 원장 없이 나감 표시 → 발행(so_service_invoice 와 같은 꼴)
  v_n        int;
begin
  if p_staff is null then raise exception 'so_pos_complete needs the acting staff id — nothing was saved'; end if;
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel not in ('pos', 'counter') then raise exception 'Order % is a % order — finish it with so_finalize — nothing was saved', v_so.so_number, v_so.channel; end if;
  if v_so.status <> 'confirmed' then raise exception 'Order % is % — only a confirmed % order can be finished — nothing was saved', v_so.so_number, v_so.status, v_so.channel; end if;

  -- 칸 계획(판정 1·2·4) — 준 픽이 없으면 계획 그대로 · counter 가 준 픽은 so_ship 이 검사한다(줄·칸·수량)
  v_goods := exists (select 1 from public.so_line l where l.so_id = p_so_id);
  if not v_goods and not exists (select 1 from public.so_charge fc join public.ref_service fs on fs.id = fc.service_id where fc.so_id = p_so_id and fs.final_sale) then                                -- fsale-1: 확정 문(so_confirm_precheck)과 같은 조건 — 떨이 줄도 없으면 옛 거부 그대로
    raise exception 'Order % has nothing to ship — nothing was saved', v_so.so_number;
  end if;
  if v_goods then                                                                                                  -- fsale-1: 아래 넷은 옛 줄 그대로(들여쓰기 무변)
  v_plan := public.so_pick_plan(p_so_id);
  v_picks := coalesce(nullif(p_picks, 'null'::jsonb), v_plan->'picks');
  if v_picks is null or jsonb_typeof(v_picks) <> 'array' or jsonb_array_length(v_picks) = 0 then
    raise exception 'Order % has nothing to ship — nothing was saved', v_so.so_number;
  end if;
  select array_agg(t.w) into v_tw from jsonb_array_elements_text(coalesce(v_plan->'warnings', '[]'::jsonb)) as t(w);
  v_warn := v_warn || coalesce(v_tw, '{}');
  else                                                                                                             -- fsale-1: 떨이 줄만 — 칸 계획 · 픽 없음(화면이 읽는 열쇠는 빈 값으로)
    v_plan := jsonb_build_object('picks', '[]'::jsonb, 'lines', '[]'::jsonb, 'short_ea_total', 0, 'warnings', '[]'::jsonb);
    v_picks := '[]'::jsonb;
  end if;

  -- 미리 보기 금액(판정 5 · 누르기 전에 받은 금액·미수) — 발행 ①②③ 과 같은 순서를 읽기로
  v_prev := public.so_tax_preview(p_so_id, public.ims_today(), null, 'ordered');
  if v_prev->'totals'->>'tax' is null then raise exception 'Order % has no tax rule for its ship-to address — pick a tax rule on the order — nothing was saved', v_so.so_number; end if;
  v_total := (v_prev->'totals'->>'total')::numeric;
  v_cust := coalesce(v_so.bill_to_customer_id, v_so.customer_id);
  select b.received, b.owed_credit into v_recv, v_owed from public.so_customer_balance(v_cust) b where b.currency_id = v_so.currency_id;
  v_recv := coalesce(v_recv, 0);  v_owed := coalesce(v_owed, 0);
  v_left := v_total;
  for pay in
    select p.id, public.so_payment_remaining(p.id) as remaining
      from public.so_payment p
     where p.customer_id = v_cust and p.currency_id = v_so.currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o where o.payment_id = p.id and o.so_id = p_so_id)
     order by p.paid_on, p.created_at, p.id
  loop
    exit when v_left <= 0;
    if pay.remaining <= 0 then continue; end if;
    v_take := least(pay.remaining, v_left, v_recv);
    if v_take <= 0 then continue; end if;
    v_dep := v_dep + v_take;  v_left := v_left - v_take;  v_recv := v_recv - v_take;
    v_dep_map := jsonb_set(v_dep_map, array[pay.id::text], to_jsonb(v_take));
  end loop;
  if v_left > 0 then
    v_cred := least(v_left, greatest(v_owed, 0));  v_left := v_left - v_cred;
  end if;
  if v_left > 0 then
    -- 발행 뒤 이 오더는 fulfilled 라 이 오더만 대상인 선결제의 예약은 풀린다 — 다른 열린 오더(살아 있는 인보이스 없음)를 대상으로 한 선결제의 남은 몫만 예약으로 남는다
    select coalesce(sum(public.so_payment_remaining(p.id) - coalesce((v_dep_map->>(p.id::text))::numeric, 0)), 0)
      into v_res_other
      from public.so_payment p
     where p.customer_id = v_cust and p.currency_id = v_so.currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o join public.so s on s.id = o.so_id
                    where o.payment_id = p.id and s.id <> p_so_id and s.status not in ('fulfilled', 'cancelled')
                      and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id));
    v_avail := greatest(v_recv - v_res_other, 0);
    v_bal := least(v_left, v_avail);  v_left := v_left - v_bal;
  end if;
  v_est := jsonb_build_object('total', v_total, 'deposit', v_dep, 'credit', v_cred, 'balance', v_bal, 'amount_due', v_total - v_dep - v_cred - v_bal, 'remaining', v_left,
                              'received_before', (select b.received from public.so_customer_balance(v_cust) b where b.currency_id = v_so.currency_id));

  if not p_commit then
    return jsonb_build_object('committed', false, 'so_id', v_so.id, 'so_number', v_so.so_number, 'channel', v_so.channel, 'picks', v_picks, 'plan', v_plan->'lines',
                              'short_ea_total', v_plan->'short_ea_total', 'estimate', v_est, 'tax', v_prev->'totals', 'warnings', to_jsonb(v_warn));
  end if;

  -- 실행 — 출고(pos·counter 는 confirmed→shipped · 목표 아래 픽은 so_ship 이 거부) → 발행 한 장(발행일 오늘 · 발행 순간 fulfilled · 자동 붙이기 ①②③)
  if v_goods then                                                                                                  -- fsale-1: 옛 줄 셋 그대로
  v_ship := public.so_ship(p_so_id, v_picks, p_staff, null);
  select array_agg(t.w) into v_tw from jsonb_array_elements_text(coalesce(v_ship->'warnings', '[]'::jsonb)) as t(w);
  v_warn := v_warn || coalesce(v_tw, '{}');
  else                                                                                                             -- fsale-1(판정 1162-4): 상품 줄 0 — 나감 표시만(confirmed → shipped · 문지기 pos · counter 짝) · 예약 · 원장 · 발송 큐 없음
    update public.so set status = 'shipped', shipped_at = now(), shipped_by = p_staff, updated_by = p_staff
    where id = p_so_id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not finished — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;
    v_ship := jsonb_build_object('shipped', true, 'so_number', v_so.so_number, 'shipped_on', public.ims_today(), 'shipped_by', p_staff, 'lines', '[]'::jsonb,
                                 'backorder', null, 'ledger', null, 'warnings', '[]'::jsonb, 'fulfill', null, 'no_goods', true);
  end if;
  v_iss := public.so_invoice_issue(array[p_so_id], p_staff, null);
  v_inv_id := (v_iss->>'invoice_id')::uuid;
  select array_agg(t.w) into v_tw from jsonb_array_elements_text(coalesce(v_iss->'warnings', '[]'::jsonb)) as t(w);
  v_warn := v_warn || coalesce(v_tw, '{}');

  return jsonb_build_object('committed', true, 'so_id', v_so.id, 'so_number', v_so.so_number, 'channel', v_so.channel, 'status', 'fulfilled',
                            'invoice_id', v_inv_id, 'invoice_number', v_iss->>'invoice_number', 'issued_on', v_iss->'issued_on', 'due_on', v_iss->'due_on',
                            'totals', v_iss->'totals', 'received', jsonb_build_object('deposit_applied', v_iss->'totals'->'deposit_applied', 'credit_applied', v_iss->'totals'->'credit_applied', 'balance_forward', v_iss->'totals'->'balance_forward'),
                            'amount_due', v_iss->'totals'->'amount_due', 'remaining', public.so_invoice_remaining(v_inv_id),
                            'estimate', v_est, 'ship', v_ship, 'short_ea_total', v_plan->'short_ea_total', 'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ 재발행 4/7 — so_credit_issue(DB prosrc 원본 md5 3c202942 + 더한 줄 · fsale-1(판정 1162-5): final_sale 서비스 줄(charge) 크레딧 = 경고 final_sale:<서비스 이름>(막지 않는다)) ═══
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
        select 'final_sale:' || fs.name into v_wt from public.so_charge fc join public.ref_service fs on fs.id = fc.service_id where fc.id = v_il.so_charge_id and fs.final_sale;   -- fsale-1(판정 1162-5 · 640 과 같은 열쇠 꼴): 떨이 줄 크레딧 — 경고만(막지 않는다)
        if found and not (v_wt = any (v_warn)) then v_warn := array_append(v_warn, v_wt); end if;
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

-- ═══ 재발행 5/7 — so_credit_prepare(DB prosrc 원본 md5 12d94334 + 더한 줄 · fsale-1: charge 줄의 final_sale = 그 줄의 서비스가 final_sale) ═══
CREATE OR REPLACE FUNCTION public.so_credit_prepare(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with inv as (
    select i.*, cu.name as customer_name, public.ims_today() as today,
           (select s.location_id from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = i.id order by o.so_number limit 1) as wh_id   -- 발행 창구 :996 과 같은 줄(원판매 첫 오더의 창고)
    from public.so_invoice i left join public.customer cu on cu.id = i.bill_to_customer_id
    where i.id = p_invoice_id
  ),
  cfg as (
    select (select nullif(k.value, '')::int     from public.inv_config k where k.key = 'so_credit_restock_fee_days')         as fee_days,
           (select nullif(k.value, '')::numeric from public.inv_config k where k.key = 'so_credit_restock_fee_pct')          as fee_pct,
           (select nullif(k.value, '')          from public.inv_config k where k.key = 'so_credit_restock_fee_account_code') as fee_account_code
  )
  select jsonb_build_object(
    'invoice', jsonb_build_object('id', inv.id, 'invoice_number', inv.invoice_number, 'status', inv.status, 'creditable', (inv.status = 'issued'), 'issued_on', inv.issued_on,
                                  'days_since_invoice', inv.today - inv.issued_on, 'customer_id', inv.bill_to_customer_id, 'customer_name', inv.customer_name, 'bill_to_name', inv.bill_to_name,
                                  'currency_id', inv.currency_id, 'currency_code', inv.currency_code, 'total', inv.total, 'remaining', public.so_invoice_remaining(inv.id)),
    'warehouse', (select jsonb_build_object('warehouse_id', w.id, 'warehouse_name', w.name, 'is_active', w.is_active) from public.ref_warehouse w where w.id = inv.wh_id),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                'so_invoice_line_id', l.id, 'line_no', l.line_no, 'kind', l.kind, 'sku', l.sku, 'description', l.description, 'unit', l.unit, 'pack_factor', l.pack_factor,
                'qty_sold', l.qty,
                -- ⚠️ 복사 식(0-5): so_credit_issue 20260925012354:1055~1056 의 「이미 반품」과 글자까지 같아야 창구가 거부하지 않는다 · ⬜ so_credit_line_returned(so_invoice_line_id) 류 함수로 떼고 발행 창구와 함께 부른다(다음 차수)
                'qty_credited', case when l.kind = 'product' then (public.so_credit_line_state(l.id)->>'qty_returned')::numeric end,                                                            -- crn-2: 식은 so_credit_line_state 한 곳(§22-f ⬜ 닫힘)
                'qty_returnable', case when l.kind = 'product' then (public.so_credit_line_state(l.id)->>'qty_returnable')::numeric end,
                -- crn-2 판정 603 · 611 · 613: 가격 조정 재료 — 낸 단가(오더 할인 뒤) · 층(tiers) · 조정할 수 있는 수량(낸 단가 층) · 열린 조정 몫 · 앞선 조정 목록(콤보 줄은 null)
                'adjust', case when l.kind = 'product' and l.combo_components is null then public.so_credit_line_state(l.id) - 'so_invoice_line_id' - 'tiers_raw' end,
                'amount', l.amount,
                -- charge 줄의 「이미 반품」은 금액(발행 창구 :1099~1103 의 v_already 와 같은 뜻)
                'amount_credited', case when l.kind in ('charge', 'surcharge') then (select coalesce(sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') end,   -- surcharge-2b: surcharge 줄은 보이기만(자동 · 손으로 못 보낸다)
                'discount_line_id', fd.fd_id, 'discount_amount', fd.fd_amount, 'net_amount', case when l.kind = 'charge' then l.amount - coalesce(fd.fd_amount, 0) end,                     -- fr-3 판정 355: 운임 줄의 할인(인보이스 charge_discount 줄 · 양수) · 순액
                'discount_credited', fd.fd_credited, 'net_credited', case when l.kind = 'charge' then fd.gross_credited - coalesce(fd.fd_credited, 0) end,                   -- 이미 돌려준 할인(양수) · 이미 돌려준 순액
                'net_remaining', case when l.kind = 'charge' then (l.amount - coalesce(fd.fd_amount, 0)) - (fd.gross_credited - coalesce(fd.fd_credited, 0)) end,              -- 남은 순액 한도(so_credit_issue 의 순액 검사와 같은 식)
                'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'rate_pct', io.rate_pct, 'tax_rule', io.tax_rule, 'tax_amount', l.tax_amount, 'account_code', l.account_code,
                'product_id', sl.product_id, 'stock_product_id', coalesce(pr.parent_product_id, pr.id), 'stock_sku', coalesce(pp.sku, pr.sku),
                'final_sale', sl.bgrade_bin_id is not null or (l.kind = 'charge' and exists (select 1 from public.so_charge fc join public.ref_service fs on fs.id = fc.service_id where fc.id = l.so_charge_id and fs.final_sale)), 'restock_bgrade_bin_gone', sl.bgrade_bin_id is not null and bgb.j is null,   -- bgr-1d 판정 640 · 649: B급으로 판 줄 · 그 B급 칸이 꺼졌거나 비활성이면 정상 기본으로
                -- 되돌려 놓을 칸 기본값 — 발행 창구 :1077 과 같은 길(ims_last_bin(낱개 제품, 창고) · ④a1 뒤로 보관용 아님 먼저 · 없으면 null → 사람이 고르거나 안 돌아옴으로)
                'restock_bin_default', case when l.kind = 'product' and l.combo_components is null and inv.wh_id is not null and pr.id is not null
                                            then coalesce(bgb.j, public.ims_last_bin(array[coalesce(pr.parent_product_id, pr.id)], inv.wh_id) -> coalesce(pr.parent_product_id, pr.id)::text) end,   -- bgr-1d 판정 649: B급 줄은 팔려 나간 그 B급 칸 먼저
                -- asm-2b2(묶음 7 · 판정 245): 콤보 인보이스 줄 = 반품 단위(qty 는 콤보 수) · 구성품마다 돌아가는 칸 기본(ims_last_bin · 낱개 제품 · 그 창고) — 보통 줄은 null
                'combo_components', (select jsonb_agg(cj || jsonb_build_object('restock_bin_default', case when inv.wh_id is not null and cpr.id is not null then public.ims_last_bin(array[coalesce(cpr.parent_product_id, cpr.id)], inv.wh_id) -> coalesce(cpr.parent_product_id, cpr.id)::text end) order by cj->>'sku')
                                       from jsonb_array_elements(l.combo_components) cj left join public.product cpr on cpr.id = nullif(cj->>'product_id', '')::uuid))
              order by l.line_no), '[]'::jsonb)
              from public.so_invoice_line l
              join public.so_invoice_order io on io.id = l.invoice_order_id
              left join public.so_line sl on sl.id = l.so_line_id
              left join public.product pr on pr.id = sl.product_id
              left join public.product pp on pp.id = pr.parent_product_id
              left join lateral (select jsonb_build_object('bin_id', rb.id, 'bin', rb.name, 'zone', rb.zone, 'received_on', null, 'is_bgrade', true) as j                       -- bgr-1d: ims_last_bin 칸 꼴 + is_bgrade
                                   from public.ref_bin rb where rb.id = sl.bgrade_bin_id and rb.is_bgrade and rb.is_active and rb.warehouse_id = inv.wh_id) bgb on true
              left join lateral (select d.id as fd_id, -d.amount as fd_amount,                                                                                       -- fr-3: 운임 줄의 할인 줄(없으면 null)
                                        (select coalesce(-sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = d.id and c.status = 'issued') as fd_credited,
                                        (select coalesce(sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') as gross_credited
                                   from public.so_invoice_line d where l.kind = 'charge' and d.invoice_id = l.invoice_id and d.kind = 'charge_discount' and d.so_charge_id = l.so_charge_id) fd on true
              where l.invoice_id = inv.id and l.kind in ('product', 'charge', 'surcharge')),
    'restock_fee', jsonb_build_object('days', cfg.fee_days, 'pct', cfg.fee_pct, 'account_code', cfg.fee_account_code,
                                      'days_since_invoice', inv.today - inv.issued_on,
                                      'applies', (cfg.fee_days is not null and inv.today - inv.issued_on > cfg.fee_days),
                                      'note', 'notice only — the preview so_credit_issue(p, false) proposes the amount (fee_suggested); the account must be picked when account_code is null'),
    'already_credited', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'reason', c.reason, 'total', c.total, 'remaining', public.so_credit_remaining(c.id)) order by c.credit_number), '[]'::jsonb)
                         from public.so_credit c where c.invoice_id = inv.id),
    'vocab', jsonb_build_object('reasons', '["customer_return","damaged","billing_error","other","price_adjustment"]'::jsonb,                                                      -- crn-2 판정 612
                                'not_restocked_reasons', '["damaged","not_returned","other"]'::jsonb,                                                   -- bgr-1e 판정 651: b_grade 는 새로 못 고른다
                                'not_restocked_reasons_retired', '["b_grade"]'::jsonb,                                                                    -- bgr-1e: 옛 줄 표시용(라벨만)
                                'line_kinds', '["product","freight","tax","other","restocking_fee","price_adjustment"]'::jsonb)                                                   -- crn-2 판정 603
  )
  from inv, cfg;
$function$;

-- ═══ 재발행 6/7 — mcp_sales(DB prosrc 원본 md5 90347c62 + 더한 줄 · fsale-1: other.final_sale(final_sale 서비스 줄 매출 · services 에서 뺀다)) ═══
CREATE OR REPLACE FUNCTION public.mcp_sales(p_from text, p_to text, p_group text, p_brand text DEFAULT NULL::text, p_customer text DEFAULT NULL::text, p_sku text DEFAULT NULL::text, p_supplier text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET work_mem TO '32MB'
AS $function$
declare
  c_cost_from constant date := '2026-08-21';                                           -- 판정 928: 원가 기록 시작(inv_layer_consume sale_out 첫 날 · 시험이 실물로 단언)
  c_slots constant int := 3;                                                           -- mcp-conc-1(1105 · 1110): 직원 전체 합쳐 동시에 도는 판매 집계 자리 수 — 상수 · 바꾸기는 작은 마이그레이션
  v_from date; v_to date; v_gp_from date;
  v_group text := lower(btrim(coalesce(p_group, '')));
  v_limit int := coalesce(p_limit, 50);
  v_offset int := coalesce(p_offset, 0);                                               -- mcp-cap-1: 쪽 넘기기(rn 이 v_offset 보다 큰 줄부터 v_limit 개)
  v_cost boolean;
  v_brand text; v_sup text; v_sku text; v_cust uuid; v_cust_group uuid; v_cust_acct uuid;
  v_filters jsonb := '{}'::jsonb;
  v_other_ok boolean;
  pk jsonb; v_q text; v_n int; v_cr record;
  v_res jsonb;
  v_slot int;                                                                          -- mcp-conc-1: 잡은 자리(1 ~ c_slots) · null = 다 참
begin
  perform public.mcp_gate('sales');
  -- 인자 검사(이견 13) — 영어 한 문장
  if coalesce(p_from, '') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(p_to, '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Give from and to as dates in YYYY-MM-DD form — nothing was read'; end if;
  begin v_from := p_from::date; v_to := p_to::date; exception when others then raise exception 'from or to is not a real calendar date (% · %) — nothing was read', p_from, p_to; end;
  if v_from > v_to then raise exception 'from (%) is after to (%) — nothing was read', v_from, v_to; end if;
  if v_to > v_from + interval '3 years' then raise exception 'The period is longer than 3 years — ask for a shorter range — nothing was read'; end if;
  if v_group not in ('brand', 'customer', 'month', 'sku', 'supplier') then raise exception 'group must be one of brand, customer, month, sku, supplier — nothing was read'; end if;
  if v_limit < 1 or v_limit > 500 then raise exception 'limit must be between 1 and 500 — nothing was read'; end if;
  if v_offset < 0 then raise exception 'offset must be 0 or more — nothing was read'; end if;
  v_cost := public.ims_can_view_cost();
  v_gp_from := greatest(v_from, c_cost_from); if v_gp_from > v_to then v_gp_from := null; end if;
  -- 거르기(이름 → 하나 · 못 풀면 후보)
  if nullif(btrim(coalesce(p_brand, '')), '') is not null then
    pk := public.mcp_name_pick('brand', p_brand);
    if pk->>'id' is null then return jsonb_build_object('resolved', false, 'field', 'brand', 'query', btrim(p_brand), 'matches', pk->'matches', 'candidates', pk->'candidates'); end if;
    v_brand := pk->>'name'; v_filters := v_filters || jsonb_build_object('brand', v_brand);
  end if;
  if nullif(btrim(coalesce(p_supplier, '')), '') is not null then
    pk := public.mcp_name_pick('supplier', p_supplier);
    if pk->>'id' is null then return jsonb_build_object('resolved', false, 'field', 'supplier', 'query', btrim(p_supplier), 'matches', pk->'matches', 'candidates', pk->'candidates'); end if;
    v_sup := pk->>'name'; v_filters := v_filters || jsonb_build_object('supplier', v_sup);
  end if;
  if nullif(btrim(coalesce(p_customer, '')), '') is not null then
    pk := public.mcp_customer_pick(p_customer);
    v_cust := (pk->>'id')::uuid;
    if v_cust is null then return jsonb_build_object('resolved', false, 'field', 'customer', 'query', btrim(p_customer), 'matches', pk->'matches', 'candidates', pk->'candidates'); end if;
    select c.name, c.parent_id, (select p.name from public.customer p where p.id = c.parent_id) as parent_name into v_cr from public.customer c where c.id = v_cust;
    if v_cr.parent_id is null then v_cust_group := v_cust; v_filters := v_filters || jsonb_build_object('customer', v_cr.name, 'customer_scope', 'this customer and its accounts');
    else v_cust_acct := v_cust; v_filters := v_filters || jsonb_build_object('customer', v_cr.name, 'customer_scope', 'this account only', 'parent_name', v_cr.parent_name); end if;
  end if;
  if nullif(btrim(coalesce(p_sku, '')), '') is not null then
    v_q := upper(btrim(p_sku));
    select p.sku into v_sku from public.product p where upper(p.sku) = v_q;
    if v_sku is null then
      select count(*), min(p.sku) into v_n, v_sku from public.product p where p.sku ilike '%' || v_q || '%';
      if v_n <> 1 then
        return jsonb_build_object('resolved', false, 'field', 'sku', 'query', v_q, 'matches', v_n,
                                  'candidates', (select coalesce(jsonb_agg(jsonb_build_object('sku', x.sku, 'name', x.name) order by x.sku), '[]'::jsonb) from (select p.sku, p.name from public.product p where p.sku ilike '%' || v_q || '%' order by p.sku limit 5) x));
      end if;
    end if;
    v_sku := upper(v_sku); v_filters := v_filters || jsonb_build_object('sku', v_sku);
  end if;
  v_other_ok := v_brand is null and v_sup is null and v_sku is null;
  -- 자리표(mcp-conc-1 · 1105 ~ 1110): c_slots 칸 중 빈 칸 하나 — 기다림 0 · 잠금은 이 트랜잭션(= RPC 한 번) 끝에 저절로 풀림 · 다 차면 즉시 PT429(기다렸다 다시는 EF 가 · 1109)
  for v_n in 1 .. c_slots loop
    if pg_try_advisory_xact_lock(hashtext('mcp_sales:slot:' || v_n)) then v_slot := v_n; exit; end if;
  end loop;
  if v_slot is null then
    raise exception using errcode = 'PT429',
      message = format('IMS is busy: %s sales summaries are already running across all staff — try again in a few seconds, one at a time — nothing was read', c_slots);
  end if;

  with
  -- 기본 공급처(930 · 이견 5): is_default · is_active · 여럿이면 이름순 첫째
  ps as (select x.product_id, min(s.name) as supplier
           from public.product_supplier x join public.supplier s on s.id = x.supplier_id
          where x.is_default and x.is_active group by x.product_id),
  -- IMS 오더 → 인보이스 날짜(못 맞춘 원가의 날짜 자리)
  soi as (select o.so_id, max(i.issued_on) as d from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where i.kind = 'sale' and i.status = 'issued' group by o.so_id),
  -- ① 줄 전부 한 번에 — src: sale · credit(제품 줄 · (ldoc, sku) = 원가와 맞출 열쇠 · 이견 3) · freight · services · order_discount · adjustments · other_credit · non_cad(이견 7 ~ 9 · 11)
  --    ⚠️ 이력 kind 는 WHERE 가 아니라 select 에서(이견 1 · 플래너 0.5 % 추정 → 중첩 루프 함정) · hist_line_kind(lower · like 넷)를 줄마다 부르면 1.3 s(283k 행) → 특수 꼴일 수 있는 줄에만(정규식 하나 · ci · 상위 집합) · 뜻은 hist_line_kind 가 정한다
  ln as (select case when x.kind = 'product' and x.doc_type = 'invoice' then 'sale' when x.kind = 'product' then 'credit' when x.doc_type = 'credit' then 'other_credit'
                     when x.kind = 'freight' then 'freight' when x.kind = 'services' then 'services' when x.kind = 'discount' then 'order_discount' else 'adjustments' end as src,
                case when x.kind <> 'product' then null when x.doc_type = 'invoice' then x.order_number else 'c:' || lower(btrim(x.doc_number)) end as ldoc,
                x.d, x.customer_id, x.brand, x.usku as sku, x.product_id, x.amount, x.qty, (x.doc_type = 'invoice') as inv
           from (select h.order_number, hl.doc_number, hl.doc_type, upper(hl.sku) as usku, hl.product_id, nullif(hl.brand, '') as brand, h.customer_id,
                        case when hl.doc_type = 'invoice' then h.invoice_date else hl.doc_date end as d, case when hl.doc_type = 'invoice' then hl.sale else -hl.sale end as amount, abs(hl.quantity) as qty,
                        case when hl.sku ~* '^(_[0-9]+_$|shipping|discount$|order total discount$|customer credit|credit-)'
                             then (case when hl.sku ~ '^_[0-9]+_$' and hl.sku <> '_4_' then 'services' else public.hist_line_kind(hl.sku) end) else 'product' end as kind
                   from public.hist_so h join public.hist_so_line hl on hl.hist_so_id = h.id
                  where (hl.doc_type = 'invoice' and h.invoice_date between v_from and v_to) or (hl.doc_type = 'credit' and hl.doc_date between v_from and v_to)
                 offset 0) x
         union all
         -- IMS 인보이스 줄 — kind sale · issued · opening 제외 · 콤보 구성 줄 제외 · CAD 아니면 non_cad(이견 11)
         select case when coalesce(i.currency_code, 'CAD') <> 'CAD' then 'non_cad' when l.kind = 'product' then 'sale'
                     when l.kind in ('charge', 'charge_discount') and sc.service_id is null then 'freight'
                     when l.kind = 'charge' and exists (select 1 from public.ref_service fs where fs.id = sc.service_id and fs.final_sale) then 'final_sale'
                     when l.kind in ('charge', 'charge_discount', 'surcharge') then 'services' else 'order_discount' end,
                case when l.kind = 'product' and coalesce(i.currency_code, 'CAD') = 'CAD' then 'i:' || l.so_line_id::text end, i.issued_on, coalesce(o.customer_id, s.customer_id), p.brand_name, upper(l.sku), sl.product_id,
                l.amount, l.qty, coalesce(i.currency_code, 'CAD') = 'CAD'
           from public.so_invoice i join public.so_invoice_order o on o.invoice_id = i.id join public.so s on s.id = o.so_id join public.so_invoice_line l on l.invoice_order_id = o.id
           left join public.so_line sl on sl.id = l.so_line_id left join public.product p on p.id = sl.product_id left join public.so_charge sc on sc.id = l.so_charge_id
          where i.kind = 'sale' and i.status = 'issued' and i.issued_on between v_from and v_to and sl.combo_line_id is null
         union all
         -- IMS 크레딧 줄 — issued · 콤보 자식 제외 · tax 줄 제외(세전) · product · price_adjustment 가 제품 크레딧
         select case when coalesce(c.currency_code, 'CAD') <> 'CAD' then 'non_cad' when l.kind in ('product', 'price_adjustment') then 'credit' else 'other_credit' end,
                case when l.kind in ('product', 'price_adjustment') and coalesce(c.currency_code, 'CAD') = 'CAD' then 'c:' || lower(c.credit_number) end, c.issued_on, c.customer_id, p.brand_name, upper(l.sku), l.product_id,
                l.amount, coalesce(l.qty_returned, 0), false
           from public.so_credit c join public.so_credit_line l on l.credit_id = c.id left join public.product p on p.id = l.product_id
          where c.status = 'issued' and c.issued_on between v_from and v_to and l.combo_credit_line_id is null and l.kind <> 'tax'),
  -- ② 원가(928 · 이견 2 · 3): sale_out(reason sale) 을 열쇠로 — IMS line_ref = so_line.id(콤보 구성품은 부모 줄 · 자리도 부모 제품) · 이력 = 오더 번호 × SKU · 자리 = 오더 머리(손님 · 인보이스 날짜) + 소비한 SKU 의 제품
  cg as (select c.doc_number, upper(l.sku) as sku, sum(c.amount) as amt, min(c.occurred_on) as occ,
                case when c.line_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then c.line_ref::uuid end as line_uuid
           from public.inv_layer_consume c join public.inv_layer l on l.id = c.layer_id
          where c.event_type = 'sale_out' and c.reason = 'sale' and v_gp_from is not null
          group by 1, 2, 5),
  -- 판매 줄 열쇠(기간 안) — 원가에 판매 줄이 있는가(matched) · hashed subplan
  sk as (select distinct h.order_number as ldoc, upper(hl.sku) as lsku
           from public.hist_so h cross join lateral (select hl.sku from public.hist_so_line hl where hl.hist_so_id = h.id and hl.doc_type = 'invoice' offset 0) hl   -- offset 0: (hist_so_id, seq) 색인으로 오더의 줄만(hcr-1 선례)
          where v_gp_from is not null and h.invoice_date between v_gp_from and v_to
         union
         select 'i:' || l.so_line_id::text, upper(l.sku) from public.so_invoice i join public.so_invoice_order o on o.invoice_id = i.id join public.so_invoice_line l on l.invoice_order_id = o.id
          where v_gp_from is not null and i.kind = 'sale' and i.status = 'issued' and i.issued_on between v_gp_from and v_to and l.kind = 'product'),
  cx as (select 'cogs' as src, lk.ldoc, (s.ldoc is not null) as matched,
                coalesce(fh.invoice_date, soi.d, g.occ) as d, coalesce(fh.customer_id, fs.customer_id) as customer_id,
                coalesce(pi.brand_name, ph.brand_name) as brand, lk.lsku as sku, coalesce(pi.id, ph.id) as product_id, g.amt as amount
           from cg g
           left join public.so_line sl on sl.id = g.line_uuid
           left join public.so_line slp on slp.id = coalesce(sl.combo_line_id, sl.id)
           cross join lateral (select case when slp.id is not null then 'i:' || slp.id::text else g.doc_number end as ldoc, coalesce(upper(slp.sku), g.sku) as lsku) lk
           left join sk s on s.ldoc = lk.ldoc and s.lsku = lk.lsku
           left join public.product pi on pi.id = slp.product_id
           left join public.product ph on sl.id is null and upper(ph.sku) = g.sku
           left join public.hist_so fh on fh.era = 'core' and fh.order_number = g.doc_number
           left join public.so fs on fs.so_number = g.doc_number
           left join soi on soi.so_id = fs.id),
  -- ③ 재입고 복원(creditnote 레이어 · 이견 2) — 열쇠 = 크레딧 번호 × SKU · 날짜 = received_on · 자리 = 크레딧 머리의 손님 + 제품
  rs as (select l.doc_number, upper(l.sku) as sku, l.received_on, sum(l.qty * l.unit_cost) as amt
           from public.inv_layer l where l.origin_type = 'creditnote' and v_gp_from is not null and l.received_on between v_gp_from and v_to group by 1, 2, 3),
  rx as (select 'restock' as src, 'c:' || lower(btrim(r.doc_number)) as ldoc, r.received_on as d, coalesce(fh.customer_id, fc.customer_id) as customer_id, p.brand_name as brand, r.sku, p.id as product_id, r.amt as amount
           from rs r
           left join lateral (select h.customer_id from public.hist_so_line hl join public.hist_so h on h.id = hl.hist_so_id
                               where hl.doc_type = 'credit' and lower(btrim(hl.doc_number)) = lower(btrim(r.doc_number)) limit 1) fh on true
           left join public.so_credit fc on fc.credit_number = r.doc_number
           left join public.product p on upper(p.sku) = r.sku),
  ck as (select distinct x.ldoc, x.sku from cx x),   -- 원가가 붙은 열쇠(판매 줄의 costed · 해시 조인 · ⚠️ EXISTS 서브플랜은 플래너가 hashed 를 안 고르면 283k × 56k — 실측으로 겪음)
  -- ④ 하나로 + 손님 묶음(929) + 공급처 + 거르기(브랜드 · 손님 · SKU · 공급처) — 한 번 · 표 밖 줄은 gkey null · okind = 그 종류 · costed = 그 판매 줄에 원가가 붙었나(hashed subplan · 열쇠 단위 집계 없음)
  f as (select u.src, u.d, u.amount, u.qty, u.inv, u.customer_id, u.matched,
               (u.src = 'sale' and ck.ldoc is not null) as costed,
               case when u.src not in ('sale', 'credit', 'cogs', 'restock') then null
                    when v_group = 'brand' then coalesce(u.brand, '(no brand)') when v_group = 'customer' then coalesce(coalesce(c.parent_id, c.id)::text, '(no customer)') when v_group = 'month' then to_char(u.d, 'YYYY-MM')
                    when v_group = 'sku' then u.sku else coalesce(ps.supplier, '(no supplier)') end as gkey,
               case when u.src in ('sale', 'credit', 'cogs', 'restock') then null else u.src end as okind
          from (select x.src, x.ldoc, x.d, x.customer_id, x.brand, x.sku, x.product_id, x.amount, x.qty, x.inv, true as matched from ln x where v_other_ok or x.src in ('sale', 'credit')
                union all select x.src, x.ldoc, x.d, x.customer_id, x.brand, x.sku, x.product_id, x.amount, null::numeric, false, x.matched from cx x where x.d between v_gp_from and v_to
                union all select x.src, x.ldoc, x.d, x.customer_id, x.brand, x.sku, x.product_id, x.amount, null::numeric, false, true from rx x) u
          left join public.customer c on c.id = u.customer_id left join ps on ps.product_id = u.product_id
          left join ck on u.src = 'sale' and ck.ldoc = u.ldoc and ck.sku = u.sku
         where (v_brand is null or lower(coalesce(u.brand, '')) = lower(v_brand))
           and (v_cust_group is null or coalesce(c.parent_id, c.id) = v_cust_group) and (v_cust_acct is null or u.customer_id = v_cust_acct)
           and (v_sku is null or u.sku = v_sku)
           and (v_sup is null or lower(coalesce(ps.supplier, '')) = lower(v_sup))),
  -- ⑤ 계정 단위(929) → 묶음 단위 롤업 — 해시 집계 한 번(묶음 × 계정 × 종류 ≈ 수만)
  ga as (select f.gkey, f.customer_id, f.okind,
                coalesce(sum(f.amount) filter (where f.src = 'sale'), 0) as sales, coalesce(sum(f.amount) filter (where f.src = 'credit'), 0) as credits,
                coalesce(sum(f.qty) filter (where f.src = 'sale'), 0) as qty, coalesce(sum(f.qty) filter (where f.src = 'credit'), 0) as qty_credited,
                coalesce(sum(f.amount) filter (where f.src = 'cogs'), 0) - coalesce(sum(f.amount) filter (where f.src = 'restock'), 0) as cogs,
                coalesce(sum(f.amount) filter (where f.src = 'cogs' and not f.matched), 0) as cogs_unmatched,
                coalesce(sum(f.amount) filter (where f.src = 'sale' and f.costed and f.d >= v_gp_from), 0) as sales_costed,
                coalesce(sum(f.amount) filter (where f.src = 'credit' and f.d >= v_gp_from), 0) as credits_costed,
                coalesce(sum(f.amount) filter (where f.src = 'sale' and not f.costed and f.d >= v_gp_from), 0) as uncosted,
                coalesce(sum(f.amount) filter (where f.okind is not null), 0) as other_amt, count(*) filter (where f.okind is not null) as other_n, coalesce(sum(f.amount) filter (where f.inv), 0) as inv_amt
           from f group by f.gkey, f.customer_id, f.okind),
  g as (select a.gkey, sum(a.sales) as sales, sum(a.credits) as credits, sum(a.qty) as qty, sum(a.qty_credited) as qty_credited, sum(a.cogs) as cogs, sum(a.cogs_unmatched) as cogs_unmatched,
               sum(a.sales_costed) as sales_costed, sum(a.credits_costed) as credits_costed, sum(a.uncosted) as uncosted, count(*) as n_acct   -- n_acct: 묶음의 계정 수(ga 는 gkey × customer_id · 표 안 줄은 okind null · mcp-cap-1 이견 3)
          from ga a where a.gkey is not null group by a.gkey),
  gr as (select g.*, row_number() over (order by (case when v_group = 'month' then g.gkey end), (case when v_group <> 'month' then g.sales - g.credits end) desc nulls last, g.gkey) as rn from g),
  -- 이 쪽(mcp-cap-1 · 이견 2 · 3): rn 이 v_offset 보다 큰 줄부터 v_limit 개 · customer 이름은 uuid 로(gkey::text 비교는 pk 색인을 못 탄다) · 계정 묶음은 ga 를 쪽의 gkey 로 한 번 묶어 조인(줄마다 ga 를 훑지 않는다)
  pg as (select gr.*, case when v_group = 'customer' and gr.gkey ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then gr.gkey::uuid end as gid
           from gr where gr.rn > v_offset and gr.rn <= v_offset + v_limit),
  acc as (select a.gkey, jsonb_agg(jsonb_build_object('name', c.name)
                                   || public.mcp_sales_cell(a.sales, a.credits, a.qty, a.qty_credited, a.cogs, a.sales_costed, a.credits_costed, a.uncosted, v_cost, v_gp_from is not null)
                                   order by a.sales - a.credits desc) as j
            from ga a join pg on pg.gkey = a.gkey left join public.customer c on c.id = a.customer_id
           where v_group = 'customer' and pg.n_acct > 1 group by a.gkey),
  rows_j as (select coalesce(jsonb_agg(
               jsonb_build_object('key', case when v_group = 'customer' then coalesce(cn.name, pg.gkey) else pg.gkey end)
               || case when v_group = 'sku' then jsonb_build_object('name', (select p.name from public.product p where upper(p.sku) = pg.gkey limit 1)) else '{}'::jsonb end
               || public.mcp_sales_cell(pg.sales, pg.credits, pg.qty, pg.qty_credited, pg.cogs, pg.sales_costed, pg.credits_costed, pg.uncosted, v_cost, v_gp_from is not null)
               || case when acc.j is not null then jsonb_build_object('accounts', acc.j) else '{}'::jsonb end
               order by pg.rn), '[]'::jsonb) as j, count(*) as shown
               from pg left join public.customer cn on cn.id = pg.gid left join acc on acc.gkey = pg.gkey),
  -- 쪽 정보 · 안 보인 줄(앞 + 뒤 · 925 항등식: 보이는 줄 net 합 + rows_truncated.net = totals.net 이 모든 쪽에서 선다 · offset 0 이면 지금까지와 같은 뜻)
  pagei as (select r.shown, t.n as total, case when v_offset + r.shown < t.n then v_offset + r.shown end as next_offset from rows_j r, (select count(*) as n from gr) t),
  trunc as (select count(*) as n, coalesce(sum(gr.sales - gr.credits), 0) as net from gr where gr.rn <= v_offset or gr.rn > v_offset + v_limit),
  -- ⑥ 표 밖(925 · 926 · 이견 7 ~ 9 · 11) — 오더 단위 · brand · sku · supplier 거르기 없을 때만(f 가 이미 손님 거르기를 했다) · invoice_total_pretax = inv 줄 전부(제품 포함)
  oth as (select coalesce(sum(a.other_amt) filter (where a.okind = 'freight'), 0) as freight, coalesce(sum(a.other_amt) filter (where a.okind = 'services'), 0) as services, coalesce(sum(a.other_amt) filter (where a.okind = 'final_sale'), 0) as final_sale,
                 coalesce(sum(a.other_amt) filter (where a.okind = 'order_discount'), 0) as order_discount, coalesce(sum(a.other_amt) filter (where a.okind = 'adjustments'), 0) as adjustments,
                 coalesce(sum(a.inv_amt), 0) as invoice_total_pretax, coalesce(sum(a.other_amt) filter (where a.okind = 'other_credit'), 0) as other_credits,
                 coalesce(sum(a.other_n) filter (where a.okind = 'non_cad'), 0) as non_cad_n, coalesce(sum(a.other_amt) filter (where a.okind = 'non_cad'), 0) as non_cad_amt
            from ga a),
  srcn as (select (select min(h.invoice_date) from public.hist_so h) as h0, (select max(h.invoice_date) from public.hist_so h) as h1,
                  (select min(i.issued_on) from public.so_invoice i where i.kind = 'sale' and i.status = 'issued') as i0)
  select jsonb_build_object(
           'period', jsonb_build_object('from', v_from, 'to', v_to), 'group', v_group, 'filters', v_filters,
           'rows', (select j from rows_j),
           'page', (select jsonb_build_object('offset', v_offset, 'limit', v_limit, 'shown', p.shown, 'total_rows', p.total, 'next_offset', p.next_offset) from pagei p),
           'totals', (select public.mcp_sales_cell(sum(g.sales), sum(g.credits), sum(g.qty), sum(g.qty_credited), sum(g.cogs), sum(g.sales_costed), sum(g.credits_costed), sum(g.uncosted), v_cost, v_gp_from is not null)
                             || case when v_cost then jsonb_build_object('cogs_unmatched', case when v_gp_from is not null then round(coalesce(sum(g.cogs_unmatched), 0), 2) end) else '{}'::jsonb end from gr g),
           'source_note', (select 'Cin7 history: invoice dates ' || coalesce(s.h0::text, '(none)') || ' to ' || coalesce(s.h1::text, '(none)') || ' · IMS invoices from ' || coalesce(s.i0::text, '(none yet)')
                                  || ' · costs recorded from ' || c_cost_from::text || ' · amounts CAD before tax · product lines only (freight, services, final sale items, order discounts and adjustments are under "other") · sales by invoice date, credits by credit date · totals are computed by IMS'
                             from srcn s))
         || case when (select t.n from trunc t) > 0 then jsonb_build_object('rows_truncated', (select jsonb_build_object('rows', t.n, 'net', round(t.net, 2)) from trunc t)) else '{}'::jsonb end
         || case when v_other_ok then jsonb_build_object('other', (select jsonb_build_object('freight', round(o.freight, 2), 'services', round(o.services, 2), 'final_sale', round(o.final_sale, 2), 'order_discount', round(o.order_discount, 2), 'adjustments', round(o.adjustments, 2),
                                                                                      'invoice_total_pretax', round(o.invoice_total_pretax, 2), 'other_credits', round(o.other_credits, 2),
                                                                                      'excluded_non_cad', jsonb_build_object('count', o.non_cad_n, 'amount', round(o.non_cad_amt, 2))) from oth o))
                 else jsonb_build_object('other_note', 'Freight, services, final sale items, order discounts and adjustments are order-level and are shown only when not filtering by brand, SKU or supplier') end
         || case when v_cost then jsonb_build_object('gp_from', v_gp_from) else '{}'::jsonb end
    into v_res;
  return v_res;
end;
$function$;

-- ═══ 재발행 7/7 — so_detail(DB prosrc 원본 md5 3f70f442 + 더한 줄 · fsale-1: charges[] 열쇠 final_sale · price_each_time) ═══
CREATE OR REPLACE FUNCTION public.so_detail(p_so_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_so       public.so%rowtype;
  v_cust     text;
  v_lines    jsonb;
  v_charges  jsonb;
  v_lines_n  int;  v_no_price int;  v_free int;  v_charges_n int;  v_deal_ended int;
  v_lines_total numeric;  v_charges_total numeric;  v_od_amt numeric;
  v_sc_amt numeric := 0;  v_sc_tax numeric := 0;                            -- surcharge-2a — so_tax_preview totals 에서 읽는다(식 한 곳 · basis 를 따라간다)
  v_chd    numeric := 0;                                                     -- fr-1 판정 352: 운임 할인 합 — so_tax_preview totals 에서(식 한 곳)
  v_warn     text[];
  v_tax      jsonb;  v_tw text[];                              -- 세금 ② — so_tax_preview
  v_basis    text;  v_inv jsonb;  v_inv_hist jsonb;  v_removed int;  v_qty_removed numeric;   -- ⓐ2 — 보낸 수량 기준 · 인보이스 · 뺀 몫
  v_bal      jsonb;                                            -- ⓑ2 — 청구처 손님 잔액(그 통화 행)
  v_rule     record;  v_rule_j jsonb;                          -- dsc-3a 판정 311 — manual 인데 규칙 쪽이 더 크면 경고
  v_cp       jsonb;                                            -- dsc-3b 판정 329 — 붙은 쿠폰
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('manual', public.so_line_manual(l), 'price_set_by_name', (select s.name from public.ims_staff s where s.id = l.price_set_by), 'total', public.so_line_total(l),   -- ln-1 판정 546(price_set_by · price_set_at 은 to_jsonb(l) 에)
                                                              'no_price', l.unit_price is null, 'free', l.free_reason is not null, 'shipped_total', round(l.qty_shipped * l.unit_price, 2), 'removed', l.qty_removed > 0,
                                                              'surcharge_unit', public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), 'surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_ordered), 'shipped_surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_shipped),   -- surcharge-2a(묶음 1 · 2 · total · shipped_total 과 같은 수량)
                                                              'qty_credited', (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_line_id = l.id and c.status = 'issued'),   -- ⓒ2
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date),
                                                              'is_combo', exists (select 1 from public.so_line c where c.combo_line_id = l.id),                                                           -- asm-2a(묶음 2 · 5): 콤보 줄 · 구성품 줄(combo_line_id · combo_qty 는 to_jsonb(l) 에 있다)
                                                              'bgrade_bin', (select rb.name from public.ref_bin rb where rb.id = l.bgrade_bin_id), 'is_bgrade_line', l.bgrade_bin_id is not null,   -- bgr-1c 판정 634 · 635: POS · so 화면의 B-grade 표시
                                                              'combo_sku', (select c.sku from public.so_line c where c.id = l.combo_line_id), 'customer_note', (select sn.note from public.so_line_note sn where sn.so_line_id = l.id)) order by l.line_no), '[]'::jsonb),
         count(*) filter (where l.combo_line_id is null), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), public.so_lines_total(p_so_id),   -- dsc-3a 판정 310: 기준 금액 식 한 곳
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)),
         count(*) filter (where l.qty_removed > 0), coalesce(sum(l.qty_removed), 0)
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended, v_removed, v_qty_removed
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('discount', public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount), 'net', c.amount - public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount), 'final_sale', coalesce(rs.final_sale, false), 'price_each_time', coalesce(rs.price_each_time, false)) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)   -- fr-1: 할인액 · 순 운임(식 한 곳)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c left join public.ref_service rs on rs.id = c.service_id where c.so_id = p_so_id;   -- fsale-1: 줄 열쇠 final_sale · price_each_time(서비스의 표시 칸 · 운임 줄은 false)

  -- 오더 전체 할인(D6) — 제품 줄 합계에 한 번 · round 2(SO-10842 실물) · 운임은 기준에 없다
  -- od-1 판정 542 ~ 544: 오더 할인 금액은 so_tax_preview 가 센 값(손으로 정한 줄을 뺀 바탕 · 식 한 곳) — 아래 v_tax 뒤에서 읽는다(ordered · shipped 둘 다)

  -- 세금(세금 ② · 판정 8) — 오더에 고른 규칙(manual|ship_to)으로 줄마다 · 규칙 없으면 tax null + 경고 tax_rule_missing
  v_basis := case when v_so.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;   -- ⓐ2: 나간 뒤에는 보낸 수량이 금액(뺀 몫·pick_short 제외 · 인보이스가 정본 8-c) · ⓑ2: invoiced 값 없음(판정 1)
  v_tax := public.so_tax_preview(p_so_id, null, null, v_basis);
  v_od_amt := -coalesce((v_tax->'totals'->>'order_discount_amount')::numeric, 0);                                                                       -- od-1: 양수(so_detail 의 모양) · 식은 so_tax_preview 한 곳
  v_sc_amt := coalesce((v_tax->'totals'->>'surcharge_amount')::numeric, 0);  v_sc_tax := coalesce((v_tax->'totals'->>'surcharge_tax')::numeric, 0);   -- surcharge-2a(묶음 3 · 4)
  v_chd := coalesce((v_tax->'totals'->>'charges_discount_amount')::numeric, 0);                                                                          -- fr-1 판정 352(세금은 v_tax 의 tax 가 이미 뺐다 · 354)
  if v_basis = 'shipped' then
    v_lines_total := (v_tax->'totals'->>'lines_amount')::numeric;
  end if;
  select jsonb_build_object('invoice_id', i.id, 'invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'due_on', i.due_on, 'total', i.total,
                            'deposit_applied', i.deposit_applied, 'credit_applied', i.credit_applied, 'balance_forward', i.balance_forward, 'amount_due', i.amount_due,
                            'remaining', public.so_invoice_remaining(i.id), 'paid', i.total - public.so_invoice_remaining(i.id),
                            'credits', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'total', c.total) order by c.credit_number), '[]'::jsonb) from public.so_credit c where c.invoice_id = i.id),
                            'credited_total', (select coalesce(sum(c.total), 0) from public.so_credit c where c.invoice_id = i.id and c.status = 'issued')) into v_inv
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id and o.cancelled_at is null;
  select coalesce(jsonb_agg(jsonb_build_object('invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'cancelled_at', i.cancelled_at) order by i.invoice_number), '[]'::jsonb) into v_inv_hist
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id;
  select to_jsonb(b) into v_bal from public.so_customer_balance(coalesce(v_so.bill_to_customer_id, v_so.customer_id)) b where b.currency_id = v_so.currency_id;   -- ⓑ2: 청구처의 그 통화 잔액(받아 둔 돈 · 예약 · available · 미수)

  v_warn := public.so_tier_warnings(v_so);
  if v_so.tax_rule_id is null then v_warn := array_append(v_warn, 'tax_rule_missing'); end if;
  if v_removed > 0 then v_warn := array_append(v_warn, 'lines_removed'); end if;
  select array_agg(t.v) into v_tw from jsonb_array_elements_text(coalesce(v_tax->'warnings', '[]'::jsonb)) as t(v);
  v_warn := v_warn || coalesce(v_tw, '{}');
  if v_lines_n = 0    then v_warn := array_append(v_warn, 'no_lines'); end if;
  if v_no_price > 0   then v_warn := array_append(v_warn, 'lines_without_price'); end if;
  if v_deal_ended > 0 then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  if v_so.status = 'draft' and v_so.order_discount_source = 'manual' then                                          -- dsc-3a 판정 282 · 311: manual(0 포함)은 그대로 + 규칙 쪽이 더 크면 경고
    select * into v_rule from public.so_order_discount(p_so_id);
    if coalesce(v_rule.pct, 0) > coalesce(v_so.order_discount_pct, 0) then
      v_warn := array_append(v_warn, 'order_discount_rule_now_better');
      v_rule_j := jsonb_build_object('rule_pct', v_rule.pct, 'rule_deal_id', v_rule.deal_id, 'manual_pct', v_so.order_discount_pct);
    end if;
  end if;

  v_cp := public.so_coupon_info(v_so);
  if v_cp is not null and v_cp->>'status' <> 'won' then v_warn := array_append(v_warn, 'coupon_not_used'); end if;   -- dsc-3b 판정 329

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'totals', jsonb_build_object('basis', v_basis, 'lines', v_lines_n, 'combo_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and exists (select 1 from public.so_line c where c.combo_line_id = x.id)),
                                 'component_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and x.combo_line_id is not null), 'lines_removed', v_removed, 'qty_removed', v_qty_removed, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt, 'discount_basis_amount', coalesce((v_tax->'totals'->>'discount_basis_amount')::numeric, 0),   -- od-1
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'charges_discount_amount', v_chd, 'charges_net_total', v_charges_total - v_chd,                            -- fr-1 판정 352: charges_total 은 정가 합 그대로 · 새 열쇠
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                        -- surcharge-2a — 물건값 · 오더 할인 기준 밖(묶음 3)
                                 'order_total', v_lines_total - v_od_amt + v_charges_total - v_chd + v_sc_amt,                                    -- fr-1: 운임 할인을 뺀다
                                 'tax_rule', v_so.tax_rule, 'tax_rule_source', v_tax->>'source', 'tax', v_tax->'totals'->'tax',
                                 'order_total_with_tax', case when v_tax->'totals'->>'tax' is null then null else v_lines_total - v_od_amt + v_charges_total - v_chd + v_sc_amt + (v_tax->'totals'->>'tax')::numeric end),   -- fr-1
    'tax', v_tax,
    'invoice', v_inv,
    'invoice_history', v_inv_hist,
    'customer_balance', v_bal,
    'order_discount_rule', v_rule_j,
    'coupon', v_cp,
    'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ comment — 재발행 일곱은 옛 글 뒤에 덧(한 번만) ═══
do $$
declare v_r record;
begin
  for v_r in select * from (values
    ('public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric, numeric, numeric, uuid)', ' · fsale-1(판정 1162-2 · 3): final_sale 서비스는 counter · pos · service 오더만 · price_each_time 서비스는 단가를 손으로(> 0) · 할인 거부 · 늘 price_set_by · 그 줄의 서비스 떼기 · 바꾸기 거부'),
    ('public.so_confirm_precheck(public.so)', ' · fsale-1(판정 1162-4): 상품 줄 0 이어도 final_sale 서비스 줄이 있는 pos · counter 오더는 지나간다'),
    ('public.so_pos_complete(uuid, jsonb, uuid, boolean)', ' · fsale-1(판정 1162-4): 상품 줄 0 + final_sale 서비스 줄 — 픽 · so_ship · 원장 없이 confirmed → shipped → 발행(ship.no_goods true)'),
    ('public.so_credit_issue(jsonb, boolean)', ' · fsale-1(판정 1162-5): final_sale 서비스 줄(charge) 크레딧 = 경고 final_sale:<서비스 이름>(막지 않는다)'),
    ('public.so_credit_prepare(uuid)', ' · fsale-1: charge 줄의 final_sale = 그 줄의 서비스가 final_sale'),
    ('public.mcp_sales(text, text, text, text, text, text, text, integer, integer)', ' · fsale-1: other.final_sale(final_sale 서비스 줄 매출 · services 에서 뺀다)'),
    ('public.so_detail(uuid)', ' · fsale-1: charges[] 열쇠 final_sale · price_each_time')
  ) as t(sig, add) loop
    if position('fsale-1' in coalesce(obj_description(v_r.sig::regprocedure, 'pg_proc'), '')) = 0 then
      execute format('comment on function %s is %L', v_r.sig, coalesce(obj_description(v_r.sig::regprocedure, 'pg_proc'), '') || v_r.add);
    end if;
  end loop;
end $$;

-- ═══ 착지 검사 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric, numeric, numeric, uuid)'::regprocedure) <> '964ca203822e726b653e86f08b615a19' then v_bad := v_bad || ' so_charge_set_md5'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_charge_set') <> 1 then v_bad := v_bad || ' so_charge_set_count'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_confirm_precheck(public.so)'::regprocedure) <> '4708b28ce60557cdd769bb6f97112ff2' then v_bad := v_bad || ' so_confirm_precheck_md5'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_confirm_precheck') <> 1 then v_bad := v_bad || ' so_confirm_precheck_count'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_pos_complete(uuid, jsonb, uuid, boolean)'::regprocedure) <> '8e0156bf77580611b88380c6dc3ef412' then v_bad := v_bad || ' so_pos_complete_md5'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_pos_complete') <> 1 then v_bad := v_bad || ' so_pos_complete_count'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_credit_issue(jsonb, boolean)'::regprocedure) <> '0f451d71041020768b4b463b248f48a4' then v_bad := v_bad || ' so_credit_issue_md5'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_issue') <> 1 then v_bad := v_bad || ' so_credit_issue_count'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_credit_prepare(uuid)'::regprocedure) <> 'dfa978d2dc2b1fd9634fd2b3cfae1892' then v_bad := v_bad || ' so_credit_prepare_md5'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_prepare') <> 1 then v_bad := v_bad || ' so_credit_prepare_count'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.mcp_sales(text, text, text, text, text, text, text, integer, integer)'::regprocedure) <> 'a73897240053cd2a5173d03f390c9973' then v_bad := v_bad || ' mcp_sales_md5'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') <> 1 then v_bad := v_bad || ' mcp_sales_count'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_detail(uuid)'::regprocedure) <> 'aeb6610276a409d9dab90c8300de3444' then v_bad := v_bad || ' so_detail_md5'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_detail') <> 1 then v_bad := v_bad || ' so_detail_count'; end if;
  if (select count(*) from public.ref_service s where s.final_sale) <> 1 then v_bad := v_bad || ' final_sale_rows'; end if;
  if not exists (select 1 from public.ref_service s join public.ref_account a on a.id = s.account_id where s.final_sale and s.price_each_time and s.is_active and s.unit_price = 0 and a.code = '_98_'
                    and s.name = 'FINAL SALE ITEM - No Return or Exchange') then v_bad := v_bad || ' final_sale_row_shape'; end if;
  if (select count(*) from public.ref_service s where s.price_each_time or s.final_sale) <> 1 then v_bad := v_bad || ' other_services_flagged'; end if;
  if v_bad <> '' then raise exception 'fsale-1 landing check failed:%', v_bad; end if;
  raise notice 'fsale-1 landing OK — ref_service price_each_time · final_sale + FINAL-SALE row(_98_) · 7 functions reissued';
end $$;
