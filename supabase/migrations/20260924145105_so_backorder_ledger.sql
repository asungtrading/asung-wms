-- SO 쓰기 ③b — 백오더 장부(so_backorder_close) · 확정 때 이어받기 · 다시 열기(되돌리기 · 취소) · 진행·취소의 끝남 기록 (2026-09-24 UTC)
-- 지시서 ~/asung/prompts/so-write-3-ship.md §1 판정 2~8 · 판정 회신 9~12 · ⬜7 · ⬜8 · 회신 이견 7·8 · 정본 so-module §15(말만) · 5-g 뒤집힘(①「출하가 superseded 로 닫는다」 → 확정 때 이어받기 · ⬜「60 → 80」 닫힘)
-- 바탕: 20260924014219(so_confirm :456 · so_split) · 20260924023740(so_unconfirm :7) · 20260924022449(so_cancel :88 · so_backorder_proceed :208) · 20260924141140(released_reason 'closed' · 트리거) · 20260923133042(so_reserve open_line_id 장치)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 검증 ~/asung/prompts/so-write-3b-verify.sql
--
-- ⭐ 무엇을 하나
--    ① 표 so_backorder_close — so_line 당 활성 한 줄(active_line_id 생성 칸 + 전체 유니크 · 다시 열면 reopened_at · 규칙 29) · end_kind 넷 superseded · expired · proceeded · cancelled(⬜7 · manual 은 창구가 설 때) ·
--       qty_open · qty_taken · qty_unwanted(superseded 만 · 합 = qty_open) · taken_by_so_id/line_id(superseded 짝) · ended_at/by(null = 시스템) · note · 읽기만(select 정책 · 쓰기는 창구만)
--       ⭐ 5-g 「같은 것을 두 번 적지 않는다」 — 누가·무엇을·몇 개·언제는 오더가 · 「열려 있다」는 so_reserve backorder 열린 줄이 · 장부는 오더가 모르는 것(끝난 방식 · 이어받은 곳 · 끝난 때)만
--    ② so_line.backorder_notified_at — 입고 알림은 백오더 제품마다 한 번(판정 3) · 지금은 아무도 안 쓴다(GAS 가 Cin7 에서 보낸다 · 2-g ⬜)
--    ③ 속 함수 셋 — so_backorder_record(장부 한 줄) · so_backorder_supersede(확정 때 이어받기 · 판정 3·4·5·8·9) · so_backorder_reopen(다시 열기 · 판정 5·10·11 — 대상 오더가 끝 상태면 거부)
--    ④ 재발행 넷(마지막 정의를 바이트 그대로 · 더한 줄만 · diff 는 회신) — so_confirm(끝에 이어받기 한 줄) · so_unconfirm(다시 열기) · so_cancel(⭐ 시그니처 +p_reopen_superseded → drop+create · 미리 보기에 이어받은 줄 · 취소되는 백오더 줄은 cancelled) · so_backorder_proceed(잡힌 줄은 proceeded)
--
-- ⭐ 규칙(정본 §15 로 옮긴다 · 말만)
--    이어받기는 새 오더를 「확정할 때」(판정 5) · 같은 customer_id · 같은 product_id · 가족 밖(so_number base 가 다르다) · 브랜치 무관(판정 8) · 새 수량 = 이 확정의 그 제품 주문 수량 합(원래 + 이 확정에서 태어난 형제) ·
--    가장 오래된 줄부터(order_date · created_at) · 모자라면 나머지 줄은 더 원하지 않음 전량(판정 4 · 100→80→60 은 60) · 원래 줄의 qty_ordered 는 안 고친다(판정 3) · 프리오더 줄은 대상 아님(판정 9)
--    오더는 뒤처리로 닫지 않는다 — 끝 상태로 가는 길은 만료 하나(판정 11 · ③c) · 다시 열기(so_unconfirm · so_cancel true)는 대상 오더가 confirmed 일 때만 · 만료·취소 뒤 거부
--    백오더 예약(kind backorder)을 닫는 자리와 장부(훑기 · 회신에 file:line): 확정 이어받기 → superseded · so_backorder_proceed 가 잡은 줄 → proceeded · so_cancel 의 대상 오더 줄 → cancelled ·
--       so_unconfirm(되돌리기 = 확정을 무른다 · 형제 줄이 draft 로 돌아간다) · so_divide(같은 kind 로 따라간다) · proceed 에서 못 잡아 형제로 간 줄(같은 줄이 이어진다)은 옮김 — 장부 없음 · so_hold · so_reallocate · so_change_location · so_ship 은 backorder 를 안 닫는다
-- ⚠️ 다시 만들지 않은 것 — so_split · so_allocate_run · so_require_role · so_current_staff · ims_touch · so_reserve_release_reason(트리거 · reason 명시 'closed')
-- ⚠️ 시퀀스 무접촉(채번 없음) · seed 없음

