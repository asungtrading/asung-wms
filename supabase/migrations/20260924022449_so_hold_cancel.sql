-- SO 쓰기 ②b — 보류 · 다시 잡기 · 취소(형제 함께) · 창고 바꾸기 · 백오더 진행 · 오더 나누기 · so_detail·so_delete 재발행 (2026-09-24 UTC · 토론토 2026-09-23 밤)
-- 지시서 ~/asung/prompts/so-write-2-confirm.md · 판정 Caleb 2026-09-23(R3·R4·R7·R8 · 이견 2 고침 「보류는 늘 오더 전체」 · 추가 판정 「오더 나누기」 · 「취소할 때 형제도 함께」) · 정본 §14(말만)
-- 바탕: ②a 다섯(20260924014219 so_confirm/so_split/so_allocate_run/so_family_* · 015859 so_available_many · 020852 grant · 021413·021759 so_unconfirm) ·
--       so_detail 마지막 정의 20260923232500:970 · so_delete 마지막 정의 20260923191030:948 — 둘을 create or replace 로 재발행(diff 는 회신)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
--
-- ⭐ 창구 여섯(전부 definer · 첫 줄 ims_require_write('sales') · 둘째 줄 so_require_role('manager') · 릴리스 전(draft·confirmed)만 · 미리 보기는 p_commit=false)
--    so_hold(so_id)                              보류 — 오더 전체 · 열린 allocated 전부 풀고(released_at/by) 줄마다 kind hold · 상태 무접촉 · 할당이 없으면 거부
--    so_reallocate(so_id)                        보류 풀기 — 열린 hold 전부 풀고 엔진(so_allocate_run)으로 다시 잡는다 · 모자란 몫은 R1 대로 백오더 형제(여기서 처음 나뉠 수 있다)
--    so_cancel(so_id, p_note, p_keep, p_commit)  취소 — closed_reason voided · closed_note 필수 · 잡아 둔 재고 전부 풀기 · draft·confirmed 둘 다 · ⭐ 열린 자손(split_from 사슬 아래 · IMS 안)도 함께 · p_keep 에 든 형제(와 그 아래)는 살린다 · 창고로 간 형제는 건드리지 않고 알린다
--    so_change_location(so_id, location_id, p_commit)  창고 바꾸기 — 확정 오더 · 릴리스 전 · 활성 창고만(IN_TRANSIT 은 비활성) · 할당이 있으면 전부 풀고 새 창고에서 엔진 · 모자란 몫은 백오더 형제(stock_short · R7) · hold·백오더·프리오더 오더는 창고 칸만
--    so_backorder_proceed(so_id, p_commit)       백오더 진행 — 열린 backorder(·preorder) 줄을 풀고 엔진 · 잡힌 줄은 이 오더가 진행 · 못 잡은 줄은 새 백오더 형제(R8)
--    so_divide(so_id, p_moves, p_commit)         오더 나누기(사람) — draft·confirmed · [{line_id, qty}] · split_reason manual · confirmed 면 떼어 낸 수량의 예약도 같은 kind 로 따라간다(풀고 → 새로 걸기 · 엔진 안 거침 · 가용 재검사 없음) · draft 면 형제도 draft · 전부 떼어 내기 거부
-- ⭐ 미리 보기 규칙 — 풀기가 필요한 계산(창고 바꾸기 · 백오더 진행)은 하위 블록에서 풀고 엔진을 돌린 뒤 예외로 되돌린다(식 한 곳 · 엔진이 계산한다) · 취소·나누기 미리 보기는 읽기만
-- ⭐ 재발행 둘 — so_detail: family(so_family_members) · 줄마다 열린 예약 kind·qty · 가용은 so_available_many 한 번(줄마다 부르지 않는다 · 100줄 = 15초) · so_delete: 문장 「cancel it instead」
-- ⚠️ 「같은 시각」(so_unconfirm)과의 관계 — 이 파일의 창구는 형제를 만들거나(so_divide · 창고 바꾸기 · 백오더 진행) 고친다(so_hold 등) · 만든 형제는 created_at ≠ 원래 confirmed_at 이라 so_unconfirm 이 「split again after confirmation」으로 거부한다 ·
--    한 창구 안에서 「나누고 바로 고치는」 길은 여기 없다(so_divide 는 만들기만) — 생기면 「같은 시각」 판정이 무너진다(정본 §14 사실)
-- ⚠️ 다시 만들지 않은 것 — so_allocate_run · so_split · so_available(_many) · so_family_* · so_confirm · so_unconfirm · so_require_role · so_status_guard(짝 넷 그대로 — 이 파일의 전이는 confirmed→cancelled · draft→cancelled 만)

