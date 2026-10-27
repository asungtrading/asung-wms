-- lec-1 — 배송지 회사 판정: 도매 등급 손님은 법인으로 본다 (2026-10-27 · Caleb · 판정 번호는 문서 차수가 정한다 · 짐작 793)
-- [테스트 · Asung-IMS] 먼저 · 운영은 전환일 적용
--
-- 사정   customer.is_legal_entity 는 Cin7 에서 손으로 체크하는 칸이라 관리가 안 된다(적재가 매번 Cin7 값으로 덮는다 · 판정 672) ·
--        Caleb 「wholesale price tier 를 쓰는 손님은 모두 legal entity 라고 봐야 한다」 · USWholesale USD · Regular CAD 도 Wholesale 처럼
-- 방법   데이터를 고치지 않는다 · 판정 함수 so_customer_is_company 의 규칙 ① 에 등급 조건을 「또는」 으로 더한다 · ② ~ ④ 그대로
--        등급은 customer.price_tier(원문 글자 · FK 없음) → ref_price_tier.name(lower · trim) → code 로 읽는다(이름 글자는 바뀔 수 있다 · code 는 Cin7 고정)
--        code 1 Wholesale · 2 Franchise · 4 Regular CAD · 7 USWholesale USD — 함수 안 상수(바꿀 사람이 지금 없다 · 설정 화면 비용) · AONE(3) 은 그대로 규칙 ② 사람
--        Franchise 는 Caleb 결정(2026-10-27 · 이견 2) — 손님 0 · ref_price_tier 주석 「Wholesale 과 같다」
-- 실측   2026-10-27 테스트 DB 활성 손님 9,734 — 회사 ↔ 사람이 바뀌는 손님 56(전부 Wholesale · legal false · 규칙 ③ 이 못 잡던 손님) ·
--        등급만으로 회사가 되는 829 중 773 은 이미 ③ 으로 회사 · USWholesale USD · Regular CAD 의 legal false 손님 둘은 이미 ③ 으로 회사
-- 바탕   20260923182231_so_write_base.sql D-3(마지막 정의 · md5 3057628c…) — 시그니처 · language sql · stable · invoker · search_path · grant 그대로 · 바뀐 줄은 규칙 ① 한 곳
-- 무접촉 so_copy_customer(부르는 곳 하나) · 열린 SO 의 배송지 스냅숏(만들 때 굳힌다 · 다시 계산하지 않는다) · 화면

create or replace function public.so_customer_is_company(p_customer_id uuid) returns boolean
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case
           when c.is_legal_entity
                or exists (select 1 from public.ref_price_tier t                 -- lec-1: 도매 등급은 법인으로 본다
                           where t.code in (1, 2, 4, 7)                         --   1 Wholesale · 2 Franchise · 4 Regular CAD · 7 USWholesale USD
                             and lower(trim(t.name)) = lower(trim(c.price_tier)))
                                                                then true      -- 1
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
  'lec-1 2026-10-27 ⭐ 손님 이름이 회사인가 — 판정 3(Caleb 2026-09-23) + 도매 등급(Caleb 2026-10-27 · 판정 번호는 문서 차수가). 위에서부터 처음 맞는 줄: ① is_legal_entity 또는 등급이 ref_price_tier code 1 Wholesale · 2 Franchise · 4 Regular CAD · 7 USWholesale USD(customer.price_tier 원문 → name lower·trim 매칭) → 회사 ② price_tier AONE → 사람 ③ 기본 연락처 이름이 다르고 서로 포함하지 않으면 → 회사 ④ 그 밖 → 사람. is_legal_entity 는 Cin7 손 체크 칸이라 관리가 안 된다(적재가 덮는다) — 데이터를 고치지 않고 판정에 등급을 더했다. so_copy_customer 가 배송지 회사/사람 칸을 이것으로 가른다 · 틀린 손님은 오더 담당이 초안에서 고친다';
revoke all on function public.so_customer_is_company(uuid) from public, anon;
grant execute on function public.so_customer_is_company(uuid) to authenticated;

-- 검증: supabase/tests/lec_1_check.sql (begin → \i → 가짜 손님 LEC- 열여섯 · 전수 비교 → rollback)
