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

-- ─────────────────────────────────────────────────────────────
-- 콤보를 오더에 — 콤보 줄 + 구성품 줄 · 고치기 · 지우기 · 상세 · 가용 · 확정 예약 (Asung-IMS · asm-2a · 2026-10-05)
--   정본(뒤에 적는다): so-module §44 — 판정 244(콤보는 팔 때 구성품을 바로 뺀다 · 조립 문서 없음) · asm 묶음 2(콤보 줄 하나 + 구성품 줄 여럿 · 값은 콤보 줄 · 재고 · 예약 · 픽 · 출고 · 원가는 구성품 줄) · 3(수량 · 삭제는 콤보 줄만 · 구성품 줄은 따라간다)
--                      · 4(구성품 하나가 모자라면 콤보 전체를 하나로 — 콤보 2 출고 · 1 백오더 · 반쪽 콤보 없음) · 5(손님 문서에는 콤보 줄만 — asm-2b) · 판정 229(같은 SKU 합치기 — 구성품 줄과는 합치지 않는다) · 판정 228(무상 줄과 가르기)
--   앞 차수 asm-1(20261005192944 · product_bom_set · 콤보 정의) — 이 파일은 2a(줄 저장 · 고치기 · 지우기 · 상세 · 가용 · 확정 예약) · 2b(픽 · 출고 · Finalize · 백오더 · 인보이스 · POS 완료 · 크레딧 · wms_pick_lines)는 다음
--   든 것:
--     1) so_line 칸 둘 — combo_line_id(구성품 줄 → 콤보 줄 · on delete cascade) · combo_qty(콤보 하나에 드는 이 구성품 수 · 정의가 바뀌어도 열린 오더는 저장된 값 그대로)
--        CHECK — so_line_free_pair_ck 를 다시(구성품 줄은 값 0 이지만 무상 줄이 아니다 · 판정 228) · combo_self · combo_pair · combo_qty · combo_values(구성품 줄 = 값 0 · 할인 · 딜 · surcharge · 덮어쓰기 없음)
--        매듭 검사(부모가 같은 오더 · 부모는 콤보 줄)는 CHECK 로 못 쓴다(다른 행) ⇒ DEFERRABLE INITIALLY DEFERRED 제약 트리거 — so_split 이 형제에 줄을 옮기는 사이의 모양을 허락하고 문장 끝에 본다
--     2) 도우미 — so_combo_is(상품이 콤보인가) · so_combo_children_insert(콤보 줄 밑에 구성품 줄) · so_combo_children_sync(콤보 수량 → 구성품 수량) · so_combo_children_json(반환용) · 읽기 창구 so_lines_available(오더 줄마다 가용 · 콤보 줄 = min(floor(구성품 가용 ÷ 콤보 하나의 낱개)))
--     3) 재발행 여덟(마지막 정의 · DB prosrc md5 와 바이트 일치 확인 뒤 복사 · 바뀐 줄만 · 보고에 diff `<` 원문) —
--        so_line_add(20261002155201 · f8b5a083…) · so_lines_paste(20261002155201 · 8d8b3a58…) · so_line_update(20261002141516 · 2b39127c…) · so_line_remove(20260923191030 · a64a451b…)
--        so_detail(20261002141516 · d15bfde3…) · so_allocate_run(20260925142307 · 24321cf1… 의 so_confirm 이 부른다 · 본문 md5 는 보고) · so_allocate_all(20260925142307) · so_split(20260924143507)
--   ⚠️ 재발행 없음 — so_available_many(그대로 · 재고 키 단위 · 콤보 줄 가용은 새 창구) · so_confirm · so_pos_confirm · so_hold · so_unconfirm(형제 줄을 도로 합칠 때 split_from_line_id 로 — 구성품 줄도 같은 길)
--   ⚠️ 2a 만 적용된 상태: 콤보 오더는 확정 · 예약까지 선다 · WMS 로 보내면 픽 계획(so_pick_plan · wms_order_doc_line)이 콤보 줄을 뽑으려 하고 so_ship 은 콤보 줄에 할당이 없어 거부한다(소리 나게 · 잘못 쓰지는 않는다) — 2b 가 잇는다
--   ⚠️ 부분 유니크 인덱스 없음 · 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 정책 · 권한 무접촉(so_line 은 select 만 · 창구가 쓴다)
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) so_line 칸 둘 · CHECK · 매듭 검사(deferred 제약 트리거) ═══
alter table public.so_line
  add column combo_line_id uuid references public.so_line (id) on delete cascade,
  add column combo_qty     numeric;
create index so_line_combo_line_id_idx on public.so_line (combo_line_id) where combo_line_id is not null;
alter table public.so_line drop constraint so_line_free_pair_ck;
alter table public.so_line
  add constraint so_line_free_pair_ck    check ((free_reason is not null) = (not (unit_price is distinct from 0::numeric) and combo_line_id is null)),   -- 원문 + 구성품 줄 제외(값 0 이지만 무상 줄이 아니다)
  add constraint so_line_combo_self_ck   check (combo_line_id is distinct from id),
  add constraint so_line_combo_pair_ck   check ((combo_line_id is null) = (combo_qty is null)),
  add constraint so_line_combo_qty_ck    check (combo_qty is null or combo_qty > 0),
  add constraint so_line_combo_values_ck check (combo_line_id is null or (unit_price = 0 and list_price is null and free_reason is null and discount_pct is null and discount_source is null and deal_line_id is null
                                                                           and not price_override and surcharge_pct is null and surcharge_amount is null and surcharge_label is null));
