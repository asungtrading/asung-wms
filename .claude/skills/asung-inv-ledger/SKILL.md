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

**진행 상태 (2026-08-18)**: 테이블 4개 + 스냅샷 EF(`inv-snapshot`) + 수집 EF(`inv-collect` —
②-a 전량 축 3종·②-b 증분 축 3종) **배포·dry 검증 통과** · 현재 `@2026-08-18.2`(발주 PutAway 축
재설계 + PA 어휘 DRAFT — `docs/sessions/2026-08-18-purchase-source-redesign.md`). **쓰기는 아직 안 켰다.**
기초 스냅샷 8/22 예정. ⚠️ **발주 축은 미검증 2건(adv_no_putaway 경로 · 재등장 전제)이 남아 있어
`commit=1` 금지 — 설계 정본 4부 「commit=1 을 켜기 전에 닫아야 하는 것」 체크리스트를 먼저 닫을 것.**
(~~CardID 재수집 안정성~~ 은 2026-08-18 저녁 PO-01117 실측으로 닫힘 — Convert 를 통과해도 유지.)

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
| `ProductID` 가 라인 식별자? | 상품 ID 다. 같은 SKU 두 줄이면 겹침. **다만 실무상 안 겹쳐서 line_ref 로 씀** (⚠️ 판매 예외 — 5절) |
| 발주 블록 `Status` 는 DRAFT 만 제외? | **아니다 — 그리고 어느 배열의 상태를 보느냐가 먼저다(08-18).** 화이트리스트 = **PA 축 기준 `AUTHORISED` 만** + 미지값 경고. ~~SR 기준 AUTHORISED·`""` 통과(08-17)~~ 는 폐기 — 빈 문자열 예외의 근거 PO-01128 은 빈 상태가 **SR 블록**이었다(PA 는 AUTHORISED 84줄). SR 상태로 거른 "−90행 유령 재고 차단" 판정도 무효(실재 입고를 지운 것) |
| 발주 입고는 `StockReceived` 를 읽으면 되나? | **아니다(2026-08-18 확정).** Advanced = **`PutAway`** / Simple = `StockReceived`. SR 은 ① `LocationID` 가 null 이거나 창고 GUID 라 **bin 이 구조적으로 없다** ② `Status` 가 stock receiving 단계의 **워크플로 상태**라 재고 반영 여부가 아니다(PO-00703 SR=DRAFT/PA=AUTHORISED · PO-01131 SR=NOT AVAILABLE/PA=AUTHORISED 3,570u). SR·PA 는 같은 입고의 두 표현 — 둘 다 읽으면 두 배 |
| 목록 `StockReceivedStatus` 로 후보를 좁히면? | **안 된다.** 상세 블록 상태와 **상관이 없다**(양방향 불일치 — PO-01131 목록 AUTHORISED/상세 NOT AVAILABLE ↔ PO-00848 반대). 표본 6건 중 4건(12,552u)이 실재 입고인데 문서째 유실됐다. 판정 권한은 상세 한 곳 — 목록 값은 분포만 센다 |
| `saleCreditNoteList` 행은 CN 단위? | **아니다. sale 단위.** 목록 `RestockStatus` 로 거르면 같은 오더의 AUTHORISED CN 이 유실 — 판정은 상세 `CreditNotes[]` 순회 한 곳만 |
| `Restock[]` 이 비면 DRAFT? | **아니다.** AUTHORISED+빈 배열 실재(표본 하나 CR-00024 의 일반화였다) — 판정은 배열 실제 길이로 |
| `UpdatedSince` 로 받으면 그 기간 이벤트만? | **아니다. 갱신 축과 이벤트 날짜는 분리** — 8월 갱신 문서가 4월 이벤트를 품는다. **`since=`(이벤트 필터)가 스냅샷 경계 방어 — 쓰기 켤 때 필수.** `from_since` 는 커서 씨앗으로 딴 것 — 혼동 금지 |
| `SR=[""]` 빈 상태 블록을 이상 신호로 볼 것인가? | **아니다. Convert 를 거친 문서의 정상 흔적**(라인이 PA 로 옮겨간 뒤 껍데기만 남는다 — PO-01117 실측: Convert 직후 SR 0줄·PA 51줄, CardID 동일) |

