-- ─────────────────────────────────────────────────────────────
-- 재고 조정 ① 느림 고치기 — 판정 54 A + B + C (Asung-IMS · adj-a2 · 2026-09-28)
--   A inv_balance 셈 모양(UNION ALL + GROUP BY · 뜻 그대로 · 마지막 정의 20260901163300:42~65) · B inv_adjust_eval materialized(20260928142722:182~211 · 바뀐 줄 1)
--   C inv_adjust_summary(새) · inv_adjust_preview · inv_adjust_detail 다시 씀(eval 한 번 · 반환 무변) · inv_adjust_confirm(20260928142722:348~375 · eval 한 번 · 바뀐 줄 8)
--   실측(조사 adj-c-slow): 한 키 잔고 108~130 ms → 0.129 ms · eval 줄 1 = 1,272 ms · 초안 3줄 detail 9,634 ms → 검증 V4 에서 다시 잰다
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · cascade 없음 · grant · 소유자 · 옵션 무변(create or replace)
-- ─────────────────────────────────────────────────────────────
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

-- ═══ A) inv_balance — 셈 모양만 다시 낸다(판정 54 A) · 마지막 정의 20260901163300:42~65 · 뜻 그대로: 기초 스냅샷(inv_config.baseline_snapshot_key) + 원장 전 행(컷오프 · source 조건 없음) ═══
--   왜: 옛 모양(집계 둘의 Full Join)은 한 키를 물어도 원장 전체를 합산했다(41,615행 Seq Scan · 108~130 ms). UNION ALL 뒤 GROUP BY 는 키 술어가 두 갈래로 내려가 인덱스로 간다(실측 0.129 ms · except 양방향 0 · 18,144 = 18,144).
--   컬럼 이름 · 순서 · 타입(text · text · text · numeric ×3) 그대로 · create or replace(grant · 소유자 · 옵션 · 의존 뷰 ims_inv_balance → ims_ledger_unlinked 무변) · 스냅샷 키가 없으면 옛 정의처럼 기초 0(원장 행만) — 서브쿼리가 null 이면 스냅샷 갈래가 0행
create or replace view public.inv_balance as
select u.sku, u.warehouse, u.bin,
       sum(u.base)                as baseline_qty,
       sum(u.delta)               as delta_qty,
       sum(u.base) + sum(u.delta) as qty
from (
  select s.sku, s.warehouse, coalesce(s.bin, '') as bin, s.qty as base, 0::numeric as delta
    from public.inv_snapshot s
   where s.snapshot_key = (select value from public.inv_config where key = 'baseline_snapshot_key')
  union all
  select l.sku, l.warehouse, coalesce(l.bin, '') as bin, 0::numeric as base, l.qty_delta as delta
    from public.inv_ledger l                       -- ⚠️ source 조건 없음(함정 1) · 컷오프 없음 — 옛 정의와 같다
) u
group by u.sku, u.warehouse, u.bin;
-- ⚠️ full join 의 뜻(기초에만 있는 것 · 원장에만 있는 것 둘 다 나온다)은 union all + group by 가 그대로 낸다.

-- ═══ C-1) 요약 조각 — eval 결과(jsonb 배열)에서 rejects · warnings 를 뽑는다 · preview · detail 이 같은 결과로 부른다(eval 한 번 · 판정 54 C) ═══
--   옛 preview 와 같은 값: rejects = 줄마다의 rejects 를 글자 순 정렬 · 줄이 없으면 'no lines' · warnings = cost_unknown(unknown 갈래 있음) · lines_without_change(delta 0 줄 있음) 이 순서
create function public.inv_adjust_summary(p_lines jsonb) returns jsonb
  language sql immutable
  set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'rejects',  coalesce((select jsonb_agg(x order by x) from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l cross join lateral jsonb_array_elements_text(l -> 'rejects') as x), '[]'::jsonb)
                || case when jsonb_array_length(coalesce(p_lines, '[]'::jsonb)) = 0 then '["no lines"]'::jsonb else '[]'::jsonb end,
    'warnings', case when exists (select 1 from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l where l ->> 'cost_branch' = 'unknown') then '["cost_unknown"]'::jsonb else '[]'::jsonb end
                || case when exists (select 1 from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l where (l ->> 'delta')::numeric = 0) then '["lines_without_change"]'::jsonb else '[]'::jsonb end);
$$;
revoke all on function public.inv_adjust_summary(jsonb) from public, anon;   grant execute on function public.inv_adjust_summary(jsonb) to authenticated;

