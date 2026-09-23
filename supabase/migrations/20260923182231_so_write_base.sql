-- SO 쓰기 ①a — 바탕: 권한(sales) · so/so_line 표 보정 · 상태 문지기 · 가격 창구 · 손님 값 복사
-- 지시서 ~/asung/prompts/so-write-1-draft.md · 판정 Caleb 2026-09-23 (①a = A·B·C·D + so_copy_customer · ①b = 창구 열 개는 다음 차수)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
--
-- A 권한   ims_perm_catalog 에 screen 'sales'(room ims) · customer_address · customer_contact 쓰기 정책 여섯 = sales OR master
--          customer 머리(티어 · 할인 · 결제조건 · 통화 · 계정)는 master 그대로(판정 1)
-- B 표 보정 so.price_tier_id FK(⬜3) · so_line.unit_price nullable · 기본값 없음(판정 2 「가격 없음」 = null)
--          so_line.free_reason + CHECK 넷(sample · promotion · replacement · other) · 짝 CHECK 셋(판정 2 · ⬜7 · 판정 7)
-- C 문지기  so_status_guard() — insert 는 draft 만 · update 로 status 가 바뀌면 전부 거부(허락 짝 0개 · 판정 6 · 이견 9)
-- D 창구   so_price_for(product_id, tier_id) · so_line_total(so_line) · so_customer_is_company(customer_id) · so_copy_customer(so_id, customer_id)
--
-- ⚠️ 표 넷은 여전히 읽기만(select 정책 · select grant · 20260923133042 355~362) — 쓰기는 ①b 의 security definer 창구가 한다(판정 5).
--    so_copy_customer 는 그 창구가 부르는 속 함수 — authenticated 에서 execute 를 뺀다(직접 부르면 42501 · 부르는 창구가 소유자 권한으로 돈다).
-- ⚠️ 다시 만들지 않은 것: ims_touch() 20260918133858:41 · ims_can_write() 20260918020000:99 · ims_require_write() 20260918010000:18
-- ⚠️ 정본 §12(신설 예정) — 회사/사람 규칙 넷(판정 3) · so_number_seq authenticated grant 는 「남아 있으나 쓰이지 않는다」(이견 3)

-- ═══ A) 권한 — screen 'sales' ═══
-- 마지막 정의 20260918165934:18 의 literal 에 sales 한 줄만 더한다(immutable literal — 다른 길 없음).
create or replace function public.ims_perm_catalog() returns jsonb
  language sql immutable
  set search_path = public, pg_temp
as $$
  select '{
    "modes": ["wms", "ims"],
    "screens": {
      "purchasing": {"room": "ims", "label": "Purchase orders, invoices, charges, payments"},
      "master":     {"room": "ims", "label": "Settings, suppliers, products, families, supplier products, prices"},
      "receiving":  {"room": "ims", "label": "Receiving and putaway"},
      "staff":      {"room": "ims", "label": "Adding and editing people (below your own rank)"},
      "sales":      {"room": "ims", "label": "Sales orders, customer addresses and contacts"}
    }
  }'::jsonb;
$$;
comment on function public.ims_perm_catalog() is
  'perms 의 알려진 값 한 곳 — modes 둘 · screens 다섯(room 은 그 화면이 속한 방). ims_can_* 가 모르는 값을 false 로 답하는 근거 · perms 편집 UI(staff.html)의 선택지. 화면이 늘면 여기만 바꾼다(2026-09-17). ⭐ 2026-09-18 receiving.room wms→ims. ⭐ 2026-09-23 sales 추가(SO 쓰기 ①a · 판정 1) — 오더 쓰기 + 손님 주소·연락처 쓰기(sales OR master) · 손님 머리는 master 만. master 라벨에 prices 를 덧붙였다(product_price · ref_price_tier 가 master 묶음 · 20260923154749)';

