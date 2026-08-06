# WMS Supabase 스키마 (14개 테이블 + 함수 1)

운영 테이블 12개(2026-07-22 `wms_waves` 추가) + 복제 2 + `wms_staff` + 불변식 함수 `wms_health_check()`. RLS ON(2026-07-19, `auth_all`). 복제 2테이블은 GAS·Edge Function만 접근하는 내부 마스터.

> ⚠️⚠️ **이 문서는 요약이고 진실은 실물 DB 다 (2026-07-29 — 규칙 29).** "적용됨"으로 적힌 인덱스가 실제와 달라 리시빙 discrepancy 가 구현 이후 한 번도 기록되지 않은 사고가 있었다. 인덱스·제약을 근거로 코드를 쓸 때는 먼저 확인할 것:
> ```sql
> select indexname, indexdef from pg_indexes where tablename='<table>';
> select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid='public.<table>'::regclass;
> ```
> 그리고 **부분(partial) 유니크 인덱스는 PostgREST `on_conflict` 로 추론되지 않는다** — upsert 키에는 WHERE 절 없는 전체 유니크를 건다.

## 운영 테이블 11개

### wms_zone_sequence — 동선 순서 + 좌표
`id`, `warehouse`(toronto/edmonton), `zone`, `sequence_order`(작을수록 먼저, UPDATE로 조정), `center_x`/`center_y`(numeric, WarehouseMap 좌표, 경로최적화 확장용), `active`, unique(warehouse,zone). 초기값 23행 적재됨(toronto 13 + edmonton 10).

### wms_drop_locations — 픽 후 드롭장소 마스터 (⚠️ 아직 비어있음)
`id`, `location_code`(unique), `name`, `warehouse`, `active`, `created_at`.

### wms_orders — 오더 헤더
`id`, `cin7_sale_id`(unique, 폴링 dedup 키), `order_number`, `customer_name`, `warehouse`, `location`(Cin7 원문), `ship_by`, `order_progress`, `cin7_status`, `status`(enum: pending/picking/packing/ready_to_close/closed/voided), `completion_type`(clean/flagged), `total_lines`, `total_required_base`, `cin7_updated`, `imported_at`, `last_polled_at`, `notified_at`, `updated_at`.
⚠️ 3단계에서 **needs_review 컬럼 신설 권장**(현재 completion_type=완료용이라 유입시점 확인필요와 별개).

### wms_order_lines — 오더 라인 (base 정규화 + import 시점 스냅샷)
`id`, `order_id`(FK→wms_orders), `cin7_line_id`, `order_sku`, `base_sku`, `factor`(변형=unit, base=1), `ordered_qty`, `required_base`(=qty×factor), 스냅샷: `product_name`/`image_url`/`bin_location`/`zone`/`is_selling`/`scannable_barcodes`(jsonb)/`line_flag`, `created_at`.

### wms_pick_tasks — 픽 배치 (오더 분할 단위 + wave 멤버)
`id`, `order_id`(FK), `batch_label`(예 SO-12345-1), `assigned_to`, `drop_location`(FK→wms_drop_locations.location_code), `status`(pending/in_progress/completed), `created_at`/`started_at`/`completed_at`, `heartbeat_at`, `work_started`(bool). **wave 컬럼(2026-07-22, `wms_waves.sql`)**: `wave_id`(FK→wms_waves, NULL=평범한 split 배치), `tote_no`(int, wave 내 물리 토트 슬롯 1..10). 인덱스 `idx_picktasks_wave`(부분, wave_id not null).

### wms_pick_task_lines — 픽 배치 라인
`id`, `pick_task_id`(FK), `order_line_id`(FK→wms_order_lines), `assigned_base`, `picked_base`(스캔 누적), `status`(pending/in_progress/picked/short), `verification_method`(scanned_variant/scanned_base/manual), `created_at`/`picked_at`.

### wms_pack_tasks — 팩 배치 (픽 배치 1:1 파생)
`id`, `order_id`(FK), `pick_task_id`(FK, 1:1), `batch_label`, `assigned_to`, `status`(pending/in_progress/completed), `created_at`/`started_at`/`completed_at`.

