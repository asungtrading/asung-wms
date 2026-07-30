-- wms_reports_image_mismatch.sql — 2026-07-30
--
-- ⚠️ 대부분의 경우 **이 파일을 돌릴 필요가 없다.**
--    baseline(20260101000000_baseline.sql:710~723)의 wms_reports.kind 는
--    그냥 `text NOT NULL` 이고 CHECK 제약이 없다 → 새 kind 값 `image_mismatch`
--    는 앱이 그대로 insert 하면 된다. 스키마 변경 불필요.
--
--    다만 규칙 29(스키마 기록의 진실은 실물 DB 다)의 교훈대로 **문서를 믿지 말고
--    아래 STEP 1 로 실물을 확인**하고, 행이 나오면 STEP 2 를 돌린다.
--
-- ⚠️ STEP 2 를 실제로 실행했다면 그것은 스키마 변경이다 →
--    CLAUDE.md 「2. DB 스키마 — 마이그레이션만」에 따라
--    `supabase db dump --linked` 로 되받아 새 마이그레이션에 반영해야
--    로컬·원격이 어긋나지 않는다. (이 파일은 기록/응급용, 마이그레이션 아님)
-- ────────────────────────────────────────────────────────────────────

-- STEP 1 — 확인. kind 를 제약하는 CHECK 가 있는가?
--          0행 = 제약 없음 = 할 일 없음. 여기서 끝.
select conname, pg_get_constraintdef(oid) as def
  from pg_constraint
 where conrelid = 'public.wms_reports'::regclass
   and contype  = 'c'
   and pg_get_constraintdef(oid) ilike '%kind%';

-- 참고 — 현재 실제로 들어있는 kind 값
-- select kind, count(*) from public.wms_reports group by 1 order by 2 desc;


-- STEP 2 — STEP 1 이 행을 냈을 때만 실행.
--          기존 CHECK 를 떼고, **이미 저장된 kind 값 전부 + 신규 3종**을 허용하는
--          제약으로 다시 만든다. 값 목록을 실데이터에서 뽑으므로 기존 행이
--          새 제약에 걸려 실패하는 일이 없다.
do $$
declare
  c      record;
  vals   text;
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.wms_reports'::regclass
       and contype  = 'c'
       and pg_get_constraintdef(oid) ilike '%kind%'
  ) then
    raise notice 'wms_reports.kind 에 CHECK 제약 없음 — 할 일 없음 (앱 코드만으로 충분)';
    return;
  end if;

  -- 허용 목록 = 저장된 값 ∪ {wrong_location, barcode_mismatch, image_mismatch}
  select string_agg(quote_literal(k), ',' order by k) into vals
    from (
      select distinct kind as k from public.wms_reports where kind is not null
      union select 'wrong_location'
      union select 'barcode_mismatch'
      union select 'image_mismatch'
    ) s;

  for c in
    select conname from pg_constraint
     where conrelid = 'public.wms_reports'::regclass
       and contype  = 'c'
       and pg_get_constraintdef(oid) ilike '%kind%'
  loop
    raise notice 'dropping %', c.conname;
    execute format('alter table public.wms_reports drop constraint %I', c.conname);
  end loop;

  execute format(
    'alter table public.wms_reports add constraint wms_reports_kind_check check (kind in (%s))',
    vals);
  raise notice 'wms_reports_kind_check 재생성 — 허용 값: %', vals;
end $$;

-- 사후 확인 (STEP 2 를 돌렸을 때만)
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--  where conrelid = 'public.wms_reports'::regclass and contype = 'c';
