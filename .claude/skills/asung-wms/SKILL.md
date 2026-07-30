---
name: asung-wms
description: >
  Asung Trading 커스텀 WMS(IMS 첫 모듈)를 다룰 때 반드시 먼저 읽으세요.
  Supabase(Postgres+Edge Function) 기반, Cin7 multi-packing 한계를 넘는
  대형오더 분할 동시 픽/팩 + 리시빙/풋어웨이.
  "WMS", "픽킹", "패킹", "Supabase", "Edge Function", "wms_orders",
  "Release to WMS", "오더 분할", "discrepancy", "base 정규화", "factor",
  "wms-auth", "perms", "wms.asung.ca", "Finalize", "Health 탭", "리시빙",
  "receiver.html", "풋어웨이", "라스트 로케이션", "wms_receipts", "Apply to Cin7",
  "stock received", "bin transfer", "트랜스퍼", "Invoice First", "스캔 이어받기",
  "Lines is invalid", "authorize", "held_by", "동시 작업", "unconfirmed",
  "writeChain", "presence", "serverChecks", "bcMap", "CAS", "on_conflict",
  "exported_base", "재평가" 등이 나오면 추측하지 말고
  이 스킬의 아키텍처·스키마·인증·배포·규칙 20~33 을 먼저 확인하세요. 특히 ⚠️Order_Progress=AdditionalAttribute1(백오더 공유),
  ⚠️bin은 base_sku 기준, ⚠️Cin7 쓰기 bin은 GUID(이름은 400),
  ⚠️PO는 Invoice First 선승인, ⚠️factor는 unit 컬럼, ⚠️service_role 금지, ⚠️UI 영어,
  ⚠️stock received는 문서당 bin 1개·authorize는 POST,
  ⚠️리시빙 저장은 라인 단위(전체 덮어쓰기 금지)·성공 판정은 .select() 1행 —
  어기면 재고·픽 수량·Cin7 반영이 틀어지거나 남의 작업이 사라집니다.
---

# Asung Trading WMS 스킬

Asung은 Cin7 Core를 장기적으로 대체할 커스텀 IMS를 짓고 있고, **WMS가 그 첫 모듈**입니다. 이 문서는 "우리가 WMS를 짓는 방식"을 인코딩합니다. 세부 스키마·코드는 `references/`에 있으니 필요할 때 읽으세요.

## 왜 만드나 (스코프의 근거)

Cin7 Core는 multi-picking은 되지만 **multi-packing이 사실상 안 됩니다** — 모든 픽이 끝나야 팩을 시작할 수 있습니다. 라인 최대 ~1000개짜리 대형오더를 여러 작업자가 **나눠서 동시에 픽/팩**하려는 것이 이 WMS의 목적입니다. 완료된 픽 배치는 다른 배치와 무관하게 독립적으로 팩됩니다.

반대 방향도 있습니다: **소량 오더 여럿을 한 작업자가 한 동선으로 묶어 픽**하는 것(cluster/batch picking). 이건 **wave(웨이브)** 로 처리하며 — 핵심은 "대형 오더는 쪼개고(split), 소량 오더는 묶는다(wave)"입니다. 둘 다 결국 **같은 pick 배치 출구 하나**로 수렴하게 설계됨(규칙 18).

## 확정된 아키텍처 (⚠️ 바꾸기 전 반드시 이해)

```
Cin7 Core ──(폴링)──> Supabase Edge Function ──> Supabase Postgres(RLS ON)
                            │                          ↑   ↑
   BQ 마스터 ──(GAS 복제)──> Supabase 복제테이블 ───────┘   │
                                                            │
브라우저 6화면 + 런처 (GitHub Pages, wms.asung.ca)          │
  wms-config.js(anon key) + wms-auth.js(로그인) ──(anon)────┘
  직원 로그인 → wms_staff role → 화면 접근/메뉴 필터
```

- **Edge Function은 BQ에 직접 안 붙습니다.** 조직정책 `iam.disableServiceAccountKeyCreation`이 서비스계정 JSON 키 생성을 차단(Google Secure by Default)했기 때문. Workload Identity는 과함. → **제3의 길**: GAS가 BQ 마스터를 Supabase로 복제하고, Edge Function은 Cin7 읽기 + Supabase 조인만. BQ 인증 관문 자체가 소멸.
- **WMS는 Cin7에 쓰지 않습니다(MVP).** 작업 완료 시 담당자에게 알림만 → 담당자가 Cin7에서 pack authorize → Cin7 automation('pack is authorized' 이벤트)이 Order_Progress를 `3.Finalized`로 전환 + 재고차감. 즉 재고 무결성은 Cin7이 지키고 WMS는 안 씀.
- **WMS가 소유하는 단계는 Cin7 Order_Progress = `2.Release to WMS` 하나뿐.** 흐름: `1.New`(오더생성) → 매니저 authorize → `2.Release to WMS`(수동) → [우리 WMS: 분할·분배·병렬 픽/팩] → `3.Finalized`(Cin7 automation 자동전환).
- **프론트엔드는 순수 HTML/JS + Supabase JS CDN.** 빌드툴 없음. GitHub Pages(public repo)로 `wms.asung.ca`에 배포. 스캔 = Bluetooth HID(키보드처럼 입력+Enter).

## 환경 상수

| 항목 | 값 |
|------|-----|
| Supabase 프로젝트 | `asung-WMS` (org: Asung Trading, Free) |
| Supabase URL | `https://gftpcnkxbdjzzfvzwcfl.supabase.co` |
| project-ref | `gftpcnkxbdjzzfvzwcfl` |
| region | `ca-central-1` (캐나다) |
| 로컬 개발폴더 | `~/asung/asung-wms` (WSL2 Ubuntu). 집·회사 동일 세팅. ⚠️ `/mnt/c/...` 아래에서 작업 금지 — WSL 파일 I/O가 크게 느려짐 |
| GitHub | `asungtrading/asung-wms` — ⚠️ **PUBLIC** (Pages 무료 배포 위해 전환) |
| 배포 URL | `https://wms.asung.ca` (커스텀 도메인, DNS CNAME→asungtrading.github.io) |
| BQ Project | `geometric-rock-487814-k4` |
| Cin7 API Base | `https://inventory.dearsystems.com/ExternalApi/v2` |

Cin7 키는 **양쪽에** 등록됨(별개 저장소): GAS Script Properties(`CIN7_ACCOUNT_ID`/`CIN7_APPLICATION_KEY`) + Supabase secrets(동일 이름). `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`는 Edge Function에 **자동 주입**(별도 등록 불필요). GAS가 Supabase에 쓸 땐 GAS Script Property의 `SUPABASE_URL`/`SUPABASE_SERVICE_KEY` 사용.

**⚠️ 비밀값 규칙 (매우 중요):**
- **anon(publishable) key = 커밋/공개 OK.** RLS + 로그인이 데이터를 보호하므로 `wms-config.js`에 넣어 public repo에 올려도 안전. 브라우저에 어차피 노출되는 값.
- **service_role key = 절대 금지.** GAS Script Property + Supabase Edge Function 자동주입에만 존재. 코드·커밋·스킬·스크린샷에 절대 안 넣음.
- Cin7 키를 `supabase secrets set`으로 넣을 때 터미널 화면·셸 히스토리에 값이 남으므로, 민감 시 rotate 권장(그럼 GAS+Supabase 양쪽 갱신).

**저장소에 있어야 하는 파일 (루트, 모두 같은 폴더):**
7개 화면 + 공유 2개 + 로고 2개 + 배포 파일.
- 화면: `index.html`(런처) `picker.html` `packer.html` `manager.html` `admin.html` `staff-admin.html` `fulfillment.html`
- 공유: `wms-config.js`(anon key — ⚠️실제 key 든 버전 유지, 덮어쓰지 말 것) `wms-auth.js`(로그인 모듈)
- 로고: `asung-logo-white.png`(런처=어두운 테마용) `asung-logo-dark.png`(6화면=밝은 헤더용, 흰로고 RGB를 잉크색으로 recolor해 생성)
- 배포: `CNAME`(내용 `wms.asung.ca`, 건드리지 말 것) `.nojekyll`(Jekyll 빌드 스킵 — supabase/·.vscode/ 폴더 때문에 필수)
- ⚠️ `tools.asung.ca`(customer-portal, 별도 repo `asungtrading/tools`)는 반드시 PUBLIC 유지(private면 무료 Pages 죽음).

## DB 스키마 변경 절차 (⚠️ 2026-07-26 확립 — 이 문서 전체에 우선)

**베이스라인 = `supabase/migrations/20260101000000_baseline.sql`** (테이블 20 · 정책 22). 원격 히스토리와 정렬됨(`migration repair` 완료). **이 파일은 수정하지 말 것** — 변경은 항상 새 마이그레이션으로.

허용된 절차:
1. `supabase migration new <name>`
2. 생성된 파일에 SQL 작성
3. `supabase db reset` — 로컬에서 처음부터 재생해 검증
4. `supabase db push` — ⚠️ **사람이 직접만 실행. Claude 는 명령만 제시한다.**

금지:
- **대시보드 SQL Editor 로 스키마 변경** — 로컬과 원격이 어긋나 이 체계가 무의미해진다. 급히 했다면 즉시 `supabase db dump --linked` 로 되받아 반영.
- `supabase db push` 자동 실행
- `supabase stop --no-backup` (로컬 볼륨 삭제)
- `db pull` 의존 — 이 프로젝트에서 diff 단계가 조용히 실패한 이력이 있다. `db dump --linked` 를 쓴다.

드리프트 확인 `supabase db diff --linked` · 작업 후 `supabase stop`(개발 머신 RAM 8GB 상한).

⚠️ **dump 에 안 잡히는 것** — pg_cron 스케줄(`supabase/ops/cron.sql` 에 기록만, 마이그레이션 아님) · Edge Function secrets · Auth 설정(Site URL / Redirect) · Storage 버킷 설정.

⚠️ **이 문서 곳곳의 `wms_*.sql` 파일 이름은 역사적 기록**(`wms_waves.sql`·`wms_receipts.sql`·`wms_healthcheck.sql` 등). 그 파일들은 repo 에 더 이상 없고 내용은 전부 baseline 에 흡수됐다. **다시 실행하지 말 것** — 스키마 계보를 볼 땐 baseline 을 읽는다.

---

## 규칙 1 — Cin7 오더 구조 (실측 확정, 추측 금지)

- **Order_Progress = `AdditionalAttributes.AdditionalAttribute1`** ⚠️ 백오더 `'Backordered'`와 **같은 필드를 공유**. 진행단계일 땐 `'2.Release to WMS'`/`'5.Fulfilled'` 등이 들어감.
- **saleList는 AdditionalAttributes를 안 줌** → 반드시 `/sale` 상세로 확인.
- **AUTHORISED에 여러 진행단계가 혼재**(Fulfilled/Packed도 AUTHORISED) → saleList로 후보 좁힌 뒤 상세에서 `AdditionalAttribute1='2.Release to WMS'`만 필터 필수.
- `/sale` 상세 최상위: `AdditionalAttributes`(객체) / `Location`(창고명 문자열) / `Order`(라인) / `Fulfilments` / `Status`(='ORDERED'). ⚠️ `OrderStatus`·`OrderLocationID`는 상세엔 없음(saleList에만).
- 라인 = `Order.Lines[]`, 필드: `SKU`/`Name`/`Quantity`/`Price`/`AverageCost`/`BackorderQuantity`/`ProductWeight`.
- Cin7 헤더: `api-auth-accountid` / `api-auth-applicationkey`.

## 규칙 2 — warehouse 정규화

```
Cin7 Location에 "Edmonton" 포함  → 'edmonton'
그 외 ("Asung Trading Inc." 등)   → 'toronto'
```
"Edmonton 포함 여부"로 판정(Toronto 문자열이 뭐든 안전). 오더 유입(Edge Function)과 bin 동기화(GAS) **양쪽에 동일 적용**해야 매칭됨.

## 규칙 3 — base 정규화 & factor (⚠️ 재고 수량의 핵심)

Cin7 UOM: 재고는 대부분 **낱개(base=EA)**로 추적, 판매단위는 제품마다 다름. 판매단위는 SKU 형태로 판별 불가 — Cin7 `Sellable` 필드(=`is_selling`)가 유일한 진실. 오더 라인엔 `is_selling=Yes` SKU만 옴.

- **factor 소스 = `asung_product_master.unit` 컬럼** (base='EA'→1, 변형=숫자 12/48/240…). ⚠️ **접미사 아닌 unit 값을 신뢰**(ALT-UPC·PIN-1/-2처럼 접미사가 factor 아닌 케이스 존재. 검증: 변형 6,270행 중 오염 0.05%).
- **정규화**: `required_base(낱개) = ordered_qty × factor`. factor = 오더SKU가 변형이면 그 unit, base면 1.
- **⚠️ bin 조회는 order_sku가 아닌 `base_sku` 기준**. 재고는 낱개(base)로 쌓이므로 변형 오더도 base 위치에서 픽.
- 무결성 가드: 라인에 `is_selling=false`면 플래그(오더에 온 것 자체가 이상).

## 규칙 4 — 바코드 스캔 3-tier & scannable_barcodes

픽커 스캔 fallback: ①변형 바코드(+factor) ②base 바코드(+1) ③수동입력(+flag). `verification_method` 추적: `scanned_variant`/`scanned_base`/`manual`. 커버리지: 변형 78%·base 98.5%(base 없는 137개는 완전수동).

`wms_sku_snapshot.scannable_barcodes`(jsonb `[{barcode,factor,type}]`)를 GAS가 조립: 자기 바코드 + base 바코드 + **ALT-UPC 별칭**(하나의 SKU에 바코드 여러개 담는 레코드, `%-ALT-UPC`). ALT-UPC를 base에 묶는 로직은 `Binstockdata.gs`의 products.json 생성부(base 첫하이픈앞 매칭 + LIKE)를 재사용.

## 규칙 5 — zone 파싱 & 동선

- **edmonton bin = `E`+zone문자 체계**(`isEdmontonCode=/^E[A-Z]/`). zone = bin[1] (E 다음 글자). 예: `EU020303`→U, `EZ010101`→Z, `ED020101`→D.
- **toronto bin = zone이 첫 글자**.
- 동선 순서는 `wms_zone_sequence`(WarehouseMap `toronto.zpos`/`edmonton.zpos` 좌표 기반 초안). 사용자가 UPDATE로 zone별 조정. 좌표(center_x/y)도 저장돼 나중 경로 최적화·시각화 확장 가능.
- 좌표 기준 초안 순서 — toronto: D-C-A-Z-B-E-G-J-H-R-F-W-K / edmonton: F-E-D-C-B-A-U-Z-G-I.

## 규칙 6 — 마스터 복제 동기화 (길 A: 테이블 고정 + 데이터 통짜교체)

`WmsSync.gs`(System_Automation)의 `runWmsMasterSync()`가 BQ 3테이블을 조인→Supabase 2테이블 **truncate + 재적재**(PostgREST delete-all + 500개씩 배치 insert). 트리거 `setupWmsSyncTrigger()`=매일 6:30.

- **길 A 이유**: PostgREST는 행 삽입만 되고 DDL(CREATE TABLE) 불가. 그래서 테이블 구조는 **마이그레이션으로 미리 고정 생성**(baseline 에 포함됨), GAS는 데이터만 교체. "BQ가 진실, Supabase는 최신 복사본"은 그대로 달성. ⚠️ 여기서 "미리 생성"은 **SQL Editor 가 아니라 마이그레이션** — 위 「DB 스키마 변경 절차」 참조.
- **스키마 드리프트 대응**: WMS 스냅샷은 master에서 4개만 씀(product_name·barcode·unit=factor·is_selling). BQ에 무관한 컬럼이 생겨도 **아무것도 안 함**. WMS에서 쓰고 싶을 때만 의식적 3줄(**새 마이그레이션의 ALTER** + GAS SELECT + 프론트).
- **복제 소스 3개**: (1)`Cin7_Master_Data.asung_product_master` (2)`Cin7_Master_Data.asung_bin_stock`(grain sku×wh×bin, sticky=재고0도 is_current=FALSE 자리보존, Binstockdata.gs 관리) (3)`Cin7_Sales_Data.asung_product_images`(sku→image_url, customer-portal·warehousemap 동일소스).

