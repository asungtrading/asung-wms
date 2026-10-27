---
name: asung-apps-script
description: >
  Asung Trading의 Google Apps Script 자동화 코드를 작성·수정·추가할 때 반드시 이 스킬을 먼저 읽으세요.
  Cin7 → BigQuery 적재 스크립트, 알림/이메일 자동화, 트리거 설정, 웹앱 배포 등
  GAS 관련 작업에서 트리거됩니다.
  "Apps Script", "GAS", "스크립트 추가", ".gs", "트리거 설정", "BQ 적재 자동화",
  "Script Properties", "웹앱 배포", "SalesOrderData", "SystemMonitor", "이메일 알림",
  "IMS 적재 스크립트", "ImsRefLoad", "ImsLoadCustomer", "ImsLoadSupplier", "하네스", "IPT_LAST_APPLY_AT", "이어 달리기", "Next run", "대량 비활성" 등의
  키워드가 나오면 이 스킬의 컨벤션(전역 상수 prefix, getProp 키 관리, diff-check 증분 적재,
  New Version 재배포 규칙, SystemMonitor 연동, IMS 적재 스크립트 규칙 셋)을 반드시 따르세요. 컨벤션을 깨면 스코프 충돌이나
  배포 누락으로 자동화가 조용히 멈춥니다. ⚠️같은 이름 함수가 둘이면 에러 없이 뒤의 것이 이긴다 — 파일은 통째로 바꾼다.
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

## 규칙 6 — IMS 적재 스크립트(Ims*Load) 셋

Cin7 → Supabase(IMS) 적재 스크립트(`ImsRefLoad` · `ImsLoadProduct` · `ImsLoadCustomer` · `ImsLoadPrice`(접두 `ilp` · 2026-09-23 · ⭐ 바뀐 것만 보낸다 — 다시 돌려도 남은 것만 · so-module 11-g) · 사본 `asung-wms/docs/probes/*.gs` · 원본은 GAS)가 공통으로 지키는 셋. 적재 규칙 자체(무엇을 보내고 무엇을 내리나)는 모듈 스킬(`asung-po` §3 · `asung-so` §1)과 정본이 갖는다.