-- ═══ C-2) preview — eval 한 번(옛 판은 네 번) · 반환 키 · 값 · 거부 문장 무변 ═══
create or replace function public.inv_adjust_preview(p_adjust_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare v_a public.inv_adjust%rowtype; v_lines jsonb; v_s jsonb;
begin
  if not public.ims_can_adjust_read() then raise exception 'You cannot view stock adjustments — this needs the stock_adjust key'; end if;
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id;
  if not found then raise exception 'Adjustment not found'; end if;
  select coalesce(jsonb_agg(to_jsonb(e) order by e.line_no), '[]'::jsonb) into v_lines from public.inv_adjust_eval(p_adjust_id) e;   -- ⭐ 한 번
  v_s := public.inv_adjust_summary(v_lines);
  return jsonb_build_object('adjust_id', v_a.id, 'adjust_number', v_a.adjust_number, 'status', v_a.status, 'warehouse', v_a.warehouse, 'posted_on', coalesce(v_a.posted_on, public.ims_today()),
                            'lines', v_lines, 'rejects', v_s -> 'rejects', 'can_confirm', v_a.status = 'draft' and jsonb_array_length(v_s -> 'rejects') = 0, 'warnings', v_s -> 'warnings');
end;
$$;

-- ═══ C-3) detail — eval 한 번(옛 판은 eval 1 + preview 4 = 5) · 반환 키 무변(header · report · lines[+product_name · ledger_rows] · preview(draft 만)) ═══
create or replace function public.inv_adjust_detail(p_adjust_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare v_a public.inv_adjust%rowtype; v_lines jsonb; v_s jsonb;
begin
  if not public.ims_can_adjust_read() then return null; end if;
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id;
  if not found then return null; end if;
  select coalesce(jsonb_agg(to_jsonb(e) order by e.line_no), '[]'::jsonb) into v_lines from public.inv_adjust_eval(p_adjust_id) e;   -- ⭐ 한 번
  v_s := public.inv_adjust_summary(v_lines);
  return jsonb_build_object(
    'header', to_jsonb(v_a) || jsonb_build_object('created_by_name', (select cb.name from public.ims_staff cb where cb.id = v_a.created_by), 'confirmed_by_name', (select fb.name from public.ims_staff fb where fb.id = v_a.confirmed_by)),
    'report', (select jsonb_build_object('id', r.id, 'order_number', r.order_number, 'sku', r.sku, 'qty_expected', r.qty_expected, 'qty_found', r.qty_found, 'note', r.note, 'resolved_at', r.resolved_at)
                 from public.wms_reports r where r.id = v_a.report_id),
    'lines', (select coalesce(jsonb_agg(l || jsonb_build_object('product_name', p.name, 'ledger_rows',
                      (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'event_type', x.event_type, 'qty_delta', x.qty_delta, 'occurred_on', x.occurred_on, 'cost', x.raw -> 'cost')), '[]'::jsonb)
                         from public.inv_ledger x where x.doc_type = 'adjustment' and x.doc_number = v_a.adjust_number and x.line_ref = l ->> 'line_id')) order by (l ->> 'line_no')::int), '[]'::jsonb)
                from jsonb_array_elements(v_lines) l join public.product p on p.id = (l ->> 'product_id')::uuid),
    'preview', case when v_a.status = 'draft' then
                 jsonb_build_object('adjust_id', v_a.id, 'adjust_number', v_a.adjust_number, 'status', v_a.status, 'warehouse', v_a.warehouse, 'posted_on', coalesce(v_a.posted_on, public.ims_today()),
                                    'rejects', v_s -> 'rejects', 'can_confirm', jsonb_array_length(v_s -> 'rejects') = 0, 'warnings', v_s -> 'warnings') end);
end;
$$;

-- ═══ B) inv_adjust_eval 재발행 — 20260928142722:182~211 바이트 그대로 · 바뀐 줄 1(x as materialized) · grant 그대로 ═══
create or replace function public.inv_adjust_eval(p_adjust_id uuid)
  returns table(line_id uuid, line_no int, product_id uuid, sku text, bin_id uuid, bin text, mode text, qty_input numeric, reason text, reason_note text, unit_cost numeric,
                seen_ledger numeric, seen_picked numeric, ledger numeric, picked numeric, basis numeric, delta numeric, result numeric,
                cost_branch text, avg_unit_cost numeric, rejects text[])
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with h as (select a.warehouse, a.warehouse_id from public.inv_adjust a where a.id = p_adjust_id),
  x as materialized (                                                                     -- adj-a2(판정 54 B): 줄마다 장부 · P · avg · 칸을 한 번만 — 인라인된 식이 참조 자리마다 다시 돌던 것(≈13회/줄)을 막는다
    select l.*, public.inv_adjust_ledger(h.warehouse, l.bin, l.sku) as ledger, public.inv_adjust_picked(h.warehouse_id, l.bin_id, l.product_id) as picked,
           (select coalesce(sum(t.rem * t.unit_cost) / nullif(sum(t.rem), 0), null)
              from (select y.unit_cost, y.qty - coalesce((select sum(c.qty) from public.inv_layer_consume c where c.layer_id = y.id), 0) as rem
                      from public.inv_layer y where y.sku = l.sku and y.warehouse = h.warehouse) t where t.rem > 0) as avg_cost,
           (select b.is_active and b.warehouse_id = h.warehouse_id from public.ref_bin b where b.id = l.bin_id) as bin_ok
      from public.inv_adjust_line l, h where l.adjust_id = p_adjust_id
  ),
  y as (select x.*, x.ledger - x.picked as basis, case when x.mode = 'set' then x.qty_input - (x.ledger - x.picked) else x.qty_input end as d from x)
  select y.id, y.line_no, y.product_id, y.sku, y.bin_id, y.bin, y.mode, y.qty_input, y.reason, y.reason_note, y.unit_cost,
         y.seen_ledger, y.seen_picked, y.ledger, y.picked, y.basis, y.d, y.ledger + y.d,
         case when y.d > 0 and y.unit_cost is not null then 'manual' when y.d > 0 and y.avg_cost is not null then 'layer_avg'
              when y.d > 0 then 'unknown' when y.d < 0 then 'fifo' else 'none' end,
         round(y.avg_cost, 6),
         array_remove(array[
           case when y.ledger + y.d < 0 then format('line %s %s %s: result would be %s (below zero)', y.line_no, y.sku, y.bin, y.ledger + y.d) end,
           case when y.ledger <> y.seen_ledger then format('line %s %s %s: ledger changed (you saw %s, it is now %s)', y.line_no, y.sku, y.bin, y.seen_ledger, y.ledger) end,
           case when y.picked <> y.seen_picked then format('line %s %s %s: picked-not-shipped changed (you saw %s, it is now %s)', y.line_no, y.sku, y.bin, y.seen_picked, y.picked) end,
           case when not coalesce(y.bin_ok, false) then format('line %s: bin %s is inactive or not in this warehouse', y.line_no, y.bin) end
         ], null)
    from y order by y.line_no;
