-- SO 할인 규칙 ②-0b — 창구에 딜을 끼운다 · 할인 다시 매기기 창구 so_reprice (2026-09-23 · 파일 시각 UTC)
-- 지시서 ~/asung/prompts/so-deal-1.md · 판정 Caleb 2026-09-23(판정 2 합치기 · 판정 3 다시 매기기 · ⬜3 · ⬜4 · 회신 이견 2·3·4·5·7) · 정본 docs/design/so-module.md §13(말만)
-- 바탕: 20260923224900_so_deal.sql(②-0a · so_deal_best · so_order_discount · so.order_discount_* · so_line.discount_source·deal_line_id) ·
--       20260923191030_so_write_rpc.sql(①b 창구 열 개 — 여기서 여섯을 재발행: so_line_quote :67 · so_create :140 · so_header_update :221 · so_line_add :378 · so_lines_paste :502 · so_line_update :684 · so_detail :981) ·
--       20260923192101(so_charge_set 재발행 — 무접촉) · 20260923182231(so_price_for · so_copy_customer · so_line_total — 무접촉)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · ⚠️ 운영에서는 ②-0a 와 한 번에(②-0a 뒤 이 파일 전까지 ①b 줄 창구 셋이 so_line_discount_pair_ck 로 거부된다)
--
-- ⭐ 무엇을 하나
--    ⓪ ims_today() — 토론토 「오늘」 함수 하나(공용 · ims_) · so.order_date 기본값을 current_date → ims_today() 로
--    ① so.reprice_suggested_at 칸 — 바깥 조건(오더 날짜 · 티어 · 손님 기본 할인)이 바뀌었는데 줄은 그대로다(판정 3) · so_reprice 가 지운다
--    ② so_line_quote(p_so, p_product_id, p_qty) — drop 뒤 새 시그니처(이견 2) · 할인 = greatest(손님 기본, so_deal_best(…).pct) · 큰 쪽의 출처(같으면 customer) · 반환 여섯
--    ③ 속 함수 둘 — so_deal_line_ended(deal_line_id, on)(세일 끝난 뒤 넣은 줄 경고) · so_line_requote(line_id, qty)(시스템 줄의 할인 다시 매기기 — 합치기가 쓴다)
--    ④ so_line_add · so_lines_paste — 판정 2 합치기: 시스템 줄(price_override=false · discount_source <> manual)은 제품만으로 짝 → 합친 수량으로 다시 견적 ·
--       사람이 정한 줄(덮어쓴 단가 · 수동 할인)만 단가 비교(다르면 ask) · p_discount_pct → source manual · p_unit_price → price_override(discount_pct·source null)
--    ⑤ so_line_update — 베낀 식을 so_line_quote 호출로(이견 3) · qty 가 바뀌면 시스템 줄은 다시 견적 · 사람이 정한 줄은 그대로 · discount_pct 를 비우면 시스템으로 되돌린다
--    ⑥ so_create · so_header_update — 오더 전체 할인을 so_order_discount 로 찾아 굳힌다(source deal) · 열쇠 order_discount_pct(값 → manual · null → 다시 찾기 · 30번째) ·
--       order_date · price_tier · discount_pct 를 바꾸면(줄이 있으면) 줄은 그대로 + 경고 reprice_suggested + 표시 · 오더 전체 할인은 source deal 일 때만 다시 찾는다(손님·오더 날짜)
--    ⑦ so_reprice(so_id) — 새 창구(9-b so_<동작>) · 시스템 줄 전부 할인 다시 견적 · 사람이 정한 줄 그대로 · 오더 전체 할인도 source deal 이면 다시 · 반환 줄마다 이전 → 새
--    ⑧ so_detail — totals 에 order_discount_pct · order_discount_amount = round(제품 줄 합계 × pct/100, 2) · lines_after_discount · order_total = lines − discount + charges ·
--       경고 deal_ended_before_line_added(줄의 딜 date_to < 그 줄 created_at 의 토론토 날짜) · reprice_suggested
--
-- ⭐ 「할인 다시 매기기」의 뜻 — 할인만이다(Caleb 판정 3 「할인 다시 매기기」). 들어간 줄의 list_price 는 그대로(⬜5 「초안의 줄은 가격표가 바뀌어도 따라가지 않는다」 유지) ·
--    unit_price = 그 줄의 list_price × (1 − 새 할인/100) · 새로 넣는 줄만 so_line_quote 의 list_price 를 받는다 · 티어를 바꿔도 list 는 안 바뀐다(lines_keep_prices 그대로)
-- ⭐ 합치기 규칙(판정 2 · 5-e 「단가가 같으면 합친다」 뒤집음)
--    들어오는 줄이 시스템(할인·단가를 안 줌) → 같은 제품의 시스템 줄이 있으면 제품만으로 합친다(단가 안 본다) → 합친 수량으로 다시 견적(6 + 6 = 12 → 20%)
--    그 밖(들어오는 줄이 수동 · 또는 시스템 줄이 없고 사람이 정한 줄만 있다) → 단가 비교 · 같으면 합친다(합쳐진 줄이 시스템 줄이면 다시 견적 · 사람이 정한 줄이면 수량만) · 다르면 ask
--    같은 SKU 두 줄(p_force_new)은 줄마다 따로 판정(이견 8)
-- ⚠️ 창구마다 첫 줄 ims_require_write('sales') · definer · set search_path = public, pg_temp · 초안만(so_require_draft) · 거부 문장 끝 「— nothing was saved」
-- ⚠️ 다시 만들지 않은 것: so_price_for · so_line_total · so_copy_customer · so_tier_warnings · so_current_staff · so_require_draft · so_line_remove · so_charge_set(20260923192101) · so_charge_remove · so_delete · ims_touch · ims_require_write
-- ⚠️ 100% 딜 줄은 unit_price 0 을 만들어 so_line_free_pair_ck(무상 사유)에 걸린다 — 실물에 100% 딜은 없다(최대 50) · 정본 ⬜
-- ⭐ 회사의 「오늘」은 토론토 날짜다(Caleb 판정 2026-09-23) — DB 시각은 UTC 라 current_date 는 토론토 저녁 8시(EDT · 겨울 7시) 이후 이미 내일이다
--    ⇒ ims_today()(now() at time zone 'America/Toronto')::date 하나를 두고 · so.order_date 기본값 · 이 파일의 「오늘」 전부 · 줄 created_at 의 날짜도 토론토로 · 에드먼튼 오더도 토론토 날짜(창고마다 날짜를 두지 않는다 · 대가)
--    ⚠️ 이미 적용된 ②-0a so_deal_best 의 coalesce(p_on, current_date) 는 못 고친다 — 부르는 쪽이 늘 order_date 를 주므로 그 폴백은 닿지 않는다(정본 ⬜ · 다음 재발행 때)

-- ═══ ⓪ ims_today — 토론토 「오늘」(Caleb 판정 2026-09-23 · 공용 · 이름 충돌 0 · 기존엔 at time zone 'America/Toronto' 인라인 10곳뿐) ═══
create function public.ims_today() returns date
  language sql stable
  set search_path = public, pg_temp
as $$
  select (now() at time zone 'America/Toronto')::date;
$$;
comment on function public.ims_today() is
  '⭐ 회사의 「오늘」 = 토론토 날짜(America/Toronto · EDT/EST 자동) — DB 시각은 UTC 라 current_date 는 토론토 저녁 8시(겨울 7시) 이후 내일이다(Caleb 2026-09-23). so.order_date 기본값 · 딜 기간 판정의 재료(D7 · order_date) · 백오더 만료(5-g) · 「세일 끝난 뒤 넣은 줄」 경고가 쓴다. 에드먼튼 오더도 토론토 날짜(창고마다 날짜를 두지 않는다). ⚠️ 시간을 바꿔 시험할 수 없다 — 날짜 경계는 식을 읽어 확인한다';
revoke all on function public.ims_today() from public, anon;
grant execute on function public.ims_today() to authenticated;

alter table public.so alter column order_date set default public.ims_today();
comment on column public.so.order_date is
  '오더 날짜 · NOT NULL · 기본값 ims_today()(토론토 오늘 · 2026-09-23 current_date 에서 바꿈 — 저녁에 만든 오더가 내일 날짜로 찍히던 자리) · ⭐ 딜 기간 판정의 기준(D7 · Caleb 「오더 날짜로 해야지」) · 백오더 만료(5-g)도 여기서 센다 · so_header_update 열쇠 order_date 로 바꿀 수 있다(줄이 있으면 reprice_suggested)';

