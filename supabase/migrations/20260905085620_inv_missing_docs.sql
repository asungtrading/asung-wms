-- 소멸 감지 2단계 — inv_missing_docs (2026-09-05)
--
-- 배경: 소멸 감지(detectMissingLines)는 다섯 축 전부에서 **판정은 한다.** 그런데 inv_missing_lines
--   의 유니크 키에 last_modified_on 이 들어 있고 그 컬럼이 not null 이라, Cin7 이 LastModifiedOn 을
--   주지 않는 **adjustment·assembly 는 표에 못 들어간다**(1단계 · inv-collect@2026-09-03.1 —
--   summary.missing_lines_unkeyed 로만 남긴다).
--   ⚠️ 로그는 닫을 수가 없다. [실물 ST-01283] 8월 소멸 3행을 09-02 에 손으로 상쇄해 원장은
--   정상인데, 감지는 매 회차 계속 unkeyed 3 을 낸다 ⇒ 아침 점검 ⑦-b 의 「0행이면 정상」이 죽고
--   기준선이 3 이 됐다 — 사람이 숫자를 외워야 하는 상태([09-04 실사고] 외운 숫자가 시야를 가린
--   실패를 두 번 겪었다).
--
-- 무엇을 하나: 그 둘(adjustment·assembly)만 **문서 단위** 별도 표에 담는다. 유니크 키에
--   last_modified_on 이 필요 없고 resolved_at 으로 **닫을 수 있다.** 잘 작동 중인 세 축
--   (sale·purchase·transfer)의 inv_missing_lines 경로는 일절 건드리지 않는다.
--   선례: inv_voided_docs(20260904192652 · 아침 점검 ⑪) — 같은 모양.
--
-- ⚠️⚠️ 「무엇으로 닫는가」 — ⑪ 과 다르다. ⑪ 은 문서 전체를 되돌리므로 원장 순액 net≈0 이면
--   상쇄 완료로 보고 기록하지 않는다. **이 표는 그 규칙을 쓰면 안 된다** — 사라진 라인만
--   상쇄하므로 문서 전체 순액은 원래 값 그대로다. ⇒ 감지되면 무조건 upsert · 닫는 수단은
--   **resolved_at 하나뿐** · 닫힌 뒤 다시 열리지 않는다(EF payload 규칙 — 아래).
--
-- 컬럼 의미
--  · missing_lines·missing_qty — **최초 감지 시점** 스냅샷(그때 몇 행이 얼마나 사라졌나).
--    EF 는 ignore-duplicates POST(신규 문서만 insert)에만 이 둘을 실어 최초 1회만 기록된다.
--  · last_seen_lines — 마지막 회차에 본 소멸 행 수. ⚠️ missing_lines 와 다르면 사건이 더 생긴 것.
--  · sample — 사라진 라인 표본(최대 20행 · {sku,bin,warehouse,event_type,qty}) — 상쇄 SQL 재료.
--    최초분으로 고정하지 않고 **마지막 회차 것으로 갱신**한다.
--  · last_seen_at — 다음 회차에도 보이면 갱신(행은 늘지 않는다). merge-duplicates POST 의 payload 는
--    doc_type·doc_number·doc_status·last_seen_at·last_seen_lines·sample·collector 만 —
--    first_detected_at / missing_lines / missing_qty / resolved_at / resolution_note 는 넣지 않는다
--    (merge 로 덮이면 사람이 닫은 것이 다시 열리고 최초 스냅샷이 덮인다).
--  · resolved_at·resolution_note — 사람이 상쇄한 뒤 닫는 자리. **유일한 종결 수단.**
--
-- ⚠️ 부분 유니크 인덱스 금지(PostgREST on_conflict 규칙) — 아래 unique 는 전체 유니크.
--  open_idx 의 where 는 조회용 일반 인덱스라 무방하다.
--
-- 조회: select * from inv_missing_docs where resolved_at is null order by first_detected_at;

create table if not exists inv_missing_docs (
  id                 bigserial primary key,
  doc_type           text not null,
  doc_number         text not null,
  missing_lines      int  not null,
  missing_qty        numeric not null,
  sample             jsonb,
  doc_status         text,
  first_detected_at  timestamptz not null default now(),
  last_seen_at       timestamptz not null default now(),
  last_seen_lines    int,
  collector          text,
  resolved_at        timestamptz,
  resolution_note    text,
  constraint inv_missing_docs_uq unique (doc_type, doc_number)
);

create index if not exists inv_missing_docs_open_idx
  on inv_missing_docs (doc_type, first_detected_at)
  where resolved_at is null;

-- RLS — inv_voided_docs·inv_missing_lines 와 동일(auth_all + anon 전부 회수). 쓰기 주체는
-- EF(service_role — RLS 우회, 서버사이드 정상 경로 · 규칙 8). 이력 보존을 위해 authenticated 의
-- DELETE/TRUNCATE 회수 — resolve 는 UPDATE(resolved_at/resolution_note)라 남겨 둔다.
alter table inv_missing_docs enable row level security;
create policy auth_all on inv_missing_docs for all to authenticated using (true) with check (true);
revoke all on inv_missing_docs from anon;
revoke delete, truncate on inv_missing_docs from authenticated;
