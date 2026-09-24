-- SO 쓰기 ③a — 출고 엔진 · 원장 출고 창구(두 층) · 출하 차이 백오더 형제(pick_short) · 재생성 일치(17-f) (2026-09-24 UTC · 토론토 2026-09-24 오전)
-- 지시서 ~/asung/prompts/so-write-3-ship.md · 판정 Caleb 2026-09-24(§1 판정 1~8 · 새 판정 9~12 · 회신 이견 1~8·11·12 ✅ · 9·10 ✗ · ⬜1~⬜12) · 정본 docs/design/so-module.md §7 · §14 · ledger-design.md 17번
-- 바탕: 20260924014219(so_split · so_status_guard 짝 넷 · so_require_role) · 20260924015859(so_available_many) · 20260924023740(so_unconfirm) ·
--       20260909233729(inv_layer_fifo_take 11인자 · definer) · 20260909174046(inv_layer_apply_sale_out :226 — 이 파일이 재발행) · 20260908195949(inv_layer · inv_layer_consume · inv_layer_open) ·
--       20260920171930(inv_layer_source_ck 마지막 · 열 개) · 20260920163231(po_price_history 뷰 · net_unit_cad) · 20260924001820(inv_post_receipt — 창구 모양 · 실시간)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 검증 ~/asung/prompts/so-write-3a-verify.sql
--
-- ⭐ 무엇을 하나(③a — ③b 장부·이어받기 · ③c 만료·읽기는 다음 파일)
--    ① CHECK 확장(drop+add 선례 20260920171930) — inv_layer_source_ck +3(layer_recent · layer_recent_other_wh · price_history · 17-e 단계별 · 17-g 신호) · inv_layer_origin_ck +sale_shortfall(17-d) · so_split_reason_ck +pick_short(⬜6)
--    ② so_status_guard 재발행 — 짝 다섯(packed→shipped 하나 더 · ⬜5 · 마지막 정의 20260924014219:58)
--    ③ so_reserve.released_reason(released · shipped · closed · ⬜4 · 회신 이견 6) — 짝 CHECK + BEFORE 트리거가 비어 있으면 'released'(② 창구 일곱은 손대지 않는다)
--    ④ inv_layer_post_sale(속 · definer) — 원가 층: FIFO 소진(inv_layer_fifo_take · reason sale) + 부족분 「최근 원가」 레이어(sale_shortfall · 17-e 네 단계) 즉시 전량 소진 · p_hint 로 재생성 재현(17-f (가))
--    ⑤ inv_post_sale(원장 창구 · invoker · 첫 줄 ims_require_write('sales','posted')) — 원장 행 sale_out(칸 단위 · 낱개 SKU · EA · seq_hint 2 · source ims · doc_number so_number · line_ref so_line_id) · ⭐ 소진 먼저 → 결과를 raw.cost 에 실어 insert(inv_ledger 는 authenticated 에 update 가 없다)
--    ⑥ so_ship(출고 엔진 · 속 · invoker · authenticated 없음 — ④⑤ 차수의 definer 창구가 부른다) — ① CAS 플립(packed→shipped · 0행 = 조용한 반환) ② 할당 닫기 ③ 줄 qty_shipped ④ pick_short 형제(할당 없음 · backorder 예약) ⑤ 원장 창구
--    ⑦ inv_layer_apply_sale_out 재발행 — source='ims' 키는 ④ 를 같은 hint 로 부른다(재생성 = 실시간 · 17-f ①②③) · cin7 키는 그대로(short 는 short · 17-a)
--
-- ⭐ 규칙(정본 §15 로 옮긴다 · 말만)
--    한 오더 한 번(7-b) · 칸 단위 행 · 원가는 창고 단위 FIFO(7-d) · 원장 SKU 는 낱개(세트 줄은 parent_product.sku · qty × pack_factor · inv_ledger 주석 「base SKU」)
--    같은 낱개 SKU 의 줄 여럿은 접어 한 번 소진(consume.line_ref = 첫 줄 · 재생성 키 (doc_number, sku, warehouse) 와 같다 · 회신 이견 4) — 줄별 COGS 는 비례 배분(인보이스 차수 ⬜)
--    부족분: hint 없음 → ① 같은 SKU×창고 마지막 레이어 ② 다른 창고 ③ po_price_history.net_unit_cad ④ unknown 0 · sale_shortfall 레이어는 원천에서 뺀다(추정의 추정을 막는다 · 짐작이 아니라 이 파일의 결정) · landed 포함(unit_cost×qty + Σcost_add)/qty
--    over-pick 거부(제자리로 돌아간다 2-f) · 덜 나간 몫 = pick_short 형제(전량 못 나간 줄은 행째 · 일부는 split_from_line_id 줄) · 할당은 나간 줄 'shipped' · 전량 못 나간 줄 'released'
--    bin: '' 받는다(7-b · WMS 칸별 수량 전까지) · 있으면 그 창고 ref_bin 에 있어야(판정 12 · 없으면 거부) · 비활성 칸은 받고 경고 inactive_bin(실물이 그 칸에서 나왔다)
--    되돌리기(reversal consume · 17-f ②)는 이번에 길이 없어 만들지 않았다(11-j 「안 도는 코드 금지」)
-- ⚠️ 다시 만들지 않은 것 — so_split · so_require_role · so_current_staff · so_require_draft · inv_layer_fifo_take · ims_require_write · ims_today · inv_post_receipt
-- ⚠️ 시퀀스: so_ship 은 채번하지 않는다(형제는 so_split 의 접미어) · 검증은 so_create 로 번호를 소비하고 끝에 setval(rollback 밖 · so 0 일 때만)

-- ═══ ① CHECK 확장 ═══
alter table public.inv_layer drop constraint inv_layer_source_ck;
alter table public.inv_layer add constraint inv_layer_source_ck check (cost_source in (
  'inv_cost','snapshot_value','cin7_unitcost',
  'layer_avg','assembly_sum','parent_layer','unknown','return_restore',
  'po_line',
  'free',
  'layer_recent','layer_recent_other_wh','price_history'));                              -- ⭐ 2026-09-24 17-e ①②③ — ④ 는 unknown(0) 그대로
