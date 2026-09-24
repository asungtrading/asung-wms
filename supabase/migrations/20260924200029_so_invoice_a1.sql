-- SO 인보이스 ⓐ1 — 인보이스 표 셋 · 시퀀스 60000 · 발행·취소·재발행 · 문지기 짝 둘 · 청구처 칸 · 결제조건 기한 값 (2026-09-24 UTC · 토론토 2026-09-24 오후)
-- 지시서 ~/asung/prompts/so-invoice-1.md · 판정 회신 Caleb 2026-09-24(판정 1~10 · 이견 1~11 ✅ · ⬜1~⬜11 ✅) · 정본 so-module §8(8-a 번호 · 8-c 묶음 · 8-h 취소 경계) · §16(세금 · 판정 5 인보이스 날 세율) · §17 은 차수 끝에
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · ⚠️ ① 이 이름을 못 맞추면 예외로 전체가 되돌아간다(판정 10 「못 맞춘 이름은 멈추고 보고」)
-- 자리: ⓐ = 인보이스(이 차수 ⓐ1 표·발행 / ⓐ2 마무리 창구 so_finalize) → ⓑ 결제·잔액 → ⓒ 크레딧(판정 3) · ⓐ2 가 so_ship 뒤 so_invoice_issue 를 부른다 · 이 차수엔 부르는 창구가 so_invoice_reissue(manager · shipped 오더 다시 발행) 하나
--
-- ① ref_payment_term 값 채우기(판정 10 · 34줄 · 이름 글자 그대로 · 손으로 정한 값 — 파싱이 아니다 · ref_price_tier 이견 8 「판정 값은 마이그레이션이 넣는다」 선례) · 못 맞춘 이름·안 채워진 행이 있으면 예외
-- ② customer.invoice_split_by_store(판정 2 · 우리 칸 · 적재가 보내지 않는다 · 기본 false · 가르는 것은 ⓐ2 so_finalize)
-- ③ so.bill_to_customer_id(이견 5 · FK + 원문 bill_to_name 짝 · 5-d 「손님에서 복사해 굳는 것」) + so_copy_customer 재발행(더한 줄 1)
-- ④ so_status_guard 재발행 — 허락 짝 + 둘(shipped→invoiced · invoiced→shipped 8-h 하향)
-- ⑤ 표 셋 so_invoice · so_invoice_order · so_invoice_line(⬜2 · 거래 표 규약: select 만 · 창구가 쓴다 · 문서→줄 CASCADE · 이력 FK no action) · 시퀀스 so_invoice_number_seq 60000 · so_invoice_next_number()
-- ⑥ so_tax_preview 재발행(drop + create · 인자 p_basis ordered|shipped · 줄·운임 객체에 열쇠 더함 — 발행이 이 식 한 곳을 쓴다 · 이견 4)
-- ⑦ so_invoice_issue(속 함수 · 묶음 하나 → 한 장 · shipped→invoiced) · ⑧ so_invoice_cancel(manager · issued→cancelled · 오더 invoiced→shipped · 번호 재사용 없음) · ⑨ so_invoice_reissue(manager · shipped 오더 → so_invoice_issue)
-- 훑기(회신에 표): ref_payment_term.net_days·discount_days·discount_percent·is_split 를 읽는 자리 — 마이그레이션·화면·js·gs 전부 0(주석만 · ImsRefLoad.gs 는 「2단계에서 사람이 채운다」로 보내지 않는다) ⇒ 값이 채워져도 다른 행동이 바뀌는 곳은 없다
-- 검증: ~/asung/prompts/so-invoice-1a-verify.sql

-- ═══ ① ref_payment_term — 기한 일수 · 조기결제 할인 · 분할 표시(판정 10 · Caleb 「맞아」) ═══
--   ⚠️ 표의 updated_at 트리거는 set_updated_at()(20260911161647 · updated_by 칸 없음) — 다시 만들지 않는다 · 조기결제 할인 칸은 기록만(손님 인보이스에는 기한만 찍는다 · Caleb)
create temp table pt_seed (name text primary key, net_days integer, discount_days integer, discount_percent numeric, is_split boolean not null, note text) on commit drop;
insert into pt_seed (name, net_days, discount_days, discount_percent, is_split, note) values
  ('Net 7',                                 7,  null, null, false, null),
  ('Net7',                                  7,  null, null, false, null),
  ('Net 14',                               14,  null, null, false, null),
  ('Net14',                                14,  null, null, false, null),
  ('Net 15',                               15,  null, null, false, null),
  ('Net15',                                15,  null, null, false, null),
  ('15 days',                              15,  null, null, false, null),
  ('Net 21',                               21,  null, null, false, null),
  ('Net 30',                               30,  null, null, false, null),
  ('Net30',                                30,  null, null, false, null),
  ('30 days',                              30,  null, null, false, null),
  ('Net 45',                               45,  null, null, false, null),
  ('Net45',                                45,  null, null, false, null),
  ('45 days',                              45,  null, null, false, null),
  ('Net 60',                               60,  null, null, false, null),
  ('Net60',                                60,  null, null, false, null),
  ('60 days',                              60,  null, null, false, null),
  ('C.B.S (Cash Before Shipment)',          0,  null, null, false, null),
  ('C.B.S. (Cash Before Shipment)',         0,  null, null, false, null),
  ('C.O.D',                                 0,  null, null, false, null),
  ('Due on receipt',                        0,  null, null, false, null),
  ('2%10 Net30',                           30,    10,    2, false, null),
  ('2% 10 Net 30',                         30,    10,    2, false, null),
  ('2%19 Net30',                           30,    19,    2, false, null),
  ('2.1%13 Net30',                         30,    13,  2.1, false, null),
  ('1%20 Net30',                           30,    20,    1, false, null),
  ('1% 20 Net 30',                         30,    20,    1, false, null),
  ('1%30 Net31',                           31,    30,    1, false, null),
  ('1% 30 Net 31',                         31,    30,    1, false, null),
  ('2%30 Net31',                           31,    30,    2, false, null),
  ('2% Net 30',                            30,  null,    2, false, 'discount days unknown in the name (2% Net 30) — discount_days left null'),
  ('1% Warehouse Allowance + 2%10 Net30',  30,    10,    2, false, '1% warehouse allowance is not an early-payment discount — recorded here only'),
  ('50% COD & 50% N30',                    30,  null, null, true,  'split terms — half on delivery, half Net 30'),
  ('50% COD & 50% Net 30',                 30,  null, null, true,  'split terms — half on delivery, half Net 30');

do $$
declare
  v_missing text;
  v_unfilled text;
  v_n int;
