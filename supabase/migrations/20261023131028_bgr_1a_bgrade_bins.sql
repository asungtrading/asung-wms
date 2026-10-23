do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;

-- ═══ bgr-1a — B급 칸 ① 칸 표시 · 「팔 수 있는 잔고」 한 곳 · 가용 · 자동 칸 (2026-10-23 · 판정 629 · 635 · 636 · 637 · 641 · bgr-0 회신) ═══
--   ① ref_bin.is_bgrade + 창구 ref_bin_bgrade_set(master · 켤 때 · 끌 때 잔고 있으면 거부) + 트리거 ref_bin_bgrade_guard(창구 밖에서 바꾸지 못한다 · current_user = postgres 만)
--   ② so_line.bgrade_bin_id(칸만 · 채우는 길은 bgr-1c) ③ ims_inv_balance 끝에 bin_is_bgrade · inv_available_base(drop + create · qty_ea = 팔 수 있는 장부 · bgrade_ea · B급 줄 할당 빼기)
--   ④ stk_availability(by_warehouse bgrade · B급만 있는 줄도 보임 · 서명 무변) · stk_reserved(alloc 과 같은 조건) ⑤ so_pick_plan · wms_pick_lines · wms_pick_shelf · ims_last_bin · wms_pick_line_bins_write(거부)
--   stk_bins · stk_bins_many 는 무변 — 반환 칸을 더하면 서명이 바뀐다 · 화면은 ref_bin.is_bgrade 를 bin_id 로 읽는다(select 열림) · 새 표 · 시퀀스 0(판정 615)

-- ═══ ① 칸 표시 ═══
alter table public.ref_bin add column is_bgrade boolean not null default false;
comment on column public.ref_bin.is_bgrade is 'bgr-1a 판정 636 · 641 — 「B급」 칸(파손 포장품 · POS 에서만 팖) · 이 칸의 잔고는 모든 가용 · On hand 에서 빠지고 옆 칸(B-grade)으로 따로 · 자동 칸 · 픽 안내 · 칸 기본이 가지 않는다 · 바꾸는 길 = ref_bin_bgrade_set(master) 하나';

create function public.ref_bin_bgrade_guard() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  -- bgr-1a 판정 636: is_bgrade 는 창구(ref_bin_bgrade_set · definer · 주인 postgres)만 바꾼다 — 화면 · PostgREST(authenticated) · 적재(service_role)의 직접 update · insert 는 막는다(적재는 기본 false 라 무해)
  if ((tg_op = 'INSERT' and new.is_bgrade) or (tg_op = 'UPDATE' and new.is_bgrade is distinct from old.is_bgrade)) and current_user <> 'postgres' then
    raise exception using errcode = 'IM636', message = 'B-grade is set with Mark as B-grade (it checks the bin is empty first) — nothing was saved';
  end if;
  return new;
end $$;
revoke all on function public.ref_bin_bgrade_guard() from public, anon, authenticated, service_role;
create trigger ref_bin_bgrade_guard before insert or update on public.ref_bin for each row execute function public.ref_bin_bgrade_guard();

create function public.ref_bin_bgrade_set(p_bin_id uuid, p_on boolean) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
-- bgr-1a 판정 636: 칸에 「B급」 표시 켜기 · 끄기 — 문 master · 켤 때 그 칸에 잔고가 있으면 거부(정상 재고가 값 없이 B급이 된다) · 끌 때 잔고 · 열린 B급 줄이 있으면 거부 · 같은 값이면 무해(changed false)
declare v_b public.ref_bin%rowtype;  v_wh text;  v_n int;  v_q numeric;  v_open int;
begin
  perform public.ims_require_write('master', 'saved');
  if p_on is null then raise exception 'p_on must be true or false — nothing was saved'; end if;
  select * into v_b from public.ref_bin where id = p_bin_id for update;
  if not found then raise exception 'Bin % not found — nothing was saved', p_bin_id; end if;
  if not v_b.is_active then raise exception 'Bin % is switched off — switch it on first — nothing was saved', v_b.name; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_b.warehouse_id;
  if v_b.is_bgrade = p_on then
    return jsonb_build_object('bin_id', v_b.id, 'bin', v_b.name, 'warehouse', v_wh, 'is_bgrade', v_b.is_bgrade, 'changed', false);
  end if;
  select count(*), coalesce(sum(b.qty), 0) into v_n, v_q from public.inv_balance b where b.warehouse = v_wh and b.bin = v_b.name and b.qty <> 0;
  if p_on and v_n > 0 then
    raise exception 'Bin % in % holds stock (% EA in % SKU line(s)) — move the stock out first, then mark it B-grade — nothing was saved', v_b.name, v_wh, v_q, v_n;
  end if;
  if not p_on and v_n > 0 then
    raise exception 'Bin % in % still holds B-grade stock (% EA in % SKU line(s)) — move it back to a regular bin first — nothing was saved', v_b.name, v_wh, v_q, v_n;
  end if;
  if not p_on then
    select count(*) into v_open from public.so_line l join public.so s on s.id = l.so_id where l.bgrade_bin_id = v_b.id and s.status not in ('fulfilled', 'cancelled');
    if v_open > 0 then raise exception 'Bin % is on % open B-grade sale line(s) — finish or remove them first — nothing was saved', v_b.name, v_open; end if;
  end if;
  update public.ref_bin set is_bgrade = p_on where id = v_b.id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Bin % was not saved — it may have been changed by someone else just now — nothing was saved', v_b.name; end if;
  return jsonb_build_object('bin_id', v_b.id, 'bin', v_b.name, 'warehouse', v_wh, 'is_bgrade', p_on, 'changed', true);
end $$;
revoke all on function public.ref_bin_bgrade_set(uuid, boolean) from public, anon, service_role;
grant execute on function public.ref_bin_bgrade_set(uuid, boolean) to authenticated;
comment on function public.ref_bin_bgrade_set(uuid, boolean) is 'bgr-1a 판정 636 — 칸의 B급 표시 켜기 · 끄기(master) · 잔고 있는 칸은 거부(켜기: 먼저 비운다 · 끄기: 먼저 되돌린다) · 끌 때 열린 B급 줄 거부 · 같은 값 무해';

-- ═══ ② so_line.bgrade_bin_id ═══
alter table public.so_line add column bgrade_bin_id uuid references public.ref_bin(id);
comment on column public.so_line.bgrade_bin_id is 'bgr-1a 판정 634 · 635 — B급으로 파는 줄의 B급 칸(POS 에서만 · 채우는 길은 bgr-1c) · so_pick_plan 이 이 칸 하나에서만 뺀다 · 할당은 정상 가용에서 빠지지 않는다(inv_available_base · stk_reserved)';

-- ═══ ③ 「팔 수 있는 잔고」 한 곳 — 뷰 끝에 bin_is_bgrade(칸 순서 · 이름 · 옵션 그대로 · ACL · comment 는 create or replace 가 지킨다) ═══
create or replace view public.ims_inv_balance with (security_invoker = true) as
 WITH baseline AS (
         SELECT inv_config.value AS k
           FROM inv_config
          WHERE inv_config.key = 'baseline_snapshot_key'::text
        ), baseline_at AS (
         SELECT (max(s.taken_at) AT TIME ZONE 'America/Toronto'::text)::date AS taken_on
           FROM inv_snapshot s,
            baseline b_1
          WHERE s.snapshot_key = b_1.k
        ), last_ev AS (
         SELECT l.sku,
            l.warehouse,
            COALESCE(l.bin, ''::text) AS bin,
            max(l.occurred_on) AS last_event_on,
            count(*) AS event_rows
           FROM inv_ledger l
          GROUP BY l.sku, l.warehouse, (COALESCE(l.bin, ''::text))
        )
 SELECT b.sku,
    b.warehouse,
    b.bin,
    b.baseline_qty,
    b.delta_qty,
    b.qty,
    p.id AS product_id,
    w.id AS warehouse_id,
    rb.id AS bin_id,
    rb.zone AS bin_zone,
    rb.is_active AS bin_is_active,
    le.last_event_on,
    COALESCE(le.last_event_on, ba.taken_on) AS last_seen_on,
    COALESCE(le.event_rows, 0::bigint) AS event_rows,
    COALESCE(rb.is_bgrade, false) AS bin_is_bgrade
   FROM inv_balance b
     CROSS JOIN baseline_at ba
     LEFT JOIN last_ev le ON le.sku = b.sku AND le.warehouse = b.warehouse AND le.bin = b.bin
     LEFT JOIN product p ON p.sku = b.sku
     LEFT JOIN ref_warehouse w ON w.name = b.warehouse
     LEFT JOIN ref_bin rb ON rb.warehouse_id = w.id AND rb.name = b.bin AND b.bin <> ''::text;
