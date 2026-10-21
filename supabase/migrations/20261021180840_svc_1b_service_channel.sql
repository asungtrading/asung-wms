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

-- ═══ svc-1b — 서비스 길(channel service) · 서비스 오더 확정 · 발행 (2026-10-21 · 판정 590 · 593 ~ 597 · 대화 Claude 결정 「늘 따로」) ═══
--   계기: Caleb 「우리는 아마존 Prep service를 제공해 … 서비스만 따로 끊어」 — svc-1a(ref_service · so_charge 수량 × 단가) 위에 서비스 오더의 길을 놓는다.
--   서비스 오더 = 상품 줄 없이 서비스(비용) 줄만(590) · 세금 = 오더 세율(593) · 창고(브랜치) = 손님 기본 · 바꿀 수 있음(594) · 초안 → 확정 → 발행 ·
--   확정 뒤 줄을 고치려면 확정 풀기(595 · so_unconfirm 그대로) · 목록 단가 + 손 단가(596 · svc-1a) · 만들기 · 확정 · 발행 = sales 쓰기(597 · 역할 문 없음) ·
--   인보이스는 늘 따로 — 물건 오더와도 · 다른 서비스 오더와도 한 장에 안 묶는다(서비스 오더 하나 = 인보이스 한 장) · 같은 SO-##### 번호 줄 · WMS · 원장 · 레이어 무접촉.
--   ① CHECK so_channel_ck 에 service · so_create 가 받는다(intake 는 지금 규칙 그대로 — service 는 pos 가 아니라 manual(csv 도 됨) · 창고를 안 주면 so_copy_customer 가 손님 기본으로 · 594)
--   ② 상품 줄 막기 — so_line_add · so_lines_paste 첫머리에서 서비스 오더 거부(so_merge · so_divide · so_hold · so_release_to_wms · so_wms_status · so_picked_up 은 이미 warehouse 만 · so_split 은 줄이 없어 못 쓴다)
--   ③ 서비스 줄은 draft 에서만 — so_charge_gate 에 service 갈래(확정 뒤 「unconfirm it first」 · packed 갈래로 새지 않는다 · so_charge_set · so_charge_remove 가 함께 쓴다)
--   ④ so_service_confirm(p_so_id) — definer · sales 쓰기 · draft → confirmed · 손님 · 브랜치 · 상품 줄 0 · 서비스 줄 ≥ 1 · 합 > 0 · 세율 · 재고 잡기 없음 · 반환 꼴 = so_confirm(so_number · status · committed · lines · siblings · keeps · coupon · warnings) + services · totals
--   ⑤ so_service_invoice(p_so_id, p_issued_on, p_commit) — definer · sales 쓰기 · 미리 보기(p_commit false · 세금 · 자동 붙이기 추정 · Due date) · 실행 = confirmed → shipped(shipped_at · 누른 사람) → so_invoice_issue 이 오더 하나만 → fulfilled ·
--      인보이스를 취소하면(so_invoice_cancel · fulfilled → shipped) shipped 에서 다시 발행 · 한 트랜잭션(실패하면 전부 되돌아감) · 반환 꼴 = so_pos_complete(committed · invoice_number · issued_on · due_on · totals · received · amount_due · remaining · estimate · warnings)
--   ⑥ 문지기 so_status_guard — confirmed → shipped 를 service 에도 · service 는 at_wms · picking · packed 로 못 간다(공통 짝 confirmed→at_wms 를 service 에는 닫음) · 그 밖은 공통 짝(draft ↔ confirmed · → cancelled · shipped ↔ fulfilled)
--   ⑦ so_invoice_issue — 묶음에 서비스 오더가 있고 오더가 둘 이상이면 거부(늘 따로) · 다른 줄 무변
--   ⑧ so_pos_confirm · so_pos_reopen — 서비스 오더는 거부(확정 = so_service_confirm · 풀기 = so_unconfirm)
--   channel 을 글자로 박은 함수(svc-0 §1-7 · 2026-10-21 다시 grep · 20): 바꾼 것 = so_create · so_status_guard · so_pos_confirm · so_pos_reopen ·
--     그대로(service 가 자동으로 막히거나 빠진다) = so_allocate_run · so_confirm · so_divide · so_hold · so_merge · so_picked_up · so_release_to_wms · so_wms_status(<> 'warehouse' 거부) ·
--     so_backorder_demand · so_backorder_overview · so_demand_flag_set · so_pos_open_list(= 'warehouse' / = 'pos' 거름) · so_ship · so_pos_complete(in ('pos','counter') — service 는 안 탄다 · so_pos_finish · so_counter_ship 이 길을 먼저 거른다) ·
--     so_stock_short_list · inv_post_sale(읽기만) · wms_order_doc(채널 칸 그대로 · 서비스 오더는 at_wms 에 못 가 WMS 목록에 안 뜬다)
--   ⚠️ 재발행 8 의 몸 = DB 원문 바이트 + 더한 · 바꾼 줄만(착지 do 블록이 md5 로 단언) · 그 밖 무접촉 · 운영에는 닿지 않는다(가드).

create temp table svc1b_before as
select (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname in ('so_confirm', 'so_unconfirm', 'so_confirm_precheck', 'so_ship', 'so_pos_complete', 'so_pos_finish', 'so_counter_ship', 'so_finalize', 'so_invoice_cancel', 'so_invoice_reissue', 'so_cancel',
                           'so_charge_set', 'so_charge_remove', 'so_merge', 'so_split', 'so_divide', 'so_hold', 'so_release_to_wms', 'so_wms_status', 'so_picked_up', 'so_allocate_run', 'so_backorder_demand', 'so_backorder_overview', 'so_demand_flag_set', 'so_pos_open_list', 'so_tax_preview', 'so_copy_customer', 'so_require_draft')) as others,
       (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname in ('so_create', 'so_status_guard', 'so_line_add', 'so_lines_paste', 'so_charge_gate', 'so_invoice_issue', 'so_pos_confirm', 'so_pos_reopen')) as acls,
       (select string_agg(conname || ':' || pg_get_constraintdef(oid), ' ' order by conname) from pg_constraint where conrelid = 'public.so'::regclass and contype = 'c' and conname <> 'so_channel_ck') as other_checks,
       (select string_agg(tgname || '→' || tgfoid::regproc::text, ' ' order by tgname) from pg_trigger where tgrelid = 'public.so'::regclass and not tgisinternal) as so_triggers;

-- ═══ ① 길 넷 — so_channel_ck ═══
alter table public.so drop constraint so_channel_ck;
alter table public.so add constraint so_channel_ck check (channel in ('warehouse', 'pos', 'counter', 'service'));
comment on column public.so.channel is '오더가 가는 길(6-b): warehouse(픽 · 팩 · WMS) · pos(계산대) · counter(선반 · manager) · service(svc-1b 판정 590: 상품 줄 없이 서비스 줄만 · WMS 없이 so_service_confirm → so_service_invoice · 인보이스 늘 따로)';

