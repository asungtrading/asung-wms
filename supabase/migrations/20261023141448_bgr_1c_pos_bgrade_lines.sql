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

-- ═══ bgr-1c — B급 칸 ③ POS 의 B급 줄 (2026-10-23 · 판정 633 · 634 ② · 635 · 642 · 644 · 646 · 647) ═══
--   ① 창구 so_line_bgrade_set(줄 → B급 · 칸 생략 시 후보 하나면 그 칸 · 여럿이면 action choose · 같은 칸 · SKU 의 B급 줄이 있으면 합친다) · so_line_bgrade_clear(정상으로 되돌리기 · 다시 견적)
--   ② POS 에서만 — so_line 가드 트리거(bgrade_bin_id 는 창구 표지 ims.bgrade_line 로만 · channel pos · draft · 그 창고의 B급 칸 · B급 줄은 값 · 할인 칸을 손으로 못 바꾸고 다른 오더로 못 간다 · 나뉘지 않는다)
--      + so 머리 가드(B급 줄이 있으면 창고 · 채널을 못 바꾼다) + 원장 가드 재발행(B급 칸의 판매 출고 = 그 칸의 B급 줄만 · B급 줄은 그 칸에서만 나간다)
--   ③ 합치기 길 — so_line_add · so_lines_paste 재발행(값이 같아도 B급 줄과 합치지 않는다 · 「같은 SKU 다른 값」 ask 에서도 뺀다)
--   ④ so_lines_available drop + create(B급 줄 = 그 칸의 B급 가용 · 반환 끝 칸 둘) ⑥ so_detail 재발행(줄에 bgrade_bin · is_bgrade_line)
--   ⑤ 확정 · 출고는 손대지 않는다 — so_allocate_all 은 B급 줄도 잡고(1a alloc 이 뺀다) · so_pick_plan(1a)이 B급 줄의 모자람을 그 칸에 둔다(음수 · 647) · 줄 값은 넣은 값 그대로(646)
--   633 은 이미 선다 — price_override 줄은 so_line_manual(손님 할인 · 다시 매기기 kept · 오더 할인 바탕에서 빠짐 · 문턱 so_lines_total 에는 들어감)

-- ═══ ② so_line 가드 ═══
create function public.so_line_bgrade_guard() returns trigger
language plpgsql set search_path = public, pg_temp as $$
-- bgr-1c 판정 635: B급 줄(bgrade_bin_id)은 so_line_bgrade_set · clear(표지 ims.bgrade_line)만 세우고 지운다 · 세울 때 POS · draft · 그 오더 창고의 B급 칸
declare v_flag boolean := coalesce(current_setting('ims.bgrade_line', true), '') = 'on';  v_s record;  v_ok boolean;
begin
  if tg_op = 'INSERT' then
    if new.bgrade_bin_id is not null and not v_flag then
      raise exception using errcode = 'IM638', message = format('B-grade lines are made only with the B-grade button on a POS line (%s) — nothing was saved', new.sku);
    end if;
    if new.split_from_line_id is not null and exists (select 1 from public.so_line l where l.id = new.split_from_line_id and l.bgrade_bin_id is not null) then
      raise exception using errcode = 'IM638', message = format('A B-grade line (%s) is not split or copied to another order — nothing was saved', new.sku);
    end if;
  else
    if new.bgrade_bin_id is distinct from old.bgrade_bin_id and not v_flag then
      raise exception using errcode = 'IM638', message = format('Line %s: B-grade is set or cleared only with the B-grade button on the POS — nothing was saved', old.line_no);
    end if;
    if old.bgrade_bin_id is not null and new.bgrade_bin_id is not null then
      if new.so_id is distinct from old.so_id then
        raise exception using errcode = 'IM638', message = format('Line %s is a B-grade line — it stays on its POS order — nothing was saved', old.line_no);
      end if;
      if not v_flag and (new.unit_price, new.discount_pct, new.discount_source, new.price_override, new.free_reason, new.deal_line_id)
                        is distinct from (old.unit_price, old.discount_pct, old.discount_source, old.price_override, old.free_reason, old.deal_line_id) then
        raise exception using errcode = 'IM638', message = format('Line %s is a B-grade line — its price comes from the B-grade bin; change the bin price (reprice) or clear B-grade — nothing was saved', old.line_no);
      end if;
    end if;
  end if;
  if new.bgrade_bin_id is not null and (tg_op = 'INSERT' or new.bgrade_bin_id is distinct from old.bgrade_bin_id) then
    select s.channel, s.status, s.so_number, s.location_id into v_s from public.so s where s.id = new.so_id;
    if v_s.channel is distinct from 'pos' or v_s.status is distinct from 'draft' then
      raise exception using errcode = 'IM638', message = format('B-grade lines are POS only, on a draft order (%s is %s · %s) — nothing was saved', v_s.so_number, v_s.channel, v_s.status);
    end if;
    select exists (select 1 from public.ref_bin rb where rb.id = new.bgrade_bin_id and rb.is_bgrade and rb.warehouse_id = v_s.location_id) into v_ok;
    if not v_ok then
      raise exception using errcode = 'IM638', message = format('Bin for line %s is not a B-grade bin of this order''s store — nothing was saved', new.line_no);
    end if;
  end if;
  return new;
