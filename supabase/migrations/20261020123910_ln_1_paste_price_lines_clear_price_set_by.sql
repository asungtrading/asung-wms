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

-- ═══ ln-1 — 붙여넣기 가격 · Lines 전부 지우기 · 「누가 단가를 정했나」 (2026-10-20 · 판정 532 · 541 ~ 546 · so-module §13 판정 2 · §47 ~ §48 판정 281 · 292) ═══
--   C 먼저(so_line.price_set_by · price_set_at · so_line_add · so_line_update · so_detail · so_split · so_merge) → A(so_lines_paste 재발행 · 가격 칸) → B(so_lines_clear 새로)
--   재발행 = 마지막 정의 바이트 + 더한 줄(diff 가 뜻한 줄뿐) · so_line_requote · so_reprice(손 줄은 kept · ord-1a2:361) · so_line_remove · so_combo_children_insert(값 0 · 두 칸 null) 무접촉
--   판정 546: 사람이 단가 또는 할인 % 를 줄 때만 찍는다(so_line_add · so_line_update · 붙여넣기 가격 줄 = so_line_add) · ↺ 로 시스템 줄로 돌아가면 비운다 · 수량 · surcharge · comments 만 바꾸면 그대로
--   Shopify 줄은 시스템 직원이 찍힌 채 둔다(shop_order_process → so_line_add(단가) · 「누가」 = 시스템 · 출처 shopify) · 이미 있는 손 줄은 백필하지 않는다(누가 정했는지 모른다)

-- ═══ C-1 칸 둘 · 짝 CHECK · FK ═══
alter table public.so_line
  add column price_set_by uuid references public.ims_staff(id),
  add column price_set_at timestamptz,
  add constraint so_line_price_set_pair_ck check ((price_set_by is null) = (price_set_at is null));
comment on column public.so_line.price_set_by is 'ln-1 판정 546 — 이 줄의 단가 또는 할인 % 를 손으로 정한 직원(so_line_add · so_line_update · 붙여넣기 가격) · 시스템 줄 · 구성품 줄은 null · 다시 견적(↺)이면 비움 · updated_by 는 ims_touch 가 덮어 이 뜻으로 못 쓴다';
comment on column public.so_line.price_set_at is 'ln-1 판정 546 — price_set_by 와 짝(둘 다 null 또는 둘 다 값 · so_line_price_set_pair_ck)';