comment on column public.ims_inv_balance.bin_is_bgrade is 'bgr-1a 판정 641 — 그 칸이 B급 칸인가(ref_bin.is_bgrade · 칸 없는 행 · 마스터에 없는 칸은 false) · 가용 · 자동 칸은 이 칸이 true 인 행을 뺀다';

-- inv_available_base — 반환 칸이 하나 늘어 drop + create(부르는 여덟은 모두 칸 이름으로 읽는다 · select * 0)
drop function public.inv_available_base(uuid, uuid[]);
create function public.inv_available_base(p_location_id uuid, p_stock_pids uuid[] default null)
  returns table (stock_pid uuid, qty_ea numeric, sales_alloc_ea numeric, transfer_alloc_ea numeric, bgrade_ea numeric)
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  with wh as (                                                                            -- 창고 이름 — 뷰는 warehouse(이름) · sku 로 걸러야 inv_ledger (sku, warehouse) 인덱스로 내려간다(warehouse_id · product_id 로 거르면 뷰 전체 18k 행을 센다)
    select w.name from public.ref_warehouse w where w.id = p_location_id
  ),
  skus as (                                                                              -- 부른 키의 sku 들 — p_stock_pids 가 null 이면 null(= 전부)
    select case when p_stock_pids is null then null else (select array_agg(p.sku) from public.product p where p.id = any(p_stock_pids)) end as arr
  ),
  bal as (                                                                               -- 장부 — 창고의 모든 bin 합(ims_inv_balance · product 에 없는 sku 는 재고 키가 아니다)
    select b.product_id as stock_pid, sum(b.qty) filter (where not b.bin_is_bgrade) as qty, sum(b.qty) filter (where b.bin_is_bgrade) as bg   -- bgr-1a 판정 641: 팔 수 있는 장부 = B급 칸을 뺀 합 · B급 칸 합은 bg 로 따로
    from public.ims_inv_balance b
    where b.warehouse = (select name from wh) and b.product_id is not null
      and ((select k.arr from skus k) is null or b.sku = any((select k.arr from skus k)::text[]))   -- 스칼라 서브쿼리(InitPlan 상수)라 뷰 안 인덱스 조건으로 내려간다 · 괄호만 쓰면 서브쿼리 꼴(text = text[])로 읽힌다
    group by b.product_id
  ),
  alloc as (                                                                             -- 판매 예약 — 열린 allocated 예약 × 줄의 pack_factor · 오더 창고 · 재고 키 = 낱개(세트는 parent)
    select coalesce(p.parent_product_id, p.id) as stock_pid, sum(r.qty_allocated * l.pack_factor) as ea
    from public.so_reserve r
    join public.so_line l on l.id = r.so_line_id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    where r.released_at is null and r.kind = 'allocated'
      and s.location_id = p_location_id
      and (p_stock_pids is null or coalesce(p.parent_product_id, p.id) = any(p_stock_pids))
      and l.bgrade_bin_id is null                                                       -- bgr-1a(bgr-0 이견 2): B급 줄의 할당은 정상 가용을 깎지 않는다(stk_reserved 와 같은 조건)
    group by 1
  ),
  talloc as (                                                                            -- 트랜스퍼 예약(tr-1a 묶음 2) — 확정된 문서(창고로 보내기 · 픽 중 포함 · 출발 전)의 줄 자체 · 출발 창고 · 낱개 EA
    select coalesce(p.parent_product_id, p.id) as stock_pid, sum(l.qty * l.pack_factor) as ea
    from public.inv_transfer_line l
    join public.inv_transfer t on t.id = l.transfer_id
    join public.product p on p.id = l.product_id
    where t.status in ('confirmed', 'at_wms', 'picking')
      and t.from_warehouse_id = p_location_id
      and (p_stock_pids is null or coalesce(p.parent_product_id, p.id) = any(p_stock_pids))
    group by 1
  ),
  keys as (
    select stock_pid from bal union select stock_pid from alloc union select stock_pid from talloc
  )
  select k.stock_pid,
         coalesce(bal.qty, 0),
         coalesce(alloc.ea, 0),
         coalesce(talloc.ea, 0),
         coalesce(bal.bg, 0)                                                              -- bgr-1a: bgrade_ea(그 창고 B급 칸 잔고 합 · 수량만)
  from keys k
  left join bal    on bal.stock_pid    = k.stock_pid
  left join alloc  on alloc.stock_pid  = k.stock_pid
  left join talloc on talloc.stock_pid = k.stock_pid;
$$;
revoke all on function public.inv_available_base(uuid, uuid[]) from public, anon;
grant execute on function public.inv_available_base(uuid, uuid[]) to authenticated, service_role;
comment on function public.inv_available_base(uuid, uuid[]) is '⭐⭐ 가용 재고 식 한 곳(stk-1 · 판정 264 · 265 · 2026-10-06 · 종전 so_available_many 본문) — 창고 하나의 재고 키(낱개 · 세트는 parent · p_stock_pids null = 전부 · 배열 = 그 키만 — 장부는 sku = any 로 뷰 안 인덱스에 밀어넣어 1 키 ~56 ms · 전부 ~170 ms · 배열 7,663 은 쓰지 마라(null 로)) → (stock_pid · qty_ea 창고 잔고 = ims_inv_balance 모든 bin 합 · sales_alloc_ea Σ 열린 allocated 예약 × pack_factor(오더 창고) · transfer_alloc_ea Σ 확정 · at_wms · picking 트랜스퍼 줄 qty × pack_factor(출발 창고)) · available = qty_ea − sales_alloc_ea − transfer_alloc_ea 는 부르는 쪽이 뺀다(so_available_many · stk_availability) · 조인 한 문장(= any 는 sku 밀어넣기에만 · product_id = any 는 뷰 전체를 센다) · ⭐ definer(판정 264): inv_transfer 의 select 정책은 transfer · WMS 열쇠인데 가용은 모든 직원에게 같아야 한다 — invoker 였던 so_available_many 는 sales 만 가진 직원에게 트랜스퍼 예약을 0 으로 보였다 · 원가 열 없음(판정 262) · authenticated execute(invoker 껍데기들이 부른다) · 음수 그대로 · preorder · hold · backorder 는 빼지 않는다 · ⭐ [2026-10-20 stk-av-1 판정 566] alloc · talloc 의 조건은 stk_reserved(목록)와 서로 같은 조건 — 한쪽을 고치면 다른 쪽도(시험: 모든 키 × 창고에서 목록 합 = 타일) · ⭐ [2026-10-23 bgr-1a 판정 641] qty_ea = 팔 수 있는 장부(B급 칸 is_bgrade 제외) · bgrade_ea = 그 창고 B급 칸 잔고 합(새 다섯째 칸) · alloc 은 B급 줄(so_line.bgrade_bin_id)의 할당을 뺀다(stk_reserved 와 같은 조건)';

