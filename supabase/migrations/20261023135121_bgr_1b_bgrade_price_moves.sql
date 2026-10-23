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

-- ═══ bgr-1b — B급 칸 ② B급 값 · B급으로 옮기기 · 되돌리기 · 다른 길 막기 (2026-10-23 · 판정 630 · 631 · 632 · 637 · 638 · 639 · 642 · 644 · 645) ═══
--   ① 표 bgrade_price(칸 × 제품 · 값 하나) — 읽기 authenticated · 쓰기는 창구만(쓰기 권한 0)
--   ② bgrade_price_put(속 · 권한 0) · bgrade_price_set(조정 문 · 잔고 있는 줄만 · p_reprice) · bgrade_stock(읽기 · 원가 칸 없음 · 「값 없음」 = has_price false)
--   ③ bgrade_move_in · bgrade_move_out(조정 문 · 속은 inv_move_now 그대로 · 세션 표지 ims.bgrade_move 로 stock_move 열쇠 · 칸 막기를 건넌다)
--   ④ 다른 길 막기 — 원장 가드 inv_ledger_bgrade_guard(IMS 사건이 B급 칸을 건드리면: 조정 · 판매 출고 · 표지 켠 칸 옮기기만 통과) +
--      칸 칸(bin_id)의 이른 거부 ims_bin_bgrade_refuse(입고 셋 · 크레딧 리스탁 · 트랜스퍼 정산 · 칸 옮기기 둘) + inv_move_bin_contents 재발행(B급 칸 거부) + inv_move_require 재발행(표지)
--   ⭐ 값이 「살아 있는」 것은 그 칸에 그 SKU 잔고 > 0 일 때뿐 — 0 에서 조정으로 다시 들어오면 원장 가드가 옛 값을 지운다(판정 644 「값 없음」) · move_in 은 죽은 값을 덮는다
--   새 시퀀스 0 · 새 표 하나(판정 615 — 권한을 이 파일에서)

-- ═══ ① 표 ═══
create table public.bgrade_price (
  id          uuid primary key default gen_random_uuid(),
  bin_id      uuid not null references public.ref_bin(id),
  product_id  uuid not null references public.product(id),
  price       numeric not null check (price > 0 and price = round(price, 2)),
  pct         numeric check (pct > 0 and pct < 100),
  basis_price numeric check (basis_price > 0),
  set_by      uuid references public.ims_staff(id),
  set_at      timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.ims_staff(id),
  constraint bgrade_price_bin_product_key unique (bin_id, product_id),
  constraint bgrade_price_pct_basis_ck check ((pct is null) = (basis_price is null))
);
create index bgrade_price_product_idx on public.bgrade_price (product_id);
create index bgrade_price_set_by_idx on public.bgrade_price (set_by);
create index bgrade_price_updated_by_idx on public.bgrade_price (updated_by);
create trigger bgrade_price_touch before update on public.bgrade_price for each row execute function public.ims_touch();
alter table public.bgrade_price enable row level security;
create policy bgrade_price_select on public.bgrade_price for select to authenticated using (true);
revoke all on table public.bgrade_price from public, anon, authenticated, service_role;
grant select on table public.bgrade_price to authenticated;
comment on table public.bgrade_price is 'bgr-1b 판정 630 · 631 · 642 · 645 — B급 칸 × 제품의 B급 값 하나(POS 최종 값) · % 로 넣었으면 pct · basis_price(그때 Wholesale 낱개 값) · 값이 살아 있는 것은 그 칸에 그 SKU 잔고 > 0 일 때뿐 · 쓰기는 bgrade_price_set · bgrade_move_in 만';

