-- ⑤-2a1 WMS 창구 첫째 — SO 짝 · Release · 카탈로그 · 계획 칸 표 · 배치 · 웨이브 (2026-09-26 UTC · 토론토 2026-09-26 오후)
-- 정본 so-module §24 · 지시서 ~/asung/prompts/wms-5-2.md · 판정 회신 wms-5-2-rulings.md(§1 · 판정 19~24 · a1/a2 경계는 첫 회신 ⬜15)
-- 대상: [테스트 · Asung-IMS] 만 — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/wms-5-2a1-verify.sql(-v mig)
-- ⛔⛔ 절대 조건(Caleb 2026-09-26): 운영 WMS(asung-WMS · wms.asung.ca)는 어떤 경우에도 멈추면 안 된다.
--     첫 문장 = 운영 가드(판정 13 · 원본 supabase/ops/guard-test-only.sql 의 글자를 그대로 복사 · 검증 G0 이 임시 파일 diff 로 같음을 잰다).
--     흔적 셋 중 하나라도 있으면 WM501 로 멈춘다(OR · fail-closed): cron.job 에 wms-poll-orders/wms-auto-hold · inv_config.db_role <> 'test' · wms_health_runs 행 > 0
-- 하는 일(§1 순서 · a1 몫):
--   0. 가드
--   1. so 칸 넷 — picking_at · picking_by · packed_at · packed_by(판정 23 · so_wms_status 가 찍는다 · 인덱스 둘 · FK ims_staff restrict)
--   2. so_status_guard 재발행 — 짝 여섯을 더한다(마지막 정의 20260925142307:118 · 원본과 diff · at_wms→cancelled · picking→cancelled 는 없다 · 판정 21)
--   3. 속 창구 so_wms_status(p_so_id, p_to, p_staff) — 창고 길의 상태 전이 한 곳(invoker · authenticated 에서 뺐다 · for update · CAS · 시각·사람 칸 찍기/지우기)
--   4. 오피스 창구 so_release_to_wms(uuid[]) · so_wms_recall(uuid[]) — definer · 첫 줄 ims_require_write(sales) · 창고 길만 · 여러 오더 한 번에(하나라도 막히면 전체 거부)
--   5. ims_perm_catalog 재발행 — wms 방 값 넷(picking · packing · fulfillment = worker 기본 · wms_manage = manager 이상 · 마지막 정의 20260923224900:371 · 원본과 diff)
--      ims_can_view · ims_can_write 재발행(판정 25 · 원본 20260918020000 에 worker 가지 한 줄만): worker 기본 = wms 방 가운데 min_role 이 없거나 worker 이하인 화면 · manager 는 perms ? 화면 그대로(화면마다 켠다 · manager 8 은 perms 에 넣어야 한다)
--   6. wms_pick_line_bins 신설 — 배치 때 so_pick_plan 의 계획 칸(planned=true) · 픽 때 실제 칸(planned=false · ⑤-2a2) · 칸은 ref_bin uuid
--   7. wms_reports_kind_check 에 stock_short(판정 20 · 규칙 41 · 값이 느는 쪽 · 훅이 읽는 drop/add 서식 그대로)
--   8. WMS 창구 — wms_batch_create(p_so_id, p_batches) · wms_wave_create(p_so_ids) — definer · 첫 줄 ims_require_write(wms_manage) · 다음 ims_can_warehouse(오더의 창고) ·
--      at_wms 오더만 · 줄마다 과제 하나에만 · assigned_base = (qty_ordered − qty_removed) × pack_factor · so_pick_plan 의 계획 칸을 wms_pick_line_bins 에 · 마지막에 so_wms_status(picking)
--      속 함수 wms_pick_task_build(둘이 함께 쓴다 · authenticated 에서 뺐다) · 운영이 찍던 칸(created_by · created_at · wave_id · tote_no · batch_label · 판정 24)
-- ⚠️ a2 로 넘긴 것: 픽 완료 · 팩 완료 · 보류 둘 · 재개 · 자동 보류(cron ims-wms-auto-hold 는 a2 때) · ⑤-2b: 치수 칸 · Finalize · wms_so_handoff · so_finalize 재발행 · 되돌리기 · 검토함
-- ⚠️ 번호 시퀀스(so · 인보이스 · 크레딧)는 이 파일이 건드리지 않는다 · 창구를 부르지 않는다

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

-- ═══ 1) so 칸 넷 (판정 23) ═══
alter table public.so
  add column picking_at timestamptz,
  add column picking_by uuid references public.ims_staff (id) on delete restrict,
  add column packed_at  timestamptz,
  add column packed_by  uuid references public.ims_staff (id) on delete restrict;