comment on column public.so_line.combo_line_id is 'asm-2a(판정 244 · 묶음 2): set on a component line — the combo line it hangs under (same order · that line is a combo line itself) · null on ordinary and combo lines · cascade with the combo line';
comment on column public.so_line.combo_qty     is 'asm-2a: component line only — units of this component per one combo at the time the line was made · qty_ordered = combo qty_ordered × combo_qty · the combo definition may change later, open orders keep this';

create function public.so_line_combo_parent_check() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare v_p public.so_line%rowtype; v_c public.so_line%rowtype;
begin
  -- deferred 라 문장 끝 · 트랜잭션 끝에 돈다 — 그 사이 지워진 줄(콤보 줄을 지우면 cascade)이나 다시 매단 줄의 묵은 사건이 올 수 있다 ⇒ 지금 행을 다시 읽어 판정한다(없으면 볼 것이 없다)
  select * into v_c from public.so_line where id = new.id;
  if not found or v_c.combo_line_id is null then return null; end if;
  select * into v_p from public.so_line where id = v_c.combo_line_id;
  if not found then
    raise exception 'Line % (%) hangs under a combo line that does not exist — nothing was saved', v_c.line_no, v_c.sku;
  end if;
  if v_p.so_id <> v_c.so_id then
    raise exception 'Line % (%) hangs under combo line % of another order — nothing was saved', v_c.line_no, v_c.sku, v_p.line_no;
  end if;
  if v_p.combo_line_id is not null then
    raise exception 'Line % (%) hangs under line %, which is itself a component — a combo cannot contain a combo — nothing was saved', v_c.line_no, v_c.sku, v_p.line_no;
  end if;
  return null;
end;
$$;
create constraint trigger so_line_combo_parent_ck after insert or update of combo_line_id, so_id on public.so_line
  deferrable initially deferred for each row execute function public.so_line_combo_parent_check();
comment on function public.so_line_combo_parent_check() is 'asm-2a: deferred row check — a component line''s combo_line_id points at a combo line of the same order (checked at statement end · so_split moves and re-hangs lines inside one statement)';

-- ═══ 2) 도우미 — 속 함수(authenticated 못 부른다 · definer 창구가 부른다) · 읽기 창구 하나 ═══
create function public.so_combo_is(p_product_id uuid) returns boolean
  language sql stable
  set search_path = public, pg_temp
as $$ select exists (select 1 from public.product_bom b where b.parent_product_id = p_product_id and b.is_active) $$;
revoke all on function public.so_combo_is(uuid) from public, anon;   grant execute on function public.so_combo_is(uuid) to authenticated;
comment on function public.so_combo_is(uuid) is 'asm-2a: is this product a combo (has active product_bom rows) — read helper, screens may call it';

create function public.so_combo_children_insert(p_parent public.so_line, p_staff uuid) returns int
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_n int := 0; v_next int; v_bad text;
begin
  select string_agg(c.sku, ', ' order by c.sku) into v_bad
    from public.product_bom b join public.product c on c.id = b.component_product_id
   where b.parent_product_id = p_parent.product_id and b.is_active and not c.is_active;
  if v_bad is not null then
    raise exception 'Combo % has inactive component(s) (%) — fix the combo first — nothing was saved', p_parent.sku, v_bad;
  end if;
  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_parent.so_id;
  insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                              list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason, tax_rule, comments, updated_by,
                              surcharge_pct, surcharge_amount, surcharge_label, combo_line_id, combo_qty)
  select p_parent.so_id, (v_next + row_number() over (order by c.sku))::int, c.id, c.sku, c.name, coalesce((select u.name from public.ref_unit u where u.id = c.unit_id), c.uom_name), coalesce(c.pack_factor, 1),
         p_parent.qty_ordered * b.quantity,
         null, null, 0, false, null, null, null, p_parent.tax_rule, null, p_staff,
         null, null, null, p_parent.id, b.quantity
    from public.product_bom b join public.product c on c.id = b.component_product_id
   where b.parent_product_id = p_parent.product_id and b.is_active;
  get diagnostics v_n = row_count;
  if v_n < 2 then
    raise exception 'Combo % has fewer than two components (%) — fix the combo first — nothing was saved', p_parent.sku, v_n;
  end if;
  return v_n;
end;
$$;
revoke all on function public.so_combo_children_insert(public.so_line, uuid) from public, anon, authenticated;

create function public.so_combo_children_sync(p_line_id uuid, p_staff uuid) returns int
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_n int := 0;
begin
  update public.so_line c set qty_ordered = p.qty_ordered * c.combo_qty, updated_by = p_staff
    from public.so_line p where p.id = p_line_id and c.combo_line_id = p.id and c.qty_ordered is distinct from p.qty_ordered * c.combo_qty;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.so_combo_children_sync(uuid, uuid) from public, anon, authenticated;

create function public.so_combo_children_json(p_line_id uuid) returns jsonb
  language sql stable
  set search_path = public, pg_temp
as $$ select coalesce((select jsonb_agg(to_jsonb(c) order by c.line_no) from public.so_line c where c.combo_line_id = p_line_id), '[]'::jsonb) $$;
revoke all on function public.so_combo_children_json(uuid) from public, anon, authenticated;

