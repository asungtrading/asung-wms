-- inv_missing_docs — merge-duplicates POST 가 INSERT 경로를 탈 때의 not-null 위반 해소
-- (2026-09-05)
--
-- 배경: 소멸 감지 2단계의 쓰기는 POST 두 번이다.
--   ① ignore-duplicates + missing_lines·missing_qty 포함 → 신규 문서만 insert(최초 스냅샷)
--   ② merge-duplicates + 7필드만 → last_seen 계열만 갱신
-- ⚠️ PostgREST 의 merge-duplicates 는 upsert 라 **INSERT 문을 만든다.** payload 에 없는
--   missing_lines·missing_qty 가 not null 이라 23502 로 실패했다([실측 2026-09-05]
--   "missing-docs upsert failed ... Failing row contains (4, adjustment, ST-01283, null, null, ...").
--   ⇒ default 를 주어 INSERT 경로를 통과시킨다.
-- 📌 ①이 항상 먼저 돌아 명시값을 넣으므로 이 default 가 실제로 쓰이는 일은 없다 —
--   ②가 INSERT 문을 만들 때만 필요한 값이다.

alter table inv_missing_docs
  alter column missing_lines set default 0,
  alter column missing_qty   set default 0;
