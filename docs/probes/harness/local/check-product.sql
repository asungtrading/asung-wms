-- 로컬 Supabase 결과 단언 — run-product.js local main 뒤에 · OK / MISMATCH 줄 · 기대 OK 11 · MISMATCH 0 (ldfix-1b · 재료 fixtures/product.js)
\set ON_ERROR_STOP on
with u as (select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid id, n from generate_series(1, 999) n),
     c as (select ('c0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid id, n from generate_series(1, 999) n),
     t(tag, okv) as (values
  ('C1 679: P7 의 sku 는 IMS 값 P7-NEW 그대로(on_conflict=cin7_id)', (select sku = 'P7-NEW' and updated_by is null from product where id = (select id from u where n=7))),
  ('C2 672: P8 이름 · family 가 Cin7 값으로(새 ⑧) · updated_by 는 적재가 비움', (select name = 'Product P8' and family_id = (select id from u where n=101) and updated_by is null from product where id = (select id from u where n=8))),
  ('C3 674: IMS 제품 P6 에 cin7_id 만 · 이름 · sellable · source 그대로', (select cin7_id = (select id from c where n=6) and name = 'P6 made in IMS' and source = 'manual' and sellable = false from product where id = (select id from u where n=206))),
  ('C4 670/675: P2 false(ims) · P1-6 false(ims 세트) · P1-12 false(세트) · P1-24 true(세트 · 그대로)', (select bool_and(case n when 2 then not sellable when 3 then not sellable when 4 then not sellable when 14 then sellable end) from product p join u on u.id = p.id where u.n in (2, 3, 4, 14))),
  ('C5 675: 새 세트 P1-36 — 잇기 뒤 parent · pack 36 · sellable false(트리거 실물)', (select parent_product_id = (select id from u where n=1) and pack_factor = 36 and sellable = false from product where sku = 'P1-36')),
  ('C6 새 낱개 P11 · sellable true · source cin7', (select sellable and source = 'cin7' from product where sku = 'P11')),
  ('C7 family: F3FAM 이름 Cin7 값(672) · F2FAM cin7_id 만 · manual', (select name = 'Family F3FAM' from product_family where id = (select id from u where n=103)) and (select cin7_id = (select id from c where n=102) and source = 'manual' from product_family where id = (select id from u where n=202))),
  ('C8 바코드: B2 manual 꺼짐 그대로 · B8 대표 true(672 덮임) · B1 있음', (select not is_active and source = 'manual' from product_barcode where product_id = (select id from u where n=2) and barcode = 'B2') and (select is_primary and updated_by is null from product_barcode where product_id = (select id from u where n=8) and barcode = 'B8') and (select is_active from product_barcode where product_id = (select id from u where n=1) and barcode = 'B1')),
  ('C9 BOM: (P10,P2) manual 꺼짐 그대로 · (P10,P1) qty 2(672 덮임)', (select not is_active and source = 'manual' from product_bom where parent_product_id = (select id from u where n=10) and component_product_id = (select id from u where n=2)) and (select quantity = 2 and updated_by is null from product_bom where parent_product_id = (select id from u where n=10) and component_product_id = (select id from u where n=1))),
  ('C10 제품 행 12(10 + 새 2) · AS91437-BLK 그대로 한 행', (select count(*) = 12 from product) and (select count(*) = 1 from product where sku = 'AS91437-BLK')),
  ('C11 Shopify 큐 0(켜진 listing 없음 → shop_queue_add 가 안 넣는다 · 새 ⑩)', (select count(*) = 0 from shop_push_queue))
)
select case when okv then 'OK ' || tag else 'MISMATCH ' || tag end result from t;
