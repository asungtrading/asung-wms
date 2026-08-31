-- 문서별 마지막 관측 상태 — inv_doc_state (2026-08-31 · 결함 D)
--
-- 배경 [실사고 2026-08-31]: ②-a 는 비종결 문서(IN TRANSIT) 앞에서 커서가 멈추는데(설계대로),
--   그 위 문서가 상세 캡(40건/120초)을 넘으면 뒤쪽이 **영영 안 들어온다.**
--   TR-04330(−144)이 그렇게 누락됐고 BMA15710 대조 차이 144 와 정확히 일치했다.
--   [실측] 후보 159건 중 154건이 COMPLETED — 이미 원장에 있고 안 바뀐 문서를 매 회차 다시 읽었다.
--
-- 무엇을 하나: 문서별로 마지막으로 본 「수정 시각」을 기록한다. 다음 회차에 목록의 값이 같으면
--   **상세를 부르지 않는다**. [실측 2026-08-31] 그 값은 라인 편집에 반응한다
--   (SO-15440 삭제 3분 뒤 · TR-04175 삭제 시각 일치 · PO-01117 수량변경 3주 뒤).
--
-- ⚠️ 판정은 **완료 문서에만** 적용한다. 비종결(IN TRANSIT 등)은 무조건 상세를 부른다 —
--   도착 시 이 값이 바뀌는지 확인되지 않았고, 안 바뀌면 도착을 영영 못 본다.
--   [실측] 비종결은 5건뿐이라 비용이 0이다.
-- ⚠️ last_modified 는 **문자열 그대로** 저장한다. 축마다 형식이 다르다 —
--   sale/transfer 는 ...Z, purchase 는 Z 가 없다. 절대 시각으로 파싱하지 말 것.
-- 📌 시딩 불필요: 1회차가 앞 39건을 처리하며 기록하고, 2회차는 그것을 건너뛰고 다음 39건을
--   처리한다. 4회차면 159건이 다 기록된다(약 20분).

create table inv_doc_state (
  source_key     text        not null,   -- 'transfer' | 'sale' | 'purchase' | 'adjustment' | ...
  doc_number     text        not null,
  last_modified  text        not null,   -- 목록 행의 원문 (파싱하지 않는다)
  doc_status     text,                   -- 관측 당시 상태 (진단용)
  collector      text        not null,
  seen_at        timestamptz not null default now(),
  primary key (source_key, doc_number)
);

create index inv_doc_state_seen_idx on inv_doc_state (source_key, seen_at desc);

-- RLS — inv_conflicts·inv_missing_lines 와 동일. 쓰기 주체는 EF(service_role).
-- ⚠️ DELETE 는 회수하지 않는다 — 재수집으로 다시 만들 수 있다(지우면 전량 재조회로 복구된다).
alter table inv_doc_state enable row level security;
create policy auth_all on inv_doc_state for all to authenticated using (true) with check (true);
revoke all on inv_doc_state from anon;
