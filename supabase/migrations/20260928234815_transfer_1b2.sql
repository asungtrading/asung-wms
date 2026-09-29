-- ─────────────────────────────────────────────────────────────
-- 재고 사건 ② 트랜스퍼 · 둘째 몫 「창고 간」 ②-2 — 트랜스퍼 입구 · 창고 창구가 트랜스퍼도 받는다 · 창고 마무리는 트랜스퍼를 거부한다(출발은 ③) (Asung-IMS · tr-1b2 · 2026-09-28)
--   정본(뒤에 적는다): so-module §27(판정 64 · 65 · 69 · 71 · 72 · 묶음 열) · tr-1a(20260928201753) · tr-1b1(20260928231355) 위에 선다
--   든 것: ① tf_wms_status — 트랜스퍼 상태를 바꾸는 유일한 손(so_wms_status 20260926192314 와 같은 결 · 허락 짝 confirmed→at_wms · at_wms→confirmed · at_wms→picking · picking→at_wms · in_transit 은 ③ · 시각 · 사람 칸 · invoker · 판정 31 revoke)
--         ② wms_doc_status(kind, id, to, staff) — 창고 창구가 부르는 하나(판매면 so_wms_status 그대로 · 트랜스퍼면 tf_wms_status)
--         ③ tf_release(ids) · tf_wms_recall(ids) — 문서 담당의 입구(transfer 열쇠 · 보내기 = 출발 창고 권한 · 묶음 9) · 판매 so_release_to_wms · so_wms_recall 과 같은 검사 결(confirmed → at_wms · at_wms 이고 과제 없음 → confirmed)
--         ④ 창고 창구 재발행 13 — tr-1b1 본문 바이트 그대로 + 갈래만: 여섯 창구에 트랜스퍼 행 잠금 한 줄(판정 72-3 의 짝) · so_wms_status 호출 8 → wms_doc_status(v_doc.doc_kind …) · 쓰는 자리는 doc_kind 로 order_id / transfer_id(과제 · 줄 · 실수 · 검토함 · 되돌리기 기록 · 보관) · 읽는 자리의 order_id = 는 coalesce(order_id, transfer_id) · 팔렛 담긴 것도 coalesce(판매 무변)
--            wms_batch_create · wms_wave_create · wms_pick_task_build · wms_pick_lines(팩 줄 짝) · wms_complete_pick · wms_complete_pack(대조 서브쿼리 짝) · wms_finalize(트랜스퍼 거부) · wms_so_handoff(줄 짝 · 팔렛) · wms_rollback · wms_rollback_batch · wms_unwave · wms_review_set · wms_rb_archive(20260926204246 · 시그니처 무변 · 문서 종류를 뷰에서 읽는다)
--   ⭐ 약속: 판매 오더로 부를 때 반환 · 전이 · 쓰는 행은 tr-1b1 과 같다(tr-1b1-verify 를 이 파일로 다시 돌려 옛/새 대조 12) · 트랜스퍼는 창고 마무리 직전까지 — wms_finalize 는 트랜스퍼면 검사 전에 거부하고 아무것도 쓰지 않는다
--         ⑤ 읽기 정책 둘 — 창고 일 열쇠 넷이 inv_transfer · inv_transfer_line 을 읽는다(worker 의 invoker 읽기 창구가 빈 결과를 냈다 · 시험 2회차)
--   이 차수가 하지 않는 것(③): 출발(원장 · 레이어 · in_transit · departed_at) · wms_finalize 의 트랜스퍼 갈래 · 팔렛에 트랜스퍼 담기(넣는 창구 없음 · 화면이 직접 쓴다) · Health 트랜스퍼 전용 검사 셋(③ · ④) · 화면(⑥)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 판매 표 · 행 무접촉 · 판매 창구(so_finalize · so_ship · inv_post_sale · so_allocate_run · so_confirm · so_wms_status 본문) 무접촉 · IMS 안에서만 선다(판정 51 · 60)
-- ─────────────────────────────────────────────────────────────
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

-- ═══ 1) tf_wms_status — 트랜스퍼 상태 손 하나(so_wms_status 와 같은 결 · 창고 창구만 부른다 · 판정 31 revoke) ═══
create function public.tf_wms_status(p_transfer_id uuid, p_to text, p_staff uuid) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare
  v_x    public.inv_transfer%rowtype;
  v_from text;
  v_n    int;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  v_from := v_x.status;
  if not ((p_to = 'at_wms'    and v_from in ('confirmed', 'picking'))
       or (p_to = 'confirmed' and v_from = 'at_wms')
       or (p_to = 'picking'   and v_from = 'at_wms')) then                                -- in_transit(출발)은 ③ · packed 는 트랜스퍼에 없다(창고 마무리 = 출발)
    raise exception 'Transfer % is % — it cannot move to % from there — nothing was saved', v_x.transfer_number, v_from, p_to;
  end if;
  update public.inv_transfer x
     set status     = p_to,
         at_wms_at  = case when p_to = 'at_wms' and v_from = 'confirmed' then now()   when p_to = 'confirmed' then null else x.at_wms_at  end,
         at_wms_by  = case when p_to = 'at_wms' and v_from = 'confirmed' then p_staff when p_to = 'confirmed' then null else x.at_wms_by  end,
         picking_at = case when p_to = 'picking' and v_from = 'at_wms' then now()     when p_to = 'at_wms' and v_from = 'picking' then null else x.picking_at end,
         picking_by = case when p_to = 'picking' and v_from = 'at_wms' then p_staff   when p_to = 'at_wms' and v_from = 'picking' then null else x.picking_by end,
         updated_by = p_staff
   where x.id = p_transfer_id and x.status = v_from;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Transfer % changed under you (expected %) — nothing was saved', v_x.transfer_number, v_from;
  end if;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'from', v_from, 'to', p_to);
end;
$$;
comment on function public.tf_wms_status(uuid, text, uuid) is 'tr-1b2(판정 64 · 묶음 4) — 트랜스퍼의 창고 단계 전이를 바꾸는 유일한 손(so_wms_status 의 짝) · confirmed→at_wms(보내기) · at_wms→confirmed(되부르기) · at_wms→picking(배치 · 웨이브) · picking→at_wms(되돌리기) · 출발(in_transit)은 ③ · 창고 창구(definer)만 부른다 · 직원에게는 회수(판정 31)';
revoke all on function public.tf_wms_status(uuid, text, uuid) from public, anon, authenticated;

-- ═══ 2) wms_doc_status — 창고 창구가 부르는 하나(판매 · 트랜스퍼 갈래) ═══
create function public.wms_doc_status(p_kind text, p_id uuid, p_to text, p_staff uuid) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
begin
  if p_kind = 'so' then
    return public.so_wms_status(p_id, p_to, p_staff);                                     -- 판매 모듈의 창구 그대로(본문 무접촉)
  elsif p_kind = 'transfer' then
    return public.tf_wms_status(p_id, p_to, p_staff);
  else
    raise exception 'Unknown document kind % — nothing was saved', coalesce(p_kind, '<null>');
  end if;
end;
$$;
comment on function public.wms_doc_status(text, uuid, text, uuid) is 'tr-1b2(판정 71 · 72) — 창고 창구가 문서 상태를 바꿀 때 부르는 하나 · kind = wms_order_doc.doc_kind(so · transfer) · 판매면 so_wms_status · 트랜스퍼면 tf_wms_status · 직원에게는 회수(판정 31)';
revoke all on function public.wms_doc_status(text, uuid, text, uuid) from public, anon, authenticated;

-- ═══ 3) tf_release · tf_wms_recall — 문서 담당의 입구(so_release_to_wms · so_wms_recall 과 같은 결 · transfer 열쇠 · 보내기 = 출발 창고) ═══
create function public.tf_release(p_ids uuid[]) returns jsonb
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
  -- ① 검사 전부
  foreach v_id in array p_ids loop
    select * into v_x from public.inv_transfer x where x.id = v_id;
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
comment on function public.tf_release(uuid[]) is 'tr-1b2(판정 64 · 묶음 9) — 확정된 트랜스퍼를 출발 창고로 보낸다(confirmed → at_wms) · 첫 줄 ims_require_write(transfer) · 출발 창고 권한 · 줄 있음 · 여럿을 한 번에(하나라도 막히면 전체 거부) · 판매 so_release_to_wms 의 짝';
revoke all on function public.tf_release(uuid[]) from public, anon;
grant execute on function public.tf_release(uuid[]) to authenticated;

