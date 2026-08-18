# 2026-08-18 — 발주 입고 축이 틀렸다 (Advanced = `PutAway`)

⚠️ **이 문서는 어제(`f33260f`) 커밋을 부분적으로 뒤집는다.** 발주 소스 재설계 전에 반드시 읽을 것.
현재 배포본 `inv-collect@2026-08-17.7` 은 **Advanced 발주 입고를 잘못 읽고 있다.**

> **v2 (2026-08-18 오전 후반)** — 최초 커밋(`5eaa918`) 이후 §5 미확인 4건을 전부 실측으로 닫고
> `line_ref` 결론(`CardID`)을 추가했다. 재설계는 별도 세션에서 진행한다(§6).

선행 문서:
- `docs/sessions/2026-08-17-ledger-02b.md` — 원장 ②-b
- `docs/sessions/2026-08-17-evening-addendum.md` — 리시빙 작업자·PO-01083

---

## 1. 결론부터

**Advanced 발주의 입고 확정 축은 `StockReceived` 가 아니라 `PutAway` 다.**

| | 확정 축 | `LocationID`(bin) | `line_ref` |
|---|---|---|---|
| **Simple** 발주 | `StockReceived` | **있다** (실측 PO-00874) | `CardID`(필드 존재 확인) |
| **Advanced** 발주 | **`PutAway`** | SR 은 **null** · PA 에만 있다 | **`CardID`** (유일성 실측) |

현재 코드는 두 경우 모두 `StockReceived` 만 읽는다. 그 결과 **세 가지가 틀린다**(§4).

---

## 2. 실측 근거

### 2-1. `StockReceived` 와 `PutAway` 는 같은 입고의 두 표현

Advanced 문서 15건 표본(`UpdatedSince=2026-07-01`, SRS 있는 것):

```
PO-00525 SR:[AUTHORISED] PA:[AUTHORISED] 6/6      PO-00787 [AUTHORISED][AUTHORISED] 25/25
PO-00691 SR:[AUTHORISED] PA:[AUTHORISED] 14/14    PO-00788 [VOIDED,AUTHORISED][VOIDED,AUTHORISED] 51/51
PO-00698 SR:[AUTHORISED] PA:[AUTHORISED] 37/37    PO-00800 [AUTHORISED][AUTHORISED] 76/76
PO-00703 SR:[DRAFT]      PA:[AUTHORISED] 62/62 ⚠️ PO-00801 [AUTHORISED][AUTHORISED] 9/9
PO-00748 SR:[AUTHORISED] PA:[AUTHORISED] 56/56    PO-00803 [AUTHORISED][AUTHORISED] 12/12
PO-00749 SR:[AUTHORISED] PA:[AUTHORISED] 10/10    PO-00805 [VOIDED,AUTHORISED][VOIDED,AUTHORISED] 41/41
PO-00771 [AUTHORISED,AUTHORISED] × 2 51/51        PO-00807 [AUTHORISED][AUTHORISED] 60/60
PO-00777 SR:[AUTHORISED] PA:[AUTHORISED] 83/83
```

**15건 전부 `srLines == paLines`.** 블록 개수·블록별 상태도 짝을 이룬다(`VOIDED,AUTHORISED` 조합까지).

⇒ **둘 다 읽으면 정확히 두 배가 된다.** 하나만 골라야 한다.

**차이는 `LocationID` 뿐이다** (PO-01131 · PO-01083 실측):
```
SR: BIG02001|72|2026-08-17|null                      ← 창고 도착, 빈 미지정
PA: BIG02001|72|2026-08-17|c5a9c1a0-d279-…           ← 빈 배치 완료
```

⚠️ **예외 2건 — PA 가 더 많다**(다른 25건 표본): 빈 분할이며 수량은 일치 → §2-6.

### 2-2. ⚠️ SR 의 `Status` 는 재고 반영 여부를 말하지 않는다

| PO | SR Status | PA Status | Cin7 화면 | 실제 |
|---|---|---|---|---|
| **PO-00703** | **DRAFT** | AUTHORISED | Completed · `FULLY RECEIVED` | 62줄 입고됨 |
| **PO-01131** | **NOT AVAILABLE** | AUTHORISED | Applied | 62줄 3,570u 입고됨 |

