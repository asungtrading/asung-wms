-- ─────────────────────────────────────────────────────────────
-- 재고 사건 ② 트랜스퍼 · 첫 몫 「칸 옮기기(같은 창고)」 — DB 창구 (Asung-IMS · trf-a · 2026-09-28)
--   정본(뒤에 적는다): so-module §26(판정 60~63 · 묶음 열) · ledger-design 1부 4·5 IMS 축 · 4부 「보조 함수 넷」 · 조사 trf-1
--   든 것: ① inv_move · inv_move_line · inv_move_number_seq · inv_move_next_number ② 문 inv_move_require(ims_require_write(stock_move) + ims_can_warehouse · 판정 63)
--         ③ 읽기 조각 inv_move_open_plans(열린 픽 계획 · 판정 62) · inv_move_eval(줄 평가 한 번 · materialized · 판정 54) ④ 초안 create · line_set · line_remove · delete
--         ⑤ preview · confirm(확정 길 하나) · now(한 트랜잭션 · 창고 스캔) ⑥ 원장 inv_post_move(줄 = 행 둘 · 레이어 무접촉) ⑦ 읽기 list · detail
--         ⑧ 재발행 셋 — ims_perm_catalog(20260928142722:546~568 · 더한 줄 1 · 바뀐 줄 1) · inv_layer_apply(20260928142722:570~1058 · 더한 줄 6 · 바뀐 줄 1 · bin_move 갈래)
--                      · wms_health_check(20260928142722:1061~1327 · 더한 줄 40 · 검사 셋 175 · 180 · 185)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 이 창구는 IMS 안에서만 선다(판정 51 · 60)
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

-- ═══ 1) 표 · 시퀀스 · 채번 (묶음 5 · inv_adjust 선례 20260928142722:38~107) ═══
create sequence public.inv_move_number_seq start with 1 increment by 1;
create function public.inv_move_next_number() returns text
  language sql volatile
  set search_path = public, pg_temp
as $$
  select 'MV-' || lpad(nextval('public.inv_move_number_seq')::text, 5, '0');
$$;
comment on function public.inv_move_next_number() is '칸 옮기기 번호 채번 — MV- + 다섯 자리(inv_move_number_seq · 1 부터 · 지운 초안의 번호는 빈다 · 판정 55 · 창고 간 트랜스퍼는 뒤 차수에 따로 TRF-). 2026-09-28';
revoke all on sequence public.inv_move_number_seq from public, anon;
grant usage, select on sequence public.inv_move_number_seq to authenticated;
revoke all on function public.inv_move_next_number() from public, anon;
grant execute on function public.inv_move_next_number() to authenticated;

create table public.inv_move (
  id            uuid primary key default gen_random_uuid(),
  move_number   text not null unique default public.inv_move_next_number(),
  status        text not null default 'draft',
  warehouse_id  uuid not null references public.ref_warehouse (id) on delete no action,
  warehouse     text not null,                                                            -- 이름 원문(원장 키 · inv_ledger.warehouse)
  note          text,
  posted_on     date,                                                                     -- 확정한 날(ims_today) = 원장 occurred_on
  plans_moved   jsonb,                                                                    -- 판정 62 — 확정 때 도착 칸으로 바꾼 기다리는 과제의 계획(감사 기록 · [{task_id, batch_label, so_number, line_id, sku, from_bin, to_bin, qty, split}])
  created_by    uuid references public.ims_staff (id) on delete no action,
  confirmed_by  uuid references public.ims_staff (id) on delete no action,
  confirmed_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,
  constraint inv_move_status_ck  check (status in ('draft', 'confirmed')),
  constraint inv_move_confirm_ck check ((status = 'confirmed') = (confirmed_at is not null) and (status = 'confirmed') = (posted_on is not null))
);
create table public.inv_move_line (
  id            uuid primary key default gen_random_uuid(),
  move_id       uuid not null references public.inv_move (id) on delete cascade,
  line_no       int  not null,
  product_id    uuid not null references public.product (id) on delete no action,
  sku           text not null,                                                            -- 낱개 SKU(원장 키)
  from_bin_id   uuid not null references public.ref_bin (id) on delete no action,
  from_bin      text not null,
  to_bin_id     uuid not null references public.ref_bin (id) on delete no action,
  to_bin        text not null,
  qty           numeric not null,                                                         -- 옮기는 낱개 EA(팩 · 세트 환산은 화면)
  seen_ledger   numeric not null,                                                         -- 줄을 적을 때 본 출발 칸 장부(CAS)
  seen_picked   numeric not null,                                                         -- 줄을 적을 때 본 출발 칸 P(뽑혔지만 안 나간 수량)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,                -- ims_touch 가 채운다
  constraint inv_move_line_uq      unique (move_id, product_id, from_bin_id, to_bin_id), -- 한 문서 안 같은 SKU · 같은 출발 → 같은 도착 두 줄 금지(보통 유니크)
  constraint inv_move_line_no_uq   unique (move_id, line_no),
  constraint inv_move_line_qty_ck  check (qty > 0),
  constraint inv_move_line_bins_ck check (from_bin_id <> to_bin_id),
  constraint inv_move_line_name_ck check (from_bin <> '' and to_bin <> '')
);
create index inv_move_line_move_idx on public.inv_move_line (move_id);
create trigger inv_move_touch      before update on public.inv_move      for each row execute function public.ims_touch();
create trigger inv_move_line_touch before update on public.inv_move_line for each row execute function public.ims_touch();
alter table public.inv_move      enable row level security;
alter table public.inv_move_line enable row level security;
create policy inv_move_select      on public.inv_move      for select to authenticated using (public.ims_can_view('stock_move'));
create policy inv_move_line_select on public.inv_move_line for select to authenticated using (public.ims_can_view('stock_move'));
comment on table public.inv_move is '칸 옮기기 문서(재고 사건 ② 첫 몫 · 같은 창고 · 판정 60~63 · 묶음 열 · 2026-09-28) — 문서 하나 = 창고 하나 · draft → confirmed · 되돌리기 없음(판정 53 모양 · 반대 방향 새 문서 · 메모에 원 번호) · 쓰기는 창구(inv_move_*)로만 · 읽기 정책 ims_can_view(stock_move) · 원장 doc_type transfer · doc_number MV-n · 레이어 무접촉';
comment on table public.inv_move_line is '옮기기 줄 — 한 낱개 SKU · 출발 칸 → 도착 칸(같은 창고 · 같은 칸 금지) · qty = 낱개 EA · seen_ledger · seen_picked = 적을 때 본 출발 칸 값(확정 때 다시 읽어 다르면 전체 거부) · 원장 line_ref = 이 줄 id · 행 둘(transfer_out 출발 −q · transfer_in 도착 +q)';

