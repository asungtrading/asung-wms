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

-- nb-2 — 칸 없는 판매 막기: 지점마다 확인 칸 UNASSIGNED · pos · counter 의 대체 칸 · counter 빈칸 거부
--   (판정 1172 · 1173 · 1174 · 1175 · deferred 526 · so-module §112-g · 2026-11-11 · 지시서 ~/asung/prompts/nb-2.md)
--   왜: 그 창고에 그 SKU 의 활성 칸 행이 없으면 so_pick_plan 이 칸 '' 를 내고(POS Finish 가 그대로 출고) · counter 창에서 bin 칸을 비우면 so_ship 이 '' 를 받는다
--       → 원장에 「칸 없음」 음수가 서고, 조정 창구(inv_adjust_line_set)는 활성 칸이 있어야 해서 화면으로 못 고친다(실물 EDM EZB70340 −1 · SO-21090 · pos)
--   무엇:
--     ① ref_bin 에 판매 창고 둘(Asung Trading Inc. · Asung - Edmonton) 각각 활성 칸 UNASSIGNED 한 행(source manual · is_staging false · is_bgrade false · zone null · 멱등)
--     ② ref_bin_unassigned_guard — UNASSIGNED 는 끄기 · B급 표시 · 지우기 거부(이름 · 창고 바꾸기는 ref_bin_name_lock 이 이미 막는다)
--     ③ so_pick_plan 재발행 — (판정 1175) UNASSIGNED 는 어느 길에서도 후보 칸이 아니다 · 활성 후보 칸이 하나도 없을 때만 대체 칸
--                              (판정 1174) 대체는 채널 pos · counter 에만 — from 'unassigned' · 경고 unassigned_bin:<SKU> · 창고 오더 · 트랜스퍼는 지금 그대로('' · from none · 경고 no_bins)
--                              UNASSIGNED 행이 없는 창고는 지금 그대로('' · no_bins · 판매는 막지 않는다)
--     ④ so_counter_ship 재발행 — 사람이 준 픽의 칸이 비었으면(null · 빈 글 · 공백) 거부 「Pick a bin for line N (SKU) — nothing was saved」 · 미리 보기 · 실행 둘 다 · UNASSIGNED 를 고르는 것은 허용
--   재발행 둘의 몸 = DB prosrc 원본(2026-11-11 · so_pick_plan 95a4a177 = 20261102230000 wms-balance-perf-1 · so_counter_ship 40bc5cd4 = 20260925142307 so-pos-a2) + 고친 자리(-- nb-2 표지)만
--   무접촉: so_ship · so_pos_complete · so_pos_finish · so_finalize · inv_post_sale · wms_pick_task_build · wms_pick_line_bins_write · ims_inv_balance(_of) · ims_last_bin(UNASSIGNED 가 입고 · 조정 칸 기본으로 뜰 수 있다 — nb-4 목록)
--            · nb-1 의 함수(inv_layer_post_adjust · inv_adjust_eval · 재생성 · 하루 원가 장) · 화면 0 · 이미 있는 원장 행 0(EZB70340 정리는 nb-5)

-- ═══ ⓪ 재발행 원본 가드 — DB 의 prosrc md5 가 지은 바탕과 같아야 한다 ═══
do $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.so_pick_plan(uuid)'::regprocedure) is distinct from '95a4a177e3ee0a9134ed93b68ca78698' then
    raise exception 'nb-2 ⓪ so_pick_plan differs from what this migration was built on — rebuild from the current body first — nothing was changed';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.so_counter_ship(uuid, jsonb, boolean)'::regprocedure) is distinct from '40bc5cd42bedcfa0434f873905089dae' then
    raise exception 'nb-2 ⓪ so_counter_ship differs from what this migration was built on — rebuild from the current body first — nothing was changed';
  end if;
  if (select count(*) from public.ref_warehouse w where w.name in ('Asung Trading Inc.', 'Asung - Edmonton') and w.is_active) <> 2 then
    raise exception 'nb-2 ⓪ the two selling warehouses (Asung Trading Inc. · Asung - Edmonton) are not both present and active — nothing was changed';
  end if;
  if exists (select 1 from public.ref_bin b where upper(btrim(b.name)) = 'UNASSIGNED' and (b.name <> 'UNASSIGNED' or not b.is_active or b.is_bgrade)) then
    raise exception 'nb-2 ⓪ a bin named like UNASSIGNED already exists in another spelling, switched off or B-grade — look at it first — nothing was changed';
  end if;