begin
  select string_agg(s.name, ' | ' order by s.name) into v_missing
  from pt_seed s where not exists (select 1 from public.ref_payment_term t where t.name = s.name);
  if v_missing is not null then
    raise exception 'payment term names not found in ref_payment_term (spelling must match the table): % — nothing was applied', v_missing;
  end if;
  update public.ref_payment_term t
     set net_days = s.net_days, discount_days = s.discount_days, discount_percent = s.discount_percent, is_split = s.is_split,
         note = case when s.note is null then t.note else coalesce(t.note || ' · ', '') || s.note || ' (2026-09-24 판정 10)' end
    from pt_seed s where s.name = t.name;
  get diagnostics v_n = row_count;
  if v_n <> 34 then
    raise exception 'expected to fill 34 payment terms, filled % — nothing was applied', v_n;
  end if;
  select string_agg(t.name, ' | ' order by t.name) into v_unfilled from public.ref_payment_term t where t.net_days is null;
  if v_unfilled is not null then
    raise exception 'payment terms still without net_days (add them to the seed): % — nothing was applied', v_unfilled;
  end if;
end;
$$;
comment on column public.ref_payment_term.net_days is '⭐ 최종 기일(일) · so-module §17 판정 10(Caleb 2026-09-24 · 이름을 보고 손으로 정한 값 · 파싱이 아니다 · 34줄 전부 · 비활성 포함 — 손님이 옛 이름 Net30 을 가리킨다) · 인보이스 due_on = issued_on + net_days · 0 = 받을 때(C.B.S · C.O.D · Due on receipt) · ⚠️ Cin7 Duration 은 할인 기한이라 여기 넣지 않는다';
comment on column public.ref_payment_term.is_split is '⭐ 분할 결제 — 「50% COD & 50% N30」 둘 true(판정 10) · 인보이스는 기한을 net_days 로 찍되 경고 split_terms(절반은 받을 때) · 숫자 한 칸으로 안 담기는 조건';

-- ═══ ② customer.invoice_split_by_store — 판정 2 「매장별로 나눈다」 설정(청구처 손님에 둔다) ═══
alter table public.customer add column if not exists invoice_split_by_store boolean not null default false;
comment on column public.customer.invoice_split_by_store is '⭐ 이 손님이 청구처일 때 인보이스를 오더의 손님(매장)별로 따로 낸다(so-module §17 판정 2 · Caleb 「쉽먼트는 하나지만 인보이스는 각 스토어별로」) · 기본 false = 청구처별 한 장(8-c) · 우리 칸 — Cin7 에 없고 ImsLoadCustomer 가 보내지 않는다(고정 키 목록) · 가르는 것은 so_finalize(ⓐ2) · 직원이 마무리 화면에서 바꿀 수 있다 · [실측 2026-09-24] default_bill_to_customer_id 채운 손님 0/9,461 — 지금은 모든 손님이 자기 청구처라 설정 없이도 매장별로 나온다';

-- ═══ ③ so.bill_to_customer_id — 청구처 손님(FK + 원문 bill_to_name 짝 · 이견 5) ═══
alter table public.so add column if not exists bill_to_customer_id uuid references public.customer (id) on delete no action;
create index if not exists so_bill_to_customer_idx on public.so (bill_to_customer_id);
comment on column public.so.bill_to_customer_id is '청구처 손님 FK → customer(id) · 5-d 「손님에서 복사해 굳는 것」 — so_copy_customer 가 coalesce(customer.default_bill_to_customer_id, customer.id) 를 그날 값으로 굳힌다(원문 bill_to_name 과 짝 · 세금 ② 이후 ⓐ1 2026-09-24) · ⭐ 인보이스 묶음의 열쇠(8-c 「같은 청구처」 · so_invoice_issue 가 다른 청구처를 섞으면 거부) · 인덱스 so_bill_to_customer_idx';

-- ═══ ③-b so_copy_customer 재발행 — 마지막 정의 20260924175014:151~299 · 더한 줄 1(bill_to_customer_id = v_bill.id) · 그 밖 바이트 그대로 ═══
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
    bill_to_customer_id      = v_bill.id,                       -- ⓐ1 이견 5 — 청구처 손님(FK) · 원문 bill_to_name 과 짝
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
  '⭐ 손님 값을 초안 오더에 복사해 굳힌다(5-d · SO 쓰기 ①a · ⬜6 공유 — so_create · so_header_update 손님 바꾸기 · 세금 ② · ⓐ1 재발행). 통화·결제조건·할인·티어(원문+id)·계정·창고(비어 있을 때만)·carrier · 청구처 7 + ⭐ bill_to_customer_id(FK · 기본 Billing · §17 이견 5) · 배송지 9(판정 ⑧ · 회사/사람은 so_customer_is_company · 판정 3). ⭐ 세금 규칙은 손님 저장값을 읽지 않고 배송지에서 고른다(so_tax_refresh · §16 판정 2 · manual 은 나라·주가 같으면 그대로 · 판정 7). 초안 아니면 거부 · 손님 통화 없으면 거부 · 그 밖은 warnings 로 알린다(customer_inactive · price_tier_missing/not_for_sale/inactive · currency_mismatch · ship_to_from_billing · ship_to_empty · bill_to_empty · tax_region_unknown · tax_rule_not_linked · tax_rule_reset_by_ship_to). ⚠️ authenticated 는 execute 없음 — ①b definer 창구의 속 함수(직접 부르면 42501)';
revoke all on function public.so_copy_customer(uuid, uuid) from public, anon, authenticated;

-- ═══ ④ so_status_guard 재발행 — 마지막 정의 20260924141140:52~80 · 짝 다섯 → 일곱(shipped→invoiced · invoiced→shipped) · 바뀐 줄 1 + 더한 줄 1 ═══
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
  v_ok := (old.status, new.status) in (('draft','confirmed'), ('confirmed','draft'), ('confirmed','cancelled'), ('draft','cancelled'), ('packed','shipped'),
                                        ('shipped','invoiced'), ('invoiced','shipped'));   -- ⓐ1 2026-09-24: 발행(so_invoice_issue) · 취소 하향(so_invoice_cancel · 8-h)

  if not v_ok then
    raise exception 'Order % cannot move from % to % this way — use the order actions — nothing was saved',
      old.so_number, old.status, new.status;
  end if;
  return new;
end;
$$;
comment on function public.so_status_guard() is
  '⭐ SO 상태 문지기(6-g′ · 12-b 판정 6 · ②a ⬜3 · ③a ⬜5 · ⓐ1) — insert 는 draft 만 · status 가 바뀌는 update 는 허락 짝에 없으면 거부(소유자·definer 창구도 지난다) · 같은 상태의 update 는 통과. 짝 일곱: draft→confirmed · confirmed→draft · confirmed→cancelled · draft→cancelled · packed→shipped(so_ship) · shipped→invoiced(so_invoice_issue) · invoiced→shipped(so_invoice_cancel · 8-h 하향). ④ POS·counter(confirmed→shipped) · ⑤ Release·WMS 사건(at_wms · picking · packed · 내려가는 짝)이 여기에 더한다';

-- ═══ ⑤ 인보이스 표 셋 · 시퀀스(8-a 60000 · 접두어 없음 · 재사용 금지) ═══
create sequence if not exists public.so_invoice_number_seq start with 60000 increment by 1;
create function public.so_invoice_next_number() returns text
  language sql volatile
  set search_path = public, pg_temp
