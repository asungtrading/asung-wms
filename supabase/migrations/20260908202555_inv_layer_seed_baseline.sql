-- 기초 레이어 적재 — inv_layer_seed_baseline(p_snapshot_key, p_force) (2026-09-08)
--
-- 배경: inv_layer(20260908195949) 는 그릇만 있다. 첫 내용물은 **기초 스냅샷**이다 —
-- 현재 재고의 96% 가 8/20 기초분이고(8/20 이후 입고분은 3.6%), 그 평가액은
-- inv_snapshot.value 에 bin 단위로 전 칸 존재한다. 이 함수가 그것을 창고 단위 레이어로 옮긴다.
--
-- 왜 함수인가 — 일회성 insert 가 아니라 재실행 가능해야 한다. 재기준선 때
-- 키만 바꿔 다시 부르고, 테스트에서 여러 번 되돌려 검증한다.
-- ⚠️ 불변 조건(inv_layer 헤더) — 레이어는 원장 + inv_cost + inv_snapshot 으로
-- 전량 재생성 가능해야 한다. 이 함수가 기초 쪽 재생성 경로다.
--
-- 무엇을 하나
--  가드 1  inv_layer 에 origin_type='baseline' 행이 이미 있으면
--          · p_force=false → 예외. 아무것도 하지 않는다.
--          · p_force=true  → 기존 baseline 행을 지우고 다시 넣는다.
--  가드 2  ⚠️ 지우려는 baseline 레이어에 inv_layer_consume 이 하나라도 붙어 있으면 p_force 여도
--          예외 — 메시지에 소비된 레이어 수를 담는다. 소비 기록까지 지우는 것은 「재기준선」이라는
--          별개 절차이고 이 함수가 조용히 할 일이 아니다. inv_layer_cost_add 도 같은 이유로 확인한다
--          (기초에 붙을 일은 없지만 붙어 있으면 거부).
--  가드 3  p_snapshot_key 로 inv_snapshot 에 qty>0 인 행이 하나도 없으면 예외 —
--          오타로 빈 기초를 만드는 것을 막는다.
--  가드 4  p_snapshot_key 의 행 중 value<0 이 하나라도 있으면 예외 — 메시지에 행 수와 최솟값.
--  삽입    inv_snapshot 의 그 키에서 sku·warehouse 로 묶어 합산한다.
--          qty=sum(qty) · unit_cost=sum(value)/sum(qty) (소수 6자리 · inv_cost 와 같은 정밀도) ·
--          origin_type='baseline' · cost_source='snapshot_value' ·
--          received_on=min(taken_at) 의 토론토 날짜 · age_known=false ·
--          doc_number/line_ref/parent_layer_id=null.
--          ⚠️ qty>0 인 행만. warehouse 는 있는 그대로(IN_TRANSIT 필터 없음 — 기초 스냅샷은 OnHand 만
--          읽으므로 애초에 IN_TRANSIT 이 없다). value 가 null 인 행은 0 으로 친다(실측 0건 · 방어).
--  반환    jsonb { snapshot_key, layers_inserted, total_qty, total_value, received_on, forced }
--          forced = 기존 baseline 행을 실제로 지우고 다시 넣었는가.
--
-- 왜 bin 을 합치나 — 레이어는 창고 단위다. [실측 2026-09-08]
-- 13,830칸 중 여러 bin 에 걸친 SKU×창고는 14개뿐이고, 그중 단가가 다른 것이
-- 13개, 차이가 10% 를 넘는 것은 0개(최악 1.09배)다. ⇒ 합쳐도 잃는 것이 없다.
-- ⭐ 그리고 이것은 Cin7 이 같은 SKU 에 사실상 하나의 단가를 쓴다는 뜻이다 —
-- bin 별 FIFO 가 아니라 SKU 단위 가중평균일 가능성이 크다(⬜ 미확인).
-- ⚠️ 그러면 우리 FIFO 계산액과 Cin7 평가액은 구조적으로 완전히 같을 수 없다.
-- 대조는 「크게 벗어나나」로 보고 「정확히 일치」를 목표로 삼지 말 것.
--
-- ⚠️ 가드 4 — 음수 평가액은 거부한다. unit_cost >= 0 CHECK 에 걸려 함수가
-- 어차피 실패하는데, 그때는 제약 위반 메시지만 나와 원인을 알 수 없다.
-- [실측 2026-09-08 · 2026-08-20-initial] 0건이지만 다른 키로 재기준선을 잡을 때
-- 섞일 수 있다. ⚠️ 0 으로 깎지 않는다 — 음수 평가액은 우리가 판단할 수 없는
-- 값이고, 사람이 원인을 보게 해야 한다(「모르면 비워둔다」).
--
-- age_known = false — 기초는 실제 입고일을 모른다. received_on 은 FIFO 정렬용
-- 이고 나이가 아니다. aging summary 는 이 플래그로 분리해야 한다.
-- ⚠️ inv_layer.age_known 은 default 가 없다(일부러) — 여기서 반드시 명시한다.
--
-- 규모 [실측 2026-08-20-initial] — 13,844행 · 13,830칸(qty>0) ·
-- 총 1,909,097개 · $3,055,493.66 · 개당 $1.6005.
-- ⚠️ 이것이 현재 재고의 96% 다(8/20 이후 입고분은 3.6%).
--
-- ⚠️ security definer — inv_layer 는 authenticated 의 delete 를 회수했다(inv_layer 헤더 · 일부러).
--  p_force 의 baseline 삭제는 이 함수가 유일하게 허가된 경로여야 하므로 소유자 권한으로 돈다
--  (inv_snap_balance_diffs 선례). 지우는 범위는 origin_type='baseline' 으로 고정돼 있고 가드 2 가
--  소비·원가가 붙은 레이어를 막는다. search_path 는 inv_compare_run 과 같이 고정한다.
--
-- 조회 예시:
--   select inv_layer_seed_baseline('2026-08-20-initial');
--   select count(*), sum(qty), round(sum(unit_cost*qty),2)
--   from inv_layer where origin_type='baseline';