### wms_pack_task_lines — 팩 배치 라인 (팩커 재스캔 검수)
`id`, `pack_task_id`(FK), `order_line_id`(FK), `expected_base`, `verified_base`(재스캔 누적), `status`(pending/in_progress/verified/mismatch), `verification_method`, `created_at`/`verified_at`.

### wms_pallets — 팔렛
`id`, `pallet_label`, `warehouse`, `status`(building/completed), `weight_note`, `height_note`, `created_at`/`completed_at`.

### wms_pallet_items — 팔렛 항목 (항목단위 배정)
`id`, `pallet_id`(FK), `pack_task_id`(FK), `order_id`(FK), `drop_location`, `label`, `note`, `created_at`. 재배치=pallet_id만 변경, 부분이동=item split.

### wms_discrepancies — ⚠️ 불일치 미해결 큐 (가장 중요)
컬럼 (2026-08-04 실물 DB 확인): `id`, `order_id`(FK, **NULL 허용** — 리시빙), `order_number`, `sku`, `ordered_base`, `actual_base`, `reason`(text — ⚠️ **2026-08-06 부터 CHECK 있음**, 아래), `cin7_corrected`(bool, backend가 Cin7 수정 완료 체크), `resolved_by`, `resolved_at`, `created_at`, `responsible`(⚠️ **실수 귀속 전용** — Stats mistake tally 가 이 컬럼으로 센다), `source`(picking/packing/receiving — pick/pack 의 옛 행은 null), `po_number`, `receipt_id`, `declared_by`(2026-08-04, stock_short 선언자 — 감사, 시각은 created_at). 부분인덱스 `where cin7_corrected=false`(미해결만 빠른 조회) + 전체 유니크 `uq_disc_receipt_sku(receipt_id, sku)`.
`reason` 실제 값: `short_pick`(픽커 부족, responsible 미설정) / `short_after_pack`(팩 후 부족, responsible=picker) / `over_pick`(진짜 초과, responsible=picker) / `resolved_pack_recovery`(팩커가 채워 해소) / **`stock_short`(재고 불일치 선언 — 실수 아님, responsible=null·declared_by 기록, 2026-08-04)** / **`pack_scan_mistake`(팩커 중복 스캔 자백 — 선해소 insert, responsible=null, 2026-08-04)** / `recv_over`·`recv_short`·`recv_off_po`(리시빙).
- ⚠️⚠️ **`reason` CHECK (2026-08-06, `20260806000000_receipts_uq_disc_reports_checks.sql`)** — 위 9개 값만 허용(코드 전수 조사와 일치 · admin REASON_LABEL 에만 있던 `pack_mismatch` 는 insert 코드·데이터 모두 없어 제외 — 사용자 결정). NULL 은 통과. **새 reason 추가 = CHECK 를 바꾸는 마이그레이션이 코드보다 먼저** — 안 나가면 첫 insert 가 400(23514) 으로 죽고, EF 리시빙 선기록이면 Apply 중단(규칙 27 R12).

## 복제 테이블 2개 (BQ→Supabase, 길 A)

### wms_sku_snapshot — SKU 1줄
`sku`(PK, 오더SKU 기준 조회), `base_sku`, `is_variant`(bool), `factor`(int), `product_name`, `barcode`, `is_selling`(bool), `image_url`, `scannable_barcodes`(jsonb `[{barcode,factor,type}]`), `synced_at`. 인덱스 `idx_snapshot_base`.

### wms_sku_bins — SKU × bin (SKU당 여러 행)
`id`(PK), `sku`, `warehouse`(정규화 toronto/edmonton), `warehouse_raw`(Cin7 원문), `bin`, `zone`(bin에서 파싱), `on_hand`, `available`, `is_current`(sticky: 과거자리 false), `synced_at`. 인덱스 `idx_skubins_sku`, `idx_skubins_wh_zone`.

두 복제테이블은 FK로 안 묶고 `sku` 문자열로 느슨하게 연결(truncate+재적재 순서 자유).