-- 손님 주소 · 연락처 쓰기 정책 여섯 — 20260922201223 217~223 의 master 만 → sales OR master (drop + create · 선례 20260918020000 ims_staff 정책)
drop policy if exists customer_address_insert on public.customer_address;
drop policy if exists customer_address_update on public.customer_address;
drop policy if exists customer_address_delete on public.customer_address;
drop policy if exists customer_contact_insert on public.customer_contact;
drop policy if exists customer_contact_update on public.customer_contact;
drop policy if exists customer_contact_delete on public.customer_contact;

create policy customer_address_insert on public.customer_address for insert to authenticated
  with check ((select public.ims_can_write('sales')) or (select public.ims_can_write('master')));
create policy customer_address_update on public.customer_address for update to authenticated
  using      ((select public.ims_can_write('sales')) or (select public.ims_can_write('master')))
  with check ((select public.ims_can_write('sales')) or (select public.ims_can_write('master')));
create policy customer_address_delete on public.customer_address for delete to authenticated
  using      ((select public.ims_can_write('sales')) or (select public.ims_can_write('master')));
create policy customer_contact_insert on public.customer_contact for insert to authenticated
  with check ((select public.ims_can_write('sales')) or (select public.ims_can_write('master')));
create policy customer_contact_update on public.customer_contact for update to authenticated
  using      ((select public.ims_can_write('sales')) or (select public.ims_can_write('master')))
  with check ((select public.ims_can_write('sales')) or (select public.ims_can_write('master')));
create policy customer_contact_delete on public.customer_contact for delete to authenticated
  using      ((select public.ims_can_write('sales')) or (select public.ims_can_write('master')));
-- customer(머리) 정책 · product_price · ref_price_tier 정책은 건드리지 않는다 — master 그대로.

-- ═══ B) 표 보정 ═══
-- B-1 so.price_tier_id — 티어를 찾는 길(⬜3) · 원문 so.price_tier 는 그대로 공존 · FK on delete no action · 인덱스 규약 <표>_<칸>_idx
alter table public.so
  add column if not exists price_tier_id uuid references public.ref_price_tier (id) on delete no action;
create index if not exists so_price_tier_idx on public.so (price_tier_id);
comment on column public.so.price_tier_id is
  '⭐ 가격을 찾는 티어(→ ref_price_tier · ⬜3 · SO 쓰기 ①a). so_copy_customer 가 customer.price_tier 원문 = ref_price_tier.name 글자 그대로로 찾아 넣는다(11-e unmatched 0) · 못 찾으면 null(가격 없음). purpose 가 sale 이 아니어도 id 는 남긴다 — 어떤 티어가 붙어 있었는지 남아야 고칠 수 있다 · 가격 창구(so_price_for)가 그때 null 을 낸다. 원문 price_tier 는 그대로(둘이 공존 · customer 쪽 FK 칸은 재적재 차수)';

-- B-2 so_line.unit_price — 「가격 없음」 = null(판정 2). CHECK so_line_unit_price_ck(unit_price >= 0) 는 그대로 — null 을 통과시킨다(§10 머리)
alter table public.so_line alter column unit_price drop not null;
alter table public.so_line alter column unit_price drop default;
comment on column public.so_line.unit_price is
  '⭐ 할인 뒤 단가(판매 단위) — 자르지 않는다(numeric(18,7) · 판정 3). null = 가격 없음(티어 없음 · 가격 줄 없음 · 판정 2) — 줄은 서되 확정(②)이 막는다. 0 = 무상(free goods) — 사람이 직접 넣는다 · price_override true · free_reason 필수(so_line_free_pair_ck). 줄 합계는 so_line_total() 하나';

