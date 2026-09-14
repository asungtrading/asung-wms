# Product 마스터 엔드포인트 레퍼런스

## Product — GET /product

제품 마스터 데이터. 페이지네이션 지원. 재고 현황은 `/ref/productavailability` 사용.

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `ID` | Guid | 특정 Product ID 조회 |
| `Name` | string | 제품명 포함 검색 (contains) |
| `Sku` | string | SKU 포함 검색 (contains) · ⭐ **먹는다**(2026-09-14 실측 — `?Sku=AS91437-BLK` 가 그 한 건을 정확히 돌려줬다 · 문서상 contains 이므로 정확 일치는 받은 뒤 SKU 로 걸러라) |
| `ModifiedSince` | DateTime | 이 날짜 이후 수정된 제품 (UTC ISO 8601) |
| `IncludeDeprecated` | bool | 비활성 포함 여부 (기본값 false) |
| `IncludeBOM` | bool | Bill of Materials 포함 (기본값 false) |
| `IncludeSuppliers` | bool | 공급업체 정보 포함 (기본값 false) |
| `IncludeMovements` | bool | 재고 이동 이력 포함 (기본값 false) |
| `IncludeReorderLevels` | bool | 재주문 레벨 포함 (기본값 false) |
| `IncludeCustomPrices` | bool | 고객별 특수가격 포함 (기본값 false) |

**주의**: `IncludeMovements=true`는 응답이 매우 커질 수 있음. 필요할 때만 사용.

### 응답 구조 (핵심 필드)
```json
{
  "Total": 500,
  "Page": 1,
  "Products": [
    {
      "ID": "guid",
      "SKU": "PROD-001",
      "Name": "제품명",
      "Category": "Hair Care",
      "Brand": "브랜드명",
      "Type": "Stock",
      "Status": "Active",
      "Barcode": "829534000001",
      "UOM": "EA",
      "DefaultLocation": "Toronto Warehouse",
      "AverageCost": 12.50,
      "PriceTier1": 25.00,
      "PriceTier2": 23.00,
      "PriceTiers": {
        "Wholesale": 25.00,
        "Distributor": 23.00
      },
      "MinimumBeforeReorder": 10,
      "ReorderQuantity": 100,
      "Tags": "haircare,popular",
      "PickZones": "Zone1",
      "StockLocator": "A0101",
      "LastModifiedOn": "2024-01-15T00:00:00Z",
      "Suppliers": [],
      "ReorderLevels": []
    }
  ]
}
```

### Suppliers 서브 필드 (IncludeSuppliers=true 시)

> **필드명 실측 확정 (2026-07-10, SKU AS92900 / Intervision China USD).**
> 이전 문서의 `Price` 필드는 존재하지 않음 — 아래가 실제 응답 구조.

```json
"Suppliers": [
  {
    "ProductSupplierID": "guid",
    "SupplierID": "guid",
    "SupplierName": "공급업체명",
    "ProductID": "guid",
    "Cost": 1.0,            // 화면의 LATEST PRICE (최근 매입가)
    "FixedCost": 0.5332,    // 화면의 FIXED PRICE (합의 고정가)
    "PurchaseCost": 0.5332, // FixedCost와 동일 값으로 옴
    "Currency": "USD",      // 공급사 통화
    "LastSupplied": "2025-10-02T00:00:00",
    "DropShip": false,
    "SupplierInventoryCode": null,
    "SupplierProductName": null,
    "SupplierProductURL": null,
    "IncludeInPricing": true,   // ⭐ [2026-09-14 실측 추가] 전량에 있다 · false 0 (2026-09-14 실측)
    "ProductSupplierOptions": [ // Location별 Lead/Safety/Reorder 설정 — ⚠️ 아래 정정
      { "ID": "guid", "LocationID": "guid", "LocationName": "Toronto Warehouse",   // ⭐ [2026-09-14] LocationName 도 온다
        "ReorderQuantity": 0, "Lead": 0, "Safety": 0, "MinimumToReorder": 0, "SupplyIntervals": [] }
    ]
  }
]
```
⭐ **[2026-09-14 전량 실측 — IMS ④ · 정본 `po-module.md` §3-g]** Type=Stock 줄 12,728.
- ⚠️⚠️ **`ProductSupplierOptions[]` 에 `Default` 가 GET 응답에 오지 않는다.** `PUT /product-suppliers` 규칙 3은 `Default:true` 정확히 1개를 요구하므로
  **GET 을 그대로 되돌려보내면 반드시 실패한다** — 우리가 만들어 붙여야 한다(`product-suppliers-write.md` 규칙 3·6).