PO-00703 은 `TaskID` 가 SR·PA 동일(`3c8cab02-…`)인데 상태만 다르다.
목록의 `StockReceivedStatus` 는 **AUTHORISED**, `CombinedReceivingStatus` 는 **FULLY RECEIVED**,
문서 `Status` 는 **COMPLETED** 다.

⇒ SR 의 `Status` 는 **stock receiving 단계 자체의 워크플로 상태**로 보이며,
**Advanced 에서는 put-away 까지 가야 확정이므로 SR 단계가 DRAFT/NOT AVAILABLE 로 남는다.**
📌 **재고 판단의 근거로 쓰면 안 된다.**

### 2-3. 블록은 receiving 횟수가 아니라 I&R 그룹이다

PO-00703 은 Cin7 화면에 stock receiving 이 **2건**(05/04, 05/05)인데 API 블록은 **1개**다:

```
StockReceived[0] TaskID=3c8cab02… IRNum=0 Status="DRAFT"      lines=62 dates={"2026-05-05":42,"2026-05-04":20}
PutAway[0]       TaskID=3c8cab02… IRNum=0 Status="AUTHORISED" lines=62 dates={"2026-05-05":42,"2026-05-04":20}
```

⇒ **분할 입고는 블록이 아니라 `Lines[].Date` 로 갈린다.** 기존 규칙("라인 단위라 분할 입고도 정확")이
여기서 실증됐다. 블록은 `InvoicingAndReceivingNumber`(I&R 그룹) 단위다.

### 2-4. ⚠️ `Type` 은 가변이다 — 문서의 고정 속성이 아니다

**Apply 시점에 Simple 이던 PO 12건이 현재 전부 Advanced 다.** 예외 없음.

| PO | Apply(토론토) | `LastUpdatedDate`(UTC) | 간격 |
|---|---|---|---|
| PO-01148 | 08-17 15:33 | 08-17 19:36 | **3분** |
| PO-01131 | 08-17 13:17 | 08-17 17:26 | **9분** |
| PO-01072 | 08-17 13:12 | 08-17 17:25 | **13분** |
| PO-01087 | 08-17 15:09 | 08-17 19:26 | **17분** |
| PO-01113 | 08-17 16:39 | 08-18 12:44 | 다음날 |

WMS `apply_note` 의 `cin7_type='…'` 이 Apply 시점 타입을 남긴다 — 최근 17건 중 **12건이 Simple**.

📌 **실무 흐름**: PO 는 Simple 로 발행 → 입고 → 여러 이유로 Advanced 로 전환(대개 Apply 후 10분 안팎).

⇒ **`simple_docs: 0` 은 이상이 아니라 정상이다.** 수집 조건이 `StockReceivedStatus` 가 서는 것(입고 후)인데
전환도 입고 후에 일어나므로, **수집이 Simple 상태를 볼 확률이 구조적으로 낮다.**
Simple 분기 코드는 유지하되(전환 전에 걸릴 수 있고 옛 문서도 있다) 0 을 결함으로 보지 말 것.

⚠️ **부수 효과**: 전환이 `LastUpdatedDate` 를 갱신하므로 **모든 PO 가 최소 두 번 `UpdatedSince` 에 잡힌다.**
→ `ON CONFLICT DO NOTHING` 문제가 가설이 아니라 **일상**이라는 뜻.

### 2-5. 엔드포인트 비대칭 — 한쪽만 소리를 낸다

| 조합 | 결과 |
|---|---|
| Advanced PO → `purchase?ID=` | **400** `This endpoint is deprecated and does not support Advanced Purchase…` |
| Simple PO → `advanced-purchase?ID=` | ⚠️ **200 + 빈 껍데기** (`Status:""`, `Lines:[]`) |

실측: PO-01131(Advanced)→400 · PO-00874(Simple)→200 빈 배열.

⇒ `Type` 판정이 틀렸을 때 **한 방향은 시끄럽게 실패하고 다른 방향은 조용히 0행**이 된다.
현재 코드는 목록 `Type` 을 따라가므로 정상 경로에서는 안 생기지만, **목록과 문서 상태 사이에 지연이 있으면**
가능하다(전환 직후).

📌 종전 서술 정정: 「`PO-00427` 은 두 엔드포인트로 형태가 갈린다」는 **위험을 과장한 것**이었다.
목록 `Type` 이 `"Simple Purchase"` 로 확정이므로 수집은 항상 `purchase?ID=` 로만 부른다.