create or replace function inv_layer_seed_baseline(p_snapshot_key text, p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing     int;
  v_consumed     int;
  v_cost_added   int;
  v_snap_rows    int;
  v_neg_rows     int;
  v_min_value    numeric;
  v_received_on  date;
  v_inserted     int;
  v_total_qty    numeric;
  v_total_value  numeric;
  v_forced       boolean := false;
begin
  -- 가드 1: 이미 기초가 있다
  select count(*) into v_existing from inv_layer where origin_type = 'baseline';
  if v_existing > 0 and not p_force then
    raise exception 'inv_layer already has % baseline layer(s) — call with p_force := true to replace', v_existing;
  end if;

  -- 가드 2: 지우려는 기초에 소비·원가가 붙어 있다 — 그것은 재기준선의 일이다
  if v_existing > 0 then
    select count(distinct l.id) into v_consumed
      from inv_layer l
      where l.origin_type = 'baseline'
        and exists (select 1 from inv_layer_consume c where c.layer_id = l.id);
    select count(distinct l.id) into v_cost_added
      from inv_layer l
      where l.origin_type = 'baseline'
        and exists (select 1 from inv_layer_cost_add a where a.layer_id = l.id);
    if v_consumed > 0 or v_cost_added > 0 then
      raise exception 'refusing to replace baseline: % layer(s) have consume rows and % layer(s) have cost_add rows — rebaselining is a separate procedure',
        v_consumed, v_cost_added;
    end if;
  end if;

  -- 가드 3: 스냅샷 키에 qty>0 행이 없다 — 오타로 빈 기초를 만들지 않는다
  select count(*), (min(taken_at) at time zone 'America/Toronto')::date
    into v_snap_rows, v_received_on
    from inv_snapshot
    where snapshot_key = p_snapshot_key and qty > 0;
  if v_snap_rows = 0 then
    raise exception 'inv_snapshot has no rows with qty > 0 for snapshot_key %', p_snapshot_key;
  end if;

  -- 가드 4: 음수 평가액 — 0 으로 깎지 않고 사람이 보게 한다
  select count(*), min(value) into v_neg_rows, v_min_value
    from inv_snapshot
    where snapshot_key = p_snapshot_key and value < 0;
  if v_neg_rows > 0 then
    raise exception 'inv_snapshot has % row(s) with negative value (min %) for snapshot_key % — refusing to seed',
      v_neg_rows, v_min_value, p_snapshot_key;
  end if;

  -- 가드를 전부 지난 뒤에만 지운다
  if v_existing > 0 then
    delete from inv_layer where origin_type = 'baseline';
    v_forced := true;
  end if;

  -- 삽입: bin 을 버리고 sku·warehouse 로 합산. age_known 은 default 가 없으니 반드시 명시.
  insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                         received_on, age_known, qty, unit_cost, cost_source)
  select s.sku, s.warehouse, 'baseline', null, null, null,
         v_received_on, false,
         sum(s.qty),
         round(sum(coalesce(s.value, 0)) / sum(s.qty), 6),
         'snapshot_value'
    from inv_snapshot s
    where s.snapshot_key = p_snapshot_key and s.qty > 0
    group by s.sku, s.warehouse;
  get diagnostics v_inserted = row_count;

  select coalesce(sum(qty), 0), coalesce(round(sum(unit_cost * qty), 2), 0)
    into v_total_qty, v_total_value
    from inv_layer where origin_type = 'baseline';

  return jsonb_build_object(
    'snapshot_key',    p_snapshot_key,
    'layers_inserted', v_inserted,
    'total_qty',       v_total_qty,
    'total_value',     v_total_value,
    'received_on',     v_received_on,
    'forced',          v_forced);
end;
$$;

revoke all on function inv_layer_seed_baseline(text, boolean) from public, anon;
grant execute on function inv_layer_seed_baseline(text, boolean) to authenticated;