end $$;
revoke all on function public.so_line_bgrade_guard() from public, anon, authenticated, service_role;
create trigger so_line_bgrade_guard before insert or update on public.so_line for each row execute function public.so_line_bgrade_guard();

create function public.so_bgrade_header_guard() returns trigger
language plpgsql set search_path = public, pg_temp as $$
-- bgr-1c: B급 줄이 있는 오더는 창고 · 채널을 바꾸지 못한다(칸은 그 창고의 B급 칸 · B급은 POS 에서만)
begin
  if (new.location_id is distinct from old.location_id or new.channel is distinct from old.channel)
     and exists (select 1 from public.so_line l where l.so_id = new.id and l.bgrade_bin_id is not null) then
    raise exception using errcode = 'IM638', message = format('Order %s has B-grade lines — clear them before changing the store or the channel — nothing was saved', old.so_number);
  end if;
  return new;
end $$;
revoke all on function public.so_bgrade_header_guard() from public, anon, authenticated, service_role;
create trigger so_bgrade_header_guard before update of location_id, channel on public.so for each row execute function public.so_bgrade_header_guard();

-- ═══ ① 창구 — 줄을 B급으로 ═══
create function public.so_line_bgrade_set(p_line_id uuid, p_bin_id uuid default null) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
-- bgr-1c 판정 634 ② · 642 · 644: POS 줄의 「B-grade」 — 값 = 그 칸의 B급 값(살아 있는 값만) · 칸 생략: 잔고 있는 B급 칸이 하나면 그 칸 · 여럿이면 action choose(저장 없음) · 없으면 거부
--   같은 오더에 같은 칸 · 같은 SKU 의 B급 줄이 있으면 그 줄에 수량을 더하고 이 줄을 지운다 · 정상 줄과는 합치지 않는다
declare v_staff uuid;  v_line public.so_line%rowtype;  v_so public.so%rowtype;  v_p public.product%rowtype;  v_b public.ref_bin%rowtype;  v_wh text;
        v_c jsonb;  v_bal numeric;  v_price numeric;  v_other public.so_line%rowtype;  v_out public.so_line%rowtype;  v_action text;  v_merge boolean;