-- ═══ ② 값 — 속(권한 0) ═══
create function public.bgrade_price_put(p_bin public.ref_bin, p_p public.product, p_price numeric, p_pct numeric, p_reprice boolean, p_staff uuid) returns jsonb
language plpgsql set search_path = public, pg_temp as $$
-- bgr-1b: 값 또는 % 하나 → 센트 값 하나(645) · 642(살아 있는 다른 값은 거부 · p_reprice 면 칸 값 전체를 바꾸고 relabel 경고) · 부르는 쪽이 문을 이미 봤다
declare v_wh text;  v_bal numeric;  v_cur public.bgrade_price%rowtype;  v_basis numeric;  v_new numeric;  v_live boolean;
begin
  if not p_bin.is_bgrade then raise exception 'Bin % is not a B-grade bin — mark it B-grade first (master) — nothing was saved', p_bin.name; end if;
  if not p_bin.is_active then raise exception 'Bin % is inactive — nothing was saved', p_bin.name; end if;
  if not p_p.is_active then raise exception 'Product % is inactive — nothing was saved', p_p.sku; end if;
  if p_p.parent_product_id is not null then raise exception 'Product % is a set or pack — B-grade prices are for the single-unit SKU — nothing was saved', p_p.sku; end if;
  if (p_price is null) = (p_pct is null) then raise exception 'Enter either a B-grade price or a percent off Wholesale, not both and not neither — nothing was saved'; end if;
  if p_pct is not null then
    if p_pct <= 0 or p_pct >= 100 then raise exception 'Percent off must be more than 0 and less than 100 (got %) — nothing was saved', p_pct; end if;
    select pp.price into v_basis from public.product_price pp join public.ref_price_tier t on t.id = pp.tier_id where pp.product_id = p_p.id and t.code = 1 and t.purpose = 'sale';
    if coalesce(v_basis, 0) <= 0 then raise exception 'No Wholesale price for % — enter a B-grade price instead — nothing was saved', p_p.sku; end if;
    v_new := round(v_basis * (1 - p_pct / 100), 2);                                      -- 판정 645: 깎는 비율 · 센트 반올림
    if v_new <= 0 then raise exception 'Percent off % leaves no price for % — nothing was saved', p_pct, p_p.sku; end if;
  else
    if p_price <= 0 then raise exception 'A B-grade price must be more than 0 — to give stock away use a stock adjustment — nothing was saved'; end if;
    if p_price <> round(p_price, 2) then raise exception 'A B-grade price is in cents (two decimals at most, got %) — nothing was saved', p_price; end if;
    v_new := round(p_price, 2);                                                           -- 센트 칸으로 남긴다(5 → 5.00)
  end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = p_bin.warehouse_id;
  v_bal := public.inv_adjust_ledger(v_wh, p_bin.name, p_p.sku);
  select * into v_cur from public.bgrade_price bp where bp.bin_id = p_bin.id and bp.product_id = p_p.id for update;
  v_live := found and v_bal > 0;
  if v_live and v_cur.price = v_new then
    return jsonb_build_object('bin_id', p_bin.id, 'bin', p_bin.name, 'product_id', p_p.id, 'sku', p_p.sku, 'price', v_cur.price, 'pct', v_cur.pct, 'basis_price', v_cur.basis_price,
                              'qty', v_bal, 'changed', false, 'relabel', false, 'previous_price', null, 'warnings', '[]'::jsonb);
  end if;
  if v_live and not coalesce(p_reprice, false) then
    raise exception 'Bin % already holds % at % — one price per SKU in a B-grade bin: use another B-grade bin, or reprice the whole bin and relabel — nothing was saved', p_bin.name, p_p.sku, v_cur.price;
  end if;
  insert into public.bgrade_price (bin_id, product_id, price, pct, basis_price, set_by, set_at, updated_by)
  values (p_bin.id, p_p.id, v_new, p_pct, case when p_pct is not null then v_basis end, p_staff, now(), p_staff)
  on conflict (bin_id, product_id) do update set price = excluded.price, pct = excluded.pct, basis_price = excluded.basis_price, set_by = excluded.set_by, set_at = excluded.set_at;
  return jsonb_build_object('bin_id', p_bin.id, 'bin', p_bin.name, 'product_id', p_p.id, 'sku', p_p.sku, 'price', v_new, 'pct', p_pct, 'basis_price', case when p_pct is not null then v_basis end,
                            'qty', v_bal, 'changed', true, 'relabel', v_live, 'previous_price', case when v_live then v_cur.price end,
                            'warnings', case when v_live then '["relabel"]'::jsonb else '[]'::jsonb end);
end $$;
revoke all on function public.bgrade_price_put(public.ref_bin, public.product, numeric, numeric, boolean, uuid) from public, anon, authenticated, service_role;