-- ═══ C-2 so_line_add 재발행 — 원본 20261006183851_dsc_1_sellable.sql:83 바이트 + insert 두 칸(v_manual 일 때 v_staff · now()) ═══
create or replace function public.so_line_add(
  p_so_id        uuid,
  p_product_id   uuid,
  p_qty          numeric,
  p_unit_price   numeric default null,      -- 주면 덮어쓰기(price_override) · 0 = 무상(free_reason 필수)
  p_discount_pct numeric default null,      -- 주면 손님 기본·딜 대신 이 할인(source manual · unit_price 와 함께 못 준다)
  p_free_reason  text    default null,
  p_comments     text    default null,
  p_force_new    boolean default false      -- ask 의 답 「따로 줄로」
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
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
$$;
comment on function public.so_line_add(uuid, uuid, numeric, numeric, numeric, text, text, boolean) is
  '⭐ SO 초안 줄 하나(①b · 할인 규칙 ②-0b · dsc-1 · ln-1 재발행 · 판정 2·4·281·292·546) — definer · 첫 줄 ims_require_write(sales) · 초안만 · 비활성 제품 거부. 가격 = so_line_quote · p_unit_price 는 덮어쓰기(price_override) · p_discount_pct 는 source manual · 사람이 단가 또는 할인을 주면 price_set_by · price_set_at 을 찍는다(ln-1 판정 546 · 합쳐지는 줄은 그대로) · 같은 SKU 는 판정 2(① 시스템 줄 합치기 · ② 단가 같으면 합침 · 다르면 ask · p_force_new) · 안 파는 세트는 낱개로(281 · 292 · 293) · 콤보면 구성품 줄까지';

-- ═══ C-3 so_line_update 재발행 — 원본 20261011003000_ord_1a2_shop_order_process.sql:196 바이트 + 선언 둘 · 갈래마다 찍기/비우기 · update 두 칸 ═══
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
  v_pset_by uuid;  v_pset_at timestamptz;                       -- ln-1 판정 546: 누가 · 언제 단가 · 할인을 정했나(사람이 주면 찍고 · ↺ 면 비우고 · 그 밖은 그대로)
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
    v_pset_by := v_staff;  v_pset_at := now();                   -- ln-1 판정 546
  elsif p_patch ? 'discount_pct' then
    v_disc := nullif(p_patch->>'discount_pct', '')::numeric;
    if v_disc is not null then                                   -- 수동 할인
      if v_disc < 0 or v_disc > 100 then
        raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
      end if;
      v_dsrc := 'manual';  v_deal := null;
      v_pset_by := v_staff;  v_pset_at := now();                 -- ln-1 판정 546
    else                                                         -- 비우면 시스템으로(할인 식 한 곳 · 딜 포함 · 이견 3)
      select * into q from public.so_line_quote(v_so, v_line.product_id, v_qty);
      v_disc := q.discount_pct;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
      v_pset_by := null;  v_pset_at := null;                     -- ln-1 판정 546: ↺ — 시스템 줄로 돌아간다
    end if;
    v_unit := case when v_line.list_price is null then null else v_line.list_price * (1 - v_disc / 100) end;
    v_override := false;
  elsif v_qty is distinct from v_line.qty_ordered and not v_line.price_override and v_line.discount_source is distinct from 'manual' and v_line.discount_source is distinct from 'shopify' then   -- ord-1a2 판정 433: shopify 줄은 수량이 바뀌어도 할인 그대로
    select * into q from public.so_line_quote(v_so, v_line.product_id, v_qty);      -- 시스템 줄 · 수량이 바뀌었다 → 할인 다시(list 는 그대로)
    v_disc := q.discount_pct;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    v_unit := case when v_line.list_price is null then null else v_line.list_price * (1 - v_disc / 100) end;
    v_override := false;
    v_pset_by := null;  v_pset_at := null;                       -- ln-1: 시스템 줄의 다시 견적(이미 null)
  else
    v_unit := v_line.unit_price;  v_disc := v_line.discount_pct;  v_override := v_line.price_override;  v_dsrc := v_line.discount_source;  v_deal := v_line.deal_line_id;
    v_pset_by := v_line.price_set_by;  v_pset_at := v_line.price_set_at;   -- ln-1: 수량 · surcharge · comments 만 — 그대로
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
    price_set_by     = v_pset_by,                               -- ln-1 판정 546
    price_set_at     = v_pset_at,
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
comment on function public.so_line_update(uuid, jsonb) is
  '⭐ SO 초안 줄 고치기(①b · ②-0b · 세금 ② · surcharge-2a · asm-2a · ord-1a2 · ln-1 재발행 · 판정 3 · 433 · 546) — definer · 첫 줄 ims_require_write(sales) · 초안만 · 열쇠 여덟(qty_ordered · unit_price · discount_pct · free_reason · surcharge_pct · surcharge_amount · surcharge_label · comments). unit_price → 덮어쓰기 + price_set_by/at · discount_pct 값 → manual + price_set_by/at · discount_pct 빈 값 → 다시 견적(↺ · 두 칸 비움) · 수량만 바뀐 시스템 줄은 다시 견적 · shopify 줄은 수량만 · 구성품 줄은 따로 못 고친다';

-- ═══ C-4 so_detail 재발행 — 원본 20261020010711_od_1_manual_lines_order_discount_name_lock.sql:159 바이트 + 줄에 price_set_by_name ═══
create or replace function public.so_detail(p_so_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
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
$$;
comment on function public.so_detail(uuid) is
  'SO 읽기 창구 하나(①b · … · od-1 · ln-1 재발행) — invoker · stable · 줄에 manual(so_line_manual) · price_set_by · price_set_at · price_set_by_name(ln-1 판정 546) · totals(discount_basis_amount · order_discount_amount 는 so_tax_preview 한 곳) · 세금 · 인보이스 · 잔액 · 쿠폰 · 경고';

-- ═══ C-5 so_split 재발행 — 원본 20261006201443_dsc_3a_order_discount.sql:955 바이트 + 일부 분할 insert 두 칸 복사(통째 이동은 update set so_id 라 따라간다) ═══
create or replace function public.so_split(p_so_id uuid, p_reason text, p_moves jsonb, p_target_status text, p_staff uuid) returns public.so
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so     public.so%rowtype;
  v_new    public.so%rowtype;
  v_base   text;
  v_max    text;
  v_num    text;
  v_id     uuid := gen_random_uuid();
  m        record;
  l        public.so_line%rowtype;
  v_next   int := 0;
  v_n      int;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if p_reason not in ('stock_short','warehouse','preorder','manual','pick_short') then                       -- ③a′ 2026-09-24: pick_short(출하 차이 · so_ship) — CHECK so_split_reason_ck 와 같은 다섯
    raise exception 'split_reason % is not one of stock_short, warehouse, preorder, manual, pick_short — nothing was saved', p_reason;
  end if;
  if p_target_status not in ('draft','confirmed') then
    raise exception 'A split order can only be born draft or confirmed — nothing was saved';
  end if;
  if coalesce(jsonb_array_length(p_moves), 0) = 0 then
    raise exception 'Nothing to split off — nothing was saved';
  end if;

  -- 번호 — base(접미어를 뗀 것)로 잠그고 그 base 의 접미어 최댓값 다음 글자 하나(5-d · PO 20260924001820:278~370 과 같은 자리 · cancelled·merged 도 센다 — 글자는 다시 쓰지 않는다)
  v_base := regexp_replace(v_so.so_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('so:' || v_base));
  select max(substring(s.so_number from length(v_base) + 1)) into v_max
  from public.so s where s.so_number ~ ('^' || v_base || '[a-z]$');
  if v_max is null then
    v_num := v_base || 'a';
  elsif v_max >= 'x' then
    raise exception 'Order % has been split too many times (last suffix %) — split it by hand — nothing was saved', v_so.so_number, v_max;
  else
    v_num := v_base || chr(ascii(v_max) + 1);
  end if;

  -- 머리 통째 복사(칸이 늘어도 따라온다) — draft 로 태어난다(문지기 · 이견 4) · 닫힘·창고·출하·되돌리기 흔적은 비운다 · 확정 흔적은 target 이 confirmed 일 때 아래 update 에서 물려받는다
  update public.so set order_discount_locked_at = coalesce(order_discount_locked_at, now()) where id = p_so_id;   -- dsc-3a 판정 312: 모체부터 잠근다(아래 줄 옮기기가 so_line 트리거를 깨운다)
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_so) || jsonb_build_object(
      'id', v_id, 'so_number', v_num, 'status', 'draft', 'order_discount_locked_at', coalesce(v_so.order_discount_locked_at, now()),
      'split_from_id', v_so.id, 'split_reason', p_reason,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null,
      'created_at', now(), 'created_by', p_staff, 'updated_at', now(), 'updated_by', p_staff));

  -- 줄 옮기기(모체 line_no 순 · 형제 line_no 1부터)
  for m in
    select (e->>'line_id')::uuid as line_id, (e->>'qty')::numeric as qty
    from jsonb_array_elements(p_moves) e
    join public.so_line x on x.id = (e->>'line_id')::uuid
    order by x.line_no
  loop
    select * into l from public.so_line where id = m.line_id and so_id = p_so_id;
    if not found then raise exception 'Line % is not on order % — nothing was saved', m.line_id, v_so.so_number; end if;
    if m.qty is null or m.qty <= 0 then raise exception 'Split quantity for line % must be positive — nothing was saved', l.line_no; end if;
    v_next := v_next + 1;
    if m.qty >= l.qty_ordered then
      update public.so_line set so_id = v_id, line_no = v_next, updated_by = p_staff where id = l.id;                       -- 통째 — 행이 간다(id 그대로)
    else
      update public.so_line set qty_ordered = qty_ordered - m.qty, updated_by = p_staff where id = l.id;                    -- 일부 — 원래 줄을 줄이고
      insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, qty_shipped,
                                  list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                  surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, split_from_line_id, updated_by, combo_line_id, combo_qty, price_set_by, price_set_at)
      values (v_id, v_next, l.product_id, l.sku, l.product_name, l.unit, l.pack_factor, m.qty, 0,
              l.list_price, l.discount_pct, l.unit_price, l.price_override, l.discount_source, l.deal_line_id, l.free_reason,
              l.surcharge_pct, l.surcharge_amount, l.surcharge_label, l.tax_rule, l.comments, l.id, p_staff, l.combo_line_id, l.combo_qty, l.price_set_by, l.price_set_at);   -- 형제에 새 줄 · 계보 · asm-2a: 콤보 매듭 두 칸도 · ln-1: 누가 정했나 두 칸도
    end if;
  end loop;
  -- asm-2a(판정 244 · 묶음 4): 일부만 간 콤보의 구성품 줄은 형제에 새로 선 콤보 줄에 다시 매단다(통째로 간 줄은 id 그대로라 매듭도 그대로) · 매듭 검사는 deferred 트리거라 문장 끝에 본다
  update public.so_line c set combo_line_id = n.id
    from public.so_line n
   where c.so_id = v_id and c.combo_line_id is not null and n.so_id = v_id and n.combo_line_id is null and n.split_from_line_id = c.combo_line_id;

  if p_target_status = 'confirmed' then
    update public.so set status = 'confirmed', confirmed_at = v_so.confirmed_at, confirmed_by = v_so.confirmed_by, updated_by = p_staff
    where id = v_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Split order % was not saved — nothing was saved', v_num; end if;
  end if;

  select * into v_new from public.so where id = v_id;
  return v_new;
