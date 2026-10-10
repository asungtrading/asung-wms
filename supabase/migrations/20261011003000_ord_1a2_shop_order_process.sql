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

-- ════════════════════════════════════════════════════════════════════════════════════════════
-- ord-1a2 — Shopify ④ 오더 받기 · DB 둘째 차수: SO 만들기 · 확정 · 취소 · 줄 고르기 (2026-10-10 밤 · 판정 366 ~ 372 · 431 ~ 434 · 1a1 20261010233000 위에)
--   ① so_line.discount_source CHECK 에 shopify · 속 갱신 so_line_set_shopify(한 곳 · service_role) — 손님이 본 정가 · 할인 그대로(431 ③)
--   ② 다시 매기기 건너뛰기(433): so_line_requote(합치기 · finalize · paste 가 쓰는 한 곳) · so_line_update(수량만 바뀐 줄) · so_reprice — shopify 줄은 할인 그대로 · 재발행 셋(바뀐 줄만)
--   ③ so_create 재발행 — intake shopify 허락(채널 warehouse 만)
--   ④ shop_order_process(shop_order): received 만 · 시스템 직원으로 so_create → 줄 so_line_add(단가 = Shopify 할인 뒤) + so_line_set_shopify → 배송지 · ref · 메모 so_header_update → 오더 할인 0(manual) → 할인 어긋남(so_line_quote 와 % 대조 · 바꾸지 않음) → 세금 어긋남(so_totals_many) → 운임(aone 만 · 369) → 결제(aone PAID · 370) → so_confirm(막히면 draft + 경고 · 371) → created · so_id · so_baseline_at(434 기준 시각) · 실패하면 error(SO 없음 · claims 복원)
--   ⑤ shop_order_cancelled(shop_order)(434): SO 가 draft · confirmed 이고 기준 시각 뒤 IMS 에서 안 바뀜(so · so_line · so_charge updated_at) → so_cancel · cancelled · 그 밖 경고 cancel_needs_review(changed_in_ims | in_warehouse) · SO 전이면 그냥 cancelled
--   ⑥ shop_order_resolve_lines(shop_order, choices, commit, ack) — 직원 · 줄에 다른 SKU 잇기 · 줄 빼기(ack) → prepare
--   ⑦ shop_order_ingest 재발행(취소 받기) · shop_order_so_ck 완화(cancelled 도 so_id 를 남긴다) · shop_order.so_baseline_at · 뷰 끝에 so_baseline_at
--   무접촉(prosrc md5 전후 같음): so_line_add · so_charge_set · so_payment_add · so_confirm · so_cancel · so_tax_refresh · so_header_update · so_finalize · so_lines_paste · customer_create · shop_order_prepare · shop_order_resolve_customer
-- ════════════════════════════════════════════════════════════════════════════════════════════

-- ═══ 1) 줄 할인 출처 shopify · 받은 오더 칸 ═══
alter table public.so_line drop constraint so_line_discount_source_ck;
alter table public.so_line add constraint so_line_discount_source_ck check (discount_source is null or discount_source in ('customer', 'deal', 'manual', 'set', 'shopify'));
comment on constraint so_line_discount_source_ck on public.so_line is 'customer · deal · manual · set · ⭐ shopify(ord-1a2 판정 431 ③ · 433: 손님이 본 할인 그대로 · 다시 매기기가 건너뛴다)';
alter table public.shop_order drop constraint shop_order_so_ck;
alter table public.shop_order add constraint shop_order_so_ck check (status <> 'created' or so_id is not null);                 -- created 면 SO 가 있다 · cancelled 도 SO 를 남길 수 있다(ord-1a2)
alter table public.shop_order add column if not exists so_baseline_at timestamptz;
comment on column public.shop_order.so_baseline_at is 'ord-1a2 판정 434: SO 를 만든 트랜잭션의 시각(now()) — 그 뒤 so · so_line · so_charge 의 updated_at 이 이보다 크면 「IMS 에서 바뀜」 · Shopify 취소를 자동으로 따르지 않는다';

-- ═══ 2) 속 갱신 한 곳 — Shopify 정가 · 할인을 줄에 적는다 ═══
create function public.so_line_set_shopify(p_line_id uuid, p_list_price numeric, p_discount_pct numeric) returns public.so_line
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_line public.so_line%rowtype;
begin
  if p_discount_pct is null or p_discount_pct < 0 or p_discount_pct > 100 then raise exception 'so_line_set_shopify: discount_pct % out of range — nothing was saved', p_discount_pct; end if;
  update public.so_line set list_price = p_list_price, discount_pct = round(p_discount_pct, 2), discount_source = 'shopify', deal_line_id = null, price_override = false, updated_by = public.so_current_staff()
   where id = p_line_id and combo_line_id is null returning * into v_line;                                                  -- unit_price 는 so_line_add 가 받은 Shopify 할인 뒤 단가 그대로
  if v_line.id is null then raise exception 'so_line_set_shopify: line % not found or is a combo component — nothing was saved', p_line_id; end if;
  return v_line;
end;
$$;
revoke all on function public.so_line_set_shopify(uuid, numeric, numeric) from public, anon, authenticated;
comment on function public.so_line_set_shopify(uuid, numeric, numeric) is 'ord-1a2 판정 431 ③: so_line_add(p_unit_price = Shopify 할인 뒤 단가)로 넣은 줄에 Shopify 정가(list_price) · 할인 %(discount_pct) · 출처 shopify 를 적는 속 갱신 한 곳 — price_override false · deal null · 단가는 그대로 · service_role 만(shop_order_process 가 부른다)';

