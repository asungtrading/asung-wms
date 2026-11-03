-- ─────────────────────────────────────────────────────────────
-- wms-balance-perf-1 ① — ims_inv_balance 뷰를 id 술어로 부르던 창고 창구를 키 잔고 함수로(Asung-IMS · 2026-11-02 밤 · 지시서 wms-balance-perf-1 §0 이견 1 ~ 7 Caleb 답 · deferred 450 · A 는 wms-complete-perf-1 7979c4f)
--   증상(20:03 UTC 리셋 뒤 pg_stat_statements): wms_pick_lines 51 회 평균 860 ~ 1,510 ms(temp 1,439 블록/호출) · so_pick_plan 14 회 1,082 ms · ims_last_bin 은 안에서 불려 통계 없음(같은 꼴).
--   범인: 뷰 ims_inv_balance 는 inv_balance(스냅샷 13,844 + 원장 97,583 행 GROUP BY) 뒤에 product · ref_warehouse · ref_bin 을 이름으로 붙인다 →
--        product_id · warehouse_id 술어는 조인 뒤 열이라 집계 안으로 못 들어간다 → 호출마다 111k 행 HashAggregate(work_mem 3.5 MB · 5 batches 디스크) 543 ms · wms_pick_lines 는 두 번(bal · sbal).
--        같은 키를 이름(sku · 창고 이름)으로 걸면 인덱스(inv_snapshot_uq · inv_ledger_sku_wh_on_idx)로 간다 — 뷰를 통해 324 제품 142 ms · 뷰 없이 직접 35 ms(뷰의 last_ev · baseline_at 은 창고 단위로 늘 다시 센다).
--   고침(결과 그대로 — 집합 무변):
--     1) 새 함수 ims_inv_balance_of(p_product_ids uuid[], p_warehouse_id uuid default null) — 뷰와 같은 열 15 개 · 같은 정의(inv_balance + product + ref_warehouse + ref_bin + 키 집합의 last_ev + baseline_at)를 키로만.
--        id → 이름 대응은 product_sku_key · ref_warehouse_name_key 유니크 · p_warehouse_id null 이면 창고 전부(product_bom_set 꼴) · 모르는 id · 빈 배열 · null 은 0 행(뷰와 같다) · sql · stable · security invoker(뷰가 security_invoker).
--     2) wms_pick_lines — bal · sbal 두 번 스캔 → kb(키 잔고 한 번 · CTE 둘이 읽어 materialize) · 술어 그대로(not bgrade · bin_id not null).
--     3) so_pick_plan — bal 의 FROM 만(제품 집합 · 문서 창고).   4) ims_last_bin — FROM 만 · where v.warehouse_id = p_warehouse_id 유지(null 이면 옛 정의처럼 0 행).
--     5) product_bom_set — 부모 장부 합 한 줄(창고 전부 · null 인자).   본문 그 밖은 DB prosrc 바이트 그대로(md5 는 각 절 머리 · 검증 E1 ~ E4 가 「태그 줄 뺀 본문 = 옛 본문에서 바뀐 줄 뺀 것」 으로 잰다).
--   마지막 정의: wms_pick_lines 20261102100000_tf_combo_1a_lines.sql · so_pick_plan · ims_last_bin 20261023131028_bgr_1a_bgrade_bins.sql · product_bom_set 20261027191301_combo_1.sql.
--   권한 그대로: 네 함수는 create or replace(acl · 소유자 · 속성 무변 — authenticated · service_role execute) · 새 함수도 같은 꼴.
--   무접촉: 뷰 ims_inv_balance · ims_ledger_unlinked · inv_balance(이견 3) · 창고 전체 꼴(inv_available_base · stk_availability — ②) · 나머지 호출자(③) · 화면(세 곳의 뷰 직접 조회는 대화 Claude · 함수가 먼저 있어야 한다).
--   틀리면: 픽 화면의 칸 목록 · 가용(available_ea) · 칸 계획 · Last bin 제안 · 콤보 부모 장부 경고 — 재고 쓰기에는 닿지 않는다(읽기 창구들). 그래서 검증은 뷰 vs 함수 집합 비교(except 양방향 0) + 옛 창구 vs 새 창구 결과 jsonb 같음.
--   적용: 두 창고가 멈춘 뒤 Caleb 이 psql -1 -f + supabase migration repair --status applied 20261102230000 · db push 금지.
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) ims_inv_balance_of — 키 집합 잔고(뷰 ims_inv_balance 와 같은 열 15 개 · 같은 정의 · 키로만) ═══
create function public.ims_inv_balance_of(p_product_ids uuid[], p_warehouse_id uuid default null)
  returns table (sku text, warehouse text, bin text, baseline_qty numeric, delta_qty numeric, qty numeric,
                 product_id uuid, warehouse_id uuid, bin_id uuid, bin_zone text, bin_is_active boolean,
                 last_event_on date, last_seen_on date, event_rows bigint, bin_is_bgrade boolean)
  language sql stable
  set search_path = public, pg_temp
