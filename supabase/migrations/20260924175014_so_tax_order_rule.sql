-- SO 세금 ② — 오더 하나에 세금 규칙 하나 · so.tax_rule_id + tax_rule_manual · 배송지에서 고른다 · 창구 재발행 (2026-09-24 UTC · 토론토 2026-09-24 오후)
-- 판정(Caleb 2026-09-24 · 말 그대로): 판정 2 손님 저장값(customer.tax_rule)은 계산에 쓰지 않는다 · 판정 7 배송지의 나라·주가 바뀌면 사람이 바꿔 둔 규칙이라도 배송지 규칙으로 되돌린다(경고 tax_rule_reset_by_ship_to · 거리만 바뀌면 그대로) ·
--   판정 8 오더 하나에 규칙 하나 — 제품 줄·운임 줄·오더 전체 할인 줄 전부 그 규칙 · 줄(so_line.tax_rule)·운임(so_charge.tax_rule)은 오더 규칙을 그대로 기록만(초안 동안 따라간다 · 인보이스가 굳힌다) ·
--   판정 9 운임도 오더 규칙 · 운임 줄만 따로 바꾸는 길은 두지 않는다(판정 6 의 「운임 줄마다 사람이 바꿀 수 있다」를 거둔다) · 대화 Claude 안: 규칙을 정할 수 없는 초안은 경고 · so_confirm 이 막는다(R6 · 세금을 모르면 인보이스를 낼 수 없다)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · ⚠️ so 가 비어 있을 때 적용한다(CHECK 둘 — 기존 행이 있으면 tax_rule 원문만 있는 행이 걸린다 · [실측 2026-09-24 세금 ① 검증 끝 so_0])
-- 고르기: 초안의 규칙 = so_tax_rule_for(ship_to_country, ship_to_state_province, ims_today(), 'sale') — 인보이스가 발행일로 다시 고르는 것은 인보이스 차수(판정 5)
--
-- ① so 칸 둘(tax_rule_id FK · tax_rule_manual) · CHECK 둘(FK ⇔ 원문 · manual ⇒ 규칙 있음) · 인덱스 · 주석 다섯(so·so_line·so_charge·customer 의 tax_rule)
-- ② 속 함수 둘(invoker · authenticated 실행 없음 · so_copy_customer 와 같은 자리): so_tax_refresh(배송지로 고르고 줄·운임까지 맞춘다 · manual 은 나라·주가 같으면 그대로 · 바뀌면 되돌리고 경고) · so_tax_set_manual(활성 sale 규칙 이름 → manual)
-- ③ 재발행 여덟(마지막 정의에서 바이트 그대로 · 원본과 diff 는 회신) — so_copy_customer(20260923182231:222 · tax_rule = c.tax_rule 한 줄을 뺀다 · 배송지로 고른다) · so_create(20260923232500:611 · 반환 셋) ·
--   so_header_update(20260923232500:705 · tax_rule 직접 쓰기 한 줄을 빼고 열쇠 tax_rule → set_manual/refresh · ship_to 나라·주 → refresh · 반환 tax) · so_line_update(20260923232500:471 · 열쇠 tax_rule 거부 · 직접 쓰기 한 줄 뺌) ·
--   so_charge_set(20260923192101:14 · p_tax_rule 은 받되 오더 규칙과 다르면 거부 · 저장은 오더 규칙) · so_confirm(20260924145105:212 · R6 세금 규칙 없음 거부) ·
--   so_tax_preview(20260924172351:455 · so.tax_rule_id 를 먼저 · 출처 manual|ship_to) · so_detail(20260923232500:970 · tax 싣기 · totals 세금 · 경고)
-- ④ 훑기(so.tax_rule · so_line.tax_rule · so_charge.tax_rule 을 쓰거나 읽는 자리 · 마지막 정의 기준 · 회신에 표): so_line_add :258 · so_lines_paste :439 는 v_so.tax_rule(= 오더 규칙)을 그대로 굳혀 값이 맞다 → 재발행 안 함 ·
--   so_split(20260924143507:51 · 머리 통째 복사 → tax_rule_id·tax_rule·tax_rule_manual 이 따라온다 · 줄 :78 l.tax_rule) → 형제가 물려받는다 · 무접촉 · so_reprice·so_unconfirm·so_cancel·so_ship·so_hold 는 tax_rule 을 읽지도 쓰지도 않는다(grep 0)
-- 검증: ~/asung/prompts/so-tax-2-verify.sql

-- ═══ ① so 칸 둘 · CHECK 둘 · 인덱스 · 주석 ═══
alter table public.so
  add column if not exists tax_rule_id     uuid references public.ref_tax_rule (id) on delete no action,   -- ⭐ FK + 원문(tax_rule) 짝 · 배송지에서 고른 값(so_tax_refresh) 또는 사람이 정한 값(so_tax_set_manual)
  add column if not exists tax_rule_manual boolean not null default false;                                 -- ⭐ 사람이 바꿨다(판정 2 예외 · 판정 7 배송지 나라·주가 바뀌면 풀린다)
alter table public.so
  add constraint so_tax_rule_pair_ck   check ((tax_rule_id is null) = (tax_rule is null)),
  add constraint so_tax_rule_manual_ck check (not tax_rule_manual or tax_rule_id is not null);