-- ═══ 3) 재발행 — so_create(intake shopify) · so_line_requote · so_line_update · so_reprice(판정 433) ═══
create or replace function public.so_create(
  p_customer_id uuid,
  p_channel     text default 'warehouse',
  p_intake      text default 'manual',
  p_location_id uuid default null,
  p_comments    text default null
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
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

  if p_channel is null or p_channel not in ('warehouse', 'pos', 'counter') then                       -- ④a2: 길 셋(6-b)
    raise exception 'Channel % is not one of warehouse, pos, counter — nothing was saved', coalesce(p_channel, 'null');
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
$$;
create or replace function public.so_line_requote(p_line_id uuid, p_qty numeric, p_set_qty boolean default true) returns public.so_line
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_line public.so_line%rowtype;
  v_so   public.so%rowtype;
  q      record;
begin
  select * into v_line from public.so_line where id = p_line_id;
  if not found then
    raise exception 'Order line not found — nothing was saved';
  end if;
  if v_line.combo_line_id is not null then                                                                         -- asm-2b2(묶음 2): 구성품 줄은 값이 없다 — 견적하면 unit_price 가 null 이 되어 so_line_combo_values_ck 에 걸린다 · 소리 나게 거부
    raise exception 'Line % (%) is a combo component — it carries no price of its own; quote the combo line — nothing was saved', v_line.line_no, v_line.sku;
  end if;
  select * into v_so from public.so where id = v_line.so_id;
  if v_line.discount_source is not distinct from 'shopify' then                                                     -- ord-1a2 판정 433: 웹 오더 줄은 다시 매기지 않는다 — 수량만(할인 % · 단가 그대로 · 바꾸려면 직원이 손으로)
    update public.so_line set qty_ordered = case when p_set_qty then p_qty else qty_ordered end, updated_by = public.so_current_staff()
    where id = p_line_id returning * into v_line;
    return v_line;
  end if;
  select * into q from public.so_line_quote(v_so, v_line.product_id, p_qty);
  update public.so_line set
    qty_ordered     = case when p_set_qty then p_qty else qty_ordered end,   -- ⓐ2 이견 3: false 면 견적만(뺀 몫 · 판정 5 「주문 12 · 뺐다 12」는 qty_ordered 에 남는다)
    discount_pct    = q.discount_pct,
    unit_price      = case when list_price is null then null else list_price * (1 - q.discount_pct / 100) end,
    discount_source = q.discount_source,
    deal_line_id    = q.deal_line_id,
    updated_by      = public.so_current_staff()
  where id = p_line_id
  returning * into v_line;
  return v_line;
end;
$$;
create or replace function public.so_line_update(p_line_id uuid, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_keys   constant text[] := array['qty_ordered', 'unit_price', 'discount_pct', 'free_reason', 'surcharge_pct', 'surcharge_amount', 'surcharge_label', 'comments'];   -- 세금 ②: tax_rule 은 오더 것(판정 8)
  v_staff  uuid;
  v_line   public.so_line%rowtype;
  v_so     public.so%rowtype;
  v_bad    text;
  q        record;
  v_qty    numeric;  v_unit numeric;  v_disc numeric;  v_override boolean;  v_dsrc text;  v_deal uuid;
  v_reason text;  v_comments text;
  v_spct   numeric;  v_samt numeric;  v_slbl text;
  v_line_no int;
  v_n      int;
  v_warn   text[] := '{}';
  v_qty_old numeric;                                            -- asm-2a(묶음 3): 콤보 줄 수량이 바뀌면 구성품 줄이 따라간다
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();

  select * into v_line from public.so_line where id = p_line_id;
  if not found then
    raise exception 'Order line not found — nothing was saved';
  end if;
  v_line_no := v_line.line_no;
  v_qty_old := v_line.qty_ordered;
  if v_line.combo_line_id is not null then                      -- asm-2a(묶음 3): 구성품 줄은 따로 못 고친다
    raise exception 'Line % is a component of combo % (line %) — change the combo line instead — nothing was saved', v_line_no,
      (select c.sku from public.so_line c where c.id = v_line.combo_line_id), (select c.line_no from public.so_line c where c.id = v_line.combo_line_id);
  end if;
  v_so := public.so_require_draft(v_line.so_id, 'saved');

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'p_patch must be a JSON object — nothing was saved';
  end if;
  if p_patch ? 'tax_rule' then                                  -- 세금 ② · 판정 8 — 줄마다 바꾸는 길은 없다(모르는 열쇠보다 먼저 · 사람이 읽는 말)
    raise exception 'The tax rule belongs to the order, not to a line — change it on the order (so_header_update tax_rule) — nothing was saved';
  end if;
  select k into v_bad from jsonb_object_keys(p_patch) k where k <> all (c_keys) limit 1;
  if v_bad is not null then
    raise exception 'Unknown field % — nothing was saved', v_bad;
  end if;
  if p_patch = '{}'::jsonb then
    raise exception 'Nothing to change — nothing was saved';
  end if;

  -- 수량
  v_qty := case when p_patch ? 'qty_ordered' then nullif(p_patch->>'qty_ordered', '')::numeric else v_line.qty_ordered end;
  if v_qty is null or v_qty <= 0 then
    raise exception 'Quantity must be a positive number — nothing was saved';
  end if;

  -- 가격 — 덮어쓰기 · 수동 할인 · 시스템으로 되돌리기 · 수량만 바뀐 시스템 줄은 다시 견적(판정 3) · 둘 다는 못 준다
  if p_patch ? 'unit_price' and p_patch ? 'discount_pct' then
    raise exception 'Give either a unit price or a discount, not both — nothing was saved';
  end if;
  if p_patch ? 'unit_price' then
    v_unit := nullif(p_patch->>'unit_price', '')::numeric;
    if v_unit is null then
      raise exception 'unit_price cannot be blank — remove the line or give a price — nothing was saved';
    end if;
    if v_unit < 0 then
      raise exception 'Unit price cannot be negative — nothing was saved';
    end if;
    v_override := true;  v_disc := null;  v_dsrc := null;  v_deal := null;
  elsif p_patch ? 'discount_pct' then
    v_disc := nullif(p_patch->>'discount_pct', '')::numeric;
    if v_disc is not null then                                   -- 수동 할인
      if v_disc < 0 or v_disc > 100 then
        raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
      end if;
      v_dsrc := 'manual';  v_deal := null;
    else                                                         -- 비우면 시스템으로(할인 식 한 곳 · 딜 포함 · 이견 3)
      select * into q from public.so_line_quote(v_so, v_line.product_id, v_qty);
      v_disc := q.discount_pct;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    end if;
    v_unit := case when v_line.list_price is null then null else v_line.list_price * (1 - v_disc / 100) end;
    v_override := false;
  elsif v_qty is distinct from v_line.qty_ordered and not v_line.price_override and v_line.discount_source is distinct from 'manual' and v_line.discount_source is distinct from 'shopify' then   -- ord-1a2 판정 433: shopify 줄은 수량이 바뀌어도 할인 그대로
    select * into q from public.so_line_quote(v_so, v_line.product_id, v_qty);      -- 시스템 줄 · 수량이 바뀌었다 → 할인 다시(list 는 그대로)
    v_disc := q.discount_pct;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    v_unit := case when v_line.list_price is null then null else v_line.list_price * (1 - v_disc / 100) end;
    v_override := false;
  else
    v_unit := v_line.unit_price;  v_disc := v_line.discount_pct;  v_override := v_line.price_override;  v_dsrc := v_line.discount_source;  v_deal := v_line.deal_line_id;
  end if;

  -- 무상(판정 2 · ⬜7)
  v_reason   := case when p_patch ? 'free_reason' then nullif(trim(p_patch->>'free_reason'), '') else v_line.free_reason end;
  v_comments := case when p_patch ? 'comments'    then nullif(trim(p_patch->>'comments'), '')    else v_line.comments end;
  if v_unit is not distinct from 0 and v_reason is null then
    raise exception 'A free line (price 0) needs a reason — sample, promotion, replacement or other — nothing was saved';
  end if;
  if v_reason is not null and v_unit is distinct from 0 then
    raise exception 'Line % has a free-goods reason but a non-zero price — clear the reason or set the price to 0 — nothing was saved', v_line_no;
  end if;
  if v_reason is not null and v_reason not in ('sample', 'promotion', 'replacement', 'other') then
    raise exception 'Free reason % is not one of sample, promotion, replacement, other — nothing was saved', v_reason;
  end if;
  if v_reason = 'other' and v_comments is null then
    raise exception 'Reason other needs a comment — nothing was saved';
  end if;

  -- 부가 요금(판정 7 · 228 · surcharge-2a) — 짝 · 범위 · 무상 금지는 so_surcharge_check 한 곳(so_finalize 와 같은 문장)
  v_spct := case when p_patch ? 'surcharge_pct'    then nullif(p_patch->>'surcharge_pct', '')::numeric    else v_line.surcharge_pct end;
  v_samt := case when p_patch ? 'surcharge_amount' then nullif(p_patch->>'surcharge_amount', '')::numeric else v_line.surcharge_amount end;
  v_slbl := case when p_patch ? 'surcharge_label'  then nullif(trim(p_patch->>'surcharge_label'), '')     else v_line.surcharge_label end;
  perform public.so_surcharge_check(v_spct, v_samt, v_slbl, v_reason);

  update public.so_line set
    qty_ordered      = v_qty,
    unit_price       = v_unit,
    discount_pct     = v_disc,
    price_override   = v_override,
    discount_source  = v_dsrc,
    deal_line_id     = v_deal,
    free_reason      = v_reason,
    comments         = v_comments,
    surcharge_pct    = v_spct,
    surcharge_amount = v_samt,
    surcharge_label  = v_slbl,
    updated_by       = v_staff
  where id = p_line_id
  returning * into v_line;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Line % of % was not saved — it may have been removed by someone else just now — nothing was saved', v_line_no, v_so.so_number;
  end if;
  if v_line.qty_ordered is distinct from v_qty_old then perform public.so_combo_children_sync(v_line.id, v_staff); end if;      -- asm-2a(묶음 3): 콤보 줄이면 구성품 줄 수량 = 콤보 수량 × 정의 수량(보통 줄은 0 행)
  if v_line.unit_price is null then v_warn := array_append(v_warn, 'no_price'); end if;
  if v_line.deal_line_id is not null and public.so_deal_line_ended(v_line.deal_line_id, public.ims_today()) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if v_spct is not null and v_spct > 100 then v_warn := array_append(v_warn, 'surcharge_pct_over_100'); end if;   -- surcharge-2a(Caleb 확인 · 위 한계 CHECK 없음 · 화면이 확인을 묻는다)

  return jsonb_build_object('so_number', v_so.so_number, 'line', to_jsonb(v_line), 'total', public.so_line_total(v_line),
                            'surcharge_unit', public.so_line_surcharge_unit(v_line.unit_price, v_line.surcharge_pct, v_line.surcharge_amount), 'surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(v_line.unit_price, v_line.surcharge_pct, v_line.surcharge_amount), v_line.qty_ordered),   -- surcharge-2a
                            'warnings', to_jsonb(v_warn), 'components', public.so_combo_children_json(v_line.id));
end;
$$;
create or replace function public.so_reprice(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_so      public.so%rowtype;
  l         public.so_line%rowtype;
  q         record;
  od        record;
  v_rows    jsonb := '[]'::jsonb;
  v_changed int := 0;
  v_diff    boolean;
  v_old_pct numeric;  v_old_src text;  v_old_deal uuid;
  v_n       int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  for l in select * from public.so_line where so_id = p_so_id order by line_no loop
    if l.combo_line_id is not null then                                                                            -- asm-2b2(묶음 2): 구성품 줄은 값이 없다(0) — 다시 매기기 대상이 아니다 · 콤보 줄은 보통 줄처럼
      v_rows := v_rows || jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'kept', true, 'reason', 'combo_component', 'discount_pct', null, 'discount_source', null, 'changed', false);
      continue;
    end if;
    if l.price_override or l.discount_source in ('manual', 'shopify') then                                               -- ord-1a2 판정 433: shopify 줄은 다시 매기지 않는다
      v_rows := v_rows || jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'kept', true,
                  'reason', case when l.price_override then 'price_override' when l.discount_source = 'shopify' then 'shopify_discount' else 'manual_discount' end,
                  'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'changed', false);
      continue;
    end if;
    select * into q from public.so_line_quote(v_so, l.product_id, l.qty_ordered);
    v_diff := q.discount_pct is distinct from l.discount_pct or q.discount_source is distinct from l.discount_source or q.deal_line_id is distinct from l.deal_line_id;
    if v_diff then
      update public.so_line set
        discount_pct    = q.discount_pct,
        unit_price      = case when list_price is null then null else list_price * (1 - q.discount_pct / 100) end,
        discount_source = q.discount_source,
        deal_line_id    = q.deal_line_id,
        updated_by      = v_staff
      where id = l.id;
      v_changed := v_changed + 1;
    end if;
    v_rows := v_rows || jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'kept', false,
                'old_discount_pct', l.discount_pct, 'old_discount_source', l.discount_source, 'old_deal_line_id', l.deal_line_id,
                'new_discount_pct', q.discount_pct, 'new_discount_source', q.discount_source, 'new_deal_line_id', q.deal_line_id, 'changed', v_diff);
  end loop;

  -- 오더 전체 할인 — manual 은 덮지 않는다
  v_old_pct := v_so.order_discount_pct;  v_old_src := v_so.order_discount_source;  v_old_deal := v_so.order_discount_deal_id;
  perform public.so_order_discount_apply(p_so_id, v_staff);                 -- dsc-3a 판정 308 · 312: manual · 잠긴 오더(나뉜 가족)는 helper 가 건너뛴다 — 줄 할인은 위에서 다시 매겼다
  update public.so set reprice_suggested_at = null, updated_by = v_staff
  where id = p_so_id and status = 'draft' returning * into v_so;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order was not saved — it may have been changed by someone else just now — nothing was saved';
  end if;

  return jsonb_build_object(
    'so_number', v_so.so_number, 'lines', v_rows, 'changed_lines', v_changed,
    'order_discount', jsonb_build_object(
      'old_pct', v_old_pct, 'old_source', v_old_src, 'old_deal_id', v_old_deal,
      'new_pct', v_so.order_discount_pct, 'new_source', v_so.order_discount_source, 'new_deal_id', v_so.order_discount_deal_id,
      'kept', v_old_src is not distinct from 'manual' or v_so.order_discount_locked_at is not null, 'locked', v_so.order_discount_locked_at is not null,
      'changed', v_so.order_discount_pct is distinct from v_old_pct or v_so.order_discount_deal_id is distinct from v_old_deal));
end;
$$;

-- ═══ 4) 처리 — shop_order_process(shop_order): received → SO → created ═══
create function public.shop_order_process(p_shop_order_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_o       public.shop_order%rowtype;
  v_s       public.shop_store%rowtype;
  c         public.customer%rowtype;
  v_prev    jsonb;
  v_so      jsonb;
  v_so_id   uuid;
  v_so_row  public.so%rowtype;
  v_ship    jsonb;
  v_warn    jsonb := '[]'::jsonb;
  v_res     jsonb;
  l         record;
  q         record;
  v_line    public.so_line%rowtype;
  v_pct     numeric;
  v_ims_pct numeric;
  v_fl      jsonb;
  v_orig    numeric;
  v_disc    numeric;
  v_ims_tax numeric;
  v_paid    numeric;
  v_conf    jsonb := null;
  v_blocked text := null;
  v_po      text;
  v_note    text;
  v_n_lines int := 0;
begin
  select * into v_o from public.shop_order o where o.id = p_shop_order_id for update;
  if v_o.id is null then raise exception 'shop_order_process: shop order % not found — nothing was saved', p_shop_order_id; end if;
  if v_o.status <> 'received' then
    return jsonb_build_object('shop_order_id', v_o.id, 'status', v_o.status, 'skipped', true, 'message', 'not received (' || v_o.status || ')');
  end if;
  if v_o.shopify_cancelled_at is not null then                                                                               -- 판정 434: SO 가 생기기 전에 취소됐다
    return public.shop_order_cancelled(v_o.id);
  end if;
  if v_o.customer_id is null or v_o.location_id is null or jsonb_array_length(v_o.reasons) > 0 then
    update public.shop_order set status = 'needs_review' where id = v_o.id;
    return jsonb_build_object('shop_order_id', v_o.id, 'status', 'needs_review', 'skipped', true, 'message', 'prepare left reasons or no customer / warehouse');
  end if;
  select * into v_s from public.shop_store s where s.id = v_o.store_id;
  select * into c from public.customer x where x.id = v_o.customer_id;
  v_ship := v_o.raw->'shippingAddress';
  v_po   := coalesce(nullif(trim(v_o.raw->>'poNumber'), ''), (select nullif(trim(a->>'value'), '') from jsonb_array_elements(coalesce(v_o.raw->'customAttributes', '[]'::jsonb)) a where lower(a->>'key') in ('purchase_order(po)', 'purchase_order', 'po') limit 1));
  v_note := coalesce(nullif(trim(v_o.raw->>'note'), ''), (select nullif(trim(a->>'value'), '') from jsonb_array_elements(coalesce(v_o.raw->'customAttributes', '[]'::jsonb)) a where lower(a->>'key') in ('order note', 'order_note', 'note') limit 1));

  begin                                                                                                                      -- 실패하면 여기까지 되감긴다(SO 없음 · claims 도 되감김) → status error
    v_prev := public.shop_system_enter();
    -- ① 머리(so_create 그대로 · intake shopify · 손님 값 복사 · 오더 할인은 손님 딜로 찾힌다 → 아래서 0 으로)
    v_so := public.so_create(c.id, 'warehouse', 'shopify', v_o.location_id, null);
    v_so_id := (v_so->>'id')::uuid;
    -- ② 줄 — 단가 = Shopify 할인 뒤(판정 367 · 431 ③) · 같은 SKU 가 둘이어도 새 줄(p_force_new) · 0 원 줄은 promotion
    for l in select x.* from public.shop_order_line x where x.shop_order_id = v_o.id and x.match = 'ok' order by x.line_no loop
      v_res := public.so_line_add(v_so_id, l.product_id, l.quantity, coalesce(l.unit_price, 0), null, case when coalesce(l.unit_price, 0) = 0 then 'promotion' end, null, true);
      if v_res->>'action' <> 'added' then raise exception 'shop_order_process: line % (%) was not added (%) — nothing was saved', l.line_no, l.sku, v_res->>'action'; end if;
      v_pct := case when coalesce(l.list_price, 0) > 0 then round((l.list_price - coalesce(l.unit_price, 0)) / l.list_price * 100, 2) else 0 end;
      v_line := public.so_line_set_shopify((v_res->'line'->>'id')::uuid, l.list_price, greatest(0, least(100, v_pct)));
      update public.shop_order_line set so_line_id = v_line.id where id = l.id;
      v_n_lines := v_n_lines + 1;
      -- 할인 어긋남(판정 431 ③) — IMS 규칙(so_line_quote: 손님 기본 · 딜 · 세트)으로 셈한 % 와 대조 · 0.1 % 안은 같은 것(돈 반올림) · IMS 값으로 바꾸지 않는다
      select * into v_so_row from public.so where id = v_so_id;
      select * into q from public.so_line_quote(v_so_row, l.product_id, l.quantity);
      v_ims_pct := coalesce(q.discount_pct, 0);
      if abs(v_pct - v_ims_pct) > 0.1 then
        v_warn := v_warn || jsonb_build_object('code', 'discount_mismatch', 'line_no', l.line_no, 'sku', l.sku, 'shopify_pct', v_pct, 'ims_pct', v_ims_pct, 'ims_source', q.discount_source,
                                               'message', format('Line %s %s: Shopify discount %s%% but IMS rules give %s%% (%s) — the Shopify price was kept', l.line_no, l.sku, v_pct, v_ims_pct, coalesce(q.discount_source, 'none')));
      end if;
      if q.list_price is not null and l.list_price is not null and abs(q.list_price - l.list_price) > 0.005 then
        v_warn := v_warn || jsonb_build_object('code', 'list_price_mismatch', 'line_no', l.line_no, 'sku', l.sku, 'shopify_list', l.list_price, 'ims_list', q.list_price,
                                               'message', format('Line %s %s: Shopify list price %s but IMS tier price %s — the Shopify price was kept', l.line_no, l.sku, l.list_price, q.list_price));
      end if;
    end loop;
    if v_n_lines = 0 then raise exception 'shop_order_process: no matched lines — nothing was saved'; end if;
    -- ③ 머리 — ref · 메모(PO · Order Note) · 배송지 = Shopify 배송지(so_header_update 가 세금 규칙을 배송지로 다시 고른다 · 368)
    perform public.so_header_update(v_so_id, jsonb_build_object(                                                                -- null 도 보낸다 — SO 배송지 = Shopify 배송지 그대로(손님 기본 주소가 남지 않게)
      'ref', v_o.name,
      'comments', nullif(concat_ws(' · ', case when v_po is not null then 'PO ' || v_po end, v_note, 'Shopify ' || v_s.code || ' ' || v_o.name), ''),
      'ship_to_company', nullif(trim(v_ship->>'company'), ''), 'ship_to_contact', nullif(trim(v_ship->>'name'), ''), 'ship_to_phone', coalesce(nullif(trim(v_ship->>'phone'), ''), nullif(trim(v_o.raw->>'phone'), '')),
      'ship_to_line1', nullif(trim(v_ship->>'address1'), ''), 'ship_to_line2', nullif(trim(v_ship->>'address2'), ''), 'ship_to_city', nullif(trim(v_ship->>'city'), ''),
      'ship_to_state_province', coalesce(nullif(trim(v_ship->>'provinceCode'), ''), nullif(trim(v_ship->>'province'), '')), 'ship_to_postal_code', nullif(trim(v_ship->>'zip'), ''),
      'ship_to_country', coalesce(nullif(trim(v_ship->>'countryCodeV2'), ''), nullif(trim(v_ship->>'country'), ''))));
    -- ④ 오더 전체 할인 — 손님이 본 금액 그대로(431 ③): 손님 딜로 찾힌 오더 할인은 0(manual) 으로 · 경고
    select * into v_so_row from public.so where id = v_so_id;
    if coalesce(v_so_row.order_discount_pct, 0) > 0 then
      v_warn := v_warn || jsonb_build_object('code', 'order_discount_dropped', 'ims_pct', v_so_row.order_discount_pct, 'source', v_so_row.order_discount_source,
                                             'message', format('IMS would give an order discount of %s%% (%s) — not applied, the Shopify amounts were kept', v_so_row.order_discount_pct, v_so_row.order_discount_source));
      perform public.so_header_update(v_so_id, '{"order_discount_pct": 0}'::jsonb);
    end if;
    -- ⑤ 운임 — aone 만(판정 369: 손님이 낸 배송비 = 확정 운임 · 무료 배송 = 운임 + 100 %) · asung 은 담기만(열어 둠)
    v_fl := v_o.raw->'shippingLines'->'nodes'->0;
    v_orig := (v_fl->'originalPriceSet'->'shopMoney'->>'amount')::numeric;
    v_disc := (v_fl->'discountedPriceSet'->'shopMoney'->>'amount')::numeric;
    if v_s.kind = 'aone' and coalesce(v_orig, 0) > 0 then
      perform public.so_charge_set(v_so_id, coalesce(nullif(trim(v_fl->>'title'), ''), 'Freight'), v_orig, null, 'Shopify ' || v_o.name, null, null,
                                   case when coalesce(v_disc, v_orig) = 0 then 100 end,
                                   case when coalesce(v_disc, v_orig) > 0 and v_disc < v_orig then round(v_orig - v_disc, 2) end);
    elsif v_s.kind <> 'aone' and coalesce(v_orig, 0) > 0 then
      v_warn := v_warn || jsonb_build_object('code', 'freight_not_applied', 'amount', v_orig, 'title', v_fl->>'title', 'message', format('Shopify charged freight %s (%s) — not put on the IMS order (asung.ca web freight is still an open question)', v_orig, v_fl->>'title'));
    end if;
    -- ⑥ 세금(판정 368) — IMS 가 셈한 세금 ↔ Shopify totalTax
    select t.tax into v_ims_tax from public.so_totals_many(array[v_so_id]) t;
    if v_o.total_tax is not null and abs(coalesce(v_ims_tax, 0) - v_o.total_tax) > 0.005 then
      v_warn := v_warn || jsonb_build_object('code', 'tax_mismatch', 'ims', round(coalesce(v_ims_tax, 0), 2), 'shopify', v_o.total_tax,
                                             'message', format('IMS tax %s but Shopify charged %s — check the tax rule and the ship-to province', round(coalesce(v_ims_tax, 0), 2), v_o.total_tax));
    end if;
    -- ⑦ 결제(판정 370) — aone 카드 · Shopify 가 받음 → 오더에 묶인 선결제 · asung NetTerm(pending) 은 없음
    if v_s.kind = 'aone' and upper(coalesce(v_o.financial_status, '')) = 'PAID' and coalesce(v_o.total, 0) > 0 then
      v_paid := round(v_o.total, 2);
      v_res := public.so_payment_add(jsonb_build_object('customer_id', c.id, 'amount', v_paid, 'method', 'shopify', 'reference', v_o.name, 'warehouse_id', v_o.location_id,
                                                        'note', 'Shopify ' || v_s.code || ' ' || v_o.name || ' (paid online)', 'target_so_ids', jsonb_build_array(v_so_id)));
    end if;
    -- ⑧ 확정(판정 371) — 막히면 draft 로 두고 까닭을 경고에
    begin
      v_conf := public.so_confirm(v_so_id);
    exception when others then
      v_blocked := sqlerrm;
    end;
    if v_blocked is not null then
      v_warn := v_warn || jsonb_build_object('code', 'confirm_blocked', 'message', v_blocked);
    end if;
    perform public.shop_system_leave(v_prev);
  exception when others then
    update public.shop_order set status = 'error', error = left(sqlerrm, 1000), processed_at = now() where id = v_o.id;
    return jsonb_build_object('shop_order_id', v_o.id, 'status', 'error', 'error', left(sqlerrm, 1000));
  end;

  update public.shop_order set status = 'created', so_id = v_so_id, processed_at = now(), so_baseline_at = now(), error = null, warnings = warnings || v_warn where id = v_o.id;
  select * into v_so_row from public.so where id = v_so_id;
  return jsonb_build_object('shop_order_id', v_o.id, 'status', 'created', 'so_id', v_so_id, 'so_number', v_so_row.so_number, 'so_status', v_so_row.status, 'lines', v_n_lines,
                            'confirmed', v_blocked is null, 'confirm', v_conf, 'payment', v_paid, 'warnings', v_warn);
end;
$$;
revoke all on function public.shop_order_process(uuid) from public, anon, authenticated;
comment on function public.shop_order_process(uuid) is 'ord-1a2 판정 367 ~ 371 · 431 ③ · 432: 받은 오더(received · 손님 · 창고 정해짐 · 까닭 0)를 IMS 오더로 — 시스템 직원이 되어(shop_system_enter) so_create(intake shopify) → so_line_add(단가 = Shopify 할인 뒤) + so_line_set_shopify(정가 · % · 출처 shopify) → so_header_update(ref = Shopify 이름 · 메모 PO · Order Note · 배송지 = Shopify 배송지 → 세금 규칙) → 오더 할인 0 → aone 운임(so_charge_set · 무료 배송 = 100 %) → aone PAID 결제(so_payment_add method shopify) → so_confirm(막히면 draft + confirm_blocked) → created · so_id · so_baseline_at · 경고 discount_mismatch(SKU · Shopify % · IMS %) · list_price_mismatch · tax_mismatch · order_discount_dropped · freight_not_applied · 값은 바꾸지 않는다 · 실패하면 error(SO 는 트랜잭션째 없음) · service_role 만(EF drain: ingest → process)';

-- ═══ 5) 취소(판정 434) ═══
create function public.shop_order_cancelled(p_shop_order_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_o      public.shop_order%rowtype;
  v_so     public.so%rowtype;
  v_prev   jsonb;
  v_res    jsonb;
  v_changed timestamptz;
  v_why    text;
begin
  select * into v_o from public.shop_order o where o.id = p_shop_order_id for update;
  if v_o.id is null then raise exception 'shop_order_cancelled: shop order % not found — nothing was saved', p_shop_order_id; end if;
  if v_o.shopify_cancelled_at is null then return jsonb_build_object('shop_order_id', v_o.id, 'status', v_o.status, 'skipped', true, 'message', 'not cancelled in Shopify'); end if;
  if v_o.status in ('received', 'needs_review', 'error') then                                                                -- SO 가 생기기 전 — 그냥 닫는다
    update public.shop_order set status = 'cancelled', processed_at = coalesce(processed_at, now()) where id = v_o.id;
    return jsonb_build_object('shop_order_id', v_o.id, 'status', 'cancelled', 'action', 'closed_before_so');
  end if;
  if v_o.status <> 'created' or v_o.so_id is null then return jsonb_build_object('shop_order_id', v_o.id, 'status', v_o.status, 'skipped', true); end if;
  select * into v_so from public.so s where s.id = v_o.so_id;
  select greatest(v_so.updated_at, (select max(l.updated_at) from public.so_line l where l.so_id = v_so.id), (select max(h.updated_at) from public.so_charge h where h.so_id = v_so.id)) into v_changed;
  if v_so.status = 'cancelled' then
    update public.shop_order set status = 'cancelled' where id = v_o.id;
    return jsonb_build_object('shop_order_id', v_o.id, 'status', 'cancelled', 'action', 'so_already_cancelled');
  end if;
  v_why := case when v_so.status not in ('draft', 'confirmed') then 'in_warehouse'
                when v_o.so_baseline_at is null or v_changed > v_o.so_baseline_at then 'changed_in_ims' end;
  if v_why is null then
    begin
      v_prev := public.shop_system_enter();
      v_res := public.so_cancel(v_so.id, 'Cancelled in Shopify — order ' || v_o.name, '{}', true, false);
      perform public.shop_system_leave(v_prev);
    exception when others then
      v_why := 'cancel_failed: ' || sqlerrm;
    end;
  end if;
  if v_why is null then
    update public.shop_order set status = 'cancelled', warnings = warnings || jsonb_build_array(jsonb_build_object('code', 'auto_cancelled', 'at', now(), 'so_number', v_so.so_number, 'message', format('IMS order %s was cancelled automatically — cancelled in Shopify at %s and untouched in IMS', v_so.so_number, v_o.shopify_cancelled_at)))
     where id = v_o.id;
    return jsonb_build_object('shop_order_id', v_o.id, 'status', 'cancelled', 'action', 'auto_cancelled', 'so_number', v_so.so_number, 'so_cancel', v_res);
  end if;
  update public.shop_order set warnings = warnings || jsonb_build_array(jsonb_build_object('code', case when v_why like 'cancel_failed%' then 'cancel_failed' else 'cancel_needs_review' end, 'reason', v_why, 'at', now(), 'so_number', v_so.so_number, 'so_status', v_so.status,
                                             'message', format('Shopify order %s was cancelled (%s) but IMS order %s is %s — check it by hand', v_o.name, v_o.shopify_cancelled_at, v_so.so_number,
                                                               case v_why when 'in_warehouse' then 'already at the warehouse (' || v_so.status || ')' when 'changed_in_ims' then 'changed in IMS since it was created' else 'not cancellable: ' || v_why end)))
   where id = v_o.id;
  return jsonb_build_object('shop_order_id', v_o.id, 'status', v_o.status, 'action', 'needs_review', 'reason', v_why, 'so_number', v_so.so_number, 'so_status', v_so.status);
end;
$$;
revoke all on function public.shop_order_cancelled(uuid) from public, anon, authenticated;
comment on function public.shop_order_cancelled(uuid) is 'ord-1a2 판정 372 · 434: Shopify 에서 취소된 받은 오더 — SO 전이면 cancelled · SO 가 draft | confirmed 이고 so_baseline_at 뒤 so · so_line · so_charge 가 안 바뀌었으면 시스템이 so_cancel(reopen_superseded false) → cancelled + auto_cancelled · 바뀌었거나(changed_in_ims) 창고로 간 뒤(in_warehouse)면 경고 cancel_needs_review 만 · 실패하면 cancel_failed · service_role 만(ingest 가 부른다)';

-- ═══ 6) 직원 창구 — 줄 고르기 ═══
create function public.shop_order_resolve_lines(p_shop_order_id uuid, p_choices jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_o      public.shop_order%rowtype;
  v_c      jsonb;
  v_l      public.shop_order_line%rowtype;
  p        public.product%rowtype;
  v_plan   jsonb := '[]'::jsonb;
  v_blocks jsonb := '[]'::jsonb;
  v_warns  jsonb := '[]'::jsonb;
  v_keys   text[];
  v_unacked text[];
  v_pid    uuid;
begin
  perform public.ims_require_write('sales', 'saved');                                                                        -- ⭐ 유일한 문 — 첫 줄
  v_staff := public.so_current_staff();
  select * into v_o from public.shop_order o where o.id = p_shop_order_id for update;
  if v_o.id is null then raise exception 'Shop order not found — nothing was saved'; end if;
  if v_o.status not in ('received', 'needs_review') then raise exception 'Shop order % is already % — nothing was saved', v_o.name, v_o.status; end if;
  if p_choices is null or jsonb_typeof(p_choices) <> 'array' or jsonb_array_length(p_choices) = 0 then raise exception 'p_choices must be a JSON array [{line_no, sku | product_id | drop}] — nothing was saved'; end if;
  for v_c in select x from jsonb_array_elements(p_choices) as x loop
    select * into v_l from public.shop_order_line x where x.shop_order_id = v_o.id and x.line_no = (v_c->>'line_no')::int;
    if v_l.id is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'line_unknown:' || coalesce(v_c->>'line_no', '?'), 'code', 'line_unknown', 'message', format('Line %s is not on this order — nothing was saved', coalesce(v_c->>'line_no', '?')));
      continue;
    end if;
    if coalesce((v_c->>'drop')::boolean, false) then
      v_warns := v_warns || jsonb_build_object('key', 'drop:' || v_l.line_no, 'code', 'line_dropped', 'line_no', v_l.line_no, 'sku', v_l.sku, 'message', format('Line %s (%s × %s) will be left off the IMS order — the customer still paid for it in Shopify. Confirm to drop it', v_l.line_no, coalesce(v_l.sku, '?'), v_l.quantity));
      v_plan := v_plan || jsonb_build_object('line_no', v_l.line_no, 'action', 'drop');
      continue;
    end if;
    v_pid := null;
    if nullif(v_c->>'product_id', '') is not null then select * into p from public.product x where x.id = (v_c->>'product_id')::uuid;
    elsif nullif(trim(v_c->>'sku'), '') is not null then select * into p from public.product x where x.sku = trim(v_c->>'sku');
    else p := null; end if;
    if p.id is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'product_unknown:' || v_l.line_no, 'code', 'product_unknown', 'message', format('Line %s: product %s not found — nothing was saved', v_l.line_no, coalesce(v_c->>'sku', v_c->>'product_id', '(none)')));
    elsif not p.is_active then
      v_blocks := v_blocks || jsonb_build_object('key', 'product_inactive:' || v_l.line_no, 'code', 'product_inactive', 'message', format('Line %s: product %s is inactive — nothing was saved', v_l.line_no, p.sku));
    elsif not p.sellable then
      v_blocks := v_blocks || jsonb_build_object('key', 'product_not_sellable:' || v_l.line_no, 'code', 'product_not_sellable', 'message', format('Line %s: product %s is not for sale — nothing was saved', v_l.line_no, p.sku));
    else
      v_plan := v_plan || jsonb_build_object('line_no', v_l.line_no, 'action', 'replace', 'from_sku', v_l.sku, 'to_sku', p.sku, 'product_id', p.id);
    end if;
  end loop;
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'shop_order_id', v_o.id, 'name', v_o.name, 'plan', v_plan, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;
  for v_c in select x from jsonb_array_elements(v_plan) as x loop
    if v_c->>'action' = 'drop' then
      delete from public.shop_order_line where shop_order_id = v_o.id and line_no = (v_c->>'line_no')::int;
    else
      update public.shop_order_line set product_id = (v_c->>'product_id')::uuid, sku = v_c->>'to_sku', match = 'ok' where shop_order_id = v_o.id and line_no = (v_c->>'line_no')::int;
    end if;
  end loop;
  update public.shop_order set warnings = warnings || jsonb_build_array(jsonb_build_object('code', 'lines_resolved', 'at', now(), 'by', v_staff, 'plan', v_plan, 'message', 'Lines were changed by staff before the IMS order was created')) where id = v_o.id;
  return jsonb_build_object('committed', true, 'shop_order_id', v_o.id, 'name', v_o.name, 'plan', v_plan, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb, 'prepare', public.shop_order_prepare(v_o.id));
