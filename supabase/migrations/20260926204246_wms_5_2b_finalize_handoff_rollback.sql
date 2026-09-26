-- ⑤-2b WMS 창구 셋째 — 치수 · Finalize · 인계 · so_finalize 재발행 · 되돌리기 · 검토함 (2026-09-26 UTC · 토론토 2026-09-26 저녁)
-- 정본 so-module §24(24-h 판정 16~25 · 24-i · 24-j) · 지시서 ~/asung/prompts/wms-5-2b.md(판정 26 · ⬜6~⬜10 · 이견 4) · a1 = 20260926192314 · a2 = 20260926200918
-- 대상: [테스트 · Asung-IMS] 만 — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/wms-5-2b-verify.sql(-v mig)
-- ⛔⛔ 절대 조건(Caleb 2026-09-26): 운영 WMS(asung-WMS · wms.asung.ca)는 어떤 경우에도 멈추면 안 된다.
--     첫 문장 = 운영 가드(원본 supabase/ops/guard-test-only.sql 의 글자를 그대로 복사 · 검증 G0 이 임시 파일 diff 로 같음을 잰다).
--     흔적 셋 중 하나라도 있으면 WM501 로 멈춘다(OR · fail-closed): cron.job 에 wms-poll-orders/wms-auto-hold · inv_config.db_role <> 'test' · wms_health_runs 행 > 0
-- 하는 일(§1 순서):
--   1. 치수(판정 19) — wms_pallets 에 입력 칸(dim_length · dim_width · dim_height · dim_unit in|cm · weight · weight_unit lb|kg)과 저장 칸(length_in · width_in · height_in · weight_lb)
--      ⭐ 「DB 가 바꾼다」 = BEFORE 트리거 wms_pallet_dims(화면은 팔렛을 직접 쓴다 · auth_all · 판정 6 — 창구를 하나 더 세우면 화면이 두 길을 가진다 · 트리거는 어느 길로 써도 같다) · 메모 칸(height_note · weight_note) 그대로
--   2. 검토함(판정 26) — wms_order_review 한 줄 표(order_id → so restrict · reviewed · reviewed_by/at · cleared_by/at) + 창구 wms_review_set(p_so_id, p_reviewed) — fulfillment 화면 값 · 누가 · 언제는 서버가
--   3. wms_order_finalize — 운영 fulfillment_type(packing_list | direct) · finalized_by/at 의 자리(WMS 자기 표 · 안) · Undo Finalize 가 지운다(아카이브)
--   4. 인계 wms_so_handoff(p_so_id) — stable · invoker · authenticated(⬜7) · picks 는 so_finalize 입력 글자 그대로({line_id, bin, qty} · 판매 단위 · 세트 줄은 정수 세트) ·
--      인계 수량 = least(Σ 실제 칸 정수 단위, floor(verified/pack), 목표) · 칸 배분은 마지막 칸부터 줄인다(⬜6) · over_pick 은 반납(picks 밖) · units(팔렛 · 박스 · 치수 in·lb · items) · shorts
--   5. Finalize wms_finalize(p_so_ids) — 첫 줄 ims_require_write(fulfillment) · 창고 · ⬜8 검사 셋(① 뷰 all_packed ② 팔렛 담긴 수량 ≤ 팩 수량 · 없어도 됨 ③ 치수 없음은 경고) · so_wms_status(picking→packed · packed_at/by)
--   6. so_finalize 재발행 — 원본 20260924202425:209~419 바이트 그대로 + 더한 줄(e.picks 가 없으면 wms_so_handoff 의 picks · 있으면 그대로 · 판정 16) · comment 갱신
--   7. 되돌리기(⬜9 표 그대로 · wms_manage · manager 이상 · 한 트랜잭션 · 아카이브 → 무효화 → 삭제 순서 · 원장 사건 없음 ⬜10):
--      wms_rollback(p_so_id, p_action finalize|fulfillment|pack|pick|split) · wms_rollback_batch(p_task_id, p_kind pack|pick) · wms_unwave(p_wave_id) · 속 함수 wms_rb_archive · wms_rb_void
--      Void 는 없다(판정 21) · Finalize 뒤의 팩 · 픽 · 배치 되돌리기는 막는다(SO-13893 선례 · Undo Finalize 먼저) · 실수 무효화 화이트리스트(규칙 41 · SO-14129) · 과제 0 이면 picking→at_wms(판정 18)
-- ⚠️ WMS 창구는 so_ship · so_invoice_* · inv_* 를 부르지 않는다(판정 16) · 번호 시퀀스(so · 인보이스 · 크레딧)는 이 파일이 건드리지 않는다 · so_finalize 미리 보기는 번호를 당기지 않는다(검증 Q1)

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

-- ═══ 1) 치수 (판정 19) ═══
alter table public.wms_pallets
  add column dim_length  numeric,
  add column dim_width   numeric,
  add column dim_height  numeric,
  add column dim_unit    text,
  add column weight      numeric,
  add column weight_unit text,
  add column length_in   numeric,
  add column width_in    numeric,
  add column height_in   numeric,
  add column weight_lb   numeric,
  add constraint wms_pallets_dim_unit_ck    check (dim_unit is null or dim_unit in ('in', 'cm')),
  add constraint wms_pallets_weight_unit_ck check (weight_unit is null or weight_unit in ('lb', 'kg')),
  add constraint wms_pallets_dim_pair_ck    check ((dim_length is null and dim_width is null and dim_height is null) or dim_unit is not null),
  add constraint wms_pallets_weight_pair_ck check (weight is null or weight_unit is not null),
  add constraint wms_pallets_dim_pos_ck     check (coalesce(dim_length, 1) > 0 and coalesce(dim_width, 1) > 0 and coalesce(dim_height, 1) > 0 and coalesce(weight, 1) > 0);
create function public.wms_pallet_dims() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  new.length_in := case when new.dim_length is null then null when new.dim_unit = 'cm' then round(new.dim_length / 2.54, 2) else round(new.dim_length, 2) end;
  new.width_in  := case when new.dim_width  is null then null when new.dim_unit = 'cm' then round(new.dim_width  / 2.54, 2) else round(new.dim_width, 2)  end;
  new.height_in := case when new.dim_height is null then null when new.dim_unit = 'cm' then round(new.dim_height / 2.54, 2) else round(new.dim_height, 2) end;
  new.weight_lb := case when new.weight is null then null when new.weight_unit = 'kg' then round(new.weight / 0.45359237, 2) else round(new.weight, 2) end;
  return new;
end;
$$;
create trigger wms_pallet_dims before insert or update on public.wms_pallets for each row execute function public.wms_pallet_dims();
comment on column public.wms_pallets.dim_unit    is '⑤-2b(판정 19) 처음 넣은 치수의 단위 in|cm — 숫자 셋(dim_length·width·height)과 함께 남는다 · 저장 칸(*_in)은 트리거 wms_pallet_dims 가 인치로 바꿔 채운다(화면이 곱하지 않는다) · 모르는 단위는 CHECK 가 거부';
comment on column public.wms_pallets.weight_unit is '⑤-2b(판정 19) 처음 넣은 무게의 단위 lb|kg — weight 와 함께 남는다 · weight_lb 는 트리거가 파운드로(÷0.45359237 · round 2)';
comment on column public.wms_pallets.length_in   is '⑤-2b(판정 19) 저장 값 인치 — 오피스 화면 · 인계(wms_so_handoff units)는 늘 이 칸(in · lb)을 읽는다 · 메모 칸 height_note · weight_note 는 그대로';
comment on function public.wms_pallet_dims() is '⑤-2b(판정 19) BEFORE 트리거 — 입력 칸(숫자 · 단위)에서 저장 칸(in · lb)을 계산한다 · 화면이 직접 써도(auth_all) 창구로 써도 같은 값';