### 2-6. ⚠️ 같은 SKU 가 여러 빈으로 쪼개진다 — `line_ref` 재설계 근거

25건 표본 중 2건에서 `paLines > srLines`:

```
PO-00936  srLines 109 → paLines 110   srQty 10,956 = paQty 10,956   SKU별 수량차 없음
PO-00944  srLines  95 → paLines  97   srQty 13,308 = paQty 13,308   SKU별 수량차 없음
```

**빈 분할이다.** 수량 총계·SKU별 합계가 완전히 일치하고 다른 사건이 섞인 것이 아니다.
PA 는 "무엇이 얼마나 **어느 자리로** 갔나"를 라인 단위로 나눠 담는다 — 원장이 bin 을 담는 설계에 정확히 맞는다.

**⚠️ 결정적 사례 — 같은 SKU · 같은 빈 · 날짜만 다름** (PO-00944):
```
KUZ77036[0] Qty=894 Date=2026-07-15 Loc=94f0a13d-…  CardID=975b04bf-…
KUZ77036[1] Qty=6   Date=2026-07-16 Loc=94f0a13d-…  CardID=f624002f-…
```
원장 유니크 키 `(doc_type, doc_number, line_ref, event_type, warehouse, bin, sku)` 에는
**`occurred_on` 이 없다.** `line_ref = ProductID` 면 **이 두 줄이 한 행으로 뭉개진다** —
판매에서 fulfilment TaskID 를 붙인 것과 정확히 같은 구조.

**후보 키 유일성 실측**:

| 키 | PO-00944 (97줄) | PO-00936 (110줄) | 판정 |
|---|---|---|---|
| `ProductID` | 94 | 109 | ❌ 뭉개짐 |
| `ProductID+LocationID` | 96 | 110 | ❌ 부족(같은 빈 2줄) |
| `ProductID+Loc+Date` | 97 | 110 | △ 날짜가 유니크 키에 없어 사용 불가 |
| **`CardID`** | **97** | **110** | ✅ |
| `ID` | 1 | 1 | ❌ 필드 없음(`undefined`) |

⇒ **발주 `line_ref` = `CardID`**

📌 스킬에 「발주의 진짜 라인 식별자 CardID 는 raw 원문에만 남는다」고 적혀 있다 —
당시엔 다른 소스와 통일하려 `ProductID` 를 썼으나, **빈 분할이 실재하므로 통일보다 정확성이 우선.**

⚠️ **미확인**: `CardID` 가 **재수집에도 안정적인가.** `Type` 전환 시 PA 라인이 재생성되며 `CardID` 가
바뀌면 같은 입고가 두 번 쌓인다(유니크 키가 달라 충돌도 안 난다).
→ **다음 전환 케이스를 관찰**할 것: 오늘 Apply 되는 PO 의 `CardID` 를 전환 전후로 기록.

---

## 3. Simple 발주 검증 결과 (미해결 항목 1 — 해소)

`PO-00874` 실측:
```
list: Type="Simple Purchase" ID=a32c6ab9-…
purchase?ID= → StockReceived isArray=false type=object
  keys=["Status","Lines"]  Status="AUTHORISED"
  Lines[0] keys=[Date, Quantity, ProductID, SKU, Name, Location, LocationID, Received, BatchSN,
                 SupplierSKU, ExpiryDate, CardID, …]
  Lines[0] Date=2026-06-09  Qty=1200  SKU=AS00879BLA  LocationID=f1ca3946-… ✅
```

⇒ **엔드포인트 판정 정확**(`"Simple Purchase"` 에 ADVANCED 없음 → `purchase?ID=`),
**객체 정규화 정확**(`Array.isArray ? … : [det.StockReceived]`),
**Simple 은 SR 에 `LocationID` 가 있다.** `CardID` 도 존재한다.

📌 `Lines[0].Date = 2026-06-09` — 6월 입고 라인이 지금도 살아 있다. **날짜 축 분리**(어제 확인)의 재확인.

---

## 4. ⚠️ 현재 배포본(`.7`)이 틀린 것 3가지

### ① Advanced 입고의 bin 이 전부 null