as $$
  select nextval('public.so_invoice_number_seq')::text;
$$;
comment on function public.so_invoice_next_number() is '인보이스 번호 채번(8-a · Caleb 2026-09-22) — 접두어 없음 · 60000 부터(Cin7 최신 49247 · 2026-09-24 BigQuery · 여유 약 10,750) · 손님이 그 번호로 문의한다(6-f 종이 하나). 취소한 번호는 재사용하지 않는다(시퀀스는 되돌리지 않는다 · 빈 번호가 「무슨 일이 있었나」를 말한다). ⚠️ 시퀀스는 롤백되지 않는다 — 검증은 rollback 밖 setval(60000, false) · so_invoice 가 비어 있을 때만';
revoke all on sequence public.so_invoice_number_seq from public, anon, authenticated;     -- definer 창구가 소유자로 쓴다(so_number_seq 의 authenticated grant 는 「남아 있으나 쓰이지 않는다」 · 여기는 처음부터 안 준다)
revoke all on function public.so_invoice_next_number() from public, anon, authenticated;

-- 5-a so_invoice — 머리(손님이 들고 있는 종이 · 그날 값을 굳힌다 · 8-c)
create table if not exists public.so_invoice (
  id                     uuid primary key default gen_random_uuid(),
  invoice_number         text not null unique default public.so_invoice_next_number(),
  status                 text not null default 'issued',
  -- 청구처(그날 값 · 첫 오더의 so.bill_to_* 복사 · 8-c 한 인보이스 = 한 청구처)
  bill_to_customer_id    uuid not null references public.customer (id) on delete no action,
  bill_to_name           text,
  bill_to_line1          text,
  bill_to_line2          text,
  bill_to_city           text,
  bill_to_state_province text,
  bill_to_postal_code    text,
  bill_to_country        text,
  -- 날짜 · 사람 · 결제조건 · 기한(판정 10)
  issued_on              date not null,
  issued_by              uuid references public.ims_staff (id) on delete no action,
  payment_term_id        uuid references public.ref_payment_term (id) on delete no action,
  payment_term_name      text,
  due_on                 date,
  -- 통화 · 합계(굳힌 값 · Σ so_invoice_order)
  currency_id            uuid not null references public.ref_currency (id) on delete no action,
  currency_code          text,
  lines_amount           numeric not null default 0,
  order_discount_amount  numeric not null default 0,
  charges_amount         numeric not null default 0,
  taxable_amount         numeric not null default 0,
  tax_amount             numeric not null default 0,
  total                  numeric not null default 0,
  balance_forward        numeric,                                -- 발행 시점 이월 잔액(8-c) · ⓑ 전에는 null(모르면 비운다 · 0 을 넣지 않는다)
  amount_due             numeric not null default 0,             -- total + coalesce(balance_forward, 0) — 종이에 찍힌 「보내실 금액」
  -- 취소(8-h · manager · 결제·크레딧이 붙기 전에만 — 그 검사는 ⓑ·ⓒ 가 이 함수를 재발행해 더한다)
  cancelled_at           timestamptz,
  cancelled_by           uuid references public.ims_staff (id) on delete no action,
  cancel_note            text,
  note                   text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  updated_by             uuid references public.ims_staff (id) on delete no action,
  constraint so_invoice_number_ck        check (invoice_number ~ '^[0-9]{5,}$'),
  constraint so_invoice_status_ck        check (status in ('issued','cancelled')),
  constraint so_invoice_cancel_ck        check ((status = 'cancelled') = (cancelled_at is not null)),
  constraint so_invoice_cancel_by_ck     check ((cancelled_at is null) = (cancelled_by is null)),
  constraint so_invoice_cancel_note_ck   check ((cancelled_at is null) = (cancel_note is null)),
  constraint so_invoice_taxable_ck       check (taxable_amount = lines_amount + order_discount_amount + charges_amount),
  constraint so_invoice_total_ck         check (total = taxable_amount + tax_amount),
  constraint so_invoice_due_ck           check (amount_due = total + coalesce(balance_forward, 0))
);
create index if not exists so_invoice_bill_to_idx      on public.so_invoice (bill_to_customer_id);
create index if not exists so_invoice_issued_on_idx    on public.so_invoice (issued_on);
create index if not exists so_invoice_issued_by_idx    on public.so_invoice (issued_by);
create index if not exists so_invoice_payment_term_idx on public.so_invoice (payment_term_id);
create index if not exists so_invoice_currency_idx     on public.so_invoice (currency_id);
create index if not exists so_invoice_cancelled_by_idx on public.so_invoice (cancelled_by);
create index if not exists so_invoice_updated_by_idx   on public.so_invoice (updated_by);
comment on table  public.so_invoice is 'SO 인보이스 머리(§8 · §17 ⓐ1 · 2026-09-24) · ⭐ 거래 — 컷오버 때 지운다 · 손님이 들고 있는 종이라 값은 발행 때 굳는다(청구처 7 · 결제조건 · 기한 · 합계) · 상태 issued|cancelled 둘(초안 없음 · 8-c) · 한 인보이스 = 한 청구처 · 한 통화 · 오더 여럿(so_invoice_order) · 오더별 세금은 so_invoice_order · 줄 사본은 so_invoice_line · 쓰기는 창구만(so_invoice_issue · so_invoice_cancel · so_invoice_reissue · 표는 select 만)';
comment on column public.so_invoice.invoice_number  is '번호 · 접두어 없음 · 60000~(so_invoice_next_number · 8-a) · unique · CHECK 숫자 5자리 이상 · ⚠️ 취소해도 번호는 남는다(재사용 금지)';
comment on column public.so_invoice.status          is 'issued · cancelled 둘(8-c 초안 없음) · CHECK 취소 짝 셋(cancelled_at · cancelled_by · cancel_note)';
comment on column public.so_invoice.bill_to_customer_id is '청구처 손님 FK · NOT NULL · 담긴 오더 전부 같은 so.bill_to_customer_id(so_invoice_issue 가 거부) · 주소 7칸은 첫 오더(so_number 순)의 so.bill_to_* 그날 값 · 다르면 경고 bill_to_differs';
comment on column public.so_invoice.issued_on       is '발행일(토론토 · ims_today 기본 · 미래 거부) · ⭐ 세율의 기준(§16 판정 5) · 기한의 기준';
comment on column public.so_invoice.due_on          is '기한 = issued_on + ref_payment_term.net_days(판정 10) · 결제조건 없음·net_days null 이면 null + 경고 due_date_unknown · is_split 이면 net_days 로 찍고 경고 split_terms(절반은 받을 때) · 조기결제 할인 기한은 찍지 않는다(Caleb)';
comment on column public.so_invoice.balance_forward is '발행 시점 이월 잔액(8-c 「그 종이에 찍혀 나간 값」) · ⓑ 결제·잔액 차수 전에는 null(모르면 비운다 · 0 이면 「잔액 0 을 확인했다」로 읽힌다 · Caleb) · ⓑ 가 채우기 시작한다';
comment on column public.so_invoice.amount_due      is '보내실 금액 = total + coalesce(balance_forward, 0) · CHECK so_invoice_due_ck · 굳힌 값';
comment on column public.so_invoice.cancel_note     is '취소 사유(필수 · manager · 8-h 「문서 전체가 틀렸을 때」 · 부분 문제는 크레딧)';

