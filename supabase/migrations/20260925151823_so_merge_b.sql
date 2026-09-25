-- SO 쓰기 ④b — 오더 병합(so-merge-1 · 2026-09-25 · Caleb 판정 1~8 · 이견 0-1~0-8 · ⬜1~⬜8 · [테스트 · Asung-IMS] 시험 적용 뒤 Caleb 적용)
-- 바탕: 정본 so-module.md 8-b(조건·번호·할당·두 방향 사슬) · 13-e 판정 2(합치기) · 14-a R5 · 15-a 판정 4·5·10·13·15 · 17-a 판정 6 · 18-c 0-7 · 지시서 §1 판정 1~8
-- ① so_backorder_close.end_kind 에 'merged'(0-4 · CHECK 넓힘 · 본문 값 목록 grep: CHECK 셋뿐 · so_backorder_list 는 필터 값을 그대로 비교)
-- ② so_line_merge_source — 합친 줄 ← 원본 줄 짝 표(⬜3 · line_id cascade(합친 초안에서 줄을 빼면 짝도 사라진다) · from_line_id no action · 원본 줄은 지워지지 않는다 · 전체 유니크 둘)
-- ③ so_merge_chain_reaches(from, target) — split_from_id(위로) ∪ merged_into_id(앞으로) 두 변을 함께 걷는다(0-2 · 깊이 60 · 경로 순환 방지)
-- ④ so_backorder_supersede 재발행(마지막 정의 20260924153856:25~83 · 바이트 그대로 + 더한 조건 한 줄) — 판정 1
-- ⑤ so_merge_requote_calc(머리 record · 줄 jsonb) · so_merge_requote_hint(so_id) — 판정 4 보완 ①(줄마다 자기 수량 · 같은 제품 둘 이상이면 합친 수량으로도 · 표시만 · 무상·override·값 없는 줄 제외)
-- ⑥ so_merge(p_so_ids, p_commit) — definer · 첫 줄 ims_require_write(sales) · 원본에 confirmed 가 있으면 so_require_role(manager)(판정 5)
--    막음: 둘 미만 · 같은 오더 두 번 · 못 찾음 · draft·confirmed 아님(merged·창고에 간 것은 문장으로) · channel ≠ warehouse · 다른 손님 · 다른 창고 · 다른 통화 · 비활성 손님
--    미리 보기(p_commit false · 아무것도 안 쓴다): head_from · head_diffs(칸별 원본 값) · order_date(= ims_today · 판정 3) · lines(계획 · 원본 줄들 · kept_apart · was_preorder) · requote(판정 4 보완 ①)
--                                            · payments_to_move · backorder_siblings(판정 1 로 빠질 형제) · superseded(원본이 이어받은 남의 줄 · reopenable) · charges(옮기지 않는다 · 판정 8) · warnings
--    실행: 머리 = 가장 오래된 원본(order_date → so_number · ⬜2) 통째 복사(so_split 식) → 줄(열쇠 (product · unit_price · list_price · discount_pct · free_reason · price_override · surcharge 셋) · 고침 ①: tax_rule 은 열쇠 밖 · 합친 오더 규칙)
--          → 원본 백오더 줄 장부 merged + 예약 closed → 원본이 이어받은 줄 다시 열기(confirmed 인 것만 · 아니면 경고 · ⬜4·0-7) → 원본 예약 released → 원본 닫기(cancelled · merged · merged_into_id · closed_at · closed_note 한 문장)
--          → 선결제 대상 옮기기(so_payment_order · on conflict do nothing · 조사 ③) → 반환
--    ⭐ 되돌리거나 바꾸는 머리 칸(⬜2 · 보고의 표와 같다): id · so_number(so_next_number) · status draft · order_date = ims_today · ref null · comments(원본 + 「Merged from …」) · split_from_id·split_reason null
--       · merged_into_id·closed_reason·closed_note·closed_at·cancelled_by null · confirmed_at/by · at_wms_at/by · shipped_at/by · invoiced_at · unconfirmed_at/by null · carrier·tracking_number null(마무리가 넣는다 · shipping_notes 는 남긴다)
--       · reprice_suggested_at = now()(주문일이 바뀌고 줄이 있으면 · §13 판정 3 그대로 — 줄은 그대로 + 표시 + 경고 reprice_suggested) · order_discount 셋(source deal 이면 합친 날로 so_order_discount 다시 · manual 은 그대로 · 판정 7)
--       · created_at/by · updated_at/by = now()/staff · 그 밖 전부 가장 오래된 원본 것(배송지 · 청구처 · 결제조건 · 티어 · 세금 규칙 셋 · 손님 할인 · required_by · shipping_notes · 계정 넷 · intake · location · currency)
-- 검증: ~/asung/prompts/so-merge-1-verify.sql(시험 적용 장치 -v mig) · 정본 §20 ④b · asung-so 4-j 는 말만
-- ⚠️ 쓰기 창구를 FROM 의 lateral 에서 부르지 않는다 · ims_touch·ims_can_write·set_updated_at·ims_require_write·ims_today 재정의 없음 · 적용된 파일 무접촉

