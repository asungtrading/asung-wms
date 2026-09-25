-- SO 쓰기 ④a2 — POS · counter 흐름: so_create·so_status_guard·so_ship·so_confirm·so_allocate_run·so_tier_warnings 재발행 · so_confirm_precheck · so_allocate_all · so_pos_confirm · so_pos_reopen · so_pos_complete · so_pos_finish · so_counter_ship (2026-09-25 UTC · 토론토 2026-09-25)
-- 지시서 ~/asung/prompts/so-pos-1.md §3 B · 판정 회신 Caleb 2026-09-25(판정 1~16 · 이견 0-4~0-8·0-12·0-14·0-15 · 고침 ①② · ⬜3·⬜4·⬜5) · ④a1(20260925133147) 위에 선다 · 정본 §20 은 차수 끝에
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/so-pos-1b-verify.sql(-v mig)
-- 판정: 5 Confirm(금액) → 결제 기록(so_payment_add · 대상 = 이 오더) → Finish(출고 + 발행 · 막지 않는다 · 받은 금액·미수를 보인다) · 6 POS 의 Confirm·다시 열기·Finish = sales(역할 문 없음 · R5 예외) · counter = manager ·
--       12 counter 는 같은 모양(칸을 사람이 바꾼다) · 13 POS·counter 확정은 백오더를 이어받지 않는다 · 14 intake pos 도 직접 오더 경고 · 고침 ② R6 검사는 속 함수 하나(so_confirm_precheck) · 6-d pos·counter 는 재고를 보지 않고 allocated · backorder 없음
--
-- ① so_create 재발행(20260924175014:305~394) — channel 셋 · intake 짝(pos ⇔ pos · counter → manual) · pos·counter 는 p_location_id 필수(계산대·선반의 창고 · ⬜3)
-- ② so_status_guard 재발행(20260925001733:28~58) — 짝 하나 더: confirmed→shipped 는 new.channel in (pos, counter) 일 때만(자기 행 · 6-g′ · 7-c)
-- ③ so_ship 재발행(20260924202425:40~167) — 「아직 안 나감」= pos·counter 는 confirmed · warehouse 는 packed(7-c) · pos·counter 는 목표 아래 픽을 거부(pick_short 없음 · 6-d) · 그 밖 바이트 그대로
-- ④ so_confirm_precheck(p_so) 신설 + so_confirm 재발행(20260924175014:835~914 · R6 블록 → perform 한 줄 · 「pos·counter 는 나중 단계」 거부 문장 그대로)
-- ⑤ so_allocate_run 재발행(20260924015859:68~209) — 첫머리 가드 한 줄(pos·counter 는 엔진을 안 탄다 · so_reallocate·so_change_location·so_backorder_proceed 가 함께 막힌다 · 이견 0-5)
-- ⑥ so_tier_warnings 재발행(20260923191030:84~134) — 직접 오더 경고의 intake 에 pos(판정 14)
-- ⑦ so_allocate_all(속) · so_pos_confirm · so_pos_reopen · so_pos_complete(속 · 미리 보기 식) · so_pos_finish · so_counter_ship
-- ⑧ so_hold · so_divide 재발행(20260924022449:21 · :248) — 길 가드 한 줄씩(훑기 ③ · 검증 6 이 찾았다: hold 는 pos 할당을 풀어 Finish 를 막고 · divide 는 pos 오더를 갈랐다)
-- 검증: ~/asung/prompts/so-pos-1b-verify.sql