## 규칙 8 — 인증 & RLS (⚠️ 2026-07-19 도입)

- **개인 계정 방식**(공용 계정 아님). 직원마다 본인 이메일/비번. Supabase Auth에 20명 계정 생성됨(dashboard Add user + 임시비번 + Auto Confirm). 임시비번은 Caleb이 배포, 각자 앱에서 변경.
- **`wms_staff` 테이블이 권한의 진실.** 로그인 → auth 이메일로 `wms_staff` 행 조회(email unique) → 그 행의 `role`(worker/manager/admin) 사용. **이름↔이메일은 이미 매칭됨** — 이름에 준 권한 = 이메일에 연결된 권한. 따로 이메일에 권한 안 줘도 됨.
- **`wms-auth.js` = 공유 로그인 모듈.** 각 화면이 `wmsAuth.start({requireManager:bool}, (sb,me)=>{...})` 호출. 이메일/비번 `signInWithPassword`, 세션 자동 유지(localStorage — 진짜 브라우저라 동작, Claude.ai 아티팩트 아님). `wms_staff` maybeSingle로 신원 확인. requireManager=true면 worker 차단. 로그인 화면·"Forgot password"(resetPasswordForEmail)·로그인 후 #logoutBtn 옆 "Change Password" 자동삽입 다 포함.
- **화면별 requireManager**: picker/packer/**fulfillment=false(작업자 화면!)**, manager/admin/staff-admin=true.
- **런처(index.html) 로그인 게이트**: 로그인 전 오버레이만, 로그인 후 role 따라 메뉴 필터(worker=Picking/Packing/Fulfillment만, mgr/admin=+Order Splitting/Admin/Staff). ⚠️ role 필터는 `classList.remove("mgr-only")`로(‌CSS `.mgr-only{display:none}` 때문에 `style.display=""`는 안 먹음).
- **RLS ON**: wms_ 테이블 전부(신규 `wms_waves` 포함) `rowsecurity=true` + 정책 `auth_all`(`for all to authenticated using(true) with check(true)`). anon 거부, authenticated 전체허용. service_role은 RLS 우회(GAS 동기화가 RLS 켜진 뒤에도 작동하는 이유 = 설계 증명). `wms_health_check()`는 `security definer`. 세분화(직원 쓰기/불일치 해소=매니저만)는 백로그.
- **⚠️ 비번 재설정 이메일 링크**: Supabase Authentication→URL Configuration의 Site URL=`https://wms.asung.ca` + Redirect URLs=`https://wms.asung.ca/*` 설정해야 링크가 맞음(안 하면 localhost:3000으로 감). 배포 후 필수 설정.

## 규칙 9 — 프론트엔드 7화면 (순수 HTML/JS + Supabase CDN)

각 화면 `<head>`에 `wms-config.js` → `supabase CDN(@supabase/supabase-js@2)` → `wms-auth.js` 순 로드. 헤더에 로고+화면명, `me.name` 표시, ☰ Menu(드롭다운 내비)·Change Password·#logoutBtn.

**⚠️ 2026-07-21 세션에서 대량 추가됨 (아래 규칙 12~16 + references/frontend.md 참조).**

1. **index.html(런처)** — 다크테마, 로그인 게이트, role별 메뉴 카드. ⚠️ 메뉴 카드 클래스 `.card`가 `display:flex` → wms-auth 로그인 카드도 `card`면 충돌. **로그인 카드는 `wcard`로 격리됨**(교훈: 공유 모듈 클래스는 페이지와 안 겹치게).
2. **picker.html** — 셀프서브 픽킹, 낙관적 잠금, 홀드/재개, 스캔=factor 증가, WebAudio 삐+진동+플래시, 부족→"Complete as incomplete"→discrepancy.
3. **packer.html** — 전량 재스캔 검수, 목표=required(주문량) not expected(픽량), 팩커 부족분 보충("Pack fill"), 초과스캔 소프트경고+완료시 1회 확인(진짜 초과→discrepancy responsible=picker+반납, 스캔실수→무시), 회수된 부족→픽 discrepancy 해소, 전배치 팩완료→order status='ready_to_close'+알림.
4. **manager.html** — 오더 분할 + wave. **Split | Group 토글**. Split=하이브리드 분할(라인 한도 or 낱개 한도 먼저 걸리는 쪽, 동선순 정렬, 1라인=1배치 최소보장, 미리보기=생성 일치). Group=소량 오더 wave 그룹핑(규칙 18).
5. **admin.html** — 매니저 허브 **8탭**(Status/Discrepancy/Reports/Stats/Rollback/Finalized/Work Screens + **Health**), 기간필터+달력. 불일치 "Fixed in Cin7" 처리(사람이 Cin7 backend 수정 후). Health=불변식 검증 탭(규칙 19).
6. **staff-admin.html** — 20명 직원 목록, 인라인 창고/역할 드롭다운(변경즉시저장), active토글, 추가/삭제. **여기서 4명(Ho Kang·Ted Shin·Changmo Ku·Jan Ko)을 manager로 설정** → 그래야 그들에게 매니저 메뉴 보임.
7. **fulfillment.html** — 팔레타이징+팩킹리스트. **멀티오더**(고객별 그룹 체크리스트→여러 오더 동시), 오더→배치 2단 그룹 드래그, 부분수량 모달, 박스→팔렛 중첩, 혼합 팔렛 오더별 추적. **프랜차이즈**(여러 고객 혼합 허용, "N customers mixed" 경고만). **팩킹리스트 2종**: 유닛별 / **스토어별 종합**(각 스토어 1페이지, 그 스토어 물건이 어느 팔렛·박스에 있는지 + ⚠️미배정 경고). requireManager=false. **스캔 배정**(2026-07-29, 세 번째 입력 수단): 유닛 탭=타깃 → 상품 스캔 배정 — Scan qty|Move all 토글, 오더 귀속 3단(1오더 자동/유닛 내 오더 자동/모달), 박스=오더 하나 원칙(혼합 가드 `New box for …` + `⚠ N orders mixed` 배지), Undo 5건, 낙관적 렌더+저장 실패 롤백 — 상세는 `references/frontend.md` 「스캔 배정」.

## 규칙 10 — GitHub Pages 배포

- **Source**: Deploy from a branch, `main`/`(root)`. 파일은 전부 repo **루트**(web/ 폴더 아님) → URL 짧게(`wms.asung.ca/picker.html`).
- **`.nojekyll` 루트에 필수** — `supabase/`(.ts)·`.vscode/` 때문에 Jekyll 빌드가 실패함. 없으면 3~4분 돌다 실패(빨간 X). 있으면 스킵하고 성공.
- **"Startup failure"(0초, Total duration `-`)는 우리 잘못 아님** = GitHub Actions 인프라 장애(githubstatus.com 확인). 파일 문제면 "빌드 후 실패"지 "시작 실패" 아님. → 복구 대기 후 Re-run/재커밋.
- **커스텀 도메인**: Settings→Pages Custom domain `wms.asung.ca`, DNS CNAME `wms`→`asungtrading.github.io`. Pages 열 때마다 "DNS Check in Progress"→"successful"은 정상(매번 실시간 재확인). Enforce HTTPS 체크.
- 순서: Pages Source 저장(배포 살리기) → 성공 확인(github.io 기본주소) → Custom domain 저장. **도메인보다 배포를 먼저.**

## 규칙 11 — UI 영어화 & 로고

- **모든 화면 UI는 영어**(픽커 중 한국어 못 읽는 사람 있음). 개발자 주석도 영어로 정리됨. 용어 통일: Picking/Packing/Fulfillment/Order Splitting/Staff Management/My In Progress/Waiting Batches/Hold/Complete as incomplete/Pack fill/Over-scan/discrepancy/Short/Over/Recovered/Needs review/Toronto/Edmonton/Sign out.
- **로고**: 런처=흰색(`asung-logo-white.png`, tools repo에서 가져옴), 6화면=어두운색(`asung-logo-dark.png`, 흰로고 alpha 유지+RGB를 #12161c로 recolor해 PIL로 생성). 헤더 `.logo{display:flex;align-items:center;gap:7px}` + `.logo .logo-img{height:15px}`, 런처 `.brand .logo-img{height:38px}`.
- 새 화면 만들 때 번역 방식: python 정규식으로 한국어 런 추출→긴 것부터 dict 치환→`re.findall(r'[가-힣]+')`로 0 확인→마지막 `<script>` `node -e`로 문법검사. `grep -o '[가-힣]'` 카운트는 로케일 오탐이니 Python으로 검증.

## 규칙 12 — 자동 폴링 & Cin7 병행운영 (⚠️ 2026-07-21)

- **자동 유입 = pg_cron + pg_net.** `wms_schedule_polling.sql`로 잡 `wms-poll-orders` 등록(`*/5 * * * *`, Edge Function `?commit=1` anon Bearer 호출). 확인: `select * from cron.job;`, 실행이력 `cron.job_run_details`, 응답 `net._http_response`.
- **⚠️ pg_net 응답이 null로 남을 수 있음** — 확대폴링이 상세조회 여럿 돌면 pg_net 기본 타임아웃(~5초) 초과. **응답 수신 실패 ≠ 저장 실패.** 진짜 확인은 **`wms_orders` 테이블의 `imported_at`** (진실). net._http_response는 참고용.
- **확대 폴링**: saleList AUTHORISED 페이지네이션(POLL_LIMIT 100 × POLL_MAX_PAGES 3=300스캔), SKIP_PICKED(CombinedPickingStatus='PICKED' 제외), **상세조회 전 dedup**(existingSaleIds), MAX_DETAIL 60캡. dry-run 진단필드: `pages_scanned/candidates/after_skip_picked/already_exists/fresh_candidates/detail_fetched/would_insert`. ⚠️ 이 필드들이 응답에 **없으면 옛날(50건 1페이지) 버전** — 확대판 재배포 필요.
- **⚠️ Cin7 병행운영 3케이스**: (A) 유입 전 `2.Release to WMS`→`3.Finalized` 등으로 바뀌면 → 유입 안 됨(정상). (B) Cin7에서 픽됨(PICKED) → SKIP_PICKED로 제외(두 시스템 동시작업 방지, 의도됨 — "안 들어온다"의 최빈 원인). (C) **유입 후 Cin7에서 바뀜 → WMS는 모름**(dedup으로 재조회 안 함). 병행 테스트 중 위험. 자동감지(pending/picking 오더 재확인 → needs_review/voided)는 백로그.

## 규칙 13 — Finalize 완료흐름 & 통계 (⚠️ 2026-07-21)

- **fulfillment "✓ Finalize order(s)" 버튼** — 팔렛/박스 유무 무관하게 완료 가능(픽업·즉시출고 대응). 판정: 그 오더 품목이 pallet_items에 하나라도 있으면 `packing_list`, 없으면 `direct`.
- **⚠️ 저장 status 값은 `closed` 그대로, 화면 표시만 "Finalized".** status가 enum일 수 있어 `finalized` 문자값을 직접 넣으면 제약위반 위험 → 표시만 바꿈(STATUS_LABEL.closed="Finalized"). loadOrders는 `closed` 제외.
- **통계 컬럼**(`wms_fulfillment_stats.sql`): `fulfillment_type`(packing_list/direct)·`finalized_by`·`finalized_at`. Finalize 시 기록(컬럼 없으면 status만 저장하는 폴백 포함).
- admin **Status 탭에 Finalized 섹션·카드**(closed 최근 40 — finalize 오더가 진행중 목록에서 빠져 안 보이던 문제 해결).

## 규칙 14 — 워커 리포트 & 롤백 (⚠️ 2026-07-21)

- **`wms_reports`**(별도 테이블, `wms_reports.sql`): 데이터품질 리포트 전용 — discrepancy(재고수량) 큐와 분리. kind=`wrong_location`(picker만)/`barcode_mismatch`(picker+packer)/**`image_mismatch`(picker+packer, 2026-07-30)**. picker 싱글뷰 ⚑Wrong location/⚑Barcode changed/⚑Image differs, packer 싱글뷰 ⚑Barcode changed/⚑Image differs. admin **Reports 탭**에서 리뷰/resolve(kind 필터 + open 건수), 미해결 배지(kind 무관 전체 집계).
- **`image_mismatch` 는 토글**(2026-07-30): 상세 프롬프트 없이 체크만 — note 는 코드가 고정 문구(`Image does not match the physical product`)로 생성. 같은 **order_id+sku+kind 의 미해결(resolved_at is null) 행 1개**가 불변식이고, 다시 누르면 그 행을 **delete**(⚠️ `.is("resolved_at",null)` 조건 필수 — 해소된 감사기록은 지우지 않는다). 진입 시 `loadImageFlags()` 가 미해결 행을 읽어 눌린 상태를 복원한다(⚠️ 상태를 localStorage 에 두지 말 것 — 규칙 5, 태블릿 교체 시나리오). 쓰기 중 `imgBusy` 로 버튼 비활성 = 연타 중복 insert 방지.
  - ⚠️ **wave 모드의 귀속**: picker 는 `wave? l._orderId : task.order_id` — finish() discrepancy 와 같은 규칙(규칙 18). 기존 두 kind 는 `task.order_id` 고정이라 wave 에서 부정확하지만 **동작 변경 금지 대상이라 그대로 뒀다**(백로그).
  - ⚠️ `kind` 는 baseline 에서 CHECK 없는 `text` → **스키마 변경 불필요**. 실물 확인은 `supabase/wms_reports_image_mismatch.sql` STEP 1(규칙 29 — 문서 말고 DB 를 믿는다).
- **롤백**(admin Rollback 탭, `wms_rollback_log.sql`): 매니저 전용, 한 단계씩 최심단계만(Undo Fulfillment→Undo Pack→Reset Pick→Undo Split), `wms_rollback_log`에 감사기록. discrepancy는 자동삭제 안 함. closed 오더도 롤백 대상.

## 규칙 15 — 프린트/다운로드 (⚠️ 2026-07-21)

- **배치별 픽리스트**(manager Create batches 시 자동): **배치 1개 = 1페이지**(page-break), 각 페이지 = 로고 + **배치라벨 CODE128 바코드** + 오더/창고/고객/총라인·총유닛/Picked By + **Zones 요약**(품목표는 뺌). 바코드=배치라벨(SO-X-N) → 픽커 스캔진입과 정확일치.
- **팩킹리스트**(fulfillment 유닛/스토어별, admin Finalized 탭 재출력): 컬럼 **SKU·Barcode·Product·Qty**(바코드=스냅샷 sku별 대표바코드). admin에서 **🖨 Print · ⬇ PDF · ⬇ CSV**. direct 오더는 "Direct pack" 태그(팩킹리스트 없음).
- **⚠️ 로고 in 프린트창**: `window.open` 새 문서라 상대경로 안 됨 → `location.origin+"/asung-logo-dark.png"` 절대URL. fulfillment은 같은문서 #printArea라 상관없지만 통일. PDF=jsPDF+autotable(CDN, 첫클릭시 lazy-load), CSV=BOM+CRLF.
- 바코드 라이브러리: JsBarcode `cdn.jsdelivr.net/npm/jsbarcode@3.11.6/dist/JsBarcode.all.min.js`.

## 규칙 16 — 매니저 세부권한 & 공용 내비 (⚠️ 2026-07-21)

- **`wms_staff.perms`**(jsonb, `wms_staff_perms.sql`, 기본 `["split","admin","staff"]`): 매니저별 화면권한. admin 역할=항상 전부, worker=해당없음. staff-admin에 Access 체크박스 3개.
- **wms-auth `requirePerm`**: manager.html=`split`·admin.html=`admin`·staff-admin.html=`staff`. 권한 없는 매니저는 URL 직접접근도 차단. index 런처는 perms별 카드 표시.
- **공용 ☰ Menu 드롭다운**(wms-auth `setupNavMenu`): 모든 화면 공통, 권한반영 목록(순서: Admin→Order Splitting→Picking→Packing→Fulfillment→Staff→Home). onReady에서 자동설치.
- **⚠️ bfcache 수정**: wms-auth에 `pageshow`(persisted) → `location.reload()`. 뒤로가기 복원 시 죽은 요청으로 스피너 무한대던 문제 근본해결(전 화면).
- **모바일**: 각 화면 `@media` 추가(헤더 줄바꿈·버튼축소, admin 테이블 가로스크롤·탭 스와이프, manager 컨트롤 줄바꿈+선택시 작업영역 자동스크롤+"✓ selected"). 데스크톱 우선이나 폰서 안 깨지게.
- **⚠️ 스캔 오류음**: 저음 180Hz→**2400/1600Hz 교차 사이렌, 볼륨 1.0, 0.72초**(작은 스피커 대응). picker/packer `beep("bad")`. 성공음은 유지(구분).

## 규칙 17 — 렌더/스캔 함정 (⚠️ 2026-07-21 디버깅 교훈)

- **진입 즉시 렌더 후 enrich**: picker loadLines·packer enterPack은 라인 로드 후 **즉시 화면전환+렌더**, 재고/바코드는 뒤이어 독립 try로 채우고 재렌더. 세 조회를 순차 await 후 렌더하면 지연·한 조회 실패가 전체 렌더를 막음.
- **⚠️ 존재하지 않는 DOM id 참조 금지**: 옛 UI 제거 후 남은 `getElementById("drop")` 한 줄이 렌더 도중 TypeError→리스트 공백+enrich 중단. 배포 전 **누락 id 전수검사**(`getElementById` vs `id=` 차집합) 습관.
- **-12 박스 바코드 스캔**: 오더가 base SKU로 들어오면 scannable_barcodes에 변형(-12) 바코드가 없음(백엔드 조립규칙 방향성 공백) → 픽커가 박스 스캔 시 거부됨. **프론트에서 형제 스냅샷 바코드를 bcMap에 병합**해 해결(picker/packer). 근본수정은 GAS scannable_barcodes 조립에 형제변형 추가(백로그).
- **ALT-UPC 표시**: 싱글뷰 barcodeBlock이 base+변형(factor>1)에 더해 `l.barcodes` 중 type='alt'를 "ALT-UPC"로 표시.
- **자동이동**: 스캔뿐 아니라 **수동 +/−·수량입력으로 목표 도달 시에도 autoAdvance**(picker). packer는 목표 초과 시 confirmFillIfNeeded(소리+플래시+확인).
- **⚠️ periodBar custom 인자는 객체**(`{from,to}`) — null 넣으면 `custom.from` 접근에서 TypeError로 boot 중단(admin 초기 로딩 공백 원인이었음). periodBar 내부 null 방어 추가됨.

## 규칙 18 — Wave: 소량 오더 그룹 픽킹 (⚠️ 2026-07-22)

**핵심 원칙: wave는 pick 배치를 "만드는" 게 아니라 이미 만들어진 pick 배치들을 "묶기만" 한다.** split과 wave는 사실 같은 일(오더 라인을 pick 배치로 나눠 담기)을 방향만 반대로 하는 것 — split은 오더 1개→배치 N개, wave는 오더 N개→각자 배치 1개를 한 묶음으로. **픽킹 출구는 여전히 하나(pick 배치 생성)라 하류(packer·fulfillment·rollback·Health)에 구멍이 안 생김.** 만약 wave를 "새 종류의 배치를 만드는" 것으로 설계하면 "픽 준비됐다=pick 배치가 있다"는 불변식이 깨지고 하류가 조용히 흔들림 → 반드시 그룹핑 레이어로만.

- **`wms_waves` 테이블**(B 최소형, `wms_waves.sql`) + `wms_pick_tasks`에 `wave_id`(FK, NULL=평범한 split 배치)·`tote_no`(1..10 물리 토트 슬롯) 컬럼. 별도 테이블인 이유: wave 단위 claim/상태/heartbeat/목록이 필요(A안=컬럼만 추가로는 부족). ⚠️ **`wms_waves.sql`을 `wms_healthcheck.sql`보다 먼저 실행**(health 함수가 wms_waves 참조).
- **각 소량 오더 = 자기 pick 배치 `{order_number}-1`**(split의 "1라인=1배치 최소보장"이 여기서도 그대로) + `wave_id`·`tote_no` 꼬리표. **토트 = 그 오더의 pick 배치**, 토트 번호 = 물리 카트 칸 번호. **선택 순서 = 토트 번호**.
- **분류(sort)는 픽커 스캔 시점에**(sort-to-tote) — 스캔이 order_line에 귀속되므로 그 순간 화면이 "→ TOTE 2 (고객명)"으로 안내, 픽커는 그 칸에 넣음. **분류를 팩커로 미루면 안 됨**(팩커가 "이 SKU가 어느 오더 것?"을 다시 풀어야 하고, 섞인 더미는 실수 유발). 팩커는 토트 하나=오더 하나로 기존 그대로 전량 재스캔 검수.
- **매니저 수동 선택만**(자동 추천 없음). manager.html **Split | Group 토글**. Group 모드에서 필터(기본 라인≤5·낱개≤100, 조정 가능) 통과한 소량 오더만 표시, 탭으로 담음. **같은 창고만**(toronto/edmonton 혼합 금지), **최소 2오더**, **카트 토트 최대 `WAVE_MAX=10`**.
- **wave 라벨 `W-MMDD-n`**(당일 생성 수+1). 프린트물 = wave 바코드 1개 + 토트 배정표(한 장). 픽커가 이 바코드 스캔 시 wave 로드.
- **픽커 wave 모드**: "Waiting Waves" 섹션 별도(⚠️ **wave 멤버 배치는 개별 배치 목록에서 숨김** — `loadBatches` 3쿼리에 `.is("wave_id",null)`, 누가 한 오더만 빼가는 것 방지). start/resume/takeover/hold/finish/back 전부 wave 단위로 동작(멤버 태스크 일괄 + wave 행 동시). heartbeat = wave 행 + 멤버 태스크 동시. 라인은 wave 전체를 zone 순 병합(tote는 타이브레이커라 동선 유지). `loadLines`·`loadWaveLines` 꼬리를 **`enterPickView` 공유 함수**로 추출(정렬+bcMap+렌더+enrich 공유).
- **⚠️ discrepancy 오더별 귀속**: wave에서 short 나면 그 라인의 `_orderId`/`_orderNumber`(loadWaveLines가 태스크→오더 매핑으로 채움)로 discrepancy insert. task.order_id 쓰면 안 됨(전부 한 오더로 잘못 귀속).
- **⚠️ v1 한계**: admin Batch activity에서 wave 멤버 배치를 **개별** Release하면 wave 행은 남는 엣지(픽커엔 안 뜨니 실해 없음, wave 해제 필요 시 멤버 전부 Release). wave 카드 라인수는 3단 중첩 쿼리(wms_waves→pick_tasks→task_lines count)라 0으로 뜨면 표시만의 문제(픽킹 무관).

## 규칙 19 — 불변식 자동검증: `wms_health_check()` & admin Health 탭 (⚠️ 2026-07-22)

**규칙 3의 불변식(factor·required_base·분할 합계 등)을 사람이 눈으로 지키는 대신 DB 함수가 상시 검증한다.** 병행 운영·wave·리시빙처럼 경로가 늘어날 때 조용히 새는 것을 잡는 안전망.

- **`wms_health_check()` DB 함수**(`wms_healthcheck.sql`, `security definer`+authenticated grant, 읽기 전용, `create or replace`라 재실행 안전). admin.html **Health 탭**이 `sb.rpc("wms_health_check")`로 호출, 검사당 카드 하나. **0행=건강**(fail_count>0이면 깨진 것, sample은 위반 최대 8행 jsonb).
- **검사 항목**(sort 순): factor_math(critical, required_base=qty×factor)·factor_drift(warn, 라인 factor vs 스냅샷)·split_sum(critical, 분할 배치 assigned 합=required_base)·short_no_disc(critical, short인데 discrepancy 없음)·pick_over(warn)·progress_leak(warn, order_progress≠`2.Release to WMS`)·dup_sale(critical, cin7_sale_id 중복)·finalize_recon(critical, clean-closed인데 picked≠required)·orphan_pick(warn)·orphan_pack(warn)·**wave_state(warn, 규칙 18)**·last_import(info). **critical 하나라도 깨지면 탭에 빨강 배지**(discBadge와 동일 패턴).
- **⚠️ orphan_pack은 반드시 배치 기준**: "오더가 picking인데 pack task 있음"으로 짜면 **오탐**(분할 오더는 일부 배치가 이미 팩 단계인 게 정상 — 이 WMS의 존재 이유). 올바른 조건 = **pack 배치의 짝 pick 배치(`pick_task_id`)가 completed 아닐 때만** 플래그. SO-13443(8배치 중 -1~-4 Packed·-5~-8 Waiting) 같은 정상 병렬을 안 걸러야 함. (2026-07-22 실데이터로 오탐 확인 후 수정한 교훈.)
- **⚠️ short_no_disc 매칭 키 = `order_id + order_sku`**: 실제 `wms_discrepancies.sku`에 order_sku가 아닌 base_sku가 저장되고 있으면 이 검사가 전건 오탐. 처음 돌렸을 때 잔뜩 뜨면 매칭 키 문제이니 SQL 한 줄 수정.
- **Health가 wave의 안전망**: wave 추가로 "픽 준비됐다"의 정의가 넓어져도, split_sum·orphan_pack·wave_state가 데이터 구조 정합성을 상시 검증 → 병행 운영 중 조용히 새는 걸 잡음.
- ⚠️ **리시빙 검사는 아직 없다**(`wms_receipts`·`wms_receipt_lines` 무검증). 규칙 27 의 R3(중복 receipt)·R4(이중 Apply)는 지금은 Health 로 안 잡힌다 — 검사 추가는 백로그.
- ⚠️ **`short_no_disc` 는 픽킹 전용이다** — `wms_pick_task_lines` 기준이라 **리시빙 discrepancy 가 한 건도 안 들어가고 있던 것을 못 잡았다**(규칙 29). 추가할 검사 2개: ①리시빙용 short/over ↔ `wms_discrepancies(source='receiving')` 대조 ②`wms_receipt_lines.putaway_bin` ↔ `asung_bin_stock` 대조(규칙 32) — 둘 다 백로그.

## 규칙 20 — 리시빙 모듈: PO/트랜스퍼 입고 + 라스트 로케이션 풋어웨이 (⚠️ 2026-07-23)

**핵심 목적: Cin7 다이나믹 로케이션의 두 빈틈 — (1)sold-out 시 라스트 로케이션 망각 (2)매번 수동 풋어웨이 강제 — 를 메운다.** 우리 sticky bin 데이터(`asung_bin_stock` → `wms_sku_bins`)가 라스트 로케이션을 이미 보존하므로, 리시빙 시 자동으로 그 자리로 풋어웨이한다.

- **화면 = `receiver.html`** (requireManager:false, 픽커 톤·bcMap·factor·사운드 재사용, Single|List 뷰 + Last bin 칩). **Edge Function = `receiving`** (hello 와 별개 함수).
- **유입은 온디맨드** (버튼/PO 바코드 스캔, 폴링 없음). ⚠️ **PO 는 `InvoiceStatus` AUTHORISED + PAID(2회 호출 병합, ID 기준 dedup)** — Asung 은 무조건 **Invoice First**(인보이스 받아 Cin7 PO 와 일치·승인 후 리시빙)이고, PAID 는 그 승인 **이후** 단계라 자격을 잃지 않는다. ⚠️ 실측 2026-07-28: PO-01081(InvoiceStatus=**PAID**, 입고 전)이 AUTHORISED 단일 조회에서 Total 0 으로 누락돼 목록에 안 뜨던 버그 → 2회 호출로 수정. ⚠️ **`Limit=1000`(`PO_PAGE_LIMIT`) 로 상태별 전량 1페이지 조회** — 2회 병합을 배포해도 PO-01081 이 무검색 목록에 안 뜬 진짜 원인은 **페이지 상한**이었다(실측 2026-07-28, InvoiceStatus=PAID Total 825): ① **정렬은 PO 번호 오름차순** — page1=PO-00004~, 최신 PO 는 마지막 페이지(Page=9 에서 PO-01081) → 기존 `Limit=100`+`page<=3`(=300건) 이 최신 PO 를 통째로 못 읽고, 읽은 300건은 거의 다 StockReceivedStatus=AUTHORISED 로 걸러져 목록에 한 건도 안 남았다. ② **Limit=1000 이 동작한다** — page1 에 825건 전부(PO-00004~PO-01081), page2 는 0건. ③ **UpdatedSince 는 부적합**(동작은 함: 30일 124/60일 249/90일 331건) — 60일 창의 page1 도 PO-00004 부터라 지불 갱신 때문에 날짜 창이 PO 번호 최신성을 보장하지 못한다. 그래서 180일 창(`PO_PAID_LOOKBACK_DAYS`) 방식은 **폐기**. ④ **RestockReceivedStatus 필터는 무시된다**(NOT AVAILABLE·DRAFT 모두 Total 825 = 무필터와 동일) → StockReceivedStatus 제외는 계속 클라이언트 측에서 한다. ⚠️ 조기 종료 조건도 같은 상수(`items.length < PO_PAGE_LIMIT`) — 100 으로 남으면 첫 페이지에서 루프가 끊긴다. 페이지 상한은 `page <= PO_MAX_PAGES`(3) 유지. **📌 PO 총건수가 2000 을 넘으면 이 상한을 다시 볼 것.** 응답에 진단 필드 **`scanned`**(상태별 가져온 행 수 예 `{AUTHORISED:n, PAID:825}`) + **`truncated`**(상한에 걸려 더 있는데 못 읽었으면 true) — 규칙 12 dry-run 진단과 같은 취지(상한에 걸린 사실이 응답에 안 보여 원인 파악에 왕복이 여러 번 걸렸다). `pos` 배열 구조·필드명은 불변(receiver.html 이 소비). 추가 제외: Type 에 Service 포함(운송·관세 — 물건 없음), Status 에 RECEIVED 포함(단 RECEIVING=부분입고 진행중은 유지), VOID/COMPLETED/CREDITED, StockReceivedStatus=AUTHORISED. **트랜스퍼는 Status='IN TRANSIT'**, 창고는 ToLocation 정규화 — 리시버 warehouse_access 필터.
- **추천 빈 규칙** (base_sku × warehouse): ①`is_current=TRUE` 우선 ②없으면 `last_seen` 최신(=sold-out 자리 중 마지막) ③available 많은 곳. ⚠️ `wms_sku_bins.last_seen` 은 2026-07-23 추가(ALTER + `wms_buildBins_` SELECT/map 각 1줄) — sticky MERGE 가 last_seen 을 갱신 안 하고 얼려두므로 "마지막 재고 있던 날"이 됨. 초기엔 전부 같은 날짜(소급 불가)라 시간이 지나야 갈림.
- ⚠️ **라스트빈 "no last bin" 근본 한계 (2026-07-24 규명)**: sticky 이력이 **2026-07-06 first_seen 부터** 시작(BQ `min(first_seen)`). 그 전에 이미 0 이 된 과거 bin 은 Cin7 productavailability 가 0-재고 bin 을 아예 안 줘서 sticky 가 **본 적이 없음 → 보존 불가**. 예: CAN01545 는 2/19 트랜스퍼로 에드먼튼 EC010303 에 있었다가 팔려 0 → 7/6 시작 땐 이미 0 → no last bin. **버그 아님, 데이터 시작점 한계.** 복구책: (가)Cin7 movements API 백필 or (나)지금부터 축적+수동지정(권장, 한 번 지정하면 재고 앉을 때 sticky 가 기억). bin 단위 과거이력은 movements 에만 있음(BQ asung_stock_daily 는 warehouse 레벨).
- **빈 지정 UI (2026-07-24)**: 라스트빈 없거나 바꿀 때 — **스캔(1순위)+드롭다운 검색(폴백) 모달**. 드롭다운 소스 = EF `action=bins&warehouse=`(Cin7 `/ref/location` 전체 bin, **빈 자리 포함** — 신제품 새 자리 지정 가능), 실패 시 wms_sku_bins 폴백. 알려진 bin 아니면 confirm(신규 bin 허용). bin 있는 라인엔 **"Change" 버튼**(다른 자리로 바꾸면 putaway_done 자동 해제).
- **검수 정렬 4종 (2026-07-24)**: Sort 드롭다운 = PO순 / Zone·Last bin순 / Product(A-Z, 브랜드가 앞이라 자연 브랜드정렬) / SKU순. ⚠️ **`lines` 배열은 안 건드리고 표시 인덱스만 정렬**(bcMap·스캔 무결성 보존). 싱글뷰 Prev/Next 는 표시 순서를 따름. ⚠️ **2026-07-27 갱신 — 여기에 "채운 라인 아래로" 1차 키가 추가되고 `autoAdvance` 는 표시 순서를 쓰지 않게 바뀜: 규칙 26 참조.**
- **Zone→Bay 점프 (2026-07-24)**: 검수(Zone정렬시)·풋어웨이에 **sticky 칩 바**(스캔+정렬+칩 한 묶음 sticky top:55px). Zone 칩 클릭 → 그 zone 의 Bay 칩 펼침 → Bay 클릭 시 스크롤. 풋어웨이는 진행률(3/8)도 표시. **bayOfBin 규칙**: [E?]Zone Rack(숫자2) 뒤가 숫자4+면 베이(2)+셸프(2)→bay=존+랙+베이2, 문자 섞이면(Pallet05·HAIR) 나머지 전부가 베이=bin 통째. 토론토 C020303→C0203, 에드먼튼 EZ010101→EZ0101(E 포함 표시), EZ01Pallet05→통째.
- **모바일(태블릿 세로) 최적화**: 칩·스테퍼·Placed/Change/Assign 버튼 터치 ≥40px. HID 블루투스 스캐너(=키보드 입력, focusScan 이 처리). `receiver-preview.html`(실제 CSS+샘플, 정적)로 태블릿 실물 확인 가능.
- **흐름**: PO/TR 선택 → PO-guided 스캔 검수(초과=confirm 후 허용+over 플래그, 홀드 가능) → **오프-PO 는 매니저 승인 대기**(needs_approval, 승인 전 풋어웨이·Apply 차단) → **Putaway→ 버튼이 빈 자동확정** → 풋어웨이 가이드(빈별 그룹, zone 동선순, Placed 체크; 신규 SKU=빈 지정 필요 그룹에서 스캔/입력) → 부분완료(PO 열림) / 최종완료.
- **테이블**: `wms_receipts`(po_number·cin7_purchase_id·warehouse·status[in_progress/held/partial/completed]·**source_type[po/transfer]**·**applied_at/by/note**) + `wms_receipt_lines`(expected_base·received_base·putaway_bin·zone·putaway_done·is_off_po·needs_approval). ⚠️ wms_sku_bins 에는 절대 안 씀(6:30 truncate). SQL: `wms_receipts.sql` + `wms_receipts_apply.sql`.
- **admin Receiving 탭**: Off-PO approvals(Approve/Reject, 배지) + **Apply to Cin7**(completed & 미반영만; dry-run 계획 confirm → commit — 규칙 21) + History(✓ Applied 배지, Delete=WMS 전체 리셋·단계 없음·Applied 후엔 Cin7 안 되돌아감 경고).
  - **Review 버튼 (2026-07-24)**: Apply 옆·History 에. 읽기전용 요약 모달(bin 별 그룹핑된 풋어웨이 결과·수량·OVER/SHORT/OFF-PO·Placed). 하단: Apply→Cin7 / **Reopen for edit**(status→in_progress + `receiver.html?receipt=N` 딥링크로 이동해 기존 화면에서 수정 — 새 수정 UI 안 만들고 검증된 화면 재활용). applied 된 건 Reopen 잠금.
  - **Apply 권한 (2026-07-24)**: perms 에 `apply` 키 추가(staff-admin PERMS 배열). admin 역할 항상 통과. 권한 없으면 Apply 버튼→"no permission", 함수 진입도 차단(3중 게이트). ⚠️ 기존 매니저에 apply 기본 없음 — 신뢰하는 소수만 체크.
- **Resume/열기 필터 (2026-07-24)**: `loadMyReceipts` 는 `applied_at IS NULL` 만(반영된 건 목록에서 제외). openReceipt 도 applied 면 차단.
  - **중복 카드 숨김 (2026-07-28)**: Resume 섹션에 **이미 카드로 떠 있는 문서**는 아래 "Ready to receive (Cin7)" 목록에서 감춘다(키 = `po_number` 대문자 비교, 헤더에 "— N already open above" 표시). ⚠️ **기준은 "화면에 렌더된 `myReceipts`" 뿐이다** — "receipt 행이 존재하면 숨김"으로 짜면 안 된다: 창고 접근 밖 등으로 Resume 에 안 뜨는 문서까지 사라져 **스캔 이어받기 진입로가 막힌다**. 빈 목록 판정도 `openPos` 가 아니라 `visPos` 기준(전부 숨겨졌는데 "없음"이 안 뜨던 문제).
- **리시빙 리스트 프린트 (2026-07-25)**: receiver 검수 헤더 **🖨 Print** → 픽리스트와 동일 형식 새 창(팝업차단 회피: 클릭 핸들러 안에서 `window.open`). 로고 + "PO/TRANSFER RECEIVING" + **문서번호 CODE128 바코드**(인쇄물 스캔으로 재진입) + 공급사/루트·창고·총라인/수량·Received By 서명란 + 라인표(**Last bin** · SKU · 제품명 · Qty · ✓체크박스). **라스트빈(존) 순 정렬**(창고 동선), no-bin 은 주황 "no bin" 으로 눈에 띄게. `zoneOfBin`/`zOrder` 재사용.
- **차이(불일치) 처리 정책 (2026-07-25 사용자 결정 · 중요 / 2026-07-28 트랜스퍼 예외 추가)**: ① Cin7 에는 **초과/부족 무관 "들어온 대로"**(received) 쓴다 — **PO stock received 는 초과 허용이 실측 사실**(⚠️ 트랜스퍼는 아니다, 아래 예외). ② 기대치와의 차이는 **`wms_discrepancies` 큐에 자동 기록**(`source='receiving'`, reason `recv_over`/`recv_short`/`recv_off_po`, `po_number`/`receipt_id`, responsible=received_by). ③ 매니저가 admin Discrepancy 탭에서 보고 **Cin7 backend 에서 수동 stock adjustment** → "Cin7 Fixed" 버튼으로 정리. **자동 adjustment 는 하지 않음**(사람 판단 유지 = 안전). `receipt_id+sku` **전체 유니크**로 재적용 중복 방지. SQL `wms_disc_receiving.sql`(order_id NULL 허용 + source/po_number/receipt_id + 유니크 인덱스). ⚠️⚠️ **2026-07-29 정정 — 원래 이 인덱스는 `WHERE receipt_id IS NOT NULL` 부분 유니크였고, 그 때문에 PostgREST `on_conflict` 가 깨져 리시빙 discrepancy 가 구현 이후 한 건도 기록되지 않았다: 규칙 29.**
  - ⚠️ **기록 시점 = Cin7 쓰기 "앞"** (2026-07-28 역전). 예전엔 applyCommit **맨 마지막**이라 bin 이동이 throw 하면 차이 기록이 통째로 유실됐다(TR-02935 실사고). 이 큐가 **유일한 보정 지시서**이므로 **insert 실패 = Apply 중단**(Cin7 을 건드리지 않는다) — 여기서만 "실패해도 Apply 성공(WARN)" 방침을 의도적으로 뒤집는다. 자세한 원칙은 규칙 27 **R12**.
- **⚠️⚠️ 트랜스퍼 예외 (2026-07-28 사용자 결정 — API 제약 때문)**: 트랜스퍼는 "Cin7 에 received 를 쓴다"가 **API 레벨에서 불가능**하다(완료 PUT 의 `TransferQuantity` 변경은 무시된다 — 규칙 21 정정 항목).
  - ① **완료 수량 = 보낸 수량(주문 수량) 그대로 확정.** 실물 수량 덮어쓰기 로직은 제거했다.
  - ② 실물과의 차이는 **반드시 discrepancy 에 명시** — 여기선 큐가 유일한 정정 근거다.
  - ③ 매니저가 **Cin7 에서 수동 stock adjustment** 로 정리.
  - ④ **bin 이동은 `min(received_base, expected_base)` 캡.** 초과 라인은 expected 만큼만(초과분은 Cin7 에 없다 → 옮기려면 400). 부족 라인은 received 만 옮기고 `expected − received` 는 착지 지점에 남는다.
  - ⑤ **잔량이 착지 지점에 남는 것은 의도된 동작이다.** 남은 수량 = 매니저가 제거해야 할 양이고, 남아 있다는 것 자체가 "미정리" 신호가 된다. 보정 트랜스퍼 자동 생성은 **채택하지 않음**(부족분을 기계적으로 되돌리면 실제 분실을 "토론토에 있다"고 잘못 기록할 위험).
  - ⑥ ⚠️ **잔량의 위치 표현이 (a)/(b) 로 다르다**(규칙 21 착지 지점 2가지): **(b)** 집결 bin → **bin 이름**(예 `EZ010101`) / **(a)** 창고에 bin 없이 → **`"Asung - Edmonton (no bin)"`** 처럼 창고명+`(no bin)`. 매니저가 Cin7 에서 찾아 제거하는 지점이라 틀리면 못 찾는다 → EF 는 `to_location_raw` 원문을 그대로 쓰고 `leftover_at_landing[].where`·`apply_note`·Review 모달에 같은 문자열을 싣는다. ⚠️ `landingBin = to_location_raw` 의 콜론 뒤 부분은 **반드시 trim + undefined 방어** — (a) 는 콜론이 없어 `split(":")[1]` 이 undefined 이고, 앞 공백이 남으면 "이미 제자리" 스킵 판정이 어긋나 From==To 이동을 쏴서 400 이 난다.
- ⚠️ **CSV 경로는 폐기** — Cin7 직접 쓰기 검증(규칙 21)으로 대체. **`exported_base` 는 2026-07-28 부터 트랜스퍼 bin 이동 체크포인트로 사용**(옮긴 수량 기록 → 재Apply 시 그 라인 건너뜀). PO 경로는 아직 미사용.
- **Apply 는 completed receipt 만**: Simple PO 는 stock received 를 한 번만 authorize 가능(Cin7 제약) → 분할 배송은 최종완료 때 일괄 반영.
- ☰ Menu 에 Receiving(전 작업자), index 런처에 카드.

## 규칙 21 — Cin7 쓰기 (⚠️ 2026-07-23 실측 검증 — MVP "안 쓴다" 원칙의 첫 예외)

리시빙은 Cin7 에 **직접 쓴다** (매니저 Apply 게이트 경유). 실측으로 확정된 규칙:

- **bin = GUID.** `From`/`To`/`LocationID` 에 bin 이름("창고: bin")을 넣으면 400 "not found in Locations reference book". `/ref/location` 에서 GUID 조회 (EF `binGuid()`/`binMap()`).
  - ⚠️ **`/ref/location` 은 Total 2678 인데 Limit 500 로 잘린다. bin GUID 는 최상위 창고 행(`ParentID` 없음)의 `Bins[]` 에서 뽑아라**(에드먼튼 628·토론토 2047 전부 포함 — 페이지네이션 불필요). **child-location 의 `Name` 은 bin 이름이 아니다**(예 "071164313169" 바코드류 — 매칭 불가한 죽은 경로였고 제거했다). 실측 2026-07-28 **TR-02935**: 잘린 500행에 에드먼튼 child 가 0행이어서 bin GUID 조회가 첫 호출부터 throw → Apply 의 bin 이동이 **한 건도 실행되지 않고** 전 품목이 집결 bin EZ010101 에 남았다. 토론토도 우연히 앞 페이지였을 뿐 안전하지 않았다. 이름 비교는 `trim().toUpperCase()`, `IsDeprecated` 제외. `?action=bins` 도 같은 소스.
  - ⚠️ **GUID 를 못 찾으면 그 라인만 스킵**(전체 throw 금지) → 응답 `skipped_bins:[{sku,bin,reason}]` + `apply_note`. 트랜스퍼는 PUT COMPLETED 이후 절대 throw 안 함(Cin7 은 이미 바뀌었는데 `applied_at` 이 null 로 남아 큐에 갇히고 discrepancy 까지 유실된 게 TR-02935 의 2차 피해). PO 는 하나도 못 찾으면 throw(아직 안 썼으므로 재Apply 가 맞다) · **스킵이 있으면 auto-authorize 생략**(DRAFT 유지 → Cin7 에서 수동 보정).
- **트랜스퍼 (TR-03236 실측)**: `POST /stockTransfer` 로 **즉시 Status=COMPLETED 생성 가능**(DRAFT 불필요). **같은 창고 bin↔bin 은 InTransitAccount 불필요.** 수량은 델타(TransferQuantity)라 절대값 위험 없음 — stock adjustment(절대값)보다 안전해 bin 이동의 표준 수단. 되돌리기 = 반대 방향 트랜스퍼(상쇄).
- **트랜스퍼 리시빙 완료** = PUT 원 TR→COMPLETED(전량 헤더 기본 To bin 착지 — 트랜스퍼 라인엔 bin 없음, 문서 구조상 불가) → **bin 그룹별 미니 트랜스퍼**(기본 bin→목적지 bin)로 재배치. Cin7 WMS 앱의 라인별 무한 풋어웨이 반복을 API 콜 몇 개로 대체.
- **PO stock received (PO-01084·PO-00965 실측)**: `POST /purchase/stock` — `{TaskID: PO GUID, Status:'DRAFT', Lines:[{Date, SKU, Quantity(라인 단위 — received_base÷factor), LocationID(bin GUID), Received:false}]}`. **입고 시점에 bin 직접 지정.**
  - ⚠️⚠️ **문서당 bin 1개만! (2026-07-24 실측 — 가장 중요)**: 한 `POST /purchase/stock` Lines 에 **서로 다른 bin(LocationID)을 섞으면 400 "Lines is invalid"**. 같은 bin 여러 SKU 는 OK. → **putaway_bin 으로 그룹핑해 bin 마다 별도 POST** (콜 간 sleep 300~400). 이게 오랫동안 "Lines is invalid" 로 헤맨 진짜 원인. (트랜스퍼 bin↔bin 은 되는데 stock received 는 안 됨 — API 마다 다름)
  - ⚠️ **같은 (SKU+bin) 중복 라인 금지**: 400 "Cannot add duplicate value". EF 가 plan 만들 때 같은 SKU+bin 은 수량 합산 병합.
  - ⚠️ **Authorize = `POST` (PUT 아님!, 2026-07-24 실측)**: `POST /purchase/stock {TaskID, Status:'AUTHORISED', Lines:[]}`. **PUT 은 405 "does not support http method 'PUT'"**. 성공 시 재고 확정. 실패해도 DRAFT 는 남아 Cin7 화면 수동 Authorize 가능(EF WARN 로그).
  - **Date 형식**: `YYYY-MM-DDT00:00:00Z` (자정, 밀리초 없이). 밀리초 포함 ISO(`.948Z`)는 의심스러워 자정 고정으로 통일. `Date` 필드는 필수.
  - **빈 DRAFT 문서 함정**: Cin7 화면 Stock Received 탭이 "비어있음"으로 보여도 API GET 은 NOT AVAILABLE 반환할 수 있음 — 화면 표시와 API 상태가 다를 수 있으니 GET 결과로 판단.
- ⚠️ **Invoice First 게이트**: 인보이스 미승인 PO 에 stock received POST 하면 400 "'Invoice First' approach... authorise Invoice before StockReceived". EF Apply 가 `/purchase/invoice` 로 선확인. Status=INVOICED PO 도 stock received 통과(실측).
- **트랜스퍼 창고간(branch→branch) — 실측 확정 (2026-07-25, TR-03260/03261)**: 실제 IN TRANSIT 은 From/To 가 **bin 이 아니라 warehouse**(FromLocation "Asung Trading Inc." → ToLocation "Asung - Edmonton"), InTransitAccount 있음, **라인에 bin 필드 없음**(ProductID/SKU/TransferQuantity/BatchSN/ExpiryDate…). 확정 3가지:
  - **완료 = `PUT /stockTransfer` `{TaskID, Status:'COMPLETED', From, To, CostDistributionType, InTransitAccount, DepartureDate, CompletionDate, Lines, SkipOrder:true}`** → 200.
  - ⚠️⚠️ **정정 (2026-07-28, TR-03267 실측) — 완료 PUT 의 `TransferQuantity` 변경은 무시된다.** 이전 기록 *"수량 초과 완료 허용: 1개로 보낸 트랜스퍼를 라인 3개로 바꿔 완료해도 200 → 들어온 대로 쓰기 가능"* 은 **틀렸다.**
    - 정정 근거(신규 IN TRANSIT TR-03267): SENT 에 변경값이 정확히 실려 나가고 PUT 200 이 떨어지지만 **되읽으면 원본 그대로다.** `AS93113` 원본 2 → 요청 4 → **저장 2** ❌ / `AS92700` 원본 4 → 요청 2 → **저장 4** ❌ → **증가·감소 양방향 모두 무시.** 코드 버그가 아니라 API 제약이다(추정: 창고간 트랜스퍼는 발송 시점에 재고가 in-transit 계정으로 넘어가므로 거기 없는 수량을 완료로 받을 수 없다).
    - 왜 틀린 기록이 남았나 — **HTTP 200 만 보고 저장값을 되읽지 않았고**, PO stock received 의 초과 허용(이쪽은 **사실**)과 혼동됐다. 📌 **교훈: 쓰기 실측은 200 이 아니라 GET 으로 되읽은 값이 근거다.** (규칙 27 R11)
    - → **트랜스퍼 완료 수량 = 보낸 수량 확정.** 실물 차이 처리는 규칙 20 의 트랜스퍼 예외 참조. **PO 경로는 그대로 — received 그대로 쓴다.**
  - ⚠️ **완료 시 bin 지정 불가 → 착지 지점 2가지** (트랜스퍼 헤더 To 에 따라): (a) To=**창고 GUID** → **bin 없이** 창고에 재고가 뜸(Cin7 재고화면 BIN 칸 공백). PO 같은 "received 화면에서 bin 지정" 단계가 **없음**. (b) To=**특정 bin GUID** → 그 bin 에 전량(예 에드먼튼 EZ010101 — 과거 수동 워크플로의 **임시 집결지**, 실제 보관자리 아님. Cin7 WMS 가 느려 한 곳에 몰아 받고 나중에 풋어웨이하던 편법).
  - **풋어웨이 = `POST /stockTransfer` `{Status:'COMPLETED', From: <트랜스퍼의 To GUID>, To: <실제 bin GUID>, Lines:[{SKU, TransferQuantity}], SkipOrder:true}`** → 200. **From 을 창고 GUID 로 주면 "bin 없는 재고"를 꺼내 옮겨줌**(실측: bin 없던 1개 → EB010204, 재고 0/23→24 확인). (b) 케이스는 From=집결 bin GUID. 즉 **From 은 항상 `det.To`** 로 두면 두 경우 다 동작.
- **트랜스퍼 리시빙 워크플로 = PO 와 동일 (2026-07-25 사용자 결정)**: 받기→풋어웨이(bin 지정)→Apply. "즉시 완료로 재고 먼저 노출"(편법)은 **채택하지 않음** — 이유: 흐름 일관성, 풋어웨이를 뒤로 미루는 나쁜 습관 방지, "보이는데 어디 있는지 모르는" 재고 구간 제거. Apply 가 뒤에서 ⓪discrepancy 선기록 →①**보낸 수량 그대로** COMPLETED →②**캡된** bin 이동(+`exported_base` 체크포인트) →③receipt PATCH 를 순차 수행 (2026-07-28 개정 — 규칙 20 트랜스퍼 예외).
  - ⚠️ **bin 이동 수량은 `min(received_base, expected_base)` 로 캡한다 — 안 하면 400.** 완료 후 착지 지점에 실제로 앉는 건 **보낸 수량**이므로 초과분은 Cin7 에 존재하지 않는다(예 APR15412 expected 24 / received 48 → 24 만 이동). off-transfer SKU 는 Cin7 보유 0 → **bin 이동 제외**, `recv_off_po` discrepancy 로만 남긴다.
  - ⚠️ **재개 경로**: 원 TR 이 **이미 COMPLETED 인데 bin 이동이 안 끝난** receipt 은 ①PUT 을 건너뛰고 ②부터 재개한다(`plan.mode="resume"`). 예전 plan 검증이 "IN TRANSIT 이어야 함" 뿐이어서 TR-02935 가 **영구히 큐에 갇혔다**. `exported_base` 가 찬 라인은 재이동하지 않는다.
  - ⚠️⚠️ **bin 이동 한 건의 실패가 나머지를 막지 않는다 — 부분 성공 + 재시도 (2026-07-28, TR-02935 재개 Apply 실측)**: discrepancy 선기록은 통과했는데 **첫 bin 그룹의 400 하나로 전체가 중단**됐다 — `POST /stockTransfer` → 400 `"Available quantity for product (SKU: AS97745 …) is 0.0000000000, cannot transfer 2"` (From = 집결 bin EZ010101 `b997fb39-…`). **344 라인 중 1 건이 나머지 143 개 bin 이동을 통째로 막았다.**
    - ⚠️ **이 400 은 버그가 아니라 정상적으로 발생하는 운영 상황이다** — 리시빙 완료(13:54)와 Apply 사이의 시차 동안 그 재고가 판매 픽킹 등으로 **이미 움직일 수 있다**. "한 건 실패"를 전제로 설계해야 한다.
    - → **그룹 실패는 수집만 하고 다음 그룹으로 진행**(루프에서 throw 금지 — 되돌릴 수 없는 구간이므로. 규칙 27 R12·R10). 수집 형태 `failed_moves:[{bin, skus[], qty, http_status, cin7_error}]` — `cin7_error` 는 Cin7 응답의 `Exception` 원문("Available quantity … is 0")이라 사람이 바로 원인을 안다. 응답 최상위 + `apply_note` 에 `failed_moves(N): [...]` 로 노출.
    - **부분 성공에서도 receipt PATCH(`applied_at`)까지 도달한다** — 실패해도 receipt 이 큐에 갇히고 discrepancy 만 남는 상태를 만들지 않는다. 대신 **실패가 하나라도 있으면 눈에 보이게**: admin History 의 CIN7 열이 `✓ Applied` 대신 **`⚠ Applied (N bins failed)`**, Apply 목록엔 그대로 남고 버튼이 `Retry failed bins`. **판정 기준은 `failed_moves.length > 0`** (log 의 WARN 문자열 아님).
    - **재시도**: 실패 그룹은 `exported_base` 를 안 찍으므로 사람이 Cin7 에서 재고를 바로잡고 **다시 Apply 하면 실패분만** 재시도된다. 이를 위해 `buildApplyPlan` 이 **`applied_at` 이 있어도 재개를 허용**한다 — 게이트 두 겹: ①`apply_note` 에 `failed_moves(N)` N>0 (트랜스퍼만) ②실제로 옮길 그룹이 남아 있음. `plan.mode="resume"` · `plan.retry=true` · 원 TR 은 COMPLETED 이므로 PUT 은 계속 SKIP · discrepancy 선기록은 `ignore-duplicates` 로 안전 재실행. ⚠️ **`failed_moves(N)` 포맷은 EF 정규식과 admin.html 이 공유한다 — 한쪽만 바꾸지 말 것.**
    - ⚠️ **재고 부족은 자동 보정하지 않는다** — 조정은 사람이 Cin7 에서(규칙 27 R13). ⚠️ **PO 경로에는 아직 같은 보호가 없다**(bin 별 `POST /purchase/stock` 중 하나가 실패하면 여전히 전체 throw) — 규칙 27 R10.
- **이중 반영 방지 (2026-07-24 강화)**: `wms_receipts.applied_at` 있으면 Apply·열기·재개 모두 거부. **한 PO = receipt 1개 강제**: startPo 가 그 PO 의 기존 receipt 전체 조회 → applied 있으면 "이미 받음" 차단, 미완료 있으면 이어받기(새로 안 만듦). 예전엔 `neq status completed` 만 봐서 applied 된 PO 에 새 receipt 이 중복 생성되던 버그. factor 로 안 나눠떨어지는 수량은 에러 차단. Apply 성공 시 status='completed' 명시(applied 인데 in_progress 로 꼬이는 것 방지).
- **자동 실행 강도**: 현재 = 매니저 admin 게이트(dry-run 계획 confirm → commit). 신뢰 쌓이면 작업자 완료 시 자동으로 전환 예정(EF 호출 위치만 이동).
- 쓰기 검증 도구: `WmsTransferWriteTest.gs`·`WmsPoStockWriteTest.gs` (System_Automation, DRY_RUN 게이트 패턴 — 새 쓰기 검증 시 재사용).
- 📌 **TR-02935 착지·수량 실측치와 Apply 운영 규칙(실행시간 예산·수동 이동 충돌·체크포인트 불가침)은 규칙 30** · **bin↔bin 이동 화면 설계는 규칙 33** · **재고 대조 리포트는 규칙 32**.

## 규칙 22 — 배터리 최적화: heartbeat 제거 → 스캔 이어받기 (⚠️ 2026-07-24)

태블릿 배터리 소모 이슈. 진단: HTML 자체가 아니라 (1)화면 상시 켜짐(디스플레이, 최대) (2)realtime presence 웹소켓 (3)20초 heartbeat 타이머 (4).live 펄스 애니. **Wake Lock 은 없음**(화면 설정 그대로 먹음 — 숨은 주범 아님).

- **heartbeat 완전 제거** (picker/packer): `HB_MS`/`beatOnce`/`hbTimer`/setInterval 삭제 → **정지 시 네트워크·CPU 0.** `startHeartbeat`/`stopHeartbeat`/`idleMin`/`staleISO` 는 no-op 스텁으로 남겨 잔여 호출 안전.
- **realtime presence 는 유지** (사용자 결정 — 생산성/LIVE NOW 우선). presence 는 웹소켓 이벤트라 heartbeat 타이머보다 가벼움.
- **heartbeat 의 원래 목적 = "열어만 두고 방치된 오더가 남에게 안 보이는 문제" 방지.** 하지만 픽리스트를 **물리적으로 인쇄**해 드는 구조라 소유권은 종이가 보증 → 상시 heartbeat 불필요. **대체 = 스캔 이어받기**: 픽리스트 스캔 시 그 오더가 이미 남이 in_progress 로 잡았으면 "X 가 열어둠, 이어받기?"(진행분 보존) → `assigned_to=me` UPDATE. (picker `scanTakeover`, packer `scanTakeoverPack`). 대기목록은 순수 pending 만(시간기반 abandoned 제거).
- **admin BATCH ACTIVITY active/idle → presence 기반** (`fresh(t)=liveBatchSet().has(t.batch_label)`). heartbeat_at 시간 판정 폐기. 🟢 active(open on screen) / 🟡 away(screen closed). **LIVE NOW 스트립은 원래 presence 라 무관 — 그대로 유지.** 범례도 idle→away 로.
- **pg_cron reaper `wms_reap_stale_claims()`**: 느슨한 백업만(work_started=false 인 유령만 해제). heartbeat 없으니 interval 넉넉히(현재 2분 → 권장 3~10분). 스캔 이어받기가 주 해결책이라 사실상 보조.
- `heartbeat_at` 컬럼은 DB 에 잔존(안 읽고 안 씀) — 나중에 drop 가능.
- ⚠️ **"종이가 소유권을 보증한다" 전제가 깨지는 경우와 그 가드는 규칙 28** 참조(종이는 보드로 돌아갔는데 화면은 열려 있는 상태).

---

## 규칙 23 — Hold 이어가기(held_by) · 픽리스트 Reference (2026-07-25)

- **held_by (Hold 한 사람에게 우선 노출)**: Hold 는 `assigned_to=null, status=pending` 으로 풀어 **누구나 이어받게** 두되 **`held_by=me.name`** 을 남긴다. picker/packer 목록 맨 위에 **"⏸ Resume your held batch"** 강조 섹션(held_by=나 인 pending). claim 시 `held_by=null` 로 정리. **서버 저장이라 화면 닫거나 다른 태블릿에서 로그인해도 보임**(브라우저 로컬은 복귀 시나리오에 부적합 — 아티팩트 localStorage 금지도 있음). 여전히 대기 풀에 있으므로 급하면 남도 집을 수 있음(= "내 것 잠금" 아님, 종이 픽리스트가 소유권). SQL `wms_held_by.sql`(pick_tasks/pack_tasks/waves 에 held_by). ⚠️ **Hold 를 눌러도 그 사람의 화면은 계속 열려 있고 계속 쓸 수 있다 — 소유권 가드는 규칙 28**(`assigned_to=null` 도 프리즈 대상).
- **픽리스트 Reference**: 화면 Cin7 "Reference"(예 `WDC-20260723`, 고객 발주번호) = **API `CustomerReference`** (기존 실측 주석 확정: Comments=`Note`, Shipping notes=`ShippingNotes`, Reference=`CustomerReference`). 폴링 EF(`hello`)가 `extractReference(d)` 로 `wms_orders.reference` 저장 → manager 픽리스트·**wave 픽리스트 둘 다** Order 줄 아래 인쇄(값 없으면 줄 생략). SQL `wms_order_reference.sql`. ⚠️ 컬럼 추가를 EF 배포보다 먼저(없으면 insert 실패). 기존 오더는 null → 신규 유입분부터 인쇄됨.

## 규칙 24 — 리시빙 동시 작업: 한 PO 를 여러 명이 나눠 받는다 (⚠️ 2026-07-27)

**배경**: 이 기능은 설계된 게 아니라 **의도치 않게 가능했고 현장에서 정착됐다**(큰 컨테이너를 두 사람이 SKU 나눠 스캔). 안전성 감사 후 아래 4개를 고쳐 **정상 기능으로 승격**했다. 되돌리면 남의 작업이 조용히 사라진다.

- **저장 모델 = 라인 단위 (`unconfirmed` Map + `writeChain`)**:
  - `unconfirmed`(line.id → {kind:qty|putaway|all})는 **"쓰려 했지만 1행 반영을 확인받지 못한 라인"만** 담는다. ⚠️ "건드린 전부(touched)"를 담으면 안 된다 — 이미 저장된 라인을 Hold/완료 때 다시 써서 그 사이 남이 바꾼 값을 스테일 스냅샷으로 되돌린다. 정상 경로에선 이 집합이 **비어 있다**.
  - **성공 판정 = `.select()` 반환 1행 확인.** ⚠️⚠️ PostgREST 는 **0행 매치도 `error=null`/204** 로 돌려준다. 그걸 성공으로 오판하면 라인이 `unconfirmed` 에서 잘못 빠져 **안전망이 사라진다**. 0행이면 `lineGone(id)` 로 갈라 판정: 삭제됨(매니저 off-PO reject) → 로컬에서도 `dropLine` / 그 외 → conflict 로 남겨 재시도.
  - **`writeChain` = 라인별 PATCH 직렬화.** 같은 라인의 쓰기가 서로 추월하면 늦게 도착한 옛 값이 DB 에 남고, 전체 배열 덮어쓰기를 없앤 뒤에는 그걸 뒤늦게 바로잡아 줄 코드가 없다. **라인별**이라 느린 라인이 다른 라인을 막지 않는다. 보낼 필드(`patchFor`)는 **호출 시점의 라인 값**에서 만들어 큐에 밀린 쓰기가 자동으로 최신값이 되게 한다.
- **⚠️ Hold / finishReceipt 는 `lines` 전체 배열을 덮어쓰지 않는다.** `flushUnconfirmed()`(실패분만 재시도) + `wms_receipts` **헤더 patch** 만. 예전의 "최종 라인 저장(authoritative)" 전체 루프가 **같은 receipt 를 함께 받던 사람의 수량·bin·placed 를 전부 되돌리던 원인**이었다. **이 루프를 되살리면 안 된다.**
- **완료 요약은 반드시 서버 재조회(`serverChecks()`)**. 메모리 스냅샷으로 계산하면 **남이 받은 물량이 전부 short 로 표시된다**(분할 수령에서 기존 동작은 이미 틀렸다). 순서도 고정: `preFinish()` = ①내 미확인분 flush ②서버 재조회 ③확인 다이얼로그. Apply 계획도 DB 를 읽으므로(EF `buildApplyPlan`) **진실은 DB 쪽**. `mergeServerRows` 는 `unconfirmed` 걸린 라인은 건너뛴다(내 값이 더 최신) + **값만 갱신하고 배열은 안 건드린다**.
- **presence = 기존 `wms-presence` 채널 재사용**, key = `me.name+"|receiver:"+receipt.id`. 헤더에 "🟢 also here: X" 배지. ⚠️ **track 페이로드에 `batch` 필드를 넣지 말 것** — admin `liveList()` 가 batch 있는 멤버만 워커로 집계하고 screen 을 Picking/Packing 으로만 표시해서, receiver 가 섞이면 **Picking 으로 오표시**된다. 구분 필드는 `screen:"receiver"` + `receipt`/`po`.
- **⚠️ 타이머 폴링 금지** — 규칙 22(배터리). presence 는 이벤트 기반이라 OK. `wms_receipts.updated_at` 갱신은 `bumpReceipt()` 로 debounce(스캔당 요청 2개 → 1개).
- **Complete 는 누가 눌러도 데이터가 안전**하다(전체 덮어쓰기 제거 + 서버 요약). 단 **모두 끝난 뒤 눌러야 한다** — 아래 R5 참조.

## 규칙 25 — 라인 식별은 id 기반이 컨벤션 (⚠️ 2026-07-27)

`bcMap`·수량 핸들러·커서는 **배열 인덱스가 아니라 `line.id`** 로 라인을 찾는다.

- `bcMap[code] = [{id, factor}]`, 스캔은 `lineById(id)` 로 해석(죽은 id 는 자연히 걸러짐). 스테퍼·수동입력·autoAdvance 커서도 동일.
- **⚠️ 인덱스 기반이면**: `dropLine` 이 `lines.splice()` 한 뒤 `buildBcMap()` 재조립을 끝내기까지의 **왕복 창에서 스캔이 엉뚱한 SKU 에 수량을 넣는다.** id 기반이면 splice 후 재조립 자체가 불필요.
- 풋어웨이 뷰는 원래 id 기반이었고 **리시빙 검수만 인덱스**였다 — 2026-07-27 통일.
- ⚠️ **`picker.html`·`packer.html` 은 아직 인덱스 기반.** 지금은 안전(그 화면들은 `lines` 를 splice 하지 않는다). **lines 를 splice 하는 기능을 추가하면 같은 함정** → 백로그.

## 규칙 26 — 검수 표시 순서: 채운 라인만 아래로 (⚠️ 2026-07-27)

- **`isFilled(l) = l.expected>0 && l.received===l.expected`**(주문 수량을 정확히 채움) 인 라인만 리스트 아래로 내린다. **short 는 아직 할 일, over 는 매니저 확인 필요, 오프-PO(expected=0)는 승인 대기** → **전부 위에 유지**(isFilled 가 expected>0 을 요구하므로 오프-PO 는 자동). 완료된 라인끼리는 원래 순서를 지킨다(방금 스캔한 게 위로 튀면 "아까 뭘 찍었지"가 어려워짐).
- **정렬은 렌더 시점에만** — `orderedIdx()`/`sortedIdx()` 가 표시 인덱스만 만든다. ⚠️ **`lines` 배열 재정렬 금지**(bcMap·커서·스캔 무결성). 규칙 20 의 정렬 4종과 같은 원칙, 1차 키만 추가된 것.
- ⚠️⚠️ **`autoAdvance` 는 표시 순서가 아니라 `sortedIdx(false)`(완료 그룹화 없는 순수 sortMode 순서)로 걸어야 한다.** 표시 순서로 다음을 찾으면 방금 채운 라인이 맨 아래로 내려간 탓에 뒤가 비어 **매번 리스트 맨 위 미충족 라인으로 되돌아간다** — 존 순서로 걷던 작업자가 이미 지나온 존으로 끌려간다. `orderedIdx()=sortedIdx(true)`, `autoAdvance`/걷기 = `sortedIdx(false)`.
- 비교는 **base 단위**(expected/received = expected_base/received_base, 스캔은 이미 factor 곱함 — 규칙 3).

## 규칙 27 — 리시빙 동시 작업: 알려진 위험 (⚠️ 미해결 — 2026-07-27 감사)

규칙 24 로 "남의 작업이 사라지는" 급은 없앴지만 **아래는 그대로 남아 있다.** 리시빙을 건드릴 때 이 목록을 먼저 볼 것.

- **R1 — 같은 라인 동시 스캔 = last-writer-wins.** 두 사람이 같은 SKU 를 찍으면 한쪽 수량이 조용히 덮인다. 현재는 **팀 규칙으로 SKU 분담**(사람마다 다른 SKU) 중. 해결책 = **PostgREST 조건부 UPDATE(CAS)** — `.eq("received_base", 읽은값)` 로 보내고 0행이면 재조회 후 재시도. `writeChain`(라인별 직렬화)과 `.select()` 1행 판정이 **CAS 의 전제조건**이라 규칙 24 가 이미 절반을 깔아뒀다.
- **R3 — `wms_receipts.cin7_purchase_id` 에 유니크 없음.** (`wms_orders.cin7_sale_id` 는 유니크 있음 — baseline `wms_orders_cin7_sale_id_key`.) 밀리초 동시 진입이면 **중복 receipt 가능**. 현재 **중복 데이터 0건 확인**. 분할 입고는 새 PO 로 처리하므로 **유니크 제약을 걸어도 됨**(새 마이그레이션으로).
- **R4 — Apply 중복 실행.** `applied_at` 가드가 **read-then-check**(EF 진입 시 1회 확인)이고, EF 최종 PATCH 에 **`applied_at=is.null` 필터가 없다.** Cin7 쓰기가 수십 초라 그 창에서 두 번째 Apply 가 통과하면 Cin7 에 이중 반영. 해결 = 최종 PATCH 에 `applied_at is null` 조건 + 1행 확인(규칙 24 와 같은 패턴).
- **R5 — Complete 후 Apply 진행 중 스캔되면 그 수량은 영구 미적용.** Apply 는 Complete 시점의 DB 를 읽고, 끝나면 `applied_at` 이 찍혀 재적용이 막힌다. → **모두 끝난 뒤 Complete 를 누를 것**(데이터는 안전하나 반영은 못 됨).
- **R10 — bin 루프가 비트랜잭션 (⚠️ 비원자성은 여전 · 다만 2026-07-28 부터 부분 실패가 기록되고 재시도 가능하다).** bin 별 분할 POST(규칙 21) 중간에 실패하면 **Cin7 에 DRAFT/부분 이동이 남는다**. 원자성은 없고 앞으로도 없을 것이다(Cin7 에 트랜잭션이 없다) — 대신 **부분 실패를 정상 상태로 다루는 쪽**으로 바꿨다:
  - **트랜스퍼**: 그룹 실패는 `failed_moves[{bin,skus,qty,http_status,cin7_error}]` 로 **수집만 하고 루프를 계속**한다(throw 금지 — R12 의 "쓰기 뒤" 방향). 성공 그룹은 `exported_base` 체크포인트를 찍고, 실패 그룹은 안 찍으므로 **재Apply 하면 실패분만 재시도**된다(`applied_at` 이 있어도 `failed_moves(N)` + 남은 그룹이 있으면 재개 허용). `applied_at` 은 부분 성공에서도 찍히되 admin 이 **`⚠ Applied (N bins failed)`** 로 구분 표시한다. 남는 구멍: 체크포인트 PATCH 자체가 실패하면 WARN 만 남고 재Apply 가 그 bin 을 두 번 옮긴다.
  - **PO 경로는 아직 그대로다** — 체크포인트도 없고 bin 별 `POST /purchase/stock` 중 하나가 실패하면 전체 throw → 앞서 성공한 DRAFT 는 Cin7 에 남고 재시도 시 중복 POST. **같은 원칙(수집 후 계속 + 체크포인트)이 필요하다 — 백로그.**
  - ⚠️ **운영 주의 — 리시빙 완료와 Apply 사이에 재고가 움직인다.** 시차가 벌어지면 착지 지점의 재고를 판매 픽킹 등이 먼저 가져가고, bin 이동은 400 `"Available quantity … is 0"` 로 거부된다(실측 TR-02935 / AS97745). **정상적으로 발생하는 상황**이므로 ①Apply 를 완료 직후에 돌리는 게 좋고 ②실패는 사람이 Cin7 재고를 바로잡은 뒤 재Apply 로 처리한다(자동 보정 없음 — R13).
- **R11 — 쓰기 실측의 근거는 HTTP 200 이 아니라 GET 으로 되읽은 값이다 (2026-07-28 교훈).** 트랜스퍼 완료 수량 변경이 "허용된다"는 기록이 **200 만 보고** 남았고, 실제로는 Cin7 이 조용히 무시하고 있었다(규칙 21 정정 항목). **되돌릴 수 없는 쓰기를 새로 실측할 때는 반드시 저장값을 되읽어 확인하고, 그 값을 근거로 기록할 것.**
- **R12 — 되돌릴 수 없는 Cin7 쓰기 앞에 Supabase 기록을 먼저 (2026-07-28 원칙 확립).** Cin7 쓰기는 사실상 롤백이 없고 WMS 기록은 언제든 다시 쓸 수 있다 → **순서는 항상 "Supabase 먼저 → Cin7 나중"**, 그리고 **선기록이 실패하면 Cin7 을 건드리지 않고 중단**한다.
  - 사례 **TR-02935**(첫 에드먼튼 트랜스퍼 Apply): discrepancy 기록이 applyCommit **맨 마지막**에 있어서 ①원 TR 은 COMPLETED 됐고 ②bin 이동이 `/ref/location` Limit 잘림으로 첫 건부터 throw → ③receipt PATCH 미실행(`applied_at` null → 큐에 남고 Applied 배지 없음) ④**discrepancy 기록 통째로 유실**(차이를 되찾을 방법이 사라졌다) ⑤plan 검증이 "IN TRANSIT 이어야 함" 이라 재Apply 도 막혀 영구히 갇힘.
  - → discrepancy 는 **Cin7 쓰기 앞**으로 이동(실패 시 throw), 재개 경로는 COMPLETED 허용, 체크포인트는 `exported_base`. **이 세 개가 한 세트다.**
  - ⚠️ 반대 방향(되돌릴 수 없는 쓰기 **뒤**의 Supabase 기록 — receipt PATCH·`exported_base`)은 여전히 **throw 금지**다. 이미 Cin7 이 바뀐 뒤이므로 중단하면 상태만 더 갈라진다(규칙 21).
- **R14 — Apply 1회가 EF 실행 시간 한도를 넘는다(대형 트랜스퍼).** 144 bin 그룹 = 1회에 안 끝나고, 타임아웃으로 죽으면 `applied_at`·`apply_note` 가 **둘 다 null** 이라 실패 목록조차 안 남는다 → **규칙 30**(회차당 처리 그룹 상한이 필요).
- **R15 — Apply 대기 중 사람이 Cin7 에서 수동 이동하면 충돌한다.** 규칙 28(픽 중복)과 같은 종류이고 상대가 WMS 자신이다 → **규칙 30**.
- **R16 — 스키마 기록(“적용됨”)이 실물 DB 와 다를 수 있다.** 부분 유니크 인덱스가 `on_conflict` 를 깨뜨려 **리시빙 discrepancy 가 구현 이후 한 번도 기록되지 않았다** → **규칙 29**.
- **R13 — Discrepancy 큐가 방치되면 재고가 계속 틀린 상태로 남는다 (⚠️ 미해결 · 새 정책의 구조적 대가).** 조정은 **사람이 Cin7 에서 수동**으로 하고(자동 adjustment·보정 트랜스퍼 모두 의도적으로 채택 안 함), 트랜스퍼는 완료 수량이 **보낸 수량으로 고정**되므로 **큐를 처리하지 않으면 Cin7 재고가 실물과 계속 어긋난다.** 게다가 캡 때문에 남은 잔량은 착지 지점(집결 bin 또는 창고 no-bin)에 그대로 앉아 있다. 현재 안전장치는 admin Discrepancy 탭 배지(미해결 건수)뿐 — **경과일 알림·에이징 리포트는 없다.**
- **RLS** — `wms_receipts`·`wms_receipt_lines` 정책이 `using(true)`(auth_all). **창고 스코프는 클라이언트 필터뿐** — 로그인한 직원이면 다른 창고 receipt 도 API 로 읽고 쓸 수 있다.
- **EF 권한** — `receiving` EF 에 **호출자 검증이 없다**(anon Bearer 면 통과). Apply 권한(perms `apply`)은 **admin.html 클라이언트 사이드 3중 게이트뿐**이고, `applied_by` 는 쿼리스트링 `&by=<name>` 이라 **위조 가능**. 서버측 검증(JWT → wms_staff perms 확인)은 미구현.

## 규칙 28 — 픽 소유권 가드: 종이와 클레임이 갈라질 때 (⚠️ 2026-07-28 실사고)

**사고 경위 5단계**
1. 픽커 A 가 보드에서 오더 001 픽리스트를 떼어 태블릿에 로드했다.
2. 매니저가 홀드 지시 → A 는 픽리스트를 **보드에 다시 붙였고 WMS 화면은 그대로 뒀다**.
3. 픽커 B 가 그 픽리스트를 떼어 스캔 → `scanTakeover` 로 클레임이 B 에게 넘어갔다(**여기까지 WMS 정상 동작**).
4. A 도 "픽해도 된다"는 말을 듣고 **이미 로드된 화면에서 그대로** 픽을 시작했다. A 는 재스캔이 필요 없었으니 이어받기 프롬프트를 볼 일이 없었다.
5. A·B 가 같은 오더를 동시에 픽하고 **같은 `wms_pick_task_lines` 에 수량을 썼다.**

**규칙 22 전제가 깨지는 조건.** 규칙 22 는 heartbeat 를 없애며 "소유권은 **종이 픽리스트**가 보증한다"를 전제했다. 이 전제는 **종이와 클레임이 항상 함께 움직일 때만** 성립한다. 종이가 보드로 돌아가고 **클레임(=열린 화면)만 남으면** 물리 상태와 디지털 상태가 갈라지고, 그때 이미 열린 화면은 아무 확인 없이 계속 쓴다. ⚠️ **팀 규칙으로 못 막는다** — A 가 Hold 를 눌렀어도(규칙 23: `assigned_to=null`, `held_by=A`) A 의 화면은 여전히 열려 있고 여전히 쓸 수 있다.

**가드 = 쓰기 직전 + 복귀 시점의 소유권 재확인** (picker/packer 각각 `checkOwner`/`ensureMine`/`freezeScreen`/`guardOnReturn`)
- **쓰기 직전**: picked/verified 수량·상태를 쓰는 모든 경로에서 `pick_tasks`(packer 는 `pack_tasks`) `assigned_to` 를 **단일 컬럼 select** 로 재조회해 `me.name` 과 비교. 관문은 **`saveLine`**(스캔 가산·스테퍼·수동 입력이 전부 여기로 모인다) + **Hold** + **Complete / Complete as incomplete**(packer 는 Pack fill·Over-scan 확인을 **끝낸 뒤**).
- **복귀 시점 감지가 실질적으로 가장 중요**: `visibilitychange`(hidden→visible) + `focus` 에서 같은 확인. 태블릿을 두고 나갔다 몇 분 뒤 돌아오는 게 실제 시나리오라 **첫 스캔 전에 잡히는 게 이상적**이다.
- ⚠️ **타이머·폴링 금지**(규칙 22 배터리). **이벤트 기반만. heartbeat 를 되살리지 마라.** 이벤트가 연속으로 튈 때 중복 조회만 `lastOwnerCheck` 타임스탬프(3초)로 억제 — setInterval 아님.
- **wave 는 소유권이 wave 단위**(규칙 18)라 `wms_waves` 행의 `assigned_to` 를 본다. **멤버 task 개별 확인은 하지 않는다**(wave 행 하나로 충분, 쿼리만 늘어난다).

**프리즈 동작**
- 스캔 입력 `disabled` + 수량 조작 버튼 전부 비활성. **렌더 우회로를 남기지 말 것** — 핸들러 `if(frozen) return` 만으로는 부족하고 `renderSingle`/`renderList` 의 스테퍼·수동입력에 `disabled` 를 함께 넣어야 한다(`focusScan` 도 프리즈면 즉시 반환).
- 모달(UI 영어 — 규칙 11): 다른 사람 → `This batch is now assigned to {name}. Your screen is out of date.` / `assigned_to` 가 **null** → `This batch was released and is waiting to be claimed.` **버튼은 리로드 하나만 — 계속 진행하는 선택지를 주지 않는다.**
- ⚠️⚠️ **프리즈 시 로컬 수량을 flush 하지 마라.** 내 메모리 값은 스테일이고, 쓰면 **이어받은 사람의 작업을 덮는다.** 규칙 24 에서 "Hold/finish 의 전체 배열 덮어쓰기"를 제거한 것과 **같은 이유** — 로컬 상태는 버리고 **서버를 진실로** 둔다.
- ⚠️ **null(Hold 로 풀림)도 프리즈 대상이다.** 대기 풀로 돌아간 상태이므로 그때 내 화면이 계속 쓰면 남이 이어받은 뒤 충돌한다.
- 정당하게 이어받고 싶으면 **픽리스트 재스캔(`scanTakeover`)** 경로를 쓴다 — 이미 검증된 진입로다. 가드는 그 경로를 건드리지 않는다.

**실패 처리 & 한계.** 확인 select 가 네트워크 오류로 실패하면 **프리즈하지 말고 쓰기를 진행한다**(창고 와이파이 순단으로 작업이 멈추는 게 더 큰 손실). 콘솔 warn 만. 즉 이 가드는 **best-effort** 이고 원자적이지 않다 — 확인과 UPDATE 사이의 밀리초 창에서 넘어가면 통과한다. **후속: claim_seq(클레임 시퀀스) 로 원자화** — 클레임마다 증가하는 정수를 task 행에 두고 UPDATE 를 `.eq("claim_seq", 진입 시 읽은 값)` 조건부로 보내 0행이면 프리즈. 규칙 27 R1 의 CAS 와 같은 패턴이라 함께 처리.

## 규칙 29 — 스키마 기록의 진실은 실물 DB 다: 부분 유니크 인덱스가 `on_conflict` 를 깨뜨렸다 (⚠️ 2026-07-29 실사고)

**증상.** 리시빙 Apply 시 Supabase 가 **400 / `42P10 there is no unique or exclusion constraint matching the ON CONFLICT specification`**. EF 는 `POST wms_discrepancies?on_conflict=receipt_id,sku` 로 선기록(규칙 27 R12)하므로 **discrepancy 기록 실패 = Apply 중단**이 되어 Cin7 을 아예 못 건드렸다.

**원인.** baseline 의 인덱스가 **부분(partial) 유니크**였다:
```sql
CREATE UNIQUE INDEX uq_disc_receipt_sku ON wms_discrepancies (receipt_id, sku)
  WHERE (receipt_id IS NOT NULL);   -- ← 이 WHERE 가 문제