begin
  perform public.ims_require_write('sales', 'saved');
  v_staff := public.so_current_staff();
  select * into v_line from public.so_line where id = p_line_id for update;
  if not found then raise exception 'Order line not found — nothing was saved'; end if;
  v_so := public.so_require_draft(v_line.so_id, 'saved');
  if v_so.channel <> 'pos' then raise exception 'B-grade is sold at the POS only — order % is a % order — nothing was saved', v_so.so_number, v_so.channel; end if;
  if v_line.combo_line_id is not null or exists (select 1 from public.so_line c where c.combo_line_id = v_line.id) then
    raise exception 'Line % is part of a combo — B-grade is for single items — nothing was saved', v_line.line_no;
  end if;
  select * into v_p from public.product p where p.id = v_line.product_id;
  if v_p.parent_product_id is not null then raise exception 'Line % (%) is a set or pack — B-grade is sold by the single unit — nothing was saved', v_line.line_no, v_line.sku; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_so.location_id;
  if p_bin_id is null then
    select coalesce(jsonb_agg(jsonb_build_object('bin_id', x.id, 'bin', x.name, 'price', x.price, 'has_price', x.price is not null, 'qty', x.bal) order by x.price nulls last, x.name), '[]'::jsonb) into v_c
      from (select rb.id, rb.name, bp.price, public.inv_adjust_ledger(v_wh, rb.name, v_p.sku) as bal
              from public.ref_bin rb left join public.bgrade_price bp on bp.bin_id = rb.id and bp.product_id = v_p.id
             where rb.is_bgrade and rb.is_active and rb.warehouse_id = v_so.location_id) x
     where x.bal > 0;
    if jsonb_array_length(v_c) = 0 then raise exception 'No B-grade stock of % at % — nothing was saved', v_p.sku, v_wh; end if;
    if jsonb_array_length(v_c) > 1 then
      return jsonb_build_object('action', 'choose', 'so_number', v_so.so_number, 'line_id', v_line.id, 'sku', v_p.sku, 'candidates', v_c,
                                'message', 'This item is in more than one B-grade bin — pick the bin (its price) — nothing was saved');
    end if;
    p_bin_id := (v_c->0->>'bin_id')::uuid;
  end if;
  select * into v_b from public.ref_bin rb where rb.id = p_bin_id;
  if not found then raise exception 'Bin not found (%) — nothing was saved', p_bin_id; end if;
  if not v_b.is_bgrade then raise exception 'Bin % is not a B-grade bin — nothing was saved', v_b.name; end if;
  if v_b.warehouse_id is distinct from v_so.location_id then raise exception 'Bin % is at another store — nothing was saved', v_b.name; end if;
  v_bal := public.inv_adjust_ledger(v_wh, v_b.name, v_p.sku);
  if v_bal <= 0 then raise exception 'No B-grade stock of % in bin % — its B-grade price is no longer live; put found stock in with an adjustment and set a price first — nothing was saved', v_p.sku, v_b.name; end if;
  select bp.price into v_price from public.bgrade_price bp where bp.bin_id = v_b.id and bp.product_id = v_p.id;
  if v_price is null then raise exception 'No B-grade price for % in bin % — ask a manager to set it (B-grade stock without a price cannot be sold) — nothing was saved', v_p.sku, v_b.name; end if;
  if v_line.bgrade_bin_id = v_b.id then
    return jsonb_build_object('action', 'unchanged', 'so_number', v_so.so_number, 'line', to_jsonb(v_line), 'removed_line_id', null, 'bin_id', v_b.id, 'bin', v_b.name,
                              'price', v_line.unit_price, 'bin_qty', v_bal, 'total', public.so_line_total(v_line), 'warnings', '[]'::jsonb);
  end if;
  select * into v_other from public.so_line l where l.so_id = v_so.id and l.id <> v_line.id and l.bgrade_bin_id = v_b.id and l.product_id = v_p.id order by l.line_no limit 1 for update;
  v_merge := found;                                                                       -- perform 이 FOUND 를 덮기 전에 담는다
  perform set_config('ims.bgrade_line', 'on', true);
  if v_merge then
    update public.so_line set qty_ordered = qty_ordered + v_line.qty_ordered, updated_by = v_staff where id = v_other.id returning * into v_out;
    delete from public.so_line where id = v_line.id;
    v_action := 'merged';
  else
    update public.so_line set bgrade_bin_id = v_b.id, unit_price = v_price, discount_pct = null, discount_source = null, deal_line_id = null, free_reason = null,
                              price_override = true, price_set_by = v_staff, price_set_at = now(), updated_by = v_staff
     where id = v_line.id returning * into v_out;
    v_action := 'set';
  end if;
  perform set_config('ims.bgrade_line', '', true);
  return jsonb_build_object('action', v_action, 'so_number', v_so.so_number, 'line', to_jsonb(v_out), 'removed_line_id', case when v_action = 'merged' then v_line.id end,
                            'bin_id', v_b.id, 'bin', v_b.name, 'price', v_price, 'bin_qty', v_bal, 'total', public.so_line_total(v_out),
                            'warnings', case when v_out.qty_ordered > v_bal then '["over_bgrade_stock"]'::jsonb else '[]'::jsonb end);
