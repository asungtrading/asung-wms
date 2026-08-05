-- wms_reports 리시빙 지원 (2026-08-05)
-- picker/packer 리포트는 order_id/order_number 기준인데 receiver 는 오더가 없다.
-- wms_discrepancies 가 리시빙 때 갔던 길과 동일: receipt_id + po_number 로 귀속 (order_id 는 NULL).
-- 화면 구분은 기존 source 컬럼('receiver'), 새 kind 'box_barcode' 는 CHECK 가 없어 컬럼 변경 불필요
--   (baseline 715행: kind text NOT NULL, CHECK 없음 — 실행 전 실물 확인:
--    select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid='public.wms_reports'::regclass;)

alter table public.wms_reports add column if not exists receipt_id bigint;
alter table public.wms_reports add column if not exists po_number  text;

-- 진입 시 눌린 상태 복원 조회(receipt_id + resolved_at is null)용 — 테이블이 작아 없어도 되지만
-- idx_reports_open(부분) 과 같은 취지로 열린 리포트 조회만 커버한다.
create index if not exists idx_reports_receipt_open
  on public.wms_reports (receipt_id) where resolved_at is null and receipt_id is not null;