-- B-3 so_line.free_reason — 무상 사유(판정 2) · CHECK 넷 · 짝 CHECK 둘(§10 머리 null 규칙 — 양쪽이 null 이 될 수 없게)
alter table public.so_line add column if not exists free_reason text;
alter table public.so_line
  add constraint so_line_free_reason_ck    check (free_reason is null or free_reason in ('sample','promotion','replacement','other')),
  add constraint so_line_free_pair_ck      check ((free_reason is not null) = (unit_price is not distinct from 0)),
  add constraint so_line_free_other_ck     check (free_reason is distinct from 'other' or comments is not null),
  -- 판정 7 — 부가 요금 이름 ↔ 값 짝 · 기존 so_line_surcharge_ck(둘 중 하나만)는 그대로
  add constraint so_line_surcharge_label_ck check ((surcharge_label is not null) = (surcharge_pct is not null or surcharge_amount is not null));
comment on column public.so_line.free_reason is
  '⭐ 무상 사유 — CHECK so_line_free_reason_ck 넷(sample · promotion · replacement · other · Caleb 2026-09-23 「대개 그정도야」). 짝 so_line_free_pair_ck: 사유가 있다 = unit_price 가 0 이다(null 이면 양쪽 false → 통과 · 0 이면 사유 필수 · 사유 있고 0 아니면 위반). other 는 comments 필수(so_line_free_other_ck · ⬜7). 관리 축: 자주 = 이 칸이 있는 줄 수 · 얼마나 = 원가(출고 때 원장 FIFO) + 받았을 금액(list_price 가 남는다)';
comment on constraint so_line_free_pair_ck      on public.so_line is '판정 2 — (free_reason is not null) = (unit_price is not distinct from 0) · unit_price null(가격 없음)이면 양쪽 false 로 통과 · price_override 는 짝에 넣지 않는다(이견 5 — 0 을 받으면 RPC 가 true 로 굳힌다)';
comment on constraint so_line_free_other_ck     on public.so_line is '⬜7 — free_reason = other 면 comments 필수 · free_reason null·other 아님이면 통과(null 규칙 확인 2026-09-23) · 빈 문자열은 RPC 가 nullif(trim()) 로 막는다';
comment on constraint so_line_surcharge_label_ck on public.so_line is '판정 7(10-e ⬜ 닫음) — 부가 요금 이름이 있다 = 값(% 또는 금액)이 있다 · 이름만·값만 둘 다 위반 · 둘 중 하나만은 so_line_surcharge_ck 가 본다';

-- ═══ C) 상태 문지기 — 자기 행만 · 허락 짝 0개(판정 6 · 6-g′) ═══
-- insert: status 는 draft 만 · update: new.status is distinct from old.status 이면 거부(이견 9 — status 그대로인 update 는 통과)
-- ⚠️ 소유자(postgres · ①b 의 definer 창구)도 이 트리거를 지난다 — 전이 길은 그 차수가 허락 짝을 v_ok 에 더한다(② draft→confirmed …)
create function public.so_status_guard() returns trigger
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

  -- 허락 짝 목록 — 지금은 0개. 길을 만드는 차수가 여기에 더한다:
  --   ② 확정·할당      v_ok := (old.status, new.status) in (('draft','confirmed'), ('confirmed','draft'), …);
  --   ③ 출고 · ④ POS·counter · ⑤ Release to WMS · WMS 사건(내려가는 짝 포함 · 6-g′ ⬜)
  v_ok := false;

  if not v_ok then
    raise exception 'Order % cannot move from % to % this way — use the order actions — nothing was saved',
      old.so_number, old.status, new.status;
  end if;
  return new;
end;
$$;
comment on function public.so_status_guard() is
  'so BEFORE INSERT OR UPDATE — 자기 행만 보는 전이 문지기(6-g′ · 판정 6). insert 는 draft 만 · update 로 status 가 바뀌면 허락 짝 목록(v_ok)에 없으면 거부 — 지금 목록은 0개(모든 전이 거부 · ②~⑤ 가 더한다). status 그대로인 update 는 통과(이견 9). ⚠️ 소유자·definer 창구도 지난다 — 「계산 규칙 대신 관례」로 비켜 가지 못하게(PO po.html setStatus 사고)';
