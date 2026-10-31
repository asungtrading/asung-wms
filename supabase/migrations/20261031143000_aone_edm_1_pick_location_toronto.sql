-- aone-edm-1 (2026-10-31 · 판정 895) — aonebeauty.com 에 Edmonton 재고를 보내도 웹 오더는 늘 Toronto
--   사실(Caleb · 동료 · 2026-10-31): Cin7 은 aonebeauty.com 에 Toronto + Edmonton 재고를 모두 보내고 있었다 — 정본의 「aone = Toronto 재고만」(판정 427 · deferred 188)은 운영과 달랐다.
--   사실(Caleb): 「cin7일때는 모든 오더는 토론토로 들어왔었어. 그리고 여전히 그것을 선호해」.
--   판정 895 = B:
--     ① aone 스토어에 위치 짝 「Aonebeauty EDM ↔ Asung - Edmonton」 을 더한다(화면 Settings → Shopify Stores · Caleb · ⚠️ 이 마이그레이션 뒤에) → aone 재고는 두 로케이션으로 나간다 · Shopify DENY 는 두 위치 Available 을 더해 판다.
--     ② 그래도 aone 웹 오더는 늘 Toronto 창고 — 배송지 주(AB · BC · SK)로 가르지 않는다 ← 이 파일.
--     ③ 손님이 픽업 위치로 EDM 을 고른 aone 오더는 Edmonton — 픽업 오더는 shop_order_prepare ③ 브랜치(ful-1b 판정 454)가 픽업 위치의 짝 창고로 따로 정하고 이 함수를 거치지 않는다 · 짝을 더하면 코드 0 으로 성립(지금은 pickup_location_unpaired 로 needs_review).
--   바뀌는 것 — shop_order_pick_location(ord-1a1 20261010233000 · 마지막 정의 · DB prosrc 와 파일 본문 동일 확인) 바이트 복사 + 갈래 하나:
--     스토어 kind = 'aone' 이면 그 스토어의 Toronto 짝(기존 v_tor 찾기 그대로)을 돌려준다 · Toronto 짝이 없으면 기존 흐름(짝 하나 = 그것 · 주 가르기 · 손님 기본 · 마지막 Toronto)으로 떨어진다.
--     갈래를 kind 로 건 까닭(Caleb 2026-10-31 · 대화 Claude 안): 「오더는 늘 Toronto」 는 aone 종류(매장 픽업 · 카드)의 성질이지 스토어 설정이 아니다 · 이미 kind = 'aone' 로 가르는 마이그레이션 파일 14 · 새 칸은 화면 차수가 따르고 얻는 게 없다.
--     asung 의 주 가르기(430) · 짝 하나면 그것(427) · 손님 기본 · 마지막 Toronto · 재고로 고르지 않음(365)은 그대로.
--   함께 고치는 주석: 함수 주석 · shop_store.oos_policy 칼럼 주석(shop-pol 20261010220500 의 「Toronto 재고만 — 위치 짝을 Toronto 하나로」 는 바뀜 · Caleb 2026-10-31).
--   컷오버 지우는 순서: 새 표 없음 → 해당 없음.
--   ⚠️ 순서(Caleb): 이 마이그레이션 적용 → 확인 → 그 뒤에 EDM 짝 더하기. 짝을 먼저 더하면 그 사이 AB · BC · SK 의 aone 오더가 Edmonton 으로 들어가고, 매시 정각 ims-stock-diff(jobid 45)가 Edmonton 수량을 보낸다.
--   적용(Caleb · 테스트 DB = IMS 메인 · 617 · 운영 asung-WMS 에는 올리지 않는다): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20261031143000_aone_edm_1_pick_location_toronto.sql && supabase migration repair --status applied 20261031143000 --db-url "$(cat ~/.asung-testdb-url)"

-- ═══ 1) shop_order_pick_location — ord-1a1 본문 그대로 + aone 갈래(판정 895) ═══
create or replace function public.shop_order_pick_location(p_store_id uuid, p_province_code text, p_customer_id uuid) returns uuid
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_edm uuid;
  v_tor uuid;
  v_n   int;
  v_cust uuid;
  v_kind text;                                                                                                                           -- aone-edm-1 판정 895
