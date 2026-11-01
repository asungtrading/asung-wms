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

-- ═══ cost-fix-1 — 기초 시점 이동 중 트랜스퍼(TR-03975 · TR-03976) 도착 레이어 원가 0 바로잡기 (2026-11-01 · 판정 932 · cost-gap-0 조사 · cost-fix-1 이견 1 ~ 6) ═══
--   결함: 기초 스냅샷(08-20)에 IN_TRANSIT 행이 없어 08-26 도착 레이어 259 개(2,559 개)가 부모 없이 unknown 0 으로 섰고, 자식(Cin7 축 트랜스퍼 526 레이어)도 0 을 물려받았다.
--   처방(판정 932 가): 재생성 없이 「원가 조정 사건」으로 얹는다 — 남은 몫은 레이어에 · 팔린 몫은 cost_late(한 kind · 한 번의 적용) · 자식은 settle · carry 가 닿는다(어느 축이든 · 판정 110).
--   ① inv_cost_adjust: target_type 'layer' + 자연키 칸 넷(layer_doc_number · layer_line_ref · layer_sku · layer_warehouse) — 레이어 id 는 재생성이 바꾸므로 자연키로만 가리킨다(뿌리 259 의 line_ref = 원장 transfer_in line_ref · 자연키 하나 = 레이어 하나 실측) · kind 'opening_fix'(두 CHECK) · opening_fix 는 layer 대상만.
--   ② inv_layer_post_opening_fix(새) — layer 대상 얹기 창구: 레이어 하나 · 전액(비례 없음 · 기준 0 거부 없음) · 멱등 키 adj:<id> · settle · 실시간 자리(posted_on · posted_ledger_id) — inv_layer_post_cost_adjust 와 같은 규약.
--   ③ inv_layer_post_cost_adjust(재발행 · +3 줄) — layer 대상은 ②로 위임(재생성 flush · 되돌림이 부르는 자리가 그대로 맞는다).
--   ④ inv_layer_apply_flush_adds(재발행 · +18 줄) — 조정 루프의 안전띠(:711~716)는 po_line · charge_alloc 만 알아 layer 대상이 영원히 deferred 된다 → 앞에 layer 갈래 블록(자연키 레이어가 섰나 · 같은 done · 창구 · 집계 · continue).
--   ⑤ inv_cost_adjust_reverse(재발행 · +9 줄 · create → create or replace 한 줄) — layer 대상 되돌림은 자연키 칸 넷을 복사(target_pair_ck).
--   ⑥ inv_cost_fix_opening_transfer(새) — 적용 창구: 부모 없는 unknown 0 도착 레이어마다 사건 하나 · 단가 = 다른 실제 창고 기초(토론토) → 같은 창고 기초 → inv_cost 최근 양수 단가 → compare 스냅샷 단가(이견 2) · 금액은 inv_layer(기초)에서 계산(손으로 적은 숫자 없음) · 멱등(되돌려지지 않은 사건이 있으면 건너뜀) · p_dry · 반환에 SKU 별 단가 · 갈래 · 합계(남은 / 나간).
--   무접촉: inv_layer_cost_add_settle · inv_layer_carry · inv_layer_value · inv_layer_fifo_take · inv_layer_apply 본체(prosrc md5 그대로 — 검증 U1) · 8 ~ 10 월 판매 원가(sale_out 소비 금액) · 원장 수량(IN_TRANSIT 영구 음수 그대로) · 운임 627.95(deferred 430) · 판단 불가 넷(PO-01381 WEL04774 · CR-00592 · CR-00706 · ST-01422).
--   REST: 새 창구 둘 · 위임 창구는 authenticated · anon EXECUTE 없음(postgres · service_role 만) — 화면 · EF 호출 0(검증 보고). inv_cost_adjust_reverse 는 원래대로 authenticated(purchasing 문 안).
--   QBO(이견 6 · 코드 없음): 이 사건의 원가는 Cin7 이 이미 QuickBooks 로 보낸 판매의 것 — 가르는 열쇠 = inv_layer_consume.line_ref like 'adj:%' → inv_cost_adjust.kind = 'opening_fix'(뿌리 cost_late 의 split_basis.kind 도 opening_fix · 자식 cost_late 는 kind carried 라 line_ref 로만 가른다).

-- ── 1) inv_cost_adjust — 자연키 칸 넷 · CHECK 셋 다시 · opening_fix ⇒ layer ──
alter table public.inv_cost_adjust
  add column layer_doc_number text,
  add column layer_line_ref   text,
  add column layer_sku        text,
  add column layer_warehouse  text;
comment on column public.inv_cost_adjust.layer_doc_number is 'cost-fix-1 · target_type layer 의 대상 레이어 자연키(inv_layer.doc_number) — 레이어 id 는 재생성이 바꾸므로 자연키 넷으로만 가리킨다';
comment on column public.inv_cost_adjust.layer_line_ref   is 'cost-fix-1 · 대상 레이어 자연키(inv_layer.line_ref)';
comment on column public.inv_cost_adjust.layer_sku        is 'cost-fix-1 · 대상 레이어 자연키(inv_layer.sku)';
comment on column public.inv_cost_adjust.layer_warehouse  is 'cost-fix-1 · 대상 레이어 자연키(inv_layer.warehouse)';

alter table public.inv_cost_adjust drop constraint inv_cost_adjust_kind_ck;
alter table public.inv_cost_adjust add constraint inv_cost_adjust_kind_ck check (kind in ('price_adjust', 'settlement_discount', 'opening_fix'));
alter table public.inv_cost_adjust drop constraint inv_cost_adjust_target_ck;
alter table public.inv_cost_adjust add constraint inv_cost_adjust_target_ck check (target_type in ('po_line', 'charge_alloc', 'layer'));
alter table public.inv_cost_adjust drop constraint inv_cost_adjust_target_pair_ck;
alter table public.inv_cost_adjust add constraint inv_cost_adjust_target_pair_ck check (
      ((target_type = 'po_line')      = (po_line_id is not null))
  and ((target_type = 'charge_alloc') = (po_charge_alloc_id is not null))
  and ((target_type = 'layer')        = (layer_doc_number is not null and layer_line_ref is not null and layer_sku is not null and layer_warehouse is not null)));
alter table public.inv_cost_adjust add constraint inv_cost_adjust_opening_fix_ck check (kind <> 'opening_fix' or target_type = 'layer');

alter table public.inv_layer_cost_add drop constraint inv_layer_cost_add_kind_ck;
alter table public.inv_layer_cost_add add constraint inv_layer_cost_add_kind_ck check (kind in ('landed', 'transfer_freight', 'carried', 'price_adjust', 'settlement_discount', 'opening_fix'));

-- ── 2) inv_layer_post_opening_fix — layer 대상 얹기 창구(inv_layer_post_cost_adjust 20261020143921:417 의 규약 그대로 · 레이어 하나 · 전액) ──
create or replace function public.inv_layer_post_opening_fix(p_adjust_id uuid, p_on date default null) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version   constant text := 'inv_layer_post_opening_fix@2026-11-01.1';
  v_j         public.inv_cost_adjust%rowtype;
  v_lay       record;
  v_n_layers  int;
  v_aid       bigint;
  v_sub       jsonb;
  v_on        date := coalesce(p_on, public.ims_today());
  v_maxid     bigint;