-- ═══ ① 표 so_backorder_close ═══
create table if not exists public.so_backorder_close (
  id                uuid primary key default gen_random_uuid(),
  so_line_id        uuid not null references public.so_line (id) on delete no action,    -- 끝난 백오더 줄(누가·무엇을·몇 개·언제는 이 줄과 그 오더가 말한다)
  end_kind          text not null,
  qty_open          numeric not null,                                                     -- 끝날 때 열려 있던 백오더 수량(so_reserve.qty_allocated · 판매 단위)
  qty_taken         numeric not null default 0,                                           -- superseded: 새 오더가 이어받은 몫
  qty_unwanted      numeric not null default 0,                                           -- superseded: 더 원하지 않은 몫(판정 3·4)
  taken_by_so_id    uuid references public.so      (id) on delete no action,              -- 이어받은 새 오더(확정한 오더 · 줄은 형제로 갔을 수 있다)
  taken_by_line_id  uuid references public.so_line (id) on delete no action,              -- 그 제품의 새 줄(대표 · 첫 줄)
  ended_at          timestamptz not null default now(),
  ended_by          uuid references public.ims_staff (id) on delete no action,            -- null = 시스템(만료 스윕 ③c)
  note              text,
  reopened_at       timestamptz,                                                          -- 되돌리기 · 취소 true 가 다시 열었다(판정 5·10)
  reopened_by       uuid references public.ims_staff (id) on delete no action,
  active_line_id    uuid generated always as (case when reopened_at is null then so_line_id end) stored,   -- 「줄당 활성 한 줄」 — 부분 유니크 금지(규칙 29) · so_reserve.open_line_id 와 같은 장치
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  updated_by        uuid references public.ims_staff (id) on delete no action,

  constraint so_backorder_close_end_kind_ck    check (end_kind in ('superseded','expired','proceeded','cancelled')),
  constraint so_backorder_close_qty_ck         check (qty_open >= 0 and qty_taken >= 0 and qty_unwanted >= 0),
  constraint so_backorder_close_taken_pair_ck  check ((end_kind = 'superseded') = (taken_by_line_id is not null)),
  constraint so_backorder_close_taken_so_ck    check ((taken_by_so_id is null) = (taken_by_line_id is null)),
  constraint so_backorder_close_split_ck       check ((end_kind = 'superseded' and qty_taken + qty_unwanted = qty_open) or (end_kind <> 'superseded' and qty_taken = 0 and qty_unwanted = 0)),
  constraint so_backorder_close_reopen_pair_ck check ((reopened_at is null) = (reopened_by is null)),
  constraint so_backorder_close_active_uq      unique (active_line_id)
);
create index if not exists so_backorder_close_line_idx       on public.so_backorder_close (so_line_id);
create index if not exists so_backorder_close_taken_so_idx   on public.so_backorder_close (taken_by_so_id);
create index if not exists so_backorder_close_taken_line_idx on public.so_backorder_close (taken_by_line_id);
create index if not exists so_backorder_close_ended_idx      on public.so_backorder_close (ended_at);
create index if not exists so_backorder_close_ended_by_idx   on public.so_backorder_close (ended_by);
create index if not exists so_backorder_close_reopened_by_idx on public.so_backorder_close (reopened_by);
create index if not exists so_backorder_close_updated_by_idx on public.so_backorder_close (updated_by);
comment on table public.so_backorder_close is
  '⭐ 백오더 장부(③b · 판정 2~5·10·11 · ⬜7) — 백오더 줄(so_reserve kind backorder)이 끝난 방식만 적는다: superseded(새 오더가 확정 때 이어받았다 · qty_taken + qty_unwanted = qty_open · taken_by_*) · expired(만료 스윕 ③c · ended_by null) · proceeded(so_backorder_proceed 가 잡아 진행) · cancelled(백오더 오더 자체를 취소). 누가·무엇을·몇 개·언제는 오더·줄이 · 「열려 있다」는 so_reserve 가 말한다(5-g 두 번 적지 않는다). 다시 열면(so_unconfirm · so_cancel true) reopened_at/by · active_line_id 로 줄당 활성 한 줄. ⭐ 거래 — 컷오버 때 지운다 · 쓰기는 창구만(select 정책 · select grant)';
comment on column public.so_backorder_close.end_kind is 'CHECK 넷 superseded · expired · proceeded · cancelled — manual(사람이 손으로 닫기 5-g ②)은 그 창구가 설 때 더한다(안 도는 값을 두지 않는다)';
comment on column public.so_backorder_close.qty_taken is '이어받은 수량 = 새 오더에서 손님이 주문한 수량(나간 수량이 아니다 · 판정 3) · 가장 오래된 줄부터 채운다(판정 4)';
comment on column public.so_backorder_close.qty_unwanted is '더 원하지 않은 수량 — 60 주문 뒤 30 재주문이면 30(판정 3 「30씩 나눠 가져갈 근거는 없다」) · 새 수량이 다 찬 뒤의 줄은 전량';
comment on column public.so_backorder_close.active_line_id is '생성 칸 — reopened_at 이 null 이면 so_line_id · 유니크 so_backorder_close_active_uq(줄당 활성 한 줄 · 다시 연 줄은 비운다) · 부분 유니크 인덱스 금지(규칙 29)';

alter table public.so_backorder_close enable row level security;
create policy so_backorder_close_select on public.so_backorder_close for select to authenticated using (true);
create trigger so_backorder_close_touch before update on public.so_backorder_close for each row execute function public.ims_touch();
revoke all on public.so_backorder_close from public, anon, authenticated;
grant select on public.so_backorder_close to authenticated;

-- ═══ ② so_line.backorder_notified_at — 알림 한 번(판정 3 · 회신 이견 8) ═══
alter table public.so_line add column if not exists backorder_notified_at timestamptz;
comment on column public.so_line.backorder_notified_at is
  '⭐ 백오더 입고 알림을 보낸 때 — 제품(줄)마다 한 번(판정 3 · Caleb 「알림은 한번만」). ⚠️ 지금은 아무도 채우지 않는다 — GAS 가 Cin7 에서 보낸다(2-g ⬜ 알림을 IMS 로 옮길 때부터) · 병행 기간 화면의 「안 보냄」은 거짓일 수 있다(「IMS 알림 전」 표시 · 말만)';