-- ═══ ② 값 창구 — 잔고 있는 줄만(값 없는 B급 재고 · 값 바꾸기) ═══
create function public.bgrade_price_set(p_bin_id uuid, p_product_id uuid, p_price numeric default null, p_pct numeric default null, p_reprice boolean default false) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
-- bgr-1b 판정 638 · 642 · 644: 조정 문 · 그 칸에 그 SKU 잔고가 있을 때만(없으면 move_in 이 옮기며 값을 정한다) · 살아 있는 값과 다르면 p_reprice 로만
declare v_staff uuid;  v_b public.ref_bin%rowtype;  v_p public.product%rowtype;  v_wh text;  v_bal numeric;
begin
  v_staff := public.inv_adjust_require(null);
  select * into v_b from public.ref_bin b where b.id = p_bin_id;
  if not found then raise exception 'Bin not found (%) — nothing was saved', p_bin_id; end if;
  perform public.inv_adjust_require(v_b.warehouse_id);                                    -- 그 칸의 창고 접근
  select * into v_p from public.product p where p.id = p_product_id;
  if not found then raise exception 'Product not found (%) — nothing was saved', p_product_id; end if;
  if not v_b.is_bgrade then raise exception 'Bin % is not a B-grade bin — mark it B-grade first (master) — nothing was saved', v_b.name; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_b.warehouse_id;
  v_bal := public.inv_adjust_ledger(v_wh, v_b.name, v_p.sku);
  if v_bal <= 0 then
    raise exception 'No B-grade stock of % in bin % — Move to B-grade sets the price as it moves; prices are set here only for stock already in the bin — nothing was saved', v_p.sku, v_b.name;
  end if;
  return public.bgrade_price_put(v_b, v_p, p_price, p_pct, p_reprice, v_staff);
end $$;
revoke all on function public.bgrade_price_set(uuid, uuid, numeric, numeric, boolean) from public, anon, service_role;
grant execute on function public.bgrade_price_set(uuid, uuid, numeric, numeric, boolean) to authenticated;
comment on function public.bgrade_price_set(uuid, uuid, numeric, numeric, boolean) is 'bgr-1b 판정 630 · 631 · 638 · 642 · 644 · 645 — B급 값 정하기(조정 문) · 값 또는 Wholesale 에서 깎는 % 하나 · 잔고 있는 줄만 · 살아 있는 다른 값은 p_reprice 로만(relabel 경고) · 같은 값 무해';

