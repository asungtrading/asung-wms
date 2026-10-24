# 적재 시험 하네스 (ldfix-1a · 2026-10-24) — 1b ~ 1d 가 다시 쓴다

`docs/probes/*.gs`(Apps Script 원본 사본)를 node 에서 돌려 **보내는 요청(메서드 · 경로 · 본문)** 을 단언한다. 레포에서 Apps Script 를 실행할 수 없어서다.

- `fake-gas.js` — 가짜 `UrlFetchApp` · `PropertiesService` · `DriveApp` · `Logger` · `Utilities` · `MimeType` · `getProp` + 두 모드
  - `emu`: 메모리 안 PostgREST 에뮬레이터(eq · in · is.null · not.is.null · gt · Range · count=exact · merge-duplicates upsert · 손님 표 트리거 흉내)
  - `local`: 같은 요청을 **진짜 PostgREST**(로컬 Supabase · `curl` 동기 호출)로 보낸다 → 트리거 · 제약 · 묶음 upsert 실물
- `ims-common.js` — 편집기 `ProbeIMS.js` 의 `ims_fetch_` · `ims_blank_` 원문 복사(56 ~ 73 · 115 ~ 119 행)
- `fixtures/customer.js` — 손님 재료(Cin7 응답 + 우리 표 상태) · 같은 재료가 `local/seed-customer.sql` 을 만든다
- `run-customer.js [emu|local] [main|dup|exists]` — Dry → Apply1 → Apply2 → Apply3 → Apply4 → Verify 를 돌리고 요청 · 결과를 단언
- `run-supplier.js [emu|local] [main|conflict]` · `fixtures/supplier.js` · `local/make-seed-supplier.js` · `local/check-supplier.sql` · `local/run-local-supplier.sh` — 공급처 적재(ldfix-1c · 본 행 Dry · Apply × 2 회차 · 주소 · 연락처 · Verify · 제품↔공급처 적재 — `ImsLoadProduct.gs` · `ImsLoadProductSupplier.gs` · `ImsLoadSupplier.gs` 셋을 올린다 · 가짜 시트 `sheets.ips_line`)
- `run-product.js [emu|local] [main|conflict]` · `fixtures/product.js` · `local/make-seed-product.js` · `local/check-product.sql` · `local/run-local-product.sh` — 제품 적재(ldfix-1b · family · 1단계 전량 Dry · Apply · 2단계 잇기 · Extra · 바코드 · BOM) · 가짜 Cin7 은 `fake-gas.js` 의 `cin7` 재료(product · productFamily · Page · Limit · Sku)
- `run-tag.js [emu|local] [main|bigdel]` · `fixtures/tag.js` · `local/make-seed-tag.js` · `local/check-tag.sql` · `local/run-local-tag.sh` — 태그 적재(ldfix-1d · 판정 676 · `ImsLoadProduct.gs` + `ImsLoadProductTag.gs` 를 올린다 · Dry(속성 없음 → 기본값 · 보고 폴더 만들기 · 보고 파일 · CSV 둘 · 딜 표시 · 짐작) → Apply(DELETE → upsert · 속성 적기) → Dry 2 회차(멱등) · `bigdel` 은 큰 지우기 안전장치 → 허락 속성으로 한 번 통과) · 에뮬레이터에 DELETE(`?source=eq.cin7&id=in.(…)` · return=representation) · `DriveApp.createFolder` · `MimeType.CSV` 를 더했다(ldfix-1d) · `fake.reports` 에 mime · folder 가 붙는다
- `run-customer.js` 는 ldfix-1d 부터 `ImsLoadSupplier.gs` 도 올린다(손님 적재가 `ils_vis_` 를 부른다 · 판정 681 · 재료에 U+200B 짝 Zwsp Co)
- `local/` — `seed-customer.sql`(생성물) · `check-customer.sql`(로컬 DB 결과 단언) · `run-local.sh`

실행: `node docs/probes/harness/run-customer.js emu main` · 로컬은 `docs/probes/harness/local/run-local.sh [main|dup|exists]`
- 로컬 DB = 테스트 DB public 의 `pg_dump --schema-only` 복원 + `grant … to service_role`(ldfix-1a 보고 · `supabase db reset` 은 데이터 의존 마이그레이션에서 멈춘다) · `run-local*.sh` 가 아직 없는 마이그레이션(목록 · 1a2 · 1c2 · `apply_mig <파일> <적용 표지 SQL>`)을 로컬에만 차례로 적용한다(가드 표식 `inv_config.db_role=test` 와 채우기 대상 행을 먼저 둔다 · 에뮬레이터는 rpc `product_supplier_default_recalc` 를 JS 로 흉내 낸다 — 실물은 로컬) · seed 의 truncate cascade 가 로컬 거래 표를 비운다(로컬 전용)
⚠️ 하네스는 레포에서만 돈다 · Apps Script 에 올리지 않는다 · 테스트 DB(Asung-IMS)를 가리키지 않는다(로컬 54321 만)
