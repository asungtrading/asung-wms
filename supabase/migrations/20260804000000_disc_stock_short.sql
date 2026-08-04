-- 2026-08-04 — 픽·팩 discrepancy: 작업자 실수 vs 재고 불일치 구분
--
-- 정책: "재고 부족 선언(stock_short)"은 실수를 지우는 것이 아니라 재분류다.
-- 주문은 여전히 부족 출고이고, Cin7 재고와 실물의 차이는 이 큐에 남아
-- 매니저가 Cin7 에서 수동 조정한다(리시빙 discrepancy 와 같은 흐름 — 자동 조정 없음).
-- responsible 은 실수 귀속(mistake tally) 전용이므로 stock_short 행은 null 로 두고,
-- 선언자는 declared_by 에 기록한다(감사 — 선언 시각은 created_at).

alter table public.wms_discrepancies
  add column if not exists declared_by text;

-- 규칙 29 응급 수정분 정착 (2026-07-29, supabase/wms_disc_uq_fix.sql):
-- 부분 유니크(WHERE receipt_id IS NOT NULL)는 PostgREST on_conflict 가 추론하지 못해
-- 리시빙 discrepancy 기록이 42P10 으로 전부 실패했다. 원격에는 전체 유니크로 이미
-- 교체됐지만 마이그레이션에 없어서 새 환경/db reset 때 부분 유니크로 되돌아간다.
-- 아래는 이미 적용된 원격에 다시 실행해도 안전(멱등).
drop index if exists public.uq_disc_receipt_sku;
create unique index if not exists uq_disc_receipt_sku
  on public.wms_discrepancies (receipt_id, sku);