end $$;

-- ═══ ① 칸 — 판매 창고마다 UNASSIGNED 하나(다시 돌려도 하나) ═══
insert into public.ref_bin (name, warehouse_id, source, is_active, is_staging, is_bgrade, zone, note)
select 'UNASSIGNED', w.id, 'manual', true, false, false, null,
       'Not a real shelf — POS and counter sales land here when the product has no bin in this warehouse yet. Count the product and move it to its real bin (nb-2).'
  from public.ref_warehouse w
 where w.name in ('Asung Trading Inc.', 'Asung - Edmonton') and w.is_active
on conflict (warehouse_id, name) do nothing;

-- ═══ ② 가드 — UNASSIGNED 는 판매가 기대는 칸: 끄기 · B급 표시 · 지우기 거부 ═══
create or replace function public.ref_bin_unassigned_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  -- nb-2(판정 1172 · 1173): 이름 · 창고 바꾸기는 ref_bin_name_lock 이 막는다 — 여기는 끄기 · B급 · 지우기
  if tg_op = 'DELETE' then
    if old.name = 'UNASSIGNED' then
      raise exception 'UNASSIGNED is the bin POS and counter sales fall back on — it cannot be deleted — nothing was saved';
    end if;
    return old;
  end if;
  if new.name = 'UNASSIGNED' and (not new.is_active or new.is_bgrade) then
    raise exception 'UNASSIGNED is the bin POS and counter sales fall back on — it cannot be switched off or marked B-grade — nothing was saved';
  end if;
  return new;
end $$;
comment on function public.ref_bin_unassigned_guard() is 'nb-2(판정 1172 · 1173 · 2026-11-11) — ref_bin 의 UNASSIGNED(지점마다 하나 · 칸 없는 pos · counter 판매의 대체 칸)는 끄기 · B급 표시 · 지우기 거부 · 이름 · 창고 바꾸기는 ims_ref_name_lock';
revoke all on function public.ref_bin_unassigned_guard() from public, anon, authenticated;
drop trigger if exists ref_bin_unassigned_guard on public.ref_bin;
create trigger ref_bin_unassigned_guard before insert or update or delete on public.ref_bin
  for each row execute function public.ref_bin_unassigned_guard();