create function public.tf_wms_recall(p_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_id uuid;  v_x public.inv_transfer%rowtype;  v_out jsonb := '[]'::jsonb;
begin
  perform public.ims_require_write('transfer', 'saved');              -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  if p_ids is null or cardinality(p_ids) = 0 then raise exception 'No transfers given — nothing was saved'; end if;
  foreach v_id in array p_ids loop
    select * into v_x from public.inv_transfer x where x.id = v_id;
    if not found then raise exception 'Transfer not found (%) — nothing was saved', v_id; end if;
    if not public.ims_can_warehouse(v_x.from_warehouse_id) then
      raise exception 'Transfer % leaves from a warehouse you are not set up for — nothing was saved', v_x.transfer_number;
    end if;
    if v_x.status <> 'at_wms' then
      raise exception 'Transfer % is % — only a transfer sent to the warehouse (and not yet in work) can be recalled — nothing was saved', v_x.transfer_number, v_x.status;
    end if;
    if exists (select 1 from public.wms_pick_tasks t where coalesce(t.order_id, t.transfer_id) = v_id) then
      raise exception 'Transfer % already has pick tasks — the warehouse must send it back first — nothing was saved', v_x.transfer_number;
    end if;
  end loop;
  foreach v_id in array p_ids loop
    v_out := v_out || public.tf_wms_status(v_id, 'confirmed', v_staff);
  end loop;
  return jsonb_build_object('recalled', v_out, 'count', jsonb_array_length(v_out));
end;
$$;
comment on function public.tf_wms_recall(uuid[]) is 'tr-1b2 — 창고로 보낸 트랜스퍼를 되부른다(at_wms → confirmed · 과제 없을 때만) · 첫 줄 ims_require_write(transfer) · 출발 창고 권한 · 판매 so_wms_recall 의 짝';
revoke all on function public.tf_wms_recall(uuid[]) from public, anon;
grant execute on function public.tf_wms_recall(uuid[]) to authenticated;

-- ═══ 4) 창고 창구 재발행 13 — tr-1b1(20260928231355) 본문 바이트 그대로 + 갈래(diff 원문은 보고) · create or replace 라 grant · comment · security 가 남는다 ═══

-- ── wms_rb_archive ──
create or replace function public.wms_rb_archive(p_staff uuid, p_action text, p_so_id uuid, p_so_number text, p_label text, p_table text, p_pred text) returns int
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_n int;  v_kind text;
begin
  select d.doc_kind into v_kind from public.wms_order_doc d where d.doc_id = p_so_id;   -- tr-1b2: p_so_id 는 문서 id(판매 오더 또는 트랜스퍼 · null 이면 웨이브 되돌리기 — 둘 다 비운다) · 시그니처 무변
  execute format('insert into public.wms_rollback_archive (archived_by, action, order_id, transfer_id, order_number, batch_label, src_table, row_data) select $1, $2, $3, $4, $5, $6, %L, to_jsonb(t) from public.%I t where %s', p_table, p_table, p_pred)
  using p_staff, p_action, case when v_kind = 'so' then p_so_id end, case when v_kind = 'transfer' then p_so_id end, p_so_number, p_label;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- ── wms_batch_create ──
create or replace function public.wms_batch_create(p_so_id uuid, p_batches jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_doc    public.wms_order_doc%rowtype;
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
  perform 1 from public.so s where s.id = p_so_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
  perform 1 from public.inv_transfer x where x.id = p_so_id for update;             -- tr-1b2: 트랜스퍼 행 잠금(판정 72-3 의 짝 · 문서 id 는 둘 중 하나에만 맞는다)
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_doc.warehouse_id;
  if not public.ims_can_warehouse(v_doc.warehouse_id) then              -- ⭐ 둘째 — 창고 제한 첫 실물
    raise exception 'Order % is at % — you are not set up for that warehouse — nothing was saved', v_doc.doc_number, coalesce(v_wh, '<none>');
  end if;
  if v_doc.status <> 'at_wms' then
    raise exception 'Order % is % — only orders released to the WMS can be batched — nothing was saved', v_doc.doc_number, v_doc.status;
  end if;
  if exists (select 1 from public.wms_pick_tasks t where coalesce(t.order_id, t.transfer_id) = p_so_id) then
    raise exception 'Order % already has pick tasks — nothing was saved', v_doc.doc_number;
  end if;
  if p_batches is null or jsonb_typeof(p_batches) <> 'array' or jsonb_array_length(p_batches) = 0 then
    raise exception 'Order % — no batches given — nothing was saved', v_doc.doc_number;
  end if;
  -- 줄 검사: 모르는 줄 · 두 번 든 줄 · 빠진 보낼 줄 · 다 뺀 줄
  for b in select * from jsonb_array_elements(p_batches) loop
    if jsonb_typeof(b->'line_ids') <> 'array' or jsonb_array_length(b->'line_ids') = 0 then
      raise exception 'Order % — a batch has no lines — nothing was saved', v_doc.doc_number;
    end if;
    select array_agg((e.v)::uuid) into v_batch from jsonb_array_elements_text(b->'line_ids') e(v);
    v_ids := v_ids || v_batch;
  end loop;
  select string_agg(u.id::text, ', ') into v_bad from unnest(v_ids) u(id) where not exists (select 1 from public.wms_order_doc_line l where l.line_id = u.id and l.doc_id = p_so_id);
  if v_bad is not null then raise exception 'Order % — lines not on this order (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ') into v_bad from (select u.id from unnest(v_ids) u(id) group by u.id having count(*) > 1) d join public.wms_order_doc_line l on l.line_id = d.id;
  if v_bad is not null then raise exception 'Order % — lines in more than one batch (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ' order by l.line_no) into v_bad from public.wms_order_doc_line l where l.doc_id = p_so_id and l.qty_target > 0 and not (l.line_id = any (v_ids));
  if v_bad is not null then raise exception 'Order % — lines left out of the batches (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ' order by l.line_no) into v_bad from public.wms_order_doc_line l where l.doc_id = p_so_id and l.qty_target <= 0 and l.line_id = any (v_ids);
  if v_bad is not null then raise exception 'Order % — lines with nothing to ship (%) cannot be batched — nothing was saved', v_doc.doc_number, v_bad; end if;
  -- 계획 칸 · 과제
  v_plan := public.so_pick_plan(p_so_id);
  i := 0;
  for b in select * from jsonb_array_elements(p_batches) loop
    i := i + 1;
    select array_agg((e.v)::uuid) into v_batch from jsonb_array_elements_text(b->'line_ids') e(v);
    v_t := public.wms_pick_task_build(p_so_id, v_doc.doc_number || '-' || i, v_batch, null, null, v_staff, v_plan);
    v_tasks := v_tasks || v_t;
    v_warn := v_warn || (v_t->'warnings');
  end loop;
  perform public.wms_doc_status(v_doc.doc_kind, p_so_id, 'picking', v_staff);     -- tr-1b2: 판매면 so_wms_status · 트랜스퍼면 tf_wms_status
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_doc.doc_number, 'status', 'picking', 'tasks', v_tasks,
                            'short_ea_total', v_plan->'short_ea_total', 'warnings', (v_plan->'warnings') || v_warn);
end;
$$;

-- ── wms_wave_create ──
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

-- ── wms_pick_task_build ──
create or replace function public.wms_pick_task_build(p_so_id uuid, p_label text, p_line_ids uuid[], p_wave_id bigint, p_tote_no int, p_staff uuid, p_plan jsonb) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare
  v_doc     public.wms_order_doc%rowtype;
  v_task    bigint;
  v_line    bigint;
  l         record;
  p         jsonb;
  v_bin     uuid;
  v_lines   int := 0;
  v_rows    int := 0;
  v_warn    text[] := '{}';
begin
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  insert into public.wms_pick_tasks (order_id, transfer_id, batch_label, status, created_by, created_at, wave_id, tote_no)
  values (case when v_doc.doc_kind = 'so' then p_so_id end, case when v_doc.doc_kind = 'transfer' then p_so_id end, p_label, 'pending', p_staff, now(), p_wave_id, p_tote_no)
  returning id into v_task;
  for l in
    select x.line_id as id, x.line_no, x.pack_factor, x.qty_target_ea as need_ea
    from public.wms_order_doc_line x where x.doc_id = p_so_id and x.line_id = any (p_line_ids) order by x.line_no
  loop
    insert into public.wms_pick_task_lines (pick_task_id, order_line_id, transfer_line_id, assigned_base, status, created_at)
    values (v_task, case when v_doc.doc_kind = 'so' then l.id end, case when v_doc.doc_kind = 'transfer' then l.id end, l.need_ea, 'pending', now())
    returning id into v_line;
    v_lines := v_lines + 1;
    for p in select * from jsonb_array_elements(coalesce(p_plan->'picks', '[]'::jsonb)) loop
      if (p->>'line_id')::uuid <> l.id then continue; end if;
      if coalesce(p->>'bin', '') = '' then
        v_warn := array_append(v_warn, format('no_bin:%s:%s', v_doc.doc_number, l.line_no));
        continue;
      end if;
      select b.id into v_bin from public.ref_bin b where b.warehouse_id = v_doc.warehouse_id and b.name = p->>'bin';
      if v_bin is null then
        v_warn := array_append(v_warn, format('bin_unknown:%s:%s:%s', v_doc.doc_number, l.line_no, p->>'bin'));
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

-- ── wms_pick_lines ──
create or replace function public.wms_pick_lines(p_task_ids bigint[] default null, p_pack_task_id bigint default null) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_task_ids bigint[];
  v_pack_id  bigint := p_pack_task_id;
  v_out      jsonb;
