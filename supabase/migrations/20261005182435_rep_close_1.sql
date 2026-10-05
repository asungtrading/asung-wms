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

-- ─────────────────────────────────────────────────────────────
-- 신고가 「어떻게 닫혔는지」 남기기 (Asung-IMS · rep-close-1 · 2026-10-05)
--   정본(뒤에 적는다): so-module §43 — §26 판정 58(팩에서 채워진 신고는 저절로 닫힌다 · 매니저가 「팩 과정에서 검수자가 해결」을 알 수 있게) · 59(미뤘다가 순서대로)
--                      · 판정 58 묶음 1 ~ 5(대화 Claude 안 · Caleb 2026-10-05 「좋아 그대로 가자」) — 이 파일은 묶음 2 · 4 · 5 의 DB 쪽 · 화면(묶음 1 · 3)은 rep-close-2
--   신고를 닫는 자리(2026-10-05 실측 · 마이그레이션 전수 + 테스트 DB pg_proc 본문 + asung-ims 64ae060 grep):
--     ① wms_complete_pack ④ p_short_resolve(sku 목록) — 팩에서 채워진 stock_short 를 팩커 이름으로 닫는다(창구) · p_recovered 는 칸 행(②′) + wms_worker_mistakes short_pick(⑤)만
--     ② inv_adjust_confirm — 신고에서 연 재고 조정을 확정하면 닫는다(창구 · inv_adjust_from_report 는 읽기 창구라 닫지 않는다)
--     ③ wms-admin.html Mark resolved — 표에 직접 update {resolved_by, resolved_at}(wa v1.15 · 2060 행 · 정책 auth_all)
--     다시 여는 길은 없다(wms_rollback 은 wms_worker_mistakes 만 다시 연다)
--   든 것: 1) 칸 넷 resolved_how(found_at_pack · adjusted · resolved) · resolved_qty · resolved_bin · resolved_doc + CHECK 둘(옛 행 = 전부 null 은 통과)
--         2) BEFORE UPDATE OF resolved_at 트리거 — 방법 없이 닫히면 'resolved'(③ 의 지금 화면이 그대로 기록된다 · 놓친 길의 안전망) · 다시 열리면 넷을 비운다
--         3) 창구 wms_report_resolve(신고 id) — 문 ims_require_write('wms_manage') · 이미 닫힌 신고 거부(지금 화면은 닫힌 신고를 다시 눌러도 누가·언제를 덮어쓴다) · rep-close-2 가 화면을 이리로 옮긴다
--         4) wms_complete_pack 재발행(20260928234815_transfer_1b2.sql 680 ~ 837 바이트 복사 · ④ 닫는 문장만) — found_at_pack · 수량 · 칸 = 이 팩의 회복 칸 행
--         5) inv_adjust_confirm 재발행(20260928151948_inv_adjust_a2_speed.sql 144 ~ 173 바이트 복사 · 닫는 문장만) — adjusted · ADJ 번호
--   ⚠️ 정책 · 권한 무접촉(auth_all 그대로 — 피커 · 팩커 · 리시버 화면이 선언을 직접 insert · delete 한다) · wms_reports_planned_empty_once(BEFORE INSERT · pick-shelf-1) 무접촉
--   ⚠️ 부분 유니크 인덱스 없음 · 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) 칸 — 닫힌 방법 · 몇 개 · 어느 칸 · 문서 번호 (묶음 2 · 4) ═══
--   found_at_pack: resolved_qty · resolved_bin 은 둘 다 있거나(회복 칸 행에서) 둘 다 없다(토트에서 찾음) · resolved_doc 없음
--   adjusted:      resolved_doc = ADJ 번호 · 수량 · 칸 없음(조정 문서가 들고 있다)
--   resolved:      셋 다 없음(Mark resolved)
--   null(옛 행 · 열린 행): 셋 다 없음 · 방법이 있으면 resolved_at 도 있어야 한다
alter table public.wms_reports
  add column resolved_how text,
  add column resolved_qty numeric,
  add column resolved_bin text,
  add column resolved_doc text;