-- ═══ ② 읽기 창구 — B급 칸 × 제품 · 「값 없음」(has_price false) · 원가 칸 없음(판정 262 · 575) ═══
create function public.bgrade_stock(p_warehouse_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_staff uuid;  v_rows jsonb;
begin
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- 문 = 로그인 + 활성 직원(stk_ 창구와 같다)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  with b as (
    select rb.id, rb.name, w.id as wh_id, w.name as wh from public.ref_bin rb join public.ref_warehouse w on w.id = rb.warehouse_id
     where rb.is_bgrade and w.is_active and (p_warehouse_id is null or w.id = p_warehouse_id)
  ), x as (
    select b.wh_id, b.wh, b.id as bin_id, b.name as bin, ib.sku, ib.qty, p.id as product_id, p.name as product_name,
           bp.price, bp.pct, bp.basis_price, bp.set_at, s.name as set_by,
           (select pp.price from public.product_price pp join public.ref_price_tier t on t.id = pp.tier_id where pp.product_id = p.id and t.code = 1 and t.purpose = 'sale') as wholesale_now
      from b join public.inv_balance ib on ib.warehouse = b.wh and ib.bin = b.name and ib.qty <> 0
      left join public.product p on p.sku = ib.sku
      left join public.bgrade_price bp on bp.bin_id = b.id and bp.product_id = p.id
      left join public.ims_staff s on s.id = bp.set_by
  )
  select coalesce(jsonb_agg(jsonb_build_object('warehouse_id', x.wh_id, 'warehouse', x.wh, 'bin_id', x.bin_id, 'bin', x.bin, 'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name,
           'qty', x.qty, 'price', x.price, 'pct', x.pct, 'basis_price', x.basis_price, 'wholesale_now', x.wholesale_now, 'set_by', x.set_by, 'set_at', x.set_at,
           'has_price', x.price is not null) order by x.wh, x.bin, x.sku), '[]'::jsonb)
    into v_rows from x;
  return jsonb_build_object('row_count', jsonb_array_length(v_rows), 'no_price_count', (select count(*) from jsonb_array_elements(v_rows) r where not (r->>'has_price')::boolean and (r->>'qty')::numeric > 0), 'rows', v_rows);
end $$;
revoke all on function public.bgrade_stock(uuid) from public, anon, service_role;
grant execute on function public.bgrade_stock(uuid) to authenticated;
comment on function public.bgrade_stock(uuid) is 'bgr-1b 판정 637 · 644 — B급 칸 × 제품 잔고 · B급 값 · % · 그때 Wholesale · 지금 Wholesale · 정한 사람 · has_price(false 이고 qty > 0 = 「값 없음」 · POS 가 막는다) · 수량 · 값만(원가 칸 없음) · jsonb 한 행';

-- ═══ ③ B급으로 옮기기 · 되돌리기 — 조정 문 · 속은 inv_move_now ═══
create function public.bgrade_move_in(p_warehouse_id uuid, p_lines jsonb, p_note text default null) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
-- bgr-1b 판정 638 · 642: 정상 칸 → B급 칸 · 줄마다 price 또는 pct(살아 있는 값이 있으면 없어도 된다 = 같은 값으로 더 넣기) · 원가 그대로(637 · bin_move 는 레이어를 안 건드린다)
declare v_staff uuid;  v_wh text;  v_l jsonb;  v_p public.product%rowtype;  v_f public.ref_bin%rowtype;  v_t public.ref_bin%rowtype;  v_cur public.bgrade_price%rowtype;
        v_keys text[] := '{}';  v_prices jsonb := '[]'::jsonb;  v_mv jsonb := '[]'::jsonb;  v_r jsonb;  v_bal numeric;
begin
  v_staff := public.inv_adjust_require(p_warehouse_id);
  select w.name into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if v_wh is null then raise exception 'Warehouse not found or inactive — nothing was saved'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'p_lines must be a JSON array of {sku|product_id, from_bin|from_bin_id, to_bin|to_bin_id, qty, price|pct} — nothing was saved';
  end if;
  for v_l in select * from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_l) <> 'object' then raise exception 'Each line must be a JSON object — nothing was saved'; end if;
    if nullif(v_l->>'product_id', '') is not null then select * into v_p from public.product p where p.id = (v_l->>'product_id')::uuid;
    else select * into v_p from public.product p where p.sku = trim(v_l->>'sku'); end if;
    if not found then raise exception 'Product not found (%) — nothing was saved', coalesce(v_l->>'sku', v_l->>'product_id'); end if;
    if nullif(v_l->>'from_bin_id', '') is not null then select * into v_f from public.ref_bin b where b.id = (v_l->>'from_bin_id')::uuid and b.warehouse_id = p_warehouse_id;
    else select * into v_f from public.ref_bin b where b.warehouse_id = p_warehouse_id and b.name = trim(v_l->>'from_bin'); end if;
    if not found then raise exception 'From bin not found in this warehouse (%) — nothing was saved', coalesce(v_l->>'from_bin', v_l->>'from_bin_id'); end if;
    if nullif(v_l->>'to_bin_id', '') is not null then select * into v_t from public.ref_bin b where b.id = (v_l->>'to_bin_id')::uuid and b.warehouse_id = p_warehouse_id;
    else select * into v_t from public.ref_bin b where b.warehouse_id = p_warehouse_id and b.name = trim(v_l->>'to_bin'); end if;
    if not found then raise exception 'To bin not found in this warehouse (%) — nothing was saved', coalesce(v_l->>'to_bin', v_l->>'to_bin_id'); end if;
    if v_f.is_bgrade then raise exception 'From bin % is a B-grade bin — B-grade to B-grade moves are not allowed: Move back first — nothing was saved', v_f.name; end if;
    if not v_t.is_bgrade then raise exception 'To bin % is not a B-grade bin — use Stock moves between regular bins — nothing was saved', v_t.name; end if;
    if (v_t.id::text || '|' || v_p.id::text) = any(v_keys) then raise exception '% is on two lines into bin % — one line per SKU and B-grade bin — nothing was saved', v_p.sku, v_t.name; end if;
    v_keys := v_keys || (v_t.id::text || '|' || v_p.id::text);
    if nullif(v_l->>'price', '') is not null or nullif(v_l->>'pct', '') is not null then
      v_r := public.bgrade_price_put(v_t, v_p, nullif(v_l->>'price', '')::numeric, nullif(v_l->>'pct', '')::numeric, false, v_staff);
    else
      select * into v_cur from public.bgrade_price bp where bp.bin_id = v_t.id and bp.product_id = v_p.id;
      v_bal := public.inv_adjust_ledger(v_wh, v_t.name, v_p.sku);
      if not found or v_bal <= 0 then raise exception 'No B-grade price for % in bin % yet — enter a price or a percent off Wholesale — nothing was saved', v_p.sku, v_t.name; end if;
      v_r := jsonb_build_object('bin_id', v_t.id, 'bin', v_t.name, 'product_id', v_p.id, 'sku', v_p.sku, 'price', v_cur.price, 'pct', v_cur.pct, 'basis_price', v_cur.basis_price,
                                'qty', v_bal, 'changed', false, 'relabel', false, 'previous_price', null, 'warnings', '[]'::jsonb);
    end if;
    v_prices := v_prices || v_r;
    v_mv := v_mv || jsonb_build_object('product_id', v_p.id, 'from_bin_id', v_f.id, 'to_bin_id', v_t.id, 'qty', v_l->'qty');
  end loop;
  perform set_config('ims.bgrade_move', 'on', true);                                       -- 표지 — inv_move_require(stock_move) · 칸 칸 거부 · 원장 가드가 이 옮기기만 건넌다
  v_r := public.inv_move_now(p_warehouse_id, v_mv, coalesce(nullif(trim(p_note), ''), 'Move to B-grade'));
  perform set_config('ims.bgrade_move', '', true);
  return v_r || jsonb_build_object('kind', 'bgrade_in', 'prices', v_prices);