begin
  -- 문 — inv_layer_post_cost_adjust 와 같다(purchasing · receiving · wms_receiving_confirm · 재생성 로그인)
  if not (public.ims_can_write('purchasing') or public.ims_can_write('receiving') or public.ims_can_write('wms_receiving_confirm')) then
    perform public.ims_require_write('purchasing', 'posted');
  end if;

  select * into v_j from public.inv_cost_adjust where id = p_adjust_id for update;
  if not found then raise exception 'Cost adjustment % not found — no cost was changed', p_adjust_id; end if;
  if v_j.target_type <> 'layer' then
    raise exception 'Cost adjustment % targets % — inv_layer_post_opening_fix is for layer targets only (use inv_layer_post_cost_adjust) — no cost was changed', v_j.source_number, v_j.target_type;
  end if;
  -- 멱등 — 실시간: 이미 posted 면 0 줄 · 재생성: posted 사건만 받고 이 사건의 얹기 줄이 이미 있으면 0 줄
  if p_on is null and v_j.status = 'posted' then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'already_posted', 'layers', 0, 'posted_cad', 0, 'posted_on', v_j.posted_on, 'builder', c_version);
  end if;
  if p_on is not null and v_j.status <> 'posted' then
    raise exception 'Cost adjustment % is still pending — regeneration replays posted adjustments only — no cost was changed', v_j.source_number;
  end if;
  if exists (select 1 from public.inv_layer_cost_add ca where ca.line_ref = 'adj:' || v_j.id::text) then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'already_posted', 'layers', 0, 'posted_cad', 0, 'posted_on', v_j.posted_on, 'builder', c_version);
  end if;

  -- 대상 — 자연키 넷으로 레이어 하나(쌍둥이면 거부 · 아직 없으면 no_layers — 재생성 안전띠가 그 전에 미룬다)
  select count(*) into v_n_layers from public.inv_layer x
   where x.doc_number = v_j.layer_doc_number and x.line_ref = v_j.layer_line_ref and x.sku = v_j.layer_sku and x.warehouse = v_j.layer_warehouse;
  if v_n_layers = 0 then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'no_layers', 'layers', 0, 'basis', 0, 'posted_cad', 0, 'amount_cad', v_j.amount_cad, 'builder', c_version);
  end if;
  if v_n_layers > 1 then
    raise exception 'Cost adjustment % names % layers (% · % · % · %) — a layer target must name exactly one layer — no cost was changed',
      v_j.source_number, v_n_layers, v_j.layer_doc_number, v_j.layer_line_ref, v_j.layer_sku, v_j.layer_warehouse;
  end if;
  select x.id, x.sku, x.warehouse, x.doc_number, x.line_ref, x.qty, x.unit_cost, x.unit_cost * x.qty as basis,
         coalesce((select sum(ca.amount) from public.inv_layer_cost_add ca where ca.layer_id = x.id), 0) as adds
    into v_lay
    from public.inv_layer x
   where x.doc_number = v_j.layer_doc_number and x.line_ref = v_j.layer_line_ref and x.sku = v_j.layer_sku and x.warehouse = v_j.layer_warehouse;
  if v_lay.basis + v_lay.adds + v_j.amount_cad < 0 then                                      -- 판정 399 와 같은 음수 가드(되돌림이 원가보다 크면 거부)
    raise exception 'Cost adjustment % (% CAD) is a credit larger than the cost of the goods on layer % (% % · cost % + earlier adds %) — check the amount — no cost was changed',
      v_j.source_number, v_j.amount_cad, v_lay.id, v_lay.sku, v_lay.doc_number, v_lay.basis, v_lay.adds;
  end if;

  -- 얹기 — 전액 한 줄 · kind = 사건 kind · doc_number = source_number · line_ref adj:<id> · ref_number = 대상 레이어 문서 · settle 이 남은 몫 / 옮겨 간 몫(자식 carried · 어느 축이든) / 나간 몫(cost_late) 으로 나눈다
  insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
  values (v_lay.id, v_j.kind, v_j.amount_cad, v_on, v_j.source_number, 'adj:' || v_j.id::text, v_j.layer_doc_number)
  returning id into v_aid;
  v_sub := public.inv_layer_cost_add_settle(v_aid);

  if p_on is null then                                                                         -- 실시간: 자리를 남긴다(재생성이 같은 자리에서 같은 소비 상태로 다시 나눈다)
    select max(g.id) into v_maxid from public.inv_ledger g;
    update public.inv_cost_adjust set status = 'posted', posted_on = v_on, posted_ledger_id = v_maxid where id = v_j.id;
  end if;
  return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'posted',
                            'layers', 1, 'basis', v_lay.basis, 'amount_cad', v_j.amount_cad, 'posted_cad', v_j.amount_cad, 'posted_on', v_on, 'posted_ledger_id', v_maxid,
                            'late_sold_cad', coalesce((v_sub ->> 'sold_amount')::numeric, 0), 'late_moved_cad', coalesce((v_sub ->> 'moved_amount')::numeric, 0),
                            'carried_rows', coalesce((v_sub ->> 'carried_rows')::int, 0),
                            'lines', jsonb_build_array(jsonb_build_object('layer_id', v_lay.id, 'sku', v_lay.sku, 'warehouse', v_lay.warehouse, 'doc_number', v_lay.doc_number, 'line_ref', v_lay.line_ref,
                                                                          'qty', v_lay.qty, 'unit_cost', v_lay.unit_cost, 'basis', v_lay.basis, 'share_cad', v_j.amount_cad, 'settle_rows', coalesce((v_sub ->> 'rows_written')::int, 0))),
                            'builder', c_version);
exception
  when unique_violation then
    raise exception 'Cost adjustment % — a cost row with the same key already exists (%) — no cost was changed', v_j.source_number, sqlerrm;
end;
$$;
revoke all on function public.inv_layer_post_opening_fix(uuid, date) from public, anon, authenticated;
grant execute on function public.inv_layer_post_opening_fix(uuid, date) to service_role;
comment on function public.inv_layer_post_opening_fix(uuid, date) is 'cost-fix-1 ⭐ layer 대상 원가 조정 얹기(판정 932 · 2026-11-01) — inv_cost_adjust(target_type layer · 자연키 넷) 한 사건을 그 레이어 하나에 전액(비례 없음 · 기준 0 거부 없음) · 멱등 키 adj:<id> · inv_layer_cost_add_settle 이 남은 몫 / 자식 carried(어느 축이든) / cost_late 로 나눈다 · 실시간은 posted_on · posted_ledger_id 를 남기고 재생성(flush_adds)은 그 자리에서 p_on 으로 다시 · 부르는 쪽: inv_layer_post_cost_adjust(위임) · 직접 호출은 psql';

-- ── 3) inv_cost_fix_opening_transfer — 적용 창구(부모 없는 unknown 0 도착 레이어마다 사건 하나 · 단가 갈래 넷 · 멱등 · p_dry) ──
create or replace function public.inv_cost_fix_opening_transfer(p_docs text[], p_skus text[] default null, p_compare_key text default '2026-10-30-compare', p_dry boolean default false) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version    constant text := 'inv_cost_fix_opening_transfer@2026-11-01.1';
  v_staff      uuid;
  v_r          record;
  v_unit       numeric;
  v_basis      text;
  v_amount     numeric;
  v_id         uuid;
  v_post       jsonb;
  v_lines      jsonb := '[]'::jsonb;
  v_refs       text[] := '{}';
  v_seen       int := 0;   v_posted int := 0;   v_already int := 0;   v_nounit int := 0;
  v_total      numeric := 0;
  v_gone       numeric := 0;
  v_by_basis   jsonb;
