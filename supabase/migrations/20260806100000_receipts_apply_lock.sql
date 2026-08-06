-- Apply in-flight 잠금 컬럼 (규칙 27 R4 — 이중 Apply 차단, 2026-08-06)
--
-- plan 시점의 applied_at 검사는 read-then-check 라, Cin7 쓰기가 도는 수 초~수십 초 동안
-- 두 번째 Apply(새로고침 재시도 · 매니저 2명 동시 · 네트워크 절단 후 재시도)를 못 막았다.
-- EF receiving 의 applyCommit 이 조건부 PATCH(원자 UPDATE)로 선점한다:
--   ① apply_lock_at IS NULL 인 행에만 세팅 → 1행이면 획득
--   ② 0행이면 90초(APPLY_LOCK_STALE_MS) 경과 잠금을 eq CAS 로 탈취(EF 사망 자동 회복 — WARN 로그)
--   ③ 둘 다 0행 → 차단 ("started {t} by {who}" — 누가 실행 중인지 반드시 표시)
-- 해제는 회차 종료 PATCH 에 병합. 순차 재시도 3종(청크 반복·부분 실패 재개·retry_failed=1)은
-- 회차마다 획득→해제라 막히지 않는다.
--
-- "동시 실행 금지"는 유니크 제약으로 표현할 수 없어(단일 행 상태 전이) 컬럼 + 조건부 UPDATE 가
-- PostgREST 로 가능한 가장 강한 형태다. advisory lock 은 커넥션 풀링에서 세션 보증이 없어 부적합.
-- PO·트랜스퍼 공통 사용(2026-08-06 같은 날 트랜스퍼 확장 — 델타 수량 mini transfer 는 duplicate
-- 거부가 없어 동시 실행이면 진짜 이중 이동이라 PO 보다 위험했다).

alter table public.wms_receipts add column if not exists apply_lock_at timestamptz;
alter table public.wms_receipts add column if not exists apply_lock_by text;

comment on column public.wms_receipts.apply_lock_at is
  'Apply in-flight lock (R4): set atomically at applyCommit start (PO path), cleared in the end-of-round PATCH; stale after 90s';
comment on column public.wms_receipts.apply_lock_by is
  'who holds the in-flight Apply lock - shown in the "already running" block message';