end;
$$;

-- ═══ C-6 so_merge 재발행 — 원본 20261015013503_bo_1d_merge_blocks_backorder.sql:36 바이트 + 계획에 두 칸(같은 묶음의 첫 원본 가운데 값이 있는 것) · 줄 insert 두 칸 ═══
create or replace function public.so_merge(p_so_ids uuid[], p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_head_fields constant text[] := array['ship_to_company','ship_to_contact','ship_to_phone','ship_to_line1','ship_to_line2','ship_to_city','ship_to_state_province','ship_to_postal_code','ship_to_country',
                                         'bill_to_customer_id','bill_to_name','bill_to_line1','bill_to_line2','bill_to_city','bill_to_state_province','bill_to_postal_code','bill_to_country',
                                         'payment_term_id','payment_term_name','price_tier','price_tier_id','tax_rule','tax_rule_id','tax_rule_manual','discount_pct',
                                         'order_discount_pct','order_discount_source','order_discount_deal_id','required_by','ref','comments','intake',
                                         'carrier','tracking_number','shipping_notes','ar_account_code','sale_account_code'];
  v_staff   uuid;
  v_ids     uuid[];
  v_n       int;
  v_today   date := public.ims_today();
  v_old     public.so%rowtype;                       -- 가장 오래된 원본 = 머리(⬜2)
  v_head    public.so%rowtype;                       -- 미리 보기용 가상 머리(order_date = 오늘)
  v_new     public.so%rowtype;
  v_cust    public.customer%rowtype;
  v_numbers text;
  v_any_confirmed boolean;
  v_diffs   jsonb; v_plan jsonb; v_calc_in jsonb; v_hint jsonb; v_pay jsonb; v_sib jsonb; v_sup jsonb; v_charges jsonb;
  v_warn    text[] := '{}';
  v_note    text;
  v_id      uuid;
  v_line_id uuid;
  v_cnt     int;
  v_bo      int := 0; v_reopened int := 0; v_released int := 0; v_moved int := 0; v_lines_n int := 0;
  v_combos  jsonb := '[]'::jsonb;  v_comp_n int := 0;                 -- asm-2b2(묶음 2 · 3): 콤보 줄끼리 합친다(열쇠 + 구성품 모양) · 합친 콤보 줄 아래 구성품을 다시 매단다(합친 콤보 수 × combo_qty · 저장된 combo_qty 로 · 정의가 바뀐 콤보는 열쇠가 갈라 따로 둔다)
  r record;
  e jsonb;
  v_cps jsonb := '[]'::jsonb;  v_best_cp uuid;  v_best_pct numeric := -1;  v_cp_pct numeric;   -- dsc-3b 판정 324 — 원본 쿠폰 가운데 큰 쪽
  od record;
  v_bo_msg  text;                                    -- bo-1d 판정 484: 열린 백오더 오더 거부 문장
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — sales 묶음
  v_staff := public.so_current_staff();

  -- ── 대상 검사 ──
  select array_agg(distinct x) into v_ids from unnest(p_so_ids) x where x is not null;
  if coalesce(array_length(p_so_ids, 1), 0) <> coalesce(array_length(v_ids, 1), 0) then raise exception 'The same order is listed twice — nothing was saved'; end if;
  if coalesce(array_length(v_ids, 1), 0) < 2 then raise exception 'A merge needs at least two orders — nothing was saved'; end if;
  perform 1 from public.so s where s.id = any(v_ids) order by s.id for update;
  get diagnostics v_n = row_count;
  if v_n <> array_length(v_ids, 1) then raise exception 'Order not found — nothing was saved'; end if;
  for r in select s.* from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number loop
    if r.status not in ('draft', 'confirmed') then
      raise exception 'Order % is % — only draft or confirmed orders still in IMS can be merged — nothing was saved', r.so_number,
        r.status || case when r.status = 'cancelled' and r.closed_reason = 'merged' then ' (already merged into ' || coalesce((select m.so_number from public.so m where m.id = r.merged_into_id), '?') || ')'
                         when r.status in ('at_wms', 'picking', 'packed') then ' (it is with the warehouse — merge is only possible before release)'
                         else '' end;
    end if;
    if r.channel <> 'warehouse' then raise exception 'Order % is a % order — only warehouse orders can be merged — nothing was saved', r.so_number, r.channel; end if;
  end loop;
  if (select count(distinct s.customer_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders belong to different customers — nothing was saved'; end if;
  if (select count(distinct coalesce(s.location_id::text, '(none)')) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are for different warehouses — change the warehouse first — nothing was saved'; end if;
  if (select count(distinct s.currency_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are in different currencies — nothing was saved'; end if;
  -- bo-1d 판정 484: 열린 백오더 예약이 있는 오더는 합치지 않는다(합치면 같은 제품 줄 수량이 더해져 확정 때의 이어받기를 건너뛴다 · 백오더의 길은 진행 · 이어받기 · 만료 · 취소) · 콤보 줄이면 구성품 줄의 예약(was_backorder 와 같은 모양) · 미리 보기도 같은 거부 · 프리오더 · 보류 · 할당은 막지 않는다
  select format('Order %s has open backorder lines (%s) — a backorder is not merged: proceed it when stock arrives, or confirm the new order so it takes the backorder over — nothing was saved',
                b.so_number, b.skus || case when b.n > 5 then ' and ' || (b.n - 5)::text || ' more' else '' end)
    into v_bo_msg
  from (select s.so_number, s.order_date, count(*) as n, string_agg(d.sku, ', ' order by d.line_no) filter (where d.rn <= 5) as skus
        from public.so s
        join (select l.so_id, l.line_no, l.sku, row_number() over (partition by l.so_id order by l.line_no) as rn
              from public.so_line l
              where l.combo_line_id is null
                and exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id
                            where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'backorder')) d on d.so_id = s.id
        where s.id = any(v_ids)
        group by s.id, s.so_number, s.order_date
        order by s.order_date, s.so_number limit 1) b;
  if v_bo_msg is not null then raise exception '%', v_bo_msg; end if;
  select c.* into v_cust from public.customer c where c.id = (select s.customer_id from public.so s where s.id = v_ids[1]);
  if not v_cust.is_active then raise exception 'Customer % is inactive — nothing was saved', v_cust.name; end if;
  v_any_confirmed := exists (select 1 from public.so s where s.id = any(v_ids) and s.status = 'confirmed');
  if v_any_confirmed then perform public.so_require_role('manager', 'saved'); end if;   -- 판정 5 · R5: 확정 오더의 재고를 푸는 순간 선을 넘는다

  select s.* into v_old from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number limit 1;
  select string_agg(s.so_number, ', ' order by s.order_date, s.so_number) into v_numbers from public.so s where s.id = any(v_ids);

  -- ── 머리 차이(판정 2·7 · 막지 않는다) ──
  select coalesce(jsonb_agg(jsonb_build_object('field', d.f, 'values', d.vals) order by d.f), '[]'::jsonb) into v_diffs
  from (select f, jsonb_agg(jsonb_build_object('so_number', s.so_number, 'value', to_jsonb(s)->f) order by s.order_date, s.so_number) as vals
        from public.so s cross join unnest(c_head_fields) f
        where s.id = any(v_ids)
        group by f having count(distinct coalesce(to_jsonb(s)->f, 'null'::jsonb)) > 1) d;

  -- ── 줄 계획(판정 4 · 고침 ①: 열쇠 = 제품 · 단가 · 정가 · 할인 % · 무상 사유 · override · 부가 셋 — tax_rule 은 열쇠 밖 · 전부 합친 오더 규칙) ──
  with src as (
    select l.*, s.so_number, dense_rank() over (order by s.order_date, s.so_number) as ord,
           exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'preorder')  as was_preorder,    -- asm-2b2: 콤보 줄의 예약은 구성품에
           exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'backorder') as was_backorder,
           (l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, v_today)) as deal_ended,
           (select string_agg(cp.sku || ':' || trim_scale(cp.combo_qty)::text, ',' order by cp.sku) from public.so_line cp where cp.combo_line_id = l.id) as combo_sig   -- asm-2b2: 콤보 줄의 구성품 모양(열쇠에 든다 · 보통 줄은 null)
    from public.so_line l join public.so s on s.id = l.so_id
    where s.id = any(v_ids) and l.combo_line_id is null                                                                                  -- asm-2b2: 구성품 줄은 계획에 들지 않는다(콤보 줄을 따라 다시 선다)
  ), grp as (
    select product_id, unit_price, list_price, discount_pct, free_reason, price_override, surcharge_pct, surcharge_amount, surcharge_label, combo_sig,
           min(ord * 100000 + line_no) as first_pos, sum(qty_ordered) as qty, count(*) as n, (array_agg(id order by ord, line_no))[1] as first_line_id,
           (array_agg(sku order by ord, line_no))[1] as sku, (array_agg(product_name order by ord, line_no))[1] as product_name,
           (array_agg(unit order by ord, line_no))[1] as unit, (array_agg(pack_factor order by ord, line_no))[1] as pack_factor,
           (array_agg(comments order by ord, line_no) filter (where comments is not null))[1] as comments,
           (array_agg(price_set_by order by ord, line_no) filter (where price_set_by is not null))[1] as price_set_by,   -- ln-1 판정 546: 첫 원본의 setter(값이 있는 것 가운데 첫째)
           (array_agg(price_set_at order by ord, line_no) filter (where price_set_by is not null))[1] as price_set_at,
           bool_or(was_preorder) as was_preorder, bool_or(was_backorder) as was_backorder, bool_or(deal_ended) as deal_ended,
           jsonb_agg(jsonb_build_object('so_number', so_number, 'line_no', line_no, 'line_id', id, 'qty', qty_ordered, 'discount_source', discount_source, 'deal_line_id', deal_line_id,
                                        'was_preorder', was_preorder, 'was_backorder', was_backorder) order by ord, line_no) as sources
    from src
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
  ), numbered as (
    select g.*, row_number() over (order by g.first_pos) as line_no,
           count(*) over (partition by g.product_id) as n_same_product,
           first_value(g.unit_price)     over (partition by g.product_id order by g.first_pos) as p_unit_price,
           first_value(g.list_price)     over (partition by g.product_id order by g.first_pos) as p_list_price,
           first_value(g.discount_pct)   over (partition by g.product_id order by g.first_pos) as p_discount_pct,
           first_value(g.free_reason)    over (partition by g.product_id order by g.first_pos) as p_free_reason,
           first_value(g.price_override) over (partition by g.product_id order by g.first_pos) as p_override,
           first_value(g.surcharge_label) over (partition by g.product_id order by g.first_pos) as p_surcharge_label,
           first_value(g.combo_sig)      over (partition by g.product_id order by g.first_pos) as p_combo_sig
    from grp g
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'line_no', x.line_no, 'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'unit', x.unit, 'pack_factor', x.pack_factor,
           'qty', x.qty, 'list_price', x.list_price, 'discount_pct', x.discount_pct, 'unit_price', x.unit_price, 'price_override', x.price_override, 'free_reason', x.free_reason,
           'discount_source', case when x.price_override then null when x.discount_pct is not null then 'manual' else null end,
           'surcharge_pct', x.surcharge_pct, 'surcharge_amount', x.surcharge_amount, 'surcharge_label', x.surcharge_label, 'comments', x.comments,
           'price_set_by', x.price_set_by, 'price_set_at', x.price_set_at,                                                                                      -- ln-1
           'source_lines', x.n, 'sources', x.sources, 'was_preorder', x.was_preorder, 'was_backorder', x.was_backorder, 'deal_ended', x.deal_ended,
           'is_combo', x.combo_sig is not null, 'combo_sig', x.combo_sig, 'first_line_id', x.first_line_id,                                              -- asm-2b2
           'kept_apart', (x.n_same_product > 1),
           'differs_in', case when x.n_same_product > 1 then
              (select coalesce(jsonb_agg(k), '[]'::jsonb) from unnest(array[
                 case when x.unit_price is distinct from x.p_unit_price then 'unit_price' end,
                 case when x.list_price is distinct from x.p_list_price then 'list_price' end,
                 case when x.discount_pct is distinct from x.p_discount_pct then 'discount_pct' end,
                 case when x.free_reason is distinct from x.p_free_reason then 'free_reason' end,
                 case when x.price_override is distinct from x.p_override then 'price_override' end,
                 case when x.surcharge_label is distinct from x.p_surcharge_label then 'surcharge' end,
                 case when x.combo_sig is distinct from x.p_combo_sig then 'combo_definition' end]) k where k is not null)
              else '[]'::jsonb end) order by x.line_no), '[]'::jsonb)
    into v_plan
  from numbered x;
  v_lines_n := coalesce(jsonb_array_length(v_plan), 0);

  -- ── 판정 4 보완 ①: 가상 머리(가장 오래된 원본 + 오늘) 로 다시 견적 ──
  v_head := v_old;
  v_head.order_date := v_today;
  select coalesce(jsonb_agg(jsonb_build_object('line_no', p->'line_no', 'product_id', p->'product_id', 'sku', p->'sku', 'qty', p->'qty', 'unit_price', p->'unit_price', 'discount_pct', p->'discount_pct',
                                               'discount_source', p->'discount_source', 'free_reason', p->'free_reason', 'price_override', p->'price_override')), '[]'::jsonb)
    into v_calc_in from jsonb_array_elements(v_plan) p;
  v_hint := public.so_merge_requote_calc(v_head, v_calc_in);

  -- ── 선결제 대상(옮긴다 · 조사 ③ unique (payment_id, so_id)) ──
  select coalesce(jsonb_agg(jsonb_build_object('payment_id', x.id, 'amount', x.amount, 'method', x.method, 'paid_on', x.paid_on, 'targets', x.targets) order by x.paid_on, x.id), '[]'::jsonb) into v_pay
  from (select p.id, p.amount, p.method, p.paid_on, jsonb_agg(s.so_number order by s.so_number) as targets
        from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active' join public.so s on s.id = o.so_id
        where o.so_id = any(v_ids) group by p.id, p.amount, p.method, p.paid_on) x;

  -- ── 판정 1 로 이어받기에서 빠질 형제(원본의 split 자손 중 열린 백오더가 있는 confirmed 오더) ──
  with recursive d as (
    select s.id, 0 as depth, array[s.id] as path from public.so s where s.id = any(v_ids)
    union all
    select c.id, d.depth + 1, d.path || c.id from d join public.so c on c.split_from_id = d.id where d.depth < 50 and not (c.id = any(d.path))
  )
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'status', s.status, 'split_reason', s.split_reason,
           'open_backorder_lines', (select count(*) from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null)) order by s.so_number), '[]'::jsonb)
    into v_sib
  from d join public.so s on s.id = d.id
  where d.depth > 0 and not (s.id = any(v_ids)) and s.status = 'confirmed'
    and exists (select 1 from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null);

  -- ── 원본이 확정 때 이어받은 남의 백오더 줄(⬜4 · 0-7: confirmed 이고 열린 예약이 없는 줄만 다시 연다 · 나머지는 닫힌 채 + 경고) ──
  select coalesce(jsonb_agg(jsonb_build_object('close_id', c.id, 'so_number', s.so_number, 'line_no', l.line_no, 'sku', l.sku, 'qty_open', c.qty_open, 'qty_taken', c.qty_taken, 'qty_unwanted', c.qty_unwanted,
           'taken_by', t.so_number, 'target_status', s.status,
           'reopenable', (s.status = 'confirmed' and not exists (select 1 from public.so_reserve rs where rs.so_line_id = l.id and rs.released_at is null))) order by s.so_number, l.line_no), '[]'::jsonb)
    into v_sup
  from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.so s on s.id = l.so_id join public.so t on t.id = c.taken_by_so_id
  where c.taken_by_so_id = any(v_ids) and c.reopened_at is null and c.end_kind = 'superseded';

  -- ── 운임(판정 8: 옮기지 않는다 · 다시 계산한다) ──
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'line_no', c.line_no, 'name', c.name, 'amount', c.amount) order by s.so_number, c.line_no), '[]'::jsonb) into v_charges
  from public.so_charge c join public.so s on s.id = c.so_id where c.so_id = any(v_ids);

  -- ── 경고(막지 않는다) ──
  if jsonb_array_length(v_diffs) > 0 then v_warn := array_append(v_warn, 'head_differs'); end if;
  if jsonb_array_length(v_charges) > 0 then v_warn := array_append(v_warn, 'charges_not_merged'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'was_preorder')::boolean) then v_warn := array_append(v_warn, 'preorder_lines_need_reflag'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'deal_ended')::boolean) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if exists (select 1 from jsonb_array_elements(v_sup) x where not (x->>'reopenable')::boolean) then v_warn := array_append(v_warn, 'superseded_not_reopenable'); end if;
  if v_old.order_date <> v_today and v_lines_n > 0 then v_warn := array_append(v_warn, 'reprice_suggested'); end if;   -- §13 판정 3: 주문일이 바뀌면 줄은 그대로 + 표시 + 경고
  if jsonb_array_length(v_sib) > 0 then v_warn := array_append(v_warn, 'backorder_siblings_stay_open'); end if;      -- 판정 1 · 0-1 대가

  if not p_commit then
    return jsonb_build_object('committed', false, 'orders', to_jsonb(string_to_array(v_numbers, ', ')), 'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today,
                              'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'charges', v_charges,
                              'needs_manager', v_any_confirmed, 'warnings', to_jsonb(v_warn));
  end if;

  -- ── 실행 ① 새 오더(머리 통째 복사 · 위 주석의 칸 표) ──
  v_id := gen_random_uuid();
  v_note := 'Merged from ' || v_numbers;
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_old) || jsonb_build_object(
      'id', v_id, 'so_number', public.so_next_number(), 'status', 'draft', 'order_date', v_today, 'ref', null,
      'comments', case when v_old.comments is null then v_note else v_old.comments || E'\n' || v_note end,
      'split_from_id', null, 'split_reason', null,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null, 'carrier', null, 'carrier_id', null, 'tracking_number', null,   -- ful-1c: carrier_id 도 비운다(합친 뒤 Ship & invoice 에서 고른다)
      'reprice_suggested_at', null, 'order_discount_locked_at', null,
      'created_at', now(), 'created_by', v_staff, 'updated_at', now(), 'updated_by', v_staff));
  select * into v_new from public.so where id = v_id;
  perform public.so_order_discount_apply(v_id, v_staff);                             -- 판정 7 · dsc-3a 판정 308 · 312: 새 머리는 잠기지 않는다 · manual 은 helper 가 그대로 · 줄이 들어오며 so_line 트리거가 금액 단계로 다시 고른다

  -- ── 실행 ② 줄(계획 그대로 · tax_rule = 합친 오더 규칙 · 짝 표) ──
  for e in select p from jsonb_array_elements(v_plan) p order by (p->>'line_no')::int loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by, price_set_by, price_set_at)
    values (v_id, (e->>'line_no')::int, (e->>'product_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
            (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, (e->>'unit_price')::numeric, (e->>'price_override')::boolean, e->>'discount_source', null, e->>'free_reason',
            (e->>'surcharge_pct')::numeric, (e->>'surcharge_amount')::numeric, e->>'surcharge_label', v_new.tax_rule, e->>'comments', v_staff, (e->>'price_set_by')::uuid, (e->>'price_set_at')::timestamptz)   -- ln-1
    returning id into v_line_id;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select v_line_id, (x->>'line_id')::uuid, v_staff from jsonb_array_elements(e->'sources') x;
    if (e->>'is_combo')::boolean then v_combos := v_combos || jsonb_build_object('line_id', v_line_id, 'first_line_id', e->'first_line_id', 'qty', e->'qty', 'sources', e->'sources'); end if;
  end loop;
  -- asm-2b2(묶음 2): 합친 콤보 줄마다 구성품을 다시 매단다 — 첫 원본 콤보 줄의 구성품(저장된 combo_qty · 정의를 다시 읽지 않는다) · 수량 = 합친 콤보 수 × combo_qty · 값 0 · 줄 번호는 끝에(so_line_add 와 같은 자리) · 짝 표에 원본 구성품 줄도
  for e in select p from jsonb_array_elements(v_combos) p loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by, combo_line_id, combo_qty)
    select v_id, (select coalesce(max(n.line_no), 0) from public.so_line n where n.so_id = v_id) + row_number() over (order by cp.line_no), cp.product_id, cp.sku, cp.product_name, cp.unit, cp.pack_factor, (e->>'qty')::numeric * cp.combo_qty,
           null, null, 0, false, null, null, null, null, null, null, v_new.tax_rule, null, v_staff, (e->>'line_id')::uuid, cp.combo_qty
    from public.so_line cp where cp.combo_line_id = (e->>'first_line_id')::uuid;
    get diagnostics v_cnt = row_count;  v_comp_n := v_comp_n + v_cnt;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select n.id, sc.id, v_staff
    from public.so_line n join jsonb_array_elements(e->'sources') sx on true join public.so_line sc on sc.combo_line_id = (sx->>'line_id')::uuid and sc.product_id = n.product_id
    where n.so_id = v_id and n.combo_line_id = (e->>'line_id')::uuid;
  end loop;
  if v_old.order_date <> v_today and v_lines_n > 0 then
    update public.so set reprice_suggested_at = now(), updated_by = v_staff where id = v_id;
  end if;
  -- dsc-3b 판정 324: 원본들의 쿠폰 가운데 helper 로 골라 본 % 가 큰 쪽만 새 머리에(같으면 오래된 원본 것) · 나머지는 뗀 채 남는다(원본은 merged 라 가족 판정에 안 걸린다)
  for r in select s.coupon_id, s.so_number, s.created_at from public.so s where s.id = any(v_ids) and s.coupon_id is not null order by s.created_at, s.so_number loop
    update public.so set coupon_id = r.coupon_id where id = v_id;
    perform public.so_order_discount_apply(v_id, v_staff, true);
    select case when s.order_discount_source = 'coupon' then s.order_discount_pct else -1 end into v_cp_pct from public.so s where s.id = v_id;
    v_cps := v_cps || jsonb_build_object('so_number', r.so_number, 'code', (select c.code from public.so_coupon c where c.id = r.coupon_id),
                                         'pct', (select public.so_coupon_pct(c, s) from public.so_coupon c, public.so s where c.id = r.coupon_id and s.id = v_id), 'won_pct', nullif(v_cp_pct, -1));
    if v_cp_pct > v_best_pct then v_best_pct := v_cp_pct; v_best_cp := r.coupon_id; end if;
  end loop;
  if v_cps <> '[]'::jsonb then
    update public.so set coupon_id = case when v_best_pct > -1 then v_best_cp else null end where id = v_id;
    perform public.so_order_discount_apply(v_id, v_staff, true);
    select coalesce(jsonb_agg(c || jsonb_build_object('kept', (select s.coupon_id from public.so s where s.id = v_id) = (select x.id from public.so_coupon x where x.code = c->>'code'))), '[]'::jsonb) into v_cps from jsonb_array_elements(v_cps) c;
  end if;

  -- ── 실행 ③ 원본의 열린 백오더 줄 → 장부 merged + 예약 closed(0-4) · asm-2b2: 수요 줄 단위(콤보 줄은 구성품 예약을 콤보 수로 · 장부는 콤보 줄에 · 구성품 예약 함께 닫힘) ──
  for r in
    select x.id as so_line_id, q.qty_open, q.ids as reserve_ids
    from public.so_line x
    cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, array_agg(res.id) as ids
                        from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                        where (cp.id = x.id or cp.combo_line_id = x.id) and res.released_at is null and res.kind = 'backorder') q
    where x.so_id = any(v_ids) and x.combo_line_id is null and q.qty_open is not null
  loop
    perform public.so_backorder_record(r.so_line_id, 'merged', r.qty_open, 0, 0, null, null, v_staff, 'Merged into ' || v_new.so_number);
    update public.so_reserve set released_at = now(), released_by = v_staff, released_reason = 'closed', updated_by = v_staff where id = any(r.reserve_ids);
    v_bo := v_bo + 1;
  end loop;

  -- ── 실행 ④ 원본이 이어받은 남의 줄 다시 열기(⬜4 · confirmed 이고 열린 예약 없는 줄만 · so_backorder_reopen 과 같은 모양) ──
  for r in select (x->>'close_id')::uuid as close_id, (x->>'reopenable')::boolean as ok from jsonb_array_elements(v_sup) x loop
    if r.ok then
      update public.so_backorder_close set reopened_at = now(), reopened_by = v_staff, updated_by = v_staff where id = r.close_id and reopened_at is null;
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
      select c.so_line_id, c.qty_open, 'backorder', null from public.so_backorder_close c where c.id = r.close_id;
      v_reopened := v_reopened + 1;
    end if;
  end loop;

  -- ── 실행 ⑤ 원본의 남은 열린 예약(allocated · preorder · hold) 풀기 → released(트리거가 reason 을 넣는다 · ⬜5) ──
  update public.so_reserve res set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x where x.id = res.so_line_id and res.released_at is null and x.so_id = any(v_ids);
  get diagnostics v_released = row_count;

  -- ── 실행 ⑥ 원본 닫기(한 문장 · so_merge_reason_ck 양방향 · so_closed_at_ck) ──
  update public.so set status = 'cancelled', closed_reason = 'merged', merged_into_id = v_id, closed_at = now(), closed_note = 'Merged into ' || v_new.so_number, cancelled_by = v_staff, updated_by = v_staff
  where id = any(v_ids) and status in ('draft', 'confirmed');
  get diagnostics v_cnt = row_count;
  if v_cnt <> array_length(v_ids, 1) then
    raise exception 'Not every order could be merged — one may have been changed by someone else just now — nothing was saved';
  end if;

  -- ── 실행 ⑦ 선결제 대상 옮기기(원본 행은 기록으로 · 합친 오더 행 하나) ──
  insert into public.so_payment_order (payment_id, so_id, created_by)
  select distinct o.payment_id, v_id, v_staff
  from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active'
  where o.so_id = any(v_ids)
  on conflict on constraint so_payment_order_uq do nothing;
  get diagnostics v_moved = row_count;

  return jsonb_build_object('committed', true, 'so_id', v_id, 'so_number', v_new.so_number, 'status', 'draft', 'orders', to_jsonb(string_to_array(v_numbers, ', ')),
                            'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today, 'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint,
                            'payments_moved', v_moved, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'superseded_reopened', v_reopened,
                            'backorder_lines_recorded', v_bo, 'reserves_released', v_released, 'charges', v_charges, 'component_lines', v_comp_n, 'coupons', v_cps, 'warnings', to_jsonb(v_warn));   -- asm-2b2: 다시 매단 구성품 줄 수
