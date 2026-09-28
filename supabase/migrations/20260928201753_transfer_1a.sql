-- ─────────────────────────────────────────────────────────────
-- 재고 사건 ② 트랜스퍼 · 둘째 몫 「창고 간」 ① — 문서 · 번호 · 열쇠 · 창고 표 칸 · 공용 목록 · 가용 (Asung-IMS · tr-1a · 2026-09-28)
--   정본(뒤에 적는다): so-module §27(판정 64~71 · 묶음 열) · 조사 trf-2 · trf-3(b3)
--   든 것: ① inv_transfer · inv_transfer_line · inv_transfer_number_seq · inv_transfer_next_number ② 문 inv_transfer_require(ims_require_write(transfer) + ims_can_warehouse 둘 중 하나)
--         ③ 문서 창구 create · line_set · line_remove · delete · shortage · confirm(가용 확인 · 묶음 3) · unconfirm · cancel · list · detail
--         ④ 창고 작업 표 열한 개에 transfer_id / transfer_line_id · CHECK 「정확히 하나」 또는 「많아야 하나」 · 인덱스 · order_finalize · order_review 기본키 풀고 보통 유니크 둘씩(규칙 29 · 부분 유니크 없음)
--         ⑤ 공용 목록 뷰 둘 wms_order_doc · wms_order_doc_line(security_invoker · ② 차수가 읽는다)
--         ⑥ 재발행 둘 — so_available_many(20260924015859:16~48 · 더한 CTE 하나 · 바뀐 줄 2 · 트랜스퍼 예약이 0 이면 반환 같음) · ims_perm_catalog(20260928182712:488~510 · 더한 줄 1 · 바뀐 줄 1)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 판매 표 · 행 무접촉 · 창고 · 판매 창구 무접촉(so_available_many 만) · IMS 안에서만 선다(판정 51 · 60)
-- ─────────────────────────────────────────────────────────────
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

-- ═══ 1) 문서 표 · 시퀀스 · 채번 (묶음 아홉 · TRF-00001 · inv_move 선례 20260928182712) ═══
create sequence public.inv_transfer_number_seq start with 1 increment by 1;
create function public.inv_transfer_next_number() returns text
  language sql volatile
  set search_path = public, pg_temp
as $$
  select 'TRF-' || lpad(nextval('public.inv_transfer_number_seq')::text, 5, '0');
$$;
comment on function public.inv_transfer_next_number() is '창고 간 트랜스퍼 번호 채번 — TRF- + 다섯 자리(inv_transfer_number_seq · 1 부터 · 지운 초안의 번호는 빈다 · 판정 55). 2026-09-28';
revoke all on sequence public.inv_transfer_number_seq from public, anon;
grant usage, select on sequence public.inv_transfer_number_seq to authenticated;
revoke all on function public.inv_transfer_next_number() from public, anon;
grant execute on function public.inv_transfer_next_number() to authenticated;

