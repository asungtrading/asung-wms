-- 스냅샷 회차 로그 — inv_snapshot_runs (2026-08-26)
--
-- 배경 [실사고 2026-08-24]: 스냅샷이 조용히 불완전해질 수 있다.
--   아침 Cin7 목록 22,079건 · 23페이지 → 43초
--   밤   목록 21,877건 · 22페이지 → 1분44초   ← 190건 적고 2.4배 느림
-- 응답은 truncated:false · rate_limited:false — 거짓이 아니다. Cin7 이 애초에 적게 줬다.
-- [실증] AS93125 토론토 2,662개가 그 스냅샷에만 없었다(Cin7 화면엔 그대로).
-- all-or-nothing 가드는 「받은 수 < Total」(회차 안)만 보고 회차 「간」 비교를 못 한다 —
-- 비교에 필요한 값(list_total·pages_scanned·duration_ms·received_rows)은 summary 로 계산돼
-- 응답으로 나간 뒤 사라진다. inv_snapshot 으로는 복원 불가(count(*) 는 재촬영 시 누적 합집합 ·
-- 목록 크기·페이지·소요시간은 아예 저장 안 됨). 이 테이블이 그 값을 회차마다 받는다.
--
-- ⚠️ 이번 범위는 **기록만** — 급감 판정·차단·경보는 다음 단계다. 임계값은 정상 회차가
--    며칠 쌓인 뒤 분포를 보고 정한다([근거] 08-26 정상 −66행 vs 08-24 불량 −42행 —
--    행 수로는 못 가른다. 가른 신호는 list_total·페이지 수·소요 시간이었다).
-- ⚠️ aborted 회차도 기록한다 — 중단된 회차가 가장 알고 싶은 회차다.
--    dry 회차는 기록하지 않는다(수동 조사용 — 기준선 오염).
-- ⚠️ wrote / existing_rows_before / db_rows_after 는 정상 적재 경로에만 있다 — aborted 는
--    한 행도 쓰지 않으므로 null (nullable 인 이유).
--
-- 조회(회차 간 비교): select ran_at, snapshot_key, ok, aborted, list_total, pages_scanned,
--   duration_ms, received_rows, wrote from inv_snapshot_runs order by ran_at desc limit 14;

create table inv_snapshot_runs (
  id                   bigint generated always as identity primary key,
  ran_at               timestamptz not null default now(),   -- EF 가 보내지 않는다 — DB default
  snapshot_key         text not null,          -- 예: 2026-08-26-compare (auto-compare 해석 후 값)
  taken_at             timestamptz not null,   -- EF 요청 시작 시각 (inv_snapshot.taken_at 과 동일 값)
  ok                   boolean not null,       -- 응답의 ok 그대로 (aborted → false)
  aborted              text,                   -- 'time'|'rate_limited'|'page_error'|'incomplete' · 정상 null
  abort_note           text,
  list_total           int,                    -- Cin7 목록 Total — ⚠️ 급감 검사의 1축. 첫 페이지 전 중단이면 null
  pages_scanned        int not null,           -- ⚠️ 급감 검사의 2축
  duration_ms          int not null,           -- ⚠️ 급감 검사의 3축 (불량 회차는 2.4배 느렸다)
  received_rows        int not null,
  insert_rows          int not null,           -- 합산 후 적재 대상 행 수 (agg.size)
  wrote                int,                    -- db_rows_after − existing_rows_before · aborted 는 null
  existing_rows_before int,
  db_rows_after        int,
  truncated            boolean,                -- listTotal null 이면 판정 불가 → null
  rate_limited         boolean not null,
  warehouses           jsonb not null,         -- 창고별 rows/skus/bins/onhand_sum/value_sum
  summary              jsonb not null          -- 응답 summary 전문 (null_bin_nonzero 등 재조사 재료)
);

create index inv_snapshot_runs_ran_at_idx on inv_snapshot_runs (ran_at desc);

-- RLS — auth_all + anon 전부 회수. 쓰기 주체는 EF(service_role — RLS 우회, 서버사이드
-- 정상 경로 · 규칙 8).
-- ⚠️ DELETE/TRUNCATE 회수는 inv_missing_lines 와 같고 inv_compare_runs 와 다르다 — 의도다:
--    inv_compare_runs 는 매일 재계산되는 결과라 지워져도 다시 만들 수 있지만, 회차 로그는
--    「그때 무슨 일이 있었나」의 증거라 재생성이 불가능하다. 급감 검사는 「직전 회차와 비교」
--    인데 직전 행이 지워지면 판정 자체가 불가능해진다.
alter table inv_snapshot_runs enable row level security;
create policy auth_all on inv_snapshot_runs for all to authenticated using (true) with check (true);
revoke all on inv_snapshot_runs from anon;
revoke delete, truncate on inv_snapshot_runs from authenticated;