### 조사 자체에서 반복된 실패 (같은 실수 반복 금지)

- **1페이지만 받고 판정** — `/transactions` 30일이 6,451행인데 1,000행만 보고 "86% 미대응"이라 오판.
  전량 받으니 **87% 일치**로 정반대였다. **Total 과 수신 행 수를 항상 대조할 것**
- **정렬 가정** — 목록 앞쪽 1,000행이 전부 UOM 집계행이라 "빈 지정 0%"로 오판
- **파라미터 이름 추측** — `stockadjustment?ID=` 로 400. 문서엔 `TaskID` 로 적혀 있었다
- **대조군 없이 판정** — Cin7 은 모르는 파라미터를 조용히 무시한다.
  존재하지 않는 이름(`ZzzNotARealParam`)을 같이 던져 "무시" 기준선을 만들 것
- **표본 하나에서 규칙을 만들었다** (2026-08-17) — 명세 전제 4개 중 3개가 실측에서 깨졌다
  (발주 블록 상태 어휘 · CN 행 단위 · 빈 Restock). **블랙리스트는 처음 보는 값을 조용히
  통과시킨다 → 화이트리스트 + 미지값 경고가 정답**
- **응답 필드명을 추측했다** (2026-08-17) — `updated_since_req`·`srs_counts`·`advanced_count`
  전부 오답(실제 `updated_since_requested`·`sr_block_status_counts`·`advanced_docs`).
  **`jq 'keys'` 로 먼저 확인할 것** — 위 「파라미터 이름 추측」과 같은 계열

---

## 3. 이벤트 8종 — 어디서 무엇을 읽나

| 사건 | 출처 | 부호 | 날짜 |
|---|---|---|---|
| 판매 출고 | `sale` → `Fulfilments[].Pick.Lines` | − | `Ship.Lines[].ShipmentDate` |
| 반품 입고 | `sale` → `CreditNotes[].Restock` | + | `CreditNoteDate` |
| 발주 입고 | Advanced → **`PutAway[].Lines`** / Simple → `StockReceived.Lines` (08-18) | + | **`Lines[].Date`** |
| 이동 출발 | `stockTransfer` → `Lines[].TransferQuantity` | − | `DepartureDate` |
| 이동 도착 | 같은 문서 | + | `CompletionDate` |
| 조정 기존 | `stockadjustment` → `ExistingStockLines` | `Adjustment − QuantityOnHand` | `EffectiveDate` |
| 조정 신규 | `stockadjustment` → `NewStockLines` | `+Quantity` | `EffectiveDate` |
| 조립 | `finishedGoods` → `PickLines`(−) + 헤더(+) | 양방향 | 오더 생성 시점 |

**원가만 바뀌는 6종**(`* Cost Change`)은 `Quantity=0` — 수량 원장에서 무시.

### 문서별 함정

