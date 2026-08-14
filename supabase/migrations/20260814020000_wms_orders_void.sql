-- ============================================================
-- Cin7 void 감지 (2026-08-14 — 백로그 「Cin7 void 감지」 · 규칙 43 과 같은 뿌리)
-- ------------------------------------------------------------
-- 실사고 SO-14015: 07-31 유입 → 08-04 15:30 Cin7 void → WMS 는 ready_to_close 로
-- 9일 방치(08-13 admin 지체 목록 59h 빨강으로 사람이 발견) → 수동 ⊘ Void.
--
-- void 는 hold 와 감지 구조가 다르다(2026-08-14 GAS 실측): void 된 sale 은
-- saleList?OrderStatus=AUTHORISED 목록에서 **빠진다**(무필터엔 남고 Status 등이 VOIDED).
-- hold 의 Updated 트리거는 "목록에 있는 행의 변화"를 보므로 구조적으로 못 본다 —
-- hello 폴링이 반대 방향(활성 오더 중 목록에 없는 것)을 대조하고, 연속 2회차 부재
-- + saleList?Search 확정 조회(Status='VOIDED' 판정)를 거쳐 여기 기록한다.
--
-- cin7_void_state 의미:
--   'voided'     = 확정 조회 Status='VOIDED' — 안 잡은 배치는 대기 풀에서 숨김 +
--                  다음 단계 진입 차단 + **진행 중 화면엔 빨간 배너**(사용자 결정 —
--                  hold 처럼 숨기면 실물이 토트에 남는다. void 는 종착이라 "나중에
--                  풀린다"가 없다). 중단 여부는 작업자가 아니라 매니저가 정한다.
--   'gone_other' = AUTHORISED 목록에서 빠졌는데 Status 가 VOIDED 가 아님
--                  (FULFILLED/CLOSED 등 다른 종착, 또는 NOT_IN_CIN7) — admin 표시만.
--   null         = 정상.
--
-- ⚠️ status 컬럼은 건드리지 않는다 — hold 가 직교 플래그를 쓴 것과 같은 이유.
--    status='voided' 전환은 매니저의 ⊘ Void 수동 실행만이 한다(아카이브·다층 삭제가
--    얽힌 검증된 경로 + 실물 회수(토트→선반)는 사람이 지시해야 한다).
--    감지는 자동·처분은 수동 — 규칙 43 의 비대칭 원칙과 동일.
--
-- ⚠️ CHECK 를 거는 근거(사용자 결정 2026-08-14): hold_state 전례와 동일. 나중에
--    gone_other 를 fulfilled/closed 로 세분하고 싶어질 수 있는데, 그때 마이그레이션이
--    필요한 것이 오히려 안전장치다(reason CHECK 전례 — 새 값은 마이그레이션이
--    코드보다 먼저).
-- ============================================================

ALTER TABLE public.wms_orders
  ADD COLUMN IF NOT EXISTS cin7_void_state text
    CONSTRAINT wms_orders_cin7_void_state_check CHECK (cin7_void_state IN ('voided','gone_other')),
  ADD COLUMN IF NOT EXISTS cin7_void_detected_at timestamptz,
  ADD COLUMN IF NOT EXISTS cin7_gone_status text,
  ADD COLUMN IF NOT EXISTS cin7_gone_missing_since timestamptz;

COMMENT ON COLUMN public.wms_orders.cin7_void_state IS
  'Cin7 void 감지: voided(대기 풀 숨김+다음 단계 차단+진행 중 빨간 배너) | gone_other(admin 표시만) | null(정상). 해제: AUTHORISED 목록 재등장 시 폴링이 자동 해제, 확정 후 처분은 매니저 ⊘ Void 수동만 (2026-08-14)';
COMMENT ON COLUMN public.wms_orders.cin7_void_detected_at IS
  '확정 조회로 voided/gone_other 판정한 시각 (완충 2회차 통과 후)';
COMMENT ON COLUMN public.wms_orders.cin7_gone_status IS
  '확정 조회(saleList?Search)에서 본 Status 원문(VOIDED·FULFILLED 등 대문자). ⚠️ NOT_IN_CIN7 만 예외 — Search 에도 없는 경우(문서가 통째로 사라짐)에 우리가 붙이는 값. 언더스코어가 "Cin7 원문 아님" 표식';
COMMENT ON COLUMN public.wms_orders.cin7_gone_missing_since IS
  'AUTHORISED 목록에서 처음 안 보인 시각 — 연속 2회차 완충용(1회차는 기록만, 2회차 부재만 확정 조회. 재등장 시 null 복귀). 목록 누락 글리치를 void 로 오판하지 않기 위한 것';
