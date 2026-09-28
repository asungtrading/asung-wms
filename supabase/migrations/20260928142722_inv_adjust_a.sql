-- ─────────────────────────────────────────────────────────────
-- 재고 사건 ① 재고 조정 — DB 창구 (Asung-IMS · adj-a · 2026-09-28)
--   정본(뒤에 적는다): so-module §25(판정 47~53 · 묶음 열둘) · ledger-design 1부 6·7 · 4부 「보조 함수 넷」 · 조사 adj-1 · adj-1b
--   든 것: ① inv_adjust · inv_adjust_line · inv_adjust_number_seq · inv_adjust_next_number ② 권한 ims_can_adjust · ims_can_adjust_read(판정 49 · 50 · ims_can_write 안 씀) · 문 inv_adjust_require
--         ③ 읽기 조각 inv_adjust_picked(P) · inv_adjust_ledger · inv_adjust_eval ④ 초안 create · line_set · line_remove · delete ⑤ preview · confirm
--         ⑥ 원가 inv_layer_post_adjust · 원장 inv_post_adjust · 재생성 inv_layer_apply_adjust_ims ⑦ 읽기 list · detail · from_report(②)
--         ⑧ 재발행 셋 — ims_perm_catalog(20260926213035:50~70 · 더한 줄 1) · inv_layer_apply(20260928025627:611~1093 · 바뀐 줄 1 · 더한 줄 6) · wms_health_check(20260928025627:1240~1495 · 더한 줄 12)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사(⑤ 부터의 규칙) · 파일 안 begin/commit 없음 · 판정 51: Cin7 쪽 장치 없음
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

-- ═══ 1) 표 · 시퀀스 · 채번 (묶음 5 · 7 · po_receipt 선례 20260918161537:44~62) ═══
create sequence public.inv_adjust_number_seq start with 1 increment by 1;
create function public.inv_adjust_next_number() returns text
  language sql volatile
  set search_path = public, pg_temp
as $$
  select 'ADJ-' || lpad(nextval('public.inv_adjust_number_seq')::text, 5, '0');
$$;
comment on function public.inv_adjust_next_number() is '재고 조정 번호 채번 — ADJ- + 다섯 자리(inv_adjust_number_seq · 1 부터 · 롤백된 번호는 빈다 · po_receipt_next_number 선례). 2026-09-28';
revoke all on sequence public.inv_adjust_number_seq from public, anon;
grant usage, select on sequence public.inv_adjust_number_seq to authenticated;
revoke all on function public.inv_adjust_next_number() from public, anon;
grant execute on function public.inv_adjust_next_number() to authenticated;

create table public.inv_adjust (
  id             uuid primary key default gen_random_uuid(),
  adjust_number  text not null unique default public.inv_adjust_next_number(),
  status         text not null default 'draft',
  warehouse_id   uuid not null references public.ref_warehouse (id) on delete no action,
  warehouse      text not null,                                                            -- 이름 원문(원장 키 · inv_ledger.warehouse)
  note           text,
  report_id      bigint references public.wms_reports (id) on delete set null,             -- 묶음 9 — 신고에서 온 문서
  account_id     uuid references public.ref_account (id) on delete no action,              -- 묶음 10 — null 허용 · 회계 연결은 뒤
  account_code   text,
  posted_on      date,                                                                     -- 확정한 날(ims_today) = 원장 occurred_on
  created_by     uuid references public.ims_staff (id) on delete no action,
  confirmed_by   uuid references public.ims_staff (id) on delete no action,
  confirmed_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.ims_staff (id) on delete no action,
  constraint inv_adjust_status_ck   check (status in ('draft', 'confirmed')),
  constraint inv_adjust_confirm_ck  check ((status = 'confirmed') = (confirmed_at is not null) and (status = 'confirmed') = (posted_on is not null)),
  constraint inv_adjust_account_ck  check ((account_id is null) = (account_code is null))
);
create table public.inv_adjust_line (
  id             uuid primary key default gen_random_uuid(),
  adjust_id      uuid not null references public.inv_adjust (id) on delete cascade,
  line_no        int  not null,
  product_id     uuid not null references public.product (id) on delete no action,
  sku            text not null,                                                            -- 낱개 SKU(원장 키)
  bin_id         uuid not null references public.ref_bin (id) on delete no action,
  bin            text not null,
  mode           text not null,                                                            -- set = N 개로 맞춘다 · delta = ± N
  qty_input      numeric not null,
  reason         text not null,
  reason_note    text,
  unit_cost      numeric,                                                                  -- 주면 새 재고 원가(manual) · 안 주면 layer_avg
  seen_ledger    numeric not null,                                                         -- 줄을 적을 때 본 장부(CAS · 묶음 2)
  seen_picked    numeric not null,                                                         -- 줄을 적을 때 본 P(뽑혔지만 안 나간 수량)
  delta          numeric,                                                                  -- 확정 때 굳힌 증감(EA)
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.ims_staff (id) on delete no action,                 -- ims_touch 가 채운다
  constraint inv_adjust_line_uq        unique (adjust_id, product_id, bin_id),            -- 한 문서 안 같은 칸 · SKU 두 줄 금지(보통 유니크)
  constraint inv_adjust_line_no_uq     unique (adjust_id, line_no),
  constraint inv_adjust_line_mode_ck   check (mode in ('set', 'delta')),
  constraint inv_adjust_line_set_ck    check (mode <> 'set' or qty_input >= 0),
  constraint inv_adjust_line_reason_ck check (reason in ('found', 'lost', 'damaged', 'count', 'other')),
  constraint inv_adjust_line_other_ck  check (reason <> 'other' or nullif(trim(reason_note), '') is not null),
  constraint inv_adjust_line_cost_ck   check (unit_cost is null or unit_cost >= 0),
  constraint inv_adjust_line_bin_ck    check (bin <> '')
);
create index inv_adjust_line_adjust_idx on public.inv_adjust_line (adjust_id);
create trigger inv_adjust_touch      before update on public.inv_adjust      for each row execute function public.ims_touch();
create trigger inv_adjust_line_touch before update on public.inv_adjust_line for each row execute function public.ims_touch();
alter table public.inv_adjust      enable row level security;
alter table public.inv_adjust_line enable row level security;
comment on table public.inv_adjust is '재고 조정 문서(재고 사건 ① · 판정 47~53 · 묶음 열둘 · 2026-09-28) — 문서 하나 = 창고 하나 · draft → confirmed · 되돌리기 없음(판정 53 · 새 문서로 바로잡고 메모에 원 번호) · 쓰기는 창구(inv_adjust_*)로만 · 읽기 정책 ims_can_adjust_read';
comment on table public.inv_adjust_line is '조정 줄 — 언제나 한 칸 · 한 낱개 SKU(묶음 1 · 7 · 8) · mode set/delta · seen_ledger · seen_picked = 적을 때 본 값(확정 때 다시 읽어 다르면 전체 거부 · 묶음 2) · delta 는 확정 때 · 사유 다섯(판정 52) · 원장 line_ref = 이 줄 id';

-- ═══ 2) 권한 — 판정 49 · 50 (ims_can_write 를 쓰지 않는다: supervisor 에게 역할로 true 를 주기 때문) ═══
create function public.ims_can_adjust() returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case when s.role = 'admin' then true
                when s.role in ('supervisor', 'manager') then s.perms ? 'stock_adjust'     -- 판정 49 — 직접 켠 사람만
                else false end                                                              -- 판정 50 — worker 는 열쇠가 있어도 못 한다
    from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active), false);
$$;
create function public.ims_can_adjust_read() returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select s.role in ('admin', 'supervisor') or s.perms ? 'stock_adjust' or s.perms ? 'stock_adjust:read'
    from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active), false);
$$;
comment on function public.ims_can_adjust() is '재고 조정을 적고 확정할 수 있는가 — admin 은 역할로 · supervisor · manager 는 perms ? stock_adjust(직접 켠 사람만 · 판정 49) · worker 는 늘 false(판정 50) · ⚠️ ims_can_write 와 다르다(그쪽은 supervisor 에게 역할로 true)';
comment on function public.ims_can_adjust_read() is '조정 문서를 읽을 수 있는가 — admin · supervisor 역할로 · 그 밖은 stock_adjust 또는 stock_adjust:read';
revoke all on function public.ims_can_adjust() from public, anon;       grant execute on function public.ims_can_adjust() to authenticated;
revoke all on function public.ims_can_adjust_read() from public, anon;  grant execute on function public.ims_can_adjust_read() to authenticated;
create policy inv_adjust_select      on public.inv_adjust      for select to authenticated using (public.ims_can_adjust_read());
create policy inv_adjust_line_select on public.inv_adjust_line for select to authenticated using (public.ims_can_adjust_read());

-- 문 — 창구 첫 줄(권한 + 창고) · 사람 id 를 돌려준다(so_current_staff 는 회수돼 있어 원본 두 줄 방식)
create function public.inv_adjust_require(p_warehouse_id uuid) returns uuid
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  if not public.ims_can_adjust() then
    raise exception 'You cannot adjust stock — this needs the stock_adjust key (admin, or a supervisor or manager with the key switched on) — nothing was saved';
  end if;
  if p_warehouse_id is not null and not public.ims_can_warehouse(p_warehouse_id) then
    raise exception 'This adjustment is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  return v_staff;
end;
$$;
revoke all on function public.inv_adjust_require(uuid) from public, anon, authenticated;

-- ═══ 3) 읽기 조각 — 장부 · P(뽑혔지만 안 나간 수량 · D 조사) ═══
--   P = 완료된 픽의 실제 칸 행(wms_pick_line_bins planned=false) 가운데 오더가 아직 창고 안(picking · packed)인 것 — 나가면(so_finalize → sale_out) 장부에서 빠지고, 되돌리면(wms_rollback) 그 행이 지워진다.
--   낱개 SKU 로 접는다(세트 줄은 product.parent_product_id) · 과다 픽(over-pick · 반납)은 나갈 때까지 P 에 남는다(한계 · 보고 D)
create function public.inv_adjust_picked(p_warehouse_id uuid, p_bin_id uuid, p_product_id uuid) returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select coalesce(sum(pb.qty_base), 0)
    from public.wms_pick_line_bins pb
    join public.wms_pick_task_lines pl on pl.id = pb.pick_task_line_id
    join public.wms_pick_tasks t on t.id = pl.pick_task_id
    join public.so s on s.id = t.order_id
    join public.so_line l on l.id = pl.order_line_id
    join public.product pr on pr.id = l.product_id
   where not pb.planned and pb.bin_id = p_bin_id and s.location_id = p_warehouse_id
     and s.status in ('picking', 'packed') and coalesce(pr.parent_product_id, pr.id) = p_product_id;
$$;
create function public.inv_adjust_ledger(p_warehouse text, p_bin text, p_sku text) returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select coalesce((select v.qty from public.ims_inv_balance v where v.sku = p_sku and v.warehouse = p_warehouse and v.bin = p_bin), 0);
$$;
revoke all on function public.inv_adjust_picked(uuid, uuid, uuid) from public, anon;   grant execute on function public.inv_adjust_picked(uuid, uuid, uuid) to authenticated;
revoke all on function public.inv_adjust_ledger(text, text, text) from public, anon;   grant execute on function public.inv_adjust_ledger(text, text, text) to authenticated;

-- 줄 평가 — 미리 보기 · 확정이 같은 식을 본다(for update 없음 · read only 에서 돈다)
--   basis = 장부 − P(선반 기대량) · set: delta = 목표 − basis · delta: 그대로 · 결과 = 장부 + delta · 음수 검사는 장부 기준 · CAS 는 장부 · P 둘 다
create function public.inv_adjust_eval(p_adjust_id uuid)
  returns table(line_id uuid, line_no int, product_id uuid, sku text, bin_id uuid, bin text, mode text, qty_input numeric, reason text, reason_note text, unit_cost numeric,
                seen_ledger numeric, seen_picked numeric, ledger numeric, picked numeric, basis numeric, delta numeric, result numeric,
                cost_branch text, avg_unit_cost numeric, rejects text[])
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with h as (select a.warehouse, a.warehouse_id from public.inv_adjust a where a.id = p_adjust_id),
  x as (
    select l.*, public.inv_adjust_ledger(h.warehouse, l.bin, l.sku) as ledger, public.inv_adjust_picked(h.warehouse_id, l.bin_id, l.product_id) as picked,
           (select coalesce(sum(t.rem * t.unit_cost) / nullif(sum(t.rem), 0), null)
              from (select y.unit_cost, y.qty - coalesce((select sum(c.qty) from public.inv_layer_consume c where c.layer_id = y.id), 0) as rem
                      from public.inv_layer y where y.sku = l.sku and y.warehouse = h.warehouse) t where t.rem > 0) as avg_cost,
           (select b.is_active and b.warehouse_id = h.warehouse_id from public.ref_bin b where b.id = l.bin_id) as bin_ok
      from public.inv_adjust_line l, h where l.adjust_id = p_adjust_id
  ),
  y as (select x.*, x.ledger - x.picked as basis, case when x.mode = 'set' then x.qty_input - (x.ledger - x.picked) else x.qty_input end as d from x)
  select y.id, y.line_no, y.product_id, y.sku, y.bin_id, y.bin, y.mode, y.qty_input, y.reason, y.reason_note, y.unit_cost,
         y.seen_ledger, y.seen_picked, y.ledger, y.picked, y.basis, y.d, y.ledger + y.d,
         case when y.d > 0 and y.unit_cost is not null then 'manual' when y.d > 0 and y.avg_cost is not null then 'layer_avg'
              when y.d > 0 then 'unknown' when y.d < 0 then 'fifo' else 'none' end,
         round(y.avg_cost, 6),
         array_remove(array[
           case when y.ledger + y.d < 0 then format('line %s %s %s: result would be %s (below zero)', y.line_no, y.sku, y.bin, y.ledger + y.d) end,
           case when y.ledger <> y.seen_ledger then format('line %s %s %s: ledger changed (you saw %s, it is now %s)', y.line_no, y.sku, y.bin, y.seen_ledger, y.ledger) end,
           case when y.picked <> y.seen_picked then format('line %s %s %s: picked-not-shipped changed (you saw %s, it is now %s)', y.line_no, y.sku, y.bin, y.seen_picked, y.picked) end,
           case when not coalesce(y.bin_ok, false) then format('line %s: bin %s is inactive or not in this warehouse', y.line_no, y.bin) end
         ], null)
    from y order by y.line_no;
