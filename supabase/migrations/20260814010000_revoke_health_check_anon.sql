-- wms_health_check() anon + PUBLIC 실행 권한 회수 (2026-08-14)
-- (파일명은 anon 만 가리키지만 실제 차단은 PUBLIC 회수가 한다 — 아래 실측 참조)
--
-- 이유: 공개 anon 키만으로 호출 가능했고, sample 에 오더번호·SKU 가 실린다
-- (SECURITY DEFINER 라 RLS 도 우회). admin.html 은 wmsAuth.start 게이트 안에서만
-- 호출하므로 항상 authenticated — 이 revoke 로 깨지는 호출자는 없다
-- (2026-08-14 조사 확인: 저장소 전체에서 이 RPC 의 호출자는 admin.html 뿐,
-- pg_cron 직접 호출은 잡 소유자 권한이라 무관).
--
-- [실측 2026-08-14] select proacl from pg_proc where proname='wms_health_check';
--   → {=X/postgres, postgres=X/postgres, authenticated=X/postgres, service_role=X/postgres}
-- ① `=X/postgres`(사용자명 없이 = 로 시작) = PUBLIC 에 EXECUTE 가 있다.
--    anon 은 PUBLIC 경유로 실행되므로 `from anon` 만으로는 못 막는다.
-- ② 실물 ACL 에 anon 항목 자체가 없다 — baseline:1601 의 `GRANT ALL ... TO anon` 을
--    근거로 `from anon` 만 쓰면 아무것도 회수하지 못한 채 조용히 통과했을 것이다.
--    문서(baseline 덤프)를 근거로 삼았는데 실물 ACL 이 달랐다 — 규칙 29 의 또 한 사례.

-- 실제 차단은 이 줄이다: PUBLIC 회수 → anon 의 유일한 경로가 끊긴다.
revoke execute on function public.wms_health_check() from public;

-- 실물 ACL 에 anon 항목이 없어 이 줄은 no-op 이지만(위 실측 ②), 어느 환경에서든
-- anon 직접 grant 가 있었다면 함께 걷어내도록 명시적으로 남긴다. 무해.
revoke execute on function public.wms_health_check() from anon;

-- ⚠️ authenticated·service_role 은 그대로 둔다 — admin 이 authenticated 로 호출한다.
--
-- ⚠️ 주의: create or replace 는 기존 ACL 을 보존하므로 이후 함수 수정에서
-- revoke 가 되살아나지는 않는다. 단 drop 후 재생성하는 마이그레이션이 생기면
-- 기본 부여(PUBLIC EXECUTE + default privileges)가 되살아난다 —
-- 그런 마이그레이션에는 이 revoke 들을 함께 넣을 것.
