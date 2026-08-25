-- Hold 닫기 RPC — wms_resume_hold (2026-08-25 · C 단계 선행 수정)
--
-- 배경 [실측 2026-08-25]: held_at 은 서버 시계(Hold RPC default now() · 자동 Hold 는
-- last_activity + c_after)인데 resumed_at 은 프론트가 new Date() 로 만든 **태블릿 시계**였다
-- (6a98247 의 닫기 UPDATE). 20행 중 11행에서 resumed_at < held_at (약 −1.2초 — 그 태블릿이
-- 서버보다 느리다). 지금은 무해하지만 C 단계는 이 구간을 빼는 계산이다 — 태블릿 시계가 몇 분
-- 틀어지면 Hold 시간이 통째로 엉뚱해지고 에러 없이 조용히 틀린다.
--
-- 채택 = 닫기 전용 RPC (후보 B · 2026-08-25 Caleb 확정):
--  · 트리거(후보 A)는 기각 — 프론트가 보낸 값을 서버가 조용히 덮는 형태라 나중에 코드만 보고
--    "프론트 값이 저장된다"고 착각한다. 게다가 애플리케이션 트리거 0 은 이 프로젝트의 앵커
--    지표다(asung-wms 스킬 앵커 표). RPC 는 값의 출처가 함수 본문에 보인다.
--  · 부수 이득이 채택 이유의 절반: **resumed_by 도 서버 유도**(auth.email → wms_staff.name —
--    Hold RPC 와 같은 관례). 종전엔 Hold 는 서버 유도인데 닫기만 프론트 me.name 신뢰였다(비대칭).
--  · only-if-null 가드(resumed_at is null) 그대로 — 이미 닫힌 행 재덮어쓰기 없음.
--  · ⚠️ 과거 11행의 음수는 보존한다(사실 기록) — C 계산이 greatest(0, …) 클램프로 방어.
--
-- 호출: 재개 프론트 3곳(picker startBatch·startWave · packer resumePack)이 fire-and-forget 으로
-- 부른다 — 기록 실패가 작업을 막지 않는다(닫힘 유실은 health hold_leak 이 잡는다).

create or replace function public.wms_resume_hold(
  p_task_kind text,     -- 'pick' | 'pack' | 'wave' (wms_task_holds.task_kind)
  p_task_id   bigint
) returns int           -- 닫은 행 수 (0 = 열린 행 없음 — 신규 시작·롤백 복귀의 정상 no-op)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_worker text;
  v_n int;
begin
  -- 재개자 = 서버 유도 (wms_hold_pick 과 같은 행·같은 컬럼)
  select s.name into v_worker from wms_staff s where s.email = auth.email();
  if v_worker is null then
    raise exception 'No staff record for this login (%) — nothing was closed', coalesce(auth.email(), 'no email');
  end if;

  update wms_task_holds
     set resumed_at = now(),        -- ⚠️ 서버 시계 — 이 함수의 존재 이유 (파일 헤더)
         resumed_by = v_worker
   where task_kind = p_task_kind and task_id = p_task_id and resumed_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end
$$;

-- EXECUTE — PUBLIC 기본 부여 회수 후 authenticated 만 (Hold RPC 와 동일 관례)
revoke all on function public.wms_resume_hold(text, bigint) from public;
revoke all on function public.wms_resume_hold(text, bigint) from anon;
grant execute on function public.wms_resume_hold(text, bigint) to authenticated, service_role;
