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

-- ─────────────────────────────────────────────────────────────
-- combo-bc-1 — 창고 읽기 창구가 구성품 줄에 「그 콤보의 바코드」 를 싣는다 (Asung-IMS · 2026-10-30 · 판정 887 · so-module §44 뒤에 적는다)
--   계기: 판정 887 Caleb — 봉한 박스(콤보 · 예 UNF18259 `810162182595`)를 박스째 스캔하면 그 콤보의 구성품 줄 수량이 채워져야 한다 · 구성품은 낱개로도 판다
--         지금은 피커 · 패커의 bcMap 이 줄마다 r.barcodes(낱개 1 + 세트 pack_factor)만 보므로 박스 바코드는 「Barcode not in this batch」
--   든 것: 재발행 하나 + CHECK 둘 + comment 하나
--     ① wms_pick_lines(bgr-1a 20261023131028 :306 ~ 446 = DB 바이트 md5 f5cde8cc8c2acfc6ceea40166376e82c) — 더한 줄만:
--        CTE cbc = 구성품 줄이 가리키는 콤보 줄(so_line combo_line_id)의 제품 바코드 · 켜진 것 · primary 먼저 · 그다음 barcode 순 · 콤보 줄마다 한 번(group) ·
--        줄 jsonb 에 'combo_barcodes' ["810162182595", …] · 구성품 줄이 아니면(보통 줄 · 트랜스퍼 갈래) [] (null 아님 — 화면이 늘 배열로 읽는다) · 픽 갈래 · 팩 갈래 둘 다
--        ⚠️ 기존 칸 · 값은 바이트 그대로 — jsonb 열쇠 순서는 jsonb 가 정한다(길이 → 바이트) · 화면은 이름으로 읽는다
--     ② verification_method CHECK 넓히기 — wms_pick_task_lines · wms_pack_task_lines 에 'scanned_combo'(박스 한 번 = 콤보 줄의 구성품 줄마다 combo_qty × pack_factor) ·
--        제약 이름 그대로 · 함수 본문에 값 목록 없음(wms_pick_line_save 는 nullif 만 · 읽는 여덟 함수는 값을 비교하지 않는다 · 리포트 셈 없음 — 실측 2026-10-30)
--        ⚠️ wms_legacy.* 의 같은 제약은 무접촉(옛 WMS 사본)
--     ③ comment on function wms_pick_lines — 옛 글 그대로 + 판정 887 한 문장
--   ⚠️ 칸 · 재고 섞임(박스 안 것과 낱개가 한 재고)은 실무 몫 — 이 차수에서 다루지 않는다 · 화면(pk · pa)은 대화 Claude 가 쓴다
--   ⚠️ 표 열 · 정책 · 권한 · 데이터 무접촉 · 새 표 · 새 FK 없음(컷오버 날 지울 것 해당 없음) · 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음
--   시험: supabase/tests/combo_bc_1_check.sql(-v mig 로 시험 · 적용 뒤 -v mig 없이 확인)
-- ─────────────────────────────────────────────────────────────

-- ═══ 무접촉 증거(적용 전 md5 · 권한 · 행 수) ═══
create temp table combobc1_before as
select (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_pick_lines') as md5_pick_lines,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_pick_line_save') as md5_line_save,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_complete_pick') as md5_complete_pick,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_complete_pack') as md5_complete_pack,
       (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname in ('wms_pick_lines', 'wms_pick_line_save', 'wms_complete_pick', 'wms_complete_pack')) as acls,
       (select count(*) from public.wms_pick_task_lines) as n_pick_lines, (select count(*) from public.wms_pack_task_lines) as n_pack_lines,
       (select count(*) from public.wms_pick_task_lines where verification_method is not null) as n_pick_vm, (select count(*) from public.wms_pack_task_lines where verification_method is not null) as n_pack_vm,
       (select count(*) from public.product_barcode) as n_barcode, (select count(*) from public.so_line) as n_so_line,
       (select obj_description(to_regprocedure('public.wms_pick_lines(bigint[], bigint)'), 'pg_proc')) as comment_pick_lines;