end $$;
revoke all on function public.bgrade_move_in(uuid, jsonb, text) from public, anon, service_role;
grant execute on function public.bgrade_move_in(uuid, jsonb, text) to authenticated;
comment on function public.bgrade_move_in(uuid, jsonb, text) is 'bgr-1b 판정 637 · 638 · 642 — Move to B-grade: 정상 칸 → B급 칸(조정 문) · 줄마다 price 또는 pct(살아 있는 같은 값이면 생략 가능 · 다른 값 거부) · 속 = inv_move_now(원장 bin_move · 레이어 무변) · B급 → B급 거부';

create function public.bgrade_move_out(p_warehouse_id uuid, p_lines jsonb, p_note text default null) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
-- bgr-1b 판정 639: B급 칸 → 정상 칸(조정 문) · 값 인자 없음 · 다 빠지면 값은 뜻을 잃는다(잔고 0 = 죽은 값)
declare v_staff uuid;  v_l jsonb;  v_p public.product%rowtype;  v_f public.ref_bin%rowtype;  v_t public.ref_bin%rowtype;  v_mv jsonb := '[]'::jsonb;  v_r jsonb;
begin
  v_staff := public.inv_adjust_require(p_warehouse_id);
  if not exists (select 1 from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active) then raise exception 'Warehouse not found or inactive — nothing was saved'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'p_lines must be a JSON array of {sku|product_id, from_bin|from_bin_id, to_bin|to_bin_id, qty} — nothing was saved';
  end if;
  for v_l in select * from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_l) <> 'object' then raise exception 'Each line must be a JSON object — nothing was saved'; end if;
    if nullif(v_l->>'product_id', '') is not null then select * into v_p from public.product p where p.id = (v_l->>'product_id')::uuid;
    else select * into v_p from public.product p where p.sku = trim(v_l->>'sku'); end if;
    if not found then raise exception 'Product not found (%) — nothing was saved', coalesce(v_l->>'sku', v_l->>'product_id'); end if;
    if nullif(v_l->>'from_bin_id', '') is not null then select * into v_f from public.ref_bin b where b.id = (v_l->>'from_bin_id')::uuid and b.warehouse_id = p_warehouse_id;
    else select * into v_f from public.ref_bin b where b.warehouse_id = p_warehouse_id and b.name = trim(v_l->>'from_bin'); end if;
    if not found then raise exception 'From bin not found in this warehouse (%) — nothing was saved', coalesce(v_l->>'from_bin', v_l->>'from_bin_id'); end if;
    if nullif(v_l->>'to_bin_id', '') is not null then select * into v_t from public.ref_bin b where b.id = (v_l->>'to_bin_id')::uuid and b.warehouse_id = p_warehouse_id;
    else select * into v_t from public.ref_bin b where b.warehouse_id = p_warehouse_id and b.name = trim(v_l->>'to_bin'); end if;
    if not found then raise exception 'To bin not found in this warehouse (%) — nothing was saved', coalesce(v_l->>'to_bin', v_l->>'to_bin_id'); end if;
    if not v_f.is_bgrade then raise exception 'From bin % is not a B-grade bin — use Stock moves between regular bins — nothing was saved', v_f.name; end if;
    if v_t.is_bgrade then raise exception 'To bin % is a B-grade bin — B-grade to B-grade moves are not allowed: move back to a regular bin first — nothing was saved', v_t.name; end if;
    v_mv := v_mv || jsonb_build_object('product_id', v_p.id, 'from_bin_id', v_f.id, 'to_bin_id', v_t.id, 'qty', v_l->'qty');
  end loop;
  perform set_config('ims.bgrade_move', 'on', true);
  v_r := public.inv_move_now(p_warehouse_id, v_mv, coalesce(nullif(trim(p_note), ''), 'Move back from B-grade'));
  perform set_config('ims.bgrade_move', '', true);
  return v_r || jsonb_build_object('kind', 'bgrade_out');
