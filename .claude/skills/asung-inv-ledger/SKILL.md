---
name: asung-inv-ledger
description: >
  Asung Trading 재고 원장(IMS 두 번째 모듈)을 다룰 때 먼저 읽으세요.
  Cin7 재고를 대체할 자체 장부 — 사건을 쌓아 잔고를 계산합니다.
  "원장", "inv_ledger", "재고 원장", "shadow", "shadow 모드", "기초 스냅샷",
  "inv_snapshot", "inv_compare", "inv_sync_state", "대조", "Movements",
  "ProductAvailability", "StockOnHand", "차감 시점", "Ship 차감", "Allocated",
  "IN_TRANSIT", "운송 중", "조립", "FinishedGoods", "번들", "AutoAssembly",
  "Adjustment", "ExistingStockLines", "NewStockLines", "CreditNotes Restock",
  "StockReceived Lines Date", "DepartureDate", "CompletionDate", "seq_hint",
  "line_ref", "FIFO", "원가 레이어" 등이 나오면 추측하지 말고
  이 스킬의 확정 사실·이벤트 규칙·함정을 확인하세요.
  ⚠️Adjustment는 증감분이 아니라 조정 후 수량, ⚠️NewStockLines는 규칙이 다름,
  ⚠️재고는 Ship에 빠짐(픽·팩은 Allocated), ⚠️StockOnHand는 수량이 아니라 평가액,
  ⚠️같은 날은 유입 먼저 — 어기면 원장 전체가 반대로 쌓이거나 잔고가 음수가 됩니다.
---

# Asung Trading 재고 원장 스킬

WMS 다음 모듈. **설계 정본은 레포의 `docs/design/ledger-design.md`** — 이 스킬은 그 요약과
실측 근거, 그리고 반복해서 틀렸던 지점들이다.

관련 스킬: `asung-wms`(같은 레포·DB), `cin7-api`(엔드포인트·파라미터)

---

## 1. 무엇을 만드는가

"지금 몇 개"를 저장하지 않고 **"무슨 일이 있었다"만 쌓는다.** 잔고는 더해서 구한다.

- **1단계 범위**: 수량만 · 창고 단위 · shadow(어디에도 안 씀)
- **기준은 Cin7 문서.** WMS 는 보조 — WMS 미경유 사건이 월 수백 건이라 WMS 기준은 처음부터 구멍
- 원가(amount)·자리(bin)는 **값만 저장하고 계산엔 안 씀** — 나중에 소급 불가라 지금부터 담는다

**진행 상태 (2026-08-16)**: 테이블 4개 배포 완료. 수집 코드는 미착수.

---

## 2. ⚠️ 반복해서 틀렸던 것 (가장 중요)

| 함정 | 진실 |
|---|---|
| `Adjustment` 가 증감분? | **아니다. 조정 후 목표 수량.** 증감 = `Adjustment − QuantityOnHand` |
| `NewStockLines` 도 같은 규칙? | **아니다.** `Quantity` 가 그대로 증가분. 섞으면 원장이 통째로 틀림 |
| `StockOnHand` 가 수량? | **아니다. 평가액.** 원장 기준값은 `OnHand` |
| 재고가 픽/팩에 빠지나? | **아니다. Ship 시점.** 픽·팩·Finalize 는 `Allocated` 일 뿐 |
| 문서 번호로 순서를 정하면? | **안 된다.** 접두어가 달라 비교 무의미. **유입(+) 먼저, 유출(−) 나중** |
| `Bin=null` 행이 창고 집계행? | **아니다.** 빈 미지정 재고 자리. 99.8%가 0이고, 0이 아닌 14행은 진짜 재고 |
| UOM SKU 도 재고가 있나? | 평소 없다(`OnHand=0`·`Available` 만 파생). 다만 **구조상 가질 수는 있다** |
| `ProductID` 가 라인 식별자? | 상품 ID 다. 같은 SKU 두 줄이면 겹침. **다만 실무상 안 겹쳐서 line_ref 로 씀** |

### 조사 자체에서 반복된 실패 (같은 실수 반복 금지)

- **1페이지만 받고 판정** — `/transactions` 30일이 6,451행인데 1,000행만 보고 "86% 미대응"이라 오판.
  전량 받으니 **87% 일치**로 정반대였다. **Total 과 수신 행 수를 항상 대조할 것**
- **정렬 가정** — 목록 앞쪽 1,000행이 전부 UOM 집계행이라 "빈 지정 0%"로 오판
- **파라미터 이름 추측** — `stockadjustment?ID=` 로 400. 문서엔 `TaskID` 로 적혀 있었다
- **대조군 없이 판정** — Cin7 은 모르는 파라미터를 조용히 무시한다.
  존재하지 않는 이름(`ZzzNotARealParam`)을 같이 던져 "무시" 기준선을 만들 것

