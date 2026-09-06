-- 이력 RPC — inv_bin_history (2026-09-06)
--
-- 왜: 재고 마스터 화면이 숫자만 보여준다 — 「PRO00124 EDM EB010302 3」 이 3 이 언제 어떻게 3 이 됐는지를
--   못 보여준다. ⭐ 이력은 편의 기능이 아니라 **진단 도구**다 — 결함 E·SO-14734 를 규명할 때 한 일이
--   「이 칸에 무슨 사건이 있었나」를 SQL 로 찾는 것이었고, 그것을 화면에 옮긴다.
--   ⚠️ 화면이 inv_ledger 를 직접 읽지 않는다 — 계약에 없는 테이블이고 21,247행이라 PostgREST 1,000행
--   캡에도 걸린다. 화면은 이 RPC 만 부른다(계약 문서 반영은 별도 작업).
--
-- 시그니처: p_sku 는 **기본값 없이 필수**(정확 일치 — 이력은 지목해 여는 것이다 · ilike 아님) ·
--   p_warehouse/p_bin null = 전 창고/전 칸 · p_limit 50 · p_offset 0. 관례(20260905211833)대로
--   language sql stable security invoker · revoke public,anon · grant authenticated.
--
-- 봉투: total · baseline{snapshot_key, taken_at, qty} · rows[]
--   ⚠️⚠️ baseline 을 rows[] 에 섞지 않는다 — 기초는 사건이 아니라 **출발점**이다. 섞으면 「사건 수」가 하나 늘어 보인다.
--   baseline.qty = inv_snapshot 에서 snapshot_key = inv_config('baseline_snapshot_key') 인 행의 합.
--   p_warehouse/p_bin 이 있으면 그 범위의 합, 없으면 그 SKU 전체 합. ⚠️ 재기준선을 잡으면 값이 바뀐다 —
--   상수로 박지 않고 inv_config 를 읽는다(inv_balance 뷰와 같은 경로).
--   ⚠️⚠️ baseline.taken_at 은 **키 전체의 max 가 아니라 그 SKU 의 기초 행에서** max 를 낸다.
--     키 전체 max(select max(taken_at) from inv_snapshot where snapshot_key = k)는 인덱스에 taken_at 이 없어
--     89,546행 Parallel Seq Scan 이고 [실측 2026-09-05 성능 수리] **143 ms** 다 — 매 호출에 붙는다.
--     한 회차의 행은 같은 시각에 찍히므로 SKU 범위의 max 와 값이 같다(유니크 인덱스 (snapshot_key, sku, …)
--     선두 두 컬럼으로 걸린다). 기초에 없는 SKU(신규)는 taken_at null · qty 0 — 정직한 값이다.
--     「전체 max 가 정확한데?」 하고 바꾸면 매 호출이 143 ms 를 더 낸다. 바꾸지 말 것.
--
-- rows[] 12개: occurred_on(⭐ 사건 날짜 — 수집 날짜가 아니다) · doc_type · doc_number · event_type ·
--   warehouse · bin · qty_delta · running_qty(⭐ 이 사건 뒤 잔고 — baseline.qty 에서 누적) ·
--   is_manual(source='manual' — 손으로 맞춘 것) · fix_kind · reason · created_at(⚠️ 수집 시각).
--   ⚠️⚠️ 두 날짜 축을 둘 다 낸다 — [실물 SO-14897] occurred_on 8/25 · 수집 9/4. 그 차이 자체가 진단 정보다.
--   정렬은 occurred_on, 표시는 둘 다(화면 몫).
--
-- ⭐ running_qty — 누적 **후** 페이징. 페이징을 먼저 하면 2페이지부터 누적이 틀린다.
--   [실측] 칸당 사건 수 최대 39 · 평균 3.0 · p95 9 — 전 사건 누적 비용이 없다.
--   누적 순서 = occurred_on, seq_hint, id. seq_hint 는 테이블 정의(20260816000000:22-24)가 「같은 날 정렬용
--   힌트: 1=유입(+) 먼저 · 2=유출(−) 나중 — 일중 시각이 없어도 유입을 먼저 적용해 음수 중간잔고를 피한다」로
--   정한 축이라 잔고 계산의 순서가 곧 이력의 순서다. id 는 안정적 tie-breaker(같은 날·같은 방향 · 삽입 순).
--   출력도 같은 순서 **오름차순(기초 → 현재)** — running_qty 가 더해가며 읽히고, 「마지막 running_qty = 현재
--   잔고」가 검산 ①의 정의다. 최신을 위로 보이고 싶으면 화면이 뒤집는다(50행 이하 · 비용 없음). 뒤집지 말 것.
--
-- ⭐ reason = coalesce(raw->>'detail', raw->>'rule') — [실측] cin7 19,668행 → raw.rule 100% ·
--   manual 1,579행 → raw.detail 987행. ⚠️ **자르지 않는다** — 어디서 자를지는 화면이 정한다. 잘라서 내면
--   전문을 볼 방법이 없어진다.
--
-- ⭐ fix_kind — 사유(detail) 없는 manual 592행(:binfix · 8/31 scripts/fix-transfer-bins.mjs)을 접미어가 덮는다.
--   실물 접미어: :voided · :deleted · :qtyfix · :latepick · :binfix · :binfixed · :superseded · :reversal(08-25 138행 ·
--   08-31 522행). ⚠️ 화이트리스트로 박으면 앞으로 생길 접미어가 전부 null 이 된다 ⇒ 규칙은
--   **「source='manual' 이고 line_ref 의 마지막 ':' 뒤가 영문 소문자만(^[a-z]+$)」**.
--   ⚠️ 판매의 line_ref 는 <Fulfilment TaskID GUID>:<ProductID GUID> 복합키(폴백 f1:GUID)이고, cin7 폴백에
--   no-product-id:<SKU> 도 콜론을 가진다 — 「마지막 ':' 뒤」만으로는 GUID·SKU 가 새어 들어온다.
--   GUID 는 숫자·하이픈을, SKU 는 숫자를 포함해 ^[a-z]+$ 에 걸리지 않고, cin7 행은 source 조건으로 애초에 null.
--   접미어 없는 manual 행(bare GUID)도 null. 검산 ④(BNAT48173 판매 행 fix_kind null)가 이것을 확인한다.
--
-- 성능: ⭐ 인덱스는 이미 있다 — inv_ledger_sku_wh_on_idx (sku, warehouse, occurred_on) (20260816000000:84).
--   p_sku 필수라 선두 컬럼이 걸리고 p_warehouse 가 둘째, occurred_on 이 셋째라 정렬까지 인덱스가 처리한다.
--   bin 은 인덱스에 없으나 한 SKU+창고의 행이 적어(칸당 평균 3) 필터로 충분하다. **인덱스를 추가하지 말 것.**
--   목표 ≤500 ms — 적용 후 실측(아래 ⑥). 넘으면 플랜을 보고 멈춘다.