-- ═══ ③-a so_backorder_record — 장부 한 줄(속 · 예약 닫기는 부르는 쪽이 한다 · released_reason ''closed'') ═══
create function public.so_backorder_record(
  p_line_id       uuid,
  p_end_kind      text,
  p_qty_open      numeric,
  p_qty_taken     numeric,
  p_qty_unwanted  numeric,
  p_taken_by_so   uuid,
  p_taken_by_line uuid,
  p_staff         uuid,
  p_note          text
) returns uuid
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if not exists (select 1 from public.so_line l where l.id = p_line_id) then
    raise exception 'Backorder line % not found — nothing was saved', p_line_id;
  end if;
  insert into public.so_backorder_close (so_line_id, end_kind, qty_open, qty_taken, qty_unwanted, taken_by_so_id, taken_by_line_id, ended_by, note, updated_by)
  values (p_line_id, p_end_kind, p_qty_open, coalesce(p_qty_taken, 0), coalesce(p_qty_unwanted, 0), p_taken_by_so, p_taken_by_line, p_staff, nullif(trim(p_note), ''), p_staff)
  returning id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception 'Backorder line % already has an active ledger entry — reopen it before closing it again — nothing was saved', p_line_id;
end;
$$;
comment on function public.so_backorder_record(uuid, text, numeric, numeric, numeric, uuid, uuid, uuid, text) is 'SO 창구 속 함수(③b) — 장부 so_backorder_close 한 줄 · CHECK 가 짝을 지킨다 · 줄당 활성 한 줄(유니크 → 읽을 수 있는 문장) · 예약을 닫는 것은 부르는 쪽(released_reason closed)';
revoke all on function public.so_backorder_record(uuid, text, numeric, numeric, numeric, uuid, uuid, uuid, text) from public, anon, authenticated;

-- ═══ ③-b so_backorder_supersede — 확정 때 이어받기(속 · so_confirm 끝에서 · commit 만) ═══
--   대상: 같은 customer_id · 같은 product_id · kind backorder 열린 줄 · 그 오더 confirmed · 가족 밖(so_number base 가 다르다 · 자기 형제를 닫지 않는다) · 브랜치 무관(판정 8) · 프리오더 제외(판정 9)
--   새 수량 = 이 확정의 그 제품 주문 수량 합(원래 + 이 확정에서 태어난 형제 — split_from_id = 원래 · confirmed_at = created_at = 원래 confirmed_at) · 대표 줄 = 원래 오더의 그 제품 첫 줄(없으면 형제의)
--   가장 오래된 줄부터(order_date · created_at · so_number · line_no) qty_taken · 모자라면 나머지 전량 qty_unwanted(판정 4) · 예약은 closed · 오더는 닫지 않는다(판정 11)
create function public.so_backorder_supersede(p_so_id uuid, p_staff uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so    public.so%rowtype;
  v_base  text;
  k       record;
  t       record;
  v_rem   numeric;
  v_take  numeric;
  v_n     int := 0;
  v_out   jsonb := '[]'::jsonb;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' or v_so.confirmed_at is null then
    raise exception 'Order % is % — backorders are taken over at confirmation only — nothing was saved', v_so.so_number, v_so.status;
  end if;
  v_base := regexp_replace(v_so.so_number, '[a-z]+$', '');

  for k in
    select l.product_id, sum(l.qty_ordered) as qty,
           (array_agg(l.id order by (s.id <> p_so_id), s.so_number, l.line_no))[1] as line_id
    from public.so_line l join public.so s on s.id = l.so_id
    where s.id = p_so_id
       or (s.split_from_id = p_so_id and s.confirmed_at = v_so.confirmed_at and s.created_at = v_so.confirmed_at)
    group by l.product_id
  loop
    v_rem := k.qty;
    for t in
      select res.id as reserve_id, res.qty_allocated, l.id as line_id, l.line_no, l.sku, s.so_number, s.order_date, s.location_name
      from public.so_reserve res
      join public.so_line l on l.id = res.so_line_id
      join public.so s on s.id = l.so_id
      where res.kind = 'backorder' and res.released_at is null
        and s.status = 'confirmed'
        and s.customer_id = v_so.customer_id
        and l.product_id = k.product_id
        and regexp_replace(s.so_number, '[a-z]+$', '') <> v_base
      order by s.order_date, s.created_at, s.so_number, l.line_no
    loop
      perform pg_advisory_xact_lock(hashtext('so_reserve:' || t.line_id::text));
      v_take := least(t.qty_allocated, v_rem);
      perform public.so_backorder_record(t.line_id, 'superseded', t.qty_allocated, v_take, t.qty_allocated - v_take, p_so_id, k.line_id, p_staff, null);
      update public.so_reserve set released_at = now(), released_by = p_staff, released_reason = 'closed', updated_by = p_staff
      where id = t.reserve_id and released_at is null;
      v_rem := v_rem - v_take;
      v_n := v_n + 1;
      v_out := v_out || jsonb_build_object('so_number', t.so_number, 'line_no', t.line_no, 'sku', t.sku, 'order_date', t.order_date, 'location', t.location_name,
                                           'qty_open', t.qty_allocated, 'qty_taken', v_take, 'qty_unwanted', t.qty_allocated - v_take, 'taken_by_line_id', k.line_id);
    end loop;
  end loop;
  return jsonb_build_object('lines_closed', v_n, 'lines', v_out);
end;
$$;
comment on function public.so_backorder_supersede(uuid, uuid) is
  '⭐ 확정 때 이어받기(③b · 판정 3·4·5·8·9 · so_confirm 끝에서 commit 만) — 같은 손님·같은 제품의 열린 백오더 줄(가족 밖 · confirmed · 브랜치 무관 · 프리오더 제외)을 가장 오래된 줄부터 새 수량으로 채우고(qty_taken) 나머지는 더 원하지 않음(qty_unwanted) · 예약 closed · 장부 superseded(taken_by = 확정한 오더 · 그 제품의 첫 줄) · 오더는 닫지 않는다(판정 11 · 만료가 닫는다)';
revoke all on function public.so_backorder_supersede(uuid, uuid) from public, anon, authenticated;

-- ═══ ③-c so_backorder_reopen — 다시 열기(속 · so_unconfirm · so_cancel true) ═══
--   대상 = taken_by_so_id ∈ p_taken_by ∧ reopened_at null · 그 백오더 오더가 confirmed 일 때만(만료·취소 뒤 거부 · 판정 11) · 줄에 열린 예약이 있으면 거부(어긋남) · 새 backorder 예약(qty_open)
create function public.so_backorder_reopen(p_taken_by uuid[], p_staff uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  c     record;
  v_n   int := 0;
  v_out jsonb := '[]'::jsonb;
begin
  for c in
    select x.id, x.so_line_id, x.qty_open, l.line_no, l.sku, s.so_number, s.status, t.so_number as taken_by
    from public.so_backorder_close x
    join public.so_line l on l.id = x.so_line_id
    join public.so s on s.id = l.so_id
    join public.so t on t.id = x.taken_by_so_id
    where x.taken_by_so_id = any(coalesce(p_taken_by, '{}'::uuid[])) and x.reopened_at is null
    order by s.so_number, l.line_no
  loop
    if c.status <> 'confirmed' then
      raise exception 'Backorder line % of % (taken over by %) cannot be reopened — that order is now % — nothing was saved', c.line_no, c.so_number, c.taken_by, c.status;
    end if;
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || c.so_line_id::text));
    if exists (select 1 from public.so_reserve r where r.so_line_id = c.so_line_id and r.released_at is null) then
      raise exception 'Backorder line % of % already has an open reservation — it cannot be reopened — nothing was saved', c.line_no, c.so_number;
    end if;
    update public.so_backorder_close set reopened_at = now(), reopened_by = p_staff, updated_by = p_staff where id = c.id and reopened_at is null;
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (c.so_line_id, c.qty_open, 'backorder', null);
    v_n := v_n + 1;
    v_out := v_out || jsonb_build_object('so_number', c.so_number, 'line_no', c.line_no, 'sku', c.sku, 'qty_open', c.qty_open, 'taken_by', c.taken_by);
  end loop;
  return jsonb_build_object('lines_reopened', v_n, 'lines', v_out);