## wms_staff — 직원/권한 (인증의 진실, 2026-07-19 추가)
`id`(PK), `name`, `email`(unique, Auth 이메일과 매칭), `role`(worker/manager/admin), `warehouse_access`(toronto/edmonton/both), `active`(bool), **`perms`(jsonb, `wms_staff_perms.sql`, 기본 `["split","admin","staff"]`)**, `created_at`, `updated_at`. 20행. 로그인=Auth 이메일→이 행 조회→role/warehouse_access/perms 사용. Edmonton: Jan Ko/Joon Kwon/Jeff Shim. admin=Caleb. manager: Ho Kang/Ted Shin/Changmo Ku/Jan Ko.
- **`perms`** = 매니저 화면권한(split=Order Splitting, admin=Admin, staff=Staff Management). admin 역할=항상 전부, worker=무관. wms-auth `requirePerm`이 화면별로 게이트.

## wms_orders — Finalize 통계 컬럼 (2026-07-21 추가, `wms_fulfillment_stats.sql`)
기존 컬럼에 더해: **`fulfillment_type`**(packing_list=팔렛/박스 구성 후 완료 / direct=직접출고·픽업, 팩킹리스트 없음), **`finalized_by`**(완료 작업자), **`finalized_at`**(완료 시각, 통계 기준). ⚠️ Finalize 시 status는 `closed`로 저장하고 화면에서만 "Finalized"로 표시(status enum 제약 회피). 인덱스 `idx_orders_finalized`(부분).

## wms_reports — 워커 데이터품질 리포트 (2026-07-21 추가, `wms_reports.sql`)
`id`(PK), `order_id`(FK, **nullable** — 리시빙 리포트는 null), `order_number`, `sku`, `kind`(`wrong_location`/`barcode_mismatch`/`image_mismatch`/`box_barcode`), `note`(상세 예 "Listed bin A1-02 · found at B3-04" — **박스 바코드 스캔 값도 여기 담긴다**), `reported_by`(작업자), `source`(picker/packer/receiver), `resolved_by`, `resolved_at`, `created_at`, **`receipt_id`/`po_number`(2026-08-05, `20260805200000_reports_receiving.sql` — 리시빙 귀속, wms_discrepancies 전례와 동일 구조 · ⚠️ 현장 미검증)**. **discrepancy(재고수량) 큐와 분리.** picker=wrong_location+barcode_mismatch+image_mismatch, packer=barcode_mismatch+image_mismatch, receiver=barcode_mismatch+box_barcode+image_mismatch. admin Reports 탭에서 리뷰/resolve(kind 필터). 인덱스 `idx_reports_open`(부분)·`idx_reports_order`·`idx_reports_receipt_open`(부분, 2026-08-05). RLS auth_all.
- ⚠️ **2026-08-06 정정 — `kind` 에 CHECK 가 생겼다** (`20260806000000_receipts_uq_disc_reports_checks.sql` — wrong_location·barcode_mismatch·image_mismatch·box_barcode 4개). 종전 기록("CHECK 제약이 없다 → 새 kind 는 앱 코드만으로")은 **그날까지만 사실**이다. **새 kind 추가 = CHECK 를 바꾸는 마이그레이션이 코드보다 먼저** — 안 나가면 첫 insert 가 400(23514) 으로 죽는다. 실물 확인은 규칙 29 대로 `pg_constraint` 조회.
- **`image_mismatch`(2026-07-30)** — 화면 이미지 ≠ 실물. 토글형: note 는 코드가 `Image does not match the physical product` 고정 생성, 다시 누르면 **미해결 행 delete**. 불변식 = **order_id+sku+kind 당 미해결 1행**(⚠️ DB 제약 아님, 앱 레벨 — 밀리초 동시진입은 이론적 예외). picker wave 는 라인별 `_orderId` 로 귀속.

## wms_rollback_log — 롤백 감사 (2026-07-21, `wms_rollback_log.sql`)
`id`(PK), `order_id`, `order_number`, `action`, `from_stage`, `to_stage`, `performed_by`, `note`, `created_at`. admin Rollback 탭이 단계 되돌릴 때 기록. 한 단계씩 최심단계만(Undo Fulfillment→Undo Pack→Reset Pick→Undo Split). discrepancy는 자동삭제 안 함.