create or replace function inv_bin_history(
  p_sku        text,                  -- ⚠️ 필수 · 정확 일치
  p_warehouse  text default null,     -- null = 전 창고
  p_bin        text default null,     -- null = 전 칸
  p_limit      int  default 50,
  p_offset     int  default 0
) returns jsonb
language sql stable security invoker
as $$
  with base as (
    select value as k from inv_config where key = 'baseline_snapshot_key'
  ),
  bl as (   -- 기초 — ⚠️ taken_at 은 그 SKU 의 기초 행 범위(파일 머리 주석 — 키 전체 max 는 89k Seq Scan)
    select b.k as snapshot_key,
           max(s.taken_at)          as taken_at,
           coalesce(sum(s.qty), 0)  as qty
    from base b
    left join inv_snapshot s
      on  s.snapshot_key = b.k
      and s.sku = p_sku
      and (p_warehouse is null or s.warehouse = p_warehouse)
      and (p_bin is null or coalesce(s.bin, '') = p_bin)
    group by b.k
  ),
  ev as (   -- 사건 전량(필터 범위) — 누적은 여기서, 페이징은 뒤에서
    select
      l.id, l.occurred_on, l.seq_hint, l.doc_type, l.doc_number, l.event_type,
      l.warehouse, l.bin, l.qty_delta, l.source, l.line_ref, l.raw, l.created_at,
      sum(l.qty_delta) over (order by l.occurred_on, l.seq_hint, l.id
                             rows between unbounded preceding and current row) as cum
    from inv_ledger l
    where l.sku = p_sku
      and (p_warehouse is null or l.warehouse = p_warehouse)
      and (p_bin is null or l.bin = p_bin)
  ),
  shaped as (
    select
      e.occurred_on, e.doc_type, e.doc_number, e.event_type, e.warehouse, e.bin, e.qty_delta,
      (select qty from bl) + e.cum                       as running_qty,
      (e.source = 'manual')                              as is_manual,
      case when e.source = 'manual'
            and split_part(e.line_ref, ':', array_length(string_to_array(e.line_ref, ':'), 1)) ~ '^[a-z]+$'
           then split_part(e.line_ref, ':', array_length(string_to_array(e.line_ref, ':'), 1))
           else null end                                 as fix_kind,
      coalesce(e.raw ->> 'detail', e.raw ->> 'rule')     as reason,   -- ⚠️ 자르지 않는다
      e.created_at,
      e.seq_hint, e.id
    from ev e
  )
  select jsonb_build_object(
    'total', (select count(*) from shaped),
    'baseline', (select jsonb_build_object('snapshot_key', snapshot_key, 'taken_at', taken_at, 'qty', qty) from bl),
    'rows', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'occurred_on', x.occurred_on, 'doc_type', x.doc_type, 'doc_number', x.doc_number,
                 'event_type', x.event_type, 'warehouse', x.warehouse, 'bin', x.bin,
                 'qty_delta', x.qty_delta, 'running_qty', x.running_qty,
                 'is_manual', x.is_manual, 'fix_kind', x.fix_kind, 'reason', x.reason,
                 'created_at', x.created_at)
               order by x.occurred_on, x.seq_hint, x.id)
      from (select * from shaped
            order by occurred_on, seq_hint, id
            limit greatest(p_limit, 1) offset greatest(p_offset, 0)) x
    ), '[]'::jsonb)
  );