end;
$$;
revoke all on function public.shop_order_resolve_lines(uuid, jsonb, boolean, text[]) from public, anon;
grant execute on function public.shop_order_resolve_lines(uuid, jsonb, boolean, text[]) to authenticated;
comment on function public.shop_order_resolve_lines(uuid, jsonb, boolean, text[]) is 'ord-1a2 판정 366: 직원이 받은 오더의 줄을 고친다 — p_choices [{line_no, sku | product_id}] 다른 SKU 로 잇기(켜진 · 판매 가능만 · Shopify 가격은 그대로) · [{line_no, drop true}] 줄 빼기(경고 drop:<line_no> 를 ack) · definer · 첫 줄 ims_require_write(sales) · 두 번 부르기 · 저장 뒤 prepare → received 면 EF drain 이 process';

-- ═══ 7) shop_order_ingest 재발행 — 취소 받기 ═══
create or replace function public.shop_order_ingest(p_store_id uuid, p_order jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_s       public.shop_store%rowtype;
  v_gid     text;
  v_o       public.shop_order%rowtype;
  v_action  text;
  v_ship    jsonb := p_order->'shippingAddress';
  v_fl      jsonb;
  v_li      jsonb;
  v_i       int := 0;
  v_n       int := 0;
  v_warn    jsonb;
  v_prep    jsonb := null;
  v_cancel  timestamptz := nullif(p_order->>'cancelledAt', '')::timestamptz;
begin
  select * into v_s from public.shop_store s where s.id = p_store_id;
  if v_s.id is null then raise exception 'shop_order_ingest: store % not found — nothing was saved', p_store_id; end if;
  if not v_s.is_active then raise exception 'shop_order_ingest: store % is off — nothing was saved', v_s.code; end if;
  if p_order is null or jsonb_typeof(p_order) <> 'object' then raise exception 'shop_order_ingest: p_order must be the GraphQL order object — nothing was saved'; end if;
  v_gid := p_order->>'id';
  if v_gid !~ '^gid://shopify/Order/[0-9]+$' then raise exception 'shop_order_ingest: order id % is not a Shopify Order GID — nothing was saved', coalesce(v_gid, '(none)'); end if;
  if nullif(p_order->>'name', '') is null then raise exception 'shop_order_ingest: order % has no name — nothing was saved', v_gid; end if;
  if coalesce(jsonb_typeof(p_order->'lineItems'->'nodes'), '') <> 'array' then raise exception 'shop_order_ingest: order % has no lineItems.nodes — nothing was saved', v_gid; end if;   -- coalesce: 칸이 없으면 jsonb_typeof 가 null 이라 if 가 조용히 지나간다(1회차 T8)
  v_fl := p_order->'shippingLines'->'nodes'->0;

  select * into v_o from public.shop_order o where o.shopify_order_gid = v_gid for update;
  if v_o.id is null then
    insert into public.shop_order (store_id, shopify_order_gid, name, shopify_created_at, shopify_updated_at, shopify_cancelled_at, is_test, financial_status, source_name, email, shopify_customer_gid,
                                   ship_province_code, ship_country_code, currency_code, subtotal, total_discounts, total_shipping, total_tax, total, freight_amount, freight_title, raw, status)
    values (v_s.id, v_gid, p_order->>'name', nullif(p_order->>'createdAt', '')::timestamptz, nullif(p_order->>'updatedAt', '')::timestamptz, v_cancel, coalesce((p_order->>'test')::boolean, false),
            p_order->>'displayFinancialStatus', p_order->>'sourceName', nullif(lower(trim(coalesce(p_order->>'email', p_order->'customer'->'defaultEmailAddress'->>'emailAddress'))), ''), nullif(p_order->'customer'->>'id', ''),
            nullif(upper(trim(v_ship->>'provinceCode')), ''), nullif(upper(trim(v_ship->>'countryCodeV2')), ''), p_order->>'currencyCode',
            (p_order->'subtotalPriceSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalDiscountsSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalShippingPriceSet'->'shopMoney'->>'amount')::numeric,
            (p_order->'totalTaxSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalPriceSet'->'shopMoney'->>'amount')::numeric,
            (v_fl->'discountedPriceSet'->'shopMoney'->>'amount')::numeric, v_fl->>'title', p_order, 'received')
    returning * into v_o;
    v_action := 'inserted';
  else
    if v_o.status in ('received', 'needs_review') then
      update public.shop_order set name = p_order->>'name', shopify_created_at = nullif(p_order->>'createdAt', '')::timestamptz, shopify_updated_at = nullif(p_order->>'updatedAt', '')::timestamptz, shopify_cancelled_at = v_cancel,
             is_test = coalesce((p_order->>'test')::boolean, false), financial_status = p_order->>'displayFinancialStatus', source_name = p_order->>'sourceName',
             email = nullif(lower(trim(coalesce(p_order->>'email', p_order->'customer'->'defaultEmailAddress'->>'emailAddress'))), ''), shopify_customer_gid = nullif(p_order->'customer'->>'id', ''),
             ship_province_code = nullif(upper(trim(v_ship->>'provinceCode')), ''), ship_country_code = nullif(upper(trim(v_ship->>'countryCodeV2')), ''), currency_code = p_order->>'currencyCode',
             subtotal = (p_order->'subtotalPriceSet'->'shopMoney'->>'amount')::numeric, total_discounts = (p_order->'totalDiscountsSet'->'shopMoney'->>'amount')::numeric, total_shipping = (p_order->'totalShippingPriceSet'->'shopMoney'->>'amount')::numeric,
             total_tax = (p_order->'totalTaxSet'->'shopMoney'->>'amount')::numeric, total = (p_order->'totalPriceSet'->'shopMoney'->>'amount')::numeric,
             freight_amount = (v_fl->'discountedPriceSet'->'shopMoney'->>'amount')::numeric, freight_title = v_fl->>'title', raw = p_order, status = 'received', reasons = '[]'::jsonb, error = null
       where id = v_o.id returning * into v_o;
      delete from public.shop_order_line where shop_order_id = v_o.id;                                                                          -- 줄은 다시 푼다(SO 가 없으니 자유)
      v_action := 'updated';
    else                                                                                                                                       -- created · cancelled · error: 원문만 갱신 · SO · 줄 무접촉(판정 372)
      v_warn := jsonb_build_object('code', case when v_o.status = 'created' then 'updated_after_so' else 'updated_after_' || v_o.status end, 'at', now(),
                                   'message', format('Shopify order %s changed after IMS %s it (Shopify updatedAt %s) — check the Shopify order and the IMS order by hand', p_order->>'name', v_o.status, p_order->>'updatedAt'));
      update public.shop_order set shopify_updated_at = nullif(p_order->>'updatedAt', '')::timestamptz, shopify_cancelled_at = v_cancel, financial_status = p_order->>'displayFinancialStatus', raw = p_order,
             warnings = warnings || (case when nullif(p_order->>'updatedAt', '')::timestamptz is distinct from v_o.shopify_updated_at then jsonb_build_array(v_warn) else '[]'::jsonb end)
                                 || (case when v_cancel is not null and v_o.shopify_cancelled_at is null
                                          then jsonb_build_array(jsonb_build_object('code', 'cancelled_in_shopify', 'at', now(), 'message', format('Shopify order %s was cancelled in Shopify (%s) — the IMS order is untouched until shop_order_cancelled runs (ord-1a2)', p_order->>'name', v_cancel)))
                                          else '[]'::jsonb end)
       where id = v_o.id returning * into v_o;
      v_action := 'updated_after_' || v_o.status;
    end if;
  end if;

  if v_action in ('inserted', 'updated') then
    for v_li in select x from jsonb_array_elements(p_order->'lineItems'->'nodes') as x loop
      v_i := v_i + 1;
      if coalesce((v_li->>'quantity')::numeric, 0) <= 0 then continue; end if;
      insert into public.shop_order_line (shop_order_id, line_gid, line_no, sku, name, quantity, list_price, discount_amount, unit_price)
      values (v_o.id, coalesce(nullif(v_li->>'id', ''), 'line-' || v_i), v_i, nullif(trim(coalesce(v_li->>'sku', v_li->'variant'->>'sku')), ''), v_li->>'name', (v_li->>'quantity')::numeric,
              (v_li->'originalUnitPriceSet'->'shopMoney'->>'amount')::numeric, (v_li->'totalDiscountSet'->'shopMoney'->>'amount')::numeric, (v_li->'discountedUnitPriceAfterAllDiscountsSet'->'shopMoney'->>'amount')::numeric);
      v_n := v_n + 1;
    end loop;
    v_prep := public.shop_order_prepare(v_o.id);
    if v_cancel is not null then perform public.shop_order_cancelled(v_o.id); end if;                                   -- ord-1a2 판정 434: SO 가 생기기 전에 취소됐으면 그냥 cancelled
    select * into v_o from public.shop_order o where o.id = v_o.id;
  elsif v_cancel is not null and v_o.status = 'created' and (select x.shopify_cancelled_at from public.shop_order x where x.id = v_o.id) is not null and not exists (select 1 from jsonb_array_elements(v_o.warnings) w where w->>'code' in ('auto_cancelled', 'cancel_needs_review', 'cancel_failed')) then
    perform public.shop_order_cancelled(v_o.id);                                                                      -- ord-1a2 판정 434: SO 가 있는 오더의 취소 — 한 번만
    select * into v_o from public.shop_order o where o.id = v_o.id;
  end if;

  return jsonb_build_object('shop_order_id', v_o.id, 'action', v_action, 'status', v_o.status, 'name', v_o.name, 'lines', v_n,
                            'customer_id', v_o.customer_id, 'location_id', v_o.location_id, 'reasons', v_o.reasons, 'warnings', v_o.warnings, 'prepare', v_prep);
end;
$$;

-- ═══ 8) 뷰 — 끝에 so_baseline_at ═══
create or replace view public.shop_order_list
  with (security_invoker = true) as
  select o.id, o.store_id, s.code as store_code, o.shopify_order_gid, o.name, o.status, o.shopify_created_at, o.shopify_updated_at, o.shopify_cancelled_at, o.is_test,
         o.financial_status, o.source_name, o.email, o.shopify_customer_gid, o.ship_province_code, o.ship_country_code, o.currency_code,
         o.subtotal, o.total_discounts, o.total_shipping, o.total_tax, o.total, o.freight_amount, o.freight_title,
         o.customer_id, c.name as customer_name, o.location_id, w.name as location_name, o.so_id, so.so_number, so.status as so_status,
         o.reasons, jsonb_array_length(o.reasons) as reason_count, o.warnings, jsonb_array_length(o.warnings) as warning_count,
         (select count(*) from public.shop_order_line l where l.shop_order_id = o.id) as line_count,
         (select count(*) from public.shop_order_line l where l.shop_order_id = o.id and l.match is distinct from 'ok') as unmatched_count,
         o.received_at, o.processed_at, o.error, o.updated_at,
         o.so_baseline_at
    from public.shop_order o
    join public.shop_store s on s.id = o.store_id
    left join public.customer c on c.id = o.customer_id
    left join public.ref_warehouse w on w.id = o.location_id
    left join public.so so on so.id = o.so_id;