create index if not exists so_tax_rule_idx on public.so (tax_rule_id);
comment on constraint so_tax_rule_pair_ck   on public.so is '세금 ② — FK(tax_rule_id) 와 원문(tax_rule)은 함께 있거나 함께 없다(§10 짝 CHECK) · 둘 다 so_tax_refresh·so_tax_set_manual 만 쓴다';
comment on constraint so_tax_rule_manual_ck on public.so is '세금 ② — 사람이 정한 규칙(manual)은 규칙이 있을 때만 · 규칙을 못 정하면 manual 도 false(판정 7)';
comment on column public.so.tax_rule_id     is '세금 규칙 FK → ref_tax_rule(id) · 세금 ② · 초안: 배송지(ship_to_country · ship_to_state_province)에서 so_tax_rule_for 로 고른다(ims_today · 판정 2) — 배송지 나라·주가 바뀌면 다시(판정 7) · 사람이 바꾸면 tax_rule_manual · null = 규칙을 정할 수 없다(tax_region_unknown · so_confirm 이 막는다) · 인보이스가 발행일로 다시 골라 굳힌다(판정 5 · 인보이스 차수) · 인덱스 so_tax_rule_idx';
comment on column public.so.tax_rule_manual is '사람이 규칙을 바꿨다(so_header_update tax_rule 열쇠 · 판정 2 「예외는 초안에서 사람이 바꾼다」) · true 면 배송지 거리가 바뀌어도 그대로 · ⚠️ 배송지의 나라·주가 바뀌면 배송지 규칙으로 되돌리고 false + 경고 tax_rule_reset_by_ship_to(판정 7) · CHECK so_tax_rule_manual_ck';
comment on column public.so.tax_rule        is '세금 규칙 이름(ref_tax_rule.name 원문 · FK tax_rule_id 와 짝 CHECK so_tax_rule_pair_ck) · 세금 ② — 배송지에서 고른다(판정 2 · 손님 저장값 customer.tax_rule 은 읽지 않는다) · ⭐ 오더 하나에 규칙 하나(판정 8) — 제품 줄·운임 줄·오더 전체 할인 줄이 전부 이 규칙 · so_line.tax_rule·so_charge.tax_rule 은 이것을 기록만(따라간다)';
comment on column public.so_line.tax_rule   is '줄 세금 규칙 원문 — ⭐ 오더 규칙(so.tax_rule)을 기록만(판정 8 · 세금 ②) · 초안 동안 오더 규칙이 바뀌면 so_tax_refresh·so_tax_set_manual 이 함께 맞춘다 · 줄마다 바꾸는 길 없음(so_line_update 열쇠 tax_rule 거부) · 인보이스가 굳힌다';
comment on column public.so_charge.tax_rule is '운임·서비스 줄 세금 규칙 원문 — ⭐ 오더 규칙(so.tax_rule)을 기록만(판정 8·9 · 세금 ②) · so_charge_set 의 p_tax_rule 은 오더 규칙과 다르면 거부(운임 줄만 따로 바꾸는 길은 없다 · 판정 6 의 「운임 줄마다 사람이 바꿀 수 있다」는 거둠) · 인보이스가 굳힌다';
comment on column public.customer.tax_rule  is 'Cin7 TaxRule 원문(예 GST (Sale)) · ⚠️ 계산에 쓰지 않는다 — [실측 2026-09-24] 배송지 주로 판정하면 91% 틀려 있다(HST NB 2016 (Sale) 이 온타리오 손님에게 등) · 오더의 세금은 배송지 주가 정한다(so-module §16 판정 2 · so_tax_refresh) · 기록으로만 두고 재적재가 계속 덮는다 · FK 칸은 만들지 않는다(⬜6 · 쓸 곳이 없다)';

-- ═══ ② 속 함수 둘 — 오더의 세금 규칙을 쓰는 자리는 이 둘만(so 표는 select-only · 창구는 definer) ═══
-- so_tax_refresh — 배송지로 고르고 so + 줄 + 운임을 맞춘다 · p_prev_*: 바뀌기 전 배송지 나라·주(manual 을 지킬지 판정 7) · p_clear_manual: 사람이 「배송지로」 되돌린 것(tax_rule 열쇠 null)
create function public.so_tax_refresh(p_so_id uuid, p_staff uuid, p_prev_country text default null, p_prev_state text default null, p_clear_manual boolean default false) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  g_new      record;
  g_old      record;
  v_pick     jsonb;
  v_new_id   uuid;
  v_new_name text;
  v_warn     jsonb;
  v_reset    boolean := false;
  v_n        int;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found — nothing was saved';
  end if;
  if v_so.status <> 'draft' then
    raise exception 'This order is not a draft (status %) — its tax rule is fixed — nothing was saved', v_so.status;
  end if;

  -- 사람이 정한 규칙(판정 7): 배송지의 나라·주가 같으면 그대로(거리·도시·우편번호만 바뀐 것) · 바뀌었으면 배송지 규칙으로 되돌리고 경고
  if v_so.tax_rule_manual and not p_clear_manual then
    select * into g_new from public.ims_region_from_address(v_so.ship_to_country, v_so.ship_to_state_province);
    select * into g_old from public.ims_region_from_address(p_prev_country, p_prev_state);
    if g_new.country_code is not distinct from g_old.country_code and g_new.region_code is not distinct from g_old.region_code then
      return jsonb_build_object('so_id', p_so_id, 'rule_id', v_so.tax_rule_id, 'rule', v_so.tax_rule, 'manual', true, 'changed', false, 'previous', v_so.tax_rule,
                                'reset_by_ship_to', false, 'warnings', '[]'::jsonb);
    end if;
    v_reset := true;
  end if;

  v_pick     := public.so_tax_rule_for(v_so.ship_to_country, v_so.ship_to_state_province, public.ims_today(), 'sale');
  v_new_id   := (v_pick->>'rule_id')::uuid;
  v_new_name := v_pick->>'rule';
  v_warn     := coalesce(v_pick->'warnings', '[]'::jsonb);
  if v_reset then
    v_warn := v_warn || '["tax_rule_reset_by_ship_to"]'::jsonb;
  end if;

  if v_new_id is distinct from v_so.tax_rule_id or v_new_name is distinct from v_so.tax_rule or v_so.tax_rule_manual then
    update public.so set tax_rule_id = v_new_id, tax_rule = v_new_name, tax_rule_manual = false, updated_by = coalesce(p_staff, updated_by)
    where id = p_so_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then
      raise exception 'Order was not saved — it may have been changed by someone else just now — nothing was saved';
    end if;
  end if;
  -- 줄·운임은 오더 규칙을 기록만(판정 8·9) — 다른 값이 남지 않게 전부 맞춘다
  update public.so_line   set tax_rule = v_new_name, updated_by = coalesce(p_staff, updated_by) where so_id = p_so_id and tax_rule is distinct from v_new_name;
  update public.so_charge set tax_rule = v_new_name, updated_by = coalesce(p_staff, updated_by) where so_id = p_so_id and tax_rule is distinct from v_new_name;

  return jsonb_build_object('so_id', p_so_id, 'rule_id', v_new_id, 'rule', v_new_name, 'rate_pct', v_pick->'rate_pct', 'manual', false,
                            'changed', v_new_id is distinct from v_so.tax_rule_id, 'previous', v_so.tax_rule, 'reset_by_ship_to', v_reset,
                            'region', v_pick->'region', 'warnings', v_warn);
