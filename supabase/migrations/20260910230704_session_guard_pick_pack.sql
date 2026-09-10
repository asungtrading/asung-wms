-- 같은 사람 · 다중 기기(탭) 차단 — ① 픽·팩 (2026-09-10 · 규칙 28 소절)
-- 설계 정본: docs/sessions/2026-09-10-multi-device-guard/v5_3-design.md
-- 경위:      docs/sessions/2026-09-10-same-user-multi-device-guard-reverted.md (§5 되돌린 이유 · §6 최대 위험)
--
-- 문제: 같은 사람이 같은 배치를 두 기기에서 열면 checkOwner(who===me.name)가 통과하고,
--       완료·Hold RPC 가 그 화면의 로컬 스냅샷으로 전 라인을 덮어써 다른 기기의 픽이 0 으로 돌아간다.
--       두 사람이면 CAS(assigned_to = v_worker)가 막는데 같은 사람만 뚫린다.
-- 해법: 「한 작업(배치·wave·팩)은 한 화면에서만 열린다」 — 화면(탭)마다 sessionStorage UUID 를 두고
--       클레임·재개 때 행에 쓴다(새 화면이 이긴다). 완료·Hold RPC 의 CAS 가 그 값을 대조한다.
--
-- 바꾸는 것 셋만 (함수 원문은 통째 복사 — diff 는 v5_4 보고서 §2 와 동일: +14/−3 · +14/−3 · +8/−2 · +8/−2):
--   (a) 마지막 파라미터 `p_session_id text default null`
--   (b) CAS where 에 `and (p_session_id is null or 행.session_id is null or 행.session_id = p_session_id)` 한 줄
--       · p_session_id null   = 옛 클라이언트(DB 만 먼저 나간 배포 창) 호환 — 종전 동작
--       · 행.session_id null  = 배포 전 클레임(레거시) 통과 — 다음 클레임/재개에서 채워진다
--       ⚠️ wave 멤버 UPDATE 에는 넣지 않는다(레거시 wave 「n of m matched」 예외 방지 — 설계 §7)
--   (c) 0행 반환에 'reason' — 같은 사람·in_progress 인데 세션만 다르면 'other_device', 그 외 null
--
-- ⚠️⚠️ 시그니처가 바뀌므로 create or replace 는 새 오버로드를 만든다 — 옛 시그니처를 drop 하지 않으면
--      PostgREST 가 옛 호출(p_session_id 생략)을 모호하다고 거부 ⇒ 완료·Hold 전면 실패.
--      drop → 재생성 → revoke/grant 를 한 마이그레이션 안에서(drop 뒤 ACL 은 보존되지 않는다).
--      선례: 20260909174046 의 drop function if exists inv_layer_apply_po_in(bigint, date).
-- ⚠️ 배포 순서 DB → HTML 절대 준수(규칙 23). 새 HTML 이 옛 RPC 를 만나면 400.

-- ① 세션 컬럼 — nullable. 릴리스(Hold·자동 Hold·admin 롤백)에서 지우지 않는다(모든 클레임이 덮어쓴다 ·
--    남겨두면 「마지막으로 잡았던 화면」 기록). 상태(누가·어느 화면이 잡고 있나)는 서버에 — 이 컬럼.
--    정체(이 탭이 누구인가)는 탭의 sessionStorage 에 — wmsAuth.sessionId().
alter table public.wms_pick_tasks add column if not exists session_id text;
alter table public.wms_waves      add column if not exists session_id text;
alter table public.wms_pack_tasks add column if not exists session_id text;
comment on column public.wms_pick_tasks.session_id is '마지막으로 이 배치를 연 화면(탭)의 세션 UUID (2026-09-10 · 규칙 28). 완료·Hold RPC CAS 가 대조. null = 배포 전 클레임(통과).';
comment on column public.wms_waves.session_id      is '마지막으로 이 wave 를 연 화면(탭)의 세션 UUID (2026-09-10 · 규칙 28). wave 행이 CAS 단위 — 멤버 task 의 값은 참고용.';
comment on column public.wms_pack_tasks.session_id is '마지막으로 이 팩을 연 화면(탭)의 세션 UUID (2026-09-10 · 규칙 28). 완료·Hold RPC CAS 가 대조. null = 배포 전 클레임(통과).';