revoke all on function public.so_status_guard() from public, anon;

create trigger so_status_guard before insert or update on public.so
  for each row execute function public.so_status_guard();
-- 트리거 순서: 이름 알파벳 — so_status_guard 가 so_touch 보다 먼저 돈다(둘 다 BEFORE · 서로 무관).

-- ═══ D) 가격 창구 · 줄 합계 · 손님 값 복사 ═══
-- D-1 so_price_for — 한 창구(판정 4 📌 세일 항은 여기가 아니라 so_line_add 의 할인 식 한 곳에 낀다)
--   순서(⬜4 · 11-c ③): 활성 product_price 줄(낱개 = 정본 · 세트 = 고정가) → 세트이고 줄이 없으면 낱개(parent_product_id) 활성 줄 × pack_factor × (1 − set_discount_pct/100) round 2 → null
--   티어는 purpose='sale' · is_active 만(⬜3 ⚠️) · 가격 줄은 is_active 만(11-g 판정 ②) · 낱개 가격이 없으면 세트도 null · pack_factor 가 없으면 계산 못 함 → null
--   늘 한 행을 낸다(없으면 (null, null)) — 부르는 쪽이 존재 여부를 따지지 않게. product.is_active 는 보지 않는다(비활성 제품 거부는 so_line_add 의 일 · ⬜5)
create function public.so_price_for(p_product_id uuid, p_tier_id uuid)
  returns table (list_price numeric, price_source text)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with t as (
    select rt.id
    from public.ref_price_tier rt
    where rt.id = p_tier_id and rt.purpose = 'sale' and rt.is_active
  ),
  own as (                                        -- 제품 자신의 활성 가격 줄(unique(product_id, tier_id) ⇒ 최대 1)
    select pp.price
    from public.product_price pp join t on t.id = pp.tier_id
    where pp.product_id = p_product_id and pp.is_active
  ),
  calc as (                                       -- 세트 계산 — 낱개(parent_product_id)의 활성 줄 × pack_factor × (1 − set_discount_pct/100)
    select round(pp.price * p.pack_factor * (1 - coalesce(p.set_discount_pct, 0) / 100), 2) as price
    from public.product p
    join public.product_price pp on pp.product_id = p.parent_product_id and pp.is_active
    join t on t.id = pp.tier_id
    where p.id = p_product_id and p.parent_product_id is not null and p.pack_factor is not null
  )
  select coalesce((select price from own), (select price from calc))::numeric as list_price,
         case when (select price from own)  is not null then 'row'
              when (select price from calc) is not null then 'set_calc'
         end as price_source;
$$;
comment on function public.so_price_for(uuid, uuid) is
  '⭐ 가격 창구 하나(SO 쓰기 ①a · ⬜4 · 11-c ③) — (list_price, price_source). row = 활성 product_price 줄(낱개 정본 · 세트 고정가) · set_calc = 낱개 줄 × pack_factor × (1 − set_discount_pct/100) round 2(판정 3 센트) · (null, null) = 가격 없음. 티어는 purpose sale · 활성만(compare·reference 티어 → null) · 가격 줄은 활성만(11-g). 늘 한 행. 손님 할인·세일은 여기 없다 — so_line_add 의 할인 식 한 곳(판정 4)';
revoke all on function public.so_price_for(uuid, uuid) from public, anon;
grant execute on function public.so_price_for(uuid, uuid) to authenticated;   -- 읽기 창구 — 화면이 가격 미리보기에 쓴다(표 select 와 같은 층)

