# Cin7 Core API v2 — 전체 엔드포인트 인덱스

이 파일은 `dearinventory.apib` 원본 문서 기반 전체 엔드포인트 목록입니다.
레퍼런스 파일이 없는 엔드포인트는 원본 `.apib` 파일에서 해당 섹션을 찾아 추가할 수 있습니다.

---

## ✅ 레퍼런스 파일 있음 (바로 사용 가능)

| 엔드포인트 | 파일 | 페이지네이션 | 응답 배열 키 |
|-----------|------|------------|------------|
| `GET /saleList` | `references/sale.md` | ✅ | `SaleList` |
| `GET /sale` | `references/sale.md` | ❌ | - |
| `GET /purchaseList` | `references/purchase.md` | ✅ | `PurchaseList` |
| `GET /purchase` | `references/purchase.md` | ❌ | - |
| `GET /advanced-purchase` | `references/purchase.md` | ❌ | - |
| `GET /customer` | `references/customer.md` | ✅ | `CustomerList` |
| `GET /supplier` | `references/supplier.md` | ✅ | `SupplierList` |
| `GET /product` | `references/product-master.md` | ✅ | `Products` |
| `GET /ref/productavailability` | `references/product.md` | ✅ | `ProductAvailabilityList` |
| `GET /stockadjustmentList` | `references/stock.md` | ✅ | `StockAdjustmentList` |
| `GET /stockadjustment` | `references/stock.md` | ❌ | - |
| `GET /stockTransferList` | `references/stock.md` | ✅ | `StockTransferList` |
| `GET /stockTransfer` | `references/stock.md` | ❌ | - |
| `GET /transactions` | `references/transactions.md` | ✅ | `Transactions` |

---

## 📋 레퍼런스 파일 없음 (apib 파일에서 추가 필요)

필요한 엔드포인트가 아래에 있으면, `dearinventory.apib` 파일을 업로드하고 해당 섹션 라인 번호를 기준으로 추출하세요.

### Reference Books (설정값 조회)
| 엔드포인트 | apib 라인 | 설명 |
|-----------|----------|------|
| `GET /ref/attributeset` | 147 | 속성 세트 목록 |
| `GET /ref/account/bank` | 530 | 은행 계좌 목록 |
| `GET /ref/brand` | 602 | 브랜드 목록 |
| `GET /ref/carrier` | 703 | 운송사 목록 |
| `GET /ref/account` | 836 | 계정과목 목록 |
| `GET /ref/location` | 3751 | 창고/위치 목록 |
| `GET /ref/paymentterm` | 4952 | 결제 조건 목록 |
| `GET /ref/priceTier` | 5108 | 가격 티어 목록 |
| `GET /ref/category` | 6257 | 제품 카테고리 목록 |
| `GET /ref/tax` | 27437 | 세금 규칙 목록 |
| `GET /ref/unit` | 27824 | 단위 목록 |
| `GET /ref/templates` | 27673 | 문서 템플릿 목록 |
| `GET /ref/customer/templates` | 1594 | 고객 기본 템플릿 |
| `GET /ref/customer/credits` | 1709 | 고객 크레딧 |
| `GET /ref/supplier/deposits` | 27350 | 공급업체 예치금 |

### Sale 관련 세부 엔드포인트
| 엔드포인트 | apib 라인 | 설명 |
|-----------|----------|------|
| `GET /saleCreditNoteList` | 20551 | 판매 크레딧 노트 목록 |
| `GET /sale/quote` | 23015 | 견적서 |
| `GET /sale/order` | 23172 | 판매 오더 |
| `GET /sale/fulfilment` | 23349 | 풀필먼트 |
| `GET /sale/fulfilment/pick` | 23700 | 피킹 |
| `GET /sale/fulfilment/pack` | 23847 | 패킹 |
| `GET /sale/fulfilment/ship` | 24004 | 배송 |
| `GET /sale/invoice` | 24222 | 인보이스 |
| `GET /sale/creditnote` | 24553 | 크레딧 노트 |
| `GET /sale/payment` | 24858 | 결제 |
| `GET /sale/attachment` | 25117 | 첨부파일 |

### Purchase 관련 세부 엔드포인트
| 엔드포인트 | apib 라인 | 설명 |
|-----------|----------|------|
| `GET /purchaseCreditNoteList` | 13388 | 발주 크레딧 노트 목록 |
| `GET /purchase/order` | 14603 | 발주 오더 |
| `GET /purchase/stock` | 14792 | 입고 처리 |
| `GET /purchase/invoice` | 14899 | 발주 인보이스 |
| `GET /purchase/creditnote` | 15111 | 발주 크레딧 노트 |
| `GET /purchase/payment` | 15355 | 발주 결제 |
| `GET /advanced-purchase/stock` | 16918 | Advanced 입고 |
| `GET /advanced-purchase/invoice` | 17565 | Advanced 인보이스 |

### Stock 관련 추가 엔드포인트
| 엔드포인트 | apib 라인 | 설명 |
|-----------|----------|------|
| `GET /stockTakeList` | 25636 | 재고 실사 목록 |
| `GET /stocktake` | 25705 | 재고 실사 상세 |
| `GET /stockTransfer/order` | 26821 | 이전 오더 상세 |
| `GET /inventoryWriteOffList` | 3084 | 재고 손실 목록 |
| `GET /inventoryWriteOff` | 3131 | 재고 손실 상세 |

### Product 관련 추가 엔드포인트
| 엔드포인트 | apib 라인 | 설명 |
|-----------|----------|------|
| `GET /product/attachments` | 6015 | 제품 첨부파일 |
| `GET /productFamily` | 6374 | 제품 패밀리 |
| `GET /ref/markupprices` | 6890 | 마크업 가격 |
| ~~`GET /product-suppliers`~~ | 19600 | **GET 미지원(405, 실측)** — 읽기는 `GET /product?IncludeSuppliers=true`, 쓰기는 `PUT /product-suppliers` (`references/product-suppliers-write.md`) |
| `GET /custom-prices` | 18750 | 고객별 특수가격 |

### 기타 엔드포인트
| 엔드포인트 | apib 라인 | 설명 |
|-----------|----------|------|
| `GET /me` | 3988 | 내 계정 정보 |
| `GET /journal` | 3504 | 수동 분개 |
| `GET /moneyTaskList` | 4423 | 금전 거래 목록 |
| `GET /moneyOperation` | 4486 | 금전 거래 상세 |
| `GET /bankTransfer` | 4754 | 계좌 이체 |
| `GET /webhooks` | 27946 | 웹훅 설정 |
| `GET /crm/lead` | 28901 | CRM 리드 |
| `GET /crm/opportunity` | 29212 | CRM 기회 |
| `GET /finishedGoodsList` | 2195 | 완제품 목록 |
| `GET /disassemblyList` | 1780 | 분해 목록 |

---

## apib 파일에서 섹션 추출하는 방법

새 엔드포인트 레퍼런스가 필요할 때:

```bash
# 예: /ref/location 섹션 추출 (라인 3751 근처)
sed -n '3751,3986p' dearinventory.apib
```

또는 Claude에게:
> "dearinventory.apib 파일에서 `/ref/location` 엔드포인트 섹션을 추출해서 references/location.md 파일로 추가해줘"