as $$
  with kk as (                                                                            -- 키 → 이름(product_sku_key · ref_warehouse_name_key 유니크) · 모르는 id 는 빠진다 = 뷰에서 product_id 가 그 id 인 행이 없다
    select array_agg(p.sku) as skus from public.product p where p.id = any(coalesce(p_product_ids, '{}'::uuid[]))
  ), wh as (
    select w.name from public.ref_warehouse w where w.id = p_warehouse_id
  ), ba as (                                                                              -- 뷰의 baseline_at 그대로(기초 스냅샷 촬영일 · 토론토 날짜)
    select (max(s.taken_at) at time zone 'America/Toronto')::date as taken_on
    from public.inv_snapshot s
    where s.snapshot_key = (select c.value from public.inv_config c where c.key = 'baseline_snapshot_key')
  ), le as (                                                                              -- 뷰의 last_ev 를 키 집합만(inv_ledger_sku_wh_on_idx · sku · warehouse · coalesce(bin, ''))
    select l.sku, l.warehouse, coalesce(l.bin, '') as bin, max(l.occurred_on) as last_event_on, count(*) as event_rows
    from public.inv_ledger l
    where l.sku = any((select kk.skus from kk)::text[])
      and (p_warehouse_id is null or l.warehouse = (select wh.name from wh))
    group by l.sku, l.warehouse, coalesce(l.bin, '')
  )
  select b.sku, b.warehouse, b.bin, b.baseline_qty, b.delta_qty, b.qty,
         p.id, w.id, rb.id, rb.zone, rb.is_active,
         le.last_event_on, coalesce(le.last_event_on, ba.taken_on), coalesce(le.event_rows, 0::bigint), coalesce(rb.is_bgrade, false)
  from public.inv_balance b                                                               -- 스냅샷(baseline_snapshot_key) + 원장 전 행 · sku · warehouse · bin 합 — 키 술어가 두 갈래로 내려간다
  cross join ba
  join public.product p on p.sku = b.sku                                                  -- 뷰는 left join 이지만 product_id 로 부르면 product 있는 행만 나온다 — 같은 집합
  left join public.ref_warehouse w on w.name = b.warehouse
  left join public.ref_bin rb on rb.warehouse_id = w.id and rb.name = b.bin and b.bin <> ''
  left join le on le.sku = b.sku and le.warehouse = b.warehouse and le.bin = b.bin
  where b.sku = any((select kk.skus from kk)::text[])
    and (p_warehouse_id is null or b.warehouse = (select wh.name from wh));
$$;
revoke all on function public.ims_inv_balance_of(uuid[], uuid) from public, anon;
grant execute on function public.ims_inv_balance_of(uuid[], uuid) to authenticated, service_role;
comment on function public.ims_inv_balance_of(uuid[], uuid) is
  'wms-balance-perf-1(2026-11-02 · deferred 450) — 키 집합 잔고: 뷰 ims_inv_balance 와 같은 열 15 개 · 같은 정의(inv_balance 스냅샷 + 원장 합 · product · ref_warehouse · ref_bin · 칸의 마지막 사건 last_event_on · last_seen_on(없으면 기초 촬영일) · event_rows · bin_is_bgrade)를 제품 id 집합 × 창고 id 로만 센다. 뷰는 product_id · warehouse_id 술어를 집계 안으로 못 밀어 넣어 호출마다 장부 전체(111k 행)를 집계하고(543 ms) 이 함수는 sku · 창고 이름으로 인덱스를 탄다(324 제품 35 ms). p_warehouse_id null = 창고 전부 · 모르는 id · 빈 배열 · null = 0 행(뷰와 같다) · 창고 없는 행(warehouse_id null)은 null 인자일 때만 나온다. 호출자는 FROM 만 바꾸고 자기 술어(not bin_is_bgrade · bin_id is not null · bin_is_active · qty)를 그대로 건다. sql · stable · security invoker(뷰가 security_invoker 라 RLS 가 같다). 창고 전체 꼴(inv_available_base 의 pids null)은 이 함수의 몫이 아니다(② 에서 직접).';