comment on constraint inv_layer_source_ck on public.inv_layer is
  '값의 출처(17-d) — 2026-09-24 셋 더함: layer_recent(같은 SKU×창고 마지막 레이어) · layer_recent_other_wh(다른 창고 마지막 레이어) · price_history(po_price_history 최근 확정 인보이스 단가) — IMS 판매 부족분(sale_shortfall) 레이어에만 쓴다 · unknown(모르는 0)·free(진짜 0)와 섞지 않는다 · 17-g 는 셋을 따로 센다';

alter table public.inv_layer drop constraint inv_layer_origin_ck;
alter table public.inv_layer add constraint inv_layer_origin_ck check (origin_type in (
  'baseline','purchase','transfer','adjust_new',
  'adjust_existing','assembly','creditnote',
  'sale_shortfall'));                                                                   -- ⭐ 2026-09-24 17-d — IMS 판매 부족분 레이어(세우고 즉시 전량 소진 · 잔량 0 · 평가액 무접촉)
comment on constraint inv_layer_origin_ck on public.inv_layer is
  '레이어가 선 사유(17-d 「출처와 사유는 다른 축」) — 2026-09-24 sale_shortfall 더함: IMS 판매(source ims)가 FIFO 로 다 못 꺼낼 때 부족분만큼 세우고 그 자리에서 전량 소진 · doc_number = so_number · received_on = 판매일 · age_known false';

alter table public.so drop constraint if exists so_split_reason_ck;
alter table public.so add  constraint so_split_reason_ck check (split_reason is null or split_reason in ('stock_short','warehouse','preorder','manual','pick_short'));
comment on constraint so_split_reason_ck on public.so is
  '갈라진 계기 다섯(2026-09-24 ③a) — stock_short(장부 부족 · 확정·창고 바꾸기·백오더 진행) · preorder(R2) · manual(오더 나누기 ②b) · pick_short(⭐ 출하 때 실물 부족 — 「장부엔 있었는데 실물이 없었다」 재고 정확도의 신호 7-g · so_ship 이 낳는다 · 할당 없음) · warehouse 는 비어 있다(만드는 길 없음)';

-- ═══ ② so_status_guard 재발행 — 짝 다섯 · 마지막 정의 20260924014219:58 · 바뀐 줄: v_ok 한 줄 · 주석 한 줄 ═══
create or replace function public.so_status_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  v_ok boolean := false;
begin
  if tg_op = 'INSERT' then
    if new.status is distinct from 'draft' then
      raise exception 'A new order must start as draft (got %) — nothing was saved', new.status;
    end if;
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;                                   -- status 그대로 — 머리 고치기 · 줄 수 반영 등은 지나간다
  end if;

  -- 허락 짝 목록 — ② 확정·할당(⬜3) 넷 + ③a 출고(2026-09-24 · ⬜5): packed→shipped(so_ship 의 CAS 플립 · warehouse 길)
  --   ④ POS·counter(confirmed→shipped) · ⑤ Release to WMS · WMS 사건(at_wms · picking · packed · 내려가는 짝 · 6-g′ ⬜) 이 여기에 더한다
  v_ok := (old.status, new.status) in (('draft','confirmed'), ('confirmed','draft'), ('confirmed','cancelled'), ('draft','cancelled'), ('packed','shipped'));

  if not v_ok then
    raise exception 'Order % cannot move from % to % this way — use the order actions — nothing was saved',
      old.so_number, old.status, new.status;
  end if;
  return new;
end;
$$;
comment on function public.so_status_guard() is
  'so BEFORE INSERT OR UPDATE — 자기 행만 보는 전이 문지기(6-g′ · 12-b 판정 6). insert 는 draft 만 · update 로 status 가 바뀌면 허락 짝 목록(v_ok)에 없으면 거부. 짝 다섯(2026-09-24 ③a): draft→confirmed · confirmed→draft · confirmed→cancelled · draft→cancelled · packed→shipped(출고 CAS) — ④⑤ 가 더한다. status 그대로인 update 는 통과 · 소유자·definer 창구도 지난다';

-- ═══ ③ so_reserve.released_reason — 「나가서 닫힘」과 「풀어서 닫힘」을 가른다(⬜4) ═══
--   released(사람이 풀었다 · 보류 · 창고 바꾸기 · 되돌리기 · 전량 못 나간 줄) · shipped(출고 사건이 닫았다 — 나간 줄) · closed(백오더 장부가 닫았다 · ③b)
--   ⚠️ ② 창구 일곱은 released_at 만 찍는다 — 짝 CHECK 를 그대로 걸면 깨진다 ⇒ BEFORE 트리거가 비어 있으면 'released' 를 채운다(회신 이견 6) · 가용 식(released_at is null)은 무변
alter table public.so_reserve add column if not exists released_reason text;
update public.so_reserve set released_reason = 'released' where released_at is not null and released_reason is null;   -- 기존 행(테스트 DB · 흔적 0 이면 0행)
alter table public.so_reserve
  add constraint so_reserve_released_reason_ck check (released_reason is null or released_reason in ('released','shipped','closed')),
  add constraint so_reserve_released_pair_ck   check ((released_at is null) = (released_reason is null));
comment on column public.so_reserve.released_reason is
  '⭐ 닫힌 방식(2026-09-24 ③a · ⬜4) — released(풀었다 · 보류·창고 바꾸기·되돌리기·출하 때 전량 못 나간 줄) · shipped(출고가 닫았다 · 나간 줄) · closed(백오더 장부가 닫았다 · ③b · 세부는 장부). 짝 so_reserve_released_pair_ck · 비어 있으면 트리거 so_reserve_release_reason 이 released 로 채운다(② 창구는 무접촉) · 가용 식은 released_at 만 본다';

