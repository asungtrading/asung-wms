# Supplier 엔드포인트 레퍼런스

## Supplier — GET /supplier

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `ID` | Guid | 특정 공급업체 ID 조회 |
| `Name` | string | 이름 시작 문자 필터 (startsWith) |
| `ModifiedSince` | DateTime | 이 날짜 이후 수정된 공급업체 (UTC ISO 8601) |
| `IncludeDeprecated` | bool | 비활성 포함 여부 (기본값 false) |

### 응답 구조
```json
{
  "Total": 10,
  "Page": 1,
  "SupplierList": [
    {
      "ID": "guid",
      "Name": "공급업체명",
      "Currency": "CAD",
      "PaymentTerm": "30 days",
      "AccountPayable": "800",
      "TaxRule": "BAS Excluded",
      "Discount": 0,
      "Comments": null,
      "TaxNumber": null,
      "Status": "Active",
      "LastModifiedOn": "2024-01-15T06:15:17.237Z",
      "Addresses": [
        {
          "Line1": "123 Supply St",
          "City": "Seoul",
          "Country": "South Korea",
          "Type": "Business",
          "DefaultForType": true
        }
      ],
      "Contacts": [
        {
          "Name": "담당자명",
          "Phone": "02-0000-0000",
          "Email": "supplier@example.com",
          "Default": true,
          "IncludeInEmail": false
        }
      ]
    }
  ]
}
```

---

## Apps Script 예시 — 공급업체 ID-이름 맵 만들기

```javascript
function buildSupplierMap() {
  const suppliers = fetchAllPages('supplier', {});
  // 반환 키: SupplierList
  const map = {};
  for (const s of suppliers) {
    map[s.ID] = s.Name;
  }
  return map;
}
```

**주의**: `fetchAllPages()`에서 `SupplierList` 키를 명시적으로 처리해야 함.
```javascript
// fetchAllPages 내부에서 SupplierList 추가
const items = data.SaleList || data.PurchaseList || data.SupplierList || 
              data.CustomerList || data.StockAdjustmentList || 
              data.StockTransferList || data.ProductAvailabilityList || 
              data.Products || data.Transactions || [];
```

---

## 2026-09-11 전량 실측 (Total 226 · GAS 프로브 · IMS PO 모듈 ② 공급처 표 설계 근거)

`IncludeDeprecated` 미사용 — **비활성은 안 봤다.** 설계 판단은 `docs/design/po-module.md`.

```
Currency        USD 159 · CAD 67  ·  ⚠️ KRW 0곳
Status          Active 226
AccountPayable  _109_ 193 · _62_ 33        ⭐ ref/account 의 Code 와 226/226 일치 (Name 일치 0)
PaymentTerm     14종 · ref/paymentterm 의 Name 과 226/226 일치
                ⚠️ 활성 17종과 불일치 — 비활성 3종(Net30·Net45·1%20 Net30)을 24곳이 쓰고 있다
                ⚠️ Net 30(33곳) / Net30(21곳) 이 별개 행 — 띄어쓰기 흔들림
TaxRule         Zero-rated 140 · HST PE 38 · HST ON 29 · HST NS 16 · GST 2 · Exempt 1
Discount        0 이 215곳
⭐ AdditionalAttribute1 만 쓴다 154/226 — 값 2종(Product Supplier 143 · Service Supplier 11)
   2~10번은 전부 0곳 · AttributeSet 은 226곳 전부 'Supplier Type'
⚠️ Addresses 최대 2 (있음 83 · 없음 143)  ·  Contacts 최대 4 (있음 196 · 없음 30)
   ⇒ 칸으로 흡수할 수 없다 — 별도 표가 필요하다(본체·주소·연락처 셋)
Address 키  Line1,Line2,City,State,Postcode,Country,Type,DefaultForType,ID
Contact 키  Name,Phone,MobilePhone,Fax,Email,Website,Default,Comment,IncludeInEmail,ID
⚠️ 이름 정규화 후 같은 이름 묶음 0개 — 통화 때문에 갈라진 공급처는 아직 없다
```
⚠️ [실물] Cin7 공급처 마스터가 실무를 못 따라오는 예 — Avlon 은 `C.O.D` 로 남아 있으나 실제 조건은 50% COD & 50% Net30(Caleb 확인).
「API 값을 잘 받았다」와 「그 값이 맞다」는 다르다.
