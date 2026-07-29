# Stock 엔드포인트 레퍼런스

## Stock Adjustment List — GET /stockadjustmentList

페이지네이션 지원. 목록만 반환 (라인 없음).

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `Status` | string | DRAFT, COMPLETED, VOIDED |

### 응답 구조
```json
{
  "Total": 22,
  "Page": 1,
  "StockAdjustmentList": [
    {
      "TaskID": "guid",
      "EffectiveDate": "2024-01-15T00:00:00",
      "StocktakeNumber": "ST-00001",
      "Status": "COMPLETED",
      "Account": "403",
      "Reference": "",
      "Comment": "메모"
    }
  ]
}
```

---

## Stock Adjustment 상세 — GET /stockadjustment

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `TaskID` | Guid | **필수** — StockAdjustmentList에서 얻은 TaskID |

### 응답 구조 (핵심 필드)
```json
{
  "TaskID": "guid",
  "EffectiveDate": "2024-01-15T00:00:00",
  "StocktakeNumber": "ST-00022",
  "Status": "COMPLETED",
  "ExistingStockLines": [
    {
      "ProductID": "guid",
      "SKU": "PROD-001",
      "ProductName": "제품명",
      "Quantity": 100,
      "AdjustedQuantity": 95,
      "UnitCost": 12.00,
      "LocationID": "guid",
      "Location": "Toronto Warehouse"
    }
  ],
  "NewStockLines": [
    {
      "ProductID": "guid",
      "SKU": "PROD-002",
      "ProductName": "신규 제품",
      "Quantity": 50,
      "UnitCost": 8.00,
      "LocationID": "guid",
      "Location": "Toronto Warehouse"
    }
  ]
}
```

**주의**: `ExistingStockLines`는 기존에 재고가 있던 제품의 조정, `NewStockLines`는 재고가 0이었던 제품의 신규 입력.

---

## Stock Transfer List — GET /stockTransferList

페이지네이션 지원. Toronto ↔ Edmonton 브랜치 이전 조회에 사용.

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `Page` | number | 기본값 1 |
| `Limit` | number | 기본값 100 |
| `Status` | string | DRAFT, IN TRANSIT, COMPLETED, VOIDED |
| `Search` | string | FromLocation, ToLocation, Status, Number에서 검색 |

### 응답 구조
```json
{
  "Total": 5,
  "Page": 1,
  "StockTransferList": [
    {
      "TaskID": "guid",
      "From": "guid",
      "FromLocation": "Toronto Warehouse",
      "To": "guid",
      "ToLocation": "Edmonton Warehouse",
      "Status": "COMPLETED",
      "Number": "TR-00005",
      "CompletionDate": "2024-01-15T00:00:00",
      "DepartureDate": "2024-01-12T00:00:00",
      "Reference": "",
      "LastModifiedOn": "2024-01-15T00:00:00"
    }
  ]
}
```

---

## Stock Transfer 상세 — GET /stockTransfer

### 파라미터
| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `TaskID` | Guid | **필수** — StockTransferList에서 얻은 TaskID |

### 응답 구조 (핵심 필드)
```json
{
  "TaskID": "guid",
  "Status": "COMPLETED",
  "FromLocation": "Toronto Warehouse",
  "ToLocation": "Edmonton Warehouse",
  "Number": "TR-00005",
  "DepartureDate": "2024-01-12T00:00:00",
  "CompletionDate": "2024-01-15T00:00:00",
  "Lines": [
    {
      "ProductID": "guid",
      "SKU": "PROD-001",
      "ProductName": "제품명",
      "QuantityOnHand": 100,
      "QuantityAvailable": 100,
      "TransferQuantity": 20
    }
  ]
}
```

---

## Apps Script 예시 — Edmonton 이전 이력 BigQuery 파이프라인

