-- 「확인됨」 축 — 신규와 확인된 것을 가른다 (2026-09-01)
--
-- 왜: WMS 착수 조건 ② — 영구 비영 항목이 이미 확정돼 있다(잔여 칸 미조사 · IN_TRANSIT 영구
--   음수). 카드가 「신규 vs 확인됨」을 가르지 못하면 매일 7 이 떠 있다가 8 이 되는 날을 놓친다.
--   무시되는 경고는 없는 것과 같다. (대조군: WMS Health 탭은 12검사 전부 0 유지라 하나만
--   켜져도 눈에 띈다.) ⇒ 원장의 기존 「사람이 닫는 축」(inv_missing_lines.resolved_at) 패턴을
--   inv_balance_diffs 에 넣는다.
--
-- ⚠️ 두 상태를 혼동하지 말 것:
--   확인됨(acknowledged) = ⭐ 창고·매니저 — 원인을 안다. 숫자는 아직 틀려 있다.
--   해결됨               = 원장 — 상쇄를 넣어 실제로 맞췄다.
--   📌 「해결됨」 버튼은 만들지 않는다 — 상쇄가 들어가면 다음 회차에 그 칸이 목록에서
--   저절로 사라진다. 별도 상태가 필요 없다. 화면이 누르는 것은 「확인됨」 하나다.
-- ⚠️ 취소(un-ack)도 만들지 않는다 — 잘못 눌렀으면 inv_bin_notes 에 한 줄 적는다.
-- ⚠️ 과거 회차는 수정하지 않는다 — 그날의 기록이다.

-- ─────────────────────────────────────────────────────────
-- 1) inv_balance_diffs — 확인 컬럼 셋
-- ─────────────────────────────────────────────────────────
-- 📌 acknowledged_note 는 「누르면서 한 줄 적는 자리」다. inv_bin_notes 와 다르다 —
--   그건 여러 명이 여러 줄, 이건 확인 행위에 붙는 한 줄이다.
alter table inv_balance_diffs
  add column acknowledged_at timestamptz,
  add column acknowledged_by text,
  add column acknowledged_note text;

-- ─────────────────────────────────────────────────────────
-- 2) inv_snap_balance_diffs() — 확인 승계 추가
-- ─────────────────────────────────────────────────────────
-- ⚠️ checked_on 마다 행이 새로 생기므로 어제 확인해도 오늘 행은 다시 미확인이 된다
--   ⇒ first_seen_on 과 같은 방식으로 잇는다: **직전 checked_on 기준**(전체 과거가 아니다).
--   직전 회차의 같은 칸에 acknowledged_at 이 있으면 at·by·note 셋 다 그대로 물려받고,
--   없으면 null(미확인). 📌 중간에 한 번 해소됐다가 재발하면 확인도 새로 받아야 한다 —
--   「다시 생긴 문제」이기 때문이다.
-- ⚠️ 아래는 20260901183252 정의에 승계만 더한 것 — first_seen_on 의 상관 서브쿼리를
--   같은 의미의 left join 으로 바꿨다(prev 행에서 4개 값을 가져와야 해서. 유니크 인덱스
--   (checked_on,sku,warehouse,bin) 이 prev 행 최대 1개를 보장하므로 행 수 불변).
create or replace function inv_snap_balance_diffs()
returns jsonb
language plpgsql security definer
as $$
declare
  v_key  text;  v_at timestamptz;  v_on date;  v_prev date;  v_rows int;
begin
  select snapshot_key, max(taken_at) into v_key, v_at
  from inv_snapshot group by snapshot_key order by max(taken_at) desc limit 1;
  if v_key is null then return jsonb_build_object('ok', false, 'error', 'no snapshot'); end if;
  v_on := (v_at at time zone 'America/Toronto')::date;

  -- 직전 회차 — 오늘보다 앞선 마지막 checked_on (없으면 null = 전부 새 시작)
  select max(checked_on) into v_prev from inv_balance_diffs where checked_on < v_on;

  insert into inv_balance_diffs
    (checked_on, snapshot_key, snapshot_at, sku, warehouse, bin,
     ledger_qty, cin7_qty, diff, first_seen_on,
     acknowledged_at, acknowledged_by, acknowledged_note)
  select v_on, v_key, v_at, d.sku, d.warehouse, d.bin,
         d.ledger_qty, d.cin7_qty, d.diff,
         coalesce(p.first_seen_on, v_on),
         p.acknowledged_at, p.acknowledged_by, p.acknowledged_note   -- ⭐ 확인 승계 — 직전 회차에서만
  from inv_balance_vs_cin7 d
  left join inv_balance_diffs p
    on  p.checked_on = v_prev
    and p.sku = d.sku and p.warehouse = d.warehouse and p.bin = d.bin
  where d.diff <> 0
  on conflict (checked_on, sku, warehouse, bin) do nothing;

  get diagnostics v_rows = row_count;
  return jsonb_build_object('ok', true, 'checked_on', v_on,
                            'snapshot_key', v_key, 'inserted', v_rows);