begin
  select count(*) into v_n from public.shop_location l where l.store_id = p_store_id and l.is_active;
  if v_n = 0 then return null; end if;
  select l.warehouse_id into v_edm from public.shop_location l join public.ref_warehouse w on w.id = l.warehouse_id
   where l.store_id = p_store_id and l.is_active and w.name ilike '%edmonton%' order by w.name limit 1;                                -- 이름으로 Edmonton 짝을 찾는다(ref_warehouse 에 지역 칸이 없다 · 이견)
  select l.warehouse_id into v_tor from public.shop_location l join public.ref_warehouse w on w.id = l.warehouse_id
   where l.store_id = p_store_id and l.is_active and l.warehouse_id is distinct from v_edm order by w.is_default desc, w.name limit 1;
  select s.kind into v_kind from public.shop_store s where s.id = p_store_id;
  if v_kind = 'aone' and v_tor is not null then return v_tor; end if;                                                                     -- aone-edm-1 판정 895: aone 웹 오더는 늘 Toronto 짝(Edmonton 짝이 있어도 · 주 · 손님 기본을 보지 않는다) · Toronto 짝이 없으면 아래 기존 흐름
  if v_edm is null then return v_tor; end if;                                                                                            -- 짝 하나(aone) → 늘 그 창고(판정 427)
  if v_tor is null then return v_edm; end if;
  if upper(trim(coalesce(p_province_code, ''))) in ('AB', 'BC', 'SK') then return v_edm; end if;                                          -- 판정 430
  if nullif(trim(p_province_code), '') is not null then return v_tor; end if;
  select c.default_location_id into v_cust from public.customer c where c.id = p_customer_id;                                            -- 주가 없을 때만 손님 기본 · 그 스토어의 짝이어야 한다
  if v_cust is not null and v_cust in (v_edm, v_tor) then return v_cust; end if;
  return v_tor;
end;
$$;
revoke all on function public.shop_order_pick_location(uuid, text, uuid) from public, anon, authenticated;
comment on function public.shop_order_pick_location(uuid, text, uuid) is 'ord-1a1 판정 430 · 427 · ⭐ aone-edm-1 판정 895: 웹 오더(배송)의 창고 — kind aone 스토어는 늘 Toronto 짝(Edmonton 짝이 있어도 · 주 · 손님 기본을 보지 않는다 · Toronto 짝이 없으면 아래로) · 스토어의 활성 위치 짝이 하나면 그것 · 둘이면 배송지 provinceCode AB · BC · SK → Edmonton 짝 · 다른 주 → Toronto 짝 · 주가 없으면 손님 기본 창고(그 스토어의 짝일 때만) · 그래도 없으면 Toronto 짝 · 재고로 고르지 않는다(365) · 픽업 오더는 이 함수를 거치지 않는다(shop_order_prepare ③ · 픽업 위치의 짝 창고 · ful-1b 454 · 895-③)';

-- ═══ 2) shop_store.oos_policy 칼럼 주석 — 「Toronto 재고만 · 짝 하나」 는 판정 895 로 바뀜 ═══
comment on column public.shop_store.oos_policy is 'shop-pol 판정 427 · aone-edm-1 판정 895: 품절 판매 — continue = 켜진 변형이 0 이어도 주문을 받는다(asung.ca · 시험 스토어) · deny = 0 이면 Shopify 가 막는다(aonebeauty.com — 스토어의 모든 위치 Available 을 더해 본다 · 위치 짝 Toronto + Edmonton 둘 · 오더는 늘 Toronto 창고(shop_order_pick_location)) · 변형의 inventoryPolicy = 꺼진 구성원 DENY(406) → 단종 DENY(428) → 이 칸 · 바꾸면 트리거가 켜진 대상 전부를 상품 큐에';

-- ═══ 3) 확인 ═══
do $$
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_pick_location' and prosrc like '%v_kind = ''aone''%') <> 1 then
    raise exception 'aone-edm-1: shop_order_pick_location without the aone branch';
  end if;
end $$;