create table public.inv_transfer (
  id                 uuid primary key default gen_random_uuid(),
  transfer_number    text not null unique default public.inv_transfer_next_number(),
  status             text not null default 'draft',                                     -- 묶음 4 — draft → confirmed → at_wms → picking → in_transit → receiving → received · cancelled 은 창고로 보내기 전까지만
  from_warehouse_id  uuid not null references public.ref_warehouse (id) on delete no action,
  to_warehouse_id    uuid not null references public.ref_warehouse (id) on delete no action,
  note               text,
  created_by         uuid references public.ims_staff (id) on delete no action,
  confirmed_by       uuid references public.ims_staff (id) on delete no action,
  confirmed_at       timestamptz,
  at_wms_at          timestamptz,                                                       -- ② 차수(창고로 보내기)가 채운다 — 뷰 wms_order_doc 가 판매 오더의 같은 칸과 나란히 비춘다
  at_wms_by          uuid references public.ims_staff (id) on delete no action,
  picking_at         timestamptz,
  picking_by         uuid references public.ims_staff (id) on delete no action,
  departed_at        timestamptz,                                                       -- ③ 차수(창고 마무리 = 출발 · 판정 65)
  departed_by        uuid references public.ims_staff (id) on delete no action,
  receiving_at       timestamptz,                                                       -- ④ 차수(도착 창고가 세기 시작)
  received_at        timestamptz,                                                       -- ④ 차수(도착 창고 Complete · 판정 70)
  received_by        uuid references public.ims_staff (id) on delete no action,
  cancelled_by       uuid references public.ims_staff (id) on delete no action,
  cancelled_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  updated_by         uuid references public.ims_staff (id) on delete no action,
  constraint inv_transfer_status_ck     check (status in ('draft', 'confirmed', 'at_wms', 'picking', 'in_transit', 'receiving', 'received', 'cancelled')),
  constraint inv_transfer_warehouses_ck check (from_warehouse_id <> to_warehouse_id),
  constraint inv_transfer_confirm_ck    check ((status = 'draft') = (confirmed_at is null) or status = 'cancelled'),
  constraint inv_transfer_cancel_ck     check ((status = 'cancelled') = (cancelled_at is not null))
);
create table public.inv_transfer_line (
  id            uuid primary key default gen_random_uuid(),
  transfer_id   uuid not null references public.inv_transfer (id) on delete cascade,
  line_no       int  not null,
  product_id    uuid not null references public.product (id) on delete no action,        -- 낱개 · 세트 둘 다(묶음 1)
  sku           text not null,
  qty           numeric not null,                                                        -- 그 제품의 단위 수(so_line.qty_ordered 와 같은 뜻) · 낱개 EA = qty × pack_factor
  pack_factor   numeric not null default 1,                                              -- 제품의 pack_factor 를 적을 때 굳힌다(so_line 과 같은 셋 · 픽 · 팩 화면이 그대로 환산)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,
  constraint inv_transfer_line_qty_ck     check (qty > 0),
  constraint inv_transfer_line_factor_ck  check (pack_factor > 0),
  constraint inv_transfer_line_product_uq unique (transfer_id, product_id),              -- 같은 제품 두 줄 금지(B)
  constraint inv_transfer_line_no_uq      unique (transfer_id, line_no)
);
create index inv_transfer_from_idx on public.inv_transfer (from_warehouse_id, status);
create index inv_transfer_to_idx   on public.inv_transfer (to_warehouse_id, status);
create index inv_transfer_line_transfer_idx on public.inv_transfer_line (transfer_id);
create trigger inv_transfer_touch      before update on public.inv_transfer      for each row execute function public.ims_touch();
create trigger inv_transfer_line_touch before update on public.inv_transfer_line for each row execute function public.ims_touch();
alter table public.inv_transfer      enable row level security;
alter table public.inv_transfer_line enable row level security;
create policy inv_transfer_select      on public.inv_transfer      for select to authenticated using (public.ims_can_view('transfer'));
create policy inv_transfer_line_select on public.inv_transfer_line for select to authenticated using (public.ims_can_view('transfer'));
comment on table public.inv_transfer is '창고 간 트랜스퍼 문서(재고 사건 ② 둘째 몫 · 판정 64~71 · 묶음 열 · 2026-09-28) — 출발 창고 → 도착 창고 · 상태 여덟(묶음 4) · 확정된 문서의 줄이 곧 출발 창고 예약(묶음 2 · so_available_many) · 창고로 보내기 ② · 출발 원장 ③ · 도착 · 운송 중 정리 ④ · 운임 ⑤ · 쓰기는 창구(inv_transfer_*)로만 · 읽기 정책 ims_can_view(transfer)';
comment on table public.inv_transfer_line is '트랜스퍼 줄 — so_line 과 같은 셋(product_id · qty · pack_factor · 묶음 1) · 낱개 EA = qty × pack_factor · 같은 제품 두 줄 금지 · 확정 뒤에는 unconfirm 해야 고친다';
comment on column public.inv_transfer.status is 'draft → confirmed(예약) → at_wms(② 창고로 보내기) → picking → in_transit(③ 창고 마무리 = 출발) → receiving(④ 세기 시작) → received(④ Complete) · cancelled 은 at_wms 전까지만(묶음 4 · 5)';

-- ═══ 2) 권한 — 묶음 아홉 8 (표준 문 · 창고 둘 중 하나 · 별도 ims_can_* 없음 · 카탈로그는 7) 재발행) ═══
create function public.inv_transfer_require(p_from_warehouse_id uuid, p_to_warehouse_id uuid) returns uuid
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  perform public.ims_require_write('transfer', 'saved');                                  -- ⭐ 첫 줄 문 — admin · supervisor 역할로 · 그 밖은 사람마다 켠 transfer
  if not (public.ims_can_warehouse(p_from_warehouse_id) or public.ims_can_warehouse(p_to_warehouse_id)) then
    raise exception 'This transfer is between warehouses you are not set up for — nothing was saved';
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  return v_staff;
end;
$$;
revoke all on function public.inv_transfer_require(uuid, uuid) from public, anon, authenticated;