-- ═══ ① so.reprice_suggested_at (판정 3) ═══
alter table public.so add column if not exists reprice_suggested_at timestamptz;
comment on column public.so.reprice_suggested_at is
  '⭐ 바깥 조건이 바뀌어 줄의 할인이 낡았을 수 있다는 표시(판정 3) — so_header_update 가 order_date · price_tier · discount_pct 를 바꿀 때 줄이 있으면 now() · so_detail 경고 reprice_suggested · so_reprice 가 null 로 지운다 · 줄 자체의 변화(넣기·합치기·수량)는 자동으로 다시 매기므로 여기 안 찍힌다';

-- ═══ ② so_line_quote — 새 시그니처(이견 2 · drop 뒤 create · grant 다시) ═══
--   (list_price, discount_pct, unit_price, price_source, discount_source, deal_line_id)
--   할인 = greatest(손님 기본 so.discount_pct, so_deal_best(product, customer, qty, order_date).pct) · 더하지 않는다(12-b 판정 4 · D5) · 딜이 더 클 때만 deal(같으면 customer)
--   unit_price = list × (1 − d/100) 자르지 않는다(판정 3 반올림) · list 없으면 unit 도 null(가격 없음) · 마지막 정의 20260923191030:67 — 인자 하나 · 반환 둘 더함 · 식은 greatest 의 0 자리에 딜
drop function public.so_line_quote(public.so, uuid);
create function public.so_line_quote(p_so public.so, p_product_id uuid, p_qty numeric)
  returns table (list_price numeric, discount_pct numeric, unit_price numeric, price_source text, discount_source text, deal_line_id uuid)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select f.list_price,
         x.d,
         case when f.list_price is null then null else f.list_price * (1 - x.d / 100) end,
         f.price_source,
         x.src,
         case when x.src = 'deal' then b.line_id end
  from public.so_price_for(p_product_id, p_so.price_tier_id) f,
       public.so_deal_best(p_product_id, p_so.customer_id, p_qty, p_so.order_date) b,
       lateral (select greatest(coalesce(p_so.discount_pct, 0), coalesce(b.pct, 0)) as d,
                       case when coalesce(b.pct, 0) > coalesce(p_so.discount_pct, 0) then 'deal' else 'customer' end as src) x;
$$;
comment on function public.so_line_quote(public.so, uuid, numeric) is
  '⭐ 줄 가격 식 한 곳(12-b 판정 4 · 할인 규칙 ②-0b) — so_price_for(티어 가격 · 세트 계산) × (1 − 할인/100) · 할인 = greatest(손님 기본 so.discount_pct, so_deal_best(product, customer, qty, so.order_date).pct) · 더하지 않는다 · 출처 = 딜이 더 클 때만 deal(deal_line_id 짝) · 같거나 작으면 customer. 단가는 자르지 않는다(판정 3) · 가격 없음은 (null, d, null, null, src, deal). 수량을 받는 이유: 몇 개 이상(qty · case) 줄 · 그 줄(같은 SKU 한 줄)의 수량만 본다(mix & match 없음)';
revoke all on function public.so_line_quote(public.so, uuid, numeric) from public, anon;
grant execute on function public.so_line_quote(public.so, uuid, numeric) to authenticated;     -- 읽기 — 화면 미리보기용(표 select 와 같은 층)

-- ═══ ③ 속 함수 둘 ═══
-- 3-a so_deal_line_ended — 그 딜 줄의 딜이 p_on 에 이미 끝났나(date_to < p_on) · 경고 deal_ended_before_line_added(D7) · 딜이 없으면 false · so_detail(invoker)이 부른다 → authenticated 허용
create function public.so_deal_line_ended(p_deal_line_id uuid, p_on date) returns boolean
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select coalesce((select d.date_to < p_on
                   from public.so_deal_line l join public.so_deal d on d.id = l.deal_id
                   where l.id = p_deal_line_id), false);
$$;
comment on function public.so_deal_line_ended(uuid, date) is 'D7 경고 재료 — 딜 줄의 딜 date_to < p_on 이면 true(세일이 끝난 뒤 줄을 넣었다 · 오더 날짜로는 기간 안이라 딜이 걸렸다). 줄 넣기는 ims_today() · so_detail 은 그 줄 (created_at at time zone America/Toronto)::date 로 묻는다 · 딜 줄이 없거나 끝이 없으면 false';
revoke all on function public.so_deal_line_ended(uuid, date) from public, anon;
grant execute on function public.so_deal_line_ended(uuid, date) to authenticated;

-- 3-b so_line_requote — 시스템 줄의 수량을 바꾸며 할인을 다시 매긴다(합치기가 쓴다 · 판정 2·3) · list_price 는 그 줄 것 그대로 · 부르는 쪽이 「시스템 줄」임을 보장한다
create function public.so_line_requote(p_line_id uuid, p_qty numeric) returns public.so_line
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
    qty_ordered     = p_qty,
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
comment on function public.so_line_requote(uuid, numeric) is 'SO 창구 속 함수(할인 규칙 ②-0b) — 시스템 줄(price_override=false · discount_source <> manual)의 수량을 p_qty 로 바꾸고 할인을 so_line_quote 로 다시 매긴다 · list_price 는 그 줄 것 그대로(할인만 다시 · 판정 3) · so_line_add·so_lines_paste 합치기가 쓴다 · 권한·초안 확인은 부르는 창구가 했다';
revoke all on function public.so_line_requote(uuid, numeric) from public, anon, authenticated;