end $$;
revoke all on function public.bgrade_move_out(uuid, jsonb, text) from public, anon, service_role;
grant execute on function public.bgrade_move_out(uuid, jsonb, text) to authenticated;
comment on function public.bgrade_move_out(uuid, jsonb, text) is 'bgr-1b 판정 639 — Move back: B급 칸 → 정상 칸(조정 문) · 속 = inv_move_now · B급 → B급 거부 · 칸이 비면 그 값은 뜻을 잃는다(다음 move_in 이 덮는다)';

-- ═══ ④ 다른 길 막기 — 칸 칸의 이른 거부(입고 · 크레딧 리스탁 · 트랜스퍼 정산 · 칸 옮기기) ═══
create function public.ims_bin_bgrade_refuse() returns trigger
language plpgsql set search_path = public, pg_temp as $$
-- bgr-1b: tg_argv = (칸 이름, 사람 말 길 이름, 'move' 면 B급 셸 표지가 켜졌을 때 통과) · 바뀌지 않은 update 는 보지 않는다
declare v_id uuid;  v_name text;
begin
  v_id := nullif(to_jsonb(new) ->> tg_argv[0], '')::uuid;
  if v_id is null then return new; end if;
  if tg_op = 'UPDATE' and nullif(to_jsonb(old) ->> tg_argv[0], '')::uuid is not distinct from v_id then return new; end if;
  if tg_argv[2] = 'move' and coalesce(current_setting('ims.bgrade_move', true), '') = 'on' then return new; end if;
  select rb.name into v_name from public.ref_bin rb where rb.id = v_id and rb.is_bgrade;
  if v_name is null then return new; end if;
  raise exception using errcode = 'IM637', message = format('%s: bin %s is a B-grade bin — %s — nothing was saved', tg_argv[1], v_name,
    case when tg_argv[2] = 'move' then 'use Move to B-grade / Move back for B-grade bins' else 'pick a regular bin; B-grade stock comes in only with Move to B-grade or a stock adjustment' end);
end $$;
revoke all on function public.ims_bin_bgrade_refuse() from public, anon, authenticated, service_role;
create trigger po_receipt_line_bgrade_refuse before insert or update of bin_id on public.po_receipt_line for each row execute function public.ims_bin_bgrade_refuse('bin_id', 'Receiving', '');
create trigger po_receipt_work_bgrade_refuse before insert or update of bin_id on public.po_receipt_work for each row execute function public.ims_bin_bgrade_refuse('bin_id', 'Receiving put-away', '');
create trigger po_receipt_diff_bgrade_refuse before insert or update of bin_id on public.po_receipt_diff for each row execute function public.ims_bin_bgrade_refuse('bin_id', 'Receiving difference', '');
create trigger so_credit_line_bgrade_refuse before insert or update of restock_bin_id on public.so_credit_line for each row execute function public.ims_bin_bgrade_refuse('restock_bin_id', 'Credit restock', '');
create trigger inv_transfer_settle_bgrade_refuse before insert or update of bin_id on public.inv_transfer_settle for each row execute function public.ims_bin_bgrade_refuse('bin_id', 'Transfer settle', '');
create trigger inv_move_line_bgrade_from before insert or update of from_bin_id on public.inv_move_line for each row execute function public.ims_bin_bgrade_refuse('from_bin_id', 'Stock move', 'move');
create trigger inv_move_line_bgrade_to before insert or update of to_bin_id on public.inv_move_line for each row execute function public.ims_bin_bgrade_refuse('to_bin_id', 'Stock move', 'move');