-- ═══ ① so_create 재발행 — 마지막 정의 20260924175014:305~394 · 바뀐 줄 6 · 더한 줄 6(길 셋 · intake pos · 짝 · 창고 필수) ═══
create or replace function public.so_create(
  p_customer_id uuid,
  p_channel     text default 'warehouse',
  p_intake      text default 'manual',
  p_location_id uuid default null,
  p_comments    text default null
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  c        public.customer%rowtype;
  v_wh     public.ref_warehouse%rowtype;
  v_so     public.so%rowtype;
  v_copy   jsonb;
  v_warn   text[] := '{}';
  od       record;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 유일한 문 — 첫 줄
  v_staff := public.so_current_staff();

  if p_channel is null or p_channel not in ('warehouse', 'pos', 'counter') then                       -- ④a2: 길 셋(6-b)
    raise exception 'Channel % is not one of warehouse, pos, counter — nothing was saved', coalesce(p_channel, 'null');
  end if;
  if p_intake is null or p_intake not in ('manual', 'csv', 'pos') then
    raise exception 'Intake % is not accepted here — manual, csv or pos (shopify is another path) — nothing was saved', coalesce(p_intake, 'null');
  end if;
  if (p_channel = 'pos') <> (p_intake = 'pos') then                                                     -- ④a2 ⬜3: pos ⇔ intake pos · counter → manual
    raise exception 'Channel % goes with intake % — a pos order has intake pos, a counter order has intake manual — nothing was saved', p_channel, p_intake;
  end if;
  if p_channel in ('pos', 'counter') and p_location_id is null then                                     -- ④a2 ⬜3: 계산대·선반이 있는 창고
    raise exception 'A % order needs the store warehouse (p_location_id) — nothing was saved', p_channel;
  end if;

  select * into c from public.customer where id = p_customer_id;
  if not found then
    raise exception 'Customer not found — nothing was saved';
  end if;
  if not c.is_active then                                       -- 판정 A — 막는다
    raise exception 'Customer % is inactive — reactivate it first — nothing was saved', c.name;
  end if;
  if c.currency_id is null then
    raise exception 'Customer % has no currency — set it on the customer first — nothing was saved', c.name;
  end if;

  if p_location_id is not null then
    select * into v_wh from public.ref_warehouse where id = p_location_id;
    if not found then
      raise exception 'Warehouse not found — nothing was saved';
    end if;
    if not v_wh.is_active then
      raise exception 'Warehouse % is inactive — nothing was saved', v_wh.name;
    end if;
  end if;

  -- so 한 행 — so_number 는 기본값 so_next_number() · status 기본 draft(so_status_guard 가 insert 를 본다) · currency 는 손님 것(so_copy_customer 가 다시 덮는다)
  insert into public.so (customer_id, channel, intake, currency_id, location_id, location_name, comments, created_by, updated_by)
  values (c.id, p_channel, p_intake, c.currency_id, v_wh.id, v_wh.name, nullif(trim(p_comments), ''), v_staff, v_staff)
  returning * into v_so;

  -- 손님 값 복사(①a · 준 창고가 있으면 그대로 · 없으면 손님 default_location) — 티어는 손님 기본(판정 B ①)
  v_copy := public.so_copy_customer(v_so.id, c.id);

  -- 오더 전체 할인(D6 · ⬜4) — 손님·오더 날짜로 찾아 굳힌다(source deal) · 없으면 null 셋
  select * into od from public.so_order_discount(v_so.id);
  if od.pct is not null then
    update public.so set order_discount_pct = od.pct, order_discount_deal_id = od.deal_id, order_discount_source = 'deal', updated_by = v_staff
    where id = v_so.id;
  end if;
  select * into v_so from public.so where id = v_so.id;

  select array_agg(t.v) into v_warn from jsonb_array_elements_text(v_copy->'warnings') as t(v);
  v_warn := coalesce(v_warn, '{}') || public.so_tier_warnings(v_so);

  return jsonb_build_object(
    'id',            v_so.id,
    'so_number',     v_so.so_number,
    'status',        v_so.status,
    'channel',       v_so.channel,
    'intake',        v_so.intake,
    'customer_id',   v_so.customer_id,
    'currency_code', v_so.currency_code,
    'price_tier',    v_so.price_tier,
    'price_tier_id', v_so.price_tier_id,
    'location_id',   v_so.location_id,
    'location_name', v_so.location_name,
    'order_discount_pct',     v_so.order_discount_pct,
    'order_discount_deal_id', v_so.order_discount_deal_id,
    'tax_rule',      v_so.tax_rule,
    'tax_rule_id',   v_so.tax_rule_id,
    'tax_rule_manual', v_so.tax_rule_manual,
    'ship_to_is_company', v_copy->'ship_to_is_company',
    'warnings',      to_jsonb(v_warn));
end;
$$;
comment on function public.so_create(uuid, text, text, uuid, text) is
  '⭐ SO 초안 만들기(SO 쓰기 ①b · 할인 규칙 ②-0b · 세금 ② · ④a2 재발행) — security definer · 첫 줄 ims_require_write(sales). channel warehouse|pos|counter(6-b) · intake manual|csv|pos · pos ⇔ intake pos · counter 는 manual · pos·counter 는 p_location_id 필수(계산대·선반의 창고 · §20 ⬜3) · 만들기는 sales(문은 확정) · 비활성 손님 거부 · 손님 통화 없으면 거부. 손님 값은 so_copy_customer 가 굳힌다(세금 규칙은 배송지 §16 판정 2 · POS 도 같다 §20 판정 9) · 오더 전체 할인 so_order_discount. 반환 warnings = 복사 경고 + so_tier_warnings(intake pos 도 직접 오더로 본다 · 판정 14)';

-- ═══ ② so_status_guard 재발행 — 마지막 정의 20260925001733:28~58 · 바뀐 줄 1 · 더한 줄 1(confirmed→shipped · pos·counter 만) ═══
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
  --   ⓑ2 2026-09-24: shipped→fulfilled(so_invoice_issue · 판정 1 발행이 곧 끝) · fulfilled→shipped(so_invoice_cancel · 8-h 하향) — ⓐ1 의 shipped→invoiced · invoiced→shipped 를 대신한다
  --   ④ POS·counter(confirmed→shipped) · ⑤ Release to WMS · WMS 사건(at_wms · picking · packed · 내려가는 짝 · 6-g′ ⬜) 이 여기에 더한다
  v_ok := (old.status, new.status) in (('draft','confirmed'), ('confirmed','draft'), ('confirmed','cancelled'), ('draft','cancelled'), ('packed','shipped'),
                                        ('shipped','fulfilled'), ('fulfilled','shipped'))
          or (old.status = 'confirmed' and new.status = 'shipped' and new.channel in ('pos', 'counter'));   -- ④a2 2026-09-25: pos·counter 는 confirmed 에서 나간다(7-c · 6-g′ 길별 짝) · warehouse 는 여전히 거부

  if not v_ok then
    raise exception 'Order % cannot move from % to % this way — use the order actions — nothing was saved',
      old.so_number, old.status, new.status;
  end if;
  return new;
end;
$$;
comment on function public.so_status_guard() is
  '⭐ SO 상태 문지기(6-g′ · 12-b 판정 6 · ②a ⬜3 · ③a ⬜5 · ⓑ2 · ④a2) — insert 는 draft 만 · status 가 바뀌는 update 는 허락 짝에 없으면 거부(소유자·definer 창구도 지난다) · 같은 상태의 update 는 통과. 짝 일곱 + 길별 하나: draft→confirmed · confirmed→draft · confirmed→cancelled · draft→cancelled · packed→shipped(so_ship · warehouse) · shipped→fulfilled(so_invoice_issue) · fulfilled→shipped(so_invoice_cancel) · ⭐ confirmed→shipped 는 channel pos·counter 만(so_ship · 7-c). ⑤ Release·WMS 사건(at_wms · picking · packed · 내려가는 짝)이 여기에 더한다';

-- ═══ ③ so_ship 재발행 — 마지막 정의 20260924202425:40~167 · 더한 줄 5(선언 1 · v_from 1 · pos 거부 3) · 바뀐 줄 3(상태 검사 2 · CAS 1) ═══
create or replace function public.so_ship(p_so_id uuid, p_picks jsonb, p_staff uuid, p_shipped_on date default null) returns jsonb
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
  v_from     text;                                              -- ④a2: 「아직 안 나감」 상태 — pos·counter confirmed · warehouse packed(7-c)
begin
  if p_staff is null then raise exception 'so_ship needs the acting staff id — nothing was saved'; end if;

  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status = 'shipped' then                               -- 재호출 멱등 — 예외가 아니라 조용한 반환(7-c · wms_complete_pack)
    return jsonb_build_object('shipped', false, 'reason', 'already_shipped', 'so_number', v_so.so_number, 'shipped_at', v_so.shipped_at, 'shipped_by', v_so.shipped_by);
  end if;
  v_from := case when v_so.channel in ('pos', 'counter') then 'confirmed' else 'packed' end;
  if v_so.status <> v_from then
    raise exception 'Order % is % — only a % order can ship here — nothing was saved', v_so.so_number, v_so.status, v_from;
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
    select l.id, l.line_no, l.sku, l.qty_ordered, l.qty_removed, l.qty_ordered - l.qty_removed as target, coalesce(s.qty, 0) as shipped,   -- ⓐ2 판정 5: 목표 = 주문 − 손님이 뺀 것
           exists (select 1 from public.so_reserve x where x.so_line_id = l.id and x.released_at is null and x.kind = 'allocated') as has_alloc
    from public.so_line l
    left join (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s on s.line_id = l.id
    where l.so_id = p_so_id
    order by l.line_no
  loop
    if not r.has_alloc then
      raise exception 'Line % of % (%) has no open allocation — an order must be fully allocated to ship — nothing was saved', r.line_no, v_so.so_number, r.sku;
    end if;
    if r.shipped > r.target then
      raise exception 'Line % of % (%): picked % but % to ship (ordered % minus removed %) — over-pick goes back to its bin, it does not ship — nothing was saved', r.line_no, v_so.so_number, r.sku, r.shipped, r.target, r.qty_ordered, r.qty_removed;
    end if;
    if r.shipped < r.target and v_so.channel in ('pos', 'counter') then   -- ④a2 6-d: pos·counter 에는 백오더가 없다 — 목표 아래 픽은 거부(줄이려면 다시 열기)
      raise exception 'Line % of % (%): picked % of % to ship — a % order ships only what was scanned (no backorder) — reopen the order and fix the line — nothing was saved', r.line_no, v_so.so_number, r.sku, r.shipped, r.target, v_so.channel;
    end if;
    if r.shipped < r.target then                                -- ⓐ2 판정 5·7: 뺀 몫은 백오더가 아니다 · 목표 아래 차이만 pick_short(할인 그대로)
      b_moves := b_moves || jsonb_build_object('line_id', r.id, 'qty', r.target - r.shipped);  b_n := b_n + 1;
    end if;
    if r.shipped > 0 then v_shipped := v_shipped + 1; end if;
    v_lines := v_lines || jsonb_build_object('line_id', r.id, 'line_no', r.line_no, 'sku', r.sku, 'ordered', r.qty_ordered, 'removed', r.qty_removed, 'to_ship', r.target, 'shipped', r.shipped, 'short', r.target - r.shipped);
  end loop;
  if v_shipped = 0 then
    raise exception 'Order % has no picked quantity at all — nothing ships (cancel or hold it with the order actions) — nothing was saved', v_so.so_number;
  end if;

  -- ① CAS 플립 — 첫 쓰기(문지기 packed→shipped) · 0행 = 그 사이 남이 바꿨다
  update public.so set status = 'shipped', shipped_at = now(), shipped_by = p_staff, updated_by = p_staff
  where id = p_so_id and status = v_from;                       -- ④a2: 문지기 짝 packed→shipped · confirmed→shipped(pos·counter)
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
  '⭐⭐ 출고 엔진(7-c · 2-f · 판정 1 · ③a · ⓐ2 · ④a2 재발행) — 세 길이 부르는 한 곳(속 함수 · authenticated 없음 · so_finalize(warehouse) · so_pos_complete(pos·counter) 가 so_current_staff 로 p_staff 를 준다). 「아직 안 나감」= warehouse packed · pos·counter confirmed(CAS 플립 · 문지기 짝) · shipped 면 조용한 반환 already_shipped. [{line_id, bin, qty}] 판매 단위 · 칸 여럿 · bin 은 그 창고 ref_bin 에 있어야(빈값 허용 · 비활성 경고) · 보낼 목표 = qty_ordered − qty_removed(§17 판정 5) · 목표 초과 픽 거부 · warehouse 는 목표 아래 덜 나간 몫만 pick_short 형제(할인 그대로 판정 7) · ⭐ pos·counter 는 목표 아래 픽 거부(백오더 없음 6-d · 줄이려면 so_pos_reopen). 한 트랜잭션: CAS 플립 → 할당 닫기(shipped/released) → qty_shipped → 형제 → inv_post_sale(원장 행 + FIFO + 부족분 레이어 · 픽만)';
revoke all on function public.so_ship(uuid, jsonb, uuid, date) from public, anon, authenticated;

-- ═══ ④ so_confirm_precheck — R6 검사 한 곳(고침 ② · so_confirm · so_pos_confirm 이 함께 부른다 · 속 함수 · invoker · authenticated 없음) ═══
--   so_confirm 의 R6 블록(20260924175014:869~893)을 바이트 그대로 옮기고 p_so_id → p_so.id 만 바꿨다 · 프리오더 줄 검사는 so_confirm 에 남는다(확정 전용)
create function public.so_confirm_precheck(p_so public.so) returns void
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  c        public.customer%rowtype;
  v_wh     public.ref_warehouse%rowtype;
  v_bad    text;
  v_n      int;
begin
  -- R6 막는 조건 — 손님 · 창고 · 줄
  select * into c from public.customer where id = p_so.customer_id;
  if not found or not c.is_active then
    raise exception 'Customer % is inactive — reactivate it first — nothing was saved', coalesce(c.name, '?');
  end if;
  if p_so.location_id is null then
    raise exception 'Order % has no warehouse — set one before confirming — nothing was saved', p_so.so_number;
  end if;
  select * into v_wh from public.ref_warehouse where id = p_so.location_id;
  if not found or not v_wh.is_active then                       -- IN_TRANSIT 은 is_active=false 로 들어 있어 여기서 걸린다(이견 11)
    raise exception 'Warehouse % is inactive — pick an active warehouse — nothing was saved', coalesce(v_wh.name, '?');
  end if;
  select count(*) into v_n from public.so_line where so_id = p_so.id;
  if v_n = 0 then
    raise exception 'Order % has no lines — nothing was saved', p_so.so_number;
  end if;
  select string_agg(l.sku, ', ' order by l.line_no) into v_bad from public.so_line l where l.so_id = p_so.id and l.unit_price is null;
  if v_bad is not null then
    raise exception 'Order % has lines without a price (%) — give them a price first — nothing was saved', p_so.so_number, v_bad;
  end if;
  select string_agg(l.sku, ', ' order by l.line_no) into v_bad
  from public.so_line l join public.product p on p.id = l.product_id where l.so_id = p_so.id and not p.is_active;
  if v_bad is not null then
    raise exception 'Order % has inactive products (%) — remove them first — nothing was saved', p_so.so_number, v_bad;
  end if;
  if p_so.tax_rule_id is null then                              -- 세금 ② R6 — 세금을 모르면 인보이스를 낼 수 없다(가격 없는 줄과 같은 이유) · 배송지 주를 채우거나 tax_rule 을 고른다
    raise exception 'Order % has no tax rule — set the ship-to province (or pick a tax rule) first — nothing was saved', p_so.so_number;
  end if;
end;
$$;
comment on function public.so_confirm_precheck(public.so) is 'SO 창구 속 함수(R6 · §20 고침 ②) — 확정을 막는 조건 한 곳: 비활성 손님 · 창고 없음/비활성(IN_TRANSIT) · 줄 없음 · 가격 없는 줄 · 비활성 제품 · 세금 규칙 없음(§16) · so_confirm(warehouse) · so_pos_confirm(pos·counter) 이 함께 부른다 · 프리오더 줄 검사는 so_confirm 만 · authenticated 직접 호출 불가';
revoke all on function public.so_confirm_precheck(public.so) from public, anon, authenticated;

-- ═══ ④-b so_confirm 재발행 — 마지막 정의 20260924175014:835~914 · 뺀 줄 25(R6 블록) → 더한 줄 1(perform) · 그 밖 바이트 그대로(「pos·counter 는 나중 단계」 거부 · 선언 c·v_wh 그대로) ═══
create or replace function public.so_confirm(
  p_so_id              uuid,
  p_preorder_line_ids  uuid[]  default '{}'::uuid[],   -- 사람이 고른 프리오더 줄(6-d) · 따로 뗀다(R2)
  p_hold               boolean default false,          -- 처음부터 보류로 확정(R3 · 오더 전체 · 재고를 잡지 않고 나누지 않는다)
  p_commit             boolean default true            -- false = 미리 보기(무엇이 할당·백오더·프리오더로 가나)
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  c        public.customer%rowtype;
  v_wh     public.ref_warehouse%rowtype;
  v_bad    text;
  v_n      int;
  v_warn   text[] := '{}';
  v_res    jsonb;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — sales 묶음
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — manager 이상(R5)
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  if v_so.channel <> 'warehouse' then
    raise exception 'Order % is a % order — confirming pos and counter orders comes in a later step — nothing was saved', v_so.so_number, v_so.channel;
  end if;
  if p_hold and coalesce(array_length(p_preorder_line_ids, 1), 0) > 0 then
    raise exception 'Choose either hold (whole order) or preorder lines, not both — nothing was saved';
  end if;

  perform public.so_confirm_precheck(v_so);                    -- R6 막는 조건 — 손님 · 창고 · 줄 · 세금(고침 ② · so_pos_confirm 과 한 곳)
  select string_agg(x::text, ', ') into v_bad
  from unnest(coalesce(p_preorder_line_ids, '{}'::uuid[])) x where not exists (select 1 from public.so_line l where l.id = x and l.so_id = p_so_id);
  if v_bad is not null then
    raise exception 'Preorder line % is not on order % — nothing was saved', v_bad, v_so.so_number;
  end if;

  -- 경고(막지 않는다) — 티어·통화 · 다시 매기기 권고 · 세일 끝난 뒤 넣은 줄
  v_warn := public.so_tier_warnings(v_so);
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  if exists (select 1 from public.so_line l where l.so_id = p_so_id and l.deal_line_id is not null
               and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)) then
    v_warn := array_append(v_warn, 'deal_ended_before_line_added');
  end if;

  v_res := public.so_allocate_run(p_so_id, v_so.location_id, p_preorder_line_ids, p_hold, true, p_commit, v_staff);
  if p_commit then                                               -- ③b 판정 4·5·8: 같은 손님·같은 제품의 열린 백오더 줄을 이어받는다(가족 밖 · 브랜치 무관 · 가장 오래된 줄부터 · 나머지는 더 원하지 않음)
    v_res := v_res || jsonb_build_object('superseded', public.so_backorder_supersede(p_so_id, v_staff));
  end if;
  return v_res || jsonb_build_object('warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_confirm(uuid, uuid[], boolean, boolean) is
  '⭐ SO 확정(②a · R1·R2·R3·R5·R6 · 6-d · 세금 ② · ④a2 재발행) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · draft 만 · warehouse 채널만(pos·counter 는 so_pos_confirm · §20). 막는 것: so_confirm_precheck(비활성 손님 · 창고 없음/비활성 · 줄 없음 · 가격 없는 줄 · 비활성 제품 · 세금 규칙 없음) · 오더 밖 프리오더 줄 · hold 와 preorder 동시. 경고: 티어·통화 · reprice_suggested · deal_ended_before_line_added. 엔진 so_allocate_run · commit 이면 열린 백오더 이어받기(③b). 반환 {so_number · status · committed · keeps · lines[] · siblings[] · superseded · warnings}';

-- ═══ ⑤ so_allocate_run 재발행 — 마지막 정의 20260924015859:68~209 · 더한 줄 1(길 가드 — so_confirm·so_reallocate·so_change_location·so_backorder_proceed 가 함께 막힌다) ═══
create or replace function public.so_allocate_run(p_so_id uuid, p_location_id uuid, p_preorder_line_ids uuid[], p_hold boolean, p_confirm boolean, p_commit boolean, p_staff uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so      public.so%rowtype;
  l         record;
  v_key     text;
  v_rem     numeric;
  v_alloc   numeric;
  v_avail   jsonb := '{}'::jsonb;                    -- 낱개 제품 → 남은 가용(EA) · 이번 실행 안에서만 · 잠금 뒤 so_available_many 한 문장으로 채운다
  v_pids    uuid[] := '{}';                          -- 이 오더의 낱개 제품(잠금 순서대로)
  v_plan    jsonb := '[]'::jsonb;
  a_ids     uuid[] := '{}';  a_qty numeric[] := '{}';       -- A 할당(줄 · 잡는 수량)
  b_moves   jsonb := '[]'::jsonb;  b_n int := 0;             -- B 백오더 [{line_id, qty}]
  p_moves   jsonb := '[]'::jsonb;  p_n int := 0;             -- P 프리오더
  v_keep    text;
  v_sib_b   public.so%rowtype;  v_sib_p public.so%rowtype;
  v_sibs    jsonb := '[]'::jsonb;
  v_n       int;
  i         int;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel <> 'warehouse' then raise exception 'Order % is a % order — pos and counter orders do not use the allocation engine (so_pos_confirm · so_pos_reopen) — nothing was saved', v_so.so_number, v_so.channel; end if;   -- ④a2 이견 0-5
  if p_location_id is null then raise exception 'Order % has no warehouse — set one before confirming — nothing was saved', v_so.so_number; end if;

  -- 잠금 — (창고, 낱개 제품) 오름차순 · 줄마다(5-f) · 두 매니저가 같은 제품을 반대 순서로 잡을 수 없다(⬜4)
  for l in
    select x.id, coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_line x join public.product p on p.id = x.product_id
    where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
    order by 2, 1
  loop
    perform pg_advisory_xact_lock(hashtext('so_avail:' || p_location_id::text || ':' || l.stock_pid::text));
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || l.id::text));
    v_pids := array_append(v_pids, l.stock_pid);
  end loop;

  -- 가용 — 잠금 뒤 한 번 · 오더의 낱개 제품 전부를 한 문장으로(so_available_many · 뷰를 한 번만 계산한다) · 음수는 0
  if not p_hold and coalesce(array_length(v_pids, 1), 0) > 0 then
    select coalesce(jsonb_object_agg(m.stock_pid::text, greatest(m.available_ea, 0)), '{}'::jsonb) into v_avail
    from public.so_available_many(v_pids, p_location_id) m;
  end if;

  -- 줄마다 판정(모체 line_no 순 — 같은 제품이 두 줄이면 앞 줄이 먼저 잡는다)
  for l in
    select x.*, coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_line x join public.product p on p.id = x.product_id
    where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
    order by x.line_no
  loop
    if p_hold then
      v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                             'kind', 'hold', 'allocated', 0, 'backordered', 0, 'preorder', 0);
      a_ids := array_append(a_ids, l.id);  a_qty := array_append(a_qty, l.qty_ordered);
      continue;
    end if;
    if l.id = any(coalesce(p_preorder_line_ids, '{}'::uuid[])) then
      v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                             'kind', 'preorder', 'allocated', 0, 'backordered', 0, 'preorder', l.qty_ordered);
      p_moves := p_moves || jsonb_build_object('line_id', l.id, 'qty', l.qty_ordered);  p_n := p_n + 1;
      continue;
    end if;
    v_key := l.stock_pid::text;
    v_rem   := coalesce((v_avail->>v_key)::numeric, 0);
    v_alloc := least(l.qty_ordered, floor(v_rem / l.pack_factor));
    v_avail := v_avail || jsonb_build_object(v_key, v_rem - v_alloc * l.pack_factor);
    v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                           'available_ea_before', v_rem,
                                           'kind', case when v_alloc = l.qty_ordered then 'allocated' when v_alloc = 0 then 'backorder' else 'partial' end,
                                           'allocated', v_alloc, 'backordered', l.qty_ordered - v_alloc, 'preorder', 0);
    if v_alloc > 0 then a_ids := array_append(a_ids, l.id);  a_qty := array_append(a_qty, v_alloc); end if;
    if v_alloc < l.qty_ordered then
      b_moves := b_moves || jsonb_build_object('line_id', l.id, 'qty', l.qty_ordered - v_alloc);  b_n := b_n + 1;
    end if;
  end loop;

  if coalesce(array_length(a_ids, 1), 0) = 0 and b_n = 0 and p_n = 0 then
    raise exception 'Order % has no lines to allocate — nothing was saved', v_so.so_number;
  end if;

  -- 어느 무리가 원래 번호를 지키나(이견 1) — hold 는 전부 원래(나누지 않는다)
  v_keep := case when p_hold then 'hold'
                 when coalesce(array_length(a_ids, 1), 0) > 0 then 'allocated'
                 when b_n > 0 then 'backorder'
                 else 'preorder' end;

  if not p_commit then
    return jsonb_build_object('so_number', v_so.so_number, 'committed', false, 'keeps', v_keep, 'lines', v_plan,
      'siblings', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
         select jsonb_build_object('split_reason', 'stock_short', 'lines', b_n) as x where b_n > 0 and v_keep <> 'backorder' and not p_hold
         union all
         select jsonb_build_object('split_reason', 'preorder', 'lines', p_n) where p_n > 0 and v_keep <> 'preorder' and not p_hold) z));
  end if;

  -- 확정(so_confirm) — 원래를 draft → confirmed 로 먼저 올린다(형제가 확정 흔적을 물려받는다)
  if p_confirm then
    update public.so set status = 'confirmed', confirmed_at = now(), confirmed_by = p_staff, updated_by = p_staff
    where id = p_so_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not confirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;
  end if;

  -- 형제 — 원래가 지키지 않는 무리만(빈 문서 없음) · B 가 앞 글자
  if b_n > 0 and v_keep <> 'backorder' then
    v_sib_b := public.so_split(p_so_id, 'stock_short', b_moves, 'confirmed', p_staff);
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'backorder', null from public.so_line x where x.so_id = v_sib_b.id;
    v_sibs := v_sibs || jsonb_build_object('so_id', v_sib_b.id, 'so_number', v_sib_b.so_number, 'split_reason', 'stock_short', 'lines', b_n);
  end if;
  if p_n > 0 and v_keep <> 'preorder' then
    v_sib_p := public.so_split(p_so_id, 'preorder', p_moves, 'confirmed', p_staff);
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'preorder', p_staff from public.so_line x where x.so_id = v_sib_p.id;
    v_sibs := v_sibs || jsonb_build_object('so_id', v_sib_p.id, 'so_number', v_sib_p.so_number, 'split_reason', 'preorder', 'lines', p_n);
  end if;

  -- 원래에 남은 줄의 예약
  if v_keep = 'hold' then
    for i in 1 .. coalesce(array_length(a_ids, 1), 0) loop
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (a_ids[i], a_qty[i], 'hold', p_staff);
    end loop;
  elsif v_keep = 'allocated' then
    for i in 1 .. array_length(a_ids, 1) loop                                          -- a_qty = 잡는 수량 = so_split 뒤 그 줄의 qty_ordered
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (a_ids[i], a_qty[i], 'allocated', null);
    end loop;
  elsif v_keep = 'backorder' then
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'backorder', null from public.so_line x where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null);
  else
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'preorder', p_staff from public.so_line x where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null);
  end if;

  select * into v_so from public.so where id = p_so_id;
  return jsonb_build_object('so_number', v_so.so_number, 'status', v_so.status, 'committed', true, 'keeps', v_keep, 'lines', v_plan, 'siblings', v_sibs);