-- ═══ ④ so_line_add — 재발행(마지막 정의 20260923191030:378 · 판정 2 합치기 · 출처 칸) ═══
--   창구 → 할인 식(so_line_quote · 수량 포함) → 손으로 준 할인(manual) · 단가(덮어쓰기) → 무상 검사 → 같은 SKU(판정 2) → 넣는 순간 굳힌다(출처 · 딜 줄까지)
create or replace function public.so_line_add(
  p_so_id        uuid,
  p_product_id   uuid,
  p_qty          numeric,
  p_unit_price   numeric default null,      -- 주면 덮어쓰기(price_override) · 0 = 무상(free_reason 필수)
  p_discount_pct numeric default null,      -- 주면 손님 기본·딜 대신 이 할인(source manual · unit_price 와 함께 못 준다)
  p_free_reason  text    default null,
  p_comments     text    default null,
  p_force_new    boolean default false      -- ask 의 답 「따로 줄로」
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_so       public.so%rowtype;
  p          public.product%rowtype;
  v_unit_nm  text;
  q          record;
  v_list     numeric;  v_disc numeric;  v_unit numeric;  v_src text;  v_dsrc text;  v_deal uuid;
  v_override boolean := false;
  v_manual   boolean := false;                                  -- 들어오는 줄을 사람이 정했나(단가 또는 할인)
  v_reason   text;  v_comments text;
  v_match    public.so_line%rowtype;
  v_line     public.so_line%rowtype;
  v_others   jsonb;
  v_next     int;
  v_warn     text[] := '{}';
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  if p_qty is null or p_qty <= 0 then
    raise exception 'Quantity must be a positive number — nothing was saved';
  end if;
  select * into p from public.product where id = p_product_id;
  if not found then
    raise exception 'Product not found — nothing was saved';
  end if;
  if not p.is_active then                                       -- ⬜5 — 되묻지 않고 거부
    raise exception 'Product % is inactive — nothing was saved', p.sku;
  end if;
  v_unit_nm := coalesce((select u.name from public.ref_unit u where u.id = p.unit_id), p.uom_name);

  -- 가격 — 창구 + 할인 식 한 곳(수량 포함 · 딜)
  select * into q from public.so_line_quote(v_so, p.id, p_qty);
  v_list := q.list_price;  v_disc := q.discount_pct;  v_unit := q.unit_price;  v_src := q.price_source;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;

  if p_discount_pct is not null and p_unit_price is not null then
    raise exception 'Give either a unit price or a discount, not both — nothing was saved';
  end if;
  if p_discount_pct is not null then                            -- 수동 할인 — 손님 기본·딜 대신(source manual · 다시 매기기가 건드리지 않는다)
    if p_discount_pct < 0 or p_discount_pct > 100 then
      raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
    end if;
    v_disc := p_discount_pct;
    v_unit := case when v_list is null then null else v_list * (1 - v_disc / 100) end;
    v_dsrc := 'manual';  v_deal := null;  v_manual := true;
  end if;
  if p_unit_price is not null then                              -- 덮어쓰기 — list_price 는 남긴다(받았을 금액 · 판정 2) · discount_pct·출처는 뜻이 없어 null(짝 CHECK)
    if p_unit_price < 0 then
      raise exception 'Unit price cannot be negative — nothing was saved';
    end if;
    v_unit := p_unit_price;  v_override := true;  v_disc := null;  v_dsrc := null;  v_deal := null;  v_manual := true;
  end if;

  -- 무상(판정 2 · ⬜7) — CHECK 가 마지막 문이지만 여기서 사람이 읽는 말로 먼저
  v_reason   := nullif(trim(p_free_reason), '');
  v_comments := nullif(trim(p_comments), '');
  if v_unit is not distinct from 0 and v_reason is null then
    raise exception 'A free line (price 0) needs a reason — sample, promotion, replacement or other — nothing was saved';
  end if;
  if v_reason is not null and v_unit is distinct from 0 then
    raise exception 'A free-goods reason needs a unit price of 0 — nothing was saved';
  end if;
  if v_reason is not null and v_reason not in ('sample', 'promotion', 'replacement', 'other') then
    raise exception 'Free reason % is not one of sample, promotion, replacement, other — nothing was saved', v_reason;
  end if;
  if v_reason = 'other' and v_comments is null then
    raise exception 'Reason other needs a comment — nothing was saved';
  end if;

  -- 같은 SKU(판정 2) — ① 들어오는 줄이 시스템이면 같은 제품의 시스템 줄과 제품만으로 합치고 합친 수량으로 다시 견적
  --                    ② 그 밖은 단가 비교 · 같으면 합침(시스템 줄이면 다시 견적 · 사람이 정한 줄이면 수량만) · 다르면 ask · p_force_new 면 그냥 새 줄
  if not p_force_new then
    if not v_manual then
      select * into v_match from public.so_line l
      where l.so_id = p_so_id and l.product_id = p.id and not l.price_override and l.discount_source is distinct from 'manual'
      order by l.line_no limit 1;
      if found then
        v_line := public.so_line_requote(v_match.id, v_match.qty_ordered + p_qty);
        if v_comments is not null then v_warn := array_append(v_warn, 'comments_not_merged'); end if;
        if v_line.unit_price is null then v_warn := array_append(v_warn, 'no_price'); end if;
        if v_line.deal_line_id is not null and public.so_deal_line_ended(v_line.deal_line_id, public.ims_today()) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
        return jsonb_build_object('action', 'merged', 'requoted', true, 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                                  'total', public.so_line_total(v_line), 'warnings', to_jsonb(v_warn));
      end if;
    end if;
    select * into v_match from public.so_line l
    where l.so_id = p_so_id and l.product_id = p.id and l.unit_price is not distinct from v_unit
    order by l.line_no limit 1;
    if found then
      if not v_match.price_override and v_match.discount_source is distinct from 'manual' then
        v_line := public.so_line_requote(v_match.id, v_match.qty_ordered + p_qty);     -- 시스템 줄에 합쳐졌다 → 시스템 규칙(수량이 바뀌면 다시 견적)
      else
        update public.so_line set qty_ordered = qty_ordered + p_qty, updated_by = v_staff
        where id = v_match.id returning * into v_line;                                 -- 사람이 정한 줄 → 수량만
      end if;
      if v_comments is not null then v_warn := array_append(v_warn, 'comments_not_merged'); end if;
      if v_line.unit_price is null then v_warn := array_append(v_warn, 'no_price'); end if;
      return jsonb_build_object('action', 'merged', 'requoted', not v_line.price_override and v_line.discount_source is distinct from 'manual', 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                                'total', public.so_line_total(v_line), 'warnings', to_jsonb(v_warn));
    end if;
    select jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'qty_ordered', l.qty_ordered,
                                        'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'price_override', l.price_override) order by l.line_no)
      into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = p.id;
    if v_others is not null then
      return jsonb_build_object('action', 'ask', 'so_number', v_so.so_number, 'product_id', p.id, 'sku', p.sku,
        'proposed', jsonb_build_object('qty_ordered', p_qty, 'list_price', v_list, 'discount_pct', v_disc, 'discount_source', v_dsrc, 'unit_price', v_unit, 'price_override', v_override),
        'existing', v_others,
        'message', 'Same SKU is already on this order at a different price — change that line (so_line_update) or add as a new line (p_force_new) — nothing was saved');
    end if;
  end if;

  select coalesce(max(line_no), 0) + 1 into v_next from public.so_line where so_id = p_so_id;
  insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                              list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason, tax_rule, comments, updated_by)
  values (p_so_id, v_next, p.id, p.sku, p.name, v_unit_nm, coalesce(p.pack_factor, 1), p_qty,
          v_list, v_disc, v_unit, v_override, v_dsrc, v_deal, v_reason, v_so.tax_rule, v_comments, v_staff)
  returning * into v_line;
  if v_unit is null then v_warn := array_append(v_warn, 'no_price'); end if;
  if v_deal is not null and public.so_deal_line_ended(v_deal, public.ims_today()) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;

  return jsonb_build_object('action', 'added', 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                            'total', public.so_line_total(v_line), 'price_source', v_src, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_line_add(uuid, uuid, numeric, numeric, numeric, text, text, boolean) is
  '⭐ SO 초안 줄 하나(①b · 할인 규칙 ②-0b 재발행 · 판정 2·4) — definer · 첫 줄 ims_require_write(sales) · 초안만 · 비활성 제품 거부. 가격 = so_line_quote(창구 × greatest(손님 할인, 딜) · 수량 포함) · p_discount_pct 는 그 할인 대신(source manual) · p_unit_price 는 덮어쓰기(price_override · discount_pct·source null · list_price 는 남긴다) · 0 원은 free_reason 필수. 같은 SKU(판정 2): 들어오는 줄이 시스템이면 같은 제품의 시스템 줄과 제품만으로 합치고 합친 수량으로 다시 견적(requoted) · 그 밖은 단가 비교 — 같으면 합침 · 다르면 action ask · p_force_new 로 새 줄(줄마다 따로 판정). 경고 deal_ended_before_line_added(D7). 넣는 순간 sku·product_name·unit·pack_factor·list_price·discount_pct·unit_price·discount_source·deal_line_id 를 굳힌다';

-- ═══ ⑤ so_lines_paste — 재발행(마지막 정의 20260923191030:502 · 판정 2 합치기 · 출처 칸 · 붙여넣기는 수동 줄을 만들지 않는다) ═══
--   판정어 여덟 그대로: ok · no_price · merged · ask · duplicate · not_found · inactive · bad_qty
create or replace function public.so_lines_paste(
  p_so_id  uuid,
  p_lines  jsonb,                          -- [{sku, qty}]
  p_commit boolean default false
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_limit    constant int := 500;
  v_staff    uuid;
  v_so       public.so%rowtype;
  v_n        int;
  v_next     int;
  r          record;
  v_sku      text;
  v_qty      numeric;
  v_pid uuid;  v_psku text;  v_pname text;  v_pactive boolean;  v_uom text;  v_unit_id uuid;  v_pack numeric;
  v_verdict  text;
  v_msgs     text[];
  v_dup_of   int;
  v_idx      int;
  i          int;
  -- 제품별로 모은 것(입력 순 · 첫 줄 번호가 대표)
  a_pid uuid[] := '{}';  a_n int[] := '{}';  a_qty numeric[] := '{}';  a_sku text[] := '{}';  a_name text[] := '{}';  a_unit text[] := '{}';  a_pack numeric[] := '{}';
  q          record;
  v_list numeric;  v_disc numeric;  v_unit numeric;  v_src text;  v_dsrc text;  v_deal uuid;
  v_match    public.so_line%rowtype;
  v_others   int;
  v_line_no  int;
  v_inserted boolean;  v_updated boolean;
  v_rows     jsonb := '[]'::jsonb;
  n_ok int := 0;  n_noprice int := 0;  n_merged int := 0;  n_ask int := 0;  n_dup int := 0;  n_nf int := 0;  n_inactive int := 0;  n_bad int := 0;  n_ins int := 0;  n_upd int := 0;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  v_n := coalesce(jsonb_array_length(p_lines), 0);
  if v_n > c_limit then
    return jsonb_build_object(
      'so_id', p_so_id, 'so_number', v_so.so_number, 'committed', false,
      'summary', jsonb_build_object('total', v_n, 'ok', 0, 'no_price', 0, 'merged', 0, 'ask', 0, 'duplicate', 0, 'not_found', 0, 'inactive', 0, 'bad_qty', 0,
                                    'inserted', 0, 'updated', 0, 'too_many', true, 'limit', c_limit,
                                    'message', format('Too many lines (%s) — up to %s lines per paste. Nothing was saved.', v_n, c_limit)),
      'lines', '[]'::jsonb);
  end if;

  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_so_id;

  -- 1) 입력 → 제품 · 같은 제품은 첫 줄에 수량을 모은다
  for r in
    select t.ord::int as n, t.e->>'sku' as sku_raw, t.e->>'qty' as qty_raw
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality as t(e, ord)
    order by t.ord
  loop
    v_pid := null; v_psku := null; v_pname := null; v_pactive := null; v_uom := null; v_unit_id := null; v_pack := null;
    v_verdict := null; v_msgs := '{}'; v_dup_of := null; v_idx := null;

    -- SKU 다듬기 — 앞뒤 공백(비분리 공백 포함)만 · po_lines_paste 와 같은 정규식(바이트 그대로)
    v_sku := nullif(regexp_replace(coalesce(r.sku_raw, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
    -- 수량 — 숫자만
    v_qty := case when r.qty_raw ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then r.qty_raw::numeric else null end;

    if v_sku is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'empty_sku');
    else
      select p.id, p.sku, p.name, p.is_active, p.uom_name, p.unit_id, p.pack_factor into v_pid, v_psku, v_pname, v_pactive, v_uom, v_unit_id, v_pack
      from public.product p where p.sku = v_sku;                                  -- 유니크 인덱스
      if v_pid is null then
        select p.id, p.sku, p.name, p.is_active, p.uom_name, p.unit_id, p.pack_factor into v_pid, v_psku, v_pname, v_pactive, v_uom, v_unit_id, v_pack
        from public.product p where upper(p.sku) = upper(v_sku) limit 1;         -- 폴백 · 못 찾은 줄에만
        if v_pid is not null then v_msgs := array_append(v_msgs, 'case_fixed'); end if;
      end if;
    end if;

    if v_verdict is null and v_pid is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'sku_not_in_product');
    end if;
    if v_verdict is null and v_pactive is false then
      v_verdict := 'inactive'; v_msgs := array_append(v_msgs, 'inactive_product — not added');
    end if;
    if v_verdict is null and (v_qty is null or v_qty <= 0) then
      v_verdict := 'bad_qty'; v_msgs := array_append(v_msgs, 'qty_must_be_positive_number');
    end if;

    if v_verdict is null then
      select s.i into v_idx from generate_subscripts(a_pid, 1) s(i) where a_pid[s.i] = v_pid limit 1;
      if v_idx is not null then
        v_dup_of := a_n[v_idx];
        a_qty[v_idx] := a_qty[v_idx] + v_qty;
        v_verdict := 'duplicate';
        v_msgs := array_append(v_msgs, format('merged_into_paste_line_%s — quantities added', v_dup_of));
      else
        a_pid := array_append(a_pid, v_pid);  a_n := array_append(a_n, r.n);  a_qty := array_append(a_qty, v_qty);
        a_sku := array_append(a_sku, v_psku);  a_name := array_append(a_name, v_pname);
        a_unit := array_append(a_unit, coalesce((select u.name from public.ref_unit u where u.id = v_unit_id), v_uom));
        a_pack := array_append(a_pack, v_pack);
      end if;
    end if;

    case v_verdict
      when 'not_found' then n_nf := n_nf + 1;
      when 'inactive'  then n_inactive := n_inactive + 1;
      when 'bad_qty'   then n_bad := n_bad + 1;
      when 'duplicate' then n_dup := n_dup + 1;
      else null;
    end case;

    v_rows := v_rows || jsonb_build_object(
      'n', r.n, 'input_sku', r.sku_raw, 'input_qty', r.qty_raw,
      'verdict', v_verdict,                                      -- null = 2) 에서 정해진다
      'product_id', v_pid, 'sku', v_psku, 'product_name', v_pname, 'product_active', v_pactive,
      'qty', v_qty, 'line_no', null, 'inserted', false, 'updated', false,
      'message', array_to_string(v_msgs, ' · '));
  end loop;

  -- 2) 제품별 — 가격(수량 포함) · 기존 줄과 대조(판정 2) · 넣기(결과는 그 제품의 첫 입력 줄에 적는다)
  for i in 1 .. coalesce(array_length(a_pid, 1), 0) loop
    select * into q from public.so_line_quote(v_so, a_pid[i], a_qty[i]);
    v_list := q.list_price;  v_disc := q.discount_pct;  v_unit := q.unit_price;  v_src := q.price_source;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    v_line_no := null; v_inserted := false; v_updated := false; v_msgs := '{}';

    -- ① 같은 제품의 시스템 줄 — 제품만으로 합치고 합친 수량으로 다시 견적
    select * into v_match from public.so_line l
    where l.so_id = p_so_id and l.product_id = a_pid[i] and not l.price_override and l.discount_source is distinct from 'manual'
    order by l.line_no limit 1;
    if found then
      v_verdict := 'merged'; v_line_no := v_match.line_no;
      v_msgs := array_append(v_msgs, format('added_to_line_%s — requoted at %s', v_match.line_no, v_match.qty_ordered + a_qty[i]));
      if p_commit then
        perform public.so_line_requote(v_match.id, v_match.qty_ordered + a_qty[i]);
        v_updated := true; n_upd := n_upd + 1;
      end if;
      n_merged := n_merged + 1;
    else
      -- ② 사람이 정한 줄 — 단가가 같으면 수량만 · 다르면 ask
      select * into v_match from public.so_line l
      where l.so_id = p_so_id and l.product_id = a_pid[i] and l.unit_price is not distinct from v_unit
      order by l.line_no limit 1;
      if found then
        v_verdict := 'merged'; v_line_no := v_match.line_no;
        v_msgs := array_append(v_msgs, format('added_to_line_%s', v_match.line_no));
        if p_commit then
          update public.so_line set qty_ordered = qty_ordered + a_qty[i], updated_by = v_staff where id = v_match.id;
          v_updated := true; n_upd := n_upd + 1;
        end if;
        n_merged := n_merged + 1;
      else
        select count(*) into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = a_pid[i];
        if v_others > 0 then
          v_verdict := 'ask';
          v_msgs := array_append(v_msgs, 'same_sku_at_different_price — use so_line_add to merge into that line or add separately (p_force_new)');
          n_ask := n_ask + 1;
        else
          if v_unit is null then
            v_verdict := 'no_price'; n_noprice := n_noprice + 1;
            v_msgs := array_append(v_msgs, 'no_price_for_this_tier — saved without a price; confirm will refuse until it has one');
          else
            v_verdict := 'ok'; n_ok := n_ok + 1;
          end if;
          if v_deal is not null and public.so_deal_line_ended(v_deal, public.ims_today()) then v_msgs := array_append(v_msgs, 'deal_ended_before_line_added'); end if;
          v_next := v_next + 1; v_line_no := v_next;
          if p_commit then
            insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                        list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason, tax_rule, comments, updated_by)
            values (p_so_id, v_line_no, a_pid[i], a_sku[i], a_name[i], a_unit[i], coalesce(a_pack[i], 1), a_qty[i],
                    v_list, v_disc, v_unit, false, v_dsrc, v_deal, null, v_so.tax_rule, null, v_staff);
            v_inserted := true; n_ins := n_ins + 1;
          end if;
        end if;
      end if;
    end if;

    v_rows := coalesce((
      select jsonb_agg(
               case when (e->>'n')::int = a_n[i]
                    then e || jsonb_build_object('verdict', v_verdict, 'qty', a_qty[i], 'list_price', v_list, 'discount_pct', v_disc, 'discount_source', v_dsrc,
                                                 'unit_price', v_unit, 'price_source', v_src, 'line_no', v_line_no,
                                                 'inserted', v_inserted, 'updated', v_updated, 'message', array_to_string(v_msgs, ' · '))
                    else e end
               order by (e->>'n')::int)
      from jsonb_array_elements(v_rows) e), '[]'::jsonb);
  end loop;

  return jsonb_build_object(
    'so_id', p_so_id, 'so_number', v_so.so_number, 'committed', p_commit,
    'summary', jsonb_build_object('total', v_n, 'ok', n_ok, 'no_price', n_noprice, 'merged', n_merged, 'ask', n_ask, 'duplicate', n_dup,
                                  'not_found', n_nf, 'inactive', n_inactive, 'bad_qty', n_bad,
                                  'inserted', n_ins, 'updated', n_upd, 'too_many', false, 'limit', c_limit, 'message', null),
    'lines', v_rows);