-- ═══ 2) 검토함 (판정 26) — 한 줄 표 + 창구 ═══
create table public.wms_order_review (
  order_id    uuid primary key references public.so (id) on delete restrict,
  reviewed    boolean not null default false,
  reviewed_by uuid references public.ims_staff (id) on delete restrict,
  reviewed_at timestamptz,
  cleared_by  uuid references public.ims_staff (id) on delete restrict,
  cleared_at  timestamptz
);
alter table public.wms_order_review enable row level security;
create policy auth_all on public.wms_order_review for all to authenticated using (true) with check (true);
comment on table public.wms_order_review is '⑤-2b(판정 26) 매니저 「검토함」 — 오더마다 한 줄: 지금 상태 + 마지막으로 켠 사람·시각 + 마지막으로 끈 사람·시각(이력 전부는 안 쌓는다 · 끄면 켠 기록이 남는다 — 운영 mgr_reviewed 셋 비우기 기각) · 쓰기는 wms_review_set';
create function public.wms_review_set(p_so_id uuid, p_reviewed boolean) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_r public.wms_order_review%rowtype;
begin
  perform public.ims_require_write('fulfillment', 'saved');            -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so s where s.id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_so.location_id) then
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_so.so_number;
  end if;
  insert into public.wms_order_review as r (order_id, reviewed, reviewed_by, reviewed_at, cleared_by, cleared_at)
  values (p_so_id, p_reviewed, case when p_reviewed then v_staff end, case when p_reviewed then now() end, case when not p_reviewed then v_staff end, case when not p_reviewed then now() end)
  on conflict (order_id) do update
    set reviewed    = excluded.reviewed,
        reviewed_by = case when excluded.reviewed then v_staff else r.reviewed_by end,
        reviewed_at = case when excluded.reviewed then now()   else r.reviewed_at end,
        cleared_by  = case when excluded.reviewed then r.cleared_by else v_staff end,
        cleared_at  = case when excluded.reviewed then r.cleared_at else now()   end
  returning * into v_r;
  return to_jsonb(v_r) || jsonb_build_object('so_number', v_so.so_number);
end;
$$;
comment on function public.wms_review_set(uuid, boolean) is '⑤-2b(판정 26) 검토함 켜기/끄기 — 첫 줄 ims_require_write(fulfillment) · ims_can_warehouse · 서버 시각 · 서버 사람 · 켜면 reviewed_by/at · 끄면 cleared_by/at(반대쪽 기록은 남는다)';
revoke all on function public.wms_review_set(uuid, boolean) from public, anon;
grant execute on function public.wms_review_set(uuid, boolean) to authenticated;

-- ═══ 3) wms_order_finalize — 운영 fulfillment_type · finalized_by/at 의 자리(WMS 자기 표) ═══
create table public.wms_order_finalize (
  order_id         uuid primary key references public.so (id) on delete restrict,
  fulfillment_type text not null,
  finalized_by     uuid not null references public.ims_staff (id) on delete restrict,
  finalized_at     timestamptz not null default now(),
  units            int not null default 0,
  units_without_dims int not null default 0,
  constraint wms_order_finalize_type_ck check (fulfillment_type in ('packing_list', 'direct'))
);
alter table public.wms_order_finalize enable row level security;
create policy auth_all on public.wms_order_finalize for all to authenticated using (true) with check (true);
comment on table public.wms_order_finalize is '⑤-2b Finalize 의 기록(운영 wms_orders.fulfillment_type · finalized_by · finalized_at 의 자리 · 규칙 13 통계) — packing_list = 팔렛/박스에 담긴 것이 하나라도 있다 · direct = 없다(픽업 · 즉시 출고) · wms_finalize 가 쓰고 wms_rollback(finalize) 가 아카이브하고 지운다 · SO 의 packed 와 짝(packed_at/by 는 so 에)';

-- ═══ 4) 인계 wms_so_handoff(p_so_id) — ⬜6 · ⬜7 (stable · invoker · authenticated · 오피스 미리 보기도 부른다) ═══
--   줄마다: 목표 = qty_ordered − qty_removed(판매 단위) · 실제 칸 EA = wms_pick_line_bins planned=false(완료된 픽 과제) · verified EA = 완료된 팩 과제의 줄 합
--   칸 단위 = floor(칸 EA ÷ pack_factor) · 인계 = least(Σ 칸 단위, floor(verified ÷ pack), 목표) · 인계 < Σ 칸 단위면 마지막 칸부터 줄인다 · over_pick 은 반납(picks 에 없다)
create function public.wms_so_handoff(p_so_id uuid) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_so     public.so%rowtype;
  v_all    boolean;
  l        record;  b record;
  v_ship   numeric;  v_sum numeric;  v_cut numeric;
  v_bins   jsonb;  v_picks jsonb := '[]'::jsonb;  v_shorts jsonb := '[]'::jsonb;  v_units jsonb;
  v_nodim  int;
  i        int;
begin
  select * into v_so from public.so s where s.id = p_so_id;
  if not found then raise exception 'Order not found'; end if;
  select coalesce(v.all_packed, false) into v_all from public.wms_order_pack_progress v where v.order_id = p_so_id;
  for l in
    select x.id, x.line_no, x.sku, x.pack_factor, x.qty_ordered - x.qty_removed as target,
           coalesce((select sum(kl.verified_base) from public.wms_pack_task_lines kl join public.wms_pack_tasks k on k.id = kl.pack_task_id
                     where kl.order_line_id = x.id and k.status = 'completed'), 0) as verified_ea,
           coalesce((select jsonb_agg(jsonb_build_object('bin', g.bin, 'units', g.units) order by g.first_id)
                     from (select pb.bin, min(pb.id) as first_id, floor(sum(pb.qty_base) / x.pack_factor) as units
                           from public.wms_pick_line_bins pb join public.wms_pick_task_lines pl on pl.id = pb.pick_task_line_id join public.wms_pick_tasks t on t.id = pl.pick_task_id
                           where pl.order_line_id = x.id and not pb.planned and t.status = 'completed' group by pb.bin) g), '[]'::jsonb) as bins
    from public.so_line x where x.so_id = p_so_id order by x.line_no
  loop
    select coalesce(sum((e->>'units')::numeric), 0) into v_sum from jsonb_array_elements(l.bins) e;
    v_ship := least(v_sum, floor(l.verified_ea / l.pack_factor), l.target);
    if v_ship < 0 then v_ship := 0; end if;
    v_cut := v_sum - v_ship;  v_bins := l.bins;
    i := jsonb_array_length(v_bins) - 1;
    while v_cut > 0 and i >= 0 loop                              -- 마지막 칸부터 줄인다(⬜6)
      v_bins := jsonb_set(v_bins, array[i::text, 'units'], to_jsonb(greatest((v_bins->i->>'units')::numeric - v_cut, 0)));
      v_cut := v_cut - least(v_cut, (l.bins->i->>'units')::numeric);  i := i - 1;
    end loop;
    v_picks := v_picks || coalesce((select jsonb_agg(jsonb_build_object('line_id', l.id, 'bin', e->>'bin', 'qty', (e->>'units')::numeric)) from jsonb_array_elements(v_bins) e where (e->>'units')::numeric > 0), '[]'::jsonb);
    if v_ship < l.target then
      v_shorts := v_shorts || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'target', l.target, 'ship', v_ship);
    end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('unit_id', u.id, 'unit_type', u.unit_type, 'label', u.label, 'parent_unit_id', u.parent_id, 'status', u.status,
           'length_in', u.length_in, 'width_in', u.width_in, 'height_in', u.height_in, 'weight_lb', u.weight_lb, 'height_note', u.height_note, 'weight_note', u.weight_note,
           'items', coalesce((select jsonb_agg(jsonb_build_object('line_id', it.order_line_id, 'qty', round(it.qty / sl.pack_factor, 4), 'qty_base', it.qty) order by sl.line_no)
                              from (select pi.order_line_id, sum(pi.qty_base) as qty from public.wms_pallet_items pi where pi.pallet_id = u.id and pi.order_id = p_so_id group by pi.order_line_id) it
                              join public.so_line sl on sl.id = it.order_line_id), '[]'::jsonb)) order by u.parent_id nulls first, u.id), '[]'::jsonb),
         count(*) filter (where u.length_in is null or u.width_in is null or u.height_in is null or u.weight_lb is null)
    into v_units, v_nodim
  from public.wms_pallets u
  where u.order_id = p_so_id or u.parent_id in (select p2.id from public.wms_pallets p2 where p2.order_id = p_so_id);
  return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'status', v_so.status, 'all_packed', v_all,
                            'picks', v_picks, 'units', v_units, 'shorts', v_shorts, 'units_without_dims', coalesce(v_nodim, 0));