-- ═══ ① so_backorder_close.end_kind 에 merged(0-4) ═══
alter table public.so_backorder_close drop constraint so_backorder_close_end_kind_ck;
alter table public.so_backorder_close add constraint so_backorder_close_end_kind_ck check (end_kind in ('superseded','expired','proceeded','cancelled','merged'));
comment on column public.so_backorder_close.end_kind is 'CHECK 다섯 superseded · expired · proceeded · cancelled · merged(④b 2026-09-25: 백오더 오더가 다른 오더로 합쳐졌다 · note 「Merged into SO-…」 · qty_taken·unwanted 0 · 수요는 합친 오더의 줄로 옮겨 갔다) — manual(사람이 손으로 닫기 5-g ②)은 그 창구가 설 때 더한다';

-- ═══ ② so_line_merge_source — 합친 줄 ← 원본 줄(⬜3) ═══
create table public.so_line_merge_source (
  id            uuid primary key default gen_random_uuid(),
  line_id       uuid not null references public.so_line (id) on delete cascade,      -- 합친 오더의 줄(초안에서 그 줄을 빼면 짝도 사라진다 · 원본은 merged_into_id 로 여전히 답한다)
  from_line_id  uuid not null references public.so_line (id) on delete no action,    -- 원본 줄(원본 오더는 닫힐 뿐 줄은 남는다)
  created_at    timestamptz not null default now(),
  created_by    uuid references public.ims_staff (id),
  constraint so_line_merge_source_uq       unique (line_id, from_line_id),
  constraint so_line_merge_source_from_uq  unique (from_line_id),                     -- 원본 줄 하나는 합친 줄 하나로만 간다
  constraint so_line_merge_source_self_ck  check (line_id <> from_line_id)
);
create index so_line_merge_source_line_idx on public.so_line_merge_source (line_id);
comment on table public.so_line_merge_source is '⭐ 오더 병합의 줄 계보(④b · 판정 4 보완 ② · ⬜3) — 합친 줄 하나 ← 원본 줄 여럿 · 원본 줄의 discount_source·deal_line_id 가 「왜 이 할인」의 흔적으로 남는다 · 쓰기는 so_merge 만(표 넷과 같은 규약 · select grant 만)';
alter table public.so_line_merge_source enable row level security;
create policy so_line_merge_source_select on public.so_line_merge_source for select to authenticated using (true);
grant select on public.so_line_merge_source to authenticated;
revoke insert, update, delete, truncate on public.so_line_merge_source from authenticated, anon, public;

-- ═══ ③ so_merge_chain_reaches — 후보 오더에서 split 조상(위) 과 merged_into(앞) 두 변을 걸어 target 에 닿는가(0-2) ═══
create function public.so_merge_chain_reaches(p_from uuid, p_target uuid) returns boolean
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with recursive w as (
    select s.id, s.split_from_id, s.merged_into_id, 0 as depth, array[s.id] as path
    from public.so s where s.id = p_from
    union all
    select n.id, n.split_from_id, n.merged_into_id, w.depth + 1, w.path || n.id
    from w join public.so n on n.id = w.split_from_id or n.id = w.merged_into_id
    where w.depth < 60 and not (n.id = any(w.path))
  )
  select exists (select 1 from w where w.depth > 0 and w.id = p_target);
$$;
comment on function public.so_merge_chain_reaches(uuid, uuid) is '④b 판정 1(0-2) — 백오더 형제 X-a(또는 손자 X-ab)에서 split_from_id 로 올라가며 만나는 오더마다 merged_into_id 를 따라(두 번 합쳐진 A → M1 → M2 도) target 에 닿으면 true · so_unconfirm 이 형제를 merged 로 닫은 사슬도 같은 변이다 · 깊이 60 · 순환 방지';
revoke all on function public.so_merge_chain_reaches(uuid, uuid) from public, anon;
grant execute on function public.so_merge_chain_reaches(uuid, uuid) to authenticated;