- ⭐ **「기본 공급처」 표시가 응답 어디에도 없다**(Suppliers[] · Options[] 모두 Default·Primary 류 칸 없음) — IMS 는 우리 칸 `is_default` 로 만든다.
- 창고별 옵션은 10,637줄에 4개씩 달려 있으나 Lead·Safety·ReorderQuantity **전량 0**(MinimumToReorder 만 2줄) — Cin7 에서 쓰지 않는 칸.
- 채움: Cost>0 11,360 · FixedCost>0 8,921 · 둘 다 0 1,232 · 소수 **일곱 자리**(1.3991666) · SupplierInventoryCode 6,981 · LastSupplied 빈 99 ·
  SupplierProductName·URL·DropShip 0 · Currency CAD 1,584 · USD 11,144(공급처 기본통화와 어긋남 0) · SupplierID 가 비활성 공급처 787줄(31곳) · 모르는 GUID 0.

**발주 단가로 쓸 때 폴백:** `FixedCost`(>0) → `Cost`(>0) → 없음(0 처리 + 사람 확인).
DRAFT PO 생성 시 이 값을 라인 Price로 넣음 (Cin7은 API 생성 시 가격 자동채움 안 함 —
`references/purchase-write.md` 참조).
**이 값들을 API로 수정하려면 `references/product-suppliers-write.md` 참조** (PUT 스키마 실측 확정).

### ReorderLevels 서브 필드 (IncludeReorderLevels=true 시)
```json
"ReorderLevels": [
  {
    "LocationID": "guid",
    "Location": "Toronto Warehouse",
    "MinimumBeforeReorder": 20,
    "ReorderQuantity": 100
  }
]
```

---

## Apps Script 예시 — 전체 활성 제품 SKU 목록 가져오기

```javascript
function getAllActiveSkus() {
  const products = fetchAllPages('product', {
    IncludeDeprecated: false
  });
  // 반환 키: Products (복수형, 대문자 P)
  return products.map(p => ({
    id: p.ID,
    sku: p.SKU,
    name: p.Name,
    brand: p.Brand,
    category: p.Category,
    status: p.Status,
    barcode: p.Barcode,
    avgCost: p.AverageCost
  }));
}
```

## Apps Script 예시 — 공급업체별 제품 목록 (purchasing.html 연동용)

```javascript
function getProductsBySupplier(supplierName) {
  const products = fetchAllPages('product', {
    IncludeSuppliers: true,
    IncludeDeprecated: false
  });
  
  return products.filter(p => 
    (p.Suppliers || []).some(s => s.SupplierName === supplierName)
  );
}
```

## Apps Script 예시 — 최근 수정된 제품만 동기화 (BigQuery 증분 업데이트)

```javascript
function syncModifiedProducts(lastSyncDate) {
  return fetchAllPages('product', {
    ModifiedSince: lastSyncDate,  // ISO 8601
    IncludeDeprecated: true       // Deprecated 포함해야 삭제 감지 가능
  });
}
```

---

## 주의사항
- 응답 배열 키: `Products` (대문자 P, 복수형) — `ProductList`가 아님
- `Name` 파라미터는 **contains** 검색 (Customer/Supplier의 startsWith와 다름)
- `AverageCost`는 read-only (FIFO/FEFO 기반 자동 계산)
- **공급사 단가는 `Suppliers[].Cost`(최근가)와 `Suppliers[].FixedCost`(고정가)** — `Price` 필드 아님(실측 확정)
- `PriceTiers` 객체는 실제 PriceTier 이름을 키로 사용 (`Tier 1`, `Wholesale` 등 계정 설정에 따라 다름)