-- ═══ 2) 권한 — 판정 63 (표준 문 · 별도 ims_can_* 없음 · 카탈로그는 8) 재발행) ═══
create function public.inv_move_require(p_warehouse_id uuid) returns uuid
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  perform public.ims_require_write('stock_move', 'saved');                                -- ⭐ 첫 줄 문 — admin · supervisor 역할로 · 그 밖은 사람마다 켠 stock_move(worker 도 · 판정 39 B · 63)
  if p_warehouse_id is not null and not public.ims_can_warehouse(p_warehouse_id) then
    raise exception 'This move is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  return v_staff;
end;
$$;
revoke all on function public.inv_move_require(uuid) from public, anon, authenticated;

-- ═══ 3) 읽기 조각 — 열린 픽 계획(판정 62) · 줄 평가 한 번 ═══
--   장부 · P 는 조정의 조각 inv_adjust_ledger · inv_adjust_picked 를 그대로 부른다(같은 뜻 · 같은 함수 — 두 벌을 두지 않는다).
--   열린 계획 = wms_pick_line_bins planned=true × 과제 pending/in_progress × 오더 at_wms/picking · (창고, 출발 칸, 낱개 제품)
--   막는 몫(blocking) · 옮길 수 있는 계획(movable) 의 셈 — 근거는 wms_complete_pick(20260927214447:190~199)의 fallback: bins 를 안 보내면 계획 칸 행을 id 순으로 채워 실제 칸 행을 만든다.
--     · in_progress 과제: 계획 전부가 그 칸에서 피커를 기다린다(이미 뽑아 토트에 든 것도 완료 때 이 칸 행이 된다) ⇒ blocking = 계획 − 이미 적힌 실제(이 칸 · 그 줄 · 보통 0) · movable 0
--     · pending 과제(보류 포함 — wms_hold_pick 은 status 를 pending 으로 되돌리고 picked_base 만 남긴다 · 실제 칸 행은 안 쓴다):
--         covered = 이 계획 행이 id 순으로 덮는 「뽑았지만 안 적힌 수량」(picked_base − 실제 행 합) — 그 몫은 완료 때 이 칸 행이 되므로 남긴다(blocking) · 나머지 = movable(도착 칸으로 바꿀 수 있다)
create function public.inv_move_open_plans(p_warehouse_id uuid, p_bin_id uuid, p_product_id uuid)
  returns table(row_id bigint, task_id bigint, batch_label text, so_number text, task_status text, pick_task_line_id bigint,
                planned_qty numeric, covered_qty numeric, blocking_qty numeric, movable_qty numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with ln as (
    select pl.id as line_id, t.id as task_id, t.batch_label, s.so_number, t.status as task_status,
           greatest(coalesce(pl.picked_base, 0) - coalesce((select sum(a.qty_base) from public.wms_pick_line_bins a where a.pick_task_line_id = pl.id and not a.planned), 0), 0) as unwritten,
           coalesce((select sum(a.qty_base) from public.wms_pick_line_bins a where a.pick_task_line_id = pl.id and not a.planned and a.bin_id = p_bin_id), 0) as actual_here
      from public.wms_pick_task_lines pl
      join public.wms_pick_tasks t on t.id = pl.pick_task_id
      join public.so s on s.id = t.order_id
      join public.so_line l on l.id = pl.order_line_id
      join public.product pr on pr.id = l.product_id
     where t.status in ('pending', 'in_progress') and s.location_id = p_warehouse_id and s.status in ('at_wms', 'picking')
       and coalesce(pr.parent_product_id, pr.id) = p_product_id
  ), r as (
    select b.id as row_id, ln.line_id, ln.task_id, ln.batch_label, ln.so_number, ln.task_status, ln.unwritten, ln.actual_here, b.bin_id, b.qty_base,
           coalesce(sum(b.qty_base) over (partition by b.pick_task_line_id order by b.id rows between unbounded preceding and 1 preceding), 0) as before_qty
      from public.wms_pick_line_bins b join ln on ln.line_id = b.pick_task_line_id
     where b.planned
  ), c as (
    select r.*, least(r.qty_base, greatest(r.unwritten - r.before_qty, 0)) as covered from r where r.bin_id = p_bin_id
  )
  select c.row_id, c.task_id, c.batch_label, c.so_number, c.task_status, c.line_id, c.qty_base, c.covered,
         case when c.task_status = 'in_progress' then greatest(c.qty_base - c.actual_here, 0) else c.covered end,
         case when c.task_status = 'in_progress' then 0 else c.qty_base - c.covered end
    from c order by c.task_id, c.row_id;
$$;
revoke all on function public.inv_move_open_plans(uuid, uuid, uuid) from public, anon;   grant execute on function public.inv_move_open_plans(uuid, uuid, uuid) to authenticated;
comment on function public.inv_move_open_plans(uuid, uuid, uuid) is '판정 62 — (창고, 칸, 낱개 제품)의 열린 픽 계획 행마다 planned · covered(뽑았지만 안 적힌 몫) · blocking(막는 몫 · in_progress 는 전부) · movable(도착 칸으로 바꿀 수 있는 몫 · pending 만). 셈의 근거는 이 마이그레이션 3) 머리 주석';

-- 줄 평가 — 미리 보기 · 확정 · line_set 이 같은 식을 본다(for update 없음 · read only 에서 돈다 · x 는 materialized — 판정 54 B)
--   shelf = 장부 − P(선반 기대량) · waiting = 열린 계획의 막는 몫 · max_qty = shelf − waiting · CAS 는 장부 · P 둘 다
create function public.inv_move_eval(p_move_id uuid)
  returns table(line_id uuid, line_no int, product_id uuid, sku text, from_bin_id uuid, from_bin text, to_bin_id uuid, to_bin text, qty numeric,
                seen_ledger numeric, seen_picked numeric, ledger numeric, picked numeric, shelf numeric, waiting numeric, max_qty numeric,
                plans_movable numeric, plans jsonb, to_ledger numeric, rejects text[])
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with h as (select m.warehouse, m.warehouse_id from public.inv_move m where m.id = p_move_id),
  x as materialized (
    select l.id, l.line_no, l.product_id, l.sku, l.from_bin_id, l.from_bin, l.to_bin_id, l.to_bin, l.qty, l.seen_ledger, l.seen_picked,
           public.inv_adjust_ledger(h.warehouse, l.from_bin, l.sku) as ledger,
           public.inv_adjust_picked(h.warehouse_id, l.from_bin_id, l.product_id) as picked,
           public.inv_adjust_ledger(h.warehouse, l.to_bin, l.sku) as to_ledger,
           op.waiting, op.movable, op.plans, op.waiting_txt,
           (select b.is_active and b.warehouse_id = h.warehouse_id from public.ref_bin b where b.id = l.from_bin_id) as from_ok,
           (select b.is_active and b.warehouse_id = h.warehouse_id from public.ref_bin b where b.id = l.to_bin_id) as to_ok,
           (select p.is_active and p.parent_product_id is null from public.product p where p.id = l.product_id) as product_ok
      from public.inv_move_line l, h
      cross join lateral (
        select coalesce(sum(p.blocking_qty), 0) as waiting, coalesce(sum(p.movable_qty), 0) as movable,
               coalesce(jsonb_agg(jsonb_build_object('task_id', p.task_id, 'batch_label', p.batch_label, 'so_number', p.so_number, 'status', p.task_status,
                                                     'planned', p.planned_qty, 'blocking', p.blocking_qty, 'movable', p.movable_qty) order by p.task_id, p.row_id), '[]'::jsonb) as plans,
               string_agg(p.batch_label || ' waits ' || p.blocking_qty, ', ' order by p.task_id, p.row_id) filter (where p.blocking_qty > 0) as waiting_txt
          from public.inv_move_open_plans(h.warehouse_id, l.from_bin_id, l.product_id) p) op
     where l.move_id = p_move_id
  )
  select x.id, x.line_no, x.product_id, x.sku, x.from_bin_id, x.from_bin, x.to_bin_id, x.to_bin, x.qty,
         x.seen_ledger, x.seen_picked, x.ledger, x.picked, x.ledger - x.picked, x.waiting, x.ledger - x.picked - x.waiting,
         least(x.qty, x.movable), x.plans, x.to_ledger,
         array_remove(array[
           case when x.qty > x.ledger - x.picked - x.waiting then
             format('line %s %s %s → %s: only %s can move (ledger %s − picked not shipped %s − waiting for pickers %s%s) — you asked %s',
                    x.line_no, x.sku, x.from_bin, x.to_bin, x.ledger - x.picked - x.waiting, x.ledger, x.picked, x.waiting,
                    case when x.waiting_txt is not null then ': ' || x.waiting_txt else '' end, x.qty) end,
           case when x.ledger <> x.seen_ledger then format('line %s %s %s: ledger changed (you saw %s, it is now %s)', x.line_no, x.sku, x.from_bin, x.seen_ledger, x.ledger) end,
           case when x.picked <> x.seen_picked then format('line %s %s %s: picked-not-shipped changed (you saw %s, it is now %s)', x.line_no, x.sku, x.from_bin, x.seen_picked, x.picked) end,
           case when not coalesce(x.from_ok, false) then format('line %s: bin %s is inactive or not in this warehouse', x.line_no, x.from_bin) end,
           case when not coalesce(x.to_ok, false) then format('line %s: bin %s is inactive or not in this warehouse', x.line_no, x.to_bin) end,
           case when not coalesce(x.product_ok, false) then format('line %s: %s is inactive or a set — move the single-unit SKU', x.line_no, x.sku) end
         ], null)
    from x order by x.line_no;
$$;
revoke all on function public.inv_move_eval(uuid) from public, anon;   grant execute on function public.inv_move_eval(uuid) to authenticated;

-- ═══ 4) 초안 창구 — definer(표에 쓰기 정책이 없다) · 첫 줄 문 ═══
create function public.inv_move_create(p_warehouse_id uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_wh public.ref_warehouse%rowtype; v_m public.inv_move%rowtype;
begin
  v_staff := public.inv_move_require(p_warehouse_id);                                      -- ⭐ 첫 줄
  select * into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if not found then raise exception 'Warehouse not found or inactive — nothing was saved'; end if;
  insert into public.inv_move (warehouse_id, warehouse, note, created_by, updated_by)
  values (v_wh.id, v_wh.name, nullif(trim(p_note), ''), v_staff, v_staff) returning * into v_m;
  return jsonb_build_object('id', v_m.id, 'move_number', v_m.move_number, 'status', v_m.status, 'warehouse', v_m.warehouse, 'warehouse_id', v_m.warehouse_id);
end;
$$;

-- 줄 넣기 · 고치기 — p_line {line_id?, product_id?|sku?, from_bin_id?|from_bin?, to_bin_id?|to_bin?, qty} · 본 값(장부 · P)은 이 순간 읽어 적는다
create function public.inv_move_line_set(p_move_id uuid, p_line jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_m public.inv_move%rowtype; v_p public.product%rowtype; v_f public.ref_bin%rowtype; v_t public.ref_bin%rowtype; v_l public.inv_move_line%rowtype;
        v_qty numeric; v_ledger numeric; v_picked numeric; v_id uuid; v_no int; v_e record;
begin
  select * into v_m from public.inv_move m where m.id = p_move_id for update;
  if not found then raise exception 'Move not found — nothing was saved'; end if;
  perform public.inv_move_require(v_m.warehouse_id);                                       -- ⭐ 첫 줄 문(문서의 창고)
  if v_m.status <> 'draft' then raise exception 'Move % is % — only a draft can be edited — nothing was saved', v_m.move_number, v_m.status; end if;
  if p_line is null or jsonb_typeof(p_line) <> 'object' then raise exception 'p_line must be a JSON object — nothing was saved'; end if;
  -- 제품 — 낱개만(묶음 3)
  if nullif(p_line->>'product_id', '') is not null then select * into v_p from public.product p where p.id = (p_line->>'product_id')::uuid;
  else select * into v_p from public.product p where p.sku = trim(p_line->>'sku'); end if;
  if not found then raise exception 'Product not found (%) — nothing was saved', coalesce(p_line->>'sku', p_line->>'product_id'); end if;
  if not v_p.is_active then raise exception 'Product % is inactive — nothing was saved', v_p.sku; end if;
  if v_p.parent_product_id is not null then raise exception 'Product % is a set or pack — move the single-unit SKU instead — nothing was saved', v_p.sku; end if;
  -- 칸 둘 — 이 창고의 활성 칸 · 같은 칸 거부(묶음 3)
  if nullif(p_line->>'from_bin_id', '') is not null then select * into v_f from public.ref_bin b where b.id = (p_line->>'from_bin_id')::uuid;
  else select * into v_f from public.ref_bin b where b.warehouse_id = v_m.warehouse_id and b.name = trim(p_line->>'from_bin'); end if;
  if not found then raise exception 'From bin not found in this warehouse (%) — nothing was saved', coalesce(p_line->>'from_bin', p_line->>'from_bin_id'); end if;
  if v_f.warehouse_id <> v_m.warehouse_id then raise exception 'Bin % is in another warehouse — nothing was saved', v_f.name; end if;
  if not v_f.is_active then raise exception 'Bin % is inactive — nothing was saved', v_f.name; end if;
  if nullif(p_line->>'to_bin_id', '') is not null then select * into v_t from public.ref_bin b where b.id = (p_line->>'to_bin_id')::uuid;
  else select * into v_t from public.ref_bin b where b.warehouse_id = v_m.warehouse_id and b.name = trim(p_line->>'to_bin'); end if;
  if not found then raise exception 'To bin not found in this warehouse (%) — nothing was saved', coalesce(p_line->>'to_bin', p_line->>'to_bin_id'); end if;
  if v_t.warehouse_id <> v_m.warehouse_id then raise exception 'Bin % is in another warehouse — nothing was saved', v_t.name; end if;
  if not v_t.is_active then raise exception 'Bin % is inactive — nothing was saved', v_t.name; end if;
  if v_f.id = v_t.id then raise exception 'From and to are the same bin (%) — nothing was saved', v_f.name; end if;
  -- 수량 — 낱개 EA · 양수(팩 · 세트 환산은 화면)
  if nullif(p_line->>'qty', '') is null or (p_line->>'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then raise exception 'qty must be a positive number — nothing was saved'; end if;
  v_qty := (p_line->>'qty')::numeric;
  if v_qty <= 0 then raise exception 'qty must be more than 0 — nothing was saved'; end if;
  -- 본 값 — 출발 칸의 장부 · P(조정과 같은 조각)
  v_ledger := public.inv_adjust_ledger(v_m.warehouse, v_f.name, v_p.sku);
  v_picked := public.inv_adjust_picked(v_m.warehouse_id, v_f.id, v_p.id);
  v_id := nullif(p_line->>'line_id', '')::uuid;
  if v_id is null then select l.id into v_id from public.inv_move_line l where l.move_id = p_move_id and l.product_id = v_p.id and l.from_bin_id = v_f.id and l.to_bin_id = v_t.id; end if;
  begin
    if v_id is not null then
      update public.inv_move_line l set product_id = v_p.id, sku = v_p.sku, from_bin_id = v_f.id, from_bin = v_f.name, to_bin_id = v_t.id, to_bin = v_t.name, qty = v_qty, seen_ledger = v_ledger, seen_picked = v_picked
       where l.id = v_id and l.move_id = p_move_id returning * into v_l;
      if not found then raise exception 'Line not found on this move — nothing was saved'; end if;
    else
      select coalesce(max(l.line_no), 0) + 1 into v_no from public.inv_move_line l where l.move_id = p_move_id;
      insert into public.inv_move_line (move_id, line_no, product_id, sku, from_bin_id, from_bin, to_bin_id, to_bin, qty, seen_ledger, seen_picked)
      values (p_move_id, v_no, v_p.id, v_p.sku, v_f.id, v_f.name, v_t.id, v_t.name, v_qty, v_ledger, v_picked) returning * into v_l;
    end if;
  exception when unique_violation then
    raise exception 'Move % already has a line %s %s → %s — edit that line instead — nothing was saved', v_m.move_number, v_p.sku, v_f.name, v_t.name;
  end;
  select * into v_e from public.inv_move_eval(p_move_id) e where e.line_id = v_l.id;         -- 줄의 지금 평가(선반 · 막는 몫 · 최대 · 거부)를 함께 돌려준다
  return jsonb_build_object('move_id', p_move_id, 'line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'from_bin', v_l.from_bin, 'to_bin', v_l.to_bin, 'qty', v_l.qty,
                            'seen_ledger', v_l.seen_ledger, 'seen_picked', v_l.seen_picked, 'shelf', v_e.shelf, 'waiting', v_e.waiting, 'max_qty', v_e.max_qty,
                            'plans_movable', v_e.plans_movable, 'plans', v_e.plans, 'to_ledger', v_e.to_ledger, 'rejects', to_jsonb(v_e.rejects));
end;
$$;

create function public.inv_move_line_remove(p_move_id uuid, p_line_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_m public.inv_move%rowtype; v_n int;
begin
  select * into v_m from public.inv_move m where m.id = p_move_id for update;
  if not found then raise exception 'Move not found — nothing was saved'; end if;
  perform public.inv_move_require(v_m.warehouse_id);
  if v_m.status <> 'draft' then raise exception 'Move % is % — only a draft can be edited — nothing was saved', v_m.move_number, v_m.status; end if;
  delete from public.inv_move_line where id = p_line_id and move_id = p_move_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Line not found on this move — nothing was saved'; end if;
  return jsonb_build_object('move_id', p_move_id, 'removed', p_line_id);
end;
$$;

create function public.inv_move_delete(p_move_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_m public.inv_move%rowtype;
begin
  select * into v_m from public.inv_move m where m.id = p_move_id for update;
  if not found then raise exception 'Move not found — nothing was saved'; end if;
  perform public.inv_move_require(v_m.warehouse_id);
  if v_m.status <> 'draft' then raise exception 'Move % is % — a confirmed move cannot be deleted (move the stock back with a new move) — nothing was saved', v_m.move_number, v_m.status; end if;
  delete from public.inv_move where id = p_move_id;                                        -- 줄은 cascade · 번호는 빈다(판정 55)
  return jsonb_build_object('deleted', v_m.move_number);
end;
$$;

-- ═══ 5) 미리 보기 · 확정 · 한 번에(묶음 1 · 창구 하나 · 입구 둘) ═══
create function public.inv_move_preview(p_move_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare v_m public.inv_move%rowtype; v_lines jsonb; v_rej jsonb; v_plans numeric;
begin
  if not public.ims_can_view('stock_move') then raise exception 'You cannot view bin moves — this needs the stock_move key'; end if;
  select * into v_m from public.inv_move m where m.id = p_move_id;
  if not found then raise exception 'Move not found'; end if;
  select coalesce(jsonb_agg(to_jsonb(e) order by e.line_no), '[]'::jsonb) into v_lines from public.inv_move_eval(p_move_id) e;   -- ⭐ eval 한 번
  v_rej := coalesce((select jsonb_agg(x order by x) from jsonb_array_elements(v_lines) l cross join lateral jsonb_array_elements_text(l -> 'rejects') as x), '[]'::jsonb)
           || case when jsonb_array_length(v_lines) = 0 then '["no lines"]'::jsonb else '[]'::jsonb end;
  select coalesce(sum((l->>'plans_movable')::numeric), 0) into v_plans from jsonb_array_elements(v_lines) l;
  return jsonb_build_object('move_id', v_m.id, 'move_number', v_m.move_number, 'status', v_m.status, 'warehouse', v_m.warehouse, 'warehouse_id', v_m.warehouse_id,
                            'posted_on', coalesce(v_m.posted_on, public.ims_today()), 'lines', v_lines, 'rejects', v_rej,
                            'can_confirm', v_m.status = 'draft' and jsonb_array_length(v_rej) = 0, 'plans_to_move_qty', v_plans);
end;
$$;

create function public.inv_move_confirm(p_move_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_m public.inv_move%rowtype; v_staff uuid; v_rej text[] := '{}'; v_on date; v_post jsonb; v_e record; v_l public.inv_move_line%rowtype; v_p record;
        v_plans jsonb := '[]'::jsonb; v_plans_qty numeric := 0; v_rem numeric; v_take numeric;
begin
  select * into v_m from public.inv_move m where m.id = p_move_id for update;              -- 머리 잠금 — 같은 문서 두 번 확정 방지
  if not found then raise exception 'Move not found — nothing was saved'; end if;
  v_staff := public.inv_move_require(v_m.warehouse_id);                                    -- ⭐ 첫 줄 문
  if v_m.status <> 'draft' then raise exception 'Move % is already % — nothing was saved', v_m.move_number, v_m.status; end if;
  if not exists (select 1 from public.inv_move_line l where l.move_id = p_move_id) then raise exception 'Move % has no lines — nothing was saved', v_m.move_number; end if;
  -- 판정 62 — 출발 칸을 가리키는 열린 픽 줄을 먼저 잠근다: 같은 줄을 완료하는 wms_complete_pick(줄 update) 과 서로 기다린다 · 평가는 잠근 뒤 한 번
  perform 1 from public.wms_pick_task_lines pl
    where pl.id in (select p.pick_task_line_id from public.inv_move_line l cross join lateral public.inv_move_open_plans(v_m.warehouse_id, l.from_bin_id, l.product_id) p where l.move_id = p_move_id)
    for update;
  for v_e in select * from public.inv_move_eval(p_move_id) loop v_rej := v_rej || v_e.rejects; end loop;   -- ⭐ eval 한 번 — 거부 판정
  select coalesce(array_agg(x order by x), '{}') into v_rej from unnest(v_rej) as x;
  if cardinality(v_rej) > 0 then raise exception 'Move % cannot be confirmed: % — reload and check the lines — nothing was saved', v_m.move_number, array_to_string(v_rej, '; '); end if;
  v_on := public.ims_today();
  -- 판정 62 — 기다리는(pending) 과제의 계획 행을 옮긴 수량까지 도착 칸으로(과제 · 행 id 순 · 부분이면 행을 나눈다 · 계획 합 무변) · in_progress 는 위 평가가 막았다
  for v_l in select * from public.inv_move_line l where l.move_id = p_move_id order by l.line_no loop
    v_rem := v_l.qty;
    for v_p in select * from public.inv_move_open_plans(v_m.warehouse_id, v_l.from_bin_id, v_l.product_id) p where p.movable_qty > 0 order by p.task_id, p.row_id loop
      exit when v_rem <= 0;
      v_take := least(v_rem, v_p.movable_qty);
      if v_take = v_p.planned_qty then
        update public.wms_pick_line_bins b set bin_id = v_l.to_bin_id, bin = v_l.to_bin where b.id = v_p.row_id;
      else
        update public.wms_pick_line_bins b set qty_base = b.qty_base - v_take where b.id = v_p.row_id;
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned) values (v_p.pick_task_line_id, v_l.to_bin_id, v_l.to_bin, v_take, true);
      end if;
      v_plans := v_plans || jsonb_build_object('task_id', v_p.task_id, 'batch_label', v_p.batch_label, 'so_number', v_p.so_number, 'line_id', v_l.id, 'sku', v_l.sku,
                                               'from_bin', v_l.from_bin, 'to_bin', v_l.to_bin, 'qty', v_take, 'split', v_take <> v_p.planned_qty);
      v_plans_qty := v_plans_qty + v_take;  v_rem := v_rem - v_take;
    end loop;
  end loop;
  update public.inv_move set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now(), posted_on = v_on, plans_moved = v_plans, updated_by = v_staff where id = p_move_id;
  v_post := public.inv_post_move(p_move_id);                                               -- 원장 행 둘씩 · 같은 트랜잭션 · 실패하면 확정도 안 된다
  return jsonb_build_object('move_id', v_m.id, 'move_number', v_m.move_number, 'status', 'confirmed', 'posted_on', v_on, 'warehouse', v_m.warehouse,
                            'ledger', v_post, 'plans_moved', v_plans, 'plans_moved_qty', v_plans_qty);
end;
$$;

-- 한 번에(창고 스캔 · 초안 없이 끝) — create + line_set × n + confirm 을 한 트랜잭션에서 · 어디서든 막히면 전부 되돌아간다(초안이 남지 않는다)
create function public.inv_move_now(p_warehouse_id uuid, p_lines jsonb, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_id uuid; v_l jsonb; v_c jsonb; v_n int := 0;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'p_lines must be a JSON array of {sku|product_id, from_bin|from_bin_id, to_bin|to_bin_id, qty} — nothing was saved';
  end if;
  v_id := (public.inv_move_create(p_warehouse_id, p_note))->>'id';
  for v_l in select * from jsonb_array_elements(p_lines) loop perform public.inv_move_line_set(v_id, v_l); v_n := v_n + 1; end loop;
  v_c := public.inv_move_confirm(v_id);
  return v_c || jsonb_build_object('lines', v_n);
end;
$$;
revoke all on function public.inv_move_create(uuid, text) from public, anon;              grant execute on function public.inv_move_create(uuid, text) to authenticated;
revoke all on function public.inv_move_line_set(uuid, jsonb) from public, anon;           grant execute on function public.inv_move_line_set(uuid, jsonb) to authenticated;
revoke all on function public.inv_move_line_remove(uuid, uuid) from public, anon;         grant execute on function public.inv_move_line_remove(uuid, uuid) to authenticated;
revoke all on function public.inv_move_delete(uuid) from public, anon;                    grant execute on function public.inv_move_delete(uuid) to authenticated;
revoke all on function public.inv_move_preview(uuid) from public, anon;                   grant execute on function public.inv_move_preview(uuid) to authenticated;
revoke all on function public.inv_move_confirm(uuid) from public, anon;                   grant execute on function public.inv_move_confirm(uuid) to authenticated;
revoke all on function public.inv_move_now(uuid, jsonb, text) from public, anon;          grant execute on function public.inv_move_now(uuid, jsonb, text) to authenticated;
comment on function public.inv_move_confirm(uuid) is '⭐ 확정 길 하나(묶음 1) — 머리 for update → 열린 픽 줄 잠금 → eval 한 번 → 거부면 전체 거부 → pending 계획을 도착 칸으로(판정 62 · plans_moved 에 기록) → confirmed → inv_post_move(행 둘씩). 되돌리기 창구 없음(반대 방향 새 문서)';
comment on function public.inv_move_now(uuid, jsonb, text) is '입구 둘째(창고 스캔 화면) — create + line_set × n + confirm 한 트랜잭션 · 반환 = confirm 반환 + lines';

-- ═══ 6) 원장 창구 (묶음 4) — 줄마다 행 둘 · 레이어 · consume 무접촉(레이어는 창고 단위 · 같은 창고 안에서는 할 일이 없다) ═══
create function public.inv_post_move(p_move_id uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_post_move@2026-09-28.1';
        v_m public.inv_move%rowtype; v_existing int; v_rows int := 0; v_qty numeric := 0; v_hdr jsonb; l record;
begin
  select * into v_m from public.inv_move m where m.id = p_move_id;
  if not found then raise exception 'Move not found — nothing was posted to the ledger'; end if;
  if v_m.status <> 'confirmed' then raise exception 'Move % is % — the ledger takes confirmed moves only — nothing was posted to the ledger', v_m.move_number, v_m.status; end if;
  select count(*) into v_existing from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = v_m.move_number and e.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('move_id', v_m.id, 'move_number', v_m.move_number, 'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_ea_posted', 0, 'warnings', '["already_posted"]'::jsonb);
  end if;
  v_hdr := jsonb_build_object('move_number', v_m.move_number, 'moved_on', v_m.posted_on, 'warehouse_id', v_m.warehouse_id, 'warehouse', v_m.warehouse, 'note', v_m.note, 'confirmed_by', v_m.confirmed_by);
  for l in select * from public.inv_move_line x where x.move_id = p_move_id order by x.line_no loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_m.posted_on, 2, l.sku, v_m.warehouse, l.from_bin, -l.qty, 'transfer_out', 'transfer', v_m.move_number, v_m.id::text, l.id::text, null, 'ims',
            jsonb_build_object('kind', 'bin_move', 'leg', 'from', 'poster', c_version, 'header', v_hdr, 'line', to_jsonb(l),
                               'rule', format('bin move %s → %s in %s: −%s at %s (same warehouse · no transit · cost layers untouched)', l.from_bin, l.to_bin, v_m.warehouse, l.qty, l.from_bin))),
           (v_m.posted_on, 1, l.sku, v_m.warehouse, l.to_bin, l.qty, 'transfer_in', 'transfer', v_m.move_number, v_m.id::text, l.id::text, null, 'ims',
            jsonb_build_object('kind', 'bin_move', 'leg', 'to', 'poster', c_version, 'header', v_hdr, 'line', to_jsonb(l),
                               'rule', format('bin move %s → %s in %s: +%s at %s (same warehouse · no transit · cost layers untouched)', l.from_bin, l.to_bin, v_m.warehouse, l.qty, l.to_bin)));
    v_rows := v_rows + 2; v_qty := v_qty + l.qty;
  end loop;
  return jsonb_build_object('move_id', v_m.id, 'move_number', v_m.move_number, 'already_posted', false, 'existing_rows', 0, 'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'poster', c_version);
exception when unique_violation then
  raise exception 'Move % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_m.move_number, sqlerrm;
end;
$$;
comment on function public.inv_post_move(uuid) is '⭐⭐ 칸 옮기기의 원장 창구(묶음 4) — confirmed 문서의 줄마다 행 둘: transfer_out 출발 칸 −q seq 2 · transfer_in 도착 칸 +q seq 1 · doc_type transfer · doc_number MV-n · doc_task_id = move id · line_ref = 줄 id · source ims · raw.kind bin_move · amount null · 운송 중 없음 · 레이어 · consume 무접촉(재생성 inv_layer_apply 도 이 행을 세지 않고 지나간다) · 멱등(already_posted) · authenticated 회수 — inv_move_confirm 만 부른다';
revoke all on function public.inv_post_move(uuid) from public, anon, authenticated;

-- ═══ 7) 읽기 창구 — 화면 ②(wms-mover) · ③(stock-moves)이 쓴다 ═══
create function public.inv_move_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_view('stock_move') then null::jsonb else
  coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from (
    select m.id, m.move_number, m.status, m.warehouse_id, m.warehouse, m.note, m.posted_on, m.created_at, m.confirmed_at,
           cb.name as created_by_name, fb.name as confirmed_by_name,
           (select count(*) from public.inv_move_line l where l.move_id = m.id) as line_count,
           (select coalesce(sum(l.qty), 0) from public.inv_move_line l where l.move_id = m.id) as qty_ea,
           coalesce(jsonb_array_length(m.plans_moved), 0) as plans_moved_count
      from public.inv_move m
      left join public.ims_staff cb on cb.id = m.created_by
      left join public.ims_staff fb on fb.id = m.confirmed_by
     where (nullif(p_filters->>'status', '') is null or m.status = p_filters->>'status')
       and (nullif(p_filters->>'warehouse_id', '') is null or m.warehouse_id = (p_filters->>'warehouse_id')::uuid)
       and (nullif(p_filters->>'q', '') is null or m.move_number ilike '%' || (p_filters->>'q') || '%' or m.note ilike '%' || (p_filters->>'q') || '%'
            or exists (select 1 from public.inv_move_line l where l.move_id = m.id and (l.sku ilike '%' || (p_filters->>'q') || '%' or l.from_bin ilike '%' || (p_filters->>'q') || '%' or l.to_bin ilike '%' || (p_filters->>'q') || '%')))
       and (nullif(p_filters->>'from', '') is null or m.created_at >= (p_filters->>'from')::date)
       and (nullif(p_filters->>'to', '') is null or m.created_at < (p_filters->>'to')::date + 1)
     order by m.created_at desc limit coalesce(nullif(p_filters->>'limit', '')::int, 300)) t), '[]'::jsonb) end;
$$;

create function public.inv_move_detail(p_move_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare v_m public.inv_move%rowtype; v_lines jsonb; v_rej jsonb; v_plans numeric;
begin
  if not public.ims_can_view('stock_move') then return null; end if;
  select * into v_m from public.inv_move m where m.id = p_move_id;
  if not found then return null; end if;
  select coalesce(jsonb_agg(to_jsonb(e) order by e.line_no), '[]'::jsonb) into v_lines from public.inv_move_eval(p_move_id) e;   -- ⭐ eval 한 번(detail 과 preview 가 같은 값)
  v_rej := coalesce((select jsonb_agg(x order by x) from jsonb_array_elements(v_lines) l cross join lateral jsonb_array_elements_text(l -> 'rejects') as x), '[]'::jsonb)
           || case when jsonb_array_length(v_lines) = 0 then '["no lines"]'::jsonb else '[]'::jsonb end;
  select coalesce(sum((l->>'plans_movable')::numeric), 0) into v_plans from jsonb_array_elements(v_lines) l;
  return jsonb_build_object(
    'header', to_jsonb(v_m) || jsonb_build_object('created_by_name', (select cb.name from public.ims_staff cb where cb.id = v_m.created_by), 'confirmed_by_name', (select fb.name from public.ims_staff fb where fb.id = v_m.confirmed_by)),
    'lines', (select coalesce(jsonb_agg(l || jsonb_build_object('product_name', p.name, 'ledger_rows',
                      (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'event_type', x.event_type, 'bin', x.bin, 'qty_delta', x.qty_delta, 'occurred_on', x.occurred_on) order by x.seq_hint desc), '[]'::jsonb)
                         from public.inv_ledger x where x.doc_type = 'transfer' and x.doc_number = v_m.move_number and x.source = 'ims' and x.line_ref = l ->> 'line_id')) order by (l ->> 'line_no')::int), '[]'::jsonb)
                from jsonb_array_elements(v_lines) l join public.product p on p.id = (l ->> 'product_id')::uuid),
    'preview', case when v_m.status = 'draft' then jsonb_build_object('rejects', v_rej, 'can_confirm', jsonb_array_length(v_rej) = 0, 'plans_to_move_qty', v_plans) end);
end;
$$;
revoke all on function public.inv_move_list(jsonb) from public, anon;    grant execute on function public.inv_move_list(jsonb) to authenticated;
revoke all on function public.inv_move_detail(uuid) from public, anon;   grant execute on function public.inv_move_detail(uuid) to authenticated;

-- ═══ 8) 재발행 — ims_perm_catalog · 마지막 정의 20260928142722:546~568 바이트 그대로 + stock_move 한 줄(판정 63 · wms 방 · min_role 없음 · stock_adjust 줄 끝 쉼표) ═══
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
      "stock_move":            {"room": "wms", "label": "Bin moves — move stock between bins in one warehouse (person by person · off until switched on)"}
    }
  }'::jsonb;
