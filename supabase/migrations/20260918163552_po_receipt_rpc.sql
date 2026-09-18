-- ─────────────────────────────────────────────────────────────
-- IMS 리시빙 2-a 차수 — 확정 전까지의 RPC (Asung-IMS · 2026-09-18)
--   po_receipt_create           입고를 연다(PO 당 draft 하나 · confirmed PO 만 · 창고 결정 · created_by 서버 유도)
--   po_receipt_work_save        검수 — 한 라인의 센 수량(없으면 만들고 있으면 고친다 · ⭐ 빈 없는 줄은 「미배정 나머지」 하나)
--   po_receipt_work_split       풋어웨이 — 줄을 쪼갠다(합 불변 · ⭐ 새 줄은 빈을 함께 받는다 · 같은 빈 줄이 있으면 거기 합친다)
--   po_receipt_work_putaway     풋어웨이 — 줄에 빈을 정한다/놓았다(그 입고의 창고 빈 · 활성만)
--   po_receipt_work_putaway_all 풋어웨이 — 한 빈의 줄 전부 놓았다/해제(WMS Place all · 이견 8)
--   po_receipt_work_delete      줄 삭제(draft 만)
--   po_receipt_delete           묶음 삭제(confirmed_at 이 null 일 때만 · 작업 줄 cascade)
--   po_receipt_detail           ⭐ 계산의 정본 — PO 라인 전부 × (ordered · invoiced · received_before · remaining · counted · allocated · placed) + work[]
--   po_receipt_list             뷰(security_invoker) — 목록
--   po_receipt_bin_check        도우미 — 빈이 그 입고의 창고 것이고 활성인가(셋이 같이 쓴다 · 규칙 한 곳)
--
-- ⚠️ 확정·자동 분할·차이 큐는 2-b 다. 이 차수가 끝나면 「열고 · 세고 · 자리를 정하는 것」까지 — 장부(po_receipt_line · 원장)에는 아무것도 안 남는다.
-- 앞 차수: 20260918161537(표 셋 · 커밋 f288ee8) · 20260918010000(ims_require_write) · 20260918133858(ims_touch). 전부 무접촉.
-- 본보기: po_invoice_line_update(20260918003000) · po_charge_alloc_update(20260918013000) · po_create(20260918000000 · staff 서버 유도) — 거부 문장 · 0행 검사 · 반환 모양을 그대로 따른다.
-- 정본: docs/design/po-module.md §5 권한 규약 ②(첫머리 ims_require_write · update/delete 뒤 row_count) · §11-b(막는 것은 저장 전에 RPC 가) · §11-i(입고) · §13-d(쓰기 RPC 관례)
-- 지시서: ~/asung/prompts/ims-receiving-2a.md · 검토 이견 1~12 · ⬜1~9(회신)
--
-- ⭐⭐ ⬜1 쪼개기와 「빈 없는 줄은 라인당 하나」의 충돌 — 이렇게 푼다
--   빈 없는 줄 = 그 라인의 **미배정 나머지**다(센 수량 − 빈이 붙은 줄들의 합). 라인당 하나 · 0 이면 없다.
--   쪼개기(po_receipt_work_split)는 **새 줄에 빈을 함께 받는다**(p_bin_id 필수) — 실무가 「400 은 여기」라 빈 없이 쪼갤 이유가 없고, 빈 없는 줄이 둘 생기는 길이 막힌다.
--   같은 라인에 그 빈 줄이 이미 있으면 새 줄을 만들지 않고 **거기에 합친다**(unique (receipt_id, po_line_id, bin_id) 가 막는 자리를 예외가 아니라 병합으로) — 합은 그대로다.
--   세는 함수(po_receipt_work_save)는 빈 없는 줄만 만들고 고친다 — 라인의 센 수량을 받아 「나머지 = 센 수량 − 배정 합」을 그 줄에 쓴다(⬜2).
--   ⇒ 불변식 셋을 함수가 지킨다: ① 라인당 빈 없는 줄 ≤ 1 ② 같은 빈 줄 ≤ 1(유니크가 받친다) ③ 센 수량 = 줄들의 합(쪼개기·병합은 합을 안 바꾼다).
--
-- ⭐ ⬜2 이미 쪼개진 라인에 work_save — 「센 수량」은 라인의 총량이다. 배정 합(A) 을 넘는 만큼이 빈 없는 줄이 된다.
--   p_qty_ea > A → 빈 없는 줄 = p_qty_ea − A(만들거나 고친다) · p_qty_ea = A → 빈 없는 줄을 지운다(전부 배정됨) · p_qty_ea < A → **거부**(배정된 것보다 적게 세었다 — 빈 줄을 먼저 줄여라 · 두 곳에 적히면 어긋나는 §11-i 와 같은 이유로 자동으로 빈 줄을 깎지 않는다).
-- ⭐ ⬜3 PO 는 confirmed 만 연다 — draft(공급처에 안 갔다) · closed(입고 종료 — 남은 수량은 갈라진 문서로 갔다 · §11-c) · cancelled(안 온다) 전부 거부 · 문장에 상태를 담는다.
-- ⭐ ⬜4 취소(cancelled)는 이 차수에 없다 — 확정 전 「그만둔다」는 초안 삭제와 뜻이 같다. 확정 뒤 되돌림은 2-b/void 차수에서 po_doc_cancel 'receipt' 가지로.
-- ⭐ ⬜5 received_before 를 낸다 — 기준은 「PO 확정 수량 − 이전 확정 입고 합 = remaining」이다(둘째 배가 왔을 때 세는 사람이 보는 숫자). 없으면 화면이 po_receipt_line 을 직접 읽어 계산하게 된다(금지).
-- ⭐ ⬜6 목록은 뷰(po_list · po_invoice_list · po_charge_list · po_payment_list 와 같은 결 · security_invoker · PostgREST .range/.ilike) · 상세는 RPC.
-- ⭐ ⬜7 작업 줄을 미리 만들지 않는다 — qty_ea > 0 CHECK 가 「센 것만 줄」을 뜻한다. 안 센 라인은 po_receipt_detail.lines[] 가 PO 라인 전부를 내므로 화면이 그것으로 그린다(WMS 「전 라인 표시」 관행은 화면에서 그대로 · 데이터는 흔적만 남긴다 — WMS 의 「Empty receipt」 판정이 「작업 줄 0」으로 단순해진다).
--
-- ⚠️ 관례 — plpgsql · volatile · security invoker · set search_path · 첫머리 perform ims_require_write('receiving', …) · update/delete 뒤 row_count 또는 returning + if not found · 0행 문장 「… was not saved|deleted — it may have been removed or changed by someone else just now — nothing was …」 · array_append · revoke public/anon + grant authenticated
-- ⚠️⚠️ 사람 이름 서브쿼리에 **별칭**을 붙인다 — ims_staff 에 updated_by 가 생긴 뒤 `select name from ims_staff where id = updated_by` 는 ims_staff 자기 칸과 비교해 에러 없이 null 을 낸다(2026-09-18 두 번). 여기서는 전부 `s.id = <바깥>.updated_by` 꼴.
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ ⓪ 도우미 — 빈이 그 입고의 창고 것이고 활성인가 (split · putaway · putaway_all 이 같이 쓴다) ═══
create function public.po_receipt_bin_check(p_receipt_id uuid, p_bin_id uuid) returns public.ref_bin
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_r   public.po_receipt%rowtype;
  v_b   public.ref_bin%rowtype;
  v_wh  text;
