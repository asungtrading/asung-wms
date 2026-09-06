-- SKU 층 RPC — inv_stock_master_sku + 칸 층 inv_stock_master 에 p_sku_exact (2026-09-05)
--
-- 왜: 재고 마스터 화면(inventory.html)은 SKU × 창고 × bin 을 한 줄씩 깐다 — 재고 마스터인데
--   「이 물건 총 몇 개」가 안 보인다. 목록이 200행 페이징이라 **클라이언트에서 접으면 SKU 가
--   페이지 경계에서 갈려 합계가 틀린다** ⇒ 서버에서 접는 별도 RPC. 화면은 SKU 목록을 이것으로
--   받고, 캐럿을 펼칠 때 기존 inv_stock_master 를 p_sku_exact 로 부른다(그때 p_warehouse 를 주지
--   않는 것은 **화면의 약속**이다 — 함수는 받은 대로 처리한다).
--
-- ⚠️⚠️ 필터를 집계 전/후로 나눈다 — diff 를 SKU 로 합치면 **거울 칸이 사라진다**
--   ([실물 PRO00124] 에드먼튼 EB010302 +3 · EB010304 −3 → 합 0 인데 실제로는 6만큼 어긋남).
--   그래서 diff_bins·abs_diff 를 함께 내는데, 칸 층처럼 필터(f)를 칸 단위로 먼저 걸고 group by 를
--   얹으면 p_only_diff 가 diff=0 칸을 먼저 지워 qty 가 「어긋난 칸의 재고만 더한 값」이 된다 —
--   거울 칸 경고를 넣어놓고 필터가 그것을 걸러내는 모양.
--     집계 전(pre)  p_sku_exact / p_search · p_warehouse       — 어느 SKU·어느 창고를 볼지 정하는 축
--     집계(g)       group by sku — 그 외 필터 없이 전 칸       — qty·diff_bins·abs_diff 가 맞으려면
--     집계 후(f)    p_only_diff → diff_bins > 0 · p_nonzero    — SKU 층의 의미로 다시 정의
--   ⚠️ p_only_diff 의 뜻이 층마다 다르다: 칸 층 「이 칸이 어긋났다」 · SKU 층 「이 SKU 에 어긋난
--   칸이 있다」. diff 합이 0 이어도 diff_bins > 0 이면 걸려야 한다 — 그것이 거울 칸이다.
--
-- p_warehouse 는 **부분합**(WMS 확정 · 집계 전에 건다): 창고를 고르면 qty·bins·warehouses·diff_bins
--   전부 그 창고 것만. qty 만 전체 합이면 한 줄 안에서 축이 갈린다(이 화면은 이미 시점 축이 셋).
--
-- qty 와 in_transit_qty: 같은 ledger_qty 를 warehouse = 'IN_TRANSIT' 로만 갈라 센다 — 둘의 합이
--   칸 층 ledger_qty 총합. warehouses 는 IN_TRANSIT 을 세지 않는다(창고가 아니다).
-- diff is null 인 칸은 **두 부류로 나눈다** — 하나로 합치면 뜻을 잃는다:
--   in_transit_bins          warehouse = 'IN_TRANSIT'   ⭐ 상시(실측 512칸 · 대조 상대가 없다)
--   new_since_snapshot_bins  그 외 diff is null          ⚠️ 하루살이 — 스냅샷 이후 생긴 자리. 낮에 자리
--                            이동이 있으면 늘 생기고 다음 스냅샷에 사라진다([실측] 09-04 저녁 10칸
--                            → 09-05 아침 0칸). **정상값**이라 화면이 경고로 띄우면 매일 오탐.
-- p_nonzero(SKU 층) = coalesce(qty,0) <> 0 or coalesce(in_transit_qty,0) <> 0 or coalesce(cin7_qty,0) <> 0
--   ⭐ 운송 중 포함 — 칸 층은 IN_TRANSIT 칸을 보여주는데 SKU 층에서 사라지면 두 층이 어긋난다.
--   「재고가 전부 운송 중인 SKU」는 숨길 것이 아니라 오히려 봐야 할 것이다.
-- qty_at_snapshot·cin7_qty·diff 는 sum() 그대로 — 비교 가능 칸이 하나도 없으면 null 로 남겨
--   칸 층의 n/a(비교 불가 ≠ 0) 의미를 유지한다.
-- ⚠️ unack_bins 는 ja.acknowledged_at(= inv_balance_diffs 최신 checked_on 회차)에서 센다.
--   **그 일지는 새벽에 굳는다** ⇒ 낮에 새로 어긋난 칸은 일지에 없어 acknowledged_at 이 null 이고
--   미확인으로 세인다. 칸 층 Ack 열이 그런 칸을 「—」로 그리는 것과 같은 동작이라 맞지만,
--   **낮에 조회하면 unack_bins 가 부풀어 보인다.** 판정은 실측 후 — 지금 동작은 바꾸지 않는다.
-- ❌ first_seen_on 은 내지 않는다 — 칸 단위 의미다. 가장 오래된 것을 대표로 내면 새로 생긴 칸이
--   오래된 것처럼 보인다. 날짜가 필요하면 펼쳐서 칸을 본다.
--
-- j·ja 는 20260905205639(full outer join 수리판)에서 그대로 복사 — 두 뷰 각 1회. ⚠️ 그 전제
--   (두 뷰 모두 (sku,warehouse,bin) 이 group by 키라 유일 · bin 이 양쪽 coalesce(bin,'') 라 not null)를
--   깨지 말 것. 뷰 정의(inv_balance·inv_balance_vs_cin7) 무접촉.
-- 📌 total 이 count(*) 라 페이징은 비용을 줄이지 않는다(칸 층과 같다). 성능은 적용 후 실측(아래 ⑥) —
--   목표 ≤ 1,000 ms(합의) · ≤ 500 ms(바람직) · 2,000 ms 초과면 설계를 다시 본다.