-- ═══ 끝 — 자기 점검 ═══
do $$ declare v_src text; begin
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'so_line_discount_source_ck') not like '%shopify%' then raise exception 'ord-1a2: discount_source CHECK missing shopify'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_line_set_shopify', 'shop_order_process', 'shop_order_cancelled', 'shop_order_resolve_lines')) <> 4 then raise exception 'ord-1a2: functions missing'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_create';
  if v_src not like '%''shopify'')%' then raise exception 'ord-1a2: so_create not re-issued'; end if;
  foreach v_src in array array['so_line_requote', 'so_line_update', 'so_reprice'] loop
    if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = v_src) not like '%shopify%' then raise exception 'ord-1a2: % not re-issued', v_src; end if;
  end loop;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest') not like '%shop_order_cancelled%' then raise exception 'ord-1a2: ingest not re-issued'; end if;
  if has_function_privilege('authenticated', 'public.shop_order_process(uuid)', 'execute') or has_function_privilege('authenticated', 'public.shop_order_cancelled(uuid)', 'execute') or has_function_privilege('authenticated', 'public.so_line_set_shopify(uuid, numeric, numeric)', 'execute') then raise exception 'ord-1a2: system functions must not be executable by authenticated'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_order_list' and column_name = 'so_baseline_at') <> 1 then raise exception 'ord-1a2: view column missing'; end if;
end $$;