-- ═══ 2) wms_pick_lines — bal · sbal 을 kb(키 잔고 한 번)에서 · 그 밖 바이트 그대로 ═══
-- 마지막 정의 md5(바꾸기 전 DB prosrc) ac211fbe7773719f87bb06bf6f309623
create or replace function public.wms_pick_lines(p_task_ids bigint[] DEFAULT NULL::bigint[], p_pack_task_id bigint DEFAULT NULL::bigint)
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
  ), kb as (                                                              -- wms-balance-perf-1(deferred 450): 키 잔고 한 번 — ims_inv_balance_of(제품 집합 × 창고 · 뷰와 같은 열 · 같은 정의) · bal · sbal 둘 다 여기서 읽는다(뷰는 id 술어를 집계 안으로 못 밀어 넣어 호출마다 장부 전체 집계 × 2)
    select v.warehouse_id, v.product_id, v.bin_id, v.qty, v.bin_is_active, v.bin_is_bgrade                                   -- wms-balance-perf-1
    from whs cross join lateral public.ims_inv_balance_of(array(select pids.stock_pid from pids), whs.location_id) v        -- wms-balance-perf-1
  ), bal as (                                                             -- 창고 전체 잔고 · 한 문장 · 한 번(속도 함정)
    select kb.warehouse_id, kb.product_id, sum(kb.qty) as qty                                                                 -- wms-balance-perf-1: kb 에서(집합 무변)
    from kb                                                                                                                    -- wms-balance-perf-1
    where not kb.bin_is_bgrade                                            -- bgr-1a 판정 635 · 641: 팔 수 있는 잔고만 · wms-balance-perf-1
    group by kb.warehouse_id, kb.product_id                                                                                    -- wms-balance-perf-1
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
    select kb.warehouse_id, kb.product_id, kb.bin_id, kb.qty, kb.bin_is_active                                               -- wms-balance-perf-1: kb 에서(집합 무변)
    from kb                                                                                                                    -- wms-balance-perf-1
    where kb.bin_id is not null                                                                                                -- wms-balance-perf-1
      and not kb.bin_is_bgrade                                            -- bgr-1a 판정 635: 픽 안내가 B급 칸으로 가지 않는다 · wms-balance-perf-1
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
  ), cbc as (                                                             -- combo-bc-1(판정 887): 구성품 줄이 가리키는 콤보 줄의 제품 바코드 — 켜진 것 · primary 먼저 · 콤보 줄마다 한 번
    select cl.id as combo_line_id,
           jsonb_agg(b.barcode order by b.is_primary desc, b.barcode) as arr
    from (select distinct pl.combo_line_id from pl where pl.combo_line_id is not null) c
    join (select sl.id, sl.product_id from public.so_line sl union all select tl.id, tl.product_id from public.inv_transfer_line tl) cl on cl.id = c.combo_line_id   -- tf-combo-1a(판정 954): 트랜스퍼 콤보 줄도(판매 · 트랜스퍼 줄 id 는 서로 다른 uuid)
    join public.product_barcode b on b.product_id = cl.product_id and b.is_active
    group by cl.id
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
           || jsonb_build_object('combo_barcodes', coalesce(cbc.arr, '[]'::jsonb))                                                -- combo-bc-1(판정 887): 박스 바코드 — 구성품 줄이 아니면 []
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
  left join cbc  on cbc.combo_line_id = pl.combo_line_id                                                                          -- combo-bc-1(판정 887)
  left join pk   on coalesce(pk.order_line_id, pk.transfer_line_id) = coalesce(pl.order_line_id, pl.transfer_line_id)
  where v_pack_id is null or pk.pack_line_id is not null;

  return v_out;
end
$function$;
comment on function public.wms_pick_lines(bigint[],bigint) is $c$⑤-4b 읽기 창구 — 픽 줄(과제 여럿 · 웨이브 멤버 전부) 또는 팩 줄(팩 과제 하나) + 제품 · 바코드(낱개 + 세트 factor) · 계획 칸 · 실제 칸 · 존(ref_bin.zone 우선 · 없으면 칸 이름 규칙) · 창고 가용(ims_inv_balance 합 · 한 문장) · ⊕ stock_bins(pick-bin-2 판정 122: 이 낱개 제품의 그 창고 칸 목록 — 계획 칸 전부 + 장부 qty > 0 인 활성 칸 · 계획 먼저 · 장부 내림 · 이름 · qty 는 낱개 EA · [{bin_id, bin, zone, qty, is_active, planned}]). 읽기 · stable · invoker · 창고 검사 없음(쓰기 창구가 지킨다). 사진 칸 없음(판정 33). ⊕ combo_barcodes(combo-bc-1 판정 887: 구성품 줄이면 그 콤보 줄 제품의 켜진 바코드 ["…"] · primary 먼저 · 아니면 [] — 박스 한 번 = 콤보 줄의 구성품 줄마다 combo_qty × pack_factor · verification_method scanned_combo). · tf-combo-1a(판정 954): combo_barcodes 는 트랜스퍼 콤보 줄(inv_transfer_line)에도 · wms-balance-perf-1(2026-11-02 · deferred 450): 잔고는 뷰 ims_inv_balance 대신 ims_inv_balance_of(키 집합 · 뷰와 같은 열 15 · 같은 정의)로 읽는다 — 집합 무변 · 뷰는 id 술어를 집계 안으로 못 밀어 넣어 호출마다 장부 전체 집계였다$c$;

-- ═══ 3) so_pick_plan — bal 을 키 잔고로 · 그 밖 바이트 그대로 ═══
-- 마지막 정의 md5(바꾸기 전 DB prosrc) bdde73f22c0e0af219e88c0b9f53e331
create or replace function public.so_pick_plan(p_so_id uuid)
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
    from public.ims_inv_balance_of(array(select pids.pid from pids), v_doc.warehouse_id) v                                  -- wms-balance-perf-1(deferred 450): 뷰 대신 키 잔고(같은 열 · 같은 정의 · 집합 무변 · 창고는 인자)
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
comment on function public.so_pick_plan(uuid) is $c$⭐ 칸 계획(§20 판정 1·2·4 · 고침 ① · ④a1) — 읽기(stable · invoker) · 줄마다 보낼 목표(qty_ordered − qty_removed)를 낱개 SKU 의 그 창고 칸 잔고(ims_inv_balance 한 번)로 나눈다. 순서: 재고 있는 평소 칸(마지막 사건 최근 · qty 큰 것 · bin 이름) → 재고 있는 보관용 칸(product_bin_overflow) → 모자란 몫은 첫 후보 칸(재고 0 이어도 · 없으면 ' · 경고 no_bins) · 세트 줄은 칸마다 정수 세트만(floor(칸 EA ÷ pack_factor)) · 같은 제품의 앞 줄이 쓴 몫을 뺀다. short_ea = 창고 전체 부족분(모든 칸 잔고 합 · 앞 줄이 쓴 EA 를 뺀 것 < 필요 EA · 원장 부족분 레이어 sale_shortfall 과 같아야 한다 · 경고 stock_short). 반환 picks 는 so_ship 의 p_picks 모양 [{line_id, bin, qty}](+from usual|overflow|fallback|none) · POS Finish 는 이대로 · counter 는 미리 채우고 사람이 바꾼다 · wms-balance-perf-1(2026-11-02 · deferred 450): 잔고는 뷰 ims_inv_balance 대신 ims_inv_balance_of(키 집합 · 뷰와 같은 열 15 · 같은 정의)로 읽는다 — 집합 무변 · 뷰는 id 술어를 집계 안으로 못 밀어 넣어 호출마다 장부 전체 집계였다$c$;

-- ═══ 4) ims_last_bin — FROM 을 키 잔고로 · 술어 그대로(warehouse_id = p_warehouse_id 유지) ═══
-- 마지막 정의 md5(바꾸기 전 DB prosrc) 69f43ebf840752e5c8bc22ca7b27847f
create or replace function public.ims_last_bin(p_product_ids uuid[], p_warehouse_id uuid)
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
    from public.ims_inv_balance_of(coalesce(p_product_ids, '{}'::uuid[]), p_warehouse_id) v                                 -- wms-balance-perf-1(deferred 450): 뷰 대신 키 잔고(같은 열 · 같은 정의 · 집합 무변)
    left join public.product_bin_overflow o on o.product_id = v.product_id and o.bin_id = v.bin_id   -- ④a1: 보관용 표시(SKU × 칸)
    where v.warehouse_id = p_warehouse_id                                                                                   -- wms-balance-perf-1: p_warehouse_id null 이면 옛 정의처럼 0 행
      and v.bin_id is not null            -- '' · 마스터에 없는 bin 은 후보 밖
      and v.bin_is_active                 -- 비활성 bin 에 놓으라고 하지 않는다
      and not v.bin_is_bgrade             -- bgr-1a(bgr-0 이견 8): 입고 · 크레딧 · 조정 칸 기본이 B급 칸으로 가지 않는다
    order by v.product_id, (o.id is null) desc, (v.qty > 0) desc, v.last_seen_on desc, v.qty desc, v.bin   -- ④a1: 보관용 아님을 맨 앞에(판정 2 · 평시 칸 먼저) · 나머지 키 그대로
  ) x;
