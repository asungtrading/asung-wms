-- 수집 회차 로그 — inv_collect_runs (2026-08-31)
--
-- 배경: 결함 C(08-29 커서 동결)·D(08-31 캡 누락) 둘 다 **EF 응답에는 신호가 있었는데**
--   (cursor_after_would_be == cursor_before · hold_capped 120) 아무도 응답을 안 봐서
--   각각 하루 반·사흘 늦게 알았다. cron 은 응답을 읽지 않고 job_run_details 는 늘 succeeded 다
--   (결함 C 때 350회+). ⇒ 회차 결과를 남겨 아침 점검이 SQL 한 줄이 되게 한다.
--   📌 inv_snapshot_runs(20260826…)가 스냅샷에 한 역할과 같은 틀. 급감 검사도 나중에 여기 얹는다.
--
-- ⚠️ dry 회차는 남기지 않는다 — 수동 조사가 기준선을 오염시킨다(inv_snapshot_runs 와 같은 판단).
-- ⚠️ 로그 실패가 수집을 막지 않는다 — EF 는 try/catch 로 감싸고 실패해도 수집·커서는 정상 진행.
-- 📌 보존: 전부 남기되 오래된 「정상」 회차는 정리한다(§보존 정책 주석 · 정리는 사람이 판단).
--
-- 조회(아침 점검): 아래 「이상 회차」 한 줄
--   select source_key, ran_at, detail_capped, hold_capped, detail_capped_remaining,
--          cursor_stalled_alert, cursor_frozen_alert
--   from inv_collect_runs
--   where ran_at > now() - interval '24 hours'
--     and (detail_capped or coalesce(hold_capped,0) > 0
--          or cursor_stalled_alert is not null or cursor_frozen_alert is not null
--          or not ok)
--   order by ran_at desc;

create table inv_collect_runs (
  id                      bigint generated always as identity primary key,
  ran_at                  timestamptz not null default now(),
  source_key              text        not null,   -- transfer·sale·purchase·adjustment·assembly·creditnote
  ok                      boolean     not null,
  collector               text        not null,   -- COLLECTOR_VERSION

  -- ⭐ 밀림 축 — 이 셋이 결함 C·D 를 즉시 드러냈을 값이다
  detail_capped           boolean     not null default false,
  detail_capped_reason    text,                   -- 'time' | 'max_detail' | 'rate_limited'
  detail_capped_remaining integer     not null default 0,
  hold_capped             integer,                -- ②-a 전용 — 캡 때문에 손도 못 댄 후보 수
  cursor_before           text,
  cursor_after            text,
  cursor_stalled_alert    text,                   -- 결함 C 증상 가드 (②-b)
  cursor_frozen_alert     text,                   -- 결함 B 가드 (②-b)

  -- 회차 실적
  list_total              integer,
  list_received           integer,
  pages                   integer,
  truncated               boolean,
  list_aborted            text,
  candidates              integer,
  docs_processed          integer,
  detail_fetched          integer,
  ledger_rows             integer,
  inserted                integer,
  insert_skipped          integer,
  skipped_unchanged       integer,                -- 결함 D 처방(inv_doc_state)의 효과
  precision_skipped       integer,
  write_skipped           text,                   -- commit 이 차단된 사유

  -- 원본 보존 — 지금 안 써도 남긴다(나중에 필요해질 필드를 지금 다 알 수 없다)
  dispositions            jsonb,
  warnings                jsonb,
  summary                 jsonb,

  duration_ms             integer
);

create index inv_collect_runs_ran_idx on inv_collect_runs (source_key, ran_at desc);
-- 이상 회차만 빠르게 — 아침 점검의 주 경로
create index inv_collect_runs_alert_idx on inv_collect_runs (ran_at desc)
  where detail_capped or not ok;

-- RLS — inv_snapshot_runs·inv_missing_lines 와 동일. 쓰기 주체는 EF(service_role).
-- ⚠️ DELETE 는 회수하지 않는다 — 오래된 정상 회차를 정리해야 하기 때문이다(보존 정책).
--    ⚠️ 다만 이상 회차(detail_capped·not ok·*_alert)는 지우지 말 것 — 재생성 불가능한 증거다.
alter table inv_collect_runs enable row level security;
create policy auth_all on inv_collect_runs for all to authenticated using (true) with check (true);
revoke all on inv_collect_runs from anon;
