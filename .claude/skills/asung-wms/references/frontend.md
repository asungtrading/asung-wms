# WMS 프론트엔드 · 인증 · 배포 참조

## 파일 구조 (repo 루트, 전부 같은 폴더)

```
index.html          런처 (다크, 로그인 게이트, role별 메뉴)
picker.html         픽킹 (셀프서브, 스캔)
packer.html         패킹 (전량 재스캔 검수)
manager.html        오더 분할 + wave 그룹핑 (매니저, Split|Group 토글)
admin.html          관리자 대시보드 8탭 (매니저, Health 탭 포함)
staff-admin.html    직원 관리 (매니저) ← 여기서 role 지정
fulfillment.html    출고 구성 (팔렛/박스 + 팩킹리스트, 작업자)
receiver.html       리시빙/풋어웨이 (작업자, 한 PO 를 여러 명이 나눠 받기 — 규칙 24~27)
wms-config.js       window.WMS_CONFIG = {SUPABASE_URL, SUPABASE_ANON_KEY}
wms-auth.js         공유 로그인 모듈
asung-logo-white.png  런처용 (어두운 배경)
asung-logo-dark.png   6화면용 (밝은 헤더)
CNAME               "wms.asung.ca"
.nojekyll           (빈 파일, Jekyll 스킵)
supabase/           Edge Function (배포 소스)
```

## 화면 로드 순서 (각 <head>)
```html
<script src="wms-config.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script src="wms-auth.js"></script>
```
그리고 `boot()`에서:
```js
wmsAuth.start({requireManager:false}, (sb, me)=>{ /* me.name, me.role, me.warehouse_access */ });
```

## wms-auth.js API
- `wmsAuth.start({requireManager:bool, requirePerm:"split"|"admin"|"staff"}, cb(sb, me))` — 로그인 게이트. requireManager=true면 worker 차단. **`requirePerm`**(2026-07-21): 매니저는 `me.perms`에 해당 값 있어야 통과(admin 역할은 항상 통과), 없으면 차단.
- `wmsAuth.signOut()` — 로그아웃 + reload.
- `me` = `wms_staff` 행 전체 (id, name, email, role, warehouse_access, active, **perms**…).
- anon key 없거나 placeholder(`PASTE_`)면 "Setup needed" 표시.
- 로그인 후 #logoutBtn 옆 "Change Password" 자동삽입. "Forgot password"=resetPasswordForEmail.
- ⚠️ 로그인/모달 카드 클래스 `wcard`(페이지 `.card` 충돌 방지). 스타일 `#wmsAuthStyle` 주입.
- **☰ Menu 드롭다운(`setupNavMenu`, 2026-07-21)**: onReady에서 자동설치. 버튼 `title="Main menu"` 탐지. 권한반영 항목(순서 Admin→Order Splitting→Picking→Packing→Fulfillment→Staff→Home), 현재화면 파란표시, 바깥클릭 닫힘. `data-perm` 항목은 admin이거나 매니저 perms 포함 시만.
- **⚠️ bfcache reload(2026-07-21)**: `window.pageshow`(e.persisted) → `location.reload()`. 뒤로가기 복원 시 죽은 in-flight 요청으로 스피너 무한대던 문제 근본해결(전 화면 공통).