begin
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if p_bin_id is null then raise exception 'A bin is required — nothing was saved'; end if;
  select * into v_b from public.ref_bin where id = p_bin_id;
  if not found then raise exception 'Bin % not found — nothing was saved', p_bin_id; end if;
  if v_b.warehouse_id <> v_r.warehouse_id then
    select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
    raise exception 'Bin % is not in this receipt''s warehouse (%) — pick a bin in that warehouse — nothing was saved', v_b.name, v_wh;
  end if;
  if not v_b.is_active then
    raise exception 'Bin % is inactive — pick an active bin — nothing was saved', v_b.name;
  end if;
  return v_b;
end;
$$;
comment on function public.po_receipt_bin_check(uuid, uuid) is '리시빙 도우미 — 빈이 그 입고(po_receipt.warehouse_id)의 창고 것이고 ref_bin.is_active 인가(§10-j 3-c). 통과하면 ref_bin 행을 돌려준다 · 아니면 읽을 문장으로 거부. 표의 CHECK 로는 못 한다(다른 표) — RPC 가 저장 전에(§5). 2026-09-18';
revoke all on function public.po_receipt_bin_check(uuid, uuid) from public, anon;
grant execute on function public.po_receipt_bin_check(uuid, uuid) to authenticated;

-- ═══ ① po_receipt_create — 입고를 연다 ═══
-- POST /rest/v1/rpc/po_receipt_create  {"p_po_id":"<po.id>"}   (p_received_on · p_warehouse_id 선택)
-- → { id, receipt_number, status:'draft', po_id, po_number, warehouse_id, warehouse_name, received_on, created_by, warnings[] }
create function public.po_receipt_create(
  p_po_id        uuid,
  p_received_on  date default current_date,
  p_warehouse_id uuid default null                  -- po.ship_to_warehouse_id 가 null 일 때만 쓴다
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_po     public.po%rowtype;
  v_open   text;
  v_wh     uuid;
  v_whn    text;
  v_r      public.po_receipt%rowtype;
  v_warn   text[] := '{}';
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ②

  -- 만든 사람 — 서버 유도(po_create 선례 · 화면이 주지 않는다)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_po from public.po where id = p_po_id;
  if not found then raise exception 'PO % not found — nothing was saved', p_po_id; end if;
  -- ⬜3 confirmed 만 — draft(공급처에 안 갔다) · closed(입고 종료 · 남은 수량은 갈라진 문서로) · cancelled(안 온다)
  if v_po.status <> 'confirmed' then
    raise exception 'PO % is % — receiving can start only on a confirmed order% — nothing was saved',
      v_po.po_number, v_po.status,
      case v_po.status when 'closed' then ' (receiving is finished on this document; the remainder, if any, moved to the split document)'
                       when 'draft'  then ' (confirm it first)'
                       else '' end;
  end if;
  -- ⭐⭐ PO 당 draft 하나 — 부분 유니크 대신 여기서(규칙 29) · 기존 번호를 문장에
  perform pg_advisory_xact_lock(hashtext('po_receipt:' || p_po_id::text));           -- 이견 12 — 둘이 동시에 열면 뒤 것이 앞 것을 본다(권한 불필요 · 트랜잭션 끝에 풀림)
  select r.receipt_number into v_open from public.po_receipt r where r.po_id = p_po_id and r.status = 'draft' order by r.created_at limit 1;
  if v_open is not null then
    raise exception 'PO % already has an open receipt (%) — continue that one or delete it first — nothing was saved', v_po.po_number, v_open;
  end if;
  -- 창고 — PO 의 배송지 · 없으면 인자 · 그것도 없으면 거부(빈은 창고의 것 · ims_last_bin 의 축)
  v_wh := coalesce(v_po.ship_to_warehouse_id, p_warehouse_id);
  if v_wh is null then
    raise exception 'PO % has no ship-to warehouse — pass p_warehouse_id — nothing was saved', v_po.po_number;
  end if;
  if v_po.ship_to_warehouse_id is null then v_warn := array_append(v_warn, 'warehouse_from_parameter'); end if;
  select w.name into v_whn from public.ref_warehouse w where w.id = v_wh and w.is_active;
  if v_whn is null then raise exception 'Warehouse % not found or inactive — nothing was saved', v_wh; end if;
  if p_received_on is not null and p_received_on > current_date then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  insert into public.po_receipt (po_id, warehouse_id, received_on, status, created_by)
  values (p_po_id, v_wh, coalesce(p_received_on, current_date), 'draft', v_staff)
  returning * into v_r;

  return jsonb_build_object(
    'id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status,
    'po_id', v_po.id, 'po_number', v_po.po_number,
    'warehouse_id', v_wh, 'warehouse_name', v_whn, 'received_on', v_r.received_on,
    'created_by', v_staff, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_receipt_create(uuid, date, uuid) is '⑤ 입고를 연다(리시빙 2-a · 2026-09-18). 거부: 권한(ims_require_write receiving) · PO 없음 · PO 가 confirmed 아님(draft·closed·cancelled — 상태를 문장에) · ⭐ 그 PO 에 draft 입고가 이미 있음(번호를 문장에 · 부분 유니크 대신 여기서 · 규칙 29) · 창고를 못 정함. 창고 = po.ship_to_warehouse_id → p_warehouse_id. created_by = auth.uid() → ims_staff.id 서버 유도. 번호는 기본값 시퀀스(RCV-). 정본 po-module §11-i';

-- ═══ ② po_receipt_work_save — 검수: 한 라인의 센 수량 (⭐ 빈 없는 줄 = 미배정 나머지 · 라인당 하나) ═══
-- POST /rest/v1/rpc/po_receipt_work_save  {"p_receipt_id":…,"p_po_line_id":…,"p_qty_ea":12,"p_count_method":"scanned"}
-- → { receipt_number, po_line_id, line_no, sku, counted, allocated, unallocated, work_id(빈 없는 줄 · 없으면 null), action:'inserted'|'updated'|'deleted'|'unchanged', counted_by, counted_at }
create function public.po_receipt_work_save(
  p_receipt_id   uuid,
  p_po_line_id   uuid,
  p_qty_ea       numeric,                           -- ⭐ 그 라인의 센 수량(총량 · 낱개) · 0 = 센 것 없음
  p_count_method text default null                  -- 'scanned' | 'manual' | null
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_r      public.po_receipt%rowtype;
  v_pl     public.po_line%rowtype;
  v_sku    text;
  v_alloc  numeric;
  v_free   public.po_receipt_work%rowtype;    -- 빈 없는 줄(있으면)
  v_free_n int;
  v_rest   numeric;
  v_n      int;
  v_action text;
  v_id     uuid;
  v_now    timestamptz := now();
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ②
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  if p_qty_ea is null or p_qty_ea < 0 then raise exception 'p_qty_ea must be 0 or more — nothing was saved'; end if;
  if p_count_method is not null and p_count_method not in ('scanned', 'manual') then
    raise exception 'p_count_method must be scanned, manual or null — nothing was saved';
  end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — counts can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  select * into v_pl from public.po_line where id = p_po_line_id;
  if not found then raise exception 'PO line % not found — nothing was saved', p_po_line_id; end if;
  if v_pl.po_id <> v_r.po_id then                                              -- 남의 PO 라인을 붙이지 못하게
    raise exception 'PO line % does not belong to the PO of receipt % — nothing was saved', p_po_line_id, v_r.receipt_number;
  end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_pl.product_id;
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || p_po_line_id::text));   -- 이견 12 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지)

  -- 배정 합(빈 붙은 줄들) · 빈 없는 줄
  select coalesce(sum(w.qty_ea), 0) into v_alloc from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = p_po_line_id and w.bin_id is not null;
  select count(*) into v_free_n from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = p_po_line_id and w.bin_id is null;
  if v_free_n > 1 then                                                          -- 불변식 ① 이 깨져 있다 — 자동으로 고치지 않고 알린다
    raise exception 'Line % of receipt % has % unassigned rows — this should not happen; fix the rows first — nothing was saved', v_pl.line_no, v_r.receipt_number, v_free_n;
  end if;
  select * into v_free from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = p_po_line_id and w.bin_id is null;

  -- ⬜2 나머지 = 센 수량 − 배정 합
  v_rest := p_qty_ea - v_alloc;
  if v_rest < 0 then
    raise exception 'Line % (%) of receipt %: counted % is less than the % already assigned to bins — reduce or remove the bin rows first — nothing was saved',
      v_pl.line_no, v_sku, v_r.receipt_number, p_qty_ea, v_alloc;
  end if;

  if v_rest = 0 then
    if v_free.id is not null then
      delete from public.po_receipt_work where id = v_free.id;
      get diagnostics v_n = row_count;
      if v_n = 0 then raise exception 'Line % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_pl.line_no, v_r.receipt_number; end if;
      v_action := 'deleted';
    else
      v_action := 'unchanged';                                                  -- 0 을 세었고 줄도 없다 — 쓸 것이 없다
    end if;
  elsif v_free.id is not null then
    update public.po_receipt_work
       set qty_ea = v_rest, count_method = coalesce(p_count_method, count_method), counted_by = v_staff, counted_at = v_now
     where id = v_free.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Line % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_pl.line_no, v_r.receipt_number; end if;
    v_id := v_free.id; v_action := 'updated';
  else
    insert into public.po_receipt_work (receipt_id, po_line_id, qty_ea, count_method, counted_by, counted_at)
    values (p_receipt_id, p_po_line_id, v_rest, p_count_method, v_staff, v_now)
    returning id into v_id;
    v_action := 'inserted';
  end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', p_po_line_id, 'line_no', v_pl.line_no, 'sku', v_sku,
    'counted', p_qty_ea, 'allocated', v_alloc, 'unallocated', v_rest,
    'work_id', v_id, 'action', v_action, 'counted_by', v_staff, 'counted_at', v_now,
    'over_ordered', (p_qty_ea > v_pl.qty_ea));                                  -- 초과 신호(표시용 · 판정·큐는 2-b 확정 RPC)