-- ═══ so_create 재발행 — 원본 20261011003000_ord_1a2_shop_order_process.sql:67 바이트 + 더한 · 바꾼 줄만 · svc-1b ═══
CREATE OR REPLACE FUNCTION public.so_create(p_customer_id uuid, p_channel text DEFAULT 'warehouse'::text, p_intake text DEFAULT 'manual'::text, p_location_id uuid DEFAULT NULL::uuid, p_comments text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff  uuid;
  c        public.customer%rowtype;
  v_wh     public.ref_warehouse%rowtype;
  v_so     public.so%rowtype;
  v_copy   jsonb;
  v_warn   text[] := '{}';
  od       record;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 유일한 문 — 첫 줄
  v_staff := public.so_current_staff();

  if p_channel is null or p_channel not in ('warehouse', 'pos', 'counter', 'service') then            -- ④a2: 길 셋(6-b) · svc-1b 판정 590 · 594: 길 넷 — service(상품 줄 없이 서비스 줄만 · intake manual · 창고 = 손님 기본 · WMS 없이 so_service_confirm → so_service_invoice)
    raise exception 'Channel % is not one of warehouse, pos, counter, service — nothing was saved', coalesce(p_channel, 'null');
  end if;
  if p_intake is null or p_intake not in ('manual', 'csv', 'pos', 'shopify') then                                   -- ord-1a2: shopify 는 시스템 창구(shop_order_process)가 준다
    raise exception 'Intake % is not accepted here — manual, csv, pos or shopify — nothing was saved', coalesce(p_intake, 'null');
  end if;
  if p_intake = 'shopify' and p_channel <> 'warehouse' then                                                          -- ord-1a2: 웹 오더는 창고 길(6-b)
    raise exception 'A shopify order is a warehouse order (channel warehouse) — nothing was saved';
  end if;
  if (p_channel = 'pos') <> (p_intake = 'pos') then                                                     -- ④a2 ⬜3: pos ⇔ intake pos · counter → manual
    raise exception 'Channel % goes with intake % — a pos order has intake pos, a counter order has intake manual — nothing was saved', p_channel, p_intake;
  end if;
  if p_channel in ('pos', 'counter') and p_location_id is null then                                     -- ④a2 ⬜3: 계산대·선반이 있는 창고
    raise exception 'A % order needs the store warehouse (p_location_id) — nothing was saved', p_channel;
  end if;

  select * into c from public.customer where id = p_customer_id;
  if not found then
    raise exception 'Customer not found — nothing was saved';
  end if;
  if not c.is_active then                                       -- 판정 A — 막는다
    raise exception 'Customer % is inactive — reactivate it first — nothing was saved', c.name;
  end if;
  if c.currency_id is null then
    raise exception 'Customer % has no currency — set it on the customer first — nothing was saved', c.name;
  end if;

  if p_location_id is not null then
    select * into v_wh from public.ref_warehouse where id = p_location_id;
    if not found then
      raise exception 'Warehouse not found — nothing was saved';
    end if;
    if not v_wh.is_active then
      raise exception 'Warehouse % is inactive — nothing was saved', v_wh.name;
    end if;
  end if;

  -- so 한 행 — so_number 는 기본값 so_next_number() · status 기본 draft(so_status_guard 가 insert 를 본다) · currency 는 손님 것(so_copy_customer 가 다시 덮는다)
  insert into public.so (customer_id, channel, intake, currency_id, location_id, location_name, comments, created_by, updated_by)
  values (c.id, p_channel, p_intake, c.currency_id, v_wh.id, v_wh.name, nullif(trim(p_comments), ''), v_staff, v_staff)
  returning * into v_so;

  -- 손님 값 복사(①a · 준 창고가 있으면 그대로 · 없으면 손님 default_location) — 티어는 손님 기본(판정 B ①)
  v_copy := public.so_copy_customer(v_so.id, c.id);

  -- 오더 전체 할인(D6 · ⬜4) — 손님·오더 날짜로 찾아 굳힌다(source deal) · 없으면 null 셋 · dsc-3a 판정 308: 굳히는 일은 so_order_discount_apply 한 곳(줄이 없어 금액 단계는 줄이 들어오며 트리거가 고른다)
  v_so := public.so_order_discount_apply(v_so.id, v_staff);

  select array_agg(t.v) into v_warn from jsonb_array_elements_text(v_copy->'warnings') as t(v);
  v_warn := coalesce(v_warn, '{}') || public.so_tier_warnings(v_so);

  return jsonb_build_object(
    'id',            v_so.id,
    'so_number',     v_so.so_number,
    'status',        v_so.status,
    'channel',       v_so.channel,
    'intake',        v_so.intake,
    'customer_id',   v_so.customer_id,
    'currency_code', v_so.currency_code,
    'price_tier',    v_so.price_tier,
    'price_tier_id', v_so.price_tier_id,
    'location_id',   v_so.location_id,
    'location_name', v_so.location_name,
    'order_discount_pct',     v_so.order_discount_pct,
    'order_discount_deal_id', v_so.order_discount_deal_id,
    'tax_rule',      v_so.tax_rule,
    'tax_rule_id',   v_so.tax_rule_id,
    'tax_rule_manual', v_so.tax_rule_manual,
    'ship_to_is_company', v_copy->'ship_to_is_company',
    'warnings',      to_jsonb(v_warn));
end;
$function$;

-- ═══ so_status_guard 재발행 — 원본 20260926192314_wms_5_2a1_so_pairs_release_batch.sql:66 바이트 + 더한 · 바꾼 줄만 · svc-1b ═══
CREATE OR REPLACE FUNCTION public.so_status_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ok boolean := false;
begin
  if tg_op = 'INSERT' then
    if new.status is distinct from 'draft' then
      raise exception 'A new order must start as draft (got %) — nothing was saved', new.status;
    end if;
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;                                   -- status 그대로 — 머리 고치기 · 줄 수 반영 등은 지나간다
  end if;

  -- 허락 짝 목록 — ② 확정·할당(⬜3) 넷 + ③a 출고(2026-09-24 · ⬜5): packed→shipped(so_ship 의 CAS 플립 · warehouse 길)
  --   ⓑ2 2026-09-24: shipped→fulfilled(so_invoice_issue · 판정 1 발행이 곧 끝) · fulfilled→shipped(so_invoice_cancel · 8-h 하향) — ⓐ1 의 shipped→invoiced · invoiced→shipped 를 대신한다
  --   ④ POS·counter(confirmed→shipped) · ⑤ Release to WMS · WMS 사건(at_wms · picking · packed · 내려가는 짝 · 6-g′ ⬜) 이 여기에 더한다
  v_ok := (old.status, new.status) in (('draft','confirmed'), ('confirmed','draft'), ('confirmed','cancelled'), ('draft','cancelled'), ('packed','shipped'),
                                        ('shipped','fulfilled'), ('fulfilled','shipped'),
                                        ('confirmed','at_wms'), ('at_wms','confirmed'), ('at_wms','picking'), ('picking','at_wms'), ('picking','packed'), ('packed','picking'))   -- ⑤-2a1 2026-09-26: WMS 짝 여섯(판정 17 · 21 — at_wms→cancelled · picking→cancelled 없음)
          or (old.status = 'confirmed' and new.status = 'shipped' and new.channel in ('pos', 'counter', 'service'));   -- ④a2 2026-09-25: pos·counter 는 confirmed 에서 나간다(7-c · 6-g′ 길별 짝) · warehouse 는 여전히 거부 · svc-1b 판정 595: service 도(so_service_invoice)
  if new.channel = 'service' and new.status in ('at_wms', 'picking', 'packed') then v_ok := false; end if;   -- svc-1b: 서비스 오더는 창고 길(WMS · 픽 · 팩)로 못 간다 — 공통 짝 confirmed→at_wms 를 service 에는 닫는다

  if not v_ok then
    raise exception 'Order % cannot move from % to % this way — use the order actions — nothing was saved',
      old.so_number, old.status, new.status;
  end if;
  return new;
end;
$function$;

-- ═══ so_line_add 재발행 — 원본 20261020123910_ln_1_paste_price_lines_clear_price_set_by.sql:43 바이트 + 더한 · 바꾼 줄만 · svc-1b ═══
CREATE OR REPLACE FUNCTION public.so_line_add(p_so_id uuid, p_product_id uuid, p_qty numeric, p_unit_price numeric DEFAULT NULL::numeric, p_discount_pct numeric DEFAULT NULL::numeric, p_free_reason text DEFAULT NULL::text, p_comments text DEFAULT NULL::text, p_force_new boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff    uuid;
  v_so       public.so%rowtype;
  p          public.product%rowtype;
  v_unit_nm  text;
  q          record;
  v_list     numeric;  v_disc numeric;  v_unit numeric;  v_src text;  v_dsrc text;  v_deal uuid;
  v_override boolean := false;
  v_manual   boolean := false;                                  -- 들어오는 줄을 사람이 정했나(단가 또는 할인)
  v_reason   text;  v_comments text;
  v_match    public.so_line%rowtype;
  v_line     public.so_line%rowtype;
  v_others   jsonb;
  v_next     int;
  v_warn     text[] := '{}';
  v_combo    boolean := false;   v_nchild int := 0;                 -- asm-2a(판정 244 · 묶음 2): 콤보 SKU 면 콤보 줄 + 구성품 줄
  v_base     public.product%rowtype;  v_converted jsonb := null;    -- dsc-1 판정 281 · 292 · 293: 안 파는 세트 → 낱개 바꾸기
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');
  if v_so.channel = 'service' then                                                                                -- svc-1b 판정 590: 서비스 오더는 서비스 줄만(상품 줄 없음)
    raise exception 'Order % is a service order — it takes service lines only (Add a service), not products — nothing was saved', v_so.so_number;
  end if;

  if p_qty is null or p_qty <= 0 then
    raise exception 'Quantity must be a positive number — nothing was saved';
  end if;
  select * into p from public.product where id = p_product_id;
  if not found then
    raise exception 'Product not found — nothing was saved';
  end if;
  if not p.is_active then                                       -- ⬜5 — 되묻지 않고 거부
    raise exception 'Product % is inactive — nothing was saved', p.sku;
  end if;
  -- dsc-1 판정 281(판매 가능) · 292 · 293 — 안 파는 세트는 낱개 × pack_factor 로 바꿔 넣고 알린다 · 바뀐 낱개도 같은 검사(안 팜이면 거부) · 안 파는 낱개 · 콤보는 거부(콤보는 바꿀 낱개가 없다)
  if p.parent_product_id is not null and not p.sellable then
    if p_unit_price is not null or p_discount_pct is not null then                         -- 판정 292: 세트 단가 · 할인을 낱개에 그대로 쓰면 12배 틀린다 · 시스템 견적 길만 바꾼다
      raise exception 'Set % is not sold as a set — enter the base SKU % with its own price — nothing was saved', p.sku, (select x.sku from public.product x where x.id = p.parent_product_id);
    end if;
    select * into v_base from public.product where id = p.parent_product_id;
    if not found then raise exception 'Set % has no base product — nothing was saved', p.sku; end if;
    if not v_base.is_active then raise exception 'Set % is not sold as a set and its base % is inactive — nothing was saved', p.sku, v_base.sku; end if;
    if not v_base.sellable then raise exception 'Set % is not sold as a set and its base % is not for sale — turn on Sellable in Products first — nothing was saved', p.sku, v_base.sku; end if;
    if p.pack_factor is null or p.pack_factor <= 0 then raise exception 'Set % has no pack_factor — nothing was saved', p.sku; end if;
    v_converted := jsonb_build_object('set_sku', p.sku, 'base_sku', v_base.sku, 'set_qty', p_qty, 'base_qty', p_qty * p.pack_factor, 'pack_factor', p.pack_factor);
    p_qty := p_qty * p.pack_factor;                                                          -- 이 뒤는 낱개 줄 넣기 그대로(견적 · 합치기 · 저장)
    p := v_base;
    v_warn := array_append(v_warn, 'set_converted_to_base');
  elsif not p.sellable then
    raise exception 'Product % is not for sale — turn on Sellable in Products first — nothing was saved', p.sku;
  end if;
  v_unit_nm := coalesce((select u.name from public.ref_unit u where u.id = p.unit_id), p.uom_name);
  v_combo := public.so_combo_is(p.id);

  -- 가격 — 창구 + 할인 식 한 곳(수량 포함 · 딜)
  select * into q from public.so_line_quote(v_so, p.id, p_qty);
  v_list := q.list_price;  v_disc := q.discount_pct;  v_unit := q.unit_price;  v_src := q.price_source;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;

  if p_discount_pct is not null and p_unit_price is not null then
    raise exception 'Give either a unit price or a discount, not both — nothing was saved';
  end if;
  if p_discount_pct is not null then                            -- 수동 할인 — 손님 기본·딜 대신(source manual · 다시 매기기가 건드리지 않는다)
    if p_discount_pct < 0 or p_discount_pct > 100 then
      raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
    end if;
    v_disc := p_discount_pct;
    v_unit := case when v_list is null then null else v_list * (1 - v_disc / 100) end;
    v_dsrc := 'manual';  v_deal := null;  v_manual := true;
  end if;
  if p_unit_price is not null then                              -- 덮어쓰기 — list_price 는 남긴다(받았을 금액 · 판정 2) · discount_pct·출처는 뜻이 없어 null(짝 CHECK)
    if p_unit_price < 0 then
      raise exception 'Unit price cannot be negative — nothing was saved';
    end if;
    v_unit := p_unit_price;  v_override := true;  v_disc := null;  v_dsrc := null;  v_deal := null;  v_manual := true;
  end if;

  -- 무상(판정 2 · ⬜7) — CHECK 가 마지막 문이지만 여기서 사람이 읽는 말로 먼저
  v_reason   := nullif(trim(p_free_reason), '');
  v_comments := nullif(trim(p_comments), '');
  if v_unit is not distinct from 0 and v_reason is null then
    raise exception 'A free line (price 0) needs a reason — sample, promotion, replacement or other — nothing was saved';
  end if;
  if v_reason is not null and v_unit is distinct from 0 then
    raise exception 'A free-goods reason needs a unit price of 0 — nothing was saved';
  end if;
  if v_reason is not null and v_reason not in ('sample', 'promotion', 'replacement', 'other') then
    raise exception 'Free reason % is not one of sample, promotion, replacement, other — nothing was saved', v_reason;
  end if;
  if v_reason = 'other' and v_comments is null then
    raise exception 'Reason other needs a comment — nothing was saved';
  end if;

  -- 같은 SKU(판정 2) — ① 들어오는 줄이 시스템이면 같은 제품의 시스템 줄과 제품만으로 합치고 합친 수량으로 다시 견적
  --                    ② 그 밖은 단가 비교 · 같으면 합침(시스템 줄이면 다시 견적 · 사람이 정한 줄이면 수량만) · 다르면 ask · p_force_new 면 그냥 새 줄
  if not p_force_new then
    if not v_manual then
      select * into v_match from public.so_line l
      where l.so_id = p_so_id and l.product_id = p.id and l.combo_line_id is null and not l.price_override and l.discount_source is distinct from 'manual'   -- asm-2a: 구성품 줄에는 합치지 않는다
      order by l.line_no limit 1;
      if found then
        v_line := public.so_line_requote(v_match.id, v_match.qty_ordered + p_qty);
        if v_combo then perform public.so_combo_children_sync(v_line.id, v_staff); end if;                                    -- asm-2a(묶음 3): 구성품 줄이 따라간다
        if v_comments is not null then v_warn := array_append(v_warn, 'comments_not_merged'); end if;
        if v_line.unit_price is null then v_warn := array_append(v_warn, 'no_price'); end if;
        if v_line.deal_line_id is not null and public.so_deal_line_ended(v_line.deal_line_id, public.ims_today()) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
        return jsonb_build_object('action', 'merged', 'requoted', true, 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                                  'total', public.so_line_total(v_line), 'warnings', to_jsonb(v_warn), 'converted', v_converted, 'components', public.so_combo_children_json(v_line.id));
      end if;
    end if;
    select * into v_match from public.so_line l
    where l.so_id = p_so_id and l.product_id = p.id and l.combo_line_id is null and l.unit_price is not distinct from v_unit                                -- asm-2a: 구성품 줄에는 합치지 않는다
    order by l.line_no limit 1;
    if found then
      if not v_match.price_override and v_match.discount_source is distinct from 'manual' then
        v_line := public.so_line_requote(v_match.id, v_match.qty_ordered + p_qty);     -- 시스템 줄에 합쳐졌다 → 시스템 규칙(수량이 바뀌면 다시 견적)
      else
        update public.so_line set qty_ordered = qty_ordered + p_qty, updated_by = v_staff
        where id = v_match.id returning * into v_line;                                 -- 사람이 정한 줄 → 수량만
      end if;
      if v_combo then perform public.so_combo_children_sync(v_line.id, v_staff); end if;                                      -- asm-2a(묶음 3)
      if v_comments is not null then v_warn := array_append(v_warn, 'comments_not_merged'); end if;
      if v_line.unit_price is null then v_warn := array_append(v_warn, 'no_price'); end if;
      return jsonb_build_object('action', 'merged', 'requoted', not v_line.price_override and v_line.discount_source is distinct from 'manual', 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                                'total', public.so_line_total(v_line), 'warnings', to_jsonb(v_warn), 'converted', v_converted, 'components', public.so_combo_children_json(v_line.id));
    end if;
    select jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'qty_ordered', l.qty_ordered,
                                        'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'price_override', l.price_override) order by l.line_no)
      into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = p.id and l.combo_line_id is null;                                      -- asm-2a: 구성품 줄은 「같은 SKU」가 아니다
    if v_others is not null then
      return jsonb_build_object('action', 'ask', 'so_number', v_so.so_number, 'product_id', p.id, 'sku', p.sku,
        'proposed', jsonb_build_object('qty_ordered', p_qty, 'list_price', v_list, 'discount_pct', v_disc, 'discount_source', v_dsrc, 'unit_price', v_unit, 'price_override', v_override),
        'existing', v_others,
        'converted', v_converted,                                                                                                  -- dsc-1 판정 293
        'message', 'Same SKU is already on this order at a different price — change that line (so_line_update) or add as a new line (p_force_new) — nothing was saved');
    end if;
  end if;

  select coalesce(max(line_no), 0) + 1 into v_next from public.so_line where so_id = p_so_id;
  insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                              list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason, tax_rule, comments, updated_by,
                              surcharge_pct, surcharge_amount, surcharge_label, price_set_by, price_set_at)                                                                                    -- surcharge-4a(묶음 3): 그 상품의 켜진 그룹 값 · 무상이면 비움(판정 228) · 합치기 길은 손대지 않는다(판정 229)
  select p_so_id, v_next, p.id, p.sku, p.name, v_unit_nm, coalesce(p.pack_factor, 1), p_qty,
          v_list, v_disc, v_unit, v_override, v_dsrc, v_deal, v_reason, v_so.tax_rule, v_comments, v_staff,
          d.surcharge_pct, d.surcharge_amount, d.surcharge_label,
          case when v_manual then v_staff end, case when v_manual then now() end                                                                         -- ln-1 판정 546
  from public.so_line_surcharge_defaults(p.id, v_reason is not null) d
  returning * into v_line;
  if v_combo then v_nchild := public.so_combo_children_insert(v_line, v_staff); end if;                                     -- asm-2a(묶음 2): 구성품 줄 = 콤보 수량 × 정의 수량 · 값 0 · 콤보 줄에 매달린다
  if v_unit is null then v_warn := array_append(v_warn, 'no_price'); end if;
  if v_deal is not null and public.so_deal_line_ended(v_deal, public.ims_today()) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;

  return jsonb_build_object('action', 'added', 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                            'total', public.so_line_total(v_line), 'price_source', v_src, 'warnings', to_jsonb(v_warn), 'converted', v_converted, 'components', public.so_combo_children_json(v_line.id));
end;
$function$;

-- ═══ so_lines_paste 재발행 — 원본 20261020123910_ln_1_paste_price_lines_clear_price_set_by.sql:887 바이트 + 더한 · 바꾼 줄만 · svc-1b ═══
CREATE OR REPLACE FUNCTION public.so_lines_paste(p_so_id uuid, p_lines jsonb, p_commit boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_limit    constant int := 500;
  v_staff    uuid;
  v_so       public.so%rowtype;
  v_n        int;
  v_next     int;
  r          record;
  v_sku      text;
  v_qty      numeric;
  v_pid uuid;  v_psku text;  v_pname text;  v_pactive boolean;  v_uom text;  v_unit_id uuid;  v_pack numeric;
  v_verdict  text;
  v_msgs     text[];
  v_dup_of   int;
  v_idx      int;
  i          int;
  -- 제품별로 모은 것(입력 순 · 첫 줄 번호가 대표)
  a_pid uuid[] := '{}';  a_n int[] := '{}';  a_qty numeric[] := '{}';  a_sku text[] := '{}';  a_name text[] := '{}';  a_unit text[] := '{}';  a_pack numeric[] := '{}';
  q          record;
  v_list numeric;  v_disc numeric;  v_unit numeric;  v_src text;  v_dsrc text;  v_deal uuid;
  v_match    public.so_line%rowtype;
  v_others   int;
  v_line_no  int;
  v_inserted boolean;  v_updated boolean;
  v_rows     jsonb := '[]'::jsonb;
  n_ok int := 0;  n_noprice int := 0;  n_merged int := 0;  n_ask int := 0;  n_dup int := 0;  n_nf int := 0;  n_inactive int := 0;  n_bad int := 0;  n_ins int := 0;  n_upd int := 0;
  v_combo    boolean;  v_ncomp int;  v_new_id uuid;                 -- asm-2a(판정 244 · 묶음 2): 콤보 SKU 면 콤보 줄 + 구성품 줄(미리 보기도 줄 번호를 같이 센다)
  v_psell boolean;  v_pparent uuid;  v_conv jsonb;  v_bid uuid;  v_bsku text;  v_bname text;  v_bactive boolean;  v_buom text;  v_bunit uuid;  v_bpack numeric;  v_bsell boolean;  n_conv int := 0;  n_ns int := 0;   -- dsc-1 판정 281 · 293
  v_price numeric;  v_has_price boolean;  a_price numeric[] := '{}';  v_res jsonb;  n_badp int := 0;  n_freep int := 0;  n_setp int := 0;  n_priced int := 0;   -- ln-1 판정 532 · 545: 줄마다 가격(선택) · 가격 묶음은 so_line_add 로
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');
  if v_so.channel = 'service' then                                                                                -- svc-1b 판정 590: 서비스 오더는 서비스 줄만(상품 줄 없음)
    raise exception 'Order % is a service order — it takes service lines only (Add a service), not products — nothing was saved', v_so.so_number;
  end if;

  v_n := coalesce(jsonb_array_length(p_lines), 0);
  if v_n > c_limit then
    return jsonb_build_object(
      'so_id', p_so_id, 'so_number', v_so.so_number, 'committed', false,
      'summary', jsonb_build_object('total', v_n, 'ok', 0, 'no_price', 0, 'merged', 0, 'ask', 0, 'duplicate', 0, 'not_found', 0, 'inactive', 0, 'bad_qty', 0,
                                    'converted', 0, 'not_sellable', 0, 'bad_price', 0, 'free_price', 0, 'set_price_refused', 0, 'priced', 0,
                                    'inserted', 0, 'updated', 0, 'too_many', true, 'limit', c_limit,
                                    'message', format('Too many lines (%s) — up to %s lines per paste. Nothing was saved.', v_n, c_limit)),
      'lines', '[]'::jsonb);
  end if;

  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_so_id;

  -- 1) 입력 → 제품 · 같은 제품은 첫 줄에 수량을 모은다
  for r in
    select t.ord::int as n, t.e->>'sku' as sku_raw, t.e->>'qty' as qty_raw, t.e->>'price' as price_raw   -- ln-1
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality as t(e, ord)
    order by t.ord
  loop
    v_pid := null; v_psku := null; v_pname := null; v_pactive := null; v_uom := null; v_unit_id := null; v_pack := null;
    v_verdict := null; v_msgs := '{}'; v_dup_of := null; v_idx := null;
    v_conv := null;
    v_price := null; v_has_price := nullif(btrim(coalesce(r.price_raw, '')), '') is not null;                                              -- ln-1 판정 545: 없거나 빈 글자 = 원래 가격

    -- SKU 다듬기 — 앞뒤 공백(비분리 공백 포함)만 · po_lines_paste 와 같은 정규식(바이트 그대로)
    v_sku := nullif(regexp_replace(coalesce(r.sku_raw, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
    -- 수량 — 숫자만
    v_qty := case when r.qty_raw ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then r.qty_raw::numeric else null end;

    if v_sku is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'empty_sku');
    else
      select p.id, p.sku, p.name, p.is_active, p.uom_name, p.unit_id, p.pack_factor into v_pid, v_psku, v_pname, v_pactive, v_uom, v_unit_id, v_pack
      from public.product p where p.sku = v_sku;                                  -- 유니크 인덱스
      if v_pid is null then
        select p.id, p.sku, p.name, p.is_active, p.uom_name, p.unit_id, p.pack_factor into v_pid, v_psku, v_pname, v_pactive, v_uom, v_unit_id, v_pack
        from public.product p where upper(p.sku) = upper(v_sku) limit 1;         -- 폴백 · 못 찾은 줄에만
        if v_pid is not null then v_msgs := array_append(v_msgs, 'case_fixed'); end if;
      end if;
    end if;

    if v_verdict is null and v_pid is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'sku_not_in_product');
    end if;
    if v_verdict is null and v_pactive is false then
      v_verdict := 'inactive'; v_msgs := array_append(v_msgs, 'inactive_product — not added');
    end if;
    if v_verdict is null and (v_qty is null or v_qty <= 0) then
      v_verdict := 'bad_qty'; v_msgs := array_append(v_msgs, 'qty_must_be_positive_number');
    end if;
    -- ln-1 판정 532 · 545: 가격 — 숫자만(수량과 같은 꼴 · 자리 수 한도 없음 = so_line_add) · 음수 · 글자 → bad_price · 0 → free_price(무상 줄은 사유가 필요하다 — Add line)
    if v_verdict is null and v_has_price then
      v_price := case when r.price_raw ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then r.price_raw::numeric else null end;
      if v_price is null or v_price < 0 then
        v_verdict := 'bad_price'; v_msgs := array_append(v_msgs, 'price_must_be_a_non_negative_number — not added');
      elsif v_price = 0 then
        v_verdict := 'free_price'; v_msgs := array_append(v_msgs, 'free lines: use Add line (a price of 0 needs a free-goods reason) — not added');
      end if;
    end if;
    -- dsc-1 판정 281 · 293 — 안 파는 세트는 낱개 × pack_factor 로 바꾼다(꼬리표 converted · duplicate 묶기 앞이라 같은 낱개 줄과 합쳐진다) · 안 파는 낱개(바뀐 것도)는 not_sellable · 콤보는 바꿀 낱개가 없어 not_sellable
    if v_verdict is null then
      select p.sellable, p.parent_product_id into v_psell, v_pparent from public.product p where p.id = v_pid;
      if v_pparent is not null and not v_psell and v_has_price then                                                                        -- ln-1 판정 292: 바꾸는 길에 손 단가 금지(세트 단가를 낱개에 쓰면 pack_factor 배 틀린다)
        v_verdict := 'set_price_refused'; v_msgs := array_append(v_msgs, format('set_%s_is_not_sold_as_a_set — paste the base SKU %s with its own price — not added', v_psku, coalesce((select x.sku from public.product x where x.id = v_pparent), '?')));
      elsif v_pparent is not null and not v_psell then
        select p.id, p.sku, p.name, p.is_active, p.uom_name, p.unit_id, p.pack_factor, p.sellable into v_bid, v_bsku, v_bname, v_bactive, v_buom, v_bunit, v_bpack, v_bsell from public.product p where p.id = v_pparent;
        if v_bid is null or not v_bactive then
          v_verdict := 'inactive'; v_msgs := array_append(v_msgs, format('set_%s_not_sold_as_set_and_base_%s_inactive — not added', v_psku, coalesce(v_bsku, '?')));
        elsif v_pack is null or v_pack <= 0 then
          v_verdict := 'bad_qty'; v_msgs := array_append(v_msgs, format('set_%s_has_no_pack_factor — not added', v_psku));
        else
          v_conv := jsonb_build_object('set_sku', v_psku, 'set_qty', v_qty, 'pack_factor', v_pack, 'base_sku', v_bsku, 'base_qty', v_qty * v_pack);
          v_msgs := array_append(v_msgs, format('converted_from_set_%s_x%s — %s × %s', v_psku, v_qty, v_bsku, v_qty * v_pack));
          v_qty := v_qty * v_pack;
          v_pid := v_bid; v_psku := v_bsku; v_pname := v_bname; v_pactive := v_bactive; v_uom := v_buom; v_unit_id := v_bunit; v_pack := v_bpack; v_psell := v_bsell;
        end if;
      end if;
      if v_verdict is null and not v_psell then
        v_verdict := 'not_sellable'; v_msgs := array_append(v_msgs, format('%s_not_for_sale — turn on Sellable in Products first — not added', v_psku));
      end if;
      if v_verdict is null and v_conv is not null then n_conv := n_conv + 1; end if;        -- 바뀌었다가 거부된 줄(바뀐 낱개가 안 팜)은 converted 수에 안 센다 · 꼬리표는 남아 「왜 거부됐나」를 보인다
    end if;

    if v_verdict is null then
      select s.i into v_idx from generate_subscripts(a_pid, 1) s(i) where a_pid[s.i] = v_pid and a_price[s.i] is not distinct from v_price limit 1;   -- ln-1: 묶기 열쇠 = (제품, 가격)
      if v_idx is not null then
        v_dup_of := a_n[v_idx];
        a_qty[v_idx] := a_qty[v_idx] + v_qty;
        v_verdict := 'duplicate';
        v_msgs := array_append(v_msgs, format('merged_into_paste_line_%s — quantities added', v_dup_of));
      elsif exists (select 1 from generate_subscripts(a_pid, 1) s(i) where a_pid[s.i] = v_pid) then                                                   -- ln-1: 같은 제품이 다른 가격으로 이미 이 붙여넣기에 있다 → 둘째부터 ask(미리 보기 = 저장)
        v_verdict := 'ask'; n_ask := n_ask + 1;
        v_msgs := array_append(v_msgs, 'same_sku_pasted_at_different_prices — paste one price per SKU or add separately — not added');
      else
        a_pid := array_append(a_pid, v_pid);  a_n := array_append(a_n, r.n);  a_qty := array_append(a_qty, v_qty);  a_price := array_append(a_price, v_price);
        a_sku := array_append(a_sku, v_psku);  a_name := array_append(a_name, v_pname);
        a_unit := array_append(a_unit, coalesce((select u.name from public.ref_unit u where u.id = v_unit_id), v_uom));
        a_pack := array_append(a_pack, v_pack);
      end if;
    end if;

    case v_verdict
      when 'not_found' then n_nf := n_nf + 1;
      when 'inactive'  then n_inactive := n_inactive + 1;
      when 'bad_qty'   then n_bad := n_bad + 1;
      when 'duplicate' then n_dup := n_dup + 1;
      when 'not_sellable' then n_ns := n_ns + 1;                   -- dsc-1
      when 'bad_price' then n_badp := n_badp + 1;                   -- ln-1
      when 'free_price' then n_freep := n_freep + 1;
      when 'set_price_refused' then n_setp := n_setp + 1;
      else null;
    end case;

    v_rows := v_rows || jsonb_build_object(
      'n', r.n, 'input_sku', r.sku_raw, 'input_qty', r.qty_raw, 'input_price', r.price_raw, 'price', v_price,   -- ln-1
      'verdict', v_verdict,                                      -- null = 2) 에서 정해진다
      'product_id', v_pid, 'sku', v_psku, 'product_name', v_pname, 'product_active', v_pactive,
      'qty', v_qty, 'line_no', null, 'inserted', false, 'updated', false,
      'converted', v_conv,                                        -- dsc-1 판정 293: 꼬리표(판정은 그대로 ok · merged · ask · no_price 로 끝난다)
      'message', array_to_string(v_msgs, ' · '));
  end loop;

  -- 2) 제품별 — 가격(수량 포함) · 기존 줄과 대조(판정 2) · 넣기(결과는 그 제품의 첫 입력 줄에 적는다)
  for i in 1 .. coalesce(array_length(a_pid, 1), 0) loop
    select * into q from public.so_line_quote(v_so, a_pid[i], a_qty[i]);
    v_list := q.list_price;  v_disc := q.discount_pct;  v_unit := q.unit_price;  v_src := q.price_source;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    v_line_no := null; v_inserted := false; v_updated := false; v_msgs := '{}';
    v_combo := public.so_combo_is(a_pid[i]);
    v_ncomp := case when v_combo then (select count(*) from public.product_bom b where b.parent_product_id = a_pid[i] and b.is_active) else 0 end;

    -- ln-1 판정 532 · 545: 가격 묶음 — ① 시스템 줄 합치기를 건너뛴다 · 사람이 정한 줄 가운데 같은 단가 → 수량만 · 같은 제품의 다른 줄(시스템 줄 · 같은 가격이어도)이 있으면 ask · 없으면 so_line_add(p_force_new) 가 새 줄
    if a_price[i] is not null then
      v_disc := null; v_dsrc := null; v_deal := null; v_unit := a_price[i]; v_src := 'paste';                                                   -- 반환 줄: 정가는 견적의 list(so_line_add 가 넣는 것과 같다) · 할인 없음 · 단가 = 그 가격
      n_priced := n_priced + 1;
      select * into v_match from public.so_line l
      where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null and (l.price_override or l.discount_source is not distinct from 'manual') and l.unit_price = a_price[i]
      order by l.line_no limit 1;
      if found then
        v_verdict := 'merged'; v_line_no := v_match.line_no;
        v_msgs := array_append(v_msgs, format('added_to_line_%s — same price you set', v_match.line_no));
        if p_commit then
          update public.so_line set qty_ordered = qty_ordered + a_qty[i], updated_by = v_staff where id = v_match.id;
          if v_combo then perform public.so_combo_children_sync(v_match.id, v_staff); end if;
          v_updated := true; n_upd := n_upd + 1;
        end if;
        n_merged := n_merged + 1;
      else
        select count(*) into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null;
        if v_others > 0 then
          v_verdict := 'ask';
          v_msgs := array_append(v_msgs, 'same_sku_already_on_this_order_at_another_price — pasted prices are final: change that line or add separately (so_line_add p_force_new)');
          n_ask := n_ask + 1;
        else
          v_verdict := 'ok'; n_ok := n_ok + 1;
          v_next := v_next + 1; v_line_no := v_next;
          v_next := v_next + v_ncomp;                                                                                                            -- 구성품 줄이 뒤따르는 번호(so_line_add 도 max + 1 · 구성품은 그 뒤)
          if p_commit then
            v_res := public.so_line_add(p_so_id, a_pid[i], a_qty[i], a_price[i], null, null, null, true);                                       -- 값 · surcharge · 콤보 구성품 · price_set_by 가 한 곳에서 난다
            v_new_id := (v_res->'line'->>'id')::uuid;
            if (v_res->'line'->>'line_no')::int <> v_line_no then raise exception 'Paste line %: line number mismatch (preview % · saved %) — nothing was saved', a_n[i], v_line_no, v_res->'line'->>'line_no'; end if;
            v_inserted := true; n_ins := n_ins + 1;
          end if;
        end if;
      end if;
    else
    -- ① 같은 제품의 시스템 줄 — 제품만으로 합치고 합친 수량으로 다시 견적
    select * into v_match from public.so_line l
    where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null and not l.price_override and l.discount_source is distinct from 'manual'   -- asm-2a: 구성품 줄에는 합치지 않는다
    order by l.line_no limit 1;
    if found then
      v_verdict := 'merged'; v_line_no := v_match.line_no;
      v_msgs := array_append(v_msgs, format('added_to_line_%s — requoted at %s', v_match.line_no, v_match.qty_ordered + a_qty[i]));
      if p_commit then
        perform public.so_line_requote(v_match.id, v_match.qty_ordered + a_qty[i]);
        if v_combo then perform public.so_combo_children_sync(v_match.id, v_staff); end if;                                 -- asm-2a(묶음 3)
        v_updated := true; n_upd := n_upd + 1;
      end if;
      n_merged := n_merged + 1;
    else
      -- ② 사람이 정한 줄 — 단가가 같으면 수량만 · 다르면 ask
      select * into v_match from public.so_line l
      where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null and l.unit_price is not distinct from v_unit                            -- asm-2a
      order by l.line_no limit 1;
      if found then
        v_verdict := 'merged'; v_line_no := v_match.line_no;
        v_msgs := array_append(v_msgs, format('added_to_line_%s', v_match.line_no));
        if p_commit then
          update public.so_line set qty_ordered = qty_ordered + a_qty[i], updated_by = v_staff where id = v_match.id;
          if v_combo then perform public.so_combo_children_sync(v_match.id, v_staff); end if;                               -- asm-2a(묶음 3)
          v_updated := true; n_upd := n_upd + 1;
        end if;
        n_merged := n_merged + 1;
      else
        select count(*) into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null;                 -- asm-2a: 구성품 줄은 「같은 SKU」가 아니다
        if v_others > 0 then
          v_verdict := 'ask';
          v_msgs := array_append(v_msgs, 'same_sku_at_different_price — use so_line_add to merge into that line or add separately (p_force_new)');
          n_ask := n_ask + 1;
        else
          if v_unit is null then
            v_verdict := 'no_price'; n_noprice := n_noprice + 1;
            v_msgs := array_append(v_msgs, 'no_price_for_this_tier — saved without a price; confirm will refuse until it has one');
          else
            v_verdict := 'ok'; n_ok := n_ok + 1;
          end if;
          if v_deal is not null and public.so_deal_line_ended(v_deal, public.ims_today()) then v_msgs := array_append(v_msgs, 'deal_ended_before_line_added'); end if;
          v_next := v_next + 1; v_line_no := v_next;
          v_next := v_next + v_ncomp;                                                                                                -- asm-2a: 구성품 줄이 뒤따르는 번호(미리 보기 · 저장 같게)
          if p_commit then
            insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                        list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason, tax_rule, comments, updated_by,
                                        surcharge_pct, surcharge_amount, surcharge_label)                                                                          -- surcharge-4a(묶음 3): 붙여 넣기도 같은 도우미(무상 줄은 이 길에 없다)
            select p_so_id, v_line_no, a_pid[i], a_sku[i], a_name[i], a_unit[i], coalesce(a_pack[i], 1), a_qty[i],
                    v_list, v_disc, v_unit, false, v_dsrc, v_deal, null, v_so.tax_rule, null, v_staff,
                    d.surcharge_pct, d.surcharge_amount, d.surcharge_label
            from public.so_line_surcharge_defaults(a_pid[i], false) d
            returning id into v_new_id;
            if v_combo then perform public.so_combo_children_insert((select l from public.so_line l where l.id = v_new_id), v_staff); end if;   -- asm-2a(묶음 2)
            v_inserted := true; n_ins := n_ins + 1;
          end if;
        end if;
      end if;
    end if;
    end if;                                                                                                                                       -- ln-1: 가격 묶음 / 가격 없는 묶음

    v_rows := coalesce((
      select jsonb_agg(
               case when (e->>'n')::int = a_n[i]
                    then e || jsonb_build_object('verdict', v_verdict, 'qty', a_qty[i], 'list_price', v_list, 'discount_pct', v_disc, 'discount_source', v_dsrc,
                                                 'unit_price', v_unit, 'price_source', v_src, 'line_no', v_line_no,
                                                 'inserted', v_inserted, 'updated', v_updated, 'message', array_to_string(v_msgs, ' · '), 'combo', v_combo, 'components', v_ncomp)   -- asm-2a
                    else e end
               order by (e->>'n')::int)
      from jsonb_array_elements(v_rows) e), '[]'::jsonb);
  end loop;

  return jsonb_build_object(
    'so_id', p_so_id, 'so_number', v_so.so_number, 'committed', p_commit,
    'summary', jsonb_build_object('total', v_n, 'ok', n_ok, 'no_price', n_noprice, 'merged', n_merged, 'ask', n_ask, 'duplicate', n_dup,
                                  'not_found', n_nf, 'inactive', n_inactive, 'bad_qty', n_bad,
                                  'converted', n_conv, 'not_sellable', n_ns, 'bad_price', n_badp, 'free_price', n_freep, 'set_price_refused', n_setp, 'priced', n_priced,   -- ln-1
                                  'inserted', n_ins, 'updated', n_upd, 'too_many', false, 'limit', c_limit, 'message', null),
    'lines', v_rows);