end;
$$;

-- ═══ ⑥ so_tier_warnings 재발행 — 마지막 정의 20260923191030:84~134 · create → create or replace · 바뀐 줄 1(intake pos) · 부르는 넷(so_create·so_header_update·so_confirm·so_detail)은 이름으로 부른다 ═══
create or replace function public.so_tier_warnings(s public.so) returns text[]
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_warn  text[] := '{}';
  v_tier  public.ref_price_tier%rowtype;
  v_cfg   text;
  v_cfg_code smallint;
  v_cust_tier text;
  v_cust_tier_id uuid;
begin
  if s.price_tier_id is null then
    v_warn := array_append(v_warn, 'price_tier_missing');
  else
    select * into v_tier from public.ref_price_tier where id = s.price_tier_id;
    if v_tier.purpose <> 'sale'            then v_warn := array_append(v_warn, 'price_tier_not_for_sale'); end if;
    if not v_tier.is_active                then v_warn := array_append(v_warn, 'price_tier_inactive');     end if;
    if v_tier.currency_id <> s.currency_id then v_warn := array_append(v_warn, 'currency_mismatch');       end if;
  end if;

  -- ③ 직접 만든 오더의 티어가 설정(code)과 다르다 — 설정이 없거나 숫자가 아니거나 표에 없으면 그 사실만
  if s.intake in ('manual', 'csv', 'pos') then                  -- ④a2 판정 14: POS 도 손님 기본 티어 · 직접 오더와 같은 경고
    select k.value into v_cfg from public.inv_config k where k.key = 'so_direct_order_tier_code';
    if v_cfg is null or v_cfg !~ '^[0-9]{1,2}$' then
      v_warn := array_append(v_warn, 'direct_order_tier_config_missing');
    else
      v_cfg_code := v_cfg::smallint;
      if not exists (select 1 from public.ref_price_tier t where t.code = v_cfg_code) then
        v_warn := array_append(v_warn, 'direct_order_tier_config_missing');
      elsif s.price_tier_id is not null and v_tier.code is distinct from v_cfg_code then
        v_warn := array_append(v_warn, 'direct_order_tier_unexpected');
      end if;
    end if;
  end if;

  -- ④ 오더 티어 ≠ 손님 원문으로 찾은 티어 · 손님 티어를 못 찾으면 그 사실도
  select c.price_tier into v_cust_tier from public.customer c where c.id = s.customer_id;
  if v_cust_tier is null then
    v_warn := array_append(v_warn, 'customer_tier_missing');
  else
    select t.id into v_cust_tier_id from public.ref_price_tier t where t.name = v_cust_tier;
    if v_cust_tier_id is null then
      v_warn := array_append(v_warn, 'customer_tier_missing');
    elsif v_cust_tier_id is distinct from s.price_tier_id then
      v_warn := array_append(v_warn, 'tier_differs_from_customer');
    end if;
  end if;
  return v_warn;