-- 읽기 창구 — 오더 줄마다 가용(화면이 so_available_many 를 재고 키로 부르던 자리 · 콤보 줄은 구성품으로 센다) · invoker(so_available_many 와 같다 · RLS 가 거른다)
create function public.so_lines_available(p_so_id uuid)
  returns table (line_id uuid, line_no int, sku text, is_combo boolean, combo_line_id uuid, stock_pid uuid, qty_ordered numeric, pack_factor numeric, available_ea numeric, available_units numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with so as (select s.location_id from public.so s where s.id = p_so_id),
  ln as (
    select l.id, l.line_no, l.sku, l.combo_line_id, l.qty_ordered, l.pack_factor, l.combo_qty, coalesce(p.parent_product_id, p.id) as stock_pid,
           exists (select 1 from public.so_line k where k.combo_line_id = l.id) as is_combo
      from public.so_line l join public.product p on p.id = l.product_id where l.so_id = p_so_id),
  av as (select m.stock_pid, greatest(m.available_ea, 0) as available_ea from so, lateral public.so_available_many((select array_agg(distinct x.stock_pid) from ln x where not x.is_combo), so.location_id) m),
  combo as (
    select k.combo_line_id as line_id, min(floor(coalesce(a.available_ea, 0) / need.need_ea)) as units
      from (select x.combo_line_id, x.stock_pid, sum(x.combo_qty * x.pack_factor) as need_ea from ln x where x.combo_line_id is not null group by 1, 2) need
      join ln k on k.combo_line_id = need.combo_line_id and k.stock_pid = need.stock_pid
      left join av a on a.stock_pid = need.stock_pid
     group by 1)
  select x.id, x.line_no, x.sku, x.is_combo, x.combo_line_id,
         case when x.is_combo then null else x.stock_pid end,
         x.qty_ordered, x.pack_factor,
         case when x.is_combo then null else coalesce(a.available_ea, 0) end,
         case when x.is_combo then coalesce(c.units, 0) else floor(coalesce(a.available_ea, 0) / x.pack_factor) end
    from ln x left join av a on a.stock_pid = x.stock_pid left join combo c on c.line_id = x.id
   order by x.line_no;
$$;
revoke all on function public.so_lines_available(uuid) from public, anon;   grant execute on function public.so_lines_available(uuid) to authenticated;
comment on function public.so_lines_available(uuid) is 'asm-2a(판정 244): per-line availability of one order at its warehouse — ordinary and component lines: so_available_many for the stock key ÷ pack_factor · combo line: min over its components of floor(available ÷ units one combo needs) · a static picture (lines are not netted against each other — so_allocate_run does that at confirm)';


-- ═══ 3) so_line_add 재발행 — 20261002155201_surcharge_4a.sql 1173~ 바이트 복사 · 구성품 줄 넣기 · 합치기에서 구성품 줄 제외 · 수량 따라가기 · 반환 components ═══
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
                                  'total', public.so_line_total(v_line), 'warnings', to_jsonb(v_warn), 'components', public.so_combo_children_json(v_line.id));
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
                                'total', public.so_line_total(v_line), 'warnings', to_jsonb(v_warn), 'components', public.so_combo_children_json(v_line.id));
    end if;
    select jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'qty_ordered', l.qty_ordered,
                                        'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'price_override', l.price_override) order by l.line_no)
      into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = p.id and l.combo_line_id is null;                                      -- asm-2a: 구성품 줄은 「같은 SKU」가 아니다
    if v_others is not null then
      return jsonb_build_object('action', 'ask', 'so_number', v_so.so_number, 'product_id', p.id, 'sku', p.sku,
        'proposed', jsonb_build_object('qty_ordered', p_qty, 'list_price', v_list, 'discount_pct', v_disc, 'discount_source', v_dsrc, 'unit_price', v_unit, 'price_override', v_override),
        'existing', v_others,
        'message', 'Same SKU is already on this order at a different price — change that line (so_line_update) or add as a new line (p_force_new) — nothing was saved');
    end if;
  end if;

  select coalesce(max(line_no), 0) + 1 into v_next from public.so_line where so_id = p_so_id;
  insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                              list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason, tax_rule, comments, updated_by,
                              surcharge_pct, surcharge_amount, surcharge_label)                                                                                    -- surcharge-4a(묶음 3): 그 상품의 켜진 그룹 값 · 무상이면 비움(판정 228) · 합치기 길은 손대지 않는다(판정 229)
  select p_so_id, v_next, p.id, p.sku, p.name, v_unit_nm, coalesce(p.pack_factor, 1), p_qty,
          v_list, v_disc, v_unit, v_override, v_dsrc, v_deal, v_reason, v_so.tax_rule, v_comments, v_staff,
          d.surcharge_pct, d.surcharge_amount, d.surcharge_label
  from public.so_line_surcharge_defaults(p.id, v_reason is not null) d
  returning * into v_line;
  if v_combo then v_nchild := public.so_combo_children_insert(v_line, v_staff); end if;                                     -- asm-2a(묶음 2): 구성품 줄 = 콤보 수량 × 정의 수량 · 값 0 · 콤보 줄에 매달린다
  if v_unit is null then v_warn := array_append(v_warn, 'no_price'); end if;
  if v_deal is not null and public.so_deal_line_ended(v_deal, public.ims_today()) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;

  return jsonb_build_object('action', 'added', 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                            'total', public.so_line_total(v_line), 'price_source', v_src, 'warnings', to_jsonb(v_warn), 'components', public.so_combo_children_json(v_line.id));