begin
  if (p_task_ids is null or cardinality(p_task_ids) = 0) = (p_pack_task_id is null) then
    raise exception 'Pass exactly one of p_task_ids / p_pack_task_id';
  end if;
  if p_pack_task_id is not null then
    select array[k.pick_task_id] into v_task_ids from public.wms_pack_tasks k where k.id = p_pack_task_id;
    if v_task_ids is null or v_task_ids[1] is null then return '[]'::jsonb; end if;     -- 팩 과제 없음 · 픽 과제 없는 팩 과제 = 빈 배열(깨끗한 빈손)
  else
    v_task_ids := p_task_ids;
  end if;

  with t as (
    select t.id, t.batch_label, coalesce(t.order_id, t.transfer_id) as order_id, t.wave_id, t.tote_no,
           d.doc_number as so_number, d.warehouse_id as location_id, w.name as wh_name, d.party_name as customer_name
    from public.wms_pick_tasks t
    join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
    left join public.ref_warehouse w on w.id = d.warehouse_id
    where t.id = any(v_task_ids)
  ), pl as (
    select l.id as line_id, l.pick_task_id, l.order_line_id, l.transfer_line_id, l.assigned_base, l.picked_base, l.status, l.verification_method, l.picked_by, l.picked_at,
           t.order_id, t.so_number, t.customer_name, t.location_id, t.wh_name, t.batch_label, t.wave_id, t.tote_no,
           x.sku, x.product_name, x.pack_factor,
           coalesce(p.parent_product_id, p.id) as stock_pid, (p.parent_product_id is not null) as is_set
    from public.wms_pick_task_lines l
    join t on t.id = l.pick_task_id
    join public.wms_order_doc_line x on x.line_id = coalesce(l.order_line_id, l.transfer_line_id)
    join public.product p on p.id = x.product_id
  ), pids as (
    select distinct pl.stock_pid from pl
  ), whs as (
    select distinct t.location_id from t where t.location_id is not null
  ), bal as (                                                             -- 창고 전체 잔고 · 한 문장 · 한 번(속도 함정)
    select v.warehouse_id, v.product_id, sum(v.qty) as qty
    from public.ims_inv_balance v
    where v.product_id = any(array(select pids.stock_pid from pids))
      and v.warehouse_id = any(array(select whs.location_id from whs))
    group by v.warehouse_id, v.product_id
  ), bc as (                                                              -- 낱개(factor 1) + 그 낱개를 parent 로 둔 세트들(factor = pack_factor)
    select coalesce(p.parent_product_id, p.id) as stock_pid,
           jsonb_agg(jsonb_build_object('barcode', b.barcode,
                                        'factor', case when p.parent_product_id is null then 1 else coalesce(p.pack_factor, 1) end,
                                        'sku', p.sku)
                     order by case when p.parent_product_id is null then 1 else coalesce(p.pack_factor, 1) end, b.is_primary desc, b.barcode) as arr
    from public.product_barcode b
    join public.product p on p.id = b.product_id
    where b.is_active
      and (p.id = any(array(select pids.stock_pid from pids)) or p.parent_product_id = any(array(select pids.stock_pid from pids)))
    group by coalesce(p.parent_product_id, p.id)
  ), bins as (                                                            -- 계획 칸(planned) · 실제 칸(actual) · 존은 여기 한 곳에서
    select x.pick_task_line_id, x.planned,
           jsonb_agg(jsonb_build_object('bin', x.bin, 'bin_id', x.bin_id, 'qty_base', x.qty_base,
                                        'zone', coalesce(rb.zone,
                                                         case when coalesce(x.bin, '') = '' then ''
                                                              when pl2.wh_name ilike '%edmonton%' and upper(left(x.bin, 1)) = 'E' then upper(substr(x.bin, 2, 1))
                                                              else upper(left(x.bin, 1)) end),
                                        'picked_by', x.picked_by, 'picked_at', x.picked_at)
                     order by x.id) as arr
    from public.wms_pick_line_bins x
    join pl pl2 on pl2.line_id = x.pick_task_line_id
    left join public.ref_bin rb on rb.id = x.bin_id
    group by x.pick_task_line_id, x.planned
  ), pk as (                                                              -- 팩 갈래 — 팩 줄(order_line_id 로 짝)
    select k.id as pack_line_id, k.order_line_id, k.transfer_line_id, k.expected_base, k.verified_base, k.status as pack_status,
           k.verification_method as pack_verification_method, k.verified_by, k.verified_at
    from public.wms_pack_task_lines k
    where v_pack_id is not null and k.pack_task_id = v_pack_id
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'line_id', case when v_pack_id is null then pl.line_id else pk.pack_line_id end,
             'pick_line_id', pl.line_id,
             'pick_task_id', pl.pick_task_id, 'batch_label', pl.batch_label, 'wave_id', pl.wave_id, 'tote_no', pl.tote_no,
             'order_line_id', coalesce(pl.order_line_id, pl.transfer_line_id), 'so_id', pl.order_id, 'so_number', pl.so_number, 'customer_name', pl.customer_name, 'warehouse_id', pl.location_id,
             'sku', pl.sku, 'base_sku', sp.sku, 'product_name', pl.product_name, 'pack_factor', pl.pack_factor, 'is_set', pl.is_set,
             'assigned_base', pl.assigned_base, 'picked_base', pl.picked_base,
             'status', case when v_pack_id is null then pl.status else pk.pack_status end,
             'verification_method', case when v_pack_id is null then pl.verification_method else pk.pack_verification_method end,
             'picked_by', pl.picked_by, 'picked_at', pl.picked_at,
             'planned_bins', coalesce(bp.arr, '[]'::jsonb), 'actual_bins', coalesce(ba.arr, '[]'::jsonb),
             'barcodes', coalesce(bc.arr, '[]'::jsonb),
             'available_ea', coalesce(bal.qty, 0))
           || case when v_pack_id is null then '{}'::jsonb
                   else jsonb_build_object('pack_line_id', pk.pack_line_id, 'expected_base', pk.expected_base, 'verified_base', pk.verified_base,
                                           'pack_status', pk.pack_status, 'pack_verification_method', pk.pack_verification_method,
                                           'verified_by', pk.verified_by, 'verified_at', pk.verified_at) end
           order by pl.tote_no nulls first, pl.pick_task_id, pl.line_id), '[]'::jsonb)
    into v_out
  from pl
  join public.product sp on sp.id = pl.stock_pid
  left join bal  on bal.warehouse_id = pl.location_id and bal.product_id = pl.stock_pid
  left join bc   on bc.stock_pid = pl.stock_pid
  left join bins bp on bp.pick_task_line_id = pl.line_id and bp.planned
  left join bins ba on ba.pick_task_line_id = pl.line_id and not ba.planned
  left join pk   on coalesce(pk.order_line_id, pk.transfer_line_id) = coalesce(pl.order_line_id, pl.transfer_line_id)
  where v_pack_id is null or pk.pack_line_id is not null;

  return v_out;
end
$$;

