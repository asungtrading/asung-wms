# 2026-08-18 — 발주 소스 재설계 (PutAway 축) 구현·검증

선행 문서: `docs/sessions/2026-08-18-purchase-putaway-axis.md`(축이 틀렸다는 실측 — 이 문서의 §0).
이 문서는 그 재설계의 **구현·배포·검증 기록**이다. 코드 커밋 `76ee3bc` · `inv-collect@2026-08-18.1`.
정본 반영: `docs/design/ledger-design.md` 1부 발주 절·2부 line_ref 표·4부 체크리스트 /
`asung-inv-ledger` 스킬 / `cin7-api` 스킬 3·11·13번 + `references/purchase.md`.

---

## 1. 결론

| 항목 | .7 (2026-08-17) | .1 (2026-08-18) |
|---|---|---|
| 축 | 전부 `StockReceived` | **Advanced = `PutAway`** / Simple = `StockReceived` (목록 `Type` 으로) |
| 목록 게이트 | `StockReceivedStatus` 없음/NOT AVAILABLE 제외 | **제거** — 분포만 센다(`srsCounts`·`crsCounts` 관측 전용) |
| 블록 화이트리스트 | SR 기준 `AUTHORISED`·`""` | **두 축 모두 `AUTHORISED` 만** + 미지값 경고(빈 문자열 예외 소멸 — PO-01128 은 빈 상태가 SR 블록) |
| `line_ref` | `ProductID`(소스 간 통일) | **`CardID`** — 통일보다 정확성 우선 |
| PA 없음(Advanced) | — | 행 미기표 + `adv_no_putaway*` 보고 · **커서 안 멈춤** |

⚠️ 어제(f33260f)의 「−90행 = 유령 재고 차단」 판정은 **무효** — SR 상태는 워크플로 중간 상태라
실재 입고를 지운 것이었다. 📌 화이트리스트 **방향 자체는 옳았다**. 틀린 것은 **어느 배열의
상태를 보느냐**였다(방향까지 뒤집으면 블랙리스트로 되돌아간다).

---

## 2. 프로브 실측 (GAS `PurchasePutawayProbe.gs`)

- **목록 게이트 탈락 문서 판정** — 탈락 표본 6건 중 **Advanced 4건(PO-00848·00931·01048·01065)이
  전부 실재 입고**(합 12,552u). 목록 `StockReceivedStatus` 와 상세 블록 `Status` 는 **양방향으로
  어긋난다**(PO-01131 목록 AUTHORISED/상세 NOT AVAILABLE ↔ PO-00848 목록 NOT AVAILABLE/상세
  AUTHORISED) = 상관이 없다.
- **PA 블록/라인 필드명 덤프** — 블록: `TaskID` · `InvoicingAndReceivingNumber` · `Status` ·
  `Lines`. 라인: `Date` · `Quantity` · `ProductID` · `SKU` · `Name` · `Location` · `LocationID` ·
  `Received` · `BatchSN` · `SupplierSKU` · `ExpiryDate` · `CardID` · 상품 치수/커스텀필드.
  ⚠️ `NonInventory` 는 **SR 라인에만** 있다.
- **PO-01128 판정** — 어제 "빈 문자열 통과"의 근거였던 그 PO 는 **Advanced** 였고 빈 상태는
  **SR 블록**이었다. PA 는 AUTHORISED · 84줄 · bin 84/84. ⇒ PA 축에서 빈 문자열 예외는 근거 소멸.
- **SR 의 `LocationID`** — null 이거나 **bin 이 아니라 창고 GUID** 다. `.7` dry 의 `warehouse`
  에 `Asung Trading Inc.` 가 섞여 있던 것이 그 지문이었다(§7).

---

## 3. before/after dry 대조

**같은 창 `from_since=2026-08-17` (캡 없음 — 15건 전량)**

| 지표 | before(.7) | after(.1) |
|---|---|---|
| `candidates` | 13 | 15 |
| `ledger_rows` | 383 | **643 (+68%)** |
| `warehouse` | `UNMAPPED(no-id)` 단일 | `Asung Trading Inc.` |
| `bin` | `""` 단일 | `C040101`·`J01PALLET07` 등 실제 선반 |
| 블록 상태 | SR: AUTHORISED 6·""4·NOT AVAILABLE 2·DRAFT 1 | **PA: AUTHORISED 13 단일** |
| `merged_lines`·`card_id_fallback`·`adv_no_putaway` | — | 전부 0 |