## 화면별 스캔진입 & 싱글모드 (2026-07-21)
- **오더 바코드 스캔진입**: picker(#orderScan → 배치 필터), packer(#orderScan → 팩배치 필터), fulfillment(#orderScan → 오더 로드, 멀티 누적). 바코드=배치라벨(SO-X-N) 또는 오더번호. 매칭: `on===f || bl.startsWith(f+"-") || bl===f`.
- **packer 싱글모드**: picker처럼 Single/List 토글(기본 List). 이미지/zone-bin/이름/sku/barcodeBlock/칩(Short/Pack fill/Over-scan).
- **싱글뷰 barcodeBlock**: base(factor1) + 변형(factor>1, ×12 등) + ALT-UPC(scannable_barcodes type='alt'). picker·packer 공통.
- **⚠️ -12 박스 스캔**: 형제 스냅샷 바코드를 bcMap에 병합해야 base 라인에서도 박스 바코드 스캔됨(picker/packer loadLines/enterPack).
- **리포트 버튼**: picker ⚑Wrong location/⚑Barcode changed, packer ⚑Barcode changed → `wms_reports` insert. **⚑Image differs**(2026-07-30, 양쪽 싱글뷰)는 프롬프트 없는 **토글** — `.rep.on`(amber 채움 + ✓)으로 눌린 상태, 재클릭 시 미해결 행 delete. `.reportrow`는 `flex-wrap`+`min-width:104px`(버튼 3개 좁은 태블릿 대응). 진입 시 `loadImageFlags()`가 독립 try 로 상태 복원(실패해도 픽/팩 뷰는 뜬다).
- **진입 즉시 렌더 후 enrich**: 라인 로드 후 즉시 렌더, 재고/바코드는 독립 try로 뒤이어. ⚠️ 존재않는 DOM id 참조 금지(렌더 죽음).
- **자동이동**: 스캔+수동(+/−·입력) 목표도달 시 autoAdvance(picker). packer 초과 시 confirmFillIfNeeded(소리+플래시+확인).
- **⚠️ 스캔 오류음**: 2400/1600Hz 교차 사이렌, 볼륨 1.0, 0.72초(작은 스피커 대응). 성공음 유지.

## 화면별 requireManager
| 화면 | requireManager |
|------|----------------|
| index (런처) | false (로그인만, 메뉴는 role 필터) |
| picker | false |
| packer | false |
| fulfillment | **false (작업자 화면)** |
| receiver | **false (작업자 화면)** |
| manager | true |
| admin | true |
| staff-admin | true |

## 런처 role 메뉴 필터
- worker: Picking / Packing / Fulfillment
- manager: perms에 있는 것만(split=Order Splitting, admin=Admin, staff=Staff) / admin: 전부
- 구현: 매니저 카드에 class `mgr-only`(CSS `display:none`) + `data-perm`, 로그인 후 admin이거나 매니저 perms 포함 카드만 `classList.remove("mgr-only")`. ⚠️ `style.display=""`는 CSS 때문에 안 먹음 → classList.remove.

## admin 탭 (8탭, 2026-07-22)
Status(카드+In-Progress+**Finalized 섹션**) / Discrepancy / **Reports**(wms_reports 리뷰·resolve, kind 필터 All/Wrong location/Barcode changed/Image differs + open 건수, 배지=kind 무관 전체 미해결) / Stats(작업자 처리량+**평균 소요시간**+실수+**리시빙·트랜스퍼·풋어웨이**) / Rollback(단계 되돌리기+로그) / **Finalized**(옛 Packing Lists — 완료오더 기간목록, Fulfillment mix 카드, 🖨Print·⬇PDF·⬇CSV / direct는 "Direct pack" 태그) / Work Screens / **Health**(Rollback 뒤 위치).
- ⚠️ 탭 전환 핸들러가 각 loadXxx 호출. periodBar `custom` 인자는 반드시 객체 `{from,to}`(null이면 TypeError로 boot 중단).
- **팩킹리스트 PDF/CSV**: `getPackingData(oid)` 공용 → HTML(print)·jsPDF+autotable(PDF, CDN lazy-load, 로고=canvas dataURL)·CSV(BOM+CRLF). 컬럼 SKU·Barcode·Product·Qty.
- **Stats 탭 리시빙·트랜스퍼·풋어웨이 지표(2026-07-30, 규칙 37)**: 기존 픽/팩과 **같은 기간 필터(`statsPeriod`) 공유** — `loadStats()` 가 `loadRecvStats(r)` 를 fire-and-forget 호출(규칙 34: 픽/팩 렌더를 막지 않고, 조회는 `Promise.all` **2회 왕복**으로 묶음 — ①`wms_receipts`+임베드 `wms_receipt_lines`(FK 임베드, 라인별 왕복 없음) ②`wms_discrepancies` `source='receiving'`. receipts 기간 필터 기준 = `created_at`). 렌더 전 `statsRange!==r` 이면 버림(기간 연타 스테일 방지). 지표: **PO/트랜스퍼 구분**(`source_type`) receipt·라인(received_base>0 만)·수량(received_base 합) / 창고별(`warehouse`) / 소요시간 avg receive=`created_at→completed_at`·avg apply=`completed_at→applied_at`(음수·60일 초과 제외) / **Apply 결과** = 성공·부분성공(`apply_note` 의 `failed_moves(N)` — ⚠️ EF 와 공유하는 포맷, 규칙 21)·미적용(completed & `applied_at` null) / **풋어웨이** 완료율(`putaway_done`)·백로그(미완료 라인 수·수량)·트랜스퍼 라인 `exported_base>0` 비율 / **리시빙 discrepancy** over·short·off-PO 건수 + 미해결(`cin7_corrected=false`). **화면 각주 3개(전부 필수 유지)**: ①`exported_base` 는 수동 UPDATE 로 오염 가능(2026-07-28 TR-02935 344행 일괄 백필 — 규칙 30-4) → "WMS 가 옮긴 것"의 **근사치** ②리시빙 discrepancy 는 유니크 인덱스 버그(규칙 29)로 **2026-07-28 이전엔 기록된 적 없음** — 그 이전 기간은 데이터 없음 ③소요시간은 근무시간 기준(아래).
- **Stats 작업자 통합 + 근무시간 소요(2026-07-30, 규칙 37)**: 작업자별 리시빙은 별도 표가 아니라 **"Throughput by worker" 에 병합** — `renderProd()` 가 모듈 상태 `prodPP`(픽/팩, loadStats)와 `prodRecv`(리시빙 byWorker, loadRecvStats)를 도착 순서 무관하게 합쳐 그린다(이름 합집합 — 리시빙만 한 사람도 행 생성. 왕복 추가 없음 — 기존 loadRecvStats 집계 재사용, 규칙 34). 두 로더 모두 `statsRange!==r` 스테일 가드.
  - ⚠️ **receipt 수를 배치 수와 같은 스케일의 막대로 그리지 말 것** — receipt 하나가 5라인일 수도 344라인일 수도 있어 왜곡된다. 막대는 **Receive 라인 수** 기준이고, 그마저 배치 max 와 분리된 **자체 스케일**(`lineMax`)을 쓴다(344라인이 픽/팩 막대를 뭉개지 않게). receipt 수·putaway % 는 요약 텍스트로(`Receive 344 lines / 1 receipt (avg 2.0 h work time) · putaway 67%`). 막대 색 `--recv`(teal) — 픽(파랑)·팩(보라)과 구분. 풋어웨이는 네 번째 막대 금지(요약 텍스트만). `Receive lines` 링크 없음 — Pick/Pack batches 도 링크가 아니라 대응 뷰가 없다.
  - ⚠️ **리시빙 소요시간은 근무시간(work hrs) 기준 + 창고별 타임존** — 달력 경과로 계산하면 퇴근 후 밤·주말이 포함돼 26.7h 같은 쓸모없는 값이 나온다(실제 그랬음). `workMinutes(a,b,warehouse)` 하나를 타입 표·작업자 행이 **공유**(두 곳이 다른 계산이면 안 됨). 상수 `WORK_HOURS`(09–17)·`WORK_DAYS`(월–금)·`WH_TZ` 는 스크립트 상단 — 토론토/에드먼턴 2시간 차라 receipt 의 `warehouse` 로 타임존 결정(미매핑=토론토 폴백), 공휴일 미반영(백로그). 결과 0(전 구간 근무시간 밖)은 `< 1 min` 표시 — `—`(데이터 없음)와 구분. **남는 한계**: 이 값은 "순수 작업 시간"이 아니라 "시작~완료까지의 근무시간 경과" — receipt 를 열어두고 다른 일 한 시간이 여전히 포함된다. 순수 작업 시간은 스캔 타임스탬프 기반 집계 필요(백로그). 검증 케이스: 금 16:00 → 월 10:00 = 2 work hrs(금 16–17 + 월 9–10, 토론토·에드먼턴 벽시계 동일), 같은 UTC 순간을 에드먼턴 창고로 계산하면 3 work hrs.
- **Health 탭(2026-07-22, 규칙 19)**: `loadHealth`가 `sb.rpc("wms_health_check")` → healthCard 렌더(critical=빨강/warn=주황/info=회색 좌측 보더, fail_count·Show sample 접이식 테이블). `updateHealthBadge`/`refreshHealthBadge`로 critical>0이면 탭에 빨강 숫자 배지. 함수 미설치 시 "not installed yet" 안내. 함수: loadHealth/healthCard/healthInfoValue/fmtHealthVal/sampleTable/updateHealthBadge/refreshHealthBadge.

## manager 오더 분할 + wave (2026-07-22)
- **Split | Group 토글**(`#modeSeg`). Split=오더 하나 쪼개기, Group=소량 오더 여럿 묶기.
- **Split**: 하이브리드 컷 — 라인 한도(기본40) **or** 낱개 한도(기본300) 먼저 걸리는 쪽. 우선순위 없음, 각 배치는 둘 다 만족. 단일라인이 낱개한도 초과 시 혼자 배치(라인 안 쪼갬). UI에 안내문(`.splitnote`). Create batches → 배치별 픽리스트 자동 프린트(창은 클릭 제스처 내 open). 배치 1개=1페이지: 로고+배치라벨 CODE128 바코드+오더/창고/고객/총라인·총유닛/Picked By+**Zones 요약**(품목표 없음).
- **Group(wave, 규칙 18)**: 필터바(기본 라인≤5·낱개≤100, `#waveMaxLines`/`#waveMaxUnits`) 통과 소량 오더만 표시. 탭으로 담음(선택 순서=토트 번호, TOTE 배지). **같은 창고만**·**최소 2**·**최대 `WAVE_MAX=10`**. Create wave → `wms_waves` insert + 오더별 pick 배치(`{order}-1`, wave_id·tote_no) + task lines + orders status picking → wave 픽리스트 프린트(wave 바코드 1개 + 토트 배정표). 실패 시 best-effort cleanup(task lines→tasks→wave 역순 삭제). 함수: waveLimits/waveCandidates/renderWaveQueue/toggleWaveSel/renderWaveWorkbench/printWaveList.
- 모바일: 오더 선택 시 작업영역 자동 스크롤 + "✓ selected" 표시.

## picker wave 모드 (2026-07-22, 규칙 18)
- **Waiting Waves 섹션**(개별 배치 목록과 분리). loadBatches가 기존 3쿼리에 `.is("wave_id",null)` 추가(wave 멤버 숨김) + wave 3쿼리(pending/mine/stale) 병렬. `waveCardHtml` + renderBatches의 `data-kind="wave"` 분기.
- **wave 단위 동작**: startWave/resumeWave/takeoverWave(낙관적 잠금 동일 패턴, wave 행 + 멤버 태스크 동시 claim). loadLines·loadWaveLines가 공유 `enterPickView`(zone 정렬+tote 타이브레이커, bcMap, 렌더, avail/sibling enrich)로 수렴. heartbeat=wave 행+멤버, beatOnce/markWorkStarted/resetToList가 wave 분기.
- **sort-to-tote UI**: renderSingle 보라 토트 배너(`.totebar`), renderList `T{n}` 칩(`.lrow .tt`), processScan 플래시 "✓ TOTE n · SKU +f". 라인은 wave 전체 zone 병합(tote는 타이브레이커).
- **⚠️ finish() discrepancy 오더별 귀속**: wave면 `l._orderId`/`l._orderNumber`(loadWaveLines가 태스크→오더 매핑으로 세팅) 사용, task.order_id 아님. 완료 시 멤버 태스크 일괄 completed + wave 행 completed. hold/back도 wave면 멤버+wave 동시 처리.

## fulfillment Finalize & 터치드래그 (2026-07-21)
- **✓ Finalize order(s)**: 팔렛/박스 유무 무관 완료(direct=픽업/즉시출고). status='closed' 저장, `fulfillment_type`/`finalized_by`/`finalized_at` 기록. loadOrders는 closed 제외.
- **터치 드래그 shim**: 네이티브 HTML5 DnD가 터치서 drop 안 됨 → touchstart/move/end로 dragstart/dragover/drop/dragend 합성(플로팅 클론+elementFromPoint+clearHi). 마우스 DnD 그대로.
- 팩킹리스트에 Barcode 열(스냅샷 sku별 대표바코드, `bcBySku`).

## RLS
- wms_ 테이블 전부(wms_waves 포함) `rowsecurity=true` + 정책 `auth_all`:
```sql
create policy auth_all on <table> for all to authenticated using (true) with check (true);
```
- anon 거부, authenticated 전체허용. service_role은 우회(GAS 동기화·Edge Function 자동주입 키가 RLS 안 걸림).
- 세분화(매니저만 쓰기)는 백로그.

## 인증/계정
- Supabase Auth 20명(dashboard Add user + 임시비번 + Auto Confirm).
- `wms_staff.email` unique, 이름↔이메일 매핑됨. 로그인=이메일→wms_staff 행→role.
- Edmonton 작업자: Jan Ko, Joon Kwon, Jeff Shim.
- 관리자: Caleb(admin/both). 매니저 지정 예정: Ho Kang, Ted Shin, Changmo Ku, Jan Ko.
- ⚠️ 배포 후 Supabase Authentication→URL Configuration: Site URL=`https://wms.asung.ca`, Redirect URLs=`https://wms.asung.ca/*` (비번재설정 링크가 localhost로 가는 것 방지).

## 배포 (GitHub Pages)
- Source: Deploy from a branch `main`/`(root)`. 파일 루트에.
- `.nojekyll` 필수(supabase/·.vscode/ 때문에 Jekyll 실패). CNAME=wms.asung.ca.
- **Startup failure(0초)** = GitHub Actions 인프라 장애(githubstatus.com), 우리 잘못 아님 → 복구 후 Re-run.
- 파일 문제면 3~4분 돌다 실패(빌드 후), 시작 실패 아님 → `.nojekyll`로 해결.
- DNS "Check in Progress"→"successful"은 페이지 열 때마다 정상.

## fulfillment.html 상세
- 멀티오더: "N orders ▾" 체크리스트(고객별 그룹) → 여러 오더 동시 작업. 프랜차이즈=여러 고객 혼합 허용("N customers mixed" 경고만, 차단 아님).
- 오더→배치 2단 그룹 드래그. 제품/배치를 팔렛·박스로. 박스→팔렛 위로 드래그=중첩. 부분수량 모달.
- 혼합 팔렛: 각 item이 order_id 가짐(오더별 추적). 유닛 로드=선택오더 홈 유닛 ∪ 선택오더 item 가진 유닛 + 자식박스.
- 팩킹리스트 2종: (a)유닛별 (b)스토어별 종합(각 스토어 1페이지 page-break, 그 스토어 물건이 어느 팔렛/박스에 얼마나 + ⚠️미배정 경고). **스토어별 종합에서 혼합 박스는 `⚠ MIXED BOX — holds N orders, re-sort at destination` 로 강조**(2026-07-29).

### 스캔 배정 (2026-07-29 추가 — 세 번째 입력 수단, DnD·탭은 그대로) · ⚠️ **실전 미검증**

> ⚠️⚠️ **2026-07-30 기준 실물 테스트가 끝나지 않았다** — `Move all` 기본값 · 포커스 정책 · 오프라인/순단 롤백 · **기존 DnD·탭 경로 회귀** · 태블릿 sticky 오프셋 미확인. 정책 근거는 **SKILL 규칙 36**, 아래는 구현 지도다.

parcel(박스) 출고는 담으면서 맞추는 작업이라 집는 순간 스캔으로 배정되는 흐름이 필요했다. 전제: **프랜차이즈 손님은 여러 스토어(=여러 오더)의 물건을 한 번에 받아 스토어별로 재분배**한다 → **팔렛은 섞여도 되고(박스를 얹는 그릇), 박스는 오더 하나가 원칙**(섞이면 받는 쪽이 풀어서 재분배해야 함).

- **타깃 = 화면 탭**: 유닛 카드(중첩 박스 포함) 탭 → 스캔 타깃(보라 테두리 `.scan-target` + 스캔바 배너 "Scanning into: 📦 BOX-3", 같은 카드 재탭=해제). 유닛 라벨 바코드 방식은 의도적으로 안 만듦(라벨 부착 작업 증가). 타깃 미선택 스캔 → "Select a box or pallet first". ⚠️ **타깃 선택 리스너는 스크립트 최상위에서 1회 등록**(`#units` delegated) — `wireUnitEvents` 안에 넣으면 렌더마다 중첩 등록돼 토글이 깨진다. `armed` 상태면 반환해 기존 tap-to-place 에 양보(등록 순서가 먼저라 안전).
- **입력 = `#prodScan`** (`#orderScan` 과 별개 — 오더 로드용은 그대로). **포커스 정책(2026-07-29)**: 오더 로드 후엔 `#prodScan` 이 **기본 포커스**(상품 스캔이 주 작업 — HID 스캐너는 포커스된 곳에 타이핑하므로 포커스가 어긋나면 조용히 실패한다). `focusProdScan(force)` — 오더 로드 완료·타깃 탭·스캔 처리 후·모달 닫힘 후 복귀하되, **다른 input/textarea 편집 중엔 안 뺏는다**(force 는 오더 로드 직후·#orderScan 전달 직후만). 잘못 들어간 스캔 감지: `#orderScan` 에 bcMap 바코드 → 타깃 있으면 상품 스캔으로 그대로 처리, 없으면 "Looks like a product barcode…" 안내 / `#prodScan` 에 오더·픽리스트 바코드 → "use the order scan field" 안내만. 스캔바 sticky top 과 scrollIntoView 여유는 고정값이 아니라 **`setStickyOffsets()` 실측**(`--hdr`/`--stickyclr` — 헤더가 태블릿에서 두 줄로 접히고 Move-all 배너로 바 높이가 변해서, 고정 58px 은 겹친다).
- **모드 2종**(`scanMode`, 화면에 크게 표시 — Move all 은 주황 배너+테두리): **Scan qty**(기본, base=+1·케이스=+factor, bcMap 3단과 형제 -12 병합은 picker 패턴 재사용) / **Move all**(스캔 SKU 의 미배정 잔량 일괄 — 단 **대상 유닛에 담긴 오더 것만**, 오더 경계를 안 넘는다. 빈 유닛이면 오더 확정 모달 먼저).
- **bcMap 은 `order_line_id`(olid) 기반**(규칙 25): `bcMap[code]=[{olid,factor}]`. `buildScanMap()`(wms_order_lines.scannable_barcodes) + `mergeSiblingBarcodes()`(wms_sku_snapshot by base_sku, 독립 enrich try). ⚠️ 분할 오더는 같은 olid 가 배치별로 poolLines 에 중복 — 잔량은 `remainingOl(olid)=packedTotal-assignedFor` 집계로 계산(개별 entry 의 `remainingFor` 아님).
- **오더 귀속 3단**: ①그 SKU 잔량 있는 오더 1개 → 자동 ②여러 개인데 **대상 유닛에 담긴 오더**(팔렛은 자식 박스 포함, 박스는 자기 것만)가 그중 하나 → 자동 ③그 외 → 오더 선택 모달(조용히 추측 금지 — 잘못 귀속되면 스토어별 리스트가 틀어짐).
- **박스 혼합 가드**(`guardBoxMix`, 팔렛은 스킵): 박스에 이미 다른 오더가 담겨 있으면 모달 — 주 버튼 **`New box for SO-456`**(같은 부모 팔렛에 새 박스 insert 후 타깃 전환, 올바른 동작이 가장 쉬워야 한다) / `Add to this box anyway`(차단 안 함 — "N customers mixed" 와 같은 방침) / Cancel. 박스 카드엔 오더 배지(단일=`SO-123 · Store X`, 혼합=`⚠ N orders mixed`), 팔렛은 배지 없음.
- **초과/거부**: 잔량 초과 케이스 스캔 → 잔량까지만 + warn 토스트("only N remained — added N"). 잔량 0 → 거부 "Already fully assigned". 오더에 없는 바코드 → 거부 "Not on the selected order(s)". **거부는 성공과 다른 소리**(2400/1600Hz 사이렌)+빨간 풀폭 플래시.
- **낙관적 렌더 + 뒤 저장**: 스캔 즉시 로컬 `items` 반영 → 렌더(타깃 카드에 행 추가/수량 증가+1.5초 하이라이트 `.just`, 헤더 `N lines · M units` 실시간, 풀 잔량 동시 감소) + `scrollIntoView` + 삐/플래시/토스트 `BOX-3 ← APR15412 ×12`. **피드백을 await 로 막지 않는다**(규칙 24).
- **저장 엔진**: `assignState`("uid:olid"→{id,confirmed}) + `writeChain`(같은 행 추월 방지) + `pendingWrites`. `syncAssign` 이 flush 시점 로컬 수량으로 행을 동기화(insert 는 `.select().single()`, update 는 `.select("id")` **1행 판정** — 규칙 24; 0행=행 소실→재insert). **실패 시 `rollbackKey`**: confirmed 값으로 되돌리고 "Not saved — … removed from BOX-3, scan again" 빨간 경고, 해당 행 undo 로그 무효화. `refresh()` 는 재조회 **전에 pendingWrites 를 await**(안 하면 in-flight 쓰기를 재읽기가 덮음) 후 `assignState.clear()`.
- **Undo**: `scanLog`(세션 메모리, 테이블 없음) — "↩ Undo last scan" + Recent ▾ 최근 5건 개별 취소. 취소는 수량 차감(0 이면 행 삭제), 같은 큐로 저장. 스캔 후 드래그로 옮겨진 항목은 취소 불가 안내.
- **동시 작업 주의**: 서로 다른 박스=다른 행이라 안전. **같은 유닛×같은 라인 동시 스캔은 last-writer-wins**(규칙 27 R1 계열, 절대값 update — 기존 DnD 와 동일 수준).
- 백로그: 박스=오더 하나가 정착되면 **박스 라벨에 스토어명 인쇄** → 프랜차이즈 창고에서 안 열고 재분배 가능.

## 개발 워크플로우
- 환경: WSL2 Ubuntu + bash, 개발 경로 `~/asung/asung-wms` (⚠️ `/mnt/c/...` 금지 — I/O 느림).
- Edge Function 배포: `cd ~/asung/asung-wms && supabase functions deploy hello` (Docker 불필요).
- 함수 호출: `curl -s "$BASE/hello" -H "Authorization: Bearer $ANON" | jq .` — POST 바디는 `--data @file.json`.
- DB 스키마 변경: 마이그레이션만 (`supabase migration new` → `db reset` 검증 → `db push` 는 사람이). SQL Editor 금지 — SKILL.md 「DB 스키마 변경 절차」 참조.
- 집·회사 동등개발: 각 컴퓨터 Supabase CLI + `git clone`. **작업 후 `git push`.** Supabase 클라우드(테이블·데이터·secrets·배포함수)는 어디서든 접근, 로컬 코드만 git 동기화.
- 화면 수정: `/home/claude/<file>` 편집 → 마지막 `<script>` `node -e`로 문법검사 → outputs 복사 → present.
- 영어화 검증: `re.findall(r'[가-힣]+')`로 0 확인(grep -o는 로케일 오탐). ${...} 템플릿 플레이스홀더는 유지.

## 로고
- 흰색만 존재(tools repo `asung-logo-white.png`). 어두운 버전은 PIL로 생성: alpha>0 픽셀 RGB를 (18,22,28)로 recolor → `asung-logo-dark.png`.
- 헤더: `.logo{display:flex;align-items:center;gap:7px}` + `.logo .logo-img{height:15px}`. 런처: `.brand .logo-img{height:38px}`.

## receiver.html (2026-07-23 — 리시빙 화면, requireManager:false)

- **리스트**: PO 바코드 스캔 진입(진행중 receipt 우선 → Cin7 검색 정확일치 시 바로 시작) + "Ready to receive" 섹션 ↻POs / ↻Transfers 온디맨드 버튼. Resume 섹션(in_progress/held/partial). 트랜스퍼 카드 = TRANSFER 태그 + 창고 태그, warehouse_access 필터.
- **검수**: Single(기본)|List 세그 토글 — 픽커 이식(큰 이미지·바코드 블록 base/×factor/ALT-UPC·큰 수량·스테퍼·Enter quantity·Prev/Next·autoAdvance). **Last bin 칩**(추천 빈 미리 표시 — buildBcMap 뒤 wms_sku_bins 독립 enrich). 스캔=bcMap(형제 -12 병합, 픽커 패턴), 초과=confirm 후 허용(over), 미지 바코드=스냅샷 조회(barcode/sku eq → scannable_barcodes contains) → 오프-PO confirm → needs_approval 라인 insert. 홀드=진행 저장.
- **풋어웨이**: Putaway→ 가 추천 빈 자동확정(is_current desc → last_seen desc → available desc, base_sku×warehouse 배치 조회) → 가이드: 빈별 그룹 zone 동선순(zoneSeq), Placed 토글, "Bin needed"(신규 SKU — prompt 스캔/입력), "Off-PO awaiting manager"(차단 표시).
- **완료**: Partial complete(PO 열림) / Complete PO — short/over/미배치/승인대기 요약 confirm. 저장 후 exitToList. ⚠️ **2026-07-27 갱신**: 요약은 메모리가 아니라 `serverChecks()` 서버 재조회, 저장은 `flushUnconfirmed()`+헤더 patch — 아래 「동시 작업」 절.
- startPo 가 source 분기(action=po vs action=transfer), receipt insert 에 source_type. ⚠️ wms_receipts_apply.sql 미실행이면 insert 실패.

## admin.html Receiving 탭 (9탭째, Health 와 Finalized 사이)

- **Off-PO approvals**: needs_approval 라인 테이블, Approve(승인자·시각) / Reject(라인 삭제 + 실물 반품 보류 안내). 탭 배지 = 대기 건수.
- **Apply to Cin7**: completed & applied_at null 인 receipt 만. 버튼 → EF dry-run 계획 → confirm(라인·bin·스킵 사유 표시) → commit=1 → alert 로그(WARN 시 경고). partial/held/in_progress 는 "finish them to apply" 힌트.
- **Apply 버튼 진행 상태 (2026-07-30 — 중복 클릭 차단, 규칙 35 · 규칙 27 R4)**: 모듈 플래그 `applyBusy`(진행 receipt id)·`applyWriting`(commit 구간)·`applyBtnRef`(버튼 노드) + `setApplyBtn`/`syncApplyBusyUI`/`setApplyWriting`. 라벨·색 = `Apply to Cin7`(초록) → `Checking…`/`Applying…`(회색 `.busy`+`.bspin` 스피너·비활성) → `✓ Applied`/`⚠ Partial`(주황 `.warn`)/`Apply failed`(빨강 `.bad`, 5초 뒤 원래 라벨 복구). 진행 중엔 **목록의 다른 Apply 도 비활성** + `#applyBanner`/모달 `#rvApplyNote` 한 줄 안내 + `beforeunload` 경고(commit 구간만). Review 모달 Apply 는 **모달을 열어둔 채** 실행(성공 시 자신이 닫음, Close/backdrop 잠금). ⚠️ 복구는 **try/finally**(취소·예외 포함) — `paintFrame()` 은 alert 전에 버튼을 그리려는 rAF 인데 **백그라운드 탭에서 rAF 가 멈추므로 150ms 타임아웃 필수**(없으면 busy 로 굳는다). ⚠️ 성공 뒤 `loadRecv()` 는 `.catch()` 로 감싼다 — 새로고침 실패를 Apply 실패로 표시하면 이미 반영된 Cin7 을 재클릭하게 만든다.
- **History**: Source(PO/TR)·Cin7(✓ Applied 배지, hover=apply_note)·Delete(PO 번호 타이핑 가드; Applied 후엔 "Cin7 안 되돌아감" 경고). Delete = WMS receipt 통째 삭제(단계 없음, cascade).
- ☰ Menu: wms-auth.js setupNavMenu items 에 ["Receiving","receiver.html",null] (Fulfillment 다음, 전 작업자). index.html 런처 카드 존재.

## receiver.html — 2026-07-24 개선 묶음

- **헤더 순서 규칙**: 유저이름 → ☰ Menu → 🗺 Map → Sign out. **☰ Menu 는 항상 유저이름 바로 옆**(Map/Stock 등보다 먼저). 전 WMS 화면 공통.
- **빈 지정 모달**(assignBin→openBinModal): 스캔(autofocus, Enter 확정)+검색 드롭다운(zone순, 필터). 소스=EF action=bins(빈자리 포함)→wms_sku_bins 폴백. 신규 bin confirm. commitBin: 다른 bin 으로 바뀌면 putaway_done=false. bin 있는 라인엔 "Change" 버튼.
- **정렬**(sortMode: po|zone|product|sku): `orderedIdx()` 가 lines 인덱스만 정렬(배열 불변→bcMap 보존). renderRList/renderSingle/move 는 표시순 따름. Product=product_name A-Z(브랜드 앞이라 자연 브랜드정렬). ⚠️ **2026-07-27 갱신 — `orderedIdx()=sortedIdx(true)` 로 바뀌고 autoAdvance 는 `sortedIdx(false)`**: 아래 「채운 라인 정렬」 절.
- **Zone→Bay 점프**: `.recv-controls`/`.put-controls` 로 스캔+정렬+칩 한 묶음 sticky(top:55px). rZjump/rZjumpBay(검수, Zone정렬시), putZjump/putZjumpBay(풋어웨이, 진행률 포함). zdiv 에 data-zone, lrow 에 data-bay, bin-group 에 data-zone/data-bay 앵커. `bayOfBin()` 규칙은 SKILL 규칙 20 참고.
- **터치 크기**(태블릿 세로): zchip/스테퍼/pk/assign/chgbin ≥40px.
- **딥링크** `?receipt=N`: admin Reopen 진입(init 에서 openReceipt 바로).
- **중복 receipt 방지**: startPo 가 그 PO 의 receipt 전체 조회 → applied 차단 / 미완료 이어받기 / completed 미적용 재개. loadMyReceipts 는 applied_at IS NULL 만. openReceipt 도 applied 차단.

## admin.html — 2026-07-24

- Receiving 탭 **Review 버튼**(reviewReceipt): 읽기전용 bin그룹 요약 모달 + Apply/Reopen/Close. applied 면 Reopen 잠금. Reopen=status→in_progress + receiver.html?receipt=N 이동.
- **Apply 권한**: canApply=(role==admin)||perms.includes("apply"). 버튼/Review모달/함수 3중 게이트.
- **BATCH ACTIVITY presence 기반**: fresh(t)=liveBatchSet().has(batch_label). 🟢active(open on screen)/🟡away(screen closed). 범례도 동일. (heartbeat 제거 — 규칙 22)

## picker.html / packer.html — 2026-07-24 (규칙 22)

- heartbeat 전면 제거(타이머 0). presence 만 유지(LIVE NOW). 
- **스캔 이어받기**: picker `scanTakeover(f)` / packer `scanTakeoverPack(f)` — 스캔한 오더가 남의 in_progress 면 confirm 후 assigned_to=me. 대기목록 순수 pending.
- startHeartbeat/stopHeartbeat/idleMin/staleISO no-op 스텁(잔여 호출 안전).

## 2026-07-25 추가

**receiver.html — 리시빙 리스트 프린트**: 헤더 `#printBtn` → `printReceivingList(win)`. ⚠️ `window.open` 은 **클릭 핸들러 안에서** 먼저 호출(팝업차단 회피 — 규칙: await 뒤 open 은 차단됨). 라스트빈(존) 순 정렬은 `zoneOfBin`/`zOrder` 재사용. jsbarcode CDN 으로 CODE128(문서번호). no-bin 라인은 주황 "no bin". ⚠️ **소스 판정은 `receipt.source_type==="transfer"`** — `wms_receipts` 컬럼명은 `source_type` 이고 `source` 는 **EF 목록 응답 필드**다. 헷갈려 `receipt.source` 를 쓰면 undefined 라 **트랜스퍼가 조용히 "PO" 로 인쇄된다**(2026-07-27 수정).

**manager.html — 픽리스트 Reference**: `pickOrd` 에 `reference:selected.reference` 전달(오더는 `select("*")` 라 컬럼만 있으면 자동), `printPickList` 의 Order 줄 아래 `${ord.reference?...:""}`. **wave 픽리스트(printWaveAll)의 per-order 페이지에도 동일 추가**(`o.reference`). ⚠️ manager.html 은 **CRLF** 줄바꿈 — 파이썬으로 편집할 때 `newline=''` 로 열고 `\r\n` 유지.

**picker.html / packer.html — held_by**: Hold 시 `held_by:me.name` 함께 저장(picker 는 wave/단일 both, wms_waves 도), 목록 select 에 `held_by` 포함, 렌더에서 pool 을 `myHeld`(held_by===me.name, 맨 위 "⏸ Resume your held" 섹션, mode `"held"`) / 나머지로 분리. `batchCardHtml`/`waveCardHtml` 에 `held` 모드(파란 카드 + "⏸ you held this" 태그 + "Resume" 버튼), 클릭은 `else startBatch/startWave` 로 자동 라우팅(pending claim + 보존된 진행분 로드). claim 시 `held_by:null`.

## 2026-07-27 — receiver.html 동시 작업 (규칙 24~27)

한 PO 를 여러 명이 나눠 받는다. **SKILL 규칙 24(저장)·25(id)·26(정렬)·27(미해결 위험)이 근거이고 여기는 구현 지도.**

### 상태 & 저장 엔진 (L1)
```js
const unconfirmed=new Map();  // line.id -> {kind:"qty"|"putaway"|"all"}  미확인 쓰기만
const writeChain =new Map();  // line.id -> Promise  같은 라인 PATCH 추월 방지
let bumpT=null;               // wms_receipts.updated_at debounce (4s)
```
- `markUnconfirmed(l,kind)` / `mergeKind(a,b)`(다른 kind 합쳐지면 `"all"`) / `patchFor(l,kind)` — **패치는 호출 시점 라인 값에서 생성**(큐에 밀린 쓰기가 자동 최신값).
- `writeLine(l,kind)`: `update(patchFor).eq("id",l.id).select("id")` → **`data.length!==1` 은 성공 아님.** 0행이면 `lineGone(id)` 로 분기 → 삭제됨(`dropLine`+토스트) / conflict(unconfirmed 유지). ⚠️ PostgREST 0행 = `error null`/204 이므로 `.select()` 없이는 구분 불가.
- `queueWrite(l,kind)` = `writeChain` 에 라인별 체인. `saveLine(l)`(수량, **await 금지 — 스캔 피드백 앞을 막으면 작업자가 재스캔해 과다 계상**) / `savePutaway(l)`(await, 실패해도 로컬 값 유지) 가 진입점.
- `flushUnconfirmed()` → `{failed,deleted,ok}`. **Hold·partial·complete 세 경로 전부 이걸 쓴다.** ⚠️ 예전의 `for(l of lines) update(...)` 전체 루프는 **삭제됨 — 되살리지 말 것**(함께 받던 사람 작업이 스테일 스냅샷으로 되돌아감).
- `dropLine(id)`: splice + unconfirmed/writeChain 정리 + **커서를 id 로 되짚음**(인덱스로 두면 삭제 라인 위쪽일 때 한 칸 밀림).
- `bumpReceipt()`: 헤더 updated_at debounce(스캔당 요청 2개→1개).

### 완료 요약 (L3)
- `serverChecks()` — `wms_receipt_lines` 를 `receipt_id` 로 재조회 → `{rows,targets,notPlaced,shorts,overs,pendingAppr,unknown}`. `unknown` = 내 `lines` 에 없는 행(남이 추가한 오프-PO).
- `mergeServerRows(rows)` — 서버 값을 화면에 반영. ⚠️ `unconfirmed.has(r.id)` 인 라인은 **건너뜀**(내 값이 더 최신). **값만 갱신, 배열 추가/삭제·재정렬 안 함**(라인 변경은 `offPoScan`/`dropLine` 만).
- `preFinish()` = flush → serverChecks → renderPutaway. `partialBtn`/`completeBtn` 이 이걸 거친 뒤 `summaryText(c)` confirm → `finishReceipt(status)`(flush + 헤더 patch 만). `finishing` 플래그로 이중 클릭 차단.

### presence (L4)
- `presenceKey()` = `me.name+"|receiver:"+receipt.id`, `presenceJoin/presenceLeave/readPresence/othersLabel/renderAlsoHere`. 채널은 picker/packer 와 같은 **`wms-presence`**.
- track 페이로드 = `{name, screen:"receiver", receipt, po, at}`. ⚠️ **`batch` 넣지 말 것** — admin `liveList()` 가 batch 있는 멤버만 워커로 집계하고 Picking/Packing 으로만 표시 → receiver 오표시.
- 배지 = 헤더 `#alsoHere`("🟢 also here: 이름", title 에 설명). `openReceipt` 에서 join, `exitToList` 에서 leave + `unconfirmed/writeChain.clear()`.
- ⚠️ **타이머 없음**(규칙 22). presence sync 이벤트로만 갱신.

### 라인 식별 (규칙 25)
- `lineById(id)` — 스캔·스테퍼·수동입력 전부 id 로 조회. `bcMap[code]=[{id,factor}]`(`buildBcMap` 이 id 로 담고 `!arr.some(c=>c.id===l.id)` 로 중복 방지), `processScan` 은 `bcMap[code].map(c=>lineById(c.id)).filter(...)`.
- ⚠️ **picker.html·packer.html 은 아직 인덱스 기반** — lines 를 splice 하는 기능 추가 전엔 안전, 추가하면 먼저 id 화.

### 채운 라인 정렬 (규칙 26)
- `isFilled(l)= l.expected>0 && l.received===l.expected` — 정렬·색·비프가 같은 기준.
- `sortedIdx(groupFilled)`: 1차 키 `g=(groupFilled&&isFilled(l))?1:0`, 그 뒤 sortMode 키, 마지막 tiebreak `i`(완료 라인끼리 원래 순서 유지).
- `orderedIdx()=sortedIdx(true)` → renderRList(그룹 구분선 `grpOf`)·renderSingle·`move()`·프린트 카운터.
- ⚠️ **`autoAdvance()` 는 `sortedIdx(false)`** — 표시 순서로 걷으면 방금 채운 라인이 내려가 뒤가 비고 매번 리스트 맨 위로 끌려간다(존 동선 파괴).

## 2026-07-28 — picker.html / packer.html 소유권 가드 (규칙 28)

종이 픽리스트가 보드로 돌아갔는데 화면은 열려 있으면 두 사람이 같은 라인에 쓴다. **SKILL 규칙 28 이 근거이고 여기는 구현 지도.** `scanTakeover`/`scanTakeoverPack` 은 **건드리지 않았다**(정당한 이어받기 진입로).

### 가드 엔진 (picker/packer 동형, 각 파일 `markWorkStarted` 바로 뒤)
```js
let frozen=false, lastOwnerCheck=0;
async function checkOwner(){}  // {s:"ok"} | {s:"lost",who} | {s:"unknown"}
async function ensureMine(){}  // true=계속 / false=프리즈됨, 쓰지 말 것
function freezeScreen(who){}   // 입력·버튼 비활성 + 모달 + presenceLeave
async function guardOnReturn(){}
```
- `checkOwner()` = **단일 컬럼 select**. picker 는 `wave ? wms_waves(id=wave.id) : wms_pick_tasks(id=task.id)`, packer 는 `wms_pack_tasks(id=packTask.id)`. `.maybeSingle()`. `who===me.name` 아니면(**null 포함**) lost.
- ⚠️ **catch = `{s:"unknown"}` → 쓰기 진행 + `console.warn` 만.** 네트워크 실패로 작업을 멈추지 않는다(규칙 28 best-effort). **여기서 프리즈로 바꾸지 말 것.**
- `lastOwnerCheck` = 3초 중복조회 억제용 타임스탬프. ⚠️ **setInterval 아님**(규칙 22).
- 이벤트 등록: `document.addEventListener("visibilitychange", …visible → guardOnReturn)` + `window.addEventListener("focus", guardOnReturn)`. 실사고 시나리오(태블릿 두고 나갔다 복귀)를 **첫 스캔 전에** 잡는 경로라 가장 중요.

### 가드가 들어간 지점
| 경로 | picker | packer |
|------|--------|--------|
| 스캔 가산·스테퍼·수동입력 | `saveLine()` 선두 (공통 관문) | `saveLine()` 선두 (공통 관문) |
| Complete | `finish(allowShort)` — confirm 뒤, 라인 루프 앞 | `doneBtn` — Pack fill·Over-scan·short confirm **전부 끝난 뒤**, 라인 루프 앞 |
| Hold | `holdBtn` — confirm 뒤, 라인 루프 앞 | `holdBtn` — confirm 뒤, 라인 루프 앞 |
| 진입 방어 | `processScan`/`manualAdjust`/`manualSet`/`finish`/`holdBtn` 선두 `if(frozen) return` | `processScan`/`manualAdjust`/`manualSetPack`/`doneBtn`/`holdBtn` 선두 |

### 프리즈 (렌더 우회로 없음)
- `#scan.disabled=true` + `blur()`, `holdBtn`/`shortBtn`/`doneBtn` disabled, `focusScan()` 선두 `if(frozen) return`(포커스 되돌리기 정지).
- ⚠️ **핸들러 가드만으로는 부족** — `renderSingle` 의 `[data-step]`·`[data-manual]`, packer `renderList` 의 `.stepmini` 버튼·`Clear over` 에 `${frozen?"disabled":""}`. `freezeScreen` 이 `renderPick()`/`renderPack()` 을 한 번 더 호출해 반영한다.
- 모달 = `#freeze`(`.fz`/`.fzbox` CSS) + `#fzMsg` + `#fzReload`(=`location.reload()`) **버튼 하나만**. 문구: 다른 사람 `This {batch|wave} is now assigned to {who}. Your screen is out of date.` / null `This {batch|wave} was released and is waiting to be claimed.` (picker 는 `ownerUnit()` 이 wave/batch 선택)
- ⚠️⚠️ **`freezeScreen` 에서 로컬 수량을 저장하지 않는다** — 스테일 값이라 이어받은 사람 작업을 덮는다(규칙 24 의 전체배열 덮어쓰기 제거와 같은 이유). 로컬은 버리고 리로드.

## 2026-07-28 — receiver.html 리스트: Resume 중복 카드 숨김

Resume 섹션에 이미 떠 있는 문서가 아래 "Ready to receive (Cin7)" 목록에도 그대로 보여 같은 문서를 두 카드로 눌렀다.

```js
// renderList() — 규칙 24
const shownDocs = new Set(myReceipts.map(r=>String(r.po_number||"").toUpperCase()));
const visPos = openPos.map((p,i)=>({p,i})).filter(({p}) => !shownDocs.has(String(p.po_number||"").toUpperCase()));
```
- 키는 **`po_number` 대문자 비교**(`cin7_purchase_id` 가 아니라 — 트랜스퍼/PO 둘 다 문서번호가 안정적인 표시 키다). 인덱스는 `{p,i}` 로 감싸 **원래 `openPos` 인덱스를 보존**해야 한다(`startPo(+el.dataset.pi)` 가 그 인덱스를 쓴다 — filter 후 재번호를 매기면 엉뚱한 문서로 들어간다).
- 헤더에 `#poHidden` → `— N already open above`(0 이면 숨김).
- 빈 목록 판정도 `visPos` 기준: `lEmpty.style.display=(myReceipts.length||visPos.length)?"none":"block"`.
- ⚠️ **기준은 "화면에 렌더된 `myReceipts`" 뿐이다.** "receipt 행이 존재하면 숨김"으로 바꾸면 창고 접근 밖 등으로 Resume 에 안 뜨는 문서까지 사라져 **스캔 이어받기 진입로가 막힌다.**

## 2026-07-30 — receiver.html 풋어웨이 진입 성능 (규칙 34)

"Putaway →" 가 라인마다 `await queueWrite` 를 직렬로 기다려 **진입 = 라인 수 × RTT** 로 멈추던 것 수정.

- `toPutawayBtn`: 추천 빈 **배치 조회 1회**(유일한 진입 전 await) → 로컬 배정 → **즉시 showPutaway()** → `savePutawayAssigns(toSave)` 백그라운드 저장. `putawayPrep` 재진입 가드 + "Preparing…" 라벨(try/finally 복구).
- `savePutawayAssigns(list)`: 동시 8개 워커 풀로 `queueWrite(l,"putaway")` 소진. 저장 엔진(규칙 24)은 무변경 — 같은 라인 후속 쓰기는 writeChain 이 줄 세움, 실패는 unconfirmed → 완료 flush.
- 계측 `?debug=perf`: `PERF` 플래그 + `perfLog()` — putaway entry / putaway bg saves / renderPutaway / renderRecv 소요와 DOM 노드 수를 콘솔 `[perf]` 로. 평상시 no-op.
- ⚠️ bin 목록은 무혐의(모달 300개 캡, 라인마다 안 그림 — 규칙 34). 앞으로도 라인마다 bin 전체 목록을 그리지 말 것.

## ⬜ admin.html Receiving — 붙일 것 (규칙 30)

- **Apply 대기 항목에 경고 문구** (규칙 30-3): *"Do not move this stock in Cin7 until Apply finishes."* TR-02935 실패의 상당수가 `Available quantity … is 0` = 사람이 이미 옮긴 재고였다. 규칙 28(픽 중복)과 같은 종류이고 상대가 WMS 자신이다.
- **`groups_remaining` 배너** (규칙 30-2): "N groups remaining, press Apply again". ⚠️ 지금 배너는 **EF 의 캡 규칙을 JS 로 중복 계산**한다 — EF 응답 필드를 그대로 표시하도록 바꿀 것(드리프트 위험).
- **`failed_moves(N):` 정규식 파싱** — EF 와 admin.html 이 같은 포맷을 각자 파싱한다. `wms_receipts` 컬럼(예 `failed_move_count`)으로 승격하는 게 맞다 — 백로그.
