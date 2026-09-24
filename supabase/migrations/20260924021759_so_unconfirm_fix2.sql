-- SO 쓰기 ②a⁗ — so_unconfirm 재발행: 「손대지 않았다」 검사는 열린 예약만 본다 (2026-09-24 UTC · 토론토 2026-09-23 밤)
-- 결함(Caleb 실측 2026-09-23 · ②a 검증 7 두 번째 되돌리기): 「Split order SO-25000c was changed after the split」 — c 는 아무도 안 고쳤다
--   확인(코드): 검사가 형제 줄의 예약 전부에 (r.released_at is not null or …) 를 물었다 · 첫 되돌리기에서 C 줄(AAL40340)이 a → 원래로 줄째 돌아오며 a 시절 예약(풀림)을 달고 왔고,
--   다시 확정에서 그 줄이 통째로 c 로 옮겨 가자 옛 풀림 이력에 걸렸다 ⇒ 한 번 되돌린 오더는 두 번째 되돌리기가 늘 거부됐다 — 대화 Claude 의 짐작이 맞다
-- 판정(Caleb): 열린 예약(released_at is null)만 본다 · 풀린 이력은 무시 · 그 밖의 시각 조건(형제·줄·열린 예약의 updated_at = 형제 created_at · 운임 0 · 자식 0)은 그대로
-- ⚠️ 시험의 함정(정본 §14 사실로): 「같은 시각」 판정은 나누기와 고치기가 다른 트랜잭션일 때만 뜻이 있다 — 한 트랜잭션 안에서는 now() 가 같아 「손댐」을 못 알아챈다 ·
--    검증은 형제를 고칠 때 updated_at 을 명시로 뒤로 적는다(session_replication_role = replica 로 ims_touch 를 비껴서) · 한 창구 안에서 나누고 고치는 길이 생기면 이 판정이 무너진다
-- 바탕: 20260924021413_so_unconfirm_fix.sql(마지막 정의) · 바뀐 줄 하나(42행 예약 검사) · 그 밖 그대로
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 검증 ~/asung/prompts/so-write-2a-verify.sql(덮어씀)

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

  -- 형제 검사(자기 행만 보는 것이 아니라 여기서 다른 행을 본다 — RPC 의 일 · 6-g′) · ⭐ 열린 자식만(cancelled = 앞선 되돌리기로 merged 된 것·취소된 것은 무시 · 2026-09-24 결함 고침)
  for s in select * from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' order by x.so_number loop
    if s.created_at is distinct from v_so.confirmed_at then
      raise exception 'Order % was split again after confirmation (%) — unconfirm only undoes the split made at confirmation — nothing was saved', v_so.so_number, s.so_number;
    end if;
    if s.status <> 'confirmed' then
      raise exception 'Split order % is % — it must still be confirmed and in IMS to merge it back — nothing was saved', s.so_number, s.status;
    end if;
    if s.updated_at is distinct from s.created_at
       or exists (select 1 from public.so_line x where x.so_id = s.id and x.updated_at is distinct from s.created_at)
       or exists (select 1 from public.so_reserve r join public.so_line x on x.id = r.so_line_id where x.so_id = s.id and r.released_at is null and r.updated_at is distinct from s.created_at)   -- 열린 예약만 · 풀린 이력은 무시(2026-09-24 결함 고침 — 돌아온 줄이 옛 풀림을 달고 온다)
       or exists (select 1 from public.so_charge ch where ch.so_id = s.id)
       or exists (select 1 from public.so y where y.split_from_id = s.id) then
      raise exception 'Split order % was changed after the split — unconfirm is only possible while the split orders are untouched — nothing was saved', s.so_number;
    end if;
  end loop;

  -- 예약 전부 풀기 — 원래(allocated · hold · backorder · preorder) + 형제(backorder · preorder) · 지우지 않는다(5-f)
  update public.so_reserve r set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x
  where x.id = r.so_line_id and r.released_at is null
    and (x.so_id = p_so_id or x.so_id in (select id from public.so where split_from_id = p_so_id and status <> 'cancelled'));
  get diagnostics v_released = row_count;

  -- 형제 줄 도로 합치기 · 형제 닫기
  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_so_id;
  for s in select * from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' order by x.so_number loop
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
                            'lines_moved_back', v_moved, 'lines_added_back', v_added, 'reserves_released', v_released);
end;
$$;

