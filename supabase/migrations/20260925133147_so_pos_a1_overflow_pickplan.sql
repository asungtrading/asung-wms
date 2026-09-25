-- SO 쓰기 ④a1 — 칸 순서: 보관용 표시(product_bin_overflow) · 창구 둘 · ims_last_bin 재발행 · 칸 계획 so_pick_plan (2026-09-25 UTC · 토론토 2026-09-25 오전)
-- 지시서 ~/asung/prompts/so-pos-1.md · 판정 회신 Caleb 2026-09-25(판정 1~4 · 이견 0-2·0-3(고침 ①)·0-9 · ⬜1·⬜2·⬜8) · 정본 §20 은 차수 끝에
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/so-pos-1a-verify.sql(-v mig)
-- 판정 1 칸 — POS·counter 는 「지금 재고 있는 칸에서 자동으로」 · 한 칸이 모자라면 다음 칸으로 · 판정 2 보관용 표시는 SKU × 칸 짝(값 하나 · 순서만 바꾸고 막지 않는다 · 칸이 비어도 남는다) ·
-- 판정 3 켜기·끄기 = ims_require_write('receiving')(매니저로 좁히지 않는다) · 판정 4 counter 는 계획을 미리 채우고 사람이 바꾼다 · 고침 ① 세트 줄은 정수 세트 단위 · short_ea 는 창고 전체 부족분만(원장 부족분 레이어와 같아야 한다)
--
-- ① product_bin_overflow — 「보관용」 표시(⚠️ 이름에 reserve 를 쓰지 않는다 — so_reserve(할당)와 낱말 충돌 · 이견 0-2) · 관계 표 규약(공통 칸 · DELETE 열림 · 끄기 = 행 삭제) · 표는 select 만 · 쓰기는 창구 둘
-- ② product_bin_overflow_set / _clear — definer · 첫 줄 ims_require_write('receiving') · 세트 제품이면 parent 로 · 비활성 칸 켜기 거부 · 같은 짝 두 번 = already(오류 아님)
-- ③ ims_last_bin 재발행(마지막 정의 20260919151601:139~158 · 시그니처·반환 모양 무변 · 정렬 맨 앞에 「보관용 아님」 한 키 · 그 밖 바이트 그대로) — 부르는 곳 셋: asung-ims receiving.html:285 · so_credit_issue(20260925012354:1077 되돌려 놓을 칸 기본값) · (이 레포 html·js·gs 0)
-- ④ so_pick_plan(p_so_id) — 읽기(stable · invoker · authenticated) · 줄마다 보낼 목표(qty_ordered − qty_removed) × pack_factor 를 낱개 SKU 의 그 창고 칸 잔고로 나눈다 · 순서 재고 있는 평소 칸 → 재고 있는 보관용 칸 → 모자란 몫은 첫 후보 칸(재고 0 이어도 · 없으면 '') ·
--    세트 줄은 정수 세트 단위(칸마다 floor(칸 EA ÷ pack) 세트 · 남는 EA 는 안 쓴다 · 나머지 세트는 첫 후보 칸에) · short_ea = 창고 전체 부족분(모든 칸 잔고 합 < 필요 EA 인 몫 · 같은 제품의 앞 줄이 쓴 EA 를 뺀다) · 반환 = so_ship 의 p_picks 모양 + 줄마다 short_ea
--    ⚠️ 임시 표 없음(stable) · 칸 잔고는 오더당 한 문장(ims_inv_balance 를 한 번 · CTE 둘) · 후보 순서는 ims_last_bin 과 같은 키(마지막 사건 최근 · qty 큰 것 · bin 이름)

