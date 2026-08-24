-- 자동 Hold (2026-08-24 · B 단계) — wms_auto_hold() 신설: 작업자가 Hold 를 안 누르고
-- 사라진 배치를 서버가 자동으로 보류 처리한다. Stats 계산 교체(C)는 다음 단계 · 화면 무변.
--
-- 배경: 작업시간 = (completed_at − started_at) − Hold 구간 합. A 단계(20260824192416)가
--   수동 Hold 를 기록하기 시작했지만, Hold 버튼을 안 누르고 사라진 구간은 아무도 기록하지
--   않아 작업시간에 통째로 들어간다.
--
-- 사용자 확정 (2026-08-24):
--  · 판정 = 마지막 활동 후 10분 (Caleb 규칙: "10분 자리를 뜰 거면 Hold 를 눌러야 한다" —
--    자동 Hold 는 안 눌렀을 때의 안전망). ⚠️ 상수는 아래 c_after 한 곳.
--    ⚠️ [실측 2026-08-24] 스캔 간격 분포(8/21~8/24 · 426행)에 10~15분 공백 1건 · 15분+ 0건 —
--    10분이면 그 1건이 오탐으로 걸린다. 배포 후 며칠 현장 청취로 15분 상향 여부를 판단한다.
--    ⚠️ [실측 2026-08-24 토론토 오후 5시경] 「10분 경과 in_progress」 = pick·pack 모두 0건 —
--    켜자마자 대량 발동하는 최악은 배제. 단 스냅샷 1회라 시간대 편향 가능 — 10분이 옳다는
--    증명이 아니라 "그때 물릴 배치가 없었다"는 것. 실제 판단은 배포 후 현장 청취.
--  · 그 10분은 작업시간에 포함 — held_at = 마지막 활동 + 10분 (insert 시각이 아니다.
--    사라진 걸 나중에 아는 구조라 마지막 활동 직후 10분은 일한 것으로 인정).
--    잡이 2분 주기라 감지는 10~12분 뒤 = held_at 은 항상 과거 시각 — resumed_at(재개 now)보다
--    항상 이르므로 역전 없음.
--  · started_at 을 지우지 않는다 — 기존 reaper 와의 결정적 차이(reaper 의 started_at=null 이
--    SO-15028-1(229라인 4.1분)의 원인 경로였다).
--  · 재진입 = Resume — held_by 에 원 소유자를 찍으므로 기존 재개 3곳(startBatch·startWave·
--    resumePack)이 이력을 그대로 닫는다(닫기 UPDATE 는 source 를 보지 않는다 — 의도).
--
-- ⚠️ reaper 관계 = 흡수 (2026-08-24 사용자 확정 — 선택지 가·나·다 중 나):
--    reaper(클레임+3분 무스캔)가 잡던 부류는 이 판정(마지막 활동 = 클레임 시각 폴백 + 10분)에
--    자연 포함된다. 공존(가)은 hold 재개 직후 무스캔 배치에 두 잡이 겹쳐 순서에 따라 결과가
--    달라지고(reaper 가 항상 먼저 물어 started_at=null — SO-15028-1 잔존), started_at=null 만
--    제거(다)해도 회수된 구간이 이력 없이 작업시간에 남는다.
--    ⇒ wms_reap_stale_claims 함수는 존치(baseline 무접촉 — 호출 0), cron 잡 2 는 unschedule
--    (supabase/ops/cron.sql 기록 · 사람이 직접). work_started 는 이제 서버에서 읽는 코드 0
--    (프론트 didWork·목록 필터만 남음 — 무접촉).
--
-- 동작 = 상태 플립 + 이력 insert 뿐 — 라인은 만질 필요가 없다:
--  · 모든 입력(스캔·스텝퍼·수동)이 saveLine 한 관문으로 즉시 증분 저장된다(picker:1324·
--    packer:1287) — 수동 Hold RPC 의 라인 저장이 "최종 flush 일 뿐"인 것과 같은 근거(20260807:13).
--  · 화면을 열어둔 채 물린 작업자의 다음 입력은 ensureMine(규칙 28)이 freezeScreen 으로 차단 —
--    로컬 수량은 flush 하지 않는다(스테일). 전용 안내 문구는 프론트 커밋(같은 날) 참조.
--
-- 안전장치 3겹:
--  ① 킬 스위치 = select cron.alter_job(<jobid>, active := false);  -- 즉시·배포 불필요
--  ② 회차 전체 상한 20건(c_cap) — 정상 운영에서 한 회차 수십 건은 판정 이상 신호. 상한에서
--    멈추면 피해 반경이 캡되고 나머지는 2분 뒤 다음 회차가 처리.
--    ⚠️ 처리 순서 = last_activity 오름차순(오래된 것 먼저 · 사용자 지시) — limit 만 있으면
--    어느 20건인지 비결정적이라 같은 배치가 영영 뒤로 밀릴 수 있다. 부문(pick→pack→wave) 내
--    정렬 + 전체 예산 차감 — 부문 간 완전 정렬은 플립이 테이블별이라 하지 않는다(상한이 차는
--    것 자체가 이상 상황이고 다음 회차가 2분 뒤라 과설계).
--  ③ 기록 = wms_task_holds 의 source='auto' 행 자체가 감사 로그. 유실·불일치는 health
--    hold_leak(20260824192416 · sort 130)가 auto 행도 동일하게 잡는다.
--
-- ⚠️ worker 컬럼 의미 재정의: "Hold 누른 사람" → **"멈춤 시점의 소유자"**
--    (source='manual' 이면 누른 사람과 동일 · 'auto' 면 시스템이 그 사람 몫을 대신 멈춘 것 —
--    그 사람은 버튼을 누르지 않았다. 구분자는 source). held_by 에 같은 값을 찍어야
--    "⏸ Resume your held" 카드·재개 경로가 성립한다.
--
-- 판정·플립 사이 경합: 플립 UPDATE 가 판정 CTE 를 FROM 으로 물고 status/assigned_to 를
-- 재확인(CAS)한다 — 그 사이 재개·완료된 배치는 0행. 판정 스냅샷 직후 스캔이 끼면 held_at 이
-- 실제보다 이를 수 있으나(분 단위) 재개가 곧 닫으므로 수용.
--
-- 배포: supabase db reset 로컬 검증 → supabase db push (사람이 직접) → cron 잡 교체(ops/cron.sql).