$$;
revoke all on function public.inv_adjust_eval(uuid) from public, anon;   grant execute on function public.inv_adjust_eval(uuid) to authenticated;

-- ═══ 4) 초안 창구 — definer(표에 쓰기 정책이 없다 · SO 거래 표 선례) · 첫 줄 문 ═══
create function public.inv_adjust_create(p_warehouse_id uuid, p_note text default null, p_report_id bigint default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_wh public.ref_warehouse%rowtype; v_r public.wms_reports%rowtype; v_a public.inv_adjust%rowtype;
begin
  v_staff := public.inv_adjust_require(p_warehouse_id);                                    -- ⭐ 첫 줄
  select * into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if not found then raise exception 'Warehouse not found or inactive — nothing was saved'; end if;
  if p_report_id is not null then
    select * into v_r from public.wms_reports r where r.id = p_report_id;
    if not found or v_r.kind <> 'stock_short' then raise exception 'Report % is not a Not-enough-stock report — nothing was saved', p_report_id; end if;
  end if;
  insert into public.inv_adjust (warehouse_id, warehouse, note, report_id, created_by, updated_by)
  values (v_wh.id, v_wh.name, nullif(trim(p_note), ''), p_report_id, v_staff, v_staff) returning * into v_a;
  return jsonb_build_object('id', v_a.id, 'adjust_number', v_a.adjust_number, 'status', v_a.status, 'warehouse', v_a.warehouse, 'report_id', v_a.report_id);
end;
$$;

-- 줄 넣기 · 고치기 — p_line {line_id?, product_id?|sku?, bin_id?|bin?, mode, qty, reason, note?, unit_cost?} · 본 값(장부 · P)은 이 순간 읽어 적는다(묶음 2)
create function public.inv_adjust_line_set(p_adjust_id uuid, p_line jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_a public.inv_adjust%rowtype; v_p public.product%rowtype; v_b public.ref_bin%rowtype; v_l public.inv_adjust_line%rowtype;
        v_mode text; v_qty numeric; v_reason text; v_note text; v_cost numeric; v_ledger numeric; v_picked numeric; v_id uuid; v_no int;
begin
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id for update;
  if not found then raise exception 'Adjustment not found — nothing was saved'; end if;
  perform public.inv_adjust_require(v_a.warehouse_id);                                     -- ⭐ 첫 줄 문(문서의 창고)
  if v_a.status <> 'draft' then raise exception 'Adjustment % is % — only a draft can be edited — nothing was saved', v_a.adjust_number, v_a.status; end if;
  if p_line is null or jsonb_typeof(p_line) <> 'object' then raise exception 'p_line must be a JSON object — nothing was saved'; end if;
  -- 제품 — 낱개만(세트는 거부 · 묶음 8)
  if nullif(p_line->>'product_id', '') is not null then select * into v_p from public.product p where p.id = (p_line->>'product_id')::uuid;
  else select * into v_p from public.product p where p.sku = trim(p_line->>'sku'); end if;
  if not found then raise exception 'Product not found (%) — nothing was saved', coalesce(p_line->>'sku', p_line->>'product_id'); end if;
  if not v_p.is_active then raise exception 'Product % is inactive — nothing was saved', v_p.sku; end if;
  if v_p.parent_product_id is not null then raise exception 'Product % is a set or pack — adjust the single-unit SKU instead — nothing was saved', v_p.sku; end if;
  -- 칸 — 이 창고의 활성 칸(묶음 7)
  if nullif(p_line->>'bin_id', '') is not null then select * into v_b from public.ref_bin b where b.id = (p_line->>'bin_id')::uuid;
  else select * into v_b from public.ref_bin b where b.warehouse_id = v_a.warehouse_id and b.name = trim(p_line->>'bin'); end if;
  if not found or v_b.warehouse_id <> v_a.warehouse_id or not v_b.is_active or v_b.name = '' then
    raise exception 'Bin % is not an active bin at % — nothing was saved', coalesce(p_line->>'bin', p_line->>'bin_id', '?'), v_a.warehouse;
  end if;
  v_mode := lower(trim(p_line->>'mode'));
  if v_mode not in ('set', 'delta') then raise exception 'mode must be set (adjust to N) or delta (add or take N) — nothing was saved'; end if;
  if (p_line->>'qty') !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then raise exception 'qty must be a number — nothing was saved'; end if;
  v_qty := (p_line->>'qty')::numeric;
  if v_mode = 'set' and v_qty < 0 then raise exception 'A target quantity cannot be negative — nothing was saved'; end if;
  if v_mode = 'delta' and v_qty = 0 then raise exception 'A delta of 0 changes nothing — nothing was saved'; end if;
  v_reason := lower(trim(p_line->>'reason'));  v_note := nullif(trim(p_line->>'note'), '');
  if v_reason not in ('found', 'lost', 'damaged', 'count', 'other') then raise exception 'reason must be one of found, lost, damaged, count, other — nothing was saved'; end if;
  if v_reason = 'other' and v_note is null then raise exception 'reason other needs a note — nothing was saved'; end if;
  if nullif(p_line->>'unit_cost', '') is not null then
    if (p_line->>'unit_cost') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then raise exception 'unit_cost must be a number 0 or more — nothing was saved'; end if;
    v_cost := (p_line->>'unit_cost')::numeric;
  end if;
  v_ledger := public.inv_adjust_ledger(v_a.warehouse, v_b.name, v_p.sku);
  v_picked := public.inv_adjust_picked(v_a.warehouse_id, v_b.id, v_p.id);
  v_id := nullif(p_line->>'line_id', '')::uuid;
  if v_id is null then select l.id into v_id from public.inv_adjust_line l where l.adjust_id = p_adjust_id and l.product_id = v_p.id and l.bin_id = v_b.id; end if;
  if v_id is not null then
    update public.inv_adjust_line set product_id = v_p.id, sku = v_p.sku, bin_id = v_b.id, bin = v_b.name, mode = v_mode, qty_input = v_qty, reason = v_reason, reason_note = v_note,
           unit_cost = v_cost, seen_ledger = v_ledger, seen_picked = v_picked
     where id = v_id and adjust_id = p_adjust_id returning * into v_l;
    if not found then raise exception 'Line % is not on this adjustment — nothing was saved', v_id; end if;
  else
    select coalesce(max(l.line_no), 0) + 1 into v_no from public.inv_adjust_line l where l.adjust_id = p_adjust_id;
    insert into public.inv_adjust_line (adjust_id, line_no, product_id, sku, bin_id, bin, mode, qty_input, reason, reason_note, unit_cost, seen_ledger, seen_picked)
    values (p_adjust_id, v_no, v_p.id, v_p.sku, v_b.id, v_b.name, v_mode, v_qty, v_reason, v_note, v_cost, v_ledger, v_picked) returning * into v_l;
  end if;
  update public.inv_adjust set updated_by = (select s.id from public.ims_staff s where s.auth_user_id = auth.uid()) where id = p_adjust_id;
  return jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'bin', v_l.bin, 'mode', v_l.mode, 'qty_input', v_l.qty_input,
                            'seen_ledger', v_ledger, 'seen_picked', v_picked, 'basis', v_ledger - v_picked,
                            'delta', case when v_mode = 'set' then v_qty - (v_ledger - v_picked) else v_qty end);
exception when unique_violation then
  raise exception 'This adjustment already has a line for % at % — edit that line instead — nothing was saved', v_p.sku, v_b.name;
end;
$$;

create function public.inv_adjust_line_remove(p_adjust_id uuid, p_line_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_a public.inv_adjust%rowtype; v_n int;
begin
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id for update;
  if not found then raise exception 'Adjustment not found — nothing was saved'; end if;
  perform public.inv_adjust_require(v_a.warehouse_id);
  if v_a.status <> 'draft' then raise exception 'Adjustment % is % — only a draft can be edited — nothing was saved', v_a.adjust_number, v_a.status; end if;
  delete from public.inv_adjust_line where id = p_line_id and adjust_id = p_adjust_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Line not found on this adjustment — nothing was saved'; end if;
  return jsonb_build_object('adjust_id', p_adjust_id, 'removed', p_line_id);
end;
$$;

create function public.inv_adjust_delete(p_adjust_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_a public.inv_adjust%rowtype;
begin
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id for update;
  if not found then raise exception 'Adjustment not found — nothing was saved'; end if;
  perform public.inv_adjust_require(v_a.warehouse_id);
  if v_a.status <> 'draft' then raise exception 'Adjustment % is % — a confirmed adjustment cannot be deleted (correct it with a new adjustment) — nothing was saved', v_a.adjust_number, v_a.status; end if;
  delete from public.inv_adjust where id = p_adjust_id;                                     -- 줄은 cascade · 번호는 빈다(허용)
  return jsonb_build_object('deleted', v_a.adjust_number);
end;
$$;

-- ═══ 5) 미리 보기 · 확정 (묶음 4) ═══
create function public.inv_adjust_preview(p_adjust_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare v_a public.inv_adjust%rowtype; v_lines jsonb; v_rej text[]; v_warn text[] := '{}';
begin
  if not public.ims_can_adjust_read() then raise exception 'You cannot view stock adjustments — this needs the stock_adjust key'; end if;
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id;
  if not found then raise exception 'Adjustment not found'; end if;
  select coalesce(jsonb_agg(to_jsonb(e) order by e.line_no), '[]'::jsonb) into v_lines from public.inv_adjust_eval(p_adjust_id) e;
  select coalesce(array_agg(x order by x), '{}') into v_rej from public.inv_adjust_eval(p_adjust_id) e cross join lateral unnest(e.rejects) as x;
  if exists (select 1 from public.inv_adjust_eval(p_adjust_id) e where e.cost_branch = 'unknown') then v_warn := array_append(v_warn, 'cost_unknown'); end if;
  if exists (select 1 from public.inv_adjust_eval(p_adjust_id) e where e.delta = 0) then v_warn := array_append(v_warn, 'lines_without_change'); end if;
  if jsonb_array_length(v_lines) = 0 then v_rej := array_append(v_rej, 'no lines'); end if;
  return jsonb_build_object('adjust_id', v_a.id, 'adjust_number', v_a.adjust_number, 'status', v_a.status, 'warehouse', v_a.warehouse, 'posted_on', coalesce(v_a.posted_on, public.ims_today()),
                            'lines', v_lines, 'rejects', to_jsonb(v_rej), 'can_confirm', v_a.status = 'draft' and cardinality(v_rej) = 0, 'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.inv_adjust_preview(uuid) from public, anon;   grant execute on function public.inv_adjust_preview(uuid) to authenticated;

create function public.inv_adjust_confirm(p_adjust_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_a public.inv_adjust%rowtype; v_staff uuid; v_rej text[]; v_on date; v_post jsonb; v_rep int := 0; v_e record;
begin
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id for update;             -- 머리 잠금 — 같은 문서 두 번 확정 방지
  if not found then raise exception 'Adjustment not found — nothing was saved'; end if;
  v_staff := public.inv_adjust_require(v_a.warehouse_id);                                   -- ⭐ 첫 줄 문
  if v_a.status <> 'draft' then raise exception 'Adjustment % is already % — nothing was saved', v_a.adjust_number, v_a.status; end if;
  if not exists (select 1 from public.inv_adjust_line l where l.adjust_id = p_adjust_id) then raise exception 'Adjustment % has no lines — nothing was saved', v_a.adjust_number; end if;
  -- 줄마다 다시 읽는다 — 음수 · 본 값 달라짐(장부 · P) · 칸 → 하나라도 막히면 전체 거부(사람 문장)
  select coalesce(array_agg(x order by x), '{}') into v_rej from public.inv_adjust_eval(p_adjust_id) e cross join lateral unnest(e.rejects) as x;
  if cardinality(v_rej) > 0 then raise exception 'Adjustment % cannot be confirmed: % — reload and check the lines — nothing was saved', v_a.adjust_number, array_to_string(v_rej, '; '); end if;
  v_on := public.ims_today();
  for v_e in select * from public.inv_adjust_eval(p_adjust_id) loop
    update public.inv_adjust_line set delta = v_e.delta where id = v_e.line_id;                   -- delta 0 줄도 굳힌다(원장 행은 없다 · Cin7 규칙)
  end loop;
  update public.inv_adjust set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now(), posted_on = v_on, updated_by = v_staff where id = p_adjust_id;
  v_post := public.inv_post_adjust(p_adjust_id);                                            -- 원장 + 원가 레이어 · 같은 트랜잭션 · 실패하면 확정도 안 된다
  if v_a.report_id is not null then                                                         -- 묶음 9 — 열린 신고를 닫는다(이미 닫힌 것은 무변)
    update public.wms_reports set resolved_by = v_staff, resolved_at = now() where id = v_a.report_id and kind = 'stock_short' and resolved_at is null;
    get diagnostics v_rep = row_count;
  end if;
  return jsonb_build_object('adjust_id', v_a.id, 'adjust_number', v_a.adjust_number, 'status', 'confirmed', 'posted_on', v_on,
                            'ledger', v_post, 'report_id', v_a.report_id, 'report_resolved', v_rep = 1);
end;
$$;
revoke all on function public.inv_adjust_create(uuid, text, bigint) from public, anon;   grant execute on function public.inv_adjust_create(uuid, text, bigint) to authenticated;
revoke all on function public.inv_adjust_line_set(uuid, jsonb) from public, anon;        grant execute on function public.inv_adjust_line_set(uuid, jsonb) to authenticated;
revoke all on function public.inv_adjust_line_remove(uuid, uuid) from public, anon;      grant execute on function public.inv_adjust_line_remove(uuid, uuid) to authenticated;
revoke all on function public.inv_adjust_delete(uuid) from public, anon;                 grant execute on function public.inv_adjust_delete(uuid) to authenticated;
revoke all on function public.inv_adjust_confirm(uuid) from public, anon;                grant execute on function public.inv_adjust_confirm(uuid) to authenticated;
comment on function public.inv_adjust_confirm(uuid) is '⭐⭐ 재고 조정 확정(판정 47~53 · 묶음 2·3·4·6·9) — definer · 머리 for update · 첫 줄 inv_adjust_require(권한 + 창고) · draft · 줄 있음 · inv_adjust_eval 로 줄마다 장부·P 를 다시 읽어 본 값과 다르거나 결과가 음수면 전체 거부 · delta 굳힘 · posted_on = ims_today · inv_post_adjust(원장 + 레이어) · report_id 의 열린 stock_short 신고를 닫는다 · 되돌리기 없음(판정 53)';

-- ═══ 6) 원장 · 원가 창구 (묶음 3 · 11 · credit_in IMS 축 20260925012354 의 셋과 같은 모양) ═══
create function public.inv_layer_post_adjust(p_doc_number text, p_line_ref text, p_sku text, p_warehouse text, p_qty numeric, p_occurred_on date, p_unit_cost numeric, p_hint jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_layer_post_adjust@2026-09-28.1';
        v_hint jsonb := case when p_hint is not null and jsonb_typeof(p_hint) = 'object' then p_hint else null end;
        v_unit numeric; v_src text; v_origin text; v_id bigint; v_rem numeric; v_remval numeric; v_rows int; v_short int; v_layers int; v_taken numeric; v_amt numeric;
begin
  if p_qty is null or p_qty = 0 then return jsonb_build_object('qty', p_qty, 'branch', 'none', 'builder', c_version); end if;
  if exists (select 1 from public.inv_layer y where y.origin_type in ('adjust_existing', 'adjust_new') and y.doc_number = p_doc_number and y.line_ref = p_line_ref)
     or exists (select 1 from public.inv_layer_consume c where c.doc_type = 'adjustment' and c.doc_number = p_doc_number and c.line_ref = p_line_ref) then
    raise exception 'Adjustment % line % was already costed — nothing was saved', p_doc_number, p_line_ref;
  end if;
  if p_qty < 0 then                                                                         -- − = FIFO 소진(Cin7 축 A-3 과 같은 reason adjust_out)
    select * into v_rows, v_short, v_layers, v_taken
      from public.inv_layer_fifo_take(p_sku, p_warehouse, -p_qty, 'adjustment', p_doc_number, p_line_ref, 'adjust_existing', p_occurred_on, 'adjust_out', null);
    select coalesce(sum(c.amount), 0) into v_amt from public.inv_layer_consume c where c.doc_type = 'adjustment' and c.doc_number = p_doc_number and c.line_ref = p_line_ref;
    return jsonb_build_object('qty', p_qty, 'branch', 'fifo', 'consume_rows', v_rows, 'layers', v_layers, 'taken', v_taken, 'short', v_short, 'amount', v_amt, 'builder', c_version);
  end if;
  if p_unit_cost is not null then                                                           -- + 단가 있음 = 새 재고(manual)
    v_unit := p_unit_cost; v_src := 'manual'; v_origin := 'adjust_new';
  elsif v_hint is not null and nullif(v_hint->>'unit_cost', '') is not null and (v_hint->>'cost_source') in ('layer_avg', 'unknown') then
    v_unit := (v_hint->>'unit_cost')::numeric; v_src := v_hint->>'cost_source'; v_origin := 'adjust_existing';   -- 재생성 hint = 실시간과 같은 값
  else                                                                                      -- + 단가 없음 = 남은 레이어 가중평균(없으면 unknown 0 · Cin7 A-1 · A-2 와 같다)
    select coalesce(sum(t.rem), 0), coalesce(sum(t.rem * t.unit_cost), 0) into v_rem, v_remval
      from (select y.unit_cost, y.qty - coalesce((select sum(c.qty) from public.inv_layer_consume c where c.layer_id = y.id), 0) as rem
              from public.inv_layer y where y.sku = p_sku and y.warehouse = p_warehouse) t where t.rem > 0;
    if v_rem > 0 then v_unit := round(v_remval / v_rem, 6); v_src := 'layer_avg'; else v_unit := 0; v_src := 'unknown'; end if;
    v_origin := 'adjust_existing';
  end if;
  insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
  values (p_sku, p_warehouse, v_origin, p_doc_number, p_line_ref, null, p_occurred_on, true, p_qty, v_unit, v_src) returning id into v_id;
  return jsonb_build_object('qty', p_qty, 'branch', v_src, 'origin_type', v_origin, 'layer_id', v_id, 'unit_cost', v_unit, 'cost_source', v_src, 'amount', round(p_qty * v_unit, 6), 'reproduced', v_hint is not null, 'builder', c_version);
end;
$$;
comment on function public.inv_layer_post_adjust(text, text, text, text, numeric, date, numeric, jsonb) is '⭐⭐ IMS 재고 조정의 원가 창구(묶음 3 · 11) — definer · authenticated 없음 · 실시간(inv_post_adjust)·재생성(inv_layer_apply_adjust_ims) 둘이 이것만 부른다 · + 단가 있음 = adjust_new/manual · + 단가 없음 = adjust_existing/layer_avg(남은 레이어 가중평균 · 없으면 unknown 0 · 거부하지 않는다) · − = inv_layer_fifo_take reason adjust_out(부족은 short 만) · 키 (doc_number, line_ref) 멱등 · p_hint = raw.cost';
revoke all on function public.inv_layer_post_adjust(text, text, text, text, numeric, date, numeric, jsonb) from public, anon, authenticated;

create function public.inv_post_adjust(p_adjust_id uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_post_adjust@2026-09-28.1';
        v_a public.inv_adjust%rowtype; v_existing int; v_rows int := 0; v_qty numeric := 0; v_cost jsonb; v_keys jsonb := '{}'::jsonb; l record;
begin
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id;
  if not found then raise exception 'Adjustment not found — nothing was posted to the ledger'; end if;
  if v_a.status <> 'confirmed' then raise exception 'Adjustment % is % — the ledger takes confirmed adjustments only — nothing was posted to the ledger', v_a.adjust_number, v_a.status; end if;
  select count(*) into v_existing from public.inv_ledger e where e.doc_type = 'adjustment' and e.doc_number = v_a.adjust_number and e.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('adjust_id', v_a.id, 'adjust_number', v_a.adjust_number, 'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_ea_posted', 0, 'warnings', '["already_posted"]'::jsonb);
  end if;
  for l in select * from public.inv_adjust_line x where x.adjust_id = p_adjust_id and x.delta is not null and x.delta <> 0 order by x.line_no loop
    v_cost := public.inv_layer_post_adjust(v_a.adjust_number, l.id::text, l.sku, v_a.warehouse, l.delta, v_a.posted_on, l.unit_cost, null);   -- ⭐ 레이어 먼저 · 결과를 raw.cost 에
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_a.posted_on, case when l.delta > 0 then 1 else 2 end, l.sku, v_a.warehouse, l.bin, l.delta,
            case when l.delta > 0 and l.unit_cost is not null then 'adjust_new' else 'adjust_existing' end, 'adjustment', v_a.adjust_number, v_a.id::text, l.id::text,
            nullif(v_cost->>'amount', '')::numeric, 'ims',
            jsonb_build_object('kind', 'adjust', 'poster', c_version,
              'header', jsonb_build_object('adjust_number', v_a.adjust_number, 'adjusted_on', v_a.posted_on, 'warehouse_id', v_a.warehouse_id, 'warehouse', v_a.warehouse, 'report_id', v_a.report_id, 'account_code', v_a.account_code, 'note', v_a.note, 'confirmed_by', v_a.confirmed_by),
              'line', jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'bin_id', l.bin_id, 'bin', l.bin, 'mode', l.mode, 'qty_input', l.qty_input,
                                         'seen_ledger', l.seen_ledger, 'seen_picked', l.seen_picked, 'delta', l.delta, 'reason', l.reason, 'reason_note', l.reason_note, 'unit_cost', l.unit_cost),
              'rule', format('%s: %s %s → delta %s (ledger %s − picked %s = shelf %s)', l.mode, l.qty_input, case when l.mode = 'set' then 'target' else 'input' end, l.delta, l.seen_ledger, l.seen_picked, l.seen_ledger - l.seen_picked),
              'cost', v_cost));
    v_rows := v_rows + 1; v_qty := v_qty + l.delta; v_keys := v_keys || jsonb_build_object(l.id::text, v_cost);
  end loop;
  return jsonb_build_object('adjust_id', v_a.id, 'adjust_number', v_a.adjust_number, 'already_posted', false, 'existing_rows', 0, 'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_keys, 'poster', c_version);
exception when unique_violation then
  raise exception 'Adjustment % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_a.adjust_number, sqlerrm;
end;
$$;
comment on function public.inv_post_adjust(uuid) is '⭐⭐ 재고 조정의 원장 창구(묶음 11 · inv_post_credit 모양) — confirmed 문서의 delta ≠ 0 줄마다 줄 = 칸 하나 adjust_existing/adjust_new 행(낱개 SKU · EA · seq_hint + 1 · − 2 · doc adjustment/ADJ 번호 · line_ref 줄 id · source ims) · 줄마다 inv_layer_post_adjust 를 먼저 불러 raw.cost 에 싣는다(재생성 hint) · 멱등(already_posted) · invoker · authenticated 없음 — inv_adjust_confirm 만 부른다';
revoke all on function public.inv_post_adjust(uuid) from public, anon, authenticated;

create function public.inv_layer_apply_adjust_ims(p_ledger_id bigint, p_until date,
                                                  out o_layers int, out o_rows int, out o_short int, out o_unknown int, out o_new_net_zero int, out o_processed int)
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare r public.inv_ledger%rowtype; v_res jsonb;
begin
  o_layers := 0; o_rows := 0; o_short := 0; o_unknown := 0; o_new_net_zero := 0; o_processed := 0;
  select * into r from public.inv_ledger where id = p_ledger_id;
  if not found or r.event_type not in ('adjust_existing', 'adjust_new') or r.source <> 'ims' then return; end if;
  if exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_adj' and d.doc_number = r.line_ref and d.sku = r.sku and d.warehouse = r.warehouse) then return; end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_adj', r.line_ref, r.sku, r.warehouse);   -- 키 = 줄(line_ref) · 줄마다 원장 행 하나
  o_processed := 1;
  v_res := public.inv_layer_post_adjust(r.doc_number, r.line_ref, r.sku, r.warehouse, r.qty_delta, r.occurred_on, nullif(r.raw -> 'line' ->> 'unit_cost', '')::numeric, r.raw -> 'cost');
  o_layers := case when v_res ? 'layer_id' then 1 else 0 end;
  o_rows := coalesce((v_res ->> 'consume_rows')::int, 0);  o_short := coalesce((v_res ->> 'short')::int, 0);
  o_unknown := case when v_res ->> 'cost_source' = 'unknown' then 1 else 0 end;
end;
$$;
comment on function public.inv_layer_apply_adjust_ims(bigint, date) is '재생성 보조 · IMS 축 adjust_existing/adjust_new(묶음 11) — inv_layer_apply 가 source ims 인 조정 행을 여기로 보낸다(Cin7 축은 inv_layer_apply_adjust 그대로) · 키 = 줄(line_ref) · raw.line.unit_cost · raw.cost(hint)로 inv_layer_post_adjust 를 불러 실시간과 같은 레이어를 세운다 · 반환 모양은 inv_layer_apply_adjust 와 같다';
revoke all on function public.inv_layer_apply_adjust_ims(bigint, date) from public, anon, authenticated;

-- ═══ 7) 읽기 창구 — 화면 adj-c · 연결 adj-b 가 쓴다 ═══
create function public.inv_adjust_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_adjust_read() then null::jsonb else
  coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from (
    select a.id, a.adjust_number, a.status, a.warehouse_id, a.warehouse, a.note, a.report_id, r.order_number as report_order, a.posted_on, a.created_at, a.confirmed_at,
           cb.name as created_by_name, fb.name as confirmed_by_name,
           (select count(*) from public.inv_adjust_line l where l.adjust_id = a.id) as line_count
      from public.inv_adjust a
      left join public.wms_reports r on r.id = a.report_id
      left join public.ims_staff cb on cb.id = a.created_by
      left join public.ims_staff fb on fb.id = a.confirmed_by
     where (nullif(p_filters->>'status', '') is null or a.status = p_filters->>'status')
       and (nullif(p_filters->>'warehouse_id', '') is null or a.warehouse_id = (p_filters->>'warehouse_id')::uuid)
       and (nullif(p_filters->>'q', '') is null or a.adjust_number ilike '%' || (p_filters->>'q') || '%' or a.note ilike '%' || (p_filters->>'q') || '%'
            or exists (select 1 from public.inv_adjust_line l where l.adjust_id = a.id and l.sku ilike '%' || (p_filters->>'q') || '%'))
       and (nullif(p_filters->>'from', '') is null or a.created_at >= (p_filters->>'from')::date)
       and (nullif(p_filters->>'to', '') is null or a.created_at < (p_filters->>'to')::date + 1)
     order by a.created_at desc limit coalesce(nullif(p_filters->>'limit', '')::int, 300)) t), '[]'::jsonb) end;
$$;

create function public.inv_adjust_detail(p_adjust_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_adjust_read() then null::jsonb else (
    select jsonb_build_object(
      'header', to_jsonb(a) || jsonb_build_object('created_by_name', cb.name, 'confirmed_by_name', fb.name),
      'report', (select jsonb_build_object('id', r.id, 'order_number', r.order_number, 'sku', r.sku, 'qty_expected', r.qty_expected, 'qty_found', r.qty_found, 'note', r.note, 'resolved_at', r.resolved_at)
                   from public.wms_reports r where r.id = a.report_id),
      'lines', (select coalesce(jsonb_agg(to_jsonb(e) || jsonb_build_object('product_name', p.name, 'ledger_rows',
                        (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'event_type', x.event_type, 'qty_delta', x.qty_delta, 'occurred_on', x.occurred_on, 'cost', x.raw -> 'cost')), '[]'::jsonb)
                           from public.inv_ledger x where x.doc_type = 'adjustment' and x.doc_number = a.adjust_number and x.line_ref = e.line_id::text)) order by e.line_no), '[]'::jsonb)
                  from public.inv_adjust_eval(a.id) e join public.product p on p.id = e.product_id),
      'preview', case when a.status = 'draft' then public.inv_adjust_preview(a.id) - 'lines' end)
      from public.inv_adjust a left join public.ims_staff cb on cb.id = a.created_by left join public.ims_staff fb on fb.id = a.confirmed_by
     where a.id = p_adjust_id) end;
