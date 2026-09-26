-- ⑤-3a WMS 입고 첫째 — 발주 입고 창구를 속 · 바깥으로 · WMS 입고 창구 · 보류 · off-PO 큐 (2026-09-26 UTC · 토론토 2026-09-26 저녁)
-- 정본 so-module §24(판정 5 · 7 · 25) · po-module §11-i · §13-i · 지시서 ~/asung/prompts/wms-5-3.md · 판정 회신 wms-5-3-rulings.md(판정 27 · 28 · 29 · ⬜ 열다섯 안 · 이견 여섯)
-- 대상: [테스트 · Asung-IMS] 만 — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/wms-5-3a-verify.sql(-v mig)
-- ⛔⛔ 절대 조건(Caleb 2026-09-26): 운영 WMS(asung-WMS · wms.asung.ca)는 어떤 경우에도 멈추면 안 된다.
--     첫 문장 = 운영 가드(원본 supabase/ops/guard-test-only.sql 의 글자를 그대로 복사 · 검증 G0 이 임시 파일 diff 로 같음을 잰다).
--     흔적 셋 중 하나라도 있으면 WM501 로 멈춘다(OR · fail-closed): cron.job 에 wms-poll-orders/wms-auto-hold · inv_config.db_role <> 'test' · wms_health_runs 행 > 0
-- 하는 일(§1 순서):
--   1. ims_perm_catalog 재발행 — wms_receiving(room wms · worker 기본) · wms_receiving_confirm(room wms · min_role manager · 판정 27 스위치 · 창구는 ⑤-3b · 지금은 아무에게도 안 켠다)
--   2. wms_task_holds — receipt_id uuid → po_receipt(restrict) · task_kind 'receipt' 되살림 · CHECK 짝((receipt) = (receipt_id 있음) · (receipt 아님) = (task_id 있음)) · 발주 표 무접촉
--   3. 속 여섯(_by · p_staff · 문 없음 · authenticated 회수) — po_receipt_create · work_save · work_putaway · work_putaway_all · product_bin_overflow_set · clear
--      원본 바이트에서 문 줄 · 사람 찾기 줄만 빼고 p_staff 를 받는다 · ⚠️ po_receipt* 넷은 definer 로(RLS 가 receiving 을 요구 · 아래 3 절 주석)
--   4. 오피스 셸 여섯 — 이름 · 시그니처 그대로(asung-ims receiving.html 무접촉) · 첫 줄 receiving 문 · 다음 ims_can_warehouse(po-module 3504 ⬜ 닫힘) · 속 호출 · 반환 그대로
--   5. WMS 셸 열 wms_recv_* — 첫 줄 wms_receiving 문 · 다음 ims_can_warehouse · 같은 속
--      start(있는 초안이면 연다 · 없으면 create_by — ⚠️ RCV 번호를 당긴다 · 검증은 이 가지를 안 돌린다) · scan(델타 → 잠금 아래 총량 · 동시 스캔 병합) · count(본 값 CAS · 다르면 거부 + 지금 값) ·
--      putaway · place_all(운영 placeAllInBin 과 같은 뜻 = 그 칸에 배정된 줄들의 placed 토글 · 이미 그 상태인 줄은 안 쓴다 — 원문 대조 2026-09-26) · off_po(큐에 적기만 · 재고 무접촉 · 승인·투입은 ⑤-6) ·
--      hold · resume(보류 = wms_task_holds receipt 행 · 문서 status 는 draft 그대로 · 판정 28 Partial 없음) · overflow_set · overflow_clear(§20 판정 3 받는 직원)
-- 그대로 둘 것(오피스만 · receiving 문 유지 · 이 파일 무접촉): work_split · work_unassign · work_delete · receipt_delete · diff_resolve · diff_reopen · diff_settle_over · inv_post_receipt_over · inv_layer_post_receipt_over
-- ⑤-3b 로 미루는 것: po_receipt_confirm · inv_post_receipt · inv_layer_post_receipt 의 속화 + 회수 · 오피스 confirm 셸 · WMS Complete 기록 · WMS 확정 창구(wms_receiving_confirm 문)
-- 판정 29: 운영 savePutawayAssigns(열기만 해도 자동 배정 쓰기)에 해당하는 창구는 없다 — 제안은 화면이 ims_last_bin 으로 읽고 놓았다를 누를 때 putaway 가 누가 · 언제를 적는다
-- ⚠️ 번호(PO · 입고 · SO · 인보이스 · 크레딧)를 이 파일이 당기지 않는다(po_receipt_create_by 는 부르는 쪽이 당긴다 · 검증은 「이미 초안이 있다」 · 「PO 가 confirmed 아님」 가지만) · 원장 · 원가 무접촉

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