create index so_picking_by_idx on public.so (picking_by);
create index so_packed_by_idx  on public.so (packed_by);
comment on column public.so.picking_at is '⑤-2a1(판정 23) 창고가 일을 시작한 때 — so_wms_status(picking) 이 찍는다(배치·웨이브 만들기) · picking→at_wms 로 되돌리면 지운다 · 통계는 ② 표(wms_pick_tasks …)에서';
comment on column public.so.picking_by is '⑤-2a1(판정 23) picking 으로 넘긴 사람 → ims_staff(id) · 배치·웨이브를 만든 매니저';
comment on column public.so.packed_at  is '⑤-2a1(판정 23) 포장이 끝난 때 — so_wms_status(packed) 가 찍는다(⑤-2a2 팩 완료) · packed→picking 으로 되돌리면 지운다';
comment on column public.so.packed_by  is '⑤-2a1(판정 23) packed 로 넘긴 사람 → ims_staff(id)';

-- ═══ 2) so_status_guard 재발행 — 짝 여섯(마지막 정의 20260925142307:118~152 · 더한 줄 = 짝 목록 둘째 줄 · 나머지 그대로) ═══
--   confirmed→at_wms(Release) · at_wms→confirmed(거둬들이기) · at_wms→picking(배치·웨이브) · picking→at_wms(창고가 되돌림) · picking→packed(팩 완료) · packed→picking(되돌리기)
--   판정 21: at_wms→cancelled · picking→cancelled 짝 없음 — 취소는 한 단계씩 confirmed 까지 돌아와서
create or replace function public.so_status_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  v_ok boolean := false;
begin
  if tg_op = 'INSERT' then
    if new.status is distinct from 'draft' then
      raise exception 'A new order must start as draft (got %) — nothing was saved', new.status;
    end if;
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;                                   -- status 그대로 — 머리 고치기 · 줄 수 반영 등은 지나간다
  end if;

  -- 허락 짝 목록 — ② 확정·할당(⬜3) 넷 + ③a 출고(2026-09-24 · ⬜5): packed→shipped(so_ship 의 CAS 플립 · warehouse 길)
  --   ⓑ2 2026-09-24: shipped→fulfilled(so_invoice_issue · 판정 1 발행이 곧 끝) · fulfilled→shipped(so_invoice_cancel · 8-h 하향) — ⓐ1 의 shipped→invoiced · invoiced→shipped 를 대신한다
  --   ④ POS·counter(confirmed→shipped) · ⑤ Release to WMS · WMS 사건(at_wms · picking · packed · 내려가는 짝 · 6-g′ ⬜) 이 여기에 더한다
  v_ok := (old.status, new.status) in (('draft','confirmed'), ('confirmed','draft'), ('confirmed','cancelled'), ('draft','cancelled'), ('packed','shipped'),
                                        ('shipped','fulfilled'), ('fulfilled','shipped'),
                                        ('confirmed','at_wms'), ('at_wms','confirmed'), ('at_wms','picking'), ('picking','at_wms'), ('picking','packed'), ('packed','picking'))   -- ⑤-2a1 2026-09-26: WMS 짝 여섯(판정 17 · 21 — at_wms→cancelled · picking→cancelled 없음)
          or (old.status = 'confirmed' and new.status = 'shipped' and new.channel in ('pos', 'counter'));   -- ④a2 2026-09-25: pos·counter 는 confirmed 에서 나간다(7-c · 6-g′ 길별 짝) · warehouse 는 여전히 거부

  if not v_ok then
    raise exception 'Order % cannot move from % to % this way — use the order actions — nothing was saved',
      old.so_number, old.status, new.status;
  end if;
  return new;
end;
$$;
comment on function public.so_status_guard() is
  '⭐ SO 상태 문지기(6-g′ · 12-b 판정 6 · ②a ⬜3 · ③a ⬜5 · ⓑ2 · ④a2 · ⑤-2a1) — insert 는 draft 만 · status 가 바뀌는 update 는 허락 짝에 없으면 거부(소유자·definer 창구도 지난다) · 같은 상태의 update 는 통과. 짝 일곱 + WMS 여섯 + 길별 하나: draft→confirmed · confirmed→draft · confirmed→cancelled · draft→cancelled · packed→shipped(so_ship · warehouse) · shipped→fulfilled(so_invoice_issue) · fulfilled→shipped(so_invoice_cancel) · ⑤ confirmed→at_wms(Release) · at_wms→confirmed(거둬들이기) · at_wms→picking(배치·웨이브) · picking→at_wms(창고가 되돌림) · picking→packed(팩 완료) · packed→picking(되돌리기) — 전부 so_wms_status 가 낸다 · at_wms→cancelled · picking→cancelled 없음(판정 21 한 단계씩) · ⭐ confirmed→shipped 는 channel pos·counter 만(so_ship · 7-c)';

