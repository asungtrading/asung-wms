-- ⑥ shadow 대조 실행기 (2026-08-24) — inv_compare_runs 신설 + RPC inv_compare_run(p_key)
--
-- 배경: inv_compare 테이블(20260816)은 완성돼 있었으나 채우는 코드가 0곳이었다. ⑥ = 매일
-- Cin7 스냅샷(inv-snapshot ?key=auto-compare 재사용 — 검증된 all-or-nothing)과 원장 잔고
-- (initial 스냅샷 + 사건 합)를 대조해 verdict 를 매기고, 불일치 0이 30일 지속되면 하드 플립.
--
-- 설계 결정 (2026-08-24 사용자 확정):
--  · 비교 단위 = SKU × 창고 (bin 은 3단계 — 트랜스퍼가 bin 을 안 읽어 소스 절반이 bin='')
--  · IN_TRANSIT(합성 창고)은 Cin7 짝이 없다 — inv-snapshot 이 OnHand 만 읽는다(InTransit 컬럼
--    미참조 · index.ts:193). Cin7 도 운송 중을 ON HAND 에서 빼고 별도 컬럼으로 관리함을 실측
--    (2026-08-24 BMA15710: 에드먼튼 ON HAND 0 · IN TRANSIT 204 — 원장과 같은 모델).
--    ⇒ 짝 없음이 정상 = verdict 'explained' 자동 분류.
--  · verdict 최소 규칙: diff=0 → match(카운트만) · IN_TRANSIT → explained · 나머지 전부 unknown.
--    ⚠️ missing_event·calc_error 는 자동 판정하지 않는다 — 원인 조사의 결론이지 계산 결과가
--    아니다. 사람이 unknown 을 닫으며 기록하는 값이다.
--  · ⚠️ inv_compare 에는 **diff≠0 행만 쓴다**(explained·unknown). match 는 runs.match_count 로.
--    대가: 「어느 SKU 가 언제부터 맞았나」의 행 단위 이력은 없다 — 필요해지면 전 쌍 기록 +
--    14일 reap 으로 바꾼다(테이블을 부풀린 뒤 줄이는 것보다 필요해지면 늘리는 쪽이 쉽다).
--  · 같은 날 재실행 = 그 날 행 delete 후 재삽입(최신이 이긴다 — 멱등).
--
-- 보존 정리 (RPC 끝에서 — health_snapshot 의 "쓰기 지점에서 reap" 패턴):
--  · inv_snapshot 의 compare 회차분 14일 (⚠️ '-initial' 불가침 — not like 로 코드 강제)
--  · inv_compare_runs 90일
--
-- ⚠️ 첫 실행은 수동(스냅샷 → RPC → 확인)이 먼저다 — cron 등록은 그 뒤(⑤ 가동과 같은 순서).
-- ⚠️ 첫 회차 예측은 ledger-design.md 「⑥ shadow 대조」 절 — 예측된 unknown(TR-03975/76 출발
--    창고 쌍)이 예측대로 나오면 그 자체가 대조 장치의 검증이다.

-- ─────────────────────────────────────────────────────────
-- 1) inv_compare_runs — 회차 기록 (wms_health_runs 동형)
-- ─────────────────────────────────────────────────────────
create table inv_compare_runs (
  id              bigint generated always as identity primary key,
  ran_at          timestamptz not null default now(),
  snapshot_key    text not null,        -- 이 회차가 대조한 Cin7 스냅샷 키 (예: 2026-08-25-compare)
  compared_pairs  int not null,         -- 비교한 sku×warehouse 쌍 수 (IN_TRANSIT 제외)
  match_count     int not null,
  explained_count int not null,         -- IN_TRANSIT 짝 없음 등 자동 설명분
  unknown_count   int not null,
  unknown_sample  jsonb not null,       -- unknown 상위 20 [{sku,warehouse,ledger_qty,cin7_qty,diff}]
  -- ⚠️ 대조 시점의 inv_sync_state 전체 — 「타이밍 차이」(대조 직전 미수집 사건) 재확인의 유일한
  --    근거. unknown 이 다음날 match 로 돌아오면 이 커서 위치가 그것이 타이밍이었다는 증거가 된다.
  cursors         jsonb not null,
  note            text
);
create index inv_compare_runs_ran_at_idx on inv_compare_runs (ran_at desc);
alter table inv_compare_runs enable row level security;
create policy auth_all on inv_compare_runs for all to authenticated using (true) with check (true);
revoke all on inv_compare_runs from anon;