begin
  perform public.ims_require_write('purchasing', 'posted');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if p_docs is null or cardinality(p_docs) = 0 then raise exception 'inv_cost_fix_opening_transfer: p_docs is empty — nothing was changed'; end if;

  for v_r in
    select x.id, x.sku, x.warehouse, x.doc_number, x.line_ref, x.qty, v.remaining_qty,
           b.other_wh, b.same_wh, ic.unit_cost as inv_cost_unit, cs.cmp
      from public.inv_layer x
      cross join lateral public.inv_layer_value(x.id) v
      left join lateral (select sum(l.unit_cost * l.qty) filter (where l.warehouse <> x.warehouse and l.warehouse <> 'IN_TRANSIT') / nullif(sum(l.qty) filter (where l.warehouse <> x.warehouse and l.warehouse <> 'IN_TRANSIT'), 0) as other_wh,
                                sum(l.unit_cost * l.qty) filter (where l.warehouse = x.warehouse) / nullif(sum(l.qty) filter (where l.warehouse = x.warehouse), 0) as same_wh
                           from public.inv_layer l where l.origin_type = 'baseline' and l.sku = x.sku) b on true
      left join lateral (select c.unit_cost from public.inv_cost c where c.sku = x.sku and c.cost_kind = 'goods' and c.unit_cost > 0 order by c.occurred_on desc, c.id desc limit 1) ic on true
      left join lateral (select sum(s.value) / nullif(sum(s.qty), 0) as cmp from public.inv_snapshot s where s.snapshot_key = p_compare_key and s.sku = x.sku and s.qty > 0 and s.value > 0) cs on true
     where x.doc_number = any (p_docs) and x.origin_type = 'transfer' and x.cost_source = 'unknown' and x.parent_layer_id is null and x.unit_cost = 0 and x.warehouse <> 'IN_TRANSIT'
       and (p_skus is null or x.sku = any (p_skus))
     order by x.doc_number, x.sku, x.id
  loop
    v_seen := v_seen + 1;
    -- 멱등 — 되돌려지지 않은 opening_fix 사건이 이 레이어(자연키)에 이미 있으면 건너뛴다
    if exists (select 1 from public.inv_cost_adjust j
                where j.kind = 'opening_fix' and j.target_type = 'layer' and j.reverses_id is null
                  and j.layer_doc_number = v_r.doc_number and j.layer_line_ref = v_r.line_ref and j.layer_sku = v_r.sku and j.layer_warehouse = v_r.warehouse
                  and not exists (select 1 from public.inv_cost_adjust rv where rv.reverses_id = j.id)) then
      v_already := v_already + 1;
      v_lines := v_lines || jsonb_build_object('sku', v_r.sku, 'doc_number', v_r.doc_number, 'line_ref', v_r.line_ref, 'qty', v_r.qty, 'remaining_qty', v_r.remaining_qty, 'status', 'already_fixed');
      continue;
    end if;
    -- 단가 갈래(이견 2): 다른 실제 창고 기초(토론토) → 같은 창고 기초 → inv_cost 최근 양수 goods 단가 → compare 스냅샷 단가 · 0 은 없는 것으로 본다
    if    coalesce(v_r.other_wh, 0)      > 0 then v_unit := v_r.other_wh;      v_basis := 'baseline_other_wh';
    elsif coalesce(v_r.same_wh, 0)       > 0 then v_unit := v_r.same_wh;       v_basis := 'baseline_same_wh';
    elsif coalesce(v_r.inv_cost_unit, 0) > 0 then v_unit := v_r.inv_cost_unit; v_basis := 'inv_cost_recent';
    elsif coalesce(v_r.cmp, 0)           > 0 then v_unit := v_r.cmp;           v_basis := 'compare_snapshot';
    else
      v_nounit := v_nounit + 1;
      v_lines := v_lines || jsonb_build_object('sku', v_r.sku, 'doc_number', v_r.doc_number, 'line_ref', v_r.line_ref, 'qty', v_r.qty, 'remaining_qty', v_r.remaining_qty, 'status', 'no_unit_cost');
      continue;
    end if;
    v_unit   := round(v_unit, 6);
    v_amount := round(v_unit * v_r.qty, 6);
    v_total  := v_total + v_amount;
    if p_dry then
      v_lines := v_lines || jsonb_build_object('sku', v_r.sku, 'doc_number', v_r.doc_number, 'line_ref', v_r.line_ref, 'qty', v_r.qty, 'remaining_qty', v_r.remaining_qty,
                                               'unit_cost', v_unit, 'basis', v_basis, 'amount_cad', v_amount, 'status', 'dry');
      continue;
    end if;
    insert into public.inv_cost_adjust (kind, target_type, layer_doc_number, layer_line_ref, layer_sku, layer_warehouse, amount_cad, source_type, source_number, status, note, created_by, updated_by)
    values ('opening_fix', 'layer', v_r.doc_number, v_r.line_ref, v_r.sku, v_r.warehouse, v_amount, 'opening_fix', v_r.doc_number, 'pending',
            format('%s x %s @ %s (%s) — in-transit at baseline 2026-08-20, arrived with unknown cost', v_r.sku, v_r.qty, v_unit, v_basis), v_staff, v_staff)
    returning id into v_id;
    v_post := public.inv_layer_post_cost_adjust(v_id);                                       -- 위임 → inv_layer_post_opening_fix(실시간 자리)
    if v_post ->> 'status' <> 'posted' then
      raise exception 'inv_cost_fix_opening_transfer: % % posting returned % — nothing was changed', v_r.doc_number, v_r.sku, v_post ->> 'status';
    end if;
    v_posted := v_posted + 1;
    v_refs := v_refs || ('adj:' || v_id::text);
    v_lines := v_lines || jsonb_build_object('sku', v_r.sku, 'doc_number', v_r.doc_number, 'line_ref', v_r.line_ref, 'qty', v_r.qty, 'remaining_qty', v_r.remaining_qty,
                                             'unit_cost', v_unit, 'basis', v_basis, 'amount_cad', v_amount, 'adjust_id', v_id, 'status', 'posted',
                                             'late_sold_cad', v_post -> 'late_sold_cad', 'late_moved_cad', v_post -> 'late_moved_cad', 'carried_rows', v_post -> 'carried_rows');
  end loop;

  -- 나간 몫 = 이 사건들의 cost_late 전부(뿌리 split_basis.kind opening_fix · 자식은 carried 지만 line_ref adj:<id> 를 물려받는다) · 남은 몫 = 전체 − 나간 몫
  if cardinality(v_refs) > 0 then
    select coalesce(sum(k.amount), 0) into v_gone from public.inv_layer_consume k where k.reason = 'cost_late' and k.line_ref = any (v_refs);
  end if;
  select coalesce(jsonb_object_agg(t.b, t.s), '{}'::jsonb) into v_by_basis
    from (select e ->> 'basis' as b, sum((e ->> 'amount_cad')::numeric) as s from jsonb_array_elements(v_lines) e where e ? 'basis' group by 1) t;
  return jsonb_build_object('docs', to_jsonb(p_docs), 'skus', to_jsonb(p_skus), 'compare_key', p_compare_key, 'dry', p_dry,
                            'layers_seen', v_seen, 'posted', v_posted, 'skipped_already_fixed', v_already, 'skipped_no_unit_cost', v_nounit,
                            'amount_total_cad', v_total, 'gone_cad', case when p_dry then null else v_gone end, 'remaining_cad', case when p_dry then null else v_total - v_gone end,
                            'by_basis', v_by_basis, 'lines', v_lines, 'builder', c_version);
end;
$$;
revoke all on function public.inv_cost_fix_opening_transfer(text[], text[], text, boolean) from public, anon, authenticated;
grant execute on function public.inv_cost_fix_opening_transfer(text[], text[], text, boolean) to service_role;
comment on function public.inv_cost_fix_opening_transfer(text[], text[], text, boolean) is 'cost-fix-1 ⭐ 기초 경계 트랜스퍼 도착 레이어 원가 바로잡기 적용 창구(판정 932 · 2026-11-01) — p_docs 의 부모 없는 transfer/unknown 0 도착 레이어마다 inv_cost_adjust(kind opening_fix · target layer · 자연키 넷) 한 사건을 만들어 곧바로 얹는다(inv_layer_post_cost_adjust → inv_layer_post_opening_fix) · 단가 = 다른 실제 창고 기초(토론토) → 같은 창고 기초 → inv_cost 최근 양수 goods 단가 → p_compare_key 스냅샷 단가 · 금액은 inv_layer(기초)에서 계산 · 멱등(되돌려지지 않은 사건이 있으면 already_fixed) · p_skus 로 좁힘 · p_dry 는 쓰기 0 · 반환: SKU 별 단가 · 갈래 · 합계(amount_total · gone(cost_late) · remaining) · psql(purchasing 열쇠 로그인)로만 부른다';

