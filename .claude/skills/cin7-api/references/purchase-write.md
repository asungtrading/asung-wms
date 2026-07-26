# Purchase 쓰기(write) 레퍼런스 — DRAFT PO 생성

> **출처: 2026-07-10 실측 검증** (스모크 테스트 PO-01019, USD 공급사 Intervision China USD, SKU AS92900).
> 공식 문서(help.core.cin7.com의 Purchase_POST)는 한 번의 POST로 Order까지 생성되는 것처럼
> 보이지만 **실제 동작은 다름**. 이 문서가 실측 기준이며, 문서와 충돌 시 이 문서를 따를 것.

## 핵심 규칙 (실측으로 확정)

### R1. Purchase 생성은 반드시 2단계

`POST /purchase`의 payload에 중첩 `Order` 블록(Status, Lines)을 넣어도 **Cin7이 조용히 무시한다**
(에러 없음, HTTP 200, 응답의 Order.Status = "NOT AVAILABLE", Lines = []).

| 단계 | 엔드포인트 | 역할 |
|------|-----------|------|
| 1 | `POST /purchase` | 구매 태스크(헤더)만 생성. 응답의 `ID`(GUID)와 `OrderNumber`(PO-xxxxx) 확보 |
| 2 | `POST /purchase/order` | 1단계 `ID`를 `TaskID`로 넘겨 주문 라인 붙이기 |

2단계는 Order.Status가 DRAFT 또는 NOT AVAILABLE인 태스크에만 가능 (AUTHORISED 이후엔 불가).

### R2. 통화: CurrencyRate는 보내지 말 것 (자동 물림)

- `BaseCurrency`: **계정 기준 통화 'CAD' 고정.** 공급사 통화를 넣는 필드가 아님.
- `CurrencyRate`: **생략하면 Cin7이 공급사(SupplierID) 통화 기준 환율을 자동으로 채움.**
  실측: USD 공급사 → CurrencyRate 1.41563 자동 설정 (UI의 "CAD units per USD"와 동일 동작).
- 라인의 `Price`는 **공급사 통화 기준 단가** (USD 공급사면 USD 단가).

### R3. Lines 규칙

- **같은 SKU를 Lines에 두 번 넣으면 예외 발생** → POST 전 SKU별 수량 합산 필수.
- `SKU`만 보내면 Cin7이 ProductID로 해석해줌 (응답에 ProductID·제품명 채워져 돌아옴).
  ProductID를 알면 함께 보내도 됨 (ProductID 우선).
- 라인 필수 필드: SKU(또는 ProductID), Quantity, Price, Discount(0), Tax(0), Total, TaxRule.
- TaxRule은 라인마다 필수 — 공급사 기본 TaxRule(`supplier.TaxRule`) 사용.

### R4. 헤더 필수값은 공급사 레코드에서

`GET /supplier?Name=...`으로 공급사를 먼저 조회해 다음을 확보:
- `ID` → `SupplierID`로 사용 (이름 문자열 대신 GUID — 오매칭 방지)
- `TaxRule`, `PaymentTerm`(→ Terms) → 헤더 필수 필드에 그대로
- `Currency` → 참고용 (payload에는 안 넣음, R2 참조)

`Location`은 Cin7 Stock Location 이름과 정확히 일치해야 함 (Asung: "Asung Trading Inc.").

### R6. 가격은 자동채움 안 됨 — 우리가 붙여야 함

환율(R2)과 달리 **Price는 생략하면 Cin7이 0으로 넣는다** (자동채움 X, 실측 확인).
DRAFT PO 라인에 Price를 반드시 명시할 것.

- 공급사 단가 소스: `GET /product?Sku=..&IncludeSuppliers=true`의 `Suppliers[]`에서
  이 공급사(SupplierID 일치) 항목의 **`FixedCost`(합의 고정가) > `Cost`(최근 매입가)** 순.
  (필드명 주의: `Price` 아님. product-master.md 참조)