-- ═══ so_pick_plan 재발행 — 원본 DB 바이트(md5 86a9e3d97643fb31dd51d7be6d273e5c) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1a」 주석) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.so_pick_plan(p_so_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_doc      public.wms_order_doc%rowtype;
  v_wh       text;
  v_cands    jsonb := '{}'::jsonb;     -- 낱개 product_id → [{bin_id, bin, qty, ovf, rank}] (순서대로)
  v_tot      jsonb := '{}'::jsonb;     -- 낱개 product_id → 창고 전체 잔고(모든 칸 · '' · 비활성 포함)
  v_used     jsonb := '{}'::jsonb;     -- product_id → 앞 줄이 계획한 EA(창고 부족분 계산)
  v_taken    jsonb := '{}'::jsonb;     -- product_id|bin_id → 앞 줄이 계획한 EA(칸 남은 잔고)
  v_totb     jsonb := '{}'::jsonb;     -- bgr-1a: product_id|B급 bin_id → 그 B급 칸 잔고(B급 줄의 부족분 계산)
  v_bgname   text;                     -- bgr-1a: B급 줄의 칸 이름(그 칸에 장부 행이 없을 때)
  l          record;
  c          jsonb;
  v_arr      jsonb;
  v_key      text;
  v_need_u   numeric;  v_need_ea numeric;  v_rem numeric;  v_avail numeric;  v_take numeric;
  v_first    text;
  v_lines    jsonb := '[]'::jsonb;
  v_picks    jsonb := '[]'::jsonb;
  v_lp       jsonb;
  v_short    numeric;  v_short_tot numeric := 0;
  v_tot_p    numeric;  v_used_p numeric;
  v_warn     text[] := '{}';
  i          int;
begin
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found'; end if;
  if v_doc.warehouse_id is null then raise exception 'Order % has no warehouse — nothing to plan', v_doc.doc_number; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_doc.warehouse_id;

  -- 칸 잔고 한 문장(ims_inv_balance 를 한 번) — 후보(활성 칸 · bin 있음)는 순서를 붙여 · 창고 전체 잔고는 모든 행
  with pids as (
    select distinct x.stock_product_id as pid
    from public.wms_order_doc_line x where x.doc_id = p_so_id
  ), bal as (
    select v.product_id, v.bin_id, v.bin, v.qty, v.bin_is_active, v.last_seen_on, v.bin_is_bgrade                         -- bgr-1a: B급 칸 표시를 함께
    from public.ims_inv_balance v join pids on pids.pid = v.product_id
    where v.warehouse_id = v_doc.warehouse_id
  ), cand as (
    select b.product_id, b.bin_id, b.bin, b.qty, (o.id is not null) as ovf, b.last_seen_on, b.bin_is_bgrade as bg,      -- bgr-1a
           case when b.qty > 0 and o.id is null then 1 when b.qty > 0 then 2 when o.id is null then 3 else 4 end as rank   -- 재고 있는 평소 → 재고 있는 보관용 → 빈 평소 → 빈 보관용
    from bal b left join public.product_bin_overflow o on o.product_id = b.product_id and o.bin_id = b.bin_id
    where b.bin_id is not null and b.bin_is_active
  )
  select coalesce((select jsonb_object_agg(x.product_id::text, x.arr)
                   from (select cd.product_id, jsonb_agg(jsonb_build_object('bin_id', cd.bin_id, 'bin', cd.bin, 'qty', cd.qty, 'ovf', cd.ovf, 'rank', cd.rank, 'bg', cd.bg)   -- bgr-1a: bg
                                                          order by cd.rank, cd.last_seen_on desc, cd.qty desc, cd.bin) as arr
                         from cand cd group by cd.product_id) x), '{}'::jsonb),
         coalesce((select jsonb_object_agg(y.product_id::text, y.t) from (select b2.product_id, sum(b2.qty) as t from bal b2 where not b2.bin_is_bgrade group by b2.product_id) y), '{}'::jsonb),   -- bgr-1a: 정상 줄의 창고 잔고 = B급 칸 제외
         coalesce((select jsonb_object_agg(y.k, y.t) from (select b3.product_id::text || '|' || b3.bin_id::text as k, sum(b3.qty) as t from bal b3 where b3.bin_is_bgrade group by 1) y), '{}'::jsonb)   -- bgr-1a: B급 칸마다
    into v_cands, v_tot, v_totb;

  for l in
    select x.line_id as id, x.line_no, x.sku, x.qty_target, x.pack_factor, x.stock_product_id as pid, (p.parent_product_id is not null) as is_set, sl.bgrade_bin_id as bg   -- bgr-1a
    from public.wms_order_doc_line x join public.product p on p.id = x.product_id left join public.so_line sl on sl.id = x.line_id                              -- bgr-1a: 트랜스퍼 줄은 null
    where x.doc_id = p_so_id order by x.line_no
  loop
    v_need_u  := l.qty_target;                    -- 보낼 목표(판매 단위 · 판정 5 §17)
    v_need_ea := v_need_u * l.pack_factor;
    v_lp := '[]'::jsonb;  v_rem := v_need_u;  v_first := null;
    v_arr := (select coalesce(jsonb_agg(e order by o), '[]'::jsonb) from jsonb_array_elements(coalesce(v_cands->(l.pid::text), '[]'::jsonb)) with ordinality t(e, o)   -- bgr-1a 판정 635: 정상 줄은 B급 칸을 빼고 · B급 줄은 그 칸 하나만(순서 그대로)
              where case when l.bg is null then not coalesce((e->>'bg')::boolean, false) else (e->>'bin_id')::uuid = l.bg end);
    if l.bg is not null and jsonb_array_length(v_arr) = 0 then                    -- bgr-1a: 그 B급 칸에 장부 행이 없으면 그 칸 하나를 빈 후보로(모자란 몫은 다른 칸으로 넘치지 않는다)
      select rb.name into v_bgname from public.ref_bin rb where rb.id = l.bg;
      v_arr := jsonb_build_array(jsonb_build_object('bin_id', l.bg, 'bin', v_bgname, 'qty', 0, 'ovf', false, 'rank', 3, 'bg', true));
    end if;
    if jsonb_array_length(v_arr) > 0 then v_first := v_arr->0->>'bin'; end if;

    -- 재고 있는 칸(순서대로)에서 · 세트 줄은 칸마다 정수 세트만(floor(칸 EA ÷ pack)) · 앞 줄이 계획한 몫은 뺀다
    for i in 0 .. jsonb_array_length(v_arr) - 1 loop
      exit when v_rem <= 0;
      c := v_arr->i;
      if (c->>'rank')::int > 2 then exit; end if;               -- 재고 없는 칸은 채우는 자리가 아니다
      v_key := l.pid::text || '|' || (c->>'bin_id');
      v_avail := (c->>'qty')::numeric - coalesce((v_taken->>v_key)::numeric, 0);
      if v_avail <= 0 then continue; end if;
      v_take := least(v_rem, floor(v_avail / l.pack_factor));    -- 낱개는 pack 1 · 세트는 정수 세트
      if v_take <= 0 then continue; end if;
      v_lp := v_lp || jsonb_build_object('line_id', l.id, 'bin', c->>'bin', 'qty', v_take, 'from', case when (c->>'ovf')::boolean then 'overflow' else 'usual' end);
      v_taken := jsonb_set(v_taken, array[v_key], to_jsonb(coalesce((v_taken->>v_key)::numeric, 0) + v_take * l.pack_factor));
      v_rem := v_rem - v_take;
    end loop;
    -- 모자란 몫 — 첫 후보 칸에(재고 0 이어도 · 그 칸이 음수가 될 수 있다 · 판정 1) · 후보가 없으면 ''
    if v_rem > 0 then
      v_lp := v_lp || jsonb_build_object('line_id', l.id, 'bin', coalesce(v_first, ''), 'qty', v_rem, 'from', case when v_first is null then 'none' else 'fallback' end);
      if v_first is not null then
        v_key := l.pid::text || '|' || (v_arr->0->>'bin_id');
        v_taken := jsonb_set(v_taken, array[v_key], to_jsonb(coalesce((v_taken->>v_key)::numeric, 0) + v_rem * l.pack_factor));
      else
        v_warn := array_append(v_warn, 'no_bins:' || l.sku);
      end if;
    end if;
    -- 창고 전체 부족분(고침 ①) — 모든 칸 잔고 합에서 같은 제품의 앞 줄이 쓴 EA 를 뺀 것보다 필요 EA 가 많은 몫 · 원장 FIFO 가 세울 부족분 레이어와 같아야 한다
    v_tot_p  := case when l.bg is null then coalesce((v_tot->>(l.pid::text))::numeric, 0) else coalesce((v_totb->>(l.pid::text || '|' || l.bg::text))::numeric, 0) end;   -- bgr-1a: B급 줄은 그 칸 잔고
    v_used_p := coalesce((v_used->>(l.pid::text || coalesce('|' || l.bg::text, '')))::numeric, 0);                                                                 -- bgr-1a: 열쇠 = pid(정상) · pid|칸(B급)
    v_short  := greatest(0, v_need_ea - greatest(v_tot_p - v_used_p, 0));
    v_used   := jsonb_set(v_used, array[l.pid::text || coalesce('|' || l.bg::text, '')], to_jsonb(v_used_p + v_need_ea));                                              -- bgr-1a
    v_short_tot := v_short_tot + v_short;
    if v_short > 0 then v_warn := array_append(v_warn, 'stock_short:' || l.sku); end if;

    v_picks := v_picks || v_lp;
    v_lines := v_lines || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'is_set', l.is_set, 'pack_factor', l.pack_factor,
                                             'to_ship', v_need_u, 'need_ea', v_need_ea, 'warehouse_qty_ea', v_tot_p, 'picks', v_lp, 'short_ea', v_short);
  end loop;

  return jsonb_build_object('so_id', v_doc.doc_id, 'so_number', v_doc.doc_number, 'warehouse_id', v_doc.warehouse_id, 'warehouse', v_wh,
                            'picks', v_picks, 'lines', v_lines, 'short_ea_total', v_short_tot, 'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ wms_pick_lines 재발행 — 원본 DB 바이트(md5 6d306c6f85928d1498cc90ad866c6252) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1a」 주석) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.wms_pick_lines(p_task_ids bigint[] DEFAULT NULL::bigint[], p_pack_task_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_task_ids bigint[];
  v_pack_id  bigint := p_pack_task_id;
  v_out      jsonb;
begin
  if (p_task_ids is null or cardinality(p_task_ids) = 0) = (p_pack_task_id is null) then
    raise exception 'Pass exactly one of p_task_ids / p_pack_task_id';
  end if;
  if p_pack_task_id is not null then
    select array[k.pick_task_id] into v_task_ids from public.wms_pack_tasks k where k.id = p_pack_task_id;
    if v_task_ids is null or v_task_ids[1] is null then return '[]'::jsonb; end if;     -- 팩 과제 없음 · 픽 과제 없는 팩 과제 = 빈 배열(깨끗한 빈손)
  else
    v_task_ids := p_task_ids;
  end if;

  with t as (
    select t.id, t.batch_label, coalesce(t.order_id, t.transfer_id) as order_id, t.wave_id, t.tote_no,
           d.doc_number as so_number, d.warehouse_id as location_id, w.name as wh_name, d.party_name as customer_name
    from public.wms_pick_tasks t
    join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
    left join public.ref_warehouse w on w.id = d.warehouse_id
    where t.id = any(v_task_ids)
  ), pl as (
    select l.id as line_id, l.pick_task_id, l.order_line_id, l.transfer_line_id, l.assigned_base, l.picked_base, l.status, l.verification_method, l.picked_by, l.picked_at,
           t.order_id, t.so_number, t.customer_name, t.location_id, t.wh_name, t.batch_label, t.wave_id, t.tote_no,
           x.sku, x.product_name, x.pack_factor,
           x.combo_line_id, x.combo_qty, x.combo_sku,                                                                       -- asm-2b1(판정 244 · 묶음 6): 구성품 줄이 어느 콤보 것인지
           coalesce(p.parent_product_id, p.id) as stock_pid, (p.parent_product_id is not null) as is_set
    from public.wms_pick_task_lines l
    join t on t.id = l.pick_task_id
    join public.wms_order_doc_line x on x.line_id = coalesce(l.order_line_id, l.transfer_line_id)
    join public.product p on p.id = x.product_id
  ), pids as (
    select distinct pl.stock_pid from pl
  ), whs as (
    select distinct t.location_id from t where t.location_id is not null
  ), bal as (                                                             -- 창고 전체 잔고 · 한 문장 · 한 번(속도 함정)
    select v.warehouse_id, v.product_id, sum(v.qty) as qty
    from public.ims_inv_balance v
    where v.product_id = any(array(select pids.stock_pid from pids))
      and v.warehouse_id = any(array(select whs.location_id from whs))
      and not v.bin_is_bgrade                                             -- bgr-1a 판정 635 · 641: 팔 수 있는 잔고만
    group by v.warehouse_id, v.product_id
  ), bc as (                                                              -- 낱개(factor 1) + 그 낱개를 parent 로 둔 세트들(factor = pack_factor)
    select coalesce(p.parent_product_id, p.id) as stock_pid,
           jsonb_agg(jsonb_build_object('barcode', b.barcode,
                                        'factor', case when p.parent_product_id is null then 1 else coalesce(p.pack_factor, 1) end,
                                        'sku', p.sku)
                     order by case when p.parent_product_id is null then 1 else coalesce(p.pack_factor, 1) end, b.is_primary desc, b.barcode) as arr
    from public.product_barcode b
    join public.product p on p.id = b.product_id
    where b.is_active
      and (p.id = any(array(select pids.stock_pid from pids)) or p.parent_product_id = any(array(select pids.stock_pid from pids)))
    group by coalesce(p.parent_product_id, p.id)
  ), bins as (                                                            -- 계획 칸(planned) · 실제 칸(actual) · 존은 여기 한 곳에서
    select x.pick_task_line_id, x.planned,
           jsonb_agg(jsonb_build_object('bin', x.bin, 'bin_id', x.bin_id, 'qty_base', x.qty_base,
                                        'zone', coalesce(rb.zone,
                                                         case when coalesce(x.bin, '') = '' then ''
                                                              when pl2.wh_name ilike '%edmonton%' and upper(left(x.bin, 1)) = 'E' then upper(substr(x.bin, 2, 1))
                                                              else upper(left(x.bin, 1)) end),
                                        'picked_by', x.picked_by, 'picked_at', x.picked_at)
                     order by x.id) as arr
    from public.wms_pick_line_bins x
    join pl pl2 on pl2.line_id = x.pick_task_line_id
    left join public.ref_bin rb on rb.id = x.bin_id
    group by x.pick_task_line_id, x.planned
  ), sbal as (                                                            -- pick-bin-2(판정 122) 칸 잔고 한 번 · bal 과 같은 술어 · bin 있는 행만(속도 함정)
    select v.warehouse_id, v.product_id, v.bin_id, v.qty, v.bin_is_active
    from public.ims_inv_balance v
    where v.product_id = any(array(select pids.stock_pid from pids))
      and v.warehouse_id = any(array(select whs.location_id from whs))
      and v.bin_id is not null
      and not v.bin_is_bgrade                                             -- bgr-1a 판정 635: 픽 안내가 B급 칸으로 가지 않는다
  ), sb as (                                                              -- 칸 목록 — 계획 칸 전부 + 장부 qty > 0 인 활성 칸 · 계획 먼저(계획 행 순) · 장부 내림 · 이름 · qty 는 낱개(EA)
    select z.line_id,
           jsonb_agg(jsonb_build_object('bin_id', z.bin_id, 'bin', z.bin, 'zone', z.zone, 'qty', z.qty, 'is_active', z.is_active, 'planned', z.planned)
                     order by z.planned desc, z.plan_ord nulls last, z.qty desc, z.bin) as arr
    from (
      select pl3.line_id, rb.id as bin_id, rb.name as bin,
             coalesce(rb.zone, case when coalesce(rb.name, '') = '' then ''
                                    when pl3.wh_name ilike '%edmonton%' and upper(left(rb.name, 1)) = 'E' then upper(substr(rb.name, 2, 1))
                                    else upper(left(rb.name, 1)) end) as zone,
             coalesce(s.qty, 0) as qty, rb.is_active, (pb.min_id is not null) as planned, pb.min_id as plan_ord
      from pl pl3
      join lateral (select s0.bin_id from sbal s0 where s0.product_id = pl3.stock_pid and s0.warehouse_id = pl3.location_id and s0.qty > 0 and s0.bin_is_active
                    union
                    select x.bin_id from public.wms_pick_line_bins x where x.pick_task_line_id = pl3.line_id and x.planned) c on true
      join public.ref_bin rb on rb.id = c.bin_id
      left join sbal s on s.bin_id = c.bin_id and s.product_id = pl3.stock_pid and s.warehouse_id = pl3.location_id
      left join (select x.pick_task_line_id, x.bin_id, min(x.id) as min_id from public.wms_pick_line_bins x where x.planned group by 1, 2) pb
             on pb.pick_task_line_id = pl3.line_id and pb.bin_id = c.bin_id
    ) z
    group by z.line_id
  ), pk as (                                                              -- 팩 갈래 — 팩 줄(order_line_id 로 짝)
    select k.id as pack_line_id, k.order_line_id, k.transfer_line_id, k.expected_base, k.verified_base, k.status as pack_status,
           k.verification_method as pack_verification_method, k.verified_by, k.verified_at
    from public.wms_pack_task_lines k
    where v_pack_id is not null and k.pack_task_id = v_pack_id
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'line_id', case when v_pack_id is null then pl.line_id else pk.pack_line_id end,
             'pick_line_id', pl.line_id,
             'pick_task_id', pl.pick_task_id, 'batch_label', pl.batch_label, 'wave_id', pl.wave_id, 'tote_no', pl.tote_no,
             'order_line_id', coalesce(pl.order_line_id, pl.transfer_line_id), 'so_id', pl.order_id, 'so_number', pl.so_number, 'customer_name', pl.customer_name, 'warehouse_id', pl.location_id,
             'sku', pl.sku, 'base_sku', sp.sku, 'product_name', pl.product_name, 'pack_factor', pl.pack_factor, 'is_set', pl.is_set,
             'combo_line_id', pl.combo_line_id, 'combo_qty', pl.combo_qty, 'combo_sku', pl.combo_sku,                                              -- asm-2b1: 화면이 「for combo ○○」 를 그린다 · 보통 줄은 null
             'assigned_base', pl.assigned_base, 'picked_base', pl.picked_base,
             'status', case when v_pack_id is null then pl.status else pk.pack_status end,
             'verification_method', case when v_pack_id is null then pl.verification_method else pk.pack_verification_method end,
             'picked_by', pl.picked_by, 'picked_at', pl.picked_at,
             'planned_bins', coalesce(bp.arr, '[]'::jsonb), 'actual_bins', coalesce(ba.arr, '[]'::jsonb),
             'stock_bins', coalesce(sb.arr, '[]'::jsonb),
             'barcodes', coalesce(bc.arr, '[]'::jsonb),
             'available_ea', coalesce(bal.qty, 0))
           || case when v_pack_id is null then '{}'::jsonb
                   else jsonb_build_object('pack_line_id', pk.pack_line_id, 'expected_base', pk.expected_base, 'verified_base', pk.verified_base,
                                           'pack_status', pk.pack_status, 'pack_verification_method', pk.pack_verification_method,
                                           'verified_by', pk.verified_by, 'verified_at', pk.verified_at) end
           order by pl.tote_no nulls first, pl.pick_task_id, pl.line_id), '[]'::jsonb)
    into v_out
  from pl
  join public.product sp on sp.id = pl.stock_pid
  left join bal  on bal.warehouse_id = pl.location_id and bal.product_id = pl.stock_pid
  left join bc   on bc.stock_pid = pl.stock_pid
  left join bins bp on bp.pick_task_line_id = pl.line_id and bp.planned
  left join bins ba on ba.pick_task_line_id = pl.line_id and not ba.planned
  left join sb   on sb.line_id = pl.line_id
  left join pk   on coalesce(pk.order_line_id, pk.transfer_line_id) = coalesce(pl.order_line_id, pl.transfer_line_id)
  where v_pack_id is null or pk.pack_line_id is not null;

  return v_out;
