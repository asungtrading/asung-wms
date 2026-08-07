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
  before StockReceived". Asung 은 전 PO Invoice First. 확인: **PO 상세 응답의 Invoice 블록**
  (`purchase.md` 「인보이스 블록 실측」 — `Array.isArray(d.Invoice)?d.Invoice[0]:d.Invoice` 의 `Status`).
  ⚠️ **정정 (2026-08-05)** — 종전 안내였던 `GET /purchase/invoice?TaskID=` 는 **Advanced PO 에서
  400** ("deprecated and does not support Advanced Purchase"): 신규 코드에 쓰지 말 것.
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

## ⚠️⚠️ Advanced PO stock received — Simple 과 전혀 다르다 (2026-08-07 실측, PO-01094 프로브)

주소·식별자·응답이 다르다는 것은 SKILL.md 주의사항 13. 여기는 **쓰기 실측 4건**:

1. ⚠️⚠️ **`POST /advanced-purchase/stock` 의 `Lines[].LocationID` 는 저장되지 않는다** — bin GUID 를
   실어 보내도 200 후 되읽으면 `LocationID:null, Location:null`. **Advanced 는 "재고 넣기"(stock
   received)와 "선반 지정"(put-away)이 분리**돼 있다(별도 엔드포인트 `/advanced-purchase/put-away`,
   apib 17347행). Simple 처럼 한 번에 안 된다 — bin 을 실었는데 조용히 사라지는 종류라 **200 만 보면
   전 라인이 bin 없이 들어간다**(되읽기 원칙의 또 한 사례).
2. **"문서당 bin 1개" 제약이 없다** — 한 태스크에 다른 bin 라인 append 가 200 (Simple 의 400
   "Lines is invalid" 와 다름). 단 1번 때문에 stock received 단계에서 bin 은 의미가 없다.
3. ⚠️⚠️ **`DELETE /advanced-purchase/stock?TaskID=` 는 200 을 주지만 태스크를 지우지 않는다**
   (Void 기본값 false=Undo 로 호출·재확인 실측). 라인은 Cin7 화면에서 수동으로 지웠고 빈 태스크는
   그래도 남았다. **API 로 입고 태스크를 제거하는 방법은 미확인** — "200 은 반영을 뜻하지 않는다"
   (TransferQuantity 무시·파라미터 오타와 같은 R11 계열)의 세 번째 실측. 프로브·쓰기를 설계할 때
   **지울 수 있다고 가정하지 말 것.**
4. **빈 DRAFT 태스크는 무해하게 남는다**(재고 영향 없음, `Lines:[]`) — PO-01094 에 실재
   (TaskID `44e2f761-5f39-4ec4-bb55-fb7e1d1abf66`). ~~지울 수 없으므로 후속 쓰기는 회차 시작에
   GET 으로 기존 DRAFT 태스크를 찾아 재사용(append)하는 설계가 필수다~~ → ⚠️⚠️ **2026-08-07 후반
   정정: "아무 DRAFT 나 재사용"이 실사고 2호를 키웠다**(그 빈 태스크가 잘못 만들어진 I&R 그룹이었고,
   재사용 로직이 그 그룹에 계속 썼다). **재사용이 아니라 11번의 타깃 지정** — TaskID 는 항상 승인
   인보이스에서 유도하고, 다른 태스크는 라인이 있으면 중단·없으면 무시.

프로브 도구: asung-wms repo `docs/probes/WmsAdvPoStockProbe.gs` (교차 조합·자체 정리 시도 포함).
put-away 요청 스펙은 apib 17347행(`PurchaseID`+`TaskID`+`Status`+`Lines[{…,Location/LocationID 필수*}]`,
authorize 는 빈 Lines POST).

### 읽기 프로브 R1~R3 추가 실측 (2026-08-07, PO-01068 이력 + PO-01094)

5. **stock 과 put-away 는 별개 문서가 아니라 한 태스크의 두 면이다** — 같은 `TaskID` 를 공유
   (PO-01068 둘 다 `f7188ac1…`, PO-01094 둘 다 `44e2f761…`). put-away 태스크를 따로 만들/찾을
   필요 없이 stock 태스크의 TaskID 로 put-away 를 쓴다.
6. **stock authorize 가 put-away 의 선행조건이다** — stock 이 DRAFT 인 동안 put-away 는
   `NOT AVAILABLE`(PO-01094 실측). 정상 이력(PO-01068)은 stock AUTHORISED + put-away
   AUTHORISED + bin GUID·이름이 put-away 라인에 채워져 있다 → **put-away 가 이 계정의 정식
   선반 지정 경로**(Use Put Away 흐름 실사용 확인).
7. ⚠️ **순서 위반을 스펙이 막지 않는다** — put-away POST 의 예외 조건은 "status 가 DRAFT/
   NOT AVAILABLE 이 아닐 때"라서 NOT AVAILABLE(=stock 미승인) 중 POST 가 명문상 허용으로
   읽힌다. 조용한 수용/무시 가능성(위 3번 전과)을 배제할 수 없으므로 **호출측이 순서를 강제**
   (stock authorize 되읽기 확인 후에만 put-away)하고 모든 쓰기를 되읽어 검증할 것.
