-- ============================================================
-- Cin7 On Hold 감지 → WMS 보류 (2026-08-12 · 규칙 43)
-- ------------------------------------------------------------
-- 목적: 실수로 오더가 진행되는 것을 막는 안전장치. 유입 후 Cin7 에서
-- AdditionalAttribute1 이 바뀌어도 WMS 가 모르던 갭(dedup 이후 재조회 없음)을
-- hello 폴링의 Updated 비교(wms_orders.cin7_updated vs saleList.Updated)로 메운다.
--
-- hold_state 의미:
--   'on_hold'    = Cin7 AdditionalAttribute1 == 'On Hold' — 작업 화면에서 숨김 +
--                  다음 단계 진입 차단(진행 중인 것은 끝까지 허용 — 규칙 43)
--   'unexpected' = 보류 목록에도 정상 목록에도 없는 값 — 숨기지도 무시하지도 않고
--                  admin 에 원문 그대로 알림(매니저 판단). Cin7 이 정상 값으로
--                  돌아오면 다음 감지에서 자동 해소(on_hold 는 수동 재개 — 비대칭 의도)
--   null         = 정상
--
-- ⚠️ wms_orders.status 는 건드리지 않는다 — 보류는 "다음 단계 진입 차단"이라는
--    직교 플래그다. status 에 값을 추가하면 진행 뷰·롤백·Finalize 전부에 파급된다.
-- ⚠️ 별도 테이블이 아닌 이유: picker/packer/fulfillment 목록이 이미 wms_orders 를
--    임베드하므로 컬럼이면 조인 추가 0. (2026-08-12 설계 보고 B)
-- ============================================================

ALTER TABLE public.wms_orders
  ADD COLUMN IF NOT EXISTS hold_state text
    CONSTRAINT wms_orders_hold_state_check CHECK (hold_state IN ('on_hold','unexpected')),
  ADD COLUMN IF NOT EXISTS hold_progress text,
  ADD COLUMN IF NOT EXISTS hold_detected_at timestamptz,
  ADD COLUMN IF NOT EXISTS hold_releasable_at timestamptz;

COMMENT ON COLUMN public.wms_orders.hold_state IS
  'Cin7 보류 감지: on_hold(숨김+다음 단계 차단) | unexpected(admin 알림만) | null(정상). 해제: on_hold 는 admin 재개(hold_recheck — Cin7 재확인 후) 수동만, unexpected 는 Cin7 정상 복귀 시 자동 (2026-08-12 규칙 43)';
COMMENT ON COLUMN public.wms_orders.hold_progress IS
  '감지 시점의 AdditionalAttribute1 원문 — admin 이 그대로 표시한다("보류"로 뭉뚱그리지 않는다: On Hold 인지 예상 밖 값인지에 따라 매니저 대응이 다르다)';
COMMENT ON COLUMN public.wms_orders.hold_detected_at IS '최초 감지 시각 (재감지에도 유지)';
COMMENT ON COLUMN public.wms_orders.hold_releasable_at IS
  'Cin7 이 2.Release to WMS 로 복귀한 것을 폴링이 본 시각 — "재개 가능" 표시용. 자동 복귀는 하지 않는다(막는 건 자동·푸는 건 수동 — 의도적 비대칭)';