-- 5-b so_invoice_order — 담긴 오더(오더별 세금 규칙·세율·세액 굳힘 · 매장별 배송지가 다른 주라 여기 · 판정 2)
create table if not exists public.so_invoice_order (
  id                      uuid primary key default gen_random_uuid(),
  invoice_id              uuid not null references public.so_invoice (id) on delete cascade,     -- 문서 → 소유 줄
  so_id                   uuid not null references public.so (id) on delete no action,           -- 이력
  so_number               text not null,
  customer_id             uuid references public.customer (id) on delete no action,              -- 오더의 손님(매장 · 청구처와 다를 수 있다)
  ship_to_company         text,
  ship_to_contact         text,
  ship_to_phone           text,
  ship_to_line1           text,
  ship_to_line2           text,
  ship_to_city            text,
  ship_to_state_province  text,
  ship_to_postal_code     text,
  ship_to_country         text,
  -- 세금 굳힘(§16 판정 5 · 발행일 규칙 · manual 이면 오더 규칙)
  tax_rule_id             uuid not null references public.ref_tax_rule (id) on delete no action,
  tax_rule                text not null,
  rate_pct                numeric(7,4) not null,
  tax_source              text not null,
  draft_rule_changed      boolean not null default false,       -- 발행일로 다시 고른 규칙이 초안(so.tax_rule_id)과 달랐다
  -- 금액(이 오더 몫 · 보낸 수량 기준)
  lines_amount            numeric not null default 0,
  order_discount_pct      numeric,
  order_discount_amount   numeric not null default 0,
  charges_amount          numeric not null default 0,
  taxable_amount          numeric not null default 0,
  tax_amount              numeric not null default 0,
  total                   numeric not null default 0,
  cancelled_at            timestamptz,                          -- 머리 취소 때 복사(비정규 · 생성 칸이 다른 표를 못 본다)
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  updated_by              uuid references public.ims_staff (id) on delete no action,
  active_so_id            uuid generated always as (case when cancelled_at is null then so_id end) stored,   -- ⭐ 「오더는 살아 있는 인보이스 하나에만」(규칙 29 · so_reserve.open_line_id 와 같은 장치)
  constraint so_invoice_order_uq          unique (invoice_id, so_id),
  constraint so_invoice_order_active_uq   unique (active_so_id),
  constraint so_invoice_order_source_ck   check (tax_source in ('ship_to','manual')),
  constraint so_invoice_order_rate_ck     check (rate_pct >= 0 and rate_pct <= 100),
  constraint so_invoice_order_taxable_ck  check (taxable_amount = lines_amount + order_discount_amount + charges_amount),
  constraint so_invoice_order_total_ck    check (total = taxable_amount + tax_amount)
);
create index if not exists so_invoice_order_invoice_idx  on public.so_invoice_order (invoice_id);
create index if not exists so_invoice_order_so_idx       on public.so_invoice_order (so_id);
create index if not exists so_invoice_order_customer_idx on public.so_invoice_order (customer_id);
create index if not exists so_invoice_order_tax_rule_idx on public.so_invoice_order (tax_rule_id);
create index if not exists so_invoice_order_updated_by_idx on public.so_invoice_order (updated_by);
comment on table  public.so_invoice_order is 'SO 인보이스가 담는 오더(8-c 하나일 수도 여럿일 수도 · §17 ⓐ1) · ⭐ 거래 · invoice → cascade · so → no action(이력) · ⭐ 오더별 세금 규칙·세율·세액을 굳힌다(매장별 배송지가 다른 주 · §16 판정 5 발행일 규칙 · manual 이면 오더 규칙) · active_so_id 생성 칸 + 유니크 = 「오더는 살아 있는 인보이스 하나에만」 · 취소 때 cancelled_at 이 복사되어 풀린다(다시 발행 가능 · 8-h)';
comment on column public.so_invoice_order.tax_source        is 'ship_to = 발행일(issued_on)로 배송지에서 다시 골랐다 · manual = 오더에서 사람이 정한 규칙(so.tax_rule_manual · §16 판정 7) · draft_rule_changed 는 다시 고른 규칙이 초안 규칙과 달랐다는 표시(세율 개정 사이)';
comment on column public.so_invoice_order.active_so_id      is '생성 칸 — cancelled_at 이 null 이면 so_id · unique ⇒ 한 오더가 살아 있는 인보이스 둘에 못 담긴다(규칙 29 · 부분 유니크 대신)';
comment on column public.so_invoice_order.cancelled_at      is '머리 so_invoice.cancelled_at 의 복사(so_invoice_cancel 이 함께 찍는다) — active_so_id 를 풀기 위한 비정규 칸 · 머리가 정본';

-- 5-c so_invoice_line — 줄 사본(종이의 줄 · 크레딧이 되짚는 열쇠 so_line_id · 8-g)
create table if not exists public.so_invoice_line (
  id                 uuid primary key default gen_random_uuid(),
  invoice_id         uuid not null references public.so_invoice (id) on delete cascade,
  invoice_order_id   uuid not null references public.so_invoice_order (id) on delete cascade,
  line_no            integer not null,
  kind               text not null,                              -- product · charge · order_discount
  so_line_id         uuid references public.so_line (id) on delete no action,      -- product 줄 · 크레딧(8-g)이 되짚는 열쇠
  so_charge_id       uuid references public.so_charge (id) on delete no action,    -- charge 줄
  sku                text,
  description        text,                                        -- product_name · 운임 이름 · 'Order discount N%'
  unit               text,
  pack_factor        numeric,
  qty                numeric,                                     -- 보낸 수량(qty_shipped · 판매 단위) · product 만
  list_price         numeric(18,7),
  discount_pct       numeric,
  discount_source    text,
  unit_price         numeric(18,7),
  amount             numeric not null,                            -- round(qty × unit_price, 2) · 운임 금액 · 오더 전체 할인은 음수
  tax_amount         numeric not null default 0,                  -- so_tax_amount(amount, rate_pct) · 줄마다 반올림(§16 판정 3)
  account_id         uuid references public.ref_account (id) on delete no action,
  account_code       text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  updated_by         uuid references public.ims_staff (id) on delete no action,
  constraint so_invoice_line_no_ck        check (line_no >= 1),
  constraint so_invoice_line_uq           unique (invoice_id, line_no),
  constraint so_invoice_line_kind_ck      check (kind in ('product','charge','order_discount')),
  constraint so_invoice_line_so_line_ck   check ((kind = 'product') = (so_line_id is not null)),
  constraint so_invoice_line_charge_ck    check ((kind = 'charge') = (so_charge_id is not null)),
  constraint so_invoice_line_qty_ck       check ((kind = 'product') = (qty is not null)),
  constraint so_invoice_line_qty_pos_ck   check (qty is null or qty > 0),
  constraint so_invoice_line_amount_ck    check (case when kind = 'order_discount' then amount <= 0 else amount >= 0 end)
);
create index if not exists so_invoice_line_invoice_idx       on public.so_invoice_line (invoice_id);
create index if not exists so_invoice_line_invoice_order_idx on public.so_invoice_line (invoice_order_id);
create index if not exists so_invoice_line_so_line_idx       on public.so_invoice_line (so_line_id);
create index if not exists so_invoice_line_so_charge_idx     on public.so_invoice_line (so_charge_id);
create index if not exists so_invoice_line_account_idx       on public.so_invoice_line (account_id);
create index if not exists so_invoice_line_updated_by_idx    on public.so_invoice_line (updated_by);
comment on table  public.so_invoice_line is 'SO 인보이스 줄 사본(⬜2 · §17 ⓐ1) — 손님이 든 종이의 줄 · so_line 은 뒤에 형제 이동·되돌리기로 바뀔 수 있어 값을 여기 굳힌다 · kind 셋 product(so_line_id 필수 · qty = 보낸 수량) · charge(so_charge_id 필수) · order_discount(음수 한 줄 · D6) · tax_amount 는 줄마다 반올림(§16 판정 3) · 크레딧(8-g credit_line.so_line_id)이 되짚는 열쇠 · 계정은 그날 값(제품 so.sale_account · 운임 so_charge.account)';