-- ── wms_complete_pick ──
create or replace function public.wms_complete_pick(p_lines jsonb, p_task_id bigint default null, p_wave_id bigint default null, p_mistakes jsonb default '[]'::jsonb, p_short_refresh jsonb default '[]'::jsonb, p_short_delete jsonb default '[]'::jsonb, p_session_id text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_worker  uuid;
  v_now     timestamptz := now();
  v_wh      uuid;
  v_flipped bigint;
  v_task_ids  bigint[];
  v_order_ids uuid[];
  v_member_total     int := 0;
  v_members_completed int := 0;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
  v_disc_inserted  int := 0;
  v_short_refreshed int := 0;
  v_short_deleted   int := 0;
  v_bins_inserted   int := 0;
  v_e       jsonb;  v_b jsonb;                                       -- ⚠️ 별칭 e·b(줄 저장 서브쿼리)와 겹치지 않게 v_ 접두
  v_pl      record;
  v_line_id bigint;  v_pb numeric;  v_sum numeric;  v_rem numeric;  v_bin uuid;  v_bin_name text;  v_first uuid;  v_first_name text;
begin
  perform public.ims_require_write('picking', 'saved');               -- ⭐ 첫 줄
  v_worker := public.so_current_staff();
  if (p_task_id is null) = (p_wave_id is null) then
    raise exception 'Pass exactly one of p_task_id / p_wave_id — nothing was saved';
  end if;
  -- 창고 제한 — 과제 오더의 창고 · 웨이브는 웨이브 행의 창고
  select case when p_wave_id is not null then (select w.warehouse_id from public.wms_waves w where w.id = p_wave_id)
              else (select d.warehouse_id from public.wms_pick_tasks t join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id) where t.id = p_task_id) end into v_wh;
  if v_wh is null then raise exception 'Task not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_wh) then                          -- ⭐ 둘째
    raise exception 'This task is at another warehouse — you are not set up for it — nothing was saved';
  end if;

  if p_wave_id is not null then
    -- ① CAS = wave 행 (소유권 단위). 첫 쓰기 — 0행이면 아무것도 안 썼다.
    update public.wms_waves w
       set status = 'completed', completed_at = v_now
     where w.id = p_wave_id and w.assigned_to = v_worker and w.status = 'in_progress'
       and (p_session_id is null or w.session_id is null or w.session_id = p_session_id)
    returning w.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('completed', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from public.wms_waves x where x.id = p_wave_id));
    end if;
    -- ② 멤버 = 서버 유도 (wave 행 잠금 아래) → 일괄 플립. 행 수 ≠ 멤버 수 = 전체 롤백.
    select coalesce(array_agg(id), '{}') into v_task_ids from public.wms_pick_tasks where wave_id = p_wave_id;
    v_member_total := coalesce(array_length(v_task_ids, 1), 0);
    if v_member_total = 0 then
      raise exception 'Wave % has no member batches — nothing was saved. Ask a manager', p_wave_id;
    end if;
    update public.wms_pick_tasks t
       set status = 'completed', completed_at = v_now, completed_by = v_worker
     where t.wave_id = p_wave_id and t.assigned_to = v_worker;
    get diagnostics v_members_completed = row_count;
    if v_members_completed <> v_member_total then
      raise exception 'Wave completion failed: % of % member batches matched (a member may have been taken over or released) — nothing was saved. Ask a manager before retrying',
        v_members_completed, v_member_total;
    end if;
  else
    -- ① 단일 모드 CAS — 팩과 동형
    update public.wms_pick_tasks t
       set status = 'completed', completed_at = v_now, completed_by = v_worker
     where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
       and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
    returning t.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('completed', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from public.wms_pick_tasks x where x.id = p_task_id));
    end if;
    v_task_ids := array[p_task_id];
  end if;

  select coalesce(array_agg(distinct coalesce(order_id, transfer_id)), '{}') into v_order_ids from public.wms_pick_tasks where id = any(v_task_ids);

  -- ⚠️ 귀속 가드 — 완료 범위 밖 order/task 가 실려 오면 예외 = 전체 롤백(플립 포함).
  perform 1 from jsonb_array_elements(coalesce(p_mistakes, '[]'::jsonb)) d
   where not ((d->>'order_id')::uuid = any(v_order_ids))
      or (d->>'pick_task_id' is not null and not ((d->>'pick_task_id')::bigint = any(v_task_ids)))
   limit 1;
  if found then
    raise exception 'Mistake row outside this pick scope (wrong order or batch) — nothing was saved';
  end if;
  perform 1 from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where not ((r->>'order_id')::uuid = any(v_order_ids)) limit 1;
  if found then
    raise exception 'Stock-short refresh outside this pick scope — nothing was saved';
  end if;
  perform 1 from jsonb_array_elements(coalesce(p_short_delete, '[]'::jsonb)) r
   where not ((r->>'order_id')::uuid = any(v_order_ids)) limit 1;
  if found then
    raise exception 'Stock-short cleanup outside this pick scope — nothing was saved';
  end if;

  -- ③ 라인 최종 저장 — pick_task_id 조건 = 타 배치 오염 차단
  update public.wms_pick_task_lines l
     set picked_base = r.pb, status = r.st, verification_method = r.vm
    from (
      select (e->>'id')::bigint                    as id,
             (e->>'picked_base')::numeric          as pb,
             e->>'status'                          as st,
             nullif(e->>'verification_method', '') as vm
        from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
    ) r
   where l.id = r.id and l.pick_task_id = any(v_task_ids);
  get diagnostics v_lines_updated = row_count;
  if v_lines_updated <> v_lines_expected then
    raise exception 'Line save failed: found % of % lines — lines may have been removed by a rollback. Nothing was saved. Ask a manager before retrying',
      v_lines_updated, v_lines_expected;
  end if;

  -- ③′ 실제 칸 행(⑤-2a2) — 줄마다 planned=false 행을 새로(있던 것은 지운다) · 합 = picked_base · bins 가 없으면 계획 칸 순서로
  for v_e in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    v_line_id := (v_e->>'id')::bigint;  v_pb := (v_e->>'picked_base')::numeric;
    delete from public.wms_pick_line_bins x where x.pick_task_line_id = v_line_id and not x.planned;
    if v_pb <= 0 then continue; end if;
    if jsonb_typeof(v_e->'bins') = 'array' and jsonb_array_length(v_e->'bins') > 0 then
      v_sum := 0;
      for v_b in select * from jsonb_array_elements(v_e->'bins') loop
        if (v_b->>'qty_base')::numeric <= 0 then raise exception 'Line %: a bin row has qty_base <= 0 — nothing was saved', v_line_id; end if;
        if v_b ? 'bin_id' then
          select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.id = (v_b->>'bin_id')::uuid and rb.warehouse_id = v_wh;
        else
          select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.name = v_b->>'bin' and rb.warehouse_id = v_wh;
        end if;
        if v_bin is null then raise exception 'Line %: bin % is not in this warehouse — nothing was saved', v_line_id, coalesce(v_b->>'bin', v_b->>'bin_id'); end if;
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (v_line_id, v_bin, v_bin_name, (v_b->>'qty_base')::numeric, false, v_worker, v_now);
        v_bins_inserted := v_bins_inserted + 1;  v_sum := v_sum + (v_b->>'qty_base')::numeric;
      end loop;
      if v_sum <> v_pb then raise exception 'Line %: bin quantities (%) do not add up to picked (%) — nothing was saved', v_line_id, v_sum, v_pb; end if;
    else
      v_rem := v_pb;  v_first := null;
      for v_pl in select x.bin_id, x.bin, x.qty_base from public.wms_pick_line_bins x where x.pick_task_line_id = v_line_id and x.planned order by x.id loop
        if v_first is null then v_first := v_pl.bin_id; v_first_name := v_pl.bin; end if;
        exit when v_rem <= 0;
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (v_line_id, v_pl.bin_id, v_pl.bin, least(v_rem, v_pl.qty_base), false, v_worker, v_now);
        v_bins_inserted := v_bins_inserted + 1;  v_rem := v_rem - least(v_rem, v_pl.qty_base);
      end loop;
      if v_rem > 0 and v_first is not null then                      -- 계획보다 많이 뽑았다 → 첫 계획 칸이 나머지를 받는다
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (v_line_id, v_first, v_first_name, v_rem, false, v_worker, v_now);
        v_bins_inserted := v_bins_inserted + 1;  v_rem := 0;
      end if;
      if v_rem > 0 then raise exception 'Line %: no bins given and no planned bins to fall back on — nothing was saved', v_line_id; end if;
    end if;
  end loop;

  -- ④ short_pick 생성 — reason 고정 · order_number 는 서버 유도(so_number) → wms_worker_mistakes
  insert into public.wms_worker_mistakes
        (order_id, transfer_id, pick_task_id, order_number, sku, ordered_base, actual_base, reason, manager_resolved)
  select case when o.doc_kind = 'so' then o.doc_id end, case when o.doc_kind = 'transfer' then o.doc_id end, (d->>'pick_task_id')::bigint, o.doc_number, d->>'sku',
         (d->>'ordered_base')::numeric, (d->>'actual_base')::numeric, 'short_pick', false
    from jsonb_array_elements(coalesce(p_mistakes, '[]'::jsonb)) d
    join public.wms_order_doc o on o.doc_id = (d->>'order_id')::uuid;
  get diagnostics v_disc_inserted = row_count;

  -- ⑤ 선언(stock_short) 정리 — wms_reports kind stock_short · UPDATE/DELETE 0행 = 자연 no-op
  update public.wms_reports d
     set qty_expected = (r->>'ordered_base')::numeric, qty_found = (r->>'actual_base')::numeric
    from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where coalesce(d.order_id, d.transfer_id) = (r->>'order_id')::uuid and d.sku = r->>'sku'
     and d.kind = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_refreshed = row_count;

  delete from public.wms_reports d
   using jsonb_array_elements(coalesce(p_short_delete, '[]'::jsonb)) r
   where coalesce(d.order_id, d.transfer_id) = (r->>'order_id')::uuid and d.sku = r->>'sku'
     and d.kind = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_deleted = row_count;

  return jsonb_build_object(
    'completed', true,
    'worker', v_worker,
    'mode', case when p_wave_id is not null then 'wave' else 'single' end,
    'members_completed', v_members_completed,
    'lines_updated', v_lines_updated,
    'bins_inserted', v_bins_inserted,
    'disc_inserted', v_disc_inserted,
    'short_refreshed', v_short_refreshed,
    'short_deleted', v_short_deleted);
end
$$;