alter table public.wms_reports
  add constraint wms_reports_resolved_how_ck check (resolved_how is null or resolved_how in ('found_at_pack', 'adjusted', 'resolved')),
  add constraint wms_reports_resolved_detail_ck check (
       (resolved_how is null and resolved_qty is null and resolved_bin is null and resolved_doc is null)
    or (resolved_how = 'found_at_pack' and resolved_at is not null and resolved_doc is null
        and ((resolved_qty is null and resolved_bin is null) or (resolved_qty > 0 and resolved_bin is not null)))
    or (resolved_how = 'adjusted' and resolved_at is not null and resolved_doc is not null and resolved_qty is null and resolved_bin is null)
    or (resolved_how = 'resolved' and resolved_at is not null and resolved_qty is null and resolved_bin is null and resolved_doc is null));
comment on column public.wms_reports.resolved_how is 'rep-close-1(판정 58 묶음 2): how the report was closed — found_at_pack (packer filled the line · wms_complete_pack) · adjusted (stock adjustment confirmed · inv_adjust_confirm) · resolved (Mark resolved · wms_report_resolve or a direct update) · null = still open or closed before this column existed';
comment on column public.wms_reports.resolved_qty is 'found_at_pack only: units the packer recovered from the shelf for this SKU (sum of this pack''s recovered bin rows) · null when the line was filled without a recovered bin row';
comment on column public.wms_reports.resolved_bin is 'found_at_pack only: bin(s) the recovered units came from (names · comma separated when more than one)';
comment on column public.wms_reports.resolved_doc is 'adjusted only: the stock adjustment number (ADJ-…) whose confirmation closed the report';

-- ═══ 2) 트리거 — 방법 없이 닫히면 resolved · 다시 열리면 비운다 (안전망 · ③ 의 지금 화면) ═══
create function public.wms_reports_resolved_how_stamp() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  if new.resolved_at is not null and old.resolved_at is null and new.resolved_how is null then
    new.resolved_how := 'resolved';                                                       -- 닫는 길이 방법을 안 적었다 = 손으로 닫기(wms-admin Mark resolved 직접 update · wa v1.15) · 창구 둘은 방법을 적어서 온다
  end if;
  if new.resolved_at is null and old.resolved_at is not null then
    new.resolved_how := null;  new.resolved_qty := null;  new.resolved_bin := null;  new.resolved_doc := null;   -- 다시 열면 방법도 비운다(지금 그런 길은 없다 · CHECK 가 방법만 남는 것을 막는다)
  end if;
  return new;
end
$$;
create trigger wms_reports_resolved_how_stamp before update of resolved_at on public.wms_reports for each row execute function public.wms_reports_resolved_how_stamp();
comment on function public.wms_reports_resolved_how_stamp() is
  'rep-close-1(판정 58 묶음 2): BEFORE UPDATE OF resolved_at — a report closed without resolved_how gets ''resolved'' (the WMS Admin Mark resolved direct update · safety net for any other path) · a report reopened loses the four closing columns';

