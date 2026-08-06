-- 제약 3종: wms_receipts 유니크 + wms_discrepancies/wms_reports CHECK (2026-08-06)
--
-- ① wms_receipts.cin7_purchase_id UNIQUE — 규칙 27 R3 (밀리초 동시 진입의 중복 receipt).
--    receiver.html startPo 의 앱 레벨 dedup(기존 receipt 조회 후 재개)이 1차 방어,
--    이 유니크가 마지막 방어선. 사전 실측 2026-08-06: 중복 0건 · status 는 completed/held 뿐
--    (롤백은 행을 삭제하므로 재수령을 막지 않는다).
--    ⚠️ 부분 유니크 금지(규칙 29 — PostgREST on_conflict 는 부분 인덱스를 추론하지 못한다)
--       → WHERE 절 없는 전체 유니크. NULL 은 NULLS DISTINCT 라 중복 허용.
--    ⚠️ 트랜스퍼 행도 cin7_purchase_id(TR TaskID)를 저장하므로(receiver.html:652 PO/TR 공통)
--       유니크가 트랜스퍼에도 걸린다 — startPo dedup 이 PO/TR 공통이라 정합(2026-08-06 확인).
--    이 컬럼을 on_conflict 로 쓰는 코드는 현재 없다(전수 확인 — EF 의 on_conflict 는
--    wms_discrepancies?on_conflict=receipt_id,sku 하나뿐).
--
-- ② wms_discrepancies.reason CHECK — 코드 전수 조사 9개 값
--    (picker/packer/receiver/fulfillment/admin + supabase/functions/**, 2026-08-06).
--    데이터 실측 8개 + 코드에만 있는 recv_off_po(미발생 — EF receiving:578).
--    admin REASON_LABEL 의 'pack_mismatch' 는 insert 코드·데이터 모두 없어 제외(사용자 결정).
--    NULL reason 은 CHECK 를 통과한다(기존 NULL 행 안전).
--
-- ③ wms_reports.kind CHECK — 4개 값. box_barcode 는 2026-08-05 신규(미발생이지만 코드에 존재
--    — receiver.html:1174). admin REPORT_KIND 4개와 일치.
--
-- ⚠️⚠️ 앞으로 새 reason/kind 분류를 추가하려면 CHECK 를 바꾸는 새 마이그레이션이 "먼저" 나가야 한다.
--    안 나가면 새 분류의 첫 insert 가 400(23514 check violation) 으로 죽는다 — 특히
--    EF 리시빙 discrepancy 선기록 실패는 Apply 중단이다(규칙 27 R12).
--    규칙 41 · references/schema.md 에 같은 내용 명시.

-- ① 전체 유니크 (drop 후 add = 멱등)
alter table public.wms_receipts
  drop constraint if exists wms_receipts_cin7_purchase_id_key;
alter table public.wms_receipts
  add constraint wms_receipts_cin7_purchase_id_key unique (cin7_purchase_id);

-- ② reason CHECK — 9개
alter table public.wms_discrepancies
  drop constraint if exists wms_discrepancies_reason_check;
alter table public.wms_discrepancies
  add constraint wms_discrepancies_reason_check check (reason in (
    'short_pick',              -- picker 부족 완료 (picker.html:1285)
    'short_after_pack',        -- 팩 후 부족 (packer.html:1258)
    'over_pick',               -- 진짜 초과, responsible=picker (packer.html:1280)
    'resolved_pack_recovery',  -- 팩커 보충으로 해소 — UPDATE 로 short_pick 을 교체 (packer.html:1294)
    'stock_short',             -- 재고 불일치 선언, 규칙 41 (picker.html:1203 · packer.html:1011)
    'pack_scan_mistake',       -- 팩커 중복 스캔 자백, 선해소 (packer.html:1286)
    'recv_over',               -- 리시빙 초과 (EF receiving:580)
    'recv_short',              -- 리시빙 부족 (EF receiving:582)
    'recv_off_po'              -- off-PO 수령 (EF receiving:578 — 미발생이지만 코드에 존재)
  ));

-- ③ kind CHECK — 4개
alter table public.wms_reports
  drop constraint if exists wms_reports_kind_check;
alter table public.wms_reports
  add constraint wms_reports_kind_check check (kind in (
    'wrong_location',    -- picker 전용
    'barcode_mismatch',  -- picker + packer + receiver
    'image_mismatch',    -- picker + packer + receiver (토글)
    'box_barcode'        -- receiver 전용 (2026-08-05 신규, 미발생)
  ));