end;
$$;

-- ═══ A so_lines_paste 재발행 — 원본 20261006183851_dsc_1_sellable.sql:252 바이트 + 가격 칸(판정 532 · 545) ═══
--   [{sku, qty, price?}] — price 가 없거나 빈 글자 = 지금 그대로(가격 없는 묶음 무변 · 티어 · 손님 할인 · 딜) · 있으면 숫자만(소수 자리 한도 없음 — so_line_add 와 같다)
--   거부(줄 단위 · 저장 안 함 · 붙여넣기 전체가 서지 않는다): bad_price(숫자 아님 · 음수) · free_price(0 — 무상 줄은 사유가 필요해 Add line 으로) · set_price_refused(안 파는 세트 + 가격 · 판정 292)
--   1단계 묶기 열쇠 = (제품, 가격) · 같은 제품을 다른 가격으로 두 번 붙이면 둘째 묶음부터 ask(미리 보기 = 저장)
--   2단계 가격 묶음: 시스템 줄 합치기(①)를 건너뛴다 · 사람이 정한 줄(price_override 또는 manual) 가운데 같은 단가 → merged(수량만) · 같은 제품의 다른 줄이 하나라도(시스템 줄도 — 판정 532 · 같은 가격이어도) → ask · 없으면 새 줄
--   새 줄 = so_line_add(p_unit_price, p_force_new := true) 를 그대로(값 · surcharge · 콤보 구성품 · price_set_by 한 곳) · 반환 줄의 price_source = 'paste'
create or replace function public.so_lines_paste(
  p_so_id  uuid,
  p_lines  jsonb,                          -- [{sku, qty, price?}] — ln-1: price 는 선택(판정 532 · 545)
  p_commit boolean default false
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
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
$$;
comment on function public.so_lines_paste(uuid, jsonb, boolean) is
  '⭐ SO 초안 붙여넣기(①b · ②-0b · dsc-1 · ln-1 재발행 · 판정 2 · 281 · 293 · 532 · 545) — definer · 첫 줄 ims_require_write(sales) · 초안만 · [{sku, qty, price?}] · 500줄 한도. SKU 는 앞뒤 공백만 다듬고 정확 일치 → upper 폴백. 판정어: ok · no_price · merged · ask · duplicate · not_found · inactive · bad_qty · not_sellable · bad_price(숫자 아님 · 음수) · free_price(0) · set_price_refused(안 파는 세트 + 가격) · 꼬리표 converted. 가격 없는 줄 = 전과 같다(티어 · 손님 할인 · 딜 · 시스템 줄 합치기 ①) · 가격 있는 줄 = 최종(오더 할인 안 받음 · 문턱 합계에는 든다) · 묶기 열쇠 (제품, 가격) · 같은 제품 다른 가격은 둘째부터 ask · 사람이 정한 같은 단가 줄에만 합친다 · 같은 제품의 다른 줄이 있으면 ask · 새 줄은 so_line_add(p_unit_price · p_force_new) · 반환 price_source paste · summary 에 bad_price · free_price · set_price_refused · priced';

-- ═══ B so_lines_clear — 새로(판정 533 → 541: draft 만 · 확정 오더는 Unconfirm 뒤에) ═══
--   intake shopify 거부(상대 시스템이 정한 줄 — 되살릴 길이 없다) · pos draft 는 받는다(POS 화면에는 단추를 안 둔다) · 열린 예약이 있으면 거부(so_line_remove 와 같다 · draft 는 보통 없다)
--   한 트랜잭션 · 오더 행 for update · 구성품 줄 먼저 → 줄 전부 · so_charge · coupon_id 는 남긴다(줄이 다시 오면 쿠폰 딜을 다시 고른다) · 지운 뒤 so_order_discount_apply(판정 308 — 행 트리거도 돌지만 updated_by 에 사람을 남긴다)
--   같은 순간 남이 넣는 줄(so_line_add 는 오더 행을 잠그지 않는다)은 살아남는다 — 받아들인다(clear 뒤에 넣은 줄이 맞는 결과)
create function public.so_lines_clear(p_so_id uuid, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_so      public.so%rowtype;
  v_lines   int;  v_combo int;  v_comp int;  v_charges int;  v_coupon boolean;
  v_n       int := 0;  v_k int := 0;
begin
  perform public.ims_require_write('sales', 'deleted');        -- ⭐ 첫 줄
  v_staff := public.so_current_staff();

  select * into v_so from public.so where id = p_so_id for update;                                                -- 오더 행 잠금(so_require_draft 는 stable · 잠그지 않는다)
  if not found then
    raise exception 'Order not found — nothing was deleted';
  end if;
  if v_so.status <> 'draft' then                                                                                   -- 판정 541
    raise exception 'Order % is not a draft (status %) — unconfirm it first (a supervisor can), then clear the lines — nothing was deleted', v_so.so_number, v_so.status;
  end if;
  if v_so.intake = 'shopify' then
    raise exception 'Order % came from Shopify — its lines cannot be cleared all at once (remove lines one by one, or cancel the order) — nothing was deleted', v_so.so_number;
  end if;
  if exists (select 1 from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = p_so_id and r.released_at is null) then
    raise exception 'Order % has an open allocation — release it first — nothing was deleted', v_so.so_number;
  end if;

  select count(*) filter (where combo_line_id is null), count(*) filter (where combo_line_id is null and exists (select 1 from public.so_line c where c.combo_line_id = l.id)), count(*) filter (where combo_line_id is not null)
    into v_lines, v_combo, v_comp
  from public.so_line l where l.so_id = p_so_id;
  select count(*) into v_charges from public.so_charge c where c.so_id = p_so_id;
  v_coupon := v_so.coupon_id is not null;

  if not p_commit then
    return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'committed', false,
                              'lines', v_lines, 'combo_lines', v_combo, 'component_lines', v_comp, 'charges_left', v_charges, 'coupon_left', v_coupon);
  end if;

  delete from public.so_line where so_id = p_so_id and combo_line_id is not null;                                   -- 구성품 줄 먼저(so_line_remove 와 같은 순서 · FK 도 cascade 지만 수를 센다)
  get diagnostics v_k = row_count;
  delete from public.so_line where so_id = p_so_id;
  get diagnostics v_n = row_count;
  if v_n <> v_lines or v_k <> v_comp then
    raise exception 'Order % lines changed while clearing (expected % + % · deleted % + %) — nothing was deleted', v_so.so_number, v_lines, v_comp, v_n, v_k;
  end if;
  v_so := public.so_order_discount_apply(p_so_id, v_staff);                                                        -- 판정 308: order_discount_* 는 그 한 곳만 쓴다(줄이 0 → 문턱 밖 · 쿠폰 id 는 남는다)

  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'committed', true,
                            'lines', v_n, 'combo_lines', v_combo, 'component_lines', v_k, 'charges_left', v_charges, 'coupon_left', v_so.coupon_id is not null,
                            'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'source', v_so.order_discount_source, 'deal_id', v_so.order_discount_deal_id));
end;
$$;
revoke all on function public.so_lines_clear(uuid, boolean) from public, anon;
grant execute on function public.so_lines_clear(uuid, boolean) to authenticated, service_role;
comment on function public.so_lines_clear(uuid, boolean) is
  'ln-1 판정 541 — SO 초안의 줄 전부 지우기(definer · 첫 줄 ims_require_write(sales) · draft 만 · intake shopify 거부 · 열린 예약 거부 · 오더 행 for update) · 구성품 줄 먼저 · so_charge · coupon_id 는 남긴다 · 지운 뒤 so_order_discount_apply · p_commit false = 미리 보기(lines · combo_lines · component_lines · charges_left · coupon_left) · true = 지우고 같은 꼴 + order_discount';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_line' and column_name in ('price_set_by', 'price_set_at')) <> 2 then v_bad := v_bad || ' columns'; end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.so_line'::regclass and conname = 'so_line_price_set_pair_ck') then v_bad := v_bad || ' pair-ck'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_line_add(uuid, uuid, numeric, numeric, numeric, text, text, boolean)'::regprocedure) !~ 'case when v_manual then v_staff end' then v_bad := v_bad || ' so_line_add'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_line_update(uuid, jsonb)'::regprocedure) !~ 'price_set_by     = v_pset_by' then v_bad := v_bad || ' so_line_update'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_detail(uuid)'::regprocedure) !~ 'price_set_by_name' then v_bad := v_bad || ' so_detail'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_split(uuid, text, jsonb, text, uuid)'::regprocedure) !~ 'l\.price_set_by, l\.price_set_at' then v_bad := v_bad || ' so_split'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_merge(uuid[], boolean)'::regprocedure) !~ '\(e->>''price_set_by''\)::uuid' then v_bad := v_bad || ' so_merge'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_lines_paste(uuid, jsonb, boolean)'::regprocedure) !~ 'set_price_refused' then v_bad := v_bad || ' so_lines_paste'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_reprice(uuid)'::regprocedure) !~ 'if l\.price_override or l\.discount_source in \(''manual'', ''shopify''\) then' then v_bad := v_bad || ' so_reprice-kept'; end if;   -- 이견 16: 손 줄 kept 줄이 마지막 정의에 있다(무접촉 전제)
  if to_regprocedure('public.so_lines_clear(uuid, boolean)') is null or not has_function_privilege('authenticated', 'public.so_lines_clear(uuid, boolean)', 'execute') or has_function_privilege('anon', 'public.so_lines_clear(uuid, boolean)', 'execute') then v_bad := v_bad || ' so_lines_clear'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_line'::regclass and tgname in ('so_line_order_discount_repick_id', 'so_line_order_discount_repick_u')) <> 2 then v_bad := v_bad || ' repick-triggers'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - ln-1 did not land as designed:%s - nothing was changed', v_bad); end if;
end $$;
