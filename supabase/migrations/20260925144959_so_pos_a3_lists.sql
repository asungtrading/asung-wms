-- SO 쓰기 ④a3 — 매니저 목록(읽기)·확인 기록: so_stock_short_check(「재고 없이 나갔다」 확인) · so_stock_short_confirm · so_stock_short_list · so_pos_open_list (2026-09-25 UTC · 토론토 2026-09-25)
-- 지시서 ~/asung/prompts/so-pos-1.md §3 C · 판정 회신 Caleb 2026-09-25(판정 7·8·15·16 · 이견 0-10·0-11·0-13 · ⬜6·⬜7) · ④a1(20260925133147)·④a2(20260925142307) 위에 선다 · 정본 §20 은 차수 끝에
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/so-pos-1c-verify.sql(-v mig)
-- 판정 7 「재고 없이 나갔다」 — 새로 적는 곳을 만들지 않는다: 원장의 판매 부족분 레이어(origin_type sale_shortfall · doc_number = so_number · §15)를 읽는 목록 + 매니저의 「확인함」 기록(누가 · 언제 · 메모) 표 하나 ·
--        화면(뒤)은 운영 WMS admin Discrepancy 탭 모양(배지 · 미해결 전량 · 해결은 기간 · Resolve) · 길(pos·counter·warehouse)과 무관하게 전부 ⇒ asung-inv-ledger ⑲ 「SO 쪽 표와 맞아야 한다」 대조 불필요(같은 기록 하나)
-- 판정 8 관리 화면 나누기 — 장부·마스터·돈은 IMS · 이번은 읽기 창구만 · 판정 15 끝나지 않은 POS 오더(그날 안에 Finish 안 됨) = 매니저 목록 · 판정 16 잠시 두기 = 새 상태 없음 · 「그 창고의 끝나지 않은 POS 오더」 읽기 하나
--
-- ① so_stock_short_check — ⚠️⚠️ 열쇠는 레이어 id 가 아니다(inv_layer_apply 재생성이 id 를 바꾼다 · 15-b 이견 3) ⇒ (doc_number, sku, warehouse) 전체 유니크(부족분 레이어는 그 키에 하나 — inv_layer_post_sale :151 존재 검사) · checked_by · checked_at · note · 표는 select 만 · 되돌리기 없음(메모로 고친다 · ⬜6)
-- ② so_stock_short_confirm — definer · manager 이상 + (sales ∨ receiving) 열쇠(ims_require_write 는 화면 하나라 ims_can_write 둘을 or 로 · 0-10) · 그 키에 부족분 레이어가 있어야 · 같은 키 두 번 = 거부(누가·언제)
-- ③ so_stock_short_list(p_filters) — inv_layer sale_shortfall ⟕ so(so_number) ⟕ customer ⟕ ① · 미확인은 기간과 상관없이 전량 · 확인된 것은 기간(checked_at · 기본 30일 · 상한 500) · 머리에 미확인 건수(배지) · 창고 필터 · jsonb 하나(1,000행 캡 밖)
-- ④ so_pos_open_list(p_location_id) — 그 창고(null 이면 전부)의 confirmed pos 오더 · 줄 수 · 수량 · 금액(so_tax_preview ordered) · 받은 금액(이 오더 대상 활성 선결제의 남은 금액) · stale = 확정일(토론토) < ims_today() · jsonb 하나
-- 검증: ~/asung/prompts/so-pos-1c-verify.sql

