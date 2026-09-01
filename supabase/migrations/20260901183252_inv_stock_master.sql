-- 재고 마스터 — 원장이 WMS 화면에 제공하는 것 (2026-09-01)
--
-- 방향: 「검증이 깨끗해지면 화면을 연다」에는 끝이 없다 — 화면은 검증의 보상이 아니라
--   **검증 도구**다. WMS 처럼 만들고 고쳐나간다.
--   ⚠️ WMS 와 다른 점 하나: 원장 재고는 8,060 SKU 라 틀려도 모를 수 있다 ⇒ **Cin7 열을
--   나란히 둔다** — 「원장이 정답」이라 주장하지 않고, 틀린 숫자가 위험이 아니라 보이는 것이 되게.
--
-- 구성 셋: ① inv_stock_master RPC(전체 재고 + Cin7 열 · 검색/필터/페이징 서버측)
--          ② inv_balance_diffs(어긋남 일지 — 아침에 굳힌 대조 · first_seen_on 이 시간 축)
--          ③ inv_bin_notes(코멘트 — 원인을 아는 사람의 한 줄)
-- ⚠️ 화면은 WMS 쪽 몫 · 자동 상쇄 없음(사람이 확인하고 원장이 넣는다) ·
--   「해결됨」 상태 없음(상쇄가 들어가야 실제로 맞는다).

-- ─────────────────────────────────────────────────────────
-- 1) inv_stock_master — 조회 RPC
-- ─────────────────────────────────────────────────────────
-- ⚠️ PostgREST 는 1,000행에서 조용히 잘린다(레포 관례 — 규칙 20 계열). 8,060 SKU 를 뷰로
--   직접 읽으면 안 된다 ⇒ 검색·필터·페이징을 서버에서 하고 **jsonb 로 감싸** 캡을 피한다.
-- ⚠️ security invoker — RLS 를 우회하지 않는다(뷰·테이블 전부 authenticated 정책).
-- 📌 IN_TRANSIT 도 포함한다. 걸러내려면 p_warehouse 로 한다
--   (⚠️ 거기 음수는 기초 스냅샷 경계 아티팩트다 — TR-03975·TR-03976 · 버그 아님).
--   ⚠️ 다만 IN_TRANSIT 은 Cin7 에 대응 축이 없어(inv_balance_vs_cin7 이 제외한다)
--   cin7_qty·diff 를 null 로 둔다 — 0 으로 두면 p_only_diff 가 IN_TRANSIT 전부를
--   「이상」으로 세어 아침 기준 9칸이 수십 칸이 된다(지시서 검증 ③과 모순).
-- ⚠️ Cin7 에만 있는 칸(원장 잔고 축에 행이 없는 칸)도 나와야 한다 — union all 가지.
--   left join 만 쓰면 「원장 0 · Cin7 실재」 부류(예: 원장이 '' 에 넣고 Cin7 은 실제 bin)가
--   빠져 p_only_diff 가 그 어긋남을 못 보여준다.
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
  with j as (
    select
      b.sku, b.warehouse, b.bin,
      b.baseline_qty, b.delta_qty, b.qty as ledger_qty,
      case when b.warehouse = 'IN_TRANSIT' then null else coalesce(c.cin7_qty, 0) end as cin7_qty,
      case when b.warehouse = 'IN_TRANSIT' then null
           else coalesce(b.qty, 0) - coalesce(c.cin7_qty, 0) end as diff
    from inv_balance b
    left join inv_balance_vs_cin7 c
      on  c.sku = b.sku and c.warehouse = b.warehouse and c.bin = b.bin
    union all
    -- Cin7 에만 있는 칸 — 원장 잔고 축에 행이 없다(기초에도 원장에도 없던 자리)
    select c.sku, c.warehouse, c.bin, 0, 0, 0, c.cin7_qty, c.diff
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
    'rows',  coalesce((
      select jsonb_agg(x order by x.sku, x.warehouse, x.bin)
      from (select * from f order by sku, warehouse, bin
            limit greatest(p_limit,1) offset greatest(p_offset,0)) x
    ), '[]'::jsonb)
  );
$$;
-- ⚠️ total 을 함께 준다 — 화면이 페이징을 그릴 수 있어야 한다.

revoke all on function inv_stock_master(text,text,boolean,boolean,int,int) from public, anon;
grant execute on function inv_stock_master(text,text,boolean,boolean,int,int) to authenticated;

-- ─────────────────────────────────────────────────────────
-- 2) inv_balance_diffs — 어긋남 일지
-- ─────────────────────────────────────────────────────────
-- ⚠️⚠️ 대조는 아침 스냅샷 직후에만 유효하다. [실측 2026-09-01] 같은 계산이 아침 9칸 ·
--   오후 128칸을 냈다 ⇒ 매일 아침 한 번 굳혀 둔다(cron — ops/cron.sql 주석).
-- ⭐ first_seen_on 이 시간 축이다 — 「새로 생긴 것」과 「한 달째 그대로인 것」이 갈린다.
create table inv_balance_diffs (
  id            bigint generated always as identity primary key,
  checked_on    date        not null,          -- 대조 기준일
  snapshot_key  text        not null,          -- 어느 Cin7 스냅샷과 댔나
  snapshot_at   timestamptz not null,          -- ⭐ 화면에 「○시 기준」으로 띄운다
  sku           text        not null,
  warehouse     text        not null,
  bin           text        not null default '',
  ledger_qty    numeric     not null,
  cin7_qty      numeric     not null,
  diff          numeric     not null,
  first_seen_on date        not null,          -- ⭐ 이 칸이 처음 어긋난 날
  created_at    timestamptz not null default now()
);

