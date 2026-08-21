---
name: asung-warehousemap
description: >
  Asung Trading 창고 지도(WarehouseMap) 도구를 다룰 때 먼저 읽으세요.
  존→랙→베이→로케이션→제품 드릴다운 지도 + 실사(cycle count) 기록 도구.
  "WarehouseMap", "창고 지도", "warehousemap.html", "tools.asung.ca",
  "bins.json", "products.json", "Binstockdata", "bs_pushWarehouseJson_",
  "asung_bin_stock", "WarehouseMapSync", "WhmapStockReview", "QtyReview",
  "wrBuildQtyReview", "Corrections 시트", "WHMAP_PIN", "WHMAP_SHEET_ID",
  "WHMAP_SYNC_URL", "실사", "재고 정정", "위치 정정", "부분 실사",
  "딥링크", "?loc=", "🗺 Map 버튼", "존 레이아웃", "구조물" 등이 나오면
  추측하지 말고 이 스킬의 데이터 흐름·확정 사실·함정을 확인하세요.
  ⚠️지도 재고는 실시간이 아니라 매일 05:00 배치, ⚠️레이아웃과 내 수정은
  localStorage 라 공유 안 됨, ⚠️정정→Cin7 반영은 전 구간 수동,
  ⚠️Adjustment 는 절대값이라 부분 실사로 창고 합계를 조정하면 재고가 날아갑니다.
---

# Asung WarehouseMap 스킬

창고 지도 도구. **WMS 보다 먼저 만든 별개 시스템**이고, 지금은 WMS 화면에
🗺 Map 버튼으로 링크만 걸려 있다(직원 편의). 2026-08-20 기준 **WMS 통합 예정 · 미착수**.

관련 스킬: `asung-wms`(통합 대상) · `asung-bq-data-model`(`asung_bin_stock`) ·
`asung-apps-script`(GAS 컨벤션) · `asung-bq-apps`(Pages 도구 패턴) ·
`asung-inv-ledger`(⚠️ 자리 단위 재고가 겹친다 — 5절)

---

## 1. 전체 데이터 흐름 (2026-08-20 실측 확정)

```
[읽기 — 매일 1회 배치]
Cin7 ──API──▶ BQ Cin7_Master_Data.asung_bin_stock
                       │
        gas-system-automation / Binstockdata.js
        runBinStockSync  ← 트리거 매일 05:00
                       │
        bs_pushWarehouseJson_()
                       │  GitHub Contents API PUT (owner/repo/token = Script Props)
                       ▼
        asungtrading/tools : bins.json · products.json
                       │  .github/workflows/deploy.yml (on: push main)
                       ▼
        GitHub Pages → tools.asung.ca/warehousemap.html
                       │  fetch('bins.json?t='+Date.now())
                       ▼
                    화면

[쓰기 — 실사 기록]
화면 ──JSONP──▶ WarehouseMapSync.gs (standalone 웹앱)
                       ▼
        구글시트 "WarehouseMap Corrections" (PENDING)
                       ▼
        WhmapStockReview.gs (System_Automation) ← 사람이 수동 실행
                       ▼
        QtyReview 탭 → 담당자가 Cin7 에서 수동 Stock Adjustment
                       ▼
        wrMarkQtyApplied() ← 사람이 수동 → APPLIED
```

⚠️ **읽기와 쓰기가 서로 모른다.** 정정을 저장해도 `bins.json` 은 안 바뀌고,
지도는 다음 날 05:00 배치까지 계속 옛 값을 보여준다. **같은 정정이 반복 보고될 수 있다.**

⚠️ **Cin7 에 자동으로 쓰는 코드는 어디에도 없다.** 전 구간 사람 손이다.

---

## 2. 파일이 어디 있나

| 파일 | 레포/프로젝트 | 역할 |
|---|---|---|
| `warehousemap.html` | `asungtrading/tools` | 화면 전부(단일 HTML 1,157줄) |
| `bins.json` (~2.3MB) | 〃 | bin → `[{sku,name,stock,avail,cur,seen,note}]` |
| `products.json` (~2.2MB) | 〃 | sku → `{name,barcode,brand,supplier,image,is_new}` |
| `launcher.html` | 〃 | 도구 런처 — 지도 링크 |
| `Binstockdata.js` | `gas-system-automation` | BQ 조회 + 두 JSON 생성 + GitHub push |
| `WarehouseMapSync.gs` | **별도 standalone GAS** | 정정 기록 수신(JSONP) → 시트 |
| `WhmapStockReview.gs` | **System_Automation GAS** | 검토 리포트 + APPLIED 마킹 |

