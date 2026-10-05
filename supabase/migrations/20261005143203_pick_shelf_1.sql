-- ─────────────────────────────────────────────────────────────
-- 픽 화면의 선반 기대량 읽기 창구 + 빈 계획 칸 보고 한 번만 (Asung-IMS · pick-shelf-1 · 2026-10-05)
--   정본(뒤에 적는다): so-module §40 — 판정 235(2026-10-05 Caleb 「가로 수정하자.」 · 픽 화면의 칸 옆에 선반 기대량 = 그 칸의 장부 − 집었지만 아직 출고 안 된 몫 · 표시만 · 막지 않는다 판정 123)
--                      · pick-shelf 묶음 1 ~ 5 · §30 판정 121 ~ 124 · §26 판정 62(선반 기대량 = 장부 − P) · §39-d 1(판정 값은 definer 창구 하나에서)
--   든 것: ① 읽기 창구 wms_pick_shelf(창고, 낱개 SKU 목록) — 상품마다 칸마다 book · picked · on_shelf 를 한 번에 · 피커 문(wms_pick_line_save 와 같은 첫 줄 ims_require_write('picking') + ims_can_warehouse) · definer · 쓰기 없음
--         ② wms_reports BEFORE INSERT 트리거 — 같은 문서 · sku · 계획 칸 · 찾은 칸의 열린(resolved_at null) wrong_location 보고가 있으면 거부(「already reported」) · 부분 유니크 인덱스 없음(PostgREST on_conflict 사고) · 옛 행 무접촉
--   ⭐ 입력이 SKU 인 까닭: 화면 줄(wms_pick_lines → lineFromRpc)은 product_id 를 들고 있지 않다 — sku(오더 SKU) · base_sku(낱개 SKU)뿐 · 장부 열쇠도 sku 다 · 세트 SKU 가 와도 낱개(parent)로 접는다
--   ⚠️ 기존 함수 재발행 없음 · 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 이 창구는 IMS 안에서만 선다(판정 51 · 60)
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

-- ═══ 1) 읽기 창구 — 선반 기대량 (판정 235 · 묶음 1) ═══
--   문: wms_pick_line_save 와 같은 피커 문 — 첫 줄 ims_require_write('picking', 'saved') · 둘째 ims_can_warehouse(창고) · 문장은 그 창구와 같은 모양(「— nothing was saved」)
--   book = inv_balance(그 창고 이름 · 그 칸 이름 · 낱개 sku · 칸 있는 행만 · qty ≠ 0) — inv_adjust_ledger 가 읽는 ims_inv_balance.qty 의 원문(같은 값 · 한 번에)
--   picked = inv_adjust_picked(20260928231355:1641) 와 같은 술어를 (칸, 낱개 상품) 으로 한 번에 — 완료된 픽의 실제 칸 행(planned=false) × 문서 picking · packed × 이 창고
--   on_shelf = book − picked — 판정 62 의 「선반 기대량」 · 피커가 기다리는 몫은 빼지 않는다(피커 본인이 그 몫을 뽑는 중) · 음수도 그대로(판정 123 「보이게 둔다」)
--   칸 = 장부 qty ≠ 0 인 칸 전부 ∪ 그 상품의 열린 픽 계획 칸(과제 pending · in_progress × 문서 at_wms · picking — 계획 칸이 비었어도 「on shelf 0」 이 보이게 · planned true)
--   한 번 부르기로 과제의 모든 상품을 준다 · 모르는 SKU 는 product_id null · 장부에 있으면 그 칸은 그대로(picked 0) · 막기 없음 · 쓰기 없음
create function public.wms_pick_shelf(p_warehouse_id uuid, p_skus text[]) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
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
$$;
revoke all on function public.wms_pick_shelf(uuid, text[]) from public, anon;   grant execute on function public.wms_pick_shelf(uuid, text[]) to authenticated;
comment on function public.wms_pick_shelf(uuid, text[]) is
  'pick-shelf-1 · 판정 235 — 픽 화면의 선반 기대량: (창고, 낱개 SKU 목록) → 상품마다 칸마다 book(inv_balance 그 칸) · picked(inv_adjust_picked 와 같은 술어 · 한 번에) · on_shelf = book − picked(판정 62 · 음수 그대로 · 기다리는 몫은 안 뺀다) · planned(열린 픽 계획 칸 · 장부 0 이어도 든다). 세트 SKU 는 낱개로 접는다 · 모르는 SKU 는 product_id null. 문 = wms_pick_line_save 와 같은 ims_require_write(picking) + ims_can_warehouse. stable · definer(§39-d 1) · 표시만 · 쓰기 없음. 2026-10-05';