-- ② 옛 시그니처 drop (전수 grep 2026-09-10 재확인 — 최신 정의: complete_pick 20260806160000 ·
--    hold_pick 20260824192416 · complete_pack/hold_pack 20260825193231 · 그 뒤 재정의 없음)
drop function if exists public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb);
drop function if exists public.wms_hold_pick(jsonb, bigint, bigint);
drop function if exists public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb);
drop function if exists public.wms_hold_pack(bigint, jsonb);

-- ③ 재생성 — 원문(위 파일) 통째 + (a)(b)(c)

-- ── wms_complete_pick (원문 20260806160000_wms_complete_pick_rpc.sql) ──
create or replace function public.wms_complete_pick(
  p_lines         jsonb,                  -- [{id, picked_base, status('picked'|'short'), verification_method|null}]
  p_task_id       bigint default null,    -- 단일 모드
  p_wave_id       bigint default null,    -- wave 모드 (둘 중 정확히 하나)
  p_disc          jsonb default '[]',     -- [{order_id, pick_task_id|null, sku, ordered_base, actual_base}] → short_pick
  p_short_refresh jsonb default '[]',     -- [{order_id, sku, ordered_base, actual_base}] — 선언·여전히 부족
  p_short_delete  jsonb default '[]',     -- [{order_id, sku}] — 선언했지만 채움 (stale delete)
  p_session_id    text default null     -- 화면 세션 (2026-09-10 · 다중 기기 차단). null = 옛 클라이언트(배포 창) 호환 · 행의 session_id 가 null(배포 전 클레임)이면 통과
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_worker  text;
  v_now     timestamptz := now();
  v_flipped bigint;
  v_task_ids  bigint[];
  v_order_ids bigint[];
  v_member_total     int := 0;
  v_members_completed int := 0;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
  v_disc_inserted  int := 0;
  v_short_refreshed int := 0;
  v_short_deleted   int := 0;
begin
  if (p_task_id is null) = (p_wave_id is null) then
    raise exception 'Pass exactly one of p_task_id / p_wave_id — nothing was saved';
  end if;

  -- 작업자 = 서버 유도 (wms-auth.js:170 과 같은 행·같은 컬럼 → me.name 과 같은 문자열)
  select s.name into v_worker from wms_staff s where s.email = auth.email();
  if v_worker is null then
    raise exception 'No staff record for this login (%) — nothing was saved', coalesce(auth.email(), 'no email');
  end if;

  if p_wave_id is not null then
    -- ① CAS = wave 행 (소유권 단위). 첫 쓰기 — 0행이면 아무것도 안 썼다.
    update wms_waves w
       set status = 'completed', completed_at = v_now
     where w.id = p_wave_id and w.assigned_to = v_worker and w.status = 'in_progress'
       and (p_session_id is null or w.session_id is null or w.session_id = p_session_id)
    returning w.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('completed', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from wms_waves x where x.id = p_wave_id));
    end if;

    -- ② 멤버 = 서버 유도 (wave 행 잠금 아래) → 일괄 플립. 행 수 ≠ 멤버 수 = 전체 롤백.
    select coalesce(array_agg(id), '{}') into v_task_ids
      from wms_pick_tasks where wave_id = p_wave_id;
    v_member_total := coalesce(array_length(v_task_ids, 1), 0);
    if v_member_total = 0 then
      raise exception 'Wave % has no member batches — nothing was saved. Ask a manager', p_wave_id;
    end if;
    update wms_pick_tasks t
       set status = 'completed', completed_at = v_now, completed_by = v_worker
     where t.wave_id = p_wave_id and t.assigned_to = v_worker;
    get diagnostics v_members_completed = row_count;
    if v_members_completed <> v_member_total then
      raise exception 'Wave completion failed: % of % member batches matched (a member may have been taken over or released) — nothing was saved. Ask a manager before retrying',
        v_members_completed, v_member_total;
    end if;
  else
    -- ① 단일 모드 CAS — 팩과 동형
    update wms_pick_tasks t
       set status = 'completed', completed_at = v_now, completed_by = v_worker
     where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
       and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
    returning t.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('completed', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from wms_pick_tasks x where x.id = p_task_id));
    end if;
    v_task_ids := array[p_task_id];
  end if;

  select coalesce(array_agg(distinct order_id), '{}') into v_order_ids
    from wms_pick_tasks where id = any(v_task_ids);

  -- ⚠️ 귀속 가드 — 완료 범위 밖 order/task 가 실려 오면 예외 = 전체 롤백(플립 포함).
  perform 1 from jsonb_array_elements(coalesce(p_disc, '[]'::jsonb)) d
   where not ((d->>'order_id')::bigint = any(v_order_ids))
      or (d->>'pick_task_id' is not null and not ((d->>'pick_task_id')::bigint = any(v_task_ids)))
   limit 1;
  if found then
    raise exception 'Discrepancy row outside this pick scope (wrong order or batch) — nothing was saved';
  end if;
  perform 1 from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where not ((r->>'order_id')::bigint = any(v_order_ids)) limit 1;
  if found then
    raise exception 'Stock-short refresh outside this pick scope — nothing was saved';
  end if;
  perform 1 from jsonb_array_elements(coalesce(p_short_delete, '[]'::jsonb)) r
   where not ((r->>'order_id')::bigint = any(v_order_ids)) limit 1;
  if found then
    raise exception 'Stock-short cleanup outside this pick scope — nothing was saved';
  end if;

  -- ③ 라인 최종 저장 — pick_task_id 조건 = 타 배치 오염 차단
  update wms_pick_task_lines l
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

  -- ④ short_pick 생성 — reason 고정 · order_number 는 서버 유도
  insert into wms_discrepancies
        (order_id, pick_task_id, order_number, sku, ordered_base, actual_base, reason, cin7_corrected)
  select (d->>'order_id')::bigint, (d->>'pick_task_id')::bigint, o.order_number, d->>'sku',
         (d->>'ordered_base')::numeric, (d->>'actual_base')::numeric, 'short_pick', false
    from jsonb_array_elements(coalesce(p_disc, '[]'::jsonb)) d
    join wms_orders o on o.id = (d->>'order_id')::bigint;
  get diagnostics v_disc_inserted = row_count;

  -- ⑤ 선언(stock_short) 정리 — UPDATE/DELETE 0행 = 자연 no-op (기존 best-effort 의미)
  update wms_discrepancies d
     set ordered_base = (r->>'ordered_base')::numeric, actual_base = (r->>'actual_base')::numeric
    from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where d.order_id = (r->>'order_id')::bigint and d.sku = r->>'sku'
     and d.reason = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_refreshed = row_count;

  delete from wms_discrepancies d
   using jsonb_array_elements(coalesce(p_short_delete, '[]'::jsonb)) r
   where d.order_id = (r->>'order_id')::bigint and d.sku = r->>'sku'
     and d.reason = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_deleted = row_count;

  return jsonb_build_object(
    'completed', true,
    'worker', v_worker,
    'mode', case when p_wave_id is not null then 'wave' else 'single' end,
    'members_completed', v_members_completed,
    'lines_updated', v_lines_updated,
    'disc_inserted', v_disc_inserted,
    'short_refreshed', v_short_refreshed,
    'short_deleted', v_short_deleted);
