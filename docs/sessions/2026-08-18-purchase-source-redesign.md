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

> ⚠️ **이 목록은 2026-08-18 시점 기록이다.** 이후 1(CardID)·3(재등장)은 닫혔고 2는 관찰 대기로
> 하향, 4(PA 어휘)는 `DRAFT` 추가로 반영됐다 — **현황은 정본 4부 체크리스트**
> (경위: `docs/sessions/2026-08-19-po01117-followup.md` §5).

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

---

## 8. 저녁 — PO-01117 실시간 관찰

WMS Apply → Cin7 `Convert`(Simple→Advanced) → 승인까지의 전 과정을 GAS 스냅샷으로 관찰했다
(15:39 Apply 전 / 15:41 Apply 직후 / 16:12 +30분 / 16:52 Convert 직후 / 16:59 승인 후).
코드 반영: `inv-collect@2026-08-18.2`(PA 어휘에 `DRAFT` 추가 — 경고 오탐 제거).

| 시점 | Type | SR | PA |
|---|---|---|---|
| Apply 전 | Simple | `[NOT AVAILABLE]` 0줄 | 없음 |
| Apply 직후 | Simple | `[DRAFT]` **51줄** (bin 전부 있음) | 없음 |
| +30분 | Simple | 변화 없음 (`LastUpdated` 도 동일) | 없음 |
| Convert 직후 | **Advanced** | `[""]` **0줄** | `[DRAFT]` **51줄** |
| 승인 후 | Advanced | `[""]` 0줄 | `[DRAFT]` (변화 없음) |

**`CardID` 51개가 전 구간에서 완전히 동일**했다(순서·`LocationID` 까지).

### 8-1. A1 판정 = 닫힘 (§5 의 1번)

`CardID` 는 Convert 를 통과해도 유지된다 — 51줄 전부 Apply 직후(SR) → Convert 후(PA) →
승인 후까지 동일. **Convert 는 재생성이 아니라 이동**이므로 이중 계상 위험은 없다.
정본 4부 체크리스트 1번 ☑. (남는 미확인은 수량 **수정** 시의 거동 — 4부 3번과 같은 축.)

### 8-2. Convert 의 구조

- **라인을 재생성하지 않고 SR → PA 로 옮긴다.** Convert 직후 SR 블록은 빈 상태(`""`)·0줄
  껍데기로 남고, PA 블록에 51줄이 그대로 들어간다(`TaskID` 양쪽 동일).
- 📌 PO-01128 의 `SR=[""]` 패턴의 정체가 이것이다 — **Convert 를 거친 문서의 정상 흔적.**
- **PA 블록은 `DRAFT` 로 생성된 뒤 승인된다** — 진행 중 상태가 존재한다. §5 의 4번(PA 어휘)이
  옳았다: 40건 표본 {AUTHORISED, VOIDED} 은 완료 문서뿐이라 진행 중 상태를 못 봤다.
- `Type` 전환은 **자동이 아니다** — Apply 후 31분 무변(`LastUpdatedDate` 도 불변),
  사람이 `Convert` 를 누르는 즉시 전환. "Apply 후 ~10분 자동(12/12)" 은 오인이었다.

### 8-3. Simple 완전일치 제약과 `auto-authorize` 경고의 재해석

Simple 발주는 **인보이스 수량 = 입고 수량 완전 일치**를 요구한다(불일치 시 승인 400:
`"quantity received should exactly match the quantity invoiced"` — **UI 도 같은 에러**라 수동
승인으로 우회 불가). 해소 경로는 `Convert` 뿐 — Advanced 는 태스크가 독립이라 192/168 이
공존하고, Convert 하나로 승인까지 완결된다(별도 Authorize 불필요).
⇒ **WMS `apply_note` 의 `WARN auto-authorize failed` 는 사고가 아니라 Simple 구조상 예정된
거부다**(미달 입고는 클램프로도 못 맞춘다 — 없는 물건을 있다고 쓸 수 없다).
2026-07-24 이후 10건 전부 이 계열·전부 정상 처리(9건 `PA=AUTHORISED`). 별건 과제 = 경고 문구
개선·화면 표시(진짜 실패와 구별이 안 된다).