-- ═══ ① so_stock_short_check ═══
create table if not exists public.so_stock_short_check (
  id          uuid primary key default gen_random_uuid(),
  doc_number  text not null,                                   -- 오더 번호(sale_shortfall 레이어의 doc_number · so.so_number)
  sku         text not null,                                   -- 낱개 SKU(원장 축)
  warehouse   text not null,                                   -- 창고 이름(원장 축 · ref_warehouse.name)
  checked_at  timestamptz not null default now(),
  checked_by  uuid not null references public.ims_staff (id) on delete no action,
  note        text,
  source      text not null default 'manual',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.ims_staff (id) on delete no action,
  constraint so_stock_short_check_source_ck check (source in ('manual')),
  constraint so_stock_short_check_uq        unique (doc_number, sku, warehouse)
);
create index if not exists so_stock_short_check_checked_by_idx on public.so_stock_short_check (checked_by);
create index if not exists so_stock_short_check_checked_at_idx on public.so_stock_short_check (checked_at);
create index if not exists so_stock_short_check_updated_by_idx on public.so_stock_short_check (updated_by);
create trigger so_stock_short_check_touch before update on public.so_stock_short_check for each row execute function public.ims_touch();
alter table public.so_stock_short_check enable row level security;
create policy so_stock_short_check_select on public.so_stock_short_check for select to authenticated using (true);
revoke all on public.so_stock_short_check from public, anon, authenticated;
grant select on public.so_stock_short_check to authenticated;
comment on table  public.so_stock_short_check is '⭐ 「재고 없이 나갔다」 확인 기록(so-module §20 판정 7 · 2026-09-25) — 원장의 판매 부족분 레이어(inv_layer origin_type sale_shortfall · IMS 판매 so_ship 이 FIFO 로 다 못 꺼낸 몫 · §15)에 매니저가 「확인함」을 붙인다(누가 · 언제 · 메모) · ⚠️⚠️ 열쇠는 (doc_number, sku, warehouse) — 레이어 id 는 inv_layer_apply 재생성이 바꾼다(15-b 이견 3) · 부족분 레이어는 그 키에 하나(inv_layer_post_sale 존재 검사) · 되돌리기 없음(메모로 고친다 · ⬜6) · 쓰기는 so_stock_short_confirm 만(표는 select) · 목록은 so_stock_short_list · 화면은 WMS admin Discrepancy 모양';
comment on column public.so_stock_short_check.doc_number is '오더 번호(sale_shortfall 레이어의 doc_number = so.so_number) · 열쇠 셋 중 하나';
comment on column public.so_stock_short_check.checked_by is '확인한 매니저 → ims_staff(id) · NOT NULL · manager 이상 + sales 또는 receiving 열쇠(so_stock_short_confirm)';