$$;


-- ═══ 9) 재발행 — inv_layer_apply · 마지막 정의 20260928142722:570~1058 바이트 그대로 · 바뀐 줄 1(source 와 raw.kind 를 한 번에 조회) · 더한 줄 7(declare 2 · bin_move 갈래 4 · 반환 1) · 재발행 뒤 revoke 그대로(판정 31) ═══
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
  v_ims_kind    text;                                                                     -- trf-a 2026-09-28 raw.kind — 'bin_move' = 같은 창고 칸 옮기기(레이어는 창고 단위라 할 일이 없다)
  v_bin_moves   int := 0;                                                                 -- trf-a 지나간 칸 옮기기 행 수(out · in 둘 다 센다 · 반환 ims.bin_moves_passed)
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
      select source, raw ->> 'kind' into v_ims_src, v_ims_kind from inv_ledger where id = r.id;   -- trf-a: kind 도 함께(조회 한 번 그대로)
      if v_ims_src = 'ims' and v_ims_kind = 'bin_move' and r.event_type in ('transfer_in', 'transfer_out') then   -- trf-a 2026-09-28 칸 옮기기(같은 창고 · inv_post_move) — 레이어는 (sku, warehouse) 단위라 할 일이 없다 · 세지 않고 지나간다(실시간 창구도 레이어를 부르지 않는다 = 같은 결과) · 창고 간 문서는 kind 가 다르다(뒤 차수의 갈래)
        v_bin_moves := v_bin_moves + 1;
        continue;
      end if;
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
      'bin_moves_passed',          v_bin_moves,             -- ⭐ trf-a 2026-09-28 raw.kind bin_move 인 칸 옮기기 행 수 — 창구가 있으니 skipped_by_event 의 transfer 두 키에 안 잡힌다(0 이 정상)
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

