-- 로컬 Supabase 결과 단언 — run-tag.js local main 뒤에(Apply + Dry 2 회차) · 기대 OK 7 · MISMATCH 0 (ldfix-1d · 재료 fixtures/tag.js)
\set ON_ERROR_STOP on
with u as (select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid id, n from generate_series(1, 999) n),
     t(tag, okv) as (values
  ('T1 넣은 5 줄(source cin7): S1 Clearance · S2 NewTag · S2 OffDeal · S3 Clearance · S7 Q4 2026', (select count(*) = 5 from product_tag pt join (values (1, 'Clearance'), (2, 'NewTag'), (2, 'OffDeal'), (3, 'Clearance'), (7, 'Q4 2026')) v(n, tag) on pt.product_id = (select id from u where u.n = v.n) and pt.tag = v.tag where pt.source = 'cin7')),
  ('T2 지운 4 줄 없음: S5 Gone Tag · S6 DISC_YesSale · S7 q4 2026 · S8 OldOnly', (select count(*) = 0 from product_tag pt join (values (5, 'Gone Tag'), (6, 'DISC_YesSale'), (7, 'q4 2026'), (8, 'OldOnly')) v(n, tag) on pt.product_id = (select id from u where u.n = v.n) and pt.tag = v.tag)),
  ('T3 manual 2 줄 그대로(AOS · Hair Care · id 무변) · P4 에 cin7 줄 안 생김', (select count(*) = 2 from product_tag where source = 'manual' and id in (select id from u where n in (502, 503))) and (select count(*) = 0 from product_tag where product_id = (select id from u where n=4) and source = 'cin7')),
  ('T4 그대로인 cin7 2 줄(Brand X · Household · id 무변 · updated_by null)', (select count(*) = 2 from product_tag where id in (select id from u where n in (501, 504)) and source = 'cin7' and updated_by is null)),
  ('T5 product_tag 9 줄 = 8 − 4 + 5', (select count(*) = 9 from product_tag)),
  ('T6 넣은 줄은 (product_id, tag) 유니크 · tag CHECK(btrim · 비지 않음) 통과 — 중복 0', (select count(*) = 0 from (select product_id, tag from product_tag group by 1, 2 having count(*) > 1) x)),
  ('T7 product 무변(9 행 · S10 manual 그대로 cin7_id 없음)', (select count(*) = 9 from product) and (select cin7_id is null and source = 'manual' from product where id = (select id from u where n=10)))
)
select case when okv then 'OK ' || tag else 'MISMATCH ' || tag end result from t;
