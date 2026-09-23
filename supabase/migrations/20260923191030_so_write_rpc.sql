-- SO 쓰기 ①b — 초안 창구 열 개(so_create · so_header_update · so_line_add · so_lines_paste · so_line_update · so_line_remove · so_charge_set · so_charge_remove · so_delete · so_detail)
-- 지시서 ~/asung/prompts/so-write-1-draft.md · 판정 Caleb 2026-09-23(①a 회신 1~8 · 판정 A 비활성 손님 거부 · 판정 B 티어는 들어온 곳이 정한다 ①~⑤)
-- 바탕: 20260923182231_so_write_base.sql(권한 sales · 표 보정 · so_status_guard · so_price_for · so_line_total · so_customer_is_company · so_copy_customer)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
--
-- ⭐ 쓰기 방식 — PO 와 다르다(판정 5 · 정본 §12 「왜 다른가」)
--    PO  security invoker + auth_all/쓰기 정책 ⇒ 화면이 표를 직접 update 할 수 있었고 그 길로 사고(po.html setStatus)
--    SO  표 넷은 읽기만(select 정책 · select grant) · 쓰기는 이 파일의 security definer 창구만 ⇒ 창구 첫 줄 ims_require_write('sales') 가 유일한 문
--    ⚠️ 대가: 창구 하나라도 첫 줄이 빠지면 누구나 쓴다 ⇒ 검증은 창구 열 개 전부 「sales 없는 신원 → 거부」
--    definer 함수마다 set search_path = public, pg_temp · 쓰기 전에 초안인지 확인(so_require_draft) · 거부 문장은 사람이 읽는 영어 · 끝은 「— nothing was saved|deleted」(PO 「솔직한 거부」 관례)
--    auth.uid() 는 JWT claim 을 읽으므로 definer 안에서도 호출자다(①a 이견 2)
-- ⭐ 가격 — 창구 so_price_for(①a) → 할인 식 한 곳 so_line_quote(줄 할인 = greatest(손님 기본, 0 /* 할인 차수 */) · 판정 4) → 넣는 순간 굳힌다(sku · product_name · unit · pack_factor · list_price · discount_pct · unit_price)
--    가격 없음 = unit_price null(줄은 선다 · 확정 ② 가 막는다) · 0 원을 받으면 price_override := true + free_reason 필수(판정 2 · ①a CHECK 가 마지막 문)
--    같은 SKU: unit_price is not distinct from 이면 qty 를 합치고 · 다르면 ask(줄 안 넣음 · 화면이 고른다 · p_force_new 가 「따로 줄로」) · 5-e 유니크 제약 금지
-- ⭐ 티어(판정 B) — 직접 만드는 오더(intake manual · csv)는 손님 기본 티어(so_copy_customer 그대로) · inv_config so_direct_order_tier_code(=1 Wholesale) 와 다르면 경고 direct_order_tier_unexpected(막지 않는다)
--    so.price_tier_id ≠ 손님 원문으로 찾은 티어 → tier_differs_from_customer(so_detail) · so_header_update 열쇠 price_tier(purpose sale 만 · 원문+FK 짝 · 들어간 줄 가격은 그대로)
-- ⚠️ 다시 만들지 않은 것: ims_touch() 20260918133858:41 · ims_can_write() 20260918020000:99 · ims_require_write() 20260918010000:18 · ①a 함수 여섯
-- ⚠️ 시퀀스: so_create 가 so_number 기본값(so_next_number · 25000 부터)을 쓴다 — 시험은 번호를 소비한다 · 끝에 setval(판정 1 · rollback 밖) · 정본 §12 「전환 전 점검 25000 · is_called f」
-- ⚠️ inv_config 는 auth_all — 로그인한 누구나 바꿀 수 있다 · so_direct_order_tier_code 는 경고만 좌우한다(정본 §12 사실로)

-- ═══ 0) 설정 한 줄 — 판정 B ② · 선례 20260916190000:103 (on conflict (key) do nothing) ═══
insert into public.inv_config (key, value, note) values
  ('so_direct_order_tier_code', '1',
   'Price tier code (ref_price_tier.code · 1 = Wholesale) expected on orders created directly (intake manual · csv). Only a warning (direct_order_tier_unexpected) — never blocks. Caleb 2026-09-23: 「aonebeauty.com은 전화나 이메일로 오더를 받지 않아. 그렇게 받는 손님은 모두 wholesale 손님이야」 · 「사실 오더 채널이 정해져 있어서 그 채널이 곧 프라이스 티어야」 · read by code, not name (same rule as the price load)')