-- ═══ 10) 재발행 — wms_health_check · 마지막 정의 20260928142722:1061~1327 바이트 그대로 · 더한 줄 40(CTE 셋 mv_nl · plan_short · bin_neg + 검사 셋 175 move_confirmed_no_ledger · 180 planned_bin_short · 185 bin_negative · 묶음 7) ═══
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
  mv_nl as (                                                             -- trf-a 2026-09-28 확정된 칸 옮기기인데 원장 행이 없다
    select m.move_number, m.confirmed_at, m.warehouse
      from public.inv_move m
     where m.status = 'confirmed'
       and exists (select 1 from public.inv_move_line l where l.move_id = m.id)
       and not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = m.move_number and e.source = 'ims')
  ),
  plan_short as (                                                        -- trf-a 열린 과제(pending · in_progress)의 계획 칸 합이 그 칸 장부보다 크다 — 피커가 빈 칸으로 간다(원인 무관 · 칸 옮기기 뒤 · 조정 뒤 · 낡은 계획)
    select s0.warehouse, s0.bin, s0.sku, s0.planned_ea, s0.ledger_ea, s0.batches
      from (select s.location_name as warehouse, b.bin, coalesce(pp.sku, pr.sku) as sku, sum(b.qty_base) as planned_ea,
                   coalesce(max(v.qty), 0) as ledger_ea, string_agg(distinct t.batch_label, ', ') as batches
              from public.wms_pick_line_bins b
              join public.wms_pick_task_lines pl on pl.id = b.pick_task_line_id
              join public.wms_pick_tasks t on t.id = pl.pick_task_id
              join public.so s on s.id = t.order_id
              join public.so_line l on l.id = pl.order_line_id
              join public.product pr on pr.id = l.product_id
              left join public.product pp on pp.id = pr.parent_product_id
              left join public.inv_balance v on v.sku = coalesce(pp.sku, pr.sku) and v.warehouse = s.location_name and v.bin = b.bin
             where b.planned and t.status in ('pending', 'in_progress')
             group by s.location_name, b.bin, coalesce(pp.sku, pr.sku)) s0
     where s0.planned_ea > s0.ledger_ea
  ),
  bin_neg as (                                                           -- trf-a 칸 잔고가 음수 — 어디선가 실제와 다른 칸에서 뺐다(칸 없는 행 · 운송 중은 제외)
    select v.warehouse, v.bin, v.sku, v.qty
      from public.inv_balance v
     where v.qty < 0 and v.bin <> '' and v.warehouse in (select w.name from public.ref_warehouse w)
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
  select 175, 'move_confirmed_no_ledger', 'critical', 'Confirmed bin move without ledger rows',
    'A confirmed bin move has no ledger rows - the confirm transaction was interrupted between the document and the ledger. Bin balances are wrong until inv_post_move is run by the DB owner.',
    (select count(*) from mv_nl), (select jsonb_agg(t) from (select * from mv_nl limit 8) t)
  union all
  select 180, 'planned_bin_short', 'warn', 'Pick plan points at a bin with less stock than planned',
    'Open pick tasks (waiting or in progress) plan more units from a bin than the ledger has there - the picker will find an empty or short bin. Usual causes: a bin move or an adjustment made after the batch was built, or a stale plan. Re-plan the batch or move the stock back.',
    (select count(*) from plan_short), (select jsonb_agg(t) from (select * from plan_short limit 8) t)
  union all
  select 185, 'bin_negative', 'warn', 'Bin balance below zero',
    'A bin reads a negative quantity in the ledger - units were deducted from a bin that did not have them (a pick recorded against the planned bin while the stock was elsewhere, or a move that was never recorded). Find the stock and fix it with a bin move or an adjustment.',
    (select count(*) from bin_neg), (select jsonb_agg(t) from (select * from bin_neg limit 8) t)
  union all
  select 200, 'last_release', 'info', 'Last release to WMS',
    'Newest Release to WMS from the office (Toronto time) - the signal that orders are still flowing into the warehouse. A long gap is normal when the office has nothing to release.',
    0::bigint, (select jsonb_build_object('last_at', last_at, 'last_at_toronto', last_at_toronto, 'minutes_ago', minutes_ago) from last_rel)
  order by 1;
end
$$;