$function$;
comment on function public.ims_last_bin(uuid[],uuid) is $c$⭐ 「그 제품이 그 창고에서 마지막으로 놓인 빈」 — 리시빙 풋어웨이의 Last bin 제안 · 크레딧 되돌려 놓을 칸 기본값(§19 ⬜4). ⭐ [2026-09-25 ④a1] 정렬 맨 앞에 「보관용 아님」(product_bin_overflow · so-module §20 판정 2) — 평시 칸을 먼저 가리킨다(재고 0 인 평소 칸 > 재고 있는 보관용 칸 · 픽 순서는 so_pick_plan 이 따로) · 시그니처·반환 모양 무변(receiving.html:285 · so_credit_issue). ⭐ 속 = 원장(ims_inv_balance · 2026-09-19 원장 이식 1차 — 종전 po_receipt_line 속을 갈아 끼웠다 · 부르는 쪽 무접촉): 1순위 지금 재고가 있는 자리(qty>0 · 마지막 사건 최근순) → 2순위 마지막으로 있던 자리(qty≤0 · 사건 있음) · 동률 qty desc, bin. 후보 밖 = bin 빈 문자열 · 마스터에 없는 bin · 비활성 bin · IN_TRANSIT(창고가 다르다). received_on = 그 빈의 마지막 사건일(사건 없으면 기초선 촬영일). 시그니처 (uuid[], uuid) → jsonb · 반환 { "<product_id>": { bin_id, bin, zone, received_on } } 무변 · 없는 제품은 키 없음 · 빈 입력 {} · 단일 값이라 캡 밖 · security invoker · stable. ⚠️ wms_sku_bins 를 읽지 않는다(원칙 1). 정본 po-module §11-i(⬜ 갱신) · wms-balance-perf-1(2026-11-02 · deferred 450): 잔고는 뷰 ims_inv_balance 대신 ims_inv_balance_of(키 집합 · 뷰와 같은 열 15 · 같은 정의)로 읽는다 — 집합 무변 · 뷰는 id 술어를 집계 안으로 못 밀어 넣어 호출마다 장부 전체 집계였다$c$;