-- ═══ 3) 속 창구 so_wms_status — 창고 길의 상태 전이 한 곳 (판정 17 · 23) ═══
--   p_to 마다 허용되는 「지금」: at_wms ← confirmed(Release · at_wms_at/by 찍음) · picking(창고가 되돌림 · picking_at/by 지움)
--                              confirmed ← at_wms(거둬들이기 · at_wms_at/by 지움) · picking ← at_wms(배치 · picking_at/by 찍음) · packed(되돌리기 · packed_at/by 지움)
--                              packed ← picking(팩 완료 · packed_at/by 찍음)
--   행을 for update 로 잡고 status = 읽은 값 으로 CAS · 창고 길(channel warehouse)만 · 문지기 짝은 트리거가 다시 본다
create function public.so_wms_status(p_so_id uuid, p_to text, p_staff uuid) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare
  v_so   public.so%rowtype;
  v_from text;
  v_n    int;
begin
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel <> 'warehouse' then
    raise exception 'Order % is a % order — only warehouse orders go through the WMS — nothing was saved', v_so.so_number, v_so.channel;
  end if;
  v_from := v_so.status;
  if not ((p_to = 'at_wms'    and v_from in ('confirmed', 'picking'))
       or (p_to = 'confirmed' and v_from = 'at_wms')
       or (p_to = 'picking'   and v_from in ('at_wms', 'packed'))
       or (p_to = 'packed'    and v_from = 'picking')) then
    raise exception 'Order % is % — it cannot move to % from there — nothing was saved', v_so.so_number, v_from, p_to;
  end if;
  update public.so s
     set status     = p_to,
         at_wms_at  = case when p_to = 'at_wms' and v_from = 'confirmed' then now()   when p_to = 'confirmed' then null else s.at_wms_at  end,
         at_wms_by  = case when p_to = 'at_wms' and v_from = 'confirmed' then p_staff when p_to = 'confirmed' then null else s.at_wms_by  end,
         picking_at = case when p_to = 'picking' and v_from = 'at_wms' then now()     when p_to = 'at_wms' and v_from = 'picking' then null else s.picking_at end,
         picking_by = case when p_to = 'picking' and v_from = 'at_wms' then p_staff   when p_to = 'at_wms' and v_from = 'picking' then null else s.picking_by end,
         packed_at  = case when p_to = 'packed' then now()   when p_to = 'picking' and v_from = 'packed' then null else s.packed_at end,
         packed_by  = case when p_to = 'packed' then p_staff when p_to = 'picking' and v_from = 'packed' then null else s.packed_by end
   where s.id = p_so_id and s.status = v_from;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order % changed under you (expected %) — nothing was saved', v_so.so_number, v_from;
  end if;
  return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'from', v_from, 'to', p_to);
end;
$$;
comment on function public.so_wms_status(uuid, text, uuid) is
  '⑤-2a1 속 창구 — 창고 길의 상태 전이 한 곳(판정 17) · confirmed⇄at_wms · at_wms⇄picking · picking⇄packed · 시각·사람 칸(at_wms_at/by · picking_at/by · packed_at/by)을 찍고 되돌릴 때 지운다(판정 23) · for update + CAS · channel warehouse 만 · authenticated 에서 뺐다 — so_release_to_wms · so_wms_recall · wms_batch_create · wms_wave_create · (a2) 팩 완료 · 되돌리기가 부른다';
revoke all on function public.so_wms_status(uuid, text, uuid) from public, anon, authenticated;

