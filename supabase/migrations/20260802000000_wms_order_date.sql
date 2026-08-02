-- 픽리스트에 주문일(Order Date) 표시 — 현장 요청 (2026-08-02)
--
-- 출처: Cin7 Core 화면의 "Order Date" = API `OrderDate`
--   · /saleList 항목:  c.OrderDate  ("2024-01-15T00:00:00")
--   · /sale 상세:      d.OrderDate
--   기존 ship_by 와 같은 취급 — 앞 10자만 잘라 date 로 저장한다.
--
-- ⚠️ 규칙 23 의 교훈: 컬럼 추가를 EF 배포보다 **먼저** 할 것.
--    폴링 EF(hello)가 order_date 를 실으면서 컬럼이 없으면 wms_orders insert 가 통째로 실패한다.
--    순서: ① 이 마이그레이션 push  ② supabase functions deploy hello
--
-- 기존 오더는 NULL 로 남는다 → 인쇄물에서 Order Date 줄이 생략되고,
-- 신규 유입분부터 찍힌다 (reference 컬럼 때와 동일).

ALTER TABLE public.wms_orders ADD COLUMN IF NOT EXISTS order_date date;

COMMENT ON COLUMN public.wms_orders.order_date IS
  'Cin7 Core 화면 Order Date (= API OrderDate). 픽리스트 인쇄용. 폴링 EF(hello)가 채운다.';
