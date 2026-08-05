---
name: asung-apps-script
description: >
  Asung Trading의 Google Apps Script 자동화 코드를 작성·수정·추가할 때 반드시 이 스킬을 먼저 읽으세요.
  Cin7 → BigQuery 적재 스크립트, 알림/이메일 자동화, 트리거 설정, 웹앱 배포 등
  GAS 관련 작업에서 트리거됩니다.
  "Apps Script", "GAS", "스크립트 추가", ".gs", "트리거 설정", "BQ 적재 자동화",
  "Script Properties", "웹앱 배포", "SalesOrderData", "SystemMonitor", "이메일 알림" 등의
  키워드가 나오면 이 스킬의 컨벤션(전역 상수 prefix, getProp 키 관리, diff-check 증분 적재,
  New Version 재배포 규칙, SystemMonitor 연동)을 반드시 따르세요. 컨벤션을 깨면 스코프 충돌이나
  배포 누락으로 자동화가 조용히 멈춥니다.
---

# Asung Trading Apps Script 자동화 스킬

Asung의 자동화는 여러 개의 Google Apps Script 프로젝트로 나뉘어 있고, 각 프로젝트 안에 여러 `.gs` 파일이 전역 스코프를 공유합니다. **새 코드를 추가할 때 기존 컨벤션을 깨면 변수 충돌·배포 누락으로 자동화가 말없이 멈춥니다.** 이 문서는 "우리가 GAS를 짜는 방식"을 인코딩합니다.

## 환경 상수 (공통)

| 항목 | 값 |
|------|-----|
| BQ Project | `geometric-rock-487814-k4` |
| BQ Dataset (sales) | `Cin7_Sales_Data` |
| BQ Dataset (purchase) | `Cin7_Purchase_Data` |
| Cin7 API Base | `https://inventory.dearsystems.com/ExternalApi` |

---

## 규칙 1 — 비밀값은 절대 코드에 쓰지 않는다

모든 API 키·토큰은 **Script Properties**에 저장하고 `Config.gs`의 `getProp()`로 꺼냅니다.

```javascript
// Config.gs
function getProp(key) {
  const v = PropertiesService.getScriptProperties().getProperty(key);
  if (!v) throw new Error('Missing Script Property: ' + key);
  return v;
}
```

표준 키 이름(값은 Script Properties에만 존재):

- `CIN7_ACCOUNT_ID`
- `CIN7_APPLICATION_KEY` — ⚠️ **`CIN7_API_KEY` 가 아니다.** `cin7-api` 스킬이 `CIN7_API_KEY` 로
  적혀 있어 **2026-08-05 실호출이 한 번 실패**했고, 근거 4:1 로 이 이름으로 통일했다
  (이 파일 · `shopify-tracking/references/customer-master.md` · `asung-wms` 환경 상수 ·
  `asung-wms/references/edge-function.md` 의 실동작 Supabase secret 대 `cin7-api` 한 곳).
  ⚠️ **Script Properties 실물 확인은 미실시** — `401/403` 이나 `Missing Script Property` 가 나오면
  추측하지 말고 Script Properties 화면을 열어 실제 이름을 확인하고 **양쪽 스킬을 함께** 고칠 것.
- `GITHUB_TOKEN`

**코드 리뷰/스킬 문서/커밋에 실제 키 문자열을 절대 넣지 마세요.**

---

## 규칙 2 — 전역 상수 prefix 규약 (스코프 충돌 방지)

한 GAS 프로젝트의 모든 `.gs` 파일은 **전역 네임스페이스를 공유**합니다. 그래서 `const CONFIG = …`를 두 파일에서 선언하면 충돌합니다. 이를 막기 위해 **파일/기능별 prefix**를 붙입니다.

| Prefix | 영역 |
|--------|------|
| `BO_` | Backorder 관련 |
| `FO_` | (Fulfillment/Order 등 해당 기능) |
| `EI_` | (Error/Invoice 등 해당 기능) |
| `MON_` | SystemMonitor |
| `RO_` | Reorder |
| `BC_` | Barcode |

