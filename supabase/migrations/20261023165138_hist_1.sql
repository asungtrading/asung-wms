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

-- ═══ hist-1 — IMS 이전의 판매 · 발주 기록(읽기 전용) — 표 넷 · 권한 · 적재 창구 둘 (2026-10-23 · 판정 654 B · 656 · 657 · 658 · 659 · 660) ═══
--   뜻: 손님 · 공급처 상세의 이력 카드가 IMS 거래와 함께 보일 「IMS 이전의 판매 · 발주 기록」 · 줄 단위(656) · 주인은 GUID 로 잇는다(657 · customer.cin7_id · supplier.cin7_id) ·
--       Core 시절(2025-11-01 ~)만 · era 칸(658) · 인보이스 된 오더만 · 미래 날짜 거름(659) · 적재는 Apps Script 하나가 창구를 부른다(660)
--   ⚠️ 이 넷은 원장 · 원가 · 잔액 · 크레딧 · 결제 · so · po 와 잇지 않는다(숫자를 맞춰 볼 대상이 아니다 · po-module §11-⓪ 함의 ② 는 「보기 전용 이력」에 한해 고쳤다)
--   ⚠️ 컷오버 때 지우지 않는다(IMS 이전의 기록이다) — 거래 표를 비우는 절차는 표마다의 comment 첫 마디로 가른다 · 새 표 넷 · 권한은 이 파일이 직접(판정 615) · 시퀀스 0

-- ═══ 표 넷 ═══
create table public.hist_so (
  id               uuid primary key default gen_random_uuid(),
  era              text not null default 'core' check (era in ('core')),
  order_number     text not null,
  cin7_customer_id uuid,
  customer_id      uuid references public.customer (id) on delete no action,
  customer_name    text,
  order_date       date,
  invoice_date     date,
  invoice_number   text,
  location         text,
  currency         text,
  sale_total       numeric,
  tax_total        numeric,
  total            numeric,
  line_count       int not null default 0,
  has_return       boolean not null default false,
  source           text not null check (source in ('bq_confirmed', 'bq_current')),
  loaded_at        timestamptz not null default now(),
  constraint hist_so_era_order_key unique (era, order_number)
);
create index hist_so_customer_idx on public.hist_so (customer_id, invoice_date desc, order_number desc);
create index hist_so_cin7_customer_idx on public.hist_so (cin7_customer_id);
comment on table public.hist_so is '⭐ 컷오버 때 지우지 않는다 — IMS 이전의 판매 기록(읽기 전용 · 판정 654 B · 656 ~ 660) · 한 행 = 인보이스 된 지난 판매 오더 하나 · 주인 = cin7_customer_id → customer.cin7_id(못 풀면 customer_id null · 이름 원문은 남는다) · 합은 적재 창구 hist_so_load 가 줄에서 더한다(화면은 더하지 않는다) · 원장 · 원가 · 잔액 · 크레딧 · 결제 · so 와 잇지 않는다 · 쓰기는 창구만';
comment on column public.hist_so.era is '판정 658 — core(2025-11-01 ~) 하나 · 뒤에 omni(이름으로 잇는 길)를 더할 자리';
comment on column public.hist_so.source is '이 오더의 줄을 어느 표에서 받았나 — bq_confirmed(확정 표 · 반품 포함) · bq_current(당월 표의 인보이스 된 것) · 한 오더는 한 출처(판정 659)';

create table public.hist_so_line (
  id           uuid primary key default gen_random_uuid(),
  hist_so_id   uuid not null references public.hist_so (id) on delete cascade,
  seq          int not null,
  doc_type     text check (doc_type in ('invoice', 'credit')),
  doc_number   text,
  doc_date     date,
  sku          text not null,
  product_id   uuid references public.product (id) on delete no action,
  product_name text,
  brand        text,
  quantity     numeric not null,
  unit_price   numeric,
  sale         numeric,
  discount     numeric,
  tax          numeric,
  total        numeric,
  is_return    boolean not null default false,
  constraint hist_so_line_seq_key unique (hist_so_id, seq)
);
create index hist_so_line_product_idx on public.hist_so_line (product_id);
comment on table public.hist_so_line is '⭐ 컷오버 때 지우지 않는다 — IMS 이전의 판매 기록의 줄(인보이스 줄 · 반품 줄 · 판정 656 · 659) · sku 원문 · product_id 는 정확 일치 → upper 일치로 풀린 것(못 풀면 null) · unit_price = sale ÷ quantity(quantity 0 이면 null) · is_return = credit 줄 · 쓰기는 hist_so_load 만(오더의 줄을 지우고 다시 넣는다)';