end $$;
revoke all on function public.so_line_bgrade_set(uuid, uuid) from public, anon, service_role;
grant execute on function public.so_line_bgrade_set(uuid, uuid) to authenticated;
comment on function public.so_line_bgrade_set(uuid, uuid) is 'bgr-1c 판정 634 ② · 635 · 642 · 644 — POS 줄을 B급 줄로(sales 문 · pos draft) · 값 = 그 칸 B급 값(잔고 > 0 인 살아 있는 값만) · 칸 생략 시 후보 하나면 그 칸 · 여럿이면 action choose + candidates(저장 없음) · 같은 칸 · SKU 의 B급 줄이 있으면 합침(action merged · removed_line_id) · warnings over_bgrade_stock(647 — 화면이 확인)';

create function public.so_line_bgrade_clear(p_line_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
-- bgr-1c: B급 줄을 정상 줄로 되돌린다(sales 문 · draft) — 칸 · price_override 를 비우고 시스템 값으로 다시 견적
declare v_staff uuid;  v_line public.so_line%rowtype;  v_so public.so%rowtype;  v_out public.so_line%rowtype;
begin
  perform public.ims_require_write('sales', 'saved');
  v_staff := public.so_current_staff();
  select * into v_line from public.so_line where id = p_line_id for update;
  if not found then raise exception 'Order line not found — nothing was saved'; end if;
  v_so := public.so_require_draft(v_line.so_id, 'saved');
  if v_line.bgrade_bin_id is null then raise exception 'Line % is not a B-grade line — nothing was saved', v_line.line_no; end if;
  perform set_config('ims.bgrade_line', 'on', true);
  update public.so_line set bgrade_bin_id = null, price_override = false, price_set_by = null, price_set_at = null, updated_by = v_staff where id = v_line.id;
  perform set_config('ims.bgrade_line', '', true);
  v_out := public.so_line_requote(v_line.id, v_line.qty_ordered, true);
  return jsonb_build_object('action', 'cleared', 'so_number', v_so.so_number, 'line', to_jsonb(v_out), 'total', public.so_line_total(v_out), 'warnings', '[]'::jsonb);
end $$;
revoke all on function public.so_line_bgrade_clear(uuid) from public, anon, service_role;
grant execute on function public.so_line_bgrade_clear(uuid) to authenticated;
comment on function public.so_line_bgrade_clear(uuid) is 'bgr-1c — B급 줄을 정상 줄로 되돌리기(sales 문 · draft) · 칸 · 덮어쓰기 표시를 비우고 시스템 값으로 다시 견적';

-- ═══ so_line_add 재발행 — 원본 DB 바이트(md5 f505807836e5974d58702202a21d2d89) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1c」) · 서명 · 권한 · comment 그대로(create or replace) ═══
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
      and l.bgrade_bin_id is null                                                                                                                           -- bgr-1c 판정 635: B급 줄은 값이 같아도 합치지 않는다
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
      into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = p.id and l.combo_line_id is null and l.bgrade_bin_id is null;                                      -- asm-2a: 구성품 줄은 「같은 SKU」가 아니다
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

-- ═══ so_lines_paste 재발행 — 원본 DB 바이트(md5 ec25aaeb81f71aee706d8abbd1e55b5b) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1c」) · 서명 · 권한 · comment 그대로(create or replace) ═══
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
        and l.bgrade_bin_id is null                                                                                                                         -- bgr-1c 판정 635: B급 줄에 붙여 넣지 않는다
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
        select count(*) into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null and l.bgrade_bin_id is null;
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
        and l.bgrade_bin_id is null                                                                                                                         -- bgr-1c
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
        select count(*) into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null and l.bgrade_bin_id is null;                 -- asm-2a: 구성품 줄은 「같은 SKU」가 아니다
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