end;
$$;
comment on function public.wms_so_handoff(uuid) is
  '⑤-2b 인계(⬜6 · ⬜7 · 판정 16) — WMS 가 SO 에 넘기는 것을 읽는 창구(stable · invoker · authenticated) · picks [{line_id, bin, qty}] 는 so_finalize 입력 글자 그대로(판매 단위 · 세트 줄은 정수 세트 · 완료된 픽의 실제 칸 wms_pick_line_bins planned=false) · 인계 = least(Σ 칸 단위, floor(verified/pack), 목표) · 마지막 칸부터 줄인다 · over_pick 은 반납(밖) · units(팔렛·박스 · 치수 in·lb · items) · shorts(목표 아래 줄 → so_ship 의 pick_short 형제) · so_finalize 가 picks 를 안 받으면 이것을 쓴다';
revoke all on function public.wms_so_handoff(uuid) from public, anon;
grant execute on function public.wms_so_handoff(uuid) to authenticated;

-- ═══ 5) Finalize wms_finalize(p_so_ids) — ⬜8 검사 셋 · picking → packed ═══
create function public.wms_finalize(p_so_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_id uuid;  v_so public.so%rowtype;  v_all boolean;  v_bad text;
  v_placed boolean;  v_units int;  v_nodim int;  v_type text;
  v_out jsonb := '[]'::jsonb;  v_warn text[] := '{}';
begin
  perform public.ims_require_write('fulfillment', 'saved');            -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  if p_so_ids is null or cardinality(p_so_ids) = 0 then raise exception 'No orders given — nothing was saved'; end if;
  -- ① 검사 전부(잠금 · 하나라도 막히면 전체 거부)
  foreach v_id in array p_so_ids loop
    select * into v_so from public.so s where s.id = v_id for update;
    if not found then raise exception 'Order not found (%) — nothing was saved', v_id; end if;
    if not public.ims_can_warehouse(v_so.location_id) then          -- ⭐ 둘째
      raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_so.so_number;
    end if;
    if v_so.status <> 'picking' then
      raise exception 'Order % is % — only an order in warehouse work (picking) can be finalized — nothing was saved', v_so.so_number, v_so.status;
    end if;
    select coalesce(v.all_packed, false) into v_all from public.wms_order_pack_progress v where v.order_id = v_id;
    if not coalesce(v_all, false) then
      raise exception 'Order % — not every batch is picked and packed yet (%) — nothing was saved', v_so.so_number,
        coalesce((select v.packs_done || '/' || v.pick_batches || ' packed' from public.wms_order_pack_progress v where v.order_id = v_id), 'no pick tasks');
    end if;
    select string_agg(format('line %s: %s on pallets but %s packed', sl.line_no, pi.q, coalesce(pk.q, 0)), '; ' order by sl.line_no) into v_bad
    from (select order_line_id, sum(qty_base) as q from public.wms_pallet_items where order_id = v_id group by 1) pi
    join public.so_line sl on sl.id = pi.order_line_id
    left join (select kl.order_line_id, sum(kl.verified_base) as q from public.wms_pack_task_lines kl join public.wms_pack_tasks k on k.id = kl.pack_task_id where k.order_id = v_id and k.status = 'completed' group by 1) pk on pk.order_line_id = pi.order_line_id
    where pi.q > coalesce(pk.q, 0);
    if v_bad is not null then raise exception 'Order % — more on pallets than was packed (%) — nothing was saved', v_so.so_number, v_bad; end if;
  end loop;
  -- ② 기록 + 전이
  foreach v_id in array p_so_ids loop
    select * into v_so from public.so s where s.id = v_id;
    v_placed := exists (select 1 from public.wms_pallet_items pi where pi.order_id = v_id);
    select count(*), count(*) filter (where u.length_in is null or u.width_in is null or u.height_in is null or u.weight_lb is null) into v_units, v_nodim
    from public.wms_pallets u where u.order_id = v_id or u.parent_id in (select p2.id from public.wms_pallets p2 where p2.order_id = v_id);
    v_type := case when v_placed then 'packing_list' else 'direct' end;
    if v_nodim > 0 then v_warn := array_append(v_warn, format('units_without_dims:%s:%s', v_so.so_number, v_nodim)); end if;
    insert into public.wms_order_finalize (order_id, fulfillment_type, finalized_by, finalized_at, units, units_without_dims)
    values (v_id, v_type, v_staff, now(), v_units, v_nodim);
    perform public.so_wms_status(v_id, 'packed', v_staff);
    v_out := v_out || jsonb_build_object('so_id', v_id, 'so_number', v_so.so_number, 'fulfillment_type', v_type, 'units', v_units, 'units_without_dims', v_nodim,
                                         'shorts', (public.wms_so_handoff(v_id))->'shorts');
  end loop;
  return jsonb_build_object('finalized', v_out, 'count', jsonb_array_length(v_out), 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.wms_finalize(uuid[]) is
  '⑤-2b Finalize(판정 16 · 18 · ⬜8) — 창고의 끝 = 출하 준비 완료 · 첫 줄 ims_require_write(fulfillment) · ims_can_warehouse · picking 오더만 · 검사 셋: ① 뷰 all_packed ② 팔렛에 담긴 수량 ≤ 팩 수량(팔렛은 없어도 된다 = direct · 규칙 13) ③ 치수 없음은 경고 units_without_dims · 부족분은 막지 않는다(인계 shorts → 오피스 so_finalize 의 pick_short) · wms_order_finalize 기록 · so_wms_status(picking→packed · packed_at/by) · 재고 · 인보이스는 건드리지 않는다(오피스 so_finalize)';
revoke all on function public.wms_finalize(uuid[]) from public, anon;
grant execute on function public.wms_finalize(uuid[]) to authenticated;

-- ═══ 6) so_finalize 재발행 — 원본 20260924202425:209~419 바이트 그대로 + 더한 줄 3(주석 1 · picks 채우기 1 · 파일 앞머리 create or replace) · comment 갱신 ═══
--   ⚠️ 재발행 결과가 같은지는 검증 F 절(미리 보기 · picks 생략 → 인계 · picks 있음 → 그대로 · 번호 무변)
create or replace function public.so_finalize(p_orders jsonb, p_commit boolean default true, p_shipped_on date default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_reasons  constant text[] := array['customer_removed', 'not_wanted', 'other'];
  v_staff    uuid;
  v_on       date;
  v_n        int;  v_cnt int;
  v_bad      text;
  e          jsonb;  x jsonb;
  v_so       public.so%rowtype;
  v_l        public.so_line%rowtype;
  v_c        public.customer%rowtype;
  v_acct     public.ref_account%rowtype;
  v_ch       public.so_charge%rowtype;
  q          record;
  v_qty      numeric;  v_remaining numeric;  v_new_unit numeric;
  v_reason   text;  v_key text;  k text;
  v_next     int;
  v_removed  jsonb;  v_repriced jsonb;  v_charges jsonb;  v_ship jsonb;  v_iss jsonb;
  v_orders   jsonb := '[]'::jsonb;
  v_groups   jsonb := '{}'::jsonb;
  v_invoices jsonb := '[]'::jsonb;
  v_ids      uuid[];
  v_warn     text[] := '{}';
  v_tw       text[];
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 8: 마무리는 오더 담당(sales)부터 · 역할 문 없음(R5 의 예외)
  v_staff := public.so_current_staff();
  v_on := coalesce(p_shipped_on, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Ship date % is in the future — nothing was saved', v_on; end if;
  if p_orders is null or jsonb_typeof(p_orders) <> 'array' or jsonb_array_length(p_orders) = 0 then
    raise exception 'p_orders must be a JSON array of orders — nothing was saved';
  end if;
  if exists (select 1 from jsonb_array_elements(p_orders) t where jsonb_typeof(t) <> 'object' or nullif(t->>'so_id', '') is null) then
    raise exception 'Every order needs a so_id — nothing was saved';
  end if;
  select count(*), count(distinct t->>'so_id') into v_cnt, v_n from jsonb_array_elements(p_orders) t;
  if v_n <> v_cnt then raise exception 'The same order is listed twice — nothing was saved'; end if;
  -- ⑤-2b(판정 16 · ⬜7): picks 가 없으면 WMS 인계(wms_so_handoff)의 picks 를 쓴다(있으면 그대로 — 오피스가 고칠 길)
  select jsonb_agg(case when t.e ? 'picks' then t.e else t.e || jsonb_build_object('picks', (public.wms_so_handoff((t.e->>'so_id')::uuid))->'picks') end order by t.ord) into p_orders from jsonb_array_elements(p_orders) with ordinality t(e, ord);

  -- ① 검사 — 오더마다(잠금) · 하나라도 막히면 전체 거부 · 오더 번호로 말한다
  for e in select t from jsonb_array_elements(p_orders) t loop
    select * into v_so from public.so s where s.id = (e->>'so_id')::uuid for update;
    if not found then raise exception 'Order % not found — nothing was saved', e->>'so_id'; end if;
    if v_so.status <> 'packed' then
      raise exception 'Order % is % — only a packed order (warehouse work finished) can be finalized here — nothing was saved', v_so.so_number, v_so.status;
    end if;
    if v_so.bill_to_customer_id is null then raise exception 'Order % has no bill-to customer — nothing was saved', v_so.so_number; end if;
    -- 뺀 몫(판정 5) — 모양 · 줄 · 수량 · 사유 · 중복
    if e ? 'removed' and jsonb_typeof(e->'removed') not in ('array', 'null') then
      raise exception 'Order %: removed must be an array of {line_id, qty, reason, note} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = nullif(x->>'line_id', '')::uuid and l.so_id = v_so.id;
      if not found then raise exception 'Order %: removed line % is not on this order — nothing was saved', v_so.so_number, coalesce(x->>'line_id', '?'); end if;
      if v_l.qty_removed > 0 then raise exception 'Order % line % already has a removed quantity — nothing was saved', v_so.so_number, v_l.line_no; end if;
      v_qty := case when (x->>'qty') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (x->>'qty')::numeric else null end;
      if v_qty is null or v_qty <= 0 then raise exception 'Order % line %: removed qty must be a positive number — nothing was saved', v_so.so_number, v_l.line_no; end if;
      if v_qty > v_l.qty_ordered then raise exception 'Order % line %: cannot remove % — only % ordered — nothing was saved', v_so.so_number, v_l.line_no, v_qty, v_l.qty_ordered; end if;
      v_reason := nullif(trim(x->>'reason'), '');
      if v_reason is null or v_reason <> all (c_reasons) then
        raise exception 'Order % line %: removed reason must be one of customer_removed, not_wanted, other — nothing was saved', v_so.so_number, v_l.line_no;
      end if;
      if v_reason = 'other' and nullif(trim(x->>'note'), '') is null then
        raise exception 'Order % line %: reason other needs a note — nothing was saved', v_so.so_number, v_l.line_no;
      end if;
    end loop;
    if (select count(*) - count(distinct t->>'line_id') from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t) > 0 then
      raise exception 'Order %: the same line is removed twice — nothing was saved', v_so.so_number;
    end if;
    -- 판정 9 — 모든 줄을 다 뺐다 → 거부 + 길
    if not exists (select 1 from public.so_line l
                   left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t where (t->>'line_id')::uuid = l.id) rm on true
                   where l.so_id = v_so.id and l.qty_ordered - coalesce(rm.q, 0) > 0) then
      raise exception 'Order % — every line was removed, there is nothing to ship: roll the order back in WMS, then cancel it (so_unconfirm / so_cancel) — nothing was saved', v_so.so_number;
    end if;
    -- 픽 — 모양 · 줄 · 수량 · 목표 초과(칸은 실행 때 so_ship 이 본다)
    if e->'picks' is null or jsonb_typeof(e->'picks') <> 'array' or jsonb_array_length(e->'picks') = 0 then
      raise exception 'Order %: picks must be a JSON array of {line_id, bin, qty} — nothing was saved', v_so.so_number;
    end if;
    if exists (select 1 from jsonb_array_elements(e->'picks') t where nullif(t->>'line_id', '') is null or (t->>'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' or (t->>'qty')::numeric <= 0) then
      raise exception 'Order %: every pick needs a line_id and a positive qty — nothing was saved', v_so.so_number;
    end if;
    select string_agg(distinct t->>'line_id', ', ') into v_bad from jsonb_array_elements(e->'picks') t
    where not exists (select 1 from public.so_line l where l.id = (t->>'line_id')::uuid and l.so_id = v_so.id);
    if v_bad is not null then raise exception 'Order %: pick line % is not on this order — nothing was saved', v_so.so_number, v_bad; end if;
    select string_agg(format('line %s picked %s but %s to ship', l.line_no, pk.q, l.qty_ordered - coalesce(rm.q, 0)), '; ' order by l.line_no) into v_bad
    from public.so_line l
    join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(e->'picks') t where (t->>'line_id')::uuid = l.id) pk on true
    left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t where (t->>'line_id')::uuid = l.id) rm on true
    where l.so_id = v_so.id and pk.q > l.qty_ordered - coalesce(rm.q, 0);
    if v_bad is not null then raise exception 'Order %: over-pick — % — over-pick goes back to its bin — nothing was saved', v_so.so_number, v_bad; end if;
    -- 운임(판정 4 · so_charge_set 의 규칙)
    if e ? 'charges' and jsonb_typeof(e->'charges') not in ('array', 'null') then
      raise exception 'Order %: charges must be an array of {charge_id, name, amount, description, account_id} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'charges', 'null'::jsonb), '[]'::jsonb)) t loop
      if nullif(trim(x->>'name'), '') is null then raise exception 'Order %: a charge needs a name — nothing was saved', v_so.so_number; end if;
      if (x->>'amount') !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then raise exception 'Order %: charge % needs an amount — nothing was saved', v_so.so_number, trim(x->>'name'); end if;
      if (x->>'amount')::numeric < 0 then raise exception 'Order %: a charge cannot be negative — use a credit note — nothing was saved', v_so.so_number; end if;
      if nullif(x->>'charge_id', '') is not null and not exists (select 1 from public.so_charge c where c.id = (x->>'charge_id')::uuid and c.so_id = v_so.id) then
        raise exception 'Order %: charge % is not on this order — nothing was saved', v_so.so_number, x->>'charge_id';
      end if;
      if nullif(x->>'account_id', '') is not null and not exists (select 1 from public.ref_account a where a.id = (x->>'account_id')::uuid) then
        raise exception 'Order %: account % not found — nothing was saved', v_so.so_number, x->>'account_id';
      end if;
    end loop;
  end loop;

  -- ②~⑤ 오더마다(주어진 순서) — 실행이면 쓰고 미리 보기면 계산만
  for e in select t from jsonb_array_elements(p_orders) t loop
    select * into v_so from public.so s where s.id = (e->>'so_id')::uuid;
    v_removed := '[]'::jsonb;  v_repriced := '[]'::jsonb;  v_charges := '[]'::jsonb;

    -- ② 택배사 · 추적번호 · 배송 메모(열쇠가 온 것만) · 운임 줄(새로 · 또는 charge_id 로 고침 · 세금은 오더 규칙 · 기본 계정 _99_)
    if p_commit and (e ? 'carrier' or e ? 'tracking_number' or e ? 'shipping_notes') then
      update public.so s set
        carrier         = case when e ? 'carrier'         then nullif(trim(e->>'carrier'), '')         else s.carrier end,
        tracking_number = case when e ? 'tracking_number' then nullif(trim(e->>'tracking_number'), '') else s.tracking_number end,
        shipping_notes  = case when e ? 'shipping_notes'  then nullif(trim(e->>'shipping_notes'), '')  else s.shipping_notes end,
        updated_by      = v_staff
      where s.id = v_so.id;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'charges', 'null'::jsonb), '[]'::jsonb)) t loop
      v_acct := null;
      if nullif(x->>'account_id', '') is not null then
        select * into v_acct from public.ref_account a where a.id = (x->>'account_id')::uuid;
      elsif nullif(x->>'charge_id', '') is null then
        select * into v_acct from public.ref_account a where a.code = '_99_';                      -- 기본 Freight Sales · 없으면 비우고 알린다(so_charge_set 과 같다)
        if not found then v_warn := array_append(v_warn, 'charge_account_unset:' || v_so.so_number); end if;
      end if;
      if p_commit then
        if nullif(x->>'charge_id', '') is null then
          select coalesce(max(c.line_no), 0) + 1 into v_next from public.so_charge c where c.so_id = v_so.id;
          insert into public.so_charge (so_id, line_no, name, description, amount, tax_rule, account_id, account_code, updated_by)
          values (v_so.id, v_next, trim(x->>'name'), nullif(trim(x->>'description'), ''), (x->>'amount')::numeric, v_so.tax_rule, v_acct.id, v_acct.code, v_staff)
          returning * into v_ch;
        else
          update public.so_charge c set
            name = trim(x->>'name'), description = nullif(trim(x->>'description'), ''), amount = (x->>'amount')::numeric, tax_rule = v_so.tax_rule,
            account_id = case when v_acct.id is not null then v_acct.id else c.account_id end, account_code = case when v_acct.id is not null then v_acct.code else c.account_code end, updated_by = v_staff
          where c.id = (x->>'charge_id')::uuid returning * into v_ch;
        end if;
        v_charges := v_charges || jsonb_build_object('charge_id', v_ch.id, 'line_no', v_ch.line_no, 'name', v_ch.name, 'amount', v_ch.amount, 'tax_rule', v_ch.tax_rule, 'account_code', v_ch.account_code);
      else
        v_charges := v_charges || jsonb_build_object('charge_id', nullif(x->>'charge_id', ''), 'name', trim(x->>'name'), 'amount', (x->>'amount')::numeric, 'tax_rule', v_so.tax_rule, 'account_code', v_acct.code, 'preview', true);
      end if;
    end loop;

    -- ③ 뺀 몫(판정 5) + 시스템 줄 다시 견적(판정 6 · 할인만 · 남은 수량 > 0 · 사람이 정한 줄은 그대로)
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = (x->>'line_id')::uuid;
      v_qty := (x->>'qty')::numeric;  v_remaining := v_l.qty_ordered - v_qty;
      if p_commit then
        update public.so_line set qty_removed = v_qty, removed_reason = nullif(trim(x->>'reason'), ''), removed_note = nullif(trim(x->>'note'), ''), removed_at = now(), removed_by = v_staff, updated_by = v_staff
        where id = v_l.id;
      end if;
      v_removed := v_removed || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'qty_ordered', v_l.qty_ordered, 'qty_removed', v_qty, 'remaining', v_remaining,
                                                   'reason', nullif(trim(x->>'reason'), ''), 'free', v_l.free_reason is not null);
      if v_remaining > 0 and not v_l.price_override and v_l.discount_source is distinct from 'manual' then
        select * into q from public.so_line_quote(v_so, v_l.product_id, v_remaining);
        v_new_unit := case when v_l.list_price is null then null else v_l.list_price * (1 - q.discount_pct / 100) end;
        if p_commit then perform public.so_line_requote(v_l.id, v_remaining, false); end if;
        v_repriced := v_repriced || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'qty', v_remaining,
                                                       'old_unit_price', v_l.unit_price, 'new_unit_price', v_new_unit, 'old_discount_pct', v_l.discount_pct, 'new_discount_pct', q.discount_pct,
                                                       'old_discount_source', v_l.discount_source, 'new_discount_source', q.discount_source, 'changed', v_new_unit is distinct from v_l.unit_price);
      end if;
    end loop;

    -- ④ 출고(so_ship · 목표 = 주문 − 뺀 것 · 그 아래 차이만 pick_short 판정 7) — 미리 보기는 줄별 계산만(칸 검사·원장은 실행 때)
    if p_commit then
      v_ship := public.so_ship(v_so.id, e->'picks', v_staff, v_on);
      select array_agg(v_so.so_number || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_ship->'warnings', '[]'::jsonb)) as t(w);
      v_warn := v_warn || coalesce(v_tw, '{}');
    else
      select jsonb_build_object('preview', true,
               'lines', coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'ordered', l.qty_ordered, 'removed', coalesce(rm.q, 0), 'to_ship', l.qty_ordered - coalesce(rm.q, 0),
                                                              'picked', coalesce(pk.q, 0), 'short', l.qty_ordered - coalesce(rm.q, 0) - coalesce(pk.q, 0)) order by l.line_no), '[]'::jsonb),
               'backorder_lines', count(*) filter (where l.qty_ordered - coalesce(rm.q, 0) - coalesce(pk.q, 0) > 0))
        into v_ship
      from public.so_line l
      left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(e->'picks') t where (t->>'line_id')::uuid = l.id) pk on true
      left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t where (t->>'line_id')::uuid = l.id) rm on true
      where l.so_id = v_so.id;
    end if;

    -- ⑤ 묶음 열쇠(판정 2) — 청구처 · 청구처 설정이 켜졌으면 오더의 손님(매장) · invoice_group 이 오면 그것(청구처 안에서 · 직원이 바꾼 묶음)
    select * into v_c from public.customer c where c.id = v_so.bill_to_customer_id;
    v_key := v_so.bill_to_customer_id::text || '|' || coalesce(nullif(trim(e->>'invoice_group'), ''), case when coalesce(v_c.invoice_split_by_store, false) then 'store:' || v_so.customer_id::text else '' end);
    v_groups := jsonb_set(v_groups, array[v_key], coalesce(v_groups->v_key, '[]'::jsonb) || to_jsonb(v_so.id));
    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'invoice_group', v_key, 'removed', v_removed, 'repriced', v_repriced, 'charges', v_charges, 'ship', v_ship);
  end loop;

  -- ⑥ 발행 — 묶음마다 한 장(so_invoice_issue · 발행일 = 오늘 ims_today · §16 판정 5) · 미리 보기는 몇 장 · 어느 오더
  for k in select t.key_txt from jsonb_object_keys(v_groups) as t(key_txt) order by t.key_txt loop   -- 별칭은 변수 이름(x · e · k)과 다르게
    select array_agg(t.v::uuid) into v_ids from jsonb_array_elements_text(v_groups->k) as t(v);
    if p_commit then
      v_iss := public.so_invoice_issue(v_ids, v_staff, null);
      select array_agg((v_iss->>'invoice_number') || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_iss->'warnings', '[]'::jsonb)) as t(w);
      v_warn := v_warn || coalesce(v_tw, '{}');
      v_invoices := v_invoices || jsonb_build_object('group', k, 'invoice_id', v_iss->'invoice_id', 'invoice_number', v_iss->'invoice_number', 'issued_on', v_iss->'issued_on', 'due_on', v_iss->'due_on',
                                                     'orders', (select jsonb_agg(o->>'so_number') from jsonb_array_elements(v_iss->'orders') o), 'totals', v_iss->'totals', 'warnings', v_iss->'warnings');
    else
      v_invoices := v_invoices || jsonb_build_object('group', k, 'preview', true, 'orders', (select jsonb_agg(s.so_number order by s.so_number) from public.so s where s.id = any(v_ids)), 'order_count', array_length(v_ids, 1));
    end if;
  end loop;

  return jsonb_build_object('committed', p_commit, 'shipped_on', v_on, 'orders', v_orders, 'invoices', v_invoices, 'invoice_count', jsonb_array_length(v_invoices), 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_finalize(jsonb, boolean, date) is
  '⭐⭐ 오피스 마무리(so-module §17 판정 1 · ⓐ2 · 2026-09-24 · ⑤-2b 재발행 2026-09-26) — definer · 첫 줄 ims_require_write(sales) · 역할 문 없음(판정 8 · R5 예외) · packed 오더 묶음을 한 트랜잭션에 출고 + 발행. p_orders [{so_id, picks?, removed?, charges?, carrier?, tracking_number?, shipping_notes?, invoice_group?}] · ⭐ picks 가 없으면 WMS 인계 wms_so_handoff 의 picks(판정 16 · §24-h) · ① 검사 전부(하나라도 막히면 전체 거부 · 판정 9 모든 줄을 뺀 오더 거부 + 길) ② 운임·택배사·추적번호·메모(판정 4) ③ 뺀 몫 so_line.qty_removed(판정 5 · 백오더 아님 · 할당은 so_ship 이 released) + 시스템 줄 다시 견적(판정 6 · 할인만) ④ so_ship(목표 = 주문 − 뺀 것 · 차이만 pick_short 판정 7) ⑤ 묶음(bill_to_customer_id · 청구처 invoice_split_by_store 면 매장 · invoice_group) ⑥ so_invoice_issue ⑦ 반환 orders[removed · repriced 이전→새 · charges · ship] · invoices[] · invoice_count · warnings. p_commit false = 읽기만(번호 없음 · 칸 검사는 실행 때)';

-- ═══ 7) 되돌리기 (⬜9 · ⬜10 · 규칙 14 · 41) — 속 함수 둘 + 창구 셋 · 아카이브 → 무효화 → 삭제 · 한 트랜잭션 · 원장 사건 없음 ═══
create function public.wms_rb_archive(p_staff uuid, p_action text, p_so_id uuid, p_so_number text, p_label text, p_table text, p_pred text) returns int
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_n int;
begin
  execute format('insert into public.wms_rollback_archive (archived_by, action, order_id, order_number, batch_label, src_table, row_data) select $1, $2, $3, $4, $5, %L, to_jsonb(t) from public.%I t where %s', p_table, p_table, p_pred)
  using p_staff, p_action, p_so_id, p_so_number, p_label;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.wms_rb_archive(uuid, text, uuid, text, text, text, text) from public, anon, authenticated;