-- ═══ 3) 창구 — Mark resolved (묶음 2 · rep-close-2 가 화면을 이리로 옮긴다) ═══
--   문 = WMS Admin 의 방(ims-auth.js 108 행 wms-admin.html → wms_manage · 카탈로그 min_role manager) · 창고 경계는 지금 화면과 같이 없다(Admin 이 me.access.warehouses 로 거른다)
--   이미 닫힌 신고는 거부 — 지금 화면의 직접 update 는 닫힌 신고를 다시 눌러도 resolved_by · resolved_at 을 덮어쓴다(발견 · rep-close-2 에서 화면이 이 창구로 오면 사라진다)
create function public.wms_report_resolve(p_report_id bigint) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.wms_reports%rowtype; v_now timestamptz := now();
begin
  perform public.ims_require_write('wms_manage', 'saved');                                -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  select * into v_r from public.wms_reports r where r.id = p_report_id for update;
  if not found then raise exception 'Report #% was not found — nothing was saved', p_report_id; end if;
  if v_r.resolved_at is not null then
    raise exception 'Report #% was already closed (%) — nothing was saved', p_report_id, coalesce(v_r.resolved_how, 'resolved');
  end if;
  update public.wms_reports set resolved_by = v_staff, resolved_at = v_now, resolved_how = 'resolved' where id = p_report_id;
  return jsonb_build_object('report_id', p_report_id, 'kind', v_r.kind, 'resolved_how', 'resolved', 'resolved_by', v_staff, 'resolved_at', v_now);
end
$$;
revoke all on function public.wms_report_resolve(bigint) from public, anon;   grant execute on function public.wms_report_resolve(bigint) to authenticated;
comment on function public.wms_report_resolve(bigint) is
  'rep-close-1(판정 58 묶음 2): WMS Admin Mark resolved — door ims_require_write(''wms_manage'') · closes one open report as resolved_how = resolved · refuses a report that is already closed · returns {report_id, kind, resolved_how, resolved_by, resolved_at}';

-- ═══ 4) wms_complete_pack 재발행 — 20260928234815_transfer_1b2.sql 680 ~ 837 바이트 복사(DB prosrc md5 1e85e7fb58883d66e1575d0a56729f7e 와 같음을 확인하고) · ④ 의 닫는 문장만 바뀐다 ═══
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

  -- rep-close-1(판정 58 묶음 2): 닫힌 방법 = found_at_pack · 몇 개 · 어느 칸 = 이 팩이 ②′ 에서 남긴 회복 칸 행(pack_task_id = 이 팩 · sku 로 합 · 칸 이름은 검증된 것) · 회복 행이 없는 sku(픽은 다 됐는데 팩커가 선언했다가 토트에서 찾음)는 둘 다 null
  update public.wms_reports d
     set resolved_by = v_worker, resolved_at = v_now,
         resolved_how = 'found_at_pack', resolved_qty = rc.qty, resolved_bin = rc.bin
    from jsonb_array_elements_text(coalesce(p_short_resolve, '[]'::jsonb)) as s(sku)
    left join (select sl.sku, sum(b.qty_base) as qty, string_agg(distinct b.bin, ', ' order by b.bin) as bin
                 from public.wms_pick_line_bins b join public.wms_pick_task_lines pl on pl.id = b.pick_task_line_id
                 join public.wms_order_doc_line sl on sl.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
                where b.pack_task_id = p_task_id group by sl.sku) rc on rc.sku = s.sku
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