end;
$$;
comment on function public.po_receipt_work_save(uuid, uuid, numeric, text) is '⑤ 검수 — 한 라인의 센 수량(총량)을 적는다(리시빙 2-a). ⭐ 빈 없는 줄 = 그 라인의 미배정 나머지(센 수량 − 빈 붙은 줄들의 합) · 라인당 하나(없으면 만들고 · 있으면 고치고 · 나머지 0 이면 지운다) — 부분 유니크가 못 지키는 규칙을 여기서. 센 수량 < 배정 합이면 거부(빈 줄을 먼저 줄여라 · 자동으로 깎지 않는다). draft 만 · 그 PO 의 라인만 · counted_by/at 서버가 찍는다(수량 축 · updated_by 로 갈음 안 함). 정본 po-module §11-i';

-- ═══ ③ po_receipt_work_split — 풋어웨이: 줄을 쪼갠다 (⭐ 합 불변 · 새 줄은 빈을 함께 받는다 · 같은 빈 줄이 있으면 합친다) ═══
-- POST /rest/v1/rpc/po_receipt_work_split  {"p_work_id":…,"p_qty_ea":400,"p_bin_id":"<ref_bin.id>"}
-- → { receipt_number, po_line_id, from:{work_id, qty_before, qty_after}, to:{work_id, bin, qty_before, qty_after, merged}, line_total }
create function public.po_receipt_work_split(
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
    update public.po_receipt_work set qty_ea = qty_ea + p_qty_ea, putaway_by = v_staff, putaway_at = v_now where id = v_to.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_to.id, v_r.receipt_number; end if;
  else
    insert into public.po_receipt_work (receipt_id, po_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at, putaway_by, putaway_at)
    values (v_w.receipt_id, v_w.po_line_id, p_qty_ea, p_bin_id, false, v_w.count_method, v_w.counted_by, v_w.counted_at, v_staff, v_now)   -- 수량 축은 원래 줄의 것을 물려받는다(센 사람은 안 바뀐다)
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
comment on function public.po_receipt_work_split(uuid, numeric, uuid) is '⑤ 풋어웨이 — 줄을 쪼갠다(리시빙 2-a). 원래 줄에서 p_qty_ea 를 빼고 ⭐ 빈을 함께 받은 새 줄을 만든다(합 불변 · 한 함수) · 같은 라인·같은 빈 줄이 있으면 새 줄 대신 거기에 합친다(unique 를 예외가 아니라 병합으로). 원래 수량 이상은 거부(0 이 되면 qty_ea>0 CHECK) · 같은 빈으로는 거부 · 빈은 po_receipt_bin_check(창고·활성). 원래 줄의 수량은 읽은 값 그대로일 때만 뺀다(남이 사이에 바꿨으면 0행 거부). draft 만 · putaway_by/at 서버가 찍는다. 정본 po-module §11-i';

-- ═══ ④ po_receipt_work_putaway — 풋어웨이: 줄에 빈을 정한다 / 놓았다 ═══
-- POST /rest/v1/rpc/po_receipt_work_putaway  {"p_work_id":…,"p_bin_id":"<ref_bin.id>","p_done":true}
-- → { receipt_number, work_id, po_line_id, bin_id, bin, zone, putaway_done, putaway_by, putaway_at, merged_into(같은 빈 줄에 합쳐졌으면 그 id) }
create function public.po_receipt_work_putaway(
  p_work_id uuid,
  p_bin_id  uuid,
  p_done    boolean default true
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
  v_dup    public.po_receipt_work%rowtype;
  v_n      int;
  v_now    timestamptz := now();
  v_out_id uuid;
  v_merged uuid;
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ②
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was saved', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — putaway can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  v_b := public.po_receipt_bin_check(v_w.receipt_id, p_bin_id);                -- 창고·활성
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || v_w.po_line_id::text));   -- 이견 12 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지)

  -- 같은 라인에 그 빈 줄이 이미 있으면(다른 줄) — 합친다(유니크가 막는 자리를 병합으로 · 합 불변)
  select * into v_dup from public.po_receipt_work w
   where w.receipt_id = v_w.receipt_id and w.po_line_id = v_w.po_line_id and w.bin_id = p_bin_id and w.id <> p_work_id;
  if found then
    update public.po_receipt_work set qty_ea = qty_ea + v_w.qty_ea, putaway_done = coalesce(p_done, true), putaway_by = v_staff, putaway_at = v_now where id = v_dup.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_dup.id, v_r.receipt_number; end if;
    delete from public.po_receipt_work where id = p_work_id and qty_ea = v_w.qty_ea;                  -- 읽은 수량 그대로일 때만 지운다
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := v_dup.id; v_merged := v_dup.id;
  else
    update public.po_receipt_work
       set bin_id = p_bin_id, putaway_done = coalesce(p_done, true), putaway_by = v_staff, putaway_at = v_now
     where id = p_work_id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := p_work_id;
  end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'work_id', v_out_id, 'po_line_id', v_w.po_line_id,
    'bin_id', p_bin_id, 'bin', v_b.name, 'zone', v_b.zone, 'putaway_done', coalesce(p_done, true),
    'putaway_by', v_staff, 'putaway_at', v_now, 'merged_into', v_merged);