```
**PostgREST 의 `on_conflict` 는 부분 인덱스를 추론하지 못한다**(Postgres 의 `ON CONFLICT (cols)` 추론이 predicate 를 요구하는 것과 같은 이유). 인덱스는 존재하는데 upsert 대상으로 지목할 수 없다.

**조치 = WHERE 절 없는 전체 유니크로 교체.** `receipt_id` 가 NULL 인 pick/pack 행은 유니크의 **NULLS DISTINCT**(Postgres 기본) 때문에 서로 충돌하지 않으므로 영향이 없다 — 부분 인덱스로 얻으려던 것을 기본 동작이 이미 해준다.
```sql
DROP INDEX IF EXISTS uq_disc_receipt_sku;
CREATE UNIQUE INDEX IF NOT EXISTS uq_disc_receipt_sku ON public.wms_discrepancies (receipt_id, sku);
```
SQL 은 **`supabase/wms_disc_uq_fix.sql`** 에 남겼다. ⚠️ 이 파일은 **기록/응급용이고 마이그레이션이 아니다** — 「DB 스키마 변경 절차」대로 `supabase migration new disc_uq_fix` 로 같은 내용을 새 마이그레이션에 담아야 로컬·원격이 다시 정렬된다(위 SQL 은 멱등이라 이미 원격에 적용됐어도 안전).

**⚠️⚠️ 파급 — 리시빙 discrepancy 는 구현 이후 한 번도 기록된 적이 없었다.** 즉 규칙 20 의 차이 처리 정책(“차이는 큐에 남기고 매니저가 Cin7 에서 수동 조정”)이 **문서상으로만 동작**하고 있었다. 트랜스퍼는 완료 수량이 보낸 수량으로 고정되므로(규칙 20 트랜스퍼 예외) **이 큐가 유일한 보정 근거**인데 그게 비어 있었다는 뜻이다. Health 의 `short_no_disc` 는 **픽킹 전용**이라 이걸 못 잡았다(규칙 19).

**⚠️ 교훈 — 스킬에 "적용됨"으로 적힌 스키마를 신뢰하지 말고 실물 DB 로 확인한다.**
```sql
select indexname, indexdef from pg_indexes where tablename='wms_discrepancies';
select conname, pg_get_constraintdef(oid) from pg_constraint
 where conrelid='public.wms_discrepancies'::regclass;
