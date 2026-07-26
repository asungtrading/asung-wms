# Transactions 엔드포인트 레퍼런스

## Transactions — GET /transactions

회계 분개 트랜잭션 조회. 모든 유형의 재무 거래 이력.

**주의**: 페이지네이션 지원하지만 응답 키가 `Transactions` (복수형).

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `FromDate` | DateTime | 이 날짜 이후 트랜잭션 (ISO 8601) |
| `ToDate` | DateTime | 이 날짜 이전 트랜잭션 (ISO 8601) |
| `Account` | string | 특정 계정 코드 필터 (Debit 또는 Credit 계정) |

### 트랜잭션 타입 (Type 필드)
| Type | 설명 |
|------|------|
| `Purchase` | 발주 관련 |
| `Sale` | 판매 관련 |
| `MoneySpend` | 지출 |
| `MoneyReceive` | 수입 |
| `BankTransfer` | 계좌 이체 |
| `StockAdjustment` | 재고 조정 |
| `StockTake` | 재고 실사 |
| `InventoryWriteOff` | 재고 손실 처리 |
| `FinishedGoods` | 완제품 |
| `Journal` | 수동 분개 |
| `Disassembly` | 분해 |
| `Depreciation` | 감가상각 |

### 응답 구조
```json
{
  "Total": 500,
  "Page": 1,
  "Transactions": [
    {
      "TaskID": "guid",
      "DebitAccountCode": "610",
      "CreditAccountCode": "200",
      "Amount": 1800.00,
      "EffectiveDate": "2024-01-15T00:00:00",
      "Reference": "INV-00004",
      "Transaction": "고객명 - INV-00004",
      "Type": "Sale"
    },
    {
      "TaskID": "guid",
      "DebitAccountCode": "500",
      "CreditAccountCode": "610",
      "Amount": 250.00,
      "EffectiveDate": "2024-01-15T00:00:00",
      "Reference": "ST-00022",
      "Transaction": "Stock Adjustment - ST-00022",
      "Type": "StockAdjustment"
    }
  ]
}
```

---

## Apps Script 예시 — 기간별 트랜잭션 BigQuery 파이프라인

```javascript
function fetchTransactionsByPeriod(fromDate, toDate) {
  return fetchAllPages('transactions', {
    FromDate: fromDate,  // "2024-01-01"
    ToDate: toDate       // "2024-01-31"
  });
  // 반환 키: Transactions (복수형, 대문자 T)
}
```

## Apps Script 예시 — 재고 조정 트랜잭션만 필터

```javascript
function getStockAdjustmentTransactions(fromDate, toDate) {
  const all = fetchTransactionsByPeriod(fromDate, toDate);
  return all.filter(t => t.Type === 'StockAdjustment');
}
```

---

## 주의사항
- `Transactions`는 **회계 분개** 데이터. 재고 수량 변화는 StockAdjustment/StockTransfer 엔드포인트 사용 권장.
- `TaskID`는 원본 거래(Sale, Purchase 등)의 ID와 연결됨.
- 날짜 범위를 좁게 설정할 것 — 전체 조회 시 데이터 매우 많음.
- `Reference` 필드에 관련 문서 번호(INV, PO, ST 등) 포함.
