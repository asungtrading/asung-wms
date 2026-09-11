# Reference Book (`/ref/*`) 엔드포인트 — 마스터 여섯 전량 실측 (2026-09-11 GAS 프로브 3회)

IMS PO 모듈 ① Settings(`ref_brand`·`ref_category`·`ref_unit`·`ref_payment_term`·`ref_account`·`ref_currency`·
`ref_warehouse`·`ref_bin`)의 설계 근거로 쓰인 실측. 설계 판단은 `docs/design/po-module.md`, 스킬은 `asung-po`.
전체 `/ref/*` 인덱스(apib 라인 번호)는 `endpoint-index.md`.

## 여섯 개 요약

| 엔드포인트 | 배열 키 | Total | 필드 |
|---|---|---|---|
| `GET /ref/brand` | `BrandList` | 415 | `ID`(guid) · `Name` — 둘뿐 · 이름 중복 0 |
| `GET /ref/category` | `CategoryList` | 19 | `ID` · `Name` — 둘뿐 · 전부 서로 다름 · ⚠️ 제품 아닌 것 섞임(Liability·Service·Unclassified·Other) |
| `GET /ref/unit` | `UnitList` | 44 | `ID` · `Name` — 둘뿐 · ⚠️ 39개가 숫자 이름(2·12·1200·960…) · 글자는 DP·EA·EA-ALT-UPC·Item·JAR 다섯 |
| `GET /ref/paymentterm` | `PaymentTermList` | 34 | `ID`·`Name`·`Duration`·`Method`·`IsActive`·`IsDefault` |
| `GET /ref/account` | ⚠️ **`AccountsList`** | 289 | 열둘(아래) |
| `GET /ref/location` | `LocationList` | 2,678 | 열일곱(아래) |

⚠️ **`ref/account` 의 배열 키만 복수형 `AccountsList` 다** — 나머지는 전부 단수형(`BrandList`·`UnitList`…). 추측하면 틀린다.

⚠️⚠️ **통화 목록 엔드포인트가 없다** — `ref/` 계열 열일곱 개 전수 확인(`endpoint-index.md`). 환율은 문서마다
`CurrencyRate` 로만 온다(⚠️ Simple Purchase 의 `Invoice.CurrencyRate` 는 null — 상위 `CurrencyRate` 를 쓴다).
⇒ 통화는 IMS 가 스스로 세운 첫 마스터다(`ref_currency` · `cin7_id` 없음).

## ⭐⭐ Cin7 은 마스터를 GUID 가 아니라 이름 문자열로 참조한다

```
제품 30행     Brand·Category·UOM 이 ref/ 목록의 Name 과 일치 100% · GUID꼴 0건
공급처 226곳  PaymentTerm 이 ref/paymentterm 의 Name 과 226/226 일치
              AccountPayable 이 ref/account 의 Code 와 226/226 일치 (Name 일치 0)
```
⇒ 긁어올 때 연결 고리는 **이름(계정만 `Code`)** 이다.
⚠️ 문자열이 흔들리면 연결도 흔들린다 — `Net 30`(33곳) / `Net30`(21곳)이 별개 행으로 존재하고 공급처가 양쪽에 나뉘어 있다.

## `ref/paymentterm` — ⚠️⚠️ `Duration` 은 최종 기일이 아니다

```
2%10 Net30   뜻: 기일 30일 · 단 10일 안에 내면 2% 할인 (회계 관용 표기)
             Cin7 Duration = 10     ← ⚠️ 할인 기한 쪽을 담았다
```
⇒ **그대로 기일 계산에 쓰면 20일이 당겨진다.** 아직 기한이 남은 건이 연체로 잡힌다.

- `Method` 34개 전부 `number of days` · `IsActive` true 17/34 · `IsDefault` 는 `C.B.S (Cash Before Shipment)` 하나.
- 활성 17 (Name(Duration)): 1% Warehouse Allowance + 2%10 Net30(10) · 1%30 Net31(30) · 2%10 Net30(10) · 2%19 Net30(19) ·
  2%30 Net31(30) · 2.1%13 Net30(13) · 50% COD & 50% N30(30) · C.B.S (Cash Before Shipment)(0) · C.O.D(0) · Due on receipt(0) ·
  Net 14(14) · Net 15(15) · Net 21(21) · Net 30(30) · Net 45(45) · Net 60(60) · Net 7(7)
- 공급처 226곳이 실제로 쓰는 14종: Due on receipt 92 · C.B.S 59 · Net 30 33 · Net30 21 · C.O.D 4 · Net 60 3 · 1%30 Net31 3 ·
  2%10 Net30 2 · Net45 2 · Net 45 2 · 2%19 Net30 2 · 2%30 Net31 1 · Net 15 1 · 1%20 Net30 1
  ⚠️ `Net30`·`Net45`·`1%20 Net30` 은 **비활성인데 24곳이 여전히 쓴다.**

## `ref/account` — 289