end;
$function$;

-- ═══ so_charge_gate 재발행 — 원본 20261020134522_ch_1_packed_charges.sql:36 바이트 + 더한 · 바꾼 줄만 · svc-1b ═══
CREATE OR REPLACE FUNCTION public.so_charge_gate(p_so_id uuid, p_verb text DEFAULT 'saved'::text)
 RETURNS so
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_so public.so%rowtype;
begin
  select * into v_so from public.so where id = p_so_id for update;                                                -- 잠금 — so_finalize 와 겹치면 뒤쪽이 상태를 다시 본다
  if not found then
    raise exception 'Order not found — nothing was %', p_verb;
  end if;
  if v_so.status = 'draft' then
    return v_so;                                                                                                   -- 판정 540: draft 는 지금 그대로(sales)
  end if;
  if v_so.channel = 'service' then                                                                                  -- svc-1b 판정 595: 서비스 오더의 서비스 줄은 draft 에서만 — 확정 뒤는 확정 풀기(so_unconfirm) · packed 갈래로 새지 않는다
    raise exception 'Order % is % — service lines change only while the order is a draft — unconfirm it first — nothing was %', v_so.so_number, v_so.status, p_verb;
  end if;
  if v_so.status <> 'packed' then                                                                                  -- 판정 539
    raise exception 'Order % is % — charges can be added or removed only on a draft or a packed order — nothing was %', v_so.so_number, v_so.status, p_verb;
  end if;
  if not public.ims_can_write('master') then                                                                      -- 판정 531 · 540
    raise exception 'Order % is packed — adding or changing charges after packing needs the master permission as well — nothing was %', v_so.so_number, p_verb;
  end if;
  if v_so.intake = 'shopify' then                                                                                  -- 판정 549: 스토어 종류로 가른다(결제 상태가 아니다)
    if not exists (select 1 from public.shop_order o where o.so_id = v_so.id) then
      raise exception 'Order % is a Shopify order but its store is unknown — nothing was %', v_so.so_number, p_verb;
    end if;
    if exists (select 1 from public.shop_order o join public.shop_store st on st.id = o.store_id where o.so_id = v_so.id and st.kind = 'aone') then
      raise exception 'Order % came from aonebeauty and was paid at checkout — charges cannot change after packing — nothing was %', v_so.so_number, p_verb;
    end if;
  end if;
  return v_so;