end;
$$;
comment on function public.po_receipt_work_putaway(uuid, uuid, boolean) is '⑤ 풋어웨이 — 줄에 빈을 정하고(놓았다 p_done · 기본 true) (리시빙 2-a). 빈은 po_receipt_bin_check(그 입고의 창고 · 활성 — 표의 CHECK 로는 못 하는 다른 표 검사 · §5). 같은 라인에 그 빈 줄이 이미 있으면 거기에 합치고 이 줄을 지운다(unique 를 병합으로 · 합 불변). p_done=false 는 「놓지 않았다」로 되돌린다(빈은 유지 · CHECK putaway_bin_ck 와 함께). draft 만 · putaway_by/at 서버가 찍는다(풋어웨이 축). 정본 po-module §11-i';

-- ═══ ⑤ po_receipt_work_putaway_all — 한 빈의 줄 전부 놓았다/해제 (WMS Place all · 이견 8) ═══
-- POST /rest/v1/rpc/po_receipt_work_putaway_all  {"p_receipt_id":…,"p_bin_id":…,"p_done":true}   → { receipt_number, bin, rows_changed, putaway_done }
create function public.po_receipt_work_putaway_all(
  p_receipt_id uuid,
  p_bin_id     uuid,
  p_done       boolean default true
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_r     public.po_receipt%rowtype;
  v_b     public.ref_bin%rowtype;
  v_n     int;
  v_now   timestamptz := now();
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ②
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — putaway can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  v_b := public.po_receipt_bin_check(p_receipt_id, p_bin_id);

  update public.po_receipt_work
     set putaway_done = coalesce(p_done, true), putaway_by = v_staff, putaway_at = v_now
   where receipt_id = p_receipt_id and bin_id = p_bin_id and putaway_done is distinct from coalesce(p_done, true);   -- 이미 그 상태인 줄은 안 건드린다(WMS 와 같다)
  get diagnostics v_n = row_count;
  -- 0행은 여기서 거짓말이 아니다 — 「바꿀 줄이 없었다」를 그대로 알린다(rows_changed 0) · 권한 거부는 첫머리가 이미 걸렀다
  return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'bin_id', p_bin_id, 'bin', v_b.name,
                            'rows_changed', v_n, 'putaway_done', coalesce(p_done, true), 'putaway_by', v_staff, 'putaway_at', v_now);