end
$function$;

-- ═══ wms_pick_shelf 재발행 — 원본 DB 바이트(md5 a2f0316cb38746d6bbd67bc38790d8ee) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1a」 주석) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.wms_pick_shelf(p_warehouse_id uuid, p_skus text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_wh public.ref_warehouse%rowtype; v_items jsonb;
begin
  perform public.ims_require_write('picking', 'saved');                                   -- ⭐ 첫 줄(wms_pick_line_save 와 같다 · 판정 39 · fail-closed)
  if p_warehouse_id is null or not public.ims_can_warehouse(p_warehouse_id) then           -- ⭐ 둘째(같은 문장)
    raise exception 'This task is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  select * into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if not found then raise exception 'Warehouse not found or inactive — nothing was saved'; end if;
  if p_skus is null or cardinality(array_remove(p_skus, null)) = 0 then raise exception 'p_skus must be a list of SKUs — nothing was saved'; end if;
  with req as (                                                                            -- 입력 SKU → 낱개 상품(세트는 parent 로 접는다) · 모르는 SKU 는 글자 그대로 · 같은 낱개로 접히면 한 줄
    select distinct on (coalesce(sp.sku, btrim(s.sku))) coalesce(sp.sku, btrim(s.sku)) as sku, sp.id as product_id, sp.name as product_name
      from unnest(p_skus) as s(sku)
      left join public.product p  on p.sku = btrim(s.sku)
      left join public.product sp on sp.id = coalesce(p.parent_product_id, p.id)
     where btrim(coalesce(s.sku, '')) <> ''
  ), bk as (                                                                               -- 장부 — 그 창고 · 칸 있는 행 · qty ≠ 0
    select r.sku, b.bin, b.qty as book
      from req r join public.inv_balance b on b.sku = r.sku and b.warehouse = v_wh.name
     where b.bin <> '' and b.qty <> 0
       and not exists (select 1 from public.ref_bin rb0 where rb0.warehouse_id = v_wh.id and rb0.name = b.bin and rb0.is_bgrade)   -- bgr-1a 판정 635: 선반 보기에 B급 칸 없음
  ), pl as (                                                                               -- 열린 픽 계획 칸(이 창고 · 이 상품들)
    select distinct coalesce(pr.parent_product_id, pr.id) as product_id, pb.bin_id, pb.bin
      from public.wms_pick_line_bins pb
      join public.wms_pick_task_lines l on l.id = pb.pick_task_line_id
      join public.wms_pick_tasks t on t.id = l.pick_task_id
      join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
      join public.wms_order_doc_line ol on ol.line_id = coalesce(l.order_line_id, l.transfer_line_id)
      join public.product pr on pr.id = ol.product_id
     where pb.planned and t.status in ('pending', 'in_progress') and d.warehouse_id = v_wh.id and d.wms_stage in ('at_wms', 'picking')
       and coalesce(pr.parent_product_id, pr.id) in (select q.product_id from req q where q.product_id is not null)
  ), pk as (                                                                               -- P — inv_adjust_picked 와 같은 술어 · (칸, 낱개 상품) 으로 한 번에
    select pb.bin_id, coalesce(pr.parent_product_id, pr.id) as product_id, sum(pb.qty_base) as picked
      from public.wms_pick_line_bins pb
      join public.wms_pick_task_lines l on l.id = pb.pick_task_line_id
      join public.wms_pick_tasks t on t.id = l.pick_task_id
      join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
      join public.wms_order_doc_line ol on ol.line_id = coalesce(l.order_line_id, l.transfer_line_id)
      join public.product pr on pr.id = ol.product_id
     where not pb.planned and d.warehouse_id = v_wh.id and d.status in ('picking', 'packed')
       and coalesce(pr.parent_product_id, pr.id) in (select q.product_id from req q where q.product_id is not null)
     group by 1, 2
  ), bins as (                                                                             -- 장부 칸(이름 → ref_bin id) ∪ 계획 칸(장부에 없는 것만 · book 0)
    select r.sku, r.product_id, rb.id as bin_id, bk.bin, bk.book
      from bk join req r on r.sku = bk.sku
      left join public.ref_bin rb on rb.warehouse_id = v_wh.id and rb.name = bk.bin
    union
    select r.sku, r.product_id, pl.bin_id, pl.bin, 0::numeric
      from pl join req r on r.product_id = pl.product_id
     where not exists (select 1 from bk where bk.sku = r.sku and bk.bin = pl.bin)
  ), x as (
    select b.sku, b.product_id, b.bin_id, b.bin, b.book, coalesce(pk.picked, 0) as picked,
           exists (select 1 from pl where pl.product_id = b.product_id and pl.bin_id = b.bin_id) as planned
      from bins b
      left join pk on pk.bin_id = b.bin_id and pk.product_id = b.product_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'product_id', r.product_id, 'sku', r.sku, 'product_name', r.product_name,
           'bins', coalesce((select jsonb_agg(jsonb_build_object('bin_id', x.bin_id, 'bin', x.bin, 'book', x.book, 'picked', x.picked, 'on_shelf', x.book - x.picked, 'planned', x.planned) order by x.bin)
                              from x where x.sku = r.sku), '[]'::jsonb)) order by r.sku), '[]'::jsonb)
    into v_items from req r;
  return jsonb_build_object('warehouse_id', v_wh.id, 'warehouse', v_wh.name, 'items', v_items);