-- ─────────────────────────────────────────────────────────
-- 2) RPC inv_compare_run(p_snapshot_key)
-- ─────────────────────────────────────────────────────────
create or replace function public.inv_compare_run(p_snapshot_key text)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_initial   text;
  v_snap_rows int;
  v_pairs     int := 0;
  v_match     int := 0;
  v_explained int := 0;
  v_unknown   int := 0;
  v_sample    jsonb;
  v_cursors   jsonb;
begin
  -- 커서 스냅숏 — 판정보다 먼저 읽는다(대조가 실패해도 그 시점 커서가 남게)
  select coalesce(jsonb_object_agg(source_key,
           jsonb_build_object('last_cursor', last_cursor, 'last_run_at', last_run_at)), '{}'::jsonb)
    into v_cursors
    from inv_sync_state;

  -- 가드 1: 대조할 Cin7 스냅샷이 없다 — all-or-nothing 의 짝. 스냅샷이 실패한 날
  -- "전부 missing" 오탐을 만들지 않고 기록만 남긴다.
  select count(*) into v_snap_rows from inv_snapshot where snapshot_key = p_snapshot_key;
  if v_snap_rows = 0 then
    insert into inv_compare_runs (snapshot_key, compared_pairs, match_count, explained_count,
                                  unknown_count, unknown_sample, cursors, note)
    values (p_snapshot_key, 0, 0, 0, 0, '[]'::jsonb, v_cursors,
            'no snapshot rows - snapshot failed or not yet run');
    return jsonb_build_object('ok', false, 'error', 'no snapshot rows for ' || p_snapshot_key);
  end if;

  -- 가드 2: 기준선(-initial) 스냅샷 — 최신 것 하나 (재촬영하면 자동으로 새 기준선을 쓴다)
  select snapshot_key into v_initial
    from inv_snapshot where snapshot_key like '%-initial'
   order by taken_at desc limit 1;
  if v_initial is null then
    insert into inv_compare_runs (snapshot_key, compared_pairs, match_count, explained_count,
                                  unknown_count, unknown_sample, cursors, note)
    values (p_snapshot_key, 0, 0, 0, 0, '[]'::jsonb, v_cursors, 'no -initial baseline snapshot');
    return jsonb_build_object('ok', false, 'error', 'no -initial baseline snapshot');
  end if;

  -- 같은 날 재실행 = 최신이 이긴다 (멱등 — 이전 실행의 스테일 행이 남지 않게 delete 후 insert)
  delete from inv_compare where checked_on = current_date;

  -- 대조 본체: 원장 잔고(기준선 + 사건 합) FULL JOIN Cin7 현재고(compare 스냅샷, bin 접기)
  with baseline as (
    select sku, warehouse, sum(qty) as qty
      from inv_snapshot where snapshot_key = v_initial group by 1, 2
  ),
  events as (
    select sku, warehouse, sum(qty_delta) as delta from inv_ledger group by 1, 2
  ),
  ledger_bal as (
    select coalesce(b.sku, e.sku) as sku,
           coalesce(b.warehouse, e.warehouse) as warehouse,
           coalesce(b.qty, 0) + coalesce(e.delta, 0) as ledger_qty
      from baseline b
      full join events e on e.sku = b.sku and e.warehouse = b.warehouse
  ),
  cin7_now as (
    select sku, warehouse, sum(qty) as cin7_qty
      from inv_snapshot where snapshot_key = p_snapshot_key group by 1, 2
  ),
  joined as (
    select coalesce(l.sku, c.sku) as sku,
           coalesce(l.warehouse, c.warehouse) as warehouse,
           coalesce(l.ledger_qty, 0) as ledger_qty,
           coalesce(c.cin7_qty, 0) as cin7_qty
      from ledger_bal l
      full join cin7_now c on c.sku = l.sku and c.warehouse = l.warehouse
  ),
  verdicts as (
    select sku, warehouse, ledger_qty, cin7_qty,
           case
             when warehouse = 'IN_TRANSIT' then 'explained'   -- 합성 창고 — Cin7 짝 없음이 정상
             when ledger_qty = cin7_qty    then 'match'
             else 'unknown'                                    -- 최소 규칙 — 나머지는 사람이 판정
           end as verdict
      from joined
  ),
  written as (
    -- diff≠0 행만 기록 (사용자 결정 Q-a) — match 는 카운트만. IN_TRANSIT 은 잔량 0 이면 소음이라 제외.
    insert into inv_compare (checked_on, sku, warehouse, ledger_qty, cin7_qty, verdict, note)
    select current_date, sku, warehouse, ledger_qty, cin7_qty, verdict,
           case when warehouse = 'IN_TRANSIT'
                then 'IN_TRANSIT synthetic warehouse - Cin7 tracks in-transit separately (BMA15710 measured 2026-08-24)'
           end
      from verdicts
     where (verdict = 'unknown')
        or (verdict = 'explained' and ledger_qty <> 0)
    returning verdict
  )
  select count(*) filter (where v.warehouse <> 'IN_TRANSIT'),
         count(*) filter (where v.verdict = 'match'),
         count(*) filter (where v.verdict = 'explained' and v.ledger_qty <> 0),
         count(*) filter (where v.verdict = 'unknown')
    into v_pairs, v_match, v_explained, v_unknown
    from verdicts v;

  -- unknown 샘플 상위 20 (|diff| 큰 순 — 이번에 insert 한 행에서 다시 읽는다: 같은 날·같은 정의)
  select coalesce(jsonb_agg(s), '[]'::jsonb) into v_sample
    from (select sku, warehouse, ledger_qty, cin7_qty, diff
            from inv_compare
           where checked_on = current_date and verdict = 'unknown'
           order by abs(diff) desc, sku limit 20) s;

  insert into inv_compare_runs (snapshot_key, compared_pairs, match_count, explained_count,
                                unknown_count, unknown_sample, cursors)
  values (p_snapshot_key, v_pairs, v_match, v_explained, v_unknown, v_sample, v_cursors);

  -- ── 보존 정리 (쓰기 지점에서 reap — health_snapshot 패턴) ──
  -- ⚠️ '-initial' 불가침 — 기준선은 어떤 조건에서도 지우지 않는다(코드로 강제).
  delete from inv_snapshot
   where snapshot_key not like '%-initial'
     and taken_at < now() - interval '14 days';
  delete from inv_compare_runs where ran_at < now() - interval '90 days';

  return jsonb_build_object(
    'ok', true, 'snapshot_key', p_snapshot_key, 'baseline_key', v_initial,
    'compared_pairs', v_pairs, 'match', v_match, 'explained', v_explained,
    'unknown', v_unknown, 'unknown_sample', v_sample);
end
$$;

-- ⚠️ 함수 EXECUTE 는 PUBLIC 기본 부여 — 명시 회수 후 필요한 것만 재부여 (기존 RPC 관례)
revoke all on function public.inv_compare_run(text) from public;
revoke all on function public.inv_compare_run(text) from anon;
grant execute on function public.inv_compare_run(text) to authenticated, service_role;
