-- 로컬 Supabase 결과 단언 — run-supplier.js local main 뒤에(본 행 Apply 2 회차 포함) · 기대 OK 10 · MISMATCH 0 (ldfix-1c · 재료 fixtures/supplier.js)
\set ON_ERROR_STOP on
with u as (select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid id, n from generate_series(1, 999) n),
     c as (select ('c0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid id, n from generate_series(1, 999) n),
     t(tag, okv) as (values
  ('C1 674 · 681: IMS 공급처에 cin7_id 만(U+200B 이름과 짝) · 이름 원문 · purchasable · source 그대로', (select cin7_id = (select id from c where n=5) and name = 'TEST Supplier-Canada' and is_purchasable and source = 'manual' from supplier where id = (select id from u where n=205))),
  ('C2 672: S2 이름 Cin7 값 · updated_by 비움 · ⚠️ is_active 는 2 회차 Apply 로 Cin7 값(false) — 680 은 한 번만', (select name = 'Supplier S2' and updated_by is null and is_active = false from supplier where id = (select id from u where n=2))),
  ('C3 새 활성 S3 들어옴 · 새 비활성 S4 없음', (select count(*) = 1 from supplier where cin7_id = (select id from c where n=3) and is_active) and (select count(*) = 0 from supplier where cin7_id = (select id from c where n=4))),
  ('C4 Cin7 에 없는 S6 내려짐 · 우리 표의 비활성 S7 그대로 비활성', (select not is_active from supplier where id = (select id from u where n=6)) and (select not is_active from supplier where id = (select id from u where n=7))),
  ('C5 공급처 행 6(5 + 새 1) · is_purchasable 무변', (select count(*) = 6 from supplier) and (select bool_and(is_purchasable) from supplier where id in (select id from u where n in (1, 2, 6, 7, 205)))),
  ('C6 주소: S6 주소 내려짐 · S1 주소 활성 · IMS 주소 그대로 · 짝지은 공급처의 Cin7 주소(C105) 없음', (select not is_active from supplier_address where cin7_id = (select id from c where n=106)) and (select is_active from supplier_address where cin7_id = (select id from c where n=101)) and (select count(*) = 1 from supplier_address where id = (select id from u where n=151) and source = 'manual' and line1 = 'IMS own') and (select count(*) = 0 from supplier_address where cin7_id = (select id from c where n=105))),
  ('C7 연락처: C202 내려짐 · 기본 풀림 · IMS 연락처 기본 그대로(기본 하나 제약 깨짐 0) · C205 · C209 없음', (select not is_active and not is_default from supplier_contact where cin7_id = (select id from c where n=202)) and (select is_default and source = 'manual' from supplier_contact where id = (select id from u where n=251)) and (select count(*) = 0 from supplier_contact where cin7_id in (select id from c where n in (205, 209)))),
  ('C8 product_supplier: IMS 가 끈 C603 그대로(manual · 꺼짐 · cost 7.77)', (select source = 'manual' and not is_active and cost = 7.77 from product_supplier where id = (select id from u where n=603))),
  ('C9 승격 줄 U604: cin7_id 만 붙고 cost 5.55 · supplier_sku IMS-SKU · source manual 그대로', (select cin7_id = (select id from c where n=604) and cost = 5.55 and supplier_sku = 'IMS-SKU' and source = 'manual' from product_supplier where id = (select id from u where n=604))),
  ('C10 손댄 cin7 줄 U601 은 Cin7 값(cost 1.5) · 새 줄 C605 들어옴(새 공급처 S3)', (select cost = 1.5 and updated_by is null from product_supplier where id = (select id from u where n=601)) and (select count(*) = 1 from product_supplier where cin7_id = (select id from c where n=605)))
)
select case when okv then 'OK ' || tag else 'MISMATCH ' || tag end result from t;