-- ═══ 1) ims_perm_catalog 재발행 — 마지막 정의 20260926192314:243~262 · 더한 줄 2(wms_receiving · wms_receiving_confirm) · wms_manage 줄 끝 쉼표 · 나머지 그대로 ═══
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
      "wms_receiving_confirm": {"room": "wms", "min_role": "manager", "label": "Warehouse receiving — confirm a receipt (manager and above · off until switched on)"}
    }
  }'::jsonb;
$$;

-- ═══ 2) wms_task_holds — 입고 보류 자리(⬜6 · 24-g ① 닫힘) ═══
alter table public.wms_task_holds
  add column receipt_id uuid references public.po_receipt (id) on delete restrict,
  alter column task_id drop not null,
  drop constraint wms_task_holds_task_kind_check,
  add constraint wms_task_holds_task_kind_check check (task_kind in ('pick', 'pack', 'wave', 'receipt')),
  add constraint wms_task_holds_receipt_pair_ck check ((task_kind = 'receipt') = (receipt_id is not null)),
  add constraint wms_task_holds_task_pair_ck    check ((task_kind <> 'receipt') = (task_id is not null));
create index idx_task_holds_receipt on public.wms_task_holds (receipt_id) where receipt_id is not null;
comment on table public.wms_task_holds is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — worker·resumed_by ims_staff.id · task_kind 넷(pick·pack·wave 는 task_id bigint · receipt 는 receipt_id uuid → po_receipt · ⑤-3a 되살림 · CHECK 짝) · source 둘(manual·auto — 운영의 partial 은 판정 28 로 없다) · 입고 보류는 wms_recv_hold/resume · 옛 표는 wms_legacy';
comment on column public.wms_task_holds.receipt_id is '⑤-3a 입고 보류 — po_receipt(id) · task_kind = receipt 일 때만(CHECK 짝) · 문서 status 는 draft 그대로 · 「held」 = 열린 행(resumed_at null) 존재 · 통계는 이 한 표에서(규칙 37 「− holds」)';

-- ═══ 3) 속 여섯 — 원본 바이트에서 문 줄 · 사람 찾기 줄만 빼고 p_staff 를 받는다(판정 7 · 이름 _by · authenticated 회수) ═══
--   원본: po_receipt_create 20260924001820:162 · work_save 20260918163552:142 · work_putaway 163552:312 · work_putaway_all 163552:376 · product_bin_overflow_set/clear 20260925133147:42·85
--   ⚠️ po_receipt* 넷은 definer 로(원본은 invoker) — po_receipt·po_receipt_work 의 RLS 가 ims_can_write('receiving') 을 요구해 창고 사람은 셸의 문을 지나도 표에서 막힌다 · overflow 둘은 원래 definer