- **발주 (2026-08-18 재설계 확정 — `@2026-08-18.1` 반영)**: 축은 목록 `Type` 으로 가른다 —
  **Advanced = `PutAway`**(bin 있음·확정 반영) / **Simple = `StockReceived`**(객체 하나 · bin 있음
  — PO-00874). SR 을 쓰면 안 되는 이유 둘: ① SR 라인의 `LocationID` 는 null 이거나 **창고
  GUID** 라 bin 이 구조적으로 없다 ② SR `Status` 는 stock receiving 단계의 **워크플로 상태**지
  재고 반영 여부가 아니다(PO-00703 SR=DRAFT/PA=AUTHORISED 62줄 `FULLY RECEIVED` · PO-01131
  SR=NOT AVAILABLE/PA=AUTHORISED 3,570u · PO-01128 SR=""/PA=AUTHORISED 84줄). SR·PA 는 같은
  입고의 두 표현(15건 srLines==paLines) — **둘 다 읽으면 정확히 두 배**.
  블록 화이트리스트: **통과는 두 축 모두 AUTHORISED 만** + 미지값 경고(~~빈 문자열 통과~~ 는
  근거 소멸로 삭제). **PA 축의 알려진 어휘 = `AUTHORISED`·`VOIDED`·`DRAFT`**(08-18 · Convert
  직후 PA 는 DRAFT 로 생성 — PO-01117) — ⚠️ 어휘와 통과 기준은 다르다: DRAFT 는 경고 없이
  건너뛰는 정상 상태일 뿐 기표되지 않는다. 목록 `StockReceivedStatus` 게이트 없음(위 함정 표).
  Advanced 인데 PA 없음 = 행 미기표 + 보고, 커서는 안 멈춘다(재등장 전제 미확인 — 정본 4부
  체크리스트).
  ⚠️ `Type` 은 가변이지만 **Convert 는 사람이 누르는 명시적 동작 — 시간 아님(PO-01117 31분 무변)**.
  ~~"Apply 후 ~10분 자동 전환(12/12)"~~ 은 Convert 가 보통 빨리 눌렸던 것의 오인.
  `simple_docs: 0` 도 `> 0` 도 정상이고, 전환이 `LastUpdatedDate` 를 올려 **모든 PO 가
  UpdatedSince 에 최소 두 번 잡힌다**. ~~"최근 40건 전부 Advanced — Simple 분기 미실행"(08-17)~~ 은 닫혔다:
  목록 게이트 제거 후 `simple_docs: 7` 실행·정상 동작(SR NOT AVAILABLE 올바르게 배제).
  [실측 08-18 dry 전/후] rows 383→643(+68%) · UNMAPPED 소멸 · bin 실제 선반으로
- **발주 날짜**: `OrderDate`·`InvoiceDate`·`LastUpdatedDate` 전부 어긋남. 우연히 맞는 경우가 있어
  **한 건만 보고 판단 금지**
- **반품**: `RestockStatus='AUTHORISED'` 일 때만 재고 복귀. `DRAFT` 는 금액만.
  한 오더에 크레딧 노트가 **여러 개** 붙을 수 있음.
  ⚠️ 정정(08-17): **AUTHORISED 인데 `Restock[]` 빈 배열 실재** — 판정은 배열 길이로.
  목록 행은 **sale 단위** — 목록에서 `RestockStatus` 로 거르지 말 것(같은 오더의 승인 CN 유실).
  원장 doc_number = **CreditNoteNumber**(오더번호면 다중 CN 이 유니크 키를 깬다)
- **이동**: 한 문서가 원장 4행(출발창고− / IN_TRANSIT+ / IN_TRANSIT− / 도착창고+).
  미완료면 출발만. **97%가 같은 창고 안 자리 이동** — 창고 단위로는 ±0이지만 **두 줄 다 기록**.
  ⚠️ **빈 이동의 `DepartureDate` 결손은 구조적이다**(Cin7 WMS 모바일 빈 이동이 만든다 —
  실측 15건 · 우리 WMS 에 빈 이동 기능이 없어 **계속 발생**). 대체 규칙: **같은 창고 →
  `LastModifiedOn` 으로 대체 + raw 에 대체 사실 기록**(창고 잔고 ±0 이라 무영향) /
  **다른 창고 → hold**(잔고가 움직이는데 시점 불명 = 진짜 이상)
- **조립**: 오더 생성 시점에 실제로 재고가 움직인다. 출고는 배송 때 — 그 사이 번들이 재고로 존재(0~15일).
  물리적 이동이 아니라 **재분류**라 실사 때 장부와 선반이 달라 보임.
  ⚠️ 조립 없이 팔리는 경우도 있다(조정으로 재고를 잡아둔 것 — 3건 확인).
  ⚠️ 필드 실측(2026-08-17): `sku` 출처는 **`ProductCode`**(PickLines·헤더 둘 다 — SKU 필드가
  없다) · `doc_number` = **`AssemblyNumber`**(목록 배열 키는 **`FinishedGoods`**) ·
  날짜 = `CompletionDate`(FG-00110 = 2026-08-06 — `Date`/`CompletionDate`/`WIPDate` 세 값 동일 ·
  재고 이동일과 일치) · `Status='COMPLETED'` 만(120건 중 VOIDED 77)

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

