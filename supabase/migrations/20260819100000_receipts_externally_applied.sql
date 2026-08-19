-- wms_receipts.status 에 'externally_applied' 추가 (2026-08-19)
--
-- 배경 [실사고 PO-01130]: Cin7 에서 이미 처리가 끝나 WMS 로 Apply 하지 않기로 정한 receipt 가
-- status=completed · applied_at=null 이라 Apply 대기 목록(admin 「APPLY TO CIN7」)에 계속 남았다.
-- Delete 는 라인별 작업자 기록 등 이력을 지우므로 부적합 → 「Cin7 에서 외부적으로 처리됨」 상태 신설:
--   · applied_at 은 안 채운다 (WMS 가 Cin7 에 쓴 적 없다는 사실 보존 — Apply 이력과 구분)
--   · Apply 대기 목록에서 빠진다 (admin applicable 필터 status==='completed' 가 자동 제외)
--   · 히스토리·Stats 에는 남는다 (Stats 는 별도 카운트 "Applied outside WMS")
--   · 누가·언제·왜는 apply_note 에 사람용 문장으로 덧붙인다 (원복도 지우지 않고 덧붙임)
--
-- ⚠️ 전이는 admin Review 모달에서만 (Mark externally applied / Back to completed — canApply 권한).
-- ⚠️ receiver 쪽 누수 봉인이 프론트에 함께 나간다 — startPo 의 status!=='completed' "미완료" 판정과
--    openReceipt 의 in_progress 되돌림이 이 상태를 화면 한 번 여는 것으로 소멸시키기 때문.
-- ⚠️ 규칙 23 배포 순서: 이 마이그레이션(db push — Caleb 직접)이 프론트(admin/receiver)보다 먼저.
--    CHECK 에 값만 더하는 변경이라 기존 행·기존 프론트에는 무영향.
-- baseline 무접촉 — CHECK drop 후 5값으로 재생성.

alter table public.wms_receipts
  drop constraint if exists wms_receipts_status_check;
alter table public.wms_receipts
  add constraint wms_receipts_status_check
  check (status = any (array['in_progress'::text, 'held'::text, 'partial'::text, 'completed'::text, 'externally_applied'::text]));