create function public.po_receipt_create_by(
  p_staff        uuid,                              -- ⑤-3a 속: 부른 셸이 확인한 사람(판정 7) · 문은 셸에
  p_po_id        uuid,
  p_received_on  date default public.ims_today(),
  p_warehouse_id uuid default null                  -- po.ship_to_warehouse_id 가 null 일 때만 쓴다
) returns jsonb
language plpgsql
volatile
security definer                                   -- ⑤-3a: po_receipt* 의 RLS 가 receiving 을 요구한다 · 창고 사람은 셸의 문을 지나 여기로 · 표는 소유자로 쓴다
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
  if p_staff is null then raise exception 'po_receipt_create_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  -- 만든 사람 — 서버 유도(po_create 선례 · 화면이 주지 않는다)

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
  if p_received_on is not null and p_received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  insert into public.po_receipt (po_id, warehouse_id, received_on, status, created_by)
  values (p_po_id, v_wh, coalesce(p_received_on, public.ims_today()), 'draft', v_staff)
  returning * into v_r;

  return jsonb_build_object(
    'id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status,
    'po_id', v_po.id, 'po_number', v_po.po_number,
    'warehouse_id', v_wh, 'warehouse_name', v_whn, 'received_on', v_r.received_on,
    'created_by', v_staff, 'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.po_receipt_create_by(uuid, uuid, date, uuid) from public, anon, authenticated;

create function public.po_receipt_work_save_by(
  p_staff        uuid,                              -- ⑤-3a 속: 부른 셸이 확인한 사람(판정 7) · 문은 셸에
  p_receipt_id   uuid,
  p_po_line_id   uuid,
  p_qty_ea       numeric,                           -- ⭐ 그 라인의 센 수량(총량 · 낱개) · 0 = 센 것 없음
  p_count_method text default null                  -- 'scanned' | 'manual' | null
) returns jsonb
language plpgsql
volatile
security definer                                   -- ⑤-3a: po_receipt* 의 RLS 가 receiving 을 요구한다 · 창고 사람은 셸의 문을 지나 여기로 · 표는 소유자로 쓴다
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
  if p_staff is null then raise exception 'po_receipt_work_save_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

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
revoke all on function public.po_receipt_work_save_by(uuid, uuid, uuid, numeric, text) from public, anon, authenticated;

create function public.po_receipt_work_putaway_by(
  p_staff        uuid,                              -- ⑤-3a 속: 부른 셸이 확인한 사람(판정 7) · 문은 셸에
  p_work_id uuid,
  p_bin_id  uuid,
  p_done    boolean default true
) returns jsonb
language plpgsql
volatile
security definer                                   -- ⑤-3a: po_receipt* 의 RLS 가 receiving 을 요구한다 · 창고 사람은 셸의 문을 지나 여기로 · 표는 소유자로 쓴다
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
  if p_staff is null then raise exception 'po_receipt_work_putaway_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

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
revoke all on function public.po_receipt_work_putaway_by(uuid, uuid, uuid, boolean) from public, anon, authenticated;

create function public.po_receipt_work_putaway_all_by(
  p_staff        uuid,                              -- ⑤-3a 속: 부른 셸이 확인한 사람(판정 7) · 문은 셸에
  p_receipt_id uuid,
  p_bin_id     uuid,
  p_done       boolean default true
) returns jsonb
language plpgsql
volatile
security definer                                   -- ⑤-3a: po_receipt* 의 RLS 가 receiving 을 요구한다 · 창고 사람은 셸의 문을 지나 여기로 · 표는 소유자로 쓴다
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_r     public.po_receipt%rowtype;
  v_b     public.ref_bin%rowtype;
  v_n     int;
  v_now   timestamptz := now();
begin
  if p_staff is null then raise exception 'po_receipt_work_putaway_all_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;
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
revoke all on function public.po_receipt_work_putaway_all_by(uuid, uuid, uuid, boolean) from public, anon, authenticated;

create function public.product_bin_overflow_set_by(p_staff uuid, p_product_id uuid, p_bin_id uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_p     public.product%rowtype;
  v_base  public.product%rowtype;
  v_b     public.ref_bin%rowtype;
  v_w     text;
  v_row   public.product_bin_overflow%rowtype;
  v_new   boolean := false;
begin
  if p_staff is null then raise exception 'product_bin_overflow_set_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;
  select * into v_p from public.product p where p.id = p_product_id;
  if not found then raise exception 'Product not found — nothing was saved'; end if;
  if v_p.parent_product_id is not null then
    select * into v_base from public.product p where p.id = v_p.parent_product_id;                       -- 세트 → 낱개(원장 축)
  else
    v_base := v_p;
  end if;
  select * into v_b from public.ref_bin b where b.id = p_bin_id;
  if not found then raise exception 'Bin not found — nothing was saved'; end if;
  if not v_b.is_active then raise exception 'Bin % is inactive — an overflow mark needs an active bin — nothing was saved', v_b.name; end if;
  select w.name into v_w from public.ref_warehouse w where w.id = v_b.warehouse_id;

  select * into v_row from public.product_bin_overflow o where o.product_id = v_base.id and o.bin_id = v_b.id;
  if not found then
    insert into public.product_bin_overflow (product_id, bin_id, note, created_by, updated_by)
    values (v_base.id, v_b.id, nullif(trim(p_note), ''), v_staff, v_staff) returning * into v_row;
    v_new := true;
  elsif p_note is not null and nullif(trim(p_note), '') is distinct from v_row.note then
    update public.product_bin_overflow set note = nullif(trim(p_note), ''), updated_by = v_staff where id = v_row.id returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row.id, 'product_id', v_base.id, 'sku', v_base.sku, 'from_set', v_p.id <> v_base.id, 'bin_id', v_b.id, 'bin', v_b.name, 'warehouse', v_w,
                            'overflow', true, 'created', v_new, 'already', not v_new, 'note', v_row.note);
end;
$$;
revoke all on function public.product_bin_overflow_set_by(uuid, uuid, uuid, text) from public, anon, authenticated;

create function public.product_bin_overflow_clear_by(p_staff uuid, p_product_id uuid, p_bin_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_p     public.product%rowtype;
  v_pid   uuid;
  v_n     int;
begin
  if p_staff is null then raise exception 'product_bin_overflow_clear_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;
  select * into v_p from public.product p where p.id = p_product_id;
  if not found then raise exception 'Product not found — nothing was saved'; end if;
  v_pid := coalesce(v_p.parent_product_id, v_p.id);
  delete from public.product_bin_overflow o where o.product_id = v_pid and o.bin_id = p_bin_id;
  get diagnostics v_n = row_count;
  return jsonb_build_object('product_id', v_pid, 'bin_id', p_bin_id, 'cleared', v_n = 1, 'overflow', false);
end;
$$;
revoke all on function public.product_bin_overflow_clear_by(uuid, uuid, uuid) from public, anon, authenticated;

-- ═══ 4) 오피스 셸 여섯 — 이름 · 시그니처 그대로 · 첫 줄 receiving 문 · ims_can_warehouse · 속 호출 · 반환 그대로 ═══
create or replace function public.po_receipt_create(
  p_po_id        uuid,
  p_received_on  date default public.ims_today(),
  p_warehouse_id uuid default null                  -- po.ship_to_warehouse_id 가 null 일 때만 쓴다
) returns jsonb
language plpgsql security definer                  -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
set search_path = public, pg_temp
as $$
declare v_staff uuid; v_wh uuid;
begin
  perform public.ims_require_write('receiving', 'saved');      -- ⭐ 첫 줄(§5 ②)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select coalesce(p.ship_to_warehouse_id, p_warehouse_id) into v_wh from public.po p where p.id = p_po_id;
  if v_wh is not null and not public.ims_can_warehouse(v_wh) then
    raise exception 'This PO ships to another warehouse — you are not set up for it — nothing was saved';
  end if;
  return public.po_receipt_create_by(v_staff, p_po_id, p_received_on, p_warehouse_id);
end;
$$;
create or replace function public.po_receipt_work_save(
  p_receipt_id   uuid,
  p_po_line_id   uuid,
  p_qty_ea       numeric,                           -- ⭐ 그 라인의 센 수량(총량 · 낱개) · 0 = 센 것 없음
  p_count_method text default null                  -- 'scanned' | 'manual' | null
) returns jsonb
language plpgsql security definer                  -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  perform public.ims_require_write('receiving', 'saved');      -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if not public.ims_can_warehouse((select r.warehouse_id from public.po_receipt r where r.id = p_receipt_id)) then
    raise exception 'This receipt is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  return public.po_receipt_work_save_by(v_staff, p_receipt_id, p_po_line_id, p_qty_ea, p_count_method);
end;
$$;
create or replace function public.po_receipt_work_putaway(
  p_work_id uuid,
  p_bin_id  uuid,
  p_done    boolean default true
) returns jsonb
language plpgsql security definer                  -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  perform public.ims_require_write('receiving', 'saved');      -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if not public.ims_can_warehouse((select r.warehouse_id from public.po_receipt_work w join public.po_receipt r on r.id = w.receipt_id where w.id = p_work_id)) then
    raise exception 'This receipt is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  return public.po_receipt_work_putaway_by(v_staff, p_work_id, p_bin_id, p_done);
end;
$$;
create or replace function public.po_receipt_work_putaway_all(
  p_receipt_id uuid,
  p_bin_id     uuid,
  p_done       boolean default true
) returns jsonb
language plpgsql security definer                  -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  perform public.ims_require_write('receiving', 'saved');      -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if not public.ims_can_warehouse((select r.warehouse_id from public.po_receipt r where r.id = p_receipt_id)) then
    raise exception 'This receipt is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  return public.po_receipt_work_putaway_all_by(v_staff, p_receipt_id, p_bin_id, p_done);
end;
$$;
create or replace function public.product_bin_overflow_set(p_product_id uuid, p_bin_id uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  perform public.ims_require_write('receiving', 'saved');       -- ⭐ 첫 줄 — 판정 3(받는 직원 · 매니저로 좁히지 않는다)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if not public.ims_can_warehouse((select b.warehouse_id from public.ref_bin b where b.id = p_bin_id)) then
    raise exception 'This bin is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  return public.product_bin_overflow_set_by(v_staff, p_product_id, p_bin_id, p_note);
end;
$$;
create or replace function public.product_bin_overflow_clear(p_product_id uuid, p_bin_id uuid) returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  perform public.ims_require_write('receiving', 'saved');       -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if not public.ims_can_warehouse((select b.warehouse_id from public.ref_bin b where b.id = p_bin_id)) then
    raise exception 'This bin is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  return public.product_bin_overflow_clear_by(v_staff, p_product_id, p_bin_id);
end;
$$;
-- 셸 여섯의 grant 는 원래대로(authenticated execute · 원본 파일의 grant 가 남아 있다) · overflow 둘은 이제 셸이 invoker 라 속이 definer 를 맡는다

-- ═══ 5) WMS 셸 열 wms_recv_* — 첫 줄 wms_receiving 문 · ims_can_warehouse · 같은 속 ═══
-- 공통 속: 입고 행 + 창고 검사(draft 검사는 속이 · 여기서는 창고만)
create function public.wms_recv_gate(p_receipt_id uuid) returns public.po_receipt
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare v_r public.po_receipt%rowtype;
begin
  select * into v_r from public.po_receipt r where r.id = p_receipt_id;
  if not found then raise exception 'Receipt not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_r.warehouse_id) then
    raise exception 'Receipt % is at another warehouse — you are not set up for it — nothing was saved', v_r.receipt_number;
  end if;
  return v_r;
end;
$$;
revoke all on function public.wms_recv_gate(uuid) from public, anon, authenticated;

-- start — 그 PO 의 열린 초안이 있으면 그것을 연다(existing true) · 없으면 속 create(⚠️ RCV 번호를 당긴다 · 검증은 이 가지를 안 돌린다) · confirmed 아닌 PO 는 속이 거부
create function public.wms_recv_start(p_po_id uuid) returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_po public.po%rowtype; v_r public.po_receipt%rowtype; v_out jsonb;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_po from public.po p where p.id = p_po_id;
  if not found then raise exception 'PO not found — nothing was saved'; end if;
  if v_po.ship_to_warehouse_id is not null and not public.ims_can_warehouse(v_po.ship_to_warehouse_id) then
    raise exception 'PO % ships to another warehouse — you are not set up for it — nothing was saved', v_po.po_number;
  end if;
  select * into v_r from public.po_receipt r where r.po_id = p_po_id and r.status = 'draft' order by r.created_at limit 1;
  if found then
    return jsonb_build_object('id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status, 'po_id', v_po.id, 'po_number', v_po.po_number,
                              'warehouse_id', v_r.warehouse_id, 'received_on', v_r.received_on, 'existing', true,
                              'held', exists (select 1 from public.wms_task_holds h where h.receipt_id = v_r.id and h.resumed_at is null));
  end if;
  v_out := public.po_receipt_create_by(v_staff, p_po_id, public.ims_today(), null);
  return v_out || jsonb_build_object('existing', false, 'held', false);
end;
$$;
comment on function public.wms_recv_start(uuid) is '⑤-3a WMS 입고 시작(운영 startPo) — 첫 줄 ims_require_write(wms_receiving) · 창고 · PO 당 열린 초안 하나: 있으면 그것을 연다(existing true · held) · 없으면 po_receipt_create_by(confirmed PO 만 · 창고 = ship_to · RCV 번호) · 라인 껍데기는 안 만든다(po_receipt_detail 이 PO 라인 전부를 그린다)';
revoke all on function public.wms_recv_start(uuid) from public, anon;
grant execute on function public.wms_recv_start(uuid) to authenticated;

-- scan — 델타 · 같은 라인 잠금(속과 같은 열쇠) 아래 지금 총량 + delta 를 속 work_save 에 총량으로 · 두 사람의 동시 스캔이 합쳐진다(⬜8)
create function public.wms_recv_scan(p_receipt_id uuid, p_po_line_id uuid, p_delta_ea numeric, p_count_method text default 'scanned') returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_total numeric;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_r := public.wms_recv_gate(p_receipt_id);
  if p_delta_ea is null or p_delta_ea = 0 then raise exception 'Scan delta must not be 0 — nothing was saved'; end if;
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || p_po_line_id::text));   -- 속과 같은 열쇠(재진입) · 읽기와 쓰기를 한 손에
  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = p_po_line_id;
  if v_total + p_delta_ea < 0 then raise exception 'Line total would go below 0 (now % · delta %) — nothing was saved', v_total, p_delta_ea; end if;
  return public.po_receipt_work_save_by(v_staff, p_receipt_id, p_po_line_id, v_total + p_delta_ea, p_count_method) || jsonb_build_object('delta', p_delta_ea, 'total_before', v_total);