-- ── 4) inv_layer_post_cost_adjust 재발행 — 원본 20261020143921:417~530(prosrc md5 832aa1e6d949b23077fff883e3e44fc4 · 2026-11-01 대조) + 3 줄(layer 위임) · 바뀐 · 빠진 줄 0 ──
create or replace function public.inv_layer_post_cost_adjust(p_adjust_id uuid, p_on date default null) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version    constant text := 'inv_layer_post_cost_adjust@2026-10-09.1';
  v_j          public.inv_cost_adjust%rowtype;
  v_tr         record;                 -- charge_alloc 대상: 배분 줄의 po_id · transfer_id · transfer_number · po_number
  v_lay        record;
  v_n_layers   int;
  v_basis      numeric;
  v_share      numeric;
  v_given      numeric := 0;
  v_i          int := 0;
  v_aid        bigint;
  v_sub        jsonb;
  v_lines      jsonb := '[]'::jsonb;
  v_carried    int := 0;
  v_late_sold  numeric := 0;
  v_late_moved numeric := 0;
  v_ref        text;                   -- cost_add.ref_number — 발주 번호(트랜스퍼 배분이면 트랜스퍼 번호) · inv_layer_post_charge 와 같은 자리
  v_on         date := coalesce(p_on, public.ims_today());
  v_maxid      bigint;
