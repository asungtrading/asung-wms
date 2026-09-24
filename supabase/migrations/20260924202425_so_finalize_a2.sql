-- SO 인보이스 ⓐ2 — 오피스 마무리 so_finalize(출고 + 발행 한 번에) · 「손님이 뺐다」 칸 · so_ship 재발행(목표 = 주문 − 뺀 것) · 다시 견적 · so_detail (2026-09-24 UTC · 토론토 2026-09-24 오후)
-- 지시서 ~/asung/prompts/so-invoice-1.md · 판정 회신 Caleb 2026-09-24(판정 1~10 · 이견 1~11 ✅ · ⬜1~⬜11 ✅) · ⓐ1(20260924200029) 위에 선다 · 정본 §17 은 차수 끝에
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
-- 판정: 1 오피스 마무리가 출고와 인보이스를 한 번에(WMS 가 아니다 · packed = 창고 일 끝) · 4 마무리 때 고칠 수 있는 것 = 운임·택배사·추적번호·메모 + 뺀 수량(늘리기·단가·할인은 못 고친다) ·
--       5 「손님이 뺐다」 — 백오더를 만들지 않는다(pick_short 와 다르다) · 뺀 수량·사유·사람·시각을 줄에 · 원장 무접촉 · 그 몫의 할당은 풀린다 · 인보이스에는 보낸 수량만 ·
--       6 뺀 줄은 새 수량으로 자동 다시 견적(할인만 · 시스템 줄만) · 7 우리 쪽 부족(pick_short)은 할인 그대로 · 8 마무리 = sales(오더 담당)부터 · 9 모든 줄을 뺀 오더는 거부하고 길을 안내한다
--
-- ① so_line 칸 다섯(qty_removed · removed_reason · removed_note · removed_at · removed_by) + CHECK 여섯 + 인덱스 + 주석
-- ② so_ship 재발행(마지막 정의 20260924141140:374~501 · 목표 = qty_ordered − qty_removed · 초과 픽·차이·반환 세 자리 · 그 밖 바이트 그대로)
-- ③ so_line_requote 재발행(마지막 정의 20260923232500:97~123 · 인자 p_set_qty · drop + create · false 면 견적만 · qty_ordered 는 그대로 — 판정 5 「주문 12 · 뺐다 12」)
-- ④ so_finalize — 창구(definer · sales) · 한 트랜잭션 · ① 검사 ② 운임·택배사·추적번호·메모 ③ 뺀 몫 + 다시 견적 ④ so_ship ⑤ 묶음(bill_to_customer_id · 설정이면 매장 · invoice_group) ⑥ so_invoice_issue ⑦ 반환 · p_commit false = 읽기만
-- ⑤ so_detail 재발행(마지막 정의 20260924175014:988~1049 · 인보이스 · 뺀 몫 · 나간 뒤에는 보낸 수량 기준) · ⑥ so_family_members · so_family_lines 재발행(20260924014219:387·422 · 남은 수량 = 주문 − 뺀 것 − 보낸 것)
-- 훑기(qty_ordered · so_line_total 을 셈에 쓰는 자리 · 마지막 정의 · 회신에 표): 뺀 몫은 마무리(packed → shipped 한 트랜잭션)에서만 생기므로 초안·확정 단계 함수(so_line_add · so_lines_paste · so_line_update · so_reprice · so_allocate_run ·
--   so_backorder_supersede(새 오더 확정 때 · qty_removed 0) · so_backorder_list(백오더 줄은 형제 · 0) · so_divide · so_hold · so_unconfirm(confirmed 만))는 뜻이 그대로 · 나간 뒤를 읽는 셋만 고친다: so_detail(합계) · so_family_members(open_qty) · so_family_lines(open_total)
--   so_split 은 목표 − 보낸 것만 옮기므로 그대로(원래 줄 = 뺀 것 + 보낸 것 ≥ qty_removed · CHECK 만족) · so_tax_preview 는 ⓐ1 의 basis 로 이미 가른다 · 가용(so_available_many)·장부(so_backorder_close)는 예약 수량을 읽는다(qty_ordered 아님)
-- 검증: ~/asung/prompts/so-invoice-1b-verify.sql