-- ── wms_complete_pack ──
create or replace function public.wms_complete_pack(p_task_id bigint, p_lines jsonb, p_mistakes jsonb default '[]'::jsonb, p_short_refresh jsonb default '[]'::jsonb, p_short_resolve jsonb default '[]'::jsonb, p_recovered jsonb default '[]'::jsonb, p_session_id text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_worker  uuid;
  v_now     timestamptz := now();
  v_wh      uuid;
  v_order_id       uuid;
  v_pick_task_id   bigint;
  v_order_number   text;  v_kind text;
  v_picker         uuid;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
  v_disc_inserted  int := 0;
  v_short_refreshed    int := 0;
  v_short_resolved     int := 0;
  v_recovered_resolved int := 0;
  v_ready       boolean := false;
  v_bad   text;
  -- 판정 57(adj-rec-a · 2026-09-28) — 팩 회복 칸 행
  v_r  jsonb;  v_pl_id bigint;  v_rq numeric;  v_bin uuid;  v_bin_name text;  v_recovered_rows int := 0;
begin
  perform public.ims_require_write('packing', 'saved');               -- ⭐ 첫 줄
  v_worker := public.so_current_staff();
  select d.warehouse_id into v_wh from public.wms_pack_tasks t join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id) where t.id = p_task_id;
  if v_wh is null then raise exception 'Task not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_wh) then                          -- ⭐ 둘째
    raise exception 'This task is at another warehouse — you are not set up for it — nothing was saved';
  end if;

  -- 페이로드 검증: 이 함수가 만들 수 있는 reason 3종만 (플립 전 — 실패 시 아무것도 안 씀)
  select d->>'reason' into v_bad
    from jsonb_array_elements(coalesce(p_mistakes, '[]'::jsonb)) d
   where d->>'reason' not in ('short_after_pack', 'over_pick', 'pack_scan_mistake')
   limit 1;
  if v_bad is not null then
    raise exception 'Reason "%" is not allowed in pack completion — nothing was saved', v_bad;
  end if;

  -- ① CAS 플립 먼저 (assigned_to = 나 + in_progress + session). 0행 = 아무것도 쓴 것이 없다 → 조용한 반환.
  update public.wms_pack_tasks t
     set status = 'completed', completed_at = v_now, completed_by = v_worker
   where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
     and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
  returning coalesce(t.order_id, t.transfer_id), t.pick_task_id into v_order_id, v_pick_task_id;

  if v_order_id is null then
    return jsonb_build_object('completed', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from public.wms_pack_tasks x where x.id = p_task_id));
  end if;

  select o.doc_number, o.doc_kind into v_order_number, v_kind from public.wms_order_doc o where o.doc_id = v_order_id;
  select pt.assigned_to into v_picker from public.wms_pick_tasks pt where pt.id = v_pick_task_id;

  -- ② 라인 최종 저장 — pack_task_id 조건 = 다른 태스크 라인 오염 차단. 방법·스캔 시각·사람은 coalesce 로 보존.
  update public.wms_pack_task_lines l
     set verified_base = r.vb, status = r.st,
         verification_method = coalesce(r.vm, l.verification_method),
         verified_at = coalesce(l.verified_at, v_now),
         verified_by = coalesce(l.verified_by, v_worker)
    from (
      select (e->>'id')::bigint                     as id,
             (e->>'verified_base')::numeric         as vb,
             e->>'status'                           as st,
             nullif(e->>'verification_method', '')  as vm
        from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
    ) r
   where l.id = r.id and l.pack_task_id = p_task_id;
  get diagnostics v_lines_updated = row_count;
  if v_lines_updated <> v_lines_expected then
    raise exception 'Line save failed: found % of % lines — lines may have been removed by a rollback. Nothing was saved. Ask a manager before retrying',
      v_lines_updated, v_lines_expected;
  end if;

  -- ②′ 팩 회복 칸 행(판정 57 · adj-rec-a 2026-09-28) — 픽을 넘겨 채운 낱개는 어느 칸에서 왔는지 남긴다 = 픽커가 뽑은 것과 같은 기록(wms_pick_line_bins planned=false · pack_task_id = 이 팩) ⇒ 출고(wms_so_handoff Σ칸) · 원장(so_ship) · P(inv_adjust_picked)가 저절로 맞는다
  --    p_recovered [{sku, bin_id | bin, qty}] · ⚠️ 옛 모양(['SKU'] · 캐시된 옛 화면)은 거부 — 칸 없이 조용히 완료되지 않게(fail-closed)
  if exists (select 1 from jsonb_array_elements(coalesce(p_recovered, '[]'::jsonb)) e where jsonb_typeof(e) <> 'object') then
    raise exception 'Reload the packing screen (Ctrl+F5) — this version cannot record where recovered stock came from — nothing was saved';
  end if;
  for v_r in select e from jsonb_array_elements(coalesce(p_recovered, '[]'::jsonb)) e loop
    select pl.id into v_pl_id from public.wms_pick_task_lines pl join public.wms_order_doc_line sl on sl.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
     where pl.pick_task_id = v_pick_task_id and sl.sku = v_r->>'sku' order by pl.id limit 1;                      -- 줄마다 과제 하나(wms_batch_create) — 첫 줄
    if v_pl_id is null then raise exception 'Recovered % is not a line of this batch — nothing was saved', v_r->>'sku'; end if;
    if (v_r->>'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' or (v_r->>'qty')::numeric <= 0 then raise exception 'Recovered % needs a positive qty — nothing was saved', v_r->>'sku'; end if;
    v_rq := (v_r->>'qty')::numeric;  v_bin := null;
    if nullif(v_r->>'bin_id', '') is not null then select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.id = (v_r->>'bin_id')::uuid and rb.warehouse_id = v_wh and rb.is_active;
    else select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.name = trim(v_r->>'bin') and rb.warehouse_id = v_wh and rb.is_active; end if;
    if v_bin is null then raise exception 'Recovered %: bin % is not an active bin at this warehouse — nothing was saved', v_r->>'sku', coalesce(v_r->>'bin', v_r->>'bin_id', '?'); end if;
    insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at, pack_task_id)
    values (v_pl_id, v_bin, v_bin_name, v_rq, false, v_worker, v_now, p_task_id);
    v_recovered_rows := v_recovered_rows + 1;
  end loop;
  -- 줄마다 대조 — 팩 verified = Σ실제 칸(픽커 + 이 팩의 회복)이어야 한다(넘치면 칸을 안 줬다 · 모자라면 회복을 너무 많이 줬다) · 회복 없이 verified ≤ 픽 칸 합은 정상(short_after_pack)
  select string_agg(format('%s packed %s, picked %s + recovered %s', t.sku, t.vb, t.pk, t.rc), '; ') into v_bad
    from (select sl.sku, kl.verified_base as vb,
                 coalesce((select sum(b.qty_base) from public.wms_pick_line_bins b join public.wms_pick_task_lines pl on pl.id = b.pick_task_line_id where pl.pick_task_id = v_pick_task_id and coalesce(pl.order_line_id, pl.transfer_line_id) = coalesce(kl.order_line_id, kl.transfer_line_id) and not b.planned and b.pack_task_id is null), 0) as pk,
                 coalesce((select sum(b.qty_base) from public.wms_pick_line_bins b where b.pack_task_id = p_task_id and b.pick_task_line_id in (select pl.id from public.wms_pick_task_lines pl where pl.pick_task_id = v_pick_task_id and coalesce(pl.order_line_id, pl.transfer_line_id) = coalesce(kl.order_line_id, kl.transfer_line_id))), 0) as rc
            from public.wms_pack_task_lines kl join public.wms_order_doc_line sl on sl.line_id = coalesce(kl.order_line_id, kl.transfer_line_id) where kl.pack_task_id = p_task_id) t
   where (t.rc = 0 and t.vb > t.pk) or (t.rc > 0 and t.vb <> t.pk + t.rc);
  if v_bad is not null then raise exception 'Recovered quantity does not match packed minus picked (%) — give the bin the extra came from — nothing was saved', v_bad; end if;

  -- ③ 실수 생성 — reason 별 템플릿 · responsible(=픽커)은 서버 유도: wms_pick_tasks.assigned_to → wms_worker_mistakes
  insert into public.wms_worker_mistakes
        (order_id, transfer_id, pack_task_id, order_number, sku, ordered_base, actual_base, reason,
         source, responsible, declared_by, resolved_by, resolved_at, manager_resolved)
  select case when v_kind = 'so' then v_order_id end, case when v_kind = 'transfer' then v_order_id end, p_task_id, v_order_number, d->>'sku',
         (d->>'ordered_base')::numeric, (d->>'actual_base')::numeric, d->>'reason',
         case when d->>'reason' = 'pack_scan_mistake' then 'packing' end,
         case when d->>'reason' in ('short_after_pack', 'over_pick') then v_picker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_worker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_worker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_now end,
         false
    from jsonb_array_elements(coalesce(p_mistakes, '[]'::jsonb)) d;
  get diagnostics v_disc_inserted = row_count;

  -- ④ 선언(stock_short) 정리 — wms_reports kind stock_short · UPDATE 0행 = 자연스러운 no-op
  update public.wms_reports d
     set qty_expected = (r->>'ordered_base')::numeric, qty_found = (r->>'actual_base')::numeric
    from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where coalesce(d.order_id, d.transfer_id) = v_order_id and d.sku = r->>'sku'
     and d.kind = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_refreshed = row_count;

  update public.wms_reports d
     set resolved_by = v_worker, resolved_at = v_now
    from jsonb_array_elements_text(coalesce(p_short_resolve, '[]'::jsonb)) as s(sku)
   where coalesce(d.order_id, d.transfer_id) = v_order_id and d.sku = s.sku
     and d.kind = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_resolved = row_count;

  -- ⑤ 팩에서 회복된 부족 → short_pick 해소. voided 행은 되살리지 않는다.
  update public.wms_worker_mistakes d
     set resolved_by = v_worker, resolved_at = v_now, reason = 'resolved_pack_recovery'
    from (select distinct e->>'sku' as sku from jsonb_array_elements(coalesce(p_recovered, '[]'::jsonb)) e) as s
   where coalesce(d.order_id, d.transfer_id) = v_order_id and d.sku = s.sku
     and d.reason = 'short_pick' and d.resolved_at is null and d.voided_at is null;                      -- 판정 57: 새 모양 [{sku, bin, qty}] 의 sku
  get diagnostics v_recovered_resolved = row_count;

  -- ⑥ ready 판정 — 뷰 wms_order_pack_progress.all_packed 를 돌려줄 뿐 · SO 상태는 안 바꾼다(packed 는 Finalize · ⑤-2b · 판정 18)
  select coalesce(v.all_packed, false) into v_ready from public.wms_order_pack_progress v where v.order_id = v_order_id;

  return jsonb_build_object(
    'completed', true,
    'worker', v_worker,
    'ready', v_ready,
    'lines_updated', v_lines_updated,
    'disc_inserted', v_disc_inserted,
    'short_refreshed', v_short_refreshed,
    'short_resolved', v_short_resolved,
    'recovered_resolved', v_recovered_resolved,
    'recovered_rows', v_recovered_rows);