end;
$$;
comment on function public.so_tax_refresh(uuid, uuid, text, text, boolean) is
  'SO 창구 속 함수(세금 ② · 판정 2·7·8) — 초안의 세금 규칙을 배송지(ship_to_country · ship_to_state_province)에서 so_tax_rule_for(ims_today)로 고르고 so.tax_rule_id + tax_rule(manual=false) · 줄·운임의 tax_rule 까지 맞춘다. manual 이었으면 바뀌기 전 배송지(p_prev_*)와 나라·주를 대조 — 같으면 그대로(거리만 바뀐 것) · 다르면 배송지 규칙으로 되돌리고 경고 tax_rule_reset_by_ship_to(previous → rule) · p_clear_manual = 사람이 「배송지로」 되돌린 것. 규칙을 못 정하면 null + 경고(tax_region_unknown · tax_rule_not_linked). so_copy_customer · so_header_update 가 부른다 · authenticated 직접 호출 불가';
revoke all on function public.so_tax_refresh(uuid, uuid, text, text, boolean) from public, anon, authenticated;

-- so_tax_set_manual — 사람이 규칙을 정한다(활성 sale 규칙 이름만) · so + 줄 + 운임
create function public.so_tax_set_manual(p_so_id uuid, p_staff uuid, p_rule_name text) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so    public.so%rowtype;
  r       public.ref_tax_rule%rowtype;
  v_name  text;
  v_n     int;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found — nothing was saved';
  end if;
  if v_so.status <> 'draft' then
    raise exception 'This order is not a draft (status %) — its tax rule is fixed — nothing was saved', v_so.status;
  end if;
  v_name := nullif(trim(p_rule_name), '');
  if v_name is null then
    raise exception 'A tax rule name is needed — or clear it to follow the ship-to province — nothing was saved';
  end if;
  select * into r from public.ref_tax_rule where name = v_name;
  if not found then
    raise exception 'Tax rule % not found — nothing was saved', v_name;
  end if;
  if r.direction <> 'sale' then
    raise exception 'Tax rule % is not a selling rule (direction %) — nothing was saved', r.name, r.direction;
  end if;
  if not r.is_active then
    raise exception 'Tax rule % is inactive — nothing was saved', r.name;
  end if;

  update public.so set tax_rule_id = r.id, tax_rule = r.name, tax_rule_manual = true, updated_by = coalesce(p_staff, updated_by)
  where id = p_so_id and status = 'draft';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order was not saved — it may have been changed by someone else just now — nothing was saved';
  end if;
  update public.so_line   set tax_rule = r.name, updated_by = coalesce(p_staff, updated_by) where so_id = p_so_id and tax_rule is distinct from r.name;
  update public.so_charge set tax_rule = r.name, updated_by = coalesce(p_staff, updated_by) where so_id = p_so_id and tax_rule is distinct from r.name;

  return jsonb_build_object('so_id', p_so_id, 'rule_id', r.id, 'rule', r.name, 'rate_pct', r.rate_pct, 'manual', true,
                            'changed', r.id is distinct from v_so.tax_rule_id, 'previous', v_so.tax_rule, 'reset_by_ship_to', false, 'warnings', '[]'::jsonb);
end;
$$;
comment on function public.so_tax_set_manual(uuid, uuid, text) is
  'SO 창구 속 함수(세금 ② · 판정 2 「예외는 초안에서 사람이 바꾼다」) — 활성 sale 규칙 이름(ref_tax_rule.name 글자 그대로)으로 so.tax_rule_id + tax_rule + tax_rule_manual=true · 줄·운임의 tax_rule 까지 맞춘다 · 없는 이름·purchase/other·비활성은 거부. so_header_update(tax_rule 열쇠 값)가 부른다 · authenticated 직접 호출 불가';
revoke all on function public.so_tax_set_manual(uuid, uuid, text) from public, anon, authenticated;