end;
$$;
comment on function public.wms_recv_scan(uuid, uuid, numeric, text) is '⑤-3a WMS 스캔(운영 writeLine kind qty 의 델타) — 첫 줄 ims_require_write(wms_receiving) · 창고 · 라인 잠금 아래 「지금 총량 + delta」를 po_receipt_work_save_by 에 총량으로 넘긴다 ⇒ 같은 SKU 동시 스캔이 합쳐진다(po-module 3504 ⬜) · 초과는 over_ordered 표시만(막지 않는다) · 반환 = work_save 의 것 + delta · total_before';
revoke all on function public.wms_recv_scan(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.wms_recv_scan(uuid, uuid, numeric, text) to authenticated;

-- count — 손 고치기(절대값) · p_seen_total(화면이 본 총량)이 지금과 다르면 거부 + 지금 값(운영 askQtyConflict 의 서버 판 · CAS 축 = 총량)
create function public.wms_recv_count(p_receipt_id uuid, p_po_line_id uuid, p_total_ea numeric, p_seen_total numeric, p_count_method text default 'manual') returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_total numeric;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_r := public.wms_recv_gate(p_receipt_id);
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || p_po_line_id::text));
  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = p_po_line_id;
  if p_seen_total is not null and v_total <> p_seen_total then
    raise exception 'Line total changed under you: you saw %, it is now % (someone else counted) — reload the line and try again — nothing was saved', p_seen_total, v_total;
  end if;
  return public.po_receipt_work_save_by(v_staff, p_receipt_id, p_po_line_id, p_total_ea, p_count_method) || jsonb_build_object('total_before', v_total);