comment on function public.wms_rb_archive(uuid, text, uuid, text, text, text, text) is '⑤-2b 속 함수 — 지우기 전에 행을 wms_rollback_archive 에 통째로(to_jsonb) · 술어는 창구가 만든다(사람 입력 아님) · authenticated 에서 뺐다';
create function public.wms_rb_void(p_staff uuid, p_link text, p_ids bigint[], p_reasons text[], p_why text) returns int
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_n int;
begin
  if p_link not in ('pick_task_id', 'pack_task_id') then raise exception 'wms_rb_void: bad link %', p_link; end if;
  execute format('update public.wms_worker_mistakes set voided_at = now(), voided_by = $1, voided_reason = $2 where %I = any($3) and reason = any($4) and voided_at is null and not cin7_corrected', p_link)
  using p_staff, p_why, p_ids, p_reasons;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.wms_rb_void(uuid, text, bigint[], text[], text) from public, anon, authenticated;
comment on function public.wms_rb_void(uuid, text, bigint[], text[], text) is '⑤-2b 속 함수 — 실수 무효화(삭제 아님 · 규칙 41 화이트리스트 · 링크 칸으로만 · cin7_corrected 는 손대지 않는다) · 팩 = short_after_pack·over_pick·pack_scan_mistake · 픽 = short_pick · stock_short 는 리포트라 무관';

