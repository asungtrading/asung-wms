# Product Suppliers 쓰기 — Fixed Price(공급사 단가) 갱신

> **출처: 2026-07-10 실측** (SKU AS92900, TSK00001 / 7단계 에러 디버깅으로 스키마 확정).
> 도움말 문서(help.core.cin7.com의 "Product Suppliers")는 **구버전 스키마**라 실제 v2와
> 완전히 다름 — payload 최상위 키, 레코드 구조, 필드명 전부 불일치. 이 문서가 실측 기준.

## 엔드포인트

| 동작 | 경로 | 비고 |
|------|------|------|
| 읽기 | `GET /product?Sku=..&IncludeSuppliers=true` | product-suppliers는 **GET 미지원(405)** — 읽기는 product로 |
| 쓰기 | `PUT /product-suppliers` | 하이픈 주의. `/productSuppliers`(카멜)는 404 |

## PUT 스키마 (실측 확정 — HTTP 200 성공 payload)

```json
{
  "ProductSuppliers": [
    {
      "ProductSupplierID": "9b5e6c8f-...",   // 연결 자체의 GUID — 필수
      "ProductID": "89f40669-...",
      "SupplierID": "ee595b45-...",
      "Cost": 1.0,                            // 화면 LATEST PRICE
      "FixedCost": 0.5332,                    // 화면 FIXED PRICE
      "DropShip": false,
      "ProductSupplierOptions": [
        { "ID": "337ecd50-...", "LocationID": null, "Default": true,
          "ReorderQuantity": 0, "Lead": 0, "Safety": 0,
          "MinimumToReorder": 0, "SupplyIntervals": [] },
        { "ID": "b6a85ec2-...", "LocationID": "623edcaa-...", "Default": false,
          "ReorderQuantity": 0, "Lead": 0, "Safety": 0, "SupplyIntervals": [] }
      ]
    }
  ]
}
```

성공 응답: `{"Success":true}`

## 실측 규칙 (에러 문구와 함께)

| # | 규칙 | 위반 시 에러 |
|---|------|-------------|
| 1 | 최상위 키는 `ProductSuppliers`, **평평한 연결 레코드 배열** (제품 안에 Suppliers 중첩 아님 — 문서와 다름) | "Nullable object must have a value" / "ProductSuppliers collection cannot be empty" |
| 2 | `ProductSupplierID` 필수 (GET /product 응답의 Suppliers[]에 있음) | "ProductSupplierID cannot be empty" |
| 3 | `ProductSupplierOptions` 포함 필수, **Default:true 정확히 1개** (LocationID null인 행) | "Only one Default value is allowed and required in options of product ..." |
| 4 | `MinimumToReorder`는 **Default 옵션에만** 포함 (다른 Location 옵션에 넣으면 400) | "Only Default option ... may have MinimumToReorder attribute set" |
| 5 | **옵션이 아예 없는 SKU 존재** (UI에서 Location 설정 안 한 제품, 실측 TSK00001) → 기본 Default 행을 생성해서 보낼 것: `{LocationID:null, Default:true, 나머지 0, ID 없이(신규)}` | 규칙 3과 동일 에러 |
| 6 | null 값 필드(SupplierInventoryCode, SupplierProductName 등)는 payload에서 제외 — GET 응답을 통째로 되돌려보내면 실패 | "Nullable object must have a value" |
| 7 | 필드 매핑: **`FixedCost` → 화면 FIXED PRICE / `Cost` → 화면 LATEST PRICE** — 독립 제어. FIXED만 바꾸려면 Cost는 GET에서 읽은 기존값 그대로 | (LATEST가 의도치 않게 덮임) |

## 안전 수칙

- **read-modify-write 필수**: GET /product?IncludeSuppliers=true → 대상 필드만 교체 → PUT.
- **그 제품의 공급사 레코드 전부를 PUT에 포함할 것.** record 단위 갱신인지 목록 sync
  (누락 = 연결 삭제)인지 실측으로 미구분 — 전부 포함하면 양쪽 모두 안전.
- 마스터 직접 수정이므로 **변경 로그 필수** (누가/언제/SKU/이전→새값). 구현은 시트 append.
- 사람 실수 가드: 기존값 대비 ±50% 초과 변경 시 추가 확인.

## 구현 위치

- `System_Automation` 프로젝트 `Podraft.gs` (v7):
  `pd_getFixedPrice(sku, supplierName)` / `pd_updateFixedPrice(sku, supplierName, newFixed, byEmail)`
  — 위 규칙 전부 반영, 변경 로그 시트 자동 생성(`PD_PRICE_LOG_SHEET_ID` Script Property).
- 웹 브리지: `Config.gs` doPost가 JSON body의 `action` 존재 시 `Podraftwebapp.gs`의
  `pdw_handleRequest_`로 라우팅 (`createDraftPO` / `getFixedPrice` / `updateFixedPrice`).
  인증은 OAuth access_token → tokeninfo 검증 (@asung.ca; **azp/aud는 전체 형태
  `xxx.apps.googleusercontent.com`로 오므로 CLIENT_ID 접두 일치로 비교** — 실측).
- 프론트: `purchasing.html` 상품명 셀 오른쪽 💲 → 인라인 가격 조회/수정 (FP_CACHE).

## 미검증

- 이 PUT으로 공급사 연결 신규 생성/삭제 (갱신만 검증됨)
- Suppliers가 2개 이상인 제품에서의 동작 (전 레코드 포함 방식으로 방어 중)