예: `const BO_BQ_PROJECT = 'geometric-rock-487814-k4';`, `function bo_getDefaultEmailMap_() {…}`.

**새 스크립트를 추가할 때:** 새 prefix를 정하고, 그 파일의 모든 전역 상수·헬퍼 함수에 일관되게 붙이세요. private 헬퍼는 함수명 끝에 `_`를 붙이는 GAS 관례도 따릅니다(예: `bo_fetchStock_()`).

---

## 규칙 3 — BQ 적재는 diff-check 증분 패턴

전체를 매번 다시 올리면 타임아웃(6분 제한)에 걸립니다. `SalesOrderData.gs`는 BQ에 이미 있는 것과 비교해 **바뀐 것만** 올리는 diff-check로 실행시간을 1800초 → 약 1분으로 줄였습니다.

골자:

1. BQ에서 현재 적재된 키 집합(예: 주문번호+상태 해시)을 가져온다.
2. Cin7에서 받은 데이터와 비교해 신규/변경 행만 추린다.
3. 그 delta만 적재한다.
4. 같은 기간 재적재가 필요하면 **CTAS로 통째 교체** (streaming buffer가 DELETE를 막으므로).

자세한 적재 코드 패턴과 dedup 주의점은 `references/bq-load-patterns.md` 참고.

---

## 규칙 4 — 웹앱은 수정 후 반드시 New Version 재배포

`/exec` URL로 노출되는 웹앱(Customer Portal, reorder-proxy, BarcodeLogger 등)은 **코드를 고쳐도 새 버전으로 재배포하지 않으면 반영되지 않습니다.** 라이브 URL은 "배포된 버전"을 가리키기 때문입니다.

작업 절차:
1. `.gs` 수정
2. 배포 → **버전 관리 → 새 버전(New Version)** 생성
3. 같은 deployment에 새 버전 지정 (URL 유지)

> 사용자에게 코드를 전달할 때는 "수정 후 New Version 재배포 필요"를 항상 알려주세요. 이걸 빠뜨려서 "왜 안 바뀌지"가 가장 흔한 사고입니다.

---

## 규칙 5 — SystemMonitor에 연동

`SystemMonitor.gs`(System_Automation 프로젝트)는 주요 스크립트들의 실행 결과를 `Asung_System_Monitor` 시트에 로깅하고, 실패 시 Google Space로 알림을 보냅니다. **새 자동화 스크립트를 추가하면 모니터링 대상에 등록**해서 조용히 죽는 일이 없게 하세요. prefix는 `MON_`.

---

## 트리거 설정 패턴

시간 기반 트리거는 코드로 설치하는 `setup…Trigger()` 함수를 둡니다(수동 설정 의존 X).

```javascript
function setupDailyPurchaseTrigger() {
  // 중복 방지: 기존 동일 핸들러 트리거 제거 후 재설치
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'runDailyPurchaseReport')
    .forEach(t => ScriptApp.deleteTrigger(t));

  ScriptApp.newTrigger('runDailyPurchaseReport')
    .timeBased().everyDays(1).atHour(7).create();
}
```

---

## 스크립트 인벤토리

현재 운영 중인 스크립트와 각자의 역할·핵심 규칙은 `references/script-inventory.md`에 정리되어 있습니다. 기존 스크립트를 수정하기 전에 거기서 해당 스크립트의 제약(예: backorder는 `Status=ORDERED + AdditionalAttribute1='Backordered'`)을 확인하세요.

---

## 연계 스킬

- **데이터를 BQ에 올린 뒤 그걸 쿼리**하는 규칙 → `asung-bq-data-model`
- **Cin7 API 엔드포인트·파라미터·응답 구조** → `cin7-api`
- **이 데이터를 쓰는 프론트엔드 앱** → `asung-bq-apps`
