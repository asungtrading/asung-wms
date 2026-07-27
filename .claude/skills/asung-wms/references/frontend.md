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
- **리포트 버튼**: picker ⚑Wrong location/⚑Barcode changed, packer ⚑Barcode changed → `wms_reports` insert.
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
| manager | true |
| admin | true |
| staff-admin | true |

## 런처 role 메뉴 필터
- worker: Picking / Packing / Fulfillment
- manager: perms에 있는 것만(split=Order Splitting, admin=Admin, staff=Staff) / admin: 전부
- 구현: 매니저 카드에 class `mgr-only`(CSS `display:none`) + `data-perm`, 로그인 후 admin이거나 매니저 perms 포함 카드만 `classList.remove("mgr-only")`. ⚠️ `style.display=""`는 CSS 때문에 안 먹음 → classList.remove.

## admin 탭 (8탭, 2026-07-22)
Status(카드+In-Progress+**Finalized 섹션**) / Discrepancy / **Reports**(wms_reports 리뷰·resolve, 배지) / Stats(작업자 처리량+**평균 소요시간**+실수) / Rollback(단계 되돌리기+로그) / **Finalized**(옛 Packing Lists — 완료오더 기간목록, Fulfillment mix 카드, 🖨Print·⬇PDF·⬇CSV / direct는 "Direct pack" 태그) / Work Screens / **Health**(Rollback 뒤 위치).
- ⚠️ 탭 전환 핸들러가 각 loadXxx 호출. periodBar `custom` 인자는 반드시 객체 `{from,to}`(null이면 TypeError로 boot 중단).
- **팩킹리스트 PDF/CSV**: `getPackingData(oid)` 공용 → HTML(print)·jsPDF+autotable(PDF, CDN lazy-load, 로고=canvas dataURL)·CSV(BOM+CRLF). 컬럼 SKU·Barcode·Product·Qty.
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
- 팩킹리스트 2종: (a)유닛별 (b)스토어별 종합(각 스토어 1페이지 page-break, 그 스토어 물건이 어느 팔렛/박스에 얼마나 + ⚠️미배정 경고).

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
- **완료**: Partial complete(PO 열림) / Complete PO — short/over/미배치/승인대기 요약 confirm. 저장 후 exitToList.
- startPo 가 source 분기(action=po vs action=transfer), receipt insert 에 source_type. ⚠️ wms_receipts_apply.sql 미실행이면 insert 실패.

## admin.html Receiving 탭 (9탭째, Health 와 Finalized 사이)

- **Off-PO approvals**: needs_approval 라인 테이블, Approve(승인자·시각) / Reject(라인 삭제 + 실물 반품 보류 안내). 탭 배지 = 대기 건수.
- **Apply to Cin7**: completed & applied_at null 인 receipt 만. 버튼 → EF dry-run 계획 → confirm(라인·bin·스킵 사유 표시) → commit=1 → alert 로그(WARN 시 경고). partial/held/in_progress 는 "finish them to apply" 힌트.
- **History**: Source(PO/TR)·Cin7(✓ Applied 배지, hover=apply_note)·Delete(PO 번호 타이핑 가드; Applied 후엔 "Cin7 안 되돌아감" 경고). Delete = WMS receipt 통째 삭제(단계 없음, cascade).
- ☰ Menu: wms-auth.js setupNavMenu items 에 ["Receiving","receiver.html",null] (Fulfillment 다음, 전 작업자). index.html 런처 카드 존재.

## receiver.html — 2026-07-24 개선 묶음

- **헤더 순서 규칙**: 유저이름 → ☰ Menu → 🗺 Map → Sign out. **☰ Menu 는 항상 유저이름 바로 옆**(Map/Stock 등보다 먼저). 전 WMS 화면 공통.
- **빈 지정 모달**(assignBin→openBinModal): 스캔(autofocus, Enter 확정)+검색 드롭다운(zone순, 필터). 소스=EF action=bins(빈자리 포함)→wms_sku_bins 폴백. 신규 bin confirm. commitBin: 다른 bin 으로 바뀌면 putaway_done=false. bin 있는 라인엔 "Change" 버튼.
- **정렬**(sortMode: po|zone|product|sku): `orderedIdx()` 가 lines 인덱스만 정렬(배열 불변→bcMap 보존). renderRList/renderSingle/move/autoAdvance 모두 표시순 따름. Product=product_name A-Z(브랜드 앞이라 자연 브랜드정렬).
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

**receiver.html — 리시빙 리스트 프린트**: 헤더 `#printBtn` → `printReceivingList(win)`. ⚠️ `window.open` 은 **클릭 핸들러 안에서** 먼저 호출(팝업차단 회피 — 규칙: await 뒤 open 은 차단됨). 라스트빈(존) 순 정렬은 `zoneOfBin`/`zOrder` 재사용. jsbarcode CDN 으로 CODE128(문서번호). no-bin 라인은 주황 "no bin".

**manager.html — 픽리스트 Reference**: `pickOrd` 에 `reference:selected.reference` 전달(오더는 `select("*")` 라 컬럼만 있으면 자동), `printPickList` 의 Order 줄 아래 `${ord.reference?...:""}`. **wave 픽리스트(printWaveAll)의 per-order 페이지에도 동일 추가**(`o.reference`). ⚠️ manager.html 은 **CRLF** 줄바꿈 — 파이썬으로 편집할 때 `newline=''` 로 열고 `\r\n` 유지.

**picker.html / packer.html — held_by**: Hold 시 `held_by:me.name` 함께 저장(picker 는 wave/단일 both, wms_waves 도), 목록 select 에 `held_by` 포함, 렌더에서 pool 을 `myHeld`(held_by===me.name, 맨 위 "⏸ Resume your held" 섹션, mode `"held"`) / 나머지로 분리. `batchCardHtml`/`waveCardHtml` 에 `held` 모드(파란 카드 + "⏸ you held this" 태그 + "Resume" 버튼), 클릭은 `else startBatch/startWave` 로 자동 라우팅(pending claim + 보존된 진행분 로드). claim 시 `held_by:null`.
