-- ledger_collected_at — 원장 값의 신선도 (2026-09-03 · WMS 요청 2026-09-01)
--
-- 왜: 재고 마스터 화면의 주인공 열이 ledger_qty 인데 **그 값이 어디까지 반영된 것인지**를
--   매니저에게 보여줄 방법이 없었다. snapshot_at 은 Cin7 스냅샷 시각, checked_on 은 일지
--   시각 — 둘 다 원장 수집 시각이 아니다.
--   [실사고 2026-09-01] WMS 의 ⟳ Stock 갱신 체인이 **12일간 죽어 있었는데 어느 화면에도
--   드러나지 않았다**(GAS 트리거 20/20 한도). 신선도가 화면에 없으면 같은 일이 반복된다.
--   그리고 「신고 없음」은 「문제 없음」이 아니다 — 세 번 실패하니 8일간 아무도 안 눌렀다.
--
-- 무엇: inv_diff_summary() 와 inv_stock_master(...) 둘 다에 두 키를 **추가만** 한다.
--   ledger_collected_at   재고 축의 마지막 성공 수집 시각 중 **가장 뒤처진 것**(보수적 min)
--   ledger_lag_source     그 min 을 낸 source_key — 어느 축이 밀렸는지 바로 보인다
--   ⚠️ 화면이 목록만 부르고 요약을 안 부를 수 있어 양쪽에 넣는다.
--   ⚠️ 기존 키(rows·total·snapshot_key·snapshot_at·컬럼 이름)는 그대로 — 화면 계약이
--   문서에 박혀 있고, 이름 변경만이 계약을 깬다. 아래는 20260901194903 정의에 fresh CTE 와
--   키 2개만 더한 것.
--
-- 컬럼 선택 — ⚠️ 추측하지 않고 확인했다 (지시서 2-a):
--   inv_sync_state 는 last_run_at 과 last_ok_at 을 **둘 다** 갖는다(20260816000000).
--   EF 실측(inv-collect 1670·2368행 · inv-cost 763행): 둘을 **성공 경로에서만, 같은 값으로**
--   쓴다 — 차단된 회차(write_skipped)는 어느 쪽도 갱신하지 않는다. 지금은 값이 같지만 의미가
--   「마지막 성공」인 **last_ok_at** 을 쓴다. 실패한 회차의 시각을 신선도로 보여주면 안 된다.
--
-- ⚠️⚠️ cost 는 세지 않는다 — 두 가지 이유:
--   ① 하루 1회(00:33 토론토)라 min 에 넣으면 **늘 「하루 뒤처짐」**으로 보인다
--   ② 원가 축이라 **재고 수량과 무관**하다
--   ⇒ 재고에 영향을 주는 여섯(transfer·sale·purchase·adjustment·assembly·creditnote)만.
--   📌 소스 목록을 코드에 박지 않는다 — source_key <> 'cost' 로 거른다. 축이 늘면 저절로 따라온다.
--   📌 여섯 중 adjustment·assembly·creditnote 는 시간당 1회라 최대 1시간 뒤처진다.
--      그것이 정직한 값이니 그대로 낸다. 「몇 분 지나면 경고」 같은 임계값은 화면이 판단한다.
--
-- null 처리: 어느 축이든 last_ok_at 이 null(한 번도 성공 못 함)이면 그 축이 가장 뒤처진 것이다
--   ⇒ nulls first 로 그 축을 lag_source 로 내고 collected_at 은 null 이 된다(「모른다」가 정직하다).
--   min() 은 null 을 건너뛰어 두 키가 서로 다른 축을 가리킬 수 있으므로 한 CTE 에서 함께 낸다.
--
-- 권한: security invoker 그대로 — inv_sync_state 는 authenticated 정책(auth_all)이 있고
--   anon 은 회수돼 있다. 화면은 여전히 inv_sync_state 를 직접 읽지 않는다 — 계약에 오른 두
--   RPC 를 통해 스칼라 두 개만 받는다(계약에 없는 테이블은 원장이 바꿔도 WMS 에 통보되지 않는다).