-- ═══ ④ so_backorder_supersede 재발행 — 마지막 정의 20260924153856:25~83 바이트 그대로 + 더한 조건 한 줄(판정 1) ═══
create or replace function public.so_backorder_supersede(p_so_id uuid, p_staff uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so    public.so%rowtype;
  v_base  text;
  k       record;
  t       record;
  v_rem   numeric;
  v_take  numeric;
  v_n     int := 0;
  v_out   jsonb := '[]'::jsonb;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' or v_so.confirmed_at is null then
    raise exception 'Order % is % — backorders are taken over at confirmation only — nothing was saved', v_so.so_number, v_so.status;
  end if;
  v_base := regexp_replace(v_so.so_number, '[a-z]+$', '');

  for k in
    select l.product_id, sum(l.qty_ordered) as qty,
           (array_agg(l.id order by (s.id <> p_so_id), s.so_number, l.line_no))[1] as line_id
    from public.so_line l join public.so s on s.id = l.so_id and l.free_reason is null     -- ③b′ 판정 13: 값을 매긴 줄만 센다(무상 줄은 우리가 준 것 · 수요가 아니다) · 무상 줄만 있는 제품은 이어받지 않는다 · 대표 줄도 유상 줄에서
    where s.id = p_so_id
       or (s.split_from_id = p_so_id and s.confirmed_at = v_so.confirmed_at and s.created_at = v_so.confirmed_at)
    group by l.product_id
  loop
    v_rem := k.qty;
    for t in
      select res.id as reserve_id, res.qty_allocated, l.id as line_id, l.line_no, l.sku, s.so_number, s.order_date, s.location_name
      from public.so_reserve res
      join public.so_line l on l.id = res.so_line_id
      join public.so s on s.id = l.so_id
      where res.kind = 'backorder' and res.released_at is null
        and l.free_reason is null                                    -- 판정 15: 무상 줄 백오더는 이어받기 대상이 아니다(우리가 줄 것 · 손님의 수요가 아니다)
        and s.status = 'confirmed'
        and s.customer_id = v_so.customer_id
        and l.product_id = k.product_id
        and regexp_replace(s.so_number, '[a-z]+$', '') <> v_base
        and not public.so_merge_chain_reaches(s.id, p_so_id)                         -- ④b 판정 1(so-merge-1 · 2026-09-25): 후보 오더의 split 조상 중 하나라도 merged_into_id 사슬로 이 오더(T)에 닿으면 제외 — 원본의 백오더 형제는 못 보낸 몫이지 준 수요가 아니다(0-2 · 조상 전부 · so_unconfirm 의 merged 도 같은 사슬)
      order by s.order_date, s.created_at, s.so_number, l.line_no
    loop
      perform pg_advisory_xact_lock(hashtext('so_reserve:' || t.line_id::text));
      v_take := least(t.qty_allocated, v_rem);
      perform public.so_backorder_record(t.line_id, 'superseded', t.qty_allocated, v_take, t.qty_allocated - v_take, p_so_id, k.line_id, p_staff, null);
      update public.so_reserve set released_at = now(), released_by = p_staff, released_reason = 'closed', updated_by = p_staff
      where id = t.reserve_id and released_at is null;
      v_rem := v_rem - v_take;
      v_n := v_n + 1;
      v_out := v_out || jsonb_build_object('so_number', t.so_number, 'line_no', t.line_no, 'sku', t.sku, 'order_date', t.order_date, 'location', t.location_name,
                                           'qty_open', t.qty_allocated, 'qty_taken', v_take, 'qty_unwanted', t.qty_allocated - v_take, 'taken_by_line_id', k.line_id);
    end loop;
  end loop;
  return jsonb_build_object('lines_closed', v_n, 'lines', v_out);
end;
$$;
comment on function public.so_backorder_supersede(uuid, uuid) is
  '⭐ 확정 때 이어받기(③b · 판정 3·4·5·8·9 · so_confirm 끝에서 commit 만) — 같은 손님·같은 제품의 열린 백오더 줄(가족 밖 · confirmed · 브랜치 무관 · 프리오더 제외)을 가장 오래된 줄부터 새 수량으로 채우고(qty_taken) 나머지는 더 원하지 않음(qty_unwanted) · ⭐ 새 수량은 값을 매긴 줄만(free_reason null · 판정 13 · 무상 줄만 있는 제품은 이어받지 않는다) · 대상 줄도 유상 백오더만(판정 15 · 무상 줄 백오더는 proceed·cancel 로만 끝난다) · 예약 closed · 장부 superseded(taken_by = 확정한 오더 · 그 제품의 첫 줄) · 오더는 닫지 않는다(판정 11 · 만료가 닫는다)';

-- ═══ ⑤ 판정 4 보완 ① — 다시 견적하면 더 유리한 줄(표시만) ═══
-- 속: 머리 record(합친 오더 · 미리 보기에서는 가장 오래된 원본에 order_date = ims_today 를 얹은 가상 머리) + 줄 jsonb → 줄마다 자기 수량 견적 · 같은 제품 둘 이상이면 합친 수량 견적(고침 ②)
create function public.so_merge_requote_calc(p_head public.so, p_lines jsonb) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_lines jsonb := '[]'::jsonb;
  v_comb  jsonb := '[]'::jsonb;
  r record;
  q record;
begin
  for r in
    select (e->>'line_no')::int as line_no, (e->>'product_id')::uuid as product_id, e->>'sku' as sku, (e->>'qty')::numeric as qty,
           (e->>'unit_price')::numeric as unit_price, (e->>'discount_pct')::numeric as discount_pct, e->>'discount_source' as discount_source
    from jsonb_array_elements(p_lines) e
    where e->>'free_reason' is null and not coalesce((e->>'price_override')::boolean, false) and e->>'unit_price' is not null
    order by 1
  loop
    select * into q from public.so_line_quote(p_head, r.product_id, r.qty);
    if q.unit_price is not null and q.unit_price < r.unit_price then
      v_lines := v_lines || jsonb_build_object('line_no', r.line_no, 'sku', r.sku, 'qty', r.qty, 'unit_price', r.unit_price, 'discount_pct', r.discount_pct, 'discount_source', r.discount_source,
                                               'quote_unit_price', q.unit_price, 'quote_discount_pct', q.discount_pct, 'quote_source', q.discount_source, 'quote_deal_line_id', q.deal_line_id);
    end if;
  end loop;
  for r in
    select (e->>'product_id')::uuid as product_id, min(e->>'sku') as sku, sum((e->>'qty')::numeric) as qty, count(*) as n,
           min((e->>'unit_price')::numeric) as min_unit_price, max((e->>'unit_price')::numeric) as max_unit_price,
           jsonb_agg(jsonb_build_object('line_no', (e->>'line_no')::int, 'qty', (e->>'qty')::numeric, 'unit_price', (e->>'unit_price')::numeric) order by (e->>'line_no')::int) as lines
    from jsonb_array_elements(p_lines) e
    where e->>'free_reason' is null and not coalesce((e->>'price_override')::boolean, false) and e->>'unit_price' is not null
    group by 1 having count(*) >= 2
    order by 2
  loop
    select * into q from public.so_line_quote(p_head, r.product_id, r.qty);
    if q.unit_price is not null and q.unit_price < r.max_unit_price then          -- 한 줄로 모으면 적어도 한 줄보다 유리하다 · better_than_all = 전부보다 유리
      v_comb := v_comb || jsonb_build_object('sku', r.sku, 'product_id', r.product_id, 'lines', r.lines, 'qty_total', r.qty,
                                             'quote_unit_price', q.unit_price, 'quote_discount_pct', q.discount_pct, 'quote_source', q.discount_source, 'quote_deal_line_id', q.deal_line_id,
                                             'better_than_all', (q.unit_price < r.min_unit_price));
    end if;
  end loop;
  return jsonb_build_object('lines', v_lines, 'combined', v_comb);
end;
$$;
comment on function public.so_merge_requote_calc(public.so, jsonb) is '④b 판정 4 보완 ①(속 · 읽기) — 줄마다 so_line_quote(머리 · 제품 · 그 줄 수량)의 단가가 지금 단가보다 낮으면 lines 에 · 같은 제품 줄이 둘 이상이면 합친 수량으로 견적해 combined 에(고침 ② · 「한 줄로 모으면 이 가격」 · better_than_all) · 무상·override·값 없는 줄 제외 · 표시만 — 자동으로 바꾸지 않는다';
revoke all on function public.so_merge_requote_calc(public.so, jsonb) from public, anon;
grant execute on function public.so_merge_requote_calc(public.so, jsonb) to authenticated;

create function public.so_merge_requote_hint(p_so_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so    public.so%rowtype;
  v_lines jsonb;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found'; end if;
  if not exists (select 1 from public.so_line_merge_source m join public.so_line l on l.id = m.line_id where l.so_id = p_so_id) then
    return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'merged', false, 'order_date', v_so.order_date, 'lines', '[]'::jsonb, 'combined', '[]'::jsonb);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'qty', l.qty_ordered, 'unit_price', l.unit_price, 'discount_pct', l.discount_pct,
                                               'discount_source', l.discount_source, 'free_reason', l.free_reason, 'price_override', l.price_override) order by l.line_no), '[]'::jsonb)
    into v_lines from public.so_line l where l.so_id = p_so_id;
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'merged', true, 'status', v_so.status, 'order_date', v_so.order_date) || public.so_merge_requote_calc(v_so, v_lines);
end;
$$;
comment on function public.so_merge_requote_hint(uuid) is '⭐ 합친 초안의 「합친 날 기준으로 다시 견적하면 더 유리한 줄」(④b 판정 4 보완 ① · ⬜6) — 읽기(stable · invoker) · 짝 표(so_line_merge_source)가 있는 오더만(없으면 merged false · 빈 배열) · so_detail 은 재발행하지 않는다 — 화면이 이 함수를 따로 부른다 · lines(줄마다 자기 수량) · combined(같은 제품 둘 이상 → 합친 수량 · 고침 ②) · 표시만';
revoke all on function public.so_merge_requote_hint(uuid) from public, anon;
grant execute on function public.so_merge_requote_hint(uuid) to authenticated;