⚠️ `WarehouseMapSync.gs` 를 System_Automation 이나 CustomerPortal 에 넣으면
기존 `doGet`/`doPost` 와 충돌한다 — **반드시 standalone**(BarcodeLogger 와 같은 방식).

**진입 경로 9곳** — 전부 `https://tools.asung.ca/warehousemap.html`:
WMS `picker`·`packer`·`receiver`·`fulfillment`·`manager`·`admin`·`index` +
`tools/launcher.html`. ⚠️ 링크를 바꾸려면 **9곳 전부** 고쳐야 한다.

---

## 3. ⚠️ 반복해서 틀렸던 것

| 함정 | 진실 |
|---|---|
| 화면의 「**BQ 자동 로드** N 로케이션」= BQ 직결? | **아니다.** 같은 폴더의 **정적 `bins.json`** 을 fetch 할 뿐. 문구가 구조와 다르다 |
| 지도 재고가 실시간? | **아니다. 매일 05:00 배치 1회.** 낮에 움직인 재고는 다음 날 반영 |
| 로컬 클론의 커밋 날짜로 배치 생사를 판정? | ⚠️ **못 한다.** GAS 는 GitHub API 로 **원격에 직접 push** 한다. `git fetch` 없이 본 날짜는 근거가 아니다. [실사고 2026-08-20] 로컬 8/4 를 보고 「16일째 멈춤」이라 오진 — `git fetch` 하니 **당일 05:33 정상**이었다 |
| `bins.json` 은 현재 재고만? | **아니다.** `is_current=FALSE` 인 **과거 자리도 포함**한다(sticky 목적). 화면은 `cur:false`·`seen`(마지막 확인)으로 흐리게 표시 |
| 정정을 저장하면 지도가 갱신되나? | **아니다.** 되먹임 경로가 없다(1절) |
| 대소문자 다른 파일은 그냥 지우면 되나? | ⚠️ **먼저 diff.** [실사고] `WarehouseMap.html`(7/23)에만 딥링크가 있었고 실사용은 `warehousemap.html`(7/08) — **한 달간 기능이 조용히 죽어 있었다**(6절) |

### 조사 실패 패턴

- ⚠️ **`git fetch` 전 날짜로 결론** — 위 표. Claude Code 가 「로컬 기준이라 근거가 못 된다」고
  **명시 경고했는데도** 그 위에 원인 후보 4개까지 세웠다. **확인 전에 결론 금지**
- **페이지 fetch 로 JS 를 못 본다** — `tools.asung.ca` 를 web_fetch 하면 텍스트만 추출된다.
  상수·`fetch` 호출부는 **로컬 파일 또는 Claude Code** 로 봐야 한다

---

## 4. 화면 구조 (`warehousemap.html`)

### 상태가 3층이고 공유 범위가 다르다

| 층 | 변수 | 저장 | 공유 |
|---|---|---|---|
| 자동 데이터 | `AUTO` | `bins.json` | ✅ 전원 |
| 내 수정 | `OVER` | **localStorage** | ❌ 나만 |
| 존 위치·구조물 | `ZPOS`/`STRUCTS` | **localStorage** | ❌ 나만 |
| 제품 정보 | `PRODUCTS` | `products.json` | ✅ 전원 |

⚠️⚠️ **`OVER` 가 가장 위험하다** — 작업자가 지도에서 고친 게 자기 브라우저에만 남는다.
캐시를 지우면 사라지고 옆 사람은 다른 걸 본다. **개선 1순위.**

⚠️ **레이아웃 공유는 재배포 루프다** — 「🧭 레이아웃」에서 JSON 을 복사해
**HTML 에 기본값으로 하드코딩하고 커밋**해야 전원에게 반영된다. 개선 2순위.

### 알아둘 것