end
$$;

-- ── wms_finalize ──
create or replace function public.wms_finalize(p_so_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_id uuid;  v_doc public.wms_order_doc%rowtype;  v_all boolean;  v_bad text;
  v_placed boolean;  v_units int;  v_nodim int;  v_type text;
  v_out jsonb := '[]'::jsonb;  v_warn text[] := '{}';
begin
  perform public.ims_require_write('fulfillment', 'saved');            -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  if p_so_ids is null or cardinality(p_so_ids) = 0 then raise exception 'No orders given — nothing was saved'; end if;
  -- ① 검사 전부(잠금 · 하나라도 막히면 전체 거부)
  foreach v_id in array p_so_ids loop
    perform 1 from public.so s where s.id = v_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
    perform 1 from public.inv_transfer x where x.id = v_id for update;             -- tr-1b2: 트랜스퍼 행 잠금(판정 72-3 의 짝 · 문서 id 는 둘 중 하나에만 맞는다)
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    if not found then raise exception 'Order not found (%) — nothing was saved', v_id; end if;
    if v_doc.doc_kind = 'transfer' then                                -- tr-1b2 판정 65: 출발(원장 · 레이어 · in_transit)은 ③ 에서 선다 — 그때까지 창고 마무리는 트랜스퍼를 받지 않는다(검사 전 · 아무것도 안 쓴다)
      raise exception 'Transfer % — departure is the next step and is not built yet — nothing was saved', v_doc.doc_number;
    end if;
    if not public.ims_can_warehouse(v_doc.warehouse_id) then          -- ⭐ 둘째
      raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_doc.doc_number;
    end if;
    if v_doc.status <> 'picking' then
      raise exception 'Order % is % — only an order in warehouse work (picking) can be finalized — nothing was saved', v_doc.doc_number, v_doc.status;
    end if;
    select coalesce(v.all_packed, false) into v_all from public.wms_order_pack_progress v where v.order_id = v_id;
    if not coalesce(v_all, false) then
      raise exception 'Order % — not every batch is picked and packed yet (%) — nothing was saved', v_doc.doc_number,
        coalesce((select v.packs_done || '/' || v.pick_batches || ' packed' from public.wms_order_pack_progress v where v.order_id = v_id), 'no pick tasks');
    end if;
    select string_agg(format('line %s: %s on pallets but %s packed', sl.line_no, pi.q, coalesce(pk.q, 0)), '; ' order by sl.line_no) into v_bad
    from (select coalesce(order_line_id, transfer_line_id) as order_line_id, sum(qty_base) as q from public.wms_pallet_items where coalesce(order_id, transfer_id) = v_id group by 1) pi
    join public.wms_order_doc_line sl on sl.line_id = pi.order_line_id
    left join (select coalesce(kl.order_line_id, kl.transfer_line_id) as order_line_id, sum(kl.verified_base) as q from public.wms_pack_task_lines kl join public.wms_pack_tasks k on k.id = kl.pack_task_id where coalesce(k.order_id, k.transfer_id) = v_id and k.status = 'completed' group by 1) pk on pk.order_line_id = pi.order_line_id
    where pi.q > coalesce(pk.q, 0);
    if v_bad is not null then raise exception 'Order % — more on pallets than was packed (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  end loop;
  -- ② 기록 + 전이
  foreach v_id in array p_so_ids loop
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    v_placed := exists (select 1 from public.wms_pallet_items pi where coalesce(pi.order_id, pi.transfer_id) = v_id);
    select count(*), count(*) filter (where u.length_in is null or u.width_in is null or u.height_in is null or u.weight_lb is null) into v_units, v_nodim
    from public.wms_pallets u where coalesce(u.order_id, u.transfer_id) = v_id or u.parent_id in (select p2.id from public.wms_pallets p2 where coalesce(p2.order_id, p2.transfer_id) = v_id);
    v_type := case when v_placed then 'packing_list' else 'direct' end;
    if v_nodim > 0 then v_warn := array_append(v_warn, format('units_without_dims:%s:%s', v_doc.doc_number, v_nodim)); end if;
    insert into public.wms_order_finalize (order_id, fulfillment_type, finalized_by, finalized_at, units, units_without_dims)
    values (v_id, v_type, v_staff, now(), v_units, v_nodim);
    perform public.wms_doc_status(v_doc.doc_kind, v_id, 'packed', v_staff);         -- tr-1b2(트랜스퍼는 위에서 거부됐다 · packed 짝은 ③)
    v_out := v_out || jsonb_build_object('so_id', v_id, 'so_number', v_doc.doc_number, 'fulfillment_type', v_type, 'units', v_units, 'units_without_dims', v_nodim,
                                         'shorts', (public.wms_so_handoff(v_id))->'shorts');
  end loop;
  return jsonb_build_object('finalized', v_out, 'count', jsonb_array_length(v_out), 'warnings', to_jsonb(v_warn));
end;
$$;

-- ── wms_so_handoff ──
create or replace function public.wms_so_handoff(p_so_id uuid) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_doc    public.wms_order_doc%rowtype;
  v_all    boolean;
  l        record;  b record;
  v_ship   numeric;  v_sum numeric;  v_cut numeric;
  v_bins   jsonb;  v_picks jsonb := '[]'::jsonb;  v_shorts jsonb := '[]'::jsonb;  v_units jsonb;
  v_nodim  int;
  i        int;
begin
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found'; end if;
  select coalesce(v.all_packed, false) into v_all from public.wms_order_pack_progress v where v.order_id = p_so_id;
  for l in
    select x.line_id as id, x.line_no, x.sku, x.pack_factor, x.qty_target as target,
           coalesce((select sum(kl.verified_base) from public.wms_pack_task_lines kl join public.wms_pack_tasks k on k.id = kl.pack_task_id
                     where coalesce(kl.order_line_id, kl.transfer_line_id) = x.line_id and k.status = 'completed'), 0) as verified_ea,
           coalesce((select jsonb_agg(jsonb_build_object('bin', g.bin, 'units', g.units) order by g.first_id)
                     from (select pb.bin, min(pb.id) as first_id, floor(sum(pb.qty_base) / x.pack_factor) as units
                           from public.wms_pick_line_bins pb join public.wms_pick_task_lines pl on pl.id = pb.pick_task_line_id join public.wms_pick_tasks t on t.id = pl.pick_task_id
                           where coalesce(pl.order_line_id, pl.transfer_line_id) = x.line_id and not pb.planned and t.status = 'completed' group by pb.bin) g), '[]'::jsonb) as bins
    from public.wms_order_doc_line x where x.doc_id = p_so_id order by x.line_no
  loop
    select coalesce(sum((e->>'units')::numeric), 0) into v_sum from jsonb_array_elements(l.bins) e;
    v_ship := least(v_sum, floor(l.verified_ea / l.pack_factor), l.target);
    if v_ship < 0 then v_ship := 0; end if;
    v_cut := v_sum - v_ship;  v_bins := l.bins;
    i := jsonb_array_length(v_bins) - 1;
    while v_cut > 0 and i >= 0 loop                              -- 마지막 칸부터 줄인다(⬜6)
      v_bins := jsonb_set(v_bins, array[i::text, 'units'], to_jsonb(greatest((v_bins->i->>'units')::numeric - v_cut, 0)));
      v_cut := v_cut - least(v_cut, (l.bins->i->>'units')::numeric);  i := i - 1;
    end loop;
    v_picks := v_picks || coalesce((select jsonb_agg(jsonb_build_object('line_id', l.id, 'bin', e->>'bin', 'qty', (e->>'units')::numeric)) from jsonb_array_elements(v_bins) e where (e->>'units')::numeric > 0), '[]'::jsonb);
    if v_ship < l.target then
      v_shorts := v_shorts || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'target', l.target, 'ship', v_ship);
    end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('unit_id', u.id, 'unit_type', u.unit_type, 'label', u.label, 'parent_unit_id', u.parent_id, 'status', u.status,
           'length_in', u.length_in, 'width_in', u.width_in, 'height_in', u.height_in, 'weight_lb', u.weight_lb, 'height_note', u.height_note, 'weight_note', u.weight_note,
           'items', coalesce((select jsonb_agg(jsonb_build_object('line_id', it.order_line_id, 'qty', round(it.qty / sl.pack_factor, 4), 'qty_base', it.qty) order by sl.line_no)
                              from (select coalesce(pi.order_line_id, pi.transfer_line_id) as order_line_id, sum(pi.qty_base) as qty from public.wms_pallet_items pi where pi.pallet_id = u.id and coalesce(pi.order_id, pi.transfer_id) = p_so_id group by 1) it
                              join public.wms_order_doc_line sl on sl.line_id = it.order_line_id), '[]'::jsonb)) order by u.parent_id nulls first, u.id), '[]'::jsonb),
         count(*) filter (where u.length_in is null or u.width_in is null or u.height_in is null or u.weight_lb is null)
    into v_units, v_nodim
  from public.wms_pallets u
  where coalesce(u.order_id, u.transfer_id) = p_so_id or u.parent_id in (select p2.id from public.wms_pallets p2 where coalesce(p2.order_id, p2.transfer_id) = p_so_id);
  return jsonb_build_object('so_id', v_doc.doc_id, 'so_number', v_doc.doc_number, 'status', v_doc.status, 'all_packed', v_all,
                            'picks', v_picks, 'units', v_units, 'shorts', v_shorts, 'units_without_dims', coalesce(v_nodim, 0));