end;
$$;

-- ═══ 4) so_lines_paste 재발행 — 20261002155201_surcharge_4a.sql 바이트 복사 · 같은 자리들 · 미리 보기도 구성품 줄 번호를 센다 ═══
create or replace function public.so_lines_paste(
  p_so_id  uuid,
  p_lines  jsonb,                          -- [{sku, qty}]
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
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  v_n := coalesce(jsonb_array_length(p_lines), 0);
  if v_n > c_limit then
    return jsonb_build_object(
      'so_id', p_so_id, 'so_number', v_so.so_number, 'committed', false,
      'summary', jsonb_build_object('total', v_n, 'ok', 0, 'no_price', 0, 'merged', 0, 'ask', 0, 'duplicate', 0, 'not_found', 0, 'inactive', 0, 'bad_qty', 0,
                                    'inserted', 0, 'updated', 0, 'too_many', true, 'limit', c_limit,
                                    'message', format('Too many lines (%s) — up to %s lines per paste. Nothing was saved.', v_n, c_limit)),
      'lines', '[]'::jsonb);
  end if;

  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_so_id;

  -- 1) 입력 → 제품 · 같은 제품은 첫 줄에 수량을 모은다
  for r in
    select t.ord::int as n, t.e->>'sku' as sku_raw, t.e->>'qty' as qty_raw
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality as t(e, ord)
    order by t.ord
  loop
    v_pid := null; v_psku := null; v_pname := null; v_pactive := null; v_uom := null; v_unit_id := null; v_pack := null;
    v_verdict := null; v_msgs := '{}'; v_dup_of := null; v_idx := null;

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

    if v_verdict is null then
      select s.i into v_idx from generate_subscripts(a_pid, 1) s(i) where a_pid[s.i] = v_pid limit 1;
      if v_idx is not null then
        v_dup_of := a_n[v_idx];
        a_qty[v_idx] := a_qty[v_idx] + v_qty;
        v_verdict := 'duplicate';
        v_msgs := array_append(v_msgs, format('merged_into_paste_line_%s — quantities added', v_dup_of));
      else
        a_pid := array_append(a_pid, v_pid);  a_n := array_append(a_n, r.n);  a_qty := array_append(a_qty, v_qty);
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
      else null;
    end case;

    v_rows := v_rows || jsonb_build_object(
      'n', r.n, 'input_sku', r.sku_raw, 'input_qty', r.qty_raw,
      'verdict', v_verdict,                                      -- null = 2) 에서 정해진다
      'product_id', v_pid, 'sku', v_psku, 'product_name', v_pname, 'product_active', v_pactive,
      'qty', v_qty, 'line_no', null, 'inserted', false, 'updated', false,
      'message', array_to_string(v_msgs, ' · '));
  end loop;

  -- 2) 제품별 — 가격(수량 포함) · 기존 줄과 대조(판정 2) · 넣기(결과는 그 제품의 첫 입력 줄에 적는다)
  for i in 1 .. coalesce(array_length(a_pid, 1), 0) loop
    select * into q from public.so_line_quote(v_so, a_pid[i], a_qty[i]);
    v_list := q.list_price;  v_disc := q.discount_pct;  v_unit := q.unit_price;  v_src := q.price_source;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    v_line_no := null; v_inserted := false; v_updated := false; v_msgs := '{}';
    v_combo := public.so_combo_is(a_pid[i]);
    v_ncomp := case when v_combo then (select count(*) from public.product_bom b where b.parent_product_id = a_pid[i] and b.is_active) else 0 end;

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
                                  'inserted', n_ins, 'updated', n_upd, 'too_many', false, 'limit', c_limit, 'message', null),
    'lines', v_rows);
end;
$$;

-- ═══ 5) so_line_update 재발행 — 20261002141516_surcharge_2a.sql 바이트 복사 · 구성품 줄 직접 고치기 막기 · 콤보 수량 → 구성품 ═══
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
  elsif v_qty is distinct from v_line.qty_ordered and not v_line.price_override and v_line.discount_source is distinct from 'manual' then
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