$$;

-- ② 신고 → 조정 채우기(묶음 9) — 초안은 만들지 않는다 · 화면이 create 와 line_set 을 부른다
create function public.inv_adjust_from_report(p_report_id bigint) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_adjust_read() then null::jsonb else (
    select jsonb_build_object(
      'report', jsonb_build_object('id', r.id, 'kind', r.kind, 'order_number', r.order_number, 'sku', r.sku, 'qty_expected', r.qty_expected, 'qty_found', r.qty_found, 'note', r.note, 'resolved_at', r.resolved_at, 'created_at', r.created_at),
      'warehouse_id', s.location_id, 'warehouse', s.location_name, 'order_status', s.status,
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('product_id', b.pid, 'sku', b.base_sku, 'bin_id', b.bin_id, 'bin', b.bin, 'picked_this_order', b.qty,
                                                              'ledger', public.inv_adjust_ledger(s.location_name, b.bin, b.base_sku), 'picked', public.inv_adjust_picked(s.location_id, b.bin_id, b.pid),
                                                              'suggested_mode', 'set', 'suggested_qty', 0) order by b.bin), '[]'::jsonb)
                  from (select coalesce(pr.parent_product_id, pr.id) as pid, coalesce(pp.sku, pr.sku) as base_sku, pb.bin_id, pb.bin, sum(pb.qty_base) as qty
                          from public.wms_pick_tasks t join public.wms_pick_task_lines pl on pl.pick_task_id = t.id join public.so_line l on l.id = pl.order_line_id
                          join public.product pr on pr.id = l.product_id left join public.product pp on pp.id = pr.parent_product_id
                          join public.wms_pick_line_bins pb on pb.pick_task_line_id = pl.id and not pb.planned
                         where t.order_id = r.order_id and l.sku = r.sku group by 1, 2, 3, 4) b))
      from public.wms_reports r join public.so s on s.id = r.order_id where r.id = p_report_id and r.kind = 'stock_short') end;