end
$$;


-- ── wms_hold_pick (원문 20260824192416_task_holds.sql) ──
create or replace function public.wms_hold_pick(
  p_lines   jsonb,                 -- [{id, picked_base, status('picked'|'in_progress'|'pending'), verification_method|null}]
  p_task_id bigint default null,   -- 단일 모드
  p_wave_id bigint default null,   -- wave 모드 (둘 중 정확히 하나)
  p_session_id    text default null     -- 화면 세션 (2026-09-10 · 다중 기기 차단). null = 옛 클라이언트(배포 창) 호환 · 행의 session_id 가 null(배포 전 클레임)이면 통과
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_worker  text;
  v_flipped bigint;
  v_task_ids bigint[];
  v_member_total int := 0;
  v_members_held int := 0;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
begin
  if (p_task_id is null) = (p_wave_id is null) then
    raise exception 'Pass exactly one of p_task_id / p_wave_id — nothing was saved';
  end if;

  -- 작업자 = 서버 유도 (wms-auth.js:170 과 같은 행·같은 컬럼 → me.name 과 같은 문자열)
  select s.name into v_worker from wms_staff s where s.email = auth.email();
  if v_worker is null then
    raise exception 'No staff record for this login (%) — nothing was saved', coalesce(auth.email(), 'no email');
  end if;

  if p_wave_id is not null then
    -- ① CAS = wave 행 (소유권 단위 — 규칙 18/28). 첫 쓰기 — 0행이면 아무것도 안 썼다.
    update wms_waves w
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
     where w.id = p_wave_id and w.assigned_to = v_worker and w.status = 'in_progress'
       and (p_session_id is null or w.session_id is null or w.session_id = p_session_id)
    returning w.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('held', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from wms_waves x where x.id = p_wave_id));
    end if;

    -- ② 멤버 = 서버 유도 (wave 행 잠금 아래) → 일괄 플립. 행 수 ≠ 멤버 수 = 전체 롤백.
    select coalesce(array_agg(id), '{}') into v_task_ids
      from wms_pick_tasks where wave_id = p_wave_id;
    v_member_total := coalesce(array_length(v_task_ids, 1), 0);
    if v_member_total = 0 then
      raise exception 'Wave % has no member batches — nothing was saved. Ask a manager', p_wave_id;
    end if;
    update wms_pick_tasks t
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
     where t.wave_id = p_wave_id and t.assigned_to = v_worker;
    get diagnostics v_members_held = row_count;
    if v_members_held <> v_member_total then
      raise exception 'Hold failed: % of % member batches matched (a member may have been taken over or released) — nothing was saved. Ask a manager before retrying',
        v_members_held, v_member_total;
    end if;
  else
    -- ① 단일 모드 CAS — 완료와 동형(방향만 반대)
    update wms_pick_tasks t
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
     where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
       and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
    returning t.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('held', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from wms_pick_tasks x where x.id = p_task_id));
    end if;
    v_task_ids := array[p_task_id];
  end if;

  -- ③ 라인 최종 저장 — pick_task_id 스코프 = 타 배치 오염 차단.
  --    행 수 ≠ 배열 길이 = 예외 = 플립 포함 전체 롤백(위 헤더의 사용자 결정).
  update wms_pick_task_lines l
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
    raise exception 'Line save failed: found % of % lines — lines may have been removed by a rollback. Nothing was held. Ask a manager before retrying',
      v_lines_updated, v_lines_expected;
  end if;

  -- ④ Hold 구간 이력 (2026-08-24) — wave 는 wave 행 1건(멤버별 N행 금지 — 파일 헤더 근거).
  --    resumed_at 은 재개 프론트 3곳이 닫는다. 여기가 마지막 문장이라 실패 시 Hold 전체가 롤백.
  insert into wms_task_holds (task_kind, task_id, worker)
  values (case when p_wave_id is not null then 'wave' else 'pick' end,
          coalesce(p_wave_id, p_task_id), v_worker);

  return jsonb_build_object(
    'held', true,
    'worker', v_worker,
    'mode', case when p_wave_id is not null then 'wave' else 'single' end,
    'members_held', v_members_held,
    'lines_updated', v_lines_updated);
