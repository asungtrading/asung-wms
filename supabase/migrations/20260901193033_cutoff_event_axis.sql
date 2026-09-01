-- 컷오프 축 정정 — 과거 사건은 늦게 수집돼도 자르지 않는다 (2026-09-01)
--
-- 문제: manual 면제(20260901191929) 뒤에도 토론토 7칸·격차 113 — 기대(아침 9 − 정정 6 = 3칸)가
--   아니다. [실물 WTA00219 A070401 · 원장 402 vs Cin7 342 · diff +60]
--     manual :binfixed             −60   포함(면제)
--     manual :binfixed:superseded  +60   포함(면제)   → 합 0
--     cin7   A070401               −60   ⚠️ 오늘 낮 수집 → 잘린다
--   ⇒ 상쇄와 재기록이 **짝**인데 반쪽만 들어와 원장이 60 많아 보였다.
--   📌 SKL01861 D110301 +6 · SBO70659 +20 · WTA00220/286 각 +6 전부 같은 구조.
--
-- ⭐ 원인: 컷오프 축이 틀렸다 — 자르고 싶은 것은 「스냅샷 이후에 **일어난** 사건」인데
--   「스냅샷 이후에 **수집된** 행」을 잘랐다. cin7 A070401 −60 은 occurred_on 8/21(과거 사건)
--   이고 created_at 만 오늘이다 — Cin7 스냅샷은 8/21 사건을 이미 반영했으므로 자르면 안 된다.
--   ⚠️ 이 부류는 앞으로도 계속 생긴다 — 커서가 밀리거나(결함 C·D) 재수집하거나 bin 규칙을
--   바꾸면 과거 사건이 오늘 수집된다. 오늘만의 일이 아니다.
--
-- 처방: delta 의 where 에 조건 하나 추가 —
--   source='manual'  or  occurred_on < 스냅샷의 토론토 날짜  or  created_at <= taken_at
--   | 과거 사건을 오늘 늦게 수집        | ⭐ 포함 | Cin7 스냅샷이 이미 반영했다        |
--   | 오늘 사건을 오늘(스냅샷 후) 수집  | 잘림   | 스냅샷에 없다                     |
--   | 오늘 사건인데 01:21 이전 수집     | 포함   | created_at 이 가른다              |
--   | manual 정정                       | 포함   | 뒤늦게 적은 과거 사실             |
-- ⚠️⚠️ 날짜 필터 하나만으로는 안 된다 — 2026-09-01 오전에 이미 실패했다(오후 49칸 ·
--   01:21 스냅샷이 그날 00:00~01:21 사건을 포함하는데 날짜로 자르면 그것까지 빠진다).
--   ⇒ created_at 과 **함께** 써야 순간이 맞는다. 두 조건은 서로를 보완한다.
-- 📌 시간대: taken_at 은 timestamptz · occurred_on 은 Cin7 의 현지 날짜 ⇒ 토론토로 변환해
--   비교한다(이 레포의 시각 처리 관례).
--
-- ⚠️ 남는 한계:
-- · 스냅샷 당일에 일어나고 스냅샷 직전에 우리가 못 받은 사건은 여전히 오탐이다
--   (수집 창 5분~1시간). 컷오프의 목적상 어쩔 수 없고, 창이 일정해 값이 시각마다 뛰지는 않는다.
-- · manual 을 잘못 넣으면 대조가 즉시 그것을 정답으로 받아들인다 —
--   정정 전에 근거를 raw 에 남기는 관례가 그래서 중요하다.
--
-- ⚠️ inv_balance·inv_stock_master 무접촉 — RPC 는 뷰 값을 그대로 쓰므로 자동 추종한다.
-- ⚠️ 이 파일은 delta 의 where 한 줄만 빼면 20260901191929 의 뷰 정의와 동일하다.

create or replace view inv_balance_vs_cin7 as
with latest as (
  select snapshot_key as k, max(taken_at) as at
  from inv_snapshot
  group by snapshot_key
  order by max(taken_at) desc
  limit 1
),
baseline as (
  select value as k from inv_config where key = 'baseline_snapshot_key'
),
snap_base as (
  select s.sku, s.warehouse, coalesce(s.bin, '') as bin, sum(s.qty) as qty
  from inv_snapshot s, baseline b
  where s.snapshot_key = b.k
  group by 1, 2, 3
),
delta as (
  select l.sku, l.warehouse, coalesce(l.bin, '') as bin, sum(l.qty_delta) as qty
  from inv_ledger l, latest la
  where l.source = 'manual'                                            -- 정정 — 뒤늦게 적은 과거 사실
     or l.occurred_on < (la.at at time zone 'America/Toronto')::date   -- ⭐ 과거 사건은 늦게 수집돼도 무조건
     or l.created_at <= la.at                                          -- 당일 사건은 수집 시각이 가른다
  group by 1, 2, 3
),
led as (
  select coalesce(s.sku, d.sku)             as sku,
         coalesce(s.warehouse, d.warehouse) as warehouse,
         coalesce(s.bin, d.bin)             as bin,
         coalesce(s.qty, 0) + coalesce(d.qty, 0) as qty
  from snap_base s
  full join delta d
    on d.sku = s.sku and d.warehouse = s.warehouse and d.bin = s.bin
),
cin7 as (
  select s.sku, s.warehouse, coalesce(s.bin, '') as bin, sum(s.qty) as qty
  from inv_snapshot s, latest l
  where s.snapshot_key = l.k
  group by 1, 2, 3
)
select
  coalesce(le.sku, c.sku)             as sku,
  coalesce(le.warehouse, c.warehouse) as warehouse,
  coalesce(le.bin, c.bin)             as bin,
  coalesce(le.qty, 0)                 as ledger_qty,
  coalesce(c.qty, 0)                  as cin7_qty,
  coalesce(le.qty, 0) - coalesce(c.qty, 0) as diff