**넓은 창 `from_since=2026-08-01` (후보 72 중 40 처리)**

```
putaway_block_status_counts = {AUTHORISED: 37, VOIDED: 1}
blocks_skipped              = {stock_received:NOT AVAILABLE 7, putaway:VOIDED 1}
warnings                    = []          (미지 어휘 없음)
simple_docs                 = 7           (← §4)
list_combined_receiving_status_counts
  = {FULLY RECEIVED 58, NOT RECEIVED 11, PARTIALLY RECEIVED 2, NOT AVAILABLE 1}
```

---

## 4. 뜻밖의 수확 — Simple 분기가 처음 실행됐고 정상 동작

어제까지 「최근 40건 전부 Advanced — Simple 분기 미실행」이었다. 그 원인은 코드가 아니라
**목록 게이트였다** — Simple 상태의 PO 는 대부분 `StockReceivedStatus` 가 서기 전이라 게이트에
걸려 상세까지 못 갔다. 게이트를 제거하자 `simple_docs: 7` 로 처음 돌았고, SR 블록
`NOT AVAILABLE` 을 화이트리스트가 올바르게 배제했다(`blocks_skipped` 의 `stock_received:NOT
AVAILABLE 7 이 그것). 📌 게이트 제거의 부수 효과가 미검증 분기 하나를 공짜로 닫았다.

---

## 5. 미검증 4건 (관찰 시점 — 정본은 `ledger-design.md` 4부 「commit=1 을 켜기 전에」 체크리스트)

내용은 체크리스트가 정본이다 — 여기는 목록과 시점만.

1. **CardID 재수집 안정성** — 다음 리시빙 Apply 직후와 30분 뒤(Type 전환 전후) 같은 PO 비교
2. **adv_no_putaway 경로** — 코드 실행 이력 0(Advanced 80건+ 에서 0건). 리시빙 진행 중
   (도착·미배치)에 dry 1회
3. **재등장 전제** — 2에서 잡힌 문서가 풋어웨이 후 다음 dry 에 재등장하는지
4. **PA 상태 어휘** — 관측은 `AUTHORISED`·`VOIDED` 뿐(40건 표본). ⚠️ 표본으로 어휘를 확정하지
   않는다 — 미지값 경고가 감시한다(NOT AVAILABLE 로 정확히 그렇게 틀린 것이 어제다)

---

## 6. 캡 실측 — 발주 후보는 평시 상시 캡

| `from_since` 창 | 후보 |
|---|---|
| 2026-08-01 | 72 |
| 2026-08-13 | 58 |
| 2026-08-17 | 15 |

캡 40 대비 **1.5~1.8배가 평시**다. 날짜 창을 좁혀도 안 줄어든다 — **`Type` 전환이
`LastUpdatedDate` 를 8월로 밀어올리기 때문**(모든 PO 가 전환 시점에 다시 잡힌다).
⇒ 캡·페이싱 결정(정본 4부)의 입력값. 이어받기(캡 회차 커서 = 마지막 처리 문서 Updated)가
있어 유실은 없지만, 발주 축은 **항상 여러 회차**를 전제해야 한다.

---

## 7. 방법론 교훈 — 요약이 아니라 실물 diff·데이터를 본다

이번에 그 덕에 잡은 것 둘:

- **`.7` dry 의 `merged_lines: 5`** — "ProductID 면 뭉개진다"가 가설이 아니라 **이미 실제로
  일어나고 있었다.** 요약 숫자(ledger_rows)만 봤으면 지나쳤다 — 진단 필드 하나가 설계 결정
  (line_ref=CardID)의 실증이 됐다.
- **`warehouse` 에 섞인 `Asung Trading Inc.`** — UNMAPPED 만 있을 줄 알았는데 실제 창고명이
  섞여 있었다 → SR 의 `LocationID` 가 "없다"가 아니라 **"bin 이 아니라 창고 GUID 다"** 라는
  발견으로 이어졌다. 결손의 모양이 원인을 말한다.

📌 같은 계열의 기존 교훈: "1페이지만 받고 판정 금지" · "응답 필드명 추측 금지(jq keys 먼저)" ·
"표본 하나로 규칙 만들지 않기" — 이번 것은 **"요약을 믿지 말고 행 실물을 볼 것"**.