-- ═══ ③ so_pick_plan — UNASSIGNED 는 후보가 아니다(1175) · 후보가 없으면 pos · counter 만 UNASSIGNED(1174) ═══
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
  v_ua_id    uuid;                     -- nb-2(판정 1175): 이 창고의 확인 칸 UNASSIGNED(활성) — 어느 길에서도 후보 칸이 아니다
  v_ua       text;                     -- nb-2(판정 1174): 대체 칸 이름 — pos · counter 오더에만(창고 오더 · 트랜스퍼는 null = 지금 그대로)
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
  select rb.id into v_ua_id from public.ref_bin rb where rb.warehouse_id = v_doc.warehouse_id and rb.name = 'UNASSIGNED' and rb.is_active;   -- nb-2: 없으면 null(그 창고는 지금 그대로 '' · no_bins)
  if v_ua_id is not null and v_doc.channel in ('pos', 'counter') then v_ua := 'UNASSIGNED'; end if;                                          -- nb-2(판정 1174)

  -- 칸 잔고 한 문장(ims_inv_balance 를 한 번) — 후보(활성 칸 · bin 있음)는 순서를 붙여 · 창고 전체 잔고는 모든 행
  with pids as (
    select distinct x.stock_product_id as pid
    from public.wms_order_doc_line x where x.doc_id = p_so_id
  ), bal as (
    select v.product_id, v.bin_id, v.bin, v.qty, v.bin_is_active, v.last_seen_on, v.bin_is_bgrade                         -- bgr-1a: B급 칸 표시를 함께
    from public.ims_inv_balance_of(array(select pids.pid from pids), v_doc.warehouse_id) v                                  -- wms-balance-perf-1(deferred 450): 뷰 대신 키 잔고(같은 열 · 같은 정의 · 집합 무변 · 창고는 인자)
  ), cand as (
    select b.product_id, b.bin_id, b.bin, b.qty, (o.id is not null) as ovf, b.last_seen_on, b.bin_is_bgrade as bg,      -- bgr-1a
           case when b.qty > 0 and o.id is null then 1 when b.qty > 0 then 2 when o.id is null then 3 else 4 end as rank   -- 재고 있는 평소 → 재고 있는 보관용 → 빈 평소 → 빈 보관용
    from bal b left join public.product_bin_overflow o on o.product_id = b.product_id and o.bin_id = b.bin_id
    where b.bin_id is not null and b.bin_is_active
      and b.bin_id is distinct from v_ua_id                                                                                 -- nb-2(판정 1175): UNASSIGNED 는 후보가 아니다 — 진짜 칸 행이 있으면(0 이어도) 진짜 칸이 먼저
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
      v_lp := v_lp || jsonb_build_object('line_id', l.id, 'bin', coalesce(v_first, v_ua, ''), 'qty', v_rem, 'from', case when v_first is not null then 'fallback' when v_ua is not null then 'unassigned' else 'none' end);   -- nb-2: 후보가 없으면 pos · counter 는 UNASSIGNED
      if v_first is not null then
        v_key := l.pid::text || '|' || (v_arr->0->>'bin_id');
        v_taken := jsonb_set(v_taken, array[v_key], to_jsonb(coalesce((v_taken->>v_key)::numeric, 0) + v_rem * l.pack_factor));
      elsif v_ua is not null then                                                                                           -- nb-2(판정 1172 · 1175)
        v_warn := array_append(v_warn, 'unassigned_bin:' || l.sku);
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
$function$
;

-- ═══ ④ so_counter_ship — 준 픽의 빈 칸 거부(R3) ═══
CREATE OR REPLACE FUNCTION public.so_counter_ship(p_so_id uuid, p_picks jsonb DEFAULT NULL::jsonb, p_commit boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff uuid;
  v_ch    text;
  v_bad   text;                                                -- nb-2 R3
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — counter 는 manager 이상(6-b · 판정 12)
  v_staff := public.so_current_staff();
  select s.channel into v_ch from public.so s where s.id = p_so_id;
  if v_ch is null then raise exception 'Order not found — nothing was saved'; end if;
  if v_ch <> 'counter' then raise exception 'Order is a % order — counter shipping is for counter orders (pos: so_pos_finish · warehouse: so_finalize) — nothing was saved', v_ch; end if;
  -- nb-2 R3(2026-11-11): 사람이 준 픽에 칸이 비었으면(null · 빈 글 · 공백) 거부 — 미리 보기 · 실행 둘 다 · 실물 위치를 모르면 UNASSIGNED 를 고른다
  if jsonb_typeof(p_picks) = 'array' then
    select format('line %s (%s)', coalesce(l.line_no::text, '?'), coalesce(l.sku, '?')) into v_bad
      from jsonb_array_elements(p_picks) with ordinality e(x, n)
      left join public.so_line l on l.so_id = p_so_id and l.id::text = e.x->>'line_id'
     where coalesce(e.x->>'bin', '') !~ '\S'
     order by l.line_no nulls last, e.n limit 1;
    if v_bad is not null then raise exception 'Pick a bin for % — nothing was saved', v_bad; end if;
  end if;
  return public.so_pos_complete(p_so_id, p_picks, v_staff, p_commit);
end;
$function$
;

do $$
begin
  execute format('comment on function public.so_pick_plan(uuid) is %L',
    'nb-2(판정 1172 ~ 1175 · 2026-11-11) — 이 창고의 활성 칸 UNASSIGNED 는 후보 칸이 아니다(어느 길에서도) · 활성 후보 칸이 하나도 없으면 pos · counter 오더는 UNASSIGNED 로(from unassigned · 경고 unassigned_bin:<SKU>) · 창고 오더 · 트랜스퍼 · UNASSIGNED 행이 없는 창고는 그대로('' · from none · 경고 no_bins) · 앞: '
    || coalesce(obj_description('public.so_pick_plan(uuid)'::regprocedure, 'pg_proc'), ''));
  execute format('comment on function public.so_counter_ship(uuid, jsonb, boolean) is %L',
    'nb-2 R3(2026-11-11) — 준 픽의 칸이 비었으면(null · 빈 글 · 공백) 거부 「Pick a bin for line N (SKU)」 · 미리 보기 · 실행 둘 다 · UNASSIGNED 는 허용 · 앞: '
    || coalesce(obj_description('public.so_counter_ship(uuid, jsonb, boolean)'::regprocedure, 'pg_proc'), ''));
end $$;

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_plan text; v_cs text; v_bad text := '';
begin
  select prosrc into v_plan from pg_proc where oid = 'public.so_pick_plan(uuid)'::regprocedure;
  select prosrc into v_cs   from pg_proc where oid = 'public.so_counter_ship(uuid, jsonb, boolean)'::regprocedure;
  if (select count(*) from public.ref_bin b join public.ref_warehouse w on w.id = b.warehouse_id
       where b.name = 'UNASSIGNED' and b.is_active and not b.is_bgrade and not b.is_staging and b.source = 'manual' and b.zone is null
         and w.name in ('Asung Trading Inc.', 'Asung - Edmonton')) <> 2 then v_bad := v_bad || ' bins_not_2'; end if;
  if (select count(*) from public.ref_bin b where upper(btrim(b.name)) = 'UNASSIGNED') <> 2 then v_bad := v_bad || ' bins_extra'; end if;
  if (select count(*) from pg_trigger t where t.tgrelid = 'public.ref_bin'::regclass and t.tgname = 'ref_bin_unassigned_guard' and not t.tgisinternal and t.tgenabled = 'O') <> 1 then v_bad := v_bad || ' trigger'; end if;
  if v_plan !~ 'b\.bin_id is distinct from v_ua_id' or v_plan !~ 'v_doc\.channel in \(''pos'', ''counter''\)' or v_plan !~ 'coalesce\(v_first, v_ua, ''''\)' or v_plan !~ 'unassigned_bin:' then v_bad := v_bad || ' plan_keys'; end if;
  if v_plan !~ 'ims_inv_balance_of' or v_plan !~ 'no_bins:' or v_plan !~ 'stock_short:' or v_plan !~ 'bgr-1a' then v_bad := v_bad || ' plan_body_lost'; end if;
  if v_cs !~ 'Pick a bin for %' or v_cs !~ 'so_require_role\(''manager'', ''saved''\)' or v_cs !~ 'so_pos_complete\(p_so_id, p_picks, v_staff, p_commit\)' then v_bad := v_bad || ' counter_keys'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_pick_plan', 'so_counter_ship')) <> 2 then v_bad := v_bad || ' overloads'; end if;
  if (select prosecdef from pg_proc where oid = 'public.so_pick_plan(uuid)'::regprocedure) or (select provolatile from pg_proc where oid = 'public.so_pick_plan(uuid)'::regprocedure) <> 's' then v_bad := v_bad || ' plan_kind'; end if;
  if not (select prosecdef from pg_proc where oid = 'public.so_counter_ship(uuid, jsonb, boolean)'::regprocedure) then v_bad := v_bad || ' counter_not_definer'; end if;
  if coalesce((select proacl::text from pg_proc where oid = 'public.so_pick_plan(uuid)'::regprocedure), '') <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' plan_acl'; end if;
  if coalesce((select proacl::text from pg_proc where oid = 'public.so_counter_ship(uuid, jsonb, boolean)'::regprocedure), '') <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' counter_acl'; end if;
  if v_bad <> '' then raise exception 'nb-2 landing check failed:%', v_bad; end if;
end $$;