-- ═══ ① so_line — 「손님이 뺐다」(판정 5) ═══
alter table public.so_line
  add column if not exists qty_removed    numeric not null default 0,
  add column if not exists removed_reason text,
  add column if not exists removed_note   text,
  add column if not exists removed_at     timestamptz,
  add column if not exists removed_by     uuid references public.ims_staff (id) on delete no action;
alter table public.so_line
  add constraint so_line_qty_removed_ck     check (qty_removed >= 0 and qty_removed <= qty_ordered),
  add constraint so_line_removed_reason_ck  check (removed_reason is null or removed_reason in ('customer_removed', 'not_wanted', 'other')),
  add constraint so_line_removed_pair_ck    check ((qty_removed > 0) = (removed_reason is not null)),
  add constraint so_line_removed_at_ck      check ((removed_reason is null) = (removed_at is null)),
  add constraint so_line_removed_by_ck      check ((removed_at is null) = (removed_by is null)),
  add constraint so_line_removed_note_ck    check (removed_reason is distinct from 'other' or removed_note is not null);
create index if not exists so_line_removed_by_idx on public.so_line (removed_by);
comment on column public.so_line.qty_removed    is '⭐ 손님이 뺀 수량(판매 단위 · so-module §17 판정 5 · 마무리 so_finalize 에서만) — 백오더가 아니다(pick_short 와 다르다) · 원장 무접촉 · 수요 기록 「주문 12 · 뺐다 12」(qty_ordered 는 그대로) · 보낼 목표 = qty_ordered − qty_removed(so_ship) · 인보이스에는 보낸 수량만 · CHECK 0 ≤ qty_removed ≤ qty_ordered · 짝 CHECK removed_reason';
comment on column public.so_line.removed_reason is '뺀 사유 — customer_removed(손님이 빼 달라 했다) · not_wanted(더 원하지 않는다) · other(note 필수) · qty_removed > 0 과 짝 · removed_at·removed_by 와 짝';
comment on column public.so_line.removed_note   is '뺀 사유 메모 · other 면 필수(CHECK so_line_removed_note_ck)';
comment on column public.so_line.removed_at     is '뺀 시각 · removed_reason 과 짝';
comment on column public.so_line.removed_by     is '뺀 사람 → ims_staff(id) · removed_at 과 짝 · 인덱스 so_line_removed_by_idx';

-- ═══ ② so_ship 재발행 — 마지막 정의 20260924141140:374~501 · create → create or replace · 바뀐 줄 4(줄 select · 초과 픽 · 차이 · 반환) · 더한 줄 0 ═══
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
  '⭐⭐ 출고 엔진(7-c · 2-f · 판정 1 · 2026-09-24 ③a · ⓐ2 재발행) — 세 길이 부르는 한 곳(속 함수 · authenticated 없음 · so_finalize(ⓐ2) · ④⑤ 의 definer 창구가 so_current_staff 로 p_staff 를 준다). packed 만 · shipped 면 조용한 반환 already_shipped. [{line_id, bin, qty}] 판매 단위 · 칸 여럿 · bin 은 그 창고 ref_bin 에 있어야(빈값 허용 · 비활성 경고) · ⭐ 보낼 목표 = qty_ordered − qty_removed(§17 판정 5 · 손님이 뺀 몫은 백오더가 아니다) · 목표 초과 픽 거부 · 목표 아래 덜 나간 몫만 pick_short 형제(backorder 예약 · 할인 그대로 판정 7). 한 트랜잭션: CAS 플립 → 할당 닫기(shipped/released · 전부 뺀 줄은 released) → qty_shipped → 형제 → inv_post_sale(원장 행 + FIFO + 부족분 레이어 · 픽만)';