create trigger so_invoice_touch       before update on public.so_invoice       for each row execute function public.ims_touch();
create trigger so_invoice_order_touch before update on public.so_invoice_order for each row execute function public.ims_touch();
create trigger so_invoice_line_touch  before update on public.so_invoice_line  for each row execute function public.ims_touch();

alter table public.so_invoice       enable row level security;
alter table public.so_invoice_order enable row level security;
alter table public.so_invoice_line  enable row level security;
create policy so_invoice_select       on public.so_invoice       for select to authenticated using (true);
create policy so_invoice_order_select on public.so_invoice_order for select to authenticated using (true);
create policy so_invoice_line_select  on public.so_invoice_line  for select to authenticated using (true);
revoke all on public.so_invoice       from public, anon, authenticated;
revoke all on public.so_invoice_order from public, anon, authenticated;
revoke all on public.so_invoice_line  from public, anon, authenticated;
grant select on public.so_invoice       to authenticated;
grant select on public.so_invoice_order to authenticated;
grant select on public.so_invoice_line  to authenticated;

-- ═══ ⑥ so_tax_preview 재발행 — 마지막 정의 20260924175014:919~981 · 인자 넷(p_basis ordered|shipped) · 시그니처가 바뀌어 drop + create(so_detail 은 한 인자라 기본값으로 그대로) · 줄·운임 객체에 열쇠 더함(발행이 이 식 한 곳을 쓴다) ═══
drop function public.so_tax_preview(uuid, date, uuid);
create function public.so_tax_preview(p_so_id uuid, p_on date default null, p_rule_id uuid default null, p_basis text default 'ordered') returns jsonb
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
  if p_basis not in ('ordered', 'shipped') then raise exception 'p_basis must be ordered or shipped'; end if;   -- ⓐ1 이견 4 — 인보이스는 보낸 수량(qty_shipped) 기준 · 초안·확정은 주문 수량
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

  select coalesce(jsonb_agg(jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'amount', a.amt, 'tax', public.so_tax_amount(a.amt, v_rate), 'free', l.free_reason is not null,
                                              'line_id', l.id, 'product_id', l.product_id, 'product_name', l.product_name, 'unit', l.unit, 'pack_factor', l.pack_factor,
                                              'qty', a.qty, 'qty_ordered', l.qty_ordered, 'qty_shipped', l.qty_shipped, 'unit_price', l.unit_price, 'list_price', l.list_price,
                                              'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'price_override', l.price_override) order by l.line_no), '[]'::jsonb),
         coalesce(sum(public.so_tax_amount(a.amt, v_rate)), 0), coalesce(sum(a.amt), 0)
    into v_lines, v_lines_tax, v_lines_amt
  from public.so_line l
  cross join lateral (select case when p_basis = 'shipped' then l.qty_shipped else l.qty_ordered end as qty,
                             case when p_basis = 'shipped' then round(l.qty_shipped * l.unit_price, 2) else public.so_line_total(l) end as amt) a   -- ⓐ1: 보낸 수량 기준은 round(qty_shipped × unit_price, 2)(so_line_total 과 같은 식 · 수량만 다르다)
  where l.so_id = p_so_id;

  if coalesce(v_so.order_discount_pct, 0) > 0 then                                  -- 오더 전체 할인은 제품 줄 합계에 한 번(D6 · 운임 제외) · 세금은 그 줄에 따로(판정 3 · SO-10842 −23.12)
    v_od_amt := -round(v_lines_amt * v_so.order_discount_pct / 100, 2);
    v_od_tax := public.so_tax_amount(v_od_amt, v_rate);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('line_no', c.line_no, 'name', c.name, 'amount', c.amount, 'tax', public.so_tax_amount(c.amount, v_rate),
                                              'charge_id', c.id, 'description', c.description, 'account_id', c.account_id, 'account_code', c.account_code) order by c.line_no), '[]'::jsonb),
         coalesce(sum(public.so_tax_amount(c.amount, v_rate)), 0), coalesce(sum(c.amount), 0)
    into v_chg, v_chg_tax, v_chg_amt
  from public.so_charge c where c.so_id = p_so_id;                                  -- 운임도 배송지 주의 규칙 · 줄마다(판정 6)

  return jsonb_build_object(
    'so_number', v_so.so_number, 'on', v_on, 'basis', p_basis, 'source', v_source, 'rule', v_pick,
    'lines', v_lines, 'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'amount', v_od_amt, 'tax', v_od_tax), 'charges', v_chg,
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'lines_tax', v_lines_tax, 'order_discount_amount', v_od_amt, 'order_discount_tax', v_od_tax,
                                 'charges_amount', v_chg_amt, 'charges_tax', v_chg_tax,
                                 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt,
                                 'tax', case when v_rate is null then null else v_lines_tax + v_od_tax + v_chg_tax end,
                                 'total', case when v_rate is null then null else v_lines_amt + v_od_amt + v_chg_amt + v_lines_tax + v_od_tax + v_chg_tax end),
    'warnings', v_warn);