## wms_discrepancies — note 컬럼 (⚠️ 2026-08-04 정정 — 존재하지 않는다)
이 문서가 "`wms_discrepancy_note.sql`로 `note` 추가됨(미사용/무해)"이라고 적어 왔으나 **실물 DB 에 note 컬럼이 없다**(2026-08-04 information_schema 직접 조회 — baseline dump 에도 없음). admin `discRow` 가 `d.note` 를 참조하지만 undefined 라 표시가 안 될 뿐 무해해서 드러나지 않았다. **규칙 29(문서 말고 실물 DB)의 또 한 사례.** 선언자 기록이 필요했던 2026-08-04 작업은 note 재사용 대신 `declared_by` 신규 컬럼으로 갔다.

## wms_waves — 소량 오더 그룹 (2026-07-22, `wms_waves.sql`)
`id`(PK), `label`(unique, `W-MMDD-n`), `warehouse`(toronto/edmonton, wave당 한 창고), `status`(pending/in_progress/completed), `assigned_to`(wave 잡은 픽커), `created_by`, `created_at`/`started_at`/`heartbeat_at`/`completed_at`. RLS auth_all. 인덱스 `idx_waves_status`.
- **그룹핑 레이어일 뿐** — 각 소량 오더는 여전히 자기 `wms_pick_tasks` 행(batch_label=`{order_number}-1`)을 갖고 `wave_id`+`tote_no`로 이 wave에 소속. wave 완료 = 멤버 pick_tasks 전부 completed + wave 행 completed 동시. 하류(pack/fulfillment/rollback)는 평범한 pick 배치로 취급(규칙 18). 픽커 heartbeat는 wave 행 + 멤버 태스크 동시 갱신.

## wms_health_check() — 불변식 검증 함수 (2026-07-22, `wms_healthcheck.sql`)
테이블 아님(함수). `returns table(sort,check_key,category,title,hint,fail_count,sample jsonb)`, `security definer`+`set search_path=public`, authenticated grant, 읽기 전용, `create or replace`. admin Health 탭이 `sb.rpc("wms_health_check")`로 호출. 검사 12개(각 CTE: bad_math/factor_drift/split_bad/short_no_disc/pick_over/progress_leak/dup_sale/finalize_recon/orphan_pick/orphan_pack/wave_state)+info 1(last_import). fail_count=0이 건강, sample=위반 최대 8행. ⚠️ orphan_pack은 pack의 짝 pick(`pick_task_id`)이 completed 아닐 때만(배치 병렬 정상케이스 오탐 방지). 규칙 19.

## RLS (2026-07-19 ON)
wms_ 테이블 전부(신규 wms_reports·wms_rollback_log·wms_waves 포함) `rowsecurity=true` + 정책 `auth_all`(`for all to authenticated using(true) with check(true)`). anon 거부, authenticated 전체허용. service_role 우회(GAS 동기화·Edge Function). `wms_health_check()`는 `security definer`라 RLS 강화돼도 전 테이블 읽음. 세분화(매니저만 쓰기)는 백로그.

## 인덱스 (운영)
idx_orders_status, idx_orders_progress, idx_lines_order, idx_lines_base_sku, idx_lines_zone, idx_picktasks_order, idx_picktasks_assignee, idx_pticklines_task, idx_pticklines_orderline, idx_packtasks_order, idx_packtasks_pick, idx_packlines_task, idx_palletitems_pallet, idx_disc_unresolved(부분).

## 참고 — asung_product_master 스키마 (BQ, 복제 소스)
sku, product_name, brand, supplier_name, supplier_sku, cost_price(FLOAT), category, is_active(BOOL=Status Active), is_selling(BOOL=Sellable, ≠is_active), barcode, unit(STRING=factor 소스), weight(FLOAT), product_attribute, registered_on(DATE), synced_at(TIMESTAMP). ProductMasterSync.gs(=Productmaster.gs)가 관리.

## 리시빙 테이블 (2026-07-23, wms_receipts.sql + wms_receipts_apply.sql)