```
필드   Code · Name · Class · Type · Status · DisplayName · Description · ForPayments ·
       BankAccountId · BankAccountNumber · SystemAccount · SystemAccountCode
Class  EXPENSE 126 · ASSET 74 · LIABILITY 52 · REVENUE 26 · EQUITY 11   (다섯 · 전수)
Status ACTIVE 213 · ARCHIVED 76
Type   16종 — EXPENSE 109 · CURRLIAB 40 · BANK 20 · FIXED 19 · OTHERCURRENTASSET 16 · COSTOFGOODSSOLD 14 · CURRENT 13 ·
       INCOME 11 · EQUITY 11 · OTHERINCOME 7 · CREDITCARD 7 · OTHERASSET 6 · REVENUE 5 · LONGTERMLIABILITY 5 · DIRECTCOSTS 3 · SALES 3
ForPayments  true 23 · false 266
DisplayName  「_188_: Accounting」 — Code + Name 화면용
SystemAccount 271/289 null (CREDITORS·DEBTORS… Cin7 내부 표시)
Code   ⭐ 중복 0 (289 전수) — 자연키로 쓸 수 있다
```
⚠️⚠️ **`Code` 형식이 둘이다** — `_숫자_` 215개 / **밑줄 없는 순수 숫자 74개**(`2000`·`1200`·`6000`·`8100`…).
⇒ 형식 CHECK 를 걸면 74개가 걸린다.

⭐ **우리가 코드에 박아 쓰는 계정 여섯 — 실재 확인 · 이름까지 (전부 ACTIVE)**
```
_59_          Inventory Asset             [ASSET]
_135_         Brokerage - COS             [EXPENSE]   ⚠️ 우리 문서의 "landed" 가 이것
_136_         Freight - COS               [EXPENSE]
_95_          Purchase Non Stock - COS    [EXPENSE]
_1150040012_  Stock in Transit (GINR)     [ASSET]
_1150040007_  In Transit                  [ASSET]
```
📌 `_135_` 의 실제 이름은 **Brokerage(통관중개료)** 다 — 우리는 "landed" 라 불러왔다. 같은 것을 가리키지만 이름이 다르다는 것을 알고 있어야 한다.
(SKILL.md 「ManualJournals」 절의 「⬜ `_135_`·`_136_` 계정명 미확인」은 이것으로 닫힌다.)

## `ref/location` — 2,678 (⚠️ 2026-09-11 정정 포함)

```
ParentID 없음(= 창고)   3
ParentID 있음(= bin)  2,675   토론토 2,047 · 에드먼튼 628
```

| Name | ID | 주소 | PickZones | Bins[] | 비고 |
|---|---|---|---|---|---|
| `Asung Trading Inc.` | `f1ca3946-5a4e-4da7-b68a-ce7d3500f0be` | North York ON M9N 2V8 · 35 Suntract Road | `Zone1,…,Zone5` | 2,047 | `IsDefault=true` |
| `Asung - Edmonton` | `623edcaa-5f18-4682-aae1-b9016d977c11` | Edmonton AB T5S 0N7 · 18418 105 NW Ave. | `Zone1,…,Zone5` | 628 | |
| `Production Facility` | `6160ca1b-c932-4b58-bf04-96fbb0bf5179` | **전부 null** | null | **0** | `IsShopFloor=true` · 미사용 |

```
필드 17개  AddressCitySuburb · AddressCountry · AddressLine1 · AddressLine2 · AddressStateProvince · AddressZipPostCode ·
           Bins · FixedAssetsLocation · ID · IsCoMan · IsDefault · IsDeprecated · IsShopFloor · IsStaging · Name · ParentID · PickZones
Bins[] 원소  {ID, Name, IsDeprecated, IsStaging}  — 그 ID = 하위 행의 ID (같은 bin GUID)
```

### ⭐⭐ 정정 — 하위 행 `Name` 은 bin 이름이다

~~「child-location 행의 `Name` 은 bin 이름이 아니다(바코드류)」~~ (2026-07-28 기록 · `SKILL.md` 6번 · `stock-write.md` 5절)
→ ⚠️⚠️ **[정정 2026-09-11] 전량 실측으로 틀렸다:**
```
창고 Bins[] 합계              2,675 (중복 제거 2,675)
하위 행 Name 이 Bins[] 에 있음  2,675
없음                              0
하위 Name 숫자만                  0   ·   글자 포함 2,675   ·   20자 이상 0
```
⇒ **bin 이름은 하위 행 `Name` 에서 그대로 얻는다. 바코드는 섞여 있지 않다.** 어느 쪽(`Bins[]` · 하위 행)에서 얻어도 같은 GUID 다.
⚠️ 원래 기록이 왜 나왔는지는 **모른다(구간·기준 불명)** — 추측으로 이유를 지어내지 않는다. `Limit 500` 잘림 때문에
하위 행 폴백이 죽은 경로였던 사실은 그대로이므로, **쓰기용 bin GUID 조회는 여전히 창고 행 `Bins[]`** 로 한다.

### 그 밖 실측
```
PickZones 채워진 하위 행    0      ⚠️ bin 별 zone 은 Cin7 에 없다 (창고 행에만 문자열 하나)
IsDeprecated 하위 행        0      비활성 bin 은 아직 없다
⚠️ 창고 행의 주소 칸은 값이 있고, bin 행은 전부 빈 문자열('')이다 — null 이 아니다
```

## 관련 실측(같은 날 · 다른 파일)

- `supplier` 226 전량 → `supplier.md` 「2026-09-11 전량 실측」
- `product` 14,677 · 30행 표본 → `product-master.md` 「2026-09-11 표본 실측」