create table public.hist_po (
  id               uuid primary key default gen_random_uuid(),
  era              text not null default 'core' check (era in ('core')),
  po_number        text not null,
  cin7_supplier_id uuid,
  supplier_id      uuid references public.supplier (id) on delete no action,
  supplier_name    text,
  order_date       date,
  required_by      date,
  received_date    date,
  status           text,
  po_complete      boolean,
  currency         text,
  po_total         numeric,
  line_count       int not null default 0,
  loaded_at        timestamptz not null default now(),
  constraint hist_po_era_po_key unique (era, po_number)
);
create index hist_po_supplier_idx on public.hist_po (supplier_id, order_date desc, po_number desc);
create index hist_po_cin7_supplier_idx on public.hist_po (cin7_supplier_id);
comment on table public.hist_po is '⭐ 컷오버 때 지우지 않는다 — IMS 이전의 발주 기록(읽기 전용 · 판정 654 B · 656 ~ 660) · 한 행 = 지난 발주 하나 · status 는 원문(어느 상태를 보일지는 뒤 판정 · 거르지 않는다) · 주인 = cin7_supplier_id → supplier.cin7_id · po_total 은 원문 · 원장 · 원가 · po 와 잇지 않는다 · 쓰기는 hist_po_load 만';

create table public.hist_po_line (
  id                uuid primary key default gen_random_uuid(),
  hist_po_id        uuid not null references public.hist_po (id) on delete cascade,
  seq               int not null,
  sku               text not null,
  product_id        uuid references public.product (id) on delete no action,
  product_name      text,
  quantity          numeric,
  received_quantity numeric,
  unit_price        numeric,
  line_total        numeric,
  constraint hist_po_line_seq_key unique (hist_po_id, seq)
);
create index hist_po_line_product_idx on public.hist_po_line (product_id);
comment on table public.hist_po_line is '⭐ 컷오버 때 지우지 않는다 — IMS 이전의 발주 기록의 줄(판정 656) · sku 원문 · product_id 는 정확 → upper 로 풀린 것 · 쓰기는 hist_po_load 만';

-- ═══ 권한(판정 615) — 읽기 authenticated(RLS · 카드를 보는 열쇠와 같은 문) · 쓰기는 어느 역할도 표에 직접 못 쓴다(창구만) ═══
alter table public.hist_so enable row level security;
alter table public.hist_so_line enable row level security;
alter table public.hist_po enable row level security;
alter table public.hist_po_line enable row level security;
create policy hist_so_select on public.hist_so for select to authenticated using (public.ims_can_view('sales'));
create policy hist_so_line_select on public.hist_so_line for select to authenticated using (public.ims_can_view('sales'));
create policy hist_po_select on public.hist_po for select to authenticated using (public.ims_can_view('purchasing') or public.ims_can_view('master'));
create policy hist_po_line_select on public.hist_po_line for select to authenticated using (public.ims_can_view('purchasing') or public.ims_can_view('master'));
revoke all on table public.hist_so, public.hist_so_line, public.hist_po, public.hist_po_line from public, anon, authenticated, service_role;
grant select on table public.hist_so, public.hist_so_line, public.hist_po, public.hist_po_line to authenticated;