```javascript
function fetchRecentTransfers(daysSince) {
  // 1단계: 완료된 트랜스퍼 목록
  const transferList = fetchAllPages('stockTransferList', {
    Status: 'COMPLETED',
    Search: 'Edmonton' // ToLocation에 Edmonton 포함된 건
  });
  
  const rows = [];
  
  for (const transfer of transferList) {
    const completionDate = new Date(transfer.CompletionDate);
    const cutoff = new Date(Date.now() - daysSince * 86400000);
    if (completionDate < cutoff) continue;
    
    // 2단계: 각 트랜스퍼 상세 (라인 아이템)
    Utilities.sleep(200);
    const detail = cin7Get('stockTransfer', { TaskID: transfer.TaskID });
    
    for (const line of (detail.Lines || [])) {
      rows.push({
        transfer_number: transfer.Number,
        from_location: transfer.FromLocation,
        to_location: transfer.ToLocation,
        completion_date: transfer.CompletionDate,
        sku: line.SKU,
        product_name: line.ProductName,
        transfer_qty: line.TransferQuantity
      });
    }
  }
  
  return rows;
}
```

---

# ⚠️ Cin7 UI 실측 노트 (API 아님 — 2026-07-29)

API 로 대체할 수 없어 화면으로 처리하는 작업들. 여기 적힌 것은 전부 **실측**이고, 미확정은 미확정으로 표시했다.

## 1. ⚠️ 원가 0 재고의 재평가 — **방법 미확정 (미해결)**

Stock Revaluation 화면은 **Non-zero stock** 탭과 **Zero stock** 탭 두 섹션이 있고, 문서상 "두 섹션을 함께 사용"하라고 되어 있다.

- ⚠️⚠️ **실측(1 SKU) — 두 섹션은 상계되지 않았다. 재고가 2배로 늘었다.** Non-zero 쪽에 **0** 을 넣어도 기존 수량이 **차감되지 않고**, Zero stock 쪽 입력이 **그대로 가산**됐다.
- **Non-zero 탭에는 unit cost 입력란이 없고 Zero stock 탭에만 있다** → "수량은 그대로, 원가만 교체"를 한 화면에서 할 수 없다.
- **후보 (둘 다 미검증)**
  1. Zero stock 으로 정상 원가 재고를 **추가**한 뒤 **별도 재고 조정으로 같은 수량을 감소** → FIFO 가 0원 카드를 빼내게 하는 2단계. ⚠️ 중간에 **재고가 2배인 구간**이 생기고(그 사이 판매가 잡히면 원가가 섞인다), `CostingMethod` 가 **FIFO-Batch / Serial** 이면 배치·시리얼 지정 때문에 동작이 다르다.
  2. **원인 문서(0원으로 들어온 입고/조정)를 void 후 재작성.**
- 📌 다음 단계: 저가·저회전 1 SKU 로 후보 ①을 **끝까지** 실측하고 **movement 리포트로 카드별 원가를 되읽어** 확인(같은 원칙: 200/화면 표시가 아니라 되읽은 값이 근거 — `stock-write.md` 머리말).

## 2. bin 별 재고를 담은 리포트 (정합성 대조용)

| 목적 | 쓸 것 |
|------|-------|
| **현재 bin 별 재고 스냅샷** | ✅ **Inventory Products Stock Level Report** — **`Bin` 컬럼을 붙일 수 있다.** 컬럼: Location / SKU / Product / Brand / **Bin** / Unit / Qty on hand / Allocated / Unit cost / Stock on hand … |
| **특정 문서로 들어온 것** | Inventory Movement Details + `Reference` 필터 — ⚠️ **유입만 보인다** |
| **현재 위치를 이동이력에서 역산** | Inventory Movement Details **필터 없이** 뽑아 `(SKU, Bin)` 별 **In − Out 넷아웃** |

- ⚠️ **InventoryList CSV 의 `StockLocator` / `PickZones` 는 bin 수량이 아니다** — 제품 마스터의 참고 문자열이라 재고 대조에 쓰면 틀린다.
- 용례: WMS 의 `putaway_bin` 기록 ↔ Cin7 실제 위치 대조. TR-02935 의 남은 이동 목록을 위 넷아웃으로 역산했다.

## 3. 재고 조정(수동)이 담당하는 몫

트랜스퍼 완료 수량은 **보낸 수량으로 고정**되므로(`stock-write.md` 2절 정정) 실물과의 초과/부족은 **사람이 stock adjustment 로** 정리한다. 실사례 TR-02935 → **ST-00794 / ST-00795**. 자동 보정(보정 트랜스퍼 자동 생성)은 **의도적으로 채택하지 않았다** — 부족분을 기계적으로 되돌리면 실제 분실을 "출발 창고에 있다"고 잘못 기록한다.