end;
$$;
comment on function public.so_lines_paste(uuid, jsonb, boolean) is
  '⭐ SO 초안 붙여넣기(①b · 할인 규칙 ②-0b 재발행) — definer · 첫 줄 ims_require_write(sales) · 초안만 · [{sku, qty}] · 500줄 한도는 판정. SKU 는 앞뒤 공백만 다듬고 정확 일치 → upper 폴백(case_fixed). 판정어 여덟: ok · no_price · merged · ask · duplicate · not_found · inactive · bad_qty. 붙여넣기 안 같은 SKU 는 첫 줄에 수량을 모으고(duplicate) · 기존 시스템 줄이 있으면 제품만으로 합쳐 합친 수량으로 다시 견적(merged · 판정 2) · 사람이 정한 줄은 단가가 같으면 수량만 · 다르면 ask · 비활성 제품은 거부. 가격은 so_line_quote(수량 포함 · 딜) · 붙여넣기는 수동 줄을 만들지 않는다 · 넣는 순간 굳힌다(출처 · 딜 줄까지)';

-- ═══ ⑥ so_line_update — 재발행(마지막 정의 20260923191030:684 · 이견 3 베낀 식 제거 · 판정 3 수량 변화 다시 견적) ═══
--   열쇠 아홉 그대로: qty_ordered · unit_price · discount_pct · free_reason · surcharge_pct · surcharge_amount · surcharge_label · tax_rule · comments
--   unit_price = 덮어쓰기(override · discount_pct·source null) · discount_pct 값 = manual · discount_pct 비움 = 시스템으로(so_line_quote · 딜 포함) · 열쇠 없이 qty 만 바뀌면 시스템 줄은 다시 견적
create or replace function public.so_line_update(p_line_id uuid, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_keys   constant text[] := array['qty_ordered', 'unit_price', 'discount_pct', 'free_reason', 'surcharge_pct', 'surcharge_amount', 'surcharge_label', 'tax_rule', 'comments'];
  v_staff  uuid;
  v_line   public.so_line%rowtype;
  v_so     public.so%rowtype;
  v_bad    text;
  q        record;
  v_qty    numeric;  v_unit numeric;  v_disc numeric;  v_override boolean;  v_dsrc text;  v_deal uuid;
  v_reason text;  v_comments text;
  v_spct   numeric;  v_samt numeric;  v_slbl text;
  v_line_no int;
  v_n      int;
  v_warn   text[] := '{}';
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();

  select * into v_line from public.so_line where id = p_line_id;
  if not found then
    raise exception 'Order line not found — nothing was saved';
  end if;
  v_line_no := v_line.line_no;
  v_so := public.so_require_draft(v_line.so_id, 'saved');

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'p_patch must be a JSON object — nothing was saved';
  end if;
  select k into v_bad from jsonb_object_keys(p_patch) k where k <> all (c_keys) limit 1;
  if v_bad is not null then
    raise exception 'Unknown field % — nothing was saved', v_bad;
  end if;
  if p_patch = '{}'::jsonb then
    raise exception 'Nothing to change — nothing was saved';
  end if;

  -- 수량
  v_qty := case when p_patch ? 'qty_ordered' then nullif(p_patch->>'qty_ordered', '')::numeric else v_line.qty_ordered end;
  if v_qty is null or v_qty <= 0 then
    raise exception 'Quantity must be a positive number — nothing was saved';
  end if;

  -- 가격 — 덮어쓰기 · 수동 할인 · 시스템으로 되돌리기 · 수량만 바뀐 시스템 줄은 다시 견적(판정 3) · 둘 다는 못 준다
  if p_patch ? 'unit_price' and p_patch ? 'discount_pct' then
    raise exception 'Give either a unit price or a discount, not both — nothing was saved';
  end if;
  if p_patch ? 'unit_price' then
    v_unit := nullif(p_patch->>'unit_price', '')::numeric;
    if v_unit is null then
      raise exception 'unit_price cannot be blank — remove the line or give a price — nothing was saved';
    end if;
    if v_unit < 0 then
      raise exception 'Unit price cannot be negative — nothing was saved';
    end if;
    v_override := true;  v_disc := null;  v_dsrc := null;  v_deal := null;
  elsif p_patch ? 'discount_pct' then
    v_disc := nullif(p_patch->>'discount_pct', '')::numeric;
    if v_disc is not null then                                   -- 수동 할인
      if v_disc < 0 or v_disc > 100 then
        raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
      end if;
      v_dsrc := 'manual';  v_deal := null;
    else                                                         -- 비우면 시스템으로(할인 식 한 곳 · 딜 포함 · 이견 3)
      select * into q from public.so_line_quote(v_so, v_line.product_id, v_qty);
      v_disc := q.discount_pct;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    end if;
    v_unit := case when v_line.list_price is null then null else v_line.list_price * (1 - v_disc / 100) end;
    v_override := false;
  elsif v_qty is distinct from v_line.qty_ordered and not v_line.price_override and v_line.discount_source is distinct from 'manual' then
    select * into q from public.so_line_quote(v_so, v_line.product_id, v_qty);      -- 시스템 줄 · 수량이 바뀌었다 → 할인 다시(list 는 그대로)
    v_disc := q.discount_pct;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    v_unit := case when v_line.list_price is null then null else v_line.list_price * (1 - v_disc / 100) end;
    v_override := false;
  else
    v_unit := v_line.unit_price;  v_disc := v_line.discount_pct;  v_override := v_line.price_override;  v_dsrc := v_line.discount_source;  v_deal := v_line.deal_line_id;
  end if;

  -- 무상(판정 2 · ⬜7)
  v_reason   := case when p_patch ? 'free_reason' then nullif(trim(p_patch->>'free_reason'), '') else v_line.free_reason end;
  v_comments := case when p_patch ? 'comments'    then nullif(trim(p_patch->>'comments'), '')    else v_line.comments end;
  if v_unit is not distinct from 0 and v_reason is null then
    raise exception 'A free line (price 0) needs a reason — sample, promotion, replacement or other — nothing was saved';
  end if;
  if v_reason is not null and v_unit is distinct from 0 then
    raise exception 'Line % has a free-goods reason but a non-zero price — clear the reason or set the price to 0 — nothing was saved', v_line_no;
  end if;
  if v_reason is not null and v_reason not in ('sample', 'promotion', 'replacement', 'other') then
    raise exception 'Free reason % is not one of sample, promotion, replacement, other — nothing was saved', v_reason;
  end if;
  if v_reason = 'other' and v_comments is null then
    raise exception 'Reason other needs a comment — nothing was saved';
  end if;

  -- 부가 요금(판정 7 · so_line_surcharge_ck) — 이름 ↔ 값 짝 · % 와 금액 둘 중 하나
  v_spct := case when p_patch ? 'surcharge_pct'    then nullif(p_patch->>'surcharge_pct', '')::numeric    else v_line.surcharge_pct end;
  v_samt := case when p_patch ? 'surcharge_amount' then nullif(p_patch->>'surcharge_amount', '')::numeric else v_line.surcharge_amount end;
  v_slbl := case when p_patch ? 'surcharge_label'  then nullif(trim(p_patch->>'surcharge_label'), '')     else v_line.surcharge_label end;
  if v_spct is not null and v_samt is not null then
    raise exception 'Use either a surcharge percent or an amount, not both — nothing was saved';
  end if;
  if v_slbl is not null and v_spct is null and v_samt is null then
    raise exception 'A surcharge needs a percent or an amount — nothing was saved';
  end if;
  if v_slbl is null and (v_spct is not null or v_samt is not null) then
    raise exception 'A surcharge needs a label — nothing was saved';
  end if;

  update public.so_line set
    qty_ordered      = v_qty,
    unit_price       = v_unit,
    discount_pct     = v_disc,
    price_override   = v_override,
    discount_source  = v_dsrc,
    deal_line_id     = v_deal,
    free_reason      = v_reason,
    comments         = v_comments,
    surcharge_pct    = v_spct,
    surcharge_amount = v_samt,
    surcharge_label  = v_slbl,
    tax_rule         = case when p_patch ? 'tax_rule' then nullif(trim(p_patch->>'tax_rule'), '') else tax_rule end,
    updated_by       = v_staff
  where id = p_line_id
  returning * into v_line;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Line % of % was not saved — it may have been removed by someone else just now — nothing was saved', v_line_no, v_so.so_number;
  end if;
  if v_line.unit_price is null then v_warn := array_append(v_warn, 'no_price'); end if;
  if v_line.deal_line_id is not null and public.so_deal_line_ended(v_line.deal_line_id, public.ims_today()) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;

  return jsonb_build_object('so_number', v_so.so_number, 'line', to_jsonb(v_line), 'total', public.so_line_total(v_line), 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_line_update(uuid, jsonb) is
  '⭐ SO 초안 줄 고치기(①b · 할인 규칙 ②-0b 재발행) — definer · 첫 줄 ims_require_write(sales) · 초안만 · 열쇠 아홉 · 모르는 열쇠 거부. unit_price = 덮어쓰기(price_override · discount_pct·source null) · discount_pct 값 = 수동 할인(source manual · 다시 매기기가 건드리지 않는다) · discount_pct 비움 = 시스템으로(so_line_quote · 손님 기본·딜 중 큰 것 · 이견 3) · 열쇠 없이 qty 만 바뀌면 시스템 줄은 할인을 다시 매긴다(판정 3 · list_price 는 그대로) · 사람이 정한 줄은 그대로. 무상·부가 요금 규칙은 CHECK 앞에서 사람이 읽는 말로 거부 · 경고 no_price · deal_ended_before_line_added';

-- ═══ ⑦ so_create — 재발행(마지막 정의 20260923191030:140 · 오더 전체 할인 굳히기 ⬜4 · 더한 줄만) ═══
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

  if p_channel is distinct from 'warehouse' then
    raise exception 'Channel % is not available yet — only warehouse orders can be created here (pos and counter come later) — nothing was saved', coalesce(p_channel, 'null');
  end if;
  if p_intake is null or p_intake not in ('manual', 'csv') then
    raise exception 'Intake % is not accepted here — manual or csv only (shopify and pos are other paths) — nothing was saved', coalesce(p_intake, 'null');
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
    'ship_to_is_company', v_copy->'ship_to_is_company',
    'warnings',      to_jsonb(v_warn));
end;
$$;
comment on function public.so_create(uuid, text, text, uuid, text) is
  '⭐ SO 초안 만들기(SO 쓰기 ①b · 할인 규칙 ②-0b 재발행) — security definer · 첫 줄 ims_require_write(sales). warehouse 채널 · intake manual|csv 만 · 비활성 손님 거부(판정 A) · 손님 통화 없으면 거부 · so_number 는 so_next_number(). 손님 값은 so_copy_customer(①a)가 굳힌다(티어 = 손님 기본 · 판정 B ①) · 오더 전체 할인은 so_order_discount 로 찾아 so.order_discount_*(source deal)에 굳힌다(D6 · ⬜4). 반환 warnings = 복사 경고 + so_tier_warnings(막지 않는다)';

-- ═══ ⑧ so_header_update — 재발행(마지막 정의 20260923191030:221 · 열쇠 30 · 오더 전체 할인 · reprice_suggested) ═══
--   더한 것: 열쇠 order_discount_pct(값 → manual · deal_id null · null → 다시 찾기) · 손님·오더 날짜가 바뀌면 source deal 일 때만 다시 찾기 ·
--            order_date · price_tier · discount_pct 를 바꿀 때 줄이 있으면 reprice_suggested_at = now() + 경고 reprice_suggested(판정 3 — 줄은 그대로)
--   ⚠️ 판정문은 order_date · price_tier 둘을 말했다 · discount_pct(손님 기본 할인)도 줄 할인의 재료라 같이 넣었다 — 회신에 표시
create or replace function public.so_header_update(p_so_id uuid, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_keys  constant text[] := array[
    'customer_id', 'location_id', 'payment_term_id', 'discount_pct', 'tax_rule', 'price_tier',
    'order_date', 'required_by', 'ref', 'comments', 'shipping_notes', 'carrier', 'tracking_number',
    'bill_to_name', 'bill_to_line1', 'bill_to_line2', 'bill_to_city', 'bill_to_state_province', 'bill_to_postal_code', 'bill_to_country',
    'ship_to_company', 'ship_to_contact', 'ship_to_phone', 'ship_to_line1', 'ship_to_line2', 'ship_to_city', 'ship_to_state_province', 'ship_to_postal_code', 'ship_to_country',
    'order_discount_pct'];
  v_staff uuid;
  v_so    public.so%rowtype;
  v_key   text;
  v_bad   text;
  v_n_lines int;  v_n_charges int;
  c       public.customer%rowtype;
  v_wh    public.ref_warehouse%rowtype;
  v_pt    public.ref_payment_term%rowtype;
  v_tier  public.ref_price_tier%rowtype;
  v_disc  numeric;
  v_od    numeric;
  od      record;
  v_reprice boolean := false;
  v_warn  text[] := '{}';
  v_n     int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'p_patch must be a JSON object — nothing was saved';
  end if;
  select k into v_bad from jsonb_object_keys(p_patch) k where k <> all (c_keys) limit 1;
  if v_bad is not null then
    raise exception 'Unknown field % — nothing was saved', v_bad;
  end if;
  if p_patch = '{}'::jsonb then
    raise exception 'Nothing to change — nothing was saved';
  end if;

  select count(*) into v_n_lines   from public.so_line   where so_id = p_so_id;
  select count(*) into v_n_charges from public.so_charge where so_id = p_so_id;

  -- 손님 바꾸기(⬜6) — 줄·운임이 있으면 거부 · 비활성 거부(판정 A) · so_copy_customer 가 다시 굳힌다(창고는 이미 있으면 그대로)
  if p_patch ? 'customer_id' then
    if v_n_lines + v_n_charges > 0 then
      raise exception 'Remove all lines and charges before changing the customer — nothing was saved';
    end if;
    select * into c from public.customer where id = nullif(p_patch->>'customer_id', '')::uuid;
    if not found then
      raise exception 'Customer not found — nothing was saved';
    end if;
    if not c.is_active then
      raise exception 'Customer % is inactive — reactivate it first — nothing was saved', c.name;
    end if;
    perform public.so_copy_customer(p_so_id, c.id);
    select * into v_so from public.so where id = p_so_id;
  end if;

  -- 창고 — 준 값 검사(null 이면 비운다)
  if p_patch ? 'location_id' then
    if jsonb_typeof(p_patch->'location_id') = 'null' or p_patch->>'location_id' = '' then
      v_wh := null;
    else
      select * into v_wh from public.ref_warehouse where id = (p_patch->>'location_id')::uuid;
      if not found then
        raise exception 'Warehouse not found — nothing was saved';
      end if;
      if not v_wh.is_active then
        raise exception 'Warehouse % is inactive — nothing was saved', v_wh.name;
      end if;
    end if;
  end if;

  -- 결제조건 — FK + 원문 짝
  if p_patch ? 'payment_term_id' then
    if jsonb_typeof(p_patch->'payment_term_id') = 'null' or p_patch->>'payment_term_id' = '' then
      v_pt := null;
    else
      select * into v_pt from public.ref_payment_term where id = (p_patch->>'payment_term_id')::uuid;
      if not found then
        raise exception 'Payment term not found — nothing was saved';
      end if;
    end if;
  end if;

  -- 손님 기본 할인 — 0~100 · 이미 들어간 줄의 할인은 따라가지 않는다(넣는 순간 굳힌다 · ⬜5) · 줄이 있으면 reprice_suggested(판정 3)
  if p_patch ? 'discount_pct' then
    v_disc := nullif(p_patch->>'discount_pct', '')::numeric;
    if v_disc is not null and (v_disc < 0 or v_disc > 100) then
      raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
    end if;
    if v_n_lines > 0 then v_warn := array_append(v_warn, 'lines_keep_prices'); v_reprice := true; end if;
  end if;

  -- 티어(판정 B ⑤) — 이름으로 받아 purpose sale · 활성만 · 원문 + FK 짝으로 · 들어간 줄의 가격은 그대로(④ 로 보인다) · 줄이 있으면 reprice_suggested
  if p_patch ? 'price_tier' then
    select * into v_tier from public.ref_price_tier where name = p_patch->>'price_tier';
    if not found then
      raise exception 'Price tier % not found — nothing was saved', p_patch->>'price_tier';
    end if;
    if v_tier.purpose <> 'sale' then
      raise exception 'Price tier % is not a selling tier (purpose %) — nothing was saved', v_tier.name, v_tier.purpose;
    end if;
    if not v_tier.is_active then
      raise exception 'Price tier % is inactive — nothing was saved', v_tier.name;
    end if;
    if v_n_lines > 0 then v_warn := array_append(v_warn, 'lines_keep_prices'); v_reprice := true; end if;
  end if;

  -- 오더 날짜 — 딜 기간의 기준(D7) · 줄이 있으면 reprice_suggested(줄은 그대로 · 판정 3)
  if p_patch ? 'order_date' and v_n_lines > 0 and nullif(p_patch->>'order_date', '')::date is distinct from v_so.order_date then
    v_reprice := true;
  end if;

  -- 오더 전체 할인 — 값이면 manual(0~100 · 0 = 사람이 껐다) · null 이면 다시 찾기(아래)
  if p_patch ? 'order_discount_pct' then
    v_od := nullif(p_patch->>'order_discount_pct', '')::numeric;
    if v_od is not null and (v_od < 0 or v_od > 100) then
      raise exception 'order_discount_pct must be between 0 and 100 — nothing was saved';
    end if;
  end if;

  update public.so s set
    location_id        = case when p_patch ? 'location_id'     then v_wh.id   else s.location_id end,
    location_name      = case when p_patch ? 'location_id'     then v_wh.name else s.location_name end,
    payment_term_id    = case when p_patch ? 'payment_term_id' then v_pt.id   else s.payment_term_id end,
    payment_term_name  = case when p_patch ? 'payment_term_id' then v_pt.name else s.payment_term_name end,
    discount_pct       = case when p_patch ? 'discount_pct'    then v_disc    else s.discount_pct end,
    tax_rule           = case when p_patch ? 'tax_rule'        then nullif(p_patch->>'tax_rule', '') else s.tax_rule end,
    price_tier         = case when p_patch ? 'price_tier'      then v_tier.name else s.price_tier end,
    price_tier_id      = case when p_patch ? 'price_tier'      then v_tier.id   else s.price_tier_id end,
    order_date         = case when p_patch ? 'order_date'      then coalesce(nullif(p_patch->>'order_date', '')::date, s.order_date) else s.order_date end,
    required_by        = case when p_patch ? 'required_by'     then nullif(p_patch->>'required_by', '')::date else s.required_by end,
    ref                = case when p_patch ? 'ref'             then nullif(trim(p_patch->>'ref'), '') else s.ref end,
    comments           = case when p_patch ? 'comments'        then nullif(trim(p_patch->>'comments'), '') else s.comments end,
    shipping_notes     = case when p_patch ? 'shipping_notes'  then nullif(trim(p_patch->>'shipping_notes'), '') else s.shipping_notes end,
    carrier            = case when p_patch ? 'carrier'         then nullif(trim(p_patch->>'carrier'), '') else s.carrier end,
    tracking_number    = case when p_patch ? 'tracking_number' then nullif(trim(p_patch->>'tracking_number'), '') else s.tracking_number end,
    bill_to_name           = case when p_patch ? 'bill_to_name'           then nullif(trim(p_patch->>'bill_to_name'), '')           else s.bill_to_name end,
    bill_to_line1          = case when p_patch ? 'bill_to_line1'          then nullif(trim(p_patch->>'bill_to_line1'), '')          else s.bill_to_line1 end,
    bill_to_line2          = case when p_patch ? 'bill_to_line2'          then nullif(trim(p_patch->>'bill_to_line2'), '')          else s.bill_to_line2 end,
    bill_to_city           = case when p_patch ? 'bill_to_city'           then nullif(trim(p_patch->>'bill_to_city'), '')           else s.bill_to_city end,
    bill_to_state_province = case when p_patch ? 'bill_to_state_province' then nullif(trim(p_patch->>'bill_to_state_province'), '') else s.bill_to_state_province end,
    bill_to_postal_code    = case when p_patch ? 'bill_to_postal_code'    then nullif(trim(p_patch->>'bill_to_postal_code'), '')    else s.bill_to_postal_code end,
    bill_to_country        = case when p_patch ? 'bill_to_country'        then nullif(trim(p_patch->>'bill_to_country'), '')        else s.bill_to_country end,
    ship_to_company        = case when p_patch ? 'ship_to_company'        then nullif(trim(p_patch->>'ship_to_company'), '')        else s.ship_to_company end,
    ship_to_contact        = case when p_patch ? 'ship_to_contact'        then nullif(trim(p_patch->>'ship_to_contact'), '')        else s.ship_to_contact end,
    ship_to_phone          = case when p_patch ? 'ship_to_phone'          then nullif(trim(p_patch->>'ship_to_phone'), '')          else s.ship_to_phone end,
    ship_to_line1          = case when p_patch ? 'ship_to_line1'          then nullif(trim(p_patch->>'ship_to_line1'), '')          else s.ship_to_line1 end,
    ship_to_line2          = case when p_patch ? 'ship_to_line2'          then nullif(trim(p_patch->>'ship_to_line2'), '')          else s.ship_to_line2 end,
    ship_to_city           = case when p_patch ? 'ship_to_city'           then nullif(trim(p_patch->>'ship_to_city'), '')           else s.ship_to_city end,
    ship_to_state_province = case when p_patch ? 'ship_to_state_province' then nullif(trim(p_patch->>'ship_to_state_province'), '') else s.ship_to_state_province end,
    ship_to_postal_code    = case when p_patch ? 'ship_to_postal_code'    then nullif(trim(p_patch->>'ship_to_postal_code'), '')    else s.ship_to_postal_code end,
    ship_to_country        = case when p_patch ? 'ship_to_country'        then nullif(trim(p_patch->>'ship_to_country'), '')        else s.ship_to_country end,
    reprice_suggested_at   = case when v_reprice then now() else s.reprice_suggested_at end,
    updated_by         = v_staff
  where s.id = p_so_id and s.status = 'draft'
  returning * into v_so;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order was not saved — it may have been changed by someone else just now — nothing was saved';
  end if;

  -- 오더 전체 할인(D6 · ⬜4) — 값을 받았으면 manual · null 을 받았거나(다시 찾기) 손님·오더 날짜가 바뀌었는데 source 가 manual 이 아니면 so_order_discount 로 다시
  if p_patch ? 'order_discount_pct' and v_od is not null then
    update public.so set order_discount_pct = v_od, order_discount_deal_id = null, order_discount_source = 'manual', updated_by = v_staff
    where id = p_so_id and status = 'draft' returning * into v_so;
  elsif (p_patch ? 'order_discount_pct')
     or ((p_patch ? 'customer_id' or p_patch ? 'order_date') and v_so.order_discount_source is distinct from 'manual') then
    select * into od from public.so_order_discount(p_so_id);
    update public.so set order_discount_pct = od.pct, order_discount_deal_id = od.deal_id,
                         order_discount_source = case when od.pct is null then null else 'deal' end, updated_by = v_staff
    where id = p_so_id and status = 'draft' returning * into v_so;
  end if;

  if v_reprice then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  v_warn := v_warn || public.so_tier_warnings(v_so);
  return jsonb_build_object('so', to_jsonb(v_so), 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_header_update(uuid, jsonb) is
  '⭐ SO 초안 머리 고치기(①b · 할인 규칙 ②-0b 재발행 · ⬜4 · 판정 3) — definer · 첫 줄 ims_require_write(sales) · 초안만. 허락 열쇠 30(29 + order_discount_pct) · 모르는 열쇠 거부. 손님 바꾸기는 줄·운임이 0일 때만. discount_pct · price_tier · order_date 를 바꾸면 들어간 줄은 그대로(lines_keep_prices) + 줄이 있으면 reprice_suggested_at·경고 reprice_suggested(so_reprice 가 다시 매긴다). 오더 전체 할인: order_discount_pct 값 → manual(deal_id null) · null → so_order_discount 로 다시 · 손님·오더 날짜가 바뀌면 source deal 일 때만 다시 찾는다';

-- ═══ ⑨ so_reprice — 새 창구 · 할인 다시 매기기(판정 3 · 9-b so_<동작>) ═══
--   시스템 줄(price_override=false · discount_source <> manual) 전부 so_line_quote 로 할인 다시(list_price 그대로) · 사람이 정한 줄은 그대로(kept) ·
--   오더 전체 할인은 source deal(또는 없음)일 때만 다시 · manual 은 덮지 않는다 · reprice_suggested_at 지움 · 반환 줄마다 이전 → 새 + 바뀐 줄 수
create function public.so_reprice(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_so      public.so%rowtype;
  l         public.so_line%rowtype;
  q         record;
  od        record;
  v_rows    jsonb := '[]'::jsonb;
  v_changed int := 0;
  v_diff    boolean;
  v_old_pct numeric;  v_old_src text;  v_old_deal uuid;
  v_n       int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  for l in select * from public.so_line where so_id = p_so_id order by line_no loop
    if l.price_override or l.discount_source is not distinct from 'manual' then
      v_rows := v_rows || jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'kept', true,
                  'reason', case when l.price_override then 'price_override' else 'manual_discount' end,
                  'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'changed', false);
      continue;
    end if;
    select * into q from public.so_line_quote(v_so, l.product_id, l.qty_ordered);
    v_diff := q.discount_pct is distinct from l.discount_pct or q.discount_source is distinct from l.discount_source or q.deal_line_id is distinct from l.deal_line_id;
    if v_diff then
      update public.so_line set
        discount_pct    = q.discount_pct,
        unit_price      = case when list_price is null then null else list_price * (1 - q.discount_pct / 100) end,
        discount_source = q.discount_source,
        deal_line_id    = q.deal_line_id,
        updated_by      = v_staff
      where id = l.id;
      v_changed := v_changed + 1;
    end if;
    v_rows := v_rows || jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'kept', false,
                'old_discount_pct', l.discount_pct, 'old_discount_source', l.discount_source, 'old_deal_line_id', l.deal_line_id,
                'new_discount_pct', q.discount_pct, 'new_discount_source', q.discount_source, 'new_deal_line_id', q.deal_line_id, 'changed', v_diff);
  end loop;

  -- 오더 전체 할인 — manual 은 덮지 않는다
  v_old_pct := v_so.order_discount_pct;  v_old_src := v_so.order_discount_source;  v_old_deal := v_so.order_discount_deal_id;
  if v_so.order_discount_source is distinct from 'manual' then
    select * into od from public.so_order_discount(p_so_id);
    update public.so set order_discount_pct = od.pct, order_discount_deal_id = od.deal_id,
                         order_discount_source = case when od.pct is null then null else 'deal' end,
                         reprice_suggested_at = null, updated_by = v_staff
    where id = p_so_id and status = 'draft' returning * into v_so;
  else
    update public.so set reprice_suggested_at = null, updated_by = v_staff
    where id = p_so_id and status = 'draft' returning * into v_so;
  end if;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order was not saved — it may have been changed by someone else just now — nothing was saved';
  end if;

  return jsonb_build_object(
    'so_number', v_so.so_number, 'lines', v_rows, 'changed_lines', v_changed,
    'order_discount', jsonb_build_object(
      'old_pct', v_old_pct, 'old_source', v_old_src, 'old_deal_id', v_old_deal,
      'new_pct', v_so.order_discount_pct, 'new_source', v_so.order_discount_source, 'new_deal_id', v_so.order_discount_deal_id,
      'kept', v_old_src is not distinct from 'manual',
      'changed', v_so.order_discount_pct is distinct from v_old_pct or v_so.order_discount_deal_id is distinct from v_old_deal));
end;
$$;
comment on function public.so_reprice(uuid) is
  '⭐ 할인 다시 매기기(할인 규칙 ②-0b · 판정 3 · Caleb 「cin7에도 있는데, 편리한 것 같아」) — definer · 첫 줄 ims_require_write(sales) · 초안만. 시스템 줄(price_override=false · discount_source <> manual)은 so_line_quote 로 할인을 다시(손님 기본·딜 중 큰 것 · list_price 는 그대로 — 할인만이다) · 사람이 정한 줄(덮어쓴 단가 · 수동 할인)은 그대로(kept) · 오더 전체 할인은 source deal(또는 없음)일 때만 다시 찾는다(manual 은 덮지 않는다) · reprice_suggested_at 을 지운다. 반환 lines[{line_no, sku, kept, old_* → new_*, changed}] · changed_lines · order_discount{old → new · kept · changed}';
revoke all on function public.so_reprice(uuid) from public, anon;
grant execute on function public.so_reprice(uuid) to authenticated;

-- ═══ ⑩ so_detail — 재발행(마지막 정의 20260923191030:981 · totals 넷 · 경고 둘 · 줄에 deal_ended) ═══
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
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('total', public.so_line_total(l), 'no_price', l.unit_price is null, 'free', l.free_reason is not null,
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)) order by l.line_no), '[]'::jsonb),
         count(*), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), coalesce(sum(public.so_line_total(l)), 0),
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date))
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

  -- 오더 전체 할인(D6) — 제품 줄 합계에 한 번 · round 2(SO-10842 실물) · 운임은 기준에 없다
  v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;

  v_warn := public.so_tier_warnings(v_so);
  if v_lines_n = 0    then v_warn := array_append(v_warn, 'no_lines'); end if;
  if v_no_price > 0   then v_warn := array_append(v_warn, 'lines_without_price'); end if;
  if v_deal_ended > 0 then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'totals', jsonb_build_object('lines', v_lines_n, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt,
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'order_total', v_lines_total - v_od_amt + v_charges_total),
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_detail(uuid) is
  '⭐ SO 오더 읽기 한 창구(①b · 할인 규칙 ②-0b 재발행) — invoker · stable(RLS select 그대로 · 로그인만). so · customer_name · lines(+ total · no_price · free · deal_ended) · charges · totals(lines_total = Σ so_line_total · order_discount_amount = round(lines_total × order_discount_pct/100, 2) · lines_after_discount · order_total = lines_total − order_discount_amount + charges_total — 운임은 할인 기준에 없다(D6) · 세금은 인보이스 차수) · warnings = so_tier_warnings + no_lines · lines_without_price · deal_ended_before_line_added(줄의 딜 date_to < 그 줄 created_at 의 토론토 날짜 · D7) · reprice_suggested(so.reprice_suggested_at). 화면 셋이 다시 짜지 않는다';