$$;
comment on function public.inv_adjust_from_report(bigint) is '② 판정 20 연결 — stock_short 신고 → 창고(오더의) · 픽 줄의 실제 칸(planned=false · 여럿이면 전부) · 낱개 SKU · 장부 · P · 목표 「이 칸 0」(suggested) — 초안은 만들지 않는다(화면이 inv_adjust_create(report_id) → line_set) · 읽기 권한 ims_can_adjust_read';
revoke all on function public.inv_adjust_list(jsonb) from public, anon;          grant execute on function public.inv_adjust_list(jsonb) to authenticated;
revoke all on function public.inv_adjust_detail(uuid) from public, anon;         grant execute on function public.inv_adjust_detail(uuid) to authenticated;
revoke all on function public.inv_adjust_from_report(bigint) from public, anon;  grant execute on function public.inv_adjust_from_report(bigint) to authenticated;

-- ═══ 8) 재발행 — ims_perm_catalog · 마지막 정의 20260926213035:50~70 바이트 그대로 + stock_adjust 한 줄(wms_receiving_confirm 줄 끝 쉼표) ═══
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
      "stock_adjust":          {"room": "ims", "min_role": "manager", "label": "Stock adjustments — draft and confirm (manager and above · off until switched on)"}
    }
  }'::jsonb;
$$;