revoke all on function public.so_ship(uuid, jsonb, uuid, date) from public, anon, authenticated;

-- ═══ ③ so_line_requote 재발행 — 마지막 정의 20260923232500:97~123 · 인자 셋(p_set_qty default true) · 시그니처가 바뀌어 drop + create(호출자 so_line_add·so_lines_paste 는 두 인자 → 기본값) · 바뀐 줄 2 ═══
drop function public.so_line_requote(uuid, numeric);
create function public.so_line_requote(p_line_id uuid, p_qty numeric, p_set_qty boolean default true) returns public.so_line
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_line public.so_line%rowtype;
  v_so   public.so%rowtype;
  q      record;
begin
  select * into v_line from public.so_line where id = p_line_id;
  if not found then
    raise exception 'Order line not found — nothing was saved';
  end if;
  select * into v_so from public.so where id = v_line.so_id;
  select * into q from public.so_line_quote(v_so, v_line.product_id, p_qty);
  update public.so_line set
    qty_ordered     = case when p_set_qty then p_qty else qty_ordered end,   -- ⓐ2 이견 3: false 면 견적만(뺀 몫 · 판정 5 「주문 12 · 뺐다 12」는 qty_ordered 에 남는다)
    discount_pct    = q.discount_pct,
    unit_price      = case when list_price is null then null else list_price * (1 - q.discount_pct / 100) end,
    discount_source = q.discount_source,
    deal_line_id    = q.deal_line_id,
    updated_by      = public.so_current_staff()
  where id = p_line_id
  returning * into v_line;
  return v_line;
end;
$$;
comment on function public.so_line_requote(uuid, numeric, boolean) is 'SO 창구 속 함수(할인 규칙 ②-0b · ⓐ2 재발행) — 시스템 줄(price_override=false · discount_source <> manual)의 할인을 p_qty 로 so_line_quote 로 다시 매긴다 · list_price 는 그 줄 것 그대로(할인만 다시 · 판정 3) · p_set_qty true(기본)면 qty_ordered 도 p_qty 로(합치기가 쓴다) · false 면 견적만(so_finalize 의 뺀 몫 · §17 판정 6 · qty_ordered 는 남는다) · 부르는 쪽이 「시스템 줄」임을 보장한다 · 권한·초안 확인은 부르는 창구가 했다';
revoke all on function public.so_line_requote(uuid, numeric, boolean) from public, anon, authenticated;

-- ═══ ④ so_finalize — 오피스 마무리(판정 1 · 창구 · definer · 첫 줄 ims_require_write(sales) · 판정 8 역할 문 없음) ═══
--   p_orders [{so_id, picks:[{line_id, bin, qty}], removed:[{line_id, qty, reason, note}]?, charges:[{charge_id?, name, amount, description?, account_id?}]?, carrier?, tracking_number?, shipping_notes?, invoice_group?}]
--   ① 검사 전부(하나라도 막히면 전체 거부 · 오더 번호로 · 판정 9 「모든 줄을 뺐다」) ② 운임·택배사·추적번호·메모(판정 4 · so_charge_set 의 규칙 그대로 · 세금은 오더 규칙 §16 판정 9) ③ 뺀 몫 기록 + 시스템 줄 다시 견적(판정 5·6 · 할인만)
--   ④ so_ship(목표 = 주문 − 뺀 것 · 그 아래 차이만 pick_short · 판정 7) ⑤ 묶음 = (bill_to_customer_id, 청구처 설정이면 오더의 손님 · invoice_group 이 오면 그것 — 청구처 안에서만) ⑥ so_invoice_issue(발행일 = 오늘 · 세율 §16 판정 5) ⑦ 반환
--   p_commit false = 읽기만(검사 · 다시 견적 결과 이전→새 · 묶음 = 인보이스가 몇 장 · 번호 없음 · 칸(bin) 검사는 실행 때 so_ship 이)
create function public.so_finalize(p_orders jsonb, p_commit boolean default true, p_shipped_on date default null) returns jsonb
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
  '⭐⭐ 오피스 마무리(so-module §17 판정 1 · ⓐ2 · 2026-09-24) — definer · 첫 줄 ims_require_write(sales) · 역할 문 없음(판정 8 · R5 예외) · packed 오더 묶음을 한 트랜잭션에 출고 + 발행. p_orders [{so_id, picks, removed?, charges?, carrier?, tracking_number?, shipping_notes?, invoice_group?}] · ① 검사 전부(하나라도 막히면 전체 거부 · 판정 9 모든 줄을 뺀 오더 거부 + 길) ② 운임·택배사·추적번호·메모(판정 4) ③ 뺀 몫 so_line.qty_removed(판정 5 · 백오더 아님 · 할당은 so_ship 이 released) + 시스템 줄 다시 견적(판정 6 · 할인만) ④ so_ship(목표 = 주문 − 뺀 것 · 차이만 pick_short 판정 7) ⑤ 묶음(bill_to_customer_id · 청구처 invoice_split_by_store 면 매장 · invoice_group) ⑥ so_invoice_issue ⑦ 반환 orders[removed · repriced 이전→새 · charges · ship] · invoices[] · invoice_count · warnings. p_commit false = 읽기만(번호 없음 · 칸 검사는 실행 때)';
