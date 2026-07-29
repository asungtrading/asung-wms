# Stock Transfer / Purchase Stock Received 쓰기 (⚠️ 2026-07-23 실측 검증)

공식 문서(apib)와 실동작이 다른 부분이 있어 실측으로 확정. purchase-write.md 와 동일하게
새 write 코드는 항상 DRY_RUN 게이트를 거칠 것. 검증 도구: System_Automation 의
`WmsTransferWriteTest.gs` / `WmsPoStockWriteTest.gs`.

> ⚠️⚠️ **원칙 (2026-07-28) — 쓰기 실측의 근거는 HTTP 200 이 아니라 GET 으로 되읽은 값이다.**
> Cin7 은 요청을 **200 으로 받고 조용히 무시**하는 경우가 있다(트랜스퍼 완료의 `TransferQuantity`
> — 아래 정정 항목). 되돌릴 수 없는 쓰기를 새로 실측할 때는 **반드시 되읽어 확인하고 그 값을 기록**할 것.

## 공통 — bin 은 GUID 로만 (⚠️ 가장 중요)

- 쓰기 API 의 `From`/`To`/`LocationID` 에 **bin 이름("Asung - Edmonton: EZ010101")을 넣으면
  400 "Location ... was not found in Locations reference book"**. apib 예시("Main Warehouse: Bin 1")는
  실동작과 다름 — 반드시 GUID.
- **bin GUID 조회**: `GET /ref/location` → **최상위 창고 행(`ParentID` 없음)의 `Bins[]` 배열**.
  ⚠️ **응답은 Total 2678 에 Limit 500 으로 잘리지만 `Bins[]` 는 창고 행 하나에 전부 들어있다**
  (에드먼튼 628 · 토론토 2047 — 페이지네이션 불필요). ⚠️ **child-location 행의 `Name` 은
  bin 이름이 아니다**(바코드류) — 그 폴백은 죽은 경로였다. 상세는 아래 5절.
- Asung location 이름: 토론토 `Asung Trading Inc.` / 에드먼튼 `Asung - Edmonton`.

## Stock Transfer 쓰기 — POST /stockTransfer (TR-03236 실측)

- **POST 로 즉시 `Status: "COMPLETED"` 생성 가능** — DRAFT 경유 불필요.
- **같은 창고 안 bin↔bin 이동에 InTransitAccount 불필요** (창고 간 이동일 때만 필요).
- 수량은 **델타**(TransferQuantity) — stock adjustment(절대값 "New value for QuantityOnHand",
  스냅샷 stale 시 위험)보다 안전. **bin 이동의 표준 수단**.
- 되돌리기 = 반대 방향 트랜스퍼 POST (상쇄). DELETE 는 Void 용.
- 트랜스퍼 **라인에는 bin 필드가 없음** (Line Model: SKU/TransferQuantity/BatchSN...) —
  목적지는 헤더 To(bin GUID) 하나뿐. 라인별 다른 bin = 트랜스퍼 여러 개로 분해.
- ⚠️ **`From`/`To` 가 문서 레벨이라 한 문서에 여러 SKU 를 담을 수 있다** — `POST /purchase/stock` 의
  "문서당 bin 1개" 제약(아래)과 **다르다**. 쪼개는 단위는 SKU 가 아니라 **(From, To) 조합**이다.

```json
POST /stockTransfer
{
  "Status": "COMPLETED",
  "From": "77a23dc5-...(bin GUID)",
  "To":   "26b21fa7-...(bin GUID)",
  "CostDistributionType": "Cost",
  "DepartureDate": "...", "CompletionDate": "...",
  "Reference": "WMS bin-move",
  "Lines": [{ "SKU": "ABE50408", "TransferQuantity": 1 }],
  "SkipOrder": true
}
```
성공 응답: TaskID + Number(TR-xxxxx) + Status COMPLETED. USER 는 "Data Management (API Application)" 로 찍힘.

**기존 IN TRANSIT 트랜스퍼 완료** = PUT 으로 GET 상세를 그대로 + Status COMPLETED + CompletionDate.
전량이 헤더 To bin 에 착지 → 라인별 배치는 후속 bin↔bin 미니 트랜스퍼로.