-- ═══ 6) so_line_remove 재발행 — 20260923191030_so_write_rpc.sql 바이트 복사 · 구성품 줄 직접 지우기 막기 · 콤보 줄 지우면 구성품도 ═══
create or replace function public.so_line_remove(p_line_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_line   public.so_line%rowtype;
  v_so     public.so%rowtype;
  v_n      int;
  v_left   int;
  v_kids   int := 0;                                            -- asm-2a(묶음 3): 콤보 줄을 지우면 구성품 줄도 · 구성품 줄은 따로 못 지운다
begin
  perform public.ims_require_write('sales', 'deleted');        -- ⭐ 첫 줄
  perform public.so_current_staff();

  select * into v_line from public.so_line where id = p_line_id;
  if not found then
    raise exception 'Order line not found — nothing was deleted';
  end if;
  v_so := public.so_require_draft(v_line.so_id, 'deleted');
  if v_line.combo_line_id is not null then
    raise exception 'Line % is a component of combo % (line %) — remove the combo line instead — nothing was deleted', v_line.line_no,
      (select c.sku from public.so_line c where c.id = v_line.combo_line_id), (select c.line_no from public.so_line c where c.id = v_line.combo_line_id);
  end if;
  if exists (select 1 from public.so_reserve r where r.released_at is null and (r.so_line_id = p_line_id or r.so_line_id in (select c.id from public.so_line c where c.combo_line_id = p_line_id))) then
    raise exception 'Line % of % has an open allocation — release it first — nothing was deleted', v_line.line_no, v_so.so_number;
  end if;

  delete from public.so_line where combo_line_id = p_line_id;                                                                 -- asm-2a: 구성품 줄 먼저(FK 도 cascade 지만 수를 센다)
  get diagnostics v_kids = row_count;
  delete from public.so_line where id = p_line_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Line % of % was not deleted — it may have been removed by someone else just now — nothing was deleted', v_line.line_no, v_so.so_number;
  end if;
  select count(*) into v_left from public.so_line where so_id = v_so.id;
  return jsonb_build_object('so_number', v_so.so_number, 'removed_line_no', v_line.line_no, 'lines_left', v_left, 'removed_components', v_kids);
end;
$$;

-- ═══ 7) so_detail 재발행 — 20261002141516_surcharge_2a.sql 바이트 복사 · 줄에 is_combo · combo_sku · totals.lines 는 구성품 줄 제외 · combo_lines · component_lines ═══
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
  v_warn     text[];
  v_tax      jsonb;  v_tw text[];                              -- 세금 ② — so_tax_preview
  v_basis    text;  v_inv jsonb;  v_inv_hist jsonb;  v_removed int;  v_qty_removed numeric;   -- ⓐ2 — 보낸 수량 기준 · 인보이스 · 뺀 몫
  v_bal      jsonb;                                            -- ⓑ2 — 청구처 손님 잔액(그 통화 행)
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('total', public.so_line_total(l), 'no_price', l.unit_price is null, 'free', l.free_reason is not null, 'shipped_total', round(l.qty_shipped * l.unit_price, 2), 'removed', l.qty_removed > 0,
                                                              'surcharge_unit', public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), 'surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_ordered), 'shipped_surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_shipped),   -- surcharge-2a(묶음 1 · 2 · total · shipped_total 과 같은 수량)
                                                              'qty_credited', (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_line_id = l.id and c.status = 'issued'),   -- ⓒ2
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date),
                                                              'is_combo', exists (select 1 from public.so_line c where c.combo_line_id = l.id),                                                           -- asm-2a(묶음 2 · 5): 콤보 줄 · 구성품 줄(combo_line_id · combo_qty 는 to_jsonb(l) 에 있다)
                                                              'combo_sku', (select c.sku from public.so_line c where c.id = l.combo_line_id)) order by l.line_no), '[]'::jsonb),
         count(*) filter (where l.combo_line_id is null), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), coalesce(sum(public.so_line_total(l)), 0),
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)),
         count(*) filter (where l.qty_removed > 0), coalesce(sum(l.qty_removed), 0)
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended, v_removed, v_qty_removed
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

  -- 오더 전체 할인(D6) — 제품 줄 합계에 한 번 · round 2(SO-10842 실물) · 운임은 기준에 없다
  v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;

  -- 세금(세금 ② · 판정 8) — 오더에 고른 규칙(manual|ship_to)으로 줄마다 · 규칙 없으면 tax null + 경고 tax_rule_missing
  v_basis := case when v_so.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;   -- ⓐ2: 나간 뒤에는 보낸 수량이 금액(뺀 몫·pick_short 제외 · 인보이스가 정본 8-c) · ⓑ2: invoiced 값 없음(판정 1)
  v_tax := public.so_tax_preview(p_so_id, null, null, v_basis);
  v_sc_amt := coalesce((v_tax->'totals'->>'surcharge_amount')::numeric, 0);  v_sc_tax := coalesce((v_tax->'totals'->>'surcharge_tax')::numeric, 0);   -- surcharge-2a(묶음 3 · 4)
  if v_basis = 'shipped' then
    v_lines_total := (v_tax->'totals'->>'lines_amount')::numeric;
    v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;
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

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'totals', jsonb_build_object('basis', v_basis, 'lines', v_lines_n, 'combo_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and exists (select 1 from public.so_line c where c.combo_line_id = x.id)),
                                 'component_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and x.combo_line_id is not null), 'lines_removed', v_removed, 'qty_removed', v_qty_removed, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt,
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                        -- surcharge-2a — 물건값 · 오더 할인 기준 밖(묶음 3)
                                 'order_total', v_lines_total - v_od_amt + v_charges_total + v_sc_amt,
                                 'tax_rule', v_so.tax_rule, 'tax_rule_source', v_tax->>'source', 'tax', v_tax->'totals'->'tax',
                                 'order_total_with_tax', case when v_tax->'totals'->>'tax' is null then null else v_lines_total - v_od_amt + v_charges_total + v_sc_amt + (v_tax->'totals'->>'tax')::numeric end),
    'tax', v_tax,
    'invoice', v_inv,
    'invoice_history', v_inv_hist,
    'customer_balance', v_bal,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 8) so_allocate_run 재발행 — 20260925142307_so_pos_a2_flow.sql 바이트 복사 · 콤보는 한 단위로 · 구성품 줄만 예약 · 백오더는 콤보 단위(묶음 4) ═══