- 폴백: FixedCost>0 → Cost>0 → 0. **0으로 떨어진 SKU는 별도 목록(zeroPriceSkus)으로
  반환해 승인 전 사람이 채우도록** 한다.
- 대안 소스: "실제 최근 매입가"가 필요하면 `asung_purchase_history`(Cin7_Purchase_Data)에서
  SKU별 최근 unit_cost 조회로 교체 가능 (구현: `pd_getSupplierPriceMap_()` 함수만 교체).

## Payload 샘플 (실측 성공본)

### 1단계 — POST /purchase

```json
{
  "SupplierID": "ee595b45-dd27-412c-b307-fd4dc6abfb74",
  "Approach": "INVOICE",
  "BaseCurrency": "CAD",
  "TaxRule": "Zero-rated (Purchase)",
  "Terms": "Due on receipt",
  "Location": "Asung Trading Inc.",
  "Note": "Auto-generated DRAFT"
}
```

응답 핵심: `ID`(태스크 GUID), `OrderNumber`("PO-01019"), `CurrencyRate`(자동 1.41563),
`SupplierCurrency`("USD"), `Order.Status`("NOT AVAILABLE" — 정상, 2단계에서 DRAFT로 바뀜).

### 2단계 — POST /purchase/order

```json
{
  "TaskID": "1111aae8-5490-48e6-898f-8c977f376023",
  "Status": "DRAFT",
  "Lines": [
    {
      "SKU": "AS92900",
      "Quantity": 1,
      "Price": 1.00,
      "Discount": 0,
      "Tax": 0,
      "Total": 1.00,
      "TaxRule": "Zero-rated (Purchase)"
    }
  ],
  "TotalBeforeTax": 1.00,
  "Tax": 0,
  "Total": 1.00
}
```

응답 핵심: `Status`("DRAFT"), `Lines[]`에 ProductID·Name 채워져 반환.

## 구현 위치와 컨벤션

- **구현 파일: `System_Automation` 프로젝트의 `Podraft.gs`** (prefix `PD_`).
- 진입점: `pd_createDraftPO(supplierName, lines, opts)` — lines는 `[{sku, quantity, price}]`,
  opts는 `{location, note}`. 2단계를 내부에서 묶어 처리.
- **웹 브리지 (2026-07)**: purchasing.html "→ Cin7 발주 초안" 버튼 → GAS 웹앱.
  `Config.gs` doPost가 JSON body의 `action` 존재 시 `Podraftwebapp.gs`의
  `pdw_handleRequest_`로 라우팅. 인증: OAuth access_token → tokeninfo 검증
  (@asung.ca 전용; azp/aud는 전체 형태로 오므로 CLIENT_ID **접두 일치** 비교 — 실측).
  브라우저 fetch는 `Content-Type: text/plain`으로 POST (CORS preflight 회피).
- 안전 장치 (asung-apps-script 스킬의 write 규율):
  - `PD_DRY_RUN` 상수 — true면 payload 로그만, 실제 전송 안 함. **새 write 코드는 항상
    DRY_RUN 검증 → 실전 순서.**
  - payload는 항상 전체 로그 (실패 재현용)
  - 5xx만 1회 재시도, **4xx는 재시도 금지** (POST 중복 생성 위험)
  - 에러 시 응답 본문 포함해 throw (Cin7이 본문에 구체 사유를 적어줌)

## 주의 / 미검증 영역

- Sale(판매주문) 쓰기는 아직 미검증 — Purchase와 유사한 패턴(POST /sale → POST /sale/order)일
  것으로 추정되나 **실측 전까지 추정으로 코드 작성 금지**. Sale POST 제약 (문서 기준):
  재고 초과 수량은 조용히 백오더 생성(에러 없음), Lines 내 중복 SKU 예외.
- Advanced Purchase 쓰기 미검증 (Asung의 DRAFT 발주는 Simple이라 현재 불필요).
- `PUT /purchase/order`(기존 라인 교체) 미검증.