end;
$$;
comment on function public.so_tax_preview(uuid, date, uuid, text) is
  '⭐ 오더 세금 미리 보기(SO 세금 ①·② · ⓐ1 · 판정 3·5·8) — 규칙은 p_rule_id(explicit) → 오더에 고른 so.tax_rule_id(출처 manual|ship_to · 비활성이면 경고 tax_rule_inactive) → 없으면 배송지에서 so_tax_rule_for · 날짜 기본 ims_today(인보이스는 발행일) · ⭐ p_basis ordered(주문 수량 · so_line_total · 초안·확정) | shipped(보낸 수량 · round(qty_shipped × unit_price, 2) · 인보이스 so_invoice_issue) · 제품 줄·오더 전체 할인 줄(−round(Σ × pct/100, 2))·운임 줄마다 so_tax_amount 로 반올림해 더한다 · 줄 객체에 line_id·qty·unit_price 등 · 운임 객체에 charge_id·account · 규칙 없으면 tax null + warnings · 읽기만';
revoke all on function public.so_tax_preview(uuid, date, uuid, text) from public, anon;
grant execute on function public.so_tax_preview(uuid, date, uuid, text) to authenticated;

-- ═══ ⑦ so_invoice_issue — 발행(속 함수 · invoker · authenticated 없음 · 묶음 하나 → 한 장 · ⓐ2 so_finalize · so_invoice_reissue 가 부른다) ═══
--   입력은 이미 갈린 오더들(가르는 것은 부르는 쪽 · 판정 2) · 검사: 전부 shipped ∧ shipped_at · 살아 있는 인보이스에 안 담김 · 같은 청구처 · 같은 통화 → 하나라도 아니면 전체 거부
--   오더마다 규칙: so.tax_rule_manual 이면 so.tax_rule_id · 아니면 so_tax_rule_for(배송지 · issued_on)(§16 판정 5·7) · 다르면 draft_rule_changed · null 이면 거부 · 금액은 so_tax_preview(…, 'shipped') 식 한 곳(줄마다 반올림 · 할인 줄 · 운임)
--   기한: issued_on + net_days · null 이면 null + due_date_unknown · is_split 이면 split_terms(판정 10) · 담긴 오더 shipped → invoiced(문지기 짝) · 번호 nextval(되돌리지 않는다)
create function public.so_invoice_issue(p_so_ids uuid[], p_staff uuid, p_issued_on date default null) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_on       date := coalesce(p_issued_on, public.ims_today());
  v_n        int;
  v_cnt      int;
  v_bad      text;
  v_first    public.so%rowtype;
  v_so       public.so%rowtype;
  v_pt       public.ref_payment_term%rowtype;
  v_inv      public.so_invoice%rowtype;
  v_io       public.so_invoice_order%rowtype;
  v_pick     jsonb;
  v_prev     jsonb;
  v_rule_id  uuid;
  v_changed  boolean;
  v_rule     text;
  v_rate     numeric;
  v_ln       int := 0;
  v_lines_amt numeric := 0;  v_od_amt numeric := 0;  v_chg_amt numeric := 0;  v_tax numeric := 0;
  v_o_lines  numeric;  v_o_od numeric;  v_o_chg numeric;  v_o_tax numeric;
  v_orders   jsonb := '[]'::jsonb;
  v_warn     text[] := '{}';
  e          jsonb;
