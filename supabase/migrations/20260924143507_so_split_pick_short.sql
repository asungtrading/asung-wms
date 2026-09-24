-- SO 쓰기 ③a′ — so_split 재발행: split_reason 어휘에 pick_short (2026-09-24 UTC · 토론토 2026-09-24 오전)
-- 결함(Caleb 실측 · ③a 검증 v2 5) C): so_ship → so_split(…, 'pick_short') 가 「split_reason pick_short is not one of stock_short, warehouse, preorder, manual」로 거부됐다.
--   ③a(20260924141140)는 CHECK so_split_reason_ck 만 다섯으로 넓혔고, so_split 본문(20260924014219:166)에 어휘 목록이 따로 있었다 — 회신 이견 12 「so_split 을 그대로 쓸 수 있다」가 틀렸다.
-- 판정(Caleb): 적용된 ③a 는 고치지 않는다 · 새 파일에서 마지막 정의(20260924014219:148~237)를 바이트 그대로 뽑아 목록만 바꿔 재발행 · 원본과 diff(바뀐 줄만 · 빠진 줄 0 · 회신)
-- 같은 모양 훑기(회신에 file:line): ③a 가 넓힌 다섯 목록(split_reason · cost_source · origin_type · released_reason · 문지기 짝) 중 함수 본문에 따로 적힌 것은 이 so_split 한 곳뿐이었다.
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 검증 ~/asung/prompts/so-write-3a-verify.sql v2 를 처음부터 다시(바꿀 것 없음)
-- ⚠️ 시그니처 그대로(create or replace · grant·revoke 유지 · revoke 는 원본 줄 그대로 다시 적는다) · 본문의 다른 줄은 무접촉

create or replace function public.so_split(p_so_id uuid, p_reason text, p_moves jsonb, p_target_status text, p_staff uuid) returns public.so
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so     public.so%rowtype;
  v_new    public.so%rowtype;
  v_base   text;
  v_max    text;
  v_num    text;
  v_id     uuid := gen_random_uuid();
  m        record;
  l        public.so_line%rowtype;
  v_next   int := 0;
  v_n      int;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if p_reason not in ('stock_short','warehouse','preorder','manual','pick_short') then                       -- ③a′ 2026-09-24: pick_short(출하 차이 · so_ship) — CHECK so_split_reason_ck 와 같은 다섯
    raise exception 'split_reason % is not one of stock_short, warehouse, preorder, manual, pick_short — nothing was saved', p_reason;
  end if;
  if p_target_status not in ('draft','confirmed') then
    raise exception 'A split order can only be born draft or confirmed — nothing was saved';
  end if;
  if coalesce(jsonb_array_length(p_moves), 0) = 0 then
    raise exception 'Nothing to split off — nothing was saved';
  end if;

  -- 번호 — base(접미어를 뗀 것)로 잠그고 그 base 의 접미어 최댓값 다음 글자 하나(5-d · PO 20260924001820:278~370 과 같은 자리 · cancelled·merged 도 센다 — 글자는 다시 쓰지 않는다)
  v_base := regexp_replace(v_so.so_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('so:' || v_base));
  select max(substring(s.so_number from length(v_base) + 1)) into v_max
  from public.so s where s.so_number ~ ('^' || v_base || '[a-z]$');
  if v_max is null then
    v_num := v_base || 'a';
  elsif v_max >= 'x' then
    raise exception 'Order % has been split too many times (last suffix %) — split it by hand — nothing was saved', v_so.so_number, v_max;
  else
    v_num := v_base || chr(ascii(v_max) + 1);
  end if;

  -- 머리 통째 복사(칸이 늘어도 따라온다) — draft 로 태어난다(문지기 · 이견 4) · 닫힘·창고·출하·되돌리기 흔적은 비운다 · 확정 흔적은 target 이 confirmed 일 때 아래 update 에서 물려받는다
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_so) || jsonb_build_object(
      'id', v_id, 'so_number', v_num, 'status', 'draft',
      'split_from_id', v_so.id, 'split_reason', p_reason,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null,
      'created_at', now(), 'created_by', p_staff, 'updated_at', now(), 'updated_by', p_staff));

  -- 줄 옮기기(모체 line_no 순 · 형제 line_no 1부터)
  for m in
    select (e->>'line_id')::uuid as line_id, (e->>'qty')::numeric as qty
    from jsonb_array_elements(p_moves) e
    join public.so_line x on x.id = (e->>'line_id')::uuid
    order by x.line_no
  loop
    select * into l from public.so_line where id = m.line_id and so_id = p_so_id;
    if not found then raise exception 'Line % is not on order % — nothing was saved', m.line_id, v_so.so_number; end if;
    if m.qty is null or m.qty <= 0 then raise exception 'Split quantity for line % must be positive — nothing was saved', l.line_no; end if;
    v_next := v_next + 1;
    if m.qty >= l.qty_ordered then
      update public.so_line set so_id = v_id, line_no = v_next, updated_by = p_staff where id = l.id;                       -- 통째 — 행이 간다(id 그대로)
    else
      update public.so_line set qty_ordered = qty_ordered - m.qty, updated_by = p_staff where id = l.id;                    -- 일부 — 원래 줄을 줄이고
      insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, qty_shipped,
                                  list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                  surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, split_from_line_id, updated_by)
      values (v_id, v_next, l.product_id, l.sku, l.product_name, l.unit, l.pack_factor, m.qty, 0,
              l.list_price, l.discount_pct, l.unit_price, l.price_override, l.discount_source, l.deal_line_id, l.free_reason,
              l.surcharge_pct, l.surcharge_amount, l.surcharge_label, l.tax_rule, l.comments, l.id, p_staff);                 -- 형제에 새 줄 · 계보
    end if;
  end loop;

  if p_target_status = 'confirmed' then
    update public.so set status = 'confirmed', confirmed_at = v_so.confirmed_at, confirmed_by = v_so.confirmed_by, updated_by = p_staff
    where id = v_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Split order % was not saved — nothing was saved', v_num; end if;
  end if;

  select * into v_new from public.so where id = v_id;
  return v_new;
end;
$$;
comment on function public.so_split(uuid, text, jsonb, text, uuid) is
  'SO 창구 속 함수(②a · 5-d 번호 규칙) — 모체에서 줄(전부 또는 일부)을 떼어 형제 문서를 만든다. 번호 = base 의 접미어 최댓값 다음 소문자 한 글자(a~x · y 이상 거부 · advisory lock so:base · cancelled·merged 도 센다) · 머리 통째 복사(운임 제외 · 오더 전체 할인 복사) · draft 로 태어나 target 이 confirmed 면 같은 트랜잭션에서 confirmed(확정 흔적은 모체 것 · 문지기 짝) · 통째 줄은 행이 가고(id 그대로) 일부 줄은 원래를 줄이고 새 줄(split_from_line_id) · 예약은 건드리지 않는다(부르는 쪽) · 권한·상태 확인은 부르는 창구가 했다';
revoke all on function public.so_split(uuid, text, jsonb, text, uuid) from public, anon, authenticated;