**wms_receipts** — PO/트랜스퍼 단위 리시빙 세션. "PO 1개 = receipt 1개"(분할 배송도 한 행에 누적).
id BIGINT PK · po_number TEXT NOT NULL (PO-xxxxx / TR-xxxxx) · cin7_purchase_id TEXT (PO GUID/TR TaskID — 안정 키, 열린 receipt dedup) · supplier_name TEXT · warehouse TEXT NOT NULL default 'toronto' CHECK(toronto/edmonton) · status TEXT CHECK(in_progress/held/partial/completed) · **source_type TEXT default 'po' CHECK(po/transfer)** · received_by TEXT · note TEXT · **applied_at TIMESTAMPTZ / applied_by TEXT / apply_note TEXT** (Apply to Cin7 성공 기록 = 이중 반영 방지 키) · created_at/updated_at/completed_at.
인덱스: idx_receipts_status(status, created_at desc), idx_receipts_po(po_number).
⚠️ **`cin7_purchase_id` 전체 유니크 (2026-08-06, `20260806000000_receipts_uq_disc_reports_checks.sql` — 규칙 27 R3)**: `wms_receipts_cin7_purchase_id_key`. WHERE 없는 전체 유니크(규칙 29 — 부분 인덱스는 on_conflict 추론 불가)·NULL 은 NULLS DISTINCT. ⚠️ **트랜스퍼 행도 걸린다** — receiver.html 이 PO/TR 공통으로 `cin7_purchase_id` 에 GUID/TaskID 를 저장(2026-08-06 코드 확인). 롤백(행 삭제) 후 재수령은 막지 않는다. startPo 의 앱 레벨 dedup 이 1차, 이 유니크는 밀리초 동시 진입의 마지막 방어선.
status 의미: held=중단(진행 저장, PO 열림) / partial=이번 배송분 끝(PO 열림, 분할배송) / completed=최종(Apply 대상).

**wms_receipt_lines** — 라인별 예상 vs 실제 + 풋어웨이 + 승인.
id BIGINT PK · receipt_id FK cascade · cin7_po_line_id TEXT · order_sku/base_sku/product_name · expected_base NUMERIC (PO 예상 낱개, 오프-PO=0) · received_base NUMERIC (받은 누적 낱개) · exported_base NUMERIC (**2026-07-28 부터 트랜스퍼 bin 이동 체크포인트** — 이미 Cin7 에 옮긴 낱개. 재Apply 때 이 라인을 건너뛰는 유일한 근거이므로 ⚠️ **사람이 수동 UPDATE 하지 말 것**(규칙 30-4). PO 경로는 아직 미사용) · putaway_bin TEXT (자동확정/수동 bin) · zone TEXT (가이드 동선 정렬) · putaway_done BOOL · is_off_po BOOL · needs_approval BOOL (승인 전 풋어웨이·Apply 차단) · approved_by/approved_at · verification_method(scanned/manual) · status(pending/received).
인덱스: idx_receipt_lines_receipt, idx_receipt_lines_base, idx_receipt_lines_export(부분 — 구 CSV 용, 현재 미사용).
RLS: 다른 wms_ 테이블 동일(auth_all).

**wms_sku_bins.last_seen DATE** (2026-07-23 추가) — 추천 빈 타이브레이커. BQ asung_bin_stock.last_seen 복제(WmsSync wms_buildBins_ 에 CAST(last_seen AS STRING) 추가). sticky MERGE 가 sold-out 행의 last_seen 을 갱신 안 함 = "마지막 재고 있던 날" 고정. 보조 인덱스 idx_sku_bins_recommend(sku, warehouse, is_current desc, last_seen desc).

## 리시빙 관련 2026-07-24 노트

- **wms_receipts.applied_at 이 마스터 게이트**: 있으면 = Cin7 반영 완료. Resume 목록·열기·재개·재Apply 모두 이걸로 차단. Apply 성공 시 status='completed' 도 같이 세팅(applied 인데 in_progress 로 꼬임 방지).
- **한 PO = receipt 1개**: 앱 레벨 방지(startPo 가 cin7_purchase_id 로 기존 전체 조회). 완벽한 동시성 방지는 부분 유니크 인덱스가 필요하나 실무엔 앱 레벨로 충분(밀리초 동시진입만 이론적 예외).
- **asung_bin_stock (BQ, sticky) first_seen 시작 = 2026-07-06**. 그 전 0-된 bin 은 소급 불가(Cin7 productavailability 가 0-bin 안 줌). "no last bin" 다수의 원인. bin 단위 과거이력은 Cin7 movements 에만.
- **Cin7 stock received 제약(실측)**: 문서당 bin 1개 / 같은 SKU+bin 중복 불가 / authorize 는 POST. (상세 SKILL 규칙 21)