SR 을 읽으므로 `LocationID` 가 없다. **어제 dry 의 `ledger_rows 1,594` 대부분이 자리 정보 없이 쌓인다.**
원장은 `warehouse`·`bin` 을 담는 설계인데 Advanced 입고에서 bin 이 통째로 비는 것 — **가장 큰 문제.**

### ② `NOT AVAILABLE` 제외가 실재 입고를 지운다

어제 `f33260f` 에서 화이트리스트(`AUTHORISED`·`""` 만 통과)로 바꾸며 `sr_blocks_skipped`
VOIDED 1 · NOT AVAILABLE 3 → `ledger_rows` **1,684 → 1,594 (−90행)** 를 "유령 재고 차단"으로 판정했다.

⚠️ **그 판정이 틀렸다.** PO-01131 처럼 SR=NOT AVAILABLE 인데 PA=AUTHORISED 인 실재 입고가 있다.
**제거한 90행 중 상당수가 진짜 입고였을 가능성이 크다.**

📌 화이트리스트 **방향 자체는 옳다**(블랙리스트는 미지값을 조용히 통과시킨다). 틀린 것은
**어느 배열의 상태를 보느냐**다. `PutAway` 로 축을 옮기면 이 문제가 자연히 사라진다.

### ③ SR `DRAFT` 제외가 실재 입고를 지운다

PO-00703: SR=DRAFT · PA=AUTHORISED · 62줄 · `FULLY RECEIVED`.
현재 코드는 `bst === "DRAFT"` 를 건너뛰므로 **62줄이 통째로 누락된다.**

📌 종전 근거였던 「PO-01083 DRAFT 194개가 재고에 없음」은 **DRAFT 가 곧 미반영이라는 뜻이 아니었다** —
표본 하나의 일반화였다(2026-08-17 세션의 그 교훈이 또 반복됐다).

---

## 5. 미확인 4건 — 전부 실측으로 닫힘 (v2)

### ① `PutAway` 누락 문서 — 없음 (관행 확인)

`UpdatedSince=2026-07-15` Advanced 93건 중 30건 상세 조회 (⚠️ `StockReceivedStatus` 필터를 **빼고**
조회 — "도착했지만 빈 미배치" 상태를 배제하지 않기 위해):

```
noPA = 0 / 30
Advanced SRS 분포 = {AUTHORISED: 88, NOT AVAILABLE: 4, VOIDED: 1}
```

⇒ **PA 는 무조건 한다**는 실무 관행이 데이터로 확인됐다.

⚠️ 단 이 표본은 **완료된 문서 기준**이다. 조회 시점에 진행 중인 PO(WMS 의 "Awaiting putaway" 상태)는
포함되지 않았을 수 있다. → **설계에서는 PA 가 비면 `hold`** (잔고가 움직이는데 자리 불명 =
이동 소스의 날짜 결손과 같은 취급).

### ② `PutAway` 블록 상태 어휘

```
PA block status = {AUTHORISED: 35, VOIDED: 3}
```

⇒ **화이트리스트 `AUTHORISED` 만 통과 + 미지값 경고.**
⚠️ **표본으로 어휘를 확정하지 말 것** — 어제 `NOT AVAILABLE` 로 정확히 그렇게 틀렸다.

### ③ `InventoryMovements` — 축으로 쓸 수 없음

```
{TaskID, ProductID, Date, COGS, ProductLength/Width/Height/Weight, WeightUnits,
 DimensionsUnits, ProductCustomField1~10}
```

**`Quantity` 도 `LocationID` 도 없다.** COGS(원가)와 상품 치수뿐 — 수량 축이 아니다.
📌 나중에 **원가 레이어** 작업에는 쓸 수 있다(라인 단위 COGS 가 들어 있다).

### ④ 주문 외 SKU — 실재하나 축 선택에 영향 없음

30건 중 3건(PO-00771 · PO-00851 · PO-00894)에서 `Order` 에 없는 SKU 가 입고됨.

```
PO-00771 orderSKU=47  SR에만(주문외)=[AIA03589, AIA06037, …]  PA에만(주문외)=[AIA06036, …]  SR엔없고PA에만=[]
PO-00851 orderSKU=77  SR·PA 양쪽 동일 4종                      SR엔없고PA에만=[]
PO-00894 orderSKU=72  SR·PA 양쪽 동일 1종(ORS11176)            SR엔없고PA에만=[]
```