-- ═══ ① so_hold — 보류(R3 · 오더 전체 · Caleb 「보류는 특정 제품에만 한한 경우는 없어」) ═══
create function public.so_hold(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_n int := 0;  r record;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — only a confirmed order still in IMS can be put on hold — nothing was saved', v_so.so_number, v_so.status;
  end if;
  for r in
    select x.id as line_id, x.qty_ordered, res.id as reserve_id
    from public.so_line x join public.so_reserve res on res.so_line_id = x.id and res.released_at is null and res.kind = 'allocated'
    where x.so_id = p_so_id order by x.line_no
  loop
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || r.line_id::text));
    update public.so_reserve set released_at = now(), released_by = v_staff, updated_by = v_staff where id = r.reserve_id;     -- 풀고 →
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (r.line_id, r.qty_ordered, 'hold', v_staff);   -- 새로 걸기(5-f)
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then
    raise exception 'Order % has no allocated lines to hold (already on hold, or a backorder/preorder order) — nothing was saved', v_so.so_number;
  end if;
  update public.so set updated_by = v_staff where id = p_so_id;
  return jsonb_build_object('so_number', v_so.so_number, 'status', v_so.status, 'lines_held', v_n);
end;
$$;
comment on function public.so_hold(uuid) is '⭐ 보류(②b · R3 · 1-e · 6-d) — definer · sales + manager · confirmed 오더 전체(줄 단위 보류 없음 · Caleb) · 열린 allocated 예약을 전부 풀고(released_at/by · 지우지 않는다 5-f) 줄마다 kind hold 새 줄 · 오더 상태 무접촉 · 가용이 돌아온다 · 할당이 없으면 거부 · 다시 잡기는 so_reallocate';
revoke all on function public.so_hold(uuid) from public, anon;
grant execute on function public.so_hold(uuid) to authenticated;