revoke all on function public.so_finalize(jsonb, boolean, date) from public, anon;
grant execute on function public.so_finalize(jsonb, boolean, date) to authenticated;

-- ═══ ⑤ so_detail 재발행 — 마지막 정의 20260924175014:988~1049 · 더한 줄: 선언 1 · 줄 열쇠 2 · 집계 2 · basis·인보이스 10 · 경고 1 · 반환 2 · 바뀐 줄 3 ═══
create or replace function public.so_detail(p_so_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  v_cust     text;
  v_lines    jsonb;
  v_charges  jsonb;
  v_lines_n  int;  v_no_price int;  v_free int;  v_charges_n int;  v_deal_ended int;
  v_lines_total numeric;  v_charges_total numeric;  v_od_amt numeric;
  v_warn     text[];
  v_tax      jsonb;  v_tw text[];                              -- 세금 ② — so_tax_preview
  v_basis    text;  v_inv jsonb;  v_inv_hist jsonb;  v_removed int;  v_qty_removed numeric;   -- ⓐ2 — 보낸 수량 기준 · 인보이스 · 뺀 몫
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('total', public.so_line_total(l), 'no_price', l.unit_price is null, 'free', l.free_reason is not null, 'shipped_total', round(l.qty_shipped * l.unit_price, 2), 'removed', l.qty_removed > 0,
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)) order by l.line_no), '[]'::jsonb),
         count(*), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), coalesce(sum(public.so_line_total(l)), 0),
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)),
         count(*) filter (where l.qty_removed > 0), coalesce(sum(l.qty_removed), 0)
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended, v_removed, v_qty_removed
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

  -- 오더 전체 할인(D6) — 제품 줄 합계에 한 번 · round 2(SO-10842 실물) · 운임은 기준에 없다
  v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;

  -- 세금(세금 ② · 판정 8) — 오더에 고른 규칙(manual|ship_to)으로 줄마다 · 규칙 없으면 tax null + 경고 tax_rule_missing
  v_basis := case when v_so.status in ('shipped', 'invoiced', 'fulfilled') then 'shipped' else 'ordered' end;   -- ⓐ2: 나간 뒤에는 보낸 수량이 금액(뺀 몫·pick_short 제외 · 인보이스가 정본 8-c)
  v_tax := public.so_tax_preview(p_so_id, null, null, v_basis);
  if v_basis = 'shipped' then
    v_lines_total := (v_tax->'totals'->>'lines_amount')::numeric;
    v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;
  end if;
  select jsonb_build_object('invoice_id', i.id, 'invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'due_on', i.due_on, 'total', i.total, 'amount_due', i.amount_due) into v_inv
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id and o.cancelled_at is null;
  select coalesce(jsonb_agg(jsonb_build_object('invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'cancelled_at', i.cancelled_at) order by i.invoice_number), '[]'::jsonb) into v_inv_hist
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id;

  v_warn := public.so_tier_warnings(v_so);
  if v_so.tax_rule_id is null then v_warn := array_append(v_warn, 'tax_rule_missing'); end if;
  if v_removed > 0 then v_warn := array_append(v_warn, 'lines_removed'); end if;
  select array_agg(t.v) into v_tw from jsonb_array_elements_text(coalesce(v_tax->'warnings', '[]'::jsonb)) as t(v);
  v_warn := v_warn || coalesce(v_tw, '{}');
  if v_lines_n = 0    then v_warn := array_append(v_warn, 'no_lines'); end if;
  if v_no_price > 0   then v_warn := array_append(v_warn, 'lines_without_price'); end if;
  if v_deal_ended > 0 then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'totals', jsonb_build_object('basis', v_basis, 'lines', v_lines_n, 'lines_removed', v_removed, 'qty_removed', v_qty_removed, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt,
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'order_total', v_lines_total - v_od_amt + v_charges_total,
                                 'tax_rule', v_so.tax_rule, 'tax_rule_source', v_tax->>'source', 'tax', v_tax->'totals'->'tax',
                                 'order_total_with_tax', case when v_tax->'totals'->>'tax' is null then null else v_lines_total - v_od_amt + v_charges_total + (v_tax->'totals'->>'tax')::numeric end),
    'tax', v_tax,
    'invoice', v_inv,
    'invoice_history', v_inv_hist,
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_detail(uuid) is
  '⭐ SO 오더 읽기 한 창구(①b · 할인 규칙 ②-0b · 세금 ② · ⓐ2 재발행) — invoker · stable(RLS select 그대로 · 로그인만). so · customer_name · lines(+ total(주문 수량) · shipped_total(보낸 수량) · removed · no_price · free · deal_ended) · charges · totals(⭐ basis ordered|shipped — shipped·invoiced·fulfilled 는 보낸 수량 기준(뺀 몫·pick_short 제외 · 인보이스가 정본 8-c) · lines_removed · qty_removed · lines_total · order_discount_amount · charges_total · order_total · tax_rule · tax_rule_source · tax · order_total_with_tax) · tax = so_tax_preview(basis) · ⭐ invoice(살아 있는 인보이스 번호·상태·기한·합계) · invoice_history(취소된 것 포함) · warnings = so_tier_warnings + tax_rule_missing · lines_removed · tax 경고 + no_lines · lines_without_price · deal_ended_before_line_added · reprice_suggested. 화면 셋이 다시 짜지 않는다';

-- ═══ ⑥ so_family_members · so_family_lines 재발행 — 마지막 정의 20260924014219:387~416 · 422~450 · 남은 수량 = 주문 − 뺀 것 − 보낸 것(반환 모양 그대로 · fragments 에 qty_removed 열쇠) ═══
create or replace function public.so_family_members(p_so_id uuid)
returns table (so_id uuid, so_number text, status text, closed_reason text, merged_into_id uuid, split_reason text, split_from_id uuid, depth int, is_self boolean, open_qty numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with recursive up as (
  select s.id, s.split_from_id, 1 as depth, array[s.id] as path
  from public.so s where s.id = p_so_id
  union all
  select q.id, q.split_from_id, up.depth + 1, up.path || q.id
  from up join public.so q on q.id = up.split_from_id
  where up.depth < 50 and not (q.id = any(up.path))
),
root as (
  select u.id from up u order by u.depth desc limit 1
),
down as (
  select s.id, s.split_from_id, 0 as depth, array[s.id] as path
  from public.so s where s.id = (select id from root)
  union all
  select c.id, c.split_from_id, down.depth + 1, down.path || c.id
  from down join public.so c on c.split_from_id = down.id
  where down.depth < 50 and not (c.id = any(down.path))
)
select s.id, s.so_number, s.status, s.closed_reason, s.merged_into_id, s.split_reason, s.split_from_id, d.depth, (s.id = p_so_id),
       case when s.status = 'cancelled' then 0
            else coalesce((select sum(l.qty_ordered - l.qty_removed - l.qty_shipped) from public.so_line l where l.so_id = s.id), 0) end   -- ⓐ2: 손님이 뺀 몫은 남은 수량이 아니다(판정 5)
from down d join public.so s on s.id = d.id
order by s.so_number;
$$;
create or replace function public.so_family_lines(p_so_id uuid)
returns table (product_id uuid, sku text, product_name text, ordered_total numeric, shipped_total numeric, open_total numeric, members int, fragments jsonb)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with fm as (
  select * from public.so_family_members(p_so_id)
),
frag as (
  select l.product_id, fm.so_id, fm.so_number, fm.status as so_status, fm.split_reason, l.id as so_line_id, l.line_no, l.qty_ordered, l.qty_removed, l.qty_shipped, l.split_from_line_id,
         r.kind as reserve_kind, r.qty_allocated as reserve_qty
  from fm
  join public.so_line l on l.so_id = fm.so_id
  left join public.so_reserve r on r.so_line_id = l.id and r.released_at is null
)
select f.product_id, pr.sku, pr.name,
       coalesce(sum(f.qty_ordered) filter (where f.so_status <> 'cancelled'), 0),
       coalesce(sum(f.qty_shipped) filter (where f.so_status <> 'cancelled'), 0),
       coalesce(sum(f.qty_ordered - f.qty_removed - f.qty_shipped) filter (where f.so_status <> 'cancelled'), 0),   -- ⓐ2: open = 주문 − 뺀 것 − 보낸 것
       (count(distinct f.so_id) filter (where f.so_status <> 'cancelled'))::int,
       jsonb_agg(jsonb_build_object('so_id', f.so_id, 'so_number', f.so_number, 'so_status', f.so_status, 'split_reason', f.split_reason,
                                    'so_line_id', f.so_line_id, 'line_no', f.line_no, 'qty_ordered', f.qty_ordered, 'qty_removed', f.qty_removed, 'qty_shipped', f.qty_shipped,
                                    'split_from_line_id', f.split_from_line_id, 'reserve_kind', f.reserve_kind, 'reserve_qty', f.reserve_qty)
                 order by f.so_number, f.line_no)
from frag f
join public.product pr on pr.id = f.product_id
group by f.product_id, pr.sku, pr.name
order by pr.sku;
$$;

-- ═══ 검증(~/asung/prompts/so-invoice-1b-verify.sql · psql -v ON_ERROR_STOP=1 -f · 시퀀스 둘은 rollback 밖 setval) ═══
--   칸 다섯 · CHECK 여섯(하나씩 · constraint_name) · 함수(so_finalize 신설 · so_line_requote 3인자 하나 · 재발행 넷) · 세 오더 한 번(한 줄 3×10.05 = 3.92 · 세 줄 10.05 = 3.93 · 100) · 두 청구처 두 장 · 청구처 설정 끔 한 장/켬 두 장 ·
--   운임·택배사·추적번호(운임 세금 = 오더 규칙) · 손님이 뺐다 12→0(백오더 없음 · 원장 없음 · 할당 released · 인보이스에 없음) · 12 중 2(12 이상 20% 딜 → 10 · 할인 원래대로 · 이전→새) · pick_short 10/12(할인 그대로 · 백오더 2) ·
--   막힌 오더 → 전체 거부 · 아무것도 안 쓰임 → 빼고 다시 · 전부 뺀 오더 거부 · 미리 보기는 아무것도 안 씀 · worker(권한 없음) 거부 · worker+sales 마무리 · so_detail(basis shipped · invoice · removed) · family open 수량 · 흔적 0