-- ─────────────────────────────────────────────────────────
-- 1) inv_diff_summary — 카드용 요약에 신선도 두 키
-- ─────────────────────────────────────────────────────────
create or replace function inv_diff_summary()
returns jsonb
language sql stable security invoker
as $$
  with latest as (select max(checked_on) as d from inv_balance_diffs),
  cur as (select * from inv_balance_diffs, latest where checked_on = latest.d),
  prev as (
    select count(*) as n from inv_balance_diffs
    where checked_on = (select max(checked_on) from inv_balance_diffs, latest
                        where checked_on < latest.d)
  ),
  fresh as (   -- ⭐ 재고 축 중 가장 뒤처진 것 (cost 제외 — 파일 머리 주석)
    select source_key, last_ok_at
    from inv_sync_state
    where source_key <> 'cost'
    order by last_ok_at asc nulls first
    limit 1
  )
  select jsonb_build_object(
    'checked_on',   (select d from latest),
    'snapshot_at',  (select max(snapshot_at) from cur),
    'total',        (select count(*) from cur),
    'new_today',    (select count(*) from cur where first_seen_on = checked_on),   -- ⭐ 오늘 처음
    'unack',        (select count(*) from cur where acknowledged_at is null),      -- ⭐ 카드의 숫자
    'acked',        (select count(*) from cur where acknowledged_at is not null),
    'prev_total',   (select n from prev),
    'abs_gap',      (select coalesce(sum(abs(diff)), 0) from cur),
    'ledger_collected_at', (select last_ok_at from fresh),   -- ⭐ ledger_qty 가 어디까지 반영된 값인지
    'ledger_lag_source',   (select source_key from fresh)
  );
$$;

revoke all on function inv_diff_summary() from public, anon;
grant execute on function inv_diff_summary() to authenticated;

-- ─────────────────────────────────────────────────────────
-- 2) inv_stock_master — 목록 응답에도 같은 두 키 (추가만)
-- ─────────────────────────────────────────────────────────
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
  fresh as (   -- ⭐ 재고 축 중 가장 뒤처진 것 (cost 제외 — 파일 머리 주석) · inv_diff_summary 와 동일
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
-- 검증 (마이그레이션 후 Caleb 이 실행 — 지시서 §5)
-- ─────────────────────────────────────────────────────────
-- ⚠️ 지시서는 last_run_at 으로 썼지만 함수는 last_ok_at 을 쓴다(파일 머리 「컬럼 선택」).
--    지금은 EF 가 둘을 같은 값으로 쓰므로 어느 쪽으로 검증해도 같아야 한다 — 다르면 그 자체가 신호다.
-- ① 요약에 두 키가 실리나
--   select jsonb_pretty(inv_diff_summary());
-- ② 목록에도 (rows 는 빼고 본다)
--   select jsonb_pretty(inv_stock_master(p_limit := 1) - 'rows');
-- ③ ⭐ 값이 맞나 — 맨 위 행의 source_key 가 ledger_lag_source, 그 시각이 ledger_collected_at
--   select source_key, last_ok_at at time zone 'America/Toronto' as last_ok,
--          last_run_at at time zone 'America/Toronto' as last_run
--   from inv_sync_state where source_key <> 'cost' order by last_ok_at nulls first;
-- ④ ⚠️ cost 를 넣었다면 어떻게 보였을지 (제외 사유 확인용 — 두 값이 크게 벌어지면 제외가 옳았다)
--   select min(last_ok_at) filter (where source_key <> 'cost') as six_axes,
--          min(last_ok_at) as with_cost
--   from inv_sync_state;
-- ⑤ 권한 — anon 없음 · authenticated EXECUTE
--   select routine_name, grantee, privilege_type
--   from information_schema.routine_privileges
--   where routine_name in ('inv_diff_summary','inv_stock_master') order by 1,2;