begin
  -- 문(⬜4) — purchasing(결제 · 크레딧 · 되돌림 창구) · receiving | wms_receiving_confirm(입고 확정 길 · po_receipt_confirm_by ⓖ) · 재생성 로그인은 둘 다 가진다
  if not (public.ims_can_write('purchasing') or public.ims_can_write('receiving') or public.ims_can_write('wms_receiving_confirm')) then
    perform public.ims_require_write('purchasing', 'posted');
  end if;
  if (select j.target_type from public.inv_cost_adjust j where j.id = p_adjust_id) = 'layer' then     -- cost-fix-1(판정 932 · 2026-11-01): layer 대상(기초 경계 트랜스퍼 도착 레이어 · 자연키 넷)은 제 창구로 — 레이어 하나 · 전액 · 기준 0 거부 없음 · 같은 멱등 키 adj:<id> · 같은 자리(posted_on · posted_ledger_id)
    return public.inv_layer_post_opening_fix(p_adjust_id, p_on);
  end if;

  select * into v_j from public.inv_cost_adjust where id = p_adjust_id for update;
  if not found then raise exception 'Cost adjustment % not found — no cost was changed', p_adjust_id; end if;
  -- 멱등 — 실시간: 이미 posted 면 0 줄 · 재생성: posted 사건만 받고 이 사건의 얹기 줄이 이미 있으면 0 줄(같은 트랜잭션 재호출도 여기 걸린다)
  if p_on is null and v_j.status = 'posted' then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'already_posted', 'layers', 0, 'posted_cad', 0, 'posted_on', v_j.posted_on, 'builder', c_version);
  end if;
  if p_on is not null and v_j.status <> 'posted' then
    raise exception 'Cost adjustment % is still pending — regeneration replays posted adjustments only — no cost was changed', v_j.source_number;
  end if;
  if exists (select 1 from public.inv_layer_cost_add ca where ca.line_ref = 'adj:' || v_j.id::text) then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'already_posted', 'layers', 0, 'posted_cad', 0, 'posted_on', v_j.posted_on, 'builder', c_version);
  end if;

  -- 대상 — charge_alloc 이면 배분 줄의 발주 · 트랜스퍼(inv_layer_post_charge 가 읽는 것과 같은 것)
  if v_j.target_type = 'charge_alloc' then
    select a.po_id, a.transfer_id, t.transfer_number, p.po_number into v_tr
      from public.po_charge_alloc a left join public.inv_transfer t on t.id = a.transfer_id left join public.po p on p.id = a.po_id
     where a.id = v_j.po_charge_alloc_id;
    if not found then raise exception 'Cost adjustment %: allocation line % not found — no cost was changed', v_j.source_number, v_j.po_charge_alloc_id; end if;
    v_ref := coalesce(v_tr.po_number, v_tr.transfer_number);
  else
    select null::uuid as po_id, null::uuid as transfer_id, null::text as transfer_number, p.po_number into v_tr from public.po_line pl join public.po p on p.id = pl.po_id where pl.id = v_j.po_line_id;
    v_ref := v_tr.po_number;
  end if;

  -- 레이어 집합 · 기준 — po_line: 그 줄의 구매 레이어 · charge_alloc: ⬜3 inv_layer_post_charge 20260930144905 의 술어 그대로(발주 갈래 · 트랜스퍼 갈래 · :settle: · :over: 제외)
  select count(*), coalesce(sum(x.unit_cost * x.qty), 0) into v_n_layers, v_basis
    from public.inv_layer x
    left join public.po_line pl on pl.id::text = public.inv_po_line_of(x.line_ref)   -- rcv-1a
   where (v_j.target_type = 'po_line' and x.origin_type = 'purchase' and x.cost_source = 'po_line' and public.inv_po_line_of(x.line_ref) = v_j.po_line_id::text)
      or (v_j.target_type = 'charge_alloc' and (
             (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_tr.po_id)
          or (v_tr.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_tr.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%')));
  if v_n_layers = 0 then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'no_layers', 'layers', 0, 'basis', 0, 'posted_cad', 0, 'amount_cad', v_j.amount_cad, 'builder', c_version);
  end if;
  if v_basis = 0 then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'no_basis', 'layers', v_n_layers, 'basis', 0, 'posted_cad', 0, 'amount_cad', v_j.amount_cad, 'builder', c_version);
  end if;

  -- 금액 비율(unit_cost × qty) · 6자리 · 끝수는 마지막 레이어 · ⬜1 음수 가드 · 줄마다 settle
  for v_lay in
    select x.id, x.sku, x.warehouse, x.doc_number, x.line_ref, x.qty, x.unit_cost, x.unit_cost * x.qty as basis,
           coalesce((select sum(ca.amount) from public.inv_layer_cost_add ca where ca.layer_id = x.id), 0) as adds
      from public.inv_layer x
      left join public.po_line pl on pl.id::text = public.inv_po_line_of(x.line_ref)   -- rcv-1a
     where (v_j.target_type = 'po_line' and x.origin_type = 'purchase' and x.cost_source = 'po_line' and public.inv_po_line_of(x.line_ref) = v_j.po_line_id::text)
        or (v_j.target_type = 'charge_alloc' and (
               (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_tr.po_id)
            or (v_tr.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_tr.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%')))
     order by x.sku, x.line_ref, x.id
  loop
    v_i := v_i + 1;
    if v_i = v_n_layers then v_share := v_j.amount_cad - v_given;                        -- 마지막 레이어에 잔액 — 합이 정확히 사건 금액
    else v_share := round(v_j.amount_cad * v_lay.basis / v_basis, 6); end if;
    if v_lay.basis + v_lay.adds + v_share < 0 then                                        -- ⬜1: 물건의 원가보다 큰 크레딧 — 입력 오류일 가능성 · 사건 전체 거부(앞 레이어에 넣은 줄은 예외로 함께 되돌아간다)
      raise exception 'Cost adjustment % (% CAD) is a credit larger than the cost of the goods on layer % (% % · cost % + earlier adds % + this share %) — check the amount — no cost was changed',
        v_j.source_number, v_j.amount_cad, v_lay.id, v_lay.sku, v_lay.doc_number, v_lay.basis, v_lay.adds, v_share;
    end if;
    v_given := v_given + v_share;
    insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
    values (v_lay.id, v_j.kind, v_share, v_on, v_j.source_number, 'adj:' || v_j.id::text, v_ref)
    returning id into v_aid;
    v_sub := public.inv_layer_cost_add_settle(v_aid);                                     -- 남은 몫 · 옮겨 간 몫(자식 carried · ref_number layer:<부모>:<kind>) · 팔린 몫(cost_late · split_basis.kind = 이 kind)
    v_carried    := v_carried    + coalesce((v_sub ->> 'carried_rows')::int, 0);
    v_late_sold  := v_late_sold  + coalesce((v_sub ->> 'sold_amount')::numeric, 0);
    v_late_moved := v_late_moved + coalesce((v_sub ->> 'moved_amount')::numeric, 0);
    v_lines := v_lines || jsonb_build_object('layer_id', v_lay.id, 'sku', v_lay.sku, 'warehouse', v_lay.warehouse, 'doc_number', v_lay.doc_number, 'line_ref', v_lay.line_ref,
                                             'qty', v_lay.qty, 'unit_cost', v_lay.unit_cost, 'basis', v_lay.basis, 'share_cad', v_share, 'settle_rows', coalesce((v_sub ->> 'rows_written')::int, 0));
  end loop;

  if p_on is null then                                                                    -- 실시간: 자리를 남긴다(재생성이 같은 자리 · 같은 날 안의 앞뒤까지 재현 · 비용의 posted_on 과 같은 모양)
    select max(g.id) into v_maxid from public.inv_ledger g;
    update public.inv_cost_adjust set status = 'posted', posted_on = v_on, posted_ledger_id = v_maxid where id = v_j.id;
  end if;
  return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'posted',
                            'layers', v_n_layers, 'basis', v_basis, 'amount_cad', v_j.amount_cad, 'posted_cad', v_given, 'posted_on', v_on, 'posted_ledger_id', v_maxid,
                            'late_sold_cad', v_late_sold, 'late_moved_cad', v_late_moved, 'carried_rows', v_carried, 'lines', v_lines, 'builder', c_version);
exception
  when unique_violation then
    raise exception 'Cost adjustment % — a cost row with the same key already exists (%) — no cost was changed', v_j.source_number, sqlerrm;
end;
$$;
comment on function public.inv_layer_post_cost_adjust(uuid, date) is 'po-disc-3 ⭐ 원가 조정 사건 얹기(판정 391 · 394 · 399) — po_line · charge_alloc 대상은 unit_cost × qty 비례 · 6자리 · 끝수 마지막 · 음수 가드(사건 전체 거부) · 줄마다 settle · 실시간은 posted_on · posted_ledger_id 자리 · cost-fix-1(2026-11-01): target_type layer 는 inv_layer_post_opening_fix 로 위임(레이어 하나 · 전액)';

-- ── 5) inv_layer_apply_flush_adds 재발행 — 원본 20261020143921:533~758(prosrc md5 82989062077d0f1ea7438916a6230606 · 2026-11-01 대조) + 18 줄(조정 루프 layer 갈래 블록) · 바뀐 · 빠진 줄 0 ──
create or replace function public.inv_layer_apply_flush_adds(p_day date, p_until date, p_before_id bigint, p_acc jsonb) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_landed_rows int := 0;
  v_doc         record;
  v_grp         record;
  v_fr_n        int;
  v_fr_basis    numeric;
  v_fr_rows     int := 0;
  v_fr_docs     int := 0;
  v_fr_nobasis  int := 0;
  v_fr_nobasis_amt numeric := 0;
  v_fr_orphan   int := 0;
  v_fr_multi    int := 0;
  v_rows        int;
  v_ims_j       jsonb;
  v_ims_chg     record;
  v_ims_chg_n       int := 0;   v_ims_chg_rows   int := 0;   v_ims_chg_amt   numeric := 0;
  v_ims_chg_nobasis_amt  numeric := 0;   v_ims_chg_nolayers_amt numeric := 0;   v_ims_chg_already int := 0;   v_ims_chg_skipped int := 0;
  v_chg_skip    jsonb := '[]'::jsonb;                                                     -- [{d charge_date · e 원문 skip 항목}] — 본체가 원문 순서로 잇는다
  v_ids         bigint[];   v_id bigint;                                                  -- cogs-2: 새로 든 얹기 줄(on conflict do nothing 의 returning) → settle
  v_al          record;     v_chg_ids uuid[] := '{}';                                      -- cogs-2(판정 114): IMS 비용은 배분 줄 단위 · charges_posted 는 비용 문서 수(distinct)
  v_deferred    int := 0;                                                                 -- cogs-3(판정 119) 안전띠: 대상 레이어가 아직 없어 이번 경계에서 미룬 posted 배분 줄 수
  v_adj         record;                                                                  -- po-disc-3(판정 391 · 394): IMS 원가 조정 사건 — 비용 갈래와 같은 자리(posted_on · posted_ledger_id) · done kind cogs_adj
  v_adj_n int := 0;   v_adj_rows int := 0;   v_adj_amt numeric := 0;   v_adj_nolayers int := 0;   v_adj_skipped int := 0;   v_adj_deferred int := 0;   v_adj_skip jsonb := '[]'::jsonb;
begin
  -- ═══ PO landed → inv_layer_cost_add (2026-09-10 · 헤더) — cogs-1: 그날까지 · 아직 안 얹은 것 · 대상 레이어가 선 것만(집합 연산 한 번은 그대로) ═══
  with ins as (
  insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
  select x.id, 'landed',
         sum(c.amount),          -- ⭐ bin 이 여럿이면 합산 (실측 0건 · 방어)
         c.occurred_on,          -- ⚠️ 날짜별로 별개 행 (통관·freight·관세)
         c.doc_number, c.line_ref,
         null                    -- PO landed 는 인보이스 번호가 오지 않는다 (헤더)
    from inv_cost c
    join inv_layer x
      on  x.origin_type = 'purchase'
      and x.doc_number  = c.doc_number
      and x.line_ref    = c.line_ref
      and x.sku         = c.sku
      and x.warehouse   = c.warehouse
    where c.cost_kind = 'landed'
      and (p_until is null or c.occurred_on <= p_until)
      and (p_day is null or c.occurred_on <= p_day)                                                                                                        -- cogs-1(판정 109): 그날까지의 비용만
      and not exists (select 1 from inv_layer_cost_add ca where ca.layer_id = x.id and ca.kind = 'landed' and ca.doc_number = c.doc_number and ca.line_ref = c.line_ref and ca.occurred_on = c.occurred_on)   -- cogs-1: 아직 안 얹은 것만(inv_layer_cost_add_uq 와 같은 키)
    group by x.id, c.occurred_on, c.doc_number, c.line_ref
  on conflict on constraint inv_layer_cost_add_uq do nothing
  returning id)
  select coalesce(array_agg(ins.id order by ins.id), '{}') into v_ids from ins;
  v_landed_rows := coalesce(array_length(v_ids, 1), 0);
  foreach v_id in array v_ids loop perform inv_layer_cost_add_settle(v_id); end loop;                     -- cogs-2(판정 107): 새로 든 얹기 줄마다 셋으로(레이어가 이미 팔린 뒤 온 landed → cost_late · 자식 carried)

  -- ═══ 트랜스퍼 운송비 → inv_layer_cost_add (kind='transfer_freight' · 2026-09-10 · 헤더 B) — landed 와 같은 자리 ═══
  -- 문서 단위 루프 — 배분 기준(도착 레이어 원가 합)은 문서에 딸린 레이어로 정해지므로 문서마다 한 번 계산한다
  for v_doc in
    select doc_number, sum(amount) as amount     -- amount: no_basis 로 떨어질 때 합산할 문서 금액 (p_until 범위)
      from inv_doc_cost
      where doc_type = 'transfer' and kind = 'transfer_freight'
        and (p_until is null or occurred_on <= p_until)
      group by doc_number
      having (p_day is null or max(occurred_on) <= p_day)                                                                                                 -- cogs-1: 저널 묶음이 그날까지 다 온 문서만
      order by doc_number
  loop
    if exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_fr' and d.doc_number = v_doc.doc_number and d.sku = '' and d.warehouse = '') then continue; end if;   -- cogs-1: 이미 처리한 문서
    if p_day is not null and exists (select 1 from inv_ledger g where g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT' and g.doc_number = v_doc.doc_number
                                        and g.occurred_on > p_day and (p_until is null or g.occurred_on <= p_until)) then continue; end if;                -- cogs-1: 도착이 더 남은 문서는 기다린다(기준 = 도착 레이어 전부 · 원문과 같은 집합)
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('cogs_fr', v_doc.doc_number, '', '');
    -- B-1 대상 = 도착 창고 레이어만 (IN_TRANSIT 제외) · B-2 기준 = unit_cost × qty (remaining 아님)
    select count(*), coalesce(sum(x.unit_cost * x.qty), 0) into v_fr_n, v_fr_basis
      from inv_layer x
      where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT';
    if v_fr_n = 0 then
      v_fr_orphan := v_fr_orphan + 1;          -- 대응 레이어 없음 (0 이 아니면 신호)
      continue;
    end if;
    if v_fr_basis <= 0 then
      v_fr_nobasis := v_fr_nobasis + 1;        -- 원가 미상(unknown · unit_cost 0) 레이어만 있는 문서 — 0 으로 나누지 않는다
      v_fr_nobasis_amt := v_fr_nobasis_amt + v_doc.amount;   -- ⚠️ 버린 운송비 금액 — Cin7 대조에서 설명된 차이의 크기 (헤더)
      continue;
    end if;

    -- 날짜별 한 묶음 — cost_add 유니크 키에 ref_number 가 없으므로 같은 날 인보이스가 둘이면 합산 1행 (헤더 B-3)
    for v_grp in
      select occurred_on, sum(amount) as amount, count(*) as n,
             string_agg(distinct ref_number, ',' order by ref_number) as ref_number
        from inv_doc_cost
        where doc_type = 'transfer' and kind = 'transfer_freight' and doc_number = v_doc.doc_number
          and (p_until is null or occurred_on <= p_until)
        group by occurred_on
        order by occurred_on
    loop
      if v_grp.n > 1 then v_fr_multi := v_fr_multi + 1; end if;
      -- B-2 배분: share = round(문서금액 × 레이어원가 / 합, 6) · 마지막 레이어(id 순) = 문서금액 − 앞선 share 합 (remainder on last)
      with ins as (
      insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
      select t.id, 'transfer_freight',
             case when t.rn = t.cnt
                  then v_grp.amount - coalesce(sum(t.share) over (order by t.rn rows between unbounded preceding and 1 preceding), 0)
                  else t.share end,
             v_grp.occurred_on, v_doc.doc_number, t.line_ref, v_grp.ref_number
        from (select x.id, x.line_ref,
                     round(v_grp.amount * (x.unit_cost * x.qty) / v_fr_basis, 6) as share,
                     row_number() over (order by x.id) as rn,
                     count(*) over () as cnt
                from inv_layer x
                where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT') t
      on conflict on constraint inv_layer_cost_add_uq do nothing
      returning id)
      select coalesce(array_agg(ins.id order by ins.id), '{}') into v_ids from ins;
      v_rows := coalesce(array_length(v_ids, 1), 0);
      v_fr_rows := v_fr_rows + v_rows;
      foreach v_id in array v_ids loop perform inv_layer_cost_add_settle(v_id); end loop;                 -- cogs-2(판정 107): 도착 레이어가 이미 팔렸거나 다시 떠난 뒤 온 운임 → cost_late · cost_moved · 자식 carried
    end loop;
    v_fr_docs := v_fr_docs + 1;
  end loop;

  -- ═══ IMS 비용 → inv_layer_cost_add (kind='landed' · 2026-09-20) — landed·운송비와 같은 층 · 창구 inv_layer_post_charge 에 넘긴다 ═══
  -- tr-4(2026-09-29): 비용 문서의 배분 줄이 트랜스퍼를 가리키면 그 문서의 도착 레이어에 얹는다 — 같은 창구 · 같은 규칙(판정 67 · 77 · 묶음 일곱) · 아래 exists 둘에 트랜스퍼 갈래를 더했다.
  -- 왜 여기(날짜 경계)인가(cogs-1 · 판정 109): 옛 판은 「비용은 금액만 얹어 FIFO 소진에 영향이 없다」며 끝에 두었다 — 다음 차수가 소진 단가에 얹힌 몫을 넣으면 그 전제가 깨지므로 지금 자리부터 옮긴다(입고 레이어는 루프 안 — 본체).
  -- 왜 레이어에서 훑나(Caleb 판정 2026-09-20): 비용은 원장에 사건을 남기지 않아(금액만 얹는다) 원장으로 훑을 수 없다. 레이어가 없으면 얹을 곳도 없으니 부를 이유가 없다.
  --   길: inv_layer(cost_source='po_line').line_ref = po_line.id::text → po_line.po_id = po_charge_alloc.po_id → po_charge_alloc.po_charge_id = po_charge.id (confirmed).
  --   비용 문서 단위로 한 번(한 비용이 여러 발주에 배분된다 — exists 로 접는다) · 순서 고정.
  -- 왜 창구에 넘기나: 배분 규칙(환율 · unit_cost×qty 비례 · 6자리 · 끝수는 마지막 · 기준 0 버림 · 배분 줄 단위 멱등)이 창구 안에 있다 — 두 곳에 살게 하지 않는다.
  -- p_until: cogs-2 — 얹기 줄 날짜 = posted_on(없으면 charge_date) — 그것이 p_until 안이면 고른다(as-of 재생성).
  -- 방문하지 않은 확정 비용(배분된 발주 어디에도 IMS 레이어가 없는 것 — 예: 환율이 없어 입고를 건너뛴 발주)은 따로 센다(charges_unvisited · 금액 CAD)
  --   — 「버린 금액」의 그림이 빠지지 않게. Cin7 대조에서 이 금액만큼은 설명된 차이다(정본 D 의 freight_no_basis_amount 와 같은 구실).
  -- ⭐ cogs-2(판정 114 · 115-1): 배분 줄 단위 · 자리 = 실시간이 남긴 posted_on(같은 날 안은 posted_ledger_id < p_before_id 인 것만 · 본체가 줄 id 로 부른다) · posted_on 없는 옛 배분 줄은 첫 차수 규칙(charge_date ≤ p_day · 그 배분 줄의 레이어가 선 뒤 · 얹기 줄 날짜 = charge_date)
  for v_al in
    select a.id as alloc_id, c.id as charge_id, c.charge_number, c.charge_date, a.posted_on, a.posted_ledger_id, a.po_id, a.transfer_id
      from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
      where c.status = 'confirmed' and c.confirmed_at is not null
        and (p_until is null or coalesce(a.posted_on, c.charge_date) <= p_until)
        and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '')   -- 이미 부른 배분 줄
        and (
              (a.posted_on is not null                                                                                   -- ⓐ 실시간이 얹은 배분 줄: posted_on 자리 · 같은 날 안은 posted_ledger_id < p_before_id 인 것만
               and (p_day is null or a.posted_on < p_day or (a.posted_on = p_day and (p_before_id is null or coalesce(a.posted_ledger_id, -1) < p_before_id))))
           or (a.posted_on is null                                                                                       -- ⓑ 아직 안 얹힌 배분 줄(옛 것 · no_layers): 첫 차수 규칙 — charge_date ≤ p_day 이고 그 배분 줄의 레이어가 선 것 · 마지막 쏟기(p_day null)는 레이어가 없어도 넘겨 no_layers 로 센다
               and (p_day is null or c.charge_date <= p_day)
               and (p_day is null
                    or (a.po_id is not null and exists (select 1 from po_line pl join inv_layer x on inv_po_line_of(x.line_ref) = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line' where pl.po_id = a.po_id))
                    or (a.transfer_id is not null and exists (select 1 from inv_transfer t join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%' where t.id = a.transfer_id))))   -- inv-basis-3(판정 95 ㉓): 창구와 같은 술어
            )
      order by coalesce(a.posted_on, c.charge_date), a.posted_ledger_id nulls first, c.charge_number, c.id, a.id
  loop
    if v_al.posted_on is not null and p_day is not null                                                                    -- cogs-3(판정 119) 안전띠: 실시간이 얹은 배분 줄인데 대상 레이어가 아직 없으면 done 을 쓰지 않고 다음 경계에서 다시 본다(마지막 쏟기 p_day null 은 창구에 넘겨 no_layers 로)
       and not ((v_al.po_id is not null and exists (select 1 from po_line pl join inv_layer x on inv_po_line_of(x.line_ref) = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line' where pl.po_id = v_al.po_id))
             or (v_al.transfer_id is not null and exists (select 1 from inv_transfer t join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%' where t.id = v_al.transfer_id))) then
      v_deferred := v_deferred + 1;
      continue;
    end if;
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('cogs_chg', v_al.alloc_id::text, '', '');
    begin
      v_ims_j := inv_layer_post_charge(v_al.charge_id, coalesce(v_al.posted_on, v_al.charge_date), v_al.alloc_id);
      if not (v_al.charge_id = any (v_chg_ids)) then v_chg_ids := v_chg_ids || v_al.charge_id; v_ims_chg_n := v_ims_chg_n + 1; end if;
      v_ims_chg_rows         := v_ims_chg_rows         + coalesce((v_ims_j->>'layers_touched')::int, 0);
      v_ims_chg_amt          := v_ims_chg_amt          + coalesce((v_ims_j->>'amount_posted_cad')::numeric, 0);
      v_ims_chg_nobasis_amt  := v_ims_chg_nobasis_amt  + coalesce((v_ims_j->>'no_basis_amount_cad')::numeric, 0);    -- 기준 0 이라 버린 금액(정본 D)
      v_ims_chg_nolayers_amt := v_ims_chg_nolayers_amt + coalesce((v_ims_j->>'no_layers_amount_cad')::numeric, 0);   -- 배분 줄 중 레이어 없는 발주로 간 금액
      v_ims_chg_already      := v_ims_chg_already      + coalesce((v_ims_j->>'already_posted_allocs')::int, 0);      -- cost_add 를 지운 뒤라 0 이어야 한다(생기면 신호)
    exception when others then
      v_ims_chg_skipped := v_ims_chg_skipped + 1;
      v_chg_skip := v_chg_skip || jsonb_build_object('d', coalesce(v_al.posted_on, v_al.charge_date), 'e', jsonb_build_object('kind', 'charge', 'number', v_al.charge_number, 'id', v_al.charge_id, 'alloc_id', v_al.alloc_id, 'sqlstate', sqlstate, 'error', sqlerrm));
    end;
  end loop;

  -- ═══ IMS 원가 조정 → inv_layer_cost_add (po-disc-3 · 판정 391 · 394) — 비용 갈래와 같은 모양 · 자리 = posted_on · posted_ledger_id(같은 날 안은 < p_before_id) · done kind cogs_adj · pending(posted_on null)은 재생성이 얹지 않는다(입고 확정 사건이 그 자리 · 확정 순간 posted_on 이 적힌다) · 되돌림 줄도 자기 자리 ═══
  for v_adj in
    select j.id, j.source_number, j.posted_on, j.posted_ledger_id, j.target_type, j.po_line_id, j.po_charge_alloc_id
      from inv_cost_adjust j
      where j.status = 'posted' and j.posted_on is not null
        and (p_until is null or j.posted_on <= p_until)
        and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_adj' and d.doc_number = j.id::text and d.sku = '' and d.warehouse = '')
        and (p_day is null or j.posted_on < p_day or (j.posted_on = p_day and (p_before_id is null or coalesce(j.posted_ledger_id, -1) < p_before_id)))
      order by j.posted_on, j.posted_ledger_id nulls first, j.created_at, j.id
  loop
    if v_adj.target_type = 'layer' then                                                                                       -- cost-fix-1(판정 932 · 2026-11-01): layer 대상 — 아래 두 갈래 안전띠는 이 대상을 모른다(not (false or false) → 영원히 deferred) · 자연키 레이어가 아직 없으면 다음 경계로 · 있으면 같은 길(done · 창구 · 집계) 그대로
      if p_day is not null and not exists (select 1 from inv_cost_adjust jj join inv_layer x on x.doc_number = jj.layer_doc_number and x.line_ref = jj.layer_line_ref and x.sku = jj.layer_sku and x.warehouse = jj.layer_warehouse where jj.id = v_adj.id) then
        v_adj_deferred := v_adj_deferred + 1;
        continue;
      end if;
      insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('cogs_adj', v_adj.id::text, '', '');
      begin
        v_ims_j := inv_layer_post_cost_adjust(v_adj.id, v_adj.posted_on);
        v_adj_n := v_adj_n + 1;
        if v_ims_j ->> 'status' in ('no_layers', 'no_basis') then v_adj_nolayers := v_adj_nolayers + 1; end if;
        v_adj_rows := v_adj_rows + coalesce((v_ims_j ->> 'layers')::int, 0);
        v_adj_amt  := v_adj_amt  + coalesce((v_ims_j ->> 'posted_cad')::numeric, 0);
      exception when others then
        v_adj_skipped := v_adj_skipped + 1;
        v_adj_skip := v_adj_skip || jsonb_build_object('d', v_adj.posted_on, 'e', jsonb_build_object('kind', 'adjust', 'number', v_adj.source_number, 'id', v_adj.id, 'sqlstate', sqlstate, 'error', sqlerrm));
      end;
      continue;
    end if;
    if p_day is not null                                                                                                   -- cogs-3(판정 119) 안전띠와 같다: 대상 레이어가 아직 없으면 done 을 쓰지 않고 다음 경계로
       and not ((v_adj.target_type = 'po_line' and exists (select 1 from inv_layer x where x.origin_type = 'purchase' and x.cost_source = 'po_line' and inv_po_line_of(x.line_ref) = v_adj.po_line_id::text))
             or (v_adj.target_type = 'charge_alloc' and exists (select 1 from po_charge_alloc a left join inv_transfer t on t.id = a.transfer_id
                                                                 where a.id = v_adj.po_charge_alloc_id
                                                                   and ((a.po_id is not null and exists (select 1 from po_line pl join inv_layer x on inv_po_line_of(x.line_ref) = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line' where pl.po_id = a.po_id))
                                                                     or (a.transfer_id is not null and exists (select 1 from inv_layer x where x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%')))))) then
      v_adj_deferred := v_adj_deferred + 1;
      continue;
    end if;
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('cogs_adj', v_adj.id::text, '', '');
    begin
      v_ims_j := inv_layer_post_cost_adjust(v_adj.id, v_adj.posted_on);
      v_adj_n := v_adj_n + 1;
      if v_ims_j ->> 'status' in ('no_layers', 'no_basis') then v_adj_nolayers := v_adj_nolayers + 1; end if;
      v_adj_rows := v_adj_rows + coalesce((v_ims_j ->> 'layers')::int, 0);
      v_adj_amt  := v_adj_amt  + coalesce((v_ims_j ->> 'posted_cad')::numeric, 0);
    exception when others then
      v_adj_skipped := v_adj_skipped + 1;
      v_adj_skip := v_adj_skip || jsonb_build_object('d', v_adj.posted_on, 'e', jsonb_build_object('kind', 'adjust', 'number', v_adj.source_number, 'id', v_adj.id, 'sqlstate', sqlstate, 'error', sqlerrm));
    end;
  end loop;

  return jsonb_build_object(
    'landed_rows',      coalesce((p_acc ->> 'landed_rows')::int, 0)          + v_landed_rows,
    'fr_rows',          coalesce((p_acc ->> 'fr_rows')::int, 0)              + v_fr_rows,
    'fr_docs',          coalesce((p_acc ->> 'fr_docs')::int, 0)              + v_fr_docs,
    'fr_nobasis',       coalesce((p_acc ->> 'fr_nobasis')::int, 0)           + v_fr_nobasis,
    'fr_nobasis_amt',   coalesce((p_acc ->> 'fr_nobasis_amt')::numeric, 0)   + v_fr_nobasis_amt,
    'fr_orphan',        coalesce((p_acc ->> 'fr_orphan')::int, 0)            + v_fr_orphan,
    'fr_multi',         coalesce((p_acc ->> 'fr_multi')::int, 0)             + v_fr_multi,
    'chg_n',            coalesce((p_acc ->> 'chg_n')::int, 0)                + v_ims_chg_n,
    'chg_rows',         coalesce((p_acc ->> 'chg_rows')::int, 0)             + v_ims_chg_rows,
    'chg_amt',          coalesce((p_acc ->> 'chg_amt')::numeric, 0)          + v_ims_chg_amt,
    'chg_nobasis_amt',  coalesce((p_acc ->> 'chg_nobasis_amt')::numeric, 0)  + v_ims_chg_nobasis_amt,
    'chg_nolayers_amt', coalesce((p_acc ->> 'chg_nolayers_amt')::numeric, 0) + v_ims_chg_nolayers_amt,
    'chg_already',      coalesce((p_acc ->> 'chg_already')::int, 0)          + v_ims_chg_already,
    'chg_skipped',      coalesce((p_acc ->> 'chg_skipped')::int, 0)          + v_ims_chg_skipped,
    'chg_deferred',     coalesce((p_acc ->> 'chg_deferred')::int, 0)         + v_deferred,                              -- cogs-3(판정 119)
    'chg_skip',         coalesce(p_acc -> 'chg_skip', '[]'::jsonb)           || v_chg_skip,
    'adj_n',            coalesce((p_acc ->> 'adj_n')::int, 0)                + v_adj_n,                                -- po-disc-3
    'adj_rows',         coalesce((p_acc ->> 'adj_rows')::int, 0)             + v_adj_rows,
    'adj_amt',          coalesce((p_acc ->> 'adj_amt')::numeric, 0)          + v_adj_amt,
    'adj_nolayers',     coalesce((p_acc ->> 'adj_nolayers')::int, 0)         + v_adj_nolayers,
    'adj_skipped',      coalesce((p_acc ->> 'adj_skipped')::int, 0)          + v_adj_skipped,
    'adj_deferred',     coalesce((p_acc ->> 'adj_deferred')::int, 0)         + v_adj_deferred,
    'adj_skip',         coalesce(p_acc -> 'adj_skip', '[]'::jsonb)           || v_adj_skip);
end;
$$;

-- ── 6) inv_cost_adjust_reverse 재발행 — 원본 20261009002744:1266~1295(prosrc md5 02d8d9b95405aa6e80759b2b0d76a5c2 · 2026-11-01 대조) + 9 줄(layer 갈래 · 자연키 복사) · 첫 줄 create → create or replace 하나 · 그 밖 바뀐 · 빠진 줄 0 · ACL · comment 는 원래대로 ──
create or replace function public.inv_cost_adjust_reverse(p_adjust_id uuid, p_note text default null) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_j     public.inv_cost_adjust%rowtype;
  v_new   uuid;
  v_post  jsonb;
begin
  perform public.ims_require_write('purchasing', 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  select * into v_j from public.inv_cost_adjust where id = p_adjust_id for update;
  if not found then raise exception 'Cost adjustment % not found — nothing was saved', p_adjust_id; end if;
  if v_j.source_type = 'reversal' then
    raise exception 'Cost adjustment % (%) is itself a reversal — a reversal is not reversed; post a new adjustment instead — nothing was saved', v_j.source_number, v_j.id;
  end if;
  if exists (select 1 from public.inv_cost_adjust r where r.reverses_id = v_j.id) then
    raise exception 'Cost adjustment % (%) was already reversed — nothing was saved', v_j.source_number, v_j.id;
  end if;
  if v_j.target_type = 'layer' then                                                                                           -- cost-fix-1(판정 932 · 2026-11-01): layer 대상은 자연키 칸 넷을 함께 복사한다(target_pair_ck) · 나머지는 아래 길과 같다(반대 부호 · reversal · 원래 posted 면 곧바로 얹기 · 같은 반환)
    insert into public.inv_cost_adjust (kind, target_type, layer_doc_number, layer_line_ref, layer_sku, layer_warehouse, amount_cad, amount_doc, currency_id, exchange_rate, source_type, source_id, source_number, reverses_id, status, note, created_by, updated_by)
    values (v_j.kind, 'layer', v_j.layer_doc_number, v_j.layer_line_ref, v_j.layer_sku, v_j.layer_warehouse, -v_j.amount_cad, -v_j.amount_doc, v_j.currency_id, v_j.exchange_rate, 'reversal', v_j.id, v_j.source_number, v_j.id, 'pending', p_note, v_staff, v_staff)
    returning id into v_new;
    if v_j.status = 'posted' then v_post := public.inv_layer_post_cost_adjust(v_new); end if;
    return jsonb_build_object('reversal_id', v_new, 'reverses_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'amount_cad', -v_j.amount_cad,
                              'status', case when v_j.status = 'posted' then coalesce(v_post ->> 'status', 'posted') else 'pending' end, 'posting', v_post);
  end if;
  insert into public.inv_cost_adjust (kind, target_type, po_line_id, po_charge_alloc_id, amount_cad, amount_doc, currency_id, exchange_rate, source_type, source_id, source_number, reverses_id, status, note, created_by, updated_by)
  values (v_j.kind, v_j.target_type, v_j.po_line_id, v_j.po_charge_alloc_id, -v_j.amount_cad, -v_j.amount_doc, v_j.currency_id, v_j.exchange_rate, 'reversal', v_j.id, v_j.source_number, v_j.id, 'pending', p_note, v_staff, v_staff)
  returning id into v_new;
  if v_j.status = 'posted' then v_post := public.inv_layer_post_cost_adjust(v_new); end if;   -- 원래가 posted 면 지금 얹는다(같은 레이어 집합 · 반대 부호 · 자기 posted_on 자리)
  return jsonb_build_object('reversal_id', v_new, 'reverses_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'amount_cad', -v_j.amount_cad,
                            'status', case when v_j.status = 'posted' then coalesce(v_post ->> 'status', 'posted') else 'pending' end, 'posting', v_post);
end;
$$;
revoke all on function public.inv_cost_adjust_reverse(uuid, text) from public, anon;
grant execute on function public.inv_cost_adjust_reverse(uuid, text) to authenticated;
comment on function public.inv_cost_adjust_reverse(uuid, text) is 'po-disc-3 ⭐ 원가 조정 되돌림 창구(purchasing · 2026-10-09) — 같은 대상 · 반대 부호 · source_type reversal · reverses_id(유니크 — 한 번만) · 원래가 posted 면 곧바로 inv_layer_post_cost_adjust(자기 자리) · pending 이면 둘 다 pending(입고 확정이 둘 다 얹어 합 0) · 되돌림의 되돌림은 거부(새 사건을 올린다) · 원래 사건은 지우지 않는다 · cost-fix-1(2026-11-01): layer 대상은 자연키 칸 넷을 복사';