create function public.so_reserve_release_reason() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  if new.released_at is null then
    new.released_reason := null;
  elsif new.released_reason is null then
    new.released_reason := 'released';            -- ② 창구 일곱(so_hold · so_reallocate · so_cancel · so_change_location · so_backorder_proceed · so_divide · so_unconfirm)의 풀기
  end if;
  return new;
end;
$$;
comment on function public.so_reserve_release_reason() is 'so_reserve BEFORE INSERT OR UPDATE — released_at 이 있고 released_reason 이 비면 released · released_at 이 비면 reason 도 비운다(짝 CHECK 앞) · 새 창구(so_ship shipped · 장부 closed)는 명시로 넣는다';
revoke all on function public.so_reserve_release_reason() from public, anon;
create trigger so_reserve_release_reason before insert or update on public.so_reserve
  for each row execute function public.so_reserve_release_reason();
-- 트리거 순서(이름 알파벳): so_reserve_release_reason → so_reserve_touch(둘 다 BEFORE · 서로 무관)

-- ═══ ④ inv_layer_post_sale — 원가 층(속 · definer · 두 경로가 부른다: 실시간 inv_post_sale · 재생성 inv_layer_apply_sale_out) ═══
--   FIFO 소진(inv_layer_fifo_take · reason 'sale' · 창고 단위) → 모자라면 17-e 네 단계로 단가를 찾아 sale_shortfall 레이어를 세우고 즉시 전량 소진
--   p_hint(재생성 · 17-f (가)) = 실시간이 raw.cost.shortfall 에 남긴 {qty · unit_cost · cost_source · step · source} — 있으면 찾지 않고 그 값으로 같은 자리에 세운다 · FIFO 는 (qty − hint.qty) 만
--   ⚠️ 원천 레이어의 id 는 재생성에서 바뀐다 — 근거는 값(unit_cost)과 키(doc_number · line_ref · received_on · warehouse)다(회신 이견 3)
--   ⚠️ 원천에서 sale_shortfall 레이어는 뺀다(추정으로 추정을 만들지 않는다) · 단가는 landed 포함 (unit_cost×qty + Σcost_add)/qty(17-e) — ⚠️ fifo_take 의 consume.amount 는 종전대로 unit_cost(landed 제외)다 · 여기서 바꾸지 않는다
create function public.inv_layer_post_sale(
  p_doc_number  text,
  p_line_ref    text,
  p_sku         text,
  p_warehouse   text,
  p_qty         numeric,
  p_occurred_on date,
  p_hint        jsonb default null
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_version   constant text := 'inv_layer_post_sale@2026-09-24.1';
  v_hint      jsonb := case when p_hint is not null and jsonb_typeof(p_hint) = 'object' then p_hint else null end;
  v_hint_qty  numeric;
  v_fifo_need numeric;
  v_rows int;  v_short int;  v_layers int;  v_taken numeric;
  v_fifo_short numeric := 0;
  v_sf_qty    numeric := 0;
  v_unit      numeric;
  v_src       text;
  v_step      int;
  v_source    jsonb;
  v_layer_id  bigint;
  v_sf_amt    numeric := 0;
  v_cogs      numeric;
  x           record;
begin
  if p_qty is null or p_qty <= 0 then
    return jsonb_build_object('sku', p_sku, 'warehouse', p_warehouse, 'qty', p_qty, 'taken_fifo', 0, 'consume_rows', 0, 'fifo_short', 0, 'shortfall', null, 'cogs', 0, 'builder', c_version);
  end if;
  if exists (select 1 from public.inv_layer y
              where y.origin_type = 'sale_shortfall' and y.doc_number = p_doc_number and y.sku = p_sku and y.warehouse = p_warehouse) then
    raise exception 'A shortfall layer for % / % on % already exists — this sale was already costed — nothing was saved', p_sku, p_warehouse, p_doc_number;
  end if;

  v_hint_qty  := case when v_hint is not null then nullif(v_hint->>'qty', '')::numeric else null end;
  v_fifo_need := case when v_hint_qty is not null then p_qty - v_hint_qty else p_qty end;
  if v_fifo_need < 0 then
    raise exception 'Shortfall hint (%) is larger than the sale quantity (%) for % / % on % — the ledger raw is wrong, not this function — nothing was saved',
      v_hint_qty, p_qty, p_sku, p_warehouse, p_doc_number;
  end if;

  -- ① FIFO — 창고 단위 · 있는 레이어는 출처를 안 보고 꺼낸다(17-a)
  select * into v_rows, v_short, v_layers, v_taken
  from public.inv_layer_fifo_take(p_sku, p_warehouse, v_fifo_need, 'sale', p_doc_number, p_line_ref, 'sale_out', p_occurred_on, 'sale', null);
  v_rows := coalesce(v_rows, 0);  v_taken := coalesce(v_taken, 0);

  if v_hint is not null then
    v_sf_qty     := coalesce(v_hint_qty, 0);
    v_fifo_short := v_fifo_need - v_taken;                    -- 재생성이 실시간보다 덜 꺼냈다 — 채우지 않고 보인다(17-f · 재현이 어긋난 신호)
  else
    v_sf_qty     := p_qty - v_taken;
  end if;

  -- ② 부족분 — 최근 원가 레이어(17-d · 17-e)
  if v_sf_qty > 0 then
    if v_hint is not null then
      v_unit   := nullif(v_hint->>'unit_cost', '')::numeric;
      v_src    := coalesce(v_hint->>'cost_source', 'unknown');
      v_step   := nullif(v_hint->>'step', '')::int;
      v_source := v_hint->'source';
      if v_unit is null or v_unit < 0 or v_src not in ('layer_recent','layer_recent_other_wh','price_history','unknown') then
        raise exception 'Shortfall hint for % / % on % has no usable unit_cost/cost_source (%) — the ledger raw is wrong, not this function — nothing was saved', p_sku, p_warehouse, p_doc_number, v_hint::text;
      end if;
    else
      -- ① 같은 SKU×창고 · 마지막으로 세워진 레이어(소진 무관 · received_on desc, id desc) · sale_shortfall 제외
      select y.id, y.doc_number, y.line_ref, y.received_on, y.warehouse,
             (y.unit_cost * y.qty + coalesce((select sum(a.amount) from public.inv_layer_cost_add a where a.layer_id = y.id), 0)) / y.qty as unit
        into x
      from public.inv_layer y
      where y.sku = p_sku and y.warehouse = p_warehouse and y.origin_type <> 'sale_shortfall'
      order by y.received_on desc, y.id desc limit 1;
      if found then
        v_unit := x.unit;  v_src := 'layer_recent';  v_step := 1;
        v_source := jsonb_build_object('layer_id', x.id, 'doc_number', x.doc_number, 'line_ref', x.line_ref, 'received_on', x.received_on, 'warehouse', x.warehouse);
      else
        -- ② 다른 창고의 마지막 레이어
        select y.id, y.doc_number, y.line_ref, y.received_on, y.warehouse,
               (y.unit_cost * y.qty + coalesce((select sum(a.amount) from public.inv_layer_cost_add a where a.layer_id = y.id), 0)) / y.qty as unit
          into x
        from public.inv_layer y
        where y.sku = p_sku and y.warehouse <> p_warehouse and y.origin_type <> 'sale_shortfall'
        order by y.received_on desc, y.id desc limit 1;
        if found then
          v_unit := x.unit;  v_src := 'layer_recent_other_wh';  v_step := 2;
          v_source := jsonb_build_object('layer_id', x.id, 'doc_number', x.doc_number, 'line_ref', x.line_ref, 'received_on', x.received_on, 'warehouse', x.warehouse);
        else
          -- ③ 확정 인보이스 가격(po_price_history · CAD · 환율 없으면 null 이라 건너뛴다)
          select h.net_unit_cad, h.invoice_number, h.invoice_date, h.supplier_name into x
          from public.po_price_history h
          where h.sku = p_sku and h.net_unit_cad is not null
          order by h.invoice_date desc, h.invoice_number desc limit 1;
          if found then
            v_unit := x.net_unit_cad;  v_src := 'price_history';  v_step := 3;
            v_source := jsonb_build_object('invoice_number', x.invoice_number, 'invoice_date', x.invoice_date, 'supplier_name', x.supplier_name);
          else
            -- ④ 모른다 — 0 · 표시가 남는다(17-e ④ · 카운터는 반환 shortfall.step 4 로 센다)
            v_unit := 0;  v_src := 'unknown';  v_step := 4;  v_source := null;
          end if;
        end if;
      end if;
    end if;

    insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
    values (p_sku, p_warehouse, 'sale_shortfall', p_doc_number, p_line_ref, null, p_occurred_on, false, v_sf_qty, v_unit, v_src)
    returning id into v_layer_id;
    insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason)
    values (v_layer_id, 'sale', p_doc_number, p_line_ref, 'sale_out', p_occurred_on, v_sf_qty, v_unit, round(v_sf_qty * v_unit, 6), 'sale');
    v_sf_amt := round(v_sf_qty * v_unit, 6);
    v_rows := v_rows + 1;
  end if;

  select coalesce(sum(c.amount), 0) into v_cogs
  from public.inv_layer_consume c join public.inv_layer l on l.id = c.layer_id
  where c.doc_type = 'sale' and c.doc_number = p_doc_number and c.line_ref = p_line_ref and c.event_type = 'sale_out' and c.reason = 'sale'
    and l.sku = p_sku and l.warehouse = p_warehouse;

  return jsonb_build_object(
    'sku', p_sku, 'warehouse', p_warehouse, 'qty', p_qty,
    'taken_fifo', v_taken, 'consume_rows', v_rows, 'fifo_short', v_fifo_short,
    'shortfall', case when v_sf_qty > 0 then jsonb_build_object('qty', v_sf_qty, 'unit_cost', v_unit, 'cost_source', v_src, 'step', v_step, 'source', v_source,
                                                                'layer_id', v_layer_id, 'amount', v_sf_amt, 'reproduced', v_hint is not null)
                 else null end,
    'cogs', v_cogs, 'builder', c_version);