-- ═══ ② so_stock_short_confirm ═══
create function public.so_stock_short_confirm(p_doc_number text, p_sku text, p_warehouse text, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_doc   text := nullif(trim(p_doc_number), '');
  v_sku   text := nullif(trim(p_sku), '');
  v_wh    text := nullif(trim(p_warehouse), '');
  v_layer record;
  v_prev  record;
  v_row   public.so_stock_short_check%rowtype;
begin
  if not (public.ims_can_write('sales') or public.ims_can_write('receiving')) then          -- ⭐ 첫 줄 — 열쇠 둘 중 하나(0-10 · ims_require_write 는 화면 하나만 받는다)
    raise exception 'This needs the sales or receiving key — nothing was saved';
  end if;
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 확인은 매니저의 일(판정 7)
  v_staff := public.so_current_staff();
  if v_doc is null or v_sku is null or v_wh is null then raise exception 'doc_number, sku and warehouse are all needed — nothing was saved'; end if;

  select y.id, y.qty, y.received_on, y.cost_source into v_layer
  from public.inv_layer y where y.origin_type = 'sale_shortfall' and y.doc_number = v_doc and y.sku = v_sku and y.warehouse = v_wh
  order by y.id limit 1;
  if v_layer.id is null then
    raise exception 'No stock-short record for % / % at % — nothing to check — nothing was saved', v_doc, v_sku, v_wh;
  end if;
  select c.checked_at, s.name as checked_by_name into v_prev
  from public.so_stock_short_check c join public.ims_staff s on s.id = c.checked_by
  where c.doc_number = v_doc and c.sku = v_sku and c.warehouse = v_wh;
  if v_prev.checked_at is not null then
    raise exception '% / % at % was already checked by % on % — nothing was saved', v_doc, v_sku, v_wh, v_prev.checked_by_name, (v_prev.checked_at at time zone 'America/Toronto')::date;
  end if;

  insert into public.so_stock_short_check (doc_number, sku, warehouse, checked_by, note, updated_by)
  values (v_doc, v_sku, v_wh, v_staff, nullif(trim(p_note), ''), v_staff) returning * into v_row;
  return jsonb_build_object('id', v_row.id, 'doc_number', v_doc, 'sku', v_sku, 'warehouse', v_wh, 'checked_at', v_row.checked_at, 'checked_by', v_staff, 'note', v_row.note,
                            'layer', jsonb_build_object('qty', v_layer.qty, 'received_on', v_layer.received_on, 'cost_source', v_layer.cost_source));
end;
$$;
comment on function public.so_stock_short_confirm(text, text, text, text) is '⭐ 「재고 없이 나갔다」 확인(§20 판정 7 · ⬜6) — definer · 첫 줄 ims_can_write(sales) ∨ ims_can_write(receiving) · 둘째 줄 so_require_role(manager) · 열쇠 (doc_number, sku, warehouse)에 sale_shortfall 레이어가 있어야 · 같은 키 두 번은 거부(누가·언제) · 되돌리기 없음 · 반환 확인 행 + 레이어 요약(qty · received_on · cost_source)';
revoke all on function public.so_stock_short_confirm(text, text, text, text) from public, anon;
grant execute on function public.so_stock_short_confirm(text, text, text, text) to authenticated;

-- ═══ ③ so_stock_short_list ═══
--   p_filters {warehouse_id? uuid, warehouse? text(name), unchecked_only? bool, from? date, to? date(확인된 것의 checked_at 기간 · 기본 to = 오늘 · from = 30일 전), limit? int(확인된 것 · 기본 200 · 상한 500), offset? int}
create function public.so_stock_short_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  f          jsonb := coalesce(p_filters, '{}'::jsonb);
  v_wh       text;
  v_unc_only boolean := coalesce((f->>'unchecked_only')::boolean, false);
  v_to       date := coalesce(nullif(f->>'to', '')::date, public.ims_today());
  v_from     date := coalesce(nullif(f->>'from', '')::date, public.ims_today() - 30);
  v_limit    int  := least(greatest(coalesce((f->>'limit')::int, 200), 1), 500);
  v_offset   int  := greatest(coalesce((f->>'offset')::int, 0), 0);
  v_open     jsonb;  v_open_n int;
  v_done     jsonb;  v_done_n int;
  v_unknown  int;
begin
  if nullif(f->>'warehouse_id', '') is not null then
    select w.name into v_wh from public.ref_warehouse w where w.id = (f->>'warehouse_id')::uuid;
    if v_wh is null then raise exception 'Warehouse not found'; end if;
  elsif nullif(f->>'warehouse', '') is not null then
    v_wh := f->>'warehouse';
  end if;
  if v_from > v_to then raise exception 'from % is after to %', v_from, v_to; end if;

  with rows as (
    select y.id as layer_id, y.doc_number, y.sku, y.warehouse, y.qty, y.received_on, y.cost_source, y.unit_cost, (y.cost_source = 'unknown') as unknown,
           s.id as so_id, s.channel, s.status as so_status, s.customer_id, c.name as customer_name,
           k.id as check_id, k.checked_at, k.checked_by, ks.name as checked_by_name, k.note
    from public.inv_layer y
    left join public.so s on s.so_number = y.doc_number
    left join public.customer c on c.id = s.customer_id
    left join public.so_stock_short_check k on k.doc_number = y.doc_number and k.sku = y.sku and k.warehouse = y.warehouse
    left join public.ims_staff ks on ks.id = k.checked_by
    where y.origin_type = 'sale_shortfall' and (v_wh is null or y.warehouse = v_wh)
  )
  select coalesce((select jsonb_agg(to_jsonb(r) order by r.received_on desc, r.doc_number, r.sku) from rows r where r.check_id is null), '[]'::jsonb),
         (select count(*) from rows r where r.check_id is null),
         (select count(*) from rows r where r.check_id is null and r.unknown),
         case when v_unc_only then '[]'::jsonb else
           coalesce((select jsonb_agg(to_jsonb(r) order by r.checked_at desc, r.doc_number, r.sku)
                     from (select * from rows r where r.check_id is not null and (r.checked_at at time zone 'America/Toronto')::date between v_from and v_to
                           order by r.checked_at desc, r.doc_number, r.sku limit v_limit offset v_offset) r), '[]'::jsonb) end,
         case when v_unc_only then 0 else (select count(*) from rows r where r.check_id is not null and (r.checked_at at time zone 'America/Toronto')::date between v_from and v_to) end
    into v_open, v_open_n, v_unknown, v_done, v_done_n;

  return jsonb_build_object(
    'warehouse', v_wh, 'from', v_from, 'to', v_to, 'limit', v_limit, 'offset', v_offset,
    'unchecked_count', v_open_n, 'unchecked_unknown_cost', v_unknown, 'checked_in_range', v_done_n,
    'unchecked', v_open, 'checked', v_done);
end;
$$;
comment on function public.so_stock_short_list(jsonb) is '⭐ 「재고 없이 나갔다」 목록(§20 판정 7·8 · 매니저 화면 · WMS admin Discrepancy 모양) — 읽기(stable · invoker) · 원장 sale_shortfall 레이어 ⟕ so(so_number) ⟕ customer ⟕ so_stock_short_check(열쇠 doc·sku·warehouse) · 길 무관 전부 · unchecked = 기간과 상관없이 전량(배지 unchecked_count · unknown 원가 수) · checked = checked_at 기간(기본 30일 · limit 200 · 상한 500 · offset) · 필터 warehouse_id|warehouse · unchecked_only · from · to · jsonb 하나(PostgREST 1,000행 캡 밖)';
revoke all on function public.so_stock_short_list(jsonb) from public, anon;
grant execute on function public.so_stock_short_list(jsonb) to authenticated;

-- ═══ ④ so_pos_open_list ═══
create function public.so_pos_open_list(p_location_id uuid default null) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_orders jsonb;
  v_n      int;
  v_stale  int;
  v_wh     text;
begin
  if p_location_id is not null then
    select w.name into v_wh from public.ref_warehouse w where w.id = p_location_id;
    if v_wh is null then raise exception 'Warehouse not found'; end if;
  end if;
  with o as (
    select s.id, s.so_number, s.customer_id, c.name as customer_name, s.location_id, s.location_name, s.confirmed_at, s.confirmed_by, cb.name as confirmed_by_name,
           (s.confirmed_at at time zone 'America/Toronto')::date as confirmed_on,
           ((s.confirmed_at at time zone 'America/Toronto')::date < public.ims_today()) as stale,
           (select count(*) from public.so_line l where l.so_id = s.id) as lines,
           (select coalesce(sum(l.qty_ordered - l.qty_removed), 0) from public.so_line l where l.so_id = s.id) as qty,
           (public.so_tax_preview(s.id, null, null, 'ordered')->'totals'->>'total')::numeric as amount,
           (select coalesce(sum(p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null), 0)), 0)
              from public.so_payment p
             where p.status = 'active' and p.kind = 'payment' and exists (select 1 from public.so_payment_order po where po.payment_id = p.id and po.so_id = s.id)) as received
    from public.so s
    join public.customer c on c.id = s.customer_id
    left join public.ims_staff cb on cb.id = s.confirmed_by
    where s.channel = 'pos' and s.status = 'confirmed' and (p_location_id is null or s.location_id = p_location_id)
  )
  select coalesce(jsonb_agg(to_jsonb(o) order by o.confirmed_at, o.so_number), '[]'::jsonb), count(*), count(*) filter (where o.stale)
    into v_orders, v_n, v_stale
  from o;
  return jsonb_build_object('warehouse_id', p_location_id, 'warehouse', v_wh, 'count', v_n, 'stale_count', v_stale, 'orders', v_orders);