---

## 3. 이벤트 8종 — 어디서 무엇을 읽나

| 사건 | 출처 | 부호 | 날짜 |
|---|---|---|---|
| 판매 출고 | `sale` → `Fulfilments[].Pick.Lines` | − | `Ship.Lines[].ShipmentDate` |
| 반품 입고 | `sale` → `CreditNotes[].Restock` | + | `CreditNoteDate` |
| 발주 입고 | `purchase`/`advanced-purchase` → `StockReceived[].Lines` | + | **`Lines[].Date`** |
| 이동 출발 | `stockTransfer` → `Lines[].TransferQuantity` | − | `DepartureDate` |
| 이동 도착 | 같은 문서 | + | `CompletionDate` |
| 조정 기존 | `stockadjustment` → `ExistingStockLines` | `Adjustment − QuantityOnHand` | `EffectiveDate` |
| 조정 신규 | `stockadjustment` → `NewStockLines` | `+Quantity` | `EffectiveDate` |
| 조립 | `finishedGoods` → `PickLines`(−) + 헤더(+) | 양방향 | 오더 생성 시점 |

**원가만 바뀌는 6종**(`* Cost Change`)은 `Quantity=0` — 수량 원장에서 무시.

### 문서별 함정

- **발주**: Advanced 는 `StockReceived` 가 **배열**, Simple 은 **객체**. 둘을 다르게 읽어야 함
- **발주 날짜**: `OrderDate`·`InvoiceDate`·`LastUpdatedDate` 전부 어긋남. 우연히 맞는 경우가 있어
  **한 건만 보고 판단 금지**
- **반품**: `RestockStatus='AUTHORISED'` 일 때만 재고 복귀. `DRAFT` 는 금액만.
  한 오더에 크레딧 노트가 **여러 개** 붙을 수 있음
- **이동**: 한 문서가 원장 4행(출발창고− / IN_TRANSIT+ / IN_TRANSIT− / 도착창고+).
  미완료면 출발만. **97%가 같은 창고 안 자리 이동** — 창고 단위로는 ±0이지만 **두 줄 다 기록**
- **조립**: 오더 생성 시점에 실제로 재고가 움직인다. 출고는 배송 때 — 그 사이 번들이 재고로 존재(0~15일).
  물리적 이동이 아니라 **재분류**라 실사 때 장부와 선반이 달라 보임.
  ⚠️ 조립 없이 팔리는 경우도 있다(조정으로 재고를 잡아둔 것 — 3건 확인)

---

## 4. 수집 경로

### 문서 목록 축으로 수집한다 (`/transactions` 아님)

⚠️ **`/transactions` 는 탐지 축으로 쓸 수 없다** — 창고내 이동의 94%가 회계 분개를 안 만든다.
금액 이동이 없어서다. 실측: 창고내 분개있음 123 / 없음 1,882 · 창고간 23 / 4.

### 목록별 증분 가능 여부 (실측)

| 목록 | Total | 증분 |
|---|---|---|
| `saleList` | 14,752 | ✅ `UpdatedSince` |
| `purchaseList` | 1,155 | ✅ `UpdatedSince` |
| `saleCreditNoteList` | 3,583 | ✅ `UpdatedSince` |
| `stockadjustmentList` | 1,201 | ❌ 전량 2p |
| `stockTransferList` | 3,977 | ❌ 전량 4p |
| `finishedGoodsList` | 120 | ❌ 전량 1p |

날짜 축 없는 셋은 **매번 전량 받아 우리 쪽에서 날짜로 거른다.** 하루 10페이지 안팎.

### `Movements` 는 검증용

`product?ID=…&IncludeMovements=true` 로 SKU 단위 전체 이력. **부호가 이미 들어 있고 완전하다**
(3건 전수: 누적 = 현재 `OnHand`). 그런데 **날짜 필터가 없고**(후보 7종+대조군 전부 무시)
**SKU 단위 조회**라 수집엔 못 쓴다. → **대조·검산 축**으로 쓴다.

`Movements` Type 어휘 14종 = 수량 8종 + 원가 6종. 필드: `TaskID·Type·Date·Number·Quantity·Amount·Location(빈 포함)·FromTo`

---

## 5. 스키마 (배포 완료)

`inv_ledger` · `inv_snapshot` · `inv_compare` · `inv_sync_state`

### `inv_ledger` 핵심