-- ═══ ④ 다른 길 막기 — 원장 가드(모든 IMS 원장 창구의 마지막 문) ═══
create function public.inv_ledger_bgrade_guard() returns trigger
language plpgsql set search_path = public, pg_temp as $$
-- bgr-1b 판정 635 · 638 · 639: IMS 사건(source ims)이 B급 칸을 건드리면 셋만 통과 — 조정(adjust_existing · adjust_new) · 판매 출고(sale_out 음수 · POS 1c) · 표지 켠 칸 옮기기(bin_move · B급 셸)
--   Cin7 적재(source cin7 · manual)는 보지 않는다 · 조정이 잔고 0 이하에서 B급 칸에 넣으면 그 칸 · SKU 의 옛 B급 값을 지운다(판정 644 — 「값 없음」으로 들어온다)
declare v_bin uuid;
begin
  if new.source is distinct from 'ims' or coalesce(new.bin, '') = '' then return new; end if;
  select rb.id into v_bin from public.ref_bin rb join public.ref_warehouse w on w.id = rb.warehouse_id where w.name = new.warehouse and rb.name = new.bin and rb.is_bgrade;
  if v_bin is null then return new; end if;
  if new.event_type in ('adjust_existing', 'adjust_new') then
    if new.qty_delta > 0 and public.inv_adjust_ledger(new.warehouse, new.bin, new.sku) <= 0 then
      delete from public.bgrade_price bp using public.product p where bp.bin_id = v_bin and bp.product_id = p.id and p.sku = new.sku;
    end if;
    return new;
  end if;
  if new.event_type = 'sale_out' and new.qty_delta < 0 then return new; end if;
  if new.raw->>'kind' = 'bin_move' and coalesce(current_setting('ims.bgrade_move', true), '') = 'on' then return new; end if;
  raise exception using errcode = 'IM637', message = format('Bin %s in %s is a B-grade bin — stock goes in or out of it only with Move to B-grade / Move back, a stock adjustment or a POS sale (%s %s %s) — nothing was saved',
    new.bin, new.warehouse, new.event_type, new.sku, new.qty_delta);
end $$;
revoke all on function public.inv_ledger_bgrade_guard() from public, anon, authenticated, service_role;
create trigger inv_ledger_bgrade_guard before insert on public.inv_ledger for each row execute function public.inv_ledger_bgrade_guard();

