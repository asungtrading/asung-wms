# WmsSync.gs — BQ 마스터 → Supabase 복제 (길 A)

System_Automation 프로젝트의 신규 파일. 접두어 `WMS_`/`wms_`. `bs_select_`(Binstockdata.gs)·`getProp`·`startMonitor` 재사용.

## 진입점
- `runWmsMasterSync()` — 수동/트리거 진입. BQ 3테이블 조인 → 스냅샷+bin 빌드 → Supabase 2테이블 통짜교체.
- `setupWmsSyncTrigger()` — 매일 6:30 트리거(bin_stock 5시·master 6시 이후). ⚠️ 아직 미실행.

## 설정
```javascript
const WMS_CFG = {
  BQ_PROJECT: 'geometric-rock-487814-k4',
  MASTER: '`geometric-rock-487814-k4.Cin7_Master_Data.asung_product_master`',
  BINS:   '`geometric-rock-487814-k4.Cin7_Master_Data.asung_bin_stock`',
  IMAGES: '`geometric-rock-487814-k4.Cin7_Sales_Data.asung_product_images`',
  SUPABASE_URL: getProp('SUPABASE_URL'),         // 실행 시 로드
  SUPABASE_KEY: getProp('SUPABASE_SERVICE_KEY'), // GAS Script Property (Edge Function 자동주입과 별개)
  INSERT_BATCH: 500,
};
```

## 1) wms_buildSnapshot_() — SKU 스냅샷
- `MASTER LEFT JOIN IMAGES ON UPPER(TRIM(sku))` 로 sku·product_name·barcode·unit·is_selling·image_url 조회.
- factor = `parseInt(unit)` 유효>0이면 그 값, 아니면 1.
- is_variant = 첫 하이픈 있고 factor>1 (⚠️ unit 기준, 접미사 아님).
- base_sku = 변형이면 첫 하이픈 앞, 아니면 자기자신.
- scannable_barcodes 조립: 자기 바코드(factor,type=variant/base) + 변형이면 base 바코드(factor=1) + **ALT-UPC 별칭**(base에 묶인 `%-ALT-UPC` 레코드들, factor=1, type=alt).
- `%-ALT-UPC` 레코드 자체는 스냅샷에 안 넣음(별칭일 뿐).

ALT-UPC 조회 쿼리:
```sql
SELECT sku, barcode, UPPER(TRIM(REGEXP_EXTRACT(sku, r"^([^-]+)"))) AS base_u
FROM `...asung_product_master`
WHERE UPPER(sku) LIKE "%-ALT-UPC" AND barcode IS NOT NULL AND TRIM(barcode) <> ""
```

## 2) wms_buildBins_() — SKU × bin
```sql
SELECT sku, warehouse, bin, on_hand, available, is_current
FROM `...asung_bin_stock` WHERE bin IS NOT NULL AND TRIM(bin) <> ""
```
- warehouse 정규화: `/edmonton/i.test(raw) ? 'edmonton' : 'toronto'`. warehouse_raw엔 원문 보존.
- zone = `wms_zoneOf_(bin, wh)`.

```javascript
function wms_zoneOf_(bin, wh) {
  if (!bin) return '';
  if (wh === 'edmonton') return /^E[A-Z]/.test(bin) ? bin.charAt(1) : bin.charAt(0);
  return bin.charAt(0); // toronto
}
```

## 3) wms_replaceTable_(table, rows) — 통짜교체 (PostgREST)
```javascript
const hdr = { apikey: KEY, Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json' };
// (a) 전체삭제 — PostgREST는 조건없는 delete 막으므로 항상 참인 필터
const delUrl = base + '?' + (table === 'wms_sku_bins' ? 'id=gt.0' : 'sku=neq.__none__');
UrlFetchApp.fetch(delUrl, { method:'delete', headers: hdr, muteHttpExceptions:true });
// (b) 500개씩 배치 POST insert. jsonb 컬럼(scannable_barcodes)은 객체 그대로 두면 JSON.stringify가 직렬화.
```

## 검증 결과 (2026-07-18)
snapshot 14,534행 + bins 14,961행 재적재 성공. warehouse·zone 정규화 정확(EU020303→U, EZ010101→Z, ED020101→D). SO-13284 3라인 스냅샷+Edmonton bin 조회 성공.

## 재사용 가능 (Binstockdata.gs)
- `bs_select_(sql)` — BQ 동기 SELECT(REST /queries + 페이지네이션). CustomerPortal `_runBQ`와 동일 개념.
- products.json 생성부의 ALT-UPC→base 묶기 로직(base 첫하이픈앞 매칭 UNION + LIKE %-ALT-UPC).
- asung_bin_stock은 sticky MERGE(재고0도 is_current=FALSE 보존). `runBinStockSync()` 매일 5시.