create or replace function public.so_allocate_run(p_so_id uuid, p_location_id uuid, p_preorder_line_ids uuid[], p_hold boolean, p_confirm boolean, p_commit boolean, p_staff uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so      public.so%rowtype;
  l         record;
  v_key     text;
  v_rem     numeric;
  v_alloc   numeric;
  v_avail   jsonb := '{}'::jsonb;                    -- 낱개 제품 → 남은 가용(EA) · 이번 실행 안에서만 · 잠금 뒤 so_available_many 한 문장으로 채운다
  v_pids    uuid[] := '{}';                          -- 이 오더의 낱개 제품(잠금 순서대로)
  v_plan    jsonb := '[]'::jsonb;
  a_ids     uuid[] := '{}';  a_qty numeric[] := '{}';       -- A 할당(줄 · 잡는 수량)
  b_moves   jsonb := '[]'::jsonb;  b_n int := 0;             -- B 백오더 [{line_id, qty}]
  p_moves   jsonb := '[]'::jsonb;  p_n int := 0;             -- P 프리오더
  v_keep    text;
  v_sib_b   public.so%rowtype;  v_sib_p public.so%rowtype;
  v_sibs    jsonb := '[]'::jsonb;
  v_n       int;
  i         int;
  -- asm-2a(판정 244 · 묶음 2 · 4): 콤보 줄은 예약하지 않는다 · 구성품 줄이 재고를 잡는다 · 콤보는 한 단위로 — 구성품 하나가 모자라면 콤보 전체를 백오더(반쪽 콤보 없음)
  v_is_combo boolean;  v_cu numeric;  v_cq numeric;  v_pid_need record;  c record;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel <> 'warehouse' then raise exception 'Order % is a % order — pos and counter orders do not use the allocation engine (so_pos_confirm · so_pos_reopen) — nothing was saved', v_so.so_number, v_so.channel; end if;   -- ④a2 이견 0-5
  if p_location_id is null then raise exception 'Order % has no warehouse — set one before confirming — nothing was saved', v_so.so_number; end if;

  -- 잠금 — (창고, 낱개 제품) 오름차순 · 줄마다(5-f) · 두 매니저가 같은 제품을 반대 순서로 잡을 수 없다(⬜4)
  for l in
    select x.id, coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_line x join public.product p on p.id = x.product_id
    where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
      and not exists (select 1 from public.so_line k where k.combo_line_id = x.id)                                             -- asm-2a: 콤보 줄은 재고 키가 아니다
    order by 2, 1
  loop
    perform pg_advisory_xact_lock(hashtext('so_avail:' || p_location_id::text || ':' || l.stock_pid::text));
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || l.id::text));
    v_pids := array_append(v_pids, l.stock_pid);
  end loop;

  -- 가용 — 잠금 뒤 한 번 · 오더의 낱개 제품 전부를 한 문장으로(so_available_many · 뷰를 한 번만 계산한다) · 음수는 0
  if not p_hold and coalesce(array_length(v_pids, 1), 0) > 0 then
    select coalesce(jsonb_object_agg(m.stock_pid::text, greatest(m.available_ea, 0)), '{}'::jsonb) into v_avail
    from public.so_available_many(v_pids, p_location_id) m;
  end if;

  -- 줄마다 판정(모체 line_no 순 — 같은 제품이 두 줄이면 앞 줄이 먼저 잡는다) · asm-2a: 구성품 줄은 콤보 줄에서 함께 판정한다(따로 돌지 않는다)
  if exists (select 1 from unnest(coalesce(p_preorder_line_ids, '{}'::uuid[])) x join public.so_line k on k.id = x where k.combo_line_id is not null) then
    raise exception 'A combo component cannot be a preorder line on its own — choose the combo line — nothing was saved';
  end if;
  for l in
    select x.*, coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_line x join public.product p on p.id = x.product_id
    where x.so_id = p_so_id and x.combo_line_id is null
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
    order by x.line_no
  loop
    v_is_combo := exists (select 1 from public.so_line k where k.combo_line_id = l.id);
    if p_hold then
      v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                             'kind', 'hold', 'allocated', 0, 'backordered', 0, 'preorder', 0, 'combo', v_is_combo);
      if v_is_combo then
        for c in select k.id, k.qty_ordered from public.so_line k where k.combo_line_id = l.id order by k.line_no loop a_ids := array_append(a_ids, c.id);  a_qty := array_append(a_qty, c.qty_ordered); end loop;
      else
        a_ids := array_append(a_ids, l.id);  a_qty := array_append(a_qty, l.qty_ordered);
      end if;
      continue;
    end if;
    if l.id = any(coalesce(p_preorder_line_ids, '{}'::uuid[])) then
      v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                             'kind', 'preorder', 'allocated', 0, 'backordered', 0, 'preorder', l.qty_ordered, 'combo', v_is_combo);
      p_moves := p_moves || jsonb_build_object('line_id', l.id, 'qty', l.qty_ordered);  p_n := p_n + 1;
      for c in select k.id, k.qty_ordered from public.so_line k where k.combo_line_id = l.id order by k.line_no loop p_moves := p_moves || jsonb_build_object('line_id', c.id, 'qty', c.qty_ordered); end loop;
      continue;
    end if;
    if v_is_combo then
      -- 콤보 단위 = min(구성품 재고 키마다 floor(가용 ÷ 콤보 하나에 드는 낱개)) · 같은 재고 키를 쓰는 구성품은 합쳐 센다
      v_cu := l.qty_ordered;
      for v_pid_need in
        select coalesce(pp.parent_product_id, pp.id) as stock_pid, sum(k.combo_qty * k.pack_factor) as need_ea
        from public.so_line k join public.product pp on pp.id = k.product_id where k.combo_line_id = l.id group by 1
      loop
        v_cu := least(v_cu, floor(coalesce((v_avail->>v_pid_need.stock_pid::text)::numeric, 0) / v_pid_need.need_ea));
      end loop;
      for v_pid_need in
        select coalesce(pp.parent_product_id, pp.id) as stock_pid, sum(k.combo_qty * k.pack_factor) as need_ea
        from public.so_line k join public.product pp on pp.id = k.product_id where k.combo_line_id = l.id group by 1
      loop
        v_avail := v_avail || jsonb_build_object(v_pid_need.stock_pid::text, coalesce((v_avail->>v_pid_need.stock_pid::text)::numeric, 0) - v_cu * v_pid_need.need_ea);
      end loop;
      v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                             'kind', case when v_cu = l.qty_ordered then 'allocated' when v_cu = 0 then 'backorder' else 'partial' end,
                                             'allocated', v_cu, 'backordered', l.qty_ordered - v_cu, 'preorder', 0, 'combo', true);
      if v_cu < l.qty_ordered then
        b_moves := b_moves || jsonb_build_object('line_id', l.id, 'qty', l.qty_ordered - v_cu);  b_n := b_n + 1;
      end if;
      for c in select k.id, k.qty_ordered, k.combo_qty from public.so_line k where k.combo_line_id = l.id order by k.line_no loop
        if v_cu > 0 then a_ids := array_append(a_ids, c.id);  a_qty := array_append(a_qty, v_cu * c.combo_qty); end if;
        if v_cu < l.qty_ordered then b_moves := b_moves || jsonb_build_object('line_id', c.id, 'qty', (l.qty_ordered - v_cu) * c.combo_qty); end if;
      end loop;
      continue;
    end if;
    v_key := l.stock_pid::text;
    v_rem   := coalesce((v_avail->>v_key)::numeric, 0);
    v_alloc := least(l.qty_ordered, floor(v_rem / l.pack_factor));
    v_avail := v_avail || jsonb_build_object(v_key, v_rem - v_alloc * l.pack_factor);
    v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                           'available_ea_before', v_rem,
                                           'kind', case when v_alloc = l.qty_ordered then 'allocated' when v_alloc = 0 then 'backorder' else 'partial' end,
                                           'allocated', v_alloc, 'backordered', l.qty_ordered - v_alloc, 'preorder', 0);
    if v_alloc > 0 then a_ids := array_append(a_ids, l.id);  a_qty := array_append(a_qty, v_alloc); end if;
    if v_alloc < l.qty_ordered then
      b_moves := b_moves || jsonb_build_object('line_id', l.id, 'qty', l.qty_ordered - v_alloc);  b_n := b_n + 1;
    end if;
  end loop;

  if coalesce(array_length(a_ids, 1), 0) = 0 and b_n = 0 and p_n = 0 then
    raise exception 'Order % has no lines to allocate — nothing was saved', v_so.so_number;
  end if;

  -- 어느 무리가 원래 번호를 지키나(이견 1) — hold 는 전부 원래(나누지 않는다)
  v_keep := case when p_hold then 'hold'
                 when coalesce(array_length(a_ids, 1), 0) > 0 then 'allocated'
                 when b_n > 0 then 'backorder'
                 else 'preorder' end;

  if not p_commit then
    return jsonb_build_object('so_number', v_so.so_number, 'committed', false, 'keeps', v_keep, 'lines', v_plan,
      'siblings', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
         select jsonb_build_object('split_reason', 'stock_short', 'lines', b_n) as x where b_n > 0 and v_keep <> 'backorder' and not p_hold
         union all
         select jsonb_build_object('split_reason', 'preorder', 'lines', p_n) where p_n > 0 and v_keep <> 'preorder' and not p_hold) z));
  end if;

  -- 확정(so_confirm) — 원래를 draft → confirmed 로 먼저 올린다(형제가 확정 흔적을 물려받는다)
  if p_confirm then
    update public.so set status = 'confirmed', confirmed_at = now(), confirmed_by = p_staff, updated_by = p_staff
    where id = p_so_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not confirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;
  end if;

  -- 형제 — 원래가 지키지 않는 무리만(빈 문서 없음) · B 가 앞 글자
  if b_n > 0 and v_keep <> 'backorder' then
    v_sib_b := public.so_split(p_so_id, 'stock_short', b_moves, 'confirmed', p_staff);
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'backorder', null from public.so_line x where x.so_id = v_sib_b.id and not exists (select 1 from public.so_line k where k.combo_line_id = x.id);   -- asm-2a: 콤보 줄 제외
    v_sibs := v_sibs || jsonb_build_object('so_id', v_sib_b.id, 'so_number', v_sib_b.so_number, 'split_reason', 'stock_short', 'lines', b_n);
  end if;
  if p_n > 0 and v_keep <> 'preorder' then
    v_sib_p := public.so_split(p_so_id, 'preorder', p_moves, 'confirmed', p_staff);
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'preorder', p_staff from public.so_line x where x.so_id = v_sib_p.id and not exists (select 1 from public.so_line k where k.combo_line_id = x.id);   -- asm-2a
    v_sibs := v_sibs || jsonb_build_object('so_id', v_sib_p.id, 'so_number', v_sib_p.so_number, 'split_reason', 'preorder', 'lines', p_n);
  end if;

  -- 원래에 남은 줄의 예약
  if v_keep = 'hold' then
    for i in 1 .. coalesce(array_length(a_ids, 1), 0) loop
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (a_ids[i], a_qty[i], 'hold', p_staff);
    end loop;
  elsif v_keep = 'allocated' then
    for i in 1 .. array_length(a_ids, 1) loop                                          -- a_qty = 잡는 수량 = so_split 뒤 그 줄의 qty_ordered
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (a_ids[i], a_qty[i], 'allocated', null);
    end loop;
  elsif v_keep = 'backorder' then
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'backorder', null from public.so_line x where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
      and not exists (select 1 from public.so_line k where k.combo_line_id = x.id);                                           -- asm-2a
  else
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'preorder', p_staff from public.so_line x where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
      and not exists (select 1 from public.so_line k where k.combo_line_id = x.id);                                           -- asm-2a
  end if;

  select * into v_so from public.so where id = p_so_id;
  return jsonb_build_object('so_number', v_so.so_number, 'status', v_so.status, 'committed', true, 'keeps', v_keep, 'lines', v_plan, 'siblings', v_sibs);
