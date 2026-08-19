-- 원장 변경 감지 — inv_conflicts (2026-08-19 · ⑤ 게이트 4번)
-- 설계 근거: docs/design/ledger-design.md 4부 3번 + 1부 「미달·초과 입고의 실무 흐름」
--
-- 원장 쓰기는 ignore-duplicates 라 유니크 키(doc_type,doc_number,line_ref,event_type,warehouse,
-- bin,sku)가 겹치면 행이 조용히 버려진다 — 재수집이 일상(모든 PO 가 최소 두 번 잡힌다)이라 그
-- 자체는 의도된 동작이다. ⚠️ 문제는 「키는 같은데 값이 다른」 경우:
-- [실측 2026-08-19] PO-01117 CAN01620 168→192 — PO 를 닫으려고 인보이스 수량으로 채우는
-- **정상 실무 흐름**인데, 지금 구조에서는 새 값이 버려지고 아무 데도 안 남는다(pg_cron 자동
-- 회차의 응답은 아무도 안 본다 — cron.job_run_details 의 succeeded 는 아무것도 보장 안 함).
-- → inv-collect 가 commit 시 「버려졌는데 값이 다른」 행을 여기 기록한다.
-- 📌 ⑥ 대조 단계의 재료 — 숫자가 어긋났을 때 "왜"를 답하는 유일한 기록.
--
-- ⚠️ 유니크 제약 없음(의도) — 같은 행이 여러 번 바뀔 수 있고 **변경 이력이 쌓이는 것이 목적**이다.
-- ⚠️ 쓰기 차단 아님 — 수량 정정은 흔한 정상 실무라 원장 쓰기는 그대로 진행되고 여기엔 기록만.
-- ⚠️ 원장 행은 안 고친다(append-only) — 역분개는 자리 단위 원장 과제(정본 4부 3번).
-- 화면·알림 없음 — 당분간 SQL 직접 조회: select * from inv_conflicts order by detected_at desc;

create table inv_conflicts (
  id           bigint generated always as identity primary key,
  -- 유니크 키 7종 — inv_ledger 의 inv_ledger_event_uq 와 같은 구성(어느 행이 충돌했는지 특정)
  doc_type     text not null,
  doc_number   text not null,
  line_ref     text not null,
  event_type   text not null,
  warehouse    text not null,
  bin          text not null default '',
  sku          text not null,
  -- 비교 핵심 — 원장에 남아 있는 값 vs 이번 수집이 가져온 값
  existing_qty         numeric not null,
  incoming_qty         numeric not null,
  existing_occurred_on date not null,
  incoming_occurred_on date not null,     -- 날짜도 바뀔 수 있다
  source       text not null,             -- 수집 소스 키 (purchase·sale·transfer·adjustment·assembly·creditnote)
  collector    text not null,             -- COLLECTOR_VERSION 문자열 — 어느 규칙 버전이 감지했나
  -- ⚠️ 문서 전체 금지 — 그 행을 만든 라인 원본만 (inv_ledger.raw 와 같은 관례)
  incoming_raw jsonb,
  detected_at  timestamptz not null default now(),
  -- 사람이 판단한 뒤 닫는 용도 (예: "PO 마감 채움 — ST-01220 이 상쇄, 조치 불요")
  resolved_at     timestamptz,
  resolution_note text
);

-- 주 용도 조회 둘: 문서 역추적 · 최근 감지 순
create index inv_conflicts_doc_idx      on inv_conflicts (doc_type, doc_number);
create index inv_conflicts_detected_idx on inv_conflicts (detected_at desc);

-- RLS — 다른 inv_* 와 동일(auth_all + anon 전부 회수). 쓰기 주체는 EF(service_role — RLS 우회,
-- 서버사이드 정상 경로 · 규칙 8). ⚠️ 이력 보존을 위해 authenticated 의 DELETE/TRUNCATE 는 회수
-- (inv_ledger append-only 선례) — resolve 는 UPDATE(resolved_at/resolution_note)라 남겨 둔다.
alter table inv_conflicts enable row level security;
create policy auth_all on inv_conflicts for all to authenticated using (true) with check (true);
revoke all on inv_conflicts from anon;
revoke delete, truncate on inv_conflicts from authenticated;