-- ─────────────────────────────────────────────────────────
-- 1) 칸 층 inv_stock_master — p_sku_exact 하나만 추가 (다른 것은 20260905205639 그대로)
-- ─────────────────────────────────────────────────────────
-- ⚠️ 옛 시그니처를 drop 한다. 화면(inventory.html)은 명명 인자 6개로 rpc 를 부르는데, 7-인자 함수는
--   p_sku_exact 가 default 라 6개 호출에도 매칭된다 — 둘이 남으면 PostgREST 가 두 후보를 모두 맞다고
--   보고 후보 선택 오류를 낸다(화면이 통째로 깨진다). 레포 내 다른 호출자 없음(grep: 화면 1곳).
-- ⚠️ p_sku_exact 는 기본값 null 로 맨 끝 — 기존 위치·명명 호출 모두 그대로 동작한다.
--   둘 다 주어지면 p_sku_exact 가 이긴다(암묵 순서를 남기지 않는다). p_search 의 ilike 동작은 무변.
drop function if exists inv_stock_master(text,text,boolean,boolean,int,int);

create or replace function inv_stock_master(
  p_search     text    default null,   -- sku 부분일치 (⚠️ 대소문자 무시 — ilike)
  p_warehouse  text    default null,   -- null = 전체
  p_only_diff  boolean default false,  -- ⭐ 이상만 보기
  p_nonzero    boolean default true,   -- 재고 0 인 칸 숨기기 (기본 숨김)
  p_limit      int     default 200,
  p_offset     int     default 0,
  p_sku_exact  text    default null    -- ⭐ 정확일치(캐럿 펼침용) — 있으면 p_search 를 이긴다
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
  j as (   -- ⭐ 두 뷰를 각 1회만 — 20260905205639 머리 주석(세 부류 동일성 · IN_TRANSIT 은 b 전용 행)
    select
      coalesce(b.sku, c.sku)             as sku,
      coalesce(b.warehouse, c.warehouse) as warehouse,
      coalesce(b.bin, c.bin)             as bin,
      coalesce(b.baseline_qty, 0)        as baseline_qty,
      coalesce(b.delta_qty, 0)           as delta_qty,
      coalesce(b.qty, 0)                 as ledger_qty,
      c.ledger_qty                       as ledger_qty_at_snapshot,
      c.cin7_qty, c.diff
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
    where (case when p_sku_exact is not null then sku = p_sku_exact
                else (p_search is null or sku ilike '%' || p_search || '%') end)
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

revoke all on function inv_stock_master(text,text,boolean,boolean,int,int,text) from public, anon;
grant execute on function inv_stock_master(text,text,boolean,boolean,int,int,text) to authenticated;

-- ─────────────────────────────────────────────────────────
-- 2) SKU 층 inv_stock_master_sku — 신규
-- ─────────────────────────────────────────────────────────
create or replace function inv_stock_master_sku(
  p_search     text    default null,   -- sku 부분일치 (ilike — 칸 층과 동일)
  p_warehouse  text    default null,   -- null = 전체 · 값이 있으면 부분합
  p_only_diff  boolean default false,  -- ⭐ 어긋난 칸이 있는 SKU 만 (diff_bins > 0)
  p_nonzero    boolean default true,   -- 재고 0 인 SKU 숨기기(운송 중 포함 판정)
  p_sku_exact  text    default null,   -- 정확일치 — 있으면 p_search 를 이긴다
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
  fresh as (
    select source_key, last_ok_at
    from inv_sync_state
    where source_key <> 'cost'
    order by last_ok_at asc nulls first
    limit 1
  ),
  ack as (   -- ⭐ 일지 최신 회차 — 새벽에 굳는다(파일 머리 unack_bins 주석)
    select sku, warehouse, bin, first_seen_on, acknowledged_at, acknowledged_note
    from inv_balance_diffs
    where checked_on = (select max(checked_on) from inv_balance_diffs)
  ),
  j as (   -- 20260905205639 와 동일 — 두 뷰 각 1회
    select
      coalesce(b.sku, c.sku)             as sku,
      coalesce(b.warehouse, c.warehouse) as warehouse,
      coalesce(b.bin, c.bin)             as bin,
      coalesce(b.baseline_qty, 0)        as baseline_qty,
      coalesce(b.delta_qty, 0)           as delta_qty,
      coalesce(b.qty, 0)                 as ledger_qty,
      c.ledger_qty                       as ledger_qty_at_snapshot,
      c.cin7_qty, c.diff
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
  pre as (   -- 집계 전 — SKU 축·창고 축만(부분합). 그 외 필터는 여기 넣지 않는다(거울 칸 보호)
    select * from ja
    where (case when p_sku_exact is not null then sku = p_sku_exact
                else (p_search is null or sku ilike '%' || p_search || '%') end)
      and (p_warehouse is null or warehouse = p_warehouse)
  ),
  g as (     -- 집계 — 전 칸
    select
      sku,
      coalesce(sum(ledger_qty) filter (where warehouse <> 'IN_TRANSIT'), 0) as qty,
      coalesce(sum(ledger_qty) filter (where warehouse =  'IN_TRANSIT'), 0) as in_transit_qty,
      sum(ledger_qty_at_snapshot)                                          as qty_at_snapshot,   -- 비교 가능 칸 없으면 null
      sum(cin7_qty)                                                        as cin7_qty,
      sum(diff)                                                            as diff,              -- ⚠️ 이것만으로는 부족 — 거울 칸
      count(*) filter (where diff is not null and diff <> 0)               as diff_bins,
      coalesce(sum(abs(diff)), 0)                                          as abs_diff,
      count(*) filter (where warehouse = 'IN_TRANSIT')                     as in_transit_bins,
      count(*) filter (where diff is null and warehouse <> 'IN_TRANSIT')   as new_since_snapshot_bins,
      count(*)                                                             as bins,
      count(distinct warehouse) filter (where warehouse <> 'IN_TRANSIT')   as warehouses,
      count(*) filter (where diff is not null and diff <> 0 and acknowledged_at is null) as unack_bins
    from pre
    group by sku
  ),
  f as (     -- 집계 후 — SKU 층의 의미로
    select * from g
    where (not p_only_diff or diff_bins > 0)
      and (not p_nonzero or coalesce(qty, 0) <> 0 or coalesce(in_transit_qty, 0) <> 0 or coalesce(cin7_qty, 0) <> 0)
  )
  select jsonb_build_object(
    'total', (select count(*) from f),
    'snapshot_key', (select k from latest),
    'snapshot_at',  (select at from latest),
    'ledger_collected_at', (select last_ok_at from fresh),
    'ledger_lag_source',   (select source_key from fresh),
    'rows',  coalesce((
      select jsonb_agg(x order by x.sku)
      from (select * from f order by sku
            limit greatest(p_limit,1) offset greatest(p_offset,0)) x
    ), '[]'::jsonb)
  );
$$;

revoke all on function inv_stock_master_sku(text,text,boolean,boolean,text,int,int) from public, anon;
grant execute on function inv_stock_master_sku(text,text,boolean,boolean,text,int,int) to authenticated;

-- ─────────────────────────────────────────────────────────
-- 검산 (적용 후 Caleb 이 실행)
-- ─────────────────────────────────────────────────────────
-- ① SKU 수 — 칸 14,272 개가 몇 SKU 로 접히는지
--   select (inv_stock_master_sku(p_limit := 1) ->> 'total')::int as total_sku;
-- ② ⭐ 거울 칸 — diff 합이 0인데 diff_bins > 0 인 SKU 가 있는가
--   select x from jsonb_array_elements(inv_stock_master_sku(p_only_diff := true, p_limit := 500) -> 'rows') x
--   where (x ->> 'diff')::numeric = 0 and (x ->> 'diff_bins')::int > 0;
-- ③ ⭐ PRO00124 — 알려진 잔재. diff 0 · diff_bins 2 · abs_diff 6 이어야 한다(핵심 검산 — 거울 칸 경고 작동)
--   select x from jsonb_array_elements(inv_stock_master_sku(p_sku_exact := 'PRO00124', p_limit := 5) -> 'rows') x;
-- ④ 부분합 — 창고를 걸면 그 창고 것만
--   select x from jsonb_array_elements(
--     inv_stock_master_sku(p_sku_exact := 'PRO00124', p_warehouse := 'Asung - Edmonton', p_limit := 5) -> 'rows') x;
-- ⑤ in_transit 분리 — 합이 512여야 한다(실측 2026-09-05)
--   select sum((x ->> 'in_transit_bins')::int) as in_transit_bins
--   from jsonb_array_elements(inv_stock_master_sku(p_nonzero := false, p_limit := 20000) -> 'rows') x;
-- ⑥ 성능 — 목표 ≤ 1,000 ms(합의) · ≤ 500 ms(바람직) · 2,000 ms 초과면 멈추고 설계 재검토
--   explain (analyze, buffers) select inv_stock_master_sku(p_limit := 200);
-- ⑦ 칸 층 무변 — 09-05 기준값 그대로여야 한다(다르면 §1 이 칸 층을 깨뜨린 것 — 되돌린다)
--   select (inv_stock_master(p_limit := 1) ->> 'total')::int as total_all;                    -- 14,272
--   select (inv_stock_master(p_warehouse := 'IN_TRANSIT', p_limit := 1) ->> 'total')::int;     -- 512
-- ⑧ 오버로드가 하나뿐인지 — 두 행 이상이면 화면의 6-인자 명명 호출이 후보 선택 오류를 낸다
--   select proname, pg_get_function_identity_arguments(oid) from pg_proc where proname like 'inv_stock_master%';