end;
$$;

-- ── wms_rollback ──
create or replace function public.wms_rollback(p_so_id uuid, p_action text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_pack constant text[] := array['short_after_pack', 'over_pick', 'pack_scan_mistake'];
  v_staff uuid;  v_doc public.wms_order_doc%rowtype;  v_fin public.wms_order_finalize%rowtype;
  v_ids bigint[];  v_wids bigint[];  v_wid bigint;
  v_arch int := 0;  v_void int := 0;  v_reopen int := 0;  v_status text;  v_from text;  v_to text;  v_orig uuid;  i int;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');
  v_staff := public.so_current_staff();
  if p_action not in ('finalize', 'fulfillment', 'pack', 'pick', 'split') then raise exception 'Unknown rollback action % — nothing was saved', p_action; end if;
  perform 1 from public.so s where s.id = p_so_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
  perform 1 from public.inv_transfer x where x.id = p_so_id for update;             -- tr-1b2: 트랜스퍼 행 잠금(판정 72-3 의 짝 · 문서 id 는 둘 중 하나에만 맞는다)
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_doc.warehouse_id) then              -- ⭐ 둘째
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_doc.doc_number;
  end if;
  select * into v_fin from public.wms_order_finalize f where coalesce(f.order_id, f.transfer_id) = p_so_id;
  if p_action = 'finalize' then
    if v_doc.status <> 'packed' or v_fin.order_id is null then raise exception 'Order % is not finalized (%) — nothing was saved', v_doc.doc_number, v_doc.status; end if;
  else
    if v_doc.status = 'packed' or v_fin.order_id is not null then       -- SO-13893 벨트: Finalize 뒤에는 팩 · 픽 · 배치를 되돌리지 않는다
      raise exception 'Order % is finalized — use Undo Finalize first — nothing was saved', v_doc.doc_number;
    end if;
    if v_doc.status <> 'picking' then raise exception 'Order % is % — nothing to roll back here — nothing was saved', v_doc.doc_number, v_doc.status; end if;
  end if;
  v_status := v_doc.status;
  if p_action in ('finalize', 'fulfillment') then
    -- 팔렛 · 박스 · 담긴 것(운영 deleteFulfillmentRows) — 담긴 것 삭제 → 빈 유닛(담긴 것 0 · 자식 0) 삭제 · finalize 기록 삭제 · SO packed → picking
    v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_doc.doc_number, null, 'wms_pallet_items', format('coalesce(order_id, transfer_id) = %L', p_so_id));
    delete from public.wms_pallet_items where coalesce(order_id, transfer_id) = p_so_id;
    for i in 1 .. 2 loop                                               -- 두 단계: 빈 박스(자식) → 빈 팔렛(부모) · 담긴 것이 남은 유닛은 둔다(운영 deleteFulfillmentRows)
      v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_doc.doc_number, null, 'wms_pallets',
                  format('(coalesce(order_id, transfer_id) = %L or parent_id in (select id from public.wms_pallets where coalesce(order_id, transfer_id) = %L)) and not exists (select 1 from public.wms_pallet_items i where i.pallet_id = t.id) and not exists (select 1 from public.wms_pallets c where c.parent_id = t.id)', p_so_id, p_so_id));
      delete from public.wms_pallets u where (coalesce(u.order_id, u.transfer_id) = p_so_id or u.parent_id in (select id from public.wms_pallets where coalesce(order_id, transfer_id) = p_so_id))
        and not exists (select 1 from public.wms_pallet_items i where i.pallet_id = u.id) and not exists (select 1 from public.wms_pallets c where c.parent_id = u.id);
    end loop;
    if p_action = 'finalize' then
      v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_doc.doc_number, null, 'wms_order_finalize', format('coalesce(order_id, transfer_id) = %L', p_so_id));
      delete from public.wms_order_finalize where coalesce(order_id, transfer_id) = p_so_id;
      perform public.wms_doc_status(v_doc.doc_kind, p_so_id, 'picking', v_staff);   -- tr-1b2
      v_status := 'picking';  v_orig := v_fin.finalized_by;
    end if;
    v_from := case p_action when 'finalize' then 'finalized' else 'fulfilled' end;  v_to := 'pack_complete';
  elsif p_action = 'pack' then
    if exists (select 1 from public.wms_pallet_items i where coalesce(i.order_id, i.transfer_id) = p_so_id) then raise exception 'Order % has items on pallets — Undo Fulfillment first — nothing was saved', v_doc.doc_number; end if;
    select coalesce(array_agg(id), '{}') into v_ids from public.wms_pack_tasks where coalesce(order_id, transfer_id) = p_so_id;
    select assigned_to into v_orig from public.wms_pack_tasks where coalesce(order_id, transfer_id) = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_doc.doc_number, null, 'wms_pack_tasks', format('coalesce(order_id, transfer_id) = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_doc.doc_number, null, 'wms_pack_task_lines', format('pack_task_id = any(%L::bigint[])', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pack_task_id', v_ids, c_pack, 'pack rollback (order ' || v_doc.doc_number || ')');
    update public.wms_worker_mistakes set reason = 'short_pick', resolved_by = null, resolved_at = null   -- 팩 회복을 다시 연다(오더 단위 · 규칙 14 양방향)
     where coalesce(order_id, transfer_id) = p_so_id and reason = 'resolved_pack_recovery' and voided_at is null and not manager_resolved;
    get diagnostics v_reopen = row_count;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_doc.doc_number, null, 'wms_pick_line_bins', format('pack_task_id = any(%L::bigint[])', v_ids));   -- 판정 57: 팩 회복 칸 행도 팩과 함께 간다(archive → 삭제 · FK cascade 는 안전망)
    delete from public.wms_pick_line_bins where pack_task_id = any(v_ids);
    delete from public.wms_pack_tasks where coalesce(order_id, transfer_id) = p_so_id;   -- 줄은 cascade
    v_from := 'pack_complete';  v_to := 'pick_complete';
  elsif p_action = 'pick' then
    if exists (select 1 from public.wms_pack_tasks k where coalesce(k.order_id, k.transfer_id) = p_so_id) then raise exception 'Order % has packing — Undo Pack first — nothing was saved', v_doc.doc_number; end if;
    select coalesce(array_agg(id), '{}') into v_ids from public.wms_pick_tasks where coalesce(order_id, transfer_id) = p_so_id;
    select assigned_to into v_orig from public.wms_pick_tasks where coalesce(order_id, transfer_id) = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_doc.doc_number, null, 'wms_pick_tasks', format('coalesce(order_id, transfer_id) = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_doc.doc_number, null, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_doc.doc_number, null, 'wms_pick_line_bins', format('not planned and pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'pick reset (order ' || v_doc.doc_number || ')');
    delete from public.wms_pick_line_bins b where not b.planned and b.pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(v_ids));
    update public.wms_pick_task_lines set picked_base = 0, status = 'pending', verification_method = null, picked_at = null, picked_by = null where pick_task_id = any(v_ids);
    update public.wms_pick_tasks set status = 'pending', assigned_to = null, started_at = null, completed_at = null, completed_by = null, heartbeat_at = null, work_started = false, held_by = null, session_id = null where coalesce(order_id, transfer_id) = p_so_id;
    v_from := 'pick_complete';  v_to := 'pick_reset';
  else   -- split
    if exists (select 1 from public.wms_pack_tasks k where coalesce(k.order_id, k.transfer_id) = p_so_id) then raise exception 'Order % has packing — Undo Pack first — nothing was saved', v_doc.doc_number; end if;
    select coalesce(array_agg(id), '{}'), coalesce(array_agg(distinct wave_id) filter (where wave_id is not null), '{}') into v_ids, v_wids from public.wms_pick_tasks where coalesce(order_id, transfer_id) = p_so_id;
    select assigned_to into v_orig from public.wms_pick_tasks where coalesce(order_id, transfer_id) = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_pick_tasks', format('coalesce(order_id, transfer_id) = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_pick_line_bins', format('pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'split undo (order ' || v_doc.doc_number || ')');
    delete from public.wms_pick_tasks where coalesce(order_id, transfer_id) = p_so_id;   -- 줄 · 칸 행은 cascade
    foreach v_wid in array v_wids loop                                 -- 이 되돌리기로 빈 웨이브는 지운다(운영 doVoid 와 같다)
      if not exists (select 1 from public.wms_pick_tasks t where t.wave_id = v_wid) then
        v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_waves', format('id = %L', v_wid));
        delete from public.wms_waves where id = v_wid;
      end if;
    end loop;
    perform public.wms_doc_status(v_doc.doc_kind, p_so_id, 'at_wms', v_staff);   -- 과제 0 → 판정 18 · tr-1b2
    v_status := 'at_wms';  v_from := 'split';  v_to := 'unsplit';
  end if;
  insert into public.wms_rollback_log (order_id, transfer_id, order_number, action, from_stage, to_stage, performed_by, original_worker)
  values (case when v_doc.doc_kind = 'so' then p_so_id end, case when v_doc.doc_kind = 'transfer' then p_so_id end, v_doc.doc_number, p_action, v_from, v_to, v_staff, v_orig);
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_doc.doc_number, 'action', p_action, 'status', v_status, 'archived', v_arch, 'voided', v_void, 'reopened', v_reopen);
end;
$$;