-- ═══ so_detail 재발행 — 원본 DB 바이트(md5 ee65f2b2ced0927afabfec6e3421e36f) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1c」) · 서명 · 권한 · comment 그대로(create or replace) ═══
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

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('manual', public.so_line_manual(l), 'price_set_by_name', (select s.name from public.ims_staff s where s.id = l.price_set_by), 'total', public.so_line_total(l),   -- ln-1 판정 546(price_set_by · price_set_at 은 to_jsonb(l) 에) 'no_price', l.unit_price is null, 'free', l.free_reason is not null, 'shipped_total', round(l.qty_shipped * l.unit_price, 2), 'removed', l.qty_removed > 0,
                                                              'surcharge_unit', public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), 'surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_ordered), 'shipped_surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_shipped),   -- surcharge-2a(묶음 1 · 2 · total · shipped_total 과 같은 수량)
                                                              'qty_credited', (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_line_id = l.id and c.status = 'issued'),   -- ⓒ2
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date),
                                                              'is_combo', exists (select 1 from public.so_line c where c.combo_line_id = l.id),                                                           -- asm-2a(묶음 2 · 5): 콤보 줄 · 구성품 줄(combo_line_id · combo_qty 는 to_jsonb(l) 에 있다)
                                                              'bgrade_bin', (select rb.name from public.ref_bin rb where rb.id = l.bgrade_bin_id), 'is_bgrade_line', l.bgrade_bin_id is not null,   -- bgr-1c 판정 634 · 635: POS · so 화면의 B-grade 표시
                                                              'combo_sku', (select c.sku from public.so_line c where c.id = l.combo_line_id)) order by l.line_no), '[]'::jsonb),
         count(*) filter (where l.combo_line_id is null), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), public.so_lines_total(p_so_id),   -- dsc-3a 판정 310: 기준 금액 식 한 곳
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)),
         count(*) filter (where l.qty_removed > 0), coalesce(sum(l.qty_removed), 0)
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended, v_removed, v_qty_removed
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('discount', public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount), 'net', c.amount - public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount)) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)   -- fr-1: 할인액 · 순 운임(식 한 곳)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

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

-- ═══ inv_ledger_bgrade_guard 재발행 — 원본 DB 바이트(md5 fa02c2f0b3c7f6a295134f6e0cc13bdd) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1c」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.inv_ledger_bgrade_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- bgr-1b 판정 635 · 638 · 639: IMS 사건(source ims)이 B급 칸을 건드리면 셋만 통과 — 조정(adjust_existing · adjust_new) · 판매 출고(sale_out 음수 · POS 1c) · 표지 켠 칸 옮기기(bin_move · B급 셸)
--   Cin7 적재(source cin7 · manual)는 보지 않는다 · 조정이 잔고 0 이하에서 B급 칸에 넣으면 그 칸 · SKU 의 옛 B급 값을 지운다(판정 644 — 「값 없음」으로 들어온다)
declare v_bin uuid;
        v_lbin uuid;                                                                                -- bgr-1c: 판매 출고 줄의 B급 칸(정상 줄이면 null)
begin
  if new.source is distinct from 'ims' then return new; end if;                                       -- bgr-1c: 칸 없는 판매 출고도 아래 B급 줄 검사를 거친다(옛 줄은 칸 '' 도 여기서 돌려보냈다)
  if new.event_type = 'sale_out' and new.raw ? 'so_line_id' then
    select l.bgrade_bin_id into v_lbin from public.so_line l where l.id = (new.raw->>'so_line_id')::uuid;   -- bgr-1c 판정 635 · 647
  end if;
  if coalesce(new.bin, '') = '' and v_lbin is null then return new; end if;                          -- bgr-1c
  select rb.id into v_bin from public.ref_bin rb join public.ref_warehouse w on w.id = rb.warehouse_id where w.name = new.warehouse and rb.name = new.bin and rb.is_bgrade;
  if v_lbin is not null and v_bin is distinct from v_lbin then                                       -- bgr-1c: B급 줄은 그 B급 칸에서만 나간다(정상 칸 · 다른 B급 칸 · 칸 없음 거부)
    raise exception using errcode = 'IM637', message = format('B-grade line (%s %s) ships only from its B-grade bin %s, not from %s — nothing was saved',
      new.sku, new.qty_delta, (select rb.name from public.ref_bin rb where rb.id = v_lbin), coalesce(nullif(new.bin, ''), '(no bin)'));
  end if;
  if v_bin is null then return new; end if;
  if new.event_type in ('adjust_existing', 'adjust_new') then
    if new.qty_delta > 0 and public.inv_adjust_ledger(new.warehouse, new.bin, new.sku) <= 0 then
      delete from public.bgrade_price bp using public.product p where bp.bin_id = v_bin and bp.product_id = p.id and p.sku = new.sku;
    end if;
    return new;
  end if;
  if new.event_type = 'sale_out' and new.qty_delta < 0 and v_lbin = v_bin then return new; end if;   -- bgr-1c 판정 635: B급 칸의 판매 출고는 그 칸의 B급 줄만(1b 는 어떤 판매든)
  if new.raw->>'kind' = 'bin_move' and coalesce(current_setting('ims.bgrade_move', true), '') = 'on' then return new; end if;
  raise exception using errcode = 'IM637', message = format('Bin %s in %s is a B-grade bin — stock goes in or out of it only with Move to B-grade / Move back, a stock adjustment or a POS sale (%s %s %s) — nothing was saved',
    new.bin, new.warehouse, new.event_type, new.sku, new.qty_delta);