-- ═══ 5) product_bom_set — 부모 장부 합 한 줄 · 그 밖 바이트 그대로 ═══
-- 마지막 정의 md5(바꾸기 전 DB prosrc) cc5069f1a07ca5bb45166047161faad8
create or replace function public.product_bom_set(p_parent_sku text, p_lines jsonb, p_old jsonb DEFAULT NULL::jsonb, p_commit boolean DEFAULT false, p_ack text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_keys     text[] := '{}';
  v_unacked  text[] := '{}';
  v_par      public.product%rowtype;
  v_comp     public.product%rowtype;
  v_key      text;
  v_e        jsonb;
  v_sku      text;
  v_qtxt     text;
  v_qty      numeric;
  v_seen     uuid[] := '{}';
  v_new      jsonb := '[]'::jsonb;            -- 검사를 지난 줄 [{component_id, sku, qty}]
  v_n        int := 0;
  v_cur_txt  text;                             -- 지금 켜진 줄 「sku|수량,…」(sku 순)
  v_old_txt  text;                             -- p_old 를 같은 모양으로
  v_new_txt  text;
  v_cur_n    int := 0;
  v_cin7_n   int := 0;
  v_cnt      bigint;
  v_stock    numeric;
  v_r        record;
  v_added    int := 0;  v_changed int := 0;  v_removed int := 0;  v_kept int := 0;
  v_chk      jsonb;                            -- combo-1: 도우미 product_bom_check_lines 의 반환
begin
  perform public.ims_require_write('master', 'saved');                                                              -- ⭐ 유일한 문 — 첫 줄(판정 140 · product_update 와 같다)
  v_staff := public.so_current_staff();
  v_key := 'combo:' || coalesce(trim(p_parent_sku), '');

  -- ① 부모
  if nullif(trim(p_parent_sku), '') is null then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'sku', p_parent_sku, 'code', 'parent_unknown', 'message', 'Combo SKU is missing — nothing was saved');
  else
    select * into v_par from public.product p where p.sku = trim(p_parent_sku);
    if not found then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'sku', trim(p_parent_sku), 'code', 'parent_unknown', 'message', format('SKU %s does not exist — nothing was saved', trim(p_parent_sku)));
    else
      if not v_par.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_inactive', 'sku', v_par.sku, 'code', 'parent_inactive', 'message', format('SKU %s is inactive — turn it on before making it a combo — nothing was saved', v_par.sku));
      end if;
      if v_par.parent_product_id is not null then                                                                   -- ⬜ 세트는 콤보가 못 된다 — 세트는 한 상품의 묶음 단위(pack_factor)라 구성품을 두 번 세게 된다
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_is_set', 'sku', v_par.sku, 'code', 'parent_is_set', 'message', format('SKU %s is a set (pack of %s) — a set cannot also be a combo — nothing was saved', v_par.sku, coalesce(v_par.pack_factor::text, '?')));
      end if;
      select count(*) into v_cnt from public.product_bom b where b.component_product_id = v_par.id and b.is_active;
      if v_cnt > 0 then                                                                                             -- 묶음 1: 콤보 안에 콤보는 안 된다 — 다른 콤보의 구성품인 상품은 콤보가 못 된다
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_is_component', 'sku', v_par.sku, 'code', 'parent_is_component', 'message', format('SKU %s is a component of %s other combo(s) — a combo cannot contain a combo — nothing was saved', v_par.sku, v_cnt));
      end if;
    end if;
  end if;

  -- ② 구성품 목록(전체) — 모양 · 하나씩 · combo-1: 도우미 product_bom_check_lines(product_combo_create 와 함께 쓴다 · 본문은 asm-1 :98 ~ 150 그대로)
  v_chk := public.product_bom_check_lines(v_par.id, p_parent_sku, p_lines, v_blocks, v_warns, v_keys);
  v_blocks := v_chk->'blocks';  v_warns := v_chk->'warns';  v_new := v_chk->'new';
  select coalesce(array_agg(x), '{}') into v_keys from jsonb_array_elements_text(v_chk->'keys') as x;

  if v_par.id is null then
    return jsonb_build_object('committed', false, 'parent_sku', trim(p_parent_sku), 'parent_id', null, 'changes', '[]'::jsonb, 'components', '[]'::jsonb, 'blocks', v_blocks, 'warnings', v_warns, 'unacked', '[]'::jsonb);
  end if;

  -- ③ 지금 줄 · 옛 목록 대조(화면이 본 것과 같은가) · 바뀐 것이 있는가
  select count(*), count(*) filter (where b.source = 'cin7'),
         coalesce(string_agg(c.sku || '|' || round(b.quantity, 6)::text, ',' order by c.sku), '')
    into v_cur_n, v_cin7_n, v_cur_txt
    from public.product_bom b join public.product c on c.id = b.component_product_id
   where b.parent_product_id = v_par.id and b.is_active;
  if v_cur_n = 0 and jsonb_typeof(p_lines) = 'array' and jsonb_array_length(p_lines) > 0 then                         -- combo-1 판정 817 · 819: 콤보가 아니던 SKU(풀린 콤보 포함)에 줄을 주면 이유를 묻지 않고 막는다 — 콤보는 Combos → New combo 에서만 태어난다
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_not_combo', 'sku', v_par.sku, 'code', 'parent_not_combo', 'message', format('%s is not a combo — make a new combo SKU in Combos → New combo — nothing was saved', v_par.sku));
  end if;
  select coalesce(string_agg(x->>'sku' || '|' || round((x->>'qty')::numeric, 6)::text, ',' order by x->>'sku'), '') into v_new_txt from jsonb_array_elements(v_new) x;
  if p_old is null then
    if v_cur_n > 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'sku', v_par.sku, 'code', 'old_missing', 'message', format('Combo %s: the component list the screen saw is missing — reload and try again — nothing was saved', v_par.sku));
    end if;
  elsif jsonb_typeof(p_old) <> 'array' then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'sku', v_par.sku, 'code', 'old_missing', 'message', format('Combo %s: the old component list must be a list of {sku, qty} — nothing was saved', v_par.sku));
  else
    begin
      select coalesce(string_agg(trim(x->>'sku') || '|' || round((x->>'qty')::numeric, 6)::text, ',' order by trim(x->>'sku')), '') into v_old_txt from jsonb_array_elements(p_old) x;
    exception when others then
      v_old_txt := '<unreadable>';
    end;
    if v_old_txt <> v_cur_txt then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'sku', v_par.sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the components of %s (now %s) — check again — nothing was saved', v_par.sku, case when v_cur_txt = '' then '(none)' else replace(v_cur_txt, '|', ' × ') end));
    end if;
  end if;
  if jsonb_array_length(v_blocks) = 0 and v_new_txt = v_cur_txt then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':no_change', 'sku', v_par.sku, 'code', 'no_change', 'message', format('Combo %s already has exactly these components — nothing to change — nothing was saved', v_par.sku));
  end if;

  -- ④ 알리기(ack) — 열린 오더 · 부모 장부(cin7_combo 는 combo-1 에서 뺐다)
  select count(distinct l.so_id) into v_cnt from public.so_line l join public.so s on s.id = l.so_id where l.product_id = v_par.id and s.status not in ('fulfilled', 'cancelled');
  if v_cnt > 0 then
    v_warns := v_warns || jsonb_build_object('key', v_key || ':open_orders', 'sku', v_par.sku, 'code', 'open_orders', 'message', format('%s open order(s) carry combo %s — they keep the components they were made with', v_cnt, v_par.sku));
    v_keys := array_append(v_keys, v_key || ':open_orders');
  end if;
  select coalesce(sum(b.qty), 0) into v_stock from public.ims_inv_balance_of(array[v_par.id], null) b;                      -- wms-balance-perf-1(deferred 450): 뷰 대신 키 잔고(창고 전부 · 같은 합)
  if v_stock <> 0 then
    v_warns := v_warns || jsonb_build_object('key', v_key || ':parent_stock', 'sku', v_par.sku, 'code', 'parent_stock', 'message', format('Combo %s has %s in the books — combos are not kept in stock (they are made when an order ships) — adjust it out', v_par.sku, round(v_stock)));
    v_keys := array_append(v_keys, v_key || ':parent_stock');
  end if;
  -- combo-1 판정 825: 알림 cin7_combo 삭제(Cin7 을 주체로 쓰지 않는다 · 적재는 manual 줄을 보내지 않는다 — ImsLoadProduct.gs ipr_loadBom_ :939 · :958)

  -- ⑤ 변경 목록(미리 보기에도 준다)
  for v_r in
    select coalesce(n.sku, c.sku) as sku, n.qty as new_qty, case when b.is_active then b.quantity end as old_qty, n.component_id as new_id, b.component_product_id as old_id
      from (select (x->>'component_id')::uuid as component_id, x->>'sku' as sku, (x->>'qty')::numeric as qty from jsonb_array_elements(v_new) x) n
      full join (select b.* from public.product_bom b where b.parent_product_id = v_par.id and b.is_active) b on b.component_product_id = n.component_id
      left join public.product c on c.id = b.component_product_id
     order by 1
  loop
    if v_r.old_id is null then v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'added', 'qty', v_r.new_qty, 'old_qty', null); v_added := v_added + 1;
    elsif v_r.new_id is null then v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'removed', 'qty', null, 'old_qty', v_r.old_qty); v_removed := v_removed + 1;
    elsif v_r.new_qty <> v_r.old_qty then v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'changed', 'qty', v_r.new_qty, 'old_qty', v_r.old_qty); v_changed := v_changed + 1;
    else v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'unchanged', 'qty', v_r.new_qty, 'old_qty', v_r.old_qty); v_kept := v_kept + 1;
    end if;
  end loop;

  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'parent_sku', v_par.sku, 'parent_id', v_par.id, 'changes', v_changes,
                              'components', (select coalesce(jsonb_agg(jsonb_build_object('sku', c.sku, 'qty', b.quantity) order by c.sku), '[]'::jsonb) from public.product_bom b join public.product c on c.id = b.component_product_id where b.parent_product_id = v_par.id and b.is_active),
                              'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ⑥ 저장 — 옛 줄과 새 목록을 견줘 더하기 · 수량 바꾸기 · 되살리기 · 끄기(지우지 않는다) · 손댄 줄은 source manual(판정 132 · prod-5 「IMS 가 고친 칸」 줄기)
  for v_r in select (x->>'component_id')::uuid as component_id, (x->>'qty')::numeric as qty from jsonb_array_elements(v_new) x loop
    update public.product_bom b
       set quantity = v_r.qty, is_active = true, source = 'manual', updated_by = v_staff
     where b.parent_product_id = v_par.id and b.component_product_id = v_r.component_id
       and (not b.is_active or b.quantity <> v_r.qty);                                                                   -- 그대로인 줄은 건드리지 않는다(cin7 표시도 그대로)
    if not found and not exists (select 1 from public.product_bom b where b.parent_product_id = v_par.id and b.component_product_id = v_r.component_id) then
      insert into public.product_bom (parent_product_id, component_product_id, quantity, source, is_active, updated_by)
      values (v_par.id, v_r.component_id, v_r.qty, 'manual', true, v_staff);
    end if;
  end loop;
  update public.product_bom b
     set is_active = false, source = 'manual', updated_by = v_staff
   where b.parent_product_id = v_par.id and b.is_active
     and not (b.component_product_id = any(coalesce((select array_agg((x->>'component_id')::uuid) from jsonb_array_elements(v_new) x), '{}'::uuid[])));

  return jsonb_build_object('committed', true, 'parent_sku', v_par.sku, 'parent_id', v_par.id, 'changes', v_changes,
                            'added', v_added, 'changed', v_changed, 'removed', v_removed, 'unchanged', v_kept,
                            'components', (select coalesce(jsonb_agg(jsonb_build_object('sku', c.sku, 'qty', b.quantity) order by c.sku), '[]'::jsonb) from public.product_bom b join public.product c on c.id = b.component_product_id where b.parent_product_id = v_par.id and b.is_active),
                            'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$function$;
comment on function public.product_bom_set(text,jsonb,jsonb,boolean,text[]) is $c$asm-1(판정 244 · asm 묶음 1) · combo-1(판정 817 · 819 · 825) · combo-one-1(판정 885): change the components of an existing combo — the whole component list [{sku, qty}] for one combo SKU · two or more components, or one component with qty 2 or more · a SKU that is not a combo (0 active rows · released ones too) is refused with parent_not_combo — new combos are born only in product_combo_create · p_old = the list the screen saw (changed_elsewhere when it differs) · preview with p_commit=false, save with true · blocks: parent_unknown · parent_inactive · parent_is_set · parent_is_component · parent_not_combo · lines_invalid · component_unknown · component_inactive · component_is_parent · component_is_combo · component_duplicate_in_call · quantity_invalid · component_single (one component with qty under 2) · old_missing · changed_elsewhere · no_change · warnings (ack keys combo:<sku>:<code>): component_is_set · open_orders · parent_stock · empty list = release (rows turned off, never deleted · cannot be undone) · touched rows become source manual · master only · wms-balance-perf-1(2026-11-02 · deferred 450): 잔고는 뷰 ims_inv_balance 대신 ims_inv_balance_of(키 집합 · 뷰와 같은 열 15 · 같은 정의)로 읽는다 — 집합 무변 · 뷰는 id 술어를 집계 안으로 못 밀어 넣어 호출마다 장부 전체 집계였다$c$;

-- ═══ 6) 자기 검사 — 새 함수 하나 · 권한 · 네 창구가 뷰를 더는 읽지 않는다 · 속성 · 뷰 무접촉 ═══
do $$
declare v_bad text := '';  v_n text;
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_inv_balance_of') <> 1 then v_bad := v_bad || ' helper_overloads'; end if;
  if (select prosecdef or provolatile <> 's' or prolang <> (select oid from pg_language where lanname = 'sql') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_inv_balance_of') then v_bad := v_bad || ' helper_attrs'; end if;
  if not has_function_privilege('authenticated', 'public.ims_inv_balance_of(uuid[], uuid)', 'execute') then v_bad := v_bad || ' acl_helper_authenticated'; end if;
  if not has_function_privilege('service_role', 'public.ims_inv_balance_of(uuid[], uuid)', 'execute') then v_bad := v_bad || ' acl_helper_service_role'; end if;
  if has_function_privilege('anon', 'public.ims_inv_balance_of(uuid[], uuid)', 'execute') then v_bad := v_bad || ' acl_helper_anon'; end if;
  for v_n in select proname from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'product_bom_set')
             and prosrc ~ 'public\.ims_inv_balance\M' loop
    v_bad := v_bad || ' view_still_used:' || v_n;
  end loop;
  for v_n in select proname from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'product_bom_set')
             and prosrc !~ 'public\.ims_inv_balance_of\(' loop
    v_bad := v_bad || ' helper_not_used:' || v_n;
  end loop;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'product_bom_set')) <> 4 then v_bad := v_bad || ' overloads'; end if;
  if (select string_agg(proname || ':' || provolatile::text || prosecdef::text, ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'product_bom_set'))
     <> 'ims_last_bin:sfalse product_bom_set:vtrue so_pick_plan:sfalse wms_pick_lines:sfalse' then v_bad := v_bad || ' attrs'; end if;
  if (select reloptions::text from pg_class where relname = 'ims_inv_balance' and relnamespace = 'public'::regnamespace) <> '{security_invoker=true}' then v_bad := v_bad || ' view_options'; end if;
  if v_bad <> '' then raise exception 'wms-balance-perf-1 self-check failed:%', v_bad; end if;
end $$;
-- 검증 E 상수(태그 줄을 뺀 새 본문 md5 = 옛 본문에서 바뀐 줄을 뺀 md5): wms_pick_lines=212e088d3fe40ecca388cf3995f39785 so_pick_plan=54ee22264ffb9b5bf0a4db7df8334e17 ims_last_bin=04385b1229a0df0be4ee4188ed5b65d1 product_bom_set=9c2e0e053dfe94a995675a02df66ec9b