## Purchase Stock Received 쓰기 — POST /purchase/stock (PO-01084 실측)

- **선행조건 (⚠️ Invoice First)**: PO 가 'Invoice First' approach 면 **인보이스가 AUTHORISED 여야**
  stock received 가능. 아니면 400 "'Invoice First' approach option set. Please authorise Invoice
  before StockReceived". Asung 은 전 PO Invoice First. 확인: GET /purchase/invoice?TaskID=.
- PO 의 전체 Status=INVOICED 상태에서도 stock received POST 통과(실측).
- **라인 `Date` 필수** (빠지면 400 "'Date' is required for 'Lines' line").
- **LocationID = bin GUID** → 입고 시점에 bin 직접 지정 (후속 재배치 불필요).
- Quantity 는 PO 라인 단위 (base 낱개면 그대로, 변형이면 낱개÷factor).
- 2단계: DRAFT 생성 → **Authorize = 빈 Lines 재요청** `{TaskID, Status:'AUTHORISED', Lines:[]}`
  (apib "To Authorize... Request with empty lines"). ⚠️ Authorize 단계는 미실측 —
  실패해도 DRAFT 는 남아 Cin7 화면 수동 Authorize 가능. DRAFT 는 재고 영향 없음 + 화면에서 취소 가능.
- POST 조건(apib): Order status AUTHORISED / Stock Received status DRAFT 또는 NOT AVAILABLE /
  같은 Product+location+batch+expiry 라인 이미 있으면 에러 / Simple PO 는 사실상 1회 authorize.

```json
POST /purchase/stock
{
  "TaskID": "63638cbf-...(PO GUID)",
  "Status": "DRAFT",
  "Lines": [{
    "Date": "2026-07-24T00:00:00Z",
    "SKU": "AS93116", "Quantity": 1,
    "LocationID": "b848f773-...(bin GUID)",
    "Received": false
  }]
}
```

## purchaseList 필터 실무 노트

📌 **필터·페이징 실측 전체는 `purchase.md` 「필터·페이징 실측」 표** — `InvoiceStatus` 는 단일 값이라 AUTHORISED/PAID 2회 병합 · `Limit=1000` 동작 · **기본 정렬이 PO 번호 오름차순**(최신 PO 는 마지막 페이지) · `UpdatedSince` 는 최신성 보장 못함 · `RestockReceivedStatus` 무시됨.

- `InvoiceStatus=AUTHORISED` 서버 파라미터 지원 — Invoice First 워크플로의 "리시빙 준비" 필터. ⚠️ **AUTHORISED 만 조회하면 PAID 로 넘어간 PO 가 누락된다**(실측 PO-01081).
- Status 는 **복합 문자열**("RECEIVED / CREDITED") 가능 — 정확 일치 말고 includes 로 검사.
- Type 에 "Service"(운송·관세 주문 — 물건 없음) 존재 — 리시빙 목록에서 제외 필요.

---

# ⚠️ 2026-07-24 실측 — PO stock received 3대 제약 (오래 헤맨 진짜 원인들)

여러 라인·여러 bin 을 한 번에 보내면 계속 400 "Lines is invalid" 가 났는데, GAS 로 한 변수씩 분리 실험해 원인 3개를 확정:

## 1. 문서당 bin(LocationID) 1개만 — 가장 중요
- 한 `POST /purchase/stock` 의 Lines 에 **서로 다른 LocationID 를 섞으면 400 "Lines is invalid"**.
- 같은 bin 에 여러 SKU 는 OK. 다른 bin 이 2개 이상이면 실패.
- **해결: putaway_bin(LocationID)으로 그룹핑 → bin 마다 별도 POST** (콜 간 sleep 300~400).
- 실측: 같은 bin 2라인 200 / 다른 bin 2라인 400. (트랜스퍼는 bin↔bin 되는데 stock received 는 안 됨)

## 2. 같은 (Product + Location) 중복 라인 금지
- 400 "Cannot add duplicate value in stock received lines. (Product:..., Location:...)".
- 이미 그 조합이 stock received 에 있거나, 한 POST 안에 같은 SKU+bin 이 두 번이면 발생.
- 재시도 시 이전 DRAFT 가 남아있으면 중복됨 → 재실험 전 Cin7 stock received 비우기.

