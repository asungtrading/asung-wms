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
-- unconf-1 — Unconfirm 을 Manager 에게 · 자기 창고 오더만 (2026-10-29 · 판정 883 · 지시서 ~/asung/prompts/unconf-1.md)
--   왜(Caleb 「Unconfirm 을 Manager 에게 열되, 자기 창고 오더만」 · 앞서 「수퍼바이저로 올릴께」 를 거둠): Edmonton Manager 가 Edmonton 오더를 Unconfirm 하지 못했다(역할 manager · 「This needs a supervisor or above」)
--   문(so_unconfirm): ① ims_require_write('sales') 그대로 ② so_require_role('manager') (전에는 'supervisor' · R9) ③ 오더를 읽은 뒤 · 상태 검사 앞에 ims_can_warehouse(v_so.location_id)
--        · ims_can_warehouse: admin · supervisor = 늘 true · warehouse_access 빈 배열 = true(Location 이 빈 manager 는 모든 오더 — Caleb 이 받아들인 대가) · 그 밖 location_id = any(warehouse_access) · location_id null → false(manager 거부 · supervisor 통과)
--        · 보는 창고 = 원래 오더(p_so_id)의 location_id 하나 — 갈린 형제는 보지 않는다(unconf-1 이견 1: 형제는 so_split 이 부모 행을 복사해 같은 창고에서 태어난다(ln_1:520 ~ 528) · 다른 창고가 되는 길은 확정 뒤 so_change_location 이 부모만 옮길 때뿐(so_hold_cancel:182 · 192 · 실측 SO-25166) — 그때 형제까지 보면 판정 883 의 바로 그 경우(옮겨 온 Edmonton 오더)를 막는다)
--   오류 글(화면에 그대로): Order % is in % — you can unconfirm only orders of your locations (ask a supervisor) — nothing was saved
--   재발행 하나(바이트 복사 + 바꾼 줄만):
--     so_unconfirm — 원본 20261006204146_dsc_3b_coupon_credit.sql:470 ~ 572 · prosrc md5 b9b48b92b7445a84abcdb5aa1b254b28(100 줄) · 바꾼 줄 = 486(둘째 문 supervisor → manager) · 490 뒤에 세 줄 더함(창고 검사 if · raise · end if) → 103 줄 · 그 밖 본문 무변
--   무접촉: so_confirm · so_pos_reopen · so_service_confirm · so_cancel · ims_can_warehouse · so_require_role · so_split · so_change_location · 화면(so.html 의 Unconfirm 은 RPC 그대로 · 글자 「(supervisor)」 는 대화 Claude 가 따로)
--     · so_pos_reopen 오류 글 「use so_unconfirm (supervisor)」(svc_1b:967 · 970)는 글자만 낡는다 — 이번에 안 고친다(unconf-1 이견 4)
--   컷오버: 새 표 · 칸 없음(재발행 하나) — 컷오버 날 지우기와 무관
--   적용(Caleb · 테스트 DB = 11-01 부터 메인 · 운영 asung-WMS 에는 올리지 않는다): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261029235800_unconf_1_manager_own_warehouse.sql && supabase migration repair --status applied 20261029235800 --db-url "$(cat ~/.asung-testdb-url)"
--   확인(적용 뒤): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -f supabase/tests/unconf_1_check.sql

-- ── so_unconfirm 재발행 — 원본 dsc_3b:470 ~ 572 바이트 복사 · 바꾼 곳 = 둘째 문(486) · 창고 검사 세 줄(490 뒤) ──
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
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — manager 이상(R9 · 판정 883 · 전에는 supervisor)
  v_staff := public.so_current_staff();

  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_so.location_id) then                             -- ⭐ 셋째 — unconf-1 판정 883: 자기 창고 오더만(supervisor · admin · Location 빈 manager 는 늘 통과 · 오더를 읽은 뒤 · 상태 검사 앞)
    raise exception 'Order % is in % — you can unconfirm only orders of your locations (ask a supervisor) — nothing was saved', v_so.so_number, coalesce(v_so.location_name, '(no location)');
  end if;
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
                            'backorders_reopened', v_reopen, 'coupon_restored', to_jsonb(public.so_coupon_release(array[p_so_id], v_staff)));   -- dsc-3b 판정 321: 가족에 confirmed 이상이 없으면 되살림
end;
$$;

comment on function public.so_unconfirm(uuid) is
  '⭐ 확정 되돌리기(②a · R9 · Caleb 「백오더로 스플릿 되기 이전으로 롤백」) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager · unconf-1 판정 883 · 전에는 supervisor) · 셋째 오더 창고 ims_can_warehouse(location_id)(판정 883: supervisor · admin · Location 빈 manager 는 전부 · 그 밖 manager 는 체크한 창고의 오더만 · 원래 오더의 창고 하나만 본다 — 형제는 같은 창고에서 태어나고 부모가 옮겨진 때만 다르다). 조건: 원래가 confirmed(IMS 안 · 창고로 갔으면 먼저 WMS 롤백) · 형제는 그 확정 때 태어난 것만(created_at = 원래 confirmed_at) · 손대지 않았다(형제·줄·예약 updated_at = 형제 created_at · 예약 전부 열림 · 운임 0 · 자식 0 — 「같은 시각」 ⬜7) · 확정 뒤 다시 나눈 자식이 있으면 거부. 하는 일: 예약 전부 풀기(원래·형제 · released_at/by) · 형제 줄 도로 합치기(통째 = 행 이동 · 일부 = split_from_line_id 줄에 수량 더함 · 형제 줄 행은 이력) · 형제 cancelled·merged·merged_into_id·closed_note · 원래 draft · confirmed_at/by 비움 · unconfirmed_at/by. 글자는 다시 쓰지 않는다(다음 확정은 다음 글자) · 줄 가격·할인은 그대로(다시 매기기는 so_reprice)';