from (select * from led where warehouse <> 'IN_TRANSIT') le
full join cin7 c
  on c.sku = le.sku and c.warehouse = le.warehouse and c.bin = le.bin;

-- ⚠️ create or replace 가 권한을 되돌릴 수 있다 — anon 회수를 다시 건다(inv_* 관례).
revoke all on inv_balance_vs_cin7 from anon;

-- 계약 문구 유지 + 이번 규칙 한 줄
comment on view inv_balance_vs_cin7 is
  'ledger balance vs latest Cin7 snapshot at the SAME instant - ledger deltas are cut off at created_at <= snapshot taken_at, so the result is identical whenever you query it (2026-09-01). Past-dated events (occurred_on before the snapshot''s Toronto date) are never cut, however late they were collected - the Cin7 snapshot already reflects them. Manual correction rows (source=''manual'') are EXEMPT from the cutoff - they state facts the ledger should have known at snapshot time, so a fix shows up in the compare immediately. Columns (sku,warehouse,bin,ledger_qty,cin7_qty,diff) are a contract read by inv_stock_master, inv_snap_balance_diffs and morning check 8 - renaming breaks the stock-master screen silently.';

-- ─────────────────────────────────────────────────────────
-- 검증 (마이그레이션 후 Caleb 이 실행 — 지시서 §4)
-- ─────────────────────────────────────────────────────────
-- ① ⭐ 판정 — 아침 9칸에서 오늘 정정 6칸을 뺀 값이 나와야 한다
--    기대: 토론토 3칸 · 격차 16 근처 · 에드먼튼 2칸 · 6
--   select warehouse, count(*) as bin_pairs,
--          count(*) filter (where diff <> 0) as mismatch,
--          sum(abs(diff)) filter (where diff <> 0) as abs_gap
--   from inv_balance_vs_cin7 group by warehouse order by 1;
-- ② ⭐ 목록 — 남아야 할 것만 남았나 (⚠️ 이것이 진짜 판정 — ①의 숫자만 보지 말 것)
--    기대: BNAT48173 +11 · CAN01003 −4 · UNF18261 '' +1 · PRO00124 짝(에드먼튼)
--    ⚠️ WTA00219/220/286 · SBO70659 · SKL01861 이 남아 있으면 실패다
--   select sku, warehouse, bin, ledger_qty, cin7_qty, diff
--   from inv_balance_vs_cin7 where diff <> 0 order by abs(diff) desc;
-- ③ 낮 사건은 여전히 잘리는가 (컷오프 생존 확인) — 📌 0 이면 판정 보류
--   select count(*) as todays_cin7_after_snapshot
--   from inv_ledger l,
--        (select max(taken_at) at from inv_snapshot
--         where snapshot_key = (select snapshot_key from inv_snapshot
--                               group by snapshot_key order by max(taken_at) desc limit 1)) s
--   where l.source = 'cin7' and l.created_at > s.at
--     and l.occurred_on >= (s.at at time zone 'America/Toronto')::date;
-- ④ 과거 사건이 늦게 수집된 것 — 이번에 살아난 부류
--   select count(*) as past_events_collected_late
--   from inv_ledger l,
--        (select max(taken_at) at from inv_snapshot
--         where snapshot_key = (select snapshot_key from inv_snapshot
--                               group by snapshot_key order by max(taken_at) desc limit 1)) s
--   where l.source = 'cin7' and l.created_at > s.at
--     and l.occurred_on < (s.at at time zone 'America/Toronto')::date;
-- ⑤ RPC 도 같은 값 + 산수(at_snapshot − cin7 = diff)
--   select jsonb_pretty(inv_stock_master(p_only_diff := true, p_limit := 20));
-- ⑥ 권한 — replace 뒤 anon 이 살아나지 않았나
--   select grantee, privilege_type from information_schema.role_table_grants
--   where table_name = 'inv_balance_vs_cin7' order by 1,2;