---

## 2026-09-11 표본 실측 (Total 14,677 · 30행 표본 · GAS 프로브 · IMS PO 모듈 ③ 제품 표 설계 근거)

```
배열 키 Products  ·  필드 83개
CostingMethod   30행 전부 FIFO
UOM 빈값        0/30
⭐ Brand·Category·UOM 이 ref/brand·ref/category·ref/unit 의 Name 과 일치 100% · GUID꼴 0건 — 이름 문자열 참조
⭐ 제품이 계정과목을 넷 참조한다 — InventoryAccount · COGSAccount · RevenueAccount · ExpenseAccount (ref/account 의 Code)
📌 HSCode · CountryOfOrigin 칸이 있다
```
⚠️⚠️ **제품이 아닌 항목이 섞여 있다** — SKU 가 `[:[OrderTotalDiscount]:]` · `_1_` · `_10_` · `_10767_` 같은 것들(Type=Service 등).
⭐ Caleb 확인: **`_숫자_` 형식은 우리 제품이 아니다.** 목록이 SKU 순 정렬이라 **앞쪽에 몰려 있다** — 앞 몇 페이지만 보고 판단하면 틀린다.

~~⬜ **`product?IncludeSuppliers=true` 는 미확인** — 표본 5행이 전부 시스템 항목이라 `Suppliers` 가 0 이었다.~~
⭐ **[2026-09-13 정정] 미확인이 아니다 — 이미 매일 돌고 있다.** `gas-system-automation/Productmaster.js` 가 `IncludeSuppliers=true` 로 전량을 긁어
BQ `asung_product_master` 에 `supplier_name`·`supplier_sku`·`cost_price` 를 넣는다. 위 「Suppliers 서브 필드」가 그 실측(2026-07-10)이다.
표본 5행이 시스템 항목이라 0 이었을 뿐 — 「없다」「안 봤다」 다음의 셋째 부류 **「이미 있는데 안 찾아봤다」**.

---

## 2026-09-13 전량 실측 (IMS PO 모듈 ③ 제품 — 정본 `docs/design/po-module.md` §3-d)

### `GET /product` 전량 — `IncludeDeprecated=true`
```
Total    IncludeDeprecated=false 14,677 · =true 18,829 (비활성 4,152)   ⚠️ 기본값은 활성만이다
Limit    ⭐ 1000 먹는다 (19페이지 · 1분 47초) — 함정 16(기본 100)
         ⚠️⚠️ IncludeBOM=true 를 켜면 Limit=500 이 실효 상한 (1000 을 보내도 안 온다 · 38페이지 · 2분 42초 · 적재 스크립트 IPR_LIMIT=500 이 그 때문 · 2026-09-14 재확인)
         ⭐ IncludeSuppliers=true 는 1000 이 먹는다 (2026-09-14 실측 · 19페이지 · 107초) — 500 상한은 BOM 만이다
Sku      ⭐ 먹는다 (2026-09-14 실측 · GET /product?Sku=AS91437-BLK → 그 한 건 · IMS ③ 적재의 imsLoadProductExtra 가 쓴다)
칸       83 (모든 행에 다 있다)
Type     Stock 18,772 · Service 53 · Non Inventory 4 (함정 17 — 공백)
SKU      중복 0 · 빈값 0 · 앞뒤공백 0   Name 576종 중복   Barcode 48종 중복
Brand·Category·UOM·계정 넷  ref/ 목록의 Name(계정은 Code)과 100% 이어진다 · 계정 채움은 5 · 3 · 1,103 · 870 곳뿐
```