$$;

revoke all on function inv_bin_history(text,text,text,int,int) from public, anon;
grant execute on function inv_bin_history(text,text,text,int,int) to authenticated;

-- ─────────────────────────────────────────────────────────
-- 검산 (적용 후 Caleb 이 실행)
-- ─────────────────────────────────────────────────────────
-- ① ⭐ PRO00124 EB010302 — 알려진 잔재. 이 칸의 현재 잔고는 3 이다
--    마지막 running_qty 가 3 이어야 하고, baseline.qty + Σqty_delta = 3 이어야 한다
--    (⑧ bin 대조의 ledger_qty 와 일치 — 안 맞으면 기초를 잘못 읽었거나 누적 순서가 틀린 것)
--   select jsonb_pretty(inv_bin_history(p_sku := 'PRO00124', p_warehouse := 'Asung - Edmonton',
--                                       p_bin := 'EB010302'));
-- ② ⭐ 수동 정정이 보이는가 — SO-15440 CAN01003 은 :deleted 로 상쇄했다
--    is_manual true · fix_kind 'deleted' · reason 에 영문 사유가 있어야 한다
--   select jsonb_pretty(inv_bin_history(p_sku := 'CAN01003', p_warehouse := 'Asung Trading Inc.',
--                                       p_bin := 'E030301'));
-- ③ ⚠️ reason 이 null 인 행 — :binfix. 에러가 아니라 정상이다
--   select x from jsonb_array_elements(
--     inv_bin_history(p_sku := 'ANN01285', p_limit := 50) -> 'rows') x
--   where x ->> 'fix_kind' = 'binfix';
-- ④ ⚠️ 판매의 복합 line_ref 가 fix_kind 로 새지 않는지 — cin7 판매 행의 fix_kind 는 null 이어야 한다
--    (GUID 가 들어오면 fix_kind 규칙이 틀린 것)
--   select x from jsonb_array_elements(
--     inv_bin_history(p_sku := 'BNAT48173', p_limit := 50) -> 'rows') x;
-- ⑤ SKU 단위 — 창고·bin 을 안 주면 전 창고 사건
--   select (inv_bin_history(p_sku := 'PRO00124') -> 'total')::int as total_events;
-- ⑥ 성능 — 목표 ≤500 ms · 넘으면 멈추고 플랜과 함께 보고(인덱스 inv_ledger_sku_wh_on_idx 를 쓰는지)
--   explain (analyze, buffers) select inv_bin_history(p_sku := 'PRO00124');
--   explain (analyze, buffers) select inv_bin_history(p_sku := 'PRO00124', p_warehouse := 'Asung - Edmonton', p_bin := 'EB010302');