end;
$$;
comment on function public.po_receipt_work_putaway_all(uuid, uuid, boolean) is '⑤ 풋어웨이 — 한 빈에 배정된 줄 전부를 놓았다(또는 해제)로(리시빙 2-a · WMS Place all 승계 — 작업자는 빈 단위로 움직인다). 이미 그 상태인 줄은 안 건드린다 · rows_changed 를 돌려준다(0 은 「바꿀 줄 없음」 · 거짓말 아님). ⚠️ 이 한 번이 그 빈 줄들의 putaway_by/at 을 덮는다 — 수량 축(counted_*)은 안 덮인다(축 분리의 목적). draft 만. 2026-09-18';

-- ═══ ⑥ po_receipt_work_delete — 줄 삭제 (draft 만) ═══
create function public.po_receipt_work_delete(p_work_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_w  public.po_receipt_work%rowtype;
  v_r  public.po_receipt%rowtype;
  v_n  int;
  v_total numeric;
begin
  perform public.ims_require_write('receiving', 'deleted');    -- §5 ②
  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was deleted', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.confirmed_at is not null or v_r.status <> 'draft' then                    -- 축은 confirmed_at(20260917100000) · status 도 함께(cancelled 도 못 고친다)
    raise exception 'Receipt % is % — rows can be deleted only while draft — nothing was deleted', v_r.receipt_number, v_r.status;
  end if;
  delete from public.po_receipt_work where id = p_work_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Work row % of receipt % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', p_work_id, v_r.receipt_number; end if;
  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and w.po_line_id = v_w.po_line_id;
  return jsonb_build_object('deleted', true, 'work_id', v_w.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number,
                            'po_line_id', v_w.po_line_id, 'qty_removed', v_w.qty_ea, 'bin_id', v_w.bin_id, 'line_total', v_total);
end;
$$;
comment on function public.po_receipt_work_delete(uuid) is '⑤ 작업 줄 삭제(리시빙 2-a) — draft 만(confirmed_at null · status draft) · 0행이면 읽을 문장. 지운 뒤 그 라인의 남은 합(line_total)을 돌려준다(화면이 되읽지 않아도 되게). 2026-09-18';

-- ═══ ⑦ po_receipt_delete — 묶음 삭제 (판정 축 confirmed_at · 작업 줄 cascade · po_receipt_line 은 no action) ═══
create function public.po_receipt_delete(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_r     public.po_receipt%rowtype;
  v_pon   text;
  v_work  int;
  v_lines int;
  v_n     int;
begin
  perform public.ims_require_write('receiving', 'deleted');    -- §5 ②
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was deleted', p_receipt_id; end if;
  if v_r.confirmed_at is not null then                                            -- ⭐ 세 문서와 같은 문장 모양(20260917100000)
    raise exception 'Receipt % was confirmed on % — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted',
      v_r.receipt_number, to_char(v_r.confirmed_at, 'YYYY-MM-DD');
  end if;
  select count(*) into v_lines from public.po_receipt_line l where l.receipt_id = p_receipt_id;   -- FK no action 이 어차피 막는다 — 읽을 문장으로 먼저
  if v_lines > 0 then
    raise exception 'Receipt % has % confirmed receipt line(s) — a receipt with facts in the books cannot be deleted — nothing was deleted', v_r.receipt_number, v_lines;
  end if;
  select po_number into v_pon from public.po p where p.id = v_r.po_id;
  select count(*) into v_work from public.po_receipt_work w where w.receipt_id = p_receipt_id;
  delete from public.po_receipt where id = p_receipt_id;                          -- 작업 줄은 cascade
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Receipt % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', v_r.receipt_number; end if;
  return jsonb_build_object('deleted', true, 'id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_pon, 'status_before', v_r.status, 'work_rows_deleted', v_work);
end;
$$;
comment on function public.po_receipt_delete(uuid) is '⑤ 입고 묶음 삭제(리시빙 2-a) — 판정 축은 confirmed_at(한 번이라도 확정된 것은 지우지 않는다 · 세 문서와 같은 문장 모양) · po_receipt_line 이 가리키면 이름으로 거부(FK no action 이 어차피 막는다) · 작업 줄은 cascade(work_rows_deleted). ⬜ 취소(cancelled)는 이 차수에 없다 — 확정 전 「그만둔다」는 삭제와 같은 뜻 · 확정 뒤 되돌림은 2-b/void 차수. 2026-09-18';

revoke all on function public.po_receipt_create(uuid, date, uuid)                 from public, anon;
revoke all on function public.po_receipt_work_save(uuid, uuid, numeric, text)     from public, anon;
revoke all on function public.po_receipt_work_split(uuid, numeric, uuid)          from public, anon;
revoke all on function public.po_receipt_work_putaway(uuid, uuid, boolean)        from public, anon;
revoke all on function public.po_receipt_work_putaway_all(uuid, uuid, boolean)    from public, anon;
revoke all on function public.po_receipt_work_delete(uuid)                        from public, anon;
revoke all on function public.po_receipt_delete(uuid)                             from public, anon;
grant execute on function public.po_receipt_create(uuid, date, uuid)              to authenticated;
grant execute on function public.po_receipt_work_save(uuid, uuid, numeric, text)  to authenticated;
grant execute on function public.po_receipt_work_split(uuid, numeric, uuid)       to authenticated;
grant execute on function public.po_receipt_work_putaway(uuid, uuid, boolean)     to authenticated;
grant execute on function public.po_receipt_work_putaway_all(uuid, uuid, boolean) to authenticated;
grant execute on function public.po_receipt_work_delete(uuid)                     to authenticated;
grant execute on function public.po_receipt_delete(uuid)                          to authenticated;

-- ═══ ⑧ po_receipt_detail — ⭐ 계산의 정본 (화면은 그린다 · 다시 짜지 않는다) ═══
-- lines[] 는 PO 라인 전부(안 센 라인도) · 라인마다 ordered(po_line.qty_ea · 기준) · invoiced(확정된 인보이스 goods 줄 합 · 표시만) · received_before(이전 확정 입고 합 · po_receipt_line) ·
-- remaining(ordered − received_before · 이번에 세어야 할 것) · counted(이 입고 작업 줄 합) · allocated(빈 붙은 줄 합) · unallocated · placed(putaway_done 줄 합) · over(counted > remaining) · work[]
create function public.po_receipt_detail(p_receipt_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with r as (
  select * from public.po_receipt where id = p_receipt_id
),
w as (
  select k.*, b.name as bin, b.zone,
         (select s.name from public.ims_staff s where s.id = k.counted_by) as counted_by_name,     -- ⚠️ 별칭 — ims_staff 자기 칸과 헷갈리지 않게
         (select s.name from public.ims_staff s where s.id = k.putaway_by) as putaway_by_name,
         (select s.name from public.ims_staff s where s.id = k.updated_by) as updated_by_name
  from public.po_receipt_work k
  left join public.ref_bin b on b.id = k.bin_id
  where k.receipt_id = p_receipt_id
),
lines as (
  select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pr.name as product_name, pl.supplier_sku, pl.qty_ea as ordered,
         pl.entered_unit_product_id, pl.entered_qty, pl.entered_pack_factor,
         coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                    where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0) as invoiced,
         coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as received_before,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id), 0) as counted,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.bin_id is not null), 0) as allocated,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.putaway_done), 0) as placed
  from r
  join public.po_line pl on pl.po_id = r.po_id
  join public.product pr on pr.id = pl.product_id
)
select case when not exists (select 1 from r) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', r.id, 'receipt_number', r.receipt_number, 'status', r.status, 'received_on', r.received_on,
      'po_id', r.po_id, 'po_number', p.po_number, 'po_status', p.status,
      'supplier_id', p.supplier_id, 'supplier_name', s.name,
      'warehouse_id', r.warehouse_id, 'warehouse_name', wh.name,
      'created_by', r.created_by, 'created_by_name', cb.name,
      'confirmed_at', r.confirmed_at, 'confirmed_by_name', fb.name,
      'cancelled_at', r.cancelled_at, 'cancelled_by_name', xb.name,
      'note', r.note, 'created_at', r.created_at, 'updated_at', r.updated_at, 'updated_by_name', ub.name)
    from r
    join public.po p on p.id = r.po_id
    join public.supplier s on s.id = p.supplier_id
    join public.ref_warehouse wh on wh.id = r.warehouse_id
    left join public.ims_staff cb on cb.id = r.created_by
    left join public.ims_staff fb on fb.id = r.confirmed_by
    left join public.ims_staff xb on xb.id = r.cancelled_by
    left join public.ims_staff ub on ub.id = r.updated_by
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'po_line_id', l.po_line_id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', l.product_name, 'supplier_sku', l.supplier_sku,
      'entered_unit_product_id', l.entered_unit_product_id, 'entered_qty', l.entered_qty, 'entered_pack_factor', l.entered_pack_factor,
      'ordered', l.ordered, 'invoiced', l.invoiced, 'received_before', l.received_before,
      'remaining', l.ordered - l.received_before,
      'counted', l.counted, 'allocated', l.allocated, 'unallocated', l.counted - l.allocated, 'placed', l.placed,
      'over', (l.counted > l.ordered - l.received_before),
      'work', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', x.id, 'qty_ea', x.qty_ea, 'bin_id', x.bin_id, 'bin', x.bin, 'zone', x.zone, 'putaway_done', x.putaway_done,
          'count_method', x.count_method, 'counted_by', x.counted_by, 'counted_by_name', x.counted_by_name, 'counted_at', x.counted_at,
          'putaway_by', x.putaway_by, 'putaway_by_name', x.putaway_by_name, 'putaway_at', x.putaway_at,
          'note', x.note, 'updated_at', x.updated_at, 'updated_by_name', x.updated_by_name)
          order by x.bin_id nulls first, x.created_at)
        from w x where x.po_line_id = l.po_line_id), '[]'::jsonb))
      order by l.line_no)
    from lines l), '[]'::jsonb),
  'totals', (
    select jsonb_build_object(
      'lines', count(*), 'counted_lines', count(*) filter (where l.counted > 0),
      'ordered', coalesce(sum(l.ordered), 0), 'remaining', coalesce(sum(l.ordered - l.received_before), 0),
      'counted', coalesce(sum(l.counted), 0), 'allocated', coalesce(sum(l.allocated), 0), 'placed', coalesce(sum(l.placed), 0),
      'over_lines', count(*) filter (where l.counted > l.ordered - l.received_before),
      'short_lines', count(*) filter (where l.counted < l.ordered - l.received_before))
    from lines l
  ),
  'warnings', (
    select coalesce(jsonb_agg(v), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when (select p.status from r join public.po p on p.id = r.po_id) <> 'confirmed' then 'po_not_confirmed' end,
        case when exists (select 1 from lines l where l.counted > l.ordered - l.received_before) then 'over_receipt' end,
        case when exists (select 1 from w x where x.bin_id is null) then 'unassigned_rows' end,
        case when not exists (select 1 from w) then 'nothing_counted' end
      ], null)) as v) t
  )
) end;
$$;
comment on function public.po_receipt_detail(uuid) is '⑤ 입고 상세 — ⭐ 계산의 정본(화면은 그린다 · 다시 짜지 않는다 · 리시빙 2-a). header · lines[] = PO 라인 전부(안 센 라인도 · 세우려면 보여야 한다) — ordered(기준 · po_line.qty_ea) · invoiced(확정 인보이스 goods 합 · 표시만 · 아무것도 결정하지 않는다) · received_before(이전 확정 입고 합) · remaining · counted(작업 줄 합) · allocated(빈 붙은 합) · unallocated · placed · over · work[](줄마다 빈·놓았나·센 사람·넣은 사람 · 이름은 별칭 서브쿼리) · product_id(ims_last_bin 의 입력) · totals · warnings[](po_not_confirmed · over_receipt · unassigned_rows · nothing_counted). 시각은 timestamptz 원문(화면이 imsTs). 없는 id → null. jsonb 단일 값(캡 밖). 정본 po-module §11-i';
revoke all on function public.po_receipt_detail(uuid) from public, anon;
grant execute on function public.po_receipt_detail(uuid) to authenticated;