-- ═══ ② so_reallocate — 보류 풀기(엔진 · 모자란 몫은 R1 대로 나눈다) ═══
create function public.so_reallocate(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_n int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — only a confirmed order can be re-allocated — nothing was saved', v_so.so_number, v_so.status;
  end if;
  update public.so_reserve r set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x where x.id = r.so_line_id and x.so_id = p_so_id and r.released_at is null and r.kind = 'hold';
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'Order % is not on hold — nothing to re-allocate — nothing was saved', v_so.so_number;
  end if;
  return public.so_allocate_run(p_so_id, v_so.location_id, '{}'::uuid[], false, false, true, v_staff) || jsonb_build_object('lines_released', v_n);
end;
$$;
comment on function public.so_reallocate(uuid) is '⭐ 보류 풀기(②b · R3) — definer · sales + manager · confirmed · 열린 hold 예약을 전부 풀고 엔진 so_allocate_run 으로 다시 잡는다 · 모자란 몫은 R1 대로 백오더 형제(여기서 처음 나뉠 수 있다 · created_at ≠ confirmed_at 이라 so_unconfirm 대상이 아니다) · hold 가 없으면 거부 · 미리 보기 없음(풀어야 계산된다)';
revoke all on function public.so_reallocate(uuid) from public, anon;
grant execute on function public.so_reallocate(uuid) to authenticated;

-- ═══ ③ so_cancel — 취소 · 형제 함께(R4 · Caleb 「가가 맞지 않나?」) ═══
--   범위 = 이 오더 + split_from 사슬 아래 열린 자손(cancelled 제외) · IMS 안(draft·confirmed)만 취소 · at_wms 이상은 건드리지 않고 알린다 · p_keep 에 든 형제와 그 아래는 살린다
create function public.so_cancel(p_so_id uuid, p_note text, p_keep uuid[] default '{}'::uuid[], p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_note text;  r record;
  v_plan jsonb := '[]'::jsonb;  v_cancel uuid[] := '{}';  v_warn text[] := '{}';  v_released int := 0;  v_n int;
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
  if not p_commit then
    return jsonb_build_object('so_number', v_so.so_number, 'committed', false, 'note', v_note, 'orders', v_plan, 'warnings', to_jsonb(v_warn));
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
  return jsonb_build_object('so_number', v_so.so_number, 'committed', true, 'note', v_note, 'orders', v_plan, 'cancelled', v_n, 'reserves_released', v_released, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_cancel(uuid, text, uuid[], boolean) is '⭐ 취소(②b · R4 · Caleb 「취소할 때 형제도 함께」) — definer · sales + manager · draft·confirmed(릴리스 전)만 · p_note 필수 → closed_note · closed_reason voided · closed_at · cancelled_by · 잡아 둔 예약 전부 풀기(어느 kind 든) · ⭐ 범위 = 이 오더 + split_from 사슬 아래 열린 자손 전부(같은 note) · p_keep 에 든 형제와 그 아래는 살린다(뺄 목록) · 창고로 간 자손(at_wms 이상)은 건드리지 않고 warnings sibling_in_warehouse · p_commit false = 함께 닫히는 형제 목록만 · 예약 이력 있는 draft 도 여기로(so_delete 가 안내)';
revoke all on function public.so_cancel(uuid, text, uuid[], boolean) from public, anon;
grant execute on function public.so_cancel(uuid, text, uuid[], boolean) to authenticated;

-- ═══ ④ so_change_location — 창고 바꾸기(R7 · 2-h · 릴리스 전 · 미리 보기 필수) ═══
--   할당이 있으면 전부 풀고(created 시각 기록) 새 창고에서 엔진 · 모자란 몫은 백오더 형제 · hold·백오더·프리오더 오더는 창고 칸만(잡을 것이 없다)
--   미리 보기 = 하위 블록에서 실제로 풀고 엔진(commit false)을 돌린 뒤 예외로 되돌린다(식 한 곳)
create function public.so_change_location(p_so_id uuid, p_location_id uuid, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_wh public.ref_warehouse%rowtype;  v_alloc int;  v_res jsonb;  v_n int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — change the warehouse of a confirmed order here (a draft uses so_header_update; a released order belongs to the warehouse) — nothing was saved', v_so.so_number, v_so.status;
  end if;
  select * into v_wh from public.ref_warehouse where id = p_location_id;
  if not found or not v_wh.is_active then
    raise exception 'Warehouse % is inactive or unknown — pick an active warehouse — nothing was saved', coalesce(v_wh.name, '?');
  end if;
  if v_so.location_id = p_location_id then
    raise exception 'Order % is already at % — nothing was saved', v_so.so_number, v_wh.name;
  end if;
  select count(*) into v_alloc from public.so_reserve r join public.so_line x on x.id = r.so_line_id
  where x.so_id = p_so_id and r.released_at is null and r.kind = 'allocated';

  if v_alloc = 0 then                                            -- hold · 백오더 · 프리오더 오더 — 창고 칸만
    if p_commit then
      update public.so set location_id = v_wh.id, location_name = v_wh.name, updated_by = v_staff where id = p_so_id and status = 'confirmed';
      get diagnostics v_n = row_count;
      if v_n <> 1 then raise exception 'Order % was not saved — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;
    end if;
    return jsonb_build_object('so_number', v_so.so_number, 'committed', p_commit, 'from', v_so.location_name, 'to', v_wh.name, 'mode', 'location_only', 'lines', '[]'::jsonb, 'siblings', '[]'::jsonb);
  end if;

  begin                                                          -- 풀고 → 창고 바꾸고 → 엔진 · 미리 보기면 예외로 되돌린다
    update public.so_reserve r set released_at = now(), released_by = v_staff, updated_by = v_staff
    from public.so_line x where x.id = r.so_line_id and x.so_id = p_so_id and r.released_at is null and r.kind = 'allocated';
    update public.so set location_id = v_wh.id, location_name = v_wh.name, updated_by = v_staff where id = p_so_id and status = 'confirmed';
    v_res := public.so_allocate_run(p_so_id, v_wh.id, '{}'::uuid[], false, false, p_commit, v_staff);
    if not p_commit then
      raise exception using errcode = 'P0777', message = v_res::text;
    end if;
  exception when sqlstate 'P0777' then
    v_res := sqlerrm::jsonb;
  end;
  return v_res || jsonb_build_object('from', v_so.location_name, 'to', v_wh.name, 'mode', 'reallocated');
end;
$$;
comment on function public.so_change_location(uuid, uuid, boolean) is '⭐ 창고 바꾸기(②b · R7 · 2-h · 6-e 릴리스 전) — definer · sales + manager · confirmed 만(draft 는 so_header_update) · 활성 창고만(IN_TRANSIT 은 비활성) · 같은 창고 거부 · 할당이 있으면 전부 풀고(이력) 새 창고에서 엔진 so_allocate_run — 잡을 수 있는 만큼 잡고 모자란 몫은 백오더 형제(stock_short) · hold·백오더·프리오더 오더는 창고 칸만(mode location_only) · p_commit false = 미리 보기(하위 블록에서 풀고 엔진을 돌린 뒤 되돌린다 · 식 한 곳) · 가격·손님 값은 그대로(2-h)';
revoke all on function public.so_change_location(uuid, uuid, boolean) from public, anon;
grant execute on function public.so_change_location(uuid, uuid, boolean) to authenticated;

-- ═══ ⑤ so_backorder_proceed — 백오더 진행(R8 · 1-f 뒤쪽) ═══
create function public.so_backorder_proceed(p_so_id uuid, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_res jsonb;  v_n int;
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
    update public.so_reserve r set released_at = now(), released_by = v_staff, updated_by = v_staff
    from public.so_line x where x.id = r.so_line_id and x.so_id = p_so_id and r.released_at is null and r.kind in ('backorder', 'preorder');
    get diagnostics v_n = row_count;
    if v_n = 0 then
      raise exception 'Order % has no backorder or preorder lines to proceed — nothing was saved', v_so.so_number;
    end if;
    v_res := public.so_allocate_run(p_so_id, v_so.location_id, '{}'::uuid[], false, false, p_commit, v_staff) || jsonb_build_object('lines_released', v_n);
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

-- ═══ ⑥ so_divide — 오더 나누기(사람 · 추가 판정 · Caleb 「스탁이 있음에도 나눠서 받기를 원할 경우」) ═══
--   [{line_id, qty}] · qty >= 줄 수량이면 줄째 · 작으면 일부(so_split 이 새 줄 + split_from_line_id) · 전부 떼어 내기 거부(빈 원본 없음) · split_reason manual
--   confirmed: 옮긴 수량의 예약이 같은 kind 로 따라간다 — 줄째면 예약 행이 줄과 함께 간다 · 일부면 원래 예약을 풀고(이력) 원래 줄·형제 줄에 같은 kind 로 다시 건다(엔진 안 거침 · 창고 재고 불변) · draft: 예약 없음 · 형제도 draft
create function public.so_divide(p_so_id uuid, p_moves jsonb, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_new public.so%rowtype;  m record;  l public.so_line%rowtype;  res public.so_reserve%rowtype;
  v_plan jsonb := '[]'::jsonb;  v_moves jsonb := '[]'::jsonb;  v_whole int := 0;  v_lines int;  v_nl public.so_line%rowtype;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status not in ('draft', 'confirmed') then
    raise exception 'Order % is % — only a draft or confirmed order still in IMS can be divided — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if p_moves is null or jsonb_typeof(p_moves) <> 'array' or jsonb_array_length(p_moves) = 0 then
    raise exception 'p_moves must be a non-empty array of {line_id, qty} — nothing was saved';
  end if;
  select count(*) into v_lines from public.so_line where so_id = p_so_id;

  for m in
    select (e->>'line_id')::uuid as line_id, nullif(e->>'qty', '')::numeric as qty from jsonb_array_elements(p_moves) e
  loop
    select * into l from public.so_line where id = m.line_id and so_id = p_so_id;
    if not found then raise exception 'Line % is not on order % — nothing was saved', m.line_id, v_so.so_number; end if;
    if m.qty is null or m.qty <= 0 then raise exception 'Quantity for line % must be positive — nothing was saved', l.line_no; end if;
    if m.qty > l.qty_ordered then raise exception 'Line % has only % — cannot split off % — nothing was saved', l.line_no, l.qty_ordered, m.qty; end if;
    if v_moves @> jsonb_build_array(jsonb_build_object('line_id', l.id)) then raise exception 'Line % is listed twice — nothing was saved', l.line_no; end if;
    select * into res from public.so_reserve where so_line_id = l.id and released_at is null;
    v_moves := v_moves || jsonb_build_object('line_id', l.id, 'qty', m.qty);
    if m.qty = l.qty_ordered then v_whole := v_whole + 1; end if;
    v_plan := v_plan || jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'qty_moved', m.qty, 'whole', m.qty = l.qty_ordered,
                                           'reserve_kind', res.kind, 'reserve_follows', case when res.id is null then 0 else m.qty end);
  end loop;
  if v_whole >= v_lines then
    raise exception 'Cannot split off every line of order % — leave at least one line (or one part of a line) — nothing was saved', v_so.so_number;
  end if;
  if not p_commit then
    return jsonb_build_object('so_number', v_so.so_number, 'committed', false, 'status', v_so.status, 'lines', v_plan);
  end if;

  perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(v_so.so_number, '[a-z]+$', '')));
  for m in select (e->>'line_id')::uuid as line_id from jsonb_array_elements(v_moves) e loop
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || m.line_id::text));
  end loop;
  v_new := public.so_split(p_so_id, 'manual', v_moves, v_so.status, v_staff);

  -- 일부만 간 줄의 예약 — 풀고(이력) 원래 줄·형제 줄에 같은 kind 로(줄째 간 줄은 예약 행이 줄과 함께 갔다)
  if v_so.status = 'confirmed' then
    for v_nl in select * from public.so_line where so_id = v_new.id and split_from_line_id is not null loop
      select * into res from public.so_reserve where so_line_id = v_nl.split_from_line_id and released_at is null;
      if found then
        update public.so_reserve set released_at = now(), released_by = v_staff, updated_by = v_staff where id = res.id;                       -- 풀고 →
        insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
        select x.id, x.qty_ordered, res.kind, res.allocated_by from public.so_line x where x.id = v_nl.split_from_line_id;                        -- 원래 줄 · 남은 수량
        insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (v_nl.id, v_nl.qty_ordered, res.kind, res.allocated_by);   -- 형제 줄 · 옮긴 수량
      end if;
    end loop;
  end if;
  return jsonb_build_object('so_number', v_so.so_number, 'committed', true, 'status', v_so.status, 'lines', v_plan,
                            'sibling', jsonb_build_object('so_id', v_new.id, 'so_number', v_new.so_number, 'status', v_new.status, 'split_reason', 'manual'));
end;
$$;
comment on function public.so_divide(uuid, jsonb, boolean) is '⭐ 오더 나누기(②b · 사람이 누르는 분할 · Caleb 「스탁이 있음에도 나눠서 받기를 원할 경우」 · 「특정 제품만 나중에」는 떼어 낸 쪽을 so_hold) — definer · sales + manager · draft·confirmed(릴리스 전) · p_moves [{line_id, qty}] · qty = 줄 수량이면 줄째 · 작으면 일부(새 줄 + split_from_line_id) · 전부 떼어 내기 거부 · split_reason manual · 형제는 원래와 같은 상태(draft → draft · confirmed → confirmed) · confirmed 면 옮긴 수량의 예약이 같은 kind 로 따라간다(줄째 = 예약 행이 줄과 함께 · 일부 = 풀고 원래·형제 줄에 다시 걸기 · 엔진 안 거침 · 가용 불변) · p_commit false = 미리 보기 · ⚠️ 사람이 나눈 형제가 있으면 so_unconfirm 은 「split again after confirmation」으로 거부';
revoke all on function public.so_divide(uuid, jsonb, boolean) from public, anon;
grant execute on function public.so_divide(uuid, jsonb, boolean) to authenticated;

-- ═══ ⑦ so_detail 재발행 — 마지막 정의 20260923232500:970 · 더한 것: family(so_family_members) · 줄마다 reserve_kind·reserve_qty·available_ea(so_available_many 한 번) · 그 밖 그대로 ═══
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
  v_warn     text[];
  v_av       jsonb := '{}'::jsonb;                    -- 낱개 제품 → 가용(EA) · so_available_many 한 번(줄마다 부르지 않는다 · ②b)
  v_family   jsonb;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  -- 가용 — 이 오더의 낱개 제품 전부를 한 문장으로(창고가 있을 때만) · 형제 목록
  if v_so.location_id is not null then
    select coalesce(jsonb_object_agg(m.stock_pid::text, m.available_ea), '{}'::jsonb) into v_av
    from public.so_available_many((select array_agg(distinct coalesce(p.parent_product_id, p.id)) from public.so_line l join public.product p on p.id = l.product_id where l.so_id = p_so_id), v_so.location_id) m;
  end if;
  select coalesce(jsonb_agg(to_jsonb(f) order by f.so_number), '[]'::jsonb) into v_family from public.so_family_members(p_so_id) f;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('total', public.so_line_total(l), 'no_price', l.unit_price is null, 'free', l.free_reason is not null,
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date),
                                                              'reserve_kind', (select r.kind from public.so_reserve r where r.so_line_id = l.id and r.released_at is null),
                                                              'reserve_qty',  (select r.qty_allocated from public.so_reserve r where r.so_line_id = l.id and r.released_at is null),
                                                              'available_ea', (v_av->>(select coalesce(p.parent_product_id, p.id)::text from public.product p where p.id = l.product_id))::numeric) order by l.line_no), '[]'::jsonb),
         count(*), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), coalesce(sum(public.so_line_total(l)), 0),
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date))
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

  -- 오더 전체 할인(D6) — 제품 줄 합계에 한 번 · round 2(SO-10842 실물) · 운임은 기준에 없다
  v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;

  v_warn := public.so_tier_warnings(v_so);
  if v_lines_n = 0    then v_warn := array_append(v_warn, 'no_lines'); end if;
  if v_no_price > 0   then v_warn := array_append(v_warn, 'lines_without_price'); end if;
  if v_deal_ended > 0 then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'family', v_family,
    'totals', jsonb_build_object('lines', v_lines_n, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt,
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'order_total', v_lines_total - v_od_amt + v_charges_total),
    'warnings', to_jsonb(v_warn));
