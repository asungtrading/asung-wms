-- inv_stock_master 성능 수리 — j 를 한 번만 계산한다 (2026-09-05)
--
-- 무엇이 문제였나: 재고 마스터 화면(inventory.html)이 부르는 이 RPC 가 3,891 ms 였다.
--   j CTE 가 `inv_balance left join inv_balance_vs_cin7` **union all** `inv_balance_vs_cin7 where
--   not exists(inv_balance)` 두 갈래라, 뷰가 인라인되어 **inv_balance_vs_cin7 2회 · inv_balance
--   2회**가 실행됐다(그 안의 최신 스냅샷 CTE — inv_snapshot Parallel Seq Scan 89,546행 — 도 중복).
--   [실측 2026-09-04] 원천 합 677 ms(inv_balance 120 + inv_balance_vs_cin7 557)인데 함수는
--   3,891 ms (5.7배 · temp written=271 = 디스크 유출). 페이징은 비용을 줄이지 않는다 —
--   total 이 count(*) from f 라 어차피 전체를 만든다. 매니저가 필터 토글·페이지 넘김마다 겪는다.
--
-- 처방: 두 갈래를 **full outer join 하나**로. 결과 집합은 종전과 완전히 같다 — 세 부류로 나눠 보면:
--   · 양쪽 매칭 행 + b 전용 행  = 종전 왼쪽 갈래(left join)와 열 값이 같다. inv_balance 의
--     baseline_qty·delta_qty·qty 는 뷰 정의가 이미 coalesce(...,0) 라 null 이 없어 coalesce(b.x,0) 은
--     값을 바꾸지 않는다. b 전용 행은 c 열이 null → diff null(화면 n/a) — 종전과 동일.
--   · c 전용 행                 = 종전 오른쪽 갈래(not exists)와 같다. b 열이 전부 null 이라 키는
--     coalesce 로 c 에서 오고 세 수량은 0 — 종전이 넣던 0,0,0 과 같은 값.
--   ⚠️ join 이 성립하는 전제: 두 뷰 모두 (sku, warehouse, bin) 이 group by 키라 **유일**하고,
--     bin 이 양쪽 coalesce(bin,'') 라 **not null** 이다(null = null 은 false 라, 이것이 아니었으면
--     매칭이 조용히 깨졌다). 한 행은 최대 한 행과 매칭되므로 |결과| = |왼쪽| + |오른쪽|.
--     **그 전제가 깨지면 이 치환도 깨진다** — 뷰의 group by 키·bin coalesce 를 바꿀 때 여기를 볼 것.
--
-- ⚠️⚠️ IN_TRANSIT — inv_balance_vs_cin7 은 그 창고를 제외한다(Cin7 쪽 대응이 없다). 지금까지
--   union all 의 **왼쪽(inv_balance 전체)이 512칸을 살려 주고 있었다**(화면의 n/a 칩). full outer
--   join 에서는 **b 전용 행**이 같은 역할을 한다 — 매칭 상대가 없어 c 열 null 로 남는다.
--   **잃어도 에러가 안 난다. 조용히 줄어든다.** ⇒ 아래 검산 ②(512)가 합격 조건이다.
--
-- 📌 「union all 이 더 읽기 쉬운데?」 — 되돌리면 뷰 2회 실행으로 돌아간다. 위 실측이 그 대가다.
-- 📌 na_bins(= diff is null 칸 수)는 검산에 쓰지 않는다 — 날마다 변한다(09-04 522 · 09-05 512:
--   스냅샷 이후 신규 자리는 다음 스냅샷에 사라지는 것이 정상).
-- ⬜ 별건: 함수와 뷰 양쪽의 latest(최신 스냅샷 키·시각) 중복. inv_snapshot 에 taken_at 인덱스가 없어
--   Seq Scan 이 불가피하고, 인덱스를 더해도 89k 를 훑는 것은 같다 ⇒ 근본은 최신 키를 한 행으로
--   굳히는 것(inv_config / inv_snapshot_runs 후보). 이번 수리 재측정 뒤 판단한다 — 한 번에 둘을 바꾸면
--   어느 쪽이 효과였는지 모른다.
--
-- ⚠️ 시그니처·반환 형태·컬럼 이름 무변경 — 화면(inventory.html)이 계약 필드 12개를 첫 행에서 검사하고,
--   이름이 바뀌면 조용히 빈 표가 된다(ledger-design.md 「재고 마스터 — WMS 화면이 읽는 계약」).
--   j 이외의 CTE(latest·fresh·ack·ja·f)·봉투·페이징은 20260903113137 정의 그대로.

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
  fresh as (   -- ⭐ 재고 축 중 가장 뒤처진 것 (cost 제외 — 20260903113137 머리 주석) · inv_diff_summary 와 동일
    select source_key, last_ok_at
    from inv_sync_state
    where source_key <> 'cost'
    order by last_ok_at asc nulls first
    limit 1
  ),
  ack as (   -- ⭐ 일지 최신 회차의 확인 상태 (유니크 인덱스가 칸당 1행 보장)
    select sku, warehouse, bin, first_seen_on, acknowledged_at, acknowledged_note
    from inv_balance_diffs
    where checked_on = (select max(checked_on) from inv_balance_diffs)
  ),
  j as (   -- ⭐ 두 뷰를 각 1회만 — 파일 머리 주석(세 부류 동일성 · IN_TRANSIT 은 b 전용 행)
    select
      coalesce(b.sku, c.sku)             as sku,
      coalesce(b.warehouse, c.warehouse) as warehouse,
      coalesce(b.bin, c.bin)             as bin,
      coalesce(b.baseline_qty, 0)        as baseline_qty,   -- c 전용 칸(원장 잔고 축에 행이 없는 자리)에서 0
      coalesce(b.delta_qty, 0)           as delta_qty,
      coalesce(b.qty, 0)                 as ledger_qty,
      c.ledger_qty                       as ledger_qty_at_snapshot,
      c.cin7_qty, c.diff                                    -- b 전용 칸(IN_TRANSIT 등)에서 null = 비교 불가
    from inv_balance b
    full outer join inv_balance_vs_cin7 c
      on  c.sku = b.sku and c.warehouse = b.warehouse and c.bin = b.bin
  ),
  ja as (
    select j.*, a.first_seen_on, a.acknowledged_at, a.acknowledged_note
    from j
    left join ack a
      on a.sku = j.sku and a.warehouse = j.warehouse and a.bin = j.bin
  ),
  f as (
    select * from ja
    where (p_search    is null or sku ilike '%' || p_search || '%')
      and (p_warehouse is null or warehouse = p_warehouse)
      and (not p_only_diff or (diff is not null and diff <> 0))
      and (not p_nonzero  or ledger_qty <> 0 or coalesce(cin7_qty, 0) <> 0)
  )
  select jsonb_build_object(
    'total', (select count(*) from f),
    'snapshot_key', (select k from latest),   -- ⭐ 화면의 「○시 기준」 표시용
    'snapshot_at',  (select at from latest),
    'ledger_collected_at', (select last_ok_at from fresh),   -- ⭐ ledger_qty 가 어디까지 반영된 값인지
    'ledger_lag_source',   (select source_key from fresh),
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
-- 검산 (적용 후 Caleb 이 실행 — ①②가 하나라도 다르면 적용하지 말고 되돌린다)
-- 기준값: 수리 전 실측 2026-09-05 09:xx
-- ─────────────────────────────────────────────────────────
-- ① 총 칸 — 14,272 여야 한다
--   select (inv_stock_master(p_limit := 1) ->> 'total')::int as total_all;
-- ② ⭐ IN_TRANSIT — 512 여야 한다. 줄면 full outer join 이 그 칸들을 잃은 것이다
--   select (inv_stock_master(p_warehouse := 'IN_TRANSIT', p_limit := 1) ->> 'total')::int as in_transit;
-- ③ 성능 — 목표 ≤ 1,000 ms(합의) · ≤ 500 ms(캐럿 펼침이 자연스러운 선). 수리 전 3,891 ms
--   explain (analyze, buffers) select inv_stock_master(p_limit := 200);
-- ④ 한 칸 값이 그대로인지 — 알려진 잔재 PRO00124: 에드먼튼 EB010302(ledger 3 · cin7 0 · diff +3) ·
--   EB010304(ledger 0 · cin7 3 · diff −3) 두 칸이 나와야 한다
--   select x from jsonb_array_elements(inv_stock_master(p_search := 'PRO00124', p_limit := 20) -> 'rows') x;