⇒ 주문 외 제품은 **SR·PA 양쪽에 똑같이** 들어온다. **PA 만의 유령 라인은 없다.**
어느 축을 골라도 잡히며, **실제로 들어온 물건이므로 거르지 않는다**(`Order` 대조 불필요).

---

## 6. 재설계 (별도 세션에서 진행)

확정된 설계 재료:

| 항목 | 결론 |
|---|---|
| Advanced 축 | **`PutAway`** (bin 있음 · 상태가 확정 반영) |
| Simple 축 | `StockReceived` (bin 있음) |
| 블록 상태 | 화이트리스트 **`AUTHORISED` 만** + 미지값 경고 |
| PA 없음 | 실무상 없음 — 그래도 **hold** |
| 주문 외 SKU | 정상 입고, 거르지 않음 |
| `line_ref` | **`CardID`** (⚠️ 재수집 안정성 미확인) |
| `InventoryMovements` | 미사용(수량 없음) — 원가 레이어용으로 보류 |
| 날짜 | `Lines[].Date` (라인 단위 — 분할 입고 정확) 유지 |

⚠️ **commit=1 은 재설계가 끝나기 전에 켜지 말 것.** 지금 켜면 bin 없는 입고와 누락된 입고가
그대로 원장에 굳는다.

재설계 후 할 일:
1. dry 로 bin 이 채워지는지 · 행 수가 어떻게 변하는지 확인
2. `f33260f` 의 판정(`−90행 = 유령 재고 차단`)을 `ledger-design.md`·스킬에서 정정
3. `asung-inv-ledger` 스킬의 발주 항목 전면 개정 + claude.ai 재업로드

---

## 7. 오늘 함께 처리된 것

- **`WMS_CRON_SECRET` 교체 완료** + `cron.job` 4·5(`wms-image-sync`, `-retry`) 헤더 갱신.
  ⚠️ 내일 08:30·09:30(토론토)에 `product-images` 가 실제로 도는지 확인할 것.
  jobid 1(`wms-poll-orders`)은 이 시크릿을 쓰지 않는다.
  📌 Supabase Secrets 는 **저장된 값을 다시 보여주지 않는다**(digest 만 표시) — 값을 잃으면 교체가 유일한 길.
- **②-a 회귀 대조 3종 통과** — 어제 못 한 "동일성 대조"를 오늘 재실행으로 확보:
  ```
  transfer   654 · TR-03974 · 08-14=554 · 08-17=100          ← 완전 동일
  assembly    21 · FG-00120 · 08-04=5 · 08-06=11 · 08-08=5   ← 완전 동일
  adjustment  47 · ST-01214 · 과거 칸 전부 동일, 08-17 13→17 · 08-18 +1  ← 신규 유입만
  ```
  ⇒ **공유 sink 추출(`2459c02`)이 ②-a 동작을 바꾸지 않았다 — 세 소스 모두 확정.**
- ⚠️ **Cin7 API 키가 WMS/GAS 로 분리되어 있다** — `cin7-api` 스킬 173·182행의
  「여러 프로세스가 같은 계정 공유」서술이 낡았다. **스킬 정정 필요.**
- **API 한도 실측은 집에서** — 업무 시간에 WMS 키를 소진하면 리시빙·폴링이 멈춘다.
  확인할 것: 한도가 **키 단위인지 계정 단위인지**(WMS 키 소진 상태에서 GAS 키가 정상이면 키 단위),
  그리고 `DETAIL_SLEEP_MS=700ms`(분당 85콜)가 실제로 초과인지.
- **리시빙 라인별 작업자 검증** — 오전 기준 0행(작업 전). 오늘 리시빙이 돌면 확인:
  ```sql
  select r.po_number, l.last_received_by, count(*) as lines,
         min(l.last_received_at at time zone 'America/Toronto') as first_touch,
         max(l.last_received_at at time zone 'America/Toronto') as last_touch
  from wms_receipt_lines l join wms_receipts r on r.id = l.receipt_id
  where l.last_received_by is not null
  group by 1,2 order by 1,3;
  ```
  ⚠️ **PO-01113 은 오늘도 화면에 안 나온다** — 컬럼 도입 전 라인이라 NULL, `created_at` 은 08-14.
  「안 고쳐졌다」고 오판하지 말 것.