-- ═══ 적재 창구 ① 판매 ═══
create function public.hist_so_load(p_orders jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
-- hist-1: Apps Script 가 쪽(≤ 500 오더)으로 부른다 · p_orders = [{order_number!, era?, source!, cin7_customer_id?, customer_name?, order_date?, invoice_date?, invoice_number?, location?, currency?,
--   lines!: [{doc_type?(invoice | credit · 'Invoice' · 'Credit note' 도 받는다), doc_number?, doc_date?, sku!, product_name?, brand?, quantity!, sale?, discount?, tax?, total?}]}]
--   ① 풀기 customer.cin7_id · product.sku 정확 → upper ② 거르기 — 줄의 doc_date(없으면 오더 invoice_date)가 ims_today() 뒤면 그 줄을 빼고 셈 · 줄이 하나도 안 남으면 오더도 안 넣음(659) · order_number 가 IMS so.so_number 와 같으면 안 넣음
--   ③ 머리 upsert on (era, order_number) · 줄은 지우고 다시 넣는다(멱등) ④ 합 · line_count · has_return · unit_price 는 여기서 셈 · ⚠️ 원장 · 원가 · so(번호 겹침 읽기 하나) · 크레딧 어느 표도 쓰지 않는다
declare
  v_today date := public.ims_today();
  o jsonb;  v_on text;  v_era text;  v_src text;  v_cid uuid;  v_cust uuid;  v_id uuid;  v_isnew boolean;
  v_inv_date date;  v_inv_no text;  v_n int;
  c_in int := 0;  c_ins int := 0;  c_upd int := 0;  c_fut int := 0;  c_ims int := 0;  l_in int := 0;  l_w int := 0;  l_fut int := 0;  c_unres int := 0;  p_unres int := 0;
begin
  if p_orders is null or jsonb_typeof(p_orders) <> 'array' then raise exception 'p_orders must be a JSON array of orders — nothing was saved'; end if;
  if jsonb_array_length(p_orders) > 500 then raise exception 'Too many orders in one call (% — the limit is 500) — send pages of 500 — nothing was saved', jsonb_array_length(p_orders); end if;
  if to_regclass('pg_temp.hist_so_ld') is null then                                                                        -- 쪽마다 한 번(NOTICE 없이) · 트랜잭션 끝에 사라진다
    create temp table hist_so_ld (seq int, doc_type text, doc_number text, doc_date date, sku text, product_id uuid, product_name text, brand text, quantity numeric, sale numeric, discount numeric, tax numeric, total numeric, fut boolean) on commit drop;
  end if;
  for o in select x from jsonb_array_elements(p_orders) as x loop
    c_in := c_in + 1;
    v_on := nullif(trim(coalesce(o->>'order_number', '')), '');
    if v_on is null then raise exception 'Order % has no order_number — nothing was saved', c_in; end if;
    v_era := coalesce(nullif(trim(o->>'era'), ''), 'core');
    if v_era <> 'core' then raise exception 'Order %: era % is not known (core) — nothing was saved', v_on, v_era; end if;
    v_src := nullif(trim(coalesce(o->>'source', '')), '');
    if v_src is null or v_src not in ('bq_confirmed', 'bq_current') then raise exception 'Order %: source must be bq_confirmed or bq_current — nothing was saved', v_on; end if;
    if jsonb_typeof(o->'lines') <> 'array' or jsonb_array_length(o->'lines') = 0 then raise exception 'Order % has no lines — nothing was saved', v_on; end if;
    l_in := l_in + jsonb_array_length(o->'lines');
    if exists (select 1 from public.so s where s.so_number = v_on) then c_ims := c_ims + 1; continue; end if;    -- IMS 번호와 겹침(실측 0 · 안전장치)
    v_inv_date := nullif(o->>'invoice_date', '')::date;
    -- 줄 펴기 · 풀기 · 미래 거르기
    delete from hist_so_ld;
    insert into hist_so_ld (seq, doc_type, doc_number, doc_date, sku, product_id, product_name, brand, quantity, sale, discount, tax, total, fut)
    select t.o,
           case lower(trim(coalesce(l->>'doc_type', 'invoice'))) when 'credit' then 'credit' when 'credit note' then 'credit' else 'invoice' end,
           nullif(trim(l->>'doc_number'), ''), coalesce(nullif(l->>'doc_date', '')::date, v_inv_date),
           trim(l->>'sku'),
           coalesce((select p.id from public.product p where p.sku = trim(l->>'sku')), (select p.id from public.product p where upper(p.sku) = upper(trim(l->>'sku')) order by p.sku limit 1)),
           nullif(trim(l->>'product_name'), ''), nullif(trim(l->>'brand'), ''),
           nullif(l->>'quantity', '')::numeric, nullif(l->>'sale', '')::numeric, nullif(l->>'discount', '')::numeric, nullif(l->>'tax', '')::numeric, nullif(l->>'total', '')::numeric,
           coalesce(nullif(l->>'doc_date', '')::date, v_inv_date) > v_today
      from jsonb_array_elements(o->'lines') with ordinality as t(l, o);
    if exists (select 1 from hist_so_ld where sku is null or sku = '' or quantity is null) then raise exception 'Order %: every line needs sku and quantity — nothing was saved', v_on; end if;
    select count(*) filter (where fut) into v_n from hist_so_ld;
    l_fut := l_fut + v_n;
    delete from hist_so_ld where fut;
    if not exists (select 1 from hist_so_ld) then c_fut := c_fut + 1; continue; end if;   -- 판정 659: 미래 날짜뿐이면 오더도 안 넣는다
    v_cid := nullif(o->>'cin7_customer_id', '')::uuid;
    v_cust := (select c.id from public.customer c where c.cin7_id = v_cid);
    if v_cust is null then c_unres := c_unres + 1; end if;
    select count(*) into v_n from hist_so_ld where product_id is null;  p_unres := p_unres + v_n;
    if v_inv_date is null then select min(doc_date) into v_inv_date from hist_so_ld where doc_type = 'invoice'; end if;
    v_inv_no := coalesce(nullif(trim(o->>'invoice_number'), ''), (select doc_number from hist_so_ld where doc_type = 'invoice' and doc_number is not null order by seq limit 1));
    -- 머리 upsert
    select h.id into v_id from public.hist_so h where h.era = v_era and h.order_number = v_on;
    v_isnew := v_id is null;
    if v_isnew then
      insert into public.hist_so (era, order_number, cin7_customer_id, customer_id, customer_name, order_date, invoice_date, invoice_number, location, currency, source)
      values (v_era, v_on, v_cid, v_cust, nullif(trim(o->>'customer_name'), ''), nullif(o->>'order_date', '')::date, v_inv_date, v_inv_no, nullif(trim(o->>'location'), ''), nullif(trim(o->>'currency'), ''), v_src)
      returning id into v_id;
      c_ins := c_ins + 1;
    else
      update public.hist_so set cin7_customer_id = v_cid, customer_id = v_cust, customer_name = nullif(trim(o->>'customer_name'), ''), order_date = nullif(o->>'order_date', '')::date, invoice_date = v_inv_date, invoice_number = v_inv_no,
             location = nullif(trim(o->>'location'), ''), currency = nullif(trim(o->>'currency'), ''), source = v_src, loaded_at = now() where id = v_id;
      c_upd := c_upd + 1;
    end if;
    delete from public.hist_so_line where hist_so_id = v_id;
    insert into public.hist_so_line (hist_so_id, seq, doc_type, doc_number, doc_date, sku, product_id, product_name, brand, quantity, unit_price, sale, discount, tax, total, is_return)
    select v_id, seq, doc_type, doc_number, doc_date, sku, product_id, product_name, brand, quantity, case when quantity <> 0 and sale is not null then round(sale / quantity, 6) end, sale, discount, tax, total, doc_type = 'credit'
      from hist_so_ld order by seq;
    get diagnostics v_n = row_count;  l_w := l_w + v_n;
    update public.hist_so h set sale_total = s.sa, tax_total = s.tx, total = s.tt, line_count = s.n, has_return = s.r
      from (select sum(sale) sa, sum(tax) tx, sum(total) tt, count(*) n, bool_or(is_return) r from public.hist_so_line where hist_so_id = v_id) s where h.id = v_id;
  end loop;
  return jsonb_build_object('orders_in', c_in, 'orders_inserted', c_ins, 'orders_updated', c_upd, 'orders_skipped_future', c_fut, 'orders_skipped_ims_number', c_ims,
                            'lines_in', l_in, 'lines_written', l_w, 'lines_skipped_future', l_fut, 'customer_unresolved', c_unres, 'product_unresolved', p_unres);
end $$;
revoke all on function public.hist_so_load(jsonb) from public, anon, authenticated;
grant execute on function public.hist_so_load(jsonb) to service_role;
comment on function public.hist_so_load(jsonb) is 'hist-1 판정 659 · 660 — IMS 이전 판매 기록 적재(service_role · Apps Script 가 쪽 ≤ 500 오더로) · 머리 upsert on (era, order_number) · 줄은 지우고 다시(멱등) · 미래 날짜 줄 · IMS 번호 겹침은 빼고 셈 · 반환 {orders_in, orders_inserted, orders_updated, orders_skipped_future, orders_skipped_ims_number, lines_in, lines_written, lines_skipped_future, customer_unresolved, product_unresolved}';

-- ═══ 적재 창구 ② 발주 ═══
create function public.hist_po_load(p_orders jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
-- hist-1: p_orders = [{po_number!, era?, cin7_supplier_id?, supplier_name?, order_date?, required_by?, received_date?, status?, po_complete?, currency?, po_total?, lines!: [{sku!, product_name?, quantity?, received_quantity?, unit_price?, line_total?}]}]
--   order_date 가 ims_today() 뒤면 오더를 안 넣고 셈(판매의 미래 거름과 같은 규칙 · 줄에는 날짜가 없다) · po_number 가 IMS po.po_number 와 같으면 안 넣음 · status 는 원문 그대로(거르지 않는다)
declare
  v_today date := public.ims_today();
  o jsonb;  v_on text;  v_era text;  v_sid uuid;  v_sup uuid;  v_id uuid;  v_isnew boolean;  v_n int;
  c_in int := 0;  c_ins int := 0;  c_upd int := 0;  c_fut int := 0;  c_ims int := 0;  l_in int := 0;  l_w int := 0;  s_unres int := 0;  p_unres int := 0;
begin
  if p_orders is null or jsonb_typeof(p_orders) <> 'array' then raise exception 'p_orders must be a JSON array of purchase orders — nothing was saved'; end if;
  if jsonb_array_length(p_orders) > 500 then raise exception 'Too many purchase orders in one call (% — the limit is 500) — send pages of 500 — nothing was saved', jsonb_array_length(p_orders); end if;
  for o in select x from jsonb_array_elements(p_orders) as x loop
    c_in := c_in + 1;
    v_on := nullif(trim(coalesce(o->>'po_number', '')), '');
    if v_on is null then raise exception 'Purchase order % has no po_number — nothing was saved', c_in; end if;
    v_era := coalesce(nullif(trim(o->>'era'), ''), 'core');
    if v_era <> 'core' then raise exception 'Purchase order %: era % is not known (core) — nothing was saved', v_on, v_era; end if;
    if jsonb_typeof(o->'lines') <> 'array' or jsonb_array_length(o->'lines') = 0 then raise exception 'Purchase order % has no lines — nothing was saved', v_on; end if;
    if exists (select 1 from jsonb_array_elements(o->'lines') l where nullif(trim(l->>'sku'), '') is null) then raise exception 'Purchase order %: every line needs sku — nothing was saved', v_on; end if;
    l_in := l_in + jsonb_array_length(o->'lines');
    if exists (select 1 from public.po p where p.po_number = v_on) then c_ims := c_ims + 1; continue; end if;
    if nullif(o->>'order_date', '')::date > v_today then c_fut := c_fut + 1; continue; end if;
    v_sid := nullif(o->>'cin7_supplier_id', '')::uuid;
    v_sup := (select s.id from public.supplier s where s.cin7_id = v_sid);
    if v_sup is null then s_unres := s_unres + 1; end if;
    select h.id into v_id from public.hist_po h where h.era = v_era and h.po_number = v_on;
    v_isnew := v_id is null;
    if v_isnew then
      insert into public.hist_po (era, po_number, cin7_supplier_id, supplier_id, supplier_name, order_date, required_by, received_date, status, po_complete, currency, po_total)
      values (v_era, v_on, v_sid, v_sup, nullif(trim(o->>'supplier_name'), ''), nullif(o->>'order_date', '')::date, nullif(o->>'required_by', '')::date, nullif(o->>'received_date', '')::date,
              nullif(trim(o->>'status'), ''), nullif(o->>'po_complete', '')::boolean, nullif(trim(o->>'currency'), ''), nullif(o->>'po_total', '')::numeric)
      returning id into v_id;
      c_ins := c_ins + 1;
    else
      update public.hist_po set cin7_supplier_id = v_sid, supplier_id = v_sup, supplier_name = nullif(trim(o->>'supplier_name'), ''), order_date = nullif(o->>'order_date', '')::date, required_by = nullif(o->>'required_by', '')::date,
             received_date = nullif(o->>'received_date', '')::date, status = nullif(trim(o->>'status'), ''), po_complete = nullif(o->>'po_complete', '')::boolean, currency = nullif(trim(o->>'currency'), ''), po_total = nullif(o->>'po_total', '')::numeric, loaded_at = now()
       where id = v_id;
      c_upd := c_upd + 1;
    end if;
    delete from public.hist_po_line where hist_po_id = v_id;
    insert into public.hist_po_line (hist_po_id, seq, sku, product_id, product_name, quantity, received_quantity, unit_price, line_total)
    select v_id, t.o, trim(l->>'sku'),
           coalesce((select p.id from public.product p where p.sku = trim(l->>'sku')), (select p.id from public.product p where upper(p.sku) = upper(trim(l->>'sku')) order by p.sku limit 1)),
           nullif(trim(l->>'product_name'), ''), nullif(l->>'quantity', '')::numeric, nullif(l->>'received_quantity', '')::numeric, nullif(l->>'unit_price', '')::numeric, nullif(l->>'line_total', '')::numeric
      from jsonb_array_elements(o->'lines') with ordinality as t(l, o);
    get diagnostics v_n = row_count;  l_w := l_w + v_n;
    select count(*) into v_n from public.hist_po_line where hist_po_id = v_id and product_id is null;  p_unres := p_unres + v_n;
    update public.hist_po set line_count = (select count(*) from public.hist_po_line where hist_po_id = v_id) where id = v_id;
  end loop;
  return jsonb_build_object('orders_in', c_in, 'orders_inserted', c_ins, 'orders_updated', c_upd, 'orders_skipped_future', c_fut, 'orders_skipped_ims_number', c_ims,
                            'lines_in', l_in, 'lines_written', l_w, 'supplier_unresolved', s_unres, 'product_unresolved', p_unres);
end $$;
revoke all on function public.hist_po_load(jsonb) from public, anon, authenticated;
grant execute on function public.hist_po_load(jsonb) to service_role;
comment on function public.hist_po_load(jsonb) is 'hist-1 판정 660 — IMS 이전 발주 기록 적재(service_role · Apps Script 가 쪽 ≤ 500 발주로) · 머리 upsert on (era, po_number) · 줄은 지우고 다시(멱등) · 미래 order_date · IMS 번호 겹침은 빼고 셈 · status 원문 · 반환 {orders_in, orders_inserted, orders_updated, orders_skipped_future, orders_skipped_ims_number, lines_in, lines_written, supplier_unresolved, product_unresolved}';

-- ═══ 착지 — 표 넷 · RLS · ACL · 정책 · 창구 권한 · comment 첫 마디 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname in ('hist_so', 'hist_so_line', 'hist_po', 'hist_po_line') and c.relrowsecurity) <> 4 then v_bad := v_bad || ' rls'; end if;
  if (select string_agg(c.relname || '=' || c.relacl::text, ' ' order by c.relname) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('hist_so', 'hist_so_line', 'hist_po', 'hist_po_line'))
     <> 'hist_po={postgres=arwdDxtm/postgres,authenticated=r/postgres} hist_po_line={postgres=arwdDxtm/postgres,authenticated=r/postgres} hist_so={postgres=arwdDxtm/postgres,authenticated=r/postgres} hist_so_line={postgres=arwdDxtm/postgres,authenticated=r/postgres}' then v_bad := v_bad || ' table_acl'; end if;
  if (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid where c.relname in ('hist_so', 'hist_so_line', 'hist_po', 'hist_po_line') and p.polcmd = 'r') <> 4 then v_bad := v_bad || ' policies'; end if;
  if (select string_agg(p.proname || '=' || p.proacl::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('hist_so_load', 'hist_po_load'))
     <> 'hist_po_load={postgres=X/postgres,service_role=X/postgres} hist_so_load={postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' fn_acl'; end if;
  if (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('hist_so', 'hist_so_line', 'hist_po', 'hist_po_line') and obj_description(c.oid, 'pg_class') like '⭐ 컷오버 때 지우지 않는다%') <> 4 then v_bad := v_bad || ' comments'; end if;
  if v_bad <> '' then raise exception 'hist-1 landing check failed:%', v_bad; end if;
end $$;
