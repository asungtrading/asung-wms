-- ⑤-4b 읽기 창구 wms_pick_lines — 픽 · 팩 화면이 줄 · 제품 · 바코드 · 칸 · 가용을 한 번에 읽는다 (2026-09-27 UTC · 토론토 2026-09-26 밤)
-- 정본 so-module §24(판정 17 · 20 · 33 · ⑤-4 안 열셋의 ⑤) · 지시서 ~/asung/prompts/wms-5-4b.md §1-A · 시험 적용 + 검증 ~/asung/prompts/wms-5-4b-verify.sql(-v mig)
-- 대상: [테스트 · Asung-IMS] 만 — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
-- ⛔⛔ 절대 조건(Caleb 2026-09-26): 운영 WMS(asung-WMS · wms.asung.ca)는 어떤 경우에도 멈추면 안 된다.
--     첫 문장 = 운영 가드(원본 supabase/ops/guard-test-only.sql 의 글자를 그대로 복사 · 검증 G0 이 임시 파일 diff 로 같음을 잰다).
--     흔적 셋 중 하나라도 있으면 WM501 로 멈춘다(OR · fail-closed): cron.job 에 wms-poll-orders/wms-auto-hold · inv_config.db_role <> 'test' · wms_health_runs 행 > 0
-- 하는 일:
--   1. wms_pick_lines(p_task_ids bigint[] default null, p_pack_task_id bigint default null) returns jsonb — stable · invoker · authenticated · 창고 검사 없음(읽기)
--      둘 중 하나만 — 픽 갈래(과제 여럿 · 웨이브는 멤버 과제 전부) · 팩 갈래(팩 과제 하나 → 그 픽 과제의 줄을 팩 줄 기준으로 · ⑤-4c 가 쓴다 · 모양만 이 차수에)
--      줄마다 {line_id, pick_task_id, batch_label, wave_id, tote_no, order_line_id, so_id, so_number, customer_name, warehouse_id, sku, base_sku, product_name, pack_factor, is_set,
--             assigned_base, picked_base, status, verification_method, picked_by, picked_at,
--             planned_bins:[{bin, bin_id, zone, qty_base}], actual_bins:[{bin, bin_id, zone, qty_base, picked_by, picked_at}], barcodes:[{barcode, factor, sku}], available_ea}
--      팩 갈래는 여기에 pack_line_id · expected_base · verified_base · pack_status · pack_verification_method · verified_by · verified_at 을 더한다(줄은 팩 줄이 있는 것만)
--      zone = ref_bin.zone 이 있으면 그것 · 없으면 칸 이름 규칙(에드먼턴 E+존 글자 · 그 외 첫 글자 — ⑤-4a 화면 zoneOf 와 같은 규칙 · 창구에서는 여기 한 곳)
--      barcodes = 낱개 제품(factor 1) + parent 가 그 낱개인 세트들(factor = pack_factor)의 product_barcode(is_active) · available_ea = 그 창고의 ims_inv_balance 합(낱개 · 모든 칸)
--      사진 칸 없음(판정 33 · 마스터에 사진이 서면 한 칸 더한다)
-- ⚠️ 번호(SO · PO · RCV · 인보이스 · 크레딧)를 이 파일이 당기지 않는다 · 표를 만들거나 고치지 않는다 · 쓰기 없음
-- ⚠️ 속도 함정(asung-workflow §4): ims_inv_balance 는 한 문장으로 한 번 — product_id = any(배열) · warehouse_id = any(배열) (제품마다 되풀이하지 않는다 · 실측 50 제품 0.36초)

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

-- ═══ 1) wms_pick_lines — 읽기 창구 (운영 picker.html 793 wms_pick_task_lines+wms_order_lines · 853 wms_sku_bins · 863 wms_sku_snapshot · 1028 wave 줄의 자리) ═══
create function public.wms_pick_lines(p_task_ids bigint[] default null, p_pack_task_id bigint default null) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
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
    select t.id, t.batch_label, t.order_id, t.wave_id, t.tote_no,
           s.so_number, s.location_id, w.name as wh_name, c.name as customer_name
    from public.wms_pick_tasks t
    join public.so s on s.id = t.order_id
    left join public.ref_warehouse w on w.id = s.location_id
    left join public.customer c on c.id = s.customer_id
    where t.id = any(v_task_ids)
  ), pl as (
    select l.id as line_id, l.pick_task_id, l.order_line_id, l.assigned_base, l.picked_base, l.status, l.verification_method, l.picked_by, l.picked_at,
           t.order_id, t.so_number, t.customer_name, t.location_id, t.wh_name, t.batch_label, t.wave_id, t.tote_no,
           x.sku, x.product_name, x.pack_factor,
           coalesce(p.parent_product_id, p.id) as stock_pid, (p.parent_product_id is not null) as is_set
    from public.wms_pick_task_lines l
    join t on t.id = l.pick_task_id
    join public.so_line x on x.id = l.order_line_id
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
  ), pk as (                                                              -- 팩 갈래 — 팩 줄(order_line_id 로 짝)
    select k.id as pack_line_id, k.order_line_id, k.expected_base, k.verified_base, k.status as pack_status,
           k.verification_method as pack_verification_method, k.verified_by, k.verified_at
    from public.wms_pack_task_lines k
    where v_pack_id is not null and k.pack_task_id = v_pack_id
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'line_id', case when v_pack_id is null then pl.line_id else pk.pack_line_id end,
             'pick_line_id', pl.line_id,
             'pick_task_id', pl.pick_task_id, 'batch_label', pl.batch_label, 'wave_id', pl.wave_id, 'tote_no', pl.tote_no,
             'order_line_id', pl.order_line_id, 'so_id', pl.order_id, 'so_number', pl.so_number, 'customer_name', pl.customer_name, 'warehouse_id', pl.location_id,
             'sku', pl.sku, 'base_sku', sp.sku, 'product_name', pl.product_name, 'pack_factor', pl.pack_factor, 'is_set', pl.is_set,
             'assigned_base', pl.assigned_base, 'picked_base', pl.picked_base,
             'status', case when v_pack_id is null then pl.status else pk.pack_status end,
             'verification_method', case when v_pack_id is null then pl.verification_method else pk.pack_verification_method end,
             'picked_by', pl.picked_by, 'picked_at', pl.picked_at,
             'planned_bins', coalesce(bp.arr, '[]'::jsonb), 'actual_bins', coalesce(ba.arr, '[]'::jsonb),
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
  left join pk   on pk.order_line_id = pl.order_line_id
  where v_pack_id is null or pk.pack_line_id is not null;

  return v_out;
end
$$;
comment on function public.wms_pick_lines(bigint[], bigint) is
  '⑤-4b 읽기 창구 — 픽 줄(과제 여럿 · 웨이브 멤버 전부) 또는 팩 줄(팩 과제 하나) + 제품 · 바코드(낱개 + 세트 factor) · 계획 칸 · 실제 칸 · 존(ref_bin.zone 우선 · 없으면 칸 이름 규칙) · 창고 가용(ims_inv_balance 합 · 한 문장). 읽기 · stable · invoker · 창고 검사 없음(쓰기 창구가 지킨다). 사진 칸 없음(판정 33).';
revoke all on function public.wms_pick_lines(bigint[], bigint) from public, anon;
grant execute on function public.wms_pick_lines(bigint[], bigint) to authenticated;