-- ═══ ⑨ po_receipt_list — 목록 뷰 (po_list · po_invoice_list 와 같은 결 · security_invoker) ═══
create view public.po_receipt_list
  with (security_invoker = true) as
with w as (
  select k.receipt_id,
         count(distinct k.po_line_id)::int                                          as counted_lines,
         coalesce(sum(k.qty_ea), 0)                                                 as counted_qty,
         coalesce(sum(k.qty_ea) filter (where k.bin_id is not null), 0)             as allocated_qty,
         coalesce(sum(k.qty_ea) filter (where k.putaway_done), 0)                   as placed_qty,
         count(*) filter (where k.bin_id is null)::int                               as unassigned_rows
  from public.po_receipt_work k
  group by k.receipt_id
),
pl as (
  select po_id, count(*)::int as po_lines, coalesce(sum(qty_ea), 0) as ordered_qty from public.po_line group by po_id
)
select
  r.id, r.receipt_number, r.status, r.received_on,
  r.po_id, p.po_number, p.status as po_status,
  p.supplier_id, s.name as supplier_name,
  r.warehouse_id, wh.name as warehouse_name,
  coalesce(pl.po_lines, 0)          as po_lines,
  coalesce(pl.ordered_qty, 0)       as ordered_qty,
  coalesce(w.counted_lines, 0)      as counted_lines,
  coalesce(w.counted_qty, 0)        as counted_qty,
  coalesce(w.allocated_qty, 0)      as allocated_qty,
  coalesce(w.placed_qty, 0)         as placed_qty,
  coalesce(w.unassigned_rows, 0)    as unassigned_rows,
  r.created_by, cb.name as created_by_name,
  r.confirmed_at, r.cancelled_at, r.note, r.created_at, r.updated_at