end;
$function$;

-- ═══ so_invoice_issue 재발행 — 원본 20261019155731_doc_1b2_ship_ready.sql:251 바이트 + 더한 · 바꾼 줄만 · svc-1b ═══
CREATE OR REPLACE FUNCTION public.so_invoice_issue(p_so_ids uuid[], p_staff uuid, p_issued_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_on       date := coalesce(p_issued_on, public.ims_today());
  v_n        int;
  v_cnt      int;
  v_bad      text;
  v_first    public.so%rowtype;
  v_so       public.so%rowtype;
  v_pt       public.ref_payment_term%rowtype;
  v_inv      public.so_invoice%rowtype;
  v_io       public.so_invoice_order%rowtype;
  v_prev     jsonb;
  v_rule_id  uuid;
  v_changed  boolean;
  v_rule     text;
  v_rate     numeric;
  v_ln       int := 0;
  v_lines_amt numeric := 0;  v_od_amt numeric := 0;  v_chg_amt numeric := 0;  v_tax numeric := 0;
  v_o_lines  numeric;  v_o_od numeric;  v_o_chg numeric;  v_o_tax numeric;
  v_sc_amt   numeric := 0;  v_o_sc numeric;  v_has_sc boolean;  v_sc_code text;  v_sc_acct public.ref_account%rowtype;   -- surcharge-2b(묶음 5 · 6)
  v_chd_amt  numeric := 0;  v_o_chd numeric;  v_has_fd boolean;  v_fd_code text;  v_fd_acct public.ref_account%rowtype;   -- fr-2 판정 352 · 358: 운임 할인 합 · 할인 줄 계정(inv_config so_freight_discount_account_code · 기본 _6_)
  v_orders   jsonb := '[]'::jsonb;
  v_warn     text[] := '{}';
  e          jsonb;
  -- ⓑ2 자동 붙이기
  v_total    numeric;
  v_deposit  numeric := 0;
  v_balance  numeric := 0;
  v_applied  jsonb := '[]'::jsonb;
  v_a        public.so_payment_alloc%rowtype;
  v_plan     jsonb;                                                                     -- doc-1b2: 자동 붙이기 계획(so_invoice_apply_plan · 미리 보기와 같은 식)
  -- ⓒ2 크레딧부터(8-e · 판정 5)
  v_credit   numeric := 0;
  v_ca       public.so_credit_alloc%rowtype;
begin
  if p_staff is null then raise exception 'so_invoice_issue needs the acting staff id — nothing was saved'; end if;
  if v_on > public.ims_today() then raise exception 'Invoice date % is in the future — nothing was saved', v_on; end if;
  v_cnt := coalesce(array_length(p_so_ids, 1), 0);
  if v_cnt = 0 then raise exception 'An invoice needs at least one order — nothing was saved'; end if;
  select count(distinct x) into v_n from unnest(p_so_ids) x;
  if v_n <> v_cnt then raise exception 'The same order is listed twice — nothing was saved'; end if;

  -- 잠금(번호 순) · 존재 · 상태 · 이미 담김 · 청구처 · 통화
  perform s.id from public.so s where s.id = any(p_so_ids) order by s.so_number for update;
  select count(*) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n <> v_cnt then raise exception 'Order not found — nothing was saved'; end if;
  select string_agg(s.so_number || ' (' || s.status || ')', ', ' order by s.so_number) into v_bad
  from public.so s where s.id = any(p_so_ids) and (s.status <> 'shipped' or s.shipped_at is null);
  if v_bad is not null then raise exception 'Only shipped orders can be invoiced — % — nothing was saved', v_bad; end if;
  select string_agg(s.so_number || ' is on invoice ' || i.invoice_number, ', ' order by s.so_number) into v_bad
  from public.so_invoice_order o join public.so s on s.id = o.so_id join public.so_invoice i on i.id = o.invoice_id
  where o.so_id = any(p_so_ids) and o.cancelled_at is null;
  if v_bad is not null then raise exception 'Order already invoiced — % — cancel that invoice first — nothing was saved', v_bad; end if;
  select string_agg(s.so_number, ', ' order by s.so_number) into v_bad from public.so s where s.id = any(p_so_ids) and s.bill_to_customer_id is null;
  if v_bad is not null then raise exception 'Order % has no bill-to customer — nothing was saved', v_bad; end if;
  select count(distinct s.bill_to_customer_id) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One invoice bills one customer — these orders have different bill-to customers, split them — nothing was saved'; end if;
  select count(distinct s.currency_id) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One invoice has one currency — these orders have different currencies, split them — nothing was saved'; end if;
  if v_cnt > 1 and exists (select 1 from public.so s where s.id = any(p_so_ids) and s.channel = 'service') then                    -- svc-1b 판정 590(대화 Claude 결정 · 늘 따로): 서비스 오더 하나 = 인보이스 한 장 — 물건 오더와도 · 다른 서비스 오더와도 안 묶는다
    select string_agg(s.so_number, ', ' order by s.so_number) into v_bad from public.so s where s.id = any(p_so_ids) and s.channel = 'service';
    raise exception 'A service order is invoiced on its own (one service order, one invoice) — take % out of this batch — nothing was saved', v_bad;
  end if;

  select * into v_first from public.so s where s.id = any(p_so_ids) order by s.so_number limit 1;
  perform 1 from public.customer c where c.id = v_first.bill_to_customer_id for update;   -- ⓑ2: 청구처 손님 행 잠금(잔액 검사 직렬화 · so_payment_* 창구와 같은 자물쇠)

  -- 결제조건 · 기한(판정 10)
  if v_first.payment_term_id is not null then
    select * into v_pt from public.ref_payment_term t where t.id = v_first.payment_term_id;
  end if;
  if v_pt.id is null then
    v_warn := v_warn || array['payment_term_missing', 'due_date_unknown'];
  elsif v_pt.net_days is null then
    v_warn := array_append(v_warn, 'due_date_unknown');
  end if;
  if coalesce(v_pt.is_split, false) then v_warn := array_append(v_warn, 'split_terms'); end if;
  if (select count(distinct coalesce(s.payment_term_id::text, '')) from public.so s where s.id = any(p_so_ids)) > 1 then v_warn := array_append(v_warn, 'payment_term_differs'); end if;
  if exists (select 1 from public.so s where s.id = any(p_so_ids)
              and (s.bill_to_name, s.bill_to_line1, s.bill_to_line2, s.bill_to_city, s.bill_to_state_province, s.bill_to_postal_code, s.bill_to_country)
                  is distinct from (v_first.bill_to_name, v_first.bill_to_line1, v_first.bill_to_line2, v_first.bill_to_city, v_first.bill_to_state_province, v_first.bill_to_postal_code, v_first.bill_to_country)) then
    v_warn := array_append(v_warn, 'bill_to_differs');
  end if;

  -- surcharge 계정(surcharge-2b · 묶음 6) — 담긴 오더에 보낸 surcharge 줄이 있으면 ⭐ 머리 insert(번호를 당긴다) 앞에서 계정을 잡는다 · 비었거나 · 없거나 · 꺼졌으면 surcharge 있는 발행만 막는다 · 없는 발행은 지금처럼
  select exists (select 1 from public.so_line l where l.so_id = any(p_so_ids) and l.surcharge_label is not null and l.qty_shipped > 0) into v_has_sc;
  if v_has_sc then
    select nullif(k.value, '') into v_sc_code from public.inv_config k where k.key = 'so_surcharge_account_code';
    if v_sc_code is null then raise exception 'Surcharge account is not set — set inv_config so_surcharge_account_code (e.g. _94_) before invoicing an order with a surcharge — nothing was saved'; end if;
    select * into v_sc_acct from public.ref_account a where a.code = v_sc_code;
    if v_sc_acct.id is null then raise exception 'Surcharge account % (inv_config so_surcharge_account_code) is not in the chart of accounts — nothing was saved', v_sc_code; end if;
    if not v_sc_acct.is_active then raise exception 'Surcharge account % (%) is inactive — pick an active account in inv_config so_surcharge_account_code — nothing was saved', v_sc_acct.code, v_sc_acct.name; end if;
  end if;
  -- 운임 할인 계정(fr-2 판정 358 · surcharge 와 같은 모양) — 담긴 오더에 할인이 걸린 운임 줄이 있으면 머리 insert 앞에서 계정을 잡는다 · 비었거나 · 없거나 · 꺼졌으면 할인 운임이 있는 발행만 막는다
  select exists (select 1 from public.so_charge c where c.so_id = any(p_so_ids) and (c.discount_pct is not null or c.discount_amount is not null)) into v_has_fd;
  if v_has_fd then
    select nullif(k.value, '') into v_fd_code from public.inv_config k where k.key = 'so_freight_discount_account_code';
    if v_fd_code is null then raise exception 'Freight discount account is not set — set inv_config so_freight_discount_account_code (e.g. _6_ Sales Discounts) before invoicing an order with a freight discount — nothing was saved'; end if;
    select * into v_fd_acct from public.ref_account a where a.code = v_fd_code;
    if v_fd_acct.id is null then raise exception 'Freight discount account % (inv_config so_freight_discount_account_code) is not in the chart of accounts — nothing was saved', v_fd_code; end if;
    if not v_fd_acct.is_active then raise exception 'Freight discount account % (%) is inactive — pick an active account in inv_config so_freight_discount_account_code — nothing was saved', v_fd_acct.code, v_fd_acct.name; end if;
  end if;

  -- 머리(합계는 0 으로 넣고 오더를 돌며 채운다 · CHECK 셋은 0 에서도 맞다)
  insert into public.so_invoice (bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_line2, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country,
                                 issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code, updated_by)
  values (v_first.bill_to_customer_id, v_first.bill_to_name, v_first.bill_to_line1, v_first.bill_to_line2, v_first.bill_to_city, v_first.bill_to_state_province, v_first.bill_to_postal_code, v_first.bill_to_country,
          v_on, p_staff, v_pt.id, coalesce(v_pt.name, v_first.payment_term_name), case when v_pt.net_days is not null then v_on + v_pt.net_days end, v_first.currency_id, v_first.currency_code, p_staff)
  returning * into v_inv;

  -- 오더마다 — 규칙 · 금액(식 한 곳 · 보낸 수량) · 담긴 오더 줄 · 줄 사본 · 상태 전이
  for v_so in select * from public.so s where s.id = any(p_so_ids) order by s.so_number loop
    v_rule_id := public.so_invoice_rule_pick(v_so, v_on);                             -- doc-1b2: 세율 고르기 한 곳(미리 보기 so_invoice_preview 와 같은 함수)
    v_changed := v_rule_id is distinct from v_so.tax_rule_id;
    v_prev := public.so_tax_preview(v_so.id, v_on, v_rule_id, 'shipped');          -- explicit 규칙 · 활성 sale 아니면 이 함수가 거부한다
    v_rule := v_prev->'rule'->>'rule';  v_rate := (v_prev->'rule'->>'rate_pct')::numeric;
    v_o_lines := (v_prev->'totals'->>'lines_amount')::numeric;  v_o_od := (v_prev->'totals'->>'order_discount_amount')::numeric;
    v_o_chg   := (v_prev->'totals'->>'charges_amount')::numeric;  v_o_tax := (v_prev->'totals'->>'tax')::numeric;
    v_o_sc    := coalesce((v_prev->'totals'->>'surcharge_amount')::numeric, 0);                                             -- surcharge-2b: 이 오더 몫 · tax 는 2a 부터 surcharge 세금을 이미 품는다
    v_o_chd   := coalesce((v_prev->'totals'->>'charges_discount_amount')::numeric, 0);                                      -- fr-2 판정 352: 이 오더의 운임 할인 합(fr-1 so_tax_preview · tax 는 할인 세금을 이미 뺐다 · 354)
    if v_o_lines + v_o_od + v_o_chg = 0 and not exists (select 1 from public.so_line l where l.so_id = v_so.id and l.qty_shipped > 0) then
      raise exception 'Order % shipped nothing — there is nothing to invoice — nothing was saved', v_so.so_number;
    end if;

    insert into public.so_invoice_order (invoice_id, so_id, so_number, customer_id,
                                         ship_to_company, ship_to_contact, ship_to_phone, ship_to_line1, ship_to_line2, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country,
                                         tax_rule_id, tax_rule, rate_pct, tax_source, draft_rule_changed,
                                         lines_amount, order_discount_pct, order_discount_amount, charges_amount, charges_discount_amount, surcharge_amount, taxable_amount, tax_amount, total, updated_by)   -- fr-2
    values (v_inv.id, v_so.id, v_so.so_number, v_so.customer_id,
            v_so.ship_to_company, v_so.ship_to_contact, v_so.ship_to_phone, v_so.ship_to_line1, v_so.ship_to_line2, v_so.ship_to_city, v_so.ship_to_state_province, v_so.ship_to_postal_code, v_so.ship_to_country,
            v_rule_id, v_rule, v_rate, case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, v_changed,
            v_o_lines, v_so.order_discount_pct, v_o_od, v_o_chg, v_o_chd, v_o_sc, v_o_lines + v_o_od + v_o_chg - v_o_chd + v_o_sc, v_o_tax, v_o_lines + v_o_od + v_o_chg - v_o_chd + v_o_sc + v_o_tax, p_staff)   -- fr-2: 운임 할인을 뺀다
    returning * into v_io;

    for e in select x from jsonb_array_elements(v_prev->'lines') x loop                     -- 제품 줄(보낸 수량 > 0 만 · 안 나간 줄은 종이에 없다)
      if (e->>'qty')::numeric > 0 and nullif(e->>'combo_line_id', '') is null then                  -- asm-2b2(묶음 5): 구성품 줄은 종이에 없다 · 콤보 줄은 product 줄(qty = 나간 콤보 수) + 「includes …」 를 combo_components 에 굳힌다(so_line 이 뒤에 바뀌어도 그대로)
        v_ln := v_ln + 1;
        insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, unit, pack_factor, qty, list_price, discount_pct, discount_source, unit_price, amount, tax_amount, account_id, account_code, updated_by, combo_components)
        values (v_inv.id, v_io.id, v_ln, 'product', (e->>'line_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
                (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, e->>'discount_source', (e->>'unit_price')::numeric, (e->>'amount')::numeric, (e->>'tax')::numeric,
                v_so.sale_account_id, v_so.sale_account_code, p_staff, nullif(e->'combo_components', 'null'::jsonb));
        if coalesce((e->>'surcharge_total')::numeric, 0) > 0 then                        -- surcharge-2b(묶음 5): 그 상품 줄 바로 뒤 · 값은 so_tax_preview 줄 객체에서(2a 계산 한 곳 · 다시 세지 않는다) · 계정 = inv_config so_surcharge_account_code
          v_ln := v_ln + 1;
          insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, qty, unit_price, amount, tax_amount, account_id, account_code, updated_by)
          values (v_inv.id, v_io.id, v_ln, 'surcharge', (e->>'line_id')::uuid, e->>'sku', e->>'surcharge_label', (e->>'qty')::numeric, (e->>'surcharge_unit')::numeric, (e->>'surcharge_total')::numeric, (e->>'surcharge_tax')::numeric,
                  v_sc_acct.id, v_sc_acct.code, p_staff);
        end if;
      end if;
    end loop;
    if v_o_od <> 0 then                                                                    -- 오더 전체 할인 줄 하나(D6 · 음수 · 세금 따로 · §16 판정 3)
      v_ln := v_ln + 1;
      insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, description, amount, tax_amount, account_id, account_code, updated_by)
      values (v_inv.id, v_io.id, v_ln, 'order_discount', format('Order discount %s%%', v_so.order_discount_pct), v_o_od, (v_prev->'order_discount'->>'tax')::numeric, v_so.sale_account_id, v_so.sale_account_code, p_staff);
    end if;
    for e in select x from jsonb_array_elements(v_prev->'charges') x loop                   -- 운임·서비스 줄 전부(0 도 · 무료 배송 흔적 · 1-p)
      v_ln := v_ln + 1;
      insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, amount, tax_amount, account_id, account_code, updated_by)
      values (v_inv.id, v_io.id, v_ln, 'charge', (e->>'charge_id')::uuid, e->>'name' || coalesce(' — ' || (e->>'description'), ''), (e->>'amount')::numeric, (e->>'tax')::numeric,
              (e->>'account_id')::uuid, e->>'account_code', p_staff);
      if coalesce((e->>'discount')::numeric, 0) > 0 then                                   -- fr-2 판정 352 · 354: 할인 줄은 그 운임 줄 바로 뒤 · 음수 · 세금은 할인 줄 몫(so_tax_preview 가 따로 반올림) · 계정 = inv_config so_freight_discount_account_code
        v_ln := v_ln + 1;
        insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, discount_pct, amount, tax_amount, account_id, account_code, updated_by)
        values (v_inv.id, v_io.id, v_ln, 'charge_discount', (e->>'charge_id')::uuid,
                (e->>'name') || ' discount' || case when nullif(e->>'discount_pct', '') is not null then format(' %s%%', trim_scale((e->>'discount_pct')::numeric)) else '' end,
                nullif(e->>'discount_pct', '')::numeric, -(e->>'discount')::numeric, -coalesce((e->>'discount_tax')::numeric, 0), v_fd_acct.id, v_fd_acct.code, p_staff);
      end if;
    end loop;

    v_lines_amt := v_lines_amt + v_o_lines;  v_od_amt := v_od_amt + v_o_od;  v_chg_amt := v_chg_amt + v_o_chg;  v_tax := v_tax + v_o_tax;  v_sc_amt := v_sc_amt + v_o_sc;   -- surcharge-2b
    v_chd_amt := v_chd_amt + v_o_chd;                                                                                                                              -- fr-2
    if v_changed then v_warn := array_append(v_warn, 'draft_rule_changed:' || v_so.so_number); end if;
    if coalesce(v_prev->'warnings', '[]'::jsonb) ? 'tax_rule_inactive' then v_warn := array_append(v_warn, 'tax_rule_inactive:' || v_so.so_number); end if;

    update public.so set status = 'fulfilled', invoiced_at = now(), closed_at = now(), updated_by = p_staff where id = v_so.id and status = 'shipped';   -- ⓑ2 판정 1: 문지기 짝 shipped→fulfilled · 끝 상태 closed_at 짝(so_closed_at_ck)
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not invoiced — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'tax_rule', v_rule, 'rate_pct', v_rate,
                                               'tax_source', case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, 'draft_rule_changed', v_changed, 'totals', v_prev->'totals');
  end loop;

  -- 합계를 먼저 굳힌다(so_invoice_remaining 이 total 을 본다) · 잔액 항은 아직 0
  v_total := v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt + v_tax;                                                               -- surcharge-2b · fr-2 운임 할인을 뺀다
  update public.so_invoice set lines_amount = v_lines_amt, order_discount_amount = v_od_amt, charges_amount = v_chg_amt, charges_discount_amount = v_chd_amt, surcharge_amount = v_sc_amt,   -- fr-2
                               taxable_amount = v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt, tax_amount = v_tax, total = v_total, amount_due = v_total, updated_by = p_staff
  where id = v_inv.id returning * into v_inv;

  -- doc-1b2: ⓑ2 ① 선수금 · ⓒ2 ② 크레딧 · ⓑ2 ③ 받아 둔 돈 — 셈은 so_invoice_apply_plan 하나(미리 보기 so_invoice_preview 와 같은 식 · 쓰지 않는다) · 여기서는 그 계획대로 붙인다(한도 검사는 alloc_add 가 그대로)
  v_plan := public.so_invoice_apply_plan(v_inv.bill_to_customer_id, v_inv.currency_id, p_so_ids, v_total);
  for e in select x from jsonb_array_elements(v_plan->'steps') x loop
    if e->>'step' = 'auto_credit' then
      v_ca := public.so_credit_alloc_add((e->>'credit_id')::uuid, v_inv.id, (e->>'amount')::numeric, 'auto', p_staff);
      v_credit := v_credit + v_ca.amount;
      v_applied := v_applied || jsonb_build_object('alloc_id', v_ca.id, 'credit_id', e->'credit_id', 'credit_number', e->>'credit_number', 'source', 'auto_credit', 'amount', v_ca.amount, 'issued_on', e->'issued_on');
    else
      v_a := public.so_payment_alloc_add((e->>'payment_id')::uuid, v_inv.id, (e->>'amount')::numeric, e->>'step', p_staff);
      if e->>'step' = 'auto_deposit' then v_deposit := v_deposit + v_a.amount; else v_balance := v_balance + v_a.amount; end if;
      v_applied := v_applied || jsonb_build_object('alloc_id', v_a.id, 'payment_id', e->'payment_id', 'source', e->>'step', 'amount', v_a.amount, 'paid_on', e->'paid_on', 'method', e->>'method', 'reference', e->'reference');
    end if;
  end loop;

  -- 종이에 찍히는 값을 굳힌다 — 받은 금액(deposit_applied) · 이전 잔액(balance_forward = −(크레딧 ② + 받아 둔 돈 ③) · 0 이하 · 봤는데 없으면 0 · 한 줄 8-c) · credit_applied(② 몫 · 회계 근거 · ⬜7) · 보내실 금액(amount_due · CHECK so_invoice_due_ck)
  update public.so_invoice set deposit_applied = v_deposit, credit_applied = v_credit, balance_forward = -(v_credit + v_balance), amount_due = v_total - v_deposit - v_credit - v_balance, updated_by = p_staff
  where id = v_inv.id returning * into v_inv;

  return jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'issued_on', v_on, 'due_on', v_inv.due_on,
                            'bill_to_customer_id', v_inv.bill_to_customer_id, 'bill_to_name', v_inv.bill_to_name, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code,
                            'orders', v_orders, 'lines', v_ln,
                            'totals', jsonb_build_object('lines_amount', v_inv.lines_amount, 'order_discount_amount', v_inv.order_discount_amount, 'charges_amount', v_inv.charges_amount, 'charges_discount_amount', v_inv.charges_discount_amount, 'surcharge_amount', v_inv.surcharge_amount,   -- fr-2
                                                         'taxable_amount', v_inv.taxable_amount, 'tax_amount', v_inv.tax_amount, 'total', v_inv.total,
                                                         'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward, 'amount_due', v_inv.amount_due,
                                                         'remaining', public.so_invoice_remaining(v_inv.id)),
                            'applied', v_applied,
                            'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id),
                            'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ so_pos_confirm 재발행 — 원본 20261006204146_dsc_3b_coupon_credit.sql:430 바이트 + 더한 · 바꾼 줄만 · svc-1b ═══