-- D-2 so_line_total — 줄 합계 식 하나(⬜4) · 덮어쓴 줄도 같다: round(qty_ordered × unit_price, 2) · unit_price null → null
--   판정 3 식 round(qty × list × (1 − d/100), 2) 와 같다 — unit_price = list × (1 − d/100) 을 자르지 않고 담기 때문(7자리 절삭이 센트를 뒤집는 예는 못 봤다 — 검증에 ANN01314 6 × 2.49 × 0.93 → 13.89)
create function public.so_line_total(l public.so_line) returns numeric
  language sql immutable
  set search_path = public, pg_temp
as $$
  select round(l.qty_ordered * l.unit_price, 2);
$$;
comment on function public.so_line_total(public.so_line) is
  '⭐ 줄 합계 식 하나(⬜4) — round(qty_ordered × unit_price, 2) · 덮어쓴 줄(price_override)도 같은 식 · unit_price null(가격 없음) → null. 판정 3(Cin7 실측 아홉 줄 일치): 단가는 자르지 않고 합계만 센트로. 화면 셋(warehouse · pos · counter)이 다시 짜지 않는다 · select so_line_total(l) from so_line l';
revoke all on function public.so_line_total(public.so_line) from public, anon;
grant execute on function public.so_line_total(public.so_line) to authenticated;

-- D-3 so_customer_is_company — 손님 이름이 회사인가(판정 3 · Caleb 2026-09-23 · 위에서부터 처음 맞는 줄)
--   1 is_legal_entity → 회사 · 2 price_tier = 'AONE' → 사람 · 3 기본 연락처가 있고 이름이 다르며 어느 쪽도 다른 쪽을 포함하지 않는다 → 회사 · 4 그 밖 → 사람
--   기본 연락처 = is_default · is_active · 이름이 빈값 아님(빈 이름은 「연락처 없음」과 같다 · position('' in x) = 1 함정 회피). 손님이 없으면 null
create function public.so_customer_is_company(p_customer_id uuid) returns boolean
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case
           when c.is_legal_entity                              then true      -- 1
           when c.price_tier = 'AONE'                          then false     -- 2 (AONE 은 95% 이상 개인 · Caleb)
           when k.name is not null
                and lower(trim(c.name)) <> lower(trim(k.name))
                and position(lower(trim(k.name)) in lower(trim(c.name))) = 0
                and position(lower(trim(c.name)) in lower(trim(k.name))) = 0
                                                               then true      -- 3
           else                                                     false     -- 4 (같다 · 한쪽이 다른 쪽을 포함 · 연락처 없음)
         end
  from public.customer c
  left join lateral (
    select cc.name
    from public.customer_contact cc
    where cc.customer_id = c.id and cc.is_default and cc.is_active and nullif(trim(cc.name), '') is not null
    order by cc.created_at
    limit 1
  ) k on true
  where c.id = p_customer_id;
$$;
comment on function public.so_customer_is_company(uuid) is
  '⭐ 손님 이름이 회사인가 — 판정 3(Caleb 2026-09-23 · 실측 Wholesale 표본 12 중 사람 10 · 「이름 ≠ 연락처」 표본 20 중 회사 16 → 규칙 2·3 으로 1/20). 위에서부터 처음 맞는 줄: ① is_legal_entity → 회사 ② price_tier AONE → 사람 ③ 기본 연락처 이름이 다르고 서로 포함하지 않으면 → 회사 ④ 그 밖 → 사람. Cin7 손님은 Name 하나에 회사·사람이 섞였고 Legal entity 는 거의 안 쓰였다. so_copy_customer 가 배송지 회사/사람 칸을 이것으로 가른다 · 틀린 손님은 오더 담당이 초안에서 고친다';
revoke all on function public.so_customer_is_company(uuid) from public, anon;
grant execute on function public.so_customer_is_company(uuid) to authenticated;