8. **따라서 불가역 지점 = stock authorize** — 여기서 재고가 창고 레벨(bin 없음)로 들어가고,
   put-away 실패 시 "bin 없는 재고"로 남는다(트랜스퍼 (a) 착지와 같은 형태 — put-away 재시도로
   회복. 진짜로 못 되돌리는 것은 수량 투입뿐).
9. **WMS 확정 설계 (2026-08-07)**: stage1 = SKU 합산 단일 POST(같은 SKU 를 나눠 보내면
   location null 중복 400 — 합산 필수) + authorize / stage2 = **put-away 단일 AUTHORISED
   POST**(그룹별 DRAFT 는 폐기 — "invoice lines match the receiving → only AUTHORISED value
   accepted" 조건이 정확 수령에서 DRAFT 를 결정론적 400 으로 만든다. AUTHORISED POST 는 항상
   허용). ⚠️ **"잘못 놓인 bin 은 stockTransfer 로 정정"은 미실측 추정** — bin↔bin 이동 자체는
   표준 실측(TR-03236)이나 **put-away 로 놓인 재고에 실측한 적은 없다.** 확정처럼 인용하지 말 것.
   구현·재개 멱등성은 asung-wms 규칙 21 Advanced 절.
10. ⚠️⚠️ **GET 응답의 태스크 `Status` 를 정확한 문자열로 신뢰하지 말 것 (2026-08-07 PO-01094 실사고)** —
    `Status==="DRAFT"` 로 승인 대상을 고른 코드에서 승인 루프가 **0회** 돌았다(원문 문자열 미확정 —
    수정 코드가 매 실행 태스크별 Status 원문을 로그로 남기므로 다음 Apply 가 확정한다). 같은
    엔드포인트에서 apib 가 LocationID 도 틀렸다(1번). **상태 판정은 부재 증명("DRAFT 없음")이 아니라
    존재 증명("전부 정확히 AUTHORISED 로 되읽힘")으로**, 비교는 trim+대문자 정규화로, 실패는
    fail-closed 로. 계획 문구·계획서는 실행 검증이 아니다 — 실행 경로는 응답 로그(`PATH=`)로 확인.
