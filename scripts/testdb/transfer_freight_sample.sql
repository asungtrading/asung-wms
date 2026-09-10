-- ⚠️ 이것은 **임시 시험 데이터**다. 수집기(EF)가 붙으면 필요 없어진다.
-- ⭐ 그때 이 파일을 지우지 말고 「수집기 이전 검증용」으로 남겨두면 배분 로직만 따로 시험할 수 있다.
--
-- 트랜스퍼 운송비 문서 단위 금액 — inv_doc_cost (20260910141553)
-- ⚠️ 실측 GAS 프로브 2026-09-10 · stockTransfer 상세 ManualJournals 의 IsSystem=false 행만.
--    가정이 아니라 실물이다 — 프로브가 본 값 그대로.
--    (TR-03975 의 IsSystem=true 행 4,878.11 은 운송중 계정 이동이라 넣지 않는다)
-- 📌 테스트 DB 재복사 후 이 파일을 다시 돌리면 복원된다:
--    psql "$(cat ~/.asung-testdb-url)" -f scripts/testdb/transfer_freight_sample.sql
--    그 뒤 select inv_layer_apply();  — 배분은 apply 안에서 매번 다시 계산된다.

insert into inv_doc_cost
  (doc_type, doc_number, kind, amount, occurred_on, ref_number,
   debit_account, credit_account, collector, raw)
values
  ('transfer','TR-03975','transfer_freight', 398.75,'2026-08-27','B6900109',
   '_59_','_136_','manual@2026-09-10', '{"note":"GAS probe 실측"}'),
  ('transfer','TR-04175','transfer_freight', 249.33,'2026-09-04','B6913286',
   '_59_','_136_','manual@2026-09-10', '{"note":"GAS probe 실측"}')
on conflict (doc_type, doc_number, kind, ref_number, occurred_on)
do update set amount = excluded.amount, refreshed_at = now();