$$;

-- ═══ C-4) inv_adjust_confirm 재발행 — 20260928142722:348~375 바이트 그대로 · 바뀐 줄 8(eval 한 번 · 선언 v_deltas) · grant · comment 그대로 ═══
create or replace function public.inv_adjust_confirm(p_adjust_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_a public.inv_adjust%rowtype; v_staff uuid; v_rej text[] := '{}'; v_on date; v_post jsonb; v_rep int := 0; v_e record; v_deltas jsonb := '{}'::jsonb;
begin
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id for update;             -- 머리 잠금 — 같은 문서 두 번 확정 방지
  if not found then raise exception 'Adjustment not found — nothing was saved'; end if;
  v_staff := public.inv_adjust_require(v_a.warehouse_id);                                   -- ⭐ 첫 줄 문
  if v_a.status <> 'draft' then raise exception 'Adjustment % is already % — nothing was saved', v_a.adjust_number, v_a.status; end if;
  if not exists (select 1 from public.inv_adjust_line l where l.adjust_id = p_adjust_id) then raise exception 'Adjustment % has no lines — nothing was saved', v_a.adjust_number; end if;
  -- 줄마다 다시 읽는다 — 음수 · 본 값 달라짐(장부 · P) · 칸 → 하나라도 막히면 전체 거부(사람 문장)
  -- adj-a2(판정 54 C): eval 한 번 — for update 뒤 읽은 그 값 하나로 거부 판정과 delta 굳힘을 같이 한다(옛 판은 두 번 읽어 둘 사이에 원장이 바뀔 수 있었다 · CAS 가 약해지지 않는다)
  for v_e in select * from public.inv_adjust_eval(p_adjust_id) loop
    v_rej := v_rej || v_e.rejects;  v_deltas := v_deltas || jsonb_build_object(v_e.line_id::text, v_e.delta);
  end loop;
  select coalesce(array_agg(x order by x), '{}') into v_rej from unnest(v_rej) as x;
  if cardinality(v_rej) > 0 then raise exception 'Adjustment % cannot be confirmed: % — reload and check the lines — nothing was saved', v_a.adjust_number, array_to_string(v_rej, '; '); end if;
  v_on := public.ims_today();
  update public.inv_adjust_line l set delta = (v_deltas ->> l.id::text)::numeric where l.adjust_id = p_adjust_id and v_deltas ? l.id::text;   -- delta 0 줄도 굳힌다(원장 행은 없다 · Cin7 규칙)
  update public.inv_adjust set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now(), posted_on = v_on, updated_by = v_staff where id = p_adjust_id;
  v_post := public.inv_post_adjust(p_adjust_id);                                            -- 원장 + 원가 레이어 · 같은 트랜잭션 · 실패하면 확정도 안 된다
  if v_a.report_id is not null then                                                         -- 묶음 9 — 열린 신고를 닫는다(이미 닫힌 것은 무변)
    update public.wms_reports set resolved_by = v_staff, resolved_at = now() where id = v_a.report_id and kind = 'stock_short' and resolved_at is null;
    get diagnostics v_rep = row_count;
  end if;
  return jsonb_build_object('adjust_id', v_a.id, 'adjust_number', v_a.adjust_number, 'status', 'confirmed', 'posted_on', v_on,
                            'ledger', v_post, 'report_id', v_a.report_id, 'report_resolved', v_rep = 1);
end;
$$;
