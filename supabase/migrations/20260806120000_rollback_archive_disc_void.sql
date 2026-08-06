-- 롤백 아카이브 + discrepancy 무효화 컬럼 (2026-08-06, SO-14129 증거 소멸 후속)
--
-- ① wms_rollback_archive — 롤백/삭제가 지우는 행을 지우기 **전에** JSON 으로 보존한다.
--    범용 1테이블(JSONB): 대상이 8종(pack/pick tasks·lines, pallets/items, receipts/lines)이라
--    미러 테이블 8개 대신 이 하나로. 용도는 사고 조사(저빈도 SQL 조회)다.
--    ⚠️ 순서 불가침: 아카이브 insert 성공을 확인한 뒤에만 delete 한다. insert 실패 = 롤백 전체
--       중단, 아무것도 지우지 않는다 (admin.html archiveRows).
--    ⚠️ 정직한 한계: 이 기록은 delete 를 수행하는 클라이언트(admin.html)가 직접 쓴다 —
--       anon key + 로그인 세션이면 쓸 수 있는 **사고 조사용 기록이지, 악의를 막는 보안
--       경계가 아니다.** EF 경유 전환은 별건 백로그. 대신 클라이언트 권한은 INSERT+SELECT 만
--       부여해 append-only 로 둔다(UPDATE/DELETE/TRUNCATE 미부여 — 실수로도 못 지운다).
--
-- ② wms_discrepancies.voided_at/voided_by/voided_reason — 롤백이 만든 행의 **무효화**(삭제 금지).
--    화이트리스트(규칙 41): 팩 롤백 = short_after_pack·over_pick·pack_scan_mistake /
--    픽 롤백 = short_pick. stock_short(선반 사실)·recv_*·cin7_corrected=true(역조정 검토 표시)·
--    링크 null(옛 행 — 수동 검토)은 절대 자동 무효화하지 않는다.

-- ① 아카이브 테이블
create table if not exists public.wms_rollback_archive (
  id           bigint generated always as identity primary key,
  archived_at  timestamptz not null default now(),
  archived_by  text,
  action       text not null,       -- pack | pick_reset | split | void | unwave | fulfillment | receipt_delete
  order_id     bigint,              -- receipt_delete 는 null
  order_number text,                -- receipt_delete 는 PO/TR 번호
  batch_label  text,
  src_table    text not null,       -- 원본 테이블명
  row_data     jsonb not null       -- 삭제(또는 0 으로 덮기) 직전의 행 전체
);
create index if not exists idx_rb_archive_order on public.wms_rollback_archive (order_id);
create index if not exists idx_rb_archive_at    on public.wms_rollback_archive (archived_at);

alter table public.wms_rollback_archive enable row level security;
drop policy if exists rb_archive_insert on public.wms_rollback_archive;
create policy rb_archive_insert on public.wms_rollback_archive
  for insert to authenticated with check (true);
drop policy if exists rb_archive_select on public.wms_rollback_archive;
create policy rb_archive_select on public.wms_rollback_archive
  for select to authenticated using (true);

-- ⚠️ Supabase 기본 default privileges 는 새 객체에 ALL 을 붙인다(2026-08-06 뷰에서 실측) —
--    전부 회수 후 필요한 것만 되부여한다. identity 컬럼은 시퀀스 별도 GRANT 불필요.
revoke all on table public.wms_rollback_archive from anon, authenticated;
grant select, insert on table public.wms_rollback_archive to authenticated;

comment on table public.wms_rollback_archive is
  'rows preserved verbatim (jsonb) BEFORE a rollback/delete removes them - incident forensics, append-only for clients; NOT a security boundary (written by the client that deletes; EF-mediated write is backlog)';

-- ② discrepancy 무효화 컬럼
alter table public.wms_discrepancies add column if not exists voided_at timestamptz;
alter table public.wms_discrepancies add column if not exists voided_by text;
alter table public.wms_discrepancies add column if not exists voided_reason text;

comment on column public.wms_discrepancies.voided_at is
  'set when a rollback invalidated this row (whitelist per rollback kind - rule 41). NEVER deleted: queue/Stats exclude voided rows, history shows them tagged';
