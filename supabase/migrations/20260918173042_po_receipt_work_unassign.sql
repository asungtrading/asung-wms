-- ─────────────────────────────────────────────────────────────
-- po_receipt_work_unassign — 풋어웨이 되돌리기 (Asung-IMS · 2026-09-18 · 리시빙 2-a 보강 · 함수 하나)
--
-- 왜: 화면의 「↩ Take it back out of the bin」이 putaway_done 만 끄고 빈을 남겼다.
--     [Caleb] 「되돌린다면서 빈이 남아 있으면 되돌린 게 아니다」 ⇒ 되돌리기 = 빈을 지우고 그 줄을 다시 **미배정**으로.
--     함께 정해진 것: 이 화면(사무 화면)은 빈을 고르는 순간 placed 다 — 중간 상태를 두지 않는다. putaway_done 칸은 나중 WMS 창고 화면 몫으로 그대로.
--
-- ⭐⭐ 병합 — 「빈 없는 줄은 라인당 하나」(20260918163552 ⬜1). 되돌린 줄이 빈 없는 줄이 되는데 그 라인에 이미 빈 없는 줄이 있으면
--     둘이 된다 ⇒ **거기에 수량을 더하고 되돌린 줄을 지운다**. 없으면 그 줄의 빈만 지운다.
--     쪼개기·풋어웨이가 같은 빈을 만났을 때와 같은 처방(2-a 이견 2 · po_receipt_work_putaway 의 v_dup 가지와 같은 결).
--     합은 변하지 않는다 — 함수가 잠금 뒤 라인 총량을 재고, 쓰기 뒤 다시 재어 다르면 전부 되돌린다.
--
-- 규약(20260918163552 그대로): plpgsql · volatile · security invoker · 첫머리 ims_require_write('receiving','saved') · update/delete 뒤 row_count ·
--   판정 축 confirmed_at + status='draft'(2-a 이견 9 · po_receipt_work_delete 와 같은 검사) · 라인 잠금 키 'po_receipt_work:<receipt_id>:<po_line_id>'(2-a 이견 12 · 같은 키) ·
--   revoke public/anon + grant authenticated. 새 함수 ⇒ create(drop 없음). 이름 충돌 없음(2026-09-18 grep).
--
-- ⬜1 이미 빈이 없는 줄 → 거부하지 않고 action 'unchanged' 로 조용히 성공(멱등). 화면이 그 버튼을 안 그리므로 사람이 부를 일이 없고,
--    남이 먼저 되돌린 뒤 늦게 누른 화면이 받는 것은 오류가 아니라 「이미 그렇다」다(화면은 detail 을 되읽는다). 0행 update 를 성공으로 보는 것과는 다르다 — 쓰기를 하지 않은 것.
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- POST /rest/v1/rpc/po_receipt_work_unassign  {"p_work_id":"<po_receipt_work.id>"}
-- → { receipt_id, receipt_number, po_line_id, work_id(살아남은 미배정 줄), removed_work_id(합쳐져 지워진 줄 · 아니면 null), merged_into(합쳤으면 그 줄 id · 아니면 null),
--     qty_moved(되돌린 수량), qty_after(미배정 줄의 수량), bin_before:{bin_id, bin, zone}, line_total(검산 · 안 변한다), action:'merged'|'unassigned'|'unchanged' }
create function public.po_receipt_work_unassign(p_work_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_w       public.po_receipt_work%rowtype;
  v_r       public.po_receipt%rowtype;
  v_b       public.ref_bin%rowtype;
  v_free    public.po_receipt_work%rowtype;    -- 그 라인의 빈 없는 줄(있으면)
  v_free_n  int;
  v_before  numeric;
  v_after   numeric;
  v_n       int;
  v_out_id  uuid;
  v_removed uuid;
  v_merged  uuid;
  v_qty     numeric;
  v_action  text;
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ②
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was saved', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.confirmed_at is not null or v_r.status <> 'draft' then                    -- 축은 confirmed_at · status 도 함께(cancelled 도 못 고친다) — work_delete 와 같은 검사
    raise exception 'Receipt % is % — rows can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || v_w.po_line_id::text));   -- 2-a 이견 12 와 같은 키 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지)
  select coalesce(sum(w.qty_ea), 0) into v_before from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and w.po_line_id = v_w.po_line_id;

  -- ⬜1 이미 빈이 없다 — 쓸 것이 없다(멱등)
  if v_w.bin_id is null then
    return jsonb_build_object(
      'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', v_w.po_line_id,
      'work_id', v_w.id, 'removed_work_id', null, 'merged_into', null,
      'qty_moved', 0, 'qty_after', v_w.qty_ea, 'bin_before', null, 'line_total', v_before, 'action', 'unchanged');
  end if;
  select * into v_b from public.ref_bin where id = v_w.bin_id;                     -- 반환용 이름(없어도 진행 — 되돌리는 데 빈 표는 필요 없다)

  -- 그 라인의 빈 없는 줄 — 둘 이상이면 불변식이 깨져 있다(work_save 와 같은 처방 · 자동으로 고치지 않는다)
  select count(*) into v_free_n from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and w.po_line_id = v_w.po_line_id and w.bin_id is null;
  if v_free_n > 1 then
    raise exception 'Line of receipt % has % unassigned rows — this should not happen; fix the rows first — nothing was saved', v_r.receipt_number, v_free_n;
  end if;
  select * into v_free from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and w.po_line_id = v_w.po_line_id and w.bin_id is null;

  if v_free.id is not null then
    -- ⭐ 병합 — 빈 없는 줄에 더하고 이 줄을 지운다(putaway 의 v_dup 가지와 같은 결 · 수량 축 counted_* 은 안 건드린다)
    update public.po_receipt_work set qty_ea = qty_ea + v_w.qty_ea where id = v_free.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_free.id, v_r.receipt_number; end if;
    delete from public.po_receipt_work where id = p_work_id and qty_ea = v_w.qty_ea;                  -- 읽은 수량 그대로일 때만 지운다
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := v_free.id; v_removed := v_w.id; v_merged := v_free.id; v_qty := v_free.qty_ea + v_w.qty_ea; v_action := 'merged';
  else
    -- 빈 없는 줄이 없다 — 이 줄이 그 줄이 된다(빈·놓았나·넣은 사람 전부 되돌린다 · putaway_bin_ck 와 함께)
    update public.po_receipt_work
       set bin_id = null, putaway_done = false, putaway_by = null, putaway_at = null
     where id = p_work_id and bin_id = v_w.bin_id;                                                     -- 읽은 빈 그대로일 때만(남이 사이에 옮겼으면 0행)
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := v_w.id; v_removed := null; v_merged := null; v_qty := v_w.qty_ea; v_action := 'unassigned';
  end if;

  -- ⭐ 합 불변 — 함수가 보장한다(다르면 전부 되돌린다)
  select coalesce(sum(w.qty_ea), 0) into v_after from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and w.po_line_id = v_w.po_line_id;
  if v_after <> v_before then
    raise exception 'Line total of receipt % changed from % to % while taking the row out of its bin — nothing was saved', v_r.receipt_number, v_before, v_after;
  end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', v_w.po_line_id,
    'work_id', v_out_id, 'removed_work_id', v_removed, 'merged_into', v_merged,
    'qty_moved', v_w.qty_ea, 'qty_after', v_qty,
    'bin_before', jsonb_build_object('bin_id', v_w.bin_id, 'bin', v_b.name, 'zone', v_b.zone),
    'line_total', v_after, 'action', v_action);
end;
$$;
comment on function public.po_receipt_work_unassign(uuid) is '⑤ 풋어웨이 되돌리기(리시빙 2-a 보강 · 2026-09-18) — 줄의 bin_id·putaway_done·putaway_by/at 을 되돌려 다시 미배정으로. ⭐ 그 라인에 이미 빈 없는 줄이 있으면 거기에 수량을 더하고 이 줄을 지운다(「빈 없는 줄은 라인당 하나」 · 쪼개기·풋어웨이의 같은-빈 병합과 같은 처방) · 없으면 빈만 지운다. 합 불변을 함수가 잰다(다르면 전부 되돌림). 이미 빈이 없으면 action unchanged(멱등 · 쓰기 없음). 판정 축 confirmed_at + draft(work_delete 와 같다) · 라인 잠금 키는 2-a 와 같다. 정본 po-module §11-i';
revoke all on function public.po_receipt_work_unassign(uuid) from public, anon;
grant execute on function public.po_receipt_work_unassign(uuid) to authenticated;

-- 화면(receiving.html · 대화 Claude)이 부르는 모양: sb.rpc("po_receipt_work_unassign", { p_work_id })  → data.action · merged_into · line_total(전과 같아야) · 그 뒤 detail 되읽기