-- ═══ 5) inv_adjust_confirm 재발행 — 20260928151948_inv_adjust_a2_speed.sql 144 ~ 173 바이트 복사(DB prosrc md5 2ec8c475b9215cb82045d9ef0d77828e 와 같음을 확인하고) · 묶음 9 의 닫는 문장만 바뀐다 ═══
create or replace function public.inv_adjust_confirm(p_adjust_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_a public.inv_adjust%rowtype; v_staff uuid; v_rej text[] := '{}'; v_on date; v_post jsonb; v_rep int := 0; v_e record; v_deltas jsonb := '{}'::jsonb;
begin
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id for update;             -- 머리 잠금 — 같은 문서 두 번 확정 방지
  if not found then raise exception 'Adjustment not found — nothing was saved'; end if;
  v_staff := public.inv_adjust_require(v_a.warehouse_id);                                   -- ⭐ 첫 줄 문
  if v_a.status <> 'draft' then raise exception 'Adjustment % is already % — nothing was saved', v_a.adjust_number, v_a.status; end if;
  if not exists (select 1 from public.inv_adjust_line l where l.adjust_id = p_adjust_id) then raise exception 'Adjustment % has no lines — nothing was saved', v_a.adjust_number; end if;
  -- 줄마다 다시 읽는다 — 음수 · 본 값 달라짐(장부 · P) · 칸 → 하나라도 막히면 전체 거부(사람 문장)
  -- adj-a2(판정 54 C): eval 한 번 — for update 뒤 읽은 그 값 하나로 거부 판정과 delta 굳힘을 같이 한다(옛 판은 두 번 읽어 둘 사이에 원장이 바뀔 수 있었다 · CAS 가 약해지지 않는다)
  for v_e in select * from public.inv_adjust_eval(p_adjust_id) loop
    v_rej := v_rej || v_e.rejects;  v_deltas := v_deltas || jsonb_build_object(v_e.line_id::text, v_e.delta);
  end loop;
  select coalesce(array_agg(x order by x), '{}') into v_rej from unnest(v_rej) as x;
  if cardinality(v_rej) > 0 then raise exception 'Adjustment % cannot be confirmed: % — reload and check the lines — nothing was saved', v_a.adjust_number, array_to_string(v_rej, '; '); end if;
  v_on := public.ims_today();
  update public.inv_adjust_line l set delta = (v_deltas ->> l.id::text)::numeric where l.adjust_id = p_adjust_id and v_deltas ? l.id::text;   -- delta 0 줄도 굳힌다(원장 행은 없다 · Cin7 규칙)
  update public.inv_adjust set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now(), posted_on = v_on, updated_by = v_staff where id = p_adjust_id;
  v_post := public.inv_post_adjust(p_adjust_id);                                            -- 원장 + 원가 레이어 · 같은 트랜잭션 · 실패하면 확정도 안 된다
  if v_a.report_id is not null then                                                         -- 묶음 9 — 열린 신고를 닫는다(이미 닫힌 것은 무변)
    update public.wms_reports set resolved_by = v_staff, resolved_at = now(), resolved_how = 'adjusted', resolved_doc = v_a.adjust_number   -- rep-close-1(판정 58 묶음 2): 닫힌 방법 = adjusted · ADJ 번호
     where id = v_a.report_id and kind = 'stock_short' and resolved_at is null;
    get diagnostics v_rep = row_count;
  end if;
  return jsonb_build_object('adjust_id', v_a.id, 'adjust_number', v_a.adjust_number, 'status', 'confirmed', 'posted_on', v_on,
                            'ledger', v_post, 'report_id', v_a.report_id, 'report_resolved', v_rep = 1);
end;
$$;

-- ═══ 6) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'wms_reports' and column_name in ('resolved_how', 'resolved_qty', 'resolved_bin', 'resolved_doc')) <> 4 then v_bad := v_bad || ' columns'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.wms_reports'::regclass and conname in ('wms_reports_resolved_how_ck', 'wms_reports_resolved_detail_ck')) <> 2 then v_bad := v_bad || ' checks'; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.wms_reports'::regclass and tgname = 'wms_reports_resolved_how_stamp') then v_bad := v_bad || ' trigger'; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.wms_reports'::regclass and tgname = 'wms_reports_planned_empty_once') then v_bad := v_bad || ' pick-shelf-1-trigger-lost'; end if;
  if to_regprocedure('public.wms_report_resolve(bigint)') is null then v_bad := v_bad || ' window'; end if;
  if (select count(*) from pg_proc p where p.oid in (to_regprocedure('public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb, text)'), to_regprocedure('public.inv_adjust_confirm(uuid)')) and p.prosrc like '%resolved_how%') <> 2 then v_bad := v_bad || ' reissues'; end if;
  if exists (select 1 from public.wms_reports where resolved_how is not null or resolved_qty is not null or resolved_bin is not null or resolved_doc is not null) then v_bad := v_bad || ' old-rows-touched'; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'wms_reports') <> 1 then v_bad := v_bad || ' policies'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM058', message = format('STOP - rep-close-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