end;
$$;
comment on function public.wms_recv_count(uuid, uuid, numeric, numeric, text) is '⑤-3a WMS 손 고치기(절대값 · 운영 스테퍼·수동 입력) — 첫 줄 ims_require_write(wms_receiving) · 창고 · 라인 잠금 아래 p_seen_total ≠ 지금 총량이면 거부하고 지금 값을 문장에(화면은 Keep theirs / Use mine / Recount) · null 이면 검사 없이 · 그 뒤 po_receipt_work_save_by(총량)';
revoke all on function public.wms_recv_count(uuid, uuid, numeric, numeric, text) from public, anon;
grant execute on function public.wms_recv_count(uuid, uuid, numeric, numeric, text) to authenticated;

-- putaway — 한 줄에 칸 + 놓았다(누가 · 언제는 속이 찍는다 · 판정 29 「누를 때 기록」)
create function public.wms_recv_putaway(p_work_id uuid, p_bin_id uuid, p_done boolean default true) returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_rid uuid;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select w.receipt_id into v_rid from public.po_receipt_work w where w.id = p_work_id;
  if v_rid is null then raise exception 'Work row not found — nothing was saved'; end if;
  perform public.wms_recv_gate(v_rid);
  return public.po_receipt_work_putaway_by(v_staff, p_work_id, p_bin_id, p_done);
