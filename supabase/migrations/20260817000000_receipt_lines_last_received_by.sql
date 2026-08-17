-- 리시빙 라인별 작업자 기록 (2026-08-17 · 세션 문서 docs/sessions/2026-08-17-ledger-02b.md §15 후속)
--
-- 배경: 리시빙은 여러 작업자가 나눠 받는 것이 기능(규칙 24)인데 라인별 작업자가 DB 어디에도
-- 없다. wms_receipts.received_by 는 "receipt 를 처음 만든 사람"이고 이후 갱신되지 않는다 —
-- 그래서 화면 세 곳이 사실과 달랐다: admin Receiving 이력 RECEIVED BY(실례 PO-01131 =
-- Joyce Chang, 들어갔다 나온 사람) · Stats 의 Receive N lines 시작자 전량 귀속 ·
-- avg work time / putaway % 가 나눠 한 작업을 한 사람 실적으로.
--
-- 컬럼 의미 = "이 라인을 마지막으로 만진 사람" (라인당 1명 — 2026-08-17 결정).
--   한 라인을 두 사람이 나눠 받으면 마지막 사람만 남지만, receipt 전체로는 참여자가 전원
--   드러난다(각자 마지막으로 만진 라인이 있으므로) — 표시는 receipt 의 distinct 로 한다.
-- ⚠️ approved_by(off-PO 승인자)와 다른 것이다 — 재사용 금지.
-- ⚠️ NULL 허용 · DEFAULT 없음 · 백필 없음 — 전부 의도:
--   · NOT NULL 이면 기존 행(전부 빈 값) 때문에 마이그레이션 자체가 실패한다.
--   · DEFAULT 가 있으면 "기록된 것"과 "안 된 것"을 구분할 수 없다.
--   · 과거 라인의 실제 작업자는 알 수 없다 — 추정으로 채우면 거짓 기록이 된다.
--     received_by 복사는 특히 금지 — 그게 바로 지금 틀린 값이다.
--   신규분부터만 찬다. 표시는 라인 값 우선 → 없으면 wms_receipts.received_by 폴백
--   (short_pick 픽커 표시의 completed_by 우선 → assigned_to 폴백과 같은 패턴 — 규칙 41).
-- 인덱스 없음 — 집계는 receipt_id 로 이미 좁혀진 뒤에 일어난다.
-- ⚠️ 프론트(receiver.html 쓰기 · admin.html 표시)는 다음 단계 — 컬럼이 코드보다 먼저(규칙 23).

alter table public.wms_receipt_lines
  add column if not exists last_received_by text,
  add column if not exists last_received_at timestamptz;

comment on column public.wms_receipt_lines.last_received_by is
  '이 라인을 마지막으로 만진 작업자 이름 (2026-08-17 — 라인당 1명, receipt 참여자는 distinct 로 집계). NULL = 컬럼 도입 전 라인 — 표시 폴백은 wms_receipts.received_by';
comment on column public.wms_receipt_lines.last_received_at is
  '위 작업자가 이 라인을 마지막으로 만진 시각. NULL = 컬럼 도입 전 라인';