- **append-only** — `authenticated` 는 INSERT+SELECT 만(`wms_rollback_archive` 선례). `anon` 전부 회수
- 유니크: `(doc_type, doc_number, line_ref, event_type, warehouse, bin, sku)`
  - ⚠️ `bin` 은 **NOT NULL DEFAULT `''`** — 부분 유니크 금지 규칙(29) 때문
  - ⚠️ `sku` 를 넣은 이유: `line_ref` 가 흔들려도 **조용한 누락 대신 가시적 이중 계상**이 되게
- `seq_hint` — **1=유입 / 2=유출**. 같은 날 정렬용
- `warehouse` — **Cin7 원문 그대로** + `IN_TRANSIT`(언더스코어 = Cin7 원문 아님 표시)
- `line_ref` = **`ProductID`** (WMS 의 `cin7_po_line_id` 도 같은 값을 쓴다 — 실무 검증됨)
- `raw` = **그 행을 만든 라인 원본 + 계산에 쓴 머리말 + 우리가 적용한 계산 규칙**.
  문서 전체 금지(344라인 트랜스퍼면 수천 벌 중복)
- ⚠️ `qty_delta` 에 CHECK 없음 — **소수 수량이 실재**(5.25개 · ×0.25)

### 기초 스냅샷

`ref/productavailability` 전량 22,133행 · 23페이지 · 1분. 페이지 상한 없음.

**스냅샷 조건**: 자리 지정된 것은 자리별로, **자리 없이 떠 있는 재고(`Bin=null` & `OnHand≠0`)도 담는다.**
자리 있는 것만 담으면 11건이 통째로 누락된다. → 약 13,847행

---

## 6. 창고

`ref/location` 2,676행 · **`ParentID` 없는 것이 창고**(2단 트리, 재귀 불필요) · 창고 3개

| Cin7 | WMS `warehouse` | WMS `location` |
|---|---|---|
| `Asung Trading Inc.` | `toronto` | 같음 |
| `Asung - Edmonton` | `edmonton` | 같음 |
| `Production Facility` | 없음 | — |

- `wms_orders.location` 은 **Cin7 표기 그대로** → 매핑 불필요
- `wms_receipts`·`wms_waves` 는 `warehouse` 만 → **2줄 매핑 필요**
- ⚠️ `Production Facility` 는 삭제 불가한 시스템 창고, 미사용(재고 0 전수 확인).
  **제외하되 `OnHand>0` 이 나타나면 경고할 것**

---

## 7. 재고 조회 규칙 (`ref/productavailability`)

- ⚠️ `Sku` 는 **전방 부분일치** — `ANN04350` 요청에 `ANN04350-12` 도 온다. **정확일치로 재필터**
- ⚠️ `Bin=null` 행과 빈행을 **합산하면 이중 계산**
- ⚠️ UOM SKU 는 `OnHand=0` · `Available>0`(파생값) — 원장 대상 아님
- `StockOnHand ÷ OnHand` = 단가. 빈마다 다르다(68%) → **FIFO 구조**. 초기 단가로 쓸 수 있으나
  **레이어 구조는 여기서 못 얻는다**
- `InTransit` 필드는 창고이동과 무관 — `OnOrder` 와 같은 값(발주 잔량)

---

## 8. 알고 시작하는 위험

- **원가 0 재고** — 조정으로 새로 잡을 때 `UnitCost=0` 이 들어온다. 원가 단계에서 공짜 재고
- **원본 데이터 오류** — `AMP41108-12` 의 `UOM="6"`(SKU 접미어와 불일치).
  ⚠️ **SKU 접미사 파싱 금지**. 원장은 원본 오류를 그대로 물려받는다
- **전체 합계 검산 경로 없음** — SKU 단위는 `Movements` 누적으로 되지만, 창고 총계는 화면 리포트뿐
- **수동 단계** — 매니저의 `2.Release to WMS`(`sale` 의 `AdditionalAttributes.AdditionalAttribute1`).
  주 5일이라 월요일에 몰린다. 재고와 무관하나 대조 때 설명이 필요
- **주말·공휴일** — 재고가 안 움직이는 게 정상. 온타리오와 앨버타의 공휴일이 다르다

---

## 9. 작업 방식

- 조사·판단 먼저 → Caleb 확인 → 구현. **한 번에 한 단계**
- git·SQL·EF 배포·Cin7 호출은 **Caleb 이 직접**. 프로덕션 직접 요청 금지
- 마이그레이션은 항상 새 파일. baseline 수정 금지. `supabase db reset` 으로 로컬 재생 검증 후 push
- 커밋 메시지에 `Co-Authored-By` 금지
- GAS 프로브가 표준 조사 도구 — EF 구현 전에 항상 실측