end;
$$;

-- ═══ ⑦-a so_allocate_all — pos·counter 전용 할당(속 · 재고를 보지 않고 전 줄 allocated · 나누지 않는다 · 6-d) ═══
create function public.so_allocate_all(p_so_id uuid, p_staff uuid) returns int
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  l    record;
  v_n  int := 0;
begin
  for l in
    select x.id from public.so_line x
    where x.so_id = p_so_id and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
    order by x.line_no
  loop
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || l.id::text));
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'allocated', p_staff from public.so_line x where x.id = l.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function public.so_allocate_all(uuid, uuid) is 'SO 창구 속 함수(§20 6-d · 판정 13) — pos·counter 확정의 할당: 열린 예약이 없는 줄 전부에 allocated(qty_ordered · 재고 수치를 보지 않는다 · 실물을 손에 쥔 길) · 백오더·프리오더·hold 없음 · 나누지 않음 · 이어받기 없음 · so_pos_confirm 이 부른다 · authenticated 직접 호출 불가';
revoke all on function public.so_allocate_all(uuid, uuid) from public, anon, authenticated;

-- ═══ ⑦-b so_pos_confirm — pos·counter 확정(창구 · definer · pos = sales · counter = + manager · 판정 6·12·13) ═══
create function public.so_pos_confirm(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_so    public.so%rowtype;
  v_n     int;
  v_warn  text[] := '{}';
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 6: POS 는 sales 만(R5 예외)
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');
  if v_so.channel = 'warehouse' then
    raise exception 'Order % is a warehouse order — confirm it with so_confirm — nothing was saved', v_so.so_number;
  end if;
  if v_so.channel = 'counter' then
    perform public.so_require_role('manager', 'saved');        -- ⭐ counter 는 manager 이상(6-b · 판정 12)
  end if;
  perform 1 from public.so s where s.id = p_so_id for update;
  perform public.so_confirm_precheck(v_so);                    -- R6(고침 ② · so_confirm 과 한 곳)

  v_n := public.so_allocate_all(p_so_id, v_staff);            -- 전 줄 allocated · 재고 안 봄 · 이어받기 없음(판정 13)
  update public.so set status = 'confirmed', confirmed_at = now(), confirmed_by = v_staff, updated_by = v_staff
  where id = p_so_id and status = 'draft';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Order % was not confirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

  v_warn := public.so_tier_warnings(v_so);                     -- 판정 14: intake pos 도 직접 오더 경고
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'channel', v_so.channel, 'status', 'confirmed',
                            'lines_allocated', (select count(*) from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = p_so_id and r.released_at is null and r.kind = 'allocated'),
                            'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_pos_confirm(uuid) is '⭐ POS·counter 확정(§20 판정 6·12·13 · 6-d) — definer · 첫 줄 ims_require_write(sales) · counter 는 + so_require_role(manager) · draft 만 · warehouse 오더는 거부(so_confirm) · R6 = so_confirm_precheck · 할당 = so_allocate_all(전 줄 allocated · 재고 안 봄 · 나누지 않음) · ⭐ 백오더를 이어받지 않는다(판정 13) · 경고 so_tier_warnings(intake pos 포함 · 판정 14) · reprice_suggested';
revoke all on function public.so_pos_confirm(uuid) from public, anon;
grant execute on function public.so_pos_confirm(uuid) to authenticated;

-- ═══ ⑦-c so_pos_reopen — 다시 열기(confirmed → draft · 열린 allocated 풀기 · pos = sales · counter = manager · 형제·사슬 없음) ═══
create function public.so_pos_reopen(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_so    public.so%rowtype;
  v_n     int;
  v_rel   int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel = 'warehouse' then
    raise exception 'Order % is a warehouse order — use so_unconfirm (supervisor) — nothing was saved', v_so.so_number;
  end if;
  if v_so.channel = 'counter' then
    perform public.so_require_role('manager', 'saved');        -- ⭐ counter 는 manager 이상
  end if;
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — only a confirmed % order can be reopened — nothing was saved', v_so.so_number, v_so.status, v_so.channel;
  end if;
  if exists (select 1 from public.so x where x.split_from_id = p_so_id) then
    raise exception 'Order % has split-off orders — a pos/counter order should never split; use so_unconfirm — nothing was saved', v_so.so_number;
  end if;

  update public.so_reserve r set released_at = now(), released_by = v_staff, released_reason = 'released', updated_by = v_staff
  from public.so_line l where r.so_line_id = l.id and l.so_id = p_so_id and r.released_at is null;
  get diagnostics v_rel = row_count;
  update public.so set status = 'draft', confirmed_at = null, confirmed_by = null, updated_by = v_staff
  where id = p_so_id and status = 'confirmed';                                                       -- 문지기 짝 confirmed→draft
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Order % was not reopened — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;
  return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'channel', v_so.channel, 'status', 'draft', 'reservations_released', v_rel);
end;
$$;
comment on function public.so_pos_reopen(uuid) is '⭐ POS·counter 다시 열기(§20 판정 6·16 · 6-f Confirm~Finish 구간) — definer · 첫 줄 ims_require_write(sales) · counter 는 + manager · confirmed 만 · warehouse 오더는 거부(so_unconfirm) · 열린 예약 전부 released(reason released) · confirmed→draft · confirmed_at/by 비움 · 형제·사슬·이어받기 없음(pos 는 나뉘지 않는다 · 판정 13) · 초안에서 줄을 빼고 다시 so_pos_confirm';
revoke all on function public.so_pos_reopen(uuid) from public, anon;
grant execute on function public.so_pos_reopen(uuid) to authenticated;

-- ═══ ⑦-d so_pos_complete — Finish·「나갔다」의 속(칸 계획 → so_ship → so_invoice_issue · 미리 보기는 읽기로 발행 ①②③ 을 옮겨 적는다 · 이견 0-8) ═══
--   미리 보기 식(so_invoice_issue 20260925014413:346~404 와 같은 순서 · 읽기만): 총액 = so_tax_preview(ordered · 출고 전 = 전량) ·
--   ① 이 오더 대상 선결제(받은 날 순 · least(남은 금액, 남은 인보이스, received 진행값)) ② 크레딧 = least(남은, owed_credit) ③ 받아 둔 돈 = least(남은, received(① 차감 뒤) − 다른 열린 오더가 예약한 몫)
--   ⚠️ 식이 두 곳 — 검증이 「미리 보기 = 발행 결과」를 판정한다 · 어긋나는 실물이 나오면 발행에서 뗀다
create function public.so_pos_complete(p_so_id uuid, p_picks jsonb, p_staff uuid, p_commit boolean) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  v_plan     jsonb;
  v_picks    jsonb;
  v_prev     jsonb;
  v_total    numeric;
  v_left     numeric;
  v_dep      numeric := 0;  v_cred numeric := 0;  v_bal numeric := 0;
  v_recv     numeric;  v_owed numeric;  v_res_other numeric;  v_avail numeric;
  v_cust     uuid;
  v_take     numeric;
  v_dep_map  jsonb := '{}'::jsonb;                              -- payment_id → ① 에서 쓴 금액(③ 의 예약 몫 계산)
  pay        record;
  v_est      jsonb;
  v_ship     jsonb;  v_iss jsonb;
  v_inv_id   uuid;
  v_warn     text[] := '{}';
  v_tw       text[];
begin
  if p_staff is null then raise exception 'so_pos_complete needs the acting staff id — nothing was saved'; end if;
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel not in ('pos', 'counter') then raise exception 'Order % is a % order — finish it with so_finalize — nothing was saved', v_so.so_number, v_so.channel; end if;
  if v_so.status <> 'confirmed' then raise exception 'Order % is % — only a confirmed % order can be finished — nothing was saved', v_so.so_number, v_so.status, v_so.channel; end if;

  -- 칸 계획(판정 1·2·4) — 준 픽이 없으면 계획 그대로 · counter 가 준 픽은 so_ship 이 검사한다(줄·칸·수량)
  v_plan := public.so_pick_plan(p_so_id);
  v_picks := coalesce(nullif(p_picks, 'null'::jsonb), v_plan->'picks');
  if v_picks is null or jsonb_typeof(v_picks) <> 'array' or jsonb_array_length(v_picks) = 0 then
    raise exception 'Order % has nothing to ship — nothing was saved', v_so.so_number;
  end if;
  select array_agg(t.w) into v_tw from jsonb_array_elements_text(coalesce(v_plan->'warnings', '[]'::jsonb)) as t(w);
  v_warn := v_warn || coalesce(v_tw, '{}');

  -- 미리 보기 금액(판정 5 · 누르기 전에 받은 금액·미수) — 발행 ①②③ 과 같은 순서를 읽기로
  v_prev := public.so_tax_preview(p_so_id, public.ims_today(), null, 'ordered');
  if v_prev->'totals'->>'tax' is null then raise exception 'Order % has no tax rule for its ship-to address — pick a tax rule on the order — nothing was saved', v_so.so_number; end if;
  v_total := (v_prev->'totals'->>'total')::numeric;
  v_cust := coalesce(v_so.bill_to_customer_id, v_so.customer_id);
  select b.received, b.owed_credit into v_recv, v_owed from public.so_customer_balance(v_cust) b where b.currency_id = v_so.currency_id;
  v_recv := coalesce(v_recv, 0);  v_owed := coalesce(v_owed, 0);
  v_left := v_total;
  for pay in
    select p.id, p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null), 0) as remaining
      from public.so_payment p
     where p.customer_id = v_cust and p.currency_id = v_so.currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o where o.payment_id = p.id and o.so_id = p_so_id)
     order by p.paid_on, p.created_at, p.id
  loop
    exit when v_left <= 0;
    if pay.remaining <= 0 then continue; end if;
    v_take := least(pay.remaining, v_left, v_recv);
    if v_take <= 0 then continue; end if;
    v_dep := v_dep + v_take;  v_left := v_left - v_take;  v_recv := v_recv - v_take;
    v_dep_map := jsonb_set(v_dep_map, array[pay.id::text], to_jsonb(v_take));
  end loop;
  if v_left > 0 then
    v_cred := least(v_left, greatest(v_owed, 0));  v_left := v_left - v_cred;
  end if;
  if v_left > 0 then
    -- 발행 뒤 이 오더는 fulfilled 라 이 오더만 대상인 선결제의 예약은 풀린다 — 다른 열린 오더(살아 있는 인보이스 없음)를 대상으로 한 선결제의 남은 몫만 예약으로 남는다
    select coalesce(sum(p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null), 0) - coalesce((v_dep_map->>(p.id::text))::numeric, 0)), 0)
      into v_res_other
      from public.so_payment p
     where p.customer_id = v_cust and p.currency_id = v_so.currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o join public.so s on s.id = o.so_id
                    where o.payment_id = p.id and s.id <> p_so_id and s.status not in ('fulfilled', 'cancelled')
                      and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id));
    v_avail := greatest(v_recv - v_res_other, 0);
    v_bal := least(v_left, v_avail);  v_left := v_left - v_bal;
  end if;
  v_est := jsonb_build_object('total', v_total, 'deposit', v_dep, 'credit', v_cred, 'balance', v_bal, 'amount_due', v_total - v_dep - v_cred - v_bal, 'remaining', v_left,
                              'received_before', (select b.received from public.so_customer_balance(v_cust) b where b.currency_id = v_so.currency_id));

  if not p_commit then
    return jsonb_build_object('committed', false, 'so_id', v_so.id, 'so_number', v_so.so_number, 'channel', v_so.channel, 'picks', v_picks, 'plan', v_plan->'lines',
                              'short_ea_total', v_plan->'short_ea_total', 'estimate', v_est, 'tax', v_prev->'totals', 'warnings', to_jsonb(v_warn));
  end if;

  -- 실행 — 출고(pos·counter 는 confirmed→shipped · 목표 아래 픽은 so_ship 이 거부) → 발행 한 장(발행일 오늘 · 발행 순간 fulfilled · 자동 붙이기 ①②③)
  v_ship := public.so_ship(p_so_id, v_picks, p_staff, null);
  select array_agg(t.w) into v_tw from jsonb_array_elements_text(coalesce(v_ship->'warnings', '[]'::jsonb)) as t(w);
  v_warn := v_warn || coalesce(v_tw, '{}');
  v_iss := public.so_invoice_issue(array[p_so_id], p_staff, null);
  v_inv_id := (v_iss->>'invoice_id')::uuid;
  select array_agg(t.w) into v_tw from jsonb_array_elements_text(coalesce(v_iss->'warnings', '[]'::jsonb)) as t(w);
  v_warn := v_warn || coalesce(v_tw, '{}');

  return jsonb_build_object('committed', true, 'so_id', v_so.id, 'so_number', v_so.so_number, 'channel', v_so.channel, 'status', 'fulfilled',
                            'invoice_id', v_inv_id, 'invoice_number', v_iss->>'invoice_number', 'issued_on', v_iss->'issued_on', 'due_on', v_iss->'due_on',
                            'totals', v_iss->'totals', 'received', jsonb_build_object('deposit_applied', v_iss->'totals'->'deposit_applied', 'credit_applied', v_iss->'totals'->'credit_applied', 'balance_forward', v_iss->'totals'->'balance_forward'),
                            'amount_due', v_iss->'totals'->'amount_due', 'remaining', public.so_invoice_remaining(v_inv_id),
                            'estimate', v_est, 'ship', v_ship, 'short_ea_total', v_plan->'short_ea_total', 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_pos_complete(uuid, jsonb, uuid, boolean) is 'SO 창구 속 함수(§20 판정 5 · 이견 0-8) — POS Finish·counter 「나갔다」의 속: confirmed pos·counter 오더 → 칸 계획(so_pick_plan · 준 픽이 있으면 그것) → 미리 보기(총액 so_tax_preview ordered · 받은 금액 ①②③ 을 발행과 같은 순서로 읽기만 · estimate) → p_commit 이면 so_ship(confirmed→shipped) + so_invoice_issue(한 장 · fulfilled) · 반환 invoice_number · totals · received(deposit_applied · credit_applied · balance_forward) · amount_due · remaining · estimate · ship · short_ea_total · ⚠️ 막지 않는다(판정 5 · 남은 몫은 미수) · authenticated 직접 호출 불가';
revoke all on function public.so_pos_complete(uuid, jsonb, uuid, boolean) from public, anon, authenticated;

-- ═══ ⑦-e so_pos_finish — POS Finish(창구 · sales · 판정 5·6) ═══
create function public.so_pos_finish(p_so_id uuid, p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_ch    text;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 6 · 역할 문 없음
  v_staff := public.so_current_staff();
  select s.channel into v_ch from public.so s where s.id = p_so_id;
  if v_ch is null then raise exception 'Order not found — nothing was saved'; end if;
  if v_ch <> 'pos' then raise exception 'Order is a % order — pos Finish is for pos orders (counter: so_counter_ship · warehouse: so_finalize) — nothing was saved', v_ch; end if;
  return public.so_pos_complete(p_so_id, null, v_staff, p_commit);
end;
$$;
comment on function public.so_pos_finish(uuid, boolean) is '⭐ POS Finish(§20 판정 5·6 · 6-f) — definer · 첫 줄 ims_require_write(sales) · pos 오더 confirmed 만 · 칸은 자동(so_pick_plan · 손님 앞에서 칸을 고르게 하지 않는다 판정 4) · p_commit false = 누르기 전에 받은 금액·미수(estimate · 아무것도 안 씀) · true = 출고 + 발행 한 트랜잭션(so_pos_complete) · 막지 않는다 — 남은 몫은 그 인보이스의 미수';
revoke all on function public.so_pos_finish(uuid, boolean) from public, anon;
grant execute on function public.so_pos_finish(uuid, boolean) to authenticated;

-- ═══ ⑦-f so_counter_ship — counter 「나갔다」(창구 · sales + manager · 판정 4·12) ═══
create function public.so_counter_ship(p_so_id uuid, p_picks jsonb default null, p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_ch    text;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — counter 는 manager 이상(6-b · 판정 12)
  v_staff := public.so_current_staff();
  select s.channel into v_ch from public.so s where s.id = p_so_id;
  if v_ch is null then raise exception 'Order not found — nothing was saved'; end if;
  if v_ch <> 'counter' then raise exception 'Order is a % order — counter shipping is for counter orders (pos: so_pos_finish · warehouse: so_finalize) — nothing was saved', v_ch; end if;
  return public.so_pos_complete(p_so_id, p_picks, v_staff, p_commit);
end;
$$;
comment on function public.so_counter_ship(uuid, jsonb, boolean) is '⭐ counter 「나갔다」(§20 판정 4·12 · 6-b) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · counter 오더 confirmed 만 · p_picks null = 칸 계획 그대로 · 주면 그 칸·수량(so_ship 이 검사 · 목표 아래는 거부) · shipped_by = 누른 사람 · p_commit false = 미리 보기 · true = 출고 + 발행(so_pos_complete)';
revoke all on function public.so_counter_ship(uuid, jsonb, boolean) from public, anon;
grant execute on function public.so_counter_ship(uuid, jsonb, boolean) to authenticated;

-- ═══ ⑧ so_hold · so_divide 재발행 — 마지막 정의 20260924022449:21~52 · 248~311 · 길 가드 한 줄씩(훑기 ③ · 검증 6 실물: so_hold 가 pos 오더의 할당을 풀어 Finish 를 막고 · so_divide 가 pos 오더를 갈라 형제를 만들었다 — 둘 다 6-f 「pos 는 나뉘지 않는다 · 잠시 두기는 hold 가 아니다(판정 16)」 위반) ═══
create or replace function public.so_hold(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_n int := 0;  r record;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel <> 'warehouse' then raise exception 'Order % is a % order — hold is for warehouse orders (a pos/counter order is reopened with so_pos_reopen) — nothing was saved', v_so.so_number, v_so.channel; end if;   -- ④a2 훑기 ③(검증 6 실물: hold 가 통과해 Finish 를 막았다)
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — only a confirmed order still in IMS can be put on hold — nothing was saved', v_so.so_number, v_so.status;
  end if;
  for r in
    select x.id as line_id, x.qty_ordered, res.id as reserve_id
    from public.so_line x join public.so_reserve res on res.so_line_id = x.id and res.released_at is null and res.kind = 'allocated'
    where x.so_id = p_so_id order by x.line_no
  loop
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || r.line_id::text));
    update public.so_reserve set released_at = now(), released_by = v_staff, updated_by = v_staff where id = r.reserve_id;     -- 풀고 →
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (r.line_id, r.qty_ordered, 'hold', v_staff);   -- 새로 걸기(5-f)
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then
    raise exception 'Order % has no allocated lines to hold (already on hold, or a backorder/preorder order) — nothing was saved', v_so.so_number;
  end if;
  update public.so set updated_by = v_staff where id = p_so_id;
  return jsonb_build_object('so_number', v_so.so_number, 'status', v_so.status, 'lines_held', v_n);
end;
$$;
create or replace function public.so_divide(p_so_id uuid, p_moves jsonb, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_new public.so%rowtype;  m record;  l public.so_line%rowtype;  res public.so_reserve%rowtype;
  v_plan jsonb := '[]'::jsonb;  v_moves jsonb := '[]'::jsonb;  v_whole int := 0;  v_lines int;  v_nl public.so_line%rowtype;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel <> 'warehouse' then raise exception 'Order % is a % order — a pos/counter order is never split (6-f) — remove the line or make a second order — nothing was saved', v_so.so_number, v_so.channel; end if;   -- ④a2 훑기 ③(검증 6 실물: so_divide 가 pos 오더를 갈라 형제를 만들었다)
  if v_so.status not in ('draft', 'confirmed') then
    raise exception 'Order % is % — only a draft or confirmed order still in IMS can be divided — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if p_moves is null or jsonb_typeof(p_moves) <> 'array' or jsonb_array_length(p_moves) = 0 then
    raise exception 'p_moves must be a non-empty array of {line_id, qty} — nothing was saved';
  end if;
  select count(*) into v_lines from public.so_line where so_id = p_so_id;

  for m in
    select (e->>'line_id')::uuid as line_id, nullif(e->>'qty', '')::numeric as qty from jsonb_array_elements(p_moves) e
  loop
    select * into l from public.so_line where id = m.line_id and so_id = p_so_id;
    if not found then raise exception 'Line % is not on order % — nothing was saved', m.line_id, v_so.so_number; end if;
    if m.qty is null or m.qty <= 0 then raise exception 'Quantity for line % must be positive — nothing was saved', l.line_no; end if;
    if m.qty > l.qty_ordered then raise exception 'Line % has only % — cannot split off % — nothing was saved', l.line_no, l.qty_ordered, m.qty; end if;
    if v_moves @> jsonb_build_array(jsonb_build_object('line_id', l.id)) then raise exception 'Line % is listed twice — nothing was saved', l.line_no; end if;
    select * into res from public.so_reserve where so_line_id = l.id and released_at is null;
    v_moves := v_moves || jsonb_build_object('line_id', l.id, 'qty', m.qty);
    if m.qty = l.qty_ordered then v_whole := v_whole + 1; end if;
    v_plan := v_plan || jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'qty_moved', m.qty, 'whole', m.qty = l.qty_ordered,
                                           'reserve_kind', res.kind, 'reserve_follows', case when res.id is null then 0 else m.qty end);
  end loop;
  if v_whole >= v_lines then
    raise exception 'Cannot split off every line of order % — leave at least one line (or one part of a line) — nothing was saved', v_so.so_number;
  end if;
  if not p_commit then
    return jsonb_build_object('so_number', v_so.so_number, 'committed', false, 'status', v_so.status, 'lines', v_plan);
  end if;

  perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(v_so.so_number, '[a-z]+$', '')));
  for m in select (e->>'line_id')::uuid as line_id from jsonb_array_elements(v_moves) e loop
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || m.line_id::text));
  end loop;
  v_new := public.so_split(p_so_id, 'manual', v_moves, v_so.status, v_staff);

  -- 일부만 간 줄의 예약 — 풀고(이력) 원래 줄·형제 줄에 같은 kind 로(줄째 간 줄은 예약 행이 줄과 함께 갔다)
  if v_so.status = 'confirmed' then
    for v_nl in select * from public.so_line where so_id = v_new.id and split_from_line_id is not null loop
      select * into res from public.so_reserve where so_line_id = v_nl.split_from_line_id and released_at is null;
      if found then
        update public.so_reserve set released_at = now(), released_by = v_staff, updated_by = v_staff where id = res.id;                       -- 풀고 →
        insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
        select x.id, x.qty_ordered, res.kind, res.allocated_by from public.so_line x where x.id = v_nl.split_from_line_id;                        -- 원래 줄 · 남은 수량
        insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (v_nl.id, v_nl.qty_ordered, res.kind, res.allocated_by);   -- 형제 줄 · 옮긴 수량
      end if;
    end loop;
  end if;
  return jsonb_build_object('so_number', v_so.so_number, 'committed', true, 'status', v_so.status, 'lines', v_plan,
                            'sibling', jsonb_build_object('so_id', v_new.id, 'so_number', v_new.so_number, 'status', v_new.status, 'split_reason', 'manual'));
end;
$$;

-- ═══ 검증(~/asung/prompts/so-pos-1b-verify.sql · 시험 적용 장치 -v mig) — 지시서 §7 POS·counter 전부 · short_ea 합 = sale_shortfall 합(고침 ①) · 미리 보기 = 발행 결과(0-8) · 0-5 표 · 비활성 칸 켜기 거부 · 권한 ═══