- `WAREHOUSES` 배열로 창고 탭. `defs` 가 비면 탭에 「· 준비중」이 붙는다
- `ALT_MAP` — Cin7 `BASE-EA-ALT-UPC` 별칭 → base SKU. 바코드 스캔 매핑용.
  ⚠️ ALT 는 재고·bin 이 없어 `bins.json` 엔 안 나온다 → `products.json` 에만 실린다
- 이미지: `products[sku].image` (소스 `Cin7_Sales_Data.asung_product_images` —
  **CustomerPortal 과 동일**). 없으면 `onerror` 로 숨김
- 인증: `WHMAP_PIN`(공용 1개) + 사용자 **이름 타이핑**(2자 이상이면 통과 — 검증 없음).
  둘 다 localStorage. ⚠️ `WHMAP_SYNC_URL` 이 HTML 에 그대로 박혀 있고 **페이지는 인증 없이 열린다**

### 딥링크 (2026-08-20 배포 · ⚠️ 실동작 미검증)

```
warehousemap.html?loc=A0101   → gotoLoc()  해당 로케이션으로 점프
warehousemap.html?q=SKU123    → runSearch() 검색 실행
```

`picker.html:1066` 이 `?loc=` 로 부른다. ⚠️ **주의점 둘**:
- `loadBinsJson`/`loadProductsJson` 은 실패를 `catch` 로 삼켜 **resolve 된다** →
  데이터가 안 왔는데 `gotoLoc()` 이 불릴 수 있다
- `setTimeout 80ms` 는 렌더 대기 임시방편. ⚠️ **2.3MB 를 창고 와이파이·태블릿에서
  받을 때 80ms 로 충분한지 미실측.** 안 되면 타이머가 아니라 데이터 도착 후 호출로 고칠 것

---

## 5. 실사(cycle count) 흐름

기록은 **3종** — `WarehouseMapSync.gs` 가 `Corrections` 시트에 append:

| type | 뜻 | status |
|---|---|---|
| `LOC` | 실제 **위치**가 시스템과 다름 | `PENDING` |
| `QTY` | 실제 **재고**가 시스템과 다름 | `PENDING` |
| `OK` | 실사했고 **일치함**(증거 기록) | `OK` |

같은 SKU 에 새 기록이 오면 이전 것을 `SUPERSEDED` 로 — **최신 하나만 유효**.
`wm_countedLocs_(since)` 가 실사한 로케이션 목록을 돌려줘 지도에 진행률을 칠한다.

### ⚠️⚠️ 부분 실사 — 이 시스템의 존재 이유

`wrBuildQtyReview()` 가 BQ 로 같은 창고의 **미카운트 bin** 과 그 OnHand 합을 붙인다.

⚠️ **한 SKU 가 여러 bin 에 있는데 한 곳만 세고 창고 합계를 조정하면 나머지가 날아간다.**
Cin7 `Adjustment` 는 증감분이 아니라 **조정 후 절대값**이기 때문이다
(`asung-inv-ledger` 스킬의 1번 함정과 같은 것).
⇒ `other_bins_uncounted` 가 비어 있지 않으면 **Cin7 조정 전에 반드시 확인**.

### 알려진 결함 (2026-08-20 코드 리뷰 · 미수정)

- ⚠️ **에드먼턴 판별이 문자열 패턴** — `/^E[A-Z]/`(토론토 Zone E 와 구분).
  로케이션 명명이 바뀌면 조용히 틀린다
- ⚠️ **`wrMarkQtyApplied()` 가 무차별** — PENDING QTY 를 **전부** APPLIED 로 바꾼다.
  리포트 생성 후 새로 들어온 정정까지 「반영했다」가 된다. 리포트 시각 이전만 마킹해야 맞다
- ⚠️ **창고 합계 제안식이 근사** — 주석도 「단순화」라고 인정. 같은 창고 다른 bin 에서
  **이미 카운트된** 값은 안 더한다. 여러 bin 을 다 센 경우 제안값이 틀린다
- **BQ 쿼리 SQL 인젝션 방어가 백슬래시 이스케이프** — `queryParameters` 바인딩이 정석.
  SKU 는 내부 데이터라 실害는 낮음
- **`applied_at` 이 LOC 정정에는 안 채워진다** — 위치 정정은 반영 추적 경로가 아예 없다

---

## 6. [실사고] 대소문자 중복 파일 (2026-08-20 해소)