-- ═══ 4) 오피스 창구 — Release to WMS · 거둬들이기 (판정 16 · 21 · 여러 오더 한 번에 · 하나라도 막히면 전체 거부 · 오더 번호로) ═══
--   Release: confirmed · 창고 길 · 창고 있음·활성 · 보낼 줄(qty_ordered − qty_removed > 0)마다 열린 allocated 예약 합 = 보낼 수 · 열린 hold/backorder/preorder 없음
--   거둬들이기: at_wms · 픽 과제 없음(있으면 창고가 먼저 되돌린다 — 판정 21 한 단계씩)
create function public.so_release_to_wms(p_so_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_id    uuid;
  v_so    public.so%rowtype;
  v_bad   text;
  v_out   jsonb := '[]'::jsonb;
begin
  perform public.ims_require_write('sales', 'saved');                 -- ⭐ 첫 줄 — Release 는 오더 담당(sales)
  v_staff := public.so_current_staff();
  if p_so_ids is null or cardinality(p_so_ids) = 0 then raise exception 'No orders given — nothing was saved'; end if;
  -- ① 검사 전부
  foreach v_id in array p_so_ids loop
    select * into v_so from public.so s where s.id = v_id;
    if not found then raise exception 'Order not found (%) — nothing was saved', v_id; end if;
    if v_so.channel <> 'warehouse' then
      raise exception 'Order % is a % order — only warehouse orders are released to the WMS — nothing was saved', v_so.so_number, v_so.channel;
    end if;
    if v_so.status <> 'confirmed' then
      raise exception 'Order % is % — only confirmed orders can be released — nothing was saved', v_so.so_number, v_so.status;
    end if;
    if v_so.location_id is null or not exists (select 1 from public.ref_warehouse w where w.id = v_so.location_id and w.is_active) then
      raise exception 'Order % has no active warehouse — nothing was saved', v_so.so_number;
    end if;
    select string_agg(distinct r.kind, ', ') into v_bad
    from public.so_reserve r join public.so_line l on l.id = r.so_line_id
    where l.so_id = v_id and r.released_at is null and r.kind <> 'allocated';
    if v_bad is not null then
      raise exception 'Order % has open % reservations — clear them first — nothing was saved', v_so.so_number, v_bad;
    end if;
    select string_agg(l.line_no::text, ', ' order by l.line_no) into v_bad
    from public.so_line l
    where l.so_id = v_id and (l.qty_ordered - l.qty_removed) > 0
      and coalesce((select sum(r.qty_allocated) from public.so_reserve r where r.so_line_id = l.id and r.kind = 'allocated' and r.released_at is null), 0) <> (l.qty_ordered - l.qty_removed);
    if v_bad is not null then
      raise exception 'Order % is not fully allocated (lines %) — allocate it first — nothing was saved', v_so.so_number, v_bad;
    end if;
    if not exists (select 1 from public.so_line l where l.so_id = v_id and (l.qty_ordered - l.qty_removed) > 0) then
      raise exception 'Order % has nothing left to ship — nothing was saved', v_so.so_number;
    end if;
  end loop;
  -- ② 전이 — 속 창구
  foreach v_id in array p_so_ids loop
    v_out := v_out || public.so_wms_status(v_id, 'at_wms', v_staff);
  end loop;
  return jsonb_build_object('released', v_out, 'count', jsonb_array_length(v_out));
end;
$$;
comment on function public.so_release_to_wms(uuid[]) is
  '⑤-2a1 오피스 창구 Release to WMS(판정 16) — 첫 줄 ims_require_write(sales) · confirmed 창고 오더만 · 보낼 줄마다 열린 allocated 예약 합 = 보낼 수 · 열린 hold/backorder/preorder 없음 · 활성 창고 · 여러 오더 한 번에(하나라도 막히면 전체 거부) · so_wms_status(at_wms) 가 at_wms_at/by 를 찍는다';
revoke all on function public.so_release_to_wms(uuid[]) from public, anon;
grant execute on function public.so_release_to_wms(uuid[]) to authenticated;

create function public.so_wms_recall(p_so_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_id    uuid;
  v_so    public.so%rowtype;
  v_out   jsonb := '[]'::jsonb;
begin
  perform public.ims_require_write('sales', 'saved');                 -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  if p_so_ids is null or cardinality(p_so_ids) = 0 then raise exception 'No orders given — nothing was saved'; end if;
  foreach v_id in array p_so_ids loop
    select * into v_so from public.so s where s.id = v_id;
    if not found then raise exception 'Order not found (%) — nothing was saved', v_id; end if;
    if v_so.status <> 'at_wms' then
      raise exception 'Order % is % — only orders released to the WMS (and not yet in work) can be recalled — nothing was saved', v_so.so_number, v_so.status;
    end if;
    if exists (select 1 from public.wms_pick_tasks t where t.order_id = v_id) then
      raise exception 'Order % already has pick tasks — the warehouse must send it back first — nothing was saved', v_so.so_number;
    end if;
  end loop;
  foreach v_id in array p_so_ids loop
    v_out := v_out || public.so_wms_status(v_id, 'confirmed', v_staff);
  end loop;
  return jsonb_build_object('recalled', v_out, 'count', jsonb_array_length(v_out));
end;
$$;
comment on function public.so_wms_recall(uuid[]) is
  '⑤-2a1 오피스 창구 거둬들이기(판정 21 한 단계씩) — 첫 줄 ims_require_write(sales) · at_wms 이고 픽 과제가 없는 오더만 → confirmed(at_wms_at/by 지움) · 창고가 일을 시작했으면(picking) 창고가 먼저 at_wms 로 되돌린다 · 취소는 confirmed 에서';
revoke all on function public.so_wms_recall(uuid[]) from public, anon;
grant execute on function public.so_wms_recall(uuid[]) to authenticated;

-- ═══ 5) ims_perm_catalog 재발행 — wms 방 값 넷 (마지막 정의 20260923224900:371~386 · 더한 줄 = wms 넷 · sales 줄 끝에 쉼표 · 나머지 그대로) ═══
--   picking · packing · fulfillment = worker 기본(wms 방 · min_role 없음) · wms_manage = min_role manager(worker 에게 false · manager 는 perms 에 켜야 한다 · 판정 25)
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
      "wms_manage":  {"room": "wms", "min_role": "manager", "label": "Warehouse management — batches, waves, rollbacks (manager and above)"}
    }
  }'::jsonb;
$$;