CREATE OR REPLACE FUNCTION public.so_pos_confirm(p_so_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff uuid;
  v_so    public.so%rowtype;
  v_n     int;
  v_warn  text[] := '{}';
  v_cp    jsonb;                                               -- dsc-3b 판정 321
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 6: POS 는 sales 만(R5 예외)
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');
  if v_so.channel = 'warehouse' then
    raise exception 'Order % is a warehouse order — confirm it with so_confirm — nothing was saved', v_so.so_number;
  end if;
  if v_so.channel = 'service' then                                                                                -- svc-1b 판정 595 · 597: 서비스 오더는 so_service_confirm(줄 0 · 서비스 줄 합 > 0)
    raise exception 'Order % is a service order — confirm it with so_service_confirm — nothing was saved', v_so.so_number;
  end if;
  if v_so.channel = 'counter' then
    perform public.so_require_role('manager', 'saved');        -- ⭐ counter 는 manager 이상(6-b · 판정 12)
  end if;
  perform 1 from public.so s where s.id = p_so_id for update;
  perform public.so_confirm_precheck(v_so);                    -- R6(고침 ② · so_confirm 과 한 곳)

  v_n := public.so_allocate_all(p_so_id, v_staff);            -- 전 줄 allocated · 재고 안 봄 · 이어받기 없음(판정 13)
  update public.so set status = 'confirmed', confirmed_at = now(), confirmed_by = v_staff, updated_by = v_staff
  where id = p_so_id and status = 'draft';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Order % was not confirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

  v_warn := public.so_tier_warnings(v_so);                     -- 판정 14: intake pos 도 직접 오더 경고
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  v_cp := public.so_coupon_settle(p_so_id, v_staff);                                                     -- dsc-3b 판정 321 · 324(POS 확정 포함)
  if v_cp->>'action' = 'detached' then v_warn := array_append(v_warn, 'coupon_detached_not_used'); end if;
  return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'channel', v_so.channel, 'status', 'confirmed', 'coupon', v_cp,
                            'lines_allocated', (select count(*) from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = p_so_id and r.released_at is null and r.kind = 'allocated'),
                            'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ so_pos_reopen 재발행 — 원본 20260925142307_so_pos_a2_flow.sql:657 바이트 + 더한 · 바꾼 줄만 · svc-1b ═══
CREATE OR REPLACE FUNCTION public.so_pos_reopen(p_so_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff uuid;
  v_so    public.so%rowtype;
  v_n     int;
  v_rel   int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel = 'warehouse' then
    raise exception 'Order % is a warehouse order — use so_unconfirm (supervisor) — nothing was saved', v_so.so_number;
  end if;
  if v_so.channel = 'service' then                                                                                -- svc-1b 판정 595: 확정 풀기는 물건 오더와 같은 창구(so_unconfirm · supervisor)
    raise exception 'Order % is a service order — use so_unconfirm (supervisor) — nothing was saved', v_so.so_number;
  end if;
  if v_so.channel = 'counter' then
    perform public.so_require_role('manager', 'saved');        -- ⭐ counter 는 manager 이상
  end if;
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — only a confirmed % order can be reopened — nothing was saved', v_so.so_number, v_so.status, v_so.channel;
  end if;
  if exists (select 1 from public.so x where x.split_from_id = p_so_id) then
    raise exception 'Order % has split-off orders — a pos/counter order should never split; use so_unconfirm — nothing was saved', v_so.so_number;
  end if;

  update public.so_reserve r set released_at = now(), released_by = v_staff, released_reason = 'released', updated_by = v_staff
  from public.so_line l where r.so_line_id = l.id and l.so_id = p_so_id and r.released_at is null;
  get diagnostics v_rel = row_count;
  update public.so set status = 'draft', confirmed_at = null, confirmed_by = null, updated_by = v_staff
  where id = p_so_id and status = 'confirmed';                                                       -- 문지기 짝 confirmed→draft
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Order % was not reopened — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;
  return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'channel', v_so.channel, 'status', 'draft', 'reservations_released', v_rel);
end;
$function$;

-- ═══ ④ so_service_confirm — 서비스 오더 확정(draft → confirmed · 재고 잡기 없음) · svc-1b 판정 595 · 597 ═══
create or replace function public.so_service_confirm(p_so_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  c        public.customer%rowtype;
  v_wh     public.ref_warehouse%rowtype;
  v_n      int;
  v_cnt    int;
  v_amt    numeric;
  v_prev   jsonb;
  v_warn   text[] := '{}';
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 597: 만들기 · 확정 · 발행 = sales 쓰기(역할 문 없음 · R5 의 예외 셋째)
  v_staff := public.so_current_staff();
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel <> 'service' then
    raise exception 'Order % is a % order — confirm it with % — nothing was saved', v_so.so_number, v_so.channel, case when v_so.channel = 'warehouse' then 'so_confirm' else 'so_pos_confirm' end;
  end if;
  if v_so.status <> 'draft' then
    raise exception 'Order % is not a draft (status %) — nothing was saved', v_so.so_number, v_so.status;
  end if;

  -- 막는 조건 — 손님 · 브랜치(판정 594) · 상품 줄 0 · 서비스 줄 ≥ 1 · 합 > 0 · 세율(판정 593 — so_confirm_precheck 의 R6 와 같은 자리 · 줄 조건만 다르다)
  select * into c from public.customer where id = v_so.customer_id;
  if not found or not c.is_active then
    raise exception 'Customer % is inactive — reactivate it first — nothing was saved', coalesce(c.name, '?');
  end if;
  if v_so.location_id is null then
    raise exception 'Order % has no branch (warehouse) — set one before confirming — nothing was saved', v_so.so_number;
  end if;
  select * into v_wh from public.ref_warehouse where id = v_so.location_id;
  if not found or not v_wh.is_active then
    raise exception 'Warehouse % is inactive — pick an active branch — nothing was saved', coalesce(v_wh.name, '?');
  end if;
  select count(*) into v_n from public.so_line where so_id = p_so_id;
  if v_n > 0 then
    raise exception 'Order % is a service order but has % product line(s) — remove them first — nothing was saved', v_so.so_number, v_n;
  end if;
  select count(*), coalesce(sum(ch.amount - public.so_charge_discount(ch.amount, ch.discount_pct, ch.discount_amount)), 0) into v_cnt, v_amt
  from public.so_charge ch where ch.so_id = p_so_id;
  if v_cnt = 0 then
    raise exception 'Order % has no service lines — add at least one service before confirming — nothing was saved', v_so.so_number;
  end if;
  if v_amt <= 0 then
    raise exception 'Order % has service lines but their total is % — a service order needs an amount above 0 — nothing was saved', v_so.so_number, trim_scale(v_amt);
  end if;
  if v_so.tax_rule_id is null then
    raise exception 'Order % has no tax rule — set the ship-to province (or pick a tax rule) first — nothing was saved', v_so.so_number;
  end if;

  update public.so set status = 'confirmed', confirmed_at = now(), confirmed_by = v_staff, updated_by = v_staff
  where id = p_so_id and status = 'draft';                                                              -- 문지기 짝 draft→confirmed(공통)
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Order % was not confirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

  v_prev := public.so_tax_preview(p_so_id, public.ims_today(), null, 'ordered', null);                  -- 오더 세율로 센 합계(판정 593) — 화면이 확정 직후 보일 것
  v_warn := public.so_tier_warnings(v_so);
  return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'channel', 'service', 'status', 'confirmed', 'committed', true,
                            'lines', '[]'::jsonb, 'siblings', '[]'::jsonb, 'keeps', null, 'coupon', null,                       -- so_confirm 과 같은 열쇠(화면이 같은 자리에 그린다) · 서비스 오더에는 늘 비어 있다
                            'services', jsonb_build_object('count', v_cnt, 'amount', v_amt), 'totals', v_prev->'totals',
                            'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.so_service_confirm(uuid) from public, anon;
grant execute on function public.so_service_confirm(uuid) to authenticated, service_role;
comment on function public.so_service_confirm(uuid) is 'svc-1b(판정 595 · 597 · 2026-10-21) — 서비스 오더(channel service) 확정: draft → confirmed · sales 쓰기(역할 문 없음) · 손님 · 브랜치 · 상품 줄 0 · 서비스 줄 ≥ 1 · 합 > 0 · 세율 · 재고 잡기 없음 · 반환 꼴 = so_confirm + services{count, amount} · totals · 확정 풀기는 so_unconfirm(공통 짝)';

-- ═══ ⑤ so_service_invoice — 서비스 오더 발행(confirmed → shipped → so_invoice_issue 이 오더 하나만 → fulfilled) · svc-1b 판정 590 · 595 ═══
create or replace function public.so_service_invoice(p_so_id uuid, p_issued_on date default null, p_commit boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  v_on     date;
  v_n      int;
  v_cnt    int;
  v_amt    numeric;
  v_prev   jsonb;
  v_total  numeric;
  v_plan   jsonb;
  v_est    jsonb;
  v_iss    jsonb;
  v_inv_id uuid;
  v_due    date;
  v_bad    text;
  v_warn   text[] := '{}';
  v_tw     text[];
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 597
  v_staff := public.so_current_staff();
  v_on := coalesce(p_issued_on, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Invoice date % is in the future — nothing was saved', v_on; end if;
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel <> 'service' then
    raise exception 'Order % is a % order — invoice it with % — nothing was saved', v_so.so_number, v_so.channel,
      case v_so.channel when 'warehouse' then 'so_finalize' when 'pos' then 'so_pos_finish' else 'so_counter_ship' end;
  end if;
  if v_so.status not in ('confirmed', 'shipped') then                                                   -- shipped = 인보이스를 취소한 뒤(so_invoice_cancel · fulfilled → shipped) 다시 발행하는 자리
    raise exception 'Order % is % — only a confirmed service order can be invoiced (a cancelled invoice leaves it shipped — issue again from there) — nothing was saved', v_so.so_number, v_so.status;
  end if;
  select string_agg(i.invoice_number, ', ') into v_bad
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id and o.cancelled_at is null;
  if v_bad is not null then raise exception 'Order % is already on invoice % — cancel that invoice first — nothing was saved', v_so.so_number, v_bad; end if;
  if v_so.bill_to_customer_id is null then raise exception 'Order % has no bill-to customer — nothing was saved', v_so.so_number; end if;
  select count(*) into v_n from public.so_line where so_id = p_so_id;
  if v_n > 0 then raise exception 'Order % is a service order but has % product line(s) — nothing was saved', v_so.so_number, v_n; end if;
  select count(*), coalesce(sum(ch.amount - public.so_charge_discount(ch.amount, ch.discount_pct, ch.discount_amount)), 0) into v_cnt, v_amt
  from public.so_charge ch where ch.so_id = p_so_id;
  if v_cnt = 0 or v_amt <= 0 then
    raise exception 'Order % has nothing to invoice (service lines %, total %) — nothing was saved', v_so.so_number, v_cnt, trim_scale(v_amt);
  end if;

  -- 미리 보기 — 세금(오더 세율 · 판정 593) · 자동 붙이기 추정(so_invoice_apply_plan · 발행과 같은 식 · 쓰지 않는다) · Due date = 발행일 + net_days(so_invoice_issue 와 같은 셈)
  v_prev := public.so_tax_preview(p_so_id, v_on, null, 'ordered', null);
  if v_prev->'totals'->>'tax' is null then raise exception 'Order % has no tax rule — set the ship-to province (or pick a tax rule) first — nothing was saved', v_so.so_number; end if;
  v_total := (v_prev->'totals'->>'total')::numeric;
  v_plan := public.so_invoice_apply_plan(v_so.bill_to_customer_id, v_so.currency_id, array[p_so_id], v_total);
  v_est := jsonb_build_object('total', v_total, 'deposit', v_plan->'deposit', 'credit', v_plan->'credit', 'balance', v_plan->'balance',
                              'amount_due', v_total - coalesce((v_plan->>'deposit')::numeric, 0) - coalesce((v_plan->>'credit')::numeric, 0) - coalesce((v_plan->>'balance')::numeric, 0),
                              'received_before', (select b.received from public.so_customer_balance(v_so.bill_to_customer_id) b where b.currency_id = v_so.currency_id));
  select v_on + t.net_days into v_due from public.ref_payment_term t where t.id = v_so.payment_term_id and t.net_days is not null;
  if not p_commit then
    return jsonb_build_object('committed', false, 'so_id', v_so.id, 'so_number', v_so.so_number, 'channel', 'service', 'status', v_so.status,
                              'issued_on', v_on, 'due_on', v_due, 'services', v_prev->'charges', 'tax', v_prev->'totals', 'estimate', v_est, 'warnings', to_jsonb(v_warn));
  end if;

  -- 실행 — 나감 표시(confirmed → shipped · 문지기 길별 짝 · 누른 사람 = shipped_by · 6-b counter 와 같은 벌충) → 발행 한 장(이 오더 하나만 · 발행 순간 fulfilled · 자동 붙이기 ①②③)
  if v_so.status = 'confirmed' then
    update public.so set status = 'shipped', shipped_at = now(), shipped_by = v_staff, updated_by = v_staff
    where id = p_so_id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not invoiced — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;
  end if;
  v_iss := public.so_invoice_issue(array[p_so_id], v_staff, v_on);
  v_inv_id := (v_iss->>'invoice_id')::uuid;
  select array_agg(t.w) into v_tw from jsonb_array_elements_text(coalesce(v_iss->'warnings', '[]'::jsonb)) as t(w);
  v_warn := v_warn || coalesce(v_tw, '{}');

  return jsonb_build_object('committed', true, 'so_id', v_so.id, 'so_number', v_so.so_number, 'channel', 'service', 'status', 'fulfilled',
                            'invoice_id', v_inv_id, 'invoice_number', v_iss->>'invoice_number', 'issued_on', v_iss->'issued_on', 'due_on', v_iss->'due_on',
                            'totals', v_iss->'totals', 'received', jsonb_build_object('deposit_applied', v_iss->'totals'->'deposit_applied', 'credit_applied', v_iss->'totals'->'credit_applied', 'balance_forward', v_iss->'totals'->'balance_forward'),
                            'amount_due', v_iss->'totals'->'amount_due', 'remaining', public.so_invoice_remaining(v_inv_id),
                            'estimate', v_est, 'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.so_service_invoice(uuid, date, boolean) from public, anon;
grant execute on function public.so_service_invoice(uuid, date, boolean) to authenticated, service_role;
comment on function public.so_service_invoice(uuid, date, boolean) is 'svc-1b(판정 590 · 595 · 597 · 2026-10-21) — 서비스 오더 발행: sales 쓰기 · p_commit false = 미리 보기(세금 · 자동 붙이기 추정 · Due date) · 실행 = confirmed → shipped(shipped_at · 누른 사람) → so_invoice_issue 이 오더 하나만(늘 따로) → fulfilled · 인보이스 취소 뒤(shipped) 다시 발행 · 한 트랜잭션 · 반환 꼴 = so_pos_complete';


-- ═══ 착지 — CHECK · 문지기 짝 · 새 창구 둘 ACL · 재발행 8 md5 · 다른 길 무변 ═══
do $$
declare
  v_bad text := '';
  v_n   int;
  b     record;
  v_exp jsonb := '{"so_create": "5b8aa34372bd8b7ad0be50172313bed8", "so_status_guard": "9e4c88d22647a84bc46394031eab6317", "so_line_add": "f505807836e5974d58702202a21d2d89", "so_lines_paste": "ec25aaeb81f71aee706d8abbd1e55b5b", "so_charge_gate": "12904d7f89b5db700d71087ed81523f4", "so_invoice_issue": "18da3d9f4e4cfcac7bea4f740a16f7cb", "so_pos_confirm": "2a20a8abad4d4a5dcb509d64a15b77b4", "so_pos_reopen": "a4cbbc54bab27e288795bb997f62aef5"}'::jsonb;
  k     text;
begin
  select * into b from svc1b_before;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so'::regclass and conname = 'so_channel_ck') !~ '''service''' then v_bad := v_bad || ' channel_ck'; end if;
  if (select string_agg(conname || ':' || pg_get_constraintdef(oid), ' ' order by conname) from pg_constraint where conrelid = 'public.so'::regclass and contype = 'c' and conname <> 'so_channel_ck') is distinct from b.other_checks then v_bad := v_bad || ' other_checks'; end if;
  if (select string_agg(tgname || '→' || tgfoid::regproc::text, ' ' order by tgname) from pg_trigger where tgrelid = 'public.so'::regclass and not tgisinternal) is distinct from b.so_triggers then v_bad := v_bad || ' so_triggers'; end if;
  for k in select jsonb_object_keys(v_exp) loop
    select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = k;
    if v_n <> 1 then v_bad := v_bad || format(' %s_overloads_%s', k, v_n); end if;
    if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = k) is distinct from (v_exp->>k) then v_bad := v_bad || ' ' || k || '_body'; end if;
  end loop;
  if (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('so_create', 'so_status_guard', 'so_line_add', 'so_lines_paste', 'so_charge_gate', 'so_invoice_issue', 'so_pos_confirm', 'so_pos_reopen')) is distinct from b.acls then v_bad := v_bad || ' reissued_acls'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('so_confirm', 'so_unconfirm', 'so_confirm_precheck', 'so_ship', 'so_pos_complete', 'so_pos_finish', 'so_counter_ship', 'so_finalize', 'so_invoice_cancel', 'so_invoice_reissue', 'so_cancel',
                         'so_charge_set', 'so_charge_remove', 'so_merge', 'so_split', 'so_divide', 'so_hold', 'so_release_to_wms', 'so_wms_status', 'so_picked_up', 'so_allocate_run', 'so_backorder_demand', 'so_backorder_overview', 'so_demand_flag_set', 'so_pos_open_list', 'so_tax_preview', 'so_copy_customer', 'so_require_draft')) is distinct from b.others then v_bad := v_bad || ' others_changed'; end if;
  if to_regprocedure('public.so_service_confirm(uuid)') is null or to_regprocedure('public.so_service_invoice(uuid, date, boolean)') is null then v_bad := v_bad || ' new_fns'; end if;
  if not has_function_privilege('authenticated', 'public.so_service_confirm(uuid)', 'execute') or has_function_privilege('anon', 'public.so_service_confirm(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.so_service_invoice(uuid, date, boolean)', 'execute') or has_function_privilege('anon', 'public.so_service_invoice(uuid, date, boolean)', 'execute') then v_bad := v_bad || ' new_fn_acl'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_service_confirm', 'so_service_invoice') and p.prosecdef and p.prosrc ~ 'ims_require_write\(''sales'', ''saved''\)') <> 2 then v_bad := v_bad || ' new_fn_gate'; end if;
  if (select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_status_guard') !~ '''pos'', ''counter'', ''service''' then v_bad := v_bad || ' guard_pair'; end if;
  if (select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_invoice_issue') !~ 'invoiced on its own' then v_bad := v_bad || ' issue_text'; end if;
  if exists (select 1 from public.so where channel = 'service') then v_bad := v_bad || ' service_rows_already'; end if;
  if v_bad <> '' then raise exception 'svc-1b landing check failed:%', v_bad; end if;
end $$;
drop table svc1b_before;