-- ═══ 9) 재발행 — inv_layer_apply · 마지막 정의 20260928025627:611~1093 바이트 그대로 · 바뀐 줄 1(IMS 문 목록에 조정 둘) · 더한 줄 6(조정 갈래를 source 로 가름 · 재발행 뒤 revoke 그대로 · 판정 31) ═══
create or replace function inv_layer_apply(p_until date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_t0          timestamptz := clock_timestamp();
  v_baseline    int;
  r             record;
  v_c int; v_u int; v_rows int; v_short int; v_proc int; v_rev int; v_layers int; v_orphan int; v_nz int; v_unk int; v_unkq numeric;
  v_partial int; v_traced int; v_avg int;
  v_po          int := 0;
  v_sale        int := 0;
  v_sale_keys   int := 0;
  v_sale_rev    int := 0;
  v_tr          int := 0;
  v_tr_layers   int := 0;
  v_tr_orphan   int := 0;
  v_tr_nz       int := 0;
  v_tr_unk      int := 0;
  v_tr_unkq     numeric := 0;
  v_tr_unpaired int := 0;
  v_adj         int := 0;
  v_adj_layers  int := 0;
  v_adj_rows    int := 0;
  v_adj_unk     int := 0;
  v_adj_new_nz  int := 0;
  v_asm         int := 0;
  v_asm_layers  int := 0;
  v_asm_rows    int := 0;
  v_asm_partial int := 0;
  v_asm_nz      int := 0;
  v_asm_unpaired int := 0;
  v_cr          int := 0;
  v_cr_layers   int := 0;
  v_cr_traced   int := 0;
  v_cr_avg      int := 0;
  v_cr_unk      int := 0;
  v_cr_nz       int := 0;
  v_layers_po   int := 0;
  v_consume     int := 0;
  v_unknown     int := 0;
  v_shorts      int := 0;
  v_skipped     jsonb;
  -- landed (2026-09-10)
  v_landed_rows int := 0;
  v_landed_amt  numeric := 0;
  v_landed_orph int := 0;
  v_neg         record;
  -- transfer_freight (2026-09-10)
  v_doc         record;
  v_grp         record;
  v_fr_n        int;
  v_fr_basis    numeric;
  v_fr_rows     int := 0;
  v_fr_amt      numeric := 0;
  v_fr_docs     int := 0;
  v_fr_nobasis  int := 0;
  v_fr_nobasis_amt numeric := 0;
  v_fr_orphan   int := 0;
  v_fr_multi    int := 0;
  -- IMS (2026-09-20) — 창구 둘(inv_layer_post_receipt · inv_layer_post_charge)의 반환을 합친다. ⚠️ 원문 변수와 겹치지 않는 v_ims_ 접두어
  v_ims_src     text;
  v_ims_task    text;
  v_ims_docno   text;
  v_ims_j       jsonb;
  v_ims_chg     record;
  v_ims_rcv         int := 0;   v_ims_rcv_layers int := 0;   v_ims_rcv_exist int := 0;   v_ims_rcv_cost numeric := 0;   v_ims_rcv_skipped int := 0;
  v_ims_chg_n       int := 0;   v_ims_chg_rows   int := 0;   v_ims_chg_amt   numeric := 0;
  v_ims_chg_nobasis_amt  numeric := 0;   v_ims_chg_nolayers_amt numeric := 0;   v_ims_chg_already int := 0;   v_ims_chg_skipped int := 0;
  v_ims_chg_unvisited int := 0;   v_ims_chg_unvisited_amt numeric := 0;
  v_ims_skip    jsonb := '[]'::jsonb;
  -- IMS 초과분 (2026-09-20 · over 닫기) — 형제 창구 inv_layer_post_receipt_over 의 반환을 합친다
  v_ims_over    text;
  v_ims_over_n  int := 0;   v_ims_over_layers int := 0;   v_ims_over_skipped int := 0;
  -- IMS off-PO (⑤-6c1 · 2026-09-27) — 형제 창구 inv_layer_post_receipt_off_po 의 반환을 합친다
  v_ims_offpo   text;
  v_ims_offpo_n int := 0;   v_ims_offpo_layers int := 0;   v_ims_offpo_skipped int := 0;
  v_ims_lref    text;                                                                     -- ⑤-6c1 — off-PO 행(<diff>:offpo)은 입고 단위 창구(ims_rcv)의 근거가 아니다(초안 입고에도 서는 행)
  -- IMS 문 · 보조 넷 (2026-09-20) — 창구가 아직 없는 IMS 사건을 사건 종류별로 센다(0 이 아니면 그 창구를 만들 때다). sale_out 은 없다(문 불필요).
  v_ims_gate    jsonb := '{"transfer_in": 0, "transfer_out": 0, "manual_reversal": 0, "adjust_existing": 0, "adjust_new": 0, "assemble_in": 0, "assemble_out": 0, "credit_in": 0}'::jsonb;
begin
  select count(*) into v_baseline from inv_layer where origin_type = 'baseline';
  if v_baseline = 0 then
    raise exception 'inv_layer has no baseline layers — run inv_layer_seed_baseline first';
  end if;

  -- ⭐ IMS 권한 문 (2026-09-20) — 창구 둘은 ims_require_write(receiving · purchasing) 로 auth.uid() 의 권한을 본다.
  --   권한이 없으면 창구가 전부 예외를 던지고 아래 IMS 블록이 그것을 「건너뛰었다」로 세어 버린다 — 재생성이 조용히 반쪽(IMS 만 빠진 레이어 표)이 된다.
  --   그래서 지우기 전에 먼저 막는다. psql 에서는 request.jwt.claims 에 admin 의 sub 를 심고 돌린다(20260918133858 검증 주석 선례).
  if not (ims_can_write('receiving') and ims_can_write('purchasing')) then
    raise exception 'inv_layer_apply: the IMS cost windows (inv_layer_post_receipt · inv_layer_post_charge) need write permission on receiving and purchasing for this login (auth.uid() = %) — from psql, set request.jwt.claims to an admin''s sub first — nothing was rebuilt',
      coalesce(auth.uid()::text, '(null)');
  end if;
  delete from inv_layer_consume;
  delete from inv_layer_cost_add;
  delete from inv_layer where origin_type <> 'baseline';
  perform inv_layer_apply_reset_done();

  -- 날짜순 루프 — ⭐ 사건 9종 전부 (order by occurred_on, seq_hint, po_in 먼저, id · source 필터 없음 · ⭐ 2026-09-21: 같은 날 유입끼리는 po_in 을 맨 앞에 — seq_hint 는 유입·유출만 가른다. 근거는 이 파일 머리 주석)
  for r in
    select id, event_type
      from inv_ledger
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                           'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, case event_type when 'po_in' then 0 else 1 end, id
  loop
    -- ⭐⭐ IMS 문 · 보조 넷 (2026-09-20 · po_in 문의 형제 · Caleb 「문만 낸다 — 창구는 만들지 않는다」) — 창구가 아직 없는 IMS 사건은 보조 함수에 보내지 않고 사건 종류별로 센다.
    -- 왜 안 보내나: 보조 넷(transfer_in · adjust · assemble · credit)은 원가를 inv_cost / 레이어 평균에서 찾는다. IMS 사건은 거기 없어 unit_cost 0 · 'unknown' 레이어가 선다 — po_in 에서 실측된 사고(rcv_unknown 0→2)와 같다.
    -- 왜 창구를 지금 안 만드나: 트랜스퍼 모듈도 IMS 재고조정도 아직 없다 — 쓰지 않을 창구는 맞는지 검증할 표본이 없다. 그 사건을 내는 날 창구를 만들고 여기서 부른다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
    -- 왜 세나: 조용히 지나가면 「IMS 트랜스퍼가 재고에 안 잡힌다」를 아무도 모른다. ims.skipped_by_event 가 0 이 아니면 창구를 만들 때가 됐다는 신호다.
    -- ⚠️ sale_out 은 세지도 막지도 않는다 — 소진은 출처를 안 보는 한 원장 FIFO 가 맞다(inv_layer_fifo_take). po_in 은 아래 분기가 창구로 처리한다.
    -- ⭐ 두 leg 다 막는다(⬜4) — transfer_out · manual_reversal · assemble_out 도 IMS 면 여기서 센다. out 은 대응 in 이 처리하므로 in 만 막아도 레이어는 안 서지만, 아래 *_unpaired 신호가 IMS 것으로 오염된다(그 집계에서도 ims 를 뺀다).
    -- 원문 루프 select(id, event_type)는 바꾸지 않는다 — po_in·sale_out 이 아닌 행만 PK 조회 한 번(po_in 은 아래 분기가 이미 조회한다).
    if r.event_type not in ('po_in', 'sale_out', 'credit_in', 'adjust_existing', 'adjust_new') then   -- adj-a 2026-09-28: 조정 둘도 아래 갈래가 source 로 가른다(IMS → inv_layer_apply_adjust_ims) · ⓒ1 2026-09-25: credit_in 은 아래 갈래가 source 로 가른다(IMS → 창구 inv_layer_apply_credit_ims · 문에서 세지 않는다 · skipped_by_event.credit_in 은 늘 0)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        v_ims_gate := jsonb_set(v_ims_gate, array[r.event_type], to_jsonb(coalesce((v_ims_gate ->> r.event_type)::int, 0) + 1));
        continue;
      end if;
    end if;
    if r.event_type = 'po_in' then
      select * into v_c, v_u from inv_layer_apply_po_in(r.id, p_until);
      v_po := v_po + 1; v_layers_po := v_layers_po + v_c; v_unknown := v_unknown + v_u;
      -- ⭐⭐ IMS 입고 (2026-09-20) — 보조 inv_layer_apply_po_in 은 source='ims' 면 문에서 돌아섰다(0·0). 이 줄의 레이어는 창구 inv_layer_post_receipt 가 만든다.
      -- 왜 여기(루프 안 · 날짜순)이고 끝이 아닌가: 입고 레이어는 **수량** 레이어다 — 뒤에 오는 sale_out·transfer_out 이 FIFO 로 이것을 소진한다.
      --   끝에서 만들면 루프 안의 소진이 이 레이어를 못 보고 short 로 떨어지거나 다른 레이어를 먹어, 실시간 기표(확정 때 창구가 만든 상태)와 재생성 결과가 갈라진다.
      --   비용(cost_add)은 수량이 아니라 금액만 얹으므로 끝(landed·운송비와 같은 층)에 둔다 — 아래 「IMS 비용」 블록.
      -- 왜 창구에 넘기나: 원가 규칙(환율 곱하기 · 기준까지만 · bin 접기)이 창구 안에 있다. 여기 다시 적으면 같은 규칙이 두 곳에 살고 한쪽만 고치면 조용히 갈라진다.
      -- 왜 원장에서 훑나: 이 함수의 일은 「원장에서 레이어를 다시 만드는 것」이다 — 원장에 없으면 레이어도 없다. p_until 도 그대로 걸린다(as-of).
      -- 왜 입고 단위(doc_task_id = po_receipt.id)로 한 번인가: 입고 하나가 원장에 bin 별 여러 줄을 남긴다. 창구는 입고 단위로 일하고 4키 멱등이라 두 번 불러도 안전하지만,
      --   세는 값이 겹치지 않게 done 표(kind 'ims_rcv')로 한 번만 부른다. 같은 입고의 원장 줄은 occurred_on 이 같아(received_on) p_until 경계에 걸쳐 갈라지지 않는다.
      -- 왜 건너뛰고 세나(멈추지 않나 · Caleb 판정 2026-09-20): 이 함수는 검산 도구다. 입고 한 건의 빈칸(환율)으로 검산 자체가 안 되면 도구가 못 쓰게 된다.
      --   건너뛰어도 틀린 값이 들어가지 않는다 — 0 원가 레이어를 만드는 것과 전혀 다르다. 환율을 채우고 다시 돌리면 그 자리에 제대로 선다. 선례: freight_no_basis(기준 0 이면 버리고 금액을 센다).
      --   ⚠️ 몇 건을 왜 건너뛰었는지 반환(ims.receipts_skipped · ims.skip_reasons)에 반드시 남긴다 — 조용히 지나가면 같은 사고의 재판이다.
      select source, doc_task_id, doc_number, line_ref into v_ims_src, v_ims_task, v_ims_docno, v_ims_lref from inv_ledger where id = r.id;   -- 루프 select 는 바꾸지 않는다(원문 무변) — PK 조회 한 번 · ⑤-6c1 line_ref 도
      if v_ims_src = 'ims' and v_ims_task is not null and v_ims_lref not like '%:offpo'                                  -- ⑤-6c1 off-PO 행으로는 inv_layer_post_receipt 를 부르지 않는다(초안 입고라 거부돼 헛 skip 이 남는다)
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_rcv' and d.doc_number = v_ims_task and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_rcv', v_ims_task, '', '');   -- 입고 단위 키 — sku·warehouse 는 not null 이라 빈 문자열
        begin
          v_ims_j := inv_layer_post_receipt(v_ims_task::uuid);
          v_ims_rcv        := v_ims_rcv + 1;
          v_ims_rcv_layers := v_ims_rcv_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
          v_ims_rcv_exist  := v_ims_rcv_exist  + coalesce((v_ims_j->>'layers_existing')::int, 0);   -- 지운 뒤라 0 이어야 한다(생기면 신호 — 다른 축이 같은 4키를 먼저 만들었다)
          v_ims_rcv_cost   := v_ims_rcv_cost   + coalesce((v_ims_j->>'cost_total_cad')::numeric, 0);
        exception when others then
          -- ⚠️ 서브트랜잭션 — 창구가 던진 것(환율 없음 · 확정 아님 · po_line 없음 · base_currency 없음)만 여기로 온다. 그 호출이 넣은 레이어는 서브트랜잭션이 되돌린다 — 이 입고의 레이어는 하나도 서지 않는다.
          v_ims_rcv_skipped := v_ims_rcv_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'receipt', 'number', v_ims_docno, 'id', v_ims_task, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
      -- ⭐ IMS 초과분 (2026-09-20 · over 닫기) — line_ref 가 ':over' 인 po_in 행은 형제 창구 inv_layer_post_receipt_over(diff_id) 가 만든다(free → 0 · billed/credited → 기준 레이어의 unit_cost).
      --   왜 여기(루프 안): 수량 레이어라 뒤의 FIFO 소진이 봐야 한다(위 입고와 같은 이유). 기준 레이어가 먼저 서야 하는데, 초과분 행은 같은 날(received_on)·더 큰 id 라 (occurred_on, seq_hint, id) 순서에서 항상 뒤다.
      --   왜 diff 단위 한 번: 한 차이가 빈 별 여러 행을 남긴다 — done 표 kind 'ims_over'. 거부(기준 레이어 없음 등)는 건너뛰고 ims.over_skipped · skip_reasons 에 센다.
      select raw->>'diff_id' into v_ims_over from inv_ledger where id = r.id and source = 'ims' and line_ref like '%:over';
      if v_ims_over is not null
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_over' and d.doc_number = v_ims_over and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_over', v_ims_over, '', '');
        begin
          v_ims_j := inv_layer_post_receipt_over(v_ims_over::uuid);
          v_ims_over_n      := v_ims_over_n + 1;
          v_ims_over_layers := v_ims_over_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
        exception when others then
          v_ims_over_skipped := v_ims_over_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'over', 'number', v_ims_docno, 'id', v_ims_over, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
      -- ⭐ IMS off-PO (⑤-6c1 · 2026-09-27) — line_ref 가 ':offpo' 인 po_in 행은 형제 창구 inv_layer_post_receipt_off_po(diff_id) 가 만든다(accepted_free → 0 · accepted_billed → diff.unit_price × 환율 · manual).
      --   왜 diff 단위 한 번: 한 차이 = 한 행 · 한 칸이지만 over 와 같은 모양으로 done 표 kind 'ims_offpo' · 거부는 건너뛰고 ims.offpo_skipped · skip_reasons 에 센다.
      select raw->>'diff_id' into v_ims_offpo from inv_ledger where id = r.id and source = 'ims' and line_ref like '%:offpo';
      if v_ims_offpo is not null
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_offpo' and d.doc_number = v_ims_offpo and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_offpo', v_ims_offpo, '', '');
        begin
          v_ims_j := inv_layer_post_receipt_off_po(v_ims_offpo::uuid);
          v_ims_offpo_n      := v_ims_offpo_n + 1;
          v_ims_offpo_layers := v_ims_offpo_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
        exception when others then
          v_ims_offpo_skipped := v_ims_offpo_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'off_po', 'number', v_ims_docno, 'id', v_ims_offpo, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
    elsif r.event_type = 'sale_out' then
      select * into v_rows, v_short, v_proc, v_rev from inv_layer_apply_sale_out(r.id, p_until);
      v_sale := v_sale + 1; v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_sale_keys := v_sale_keys + v_proc; v_sale_rev := v_sale_rev + v_rev;
    elsif r.event_type = 'transfer_in' then
      select * into v_layers, v_rows, v_short, v_orphan, v_nz, v_unk, v_unkq, v_proc from inv_layer_apply_transfer_in(r.id, p_until);
      v_tr := v_tr + 1; v_tr_layers := v_tr_layers + v_layers; v_consume := v_consume + v_rows;
      v_shorts := v_shorts + v_short; v_tr_orphan := v_tr_orphan + v_orphan; v_tr_nz := v_tr_nz + v_nz;
      v_tr_unk := v_tr_unk + v_unk; v_tr_unkq := v_tr_unkq + v_unkq;
    elsif r.event_type in ('adjust_existing', 'adjust_new') then
      -- adj-a 2026-09-28: IMS 축(source ims)은 창구(inv_layer_post_adjust)로 · Cin7 축은 종전 inv_layer_apply_adjust — 같은 반환 모양(credit_in 갈래와 같은 식)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust_ims(r.id, p_until);
      else
        select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust(r.id, p_until);
      end if;
      v_adj := v_adj + 1; v_adj_layers := v_adj_layers + v_layers; v_adj_rows := v_adj_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_adj_unk := v_adj_unk + v_unk; v_adj_new_nz := v_adj_new_nz + v_nz;
    elsif r.event_type = 'assemble_in' then
      select * into v_layers, v_rows, v_short, v_partial, v_nz, v_proc from inv_layer_apply_assemble(r.id, p_until);
      v_asm := v_asm + 1; v_asm_layers := v_asm_layers + v_layers; v_asm_rows := v_asm_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_asm_partial := v_asm_partial + v_partial; v_asm_nz := v_asm_nz + v_nz;
    elsif r.event_type = 'assemble_out' then
      v_asm := v_asm + 1;   -- 부품 out 은 대응 in 이 처리한다(A-2 ④) — 여기서는 세기만
    elsif r.event_type = 'credit_in' then
      -- ⓒ1 2026-09-25: IMS 축(source ims)은 창구(inv_layer_post_credit)로 · Cin7 축은 종전 inv_layer_apply_credit — 두 축이 같은 반환 모양(17-f · 실시간과 재생성이 같은 함수)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit_ims(r.id, p_until);
      else
        select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit(r.id, p_until);
      end if;
      v_cr := v_cr + 1; v_cr_layers := v_cr_layers + v_layers; v_cr_traced := v_cr_traced + v_traced;
      v_cr_avg := v_cr_avg + v_avg; v_cr_unk := v_cr_unk + v_unk; v_cr_nz := v_cr_nz + v_nz;
    else
      v_tr := v_tr + 1;   -- transfer_out · manual_reversal: out leg 는 대응 in 이 처리한다
    end if;
  end loop;

  -- ⭐ 순액 > 0 인데 같은 날짜의 대응 in 이 처리하지 않은 out 키 — (doc, sku, wh, day) · 0 이어야 한다(생기면 신호)
  select count(*) into v_tr_unpaired
    from (select doc_number, sku, warehouse, occurred_on
            from inv_ledger
            where event_type in ('transfer_out', 'manual_reversal')
              and source <> 'ims'                                                       -- ⭐ 2026-09-20 IMS out leg 는 위 문이 세었다(ims.skipped_by_event) — 여기 섞이면 「생기면 신호」가 IMS 것으로 오염된다
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse, occurred_on
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'tr_out' and d.doc_number = o.doc_number and d.sku = o.sku
                          and d.warehouse = o.warehouse and d.day = o.occurred_on);

  -- 순액 > 0 인데 대응 in 이 처리하지 않은 부품 out 키 — 0 이어야 한다(생기면 신호). 순액 ≤ 0(상쇄 소멸) 키는 제외.
  select count(*) into v_asm_unpaired
    from (select doc_number, sku, warehouse
            from inv_ledger
            where event_type = 'assemble_out'
              and source <> 'ims'                                                       -- ⭐ 2026-09-20 같은 이유
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'asm_out' and d.doc_number = o.doc_number and d.sku = o.sku and d.warehouse = o.warehouse);

  -- ═══ PO landed → inv_layer_cost_add (2026-09-10 · 헤더) — 레이어가 전부 만들어진 뒤 집합 연산 한 번 ═══
  -- 가드: 키(4키 + occurred_on) 합이 음수면 예외 — inv_layer_cost_add 에는 amount CHECK 가 없어 이것이 유일한 방어다
  select c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on, sum(c.amount) as amt into v_neg
    from inv_cost c
    where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)
    group by c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on
    having sum(c.amount) < 0
    order by 1, 2, 5 limit 1;
  if found then
    raise exception 'inv_cost landed sum(amount) is negative for % / % / % / % @ %: % — refusing to add cost (revaluation offset? inspect inv_cost)',
      v_neg.doc_number, v_neg.line_ref, v_neg.sku, v_neg.warehouse, v_neg.occurred_on, v_neg.amt;
  end if;

  insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
  select x.id, 'landed',
         sum(c.amount),          -- ⭐ bin 이 여럿이면 합산 (실측 0건 · 방어)
         c.occurred_on,          -- ⚠️ 날짜별로 별개 행 (통관·freight·관세)
         c.doc_number, c.line_ref,
         null                    -- PO landed 는 인보이스 번호가 오지 않는다 (헤더)
    from inv_cost c
    join inv_layer x
      on  x.origin_type = 'purchase'
      and x.doc_number  = c.doc_number
      and x.line_ref    = c.line_ref
      and x.sku         = c.sku
      and x.warehouse   = c.warehouse
    where c.cost_kind = 'landed'
      and (p_until is null or c.occurred_on <= p_until)
    group by x.id, c.occurred_on, c.doc_number, c.line_ref;
  get diagnostics v_landed_rows = row_count;
  select coalesce(sum(amount), 0) into v_landed_amt from inv_layer_cost_add where kind = 'landed';

  -- orphan — 대응 purchase 레이어가 없는 landed 키 (조인에서 조용히 빠지므로 따로 센다)
  select count(*) into v_landed_orph
    from (select distinct c.doc_number, c.line_ref, c.sku, c.warehouse
            from inv_cost c
            where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)) k
    where not exists (select 1 from inv_layer x
                        where x.origin_type = 'purchase' and x.doc_number = k.doc_number and x.line_ref = k.line_ref
                          and x.sku = k.sku and x.warehouse = k.warehouse);

  -- ═══ 트랜스퍼 운송비 → inv_layer_cost_add (kind='transfer_freight' · 2026-09-10 · 헤더 B) — landed 와 같은 자리 ═══
  -- B-4 가드: 저널 행 금액이 음수면 예외 — inv_doc_cost 에도 inv_layer_cost_add 에도 amount CHECK 가 없어 이것이 유일한 방어다
  select d.doc_number, d.ref_number, d.occurred_on, d.amount into v_neg
    from inv_doc_cost d
    where d.doc_type = 'transfer' and d.kind = 'transfer_freight'
      and (p_until is null or d.occurred_on <= p_until)
      and d.amount < 0
    order by d.doc_number, d.occurred_on, d.ref_number limit 1;
  if found then
    raise exception 'inv_doc_cost transfer_freight amount is negative for % / invoice % @ %: % — refusing to distribute (correction? inspect inv_doc_cost)',
      v_neg.doc_number, coalesce(v_neg.ref_number, '(null)'), v_neg.occurred_on, v_neg.amount;
  end if;

  -- 문서 단위 루프 — 배분 기준(도착 레이어 원가 합)은 문서에 딸린 레이어로 정해지므로 문서마다 한 번 계산한다
  for v_doc in
    select doc_number, sum(amount) as amount     -- amount: no_basis 로 떨어질 때 합산할 문서 금액 (p_until 범위)
      from inv_doc_cost
      where doc_type = 'transfer' and kind = 'transfer_freight'
        and (p_until is null or occurred_on <= p_until)
      group by doc_number
      order by doc_number
  loop
    -- B-1 대상 = 도착 창고 레이어만 (IN_TRANSIT 제외) · B-2 기준 = unit_cost × qty (remaining 아님)
    select count(*), coalesce(sum(x.unit_cost * x.qty), 0) into v_fr_n, v_fr_basis
      from inv_layer x
      where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT';
    if v_fr_n = 0 then
      v_fr_orphan := v_fr_orphan + 1;          -- 대응 레이어 없음 (0 이 아니면 신호)
      continue;
    end if;
    if v_fr_basis <= 0 then
      v_fr_nobasis := v_fr_nobasis + 1;        -- 원가 미상(unknown · unit_cost 0) 레이어만 있는 문서 — 0 으로 나누지 않는다
      v_fr_nobasis_amt := v_fr_nobasis_amt + v_doc.amount;   -- ⚠️ 버린 운송비 금액 — Cin7 대조에서 설명된 차이의 크기 (헤더)
      continue;
    end if;

    -- 날짜별 한 묶음 — cost_add 유니크 키에 ref_number 가 없으므로 같은 날 인보이스가 둘이면 합산 1행 (헤더 B-3)
    for v_grp in
      select occurred_on, sum(amount) as amount, count(*) as n,
             string_agg(distinct ref_number, ',' order by ref_number) as ref_number
        from inv_doc_cost
        where doc_type = 'transfer' and kind = 'transfer_freight' and doc_number = v_doc.doc_number
          and (p_until is null or occurred_on <= p_until)
        group by occurred_on
        order by occurred_on
    loop
      if v_grp.n > 1 then v_fr_multi := v_fr_multi + 1; end if;
      -- B-2 배분: share = round(문서금액 × 레이어원가 / 합, 6) · 마지막 레이어(id 순) = 문서금액 − 앞선 share 합 (remainder on last)
      insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
      select t.id, 'transfer_freight',
             case when t.rn = t.cnt
                  then v_grp.amount - coalesce(sum(t.share) over (order by t.rn rows between unbounded preceding and 1 preceding), 0)
                  else t.share end,
             v_grp.occurred_on, v_doc.doc_number, t.line_ref, v_grp.ref_number
        from (select x.id, x.line_ref,
                     round(v_grp.amount * (x.unit_cost * x.qty) / v_fr_basis, 6) as share,
                     row_number() over (order by x.id) as rn,
                     count(*) over () as cnt
                from inv_layer x
                where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT') t;
      get diagnostics v_rows = row_count;
      v_fr_rows := v_fr_rows + v_rows;
    end loop;
    v_fr_docs := v_fr_docs + 1;
  end loop;
  select coalesce(sum(amount), 0) into v_fr_amt from inv_layer_cost_add where kind = 'transfer_freight';


  -- ═══ IMS 비용 → inv_layer_cost_add (kind='landed' · 2026-09-20) — landed·운송비와 같은 층 · 창구 inv_layer_post_charge 에 넘긴다 ═══
  -- 왜 여기(끝)인가: 비용은 수량이 아니라 금액만 얹는다 — FIFO 소진에 영향이 없어 Cin7 landed·운송비와 같은 자리다(입고 레이어는 루프 안 — 위).
  -- 왜 레이어에서 훑나(Caleb 판정 2026-09-20): 비용은 원장에 사건을 남기지 않아(금액만 얹는다) 원장으로 훑을 수 없다. 레이어가 없으면 얹을 곳도 없으니 부를 이유가 없다.
  --   길: inv_layer(cost_source='po_line').line_ref = po_line.id::text → po_line.po_id = po_charge_alloc.po_id → po_charge_alloc.po_charge_id = po_charge.id (confirmed).
  --   비용 문서 단위로 한 번(한 비용이 여러 발주에 배분된다 — exists 로 접는다) · 순서 고정.
  -- 왜 창구에 넘기나: 배분 규칙(환율 · unit_cost×qty 비례 · 6자리 · 끝수는 마지막 · 기준 0 버림 · 배분 줄 단위 멱등)이 창구 안에 있다 — 두 곳에 살게 하지 않는다.
  -- p_until: 창구는 occurred_on = po_charge.charge_date 로 얹는다 — 그래서 charge_date <= p_until 로 고른다(as-of 재생성).
  -- 방문하지 않은 확정 비용(배분된 발주 어디에도 IMS 레이어가 없는 것 — 예: 환율이 없어 입고를 건너뛴 발주)은 따로 센다(charges_unvisited · 금액 CAD)
  --   — 「버린 금액」의 그림이 빠지지 않게. Cin7 대조에서 이 금액만큼은 설명된 차이다(정본 D 의 freight_no_basis_amount 와 같은 구실).
  for v_ims_chg in
    select c.id, c.charge_number, c.charge_date
      from po_charge c
      where c.status = 'confirmed' and c.confirmed_at is not null
        and (p_until is null or c.charge_date <= p_until)
        and exists (select 1
                      from po_charge_alloc a
                      join po_line  pl on pl.po_id = a.po_id
                      join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                      where a.po_charge_id = c.id)
      order by c.charge_date, c.charge_number, c.id       -- ⚠️ 순서 고정 · charge_number 는 (supplier_id, charge_number) 유니크라 id 까지 건다
  loop
    begin
      v_ims_j := inv_layer_post_charge(v_ims_chg.id);
      v_ims_chg_n            := v_ims_chg_n + 1;
      v_ims_chg_rows         := v_ims_chg_rows         + coalesce((v_ims_j->>'layers_touched')::int, 0);
      v_ims_chg_amt          := v_ims_chg_amt          + coalesce((v_ims_j->>'amount_posted_cad')::numeric, 0);
      v_ims_chg_nobasis_amt  := v_ims_chg_nobasis_amt  + coalesce((v_ims_j->>'no_basis_amount_cad')::numeric, 0);    -- 기준 0 이라 버린 금액(정본 D)
      v_ims_chg_nolayers_amt := v_ims_chg_nolayers_amt + coalesce((v_ims_j->>'no_layers_amount_cad')::numeric, 0);   -- 배분 줄 중 레이어 없는 발주로 간 금액
      v_ims_chg_already      := v_ims_chg_already      + coalesce((v_ims_j->>'already_posted_allocs')::int, 0);      -- cost_add 를 지운 뒤라 0 이어야 한다(생기면 신호)
    exception when others then
      v_ims_chg_skipped := v_ims_chg_skipped + 1;
      v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'charge', 'number', v_ims_chg.charge_number, 'id', v_ims_chg.id, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  -- 방문하지 않은 확정 비용 — 위 exists 가 거른 것. 금액은 창구와 같은 규칙으로 CAD(기준통화면 ×1 · 아니면 × exchange_rate). ⚠️ 환율 null 인 외화 비용은 합에서 빠진다(확정 게이트 ⑥ 뒤엔 없다 · 건수에는 든다).
  select count(*), coalesce(sum(c.total_amount * case when cu.code is not distinct from k.value then 1 else c.exchange_rate end), 0)
    into v_ims_chg_unvisited, v_ims_chg_unvisited_amt
    from po_charge c
    join ref_currency cu on cu.id = c.currency_id
    left join inv_config k on k.key = 'base_currency'
    where c.status = 'confirmed' and c.confirmed_at is not null
      and (p_until is null or c.charge_date <= p_until)
      and not exists (select 1
                        from po_charge_alloc a
                        join po_line  pl on pl.po_id = a.po_id
                        join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                        where a.po_charge_id = c.id);

  select coalesce(jsonb_object_agg(event_type, n), '{}'::jsonb) into v_skipped
    from (select event_type, count(*) as n
            from inv_ledger
            where event_type not in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                                     'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
              and (p_until is null or occurred_on <= p_until)
            group by event_type) s;

  return jsonb_build_object(
    'until',                     p_until,
    'processed_po_in',           v_po,
    'processed_sale_out',        v_sale,
    'sale_keys_processed',       v_sale_keys,
    'sale_keys_fully_reversed',  v_sale_rev,
    'processed_transfer',        v_tr,
    'transfer_layers_created',   v_tr_layers,
    'transfer_orphan_in',        v_tr_orphan,
    'transfer_keys_net_zero',    v_tr_nz,
    'transfer_unknown_layers',   v_tr_unk,
    'transfer_unknown_qty',      v_tr_unkq,
    'transfer_out_unpaired',     v_tr_unpaired,
    'processed_adjust',          v_adj,
    'adjust_layers_created',     v_adj_layers,
    'adjust_consume_rows',       v_adj_rows,
    'adjust_unknown_layers',     v_adj_unk,
    'adjust_new_net_zero',       v_adj_new_nz,
    'processed_assembly',        v_asm,
    'assembly_layers_created',   v_asm_layers,
    'assembly_consume_rows',     v_asm_rows,
    'assembly_partial_cost',     v_asm_partial,
    'assembly_net_zero',         v_asm_nz,
    'assembly_out_unpaired',     v_asm_unpaired,
    'processed_credit',          v_cr,
    'credit_layers_created',     v_cr_layers,
    'credit_traced',             v_cr_traced,
    'credit_avg',                v_cr_avg,
    'credit_unknown_layers',     v_cr_unk,
    'credit_net_zero',           v_cr_nz,
    'landed_rows',               v_landed_rows,
    'landed_amount',             v_landed_amt,
    'landed_orphan',             v_landed_orph,
    'freight_rows',              v_fr_rows,
    'freight_amount',            v_fr_amt,
    'freight_docs',              v_fr_docs,
    'freight_no_basis',          v_fr_nobasis,
    'freight_no_basis_amount',   v_fr_nobasis_amt,
    'freight_orphan',            v_fr_orphan,
    'freight_multi_ref',         v_fr_multi,
    -- ⭐ IMS (2026-09-20) — 한 칸에 중첩한다. ⚠️ jsonb_build_object 는 인자 100개 한도(키 50) — 기존 45키에 평면으로 더하면 넘는다. 기존 45칸은 이름·뜻 무변.
    'ims', jsonb_build_object(
      'receipts_posted',           v_ims_rcv,               -- 창구가 레이어를 만든 입고 수
      'layers_created',            v_ims_rcv_layers,        -- 그 레이어 행 수(라인 단위 · bin 접힘)
      'layers_existing',           v_ims_rcv_exist,         -- 0 이어야 한다
      'layers_cost_cad',           v_ims_rcv_cost,          -- Σ qty × unit_cost(CAD)
      'receipts_skipped',          v_ims_rcv_skipped,       -- ⚠️ 창구가 거부해 건너뛴 입고 수 — skip_reasons 에 문장
      'charges_posted',            v_ims_chg_n,
      'charge_rows',               v_ims_chg_rows,          -- cost_add 행 수
      'charge_amount_cad',         v_ims_chg_amt,
      'charge_no_basis_amount_cad',  v_ims_chg_nobasis_amt,   -- 버린 금액(정본 D)
      'charge_no_layers_amount_cad', v_ims_chg_nolayers_amt,  -- 버린 금액(레이어 없는 발주)
      'charge_already_posted',     v_ims_chg_already,       -- 0 이어야 한다
      'charges_skipped',           v_ims_chg_skipped,       -- ⚠️ 창구가 거부해 건너뛴 비용 수
      'charges_unvisited',         v_ims_chg_unvisited,     -- 배분된 발주 어디에도 IMS 레이어가 없어 부르지 않은 확정 비용 수
      'charges_unvisited_amount_cad', v_ims_chg_unvisited_amt,  -- 그 금액 — 설명된 차이
      'over_posted',               v_ims_over_n,            -- ⭐ 2026-09-20 초과분(over 닫기) — 창구가 레이어를 만든 차이 수
      'over_layers',               v_ims_over_layers,
      'over_skipped',              v_ims_over_skipped,      -- ⚠️ 창구가 거부해 건너뛴 차이 수 — skip_reasons kind 'over'
      'offpo_posted',              v_ims_offpo_n,           -- ⭐ ⑤-6c1 off-PO — 창구가 레이어를 만든 차이 수
      'offpo_layers',              v_ims_offpo_layers,
      'offpo_skipped',             v_ims_offpo_skipped,     -- ⚠️ 창구가 거부해 건너뛴 차이 수 — skip_reasons kind 'off_po'
      'skipped_by_event',          v_ims_gate,              -- ⭐ 2026-09-20 창구가 아직 없어 보조 함수에 보내지 않은 IMS 사건 수(종류별 · 여덟 키 항상) — 0 이 아니면 그 사건의 창구를 만들 때다
      'skip_reasons',              v_ims_skip),             -- [{kind receipt|charge · number · id · sqlstate · error}] — 이유 문장 그대로
    'skipped_by_type',           v_skipped,
    'layers_created',            v_layers_po,
    'consume_rows',              v_consume,
    'cost_unknown_layers',       v_unknown,
    'short_events',              v_shorts,
    'elapsed_ms',                round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;
revoke all on function public.inv_layer_apply(date) from public, anon, authenticated;   -- ⭐ 판정 31 — 재생성 계열은 사람이 psql(소유자)로만 · 재발행마다 같은 파일에 다시 적는다

-- ═══ 10) 재발행 — wms_health_check · 마지막 정의 20260928025627:1240~1495 바이트 그대로 · 더한 줄 12(adj_nl · 170 adjust_confirmed_no_ledger) ═══
create or replace function public.wms_health_check() returns table(sort integer, check_key text, category text, title text, hint text, fail_count bigint, sample jsonb)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  c_stale constant interval := interval '24 hours';   -- packed_not_finalized · long_hold
  c_claim constant interval := interval '8 hours';    -- stale_claim(근무 하루)
begin
  if not public.ims_can_view('wms_manage') then                        -- ⭐ 첫 줄 문
    raise exception 'You cannot view WMS health — this needs the wms_manage screen — ask an admin';
  end if;
  return query
  with
  line_split as (
    select s.so_number, l.line_no, l.sku,
           (l.qty_ordered - l.qty_removed) * l.pack_factor as need_ea,
           sum(pl.assigned_base) as assigned_ea
      from public.so s
      join public.so_line l on l.so_id = s.id
      join public.wms_pick_task_lines pl on pl.order_line_id = l.id
      join public.wms_pick_tasks t on t.id = pl.pick_task_id and t.order_id = s.id
     where s.status in ('picking', 'packed')
     group by s.so_number, l.line_no, l.sku, l.qty_ordered, l.qty_removed, l.pack_factor
    having sum(pl.assigned_base) is distinct from (l.qty_ordered - l.qty_removed) * l.pack_factor
  ),
  short_nd as (
    select s.so_number, t.batch_label, l.sku, pl.assigned_base, pl.picked_base
      from public.wms_pick_task_lines pl
      join public.wms_pick_tasks t on t.id = pl.pick_task_id
      join public.so s on s.id = t.order_id
      join public.so_line l on l.id = pl.order_line_id
     where pl.status = 'short'
       and not exists (select 1 from public.wms_worker_mistakes m
                        where m.order_id = s.id and m.sku = l.sku and m.reason in ('short_pick', 'resolved_pack_recovery') and m.voided_at is null)
       and not exists (select 1 from public.wms_reports r                 -- ⑤-5c3: 「Not enough stock」 신고(판정 20 · 24-b 로 갈린 쪽)도 모자람을 설명한다 · resolved 무관
                        where r.order_id = s.id and r.sku = l.sku and r.kind = 'stock_short')
  ),
  pick_over as (
    select s.so_number, t.batch_label, l.sku, pl.assigned_base, pl.picked_base
      from public.wms_pick_task_lines pl
      join public.wms_pick_tasks t on t.id = pl.pick_task_id
      join public.so s on s.id = t.order_id
      join public.so_line l on l.id = pl.order_line_id
     where pl.picked_base > pl.assigned_base
  ),
  fin_pair as (
    select s.so_number, s.status, (f.order_id is not null) as has_finalize_row, f.finalized_at
      from public.so s
      left join public.wms_order_finalize f on f.order_id = s.id
     where (s.status = 'packed' and f.order_id is null)
        or (f.order_id is not null and s.status in ('draft', 'confirmed', 'at_wms', 'picking', 'cancelled'))
  ),
  orphan_task as (
    select s.so_number, s.status, count(t.id) as pick_tasks, string_agg(t.batch_label, ', ' order by t.batch_label) as batches
      from public.so s
      join public.wms_pick_tasks t on t.order_id = s.id
     where s.status in ('draft', 'confirmed', 'at_wms', 'cancelled')
     group by s.id, s.so_number, s.status
  ),
  orphan_pack as (
    select k.id as pack_task_id, k.batch_label, s.so_number, k.status as pack_status, t.status as pick_status
      from public.wms_pack_tasks k
      join public.so s on s.id = k.order_id
      left join public.wms_pick_tasks t on t.id = k.pick_task_id
     where t.id is null or t.status is distinct from 'completed'
  ),
  wave_state as (
    select w.id, w.label, w.status,
           count(t.id) as member_batches,
           count(t.id) filter (where t.status = 'completed') as completed_batches
      from public.wms_waves w
      left join public.wms_pick_tasks t on t.wave_id = w.id
     group by w.id, w.label, w.status
    having count(t.id) = 0
        or (w.status = 'completed' and count(t.id) <> count(t.id) filter (where t.status = 'completed'))
        or (w.status <> 'completed' and count(t.id) > 0 and count(t.id) = count(t.id) filter (where t.status = 'completed'))
  ),
  hold_leak as (
    select h.id as hold_id, h.task_kind, h.task_id, h.worker, h.held_at,
           coalesce(p.status, k.status, w.status) as task_status,
           (coalesce(p.held_by, k.held_by, w.held_by) is not null) as task_held,
           h.rn as open_rank
      from (select th.*, row_number() over (partition by th.task_kind, th.task_id order by th.held_at desc) as rn
              from public.wms_task_holds th
             where th.resumed_at is null and th.task_kind in ('pick', 'pack', 'wave')) h
      left join public.wms_pick_tasks p on h.task_kind = 'pick' and p.id = h.task_id
      left join public.wms_pack_tasks k on h.task_kind = 'pack' and k.id = h.task_id
      left join public.wms_waves      w on h.task_kind = 'wave' and w.id = h.task_id
     where h.rn > 1                                                     -- 같은 과제에 열린 보류가 둘 = 닫기가 유실된 지문
        or (coalesce(p.id, k.id, w.id) is not null                      -- 지워진 과제(되돌리기)는 의도 · 표시 안 함
            and not (coalesce(p.status, k.status, w.status) = 'pending' and coalesce(p.held_by, k.held_by, w.held_by) is not null))
    union all                                                            -- ⑤-6b 입고 가지(판정 37 「receipt 는 ⑤-6」): 열린 보류가 draft 아닌 입고 · 창고 Complete 된 입고 · 한 입고에 둘
    select h.id, 'receipt'::text, null::bigint, h.worker, h.held_at,
           r.status, exists (select 1 from public.wms_receipt_complete c where c.receipt_id = r.id and c.completed), h.rn
      from (select th.*, row_number() over (partition by th.receipt_id order by th.held_at desc) as rn
              from public.wms_task_holds th
             where th.resumed_at is null and th.receipt_id is not null) h
      join public.po_receipt r on r.id = h.receipt_id
     where h.rn > 1
        or r.status <> 'draft'
        or exists (select 1 from public.wms_receipt_complete c where c.receipt_id = r.id and c.completed)
  ),
  recv_nc as (                                                           -- ⑤-6b 창고 Complete 뒤 24h 넘게 오피스 확정이 없다(여전히 draft)
    select r.receipt_number, p.po_number, c.completed_at, c.completed_by
      from public.wms_receipt_complete c
      join public.po_receipt r on r.id = c.receipt_id
      join public.po p on p.id = r.po_id
     where c.completed and r.status = 'draft' and c.completed_at < now() - c_stale
  ),
  recv_stale as (                                                        -- ⑤-6b 초안인데 작업 줄 0 · 만든 지 24h 넘음(열어 두고 아무것도 안 셈)
    select r.receipt_number, p.po_number, r.created_at, r.created_by
      from public.po_receipt r
      join public.po p on p.id = r.po_id
     where r.status = 'draft' and r.created_at < now() - c_stale
       and not exists (select 1 from public.po_receipt_work w where w.receipt_id = r.id)
  ),
  offpo_und as (                                                         -- ⑤-6c1 off-PO 가 정해지지 않은 채 24h(판정 43 대가 — 선반에는 있고 장부에는 없다)
    select r.receipt_number, pr.sku, d.received_qty, (d.placed_at is not null) as on_shelf, b.name as bin, d.created_at
      from public.po_receipt_diff d
      join public.po_receipt r on r.id = d.receipt_id
      join public.product pr on pr.id = d.product_id
      left join public.ref_bin b on b.id = d.bin_id
     where d.kind = 'off_po' and d.resolved_at is null and d.created_at < now() - c_stale
  ),
  offpo_rej as (                                                         -- ⑤-6c1 거절됐는데 선반에서 뺐다는 확인이 없다 24h
    select r.receipt_number, pr.sku, d.received_qty, b.name as bin, d.resolved_at, d.resolved_by
      from public.po_receipt_diff d
      join public.po_receipt r on r.id = d.receipt_id
      join public.product pr on pr.id = d.product_id
      left join public.ref_bin b on b.id = d.bin_id
     where d.kind = 'off_po' and d.resolution = 'rejected' and d.bin_id is not null and d.removed_at is null and d.resolved_at < now() - c_stale
  ),
  picking_nt as (
    select s.so_number, s.picking_at, s.picking_by
      from public.so s
     where s.status = 'picking' and not exists (select 1 from public.wms_pick_tasks t where t.order_id = s.id)
  ),
  packed_nf as (
    select s.so_number, v.pick_batches, v.packs_done, max(k.completed_at) as last_pack_at
      from public.so s
      join public.wms_order_pack_progress v on v.order_id = s.id
      join public.wms_pack_tasks k on k.order_id = s.id and k.status = 'completed'
     where s.status = 'picking' and v.all_packed
     group by s.id, s.so_number, v.pick_batches, v.packs_done
    having max(k.completed_at) < now() - c_stale
  ),
  stale_claim as (
    select 'pick' as kind, t.id as task_id, t.batch_label as label, t.assigned_to,
           greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at) as last_activity
      from public.wms_pick_tasks t
      left join public.wms_pick_task_lines l on l.pick_task_id = t.id
     where t.status = 'in_progress' and t.wave_id is null
     group by t.id
    having greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at) < now() - c_claim
    union all
    select 'pack', t.id, t.batch_label, t.assigned_to,
           greatest(coalesce(max(l.verified_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at)
      from public.wms_pack_tasks t
      left join public.wms_pack_task_lines l on l.pack_task_id = t.id
     where t.status = 'in_progress'
     group by t.id
    having greatest(coalesce(max(l.verified_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at) < now() - c_claim
    union all
    select 'wave', w.id, w.label, w.assigned_to,
           greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(w.started_at, 'epoch'::timestamptz), coalesce(w.heartbeat_at, 'epoch'::timestamptz), w.created_at)
      from public.wms_waves w
      left join public.wms_pick_tasks t on t.wave_id = w.id
      left join public.wms_pick_task_lines l on l.pick_task_id = t.id
     where w.status = 'in_progress'
     group by w.id
    having greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(w.started_at, 'epoch'::timestamptz), coalesce(w.heartbeat_at, 'epoch'::timestamptz), w.created_at) < now() - c_claim
  ),
  long_hold as (
    select h.id as hold_id, h.task_kind, h.task_id, h.worker, h.held_at, h.source
      from public.wms_task_holds h
     where h.resumed_at is null and h.task_kind in ('pick', 'pack', 'wave') and h.held_at < now() - c_stale
       and ((h.task_kind = 'pick' and exists (select 1 from public.wms_pick_tasks p where p.id = h.task_id))
         or (h.task_kind = 'pack' and exists (select 1 from public.wms_pack_tasks k where k.id = h.task_id))
         or (h.task_kind = 'wave' and exists (select 1 from public.wms_waves w where w.id = h.task_id)))
  ),
  adj_nl as (                                                            -- adj-a 2026-09-28 확정된 조정인데 원장 행이 없다(delta 0 줄뿐인 문서는 제외)
    select a.adjust_number, a.confirmed_at, a.warehouse
      from public.inv_adjust a
     where a.status = 'confirmed'
       and exists (select 1 from public.inv_adjust_line l where l.adjust_id = a.id and l.delta <> 0)
       and not exists (select 1 from public.inv_ledger e where e.doc_type = 'adjustment' and e.doc_number = a.adjust_number and e.source = 'ims')
  ),
  last_rel as (
    select max(s.at_wms_at) as last_at,
           to_char(max(s.at_wms_at) at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI') as last_at_toronto,
           round(extract(epoch from (now() - max(s.at_wms_at))) / 60)::int as minutes_ago
      from public.so s
  )
  select 10, 'line_split_sum', 'critical', 'Line split sum',
    'For every line of an order in warehouse work (Working / Finalized) the batch assignments in base units must add up to (ordered - removed) x pack factor. A row here means a split lost or double-counted units. Lines that have no batch line at all are not listed here (see Working order without batches).',
    (select count(*) from line_split), (select jsonb_agg(t) from (select * from line_split limit 8) t)
  union all
  select 20, 'short_no_disc', 'warn', 'Short pick without a mistake row',
    'A pick line marked short with neither a short-pick mistake row nor a Not enough stock report for the same order and SKU (voided mistake rows do not count; a report explains the shortfall whether or not it is resolved) - the shortfall vanished silently. Match key: order + SKU; verify if unsure.',
    (select count(*) from short_nd), (select jsonb_agg(t) from (select * from short_nd limit 8) t)
  union all
  select 30, 'pick_over', 'warn', 'Picked exceeds assigned',
    'Picked base is greater than assigned at the pick level. Over-quantity should surface at pack (over-pick), not pick.',
    (select count(*) from pick_over), (select jsonb_agg(t) from (select * from pick_over limit 8) t)
  union all
  select 40, 'finalize_pair', 'critical', 'Finalized order without a finalize record (or the reverse)',
    'An order in Finalized (packed) must have exactly one finalize record, and a finalize record must not exist on an order that has not been finalized yet. A row means Finalize or Undo Finalize was interrupted - the office cannot fulfil it until the pair is repaired.',
    (select count(*) from fin_pair), (select jsonb_agg(t) from (select * from fin_pair limit 8) t)
  union all
  select 50, 'orphan_task', 'critical', 'Batches on an order that left warehouse work',
    'Pick batches exist for an order whose status is not Working or Finalized (the office recalled or cancelled it, or a rollback did not clean up). Pickers will see a red banner on these batches - undo the batches (Rollback tab).',
    (select count(*) from orphan_task), (select jsonb_agg(t) from (select * from orphan_task limit 8) t)
  union all
  select 60, 'orphan_pack', 'warn', 'Orphaned pack tasks',
    'A pack batch whose paired pick batch is missing or not completed. (An order can be Working overall while some of its batches pack - that is normal and not flagged.)',
    (select count(*) from orphan_pack), (select jsonb_agg(t) from (select * from orphan_pack limit 8) t)
  union all
  select 70, 'wave_state', 'warn', 'Wave consistency',
    'A wave with no member batches, a completed wave with unfinished batches, or a wave whose batches are all done but the wave never closed (an interrupted finish).',
    (select count(*) from wave_state), (select jsonb_agg(t) from (select * from wave_state limit 8) t)
  union all
  select 80, 'hold_leak', 'warn', 'Open hold vs batch state',
    'An open hold row (not resumed) whose batch is not pending-and-held, or two open rows on one batch - the resume close was lost, so its hold time will silently not be subtracted in Stats. Deleted batches (rollback) are intentionally not flagged. Receipt rows: an open hold on a receipt that is no longer a draft, or already completed in the warehouse, or two open holds on one receipt.',
    (select count(*) from hold_leak), (select jsonb_agg(t) from (select * from hold_leak limit 8) t)
  union all
  select 90, 'picking_no_tasks', 'critical', 'Working order without batches',
    'An order in Working (picking) with no pick batches at all. Split & Waves always creates the batches in the same transaction, and Undo Split returns the order to Released to WMS - a row here means an interrupted rollback. Roll it back or re-release it.',
    (select count(*) from picking_nt), (select jsonb_agg(t) from (select * from picking_nt limit 8) t)
  union all
  select 100, 'packed_not_finalized', 'warn', 'All batches packed but not finalized for 24h',
    'Every batch of the order is packed (it is on the Fulfillment board) but nobody finalized it for more than 24 hours after the last pack. The goods are sitting on the floor - finish the pallets and press Finalize.',
    (select count(*) from packed_nf), (select jsonb_agg(t) from (select * from packed_nf limit 8) t)
  union all
  select 110, 'stale_claim', 'warn', 'Batch claimed but silent for 8h',
    'A pick/pack batch or wave still in progress with no scan, start or heartbeat for more than 8 hours (last activity = latest of line scan time, started_at, heartbeat_at, created_at - the same rule as auto-hold). Auto-hold should have returned it to the pool after 10 minutes - a row here usually means the auto-hold job is not running. Release it from the Status tab.',
    (select count(*) from stale_claim), (select jsonb_agg(t) from (select * from stale_claim limit 8) t)
  union all
  select 120, 'long_hold', 'warn', 'Batch on hold for more than 24h',
    'A pick/pack batch or wave has been on hold (not resumed) for more than 24 hours. Someone started it and nobody finished it - resume it or roll the order back.',
    (select count(*) from long_hold), (select jsonb_agg(t) from (select * from long_hold limit 8) t)
  union all
  select 130, 'receipt_completed_not_confirmed', 'warn', 'Receipt completed in the warehouse but not confirmed for 24h',
    'The warehouse pressed Complete more than 24 hours ago and the office has not confirmed the receipt (it is still a draft) - the goods are in their bins but not in the books. Confirm it in Purchase Receipts, or reopen it if the count was wrong.',
    (select count(*) from recv_nc), (select jsonb_agg(t) from (select * from recv_nc limit 8) t)
  union all
  select 140, 'stale_receipt_draft', 'warn', 'Receipt draft with nothing counted for 24h',
    'A receipt was started more than 24 hours ago and nothing has been counted on it. Usually someone pressed Start and walked away - delete the empty draft (Receiving tab) or count the goods.',
    (select count(*) from recv_stale), (select jsonb_agg(t) from (select * from recv_stale limit 8) t)
  union all
  select 150, 'off_po_undecided', 'warn', 'Off-PO item waiting for a decision for 24h',
    'An item scanned at the dock that is not on the PO has been waiting more than 24 hours for the office to accept (free or billed) or reject it. Until then it sits on the shelf but not in the books - decide it in Purchase Receipts (the WMS Admin Receiving tab links there).',
    (select count(*) from offpo_und), (select jsonb_agg(t) from (select * from offpo_und limit 8) t)
  union all
  select 160, 'off_po_rejected_on_shelf', 'warn', 'Rejected off-PO item still on the shelf for 24h',
    'The office rejected an off-PO item more than 24 hours ago and nobody confirmed taking it off the shelf. Pickers may find stock that is not in the books - take it off and press Removed in the receiving screen.',
    (select count(*) from offpo_rej), (select jsonb_agg(t) from (select * from offpo_rej limit 8) t)
  union all
  select 170, 'adjust_confirmed_no_ledger', 'critical', 'Confirmed stock adjustment without ledger rows',
    'A confirmed stock adjustment with a non-zero line has no ledger rows - the confirm transaction was interrupted between the document and the ledger. Stock is wrong until inv_post_adjust is run by the DB owner.',
    (select count(*) from adj_nl), (select jsonb_agg(t) from (select * from adj_nl limit 8) t)
  union all
  select 200, 'last_release', 'info', 'Last release to WMS',
    'Newest Release to WMS from the office (Toronto time) - the signal that orders are still flowing into the warehouse. A long gap is normal when the office has nothing to release.',
    0::bigint, (select jsonb_build_object('last_at', last_at, 'last_at_toronto', last_at_toronto, 'minutes_ago', minutes_ago) from last_rel)
  order by 1;
end
$$;