-- ═══ 3) 문서 창구 (B) — definer · 첫 줄 문 · 창고로 보내기 · 거둬들이기는 ② 차수 ═══
create function public.inv_transfer_create(p_from_warehouse_id uuid, p_to_warehouse_id uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_f public.ref_warehouse%rowtype; v_t public.ref_warehouse%rowtype; v_x public.inv_transfer%rowtype;
begin
  if p_from_warehouse_id is null or p_to_warehouse_id is null then raise exception 'A transfer needs a from warehouse and a to warehouse — nothing was saved'; end if;
  if p_from_warehouse_id = p_to_warehouse_id then raise exception 'From and to are the same warehouse — use Bin Moves inside one warehouse — nothing was saved'; end if;
  v_staff := public.inv_transfer_require(p_from_warehouse_id, p_to_warehouse_id);        -- ⭐ 첫 줄
  select * into v_f from public.ref_warehouse w where w.id = p_from_warehouse_id and w.is_active;
  if not found then raise exception 'From warehouse not found or inactive — nothing was saved'; end if;
  select * into v_t from public.ref_warehouse w where w.id = p_to_warehouse_id and w.is_active;
  if not found then raise exception 'To warehouse not found or inactive — nothing was saved'; end if;
  insert into public.inv_transfer (from_warehouse_id, to_warehouse_id, note, created_by, updated_by)
  values (v_f.id, v_t.id, nullif(trim(p_note), ''), v_staff, v_staff) returning * into v_x;
  return jsonb_build_object('id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', v_x.status,
                            'from_warehouse_id', v_f.id, 'from_warehouse', v_f.name, 'to_warehouse_id', v_t.id, 'to_warehouse', v_t.name);
end;
$$;

-- 줄 넣기 · 고치기 — p_line {line_id?, product_id?|sku?, qty} · pack_factor 는 제품에서 굳힌다 · 같은 제품 두 줄 거부 · 초안에서만
create function public.inv_transfer_line_set(p_transfer_id uuid, p_line jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_x public.inv_transfer%rowtype; v_p public.product%rowtype; v_l public.inv_transfer_line%rowtype; v_qty numeric; v_id uuid; v_no int; v_pf numeric;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  perform public.inv_transfer_require(v_x.from_warehouse_id, v_x.to_warehouse_id);       -- ⭐ 첫 줄 문(문서의 창고 둘)
  if v_x.status <> 'draft' then raise exception 'Transfer % is % — only a draft can be edited (unconfirm it first) — nothing was saved', v_x.transfer_number, v_x.status; end if;
  if p_line is null or jsonb_typeof(p_line) <> 'object' then raise exception 'p_line must be a JSON object — nothing was saved'; end if;
  if nullif(p_line->>'product_id', '') is not null then select * into v_p from public.product p where p.id = (p_line->>'product_id')::uuid;
  else select * into v_p from public.product p where p.sku = trim(p_line->>'sku'); end if;
  if not found then raise exception 'Product not found (%) — nothing was saved', coalesce(p_line->>'sku', p_line->>'product_id'); end if;
  if not v_p.is_active then raise exception 'Product % is inactive — nothing was saved', v_p.sku; end if;
  if nullif(p_line->>'qty', '') is null or (p_line->>'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then raise exception 'qty must be a positive number — nothing was saved'; end if;
  v_qty := (p_line->>'qty')::numeric;
  if v_qty <= 0 then raise exception 'qty must be more than 0 — nothing was saved'; end if;
  v_pf := coalesce(nullif(v_p.pack_factor, 0), 1);
  v_id := nullif(p_line->>'line_id', '')::uuid;
  if v_id is not null and not exists (select 1 from public.inv_transfer_line l where l.id = v_id and l.transfer_id = p_transfer_id) then
    raise exception 'Line not found on this transfer — nothing was saved';
  end if;
  if exists (select 1 from public.inv_transfer_line l where l.transfer_id = p_transfer_id and l.product_id = v_p.id and l.id is distinct from v_id) then
    raise exception 'Transfer % already has a line for % — change that line instead — nothing was saved', v_x.transfer_number, v_p.sku;
  end if;
  if v_id is not null then
    update public.inv_transfer_line l set product_id = v_p.id, sku = v_p.sku, qty = v_qty, pack_factor = v_pf where l.id = v_id returning * into v_l;
  else
    select coalesce(max(l.line_no), 0) + 1 into v_no from public.inv_transfer_line l where l.transfer_id = p_transfer_id;
    insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (p_transfer_id, v_no, v_p.id, v_p.sku, v_qty, v_pf) returning * into v_l;
  end if;
  return jsonb_build_object('transfer_id', p_transfer_id, 'line_id', v_l.id, 'line_no', v_l.line_no, 'product_id', v_l.product_id, 'sku', v_l.sku, 'product_name', v_p.name,
                            'qty', v_l.qty, 'pack_factor', v_l.pack_factor, 'qty_ea', v_l.qty * v_l.pack_factor);
end;
$$;

create function public.inv_transfer_line_remove(p_transfer_id uuid, p_line_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_x public.inv_transfer%rowtype; v_n int;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  perform public.inv_transfer_require(v_x.from_warehouse_id, v_x.to_warehouse_id);
  if v_x.status <> 'draft' then raise exception 'Transfer % is % — only a draft can be edited (unconfirm it first) — nothing was saved', v_x.transfer_number, v_x.status; end if;
  delete from public.inv_transfer_line where id = p_line_id and transfer_id = p_transfer_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Line not found on this transfer — nothing was saved'; end if;
  return jsonb_build_object('transfer_id', p_transfer_id, 'removed', p_line_id);
end;
$$;

create function public.inv_transfer_delete(p_transfer_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_x public.inv_transfer%rowtype;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  perform public.inv_transfer_require(v_x.from_warehouse_id, v_x.to_warehouse_id);
  if v_x.status <> 'draft' then raise exception 'Transfer % is % — only a draft can be deleted (cancel it instead) — nothing was saved', v_x.transfer_number, v_x.status; end if;
  delete from public.inv_transfer where id = p_transfer_id;                              -- 줄은 cascade · 번호는 빈다(판정 55)
  return jsonb_build_object('deleted', v_x.transfer_number);
end;
$$;

-- 가용 검사 조각 — 줄을 낱개 제품으로 접어(세트는 parent) 출발 창고 가용(so_available_many · 판매 예약 + 다른 트랜스퍼 예약을 뺀 값)과 견준다 · 이 문서 자신은 draft 라 아직 안 잡힌다
create function public.inv_transfer_shortage(p_transfer_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with x as (select t.from_warehouse_id from public.inv_transfer t where t.id = p_transfer_id),
  need as (
    select coalesce(p.parent_product_id, p.id) as stock_pid, min(sp.sku) as stock_sku, sum(l.qty * l.pack_factor) as need_ea
      from public.inv_transfer_line l join public.product p on p.id = l.product_id
      left join public.product sp on sp.id = coalesce(p.parent_product_id, p.id)
     where l.transfer_id = p_transfer_id group by 1
  ),
  av as (select m.* from public.so_available_many((select array_agg(stock_pid) from need), (select from_warehouse_id from x)) m)
  select coalesce(jsonb_agg(jsonb_build_object('stock_product_id', n.stock_pid, 'sku', n.stock_sku, 'need_ea', n.need_ea, 'available_ea', coalesce(av.available_ea, 0)) order by n.stock_sku)
                  filter (where n.need_ea > coalesce(av.available_ea, 0)), '[]'::jsonb)
    from need n left join av on av.stock_pid = n.stock_pid;
$$;
revoke all on function public.inv_transfer_shortage(uuid) from public, anon;   grant execute on function public.inv_transfer_shortage(uuid) to authenticated;

create function public.inv_transfer_confirm(p_transfer_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_x public.inv_transfer%rowtype; v_staff uuid; v_short jsonb; v_lines int;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  v_staff := public.inv_transfer_require(v_x.from_warehouse_id, v_x.to_warehouse_id);   -- ⭐ 첫 줄 문
  if v_x.status <> 'draft' then raise exception 'Transfer % is already % — nothing was saved', v_x.transfer_number, v_x.status; end if;
  select count(*) into v_lines from public.inv_transfer_line l where l.transfer_id = p_transfer_id;
  if v_lines = 0 then raise exception 'Transfer % has no lines — nothing was saved', v_x.transfer_number; end if;
  v_short := public.inv_transfer_shortage(p_transfer_id);                                -- 묶음 3 — 모자라면 거부(백오더 없음 · 수량을 줄여 다시)
  if jsonb_array_length(v_short) > 0 then
    raise exception 'Transfer % cannot be confirmed — not enough available at the from warehouse: % — reduce the quantity and try again — nothing was saved', v_x.transfer_number,
      (select string_agg(format('%s needs %s, available %s', e->>'sku', e->>'need_ea', e->>'available_ea'), '; ') from jsonb_array_elements(v_short) e);
  end if;
  update public.inv_transfer set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now(), updated_by = v_staff where id = p_transfer_id;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', 'confirmed', 'lines', v_lines, 'from_warehouse_id', v_x.from_warehouse_id, 'to_warehouse_id', v_x.to_warehouse_id);
end;
$$;

create function public.inv_transfer_unconfirm(p_transfer_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_x public.inv_transfer%rowtype; v_staff uuid;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  v_staff := public.inv_transfer_require(v_x.from_warehouse_id, v_x.to_warehouse_id);
  if v_x.status <> 'confirmed' then raise exception 'Transfer % is % — only a confirmed transfer that has not gone to the warehouse can go back to draft — nothing was saved', v_x.transfer_number, v_x.status; end if;
  update public.inv_transfer set status = 'draft', confirmed_by = null, confirmed_at = null, updated_by = v_staff where id = p_transfer_id;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', 'draft');
end;
$$;

create function public.inv_transfer_cancel(p_transfer_id uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_x public.inv_transfer%rowtype; v_staff uuid;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  v_staff := public.inv_transfer_require(v_x.from_warehouse_id, v_x.to_warehouse_id);
  if v_x.status not in ('draft', 'confirmed') then raise exception 'Transfer % is % — once it has gone to the warehouse it cannot be cancelled (recall it first; after it has left, use the in-transit settlement) — nothing was saved', v_x.transfer_number, v_x.status; end if;
  update public.inv_transfer set status = 'cancelled', cancelled_by = v_staff, cancelled_at = now(), updated_by = v_staff,
         note = case when nullif(trim(p_note), '') is null then note else coalesce(note || ' · ', '') || trim(p_note) end
   where id = p_transfer_id;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', 'cancelled', 'was', v_x.status);
end;
$$;

create function public.inv_transfer_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_view('transfer') then null::jsonb else
  coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from (
    select x.id, x.transfer_number, x.status, x.from_warehouse_id, fw.name as from_warehouse, x.to_warehouse_id, tw.name as to_warehouse, x.note,
           x.created_at, x.confirmed_at, x.at_wms_at, x.departed_at, x.received_at, x.cancelled_at,
           cb.name as created_by_name, fb.name as confirmed_by_name,
           (select count(*) from public.inv_transfer_line l where l.transfer_id = x.id) as line_count,
           (select coalesce(sum(l.qty * l.pack_factor), 0) from public.inv_transfer_line l where l.transfer_id = x.id) as qty_ea
      from public.inv_transfer x
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id
      join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      left join public.ims_staff cb on cb.id = x.created_by
      left join public.ims_staff fb on fb.id = x.confirmed_by
     where (nullif(p_filters->>'status', '') is null or x.status = p_filters->>'status')
       and (nullif(p_filters->>'from_warehouse_id', '') is null or x.from_warehouse_id = (p_filters->>'from_warehouse_id')::uuid)
       and (nullif(p_filters->>'to_warehouse_id', '') is null or x.to_warehouse_id = (p_filters->>'to_warehouse_id')::uuid)
       and (nullif(p_filters->>'q', '') is null or x.transfer_number ilike '%' || (p_filters->>'q') || '%' or x.note ilike '%' || (p_filters->>'q') || '%'
            or exists (select 1 from public.inv_transfer_line l where l.transfer_id = x.id and l.sku ilike '%' || (p_filters->>'q') || '%'))
       and (nullif(p_filters->>'from', '') is null or x.created_at >= (p_filters->>'from')::date)
       and (nullif(p_filters->>'to', '') is null or x.created_at < (p_filters->>'to')::date + 1)
     order by x.created_at desc limit coalesce(nullif(p_filters->>'limit', '')::int, 300)) t), '[]'::jsonb) end;
$$;

create function public.inv_transfer_detail(p_transfer_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_view('transfer') then null::jsonb else (
    select jsonb_build_object(
      'header', to_jsonb(x) || jsonb_build_object('from_warehouse', fw.name, 'to_warehouse', tw.name, 'created_by_name', cb.name, 'confirmed_by_name', fb.name),
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', p.name, 'qty', l.qty, 'pack_factor', l.pack_factor,
                                                              'qty_ea', l.qty * l.pack_factor, 'stock_product_id', coalesce(p.parent_product_id, p.id)) order by l.line_no), '[]'::jsonb)
                  from public.inv_transfer_line l join public.product p on p.id = l.product_id where l.transfer_id = x.id),
      'shortage', case when x.status = 'draft' then public.inv_transfer_shortage(x.id) else '[]'::jsonb end)
      from public.inv_transfer x
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      left join public.ims_staff cb on cb.id = x.created_by left join public.ims_staff fb on fb.id = x.confirmed_by
     where x.id = p_transfer_id) end;
$$;
revoke all on function public.inv_transfer_create(uuid, uuid, text) from public, anon;   grant execute on function public.inv_transfer_create(uuid, uuid, text) to authenticated;
revoke all on function public.inv_transfer_line_set(uuid, jsonb) from public, anon;      grant execute on function public.inv_transfer_line_set(uuid, jsonb) to authenticated;
revoke all on function public.inv_transfer_line_remove(uuid, uuid) from public, anon;    grant execute on function public.inv_transfer_line_remove(uuid, uuid) to authenticated;
revoke all on function public.inv_transfer_delete(uuid) from public, anon;               grant execute on function public.inv_transfer_delete(uuid) to authenticated;
revoke all on function public.inv_transfer_confirm(uuid) from public, anon;              grant execute on function public.inv_transfer_confirm(uuid) to authenticated;
revoke all on function public.inv_transfer_unconfirm(uuid) from public, anon;            grant execute on function public.inv_transfer_unconfirm(uuid) to authenticated;
revoke all on function public.inv_transfer_cancel(uuid, text) from public, anon;         grant execute on function public.inv_transfer_cancel(uuid, text) to authenticated;
revoke all on function public.inv_transfer_list(jsonb) from public, anon;                grant execute on function public.inv_transfer_list(jsonb) to authenticated;
revoke all on function public.inv_transfer_detail(uuid) from public, anon;               grant execute on function public.inv_transfer_detail(uuid) to authenticated;
comment on function public.inv_transfer_confirm(uuid) is '확정 = 출발 창고 예약(묶음 2 · 3) — 줄을 낱개로 접어 so_available_many(판매 예약 + 다른 트랜스퍼 예약을 뺀 가용)과 견주고 모자라면 사람 문장으로 거부 · 확정된 줄은 그 순간부터 가용에서 빠진다(so_available_many 재발행) · 창고로 보내기는 ② 차수';

-- ═══ 4) 창고 작업 표 — 판매 칸 옆에 트랜스퍼 칸 (판정 71 b3 · 칸 둘 · 둘 중 하나) ═══
--   규칙(실측 trf-3 · tr-1a N1 — 기존 행 총 37 · null 0 · 모두 판매 칸이 찬 행):
--   「정확히 하나」 = 지금 order_id/order_line_id 가 not null 인 표(pick_tasks · pick_task_lines · pack_tasks · pack_task_lines · worker_mistakes · order_finalize · order_review)
--   「많아야 하나」 = 지금도 빈 행이 있을 수 있는 표(reports — 입고 신고는 둘 다 빈다 · rollback_log · rollback_archive(FK 없음 · 기록) · pallets · pallet_items(자식 팔렛 · 둘 다 빌 수 있다))
--   order_number 글자 칸(reports · rollback_log · rollback_archive · worker_mistakes)은 「문서 번호」로 뜻만 넓힌다(SO- 또는 TRF-) · 이름은 그대로(화면 · 창구 무접촉)
alter table public.wms_pick_tasks       alter column order_id drop not null,       add column transfer_id uuid references public.inv_transfer (id) on delete restrict,
  add constraint wms_pick_tasks_doc_ck       check ((order_id is not null)::int + (transfer_id is not null)::int = 1);
alter table public.wms_pick_task_lines  alter column order_line_id drop not null,  add column transfer_line_id uuid references public.inv_transfer_line (id) on delete restrict,
  add constraint wms_pick_task_lines_doc_ck  check ((order_line_id is not null)::int + (transfer_line_id is not null)::int = 1);
alter table public.wms_pack_tasks       alter column order_id drop not null,       add column transfer_id uuid references public.inv_transfer (id) on delete restrict,
  add constraint wms_pack_tasks_doc_ck       check ((order_id is not null)::int + (transfer_id is not null)::int = 1);
alter table public.wms_pack_task_lines  alter column order_line_id drop not null,  add column transfer_line_id uuid references public.inv_transfer_line (id) on delete restrict,
  add constraint wms_pack_task_lines_doc_ck  check ((order_line_id is not null)::int + (transfer_line_id is not null)::int = 1);
alter table public.wms_worker_mistakes  alter column order_id drop not null,       add column transfer_id uuid references public.inv_transfer (id) on delete restrict,
  add constraint wms_worker_mistakes_doc_ck  check ((order_id is not null)::int + (transfer_id is not null)::int = 1);
alter table public.wms_pallets          add column transfer_id uuid references public.inv_transfer (id) on delete restrict,
  add constraint wms_pallets_doc_ck          check ((order_id is not null)::int + (transfer_id is not null)::int <= 1);
alter table public.wms_pallet_items     add column transfer_id uuid references public.inv_transfer (id) on delete restrict, add column transfer_line_id uuid references public.inv_transfer_line (id) on delete restrict,
  add constraint wms_pallet_items_doc_ck     check ((order_id is not null)::int + (transfer_id is not null)::int <= 1 and (order_line_id is not null)::int + (transfer_line_id is not null)::int <= 1);
alter table public.wms_reports          add column transfer_id uuid references public.inv_transfer (id) on delete set null,
  add constraint wms_reports_doc_ck          check ((order_id is not null)::int + (transfer_id is not null)::int <= 1);
alter table public.wms_rollback_log     add column transfer_id uuid references public.inv_transfer (id) on delete set null,
  add constraint wms_rollback_log_doc_ck     check ((order_id is not null)::int + (transfer_id is not null)::int <= 1);
alter table public.wms_rollback_archive add column transfer_id uuid,                                                                     -- 기록 표 · order_id 도 FK 없음 — 같게
  add constraint wms_rollback_archive_doc_ck check ((order_id is not null)::int + (transfer_id is not null)::int <= 1);
-- order_finalize · order_review 는 order_id 가 기본키였다 — 기본키를 풀고 문서마다 하나 = 보통 유니크 둘(unique(order_id) · unique(transfer_id) · NULLS DISTINCT 기본) + 「정확히 하나」 CHECK
--   ⚠️ 규칙 29 — 부분 유니크 인덱스는 쓰지 않는다(PostgREST on_conflict · insert … on conflict (order_id) 의 중재자가 못 된다 · 입고 차이 실사고) · wms_review_set 의 on conflict (order_id) 가 unique(order_id) 와 짝이 된다
alter table public.wms_order_finalize drop constraint wms_order_finalize_pkey, alter column order_id drop not null,
  add column transfer_id uuid references public.inv_transfer (id) on delete restrict,
  add constraint wms_order_finalize_doc_ck check ((order_id is not null)::int + (transfer_id is not null)::int = 1),
  add constraint wms_order_finalize_order_uq unique (order_id), add constraint wms_order_finalize_transfer_uq unique (transfer_id);
alter table public.wms_order_review drop constraint wms_order_review_pkey, alter column order_id drop not null,
  add column transfer_id uuid references public.inv_transfer (id) on delete restrict,
  add constraint wms_order_review_doc_ck check ((order_id is not null)::int + (transfer_id is not null)::int = 1),
  add constraint wms_order_review_order_uq unique (order_id), add constraint wms_order_review_transfer_uq unique (transfer_id);
create index idx_picktasks_transfer      on public.wms_pick_tasks (transfer_id)           where transfer_id is not null;
create index idx_pticklines_transferline on public.wms_pick_task_lines (transfer_line_id) where transfer_line_id is not null;
create index idx_packtasks_transfer      on public.wms_pack_tasks (transfer_id)           where transfer_id is not null;
create index idx_packlines_transferline  on public.wms_pack_task_lines (transfer_line_id) where transfer_line_id is not null;
create index idx_mistakes_transfer       on public.wms_worker_mistakes (transfer_id)      where transfer_id is not null;
create index idx_pallets_transfer        on public.wms_pallets (transfer_id)              where transfer_id is not null;
create index idx_pallet_items_transfer   on public.wms_pallet_items (transfer_id)         where transfer_id is not null;
create index idx_reports_transfer        on public.wms_reports (transfer_id)              where transfer_id is not null;
create index idx_rollback_transfer       on public.wms_rollback_log (transfer_id)         where transfer_id is not null;
create index idx_rb_archive_transfer     on public.wms_rollback_archive (transfer_id)     where transfer_id is not null;
comment on column public.wms_pick_tasks.transfer_id is '판정 71 — 이 과제가 트랜스퍼 것이면 그 문서(order_id 와 둘 중 정확히 하나) · 창고 창구는 ② 부터 공용 목록 wms_order_doc 로 읽는다';
comment on column public.wms_reports.order_number is '문서 번호(SO- 또는 TRF- · 판정 71 뜻 넓힘 · 이름은 그대로) · 입고 신고는 비고 receipt_id · po_number';
comment on column public.wms_worker_mistakes.order_number is '문서 번호(SO- 또는 TRF- · 판정 71 뜻 넓힘 · 이름은 그대로)';
comment on column public.wms_rollback_log.order_number is '문서 번호(SO- 또는 TRF- · 판정 71 뜻 넓힘 · 이름은 그대로)';
comment on column public.wms_rollback_archive.order_number is '문서 번호(SO- 또는 TRF- · 판정 71 뜻 넓힘 · 이름은 그대로)';

-- ═══ 5) 공용 목록 둘 (D · 판정 71 b3) — 창고 창구가 ② 부터 「join so」 대신 읽는 한 모양 · 판매는 so 원문 그대로 · 트랜스퍼는 같은 칸 이름으로 비춘다 ═══
--   칸 = ② 조사(trf-2 K1 · trf-3 K1)에서 창구가 so 에서 읽던 것 전수: so_number · status · location_id · location_name · customer(name) · channel · at_wms_at · picking_at · packed_at · created_at · comments · ref
--   wms_stage = 창고가 보는 단계 한 어휘: before_wms(draft · confirmed) · at_wms · picking · done(판매 packed 부터 · 트랜스퍼 in_transit 부터) · cancelled
create view public.wms_order_doc with (security_invoker = true) as
  select 'so'::text as doc_kind, s.id as doc_id, s.so_number as doc_number, s.status, s.channel,
         case when s.status in ('draft', 'confirmed') then 'before_wms' when s.status = 'at_wms' then 'at_wms' when s.status = 'picking' then 'picking'
              when s.status = 'cancelled' then 'cancelled' else 'done' end as wms_stage,
         s.location_id as warehouse_id, s.location_name as warehouse_name, null::uuid as dest_warehouse_id, null::text as dest_warehouse_name,
         s.customer_id as party_id, c.name as party_name, s.at_wms_at, s.picking_at, s.packed_at as done_at, s.created_at, s.comments, s.ref
    from public.so s left join public.customer c on c.id = s.customer_id
  union all
  select 'transfer', t.id, t.transfer_number, t.status, 'transfer',
         case when t.status in ('draft', 'confirmed') then 'before_wms' when t.status = 'at_wms' then 'at_wms' when t.status = 'picking' then 'picking'
              when t.status = 'cancelled' then 'cancelled' else 'done' end,
         t.from_warehouse_id, fw.name, t.to_warehouse_id, tw.name,
         t.to_warehouse_id, tw.name, t.at_wms_at, t.picking_at, t.departed_at, t.created_at, t.note, null::text
    from public.inv_transfer t join public.ref_warehouse fw on fw.id = t.from_warehouse_id join public.ref_warehouse tw on tw.id = t.to_warehouse_id;
create view public.wms_order_doc_line with (security_invoker = true) as
  select 'so'::text as doc_kind, l.so_id as doc_id, l.id as line_id, l.line_no, l.product_id, l.sku, l.product_name, l.pack_factor,
         l.qty_ordered - l.qty_removed as qty_target, (l.qty_ordered - l.qty_removed) * l.pack_factor as qty_target_ea, coalesce(p.parent_product_id, p.id) as stock_product_id
    from public.so_line l join public.product p on p.id = l.product_id
  union all
  select 'transfer', l.transfer_id, l.id, l.line_no, l.product_id, l.sku, p.name, l.pack_factor, l.qty, l.qty * l.pack_factor, coalesce(p.parent_product_id, p.id)
    from public.inv_transfer_line l join public.product p on p.id = l.product_id;
grant select on public.wms_order_doc, public.wms_order_doc_line to authenticated;
comment on view public.wms_order_doc is '⭐ 공용 목록(판정 71 b3) — 창고 창구가 보는 문서 한 모양: 판매 오더(so · 손님 이름 · 원문 그대로) union all 트랜스퍼(inv_transfer · party = 도착 창고 · 같은 칸 이름) · doc_id 로 한 줄 읽기(양쪽 기본키 · 술어가 내려간다) · wms_stage 는 창고 어휘 하나 · ② 차수부터 창고 창구가 join so 대신 읽는다';
comment on view public.wms_order_doc_line is '공용 줄 목록 — so_line(qty_ordered − qty_removed) union all inv_transfer_line(qty) · pack_factor · qty_target_ea · stock_product_id(세트는 parent) · doc_id 로 읽는다';

-- ═══ 6) 재발행 — so_available_many · 마지막 정의 20260924015859:16~48 바이트 그대로(grant 는 20260924020852 가 authenticated 에 준 상태 그대로 남는다) · 더한 CTE 1(talloc 10줄) · 바뀐 줄 2(allocated_ea · available_ea) · 시그니처 · 반환 모양 무변 ═══
create or replace function public.so_available_many(p_stock_pids uuid[], p_location_id uuid)
  returns table (stock_pid uuid, qty_ea numeric, allocated_ea numeric, available_ea numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with pids as (
    select distinct u.pid as stock_pid from unnest(coalesce(p_stock_pids, '{}'::uuid[])) as u(pid)
  ),
  bal as (
    select b.product_id, sum(b.qty) as qty
    from public.ims_inv_balance b
    where b.warehouse_id = p_location_id and b.product_id = any(p_stock_pids)
    group by b.product_id
  ),
  alloc as (
    select coalesce(p.parent_product_id, p.id) as stock_pid, sum(r.qty_allocated * l.pack_factor) as ea
    from public.so_reserve r
    join public.so_line l on l.id = r.so_line_id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    where r.released_at is null and r.kind = 'allocated'
      and s.location_id = p_location_id
      and coalesce(p.parent_product_id, p.id) = any(p_stock_pids)
    group by 1
  ),
  talloc as (                                                                            -- tr-1a 2026-09-28 트랜스퍼 예약(묶음 2) — 확정된 문서(창고로 보내기 · 픽 중 포함 · 출발 전)의 줄 자체 · 출발 창고 · 낱개 EA
    select coalesce(p.parent_product_id, p.id) as stock_pid, sum(l.qty * l.pack_factor) as ea
    from public.inv_transfer_line l
    join public.inv_transfer t on t.id = l.transfer_id
    join public.product p on p.id = l.product_id
    where t.status in ('confirmed', 'at_wms', 'picking')
      and t.from_warehouse_id = p_location_id
      and coalesce(p.parent_product_id, p.id) = any(p_stock_pids)
    group by 1
  )
  select pids.stock_pid,
         coalesce(bal.qty, 0),
         coalesce(alloc.ea, 0) + coalesce(talloc.ea, 0),                                       -- tr-1a: 판매 예약 + 트랜스퍼 예약(반환 모양 무변 · 트랜스퍼가 0 이면 옛 값 그대로)
         coalesce(bal.qty, 0) - coalesce(alloc.ea, 0) - coalesce(talloc.ea, 0)
  from pids
  left join bal   on bal.product_id  = pids.stock_pid
  left join alloc on alloc.stock_pid = pids.stock_pid
  left join talloc on talloc.stock_pid = pids.stock_pid;
$$;

-- ═══ 7) 재발행 — ims_perm_catalog · 마지막 정의 20260928182712:488~510 바이트 그대로 + transfer 한 줄(묶음 아홉 8 · ims 방 · min_role 없음 · stock_move 줄 끝 쉼표) ═══
create or replace function public.ims_perm_catalog() returns jsonb
  language sql immutable
  set search_path = public, pg_temp
as $$
  select '{
    "modes": ["wms", "ims"],
    "screens": {
      "purchasing": {"room": "ims", "label": "Purchase orders, invoices, charges, payments"},
      "master":     {"room": "ims", "label": "Settings, suppliers, products, families, supplier products, prices, product tags, deals"},
      "receiving":  {"room": "ims", "label": "Receiving and putaway"},
      "staff":      {"room": "ims", "label": "Adding and editing people (below your own rank)"},
      "sales":      {"room": "ims", "label": "Sales orders, customer addresses and contacts"},
      "picking":     {"room": "wms", "label": "Picking — pick tasks, waves, holds"},
      "packing":     {"room": "wms", "label": "Packing — pack tasks, pallets, boxes"},
      "fulfillment": {"room": "wms", "label": "Fulfillment — finalize, shipping, manager review"},
      "wms_manage":  {"room": "wms", "min_role": "manager", "label": "Warehouse management — batches, waves, rollbacks (manager and above)"},
      "wms_receiving":         {"room": "wms", "label": "Warehouse receiving — count, put away, hold, off-PO"},
      "wms_receiving_confirm": {"room": "wms", "min_role": "manager", "label": "Warehouse receiving — confirm a receipt (manager and above · off until switched on)"},
      "stock_adjust":          {"room": "ims", "min_role": "manager", "label": "Stock adjustments — draft and confirm (manager and above · off until switched on)"},
      "stock_move":            {"room": "wms", "label": "Bin moves — move stock between bins in one warehouse (person by person · off until switched on)"},
      "transfer":              {"room": "ims", "label": "Transfers — warehouse to warehouse (person by person · off until switched on)"}
    }
  }'::jsonb;
$$;