on conflict (key) do nothing;

-- ═══ 1) 속 함수 셋 — 창구가 공유한다(authenticated 는 부르지 못한다 · definer 창구가 소유자 권한으로 부른다) ═══
-- 1-a so_current_staff — 만든 사람 · 고친 사람(서버 유도 · PO po_create 선례 문장 그대로)
create function public.so_current_staff() returns uuid
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then
    raise exception 'No active staff record for this login — nothing was saved';
  end if;
  return v_staff;
end;
$$;
comment on function public.so_current_staff() is 'SO 창구 속 함수 — 호출자의 ims_staff.id(auth.uid() · 활성) · 없으면 거부(PO 선례 문장). authenticated 직접 호출 불가';
revoke all on function public.so_current_staff() from public, anon, authenticated;

-- 1-b so_require_draft — 오더를 읽고 초안이 아니면 거부(모든 쓰기 창구 둘째 줄 · ⬜1)
create function public.so_require_draft(p_so_id uuid, p_verb text default 'saved') returns public.so
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare v_so public.so%rowtype;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found — nothing was %', p_verb;
  end if;
  if v_so.status <> 'draft' then
    raise exception 'Order % is not a draft (status %) — nothing was %', v_so.so_number, v_so.status, p_verb;
  end if;
  return v_so;
end;
$$;
comment on function public.so_require_draft(uuid, text) is 'SO 창구 속 함수 — 오더 행을 돌려주되 없거나 초안이 아니면 거부(「— nothing was saved|deleted」). ⚠️ 잠그지 않는다 — 전이는 so_status_guard 가 마지막 문';
revoke all on function public.so_require_draft(uuid, text) from public, anon, authenticated;

-- 1-c so_line_quote — ⭐ 할인 식 한 곳(판정 4 📌 세일 항은 아래 d 한 줄에 낀다) · so_price_for(①a) 위에 손님 기본 할인
--    (list_price, discount_pct, unit_price, price_source) · unit_price = list × (1 − d/100) 자르지 않는다(판정 3) · list 없으면 unit 도 null(가격 없음)
create function public.so_line_quote(p_so public.so, p_product_id uuid)
  returns table (list_price numeric, discount_pct numeric, unit_price numeric, price_source text)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select f.list_price,
         x.d,
         case when f.list_price is null then null else f.list_price * (1 - x.d / 100) end,
         f.price_source
  from public.so_price_for(p_product_id, p_so.price_tier_id) f,
       lateral (select greatest(coalesce(p_so.discount_pct, 0), 0 /* 할인 차수: 그 줄에 맞는 세일 % 가 여기 온다 — 더하지 않고 큰 것 하나(판정 4) */) as d) x;
$$;
comment on function public.so_line_quote(public.so, uuid) is '⭐ 줄 가격 식 한 곳(판정 4) — so_price_for(티어 가격 · 세트 계산) × (1 − 할인/100) · 할인 = greatest(손님 기본 so.discount_pct, 세일 %(할인 차수 · 지금 0)) · 더하지 않는다. 단가는 자르지 않는다(판정 3) · 가격 없음은 (null, d, null, null)';
revoke all on function public.so_line_quote(public.so, uuid) from public, anon;
grant execute on function public.so_line_quote(public.so, uuid) to authenticated;     -- 읽기 — 화면 미리보기용(표 select 와 같은 층)

-- 1-d so_tier_warnings — 판정 B ③·④ + 티어·통화 경고(so_create 반환 · so_detail 둘 다 · 막지 않는다)
create function public.so_tier_warnings(s public.so) returns text[]
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
  if s.intake in ('manual', 'csv') then
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
comment on function public.so_tier_warnings(public.so) is '판정 B ③·④ — price_tier_missing · price_tier_not_for_sale · price_tier_inactive · currency_mismatch(오더 통화 ≠ 티어 통화 · 11-c 이견 2) · direct_order_tier_config_missing(inv_config so_direct_order_tier_code 없음·숫자 아님·표에 없음) · direct_order_tier_unexpected(직접 오더 intake manual·csv 의 티어 code ≠ 설정) · customer_tier_missing · tier_differs_from_customer. 전부 경고 — 막지 않는다. so_create 반환 · so_detail 둘 다';
revoke all on function public.so_tier_warnings(public.so) from public, anon;
grant execute on function public.so_tier_warnings(public.so) to authenticated;        -- so_detail(invoker)이 부른다