-- D-4 so_copy_customer — 손님 값을 오더에 복사해 굳힌다(5-d · 참조가 아니라 복사) · so_create 와 so_header_update(손님 바꾸기 · ⬜6)가 공유
--   ⚠️ 표 so 에 쓴다 — authenticated 는 update 권한이 없어 직접 부르면 42501 · ①b 의 definer 창구가 소유자 권한으로 부른다 ⇒ execute 를 authenticated 에서 뺀다
--   복사: currency(FK+원문 · null 이면 거부 — so.currency_id NOT NULL) · payment_term · discount_pct · tax_rule · price_tier 원문 + price_tier_id(이름 글자 그대로)
--         ar/sale account · location(so 에 이미 있으면 그대로 · 없으면 손님 default_location — 5-d 「채우되 사람이 바꾼다」) · carrier(default_carrier)
--         bill_to 7(청구처 손님 = default_bill_to_customer_id → 없으면 자신 · 기본 Billing 주소 · 없으면 비움) · ship_to 9(판정 ⑧ · 판정 3)
--   배송지(판정 ⑧ · 오더를 만드는 자리에서만): 배송 손님 = default_ship_to_customer_id → 없으면 자신
--         ① 기본 Shipping → ② Shipping 이 0개일 때만 기본 Billing(warning ship_to_from_billing) → ③ 그 밖 비움(warning ship_to_empty) · Business 는 안 쓴다 · 주소록에 되돌려 담지 않는다
--   회사/사람(판정 3): 회사 → ship_to_company = 배송 손님 name · ship_to_contact = 기본 연락처 name · 사람 → company null · contact = 배송 손님 name
--         ship_to_phone = 기본 연락처 phone → mobile_phone → null · bill_to_name = 청구처 손님 name
--   warnings: customer_inactive · price_tier_missing · price_tier_not_for_sale · price_tier_inactive · currency_mismatch(손님 통화 ≠ 티어 통화 · 11-c 이견 2 「막지 않고 알린다」) · ship_to_from_billing · ship_to_empty · bill_to_empty
create function public.so_copy_customer(p_so_id uuid, p_customer_id uuid) returns jsonb
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
    tax_rule           = c.tax_rule,
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

  return jsonb_build_object(
    'so_id',            p_so_id,
    'customer_id',      c.id,
    'price_tier_id',    v_tier.id,
    'ship_to_is_company', v_company,
    'warnings',         to_jsonb(v_warn)
  );
end;
$$;
comment on function public.so_copy_customer(uuid, uuid) is
  '⭐ 손님 값을 초안 오더에 복사해 굳힌다(5-d · SO 쓰기 ①a · ⬜6 공유 — so_create · so_header_update 손님 바꾸기). 통화·결제조건·할인·세율·티어(원문+id)·계정·창고(비어 있을 때만)·carrier · 청구처 7(기본 Billing) · 배송지 9(판정 ⑧: 기본 Shipping → Shipping 0개면 기본 Billing → 비움 · 회사/사람은 so_customer_is_company · 판정 3). 초안 아니면 거부 · 손님 통화 없으면 거부 · 그 밖은 warnings 로 알린다(customer_inactive · price_tier_missing/not_for_sale/inactive · currency_mismatch · ship_to_from_billing · ship_to_empty · bill_to_empty). ⚠️ authenticated 는 execute 없음 — ①b definer 창구의 속 함수(직접 부르면 42501)';
revoke all on function public.so_copy_customer(uuid, uuid) from public, anon, authenticated;

-- ═══ 검증(Caleb · psql heredoc · 회신에 따로) — 권한(가짜 직원 A·B · 주소록 · customer 머리) · 문지기 셋 · CHECK 넷 · so_price_for 다섯 · so_line_total · 회사/사람 넷 · so_copy_customer 한 번
--   기대: 함수 다섯 신설(so_status_guard · so_price_for · so_line_total · so_customer_is_company · so_copy_customer) · 트리거 so_status_guard · 정책 여섯 식 sales OR master
--         ims_perm_catalog screens 5 · so.price_tier_id · so_line.free_reason · so_line CHECK 12(기존 8 + 4) · so_line.unit_price nullable · 기본값 없음