-- ims_can_view · ims_can_write 재발행(마지막 정의 20260918020000:79~116 · 판정 25 · 원본 바이트에 worker 가지 한 줄만 더한다 · 나머지 그대로)
--   worker: room wms 이고 그 화면에 min_role 이 없거나 worker 이하일 때만 true — wms_manage(min_role manager)는 worker 에게 false
--   manager: 원래대로 perms ? 화면(화면마다 켠다 · staff.html 라디오 · 운영의 사람별 Split 권한과 같은 모양) · admin·supervisor 가지는 그대로
--   뜻: worker 기본 = WMS 방 화면 가운데 「manager 이상」 표시가 없는 것 전부 — 나중의 WMS 입고·풋어웨이·트랜스퍼·bin transfer 도 WMS 방 값이면 worker 기본
-- ═══ 3) ims_can_view / ims_can_write — 'staff' 특례 제거 (그 외 무변 · 20260917230000 원문 기준) ═══
create or replace function public.ims_can_view(p_screen text) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when not (public.ims_perm_catalog()->'screens' ? p_screen) then false        -- 모르는 화면 = false (admin 도)
      when s.role in ('admin', 'supervisor') then true                             -- supervisor = almost everything (staff 포함 · 2026-09-17 1-b)
      when s.role = 'worker'
           and coalesce(public.ims_role_rank(coalesce(public.ims_perm_catalog()->'screens'->p_screen->>'min_role', 'worker')), 99) <= public.ims_role_rank('worker')   -- ⑤-2a1 판정 25: min_role 이 없거나 worker 이하인 화면만
           and public.ims_perm_catalog()->'screens'->p_screen->>'room' = 'wms' then true   -- 창고 사람은 wms 방 화면이 기본
      else s.perms ? p_screen or s.perms ? (p_screen || ':read')                   -- manager · worker(ims 방) = perms
    end
    from public.ims_staff s
    where s.auth_user_id = auth.uid() and s.is_active
  ), false);
$$;
comment on function public.ims_can_view(text) is
  '호출자가 화면을 볼 수 있는가(:read 포함). admin·supervisor 전부 · worker 는 wms 방 화면 기본(⑤-2a1 판정 25: 카탈로그 min_role 이 없거나 worker 이하인 화면만 — wms_manage 는 아니다) · 그 외 perms(manager 는 화면마다 켠다). staff 도 같은 규칙(2026-09-17 1-b). 모르는 값·비활성·행 없음 = false';

create or replace function public.ims_can_write(p_screen text) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when not (public.ims_perm_catalog()->'screens' ? p_screen) then false
      when s.role in ('admin', 'supervisor') then true                             -- staff 도 포함 — 누구를 다룰 수 있나는 ims_can_manage 가 따로 본다
      when s.role = 'worker'
           and coalesce(public.ims_role_rank(coalesce(public.ims_perm_catalog()->'screens'->p_screen->>'min_role', 'worker')), 99) <= public.ims_role_rank('worker')   -- ⑤-2a1 판정 25: min_role 이 없거나 worker 이하인 화면만
           and public.ims_perm_catalog()->'screens'->p_screen->>'room' = 'wms' then true
      else s.perms ? p_screen                                                       -- ':read' 는 세지 않는다
    end
    from public.ims_staff s
    where s.auth_user_id = auth.uid() and s.is_active
  ), false);
$$;
comment on function public.ims_can_write(text) is
  '호출자가 화면에서 저장할 수 있는가. :read 만 가진 화면은 false. staff 는 다른 값과 같다(admin 전용 아님 · 2026-09-17 1-b) — 누구를 다룰 수 있나는 ims_can_manage. ② RLS with check · ims_require_write 가 이 함수를 쓴다';

-- ═══ 6) wms_pick_line_bins — 픽 줄의 칸 행 (첫 회신 ⬜ · 배치 때 계획 칸 · 픽 때 실제 칸) ═══
create table public.wms_pick_line_bins (
  id                bigint generated always as identity primary key,
  pick_task_line_id bigint not null references public.wms_pick_task_lines (id) on delete cascade,
  bin_id            uuid not null references public.ref_bin (id) on delete restrict,
  bin               text not null,
  qty_base          numeric not null,
  planned           boolean not null default false,
  picked_by         uuid references public.ims_staff (id) on delete restrict,
  picked_at         timestamptz,
  created_at        timestamptz not null default now(),
  constraint wms_pick_line_bins_qty_ck check (qty_base > 0),
  constraint wms_pick_line_bins_actual_ck check (planned or (picked_by is not null and picked_at is not null))
);
create index idx_pick_line_bins_line on public.wms_pick_line_bins (pick_task_line_id);
create index idx_pick_line_bins_bin  on public.wms_pick_line_bins (bin_id);
create index idx_pick_line_bins_picked_by on public.wms_pick_line_bins (picked_by);
alter table public.wms_pick_line_bins enable row level security;
create policy auth_all on public.wms_pick_line_bins for all to authenticated using (true) with check (true);
comment on table public.wms_pick_line_bins is
  '⑤-2a1 픽 줄의 칸 행 — planned=true 는 배치·웨이브 때 so_pick_plan 의 계획 칸(그 줄의 합 = assigned_base · 칸 이름이 빈 몫은 행 없음 + warnings) · planned=false 는 픽 완료 때 실제 칸(⑤-2a2 · 합 = picked_base · picked_by/at 필수) · 칸은 ref_bin uuid(bin 이름은 그때의 기록) · so_finalize 의 picks 는 실제 칸 행에서(⑤-2b wms_so_handoff)';