-- ═══ 2) 빈 계획 칸 보고 한 번만 — wms_reports BEFORE INSERT (묶음 4) ═══
--   화면(wms-picker.html reportPlannedEmpty)이 wms_reports 에 직접 insert 한다(창구 아님 · 정책 auth_all) — 막는 자리는 표 쓰기 길 = 트리거
--   「열린」 = resolved_at is null(wms_reports 의 상태 칸은 resolved_at · resolved_by 뿐) · 닫힌 뒤 같은 칸이 또 비면 새 보고를 받는다
--   같은 보고 = kind wrong_location · 같은 문서(order_id · transfer_id 둘 다 is not distinct from) · 같은 sku · 같은 planned_bin · 같은 found_bin(앞뒤 공백 · 대소문자 무시)
--   planned_bin null 인 손 보고(판정 124 전 모양 · wrong_location 의 「Where did you actually find it?」)는 무접촉 · 다른 kind 무접촉 · UPDATE 무접촉
--   같은 열쇠의 동시 insert 둘은 트랜잭션 자문 잠금으로 줄 세운다(부분 유니크 인덱스 없이) · 거부된 insert 도 id 하나를 쓴다(identity 기본값이 트리거보다 먼저 · 번호가 빈다 · 판정 55 모양)
create function public.wms_reports_planned_empty_once() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare v_dup public.wms_reports%rowtype;
begin
  if new.kind <> 'wrong_location' or new.planned_bin is null then return new; end if;
  perform pg_advisory_xact_lock(hashtext('wms_reports.planned_empty:' || coalesce(new.order_id::text, new.transfer_id::text, '-') || ':' || coalesce(new.sku, '-') || ':'
                                         || upper(btrim(new.planned_bin)) || ':' || upper(btrim(coalesce(new.found_bin, '')))));
  select * into v_dup from public.wms_reports r
   where r.kind = 'wrong_location' and r.resolved_at is null and r.planned_bin is not null
     and r.order_id is not distinct from new.order_id and r.transfer_id is not distinct from new.transfer_id
     and r.sku is not distinct from new.sku
     and upper(btrim(r.planned_bin)) = upper(btrim(new.planned_bin))
     and upper(btrim(coalesce(r.found_bin, ''))) = upper(btrim(coalesce(new.found_bin, '')))
   order by r.id limit 1;
  if found then
    raise exception 'Planned bin % for % (found at %) on % was already reported — report #% is still open — nothing was saved',
      new.planned_bin, coalesce(new.sku, '?'), coalesce(new.found_bin, '?'), coalesce(new.order_number, v_dup.order_number, '?'), v_dup.id;
  end if;
  return new;
end;
$$;
create trigger wms_reports_planned_empty_once before insert on public.wms_reports for each row execute function public.wms_reports_planned_empty_once();
comment on function public.wms_reports_planned_empty_once() is
  'pick-shelf-1 · 묶음 4 — wms_reports BEFORE INSERT: kind wrong_location · planned_bin 있는 행만 · 같은 문서(order_id · transfer_id) · sku · planned_bin · found_bin(공백 · 대소문자 무시)의 열린(resolved_at null) 보고가 있으면 거부(「already reported」 · 열린 보고 번호) · 트랜잭션 자문 잠금으로 동시 insert 줄 세움 · 부분 유니크 없음 · 손 보고(planned_bin null) · 다른 kind · UPDATE 무접촉. 2026-10-05';