end;
$$;

-- ═══ 9) so_allocate_all 재발행(POS · counter 확정) — 20260925142307_so_pos_a2_flow.sql 바이트 복사 · 콤보 줄 제외 ═══
create or replace function public.so_allocate_all(p_so_id uuid, p_staff uuid) returns int
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  l    record;
  v_n  int := 0;
begin
  for l in
    select x.id from public.so_line x
    where x.so_id = p_so_id and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
      and not exists (select 1 from public.so_line c where c.combo_line_id = x.id)                                             -- asm-2a(판정 244): 콤보 줄은 예약하지 않는다 · 구성품 줄만
    order by x.line_no
  loop
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || l.id::text));
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'allocated', p_staff from public.so_line x where x.id = l.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- ═══ 10) so_split 재발행 — 20260924143507_so_split_pick_short.sql 바이트 복사 · 형제 줄에 매듭 두 칸 복사 · 일부만 간 콤보의 구성품을 형제의 콤보 줄에 다시 매단다 ═══
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
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_so) || jsonb_build_object(
      'id', v_id, 'so_number', v_num, 'status', 'draft',
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
                                  surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, split_from_line_id, updated_by, combo_line_id, combo_qty)
      values (v_id, v_next, l.product_id, l.sku, l.product_name, l.unit, l.pack_factor, m.qty, 0,
              l.list_price, l.discount_pct, l.unit_price, l.price_override, l.discount_source, l.deal_line_id, l.free_reason,
              l.surcharge_pct, l.surcharge_amount, l.surcharge_label, l.tax_rule, l.comments, l.id, p_staff, l.combo_line_id, l.combo_qty);   -- 형제에 새 줄 · 계보 · asm-2a: 콤보 매듭 두 칸도
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