-- ═══ 7) wms_reports.kind CHECK — 5 값 (판정 20 · stock_short 더함 · 규칙 41 · scripts/check-class-values.sh 가 읽는 drop/add 서식) ═══
alter table public.wms_reports
  drop constraint if exists wms_reports_kind_check;
alter table public.wms_reports
  add constraint wms_reports_kind_check check (kind in (
    'wrong_location',    -- picker 전용
    'barcode_mismatch',  -- picker + packer + receiver
    'image_mismatch',    -- picker + packer + receiver (토글)
    'box_barcode',       -- receiver 전용
    'stock_short'        -- picker 「Not enough stock」(⑤-2a1 · 판정 20 · 알림 · 실수 집계 밖)
  ));

-- ═══ 8) WMS 창구 — 배치 만들기 · 웨이브 만들기 (운영 manager.html 527~548 Split · 720~760 wave 의 자리 · at_wms → picking) ═══
--   속 함수 wms_pick_task_build — 과제 하나 + 줄 + 계획 칸 행(so_pick_plan 의 picks · qty 는 판매 단위 → × pack_factor · 칸 이름 → ref_bin(창고, 이름) · '' 는 행 없음 + warning)
--   운영이 찍던 칸(판정 24): wms_pick_tasks.order_id · batch_label · status pending · created_by · created_at · wave_id · tote_no / wms_pick_task_lines.order_line_id · assigned_base · status pending · created_at
create function public.wms_pick_task_build(p_so_id uuid, p_label text, p_line_ids uuid[], p_wave_id bigint, p_tote_no int, p_staff uuid, p_plan jsonb) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare
  v_so      public.so%rowtype;
  v_task    bigint;
  v_line    bigint;
  l         record;
  p         jsonb;
  v_bin     uuid;
  v_lines   int := 0;
  v_rows    int := 0;
  v_warn    text[] := '{}';
