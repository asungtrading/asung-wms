# Customer 엔드포인트 레퍼런스

## Customer — GET /customer

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 · ⚠️ 100 을 넘겨도 100 (2026-09-22 실측 · 95페이지) |
| `ID` | Guid | 특정 고객 ID로 조회 |
| `Name` | string | 이름 **앞부분 일치**(startsWith) — `Name=JOJOJO` 로 `JOJOJO - Joel Chang` 이 나왔다(2026-09-22) · 짐작: 대소문자 무시 여부는 안 봤다 |
| `ContactFilter` | string | 연락처 이름 또는 이메일로 필터 |
| `ModifiedSince` | DateTime | 이 날짜 이후 수정된 고객 (UTC ISO 8601) |
| `IncludeDeprecated` | bool | 비활성 고객 포함 여부 (기본값 false) · ⭐ 전량 적재는 `true` |
| `IncludeProductPrices` | bool | 고객별 특수 가격 포함 여부 (기본값 false) |

---

## ⭐ 실측 (2026-09-22 · `docs/probes/CustomerProbe.gs` · 전량 9,469명 · 정본 `docs/design/so-module.md` §9-g · 9-j)

```
전량        GET /customer?Page=N&Limit=100&IncludeDeprecated=true · 배열 키 CustomerList · 9,469명 = 95페이지(2026-09-22)
            ⚠️ 끝은 Total 이 아니라 「받은 행 수 < Limit」로 판단한다 · 받은 행 수 ≠ Total 이면 수집이 짧게 끝난 것(적재를 멈춘다)
Status      둘 — Active · Deprecated
Address 키  ID · Line1 · Line2 · City · State · Postcode · Country · Type · DefaultForType     ← ⭐ ID 있음(전부 고유 · 적재 열쇠)
Contact 키  ID · Name · JobTitle · Phone · MobilePhone · Fax · Email · Website · Default · Comment · IncludeInEmail · MarketingConsent
  ⚠️ JobTitle 은 손님 연락처에만 온다 — 공급처 Contact 키(supplier.md 101행)에는 없다 · 「API 에 없다」를 공급처에서 손님으로 옮기지 마라
  ⚠️⚠️ MarketingConsent 는 boolean 이 아니라 숫자 — 0·1 = Unknown(둘 다) · 2 = Opt in · 3 = Opt out
       화면 선택 목록 순서(Unknown·Opt in·Opt out)와 다르다 · 네 값 모두 Cin7 화면 대조로 확정 · 그 밖의 값은 받는 쪽이 멈춘다
Address Type 셋 — Billing · Business · Shipping(화면 선택지 그대로 · 대소문자 그대로) · ⚠️ Cin7 은 같은 type 에 DefaultForType 둘을 막지 않는다
세금 번호 키 TaxNumber · Tags 는 쉼표로 이은 문자열(null 이 대부분 · "" 도 온다)
빈 값       "" 와 null 이 섞여 온다(Line2 "" · Phone null …) — 받는 쪽에서 null 로 통일 · 글자 안쪽 공백은 그대로
부모        CustomerParentID(GUID) · IsBillParent 는 **자식 쪽** 표시 · ChildCustomers 는 부모 쪽
429         전량 수집 중 한 번(87페이지) — 65초 쉬고 이어 받았다(SKILL.md 백오프 패턴)
```
📌 분포·건수(Type · DefaultForType · 동의 · 부모 …)는 정본 §9-g 에 — 여기 옮겨 적지 않는다.

### 응답 구조 (키는 2026-09-22 실측 · 값은 예시)
```json
{
  "Total": 9469,
  "Page": 1,
  "CustomerList": [
    {
      "ID": "guid",
      "Name": "Asung Trading Inc",
      "DisplayName": "Asung",
      "Status": "Active",
      "Currency": "CAD",
      "PaymentTerm": "30 days",
      "Discount": 0,
      "TaxRule": "HST ON (Sale)",
      "PriceTier": "Wholesale",
      "AccountReceivable": "_61_",
      "RevenueAccount": "_98_",
      "SalesRepresentative": null,
      "Location": "Asung Trading Inc.",
      "Carrier": null,
      "TaxNumber": null,
      "Comments": null,
      "Tags": "tag1,tag2",
      "CustomerParentID": null,
      "IsBillParent": false,
      "IsLegalEntity": false,
      "LastModifiedOn": "2024-01-15T05:07:23.917Z",
      "Contacts": [
        {
          "ID": "guid",
          "Name": "담당자명",
          "JobTitle": "Owner",
          "Phone": "416-000-0000",
          "MobilePhone": null,
          "Fax": null,
          "Email": "contact@example.com",
          "Website": null,
          "Default": true,
          "Comment": null,
          "IncludeInEmail": false,
          "MarketingConsent": 1
        }
      ],
      "Addresses": [
        {
          "ID": "guid",
          "Line1": "123 Main St",
          "Line2": "",
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
⚠️ 손님 최상위 키는 실측에서 쓴 것만 적었다(전체 키 목록은 `CustomerProbe.gs` `cupPeek` 출력 · Drive 보고서) — 없는 키를 짐작해 코드에 쓰지 마라.

---

## Apps Script 예시 — 전체 활성 고객 목록 가져오기

```javascript
function getAllActiveCustomers() {
  return fetchAllPages('customer', {
    IncludeDeprecated: false
  });
  // 반환: CustomerList 배열
  // 각 항목: { ID, Name, Status, Contacts[{Email}], ... }
  // ⚠️ 전량 적재라면 IncludeDeprecated: true · 끝 판단은 Total 이 아니라 받은 행 수(위 실측) — fetchAllPages 가 그렇게 하는지는 안 봤다
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