end;
$$;
comment on function public.wms_recv_putaway(uuid, uuid, boolean) is '⑤-3a WMS 놓기(운영 savePutaway · Change bin · Placed 토글) — 첫 줄 ims_require_write(wms_receiving) · 창고 · po_receipt_work_putaway_by(칸은 ref_bin · 그 입고의 창고 · 활성 · 같은 칸 줄과 병합 · putaway_by/at = 누른 사람 · 그때 · 판정 24 · 29)';
revoke all on function public.wms_recv_putaway(uuid, uuid, boolean) from public, anon;
grant execute on function public.wms_recv_putaway(uuid, uuid, boolean) to authenticated;

-- place_all — 운영 placeAllInBin 과 같은 뜻: 그 칸에 이미 배정된 줄들의 placed 를 p_done 으로 · 이미 그 상태인 줄은 안 쓴다(rows_changed)
create function public.wms_recv_place_all(p_receipt_id uuid, p_bin_id uuid, p_done boolean default true) returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  perform public.wms_recv_gate(p_receipt_id);
  return public.po_receipt_work_putaway_all_by(v_staff, p_receipt_id, p_bin_id, p_done);
end;
$$;
comment on function public.wms_recv_place_all(uuid, uuid, boolean) is '⑤-3a WMS Place all(운영 placeAllInBin — 원문 대조 2026-09-26: 그 칸에 이미 배정된 줄들의 placed 토글 · 방향은 화면이 정한다 · 이미 그 상태인 줄은 안 쓴다) — 첫 줄 ims_require_write(wms_receiving) · 창고 · po_receipt_work_putaway_all_by';
revoke all on function public.wms_recv_place_all(uuid, uuid, boolean) from public, anon;
grant execute on function public.wms_recv_place_all(uuid, uuid, boolean) to authenticated;