end;
$$;
comment on function public.so_pos_open_list(uuid) is '⭐ 끝나지 않은 POS 오더(§20 판정 15·16 · 잠시 두기 · 매니저 목록) — 읽기(stable · invoker) · 그 창고(null 이면 전부)의 channel pos · status confirmed · 줄 수 · 수량(뺀 몫 제외) · 금액(so_tax_preview ordered) · received(이 오더를 대상으로 한 활성 선결제의 남은 금액) · stale = 확정일(토론토) < ims_today()(그날 안에 Finish 되지 않았다 · 자동으로 풀지 않는다) · 모든 계산대에서 같은 목록(이어받기) · Finish·취소·다시 열기 뒤 빠진다 · jsonb 하나';
revoke all on function public.so_pos_open_list(uuid) from public, anon;
grant execute on function public.so_pos_open_list(uuid) to authenticated;

-- ═══ 검증(~/asung/prompts/so-pos-1c-verify.sql · 시험 적용 장치 -v mig) — 재고 0 SKU 를 POS 로 팔아 부족분 → 목록 · 확인 → 미확인 −1 · 같은 키 두 번 거부 · 권한 셋 · inv_layer_apply 재생성 뒤에도 확인이 열쇠로 이어진다 · so_pos_open_list(stale · 창고 · Finish 뒤) · ④a2 잔여 둘(AONE 티어 손님 경고 · counter 다시 열기 권한) ═══