end;
$$;
comment on function public.so_backorder_reopen(uuid[], uuid) is
  '⭐ 다시 열기(③b · 판정 5·10·11) — p_taken_by(확정을 무르는 오더 · 취소되는 오더들)가 이어받아 닫은 장부 줄을 reopened 로 표시하고 그 줄에 backorder 예약(qty_open)을 다시 건다 · 대상 백오더 오더가 confirmed 가 아니면(만료·취소 뒤) 거부 — 그때 되돌리기·취소도 함께 거부된다';
revoke all on function public.so_backorder_reopen(uuid[], uuid) from public, anon, authenticated;

-- ═══ ④-a so_confirm 재발행 — 마지막 정의 20260924014219:456~533 · 더한 줄 3(commit 이면 이어받기) · create → create or replace ═══
create or replace function public.so_confirm(
  p_so_id              uuid,
  p_preorder_line_ids  uuid[]  default '{}'::uuid[],   -- 사람이 고른 프리오더 줄(6-d) · 따로 뗀다(R2)
  p_hold               boolean default false,          -- 처음부터 보류로 확정(R3 · 오더 전체 · 재고를 잡지 않고 나누지 않는다)
  p_commit             boolean default true            -- false = 미리 보기(무엇이 할당·백오더·프리오더로 가나)
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  c        public.customer%rowtype;
  v_wh     public.ref_warehouse%rowtype;
  v_bad    text;
  v_n      int;
  v_warn   text[] := '{}';
  v_res    jsonb;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — sales 묶음
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — manager 이상(R5)
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  if v_so.channel <> 'warehouse' then
    raise exception 'Order % is a % order — confirming pos and counter orders comes in a later step — nothing was saved', v_so.so_number, v_so.channel;
  end if;
  if p_hold and coalesce(array_length(p_preorder_line_ids, 1), 0) > 0 then
    raise exception 'Choose either hold (whole order) or preorder lines, not both — nothing was saved';
  end if;

  -- R6 막는 조건 — 손님 · 창고 · 줄
  select * into c from public.customer where id = v_so.customer_id;
  if not found or not c.is_active then
    raise exception 'Customer % is inactive — reactivate it first — nothing was saved', coalesce(c.name, '?');
  end if;
  if v_so.location_id is null then
    raise exception 'Order % has no warehouse — set one before confirming — nothing was saved', v_so.so_number;
  end if;
  select * into v_wh from public.ref_warehouse where id = v_so.location_id;
  if not found or not v_wh.is_active then                       -- IN_TRANSIT 은 is_active=false 로 들어 있어 여기서 걸린다(이견 11)
    raise exception 'Warehouse % is inactive — pick an active warehouse — nothing was saved', coalesce(v_wh.name, '?');
  end if;
  select count(*) into v_n from public.so_line where so_id = p_so_id;
  if v_n = 0 then
    raise exception 'Order % has no lines — nothing was saved', v_so.so_number;
  end if;
  select string_agg(l.sku, ', ' order by l.line_no) into v_bad from public.so_line l where l.so_id = p_so_id and l.unit_price is null;
  if v_bad is not null then
    raise exception 'Order % has lines without a price (%) — give them a price first — nothing was saved', v_so.so_number, v_bad;
  end if;
  select string_agg(l.sku, ', ' order by l.line_no) into v_bad
  from public.so_line l join public.product p on p.id = l.product_id where l.so_id = p_so_id and not p.is_active;
  if v_bad is not null then
    raise exception 'Order % has inactive products (%) — remove them first — nothing was saved', v_so.so_number, v_bad;
  end if;
  select string_agg(x::text, ', ') into v_bad
  from unnest(coalesce(p_preorder_line_ids, '{}'::uuid[])) x where not exists (select 1 from public.so_line l where l.id = x and l.so_id = p_so_id);
  if v_bad is not null then
    raise exception 'Preorder line % is not on order % — nothing was saved', v_bad, v_so.so_number;
  end if;

  -- 경고(막지 않는다) — 티어·통화 · 다시 매기기 권고 · 세일 끝난 뒤 넣은 줄
  v_warn := public.so_tier_warnings(v_so);
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  if exists (select 1 from public.so_line l where l.so_id = p_so_id and l.deal_line_id is not null
               and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)) then
    v_warn := array_append(v_warn, 'deal_ended_before_line_added');
  end if;

  v_res := public.so_allocate_run(p_so_id, v_so.location_id, p_preorder_line_ids, p_hold, true, p_commit, v_staff);
  if p_commit then                                               -- ③b 판정 4·5·8: 같은 손님·같은 제품의 열린 백오더 줄을 이어받는다(가족 밖 · 브랜치 무관 · 가장 오래된 줄부터 · 나머지는 더 원하지 않음)
    v_res := v_res || jsonb_build_object('superseded', public.so_backorder_supersede(p_so_id, v_staff));
  end if;
  return v_res || jsonb_build_object('warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_confirm(uuid, uuid[], boolean, boolean) is
  '⭐ SO 확정(②a · R1·R2·R3·R5·R6 · 6-d) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · draft 만 · warehouse 채널만(pos·counter 는 ④). 막는 것: 비활성 손님 · 창고 없음/비활성(IN_TRANSIT 포함) · 줄 없음 · 가격 없는 줄 · 비활성 제품 · 오더 밖 프리오더 줄 · hold 와 preorder 동시. 경고: 티어·통화 · reprice_suggested · deal_ended_before_line_added. 엔진 so_allocate_run: 잡을 수 있는 만큼 잡고 모자란 몫은 백오더 형제(a) · 프리오더 줄은 형제(b) · 원래는 가장 앞선 무리를 지킨다(빈 문서 없음) · p_hold = 오더 전체 보류로 확정(재고 안 잡음 · 안 나눔) · p_commit false = 미리 보기. 반환 {so_number · status · committed · keeps · lines[] · siblings[] · warnings}';
revoke all on function public.so_confirm(uuid, uuid[], boolean, boolean) from public, anon;
grant execute on function public.so_confirm(uuid, uuid[], boolean, boolean) to authenticated;

-- ═══ ④-b so_unconfirm 재발행 — 마지막 정의 20260924023740:7~105 · 더한 줄(선언 1 · 다시 열기 3) · 반환에 backorders_reopened ═══
create or replace function public.so_unconfirm(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_so      public.so%rowtype;
  s         public.so%rowtype;
  l         public.so_line%rowtype;
  v_next    int;
  v_merged  text[] := '{}';
  v_moved   int := 0;  v_added int := 0;  v_released int := 0;
  v_reopen  jsonb;                                              -- ③b: 이 확정이 이어받아 닫은 남의 백오더 줄
  v_n       int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('supervisor', 'saved');       -- ⭐ 둘째 줄 — supervisor 이상(R9)
  v_staff := public.so_current_staff();

  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — only a confirmed order still in IMS can be unconfirmed (if it went to the warehouse, roll it back in WMS first) — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if v_so.split_from_id is not null and v_so.confirmed_at is not null
     and exists (select 1 from public.so m where m.id = v_so.split_from_id and m.confirmed_at = v_so.confirmed_at) then
    raise exception 'Order % was itself split off at confirmation — unconfirm the original order % instead — nothing was saved',
      v_so.so_number, (select m.so_number from public.so m where m.id = v_so.split_from_id);
  end if;

  perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(v_so.so_number, '[a-z]+$', '')));

  -- ⭐ 사슬로 판정한다 — 시각에만 기대지 않는다(2026-09-24 결함 고침: 한 트랜잭션에서 so_divide 로 난 형제의 created_at 이 confirmed_at 과 같았다)
  if exists (select 1 from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason = 'manual') then
    raise exception 'Order % has a hand-made split order (%) — unconfirm is not possible while it is open (cancel or merge it first) — nothing was saved',
      v_so.so_number, (select string_agg(x.so_number, ', ' order by x.so_number) from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason = 'manual');
  end if;

  -- 형제 검사(자기 행만 보는 것이 아니라 여기서 다른 행을 본다 — RPC 의 일 · 6-g′) · ⭐ 열린 자식만(cancelled = 앞선 되돌리기로 merged 된 것·취소된 것은 무시 · 2026-09-24 결함 고침)
  for s in select * from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason in ('stock_short','preorder') order by x.so_number loop
    if s.created_at is distinct from v_so.confirmed_at then
      raise exception 'Order % was split again after confirmation (%) — unconfirm only undoes the split made at confirmation — nothing was saved', v_so.so_number, s.so_number;
    end if;
    if s.status <> 'confirmed' then
      raise exception 'Split order % is % — it must still be confirmed and in IMS to merge it back — nothing was saved', s.so_number, s.status;
    end if;
    if exists (select 1 from public.so y where y.split_from_id = s.id) then
      raise exception 'Split order % has itself been split again (%) — unconfirm is not possible — nothing was saved',
        s.so_number, (select string_agg(y.so_number, ', ' order by y.so_number) from public.so y where y.split_from_id = s.id);
    end if;
    if s.updated_at is distinct from s.created_at
       or exists (select 1 from public.so_line x where x.so_id = s.id and x.updated_at is distinct from s.created_at)
       or exists (select 1 from public.so_reserve r join public.so_line x on x.id = r.so_line_id where x.so_id = s.id and r.released_at is null and r.updated_at is distinct from s.created_at)   -- 열린 예약만 · 풀린 이력은 무시(2026-09-24 결함 고침 — 돌아온 줄이 옛 풀림을 달고 온다)
       or exists (select 1 from public.so_charge ch where ch.so_id = s.id) then
      raise exception 'Split order % was changed after the split — unconfirm is only possible while the split orders are untouched — nothing was saved', s.so_number;
    end if;
  end loop;

  -- ③b 판정 5·⬜8: 이 확정이 이어받아 닫은 남의 백오더 줄을 다시 연다 — 대상 백오더 오더가 끝 상태(만료·취소)면 거부(판정 11) · 쓰기 전에 먼저(거부면 아무것도 안 쓴다)
  v_reopen := public.so_backorder_reopen(array[p_so_id], v_staff);

  -- 예약 전부 풀기 — 원래(allocated · hold · backorder · preorder) + 형제(backorder · preorder) · 지우지 않는다(5-f)
  update public.so_reserve r set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x
  where x.id = r.so_line_id and r.released_at is null
    and (x.so_id = p_so_id or x.so_id in (select id from public.so where split_from_id = p_so_id and status <> 'cancelled' and split_reason in ('stock_short','preorder')));
  get diagnostics v_released = row_count;

  -- 형제 줄 도로 합치기 · 형제 닫기
  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_so_id;
  for s in select * from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason in ('stock_short','preorder') order by x.so_number loop
    for l in select * from public.so_line x where x.so_id = s.id order by x.line_no loop
      if l.split_from_line_id is not null then
        update public.so_line set qty_ordered = qty_ordered + l.qty_ordered, updated_by = v_staff
        where id = l.split_from_line_id and so_id = p_so_id;
        get diagnostics v_n = row_count;
        if v_n <> 1 then raise exception 'Line % of % has lost its original line — nothing was saved', l.line_no, s.so_number; end if;
        v_added := v_added + 1;                                  -- 형제 줄 행은 이력으로 남는다(합계는 merged 문서를 뺀다)
      else
        v_next := v_next + 1;
        update public.so_line set so_id = p_so_id, line_no = v_next, updated_by = v_staff where id = l.id;
        v_moved := v_moved + 1;
      end if;
    end loop;
    update public.so set status = 'cancelled', closed_reason = 'merged', merged_into_id = p_so_id, closed_at = now(),
                         closed_note = format('Unconfirmed with %s', v_so.so_number), cancelled_by = v_staff, updated_by = v_staff
    where id = s.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Split order % was not merged back — it may have been changed by someone else just now — nothing was saved', s.so_number; end if;
    v_merged := array_append(v_merged, s.so_number);
  end loop;

  -- 원래 → draft · 되돌리기 기록 · 확정 흔적 비움(다시 확정하면 새로 찍힌다)
  update public.so set status = 'draft', confirmed_at = null, confirmed_by = null, unconfirmed_at = now(), unconfirmed_by = v_staff, updated_by = v_staff
  where id = p_so_id and status = 'confirmed';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Order % was not unconfirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

  return jsonb_build_object('so_number', v_so.so_number, 'status', 'draft', 'merged', to_jsonb(v_merged),
                            'lines_moved_back', v_moved, 'lines_added_back', v_added, 'reserves_released', v_released,
                            'backorders_reopened', v_reopen);