end;
$$;

comment on function public.so_detail(uuid) is
  '⭐ SO 오더 읽기 한 창구(①b · ②b 재발행) — invoker · stable(RLS select 그대로 · 로그인만). so · customer_name · lines(+ total · no_price · free · deal_ended · reserve_kind·reserve_qty(열린 예약) · available_ea(그 창고 가용 · so_available_many 한 번 — 줄마다 부르지 않는다)) · charges · family(so_family_members — 형제 줄 · 상태 · open_qty) · totals(lines_total · order_discount_amount · lines_after_discount · order_total = lines − discount + charges) · warnings. 화면 셋이 다시 짜지 않는다';

-- ═══ ⑧ so_delete 재발행 — 마지막 정의 20260923191030:948 · 바뀐 줄: create or replace · 거부 문장 「cancel it instead」(예약 이력이 있는 draft · ②a 이견 7) ═══
create or replace function public.so_delete(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_so        public.so%rowtype;
  v_lines     int;
  v_charges   int;
  v_reserves  int;
  v_n         int;
begin
  perform public.ims_require_write('sales', 'deleted');        -- ⭐ 첫 줄
  perform public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'deleted');

  select count(*) into v_reserves from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = p_so_id;
  if v_reserves > 0 then
    raise exception 'Order % has allocation history (it was confirmed before) — cancel it instead (so_cancel) — nothing was deleted', v_so.so_number;
  end if;
  select count(*) into v_lines   from public.so_line   where so_id = p_so_id;
  select count(*) into v_charges from public.so_charge where so_id = p_so_id;

  delete from public.so where id = p_so_id and status = 'draft';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order % was not deleted — it may have been changed by someone else just now — nothing was deleted', v_so.so_number;
  end if;
  return jsonb_build_object('deleted', v_so.so_number, 'lines', v_lines, 'charges', v_charges);
end;
$$;

comment on function public.so_delete(uuid) is '⭐ SO 초안 지우기(①b · ②b 문장 갱신) — definer · 첫 줄 ims_require_write(sales, deleted) · 초안만 · 줄·운임은 cascade(거래 표 규약) · so_reserve 이력이 하나라도 있으면(확정된 적 있는 draft · so_unconfirm 뒤) 거부 「cancel it instead (so_cancel)」 — 이력은 지우지 않는다(5-f) · 번호는 되돌아오지 않는다(시퀀스)';

-- ═══ 검증(~/asung/prompts/so-write-2b-verify.sql) — 확정 → 보류(가용 돌아옴) → 다시 잡기 → 창고 바꾸기 미리 보기·실행 → 백오더 진행(새 글자) → 나누기(confirmed 할당 따라감 · draft) → 되돌리기 거부 → 취소 미리 보기 → 살리고 취소 → 지우기 거부 · 권한 · 문지기 · 시퀀스 되돌리기 ═══