-- ═══ 2) so_create — 초안 만들기(⬜1 · ⬜2 · 판정 A · 판정 B ①③) ═══
create function public.so_create(
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
    'ship_to_is_company', v_copy->'ship_to_is_company',
    'warnings',      to_jsonb(v_warn));
end;
$$;
comment on function public.so_create(uuid, text, text, uuid, text) is
  '⭐ SO 초안 만들기(SO 쓰기 ①b · ⬜1·⬜2) — security definer · 첫 줄 ims_require_write(sales). warehouse 채널 · intake manual|csv 만(pos·counter·shopify 는 뒤 차수) · 비활성 손님 거부(판정 A) · 손님 통화 없으면 거부 · so_number 는 so_next_number(). 손님 값은 so_copy_customer(①a)가 굳힌다(티어 = 손님 기본 · 판정 B ①). 반환 warnings = 복사 경고 + so_tier_warnings(direct_order_tier_unexpected 등 · 막지 않는다)';

-- ═══ 3) so_header_update — 머리 고치기(⬜1 · ⬜6 · 판정 B ⑤) ═══
create function public.so_header_update(p_so_id uuid, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_keys  constant text[] := array[
    'customer_id', 'location_id', 'payment_term_id', 'discount_pct', 'tax_rule', 'price_tier',
    'order_date', 'required_by', 'ref', 'comments', 'shipping_notes', 'carrier', 'tracking_number',
    'bill_to_name', 'bill_to_line1', 'bill_to_line2', 'bill_to_city', 'bill_to_state_province', 'bill_to_postal_code', 'bill_to_country',
    'ship_to_company', 'ship_to_contact', 'ship_to_phone', 'ship_to_line1', 'ship_to_line2', 'ship_to_city', 'ship_to_state_province', 'ship_to_postal_code', 'ship_to_country'];
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

  -- 손님 기본 할인 — 0~100 · 이미 들어간 줄의 할인은 따라가지 않는다(넣는 순간 굳힌다 · ⬜5)
  if p_patch ? 'discount_pct' then
    v_disc := nullif(p_patch->>'discount_pct', '')::numeric;
    if v_disc is not null and (v_disc < 0 or v_disc > 100) then
      raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
    end if;
    if v_n_lines > 0 then v_warn := array_append(v_warn, 'lines_keep_prices'); end if;
  end if;

  -- 티어(판정 B ⑤) — 이름으로 받아 purpose sale · 활성만 · 원문 + FK 짝으로 · 들어간 줄의 가격은 그대로(④ 로 보인다)
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
    if v_n_lines > 0 then v_warn := array_append(v_warn, 'lines_keep_prices'); end if;
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
    updated_by         = v_staff
  where s.id = p_so_id and s.status = 'draft'
  returning * into v_so;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order was not saved — it may have been changed by someone else just now — nothing was saved';
  end if;

  v_warn := v_warn || public.so_tier_warnings(v_so);
  return jsonb_build_object('so', to_jsonb(v_so), 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_header_update(uuid, jsonb) is
  '⭐ SO 초안 머리 고치기(①b · ⬜1·⬜6 · 판정 B ⑤) — definer · 첫 줄 ims_require_write(sales) · 초안만. 허락 열쇠 29(customer_id · location_id · payment_term_id · discount_pct · tax_rule · price_tier(이름 · sale 티어만 · 원문+FK) · order_date · required_by · ref · comments · shipping_notes · carrier · tracking_number · bill_to 7 · ship_to 9) · 모르는 열쇠 거부. 손님 바꾸기는 줄·운임이 0일 때만(so_copy_customer 다시). 할인·티어를 바꿔도 들어간 줄 가격은 그대로(warning lines_keep_prices) — 다시 가격 매기기 창구는 없다(⬜5)';

-- ═══ 4) so_line_add — 줄 하나(⬜1 · ⬜5 · 판정 2 · 판정 4) ═══
--   창구 → 할인 식(so_line_quote) → 손으로 준 할인 · 단가(덮어쓰기) → 무상 검사 → 같은 SKU(합치기 · ask) → 넣는 순간 굳힌다
create function public.so_line_add(
  p_so_id        uuid,
  p_product_id   uuid,
  p_qty          numeric,
  p_unit_price   numeric default null,      -- 주면 덮어쓰기(price_override) · 0 = 무상(free_reason 필수)
  p_discount_pct numeric default null,      -- 주면 손님 기본 대신 이 할인(unit_price 와 함께 못 준다)
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
  v_list     numeric;  v_disc numeric;  v_unit numeric;  v_src text;
  v_override boolean := false;
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

  -- 가격 — 창구 + 할인 식 한 곳
  select * into q from public.so_line_quote(v_so, p.id);
  v_list := q.list_price;  v_disc := q.discount_pct;  v_unit := q.unit_price;  v_src := q.price_source;

  if p_discount_pct is not null and p_unit_price is not null then
    raise exception 'Give either a unit price or a discount, not both — nothing was saved';
  end if;
  if p_discount_pct is not null then
    if p_discount_pct < 0 or p_discount_pct > 100 then
      raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
    end if;
    v_disc := p_discount_pct;
    v_unit := case when v_list is null then null else v_list * (1 - v_disc / 100) end;
  end if;
  if p_unit_price is not null then                              -- 덮어쓰기 — list_price 는 남긴다(받았을 금액 · 판정 2) · discount_pct 는 뜻이 없어 null
    if p_unit_price < 0 then
      raise exception 'Unit price cannot be negative — nothing was saved';
    end if;
    v_unit := p_unit_price;  v_override := true;  v_disc := null;
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

  -- 같은 SKU(5-e · ⬜5) — 단가가 같으면(null 끼리도) 수량을 더한다 · 다르면 ask · p_force_new 면 그냥 새 줄
  if not p_force_new then
    select * into v_match from public.so_line l
    where l.so_id = p_so_id and l.product_id = p.id and l.unit_price is not distinct from v_unit
    order by l.line_no limit 1;
    if found then
      update public.so_line set qty_ordered = qty_ordered + p_qty, updated_by = v_staff
      where id = v_match.id returning * into v_line;
      if v_comments is not null then v_warn := array_append(v_warn, 'comments_not_merged'); end if;
      if v_line.unit_price is null then v_warn := array_append(v_warn, 'no_price'); end if;
      return jsonb_build_object('action', 'merged', 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                                'total', public.so_line_total(v_line), 'warnings', to_jsonb(v_warn));
    end if;
    select jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'qty_ordered', l.qty_ordered,
                                        'unit_price', l.unit_price, 'price_override', l.price_override) order by l.line_no)
      into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = p.id;
    if v_others is not null then
      return jsonb_build_object('action', 'ask', 'so_number', v_so.so_number, 'product_id', p.id, 'sku', p.sku,
        'proposed', jsonb_build_object('qty_ordered', p_qty, 'list_price', v_list, 'discount_pct', v_disc, 'unit_price', v_unit, 'price_override', v_override),
        'existing', v_others,
        'message', 'Same SKU is already on this order at a different price — change that line (so_line_update) or add as a new line (p_force_new) — nothing was saved');
    end if;
  end if;

  select coalesce(max(line_no), 0) + 1 into v_next from public.so_line where so_id = p_so_id;
  insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                              list_price, discount_pct, unit_price, price_override, free_reason, tax_rule, comments, updated_by)
  values (p_so_id, v_next, p.id, p.sku, p.name, v_unit_nm, coalesce(p.pack_factor, 1), p_qty,
          v_list, v_disc, v_unit, v_override, v_reason, v_so.tax_rule, v_comments, v_staff)
  returning * into v_line;
  if v_unit is null then v_warn := array_append(v_warn, 'no_price'); end if;

  return jsonb_build_object('action', 'added', 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                            'total', public.so_line_total(v_line), 'price_source', v_src, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_line_add(uuid, uuid, numeric, numeric, numeric, text, text, boolean) is
  '⭐ SO 초안 줄 하나(①b · ⬜1·⬜5 · 판정 2·4) — definer · 첫 줄 ims_require_write(sales) · 초안만 · 비활성 제품 거부. 가격 = so_line_quote(창구 × 손님 할인) · p_discount_pct 는 그 할인 대신 · p_unit_price 는 덮어쓰기(price_override · discount_pct null · list_price 는 남긴다) · 0 원은 free_reason 필수(other 는 comments). 같은 SKU: unit_price is not distinct from 이면 qty 합침(action merged) · 다르면 action ask(줄 안 넣음) · p_force_new 로 새 줄. 넣는 순간 sku·product_name·unit(ref_unit.name → uom_name)·pack_factor(없으면 1)·list_price·discount_pct·unit_price 를 굳힌다 · tax_rule 은 오더(손님) 값';

-- ═══ 5) so_lines_paste — 붙여넣기(⬜1 · po_lines_paste 20260918000000:198 모양 · ⚠️ 같은 SKU 처리가 다르다 — ①a 회신 이견 4) ═══
--   PO 는 붙여넣기 안 중복을 duplicate 로 거부 · SO 는 첫 줄에 수량을 모은 뒤(verdict duplicate = 「위 줄에 합쳤다」) 기존 줄과 대조(merged · ask) — 5-e 규칙
--   판정어 여덟: ok · no_price(넣되 가격 없음) · merged(기존 줄에 수량 더함) · ask(다른 단가 · 안 넣음) · duplicate(붙여넣기 안 같은 SKU · 위 줄에 합침) · not_found · inactive(거부 · PO 와 다르다) · bad_qty
--   commit=false 는 미리 보기(번호만 예약) · 500줄 한도는 예외가 아니라 판정(PO 그대로)
create function public.so_lines_paste(
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
  v_list numeric;  v_disc numeric;  v_unit numeric;  v_src text;
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

  -- 2) 제품별 — 가격 · 기존 줄과 대조 · 넣기(결과는 그 제품의 첫 입력 줄에 적는다)
  for i in 1 .. coalesce(array_length(a_pid, 1), 0) loop
    select * into q from public.so_line_quote(v_so, a_pid[i]);
    v_list := q.list_price;  v_disc := q.discount_pct;  v_unit := q.unit_price;  v_src := q.price_source;
    v_line_no := null; v_inserted := false; v_updated := false; v_msgs := '{}';

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
        v_next := v_next + 1; v_line_no := v_next;
        if p_commit then
          insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                      list_price, discount_pct, unit_price, price_override, free_reason, tax_rule, comments, updated_by)
          values (p_so_id, v_line_no, a_pid[i], a_sku[i], a_name[i], a_unit[i], coalesce(a_pack[i], 1), a_qty[i],
                  v_list, v_disc, v_unit, false, null, v_so.tax_rule, null, v_staff);
          v_inserted := true; n_ins := n_ins + 1;
        end if;
      end if;
    end if;

    v_rows := coalesce((
      select jsonb_agg(
               case when (e->>'n')::int = a_n[i]
                    then e || jsonb_build_object('verdict', v_verdict, 'qty', a_qty[i], 'list_price', v_list, 'discount_pct', v_disc,
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
  '⭐ SO 초안 붙여넣기(①b · ⬜1) — definer · 첫 줄 ims_require_write(sales) · 초안만 · [{sku, qty}] · 500줄 한도는 판정. SKU 는 앞뒤 공백(비분리 포함)만 다듬고 정확 일치 → upper 폴백(case_fixed). 판정어 여덟: ok · no_price · merged · ask · duplicate · not_found · inactive · bad_qty. ⚠️ po_lines_paste 와 다른 곳 — 붙여넣기 안 같은 SKU 는 첫 줄에 수량을 모으고(duplicate) · 기존 줄과 단가가 같으면 더하고(merged) 다르면 ask · 비활성 제품은 거부(inactive). 가격은 so_line_quote · 넣는 순간 굳힌다';

-- ═══ 6) so_line_update — 줄 고치기(⬜1) ═══
--   열쇠 아홉: qty_ordered · unit_price(덮어쓰기 · discount_pct 와 함께 못 준다) · discount_pct(list_price 로 다시 계산 · 덮어쓰기 해제) · free_reason · surcharge_pct · surcharge_amount · surcharge_label · tax_rule · comments
create function public.so_line_update(p_line_id uuid, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_keys   constant text[] := array['qty_ordered', 'unit_price', 'discount_pct', 'free_reason', 'surcharge_pct', 'surcharge_amount', 'surcharge_label', 'tax_rule', 'comments'];
  v_staff  uuid;
  v_line   public.so_line%rowtype;
  v_so     public.so%rowtype;
  v_bad    text;
  v_qty    numeric;  v_unit numeric;  v_disc numeric;  v_override boolean;
  v_reason text;  v_comments text;
  v_spct   numeric;  v_samt numeric;  v_slbl text;
  v_line_no int;
  v_n      int;
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

  -- 가격 — 덮어쓰기 또는 할인 다시 계산 · 둘 다는 못 준다
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
    v_override := true;  v_disc := null;
  elsif p_patch ? 'discount_pct' then
    v_disc := nullif(p_patch->>'discount_pct', '')::numeric;
    if v_disc is not null and (v_disc < 0 or v_disc > 100) then
      raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
    end if;
    if v_disc is null then v_disc := greatest(coalesce(v_so.discount_pct, 0), 0); end if;   -- 비우면 손님 기본으로(so_line_quote 와 같은 식)
    v_unit := case when v_line.list_price is null then null else v_line.list_price * (1 - v_disc / 100) end;
    v_override := false;
  else
    v_unit := v_line.unit_price;  v_disc := v_line.discount_pct;  v_override := v_line.price_override;
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

  return jsonb_build_object('so_number', v_so.so_number, 'line', to_jsonb(v_line), 'total', public.so_line_total(v_line));
end;
$$;
comment on function public.so_line_update(uuid, jsonb) is
  '⭐ SO 초안 줄 고치기(①b · ⬜1) — definer · 첫 줄 ims_require_write(sales) · 초안만 · 열쇠 아홉(qty_ordered · unit_price · discount_pct · free_reason · surcharge_pct · surcharge_amount · surcharge_label · tax_rule · comments) · 모르는 열쇠 거부. unit_price = 덮어쓰기(price_override true · discount_pct null) · discount_pct = list_price 로 다시 계산(덮어쓰기 해제 · 비우면 손님 기본) · 둘 다는 거부. 무상·부가 요금 규칙은 CHECK 앞에서 사람이 읽는 말로 거부';

-- ═══ 7) so_line_remove — 줄 지우기(⬜1) ═══
create function public.so_line_remove(p_line_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_line   public.so_line%rowtype;
  v_so     public.so%rowtype;
  v_n      int;
  v_left   int;
begin
  perform public.ims_require_write('sales', 'deleted');        -- ⭐ 첫 줄
  perform public.so_current_staff();

  select * into v_line from public.so_line where id = p_line_id;
  if not found then
    raise exception 'Order line not found — nothing was deleted';
  end if;
  v_so := public.so_require_draft(v_line.so_id, 'deleted');
  if exists (select 1 from public.so_reserve r where r.so_line_id = p_line_id and r.released_at is null) then
    raise exception 'Line % of % has an open allocation — release it first — nothing was deleted', v_line.line_no, v_so.so_number;
  end if;

  delete from public.so_line where id = p_line_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Line % of % was not deleted — it may have been removed by someone else just now — nothing was deleted', v_line.line_no, v_so.so_number;
  end if;
  select count(*) into v_left from public.so_line where so_id = v_so.id;
  return jsonb_build_object('so_number', v_so.so_number, 'removed_line_no', v_line.line_no, 'lines_left', v_left);
end;
$$;
comment on function public.so_line_remove(uuid) is '⭐ SO 초안 줄 지우기(①b) — definer · 첫 줄 ims_require_write(sales, deleted) · 초안만 · 열린 할당(so_reserve.released_at null)이 있으면 거부(초안엔 없다 — ② 뒤 대비) · 줄 번호는 다시 매기지 않는다';

-- ═══ 8) so_charge_set — 운임·서비스 줄 넣기·고치기(⬜1 · ⚠️ 인자 순서는 ⬜1 안과 다르다 — 기본값 있는 인자는 뒤에만 올 수 있다) ═══
--   p_charge_id 없으면 새 줄(계정 기본 = ref_account.code '_99_' Freight Sales · 20260923133042:30 「화면·RPC 가 code 로 찾아 넣는다」) · 있으면 그 줄을 준 값으로 덮는다(description · tax_rule 은 null 이면 비운다 · 계정은 주면 바꾸고 안 주면 그대로)
create function public.so_charge_set(
  p_so_id       uuid,
  p_name        text,
  p_amount      numeric,
  p_charge_id   uuid default null,
  p_description text default null,
  p_tax_rule    text default null,
  p_account_id  uuid default null
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  v_name   text;
  v_acct   public.ref_account%rowtype;
  v_ch     public.so_charge%rowtype;
  v_next   int;
  v_warn   text[] := '{}';
  v_n      int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  v_name := nullif(trim(p_name), '');
  if v_name is null then
    raise exception 'A charge needs a name — nothing was saved';
  end if;
  if p_amount is null then
    raise exception 'A charge needs an amount — nothing was saved';
  end if;

  if p_account_id is not null then
    select * into v_acct from public.ref_account where id = p_account_id;
    if not found then
      raise exception 'Account not found — nothing was saved';
    end if;
  end if;

  if p_charge_id is null then
    if p_account_id is null then
      select * into v_acct from public.ref_account where code = '_99_';          -- 기본 Freight Sales · 없으면 비우고 알린다(짐작 값을 박지 않는다)
      if not found then v_warn := array_append(v_warn, 'charge_account_unset'); end if;
    end if;
    select coalesce(max(line_no), 0) + 1 into v_next from public.so_charge where so_id = p_so_id;
    insert into public.so_charge (so_id, line_no, name, description, amount, tax_rule, account_id, account_code, updated_by)
    values (p_so_id, v_next, v_name, nullif(trim(p_description), ''), p_amount, nullif(trim(p_tax_rule), ''), v_acct.id, v_acct.code, v_staff)
    returning * into v_ch;
    return jsonb_build_object('action', 'added', 'so_number', v_so.so_number, 'charge', to_jsonb(v_ch), 'warnings', to_jsonb(v_warn));
  end if;

  select * into v_ch from public.so_charge where id = p_charge_id and so_id = p_so_id;
  if not found then
    raise exception 'Charge not found on order % — nothing was saved', v_so.so_number;
  end if;
  update public.so_charge c set
    name         = v_name,
    description  = nullif(trim(p_description), ''),
    amount       = p_amount,
    tax_rule     = nullif(trim(p_tax_rule), ''),
    account_id   = case when p_account_id is not null then v_acct.id   else c.account_id end,
    account_code = case when p_account_id is not null then v_acct.code else c.account_code end,
    updated_by   = v_staff
  where c.id = p_charge_id
  returning * into v_ch;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Charge was not saved — it may have been removed by someone else just now — nothing was saved';
  end if;
  return jsonb_build_object('action', 'updated', 'so_number', v_so.so_number, 'charge', to_jsonb(v_ch), 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid) is
  '⭐ SO 초안 운임·서비스 줄(①b · ⬜1) — definer · 첫 줄 ims_require_write(sales) · 초안만. p_charge_id 없으면 새 줄(line_no max+1 · 계정 기본 ref_account.code _99_ Freight Sales · 없으면 warning charge_account_unset) · 있으면 그 줄을 준 값으로 덮는다(계정은 주면 바꾸고 안 주면 그대로). 이름 필수 · 금액 필수(음수 허용 — CHECK 없음 · 8-c 금액 칸 없음과 무관)';

-- ═══ 9) so_charge_remove ═══
create function public.so_charge_remove(p_charge_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_ch  public.so_charge%rowtype;
  v_so  public.so%rowtype;
  v_n   int;
begin
  perform public.ims_require_write('sales', 'deleted');        -- ⭐ 첫 줄
  perform public.so_current_staff();
  select * into v_ch from public.so_charge where id = p_charge_id;
  if not found then
    raise exception 'Charge not found — nothing was deleted';
  end if;
  v_so := public.so_require_draft(v_ch.so_id, 'deleted');
  delete from public.so_charge where id = p_charge_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Charge was not deleted — it may have been removed by someone else just now — nothing was deleted';
  end if;
  return jsonb_build_object('so_number', v_so.so_number, 'removed_line_no', v_ch.line_no);
end;
$$;
comment on function public.so_charge_remove(uuid) is '⭐ SO 초안 운임·서비스 줄 지우기(①b) — definer · 첫 줄 ims_require_write(sales, deleted) · 초안만';

-- ═══ 10) so_delete — 초안 지우기(⬜1 · 줄·운임 cascade · so_reserve 는 no action — 초안엔 없다) ═══
create function public.so_delete(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_so        public.so%rowtype;
  v_lines     int;
  v_charges   int;
  v_reserves  int;
  v_n         int;
begin
  perform public.ims_require_write('sales', 'deleted');        -- ⭐ 첫 줄
  perform public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'deleted');

  select count(*) into v_reserves from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = p_so_id;
  if v_reserves > 0 then
    raise exception 'Order % has allocations — release them first — nothing was deleted', v_so.so_number;
  end if;
  select count(*) into v_lines   from public.so_line   where so_id = p_so_id;
  select count(*) into v_charges from public.so_charge where so_id = p_so_id;

  delete from public.so where id = p_so_id and status = 'draft';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order % was not deleted — it may have been changed by someone else just now — nothing was deleted', v_so.so_number;
  end if;
  return jsonb_build_object('deleted', v_so.so_number, 'lines', v_lines, 'charges', v_charges);
end;
$$;
comment on function public.so_delete(uuid) is '⭐ SO 초안 지우기(①b) — definer · 첫 줄 ims_require_write(sales, deleted) · 초안만 · 줄·운임은 cascade(거래 표 규약) · so_reserve 가 있으면 거부(초안엔 없다 — ② 뒤 대비). 번호는 되돌아오지 않는다(시퀀스)';

-- ═══ 11) so_detail — 읽기(⬜1 · ①a 회신 이견 8) · security invoker · stable · 화면 셋이 같은 표시를 본다 ═══
create function public.so_detail(p_so_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  v_cust     text;
  v_lines    jsonb;
  v_charges  jsonb;
  v_lines_n  int;  v_no_price int;  v_free int;  v_charges_n int;
  v_lines_total numeric;  v_charges_total numeric;
  v_warn     text[];
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('total', public.so_line_total(l), 'no_price', l.unit_price is null, 'free', l.free_reason is not null) order by l.line_no), '[]'::jsonb),
         count(*), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), coalesce(sum(public.so_line_total(l)), 0)
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

  v_warn := public.so_tier_warnings(v_so);
  if v_lines_n = 0   then v_warn := array_append(v_warn, 'no_lines'); end if;
  if v_no_price > 0  then v_warn := array_append(v_warn, 'lines_without_price'); end if;

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'totals', jsonb_build_object('lines', v_lines_n, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'order_total', v_lines_total + v_charges_total),
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_detail(uuid) is
  '⭐ SO 오더 읽기 한 창구(①b · ⬜1) — invoker · stable(RLS select 그대로 · 로그인만). so · customer_name · lines(+ total · no_price · free) · charges · totals(lines_total = Σ so_line_total · 가격 없는 줄은 0 으로 세지 않고 lines_without_price 로 센다 · order_total = lines_total + charges_total · 세금은 인보이스 차수) · warnings = so_tier_warnings(direct_order_tier_unexpected · tier_differs_from_customer …) + no_lines · lines_without_price. 화면 셋(warehouse · pos · counter)이 다시 짜지 않는다';