end
$$;


-- ── wms_complete_pack (원문 20260825193231_preserve_verification_method.sql) ──
create or replace function public.wms_complete_pack(
  p_task_id       bigint,
  p_lines         jsonb,                  -- [{id, verified_base, status('verified'|'mismatch'), verification_method|null}]
  p_disc          jsonb default '[]',     -- [{sku, reason('short_after_pack'|'over_pick'|'pack_scan_mistake'), ordered_base, actual_base}]
  p_short_refresh jsonb default '[]',     -- [{sku, ordered_base, actual_base}] — 선언 라인의 열린 stock_short 수량 갱신
  p_short_resolve jsonb default '[]',     -- ["sku"] — 선언했지만 채워진 라인 → stock_short 해소
  p_recovered     jsonb default '[]',     -- ["sku"] — 팩에서 회복 → short_pick 을 resolved_pack_recovery 로
  p_session_id    text default null     -- 화면 세션 (2026-09-10 · 다중 기기 차단). null = 옛 클라이언트(배포 창) 호환 · 행의 session_id 가 null(배포 전 클레임)이면 통과
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_worker  text;
  v_now     timestamptz := now();
  v_order_id       bigint;
  v_pick_task_id   bigint;
  v_order_number   text;
  v_picker         text;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
  v_disc_inserted  int := 0;
  v_short_refreshed    int := 0;
  v_short_resolved     int := 0;
  v_recovered_resolved int := 0;
  v_ready       boolean := false;
  v_ready_error text := null;
  v_total int;
  v_done  int;
  v_bad   text;
begin
  -- 작업자 = 서버 유도. 정확 일치(eq) — wms-auth.js 의 조회와 같은 의미
  -- (로그인이 성립했다면 auth 이메일과 wms_staff.email 은 정확히 같다).
  select s.name into v_worker from wms_staff s where s.email = auth.email();
  if v_worker is null then
    raise exception 'No staff record for this login (%) — nothing was saved', coalesce(auth.email(), 'no email');
  end if;

  -- 페이로드 검증: 이 함수가 만들 수 있는 reason 3종만 (플립 전 — 실패 시 아무것도 안 씀)
  select d->>'reason' into v_bad
    from jsonb_array_elements(coalesce(p_disc, '[]'::jsonb)) d
   where d->>'reason' not in ('short_after_pack', 'over_pick', 'pack_scan_mistake')
   limit 1;
  if v_bad is not null then
    raise exception 'Reason "%" is not allowed in pack completion — nothing was saved', v_bad;
  end if;

  -- ① CAS 플립 먼저 (2026-08-06 배포 조건 그대로: assigned_to + in_progress).
  --    0행 = 아무것도 쓴 것이 없다 → 예외가 아니라 조용한 반환. worker 를 실어
  --    프론트가 me.name 과 대조해 "직원 이름 변경" 드리프트를 구분한다.
  update wms_pack_tasks t
     set status = 'completed', completed_at = v_now, completed_by = v_worker
   where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
     and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
  returning t.order_id, t.pick_task_id into v_order_id, v_pick_task_id;

  if v_order_id is null then
    return jsonb_build_object('completed', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from wms_pack_tasks x where x.id = p_task_id));
  end if;

  select o.order_number into v_order_number from wms_orders o where o.id = v_order_id;
  select pt.assigned_to into v_picker from wms_pick_tasks pt where pt.id = v_pick_task_id;

  -- ② 라인 최종 저장 — 진짜 UPDATE (7단계 upsert 의 23502 문제 없음).
  --    pack_task_id 조건 = 다른 태스크 라인 오염 차단.
  update wms_pack_task_lines l
     set verified_base = r.vb, status = r.st,
         -- 방법 보존 (2026-08-25): null 이 오면 기존값 유지 — 새 값이 오면 항상 새 값(정당한 변경 통과)
         verification_method = coalesce(r.vm, l.verification_method),
         -- 스캔 시점 verified_at 보존 (2026-08-21 — 라인 시각 편승 1단계): packer saveLine 이 스캔마다
         -- 찍은 값이 있으면 유지, 스캔 0 라인(최종 flush 만 탄 것)은 종전대로 완료 시각.
         -- 소비처는 값이 항상 채워진다는 기대 유지 — coalesce 라 null 로 남는 라인 없음.
         verified_at = coalesce(l.verified_at, v_now)
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
    -- 예외 = 전체 롤백(플립 포함). 원인 없는 메시지는 작업자가 계속 다시 누르게 만든다.
    raise exception 'Line save failed: found % of % lines — lines may have been removed by a rollback. Nothing was saved. Ask a manager before retrying',
      v_lines_updated, v_lines_expected;
  end if;

  -- ③ discrepancy 생성 — 현행 코드와 같은 컬럼 모양 (reason 별 템플릿).
  --    responsible(=픽커)은 서버 유도: wms_pick_tasks.assigned_to (packer.html 의
  --    best-effort enrich 와 같은 출처, 더 신뢰).
  insert into wms_discrepancies
        (order_id, pack_task_id, order_number, sku, ordered_base, actual_base, reason,
         source, responsible, declared_by, resolved_by, resolved_at, cin7_corrected)
  select v_order_id, p_task_id, v_order_number, d->>'sku',
         (d->>'ordered_base')::numeric, (d->>'actual_base')::numeric, d->>'reason',
         case when d->>'reason' = 'pack_scan_mistake' then 'packing' end,
         case when d->>'reason' in ('short_after_pack', 'over_pick') then v_picker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_worker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_worker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_now end,
         false
    from jsonb_array_elements(coalesce(p_disc, '[]'::jsonb)) d;
  get diagnostics v_disc_inserted = row_count;

  -- ④ 선언(stock_short) 정리 — UPDATE 0행 = 자연스러운 no-op (기존 best-effort 의미 그대로)
  update wms_discrepancies d
     set ordered_base = (r->>'ordered_base')::numeric, actual_base = (r->>'actual_base')::numeric
    from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where d.order_id = v_order_id and d.sku = r->>'sku'
     and d.reason = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_refreshed = row_count;

  update wms_discrepancies d
     set resolved_by = v_worker, resolved_at = v_now
    from jsonb_array_elements_text(coalesce(p_short_resolve, '[]'::jsonb)) as s(sku)
   where d.order_id = v_order_id and d.sku = s.sku
     and d.reason = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_resolved = row_count;

  -- ⑤ 팩에서 회복된 부족 → short_pick 해소. voided 행은 되살리지 않는다(2026-08-06 롤백 무효화).
  update wms_discrepancies d
     set resolved_by = v_worker, resolved_at = v_now, reason = 'resolved_pack_recovery'
    from jsonb_array_elements_text(coalesce(p_recovered, '[]'::jsonb)) as s(sku)
   where d.order_id = v_order_id and d.sku = s.sku
     and d.reason = 'short_pick' and d.resolved_at is null and d.voided_at is null;
  get diagnostics v_recovered_resolved = row_count;

  -- ⑥ ready 판정 (checkOrderReady 상당) — 비치명 서브블록: 실패해도 완료는 커밋.
  begin
    select count(*) into v_total from wms_pick_tasks where order_id = v_order_id;
    select count(distinct pick_task_id) into v_done
      from wms_pack_tasks where order_id = v_order_id and status = 'completed';
    if v_total > 0 and v_done >= v_total then
      update wms_orders
         set status = 'ready_to_close', notified_at = v_now
       where id = v_order_id
         and status in ('pending', 'picking', 'packing', 'ready_to_close');  -- 멱등 가드 — 0행 정상
      v_ready := true;
    end if;
  exception when others then
    v_ready := false;
    v_ready_error := sqlerrm;
  end;

  return jsonb_build_object(
    'completed', true,
    'worker', v_worker,
    'ready', v_ready,
    'ready_error', v_ready_error,
    'lines_updated', v_lines_updated,
    'disc_inserted', v_disc_inserted,
    'short_refreshed', v_short_refreshed,
    'short_resolved', v_short_resolved,
    'recovered_resolved', v_recovered_resolved);
