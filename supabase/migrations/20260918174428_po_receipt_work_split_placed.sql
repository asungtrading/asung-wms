-- ─────────────────────────────────────────────────────────────
-- po_receipt_work_split 다시 냄 — 쪼갠 줄도 **놓인 것**으로 (Asung-IMS · 2026-09-18)
--
-- 왜: 이 화면(receiving.html · 사무 화면)은 빈을 고르는 순간 놓인 것이다(Caleb 2026-09-18 · 「자리를 정했다」와 「갖다 놨다」가 갈릴 이유가 없다).
--     그런데 20260918163552 의 split 은 새 줄을 putaway_done = false 로 넣었다 ⇒ 쪼개서 빈 A 로 4 를 보내면 빈은 있는데 안 놓인 상태.
--     [실물 2026-09-18] 12 를 4·8 로 쪼개 각각 빈을 줬는데 PLACED 0. putaway(p_done 기본 true)로 들어온 줄과 길이 달랐다(20260918173042 이견 1).
--     화면이 split 뒤 putaway 를 이어 부르는 대안은 버렸다 — 왕복 둘 · 중간에 끊기면 어중간한 줄.
--
-- 바꾼 곳(원본 20260918163552:235-307 과 diff 로 대조 · 그 밖은 글자 그대로):
--   ① 새 줄 insert  putaway_done false → true (putaway_by = v_staff · putaway_at = v_now 는 원본부터 찍고 있었다 — putaway 와 같은 모양)
--   ② 병합 가지     putaway_done = true 를 더한다 · putaway_by/at 은 원본이 이미 덮고 있었다(po_receipt_work_putaway 의 v_dup 가지와 같다) — 그대로
--   ③ comment       한 문장 더함
--   ④ create → create or replace (인자 무변 · §5 함수 시그니처 · grant 유지 · drop 없음)
--   ⑤ 기존 데이터   bin_id is not null and putaway_done = false 인 줄을 true 로(⬜3) — 이 화면의 뜻으로는 있을 수 없는 상태 · 행 수는 notice 로 남긴다
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- ═══ po_receipt_work_split — 다시 냄 (⭐ 합 불변 · 새 줄은 빈을 함께 받는다 · 같은 빈 줄이 있으면 합친다 · ⭐ 새 줄·합쳐진 줄은 놓인 것) ═══
-- POST /rest/v1/rpc/po_receipt_work_split  {"p_work_id":…,"p_qty_ea":400,"p_bin_id":"<ref_bin.id>"}
-- → { receipt_number, po_line_id, from:{work_id, qty_before, qty_after}, to:{work_id, bin, qty_before, qty_after, merged}, line_total }
create or replace function public.po_receipt_work_split(
  p_work_id uuid,
  p_qty_ea  numeric,                                -- 떼어 낼 수량(낱개) · 0 < p_qty_ea < 원래 수량
  p_bin_id  uuid                                    -- ⭐ 새 줄의 빈(필수 · 그 입고의 창고 · 활성)
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_w      public.po_receipt_work%rowtype;
  v_r      public.po_receipt%rowtype;
  v_b      public.ref_bin%rowtype;
  v_to     public.po_receipt_work%rowtype;
  v_to_id  uuid;
  v_to_before numeric := 0;
  v_merged boolean := false;
  v_n      int;
  v_total  numeric;
  v_now    timestamptz := now();
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ②
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was saved', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — rows can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  if p_qty_ea is null or p_qty_ea <= 0 then raise exception 'p_qty_ea must be above 0 — nothing was saved'; end if;
  if p_qty_ea >= v_w.qty_ea then
    raise exception 'Cannot split % of % — the row would be left with nothing; use putaway to move the whole row — nothing was saved', p_qty_ea, v_w.qty_ea;
  end if;
  v_b := public.po_receipt_bin_check(v_w.receipt_id, p_bin_id);                -- 창고·활성(도우미 · 문장은 거기)
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || v_w.po_line_id::text));   -- 이견 12 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지)
  if v_w.bin_id = p_bin_id then
    raise exception 'The row is already in bin % — pick a different bin to split into — nothing was saved', v_b.name;
  end if;

  -- 원래 줄에서 뺀다
  update public.po_receipt_work set qty_ea = qty_ea - p_qty_ea where id = p_work_id and qty_ea = v_w.qty_ea;   -- ⭐ 읽은 수량 그대로일 때만(남이 사이에 바꿨으면 0행)
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;

  -- 같은 라인·같은 빈 줄이 있으면 합친다(유니크가 막는 자리를 병합으로) · 없으면 새 줄
  select * into v_to from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and w.po_line_id = v_w.po_line_id and w.bin_id = p_bin_id;
  if found then
    v_to_id := v_to.id; v_to_before := v_to.qty_ea; v_merged := true;
    update public.po_receipt_work set qty_ea = qty_ea + p_qty_ea, putaway_done = true, putaway_by = v_staff, putaway_at = v_now where id = v_to.id;   -- ⬜1 합쳐진 줄도 놓인 것 · by/at 은 putaway 병합 가지와 같은 모양(덮는다)
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_to.id, v_r.receipt_number; end if;
  else
    insert into public.po_receipt_work (receipt_id, po_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at, putaway_by, putaway_at)
    values (v_w.receipt_id, v_w.po_line_id, p_qty_ea, p_bin_id, true, v_w.count_method, v_w.counted_by, v_w.counted_at, v_staff, v_now)    -- ⭐ 빈을 고르는 순간 놓인 것(true · Caleb 2026-09-18) · 수량 축은 원래 줄의 것을 물려받는다(센 사람은 안 바뀐다)
    returning id into v_to_id;
  end if;

  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and w.po_line_id = v_w.po_line_id;
  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', v_w.po_line_id,
    'from', jsonb_build_object('work_id', v_w.id, 'bin_id', v_w.bin_id, 'qty_before', v_w.qty_ea, 'qty_after', v_w.qty_ea - p_qty_ea),
    'to',   jsonb_build_object('work_id', v_to_id, 'bin_id', p_bin_id, 'bin', v_b.name, 'zone', v_b.zone, 'qty_before', v_to_before, 'qty_after', v_to_before + p_qty_ea, 'merged', v_merged),
    'line_total', v_total);                                                    -- ⭐ 쪼개기 전과 같아야 한다