end;
$function$;

-- ═══ ims_last_bin 재발행 — 원본 DB 바이트(md5 b8440c61835780ed0b9ff30a22524274) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1a」 주석) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.ims_last_bin(p_product_ids uuid[], p_warehouse_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_object_agg(x.product_id::text,
           jsonb_build_object('bin_id', x.bin_id, 'bin', x.bin, 'zone', x.bin_zone, 'received_on', x.last_seen_on)), '{}'::jsonb)
  from (
    select distinct on (v.product_id)
           v.product_id, v.bin_id, v.bin, v.bin_zone, v.last_seen_on
    from public.ims_inv_balance v
    left join public.product_bin_overflow o on o.product_id = v.product_id and o.bin_id = v.bin_id   -- ④a1: 보관용 표시(SKU × 칸)
    where v.product_id   = any(coalesce(p_product_ids, '{}'::uuid[]))
      and v.warehouse_id = p_warehouse_id
      and v.bin_id is not null            -- '' · 마스터에 없는 bin 은 후보 밖
      and v.bin_is_active                 -- 비활성 bin 에 놓으라고 하지 않는다
      and not v.bin_is_bgrade             -- bgr-1a(bgr-0 이견 8): 입고 · 크레딧 · 조정 칸 기본이 B급 칸으로 가지 않는다
    order by v.product_id, (o.id is null) desc, (v.qty > 0) desc, v.last_seen_on desc, v.qty desc, v.bin   -- ④a1: 보관용 아님을 맨 앞에(판정 2 · 평시 칸 먼저) · 나머지 키 그대로
  ) x;
$function$;