### 8-4. 미확정 2건 (정본 4부 「신규 미확정」에 등록) — ✅ **둘 다 2026-08-19 닫힘**

> 결과: `docs/sessions/2026-08-19-po01117-followup.md` §1-1(지연 확정) · §2(미달 24개 =
> PO 채움 + `ST-01220` adjustment). 정본 4부 「신규 미확정」 절에도 닫힘 표시.

1. **화면 `Authorized` vs API `PA.Status=DRAFT` 불일치** — 화면엔 뱃지가 붙었는데 API 는
   DRAFT·`LastUpdatedDate` 불변. 지연인지 별도 승인 단계인지 미확인 — 원장은 AUTHORISED 만
   기표하므로 결국 기표되는지 다음 날 재조회 필요.
2. **미달 입고분 24개의 행방** — 인보이스 192/입고 168, Convert 후 화면에
   `Add stock receiving 24` 잔존. 추가 입고/크레딧노트/방치에 따라 원장에 추가 이벤트 가능.

### 8-5. ⚠️ 방법론 기록 — 같은 날 같은 함정을 두 번 밟았다

이 관찰 과정에서 Claude 의 진단이 네 번 틀렸다:
① 승인 상태를 SR 축으로 판정(PA 를 봐야 했다) ② UI 수동 승인 권유(UI 도 거부한다)
③ Activity log 의 계정명만 보고 실무 흐름을 추정 ④ 불필요한 Authorize 클릭 안내.
**원인은 하나 — 원장은 실측을 쌓아 왔는데 리시빙은 화면 몇 장으로 판단했다.**
같은 날 원장에서 얻은 교훈(「Cin7 발주는 축이 여러 개고 한 축만 보면 반대 결론이 난다」)을
같은 세션의 리시빙 문제에 적용하지 못했다.
📌 **도메인이 달라도 데이터 소스가 같으면 함정도 같다.**

---

## 9. 밤 — Cin7 API 한도 실측

`/ref/location?Page=1&Limit=1` 무간격 연타 + 회복 측정 + 키 범위 판정으로 전부 확정.

| 항목 | 실측값 | 근거 |
|---|---|---|
| **한도** | **60콜 / 60초** | 429 본문 명문: `You have reached 60 calls per 60 seconds API limit.` |
| **범위** | **애플리케이션 키 단위** | GAS 키 `remaining=0`(429)인 그 순간 WMS 키로 HTTP 200. ⚠️ **두 키의 `AccountID` 는 동일** — 계정이 같아도 한도는 독립 |
| **회복** | **31초** | 429 후 5초 간격 재시도, 6회째(+31s) 200 |
| 429 응답 헤더 | `x-ratelimit-limit: 60` · `x-ratelimit-remaining: 0` · `x-ratelimit-reset: 60` · `Retry-After: 60 Seconds` | 실측 덤프 |
| ⚠️ **200 응답 헤더** | **`ratelimit` 계열이 전혀 없다** | 200 헤더 전문 덤프 — `Cache-Control`·`Content-Type`·`Set-Cookie`·`Date` 등만 |
| 차단 지점 | 53콜째(18초) / 61콜째 | 앞선 호출이 같은 60초 창에 남아 있으면 더 빨리 걸린다 |

### 9-1. 측정 방법

GAS `ppa_rateLimitProbe`(무간격 연타로 429 유도 + 5초 간격 회복 측정) →
`ppa_keyScopeProbe`(GAS 키 429 시점에 WMS 키 동시 호출로 키/계정 범위 판정) →
200 응답 헤더 전문 덤프. ⚠️ **프로브 코드는 `docs/probes/` 에 없다** — 필요하면 재작성해야 한다.

### 9-2. ⑤ 설계에 반영될 것 4가지

1. **간격 1,200ms** (분당 50콜 — 계산식: 간격 ms = 60,000 / 목표 분당 콜수. 현행 700ms 는
   분당 85.7콜로 한도의 1.43배 초과 확정)