-- ═══ ⑥ so_merge — 오더 병합 창구 ═══
create function public.so_merge(p_so_ids uuid[], p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_head_fields constant text[] := array['ship_to_company','ship_to_contact','ship_to_phone','ship_to_line1','ship_to_line2','ship_to_city','ship_to_state_province','ship_to_postal_code','ship_to_country',
                                         'bill_to_customer_id','bill_to_name','bill_to_line1','bill_to_line2','bill_to_city','bill_to_state_province','bill_to_postal_code','bill_to_country',
                                         'payment_term_id','payment_term_name','price_tier','price_tier_id','tax_rule','tax_rule_id','tax_rule_manual','discount_pct',
                                         'order_discount_pct','order_discount_source','order_discount_deal_id','required_by','ref','comments','intake',
                                         'carrier','tracking_number','shipping_notes','ar_account_code','sale_account_code'];
  v_staff   uuid;
  v_ids     uuid[];
  v_n       int;
  v_today   date := public.ims_today();
  v_old     public.so%rowtype;                       -- 가장 오래된 원본 = 머리(⬜2)
  v_head    public.so%rowtype;                       -- 미리 보기용 가상 머리(order_date = 오늘)
  v_new     public.so%rowtype;
  v_cust    public.customer%rowtype;
  v_numbers text;
  v_any_confirmed boolean;
  v_diffs   jsonb; v_plan jsonb; v_calc_in jsonb; v_hint jsonb; v_pay jsonb; v_sib jsonb; v_sup jsonb; v_charges jsonb;
  v_warn    text[] := '{}';
  v_note    text;
  v_id      uuid;
  v_line_id uuid;
  v_cnt     int;
  v_bo      int := 0; v_reopened int := 0; v_released int := 0; v_moved int := 0; v_lines_n int := 0;
  r record;
  e jsonb;
  od record;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — sales 묶음
  v_staff := public.so_current_staff();

  -- ── 대상 검사 ──
  select array_agg(distinct x) into v_ids from unnest(p_so_ids) x where x is not null;
  if coalesce(array_length(p_so_ids, 1), 0) <> coalesce(array_length(v_ids, 1), 0) then raise exception 'The same order is listed twice — nothing was saved'; end if;
  if coalesce(array_length(v_ids, 1), 0) < 2 then raise exception 'A merge needs at least two orders — nothing was saved'; end if;
  perform 1 from public.so s where s.id = any(v_ids) order by s.id for update;
  get diagnostics v_n = row_count;
  if v_n <> array_length(v_ids, 1) then raise exception 'Order not found — nothing was saved'; end if;
  for r in select s.* from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number loop
    if r.status not in ('draft', 'confirmed') then
      raise exception 'Order % is % — only draft or confirmed orders still in IMS can be merged — nothing was saved', r.so_number,
        r.status || case when r.status = 'cancelled' and r.closed_reason = 'merged' then ' (already merged into ' || coalesce((select m.so_number from public.so m where m.id = r.merged_into_id), '?') || ')'
                         when r.status in ('at_wms', 'picking', 'packed') then ' (it is with the warehouse — merge is only possible before release)'
                         else '' end;
    end if;
    if r.channel <> 'warehouse' then raise exception 'Order % is a % order — only warehouse orders can be merged — nothing was saved', r.so_number, r.channel; end if;
  end loop;
  if (select count(distinct s.customer_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders belong to different customers — nothing was saved'; end if;
  if (select count(distinct coalesce(s.location_id::text, '(none)')) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are for different warehouses — change the warehouse first — nothing was saved'; end if;
  if (select count(distinct s.currency_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are in different currencies — nothing was saved'; end if;
  select c.* into v_cust from public.customer c where c.id = (select s.customer_id from public.so s where s.id = v_ids[1]);
  if not v_cust.is_active then raise exception 'Customer % is inactive — nothing was saved', v_cust.name; end if;
  v_any_confirmed := exists (select 1 from public.so s where s.id = any(v_ids) and s.status = 'confirmed');
  if v_any_confirmed then perform public.so_require_role('manager', 'saved'); end if;   -- 판정 5 · R5: 확정 오더의 재고를 푸는 순간 선을 넘는다

  select s.* into v_old from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number limit 1;
  select string_agg(s.so_number, ', ' order by s.order_date, s.so_number) into v_numbers from public.so s where s.id = any(v_ids);

  -- ── 머리 차이(판정 2·7 · 막지 않는다) ──
  select coalesce(jsonb_agg(jsonb_build_object('field', d.f, 'values', d.vals) order by d.f), '[]'::jsonb) into v_diffs
  from (select f, jsonb_agg(jsonb_build_object('so_number', s.so_number, 'value', to_jsonb(s)->f) order by s.order_date, s.so_number) as vals
        from public.so s cross join unnest(c_head_fields) f
        where s.id = any(v_ids)
        group by f having count(distinct coalesce(to_jsonb(s)->f, 'null'::jsonb)) > 1) d;

  -- ── 줄 계획(판정 4 · 고침 ①: 열쇠 = 제품 · 단가 · 정가 · 할인 % · 무상 사유 · override · 부가 셋 — tax_rule 은 열쇠 밖 · 전부 합친 오더 규칙) ──
  with src as (
    select l.*, s.so_number, dense_rank() over (order by s.order_date, s.so_number) as ord,
           exists (select 1 from public.so_reserve rs where rs.so_line_id = l.id and rs.released_at is null and rs.kind = 'preorder')  as was_preorder,
           exists (select 1 from public.so_reserve rs where rs.so_line_id = l.id and rs.released_at is null and rs.kind = 'backorder') as was_backorder,
           (l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, v_today)) as deal_ended
    from public.so_line l join public.so s on s.id = l.so_id
    where s.id = any(v_ids)
  ), grp as (
    select product_id, unit_price, list_price, discount_pct, free_reason, price_override, surcharge_pct, surcharge_amount, surcharge_label,
           min(ord * 100000 + line_no) as first_pos, sum(qty_ordered) as qty, count(*) as n,
           (array_agg(sku order by ord, line_no))[1] as sku, (array_agg(product_name order by ord, line_no))[1] as product_name,
           (array_agg(unit order by ord, line_no))[1] as unit, (array_agg(pack_factor order by ord, line_no))[1] as pack_factor,
           (array_agg(comments order by ord, line_no) filter (where comments is not null))[1] as comments,
           bool_or(was_preorder) as was_preorder, bool_or(was_backorder) as was_backorder, bool_or(deal_ended) as deal_ended,
           jsonb_agg(jsonb_build_object('so_number', so_number, 'line_no', line_no, 'line_id', id, 'qty', qty_ordered, 'discount_source', discount_source, 'deal_line_id', deal_line_id,
                                        'was_preorder', was_preorder, 'was_backorder', was_backorder) order by ord, line_no) as sources
    from src
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
  ), numbered as (
    select g.*, row_number() over (order by g.first_pos) as line_no,
           count(*) over (partition by g.product_id) as n_same_product,
           first_value(g.unit_price)     over (partition by g.product_id order by g.first_pos) as p_unit_price,
           first_value(g.list_price)     over (partition by g.product_id order by g.first_pos) as p_list_price,
           first_value(g.discount_pct)   over (partition by g.product_id order by g.first_pos) as p_discount_pct,
           first_value(g.free_reason)    over (partition by g.product_id order by g.first_pos) as p_free_reason,
           first_value(g.price_override) over (partition by g.product_id order by g.first_pos) as p_override,
           first_value(g.surcharge_label) over (partition by g.product_id order by g.first_pos) as p_surcharge_label
    from grp g
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'line_no', x.line_no, 'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'unit', x.unit, 'pack_factor', x.pack_factor,
           'qty', x.qty, 'list_price', x.list_price, 'discount_pct', x.discount_pct, 'unit_price', x.unit_price, 'price_override', x.price_override, 'free_reason', x.free_reason,
           'discount_source', case when x.price_override then null when x.discount_pct is not null then 'manual' else null end,
           'surcharge_pct', x.surcharge_pct, 'surcharge_amount', x.surcharge_amount, 'surcharge_label', x.surcharge_label, 'comments', x.comments,
           'source_lines', x.n, 'sources', x.sources, 'was_preorder', x.was_preorder, 'was_backorder', x.was_backorder, 'deal_ended', x.deal_ended,
           'kept_apart', (x.n_same_product > 1),
           'differs_in', case when x.n_same_product > 1 then
              (select coalesce(jsonb_agg(k), '[]'::jsonb) from unnest(array[
                 case when x.unit_price is distinct from x.p_unit_price then 'unit_price' end,
                 case when x.list_price is distinct from x.p_list_price then 'list_price' end,
                 case when x.discount_pct is distinct from x.p_discount_pct then 'discount_pct' end,
                 case when x.free_reason is distinct from x.p_free_reason then 'free_reason' end,
                 case when x.price_override is distinct from x.p_override then 'price_override' end,
                 case when x.surcharge_label is distinct from x.p_surcharge_label then 'surcharge' end]) k where k is not null)
              else '[]'::jsonb end) order by x.line_no), '[]'::jsonb)
    into v_plan
  from numbered x;
  v_lines_n := coalesce(jsonb_array_length(v_plan), 0);

  -- ── 판정 4 보완 ①: 가상 머리(가장 오래된 원본 + 오늘) 로 다시 견적 ──
  v_head := v_old;
  v_head.order_date := v_today;
  select coalesce(jsonb_agg(jsonb_build_object('line_no', p->'line_no', 'product_id', p->'product_id', 'sku', p->'sku', 'qty', p->'qty', 'unit_price', p->'unit_price', 'discount_pct', p->'discount_pct',
                                               'discount_source', p->'discount_source', 'free_reason', p->'free_reason', 'price_override', p->'price_override')), '[]'::jsonb)
    into v_calc_in from jsonb_array_elements(v_plan) p;
  v_hint := public.so_merge_requote_calc(v_head, v_calc_in);

  -- ── 선결제 대상(옮긴다 · 조사 ③ unique (payment_id, so_id)) ──
  select coalesce(jsonb_agg(jsonb_build_object('payment_id', x.id, 'amount', x.amount, 'method', x.method, 'paid_on', x.paid_on, 'targets', x.targets) order by x.paid_on, x.id), '[]'::jsonb) into v_pay
  from (select p.id, p.amount, p.method, p.paid_on, jsonb_agg(s.so_number order by s.so_number) as targets
        from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active' join public.so s on s.id = o.so_id
        where o.so_id = any(v_ids) group by p.id, p.amount, p.method, p.paid_on) x;

  -- ── 판정 1 로 이어받기에서 빠질 형제(원본의 split 자손 중 열린 백오더가 있는 confirmed 오더) ──
  with recursive d as (
    select s.id, 0 as depth, array[s.id] as path from public.so s where s.id = any(v_ids)
    union all
    select c.id, d.depth + 1, d.path || c.id from d join public.so c on c.split_from_id = d.id where d.depth < 50 and not (c.id = any(d.path))
  )
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'status', s.status, 'split_reason', s.split_reason,
           'open_backorder_lines', (select count(*) from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null)) order by s.so_number), '[]'::jsonb)
    into v_sib
  from d join public.so s on s.id = d.id
  where d.depth > 0 and not (s.id = any(v_ids)) and s.status = 'confirmed'
    and exists (select 1 from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null);

  -- ── 원본이 확정 때 이어받은 남의 백오더 줄(⬜4 · 0-7: confirmed 이고 열린 예약이 없는 줄만 다시 연다 · 나머지는 닫힌 채 + 경고) ──
  select coalesce(jsonb_agg(jsonb_build_object('close_id', c.id, 'so_number', s.so_number, 'line_no', l.line_no, 'sku', l.sku, 'qty_open', c.qty_open, 'qty_taken', c.qty_taken, 'qty_unwanted', c.qty_unwanted,
           'taken_by', t.so_number, 'target_status', s.status,
           'reopenable', (s.status = 'confirmed' and not exists (select 1 from public.so_reserve rs where rs.so_line_id = l.id and rs.released_at is null))) order by s.so_number, l.line_no), '[]'::jsonb)
    into v_sup
  from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.so s on s.id = l.so_id join public.so t on t.id = c.taken_by_so_id
  where c.taken_by_so_id = any(v_ids) and c.reopened_at is null and c.end_kind = 'superseded';

  -- ── 운임(판정 8: 옮기지 않는다 · 다시 계산한다) ──
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'line_no', c.line_no, 'name', c.name, 'amount', c.amount) order by s.so_number, c.line_no), '[]'::jsonb) into v_charges
  from public.so_charge c join public.so s on s.id = c.so_id where c.so_id = any(v_ids);

  -- ── 경고(막지 않는다) ──
  if jsonb_array_length(v_diffs) > 0 then v_warn := array_append(v_warn, 'head_differs'); end if;
  if jsonb_array_length(v_charges) > 0 then v_warn := array_append(v_warn, 'charges_not_merged'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'was_preorder')::boolean) then v_warn := array_append(v_warn, 'preorder_lines_need_reflag'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'deal_ended')::boolean) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if exists (select 1 from jsonb_array_elements(v_sup) x where not (x->>'reopenable')::boolean) then v_warn := array_append(v_warn, 'superseded_not_reopenable'); end if;
  if v_old.order_date <> v_today and v_lines_n > 0 then v_warn := array_append(v_warn, 'reprice_suggested'); end if;   -- §13 판정 3: 주문일이 바뀌면 줄은 그대로 + 표시 + 경고
  if jsonb_array_length(v_sib) > 0 then v_warn := array_append(v_warn, 'backorder_siblings_stay_open'); end if;      -- 판정 1 · 0-1 대가

  if not p_commit then
    return jsonb_build_object('committed', false, 'orders', to_jsonb(string_to_array(v_numbers, ', ')), 'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today,
                              'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'charges', v_charges,
                              'needs_manager', v_any_confirmed, 'warnings', to_jsonb(v_warn));
  end if;

  -- ── 실행 ① 새 오더(머리 통째 복사 · 위 주석의 칸 표) ──
  v_id := gen_random_uuid();
  v_note := 'Merged from ' || v_numbers;
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_old) || jsonb_build_object(
      'id', v_id, 'so_number', public.so_next_number(), 'status', 'draft', 'order_date', v_today, 'ref', null,
      'comments', case when v_old.comments is null then v_note else v_old.comments || E'\n' || v_note end,
      'split_from_id', null, 'split_reason', null,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null, 'carrier', null, 'tracking_number', null, 'reprice_suggested_at', null,
      'created_at', now(), 'created_by', v_staff, 'updated_at', now(), 'updated_by', v_staff));
  select * into v_new from public.so where id = v_id;
  if v_old.order_discount_source = 'deal' then                                       -- 판정 7: source deal 이면 합친 날로 §13 자동 재계산 · manual 은 그대로
    select * into od from public.so_order_discount(v_id);
    update public.so set order_discount_pct = od.pct, order_discount_deal_id = od.deal_id, order_discount_source = case when od.pct is null then null else 'deal' end, updated_by = v_staff where id = v_id;
  end if;

  -- ── 실행 ② 줄(계획 그대로 · tax_rule = 합친 오더 규칙 · 짝 표) ──
  for e in select p from jsonb_array_elements(v_plan) p order by (p->>'line_no')::int loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by)
    values (v_id, (e->>'line_no')::int, (e->>'product_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
            (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, (e->>'unit_price')::numeric, (e->>'price_override')::boolean, e->>'discount_source', null, e->>'free_reason',
            (e->>'surcharge_pct')::numeric, (e->>'surcharge_amount')::numeric, e->>'surcharge_label', v_new.tax_rule, e->>'comments', v_staff)
    returning id into v_line_id;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select v_line_id, (x->>'line_id')::uuid, v_staff from jsonb_array_elements(e->'sources') x;
  end loop;
  if v_old.order_date <> v_today and v_lines_n > 0 then
    update public.so set reprice_suggested_at = now(), updated_by = v_staff where id = v_id;
  end if;

  -- ── 실행 ③ 원본의 열린 백오더 줄 → 장부 merged + 예약 closed(0-4) ──
  for r in
    select res.id as reserve_id, res.so_line_id, res.qty_allocated
    from public.so_reserve res join public.so_line x on x.id = res.so_line_id
    where res.released_at is null and res.kind = 'backorder' and x.so_id = any(v_ids)
  loop
    perform public.so_backorder_record(r.so_line_id, 'merged', r.qty_allocated, 0, 0, null, null, v_staff, 'Merged into ' || v_new.so_number);
    update public.so_reserve set released_at = now(), released_by = v_staff, released_reason = 'closed', updated_by = v_staff where id = r.reserve_id;
    v_bo := v_bo + 1;
  end loop;

  -- ── 실행 ④ 원본이 이어받은 남의 줄 다시 열기(⬜4 · confirmed 이고 열린 예약 없는 줄만 · so_backorder_reopen 과 같은 모양) ──
  for r in select (x->>'close_id')::uuid as close_id, (x->>'reopenable')::boolean as ok from jsonb_array_elements(v_sup) x loop
    if r.ok then
      update public.so_backorder_close set reopened_at = now(), reopened_by = v_staff, updated_by = v_staff where id = r.close_id and reopened_at is null;
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
      select c.so_line_id, c.qty_open, 'backorder', null from public.so_backorder_close c where c.id = r.close_id;
      v_reopened := v_reopened + 1;
    end if;
  end loop;

  -- ── 실행 ⑤ 원본의 남은 열린 예약(allocated · preorder · hold) 풀기 → released(트리거가 reason 을 넣는다 · ⬜5) ──
  update public.so_reserve res set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x where x.id = res.so_line_id and res.released_at is null and x.so_id = any(v_ids);
  get diagnostics v_released = row_count;

  -- ── 실행 ⑥ 원본 닫기(한 문장 · so_merge_reason_ck 양방향 · so_closed_at_ck) ──
  update public.so set status = 'cancelled', closed_reason = 'merged', merged_into_id = v_id, closed_at = now(), closed_note = 'Merged into ' || v_new.so_number, cancelled_by = v_staff, updated_by = v_staff
  where id = any(v_ids) and status in ('draft', 'confirmed');
  get diagnostics v_cnt = row_count;
  if v_cnt <> array_length(v_ids, 1) then
    raise exception 'Not every order could be merged — one may have been changed by someone else just now — nothing was saved';
  end if;

  -- ── 실행 ⑦ 선결제 대상 옮기기(원본 행은 기록으로 · 합친 오더 행 하나) ──
  insert into public.so_payment_order (payment_id, so_id, created_by)
  select distinct o.payment_id, v_id, v_staff
  from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active'
  where o.so_id = any(v_ids)
  on conflict on constraint so_payment_order_uq do nothing;
  get diagnostics v_moved = row_count;

  return jsonb_build_object('committed', true, 'so_id', v_id, 'so_number', v_new.so_number, 'status', 'draft', 'orders', to_jsonb(string_to_array(v_numbers, ', ')),
                            'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today, 'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint,
                            'payments_moved', v_moved, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'superseded_reopened', v_reopened,
                            'backorder_lines_recorded', v_bo, 'reserves_released', v_released, 'charges', v_charges, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_merge(uuid[], boolean) is
  '⭐ 오더 병합(④b · 8-b · 판정 1~8 · 2026-09-25) — definer · 첫 줄 ims_require_write(sales) · 원본에 confirmed 가 있으면 so_require_role(manager) · 같은 손님·창고·통화 · draft·confirmed · channel warehouse 만 · 둘 이상. p_commit false = 미리 보기(안 쓴다). 실행: 가장 오래된 원본(order_date → so_number)의 머리 통째 복사 → 새 번호 · 초안 · order_date = ims_today(판정 3) · ref 비움 · comments + Merged from … · 줄은 열쇠(제품·단가·정가·할인%·무상·override·부가)가 같을 때만 모으고 전부 manual(판정 4 · deal_line_id null) · tax_rule = 합친 오더 규칙(고침 ①) · 원본 백오더 줄 장부 merged · 원본이 이어받은 줄 다시 열기(confirmed 만 · 아니면 경고) · 원본 예약 released · 원본 cancelled·merged·merged_into_id · 선결제 대상 옮김 · 운임은 안 옮긴다(판정 8 · charges_not_merged). 되돌리기 없음(판정 6). 합친 오더 확정은 원본의 백오더 형제를 이어받지 않는다(판정 1 · so_backorder_supersede + so_merge_chain_reaches)';
revoke all on function public.so_merge(uuid[], boolean) from public, anon;
grant execute on function public.so_merge(uuid[], boolean) to authenticated;
