-- 컷오프 정정 — manual 은 자르지 않는다 (2026-09-01)
--
-- 문제: 방금 넣은 시점 컷오프(created_at <= 스냅샷 taken_at · 20260901185640)가
--   **source='manual' 정정 행을 제외**한다 — 정정은 사건 시각이 과거인데 기록 시각은 현재라서다.
--   [실측 2026-09-01 오후] 컷오프 전 토론토 475칸 → 컷오프 후 161칸 ⚠️ 아침 값 9칸이 아니다
--   (에드먼튼 2칸 = 아침과 같음 — 오늘 정정이 토론토에만 있었다).
--   [실물 ANN01111] 라이브 20(Cin7 과 일치 ✅)인데 at_snapshot −4 · diff −24 —
--   컷오프가 상쇄를 잘라 **상쇄 전 상태로 되돌렸다.** total 157 = 오늘 아침 상쇄한 경계 오더
--   행 수와 정확히 같다(오늘 정정 171행 = 경계 157 + bin 8 + SKL01861 1 + FG-00131 5 이
--   전부 스냅샷 05:21 UTC 이후 기록).
--
-- 처방: delta 의 where 를 `source='manual' or created_at <= 스냅샷` 으로.
-- · manual 은 사람이 판단해 넣는 정정이다. 「스냅샷 시점에 원장이 알았어야 할 사실」을
--   뒤늦게 적는 것이므로 컷오프 대상이 아니다.
-- · ⚠️ 그러므로 manual 을 잘못 넣으면 대조가 **즉시** 그것을 정답으로 받아들인다.
--   정정 전에 근거를 raw 에 남기는 관례가 그래서 중요하다.
-- · 컷오프의 대상은 source='cin7' — 낮에 수집된 진짜 사건이다. 그것은 그대로 잘린다.
-- 📌 그리고 그것이 원하는 동작이다 — **고쳤으면 대조가 바로 맞아야** 한다. 다음날까지
--   기다리면 「고친 것이 맞나」를 그날 확인할 수 없다(오늘 그 확인을 네 번 했다).
--
-- ⚠️ inv_balance 무접촉 — 라이브이고 이미 맞다(ANN01111 이 20). RPC(inv_stock_master)도
--   무접촉 — 뷰 값을 그대로 쓰므로 자동으로 따라온다.
-- ⚠️ 이 파일은 delta 의 where 한 줄만 빼면 20260901185640 의 뷰 정의와 동일하다.

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
  where l.source = 'manual' or l.created_at <= la.at   -- ⭐ 시점 컷오프 — manual 정정은 자르지 않는다
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
  'ledger balance vs latest Cin7 snapshot at the SAME instant - ledger deltas are cut off at created_at <= snapshot taken_at, so the result is identical whenever you query it (2026-09-01). Manual correction rows (source=''manual'') are EXEMPT from the cutoff - they state facts the ledger should have known at snapshot time, so a fix shows up in the compare immediately. Columns (sku,warehouse,bin,ledger_qty,cin7_qty,diff) are a contract read by inv_stock_master, inv_snap_balance_diffs and morning check 8 - renaming breaks the stock-master screen silently.';

-- ─────────────────────────────────────────────────────────
-- 검증 (마이그레이션 후 Caleb 이 실행 — 지시서 §4)
-- ─────────────────────────────────────────────────────────
-- ① ⭐ 판정 — 오후인데도 아침 값이 나와야 한다
--    [기준] 2026-09-01 아침 실측: 토론토 9칸 · 격차 52 · 에드먼튼 2칸 · 6
--    ⚠️ 아침 값(토론토 9칸 근처)과 다르면 멈출 것.
--   select warehouse, count(*) as bin_pairs,
--          count(*) filter (where diff <> 0) as mismatch,
--          sum(abs(diff)) filter (where diff <> 0) as abs_gap
--   from inv_balance_vs_cin7 group by warehouse order by 1;
-- ② ⭐ ANN01111 — at_snapshot 이 −4 가 아니라 20 이어야 한다
--   select sku, bin, ledger_qty, cin7_qty, diff
--   from inv_balance_vs_cin7 where sku = 'ANN01111';
-- ③ 어긋난 칸 실물 — 아침에 본 목록과 같아야 한다
--    (BNAT48173 +11 · CAN01003 −4 · UNF18261 '' +1 · PRO00124 짝 · UNF1805x 는 해소됨)
--   select * from inv_balance_vs_cin7 where diff <> 0 order by abs(diff) desc;
-- ④ RPC 도 같은 값 + 산수
--   select jsonb_pretty(inv_stock_master(p_only_diff := true, p_limit := 20));
-- ⑤ 낮 사건은 여전히 잘리는가 (컷오프가 살아 있나) — 📌 0 이 아니어야 판정이 된다
--    (0 이면 낮에 수집된 것이 없다는 뜻)
--   select count(*) as cin7_rows_after_snapshot
--   from inv_ledger l, (select max(taken_at) at from inv_snapshot
--                       where snapshot_key = (select snapshot_key from inv_snapshot
--                                             group by snapshot_key order by max(taken_at) desc limit 1)) s
--   where l.source = 'cin7' and l.created_at > s.at;
