-- wms_disc_uq_fix.sql — 2026-07-29
--
-- ⚠️ 이 파일은 **기록/응급용이고 마이그레이션이 아니다.**
--    CLAUDE.md 「DB 스키마 변경 절차」대로 같은 내용을 새 마이그레이션
--    (`supabase migration new disc_uq_fix`)에 담아야 로컬·원격이 정렬된다.
--    아래 SQL 은 멱등이라 원격에 이미 적용됐어도 그대로 다시 돌려도 안전하다.
--
-- ── 왜 (SKILL 규칙 29) ──────────────────────────────────────────────
-- 증상: 리시빙 Apply 시 Supabase 400
--        42P10 there is no unique or exclusion constraint matching the
--        ON CONFLICT specification
--
-- 원인: baseline 의 인덱스가 **부분(partial) 유니크** 였다.
--        CREATE UNIQUE INDEX uq_disc_receipt_sku
--          ON wms_discrepancies (receipt_id, sku)
--          WHERE (receipt_id IS NOT NULL);        -- ← 이 WHERE
--       PostgREST 의 on_conflict 는 부분 인덱스를 추론하지 못한다.
--       Edge Function `receiving` 은
--         POST wms_discrepancies?on_conflict=receipt_id,sku
--       로 Cin7 쓰기 **앞에** discrepancy 를 선기록하므로(규칙 27 R12),
--       이 실패가 곧 Apply 중단이었다.
--
-- ⚠️ 파급: 이 때문에 리시빙 discrepancy 는 구현 이후 한 번도 기록되지 않았다.
--          (Health 의 short_no_disc 는 픽킹 전용이라 못 잡았다.)
--
-- 안전성: receipt_id 가 NULL 인 pick/pack 행은 유니크 인덱스의 기본 동작
--         NULLS DISTINCT 때문에 서로 충돌하지 않는다 — 부분 인덱스로 얻으려던
--         것을 기본 동작이 이미 해준다.
--
-- 확인 (문서가 아니라 이게 근거다):
--   select indexname, indexdef from pg_indexes
--    where tablename = 'wms_discrepancies';
-- ────────────────────────────────────────────────────────────────────

begin;

drop index if exists public.uq_disc_receipt_sku;

create unique index if not exists uq_disc_receipt_sku
  on public.wms_discrepancies (receipt_id, sku);

commit;

-- 사후 확인
-- select indexname, indexdef from pg_indexes
--  where tablename = 'wms_discrepancies' and indexname = 'uq_disc_receipt_sku';
-- 기대: CREATE UNIQUE INDEX uq_disc_receipt_sku ON public.wms_discrepancies
--       USING btree (receipt_id, sku)      ← WHERE 절 없음