-- ═══ ③-1 so_copy_customer 재발행 — 마지막 정의 20260923182231:222~361 · create → create or replace · 빠진 줄 1(tax_rule = c.tax_rule · 판정 2 의도) · 더한 줄: 선언 2 · 세금 고르기 4 · 반환 3 ═══
create or replace function public.so_copy_customer(p_so_id uuid, p_customer_id uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so        public.so%rowtype;
  c           public.customer%rowtype;
  v_bill      public.customer%rowtype;           -- 청구처 손님
  v_ship      public.customer%rowtype;           -- 배송 손님(주소 주인)
  v_tier      public.ref_price_tier%rowtype;
  v_ba        public.customer_address%rowtype;   -- 청구 주소
  v_sa        public.customer_address%rowtype;   -- 배송 주소
  v_contact   public.customer_contact%rowtype;   -- 배송 손님의 기본 연락처
  v_company   boolean;
  v_ship_n    integer;
  v_warn      text[] := '{}';
  v_n         integer;
  v_tax       jsonb;                              -- 세금 ② — 배송지에서 고른 규칙
  v_tw        text[];
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found — nothing was saved';
  end if;
  if v_so.status <> 'draft' then
    raise exception 'This order is not a draft (status %) — nothing was saved', v_so.status;
  end if;

  select * into c from public.customer where id = p_customer_id;
  if not found then
    raise exception 'Customer not found — nothing was saved';
  end if;
  if not c.is_active then
    v_warn := array_append(v_warn, 'customer_inactive');
  end if;
  if c.currency_id is null then
    raise exception 'Customer % has no currency — set it on the customer first — nothing was saved', c.name;
  end if;

  -- 티어(⬜3) — 이름 글자 그대로 · id 는 purpose 와 무관하게 남긴다
  if c.price_tier is null then
    v_warn := array_append(v_warn, 'price_tier_missing');
  else
    select * into v_tier from public.ref_price_tier where name = c.price_tier;
    if not found then
      v_warn := array_append(v_warn, 'price_tier_missing');
    else
      if v_tier.purpose <> 'sale' then v_warn := array_append(v_warn, 'price_tier_not_for_sale'); end if;
      if not v_tier.is_active     then v_warn := array_append(v_warn, 'price_tier_inactive');     end if;
      if v_tier.currency_id <> c.currency_id then v_warn := array_append(v_warn, 'currency_mismatch'); end if;
    end if;
  end if;

  -- 청구처 · 배송 손님
  select * into v_bill from public.customer where id = coalesce(c.default_bill_to_customer_id, c.id);
  select * into v_ship from public.customer where id = coalesce(c.default_ship_to_customer_id, c.id);

  -- 청구 주소 — 기본 Billing · 없으면 비움
  select * into v_ba
  from public.customer_address a
  where a.customer_id = v_bill.id and a.type = 'Billing' and a.is_active and a.is_default_for_type
  order by a.created_at limit 1;
  if not found then v_warn := array_append(v_warn, 'bill_to_empty'); end if;

  -- 배송 주소 — 판정 ⑧
  select * into v_sa
  from public.customer_address a
  where a.customer_id = v_ship.id and a.type = 'Shipping' and a.is_active and a.is_default_for_type
  order by a.created_at limit 1;
  if not found then
    select count(*) into v_ship_n from public.customer_address a
    where a.customer_id = v_ship.id and a.type = 'Shipping' and a.is_active;
    if v_ship_n = 0 then
      select * into v_sa
      from public.customer_address a
      where a.customer_id = v_ship.id and a.type = 'Billing' and a.is_active and a.is_default_for_type
      order by a.created_at limit 1;
      if found then
        v_warn := array_append(v_warn, 'ship_to_from_billing');
      else
        v_warn := array_append(v_warn, 'ship_to_empty');
      end if;
    else
      v_warn := array_append(v_warn, 'ship_to_empty');     -- Shipping 여럿 · 기본 없음 → 사람이 고른다
    end if;
  end if;

  -- 배송 손님의 기본 연락처 · 회사/사람(판정 3)
  select * into v_contact
  from public.customer_contact cc
  where cc.customer_id = v_ship.id and cc.is_default and cc.is_active
  order by cc.created_at limit 1;
  v_company := public.so_customer_is_company(v_ship.id);

  update public.so s set
    customer_id        = c.id,
    currency_id        = c.currency_id,
    currency_code      = c.currency_code,
    payment_term_id    = c.payment_term_id,
    payment_term_name  = c.payment_term_name,
    discount_pct       = c.discount_pct,
    price_tier         = c.price_tier,
    price_tier_id      = v_tier.id,
    ar_account_id      = c.ar_account_id,
    ar_account_code    = c.ar_account_code,
    sale_account_id    = c.sale_account_id,
    sale_account_code  = c.sale_account_code,
    location_id        = coalesce(s.location_id, c.default_location_id),
    location_name      = case when s.location_id is null then c.default_location_name else s.location_name end,
    carrier            = c.default_carrier,
    bill_to_name             = v_bill.name,
    bill_to_line1            = v_ba.line1,
    bill_to_line2            = v_ba.line2,
    bill_to_city             = v_ba.city,
    bill_to_state_province   = v_ba.state_province,
    bill_to_postal_code      = v_ba.postal_code,
    bill_to_country          = v_ba.country,
    ship_to_company          = case when v_company then v_ship.name else null end,
    ship_to_contact          = case when v_company then nullif(trim(v_contact.name), '') else v_ship.name end,
    ship_to_phone            = coalesce(nullif(trim(v_contact.phone), ''), nullif(trim(v_contact.mobile_phone), '')),
    ship_to_line1            = v_sa.line1,
    ship_to_line2            = v_sa.line2,
    ship_to_city             = v_sa.city,
    ship_to_state_province   = v_sa.state_province,
    ship_to_postal_code      = v_sa.postal_code,
    ship_to_country          = v_sa.country
  where s.id = p_so_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order not found — nothing was saved';
  end if;

  -- 세금 규칙(세금 ② · 판정 2·7) — 손님 저장값(c.tax_rule)은 읽지 않는다 · 새 배송지에서 고른다 · 사람이 정한 규칙은 나라·주가 같으면 그대로(바뀌기 전 배송지 = v_so)
  v_tax := public.so_tax_refresh(p_so_id, null, v_so.ship_to_country, v_so.ship_to_state_province);
  select array_agg(t.v) into v_tw from jsonb_array_elements_text(v_tax->'warnings') as t(v);
  v_warn := v_warn || coalesce(v_tw, '{}');

  return jsonb_build_object(
    'so_id',            p_so_id,
    'customer_id',      c.id,
    'price_tier_id',    v_tier.id,
    'ship_to_is_company', v_company,
    'tax_rule',         v_tax->'rule',
    'tax_rule_id',      v_tax->'rule_id',
    'tax_rule_manual',  v_tax->'manual',
    'warnings',         to_jsonb(v_warn)
  );
end;
$$;
comment on function public.so_copy_customer(uuid, uuid) is
  '⭐ 손님 값을 초안 오더에 복사해 굳힌다(5-d · SO 쓰기 ①a · ⬜6 공유 — so_create · so_header_update 손님 바꾸기 · 세금 ② 재발행). 통화·결제조건·할인·티어(원문+id)·계정·창고(비어 있을 때만)·carrier · 청구처 7(기본 Billing) · 배송지 9(판정 ⑧: 기본 Shipping → Shipping 0개면 기본 Billing → 비움 · 회사/사람은 so_customer_is_company · 판정 3). ⭐ 세금 규칙은 손님 저장값을 읽지 않고 배송지에서 고른다(so_tax_refresh · §16 판정 2 · manual 은 나라·주가 같으면 그대로 · 판정 7). 초안 아니면 거부 · 손님 통화 없으면 거부 · 그 밖은 warnings 로 알린다(customer_inactive · price_tier_missing/not_for_sale/inactive · currency_mismatch · ship_to_from_billing · ship_to_empty · bill_to_empty · tax_region_unknown · tax_rule_not_linked · tax_rule_reset_by_ship_to). ⚠️ authenticated 는 execute 없음 — ①b definer 창구의 속 함수(직접 부르면 42501)';
revoke all on function public.so_copy_customer(uuid, uuid) from public, anon, authenticated;

-- ═══ ③-2 so_create 재발행 — 마지막 정의 20260923232500:611~697 · 더한 줄 3(반환 tax_rule · tax_rule_id · tax_rule_manual) · 고르기는 so_copy_customer 안에서 ═══
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
    'tax_rule',      v_so.tax_rule,
    'tax_rule_id',   v_so.tax_rule_id,
    'tax_rule_manual', v_so.tax_rule_manual,
    'ship_to_is_company', v_copy->'ship_to_is_company',
    'warnings',      to_jsonb(v_warn));
