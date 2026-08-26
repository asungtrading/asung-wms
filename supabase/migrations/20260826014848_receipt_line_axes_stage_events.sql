-- 리시빙 축 분리 + 전환 이력 (2026-08-25 저녁 설계 · S2) — 인력 배치 지표의 기록층
--
-- 왜: 라인의 사람·시각이 last_received_by/at 한 칸(마지막 터치)뿐이라 placeAllInBin 이
--   스캔자의 이름·시각을 bin 단위로 덮는다([실측] receipt 67 = PO-01151: 20줄 시각이 bin 별
--   버스트 3.2초 — 실제 80분 · 전 라인 동일인). 목적(인력 배치 = 「스캔 몇 명·몇 분 /
--   풋어웨이 몇 분」)에는 축을 나눠야 한다 — 축을 나누면 Place all 은 풋어웨이 축만 덮고
--   스캔 축은 살아남는다(스캔 2명이 데이터에 남는다).
--
-- 설계 결정 (2026-08-25 Caleb 확정):
--  · 축 4컬럼 = 라인의 「축별 마지막 터치」 상태 캐시. last_received_by/at 은 **병존·의미 무변**
--    (소비처 3곳 — admin 기간 귀속·recvWorkers·Workers 열 — 무접촉. 값 진실화는 프론트 몫).
--  · 전환은 이력으로(B안 — 오갈 때마다 한 줄. 누계 컬럼은 정보를 버린다 · wms_task_holds 전례).
--    ⚠️ wms_task_holds 재사용 기각: admin 이 task_kind='receipt' 전 행을 Hold 공제로 읽는다
--    (loadRecvStats rHoldMap) — 전환 행이 들어가는 순간 작업시간에서 빼는 값이 된다.
--  · 전환 지점 전수 2곳(코드 확정): putView 를 여는 경로는 showPutaway() 하나(호출자
--    toPutawayBtn 하나), 복귀는 putBackBtn 하나. openReceipt 은 목록·재개·admin Reopen 딥링크
--    전부 항상 recvView — 열기는 기록하지 않는다(모든 열기가 리시빙 시작이라 정보 0).
--  · stage_events.at 은 서버 시계(default now()) — 전환은 버튼 즉시 insert 라 지연이 없고,
--    태블릿 시계 음수 전례(hold 11행)를 피한다. 축 컬럼의 at 은 클라이언트 터치 시각
--    (쓰기 편승 — 라인 스탬프와 동일한 사용자 결정 2026-08-21).
--  · 계산 정의(화면은 별건 — 이번 범위는 기록만): 리시빙 구간 = created_at ~ max(last_qty_at) ·
--    풋어웨이 구간 = min(stage='putaway' at) ~ completed_at(끝에 Place all 만 누르는 관행에도
--    견디는 유일한 정의 — 걷는 시간이 들어온다) · 겹침은 병기, 합산 금지 ·
--    사람 수 = 축별 distinct. 복귀 빈도 = stage='receiving' 행 수(실측 후 나중 판단).
--  · FK 없음 — admin 삭제·off-PO reject(라인 delete) 후에도 사실 기록 보존
--    (wms_task_holds · wms_discrepancies.pick_task_id 전례).
--  · 부분 유니크 인덱스 금지(프로젝트 규칙) — 인덱스는 조회용 일반형만.
--  · 백필 금지 — 도입 전 라인은 축 NULL(과거 터치 시각은 이미 덮여 소멸 — 비가역).
--    신뢰 시점은 배포 후 첫 행 실측으로 스킬 규칙 37 계열에 기입.
--
-- ⚠️⚠️ 배포 순서(규칙 23 — order_date 전례): 이 SQL 을 supabase db push (Caleb 직접) 로
--   원격 반영을 확인한 뒤에만 receiver 프론트를 커밋·배포한다. 축 4컬럼이 qty UPDATE
--   페이로드와 off-PO insert 에 실리므로, 순서를 어기면 수량 저장이 전면 400 이다.

-- ─────────────────────────────────────────────────────────
-- 1) wms_receipt_lines — 축 4컬럼 (축별 마지막 터치)
-- ─────────────────────────────────────────────────────────
alter table wms_receipt_lines
  add column if not exists last_qty_at     timestamptz,
  add column if not exists last_qty_by     text,
  add column if not exists last_putaway_at timestamptz,
  add column if not exists last_putaway_by text;

comment on column wms_receipt_lines.last_qty_at is
  '이 라인의 마지막 수량 터치 시각(스캔·수동입력·스테퍼 — 클라이언트 시계). Place all 이 덮지 못하는 스캔 축. NULL = 2026-08-26 도입 전(백필 안 함)';
comment on column wms_receipt_lines.last_qty_by is
  '마지막 수량 터치를 한 사람. 스캔 인원 수 = receipt 내 distinct. 한 라인을 같은 축에서 둘이 만지면 앞사람이 덮인다(라인 스탬프와 동일 한계)';
comment on column wms_receipt_lines.last_putaway_at is
  '이 라인의 마지막 풋어웨이 터치 시각(Placed/Change/Place all — putaway_auto 자동배정·startPo 초기 적재는 제외, last_received_at 과 같은 규칙)';
comment on column wms_receipt_lines.last_putaway_by is
  '마지막 풋어웨이 터치를 한 사람(Place all 을 누른 사람에게 몰리는 것이 이 축에서는 사실 그대로다)';

-- ─────────────────────────────────────────────────────────
-- 2) wms_receipt_stage_events — 리시빙↔풋어웨이 전환 이력
-- ─────────────────────────────────────────────────────────
create table wms_receipt_stage_events (
  id         bigint generated always as identity primary key,
  receipt_id bigint not null,        -- FK 없음: 삭제된 receipt 의 사실 기록 보존 (holds 전례)
  worker     text not null,          -- 버튼 누른 사람 (me.name — 라인 스탬프와 동일 출처·신뢰)
  stage      text not null check (stage in ('putaway','receiving')),
                                     -- 'putaway' = Putaway → 진입 · 'receiving' = ← Receiving 복귀
  at         timestamptz not null default now()   -- 서버 시계 (헤더 주석 참조)
);
create index idx_receipt_stage_events_receipt on wms_receipt_stage_events (receipt_id);

comment on table wms_receipt_stage_events is
  '리시빙↔풋어웨이 화면 전환 이력(사람 단위 · 2026-08-26). 기록 = receiver 2버튼 fire-and-forget — 실패해도 화면 전환을 막지 않는다(통계 전용). 풋어웨이 구간 = min(putaway at) ~ receipt.completed_at';

alter table wms_receipt_stage_events enable row level security;
create policy auth_all on wms_receipt_stage_events for all to authenticated using (true) with check (true);
revoke all on wms_receipt_stage_events from anon;
