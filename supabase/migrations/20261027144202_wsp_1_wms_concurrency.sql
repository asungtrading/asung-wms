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
-- 20261027144202_wsp_1_wms_concurrency.sql — wsp-1 IMS WMS 동시 작업 작은 구멍 넷(a · b · c · d) (2026-10-27 · 회사 · Caleb 지시서 ~/asung/prompts/wsp-1.md)
--   계기   운영 WMS(wms.asung.ca) 2026-10-26 — 매니저 둘이 같은 오더를 동시에 Split 해 픽 배치가 두 벌(운영 manager.html 이 표에 직접 insert · 상태 확인 · CAS 없음)
--          wsp-0 조사: IMS 의 Split(wms_batch_create)은 so · inv_transfer for update → 잠근 뒤 재확인 → so_wms_status CAS 로 두 번째를 거부한다(두 벌 없음) · 남은 구멍 넷을 Caleb 「고치자」
--   a      wms_pick_tasks 보통 유니크 둘 (order_id, batch_label) · (transfer_id, batch_label) — 창구 밖 직접 insert(정책 auth_all · authenticated INSERT)도 DB 가 막는다
--          부분 유니크 금지(asung-wms 규칙 29) · null 은 서로 다르다 → 판매 과제(transfer_id null)와 트랜스퍼 과제(order_id null)는 서로 안 걸린다 · 이름은 uq_packtasks_pick 꼴
--   b      wms_rollback_batch — 잠근 뒤 그 과제를 다시 본다: 팩은 아직 있는가 · 픽은 아직 있는가 + 되돌릴 픽이 있는가(화면 Reset Pick 단추 조건 = in_progress · completed · picked_base > 0)
--   c      so_release_to_wms · tf_release — 검사 select 에 for update + 검사 앞 id 순 잠금 한 문장(검사 ~ so_wms_status/tf_wms_status 잠금 사이 창 · 그 창에 Release → Split 이 끼면 picking → at_wms 가 허락되던 것)
--   d      wms_wave_create — ⓐ 라벨 셈 앞 pg_advisory_xact_lock(hashtext('wms_wave_label:' || MMDD)) ⓑ 검사 앞 id 순 잠금(판매 → 트랜스퍼) · 토트 번호 = p_so_ids 순 그대로(돌기 순서는 안 바꾼다)
--          남는 날것 23505 · 40P01 을 문장으로 바꾸지 않는다 — 23505 는 이제 창구 밖 insert 에서만 난다(창구 사용자는 못 본다) · 40P01 은 Unwave(웨이브 → so) 와 Undo split(so → 웨이브) 의 순서 차이에서만 남고 Postgres 가 한쪽을 끊어 저장 0 · 화면은 오류를 토스트하고 목록을 다시 읽는다
--   바탕   재발행 넷 = 마지막 정의 본문 바이트 그대로 + 위 줄만: so_release_to_wms(20261005201634 · md5 76cd1ae0…) · tf_release · wms_wave_create · wms_rollback_batch(20260928234815 · md5 da8cf01e… · 9c334956… · acf37648…)
--          create or replace 라 grant · revoke · comment · security definer 가 그대로 남는다(시그니처 무변) · 새 함수 없음 · 새 표 없음(컷오버 지우는 순서 무변)
--   무접촉 화면(창구 거부 문장은 기존 토스트가 그대로 보인다) · wms_batch_create · wms_rollback · wms_unwave · so_wms_status · tf_wms_status · 운영 WMS
do $$
declare v_bad text := '';  v_n bigint;
begin
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_release_to_wms')  is distinct from '76cd1ae0a23493f9dc8420543dc681ad' then v_bad := v_bad || ' so_release_to_wms_not_asm_2b1'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'tf_release')         is distinct from 'da8cf01ee8d1284c53546b2cc4a29945' then v_bad := v_bad || ' tf_release_not_tr_1b2'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_wave_create')    is distinct from '9c33495656d2b6f9734f0d6177b75e82' then v_bad := v_bad || ' wms_wave_create_not_tr_1b2'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_rollback_batch') is distinct from 'acf37648cdac600b9378d2e9d81fe598' then v_bad := v_bad || ' wms_rollback_batch_not_tr_1b2'; end if;
  if to_regclass('public.uq_picktasks_order_label') is not null or to_regclass('public.uq_picktasks_transfer_label') is not null then v_bad := v_bad || ' unique_already_there'; end if;
  select count(*) into v_n from (select 1 from public.wms_pick_tasks where order_id is not null group by order_id, batch_label having count(*) > 1) d;
  if v_n > 0 then v_bad := v_bad || format(' duplicate_order_labels_%s', v_n); end if;
  select count(*) into v_n from (select 1 from public.wms_pick_tasks where transfer_id is not null group by transfer_id, batch_label having count(*) > 1) d;
  if v_n > 0 then v_bad := v_bad || format(' duplicate_transfer_labels_%s', v_n); end if;
  if v_bad <> '' then raise exception using errcode = 'WM503', message = format('STOP - wsp-1 needs%s - nothing was changed', v_bad); end if;
