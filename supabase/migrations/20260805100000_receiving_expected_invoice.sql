-- ============================================================
-- 리시빙 기대치 기준 전환: order → invoice (2026-08-05, 규칙 20 개정)
-- ------------------------------------------------------------
-- expected_source: 이 receipt 의 expected_base 가 어느 문서 기준인지.
--   'order'   = PO 오더 라인 수량 (종전 방식 · 인보이스 폴백)
--   'invoice' = authorize 된 공장 인보이스 라인 수량 (신규 기본)
--   기존 행은 전부 'order'(DEFAULT) — 같은 컬럼에 두 기준 값이 표식 없이
--   섞이면 나중에 discrepancy 해석이 불가능해진다.
--
-- cin7_type: Cin7 purchaseList 의 Type ("Simple Purchase"/"Advanced Purchase").
--   Apply 인보이스 게이트가 상세 엔드포인트(/purchase vs /advanced-purchase)를
--   고르는 근거 — GET /purchase/invoice 는 Advanced 에서 400 (deprecated, 실측
--   2026-08-05)이라 상세 응답의 Invoice 블록으로 전환했다.
--   기존 행은 NULL → Simple(/purchase)로 간주 — 종전 게이트도 Simple 전용
--   엔드포인트였으므로 회귀 없음.
--
-- ⚠️ 배포 순서: 이 SQL 먼저 → EF(receiving) 배포 → receiver.html 푸시 (규칙 23).
--    컬럼 없이 프론트가 먼저 나가면 startPo 의 receipt insert 가 실패한다.
-- ============================================================

ALTER TABLE public.wms_receipts
  ADD COLUMN IF NOT EXISTS expected_source text NOT NULL DEFAULT 'order'
    CONSTRAINT wms_receipts_expected_source_check
    CHECK (expected_source IN ('order', 'invoice')),
  ADD COLUMN IF NOT EXISTS cin7_type text;

COMMENT ON COLUMN public.wms_receipts.expected_source IS
  'expected_base 기준 문서: order(오더 라인·폴백) | invoice(공장 인보이스 라인, 2026-08-05 부터 기본)';
COMMENT ON COLUMN public.wms_receipts.cin7_type IS
  'Cin7 purchaseList Type (Simple/Advanced Purchase) — Apply 인보이스 게이트의 상세 엔드포인트 선택용. NULL=Simple 간주(구형 receipt)';