end;
$$;
comment on function public.inv_layer_post_sale(text, text, text, text, numeric, date, jsonb) is
  '⭐⭐ IMS 판매의 원가 창구(17번 · 2026-09-24 ③a · 실시간·재생성 공용) — 키 (doc_number, sku, warehouse) 한 번: FIFO 소진(inv_layer_fifo_take · reason sale) → 모자라면 최근 원가로 sale_shortfall 레이어를 세우고 즉시 전량 소진(17-d). 최근 원가 네 단계(17-e): ① 같은 SKU×창고 마지막 레이어(layer_recent) ② 다른 창고(layer_recent_other_wh) ③ po_price_history.net_unit_cad(price_history) ④ unknown 0 · sale_shortfall 레이어는 원천에서 뺀다 · landed 포함. p_hint(실시간이 raw.cost.shortfall 에 남긴 값)가 있으면 그 값으로 재현하고 FIFO 는 qty − hint.qty 만(17-f (가)) · 반환 shortfall·cogs·fifo_short. definer · authenticated 없음 — inv_post_sale(실시간) · inv_layer_apply_sale_out(재생성)이 부른다';
revoke all on function public.inv_layer_post_sale(text, text, text, text, numeric, date, jsonb) from public, anon, authenticated;

-- ═══ ⑤ inv_post_sale — 원장 창구(원칙 2 · SO 는 원장에 직접 쓰지 않는다 · inv_post_receipt 20260924001820:1029 와 같은 모양) ═══
--   읽는 것: shipped 오더(창구가 스스로 확인 · 11-j) · p_picks [{line_id, bin, qty}](판매 단위 · so_ship 이 다듬은 것) · 창고 이름 · 낱개 SKU(세트 줄은 parent_product.sku · qty × pack_factor)
--   넣는 것: 줄×칸 한 행 sale_out · seq_hint 2 · doc_type sale · doc_number so_number · doc_task_id so.id · line_ref so_line_id · amount null(수량 원장 · 원가는 inv_layer_consume) · source ims · bin '' 허용
--   ⭐ 순서: 낱개 SKU 키마다 inv_layer_post_sale 먼저(소진·보충) → 그 결과를 raw.cost 에 실어 원장 행 insert(inv_ledger 는 authenticated 에 update 없음 · 회신 이견 3) · 한 트랜잭션(원장 쪽이 실패하면 출고도 실패 — 그것이 맞다 11-j)
--   멱등: 이미 이 so_number 의 ims sale 행이 있으면 안 쓰고 말한다(already_posted) · 레이어는 다시 만들지 않는다(같은 트랜잭션에서 함께 섰다 — PO 백필 경로와 다르다)
--   security invoker(inv_ledger insert 는 authenticated 에 열려 있다) · ⚠️ execute 는 authenticated 에서 뺀다 — so_ship 만 부른다(④⑤ 창구가 소유자 권한으로) · 재생성은 원장 행을 다시 쓰지 않으므로 부르지 않는다
create function public.inv_post_sale(p_so_id uuid, p_picks jsonb, p_occurred_on date) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_post_sale@2026-09-24.1';
  v_so       public.so%rowtype;
  v_wh       text;
  v_existing int;
  v_baseline date;
  v_alloc    jsonb;
  v_bad      text;
  v_costs    jsonb := '{}'::jsonb;
  v_rows     int := 0;
  v_qty      numeric := 0;
  v_warn     text[] := '{}';
  k          record;
  b          record;