end $function$;

-- ═══ so_lines_available — 반환 칸 둘이 늘어 drop + create(원본 DB 바이트 md5 c661d318… + 더한 줄 · 바꾼 줄 · 권한 · comment 다시) · 부르는 곳 = pos.html · so.html(칸 이름으로 읽는다) · DB 함수 0 ═══
drop function public.so_lines_available(uuid);
CREATE FUNCTION public.so_lines_available(p_so_id uuid)
 RETURNS TABLE(line_id uuid, line_no integer, sku text, is_combo boolean, combo_line_id uuid, stock_pid uuid, qty_ordered numeric, pack_factor numeric, available_ea numeric, available_units numeric, bgrade_bin_id uuid, bgrade_bin text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with so as (select s.location_id from public.so s where s.id = p_so_id),
  ln as (
    select l.id, l.line_no, l.sku, l.combo_line_id, l.qty_ordered, l.pack_factor, l.combo_qty, coalesce(p.parent_product_id, p.id) as stock_pid,
           l.bgrade_bin_id,                                                                         -- bgr-1c
           exists (select 1 from public.so_line k where k.combo_line_id = l.id) as is_combo
      from public.so_line l join public.product p on p.id = l.product_id where l.so_id = p_so_id),
  av as (select m.stock_pid, greatest(m.available_ea, 0) as available_ea from so, lateral public.so_available_many((select array_agg(distinct x.stock_pid) from ln x where not x.is_combo), so.location_id) m),
  bg as (                                                                                 -- bgr-1c 판정 647: B급 줄 = 그 칸 그 SKU 장부 − 그 칸을 가리키는 열린 B급 줄 할당(정상 줄 식처럼 이 오더 할당도 뺀다 · 음수 그대로 · 막지 않는다)
    select x.id as line_id, rb.name as bin,
           public.inv_adjust_ledger(w.name, rb.name, sp.sku)
           - coalesce((select sum(r.qty_allocated * l2.pack_factor) from public.so_reserve r join public.so_line l2 on l2.id = r.so_line_id
                        where r.released_at is null and r.kind = 'allocated' and l2.bgrade_bin_id = x.bgrade_bin_id and l2.product_id = x.stock_pid), 0) as available_ea
      from ln x join public.ref_bin rb on rb.id = x.bgrade_bin_id join public.ref_warehouse w on w.id = rb.warehouse_id join public.product sp on sp.id = x.stock_pid),
  combo as (
    select k.combo_line_id as line_id, min(floor(coalesce(a.available_ea, 0) / need.need_ea)) as units
      from (select x.combo_line_id, x.stock_pid, sum(x.combo_qty * x.pack_factor) as need_ea from ln x where x.combo_line_id is not null group by 1, 2) need
      join ln k on k.combo_line_id = need.combo_line_id and k.stock_pid = need.stock_pid
      left join av a on a.stock_pid = need.stock_pid
     group by 1)
  select x.id, x.line_no, x.sku, x.is_combo, x.combo_line_id,
         case when x.is_combo then null else x.stock_pid end,
         x.qty_ordered, x.pack_factor,
         case when x.is_combo then null when x.bgrade_bin_id is not null then g.available_ea else coalesce(a.available_ea, 0) end,                                       -- bgr-1c: B급 줄은 그 칸
         case when x.is_combo then coalesce(c.units, 0) when x.bgrade_bin_id is not null then floor(g.available_ea / x.pack_factor) else floor(coalesce(a.available_ea, 0) / x.pack_factor) end,   -- bgr-1c
         x.bgrade_bin_id, g.bin                                                                    -- bgr-1c: 새 반환 칸 둘
    from ln x left join av a on a.stock_pid = x.stock_pid left join combo c on c.line_id = x.id
    left join bg g on g.line_id = x.id                                                        -- bgr-1c
   order by x.line_no;
$function$;
revoke all on function public.so_lines_available(uuid) from public, anon;
grant execute on function public.so_lines_available(uuid) to authenticated, service_role;
comment on function public.so_lines_available(uuid) is 'asm-2a(판정 244): per-line availability of one order at its warehouse — ordinary and component lines: so_available_many for the stock key ÷ pack_factor · combo line: min over its components of floor(available ÷ units one combo needs) · a static picture (lines are not netted against each other — so_allocate_run does that at confirm) · bgr-1c 판정 647: B급 줄(bgrade_bin_id)은 그 칸 그 SKU 장부 − 그 칸을 가리키는 열린 B급 줄 할당(음수 그대로) · 반환 끝 칸 bgrade_bin_id · bgrade_bin';
-- ═══ 착지 ═══
do $$
declare v_bad text := '';
begin
  if (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('so_line_bgrade_set', 'so_line_bgrade_clear', 'so_line_bgrade_guard', 'so_bgrade_header_guard', 'so_lines_available'))
     <> 'so_bgrade_header_guard={postgres=X/postgres} so_line_bgrade_clear={postgres=X/postgres,authenticated=X/postgres} so_line_bgrade_guard={postgres=X/postgres} so_line_bgrade_set={postgres=X/postgres,authenticated=X/postgres} so_lines_available={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
     then v_bad := v_bad || ' fn_acl'; end if;
  if (select count(*) from pg_trigger where not tgisinternal and tgenabled = 'O' and tgname in ('so_line_bgrade_guard', 'so_bgrade_header_guard', 'inv_ledger_bgrade_guard')) <> 3 then v_bad := v_bad || ' triggers'; end if;
  if (select pg_get_function_result(oid) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_available') not like '%bgrade_bin_id uuid, bgrade_bin text)' then v_bad := v_bad || ' sla_result'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('so_line_add', 'so_lines_paste', 'so_detail', 'so_lines_available', 'inv_ledger_bgrade_guard'))
     <> 'inv_ledger_bgrade_guard=d7c0960a1f5cccee8a0b4fd4ad3fa39d so_detail=9f4e87f639bcef66b663a3cd78906247 so_line_add=b24f9d83035d6aa3e68119be4904cb17 so_lines_available=5fae508a5cf2c51dd15ad11f1056a537 so_lines_paste=ed9f56386f3eab17b0a05ecf2b6ab93a'
     then v_bad := v_bad || ' reissue_bodies'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('so_line_update', 'so_pos_confirm', 'so_pos_complete', 'so_allocate_all', 'so_pick_plan', 'inv_post_sale', 'so_reprice', 'so_split', 'so_merge'))
     <> 'inv_post_sale=ff5e3006ffb81a9bbcf46e07a84b1ffb so_allocate_all=c3298ba7a9b1c06da0fc917b0c1b6533 so_line_update=d0e0f54f79b5c55334e5ea0f5f4b83b2 so_merge=fbbd2a426bb55f8a871ba7bdd5a8aa10 so_pick_plan=bdde73f22c0e0af219e88c0b9f53e331 so_pos_complete=0b4e2e4b81ca44d7174dab51e2097cde so_pos_confirm=2a20a8abad4d4a5dcb509d64a15b77b4 so_reprice=7683d1724e01027ec4e6178828abbcad so_split=a8214b121c70c054943b318bec00c847'
     then v_bad := v_bad || ' untouched_changed'; end if;
  if v_bad <> '' then raise exception 'bgr-1c landing check failed:%', v_bad; end if;
end $$;