from public.po_receipt r
join public.po p on p.id = r.po_id
join public.supplier s on s.id = p.supplier_id
join public.ref_warehouse wh on wh.id = r.warehouse_id
left join public.ims_staff cb on cb.id = r.created_by
left join w  on w.receipt_id = r.id
left join pl on pl.po_id = r.po_id;

comment on view public.po_receipt_list is '⑤ 입고 목록 — PostgREST 로 표처럼(§10-j 3-a · po_list·po_invoice_list 와 같은 결). 번호 · PO · 공급처 · 창고 · 받은 날 · 상태 · PO 라인 수 · 센 수량 합 · 배정 합 · 놓은 합 · 미배정 줄 수 · 만든 사람. 계산은 뷰가(화면이 다시 짜지 않는다). security_invoker. 2026-09-18';
revoke all on public.po_receipt_list from anon;
grant select on public.po_receipt_list to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 화면(receiving.html · 대화 Claude · 다음 차수)이 부르는 모양 — 여기 한 곳
--   목록      sb.from("po_receipt_list").select("*",{count:"exact"}).order("received_on",{ascending:false}).range(a,b) · .ilike receipt_number · po_number · supplier_name · 필터 status · warehouse_id
--   열기      sb.rpc("po_receipt_create", { p_po_id })                                   → data.id · data.receipt_number · 거부 문장은 그대로 띄운다(「already has an open receipt (RCV-00003)」)
--   상세      sb.rpc("po_receipt_detail", { p_receipt_id })                              → header · lines[](ordered·invoiced·remaining·counted·allocated·placed·work[]) · totals · warnings
--   세기      sb.rpc("po_receipt_work_save", { p_receipt_id, p_po_line_id, p_qty_ea, p_count_method:"scanned"|"manual" })   ⭐ 그 라인의 낱개 총량을 보낸다(팩→낱개 환산 RPC 는 이 차수에 없다 · 이견 3) → data.counted · allocated · unallocated
--   Last bin  sb.rpc("ims_last_bin", { p_product_ids: lines.map(l=>l.product_id), p_warehouse_id: header.warehouse_id })  → { "<product_id>": {bin_id, bin, zone, received_on} }
--   빈 정하기 sb.rpc("po_receipt_work_putaway", { p_work_id, p_bin_id, p_done:true })      · Place all sb.rpc("po_receipt_work_putaway_all", { p_receipt_id, p_bin_id, p_done })
--   쪼개기    sb.rpc("po_receipt_work_split", { p_work_id, p_qty_ea, p_bin_id })          → from/to/line_total(전과 같아야)
--   지우기    sb.rpc("po_receipt_work_delete", { p_work_id }) · sb.rpc("po_receipt_delete", { p_receipt_id })
--   ⚠️ 화면은 계산하지 않는다 — counted/allocated/remaining/over 는 detail 이 준 값 · 저장 뒤 detail 을 되읽는다(스크롤 자리 유지 §10-j 3-i)