**증상**: `WarehouseMap.html`(7/23) 과 `warehousemap.html`(7/08) 이 공존.
`git log` 는 `Add files via upload` 9건 + `Delete WarehouseMap.html` 1건 —
**과거에 한 번 정리했다가 되살아났다.**

**진단**: 진입 링크 9곳이 **전부 소문자**. 대문자를 가리키는 링크는 0곳.
그런데 **딥링크 15줄이 대문자판에만** 있었다 → WMS `picker` 가 `?loc=` 로 불러도
**조용히 무시되고 있었다**(에러 없음). 약 한 달.

**해소**: `init()` 을 소문자판에 이식 → `git rm WarehouseMap.html` → 한 커밋으로
push (`4efe6cd`). 되살리려면 `git show 6a46ad5:WarehouseMap.html`.

⚠️ **근본 원인은 삭제를 안 해서가 아니라 GitHub 웹 UI 드래그 업로드**다.
원본 파일명(대문자)으로 올리면 또 생기고, **또 조용히 안 먹는다.**
⇒ 로컬 `git add`/`commit`/`push` 로 바꾸는 것이 진짜 해결.

📌 **교훈**: 파일명 대소문자만 다른 중복이 보이면 **먼저 diff, 그다음 링크 grep.**
최신 파일이 실사용 파일이라는 보장이 없다.

---

## 7. WMS 통합 (계획 · 2026-08-20 합의 · 미착수)

목표: 별도 사이트가 아니라 **WMS 안의 한 화면**으로.

| | 지금 | 통합 후 |
|---|---|---|
| 레포 | `tools`(public) | `asung-wms` |
| 인증 | PIN + 이름 타이핑 | `wms-auth` · `wms_staff` · perms |
| 데이터 | 정적 `bins.json` | Supabase |
| 쓰기 | GAS → 구글시트 | Edge Function → Postgres |

**순서 (합의)**:
1. **껍데기 이관** — 레포 이동 + `wms-auth` 적용, 데이터는 당분간 `bins.json` fetch 유지
2. **데이터 층 교체** — ⚠️ **원장 ⑥ 대조가 끝난 뒤.** 원장은 shadow 모드 =
   「어디에도 안 쓴다」가 원칙이라, 지도가 원장을 읽으면 그 원칙이 깨진다
3. **쓰기 이관** — 실사 정정을 Postgres 로. 구글시트 경로 은퇴

⚠️ **지금 데이터 층을 옮기면 두 번 짓게 된다** — 원장 3단계가 자리(bin) 단위 재고를
만들고 있고, hard flip 되면 `asung_bin_stock`(Cin7 기반) 자체가 대체 대상이다.
📌 설계 원칙 「자체 IMS 의 API 는 호출자가 필요한 데이터를 **한 번에** 받게」 —
**지도는 그 API 의 첫 소비자로 적합**하다.

### 착수 전 열린 질문

- WMS 에 이미 bin 단위 재고가 있는가(`wms_sku_snapshot` 의 grain 미확인)
- ⚠️ 1단계에서 `bins.json` 을 다른 오리진에서 fetch 할 때 CORS
- 2.3MB 를 매 로드마다 받는 구조를 유지할 것인가
- ⚠️ GAS 가 `tools` 에 push 할 때마다 **Pages 가 전체 재배포**된다
  (`bins.json`·`products.json`·`stock.json`·`data_orders.json` 여러 건/일)

---

## 8. 작업 방식

- 조사·판단 먼저 → Caleb 확인 → 구현. **한 번에 한 단계**
- git·SQL·GAS 배포·Cin7 호출은 **Caleb 이 직접**
- ⚠️ **원격 상태는 `git fetch` 후에 판정** (3절 실사고)
- ⚠️ **커밋 전 diff 실물 확인.** `git --no-pager` 로 페이저 회피
- GAS 수정 후엔 **New Version 재배포** (`asung-apps-script` 규칙 4)
- ⚠️ `tools` push 는 **즉시 Pages 배포**된다 — 업무 시간이면 타이밍을 판단할 것
- 배포 후 **강력 새로고침(Ctrl+Shift+R)** 으로 확인.
  캐시 때문에 「안 된다」가 배포 문제인지 캐시인지 안 갈린다
