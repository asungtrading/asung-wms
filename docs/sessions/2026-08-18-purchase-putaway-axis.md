# 2026-08-18 — 발주 입고 축이 틀렸다 (Advanced = `PutAway`)

⚠️ **이 문서는 어제(`f33260f`) 커밋을 부분적으로 뒤집는다.** 발주 소스 재설계 전에 반드시 읽을 것.
현재 배포본 `inv-collect@2026-08-17.7` 은 **Advanced 발주 입고를 잘못 읽고 있다.**

선행 문서:
- `docs/sessions/2026-08-17-ledger-02b.md` — 원장 ②-b
- `docs/sessions/2026-08-17-evening-addendum.md` — 리시빙 작업자·PO-01083

---

## 1. 결론부터

**Advanced 발주의 입고 확정 축은 `StockReceived` 가 아니라 `PutAway` 다.**

| | 확정 축 | `LocationID`(bin) |
|---|---|---|
| **Simple** 발주 | `StockReceived` | **있다** (실측 PO-00874) |
| **Advanced** 발주 | **`PutAway`** | SR 은 **null** · PA 에만 있다 |

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
→ §5 의 `ON CONFLICT DO NOTHING` 문제가 가설이 아니라 **일상**이라는 뜻.

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

---

## 3. Simple 발주 검증 결과 (미해결 항목 1 — 해소)

`PO-00874` 실측:
```
list: Type="Simple Purchase" ID=a32c6ab9-…
purchase?ID= → StockReceived isArray=false type=object
  keys=["Status","Lines"]  Status="AUTHORISED"
  Lines[0] keys=[Date, Quantity, ProductID, SKU, Name, Location, LocationID, Received, BatchSN, …]
  Lines[0] Date=2026-06-09  Qty=1200  SKU=AS00879BLA  LocationID=f1ca3946-… ✅
```

⇒ **엔드포인트 판정 정확**(`"Simple Purchase"` 에 ADVANCED 없음 → `purchase?ID=`),
**객체 정규화 정확**(`Array.isArray ? … : [det.StockReceived]`),
**Simple 은 SR 에 `LocationID` 가 있다.**

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

## 5. 아직 모르는 것 (설계 전에 확인)

1. **`PutAway` 가 없거나 미완료인 Advanced 문서** — 창고 도착했지만 빈 미배치 재고.
   표본 15건은 전부 PA 가 있었으나 **진행 중 문서는 다를 수 있다**(WMS 의 "Awaiting putaway" 가 그 상태).
   → 그런 재고를 원장에 어떻게 담을지: 이동 소스의 `IN_TRANSIT` 같은 합성 자리가 필요한가?
2. **`PutAway` 블록 상태 어휘 전수** — VOIDED 는 봤다. ⚠️ **또 표본으로 화이트리스트를 만들지 말 것.**
   미지값 경고는 유지.
3. **`InventoryMovements`** — 최상위 키에 존재. **더 나은 축일 가능성**이 있어 구조 확인 필요.
4. **전환으로 원장 행이 달라지는가** — §2-4 로 재수집이 일상임이 확정됐다.
   Simple(SR·bin 있음) → Advanced(PA 축) 로 바뀌면 **같은 입고의 `line_ref`·`bin` 이 달라질 수 있다.**
   ⚠️ 유니크 키에 `occurred_on` 이 없고 `ON CONFLICT DO NOTHING` 이므로 **옛 값이 남고 차이가 조용히 묻힌다.**
   → **commit=1 켜기 전 필수 결정**(2026-08-17 문서 §7-3 과 같은 항목, 이제 긴급도 상승)

---

## 6. 다음 작업 순서 (제안)

1. §5 의 1~3 확인 (GAS 프로브 · 읽기 전용)
2. 발주 소스 재설계 — Simple=SR / Advanced=PA 분기, 블록 상태 화이트리스트 재정의
3. dry 로 bin 이 채워지는지·행 수가 어떻게 변하는지 확인
4. `f33260f` 의 판정(`−90행 = 유령 재고 차단`)을 문서에서 정정

⚠️ **commit=1 은 이 재설계가 끝나기 전에는 켜지 말 것.** 지금 켜면 bin 없는 입고와
누락된 입고가 그대로 원장에 굳는다.

---

## 7. 오늘 함께 처리된 것

- **`WMS_CRON_SECRET` 교체 완료** + `cron.job` 4·5(`wms-image-sync`, `-retry`) 헤더 갱신.
  ⚠️ 내일 08:30·09:30(토론토)에 `product-images` 가 실제로 도는지 확인할 것.
  jobid 1(`wms-poll-orders`)은 이 시크릿을 쓰지 않는다.
- **②-a 회귀 대조 3종 통과** — 어제 못 한 "동일성 대조"를 오늘 재실행으로 확보:
  ```
  transfer   654 · TR-03974 · 08-14=554 · 08-17=100   ← 완전 동일
  assembly    21 · FG-00120 · 08-04=5 · 08-06=11 · 08-08=5  ← 완전 동일
  adjustment  47 · ST-01214 · 과거 칸 전부 동일, 08-17 13→17 · 08-18 +1  ← 신규 유입만
  ```
  ⇒ **공유 sink 추출(`2459c02`)이 ②-a 동작을 바꾸지 않았다 — 세 소스 모두 확정.**
- ⚠️ **Cin7 API 키가 WMS/GAS 로 분리되어 있다** — `cin7-api` 스킬 173·182행의
  「여러 프로세스가 같은 계정 공유」서술이 낡았다. **스킬 정정 필요.**
- **API 한도 실측은 집에서** — 업무 시간에 WMS 키를 소진하면 리시빙·폴링이 멈춘다.
  확인할 것: 한도가 **키 단위인지 계정 단위인지**(WMS 키 소진 상태에서 GAS 키가 정상이면 키 단위),
  그리고 `DETAIL_SLEEP_MS=700ms`(분당 85콜)가 실제로 초과인지.