-- ── wms_rollback_batch ──
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

-- ── wms_unwave ──
create or replace function public.wms_unwave(p_wave_id bigint) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_w public.wms_waves%rowtype;  v_ids bigint[];  v_oids uuid[];  v_id uuid;  v_doc public.wms_order_doc%rowtype;
  v_arch int := 0;  v_void int := 0;  v_back int := 0;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');
  v_staff := public.so_current_staff();
  select * into v_w from public.wms_waves w where w.id = p_wave_id for update;
  if not found then raise exception 'Wave not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_w.warehouse_id) then              -- ⭐ 둘째
    raise exception 'Wave % is at another warehouse — you are not set up for it — nothing was saved', v_w.label;
  end if;
  select coalesce(array_agg(t.id), '{}'), coalesce(array_agg(distinct coalesce(t.order_id, t.transfer_id)), '{}') into v_ids, v_oids from public.wms_pick_tasks t where t.wave_id = p_wave_id;
  foreach v_id in array v_oids loop
    perform 1 from public.so s where s.id = v_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
    perform 1 from public.inv_transfer x where x.id = v_id for update;             -- tr-1b2: 트랜스퍼 행 잠금(판정 72-3 의 짝 · 문서 id 는 둘 중 하나에만 맞는다)
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    if v_doc.status = 'packed' or exists (select 1 from public.wms_order_finalize f where coalesce(f.order_id, f.transfer_id) = v_id) then
      raise exception 'Order % in wave % is finalized — use Undo Finalize first — nothing was saved', v_doc.doc_number, v_w.label;
    end if;
    if exists (select 1 from public.wms_pack_tasks k where k.pick_task_id = any(v_ids) and coalesce(k.order_id, k.transfer_id) = v_id) then
      raise exception 'Order % in wave % already has packing — Undo Pack first — nothing was saved', v_doc.doc_number, v_w.label;
    end if;
  end loop;
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_pick_tasks', format('wave_id = %L', p_wave_id));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_pick_line_bins', format('pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_waves', format('id = %L', p_wave_id));
  v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'wave undo ' || v_w.label);
  delete from public.wms_pick_tasks where wave_id = p_wave_id;         -- 줄 · 칸 행 cascade
  delete from public.wms_waves where id = p_wave_id;
  foreach v_id in array v_oids loop                                    -- 과제 0 이 된 오더만 at_wms(판정 18)
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    if v_doc.status = 'picking' and not exists (select 1 from public.wms_pick_tasks t where coalesce(t.order_id, t.transfer_id) = v_id) then
      perform public.wms_doc_status(v_doc.doc_kind, v_id, 'at_wms', v_staff);  v_back := v_back + 1;   -- tr-1b2
    end if;
    insert into public.wms_rollback_log (order_id, transfer_id, order_number, action, from_stage, to_stage, performed_by, batch_label)
    values (case when v_doc.doc_kind = 'so' then v_id end, case when v_doc.doc_kind = 'transfer' then v_id end, v_doc.doc_number, 'unwave', 'wave', 'unsplit', v_staff, v_w.label);
  end loop;
  return jsonb_build_object('wave_id', p_wave_id, 'label', v_w.label, 'orders', cardinality(v_oids), 'tasks', cardinality(v_ids), 'back_to_at_wms', v_back, 'archived', v_arch, 'voided', v_void);
end;
$$;

-- ── wms_review_set ──
create or replace function public.wms_review_set(p_so_id uuid, p_reviewed boolean) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_doc public.wms_order_doc%rowtype;  v_r public.wms_order_review%rowtype;
begin
  perform public.ims_require_write('fulfillment', 'saved');            -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_doc.warehouse_id) then
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_doc.doc_number;
  end if;
  if v_doc.doc_kind = 'so' then
  insert into public.wms_order_review as r (order_id, reviewed, reviewed_by, reviewed_at, cleared_by, cleared_at)
  values (p_so_id, p_reviewed, case when p_reviewed then v_staff end, case when p_reviewed then now() end, case when not p_reviewed then v_staff end, case when not p_reviewed then now() end)
  on conflict (order_id) do update
    set reviewed    = excluded.reviewed,
        reviewed_by = case when excluded.reviewed then v_staff else r.reviewed_by end,
        reviewed_at = case when excluded.reviewed then now()   else r.reviewed_at end,
        cleared_by  = case when excluded.reviewed then r.cleared_by else v_staff end,
        cleared_at  = case when excluded.reviewed then r.cleared_at else now()   end
  returning * into v_r;
  else                                                                 -- tr-1b2: 트랜스퍼는 transfer_id 칸 · 같은 갱신(규칙 29 · 보통 유니크 wms_order_review_transfer_uq)
  insert into public.wms_order_review as r (transfer_id, reviewed, reviewed_by, reviewed_at, cleared_by, cleared_at)
  values (p_so_id, p_reviewed, case when p_reviewed then v_staff end, case when p_reviewed then now() end, case when not p_reviewed then v_staff end, case when not p_reviewed then now() end)
  on conflict (transfer_id) do update
    set reviewed    = excluded.reviewed,
        reviewed_by = case when excluded.reviewed then v_staff else r.reviewed_by end,
        reviewed_at = case when excluded.reviewed then now()   else r.reviewed_at end,
        cleared_by  = case when excluded.reviewed then r.cleared_by else v_staff end,
        cleared_at  = case when excluded.reviewed then r.cleared_at else now()   end
  returning * into v_r;
  end if;
  return to_jsonb(v_r) || jsonb_build_object('so_number', v_doc.doc_number);
end;
$$;

-- ═══ 5) 읽기 정책 — 창고 일 열쇠 넷(picking · packing · fulfillment · wms_manage · 묶음 9)이 트랜스퍼 문서 · 줄을 읽는다 ═══
--   tr-1a 의 정책(inv_transfer_select · ims_can_view('transfer'))은 그대로 두고 하나를 더한다(정책은 OR) · 판매는 so_select = true 라 창고가 다 읽는다 — 트랜스퍼는 문서 담당 열쇠에만 열려 있어
--   invoker 읽기 창구(wms_pick_lines · so_pick_plan · wms_so_handoff · inv_adjust_*)가 security_invoker 뷰를 거칠 때 창고 직원에게 빈 결과를 냈다(tr-1b2 시험 2회차 실측) · 창고 경계는 창구의 ims_can_warehouse 가 지킨다(읽기는 판매와 같은 넓이)
create policy inv_transfer_select_warehouse on public.inv_transfer for select to authenticated
  using (public.ims_can_view('picking') or public.ims_can_view('packing') or public.ims_can_view('fulfillment') or public.ims_can_view('wms_manage'));
create policy inv_transfer_line_select_warehouse on public.inv_transfer_line for select to authenticated
  using (public.ims_can_view('picking') or public.ims_can_view('packing') or public.ims_can_view('fulfillment') or public.ims_can_view('wms_manage'));