```
- 이 규칙은 **스키마 관련 서술 전부에 적용된다**(references/schema.md 포함). 문서가 아니라 `pg_indexes`/`information_schema` 가 근거다.
- 함께 볼 것: 규칙 27 **R11**(쓰기 실측은 200 이 아니라 되읽은 값) — 같은 종류의 "성공했다고 믿었는데 아니었다" 계열이다.
- **부분 인덱스는 upsert 키로 쓰지 말 것.** PostgREST `on_conflict` 를 쓸 컬럼 조합에는 반드시 **전체** 유니크를 건다.

## 규칙 30 — Apply 는 한 번에 끝나지 않는다: 실행시간 예산 · 수동 이동 충돌 · 체크포인트 불가침 (⚠️ 2026-07-28~29, TR-02935 사후분석)

TR-02935(토론토→에드먼튼, **344 라인 / 144 bin 그룹**)를 실제로 닫으면서 나온 네 가지. 대형 트랜스퍼를 Apply 할 때 반드시 먼저 읽을 것.

### 30-1. 착지·수량 실측 (movement 리포트로 재확인)
- TR-02935 는 **(b) 케이스**: 헤더 `To` = **집결 bin EZ010101 의 GUID**, **344 라인 전량이 그 bin 에 착지**했다.
- **Cin7 이 받은 수량 = 보낸 수량**(실물과 다름): APR15412 **24**(실물 48) · APR16104 **6**(12) · APR48208 **12**(24) · AJA66008 **6**(12) · WOC40103 **12**(실물 6). → 규칙 20 트랜스퍼 예외 B 정책("완료 수량 = 보낸 수량 확정")의 **직접 근거**이고, `min(received, expected)` bin 이동 캡의 근거다.
- 초과/부족 보정은 **ST-00794 / ST-00795(재고 조정)로 사람이 처리**했다 — 자동 보정은 없다(규칙 27 R13).

### 30-2. ⚠️ EF 실행 시간 한도 → 회차당 처리 그룹 상한이 필요 (미구현 · 백로그)
- 실측: 144 bin 그룹 중 **1회차에 81 라인 이동 후 무응답 종료**. 이후 Apply 를 **3번 더 눌러 +43 라인**만 전진.
- ⚠️ **실패한 그룹이 매 회차 앞에서 다시 시도되어 시간 예산을 먹는다** → 회차당 전진량이 **81 → 약 14/회**로 급감한다(재시도 경로 자체는 의도된 동작 — 규칙 21 — 이지만 순서가 앞이라 뒤쪽 미처리 그룹에 시간이 안 남는다).
- ⚠️ **타임아웃으로 죽으면 `applied_at`·`apply_note` 가 둘 다 null 로 남아 실패 목록조차 안 남는다.** 남는 것은 성공 그룹의 `exported_base` 뿐 → 진행률을 사람이 역산해야 한다.
- **필요한 것**: 1회 Apply 당 **처리 그룹 상한(예 30~40)** + 응답·admin 배너에 **"N groups remaining, press Apply again"**. 상한은 EF 안에서 세고(규칙 21 `failed_moves` 와 같은 방식으로 응답 최상위에 노출), 미처리 그룹은 `exported_base` 가 안 찍혀 자연히 다음 회차로 넘어간다.

### 30-3. ⚠️ Apply 대기 중 Cin7 에서 수동 이동하면 충돌한다 (운영 규칙)
- TR-02935 실패의 **상당 부분이 `Available quantity … is 0`** — 사람이 이미 옮긴 재고를 WMS 가 집결 bin EZ010101 에서 꺼내려 한 것이다.
- **규칙 28(픽 중복)과 같은 종류의 사고이고, 상대가 WMS 자신이었다.** 물리 상태를 사람이 먼저 바꾸면 디지털 계획이 스테일이 된다.
- **조치**: ①admin Receiving 의 **Apply 대기 항목에 경고 문구**("Do not move this stock in Cin7 until Apply finishes") ②**운영 규칙으로 명문화** — Apply 대기 중인 문서의 재고는 Cin7 에서 손대지 않는다. ③Apply 는 **리시빙 완료 직후**에 돌린다(시차가 벌어질수록 충돌 확률이 올라간다 — 규칙 27 R10 운영 주의).

### 30-4. ⚠️⚠️ 체크포인트 컬럼을 수동으로 채워 receipt 을 닫지 마라
- TR-02935 를 닫으려고 `exported_base = least(received_base, expected_base)` 를 **344행 전체에 UPDATE** 했다. 그 순간 **"WMS 가 실제로 옮긴 것(124 라인)"과 "사람이 수동 처리한 것"을 구분할 신호가 사라졌다** → 남은 이동 목록을 **Cin7 movement 리포트에서 역산**해야 했다(규칙 32).
- **규칙: 강제 종료는 별도 마커로 한다** — `wms_receipts.closed_manually`(신규 컬럼 후보) 또는 `apply_note` 에 사유를 남기고, **`exported_base` 는 절대 손대지 않는다.**
- 이유: `exported_base` 는 **"Cin7 에 실제로 반영된 양"이라는 사실 기록**이고 재Apply 의 유일한 근거다(규칙 21). 여기에 추정치를 쓰면 그 뒤로는 어떤 재개도 신뢰할 수 없다. 규칙 28 의 "로컬 스테일 값을 flush 하지 마라"·규칙 24 의 "전체 배열 덮어쓰기 금지"와 **같은 원칙**: 사실 기록에는 추정을 쓰지 않는다.

## 규칙 31 — Cin7 원가 0 재고의 재평가 (⚠️ 미해결 — 2026-07-29 실측)

**목표**: 원가가 0 으로 들어간 재고 카드를 정상 원가로 재평가한다. **결론: 방법 미확정. 아래 실측만 확정.**

- Cin7 UI 의 재평가(Stock Revaluation) 화면은 **Non-zero stock** 탭과 **Zero stock** 탭 두 섹션이 있고, 문서상 "두 섹션을 함께 사용"한다고 되어 있다.
- ⚠️⚠️ **실측(1 SKU) — 두 섹션은 상계되지 않았다. 재고가 2배로 늘었다.** Non-zero 쪽에 0 을 넣어도 기존 수량이 **차감되지 않고**, Zero stock 쪽 입력이 **그대로 가산**됐다.
- **Non-zero 탭에는 unit cost 입력란이 없고, Zero stock 탭에만 있다** → "수량은 그대로 두고 원가만 고친다"를 한 화면에서 할 수 없다.
- **후보 (둘 다 미검증)**: ①**Zero stock 으로 정상 원가 재고를 추가한 뒤 별도 재고 조정으로 같은 수량을 감소**시켜 FIFO 가 0원 카드를 빼내게 하는 2단계 — ⚠️ 중간에 **재고가 2배인 구간**이 생기고(그 사이 판매가 잡히면 원가가 섞인다), `CostingMethod` 가 **FIFO-Batch/Serial** 이면 배치 지정 때문에 동작이 다르다. ②**원인 문서(0원으로 들어온 입고/조정)를 void 후 재작성.**
- 📌 **다음 단계**: 저가·저회전 1 SKU 로 ①을 **끝까지** 실측하고 movement 리포트로 카드별 원가를 되읽어 확인할 것(규칙 27 R11 — 200 이 아니라 되읽은 값이 근거).

## 규칙 32 — bin 재고 대조는 어느 Cin7 리포트를 쓰나 (⚠️ 2026-07-29 실측)

WMS 의 `putaway_bin` 기록과 Cin7 의 실제 bin 위치를 맞춰볼 때 **리포트 선택이 결과를 좌우한다.**

- ✅ **Inventory Products Stock Level Report 에 `Bin` 컬럼을 붙일 수 있다.** 컬럼: Location / SKU / Product / Brand / **Bin** / Unit / Qty on hand / Allocated / Unit cost / Stock on hand …  → **현재 bin 별 재고 스냅샷이 필요하면 이 리포트를 쓴다**(WMS `putaway_bin` 대조의 기본 도구).
- ⚠️ **Inventory Movement Details 는 `Reference` 필터를 걸면 유입만 보인다**(그 문서로 들어온 것만). **현재 위치를 알려면 필터 없이 뽑아 `(SKU, Bin)` 별 In − Out 을 넷아웃**해야 한다. TR-02935 의 남은 이동 목록을 이렇게 역산했다(규칙 30-4).
- ⚠️ **InventoryList CSV 의 `StockLocator`/`PickZones` 는 bin 수량이 아니다** — 제품 마스터의 참고 문자열이므로 재고 대조에 쓰면 틀린다.
- 📌 Health 검사 후보: `wms_receipt_lines.putaway_bin` vs **`asung_bin_stock`(BQ, 매일 6:30 스냅샷)** 대조 → "풋어웨이 기록과 Cin7 위치 불일치". ⚠️ **하루 지연이므로 실시간 용도는 아니다**(어제 이후의 이동은 못 본다). 백로그.

## 규칙 33 — Cin7 bin-to-bin 이동 화면 (설계만 — 백로그, 2026-07-29)

리시빙 풋어웨이와 별개로, **창고에서 자리를 옮길 때 쓰는 독립 화면**. API 근거는 전부 실측됨(규칙 21 · TR-03236).

```
POST /stockTransfer
{ Status:'COMPLETED', From:<bin GUID>, To:<bin GUID>,
  Lines:[{SKU, TransferQuantity}], SkipOrder:true }