-- ═══ wms_pick_line_bins_write 재발행 — 원본 DB 바이트(md5 dac698c3ce5233988860a15a94490933) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1a」 주석) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.wms_pick_line_bins_write(p_line_id bigint, p_picked numeric, p_bins jsonb, p_wh uuid, p_worker uuid, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_b jsonb;  v_pl record;
  v_sum numeric := 0;  v_n int := 0;  v_rem numeric;  v_qty numeric;
  v_bin uuid;  v_bin_name text;  v_first uuid;  v_first_name text;
  v_mode text;  v_pid uuid;  v_out jsonb;  v_warn text[] := '{}';
begin
  if p_picked is null or p_picked < 0 then raise exception 'Line %: picked quantity must be 0 or more — nothing was saved', p_line_id; end if;
  -- ① 갈래: bins 가 왔으면 교체(given) · 안 왔으면 이미 적힌 실제 행(pack_task_id null)의 합 = picked 면 그대로(kept · 판정 121) · 없거나 다르면 계획 칸 순서(planned · 옛 화면 그대로)
  if jsonb_typeof(p_bins) = 'array' and jsonb_array_length(p_bins) > 0 then
    v_mode := 'given';
  else
    select coalesce(sum(x.qty_base), 0), count(*) into v_sum, v_n
      from public.wms_pick_line_bins x where x.pick_task_line_id = p_line_id and not x.planned and x.pack_task_id is null;
    v_mode := case when v_n > 0 and p_picked > 0 and v_sum = p_picked then 'kept' else 'planned' end;
  end if;
  if v_mode <> 'kept' then
    delete from public.wms_pick_line_bins x where x.pick_task_line_id = p_line_id and not x.planned and x.pack_task_id is null;   -- 팩 회복 행(pack_task_id)은 손대지 않는다
    v_sum := 0;  v_n := 0;
    if p_picked > 0 and v_mode = 'given' then
      for v_b in select * from jsonb_array_elements(p_bins) loop
        v_qty := coalesce((v_b->>'qty_base')::numeric, 0);
        if v_qty <= 0 then raise exception 'Line %: a bin row has qty_base <= 0 — nothing was saved', p_line_id; end if;
        v_bin := null;  v_bin_name := null;
        if v_b ? 'bin_id' then
          select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.id = (v_b->>'bin_id')::uuid and rb.warehouse_id = p_wh;
        else
          select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.name = trim(v_b->>'bin') and rb.warehouse_id = p_wh;
        end if;
        if v_bin is null then raise exception 'Line %: bin % is not in this warehouse — nothing was saved', p_line_id, coalesce(v_b->>'bin', v_b->>'bin_id'); end if;
        if (select rb.is_bgrade from public.ref_bin rb where rb.id = v_bin) then            -- bgr-1a 판정 635: 정상 오더 줄에 B급 칸 저장 거부(B급은 POS 에서만)
          raise exception 'Line %: bin % is a B-grade bin — B-grade stock is sold at POS only, pick from a regular bin — nothing was saved', p_line_id, v_bin_name;
        end if;
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (p_line_id, v_bin, v_bin_name, v_qty, false, p_worker, p_now);
        v_n := v_n + 1;  v_sum := v_sum + v_qty;
      end loop;
      if v_sum <> p_picked then raise exception 'Line %: bin quantities (%) do not add up to picked (%) — nothing was saved', p_line_id, v_sum, p_picked; end if;
    elsif p_picked > 0 then
      v_rem := p_picked;  v_first := null;
      for v_pl in select x.bin_id, x.bin, x.qty_base from public.wms_pick_line_bins x where x.pick_task_line_id = p_line_id and x.planned order by x.id loop
        if v_first is null then v_first := v_pl.bin_id; v_first_name := v_pl.bin; end if;
        exit when v_rem <= 0;
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (p_line_id, v_pl.bin_id, v_pl.bin, least(v_rem, v_pl.qty_base), false, p_worker, p_now);
        v_n := v_n + 1;  v_rem := v_rem - least(v_rem, v_pl.qty_base);
      end loop;
      if v_rem > 0 and v_first is not null then                      -- 계획보다 많이 뽑았다 → 첫 계획 칸이 나머지를 받는다
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (p_line_id, v_first, v_first_name, v_rem, false, p_worker, p_now);
        v_n := v_n + 1;  v_rem := 0;
      end if;
      if v_rem > 0 then raise exception 'Line %: no bins given and no planned bins to fall back on — nothing was saved', p_line_id; end if;
    end if;
  end if;
  -- ② 반환 — 칸마다 장부(ims_inv_balance · 낱개 EA · 이 픽은 출고 전이라 아직 안 빠진 값) · is_active · 경고(판정 123 — 막지 않는다)
  select coalesce(pr.parent_product_id, pr.id) into v_pid
    from public.wms_pick_task_lines pl join public.wms_order_doc_line l on l.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
    join public.product pr on pr.id = l.product_id where pl.id = p_line_id;
  select coalesce(jsonb_agg(jsonb_build_object('bin_id', x.bin_id, 'bin', x.bin, 'qty_base', x.qty_base, 'ledger_qty', coalesce(v.qty, 0), 'is_active', rb.is_active,
                                               'planned', exists (select 1 from public.wms_pick_line_bins q where q.pick_task_line_id = p_line_id and q.planned and q.bin_id = x.bin_id))
                            order by x.id), '[]'::jsonb),
         coalesce(array_agg(format('ledger_short:%s:%s<%s', x.bin, coalesce(v.qty, 0), x.qty_base) order by x.id) filter (where coalesce(v.qty, 0) < x.qty_base), '{}')
         || coalesce(array_agg(format('inactive_bin:%s', x.bin) order by x.id) filter (where not rb.is_active), '{}')
    into v_out, v_warn
    from public.wms_pick_line_bins x
    join public.ref_bin rb on rb.id = x.bin_id
    left join public.ims_inv_balance v on v.bin_id = x.bin_id and v.warehouse_id = p_wh and v.product_id = v_pid
   where x.pick_task_line_id = p_line_id and not x.planned and x.pack_task_id is null;
  return jsonb_build_object('mode', v_mode, 'rows', v_n, 'bins', v_out, 'warnings', to_jsonb(v_warn));
end
$function$;

-- ═══ stk_reserved 재발행 — 원본 DB 바이트(md5 bf0e12bb8140f1e5b8ae19a3beca3cb5) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1a」 주석) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.stk_reserved(p_product_id uuid, p_warehouse_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff     uuid;
  v_pid       uuid;
  v_sku       text;
  v_wh        text;
  v_sales     boolean;
  v_so        jsonb;
  v_trf       jsonb;
  v_so_total  numeric;
  v_trf_total numeric;
begin
  -- 문(판정 268) — 로그인 + 활성 직원 · 열쇠는 보지 않는다(stk_* 와 같은 문)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if v_wh is null then raise exception 'Warehouse not found or inactive — pick an active branch'; end if;
  select coalesce(p.parent_product_id, p.id) into v_pid from public.product p where p.id = p_product_id;   -- 재고 키 = 낱개(세트 id 를 받으면 그 낱개 · inv_available_base 와 같은 키)
  if v_pid is null then raise exception 'Product not found — nothing was read'; end if;
  select p.sku into v_sku from public.product p where p.id = v_pid;
  v_sales := public.ims_can_view('sales');   -- 손님 이름은 sales(:read 포함) 열쇠가 있는 사람에게만 · 창고 직원에게는 SO 번호 · 상태 · 수량만
  -- ⭐ 판매 예약 — inv_available_base 의 alloc 과 서로 같은 조건(판정 566) — 한쪽을 고치면 다른 쪽도:
  --   released_at null · kind allocated(hold · backorder · preorder 는 안 셈) · 오더 창고 s.location_id · 재고 키 coalesce(parent_product_id, id) · qty_allocated × 줄 pack_factor · 콤보는 구성품 줄이 그대로 걸린다
  select coalesce(jsonb_agg(jsonb_build_object(
           'so_id', s.id, 'so_number', s.so_number, 'status', s.status,
           'customer_name', case when v_sales then c.name end,
           'line_sku', l.sku, 'qty', r.qty_allocated, 'pack_factor', l.pack_factor, 'qty_ea', r.qty_allocated * l.pack_factor,
           'allocated_at', r.allocated_at) order by r.allocated_at, s.so_number, l.line_no), '[]'::jsonb),
         coalesce(sum(r.qty_allocated * l.pack_factor), 0)
    into v_so, v_so_total
  from public.so_reserve r
  join public.so_line l on l.id = r.so_line_id
  join public.so s on s.id = l.so_id
  join public.product p on p.id = l.product_id
  left join public.customer c on c.id = s.customer_id
  where r.released_at is null and r.kind = 'allocated'
    and s.location_id = p_warehouse_id
    and l.bgrade_bin_id is null                                                        -- bgr-1a: inv_available_base alloc 과 같은 조건(B급 줄의 할당은 타일 · 목록 둘 다 빠진다)
    and coalesce(p.parent_product_id, p.id) = v_pid;
  -- ⭐ 트랜스퍼 예약 — inv_available_base 의 talloc 과 서로 같은 조건(판정 566): status confirmed · at_wms · picking(출발 전) · 출발 창고 · qty × 줄 pack_factor
  select coalesce(jsonb_agg(jsonb_build_object(
           'transfer_id', t.id, 'transfer_number', t.transfer_number, 'status', t.status,
           'from_warehouse', wf.name, 'to_warehouse', wt.name,
           'line_sku', l.sku, 'qty', l.qty, 'pack_factor', l.pack_factor, 'qty_ea', l.qty * l.pack_factor,
           'confirmed_at', t.confirmed_at) order by t.transfer_number, l.line_no), '[]'::jsonb),
         coalesce(sum(l.qty * l.pack_factor), 0)
    into v_trf, v_trf_total
  from public.inv_transfer_line l
  join public.inv_transfer t on t.id = l.transfer_id
  join public.product p on p.id = l.product_id
  left join public.ref_warehouse wf on wf.id = t.from_warehouse_id
  left join public.ref_warehouse wt on wt.id = t.to_warehouse_id
  where t.status in ('confirmed', 'at_wms', 'picking')
    and t.from_warehouse_id = p_warehouse_id
    and coalesce(p.parent_product_id, p.id) = v_pid;
  return jsonb_build_object('product_id', v_pid, 'sku', v_sku, 'warehouse_id', p_warehouse_id, 'warehouse', v_wh, 'customer_name_visible', v_sales,
                            'so', v_so, 'so_total', v_so_total, 'trf', v_trf, 'trf_total', v_trf_total);
end;
$function$;

-- ═══ stk_availability 재발행 — 원본 DB 바이트(md5 fd12bcc1280c2bc952490d240cd58f05) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1a」 주석) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.stk_availability(p_warehouse_id uuid, p_q text DEFAULT NULL::text, p_brand_id uuid DEFAULT NULL::uuid, p_category_id uuid DEFAULT NULL::uuid, p_include_zero boolean DEFAULT false, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0, p_sale_only boolean DEFAULT false, p_supplier_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(product_id uuid, sku text, name text, brand_id uuid, brand_name text, category_id uuid, category_name text, is_active boolean, on_hand numeric, sales_allocated numeric, transfer_reserved numeric, available numeric, on_order numeric, in_transit numeric, last_event_on date, matched_set_sku text, matched_set_pack_factor numeric, matched_set_count integer, sale_pct numeric, sale_conditional boolean, total bigint, by_warehouse jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff  uuid;
  v_q      text := nullif(btrim(p_q), '');
  v_limit  int  := least(greatest(coalesce(p_limit, 100), 1), 20000);                                 -- stkx-1 판정 628: 내보내기가 한 번에 전부(500 → 20000 · 재고 키 ≈ 12,400 · 화면 목록은 100 그대로)
  v_offset int  := greatest(coalesce(p_offset, 0), 0);
  v_whs    uuid[];
begin
  -- 문(판정 268) — 로그인 + 활성 직원 · 열쇠는 보지 않는다(판정 258)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  if p_warehouse_id is null then                                                           -- 판정 571 「B」 Both = 활성 창고 전부 · 평평한 열은 합 · by_warehouse 에 창고별
    select coalesce(array_agg(w.id order by w.name), '{}'::uuid[]) into v_whs from public.ref_warehouse w where w.is_active;
    if cardinality(v_whs) = 0 then raise exception 'No active warehouse — nothing was read'; end if;
  else
    if not exists (select 1 from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active) then
      raise exception 'Warehouse not found or inactive — pick an active branch';
    end if;
    v_whs := array[p_warehouse_id];
  end if;
  return query
  with whs as (select w.id, w.name from public.ref_warehouse w where w.id = any(v_whs)),
  av as (                                                                                  -- 장부 · 판매 예약 · 트랜스퍼 예약 — 식 한 곳(inv_available_base) · 창고마다 한 번(lateral)
    select x.id as wh, b.stock_pid, b.qty_ea, b.sales_alloc_ea, b.transfer_alloc_ea, b.bgrade_ea from whs x cross join lateral public.inv_available_base(x.id, null) b   -- bgr-1a: bgrade_ea
  ),
  lastev as (                                                                              -- 뷰는 warehouse(이름)로 걸러야 인덱스로 내려간다 — lateral 의 x.name 은 파라미터라 밀어넣어진다(stk-1 교훈)
    select x.id as wh, le.product_id, le.last_event_on
    from whs x cross join lateral (select b.product_id, max(b.last_event_on) as last_event_on from public.ims_inv_balance b where b.warehouse = x.name and b.product_id is not null group by 1) le
  ),
  onord as (                                                                               -- 판정 260 — 확정 발주 줄 − 확정 입고 줄 · 줄마다 0 아래는 0 · 발주의 배송 창고
    select po.ship_to_warehouse_id as wh, coalesce(pr.parent_product_id, pr.id) as stock_pid, sum(greatest(l.qty_ea - coalesce(rc.recv, 0), 0)) as ea
    from public.po po
    join public.po_line l on l.po_id = po.id
    join public.product pr on pr.id = l.product_id
    left join (select rl.po_line_id, sum(rl.qty_ea) as recv
                 from public.po_receipt_line rl join public.po_receipt r on r.id = rl.receipt_id
                where r.status = 'confirmed' group by 1) rc on rc.po_line_id = l.id
    where po.status = 'confirmed' and po.ship_to_warehouse_id = any(v_whs)
    group by 1, 2
  ),
  intr as (                                                                                -- 운송 중 — 출발했고 아직 도착 창고에 다 들어오지 않은 트랜스퍼 줄 · 도착 창고
    select t.to_warehouse_id as wh, coalesce(pr.parent_product_id, pr.id) as stock_pid,
           sum(greatest(coalesce(l.qty_sent, 0) - coalesce(l.qty_received, 0) - coalesce(l.qty_lost, 0) - coalesce(l.qty_returned, 0), 0) * l.pack_factor) as ea
    from public.inv_transfer t
    join public.inv_transfer_line l on l.transfer_id = t.id
    join public.product pr on pr.id = l.product_id
    where t.status in ('in_transit', 'receiving') and t.to_warehouse_id = any(v_whs)
    group by 1, 2
  ),
  pw as (                                                                                  -- 재고 키 × 고른 창고 — 창고별 한 줄
    select p.id as pid, x.id as wh, x.name as whname,
           coalesce(av.qty_ea, 0) as on_hand, coalesce(av.sales_alloc_ea, 0) as sales_allocated, coalesce(av.transfer_alloc_ea, 0) as transfer_reserved,
           coalesce(onord.ea, 0) as on_order, coalesce(intr.ea, 0) as in_transit, lastev.last_event_on, coalesce(av.bgrade_ea, 0) as bgrade   -- bgr-1a: B급 수량(옆 칸 · 판정 641)
    from public.product p
    cross join whs x
    left join av     on av.wh = x.id     and av.stock_pid = p.id
    left join lastev on lastev.wh = x.id and lastev.product_id = p.id
    left join onord  on onord.wh = x.id  and onord.stock_pid = p.id
    left join intr   on intr.wh = x.id   and intr.stock_pid = p.id
    where p.parent_product_id is null
  ),
  agg as (                                                                                 -- 평평한 열 = 고른 창고들의 합 · by_warehouse = 창고별(이름 순 · 한 창고면 원소 하나)
    select pw.pid,
           sum(pw.on_hand) as on_hand, sum(pw.sales_allocated) as sales_allocated, sum(pw.transfer_reserved) as transfer_reserved,
           sum(pw.on_order) as on_order, sum(pw.in_transit) as in_transit, max(pw.last_event_on) as last_event_on, sum(pw.bgrade) as bgrade,   -- bgr-1a
           jsonb_agg(jsonb_build_object('warehouse_id', pw.wh, 'warehouse', pw.whname,
                                        'on_hand', pw.on_hand, 'sales_allocated', pw.sales_allocated, 'transfer_reserved', pw.transfer_reserved,
                                        'available', pw.on_hand - pw.sales_allocated - pw.transfer_reserved,
                                        'on_order', pw.on_order, 'in_transit', pw.in_transit, 'last_event_on', pw.last_event_on, 'bgrade', pw.bgrade) order by pw.whname) as by_warehouse   -- bgr-1a: bgrade(수량만 · 판정 262 · 575)
    from pw group by pw.pid
  ),
  sale as (                                                                                -- sale-1 판정 361: 오늘 세일(so_sale_now · 식 한 곳) — 낱개 줄에 붙인다
    select z.product_id, z.best_pct, z.conditional from public.so_sale_now(null, null) z
  ),
  bc as (                                                                                  -- ⑥ 바코드 정확 일치(product_barcode · 활성) → 그 제품의 재고 키 · 여러 제품이면 전부 · 세트 바코드는 setm 에서 세트 표시
    select coalesce(s.parent_product_id, s.id) as stock_pid
    from public.product_barcode b join public.product s on s.id = b.product_id
    where v_q is not null and b.is_active and b.barcode = v_q
    group by 1
  ),
  setm as (                                                                                -- 판정 261 · 267 — 세트 sku 검색(또는 세트 바코드 정확 일치) → 낱개 줄 · 첫 세트(sku 순) + 개수
    select s.parent_product_id as stock_pid,
           (array_agg(s.sku order by s.sku))[1]         as matched_set_sku,
           (array_agg(s.pack_factor order by s.sku))[1] as matched_set_pack_factor,
           count(*)::int                                as matched_set_count
    from public.product s
    where v_q is not null and s.parent_product_id is not null
      and (s.sku ilike '%' || v_q || '%' or exists (select 1 from public.product_barcode b where b.product_id = s.id and b.is_active and b.barcode = v_q))
    group by 1
  ),
  sup as (                                                                                 -- 판정 570 「A」 — 그 공급처의 활성 줄이 있는 제품 전부(기본 아니어도) · 세트 줄은 낱개로(짐작 확인 8) · 비활성 줄 제외
    select distinct coalesce(sp.parent_product_id, sp.id) as stock_pid
    from public.product_supplier ps join public.product sp on sp.id = ps.product_id
    where p_supplier_id is not null and ps.supplier_id = p_supplier_id and ps.is_active
  ),
  rows_all as (                                                                            -- ⭐ 이 where 는 stk_value_total 의 keys 와 서로 같은 조건 — 한쪽을 고치면 다른 쪽도
    select p.id, p.sku, p.name, p.brand_id, p.brand_name, p.category_id, p.category_name, p.is_active,
           coalesce(agg.on_hand, 0)            as on_hand,
           coalesce(agg.sales_allocated, 0)    as sales_allocated,
           coalesce(agg.transfer_reserved, 0)  as transfer_reserved,
           coalesce(agg.on_hand, 0) - coalesce(agg.sales_allocated, 0) - coalesce(agg.transfer_reserved, 0) as available,
           coalesce(agg.on_order, 0)           as on_order,
           coalesce(agg.in_transit, 0)         as in_transit,
           agg.last_event_on,
           setm.matched_set_sku, setm.matched_set_pack_factor, setm.matched_set_count,
           sale.best_pct as sale_pct, sale.conditional as sale_conditional,
           coalesce(agg.bgrade, 0)             as bgrade,                                  -- bgr-1a: rows_kept 가 본다(반환 칸 아님)
           agg.by_warehouse
    from public.product p                                                                -- 줄 = 재고 키 = 낱개(세트 · 콤보 줄 없음 · 판정 261)
    left join agg    on agg.pid          = p.id
    left join setm   on setm.stock_pid   = p.id
    left join sale   on sale.product_id  = p.id
    left join bc     on bc.stock_pid     = p.id
    left join sup    on sup.stock_pid    = p.id
    where p.parent_product_id is null
      and (not p_sale_only or sale.product_id is not null)                                                             -- sale-1 판정 361: 세일 제품만
      and not exists (select 1 from public.product_bom bm where bm.parent_product_id = p.id and bm.is_active)
      and (p_brand_id is null or p.brand_id = p_brand_id)
      and (p_category_id is null or p.category_id = p_category_id)
      and (p_supplier_id is null or sup.stock_pid is not null)
      and (v_q is null or p.sku ilike '%' || v_q || '%' or p.name ilike '%' || v_q || '%' or p.brand_name ilike '%' || v_q || '%' or setm.stock_pid is not null or bc.stock_pid is not null)
  ),
  rows_kept as (
    select r.* from rows_all r
    where p_include_zero
       or r.on_hand <> 0 or r.sales_allocated <> 0 or r.transfer_reserved <> 0 or r.on_order <> 0 or r.in_transit <> 0   -- 판정 266 — 다섯 숫자(Both 는 합) 모두 0 인 줄만 뺀다
       or r.bgrade <> 0                                                                                                  -- bgr-1a 판정 637: B급만 있는 줄도 보인다
  )
  select r.id, r.sku, r.name, r.brand_id, r.brand_name, r.category_id, r.category_name, r.is_active,
         r.on_hand, r.sales_allocated, r.transfer_reserved, r.available, r.on_order, r.in_transit, r.last_event_on,
         r.matched_set_sku, r.matched_set_pack_factor, r.matched_set_count,
         r.sale_pct, r.sale_conditional,
         count(*) over () as total,
         r.by_warehouse
  from rows_kept r
  order by r.sku, r.id
  limit v_limit offset v_offset;
end;
$function$;

-- ═══ 착지 — 칸 둘 · 뷰 칸 끝 · 옵션 · ACL · 함수 몸 md5 · 창구 · 트리거 · 다른 stk_ 무변 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and ((table_name = 'ref_bin' and column_name = 'is_bgrade') or (table_name = 'so_line' and column_name = 'bgrade_bin_id'))) <> 2 then v_bad := v_bad || ' columns'; end if;
  if (select attname from pg_attribute where attrelid = 'public.ims_inv_balance'::regclass and attnum > 0 and not attisdropped order by attnum desc limit 1) <> 'bin_is_bgrade' then v_bad := v_bad || ' view_last_col'; end if;
  if (select count(*) from pg_attribute where attrelid = 'public.ims_inv_balance'::regclass and attnum > 0 and not attisdropped) <> 15 then v_bad := v_bad || ' view_cols'; end if;
  if (select coalesce(array_to_string(reloptions, ','), '-') from pg_class where oid = 'public.ims_inv_balance'::regclass) <> 'security_invoker=true' then v_bad := v_bad || ' view_options'; end if;
  if (select relacl::text from pg_class where oid = 'public.ims_inv_balance'::regclass) <> '{postgres=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' then v_bad := v_bad || ' view_acl'; end if;
  if (select pg_get_function_result(oid) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_available_base') <> 'TABLE(stock_pid uuid, qty_ea numeric, sales_alloc_ea numeric, transfer_alloc_ea numeric, bgrade_ea numeric)' then v_bad := v_bad || ' iab_result'; end if;
  if (select proacl::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_available_base') <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' iab_acl'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('ims_last_bin', 'inv_available_base', 'so_pick_plan', 'stk_availability', 'stk_reserved', 'wms_pick_line_bins_write', 'wms_pick_lines', 'wms_pick_shelf'))
     <> 'ims_last_bin=69f43ebf840752e5c8bc22ca7b27847f inv_available_base=d3f21fae0b0b5b52bdc7a69b75c3ea71 so_pick_plan=bdde73f22c0e0af219e88c0b9f53e331 stk_availability=6eda5898b7f8b8213f53eb732f38de30 stk_reserved=664db9614f046ffeb8b6dc66a09ce82a wms_pick_line_bins_write=e14562afd1e68f524ea803e768c9ae55 wms_pick_lines=f5cde8cc8c2acfc6ceea40166376e82c wms_pick_shelf=8c6f9ffdc3f90561256cba8c0a439110' then v_bad := v_bad || ' bodies'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('ims_last_bin', 'inv_available_base', 'so_pick_plan', 'stk_availability', 'stk_reserved', 'wms_pick_line_bins_write', 'wms_pick_lines', 'wms_pick_shelf')) <> 8 then v_bad := v_bad || ' overloads'; end if;
  if not has_function_privilege('authenticated', 'public.ref_bin_bgrade_set(uuid, boolean)', 'execute') or has_function_privilege('anon', 'public.ref_bin_bgrade_set(uuid, boolean)', 'execute') or has_function_privilege('service_role', 'public.ref_bin_bgrade_set(uuid, boolean)', 'execute') then v_bad := v_bad || ' window_acl'; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.ref_bin'::regclass and tgname = 'ref_bin_bgrade_guard' and not tgisinternal) then v_bad := v_bad || ' trigger'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stk_bins', 'stk_bins_many', 'stk_availability_export', 'ims_ref_name_lock'))
     <> 'ims_ref_name_lock=d376981333f0959604742f15fb1b8298 stk_availability_export=95adf4318a421c2ab5b491ce1e9e66b5 stk_bins=2b4d86b893608a999cc86dc2eeba3cec stk_bins_many=6e618902010d900ea3286b565feaef7b' then v_bad := v_bad || ' untouched_changed'; end if;
  if v_bad <> '' then raise exception 'bgr-1a landing check failed:%', v_bad; end if;
end $$;