end $$;

-- ═══ a) 유니크 둘 ═══
create unique index uq_picktasks_order_label    on public.wms_pick_tasks (order_id, batch_label);
create unique index uq_picktasks_transfer_label on public.wms_pick_tasks (transfer_id, batch_label);

-- ═══ b) wms_rollback_batch ═══
create or replace function public.wms_rollback_batch(p_task_id bigint, p_kind text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_pack constant text[] := array['short_after_pack', 'over_pick', 'pack_scan_mistake'];
  v_staff uuid;  v_doc public.wms_order_doc%rowtype;  v_label text;  v_orig uuid;  v_so_id uuid;
  v_arch int := 0;  v_void int := 0;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');
  v_staff := public.so_current_staff();
  if p_kind not in ('pack', 'pick') then raise exception 'Unknown batch rollback kind % — nothing was saved', p_kind; end if;
  if p_kind = 'pack' then select coalesce(k.order_id, k.transfer_id), k.batch_label, k.assigned_to into v_so_id, v_label, v_orig from public.wms_pack_tasks k where k.id = p_task_id;
  else select coalesce(t.order_id, t.transfer_id), t.batch_label, t.assigned_to into v_so_id, v_label, v_orig from public.wms_pick_tasks t where t.id = p_task_id; end if;
  if v_so_id is null then raise exception 'Task not found — nothing was saved'; end if;
  perform 1 from public.so s where s.id = v_so_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
  perform 1 from public.inv_transfer x where x.id = v_so_id for update;             -- tr-1b2: 트랜스퍼 행 잠금(판정 72-3 의 짝 · 문서 id 는 둘 중 하나에만 맞는다)
  select * into v_doc from public.wms_order_doc d where d.doc_id = v_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not public.ims_can_warehouse(v_doc.warehouse_id) then              -- ⭐ 둘째
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_doc.doc_number;
  end if;
  if v_doc.status = 'packed' or exists (select 1 from public.wms_order_finalize f where coalesce(f.order_id, f.transfer_id) = v_so_id) then
    raise exception 'Order % is finalized — use Undo Finalize first — nothing was saved', v_doc.doc_number;
  end if;
  -- wsp-1 b: 잠근 뒤 다시 본다 — 먼저 끝난 같은 되돌리기(또는 Undo split)가 있으면 거부(0 행 삭제 · 기록 한 줄 더 를 막는다)
  if p_kind = 'pack' and not exists (select 1 from public.wms_pack_tasks k where k.id = p_task_id) then
    raise exception 'Batch % has no packing to undo — it was already undone — nothing was saved', v_label;
  end if;
  if p_kind = 'pick' and not exists (select 1 from public.wms_pick_tasks t where t.id = p_task_id) then
    raise exception 'Batch % is gone — the order was already sent back — nothing was saved', v_label;
  end if;
  if p_kind = 'pick' and not exists (select 1 from public.wms_pick_tasks t where t.id = p_task_id
                                       and (t.status in ('in_progress', 'completed')
                                            or exists (select 1 from public.wms_pick_task_lines pl where pl.pick_task_id = t.id and pl.picked_base > 0))) then   -- 화면의 Reset Pick 단추 조건과 같다(wa batchRows)
    raise exception 'Batch % has no picking to reset — it was already reset — nothing was saved', v_label;
  end if;
  if p_kind = 'pack' then
    if exists (select 1 from public.wms_pallet_items i where i.pack_task_id = p_task_id) then raise exception 'Batch % is on a pallet — Undo Fulfillment first — nothing was saved', v_label; end if;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', v_so_id, v_doc.doc_number, v_label, 'wms_pack_tasks', format('id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', v_so_id, v_doc.doc_number, v_label, 'wms_pack_task_lines', format('pack_task_id = %L', p_task_id));
    v_void := public.wms_rb_void(v_staff, 'pack_task_id', array[p_task_id], c_pack, 'pack rollback ' || v_label);
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', v_so_id, v_doc.doc_number, v_label, 'wms_pick_line_bins', format('pack_task_id = %L', p_task_id));   -- 판정 57: 이 팩의 회복 칸 행
    delete from public.wms_pick_line_bins where pack_task_id = p_task_id;
    delete from public.wms_pack_tasks where id = p_task_id;             -- 배치 단위는 회복을 재개하지 않는다(규칙 14 · 남은 팩이 있다)
  else
    if exists (select 1 from public.wms_pack_tasks k where k.pick_task_id = p_task_id) then raise exception 'Batch % already has packing — Undo Pack first — nothing was saved', v_label; end if;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_doc.doc_number, v_label, 'wms_pick_tasks', format('id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_doc.doc_number, v_label, 'wms_pick_task_lines', format('pick_task_id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_doc.doc_number, v_label, 'wms_pick_line_bins', format('not planned and pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = %L)', p_task_id));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', array[p_task_id], array['short_pick'], 'pick reset ' || v_label);
    delete from public.wms_pick_line_bins b where not b.planned and b.pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = p_task_id);
    update public.wms_pick_task_lines set picked_base = 0, status = 'pending', verification_method = null, picked_at = null, picked_by = null where pick_task_id = p_task_id;
    update public.wms_pick_tasks set status = 'pending', assigned_to = null, started_at = null, completed_at = null, completed_by = null, heartbeat_at = null, work_started = false, held_by = null, session_id = null where id = p_task_id;
  end if;
  insert into public.wms_rollback_log (order_id, transfer_id, order_number, action, from_stage, to_stage, performed_by, batch_label, original_worker)
  values (case when v_doc.doc_kind = 'so' then v_so_id end, case when v_doc.doc_kind = 'transfer' then v_so_id end, v_doc.doc_number, p_kind, case p_kind when 'pack' then 'pack_complete' else 'pick_complete' end, case p_kind when 'pack' then 'pick_complete' else 'pick_reset' end, v_staff, v_label, v_orig);
  return jsonb_build_object('so_id', v_so_id, 'so_number', v_doc.doc_number, 'batch_label', v_label, 'kind', p_kind, 'archived', v_arch, 'voided', v_void);
