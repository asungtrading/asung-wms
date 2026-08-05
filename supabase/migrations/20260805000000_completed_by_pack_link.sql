-- 2026-08-05 — SO-14129 팩 무단완료 후속 (docs/incidents/2026-08-04-so14129.md)
--
-- completed_by: "누가 완료를 실행했나"의 직접 기록.
--   기존 responsible 은 enterPack 시점에 읽은 픽 배정자(assigned_to)라 완료 실행자를
--   답하지 못했고, 사고 조사에서 귀속이 엇갈렸다. 완료 UPDATE 가 me.name 을 채운다.
alter table public.wms_pack_tasks add column if not exists completed_by text;
alter table public.wms_pick_tasks add column if not exists completed_by text;

-- pack_task_id / pick_task_id: 이 discrepancy 가 어느 단계·어느 작업의 산물인지 링크.
--   pack_task_id 는 packer.html 의 insert 4곳(short_after_pack · over_pick · pack_scan_mistake · stock_short),
--   pick_task_id 는 picker.html 의 insert 2곳(short_pick · stock_short)이 채운다 (wave 는 라인별 멤버 task).
-- ⚠️ FK 를 걸지 않는다 — 롤백이 task 행을 delete 하므로 FK 면
--   CASCADE(행 소멸)든 SET NULL(링크 소멸)이든 증거가 사라진다. 링크는 id 값으로만 남긴다.
-- ⚠️ 읽는 쪽은 아직 없다(의도) — 나중에 롤백이 남긴 discrepancy 를 무효화할 때의 근거.
--   지금 넣는 이유: 나중에 추가하면 그때까지 쌓인 행은 어느 단계 산물인지 알 수 없어 영구히 정리 불가.
--   무효화 판단은 reason 으로 할 것 — stock_short 는 완료 산물이 아니라 선언 산물이라 대상이 아니다.
alter table public.wms_discrepancies add column if not exists pack_task_id bigint;
alter table public.wms_discrepancies add column if not exists pick_task_id bigint;
