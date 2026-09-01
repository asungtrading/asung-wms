-- 시점 컷오프 — 대조를 언제 봐도 같은 값으로 (2026-09-01)
--
-- 문제: Cin7 스냅샷은 01:21 의 한순간인데 원장 델타는 그 뒤로 계속 쌓인다 ⇒ 낮 사건이
--   전부 「원장이 과하게 뺐다」로 잡혔다. [실측 2026-09-01 · 같은 날 · 같은 정의]
--   아침 08시 토론토 9칸·격차 52 vs 오후 14시 475칸(전 창고).
--   ⚠️ 실제 피해: inv_snap_balance_diffs() 를 오후 14:48 에 수동으로 돌려 475행이 굳었다
--   (삭제로 정정 — cron 이 잘못된 시각에 돌면 같은 일이 난다).
-- ⚠️ 날짜 필터(occurred_on)로는 못 고친다 — 01:21 스냅샷이 그날 00:00~01:21 사건을 이미
--   포함하는데 날짜 단위로 자르면 그것까지 빠진다(실측 오후 49칸).
-- ⇒ 처방: **수집 시각(created_at)으로 자른다** — created_at <= 최신 스냅샷 taken_at.
--   「스냅샷을 찍던 그 순간까지 원장이 알고 있던 것」과 스냅샷을 댄다. 양쪽 시각이 같다.
--   (created_at 은 「사건 시각」이 아니라 「원장 기록 시각」 — 스냅샷 시점의 원장 상태를
--    재현하는 것이므로 그것이 맞는 축이다. WMS 세션이 짚어준 길.)
-- ⚠️ 남는 한계: 사건 발생 ~ 수집 사이의 창(주기 5분~1시간)에 스냅샷이 찍히면 그 사건은
--   스냅샷에만 있고 원장에는 없다 — 소량 오탐이 남는다. 📌 그래도 몇 시간짜리 드리프트보다
--   훨씬 작고, 창이 일정해(주기 고정) 값이 시각마다 뛰지 않는다.
--
-- ⚠️ inv_balance 는 고치지 않는다 — 그건 **지금 재고**다. 컷오프는 **대조 축에만** 필요하다.
-- ⚠️ 새 뷰를 만들지 않고 기존 inv_balance_vs_cin7 을 교체한다 — 아침 점검 ⑧ ·
--   inv_snap_balance_diffs() · inv_stock_master 가 모두 이 뷰를 쓴다. 정의가 둘이면
--   어느 것이 맞는지 다시 모르게 된다.

-- ─────────────────────────────────────────────────────────
-- 1) inv_balance_vs_cin7 — 시점 컷오프 판으로 교체
-- ─────────────────────────────────────────────────────────
-- ⚠️ IN_TRANSIT 은 Cin7 쪽에 대응이 없으므로 제외한다.
-- ⚠️ latest 는 taken_at 최댓값 기준이다 — 스냅샷 키 이름 규칙에 기대지 않는다.
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
  where l.created_at <= la.at          -- ⭐ 시점 컷오프
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

-- 계약 문구 — wms_order_pack_progress 관례(WMS 답신 요청)
comment on view inv_balance_vs_cin7 is
  'ledger balance vs latest Cin7 snapshot at the SAME instant - ledger deltas are cut off at created_at <= snapshot taken_at, so the result is identical whenever you query it (2026-09-01). Columns (sku,warehouse,bin,ledger_qty,cin7_qty,diff) are a contract read by inv_stock_master, inv_snap_balance_diffs and morning check 8 - renaming breaks the stock-master screen silently.';