create function public.wms_rollback(p_so_id uuid, p_action text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_pack constant text[] := array['short_after_pack', 'over_pick', 'pack_scan_mistake'];
  v_staff uuid;  v_so public.so%rowtype;  v_fin public.wms_order_finalize%rowtype;
  v_ids bigint[];  v_wids bigint[];  v_wid bigint;
  v_arch int := 0;  v_void int := 0;  v_reopen int := 0;  v_status text;  v_from text;  v_to text;  v_orig uuid;  i int;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');
  v_staff := public.so_current_staff();
  if p_action not in ('finalize', 'fulfillment', 'pack', 'pick', 'split') then raise exception 'Unknown rollback action % — nothing was saved', p_action; end if;
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_so.location_id) then              -- ⭐ 둘째
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_so.so_number;
  end if;
  select * into v_fin from public.wms_order_finalize f where f.order_id = p_so_id;
  if p_action = 'finalize' then
    if v_so.status <> 'packed' or v_fin.order_id is null then raise exception 'Order % is not finalized (%) — nothing was saved', v_so.so_number, v_so.status; end if;
  else
    if v_so.status = 'packed' or v_fin.order_id is not null then       -- SO-13893 벨트: Finalize 뒤에는 팩 · 픽 · 배치를 되돌리지 않는다
      raise exception 'Order % is finalized — use Undo Finalize first — nothing was saved', v_so.so_number;
    end if;
    if v_so.status <> 'picking' then raise exception 'Order % is % — nothing to roll back here — nothing was saved', v_so.so_number, v_so.status; end if;
  end if;
  v_status := v_so.status;
  if p_action in ('finalize', 'fulfillment') then
    -- 팔렛 · 박스 · 담긴 것(운영 deleteFulfillmentRows) — 담긴 것 삭제 → 빈 유닛(담긴 것 0 · 자식 0) 삭제 · finalize 기록 삭제 · SO packed → picking
    v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_so.so_number, null, 'wms_pallet_items', format('order_id = %L', p_so_id));
    delete from public.wms_pallet_items where order_id = p_so_id;
    for i in 1 .. 2 loop                                               -- 두 단계: 빈 박스(자식) → 빈 팔렛(부모) · 담긴 것이 남은 유닛은 둔다(운영 deleteFulfillmentRows)
      v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_so.so_number, null, 'wms_pallets',
                  format('(order_id = %L or parent_id in (select id from public.wms_pallets where order_id = %L)) and not exists (select 1 from public.wms_pallet_items i where i.pallet_id = t.id) and not exists (select 1 from public.wms_pallets c where c.parent_id = t.id)', p_so_id, p_so_id));
      delete from public.wms_pallets u where (u.order_id = p_so_id or u.parent_id in (select id from public.wms_pallets where order_id = p_so_id))
        and not exists (select 1 from public.wms_pallet_items i where i.pallet_id = u.id) and not exists (select 1 from public.wms_pallets c where c.parent_id = u.id);
    end loop;
    if p_action = 'finalize' then
      v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_so.so_number, null, 'wms_order_finalize', format('order_id = %L', p_so_id));
      delete from public.wms_order_finalize where order_id = p_so_id;
      perform public.so_wms_status(p_so_id, 'picking', v_staff);
      v_status := 'picking';  v_orig := v_fin.finalized_by;
    end if;
    v_from := case p_action when 'finalize' then 'finalized' else 'fulfilled' end;  v_to := 'pack_complete';
  elsif p_action = 'pack' then
    if exists (select 1 from public.wms_pallet_items i where i.order_id = p_so_id) then raise exception 'Order % has items on pallets — Undo Fulfillment first — nothing was saved', v_so.so_number; end if;
    select coalesce(array_agg(id), '{}') into v_ids from public.wms_pack_tasks where order_id = p_so_id;
    select assigned_to into v_orig from public.wms_pack_tasks where order_id = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_so.so_number, null, 'wms_pack_tasks', format('order_id = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_so.so_number, null, 'wms_pack_task_lines', format('pack_task_id = any(%L::bigint[])', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pack_task_id', v_ids, c_pack, 'pack rollback (order ' || v_so.so_number || ')');
    update public.wms_worker_mistakes set reason = 'short_pick', resolved_by = null, resolved_at = null   -- 팩 회복을 다시 연다(오더 단위 · 규칙 14 양방향)
     where order_id = p_so_id and reason = 'resolved_pack_recovery' and voided_at is null and not cin7_corrected;
    get diagnostics v_reopen = row_count;
    delete from public.wms_pack_tasks where order_id = p_so_id;        -- 줄은 cascade
    v_from := 'pack_complete';  v_to := 'pick_complete';
  elsif p_action = 'pick' then
    if exists (select 1 from public.wms_pack_tasks k where k.order_id = p_so_id) then raise exception 'Order % has packing — Undo Pack first — nothing was saved', v_so.so_number; end if;
    select coalesce(array_agg(id), '{}') into v_ids from public.wms_pick_tasks where order_id = p_so_id;
    select assigned_to into v_orig from public.wms_pick_tasks where order_id = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_so.so_number, null, 'wms_pick_tasks', format('order_id = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_so.so_number, null, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_so.so_number, null, 'wms_pick_line_bins', format('not planned and pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'pick reset (order ' || v_so.so_number || ')');
    delete from public.wms_pick_line_bins b where not b.planned and b.pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(v_ids));
    update public.wms_pick_task_lines set picked_base = 0, status = 'pending', verification_method = null, picked_at = null, picked_by = null where pick_task_id = any(v_ids);
    update public.wms_pick_tasks set status = 'pending', assigned_to = null, started_at = null, completed_at = null, completed_by = null, heartbeat_at = null, work_started = false, held_by = null, session_id = null where order_id = p_so_id;
    v_from := 'pick_complete';  v_to := 'pick_reset';
  else   -- split
    if exists (select 1 from public.wms_pack_tasks k where k.order_id = p_so_id) then raise exception 'Order % has packing — Undo Pack first — nothing was saved', v_so.so_number; end if;
    select coalesce(array_agg(id), '{}'), coalesce(array_agg(distinct wave_id) filter (where wave_id is not null), '{}') into v_ids, v_wids from public.wms_pick_tasks where order_id = p_so_id;
    select assigned_to into v_orig from public.wms_pick_tasks where order_id = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_so.so_number, null, 'wms_pick_tasks', format('order_id = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_so.so_number, null, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_so.so_number, null, 'wms_pick_line_bins', format('pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'split undo (order ' || v_so.so_number || ')');
    delete from public.wms_pick_tasks where order_id = p_so_id;        -- 줄 · 칸 행은 cascade
    foreach v_wid in array v_wids loop                                 -- 이 되돌리기로 빈 웨이브는 지운다(운영 doVoid 와 같다)
      if not exists (select 1 from public.wms_pick_tasks t where t.wave_id = v_wid) then
        v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_so.so_number, null, 'wms_waves', format('id = %L', v_wid));
        delete from public.wms_waves where id = v_wid;
      end if;
    end loop;
    perform public.so_wms_status(p_so_id, 'at_wms', v_staff);        -- 과제 0 → 판정 18
    v_status := 'at_wms';  v_from := 'split';  v_to := 'unsplit';
  end if;
  insert into public.wms_rollback_log (order_id, order_number, action, from_stage, to_stage, performed_by, original_worker)
  values (p_so_id, v_so.so_number, p_action, v_from, v_to, v_staff, v_orig);
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'action', p_action, 'status', v_status, 'archived', v_arch, 'voided', v_void, 'reopened', v_reopen);
end;
$$;
comment on function public.wms_rollback(uuid, text) is
  '⑤-2b 오더 단위 되돌리기(⬜9 · 운영 admin doRollback 의 자리 · Void 없음 판정 21) — 첫 줄 ims_require_write(wms_manage) · manager 이상 · ims_can_warehouse · finalize: 팔렛·담긴 것·기록 삭제 + packed→picking · fulfillment: 팔렛만(Finalize 전) · pack: 팩 과제·줄 삭제 + 팩 실수 셋 무효화 + 회복 재개 · pick: 픽 줄 0 · 과제 pending · 실제 칸 행 삭제(계획 행은 남음) + short_pick 무효화 · split: 픽 과제·줄·칸 삭제 · 빈 웨이브 삭제 + picking→at_wms · 전부 아카이브 → 무효화 → 삭제 한 트랜잭션 · Finalize 뒤의 pack·pick·split 은 거부(SO-13893) · 원장 사건 없음(⬜10)';