end;
$$;

-- ═══ c) so_release_to_wms · tf_release ═══
create or replace function public.so_release_to_wms(p_so_ids uuid[]) returns jsonb
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
  perform 1 from public.so s where s.id = any (p_so_ids) order by s.id for update;    -- wsp-1 c: 검사 전에 잠근다 · id 순(동시 Release 둘이 엇갈려 교착하지 않게)
  -- ① 검사 전부
  foreach v_id in array p_so_ids loop
    select * into v_so from public.so s where s.id = v_id for update;            -- wsp-1 c: 검사 select 가 잠근 행을 읽는다(검사 ~ so_wms_status 사이 창 닫기)
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
      and not exists (select 1 from public.so_line k where k.combo_line_id = l.id)                                                   -- asm-2b1(판정 244): 콤보 줄은 예약이 없다 — 구성품 줄이 할당을 든다
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

create or replace function public.tf_release(p_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_id uuid;  v_x public.inv_transfer%rowtype;  v_out jsonb := '[]'::jsonb;
begin
  perform public.ims_require_write('transfer', 'saved');              -- ⭐ 첫 줄 — 보내기는 문서 담당(transfer 열쇠 · 판매 Release 의 sales 와 같은 결)
  v_staff := public.so_current_staff();
  if p_ids is null or cardinality(p_ids) = 0 then raise exception 'No transfers given — nothing was saved'; end if;
  if (select count(distinct u.id) from unnest(p_ids) u(id)) <> cardinality(p_ids) then raise exception 'A transfer is listed twice — nothing was saved'; end if;
  perform 1 from public.inv_transfer x where x.id = any (p_ids) order by x.id for update;   -- wsp-1 c: 검사 전에 잠근다 · id 순
  -- ① 검사 전부
  foreach v_id in array p_ids loop
    select * into v_x from public.inv_transfer x where x.id = v_id for update;   -- wsp-1 c: 검사 select 가 잠근 행을 읽는다
    if not found then raise exception 'Transfer not found (%) — nothing was saved', v_id; end if;
    if not public.ims_can_warehouse(v_x.from_warehouse_id) then       -- 보내기 = 출발 창고(묶음 9)
      raise exception 'Transfer % leaves from a warehouse you are not set up for — nothing was saved', v_x.transfer_number;
    end if;
    if v_x.status <> 'confirmed' then
      raise exception 'Transfer % is % — only a confirmed transfer can be released to the warehouse — nothing was saved', v_x.transfer_number, v_x.status;
    end if;
    if not exists (select 1 from public.ref_warehouse w where w.id = v_x.from_warehouse_id and w.is_active) then
      raise exception 'Transfer % — its from warehouse is not active — nothing was saved', v_x.transfer_number;
    end if;
    if not exists (select 1 from public.inv_transfer_line l where l.transfer_id = v_id and l.qty > 0) then
      raise exception 'Transfer % has nothing to send — nothing was saved', v_x.transfer_number;
    end if;
  end loop;
  -- ② 전이 — 속 창구(가용은 확정이 잡았다 · 묶음 2 · 창고 부족은 계획의 stock_short 가 말한다)
  foreach v_id in array p_ids loop
    v_out := v_out || public.tf_wms_status(v_id, 'at_wms', v_staff);
  end loop;
  return jsonb_build_object('released', v_out, 'count', jsonb_array_length(v_out));
end;
$$;

-- ═══ d) wms_wave_create ═══
create or replace function public.wms_wave_create(p_so_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_id     uuid;
  v_doc    public.wms_order_doc%rowtype;
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
  perform 1 from public.so s where s.id = any (p_so_ids) order by s.id for update;             -- wsp-1 d-ⓑ: 잠금은 id 순(판매 먼저 · 트랜스퍼 다음) — 순서가 엇갈린 두 Wave 가 교착하지 않는다 · 토트 번호는 p_so_ids 순 그대로
  perform 1 from public.inv_transfer x where x.id = any (p_so_ids) order by x.id for update;
  -- ① 검사 전부(잠근다)
  foreach v_id in array p_so_ids loop
    perform 1 from public.so s where s.id = v_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
    perform 1 from public.inv_transfer x where x.id = v_id for update;             -- tr-1b2: 트랜스퍼 행 잠금(판정 72-3 의 짝 · 문서 id 는 둘 중 하나에만 맞는다)
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    if not found then raise exception 'Order not found (%) — nothing was saved', v_id; end if;
    select w.name into v_wh from public.ref_warehouse w where w.id = v_doc.warehouse_id;
    if not public.ims_can_warehouse(v_doc.warehouse_id) then            -- ⭐ 둘째
      raise exception 'Order % is at % — you are not set up for that warehouse — nothing was saved', v_doc.doc_number, coalesce(v_wh, '<none>');
    end if;
    if v_doc.status <> 'at_wms' then
      raise exception 'Order % is % — only orders released to the WMS can go in a wave — nothing was saved', v_doc.doc_number, v_doc.status;
    end if;
    if exists (select 1 from public.wms_pick_tasks t where coalesce(t.order_id, t.transfer_id) = v_id) then
      raise exception 'Order % already has pick tasks — nothing was saved', v_doc.doc_number;
    end if;
    if not exists (select 1 from public.wms_order_doc_line l where l.doc_id = v_id and l.qty_target > 0) then
      raise exception 'Order % has nothing left to ship — nothing was saved', v_doc.doc_number;
    end if;
    if v_wh_id is null then v_wh_id := v_doc.warehouse_id;
    elsif v_wh_id <> v_doc.warehouse_id then
      raise exception 'Order % is at % — a wave takes one warehouse only — nothing was saved', v_doc.doc_number, coalesce(v_wh, '<none>');
    end if;
  end loop;
  -- ② 웨이브 행
  v_md := to_char(public.ims_today(), 'MMDD');
  perform pg_advisory_xact_lock(hashtext('wms_wave_label:' || v_md));   -- wsp-1 d-ⓐ: 같은 날 Wave 라벨 셈을 한 줄로(두 번째는 첫 커밋 뒤 n+1 을 센다)
  select coalesce(max(substring(w.label from '^W-' || v_md || '-([0-9]+)$')::int), 0) + 1 into v_n from public.wms_waves w where w.label like 'W-' || v_md || '-%';
  v_label := format('W-%s-%s', v_md, v_n);
  insert into public.wms_waves (label, warehouse_id, status, created_by, created_at)
  values (v_label, v_wh_id, 'pending', v_staff, now())
  returning id into v_wave;
  -- ③ 오더마다 과제 하나 → picking
  foreach v_id in array p_so_ids loop
    i := i + 1;
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    select array_agg(l.line_id) into v_ids from public.wms_order_doc_line l where l.doc_id = v_id and l.qty_target > 0;
    v_plan := public.so_pick_plan(v_id);
    v_t := public.wms_pick_task_build(v_id, v_doc.doc_number || '-1', v_ids, v_wave, i, v_staff, v_plan);
    v_tasks := v_tasks || (v_t || jsonb_build_object('so_id', v_id, 'so_number', v_doc.doc_number, 'short_ea_total', v_plan->'short_ea_total'));
    v_warn := v_warn || (v_plan->'warnings') || (v_t->'warnings');
    perform public.wms_doc_status(v_doc.doc_kind, v_id, 'picking', v_staff);       -- tr-1b2
  end loop;
  return jsonb_build_object('wave_id', v_wave, 'label', v_label, 'warehouse_id', v_wh_id, 'orders', i, 'tasks', v_tasks, 'warnings', v_warn);
end;
$$;