-- ═══ 12) 권한 — definer 창구는 기본 EXECUTE(public)를 걷고 authenticated 에만 · 읽기 둘은 invoker ═══
revoke all on function public.so_create(uuid, text, text, uuid, text)                         from public, anon;
revoke all on function public.so_header_update(uuid, jsonb)                                   from public, anon;
revoke all on function public.so_line_add(uuid, uuid, numeric, numeric, numeric, text, text, boolean) from public, anon;
revoke all on function public.so_lines_paste(uuid, jsonb, boolean)                            from public, anon;
revoke all on function public.so_line_update(uuid, jsonb)                                     from public, anon;
revoke all on function public.so_line_remove(uuid)                                            from public, anon;
revoke all on function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid)      from public, anon;
revoke all on function public.so_charge_remove(uuid)                                          from public, anon;
revoke all on function public.so_delete(uuid)                                                 from public, anon;
revoke all on function public.so_detail(uuid)                                                 from public, anon;
grant execute on function public.so_create(uuid, text, text, uuid, text)                         to authenticated;
grant execute on function public.so_header_update(uuid, jsonb)                                   to authenticated;
grant execute on function public.so_line_add(uuid, uuid, numeric, numeric, numeric, text, text, boolean) to authenticated;
grant execute on function public.so_lines_paste(uuid, jsonb, boolean)                            to authenticated;
grant execute on function public.so_line_update(uuid, jsonb)                                     to authenticated;
grant execute on function public.so_line_remove(uuid)                                            to authenticated;
grant execute on function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid)      to authenticated;
grant execute on function public.so_charge_remove(uuid)                                          to authenticated;
grant execute on function public.so_delete(uuid)                                                 to authenticated;
grant execute on function public.so_detail(uuid)                                                 to authenticated;
-- 표 넷의 grant 는 20260923133042 그대로(select 만) — 창구가 소유자 권한으로 쓴다 · so_number_seq 의 authenticated grant 는 남아 있으나 쓰이지 않는다(①a 이견 3)

-- ═══ 검증(Caleb · psql heredoc · 회신에 따로) — 권한 열 개(가짜 A 통과 · B 거부) · 표 직접 쓰기 42501 · 흐름(so_create → so_line_add ×3 → paste → line_update → charge_set → header_update price_tier → so_detail → so_delete) · 거부 넷 · 시퀀스 setval(rollback 밖)
--   기대: 함수 열넷(속 함수 4 + 창구 10) · inv_config 1행 · SO-25000 소비 뒤 setval 25000 · is_called f