revoke all on function public.wms_rollback(uuid, text) from public, anon;
grant execute on function public.wms_rollback(uuid, text) to authenticated;

create function public.wms_rollback_batch(p_task_id bigint, p_kind text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_pack constant text[] := array['short_after_pack', 'over_pick', 'pack_scan_mistake'];
  v_staff uuid;  v_so public.so%rowtype;  v_label text;  v_orig uuid;  v_so_id uuid;
  v_arch int := 0;  v_void int := 0;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');
  v_staff := public.so_current_staff();
  if p_kind not in ('pack', 'pick') then raise exception 'Unknown batch rollback kind % — nothing was saved', p_kind; end if;
  if p_kind = 'pack' then select k.order_id, k.batch_label, k.assigned_to into v_so_id, v_label, v_orig from public.wms_pack_tasks k where k.id = p_task_id;
  else select t.order_id, t.batch_label, t.assigned_to into v_so_id, v_label, v_orig from public.wms_pick_tasks t where t.id = p_task_id; end if;
  if v_so_id is null then raise exception 'Task not found — nothing was saved'; end if;
  select * into v_so from public.so s where s.id = v_so_id for update;
  if not public.ims_can_warehouse(v_so.location_id) then              -- ⭐ 둘째
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_so.so_number;
  end if;
  if v_so.status = 'packed' or exists (select 1 from public.wms_order_finalize f where f.order_id = v_so_id) then
    raise exception 'Order % is finalized — use Undo Finalize first — nothing was saved', v_so.so_number;
  end if;
  if p_kind = 'pack' then
    if exists (select 1 from public.wms_pallet_items i where i.pack_task_id = p_task_id) then raise exception 'Batch % is on a pallet — Undo Fulfillment first — nothing was saved', v_label; end if;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', v_so_id, v_so.so_number, v_label, 'wms_pack_tasks', format('id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', v_so_id, v_so.so_number, v_label, 'wms_pack_task_lines', format('pack_task_id = %L', p_task_id));
    v_void := public.wms_rb_void(v_staff, 'pack_task_id', array[p_task_id], c_pack, 'pack rollback ' || v_label);
    delete from public.wms_pack_tasks where id = p_task_id;             -- 배치 단위는 회복을 재개하지 않는다(규칙 14 · 남은 팩이 있다)
  else
    if exists (select 1 from public.wms_pack_tasks k where k.pick_task_id = p_task_id) then raise exception 'Batch % already has packing — Undo Pack first — nothing was saved', v_label; end if;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_so.so_number, v_label, 'wms_pick_tasks', format('id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_so.so_number, v_label, 'wms_pick_task_lines', format('pick_task_id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_so.so_number, v_label, 'wms_pick_line_bins', format('not planned and pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = %L)', p_task_id));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', array[p_task_id], array['short_pick'], 'pick reset ' || v_label);
    delete from public.wms_pick_line_bins b where not b.planned and b.pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = p_task_id);
    update public.wms_pick_task_lines set picked_base = 0, status = 'pending', verification_method = null, picked_at = null, picked_by = null where pick_task_id = p_task_id;
    update public.wms_pick_tasks set status = 'pending', assigned_to = null, started_at = null, completed_at = null, completed_by = null, heartbeat_at = null, work_started = false, held_by = null, session_id = null where id = p_task_id;
  end if;
  insert into public.wms_rollback_log (order_id, order_number, action, from_stage, to_stage, performed_by, batch_label, original_worker)
  values (v_so_id, v_so.so_number, p_kind, case p_kind when 'pack' then 'pack_complete' else 'pick_complete' end, case p_kind when 'pack' then 'pick_complete' else 'pick_reset' end, v_staff, v_label, v_orig);
  return jsonb_build_object('so_id', v_so_id, 'so_number', v_so.so_number, 'batch_label', v_label, 'kind', p_kind, 'archived', v_arch, 'voided', v_void);