-- ─────────────────────────────────────────────────────────
-- 2) inv_stock_master — 응답에 「어느 시점인지」를 담는다
-- ─────────────────────────────────────────────────────────
-- ⚠️ 화면이 「○시 기준」을 크게 띄워야 한다(WMS 요구) — snapshot_key·snapshot_at 추가.
--   rows·total 의 모양(키)은 그대로다 — 화면 계약이 문서에 박혀 있다.
-- ⭐ [함께 정정] 대조값(cin7_qty·diff)은 **컷오프 뷰의 값 그대로** 쓴다 — 종전처럼
--   라이브 잔고(inv_balance.qty)에서 재계산하면 컷오프를 넣고도 p_only_diff 가 낮 드리프트를
--   「이상」으로 세어 검증 ③(RPC 도 같은 값)이 성립하지 않는다.
--   ⇒ 행의 시점 축이 둘이다 — **산수가 표 안에서 맞도록 넷을 준다**:
--     ledger_qty              지금 재고 (inv_balance · 라이브)   ← 재고 마스터의 주역
--     ledger_qty_at_snapshot  아침 시점 재고 (컷오프)            ⭐ diff 의 근거
--     cin7_qty                아침 스냅샷
--     diff                    = ledger_qty_at_snapshot − cin7_qty ← 산수가 맞는다
--   ledger_qty − ledger_qty_at_snapshot = 스냅샷 이후 낮 동안의 변동이다.
--   IN_TRANSIT·스냅샷 이후 생긴 칸은 뷰에 없어 at_snapshot·cin7_qty·diff 가 null = 「비교 불가」.
create or replace function inv_stock_master(
  p_search     text    default null,   -- sku 부분일치 (⚠️ 대소문자 무시 — ilike)
  p_warehouse  text    default null,   -- null = 전체
  p_only_diff  boolean default false,  -- ⭐ 이상만 보기
  p_nonzero    boolean default true,   -- 재고 0 인 칸 숨기기 (기본 숨김)
  p_limit      int     default 200,
  p_offset     int     default 0
) returns jsonb
language sql stable security invoker
as $$
  with latest as (
    select snapshot_key as k, max(taken_at) as at
    from inv_snapshot
    group by snapshot_key
    order by max(taken_at) desc
    limit 1
  ),
  j as (
    select
      b.sku, b.warehouse, b.bin,
      b.baseline_qty, b.delta_qty, b.qty as ledger_qty,
      c.ledger_qty as ledger_qty_at_snapshot,
      c.cin7_qty, c.diff
    from inv_balance b
    left join inv_balance_vs_cin7 c
      on  c.sku = b.sku and c.warehouse = b.warehouse and c.bin = b.bin
    union all
    -- Cin7 에만 있는 칸 — 원장 잔고 축에 행이 없다(기초에도 원장에도 없던 자리)
    select c.sku, c.warehouse, c.bin, 0, 0, 0, c.ledger_qty, c.cin7_qty, c.diff
    from inv_balance_vs_cin7 c
    where not exists (
      select 1 from inv_balance b
      where b.sku = c.sku and b.warehouse = c.warehouse and b.bin = c.bin
    )
  ),
  f as (
    select * from j
    where (p_search    is null or sku ilike '%' || p_search || '%')
      and (p_warehouse is null or warehouse = p_warehouse)
      and (not p_only_diff or (diff is not null and diff <> 0))
      and (not p_nonzero  or ledger_qty <> 0 or coalesce(cin7_qty, 0) <> 0)
  )
  select jsonb_build_object(
    'total', (select count(*) from f),
    'snapshot_key', (select k from latest),   -- ⭐ 화면의 「○시 기준」 표시용
    'snapshot_at',  (select at from latest),
    'rows',  coalesce((
      select jsonb_agg(x order by x.sku, x.warehouse, x.bin)
      from (select * from f order by sku, warehouse, bin
            limit greatest(p_limit,1) offset greatest(p_offset,0)) x
    ), '[]'::jsonb)
  );
$$;

-- create or replace 는 함수 ACL 을 유지하지만, 명시가 관례다 — 다시 건다.
revoke all on function inv_stock_master(text,text,boolean,boolean,int,int) from public, anon;
grant execute on function inv_stock_master(text,text,boolean,boolean,int,int) to authenticated;

-- ─────────────────────────────────────────────────────────
-- 검증 (마이그레이션 후 Caleb 이 실행 — 지시서 §5)
-- ─────────────────────────────────────────────────────────
-- ① ⭐ 핵심 — 오후에 돌려도 아침 값이 나와야 한다
--    [기준] 2026-09-01 아침 실측: 토론토 9칸 · 격차 52 · 에드먼튼 2칸 · 6
--    ⚠️ 아침 값(토론토 9칸 근처)과 다르면 멈출 것 — 컷오프가 안 먹은 것이다.
--   select warehouse, count(*) as bin_pairs,
--          count(*) filter (where diff <> 0) as mismatch,
--          sum(abs(diff)) filter (where diff <> 0) as abs_gap
--   from inv_balance_vs_cin7 group by warehouse order by 1;
-- ② 어긋난 칸 실물 — 아침에 본 그 목록과 같아야 한다
--    (BNAT48173 +11 · CAN01003 −4 · UNF18261 '' +1 · PRO00124 짝 · SKL01861 은 해소됨)
--   select * from inv_balance_vs_cin7 where diff <> 0 order by abs(diff) desc;
-- ③ RPC 도 같은 값 + 시점 표시
--   select jsonb_pretty(inv_stock_master(p_only_diff := true, p_limit := 20));
-- ④ 일지 — 이제 언제 돌려도 안전하다
--   select jsonb_pretty(inv_snap_balance_diffs());
--   select checked_on, first_seen_on, count(*) from inv_balance_diffs group by 1,2 order by 1 desc;
-- ⑤ 성능 — 컷오프가 인덱스를 타는지 (느리면 inv_ledger(created_at) 인덱스 검토 — 재보고 정한다)
--   explain analyze select count(*) from inv_balance_vs_cin7 where diff <> 0;
-- ⑥ 권한 — create or replace 뒤에 anon 이 살아나지 않았나
--   select grantee, privilege_type from information_schema.role_table_grants
--   where table_name in ('inv_balance','inv_balance_vs_cin7') order by 1,2;
