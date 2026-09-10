-- inv_doc_cost 표만 — 20260910141553 의 표 정의 복제 (2026-09-10)
--
-- ⚠️⚠️ 이 파일은 20260910141553_inv_doc_cost_transfer_freight.sql 의 「A. inv_doc_cost」 표 정의를 **복제**한 것이다.
-- ⭐ 목적: 수집기(inv-doc-cost EF)를 **운영에서 돌리기 위해 표만 운영에 올린다.**
--   inv_doc_cost 는 수집기의 표다(inv-cost ↔ inv_cost 와 같은 관계) — 수집기가 쓰려면 표가 운영에 있어야 한다.
--   배분(inv_layer_apply 의 운송비 블록)은 원가 레이어 계열이라 **운영에 올리지 않는다**(금액 미검증 · 아침 점검 ⑭ 의 의도한 차이).
--   20260910141553 은 둘을 한 파일에 담고 있어 갈라 올릴 수 없다 ⇒ 표만 만드는 파일을 따로 둔다.
--
-- ⚠️⚠️ 두 파일이 같은 표를 정의한다 — 한쪽만 고치면 환경별로 스키마가 갈린다.
-- ⇒ ⭐ inv_doc_cost 스키마를 바꿀 때는 **반드시 새 마이그레이션으로** 하고, 두 정의 중 어느 것도 고치지 마라
--   (create table / create index 가 if not exists 라 둘 다 그대로 둬도 무해하다 — 테스트 DB 처럼 이미 있으면 아무 일도 일어나지 않는다).
--   유일한 차이: create policy 앞의 drop policy if exists 한 줄(아래 주석) — 정의 문자열은 같다.
--
-- 📌 [배경 2026-09-10] 운영 migration list 에서 20260910132601·20260910141553 이 비어 있어 commit=1 이 실패하는 상태였다.
--   수집기가 inv_doc_cost 에 쓰려면 그 표가 운영에 있어야 한다.
-- 설계·실측(ManualJournals 원문 · ~~IsSystem~~ · 유니크의 ref_number null 약점)은 20260910141553 헤더가 정본이다 — 여기 반복하지 않는다.
-- ⚠️ [정정 2026-09-10] 141553 헤더의 IsSystem 실측표는 창작이었다(트랜스퍼 ManualJournals 에 IsSystem 없음 · 발주 구조를 옮겨 적은 것) — 141553 헤더의 정정 절 참조.
--   표 정의는 그 사고와 무관하다(컬럼에 IsSystem 이 없다).

create table if not exists inv_doc_cost (
  id             bigint generated always as identity primary key,
  doc_type       text not null,      -- 'transfer' (앞으로 다른 축이 올 수 있다)
  doc_number     text not null,
  kind           text not null,      -- 'transfer_freight'
  amount         numeric not null,   -- ⚠️ CHECK 없음 — 정정이 음수로 올 수 있다. 배분 가드가 방어
  occurred_on    date not null,      -- ⚠️ 저널 Date (인보이스 날짜)
  ref_number     text,               -- ⭐ Service Invoice 번호 (B6913286)
  debit_account  text,               -- '_59_'
  credit_account text,               -- '_136_'
  collector      text not null,
  refreshed_at   timestamptz not null default now(),
  raw            jsonb,              -- 그 문서의 ManualJournals 배열 전체(~~IsSystem=true 포함~~ → 화이트리스트에 걸린 행 포함 · 2026-09-10 정정) — 「왜 이 금액만 골랐나」 추적용
  constraint inv_doc_cost_doc_type_ck check (doc_type in ('transfer')),
  constraint inv_doc_cost_kind_ck     check (kind in ('transfer_freight')),
  constraint inv_doc_cost_uq
    unique (doc_type, doc_number, kind, ref_number, occurred_on)
);
create index if not exists inv_doc_cost_doc_idx on inv_doc_cost (doc_type, doc_number);

alter table inv_doc_cost enable row level security;
-- ⚠️ create policy 에는 if not exists 가 없다 — 테스트 DB(표·정책이 이미 있음)에서 오류 나지 않게 먼저 지운다. 정의는 아래 한 줄 그대로.
drop policy if exists auth_all on inv_doc_cost;
create policy auth_all on inv_doc_cost for all to authenticated using (true) with check (true);
revoke all on inv_doc_cost from anon;
revoke delete, truncate on inv_doc_cost from authenticated;