end;
$$;
comment on function public.wms_rollback_batch(bigint, text) is
  '⑤-2b 배치 단위 되돌리기(⬜9 · 운영 doBatchRollback) — wms_manage · manager 이상 · 창고 · pack: 그 팩 과제·줄 삭제 + 팩 실수 셋 무효화(회복 재개는 안 한다 · 규칙 14) · 팔렛에 담긴 배치는 거부 · pick: 그 픽 과제 줄 0 · pending · 실제 칸 행 삭제 + short_pick 무효화 · 팩이 있으면 거부 · Finalize 뒤는 거부 · SO 상태 무변(picking)';
revoke all on function public.wms_rollback_batch(bigint, text) from public, anon;
grant execute on function public.wms_rollback_batch(bigint, text) to authenticated;

create function public.wms_unwave(p_wave_id bigint) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_w public.wms_waves%rowtype;  v_ids bigint[];  v_oids uuid[];  v_id uuid;  v_so public.so%rowtype;
  v_arch int := 0;  v_void int := 0;  v_back int := 0;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');
  v_staff := public.so_current_staff();
  select * into v_w from public.wms_waves w where w.id = p_wave_id for update;
  if not found then raise exception 'Wave not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_w.warehouse_id) then              -- ⭐ 둘째
    raise exception 'Wave % is at another warehouse — you are not set up for it — nothing was saved', v_w.label;
  end if;
  select coalesce(array_agg(t.id), '{}'), coalesce(array_agg(distinct t.order_id), '{}') into v_ids, v_oids from public.wms_pick_tasks t where t.wave_id = p_wave_id;
  foreach v_id in array v_oids loop
    select * into v_so from public.so s where s.id = v_id for update;
    if v_so.status = 'packed' or exists (select 1 from public.wms_order_finalize f where f.order_id = v_id) then
      raise exception 'Order % in wave % is finalized — use Undo Finalize first — nothing was saved', v_so.so_number, v_w.label;
    end if;
    if exists (select 1 from public.wms_pack_tasks k where k.pick_task_id = any(v_ids) and k.order_id = v_id) then
      raise exception 'Order % in wave % already has packing — Undo Pack first — nothing was saved', v_so.so_number, v_w.label;
    end if;
  end loop;
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_pick_tasks', format('wave_id = %L', p_wave_id));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_pick_line_bins', format('pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_waves', format('id = %L', p_wave_id));
  v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'wave undo ' || v_w.label);
  delete from public.wms_pick_tasks where wave_id = p_wave_id;         -- 줄 · 칸 행 cascade
  delete from public.wms_waves where id = p_wave_id;
  foreach v_id in array v_oids loop                                    -- 과제 0 이 된 오더만 at_wms(판정 18)
    select * into v_so from public.so s where s.id = v_id;
    if v_so.status = 'picking' and not exists (select 1 from public.wms_pick_tasks t where t.order_id = v_id) then
      perform public.so_wms_status(v_id, 'at_wms', v_staff);  v_back := v_back + 1;
    end if;
    insert into public.wms_rollback_log (order_id, order_number, action, from_stage, to_stage, performed_by, batch_label)
    values (v_id, v_so.so_number, 'unwave', 'wave', 'unsplit', v_staff, v_w.label);
  end loop;
  return jsonb_build_object('wave_id', p_wave_id, 'label', v_w.label, 'orders', cardinality(v_oids), 'tasks', cardinality(v_ids), 'back_to_at_wms', v_back, 'archived', v_arch, 'voided', v_void);
end;
$$;
comment on function public.wms_unwave(bigint) is
  '⑤-2b 웨이브 되돌리기(⬜9 · 운영 doUndoWave) — wms_manage · manager 이상 · 창고 · 멤버 과제·줄·칸 행 · 웨이브 행을 아카이브하고 지운다 · short_pick 무효화 · 팩이 있거나 Finalize 된 오더가 있으면 거부 · 과제가 0 이 된 오더는 picking→at_wms(판정 18) · 오더마다 로그 한 줄';
revoke all on function public.wms_unwave(bigint) from public, anon;
grant execute on function public.wms_unwave(bigint) to authenticated;