create or replace function public.wms_auto_hold()
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  c_after constant interval := interval '10 minutes';  -- ⚠️ 판정 상수 — 유일한 자리 (경위는 파일 헤더)
  c_cap   constant int := 20;                          -- 회차 전체 상한 (안전장치 ②)
  v_budget int := c_cap;                               -- 남은 예산 (c_cap 에서 차감 — 값 중복 금지)
  v_n int;
  w record;
  v_members int;
  v_flipped int;
begin
  -- ── 1) 단일 픽 (wave 멤버 제외 — wave 는 3)에서 wave 단위로) ──
  with stale as (
    select t.id, t.assigned_to,
           greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz),
                    coalesce(t.started_at,     'epoch'::timestamptz),
                    coalesce(t.heartbeat_at,   'epoch'::timestamptz),
                    t.created_at) as last_activity
      from wms_pick_tasks t
      left join wms_pick_task_lines l on l.pick_task_id = t.id
     where t.status = 'in_progress' and t.wave_id is null and t.assigned_to is not null
     group by t.id
    having greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz),
                    coalesce(t.started_at,     'epoch'::timestamptz),
                    coalesce(t.heartbeat_at,   'epoch'::timestamptz),
                    t.created_at) < now() - c_after
     order by 3 asc                                    -- 오래된 것 먼저 (안전장치 ② 순서)
     limit v_budget                                    -- 남은 예산 (첫 부라 = c_cap · 전 부 동일 표기 — 새 부를 추가할 때도 이것)
  ),
  flipped as (
    update wms_pick_tasks t
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = s.assigned_to
      from stale s
     where t.id = s.id and t.status = 'in_progress' and t.assigned_to = s.assigned_to  -- CAS 재확인
    returning t.id, s.assigned_to as worker, s.last_activity
  )
  insert into wms_task_holds (task_kind, task_id, worker, held_at, source)
  select 'pick', f.id, f.worker, f.last_activity + c_after, 'auto' from flipped f;
  get diagnostics v_n = row_count;
  v_budget := v_budget - v_n;
  if v_budget <= 0 then return; end if;

  -- ── 2) 팩 ──
  with stale as (
    select t.id, t.assigned_to,
           greatest(coalesce(max(l.verified_at), 'epoch'::timestamptz),
                    coalesce(t.started_at,       'epoch'::timestamptz),
                    coalesce(t.heartbeat_at,     'epoch'::timestamptz),
                    t.created_at) as last_activity
      from wms_pack_tasks t
      left join wms_pack_task_lines l on l.pack_task_id = t.id
     where t.status = 'in_progress' and t.assigned_to is not null
     group by t.id
    having greatest(coalesce(max(l.verified_at), 'epoch'::timestamptz),
                    coalesce(t.started_at,       'epoch'::timestamptz),
                    coalesce(t.heartbeat_at,     'epoch'::timestamptz),
                    t.created_at) < now() - c_after
     order by 3 asc
     limit v_budget                                    -- 남은 예산 (pick 부에서 차감된 값)
  ),
  flipped as (
    update wms_pack_tasks t
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = s.assigned_to
      from stale s
     where t.id = s.id and t.status = 'in_progress' and t.assigned_to = s.assigned_to
    returning t.id, s.assigned_to as worker, s.last_activity
  )
  insert into wms_task_holds (task_kind, task_id, worker, held_at, source)
  select 'pack', f.id, f.worker, f.last_activity + c_after, 'auto' from flipped f;
  get diagnostics v_n = row_count;
  v_budget := v_budget - v_n;
  if v_budget <= 0 then return; end if;

  -- ── 3) wave — wave 행 단위 판정·이력(A 단계 계약: 멤버별 N행 금지), 플립은 행+멤버 전부 ──
  --    수동 RPC 의 「행 수 불일치 = 예외 전체 롤백」을 여기서 그대로 쓰면 cron 회차 전체가
  --    조용히 실패를 반복한다 → wave 별 루프에서 선검사 후 어긋난 wave 는 skip(무접촉 —
  --    다음 회차 재시도 · 어긋남 자체는 health wave_state/hold_leak 가 잡는다).
  for w in
    select wv.id, wv.assigned_to,
           greatest(coalesce(max(l.picked_at),  'epoch'::timestamptz),
                    coalesce(wv.started_at,     'epoch'::timestamptz),
                    coalesce(wv.heartbeat_at,   'epoch'::timestamptz),
                    wv.created_at) as last_activity
      from wms_waves wv
      left join wms_pick_tasks t on t.wave_id = wv.id
      left join wms_pick_task_lines l on l.pick_task_id = t.id
     where wv.status = 'in_progress' and wv.assigned_to is not null
     group by wv.id
    having greatest(coalesce(max(l.picked_at),  'epoch'::timestamptz),
                    coalesce(wv.started_at,     'epoch'::timestamptz),
                    coalesce(wv.heartbeat_at,   'epoch'::timestamptz),
                    wv.created_at) < now() - c_after
     order by 3 asc
     limit v_budget
  loop
    exit when v_budget <= 0;
    -- 선검사: 멤버 전원이 in_progress + 같은 소유자일 때만 (수동 RPC 의 원자성 요건과 동치)
    select count(*), count(*) filter (where status = 'in_progress' and assigned_to = w.assigned_to)
      into v_members, v_flipped
      from wms_pick_tasks where wave_id = w.id;
    if v_members = 0 or v_flipped <> v_members then
      continue;  -- 어긋난 wave — 이번 회차 skip (health 가 잡는다)
    end if;
    -- wave 행 CAS — 그 사이 재개·완료됐으면 0행 = skip
    update wms_waves
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = w.assigned_to
     where id = w.id and status = 'in_progress' and assigned_to = w.assigned_to;
    if not found then continue; end if;
    update wms_pick_tasks
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = w.assigned_to
     where wave_id = w.id and status = 'in_progress' and assigned_to = w.assigned_to;
    insert into wms_task_holds (task_kind, task_id, worker, held_at, source)
    values ('wave', w.id, w.assigned_to, w.last_activity + c_after, 'auto');
    v_budget := v_budget - 1;
  end loop;
end
$$;

-- cron(postgres 소유자)만 부른다 — 프론트가 남의 배치를 자동 Hold 시키는 경로 차단
revoke all on function public.wms_auto_hold() from public;
revoke all on function public.wms_auto_hold() from anon;
revoke all on function public.wms_auto_hold() from authenticated;