```
⭐ 이어 달리기 수집 — 4분 30초에서 새 페이지를 멈추고 받은 것을 Drive 에 저장 · Script Properties 에 다음 페이지 · 로그에 「Next run」이면 다시 실행
   (6분 제한 대비 · 429 가 오면 쉬고 이어 받는다 · 끝 판단은 Total 이 아니라 받은 행 수 < Limit)
⭐ 대량 비활성 안전장치 — 받은 행 수 ≠ API Total 이면 멈춤(수집이 짧게 끝난 것) · 한 번에 내리는(is_active=false) 줄 > max(20, 1%) 면 멈춤
   맞으면 허락 속성(예 ILC_ALLOW_BIG_DOWN=1)을 넣고 **한 번만** 통과 · 계기: 2026-09-22 가짜 데이터 시험에서 수집이 짧게 끝나자 151명을 내렸다
⭐ [2026-10-10 · so-module §57-c] ImsLoadProductTag.gs(접두 ipt · c61ba04) — 관계 표(product_tag) 맞추기: 원하는 집합 − cin7 줄 = 넣기 · cin7 줄 − 원하는 집합 = 지우기(행 삭제 · 먼저) · manual 무접촉 · **커서 없음**(매번 Cin7 을 새로 훑어 diff — 다시 돌리면 남은 것만 · Next run 도 같은 함수) · 큰 지우기 안전장치(> max(20, 1%) · IPT_ALLOW_BIG_DELETE=1 한 번만) · 지우기는 ~~id 40 개씩~~ → [2026-10-27 · url-1 · cdd897e] **id 부분 글자 수 1,500**(`ipt_idChunks_` · IPT_DELETE_MAXLEN · UrlFetch URL 한도 짐작 2 KB · 시간 확인 · finish 흐름은 덩이마다 그대로)
⭐ [2026-10-24 · ldfix · so-module §73 · 판정 671] **IMS 가 정한 값은 적재가 건드리지 않는다** — 적재 다섯 공통
   · 짝짓기(674 · 681): cin7_id 없는 IMS 행(manual)과 이름(제품은 SKU)이 같으면 그 행에 cin7_id 만 PATCH(`id=eq.<id>&cin7_id=is.null` · 0 행이면 멈춤) · 이름 비교는 보이는 글자(`ils_vis_`)
   · 손댄 행(672): `source='cin7' and updated_by is not null` 을 Dry 가 IMS ↔ Cin7 값으로 낸다(ims_touch 가 service_role 쓰기 땐 updated_by 를 비운다) · 보조 `*_LAST_APPLY_AT`(Apply 끝에 코드가 적는다 · ILC · ILS · IPR · IPT)
   · 칸 표식이면 IMS 값을 **같은 키로 싣는다**(행마다 칸을 빼지 않는다 — 묶음의 빠진 키 · asung-wms 규칙 45): sellable_source · is_active_source · parent_source
⭐ [2026-10-24] ImsLoadSupplier.gs(접두 **ils** · 판정 673) — imsLoadSupplier → Apply → Sub → SubApply → Verify · Apply 끝 rpc `product_supplier_default_recalc`(682 · 제품-공급처 Apply 끝도) · 허락 ILS_ALLOW_BIG_DOWN · ⛔ imsLoadPurchasableApply 는 dryRun 만 · ⚠️ 손님 적재가 이 파일의 `ils_vis_` 를 부른다 — 편집기에서 지우지 마라(deferred 322)
⭐ [2026-10-24] ImsLoadProduct.gs Dry 는 전량을 훑는다(커서 IPR_DRY_PAGE · ⏸ 면 다시) · ImsLoadProductTag.gs 는 Dry · Apply 마다 Drive 보고 파일 셋(폴더 IPT_FOLDER_ID · 코드가 만든다 · 676) · IPT_LAST_APPLY_AT 가 없으면 코드 기본값 2026-10-10T18:52:00Z(「기본값 사용」 을 로그에) — 속성을 사람이 넣는 단계는 없다(50 개 초과 · 읽기 전용)
⭐ [2026-10-24] **시험 하네스** `asung-wms/docs/probes/harness/` — 가짜 GAS + PostgREST 에뮬레이터(emu) · 로컬 Supabase 진짜 PostgREST(local · 테스트 DB 스키마 덤프 복원) · `run-<적재>.js [emu|local]` · 적재 코드를 고치면 다섯 적재 회귀를 돌린다 · ⚠️ `node --check` 는 `.gs` 를 거부 → `.js` 사본 · 시험 전 대상 파일 md5 · mtime 을 찍는다
   ⚠️ 틈: 넣기가 ipr_upsert_(merge-duplicates)라 적재 도중 직원이 같은 태그를 붙이면 manual 줄이 cin7 줄로 바뀔 수 있다 — 정기 재적재로 바꿀 때 ignore-duplicates 로(so-module 미룬 175)
⭐ Apps Script 는 같은 이름 함수가 둘이면 **에러 없이 뒤의 것이 이긴다** — 파일을 고칠 때는 통째로 바꾼다(덧붙이지 않는다) · 파일별 접두(cup · ilc · ilp · ptp …)로 겹침을 막는다
⭐ [2026-10-23 · so-module §72] ImsLoadHist.gs(접두 ilh · 판정 660) — IMS 이전 판매 · 발주 이력 → hist_so_load · hist_po_load(service_role) · 함수 ilhDry → ilhPairs → ilhLoadPurchases → ilhLoadSales(당월만 다시 = ilhRedoCurrentSales) · ilhReset
   쪽 ILH_PAGE_ORDERS 기본 100(REST statement_timeout 8 초 안 · 실측) · ILH_PRACTICE=1 = 연습 적재(주인 · 제품 못 풀림을 멈추지 않는다 · IMS 번호 겹침은 멈춘다 · 664 · 665 · 컷오버 직전 적재 전에 지운다) · 당월 표 Sale 은 단가라 sale 칸에 Total(667)
   ⚠️ 확정 표를 새로 올린 뒤에는 ilhRedoCurrentSales 가 아니라 ~~ilhReset 뒤 ilhLoadSales 전체~~(당월 → 확정으로 옮겨 간 오더가 틀린 채 남는다)
   → [2026-10-24 · so-module §73 · deferred 303] **판매 커서 일곱만 지우고 ilhLoadSales** — ILH_SO_CONF_CURSOR · ILH_SO_CONF_DONE · ILH_SO_CONF_SUM · ILH_SO_CURR_CURSOR · ILH_SO_CURR_DONE · ILH_SO_CURR_SUM · ILH_SO_SUM(임시 함수로 지우고 그 파일을 지운다 · 50 개 넘어 화면 읽기 전용) · ⚠️ ilhReset 금지 — 짝(ILH_PAIRS_* 여덟)까지 지워 ilhLoadSales 가 「짝이 없다 — ilhPairs 먼저」 로 멈춘다 · 발주 · ILH_PRACTICE 는 그대로
⚠️ [2026-10-23] **Script Properties 가 50 개를 넘으면 설정 화면이 읽기 전용** — 코드(PropertiesService)로 바꾼다: 임시 파일에 setProperty 함수 → 실행 → 그 파일을 지운다(같은 이름 함수 함정 · 남겨 두지 않는다)
⭐ [2026-10-26 · so-module §79-c · 판정 775 · 783 ~ 786] **ImsLoadOpening.gs**(접두 **ilo** · d6be2d6) — 컷오버 날 미수 · 받아 둔 돈 이월 → 창구 so_opening_load(service_role) · 대상 Asung-IMS(SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY)
   iloCollect → iloDetail → iloBuild(쓰기 0 · sale 마다 상세 ↔ 목록 대조) → iloDry → iloApply(Dry 때와 같은 p md5 · 직전 Dry 한 번 더) → iloVerify · iloReset(ILO_STATE 만 지움) · 순서 · 멈춤은 reload-procedure §P-2 12b
   ⭐ Script Properties 는 **ILO_STATE 하나**(JSON · 속성 50 개 초과로 화면이 읽기 전용) — 허락도 속성이 아니라 그 안의 표지 · **함수 iloAllowMismatch · iloAllowRejects** 로만 켠다(각각 Apply 의 멈춤 하나를 **한 번만** 통과 · 쓰면 꺼진다)
   ⚠️ iloAllowMismatch 는 어긋난 sale 을 Cin7 화면으로 확인한 뒤에만 · as_of 는 ilo_cfg_ 의 asOf(비우면 Build 날 · 창구는 미래 as_of 거부)
   ⭐ [2026-10-27 · ilo-zero-1 · e194933 · so-module §81-a · 판정 797] **회계에서 0 처리된 인보이스 19 장 = 상수 `ilo_zeroDocs_`**(보고서 「Sales Outstanding Balance」 Due 칸 파랑 JE Write Off · 주황 No Outstanding Balance · QuickBooks 에서 0 · Cin7 은 Lock 으로 못 고침)
      → 그 인보이스 줄 · 단일 인보이스 sale 의 overpay 줄을 p 에 싣지 않는다 · **손님 크레딧(CR-…)은 거르지 않는다** · 목록은 레포 상수(Script Property 아님 · 컷오버 날 같은 판)
      가드(Build 를 멈추고 build json 을 남기지 않는다 · 보고서 0z 표): 수집에 없다 · 번호가 두 곳 · SO 번호가 다르다 · VOIDED/DRAFT · Total 이 다르다 · Due 가 0.01 넘게 다르다 · 종류(open/overpay)가 안 맞다 · overpay 인데 다중 인보이스(deferred 350)
      그 sale 의 live 인보이스가 전부 목록이면 대조 어긋남 면제(SO-10447 — 「면제된 대조 1」) ⇒ **리허설의 iloAllowMismatch 단계는 없어졌다**(함수는 남아 있다 — 다른 sale 이 어긋나면 Cin7 화면 먼저)
      하네스 `docs/probes/harness/run-opening.js`(58962ae · Build 를 node 에서) · 실측 12:05 Build = CAD 294 장 976,939.54 · 받아 둔 돈 81 줄 6,308.16 · 0z 문제 0
⭐ [2026-10-26 · ar-1] **OpeningProbe.gs**(접두 **opp** · daf8af5) — 읽기 전용 Cin7 프로브(열린 인보이스 · 오버페이 · 손님 크레딧) · 쓰기 없음 · 원천 규칙은 so-module §79-c
⚠️ [2026-10-27 · so-module §80-c · c91bc24] **`in.(…)` 는 개수가 아니라 글자 수로 나눈다** — ImsLoadCustomer Apply3 가 `Limit Exceeded: URLFetch URL Length`(ilc_patchIn_ · id 100 개씩)로 첫 묶음에서 섰다(쓰기 0)
   Apps Script URLFetch URL 길이 한도(정확한 값은 짐작 2 kB) · ilc_patchIn_ 은 1,500 자로 잡았다 · ~~개수로 나누는 다른 곳(ImsLoadPrice ilp_patchIds_ · ImsLoadProduct ipr_recheckKept_ 100 개 …)은 deferred 349~~
   → [2026-10-27 · **url-1** · cdd897e · deferred 349 닫힘 · so-module §81-b] 넷 모두 **id 부분 글자 수 1,500** — 파일마다 자기 접두의 순수 함수 `ilp_idChunks_`(ImsLoadPrice) · `ils_idChunks_`(ImsLoadSupplier) · `ipr_idChunks_`(ImsLoadProduct) · `ipt_idChunks_`(ImsLoadProductTag)
      1,500 넘는 키 하나는 혼자 한 묶음 · 공용 파일은 기각(편집기에 그 파일이 없으면 모두 멈춘다 — deferred 322 사례) · 하네스 `docs/probes/harness/run-inchunks.js`(186 줄 · 회귀 일곱 통과)
      ImsLoadCustomer ilc_patchIn_(c91bc24)은 무접촉 — 그 docblock(ImsLoadCustomer.gs:596 「100개씩」)은 옛 글 · 다음에 그 파일을 만질 때 · 다른 `in.(` 자리 0(Opening · Hist · RefLoad · ProductSupplier) · GAS 에 네 파일 붙임(Caleb 2026-10-27)
⭐ [2026-10-27 · so-module §81-b] **GAS 프로젝트 = `System_Automation`**(IMS 적재 스크립트도 여기 · 「Asung-IMS 프로젝트」 가 아니다 — Asung-IMS 는 DB 이름) · **GAS 파일 이름 ≠ 레포 이름** — GAS 에서 그 파일을 찾는 법 = 그 파일만의 함수 · 상수 이름으로 Ctrl+F
   GAS Imsloadcustomer.gs ↔ 레포 ImsLoadCustomer.gs · Imsloadprice.gs ↔ ImsLoadPrice.gs · Imsloadproduct.gs ↔ ImsLoadProduct.gs · ImsTagProbe.gs(이름을 ImsLoadProductTag.gs 로 바꿨을 수 있다 — 짐작) ↔ ImsLoadProductTag.gs
   같은 이름: ImsLoadSupplier.gs · ImsLoadOpening.gs · ImsLoadHist.gs · ⚠️ Imsloadproductsupplier.gs 는 Imsloadproduct.gs 와 **다른 파일**(제품-공급처 · 레포 ImsLoadProductSupplier.gs 짐작)
```

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

⚠️ **`BackorderedItemEmail.gs` 는 IMS 메일로 넘어간다**(so-module §65 · 판정 493 ~ 519) — 지금은 **caleb@ 계정**의 GAS 가 From 만 backorder@(Google 그룹) 로 바꿔 월 · 목 트리거로 보낸다 · IMS 는 ims@ 계정 · From notifications@ · EF mail · cron 으로 같은 일을 한다(테스트에서 섰다) · **정지는 mail-5(운영 전환)에서 IMS 켜기와 같은 날** — 그 전에 이 스크립트를 고치거나 끄지 마라(중복 · 누락)

---

## 연계 스킬

- **데이터를 BQ에 올린 뒤 그걸 쿼리**하는 규칙 → `asung-bq-data-model`
- **Cin7 API 엔드포인트·파라미터·응답 구조** → `cin7-api`
- **이 데이터를 쓰는 프론트엔드 앱** → `asung-bq-apps`
