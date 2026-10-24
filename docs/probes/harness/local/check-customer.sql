-- 로컬 Supabase 결과 단언 — run-customer.js local main 뒤에 · OK / MISMATCH 줄 · 기대 OK 18 · MISMATCH 0 (ldfix-1a · 1a2 · 1d · 재료 fixtures/customer.js · 로컬에 ldfix-1a2 마이그레이션 적용 뒤)
\set ON_ERROR_STOP on
with u as (select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid id, n from generate_series(1, 999) n),
     c as (select ('c0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid id, n from generate_series(1, 999) n),
     t(tag, okv) as (values
  ('C1 짝지은 IMS 손님: cin7_id 만 · price_tier Retail · source manual', (select x.cin7_id = (select id from c where n=7) and x.price_tier = 'Retail' and x.source = 'manual' and x.name = 'TEST IMS Shopify' from customer x where x.id = (select id from u where n=51))),
  ('C2 Touched Co 이름이 Cin7 값으로(672) · updated_by 는 적재가 비움', (select x.name = 'Touched Co' and x.updated_by is null from customer x where x.id = (select id from u where n=9))),
  ('C3 Cin7 에 없는 손님 둘 내려짐(C10 · C17)', (select bool_and(not is_active) from customer where id in ((select id from u where n=10), (select id from u where n=17)))),
  ('C4 Kid A 이어짐 · parent_source cin7', (select x.parent_id = (select id from u where n=3) and x.parent_source = 'cin7' from customer x where x.id = (select id from u where n=4))),
  ('C5 Kid Gone 부모 · parent_source · 청구처 비움(판정 256 · 규칙 4 · 트리거 실물)', (select x.parent_id is null and x.parent_source is null and x.default_bill_to_customer_id is null from customer x where x.id = (select id from u where n=5))),
  ('C6 Kid ImsOnly 그대로(ims)', (select x.parent_id = (select id from u where n=2) and x.parent_source = 'ims' from customer x where x.id = (select id from u where n=6))),
  ('C7 Clore 자식 6 전부 parent_source ims 그대로 · OTT 부모 Other Parent 그대로', (select count(*) = 6 and bool_and(parent_source = 'ims') and bool_and(default_bill_to_customer_id = parent_id) from customer where id in (select id from u where n between 11 and 16)) and (select parent_id = (select id from u where n=2) from customer where id = (select id from u where n=16))),
  ('C8 손댄 주소가 Cin7 값으로(672)', (select line1 = 'Line 3 CIN7' from customer_address where id = (select id from u where n=103))),
  ('C9 Gone Active 의 주소 내려짐 · 기본 풂', (select not is_active and not is_default_for_type and default_customer_id is null from customer_address where id = (select id from u where n=109))),
  ('C10 IMS 손님의 manual 주소 셋 그대로(기본 유지)', (select count(*) = 3 and bool_and(is_default_for_type and source = 'manual') from customer_address where id in (select id from u where n in (151, 152, 153)))),
  ('C11 짝지은 손님의 Cin7 주소 · 연락처 행 없음(C107 · C108 · C110 · C207)', (select count(*) = 0 from customer_address where cin7_id in (select id from c where n in (107, 108, 110))) and (select count(*) = 0 from customer_contact where cin7_id = (select id from c where n=207))),
  ('C12 cin7 주소 활성 2 · cin7 연락처 활성 1', (select count(*) = 2 from customer_address where source = 'cin7' and is_active) and (select count(*) = 1 from customer_contact where source = 'cin7' and is_active)),
  ('C13 손님 행 수 20 그대로(새 행 0 · ldfix-1d 재료 Zwsp Co 포함) · cin7 활성 15', (select count(*) = 20 from customer) and (select count(*) = 15 from customer where source = 'cin7' and is_active)),
  ('C14 parent_source cin7 = 1 · ims 세움 7 · ims 뗌 1', (select count(*) = 1 from customer where parent_source = 'cin7') and (select count(*) = 7 from customer where parent_source = 'ims' and parent_id is not null) and (select count(*) = 1 from customer where parent_source = 'ims' and parent_id is null)),
  ('C15 적재가 쓴 cin7 행은 updated_by null(ims_touch 실물)', (select bool_and(updated_by is null) from customer where source = 'cin7' and cin7_id in (select id from c where n in (1, 2, 3, 4, 9, 11, 12, 13, 14, 15, 16, 18, 19)))),
  ('C17 Kid Detached 그대로(parent null · ims · 판정 678 · 트리거 실물로 ims 가 남는다)', (select x.parent_id is null and x.parent_source = 'ims' from customer x where x.id = (select id from u where n=19))),
  ('C16 기본 하나 제약 깨짐 0 — (default_customer_id, type) 겹침 없음', (select count(*) = 0 from (select default_customer_id, type from customer_address where default_customer_id is not null group by 1, 2 having count(*) > 1) x)),
  ('C18 [ldfix-1d · 681] Zwsp Co: U+200B 가 붙은 Cin7 이름과 짝 — cin7_id 만 · 이름 원문 · manual 그대로 · 그 Cin7 행은 따로 안 생김', (select cin7_id = (select id from c where n=24) and name = 'Zwsp Co' and source = 'manual' from customer where id = (select id from u where n=55)) and (select count(*) = 1 from customer where cin7_id = (select id from c where n=24)))
)
select case when okv then 'OK ' || tag else 'MISMATCH ' || tag end result from t;