## 2026-07-25 추가 컬럼

- `wms_pick_tasks.held_by` / `wms_pack_tasks.held_by` / `wms_waves.held_by` (text) — Hold 한 사람. `wms_held_by.sql`
- `wms_discrepancies`: `order_id` **NULL 허용으로 변경**(리시빙 차이는 sales order 없음) + `source`(pick/pack/receiving) + `po_number` + `receipt_id`(bigint) + 유니크 `uq_disc_receipt_sku(receipt_id, sku)`. `wms_disc_receiving.sql`
  - ⚠️⚠️ **2026-07-29 정정 (규칙 29)** — 원래 이 인덱스는 `WHERE receipt_id IS NOT NULL` **부분** 유니크였고, **PostgREST `on_conflict` 는 부분 인덱스를 추론하지 못한다** → EF 의 `POST wms_discrepancies?on_conflict=receipt_id,sku` 가 **400 `42P10 there is no unique or exclusion constraint matching the ON CONFLICT specification`** 으로 실패했고, 그래서 **리시빙 discrepancy 가 구현 이후 한 번도 기록되지 않았다.** **WHERE 절 없는 전체 유니크로 교체**했다(pick/pack 행은 `receipt_id` 가 NULL 이고 유니크는 기본 **NULLS DISTINCT** 라 무영향). SQL = `supabase/wms_disc_uq_fix.sql` (⚠️ 마이그레이션 아님 — 같은 내용을 새 마이그레이션으로 담아야 로컬·원격이 정렬된다).
- `wms_orders.reference` (text) — Cin7 화면 Reference(=API CustomerReference), 픽리스트 인쇄용. `wms_order_reference.sql`

## 2026-08-02 추가 — 픽리스트 Order Date (`supabase/migrations/20260802000000_wms_order_date.sql`)

- `wms_orders.order_date` (**date**, nullable) — Cin7 화면 "Order Date" = API `OrderDate`. 픽리스트 인쇄용. 폴링 EF(`hello`)가 `(d.OrderDate || c.OrderDate).slice(0,10)` 로 채운다(상세 우선, 목록 폴백).
- ⚠️ **신규 유입분부터만 찬다** — 기존 행은 null(소급 백필 안 함). 인쇄 3경로가 값 없으면 줄/열을 생략하므로 안전.
- ⚠️ 규칙 23 순서: **컬럼 먼저, EF 나중.** 컬럼 없이 EF 가 이 키를 실으면 `wms_orders` insert 가 통째로 실패해 **오더 유입이 전면 중단**된다(개별 라인 실패가 아니다).

## 2026-08-04 추가 — 실수 vs 재고 불일치 구분 (`supabase/migrations/20260804000000_disc_stock_short.sql`)

- `wms_discrepancies.declared_by` (text) — `stock_short`/`pack_scan_mistake` 의 선언자(감사용, 시각은 `created_at`). ⚠️ `responsible` 재사용 금지 — responsible 은 mistake tally 가 세는 컬럼이라 선언자가 실수로 집계된다.
- **정책**: "재고 부족 선언(stock_short)"은 실수를 지우는 것이 아니라 **재분류**다 — 주문은 여전히 부족 출고, Cin7 재고와 실물의 차이는 큐에 남아 매니저가 Cin7 에서 수동 조정("Cin7 Fixed"). 리시빙 discrepancy 와 같은 흐름 = 남용해도 매니저가 bin 확인 단계에서 걸러진다.
- 같은 마이그레이션이 **규칙 29 응급 수정분을 정착**시킨다: `uq_disc_receipt_sku` 를 WHERE 없는 전체 유니크로 재생성(멱등 — 원격엔 이미 적용됨, 이걸 안 담으면 새 환경/`db reset` 때 부분 유니크로 되돌아가 on_conflict 42P10 이 재발한다).