end
$$;


-- ── wms_hold_pack (원문 20260825193231_preserve_verification_method.sql) ──
create or replace function public.wms_hold_pack(
  p_task_id bigint,
  p_lines   jsonb,                 -- [{id, verified_base, status('verified'|'in_progress'|'pending'), verification_method|null}]
  p_session_id    text default null     -- 화면 세션 (2026-09-10 · 다중 기기 차단). null = 옛 클라이언트(배포 창) 호환 · 행의 session_id 가 null(배포 전 클레임)이면 통과
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_worker  text;
  v_flipped bigint;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
begin
  select s.name into v_worker from wms_staff s where s.email = auth.email();
  if v_worker is null then
    raise exception 'No staff record for this login (%) — nothing was saved', coalesce(auth.email(), 'no email');
  end if;

  -- ① CAS 플립 먼저 — 0행 = 무기록 {held:false, worker} (재호출 멱등)
  update wms_pack_tasks t
     set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
   where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
     and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
  returning t.id into v_flipped;
  if v_flipped is null then
    return jsonb_build_object('held', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from wms_pack_tasks x where x.id = p_task_id));
  end if;

  -- ② 라인 최종 저장 — pack_task_id 스코프 + 행 수 검사 = 전체 롤백
  update wms_pack_task_lines l
     set verified_base = r.vb, status = r.st,
         -- 방법 보존 (2026-08-25 — 완료 RPC 와 같은 한 줄 · 파일 헤더)
         verification_method = coalesce(r.vm, l.verification_method)
    from (
      select (e->>'id')::bigint                    as id,
             (e->>'verified_base')::numeric        as vb,
             e->>'status'                          as st,
             nullif(e->>'verification_method', '') as vm
        from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
    ) r
   where l.id = r.id and l.pack_task_id = p_task_id;
  get diagnostics v_lines_updated = row_count;
  if v_lines_updated <> v_lines_expected then
    raise exception 'Line save failed: found % of % lines — lines may have been removed by a rollback. Nothing was held. Ask a manager before retrying',
      v_lines_updated, v_lines_expected;
  end if;

  -- ③ Hold 구간 이력 (2026-08-24 — wms_hold_pick ④ 와 동일 원칙)
  insert into wms_task_holds (task_kind, task_id, worker)
  values ('pack', p_task_id, v_worker);

  return jsonb_build_object(
    'held', true,
    'worker', v_worker,
    'lines_updated', v_lines_updated);
end
$$;


-- ④ ACL 재설정 — 새 시그니처. 함수 EXECUTE 는 PUBLIC 기본 부여라 명시 revoke(20260806160000 패턴).
--    drop 뒤 재생성이라 종전 grant 는 보존되지 않는다 — 여기서 반드시 다시 건다.
revoke all on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text) from public;
revoke all on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text) from anon;
grant execute on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text) to authenticated, service_role;

revoke all on function public.wms_hold_pick(jsonb, bigint, bigint, text) from public;
revoke all on function public.wms_hold_pick(jsonb, bigint, bigint, text) from anon;
grant execute on function public.wms_hold_pick(jsonb, bigint, bigint, text) to authenticated, service_role;

revoke all on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb, text) from public;
revoke all on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb, text) from anon;
grant execute on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb, text) to authenticated, service_role;

revoke all on function public.wms_hold_pack(bigint, jsonb, text) from public;
revoke all on function public.wms_hold_pack(bigint, jsonb, text) from anon;
grant execute on function public.wms_hold_pack(bigint, jsonb, text) to authenticated, service_role;