begin
  select * into v_so from public.so s where s.id = p_so_id;
  insert into public.wms_pick_tasks (order_id, batch_label, status, created_by, created_at, wave_id, tote_no)
  values (p_so_id, p_label, 'pending', p_staff, now(), p_wave_id, p_tote_no)
  returning id into v_task;
  for l in
    select x.id, x.line_no, x.pack_factor, (x.qty_ordered - x.qty_removed) * x.pack_factor as need_ea
    from public.so_line x where x.so_id = p_so_id and x.id = any (p_line_ids) order by x.line_no
  loop
    insert into public.wms_pick_task_lines (pick_task_id, order_line_id, assigned_base, status, created_at)
    values (v_task, l.id, l.need_ea, 'pending', now())
    returning id into v_line;
    v_lines := v_lines + 1;
    for p in select * from jsonb_array_elements(coalesce(p_plan->'picks', '[]'::jsonb)) loop
      if (p->>'line_id')::uuid <> l.id then continue; end if;
      if coalesce(p->>'bin', '') = '' then
        v_warn := array_append(v_warn, format('no_bin:%s:%s', v_so.so_number, l.line_no));
        continue;
      end if;
      select b.id into v_bin from public.ref_bin b where b.warehouse_id = v_so.location_id and b.name = p->>'bin';
      if v_bin is null then
        v_warn := array_append(v_warn, format('bin_unknown:%s:%s:%s', v_so.so_number, l.line_no, p->>'bin'));
        continue;
      end if;
      insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned)
      values (v_line, v_bin, p->>'bin', (p->>'qty')::numeric * l.pack_factor, true);
      v_rows := v_rows + 1;
    end loop;
  end loop;
  return jsonb_build_object('task_id', v_task, 'batch_label', p_label, 'wave_id', p_wave_id, 'tote_no', p_tote_no, 'lines', v_lines, 'planned_rows', v_rows, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.wms_pick_task_build(uuid, text, uuid[], bigint, int, uuid, jsonb) is
  '⑤-2a1 속 함수 — 픽 과제 하나(wms_pick_tasks) + 줄(assigned_base = (qty_ordered − qty_removed) × pack_factor) + 계획 칸 행(wms_pick_line_bins planned=true · so_pick_plan 의 picks · 칸 이름 → ref_bin(창고, 이름) · 빈 이름은 행 없음 + no_bin 경고) · 검사·권한·상태 전이는 부르는 창구(wms_batch_create · wms_wave_create)가 · authenticated 에서 뺐다';
revoke all on function public.wms_pick_task_build(uuid, text, uuid[], bigint, int, uuid, jsonb) from public, anon, authenticated;

-- 배치 만들기 — p_batches = [{"line_ids": [so_line.id, …]}, …] · 보낼 줄(qty_ordered − qty_removed > 0)마다 정확히 한 배치에 · 라벨 <so_number>-<n>
create function public.wms_batch_create(p_so_id uuid, p_batches jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  v_wh     text;
  v_plan   jsonb;
  v_ids    uuid[] := '{}';
  v_batch  uuid[];
  v_bad    text;
  v_n      int;
  i        int;
  b        jsonb;
  v_tasks  jsonb := '[]'::jsonb;
  v_t      jsonb;
  v_warn   jsonb := '[]'::jsonb;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄 — 카탈로그 wms_manage = manager 이상(min_role)
  v_staff := public.so_current_staff();
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_so.location_id;
  if not public.ims_can_warehouse(v_so.location_id) then              -- ⭐ 둘째 — 창고 제한 첫 실물
    raise exception 'Order % is at % — you are not set up for that warehouse — nothing was saved', v_so.so_number, coalesce(v_wh, '<none>');
  end if;
  if v_so.status <> 'at_wms' then
    raise exception 'Order % is % — only orders released to the WMS can be batched — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if exists (select 1 from public.wms_pick_tasks t where t.order_id = p_so_id) then
    raise exception 'Order % already has pick tasks — nothing was saved', v_so.so_number;
  end if;
  if p_batches is null or jsonb_typeof(p_batches) <> 'array' or jsonb_array_length(p_batches) = 0 then
    raise exception 'Order % — no batches given — nothing was saved', v_so.so_number;
  end if;
  -- 줄 검사: 모르는 줄 · 두 번 든 줄 · 빠진 보낼 줄 · 다 뺀 줄
  for b in select * from jsonb_array_elements(p_batches) loop
    if jsonb_typeof(b->'line_ids') <> 'array' or jsonb_array_length(b->'line_ids') = 0 then
      raise exception 'Order % — a batch has no lines — nothing was saved', v_so.so_number;
    end if;
    select array_agg((e.v)::uuid) into v_batch from jsonb_array_elements_text(b->'line_ids') e(v);
    v_ids := v_ids || v_batch;
  end loop;
  select string_agg(u.id::text, ', ') into v_bad from unnest(v_ids) u(id) where not exists (select 1 from public.so_line l where l.id = u.id and l.so_id = p_so_id);
  if v_bad is not null then raise exception 'Order % — lines not on this order (%) — nothing was saved', v_so.so_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ') into v_bad from (select u.id from unnest(v_ids) u(id) group by u.id having count(*) > 1) d join public.so_line l on l.id = d.id;
  if v_bad is not null then raise exception 'Order % — lines in more than one batch (%) — nothing was saved', v_so.so_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ' order by l.line_no) into v_bad from public.so_line l where l.so_id = p_so_id and (l.qty_ordered - l.qty_removed) > 0 and not (l.id = any (v_ids));
  if v_bad is not null then raise exception 'Order % — lines left out of the batches (%) — nothing was saved', v_so.so_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ' order by l.line_no) into v_bad from public.so_line l where l.so_id = p_so_id and (l.qty_ordered - l.qty_removed) <= 0 and l.id = any (v_ids);
  if v_bad is not null then raise exception 'Order % — lines with nothing to ship (%) cannot be batched — nothing was saved', v_so.so_number, v_bad; end if;
  -- 계획 칸 · 과제
  v_plan := public.so_pick_plan(p_so_id);
  i := 0;
  for b in select * from jsonb_array_elements(p_batches) loop
    i := i + 1;
    select array_agg((e.v)::uuid) into v_batch from jsonb_array_elements_text(b->'line_ids') e(v);
    v_t := public.wms_pick_task_build(p_so_id, v_so.so_number || '-' || i, v_batch, null, null, v_staff, v_plan);
    v_tasks := v_tasks || v_t;
    v_warn := v_warn || (v_t->'warnings');
  end loop;
  perform public.so_wms_status(p_so_id, 'picking', v_staff);
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'status', 'picking', 'tasks', v_tasks,
                            'short_ea_total', v_plan->'short_ea_total', 'warnings', (v_plan->'warnings') || v_warn);
end;
$$;
comment on function public.wms_batch_create(uuid, jsonb) is
  '⑤-2a1 WMS 창구 배치 만들기(운영 manager.html Split 의 자리) — 첫 줄 ims_require_write(wms_manage) · 둘째 ims_can_warehouse(오더의 창고) · at_wms 오더 · 픽 과제 없음 · p_batches [{line_ids}] 는 보낼 줄마다 정확히 한 배치 · 라벨 <so_number>-<n> · so_pick_plan 의 계획 칸을 wms_pick_line_bins 에 · 마지막에 so_wms_status(picking · picking_at/by) · 빈 선반도 막지 않는다(warnings)';
revoke all on function public.wms_batch_create(uuid, jsonb) from public, anon;
grant execute on function public.wms_batch_create(uuid, jsonb) to authenticated;

-- 웨이브 만들기 — 오더 여럿(같은 창고) · wms_waves 한 행(라벨 W-MMDD-n · 토론토 날짜 · 그날 최대 n + 1) · 오더마다 과제 하나(<so_number>-1 · 모든 보낼 줄 · wave_id · tote_no 순번)
create function public.wms_wave_create(p_so_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_id     uuid;
  v_so     public.so%rowtype;
  v_wh_id  uuid;
  v_wh     text;
  v_wave   bigint;
  v_label  text;
  v_md     text;
  v_n      int;
  v_plan   jsonb;
  v_ids    uuid[];
  i        int := 0;
  v_tasks  jsonb := '[]'::jsonb;
  v_t      jsonb;
  v_warn   jsonb := '[]'::jsonb;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  if p_so_ids is null or cardinality(p_so_ids) = 0 then raise exception 'No orders given — nothing was saved'; end if;
  if (select count(distinct u.id) from unnest(p_so_ids) u(id)) <> cardinality(p_so_ids) then raise exception 'An order is listed twice — nothing was saved'; end if;
  -- ① 검사 전부(잠근다)
  foreach v_id in array p_so_ids loop
    select * into v_so from public.so s where s.id = v_id for update;
    if not found then raise exception 'Order not found (%) — nothing was saved', v_id; end if;
    select w.name into v_wh from public.ref_warehouse w where w.id = v_so.location_id;
    if not public.ims_can_warehouse(v_so.location_id) then            -- ⭐ 둘째
      raise exception 'Order % is at % — you are not set up for that warehouse — nothing was saved', v_so.so_number, coalesce(v_wh, '<none>');
    end if;
    if v_so.status <> 'at_wms' then
      raise exception 'Order % is % — only orders released to the WMS can go in a wave — nothing was saved', v_so.so_number, v_so.status;
    end if;
    if exists (select 1 from public.wms_pick_tasks t where t.order_id = v_id) then
      raise exception 'Order % already has pick tasks — nothing was saved', v_so.so_number;
    end if;
    if not exists (select 1 from public.so_line l where l.so_id = v_id and (l.qty_ordered - l.qty_removed) > 0) then
      raise exception 'Order % has nothing left to ship — nothing was saved', v_so.so_number;
    end if;
    if v_wh_id is null then v_wh_id := v_so.location_id;
    elsif v_wh_id <> v_so.location_id then
      raise exception 'Order % is at % — a wave takes one warehouse only — nothing was saved', v_so.so_number, coalesce(v_wh, '<none>');
    end if;
  end loop;
  -- ② 웨이브 행
  v_md := to_char(public.ims_today(), 'MMDD');
  select coalesce(max(substring(w.label from '^W-' || v_md || '-([0-9]+)$')::int), 0) + 1 into v_n from public.wms_waves w where w.label like 'W-' || v_md || '-%';
  v_label := format('W-%s-%s', v_md, v_n);
  insert into public.wms_waves (label, warehouse_id, status, created_by, created_at)
  values (v_label, v_wh_id, 'pending', v_staff, now())
  returning id into v_wave;
  -- ③ 오더마다 과제 하나 → picking
  foreach v_id in array p_so_ids loop
    i := i + 1;
    select * into v_so from public.so s where s.id = v_id;
    select array_agg(l.id) into v_ids from public.so_line l where l.so_id = v_id and (l.qty_ordered - l.qty_removed) > 0;
    v_plan := public.so_pick_plan(v_id);
    v_t := public.wms_pick_task_build(v_id, v_so.so_number || '-1', v_ids, v_wave, i, v_staff, v_plan);
    v_tasks := v_tasks || (v_t || jsonb_build_object('so_id', v_id, 'so_number', v_so.so_number, 'short_ea_total', v_plan->'short_ea_total'));
    v_warn := v_warn || (v_plan->'warnings') || (v_t->'warnings');
    perform public.so_wms_status(v_id, 'picking', v_staff);
  end loop;
  return jsonb_build_object('wave_id', v_wave, 'label', v_label, 'warehouse_id', v_wh_id, 'orders', i, 'tasks', v_tasks, 'warnings', v_warn);
end;
$$;
comment on function public.wms_wave_create(uuid[]) is
  '⑤-2a1 WMS 창구 웨이브 만들기(운영 manager.html printWaveAll 의 자리) — 첫 줄 ims_require_write(wms_manage) · 오더마다 ims_can_warehouse · at_wms · 픽 과제 없음 · 한 창고 · wms_waves 라벨 W-MMDD-n(토론토 날짜 · 그날 최대 n + 1) · 오더마다 과제 <so_number>-1(모든 보낼 줄 · wave_id · tote_no 순번) + 계획 칸 · 오더마다 so_wms_status(picking)';
revoke all on function public.wms_wave_create(uuid[]) from public, anon;
grant execute on function public.wms_wave_create(uuid[]) to authenticated;
