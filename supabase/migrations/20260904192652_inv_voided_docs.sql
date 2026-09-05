-- 「수집 후 취소」 감지 — inv_voided_docs (2026-09-04)
--
-- 배경 [실사고 FG-00131 09-01 · FG-00133 09-02 · FG-00134 09-04]: 원장에 이미 들어온 문서를
-- Cin7 에서 나중에 VOID 하면 원장은 그것을 모른다. Cin7 은 재고를 되돌리는데 원장은 차감한
-- 채로 남아 어긋난다 — 셋 다 재고 숫자가 안 맞는 것을 보고 반나절씩 파서 찾았다. 감지 축이
-- 없는 것이 원인이다.
--
-- 무엇을 하나: inv-collect(②-a · adjustment·assembly 축)가 매 회차 목록 전량을 받아
-- status_counts 를 세는 자리에서 — 커서·floor·재조회 창 **이전**이라 목록 전체를 본다 —
-- Status=VOIDED 문서번호를 모아 원장과 대조한다(새 API 호출 0건).
--   원장에 행이 있고(cin7+manual 합산) net<>0 인 문서 = 「취소됐는데 원장에 남아 있는 문서」
-- 를 여기 기록한다. ⚠️ **기록과 경보만 한다**:
--  · 원장 행을 삭제·수정하지 않는다 (append-only 불변)
--  · 자동 상쇄 없음 — 사람이 상쇄 행을 넣고 resolved_at/resolution_note 로 닫는다
--  · net=0 인 문서(이미 상쇄됨)·원장에 없는 문서(받은 적 없음)는 기록하지 않는다
--
-- 컬럼 의미
--  · ledger_rows·ledger_net — **감지 시점** 원장 상태의 스냅샷(cin7+manual). 나중에 상쇄하면
--    값이 달라지므로 「그때 무엇을 보고 기록했나」다.
--  · last_seen_at — 같은 문서가 다음 회차에도 VOIDED 로 보이면 갱신(행은 늘리지 않는다).
--    EF 는 on_conflict=doc_type,doc_number + merge-duplicates 로 쓰고, first_detected_at /
--    resolved_at / resolution_note 는 payload 에 넣지 않는다(merge 로 덮이면 사람이 닫은
--    것이 다시 열린다).
--
-- ⚠️ 부분 유니크 인덱스 금지(PostgREST on_conflict 규칙) — 아래 unique 는 전체 유니크.
--  open_idx 의 where 는 조회용 일반 인덱스라 무방하다.
--
-- 조회: select * from inv_voided_docs where resolved_at is null order by first_detected_at desc;

create table if not exists inv_voided_docs (
  id                 bigserial primary key,
  doc_type           text not null,
  doc_number         text not null,
  doc_status         text not null,
  ledger_rows        int  not null,
  ledger_net         numeric not null,
  first_detected_at  timestamptz not null default now(),
  last_seen_at       timestamptz not null default now(),
  collector          text,
  resolved_at        timestamptz,
  resolution_note    text,
  constraint inv_voided_docs_uq unique (doc_type, doc_number)
);

create index if not exists inv_voided_docs_open_idx
  on inv_voided_docs (doc_type, first_detected_at)
  where resolved_at is null;

-- RLS — inv_missing_lines·inv_conflicts 와 동일(auth_all + anon 전부 회수). 쓰기 주체는
-- EF(service_role — RLS 우회, 서버사이드 정상 경로 · 규칙 8). 이력 보존을 위해 authenticated 의
-- DELETE/TRUNCATE 회수 — resolve 는 UPDATE(resolved_at/resolution_note)라 남겨 둔다.
alter table inv_voided_docs enable row level security;
create policy auth_all on inv_voided_docs for all to authenticated using (true) with check (true);
revoke all on inv_voided_docs from anon;
revoke delete, truncate on inv_voided_docs from authenticated;