**전량 셋의 커서 하한(`?from_cursor=` — 2026-08-17)**: 저장된 커서가 없을 때의 시야 하한 —
그 번호 이하 문서는 후보에서 아예 제외(스냅샷에 녹아 있어 볼 이유가 없다).
⚠️ 근거 사고: `DepartureDate` 없는 2025-11 초기 트랜스퍼 **TR-00012~76 40건이
hold_missing_date 로 상세 캡 40을 정확히 소진**해 뒤 ~3,000건을 한 건도 못 봤다.
**`since` 로는 못 푼다 — 커서 정지가 필터보다 먼저다.** ⚠️ 하한은 "옛 데이터를 안 보는 것"이지
**이상 감지를 끄는 것이 아니다** — 하한 이후의 날짜 결손·DRAFT 는 여전히 커서를 막는다.

**증분 셋의 날짜 커서 규칙 (2026-08-17 구현 확정)**: `UpdatedSince = last_cursor − 1일`
(겹침 수신 — 중복은 유니크 키 흡수) · 문서 상태로 커서 안 멈춤(갱신되면 재등장) ·
⚠️ **캡 회차만 커서 = 마지막 처리 문서의 Updated**(오름차순 처리 전제 — 회차 시작 시각으로
옮기면 캡 밖 후보가 영영 유실. 판매는 캡 초과가 일상) · ⚠️ 커서는 시각 전체 정밀도로 저장하고
**거르기도 우리 쪽 전체 정밀도로**(날짜 절단이 "매 회차 같은 40건 반복·삽입 0행·정상 응답"의
완전히 조용한 정체를 만든다 — dry 로는 재현 불가) · ⚠️ **`since=<스냅샷 날짜>`(이벤트 필터)는
쓰기 켤 때 필수** — 갱신 축과 이벤트 날짜가 분리라 과거 이벤트가 스냅샷과 이중 계상된다.

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
- `line_ref` = **`ProductID`** (WMS 의 `cin7_po_line_id` 선례) — ⚠️⚠️ ~~판매만 예외~~ →
  **예외 둘(08-18): 판매·발주.** 규칙의 정본은 설계 문서 2부 「중복 방지」 소스별 표
  ("소스마다 가장 안정적인 라인 식별자" — 통일보다 정확성 우선). **판매 예외:
  `<fulfilment TaskID>:<ProductID>`** (2026-08-17 · 의도적 이탈). 유니크 키에 **occurred_on 이
  없어서**, 분할 출하(같은 SKU·같은 bin·날짜만 다름)의 두 행이 키가 완전히 같아져 두 번째
  출고가 조용히 사라진다. **"스킬대로 ProductID 로 되돌리자"는 제안이 나오면 이 줄이 근거다 —
  되돌리면 분할 출하가 뭉개진다.** fulfilment 식별자는 TaskID(GUID — 재수집에도 안정 · 배열
  인덱스 금지). [실측] TaskID 폴백 발동 0회. ~~발주의 진짜 라인 식별자 CardID 는 raw 원문에만~~
  → 08-18 부터 발주의 line_ref 자체가 CardID 다(아래).
  ⚠️ **발주는 `CardID` 로 확정(2026-08-18 · `@2026-08-18.1`)** — 같은 SKU 가 여러 빈으로 쪼개지고
  같은 빈·같은 SKU 가 날짜만 달리 두 줄인 사례 실측(PO-00944 KUZ77036). `ProductID` 는 유일성
  94/97 · 109/110 으로 부족, `CardID` 는 97/97 · 110/110. [실측] `.7` dry `merged_lines: 5`
  (가설이던 뭉개짐이 실재) → `.1` 에서 **0**. ✅ CardID 의 재수집 안정성은 **닫힘(08-18 저녁
  PO-01117)** — Convert(SR→PA)를 통과해도 51줄 전부 CardID·LocationID·순서 유지, 재생성 아님
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