-- ═══ ① product_bin_overflow ═══
create table if not exists public.product_bin_overflow (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.product (id) on delete no action,   -- 낱개 제품(세트면 창구가 parent 로 바꿔 담는다 · 원장·잔고 축)
  bin_id      uuid not null references public.ref_bin (id) on delete no action,   -- 칸(창고는 칸이 안다)
  source      text not null default 'manual',
  note        text,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.ims_staff (id) on delete no action,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.ims_staff (id) on delete no action,
  constraint product_bin_overflow_source_ck check (source in ('manual')),
  constraint product_bin_overflow_uq        unique (product_id, bin_id)
);
create index if not exists product_bin_overflow_product_idx    on public.product_bin_overflow (product_id);
create index if not exists product_bin_overflow_bin_idx        on public.product_bin_overflow (bin_id);
create index if not exists product_bin_overflow_created_by_idx on public.product_bin_overflow (created_by);
create index if not exists product_bin_overflow_updated_by_idx on public.product_bin_overflow (updated_by);
create trigger product_bin_overflow_touch before update on public.product_bin_overflow for each row execute function public.ims_touch();
alter table public.product_bin_overflow enable row level security;
create policy product_bin_overflow_select on public.product_bin_overflow for select to authenticated using (true);
revoke all on public.product_bin_overflow from public, anon, authenticated;
grant select on public.product_bin_overflow to authenticated;
comment on table  public.product_bin_overflow is '⭐ 보관용 칸 표시(SKU × 칸 짝 · so-module §20 판정 2 · 2026-09-25) — 같은 칸이 A 에게는 보관용 · B 에게는 평소 칸일 수 있어 칸이 아니라 짝에 붙는다 · 값은 「보관용」 하나(행이 있으면 보관용 · 없으면 평소 칸) · 순서만 바꾸고 막지 않는다(평소 칸이 비면 보관용에서 뺀다 · 틀려도 창고 수량은 맞다) · 칸이 비어도 표시는 남는다(다음에 또 넘치면 같은 자리) · 켜기 = 풋어웨이 때 받는 직원 · 끄기 = 재고 화면 · 둘 다 receiving 열쇠(판정 3 · 매니저로 좁히지 않는다) · 끄기 = 행 삭제(관계 표 · 이력 없음) · 쓰기는 창구 둘(product_bin_overflow_set · _clear · 표는 select 만) · ⚠️ 이름에 reserve 를 쓰지 않는다(so_reserve 는 할당) · 화면 낱말 「보관용」 · 영어 Overflow';
comment on column public.product_bin_overflow.product_id is '낱개 제품 FK(원장·잔고 축) — 창구가 세트 제품을 받으면 parent_product_id 로 바꿔 담는다';
comment on column public.product_bin_overflow.bin_id     is '칸 FK → ref_bin(id) · 창고는 칸이 안다 · 켤 때 비활성 칸은 거부 · 유니크 (product_id, bin_id)';

-- ═══ ② 창구 둘 — definer · 첫 줄 ims_require_write(receiving) ═══
create function public.product_bin_overflow_set(p_product_id uuid, p_bin_id uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_p     public.product%rowtype;
  v_base  public.product%rowtype;
  v_b     public.ref_bin%rowtype;
  v_w     text;
  v_row   public.product_bin_overflow%rowtype;
  v_new   boolean := false;
begin
  perform public.ims_require_write('receiving', 'saved');       -- ⭐ 첫 줄 — 판정 3(받는 직원 · 매니저로 좁히지 않는다)
  v_staff := public.so_current_staff();
  select * into v_p from public.product p where p.id = p_product_id;
  if not found then raise exception 'Product not found — nothing was saved'; end if;
  if v_p.parent_product_id is not null then
    select * into v_base from public.product p where p.id = v_p.parent_product_id;                       -- 세트 → 낱개(원장 축)
  else
    v_base := v_p;
  end if;
  select * into v_b from public.ref_bin b where b.id = p_bin_id;
  if not found then raise exception 'Bin not found — nothing was saved'; end if;
  if not v_b.is_active then raise exception 'Bin % is inactive — an overflow mark needs an active bin — nothing was saved', v_b.name; end if;
  select w.name into v_w from public.ref_warehouse w where w.id = v_b.warehouse_id;

  select * into v_row from public.product_bin_overflow o where o.product_id = v_base.id and o.bin_id = v_b.id;
  if not found then
    insert into public.product_bin_overflow (product_id, bin_id, note, created_by, updated_by)
    values (v_base.id, v_b.id, nullif(trim(p_note), ''), v_staff, v_staff) returning * into v_row;
    v_new := true;
  elsif p_note is not null and nullif(trim(p_note), '') is distinct from v_row.note then
    update public.product_bin_overflow set note = nullif(trim(p_note), ''), updated_by = v_staff where id = v_row.id returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row.id, 'product_id', v_base.id, 'sku', v_base.sku, 'from_set', v_p.id <> v_base.id, 'bin_id', v_b.id, 'bin', v_b.name, 'warehouse', v_w,
                            'overflow', true, 'created', v_new, 'already', not v_new, 'note', v_row.note);
