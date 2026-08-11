-- ============================================================
-- 폴링 "확인했으나 비대상" 기억 테이블 (2026-08-11 — 백로그 17번)
-- ------------------------------------------------------------
-- hello EF 의 오더 폴링이 매 회차 같은 비대상 오더(~51건)의 /sale 상세를
-- 다시 읽는 낭비(회차당 52콜 · 하루 ~15,000콜 · 25초 버스트 = 트랜스퍼
-- Apply 429 의 원인)를 없앤다. saleList 의 `Updated` 를 변경 트리거로:
--   스킵 = 기억에 있고 AND Updated 가 저장값과 정확히 같고 AND 확인 1시간 이내
-- ⚠️ Updated 는 "릴리즈됐다"가 아니라 "뭔가 바뀌었으니 읽어봐라"다 —
--    판정(AdditionalAttribute1='2.Release to WMS')은 언제나 상세조회가 한다.
-- ⚠️ 기록은 "상세조회 성공 + 비대상 판정"일 때만 — 안 읽은 것을 기억하면
--    Updated 가 다시 바뀔 때까지 영영 안 읽힌다(hello EF 의 기록 지점 주석).
--
-- ⚠️ PK 는 평범한 PK — 부분 유니크 인덱스 금지 (PostgREST on_conflict 가
--    깨진다. 규칙 29 — wms_discrepancies 실사고).
-- ⚠️ upsert 페이로드에는 NOT NULL 전 컬럼을 실을 것 — NOT NULL 검사가
--    ON CONFLICT 해소보다 먼저 돈다 (2026-08-06 배치 upsert 프로덕션 실패).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.wms_polled_sales (
  cin7_sale_id  text PRIMARY KEY,
  order_number  text,
  last_progress text,
  cin7_updated  text NOT NULL,
  checked_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.wms_polled_sales IS
  '폴링 "확인했으나 비대상" 기억 (hello EF · 2026-08-11). 스킵 = Updated 정확 일치 + TTL(1시간) 이내. 행 부재 = 다음 회차에 상세조회(안전 방향).';
COMMENT ON COLUMN public.wms_polled_sales.cin7_updated IS
  'saleList 의 Updated 문자열 그대로 (⚠️ timestamptz 파싱 금지 — .29Z/.290Z 형식 차이가 흡수되어 "다른데 같다" 오판. 정확 문자열 비교만).';
COMMENT ON COLUMN public.wms_polled_sales.last_progress IS
  '마지막 상세조회에서 본 AdditionalAttribute1 (예 ''1.New Order''). ⚠️ 진단 전용 · 판정에 쓰지 말 것 — 이 값으로 스킵 판정을 하면 목록만으로 릴리즈를 판단하는 셈이 되어 설계가 무너진다.';
COMMENT ON COLUMN public.wms_polled_sales.checked_at IS
  '마지막 상세조회 시각. 스킵은 쓰기가 없으므로 활성 비대상 오더는 TTL(1시간) 주기로 갱신된다 — 30일 미갱신 = 목록에서 빠진 지 오래 = purge 대상.';

-- RLS — wms_ 테이블 컨벤션 (규칙 8). hello EF 는 service_role 이라 우회하지만 컨벤션 유지.
ALTER TABLE public.wms_polled_sales ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS auth_all ON public.wms_polled_sales;
CREATE POLICY auth_all ON public.wms_polled_sales
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