## 3. Authorize 는 POST (PUT 아님)
- `POST /purchase/stock {TaskID, Status:'AUTHORISED', Lines:[]}` → 200.
- **PUT → 405 "The requested resource does not support http method 'PUT'".**
- authorize 성공 = 재고 확정. 실패해도 DRAFT 는 남아 화면 수동 authorize 가능.

## 기타
- **Date**: `YYYY-MM-DDT00:00:00Z` (자정, 밀리초 없이) 권장. 필드 필수.
- **화면 vs API 불일치**: Cin7 Stock Received 탭이 "비어있음"이어도 GET `/purchase/stock?TaskID=` 는 NOT AVAILABLE 반환 가능 — API 상태로 판단.
- **디버깅 패턴**: 실패 시 보낸 body(SENT)를 에러에 붙여 확인. GAS 로 1라인→N라인→bin분할 순으로 이분 격리(WmsPoStockWriteTest.gs: psRunStockTest / psMultiLineTest / psAuthorizeTest).

# 트랜스퍼 창고간(branch→branch) — 미완 (2026-07-24)
- 실제 IN TRANSIT(TR-03259)은 From/To 가 warehouse(bin 아님), InTransitAccount 있음, 라인에 bin 필드 없음.
- 완료(COMPLETED)해야 목적지 창고에 재고 들어옴 → 그 후 bin transfer 로 풋어웨이. 기존 수동 = 임시 집결 bin(EZ010101)에 전량 받고 재배치.
- 완료 방식(PUT/POST)·착지 bin 지정 가능 여부 실측 미완. WMS 워크플로(완료후 Apply)와 순서 충돌 → 재설계 필요.

---

# ⚠️ 2026-07-25 실측 — 창고간(branch→branch) 트랜스퍼 완료 & bin 풋어웨이

테스트 트랜스퍼 TR-03260(토론토→에드먼튼, 2 SKU ×1) 로 IN TRANSIT 상태에서 검증.

## 1. 완료 = PUT (POST 아님)
```
PUT /stockTransfer
{ TaskID, Status:'COMPLETED', From, To, CostDistributionType:'Cost',
  InTransitAccount, DepartureDate, CompletionDate, Reference, Lines, SkipOrder:true }
```
→ 200, Status: COMPLETED.

## 2. ~~수량 초과 완료 허용~~ → ⚠️⚠️ **틀린 기록이었다 (2026-07-28 정정)**

**폐기된 기록**: *"원본 `TransferQuantity:1` 짜리 라인을 3으로 바꿔 완료해도 200 → 실물이 보낸 수량보다 많아도 '들어온 대로' 쓸 수 있다(PO stock received 와 동일)."*

**정정 — 완료 PUT 의 `TransferQuantity` 변경은 무시된다.** 신규 IN TRANSIT **TR-03267** 로 재실측(2026-07-28):

| SKU | 원본 | 요청 | 저장(되읽음) |
|-----|------|------|--------------|
| `AS93113` | 2 | **4** | **2** ❌ |
| `AS92700` | 4 | **2** | **4** ❌ |

- **증가·감소 양방향 모두 무시**. 보낸 body(SENT)에 변경값이 정확히 실려 나가고 **PUT 은 200** 을 준다. 코드 버그가 아니라 **API 제약**이다(추정: 창고간 트랜스퍼는 발송 시점에 재고가 in-transit 계정으로 넘어가므로 거기 없는 수량을 완료로 받을 수 없다).
- **왜 틀린 기록이 남았나**: **HTTP 200 만 보고 저장값을 되읽지 않았고**, PO stock received 의 초과 허용(이쪽은 **사실**)과 혼동됐다.
- 📌 **원칙 — 쓰기 API 는 200 이 아니라 GET 으로 되읽은 값으로 검증한다.** 되돌릴 수 없는 쓰기를 새로 실측할 때는 반드시 되읽어 확인하고, **그 값**을 근거로 기록한다.
- → 창고간 트랜스퍼 **완료 수량 = 보낸 수량 확정**. 실물 차이는 별도 재고 조정/discrepancy 로 처리한다. **PO stock received 경로는 그대로 — received 그대로 쓸 수 있다.**
- 실측 뒷받침(**TR-02935**, 344 라인): Cin7 이 받은 수량 = 보낸 수량. APR15412 **24**(실물 48) · APR16104 **6**(12) · APR48208 **12**(24) · AJA66008 **6**(12) · WOC40103 **12**(실물 6).

