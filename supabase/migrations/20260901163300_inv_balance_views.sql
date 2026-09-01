-- 잔고 뷰 — 재고 마스터의 첫 조각 (2026-09-01)
--
-- 왜: 「원장이 말하는 재고」의 정의가 세 곳에 흩어져 있었다 — 아침 점검 ⑧ SQL ·
--   inv-collect 의 잔고 규칙(2026-09-01) · 앞으로의 재고 마스터 화면.
--   세 곳이 조금씩 달라지면 어느 것이 맞는지 알 수 없다 ⇒ 정의를 한 곳(inv_balance)에 둔다.
--   화면은 별도 작업(asung-bq-apps 관례) · EF·스크립트가 정의를 이 뷰로 옮기는 것도 다음 단계.
--
-- ⚠️ 잔고 테이블 신설이 아니라 뷰다 — 테이블은 원장과 어긋날 위험이 크다.
-- ⚠️ 일반 뷰(머티리얼라이즈드 아님) — 항상 최신이지만 매번 계산한다.
--   느리면 그때 머티리얼라이즈드로 옮긴다. 성능은 재보고 정한다.

-- ─────────────────────────────────────────────────────────
-- 1) inv_config — 기준선 설정
--    ⚠️ 스냅샷 키를 뷰에 박으면 재기준선 때 뷰를 고쳐야 한다 — 설정으로 뺀다.
-- ─────────────────────────────────────────────────────────
create table inv_config (
  key         text primary key,
  value       text not null,
  note        text,
  updated_at  timestamptz not null default now()
);

-- ⚠️ 재기준선을 잡으면 이 값과 cron URL 의 since= 를 **함께** 바꿔야 한다.
--    둘이 갈라지면 잔고가 조용히 틀어진다.
insert into inv_config (key, value, note) values
  ('baseline_snapshot_key', '2026-08-20-initial',
   'Baseline for every ledger balance. ⚠️ Must move together with the since= parameter on the inv-collect cron URLs - if they diverge the balance silently drifts.');

alter table inv_config enable row level security;
create policy auth_all on inv_config for all to authenticated using (true) with check (true);
revoke all on inv_config from anon;

-- ─────────────────────────────────────────────────────────
-- 2) inv_balance — 원장이 말하는 재고 (sku, warehouse, bin 단위)
-- ─────────────────────────────────────────────────────────
-- 정의: 기초 스냅샷 + 그 이후 원장 델타 전부.
-- ⚠️ IN_TRANSIT 도 포함한다 — 합성 창고지만 원장의 정식 축이고, 빼려면
--    보는 쪽에서 빼는 것이 맞다(여기서 빼면 총량이 안 맞는다).
-- 📌 bin 은 '' 가 정상인 경우가 있다: 에드먼튼 도착 대기 자리 · IN_TRANSIT.
--    「비어 있다 = 결손」이 아니다.
-- ⚠️ baseline_qty·delta_qty 를 따로 남긴다 — 어긋남을 볼 때 어느 쪽에서 왔는지 갈린다.
create view inv_balance as
with baseline as (
  select value as k from inv_config where key = 'baseline_snapshot_key'
),
snap as (
  select s.sku, s.warehouse, coalesce(s.bin, '') as bin, sum(s.qty) as qty
  from inv_snapshot s, baseline b
  where s.snapshot_key = b.k
  group by 1, 2, 3
),
delta as (
  select l.sku, l.warehouse, coalesce(l.bin, '') as bin, sum(l.qty_delta) as qty
  from inv_ledger l
  group by 1, 2, 3
)
select
  coalesce(s.sku, d.sku)             as sku,
  coalesce(s.warehouse, d.warehouse) as warehouse,
  coalesce(s.bin, d.bin)             as bin,
  coalesce(s.qty, 0)                 as baseline_qty,
  coalesce(d.qty, 0)                 as delta_qty,
  coalesce(s.qty, 0) + coalesce(d.qty, 0) as qty
from snap s
full join delta d
  on d.sku = s.sku and d.warehouse = s.warehouse and d.bin = s.bin;