begin
  if p_staff is null then raise exception 'so_invoice_issue needs the acting staff id — nothing was saved'; end if;
  if v_on > public.ims_today() then raise exception 'Invoice date % is in the future — nothing was saved', v_on; end if;
  v_cnt := coalesce(array_length(p_so_ids, 1), 0);
  if v_cnt = 0 then raise exception 'An invoice needs at least one order — nothing was saved'; end if;
  select count(distinct x) into v_n from unnest(p_so_ids) x;
  if v_n <> v_cnt then raise exception 'The same order is listed twice — nothing was saved'; end if;

  -- 잠금(번호 순) · 존재 · 상태 · 이미 담김 · 청구처 · 통화
  perform s.id from public.so s where s.id = any(p_so_ids) order by s.so_number for update;
  select count(*) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n <> v_cnt then raise exception 'Order not found — nothing was saved'; end if;
  select string_agg(s.so_number || ' (' || s.status || ')', ', ' order by s.so_number) into v_bad
  from public.so s where s.id = any(p_so_ids) and (s.status <> 'shipped' or s.shipped_at is null);
  if v_bad is not null then raise exception 'Only shipped orders can be invoiced — % — nothing was saved', v_bad; end if;
  select string_agg(s.so_number || ' is on invoice ' || i.invoice_number, ', ' order by s.so_number) into v_bad
  from public.so_invoice_order o join public.so s on s.id = o.so_id join public.so_invoice i on i.id = o.invoice_id
  where o.so_id = any(p_so_ids) and o.cancelled_at is null;
  if v_bad is not null then raise exception 'Order already invoiced — % — cancel that invoice first — nothing was saved', v_bad; end if;
  select string_agg(s.so_number, ', ' order by s.so_number) into v_bad from public.so s where s.id = any(p_so_ids) and s.bill_to_customer_id is null;
  if v_bad is not null then raise exception 'Order % has no bill-to customer — nothing was saved', v_bad; end if;
  select count(distinct s.bill_to_customer_id) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One invoice bills one customer — these orders have different bill-to customers, split them — nothing was saved'; end if;
  select count(distinct s.currency_id) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One invoice has one currency — these orders have different currencies, split them — nothing was saved'; end if;

  select * into v_first from public.so s where s.id = any(p_so_ids) order by s.so_number limit 1;

  -- 결제조건 · 기한(판정 10)
  if v_first.payment_term_id is not null then
    select * into v_pt from public.ref_payment_term t where t.id = v_first.payment_term_id;
  end if;
  if v_pt.id is null then
    v_warn := v_warn || array['payment_term_missing', 'due_date_unknown'];
  elsif v_pt.net_days is null then
    v_warn := array_append(v_warn, 'due_date_unknown');
  end if;
  if coalesce(v_pt.is_split, false) then v_warn := array_append(v_warn, 'split_terms'); end if;
  if (select count(distinct coalesce(s.payment_term_id::text, '')) from public.so s where s.id = any(p_so_ids)) > 1 then v_warn := array_append(v_warn, 'payment_term_differs'); end if;
  if exists (select 1 from public.so s where s.id = any(p_so_ids)
              and (s.bill_to_name, s.bill_to_line1, s.bill_to_line2, s.bill_to_city, s.bill_to_state_province, s.bill_to_postal_code, s.bill_to_country)
                  is distinct from (v_first.bill_to_name, v_first.bill_to_line1, v_first.bill_to_line2, v_first.bill_to_city, v_first.bill_to_state_province, v_first.bill_to_postal_code, v_first.bill_to_country)) then
    v_warn := array_append(v_warn, 'bill_to_differs');
  end if;

  -- 머리(합계는 0 으로 넣고 오더를 돌며 채운다 · CHECK 셋은 0 에서도 맞다)
  insert into public.so_invoice (bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_line2, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country,
                                 issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code, updated_by)
  values (v_first.bill_to_customer_id, v_first.bill_to_name, v_first.bill_to_line1, v_first.bill_to_line2, v_first.bill_to_city, v_first.bill_to_state_province, v_first.bill_to_postal_code, v_first.bill_to_country,
          v_on, p_staff, v_pt.id, coalesce(v_pt.name, v_first.payment_term_name), case when v_pt.net_days is not null then v_on + v_pt.net_days end, v_first.currency_id, v_first.currency_code, p_staff)
  returning * into v_inv;

  -- 오더마다 — 규칙 · 금액(식 한 곳 · 보낸 수량) · 담긴 오더 줄 · 줄 사본 · 상태 전이
  for v_so in select * from public.so s where s.id = any(p_so_ids) order by s.so_number loop
    if v_so.tax_rule_manual then
      v_rule_id := v_so.tax_rule_id;
    else
      v_pick := public.so_tax_rule_for(v_so.ship_to_country, v_so.ship_to_state_province, v_on, 'sale');
      v_rule_id := (v_pick->>'rule_id')::uuid;
    end if;
    if v_rule_id is null then
      raise exception 'Order % has no tax rule for its ship-to address on % — pick a tax rule on the order — nothing was saved', v_so.so_number, v_on;
    end if;
    v_changed := v_rule_id is distinct from v_so.tax_rule_id;
    v_prev := public.so_tax_preview(v_so.id, v_on, v_rule_id, 'shipped');          -- explicit 규칙 · 활성 sale 아니면 이 함수가 거부한다
    v_rule := v_prev->'rule'->>'rule';  v_rate := (v_prev->'rule'->>'rate_pct')::numeric;
    v_o_lines := (v_prev->'totals'->>'lines_amount')::numeric;  v_o_od := (v_prev->'totals'->>'order_discount_amount')::numeric;
    v_o_chg   := (v_prev->'totals'->>'charges_amount')::numeric;  v_o_tax := (v_prev->'totals'->>'tax')::numeric;
    if v_o_lines + v_o_od + v_o_chg = 0 and not exists (select 1 from public.so_line l where l.so_id = v_so.id and l.qty_shipped > 0) then
      raise exception 'Order % shipped nothing — there is nothing to invoice — nothing was saved', v_so.so_number;
    end if;

    insert into public.so_invoice_order (invoice_id, so_id, so_number, customer_id,
                                         ship_to_company, ship_to_contact, ship_to_phone, ship_to_line1, ship_to_line2, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country,
                                         tax_rule_id, tax_rule, rate_pct, tax_source, draft_rule_changed,
                                         lines_amount, order_discount_pct, order_discount_amount, charges_amount, taxable_amount, tax_amount, total, updated_by)
    values (v_inv.id, v_so.id, v_so.so_number, v_so.customer_id,
            v_so.ship_to_company, v_so.ship_to_contact, v_so.ship_to_phone, v_so.ship_to_line1, v_so.ship_to_line2, v_so.ship_to_city, v_so.ship_to_state_province, v_so.ship_to_postal_code, v_so.ship_to_country,
            v_rule_id, v_rule, v_rate, case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, v_changed,
            v_o_lines, v_so.order_discount_pct, v_o_od, v_o_chg, v_o_lines + v_o_od + v_o_chg, v_o_tax, v_o_lines + v_o_od + v_o_chg + v_o_tax, p_staff)
    returning * into v_io;

    for e in select x from jsonb_array_elements(v_prev->'lines') x loop                     -- 제품 줄(보낸 수량 > 0 만 · 안 나간 줄은 종이에 없다)
      if (e->>'qty')::numeric > 0 then
        v_ln := v_ln + 1;
        insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, unit, pack_factor, qty, list_price, discount_pct, discount_source, unit_price, amount, tax_amount, account_id, account_code, updated_by)
        values (v_inv.id, v_io.id, v_ln, 'product', (e->>'line_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
                (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, e->>'discount_source', (e->>'unit_price')::numeric, (e->>'amount')::numeric, (e->>'tax')::numeric,
                v_so.sale_account_id, v_so.sale_account_code, p_staff);
      end if;
    end loop;
    if v_o_od <> 0 then                                                                    -- 오더 전체 할인 줄 하나(D6 · 음수 · 세금 따로 · §16 판정 3)
      v_ln := v_ln + 1;
      insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, description, amount, tax_amount, account_id, account_code, updated_by)
      values (v_inv.id, v_io.id, v_ln, 'order_discount', format('Order discount %s%%', v_so.order_discount_pct), v_o_od, (v_prev->'order_discount'->>'tax')::numeric, v_so.sale_account_id, v_so.sale_account_code, p_staff);
    end if;
    for e in select x from jsonb_array_elements(v_prev->'charges') x loop                   -- 운임·서비스 줄 전부(0 도 · 무료 배송 흔적 · 1-p)
      v_ln := v_ln + 1;
      insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, amount, tax_amount, account_id, account_code, updated_by)
      values (v_inv.id, v_io.id, v_ln, 'charge', (e->>'charge_id')::uuid, e->>'name' || coalesce(' — ' || (e->>'description'), ''), (e->>'amount')::numeric, (e->>'tax')::numeric,
              (e->>'account_id')::uuid, e->>'account_code', p_staff);
    end loop;

    v_lines_amt := v_lines_amt + v_o_lines;  v_od_amt := v_od_amt + v_o_od;  v_chg_amt := v_chg_amt + v_o_chg;  v_tax := v_tax + v_o_tax;
    if v_changed then v_warn := array_append(v_warn, 'draft_rule_changed:' || v_so.so_number); end if;
    if coalesce(v_prev->'warnings', '[]'::jsonb) ? 'tax_rule_inactive' then v_warn := array_append(v_warn, 'tax_rule_inactive:' || v_so.so_number); end if;

    update public.so set status = 'invoiced', invoiced_at = now(), updated_by = p_staff where id = v_so.id and status = 'shipped';   -- 문지기 짝 shipped→invoiced
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not invoiced — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'tax_rule', v_rule, 'rate_pct', v_rate,
                                               'tax_source', case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, 'draft_rule_changed', v_changed, 'totals', v_prev->'totals');
  end loop;

  update public.so_invoice set lines_amount = v_lines_amt, order_discount_amount = v_od_amt, charges_amount = v_chg_amt,
                               taxable_amount = v_lines_amt + v_od_amt + v_chg_amt, tax_amount = v_tax, total = v_lines_amt + v_od_amt + v_chg_amt + v_tax,
                               amount_due = v_lines_amt + v_od_amt + v_chg_amt + v_tax + coalesce(balance_forward, 0), updated_by = p_staff
  where id = v_inv.id returning * into v_inv;

  return jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'issued_on', v_on, 'due_on', v_inv.due_on,
                            'bill_to_customer_id', v_inv.bill_to_customer_id, 'bill_to_name', v_inv.bill_to_name, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code,
                            'orders', v_orders, 'lines', v_ln,
                            'totals', jsonb_build_object('lines_amount', v_inv.lines_amount, 'order_discount_amount', v_inv.order_discount_amount, 'charges_amount', v_inv.charges_amount,
                                                         'taxable_amount', v_inv.taxable_amount, 'tax_amount', v_inv.tax_amount, 'total', v_inv.total, 'balance_forward', v_inv.balance_forward, 'amount_due', v_inv.amount_due),
                            'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_invoice_issue(uuid[], uuid, date) is
  '⭐⭐ 인보이스 발행(§8 8-c · §17 ⓐ1 · 2026-09-24) — 속 함수(invoker · authenticated 없음 · so_finalize(ⓐ2) · so_invoice_reissue 가 부른다). 이미 갈린 오더 묶음 하나 → 한 장: 전부 shipped · 살아 있는 인보이스에 안 담김 · 같은 청구처(so.bill_to_customer_id) · 같은 통화 아니면 전체 거부. 오더마다 규칙 = manual 이면 오더 규칙 · 아니면 발행일로 배송지에서 다시(§16 판정 5·7 · draft_rule_changed) · 금액은 so_tax_preview(…, shipped) 식 한 곳(보낸 수량 · 줄마다 반올림 · 할인 줄 · 운임 0 도 줄) · 줄 사본 so_invoice_line · 기한 issued_on + net_days(판정 10 · 경고 due_date_unknown · split_terms) · balance_forward 는 null(ⓑ) · 담긴 오더 shipped→invoiced · 번호는 되돌리지 않는다';