end;
$$;
comment on function public.so_create(uuid, text, text, uuid, text) is
  '⭐ SO 초안 만들기(SO 쓰기 ①b · 할인 규칙 ②-0b · 세금 ② 재발행) — security definer · 첫 줄 ims_require_write(sales). warehouse 채널 · intake manual|csv 만 · 비활성 손님 거부(판정 A) · 손님 통화 없으면 거부 · so_number 는 so_next_number(). 손님 값은 so_copy_customer(①a)가 굳힌다(티어 = 손님 기본 · 판정 B ① · ⭐ 세금 규칙은 배송지에서 so_tax_refresh · §16 판정 2) · 오더 전체 할인은 so_order_discount 로 찾아 so.order_discount_*(source deal)에 굳힌다(D6 · ⬜4). 반환 + tax_rule · tax_rule_id · tax_rule_manual · warnings = 복사 경고(+ tax_region_unknown 등) + so_tier_warnings(막지 않는다)';

-- ═══ ③-3 so_header_update 재발행 — 마지막 정의 20260923232500:705~887 · 빠진 줄 1(tax_rule 직접 쓰기 · 의도) · 더한 줄: 선언 2 · 이전 배송지 1 · 세금 블록 19 · 반환 tax ═══
--   열쇠 30 그대로(tax_rule 은 남되 뜻이 「활성 sale 규칙 이름 · manual」로 바뀐다 · 같은 패치에 ship_to 와 tax_rule 이 함께 오면 배송지 → 그다음 사람 값(사람 값이 남는다))
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
  v_prev_c text;  v_prev_s text;                              -- 세금 ② — 바뀌기 전 배송지 나라·주(판정 7)
  v_tax   jsonb;  v_tw text[];
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

  v_prev_c := v_so.ship_to_country;  v_prev_s := v_so.ship_to_state_province;     -- 세금 ② — 손님을 바꿨으면 이미 새 손님의 배송지(so_copy_customer 가 그 안에서 골랐다)
  update public.so s set
    location_id        = case when p_patch ? 'location_id'     then v_wh.id   else s.location_id end,
    location_name      = case when p_patch ? 'location_id'     then v_wh.name else s.location_name end,
    payment_term_id    = case when p_patch ? 'payment_term_id' then v_pt.id   else s.payment_term_id end,
    payment_term_name  = case when p_patch ? 'payment_term_id' then v_pt.name else s.payment_term_name end,
    discount_pct       = case when p_patch ? 'discount_pct'    then v_disc    else s.discount_pct end,
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

  -- 세금 규칙(세금 ② · 판정 7·8·9) — 배송지의 나라·주 열쇠가 오면 다시 고른다(manual 이었으면 같은 나라·주는 그대로 · 다르면 되돌리고 경고 tax_rule_reset_by_ship_to) ·
  --   열쇠 tax_rule: 활성 sale 규칙 이름 → manual(so_tax_set_manual) · null → manual 을 풀고 배송지로(so_tax_refresh p_clear_manual) · 줄·운임의 tax_rule 은 두 속 함수가 함께 맞춘다
  if p_patch ? 'ship_to_country' or p_patch ? 'ship_to_state_province' then
    v_tax := public.so_tax_refresh(p_so_id, v_staff, v_prev_c, v_prev_s);
    select array_agg(t.v) into v_tw from jsonb_array_elements_text(v_tax->'warnings') as t(v);
    v_warn := v_warn || coalesce(v_tw, '{}');
  end if;
  if p_patch ? 'tax_rule' then
    if nullif(trim(p_patch->>'tax_rule'), '') is null then
      v_tax := public.so_tax_refresh(p_so_id, v_staff, null, null, true);
    else
      v_tax := public.so_tax_set_manual(p_so_id, v_staff, p_patch->>'tax_rule');
    end if;
    select array_agg(t.v) into v_tw from jsonb_array_elements_text(v_tax->'warnings') as t(v);
    v_warn := v_warn || coalesce(v_tw, '{}');
  end if;
  if v_tax is not null then
    select * into v_so from public.so where id = p_so_id;
  end if;

  if v_reprice then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  v_warn := v_warn || public.so_tier_warnings(v_so);
  return jsonb_build_object('so', to_jsonb(v_so), 'tax', v_tax, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_header_update(uuid, jsonb) is
  '⭐ SO 초안 머리 고치기(①b · 할인 규칙 ②-0b · 세금 ② 재발행 · ⬜4 · 판정 3) — definer · 첫 줄 ims_require_write(sales) · 초안만. 허락 열쇠 30 · 모르는 열쇠 거부. 손님 바꾸기는 줄·운임이 0일 때만(so_copy_customer 가 배송지로 세금 규칙까지 다시). discount_pct · price_tier · order_date 를 바꾸면 들어간 줄은 그대로(lines_keep_prices) + reprice_suggested. 오더 전체 할인: order_discount_pct 값 → manual · null → so_order_discount. ⭐ 세금(§16 판정 7·8·9): ship_to_country·ship_to_state_province 가 오면 so_tax_refresh(나라·주가 같으면 manual 그대로 · 다르면 배송지 규칙 + 경고 tax_rule_reset_by_ship_to) · tax_rule 값 = 활성 sale 규칙 이름 → so_tax_set_manual(manual) · tax_rule null → 배송지로 되돌림 · 줄·운임 tax_rule 은 오더를 따라간다. 반환 + tax{rule_id · rule · manual · changed · previous · reset_by_ship_to · warnings}';

-- ═══ ③-4 so_line_update 재발행 — 마지막 정의 20260923232500:471~606 · 열쇠 아홉 → 여덟(tax_rule 은 거부 문장) · 빠진 줄 1(tax_rule 직접 쓰기 · 의도) · 더한 줄 3 ═══
create or replace function public.so_line_update(p_line_id uuid, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_keys   constant text[] := array['qty_ordered', 'unit_price', 'discount_pct', 'free_reason', 'surcharge_pct', 'surcharge_amount', 'surcharge_label', 'comments'];   -- 세금 ②: tax_rule 은 오더 것(판정 8)
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
  if p_patch ? 'tax_rule' then                                  -- 세금 ② · 판정 8 — 줄마다 바꾸는 길은 없다(모르는 열쇠보다 먼저 · 사람이 읽는 말)
    raise exception 'The tax rule belongs to the order, not to a line — change it on the order (so_header_update tax_rule) — nothing was saved';
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
  '⭐ SO 초안 줄 고치기(①b · 할인 규칙 ②-0b · 세금 ② 재발행) — definer · 첫 줄 ims_require_write(sales) · 초안만 · 열쇠 여덟(qty_ordered · unit_price · discount_pct · free_reason · surcharge_pct · surcharge_amount · surcharge_label · comments) · ⭐ tax_rule 열쇠는 거부(「The tax rule belongs to the order」 · §16 판정 8 — 줄은 오더 규칙을 기록만) · 모르는 열쇠 거부. unit_price = 덮어쓰기(price_override · discount_pct·source null) · discount_pct 값 = 수동 할인(source manual) · discount_pct 비움 = 시스템으로(so_line_quote) · 열쇠 없이 qty 만 바뀌면 시스템 줄은 할인을 다시 매긴다(판정 3) · 사람이 정한 줄은 그대로. 무상·부가 요금 규칙은 CHECK 앞에서 사람이 읽는 말로 거부 · 경고 no_price · deal_ended_before_line_added';

-- ═══ ③-5 so_charge_set 재발행 — 마지막 정의 20260923192101:14~90 · 시그니처 그대로(p_tax_rule 은 남긴다 · 호출자가 깨지지 않게) · 더한 줄 3(오더 규칙과 다르면 거부) · 바뀐 줄 2(저장은 오더 규칙) ═══
create or replace function public.so_charge_set(
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
  if p_amount < 0 then                                          -- ①c 판정(Caleb 2026-09-23) — 돌려줄 돈은 크레딧 노트(8-g) · CHECK so_charge_amount_ck 가 마지막 문
    raise exception 'A charge cannot be negative — use a credit note — nothing was saved';
  end if;
  if nullif(trim(p_tax_rule), '') is not null and nullif(trim(p_tax_rule), '') is distinct from v_so.tax_rule then   -- 세금 ② · 판정 8·9 — 운임 줄만 따로 바꾸는 길은 없다(조용히 무시하지 않고 거부)
    raise exception 'Freight and charges follow the order tax rule (%) — change it on the order, not on the charge — nothing was saved', coalesce(v_so.tax_rule, 'none yet');
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
    values (p_so_id, v_next, v_name, nullif(trim(p_description), ''), p_amount, v_so.tax_rule, v_acct.id, v_acct.code, v_staff)   -- 세금 ②: 오더 규칙을 기록
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
    tax_rule     = v_so.tax_rule,                             -- 세금 ②: 오더 규칙을 기록
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
  '⭐ SO 초안 운임·서비스 줄(①b·①c · 세금 ② 재발행) — definer · 첫 줄 ims_require_write(sales) · 초안만 · p_charge_id 없으면 새 줄(계정 기본 _99_ Freight Sales · 없으면 경고 charge_account_unset) · 있으면 고침 · 이름 필수 · 금액 필수 · 음수 거부(크레딧 노트 · ①c). ⭐ 세금(§16 판정 8·9): 운임도 오더 규칙 — p_tax_rule 은 받되 오더 규칙과 다르면 거부(「Freight and charges follow the order tax rule」) · 저장은 늘 so.tax_rule · 운임 줄만 따로 바꾸는 길은 없다';

-- ═══ ③-6 so_confirm 재발행 — 마지막 정의 20260924145105:212~288 · 더한 줄 3(R6 세금 규칙 없음 거부) ═══
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

  -- R6 막는 조건 — 손님 · 창고 · 줄
  select * into c from public.customer where id = v_so.customer_id;
  if not found or not c.is_active then
    raise exception 'Customer % is inactive — reactivate it first — nothing was saved', coalesce(c.name, '?');
  end if;
  if v_so.location_id is null then
    raise exception 'Order % has no warehouse — set one before confirming — nothing was saved', v_so.so_number;
  end if;
  select * into v_wh from public.ref_warehouse where id = v_so.location_id;
  if not found or not v_wh.is_active then                       -- IN_TRANSIT 은 is_active=false 로 들어 있어 여기서 걸린다(이견 11)
    raise exception 'Warehouse % is inactive — pick an active warehouse — nothing was saved', coalesce(v_wh.name, '?');
  end if;
  select count(*) into v_n from public.so_line where so_id = p_so_id;
  if v_n = 0 then
    raise exception 'Order % has no lines — nothing was saved', v_so.so_number;
  end if;
  select string_agg(l.sku, ', ' order by l.line_no) into v_bad from public.so_line l where l.so_id = p_so_id and l.unit_price is null;
  if v_bad is not null then
    raise exception 'Order % has lines without a price (%) — give them a price first — nothing was saved', v_so.so_number, v_bad;
  end if;
  select string_agg(l.sku, ', ' order by l.line_no) into v_bad
  from public.so_line l join public.product p on p.id = l.product_id where l.so_id = p_so_id and not p.is_active;
  if v_bad is not null then
    raise exception 'Order % has inactive products (%) — remove them first — nothing was saved', v_so.so_number, v_bad;
  end if;
  if v_so.tax_rule_id is null then                              -- 세금 ② R6 — 세금을 모르면 인보이스를 낼 수 없다(가격 없는 줄과 같은 이유) · 배송지 주를 채우거나 tax_rule 을 고른다
    raise exception 'Order % has no tax rule — set the ship-to province (or pick a tax rule) first — nothing was saved', v_so.so_number;
  end if;
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
  '⭐ SO 확정(②a · R1·R2·R3·R5·R6 · 6-d · 세금 ② 재발행) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · draft 만 · warehouse 채널만(pos·counter 는 ④). 막는 것: 비활성 손님 · 창고 없음/비활성(IN_TRANSIT 포함) · 줄 없음 · 가격 없는 줄 · 비활성 제품 · ⭐ 세금 규칙 없음(so.tax_rule_id null · §16 — 배송지 주를 채우거나 tax_rule 을 고른다) · 오더 밖 프리오더 줄 · hold 와 preorder 동시. 경고: 티어·통화 · reprice_suggested · deal_ended_before_line_added. 엔진 so_allocate_run: 잡을 수 있는 만큼 잡고 모자란 몫은 백오더 형제(a) · 프리오더 줄은 형제(b) · 원래는 가장 앞선 무리를 지킨다(빈 문서 없음) · p_hold = 오더 전체 보류로 확정(재고 안 잡음 · 안 나눔) · p_commit false = 미리 보기 · commit 이면 열린 백오더 이어받기(③b). 반환 {so_number · status · committed · keeps · lines[] · siblings[] · superseded · warnings}';

-- ═══ ③-7 so_tax_preview 재발행 — 마지막 정의 20260924172351:455~511 · create → create or replace · 더한 줄 7(so.tax_rule_id 를 먼저 · 출처 manual|ship_to · 비활성 경고) ═══
create or replace function public.so_tax_preview(p_so_id uuid, p_on date default null, p_rule_id uuid default null) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so     public.so%rowtype;
  v_on     date := coalesce(p_on, public.ims_today());
  v_pick   jsonb;
  v_rate   numeric;
  v_rule   text;
  v_source text;
  v_active boolean;                                           -- 세금 ② — 오더에 굳은 규칙이 비활성이 됐나
  v_lines  jsonb;  v_lines_tax numeric;  v_lines_amt numeric;
  v_chg    jsonb;  v_chg_tax numeric;    v_chg_amt numeric;
  v_od_amt numeric := 0;  v_od_tax numeric := 0;
  v_warn   jsonb := '[]'::jsonb;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found'; end if;

  if p_rule_id is not null then
    select r.name, r.rate_pct into v_rule, v_rate from public.ref_tax_rule r where r.id = p_rule_id and r.is_active and r.direction = 'sale';
    if v_rule is null then raise exception 'Tax rule % is not an active selling rule', p_rule_id; end if;
    v_source := 'explicit';
    v_pick := jsonb_build_object('rule_id', p_rule_id, 'rule', v_rule, 'rate_pct', v_rate, 'on', v_on);
  elsif v_so.tax_rule_id is not null then                                              -- 세금 ② — 오더에 고른 규칙을 먼저(배송지에서 고른 것 ship_to · 사람이 정한 것 manual · 판정 8)
    select r.name, r.rate_pct, r.is_active into v_rule, v_rate, v_active from public.ref_tax_rule r where r.id = v_so.tax_rule_id;
    v_source := case when v_so.tax_rule_manual then 'manual' else 'ship_to' end;
    v_pick := jsonb_build_object('rule_id', v_so.tax_rule_id, 'rule', v_rule, 'rate_pct', v_rate, 'on', v_on, 'manual', v_so.tax_rule_manual);
    if not v_active then v_warn := '["tax_rule_inactive"]'::jsonb; end if;
  else                                                                                 -- 규칙이 없는 초안(배송지 모름) — 지금 배송지로 다시 골라 보고 경고를 그대로 낸다
    v_pick := public.so_tax_rule_for(v_so.ship_to_country, v_so.ship_to_state_province, v_on, 'sale');
    v_rate := (v_pick->>'rate_pct')::numeric;  v_rule := v_pick->>'rule';
    v_source := 'ship_to';
    v_warn := coalesce(v_pick->'warnings', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'amount', public.so_line_total(l), 'tax', public.so_tax_amount(public.so_line_total(l), v_rate), 'free', l.free_reason is not null) order by l.line_no), '[]'::jsonb),
         coalesce(sum(public.so_tax_amount(public.so_line_total(l), v_rate)), 0), coalesce(sum(public.so_line_total(l)), 0)
    into v_lines, v_lines_tax, v_lines_amt
  from public.so_line l where l.so_id = p_so_id;

  if coalesce(v_so.order_discount_pct, 0) > 0 then                                  -- 오더 전체 할인은 제품 줄 합계에 한 번(D6 · 운임 제외) · 세금은 그 줄에 따로(판정 3 · SO-10842 −23.12)
    v_od_amt := -round(v_lines_amt * v_so.order_discount_pct / 100, 2);
    v_od_tax := public.so_tax_amount(v_od_amt, v_rate);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('line_no', c.line_no, 'name', c.name, 'amount', c.amount, 'tax', public.so_tax_amount(c.amount, v_rate)) order by c.line_no), '[]'::jsonb),
         coalesce(sum(public.so_tax_amount(c.amount, v_rate)), 0), coalesce(sum(c.amount), 0)
    into v_chg, v_chg_tax, v_chg_amt
  from public.so_charge c where c.so_id = p_so_id;                                  -- 운임도 배송지 주의 규칙 · 줄마다(판정 6)

  return jsonb_build_object(
    'so_number', v_so.so_number, 'on', v_on, 'source', v_source, 'rule', v_pick,
    'lines', v_lines, 'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'amount', v_od_amt, 'tax', v_od_tax), 'charges', v_chg,
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'lines_tax', v_lines_tax, 'order_discount_amount', v_od_amt, 'order_discount_tax', v_od_tax,
                                 'charges_amount', v_chg_amt, 'charges_tax', v_chg_tax,
                                 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt,
                                 'tax', case when v_rate is null then null else v_lines_tax + v_od_tax + v_chg_tax end,
                                 'total', case when v_rate is null then null else v_lines_amt + v_od_amt + v_chg_amt + v_lines_tax + v_od_tax + v_chg_tax end),
    'warnings', v_warn);