### Include 파라미터 실측
```
IncludeBOM=true           ⭐ 먹는다. BillOfMaterialsProducts[] 원소: ComponentProductID · ProductCode · Name · Quantity · WastagePercent · WastageQuantity · CostPercentage
                          ⚠️ SKU 가 아니라 ProductCode 다
                          ⚠️⚠️ BOMType=Assembly 6,422 중 진짜 조립은 15 — UOM 을 만들면 Cin7 이 자동으로 Assembly 로 바꾸고 구성품 1개(낱개 ×N)를 채운다.
                             구성품 1개 6,406 · 2개 이상 15 · 없음 12,408. 가르는 기준은 BOMType 이 아니라 **구성품 수**.
                          ⭐⭐ 세트 계수의 정본은 BOM Quantity 다 — Cin7 이 재고를 빼는 수. UOM 이름은 화면 표시.
                             실측: 숫자UOM · BOM · SKU 접미사 셋 일치 6,340 · 어긋남 3 (AIA00207-6·ORS12208-6 UOM=6/BOM=1 → 재고가 1개만 빠졌다 · AMP41108-12 접미사만 틀림)
                          ⚠️ [2026-09-14] AutoAssembly·AutoDisassembly 로는 **조립 방향**(낱개로 사서 우리가 묶는다 / 디스플레이로 사서 우리가 가른다)을 가를 수 없다 —
                             콤보 15 전수 AutoAssembly true · AutoDisassembly false 한 모양 · AssemblyInstructionURL 빈 문자열 · AssemblyCostEstimationMethod 전부 Average Cost
                             (ProbeProductSupplier.gs psp_step10_bomdirection · 정본 po-module §3-g). IMS 는 공급처 줄 유무로 판정하고 방향 칸은 ⑤ 에서 만든다
IncludeMovements=true     ⭐ 먹는다. Movements[] 원소: TaskID · Type · Date · Number · Quantity · Amount · Location · BatchSN · ExpiryDate · FromTo
IncludeAttachments=true   ⭐ 먹는다 (끄면 빈 배열 · 켜면 1개). GET /product/attachments?ProductID= 도 같은 내용
IncludeReorderLevels=true ⭐ 먹는다. ReorderLevels[] 원소: LocationID · LocationName · MinimumBeforeReorder · ReorderQuantity · StockLocator · PickZones
                          ⚠️ 실측 값은 전부 0 (낱개 활성 8,668 에서 흩어 뽑은 40/40 · 토론토 줄만) — 안 쓰고 있다
                          ⭐ StockLocator · PickZones 는 창고별 값 — 제품 본체의 그 두 칸은 대표값 하나
IncludeSuppliers=true     ⭐ 먹는다 · 위 「Suppliers 서브 필드」 · Productmaster.js 가 매일 쓴다
채널                      ⚠️ API 에 없다 — 후보 경로 일곱 전부 200 + HTML (함정 18)
```

### `GET /productFamily` 전량
```
파라미터   Page · Limit (⭐ 1000 먹는다 · 2페이지면 전량)
           ⚠️ IncludeDeprecated 는 Total 이 같아 판정 불가 — 변형 SKU 4,884 가 전부 제품 덤프에 있었으므로 「비활성 제품군 없음」쪽
배열 키    ProductFamilies          ⚠️ List 접미사 없음 (함정 19)
Total      1,141 · SKU 전부 …FAM 으로 끝난다(Caleb 이 예외 둘을 고친 뒤)
칸         44 (Products[] · Attachments[] 포함) · 33개가 제품 83칸과 겹친다 — 가격 10단계만 950/4,884 어긋나고 나머지(Brand·Category·계정·원산지)는 전수 일치
Products[] 원소     ID · SKU · Name · Option1 · Option2 · Option3
Attachments[] 원소  ID · ContentType · FileName · IsDefault · DownloadUrl
Option1Name 33종(Color 463 · Size 332 · Formula 69 · Type 52 · Style 46 · color 38 …) · Option2Name 13종 · Option3Name 1종(Quantity)
⚠️ Color/color · Size/size · Flavor/Flavour 가 따로 있다 — 정규화하지 않고 원문 그대로
```