```
- **같은 창고 bin↔bin 은 `InTransitAccount` 불필요**(TR-03236 실측). 수량은 델타라 절대값 사고가 없다.
- ⚠️ **트랜스퍼는 `From`/`To` 가 문서 레벨이라 한 문서에 여러 SKU 를 담을 수 있다** — `purchase/stock` 의 "문서당 bin 1개" 제약(규칙 21)과 **다르다**. 단 **bin 조합(From,To) 마다 문서 1개**로 쪼개야 한다.
- **단계**: **A 자유 이동**(SKU·수량·From·To 를 사람이 지정) → **B 풋어웨이 큐 소진**(receipt 의 `putaway_bin` 을 목록으로 띄워 소진). **A 를 먼저** — B 는 receipt 상태와 얽혀 Apply 경로와 충돌 여지가 있다.
- ⚠️ **`wms_sku_bins` 에 쓰지 말 것** — 매일 6:30 truncate + 재적재(규칙 6)라 조용히 사라진다. 위치의 진실은 Cin7 이고, 우리 기록은 **감사용 신규 테이블 `wms_bin_moves`**(sku·qty·from_bin·to_bin·warehouse·cin7_tr_number·moved_by·moved_at)에 남긴다.
- **미정**: 권한 범위(매니저 전용 vs 창고 직원 전체). 되돌릴 수 없는 Cin7 쓰기라 최소한 perms 키 하나(`binmove` 등)를 새로 두는 쪽이 안전하다.

## 현재 진행 상태 (2026-07-29 기준)

**전 기능 LIVE — wms.asung.ca. 리시빙 PO 경로 실전 성공. 트랜스퍼 창고간 = 첫 실전(TR-02935, 2026-07-28)이 실패해 재설계 배포 + 수동 마무리로 종료. 배터리 최적화 완료. 리시빙 동시 작업 정식 지원.**

**2026-07-28~29 세션 (규칙 29~33)**
- ✅ **discrepancy 유니크 인덱스 수정**(부분 → 전체) — `on_conflict` 42P10 으로 **리시빙 discrepancy 가 구현 이후 한 번도 기록되지 않았음**을 발견·해소. SQL `supabase/wms_disc_uq_fix.sql`. ⬜ **같은 내용을 새 마이그레이션으로 담아 로컬·원격 정렬**(사람이 `db push`). — 규칙 29
- ✅ **TR-02935 종료** — 4회 Apply(124 라인 이동) + 나머지는 Cin7 수동 처리, 초과/부족은 ST-00794/00795 재고 조정. 착지·수량 실측은 규칙 30-1.
- ⬜ **Apply 회차당 그룹 상한 미구현** — 144 그룹은 1회에 안 끝나고 타임아웃 시 `applied_at`·`apply_note` 가 둘 다 null. 규칙 30-2 (최우선 백로그)
- ⬜ **Apply 대기 중 수동 이동 경고 문구**(admin) 미구현 — 규칙 30-3
- ⚠️ **`exported_base` 수동 UPDATE 로 receipt 을 닫은 이력이 있다**(TR-02935) — 다시 하지 말 것. 규칙 30-4
- ⚠️ **원가 0 재고 재평가 = 미해결**(Non-zero 0 + Zero stock 재입력은 상계되지 않고 재고가 2배가 된다) — 규칙 31
- 📌 bin 재고 대조 리포트 확정(Stock Level Report + Bin 컬럼) — 규칙 32 · ⬜ bin↔bin 이동 화면은 설계만 — 규칙 33

**픽 소유권 가드 (2026-07-28 세션 — 규칙 28)**
- ✅ picker.html·packer.html: 쓰기 직전(`saveLine`/Complete/Hold) + `visibilitychange`·`focus` 에서 `assigned_to` 재확인 → 아니면 **프리즈**(입력·버튼 비활성 + 리로드 전용 모달, **로컬 수량 flush 안 함**). 타이머 0 유지(규칙 22). wave 는 `wms_waves` 행 기준. ⬜ 원자화(claim_seq)는 백로그.

**리시빙 동시 작업 (2026-07-27 세션 — 규칙 24~27) · 커밋 4개**
- ✅ **L1 라인 단위 저장**(`unconfirmed`+`writeChain`, `.select()` 1행 판정) / **Hold·finish 의 전체 배열 덮어쓰기 제거** — 함께 받던 사람 작업이 되돌아가던 근본 원인 해결
- ✅ **L3 완료 요약 서버 재조회**(`serverChecks`/`preFinish`/`mergeServerRows`) — 남이 받은 물량이 short 로 뜨던 오표시 해결
- ✅ **L4 presence 배지**("🟢 also here", `wms-presence` 재사용, batch 필드 없음 — admin 오표시 방지). 타이머 0 유지(규칙 22)
- ✅ **bcMap·수량 핸들러 id 기반화**(규칙 25) — dropLine 왕복 창의 엉뚱한 SKU 가산 제거
- ✅ **채운 라인 아래로 정렬**(규칙 26, `isFilled`/`sortedIdx`) — autoAdvance 는 `sortedIdx(false)` 로 동선 유지
- ✅ `printReceivingList` 오타 수정 — `receipt.source` → **`source_type`**(트랜스퍼가 PO 로 인쇄되던 문제)
- ⬜ **미해결 위험 R1·R3·R4·R5·R10 + RLS/EF 권한 — 규칙 27 참조.** R1 은 현재 팀 규칙(SKU 분담)으로 운영 중

**리시빙 (2026-07-24 세션 — PO 경로 완결)**
- ✅ **Cin7 stock received 3대 제약 실측 확정 & EF 반영**: 문서당 bin 1개(bin별 분할 POST) / 같은 SKU+bin 중복 병합 / **authorize=POST(PUT 405)**. 오래 헤맨 "Lines is invalid" 원인 = 여러 bin 한번에 → 해결. (규칙 21)
- ✅ **PO Apply to Cin7 실전 성공** — DRAFT(bin별) → authorize 자동까지. (PO-00965 검증)
- ✅ 빈 지정 스캔+드롭다운(빈자리 포함, EF action=bins) / 정렬 4종 / Zone→Bay sticky 점프 / Change 버튼 / 모바일 터치 / bayOfBin 파서 (규칙 20)
- ✅ admin **Review 버튼**(읽기요약+Reopen) / **Apply 권한**(perms `apply`, staff-admin 체크박스) / Resume-applied 필터 / **중복 receipt 방지**(한 PO=receipt 1개)
- ✅ 라스트빈 "no last bin" 근본 규명(sticky first_seen=7/6 한계, 버그 아님)
- ✅ **트랜스퍼 창고간 실측 완료 + EF 반영** (규칙 21): 완료=PUT COMPLETED·~~수량 초과 허용~~(⚠️ **2026-07-28 정정: 틀린 기록 — `TransferQuantity` 변경은 무시된다.** 규칙 21 정정 항목)·착지는 (a)bin 없이 창고 or (b)집결 bin 두 경우 → **From=det.To 로 통일**해 bin 이동. 워크플로는 **PO 와 동일**(받기→풋어웨이→Apply)로 확정.
- ✅ **차이 처리 정책 확립 + 구현**: 실물대로 Cin7 → 차이는 discrepancy 큐 → 매니저가 Cin7 수동 adjustment (규칙 20)
- ✅ **리시빙 리스트 프린트**(문서 바코드·라스트빈 정렬·체크박스) / **held_by Hold 이어가기** / **픽리스트 Reference**(규칙 23)

**배터리 최적화 (2026-07-24) — 규칙 22**
- ✅ picker/packer **heartbeat 전면 제거** → **스캔 이어받기**로 대체. admin BATCH ACTIVITY presence 기반(active/away). realtime presence·LIVE NOW 유지. reaper 는 느슨한 백업.

**백엔드 — 완료**
- ✅ 스키마: 운영 + 복제 2 + 신규(`wms_reports`·`wms_rollback_log`·`wms_waves`·**리시빙 `wms_receipts`/`wms_receipt_lines`**) + 컬럼추가(`perms`+**`apply`**·`fulfillment_type`/`finalized_by`/`finalized_at`·`note`·pick_tasks `wave_id`/`tote_no`·**`wms_orders.mgr_reviewed`**·**`wms_sku_bins.last_seen`**) — `references/schema.md`
- ✅ `wms_health_check()`(불변식 12검사) — 규칙 19. ✅ wave(`wms_waves.sql`) — 규칙 18. ✅ BQ→Supabase 동기화(`WmsSync.gs`). ✅ 자동 폴링 pg_cron `wms-poll-orders`. ✅ Edge Function `receiving` 배포(bin분할·authorize POST) — `references/edge-function.md`

**인증/권한 — 완료**
- ✅ 개인계정 Auth + `wms-auth.js`. RLS + auth_all. 세부권한 perms(split/admin/staff/stock/**apply**). 매니저 지정 완료.

**프론트엔드 — 완료 (7화면 + 리시빙 receiver.html)**
- ✅ 기본 7화면 + 영어화 + 로고 + Health 탭 + wave 모드. ✅ receiver.html(규칙 20). ✅ **헤더 규칙: ☰ Menu 는 유저이름 바로 옆**(전 화면).

**스키마 SQL — 전부 baseline 에 포함됨 (2026-07-26)**
예전에 하나씩 실행하던 `.sql` 파일들 — `wms_rollback_log`·`wms_reports`·`wms_schedule_polling`·`wms_staff_perms`·`wms_fulfillment_stats`·`wms_waves`·`wms_healthcheck`·`wms_receipts`+`wms_receipts_apply`·`wms_orders_review`·`wms_held_by`·`wms_disc_receiving`·`wms_order_reference` — 은 **모두 `supabase/migrations/20260101000000_baseline.sql` 에 흡수됐고 repo 에서 삭제됐다.**

- ✅ **실행할 것 없음.** 위 목록은 이력용. 다시 실행하지 말 것.
- 확인됨: `held_by`(pick/pack/waves) · `wms_orders.reference` · 리시빙 discrepancy 컬럼(`receipt_id` 등) 전부 baseline 에 존재.
- 예전의 "순서 의존"(`wms_waves.sql`→`wms_healthcheck.sql`) 도 baseline 안에서 이미 해결 — 신경 쓸 필요 없음.
- **앞으로의 스키마 변경은 새 마이그레이션만** — 위 「DB 스키마 변경 절차」. pg_cron 스케줄은 예외로 `supabase/ops/cron.sql` 에 기록(마이그레이션 아님).

## 백로그 / 미해결

### 리시빙 Apply — 최우선 (2026-07-29 갱신)

1. **Apply 회차당 처리 그룹 상한 (규칙 30-2)** — 예 30~40 그룹 + 응답·배너에 "N groups remaining, press Apply again". 지금은 대형 트랜스퍼가 EF 실행시간 한도에 걸려 **타임아웃으로 죽으면 `applied_at`·`apply_note` 가 둘 다 null**(실패 목록조차 안 남는다).
2. **트랜스퍼 (a) 케이스 첫 실전 Apply** — 첫 실전은 **TR-02935**((b) 집결 bin)였고 실패했다(규칙 20 트랜스퍼 예외 + 규칙 27 R12, 사후분석 규칙 30). ⚠️ **지금까지 실측한 트랜스퍼는 전부 (b)** 이고 **(a)(창고 GUID, bin 없이 착지)의 완료 후 bin 이동은 실전 경험이 없다** → **TR-03259 로 먼저 dry-run**.
3. **Apply 대기 중 수동 이동 경고 (규칙 30-3)** — admin Receiving 의 Apply 대기 항목에 경고 문구 + 운영 규칙 명문화.
4. **`apply_note` 정규식(`failed_moves(N):`) 파싱을 컬럼으로** — 지금 EF 와 admin.html **양쪽이 같은 포맷을 파싱**한다(드리프트 위험). `wms_receipts.failed_move_count`(또는 jsonb `failed_moves`) 컬럼으로 승격.
5. **admin.html 배너가 EF 캡 규칙을 JS 로 중복 계산** — 같은 판정을 두 곳에서 하지 말고 EF 응답 필드를 그대로 표시하도록.
6. **PO 경로에는 체크포인트가 없다** — bin 별 `POST /purchase/stock` 중 하나가 실패하면 **전체 throw**(앞서 성공한 DRAFT 는 Cin7 에 남고 재시도 시 중복 POST). 트랜스퍼와 같은 원칙(수집 후 계속 + `exported_base` 체크포인트) 필요 — 규칙 27 R10.
7. **discrepancy 유니크 인덱스 수정을 마이그레이션으로** — `supabase/wms_disc_uq_fix.sql` 내용을 새 마이그레이션에 담아 로컬·원격 정렬(규칙 29).
8. **리시빙 discrepancy Health 검사** — `short_no_disc` 는 픽킹 전용이라 규칙 29 의 사고를 못 잡았다(규칙 19).
9. **`wms_receipt_lines.putaway_bin` ↔ `asung_bin_stock` 대조 Health 검사** — 하루 지연 스냅샷이라 실시간 용도는 아님(규칙 32).
10. **R13 Discrepancy 큐 방치 시 재고 불일치가 계속 남는다** — 에이징 알림·리포트 없음(규칙 27 R13). ⚠️ 규칙 29 로 **큐 자체가 비어 있던 기간**이 있었으므로 과거분은 큐로 복원되지 않는다.
11. **R10 bin 루프 비트랜잭션** — 트랜스퍼는 부분 실패 수집 + 재Apply 로 운영 가능하지만 원자성은 아니다(체크포인트 PATCH 실패 구멍).

### 동시 작업 원자화
- **같은 SKU 다중 픽커 / 같은 라인 동시 스캔 (R1)** — PostgREST 조건부 UPDATE(CAS) 또는 RPC 증분.
- **`claim_seq`(A→B→A 스테일 화면) — 규칙 28 후속.** 현재 가드는 best-effort. R1 CAS 와 같은 패턴이라 함께 처리.

### 신규 기능
- **Cin7 bin↔bin 이동 화면 — 규칙 33**(A 자유 이동 → B 풋어웨이 큐. `wms_bin_moves` 감사 테이블 필요, `wms_sku_bins` 에 쓰지 말 것).
- **원가 0 재고 재평가 방법 확정 — 규칙 31**(미해결. 1 SKU 로 2단계 후보를 끝까지 실측).
- **박스 라벨에 스토어명 인쇄** — 스캔 배정으로 "박스=오더 하나"가 정착되면 가능. 프랜차이즈 창고가 박스를 열어보지 않고 스토어별 재분배할 수 있다(fulfillment 스캔 배정의 후속, 2026-07-29).

### 정리 필요 (데이터)
- TR-02935(수동 처리분) · 테스트로 만든 TR-03260(3개씩 완료됨)·TR-03261·TR-03267(수량 실측용) 재고 조정.

### 그 외 (기존)

- **리시빙 PO**: partial 상태 Cin7 draft 누적(현재 최종완료 때 일괄). Apply 자동 실행 전환(매니저 게이트→작업자 완료 시, 신뢰 쌓이면). Advanced Purchase 상세 라인 실측. 라스트빈 movements 백필(선택).
- **유령 bin 정리**: 숫자만/오타 bin 은 Cin7 삭제 후 sync 로 자연 소멸.
- **리시빙 동시 작업 미해결분 — 규칙 27 이 전체 목록** (위 「리시빙 Apply」·「동시 작업 원자화」에 안 담긴 것): **R3 `wms_receipts.cin7_purchase_id` 유니크**(중복 0건 확인, 분할 입고는 새 PO 라 걸어도 안전 — 새 마이그레이션) · R4 Apply 최종 PATCH 에 `applied_at is null` · R5 Complete↔Apply 창 · RLS 창고 스코프 · EF 호출자/perms 서버 검증.
- **인덱스 기반 bcMap 잔존**: picker.html·packer.html(규칙 25). 지금은 splice 를 안 해 안전 — 라인 삭제 기능 추가 시 반드시 id 기반으로 먼저 전환.
- **Cin7 병행 케이스 C 자동감지**: 유입 후 Cin7 상태 변경 감지.
- **GAS scannable_barcodes 근본수정**: base 라인에 형제변형(-12) 바코드 포함(현재 bcMap 병합 우회).
- 진단 로그(EF SENT) 유지 중 — 안정화 후 제거 가능.
- `wms_drop_locations` 비어있음.
- RLS 세분화(쓰기/해소=매니저만) — auth_all로 충분하나 운영 강화 시.
- is_selling 이상치 청소: CAN94629/-12·RSK53280/-12(변형 No로)·EBI00001~4(Cin7 수정 후 청소쿼리).
- 알림(작업완료 clean/flagged) 미구현. 미사용 SA `wms-edge-bq` 삭제 가능. private repo+$4/mo 고려.
- 스캔 오류음 추가강화(풀스크린 빨강 플래시 등)·팔렛/박스 완료 잠금 — 현장 피드백 대기.

## 개발 워크플로우 노트

- **환경 = WSL2 Ubuntu + bash.** 이전 기록의 PowerShell 예시(`Invoke-RestMethod`, `cd ~\asung-wms`)는 낡았다.
- Edge Function 배포: `cd ~/asung/asung-wms && supabase functions deploy hello` (Docker 불필요, "Docker not running" 경고 무시).
- 함수 호출(bash + 진짜 curl):
  ```bash
  curl -s "https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/hello?commit=1" \
    -H "Authorization: Bearer $ANON" | jq .
  # POST 바디는 파일로 넘기면 이스케이프 사고 없음
  curl -s -X POST ".../functions/v1/receiving" \
    -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" \
    --data @/tmp/body.json | jq .
  ```
- anon key로 호출(Authorization Bearer). service_role은 Edge Function 내부에서만(자동주입).
- 현재 함수명은 연습 함수 `hello`를 재활용 중(나중에 제대로 된 이름으로 새 함수 분리 가능).
- 집·회사 동등개발: 각 컴퓨터 CLI 설치 + `git clone`. **작업 후 `git push` 습관.** Supabase 클라우드(테이블·데이터·secrets·배포함수)는 어디서든 접근, 로컬 코드만 git 동기화 필요.

## 참조 파일

- `references/schema.md` — 14개 테이블(+`wms_waves`) + `wms_staff` 전체 컬럼·enum·인덱스, 복제 2테이블, `wms_health_check()` 함수, RLS
- `references/edge-function.md` — Edge Function 1~3단계 코드 구조, assembleLine 로직, 폴링/dedup/저장
- `references/sync-gas.md` — WmsSync.gs 구조, BQ 소스 쿼리, warehouse/zone 정규화 함수
- `references/frontend.md` — 8화면 구조(manager Split/Group·admin Health/Receiving 탭·picker wave 모드·**receiver 동시 작업 구현 지도**), wms-auth.js 로그인 모듈, RLS, 배포, 영어화·로고, 개발 워크플로우