-- ⚠️ full join — 기초에만 있는 것과 원장에만 있는 것이 둘 다 나와야 한다.

-- ─────────────────────────────────────────────────────────
-- 3) inv_balance_vs_cin7 — 원장 잔고 vs 그날 Cin7 스냅샷 (아침 점검 ⑧ 의 정의)
-- ─────────────────────────────────────────────────────────
-- ⚠️⚠️ **아침 스냅샷 직후에만 유효하다.** 스냅샷은 01:21 의 한순간인데 원장은 그 뒤로
--    계속 쌓이므로, 오후에 보면 낮 판매가 전부 「원장이 과하게 뺐다」로 잡힌다.
--    [실측 2026-09-01] 같은 날 같은 계산이 아침 9칸 · 오후 128칸을 냈다.
--    ⚠️ occurred_on 날짜 필터도 답이 아니다 — 01:21 스냅샷은 그날 00:00~01:21 사건을
--    이미 포함하는데 필터가 그것까지 뺀다(오후 49칸).
-- ⚠️ IN_TRANSIT 은 Cin7 쪽에 대응이 없으므로 제외한다.
-- ⚠️ latest 는 taken_at 최댓값 기준이다 — 스냅샷 키 이름 규칙에 기대지 않는다.
create view inv_balance_vs_cin7 as
with latest as (
  select snapshot_key as k
  from inv_snapshot
  group by snapshot_key
  order by max(taken_at) desc
  limit 1
),
cin7 as (
  select s.sku, s.warehouse, coalesce(s.bin, '') as bin, sum(s.qty) as qty
  from inv_snapshot s, latest l
  where s.snapshot_key = l.k
  group by 1, 2, 3
),
led as (
  select sku, warehouse, bin, qty from inv_balance where warehouse <> 'IN_TRANSIT'
)
select
  coalesce(le.sku, c.sku)             as sku,
  coalesce(le.warehouse, c.warehouse) as warehouse,
  coalesce(le.bin, c.bin)             as bin,
  coalesce(le.qty, 0)                 as ledger_qty,
  coalesce(c.qty, 0)                  as cin7_qty,
  coalesce(le.qty, 0) - coalesce(c.qty, 0) as diff
from led le
full join cin7 c
  on c.sku = le.sku and c.warehouse = le.warehouse and c.bin = le.bin;

-- ⚠️ anon 회수 — inv_* 관례(전 테이블 anon 전부 회수)와 정합. 뷰는 소유자 권한으로 돌므로
--    (security_invoker 아님) anon 에 열어두면 원본 테이블의 RLS·회수를 우회해 원장이 노출된다.
revoke all on inv_balance from anon;
revoke all on inv_balance_vs_cin7 from anon;

-- ─────────────────────────────────────────────────────────
-- 검증 (마이그레이션 후 Caleb 이 실행 — 지시서 §4)
-- ─────────────────────────────────────────────────────────
-- ① 뷰가 도나 · 몇 행인가
--   select count(*) as rows, count(distinct sku) as skus, count(distinct warehouse) as whs
--   from inv_balance;
--
-- ② ⭐ 아침 점검 ⑧ 과 같은 값이 나오나 (2026-09-01 아침 기준: 토론토 9칸 · 격차 52)
--   ⚠️ 오후에 재면 값이 다르다(위 시점 경고) — 판정은 아침 값과 비교할 것.
--   select warehouse, count(*) as bin_pairs,
--          count(*) filter (where diff <> 0) as mismatch,
--          sum(abs(diff)) filter (where diff <> 0) as abs_gap
--   from inv_balance_vs_cin7 group by warehouse order by 1;
--
-- ③ 어긋난 칸 실물
--   select * from inv_balance_vs_cin7 where diff <> 0 order by abs(diff) desc;
--
-- ④ 성능 — 느리면 머티리얼라이즈드로 옮긴다
--   explain analyze select count(*) from inv_balance_vs_cin7 where diff <> 0;
--
-- ⑤ ⚠️ 음수 재고 — 앞으로 이 축을 쓴다
--   select * from inv_balance where qty < 0 order by qty limit 20;