end;
$$;


-- ═══ ④-c so_cancel 재발행 — 마지막 정의 20260924022449:88~150 · ⭐ 시그니처 +p_reopen_superseded boolean default null → drop + create(asung-workflow §4) · 더한 줄: 선언 1 · 이어받은 줄 목록 · null 거부 · 백오더 줄 cancelled · 다시 열기 ═══
drop function if exists public.so_cancel(uuid, text, uuid[], boolean);
create function public.so_cancel(p_so_id uuid, p_note text, p_keep uuid[] default '{}'::uuid[], p_commit boolean default true, p_reopen_superseded boolean default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_note text;  r record;
  v_plan jsonb := '[]'::jsonb;  v_cancel uuid[] := '{}';  v_warn text[] := '{}';  v_released int := 0;  v_n int;
  v_taken jsonb := '[]'::jsonb;  v_taken_n int := 0;  v_reopen jsonb := null;  v_bo int := 0;     -- ③b 판정 10: 이어받은 장부 줄 · 다시 열기 · 취소되는 백오더 줄
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'A cancel needs a reason (p_note) — nothing was saved'; end if;
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status not in ('draft', 'confirmed') then
    raise exception 'Order % is % — only a draft or confirmed order still in IMS can be cancelled (if it went to the warehouse, roll it back in WMS first) — nothing was saved', v_so.so_number, v_so.status;
  end if;
  perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(v_so.so_number, '[a-z]+$', '')));

  -- 자손(열린 것만) · path 로 「살린 형제 아래」를 가른다
  for r in
    with recursive down as (
      select s.id, s.so_number, s.status, s.split_reason, 0 as depth, array[s.id] as path from public.so s where s.id = p_so_id
      union all
      select c.id, c.so_number, c.status, c.split_reason, down.depth + 1, down.path || c.id
      from down join public.so c on c.split_from_id = down.id
      where down.depth < 50 and not (c.id = any(down.path)) and c.status <> 'cancelled'
    )
    select d.*, (d.path && p_keep) as kept from down d order by d.so_number
  loop
    if r.kept then
      v_plan := v_plan || jsonb_build_object('so_number', r.so_number, 'status', r.status, 'split_reason', r.split_reason, 'action', 'kept');
    elsif r.status not in ('draft', 'confirmed') then
      v_plan := v_plan || jsonb_build_object('so_number', r.so_number, 'status', r.status, 'split_reason', r.split_reason, 'action', 'in_warehouse_untouched');
      v_warn := array_append(v_warn, 'sibling_in_warehouse:' || r.so_number);
    else
      v_plan := v_plan || jsonb_build_object('so_number', r.so_number, 'status', r.status, 'split_reason', r.split_reason, 'action', 'cancel');
      v_cancel := array_append(v_cancel, r.id);
    end if;
  end loop;
  if not (p_so_id = any(v_cancel)) then
    raise exception 'Order % itself is in p_keep — nothing was saved', v_so.so_number;
  end if;
  -- ③b 판정 10: 취소 대상(자손 포함)이 이어받아 닫은 남의 백오더 줄(장부 · 다시 열지 않은 것) — 미리 보기에 목록 · commit 은 p_reopen_superseded 로 사람이 고른다(§7-e 「시스템이 짐작하지 않는다」)
  select coalesce(jsonb_agg(jsonb_build_object('close_id', c.id, 'so_number', s.so_number, 'line_no', l.line_no, 'sku', l.sku, 'qty_open', c.qty_open, 'qty_taken', c.qty_taken, 'qty_unwanted', c.qty_unwanted,
                                              'taken_by', t.so_number, 'target_status', s.status) order by s.so_number, l.line_no), '[]'::jsonb), count(*)
    into v_taken, v_taken_n
  from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.so s on s.id = l.so_id join public.so t on t.id = c.taken_by_so_id
  where c.taken_by_so_id = any(v_cancel) and c.reopened_at is null;
  if not p_commit then
    return jsonb_build_object('so_number', v_so.so_number, 'committed', false, 'note', v_note, 'orders', v_plan, 'superseded_lines', v_taken, 'warnings', to_jsonb(v_warn));
  end if;
  if v_taken_n > 0 and p_reopen_superseded is null then
    raise exception 'Order % took over % backorder line(s) from earlier orders — choose whether to reopen them (p_reopen_superseded true or false) — nothing was saved', v_so.so_number, v_taken_n;
  end if;
  -- ③b: 취소되는 오더의 열린 백오더 줄은 장부에 cancelled 로 적고 예약을 closed 로 닫는다(아래 일괄 풀기 앞) — 백오더가 조용히 사라지지 않게
  for r in
    select res.id as reserve_id, res.so_line_id, res.qty_allocated
    from public.so_reserve res join public.so_line x on x.id = res.so_line_id
    where res.released_at is null and res.kind = 'backorder' and x.so_id = any(v_cancel)
  loop
    perform public.so_backorder_record(r.so_line_id, 'cancelled', r.qty_allocated, 0, 0, null, null, v_staff, v_note);
    update public.so_reserve set released_at = now(), released_by = v_staff, released_reason = 'closed', updated_by = v_staff where id = r.reserve_id;
    v_bo := v_bo + 1;
  end loop;
  if v_taken_n > 0 and p_reopen_superseded then                 -- true = so_unconfirm 과 같은 다시 열기 · false = 닫힌 채(손님의 새 답)
    v_reopen := public.so_backorder_reopen(v_cancel, v_staff);
  end if;

  update public.so_reserve res set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x where x.id = res.so_line_id and res.released_at is null and x.so_id = any(v_cancel);
  get diagnostics v_released = row_count;
  update public.so set status = 'cancelled', closed_reason = 'voided', closed_note = v_note, closed_at = now(), cancelled_by = v_staff, updated_by = v_staff
  where id = any(v_cancel) and status in ('draft', 'confirmed');
  get diagnostics v_n = row_count;
  if v_n <> coalesce(array_length(v_cancel, 1), 0) then
    raise exception 'Not every order could be cancelled — one may have been changed by someone else just now — nothing was saved';
  end if;
  return jsonb_build_object('so_number', v_so.so_number, 'committed', true, 'note', v_note, 'orders', v_plan, 'cancelled', v_n, 'reserves_released', v_released,
                            'backorder_lines_recorded', v_bo, 'superseded_lines', v_taken, 'reopen_superseded', p_reopen_superseded, 'reopened', v_reopen, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_cancel(uuid, text, uuid[], boolean, boolean) is '⭐ 취소(②b · R4 · Caleb 「취소할 때 형제도 함께」) — definer · sales + manager · draft·confirmed(릴리스 전)만 · p_note 필수 → closed_note · closed_reason voided · closed_at · cancelled_by · 잡아 둔 예약 전부 풀기(어느 kind 든) · ⭐ 범위 = 이 오더 + split_from 사슬 아래 열린 자손 전부(같은 note) · p_keep 에 든 형제와 그 아래는 살린다(뺄 목록) · 창고로 간 자손(at_wms 이상)은 건드리지 않고 warnings sibling_in_warehouse · p_commit false = 함께 닫히는 형제 목록만 · 예약 이력 있는 draft 도 여기로(so_delete 가 안내)';
revoke all on function public.so_cancel(uuid, text, uuid[], boolean, boolean) from public, anon;
grant execute on function public.so_cancel(uuid, text, uuid[], boolean, boolean) to authenticated;

-- ═══ ④-d so_backorder_proceed 재발행 — 마지막 정의 20260924022449:208~243 · 더한 줄(선언 1 · 풀기 전 담기 3 · 잡힌 줄 장부 proceeded 9) · create → create or replace ═══
create or replace function public.so_backorder_proceed(p_so_id uuid, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_res jsonb;  v_n int;
  v_bo jsonb := '[]'::jsonb;  bo record;  v_ended int := 0;                       -- ③b: 진행 전 열린 백오더 줄 · 잡힌 줄은 장부 proceeded
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — only a confirmed backorder still in IMS can proceed — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if v_so.location_id is null then raise exception 'Order % has no warehouse — nothing was saved', v_so.so_number; end if;
  begin
    select coalesce(jsonb_agg(jsonb_build_object('line_id', res.so_line_id, 'qty', res.qty_allocated, 'reserve_id', res.id)), '[]'::jsonb) into v_bo
    from public.so_reserve res join public.so_line x on x.id = res.so_line_id
    where x.so_id = p_so_id and res.released_at is null and res.kind = 'backorder';                 -- ③b: 풀기 전에 담아 둔다
    update public.so_reserve r set released_at = now(), released_by = v_staff, updated_by = v_staff
    from public.so_line x where x.id = r.so_line_id and x.so_id = p_so_id and r.released_at is null and r.kind in ('backorder', 'preorder');
    get diagnostics v_n = row_count;
    if v_n = 0 then
      raise exception 'Order % has no backorder or preorder lines to proceed — nothing was saved', v_so.so_number;
    end if;
    v_res := public.so_allocate_run(p_so_id, v_so.location_id, '{}'::uuid[], false, false, p_commit, v_staff) || jsonb_build_object('lines_released', v_n);
    -- ③b 판정 2: 엔진이 잡은 줄(이 오더에 남아 allocated 예약이 열린 줄)은 백오더가 끝났다 → 장부 proceeded · 옛 예약은 closed · 못 잡아 형제로 간 줄은 같은 줄이 이어진다(장부 없음)
    for bo in select (e->>'line_id')::uuid as line_id, (e->>'qty')::numeric as qty, (e->>'reserve_id')::uuid as reserve_id from jsonb_array_elements(v_bo) e loop
      if exists (select 1 from public.so_reserve a join public.so_line x on x.id = a.so_line_id where a.so_line_id = bo.line_id and x.so_id = p_so_id and a.released_at is null and a.kind = 'allocated') then
        perform public.so_backorder_record(bo.line_id, 'proceeded', bo.qty, 0, 0, null, null, v_staff, null);
        update public.so_reserve set released_reason = 'closed', updated_by = v_staff where id = bo.reserve_id;
        v_ended := v_ended + 1;
      end if;
    end loop;
    v_res := v_res || jsonb_build_object('backorder_lines_ended', v_ended);
    if not p_commit then
      raise exception using errcode = 'P0777', message = v_res::text;
    end if;
  exception when sqlstate 'P0777' then
    v_res := sqlerrm::jsonb;
  end;
  return v_res;
end;
$$;
comment on function public.so_backorder_proceed(uuid, boolean) is '⭐ 백오더 진행(②b · R8 · Caleb 「백오더에서 1개의 sku만 스플릿 해서 진행」) — definer · sales + manager · confirmed · 열린 backorder(·preorder) 예약을 풀고 엔진 so_allocate_run — 잡을 수 있는 줄은 이 오더에 allocated 로 남아 진행 · 못 잡은 줄은 새 백오더 형제(다음 글자 · stock_short) · 전부 못 잡으면 그대로 백오더(형제 없음) · p_commit false = 미리 보기(하위 블록에서 되돌린다) · 프리오더 오더도 같은 길로 진행한다(물건이 들어왔다)';
revoke all on function public.so_backorder_proceed(uuid, boolean) from public, anon;
grant execute on function public.so_backorder_proceed(uuid, boolean) to authenticated;

-- ═══ 검증(Caleb · ~/asung/prompts/so-write-3b-verify.sql · psql -v ON_ERROR_STOP=1 -f) — vv 예(100 → 80 → 60 · 60 → 80 · 여러 줄 + 새 30 · 다른 브랜치 · 자기 형제 안 닫힘 · proceed/change_location 안 닫음 · 되돌리기 다시 엶 · 취소 p_reopen true/false/null) · MISMATCH 기대·실제