create unique index inv_balance_diffs_uq
  on inv_balance_diffs (checked_on, sku, warehouse, bin);
create index inv_balance_diffs_first_idx on inv_balance_diffs (first_seen_on);

alter table inv_balance_diffs enable row level security;
create policy auth_all on inv_balance_diffs for all to authenticated using (true) with check (true);
revoke all on inv_balance_diffs from anon;

-- 채우는 함수 — 최신 스냅샷과의 어긋남을 그날 일지로 굳힌다.
-- ⚠️ first_seen_on 은 **직전 회차에 같은 칸이 있었을 때만** 이어받는다 — 연속으로 어긋나
--   있으면 처음 날짜가 유지되고, **중간에 한 번 맞았다가(=직전 회차 일지에 없음) 다시
--   어긋나면 그날이 새 시작**이 된다(「다시 생긴 문제」이기 때문 — 지시서 명시 의도).
--   📌 전 기록 min() 으로 이어받으면 재발이 옛 날짜를 물려받아 「한 달째 vs 재발」 구분이
--   깨진다 — 그래서 직전 회차(마지막 checked_on) 기준이다. cron 이 며칠 빠져도
--   「마지막으로 실제로 돈 회차」와 비교하므로 견딘다.
-- ⚠️ on conflict do nothing — 같은 날 두 번 돌아도 안전하다.
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
     ledger_qty, cin7_qty, diff, first_seen_on)
  select v_on, v_key, v_at, d.sku, d.warehouse, d.bin,
         d.ledger_qty, d.cin7_qty, d.diff,
         coalesce(
           (select p.first_seen_on from inv_balance_diffs p
             where p.checked_on = v_prev
               and p.sku = d.sku and p.warehouse = d.warehouse and p.bin = d.bin),
           v_on)
  from inv_balance_vs_cin7 d
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
-- 3) inv_bin_notes — 코멘트
-- ─────────────────────────────────────────────────────────
-- ⭐ 이 화면의 목적이다 — 원인을 아는 사람이 한 줄 적으면 우리가 몇 시간을 아낀다.
-- ⚠️ 수정·삭제 정책을 만들지 않는다 — 기록이 목적이다. 여러 명이 여러 줄 적는다.
-- ⚠️⚠️ author 는 「누가 틀렸나」가 아니라 「누가 알려줬나」다.
--   [2026-08-25 확정 원칙] 지표를 개인 평가로 쓰지 않는다 — 순위·색 강조·개인 귀속 금지.
--   ⇒ 화면에서도 그 구분이 보여야 한다(WMS 답신의 요구이기도 하다).
create table inv_bin_notes (
  id          bigint generated always as identity primary key,
  sku         text not null,
  warehouse   text not null,
  bin         text not null default '',
  note        text not null,
  author      text not null,
  created_at  timestamptz not null default now()
);

create index inv_bin_notes_key_idx on inv_bin_notes (sku, warehouse, bin, created_at desc);

alter table inv_bin_notes enable row level security;
create policy auth_read   on inv_bin_notes for select to authenticated using (true);
create policy auth_insert on inv_bin_notes for insert to authenticated with check (true);
revoke all on inv_bin_notes from anon;

-- ─────────────────────────────────────────────────────────
-- 검증 (마이그레이션 후 Caleb 이 실행 — 지시서 §5)
-- ─────────────────────────────────────────────────────────
-- ① RPC 기본
--   select jsonb_pretty(inv_stock_master(p_limit := 5));
-- ② 검색
--   select jsonb_pretty(inv_stock_master(p_search := 'SKL018', p_limit := 10));
-- ③ ⭐ 이상만 — 아침 기준 9칸 근처여야 한다 (⚠️ 오후에는 드리프트로 커진다 — 아침 값과 비교)
--   select jsonb_pretty(inv_stock_master(p_only_diff := true, p_limit := 50));
-- ④ 일지 채우기 (수동 1회)
--   select jsonb_pretty(inv_snap_balance_diffs());
-- ⑤ 일지 확인 — first_seen_on 이 오늘로 찍힌다(첫 실행이라 전부 오늘)
--   select checked_on, first_seen_on, count(*) as rows
--   from inv_balance_diffs group by 1,2 order by 1 desc;
-- ⑥ 코멘트 왕복
--   insert into inv_bin_notes (sku, warehouse, bin, note, author)
--   values ('SKL01861','Asung Trading Inc.','D110302','TR-04169 로 옮겼음 (테스트)','caleb@asung.ca');
--   select * from inv_bin_notes order by created_at desc limit 5;
-- ⑦ 성능
--   explain analyze select inv_stock_master(p_limit := 200);