revoke all on function public.so_invoice_issue(uuid[], uuid, date) from public, anon, authenticated;

-- ═══ ⑧ so_invoice_cancel — 취소(창구 · definer · sales + manager · 8-h 「문서 전체가 틀렸을 때」 · 담긴 오더 invoiced→shipped · 번호는 남는다) ═══
create function public.so_invoice_cancel(p_invoice_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_inv   public.so_invoice%rowtype;
  v_note  text;
  v_n     int;
  v_orders int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 인보이스 취소는 manager 이상(6-g · 8-h · 판정 8)
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'A cancel needs a reason (p_note) — nothing was saved'; end if;

  select * into v_inv from public.so_invoice i where i.id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found — nothing was saved'; end if;
  if v_inv.status <> 'issued' then raise exception 'Invoice % is already % — nothing was saved', v_inv.invoice_number, v_inv.status; end if;
  -- ⬜ ⓑ·ⓒ 자리(8-h 「결제·크레딧이 붙기 전에만」): so_payment_alloc · so_credit_applied 표가 서는 차수가 이 함수를 재발행해 「붙었으면 거부」를 여기에 더한다(없는 표를 참조하는 코드는 지금 쓰지 않는다)

  update public.so_invoice set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff, cancel_note = v_note, updated_by = v_staff
  where id = p_invoice_id and status = 'issued';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Invoice % was not cancelled — it may have been changed by someone else just now — nothing was saved', v_inv.invoice_number; end if;
  update public.so_invoice_order set cancelled_at = now(), updated_by = v_staff where invoice_id = p_invoice_id and cancelled_at is null;   -- active_so_id 가 풀린다 → 다시 발행 가능
  get diagnostics v_orders = row_count;
  update public.so s set status = 'shipped', invoiced_at = null, updated_by = v_staff                                                   -- 문지기 짝 invoiced→shipped(8-h 하향)
  from public.so_invoice_order o where o.invoice_id = p_invoice_id and s.id = o.so_id and s.status = 'invoiced';
  get diagnostics v_n = row_count;
  if v_n <> v_orders then raise exception 'Invoice % — % of % orders could not be set back to shipped — nothing was saved', v_inv.invoice_number, v_n, v_orders; end if;

  return jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'status', 'cancelled', 'orders_back_to_shipped', v_orders, 'cancelled_by', v_staff, 'note', v_note);
end;
$$;
comment on function public.so_invoice_cancel(uuid, text) is
  '⭐ 인보이스 취소(6-g · 8-h · §17 ⓐ1) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · issued 만 · 사유 필수 · 문서 전체가 틀렸을 때만(부분 문제는 크레딧 8-h) · 담긴 오더 전부 invoiced→shipped(invoiced_at null) · so_invoice_order.cancelled_at 복사(active_so_id 풀림 → so_invoice_reissue 로 새 번호) · 번호는 남는다(재사용 금지 · 8-a) · ⬜ 결제·크레딧이 붙었으면 거부는 ⓑ·ⓒ 가 재발행해 더한다';
revoke all on function public.so_invoice_cancel(uuid, text) from public, anon;
grant execute on function public.so_invoice_cancel(uuid, text) to authenticated;

-- ═══ ⑨ so_invoice_reissue — 취소된 뒤(또는 마무리 밖에서) shipped 오더를 다시 발행(창구 · definer · sales + manager · 묶음은 인자 그대로) ═══
create function public.so_invoice_reissue(p_so_ids uuid[], p_issued_on date default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 마무리 밖의 발행은 manager 이상(마무리 so_finalize 는 sales · 판정 8)
  v_staff := public.so_current_staff();
  return public.so_invoice_issue(p_so_ids, v_staff, p_issued_on);
end;
$$;
comment on function public.so_invoice_reissue(uuid[], date) is
  '⭐ 다시 발행(8-h 「취소된 인보이스의 오더는 새 번호로 다시」 · §17 ⓐ1 ⬜8) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · shipped 오더 묶음(살아 있는 인보이스 없음 · 같은 청구처·통화)을 so_invoice_issue 로 · 발행일 기본 ims_today · 마무리(so_finalize · sales)와 달리 manager 이상 — 마무리 밖에서 청구서를 내는 길은 좁게';
revoke all on function public.so_invoice_reissue(uuid[], date) from public, anon;
grant execute on function public.so_invoice_reissue(uuid[], date) to authenticated;

-- ═══ 검증(~/asung/prompts/so-invoice-1a-verify.sql · psql -v ON_ERROR_STOP=1 -f · 시퀀스 둘은 rollback 밖 setval) ═══
--   ref_payment_term 34 채움(net_days null 0 · is_split 2 · 표본 값) · 칸 둘 · 표 셋 · 시퀀스 · 함수 넷 · 문지기 일곱 · so_copy_customer 가 bill_to_customer_id 를 채운다 ·
--   같은 청구처 세 오더 packed(replica) → so_ship 셋 → so_invoice_issue → 60000 · 세 오더 invoiced · 합계 = Σ so_tax_preview(shipped) · 기한 = 발행일 + 30(Net 30) · 운임 줄 · 할인 줄 · pick_short 10/12 → 10 × 단가 ·
--   다른 청구처 섞기 거부 · 다시 담기 거부 · shipped 아닌 오더 거부 · 결제조건 없음 → due null + 경고 · split → 경고 · 취소(manager · worker 거부 · 사유 필수) → shipped · 재발행 60001 · 60000 남음 · 권한(authenticated 직접 42501 · 표 insert 42501) · 흔적 0