11. ⚠️⚠️ **Advanced 의 `TaskID` 는 I&R(Invoicing & Receiving) 그룹 식별자다. 지정하지 않으면 새 그룹이
    생기고 빈 DRAFT 인보이스가 딸려 만들어진다. 반드시 승인된 인보이스의 TaskID 를 지정할 것.**
    (2026-08-07 PO-01094 실사고 2호 실측: TaskID 없이 stock POST → Cin7 이 새 그룹 #1 생성 + 빈
    DRAFT 인보이스 자동 생성 → 승인 인보이스(#63467, 그룹 #0=cf791a11…)와 입고가 영구히 갈라짐.
    프로브 탓이 아니라 TaskID 생략의 구조적 결과 — 모든 Advanced PO 에서 재현된다.)
    · **타깃 유도**: PO 상세의 `Invoice[]` 원소가 `TaskID`·`InvoicingAndReceivingNumber` 를 갖는다 —
      `Status ∈ {AUTHORISED, PAID}` && TaskID 있는 인보이스가 **정확히 1개**일 때만 그 TaskID 로 진행.
      0개(타깃 불능)·2개+(다중 인보이스 부분 출하 — 어느 출하의 입고인지 알 수 없음)는 **중단**.
    · put-away 도 같은 TaskID 를 쓴다(같은 그룹의 두 면 — 5번). stock·put-away 모두 **TaskID 생략 경로 금지**.
    · **외부 그룹 가드**: 타깃이 아닌 태스크에 라인이 있으면(상태 불문 비VOID) 중단 — 그 라인이
      승인돼 있으면 이미 재고라서 타깃 그룹에 재전송 시 **이중 재고**. 사람이 Cin7 에서 정리 후 재시도.
    · "기본 그룹의 TaskID == PurchaseID"(PO-01068 관찰)는 **미확인이며 의존하지 않는다** —
      타깃은 항상 인보이스에서 유도한다.

## purchaseList 필터 실무 노트

📌 **필터·페이징 실측 전체는 `purchase.md` 「필터·페이징 실측」 표** — `InvoiceStatus` 는 단일 값 · `Limit=1000` 동작 · **기본 정렬이 PO 번호 오름차순**(최신 PO 는 마지막 페이지) · `UpdatedSince` 는 최신성 보장 못함.

⚠️⚠️ **2026-08-04 정정 2건 — 아래 줄에 예전에 적혀 있던 두 문장이 틀렸거나 폐기됐다** (경위는 `purchase.md` 「정정 — 파라미터 이름 오타」·「`InvoiceStatus` 로 좁히지 말고 `Status` 로」):

1. ~~"`RestockReceivedStatus` 무시됨"~~ → 무시되는 것은 **이름을 잘못 쓴 쪽**이다. 올바른 이름 **`StockReceivedStatus` 는 동작한다**(2026-08-04 실측 `NOT AVAILABLE` Total **585** vs 오타 `RestockReceivedStatus` 877=무필터). 이 오기록이 "서버 필터 불가" 라는 결론을 일주일간 유지시켰다.
2. ~~"`InvoiceStatus=AUTHORISED` + PAID 2회 병합 = 리시빙 준비 필터"~~ → **좁히는 축으로 폐기.** 사실 자체(파라미터 지원·단일 값·AUTHORISED 만 보면 PAID 로 넘어간 PO 누락 — 실측 PO-01081)는 그대로 유효하지만, `InvoiceStatus=PAID` 는 창업 이후 지불을 마친 **모든** PO(2026-08-04 실측 877건, 그중 리시빙 대상 **0건**)를 돌려줘 전량을 긁고 클라이언트에서 버리는 구조였다. **좁힐 땐 `Status`**(INVOICED 73 + RECEIVING 5 — 완료된 PO 는 COMPLETED 로 빠지므로 데이터가 쌓여도 조회량이 안 늘어난다). Invoice First 검사는 클라이언트로 옮겼다(asung-wms 규칙 20).
여전히 유효한 실무 사실:

- Status 는 **복합 문자열**("RECEIVED / CREDITED") 가능 — 정확 일치 말고 includes 로 검사.
- Type 에 "Service"(운송·관세 주문 — 물건 없음) 존재 — 리시빙 목록에서 제외 필요(⚠️ `Type` 서버 필터는 무시된다 — 2026-08-04 실측).

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
- ⚠️ **이 400 은 안전장치이기도 하다 (2026-07-31)**: "POST 는 성공했는데 호출측 체크포인트 기록 전에 프로세스가 죽은" 잔여물을 재전송하면 이 에러로 **시끄럽게 거부**된다 → **조용한 이중 계상이 구조적으로 없다.** 이 에러를 받으면 = 그 라인은 이미 DRAFT 문서에 있다는 뜻 — Cin7 화면에서 확인 후 거기서 마무리하면 된다(WMS Apply PO 경로가 되읽기 회복 없이 안전한 근거).

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

# ⚠️⚠️ 2026-07-31 실측 — 트랜스퍼 Put away 는 v2 API 에 없다 (탐색 종결 — 같은 탐색 반복 금지)

Cin7 UI 의 트랜스퍼 문서에는 `Put away` 옵션이 있고, 켜면 라인별 `LOCATION` 컬럼이 생긴다. "이걸 API 로 쓰면 bin 별 미니 트랜스퍼가 필요 없지 않을까"는 **이미 끝까지 탐색했고 답은 없다** (TR-03259 실측):

- `/stockTransfer/putaway`·`putAway`·`put-away`·`pick`·`stock`·`received`·`receive` → **전부 HTML "Page not found"**
- `/stockTransfer/order` → 정상 JSON 이지만 **라인에 위치 필드 없음**
- 본 문서(`/stockTransfer?TaskID=`) 응답 헤더에 **`PutAway` 플래그조차 없다** — UI 에서 체크·저장해도 API 응답에 반영되지 않는다
- Put away 탭에는 **CSV Import 버튼도 없다** — 수동 대량 입력 우회도 불가

→ **결론: 헤더 `To` 착지 + bin 별 별도 트랜스퍼 문서가 유일한 API 경로다.** (asung-wms 스킬 규칙 38 과 동일 기록.)

# `/ref/productavailability` 로 bin 단위 재고 확인 (2026-07-31 — 쓰기 되읽기 검증의 표준 도구)

쓰기 후 검증(위 원칙 — 200 이 아니라 되읽은 값)과 bin 단위 재고 확인은 `GET /ref/productavailability?Sku=<SKU>` 로 한다. 응답 행 = SKU × Location × Bin 단위(`OnHand`/`Available`/`OnOrder`/`InTransit`…).

- ⚠️ **판정은 `OnHand` 로** — `Available` 은 판매 주문 배정(allocation)이 차감된 값이라 "물리적으로 도착했는가" 판정에 쓰면 **오판한다**(도착했는데 배정 때문에 0 으로 보임).
- 매칭은 **SKU 정확 일치 + 창고 + Bin 정확 일치**. 같은 SKU 가 여러 행(창고×bin)으로 오므로 대상 bin 행들의 **OnHand 합**으로 본다.
- ⚠️ **응답 잘림 방어**: `Total > 반환 행 수` 면 그 조회로 단정하지 말 것(미확인 처리). 애매하면 "확인 실패" 로 유지 — 잘린 응답을 근거로 완료 판정하면 안 된다.

# 참고 — Sale 필드 매핑 (실측 확정)
화면 **Comments** = API `Note` · 화면 **Shipping notes** = `ShippingNotes` · 화면 **Reference** = **`CustomerReference`** · **PriceTier** 는 최상위.