-- ═══ 권한 — 재발행 여섯은 create or replace 라 grant 유지(20260923191030 ⑫ 그대로) · 새것 셋은 위에서 각각(so_line_quote · so_deal_line_ended · so_reprice = authenticated · so_line_requote = 속 함수) ═══

-- ═══ 검증(~/asung/prompts/so-deal-0b-verify.sql · psql -v ON_ERROR_STOP=1 -f · 시퀀스는 rollback 밖 setval) ═══
--   함수: so_line_quote(so,uuid,numeric) 1 · 옛 (so,uuid) 0 · so_deal_line_ended · so_line_requote · so_reprice 신설 · 재발행 여섯 · so.reprice_suggested_at
--   흐름(태그 12 이상 20% 딜 · 손님 기본 7% · 딜 date_to 는 오늘 전): so_create(오더 전체 5% 굳음) → order_date 딜 기간 안 → add 6 → 7% customer · add 6 → merged 12 · 20% deal(+ deal_ended_before_line_added) · add 6 → 18 · 줄 1 ·
--        수동 10% 줄 → qty 바꿔도 10% · 수동 단가 줄 → 다른 단가 ask · 같은 단가 merged 수량만 · update qty 18 → 6 → 7% customer · 12 → 20% deal ·
--        paste 같은 SKU → merged requoted · 새 SKU ok 7% · order_date 밖 → reprice_suggested · so_reprice → 시스템 줄 7% · 수동·덮어쓴 줄 kept · changed_lines ·
--        운임 110.50 → so_detail 할인 = round(제품 줄 합계 × 5%, 2) · 운임 그대로 · order_discount_pct 3 → manual · so_reprice 가 덮지 않음 · null → 5 deal
--   권한: 쓰기 창구 열 개(so_reprice 포함) sales 없는 가짜 직원 거부 · so_detail·so_line_quote 는 읽기