begin
  perform public.ims_require_write('sales', 'posted');        -- ⭐ 첫 줄 — 호출자(auth.uid())의 sales 쓰기

  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was posted to the ledger'; end if;
  if v_so.status <> 'shipped' or v_so.shipped_at is null then
    raise exception 'Order % is % — the ledger takes shipped orders only — nothing was posted to the ledger', v_so.so_number, v_so.status;
  end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_so.location_id;
  if v_wh is null then raise exception 'Order % has no warehouse — nothing was posted to the ledger', v_so.so_number; end if;

  -- 멱등 — 이미 기표된 출고는 다시 쓰지 않는다(말하는 0)
  select count(*) into v_existing from public.inv_ledger l
  where l.doc_type = 'sale' and l.doc_number = v_so.so_number and l.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'already_posted', true, 'existing_rows', v_existing,
                              'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 날짜 경고 — 기초선보다 이르면 · 미래면(막지 않는다 · inv_post_receipt 와 같다)
  select (max(s.taken_at) at time zone 'America/Toronto')::date into v_baseline
  from public.inv_snapshot s where s.snapshot_key = (select c.value from public.inv_config c where c.key = 'baseline_snapshot_key');
  if v_baseline is not null and p_occurred_on < v_baseline then v_warn := array_append(v_warn, 'shipped_on_before_baseline'); end if;
  if p_occurred_on > public.ims_today() then v_warn := array_append(v_warn, 'shipped_on_in_future'); end if;

  -- 줄×칸 모으기 — 판매 단위 → EA(pack_factor) · 낱개 SKU(세트 줄은 parent) · 이 오더의 줄만
  select string_agg(distinct p.line_id::text, ', ') into v_bad
  from (select (e->>'line_id')::uuid as line_id from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e) p
  where not exists (select 1 from public.so_line l where l.id = p.line_id and l.so_id = p_so_id);
  if v_bad is not null then
    raise exception 'Pick line % is not on order % — nothing was posted to the ledger', v_bad, v_so.so_number;
  end if;
  with p as (
    select (e->>'line_id')::uuid as line_id, coalesce(nullif(trim(e->>'bin'), ''), '') as bin, (e->>'qty')::numeric as qty
    from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e
  ),
  g as (select line_id, bin, sum(qty) as qty from p group by 1, 2),
  a as (
    select l.id as line_id, l.line_no, l.product_id, l.sku as sold_sku, l.pack_factor, l.unit_price,
           coalesce(pp.sku, pr.sku) as base_sku, g.bin, g.qty, g.qty * l.pack_factor as qty_ea
    from g
    join public.so_line l on l.id = g.line_id and l.so_id = p_so_id
    join public.product pr on pr.id = l.product_id
    left join public.product pp on pp.id = pr.parent_product_id
    where g.qty > 0
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.bin), '[]'::jsonb) into v_alloc from a;
  if jsonb_array_length(v_alloc) = 0 then
    raise exception 'Order % has no picked quantity — nothing was posted to the ledger', v_so.so_number;
  end if;

  -- ⭐ 소진 먼저 — 낱개 SKU 키마다 한 번(창고 하나 · 줄 여럿은 접는다 · consume.line_ref = 첫 줄 · 재생성 키와 같다)
  for k in
    select t.base_sku, sum(t.qty_ea) as qty_ea, (array_agg(t.line_id::text order by t.line_no, t.bin))[1] as line_ref
    from jsonb_to_recordset(v_alloc) as t(base_sku text, qty_ea numeric, line_id uuid, line_no int, bin text)
    group by t.base_sku order by t.base_sku
  loop
    v_costs := v_costs || jsonb_build_object(k.base_sku,
                 public.inv_layer_post_sale(v_so.so_number, k.line_ref, k.base_sku, v_wh, k.qty_ea, p_occurred_on, null));
  end loop;

  -- 원장 행 — 줄×칸 · raw.cost 에 그 키의 소진·보충 결과(재생성이 raw.cost.shortfall 을 hint 로 읽는다 · 17-f (가))
  for b in
    select * from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, sold_sku text, pack_factor numeric, unit_price numeric,
                                                   base_sku text, bin text, qty numeric, qty_ea numeric)
    order by line_no, bin
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (p_occurred_on, 2, b.base_sku, v_wh, b.bin, -b.qty_ea, 'sale_out', 'sale', v_so.so_number, v_so.id::text, b.line_id::text, null, 'ims',
      jsonb_build_object(
        'kind', 'sale_out', 'poster', c_version,
        'so_id', v_so.id, 'so_number', v_so.so_number, 'so_line_id', b.line_id, 'line_no', b.line_no,
        'product_id', b.product_id, 'sku', b.sold_sku, 'base_sku', b.base_sku, 'pack_factor', b.pack_factor,
        'qty', b.qty, 'qty_ea', b.qty_ea, 'unit_price', b.unit_price,
        'warehouse_id', v_so.location_id, 'warehouse', v_wh, 'bin', b.bin,
        'customer_id', v_so.customer_id, 'channel', v_so.channel, 'intake', v_so.intake,
        'shipped_on', p_occurred_on, 'shipped_at', v_so.shipped_at, 'shipped_by', v_so.shipped_by,
        'cost', v_costs->b.base_sku));
    v_rows := v_rows + 1;
    v_qty  := v_qty + b.qty_ea;
  end loop;

  return jsonb_build_object(
    'so_id', v_so.id, 'so_number', v_so.so_number, 'already_posted', false, 'existing_rows', 0,
    'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_costs, 'poster', c_version, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Order % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_so.so_number, sqlerrm;
end;
$$;
comment on function public.inv_post_sale(uuid, jsonb, date) is
  '⭐⭐ 출고의 원장 창구(원칙 2 · 7-b·7-c · 17-f · 2026-09-24 ③a) — shipped 오더의 픽 [{line_id, bin, qty}] 을 줄×칸 sale_out 행으로(낱개 SKU · EA · seq_hint 2 · doc sale/so_number · line_ref so_line_id · source ims · bin 허용 ) · ⭐ 낱개 SKU 키마다 inv_layer_post_sale 을 먼저 불러 FIFO 소진·부족분 레이어를 만들고 그 결과를 raw.cost 에 싣는다(재생성 hint). 멱등(already_posted) · 첫 줄 ims_require_write(sales, posted) · invoker · authenticated 는 execute 없음 — so_ship 만 부른다';
revoke all on function public.inv_post_sale(uuid, jsonb, date) from public, anon, authenticated;

-- ═══ ⑥ so_ship — 출고 엔진(속 함수 · 세 길이 모두 부르는 한 곳 · 7-c · 판정 1) ═══
--   부르는 쪽: ⑤ WMS 사건(packed 오더) · ④ POS·counter(confirmed→shipped 는 그 차수가 짝을 더한다) — 이번엔 부르는 창구가 없다 · 시험은 replica 로 packed 를 만든다(⬜5)
--   한 트랜잭션: ① CAS 플립(첫 쓰기 · 0행이면 조용한 반환 「이미 나갔다」) ② 할당 닫기(shipped · 전량 못 나간 줄 released) ③ 줄 qty_shipped ④ pick_short 형제(할당 없음 · backorder 예약 · 2-f) ⑤ 원장 창구 inv_post_sale(원장 행 + FIFO + 부족분)
--   p_picks [{line_id, bin, qty}] 판매 단위 · 한 줄 여러 칸 · 같은 줄·칸은 합친다 · bin '' 허용 · 있으면 그 창고 ref_bin 에 있어야(판정 12) · 비활성 칸은 받고 경고 · 줄 합 > qty_ordered 거부(over-pick 은 제자리로 2-f) · 줄 합 < qty_ordered 는 차이가 형제
--   p_shipped_on = 원장 occurred_on(재고가 빠진 날 · 기본 ims_today() · 미래 거부) · p_staff = 부르는 창구가 확인한 사람(so_current_staff)
create function public.so_ship(p_so_id uuid, p_picks jsonb, p_staff uuid, p_shipped_on date default null) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  v_wh       public.ref_warehouse%rowtype;
  v_on       date;
  v_bad      text;
  v_norm     jsonb;
  v_lines    jsonb := '[]'::jsonb;
  b_moves    jsonb := '[]'::jsonb;
  b_n        int := 0;
  v_shipped  int := 0;
  v_sib      public.so%rowtype;
  v_warn     text[] := '{}';
  v_ledger   jsonb;
  v_n        int;
  r          record;
begin
  if p_staff is null then raise exception 'so_ship needs the acting staff id — nothing was saved'; end if;

  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status = 'shipped' then                               -- 재호출 멱등 — 예외가 아니라 조용한 반환(7-c · wms_complete_pack)
    return jsonb_build_object('shipped', false, 'reason', 'already_shipped', 'so_number', v_so.so_number, 'shipped_at', v_so.shipped_at, 'shipped_by', v_so.shipped_by);
  end if;
  if v_so.status <> 'packed' then
    raise exception 'Order % is % — only a packed order can ship here (pos and counter shipping comes in a later step) — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if v_so.location_id is null then raise exception 'Order % has no warehouse — nothing was saved', v_so.so_number; end if;
  select * into v_wh from public.ref_warehouse where id = v_so.location_id;
  if not found or not v_wh.is_active then
    raise exception 'Warehouse % of order % is inactive — nothing was saved', coalesce(v_wh.name, '?'), v_so.so_number;
  end if;
  v_on := coalesce(p_shipped_on, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Ship date % is in the future — nothing was saved', v_on; end if;

  -- 픽 다듬기 — 모양 · 줄 · 수량 · 칸
  if p_picks is null or jsonb_typeof(p_picks) <> 'array' or jsonb_array_length(p_picks) = 0 then
    raise exception 'p_picks must be a JSON array of {line_id, bin, qty} — nothing was saved';
  end if;
  if exists (select 1 from jsonb_array_elements(p_picks) e where nullif(e->>'line_id', '') is null or nullif(e->>'qty', '') is null) then
    raise exception 'Every pick needs a line_id and a qty — nothing was saved';
  end if;
  if exists (select 1 from jsonb_array_elements(p_picks) e where (e->>'qty') !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' or (e->>'qty')::numeric <= 0) then
    raise exception 'Every pick needs a positive quantity — nothing was saved';
  end if;
  select string_agg(distinct e->>'line_id', ', ') into v_bad
  from jsonb_array_elements(p_picks) e
  where not exists (select 1 from public.so_line l where l.id = (e->>'line_id')::uuid and l.so_id = p_so_id);
  if v_bad is not null then raise exception 'Pick line % is not on order % — nothing was saved', v_bad, v_so.so_number; end if;
  select string_agg(distinct x.bin, ', ') into v_bad
  from (select coalesce(nullif(trim(e->>'bin'), ''), '') as bin from jsonb_array_elements(p_picks) e) x
  where x.bin <> '' and not exists (select 1 from public.ref_bin rb where rb.warehouse_id = v_so.location_id and rb.name = x.bin);
  if v_bad is not null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bad, v_wh.name; end if;
  select string_agg(distinct x.bin, ', ') into v_bad
  from (select coalesce(nullif(trim(e->>'bin'), ''), '') as bin from jsonb_array_elements(p_picks) e) x
  join public.ref_bin rb on rb.warehouse_id = v_so.location_id and rb.name = x.bin
  where not rb.is_active;
  if v_bad is not null then v_warn := array_append(v_warn, 'inactive_bin:' || v_bad); end if;   -- 받는다 — 실물이 그 칸에서 나왔다(판정 12 · 안)

  select coalesce(jsonb_agg(jsonb_build_object('line_id', g.line_id, 'bin', g.bin, 'qty', g.qty) order by g.line_id, g.bin), '[]'::jsonb) into v_norm
  from (select (e->>'line_id')::uuid as line_id, coalesce(nullif(trim(e->>'bin'), ''), '') as bin, sum((e->>'qty')::numeric) as qty
        from jsonb_array_elements(p_picks) e group by 1, 2) g;

  -- 줄마다 — 열린 allocated 예약이 있어야(packed 오더는 전부 할당 · R1) · 합 > 주문 거부 · 합 < 주문은 차이
  for r in
    select l.id, l.line_no, l.sku, l.qty_ordered, coalesce(s.qty, 0) as shipped,
           exists (select 1 from public.so_reserve x where x.so_line_id = l.id and x.released_at is null and x.kind = 'allocated') as has_alloc
    from public.so_line l
    left join (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s on s.line_id = l.id
    where l.so_id = p_so_id
    order by l.line_no
  loop
    if not r.has_alloc then
      raise exception 'Line % of % (%) has no open allocation — an order must be fully allocated to ship — nothing was saved', r.line_no, v_so.so_number, r.sku;
    end if;
    if r.shipped > r.qty_ordered then
      raise exception 'Line % of % (%): picked % but ordered % — over-pick goes back to its bin, it does not ship — nothing was saved', r.line_no, v_so.so_number, r.sku, r.shipped, r.qty_ordered;
    end if;
    if r.shipped < r.qty_ordered then
      b_moves := b_moves || jsonb_build_object('line_id', r.id, 'qty', r.qty_ordered - r.shipped);  b_n := b_n + 1;
    end if;
    if r.shipped > 0 then v_shipped := v_shipped + 1; end if;
    v_lines := v_lines || jsonb_build_object('line_id', r.id, 'line_no', r.line_no, 'sku', r.sku, 'ordered', r.qty_ordered, 'shipped', r.shipped, 'short', r.qty_ordered - r.shipped);
  end loop;
  if v_shipped = 0 then
    raise exception 'Order % has no picked quantity at all — nothing ships (cancel or hold it with the order actions) — nothing was saved', v_so.so_number;
  end if;

  -- ① CAS 플립 — 첫 쓰기(문지기 packed→shipped) · 0행 = 그 사이 남이 바꿨다
  update public.so set status = 'shipped', shipped_at = now(), shipped_by = p_staff, updated_by = p_staff
  where id = p_so_id and status = 'packed';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order % was not shipped — it may have been changed by someone else just now — nothing was saved', v_so.so_number;
  end if;

  -- ② 할당 닫기(5-f · ⬜4) — 나간 줄 shipped · 전량 못 나간 줄 released(실물이 없었다 · 형제에 backorder 가 선다)
  update public.so_reserve x set released_at = now(), released_by = p_staff, updated_by = p_staff,
         released_reason = case when coalesce(s.qty, 0) > 0 then 'shipped' else 'released' end
  from public.so_line l
  left join (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s on s.line_id = l.id
  where x.so_line_id = l.id and l.so_id = p_so_id and x.released_at is null and x.kind = 'allocated';

  -- ③ 줄 qty_shipped(판매 단위 · 나간 줄만 · 전량 못 나간 줄은 0 그대로 행째 형제로 간다)
  update public.so_line l set qty_shipped = s.qty, updated_by = p_staff
  from (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s
  where s.line_id = l.id and l.so_id = p_so_id;

  -- ④ 출하 차이 → 백오더 형제(2-f · 7-b · ⬜6 pick_short) — 할당 없이 · 물건이 들어와도 자동으로 잡지 않는다 · 재고 조정은 사람이(2-f)
  if b_n > 0 then
    v_sib := public.so_split(p_so_id, 'pick_short', b_moves, 'confirmed', p_staff);
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'backorder', null from public.so_line x where x.so_id = v_sib.id;
  end if;

  -- ⑤ 원장 — 창구 하나(원장 행 + FIFO + 부족분 · 한 트랜잭션 · 실패하면 출고도 실패)
  v_ledger := public.inv_post_sale(p_so_id, v_norm, v_on);

  return jsonb_build_object(
    'shipped', true, 'so_number', v_so.so_number, 'shipped_on', v_on, 'shipped_by', p_staff,
    'lines', v_lines,
    'backorder', case when b_n > 0 then jsonb_build_object('so_id', v_sib.id, 'so_number', v_sib.so_number, 'split_reason', 'pick_short', 'lines', b_n) else null end,
    'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_ship(uuid, jsonb, uuid, date) is
  '⭐⭐ 출고 엔진(7-c · 2-f · 판정 1 · 2026-09-24 ③a) — 세 길이 부르는 한 곳(속 함수 · authenticated 없음 · ④⑤ 의 definer 창구가 so_current_staff 로 p_staff 를 준다). packed 만 · shipped 면 조용한 반환 already_shipped. [{line_id, bin, qty}] 판매 단위 · 칸 여럿 · bin 은 그 창고 ref_bin 에 있어야(빈값 허용 · 비활성 경고) · over-pick 거부 · 덜 나간 몫은 pick_short 형제(backorder 예약). 한 트랜잭션: CAS 플립 → 할당 닫기(shipped/released) → qty_shipped → 형제 → inv_post_sale(원장 행 + FIFO + 부족분 레이어)';
revoke all on function public.so_ship(uuid, jsonb, uuid, date) from public, anon, authenticated;

-- ═══ ⑦ inv_layer_apply_sale_out 재발행 — 재생성이 IMS 판매를 실시간과 같은 함수로(17-f) · 마지막 정의 20260909174046:226 · 더한 줄만(선언 2 · ims 분기 8) ═══
--   cin7 키는 종전 그대로(순액 FIFO · short 는 short · 17-a) · ims 키는 첫 행 raw.cost.shortfall 을 hint 로 inv_layer_post_sale — 같은 자리에 같은 sale_shortfall 레이어(17-f (가))
--   o_short: ims 키는 fifo_short > 0 일 때만(재현이 실시간보다 덜 꺼냈다 = 신호) · 시그니처 그대로(inv_layer_apply 의 select * into 넷)
create or replace function inv_layer_apply_sale_out(p_ledger_id bigint, p_until date,
                                                    out o_rows int, out o_short int,
                                                    out o_processed int, out o_reversed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r       inv_ledger%rowtype;
  v_net   numeric;
  v_rows  int; v_short int; v_layers int; v_taken numeric;
  v_hint  jsonb;                                                          -- ⭐ 2026-09-24 IMS 판매 재현(17-f (가))
  v_j     jsonb;
begin
  o_rows := 0; o_short := 0; o_processed := 0; o_reversed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found then return; end if;

  -- 이미 처리한 키면 끝
  if exists (select 1 from inv_layer_apply_done d
              where d.kind = 'sale' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.warehouse) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('sale', r.doc_number, r.sku, r.warehouse);
  o_processed := 1;

  -- 키 순액 × −1 — ⚠️ line_ref 는 키에 없다(접미어 상쇄 자동 흡수) · source 무관
  select -sum(qty_delta) into v_net
    from inv_ledger
    where event_type = 'sale_out'
      and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);
  if v_net is null or v_net <= 0 then o_reversed := 1; return; end if;   -- 완전 상쇄된 판매

  -- ⭐ 2026-09-24 IMS 판매(source ims) — 실시간 창구와 같은 함수 · 첫 행 raw.cost.shortfall 이 hint(없으면 null → 순수 FIFO · cin7 과 같다)
  if r.source = 'ims' then
    select l.raw->'cost'->'shortfall' into v_hint from inv_ledger l
      where l.event_type = 'sale_out' and l.source = 'ims' and l.doc_number = r.doc_number and l.sku = r.sku and l.warehouse = r.warehouse
        and (p_until is null or l.occurred_on <= p_until)
      order by l.id limit 1;
    v_j := inv_layer_post_sale(r.doc_number, r.line_ref, r.sku, r.warehouse, v_net, r.occurred_on, v_hint);
    o_rows := coalesce((v_j->>'consume_rows')::int, 0);
    o_short := case when coalesce((v_j->>'fifo_short')::numeric, 0) > 0 then 1 else 0 end;
    return;
  end if;

  select * into v_rows, v_short, v_layers, v_taken
    from inv_layer_fifo_take(r.sku, r.warehouse, v_net,
                             r.doc_type, r.doc_number, r.line_ref, r.event_type, r.occurred_on, 'sale', null);
  o_rows := v_rows; o_short := v_short;
end;
$$;
comment on function inv_layer_apply_sale_out(bigint, date) is
  '재생성 보조 — sale_out 키 (doc_number, sku, warehouse) 순액을 한 번 소진(bin 접음 · :reversal 자동 흡수). ⭐ 2026-09-24 ③a: source ims 키는 inv_layer_post_sale 을 첫 행 raw.cost.shortfall 을 hint 로 불러 실시간과 같은 자리에 같은 sale_shortfall 레이어(17-f (가)) · cin7 키는 종전 그대로(short 는 short · 17-a) · o_short 는 ims 키에서 fifo_short(재현이 덜 꺼냄)일 때만';
revoke all on function inv_layer_apply_sale_out(bigint, date) from public, anon, authenticated;

-- ═══ 검증(Caleb · ~/asung/prompts/so-write-3a-verify.sql · psql -v ON_ERROR_STOP=1 -f) ═══
--   출고 12 = 두 칸(8+4) → 원장 두 줄 · 소진 창고 단위 · 합 = FIFO 식 · 두 번째 호출 already_shipped · 할당 shipped · 가용 불변(잔고 −12 · 할당 −12) ·
--   장부 레이어 모자람 → sale_shortfall(layer_recent) 즉시 전량 소진 · raw.cost.shortfall · 평가액 무접촉 · 10/12 → pick_short 형제(backorder 예약) ·
--   over-pick 거부 · 없는 줄 · 없는 칸 · packed 아님 거부 · 재생성(inv_layer_apply)이 소진 합·부족분 레이어를 같게 세운다(17-f) · 100줄 × 2칸 서버 안 시간 · 흔적 0 · setval 25000