-- off_po — PO 에 없는 물건: 차이 큐 po_receipt_diff kind off_po 한 행(product · received) · 같은 제품 다시 = 수량 더함 · 재고 · 원장 무접촉 · 승인 · 투입은 ⑤-6
create function public.wms_recv_off_po(p_receipt_id uuid, p_product_id uuid, p_qty_ea numeric) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_p public.product%rowtype; v_d public.po_receipt_diff%rowtype; v_new boolean := false;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_r := public.wms_recv_gate(p_receipt_id);
  if v_r.status <> 'draft' then raise exception 'Receipt % is % — off-PO items can be added only while draft — nothing was saved', v_r.receipt_number, v_r.status; end if;
  if p_qty_ea is null or p_qty_ea <= 0 then raise exception 'Off-PO quantity must be more than 0 — nothing was saved'; end if;
  select * into v_p from public.product p where p.id = p_product_id;
  if not found then raise exception 'Product not found — nothing was saved'; end if;
  if exists (select 1 from public.po_line l where l.po_id = v_r.po_id and l.product_id = p_product_id) then
    raise exception 'Product % is on this PO — count it on its line, not as off-PO — nothing was saved', v_p.sku;
  end if;
  select * into v_d from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.kind = 'off_po' and d.product_id = p_product_id and d.resolved_at is null;
  if found then
    update public.po_receipt_diff set received_qty = received_qty + p_qty_ea, updated_by = v_staff where id = v_d.id returning * into v_d;
  else
    insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty, note, updated_by)
    values (p_receipt_id, v_r.po_id, null, p_product_id, 'off_po', 0, p_qty_ea, 'off-PO (WMS receiving) — approval pending', v_staff) returning * into v_d;
    v_new := true;
  end if;
  return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_p.sku, 'product_id', p_product_id, 'kind', 'off_po', 'received_qty', v_d.received_qty, 'added', p_qty_ea, 'created', v_new, 'declared_by', v_staff);
end;
$$;
comment on function public.wms_recv_off_po(uuid, uuid, numeric) is '⑤-3a WMS off-PO(운영 offPoScan · 판정 5 「off-PO → 차이 큐 off_po」 · 모양은 ⑤-6) — 첫 줄 ims_require_write(wms_receiving) · 창고 · draft 만 · PO 에 있는 제품은 거부 · po_receipt_diff(kind off_po · po_line_id null · product_id · expected 0 · received) 한 행 · 같은 제품 다시 = 더한다 · 재고 · 원장 · 레이어 무접촉 · 승인 · 거절 · 투입 · 약식 등록은 ⑤-6 · definer(po_receipt_diff RLS 가 receiving 을 요구)';
revoke all on function public.wms_recv_off_po(uuid, uuid, numeric) from public, anon;
grant execute on function public.wms_recv_off_po(uuid, uuid, numeric) to authenticated;

