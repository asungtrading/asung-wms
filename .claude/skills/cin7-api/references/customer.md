# Customer 엔드포인트 레퍼런스

## Customer — GET /customer

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `ID` | Guid | 특정 고객 ID로 조회 |
| `Name` | string | 이름 시작 문자로 필터 (startsWith) |
| `ContactFilter` | string | 연락처 이름 또는 이메일로 필터 |
| `ModifiedSince` | DateTime | 이 날짜 이후 수정된 고객 (UTC ISO 8601) |
| `IncludeDeprecated` | bool | 비활성 고객 포함 여부 (기본값 false) |
| `IncludeProductPrices` | bool | 고객별 특수 가격 포함 여부 (기본값 false) |

### 응답 구조
```json
{
  "Total": 50,
  "Page": 1,
  "CustomerList": [
    {
      "ID": "guid",
      "Name": "Asung Trading Inc",
      "DisplayName": "Asung",
      "Status": "Active",
      "Currency": "CAD",
      "PaymentTerm": "30 days",
      "PriceTier": "Tier 1",
      "SalesRepresentative": null,
      "Location": "Toronto Warehouse",
      "Tags": "",
      "LastModifiedOn": "2024-01-15T05:07:23.917Z",
      "Contacts": [
        {
          "Name": "담당자명",
          "Email": "contact@example.com",
          "Phone": "416-000-0000",
          "Default": true,
          "IncludeInEmail": false
        }
      ],
      "Addresses": [
        {
          "Line1": "123 Main St",
          "City": "Toronto",
          "State": "ON",
          "Postcode": "M1M 1M1",
          "Country": "Canada",
          "Type": "Billing",
          "DefaultForType": true
        }
      ]
    }
  ]
}
```

---

## Apps Script 예시 — 전체 활성 고객 목록 가져오기

```javascript
function getAllActiveCustomers() {
  return fetchAllPages('customer', {
    IncludeDeprecated: false
  });
  // 반환: CustomerList 배열
  // 각 항목: { ID, Name, Status, Contacts[{Email}], ... }
}
```

## Apps Script 예시 — 이메일 주소 포함 고객 맵 만들기

```javascript
function buildCustomerEmailMap() {
  const customers = getAllActiveCustomers();
  const emailMap = {};
  
  for (const customer of customers) {
    const defaultContact = (customer.Contacts || []).find(c => c.Default && c.Email);
    if (defaultContact) {
      emailMap[customer.ID] = {
        name: customer.Name,
        email: defaultContact.Email
      };
    }
  }
  return emailMap;
}
```