end;
$$;
comment on function public.po_receipt_work_split(uuid, numeric, uuid) is '⑤ 풋어웨이 — 줄을 쪼갠다(리시빙 2-a). 원래 줄에서 p_qty_ea 를 빼고 ⭐ 빈을 함께 받은 새 줄을 만든다(합 불변 · 한 함수) · 같은 라인·같은 빈 줄이 있으면 새 줄 대신 거기에 합친다(unique 를 예외가 아니라 병합으로). 원래 수량 이상은 거부(0 이 되면 qty_ea>0 CHECK) · 같은 빈으로는 거부 · 빈은 po_receipt_bin_check(창고·활성). 원래 줄의 수량은 읽은 값 그대로일 때만 뺀다(남이 사이에 바꿨으면 0행 거부). draft 만 · putaway_by/at 서버가 찍는다. ⭐ [2026-09-18 다시 냄] 새 줄과 합쳐진 줄은 putaway_done = true — 이 화면은 빈을 고르는 순간 놓인 것(po_receipt_work_putaway 의 p_done 기본값과 같은 길). 정본 po-module §11-i';

-- ═══ ⑤ 기존 데이터 — 빈은 있는데 안 놓인 줄을 놓인 것으로 (한 번 · 행 수를 notice 로) ═══
-- ⚠️ putaway_by/at 은 건드리지 않는다 — split 이 원본부터 찍었으므로 이미 있다(없는 줄이 있으면 그대로 null · 아래 검증 ⑥-b 가 센다).
do $$
declare v_n int;
begin
  update public.po_receipt_work set putaway_done = true where bin_id is not null and putaway_done = false;
  get diagnostics v_n = row_count;
  raise notice 'po_receipt_work: % row(s) with a bin marked placed (2026-09-18 split_placed)', v_n;
end;
$$;