## 3. 완료 시 bin 지정 불가 → 착지 지점 2가지
트랜스퍼 **라인에 bin/location 필드가 없다**(ProductID, SKU, ProductName, QuantityOnHand, QuantityAvailable, TransferQuantity, BatchSN, ExpiryDate, Comments, 치수/가격/Barcode…). 그래서 헤더 `To` 하나로만 착지:
- **To = 창고 GUID** → 재고가 **bin 없이** 창고에 들어옴 (Cin7 재고화면에서 BIN 칸이 공백인 행으로 보임). PO 처럼 "stock received 화면에서 bin 지정" 하는 단계가 **아예 없다**.
- **To = 특정 bin GUID** → 그 bin 에 전량 (예: 임시 집결 bin).

## 4. bin 풋어웨이 = POST, From 은 트랜스퍼의 To
```
POST /stockTransfer
{ Status:'COMPLETED', From: <원 트랜스퍼의 To GUID>, To: <실제 bin GUID>,
  CostDistributionType:'Cost', DepartureDate, CompletionDate, Reference,
  Lines:[{SKU, TransferQuantity}], SkipOrder:true }
```
→ 200 (새 TR 번호 생성되며 즉시 완료). **From 을 창고 GUID 로 주면 "bin 없는 재고"를 꺼내 목적지 bin 으로 옮겨준다** (실측: bin 없던 1개 → EB010204, 재고 bin없음 1→0 / EB010204 23→24 확인). To 가 집결 bin 이었던 경우도 From=그 bin GUID 로 동일하게 동작. 즉 **From = 원 트랜스퍼의 To** 로 통일하면 두 경우 다 처리됨.

## 5. bin GUID 조회 (`/ref/location`)
응답 행 키: `ID, Name, IsDefault, IsDeprecated, ParentID, Bins, FixedAssetsLocation, Address*, PickZones, IsCoMan, IsShopFloor, IsStaging`. ⚠️ `Location`/`Bin` 필드는 **없다**.
- 창고: `Name === "Asung - Edmonton"` (ParentID 없음). 그 창고의 **`Bins[]`** 배열에서 `Name === bin코드` → `.ID` (에드먼튼 Bins 628개 확인)
- ~~폴백: `ParentID === 창고ID` 인 child location…~~ → ⚠️ **2026-07-28 정정: 죽은 경로였다. 제거할 것** (아래).

### ⚠️⚠️ 2026-07-28 실측 — `/ref/location` 은 잘린다. **`Bins[]` 만 써라**

- **`Total` 2678 인데 `Limit=500` 으로 잘린다.** 잘린 500행 안에 **에드먼튼 child 가 0행**이었다 → child 폴백에 의존한 bin GUID 조회가 **첫 호출부터 실패**. (토론토는 우연히 앞 페이지에 있었을 뿐 안전하지 않았다.)
- ✅ **최상위 창고 행(`ParentID` 없음)의 `Bins[]` 에 그 창고 bin 이 전부 들어있다** — 에드먼튼 **628** · 토론토 **2047**. **페이지네이션 불필요.** 원소 = `{ ID(GUID), Name, IsDeprecated, IsStaging }`.
- ⚠️ **child-location 행의 `Name` 은 bin 이름이 아니다** — 예 `"071164313169"` 같은 바코드류다. 이름 매칭이 애초에 성립하지 않았다.
- 이름 비교는 `trim().toUpperCase()`, `IsDeprecated` 는 제외.
- 실사고(**TR-02935**, 2026-07-28): 이 때문에 bin 이동이 **한 건도 실행되지 않고** 전 품목(344 라인)이 집결 bin EZ010101 에 남았다.

# 참고 — Sale 필드 매핑 (실측 확정)
화면 **Comments** = API `Note` · 화면 **Shipping notes** = `ShippingNotes` · 화면 **Reference** = **`CustomerReference`** · **PriceTier** 는 최상위.