-- ═══ ① wms_pick_lines 재발행 — bgr-1a :306 ~ 446 바이트 그대로 + 더한 줄(줄 끝 「combo-bc-1」 주석) · 서명 · 권한 그대로(create or replace) ═══
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
  ), cbc as (                                                             -- combo-bc-1(판정 887): 구성품 줄이 가리키는 콤보 줄의 제품 바코드 — 켜진 것 · primary 먼저 · 콤보 줄마다 한 번
    select cl.id as combo_line_id,
           jsonb_agg(b.barcode order by b.is_primary desc, b.barcode) as arr
    from (select distinct pl.combo_line_id from pl where pl.combo_line_id is not null) c
    join public.so_line cl on cl.id = c.combo_line_id
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

-- ═══ ② verification_method CHECK 넓히기 — 'scanned_combo' 추가 · 제약 이름 그대로 · wms_legacy 무접촉 ═══
alter table public.wms_pick_task_lines
  drop constraint wms_pick_task_lines_verification_method_check,
  add constraint wms_pick_task_lines_verification_method_check check (verification_method in ('scanned_variant', 'scanned_base', 'manual', 'scanned_combo'));
alter table public.wms_pack_task_lines
  drop constraint wms_pack_task_lines_verification_method_check,
  add constraint wms_pack_task_lines_verification_method_check check (verification_method in ('scanned_variant', 'scanned_base', 'manual', 'scanned_combo'));

-- ═══ ③ comment — 옛 글 그대로 + 판정 887 ═══
comment on function public.wms_pick_lines(bigint[], bigint) is
  '⑤-4b 읽기 창구 — 픽 줄(과제 여럿 · 웨이브 멤버 전부) 또는 팩 줄(팩 과제 하나) + 제품 · 바코드(낱개 + 세트 factor) · 계획 칸 · 실제 칸 · 존(ref_bin.zone 우선 · 없으면 칸 이름 규칙) · 창고 가용(ims_inv_balance 합 · 한 문장) · ⊕ stock_bins(pick-bin-2 판정 122: 이 낱개 제품의 그 창고 칸 목록 — 계획 칸 전부 + 장부 qty > 0 인 활성 칸 · 계획 먼저 · 장부 내림 · 이름 · qty 는 낱개 EA · [{bin_id, bin, zone, qty, is_active, planned}]). 읽기 · stable · invoker · 창고 검사 없음(쓰기 창구가 지킨다). 사진 칸 없음(판정 33). ⊕ combo_barcodes(combo-bc-1 판정 887: 구성품 줄이면 그 콤보 줄 제품의 켜진 바코드 ["…"] · primary 먼저 · 아니면 [] — 박스 한 번 = 콤보 줄의 구성품 줄마다 combo_qty × pack_factor · verification_method scanned_combo).';

-- ═══ 착지 확인 — 설계대로 내려앉지 않았으면 전부 되돌린다 ═══
do $$
declare v_b combobc1_before%rowtype; v_bad text := ''; v_md5 text; v_src text; v_def text;
begin
  select * into v_b from combobc1_before;
  select md5(p.prosrc), p.prosrc into v_md5, v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_pick_lines';
  if v_md5 is not distinct from v_b.md5_pick_lines then v_bad := v_bad || ' pick_lines_unchanged'; end if;
  if v_src !~ $r$\), cbc as \($r$ or v_src !~ $r$jsonb_build_object\('combo_barcodes', coalesce\(cbc\.arr, '\[\]'::jsonb\)\)$r$
     or v_src !~ 'left join cbc  on cbc\.combo_line_id = pl\.combo_line_id' then v_bad := v_bad || ' pick_lines_body'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_pick_line_save', 'wms_complete_pick', 'wms_complete_pack'))
     <> 'wms_complete_pack=' || v_b.md5_complete_pack || ' wms_complete_pick=' || v_b.md5_complete_pick || ' wms_pick_line_save=' || v_b.md5_line_save then v_bad := v_bad || ' other_functions_changed'; end if;
  if (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('wms_pick_lines', 'wms_pick_line_save', 'wms_complete_pick', 'wms_complete_pack')) is distinct from v_b.acls then v_bad := v_bad || ' acl_changed'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_pick_lines') <> 1 then v_bad := v_bad || ' overloads'; end if;
  if (select provolatile::text || prosecdef::text || '/' || array_to_string(proconfig, ';') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_pick_lines') <> 'sfalse/search_path=public, pg_temp' then v_bad := v_bad || ' attrs'; end if;
  select pg_get_constraintdef(oid) into v_def from pg_constraint where conrelid = 'public.wms_pick_task_lines'::regclass and conname = 'wms_pick_task_lines_verification_method_check';
  if v_def is distinct from $c$CHECK ((verification_method = ANY (ARRAY['scanned_variant'::text, 'scanned_base'::text, 'manual'::text, 'scanned_combo'::text])))$c$ then v_bad := v_bad || ' pick_check'; end if;
  select pg_get_constraintdef(oid) into v_def from pg_constraint where conrelid = 'public.wms_pack_task_lines'::regclass and conname = 'wms_pack_task_lines_verification_method_check';
  if v_def is distinct from $c$CHECK ((verification_method = ANY (ARRAY['scanned_variant'::text, 'scanned_base'::text, 'manual'::text, 'scanned_combo'::text])))$c$ then v_bad := v_bad || ' pack_check'; end if;
  if (select count(*) from pg_constraint where conname in ('wms_pick_task_lines_verification_method_check', 'wms_pack_task_lines_verification_method_check') and connamespace = 'wms_legacy'::regnamespace
        and pg_get_constraintdef(oid) ~ 'scanned_combo') <> 0 then v_bad := v_bad || ' legacy_touched'; end if;
  if obj_description(to_regprocedure('public.wms_pick_lines(bigint[], bigint)'), 'pg_proc') !~ '판정 887'
     or obj_description(to_regprocedure('public.wms_pick_lines(bigint[], bigint)'), 'pg_proc') not like v_b.comment_pick_lines || '%' then v_bad := v_bad || ' comment'; end if;
  if (select count(*) from public.wms_pick_task_lines) <> v_b.n_pick_lines or (select count(*) from public.wms_pack_task_lines) <> v_b.n_pack_lines
     or (select count(*) from public.wms_pick_task_lines where verification_method is not null) <> v_b.n_pick_vm or (select count(*) from public.wms_pack_task_lines where verification_method is not null) <> v_b.n_pack_vm
     or (select count(*) from public.product_barcode) <> v_b.n_barcode or (select count(*) from public.so_line) <> v_b.n_so_line then v_bad := v_bad || ' data_changed'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM887', message = format('STOP - combo-bc-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
drop table combobc1_before;