end;
$$;

revoke all on function inv_snap_balance_diffs() from public, anon;
grant execute on function inv_snap_balance_diffs() to authenticated;

-- ─────────────────────────────────────────────────────────
-- 3) inv_ack_diff — 확인 누르기
-- ─────────────────────────────────────────────────────────
-- ⚠️ 최신 회차만 갱신한다 — 과거 회차는 그날의 기록이라 건드리지 않는다.
-- 📌 p_by 는 화면이 로그인 사용자를 넘긴다. 없으면 current_user.
create or replace function inv_ack_diff(
  p_sku       text,
  p_warehouse text,
  p_bin       text default '',
  p_note      text default null,
  p_by        text default null
) returns jsonb
language plpgsql security invoker
as $$
declare v_on date; v_rows int;
begin
  select max(checked_on) into v_on from inv_balance_diffs;
  if v_on is null then return jsonb_build_object('ok', false, 'error', 'no diffs'); end if;

  update inv_balance_diffs
     set acknowledged_at = now(),
         acknowledged_by = coalesce(p_by, current_user),
         acknowledged_note = p_note
   where checked_on = v_on
     and sku = p_sku and warehouse = p_warehouse and bin = coalesce(p_bin, '');

  get diagnostics v_rows = row_count;
  return jsonb_build_object('ok', v_rows > 0, 'checked_on', v_on, 'updated', v_rows);
end;
$$;

revoke all on function inv_ack_diff(text,text,text,text,text) from public, anon;
grant execute on function inv_ack_diff(text,text,text,text,text) to authenticated;

-- ─────────────────────────────────────────────────────────
-- 4) inv_diff_summary — 화면 카드용 요약
-- ─────────────────────────────────────────────────────────
-- ⭐ unack 이 카드의 숫자다 — 그것이 0 을 향해 갈 수 있다.
-- ⭐ new_today 가 「오늘 처음 생긴 것」 — WMS 가 요구한 조기 발견 축.
-- 📌 prev_total 로 어제 대비 증감을 화면이 그린다.
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
  )
  select jsonb_build_object(
    'checked_on',   (select d from latest),
    'snapshot_at',  (select max(snapshot_at) from cur),
    'total',        (select count(*) from cur),
    'new_today',    (select count(*) from cur where first_seen_on = checked_on),   -- ⭐ 오늘 처음
    'unack',        (select count(*) from cur where acknowledged_at is null),      -- ⭐ 카드의 숫자
    'acked',        (select count(*) from cur where acknowledged_at is not null),
    'prev_total',   (select n from prev),
    'abs_gap',      (select coalesce(sum(abs(diff)), 0) from cur)
  );
$$;

revoke all on function inv_diff_summary() from public, anon;
grant execute on function inv_diff_summary() to authenticated;

-- ─────────────────────────────────────────────────────────
-- 5) inv_stock_master — 목록에 확인 상태 얹기 (추가만)
-- ─────────────────────────────────────────────────────────
-- rows[] 에 추가: first_seen_on(처음 어긋난 날) · acknowledged_at(null=미확인) ·
--   acknowledged_note(확인할 때 적은 한 줄). ⚠️ 최신 checked_on 행에서만(left join).
-- ⚠️ 기존 키(rows·total·snapshot_key·snapshot_at·컬럼 이름)는 그대로 — 화면 계약이
--   문서에 박혀 있다. 아래는 20260901185640 정의에 ack CTE 와 컬럼 3개만 더한 것.
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
-- ① 일지를 한 번 채운다 (오늘 것이 없으면)
--   select jsonb_pretty(inv_snap_balance_diffs());
-- ② 요약 — 카드가 읽을 값
--   select jsonb_pretty(inv_diff_summary());
-- ③ ⭐ 확인 누르기 — BNAT48173 은 미조사지만 「보고 있다」로 표시해 본다
--    ⚠️ updated: 0 이면 최신 checked_on 에 그 칸이 없는 것 — ①을 먼저 돌렸는지 확인.
--   select jsonb_pretty(inv_ack_diff('BNAT48173','Asung Trading Inc.','C120102',
--     '미조사 — 원인 확인 중', 'caleb@asung.ca'));
-- ④ 요약이 갈리는가 — unack 이 하나 줄어야 한다
--   select jsonb_pretty(inv_diff_summary());
-- ⑤ 목록에 확인 상태가 실리는가
--   select jsonb_pretty(inv_stock_master(p_only_diff := true, p_limit := 20));
-- ⑥ 권한
--   select routine_name, grantee, privilege_type
--   from information_schema.routine_privileges
--   where routine_name in ('inv_ack_diff','inv_diff_summary') order by 1,2;
-- 📌 승계 검증은 로컬에서 했다(3회차: 확인→승계, 해소→재발→새로 받아야 함) —
--   프로덕션은 회차가 하루 한 번이라 못 본다.