end;
$$;
comment on function public.so_tax_preview(uuid, date, uuid) is
  '⭐ 오더 세금 미리 보기(SO 세금 ①·② · 판정 3·5·8) — 규칙은 p_rule_id(explicit) → 오더에 고른 so.tax_rule_id(출처 manual|ship_to · 비활성이면 경고 tax_rule_inactive) → 없으면 배송지에서 so_tax_rule_for(경고 tax_region_unknown 등) · 날짜 기본 ims_today(인보이스는 발행일) · 제품 줄(so_line_total)·오더 전체 할인 줄(−round(Σ × pct/100, 2))·운임 줄마다 so_tax_amount 로 반올림해 더한다 · 규칙 없으면 tax null + warnings · 읽기만(굳히는 것은 인보이스)';
revoke all on function public.so_tax_preview(uuid, date, uuid) from public, anon;
grant execute on function public.so_tax_preview(uuid, date, uuid) to authenticated;

-- ═══ ③-8 so_detail 재발행 — 마지막 정의 20260923232500:970~1021 · 더한 줄: 선언 1 · 세금 5 · totals 2 · tax 1 ═══
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

  -- 세금(세금 ② · 판정 8) — 오더에 고른 규칙(manual|ship_to)으로 줄마다 · 규칙 없으면 tax null + 경고 tax_rule_missing
  v_tax := public.so_tax_preview(p_so_id);

  v_warn := public.so_tier_warnings(v_so);
  if v_so.tax_rule_id is null then v_warn := array_append(v_warn, 'tax_rule_missing'); end if;
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
    'totals', jsonb_build_object('lines', v_lines_n, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt,
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'order_total', v_lines_total - v_od_amt + v_charges_total,
                                 'tax_rule', v_so.tax_rule, 'tax_rule_source', v_tax->>'source', 'tax', v_tax->'totals'->'tax',
                                 'order_total_with_tax', case when v_tax->'totals'->>'tax' is null then null else v_lines_total - v_od_amt + v_charges_total + (v_tax->'totals'->>'tax')::numeric end),
    'tax', v_tax,
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_detail(uuid) is
  '⭐ SO 오더 읽기 한 창구(①b · 할인 규칙 ②-0b · 세금 ② 재발행) — invoker · stable(RLS select 그대로 · 로그인만). so · customer_name · lines(+ total · no_price · free · deal_ended) · charges · totals(lines_total · order_discount_amount · lines_after_discount · charges_total · order_total — 운임은 할인 기준에 없다(D6) · ⭐ tax_rule · tax_rule_source manual|ship_to · tax(줄마다 반올림 Σ · 규칙 없으면 null) · order_total_with_tax) · tax = so_tax_preview 전체(줄마다 세금 · 오더 전체 할인 줄 · 운임 줄) · warnings = so_tier_warnings + tax_rule_missing · tax_region_unknown · tax_rule_not_linked · tax_rule_inactive + no_lines · lines_without_price · deal_ended_before_line_added · reprice_suggested. 화면 셋이 다시 짜지 않는다';

-- ═══ 검증(~/asung/prompts/so-tax-2-verify.sql · psql -v ON_ERROR_STOP=1 -f · 시퀀스는 rollback 밖 setval) ═══
--   칸 둘 · CHECK 둘 · 인덱스 · 함수 둘 신설 · 재발행 여덟 · 온타리오 손님(customer.tax_rule = HST NB 2016 (Sale)) 초안 → HST ON · 줄·운임이 따라감 · 운임에 다른 규칙 거부 · 줄 tax_rule 열쇠 거부 ·
--   AB → GST · Exempt manual · 거리만 → 그대로 · QC → GST + tax_rule_reset_by_ship_to + manual false · tax_rule null → 배송지로 · 비활성·purchase·없는 이름 거부 · 주 모름 → null + 경고 · 확정 거부 · so_split 형제 물려받음 · so_detail 세금 · 권한 · 흔적 0