2. **캡의 근거 확립** — 200 응답에 ratelimit 헤더가 없어 사전 제어가 불가능하므로
   **회차당 호출 수를 미리 묶는 `MAX_DETAIL_PER_SOURCE` 가 유일한 예방책**이다.
   `1,200ms × 40 = 48초 < 60초 창`. 캡을 올리려면 간격도 함께 봐야 한다(55 × 1.2s = 66초 초과)
3. **`Retry-After` 백오프** — 현행 1.5s→3s(최대 4.5초)는 실측 회복 31초의 1/7 로 사실상
   재시도가 아니다. 헤더 값을 읽어 그만큼 대기(없으면 60초 가정). 회복이 31초여도
   표기값 60초를 신뢰하는 쪽이 안전(31초는 단발 관측)
4. **키 공유 확인** — WMS 키를 `hello`(5분 폴링)·`receiving`·`inv-collect` 가 함께 쓰는지
   코드 확인 필요. 공유라면 pg_cron 시각을 폴링과 어긋나게 잡거나 `inv-collect` 전용 키 발급
   (⚠️ Cin7 약관 허용 여부 미확인)

⚠️ **이 절의 결정은 아직 문서뿐이다 — 코드(`_shared/cin7.ts` 의 백오프 상수 ·
`inv-collect` 의 `DETAIL_SLEEP_MS=700`)는 옛 값 그대로다.** 수정은 ⑤ 작업 항목.
그때까지 문서와 코드가 다른 상태임을 알고 볼 것.

### 9-3. ⚠️ 정정 기록

측정 도중 Claude 가 「200 응답의 `x-ratelimit-remaining` 을 읽어 사전 제어 가능」이라고 했으나
**틀렸다** — 그 헤더는 429 응답에만 온다. 429 를 한 번 본 것만으로 "매 응답에 온다"고
일반화한 오류다. 📌 **표본 하나로 규칙 만들기의 또 다른 사례.**

---

## 다음 세션에서 먼저 할 것 (2026-08-19 아침)

> ✅ **결과 보고는 `docs/sessions/2026-08-19-po01117-followup.md`** — 1·3 닫힘 · 2 는 "판정 불가"로
> 확인(결과물로만 판정 — 별건) · 4·5 미착수(그 문서 「다음에 할 것」으로 이월).

1. **`putaway:DRAFT` 가 해소되는가** — `dry=1&only=purchase&from_since=2026-08-18` 재실행.
   PO-01117 이 `AUTHORISED` 로 넘어가 `ledger_rows` 가 늘면 §8 의 「화면 Authorized vs API DRAFT」는
   **반영 지연**으로 확정된다. 여전히 `DRAFT` 면 PA 승인이 별도 단계라는 뜻이므로 조사 필요.
2. **`cron.job` 4·5 실행 확인** — 08:30·09:30(토론토). 시크릿 교체 후 첫 실행이라
   401 이면 헤더 갱신이 안 된 것(4부 참조).
3. **미달 24개의 행방** — PO-01117 `Add stock receiving 24`(CAN01620 인보이스 192 / 입고 168).
   추가 입고 / 크레딧노트 / 방치 중 어느 쪽인지에 따라 원장에 이벤트가 더 생긴다.
4. **분할 인보이스 비율 조사** — Advanced 기본값 판정(4부 「검토 중」 절).
5. **리시빙 라인별 작업자 검증** — 2026-08-17 배포분, 신규 리시빙부터만 기록.
   ⚠️ PO-01113 은 화면에 안 나오는 것이 정상(컬럼 도입 전 라인).

⚠️ **⑤(쓰기) 진입 게이트 현황 (2026-08-18 시점 — ⚠️ 낡음. 현황은 정본 4부 · 2026-08-19 에
☑3 닫힘 · 👁2 하향 · ⬜6 신설)**:
☑ 1 CardID 안정성(닫힘) · ⬜ 2 adv_no_putaway 실행 · ⬜ 3 재등장 전제 ·
⬜ 4 ON CONFLICT 정책(실무 빈도 3문항 Caleb 답변 대기) · ⬜ 5 캡·페이싱(수치 확보, 코드 반영 미완)