end;
$$;
comment on function public.product_bin_overflow_set(uuid, uuid, text) is '⭐ 보관용 표시 켜기(§20 판정 2·3) — definer · 첫 줄 ims_require_write(receiving) · 세트 제품이면 parent(낱개)로 · 없는 제품·칸 거부 · 비활성 칸 거부 · 같은 짝이 이미 있으면 already(오류 아님 · note 만 갱신) · 풋어웨이 화면이 칸을 고르며 체크할 때 부른다';
revoke all on function public.product_bin_overflow_set(uuid, uuid, text) from public, anon;
grant execute on function public.product_bin_overflow_set(uuid, uuid, text) to authenticated;

create function public.product_bin_overflow_clear(p_product_id uuid, p_bin_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_p     public.product%rowtype;
  v_pid   uuid;
  v_n     int;
begin
  perform public.ims_require_write('receiving', 'saved');       -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  select * into v_p from public.product p where p.id = p_product_id;
  if not found then raise exception 'Product not found — nothing was saved'; end if;
  v_pid := coalesce(v_p.parent_product_id, v_p.id);
  delete from public.product_bin_overflow o where o.product_id = v_pid and o.bin_id = p_bin_id;
  get diagnostics v_n = row_count;
  return jsonb_build_object('product_id', v_pid, 'bin_id', p_bin_id, 'cleared', v_n = 1, 'overflow', false);
end;
$$;
comment on function public.product_bin_overflow_clear(uuid, uuid) is '⭐ 보관용 표시 끄기(§20 판정 2·3) — definer · 첫 줄 ims_require_write(receiving) · 행 삭제(관계 표 · 이력 없음) · 세트 제품이면 parent 로 · 없으면 cleared false(오류 아님) · 재고 화면이 부른다';
revoke all on function public.product_bin_overflow_clear(uuid, uuid) from public, anon;
grant execute on function public.product_bin_overflow_clear(uuid, uuid) to authenticated;

-- ═══ ③ ims_last_bin 재발행 — 마지막 정의 20260919151601:139~158 · create or replace · 더한 줄 1(left join) · 바뀐 줄 1(order by 첫 키) · 주석 · 시그니처·반환·grant 무변 ═══
create or replace function public.ims_last_bin(p_product_ids uuid[], p_warehouse_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
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
    order by v.product_id, (o.id is null) desc, (v.qty > 0) desc, v.last_seen_on desc, v.qty desc, v.bin   -- ④a1: 보관용 아님을 맨 앞에(판정 2 · 평시 칸 먼저) · 나머지 키 그대로
  ) x;
$$;
comment on function public.ims_last_bin(uuid[], uuid) is '⭐ 「그 제품이 그 창고에서 마지막으로 놓인 빈」 — 리시빙 풋어웨이의 Last bin 제안 · 크레딧 되돌려 놓을 칸 기본값(§19 ⬜4). ⭐ [2026-09-25 ④a1] 정렬 맨 앞에 「보관용 아님」(product_bin_overflow · so-module §20 판정 2) — 평시 칸을 먼저 가리킨다(재고 0 인 평소 칸 > 재고 있는 보관용 칸 · 픽 순서는 so_pick_plan 이 따로) · 시그니처·반환 모양 무변(receiving.html:285 · so_credit_issue). ⭐ 속 = 원장(ims_inv_balance · 2026-09-19 원장 이식 1차 — 종전 po_receipt_line 속을 갈아 끼웠다 · 부르는 쪽 무접촉): 1순위 지금 재고가 있는 자리(qty>0 · 마지막 사건 최근순) → 2순위 마지막으로 있던 자리(qty≤0 · 사건 있음) · 동률 qty desc, bin. 후보 밖 = bin 빈 문자열 · 마스터에 없는 bin · 비활성 bin · IN_TRANSIT(창고가 다르다). received_on = 그 빈의 마지막 사건일(사건 없으면 기초선 촬영일). 시그니처 (uuid[], uuid) → jsonb · 반환 { "<product_id>": { bin_id, bin, zone, received_on } } 무변 · 없는 제품은 키 없음 · 빈 입력 {} · 단일 값이라 캡 밖 · security invoker · stable. ⚠️ wms_sku_bins 를 읽지 않는다(원칙 1). 정본 po-module §11-i(⬜ 갱신)';

-- ─────────────────────────────────────────────────────────────

-- ═══ ④ so_pick_plan — 칸 계획(읽기 · 판정 1·2 · 고침 ①) ═══
create function public.so_pick_plan(p_so_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  v_wh       text;
  v_cands    jsonb := '{}'::jsonb;     -- 낱개 product_id → [{bin_id, bin, qty, ovf, rank}] (순서대로)
  v_tot      jsonb := '{}'::jsonb;     -- 낱개 product_id → 창고 전체 잔고(모든 칸 · '' · 비활성 포함)
  v_used     jsonb := '{}'::jsonb;     -- product_id → 앞 줄이 계획한 EA(창고 부족분 계산)
  v_taken    jsonb := '{}'::jsonb;     -- product_id|bin_id → 앞 줄이 계획한 EA(칸 남은 잔고)
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
  select * into v_so from public.so s where s.id = p_so_id;
  if not found then raise exception 'Order not found'; end if;
  if v_so.location_id is null then raise exception 'Order % has no warehouse — nothing to plan', v_so.so_number; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_so.location_id;

  -- 칸 잔고 한 문장(ims_inv_balance 를 한 번) — 후보(활성 칸 · bin 있음)는 순서를 붙여 · 창고 전체 잔고는 모든 행
  with pids as (
    select distinct coalesce(p.parent_product_id, p.id) as pid
    from public.so_line x join public.product p on p.id = x.product_id where x.so_id = p_so_id
  ), bal as (
    select v.product_id, v.bin_id, v.bin, v.qty, v.bin_is_active, v.last_seen_on
    from public.ims_inv_balance v join pids on pids.pid = v.product_id
    where v.warehouse_id = v_so.location_id
  ), cand as (
    select b.product_id, b.bin_id, b.bin, b.qty, (o.id is not null) as ovf, b.last_seen_on,
           case when b.qty > 0 and o.id is null then 1 when b.qty > 0 then 2 when o.id is null then 3 else 4 end as rank   -- 재고 있는 평소 → 재고 있는 보관용 → 빈 평소 → 빈 보관용
    from bal b left join public.product_bin_overflow o on o.product_id = b.product_id and o.bin_id = b.bin_id
    where b.bin_id is not null and b.bin_is_active
  )
  select coalesce((select jsonb_object_agg(x.product_id::text, x.arr)
                   from (select cd.product_id, jsonb_agg(jsonb_build_object('bin_id', cd.bin_id, 'bin', cd.bin, 'qty', cd.qty, 'ovf', cd.ovf, 'rank', cd.rank)
                                                          order by cd.rank, cd.last_seen_on desc, cd.qty desc, cd.bin) as arr
                         from cand cd group by cd.product_id) x), '{}'::jsonb),
         coalesce((select jsonb_object_agg(y.product_id::text, y.t) from (select b2.product_id, sum(b2.qty) as t from bal b2 group by b2.product_id) y), '{}'::jsonb)
    into v_cands, v_tot;

  for l in
    select x.id, x.line_no, x.sku, x.qty_ordered, x.qty_removed, x.pack_factor, coalesce(p.parent_product_id, p.id) as pid, (p.parent_product_id is not null) as is_set
    from public.so_line x join public.product p on p.id = x.product_id
    where x.so_id = p_so_id order by x.line_no
  loop
    v_need_u  := l.qty_ordered - l.qty_removed;                    -- 보낼 목표(판매 단위 · 판정 5 §17)
    v_need_ea := v_need_u * l.pack_factor;
    v_lp := '[]'::jsonb;  v_rem := v_need_u;  v_first := null;
    v_arr := coalesce(v_cands->(l.pid::text), '[]'::jsonb);
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
    v_tot_p  := coalesce((v_tot->>(l.pid::text))::numeric, 0);
    v_used_p := coalesce((v_used->>(l.pid::text))::numeric, 0);
    v_short  := greatest(0, v_need_ea - greatest(v_tot_p - v_used_p, 0));
    v_used   := jsonb_set(v_used, array[l.pid::text], to_jsonb(v_used_p + v_need_ea));
    v_short_tot := v_short_tot + v_short;
    if v_short > 0 then v_warn := array_append(v_warn, 'stock_short:' || l.sku); end if;

    v_picks := v_picks || v_lp;
    v_lines := v_lines || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'is_set', l.is_set, 'pack_factor', l.pack_factor,
                                             'to_ship', v_need_u, 'need_ea', v_need_ea, 'warehouse_qty_ea', v_tot_p, 'picks', v_lp, 'short_ea', v_short);
  end loop;

  return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'warehouse_id', v_so.location_id, 'warehouse', v_wh,
                            'picks', v_picks, 'lines', v_lines, 'short_ea_total', v_short_tot, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_pick_plan(uuid) is
  '⭐ 칸 계획(§20 판정 1·2·4 · 고침 ① · ④a1) — 읽기(stable · invoker) · 줄마다 보낼 목표(qty_ordered − qty_removed)를 낱개 SKU 의 그 창고 칸 잔고(ims_inv_balance 한 번)로 나눈다. 순서: 재고 있는 평소 칸(마지막 사건 최근 · qty 큰 것 · bin 이름) → 재고 있는 보관용 칸(product_bin_overflow) → 모자란 몫은 첫 후보 칸(재고 0 이어도 · 없으면 '' · 경고 no_bins) · 세트 줄은 칸마다 정수 세트만(floor(칸 EA ÷ pack_factor)) · 같은 제품의 앞 줄이 쓴 몫을 뺀다. short_ea = 창고 전체 부족분(모든 칸 잔고 합 · 앞 줄이 쓴 EA 를 뺀 것 < 필요 EA · 원장 부족분 레이어 sale_shortfall 과 같아야 한다 · 경고 stock_short). 반환 picks 는 so_ship 의 p_picks 모양 [{line_id, bin, qty}](+from usual|overflow|fallback|none) · POS Finish 는 이대로 · counter 는 미리 채우고 사람이 바꾼다';
revoke all on function public.so_pick_plan(uuid) from public, anon;
grant execute on function public.so_pick_plan(uuid) to authenticated;

-- ═══ 검증(~/asung/prompts/so-pos-1a-verify.sql · 시험 적용 장치 -v mig) — 표·창구·권한 · ims_last_bin 모양 무변 + 보관용 뒤로 · 두 칸 SKU 평소→다음 칸 · 보관용 켜면 순서 뒤집힘 · 끄면 되돌아옴 · 재고 0 SKU 첫 후보 + short · 후보 없음 '' ·
--   세트 12 EA = 칸1 10 + 칸2 2 → 칸1 에서 1세트 · short 0(고침 ① 예) · 같은 제품 두 줄 · 유니크 · receiving 없는 직원 거부 ═══