-- ═══ inv_move_require 재발행 — 원본 DB 바이트(md5 9db467a1abfb87f7b17916571c65805e) + 더한 줄(줄 끝 「bgr-1b」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.inv_move_require(p_warehouse_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_staff uuid;
begin
  if coalesce(current_setting('ims.bgrade_move', true), '') <> 'on' then              -- bgr-1b 판정 638: B급 셸(bgrade_move_in · out)이 조정 문(inv_adjust_require)을 본 뒤에는 stock_move 열쇠를 다시 보지 않는다
  perform public.ims_require_write('stock_move', 'saved');                                -- ⭐ 첫 줄 문 — admin · supervisor 역할로 · 그 밖은 사람마다 켠 stock_move(worker 도 · 판정 39 B · 63)
  end if;                                                                                  -- bgr-1b
  if p_warehouse_id is not null and not public.ims_can_warehouse(p_warehouse_id) then
    raise exception 'This move is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  return v_staff;
end;
$function$;

-- ═══ inv_move_bin_contents 재발행 — 원본 DB 바이트(md5 dc5822daf83b7c9648e90c3dcfdae9be) + 더한 줄(줄 끝 「bgr-1b」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.inv_move_bin_contents(p_warehouse_id uuid, p_bin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_wh public.ref_warehouse%rowtype; v_b public.ref_bin%rowtype; v_items jsonb;
begin
  perform public.inv_move_require(p_warehouse_id);                                        -- ⭐ 첫 줄 문(판정 63 · 창고 접근 · 활성 직원)
  select * into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if not found then raise exception 'Warehouse not found or inactive — nothing was saved'; end if;
  if p_bin_id is null then raise exception 'Bin not found in this warehouse — nothing was saved'; end if;
  select * into v_b from public.ref_bin b where b.id = p_bin_id;
  if not found then raise exception 'Bin not found in this warehouse (%) — nothing was saved', p_bin_id; end if;
  if v_b.warehouse_id <> v_wh.id then raise exception 'Bin % is in another warehouse — nothing was saved', v_b.name; end if;
  if not v_b.is_active then raise exception 'Bin % is inactive — nothing was saved', v_b.name; end if;
  if v_b.is_bgrade then raise exception 'Bin % is a B-grade bin — take stock out of it with Move back — nothing was saved', v_b.name; end if;   -- bgr-1b 판정 639: 칸 비우기(mover)는 B급 칸을 다루지 않는다
  with bal as (
    select b.sku, b.qty as book from public.inv_balance b where b.warehouse = v_wh.name and b.bin = v_b.name and b.qty <> 0
  ), x as (
    select bal.sku, bal.book, p.id as product_id, p.name as product_name,
           case when p.id is null then 'not in product master' when not p.is_active then 'inactive' when p.parent_product_id is not null then 'set or pack' end as blocked,
           case when p.id is null then 0 else public.inv_adjust_picked(v_wh.id, v_b.id, p.id) end as picked,
           op.waiting, op.movable, op.plans
      from bal
      left join public.product p on p.sku = bal.sku
      cross join lateral (
        select coalesce(sum(q.blocking_qty), 0) as waiting, coalesce(sum(q.movable_qty), 0) as movable,
               coalesce(jsonb_agg(jsonb_build_object('task_id', q.task_id, 'batch_label', q.batch_label, 'so_number', q.so_number, 'status', q.task_status,
                                                     'planned', q.planned_qty, 'blocking', q.blocking_qty, 'movable', q.movable_qty) order by q.task_id, q.row_id), '[]'::jsonb) as plans
          from public.inv_move_open_plans(v_wh.id, v_b.id, p.id) q) op
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'book', x.book, 'picked', x.picked, 'waiting', x.waiting,
           'max', case when x.blocked is not null then 0 else greatest(x.book - x.picked - x.waiting, 0) end,
           'plans', x.plans, 'follow', x.movable, 'blocked', x.blocked) order by x.sku), '[]'::jsonb)
    into v_items from x;
  return jsonb_build_object('warehouse_id', v_wh.id, 'warehouse', v_wh.name, 'bin_id', v_b.id, 'bin_name', v_b.name, 'item_count', jsonb_array_length(v_items), 'items', v_items);
end;
$function$;
-- ═══ 착지 ═══
do $$
declare v_bad text := '';
begin
  if (select relrowsecurity from pg_class where oid = 'public.bgrade_price'::regclass) is not true then v_bad := v_bad || ' rls'; end if;
  if (select relacl::text from pg_class where oid = 'public.bgrade_price'::regclass) <> '{postgres=arwdDxtm/postgres,authenticated=r/postgres}' then v_bad := v_bad || ' table_acl'; end if;
  if (select count(*) from pg_policy where polrelid = 'public.bgrade_price'::regclass) <> 1 then v_bad := v_bad || ' policies'; end if;
  if (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('bgrade_price_put', 'bgrade_price_set', 'bgrade_stock', 'bgrade_move_in', 'bgrade_move_out', 'ims_bin_bgrade_refuse', 'inv_ledger_bgrade_guard'))
     <> 'bgrade_move_in={postgres=X/postgres,authenticated=X/postgres} bgrade_move_out={postgres=X/postgres,authenticated=X/postgres} bgrade_price_put={postgres=X/postgres} bgrade_price_set={postgres=X/postgres,authenticated=X/postgres} bgrade_stock={postgres=X/postgres,authenticated=X/postgres} ims_bin_bgrade_refuse={postgres=X/postgres} inv_ledger_bgrade_guard={postgres=X/postgres}'
     then v_bad := v_bad || ' fn_acl'; end if;
  if (select count(*) from pg_trigger where not tgisinternal and tgenabled = 'O' and tgname in ('po_receipt_line_bgrade_refuse', 'po_receipt_work_bgrade_refuse', 'po_receipt_diff_bgrade_refuse', 'so_credit_line_bgrade_refuse',
        'inv_transfer_settle_bgrade_refuse', 'inv_move_line_bgrade_from', 'inv_move_line_bgrade_to', 'inv_ledger_bgrade_guard', 'bgrade_price_touch')) <> 9 then v_bad := v_bad || ' triggers'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_move_require', 'inv_move_bin_contents'))
     <> 'inv_move_bin_contents=5375991777c4816930a7bd8f3f5d6f8f inv_move_require=8c57daead0e7dd1ebfb4217e8424be0c' then v_bad := v_bad || ' reissue_bodies'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('inv_move_now', 'inv_move_line_set', 'inv_move_confirm', 'inv_post_move', 'inv_adjust_require', 'ref_bin_bgrade_set'))
     <> 'inv_adjust_require=7c95bfe8948fa6c11b8e59bd5ca00094 inv_move_confirm=b0a779155a1ce048cde694237a592b12 inv_move_line_set=a87c4444c12daf622c9470203cf841dc inv_move_now=b44d3489e38188b30ced18a2dc1c2224 inv_post_move=2c58fbb3b7e867b818c7bcf4b0985c21 ref_bin_bgrade_set=593485fbf46435b86690a85531de8000'
     then v_bad := v_bad || ' untouched_changed'; end if;
  if v_bad <> '' then raise exception 'bgr-1b landing check failed:%', v_bad; end if;
end $$;