-- hold · resume — 보류 = wms_task_holds receipt 행(문서 status 는 draft 그대로) · 두 번 hold 는 한 행 · resume 은 서버 시계로 닫는다(0행 = 신규 시작)
create function public.wms_recv_hold(p_receipt_id uuid) returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_h public.wms_task_holds%rowtype; v_new boolean := false;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_r := public.wms_recv_gate(p_receipt_id);
  if v_r.status <> 'draft' then raise exception 'Receipt % is % — only a draft receipt can be held — nothing was saved', v_r.receipt_number, v_r.status; end if;
  select * into v_h from public.wms_task_holds h where h.receipt_id = p_receipt_id and h.resumed_at is null order by h.id limit 1;
  if not found then
    insert into public.wms_task_holds (task_kind, receipt_id, worker, source) values ('receipt', p_receipt_id, v_staff, 'manual') returning * into v_h;
    v_new := true;
  end if;
  return jsonb_build_object('receipt_number', v_r.receipt_number, 'held', true, 'hold_id', v_h.id, 'held_by', v_h.worker, 'held_at', v_h.held_at, 'created', v_new);
end;
$$;
comment on function public.wms_recv_hold(uuid) is '⑤-3a WMS 입고 보류(운영 holdBtn · wms_pause_receipt held) — 첫 줄 ims_require_write(wms_receiving) · 창고 · draft 만 · wms_task_holds(task_kind receipt · receipt_id · worker · manual) 열린 행 하나(이미 열려 있으면 그것을 돌려준다 · created false) · po_receipt.status 는 안 바꾼다 · Partial 은 없다(판정 28)';
revoke all on function public.wms_recv_hold(uuid) from public, anon;
grant execute on function public.wms_recv_hold(uuid) to authenticated;

create function public.wms_recv_resume(p_receipt_id uuid) returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_n int;
begin
  perform public.ims_require_write('wms_receiving', 'closed');  -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_r := public.wms_recv_gate(p_receipt_id);
  update public.wms_task_holds set resumed_at = now(), resumed_by = v_staff where receipt_id = p_receipt_id and resumed_at is null;   -- 서버 시계
  get diagnostics v_n = row_count;
  return jsonb_build_object('receipt_number', v_r.receipt_number, 'closed', v_n, 'resumed_by', v_staff);
end;
$$;
comment on function public.wms_recv_resume(uuid) is '⑤-3a WMS 입고 재개(운영 resumeReceipt + wms_resume_hold receipt) — 첫 줄 ims_require_write(wms_receiving) · 창고 · 열린 보류 행을 서버 시계 · 서버 사람으로 닫는다 · 0행 = 보류가 없었다(신규 열기)';
revoke all on function public.wms_recv_resume(uuid) from public, anon;
grant execute on function public.wms_recv_resume(uuid) to authenticated;

-- overflow — 보관용 칸 켜기/끄기(§20 판정 3 받는 직원)
create function public.wms_recv_overflow_set(p_product_id uuid, p_bin_id uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if not public.ims_can_warehouse((select b.warehouse_id from public.ref_bin b where b.id = p_bin_id)) then
    raise exception 'This bin is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  return public.product_bin_overflow_set_by(v_staff, p_product_id, p_bin_id, p_note);
end;
$$;
revoke all on function public.wms_recv_overflow_set(uuid, uuid, text) from public, anon;
grant execute on function public.wms_recv_overflow_set(uuid, uuid, text) to authenticated;
create function public.wms_recv_overflow_clear(p_product_id uuid, p_bin_id uuid) returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if not public.ims_can_warehouse((select b.warehouse_id from public.ref_bin b where b.id = p_bin_id)) then
    raise exception 'This bin is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  return public.product_bin_overflow_clear_by(v_staff, p_product_id, p_bin_id);
end;
$$;
revoke all on function public.wms_recv_overflow_clear(uuid, uuid) from public, anon;
grant execute on function public.wms_recv_overflow_clear(uuid, uuid) to authenticated;
comment on function public.wms_recv_overflow_set(uuid, uuid, text) is '⑤-3a WMS 보관용 칸 켜기(§20 판정 3 · 받는 직원) — 첫 줄 ims_require_write(wms_receiving) · 창고 · product_bin_overflow_set_by';
comment on function public.wms_recv_overflow_clear(uuid, uuid) is '⑤-3a WMS 보관용 칸 끄기 — 첫 줄 ims_require_write(wms_receiving) · 창고 · product_bin_overflow_clear_by';
