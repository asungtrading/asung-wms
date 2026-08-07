-- 픽·팩 라인 id 를 GENERATED ALWAYS 로 복원 — BY DEFAULT 왕복의 기록.
--
-- 경위 (2026-08-06, 같은 날 왕복):
--   ① 7단계(완료 라인 묶음 upsert)가 명시 id 삽입을 위해 BY DEFAULT 로 전환
--      (20260806130000 — revert 로 파일은 삭제됐으나 DB 에는 적용된 상태).
--   ② 7단계는 프로덕션 실측 23502 로 폐기: INSERT..ON CONFLICT 는 NOT NULL 검사를
--      충돌 판정보다 먼저 하므로, NOT NULL 컬럼(pack_task_id 등)이 페이로드에 없으면
--      행이 이미 있어도 항상 거부된다 — 이 스키마에서 묶음 upsert 는 구조적으로 불가.
--   ③ 8단계(팩 완료 RPC, 20260806150000)는 진짜 UPDATE 라 명시 id 삽입이 필요 없다.
--      → BY DEFAULT 의 존재 이유 소멸. "명시 id 삽입 차단"이라는 원래 가드를 복원한다.
--
-- 새 환경(db reset)에서는 baseline 이 이미 ALWAYS 라 이 문장은 no-op — 멱등.
-- 이 파일의 목적 절반은 "DB(BY DEFAULT 적용됨)와 마이그레이션 히스토리의 정렬 회복"이다.

alter table public.wms_pick_task_lines alter column id set generated always;
alter table public.wms_pack_task_lines alter column id set generated always;