-- ═══ 11) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_line' and column_name in ('combo_line_id', 'combo_qty')) <> 2 then v_bad := v_bad || ' columns'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.so_line'::regclass and conname in ('so_line_free_pair_ck', 'so_line_combo_self_ck', 'so_line_combo_pair_ck', 'so_line_combo_qty_ck', 'so_line_combo_values_ck')) <> 5 then v_bad := v_bad || ' checks'; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.so_line'::regclass and tgname = 'so_line_combo_parent_ck' and tgdeferrable and tginitdeferred) then v_bad := v_bad || ' deferred-trigger'; end if;
  if to_regprocedure('public.so_lines_available(uuid)') is null or to_regprocedure('public.so_combo_children_insert(public.so_line, uuid)') is null or to_regprocedure('public.so_combo_children_sync(uuid, uuid)') is null or to_regprocedure('public.so_combo_is(uuid)') is null then v_bad := v_bad || ' helpers'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_line_add', 'so_lines_paste', 'so_line_update', 'so_line_remove', 'so_detail', 'so_allocate_run', 'so_allocate_all', 'so_split') and p.prosrc like '%asm-2a%') <> 8 then v_bad := v_bad || ' reissues'; end if;
  if has_function_privilege('authenticated', 'public.so_combo_children_insert(public.so_line, uuid)', 'execute') or has_function_privilege('authenticated', 'public.so_allocate_run(uuid, uuid, uuid[], boolean, boolean, boolean, uuid)', 'execute') or has_function_privilege('authenticated', 'public.so_split(uuid, text, jsonb, text, uuid)', 'execute') then v_bad := v_bad || ' inner-grants'; end if;
  if has_table_privilege('authenticated', 'public.so_line', 'insert') or has_table_privilege('authenticated', 'public.so_line', 'update') or has_table_privilege('authenticated', 'public.so_line', 'delete') then v_bad := v_bad || ' so_line-opened'; end if;
  if exists (select 1 from public.so_line where combo_line_id is not null or combo_qty is not null) then v_bad := v_bad || ' old-rows-touched'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM244', message = format('STOP - asm-2a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
