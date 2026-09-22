# PO(발주) 모듈 설계 — 정본

작성 2026-09-11 · ① Settings 완료 직후 (Caleb 지시 · 구조 방침 확정)
상위 문서: `docs/design/ims-principles.md` — **충돌하면 그쪽이 이긴다.**
요약·함정: `.claude/skills/asung-po/SKILL.md` — 이 문서를 가리키기만 한다. 실측 표·경위·대안은 전부 여기.

⭐ **구조 방침 (Caleb 확정 2026-09-11)**: 원장이 `ledger-design.md`(정본) + `asung-inv-ledger`(요약)로
나뉜 것과 **같은 구조로 처음부터 시작한다.** 근거: `asung-inv-ledger/SKILL.md` 가 190KB 를 넘어
오래된 기록을 옮겨야 하는 상태다. PO 는 같은 길을 가지 않는다 — **설계 정본 = 왜 그렇게 정했나 ·
실측 숫자 · 대안과 대가 · 경위. 스킬 = 모르면 사고가 나는 것만.**

1차 사료: 2026-09-11 마이그레이션 다섯의 헤더 주석(아래 §3 표의 파일명). 헤더가 정본이었던 것을
이 문서가 받는다 — 마이그레이션 헤더는 이미 커밋됐으므로 고치지 않는다.

---

## 1. 이 모듈이 무엇인가 · 만드는 순서

Cin7 Core 의 발주(Purchase)를 대체하는 IMS 세 번째 모듈. WMS(첫 모듈) · 재고 원장(둘째) 다음이다.
Cin7 을 베끼지 않고 **우리 표를 세우고 Cin7 을 매핑한다**(원칙 1) · 다른 모듈의 표를 읽지 않는다(원칙 2).

```
① Settings (8축)  ✅ 2026-09-11 완료 — 7축 · 사용자는 ~~wms_staff 확장(별건)~~ [2026-09-15] `ims_staff` 신설 — §10-h(`20260915141105`)
② 공급처           ✅ 범위·칸 확정 2026-09-11(§7-a) — 활성 226 만 담는다 · ~~표 셋(본체·주소·연락처)~~ [2026-09-12 정정] **표 넷 — §3-b**(`supplier_discount` 추가 · ~~§7-b~~ 2026-09-13 이사) · is_purchasable 은 우리 칸 — §8 supplier 실측 · ✅ **표 넷 신설·적재 완료(2026-09-12 · §3-c · ~~§7-c~~) — 226 / 87 / 237 / 0**
③ 제품             ✅ **적재 완료(2026-09-14 · §3-e · ⚠️ 테스트 DB 한정 — 운영 미적용) — 1,141 / 18,714 / 17,104 / 65** · ~~🔄 표 넷 생성 완료 · 적재 대기(2026-09-13 · §3-d)~~ · 전량 18,829 실측(⚠️ 14,677 은 활성만) · `20260913225935`·`230500`·`230600`·`230700` · pack_factor 정본 = **BOM Quantity** · 관계 없음 4,161 · 적재 GAS `docs/probes/ImsLoadProduct.gs` · 카운터 넷 DB 재확인 0 · ⚠️ 카운터 ⑤ 활성끼리 바코드 겹침 **23**(무관 6)
④ 제품↔공급처      ✅ **적재 완료(2026-09-14 · §3-g · ⚠️ 테스트 DB 한정 — 운영 미적용) — `product_supplier` 12,728줄(활성 12,721) · supplier 226→257** · `20260914175145` · 충돌 키 cin7_id · is_default 는 우리 칸(11,480) · 적재 GAS `docs/probes/ImsLoadProductSupplier.gs` · 카운터 여섯 — ⑤ 세트 줄 0 · ⑥ 사 오는 콤보 **3**(기대값) · ⚠️ 콤보 방향은 ⑤ 에서(부모당 하나)
⑤ PO 본체          ✅ **표 열하나 적용·실물 검증(2026-09-16 · §13 · ⚠️ 테스트 DB 한정)** — ①차 `20260916144201` po·po_line·po_discount·po_receipt_line · ②차 `20260916153313` po_invoice·_line·_discount · po_charge·_alloc · po_payment·_alloc · ③차 `20260916175003` 크레딧(po_invoice.doc_kind · 표 수 그대로) · 읽기 `20260916163806`·`164539` 뷰 po_list + RPC po_detail(⭐ 계산 규칙의 정본) · 쓰기 `20260916181719` po_create·po_lines_paste·po_line_update/delete · 화면 `asung-ims/po.html`(읽기 → 크레딧 → 만들기·편집) · 설계 판단은 §11(2026-09-15 · ⭐ 09-16 정정: 확정은 잠금이 아니다 §11-b) · 저녁 **§13-g**(넓은 목록·국면 다섯·머리 칸 15 · `20260916190000`) · **§13-h**(인보이스·크레딧 만들기·할인 편집·⭐ 크레딧 번호는 우리 것 · `20260916200000`·`210000` · 화면 `invoices.html`) · ⭐ **[2026-09-17] 취소·삭제(11-b) · 비용(11-f) · 줄별 수량(11-g) · 결제(11-h) 뒷단 넷(`20260917100000`·`150000`·`170000`·`190000`) + 화면 charges·payments · 공통 CSS·구매 탭(10-j 3-j·3-k)** · ⭐⭐ **[2026-09-18] 리시빙(§13-i · §11-i·c) — 방향 전환(WMS 이관을 미루고 IMS 안에 먼저) · 표 셋 + 차이 큐 · RPC 열(`20260918161537`~`203805`) · 동시 편집 바닥(`133858` · §10-j 3-i) · Receiving 탭(ims)** · 🔄 다음은 §13-f(차이 닫기 · off_po · 환산 · 확정 취소 · 머리 잠금 · 크레딧을 결제에 · 동시 편집 화면) · 원장·원가 이식은 PO 뒤(§12 · ⚠️ 재검토 짐작 §12-a) · 제품 생성 규칙 §11-k
```

순서의 이유: **참조되는 쪽을 먼저 세운다.** 공급처가 결제조건·계정과목을 참조하고(226/226 실측),
제품이 계정과목 넷·브랜드·카테고리·UOM 을 참조하며, PO 가 그 전부를 참조한다.

---

## 2. ⭐ Cin7 전환 모델 — 반복해서 오해된 지점

```
지금       Cin7 Core 가 정본 · 동시에 테스트 DB(Asung-IMS)에서 새 플랫폼을 만든다
           ⚠️⚠️ 두 재고가 다른 것은 정상 — 맞추려 하지 않는다
전환 시점  IMS 를 리셋하고 특정 시각의 Cin7 재고를 통째로 가져온다 → 그 순간부터 IMS 가 정본
과거 이력  옮기지 못한 것은 참조용으로 남긴다
```
**[2026-09-15 저녁 갱신 — 상(像)이 선명해졌다 · 전문은 §11-⓪]**
```
연습 기간   IMS 에서 PO 를 만들고 · 받고 · SO 를 만들고 내보낸다 — **전부 실제로 돌려 본다**(대조용이 아니다)
           ⚠️ 실물 업무는 지금 그대로(물건은 WMS 가 Cin7 발주를 보고 받는다) · IMS 리시빙은 **테스트 리시빙** — 창고가 두 번 받지 않는다
리셋의 뜻   그때까지 IMS 에 쌓인 **거래는 지운다 · 마스터만 남긴다** → 그 시점의 Cin7 재고를 통째로 기초 잔고로
⇒ 표마다 「컷오버 때 지워지는가」가 서야 한다(`source` 축과 **다른 축**) · Cin7 발주·인보이스는 적재하지 않는다 — 적재는 마스터만
```

⇒ ⭐ **PO 를 Cin7 에도 쓰지 않는다.** 테스트 DB 에는 Cin7 secret 도 없다(수집이 돌지 않는 것은 의도).
⚠️ [실사고] 「켜면 Cin7 재고가 어긋난다」를 걱정해 이중 기록을 제안한 적이 있다 — **틀렸다.**
어긋나는 것이 정상이고, 전환 시점에 한 번에 맞춘다.

📌 운영 승격 기준(아침 점검 ⑭ 와 연결): `ref_` 표 여덟은 **테스트에만 있다**. 운영에서 실제로 도는
것이 그 표를 필요로 할 때만 운영에 올린다. 2026-09-10 원가 레이어를 운영에 올린 것은 cron 이 필요로
했기 때문 — 방침 변경이 아니라 예외였다.

---

## 3. ⭐ 표 여덟 개와 그 판단

| 표 | 마이그레이션 | 칸 | 자연키 | 이 표만의 판단 |
|---|---|---|---|---|
| `ref_brand` · `ref_category` · `ref_unit` | `20260911144606` | 8 | `name` | Cin7 필드가 `ID`·`Name` 둘뿐 · ⚠️ `ref_unit.name` 은 **text** — 44개 중 39개가 숫자 이름(2·12·1200·960…)이지만 파싱·CHECK 하지 않는다(케이스 입수 수량으로 쓰이는 UOM · SKU 접미사 파싱 금지 계열). 카테고리 19 중 제품 아닌 것(Liability·Service·Unclassified·Other)도 거르지 않는다 — ③ 제품 단계의 판단 |
| `ref_payment_term` | `20260911161647` | 12 | `name` | `net_days`·`discount_days`·`discount_percent`·`is_split` 네 칸 — ⚠️ Cin7 `Duration` 함정(§4-②) 때문에 나눴다 · **값은 손으로 채운다**(파싱 금지 — 표기가 흔들린다: Net31 · N30 · 「1% Warehouse Allowance + 2%10 Net30」) · `Method` 칸 없음(34개 전부 `number of days` — 값이 하나뿐인 칸은 아무것도 구별하지 않는다) · `IsDefault` 는 `inv_config` 로(이번엔 행 안 넣음) · 통합용 `canonical_id` 없음(표에는 정리된 것만 · 흔들림은 불러올 때 매칭이 흡수) |
| `ref_account` | `20260911162906` | 12 | ⭐ **`code`** | ⚠️ **`name` 유니크 없음**(§4-①) · `account_class` 만 CHECK(다섯) · `account_type` CHECK 없음(16종) · `code` 형식 CHECK 없음(형식 둘) · `for_payments` · `Status` → `is_active`(ARCHIVED 76개도 담는다 — 과거 문서가 가리킬 수 있다) · `Description` → `note` · `DisplayName`·은행 계좌·`SystemAccount*` 는 담지 않는다 |
| `ref_currency` | `20260911164513` | 9 | ⭐ **`code`** | ⚠️ **`cin7_id` 없음**(Cin7 에 목록이 없다) · `source` default **`manual`** · ⭐ **값 2행(CAD·USD)을 넣은 유일한 표** + `inv_config.base_currency='CAD'` 1행 · `code` 형식 CHECK **있음**(`^[A-Z]{3}$`) · `name` 유니크 있음 · `symbol` 화면용(⚠️ CAD·USD 둘 다 `$`) · `rate`·`is_base`·`decimal_places` 없음 · KRW 없음(송금 수단이지 거래 통화가 아니다 · ~~공급처 Currency 실측 KRW 0~~ [2026-09-11 정정] **담는 범위(활성 226) 안에 KRW 0** — 비활성에 1곳 있다 · §8-A-2) |
| `ref_warehouse` | `20260911165946` | 15 | `name` | 주소 6칸 + `is_default` 를 **표에 뒀다**(§4-④) · ⚠️ `IN_TRANSIT` 안 담는다(원장의 합성 창고 · 실재하지 않는다) · `Production Facility` 는 담되 비활성(Cin7 시스템 창고 · 삭제 불가 · 없으면 갈 곳 없는 참조) · Cin7 플래그 넷(`FixedAssetsLocation`·`IsCoMan`·`IsShopFloor`·`IsStaging`)·`PickZones`·`Bins` 는 담지 않는다 · ⭐ `name` 이 `inv_ledger.warehouse`·`wms_orders.location` 과 잇는 고리 |
| `ref_bin` | `20260911165946` | 11 | ⭐ **`(warehouse_id, name)`** | FK → `ref_warehouse` (`on delete no action` · 인덱스 `ref_bin_warehouse_idx`) · ⚠️⚠️ ~~2,675행 예정 — PostgREST 1,000행 캡을 넘는 첫 마스터~~ [2026-09-11 저녁] **2,675행 적재 완료 — 1,000행 캡을 넘는 첫 실물** · `zone` 은 칸만 있고 비어 있다 · `is_staging` · 주소 칸 없음(~~bin 행 주소는 전부 빈 문자열~~ [2026-09-11 저녁 정정] ⚠️ **`""` 와 null 이 섞여 온다** — 같은 응답 안에서도 행마다 다르다 · `= ''` 로만 거르면 null 행이 조용히 빠진다 · 적재 시 빈 문자열을 null 로 통일(`ImsRefLoad.gs` 의 `ims_blank_`)) · `IsDeprecated` → `is_active` |

**표를 둘로 나눈 이유(창고·bin)**: Cin7 은 한 표 + `ParentID` 자기참조지만 창고 3 · bin 2,675 로 규모가
다르고, 주소·회계 의미는 창고에만 있으며, ⭐ `inv_ledger` 가 이미 `warehouse` 와 `bin` 을 별개 칸으로
둔다 — 한 표로 묶으면 쓰는 쪽이 매번 갈라야 한다.

**`ref_bin.name` 에 단독 유니크가 없는 이유**: bin 이름은 창고 안에서만 유일하다. ~~지금은 접두어가
갈려(`A…` 토론토 · `E…` 에드먼튼) 전역 중복 0 이지만~~ 지금은 전역 중복 0 이지만 **오늘의 우연이지 규칙이 아니다.**

⚠️ **[2026-09-13 정정] 「접두어가 갈린다」는 틀렸다.** 토론토에도 `E…` bin 이 있다 — zone E 233 bins.
```
토론토  zone = 첫 글자   A B C D E F G K R Z  (+ 형식 밖 J H W)
에드먼튼 전부 E 로 시작 · zone = 둘째 글자   U 195 · D 92 · E 82 · C 66 · B 62 · F 45 · G 42 · A 30 · Z 1
겹치는 zone 글자  A B C D E F G Z = 여덟   ⭐ 에드먼튼 zone E 는 `EE…` 다 (Caleb)
```
⇒ ⚠️⚠️ **창고는 접두어가 아니라 「어느 창고 칸(warehouse_id) · 어느 슬롯인가」로 판정한다.** 접두어로
판정하면 토론토 E zone 739곳이 에드먼튼으로 **조용히** 넘어간다(에러 없음 · §1-a 감지되지 않는 결함).
📌 zone 글자가 겹치는 것은 복합키 `(warehouse_id, name)` 판단이 옳았음을 **뒷받침**하지만 「확인」은 아니다 —
겹치는 것은 zone 글자이고 bin **이름**의 전역 중복은 여전히 0 이다. 「오늘의 사실이지 규칙 아님」 그대로.

---

## 3-a. ref_ 표 여덟 적재 완료 (2026-09-11 저녁 · 테스트 DB)

⭐ 표만 있던 상태에서 **값이 들어간 상태**가 됐다. 합계 3,481행.

```
ref_brand          415
ref_category        19
ref_unit            44
ref_account        289   (ACTIVE 213 · ARCHIVED 76)
ref_payment_term    34   (활성 17 · 비활성 17 · ⚠️ 계산 칸 넷은 전부 비어 있다 — 2단계)
ref_currency         2   (마이그레이션에서 이미 들어가 있었다)
ref_warehouse        3   (Production Facility 는 is_active=false)
ref_bin          2,675   (토론토 2,047 · 에드먼턴 628 · Production Facility 0)
```

**적재 방식** — Google Apps Script 에서 Cin7 을 읽고 PostgREST 로 upsert.
원본은 `docs/probes/ImsRefLoad.gs`.

- Script Properties 에 `SUPABASE_IMS_URL` · `SUPABASE_IMS_SERVICE_KEY` 를 **새 이름으로** 추가했다.
  ⚠️ 기존 WMS 용 키를 고치면 WMS 자동화가 테스트 DB 를 보게 된다 — 반드시 별도 이름.
- ⚠️⚠️ **`service_role` 금지는 프론트엔드 한정이다.** GitHub Pages 정적 페이지에 키가 공개되기
  때문에 금지인 것이고, Apps Script 는 서버에서 돌고 Script Properties 가 공개되지 않으므로
  service key 사용이 맞다.
  ⇒ `asung-wms` 스킬의 「service_role 금지」를 다른 맥락에 넓게 적용하지 마라.
- 각 표마다 **dryRun**(쓰지 않고 무엇이 들어갈지 확인) → **Apply** 2단계로 돌렸다.
- `ref_bin` 은 200행씩 14묶음으로 나눠 POST.
- `ref_bin.warehouse_id` 는 창고 uuid 를 코드에 박지 않고 **`ref_warehouse` 에서 읽어** 대응표를
  만들어 채웠다(테스트 DB 를 다시 만들면 uuid 가 바뀐다).

⭐ **검증 원칙** — HTTP 201 과 응답 행 수만 보고 끝내지 않고, 매 표마다 SQL 로 다시 읽어 확인했다.

---

## 3-b. ⭐ ② 공급처 — 표 넷 확정 (2026-09-12)

⚠️ **표 셋이 아니라 넷이다.** §7-a 의 「표 셋(본체·주소·연락처)」을 정정한다 —
~~표 셋~~ → **표 넷**. 넷째는 `supplier_discount`(아래 D).

### 표 이름 — `ref_` 를 붙이지 않는다

```
supplier · supplier_address · supplier_contact · supplier_discount
```
⭐ 근거: 표 여덟의 `ref_` 는 **다른 표가 값을 고르러 오는 목록**이라는 뜻이었다. 공급처는 고르는
대상이 아니라 거래 상대이고, 자기 주소·연락처·할인을 거느리며 발주가 여기 매달린다.
⑤ PO 본체가 서면 `po_header`·`po_line` 옆에 `supplier` 가 놓이는 것이 자연스럽다.
📌 §5 가 공유 트리거 함수에 `ref_` 를 안 붙인 판단(「②·③ 이 `ref_` 가 아닐 수 있다」)이 오늘 맞은 것으로
확인됐다. ⚠️ `set_updated_at()` 은 하나뿐 — 다시 만들지 마라.

### A. `supplier` — 본체

**담는다**
```
공통        id · cin7_id · name · is_active · source · note · created_at · updated_at
⭐ name     유니크를 건다 (아래 근거)
FK+원문     payment_term_id + payment_term_name · account_payable_id + account_payable_code
FK          currency_id
원문         tax_rule (ref_tax_rule 은 아직 없다 · §7-a)
우리 칸      is_purchasable  (null=미판정 · false 로 밀지 마라)
우리 칸 ⭐    거래 중단 두 칸 — is_discontinued(bool) + discontinued_on(date · nullable)
Cin7 메모    cin7_comments  ⚠️ 우리 note 와 섞지 마라 (아래)
```

**⭐ `name` 유니크 — 단순히 중복을 막는 것이 아니다**
```
① Cin7 이 마스터를 이름 문자열로 참조한다(§8) ⇒ 이름이 열쇠 노릇을 해야 우리 행 하나를 집을 수 있다
② upsert(on_conflict=name) 가 유니크 제약에 기댄다 — 없으면 조회→분기로 풀어야 하고 이중 삽입이 열린다
③ 인덱스가 따라온다(226곳 규모에선 체감 없음)
```
⚠️ 대가: 겹치는 순간 **그 배치 전체가 실패한다.** 전량 688 중복 0 은 오늘의 사실이지 규칙이 아니다.
⚠️ 유니크가 막아 주지 못하는 것: `Ampro Industries` 와 `Ampro Industries, Inc.` 는 다른 글자다.
   이름 유니크는 「같은 회사 두 번」을 막는 장치가 아니라 **이름을 열쇠로 쓸 수 있게 하는 장치**다.

**⭐ 이름이 바뀌면 — 행을 바꾼다, 새로 만들지 않는다** (2026-09-12 문답)
식별은 `id` 이고 `name` 은 열쇠 칸일 뿐이다. PO·제품↔공급처가 `id` 로 매달려 있으므로 이름을 바꿔도
과거가 따라온다. 새 행을 만들면 과거·미래가 갈려 「작년에 얼마 샀나」가 틀린다.
새로 만드는 경우는 법인이 갈렸거나 거래 주체가 바뀐 때 — 이름 변경이 아니라 다른 회사가 된 때다.
⚠️ **병행 운영 중에는 Cin7 을 먼저 바꾸고 우리가 따라간다.** 반대로 하면 Cin7 이 옛 이름으로 내려주고
   우리 표에 그 이름이 없어 **다음 적재가 새 행을 만든다**(유니크가 못 막는다 — 다른 글자다).
📌 이름 변경 이력 표는 만들지 않는다(드물고 코드가 해석할 일이 없다) — 우리 `note` 에 적는다.

**⭐ 거래 중단을 `is_purchasable` 과 섞지 않는다** ⚠️ 오늘의 핵심 판단
```
is_purchasable    「살 수 있는 곳인가」   — 발주처/경비처 판정 (어제 161/56/9)
is_discontinued   「지금도 사는 곳인가」  — 거래 중단
```
AIM DISTRIBUTOR 는 **발주처가 맞고 지금 안 살 뿐**이다. 한 칸으로 합치면 「경비처라서 안 산다」와
「거래가 끝나서 안 산다」가 섞여 갈라낼 수 없게 된다.
⇒ 중단이어도 `is_purchasable` 은 건드리지 않는다. 새 PO 후보는 두 칸을 같이 보고 고른다.
⚠️ `discontinued_on` 은 적재 시점에 **전부 null 이다** — Cin7 에 날짜가 없다(글자만 있다).
   null = 「중단인데 날짜 모름」 또는 「거래 중」 → 여부는 bool 이 갖고 날짜는 앞으로만 채워진다.

**⚠️ [실측 2026-09-12] 거래 중단 표시가 연락처 이름 칸에 숨어 있다 — 활성 226 중 24곳**
```
정확히 'No longer purchase'        18곳
대소문자 변형                        6곳 (No Longer Purchase · No longer Purchase)
⇒ 적재 판정은 소문자로 맞춰 비교한다. 24곳 전부 걸린다
⚠️ 제외 1곳  Exod International — 이름='Hansoo Kim' · 메모='No Longer Working'
             담당자가 그만둔 것이지 거래 중단이 아니다(Comments 에 주문처·결제방식이 살아 있다)
             ⇒ 판정은 연락처 '이름' 칸만 본다. Comment 는 보지 않는다
⚠️ Ashton Adams LTD 는 이름 칸이 'INACTIVE' — Status 는 Active. 같은 부류의 다른 표기
```
📌 왜 Status 를 비활성으로 안 바꾸고 연락처를 빌려 썼나 — ⬜ **동료 확인 대기**.
Caleb 추정(2026-09-12): 비활성 전환이 되돌리기 어렵고 책임이 따르니 아무도 먼저 손대지 않았다.
그 외 가설: 비활성은 목록에서 사라진다 · 「당분간 안 산다」를 담을 자리가 Cin7 에 없다.
⭐ 이 물음이 중요한 이유는 **자리가 없어서가 아니라 「보이는 자리」가 없어서** 빌려 쓴 것이기 때문이다
(진행단계를 `AdditionalAttribute1` 에 넣은 것과 같은 뿌리 · `ims-principles.md` §4-d).
⇒ 우리 화면에서 `is_discontinued` 가 목록에 보이지 않으면 실무는 또 다른 자리를 빌려 쓴다.

**⭐ `Comments` 는 담는다 — 별도 칸으로**
실측 **75 / 226 곳**에 값이 있고 내용이 실하다: 주문 보낼 이메일과 담당자, 픽업 방식(Showtime 등),
결제 방식, 처리 규칙("인보이스에 있는 shipping cost 빼고 pay함").
⚠️ 우리 `note` 에 붓지 마라 — **재적재가 우리가 적은 말을 덮는다.** 출처가 드러나는 칸으로 따로 받고,
재적재는 그 칸만 덮는다(결제조건·계정과목의 FK+원문과 같은 판단).
⚠️ 칸으로 쪼개지 않는다: 운송사·픽업 여부·임시 연락처·시간 변경 등 성격이 제각각이라 지금 쪼개면
대부분 빈 칸 넷이 생기고 다섯째는 또 못 담는다. **실태가 먼저고 칸이 나중이다.**
📌 `ims-principles.md` §4-d 와 충돌하지 않는다 — 그쪽은 「이름 없는 칸에 뜻 있는 값을 숨기는 것」을
   금한 것이고, 메모란은 처음부터 **사람이 읽는 말**이다(코드가 해석하지 않는다).
📌 Emerson Healthcare("2%30 Net31") · Exod International("NET30 DUE") 처럼 **결제조건이 메모에도**
   적혀 있다. 결제조건 표가 정본 — 메모 쪽은 낡는다.

**담지 않는다**
```
AdditionalAttribute1(Supplier Type) · AttributeSet   §7-a (2026-09-12)
  ⚠️ 화면 실물(2026-09-12): Additional attributes 탭에 칸이 셋 — Supplier Category · Documents · PO Progress
     Supplier Category 가 AdditionalAttribute1(Product/Service Supplier)
     📌 PO Progress 는 전 공급처 빈값(어제 실측: 2~10번 전부 0곳) — 발주 진행단계를 쓰려던 흔적일 수
        있다. ~~⑤ PO 본체에서 발주 진행단계를 정할 때 참고~~ → [2026-09-15] 참고할 것이 없었다 — 우리 상태는 위로 선다(§11-b)
Discount           ⚠️⚠️ 아래 D 와 혼동 금지 — 「Cin7 의 칸 하나」를 안 담는 것이지 할인을 안 담는 게 아니다
TaxNumber          공급처의 세금 등록번호 — 우리는 수집하지 않는다(Caleb 2026-09-12) · 전 곳 빈값
LastModifiedOn     ⭐ 아래 「뒤집힌 판단」 참조
Default carrier    §8-D
```

### B. `supplier_address`

**[실측 2026-09-12 · 활성 226 · 주소 87건]**
```
Type          Billing 77 · Business 8 · Shipping 2
주소 개수      0건 143곳 · 1건 79곳 · 2건 4곳   (§8 의 「최대 2」와 일치)
2건인 4곳의 조합   Billing+Billing 1 · Billing+Business 1 · Billing+Shipping 1 · Business+Shipping 1
같은 타입 2개   1곳뿐 — House of Cheatham, Inc. (Billing x2)
칸별 채움/87   Line1 87 · Line2 9 · City 85 · State 81 · Postcode 83 · Country 83 · Type 87
```

**담는다**: `supplier_id`(FK) · Line1 · Line2 · City · State · Postcode · Country · `type` · `cin7_id` + 공통

**⚠️⚠️ `DefaultForType` 은 담지 않는다 — 값이 실태를 반영하지 않는다**
```
true 15 / false 72.  그런데 주소가 1건뿐인 공급처가 79곳이다
⇒ 유일한 주소인데 「기본이 아니다」로 찍힌 행이 60곳 안팎
원인: 화면의 체크박스이고 아무도 안 누르면 false 로 남는다
      (실물 확인 — Beauty Treats: 주소 1건 BILLING · DEFAULT FOR TYPE 빈 칸)
⚠️ 담으면 「기본 청구지를 가져와라」가 60곳에서 아무것도 못 찾고 화면만 빈다 — 에러는 안 난다
   (§6-a 픽리스트 사건과 같은 「감지되지 않는 결함」)
```
⇒ **기본 주소는 규칙으로 정한다**: 1건이면 그것 · 2건이면 타입으로 고른다(3곳) ·
   Billing 둘인 House of Cheatham 1곳만 사람이 정한다.
📌 늦게 파도 채워지는 부류(§4-d) — 필요해지면 다시 긁는다.

**열쇠**: `cin7_id`. ⚠️ `(supplier_id, type)` 은 자연키로 쓸 수 없다 — House of Cheatham 이 깬다.
**⚠️ 빈 문자열**: `Line2` 등이 `""` 로 온다 → 적재 시 null 로 통일(`ims_blank_` · `ref_bin` 전례).

### C. `supplier_contact`

**[실측 2026-09-12 · 연락처 261건]**
```
칸별 채움/261   Name 229(빈 32) · Phone 112 · MobilePhone 38 · Fax 17 · Email 139 ·
                Website 53 · Comment 45 · Default 261 · IncludeInEmail 261
Default         true 169 · false 92 · ⭐ 둘 이상인 공급처 0곳 (주소의 DefaultForType 과 달리 실제로 구별한다)
IncludeInEmail  true 2 / 261
⚠️ 연락수단(전화·모바일·팩스·메일·웹)이 하나도 없는 행 117건 — 절반 가까이가 사람이 아니다
   회사 이름이 그대로 들어간 행(Alamo · Anthropic · DHL Express · China Grill …),
   상태를 적은 행("Acquired by J&D Brush" · "INACTIVE"), 거래 중단 표시 24건
한 공급처 안 이름 중복 0 — 그러나 이름 빈 행이 32건이라 이름을 열쇠로 쓸 수 없다
```

**담는다**: `supplier_id`(FK) · Name · Phone · MobilePhone · Fax · Email · Website ·
`is_default` · Comment · `cin7_id` + 공통. **열쇠는 `cin7_id`.**

**⚠️ `IncludeInEmail` 은 담지 않는다** — true 2/261. 기능은 「문서 메일 보낼 때 함께 받는 사람」인데
실무는 그 대신 **Comments 에 문장으로 적었다**(E.T Browne: cc 넷). 지금 담아야 2건이고 그 2건이 우리
뜻과 맞는지도 모른다. ⇒ 발주서 발송을 실제로 만들 때 **우리 칸으로 새로 만들고** 메모의 주소들을
연락처로 옮긴다.
**⚠️ JOB TITLE 은 화면에만 있고 API 응답에 없다** — 담을 수 없다.

**⭐ 적재 방침 (Caleb 2026-09-12)**: 261건을 **그대로 옮기고 나중에 걸러서 지운다.**
다만 거래 중단 표시 24건은 연락처가 아니므로 `supplier.is_discontinued` 로 승격하고 행은 남기지 않는다.

### D. `supplier_discount` — ⭐ 오늘 새로 선 표

**⚠️⚠️ Cin7 의 `Discount` 칸(하나)을 안 담는 것과 이 표는 다른 이야기다.**
Cin7 은 공급처에 할인 칸을 **하나**만 준다. 그 하나로는 실태를 못 담아서 실무가 그 칸을 비워 두고
인보이스를 보고 총액을 계산해 **additional cost 에 마이너스로** 넣어 왔다. 칸이 실태를 못 담으니
우회로가 생긴 것이다. ⇒ 우리는 칸 하나가 아니라 **줄이 여럿 달리는 표**로 받는다.
📌 `ims-principles.md` §4-d 가 실제로 작동하는 첫 사례 — Cin7 이 칸 하나를 준다고 우리도 칸 하나를
   두는 것이 아니다.

**담는다**: `supplier_id`(FK) · `name`(⭐ 자유 문자열) · `percent` · `seq`(곱해지는 차례) + 공통

**⭐ 이름은 자유 문자열 — 목록(마스터)으로 만들지 않는다** (2026-09-12 확정)
공급사마다 이름이 다르다(Trade / Damage / Full Line / Volume DC …). 실태를 모르는 채 목록부터
만들면 목록이 실태를 왜곡한다. 문자열로 쌓고, 어떤 이름이 몇 번 나오는지 보고 나서 승격한다
(계정과목 `name` 에 유니크를 안 건 것과 같은 판단).

**⚠️⚠️ 체인 할인 — 차례로 곱해진다. 더하는 것이 아니다** [실물 Ampro INV 0094204-IN · 2026-07-10]
```
Net Invoice        20,729.70
Trade    17%   →    3,524.05   남은 금액 17,205.65
Damage    1%   →      172.06   남은 금액 17,033.59
Full Line 3%   →      511.01
Invoice Total      16,522.58   ✅ 인보이스와 정확히 일치
⚠️ 단순 합(21%)으로 계산하면 16,376.46 — 146 달러 어긋난다
```

**⭐ 매입가 층만 담는다. 조기결제는 결제조건이 정본이다** (2026-09-12 확정)
```
매입가 할인   물건을 받는 순간 확정 · 인보이스에 이미 찍혀 온다 ⇒ 재고 원가로 내려간다  ⇒ 이 표
조기결제 할인 돈을 낼 때 확정 · 기한을 놓치면 안 생긴다      ⇒ 원가로 내려가지 않는다 ⇒ ref_payment_term
```
⚠️ 조기결제 비율을 이 표에도 적으면 **같은 값이 두 곳에 살고 어긋나면 어느 쪽이 맞는지 알 수 없다.**
   `ref_payment_term.discount_days`·`discount_percent` 가 이미 그 값을 갖고 있다(§4-②).
⚠️ 층 칸(bool/enum)은 두지 않는다 — 종류가 하나뿐이면 아무것도 구별하지 못한다(`Method` 를 안 만든 판단).
   매입가도 결제도 아닌 셋째가 나오면 그때 nullable 로 붙이고 null 을 「아직 안 정함」으로 쓴다(§4-d).

**⭐ 마스터는 제안이지 잠금이 아니다**
매번 같은 할인만 여기 담는다. **스페셜 할인은 문서에서 줄을 추가한다**(마스터에 없는 이름도 받는다).
마스터에서 온 줄도 문서에서 고칠 수 있다(이번 달만 15%). 고친 사실이 문서에 남으면 「마스터가 낡았나
이번만 달랐나」를 사람이 판단할 수 있다. 마스터가 낡아도 **인보이스 금액이 정본이라 장부는 맞는다.**
⚠️ 채워야 할 공급사가 몇 곳인지는 **세어 보지 않았다**(Caleb: 정확히 세기 어렵다 · 지금 만드는 게 맞다).
   줄이 0개인 공급사가 대부분이어도 표가 비어 있을 뿐이다.

### ⬜ 열린 물음 — 컷오버 때 다시 꺼낸다

**경비처는 우리 IMS 에 남는가** (Caleb 2026-09-12)
```
⭐ 구별선: 물건의 원가에 얹히는 것은 우리 것이고, 나머지는 회계(QBO)의 것이다
남는다   물건을 사 오는 곳 · 원가에 얹히는 비용을 주는 곳(운임·통관·검사 · Service 인보이스 포함)
안 남는다 어떤 SKU 의 원가도 건드리지 않는 순수 경비(식대 등)
```
⚠️⚠️ **어제 판정의 X 는 「버린다」는 뜻이 아니다.** Showtime(운송)은 X 로 판정됐지만 컷오버 뒤에도
IMS 에 있어야 한다 — 발주에 붙는 운임을 우리 PO 가 배분하기 때문이다.
⇒ **`is_purchasable=false` 를 기준으로 컷오버 때 정리하면 운송사까지 같이 지워진다.**
⇒ 발동 조건은 날짜가 아니라 사건: **⑤ PO 본체에서 비용 라인을 다룰 때** 56곳만 다시 훑는다
   (「원가에 얹히는가」는 실제로 비용 라인을 붙여 봐야 선명해진다). 지금은 226곳 전부 담겨 있어 소급된다.

### ⭐ ⑤ PO 본체로 넘기는 판단 (2026-09-12 · 실물 두 건에서 나왔다)

1. **할인은 문서에 여러 줄로, 순서를 갖고 선다.** 실제 금액이 정본이고 비율은 검증용이다
   (비율만 저장해 다시 계산하면 반올림이 단계마다 끼어들어 센트가 어긋난다 — 그것이 애초에
   라인 할인을 포기하고 총액을 아래에서 빼게 만든 원인이다).
2. **⚠️⚠️ 조기결제 할인은 재고 원가로 내려가지 않는다.**
   [실물 E.T Browne INV 2142773 · 2026-07-16] 품목 10,036.02 + HST 1,304.68 = Net Due 11,340.70,
   결제 11,113.89 → 차액 **226.81 = 총액(세금 포함)의 2%** (조건 2% 10 Net 30).
   ⚠️ Cin7 에는 이것이 additional cost 한 줄(`HST ON (Purchase)`)로 들어가 **세금을 29.49 더 깎아**
   할인 효과를 −256.30 으로 잡는다. 실제로 덜 낸 돈은 226.81 인데 장부는 256.30 을 깎았다.
   ⬜ 조기결제 할인 시 HST 매입세액 처리는 **회계사 확인 필요**(우리가 판단할 사안이 아니다).
3. **⚠️ 할인은 인보이스 단위인데 Cin7 은 PO 단위로 배분한다.** 같은 PO(#PO-01010)에 아직 인보이스되지
   않은 498.33 이 남아 있는데, 인보이스 2142773 에만 걸린 할인이 그 품목의 원가까지 내린다.
   ⇒ 우리 할인 줄은 **어느 인보이스에 속하는지**를 알아야 한다.
4. **⚠️ 샘플은 수량이 있고 단가가 0 이다.** 금액 CHECK 에서 0 을 막지 마라.
   ⭐ 라인이 드는 것은 **실제 단가**다 — 할인은 거기 이미 녹아 있거나 문서 단위 금액으로 따로 선다.
   할인율 칸은 공급처에도 제품에도 두지 않는다(④ 는 Fixed Price·Last Price 가 기본 단가를 제안한다).
5. 📌 **단위 환산이 ④ 에서 다시 온다** — Ampro 인보이스는 CASE 345 @ 20.34 인데 Cin7 은 EA 2,070 @ 3.39
   (6pk 환산이 이미 들어가 있다).

### ⚠️ 오늘 뒤집힌 판단 둘 — 경위를 남긴다

```
LastModifiedOn   담자 → ⭐ 안 담는다
  처음 근거: ModifiedSince 증분 적재의 발판 · 「비용이 0 이니 담자」
  ⚠️ 뒤집은 이유(Caleb 지적): Cin7 과 테스트 DB 는 이어져 있지 않다 — 긁어 와서 넣는 관계다.
     「대조」라 부른 것은 실제로는 재적재 후 값 비교인데, 그건 값 자체를 비교해도 알 수 있다.
     이 칸이 혼자 값을 하는 자리는 ModifiedSince 증분뿐이고, 226곳에서는 필요 없다.
     ⇒ §4-d 의 「혹시 몰라서 미리는 하지 않는다」를 제 권고에 적용하지 않은 것이 잘못이었다.
     늦게 파도 채워지는 부류 — 증분이 실제로 필요해질 때(제품 14,677) 만든다

Discount(Cin7 칸)  담자 → ⭐ 안 담는다
  처음 근거: 11곳에 값이 있고 PO 금액에 작용하니 안 담으면 Cin7 과 어긋난다
  ⚠️ 뒤집은 이유: 실무가 그 칸을 쓰지 않는다 — 미세하게 안 맞아 할인 총액을 additional cost 의
     마이너스로 처리해 왔다. 담으면 PO 가 그것을 기본값으로 밀어 넣고 실무는 다시 지운다.
     ⚠️ 더 나쁜 것은 언젠가 누군가 그 칸이 맞는 줄 알고 쓰는 것이다(Supplier Type 을 안 담은 이유와 같다)
     ⇒ 대신 supplier_discount 표로 여러 줄을 담는다 (위 D)
```

---

## 3-c. ② 공급처 표 넷 적재 완료 (2026-09-12 저녁 · 테스트 DB)

**[테스트 · Asung-IMS]** `fazgmyvzzhqybtvtktyg` · 마이그레이션 셋 적용·커밋·푸시 완료.

| 표 | 마이그레이션 | 행 | 열쇠 | 비고 |
|---|---|---|---|---|
| `supplier` | `20260912202952` | **226** | `name` (unique) | `cin7_id` 도 unique · FK 셋 전부 연결 성공 |
| `supplier_address` | `20260912210733` | **87** | `cin7_id` | 주소 있는 공급처 83곳 · Billing 77 |
| `supplier_contact` | `20260912210733` | **237** | `cin7_id` | 261 − 거래중단 24 · 연락처 있는 공급처 182곳 |
| `supplier_discount` | `20260912212150` | **0** | `(supplier_id, seq)` unique | ⚠️ 뼈대만 — 내용은 Cin7 에 없다(사람이 채운다) |

**적재 후 실측 (SQL 확인)**
```
supplier         226 = is_purchasable true 161 · false 56 · null 9   ⭐ 어제 판정과 정확히 일치
                 is_discontinued 24 · cin7_comments 75
                 payment_term_id·account_payable_id·currency_id 미연결 0 ⭐ 226/226 전부 연결
supplier_address  87 · 주소 있는 공급처 83 · type='Billing' 77
supplier_contact 237 · 연락처 있는 공급처 182 · is_default true 159
```

**📌 `is_purchasable` 은 별도 단계로 넣었다** — 적재 스크립트는 이 칸을 **보내지 않는다**(Cin7 이 모르는
우리 칸이므로 재동기화가 덮으면 안 된다). 판정은 시트
`공급처 판정 2026-09-11 13:43`(`1AqoQPQejFcZfkkwRWDFKMw4GVkM2HcGT5vNRSfI-HJU`)에서
`cin7_id` 로 이어 PATCH 했다(217행 = 161 + 56 · `?` 9곳은 건드리지 않는다).
⚠️ 이 시트는 Cin7 에 없는 값의 **유일한 사본이었다** — 표로 옮겨 사본이 둘이 됐다.

**📌 적재 스크립트 (GAS · `~/asung/gas-system-automation`)**
```
ImsLoadSupplier.gs      imsLoadSupplier / ...Apply       본체 226
ImsLoadPurchasable.gs   imsLoadPurchasable / ...Apply    판정 217 (시트 → PATCH)
ImsLoadSupplierSub.gs   imsLoadSupplierSub / ...Apply    주소 87 · 연락처 237
```
⚠️ 셋 다 `ims_fetch_`·`ims_blank_`(`ImsLoad.gs`) 와 `sp_fetchSuppliers_`(`ProbeSupplier.gs`) 를 쓴다 —
**다시 만들지 마라.**
📌 연락처 적재는 이름이 `'no longer purchase'`(⭐ 소문자로 맞춰 비교)인 행을 건너뛴다 — 24건.

### ⚠️ 오늘 겪은 것 셋 — 다음에 같은 데서 멈추지 않도록

**① `UrlFetchApp` 이 URL 안의 큰따옴표를 거부한다** (PATCH 가 두 번 실패했다)
```
PostgREST 의 in.("guid","guid",…) 문법을 그대로 URL 에 넣으면
  Exception: Invalid argument: https://…/supplier?cin7_id=in.("…","…")
⚠️ 처음엔 URL 길이 문제로 오진하고 묶음을 200 → 40 으로 줄였다 — 그래도 같은 오류였다.
   40개짜리 URL 은 1,700자 남짓이라 한도와 무관했다.
⭐ 원인은 인코딩되지 않은 " 다. GUID 에 따옴표는 필요 없다:
   var list = encodeURIComponent(chunk.map(function (r) { return r.id; }).join(','));
```

**② 조회 결과를 눈으로 보고 「표가 잘못 섰다」고 판단할 뻔했다**
`information_schema.columns` 결과가 화면에서 어긋나 보여(`is_purchasable` 이 `NO`/`DEFAULT false` 로,
끝에 `ate` 세 줄이 붙어) 마이그레이션이 반대로 적용된 줄 알았다. **두 칸만 다시 조회하니 정상**이었다
(`YES` / `null`).
⚠️ §1-a 「결론을 데이터 전에 내리지 않는다」가 사람이 아니라 **도구 출력**에서도 똑같이 적용된다 —
   화면에 보인 것을 사실로 받기 전에 **범위를 좁혀 다시 물어라.**

**③ `supabase db push` 의 카탈로그 캐시 경고는 실패가 아니다**
```
Warning: failed to cache migrations catalog: … pgdelta-target-ca.crt: ENOENT
```
마이그레이션은 `Applying …` → `Finished supabase db push.` 로 정상 적용됐다. 캐시는 편의 기능이라
표 생성과 무관하다(CLI v2.109.1 · 업데이트 안내 동반). ⚠️ 그래도 적용 여부는 **실제로 조회해서 확인**했다.

### ⚠️ [실측 정정] TaxRule 분포가 하루 사이에 움직였다

```
2026-09-11  Zero-rated 140 · HST PE 2016 38 · HST ON 29 · HST NS 16 · GST 2 · Exempt 1
2026-09-12  Zero-rated 149 · HST ON 34 · HST PE 2016 29 · HST NS  8 · GST 4 · Exempt 1 · Out of Scope 1
```
⭐ **폐지된 `HST NS (Purchase)`(15%)를 쓰던 곳이 16 → 8 로 줄었다** — 누군가 정리하고 있다.
⚠️ §8 의 「활성 226곳 TaxRule 분포」는 **2026-09-11 시점의 사실**이다. 취소선을 긋지 말고 위 두 줄을
   나란히 남긴다 — 값이 움직이는 중이라는 것 자체가 사실이다.
⇒ `ref_tax_rule` 을 만들 때 **지금 값이 정리되는 중임을 전제로** 시작한다. 오늘 분포를 그대로 시드로
   박으면 내일 또 달라진다. 종류는 일곱(위 2026-09-12 줄)이고 표를 만들 값어치는 충분하다.
📌 어제 남긴 「발주처 161곳만 추려 다시 세야 한다」(§7 미결)는 **여전히 유효**하다 — 위 숫자도 226곳 전체다.

### 활성 226 전 칸 빈값 실측 (2026-09-12 · NOT NULL 판단 근거)
```
Name · PaymentTerm · AccountPayable · Currency · TaxRule — 빈값 0 / 226 (전부 채워져 있다)
ID 중복 0 · 이름 앞뒤 공백 0
Currency: CAD 67 · USD 159
```
⚠️ 그럼에도 **`tax_rule` 에 NOT NULL 을 걸지 않았다** — 226/226 은 Cin7 화면이 필수로 강제한 결과이지
우리 규칙이 아니다. 우리 화면에서 새 공급처를 만들 때 세금규칙을 아직 안 정한 상태가 있을 수 있고,
막히면 등록 자체가 안 된다. `ref_tax_rule` 이 생겨 FK+원문 쌍이 될 때 다시 판단한다.

### ⬜ 다음

```
supplier_discount 채우기   실무 지식 — 어느 공급사가 어떤 할인을 주는지. Cin7 에 없다
연락처 정리               연락수단 없는 117건 중 회사 이름·상태 문구 행을 지운다(DELETE 열려 있다)
사라진 행 감지            ⚠️ 두 번째 적재부터 생긴다 — upsert 는 「없어진 것」을 모른다.
                         Cin7 에서 연락처를 지우면 우리 표에 남고 에러도 안 난다(§6-a 계열).
                         ⭐ 오늘은 「그대로 둔다」로 간다 — 재적재를 몇 번 해 보고 실태를 본 뒤 정한다.
                         후보: ⓐ 그대로 둔다 ⓑ 공급처별로 지우고 다시 넣는다(우리 note 가 사라진다)
                               ⓒ 이번에 안 들어온 행을 is_active=false 로 내린다(되돌릴 수 있다)
                         📌 컷오버 뒤에는 문제 자체가 사라진다 — 우리 표가 정본이 되면 재적재가 없다
                         ⭐ [2026-09-14 오후] **ⓒ 로 정했다** — ③ 제품 넷과 한 처방. 본문은 **§3-f** 한 곳에만 적고 여기서는 가리킨다. 코드는 아직
③ 제품                    다음 모듈. Cin7 필드 83 · `_숫자_` SKU 거르는 판단이 첫 질문
```

---

## 3-d. ⭐ ③ 제품 — 표 넷 확정 (2026-09-13 · 2차 실측 반영 · 마이그레이션 넷 생성)

**상태**: 2026-09-13 GAS 프로브로 `GET /product?IncludeDeprecated=true` 전량 18,829(83칸) · `GET /productFamily`
전량 1,141 을 실측하고 설계를 검토했다(1차). 검토에서 미결로 남긴 셋(`pack_factor` 정본 · `parent_product_id` 출처 · 재주문점)을
**2차 실측(`ProbeProductBom.gs` · `IncludeBOM=true` 전량)으로 결판내고 마이그레이션 넷을 만들었다** — 로컬 `db reset` 재생 통과.
~~⚠️ 테스트 DB 적용(`supabase db push --db-url "$(cat ~/.asung-testdb-url)"`)과 적재 GAS 는 다음 단계.~~ [2026-09-14 완료 — **§3-e**]. 숫자 중 ⬜ 는 **미측정**이다. 지어내지 않는다.
1차 사료: `~/asung/prompts/ims-product-claude-code-prompt.md` · 검토 회신 `ims-product-reply-prompt.md` · 2차 `ims-product-reply2-prompt.md`.

### 모집단 정정 ⚠️⚠️

§8 의 `product (Total 14,677)` 은 **활성만** 센 숫자였다. 공급처를 226 으로 알았다가 688 이었던 자리(§8-A-1)와 같다.
```
IncludeDeprecated=false   14,677
IncludeDeprecated=true    18,829   ⇐ 전량 (비활성 전용 4,152)
Type                      Stock 18,772 · Service 53 · Non Inventory 4
```

### 표 넷 (예정)

```
product_family   제품군 — 같은 물건의 색상·사이즈 변형을 묶는 단위. 팔리지 않는다. 자연키 sku(…FAM)
product          본체 — 자연키 sku(18,829 전수 중복 0) · ⚠️ name 유니크 금지(576종 중복 · ORLY GEL FX 60행)
product_barcode  바코드 — 제품당 여럿 · 유니크 (product_id, barcode) · Cin7 의 「제품당 바코드 1칸」 한계를 SKU 로 우회한 62건을 흡수
product_bom      콤보 구성 — 다른 물건들을 묶은 것만(15건) · ⚠️ BOMType 으로 가르지 않는다(구성품 2개 이상으로 가른다)
```
| 표 | 마이그레이션 | 칸 | 자연키 | 이 표만의 판단 |
|---|---|---|---|---|
| `product_family` | `20260913225935` | 21 | `sku`(…FAM · 1,141/1,141) | ⚠️ `name` 유니크 없음(변형 이름 중복의 뿌리 · 제품군 이름 중복은 미측정) · 가격 10단계 안 담는다(제품군↔변형 950/4,884 어긋남) · 옵션 축 **이름**만(33종 · 값은 product) |
| `product` | `20260913230500` | 46 | `sku` | ⚠️ `name` 유니크 금지 · `barcode` 칸 없음 · 계정 넷 nullable · `cin7_type` 원문 · `is_discontinued`+`cin7_project_name`(❌ `product_channel` 뺐다) · `sellable` 원문 보존 · ⭐ `pack_factor` = BOM Quantity · `parent_product_id` = BOM ComponentProductID |
| `product_barcode` | `20260913230600` | 11 | `(product_id, barcode)` | 관계 표 · `cin7_id` = 흡수한 대체 UPC 행의 ProductID(⭐ null 아님) · `is_primary` 부분 유니크 금지(카운터) · `valid_from` · DELETE 열림 |
| `product_bom` | `20260913230700` | 13 | `(parent_product_id, component_product_id)` | 관계 표 · **구성품 2개 이상**만(15건) · `quantity > 0` · `cin7_id` 항상 null(규약대로 둠) · DELETE 열림 |

CHECK 이름은 넷 다 `<표>_source_ck`(첨부 `family.sql` 의 인라인 무명 CHECK 도 통일 — 유일한 「그대로」 예외). 인덱스는 `<표>_<컬럼>_idx`.
로컬 재생 실측(2026-09-13): `set_updated_at` 정의 1 · 트리거 4 · 정책 4(`auth_all`) · anon 권한 0 · authenticated DELETE 는 관계 표 둘만 · 트리거 동작 확인.

### ⭐ 조합 형태 넷 — 「종류 칸」을 만들지 않는다

| 형태 | 뜻 | 실측 | 우리 구조 |
|---|---|---|---|
| 관계 없음 | 홀로 선다 (family 도 세트도 콤보도 구성품도 아니다) | ⭐ **4,161** (2차 실측) | 관계가 전부 null |
| family | 같은 물건의 색상·사이즈 변형 | 1,141군 / 4,884변형 | `product.family_id` |
| UOM 세트 | 같은 물건의 다른 포장 단위 | ⭐ **구성품 1개인 BOM 6,406**(대체 UPC 61 포함) | `product.parent_product_id` + `pack_factor` |
| 콤보 | **다른 물건들**을 묶은 것 | 15 | `product_bom` |

⚠️⚠️ **[2026-09-13 정정] 초안의 「기본 제품 13,888 = 관계가 전부 null」은 틀렸다.** 그 수는 `Stock 18,772 − family 변형 4,884` 이고,
그 안에 세트 · 대체바코드 · 콤보 · 세트의 부모가 다 들어 있다. 2차 실측으로 `Type=Stock` 18,772 를 네 축(family · BOM · 구성품 · 세트의 부모)으로 갈랐다:

| 축 조합 | 수 |
|---|---|
| 세트/대체 (구성품 1개인 BOM) | 6,406 |
| ⭐ 관계 없음 | **4,161** |
| 구성품 + 세트의 부모 | 3,297 |
| family | 2,437 |
| ⭐ family + 구성품 + 세트의 부모 | **2,405** |
| family + 구성품 | 38 |
| 구성품 | 13 |
| 콤보 | 11 |
| family + 콤보 | 4 |

📌 「관계 없음」 예: `17251` · `17252`(순수 숫자 SKU 둘 · MIXED CHICKS Foundation & Bronzer · 비활성) · `AAA17000` · `AAL10850` …
📌 세트 모집단은 **BOM 기준 6,406(구성품 1개)** 으로 통일한다. 접미사 SKU 6,349 · 낱개 실재 6,339 는 **검산 수치**로 강등.

⚠️⚠️ **넷은 배타적이지 않다 — 그리고 그것이 다수다.** 초안은 `AS92080`(family 소속 + `AS-DSPLY` 의 구성품 ×12 + `AS92080-6` 의 부모 + 자기도 팔린다)
같은 제품이 「6건」이라 적었다. **틀렸다** — 그건 `AS-DSPLY` 구성품만 센 수였다. 세 축에 동시에 걸리는 것이 **2,405건**, 두 축 이상은 **5,758건**이다.
⇒ `product_type` 같은 칸을 하나 두고 고르게 했다면 **5,758행이 갈 곳을 잃었다**(슬롯3 `Project Name` 한 칸에 단종과 한정판이 같이 살던 모양 · ims-principles §4-d).
**종류는 관계가 있느냐 없느냐로 읽는다**: `family_id` · `parent_product_id` · `product_bom` 의 부모/자식 소속.

축이 겹치는 방식(실측 · ⬜ 재긁기 후 재확인): 세트 SKU 가 family 변형 0건 · 같은 SKU 가 두 제품군 0건 · 콤보 중첩 0건(재귀 없음) ·
⚠️ 콤보가 family 변형 4건(`JAL99890~93CB`) · ⚠️ 세트의 부모가 family 변형 2,712건(43%) — 「색상 골라 12개들이로 사기」가 일상.
⇒ 콤보 4건은 `family_id` 와 `product_bom` 이 한 행에 동시에 걸린다. 막지 마라.

### ⭐⭐ `parent_product_id` · `pack_factor` — 정본은 BOM 이다 (2026-09-13 2차 실측으로 확정)

```
parent_product_id  ⭐ 정본 = BillOfMaterialsProducts[0].ComponentProductID (구성품 1개인 BOM · 구조화된 GUID)
                   실측: 구성품 1개 6,406건 전부 부모를 GUID 로 찾았다 · ⚠️ 덤프에 없는 ComponentProductID 0 ⇒ FK 가 전부 이어진다
                   검산 = SKU 접미사를 잘라 찾은 부모와 일치하는가 → 불일치 건수를 카운터로
                   ⚠️ 처음 초안은 부모를 찾는 법이 접미사뿐이었다 — 「접미사 파싱 금지」라 써 놓고 그 자리에 섰다(검토에서 발견)
pack_factor        ⭐ 정본 = BOM Quantity. UOM 이름·접미사는 검산으로만
                   실측: 숫자UOM · BOM · 접미사 셋 일치 6,340 · 어긋남 3 · 숫자UOM 인데 접미사 없음 0
```
**⭐ 왜 BOM 인가** — BOM 은 「이 세트 하나를 만들려면 낱개가 몇 개 드는가」이고 **Cin7 이 재고를 실제로 빼는 것도 BOM 이다.**
UOM 이름은 화면 표시일 뿐이라, 둘이 어긋나면 **화면은 6개라 하고 재고는 1개가 빠진다. 에러는 안 난다**(§1-a 감지되지 않는 결함).
```
AIA00207-6    UOM=6 · BOM=1 · 접미사=6    ⚠️ 6개들이를 팔면 재고가 1개만 빠지던 자리 — Caleb 이 Cin7 에서 수정 완료(2026-09-13)
ORS12208-6    UOM=6 · BOM=1 · 접미사=6    ⚠️ 같은 모양 — 수정 완료
AMP41108-12   UOM=6 · BOM=6 · 접미사=12   ⭐ 접미사만 틀렸다 (비활성 · 급하지 않다)
```
⚠️⚠️ **`AMP41108-12` 의 뒤집힘** — 초안은 「실제 UOM 이 6」이라 적었고 검토는 「미확인」으로 내렸고, `asung-inv-ledger` 스킬은 「UOM='6' 이 원본 오류」로
**반대로** 적어 뒀었다. 2차 실측으로 결판: **UOM 도 BOM 도 6 이고 SKU 접미사 `-12` 가 틀렸다.** 원장 스킬은 정정했다(2026-09-13).
WMS 의 「unit 을 믿고 접미사는 믿지 않는다」(변형 6,270행 오염 0.05%)는 결과적으로 맞았지만, 그 근거는 UOM 이 아니라 BOM 이어야 한다 — 둘이 어긋난 자리가 실제로 둘 있었다.

⭐ **카운터 넷 — 평상시 0 이어야 신호가 산다.** 2026-09-13 에 이 넷으로 **오류 열 건**을 찾았고 Caleb 이 여덟을 고쳤다. 넷 다 지금 0.
| 카운터 | 지금 | 잡히는 것 |
|---|---|---|
| 구성품 1개인데 그 GUID 가 우리 표에 없음 | 0 | FK 가 끊긴다 |
| ⭐ 세트의 `uom_name`(숫자) ≠ `pack_factor`(BOM) | 0 | **재고가 조용히 틀어진다** |
| 접미사로 찾은 부모 ≠ BOM 으로 찾은 부모 | 0 | SKU 오타 |
| Family SKU 가 `FAM` 으로 안 끝남 | 0 | 1,141/1,141 |
⭐ 둘째가 가장 무겁다 — 나머지 셋은 이름 오타를 잡지만 이건 **재고 수량**을 잡는다.
⚠️ 「세트 SKU 인데 `parent_product_id` 가 null」 초안 카운터는 첫째로 대체됐다 — 「접미사가 있는데 부모를 못 찾음」이 아니라 「BOM 구성품이 1개인데 그 GUID 가 우리 표에 없음」.

Caleb 이 2026-09-13 에 고친 것(다시 긁으면 숫자가 움직인다):
```
SKU 공백      FSP60025 -12 · FSP60027 -4 · PNA01280 -4
SKU 오타      CHI811573-12 → CHI81157-12 · BIS74414-12 → BSI74414-12
Family SKU    AS93146 → AS93146FAM · WTA00264FAM(뒤 공백)
⭐ BOM 수량    AIA00207-6 · ORS12208-6  (UOM=6 인데 BOM=1 이던 것)
```

⬜ **남은 확인(Cin7 · Caleb)**: `SIS00522-6` — UOM=EA-ALT-UPC 인데 BOM ×6 · 활성 ⇒ 대체 UPC 가 아니라 진짜 6개들이일 수 있다(UOM 이름이 잘못 잡혔나) ·
BOM ×12 인 EA-ALT-UPC 1건 · `AMP41108-12` 접미사 · 구성품 0인 채 Assembly 인 콤보 1건 · `CON00134`(부모 없는 대체바코드 · 비활성).

### 상태 셋은 서로를 설명하지 못한다 — 셋 다 둔다

```
is_active          Cin7 Status                       비활성 4,152
is_discontinued    슬롯3 'Project Name' = Discontinued  4,662   ⭐ 우리 칸으로 승격 (제품의 성질)
sellable           Cin7 Sellable 원문                 false 9,974
교차  Discontinued × Active 1,141(단종 정했는데 재고가 남아 판다) · Discontinued × Deprecated 3,521 · (빈값) × Deprecated 617
      Sellable=false × Active 5,879 중 98.7% 가 숫자 UOM(세트) ⇒ 진짜 안 파는 것은 78곳뿐
```
⭐ **`sellable` 은 원문 보존용이다. 우리 논리가 이 칸을 읽지 않는다** — 사실상 「세트인가」의 그림자다.
낱개/세트 판정은 `pack_factor` 와 관계(`parent_product_id`)로 한다(검토 회신 1-d).

**슬롯3 `Project Name` 의 세 값은 전부 「팔 수 있는가」를 말한다** (Caleb 2026-09-13):
```
Discontinued      더 이상 안 들여온다   4,662   제품의 성질  → is_discontinued
Limited Edition   한정 물량이다            42   제품의 성질  → ⏸ 칸 없음 · cin7_project_name 원문에 남는다
No Channel        아직 안 올렸다           74   ⚠️ 지금 상태 — 재고 도착·보류 해제로 풀린다 → ❌ 칸으로 물려받지 않는다
```
❌ **`product_channel` 칸은 뺀다**(검토 회신 1-a). `No Channel` 은 채널 정보가 아니라 **판매 게이트**다 — 「active stock 으로 갖고 있으나
Shopify 등에 퍼블리시하지 않은 것」이고 사유는 제각각(재고 미도착 신제품 · 판매 보류). 「없음」을 값으로 담는 칸이었고,
진짜 채널 정보는 Cin7 Channels 탭에 살며 **API 에 없다**(2026-09-13 실측 · 후보 경로 일곱 전부 200 + HTML). ⇒ §7 ⏸ 「판매 게이트는 ⑤ 이후 사건으로」.
✅ `cin7_project_name text` 원문 그대로 보존(116곳 · 값은 사라지지 않는다).

### 확정된 변경 — 초안 대비 (2026-09-13 검토 회신)

```
❌ product_channel 뺀다             위
✅ cin7_type text 넣는다            Stock / Service / Non Inventory 원문 — AS91437-BLK(Non Inventory · 실물은 자재)를 손으로 넣으면 그 사실이 표에서 사라지면 안 된다
✅ CHECK 이름 <표>_source_ck        기존 표 전부와 통일(인라인 무명 금지)
✅ product_barcode·product_bom 에 cin7_id · is_active   supplier_discount 선례 「항상 null 이어도 규약대로」 · ⭐ barcode 의 62건은 Cin7 ProductID 를 가진 실물 행 — 재적재 멱등 키 · 추적선
✅ 인덱스 product_family_idx → product_family_id_idx   product_family 표의 인덱스로 읽힌다
✅ product_bom.quantity > 0 CHECK
✅ family.sql 은 첨부 파일(프롬프트 본문 블록 아님 — 주석 한 줄 차이)
```

### 담는 범위 · 담지 않는 것 (2026-09-13 확정)

```
담는 범위   Type='Stock' 18,772 − 대체바코드(⭐ UOM=EA-ALT-UPC **그리고** BOM Quantity=1) 59 = 18,713  + AS91437-BLK 1건(Non Inventory · 자재 · 손으로)
            ⚠️ 초안의 「62 를 뺀 18,710」에서 정정 — EA-ALT-UPC 61건의 BOM Quantity 는 1→59 · 6→1 · 12→1 (+ BOM 없는 CON00134).
            BOM 이 1 이 아닌 둘은 「진짜 세트인데 UOM 이름만 잘못 잡힌 것」일 수 있어 흡수하지 않고 ⬜ 확인 뒤 판정(위)
빠지는 57   Service 53 · Non Inventory 4 — 전부 청구서 줄(아마존 프렙·드롭십·배송비·회계 조정·시스템 항목)
            ~~⬜ 별도 작업 — ⑤ PO 비용 라인이 참조할 대상이다. 제외는 맞되 담을 자리를 ⑤ 전에 / ⑤ 표 설계 때 함께 정한다(§7 · §11-f)~~
            → [2026-09-16 닫힘] **담을 자리가 필요 없어졌다** — 비용 문서(po_charge)는 제품을 참조하지 않는다(kind CHECK + description · §13). AS91437-BLK 는 이미 product 에 손으로(별건)
담지 않는 것  Barcode(→ product_barcode) · 치수 넷(전량 0 · Weight 만 값) · PriceTier 1~10(SO 모듈 · 계산 규칙이 API 에 없다) ·
            BOM 플래그 다섯(관계는 product_bom) · Attachments(이미지 사슬이 따로 있다 — 셋째 사본 금지 · IncludeAttachments 는 먹는다) ·
            Channels(API 에 없다) · Bin 슬롯 1·2(실제 자리이나 미사용 · 정본은 Cin7 재고 → 원장) · 값이 하나뿐인 칸 · 전량 null 칸
            ⭐ 재주문점(MinimumBeforeReorder · ReorderQuantity · ReorderLevels[]) — 「안 봤다」가 아니라 **「봤고, 비어 있어서 뺀다」**(2차 실측 · §8)
```
📌 「⚠️ 가격 10단계」— 제품군 값과 변형 값이 950/4,884 어긋난다. 같은 값을 두 곳에 담지 않는다. SO 모듈에서 `ref/markupprices` 까지 재고 세운다.

### ⬜ 미측정 — 「없다」가 아니라 「안 봤다」 (2026-09-13 검토)

```
Name 빈값 · 앞뒤공백            안 셌다 (SKU 는 셌다) · family name 도 같다  ⚠️ name not null 을 걸려면 먼저 센다
Barcode 빈값                    안 셌다 — product_barcode 행 수가 18,000+ 가 되는데 모른다
Barcode 중복 48종의 성격        세트·낱개 쌍 / 대체 UPC / 무관 — 안 갈랐다  ⚠️ 무관이면 스캔 화면이 갈라 물어야 한다
PriceTier 「8단계」              이름 목록(Wholesale · Franchise · AONE · Regular CAD · ComparedPrice CAD · wholesalespecia CAD · USWholesale USD · REFERENCECOST USD)이지 사용 집계가 아니다 · 티어별 비0 건수 없음
Tags 채움 12,321 (65%)          distinct 안 봤다 — 이 정도면 누가 쓴다
Option1~3 값의 위치             GET /product 행에 있는지 family 의 Products[] 에만 있는지  ⚠️ 적재 의존 방향이 갈린다
~~세트 모집단 숫자 셋~~            ✅ 2차 실측 — BOM 기준 6,406 으로 통일 · 접미사 6,349·낱개 실재 6,339 는 검산 수치
~~관계 전부 null 인 제품 수~~      ✅ 2차 실측 — 4,161
~~ReorderLevels~~                 ✅ 2차 실측 — 먹는다 · 값 전부 0 · 담지 않는다(§8)
CustomPrices                    안 켜고 물어 빈 배열 — 「없다」가 아니다 (SO 모듈)
IncludeSuppliers                ⭐ [정정] 「미확인」이 아니라 **이미 돌고 있다** — §8 product 절
Registered On 시간대            CreatedDate 에 Z 가 없어 미판정
구성품 0인 채 Assembly 1건       SKU 미기록 · Cin7 확인 대기
```

### 프로브 — 표를 만들기 전에 (GAS · Caleb 이 돌린다) · ✅ 1·3·4 완료(2026-09-13 `ProbeProductBom.gs`) · 2·5·6·7·8 은 문서 숫자라 적재와 병행

| # | 무엇 | 표 전에 필요한가 |
|---|---|---|
| 1 | `IncludeBOM=true` 전량 덤프(19페이지 · 응답 커지면 Limit 낮춤) — 구성품 1개인 BOM 전수에서 UOM 이름 · BOM Quantity · SKU 접미사 셋 대조 · 불일치 전량 · `AMP41108-12`·`SIS00522-6` 의 BOM Quantity · EA-ALT-UPC 61건의 Quantity(1 인가) · ComponentProductID 가 덤프에 없는 건수 | ✅ 완료 — 정본 BOM 확정 · 덤프에 없는 GUID 0 · 어긋남 3 |
| 2 | Name 빈값·공백(family 포함) · Barcode 빈값 · 중복 48종 분류 | 아니오(문서 숫자) |
| 3 | 「관계 전부 null」 재계산 — family 없음 · BOM 없음 · 누구의 구성품도 부모도 아님 | ✅ 완료 — 4,161 · 축 조합 표 |
| 4 | `IncludeReorderLevels=true` 실제 상품 SKU 표본 200 + 상위 칸 둘(MinimumBeforeReorder·ReorderQuantity) 비0 건수 | ✅ 완료 — 40/40 값 전부 0 · 담지 않는다 |
| 5 | PriceTier1~10 비0 건수 · Tags distinct 상위 20 | 아니오 |
| 6 | 실제 상품 1행에 Option1 이 있는지 | 아니오(적재 설계) |
| 7 | Type=Service·Non Inventory 57건 SKU 목록 저장 | 아니오(⑤ 준비) |
| 8 | Caleb 확인 — 「한정판이면서 단종」 4건을 어디서 봤나 | 아니오 |

⚠️ 6,343건을 건별로 물으면 Cin7 호출이 4시간이다. **전량 덤프에 `IncludeBOM=true` 를 켜서 한 번에** 받는다 — 실제로 그렇게 했다(38페이지 · 2분 42초 · §8).

### ⭐ 덧붙임 (2026-09-15 · 화면을 세우며 드러난 것) — 패밀리와 콤보는 성질이 반대다

같은 「묶음」이라는 말을 쓰지만 하나는 **보여 주기 위한 것**, 하나는 **계산하기 위한 것**이다.
```
패밀리(product_family)   ⭐ 느슨한 묶음 — 안 묶여도 재고·발주가 안 깨진다. 안 묶인 제품 4,161 이 있고 그것이 정상이다(위 「관계 전부 null」)
                        ⭐ Shopify 에서 한 상품의 변형(variant)으로 보일지를 정하는 축 — 묶고 푸는 것은 판매 쪽 판단이다
콤보(product_bom)       ⚠️ 단단한 묶음 — 재고가 실제로 흐른다. 디스플레이 1개가 낱개 24개로 갈린다(립오일 UNF18259 → UNF18048 ×24). 끊어지면 재고가 안 맞는다
```
[화면 실측 · Caleb 2026-09-15 · families.html] 묶인 제품 수 — 1개 11 · 2~5개 913 · 6~20개 197 · 21개 이상 20 · ⭐ 빈 패밀리 0.
립오일 검산 — 디스플레이 `UNF18259` FixedCost 7.92 = 낱개 `UNF18048` 0.33 × 24(구성품 4종 × 6개). 「사 오는 콤보」의 단가가 구성품 합과 맞는다 — ⑤ 에서 발주 금액 검산에 쓸 수 있다.

⬜ **옵션 축 이름이 갈려 있다** [화면 실측 · Caleb 2026-09-15] — `Color` 463 / `color` 38 · `Flavor` 4 / `Flavour` 3 · `Size` 332 · `Formula` 69 · `Type` 52 · `Style` 46 · 둘째 축이 있는 패밀리 33 · 셋째 축 없음.
지금은 `families.html` 이 **화면에서만** 합친다(`AXIS_ALIAS` · color→Color · Flavour/flavour/flavor→Flavor · size→Size). 데이터는 Cin7 에서 온 값이라 IMS 에서 고쳐도 다음 재적재(§3-f)가 되돌린다.
⬜ Shopify 연동 때 정리한다 — 우리 칸을 두거나 Cin7 을 고치거나. ⚠️ `Size`/`Volume`/`Length` 와 `Type`/`Style`/`Design`/`Shape` 는 합치지 않았다 — 실무에서 구별하는 것일 수 있어 판단할 수 없었다.

---

## 3-e. ③ 제품 표 넷 적재 완료 (2026-09-14 토론토 오전 · 테스트 DB)

**[테스트 · Asung-IMS]** `fazgmyvzzhqybtvtktyg` · 마이그레이션 넷(`20260913225935`·`230500`·`230600`·`230700`) `db push` 적용 후 전량 적재.
**합계 36,924행.** ⚠️ 운영 DB(asung-WMS)에는 없다 — `ref_` 여덟·② 넷과 같이 테스트 한정(§2 승격 기준).
②가 §3-b(표 확정) → §3-c(적재 완료)로 나뉜 것과 같은 모양 — 설계는 §3-d, 이 절은 결과와 사고 기록이다.

### 행 수 — SQL 실물 · 적재 후 재조회

| 표 | 마이그레이션 | 행 | 비고 |
|---|---|---|---|
| `product_family` | `20260913225935` | **1,141** | FK 셋 전부 1,141 연결 · `not_fam` 0 |
| `product` | `20260913230500` | **18,714** | `Type=Stock` 18,713 + `AS91437-BLK` 1 |
| `product_barcode` | `20260913230600` | **17,104** | primary 17,054 + 대체 UPC 50 |
| `product_bom` | `20260913230700` | **65** | 콤보 15건의 구성품 줄 |

### `product` 속살
```
활성                 14,575   (전량 활성 14,677 중 걸러진 116 안에 102 가 있었다)
family_id             4,884   ⭐ 09-13 실측과 정확히 일치
is_discontinued       4,660   (전량 4,662 중 둘이 걸러진 116 안에 있었다)
registered_on           612   ⭐ 실측과 일치
parent_product_id     6,347   ⭐ pack_factor 와 같은 수 — 짝이 안 맞는 행 0
cin7_type ≠ Stock         1   AS91437-BLK
note 있는 행              1   같은 행
```

### 거르기 — 18,829 → 18,713
```
Type ≠ Stock                              57 제외   (Service 53 · Non Inventory 4 — ~~§7 「담을 자리」 미결~~ → [2026-09-16 닫힘] 비용 문서는 제품을 참조하지 않는다 · 자리 불필요 · §13)
UOM = EA-ALT-UPC  그리고  BOM Quantity = 1   59 제외   → product_barcode 로 흡수
= 18,713  (+ AS91437-BLK 1건 = 18,714)
```
⭐ **`EA-ALT-UPC` 셋이 `product` 에 남았다** — 「UOM 만으로」 걸렀다면 사라졌을 것들이다(§3-d 「담는 범위」의 **그리고** 조건이 한 일).

| SKU | 상태 | BOM | 왜 남았나 |
|---|---|---|---|
| `SIS00522-6` | 활성 | ×6 | 대체 UPC 가 아니라 **세트일 수 있다** ⬜ Caleb 이 Cin7 에서 확인 |
| `AJA69215-EA-ALT-UPC` | 비활성 | ×12 | 같은 부류 ⬜ |
| `CON00134` | 비활성 | 없음 | BOM 이 없어 흡수 조건에 안 걸렸다 |

### ⭐ 오타 탐지기 — DB 에서 재확인, 넷 다 0

09-13 에는 GAS 덤프에서 셌다(§3-d 카운터 넷). 이번엔 **적재된 표에서 SQL 로** 다시 셌다 — 같은 값이 다른 경로에서 나왔다.

| 카운터 | 값 |
|---|---|
| 세트인데 부모가 우리 표에 없음(고아) | 0 |
| ⚠️ `uom_name`(숫자) ≠ `pack_factor` | **0** ← 09-13 에 `AIA00207-6`·`ORS12208-6` 를 고친 결과 |
| 부모가 자기 자신 | 0 |
| 부모는 있는데 `pack_factor` 없음 | 0 |
| `product_barcode`·`product_bom` 고아(product_id · parent · component) | 0 · 0 · 0 |

⭐ 실물 검산 — `AS92080` 부류(§3-d 「넷은 배타적이지 않다」의 예시)가 설계대로 갈렸다.
```
AS92080     EA   부모 없음 · family AS92082FAM
AS92080-6   6    부모 AS92080 · pack_factor 6 · family 없음
```

### 대체 UPC 59 의 처분
```
넣은 줄                50
⚠️ 바코드 없음           5   AIA03530 · AIA03534 · DEX30160 · DMI00077 · SIS00510 (전부 …-EA-ALT-UPC — 바코드용 SKU 인데 바코드가 없다)
⚠️ 부모가 이미 보유       4   ADA96563 · AMB23411 · AMB46405 · SUN31502 (같은 값이라 새 정보가 없다 · 줄을 만들지 않는다)
⚠️ 부모 못 찾음           0
```
📌 09-13 에 62건을 셀 때 나온 「바코드 없음 7 · 부모와 같음 12」와 다르다. 그때는 `product` 에 남은 셋과 `CON00134` 까지
포함한 수였고, 흡수 대상 59 만 보면 5 와 4 다.

### ⚠️ 한 바코드를 여러 제품이 쓰는 것 — ~~38~~ 42 · ⭐ 카운터는 활성끼리 **23** (2026-09-14 오후 정정)

```
48   09-13 GAS 덤프 실측 (대체 UPC 포함)
38   바코드 로더가 센 수 — ⚠️ 대체 UPC 50줄을 넣기 **전**의 수였다 (오전 기록 · 경위로 남긴다)
42   대체 UPC 50줄이 들어간 뒤 · SQL 실물
```

**⭐ 활성/비활성을 갈랐다** (Caleb 2026-09-14) — 겹치는 쪽이 비활성이면 스캔될 일이 없어 문제가 아니다.

| 구분 | 건 | 뜻 |
|---|---|---|
| ⚠️ **활성끼리 겹침** | **23** | 스캔이 어느 쪽인지 못 가른다 — **진짜 문제** · 이것이 카운터 ⑤ |
| 활성 1 + 비활성 | 13 | 스캔되는 건 하나뿐 · ⬜ 버리지 않는다 — 그 비활성을 되살리는 순간 활성끼리로 올라간다(§7) |
| 전부 비활성 | 6 | 스캔될 일 없음 |

⚠️ **카운터는 42 가 아니라 23 이다.** 42 로 두면 고칠 수 없는 과거(비활성)가 섞여 **평상시 0 이 영원히 안 된다** — 「0 이어야 신호가 산다」(§3-d 카운터 넷)를 깬다.

**활성끼리 23 의 성격 — 셋으로 갈린다**

| 부류 | 건 | 무엇 |
|---|---|---|
| ⚠️⚠️ **무관한 제품** | **6** | 서로 다른 물건이 같은 바코드 — **WMS 가 잘못 집는다** · Caleb 이 Cin7 에서 고친다 |
| 색상·향 변형 | 12 | 같은 제품의 색상별인데 바코드가 하나 · ⬜ 아래 |
| 세트·낱개 | 5 | 같은 물건의 다른 포장 — 정상일 수 있다 |

무관한 제품 6건:
```
10815680003022  UNCLE JIMMY 비어드소프너 · 록홀드 · 몰딩퍼티   ⚠️ 활성 3종이 한 바코드
10743690086431  HAWAIIAN SILKY 릴랙서 ↔ WONDER GRO 스타일링젤  ⚠️ 다른 브랜드
074108470508    BABYLISS 포일셰이버 ↔ 메탈트리머               고가 제품
021959611703    HAIR CHEMIST 샴푸 ↔ 컨디셔너
10705372000500  ANNIE 스타일링픽 ↔ 커팅콤
30796708310176  KCA31017-12(Moisturizing Health…) ↔ KCA33081-12(Moisturizing Curl…)
```
📌 색상 변형 12 는 **고칠 것이 아닐 수도 있다** — 공급사가 색상 구분 없이 한 바코드로 찍어 보냈다면 Cin7 이 맞다.
그때는 「이 제품군은 스캔으로 색상을 못 가른다」를 아는 것이 답이다. ⬜ 12건이 어느 쪽인지는 Caleb 이 Cin7 수정 때 함께 본다.

재현 쿼리 — 활성끼리 겹치는 것만(이것이 카운터):
```sql
-- [테스트 · Asung-IMS]
with act as (
  select b.barcode, p.sku, p.name
  from public.product_barcode b
  join public.product p on p.id = b.product_id
  where p.is_active and b.is_active          -- b.is_active: §3-f 규칙(안 들어온 cin7 행은 비활성으로 남는다) 뒤 추가 · 2026-09-14 오후
)
select barcode, count(*) as active_cnt,
       string_agg(sku, ' · ' order by sku) as skus,
       string_agg(left(name, 45), ' | ' order by sku) as names
from act group by barcode having count(*) > 1
order by count(*) desc, barcode;
```

### 📌 적재 스크립트 — `docs/probes/ImsLoadProduct.gs`

`ImsRefLoad.gs`·`SupplierProbe.gs` 선례대로 레포에 사본을 둔다(원본은 GAS `gas-system-automation` · 레포에서 실행되지 않는다).
`ims_fetch_`·`ims_blank_`·`ims_cin7All_`(`ImsLoad.gs`)를 쓴다 — **다시 만들지 마라.** 함수마다 `[Apply]` 없는 쪽이 dry-run 이다.

| 함수 | 하는 일 |
|---|---|
| `imsLoadProductFamily[Apply]` | 제품군 1,141 |
| `imsLoadProduct[Apply]` | 본체 · 페이지마다 upsert · 커서 `IPR_PRODUCT_PAGE`(Script Property · `imsLoadProductReset` 이 지운다) |
| `imsLoadProductExtra[Apply]` | ⭐ `AS91437-BLK` 한 건 — 규칙 밖(Non Inventory · 실물은 자재)이라 별도 함수 |
| `imsLinkProductSets[Apply]` | 2단계 · `parent_product_id`·`pack_factor` 를 **PATCH** · 링크 목록을 `_set_links` 시트에 저장 |
| `imsLinkProductSetsResume` | ⭐ 이어받기 전용 — Cin7 을 안 훑고 시트만 읽는다 |
| `imsLoadProductBarcode[Apply]` | primary 17,054 · 커서 `IPR_BARCODE_PAGE` |
| `imsLoadProductAltUpc[Apply]` | ⚠️ 바코드 적재 **뒤에** — 부모 보유 여부를 `product_barcode` 에서 읽어 비교 |
| `imsLoadProductBom[Apply]` | 콤보 65줄 |

⚠️ **순서 의존이 둘이다.**
```
imsLinkProductSets    는 imsLoadProduct         뒤 — 낱개가 다 있어야 자기참조 FK 가 이어진다
imsLoadProductAltUpc  는 imsLoadProductBarcode  뒤 — 부모의 바코드 줄이 있어야 「이미 보유」 비교가 된다
```
`IPR_LIMIT=500`(BOM 을 켜면 1000 이 안 온다 · §8) · `IPR_MAX_RUN` 4분 30초(GAS 6분 한도 안에서 커서를 남기고 ⏸) ·
대응표는 Range 페이징으로 읽는다(`product_family` 1,141 은 1,000행 캡을 넘는다 — §7).

### ⚠️⚠️ 오늘 겪은 것 셋 — 뿌리가 같다: 요청 하나하나의 비용을 계산하지 않았다

**① upsert 로 부분 갱신을 하려다 400** — `product` 18,714행 · 스킬 `asung-wms` 규칙 45
두 칸(`parent_product_id`·`pack_factor`)만 고치려고 `POST … Prefer: resolution=merge-duplicates` 를 썼다가
`23502 null value in column "name" violates not-null` 이 났다.
```
관찰  보낸 객체에 없는 NOT NULL 칸(name)에서 23502 — upsert 는 INSERT 후보 행을 먼저 만들므로 부분 객체는 그 검사를 못 넘는다.
      성공했더라도 보낸 칸은 전부 덮인다(같은 스크립트의 product_barcode 절 — is_primary=true 가 false 로 덮이는 자리).
⇒ 부분 갱신은 반드시 PATCH 다. upsert 는 「행 전체를 가진 적재」에만.
추정  「name 이 nullable 이었다면 18,714행의 이름이 통째로 비워졌을 것」— 사고 당시의 해석이다. ⚠️ 미실측.
      PostgREST 의 DO UPDATE SET 은 보낸 칸만 나열하는 구현이라 안 보낸 nullable 칸은 보존될 가능성이 있다 — 그래도 처방(PATCH)은 같다.
```
📌 어느 쪽이든 **「공통 8칸의 NOT NULL 이 왜 값어치 있는가」**의 실물이다 — 검사가 없었다면 부분 객체가 조용히 통과했다(§5).

**② 「건너뛰는 요청」도 공짜가 아니다** — 스킬 `asung-wms` 규칙 46
PATCH URL 에 `&parent_product_id=is.null` 을 붙여 이미 이어진 행을 서버가 거르게 했는데, **거르는 것도 요청을 한 번씩 보낸다.**
709건을 건너뛰는 데만 4분을 썼다.
```
⇒ 먼저 이어진 id 목록을 읽어 **아예 빼고** 시작한다 (ipr_patch_ 가 select=id&parent_product_id=not.is.null 을 먼저 읽는다 · Range 페이징).
⭐ 실측: PATCH 한 건 ≈ 0.28초 · 6분 한도에 ~1,200건
```

**③ Cin7 재훑기를 이어받기마다 반복했다**
`imsLinkProductSetsApply()` 가 매번 Cin7 18,829행을 2분 10초 훑고 실제 작업은 2분 20초뿐이었다.
```
⇒ 링크 목록을 시트(_set_links)에 저장하고, 이어받기(imsLinkProductSetsResume)는 Cin7 을 안 훑는다.   984건/회 → 1,200건/회
```

### ⬜ 다음
```
SIS00522-6 · AJA69215-EA-ALT-UPC   세트인가 대체 UPC 인가 — Caleb 이 Cin7 에서 확인(§7)
활성끼리 겹치는 바코드 23           무관 6 은 Caleb 이 Cin7 에서 고친다 · 색상 변형 12 는 「고칠 것인가」 판단 · 고친 뒤 재조회해 카운터 ⑤ 를 갱신
운영 DB 적용                       아직 — ref_ 여덟·② 넷과 함께 「운영에서 도는 것이 필요로 할 때」(§2)
④ 제품↔공급처                      출발점은 0 이 아니다 — Productmaster.js 의 IncludeSuppliers(§8)
재적재(Cin7 정리 뒤)               ⭐ 넷이 한 규칙 — upsert + 안 들어온 cin7 행은 is_active=false · §3-f
```

---

## 3-f. ⭐ 재적재 방식 — 넷이 한 규칙 (2026-09-14 오후 · 문서만 · 코드는 Cin7 정리 뒤)

### 왜 지금 정하나

Caleb 이 Cin7 에서 **바코드 중복을 정리할 예정**이다(스프레드시트 `cin7-cleanup.xlsx` 기준 · §3-e 활성끼리 23). 정리가 끝나면
재적재를 해야 한다. 정리 뒤에 정하면 이미 어긋난 표를 앞에 두고 고민하게 된다 — 그래서 먼저 정한다.
⚠️ 이 절은 **판단만** 담는다. 적재 스크립트(`docs/probes/ImsLoadProduct.gs`)는 Cin7 정리가 끝난 뒤에 고친다.

### 전제 — SKU 는 바뀌지 않는다

Caleb 확인(2026-09-14): **공백이 든 SKU 와 이름이 틀린 SKU 는 적재 전에 이미 다 고쳤다.** 남은 정리 대상은 **바코드 중복뿐**이다.
⇒ 「Cin7 에서 SKU 를 고치면 우리 표가 어떻게 따라가나」(§7)는 지금 발동하지 않는다. `sku` 충돌 키 그대로.
⚠️ [2026-09-15 저녁] 발동 조건이 없어도 **열쇠는 cin7_id 로 바꾼다** — 그때 가서 바꾸면 이미 두 행이다(§11-k). 위 문장의 「그대로」는 코드 고치기 전까지의 현재 상태.
📌 딸린 결과: `cin7_id` 가 SKU 변경에도 유지되는지는 **여전히 미확인** — 실측할 일이 없어졌을 뿐이다(§7 ⬜).

### ⭐ 한 규칙 — upsert 하고, 이번에 안 들어온 `source='cin7'` 행은 `is_active=false` 로 내린다

| 표 | 충돌 키 | 규칙 |
|---|---|---|
| `product_family` | `sku` | 같다 |
| `product` | `sku` | 같다 — ⚠️ 원장·WMS 가 가리킬 수 있는 표라 **지우는 방식은 애초에 후보가 아니다** |
| `product_barcode` | `(product_id, barcode)` | 같다 |
| `product_bom` | `(parent_product_id, component_product_id)` | 같다 |

```
회차마다
  1) Cin7 전량을 받아 upsert 한다 (is_active:true 를 실어 보낸다)
  2) source='cin7' 이고 이번 회차에 안 들어온 행을 is_active=false 로 내린다  — 지우지 않는다
  3) 내린 수 · 되살린 수를 로그에 남긴다 — 판정은 사람이 한다
⭐ source='manual' 행은 1)·2) 어디에도 안 걸린다 — 사람이 화면에서 더한 줄은 남는다(지금 0줄이지만 그게 이 표들을 만든 이유다)
```

**⭐ 되살아나는 경우 — 의도된 동작이다.** `is_active=false` 로 내린 행이 다시 Cin7 에 나타나면 1) 의 upsert 가 `is_active:true` 를
실어 보내므로 **저절로 true 가 된다.** 따로 되살리는 단계가 없다. 스크립트 주석에도 이 문장을 남긴다(코드 고칠 때).

**왜 이 규칙인가 — 세 표의 설계와 맞는다**
```
valid_from   「UPC 가 바뀌어도 옛 바코드를 단 재고가 창고에 남는다 — 지우지 않고 쌓는다」(20260913230600 주석)   ← 지우면 이 칸을 둔 이유가 사라진다
note         「우리가 적는 메모. 재적재가 덮지 않는다」(barcode·bom 주석)                                     ← cin7 행의 note 도 남는다
id           바뀌지 않는다 ⇒ 나중에 스캔 기록이 product_barcode.id 를 FK 로 물어도 이 규칙은 그대로 쓴다
빈 시간      없다 — 지우고 다시 넣는 사이가 없으므로 운영 전환 뒤에도 그대로 쓴다
§5           「마스터는 지우지 않고 is_active 로 물러나게 한다」를 관계 표에도 같은 말로 적용하는 것
```

### ⚠️⚠️ 왜 지우지 않나 — Cin7 은 「없어진 것」을 알려주지 않고, 사라진 바코드는 두 종류다

upsert 는 새 값을 넣지만 사라진 값을 모른다. Cin7 에서 바코드를 비우거나 바꾸면 우리 표에 옛 바코드가 **유령**으로 남고, 스캔하면
여전히 그 제품이 나온다 — 이번 바코드 중복 정리가 바로 이 경우다(한쪽 제품의 바코드를 비운다).

그런데 「Cin7 에서 사라진 바코드」는 **두 종류**다:
```
잘못 붙은 바코드 정리   (이번 무관 6건)      → 스캔에서 빠져야 한다
공급사 UPC 변경         (valid_from 의 이유)  → 옛 바코드를 단 재고가 남아 있으니 남아야 한다
```
`is_active=false` 는 둘을 **같은 동작으로 맞게** 처리한다 — 둘 다 「지금 Cin7 에는 없다」이고, 스캔은 활성만 보되 비활성 줄은 「옛 바코드 · 재고에
남을 수 있음」으로 읽힌다. 지우고 다시 넣기는 둘을 가르지 못하고 둘째를 잃는다.

**⚠️ 뒤집힌 판단 — 경위를 남긴다.** 같은 날 오전의 초안은 「`product_barcode`·`product_bom` 은 `source='cin7'` 을 **지우고 다시 넣는다**,
마스터 둘은 upsert + 「Cin7 에 없는 행」 세기」로 **표마다 방식이 다른** 안이었다(`wms_sku_bins` 매일 truncate 와 같은 생각 · 범위만 `source='cin7'`).
검토에서 `valid_from`·`note` 주석과의 충돌, 그리고 「사라진 바코드가 두 종류」라는 점이 나와 오후에 폐기했다.
그 안이 안고 있던 제약 둘(새 UUID 가 생겨 FK 를 못 건다 · 지우고 넣는 사이의 빈 시간)도 이 규칙에서는 생기지 않는다.

### 마스터도 같다 — §3-c 「사라진 행 감지」와 한 처방

`product`·`product_family` 에도 같은 문제가 있다(Cin7 에서 제품을 지우거나 합치면 유령 행). §3-c 가 ⬜ 로 남긴 「사라진 행 감지」의
후보 ⓒ(이번에 안 들어온 행을 `is_active=false` 로 내린다 · 되돌릴 수 있다)가 정확히 이 규칙이다.
⇒ **한 곳(여기)에 적고 양쪽에서 가리킨다.** 공급처 넷(§3-c)도 같은 처방 — 코드는 둘 다 아직이다.
📌 컷오버 뒤에는 문제 자체가 사라진다 — 우리 표가 정본이 되면 재적재가 없다.

### ⚠️ 읽는 쪽이 지는 조건 — `is_active` 를 건다

비활성 행이 표에 **남는** 규칙이므로, 읽는 쪽이 걸러야 한다. 안 걸면 유령이 그대로 보인다(에러 없음 · §1-a).
```
스캔 화면        product_barcode.is_active and product.is_active — 둘 다
카운터 ⑤ (§3-e)  활성끼리 겹침 쿼리에 and b.is_active 를 건다 (§3-e 쿼리에 반영)
is_primary 카운터 「제품당 primary 둘 이상」도 활성 줄만 센다
```

### 전량이냐 증분이냐 — 전량

```
증분(cin7_modified_on · 18,829 전수 채워져 있어 가능하긴 하다)   ⚠️ 삭제를 못 본다 — 2) 단계가 성립하지 않는다
전량                                                         느리지만(18,829행 3~4분) 「지금 Cin7 에 무엇이 있나」를 통째로 안다 — 2) 의 전제
```
**전량으로 둔다.** 증분이 필요해지는 조건은 「전량이 GAS 6분 한도를 못 맞출 때」다. 그때는 2) 단계를 어떻게 지킬지 함께 다시 본다.

### ⚠️ [2026-09-15 실측] 적재 GAS 는 Status 를 직접 읽는다 — 「비활성」이 오는 길이 둘이다

`docs/probes/ImsLoadProduct.gs` 를 읽고 확인했다(대화 Claude · 검토 Claude 가 행 번호 재확인):
```
230·350·438·640·731·807행   Cin7 요청에 IncludeDeprecated: true
294행                       is_active: String(p.Status) === 'Active'
⇒ ⭐ Cin7 에서 deprecated 된 제품도 **응답에 들어온다.** 빠지는 것이 아니다. is_active 는 Cin7 이 준 Status 를 **그대로 읽어** 정한다.
  ⇒ 다음 적재 때 그 행이 is_active=false 로 **갱신**된다. 행은 남고 id 도 유지되니 그 제품을 가리키던 공급처 줄·바코드·BOM 이 끊어지지 않는다.
    Cin7 에서 다시 살리면 true 로 돌아온다.
⭐ **안전한 쪽이었다** — 적재가 중간에 끊겨도 「안 들어왔으니 내린다」를 하지 않는다. 들어온 것만 갱신하고 안 들어온 것은 건드리지 않는다.
  API 가 일부만 돌려줘도 무더기 비활성이 안 생긴다.
```
⚠️ 그래서 「비활성」이 우리 표에 오는 길이 **둘**이다 — 위 「한 규칙」이 이것을 가르지 않고 있었다:
```
ⓐ Cin7 이 deprecate 했다(Status)           → 응답에 들어온다 · 1) upsert 가 is_active=false 를 실어 온다 · **2) 단계가 필요 없다**
ⓑ Cin7 에서 지웠거나 합쳤다(행 자체가 없다)  → 응답에 안 들어온다 · **2) 단계만이 잡는다**(위 「마스터도 같다」의 「지우거나 합치면 유령 행」)
```
⇒ 2) 단계는 **ⓑ 를 위해 남는다.** 폐기가 아니다. 다만 ⓐ 가 대부분이라 2) 가 내리는 수는 작아야 정상 — 회차 로그의 「내린 수」가 크면 ⓑ 보다 **API 가 일부만 준 것**을 먼저 의심한다.
⚠️ [검토 Claude 정정] 지시서는 「넷이 한 규칙과 실제 구현이 다르다」고 했으나, 코드는 1)~3) 어느 단계도 **아직 구현 전**이다(위 절 머리 · 아래 「열린 것 · 코드」). 다른 것이 아니라 안 한 것이다.
⚠️ 다른 표 실측: ④ `ImsLoadProductSupplier.gs` 는 새로 데려오는 supplier 에 Status 를 읽고(180행 `is_active: String(s.Status) === 'Active'`) product_supplier 줄은 `is_active: true` 만 실어 보낸다(282행) — 2) 단계 없음(③ 과 같은 상태).
⬜ ② 공급처 넷 적재 · product_family · barcode · bom 이 Status 를 읽는지는 **확인하지 않았다.** 「왜 이 표만 다르지」가 나올 자리라 적어 둔다.

### ⬜ 열린 것
```
충돌 키          [2026-09-15] product·product_family 의 sku → **cin7_id + SKU 승격 폴백**(§11-k) — 코드 고칠 때 함께 · 위 표는 그때 갱신
코드              Cin7 정리 뒤 · 1)~3) + 되살아남 주석 · 회차 로그(내린 수 · 되살린 수)
cin7_id 유지      SKU 변경에도 유지되는지 미확인 (§7)
스캔 화면         is_active 필터 — WMS 쪽 일(원칙 2 · 표를 읽는 쪽이 건다)
```

---

## 3-g. ⭐ ④ 제품↔공급처 — `product_supplier` 표 확정 · 적재 완료 (2026-09-14 오후 · 마이그레이션 1 · 같은 날 적재)

**상태**: GAS `ProbeProductSupplier.gs` 로 `GET /product?IncludeSuppliers=true` 전량 18,829 를 실측하고, 설계 검토(이견 넷 · 아래 「검토에서 바뀐 것」)를
거쳐 `20260914175145_product_supplier.sql` 을 만들었다 — 로컬 `db reset` 재생 통과. ~~⚠️ 테스트 DB push · 적재 GAS(`ImsLoadProductSupplier.gs`)는 다음 단계.~~
[같은 날 저녁] **테스트 DB 적재 완료 — 아래 「적재 결과」**. 스킬(`asung-po`)은 적재 뒤 한 번에 고쳤다(정본 먼저 · 스킬에는 「모르면 사고가 나는 것」만).

### 실측 (2026-09-14 · 전량)

```
공급처          688 = 활성 226 + 비활성 462
제품            18,829 (Type=Stock 18,772 · 그중 활성 14,602)
제품↔공급처 줄  ⭐ 12,728 (Type=Stock)   ⚠️ 시트 전체는 12,729 — Stock 아닌 제품의 줄 1 이 섞여 있다 (아래 경위)
  공급처 상태별   활성 11,941 · 비활성 787 · 우리가 모르는 GUID 0
  ⭐ 비활성을 가리키는 공급처는 31곳뿐 · 제품에 붙은 활성 공급처는 144곳 / 226
  ⭐ 쌍 (ProductID, SupplierID) 중복 0 · ProductSupplierID 중복·빈값 0 (psp_step9_gaps)
줄 수 분포      0줄 6,512 · 1줄 11,819 · 2줄 416 · 3줄 이상 25  (= 18,772)
단가            FixedCost>0 8,921 · Cost>0 11,360 · ⚠️ 둘 다 0 인 줄 1,232 · 소수 일곱 자리(Cost 1.3991666 · FixedCost 1.3991667)
통화            CAD 1,584 · USD 11,144 · ⭐ 공급처 기본통화와 어긋난 줄 0 · KRW 없음
채움            공급처SKU 6,981 · LastSupplied 빈 줄 99
                SupplierProductName 0 · SupplierProductURL 0 · DropShip 0 · IncludeInPricing=false 0
창고별 옵션     10,637 줄에 4개씩 달려 있으나 ⭐ Lead·Safety·ReorderQuantity 전량 0 (MinimumToReorder 만 2줄) — Cin7 에서 쓰지 않는 칸
```
⭐ **「기본 공급처」 표시가 Cin7 응답에 없다** — `Suppliers[]`·`ProductSupplierOptions[]` 어디에도 Default·Primary 류 칸이 없다.
⭐ 문서에 없던 칸 둘 — `Suppliers[].IncludeInPricing` · `ProductSupplierOptions[].LocationName`(`cin7-api` 정정).
⚠️ **`ProductSupplierOptions[]` 에 `Default` 가 오지 않는다.** 그런데 `PUT /product-suppliers` 규칙 3은 「`Default:true` 정확히 1개」를 요구한다
⇒ GET 을 그대로 되돌려보내면 반드시 실패한다. ⑤ 에서 우리가 만들어 붙인다(`product-suppliers-write.md` 규칙 3·6).

**⚠️ 12,729 → 12,728 경위** — 검토에서 「상태별 11,941+787 · 통화별 1,584+11,144 가 둘 다 12,728 인데 총계는 12,729 — 한 줄 빈다」가 나왔다.
빈 줄은 없었다. **보고서가 두 모집단을 섞어 찍은 것**이다 — 12,729 는 시트 전체 행(Stock 아닌 제품의 줄 포함), 상태별·통화별은 Type=Stock 만 센 수.
⇒ 정본은 12,728(Type=Stock). 📌 같은 표에서 나온 숫자라도 **어느 모집단을 센 것인지**를 먼저 맞춘다(§3-d 「14,677 은 활성만」과 같은 부류).

### ⭐ 판단 (Caleb 확정 2026-09-14)

**① 비활성 공급처 줄도 담는다 — 표 범위는 226 + 31 = 257**
- 비활성 공급처 = 「지금도 앞으로도 구매하지 않을 곳」. 그래도 줄은 담는다 — 「이 제품을 예전에 어디서 샀나」는 Cin7 이 지우면 복원할 수 없다(원칙 1).
  발주 후보에서 빼는 일은 **읽는 쪽이 `supplier.is_active` 를 걸어서** 한다(§3-f 와 같은 모양).
- ⚠️⚠️ 688 전부를 담지 않는다 — 비활성 462 의 대부분은 경비 지출처(§7-a 의 경계 · QBO 영역).
- ⭐ 「31곳」을 목록으로 박지 않는다 — 적재가 스스로 판정한다:
  ```
  ① 제품 전량을 IncludeSuppliers 로 훑어 등장한 SupplierID 를 모은다
  ② 그중 supplier 표에 없는 것을 넣는다 (is_active=false · is_purchasable null · 이번 실측 31곳)
     ⚠️ Suppliers[] 에는 SupplierID·SupplierName 만 온다 — supplier 의 NOT NULL 칸(payment_term_name · account_payable_code)은
        GET /supplier?IncludeDeprecated=true 전량 688 을 함께 받아 채운다 (검토에서 추가)
  ③ 그다음에 product_supplier 줄을 넣는다 — FK 가 전부 붙는다
  ```
  ⚠️ ②가 ③보다 먼저다(③ 제품의 `imsLinkProductSets` 순서 의존과 같은 모양). 32번째가 생겨도 다음 적재가 알아서 데려온다.
- 이렇게 들어온 31곳은 「제품에 붙어 있어서」 들어온 것이지 「발주처라서」가 아니다 — `is_purchasable` 은 null(Caleb 의 226곳 전수 판정이 여기엔 없다).

**② ④ 는 낱개에만 붙는다 — 「발주는 낱개 단위로 한다」** (⚠️ 콤보 줄은 같은 날 저녁 정정 — 아래 「콤보에 방향이 둘」)
```
세트(parent_product_id 있음)   부모의 공급처·단가를 pack_factor 로 환산해 발주 — ⚠️ 세트 코드에 줄이 붙으면 안 된다(카운터 ⑤ · 0 목표)
콤보(product_bom 의 부모)      ~~⭐ 사지 않는다 — 낱개로 사서 우리가 묶는다(AutoAssembly=true)~~
                               [2026-09-14 저녁 정정] 방향이 둘이다 — 묶는 콤보(줄 없음 · 8)와 사 오는 콤보(줄 있음 · 3 립오일). AutoAssembly 는 15/15 true 라 근거가 못 된다
낱개                            ④ 가 붙는 자리
```
세트에 줄이 없는 것 · 묶는 콤보에 줄이 없는 것은 결함이 아니다 — 이유가 다를 뿐 둘 다 정상.
⭐ **⑤ 발주 화면 규칙**: ~~콤보를 발주 후보에 올리지 않는다 — 콤보 재고가 필요하면 구성품 발주로 푼다.~~ [정정] **「공급처 줄이 있으면 후보」** 하나다 — 사 오는 콤보가 있다(아래 「규칙이 예외 없이 섰다」).
⚠️ [실측] 세트 5,805 중 공급처 줄이 붙은 것 3 — `AS92082-6`·`CRO71964-6`·`EBI68634-6`. 적재는 거르지 않고 넣는다(원칙 1 · 거르면 원문이 사라진다) —
카운터 ⑤ 로 센다. ~~Caleb 이 Cin7 에서 확인한다~~ → [같은 날] **Caleb 이 Cin7 에서 지웠다**(아래 「닫힌 것 일곱」 · `AS92082-6` 의 FixedCost 0.95 가 낱개 값 복사였다).

**③ 「공급처 줄이 0」의 뜻이 넷 — 카운터는 마지막 하나뿐**
```
세트     부모가 갖고 있다              정상
콤보     묶는 콤보 — 사지 않는다      정상 (실측 8 — DP 7 + AS-DSPLY) · ⚠️ 사 오는 콤보 3 은 줄이 있다(방향 둘 · 아래)
선주문   살 곳은 있는데 아직 안 샀다   ⭐ 정상 · 사람이 미리 공급처를 적어 둘 수 있어야 한다 (실물: Custom Reusable Bag 25 — 선주문받아 사입)
진짜     살 곳을 모른다                ⚠️ 채워야 할 목록 (카운터 ④)
```
⚠️ 셋째와 넷째는 데이터로 구별되지 않는다 — 둘 다 줄이 없고 `LastSupplied` 도 없다.
⇒ 사람이 적은 줄은 `source='manual'` 로 들어오고 재적재가 지우지 않는다(§3-f). ⇒ **단가 없는 연결을 허용한다** — Cin7 에도 둘 다 0 인 줄이 1,232 있다.

**④ 기본 공급처는 우리 칸(`is_default`)으로 만든다**
```
후보            ⭐ supplier.is_active=true 인 줄만 (검토에서 추가 — 787줄이 비활성을 가리킨다 · 가장 최근이 비활성이면 「앞으로도 안 살 곳」이 기본이 된다)
줄이 하나면      그것이 기본
둘 이상이면      last_supplied 가 가장 최근인 것
가릴 수 없으면   비워 두고 센다 (카운터 ② · 화면에서 사람이 고른다) · 활성 줄이 없어도 같다
is_discontinued  기본 계산에 안 쓴다 — 화면 경고로만
```
⭐ **바뀔 때 누가 이기나 — `source` 로 가른다.** 그 제품에 `source='manual'` 줄이 하나라도 있으면 재적재가 `is_default` 를 다시 계산하지 않는다.
사람이 손대지 않은 제품만 `last_supplied` 기준으로 갱신한다(②의 `is_purchasable` 을 Cin7 재동기화가 못 덮게 한 것과 같은 장치).
❌ `product.default_supplier_id` FK 대안은 채택하지 않았다 — 제품당 하나가 구조로 보장되지만 `product` 를 ALTER 하면 **③ 이 ④ 의 사정을 알게 된다**(원칙 2). `is_primary` 선례와 맞춘다.

### 표 — `product_supplier` (`20260914175145`)

⚠️ `ref_` 를 붙이지 않는다(§3-b · 관계 표). 칸 순서는 `product_barcode` 선례대로 공통 7칸 먼저.
```
공통 7칸       id · cin7_id(unique) · is_active · source · note · created_at · updated_at   — name 없음(관계 표 · §5 예외)
product_id     not null → product(id)    on delete no action
supplier_id    not null → supplier(id)   on delete no action
supplier_sku   SupplierInventoryCode
cost           numeric(18,7)  Cost · 최근 매입가(LATEST PRICE)     ⚠️ Cin7 의 「없음」은 0 — 0 은 0 으로 둔다(원문) · manual 줄의 없음은 null
fixed_cost     numeric(18,7)  FixedCost · 합의 고정가(FIXED PRICE)  읽는 쪽 폴백 fixed_cost>0 → cost>0 → 없음 이 둘을 같은 「없음」으로 읽는다
currency_id    → ref_currency(id) nullable   오늘 CAD·USD 만이지만 「오늘의 사실이지 규칙이 아니다」 · 못 이은 줄은 null 로 넣고 센다
last_supplied  date   Cin7 이 T00:00:00 시간대 없이 준다 (시간대 미판정 · registered_on 과 같다)
is_default     boolean not null default false   ⭐ 우리 칸
unique (product_id, supplier_id)   ⭐ 12,728 줄 실측 중복 0 위에 건다 — 「같은 쌍 두 줄 금지」는 우리 규칙
CHECK product_supplier_source_ck · 인덱스 셋 product_supplier_{product_id,supplier_id,currency_id}_idx · 트리거 set_updated_at() 재사용 · ~~auth_all~~(→ 09-17 select 열림·쓰기 ims_can_write('master') · §5 권한 규약) · revoke anon · revoke truncate(DELETE 는 연다)
```

**⭐ 충돌 키는 `cin7_id`(ProductSupplierID) — 그리고 승격 규칙** (검토에서 바뀐 것 · 아래)
```
충돌 키          cin7_id — Cin7 이 유니크를 보장 · ~~⑤ PUT /product-suppliers 의 필수 열쇠(없으면 단가를 Cin7 에 못 쓴다)~~ → [2026-09-16] 전환 기간엔 IMS 가 Fixed Price 를 **안 고친다**(§11-d · Caleb)라 PUT 도 없다. 충돌 키 판단은 그대로다 — 근거는 「Cin7 이 유니크를 보장 · manual 줄 승격의 열쇠」
승격             사람이 먼저 적은 manual 줄(cin7_id null)과 같은 (product_id, supplier_id) 가 Cin7 에 나타나면
                 새 행을 만들지 않고 그 행에 cin7_id·단가를 PATCH 로 채운다 · source 는 manual 유지(사람이 만든 줄이라는 사실은 남긴다)
                 ⚠️ 이 규칙이 없으면 선주문 시나리오(③)가 (product_id, supplier_id) 유니크에 걸려 배치가 실패한다
재적재 갱신 대상  「source='cin7'」이 아니라 「cin7_id 가 있는 줄」 — §3-f 의 2) (안 들어온 줄 is_active=false)도 같은 기준
못 이은 줄        supplier_id·product_id 를 못 찾으면 넣지 않고 센다 — 오늘 0(우리가 모르는 GUID 0)이어도 장치는 둔다
```
공통 8칸에서 벗어나는 곳은 의도된 것 — `name` 없음(관계 표) · `cin7_id` 가 보조가 아니라 열쇠(⑤ PUT) · DELETE 개방(관계 표 관례 · TRUNCATE 는 막는다).
⚠️⚠️ **부분 유니크 인덱스 금지** — `is_default` 가 제품당 하나임을 인덱스로 강제하지 마라(WMS 규칙 29). 카운터 ①로 센다.

### 담지 않는 것 — 「봤고 비어 있어서 뺀다」
```
ProductSupplierOptions 전체   창고별 Lead·Safety·ReorderQuantity 전량 0 (10,637줄 × 4) — 제품 × 공급처 × 창고 축은 지금 만들지 않는다 · 필요해지면 다시 긁어온다(마스터는 소급이 된다)
SupplierProductName · URL     0곳
DropShip                      0곳
IncludeInPricing              false 가 0곳 (전부 true)
PurchaseCost                  FixedCost 와 같은 값
Currency 문자열               공급처 기본통화와 어긋난 줄 0 ⇒ 공급처에서 따라온다 · ⚠️ 단 currency_id 는 둔다
```

### 카운터 여섯 (적재 뒤 SQL · ⚠️ 전부 `is_active` 를 걸고 센다 · §3-f) — ⑤ 는 0 목표 · ⑥ 은 기대값

~~다섯~~ [2026-09-14 저녁] 초안의 ⑤ 「세트·콤보에 붙은 줄(0 목표)」은 **둘을 섞은 것**이었다 — 세트에 붙은 줄은 사고(0 목표)지만 콤보에 붙은 줄은 「사 오는 콤보」라는 사실이다(아래 「콤보에 방향이 둘」). 검토에서 갈랐다.
```
① is_default 가 둘 이상인 제품                  부분 유니크를 못 거는 대신 센다                                        최종 0
② 기본을 못 정한 제품 (활성 줄은 있는데)        날짜 없음·동점 · ①로 꺼진 manual 제품 — 화면에서 사람이 고른다              최종 2
③ 단가가 둘 다 없는 활성 줄                     발주 단가 폴백이 비는 자리                                             최종 1,227 (적재 전 1,232 — 내린 7줄 중 5)
④ 활성 낱개인데 활성 줄이 0                     ⚠️ 세트·콤보·선주문(manual 줄 있음)을 뺀 뒤의 수 — 성격이 셋(아래)          최종 27
⑤ ⚠️ 세트에 붙은 활성 줄                        0 목표 — 실물 사고 AS92082-6(여섯 개를 하나 값으로 발주할 뻔)             최종 0 (Cin7 정리 뒤)
⑥ ⭐ 사 오는 콤보 (콤보에 붙은 활성 줄)         0 이 목표가 아니다 · 기대값 3(립오일) · **변화가 신호** — 3→4 면 사람이 본다  최종 3
```

### ⚠️ 검토에서 바뀐 것 — 초안 대비 (2026-09-14 · 「그대로 만들어라」가 아니었다)
```
✅ 충돌 키 cin7_id + 승격 규칙          초안은 (product_id, supplier_id) 유니크만 있고 쌍 유니크 실측·manual 승격 경로가 없었다 → 실측 후 유니크 유지 · 승격 규칙 추가
✅ is_default 후보 = 활성 공급처         초안은 last_supplied 만 봤다 — 비활성이 기본이 될 수 있었다
✅ 12,729 → 12,728                       두 모집단이 섞인 숫자 — 위 경위
✅ ② 단계에 GET /supplier 전량 명시      Suppliers[] 만으로는 supplier 의 NOT NULL 칸을 못 채운다
✅ 세트 3건은 거르지 않고 넣는다          카운터 ⑤ 신설
✅ 단가 0 은 0 으로                       Cin7 원문 · manual 은 null · 폴백이 둘 다 「없음」
❌ product.default_supplier_id 대안       채택 안 함 — 원칙 2
📌 KRW 없음(전수 CAD·USD) · currency_id nullable 은 그대로
```

### ~~⬜ 다음~~ → 같은 날 저녁에 했다 (아래)
```
~~적재 GAS   ImsLoadProductSupplier.gs~~   ✅ 아래 「적재 결과」 · 원자료 시트(psp_line)를 읽어 Cin7 을 다시 훑지 않았다
~~SQL 검증   카운터 다섯~~                 ✅ 여섯으로 갈라 셌다(위)
화면 ⓐ     마스터 조회·편집 — 시트로 우회하던 것들(supplier_discount 0행 · is_purchasable · 새 바코드 · ref_bin.zone)과
           오늘 생긴 것(기본 공급처 지정 · 선주문 제품의 공급처 · 콤보 방향).
           ⭐ 자리   ims.asung.ca (asungtrading/asung-ims) · DB 는 Asung-IMS · §10 — ⚠️ 가입 닫기 확인 전에는 배포하지 않는다(§10-f ⓪)
           ~~⚠️ 먼저 asungtrading/tools/purchasing.html 을 읽어라 — 붙이는 일일 수 있다~~ [2026-09-14] 읽었고 **붙이지 않는다** — 겹치는 기능이 없고 컷오버 때 통째로 옮길 대상(§10-d)
           채울 것(적재 뒤 실측 · §3-g):
             기본 공급처를 못 정한 제품 2                   카운터 ② — 사람이 골라야 한다
             살 곳을 적을 제품 26(선주문 Bag 25 + AS01433)   source='manual' 로 미리 적을 자리
             AS91437-BLK                                    Type=Non Inventory 라 ④ 모집단에서 빠졌다 — 공급처를 손으로
             새로 들어온 공급처 31곳의 is_purchasable        전부 null(미판정)
```

### ✅ 적재 결과 (2026-09-14 저녁 · 테스트 DB `Asung-IMS`)

```
product_supplier   12,728 줄 적재 → 그중 7 줄을 내렸다(아래 「닫힌 것 일곱」) → 활성 12,721
supplier           226 → 257 (제품이 가리키는 비활성 공급처 31곳을 데려왔다 · is_active=false · is_purchasable null)
제품               12,260 개가 공급처 175 곳과 이어졌다 (활성 144 + 비활성 31)
is_default         11,480 개 제품에 붙었다
```
**적재 GAS — `docs/probes/ImsLoadProductSupplier.gs` · 프로브 `docs/probes/ProbeProductSupplier.gs`**(사본 · 원본은 GAS · ⭐ 프로브도 함께 둔다 — 이 절이 `psp_step9_gaps`·`psp_step10_bomdirection` 을 근거로 인용하므로 코드가 레포에 없으면 다음 사람이 확인할 수 없다)
```
imsLoadSupplierExtraApply()      ①②③ 공급처 보충 + 줄 원자료를 시트에 적는다 (19콜 · 이어받기)
imsLoadProductSupplierApply()    ④ 시트를 읽어 줄을 넣는다 (Cin7 안 부른다 · 26묶음 11초)
SQL                              ⑤ is_default (아래 「끄고 나서 켠다」) · 카운터 여섯
```
⚠️ **시트를 거치며 날짜가 깨졌다** — `'2025-10-03T00:00:00'` 를 시트가 Date 로 바꾸고 다시 읽으니 `'Fri Oct 03'`(연도 소멸).
⇒ 전 칸 텍스트 서식(`@`) + 문자열로 기록 + 읽을 때 모양 검사(아니면 멈춘다). GAS 가 시트를 중간 저장소로 쓸 때마다 같은 자리다.

📌 **기본이 없는 제품 780 = 12,260 − 11,480 — 두 부류뿐이다**
```
778   활성 공급처 줄이 없는 제품 — 후보가 아예 없다 (비활성 공급처만 가리킨다 · 787줄이 그쪽 · 오늘 내린 세트 셋·JAL 콤보 넷도 여기 들어 있다)
  2   활성 줄은 있는데 못 고른 제품 — 카운터 ②
```
⚠️ 「기본이 없다」와 「기본을 못 정했다」는 다르다. ⚠️ 검토 중 「775 + 2 + 3(세트)」으로 잘못 분해했었다 — 세트 셋은 778 안에 이미 있어 이중으로 셌다. 쓰지 마라.

### ⭐ 규칙이 예외 없이 섰다 (Caleb 이 Cin7 을 정리한 뒤)

```
공급처 줄이 있다   →  그 코드로 산다      (낱개 · 사 오는 콤보)
공급처 줄이 없다   →  그 코드로 안 산다   (세트 · 묶는 콤보)
```
⭐ **⑤ PO 발주 화면의 규칙은 「공급처 줄이 있으면 후보」 하나다.** ❌ ~~「콤보는 발주 후보에서 뺀다」~~ 는 틀렸다 — 사 오는 콤보가 있다.
⚠️ **단 세트는 예외다** — 세트는 줄이 없어야 하고 **부모로 산다**(pack_factor 환산). 세트 코드에 줄이 붙으면 그 줄이 「후보」로 읽혀 여섯 개를 하나 값으로 발주한다(`AS92082-6` 실물). 카운터 ⑤ 가 그 자리다.
⚠️ 묶는 콤보에 줄이 잘못 붙으면 방향 칸이 서기 전까지 「사 오는 콤보」로 읽힌다 — ⑥ 의 **변화**가 그 신호다(JAL 콤보 넷이 오늘 그 실물이었다).

### ✅ Cin7 정리로 닫힌 것 일곱 (Caleb 이 화면에서 지웠다)

```
세트 셋    AS92082-6 · CRO71964-6 · EBI68634-6
콤보 넷    JAL99890CB · JAL99891CB · JAL99892CB · JAL99893CB   (빗자루·쓰레받기 · 전부 낱개로 주문한다 — 묶는 콤보)
```
⚠️ **실물 근거** — `AS92082-6`(세트 ×6)의 FixedCost 가 낱개 `AS92082` 와 **같은 0.95** 였다. 여섯 개짜리인데 낱개 값이 복사돼 있었다. Cost 는 0(세트 코드로 산 적이 없다).
⇒ 그대로 뒀으면 발주 화면이 **여섯 개 값을 하나 값으로** 발주했을 것이다.
우리 표에는 손으로 반영했다 — `is_active=false` 7줄. §3-f 가 다음 재적재에 할 일을 앞당긴 것이라 결과는 같다.

### ⭐⭐ 새로 드러난 것 — 콤보에 방향이 둘 있다 (⑤ 로 넘긴다)

```
묶는 쪽    낱개로 사서 우리가 디스플레이를 만든다      DP 일곱 · AS-DSPLY (+ 오늘 정리한 JAL 넷)  → 공급처 줄 없음
가르는 쪽  디스플레이로 사서 우리가 갈라 판다          립오일 셋 UNF18259·18260·18261            → 공급처 줄 있음(FixedCost 7.92)
```
⚠️⚠️ **Cin7 에 이 방향이 없다** (2026-09-14 실측 · 콤보 15 전수 · `ProbeProductSupplier.gs` `psp_step10_bomdirection`):
```
BOMType      15/15 Assembly
AutoAssembly 15/15 true      AutoDisassembly 15/15 false
그 밖         AssemblyInstructionURL 전부 빈 문자열 · AssemblyCostEstimationMethod 전부 Average Cost
```
⇒ 실무에서 갈리는 것을 Cin7 이 담을 자리가 없어 **한쪽으로 뭉뚱그렸다** — `ims-principles.md` §4-d 와 같은 부류(자리가 없어 다른 칸을 빌려 쓴 것들).
⭐ **지금은 공급처 줄 유무가 그 판정이다**(위 규칙). Cin7 정리 뒤 예외가 없어졌다.
⬜ **⑤ 에서 방향 칸을 둔다** — 초기값은 공급처 줄 유무로 채우고 화면에서 고친다. ⚠️ 지금 만들지 않는다 — 원장이 그 값을 실제로 쓸 때(디스플레이 1개 입고 → 낱개 24개) 만든다.
   ⚠️⚠️ **자리의 조건 = 부모(콤보)당 하나.** 방향은 콤보 단위의 사실이다. `product_bom` 은 구성품 줄 표(콤보 15 에 65줄)라 **줄에 두면 한 콤보 안에서 값이 갈릴 수 있다**(에러 없음) — 두지 마라.
   후보 둘: `product` 의 콤보 전용 nullable 칸 · BOM 머리 표. 둘 다 ③ 의 표라 원칙 2 문제는 없다. 자리는 ⑤ 에서 정한다(§7 ⬜).

### ⚠️⚠️ `is_default` 재계산 — 끄고 나서 켠다

**[실사고 2026-09-14] 첫 SQL 이 켜기만 하고 끄는 쪽이 없었다.** 줄을 `is_active=false` 로 내려도 `is_default=true` 가 그대로 남아 **비활성 줄이 기본**인 상태가 됐다(세트 셋).
재적재 때마다 같은 일이 생긴다 — §3-f 가 안 들어온 줄을 내리기 때문이다. ⇒ 아래 두 문장을 **한 벌로** 돈다. ①이 먼저, ②가 나중.
⭐ **끄기에는 manual 보호가 없다**(검토에서 바뀐 것) — 불가능한 기본(줄이 비활성 · 공급처가 비활성)을 끄는 것은 사람의 선택을 덮는 게 아니라 **비우는** 것이다.
켜기(②)만 manual 을 보호한다. ①로 꺼진 manual 제품은 카운터 ②에 잡혀 사람이 다시 고른다.
```sql
-- ① 자격을 잃은 것을 끈다 (줄이 비활성 · 공급처가 비활성) — manual 보호 없음
update product_supplier ps
set is_default = false
from supplier s
where s.id = ps.supplier_id
  and ps.is_default
  and (not ps.is_active or not s.is_active);

-- ② 기본이 없는 제품에만 켠다 (활성 공급처 줄만 후보 · 동점·날짜없음은 비워 두고 센다 · manual 줄이 있는 제품은 건드리지 않는다)
with cand as (
  select ps.id, ps.product_id, ps.last_supplied,
         count(*) over (partition by ps.product_id) as n,
         rank()   over (partition by ps.product_id order by ps.last_supplied desc nulls last) as rk,
         count(*) over (partition by ps.product_id, ps.last_supplied) as tie
  from product_supplier ps
  join supplier s on s.id = ps.supplier_id
  where ps.is_active and s.is_active
    and not exists (select 1 from product_supplier m
                    where m.product_id = ps.product_id and m.source = 'manual')
    and not exists (select 1 from product_supplier d
                    where d.product_id = ps.product_id and d.is_default)
)
update product_supplier ps
set is_default = true
from cand
where ps.id = cand.id and cand.rk = 1
  and (cand.n = 1 or (cand.last_supplied is not null and cand.tie = 1));
```
⬜ 이 두 문장은 **재적재마다** 돌아야 한다 — ⑤ 에서 적재 스크립트에 붙이거나 cron 으로(§7 ⬜).

### ④ 살 곳이 없는 27건 — 성격이 셋

```
25  Custom Reusable Bag (AS92620~AS92644)   ⭐ 선주문 제품 — 만들어는 뒀고 주문이 들어온 적이 없다. 주문이 오면 살 곳은 있다
                                              ⇒ source='manual' 로 미리 적어 둘 자리(화면 ⓐ)
 1  AS01433                                   KIM & C Teasing Brush 벌크 팩
 1  ⚠️ AS91437-BLK                            ③ 에서 imsLoadProductExtra 로 따로 넣은 그 한 건. Cin7 에서 Type=Non Inventory 라
                                              ④ 적재 모집단(Type=Stock)에서 빠졌다 ⇒ 결함이 아니라 **모집단이 달라 생긴 구멍** — 공급처를 따로 채워야 한다(§7 ⬜)
```
⚠️ 이름이 같은 다섯 종(Bag 1~5)에 SKU 가 스물다섯이다 — 화면은 SKU 를 함께 띄워야 한다(`product.name` 중복 576종과 같은 자리).

### ⚠️ 오늘의 실수 — 「내가 만든 라벨」이라는 새 모양

§3-e 의 「화면에 그럴듯한 값이 있으면 실측으로 착각한다」와 뿌리가 같고, 모양이 하나 늘었다:
```
⚠️⚠️ 내가 붙인 라벨을 실측으로 믿었다 — SQL 에서 parent_product_id is null 을 「낱개」라 이름 붙이고 그것을 「콤보가 아니다」로 읽었다.
     ⭐ 콤보는 부모다 — parent_product_id 가 비어 있는 것이 맞다.
     ⇒ 멀쩡한 ③ 적재를 결함이라 판단하고 BOM 전량 훑기를 두 번(38페이지 × 2) 돌렸다.
⚠️ 원인을 단정하고 프로브를 짰다 — 「IncludeBOM 이 조기 종료시켰을 것」은 틀렸다(p38 까지 전부 500).
⚠️ 두 모집단을 섞어 찍었다 — 12,729(시트 전체)와 12,728(Type=Stock) · 그리고 780 의 분해(위)에서 한 번 더.
⚠️ 시트를 거치며 날짜가 깨졌다 — 위 「적재 결과」.
```

---

## 4. ⚠️ 판단이 갈린 곳 — 「왜 표마다 다른가」

⭐ **이 절이 이 문서의 핵심이다.** 적어 두지 않으면 다음 사람이 결함으로 본다.

### ① 자연키와 `name` 유니크

```
자연키      name (brand·category·unit·payment_term·warehouse)
            code (account · currency)          ← Cin7·우리 코드가 code 로 참조한다
            복합 (bin)                          ← 창고 안에서만 유일하다
name 유니크  있다 — 대부분(실측 중복 0 · Cin7 이 이름으로 참조하므로 실질 자연키)
            ⚠️ 없다 — ref_account
```
`ref_account` 근거 넷: ⓐ 공급처가 `Code` 로 참조한다(226/226 · `Name` 일치 0) ⓑ `inv-cost`·`inv-doc-cost` 가
`Code` 를 코드에 박아 쓴다 ⓒ `Code` 중복 0(289 전수) ⓓ ⚠️ **`Name` 의 중복 여부는 측정하지 않았다** —
Cin7 이 화면에 `DisplayName`(「_188_: Accounting」 · 코드를 앞에 붙임)을 따로 두는 것은 이름만으로
구별이 안 되는 경우가 있다는 신호다. 측정하지 않은 것을 제약으로 걸면 적재가 조용히 깨진다.

`name` 유니크는 **plain** 그대로 — `lower(name)` 로 바꾸지 않는다. 이 부류의 실제 사례는 대소문자가
아니라 띄어쓰기다(`Net 30`/`Net30`). `lower()` 로는 못 막으므로 제약이 아니라 매칭(§6)의 문제다.

### ② ⚠️⚠️ `ref_payment_term` — Cin7 `Duration` 은 최종 기일이 아니다

```
2%10 Net30   뜻: 기일 30일 · 단 10일 안에 내면 2% 할인 (회계 관용 표기)
             Cin7 Duration = 10     ← 칸이 하나라 할인 기한 쪽을 담았다
```
그대로 기일 계산에 쓰면 **20일이 당겨져** 아직 기한이 남은 건이 연체로 잡힌다.
⇒ 우리는 칸을 나눠 담는다: `net_days`(30) · `discount_days`(10) · `discount_percent`(2) · `is_split`.
**Cin7 이 못 담는 것을 우리가 담는 첫 사례**(원칙 1 — 구조를 베끼는 것이 아니다).
`is_split` 은 숫자 한 칸으로 안 담기는 조건 — 실물 「50% COD & 50% Net30」(Avlon · 절반 즉시 · 절반
30일) → `net_days=30 + is_split=true`. ⚠️ Cin7 공급처 마스터에는 아직 `C.O.D` 로 남아 있다(§7).

### ③ 형식 CHECK

⭐ 기준은 「전수를 봤는가」가 아니라 **「늘어날 수 있는가 · 우리가 만드는가」** 다.
```
건다   — ref_currency.code        ISO 4217 · 우리가 만든다 · 형식이 바뀌지 않는다
       — ref_account.account_class 회계 기본 다섯 · 안 늘어난다 (289 전수)
안 건다 — ref_account.code          Cin7 표기가 이미 두 형식(_숫자_ 215 / 순수 숫자 74) — 걸면 74개가 걸린다
       — ref_account.account_type  16종 · Cin7 이 늘릴 수 있다 (전수를 봤어도 class 와 성질이 다르다)
       — ref_unit.name              39/44 가 숫자 이름이지만 text 다 — numeric·파싱 금지
```
**우리가 만드는 값과 남이 주는 값은 다르다.**

### ④ 기본값 표시 — `inv_config` 냐 표 안이냐

```
inv_config 로 — ref_payment_term(IsDefault) · ref_currency(base_currency)
                「새로 만들 때 뭘 고를까」 = 설정. 표 안에 두면 둘이 true 되는 것을 막을 수단이 부분 유니크뿐
표에          — ref_warehouse.is_default
                ⭐ 창고의 속성이고 Cin7 이 창고 행에 직접 담아 준다(IsDefault=true · Asung Trading Inc.)
                ⇒ 긁어올 때 받을 자리가 필요하다 · 창고가 셋뿐이라 눈으로 보인다(결제조건 34개와 규모가 다르다)
⚠️ 어느 쪽도 부분 유니크로 막지 않는다(WMS 규칙 29 · PostgREST on_conflict 를 깨뜨린다)
```
`inv_config.base_currency` ↔ `ref_currency` 에 FK 는 없다 — `inv_config` 는 key-value 표라 `value` 가
문자열이고 FK 를 걸면 다른 설정값이 전부 막힌다. 그래서 값 2행이 실재해야 한다(⑤).

### ⑤ 값 적재

```
행 0건 — 일곱 표(Cin7 에서 긁어온다 · 적재는 별도 작업)
2행    — ref_currency 뿐 (+ inv_config 1행)
```
예외의 이유 둘: ⓐ Cin7 에서 긁어올 데가 없다 — 누군가는 손으로 넣어야 하고 두 줄뿐이다 ⓑ `base_currency='CAD'`
가 가리킬 대상이 표에 실재해야 한다. ⚠️ 「마이그레이션에 데이터를 넣어도 된다」가 **아니다.** 재실행
안전은 `on conflict do nothing`.

### ⑥ `cin7_id` 가 있는 표와 없는 표

`cin7_id` 는 Cin7 행과의 매핑 고리(우리가 새로 만든 행은 null). `ref_currency` 는 Cin7 에 대응
엔드포인트가 없어 영원히 비게 되므로 안 쓰는 칸을 두지 않았다 — **우리가 처음부터 세우는 첫 마스터.**
`sort_order` 를 어디에도 넣지 않은 것과 같은 이유(Cin7 이 주지 않고 실무 요구도 없다 · 빈 표에 컬럼 추가는 공짜).

---

## 5. ⭐ 공통 규약 — 새 마스터 표를 만들 때

```
공통 8칸    id uuid PK gen_random_uuid()   ⭐ 우리 키 — Cin7 GUID 를 PK 로 쓰면 Cin7 이 사라질 때 신원이 사라진다(ims-principles §4-b)
            cin7_id uuid unique (plain · null 허용 · 부분 유니크 금지)
            name text not null (유니크는 표마다 — §4-①)
            is_active boolean not null default true   ⭐ Cin7 에 없는 우리 칸 — 지우지 않고 물러나게 하는 수단
            source text not null default 'cin7' check in ('cin7','manual')   재동기화가 덮어써도 되는지의 근거
            note text
            created_at / updated_at timestamptz not null default now()
RLS         ~~auth_all (ALL · authenticated · using true / with check true)~~ → ⭐ [2026-09-17 밤 · `20260917235000`] **select 열림(using true) · insert/update/delete = `(select ims_can_write('<묶음>'))`** · 정책 이름 `<표>_<동사>`(select·insert·update·delete)
            ⚠️ 마스터는 delete 권한 자체가 없어(아래) delete 정책을 만들지 않는다(정책 셋) · 관계 표·거래 표는 넷 · 묶음 = perms 화면 값(master · purchasing · receiving · staff) · revoke all from anon · service_role 개방 없음
            ⚠️ 정책 안의 함수는 `(select …)` 로 감싼다 — 안 그러면 행마다 평가된다(다건 insert 에서 ims_staff 조회가 행 수만큼). 규약 셋은 아래 「권한 규약」
⚠️ 권한      revoke delete, truncate from authenticated
            근거: 마스터는 지우지 않고 is_active 로 물러나게 한다. 브랜드 한 줄을 지우면 그것을 가리키던 제품이 갈 곳을 잃는다.
            ⚠️ inv_config·inv_sku_types 관례(안 막음)를 따르지 않는다 — 그쪽은 지워도 다시 만들 수 있는 캐시·설정이다
⭐ 트리거    ~~공용 함수 set_updated_at() · 표당 트리거 하나 <표>_set_updated_at~~ → ⭐⭐ [2026-09-18 · `20260918133858`] **IMS 표는 <표>_touch … ims_touch()** — updated_at 은 지금 · **updated_by** 는 auth.uid() → ims_staff.id(없으면 null = system · service_role 적재) · before update · for each row · 표당 트리거는 여전히 하나(갈아 끼웠다 · 둘을 두면 「어느 것이 이겼나」를 이름 순서로 알아야 한다)
            ⚠️ set_updated_at() 정의는 남긴다(규약 · 다시 만들지 마라) — 그러나 **참조 트리거가 0** 이다. [실측 2026-09-18 · 전 마이그레이션 grep] 이 함수를 쓰던 트리거는 IMS 표 29 뿐이었다 · wms_* 표에 붙은 것은 0 — 지시서의 「WMS 표까지 함께 쓴다」는 실물과 달랐다(133858 이견 1)
            ⚠️ ims_touch 는 **security definer**(ims_staff 를 읽는다 — 쓰는 사람이 못 읽어도 트리거는 읽어야 한다) · set search_path = public, pg_temp · updated_by 는 서버가 채운다(화면이 주면 공개 anon key 로 아무 id 나 줄 수 있다 · created_by 와 같은 자리) · FK ims_staff(id) no action + <표>_updated_by_idx · 새 표는 그 마이그레이션이 같은 두 줄을 넣는다(po_receipt · po_receipt_work · po_receipt_diff 가 그렇게 섰다)
            ⚠️ 재적재가 updated_at 을 전부 움직이는 것은 그대로 둔다 — Cin7 값이 덮은 것은 사실이고 사람이 알아야 한다(updated_by null = system)
            returns trigger 함수는 SQL 로 직접 호출할 수 없어 PostgREST RPC 로 노출되지 않는다 — RPC 관례의 revoke/grant 불필요
            ⚠️⚠️ **이름을 꺼내는 서브쿼리에 별칭을 붙인다** — ims_staff 에 updated_by 가 생긴 뒤 `select name from ims_staff where id = updated_by` 는 ims_staff **자기 칸**과 비교해 에러 없이 null 을 낸다(2026-09-18 하루에 두 번). 전부 `s.id = <바깥>.updated_by` 꼴로
FK          on delete no action (기존 참조 FK 13건 관례 · RESTRICT 0건 · CASCADE 는 문서→소유 라인 7건에만)
            ❌ cascade 금지 — 창고 한 줄에 bin 2,047개가 조용히 딸려 사라진다
            ⭐ FK 컬럼에 인덱스를 직접 만든다(Postgres 는 자동 생성 안 한다) · 이름 <표>_<컬럼>_idx
```

📌 **`name text not null` 이 방어선이 된 실물 (2026-09-14 · §3-e ①)** — `product` 18,714행에서 두 칸만 고치려고 upsert(`merge-duplicates`)를
썼다가 `23502` 로 막혔다. NOT NULL 은 형식 검사가 아니라 **「부분 객체를 행으로 밀어 넣는 도구」를 첫 요청에서 세우는 제약**이다 —
검사가 없었다면 부분 객체가 조용히 통과했다(§1-a 감지되지 않는 결함). 부분 갱신은 PATCH — `asung-wms` 규칙 45.

왜 `updated_at` 을 트리거로 (2026-09-11 이전 public 스키마에 트리거 0개 · `default now()` 만): 쓰는 쪽이
매번 실어 주는 방식은 빠뜨려도 에러가 안 나고 어느 카운터에도 안 잡힌다(감지되지 않는 결함 ·
ims-principles §1-a). 표가 비어 있는 지금이 넣기 가장 안전했다. 함수에 `ref_` 접두어를 붙이지 않은 것은
②공급처·③제품 표가 `ref_` 가 아닐 수 있어서다. ⚠️ `now()` 는 트랜잭션 시작 시각 고정 — 트리거 검증은
문장마다 별도 트랜잭션으로.

### 관계 표의 규약 예외 (2026-09-13 · `supplier_address`·`supplier_contact`·`supplier_discount` 선례 · ③ `product_barcode`·`product_bom` 도 같다)

```
DELETE      막지 않는다 — 마스터가 아니라 관계다(잘못 넣은 바코드·구성품은 지운다). TRUNCATE 는 막는다
            선례: supplier_address(어느 문서도 가리키지 않는다) · supplier_contact(걸러서 지운다) · supplier_discount
공통 칸     ⚠️ 축소하지 않는다 — cin7_id · is_active 는 항상 null 이어도 둔다(supplier_discount 「규약대로 두지만 항상 null」)
            ⭐ product_barcode.cin7_id 는 null 이 아니다 — 흡수한 대체 UPC 62건이 Cin7 ProductID 를 가진 실물 행이다(재적재 멱등 키 · 추적선)
            name 은 관계 표에 없다(주소·바코드·구성 줄에는 이름이 없다) — 7칸
CHECK 이름  <표>_source_ck 로 통일 · 인라인 무명 CHECK 금지(자동 이름이 표마다 달라진다)
⚠️ 금지     부분 유니크 인덱스(PostgREST on_conflict · WMS 규칙 29) — product_barcode.is_primary 가 정확히 그 자리다.
            제약 대신 「제품당 primary 둘 이상」 카운터를 화면에 둔다(평상시 0)
```

### 거래 표의 규약 예외 (2026-09-16 · ⑤ PO 표 열하나가 첫 선례 · `20260916144201`·`20260916153313` · §13)

⭐ 거래(문서·줄·결제)는 **마스터 표 규약의 대상이 아니다** — 컷오버 때 지워지는 쪽이다(§11-⓪ 축).
```
물려받음   id uuid PK · note · created_at/updated_at + set_updated_at 트리거 · RLS(~~auth_all~~ → [2026-09-17] select 열림 · 쓰기 `ims_can_write('purchasing')` · delete 정책 있음 — 삭제 RPC 가 쓴다) + revoke anon · <표>_*_ck 이름 · FK 인덱스 <표>_<칸>_idx
뺌         cin7_id(Cin7 발주·인보이스는 적재하지 않는다 · §11-⓪ 함의 ②) · source(cin7/manual 축이 없다) · is_active(status 가 대신) · name(문서에 이름이 없다)
CASCADE    ⭐ 문서 → 소유 줄에만(po→po_line·po_discount · po_invoice→_line·_discount · po_charge→_alloc · po_payment→_alloc) — 위 「CASCADE 는 문서→소유 라인 7건에만」이 정확히 이 부류
           밖을 가리키는 FK(po_line→product · po_receipt_line→po_line·ref_bin·ims_staff · po_invoice_line→po_line · po_charge_alloc→po · po_payment_alloc→po_invoice/po_charge)는 전부 no action
DELETE     막지 않는다 — 초안은 지울 수 있어야 한다 · 확정 뒤는 취소(cancelled)로 물러난다 · 결제는 사실이라 잘못 넣었으면 지운다. TRUNCATE 는 막는다 · ⭐ [2026-09-17 · `20260917100000`] **판정 축은 confirmed_at — 한 번이라도 확정된 문서는 지워지지 않는다**(status 가 아니다 · 발주도 같다 · §11-b) · 크레딧은 종류로 삭제 금지(§11-c 크레딧 번호) · 결제는 상태가 없어 언제든 지운다(§11-h)
상태       있으면 CHECK · 진행도(입고 · 결제됨)는 상태가 아니라 줄 합으로 계산한다
⚠️⚠️       ~~확정=잠금이지만 지금 확정 문서는 DB 가 보호하지 않는다 — 트리거 없음(⬜ 분할 함수 차수에 예외 경로와 함께)~~ → [2026-09-16 오후 정정] **확정은 잠금이 아니다**(§11-b · 「공급사에 보낼 수량과 라인이 정해졌다」). 막는 것은 둘(받은 것보다 적게 줄이기 · closed/cancelled 문서 고치기)이고 **RPC 가 저장 전에 본다**(po_line_update · po_line_delete · §13-d)
⭐ 다른 행     다른 행을 봐야 하는 제약은 트리거 대신 — **읽기는 RPC warnings**(크레딧 · credit_for 가 크레딧을 가리킨다 · 다른 공급처 · 붙어 있는데 alloc 으로도 썼다 · §11-g) · **쓰기는 RPC 가 저장 전에 본다**(사후 warnings 로 구별이 안 될 때 — 수량 감축과 초과 입고는 둘 다 remaining 음수 · §11-b). 같은 행 안의 것만 CHECK
채번       첫 시퀀스 선례 — po_number_seq + po_next_number() 를 기본값으로 · authenticated 에 USAGE 필요 · 롤백된 번호는 빈다(허용)
함수 시그니처  ⭐ [2026-09-17] **인자를 늘려 시그니처가 바뀌면 create or replace 가 아니라 drop + create 다** — replace 는 옛 판을 남겨 같은 이름의 함수가 둘이 된다(PostgREST 의 이름 인자 호출이 둘을 다 맞춘다). 레포 첫 사례 `20260917170000`(po_invoice_create + p_line_qty). 인자 타입이 같으면(기본값만 바뀜) replace 로 된다(`20260916210000`)
```

### ⭐⭐ 권한 규약 셋 (2026-09-17 밤 · 마이그레이션 여덟 · §10-h 「등급·두 축」이 판정 함수의 정본)

```
① RLS 는 읽기를 열고 쓰기만 조인다   select using(true) — 화면들이 서로 참조한다(리시빙이 product·product_barcode 를, 발주가 supplier·ref_currency 를). anon 은 이미 전부 회수.
                                  insert/update/delete = (select ims_can_write('<묶음>')) · ~~표 28 · 정책 104~~ → [2026-09-18] **표 31(+ ims_staff = 32) · 정책 116**(마스터 11×3 · 관계 6×4 · 거래 10×4 · po_receipt_line 4 · ⭐ 리시빙 셋 po_receipt·po_receipt_work·po_receipt_diff 3×4 · ims_staff 3 — 마이그레이션에서 센 수 · 실물 pg_policies 확인은 ⬜ · 「표 28」은 ims_staff 를 빼고 센 것이었다(133858 머리 주석)) · 뷰는 security_invoker 라 select 만 탄다 · GAS 적재는 service_role(안 탄다)
                                  ⚠️ CASCADE 삭제는 부모 정책만 본다(자식 delete 정책은 화면 직접 삭제 경로용)
② ⭐⭐ 쓰기 RPC 규약               **첫머리에서 ims_require_write('<묶음>', 'saved'|'deleted') 를 부르고, delete·update 뒤 row_count(또는 returning 뒤 if not found)를 본다.** 23 함수 전부(20260918000000·003000·013000).
   근거 (검토가 찾았다)            ⚠️⚠️ **RLS 는 쓰기를 거부하지 않고 안 보이게 한다.** 읽기 전용 사용자가 삭제 RPC 를 부르면 앞의 select 검사는 통과하고(읽기 열림) delete 는 0행 — 함수는 row_count 를 안 봐 `deleted: true` 를 돌려줬다.
                                  정책은 막았고 **함수가 거짓말을 했다.** insert 만 42501 로 죽는데 그 문장은 사람이 읽는 말이 아니다 ⇒ 둘 다 고친다(권한이 있어도 0행일 수 있다 — 그 사이 남이 지웠다 — 그래서 ②의 둘째도 필요)
   두 묶음 함수                    po_discount_save · po_discount_delete 의 p_target='supplier' 는 supplier_discount(master)를 쓴다 ⇒ **갈래 안에서** 가른다(case when p_target='supplier' then 'master' else 'purchasing').
                                  ⭐ 그때는 권한 검사가 함수 첫머리가 아니라 p_target 검증 바로 뒤다 — **인자가 어느 권한을 물어야 하는지를 정하기 때문**(인자를 읽기 전에는 묶음을 모른다). 그래도 어떤 select 보다 앞.
   거부 문장 하나                  「You cannot change <묶음> data — ask an admin to add the '<묶음>' permission — nothing was saved|deleted」(20260918010000 · 도우미 ims_require_write 가 만든다 · 함수는 perform 만)
                                  ⚠️ **읽기 여부를 말하지 않는다.** [실측 2026-09-17] purchasing 만 가진 사람은 ims_can_view('master')=false 인데 표의 select 는 열려 있어 product·supplier 를 다 읽는다 —
                                  「읽기는 되는데 쓰기가 안 된다」고 말하면 실물과 어긋난다. ⭐ **ims_can_view 는 「데이터를 읽을 수 있나」가 아니라 「그 화면에 들어갈 수 있나」다**(메뉴·탭 노출 판정)
   0행 문장                        「<문서> was not saved|deleted — it may have been removed or changed by someone else just now — nothing was …」 · 미리 보기(p_commit=false)도 막는다(왜 미리 보기는 되는데 저장이 안 되지, 를 만들지 않는다)
   시그니처 무변                    본문만 바뀌면 create or replace(같은 OID · grant·comment 유지) · 인자가 늘면 drop+create(위)
   ⭐⭐ security definer 예외 하나     **po_receipt_confirm**(`20260918203805` · 이견 1) — 확정이 po·po_line·po_discount 에 쓰는데(번호 바꾸기 · 닫기 · b 문서) 그 표는 purchasing 이고 창고 담당은 receiving 만 갖는다.
                                  invoker 로 두면 update 는 0행(조용히) · insert 는 42501 — 「권한은 있는데 확정이 안 된다」. purchasing 을 함께 요구하면 창고 담당이 확정을 못 한다.
                                  ⇒ 문 앞에서 ims_require_write('receiving') 을 묻고(auth.uid() 는 definer 안에서도 JWT 를 읽는다) 그 뒤 쓰기는 정의자 권한으로 · revoke public/anon · search_path 고정 · 모든 update 뒤 row_count
                                  ⚠️⚠️ **둘째 겹(RLS)이 이 함수에서는 없다.** 고칠 때 다른 함수보다 조심한다 · **따라 하지 마라** — 다른 쓰기 RPC 는 전부 invoker
③ 옛/새 행 비교가 필요해 보이면      **먼저 using/with check 각각의 엄격 조건으로 표현할 수 있는지 본다** — ims_staff 의 「자기보다 아래만」은 using 에 옛 등급 · with check 에 새 등급을 각각 엄격 비교로 두어
                                  트리거도 RPC 도 없이 막혔다(자기 행 = 같은 등급 = 불가 · 승격 상한 · 낮췄다 올리기 차단 — §10-h). 트리거(규약 위반)·RPC(화면 수정) 는 그 뒤의 선택지다
```

---

## 6. ⚠️ 매칭 — 아직 만들지 않은 것

Cin7 에서 `Net30` 이 오면 우리 표의 `Net 30` 에 잇는다 — 그 매칭은 표가 아니라 **불러오는 코드의 일**이다.
- ⭐ 정해진 원칙 하나: 정확히 못 이으면 **비워 두고 센다**(「모르면 비워둔다」). 억지로 붙이면 `Net 30`/`Net 45`
  를 헷갈려 기일이 15일 틀린다.
- ⚠️ Caleb 방침: Cin7 값을 그대로 불러온 뒤 **사람이 전수 검사**한다. ⇒ 결제조건 표는 활성 17개(띄어쓰기
  중복 포함)를 그대로 받을 수 있어야 하고, 정리는 `is_active` 를 끄는 것으로. `source` 칸이 그 검사의
  근거다(`cin7` / `manual` — 재동기화가 손댄 것을 덮지 않게).
- ⭐ Cin7 은 마스터를 GUID 가 아니라 **이름 문자열**로 참조한다(계정만 `Code`). 연결 고리는 이름이고,
  `cin7_id` 는 안정성을 위해 함께 담되 매핑 실패 시 이름으로 붙일 수 있어야 한다. 실측은 §8.
- 적재 시 bin 행 주소 빈 문자열(`''`) → null 로 받는다.

---

## 7. ⬜ 알고 시작하는 위험

- ⚠️ **Cin7 공급처 마스터가 실무를 못 따라온다** — [실물] Avlon 은 Cin7 에 `C.O.D` 로 남아 있으나 실제 조건은
  「50% COD & 50% Net30」(Caleb 확인). ⇒ 「우리 표에 잘 이어졌다」와 「그 값이 맞다」는 다르다. 전수 검사가 그래서 필요하다.
- ⚠️ 비활성 결제조건 3종(`Net30`·`Net45`·`1%20 Net30`)을 공급처 24곳이 여전히 쓴다.
- ⚠️ 제품 마스터 14,677개에 우리 것이 아닌 항목이 섞여 있다(`_숫자_` 형식 · `[:[OrderTotalDiscount]:]` · Type=Service).
  목록이 SKU 순 정렬이라 앞쪽에 몰려 있다 — 앞 몇 페이지만 보고 판단하면 틀린다.
- ⚠️ `ref_bin` 2,675행이 1,000행 캡을 넘는다 — 전량을 읽는 코드는 페이징하거나 `jsonb_agg` RPC. 모르고 읽으면
  **에러 없이 1,000개만 온다.** 브랜드 415행·계정 289행은 캡 아래지만 마스터는 늘어난다.
  [2026-09-15] 넘는 표는 **넷** — `ref_bin` 2,675 · `product_family` 1,141 · `product` 18,714 · `product_supplier` 12,721. 화면은 예외 없이 `.range()`(§10-j 3-a).
- ⬜ **채워야 할 우리 칸**(is_purchasable 판정 · 기본 공급처 · ref_payment_term 값 · ref_bin.zone·is_staging · 단가 없는 줄 …) — 목록은 **§10-k** 한곳에 모았다. 쓰기의 첫 대상.
- ⚠️ 화면에서 통화를 기호로만 구별하면 안 된다 — CAD·USD 둘 다 `$`.
- ⚠️ 환율은 마스터가 아니라 문서에 박는다 — 필요한 것은 「그 거래를 한 날의 환율」. Cin7 도 문서마다 `CurrencyRate`
  (⚠️ Simple Purchase 의 `Invoice.CurrencyRate` 는 null 이라 상위 `CurrencyRate` — `inv-cost` 실측).
- ⬜ KRW 송금의 환차손익 — 인보이스는 USD 로 받고 결제만 원화다. 회계 담당자와 정리할 영역(Caleb 판정) · QBO 연동 때 다시 올라온다.
- ⬜ `inv-cost`·`inv-doc-cost` 가 계정 코드(`_59_`·`_136_` 등)를 하드코딩한다 — 표는 세웠지만 **필터는 건드리지 않았다.**
  QBO 연동 때 옮긴다(2026-09-10 에 고친 것을 또 흔들지 않는다).
- ⬜ 아침 점검 ⑭ — `ref_` 표 여덟은 테스트에만 있다(§2 승격 기준). [2026-09-14] ② 넷·③ 넷도 같다 — 마스터 16표 전부 테스트 한정.
- ~~⬜ `ref_bin.zone` 채우는 방법 미정 — `wms_sku_bins` 에 있지만 마스터가 WMS 표를 읽으면 안 된다(원칙 2 · 원장이
  `wms_order_lines` 를 읽는 「잠정·결합」 빚을 하나 더 지는 것).~~ [2026-09-13 닫음] **bin 이름에서 뽑는다** — 창고별 규칙이 다르다
  (토론토 첫 글자 · 에드먼튼 둘째 글자 · §3 정정 블록) · 2,675 중 2,478 추출 가능 · ⚠️ 못 뽑는 **197건(`…PALLET01` 계열 · Aoneroom · B0601002)은 null 로 두고
  그 수를 카운터로** 남긴다 — 채우지 않는다. bin 이름은 우리가 짓는 값이라 파싱이 허용된다(§4-③ 「우리가 만드는 값과 남이 주는 값은 다르다」 · SKU 접미사와 다른 이유).
- ⏸ **판매 게이트는 ⑤ 이후에 사건으로 만든다 — `No Channel` 을 칸으로 물려받지 않는다** (Caleb 2026-09-13 · §3-d).
  슬롯3 의 `No Channel` 은 「재고는 있으나 아직 안 올렸다」는 **지금 상태**이고 재고 도착·보류 해제로 풀린다. `2.Release to WMS` 를
  상태 칸 + 동작으로 옮기기로 한 것(ims-principles §4-d)과 같은 모양 — 칸이 아니라 사건이다.
- ~~⏸ **`pack_factor` 의 정본 미확정** — UOM 이름 · BOM Quantity · SKU 접미사 셋 대조(§3-d 프로브 1) 뒤 정한다.~~ [2026-09-13 닫음] **BOM Quantity 로 확정**(§3-d).
  `AMP41108-12` 는 UOM·BOM 둘 다 6 · 접미사가 틀렸다 — `asung-inv-ledger` 스킬의 반대 기록을 정정했다.
  ~~⬜ 남는 것: `SIS00522-6`(EA-ALT-UPC 인데 BOM ×6 · 활성) 확인 · `AMP41108-12` 접미사 수정 · 구성품 0인 콤보 1건 · `CON00134`.~~ [2026-09-14] 적재 뒤 목록으로 갱신 — 아래 ③ 항목.
- ✅ **③ 적재 GAS — 완료**(2026-09-14 · §3-e · 36,924행 · 테스트 DB). ⬜ **적재 뒤 남은 것(③ 제품)**:
  ```
  SIS00522-6            UOM=EA-ALT-UPC 인데 BOM ×6 · 활성 — 세트인가 대체 UPC 인가 (product 에 남겨 두었다)
  AJA69215-EA-ALT-UPC   같은 부류 · BOM ×12 · 비활성
  AMP41108-12           접미사 -12 · 실제 6 · 비활성
  구성품 0 인 콤보 1건    SKU 미기록 · Cin7 확인 대기
  CON00134              부모 없는 대체 UPC · 비활성 (BOM 이 없어 흡수되지 않았다)
  대체 UPC 중 바코드 없는 5건   AIA03530 · AIA03534 · DEX30160 · DMI00077 · SIS00510 — 줄이 안 생겼다
  ⚠️ 한 바코드를 활성 제품 둘 이상이 쓰는 23 (~~38~~ → 전체 42 · 09-14 오후 정정) — 무관 6 · 색상 변형 12 · 세트·낱개 5 — 카운터 ⑤ · §3-e
  ~~세트인데 공급처 줄이 붙은 3건   AS92082-6 · CRO71964-6 · EBI68634-6 — ④ 는 낱개에만 붙는다(§3-g) · 거르지 않고 넣는다(§3-g) · Cin7 에서 확인~~ [2026-09-14 저녁 닫음] Caleb 이 Cin7 에서 지웠다(콤보 JAL 넷도) · 우리 표 is_active=false 7줄 · §3-g 「닫힌 것 일곱」
  ⬜ 활성 1 + 비활성 13 — 지금은 문제가 아니지만 그 비활성 SKU 를 되살리면 활성끼리로 올라온다 · 카운터에 넣지 않고 여기 남긴다
  ```
  ✅ 재적재 방식은 정했다 — **넷이 한 규칙**(upsert + 안 들어온 cin7 행은 is_active=false · §3-f). ⬜ 읽는 쪽(스캔 화면 · 카운터 ⑤ · is_primary 카운터)이 `is_active` 를 걸어야 한다.
- ⬜ **④ 제품↔공급처 — 적재 뒤 남은 것 셋 (2026-09-14 저녁 · §3-g)**
  ```
  콤보 방향 칸            ⑤ 에서 만든다 — 원장이 「디스플레이 1개 입고 → 낱개 24개」를 실제로 쓸 때. ⚠️ 조건 = 부모(콤보)당 하나 · product_bom 줄에 두지 마라
                          후보: product 의 콤보 전용 nullable 칸 · BOM 머리 표. 초기값은 공급처 줄 유무(지금 사 오는 콤보 3). 그전까지는 카운터 ⑥의 변화가 신호
  is_default 끄고 켜기    §3-g 의 두 문장을 재적재마다 돌린다 — 적재 스크립트에 붙이거나 cron. 안 돌리면 내린 줄이 기본으로 남는다(실사고)
  AS91437-BLK 공급처      Type=Non Inventory 라 ④ 모집단(Type=Stock)에 없다 — 손으로 넣은 제품이니 공급처도 손으로(source='manual' · 화면 ⓐ)
  ```
- ✅ **화면 ⓐ 의 자리가 정해졌다**(2026-09-14 · §10) — `ims.asung.ca` · `asungtrading/asung-ims` · DB 는 Asung-IMS · `purchasing.html` 에 붙이지 않는다(§10-d). ⬜ 배포 전 **가입 닫기 확인**(§10-f ⓪) · IMS 로그인·사용자 표(§10-f).
  📌 위 목록은 Caleb 이 **Cin7 에서 전부 수정할 예정**이다 — 수정 뒤 재적재·갱신. 그때 정할 것 하나를 미리 적어 둔다:
  ```
  ⬜ Cin7 에서 SKU 를 고치면 우리 표는 어떻게 따라가나
     지금 적재는 sku 를 충돌 키로 쓴다(ipr_upsert_('product','sku',…)) → SKU 가 바뀌면 옛 행이 남고 새 행이 생긴다.
     ⭐ cin7_id(ProductID)는 SKU 가 바뀌어도 유지된다 → 충돌 키를 cin7_id 로 바꾸면 따라온다.
     ⚠️ 다만 sku 에 unique 가 걸려 있어(20260913230500 `sku text not null unique`), 옛 SKU 행이 남은 채 갱신하면 충돌할 수 있다.
        Cin7 에서 SKU 를 고치면 옛 SKU 는 사라지므로 실제로는 안 걸릴 것으로 보이나 미확인.
     ⇒ 재적재 전에 정한다.
     📌 [2026-09-14 오후] **현재 발동 조건 없음** — Caleb 확인: 공백 SKU·이름 틀린 SKU 는 적재 전에 다 고쳤고, 남은 Cin7 정리는 **바코드 중복뿐**이다.
        SKU 변경 계획이 없다. 지우지 않는다 — 언젠가 다시 온다.
     ⬜ 딸린 미확인: cin7_id(ProductID)가 SKU 변경에도 유지되는지 — 실측할 일이 없어졌을 뿐, 확인된 것이 아니다.
     ⭐ [2026-09-15 저녁] **결정으로 올렸다 — 충돌 키 cin7_id + SKU 승격 폴백(§11-k).** 발동 조건이 없어도 간다(그때 바꾸면 이미 두 행이다). 미확인 둘(cin7_id 유지 · sku unique 충돌)은 그대로 열려 있다.
  ```
- ~~⬜ 재주문점~~ [2026-09-13 닫음] `IncludeReorderLevels=true` 는 먹지만 **값이 전부 0** 이다(낱개 활성 8,668 에서 흩어 뽑은 40/40 · 토론토 줄만) — 안 쓰고 있다.
  `purchasing.html` 이 자체 수요 예측을 하므로 당연하다. 「봤고 비어 있어서 뺀다」.
- ~~⬜ **별도 작업 — Type=Service 53 · Non Inventory 4** 를 담을 자리. ③ 제품 표에서 빼는 것은 맞지만 ⑤ PO 비용 라인(운임·프렙·드롭십)이
  참조할 대상이다. ⑤ 전에 정한다(§3-d) / [2026-09-15] ⑤ 표 설계 때 함께 정한다 — §11-f 비용 문서가 이 자리를 쓴다.~~
  → [2026-09-16 닫힘] **필요 없어졌다** — 비용 문서 `po_charge` 는 줄 없는 문서이고 제품을 참조하지 않는다(`kind` CHECK freight·duty·brokerage·other + `description` · §13). Service 를 product 에 넣는 것은 ③ 의 범위 판단을 뒤집는 일이라 하지 않았다.
- ⬜ **제품의 기본 자리(bin)** — ⑤ 리시빙·풋어웨이에서 만든다. 발동 조건은 날짜가 아니라 사건. Cin7 Bin 슬롯 1·2 는 실제 자리이나 미사용(Caleb) — 담지 않는다. [2026-09-15] ⑤ 입고는 풋어웨이까지 한다(§11-i) — 그 자리가 여기다.
- ⬜ 공급처당 기본 통화는 하나(Caleb 확정) — 새 통화로 결제하면 공급처 계정을 새로 연다. ~~아직 발동 없음(이름 정규화 묶음 0).~~
  [2026-09-11 정정] **이미 발동된 실물 둘** — `East West Connect Inc.`/`East West Connect Inc._USD`(활성) · `Asung Trading`/`Asung Trading - USD`(비활성). 접미사 표기가 제각각이라 이름 정규화로는 안 잡힌다(§8-A-3).
- ⬜ 사용자 축은 `wms_staff` 확장 — 별건.

### ⬜ 다음 갈림길 — ② 공급처 (2026-09-11 오후)

- ⬜ **`ref_tax_rule` 표를 만들 것인가** (미결 · 다음 판단)
  - 만들자는 쪽 근거 셋: ⓐ 데이터가 이미 손에 있다 — CSV 31행에 세율·계정코드·활성여부·매입매출 구분이 다 들어 있다(`ref_currency` 2행을 손으로 넣은 것과 같은 상황) ⓑ ⚠️ **세율은 바뀐다 — 소급이 안 될 수 있다.** NS 15%→14% 가 이미 일어났다. Cin7 이 옛 규칙을 지우면 「오늘 15%였다」를 복원할 수 없다(원칙 1 의 3번) ⓒ 문자열로 두면 QBO 연동 때 226곳을 다시 이어야 한다.
  - 미루자는 쪽 근거: ② 가 한 칸 밀린다 · 마스터는 대체로 소급이 된다.
  - ⚠️ 어느 쪽이든 원문 칸 이름은 결제조건·계정과목과 같은 규칙으로 지어 둔다 — 나중에 FK 칸만 옆에 붙이면 구조가 흔들리지 않는다.
- ⬜ 발주처 161곳만 추린 TaxRule 분포 (§8-C 오염 문제)
- ⬜ HST PE 2016 · 38곳 동일값의 원인 (기본값 가설 기각됨)
- ⬜ Intervision Trading 중복 의심 2행

---

## 7-a. ② 공급처 설계 확정 (2026-09-11 오후)

**담는 범위** — 활성 226곳 전부. 비활성 462곳은 담지 않는다.
근거: 대부분이 경비 지출처이고 발주 모듈이 참조할 대상이 아니다(§8-A-1). 경비 지급처는 QBO 연동의 영역.
⚠️ 「거래처가 아니다」와 「IMS 에 필요 없다」는 다르다 — 버리는 것이 아니라 여기 있을 것이 아니라고 경계를 긋는 것이다(원칙 2).

**⭐ `is_purchasable` — Cin7 에 없는 우리 칸** (nullable boolean)
- true 161 · false 56 · null 9 (= 아직 판정 안 됨 · Caleb 전수 판정 §8-B).
- ⚠️ `is_active` 와 뜻이 다르다 — 활성이면서 발주 대상이 아닌 곳이 56곳이다.
- ⚠️ null 을 false 로 밀지 마라 — 「경비처로 판정했다」와 「아직 안 정했다」가 구별되지 않는다(「모르면 비워둔다」). null 개수가 정리해야 할 목록의 카운터가 된다.
- ⚠️ Cin7 재동기화가 이 칸을 덮어쓰면 안 된다 — Cin7 에 대응 개념이 없다. `source` 칸이 그 근거.

**참조 방식 — FK 로 잇는다**
```
결제조건  FK(ref_payment_term) nullable + Cin7 원문 문자열 칸
계정과목  FK(ref_account · code 로 매칭) nullable + Cin7 원문 문자열 칸
통화      FK(ref_currency) 하나 — CAD·USD 둘뿐이고 우리가 만든 표라 흔들리지 않는다
세금규칙  원문 문자열 (⬜ ref_tax_rule 표를 만들지 미결 — §7 다음 갈림길)
```
- ⭐ 원문 칸을 함께 두는 이유: 적재가 도중에 멈추지 않게 한다. 못 이은 것은 FK 가 null 이고 그 개수가 「아직 정리 안 된 곳」의 카운터가 된다(§6 「정확히 못 이으면 비워 두고 센다」).
- ⚠️ 계정과목은 실측 226/226 이 Code 로 일치하지만 원문 칸을 둔다 — **226/226 은 오늘의 사실이지 규칙이 아니다**(`ref_bin` 이름이 창고 간 안 겹치는 것과 같은 성질).
- ⚠️ Cin7 화면에서 필수인 축이라도 우리 FK 에 NOT NULL 을 걸지 마라. NOT NULL 은 원문 칸에.

**`AdditionalAttribute1`(Supplier Type)·`AttributeSet` 은 담지 않는다** (2026-09-12 Caleb 확정).
구분의 정본은 `is_purchasable` 이고 이 값은 참고값이다(§8-B · 154곳 중 8곳이 판정과 어긋난다).
두 칸이 나란히 있으면 언젠가 짧은 쪽으로 필터를 짜게 되고, 활성 226 중 72곳이 빈값이라
`is_purchasable` 의 null 과 신호가 겹친다. 마스터는 소급이 되므로 필요해지면 다시 긁어온다.
⭐ 방침의 상위 근거는 `ims-principles.md` §4-d — 커스텀 속성 엔진을 만들지 않고 뜻이 있는 칸으로 승격한다.

**Default carrier 는 담지 않는다** (§8-D).

---

## 8. 실측 근거 (2026-09-11 GAS 프로브 3회 · 전량)

API 쪽 정본은 `cin7-api/references/ref-endpoints.md`(ref/ 계열) · `supplier.md` · `product-master.md`. 여기는 설계 판단에 쓰인 숫자.

### ref/ 계열 여섯

| 엔드포인트 | 배열 키 | Total | 필드 |
|---|---|---|---|
| `GET /ref/brand` | `BrandList` | 415 | `ID`(guid) · `Name` — 둘뿐 · 이름 중복 0 |
| `GET /ref/category` | `CategoryList` | 19 | `ID` · `Name` — 둘뿐 · 전부 서로 다름 |
| `GET /ref/unit` | `UnitList` | 44 | `ID` · `Name` — 둘뿐 · 39개가 숫자 이름 · 글자는 DP·EA·EA-ALT-UPC·Item·JAR |
| `GET /ref/paymentterm` | `PaymentTermList` | 34 | `ID`·`Name`·`Duration`·`Method`·`IsActive`·`IsDefault` |
| `GET /ref/account` | ⚠️ **`AccountsList`**(복수형) | 289 | 열둘 |
| `GET /ref/location` | `LocationList` | 2,678 | 열일곱 |

⚠️⚠️ **통화 목록 엔드포인트는 없다** — `ref/` 계열 17개 전수(`endpoint-index.md`). 환율은 문서마다 `CurrencyRate` 로만.

### ⭐⭐ Cin7 은 마스터를 이름 문자열로 참조한다

```
제품 30행     Brand·Category·UOM 이 ref/ 목록의 Name 과 일치 100% · GUID꼴 0건
공급처 226곳  PaymentTerm 이 ref/paymentterm 의 Name 과 226/226 일치
              AccountPayable 이 ref/account 의 Code 와 226/226 일치 (Name 일치 0)
```

### paymentterm 34

- `IsActive` true 17/34 · `IsDefault` = `C.B.S (Cash Before Shipment)` 하나 · `Method` 34개 전부 `number of days`.
- 활성 17 (Name(Duration)): 1% Warehouse Allowance + 2%10 Net30(10) · 1%30 Net31(30) · 2%10 Net30(10) · 2%19 Net30(19) ·
  2%30 Net31(30) · 2.1%13 Net30(13) · 50% COD & 50% N30(30) · C.B.S (Cash Before Shipment)(0) · C.O.D(0) · Due on receipt(0) ·
  Net 14(14) · Net 15(15) · Net 21(21) · Net 30(30) · Net 45(45) · Net 60(60) · Net 7(7)
- 공급처 226곳이 실제로 쓰는 14종: Due on receipt 92 · C.B.S 59 · Net 30 33 · Net30 21 · C.O.D 4 · Net 60 3 · 1%30 Net31 3 ·
  2%10 Net30 2 · Net45 2 · Net 45 2 · 2%19 Net30 2 · 2%30 Net31 1 · Net 15 1 · 1%20 Net30 1
- ⚠️ 띄어쓰기만 다른 같은 조건이 따로 있고 공급처가 양쪽에 나뉘어 있다 — `Net 30`(33)/`Net30`(21) · `Net 45`(2)/`Net45`(2).

### account 289

```
필드   Code · Name · Class · Type · Status · DisplayName · Description · ForPayments ·
       BankAccountId · BankAccountNumber · SystemAccount · SystemAccountCode
Class  EXPENSE 126 · ASSET 74 · LIABILITY 52 · REVENUE 26 · EQUITY 11   (다섯 · 전수)
Status ACTIVE 213 · ARCHIVED 76
Type   16종 — EXPENSE 109 · CURRLIAB 40 · BANK 20 · FIXED 19 · OTHERCURRENTASSET 16 · COSTOFGOODSSOLD 14 · CURRENT 13 ·
       INCOME 11 · EQUITY 11 · OTHERINCOME 7 · CREDITCARD 7 · OTHERASSET 6 · REVENUE 5 · LONGTERMLIABILITY 5 · DIRECTCOSTS 3 · SALES 3
ForPayments  true 23 · false 266
Code   ⭐ 중복 0 (289 전수) — 자연키로 쓸 수 있다
       ⚠️⚠️ 형식이 둘 — `_숫자_` 215개 / 밑줄 없는 순수 숫자 74개(2000·1200·6000·8100…)
SystemAccount  271/289 null (CREDITORS·DEBTORS… Cin7 내부 표시)
Description    내용 제각각 — 「Accrued Purchases (GRNI)」 설명 · 「1050-421」 번호 · 사람 이름 ⇒ note 로 흡수
```

⭐ 우리가 코드에 박아 쓰는 계정 여섯 — 실재 확인(전부 ACTIVE):
```
_59_          Inventory Asset             [ASSET]
_135_         Brokerage - COS             [EXPENSE]   ⚠️ 우리 문서의 "landed" 가 이것 — 실제 이름은 통관중개료
_136_         Freight - COS               [EXPENSE]
_95_          Purchase Non Stock - COS    [EXPENSE]
_1150040012_  Stock in Transit (GINR)     [ASSET]
_1150040007_  In Transit                  [ASSET]
```

### location 2,678

```
ParentID 없음(창고) 3  ·  있음(bin) 2,675   토론토 2,047 · 에드먼튼 628
창고 GUID   Asung Trading Inc.  f1ca3946-5a4e-4da7-b68a-ce7d3500f0be  (IsDefault=true · North York ON M9N 2V8 · 35 Suntract Road · PickZones Zone1,…,Zone5)
            Asung - Edmonton    623edcaa-5f18-4682-aae1-b9016d977c11  (Edmonton AB T5S 0N7 · 18418 105 NW Ave. · PickZones Zone1,…,Zone5)
            Production Facility 6160ca1b-c932-4b58-bf04-96fbb0bf5179  (IsShopFloor=true · Bins 0 · 주소 전부 null · 미사용)
필드 17     AddressCitySuburb · AddressCountry · AddressLine1 · AddressLine2 · AddressStateProvince · AddressZipPostCode · Bins ·
            FixedAssetsLocation · ID · IsCoMan · IsDefault · IsDeprecated · IsShopFloor · IsStaging · Name · ParentID · PickZones
⭐ 정정      하위 행(bin)의 Name = bin 이름. Bins[] 원소 {ID,Name,IsDeprecated,IsStaging} 와 2,675/2,675 일치 · 숫자만 0 · 20자 이상 0.
            ⇒ cin7-api 스킬의 「child-location Name 은 바코드류」는 틀렸다(2026-09-11 정정 · 원래 기록의 구간·기준 불명)
⚠️ PickZones 는 창고 행에만 문자열 하나 — bin 별 zone 0건
~~⚠️ bin 행의 주소 칸은 null 이 아니라 빈 문자열('')~~
            [2026-09-11 저녁 정정] ⚠️ "" 와 null 이 섞여 온다 — 같은 응답 안에서도 행마다 다르다(A0100PALLET01 "" · A010101 "" · A010102 null · A010103 null).
            ⇒ = '' 로만 거르면 null 행이 조용히 빠진다. 적재 시에는 빈 문자열을 null 로 통일한다(ImsRefLoad.gs 의 ims_blank_)
⚠️ IsDeprecated 인 bin 0건
```

### supplier ~~226 (전량 · `IncludeDeprecated` 미사용 — 비활성은 안 봤다)~~ → [2026-09-11 정정] 전량 688 · 활성 226 — 아래 A-1

아래 첫 블록은 **활성 226 기준**(오전 프로브)이다. 정정된 두 줄은 블록 안에 표시하고 새 실측은 그 뒤 A-1~A-3 에 있다.

```
Currency        USD 159 · CAD 67  ·  ~~⚠️ KRW 0곳~~ [2026-09-11 정정] 활성 226 안에 0 · 비활성에 1곳(A-2)
Status          Active 226
AccountPayable  _109_ 193 · _62_ 33
PaymentTerm     14종 (활성 17종과 불일치 — 비활성 3종을 24곳이 쓰고 있다)
TaxRule         Zero-rated 140 · HST PE 38 · HST ON 29 · HST NS 16 · GST 2 · Exempt 1
Discount        0 이 215곳
⭐ AdditionalAttribute1 만 쓴다 154/226 — 값 2종(Product Supplier 143 · Service Supplier 11)
   2~10번은 전부 0곳 · AttributeSet 은 226곳 전부 'Supplier Type'
⚠️ Addresses 최대 2 (있음 83 · 없음 143)  ·  Contacts 최대 4 (있음 196 · 없음 30)
   ⇒ 칸으로 흡수할 수 없다 — 별도 표가 필요하다(② 공급처가 표 셋이 되는 이유)
Address 키  Line1,Line2,City,State,Postcode,Country,Type,DefaultForType,ID
Contact 키  Name,Phone,MobilePhone,Fax,Email,Website,Default,Comment,IncludeInEmail,ID
⚠️ 이름 정규화 후 같은 이름 묶음 0개 — ~~통화 때문에 갈라진 공급처는 아직 없다~~ [2026-09-11 정정] 앞 문장만 맞다 · A-3
```

#### A-1. [2026-09-11 정정] 비활성을 봤다 — 전량 688 (GAS 프로브 `spProbeSupplierDeprecated` · 13:36 Toronto)

```
Total   IncludeDeprecated=false 226 · =true 688  ⇒ 비활성 전용 462
Status  Active 226 · Deprecated 462 (값 2종)
⭐ 이름 중복  688행 전수 0 — 원문 기준도, 정규화(소문자·앞뒤공백·연속공백1) 기준도 0
             ⇒ name 자연키를 쓸 수 있다. ref_account 와 달리 측정했다
비활성 462곳이 쓰는 참조 문자열 중 활성 집합에 없던 값
  PaymentTerm 0종 · AccountPayable 0종 · TaxRule 0종 · Currency 1종 = KRW(1)
비활성 462곳의 빈 값  Name·Currency·PaymentTerm·AccountPayable·TaxRule 전부 0건
Addresses 최대 2 · Contacts 최대 4 — 688행 전체에서도 동일(표 셋 구조 무변)
```
⭐ 비활성 462곳의 성격: `AdditionalAttribute1` 이 Service Supplier 457 · Product 4 · 빈값 1. 실물 이름이 407 ETR · Air Canada ·
Airbnb · Amazon · Apple Store · Adobe · ATCO Energy · 7-Eleven · 식당 다수 ⇒ **발주처가 아니라 경비 지출처다.** Cin7 은 경비
지급처를 담을 곳이 공급처 표뿐이라 여기에 쌓인다.

#### A-2. [2026-09-11 정정] KRW — ~~0곳~~ **비활성에 1곳 있다**

IPOS Systems (Deprecated · Service Supplier · Due on receipt · `_109_`).
⇒ 활성 226곳만 담는 이번 설계(§7-a)에서는 `ref_currency` 2행(CAD·USD) 판단이 그대로 선다.
⚠️ 다만 근거 문장은 「실측 KRW 0」이 아니라 **「담는 범위 안에 KRW 0」** 이다(§3 표 · §7 도 같이 정정).

#### A-3. [2026-09-11 정정] 통화 때문에 갈라진 공급처 — ~~아직 없다~~ **실물 둘**

```
Asung Trading (CAD)          / Asung Trading - USD (USD)          — 둘 다 비활성
East West Connect Inc. (CAD) / East West Connect Inc._USD (USD)   — 둘 다 활성
```
⚠️ 접미사 표기가 ` - USD` 와 `_USD` 로 제각각이라 **이름 정규화로는 안 잡힌다**(그래서 「묶음 0」은 맞았고 결론이 틀렸다).
「공급처당 기본 통화는 하나 · 새 통화면 계정을 새로 연다」(§7)가 실제로 발동된 실물이다.
📌 별건 의심: Intervision Trading / Intervision Trading (Supplier) — 통화·조건·계정이 모두 같은데 이름만 다르다. 중복 행일 가능성(미확인).

#### B. ⚠️⚠️ `AdditionalAttribute1`(Supplier Type)은 구분 기준이 아니다

**Cin7 의 Supplier Type 표시를 거르는 기준으로 쓰면 안 된다.**
```
활성 226곳   Product Supplier 143 · Service Supplier 11 · 빈값 72
비활성 462곳 Service Supplier 457 · Product 4 · 빈값 1
```
⇒ 비활성 쪽이 98.9% Service 로 깨끗한 것은 **비활성으로 내리는 정리 작업 때 같이 붙인 표시**이지 평상시 관리되는 값이 아니다.
활성 쪽은 72곳이 아예 비어 있다.

⭐ **Caleb 전수 판정**(2026-09-11 · 활성 226곳 · 시트 「공급처 판정 2026-09-11 13:43」): **O 발주처 161 · X 경비처 56 · ? 모름 9** → `is_purchasable`(§7-a).

⚠️ 속성이 붙은 154곳 중 **8곳이 판정과 어긋났다**:
```
Service Supplier 인데 O — Biochem Korea · Les Aliments Basmex Inc. · The Clorox Company
Product Supplier 인데 X — Walmart
Product Supplier 인데 ? — Intervision Trading · Intervision Trading (Supplier) · Locher Evers International · UNIT5LLC
```
⇒ 표에 담더라도 참고값이다. **구분의 정본은 Caleb 판정이다.**

⬜ ? 9곳: East West Connect Inc. · East West Connect Inc._USD · Intervision Trading · Intervision Trading (Supplier) ·
Locher Evers International · Polymos Inc. · Rosinella · UNIT5LLC · Urban Crave
(Locher Evers 는 통관·물류 — 발주서는 안 나가지만 운임·통관료가 원가에 얹히는 통로)

#### C. 세금 규칙 (Cin7 Settings › Taxation Rules 내보내기 CSV 31행 · 2026-09-11)

필드: `Description` · `Tax1`(INPUT/OUTPUT/NONE/GSTONIMPORTS/AVALARA) · `AccountCode` · `Inclusive` · `IsActive` ·
`EffectivePercentExclusive` · `EffectivePercentInclusive` · `EffectivePercent`

⭐ **이름 규칙: 세율이 바뀐 해를 이름에 붙인다. 연도가 붙은 쪽이 현행이다.** (2026-09-11 CRA·공개 자료로 확인 · Caleb 추정이 맞았다)
```
현행                              폐지된 옛 세율
HST PE 2016 (Purchase) 15%   ←→   HST PE (Purchase) 14%   (2016-10-01 인상)
HST NB 2016 (Purchase) 15%   ←→   HST NB (Purchase) 13%   (2016-07-01 인상)
HST NL 2016 (Purchase) 15%   ←→   HST NL (Purchase) 13%   (2016-07-01 인상)
HST NS 2025 (Purchase) 14%   ←→   HST NS (Purchase) 15%   (2025-04-01 인하 · Cin7 에서 IsActive=false)
HST ON (Purchase) 13%             연도 없음 — 2010 이후 변경 없음
```
⚠️ 활성 공급처 226곳의 TaxRule 분포: Zero-rated (Purchase) 140 · HST PE 2016 (Purchase) 38 · HST ON (Purchase) 29 ·
HST NS (Purchase) 16 · GST (Purchase) 2 · Exempt (Purchase) 1

⚠️⚠️ **HST NS (Purchase) — 폐지된 15% 이고 Cin7 에서도 비활성인데 활성 공급처 16곳이 쓴다.** 결제조건에서 비활성 3종을
24곳이 쓰는 것과 같은 모양이다. Cin7 은 마스터를 비활성으로 내릴 뿐 그것을 쓰던 거래처를 고쳐 주지 않는다.

⚠️ HST PE 2016 을 쓰는 38곳: 세 축(TaxRule · PaymentTerm=C.B.S · AccountPayable=`_109_`)이 완전히 동일하고 통화만 CAD 20 / USD 18 로
갈린다. Caleb 판정은 X 32 · O 4 · ? 2 로 대부분 경비처(식당·호텔·항공·SaaS 구독).
⬜ **원인 미상.** 「생성 시 기본값」 가설은 Caleb 이 Cin7 현재 설정을 확인해 **기각**했다. 과거 기본값 · 일괄 생성 등 대체 설명은 아직 없다.

⚠️ 이 분포는 경비처 56곳에 오염돼 있다 — 설계 근거로 쓰려면 발주처 161곳만 추려 다시 세야 한다(⬜ 미측정 · §7 다음 갈림길).

#### D. Cin7 공급처 화면 실측 (스크린샷 · 2026-09-11)

- 필수(빨간 별) 여섯: Name · Tax rule · Currency · Status · Payment term · Account payable
- 선택: Discount · Tax number · Comments · Attribute set · Default carrier
- ⚠️ **Default carrier 는 화면에만 있고 `GET /supplier` 응답에 없다** — 그리고 실무에서 쓰지 않는다(Caleb 확인 2026-09-11). ⇒ 담지 않는다.
  `ref_payment_term` 의 `Method` 를 안 만든 것과 같은 판단.
- 📌 Account payable 화면 표기는 `_109_: Accounts Payable (A/P) - USD`(DisplayName). API 는 `_109_` 만 준다. 우리는 Code 로 잇는다.
  DisplayName 은 담지 않아도 코드+이름으로 재구성된다.
- ⚠️ **주소가 없는 발주처가 있다**(Caleb 2026-09-11). 활성 226곳 중 주소 0건이 143곳.
  ⇒ 공급처 주소 표에 「최소 1건」류의 제약을 걸지 마라 · 본체 표로 주소를 끌어올리지 마라.
  ⚠️ 주소 유무는 발주처/경비처 판정의 근거로도 쓰지 않는다(상관이 보였으나 인과가 아니다).

#### E. [2026-09-11 저녁] 적재로 검증된 아침 판단들

⭐⭐ **`ref_account.name` 중복이 실제로 9개 있었다.** 아침에 「Name 중복을 측정하지 않았으므로
유니크를 걸지 않는다」고 물러선 판단이 옳았다. 걸었으면 289행 전체가 막혔다.

Automobile Expense · Cost of Goods Sold · Customer Credits · Insurance · Other Expense ·
Professional Fees · Retained Earnings · Stock in Transit (GINR) · Uncategorized Income

⇒ 「측정하지 않은 것을 제약으로 걸면 적재가 조용히 깨진다」(§4-①)의 실물 사례.

⭐ **`Duration` 함정이 실물로 찍혔다.** `1% Warehouse Allowance + 2%10 Net30` 의 Duration 이 **10**
(이름의 Net30 은 어디에도 담기지 않는다). ⇒ 담지 않기로 한 판단이 옳았다.
⚠️ 같은 칸에 **기일 · 할인 기한 · 0** 세 가지가 섞여 있다:
`Net 30`→30(기일) · `2%10 Net30`→10(할인 기한) · `C.O.D`·`Due on receipt`·`C.B.S`→0

⭐ **`IN_TRANSIT` 은 Cin7 `ref/location` 에 존재하지 않는다.** 창고는 3곳뿐
(Asung Trading Inc. · Asung - Edmonton · Production Facility).
원장의 합성 창고라는 판단이 실측으로 확인됐다.

⭐ **bin 이름의 창고 간 중복은 0.** 복합키 `(warehouse_id, name)` 판단은 유효하고,
0 은 **오늘의 사실이지 규칙이 아니다**(기존 문장 유지).

⭐ **`ref_payment_term` 활성/비활성이 정확히 17/17.** 목록을 보면 **활성은 띄어쓰기 있는 형태,
비활성은 붙은 형태**로 규칙적으로 갈린다:
`Net 30`(활성)/`Net30`(비활성) · `Net 45`/`Net45` · `C.B.S (…)`(활성)/`C.B.S. (…)`(비활성)
언젠가 정리하며 새로 만들고 옛것을 내린 흔적이다.
⚠️ 그런데 공급처 226곳 중 `Net30`(비활성) 21곳 · `Net45`(비활성) 2곳이 아직 옛 형태를 쓴다
— **정리가 절반만 됐다.**
📌 새 값: `2.1%13 Net30` — 소수점 할인율. `discount_percent` 가 numeric 인 것이 맞았다.

⭐ **세금 규칙의 계정** — `_54_` = **GST/HST Payable**(LIABILITY/CURRLIAB). 세금 규칙 27행이
전부 이 계정을 쓴다. 캐나다는 매입·매출분을 상계해 순액 신고하므로 한 계정에 모으는 것이 맞다.
⚠️ `_118_` = **Vacation Pay** — 세금과 무관한 계정인데 `Tax on Sales`·`Tax Exempt`·
`Sales Tax on Imports` 셋이 이것을 가리킨다. 우리가 쓰지 않는 Cin7 기본 규칙이라 실무 지장은 없으나,
나중에 「세금이 휴가수당 계정으로 간다」고 읽히지 않도록 기록해 둔다.
⇒ `ref_tax_rule` 의 `AccountCode` 는 `ref_account` 에 **FK 로 이을 수 있다**
(`_54_`·`_118_`·`_109_`·`_62_` 네 코드 모두 존재 확인).

⚠️ 빈 주소가 `""` 와 `null` **두 형태로 섞여 온다**(같은 응답 안에서도).
⇒ 적재 때 빈 문자열은 null 로 통일했다(값을 바꾸는 것이 아니라 같은 것을 같게 적는 것).

### product (Total 14,677 · 30행 표본)

⚠️⚠️ **[2026-09-13 전량 실측으로 정정됨 — 설계는 §3-d]** 아래 표본 30행 기록은 SKU 순 앞쪽 시스템 항목에 몰려 있었다. 지우지 않고 남긴다.
```
· Total 14,677 → 활성만. 전량(IncludeDeprecated=true)은 18,829 · 비활성 4,152
· CostingMethod FIFO 30/30 → 전량에는 Special - Serial Number 가 섞여 있다
· 「계정과목을 넷 참조한다」 → 전량 채움은 Inventory 5 · COGS 3 · Revenue 1,103 · Expense 870 곳뿐(착시) — 넷 다 nullable
· `_숫자_` 형식으로 거를 것 → 전량에서 19건뿐. 진짜 기준은 Type(Stock 18,772 · Service 53 · Non Inventory 4)
· ⭐ IncludeSuppliers 「미확인」 → 틀렸다. 아래 정정
```
⭐ **[2026-09-13 정정] `IncludeSuppliers` 는 「미확인」이 아니라 이미 돌고 있다.** `~/asung/gas-system-automation/Productmaster.js` 가 매일
`GET /product?IncludeSuppliers=true` 로 전량을 긁어 BQ `asung_product_master` 에 `supplier_name`·`supplier_sku`·`cost_price` 를 넣고 있고,
`Suppliers[]` 스키마(`ProductSupplierID`·`SupplierID`·`Cost`·`FixedCost`·`PurchaseCost`·`Currency`·`LastSupplied`…)는
`cin7-api/references/product-master.md` 에 2026-07-10 실측으로 확정돼 있다. ⇒ **④ 제품↔공급처의 출발점은 0 이 아니다.**
⚠️ 「없다」와 「안 봤다」를 가르라고 해 놓고 셋째 부류 **「이미 있는데 안 찾아봤다」**를 놓쳤다(§9).

```
배열 키 Products  ·  필드 83개
CostingMethod   30행 전부 FIFO  ·  UOM 빈값 0/30
⚠️⚠️ 제품이 아닌 항목이 섞여 있다 — SKU 가 [:[OrderTotalDiscount]:] · _1_ · _10_ · _10767_ 같은 것들(Type=Service 등).
   ⭐ Caleb 확인: `_숫자_` 형식은 우리 제품이 아니다. 목록이 SKU 순 정렬이라 앞쪽에 몰려 있다
⭐ 제품이 계정과목을 넷 참조한다 — InventoryAccount · COGSAccount · RevenueAccount · ExpenseAccount
📌 HSCode · CountryOfOrigin 칸이 있다
~~⬜ product?IncludeSuppliers=true 는 미확인 — 표본 5행이 전부 시스템 항목이라 Suppliers 0 이었다.
   실제 상품 SKU 로 다시 봐야 한다(「파라미터가 안 먹는다」와 「표본이 나쁘다」가 구별되지 않는다)~~
   [2026-09-13 정정] 위 머리말 — Productmaster.js 가 매일 쓰고 있다. 표본 5행이 시스템 항목이라 0 이었을 뿐이다
```

### productFamily 1,141 · product 전량 18,829 (2026-09-13) — ⬜ 실측 숫자 부록은 프로브 1·3·4 뒤에 여기 붙인다

설계와 미측정 목록은 §3-d. 1차 사료(`~/asung/prompts/ims-product-claude-code-prompt.md` §6 부록)의 숫자는 재긁기 뒤 검증해 옮긴다 —
Caleb 이 2026-09-13 에 SKU 여섯(`FSP60025 -12`·`FSP60027 -4`·`PNA01280 -4` 공백 · `CHI811573-12→CHI81157-12` 자리수 · `BIS74414-12→BSI74414-12` 글자순서 ·
`AS93146→AS93146FAM` · `WTA00264FAM` 뒤 공백)을 고쳐 다시 긁으면 숫자가 움직인다.
```
GET /productFamily   Limit 1000 먹는다(2페이지) · 배열 키 ProductFamilies(⚠️ List 접미사 없음) · Total 1,141 · 칸 44(Products[]·Attachments[] 포함)
                     ⚠️ IncludeDeprecated 는 Total 이 같아 판정 불가 — 변형 SKU 4,884 가 전부 제품 덤프에 있었으므로 「비활성 제품군 없음」쪽
GET /product         Limit 1000 먹는다(19페이지 · 1분 47초) · 칸 83(전 행 동일)
⚠️ Cin7 은 없는 경로에 404 가 아니라 200 + HTML 을 준다(채널 후보 경로 일곱 전부) — HTTP 코드로 엔드포인트 존재를 판정하지 마라(cin7-api 함정 12 계열)
```

**2026-09-13 2차 (`ProbeProductBom.gs` · `IncludeBOM=true` 전량 18,829)**
```
⚠️ Limit=500 이 실효 상한 — BOM 을 켜면 1000 이 안 온다 · 38페이지 · 2분 42초
BOM   구성품 1개 6,406 · 2개 이상 15 · 없음 12,408 · ComponentProductID 가 덤프에 없음 0
      숫자UOM · BOM Quantity · 접미사 셋 일치 6,340 · 어긋남 3(AIA00207-6 · ORS12208-6 · AMP41108-12) · 숫자UOM 인데 접미사 없음 0
      EA-ALT-UPC 61건의 BOM Quantity: 1 → 59 · 6 → 1 · 12 → 1
축 조합(Type=Stock 18,772)  세트/대체 6,406 · 관계 없음 4,161 · 구성품+세트의부모 3,297 · family 2,437 · family+구성품+세트의부모 2,405 ·
                            family+구성품 38 · 구성품 13 · 콤보 11 · family+콤보 4
IncludeReorderLevels=true  ⭐ 먹는다 — 낱개(UOM=EA) 활성 8,668 에서 216개마다 하나씩 40건: 40/40 이 1줄씩 · 빈 배열 0
      원소의 칸  LocationID · LocationName · MinimumBeforeReorder · ReorderQuantity · StockLocator · PickZones
      값  MinimumBeforeReorder 0 · ReorderQuantity 0 (전부 0) · ⚠️ 창고는 전부 토론토 — 에드먼튼 줄 없음
      ⭐ 딸려 나온 사실: StockLocator · PickZones 는 **창고별 값**이다 — 제품 본체의 그 두 칸은 대표값 하나를 보여주는 것
```

---

## 10. 화면과 인프라 (2026-09-14 오후 · ④ 적재 완료 직후 · 결정의 경위)

⚠️ 표도 코드도 아니고 **결정의 경위**다. 코드에 드러나지 않는 판단이라 적어 두지 않으면 다음에 「같은 도메인이 간단한데」로 되돌아간다.
⭐ 스킬은 이번에 고치지 않았다 — 화면 작업이 실제로 시작될 때 한 번에 반영한다.

### 10-a. 자리 — `ims.asung.ca` (2026-09-14 완료)

```
도메인   ims.asung.ca            GoDaddy DNS 에 CNAME ims → asungtrading.github.io
레포     asungtrading/asung-ims  ⚠️ 공개 · GitHub Pages(main · /root) · HTTPS 켜짐 · 소유자는 개인 계정 asungtrading(GitHub Pro · asung-wms 와 같다)
로컬     ~/asung/asung-ims
DB       Asung-IMS (fazgmyvzzhqybtvtktyg)
```
⭐ **왜 레포를 나눴나** — GitHub Pages 는 **레포 하나에 커스텀 도메인 하나**다. `asung-wms` 루트에 `CNAME`(`wms.asung.ca`)이 이미 있어
같은 레포로 두 도메인을 낼 수 없다.
⚠️ **`asung-wms` 는 가르지 않았다.** 마이그레이션 · `docs/design` · `.claude/skills` · WMS 화면은 그대로다. 새 레포는 **앞으로 만들 화면 파일만** 담는다 — 옮긴 것이 없다.
📌 레포 이름이 `asung-wms` 인데 IMS 설계가 그 안에 사는 어색함은 인정하고 **지금 고치지 않는다** — `supabase link`·`db push` 배선을 전부 다시 해야 하고
얻는 것은 이름뿐이다. 컷오버 때 함께 정리한다.

### 10-b. ⚠️⚠️ 왜 `wms.asung.ca` 에 올리지 않았나 — 기술이 아니라 사람 문제다

```
Caleb: 「wms.asung.ca 를 잘 쓰는 사람들이 헷갈릴 것 같다」
Caleb: 「비공개는 우리 동료들에게 아직은 공개하고 싶지 않다는 뜻이다」
```
⇒ 막으려는 대상은 **바깥이 아니라 동료들**이다. 그래서:
- ⚠️ 「메뉴에 안 올리면 안 보인다」는 **부족하다** — 안 보이는 것과 안 열리는 것은 다르다. URL 을 알면 누구나 연다. 히스토리·자동완성으로도 걸린다.
- ⭐ 자리를 아예 나누는 편이 확실하고, 어차피 가야 할 자리다.
- ⭐ 실질 방어는 **IMS 프로젝트에 계정이 있는 사람만 로그인된다**는 것 — 처음엔 Caleb 혼자. ⚠️⚠️ 이 방어는 **가입이 닫혀 있을 때만** 성립한다(10-f ⓪).

### 10-c. ⚠️ 레포는 공개다 — 그 대가와 선

비공개를 검토했으나 **공개로 둔다**. 근거 둘 — 둘 다 `asung-wms` 규칙 12 의 2026-08-19 실측(같은 계정 · public → private → public)에서 왔다:
```
⭐ private 은 프론트를 보호하지 못한다   레포가 private 이어도 발행된 사이트는 공개다(「This repository is private but the published site will be public」).
                                      사이트 자체를 비공개로 발행하는 Visibility 는 GitHub Enterprise 전용.
⚠️ 작업 비용                          2026-08-19 에 겪었다 — Claude 가 raw 로 레포를 읽지 못해 진단·프롬프트의 정밀도가 떨어졌다(「339~343행」이 「어딘가」가 된다).
```
⚠️ **[정정 경위]** 이 절의 초안은 「레포를 비공개로 하면 Pages 가 아예 안 나가고 ims.asung.ca 가 죽는다」로 적혀 있었다 — 오늘 실측한 적이 없다.
Visibility 설정에 붙은 Enterprise 배지를 「private 레포는 Pages 가 안 나간다」로 잘못 확장한 것이다. **추론을 실측처럼 적었다.** 규칙 12 의 실측(Pro · private 에서도 발행)이 맞다.
⇒ 공개로 둔다. 대신 선을 지킨다:
```
넣어도 되는 것   HTML · JS · anon(publishable) key   ⭐ 브라우저에 어차피 노출된다 · RLS 와 로그인이 지킨다
절대 안 되는 것  service_role · Cin7 키 · 비밀번호 · 사람 이름이 붙은 실데이터
                ⚠️ 테스트용으로 실제 SKU·공급처 이름을 하드코딩하면 지워도 히스토리에 남는다
```
⚠️ 공개의 실제 대가는 「뚫린다」가 아니라 **「구조가 읽힌다」**이다 — 표 이름·경로·판단이 드러난다. 언젠가 감춰야 할 때가 오면 Enterprise 체험이나 비공개 레포에서 배포되는 다른 배포처를 본다.

### 10-d. ⭐ `purchasing.html` — 건드리지 않는다

[2026-09-14 읽음 · `asungtrading/tools/purchasing.html` · 4,566줄]
```
읽기   BigQuery 직접 — 브라우저가 구글 OAuth 로 bigquery.readonly 토큰을 받아 친다
       제품·공급처는 Cin7_Master_Data.asung_product_master (supplier_name 이 있고 활성인 것)
쓰기   GAS 웹앱 브리지(PO_WEBAPP_URL) — DRAFT PO 생성 · Fixed Price 조회/수정
       ⭐ PUT /product-suppliers 로 Fixed Price 를 고치는 기능이 이미 돌고 있다(±50% 경고 · 변경 로그 · Podraft.gs pd_updateFixedPrice)
       → [2026-09-16] 전환 기간 동안 Fixed Price 는 **여기(purchasing.html · Cin7)에서만** 고친다 — IMS 는 읽기만(§11-d · Caleb). 컷오버 뒤에 이 💲 기능이 IMS 로 옮겨 온다
계산   절반 이상이 수요 예측 — Huber 회귀·계절성·안전재고·ABC·워킹데이·캐나다 공휴일
```
⚠️ **복사해서 고치지 않는다.** 원본과 사본이 갈리면 한쪽을 고칠 때마다 다른 쪽을 따라 고쳐야 한다.
⭐ **컷오버 때 통째로 옮길 대상**이다 — 계산 로직은 그대로 살고 바뀌는 것은 「어디서 읽느냐」뿐이다.
⇒ 지금 세우는 화면과 **겹치는 기능이 없다**. 저쪽은 발주 추천, 이쪽은 마스터 값을 채우는 자리. Fixed Price 조차 저쪽은 **Cin7 에** 쓰고 이쪽은 **IMS 에** 쓴다 — 대상이 다르다.
📌 ⑤ 가 `product_supplier.cin7_id` 로 `PUT /product-suppliers` 를 치려 할 때(§3-g 「⑤ PUT 의 필수 열쇠」) **그 일을 하는 GAS 브리지가 이미 있다** — `pd_updateFixedPrice`.
   두 번 만들지 말고 그 브리지를 부른다(±50% 경고·변경 로그·Default 옵션 규칙이 거기 산다 · `cin7-api/references/product-suppliers-write.md`).

### 10-e. ⭐ 로그인은 Supabase 프로젝트마다 따로다

```
한 화면이 두 프로젝트를 볼 수는 있다   createClient 를 둘 만들면 된다 (도메인과 무관)
⚠️⚠️ 그러나 세션은 공유되지 않는다     운영에서 받은 토큰을 Asung-IMS 에 내밀면 거부된다
                                      IMS 표는 로그인하면 전부 읽힌다(select 열림 · ~~auth_all~~ → 2026-09-17 쓰기만 ims_can_write · §5 권한 규약) — anon 으로는 못 읽는다
```
⇒ IMS 화면은 **`Asung-IMS` 에 로그인**해야 한다. 운영의 `wms_staff` 는 다른 프로젝트라 쓸 수 없다.

⚠️⚠️ **`Asung-IMS` 는 「테스트 DB」가 아니라 목적지다.**
Caleb: 「현재 운영중인 wms 는 cin7 을 바라본다. 특정 시점에 cin7 에서 우리 시스템으로 완전히 넘어오는 것이 목표다. 새로 만든 Asung-IMS 에 모든 기능이 다 들어와야 한다.」
⇒ 「화면을 어느 DB 에 붙일까」는 애초에 갈림길이 아니었다. `Asung-IMS` 다. ⚠️ 마스터 표를 운영으로 올리는 쪽은 **방향이 반대**다.
📌 정본 곳곳의 「테스트 DB(Asung-IMS)」와 CLAUDE.md §1 의 `[테스트 · Asung-IMS]` 라벨은 **그대로 둔다** — 「검증 환경」이라는 뜻이 아니라 **「운영 WMS 와 다른 프로젝트」를 가르는 안전 라벨**이다
(명령이 어느 프로젝트를 치는지). 뜻은 `ims-principles.md` §1-a 「Asung-IMS 는 내일의 운영이다. 버리는 놀이터가 아니다」가 정본.

### 10-f. IMS 로그인 — ⓪ ✅ · ② 표 확정 · 나머지 ⬜ (2026-09-15 갱신)

```
⓪ ✅ 가입 닫기      [Caleb 확인 2026-09-15 · Asung-IMS → Authentication → Sign In / Providers]
                      Allow new users to sign up     꺼짐   ⭐ 공개 레포의 anon key 로 아무나 가입할 수 없다
                      Allow anonymous sign-ins       꺼짐   ⭐ 로그인 없이 authenticated 토큰을 받을 수 없다
                      Allow manual linking           꺼짐
                      Confirm email                  켜짐   ⇒ Add user 로 만들 때 Auto Confirm User 를 켠다
                      Email provider                 Enabled (로그인 방식이라 켜져 있어야 맞다)
                      ~~⬜ 현재 설정 미확인 — 확인 전에는 화면을 배포하지 않는다~~ → 확인됐다. 「계정이 있는 사람만」이라는 방어(10-b)가 성립한다
⓪-b ✅ URL 설정      [실사고 → Caleb 고침 2026-09-15 · Asung-IMS → Authentication → URL Configuration]
                      Site URL        https://ims.asung.ca
                      Redirect URLs   https://ims.asung.ca/**
                      ⚠️⚠️ 새 Supabase 프로젝트는 이것이 **기본값(localhost:3000)** 이다 — 비밀번호 재설정 링크가 localhost:3000 으로 갔다(`error_code=otp_expired` 도 함께).
                      가입 닫기(⓪)는 어제 적었는데 이것은 빠져 있었다. ⚠️ 옛 재설정 링크는 한 번 쓰면 소모된다 — 설정을 고친 뒤 **새 메일**을 받아야 한다.
① Auth 계정          대시보드 → Authentication → Users → Add user (⭐ Auto Confirm User 켜기) → 만들어진 사용자의 **UID 를 복사**한다
② ✅ 사용자 표        `ims_staff` — 표 확정 · 마이그레이션 `20260915141105_ims_staff.sql` · 로컬 재생·RLS 실동작 통과 · **§10-h**
                      ~~⬜ WMS 것을 베낄지 IMS 답게 다시 설계할지 미정~~ → 베끼지 않았다(어긋나는 다섯 · §10-h) · ⚠️ 테스트 DB push 는 Caleb
②-b ⚠️ 첫 admin      정책이 「admin 만 insert」라 첫 행은 아무 authenticated 도 못 넣는다(마이그레이션은 행을 적재하지 않는다).
                      ⇒ ① 의 UID 로 **SQL Editor(postgres · RLS 우회)** 에서 자기 행을 넣는다 — 데이터라 「스키마는 마이그레이션만」 규칙 위반이 아니다.
                      ~~⭐ 다음 사람을 추가할 때도 같은 SQL 이다(그때는 admin 이 화면·PostgREST 로 넣어도 되지만 화면이 서기 전엔 이것).~~
                      → [2026-09-15] 다음 사람은 **화면으로 넣는다** — `staff.html` + `ims-staff-create` EF(**§10-i** · 파일만 만들었다 · 배포 ⬜ Caleb).
                      ⚠️ 이 SQL 은 **지우지 않는다** — 표가 빈 첫 admin 과 「Auth 계정만 있고 행이 없는 경우」(EF 가 409 로 여기를 가리킨다)는 여전히 이 길뿐이다.
③ URL·anon key       Settings → API
④ 화면               wms-auth.js 는 복사한다(가져다 쓰면 IMS 가 WMS 파일에 매달린다 · 어차피 URL·anon key 가 달라 그대로는 못 쓴다)
                      ⚠️ 복사한 뒤 staff 조회를 `.eq("email", user.email)` 이 아니라 **`.eq("auth_user_id", user.id)`** 로 바꾼다(§10-h 열쇠)
```
**②-b 의 SQL** — `<UID>` 는 ① 에서 복사한 값 · `email` 은 Auth 와 같은 표기로:
```sql
-- [Asung-IMS · SQL Editor · postgres] 첫 admin (그리고 다음 사람도 같은 모양 · role 만 바꾼다)
insert into public.ims_staff (auth_user_id, email, name, role, note)
values ('<UID>', 'caleb@asung.ca', 'Caleb Chang', 'admin', 'first admin · 2026-09-15 · inserted as postgres (RLS bypass) — see po-module §10-f ②-b')
returning id, auth_user_id, email, role, is_active;
-- 확인 (반드시 되읽는다 — 0행 삽입도 조용히 성공한다)
select email, role, is_active, auth_user_id from public.ims_staff order by created_at;
```

### 10-g. 📌 머신 구분

```
회사 머신  Windows 사용자 chang · WSL caleb · 머신명 ASUNG-CALEB
집 머신    Windows 사용자 yoonh · WSL caleb · 머신명 Jeannie
⚠️ Downloads 경로(/mnt/c/Users/<사용자>/Downloads)와 zip 만들기에서 매번 갈린다 — 먼저 확인할 것
```

### 10-h. 사용자 표 `ims_staff` — 표 · 열쇠 · RLS (2026-09-15 · 마이그레이션 `20260915141105` · 로컬 검증 통과 · ⭐ **2026-09-17 밤 확장 — 아래 「등급 넷 · 두 축 · 등급 순서」가 지금 판**)

📌 **자리** — 이 표는 PO 도메인 마스터(§3 계열 · Cin7 매핑)가 아니라 **로그인 인프라의 일부**라 §10 에 둔다. 감사로그·승인 권한이 생겨 커지면 **§11 로 독립**시킨다.
📌 ①Settings 의 「사용자 축은 `wms_staff` 확장(별건)」이 가리키던 자리 — 확장이 아니라 **새로 세웠다**(운영 `wms_staff` 는 다른 프로젝트 · §10-e).

**실무 (Caleb 2026-09-15)** — 매니저 등급이 발주를 짜고 승인까지 한다(한 사람이 둘 다) · 그 사람들이 IMS 를 메인으로 쓴다 · ⭐ 지금은 Caleb 혼자.
⚠️ **짜는 사람과 승인하는 사람을 지금 권한으로 가르지 않는다** — 없는 구분을 미리 칸으로 만들면 ③ 「종류 칸」 실수의 반복. 갈리면 그때 권한을 하나 더 만든다.

**표**
```
id            uuid pk
auth_user_id  uuid not null unique     ⭐ 열쇠 = auth.uid() (JWT sub) · auth.users(id) FK 없음
email         text not null unique     사람이 읽는 칸 — 로그인 매칭에 쓰지 않는다
name          text not null
role          text not null default 'manager'   ~~check in ('manager','admin')~~ → [09-17] check in ('worker','supervisor','manager','admin') · ims_staff_role_ck ⚠️ 나열 순서 ≠ 등급 순서
perms         jsonb not null default '[]'        [09-17] 두 축이 든다 — 모드 'wms'·'ims' · 화면 'purchasing'·'master'·'receiving'·'staff'(+ ':read')
warehouse_access uuid[] not null default '{}'   [09-17 · 20260917230000] ref_warehouse.id 배열 · ⭐ 빈 배열 = 전부 · FK 없음(배열)
is_active     boolean not null default true
note · created_at · updated_at(트리거 set_updated_at() 재사용)
```
공통 8칸에서 벗어나는 곳 — **의도된 것**: `cin7_id`·`source` 없음(Cin7 대응이 없다 · `ref_currency` 가 `cin7_id` 를 뺀 것과 같은 판단).
`wms_staff` 와 어긋나는 것(의도): `id` bigint → uuid · `email` nullable → NOT NULL UNIQUE · `active` → `is_active` · `perms` 기본 `["split","admin","staff"]` → `'[]'`(새 사람에게 admin 이 기본으로 붙지 않게) ·
~~`warehouse_access` 없음(마스터 편집에 창고 구분이 없다 · ⬜ ⑤ 가 창고별 발주를 다루면 그때).~~ → [2026-09-17 밤] **uuid[] 신설 · 빈 값 = 전부** — 채워야 열리는 모양이면 사람을 더할 때 빠뜨리고, 빠뜨리면 조용히 아무것도 안 보인다. WMS 의 text(toronto/edmonton/both) 대신 id — 문서가 창고를 id 로 든다(아래 「등급 넷」).
~~role 둘 — `manager`(일하는 사람 · 발주·마스터 편집) · `admin`(+ 사람 추가·비활성). WMS 의 `worker` 는 없다(창고 직원은 IMS 에 들어오지 않는다).~~
→ ⭐⭐ [2026-09-17 밤 · Caleb] **넷이다 — 리시빙을 IMS 로 옮기기로 해서 창고 직원이 들어온다**(WMS 는 2026-01-01 컷오버까지 그대로 · 「모든 유저는 ims.asung.ca 에서 통합 관리 · WMS 모드와 IMS 모드」). worker · manager · supervisor · admin — 아래 「등급 넷」.
~~perms 는 빈 배열로 시작 — 화면이 하나뿐이라 쪼갤 것이 없다. 늘면 `purchasing`·`master` 같은 값(WMS `requirePerm` 과 같은 쓰임).~~ → [2026-09-17 밤] **두 축이 선다** — 모드(wms·ims) · 화면(purchasing·master·receiving·staff · `:read` 변형 = 화면은 뜨고 저장이 막힌다). 기본값은 여전히 `[]`(role 기본이 채운다 · 아래).

**⭐ 열쇠는 `auth_user_id`(= `auth.uid()`) — 이메일이 아니다** (검토에서 바뀐 것 · 초안은 WMS 처럼 이메일)
```
auth.uid() = JWT sub          이메일이 바뀌어도 끊어지지 않는다
⚠️ 이메일 매칭의 함정          대소문자 — WMS 는 wms-auth.js:170 이 원문 .eq 를 하는 것이 불변식이 되어 EF 게이트(authgate)에 정규화를 못 넣었다(asung-wms 규칙 8 각주 ·
                              정규화하면 mixed-case 계정이 로그인은 되는데 게이트만 막히는 회귀). uid 에는 그 문제가 없다
auth.users(id) FK 없음         걸면 퇴사자의 auth 계정을 지울 때 막힌다(우리는 delete 를 닫아 두므로 영구히) · WMS 도 안 걸었다
비용                          Add user 뒤 UID 를 복사해 넣는 순서 하나 — 첫 admin 을 손으로 넣는 절차(§10-f ②-b)와 합쳐져 추가 부담 없음
```
[로컬 실측] `auth.uid()` 변형 — sub 일치 `UPDATE 1` · 불일치 `UPDATE 0`.

**⚠️⚠️ RLS — 다른 IMS 표와 다르다.** `auth_all` 이면 매니저가 자기 `role` 을 `admin` 으로 고친다. [2026-09-17 밤부터는 다른 표도 쓰기를 조인다 — §5 권한 규약 · 이 표만 「등급」이 더 걸린다]
```
select          authenticated 전부 (true)              자기가 누구인지 알아야 화면이 뜬다 · ⚠️ 조이면 재귀(아래) — 건드리지 않는다
insert·update   ~~ims_is_admin() 인 사람만~~ → [2026-09-17 밤 · 20260918020000] (select ims_can_write('staff')) AND (select ims_can_manage(role)) — insert 는 새 행의 role · update 는 using 에 옛 role · with check 에 새 role
                ⚠️ ims_is_admin() 은 남아 있으나 이제 어느 정책도 쓰지 않는다(⬜ 지울지 §13-f)
delete          정책 없음 + revoke delete, truncate     직원은 지우지 않고 is_active 로 물러난다(§5 · 나중에 PO created_by·감사로그가 이 행을 가리킨다 · WMS 는 admin 삭제를 열어 뒀지만 IMS 는 닫는다)
anon            revoke all
```
`ims_is_admin()` — `security definer` · `stable` · `set search_path = public, pg_temp` · `auth.uid()` 로 활성 admin 인지 · anon 실행 권한 회수 · authenticated 만.
⚠️ **하나뿐이다** — 정책과 EF 게이트가 같은 판정을 쓴다. 다시 만들지 마라(`set_updated_at()` 과 같은 원칙). [09-17] 판정 함수는 아홉으로 늘었지만 원칙은 같다 — 화면·EF·정책이 **같은 함수**를 부른다(아래 「판정 함수」).
📌 [2026-09-15 · §10-i] EF 가 「같은 판정」을 쓰는 방법은 **caller 의 JWT 로 `POST /rest/v1/rpc/ims_is_admin`** 이다. → [09-17] 지금은 `rpc/ims_can_write`(p_screen 'staff') + `rpc/ims_can_manage`(p_target_role) 둘 — 방법(caller JWT)은 그대로.
   ⚠️ WMS 원본(`staff-create`)처럼 service_role 로 표를 직접 읽으면 `auth.uid()` 가 null 이라 이 함수를 못 쓰고,
   정책과 EF 가 **서로 다른 판정 코드**를 갖게 된다 — 어제 함수를 만든 근거 하나가 무너진다. 그래서 rpc 로 갔다(검토에서 바뀐 것 · 초안은 원본 방식).

**⭐ 재귀 — 실측 (2026-09-15 로컬 · 스크래치 표 · 정책 모양 셋)**
```
① update 정책이 자기 표를 직접 읽는다 · select 정책은 true          재귀 없음 — manager 자기 role UPDATE 0 · admin UPDATE 1
⑤ select 정책이 자기 표를 읽는다(「활성 직원만 읽게」)              ERROR: infinite recursion detected in policy for relation
②⑥ 같은 조건을 security definer 함수로                              둘 다 정상 · manager 막힘 · admin 통과
```
Postgres 는 정책 안의 부질의에 **그 표의 select 정책을 다시 적용**한다. select 가 `true` 면 끝나고, select 자체가 표를 읽으면 무한이다.
⇒ **지금 모양은 안전하지만 나중에 select 를 조이면 조용히 안 뜬다**(에러가 아니라 화면이 그냥 안 뜨는 형태) — 그것이 함수로 가는 이유다. WMS 의 `wms_is_admin()`·`wms_can_manage_staff()` 와 같은 패턴.

**❌ 검토에서 기각된 안 — 「지금은 `auth_all` 로 두고 화면에서만 막고, 카운터·감사로그로 지킨다」.** 다음에 또 떠오를 안이라 남긴다.
anon key 가 공개 레포에 있으니(§10-c) **PostgREST 를 직접 치면 화면 게이트는 장식**이다. WMS 규칙 8 의 실사고(「EF 에 서버측 권한 검사가 없다」— 3중 게이트가 전부 클라이언트였다)가 정확히 그 모양이었고, RLS 가 유일한 서버측 게이트다. 지금 한 명이라 사고는 안 나지만 그래서 지금 정한다.

**⚠️ 첫 admin — 초안에서 통째로 빠져 있던 것.** 정책이 「admin 만 insert」면 첫 행을 아무도 못 넣는다. 절차와 SQL 은 §10-f ②-b.

**로컬 검증 (2026-09-15 · `db reset` 재생 통과 · 문장마다 별도 트랜잭션 · JWT 클레임을 `request.jwt.claims` 로 심어 authenticated 로 실행)**
```
칸 10 · 제약 4(pk · auth_user_id unique · email unique · role_ck) · 정책 3 · 함수 definer=true · search_path=public,pg_temp · anon 실행 false
postgres 로 첫 admin insert           admin
admin 이 manager 행 insert            INSERT 1
manager select                        2행 (전부 보인다)
manager 가 자기 role → admin          UPDATE 0            ⭐ 막힌다
manager 가 새 사람 insert             RLS 위반 에러
admin 이 manager role 수정            UPDATE 1 · updated_at 갱신
admin 이 delete                       permission denied   (닫혀 있다)
비활성 admin 이 수정                  UPDATE 0            (is_active 를 본다)
anon select                           permission denied
role='worker'                         role_ck 위반        → [09-17] 이제 통과한다(넷)
```

**⭐⭐ 2026-09-17 밤 — 등급 넷 · 두 축 · 판정 함수 · 등급 순서** (마이그레이션 `20260917230000`(231행) · `20260918020000`(152행) · `20260918023000`(25행) · 커밋 `5b4e4c7` · `7ba12b4` · `c034a6f` · 검토 이견은 각 파일 머리 주석)
```
등급 넷        worker(창고 · 기본 wms 방 · wms 방 화면 기본 쓰기) < manager(같은 일 · ⚠️ 창고가 걸린다 warehouse_access · 화면은 perms) < supervisor(almost everything · 창고 경계 없음 · 사람 관리 포함 · 아래 등급만) < admin(전부)
   ⚠️⚠️ role_ck 의 값 나열 순서(worker·supervisor·manager·admin)는 **등급 순서가 아니다** — 임의 나열. 순서를 아는 곳은 ims_role_rank() 하나(1·2·3·4 · 모르는 값 null)
   ⭐ 값은 WMS 와 같은 낱말(컷오버 때 wms_staff 를 옮기기 쉽게) · supervisor 만 IMS 신설 · 기본값 'manager'
두 축(perms)   모드 'wms'·'ims' — 방(헤더 모드 전환) · 화면 'purchasing'(po·invoices·charges·payments) · 'master'(settings·suppliers·products·families·supplier-products) · 'receiving' · 'staff' — 쓰기 · '<screen>:read' 읽기만
   ⭐ 값 목록은 ims_perm_catalog() 한 곳(CHECK 없음 — 화면이 늘 때 표를 안 고친다 · 모르는 값은 함수가 false) · 라벨 staff = 「Adding and editing people (below your own rank)」(20260918023000)
   ⭐ **더하기만 한다** — role 기본으로 열린 것을 perms 로 닫지 않는다(두 축이 서로 막으면 「왜 안 보이지」를 두 곳에서 찾게 된다). 닫는 길이 필요하면 그때 별도 값
   ⭐ 방은 화면 값에서도 열린다 — 'receiving' 만 준 worker 도 wms 방에 들어간다(모드 토큰을 따로 안 줘도)
role 기본      admin 전부 · supervisor 모드 둘·화면 전부(staff 포함 · 09-17 밤 1-b)·창고 전부 · manager 모드 둘·화면 perms·창고 warehouse_access · worker 모드 wms + perms·화면 wms 방(지금 receiving) + perms·창고 warehouse_access
   ⭐ **모르는 값은 admin 에게도 false** — 정책에 오타가 나면 열리는 쪽이 아니라 닫히는 쪽으로 틀려야 한다
warehouse_access  uuid[](ref_warehouse.id) · ⭐ 빈 = 전부 · admin·supervisor 는 비워 둔다 · FK 없음(배열 — 없는 id 는 그 창고만 조용히 안 열린다 · 닫히는 쪽) · WMS 매핑 toronto/edmonton → 해당 id · both → {}
   ⚠️ ims_can_warehouse(null) = false(admin·supervisor 만 true) — 창고 없는 문서(po.ship_to_warehouse_id nullable)는 정책이 따로 다룬다(② 차수)
판정 함수      ims_role_rank(text)→int · ims_can_manage(text)→bool · ims_can_enter(mode) · ims_can_view(screen) · ims_can_write(screen) · ims_can_warehouse(uuid) · ims_perm_catalog()→jsonb · ims_access()→jsonb · ims_require_write(screen, verb)→void(거부 문장) · (ims_is_admin 잔존 · 미사용)
   전부 security definer(ims_require_write·ims_perm_catalog·ims_role_rank 제외) · stable · search_path=public,pg_temp · anon 회수 · authenticated 만 · 비활성·행 없음 = false/null
   ⭐ **ims_access() 가 화면이 부르는 하나** — 로그인 뒤 한 번 · { role, name, modes[], screens{screen: 'write'|'read'|null}, warehouses: null(전부)|uuid[] } · 화면은 role·perms 를 다시 가르지 않는다(§10-j 3-l)
등급 순서·직원 관리 (20260918020000 · Caleb 1-a~c)
   직원 관리는 admin 전용이 아니다 — 'staff' 쓰기 권한(admin·supervisor 기본 · manager 는 perms)이 있으면 관리한다
   ⭐ **자기보다 아래만** 만들고 고친다 — 같은 등급도 안 된다(같은 등급을 늘리는 것은 위가 판단할 일) · admin 은 전부(다른 admin 포함) · worker 는 아래가 없어 아무도 못 만든다
   ⭐ **자기 행은 못 고친다(admin 만 예외)** — 자기는 자기보다 아래가 아니다. ⚠️ 대가: 자기 이름·메모도 못 고친다(0행 → Not saved). 비밀번호는 Auth 라 무관(Change Password 는 누구나) · ⬜ 자기 행의 이름·메모만 고치는 길은 §13-f
   ⭐⭐ 지시서의 「옛 행과 새 행을 비교해야 한다(트리거 또는 RPC)」는 **틀린 전제였다** — using 에 옛 등급, with check 에 새 등급을 각각 **엄격 비교**로 두면 두 행을 비교하지 않아도 막힌다(검토가 뒤집었다 · 화면 무접촉 · §5 규약 ③)
   EF ims-staff-create 도 같은 둘을 caller JWT 로 부른다(rpc/ims_can_write 'staff' → rpc/ims_can_manage role · 963fadd · 7ba12b4) · 거부 문장 「Not allowed — you need the 'staff' permission …」 / 「… only add people below your own role (<role> is not below yours)」
```

### 10-i. 계정 추가 경로 — `staff.html` + `ims-staff-create` EF (2026-09-15 · ✅ 배포 · ✅ 실측 — 계정 생성 성공 · Caleb)

⭐ 첫 쓰기 화면. §10-f ①·②-b 의 손 절차(Add user → UID 복사 → SQL insert)를 **화면 한 번**으로 대체한다 — WMS `staff-admin.html` + `staff-create` EF(2026-07-21)와 같은 모양.
```
화면  staff.html(asung-ims)   이름·이메일·역할 → 로그인 세션 JWT 를 붙여 EF 에 POST → 임시 비밀번호를 한 번만 보여 주고 복사
EF    ims-staff-create        ① caller JWT 로 ~~rpc/ims_is_admin (활성 admin 만~~ → [09-17 밤] rpc/ims_can_write('staff') + rpc/ims_can_manage(role) · role 넷 · 정책과 같은 판정 · §10-h)
                              ② service_role 로 Auth 계정 생성(auto-confirm) ③ ims_staff insert(⭐ auth_user_id 필수) ④ 실패 시 Auth 계정 롤백
```
⚠️⚠️ `service_role` 은 EF 안에만 있다 — asung-ims 는 공개 레포다(§10-c).

**⚠️⚠️ 레포가 둘로 갈린다 — 이 프로젝트에서 처음.** EF 는 `asung-wms` 에, 화면은 `asung-ims` 에.
「Supabase 것은 전부 asung-wms」의 근거 — `supabase link`·마이그레이션 이력 외에 **둘 더**(2026-09-15 검토):
```
① asung-ims 는 GitHub Pages 가 루트를 그대로 발행한다   EF 소스를 거기 두면 ims.asung.ca/supabase/functions/…/index.ts 로 열린다.
                                                        비밀은 없지만(키는 env) 서버 코드가 공개 사이트에 서빙되는 모양이 된다
② CLI 는 supabase/ 폴더 + config.toml 이 있어야 배포한다   asung-ims 에 두면 supabase 폴더가 둘 · link 도 둘. ims_staff 마이그레이션이 이미 asung-wms 에 있으니 표와 EF 는 같은 곳
```
**⚠️⚠️ 배포 함정 — 한 `config.toml` 에 두 프로젝트의 블록이 섞이는 첫 사례다.** `supabase functions deploy` 는 **이름을 빼면 폴더의 함수 전부**를 대상에 배포한다:
```
--project-ref 없이            운영(asung-WMS)에 IMS 함수가 올라간다 (link 가 운영에 고정 · CLAUDE.md)
이름 없이 --project-ref 만    Asung-IMS 에 WMS 함수 아홉이 올라간다
⇒ 반드시 둘 다:  supabase functions deploy ims-staff-create --project-ref fazgmyvzzhqybtvtktyg
```
접두어 `ims-` 가 어느 프로젝트 함수인지 가르는 유일한 표시다 — IMS 함수는 앞으로도 `ims-` 로 시작한다.

**`config.toml` 블록 · `verify_jwt`** — 블록을 넣었다(`verify_jwt = false`). 📌 **사실 정정(2026-09-15 확인)**: 원본 `staff-create` 는 블록이 **없다** —
기본값(true)으로 배포돼 있고 브라우저가 사용자 JWT 를 보내니 통과해 돌고 있다. 「원본도 false」는 확인 없이 적은 짐작이었다. 09-12 의 401(asung-inv-ledger SKILL.md 196행·1770행)은 JWT 없는 cron 호출의 일이라 이 EF 에는 그대로 적용되지 않는다.
그래도 넣는 이유 — 스킬 규칙(새 EF 는 블록 필수) · EF 가 스스로 검사하니 게이트웨이 검사는 중복 · [짐작] 게이트웨이 401 은 CORS 헤더 없이 돌아와 브라우저에서 원인이 안 보일 것.

**원본에서 바꾼 여섯** — ① `wms_staff`→`ims_staff` ② caller 확인 email 조회 → **rpc/ims_is_admin**(§10-h) ③ `active`→`is_active` ④ ~~role 둘 · `warehouse_access` 없음~~ → [09-17] role 넷 · warehouse_access 는 안 받는다(비움=전부 · 편집은 staff.html) · 기본 `manager` ⑤ ~~admin 만~~ → 'staff' 쓰기 권한자 · 만들 수 있는 등급은 자기보다 아래만(perms 는 [] 로 만든다) ⑥ insert 에 `auth_user_id`.
덧붙인 것 — 이메일 **소문자 저장 + `ilike` 중복 검사**(UNIQUE 가 대소문자를 가른다) · Auth 계정만 있고 행이 없으면 **연결하지 않고** 409 로 §10-f ②-b SQL 을 가리킨다(열쇠가 uid 라 WMS 의 「email 을 고쳐 연결」은 맞지 않다) · 롤백도 실패하면 `orphan_auth_user_id` 를 응답에 싼다.

**화면 규칙** — 영문 UI · 한국어 주석 · `suppliers.html` 틀(목록+상세). 페이지네이션 없음(직원 수십 명 · caps-ok).
```
admin 아니면      편집·추가 UI 를 감춘다(읽기 전용) — 진짜 방어는 RLS 와 EF
자기 행           role·is_active 를 못 바꾼다(스스로 잠긴다 · 마지막 admin 이 자기를 끄면 아무도 못 고친다) · name·note 는 된다
email·auth_user_id  보여만 준다 — 로그인의 열쇠
삭제              없다 — is_active=false (delete revoke · §10-h)
⭐ UPDATE 0        RLS 에 막힌 update 는 에러가 아니라 0행이다(§10-h 실측) — .update().select() 로 되읽어 0행이면 「Not saved」.
                  「0행 삽입도 조용히 성공한다」(§10-f)와 같은 교훈
```
⚠️ EF 는 로컬에서 못 돌린다(Auth admin API) — 원본과 나란히 코드 검토로 대신했다. ~~첫 실측은 배포 뒤 Caleb 이 사람 하나를 실제로 넣어 보는 것.~~
→ [실측 · Caleb 2026-09-15] ⭐ **계정 생성 성공.** 비밀번호 재설정도 작동 — 단, URL Configuration 이 기본값(localhost:3000)이라 먼저 고쳐야 했다(§10-f ⓪-b).
📌 프롬프트가 가리킨 `.claude/skills/asung-ops/SKILL.md` 의 401 내용은 실제로는 `asung-inv-ledger/SKILL.md` 에 있다 — 스킬 정리는 다음에 한 번에.

### 10-j. ⭐⭐ 화면 공통 규칙 — 다섯이 이렇게 만들어졌다 (2026-09-15 · 적어 두지 않으면 다음 화면이 제각각이 된다)

**실물 (asung-ims · ims.asung.ca · 2026-09-15)** — 읽기 넷 + **쓰기 둘**(staff · suppliers). 행 수는 [화면 실측 · Caleb].
```
index.html              로그인 확인 · 마스터 표 행 수 (배선 확인용)
settings.html           ref_ 여덟 3,481행 — 왼쪽에 표 목록, 오른쪽에 내용
suppliers.html          supplier 257 + 주소 · 연락처 · 할인 · 연결 제품 수 · ⭐ 쓰기 — is_purchasable 판정(2026-09-15 저녁 · 둘째 쓰기 화면 · 3-i)
products.html           product 18,714 — 검색 중심 · 세트는 캐럿 · 브랜드/카테고리 필터 · 상세: 공급처 · 바코드 · 구성품 · 이 제품의 세트 · Same family
families.html           product_family 1,141 — 옵션 축별 · 속한 제품
supplier-products.html  product_supplier 12,721(활성 · 전체 12,728 — SQL 실측 2026-09-15)을 공급처 쪽에서 · 단가 없는 줄 카운터
staff.html              ims_staff — ⭐ 첫 쓰기 화면 (§10-i)
메뉴(ims-auth.js items)  Settings · Suppliers · Products · Families · Supplier Products · Staff · Home
```
[SQL 실측 · Caleb 2026-09-15] 공급처 **전체 257** = true 161 · false 56 · null **40** / **활성 226** = true 161 · false 56 · null **9** / 활성·true·미단종 **138** — ⭐ 138 이 실제 매입처다. 발주 화면이 보게 될 크기.
⚠️⚠️ **40 과 9 는 다른 모집단이다(전체 / 활성).** 차이 31 은 ④ 적재가 데려온 비활성 공급처 31곳(§3-g 판단 · is_purchasable null) — ⭐ 판정 대상이 아니다(Caleb 2026-09-15 · §10-k). 화면 기본 상태(Active only 켜짐 · 드롭다운 Not set)가 보여 주는 수는 **9** 다.
⚠️ [정정 2026-09-15 오후] 오전 판은 「257 → Active only 226 → + Purchasable **217** → 138」이었다. 217 은 「226 − 판정 없음 31」로 **어림한 값을 실측처럼 적은 것** — 판정 없음이 40 이고 `is_purchasable=false` 인 곳도 있어 성립하지 않는다. 화면의 Purchasable 드롭다운(Yes)은 161 을 보인다.
Cygnus Beauty Supply 연결 236 · 그중 기본 122 · 단가 없음 0.

**3-a. 읽기**
```
⚠️⚠️ PostgREST 1,000행 캡 — 모든 목록을 .range() 로 나눠 읽고 count:'exact' 로 총계를 받는다. 예외를 두지 않는다.
     ⭐ 지금 캡을 넘는 표는 넷 — ref_bin 2,675 · product_family 1,141 · product 18,714 · product_supplier 12,721.
        ⚠️ [정정 2026-09-15] 초안은 「ref_bin 과 product 뿐」이었다 — §1 에 적어 둔 숫자를 스스로 안 봤다.
     「지금은 안 넘으니까」로 두면 나중에 늘었을 때 조용히 잘린다(이 프로젝트 사고 5건).
     ⚠️ 예외 하나 — staff.html 은 페이지네이션이 없고 검색도 클라이언트에서 한다(전량을 받는다 · 직원 수십 명). caps-ok 주석을 단다.
⚠️ 검색은 서버에서 한다(ilike / or). 받아 와서 거르면 첫 페이지 안에서만 찾는다.
⚠️ 조인된 칸(product.name 등)은 서버에서 못 거른다 — supplier-products.html 의 제품 검색은 받은 페이지 안에서만 걸린다. 알고 쓰는 한계다(코드 주석에 적혀 있다).
⭐ 목록이 **뷰**여도 .range() + count:'exact' · .ilike · .order 가 그대로 듣는다(po_list · 2026-09-16) — 그래서 목록은 뷰, 상세는 RPC(§13-d). 뷰는 with (security_invoker = true) 로 RLS 구멍을 막는다(선례 wms_order_pack_progress)
```

**3-b. ⭐ 누가 무엇을 보는가**
```
매니저   정돈된 목록만 본다 — 토글이 아예 안 보인다
admin    토글로 그 바깥을 꺼내 본다 (판정이 없는 것 · 잘못된 것을 정리하는 자리)
```
```
suppliers.html          매니저는 is_active·is_purchasable·is_discontinued 셋이 고정(138곳) · admin 만 #opts — 체크박스 둘(Active only · Hide discontinued) + ⭐ Purchasable **드롭다운 넷**(All · Yes · No · Not set · null 은 .is()) · 상세의 판정 드롭다운도 admin 만(3-i)
supplier-products.html  같다 (!isAdmin || !showAll 이면 정돈된 것만)
products.html           ⭐ 제품은 감추지 않는다(Caleb 2026-09-15) — 비활성·대체 UPC 도 찾을 일이 있다. Active only 토글은 매니저에게도 보인다.
                        단, 상세의 「공급처 show N inactive」 토글은 admin 만(3-c)
families.html           토글 없음 — 모두에게 전량
staff.html              매니저는 읽기 전용 — 편집·추가 UI 를 감춘다(§10-i)
```
⚠️⚠️ **이것은 화면에서 감추는 것이지 막는 것이 아니다.** anon key 가 공개 레포에 있으니(§10-c) PostgREST 를 직접 치면 다 보인다. 지금은 감추는 것으로 충분하다(공급처 목록은 비밀이 아니다).
⭐ 진짜 막을 것이 생기면 **RLS** 로 간다 — `ims_staff` 의 `ims_is_admin()`(§10-h)이 그 선례다. → [2026-09-17 밤] **표 28 전부 쓰기를 조였다**(select 열림 · 쓰기 ims_can_write · §5 권한 규약). 감추기(3-b)는 그대로 UX 이고 막는 것은 RLS 다.

**3-c. ⚠️ 읽는 쪽이 `is_active` 를 건다 (§3-f)**
⚠️⚠️ **[실사고 2026-09-15]** `AS92082-6`(세트) 상세에 공급처가 붙어 보였다. 데이터는 맞았다 — 어제 Cin7 에서 지우고 `is_active=false` 로 내린 줄인데 **화면이 그대로 띄웠다.**
`suppliers.html` 의 연결 제품 수는 걸었는데 `products.html` 에서 빠뜨렸다.
⇒ 내려간 줄은 기본으로 감추고, admin 만 `show N inactive` 토글로 꺼내 본다.
📌 §3-f 는 「안 들어온 줄을 is_active=false 로 내린다」이고, 그것이 보이지 않으려면 **읽는 쪽이 매번 걸어야 한다.** 표가 알아서 감춰 주지 않는다.

**3-d. ⭐ 상세 비우기 · 목록과 상세의 관계 (2026-09-15 오후 · 규칙이 바뀌었다)**
```
사람이 검색어를 바꾸거나 지운다 · 토글·드롭다운을 바꾼다   → 오른쪽(상세)을 비운다      화면마다 clearDetail()
← → 로 페이지를 넘긴다                                    → 그대로 둔다
⭐ 코드가 넣는 검색어(화면 안 SKU 이동 · ?id=/?sku= 진입)      → 비우지 않는다 — 그 제품을 열러 가는 길이다
```
⚠️⚠️ **「사람이 바꾼 검색어만 비운다」를 코드에 박아라.** 지금은 `imsQ` 가 `input` 이벤트만 듣고, 코드는 `q` 변수와 `.value` 를 직접 넣어서 **우연히** 맞는다. 검색칸에 값을 넣고 `dispatchEvent` 를 하거나 `imsQ` 가 값 변화를 감시하게 바꾸면 SKU 이동이 방금 연 상세를 지운다.
❌ **버린 규칙 — 「고른 것이 이 페이지에 없으면 비운다」(loadList 안에서).** 알파벳 앞쪽이면 남고 2페이지로 넘기면 보던 상세가 사라져서 **언제 비는지 알 수 없었다**(실물: `Ashton Adams` 는 남고 `Parfums de Coeur` 는 사라졌다).
📌 「비우지 말자」도 검토했으나 접었다 — 왼쪽의 파란 표시가 **화면 밖에 있으면 없는 것과 같다.** 100줄 목록에서 스크롤해야 보이는 자리면 무엇을 보고 있는지 알 수 없다(Caleb). 「커서 있는 곳으로 스크롤한다」도 접었다 — 검색을 지울 때마다 목록이 엉뚱한 데로 튄다.
⇒ `clearDetail()` 은 화면마다 둔다(문구가 다르다 · 공통에 두지 않았다). 검색·필터 핸들러에서 부른다.

**진입·이동할 때는 그 행이 목록에 들어오게 한다** — 이유가 바뀌었다. 옛 이유는 「loadList 가 지운다」였고 이제는 지우지 않는다. 새 이유는 **목록에 없으면 파란 표시가 없어 무엇을 보고 있는지 모른다**.
```
?id= · ?sku= 진입 · 화면 안 SKU 이동     그 제품의 SKU 를 검색칸에 넣는다 · 넘어온 것이 세트일 때만 Kind 를 푼다(낱개면 Singles 그대로 · 세트는 캐럿) → 목록 → 상세
```
⚠️ 상세 조회는 **경합한다** — `loadDetail()` 이 조회 여럿을 기다리는 사이 필터가 바뀌면 `clearDetail()` 이 비운 뒤 **늦게 도착한 조회가 다시 쓴다** ⇒ 요청마다 번호(`detailSeq`)를 붙여 최신이 아니면 쓰지 않는다. `clearDetail()` 도 번호를 올려 날아오던 것을 무효로 만든다.
```
✅ products.html · suppliers.html     clearDetail + detailSeq
⬜ families.html · supplier-products.html   clearDetail 만 — 상세 조회가 Promise.all 하나라 창이 좁지만 없지 않다
⬜ staff.html                          clearDetail 없음 — 검색이 클라이언트라 목록에서 사라져도 상세가 남는다(규칙과 어긋난다 · 다음 화면 작업 때)
—  settings.html                       규칙 대상 아님 — 왼쪽이 고정된 표 목록이고 검색은 오른콽 표 안에서 건다
```

**경위 — 오늘 이 규칙이 생기기까지 (실사고 넷 · 2026-09-15)**
```
① ?id= 진입      상세가 빈 채로 떴다 — loadDetail 을 loadList 보다 먼저 불렀고, loadList 의 「목록에 없으면 비운다」가 지웠다
② 화면 안 이동    구성품·부모·형제 SKU 를 눌러도 안 넘어갔다 — 검색어가 앞 제품 SKU 로 남아 새로 고른 것이 목록에 없었고 ①과 같은 장치가 지웠다
                 ⚠️ ①을 고치고 같은 모양(화면 안 이동)을 안 봤다 — 한 곳을 고치면 같은 모양을 다 본다
③ 세트 중복      낱개 SKU 로 검색하면 그 세트도 ilike 에 걸려 본체에 들어오는데 펼친 부모의 자식으로도 그려져 겹쳤다(BNAT57623 → BNAT57623-12) ⇒ 펼쳐서 이미 보인 것은 본체에서 건너뛴다
④ Kind 풀림      ?id= 로 들어올 때 Kind 를 무조건 풀어 낱개로 넘어와도 세트가 따라 나왔다 ⇒ 세트일 때만 푼다
```
📌 ①②의 뿌리였던 「목록에 없으면 비운다」를 버리자 규칙이 위 모양으로 정리됐다. 비동기 순서는 실제로 돌려 봐야 안다.
⚠️ **버린 규칙은 문서에서도 찾아 지운다** — 같은 문서에 옛 규칙과 새 규칙이 함께 있으면 다음 사람이 어느 쪽이 맞는지 모른다. [2026-09-15 저녁] CHECKLIST 의 suppliers 절뿐 아니라 **products 절에도** 「목록에서 빠지면 오른쪽도 비워진다」가 남아 있었다 — 한 곳을 고치면 같은 문장을 문서 전체에서 grep 한다.

**3-e. 불리언 색 (2026-09-15 오후 · 여섯 화면 전부 적용)**
⚠️ 색은 `is_active` 에만 쓴다. `is_staging`·`is_default`·`is_split`·`is_primary` 는 false 가 정상인데 빨갛게 칠하면 2,675행이 전부 경고처럼 보인다(2026-09-15 settings.html 에서 드러남).
⇒ 공통 `yn(v)` 는 색(is_active 용) · **`yn(v, false)` 는 회색**(그 밖의 불리언). ims-ui.js 에 있다(3-g).
```
✅ settings.html                                    is_active 만 on/off 색 (오전)
✅ suppliers.html · products.html · supplier-products.html   is_default · is_primary 를 yn(v, false) 로 (오후 · 공통 파일로 옮기며 고쳤다)
```
⚠️ [정정 경위] 오전 판은 「색은 is_active 에만 쓴다」를 다섯 화면 전부의 사실처럼 적었다가 코드를 보고 ⬜ 셋으로 고쳤고(코드를 안 보고 기억으로 적은 것), 오후에 셋을 실제로 고쳐 ✅ 가 됐다.
⚠️ [정정 2026-09-15 저녁] 규칙의 반대쪽도 있었다 — **suppliers.html 만** 목록의 `inactive` 태그가 회색이었다(커밋본부터 · 상세 칩과 products·staff 는 빨강). 저녁에 `tag off` 로 맞췼다. 「색은 is_active 에만」은 **is_active 는 칠하라는 쪽도 포함**한다 — 안 칠하면 비활성이 눈에 안 걸린다.

**3-f. 그 밖**
```
화면 글자는 영문   ⭐ IMS 앱은 모두 영문(Caleb 2026-09-15). 코드 주석은 한국어(정본이 한국어다)
표 이름은 숨긴다   화면 제목은 `ref_bin` 이 아니라 `Bin` — ⚠️ 표 이름 자체는 바꾸지 않았다(FK·적재 코드가 그 이름을 쓴다)
☰ Menu 위치       이름·역할 바로 옆 · 다른 버튼보다 앞 (WMS UI 규칙과 같다) · 항목은 ims-auth.js items 한곳
화면 사이 이동     products.html?id=… / ?sku=… · families.html?id=… · supplier-products.html 의 SKU → products.html 상세
저장 확인          ⚠️⚠️ PostgREST update 가 RLS 에 막히면 에러가 아니라 0행이다(§10-h 실측).
                  .update().eq().select() 로 되읽어 0행이면 「Not saved」를 띄운다(staff.html · §10-i) · ⭐ 쓰기 화면 공통 규칙은 **3-i**
시각               ⚠️⚠️ timestamptz(created_at·updated_at)는 imsTs() 로 토론토 시각으로 보인다(3-g). 문자열을 자르면 UTC 로 보인다(실사고).
                  ⚠️ date 칸(product_barcode.valid_from · product_supplier.last_supplied · product.cin7_modified_on)에는 쓰지 않는다 — 시간대가 없다
틀                settings.html(가장 짧다)이나 suppliers.html 을 본떠 만든다(헤더 · 왼쪽 목록 · 오른쪽 상세) — ⭐ 공통 파일 넷을 순서대로 부른다(3-g) + imsAuth.start
```
**3-g. ⭐⭐ 공통 파일 — `ims-ui.css` · `ims-ui.js` (2026-09-15 오후)**
오전에는 화면 다섯이 스타일과 도구를 각자 복사해 갖고 있었다. 오후에 공통으로 뺐다.
```
ims-ui.css   7,510 바이트   색 변수 · 헤더 · 배치 · 목록 패널 · 카드 · 표 · 칩 · 값 표시
ims-ui.js    6,744 바이트   esc · dim · yn · num · imsTs · imsPage · imsSaved · imsQ · imsParam · imsHeader
             ⚠️ 헬퍼 이름은 코드가 정본 — 지시서가 imsFmtTs 라 적었으나 실제는 imsTs (2026-09-15 · 이름은 그대로 둔다)
```
**⚠️⚠️ 새 화면은 반드시 우리 파일 넷을 이 순서로 부른다** (CDN 은 그 앞):
```html
<link rel="stylesheet" href="ims-ui.css">
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script src="ims-config.js"></script>
<script src="ims-ui.js"></script>
<script src="ims-auth.js"></script>
```
⚠️ `ims-ui.js` 가 빠지거나 뒤로 가면 **화면이 아예 안 뜬다**(`imsPage is not defined`). CSS 링크가 없으면 글자만 나온다.
⭐ 안 부르면 그 화면만 혼자 논다 — 나중에 공통을 고쳐도 따라오지 않는다.
```
✅ settings · suppliers · products · families · supplier-products · staff   여섯이 공통을 쓴다
⬜ index.html   공통을 안 부른다(supabase-js · ims-config · ims-auth 셋만 · 배선 확인용 3KB) — 옮길지는 정하지 않았다
```
**크기 (옮긴 직후 → 지금 · 2026-09-15 15:30)** — 지금 값이 큰 것은 오후 커밋(상세 비우기 · 경합 방지 · 시각)이 들어갔기 때문:
```
settings 12,179 → 8,104 → 8,104 · suppliers 15,147 → 10,222 → 10,899 → **18,151**(저녁 · is_purchasable 쓰기 · 3-i) · products 25,143 → 19,842 → 21,909
families 13,898 → 9,151 → 9,283 · supplier-products 13,759 → 8,598 → 8,942 · staff (처음부터 옮겨 만들지 않았다) → 17,810
```
**⚠️ 공통 파일을 고치면 여섯이 다 움직인다** ⇒ 고친 뒤 `asung-ims/CHECKLIST.md` 를 처음부터 훑는다(그 문서 §0-a). ⚠️ 다만 **함수를 더하기만 한 경우**는 그 화면만 보면 된다(`imsTs` 를 더할 때 그랬다).
**⚠️ 공통에 흔한 이름을 두면 화면의 것과 부딪친다** — [실사고] `staff.html` 을 옮길 때 `.note` 가 겹쳤다. 공통 `.note` 는 카드 아래 띠(패딩·윗선·배경)인데 그 화면에서는 폼 밑 작은 안내글이었다 ⇒ 화면 쪽을 `.hint` 로. 공통에 이름을 더할 때 흔한 낱말인지 본다.
**⚠️ 공통 `esc` 는 따옴표를 바꾸지 않는다** — [실사고] 옛 지역 `esc` 는 `"` 를 바꿨고 그 값을 `value="…"` 속성에 썼다. 이름에 `"` 가 들어오면 속성이 깨진다 ⇒ 입력칸 값은 속성이 아니라 **DOM 으로 넣는다**(`el.value = …`).
**`imsTs`** — timestamptz 를 `toLocaleString("sv-SE", { timeZone:"America/Toronto" })` 로 분까지. [실사고] staff.html 이 ISO 문자열을 잘라 UTC 로 보였다(19:16 → 토론토 15:16). ⭐ 헬퍼로 뺀 이유 — 마스터 표 전부가 공통 8칸으로 `created_at`·`updated_at` 을 갖는다. 쓰기 화면이 늘면 Updated 를 보여 줄 곳도 늘고, 「문자열을 자른다」는 화면마다 복사될 실수다. 📌 `updated_at` 은 UPDATE 때만 바뀐다 — 넣기만 하고 안 고친 행은 `created_at` 과 같다(정상).

**3-h. ⭐ 점검 목록 — `asung-ims/CHECKLIST.md` (2026-09-15)**
```
자리    asung-ims/CHECKLIST.md   ⚠️ 화면 옆에 둔다(고친 직후 보는 문서다)
        ⚠️ 공개 사이트에서 ims.asung.ca/CHECKLIST.md 로 열린다 — 비밀은 넣지 않는다
담은 것  화면마다 「열면 무엇이 보여야 하는가」를 숫자까지
        ⭐ 「목록이 뜬다」가 아니라 「8,771 이 뜬다」 — 캡에 잘리거나 필터가 어긋나면 숫자가 달라진다
        §0-a 공통 파일을 고쳤을 때 · §9 아직 확인 못 한 것
규칙    ⚠️⚠️ 화면을 새로 만들면 항목을 더한다. 안 더하면 낡은 목록이 되고 낡은 점검 목록은 「통과했다」는 거짓 안심만 준다
        ⇒ 화면을 만드는 지시서마다 「CHECKLIST 에 항목을 더해라」를 넣는다
        ⚠️ 숫자가 바뀌면(적재 · SQL 정정) 그 문서도 같은 날 고친다 — [실사고 2026-09-15] 「Purchasable 217」이 정본과 점검 목록 둘에 박혔다가 실측 161 로 정정
        ⭐ 숫자에는 **모집단**을 함께 적는다 — Active only 켜짐/꺼짐 · 전체/활성. 같은 필터라도 모집단이 다르면 수가 다르다(null 40 / 9 · 12,728 / 12,721)
        ⭐ **줄어들 숫자에는 날짜와 성격을 붙인다** — 「작업 시작 시점 9(2026-09-15) · 판정할수록 줄어든다」. 그대로 박으면 다음 확인 때 「틀렸다」가 된다
```
[2026-09-15 저녁] suppliers 절을 is_purchasable 쓰기에 맞춰 갱신 · 브라우저 확인 다섯 통과(Caleb).

**3-i. ⭐⭐ 쓰기 화면 공통 — 다음 쓰기 화면이 같은 자리에 서지 않게 (2026-09-15 저녁 · suppliers.html is_purchasable 검토에서)**
선례 둘 — staff.html(§10-i · 편집·추가) · suppliers.html(is_purchasable 판정 · 드롭다운 하나 · 고르면 바로 저장). 다음은 ref_payment_term · 기본 공급처 · ref_bin.zone(§10-k).
```
저장 확인        imsSaved() 로 되읽는다 — 0행이면 「Not saved」(3-f · §10-h 실측). ~~지금 마스터는 auth_all 이라 막힐 일이 없지만~~ → [09-17] 표 28 이 쓰기를 조여 **실제로 막히는 자리가 됐다**(§5 권한 규약) — 0행을 성공으로 보지 않는 것이 이제 실동작이다
⚠️ 되돌리기      저장이 실패했는데 입력칸이 고른 값에 머물면 **화면만 저장된 것처럼 보여** 「Not saved」가 무력해진다
                ⇒ 직전 값을 들고 있다가(dataset.prev) 실패하면 되돌린다
⚠️ 잠금          저장이 끝날 때까지 입력칸을 잠근다(disabled) — 여러 곳을 빠르게 훑는 자리에서 update 둘이 경합한다. DB 는 마지막 것, 화면은 늦게 돌아온 것을 보인다
⭐ seq 의 범위    detailSeq 는 **오른쪽 상세에 쓰는 것만** 막는다. 왼쪽 목록은 화면 공통이라 보호 대상이 아니다
                ⚠️ 목록 재읽기까지 seq 로 막으면 숫자가 한 번 안 줄고 다음 새로 고침에야 맞는다 — **재현되지 않는 증상**으로 남는다
저장 뒤 목록      다시 읽는다(성공했을 때만 — 실패면 목록이 안 바뀌었다). ⚠️ clearDetail() 은 부르지 않는다 — 사람이 필터를 바꾼 것이 아니다(3-d)
                ⭐ 그래서 되돌리는 길이 남는다 — Not set 으로 걸러 놓고 판정하면 그 행은 목록에서 빠지지만 상세는 열려 있어 잘못 눌렀으면 바로 되돌린다
세 상태 값        null 을 화면에서 만들 수 있게 둔다(체크박스 두 상태로 가지 마라)
                ⚠️ 「판정 없음 N곳」이 남은 일의 눈금인데 체크박스로 가면 첫 클릭에 그 눈금이 사라진다. null 필터는 .eq 가 아니라 .is(col, null)
누가 고치나       ~~지금은 화면에서 감춘다(admin 만) · RLS 는 걸지 않았다 — 마스터 열일곱이 전부 auth_all 인데 한 표만 예외를 내기에는 이르다.~~
                → [2026-09-17 밤] **규칙으로 갔다** — 마스터·관계 표는 ims_can_write('master') · 거래 표는 'purchasing'(§5 권한 규약 ①). 화면의 admin 토글(3-b)은 정돈용으로 남는다
읽는 값 vs 쓴 값  칩·시각은 **DB 가 돌려준 값**으로 갈아 끼운다(보낸 값이 아니라) — imsSaved 의 .select() 결과를 쓴다. updated_at 은 트리거가 찍는다
⭐ 동시 편집       [2026-09-18 · 1차 · `20260918133858` + ims-ui.js] **imsSaved(builder, seenAt, ref)** — seenAt(내가 읽었을 때의 updated_at)을 주면 .eq("updated_at", seenAt) 을 붙여 **낡은 값을 보고 고친 저장**만 0행이 된다 · 안 주면 예전과 같다
                ⭐ 0행이면 되읽어 셋으로 가른다 — 남이 지웠다(removed) / updated_at 이 다르다(conflict · **현재 값 + 마지막으로 고친 사람 이름**(updated_by → ims_staff) · [Caleb 09-17] 「누군가 이미 저장했고 그 값이 뭐다라고 보여 줄 수 있으면 · 이름까지」) / 권한
                ⚠️⚠️ **화면에는 아직 안 붙어 있다**(2026-09-18 · PO 화면들의 seenAt 을 되돌렸다 dc0da29) — 처방을 「거부하고 끝」에서 **WMS 모양으로 묻고 고르게**(Keep theirs / Use mine / Recount)로 바꿨기 때문 · §13-f 「동시 편집」
```
📌 위 「되돌리기 · seq 의 범위 · 잠금」 셋은 suppliers.html 초안이 놓쳤고 검토(Claude Code · 2026-09-15 저녁)에서 잡힌 실제 버그다 — 코드를 읽어야 보이는 종류라 여기 남긴다.
⭐ [2026-09-16 오후 · po.html 만들기·편집에서 · §13-e 실사고]
```
화면은 계산하지 않는다   RPC 가 준 값을 그린다(할인 체인 · 미지급 · 차이 — §13-d 「계산 규칙의 정본은 RPC」 · [2026-09-16 저녁] 문서 돈(미지급·크레딧 잔액)은 뷰 po_invoice_money·po_charge_money 가 정본 — §13-g)
막는 것은 화면이 하지 않는다  DB(RPC)가 거부한 메시지(error.message 「… nothing was saved」)를 **그대로** 띄운다 — 화면에서 감추는 것은 막는 것이 아니다
오류는 삼키지 않는다      쓸 자리(모달 · 상태줄)가 없으면 alert 로라도 반드시 보여 준다 — 자리가 없어 화면이 죽으면 RPC 가 뭐라 했는지 못 본다(실사고 ③)
선언은 조각보다 위에      화면 조각(버튼 줄 · 표)이 쓰는 값은 그 조각보다 **위에서** 선언한다 — const 를 아래 두면 ReferenceError 로 상세가 안 그려지고 「Loading…」이 영원히 남는다(실사고 ②)
저장 뒤 다시 읽되        **스크롤 자리를 지킨다**(50줄짜리를 표 안에서 바로 고친다 · Caleb)
```

**3-j. ⭐ 공통 CSS 「⑤ 문서 화면 공통」 (2026-09-17 · asung-ims af06c61)**
화면 셋(po · invoices · charges)의 `<style>` 에 복사돼 있던 **규칙 34** 를 ims-ui.css 맨 아래 한 구역으로 올렸다(`<style>` 밖은 한 글자도 안 건드림 · 스크립트로 대조).
```
⭐ 왜 그때인가    [Caleb] 「레이아웃과 디자인을 PO 에서 잡는다 — 상품등록·SO 에도 그대로 쓴다」 ⇒ 기준이 **한 곳**에 있어야 한다. 버튼 하나를 바꾸면 세 곳을 고쳐야 했고 넷째 화면(payments.html)이 오기 전이 가장 쌌다
올린 것          .pobtn(5) · .qin/.tin/.xbtn(4) · .pomodal/.pobox(6) · .frow(3) · #wide(5) · .wfilt(5) · .invbar/.invgrid/@media/.invsub(5) · [hidden](1 · 실사고 주석도 함께)
⚠️ 통일한 값 셋   .qin 84→**104** · .tin 150→**180**(charges 값 — 금액이 잘리는 것이 좁은 것보다 나쁘다) · 검색칸 280/340→**260/320**(invoices·charges 값 · po 만 혼자 넓었다) — 이름은 같은데 화면마다 달랐다. 설계가 아니라 그때그때 늘린 값이었다 ⇒ .qin.pin(104)은 뜻이 없어져 지웠다(class="qin pin" 의 pin 은 이제 아무 규칙도 안 건다)
⚠️ 올리지 못한 둘  **main** — ims-ui.css 의 main·main.stack 과 이름이 겹친다(3-g .note 선례 · 바른 길은 `<main class="stack">` · HTML 은 범위 밖 · §13-f) · **.pobox input,.pobox select** — 특이도(0,1,1)가 .qin(0,1,0)을 이겨 po 모달 안의 수량 칸 모양이 바뀐다 ⇒ 두 화면 로컬에 남겼다
검산             po 59 = 32 + 27 · invoices 37 = 2 + 35 · charges 45 = 11 + 34 · ims-ui.css 69 → 103 · 같은 선택자 두 번 없음 · 바이트 7,510 → 12,865
⭐ 규칙            다음 화면은 `<style>` 에 공통을 복사하지 않는다 — ims-ui.css 「⑤ 문서 화면 공통」을 쓴다
발견             invoices.html 은 .pick/.prow 를 쓰는데 정의가 없다(인라인 style) · charges 는 .prow 만 정의 · po 는 둘 다 — 같은 「PO 고르기」 상자가 세 모양(§13-f)
```
**3-k. ⭐ 구매 문서 탭 — 헤더 바로 아래 한 줄 (2026-09-17 · asung-ims 9dcee4d · db4841e)**
[Caleb] 「payments·charges·invoices 로 넘어가면 PO 로 돌아갈 방법이 다시 메뉴를 클릭하는 것뿐이라 불편하다. PO 와 관련된 메뉴를 한 곳에 모을 수 있을까 — 탭으로」
```
묶는 것          **구매 문서 넷** — Purchase Orders · Invoices · Charges · Payments ~~(입고가 서면 그때 더한다)~~ → ✅ [2026-09-18] **Receiving 이 다섯째** · 모드는 **ims**(PO 갈래의 사무 화면 · 3-l)
❌ 묶지 않는 것    Settings · Suppliers · Products · Families · Supplier Products · Staff · Home — [Caleb] 마스터는 어쩌다 한 번 열지만 이 넷은 하루에도 여러 번 오간다. 전부 묶으면 성격이 다른 아홉이 한 줄에 선다
자리             헤더 **바로 아래** 한 줄 · 모든 화면에서 같은 자리(넓은 목록 위가 아니다 — 상세를 볼 때 안 보이면 자리가 흔들린다) · 넷에 속하지 않는 화면에서는 그리지 않는다 · 현재 화면은 .cur + aria-current 로 눌리지 않는다 · 그냥 링크(SPA 아님)
⭐ 출처는 하나     ims-auth.js items 배열 — ~~넷째 칸 'purchase'~~ → [09-17 밤 · 3-l] **다섯 칸 [이름, 주소, 화면값, 모드, 탭에 서나]** · 메뉴와 탭이 같은 배열에서 나온다 · 화면을 더할 때 고칠 자리가 한 줄 · 권한은 access.screens[화면값] 이 null 이 아니면('read' 도 보인다)
현재 판정         location.pathname 의 마지막 조각(소문자) · 「/」로 끝나면 index.html · 쿼리·해시는 pathname 에 없다 · 메뉴의 .cur 와 같은 변수
sticky 아님      헤더(sticky · top:0)만 남고 탭은 함께 스크롤된다 — .list 의 top:70px 은 그대로 맞는다 · ⚠️ 탭 높이는 JS 가 재서 `--ims-tabs-h` 로 :root 에 적는다 — po.html 의 .list .rows max-height 가 `calc(100vh - 230px - var(--ims-tabs-h, 0px))` 로 빼 쓴다(탭 없는 화면은 0px · 화면 파일 · 대화 Claude)
모양             ims-ui.css 「구매 문서 탭」 구역(.ims-tabs · 접두어 ims- · 충돌 없음) · 마크업은 화면에 없다(공통 코드가 <header> 뒤에 끼운다 · <header> 가 없으면 조용히 아무것도 안 한다)
☰ Menu           그대로 둔다 — 탭은 메뉴를 대신하는 것이 아니라 자주 가는 길을 짧게 하는 것이다 · ⚠️ .ims-nav 의 CSS 는 아직 JS 안 <style> 에 있다 — ims-ui.css 로 옮길 후보(§13-f)
```

**3-l. ⭐⭐ 권한과 모드는 `ims_access()` 하나로 — 화면은 판정하지 않는다 (2026-09-17 밤 · asung-ims `9f8ed27` ims-auth.js · staff.html `ff36b20`·`6085092`·`29fd003`·`87e0118`)**
```
판정은 한 번        로그인 뒤 rpc ims_access() 한 번 → { role, name, modes[], screens{purchasing|master|receiving|staff: 'write'|'read'|null}, warehouses: null(전부)|uuid[] } · me.access 에 실린다(기존 칸 무접촉 — 화면들의 me.role==='admin' 은 깨지지 않는다)
                  ⚠️ 왜: role 이 넷이 됐는데 옛 코드(resolveIdentity)는 'manager' 만 알았다 ⇒ worker·supervisor 가 requirePerm 게이트를 통과했다. 화면이 role·perms 를 다시 가르면 DB 와 어긋난다(「판정은 한 곳」)
                  화면이 묻는 법  me.access.screens.purchasing === 'read'(읽기 전용) · imsAuth.canWrite('purchasing') · imsAuth.canView('master') · me.access.warehouses(null = 전부)
                  ⚠️ RPC 오류 = 로그인 막되 **signOut 하지 않는다**(와이파이 순단에 세션이 날아간다 · 새로고침으로 재시도) · null = 막고 signOut · 조용히 전부 열지 않는다
                  ⚠️ 왕복이 하나 는다(ims_staff select 뒤 rpc) — 느려지는지는 재지 않았다
옵션               requireScreen:'purchasing'(옛 이름 requirePerm 도 같은 뜻 · 값 어휘는 새 것) · requireManager(worker 만 막는다 — supervisor 통과) · ⚠️ 2026-09-17 현재 어느 화면도 둘을 쓰지 않는다(grep 0 · 전부 {changePw:true})
items 다섯 칸      [이름, 주소, 화면값(null=로그인만), 모드('ims'|'wms'|null=둘 다), 탭에 서나(true)] — 메뉴·탭이 이 하나에서 나온다 · 노출 = screens[화면값] 이 null 이 아니면
                  ⭐ 모드와 탭 플래그가 **둘 다** 필요하다 — 모드는 「어느 방」, 탭은 「자주 가는가」(구매 넷만 · 마스터는 어쩌다 열어 메뉴에만) — 다른 물음이다. 탭 그룹 하나로 대체하면 ims 아홉이 한 줄에 선다
                  ~~⬜ 리시빙이 서면 ["Receiving","receiving.html","receiving","wms",true] 한 줄 — 그 순간 WMS 모드가 탭 줄에 나타난다~~
                  → ✅ [2026-09-18 · `20260918165934` · ims-auth.js] **["Receiving","receiving.html","receiving","ims",true]** — [Caleb] 「지금 세우는 것은 IMS PO 옆에 인보이스·비용과 같이 있는 리시빙이다. 그러니 IMS 가 맞다」 · 카탈로그 receiving.room 도 wms → **ims**
                  ⚠️ 카탈로그 room 과 items 넷째 칸은 **같은 사실을 두 곳에 적는다** — 화면이 room 을 읽지 않아 어긋나도 깨지지 않지만 조용히 간다 ⇒ 함께 고친다
                  ⚠️ room 을 ims 로 옮기면 **worker 기본이 안 열린다**(ims_can_view/write 의 worker 기본은 room='wms' 화면) — perms 에 'receiving' 을 줘야 한다. 지금은 그것이 맞다 — 창고 사람 기본은 나중 WMS 창고 화면 몫 · 그 화면은 ["…","…","receiving","wms",true] 로 따로 선다(⚠️ 화면 값 하나에 방 하나 — 그때 값을 따로 둘지 정한다 · §13-f)
                  ⚠️ 부수효과: wms 방에 화면이 0 이라 탭 줄에 WMS 모드는 아무에게도 안 그려진다(설계대로 · vis.some) · 탭 다섯은 폰 폭(≈400px)에서 넘친다(짐작 · .ims-tabs 에 overflow-x 없음 · §13-f 그대로)
탭 줄 = 모드 + 탭   [Caleb] 탭 줄 왼쪽 끝에 모드(IMS · WMS) · 구분선 · 그 뒤 그 모드의 탭 — 한 줄(줄이 셋이 되면 화면이 밀린다 · 헤더 안 작게도 기각) · --ims-tabs-h 그대로(po.html 이 빼 쓴다)
                  ⚠️ 모드 부분은 **들어갈 수 있고 보이는 화면이 있는 모드가 둘 이상**일 때만 그린다 — 화면이 하나도 없는 모드는 안 그린다(WMS 는 리시빙 전까지 아무에게도 · admin 도) · 모드가 하나뿐인 사람(창고 직원)도 안 그린다
                  ⚠️ 모드를 누르면 그 모드의 **첫 보이는 화면**으로(마지막 화면 기억 없음 — 저장할 곳이 필요해진다 · WMS 규칙 5 와 같은 결) · 탭 줄이 죽어도 메뉴는 산다(try/catch)
staff.html        등급으로 폼을 그린다 — 편집 가능 = 'staff' 쓰기 + 자기 아님 + 상대가 자기보다 아래(RANKS 순서 · admin 은 전부) · 선택지와 설명에 **자기보다 위는 나오지 않는다** · ⭐ [Caleb] 「admin = everything 을 빼 달라 — admin 의 존재를 아예 모르게」
                  ⚠️ 읽기 전용 문구 셋으로 갈린다 — 권한 없음 「you need the 'staff' permission」 · 자기 행 「you cannot edit your own record. Ask someone above you」 · 상대가 위 「this person is at or above your own rank」
                  ⭐ perms 편집 UI 는 ims_perm_catalog() 를 읽어 그린다(값을 화면에 적지 않는다) · ⚠️ 진짜 게이트는 DB(ims_can_manage · §10-h) — 선택지에서 빼는 것은 UX 다
```

⬜ IMS 인프라(Supabase 프로젝트 준비 · 화면 규칙 · EF 배포)를 담는 **스킬을 따로 세울지** 정할 일 — 지금은 `asung-po` 스킬 §0·§4 에 한 줄씩 얹어 두었다(마스터·적재 스킬과 성격이 다르다는 것을 알고 얹었다 · 2026-09-15).

### 10-k. ⬜ 채워야 할 우리 칸 — 쓰기의 첫 대상 (2026-09-15 · 한곳에 모았다)

⚠️⚠️ [2026-09-15 저녁 · Caleb] **이 목록은 지금의 우선순위가 아니다** — 전부 표가 섰고 칸만 비어 있어 나중에 채워도 구조가 안 달라진다(§11-⓪).
   예외는 **제품 생성**(§11-k) — 값이 아니라 규칙이 먼저 필요하다. 아래는 그대로 유효한 할 일 목록이다.

전부 **Cin7 이 모르는 우리 칸**이라 IMS 에서 고쳐도 아무것도 안 깨진다(재적재 §3-f 가 manual·우리 칸을 건드리지 않는다) ⇒ 쓰기의 첫 대상이다. 수치는 [화면 실측 · Caleb 2026-09-15].
```
is_purchasable        화면 ✅ 2026-09-15 저녁(suppliers.html 상세 드롭다운 · §10-j 3-i) — 판정(값 채우기) ⬜
                      ⭐ 판정 없음(null)은 **모집단을 갈라 적는다** [SQL 실측 · Caleb 2026-09-15]:
                        전체 257 기준  40곳
                        활성 226 기준   9곳   ⭐ 화면 기본 상태(Active only 켜짐 · Not set)가 보여 주는 수 · 작업 시작 시점(판정할수록 줄어든다)
                        차이 31        ④ 적재가 데려온 비활성 공급처(§3-g 판단 · null 로 들어왔다) — ⭐ **판정 대상이 아니다**(Caleb 2026-09-15):
                                       Cin7 에서 비활성이면 「지금 여기서 안 산다」가 이미 말해져 있다. 다시 활성이 되면 활성 목록에 저절로 뜬다
                      ⇒ 실제 대상은 둘 — **활성인데 판정 없는 9곳** · **true 161곳 중 잘못 켜진 것**(실물: Airalo · Klook 같은 것이 매입처로 잡혀 있다)
                      📌 활성 9 는 이 문서에 이미 있던 수다 — §3-c 적재 후 실측(226 = 161·56·9) · §8 supplier 의 Caleb 전수 판정(O 161 · X 56 · ? 9)과 같은 수
                      ⚠️ [정정 경위] 오전 판 「31곳」은 비활성 31 을 판정 없음 전부로 어림한 것 → 오후에 실측 40 으로 정정 → 그런데 **40 이 전체 기준이라는 것을 안 적었고, 문서 안에 이미 있던 9 와 잇지 않았다.**
                         40 과 9 는 어느 쪽도 틀리지 않았다. **기준을 안 적은 것이 틀렸다.** 반복되는 실수 — 두 모집단을 섞어 센다 · 내 문서 안의 숫자를 내가 안 본다
기본 공급처            2건 — 활성 줄이 있는데 날짜가 없거나 동점이라 못 골랐다(§3-g)
선주문 공급처          26건 — Custom Reusable Bag 25 + AS01433 · source='manual' 줄로 미리 적을 자리(§3-g 승격 규칙)
AS91437-BLK           Type=Non Inventory 라 ④ 적재 모집단에서 빠졌다
supplier_discount     0행 — ~~표만 있고 채울 자리가 없다~~ → [2026-09-16 저녁] 채울 자리는 섰다(RPC po_discount_save · p_target supplier · §11-e·13-h) · ⬜ suppliers.html 에 편집 UI 는 아직 · 채우면 po_create 가 바로 복사한다
ref_payment_term      기일·할인기한·할인율·분할 34행 전부 비어 있다 — ⭐ Cin7 에서 긁지 않고 화면에서 채운다(Caleb) · 34행이라 손이 빠르다
ref_bin.zone          2,675행 전부 비어 있다 — ⚠️ 손으로 채울 크기가 아니다. 규칙으로 한 번에(§7 · bin 이름에서 뽑는다 · 197건 null)
ref_bin.is_staging    ⭐ 임시 보관용으로 정해진 자리가 실제로 있다(Caleb) — 값만 안 채워졌다
단가 없는 줄           1,227 — supplier-products.html 의 No price 카운터로 어디에 몰렸는지 보인다
```
순서: ~~`is_purchasable` 체크 하나부터 — 화면이 이미 있고 가장 작다(지금 하지 않는다)~~ → ✅ **화면(고칠 수단)은 2026-09-15 저녁에 섰다**(§10-j 3-i) · ⬜ **판정(값 채우기)은 남았다** — 활성 9곳 · Yes 161곳 중 잘못 켜진 것. 다음 화면 후보는 ref_payment_term(34행 · 손이 빠르다). ⚠️ ⑤ PO 본체는 단가 없는 줄 1,227 과 supplier_discount 0행이 남아 있으면 발주 금액이 안 맞는다.
📌 그 뒤(Caleb 2026-09-15 · 판단만): 제품 등록·이미지 등록은 결국 IMS 에서 한다(Cin7 이 이미지를 회계·재고에 쓰지 않으니 「IMS 가 정본이 되는 첫 값」 · ⚠️ Supabase Storage 첫 사용 — 누가 올리고 누가 보는지) ·
⚠️⚠️ Cin7 으로 내보내는 일은 없다 — 한 방향(Cin7 → IMS)뿐. 컷오버 전에 새 제품이 필요하면 **양쪽에서 각각 만든다** ⇒ IMS 에서 먼저 만든 제품(source='manual' · cin7_id 없음)에 나중에 Cin7 것이 따라오면 같은 SKU 가 두 행 — ④ 의 승격 규칙과 같은 장치가 `product` 에도 필요하다(열쇠는 sku · ⬜ 제품 생성 화면 때) ·
재고·판매가는 원장 이전 뒤(원장은 아직 운영에서 shadow) · ~~`ims_staff.perms` 는 아직 안 쓴다(전부 [] · 화면이 늘면 requirePerm)~~ → [09-17 밤] 두 축이 든다(§10-h) · staff.html 의 Access 편집기가 ims_perm_catalog() 로 그린다.

---

## 11. ⭐⭐ ⑤ PO 본체 — 설계 판단 (2026-09-15 저녁(집) 판단 · ~~⚠️ 판단만 · 표 정의는 다음 단계~~ → 2026-09-16 표 열하나 적용·실물 검증 ✅ — 표는 **§13**)

⚠️ 이 절은 **2026-09-15 대화에서 나온 판단의 기록**이다. ~~표(DDL)도 화면도 없다. 표는 이 절을 입력으로 다음 세션에서 세운다.~~ → [2026-09-16] 이 절을 입력으로 표 열하나가 섰다(`20260916144201` · `20260916153313`). 판단 문장은 그대로 두고 절마다 「→ 표(2026-09-16 · §13)」로 어떻게 됐는지 잇는다. 표 목록 · 실물 검증 · 거래 표 규약은 §13.
⚠️ 「짐작」이라 적은 것은 확인하지 않은 것이다. 나머지는 Caleb 실측·결정, 또는 이 레포의 파일에서 확인한 것이다.
   [검토 Claude 정정]·[검토 Claude 추가] 표시는 지시서(`~/asung/prompts/po-module-design-session.md`)와 다르게 적은 자리다 — 이유는 그 자리에 있다.

### 11-⓪. ⭐⭐ 큰 틀 — Caleb 이 다시 못 박은 것 (2026-09-15 저녁)

```
⭐ Asung-IMS 는 애초에 Cin7 과 무관한 시스템이다. 이 단계에서 Cin7 은 **데이터 소스일 뿐**이다.
   적재는 앞으로도 계속하지만, 작동 자체는 Cin7 없이 돌아야 한다(원칙 1).
⭐ 지금은 **엮는 시점**이다. 마스터를 하나씩 세우는 단계(①~④)는 끝났다.
   제품을 만들 수 있어야 하고 → 그 제품으로 PO 를 만들 수 있어야 하고 → 입고된 재고로 SO 가 나가야 한다. 그 고리가 닫혀야 시스템이다.
⭐ 남은 모듈: PO · 손님 · SO · 재고조정 · 브랜치 트랜스퍼 · 빈 트랜스퍼. 원장과 원가라는 바닥이 이미 섰으니 그 위에 얹는 일이다.
⚠️ 작은 작업에 매몰되면 해야 할 것이 미뤄진다. **지금 안 하면 나중에 고치기 어려운 것만** 먼저 한다.
```
⚠️⚠️ 그래서 **§10-k 「채워야 할 우리 칸」은 지금의 우선순위가 아니다.** `ref_payment_term` · `ref_bin.zone` · `is_staging` · `supplier_discount` 는 전부
**표가 이미 섰고 칸만 비어 있다** — 나중에 채워도 구조가 안 달라진다. 당연히 할 일이지만 지금은 아니다.
📌 예외는 **제품 생성**(11-k) — 값 채우기가 아니라 **IMS 가 처음으로 정본이 되는 자리**라 규칙이 먼저 필요하다.

**⭐⭐ 컷오버 상(像)이 선명해졌다 — §2 의 「리셋」이 이 뜻이었다**
```
연습 기간   IMS 에서 PO 를 만들고 · 받고 · SO 를 만들고 내보낸다. **전부 실제로 돌려 본다**(대조용이 아니다)
           ⚠️ 다만 **실물 업무는 지금 그대로** — 물건은 WMS 가 Cin7 발주를 보고 받는다. 창고는 아무것도 안 바뀐다.
           ⚠️⚠️ **IMS 리시빙은 테스트 리시빙이다.** 창고가 두 번 받지 않는다.
컷오버     그때까지 IMS 에 쌓인 **거래(트랜잭션)는 지운다. 마스터만 남긴다.**
           그리고 그 시점의 Cin7 재고를 통째로 가져와 다시 시작한다.
```
⇒ ⭐ **설계 함의 ①: 마스터와 거래가 명확히 갈려 있어야 하고, 거래를 지워도 마스터가 안 깨져야 한다.**
   ⚠️ 이것은 `source='cin7'/'manual'` 과는 **다른 축**이다. 표마다 「이 표는 컷오버 때 지워지는가」가 서야 한다 — 표 설계 때 표마다 적는다.
   → [2026-09-16 · §13] 열하나 전부 **거래 ⇒ 지운다**로 표마다 주석에 박았다. ⭐ 예외 하나 — PO 확정이 갱신하는 `product_supplier.cost`·`last_supplied`(Latest)는 마스터에 있으나 거래에서 나오는 값 · **컷오버 때 거래는 지우지만 Latest 는 남긴다**(11-d). ⚠️ [2026-09-20] 「PO 확정이 갱신하는」은 설계 문장이지 실물이 아니다 — 갱신 함수는 없고(11-d 정정) 출처는 확정 인보이스로 바뀌었다(11-g).
⇒ ⭐ 설계 함의 ②: Cin7 발주·인보이스를 IMS 로 적재할 필요가 없다 — 숫자를 맞춰 볼 대상이 아니다. **적재는 마스터만.**
   📌 [Caleb 확인 2026-09-15 저녁] 「Cin7 으로 내보내는 일은 없다」는 **거래(발주·입고)를 두고 한 말**이다. Fixed Price 는 거래가 아니라 마스터이고,
      Cin7 이 아직 정본인 값이다 — 층이 다르다. §3-g 「⑤ PUT 의 필수 열쇠」·§10-d 의 `PUT /product-suppliers` 는 purchasing.html 의
      Fixed Price 인라인 조회/수정(791~848행 · 상품명 옆 💲 → 불러오기 → 고쳐서 Enter → 확인 후 Cin7 에 저장)을 IMS 로 옮길 때를 말한 것이라 부딪치지 않는다.
      ~~⚠️ 단 전환 기간에만 있는 예외다 — 컷오버 뒤에는 IMS 가 정본이 되어 필요 없어진다.~~ → [2026-09-16 오후 · Caleb] **전환 기간엔 IMS 가 Fixed Price 를 고치지 않는다**(「우리가 개별로 가격을 수정하면 되니까」 · §11-d). 그러니 IMS 가 PUT 을 칠 일이 없고 두 곳이 갈라지지 않는다. 💲 기능은 컷오버 뒤에 옮겨 온다.
⇒ 📌 설계 함의 ③ [검토 Claude 추가]: `ims-principles.md` §4-b 「과거 Cin7 문서와 새 우리 문서를 한 원장에 담는 문제(PO/SO 의 첫 관문)」가 이 상으로 대부분 풀린다 —
   과거 Cin7 문서는 원장에 행으로 들어오지 않고 **기초 잔고 하나**로 들어온다(옮기지 못한 이력은 §2 대로 참조용). ⬜ 상위 문서 갱신은 별건.
⚠️ [대화 Claude 의 잘못] 오늘 대화에서 「IMS 가 Cin7 에 밀어 넣어야 한다」·「IMS 리시버가 창고 화면이 된다」로 두 번 끌고 갔다. 둘 다 틀렸다 —
   **Cin7 을 축에 놓고 생각한 것**이다. §2 의 [실사고](이중 기록 제안)와 같은 뿌리. 이 경위를 남긴다.

### 11-a. 범위 — Purchase 하나다
```
⭐ Cin7 의 Simple / Advanced 구분을 따라가지 않는다. 우리는 **Purchase 하나**다(`ims-principles.md` §4-c · Caleb 2026-08-28 판단의 재확인).
   ⚠️ Cin7 이 둘로 가른 것은 Cin7 의 사정이다 — 부분입고를 한 문서 안에서 처리하려다 생긴 구조다.
   우리는 문서를 가르는 쪽을 택했다(11-c) ⇒ 가를 이유가 없다.
```

### 11-b. 생성과 확정
```
생성      ⭐ 주된 길은 purchasing.html 의 수요 계산이다 — 오더를 준비하고 authorize 하면 PO 가 자동 생성된다.
          (지금은 그 결과를 Cin7 에 넣고 있다 — Caleb: CSV 임포트 · ⚠️ §10-d 는 GAS 브리지의 DRAFT PO 생성을 적고 있다. 둘 다 있는지는 짐작 · 아래 이견)
          사람이 빈 화면에서 직접 만드는 길도 있어야 한다
확정      ⭐ **결재가 아니다.** 만드는 사람과 누르는 사람이 같다(Caleb 실측 — 「보통은 주문하는 같은 사람이 누른다」).
          ~~⇒ 확정은 「이제 고치지 않겠다」는 문서 잠금이다.~~ 승인자 칸·대기열을 만들지 마라(이건 그대로).
          ⭐⭐ [2026-09-16 오후 정정 · Caleb 실측] **틀렸다 — 확정은 잠금이 아니다.** 확정 뒤 수정은 **빈번하다**: 수량을 추가하고, 오더를 보내고 공급사와 통화하다 **세일 품목이 있다면 그 품목을 추가한다.**
          ⭐⭐ **Confirm 의 뜻: 「공급사에 보낼 수량과 라인이 정해졌다」는 확정.** 잠금이 아니다 · 메일을 보내는 것도 아니다(그 기능은 아직 없다 · 버튼 문구에서 「sent to supplier」를 뺐다 — 누르면 메일이 가는 줄 오해했다).
             이 시점부터 「올 물건」이 시스템에 존재하고 입고 대상이 된다. **확정 뒤에도 라인을 고치고 더한다.** 상태 이름은 `confirmed` 그대로 — 「확정됐다」가 정확히 그 뜻이다(open 은 다른 말이다 · Caleb).
          📌 [경위] 「만드는 사람과 누르는 사람이 같으니 결재가 아니다」까지는 맞았는데, 거기서 **잠금까지 끌어낸 것이 설계 대화의 비약**이었다. 실무를 물어 바로잡았다(2026-09-16 오후).
             ⚠️ 쓰기 RPC 파일(`20260916181719`) 머리 주석은 한 판 앞인 「확정 = 공급처에 보냈다」로 적혀 있다 — 그 뒤 대화에서 한 번 더 바뀌었다. 마이그레이션은 고치지 않는다(§13-d 에 표시).
          ~~📌 [검토 Claude 추가] 잠금은 사람의 편집을 막는 것이다. 11-c 의 자동 분할은 시스템 동작이라 잠금의 예외다 — 표 설계 때 이 예외를 명시한다.~~ → 잠금이 없어졌으니 예외도 없다. 분할은 시스템 동작이라는 것만 남는다(po.status 주석의 그 문장은 뜻이 약해졌을 뿐 틀리지 않는다).
          ⚠️ 막는 것은 **둘뿐이고 DB(RPC)가 막는다**(po_line_update · po_line_delete · §13-d):
             ① 입고가 붙은 라인의 수량을 **받은 것보다 적게** 줄이기 — 앞뒤가 안 맞는다   ② **closed · cancelled** 문서 고치기 — 입고가 끝났다
             ⭐ 왜 po_detail warnings 로 못 하나 — 수량을 줄여 생긴 음수 remaining 과 **초과 입고로 생긴 음수 remaining 이 같은 모양**이라 사후에는 구별이 안 된다(검토 Claude 지적 · 설계 대화가 못 본 자리). 화면이 막는 것은 막는 것이 아니다(anon key 공개). 트리거 없음 규약이라 남는 길이 RPC 다.
          ⚠️⚠️ 「100 시켜 100 청구받고 90 만 온 것」은 **라인 수정이 아니다.** 발주 100 · 입고 90 · 인보이스 100 · 크레딧 10개분 — 네 문서가 각자 사실을 말한다. **수량 수정을 크레딧으로 자동 전환하는 장치는 없다.** 크레딧은 공급처가 보내오는 문서다(11-g).
상태      작성 중 → 확정 → (입고 진행) → 종료 · 취소가 옆으로 붙는다
          ⚠️ 입고는 상태가 아니라 **진행도**에 가깝다(부분 입고가 있다)
          ~~⚠️ 입고가 끝나도 바로 안 닫는다 — 비용이 나중에 붙는다(11-f)~~
          → [2026-09-16 정정 · Caleb] ⭐⭐ **closed 의 뜻은 입고 종료다. 비용은 그 뒤에 붙는다.** 「비용까지 붙어야 닫는다」로 하면 ① 비용이 안 오는 발주(국내 발주 — 관세도 통관도 없다)는 영원히 안 닫히고 ② 비용은 나중에 또 붙을 수 있어 「이제 다 붙었다」를 시스템이 알 수 없다.
            ⇒ po_charge_alloc 은 closed 여부와 무관하게 붙는다(제약 없음) · 「닫혔는데 비용 안 붙음」은 큐가 아니라 **조회**로 본다
```
→ **표(2026-09-16 · §13)** `po.status` CHECK `draft · confirmed · closed · cancelled` 넷 — 입고 진행은 상태가 아니라 `po_receipt_line` 합. `confirmed_by/at · closed_at · cancelled_at · created_by(→ ims_staff.id)`.
→ **쓰기(2026-09-16 오후 · §13-d)** 나누는 기준(Caleb): **일이 여럿이면 RPC · 한 가지면 PostgREST**(+ imsSaved 되읽기 · §10-j 3-i). RPC 넷 — `po_create`(공급처 기본값 + supplier_discount 복사 · created_by 는 **auth.uid() → ims_staff.id 서버 유도** — 화면이 주면 공개 anon key 로 아무 id 나 줄 수 있다 ⇒ ①차 ⬜ 기본값 함수 닫힘) · `po_lines_paste`(11-d) · `po_line_update` · `po_line_delete`(위 「막는 둘」). 확정·메모·할인 줄은 PostgREST. ~~취소~~ → [2026-09-17] **취소는 `po_doc_cancel`**(아래 「취소·삭제」).
→ **취소·삭제(2026-09-17 · `20260917100000` 433행 · 커밋 5355033 · 검토 이견 1~14 · fix 로 둘 뒤집음)**
```
왜 지금        [Caleb 2026-09-17] 「테스트 오더를 계속 만들 텐데 하나씩 지우거나 취소를 해야 한다」 — 발주 초안을 지우는 길과 인보이스·크레딧을 취소·삭제하는 길이 화면에 없었다
RPC 둘         po_doc_cancel(p_target, p_id, p_cancel) · po_doc_delete(p_target, p_id) · p_target 'po' | 'invoice'(크레딧 포함 · doc_kind 는 행에서) → [150000] + 'charge' → [190000] + 'payment'(삭제만)
               ⭐ 취소를 PostgREST 한 칸에서 RPC 로 옮겼다 — 저장 전에 **다른 행**(입고 줄 · 결제 충당 · 붙은 크레딧)을 봐야 막을 수 있다.
               ⚠️ 그전에는 **입고가 붙은 발주도 취소되는 길이 열려 있었다**(검토가 찾았다 · po.html setStatus 가 status 만 바꿨다)
⭐⭐ 지운다/취소한다  **판정 축은 status 가 아니라 confirmed_at 이다 — 한 번이라도 확정된 문서는 지워지지 않는다.** 확정된 적 없는 것(draft · draft→cancelled)만 지운다
               ⚠️ 발주도 같다 — 처음 검토안은 「발주는 장부가 아니고 번호가 시퀀스라 cancelled 면 지운다」로 넓게 두었다. [Caleb 판정 2026-09-17 · 뒤집음]
                  근거: 「밖에서 아무것도 안 가리키는 확정 발주」는 물건도 인보이스도 아직 안 온 것 — 그것이 §11-c 「안 온다고 판명되면 취소한다」의 **전형**이다.
                  지워도 되는 것과 취소의 전형이 같은 모양이 되어 가장 남겨야 할 문서가 가장 잘 지워진다. 「시퀀스라 재사용 위험이 없다」는 이력을 지워도 된다는 뜻이 아니다
               [실물 2026-09-17 · Caleb SQL] PO-02005 · 02008 은 status='cancelled' 인데 confirmed_at is null — 확정을 안 거쳐 지워졌다(PO-02009 도)
               ⭐ 크레딧은 **종류로 삭제 금지**(§11-c 크레딧 번호 소절 — 채번이 행을 읽는다) · 취소는 draft 도 받는다(「받았지만 받아들이지 않은 인보이스」를 기록으로 · warnings cancelled_from_draft)
막는 것        발주 취소: closed · 입고 줄 있음 ⇒ 거부 / 인보이스·크레딧 줄이 가리킴 · 비용 배분 · 번호 낸 크레딧(credit_po_id) · 갈라진 자식은 **경고만**(attached{} 에 이름 — 「안 온다고 판명되면 취소한다」가 실무 · 순서를 강요하면 실물을 못 넣는다)
               인보이스·크레딧 취소: 결제 충당 ⇒ 거부(po_invoice_confirm Reopen 과 같은 문장 · 참조번호·금액을 이름으로 「WIRE-20260916-01 2010.54」) · 취소 안 된 크레딧이 붙은 인보이스 ⇒ 거부(크레딧의 돈이 허공에 뜬다 · 함께 취소하지 않는다 — 취소는 사람이 한다 §11-c) · 크레딧 취소는 credit_for 인보이스에 결제가 있으면 경고 + unpaid 전후
               삭제: 밖에서 가리키는 FK(전부 no action)가 어차피 막는다 — RPC 는 **이름을 붙여 읽을 문장으로**(po_line_delete 선례) · 딸려 가는 줄(CASCADE)은 수만 알린다(lines_deleted · discounts_deleted · allocs_deleted)
               세 문서의 거부 문장이 같은 모양 — 「<문서> <번호> was confirmed on <날짜> — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted」
⭐ 되돌리기      p_cancel=false · cancelled → **취소 직전 상태로**(confirmed_at 있으면 confirmed · 없으면 draft) — 취소는 confirmed_at/by 를 건드리지 않는다(po_list order_phase 가 그 값을 본다)
               필요한 이유: 취소된 인보이스도 유니크 (supplier, doc_kind, number) 를 붙들고 있어 되살릴 길이 없으면 같은 번호를 다시 못 넣는다 — **취소가 곧 삭제가 된다**(Caleb 확인)
               Reopen(po_invoice_confirm false)은 confirmed_at 을 지운다 — 그래서 그 뒤 삭제가 열린다(크레딧은 종류로 막혀 그 길도 닫혔다)
cancelled_by   po · po_invoice · po_charge 에 신설 — confirmed_by 는 있는데 누가 취소했나가 안 남았다 · auth.uid() → ims_staff.id 서버 유도 · 되돌리면 cancelled_at 과 함께 비운다
화면            po.html Cancel 을 RPC 로 · Delete/Restore(po · invoices · charges) · 버튼 노출: Delete = confirmed_at null(크레딧 없음) · Restore = cancelled 만 · 거부 문장은 그대로 띄운다
```
📌 Cin7 공급처 Additional attributes 의 `PO Progress` 칸(전 공급처 빈값 · §3-b 「담지 않는다」)은 「⑤ 에서 참고」로 적혀 있었다 ⇒ **참고할 것이 없었다.** 우리 상태는 위로 선다.
→ **머리 칸 편집(2026-09-19 · 화면 po.html · 대화 Claude)** — 발주만 그 길이 없었다(다른 문서 셋은 있었다).
```
여는 것 다섯   draft 까지   Order date · Required by · Ship to(활성 창고 드롭다운)
              언제나      **Exchange rate · Note**(HEAD_ALWAYS) · ⚠️ 취소된 발주는 아무것도 안 고친다
⭐⭐ Exchange rate 가 확정·마감 뒤에도 열리는 이유 — **원가가 이 값에 매달린다**(inv_layer_post_receipt · unit_price × CAD per USD). 실제 환율은 인보이스가 온 뒤에야 아는 경우가 있다
⚠️⚠️ 안 여는 것과 그 이유 — 머리 칸은 라인의 뜻을 바꾼다
   Supplier        바꾸면 라인의 단가 근거가 통째로 달라진다 — 잘못 골랐으면 새 발주가 맞다
   Currency        이미 적힌 USD 5.19 가 CAD 5.19 가 되어 버린다
   Payment term    (Caleb: 열 필요 없다) · Tax rule · Tax inclusive · Inventory account
⬜ Tax rule — ref_tax_rule 이 Settings 에 서면 그때 드롭다운으로 연다. ⚠️ 지금 세율을 몰라 「기록만」이고 자유 텍스트로 열면 국내 공급처가 생길 때 아무 글자나 쌓인다
   [Caleb] 「해외 계정은 모두 Zero-rated」 · ⭐ **QBO 가 연동되면 QBO 세율이 내려오고 그쪽이 우선**이다
```

### 11-c. ⭐⭐ 부분 입고 = 문서가 갈라진다 (오늘의 핵심 판단)
```
⚠️ Cin7 은 부분입고가 생기면 Simple → Advanced 로 convert 해서 한 문서 안에서 여러 번 받는다. 안이 복잡해진다.
⭐ 우리는 **문서가 갈라진다.** 각 문서는 한 번 받고 닫힌다. 안이 단순해진다(WMS 오더 분할과 같은 구조).

10개 주문 · 8개 도착 ⇒  PO-12345  →  PO-12345a (8개 · 받고 닫힘)
                                  +  PO-12345b (2개 · 기다림)
⭐ **받은 쪽에 a 가 붙는다**(Caleb) — 접미사가 있다는 것 자체가 「이 발주는 갈라졌다」는 표시가 된다. a·b·c·d 순서가 그대로 받은 순서다.
⭐ **원본 번호 PO-12345 는 남지 않는다 — a 가 된다.** 껍데기 문서를 두지 않는다.
   근거(Caleb): 「PO-12345 는 우리의 발주 번호일 뿐이다. 공급처가 레퍼런스로 쓸 수는 있어도 우리 방식이 더 중요하다」
   ⇒ 문서는 항상 **실제 입고 하나**에 대응한다. 원장·회계가 「둘 중 어느 쪽이 진짜인가」를 매번 가를 일이 없다.
   📌 [검토 Claude 추가] 공급처 인보이스에는 PO-12345 로 적혀 온다 — 찾기는 접두어로 한다. 번호 형식(지금 Cin7 은 PO-01010 다섯 자리)은 ~~표 설계 때~~ → [2026-09-16] **PO-02000 부터**(Caleb · Cin7 은 PO-01302 근처라 벌려 둠) · 다섯 자리 · 접미사 소문자 · CHECK `^PO-[0-9]{5,}[a-z]*$` · 접두어 찾기는 `po_number like 'PO-02000%'`(유니크 인덱스가 받는다).
b 가 또 갈라지면 c(받은 쪽) · d(남은 쪽). 규칙이 반복되고 예외가 없다.

⭐ **자동으로 갈라진다. 취소는 사람이 한다**(Caleb).
   사람이 그 자리에서 판단 못 하거나 깜빡해도 남은 수량이 반드시 문서로 남는다.
   안 온다고 판명되면 그 문서를 취소한다. ⚠️ 안 만든 문서는 나중에 기억해 낼 수 없다.
~~⬜ 갈라진 문서끼리의 연결 칸(바로 앞을 가리키나 · 맨 처음을 가리키나 · 둘 다)은 표 설계 때 정한다 — 오늘 미결.~~
→ [2026-09-16 닫힘 · Caleb] ⭐ **`split_from_id` → 바로 앞 문서.** 「PO-12345 가 모체고 바로 직전 알파벳에서 갈라진 것이니 바로 앞을 가리킨다」 — c→b→a 사슬로 갈라진 순서가 그대로 보인다. ⚠️ 「맨 처음을 가리키는 칸」은 두지 않는다 — 한 번에 모으는 것은 **번호 접두어로 찾는다**.
```
→ **표(2026-09-16 · §13)** 채번은 시퀀스 `po_number_seq`(2000 부터) + `po_next_number()` 를 `po.po_number` 기본값으로 — 동시 생성에서 겹치지 않고 PostgREST insert 만으로 번호가 붙는다. ⚠️ 시퀀스는 롤백돼도 되돌리지 않는다 — **빈 번호가 생긴다.** 허용한다(「PO-12345 는 우리 번호일 뿐」). ⚠️ authenticated 에 시퀀스 USAGE 가 필요하다(기본값은 insert 하는 역할로 실행된다). 접미사는 분할 함수~~(⬜ 다음 차수)~~ → ✅ 아래 가 붙인다.
→ **분할 함수(2026-09-18 · `20260918203805` po_receipt_confirm ⓒ · 커밋 0f50a7e · §13-i)** — 확정 RPC 안에서 라인 하나라도 남으면 갈라진다(판정은 라인마다).
```
번호        ⭐ **알파벳을 잇는다** — base(접미사를 뗀 번호)의 접미사 최댓값 다음 두 글자 · 없으면 a(받은 쪽)·b(남은 쪽) · 'b' 가 또 덜 받으면 c·d · 실물 조회(칸 없음 · 잠금 'po:'||base 로 형제 채번을 줄 세운다) · **y 이상이면 거부**(두 글자 접미사는 만들지 않는다)
라인 셋      다 받은 라인은 a 에 그대로 · **일부 받은 라인은 a 를 받은 만큼으로 줄이고 b 에 나머지 줄 신설**(line_no 같게 — 원장 line_ref 가 흔들리지 않는다) · ⭐ **하나도 안 온 라인은 지우지 않고 행을 b 로 옮긴다**(update po_id) — 인보이스 줄이 그 라인을 가리킬 수 있고 「인보이스가 먼저 온다」가 실무 · 한 인보이스가 a·b 에 걸치는 것은 11-g 가 허용
딸린 것      할인 줄(po_discount)은 b 에 **복사**(2026-09-16 Caleb 이 PO-02001b 에 손으로 한 것과 같다) · 비용 배분(po_charge_alloc.po_id)과 크레딧 채번 축(credit_po_id)은 **a 에 남는다**(문서에 붙는 것 · 11-b) · po(id) 를 가리키는 FK 는 넷뿐(grep)
b 의 머리    a 의 머리를 통째로 복사(칸이 늘어도 따라온다) · split_from_id = a · status confirmed · ⭐ **confirmed_at/by · created_by 를 물려받는다**(같은 확정의 나머지다 · po_list order_phase 가 confirmed_at 을 본다) · 닫힘·취소 흔적 없음 · created_at 만 지금
「닫는다」    실물은 **po.status = 'closed' + closed_at**(11-b 「closed = 입고 종료」) · ⚠️ closed_by 칸은 없다(§13-f) · 다 받았으면(초과만이어도) 갈라지지 않고 닫힌다
⚠️ entered_* 줄인 a 라인과 신설 b 라인에서 입력 단위 셋(entered_unit_product_id · entered_qty · entered_pack_factor)을 **비운다** — 「사람이 넣은 수 × 계수 = qty_ea」 검산이 더는 맞지 않는다 · warnings entered_units_cleared 에 라인 번호 · 옮긴 행은 그대로
⚠️⚠️ 크레딧  채번이 PO 번호 **접두어**를 읽는다(CN-<po_number>) — 확정 전에 크레딧이 났다면 PO-02011 → PO-02011a 뒤 접두어가 안 맞아 첫째 번호가 다시 난다. 실무는 크레딧이 입고 뒤라 드물다 · 고치지 않았다(§13-f)
```
→ ⚠️ **[2026-09-21 정정 · Caleb · 자택 세션] 채번 규칙이 바뀐다 — 원래 번호를 지킨다.** 위의 「받은 쪽에 a 가 붙는다 · 원본 번호는 남지 않는다 — a 가 된다 · b 가 또 갈라지면 c·d」와 분할 함수 표의 「번호」 줄은 **2026-09-21 까지의 규칙**이다. 지우지 않는다 — 판단이 바뀐 이력이다(so-module §2-m 을 같은 방식으로 정정했다).
```
바뀐 규칙     원래 문서는 글자를 받지 않는다 · **갈라져 나온 문서만** 다음 글자 **하나**를 받는다
              ⭐ **원래 번호는 「받고 닫힌 쪽」에 남는다**(Caleb 확정 2026-09-21 · 이견 1)
              PO-02001 (받고 닫힘 · 원래 번호 그대로) + PO-02001a (남은 것 · 기다림 · 새 글자)
              근거 ①  공급처와 주고받은 서류가 그 번호이고, **실제로 물건이 온 것이 그 번호 아래의 일**이다 — 서류와 실물이 같은 번호에 모인다
              근거 ②  2026-09-16 판단 「문서는 실제 입고 하나에 대응 · 껍데기 없음」이 그대로 살아 있다. 남은 쪽에 원래 번호를 주면
                      「아무것도 안 받은 문서가 원래 번호를 든다」가 되어 그 판단과 어긋난다
              ⚠️ **옛 규칙에서 방향이 뒤집힌 것이 맞다** — 옛 규칙은 받은 쪽이 `a`(글자를 받는 쪽)였고, 새 규칙은 받은 쪽이 **원래 번호**(글자를 안 받는 쪽)다. 글자는 안 받은 것에 붙는다
              PO-02001a 를 또 나누면 → PO-02001a (그대로) + PO-02001b        ⚠️ ba 아님 · 번호는 뭉치 안 순서 · 계보는 split_from_id
              ⇒ 한 글자 · 새 문서만 받으므로 **최대 24번**(a~x · y 이상이면 거부는 그대로) — 옛 방식은 분할마다 두 글자를 써 12번이었다
근거          ⭐ **SO 에서 나온 판단이다**(so-module §5-d). SO-25001 로 주문 확인서가 손님에게 나간 뒤에 스플릿이 일어나는데, 원래 번호가 사라지면
              **손님이 들고 있는 서류의 번호가 우리 시스템에 없게 된다.** 손님은 그 번호로 문의하고 결제하고 회계에 기록한다
              (so-module §2-b 가 번호 체계의 이유로 「손님에게 나가는 서류가 그대로다」를 든 것과 같은 결).
              PO 는 공급처 서류라 사정이 덜 급하지만, 두 모듈이 다른 방식으로 갈라지면 다음에 만지는 사람이 매번 어느 쪽인지 되짚어야 한다 ⇒ 같은 방식으로 맞춘다.
              📌 위 2026-09-16 근거 「PO-12345 는 우리 번호일 뿐 · 문서는 실제 입고 하나에 대응」은 여전히 참이다 — 새 규칙에서도 원래 문서는 「받고 닫힌 것」 하나에 대응한다. 껍데기가 생기는 것이 아니다.
              ⭐ **SO 와 공통 규칙 — 「일이 일어난 쪽이 원래 번호를 지킨다」**(Caleb 2026-09-21)
                PO   입고 확정 — **받은 쪽**이 원래 번호 · 안 받은 것이 새 글자
                SO   출하 확정 — **나간 쪽**이 원래 번호 · 백오더가 새 글자 (so-module §5-d)
              ⬜ so-module.md 에도 같은 문장을 넣을지는 다음 차수에서 판단한다.
그대로인 것   ⭐ **`split_from_id` 는 바로 앞 문서 · 뿌리 칸은 두지 않는다**(위 2026-09-16 닫힘 · 오늘도 유효) — ⚠️ 연결 칸 판단과 채번 판단은 **다른 것**이다. 오늘 바뀐 것은 「누가 새 글자를 받나」뿐.
              접미어 소문자 한 글자 · CHECK `^PO-[0-9]{5,}[a-z]*$` · 접두어 찾기 · 잠금 'po:'||base · 라인 셋 · 딸린 것 · 머리 복사 · 「닫는다」 규칙도 그대로.
⬜ 함수        **아직 옛 방식이다** — po_receipt_confirm 이 갈라지는 문서 자신에도 글자를 붙인다(`20260919192236` 435·440행 채번 · 485행 update po_number · 519행 number_before/number_after 반환). **함수 수정은 별도 차수.**
              그때 마이그레이션 주석 `20260916144201` 42·88행 · `20260918203805` 10행의 「a 받은 쪽 · 원본 번호는 남지 않는다」도 옛 문장이 된다 — 적용된 파일은 고치지 않는다(선례 · 새 파일 주석과 comment on column 다시 냄으로).
⭐ 이미 갈린 넷은 그대로 둔다(Caleb 2026-09-21) — 되돌리지 않는다.
  [실측 · Asung-IMS 테스트 · 2026-09-21]   PO-02001 → PO-02001a · PO-02001b   /   PO-02011 → PO-02011a · PO-02011b   (base_alive false = 원래 번호가 사라졌다 · 뭉치 둘 · 문서 넷)
  그 번호가 입고·인보이스·원장·레이어에 이미 박혀 있어 따라 고칠 자리가 여럿이고, 얻는 것이 그 위험만큼 크지 않다(연습 데이터 두 뭉치).
  ⇒ ⭐ **PO 번호에 두 세대가 섞인다 — 정상이고 의도된 것이다.** 옛 세대는 뿌리가 `a`(접미어 없는 번호가 없다) · 새 세대는 뿌리가 접미어 없는 번호. 대조하다 버그로 오해하지 마라.
  po_family_members 는 번호를 읽지 않고 split_from_id 만 따라가므로 두 모양을 가리지 않는다(§3-② 판단 · 아래 형제 문서 합계 소절).
📌 덤으로 풀리는 것   위 ⚠️⚠️ 「크레딧 채번이 PO 번호 접두어를 읽는다 — PO-02011 → PO-02011a 뒤 접두어가 안 맞는다」는 새 규칙에서는 **원래 문서 번호가 바뀌지 않으므로 생기지 않는다.** 옛 세대 넷에만 남는 이야기다(§13-f 「그 밖」의 같은 항목도 함수 수정 뒤 닫힌다).
```

### ⭐⭐ 크레딧 번호 — 우리가 붙인다 (2026-09-16 저녁 신설 · `20260916210000` · 커밋 `0b4a6aa`)

⚠️ 위 11-c 는 **발주 번호**만 다뤘다. 크레딧 번호는 정본에 없었다 — 여기서 처음 선다. 인보이스 번호와 **성격이 다르다**.
```
인보이스  **공급처가 붙인다.** 공급처가 그 번호로 문의해 온다(그래서 목록 검색과 po_list.doc_numbers 가 그 번호로 찾는다)
          ⇒ 우리가 만들지 않는다 · 없으면 거부한다(po_invoice_create 「Invoice number is required — it is the supplier's number」)
크레딧    ⭐⭐ **우리가 붙인다.** [Caleb 실측 2026-09-16] 「리시빙을 하면서 못 받은 것을 supplier credit 으로 돌린다.
          그 내역을 알려 주면 공급처가 진짜 크레딧 노트를 보내 주거나, 그냥 해당 금액을 까 준다」
          ⇒ **만들 때 번호가 없다.** 끝까지 공급처 번호가 안 오는 경우도 있다(금액만 까 주는 경우)

번호 모양
  발주에 붙는 크레딧   첫째 CN-<PO번호>          예 CN-PO-02001a
                      둘째부터 CN-<PO번호>-<n>    예 CN-PO-02001a-2 (n 은 2 부터)
                      ⭐ [Caleb] **첫째에는 꼬리를 안 붙인다** — 「보통은 2개 이상이 거의 없다」
                      📌 발주 분할(첫째에도 a · 위)과 **반대 판단**이다. 이유가 다르다: 발주는 갈라졌다는 사실 자체가 신호라 꼬리가 표시가 되지만,
                         크레딧은 대개 하나뿐이라 늘 -1 이 붙으면 아무것도 말하지 않고 지저분하기만 하다
  조정 크레딧          CN-<연도>-<네자리>          예 CN-2026-0001 · ⭐ 전 공급처 통합(공급처별이면 CN-2026-0001 이 여러 곳에 생겨 대화에서 헷갈린다) · 연도(문서 날짜)가 바뀌면 0001 부터

⭐ 공급처가 진짜 크레딧 노트를 보내오면 `po_invoice.supplier_ref_number` 에 **참조로 남긴다**
   ⚠️ 우리 번호를 갈아치우지 않는다 — 그동안 주고받은 기록이 안 맞게 된다. 📌 위 「PO-12345 는 우리의 발주 번호일 뿐」과 같은 판단
   ⚠️ 크레딧 전용이다(CHECK po_invoice_credit_only_ck) — 인보이스는 invoice_number 가 이미 공급처 번호다
   ⚠️ 유니크를 안 건다 — 공급처 크레딧 노트 한 장이 우리 크레딧 여럿을 덮을 수 있다(짐작 · 「금액을 까 준다」와 같은 결)
   ⭐ 확정 뒤에도 넣는다(PostgREST 한 칸) — 참조가 나중에 오는 것이 정상 흐름이고 장부를 안 건드린다(11-g 확정의 뜻 참조)
⚠️ 사람이 크레딧 번호를 주면 그대로 쓴다(공급처가 먼저 보내온 것을 사후 입력하는 실물 — Cin7 23537005816) · warnings credit_number_manual
⚠️ 미리 보기(p_commit=false)의 번호는 **잠정**이다(warnings number_is_provisional) — commit 때 다시 센다 · 사이에 다른 크레딧이 끼면 달라진다
```
→ **채번이 어떻게 도는가**(「최대 꼬리 + 1」 · 취소 포함 · `credit_po_id` · advisory lock)는 **§13-h** 에. 시험 데이터 CN-AMP-778812-1 은 대화 Claude 가 임의로 붙인 번호라 규칙의 실물이 아니다.
⭐⭐ **크레딧은 지우지 않는다 — 취소만** (2026-09-17 · `20260917100000` · Caleb 판정 · 검토 이견 5 를 뒤집음)
```
채번은 행을 읽는다   po_credit_next_number 는 시퀀스가 아니라 **po_invoice.invoice_number 행**을 읽는다(doc_kind='credit' · 접두어 CN-<po> / CN-<연도>-).
                    꼬리 없는 첫째(CN-PO-02001a)는 **존재 여부로만** 보고, 둘째부터는 CN-<po>-<n> 의 n 최댓값+1 이다.
                    ⇒ 첫째를 지우면 다음 크레딧이 **같은 번호를 그대로 다시 받고**, 마지막 꼬리를 지우면 그 꼬리가 다시 난다
근거가 무너진다      취소된 것을 세기로 한 근거(「공급처에 이미 알려 준 번호가 다른 문서를 가리키면 안 된다」)가 **삭제 한 번으로 무너진다** ⇒ po_doc_delete 가 doc_kind='credit' 을 status·confirmed_at 무관 무조건 거부한다
                    ⚠️ 「알려 준다」가 IMS 의 confirm 앞인지 뒤인지 정본 어디에도 없다 — 확인되지 않은 것 위에 채번 규칙을 얹지 않는다 ⇒ **초안 예외도 두지 않는다**
                    ⚠️ 확정 → Reopen(confirmed_at 이 지워진다) → 삭제, 클릭 둘로 빠져나갈 길도 이것으로 함께 닫혔다
                    ⚠️ 사람이 준 번호(CN-AMP-778812-1)도 같이 막는다 — 종류로 하나의 규칙(예외를 두면 화면도 설명도 갈린다)
대가는 대가가 아니다 시험 크레딧이 cancelled 로 쌓인다 — 쌓이는 곳은 테스트 DB 뿐이고 그 청소는 Caleb 이 SQL 로 한다 · 운영에서는 쌓이는 쪽이 옳은 동작이다. 저울: 한쪽은 지저분함 · 다른 쪽은 복구 불가
⚠️ 발주 번호는 다르다  시퀀스(po_number_seq)라 지워도 안 돌아온다 — 빈 번호는 위 11-c 에서 이미 허용했다
[실물 2026-09-17]   CN-AMP-778812-1 삭제 시도 → 「Credit note CN-AMP-778812-1 cannot be deleted — cancel it instead; its number must never be reused by another credit note — nothing was deleted」 (cancelled 여도 같은 문장 — 종류 검사가 상태 검사보다 앞)
```
~~⚠️ 초안을 지우면 그 번호가 다시 날 수 있다 — 지운 초안은 공급처에 안 갔다고 본다(짐작 · `20260916210000` 32행 주석)~~ → [2026-09-17 정정] 위 규칙으로 틀린 문장이 됐다. 마이그레이션 주석은 고치지 않는다(적용된 파일) — §13-h 의 같은 문장도 함께 고쳤다.
→ **형제 문서 합계(2026-09-19 · `20260919175712` · 9a5344a · 함수 `po_family_members(po_id)` · `po_family_lines(po_id)`)**
```
[Caleb] 「애초에 PO-02011 을 봐야 하는데, 오더가 스플릿 되니까 PO-02011a 만 봐서 생기는 문제로 보인다」
⇒ 차이를 닫으려 할 때 **그 발주가 결국 다 채워졌는지**가 보여야 판단이 된다 — 12 중 12 · 조각 a 10 · b 2(detail 의 diffs[].family · lines[].family · header.po_family)
⚠️⚠️ **계산은 DB 가 한다** — 화면이 형제를 찾아 더하면 규칙이 화면에 생긴다.
   [실사고 2026-09-19] 대화 Claude 가 검증용으로 손으로 쓴 재귀가 뿌리를 중복 제거하지 않아 **합이 두 배(24)로 나왔다.** 함수는 그 실수를 안 했다
⭐ 형제끼리 라인은 **product_id** 로 맞춘다 — ⚠️ line_no 로는 안 된다: 갈라진 b 는 confirmed 라 새 라인을 붙일 수 있고(po_lines_paste · 「draft·confirmed 는 붙인다」)
   그 line_no 는 b 안의 max+1 이라 a 의 다른 제품과 겹친다 ⇒ **다른 제품이 합쳐진다.** line_no 는 조각(fragments[])에 표시용
⭐ 뿌리 찾기 — split_from_id 로 올라가 뿌리에서 내려오며 전부 모은다(a → b → c·d 여러 단). ⚠️ 재귀는 순환을 막는다(path 배열 + 깊이 50) — 자기 참조도 두 문서 고리도 끝난다(실측)
⚠️ 「분할이 합을 보존한다」는 **분할 시점**의 이야기다 — 그 뒤 라인을 고치거나 지우면 합이 준다. 그것은 「가족이 정말 덜 시켰다」는 뜻이라 ordered_total 이 따라 주는 것이 맞다
   (실측 등식: 가족 ordered_total = short 차이의 expected_qty + 그 입고 이전 입고 합 · 어긋난 행 0)
```

### 11-d. 라인
```
수량·단가  ⭐ **저장은 낱개(EA)** — 원장·원가가 한 축으로 간다(inv_ledger.sku 는 base SKU · `20260816000000` 주석).
           실무도 대부분 낱개로 센다(Caleb) · 디스플레이 제품만 예외(콤보 방향 · §3-g)
⭐ 입력 단위를 고를 수 있다(Caleb: 「참 좋은 아이디어야」 · 오늘 채택)
   케이스로 넣으면 시스템이 낱개로 환산한다.
   ⚠️ [검토 Claude 정정] 환산값은 ③ 제품의 pack_factor(정본 BOM Quantity · §3-d)에 있다 — **product_supplier 에는 없다**(§3-g 표 실물 ·
      줄은 낱개에만 붙는다). 고를 수 있는 단위 = 그 낱개를 부모로 가진 세트 SKU 들(parent_product_id). 지시서의 「product_supplier 에 있다」는 오기.
   ⚠️ 지금은 **사람이 머릿속에서 환산**하고 있다 — [실물 Ampro] 인보이스 CASE 345 @ 20.34 를 Cin7 에 EA 2,070 @ 3.39 로 넣는다(§3-b ⑤).
      숫자 둘을 손으로 바꾸는 자리라 틀릴 여지가 있다.
   ⭐ **사람이 넣은 단위를 라인에 남긴다** — 인보이스와 대조할 때 「이 줄은 케이스로 넣은 것」이 보이면 검산이 된다.
      📌 [검토 Claude 제안 · ~~표 설계 때 판단~~ → 2026-09-16 채택] 그때의 환산 계수도 함께 남긴다 — pack_factor 가 나중에 바뀌어도 그날의 환산은 그대로여야 한다(§4-d 「그 순간에만 존재한 것」). → `po_line.entered_unit_product_id · entered_qty · entered_pack_factor`(null = EA 로 넣었다) · 인보이스 줄도 같은 칸 넷(11-g).
칸        제품 · 코멘트 · 공급처 SKU · 단위 · 수량 · 단가 · 세금규칙
          ⚠️ **라인 할인 칸은 두지 않는다** — 할인은 문서 위에 선다(11-e)
⚠️ 샘플은 수량이 있고 단가가 0 이다 — 금액 CHECK 에서 0 을 막지 마라(§3-b ④)
단가 출처  purchasing.html 285행(Caleb 확인): **Fixed Price → 없으면 Latest → 없으면 0(경고)**. IMS 발주 화면도 같은 순서로 제안한다(④ product_supplier 의 fixed_cost · cost).
~~⬜~~ 표 설계 때 정할 것 (단가 · Caleb 실측 2026-09-15) → [2026-09-16 일부 닫힘 · 아래 →]:
   Cin7 은 기본 단가를 Fixed Price / Last Price 중에 고르는 옵션이 있고, 지금은 Fixed Price 를 쓴다.
   실제 가격이 다르면 Cin7 PO 안에서 **그 줄의 가격을 고친다** — 그 발주에만 적용되고 마스터는 그대로다.
   ⇒ 우리 화면도 **두 자리가 갈려야 한다**:
      라인 단가     이번 발주만 바꾼다
      Fixed Price   마스터(product_supplier.fixed_cost) · 앞으로 계속 적용된다 — ~~purchasing.html 791~848행의 💲 기능이 이 자리(전환 기간에는 Cin7 에 쓴다 · 11-⓪)~~
   ⭐⭐ [2026-09-16 오후 · Caleb 결정] **Fixed Price 는 IMS 에서 고치지 않는다** — 「그것은 하지 말자. 우리가 개별로 가격을 수정하면 되니까」.
      ⇒ 전환 기간 동안 Fixed Price 의 정본은 **Cin7 하나**다. IMS 는 읽기만 한다 ⇒ 적재가 덮어써도 문제가 없고 두 곳이 갈라지지 않는다.
      ⇒ 발주에서는 **라인 단가만** 고친다 — 그 발주에만 적용된다. 붙여넣기에도 단가 칸(세 번째 열)을 두지 않는다 — 라인에서 고친다.
      ⇒ 위 ⬜ 「IMS 발주 화면에서 단가를 고치면 어느 쪽을 고치나」가 **닫힌다.** 📌 컷오버 뒤에 Fixed Price 가 IMS 로 넘어온다(그때 💲 기능이 옮겨 온다).
   ⭐ 라인 단가가 마스터와 다르면 **표시해 준다** — 「마스터도 고쳐야 하나」를 그 자리에서 판단할 수 있다(고치는 곳은 Cin7).
   ⚠️ 전환 기간에 Cin7 Fixed Price 를 고치면 다음 적재까지 IMS 화면에 안 보인다.
   ~~⬜ 기본값을 Fixed / Last 중에 고르는 옵션을 우리도 둘지는 나중에 정한다.~~ → [2026-09-16 닫힘] 옵션 없이 **폴백 순서로 확정** — Fixed>0 → Latest>0 → 0(경고 · no_price). `po_lines_paste` 가 그렇게 구현됐다(§13-d).
```
→ **표(2026-09-16 · §13)** ⭐ Fixed 와 Latest 는 **새로 만들 칸이 아니다** — `product_supplier.fixed_cost · cost · last_supplied` 에 이미 있다([실측 화면 · Caleb] products.html 상세 SUPPLIERS 표에 FIXED · LATEST · LAST SUPPLIED 셋 · ABE50205 / House of Cheatham 2.54 · 2.54 · 2026-08-17). 두 자리 갈림은 `po_line.unit_price`(이번 발주만 · 낱개 · numeric(18,7) · 0 허용) vs `product_supplier.fixed_cost`(마스터).
⭐⭐ **연습 기간에도 IMS 발주 확정이 Latest(cost · last_supplied)를 갱신한다**(Caleb 2026-09-16 · 흐름을 봐야 하니까). **그런데 적재가 돌면 Cin7 값이 덮는다 — 그것이 정상이다.** 컷오버 전까지 Latest 의 정본은 Cin7 이고, 마지막 적재 뒤 컷오버하면 그때부터 IMS 가 정본이다. ⚠️ 이 문장이 없으면 「IMS 가 쓴 값이 왜 사라졌지」가 버그로 오해된다. ⭐ 컷오버 때 **거래는 지우지만 Latest 는 남긴다**(11-⓪ 축의 예외). 갱신 동작 자체는 확정 RPC(⬜ 다음 차수). ⚠️ **[2026-09-20 실측] 그 갱신은 만든 적이 없다** — `product_supplier` 에 쓰는 DB 함수 0개(`po_lines_paste` 는 읽기만 · writes_it f) · AMP41103 `last_supplied` 2026-08-05 그대로(오늘 입고를 확정해도 안 움직였다). ⭐ **출처도 바뀌었다**(Caleb 09-20) — 발주 확정도 입고도 아니라 **확정 인보이스**다(11-g 「매입 가격 이력」 `po_price_history`). ⚠️⚠️ 공짜·초과분(over free)을 가격으로 세면 latest 가 0 이 된다 — 가격의 출처는 인보이스이지 입고가 아니다. ⬜ §13-f 「latest·fixed 갱신을 IMS 가 맡는다」.
⚠️ 라인 할인 칸 없음 · `tax_rule` 원문(ref_tax_rule 미결 §7-a) · `line_no` unique(po_id, line_no) 가 원장 line_ref.
→ **붙여넣기(2026-09-16 오후 · `po_lines_paste` · §13-d)** [실무 Caleb] **50줄 넘는 발주가 꽤 된다** — 하나씩 고르는 방식은 안 된다. 열쇠는 **우리 SKU**(「공급처 SKU 는 다 갱신돼 있지 않고 아예 없는 공급처도 있다」 — 공급처 SKU 는 참고로만 담는다).
⭐⭐ **미리 보기가 반드시 있다**(Caleb) — 밖에서 오는 데이터(엑셀 · 공급처 파일)라 옛 SKU·공백·칸 밀림이 있고, 50줄이 잘못 들어가면 하나씩 찾아 지워야 한다. 「이 공급처 제품이 아니다」가 마스터를 채우라는 신호가 된다. ⚠️ 미리 보기에서 **고치지 않는다** — 원본을 고쳐 다시 붙인다(그래서 duplicate·exists 도 합치거나 더하지 않고 판정만 · 합치면 「추가 주문」과 「중복 붙임」을 구별할 수 없다).
```
판정 여섯   ok(연결 있음 · 단가 Fixed→Latest→0) · no_link(SKU 는 있는데 이 공급처와 연결 없음/비활성 — 막지 않고 경고 · 단가 0 · 사람이 채운다) · not_found · duplicate(같은 붙임 안 중복) · exists(발주에 이미 있다 — 수량은 그 라인을 고쳐라) · bad_qty(0·음수·숫자 아님)
SKU 다듬기  앞뒤 공백(비분리 공백 포함)만 자른다 · 정확히 찾고 못 찾으면 대소문자 무시 폴백 · 안쪽 공백·철자는 손대지 않는다(§3-f)
한도       500줄 — 예외가 아니라 **판정**(summary.too_many · 넣지도 않는다) · closed·cancelled 는 예외 · draft·confirmed 는 붙인다(확정 뒤 추가 · 11-b)
[화면 실측 · Caleb 2026-09-16] By Natures 제품들은 연결이 아예 없어 단가 0 으로 들어갔다 · Strength of Nature 는 공급처 SKU 와 단가가 다 따라왔다(3.43 · 3.5 · 3.23 · 2.41 · 소계 586.92) — 설계대로다
```
→ **한 줄 고르기 「Add a line」(2026-09-19 · 화면 po.html · 대화 Claude)** — ⚠️ 붙여넣기를 대신하는 것이 아니다. 50줄짜리는 붙여넣기고 **한둘을 더할 때**가 이것이다.
```
후보          **그 공급처가 파는 것만**(product_supplier · is_active) — 수천이 백 개 안팎으로 준다
판단 재료      **fixed 와 latest 를 나란히** 보인다 (⚠️ 실측: Ampro 112 중 76 이 다르다 · 전체 12,728 중 fixed 가 싼 것 6,378 · 비싼 것 1,709 · 같은 것 4,641)
              ⚠️⚠️ **화면이 판정하지 않는다.** 「낡았다」고 쓰면 아닌 경우에 거짓말이 된다 — 협상가일 수도, 지난번만 예외였을 수도 있다. 숫자 둘을 놓고 다르다는 것만 보인다
단가          **화면이 정하지 않는다** — po_lines_paste 가 Fixed>0 → Latest>0 → 0 으로 고른다(2026-09-16 확정) ⇒ 나중에 발주앱이 생겨도 같은 값
미리 보기      두 단계 그대로(Check → Add) — 자동으로 채운 단가를 사람이 한 번 본다 · 판정 표는 **공통(runLines)** — 붙여넣기와 한 줄 고르기가 같은 RPC·같은 판정·같은 표
중복          같은 SKU 를 두 번 넣으면 **합산하지 않고 거부**(Caleb) — duplicate·exists 판정 그대로
⬜ 셋째 재료   「우리가 지난번에 적은 값」(po_line.unit_price)은 아직 쌓이지 않았다. 그것이 서면 「우리는 5.19 로 발주했는데 latest 가 5.49 다」가 읽히고 **그게 진짜 신호**다(청구가 다르게 오고 있다)
```

### 11-e. ⭐⭐ 할인 — 문서 위에 줄로 선다
```
⭐ Caleb 의 요구: 「라인마다 일일이 넣는 것이 아니라 **일괄로** 넣어 적용되었으면 좋겠다」
⇒ §3-b D `supplier_discount` 의 설계가 정확히 그것이다. 새로 정할 것이 없었다.
   공급처를 고르면 그 공급처의 상시 할인 줄이 따라 들어온다 · 이번만 다르면 문서에서 고친다 ·
   마스터에 없는 스페셜 할인은 줄을 추가한다(「마스터는 제안이지 잠금이 아니다」)
⚠️⚠️ 체인이다 — 차례로 **곱해진다**. 더하는 것이 아니다([실물 Ampro] 21% 로 더하면 146 달러 어긋난다 · §3-b D)

⭐⭐ 오늘 새로 정한 것 — 원가로 내려가는 방법
   Caleb 의 뜻: 「개별 단위별로 주고 싶다」 = 그 할인이 **각 제품의 원가까지 내려가야 한다**(안 그러면 COGS 가 틀린다)
   ⇒ 문서 위 할인을 라인들에게 **금액 비례**로 나눈다
   ⚠️ 반올림 잔돈은 **금액이 가장 큰 줄**에 몰아 준다(Caleb 결정). 근거 둘:
      ① 큰 줄일수록 잔돈이 개당 원가에 미치는 영향이 작다(1,200개짜리 vs 30개짜리)
      ② 「마지막 줄」은 정렬에 따라 바뀐다 — 가장 큰 줄은 정렬과 무관하게 같다(결정론적)
   ⚠️ 동점이면 SKU 순으로 앞선 줄(규칙이 없으면 매번 결과가 달라진다)

⭐ **조기결제 할인은 여기 안 섞는다** — 돈 낼 때 생기고 원가로 안 내려간다. `ref_payment_term` 이 정본(§3-b D · §4-②)
⭐ **문서 분할이 뜻밖에 여기서 돕는다** — §3-b ③ 「할인은 인보이스 단위인데 Cin7 은 PO 단위로 배분해서 아직 인보이스 안 된 부분의
   원가까지 내린다」(실물 PO-01010 의 498.33). 부분입고마다 문서가 갈라지면 **문서 하나가 대체로 인보이스 하나와 맞아떨어진다.**
   그 문제가 구조적으로 줄어든다(⚠️ 없어지는 것은 아니다 — 한 인보이스가 여러 쉽먼트로 오는 경우는 11-g 가 받는다).
```
→ **표(2026-09-16 · §13)** ⭐⭐ 할인이 **두 층**이 됐다 — 「문서 위에 선다」는 그대로이고 **「어느 문서」가 둘**이다.
```
po_discount           예상 — 발주를 만들 때 supplier_discount 에서 제안받아 넣은 값 · 발주 금액 계산용 · 인보이스를 만들 때 복사 제안된다 → ✅ [2026-09-16 저녁] `po_invoice_create(p_copy_discounts default true)` 가 그렇게 한다 · ⚠️ 같은 날 지시서(po-invoice-write.md)가 이것을 「미결」이라 적었다 — 정본을 안 보고 쓴 대화 Claude 의 오기(검토가 이 줄을 근거로 잡았다)
po_invoice_discount   확정 — 공급처가 인보이스에 적어 보낸 값([실물 Ampro] Trade 17% → Damage 1% → Full Line 3%) · ⭐ **원가 배분의 정본**(11-g ①)
```
⇒ §3-b ③ 「우리 할인 줄은 어느 인보이스에 속하는지 알아야 한다」가 이것으로 닫힌다. 둘 다 `seq · name · percent(0~100) · supplier_discount_id(원천 · 스페셜은 null)` · unique(문서, seq) · 차례로 곱한다. 배분 규칙(금액 비례 · 잔돈 · 동점 SKU 순)은 계산 — 칸 없음. [실측 · Caleb 2026-09-16 · SQL] 소계 2,755.80 에 17%·1% 를 곱하면 2,264.44 · 더하면 2,259.76 — **차이 4.68**. 「차례로 곱한다」가 실제로 다르다.
⭐ [2026-09-16 오후 · Caleb] 인보이스 할인 체인은 **goods 줄에만** 곱한다 · charge(운임) 줄에는 안 곱한다 · ⬜ **other(우리가 안 시킨 것) 줄은 판단 보류** — 공급처가 할인을 적용했는지 우리가 모른다. total_amount 가 대조값으로 있으니 잘못 계산하면 차이로 드러난다 — 실물이 나왔을 때 그 차이를 보고 정한다. 지금 짐작으로 정하지 않는다(`po_detail` · §13-d). → [2026-09-20] **매입 가격 이력(`po_price_history` · 11-g)에서는 other 를 뺀다**(po_line 이 없어 SKU 를 모른다 · `po_price_history_skipped` 에 reason `not_ordered` 로 남는다).
→ **쓰기(2026-09-16 저녁 · `20260916200000` · §13-h)** ⚠️ 그때까지 할인 줄은 **화면에서 만들 수가 없었다** — 보여 주기만 했다(대화 Claude 가 SQL 로 넣었다).
⭐ [Caleb 요구] 「늘 주는 건 아니지만 **이번 인보이스에 한해 10%** 를 줄 수 있다 — 그런 경우 문서에 적용할 수 있어야 한다」 ⇒ 세 자리가 열렸다: `supplier_discount`(상시) · `po_discount`(발주) · `po_invoice_discount`(인보이스·크레딧).
```
RPC 둘     po_discount_save(p_target: supplier | po | invoice · p_patch · p_id) · po_discount_delete(p_target · p_id)
PostgREST 로 안 되는 이유 둘
  ① seq 는 곱해지는 차례라 뜻이 있고 unique(문서, seq) 다 — max+1 을 화면 세 곳이 각자 세면 어긋난다. 안 주면 RPC 가 max+1 · 겹치면 읽을 문장 · 지운 뒤 빈 seq 는 둔다(순서만 뜻이 있다)
  ② ⭐ 상태 검사가 **다른 행**에 있다 — po_discount 는 closed·cancelled 발주를, po_invoice_discount 는 draft 아닌 인보이스를 막아야 하는데 PostgREST 는 그 행을 못 본다(§5 「쓰기는 RPC 가 저장 전에 본다」)
  supplier_discount 삭제는 문서 줄이 FK(no action)로 가리키면 어차피 막힌다 — 읽을 문장으로 「비활성으로 내려라」 · source=manual
⚠️⚠️ **라인에는 여전히 할인 칸이 없다.** 할인은 문서 위에 서서 모든 라인에 한꺼번에 걸린다 — 그것이 요구의 핵심이었다(위 ⭐ Caleb 의 요구)
복사 두 번   po_create: supplier_discount → po_discount(지금 0행이라 따라올 것이 없을 뿐) · po_invoice_create: po_discount → po_invoice_discount **복사 제안**(p_copy_discounts) · ⚠️ 크레딧에는 복사하지 않는다(공급처 문서에 적힌 대로)
Source 열    supplier_discount_id 가 「따라온 줄」(from supplier)과 「여기서 더한 줄」(added here)을 가른다 — 두 화면(po.html · invoices.html) 같은 규칙
```

### 11-f. ⭐ 비용(운임·관세·통관) — 별도 문서가 PO 여럿을 가리킨다
```
실무 실측(Caleb · Cin7 화면): 운송·관세·통관은 **Service invoice 로 갈라서** 만들고 있다.
  [실물] Ampro 발주 옆에 CBSA(관세)·BBE(통관중개)가 각각 자기 문서로 선다 · Type=Service · Stock status=Not available
  날짜가 짝을 이룬다(07/15 · 08/03 · 09/04 에 둘이 함께)
⭐ 원가에 들어간다 — §3-b 의 구별선 그대로: 「물건의 원가에 얹히는 것은 우리 것, 나머지는 회계(QBO)의 것」
  ⚠️ 그래서 Showtime(운송) 같은 곳이 is_purchasable=false 여도 IMS 에 남아야 한다는 문장이 이미 있다(§3-b 열린 물음)

⭐⭐ **별도 문서로 간다**(오늘 결정). 결정적 근거:
   ⚠️ **컨테이너 하나에 여러 공급처 물건이 섞여 들어오는 경우가 있다**(Caleb 실측).
   ⇒ 청구서 한 장이 PO 여러 건에 걸친다. PO 안에 넣으면 그 순간 쪼개야 하고,
      쪼개면 원본 청구서와 우리 기록이 일대일로 안 맞는다 — 회계와 맞출 때 곤란해진다.

배분은 두 단계
  ① 청구서 → PO 들       ⭐ **금액 비례**(Caleb) · ⚠️ 사람이 직접 고칠 수 있게 연다
     📌 무게·부피가 더 정확하지만 우리는 그 값을 갖고 있지 않다(제품 치수 넷 전량 0 · Weight 만 값 — §3-d 「담지 않는 것」).
        열어 두면 나중에 무게가 생겨도 구조를 안 바꾼다
  ② PO → 라인들          11-e 와 **같은 규칙**(금액 비례 · 잔돈은 가장 큰 줄 · 동점은 SKU 순)
  ⭐ [2026-09-18] 발주가 갈라져도(11-c) 배분은 **a 에 남는다** — po_charge_alloc.po_id 는 확정 순간의 문서 · b 로 나누지 않는다(비용은 문서에 붙고 닫힌 문서에도 붙는다 · 11-b)
  ⭐ [2026-09-16 추가] ① 청구서 → PO 들 에도 **잔돈 규칙이 필요하다** — 금액 비례 · 잔돈은 금액이 가장 큰 발주 · ⚠️ 동점은 **발주번호 순**(발주 단위엔 SKU 가 없다 — 11-e 를 그대로 옮기며 놓친 것).
     [실측 · Caleb 2026-09-16 · SQL] CBSA 2,547.37 을 두 발주에 597.49(23.5%) + 1,949.88(76.5%) 로 나눈 것은 **우연히 맞았다.** 발주가 셋 이상이거나 비율이 나쁘면 센트가 남는다. 적어 두지 않으면 화면마다 다르게 구현한다.

⭐ **비용은 스탁을 다 받은 뒤에 붙는 경우가 많다**(Caleb) ⇒ ~~입고가 끝나도 문서가 바로 안 닫힌다(11-b).~~ → [2026-09-16 정정] 문서는 입고가 끝나면 닫히고(closed = 입고 종료) **비용은 닫힌 문서에도 붙는다**(11-b · po_charge_alloc 에 제약 없음).
   ⚠️ 원가는 고치는 것이 아니라 **더한다** — `inv_layer_cost_add` 가 이미 그 자리다(§12-c).
~~⬜ Type=Service 53 · Non Inventory 4 를 담을 자리(§3-d·§7 미결)가 여기서 쓰인다 — 표 설계 때 함께 정한다.~~ → [2026-09-16 닫힘] 비용 문서는 제품을 참조하지 않는다 — 자리가 필요 없어졌다(§13).
```
→ **표(2026-09-16 · §13)** `po_charge`(줄 없는 문서 · kind·description · 총액) + `po_charge_alloc`(발주에 얼마). ⭐⭐ 배분 금액은 넣을 때 계산해 **박아 두고 발주 금액이 나중에 바뀌어도 다시 계산하지 않는다**(Caleb) — 한번 원가 층에 더해진 금액이 저절로 바뀌면 원가가 흔들린다 · 고치려면 사람이. 「배분이 안 따라온다」는 버그가 아니라 설계다.
⭐ closed(입고 종료) 문서에도 붙는다 — 제약 없음. ⚠️ 비용 청구서도 **돈을 낸다** — 결제 충당(`po_payment_alloc`)이 인보이스뿐 아니라 이 문서도 가리킨다(11-h).
→ **쓰기(2026-09-17 · `20260917150000` 901행 · 커밋 38f1098 · 화면 `charges.html` 신설 · 검토 이견 1~16 · 5(통화 폴백)만 뒤집음)**
```
만드는 자리   비용 화면에서 새로 만든다 — 청구서가 먼저 손에 있다(Caleb). PO 상세의 「Add a charge」는 p_po_ids 에 그 발주 하나를 담아 같은 RPC 를 부른다
             ⚠️ 인보이스처럼 「PO 에서 갈라 만든다」가 아니다 — 비용의 공급처는 발주처가 아니고(CBSA · BBE · Showtime) 컨테이너 하나가 PO 여럿에 걸친다(위)
             ⚠️ 통화는 **사람이 고른다 · 폴백 없음**(Caleb · 이견 5 뒤집음) — 비용처는 건마다 통화가 다를 수 있어 마스터 값이 그 청구서의 통화라는 보장이 없고, 틀려도 결제 단계까지 조용히 간다
확정          인보이스와 같게 잠근다(배분 편집 RPC 넷이 draft 만 받는다) · Reopen 은 결제 충당이 있으면 거부(po_invoice_confirm 과 같은 선 · 참조번호·금액을 이름으로)
             ⚠️ 뜻이 다르다: 비용은 문서가 서는 순간 **이미 미지급**이다(po_charge_money.unpaid 는 status 를 안 본다)
             ⇒ 비용의 확정은 「돈이 생긴다」가 아니라 **「이 배분으로 원가에 얹겠다」는 선언**이다
배분 편집     ⭐⭐ **고친 줄만 바뀐다. 나머지는 저절로 움직이지 않는다**(po_charge_alloc_add · _update · _delete)
             ❌ 기각(Caleb): 「고친 줄을 뺀 나머지를 다시 비례로」 — 사람이 확인하고 지나간 칸이 다른 칸을 고칠 때마다 바뀐다. 「박아 두고 다시 계산하지 않는다」와 반대 방향이다
             ⇒ 합이 총액과 안 맞는 중간 상태가 정상(po_charge_money.unallocated 가 그 값) · 다시 비례로 채우는 것은 po_charge_alloc_spread 를 **사람이 누를 때만** — 어떤 저장도 자동으로 부르지 않는다
확정 전 검사  ⭐⭐ unallocated ≠ 0 이면 **거부한다**(경고가 아니다 · 문장에 총액·배분합·미배분 셋)
             ⚠️ 인보이스의 diff 는 경고였다 — 거기는 공급처가 찍은 총액이 정본이고 우리 계산이 대조값이라 둘이 달라도 공급처 문서가 이긴다.
                비용 배분은 **양쪽 다 우리가 넣는 숫자**라 안 맞으면 덜 입력한 것이다. 그 밖: 배분 0줄 ⇒ 거부 · total 0 ⇒ 경고 · 취소된 발주에 배분 ⇒ 경고
비례 규칙     한 곳 — po_charge_alloc_propose(만들기와 spread 가 같이 쓴다 · 규칙이 두 곳이면 갈린다) · 기준은 발주의 **라인 금액 합(할인 전 · po_list.subtotal 과 같은 식 sum(round(qty_ea×unit_price,2)))**
             줄 = round(총액×기준/합, 2) · 잔돈(총액 − 줄 합)은 기준이 가장 큰 발주 · 동점은 발주번호 순 · 기준이 전부 0 이면 균등 + warnings no_base_amount
읽기          뷰 po_charge_list(po_invoice_list 와 같은 모양 · po_numbers 로 발주 번호 검색 · 배분 없는 청구서도 보인다) · RPC po_charge_detail(allocs[] 에 base_amount · other_charges — 사람이 배분을 고치는 판단의 재료)
취소·삭제     po_doc_cancel / po_doc_delete 의 p_target 'charge'(§11-b) · cancelled_by 신설 · 취소는 결제 있으면 거부 · 배분은 경고만 · 삭제는 confirmed_at null 만 · allocs_deleted
```
⭐⭐ **[실물 2026-09-17 · Caleb SQL] 박아 둔 배분이 발주 금액 변화를 안 따라오는 실례가 나왔다.** CBSA 2,547.37 의 배분 597.49 / 1,949.88 은 2026-09-16 정오 기준값(PO-02002 소계 7,985.00 · 그때 discount_factor 1.000000)에서 나왔고,
그 뒤 PO-02002 라인이 +25.40 되어 지금 기준은 8,010.40 이다 ⇒ 지금 비례로는 596.04 / 1,951.33(차이 1.45). **다시 계산하지 않는다 — 설계대로다.** spread 를 사람이 누를 때만 596.04 / 1,951.33 이 된다. §13-b 2868행의 「소계 7,985.00」은 그날 실물이지 오기가 아니다(§13-b 덧붙임 · §13-a 경위).
→ **원가(2026-09-19 · `20260919200414` 280행 · 커밋 83b79f5 · 원가 이식 2차)** ⭐ **비용 확정이 원가에 얹는다** — `po_charge_confirm` 이 확정 뒤 같은 트랜잭션으로 `inv_layer_post_charge` 를 부른다(원칙 2 「안에 있는 것끼리는 창구를 부른다」).
```
얹는 곳       그 발주의 IMS 입고 레이어(po_line 을 거쳐 · cost_source po_line) · kind 넷 전부 **landed** · 금액 비율(unit_cost × qty) · CAD(⚠️ CAD per USD · amount × rate · 곱한다)
게이트 ⑥      기준통화가 아닌 비용에 환율이 없거나 0 이면 **확정 거부**(입고와 같은 이유 · 문장이 어디서 고치는지 말한다)
⚠️⚠️ 되돌리기   landed 가 얹혔으면 **거부** — 되돌려 배분을 고치고 다시 확정해도 멱등이 건너뛰어 옛 금액이 남는다. 고치는 길은 상쇄 비용 문서(append-only)
반환          cost{layers_touched · amount_posted_cad · no_layers(입고 없는 발주 · 백필 창구) · no_basis(단가 0 · 버림) · allocs[]} · warnings cost_not_on_stock_no_receipt_yet · cost_dropped_no_basis
⚠️ 위 「박아 둔 배분은 다시 계산하지 않는다」와 한 쌍 — 얹힌 뒤에는 배분도 landed 도 고치지 않는다 · 정본(원가 규칙)은 ledger-design 4부 「원가 이식 2차」
```

### 11-g. ⭐⭐ 인보이스 — 자기 행으로 서고 PO 여럿을 가리킨다
```
실무: 인보이스는 **이메일로 온다** · PO 에 파일을 업로드한다 · 내역은 대개 PO 에 있으므로 거기서 갈라 만든다
  (Cin7 은 Invoice 탭에서 Copy 를 누르면 PO 내역이 전부 딸려오고, 백오더 난 것을 거기서 빼낸다)
  📌 Cin7 은 한 PO 안에 탭이 여럿이다 — Order · Invoice · Stock received · Credit note · Unstock  → 크레딧 노트는 아래 **「크레딧 노트」** 소절(2026-09-16 오후 신설)

⭐ **화면은 Cin7 처럼** — PO 를 열면 그 PO 에 걸린 인보이스가 보인다(보이는 모양은 같다)
⭐⭐ **저장은 인보이스 한 장 = 한 행** — ~~그 행이 PO 들을 가리킨다~~ → [2026-09-16 정정 · Caleb 「줄 수준으로 가자」] **줄(po_invoice_line)이 po_line 을 가리킨다.** 머리에 PO 칸은 없다 — 두 단계 조인(po_invoice_line → po_line → po)으로 낸다(받은 수량을 안 둔 것과 같은 이유 · 줄이 바뀌면 어긋난다). ⭐ [2026-09-16 저녁 · 예외 하나] 크레딧의 `credit_po_id`(`20260916210000`)는 「걸린 발주」가 아니라 **번호를 낸 발주 = 채번의 축**이다 — 관계는 여전히 줄이 말한다(po_detail credits[] · po_list credit_count 는 줄로 센다). 줄로 유추하면 줄이 빈 조정 크레딧에선 안 되고 · 발주 둘에 걸친 인보이스에선 정해지지 않고 · 줄을 고치면 이미 붙은 번호의 근거가 사라진다(§11-c 크레딧 번호 · §13-h). 근거 셋: ② 의 수량 차이는 줄이 없으면 안 보인다 · 할인이 물건에 비례로 내려가려면 어느 물건인지 알아야 한다 · 실무가 줄 단위다(Copy).
   근거: ⚠️ **한 인보이스가 여러 쉽먼트로 오는 일이 종종 있다**(Caleb).
        우리는 입고마다 문서가 갈라지므로 그 인보이스가 PO-12345a 와 b 둘 다에 걸린다.
        PO 안에 넣으면 한 장을 쪼개야 하고 ⇒ 인보이스 번호가 두 군데 생겨 회계에서 「INV-2142773 이 어디 있지」 할 때 두 곳을 봐야 한다.
   ⇒ 총액은 한 번만 있다. 두 번 세지 않는다. 할인도 그 인보이스에 한 번 걸리고 줄들을 통해 양쪽 PO 로 내려간다.
   ⇒ 반대 방향도 된다 — PO 하나에 인보이스 여러 장(실물 PO-01010 · §3-b ③).
   📌 **비용 문서와 같은 모양이다** — 「밖에서 오는 청구서가 우리 발주 여럿을 가리킨다」로 규칙이 하나로 선다.

⭐ **우리 구조에서는 Copy 가 더 간단해진다** — 입고할 때 이미 문서가 갈라져 PO-12345a 에는 백오더가 빠진 상태다. 빼는 손이 한 번 줄어든다.
⭐ 인보이스 확정이 일으키는 것 **셋**:
   ① 인보이스에 걸린 할인이 원가로 내려간다(11-e)
   ② 인보이스 수량과 우리가 받은 수량(po_receipt_line 합)의 차이가 드러난다 — 그리고 **PO 에 없는 줄**(우리가 안 시킨 것 · 운임)도 차이다
   ③ ⭐ **미지급이 생긴다**(Caleb 지적 — 대화 Claude 가 빠뜨렸다)
      ⇒ 결제조건이 여기서 처음 일한다: 인보이스 날짜 + ref_payment_term = 기한
        [실물 표기] `2%10 Net30` = 기일 30일 · 10일 안에 내면 2%(§4-②)
        ⚠️ 그 값을 담을 ref_payment_term 34행이 지금 비어 있다(§10-k) — **여기서 쓰인다.** 채우는 시점 = 첫 인보이스를 IMS 에서 만들 때
📌 Cin7 의 `Extract from file`(인보이스 파일에서 내용 추출)은 나중에 우리도 붙일 수 있는 자리 — 지금 정하지 않는다
```
→ **표(2026-09-16 · §13)** `po_invoice`(머리) · `po_invoice_line` · `po_invoice_discount`(11-e).
```
po_line_id     ⭐ nullable + line_kind CHECK(goods · charge · other) + description — 인보이스는 **밖에서 오는 사실**이다. 공급처가 안 시킨 것을 청구하거나 **운임을 인보이스에 넣어 보낸다**
               ([실물] §3-b Comments 「인보이스에 있는 shipping cost 빼고 pay 함」 — Ampro 인보이스에 운임이 들어 있다). 막으면 그런 인보이스를 IMS 에 못 넣고 「PO 에 없는 줄」이라는 차이가 사라진다
is_payable     ⭐⭐ 운임을 빼고 내는 실무를 닫는 칸 — 미지급 = payable 줄 합(할인 적용 후) − 충당 합. 없으면 그 인보이스가 **영원히 미지급으로 남는다**
               [실측 · Caleb 2026-09-16 · SQL] AMP-778812 청구 2,197.54(운임 187 포함) vs 갚을 돈 2,010.54 — 운임 줄 is_payable=false 로 미지급 0
단위 칸 넷      qty_ea · entered_unit_product_id · entered_qty · entered_pack_factor — 인보이스는 CASE 345 @ 20.34 인데 우리 라인은 EA 2,070 @ 3.39(§3-b ⑤) · **대조하려면 낱개로 서야 한다**
total_amount   ⭐ 인보이스에 찍힌 값(정본) · 줄 합 × 할인 체인은 계산값 ⇒ **대조값**이다(두 곳에 적는 것이 아니다) · 다르면 입력 오류·반올림
               [실측 · Caleb 2026-09-16 · SQL] 처음 근거 없이 2,451.44 를 넣자 차이 −253.90 이 드러났다 · 바로 넣으면 2,010.54 + 187 = 2,197.54 = 찍힌 총액(차이 0.00)
유니크          ~~(supplier_id, invoice_number)~~ → [2026-09-16 ③차] **(supplier_id, doc_kind, invoice_number)** — 공급처가 다르면 같은 번호가 있을 수 있어 전역은 틀리고, 안 걸면 같은 인보이스를 두 번 넣는 것이 조용히 지나간다(「총액은 한 번만」). 종류를 넣은 이유는 아래 크레딧 소절
due_date       사람이 넣는다 — invoice_date + ref_payment_term.net_days 로 계산해야 하지만 **34행이 전부 비어 있다**(§10-k) · 채워지면 화면이 제안
상태           draft · confirmed · cancelled — 「결제됨」은 상태가 아니라 진행도(충당 합)
⬜ 파일 업로드 칸은 두지 않았다 — Supabase Storage 결정 미결(§10-k)
```
⭐ 갈라진 문서 덕에 a 는 주문=입고가 맞아 **Copy 할 때 뺄 것이 없다** — [실측 · Caleb 2026-09-16] PO-02001a 세 라인 주문=입고 완전 일치.

**⭐⭐ 매입 가격 이력 — `po_price_history` (2026-09-20 · `20260920163231_po_price_history.sql` · 커밋 `497cd59`)** — 특정 SKU 를 **언제 얼마에 샀나**. 출처는 발주가 아니라 **확정 인보이스**다.
```
⭐ [Caleb 2026-09-20 · 말 그대로]
  「우리는 우리가 업데이트한 fixed price 와 가장 최근에 받은 latest price 를 사용하고 있어. 컷오버 뒤에는 우리가 업데이트를 해야 하는 거야」
  「난 솔직히 말하면 latest price 만 있는 것은 아쉬워. ⭐ 특정 SKU 의 구매가를 한눈에 볼 수 있는 게 제일 좋아」
  「인보이스는 공급처에서 제공하는 실제 가격이 들어있는 문서야 … 당연히 인보이스가 가져와야 해. ⭐ 그런데 해당 인보이스에 적용된 **디스카운트도 볼 수 있어야** 제대로 된 확인이 될 것 같아」
⇒ 한 칸에 마지막 값만 두면 그 값이 예외였는지 추세였는지 알 수 없다. 할인을 빼고 보면 8.29 로 적혀 있어도 17% 가 걸렸으면 실제는 6.88 이다 — 모르고 「지난번 8.29 였으니」 하면 매번 조금씩 비싸게 산다.

뷰 둘(security_invoker · PostgREST 필터 · RPC 없음 — 계산이 없다)
  po_price_history          한 줄 = 확정 인보이스의 goods 줄 하나 · product·supplier·invoice·po · qty · gross_unit · factor · net_unit · discount_label · currency_code · is_base_currency ·
                            exchange_rate · exchange_rate_source · net_unit_cad · has_credit · credit_count · credit_numbers · confirmed_at
  po_price_history_skipped  확정 인보이스 줄 중 위에 안 나오는 것 + reason(charge · not_ordered · not_payable · zero_price · negative_qty) — ⭐ 두 뷰의 합 = 확정 인보이스의 모든 줄(조용히 사라진 줄 0)
규칙
  담는 것   doc_kind invoice · status confirmed · line_kind goods · is_payable · 단가 > 0 · 수량 > 0
  단가      net_unit = round(unit_price × factor, 6) · factor 는 **po_invoice_money 의 po_mul 체인**(정본 하나 · 다시 계산하지 않는다) · ⚠️ 할인은 goods 에만(문서 총액 = round(goods_sum × factor, 2) + other_sum · 운임에 곱하면 안 된다)
  discount_label ⭐ 「Trade 17% · Damage 1%」(seq 순 · 곱해지는 차례) — 계수 0.8217 만으로는 사람이 확인할 수 없다 · 17% × 1% = 0.8217 이고 18% 가 아니다
  통화      인보이스 통화가 기준 · 기준통화(inv_config.base_currency)면 is_base_currency=true · 환산하지 않는다(같은 숫자를 두 번 그리지 않는다) · ⚠️ CAD 공급처가 75곳(257 중) — 드문 경우가 아니다
  환율      인보이스 → 발주(⚠️ 통화가 같을 때만 — 다르면 남의 환율) → null · exchange_rate_source 가 출처를 말한다 · ⚠️⚠️ 없으면 net_unit_cad 는 **null**(0 아님 — 0 은 가격으로 읽힌다)
  크레딧    이번 판에 안 섞는다 — has_credit · credit_numbers 로 표시만
  세트      다루지 않는다([Caleb] 「실제로 우리는 세트로 주문하지 않아」 · entered_pack_factor 23행 전부 null)
⚠️ 왜 is_payable 을 거르나 [Caleb 실무] 「goods 는 모두 payable 이 기본적으로 맞아. 그런데 간혹 ⓐ 우리가 쓸려고 가져오는 제품들도 인보이스에 섞여 오는 경우가 가끔 있어. 사실 이것은 우리가 다르게 처리해야 하는 게 맞아. ⓑ 그리고 공짜로 보내주는 경우도 있긴 있지」
  ⇒ ⓐ 는 돈은 내지만 판매용 매입과 조건이 다르다 · ⓑ 는 애초에 가격이 아니다 — 둘 다 이력에서 뺀다(skipped 에 not_payable) · ⬜ ⓐ 가 재고로 들어가는 길이 있는지 모른다(§13-f)
⚠️ 왜 크레딧을 뺐나 [Caleb 실무] 「주로 수량 쪽이야. 그러나 가격 쪽도 간혹 존재해. 얼마 전에 한 공급업체는 가격을 인상했어. 특정 시점 전에 주문하면 이전 가격을 적용해 주기로 했지. 그런데 막상 인보이스를 받으니 오른 가격으로 온 경우가 있어서 크레딧을 받은 적도 있어」
  「가격 쪽 크레딧은 물건을 특정해서 주는 게 아니라 **그 차액만큼 돌려받는** 경우가 많아」 ⇒ 수량 크레딧 = 제품·개수가 붙는다 / 가격 크레딧 = 금액만 온다 — 줄에 제품이 붙었나로 갈린다 · ⚠️ 실물 크레딧이 1건뿐이고 그것도 cancelled ⇒ 표본 없이 설계하지 않는다(⬜ §13-f)
⚠️ po_line_id null 인 goods 줄은 없다 — CHECK po_invoice_line_target_ck 가 goods 에 po_line 을 강제한다. 「po_line_id null 1건」은 charge 줄(운임 187)이다 ⇒ SKU 를 몰라 빠지는 goods 는 구조적으로 없다
⚠️ supplier_ref_number 는 크레딧 전용 칸(CHECK po_invoice_credit_only_ck)이라 뷰에 없다 — 인보이스의 공급처 번호는 invoice_number 자체다

실측 [2026-09-20 · 테스트 DB]
  AMP-778812  factor 0.8217(Trade 17% × Damage 1%) · 3.09 → 2.539053 · net_unit_cad 3.537536(환율 1.39325 · source invoice) · 운임 187 은 뷰에 없다(skipped · charge)
  5566        인보이스 환율 없음 → 발주 1.4 로 내려간다(source po) · 3.50 → 4.90
  CAD test    Laboratories Delon · is_base_currency t · 환산 없이 2.05
  거르기      확정 인보이스 17줄 = 뷰 16 + skipped 1(Freight - inland) ⭐ 합이 맞는다
  ⚠️ 1센트 — 라인 합 ≠ 문서 총액이 **정상**이다(끊는 횟수가 한 번이냐 세 줄이냐) · 2,446.80 × 0.8217 → 문서 2,010.54 · 라인 합 2,010.53 · 가격 이력은 단가를 보는 자리라 문제가 아니다
     ⚠️⚠️ 나중에 이 값을 **원가에 쓰게 되면** 그때는 레이어 배분 방식(6자리 · 끝수는 마지막 줄)을 따라 맞춘다
화면      po.html 붙여넣기 미리 보기 「Last paid」(asung-ims 161259f) — 같은 공급처 것만 · 지금 값과의 차이 ▲▼(방향만 · 판정하지 않는다) · 날짜·인보이스 번호·할인 문장 · 조회 실패가 미리 보기를 막지 않는다
⬜ latest·fixed 갱신을 IMS 가 맡는다 — 출처는 이 뷰(11-d 정정) · ⬜ supplier_discount 0행(§13-f) · ⬜ 아침 점검 한 줄 `select count(*) from po_price_history_skipped where reason <> 'charge'`(0 이 정상)
```
**⭐⭐ 크레딧 노트 (2026-09-16 오후 신설 · `20260916175003_po_credit.sql` · 커밋 `3be9a86`)** — ⚠️ 정본에 크레딧 설계가 **없었다**(위 「Credit note · Unstock 탭」 한 줄이 전부). 여기서 처음 선다.
```
실무      [Caleb 2026-09-16] PO 100 · 인보이스 100 · 실제 입고 90 — 공급처마다 다르지만 **특정 공급처는 거의 매번 그렇다.** 그때 supplier credit note 를 만들어 두고 있다.
          [Cin7] Purchases 목록을 「With a credit note」로 거르면 걸리는 건이 꽤 많다(Camille Rose · By Natures · Recho Ayumaah · Ebin New York · J.Strickland · Exod · Avlon · Taliah Waajid · BIP …)
실물      [Recho Ayumaah / PO-00832] Credit note 23537005816 · 2026-06-10 · RCO00162 54 × 6 = 324.00 · 「Credit note for」 23537005760
          Payments: 23537005760 = 7,822.66 · 23537005817 = 86.88 · 23537005816 = 324.00 → paid **7,585.54** ⇒ 크레딧이 갚을 돈을 **줄인다**
          📌 Credit note 옆에 Unstock 탭이 따로 있다 — 크레딧과 재고 빼기는 갈려 있다. 우리 경우(90개만 받음)는 뺄 재고가 없다
```
확정된 설계(Caleb 2026-09-16 · 검토 이견 1~11 전부 받음):
```
⭐ 별도 표가 아니다      po_invoice 에 doc_kind CHECK('invoice','credit') — 모양이 같다(번호·날짜·환율·줄) · 줄 구조가 같다 · 결제 충당이 같은 자리다 · 별도 표면 po_payment_alloc 대상이 셋이 되어 복잡해진다
⭐ 금액은 양수          공급처 문서에 찍힌 그대로(324.00). −324.00 이 들어 있으면 대조할 때마다 뒤집어 생각해야 한다. **부호는 계산(po_detail RPC)에서** 준다. ⚠️ ②차 주석의 「크레딧성 음수 인보이스가 올 수 있다(짐작)」는 이것으로 정정됐다
⭐ credit_for_invoice_id  nullable · self-FK — 「인보이스와 무관한 조정도 있다」(Caleb). 붙은 크레딧은 그 인보이스의 미지급을 **줄인다** · 안 붙은 크레딧은 **쓸 수 있는 크레딧**으로 남아 결제 때 po_payment_alloc 이 가리켜 「썼다」(11-h)
⭐ 줄은 po_invoice_line 그대로   크레딧 줄도 po_line 을 가리킨다(Caleb 「인보이스 줄과 같은 구조가 자연스럽다」) ⇒ 「시켰다 · 청구됐다 · 받았다 · 크레딧 받았다」가 한 줄로 이어진다. is_payable 의 뜻을 「결제 계산에 드는 줄」로 넓혔다(인보이스: 낼 돈 · 크레딧: 뺄 돈)
⭐ 할인 줄은 자동 복사 안 함  크레딧은 공급처가 보내오는 문서다 — 적힌 대로 넣는다. [실물] Cin7 크레딧 줄에도 DISCOUNT 0% 칸이 있다. 적혀 있으면 사람이 po_invoice_discount 에 넣는다
⭐ 유니크 셋            (supplier_id, doc_kind, invoice_number) — 공급처가 크레딧 메모를 다른 번호 체계로 내면 같은 숫자가 겹칠 수 있다(짐작 · 실물은 다른 번호). 막았을 때의 대가(못 넣는다)가 크다
⭐⭐ 제약의 자리         같은 행 안에서 걸 수 있는 것만 CHECK(크레딧만 credit_for 를 갖는다 · 자기 자신 금지). **다른 행을 봐야 하는 것은 트리거 대신 RPC warnings** — 크레딧이 크레딧을 가리킨다 · 다른 공급처를 가리킨다 · 붙어 있는데 alloc 으로도 썼다(두 번 깎인다) ⇒ credits[].warnings · 만들기 화면이 막는다(§5 거래 표 규약)
⬜ Unstock              「받고 나서 반품」(재고가 줄어야 한다)은 사건 차수(11-j)
```
[검증 실측 · Caleb 2026-09-16 · SQL] CN-AMP-778812-1 · AMP00415 10 × 3.09 = 30.90 · credit_for AMP-778812(이미 다 낸 인보이스)
⇒ invoices[0]: payable_net 2,010.54 · paid 2,010.54 · credit_total 30.90 · **unpaid −30.90** · credits[0]: credit_net 30.90 · diff 0.00 · used 0 · remaining null · warnings []
⭐ **음수 미지급은 받을 돈이다** — 공급처가 우리에게 빚졌다. 결함이 아니다. 화면은 「30.90 credit due」로 그린다(po.html `4ae86d6`).

**⭐⭐ 인보이스·크레딧을 만드는 법 (2026-09-16 저녁 · `20260916200000` · 커밋 `160430b` · 화면 `asung-ims/invoices.html` 신설)**
```
만드는 자리  [Caleb] PO 상세 「Create an invoice」 → 그 PO 의 라인이 채워진 초안 → **인보이스 전용 화면**(invoices.html)이 열린다 — 거기서 고치고 · 줄을 빼고 · 다른 PO 의 줄을 더한다(인보이스 하나가 발주 둘에 걸친다 · 위)
             ⚠️ 크레딧은 **PO 에서 만들지 않는다** — 인보이스 화면에서 만든다. 그 인보이스가 무엇을 얼마나 청구했는지 알아야 채울 수 있다(po.html 의 Kind 는 Invoice 하나 · asung-ims ccb58a1)
머리         공급처·통화·환율·결제조건은 **PO 에서**(그날 값 · 공급처를 다시 읽으면 「PO 만든 뒤 바뀐 마스터」가 섞인다) · due_date 는 사람이(34행 비어 있음 §10-k)
             크레딧 머리의 원천 셋: credit_for 인보이스 → p_po_id → p_supplier_id(조정 크레딧 · 줄 비움)
⭐⭐ 줄        **미청구 수량**으로 복사한다(po_uninvoiced_lines) — 주문 수량도 입고 수량도 아니다
             ① 입고 수량은 「인보이스가 대체로 먼저 온다」(11-i)라 0 인 경우가 많다  ② 주문 수량은 **둘째 인보이스에서 이중 청구**가 된다(한 PO 에 여러 장 — 실물 PO-01010 · §3-b ③)
             ⇒ 첫 장이면 주문 수량과 같고, 둘째 장이면 남은 것만 온다 · 단가는 po_line(공급처 실제 단가는 사람이) · 단위 칸 넷은 수량이 주문 수량과 같을 때만(일부면 entered_qty 가 틀린 값이 된다)
             ⭐⭐ [2026-09-17 · `20260917170000` 446행 · 커밋 0184260] **p_line_qty 로 줄마다 수량을 정할 수 있다** — 물건은 한 번에 오는데 공급처가 **인보이스만 여러 장으로 나눠 보내는** 실무(Caleb · 부분 입고가 아니다 · PO 는 안 갈라진다).
                그전에는 미청구 수량이 전 라인 채워져 나와 안 실린 품목을 만든 뒤 하나씩 지웠다(열 중 셋만 청구됐으면 일곱 번). 모양 { "<po_line_id>": qty_ea } · 인보이스만(크레딧에 주면 거부).
                0·null·키 없음 = 줄 없음(verdict 'skipped' 로 lines[] 에 담기만 한다 · skipped_count) · 미청구 초과는 **저장 전 거부**(§11-b 와 같은 이유 — 넘긴 음수 remaining 은 초과 입고의 음수와 사후 구별이 안 된다) · 남길 줄 없음(전부 0)도 거부 · 미리 보기도 같은 판정
                ⭐ **다음 장은 po_uninvoiced_lines 가 저절로 맞춘다**(그 함수는 무변) — 첫 장에 6 만 넣으면 둘째 장에 6 이 돌아오고, 안 넣은 품목은 주문 수량 그대로 나온다
                [실측 2026-09-17 · Caleb · PO-02007 13라인 전량 12] 라인 1·2 를 12, 라인 3 을 6 으로 넣고 확정 → 둘째 미리 보기: 1·2 fully_invoiced · 3 은 remaining 6 · 4~13 은 12 그대로
                ⚠️ 인자가 늘어 시그니처가 바뀌었다 — create or replace 로는 옛 판이 남아 둘이 된다 ⇒ **drop 뒤 create**(레포 첫 사례 · §5 규약) · 새 인자는 맨 뒤(살아 있는 호출은 전부 이름 인자)
⭐ 크레딧 자동 채우기   credit_for 를 주면 **그 인보이스의 goods 줄 − 그 po_line 의 입고 합**(> 0 만) · 단가는 인보이스 줄 · 단위 EA
             [Caleb] 「화면이 물어보고 누르면 그 차이만큼 줄이 채워진 초안 — 만드는 것은 사람 · 숫자를 손으로 옮기지 않는다」(특정 공급처는 거의 매번)
             ⚠️ 차이가 하나도 없어도 **빈 크레딧을 만들 수 있다**(warnings no_qty_difference) — 수량이 아니라 **단가**를 깎아 주는 크레딧이 있다. 거부하면 그 실물을 못 넣는다
             ⚠️ 전제: 그 라인의 청구가 이 인보이스 한 장(문서 분할 덕에 대체로 참 · 11-e) · 다른 인보이스도 가리키면 줄에 line_has_other_invoices 경고
⭐ 총액        p_total_amount 를 안 주면 **0 으로 넣고 경고**한다(total_amount_missing) — 계산값으로 채우지 않는다. 계산값을 넣으면 diff 가 0 이 되어 **대조값의 뜻이 사라진다**(찍힌 값이 없는데 맞는 것처럼 보인다). 0 이면 diff = −계산값이 크게 보인다
⭐ 미리 보기   p_commit=false(po_lines_paste 선례) — 만들기도 · PO 줄 더하기(po_invoice_add_po_lines)도 두 단계(Check → Create/Add · 화면 ccb58a1) · 번호 중복은 미리 보기 경고 · commit 거부
줄 편집      po_invoice_line_add(다른 PO 의 라인 하나 · charge/other 는 description 필수 · is_payable) · _update(patch) · _delete — **draft 만**
⭐⭐ 확정의 뜻  **「공급처 문서를 우리 장부에 받아들였다」**(po_invoice_confirm) — 금액·수량이 문서와 대조됐고 이제 미지급이 생기고 할인이 원가로 내려간다(원가 배분 자체는 원장 차수 11-j). draft = 입력 중
             ⚠️ 발주의 Confirm(「보낼 수량·라인이 정해졌다」 · 11-b)과 **다르다.** 발주는 장부가 아니다
             ⇒ 확정 뒤에는 줄·할인을 못 고친다(RPC 가 거부) — 이미 내려간 원가와 생긴 미지급이 소리 없이 바뀐다 · 되돌리기(Reopen · p_confirm=false)는 **결제 충당이 붙어 있으면 거부**
             확정 전 검사: 줄 0개 → 거부 · 크레딧이 인보이스 아닌 것/다른 공급처를 가리킴 → 거부 · total_amount 0 → 경고(샘플 인보이스 실물) · diff ≠ 0 → **경고만**(정본은 찍힌 값 · Cin7 도 안 막는다)
             ⚠️ 예외 하나: `supplier_ref_number`(11-c 크레딧 번호)는 확정 뒤에도 넣는다 — 참조가 나중에 오는 것이 정상 흐름이고 장부를 안 건드린다
목록·상세    뷰 po_invoice_list(PO 없는 조정 크레딧이 보이는 유일한 자리) · RPC po_invoice_detail(한 장을 깊게 · 줄마다 발주 대조값과 qty_diff — 「크레딧을 만드시겠습니까」의 근거) · 돈은 po_invoice_money(§13-g)
```
→ **화면 셋(2026-09-17 · asung-ims)** ⭐ **PO 에서 크레딧으로 가는 길** — po.html 의 인보이스 줄에 「+ credit」(확정된 인보이스에만) → `invoices.html?id=…&credit=1`. ⚠️ **만드는 자리는 옮기지 않았다** — 크레딧 초안이 「청구 − 입고」 차이로 채워지려면 기준 인보이스가 정해져야 한다(§13-h · 크레딧은 PO 에서 만들지 않는다 그대로).
⭐ **PO 에 없는 제품이 인보이스에 있으면 인보이스에만 둔다**(Caleb 2026-09-17) — `po_line_id` nullable 이 그 자리다. PO 에 끼워 넣으면 「우리가 시켰다」는 거짓이 장부에 남고 확정이 드러내는 차이(②)가 사라진다. 그 제품이 실제로 입고되면 「PO 라인 없이 받는 길 · 약식 제품 등록」이 필요하다 — 입고 차수(§13-f).
⭐ 문서 사이 이동 — po.html 상세에서 인보이스·크레딧·비용·결제 번호를 눌러 그 문서로, 거꾸로 각 문서에서 발주 번호로(4a87a6c · 55ffd15 · b3e5c89 Pay 링크 — 커밋 제목으로 확인 · 화면 세부는 짐작). 문서 하나를 짚어 따라가는 길이 이것이고, 옆 목록으로 건너뛰는 길은 구매 탭(§10-j 3-k)이다.

### 11-h. ⭐ 결제 — IMS 가 든다
```
⭐ Caleb: 「결제는 IMS 에서 하는 게 맞지 않나」 ⇒ 그렇다. 근거 둘:
   ① 인보이스가 IMS 에 있는데 결제만 밖에 있으면 **냈는지 안 냈는지를 IMS 가 모른다** — 「아직 안 낸 것」 목록이 안 나온다
   ② 조기결제 할인은 결제 시점에 생긴다. 결제를 모르면 그 할인도 모른다
⚠️ **구별선은 유지된다** — IMS 가 드는 것은 「무엇을 언제 얼마 냈다」는 **사실**이다.
   그 돈이 어느 계정으로 어떻게 분개되는지는 **QBO 의 일**이다(§3-b 구별선).
   ⇒ QBO 연동의 이음새가 **여기**다(로드맵 「재고 원장 → PO+원가 → SO → QBO」 · `ims-principles.md` §1-a).
      ⚠️ [검토 Claude 정정] 지시서의 「정본이 『PO 모듈부터 병행 트랙』이라 했다」는 문구는 이 문서·상위 문서 어디에도 없다(grep) — 인용으로 적지 않는다.
⬜ 조기결제 할인의 HST 매입세액 처리는 **회계사 확인**(§3-b ② 미결 — 우리가 판단할 사안이 아니다).
   [실물 E.T Browne INV 2142773] 실제로 덜 낸 돈 226.81 인데 Cin7 장부는 256.30 을 깎았다.
   ⇒ 금액과 할인액을 기록해 두면 회계사가 정한 뒤에 얹을 수 있다.
⬜ KRW 송금의 환차손익(§7)도 결제가 IMS 에 서면 여기서 다시 올라온다. → [2026-09-16] `po_payment.currency_id · exchange_rate · amount` 칸만 두었다 — **계산은 QBO 때**(§7 Caleb 판정). 칸이 없으면 그때 소급이 안 된다. ⬜ 유지.
```
→ **표(2026-09-16 · §13)** `po_payment`(사실) · `po_payment_alloc`(어느 청구서에 얼마).
```
가리키는 것    ⭐ po_payment_alloc 은 **po_invoice 또는 po_charge 정확히 하나**(CHECK) — 비용 청구서(CBSA 관세 · BBE 통관)도 **돈을 낸다**([실측 · Caleb] Cin7 Purchases 목록에서 Payment status 가 Paid)
               ⭐ [2026-09-16 ③차] po_invoice 가 **크레딧**(doc_kind=credit)이면 뜻이 뒤집힌다 — 갚은 게 아니라 **「이 결제에서 이 크레딧을 썼다」**(amount 는 양수 그대로 · 부호는 RPC). 안 붙은 크레딧만 이 길 · 붙은 크레딧은 인보이스에서 직접 빼므로 여기 오면 두 번 깎인다(warnings attached_and_used)
               검산: Σ인보이스 + Σ비용 = amount + discount_taken + Σ크레딧 (화면) · 인보이스 미지급 = payable 줄 합 − 충당 − 붙은 크레딧(credit_total) · 음수면 받을 돈
               📌 처음 「결제는 인보이스 여럿을 가리킨다」로 정할 때 비용 문서를 빼놓은 것은 **설계 대화의 누락** — 검토(Claude Code)가 잡았다
               실무의 「PO(입고된 쉽먼트) 단위로 묶어 낸다」(Caleb 실측)는 화면이 돕는다 — 저장은 청구서별 충당 금액. 근거: 갚을 돈을 만든 것은 인보이스 · PO 를 가리키면 어느 인보이스가 결제됐는지 모른다 · 인보이스 하나가 PO 둘에 걸친다
discount_taken ⭐ 조기결제로 덜 낸 금액 — 계산(충당 합 − 낸 돈)만으로는 **덜 낸 것과 할인 받은 것이 구별되지 않는다**([실물] 부분 결제 Avlon 「50% COD & 50% Net30」 §7). 사람이 「이 200 은 할인이다」를 선언해야 문서가 닫힌다
               검산: 충당 합 = 낸 돈 + discount_taken. [실측 · Caleb 2026-09-16 · SQL] WIRE USD 2,010.54 → AMP-778812 · EFT CAD 2,496.42 + 할인 50.95(2%) → CBSA 2,547.37 — 둘 다 0.00
상태 없음      결제는 사실이다 — 잘못 넣었으면 지운다(DELETE 열림) · 상쇄 규칙은 QBO 이음새 때
결제 계정      ⭐⭐ [Caleb 실측 2026-09-16] Cin7 의 결제는 **은행과 직접 연결되어 있지 않다.** IMS 도 은행 연동이 필요 없다.
               흐름: QBO 가 계정과목을 만든다 → Cin7 으로 내려온다 → 결제할 때 그중 하나를 **지정만** 한다 → fund 매칭은 QBO 가 한다 ⇒ 위 「IMS 는 사실만 · 분개는 QBO」와 정확히 맞는다
               📌 Cin7 Omni 시절에는 e-transfer/카드/현금/수표 구분만 했고 전부 QBO 에서 처리했다
               ⚠️⚠️ `ref_account.for_payments` 를 결제 계좌 필터로 쓰지 마라 — [실측 · Caleb] 289행 중 true 23행 · 그중 7개가 카드이고 나머지는 **is_active=false 인 Cin7 기본 계정**
                  (Suspense · Gift Card · Petty Cash · Cash Float · Cash in/out — 지금 쓰지 않는 것들) · 정작 실제 은행 계좌 셋(`_104_` TD CAD CHEQUING · `_105_` BMO CAD CHEQUING · `_106_` BMO USD CHEQUING)은 거기 **없다**
               ⇒ `account_id` → ref_account(id) · nullable · 화면이 목록을 보여 주고 사람이 고른다 · ⬜ 후보를 좁히는 규칙은 실제로 쓰는 계정이 드러나면(화면 차수 이후)
```
미지급(계산): 인보이스 = payable 줄 합(할인 적용 후) − 충당 합 · 비용 = total_amount − 충당 합. [실측 · Caleb 2026-09-16] AMP-778812 0 · CBSA 0.
→ **쓰기(2026-09-17 · `20260917190000` 880행 · 커밋 db36acd · 화면 `payments.html` 신설 · 검토 이견 1~14 전부 받음)**
```
⭐ 통화를 정하는 것은 **공급처**다   [Caleb 실측] Cin7 에서 공급처마다 통화가 정해져 있고 우리는 그것을 지킨다 — 공급처 기본 통화가 USD 면 USD 로 낸다
             ⚠️ KRW 송금은 결제 단계의 문제가 아니다 — **그런 공급처는 인보이스를 CAD 로 환산해 만든다**(Caleb). 시스템이 보는 것은 CAD 문서를 CAD 로 갚는 것뿐 ⇒ exchange_rate 칸은 두되 이번에 쓰지 않는다(insert 안 함)
⭐⭐ 한 결제 = 한 통화   대상 문서 전부의 통화 = 결제 통화 — **뒷단이 검사**한다(공급처로 좁혀도 · 손으로 만든 문서가 다를 수 있고 anon key 가 공개다). 거부 문장에 문서 번호와 통화를 이름으로(「Charge FX-TEST-1 is CAD but the payment is USD — one payment, one currency …」)
             실무에서 섞이는 자리는 **운송** — 제품 인보이스는 CAD 인데 운송 비용 문서가 USD 로 올 수 있다 · [실물] PO-02001a 하나에 결제가 둘(WIRE USD → 인보이스 · EFT CAD → 관세)
⭐ 확정된 문서에만 붙는다   인보이스·비용 status='confirmed' 만 — 확정 = 「장부에 받아들였다」이고 그때 미지급이 생긴다(§11-g). ⚠️ po_invoice_money.unpaid 는 status 를 안 봐 **초안에도 미지급이 계산된다** — 막지 않으면 초안에 결제가 붙는다 · cancelled 도 거부
⭐ 부분 결제는 정상   [실물] Avlon 50% COD & 50% Net30 · 막는 둘: **문서 미지급 초과** · **Σ충당 ≠ amount + discount_taken**(표 주석의 검산 · 저장 전 거부 · gap 을 문장에). 비용 배분(unallocated)과 성격이 같다 — 양쪽 다 우리 숫자
⭐ discount_taken 은 사람이 선언   계산(충당 합 − 낸 돈)만으로는 「덜 낸 것」과 「할인 받은 것」이 구별되지 않는다 · [실측 2026-09-17] 5566 USD 586.92 중 286.92 를 낼 때 250 + 할인 36.92 로 선언하면 통과 · HST 매입세액은 회계사 미결(금액만 기록)
⭐ 한 결제 = 한 공급처는 **강제하지 않는다**   경고 mixed_supplier 만(검토 이견 1 ⓑ · Caleb) — 비용 문서의 공급처는 경비처(CBSA·BBE)라 「Ampro 인보이스 + CBSA 관세를 한 송금」 실무가 있는지 모른다(짐작). 강제하면 그 실물을 못 넣고 실제 위험(통화 섞임)은 통화 검사가 잡는다 · po_payment 에 공급처 칸은 없다(p_supplier_id 는 화면의 축 · 선택)
⭐ 상태 없음   결제는 사실이다 — 잘못 넣었으면 **지운다**(po_doc_delete 'payment' · confirmed_at 검사 없음 · 충당 CASCADE · allocs_deleted · 그 문서들의 미지급이 되살아난다) · po_doc_cancel 'payment' 는 **거부**(「A payment has no cancelled state — delete it instead」 · 조용히 통과시키지 않는다)
⭐ 결제 계좌 — ❌ **ref_account 를 고치지 않았다**   ⚠️ 계좌에 통화 칸을 붙이자는 안이 한 번 섰다가 [Caleb] 「통화는 공급처에서 이미 정해져 내려온다. 계좌에 또 적으면 같은 사실이 두 곳에 있고 언젠가 어긋난다」로 기각됐다
             ⇒ account_id nullable · 통화 검사 없음 · 안 고르면 경고 account_missing 만 · 화면이 **검색으로** 고른다(코드·이름 · 「CHEQUING」) · for_payments 를 후보 필터로 쓰지 않는 이유는 위 문장 그대로 · 계좌 코드 하드코딩 없음
             ⚠️ [Caleb 실측 2026-09-17] 카드·Wise 도 쓰지만 **결국 모든 돈은 세 계좌(_104_ TD CAD · _105_ BMO CAD · _106_ BMO USD)에서 나간다** ⇒ 계좌는 셋만 · 수단은 reference 에 적는다(카드 대금 정산은 분개 영역 — QBO 의 일)
❌ 크레딧을 결제에 쓰는 길은 이번에 없다   위 「안 붙은 크레딧만 이 길」이 190000 의 p_targets(kind invoice | charge)에 빠졌다 — 지시서의 누락(대화 Claude). 검산 부호가 뒤집혀(Σ인보이스 + Σ비용 = amount + discount_taken + Σ크레딧) 섞을 수 없어 **거부**한다(「… is a credit note — a later step」) · 조용히 통과시키지 않는다 · §13-f
검사 한 곳   po_payment_target_check(존재 · 종류 · confirmed · 통화 · 초과 — 고치는 줄의 금액은 미지급에 되돌려 놓고) — 만들기(po_payment_create · 미리 보기 두 단계 · amount 없으면 미지급 전액 제안)와 충당 편집(po_payment_alloc_set 은 있으면 고치고 없으면 더한다 · unique (payment, invoice)·(payment, charge) 가 축 · _delete)이 같이 쓴다
읽기          뷰 po_payment_list(alloc_sum · balanced = Σ충당 = amount + discount · doc_numbers · supplier_names · 충당 없는 결제도 보인다) · RPC po_payment_detail(allocs[] 에 doc_total · doc_paid_total · doc_unpaid — 부분 결제가 정상이라 「지금 얼마 남았나」를 보고 정한다)
머리 칸        paid_on · amount · discount_taken · account_id · reference · note 는 화면이 PostgREST 로 쓴다 — 결제는 상태가 없어 잠금 지점이 없다. gap 은 목록 balanced · 상세가 보여 준다 · ⚠️ currency_id 는 충당이 있으면 **화면이 잠근다**(대화 Claude)
```

### 11-i. ⭐⭐ 입고
```
⭐ **인보이스를 기다리지 않는다.** Cin7 의 Invoice First 선승인 제약은 **Cin7 의 사정**이다.
   (WMS 규칙 20 의 유입 필터가 지금 그 제약에 맞춰져 있다 — `receiving` EF `PO_INVOICE_OK` = AUTHORISED/PAID 만 통과 · 코드 실측)
   우리 유입 조건: **확정됐고 아직 다 안 받은 PO.** 그게 전부다.
   ⚠️⚠️ 다만 **실무는 대부분 인보이스가 먼저 온다**(Caleb) — 제약을 없애는 것이 중요한 게 아니라,
      드물게 물건이 먼저 와도 **창고가 멈추지 않게 열어 두는 것**이 중요하다. [대화 Claude 의 강조점이 처음엔 어긋나 있었다]

⭐ **풋어웨이까지 한다**(Caleb) — 빈이 정해진 뒤 입고가 확정된다. §7 「제품의 기본 자리(bin) — ⑤ 리시빙·풋어웨이에서 만든다」가 여기서 발동한다.

⭐ 초과·부족은 **지금 WMS 방식 그대로**(Caleb: 「wms 에서 하는 방식과 같아」 · 「초과로 온 것은 지금 방식으로」 — `asung-wms` 규칙 20 「차이(불일치) 처리 정책」)
```
```
부족      들어온 대로 재고가 는다 + 남은 수량으로 **다음 문서가 자동으로 갈라진다**(11-c)
초과      ⚠️ **기준 수량까지만 재고가 는다.** 넘은 만큼은 재고로 안 들어가고 **차이로만 남는다**
          ⇒ 물건은 창고에 있는데 장부에는 없다. 사람이 보고 메운다
          ⚠️ 기준이 **인보이스 → PO 확정 수량**으로 바뀐다(인보이스를 안 기다리므로). 나머지 논리는 같다
          근거(WMS 규칙 20 · 2026-08-12 반전): 「인보이스에 없는 물건 = 공급사 정산이 안 된 것, 자동 투입 금지」
PO 밖     PO 에 없는 물건이 나오면 **매니저 승인 전까지 막는다**(승인 전 풋어웨이·반영 차단 — WMS 의 needs_approval 과 같은 모양)
차이 큐    전부 큐에 쌓인다 · ⭐ **자동 조정은 하지 않는다 — 사람 판단 유지**(WMS 에서 확립된 정책)
⭐ 보정 경로가 짧아진다 — 지금은 매니저가 **Cin7 에 가서** 손으로 고친다. IMS 에 재고조정 모듈이 서면 그 왕복이 사라진다.
```
→ **표(2026-09-16 · §13)** ⭐⭐ `po_receipt_line` 이 **따로 선다** — 어느 라인을 · 언제(received_on = 원장 occurred_on) · 누가(→ ims_staff.id) · 어느 빈에(→ ref_bin.id · 창고는 bin 에서 따라온다) · 몇 개. 한 라인이 **여러 빈**으로 나뉜다([Caleb 실측] 「가능하면 한 SKU 는 한 빈에」지만 부득이한 경우가 있다 · [실측 SQL] 600개를 A010101 400 · A010102 200 으로 나눠 넣었다). ~~입고 줄 하나로 설계했다~~ → ⭐⭐ [2026-09-18] **표 셋 · 두 단계**(아래 「→ 표 셋」) — 이 문단의 po_receipt_line 은 그중 「확정된 사실」이다.
⚠️ `po_line` 에 received_qty 를 **두지 않는다** — 두 곳에 적히면 어긋난다. 입고 줄 합으로 낸다([실측 · Caleb] 합으로 냈는데 문제없다). ⭐ 입고 줄 하나 = 원장 사건 하나(11-j).
⚠️⚠️ **초과분은 입고 줄에 그대로 적히되 사건은 PO 확정 수량까지만** ⇒ **원장 합 ≠ 입고 줄 합.** 설계대로다 — 대조하다 버그로 오해하지 마라. 차이 = 입고 줄 합 − qty_ea 로 계산. ~~⬜ 차이 큐 표는 재고조정 모듈 때(WMS `wms_discrepancies` 선례 · 받을 곳이 서면).~~ → ✅ [2026-09-18] **차이 큐는 리시빙에 섰다**(po_receipt_diff · 아래) — 「받을 곳」이 재고조정이 아니라 **확정하는 순간**이었다(Caleb · short 를 담는 이유 아래).

→ **표 셋 · 두 단계 · RPC 열(2026-09-18 · `20260918161537`·`163552`·`173042`·`174428`·`203805` · 커밋 f288ee8 → 0f50a7e · §13-i)**
```
⭐ 두 단계 관행   [Caleb] ① 검수(인보이스대로 왔는지 센다 · **빈을 모른다**) → ② 풋어웨이(자리에 갖다 놓는다) — 사람도 시점도 다르다 · WMS 도 Cin7 도 같다
                ⇒ po_receipt_line 하나로는 못 담는다(bin_id NOT NULL 이라 ①단계의 줄이 들어갈 자리가 없다)
⭐ 표 셋         po_receipt        묶음 — 어느 PO(갈라진 뒤의 문서) · 받는 창고 · 받은 날(received_on = 원장 occurred_on 의 근거) · RCV-00001 번호(시퀀스) · draft|confirmed|cancelled · created/confirmed/cancelled_by
                po_receipt_work   작업 줄 — 라인별 센 수량(낱개 · >0) · bin_id 는 나중(nullable) · putaway_done · count_method(scanned|manual) · ⭐ 축 칸 넷 counted_by/at · putaway_by/at(WMS 축 분리 승계 — Place all 이 「누가 세었나」를 덮지 못하게) · unique (receipt_id, po_line_id, bin_id)
                po_receipt_line   확정된 사실(이미 있었다) — receipt_id 를 더했다(⚠️ nullable · 09-16 검증 데이터가 묶음 없이 있다 · ⬜ 백필 뒤 not null §13-f) · 쓰는 길은 **확정 RPC 하나**(관례 · 정책은 열려 있다)
                po_receipt_diff   차이 큐 — 아래
⭐ 한 줄 = 한 빈   나누려면 **줄을 쪼갠다**(po_receipt_work_split · 쪼개기는 풋어웨이의 일 · ⭐ 새 줄에 빈을 함께 받는다 — 빈 없이 쪼갤 이유가 없고 빈 없는 줄이 둘 생기는 길이 막힌다) · 확정이 1:1 이 된다(작업 줄 하나 → 입고 줄 하나 · bin·qty 그대로 복사)
⭐ 빈 없는 줄     = 그 라인의 **「미배정 나머지」**(센 총량 − 빈 붙은 줄들의 합) · 라인당 하나 · 0 이면 없다 · 세는 함수(work_save)는 라인의 **낱개 총량**을 받아 그 줄만 만들고 고친다(총량 < 배정 합이면 거부 — 빈 줄을 먼저 줄여라 · 자동으로 깎지 않는다)
                ⚠️ 부분 유니크 금지(규칙 29)라 DB 는 (receipt_id, po_line_id, bin_id) 만 건다(null 은 서로 다르다) — 「하나」는 RPC 가 지킨다 · 「PO 당 열린(draft) 입고 하나」도 만들기 RPC 가 막는다(문장에 그 번호 「already has an open receipt (RCV-00003)」)
⭐ 병합          같은 라인·같은 빈을 만나면 **합친다** — 예외가 아니다 · split · putaway · unassign 셋이 같은 태도(합쳐진 줄의 putaway_by/at 은 덮인다 — 줄은 상태 행이고 사건 기록이 아니다)
⭐ 합 불변        라인 총량 = 줄들의 합 · 쪼개기·병합·되돌리기는 합을 안 바꾼다 · unassign 은 쓰기 **전후로 실제로 잰다**(다르면 전부 되돌린다) · 되돌리기 = 빈을 지우고 미배정으로(이미 빈 없는 줄이 있으면 거기에 합친다 · [Caleb] 「되돌린다면서 빈이 남아 있으면 되돌린 게 아니다」)
⭐ 놓인 것        이 화면(사무 화면)은 **빈을 고르는 순간 놓인 것**(putaway_done = true · split 도 같은 길 `174428`) — 「자리를 정했다」와 「갖다 놨다」가 갈릴 이유가 없다 · p_done=false 가지(putaway · putaway_all)는 나중 WMS 창고 화면 몫 · 그 가지가 이제 「빈은 있는데 안 놓인 줄」을 만드는 유일한 길
⭐ 기준 하나      **PO 확정 수량**(po_line.qty_ea − 이전에 확정된 입고 합 = remaining) · 확정된 인보이스 goods 합은 **표시만 · 아무것도 결정하지 않는다**(detail.lines[].invoiced)
                ⚠️ WMS 는 2026-08-05 에 기준을 인보이스로 바꿨었다(가짜 차이 때문 · 규칙 20) — IMS 는 PO 기준으로 돌아오되 인보이스를 나란히 보여 사람이 이유를 읽게 한다
⭐⭐ 확정 게이트   **빈 없는 줄이 하나라도 있으면 거부**(Caleb · po_receipt_line.bin_id NOT NULL · 「빈이 정해진 뒤 입고가 확정된다」) · 거부 문장이 **빠져나갈 길을 함께** 말한다 — 「… still have no bin: line 3 (SKU) 5 EA. Put them away first, or lower the count to what you actually placed — the rest stays on the order — nothing was saved」
                그 밖에 막는 것 다섯: 이미 확정·취소 · PO 가 confirmed 아님(잠금 뒤 다시 본다 — 그 사이 닫혔을 수 있다) · 작업 줄 없음 · 빈이 그 사이 비활성·다른 창고 · 남이 사이에 확정
⭐ 확정이 하는 일  ⓐ 작업 줄 → po_receipt_line 1:1(received_on 은 묶음의 것 · ⭐ **received_by = 놓은 사람 → 없으면 센 사람 → 없으면 확정한 사람** · 확정한 사람은 po_receipt.confirmed_by · **초과분도 입고 줄에 그대로** · 줄을 깎지 않는다)
                ⓑ 차이 큐(기준은 갈라지기 **전** 문서의 수량 — 그래서 ⓒ 앞) ⓒ 자동 분할 또는 닫기(11-c) ⓓ 묶음 confirmed(맨 뒤 — 어디서 터져도 아무것도 안 남는다) · 잠금은 PO(base)+라인 둘
                ~~⚠️⚠️ **사건은 안 나간다 · 훅도 없다**~~ → ✅ [2026-09-19] **ⓔ 창구 inv_post_receipt 가 같은 트랜잭션으로 사건을 낸다**(11-j · 훅이 아니라 함수 호출 · 원장이 po_receipt_line·po_receipt_diff 를 읽는다) · 초과는 발주 라인을 늘리지 않는다(원장이 기준까지 자른다 · 차이 큐 over 가 그 근거)
⭐ 차이 큐        po_receipt_diff — kind **over · short · off_po** · expected_qty(기준) · received_qty · resolved_by/at · unique (receipt_id, po_line_id) · 열린 것 = resolved_at is null(뷰 po_receipt_diff_list · 부분 인덱스 없음)
                ⭐ short 를 담는 이유(Caleb) — **분할은 남은 수량을 옮길 뿐 「왜 덜 왔나」를 아무도 안 본다.** 넷이 섞여 있고 분할은 구별하지 못한다: 공급사가 나눠 보냈다(다음 배에 온다) · 결품(PO 를 닫아야 한다) · 운송 중 분실·파손(크레딧) · 우리가 잘못 셌다(다시 세야 한다)
                ⚠️ 안 센 라인도 short 다(received 0) · 만드는 시점은 확정하는 순간 · 그 뒤 b 문서에서 더 받아도 앞의 건은 그대로 남는다 · **자동으로 닫지 않는다**(사람 판단 유지) · ~~⚠️ 닫는 길(RPC·화면·여러 건 한 번에)은 아직 없다(§13-f)~~ → ✅ [2026-09-19 `20260919175712`] 닫는 길이 섰다(아래 「→ 차이 닫기」 · 여러 건 한 번에는 ⬜) · 부분 입고가 흔하면 매번 쌓인다 — 처방은 「닫기 쉽게」
                ⚠️ off_po 는 CHECK 어휘에만 있다((kind='off_po') = (po_line_id is null) 로 뜻을 같은 행 안에 못 박았다) — po_receipt_work.po_line_id 가 NOT NULL 이라 아직 날 수 없다(PO 밖 줄은 §13-f · 「관행을 버린 것이 아니라 미룬 것」)
→ 차이 닫기      ⭐ [2026-09-19 `20260919175712` · 9a5344a] `po_receipt_diff_resolve(diff, resolution, note)` · `po_receipt_diff_reopen(diff, note)` · 칸 resolution · resolution_note
                ⭐ 이유 어휘 다섯 — split_shipment(나눠 왔다) · out_of_stock(공급사 결품) · lost_damaged(운송 중 분실·파손) · miscount(우리가 잘못 셌다) · other(⚠️ **메모 필수** — 셀 뜻이 없는 「그 밖」을 막는다)
                ⭐ 왜 어휘인가 — 자유 메모는 셀 수 없다. 「이 공급처가 몇 번 결품했나」를 물으려면 어휘여야 한다(위 「short 를 담는 이유」의 완결)
                ~~⭐⭐ short 만 닫는다. over 는 별도 차수~~ → ✅ **[2026-09-20 `20260920171930` · f413fe3] over 는 형제 함수 `po_receipt_diff_settle_over(diff, reason, note)` 가 닫는다 — 초과 입고를 재고에 넣는다.** `_resolve` 와 `_settle_over` 는 서로를 가리킨다(short 에 over 함수를 부르면 _resolve 를, 반대면 새 함수를 문장으로).
                ⭐ [Caleb · 실무 셋 · 말 그대로] ① 잘못 더 보냈고 공급처는 리턴보다 **샘플로 쓰라고 공짜로 준다**(⭐ 가장 많다) ② 인보이스를 추가로 보낸다 ③ 다음 오더에서 수량을 깐다 · 「돌려보내는 일은 거의 없어」 ⇒ ⚠️ **returned 는 만들지 않았다**(쓰지 않을 갈래도 유지해야 할 코드다 · 생기면 그때)
                ⭐ 이유 셋 · 원가는 둘 — **free** → 원가 0 · `cost_source 'free'`(⚠️ `unknown` 과 섞지 마라 — 모르는 0 과 진짜 0) / **billed** · **credited** → 기준 레이어의 unit_cost 그대로(같은 배 · 같은 값 · 기록만 다르다 — 합치면 「그때 깎기로 했다」가 사라진다)
                ⚠️⚠️ 왜 free 는 0 인가 — 낸 돈이 없다. 발주 단가로 넣으면 재고 자산이 공중에서 생긴다(실물 3개 × 11.606 = 34.82). 0 이면 낸 돈과 자산이 같다. FIFO 로 그 3개가 팔릴 때 이익이 크게 잡히는데 **그것이 사실이다.** ⚠️ 「총액을 15 로 나눈다」(99.48÷15)는 **기각** — 이미 선 12개의 단가가 흔들리고, landed 가 얹혔거나 팔렸으면 되돌릴 수 없어 append-only 와 부딪힌다
                ⭐ 왜 그 발주의 단가인가 — Cin7 은 재고조정으로 넣어 **창고 평균원가**가 붙는다(같은 배 물건인데 값이 달라진다). IMS 는 어느 발주에서 왔는지 안다 ⇒ 같은 값. **이것이 나아지는 부분이다**(Caleb). ⭐ 값은 기준 레이어에서 **읽는다** — 다시 계산하지 않는다(환율 곱하기 식은 `inv_layer_post_receipt` 한 곳에만 산다)
                ⭐ 구조 — 창구 둘 `inv_post_receipt_over(diff)`(원장 · 빈 별 초과분 = po_receipt_line 센 것 − 그 빈의 기준 행 · 합 ≠ gap 이면 거부) → `inv_layer_post_receipt_over(diff)`(레이어 하나). ⚠️ 기존 창구는 입고 단위로 「기준까지만」을 스스로 자른다 — 그대로 못 쓴다. ⚠️⚠️ 원장 **line_ref = `po_line_id:over`** — 유니크 7키(doc_type, doc_number, line_ref, event_type, warehouse, bin, sku)에 seq_hint 가 없어 그대로 쓰면 같은 빈의 기준 행(12)과 충돌한다(`:reversal` 선례 · 레이어 4키도 갈라진다) · doc_number RCV 그대로 · occurred_on = 입고일 · raw.kind `po_over` · raw.diff_id
                ⚠️ 빈은 건드리지 않는다 — 풋어웨이에서 이미 다 놓았다. **장부만 올린다.** · ⚠️ **reopen 은 over 를 거부한다**(재고가 움직였다 · append-only · 상쇄 사건 길은 ⬜) · CHECK `po_receipt_diff_resolution_kind_ck` 가 short 어휘로 over 를(또는 반대로) 닫는 것을 같은 행 안에서 막는다
                ⭐ 재생성 — `inv_layer_apply` 가 `:over` 행을 만나면 `inv_layer_post_receipt_over` 를 diff 단위로 부른다(기준 레이어 뒤 · 같은 날·더 큰 id) · `inv_layer_post_receipt` 는 `:over` 를 접지 않는다 · 반환 `ims.over_posted/over_layers/over_skipped`
                ⭐ 실측 [RCV-00026 · PO-02025 · AMP41103 · 실제로 닫았다 · 2026-09-20 17:46 토론토] over 3 · free · 원장 `…po_line_id` 12 + `…:over` 3(같은 빈 F0311PALLET02 · source ims) · 레이어 12·11.606·po_line / 3·0·free · ⭐ 전량 재생성 뒤에도 같다(over_posted 1 · over_layers 1) · billed 로 닫으면 3·11.606(= 8.29 × 1.40 · ⚠️ 나누면 5.92) · 되돌리기·두 번 닫기·short 에 부르기·어휘 밖·권한 없음 전부 문장으로 거부
                ⬜ billed 초과분에 landed 를 얹나 — `inv_layer_post_charge` 가 `:over` 레이어를 못 본다(`pl.id::text = x.line_ref` 조인). free 는 안 얹는 것이 맞고 billed 는 논의 여지 · ⬜ over 되돌리기 = 상쇄 사건 길
                ⭐ 「닫혔다」의 축은 **resolved_at** 하나 · resolution·resolved_by 와 **CHECK 로 묶었다**(po_receipt_diff_resolved_ck) — ⚠️ 반쪽만 채운 행을 DB 가 거부한다 · 목록의 칩(open_diffs)이 거짓말할 길을 막았다
                ⭐ reopen 은 세 칸을 비우되 **메모에 흔적을 남긴다**(「reopened: … | was: split_shipment」) · 닫힌 것을 또 닫으면 거부(누가·무엇으로·언제 + reopen 안내) · 닫을 때 형제 합계(11-c)가 함께 나온다
⭐ Last bin       **ims_last_bin(uuid[], uuid) → jsonb 하나 뒤에** 있다 — ~~지금 속은 po_receipt_line(received_on desc, created_at desc)~~ → ⭐ **[2026-09-19 `20260919151601`] 속 = 원장(ims_inv_balance)**: 1순위 지금 재고가 있는 자리(qty>0 · 마지막 사건 최근순) → 2순위 마지막으로 있던 자리(qty≤0 · 사건 있음) · 동률이면 수량 큰 것 → 빈 이름(결정적이어야 한다 — 두 번 불러 다른 답이 안 나오게) · **부르는 쪽(화면·RPC)은 안 고친다**
                ⭐⭐ **화면은 한 줄도 안 고쳤다**(시그니처 · 반환 키 넷 bin_id·bin·zone·received_on 무변) — 「함수 하나 뒤에 감춘다」(09-18 ⬜6)가 실물로 증명된 자리다 · ⚠️ received_on 의 **뜻이 바뀌었다** — 그 빈에서 그 SKU 의 **마지막 사건일**(사건 없이 기초선에만 있으면 촬영일) · 화면은 문자열로 찍기만 한다
                ⚠️ 후보에서 빼는 것: IN_TRANSIT(창고가 다르다) · 빈 문자열 bin · 마스터에 없는 bin · **비활성 bin** · ⚠️ 0 으로 깎인 빈(§11-j 초과 배분)은 원장 행이 없어 후보에서 빠진다 · ⚠️ 원장은 낱개 SKU 라 세트 product 의 id 로 물으면 키가 없다(화면은 po_line.product_id 낱개를 넘긴다)
                ⚠️ wms_sku_bins(Cin7 스냅샷)는 읽지 않는다(원칙 1) · 시드하지 않는다(컷오버 때 채워진다 · 초기에는 거의 비어 있다) · 화면이 po_receipt_line 을 직접 조회해 라스트 빈을 만들지 마라
⭐ 계산은 DB 에만  po_receipt_detail 이 정본 — lines[] 는 PO 라인 전부(안 센 라인도 · 「센 것만 줄」이라 안 센 라인은 여기서 그린다) · ordered · invoiced · received_before · received_here · remaining · counted · allocated · unallocated · placed · over · work[] · receipt_lines[] · diffs[] · totals · warnings · 목록은 뷰 po_receipt_list · 화면은 저장 뒤 detail 을 되읽는다
⚠️ 환산          work_save 는 **낱개 총량**을 받는다 — 팩→낱개 환산 RPC 는 없다(화면이 곱하면 「계산은 DB」를 어긴다 · p_entered_qty·p_unit_product_id 로 DB 가 곱하는 안 · §13-f)
```

### 11-j. ⭐⭐ 내보내는 사건 — PO 는 원장을 직접 부르지 않는다
```
⚠️ 원칙 2(레고): 모듈은 사건으로만 잇는다. 원장이 PO 표를 들여다보면
   원장이 PO 의 표 구조를 알아야 하고, SO·재고조정·트랜스퍼가 서면 그것들도 알아야 한다 ⇒ 원장이 덩어리가 된다.
⇒ PO 가 **입고를 확정하는 순간** 「이런 일이 있었다」를 써서 내보낸다. 원장은 받아 쌓기만 한다.

⭐ **언제**: 입고 확정 순간이다(Caleb: 「재고는 흐르는 것이고 판매는 계속 이뤄져야 하니까」). 인보이스를 기다리지 않는다.

모양 — 원장이 받는 칸은 이미 있다(inv_ledger · `20260816000000`). PO 는 이렇게 채운다:
  날짜        물건이 들어온 날(occurred_on) — 우리가 처리한 시각이 아니다(inv_ledger 주석 그대로)
  문서 번호    ⭐ **갈라진 뒤의 번호**다 — PO-12345a 이지 PO-12345 가 아니다
  수량        실제 받은 것, 단 PO 수량을 넘지 않는다 — ⚠️ **초과분은 사건이 아예 안 나간다**(11-i)
  빈          풋어웨이에서 정해진 자리
  금액        인보이스가 있으면 그 단가 · 없으면 PO 단가(뒤에 차액이 붙는다 · §12-c)
  줄 번호      같은 문서 안에서 줄을 구별하는 값(line_ref)
              ⚠️ [검토 Claude 정정] 「같은 사건이 두 번 들어오는 것을 막는 열쇠」의 **한 부분**이다 — 실물 유니크 키는
              (doc_type, doc_number, line_ref, event_type, warehouse, bin, sku) 일곱(`inv_ledger_event_uq`). 줄 번호 하나가 열쇠가 아니다.
⭐ SO · 재고조정 · 트랜스퍼도 **같은 모양**을 따른다. 이 모양이 원장 이식(§12)의 입력 명세가 된다.
⬜ 사건을 실제로 어떻게 전달하는가(표 · 트리거 · EF)는 ~~표 설계 때 정한다~~ → [2026-09-16 합의 · Caleb] **원장을 IMS 로 옮길 때 잇는다.** 받을 곳이 없는데 보내는 쪽만 만들면 그 모양이 맞는지 확인할 방법이 없다. 입고 줄(`po_receipt_line`)에 원장이 필요로 하는 것이 다 있다 — 날짜 · SKU(po_line.product_id) · 창고/빈(ref_bin) · 수량 · 문서 번호(갈라진 뒤) · 줄 번호(line_no). ~~⬜ 유지 — 사건 표·트리거·아웃박스는 만들지 않았다.~~ → ✅ **[2026-09-19 `20260919155005` 원장 이식 2차] 표·트리거·아웃박스가 아니라 함수 하나로 이어졌다 — 아래.**
⭐ [2026-09-18 · `20260918203805`] 확정 RPC(po_receipt_confirm)도 **사건을 내보내지 않는다 · 빈 훅도 두지 않았다**(안 도는 코드가 남는다) — po_receipt_line 에 receipt_id 가 더해져 묶음(받은 날·창고·확정한 사람)까지 잇는다 · 초과분은 줄에 그대로이니 「기준까지만」은 원장 쪽이 po_receipt_diff(over)를 보고 자른다 · 방향(원장이 po_receipt_line 을 읽는다)은 맞다고 판단(2-b 이견 7).
⭐⭐ ✅ [2026-09-19 · 원장 이식 2차 `20260919155005` · 근거는 그 파일 머리 주석] **원장이 창구를 내고 PO 가 그것을 부른다** — `inv_post_receipt(receipt_id) → jsonb` · **같은 트랜잭션**
   ⚠️ po_receipt_confirm 이 inv_ledger 에 직접 insert 하지 않는다(원칙 2) — 장부를 어떻게 적을지는 원장이 정하고 PO 는 id 하나만 넘긴다. SO·조정·트랜스퍼가 서면 inv_post_<사건> 이 하나씩 선다
   ⚠️ 원장 쪽이 실패하면 확정도 실패한다 — **그것이 맞다**(재고에 안 잡힐 거면 확정도 하면 안 된다) · 「확정은 됐는데 재고가 안 늘었다」가 생길 수 없다
   ⭐ 부르는 자리 = ⓓ(묶음 confirmed) **뒤** · 창구가 status='confirmed' 를 스스로 확인한다(직접 호출로 초안이 장부에 닿는 길이 막힌다) · 그래서 raw 의 po_number 는 **갈라진 뒤 번호**다
   ⭐ 사건의 모양 (⚠️ 위 「모양」 표 두 줄과 부딪힌다 — 끝의 ⚠️)
      doc_type purchase · event_type po_in · source **ims** · seq_hint 1 · amount **null**(수량 원장 · 단가·통화·환율은 raw — 원가 차수가 읽는다)
      doc_number **RCV-…**(⚠️ PO 번호가 아니다 — 유니크 7키에 doc_task_id 가 없어 같은 PO·같은 제품·같은 빈의 재입고가 겹친다 · **입고가 사건의 실제 단위**다 · PO 번호는 raw.po_number)
      line_ref **po_line_id**(⚠️ ProductID 가 아니다 — Caleb 실측 확정 2026-09-19 · 발주 CardID 와 같은 결 · 같은 제품 두 라인도 키가 안 겹친다 · ledger-design 2부 line_ref 표) · doc_task_id po_receipt.id · occurred_on 묶음의 received_on
      한 입고 줄 = 한 행(빈별) · warehouse·bin·sku 는 **이름**으로(원장은 텍스트 축 · ledger-design 4부 「이식」)
   ⭐⭐ **초과는 기준까지만** 원장에 간다(§11-i) ⇒ **원장 합 ≠ 입고 줄 합이 정상이다.** 깎인 것은 raw 에 남는다 — line{counted, basis, posted, excess, diff_kind} · this_bin{counted, posted, trimmed} · bins[](라인 전체 배분 · 0 으로 깎인 줄도 여기)
      ⭐ **basis(기록)와 cap(깎기)은 다른 값이다** — 기준을 po_line.qty_ea 에서 읽지 않는다(ⓒ 분할이 그 값을 줄인다 · 시점 함정):
         basis = 차이 큐 po_receipt_diff.expected_qty(over·short 어느 쪽이든 행이 있으면 · ⓑ 가 얼린 **분할 전 기준**) · 없으면(딱 맞게 받음) 센 것
         cap   = over 면 expected_qty · 아니면 센 것(short 는 깎을 것이 없다) · posted 는 cap 으로만 계산
         ⚠️ [실사고 2026-09-19 검증 ⑤] 처음에 basis 를 over 에서만 읽어 부족일 때 raw 에 10 이 적혔다(기준은 12 였다 · 분할이 qty_ea 를 10 으로 줄인 뒤라 되캘 길도 없었다). 숫자(posted)는 맞았지만 **기록이 틀렸다** — 나중에 원장 행 하나로 기준을 캐면 틀린 답을 얻는다 ⇒ 둘을 갈랐다
      ⭐ 초과 배분(한 라인이 여러 빈 · 기준을 넘을 때) — **수량 큰 빈부터 채우고(동률은 빈 이름 → id) 바닥나는 줄에서 자른다**(예 기준 12 · A 8 · B 7 → A 8 · B 4)
         근거: 어떤 규칙도 실물과 어긋난다(초과분은 어딘가의 빈에 실제로 있다) — 그래서 「덜 틀리게」: 큰 무더기가 그 SKU 의 주 자리이고 작은 쪽이 넘친 것일 확률이 높다 · 주 자리의 장부가 맞는 쪽이 Last bin·피킹에 낫다
         ⚠️ 비례 배분은 6.4 같은 **가짜 소수**를 만든다 · 이름순은 실물과 무관하다 · 「마지막 놓은 줄」은 po_receipt_line 에 순서가 없다(created_at 이 한 트랜잭션이라 전부 같다)
         0 으로 깎인 줄은 행을 만들지 않는다(raw.bins 에는 남는다) ⇒ 그 빈은 ims_last_bin 후보에서 빠진다
   ⭐ 멱등 — 이미 그 RCV 의 ims 행이 있으면 쓰지 않고 already_posted=true · existing_rows 를 말한다(**조용한 0 이 아니라 말하는 0**) · 창구는 직접 부를 수 있다(백필·복구 — 확정된 입고만 받는다) · 유니크 충돌은 읽을 수 있는 문장으로
   ⭐ 거부(문장) 권한(ims_require_write receiving) · 확정 아님 · 경고만: received_on 이 기초선보다 이름(received_on_before_baseline) · 미래 · 반환 { rows_posted · qty_counted · qty_posted · qty_excess · lines[] · warnings[] } — confirm 반환의 **ledger** 키 · warnings 에 ledger_trimmed_to_basis
   ⭐ security **invoker**(inv_ledger insert 는 authenticated 에 열려 있다 · definer 가 필요한 표가 없다 · §5 예외를 늘리지 않았다)
   ⚠️ 위 「모양」 표와 부딪히는 두 줄 — 고치지 않고 적어 둔다(ims-doc-update-0919 ⬜1 · Caleb 판정): 「문서 번호 = 갈라진 뒤의 PO 번호」→ 실물은 **RCV 번호**(PO 번호는 raw) · 「줄 번호(line_no) = line_ref」→ 실물은 **po_line_id**   ⭐⭐ [원가 이식 1차 2026-09-19 · `20260919192236` · b09a4c0] **확정이 레이어도 만든다** — inv_post_receipt 가 원장을 넣은 뒤 같은 트랜잭션으로 `inv_layer_post_receipt` 를 부른다(원장 사건·레이어가 함께 서거나 함께 죽는다)
      키 = 원장 키(RCV · po_line_id) · bin 을 접는다(원장 행 수 ≠ 레이어 행 수가 정상) · 수량 = 원장(기준까지만) · cost_source po_line · unit_cost = unit_price × **CAD per USD**(곱한다 · 기준통화면 ×1)
      ⭐⭐ 게이트 ⑥ — 기준통화(inv_config.base_currency) 아닌 발주에 환율이 없거나 0 이면 **확정 거부**(어디서 고치는지 문장에 · 발주 머리 Exchange rate 칸은 확정 뒤에도 열린다 · 11-b) · 창구도 같은 조건으로 막는다(백필 경로)
      백필 — 환율을 넣고 inv_post_receipt 를 다시 부르면 already_posted 분기가 레이어만 세운다(RCV-00005·00006 ⬜) · 반환 ledger.layers{layers_created · qty · cost_total_cad · fx_direction}
      ✅ [2026-09-20] **inv_layer_apply() 전량 재생성이 이 레이어를 창구로 되살린다**(`20260920142635` · 옛 「돌리지 마라 · 되살리지 않는다」는 틀렸었다 — 실물은 0 원 레이어로 덮어썼다 · ledger-design 4부 「✅ 해소 — inv_layer_apply() 에 IMS 판」 · §13-f) · 원가 규칙의 정본은 ledger-design 4부 「원가 이식 1차」
```

### 11-k. ⭐ 제품 생성 — 지금 규칙이 필요한 유일한 것 (§10-k 의 예외)

Caleb 의 지적이 정확했다: 「제품 등록을 컷오버까지 미루면 **그날 처음 써 보게 된다**. 그러면 테스트는 언제 하나」
⚠️ [대화 Claude 의 잘못] 「컷오버 근처에 한다」고 말했는데 **정본에 그런 문장이 없다.** 내가 얹은 것이다.
   정본(§10-k 끝)에 있는 것은 「결국 IMS 에서 한다」와 「컷오버 전에 새 제품이 필요하면 **양쪽에서 각각 만든다**」이다
   — 즉 **컷오버 전에 IMS 에서 제품을 만드는 상황을 이미 상정하고 있었다.**

**⭐ 적재가 같은 것을 어떻게 알아보는가 — 열쇠를 `cin7_id` 로 바꾼다**
```
⚠️⚠️ [검토 Claude 정정] 지금 실물: ③ 제품 적재는 **SKU 를 충돌 키로 쓴다** — `ImsLoadProduct.gs` 255·367행 `ipr_upsert_('product','sku',…)` · 181행 product_family 도 sku(§3-f 표 그대로).
   cin7_id 를 충돌 키로 쓰는 것은 ④ product_supplier 만이다(§3-g · ProductSupplierID).
   ⇒ 지시서의 「적재는 cin7_id 로 맞춘다 · SKU 를 고쳤을 때 cin7_id 로 맞추니 제품이 하나로 유지됐다」는 제품 적재의 **현재 상태가 아니다.**
      Caleb 의 SKU 정리(공백·철자)는 적재 **전**에 끝났다(§3-f 전제)라, SKU 변경이 재적재를 통과한 적이 아직 없다.
⭐ 그래도 **판단은 그대로 선다 — 열쇠는 cin7_id 여야 한다.** SKU 는 움직이는 값이다(공백·철자 수정이 실제로 있었다).
   SKU 로 맞추면 그 수정 하나하나가 **새 제품**을 만들어 재고와 발주 이력이 둘로 갈린다. cin7_id 로 맞추면 SKU 칸만 새 값으로 바뀌고 제품은 하나다.
   ⇒ §7 의 메모 「충돌 키를 cin7_id 로 바꾸면 따라온다」를 **결정으로 올린다**(발동 조건이 없어도 간다 — 그때 바꾸면 이미 두 행이다).
   ⚠️ 「지금 SKU 에 중복이 없으니 결과가 같지 않나」 — 결과가 같은 이유는 중복이 없어서가 아니라 **SKU 를 바꾼 적이 없어서**다. 다른 문제다.
   ⬜ 딸린 미확인 그대로(§7): cin7_id(ProductID)가 SKU 변경에도 유지되는지 — GUID 라 유지될 것으로 보이나 **실측 전** ·
      sku unique(`20260913230500`)는 유지 — Cin7 에서 SKU 를 고치면 옛 SKU 는 사라져 충돌하지 않을 것으로 보이나 미확인.

⚠️ IMS 에서 만든 제품(source='manual')은 cin7_id 가 없다 ⇒ Cin7 에서 같은 SKU 가 오면 **열쇠가 안 맞아 새 행**이 된다.
⇒ ⭐ **승격이 필요하다**: cin7_id 로 못 찾으면 **SKU 로 한 번 더** 찾고, 있으면 그 행에 cin7_id 를 붙인다.
   ④ product_supplier 에 **이미 있는 장치**다(§3-g 「충돌 키 cin7_id + manual 승격」) · product 에는 아직 없다.
   ⬜ 승격된 행의 source 를 'manual' 로 두는가 'cin7' 으로 바꾸는가 — 표 설계 때(§3-f 의 2) 단계와 is_default 재계산이 source 를 본다).
⚠️ 스킵이 아니라 승격이다 — 스킵하면 그 제품은 cin7_id 없이 남아 **그 뒤로 Cin7 갱신을 못 받는다**(연결 고리가 없다).
⚠️⚠️ **승격은 자동으로 다 되지 않는다** — 그 SKU 마저 움직이는 값이다.
   우리가 AS12345 로 만들고 Cin7 이 AS12345-A 로 만들면 SKU 로도 못 찾아 두 행이 된다.
   ⇒ **cin7_id 없는 제품을 항상 볼 수 있는 자리**가 필요하다(수가 적으니 눈으로 볼 수 있는 크기 · 카운터 하나).
⭐ 실제로 IMS 에서 제품을 만드는 상황은 대개 **새로 발주할 물건이 아직 Cin7 에 없을 때**다
   ⇒ PO 의 「후보에 없는 제품을 발주하려면」에서 이 규칙이 자연히 쓰인다.
```
**⚠️ 왜 「지금」인가**
```
규칙 없이 제품을 몇 개 만들어 두고 나중에 붙이면, 그사이 적재가 돌면서 **같은 SKU 가 이미 두 행**으로 들어와 있다.
그러면 어느 쪽이 진짜인지 손으로 갈라야 한다. 규칙을 먼저 넣으면 그런 일이 안 생긴다.
⇒ §10-k 의 다른 항목들과 **성격이 다르다** — 저것들은 나중에 채워도 구조가 안 달라진다.
```

---

## 12. ⭐⭐ 원장·원가를 IMS 로 옮긴다 (2026-09-15 저녁 · 판단만)

Caleb: 「지금 만들어 놓은 원장과 원가에 연결해서 쓰는 게 아니라, **그 원장과 설계를 복사해서 IMS 에서 연결**할 수는 없냐」
⇒ 된다. 그리고 그게 맞는 방향이다(원칙 1 Cin7 독립).

⚠️ 지금 원장·원가는 **운영 프로젝트 `asung-WMS`(gftpcnkxbdjzzfvzwcfl)** 에 있다. PO 는 **테스트 `Asung-IMS`(fazgmyvzzhqybtvtktyg)**. 서로 다른 Supabase 프로젝트다.
⚠️ 운영 원장은 당분간 거기 있어야 한다 — Cin7 과 대조하며 완성도를 올리는 중이다(shadow).
⚠️ 원장의 정본은 `ledger-design.md` 다 — 이 절은 **PO 쪽에서 본 이식 판단**만 적는다. ⬜ 그쪽에 「IMS 이식」 절을 여는 것은 별건(이번 세션은 손대지 않았다).

### 12-a. ⭐ 갈라진다 — 마이그레이션을 읽고 분류했다

⚠️ [검토 Claude 정정] 아래는 `supabase/migrations/` 의 **`create table` 실물 21표**(`inv_` 접두 · grep) 기준이다. 대화의 「30개」는 원장 관련 마이그레이션 **파일** 수(28)에 가까운 어림이었다 —
   표가 아닌 것(`ledger_collected_at` 은 RPC 에 더한 신선도 키 · `inv_stock_master` 는 RPC · `inv_balance`·`inv_balance_vs_cin7` 은 뷰)이 섞여 있었고, 표 넷(`inv_config`·`inv_sku_types`·`inv_balance_diffs`·`inv_bin_notes`)이 빠져 있었다.
   실제 운영 DB 와 다를 수 있다 — 이식할 때 실물로 다시 확인한다.
```
✅ 옮긴다 — 원장 본연 (Cin7 없이 성립한다)
   inv_ledger              뼈대. 언제·어느 SKU·어느 창고/빈·얼마·무슨 사건·어느 문서 몇째 줄
   inv_layer               언제 받은 물건이 개당 얼마인지를 층으로
   inv_layer_cost_add      ⭐ **나중에 붙는 비용을 이미 쌓인 층에 더한다** — 11-f 의 「비용은 나중에 온다」가 여기서 풀린다
   inv_layer_consume       나갈 때 어느 층에서 얼마나 뺐는지 — 소비 시점 unit_cost 를 굳힌다(12-c)
   inv_cost · inv_doc_cost 문서별 원가·비용 — inv_doc_cost.ref_number 가 「Service Invoice 번호」 칸(`20260910152545` 주석) · 11-f 와 맞는다
   inv_config              기준선·기본값 설정(ref_currency 기본값도 여기 · §4-④) — Cin7 무관 [검토 Claude 추가]

❌ 안 옮긴다 — Cin7 때문에 생긴 것
   inv_snapshot            Cin7 재고를 찍어 두는 표(대조 상대가 없다)
                           ⚠️ 다만 컷오버 때 「Cin7 재고를 통째로 가져오는」 기초 잔고로는 쓸 수 있다 — 그때 판단
   inv_compare · inv_compare_runs · inv_balance_diffs   우리 계산 vs Cin7 (inv_balance_diffs 는 아침에 굳히는 차이 표 · [검토 Claude 추가])
   inv_sync_state          Cin7 을 어디까지 긁었는지 커서
   inv_sku_types           Cin7 제품 타입 캐시(§9 경위 첫 줄 「마스터가 아니다」) — IMS 에서는 ③ product 가 그 자리 [검토 Claude 추가]
   수집 장치 다수          inv_conflicts · inv_missing_lines · inv_snapshot_runs · inv_doc_state · inv_collect_runs · inv_voided_docs · inv_missing_docs
                           ⇒ 전부 「Cin7 을 긁어오다 생기는 문제」를 막는 장치다
   ⭐ 앞단이 통째로 없어진다 — 긁어올 필요가 없다. PO 가 입고 확정 자리에서 사건을 **직접 쓴다**(11-j). 오히려 단순해진다.

⬜ 분류 미결 [검토 Claude]
   inv_bin_notes           bin 메모(기록이 목적 · 사람이 적는다 · `20260901183252`) — Cin7 대조 화면(재고 마스터)에 딸려 태어났지만 내용은 Cin7 무관. IMS 재고 화면이 서면 그때 판단

⚠️ 손봐야 하는 것 (마이그레이션 주석 실물)
   inv_ledger.doc_task_id  「Cin7 내부 식별자(있으면)」 — IMS 문서에는 없다
   inv_ledger.source       지금 'cin7' / 'wms' — IMS 에서는 뜻이 달라진다(사건을 낸 모듈 이름이 될 것으로 보인다 · 짐작)
   inv_cost.collector      「누가 긁어왔는지」
   inv_cost.occurred_on    주석이 「Cin7 이 준 날짜 그대로」다
   [2026-09-16 추가 · PO 표를 세우며 드러난 것]
   inv_ledger.warehouse·bin   **text**(Cin7 원문 이름)인데 IMS 는 **uuid FK**(po_receipt_line.bin_id → ref_bin → ref_warehouse) — 입고 줄이 사건이 될 때 ref_warehouse.name · ref_bin.name 으로 **풀어야 한다**
   inv_layer_cost_add.kind    landed · transfer_freight 인데 po_charge.kind 는 freight · duty · brokerage · other — **대응**을 정해야 한다(비용 → 층에 더할 때)
```
⚠️⚠️ **§12 를 다시 봐야 한다 (짐작 — 확인 전엔 위 분류를 고치지 않는다).** [실측 · Caleb 2026-09-16] 테스트 DB Asung-IMS 의 시퀀스 목록에 `inv_ledger_id_seq` · `inv_layer_id_seq` · `inv_cost_id_seq` · `wms_orders_id_seq` 등 **inv_* · wms_* 시퀀스가 전부 있다.** baseline 을 통째로 올린 것으로 짐작된다.
그러면 이 절의 「원장을 **복사해 옮긴다**」는 틀린 전제일 수 있다 — **이미 있고 안 쓰일 뿐**일 수 있다. ⚠️ 표 존재는 미확인이다(시퀀스가 있다고 표가 있는 것은 아니다). ⬜ 다음 세션에 아래로 확인한 뒤 「옮긴다/안 옮긴다」 분류와 12-b · §9 의 「복사해 옮긴다」를 한 번에 다시 본다(이번 문서 작업 범위 밖 · 2026-09-16 판단).
```bash
psql "$(cat ~/.asung-testdb-url)" -P pager=off -c "\dt public.inv_*" -c "\dt public.wms_*" -c "select count(*) as inv_ledger_rows from public.inv_ledger;"
```

### 12-b. ⭐ 순서 — PO 를 먼저 끝내고 원장을 옮긴다 (오늘 합의)
```
근거  원장은 사건을 **받는** 쪽이다. 무엇이 들어오는지 모르면 제대로 못 옮긴다.
      반대로 PO 는 원장이 없어도 설계가 끝난다 — 사건을 내보내는 자리만 정해 두면 된다(11-j).
⚠️ 순서를 바꾸면 스물한 표 중 무엇을 뺄지 **PO 가 무엇을 쓸지 모르는 채로** 판단하게 된다
   ⇒ 나중에 「이건 필요했네」가 나오면 다시 가져오는 게 아니라 **옮기는 작업을 다시** 하게 된다.
```

### 12-c. ⭐ 늦게 오는 원가 — 이미 풀려 있었다

대화 Claude 가 「비용이 나중에 붙으면 이미 쌓인 원가를 고쳐야 한다」고 걱정했으나 **이미 구조가 있다.**
```
소비 기록의 unit_cost 는 **나간 시점 값으로 굳는다**(`ledger-design.md`: 「소비 시점 값을 굳힌다」 · inv_layer_consume).
⇒ 나중에 비용이 붙으면 **남아 있는 층에만** 붙고, 이미 나간 몫만큼은 안 붙는다. 그 안 붙은 금액이 곧 차액이다.
⇒ 소급하지 않으니 **마감한 달이 흔들리지 않는다.**
[실물 · ledger-design 2026-09-10] PO landed $2,215.65 중 $2,086.45 만 평가액에 반영 — 차액 $129.20 = 이미 팔린 몫(8월 건이라 판매가 있었다)
```
⇒ 인보이스가 늦게 와서 단가가 달라져도 **같은 길**로 간다(11-j 「금액 — 없으면 PO 단가 · 뒤에 차액이 붙는다」). PO 쪽에서 새로 만들 것이 없다.
⬜ 그 차액을 **어느 계정으로 터는가**는 여전히 미결 — `ledger-design.md` 3부 「13. 미결 (다음 세션)」의 「뒤늦게 붙은 원가 차액의 회계 처리 · 실측 후 회계사와 상의」.
   ⚠️ [검토 Claude 정정] 그 문서에 「§13」이라는 절은 없다 — 3부 안의 굵은 소제목이다(1부~4부 + 부록 구조). 지시서의 「§13」은 그 소제목을 가리킨 것으로 읽었다.
📌 **회계사에게 물을 것이 둘로 모였다** — ① 이 차액의 회계 처리 ② 조기결제 할인의 HST 매입세액(11-h). 한 번에 묶어 물으면 된다.

---

## 13. ⭐⭐ ⑤ PO 표 열하나 — 실물 · 검증 · 거래 표 규약 (2026-09-16 · 테스트 DB Asung-IMS 적용 · ⚠️ 운영 미적용)

⚠️ §11 은 판단의 기록이고 이 절은 **그 판단이 표가 된 실물**이다. 칸·제약·근거의 정본은 마이그레이션 파일의 주석이다 — 여기는 목록·검증·규약만.
지시서 `~/asung/prompts/po-tables-1.md` · `po-tables-2.md` · `po-tables-doc.md` · 검토 이견은 각 파일 머리에.

### 13-a. 표 열하나 · 파일 아홉 · 커밋 여덟 (git log 로 확인 · 2026-09-16 · 저녁 갱신 — ⚠️ 표 수는 열하나 그대로 · 칸만 늘었다: po +15 · po_invoice +2) → ⭐ [2026-09-18] **표 열넷**(+ po_receipt · po_receipt_work · po_receipt_diff) · 뷰 + po_receipt_list · po_receipt_diff_list · 파일 +7 · 커밋 +6 → ⭐ [2026-09-19 원장 이식] 뷰 + `ims_inv_balance` · `ims_ledger_unlinked` · 함수 `inv_post_receipt` · `ref_warehouse` +1행(IN_TRANSIT · manual · 비활성) · `po_receipt_list` +open_diffs(맨 뒤) · 마이그레이션 둘 `20260919151601`(162행 · 커밋 49faf5d) · `20260919155005`(450행 · 커밋 2d2219b) · 정본 ledger-design 4부 「이식」 → ⭐ [2026-09-19 오후] **표 변경 없음** · 칸 +2(po_receipt_diff.resolution · resolution_note) · 어휘 +1(inv_layer.cost_source 'po_line') · 뷰·함수만: `po_family_members` · `po_family_lines` · `po_receipt_diff_resolve` · `po_receipt_diff_reopen` · `inv_layer_post_receipt` · `inv_layer_post_charge` · 다시 낸 것 po_receipt_detail · po_receipt_diff_list(+2칸) · inv_post_receipt · po_receipt_confirm(게이트 ⑥) · po_charge_confirm(게이트 ⑥ · 되돌리기 landed 거부) · 마이그레이션 셋 `20260919175712`(420행 · 9a5344a) · `192236`(538행 · b09a4c0) · `200414`(280행 · 83b79f5)
```
①차 20260916144201_po.sql (226행)                        커밋 8a27edd  10:49
   po               발주 머리   po_number(PO-02000~ · 시퀀스 기본값) · status 넷 · supplier · currency/exchange_rate · payment_term(FK+원문) · ship_to_warehouse · split_from_id(바로 앞) · created/confirmed_by → ims_staff
   po_line          발주 라인   line_no · product(낱개) · supplier_sku · qty_ea · 입력 단위 칸 셋 · unit_price(18,7 · 0 허용) · tax_rule 원문 · ❌ received_qty · ❌ 라인 할인
   po_discount      할인 줄(예상) seq · name · percent · supplier_discount_id
   po_receipt_line  입고 줄     po_line · received_on · received_by → ims_staff · bin_id → ref_bin(NOT NULL) · qty_ea
②차 20260916153313_po_invoice_charge_payment.sql (312행)  커밋 37be987  11:53
   po_invoice           인보이스 머리  supplier · invoice_number · invoice_date · due_date · payment_term · currency/rate · total_amount(대조값 · 크레딧도 양수) · status 셋
                                    ⭐ ③차 추가 doc_kind(invoice/credit) · credit_for_invoice_id(nullable · self-FK) · unique (supplier_id, doc_kind, invoice_number)
   po_invoice_line      인보이스 줄    po_line_id nullable · line_kind(goods/charge/other) · description · 단위 칸 넷 · unit_price · ⭐ is_payable
   po_invoice_discount  할인 줄(확정)  po_discount 와 같은 모양 · ⭐ 원가 배분의 정본
   po_charge            비용 문서     supplier(경비처) · charge_number · kind(freight/duty/brokerage/other) · description · 총액 · status 셋 · 제품 참조 없음
   po_charge_alloc      비용 배분     po_charge → po · amount 박아 둠(재계산 없음 · CHECK 없음)
   po_payment           결제         paid_on · amount · currency/rate · account_id → ref_account(nullable · 지정만) · reference · ⭐ discount_taken · paid_by · 상태 없음
   po_payment_alloc     결제 충당     po_invoice(인보이스 · 또는 크레딧이면 「썼다」) **또는** po_charge 하나(CHECK) · amount(양수)
읽기 20260916163806_po_read.sql (364행) + 164539_po_read_factor.sql (295행)   커밋 68aefa0  12:47   po_mul(곱 집계) · po_list(뷰 · security_invoker) · po_detail(RPC · jsonb) · factor 표시 6자리
③차 20260916175003_po_credit.sql (358행)                  커밋 3be9a86  13:54   po_invoice 에 doc_kind·credit_for · 유니크 셋 · po_detail 에 credits[] · invoices[].credit_total
쓰기 20260916181719_po_write.sql (472행)                  커밋 540e518  14:28   po_create · po_lines_paste · po_line_update · po_line_delete (array_append 정정본 포함)
넓은 목록 20260916190000_po_list_wide.sql (847행)           커밋 e62d16a  18:37   ⭐ po 머리 칸 15(required_by · tax_rule · tax_inclusive · inventory_account id+code · 그날의 연락처 3 · 주소 6) · po_list +14칸(국면 다섯 · doc_numbers · paid/unpaid_total …) ·
                                                                                  po_detail 캐럿(po_shares · allocs) + header 편집용 id · ⭐ 뷰 po_invoice_money · po_charge_money(문서 돈의 정본) · po_create 손질(연락처·주소·tax_rule·inventory account) · inv_config po_inventory_account_code   → 13-g
인보이스 20260916200000_po_invoice_write.sql (1,093행)     커밋 160430b  19:52   po_uninvoiced_lines · po_invoice_create · po_invoice_add_po_lines · po_invoice_line_add/update/delete · po_invoice_confirm ·
                                                                                  ⭐ po_discount_save/delete(세 자리) · 뷰 po_invoice_list · RPC po_invoice_detail   → 13-h
크레딧번호 20260916210000_po_credit_number.sql (778행)     커밋 0b4a6aa  20:48   po_invoice 에 supplier_ref_number · credit_po_id · po_credit_next_number(CN-<po> / CN-<연도>-<n> · advisory lock) · po_invoice_create 손질 · po_invoice_list/detail · po_list.doc_numbers   → 11-c · 13-h
[2026-09-17] 취소·삭제 20260917100000_po_void_delete.sql (433행)       커밋 5355033        po_doc_cancel · po_doc_delete(발주·인보이스·크레딧 · ⚠️ 크레딧은 삭제 금지 · 판정 축 confirmed_at) · cancelled_by(po · po_invoice)   → 11-b · 11-c
           비용     20260917150000_po_charge.sql (901행)            커밋 38f1098        po_charge_list · _detail · _create(미리 보기 · 비례 제안 po_charge_alloc_propose) · 배분 편집 셋 · _spread · _confirm · cancelled_by(po_charge) · 'charge' 를 취소·삭제에   → 11-f
           줄별 수량 20260917170000_po_invoice_line_qty.sql (446행)   커밋 0184260        po_invoice_create + p_line_qty · ⚠️ 시그니처가 바뀌어 **drop + create**(레포 첫 사례 · §5)   → 11-g
           결제     20260917190000_po_payment.sql (880행)           커밋 db36acd        po_payment_target_check · po_payment_list · _detail · _create · 충당 편집 둘 · 'payment' 를 삭제에(취소는 거부)   → 11-h
[2026-09-17 밤] 권한 다섯 덩어리 — 표는 그대로 열하나(ims_staff 칸 +1) · 정책·함수·RPC 본문만 (§10-h · §5 권한 규약 · §10-j 3-l)
           ① 계정     20260917230000_ims_staff_roles.sql (231행)              커밋 5b4e4c7        role 넷 CHECK · warehouse_access uuid[](빈=전부) · perms 두 축 · 판정 함수 여섯(ims_can_enter/view/write/warehouse · ims_perm_catalog · ims_access)
           ② RLS      20260917235000_ims_rls_write_gate.sql (249행)           커밋 352d024        auth_all 28 → select 열림 + insert/update/delete = ims_can_write('<묶음>') · 정책 101(+ims_staff 3 = 104) · 마스터 11 은 delete 정책 없음
           ③-1 거부    20260918000000_ims_rpc_honest_refusal_po.sql (855행)    커밋 d6c3155        도우미 ims_require_write 신설 · 발주 6(po_create · lines_paste · line_update/delete · doc_cancel/delete) 첫머리 권한 + row_count
           ③-2 거부    20260918003000_ims_rpc_honest_refusal_invoice.sql (870행) 커밋 0e7b61c      인보이스·할인 8(두 묶음 po_discount_save/delete 는 갈래로) · 원본 바이트 스크립트로 옮김(diff 첨부 방식 시작)
           ③-3 문장    20260918010000_ims_require_write_one_message.sql (34행) 커밋 0e7b61c        거부 문장 하나로 — 읽기 여부를 말하지 않는다(ims_can_view ≠ 데이터 읽기 · 실측)
           ③-4 거부    20260918013000_ims_rpc_honest_refusal_charge_payment.sql (548행) 커밋 2120657  비용·결제 9 — 쓰기 RPC 23 전부 완료
           ⑤ 등급     20260918020000_ims_role_hierarchy.sql (152행)           커밋 7ba12b4        ims_role_rank · ims_can_manage · can_view/write 의 staff 특례 제거 · ims_staff 정책 둘 = staff 쓰기 + 아래 등급(트리거·RPC 없이) · EF ims-staff-create 도(963fadd)
           ⑤ 라벨     20260918023000_ims_perm_catalog_staff_label.sql (25행)  커밋 c034a6f        staff 라벨 「Adding and editing people (below your own rank)」 · ⚠️ 020000 §4 도 같은 함수를 한 번 고쳤다(중복 · 뒤 파일이 이긴다)
           ④ 화면     asung-ims 9f8ed27(ims-auth.js · ims-ui.css) · staff.html ff36b20 → 6085092 → 29fd003 → 87e0118        ims_access() 한 번 · 모드 탭 줄 · items 다섯 칸 · 등급으로 폼
[2026-09-18] 리시빙 일곱 — 표 +3 · 뷰 +2 · 함수 +11(+ detail·split 다시 냄) · 칸 +29(updated_by) +1(po_receipt_line.receipt_id) (§13-i · 머리 주석에 근거)
           동시 편집 바닥 20260918133858_ims_updated_by.sql (121행)         커밋 f288ee8 12:25   ims_touch() · IMS 표 29 에 updated_by + <표>_updated_by_idx · <표>_set_updated_at drop → <표>_touch(§5) · RPC 무접촉
           1번 표 셋   20260918161537_po_receipt_tables.sql (198행)        커밋 f288ee8 12:25   po_receipt · po_receipt_work · po_receipt_line.receipt_id(nullable) · po_receipt_next_number(RCV-) · ⭐ ims_last_bin(uuid[], uuid) · 정책 8 · touch 트리거
           2-a RPC    20260918163552_po_receipt_rpc.sql (641행)            커밋 38527e7 12:49   po_receipt_bin_check · _create · _work_save · _work_split · _work_putaway · _work_putaway_all(WMS Place all) · _work_delete · _delete · RPC po_receipt_detail(⭐ 계산의 정본) · 뷰 po_receipt_list · 권고 잠금(PO·라인)
           탭·room    20260918165934_ims_perm_catalog_receiving_room.sql (35행) 커밋 9f58d40 13:10   receiving.room wms → ims(§10-j 3-l · ⚠️ worker 기본이 안 열린다) · asung-ims ims-auth.js items 다섯째
           되돌리기   20260918173042_po_receipt_work_unassign.sql (115행)   커밋 e1c7115 13:40   po_receipt_work_unassign — 빈을 지우고 미배정으로 · 빈 없는 줄이 있으면 병합 · 합 불변을 잰다
           놓인 것    20260918174428_po_receipt_work_split_placed.sql (102행) 커밋 b2adcb5 13:49   split 다시 냄(create or replace) — 새 줄·합쳐진 줄 putaway_done = true · 기존 false 줄 데이터 수정(notice)
           2-b 확정   20260918203805_po_receipt_confirm.sql (446행)          커밋 0f50a7e 16:50   ⭐⭐ po_receipt_diff(표·뷰 po_receipt_diff_list) · po_receipt_confirm(security definer · 입고 줄 · 차이 · 자동 분할 · 닫기) · detail 다시 냄(receipt_lines · diffs · received_here · split 정보)
```
⭐ [2026-09-17] 파일 넷 · 커밋 넷이 더 섰다(위 네 줄) — 표는 그대로 열하나 · 칸은 cancelled_by 셋만 늘었다. 화면은 asung-ims 에 charges.html · payments.html 신설 + po.html·invoices.html 손질 + 공통 CSS(af06c61) + 구매 탭(9dcee4d · db4841e).
전부 **거래** ⇒ 컷오버 때 지운다(§11-⓪). 규약은 §5 「거래 표의 규약 예외」. ~~⚠️ 확정 문서는 DB 가 보호하지 않는다(트리거 없음 · ⬜ 분할 함수 차수).~~ → [2026-09-16 오후] 확정은 잠금이 아니다(§11-b) · 막는 둘은 po_line_update/delete 가 본다(13-d).
📌 검증 데이터는 지우지 않는다(Caleb) — 화면 만들 때 볼 것이 있다. 어차피 컷오버 때 지울 거래다. `po_number_seq` 는 ~~2002~~ → 2007 까지 썼다(2026-09-16 저녁 · po 8행 PO-02001a·b · 02002~02007).

### 13-b. ⭐ 실물 검증 — 열한 표가 이어진다 [실측 · Caleb 2026-09-16 · SQL 로 직접 돌림 · 검토 Claude 는 결과만 받았다]
```
발주      PO-02001 Ampro 3라인 · 소계 2,755.80 · 할인 Trade 17% + Damage 1%
          ⭐ 체인곱 2,264.44 vs 단순합 2,259.76 — **차이 4.68** ⇒ 「차례로 곱한다」가 실제로 다르다(§11-e 확증 · Ampro 146 달러의 축소판)
입고      1번 라인 600개를 두 빈(A010101 400 · A010102 200)에 나눠 넣었다 ⇒ po_receipt_line 이 담는다
          ⭐ po_line 에 received_qty 를 안 두고 **합으로 냈는데 문제없다**
분할      PO-02001 → PO-02001a(closed · 세 라인 주문=입고 완전 일치) + PO-02001b(confirmed · split_from → a · 100개 대기)
          ⭐ a 는 주문=입고가 맞는다 ⇒ **인보이스 만들 때 뺄 것이 없다**(§11-g 「Copy 가 간단해진다」 실증)
인보이스  AMP-778812 · 물건 3줄(a 의 라인을 가리킴) + charge 1줄(운임 187 · po_line_id 없음 · is_payable=false) · 할인 Trade 17% + Damage 1%
          ⭐ 물건 2,446.80 × 할인 체인 = 2,010.54 · + 운임 187 = **2,197.54 = 찍힌 총액**(차이 0.00)
          ⚠️ 처음 총액을 근거 없이 2,451.44 로 넣자 **차이 −253.90 이 드러났다** ⇒ total_amount 를 대조값으로 둔 이유가 실증됨
비용      CBSA 10039192310530 · duty · CAD 2,547.37 · **두 발주에 걸침** — PO-02001a(소계 2,446.80) 597.49(23.5%) · PO-02002(소계 7,985.00) 1,949.88(76.5%) · 합 = 총액(차이 0)
          ⭐ [2026-09-17 실측 · Caleb SQL] PO-02002 소계는 지금 **8,010.40** — 그 뒤 라인이 +25.40 되었다. **위 7,985.00 은 오기가 아니라 그날 실물이다**(2026-09-16 정오 discount_factor 1.000000 이라 소계 = net_total · `20260916164539` 291행 · `20260916163806` 347행).
          ⇒ 지금 비례로는 596.04 / 1,951.33 인데 박힌 597.49 / 1,949.88 은 그대로다 — **박아 둔 배분이 따라오지 않는 §11-f 의 실례.** 📌 [경위] 대화 Claude 가 이 줄을 「net_total 을 소계라 적은 오기」로 단정했다가 검토가 바로잡았다 — 값 하나가 안 맞는 것을 보고 **데이터가 움직였을 가능성을 안 봤다.**
          ⚠️ 우연히 맞았다 — 잔돈 규칙(금액이 가장 큰 발주 · 동점은 발주번호 순)은 §11-f 에 새로 적었다
결제      WIRE-20260916-01 · USD 2,010.54 · BMO USD CHEQUING → AMP-778812 충당 2,010.54
          EFT-20260916-02 · CAD 2,496.42 + **discount_taken 50.95**(2% 조기결제) → CBSA 충당 2,547.37
          ⭐ 검산 「송금액 + 할인 = 충당액」 둘 다 0.00
미지급    AMP-778812 갚을 돈 2,010.54 − 충당 2,010.54 = **0** — ⭐ 청구 총액은 2,197.54 인데 갚을 돈은 2,010.54 다
          ⇒ is_payable=false 가 없었으면 운임 187 이 **영원히 미지급으로 남았다**(검토 이견 12 가 실제로 필요했음)
          CBSA 2,547.37 − 2,547.37 = **0**
```
⭐ 검증이 증명한 것 넷 — 할인 체인 차이 4.68 · received_qty 없이 합으로 됨 · total_amount 대조값이 −253.90 을 드러냄 · is_payable 없으면 운임 187 이 영원히 미지급.

### 13-c. 표를 세우며 정해진 것 · 정정된 것 (§11 각 절의 「→ 표」 요약)
```
닫힘    11-c 연결 칸 = 바로 앞(split_from_id) · 번호 형식 PO-02000~ · 11-d 단가는 product_supplier 에 이미 있다 · 환산 계수 채택 · §3-b ③ 할인 소속 = 인보이스 · §3-d·§7·11-f Service 53 자리 불필요
정정    11-b·11-f 「입고가 끝나도 바로 안 닫는다」 → **closed = 입고 종료 · 비용은 뒤에 붙는다**(국내 발주 · 「다 붙었다」를 알 수 없다)
        11-g 「행이 PO 들을 가리킨다」 → 줄이 po_line 을 가리킨다 · 11-h 「결제는 인보이스를 가리킨다」 → 인보이스 **또는** 비용 문서(설계 대화의 누락 · 검토가 잡음)
        [오후] ⭐⭐ 11-b 「확정 = 문서 잠금」 → **확정 = 공급사에 보낼 수량과 라인이 정해졌다 · 잠금 아님**(비약을 실무가 바로잡음 · 잠금 문장 일곱 곳 정정) · 11-d Fixed Price 는 IMS 에서 안 고친다(전환 기간 정본 Cin7) · 유니크 (supplier, invoice_number) → 셋 · ②차 「크레딧성 음수」 주석 정정
새 규칙  할인 두 층(예상 po_discount · 확정 po_invoice_discount) · 비용 배분은 박아 두고 재계산 없음 · 비용 배분 잔돈은 발주번호 순 · 초과분은 입고 줄에 적히되 사건은 확정 수량까지(원장 합 ≠ 입고 줄 합)
        Latest 는 연습 기간에도 갱신하되 적재가 덮는 것이 정상 · 컷오버 때 Latest 는 남긴다 · for_payments 는 결제 계좌 필터가 아니다
검토가 잡은 것  거래 표는 마스터 규약 대상이 아니다 · 할인 두 층 · po_line_id nullable · is_payable · 결제가 비용 문서도 가리킨다 · 「바로 안 닫는다」 문장 둘 · Service 자리 문장 셋 · 잔돈 동점 기준
[저녁] 정정  청구 국면은 금액 → **수량**(금액으로 재면 다 청구됐는데 영원히 「일부」 · 13-g) · 11-e 「복사 제안된다」를 지시서가 「미결」이라 적은 오기(11-e) · 11-g 「머리에 PO 칸 없음」에 예외 credit_po_id(채번의 축) ·
             「계산 규칙의 정본은 RPC」 → 문서 돈은 뷰 둘(po_invoice_money · po_charge_money · 13-g) · 크레딧 번호는 우리 것(11-c 신설)
⬜ 남은 것     → **13-f** (2026-09-16 오후 · 저녁 갱신 — 닫힌 것은 취소선)
```

### 13-d. 읽기 · 크레딧 · 쓰기 · 화면 (2026-09-16 오후 · 커밋 셋 + asung-ims 다섯)
```
읽기  뷰 po_list · RPC po_detail(p_po_id) · 곱 집계 po_mul                              68aefa0 12:47 (+ 164539 factor 6자리)
      나누는 기준(Caleb): 목록은 **뷰**(표처럼 보여 imsPage·imsQ 가 그대로 듣는다 · §10-j 3-a) · 상세는 **RPC**(한 번에 · 조회 일고여덟 번이 하나로)
      ⭐⭐ **계산 규칙의 정본은 RPC 다** — 할인 체인 · 미지급 · 총액 대조를 화면에서 다시 짜지 않는다(화면마다 다시 짜면 어긋난다)
      → [2026-09-16 저녁 정정 · 13-g] 발주 쪽(할인 체인 · 라인 금액 · 입고 합)은 po_detail 그대로 · **문서 돈(payable · paid · credit_total · unpaid · remaining)은 뷰 po_invoice_money · po_charge_money 로 옮겼다** — po_list 도 같은 식이 필요해져 두 곳이 될 판이었다(「식이 두 곳이면 정본이 둘」 · Caleb 「지금이 옮길 때다」)
      뷰는 with (security_invoker = true) — 나중에 RLS 를 걸어도 뷰가 구멍이 안 된다(선례 wms_order_pack_progress 2026-08-06)
      할인 체인은 **곱 집계 po_mul**(첫 집계 선례) — exp(sum(ln())) 은 percent=100 에서 ln(0) 으로 터지고 부동소수 오차가 있다(검증에서 쓴 식은 임시였다)
      discount_factor 는 표시용 6자리(numeric 곱은 40자리까지 나온다 · 실측) — ⚠️ 금액은 **원래 factor 로 계산한 뒤** 2자리 · 표시용과 계산용을 섞지 않는다
      없는 id → null · 숫자는 JSON number · 미지급 = payable 줄 합(goods 체인) − 충당 − 붙은 크레딧 · 인보이스 할인은 goods 줄에만(11-e)
      [실측 · Caleb] 예상값 전부 일치 · PO-02001b net_total 253.91(예상 253.90 은 뺄셈 어림 · 곱 집계가 맞았다)
크레딧  po_invoice.doc_kind · credit_for_invoice_id · 유니크 셋 · po_detail credits[] · invoices[].credit_total          3be9a86 13:54   설계는 11-g 크레딧 소절
쓰기  RPC 넷                                                                                540e518 14:28
      po_create(supplier, warehouse?, date?, note?)  → {id, po_number, warnings[]}   공급처 기본값(통화 없으면 inv_config.base_currency) · 기본 창고는 is_default 가 정확히 하나일 때만 · supplier_discount 복사(지금 0행 · 채우면 듣는다) · created_by 서버 유도
      po_lines_paste(po, [{sku,qty}], commit)        → {summary, lines[]}          판정 여섯(11-d) · 미리 보기 = 같은 모양 · 500줄은 판정(too_many) · closed/cancelled 는 예외
      po_line_update(line, patch) · po_line_delete(line)                            막는 둘(11-b) · 입고·인보이스가 붙은 줄 삭제 거부 · 갱신된 행을 돌려준다
      ⚠️ 이 파일 머리 주석은 「확정 = 공급처에 보냈다」로 한 판 앞이다 — 그 뒤 대화에서 「수량·라인이 정해졌다」로 한 번 더 바뀌었다(11-b). 마이그레이션은 고치지 않는다
리시빙 [2026-09-18 · §11-i · §13-i]  쓰기 아홉 · 읽기 셋 — 전부 첫머리 ims_require_write('receiving', …) + update/delete 뒤 row_count(§5 ②) · 이름 서브쿼리는 별칭 · 계산은 DB 에만
      po_receipt_create(po, received_on?, warehouse?)      → {id, receipt_number, status:'draft', warehouse, warnings}   confirmed PO 만 · PO 당 draft 하나(번호를 문장에) · 창고 = po.ship_to → 인자 · created_by 서버 유도 · 잠금 po_receipt:<po>
      po_receipt_work_save(receipt, po_line, qty_ea, method?)  → {counted, allocated, unallocated, work_id, action}      ⭐ 라인의 낱개 총량 · 빈 없는 줄 = 나머지 하나(만들고·고치고·0 이면 지운다) · 총량 < 배정 합이면 거부 · 잠금 po_receipt_work:<receipt>:<line>
      po_receipt_work_split(work, qty_ea, bin)             → {from, to{merged}, line_total}                             원래 줄에서 빼고 빈을 함께 받은 새 줄(putaway_done true) · 같은 빈 줄이 있으면 병합 · 원래 수량 이상은 거부 · 읽은 수량 그대로일 때만
      po_receipt_work_putaway(work, bin, done=true)        → {work_id, bin, putaway_done, merged_into}                  빈은 po_receipt_bin_check(그 입고의 창고 · 활성) · 같은 빈 줄이 있으면 합치고 이 줄을 지운다
      po_receipt_work_putaway_all(receipt, bin, done=true) → {rows_changed}                                              WMS Place all 승계 · 이미 그 상태인 줄은 안 건드린다(0 은 거짓말 아님)
      po_receipt_work_unassign(work)                       → {work_id, removed_work_id, merged_into, qty_after, line_total, action}   빈·놓았나·넣은 사람을 되돌린다 · 빈 없는 줄이 있으면 병합 · 이미 빈 없으면 unchanged · 합 불변을 잰다
      po_receipt_work_delete(work) · po_receipt_delete(receipt)   → {deleted, line_total} · {deleted, work_rows_deleted}   draft 만 · 묶음 삭제 축은 confirmed_at(세 문서와 같은 문장) · po_receipt_line 이 가리키면 이름으로 거부
      ⭐⭐ po_receipt_confirm(receipt)                      → {po{number_before, number_after, status}, split|null, diffs{over, short, rows}, receipt_lines_created, **ledger**, warnings}   §11-i 확정 게이트 · ⚠️ security definer(§5 예외 하나) · [2026-09-19] ⓓ 뒤 ⓔ 창구 호출 · warnings + ledger_trimmed_to_basis · received_on_before_baseline
      ⭐⭐ inv_post_receipt(receipt)                          → {rows_posted, qty_counted, qty_posted, qty_excess, lines[], already_posted, existing_rows, warnings}   [2026-09-19 `20260919155005`] ⭐ **원장의 창구**(inv_ 접두어 = 원장 소유 · §11-j) — confirm 이 부른다 · 확정된 입고만 · 멱등(말하는 0) · security invoker(예외를 늘리지 않았다) · ⚠️ create function 이라 다시 못 돈다(§13-f)
      읽기  po_receipt_detail(receipt) → jsonb(⭐ 계산의 정본) · 뷰 po_receipt_list(+ **open_diffs** 맨 뒤 칸 · 2026-09-19 · 기존 24칸 이름·순서 무변 · 화면은 select("*")) · po_receipt_diff_list · ims_last_bin(product_ids[], warehouse) → jsonb 맵(**속 = 원장** 2026-09-19 · §11-i)
            [2026-09-19 `20260919151601`] 뷰 **ims_inv_balance**(inv_balance 를 읽어 product_id·warehouse_id·bin_id·last_event_on·last_seen_on 을 붙인다 · 잔고 정의는 inv_balance 하나 · security_invoker) · **ims_ledger_unlinked**(축 점검 · kind sku|warehouse|bin · 기준선 sku 1 · warehouse 0 · bin 0)
      [2026-09-19 오후 · `20260919175712`] 차이 닫기 — 쓰기 둘 · 읽기 둘 · 전부 첫머리 ims_require_write('receiving') · security invoker
      po_receipt_diff_resolve(diff, resolution, note?)   → {diff_id, receipt_number, resolution, resolved_by_name, resolved_at, family{ordered_total, received_total, still_owed}, open_diffs_left}   short 만 · 어휘 다섯 · other 는 메모 · 이미 닫힘 거부(reopen 안내) · for update 잠금
      po_receipt_diff_reopen(diff, note?)                → {was_resolution, was_resolved_by, open_diffs_left}   세 칸을 비우고 메모에 흔적
      읽기  po_family_members(po_id) → table(po_id, po_number, status, closed_at, split_from_id, depth, is_self) · po_family_lines(po_id) → table(product_id, sku, line_nos[], ordered_total, received_total, still_owed, members, fragments[])   ⭐ 계산은 DB · 재귀 순환 방어(path · 깊이 50)
            po_receipt_detail 이 header.po_family · lines[].family · diffs[].family(+ resolution · resolution_note · resolved_by)를 낸다 · po_receipt_diff_list 맨 뒤 +resolution · resolution_note
      [2026-09-19 오후 · `20260919192236` · `20260919200414`] 원가 창구 둘 — inv_layer_ 접두어(원가 표 소유) · security invoker
      inv_layer_post_receipt(receipt)                     → {layers_created, layers_existing, qty, cost_total_cad, fx_rate, fx_direction, lines[]}   inv_post_receipt 가 부른다(already_posted 분기에서도 — 백필) · 확정된 입고만 · 환율 게이트 · 멱등(4키)
      inv_layer_post_charge(charge)                       → {layers_touched, amount_posted_cad, no_layers_allocs/_amount_cad, no_basis_allocs/_amount_cad, already_posted_allocs, allocs[]}   po_charge_confirm 이 부른다 · purchasing 권한 · 배분 줄 단위 멱등
      다시 낸 것  po_receipt_confirm(+ 게이트 ⑥ 환율 · 반환 ledger.layers) · po_charge_confirm(+ 게이트 ⑥ · 확정 뒤 창구 · 되돌리기 landed 거부 · 반환 cost)
      ⚠️ 검증은 RCV-00005(PO-02011)로 rollback 안에서 — po_receipt_create 를 부르면 「already has an open receipt」로 거부된다(앞 검증이 여기서 어긋나 뒤가 전부 깨졌다) · RCV 시퀀스는 rollback 으로 안 돌아간다
화면  asung-ims po.html                                                                    36c1fc2 12:59 읽기 → 4ae86d6 13:56 크레딧(credit due) → 0e23369 14:35 만들기·편집 → 609297c 14:38 오류 삼킴 수정 → d376907 14:45 TDZ 수정
      읽기: 왼쪽 목록(po_list) + 오른�록 상세(po_detail) · 카드 일곱 + 크레딧 · 갈라진 문서 이동은 모체 번호를 검색칸에(§11-c · §10-j 3-d)
      쓰기: + New purchase order(공급처 → po_create) · Paste lines(미리 보기 → 넣기) · 라인 수량·단가를 표 안에서 바로 고친다(50줄을 하나씩 눌러 들어가면 느리다 · Caleb) · 삭제 · Confirm · Cancel
      규칙: 화면은 계산하지 않는다 · 막는 것은 화면이 하지 않는다(DB 거부 메시지를 그대로) · 저장 뒤 다시 읽되 스크롤 자리를 지킨다(§10-j 3-i)
      [화면 실측 · Caleb] 붙여넣기 — By Natures 는 연결이 없어 단가 0 · Strength of Nature 는 공급처 SKU·단가가 따라왔다(3.43 · 3.5 · 3.23 · 2.41 · 소계 586.92) — 설계대로
```

### 13-e. ⚠️⚠️ 실사고 셋 — 문법 검사로는 안 잡히고 **실제로 돌려야** 드러난다 (2026-09-16 오후)
```
① text[] 에 문자열 리터럴을 || 로 붙이면 터진다    ERROR: malformed array literal — Postgres 가 리터럴의 타입을 못 정해 **배열 || 배열**로 푼다
   ⚠️ format(...) 결과는 text 라 통과한다 ⇒ **어떤 판정은 되고 어떤 판정은 터지는** 모양이 된다(no_link 는 터지고 duplicate 는 됐다)
   ⇒ array_append(배열, 요소) 를 쓴다 · 파일 전체를 grep 한다(:= v_\w+ || ') — 16군데 · 「적용됐지만 한 번도 제대로 돌지 않은 함수」라 원본을 고치고 같은 파일을 다시 적용했다(이 경우만의 예외 · 표 DDL 이었다면 새 파일)
   ⬜ 이 레포의 **다른 plpgsql 함수**에 같은 모양이 있는지는 별건 — 운영 WMS 함수가 조용히 터지고 있을 수 있다(ledger-design.md 미결에도)
② JS 에서 선언 전에 읽으면 화면이 통째로 멈춘다     const ed 를 라인 표 앞에 두었는데 **그보다 위에 있는 버튼 줄(acts)이 먼저 읽어** ReferenceError(TDZ)
   상세가 안 그려지고 **「Loading…」이 영원히 남았다** — 증상이 원인을 안 가리킨다 ⇒ 화면 조각이 쓰는 값은 그 조각보다 위에서 선언한다(§10-j 3-i) · d376907
③ 오류를 쓸 자리가 없으면 진짜 오류가 가려진다      모달 안의 자리에 쓰려다 그 요소가 없어 화면이 죽었고 **RPC 가 뭐라 했는지 못 봤다**
   ⇒ 자리가 없으면 alert 로라도 반드시 보여 준다. 오류는 삼키지 않는다(§10-j 3-i) · 609297c
📌 ②의 곁가지 — 브라우저가 말한 줄 번호가 파일과 **안 맞았다**(showErr 265행인데 307이라 했다 · 차이도 일정하지 않았다). 배포본을 받아 제 사본과 cmp 로 대조해 같음을 확인한 뒤에야 코드에서 원인을 찾았다
   ⇒ **증상이 가리키는 곳이 아니라 코드를 읽어야 할 때가 있다**
```

⭐ [2026-09-16 저녁 · 화면 쪽 셋이 더 있다 — 대화 Claude 기록 · 검토 Claude 가 본 것은 ⑥ 의 1180 조사와 PO_BUILD 실재(po.html 202행)]
```
④ JS 선언 순서를 **두 번** 틀렸다 — 같은 실수를 하루에 두 번
   첫 번째(오후 ②): const ed 를 라인 표 앞에 두었더니 그보다 위의 버튼 줄이 먼저 읽어 「Loading…」이 남았다
   두 번째(저녁): 캐럿 도우미를 비용 줄 앞에 두었더니 그보다 위의 인보이스 줄이 먼저 읽어 또 멈췼다(asung-ims 749bd5f → 54fefb0 네 커밋이 같은 제목인 이유)
   ⇒ **조각들이 쓰는 값은 전부 조각보다 위에 모아 둔다.** 「그 조각 바로 앞」으로는 부족하다 · 검토 항목: 「선언 순서 — 조각이 쓰는 값이 그 조각보다 위에 있는가」(po-invoice 화면 검토 2026-09-16 저녁)
⑤ hidden 속성이 안 먹었다 — .wrap{display:flex} 가 브라우저 기본 [hidden]{display:none} 을 이긴다(po.html 59~62행 주석)
   ⇒ 숨기라고 해도 그대로 보이고 넓은 목록은 숨은 채였다. [hidden]{display:none !important} 로 못 박았다(po.html · invoices.html 둘 다)
   ⚠️ display 를 가진 요소에 hidden 을 쓸 때마다 걸리는 함정이다
⑥ 버튼을 바꿔치기하며 id 를 없앴는데 시작 코드가 그 id 를 찾고 있었다 — 화면이 통째로 죽었다
   ⇒ 그 뒤로 **찾는 id 가 실제로 있는지 전수 대조**한다(getElementById 목록 vs id= 목록 · 검토가 invoices 23 · po 37 개를 스크립트로 대조 · 2026-09-16 저녁)
⚠️ 셋 다 **문법 검사로는 안 잡힌다.** 위 ①~③ 의 공통점과 같다
📌 곁가지 — 브라우저가 말한 줄 번호가 파일과 안 맞는 일이 오늘 여러 번 있었다(대화 Claude 기록: po.html:1180 을 세 번 보고). 검토 Claude 의 조사(2026-09-16 저녁): 배포본 a867578 은 1,137행 ·
   36c1fc2 → a867578 어느 커밋에도 1,180행이 없었고 imsAuth.start 콜백 안에 forEach 로 onchange 를 거는 자리 자체가 없었다 — 커밋되지 않은 사본이나 콘솔에 남은 옛 기록으로 짐작.
   ⇒ 줄 번호를 믿지 말고 코드로 찾는다. po.html 에 빌드 표시(PO_BUILD · 5f5de57)를 넣어 어느 판이 도는지 보이게 했다
```

### 13-g. ⭐⭐ 넓은 목록 · 국면 다섯 · 머리 칸 15 (2026-09-16 저녁 · `20260916190000` 847행 · 커밋 `e62d16a` 18:37 · 화면 po.html 749bd5f→54fefb0)

지시서 `~/asung/prompts/po-list-wide.md` · 검토 이견 1~24(14 「cancelled 는 none」만 뒤집힘 → 「사실로 판정」). 근거의 정본은 파일 머리 주석 — 여기는 판단의 요약.
```
⭐ 화면 두 모드   아무것도 안 골랐으면 **넓은 목록**이 화면 전체 · 고르면 좁은 목록 + 상세 · ⭐ 상세에서 왼쪽 목록을 **접을 수 있다**(「☰ List」) [Caleb] 「들어갔다 나왔다 하는 게 Cin7 은 많이 불편하다」
⭐⭐ 국면 다섯    주문 · 청구 · 입고 · 비용 · 결제 — 각 셋(none 회색 · partial 주황 · done 초록) · ⭐ **뷰(po_list)가 문자열로 내고 금액·수량도 함께 준다**(계산 규칙은 한곳 · 화면이 정하면 다음 화면이 다시 짠다)
                 ⚠️ **넓은 목록에만** 그린다 · 머리는 「Status」 하나(낱말 다섯을 두었더니 점과 세로로 안 맞았다 · 화면)
   주문          라인 0 → none · 라인은 있는데 확정 전(draft · 또는 confirmed_at 없는 cancelled) → partial · 확정됐으면 → done
                 ⭐ **상태가 아니라 사실로 판정한다**(Caleb) — 취소된 문서도 라인이 있으면 「만들다 접은 것」이다(라인 13개짜리 PO-02005). 취소는 상태 칩이 보여 준다
   청구          ⭐ **금액이 아니라 수량으로**(검토 Claude 정정 · Caleb 「맞다」) — invoiced_qty(goods 줄 합) vs ordered_qty
                 ⚠️ 인보이스 단가는 발주 단가와 자주 다르고(11-d) 할인은 문서 단위라 발주 몫으로 안 내려간다 — 금액으로 재면 **다 청구됐는데 영원히 「일부」**가 된다 · 취소 안 된 인보이스는 draft 도 센다 · 크레딧은 빼지 않는다
   입고          received_qty vs ordered_qty · 초과도 done(설계대로)
   비용          취소 안 된 배분이 하나라도 있으면 done · ⚠️ 국내 발주는 비용이 없어 늘 회색 — **구별하지 않는다**(Caleb)
   결제          ⭐⭐ **문서 기준** — 걸린 인보이스·비용 문서의 미지급 합 · ≤ 0 이면 done(음수 = 받을 돈 · 크레딧) · > 0 이면 paid 가 있으면 partial 없으면 none
                 ⚠️⚠️ 인보이스 하나가 발주 둘에 걸치면 그 미지급이 두 줄에 다 보인다 ⇒ **세로로 더하면 두 번 센다.** 화면 표 아래에도 그 문장이 있다(po.html posub)
⚠️ 크레딧은 국면이 **아니다**(진행도가 아니라 사건) ⇒ 발주번호 옆 **태그**(credit_count · split 과 같은 자리)
⚠️ 취소된 인보이스·크레딧·비용은 국면·건수·돈에서 뺀다 — 앞 po_detail 은 status 를 안 봤다(검증 데이터에 취소 문서가 없어 값 무변) · 헬퍼 뷰의 credit_total 도 취소된 크레딧을 뺀다(취소한 크레딧이 미지급을 줄이면 틀린다)
⭐ 검색·필터     **공급처가 첫째, 날짜가 둘째**(Caleb 실측 「주로 공급처별이 가장 많고 그다음이 날짜」) · 그다음 상태 · 검색 — ⭐ doc_numbers(text 한 칸 · 인보이스·크레딧·비용 번호 모음 · [저녁 210000] + 크레딧의 공급처 참조 번호)로 문서 번호로도 발주가 찾힌다
                 ❌ Document # 열은 두지 않는다(Caleb 「그다지 유용하지 않다」) · 빠른 필터(아직 안 온 것 · 미지급 있는 것)는 뷰 칸으로 충분 · 배열 칸은 PostgREST ilike 가 안 듣는다
⭐⭐ 돈의 정본    뷰 **po_invoice_money**(인보이스·크레딧 한 장의 goods/other 합 · factor · computed_total · diff · payable_net · alloc_total · credit_total · unpaid · remaining) · **po_charge_money**(paid · unpaid · alloc_sum · unallocated)
                 — po_list 와 po_detail 이 같은 뷰를 읽는다. 식이 두 곳이면 정본이 둘이 된다(Caleb 「지금이 옮길 때다」). 발주 쪽 계산(할인 체인 · 라인 금액 · 입고 합)은 po_detail 그대로 · 13-d 의 「정본은 RPC」는 그 범위로 좁아졌다
⭐ po_detail 캐럿  invoices[].po_shares · credits[].po_shares(문서가 걸린 발주 전부 · amount 는 할인 전 줄 합) · charges[].allocs([실물] CBSA 2,547.37 = PO-02001a 597.49 + PO-02002 1,949.88) · header 에 편집용 id(currency_id · payment_term_id · ship_to_warehouse_id)
⭐ po 머리 칸 15  required_by(Caleb 「필요해」 · 뷰에도 낸다 — 「아직 안 온 것」의 정렬 축) · tax_rule(머리가 기본값 · 줄 null 이면 머리를 따른다 · [실측] po_line.tax_rule 47개 전부 null · product.purchase_tax_rule 0행 · ⚠️ 세금 **계산**은 없다 — ref_tax_rule 미결) · tax_inclusive(기록만) ·
                 inventory_account id+code(⭐ 공급처도 제품도 아닌 **회사 기본값** inv_config.po_inventory_account_code=_59_ · [실측] product.inventory_account_code 는 18,713 중 1곳뿐이고 그것도 _58_ · supplier 에는 account_payable 만) ·
                 ⭐ **그날의 연락처 3 · 주소 6**(결제조건 FK+원문과 같은 이유 — 나중에 메일을 보낼 때 「누구에게 보냈나」 · 답장 받기는 지금 필요 없다) — ⚠️ **원문만 · FK 없음**: supplier_contact 는 「261건 그대로 옮기고 나중에 걸러 지운다」(§3-b C)라 FK no action 은 정리를 막고 set null 은 §5 의 새 예외다 · 주소는 여섯 칸 그대로(한 줄로 합치면 문서에 다시 못 찍는다)
                 po_create 규칙: 연락처 = is_default 정확히 하나 → 활성 정확히 하나 → null(contact_unset/ambiguous · [실측] 활성 226 중 기본 하나 159 · 기본 없이 하나 20 · 0건 44 ⇒ 179 곳) · 주소 = 1건 → Billing 하나 → null(⚠️ 활성 226 중 0건 143 ⇒ address_unset 이 대다수 · 오류가 아니다) · 회사 이름·메모가 든 행(「Acquired by House of Cheatham」이 연락처와 Billing 주소로)을 규칙으로 골라내지 않는다 — 정리의 일
                 ❌ blind_receipt · Additional attributes 는 두지 않는다(Caleb) · 기존 8행은 null(backfill 없음 · 그날 값은 만든 날 박히는 것)
⬜ 드롭십(다른 배송지)  미뤘다 — ⚠️ 주소 칸만 두면 「받을 수 없는 발주」가 생긴다. po_receipt_line.bin_id 가 NOT NULL 이라 우리 창고에 안 들어오는 물건은 입고 줄을 못 세우고 원장 사건도 나가면 안 된다. §3-d 의 「드롭십」은 Service 제품(수수료)이라 발주 흐름의 증거가 아니다(짐작) · Cin7 실측이 먼저
파일 하나      뷰·RPC 가 새 칸을 읽고 po_create 가 쓴다 — 나누면 중간 상태에서 깨진다 · create or replace view 는 칸 순서·타입을 못 바꾸므로 새 칸은 **전부 뒤에**(po_list 22 → 36칸)
```

### 13-h. ⭐⭐ 인보이스·크레딧 만들기 · 할인 편집 · 크레딧 번호 (2026-09-16 저녁 · `20260916200000` 1,093행 `160430b` 19:52 · `20260916210000` 778행 `0b4a6aa` 20:48 · 화면 invoices.html a867578→ccb58a1→bbea8a9 · ims-auth.js 메뉴 Invoices)

지시서 `po-invoice-write.md`(검토 이견 1~18 · 15 목록 뷰는 「빠뜨린 것」으로 범위에) · `po-credit-number.md`(이견 1~14 · ⓒ 실측으로 예상값 성립). 판단은 **11-e(할인 세 자리) · 11-g(만들기 · 확정의 뜻) · 11-c(크레딧 번호)** 에 적었다 — 여기는 기제와 실물.
```
RPC 열       po_uninvoiced_lines(발주 라인의 미청구 = 주문 − 취소 안 된 인보이스 goods 합 · 화면도 본다) · po_invoice_create(미리 보기 · 머리 원천 셋 · 미청구 복사 · 할인 복사 제안 · 크레딧 차이 채우기 · 번호 자동) ·
             po_invoice_add_po_lines(다른 PO 통째로 · 같은 공급처만 · 두 단계) · po_invoice_line_add/update/delete(draft 만 · goods 는 po_line_id · 그 밖은 description) · po_invoice_confirm(양방향 · reopen 은 결제 없을 때만) ·
             po_discount_save/delete(세 자리 · 11-e) · po_credit_next_number(채번) · 뷰 po_invoice_list · RPC po_invoice_detail — 나누는 기준은 오후와 같다(일이 여럿이면 RPC · 다른 행을 봐야 하면 RPC)
⭐⭐ 크레딧 채번  「건수가 아니라 번호를 읽어 **최대 꼬리 + 1**」 — CN-<po> 가 없으면 그것 · 있으면 CN-<po>-<n> 의 n 최댓값 + 1(없으면 2) · 조정 번호도 CN-<연도>-% 의 최댓값 + 1
             ⭐ **취소된 것도 센다** — 결정적 근거: 취소된 것을 빼면 **공급처에 이미 알려 준 번호가 다른 문서를 가리키게 된다**(「내역을 알려 주면」이 실무) · 유니크(supplier, doc_kind, number)에도 걸린다 · 번호가 건너뛰는 것은 PO 시퀀스의 빈 번호와 같은 판단 · ~~지운 초안은 번호를 돌려준다(짐작)~~ → [2026-09-17 정정] **크레딧은 지우지 않는다 — 취소만**(채번이 행을 읽어 첫째를 지우면 같은 번호가 그대로 다시 난다 · po_doc_delete 가 종류로 거부 · §11-c 크레딧 번호 소절)
             ⭐ `credit_po_id` = 번호를 낸 발주(채번의 축 · 11-g 예외) — p_po_id → credit_for 인보이스의 발주가 **정확히 하나**일 때 그것 → 아니면 null(조정 번호 · 둘 이상이면 warnings credit_po_ambiguous · 화면이 p_po_id 를 골라 준다)
             ⭐ 동시성은 `pg_advisory_xact_lock(hashtext('po_credit_number'))` — ⚠️ **이 레포의 첫 advisory lock**(2026-09-16 grep 선례 없음) · 채번 함수 첫머리에서 잡아 **발주 번호·조정 번호 둘 다** lock 안에서 세고 트랜잭션 끝(insert 뒤)에 풀린다
               재시도 루프 대신 lock 을 고른 **결정적 이유는 조정 번호**다 — 전역인데 유니크는 (supplier, doc_kind, number) 라 다른 공급처끼리의 CN-2026-0001 중복을 재시도로는 못 잡는다 · 시퀀스로 못 내는 이유 — 발주마다 다시 세고 해마다 0001 로 돌아간다
             접두어 CN- 로만 센다 — 시험 데이터의 인보이스 번호 'PO-02002'(대화 Claude 가 발주 번호를 그대로 넣었다)는 셈에 안 든다 · ⚠️ 공급처가 우연히 그런 번호를 쓰면 인보이스 PO-02002 와 크레딧 CN-PO-02002 가 나란히 서서 헷갈린다 — 막을 방법이 없다(공급처 번호는 우리가 못 정한다) · 화면이 Kind 칩으로 가른다
             [Caleb 확인 2026-09-16 · 지시서 po-doc-evening 기록 · 검토 Claude 는 함수 실행 결과를 못 봤다] po_credit_next_number: PO-02002 → CN-PO-02002 · PO-02001a → CN-PO-02001a · null → CN-2026-0001 (CN-AMP-778812-1 은 접두어가 달라 셈에 안 든다)
             화면(invoices.html · bbea8a9): 크레딧 만들기에 번호 칸이 없다 · 미리 보기 번호는 「(provisional)」 · Supplier ref 칸은 confirmed 에서도 · 목록 검색 .or 에 supplier_ref_number
⭐ 검토가 잡은 것  크레딧 자동 채우기를 뒷단에만 만들고 **화면에서 닿을 길을 빼먹었다**(invoices.html 에 「Create a credit note」가 없었다 — 가장 큰 것 · ccb58a1 로 고침) · po.html 의 Kind=Credit 은 영원히 잠긴 Create(크레딧 + PO 는 줄이 빈 조정 크레딧 · 옵션 제거) ·
             목록의 Paid·Balance 가 크레딧 행에서 뜻이 다르다(doc_kind 로 갈라 Used·Remaining) · 「Add lines from a PO」 미리 보기 없음(두 단계로) · 뒷단: 청구 국면 수량 · 미지급 문서 기준 · 미청구 수량 · credit_po_id 의 구분 · 목록 뷰 누락(15)
⬜ 미룬 것(검토 이견 · Caleb 결정)  confirmed 머리(Printed total · Due date)는 뒷단이 안 막는다(화면은 draft 만 입력칸 · ⬜ 다음 뒷단 차수에 「confirmed 머리 잠금」) · po.html·invoices.html 의 로컬 main{display:flex} → ims-ui.css main.stack 으로(두 화면 함께 · 따로) ·
             .pick/.prow 로컬 CSS 없음(hover 색만) · 검색 .or 쉼표·괄호가 다섯째 화면 · Supplier 드롭다운을 발주처로 좁히지 않는다(비용처 문서가 이 화면에 올 수 있다) · 크레딧 줄의 Qty diff 는 뜻이 없다(비우는 것이 맞다 · 사소)
CHECKLIST    asung-ims fc718d9(7-a 다시 씀 · 7-b 신설 · §0 아홉 · §0-a 여덟) — ⚠️ 그 뒤 ccb58a1 · bbea8a9 로 화면이 두 번 더 바뀌었다 ⇒ ⬜ 「⬜ 아직 없다」 넷을 ✅ 로 · 크레딧 만들기(번호 자동 · provisional · Supplier ref) · Used/Remaining 열 · 빌드 표시(buildTag) · 모집단을 검증 뒤 행수로 — 말만(다른 레포)
→ [2026-09-17] RPC 열이 늘었다 — po_invoice_create 에 p_line_qty(11-g) · po_doc_cancel/delete(11-b) · po_charge_*(11-f) · po_payment_*(11-h). 「confirmed 머리 잠금」은 인보이스·비용·결제 셋을 한 차수로(§13-f).
```

### 13-i. ⭐⭐ 리시빙 — 방향 전환 · 표 셋 · RPC 열 · 동시 편집 바닥 (2026-09-18 · 마이그레이션 일곱 `20260918133858`~`203805` · 커밋 f288ee8 → 0f50a7e · 화면 receiving.html 은 대화 Claude)
```
⭐⭐ 방향이 바뀌었다   아침 계획은 WMS 리시빙을 IMS 로 **복사**해 오는 여섯 차수였다.
   저녁 결론 [Caleb] **WMS 이관을 미루고 IMS 안에 리시빙을 먼저 세운다** — 「지금 세우는 것은 IMS PO 옆에 인보이스·비용과 같이 있는 리시빙이다」 · 「IMS 전체를 다 세우고 나서 운영 WMS 를 통째로 옮기면 더 쉽지 않겠나」
   이유(조사가 밝혔다) — 반쯤 지어진 IMS 위에 완성된 화면을 얹으려니 **없는 것에 걸렸다.** 조사가 찾은 「1번 철칙에 걸리는 것」: 트랜스퍼 입고 · 기대치의 인보이스 기준 · 사람이 누르는 partial · 창고 접근 · 미지 bin 허용 · 상품 이미지(지시서는 「다섯」이라 했으나 나열은 여섯)
   ⇒ IMS 가 다 서면 그 걸림이 전부 사라지고 WMS 이관은 **배선 작업**이 된다
⭐⭐ 1번 철칙은 그대로   [Caleb] 「WMS 에서 현재 사용하는 기능과 관행이 깨지지 않아야 한다」 — 옮기지 않기로 한 것이지 버린 것이 아니다
   조사 결론(칸 대조표 81칸 · 기능 대조표 49항목 — 전문은 2026-09-18 대화에만 · 여기는 결론만)
     칸 81 중 「안 온다」 — WMS 만 있던 것: 기대치 스냅샷(expected_base — IMS 는 계산) · 인보이스 기준 칸 · 트랜스퍼 참조 · presence(held_by 계열 — 별 프로젝트) · 상품 이미지(product 에 칸 없음) · 미지 bin(Cin7 /ref/location 의 전 빈을 그대로 받던 것 — IMS 는 ref_bin 만)
     기능 49 중 그대로 건너온 것: 두 단계(검수 → 풋어웨이) · 라인별 수량·빈 · Placed/Place all · Change bin · Last bin 제안 · 축 칸 넷(누가 세었나 · 누가 놓았나) · 스캔/수동 구별 · 「전 라인 표시」(안 센 라인은 detail 의 PO 라인으로 그린다) · 초과·부족은 차이 큐 · 사람 판단 유지
     더해진 것(WMS 가 못 하던 것): 줄 쪼개기(한 라인을 두 빈에 · 실측 600 → 400 + 200) · 병합 · 되돌리기(빈까지 지운다) · 「누가 마지막에 고쳤나」(updated_by)
     남은 것(WMS 이관 때): 같은 줄 동시 스캔의 병합(WMS 는 델타라 병합됨 · IMS 는 총량 저장 — 동시 편집 화면이 그 자리) · 창고 접근(ims_staff.warehouse_access 는 섰다 · 리시빙 RPC 가 아직 안 본다 · 짐작: ims_can_warehouse 로 잇는다) · 트랜스퍼
   ⚠️ 트랜스퍼: IMS 에 트랜스퍼 문서가 없어 지금 리시빙은 **PO 만** 받는다. [Caleb] 「IMS 에 트랜스퍼가 서면 그것도 같이 가져온다 — 순서의 문제다」 · 컷오버 전 필수 · ⚠️ 그때 풀어야 할 자국: 지금 코드가 「PO 가 반드시 있다」를 전제로 쌓인다(po_receipt.po_id NOT NULL · work.po_line_id NOT NULL · 기준 = po_line.qty_ea)
⭐ 오늘 선 것        표 셋 + 차이 큐(§11-i 「→ 표 셋」) · RPC 열 + 뷰 둘(§13-d 「리시빙」) · 분할 함수(§11-c 「→ 분할 함수」) · Receiving 탭 ims(§10-j 3-k·3-l) · 동시 편집 바닥(§5 트리거 · §10-j 3-i) · security definer 예외 하나(§5 권한 규약 ②)
   순서(차수)         133858 바닥 → 161537 표 셋 → 163552 2-a RPC → 165934 탭·room → 173042 되돌리기 → 174428 놓인 것 → 203805 2-b 확정. 화면 receiving.html(815행 · 대화 Claude)은 detail 하나로 그린다(sb.rpc("po_receipt_detail") · grep)
⭐ 실사고·발견        ① 이름 서브쿼리 별칭 없음 → null 두 번(§5 트리거 ⚠️) ② split 의 새 줄이 putaway_done=false 라 PLACED 0(`174428` 로 고침 · 2-a 의 두 길이 달랐다) ③ 검증에서 po_receipt_create 를 다시 불러 「already has an open receipt」로 뒤가 전부 깨짐 → RCV-00005 를 쓰고 rollback
                    ④ pre-commit 훅(scripts/check-class-values.sh)이 po_receipt_diff 의 kind CHECK 를 wms_reports.kind 로 오해해 커밋을 막았다 — --no-verify 로 지나갔다(§13-f) ⑤ psql -f 로 적용하면 이력 표가 안 쌓여 db push 가 22개를 처음부터 밀다 멈췄다(피해 없음 · §13-f)
⚠️ 정본과 어긋난 것    §13-f 「원래 주문 수량을 라인에 남긴다(200 / 원래 300)」는 오늘 분할이 **하지 않았다**(a 라인은 받은 만큼으로 줄고 entered_* 는 비운다 · 원래 수량은 갈라진 전 문서에서 접두어로 모아 본다) — 고치지 않고 보고(ims-doc-update-0918 ⬜1)
```

### 13-f. ⬜ 다음 차수로 넘긴 것 (2026-09-16 오후 · 저녁 갱신 — 닫힌 것은 취소선 · → 어디서 닫혔나)
```
~~⭐⭐ 목록 화면 두 모드~~ → ✅ 13-g(e62d16a · po.html 54fefb0) · ~~⭐⭐ 국면 다섯~~ → ✅ 13-g(⚠️ 「confirmed 이상 초록」은 「확정됐으면 · 취소는 판정을 바꾸지 않는다」로 정정됐다) ·
~~⭐ 발주 머리 칸 추가~~ → ✅ 13-g(15칸 · 드롭십만 ⬜ 아래) · ~~⭐ 검색·필터~~ → ✅ 13-g · ~~⭐ 캐럿 확장~~ → ✅ 13-g · ~~⬜ 크레딧 자동 채우기~~ → ✅ 11-g·13-h(160430b · 화면 ccb58a1) · 인보이스 목록 화면 → ✅ po_invoice_list + invoices.html
~~⬜⬜ 인보이스·크레딧·발주 **무효로 만들기**   [Caleb 2026-09-16] 「테스트 오더를 계속 만들 텐데 하나씩 지우거나 취소해야 한다」 — draft 는 지우고 · confirmed 는 취소 · ⚠️ 결제가 붙었거나 이미 쓴 크레딧은 거부~~ → ✅ **11-b 「취소·삭제」 · 11-c 크레딧 번호 소절(`20260917100000` · 5355033)** — draft 는 지우고 confirmed 는 취소가 그대로 섰다 · ⚠️ 크레딧은 삭제 금지로 · 판정 축은 confirmed_at
~~                              ⚠️ 발주(po)에도 같은 문제 — 취소는 화면에 있지만 초안 삭제가 없다 · 시험 발주 8건 · ⇒ **내일 회사에서 먼저 한다**(Caleb)~~
~~⬜ 비용 문서 만들기 + 배분 · 비용 목록 화면   어느 발주에도 안 붙은 청구서는 캐럿으로도 안 보인다(po_charge_money.unallocated 가 그 자리) · 잔돈은 금액이 가장 큰 발주 · 동점은 발주번호 순(11-f)~~ → ✅ **11-f 「→ 쓰기」(`20260917150000` · 38f1098) · 화면 charges.html** — 고친 줄만 바뀐다 · unallocated ≠ 0 은 확정 거부 · 비례 한 곳
~~⬜ 결제 만들기                 ⚠️⚠️ **한 결제는 한 통화**다(Caleb 2026-09-16) — CAD·USD 계좌가 따로 있고 청구서 통화에 따라 갈린다 · 통화가 다른 문서를 한 결제에 섞지 않는다 ⇒ RPC 가 저장 전에 막는다 · cancelled 대상 거부 · 「한 결제 = 한 통화」~~ → ✅ **11-h 「→ 쓰기」(`20260917190000` · db36acd) · 화면 payments.html** — 한 결제 한 통화를 뒷단이 검사 · 확정 문서만 · 상태 없음(삭제만)
⬜⬜ 확정 뒤 머리 칸 잠금      **인보이스·비용·결제를 한 차수에 같은 규칙으로**(13-h 「confirmed 머리 잠금」이 셋으로 늘었다)
                              ⚠️ 비용이 가장 위험하다 — 확정 뒤 total_amount 를 PostgREST 로 고치면 unallocated ≠ 0 인 confirmed 문서가 생겨 §11-f 확정 검사가 지킨 불변식이 조용히 깨진다. 지금은 화면이 draft 에서만 입력칸을 연다
                              ⚠️ 결제는 currency_id 가 같은 성격 — 충당이 있으면 화면이 잠근다(11-h) · 뒷단 잠금이 서면 그것도 함께
⬜ 크레딧을 결제에 쓰는 길      §11-h 「안 붙은 크레딧만 이 길」이 `20260917190000` 의 p_targets 에 없다(지금은 거부 · 지시서 누락) · ⚠️ 검산 부호가 뒤집힌다: Σ인보이스 + Σ비용 = amount + discount_taken + Σ크레딧 · po_payment_target_check 에 kind 'credit' 가지
⬜ 입고 차수에 셋              입고에서 바로 크레딧(위 「입고 + 분할」에 이미 있다) · ⭐ **PO 라인 없이 받는 길** · ⭐ **약식 제품 등록**
                              ⭐ [Caleb 2026-09-17] 「PO 에 없고 인보이스에만 있는 제품이 입고된다. 그 자리에서 약식 등록이 되면 좋겠다」 · ⭐ 그 줄은 **PO 에 넣지 않는다**(Caleb) — 발주는 우리가 시킨 것의 기록이다(11-g)
                              📌 왜 입고 차수인가 — 약식 제품에 무슨 칸이 필요한지를 입고·원장이 정한다. 지금 고르면 그때 다시 연다
⬜ .pick / .prow               같은 「PO 고르기」 상자가 화면마다 세 모양(po 정의 · invoices 인라인 · charges 일부 · 10-j 3-j 발견) — 공통으로 올릴 후보
⬜ .ims-nav CSS                JS(ims-auth.js) 안의 <style> 에 있다 — ims-ui.css 로 옮길 후보(3-j 와 같은 결 · 탭 CSS 는 이미 ims-ui.css 에)
⬜ payments.html 만들기 창 재설계  [Caleb 2026-09-17] 「페이먼트가 뭐 이리 어려워」 — ⚠️ 순서가 거꾸로다: 돈 다섯 칸을 먼저 채우게 해 놓고 「무엇을 갚는가」가 맨 아래에 있다
                              ⇒ 문서 고르기를 맨 위로 · 고르기 전에는 돈 칸을 감춘다 · Check 를 없애고 Create 하나로(뒷단 미리 보기는 그대로 — 화면이 한 번에 부른다)
⬜ po.html .list .rows          `calc(100vh - 230px - var(--ims-tabs-h, 0px))` 로(3-k · 탭 높이만큼 넘친다) · main → `<main class="stack">` 두 화면(3-j 올리지 못한 둘)
~~⬜ 입고 + 분할 함수            ⭐ **PO 는 자동으로 닫힌다**(사람이 누를 일이 없다 · Caleb): 받은 수량 = 주문 수량이면 닫고 · 덜 받았으면 갈라져 받은 쪽이 닫히고 남은 쪽이 새로 선다 · ⚠️ 「비용과 결제는 PO 가 닫히는 것과 무관하다」 ⇒ 닫기 조건에 넣지 마라 ·~~ → ✅ [2026-09-18] `20260918203805` po_receipt_confirm(§11-i · §11-c · §13-i)
                              ~~⭐ 할인 줄(po_discount)은 갈라진 문서에 복사(검증에서 그렇게 했다)~~ → ✅ 복사한다 · ⚠️⚠️ **⭐ 원래 주문 수량을 라인에 남긴다(「200 / 원래 300」)** — 오늘 분할은 **하지 않았다**(a 라인은 받은 만큼으로 줄고 entered_* 는 비운다 · 「원래」는 갈라진 전 문서를 접두어로 모아 본다) · 정본 문장과 부딪힌다 — 고치지 않고 보고(⬜ Caleb 판정) · 잠금 트리거는 **없다**(11-b) · ⬜ **입고에서 바로 크레딧을 만드는 길**(「리시빙을 하면서 못 받은 것을 돌린다」 · 지금은 인보이스에서만)
⬜ 주석을 영어로               [Caleb] 「한국어가 안 되는 직원들을 위해 다 영문이 좋겠다」 — ⚠️ 화면 일곱 + 공통 둘 + 마이그레이션 여럿이 전부 한국어 · 한 파일만 바꾸면 섞인다 · ⬜ **정본 문서도 영어로 할 것인가**를 먼저 정한다(주석이 §11-b 를 가리키는데 그쪽이 한국어면 거기서 막힌다)
⬜ 드롭십(다른 배송지)          13-g — bin_id NOT NULL 이 막는다 · Cin7 실측이 먼저
⬜ 화면 잡일                   검색 .or 의 쉼표·괄호(다섯 화면 · 헬퍼) · main.stack(두 화면) · 뷰에 split_from_id · confirmed 머리 잠금(13-h 미룬 것)
⬜ 메일 보내기                 기술적으로 가능(EF + 메일 서비스 · PDF 첨부) · ⚠️ 답장 받기는 지금 필요 없다(Caleb) · PO·SO·손님이 다 선 뒤 · 「누구에게 보냈나」는 po 의 그날 연락처(13-g)
⬜ [09-17 밤 · 권한] 자기 행의 이름·메모만 고치는 길   지금은 admin 외 자기 행 전부 막힌다(등급 엄격 비교의 대가 · §10-h) — 쓰기를 RPC 로 옮기면 칸 단위로 열린다
⬜ 읽기 전용 화면의 Access 표시      staff.html 이 perms 배열 원문을 보여 「등급으로 열린 것」(supervisor 의 전부 등)이 안 보인다 — ims_access().screens 로 그리면 보인다
⬜ 읽기 전용(:read)일 때 입력칸 잠금   지금은 뒷단(RLS · RPC 거부 문장)만 막는다 · 화면은 me.access.screens[x]==='read' 로 잠근다(§10-j 3-l)
⬜ created_by 표시                 staff 화면에 없다(Caleb 2026-09-17)
⬜ ims_is_admin() 을 지울지          이제 아무 정책도 EF 도 안 쓴다(§10-h) · §10-h 「하나뿐이다 · 고치지 마라」 문장과 함께 정리
⬜ 020000 §4 의 카탈로그 중복 정의    023000 이 같은 함수를 다시 냈다 — 적용 전이면 020000 §4 를 지워도 된다 · 적용 뒤면 그대로
⬜ ims-staff-create 가 warehouse_access 를 안 받는다   worker 를 만들면 창고 전부(빈 배열)로 시작 — 창고를 걸 사람은 만든 뒤 staff.html 에서
[2026-09-18 · 리시빙 · 동시 편집 — 오늘 늘어난 것 · 근거는 마이그레이션 일곱의 머리 주석과 §13-i]
동시 편집
⭐⭐ 뒷단은 섰고 화면은 되돌렸다   `20260918133858`(updated_by · ims_touch) + ims-ui.js imsSaved(builder, seenAt, ref)(§10-j 3-i) — 화면(PO 넷)의 seenAt 은 되돌렸다(asung-ims dc0da29). 처방을 바꿨기 때문 — 거부하고 끝내는 것이 아니라 **WMS 모양으로 묻고 고르게 한다**
                              근거: receiver.html 1133~1160 askQtyConflict 「Keep theirs / Use mine / Recount」 · WMS 는 스캔이 델타라 병합되고 **절대값 입력만** 충돌한다 · ⚠️ WMS 는 「누가 바꿨나」를 못 채워 presence 로 후보만 보여 준다(1135 주석) — IMS 는 updated_by 로 채운다
⬜ 리시빙에서 이 모양을 먼저 만들고 그 뒤 PO 화면들로 가져온다
⬜ 취소·삭제의 동시 편집        성립하지만 대가가 작아 미뤘다(취소는 되돌릴 수 있고 삭제는 확정 전 초안뿐) · ⚠️ confirmed_at 게이트는 「확정된 적이 있나」를 볼 뿐 「내가 본 뒤에 바뀌었나」를 안 본다 — 서로 대신 못 한다
⬜ confirm 계열                 문서가 아니라 **자식 줄의 max(updated_at)** 을 봐야 한다(표 단위 트리거의 한계 · 부모 updated_at 은 줄이 바뀌어도 안 움직인다)
⬜ 상세 RPC 넷이 줄의 updated_at 을 안 낸다   줄에 seenAt 을 걸려면 먼저 내야 한다(po_receipt_detail 은 work[].updated_at 을 낸다 — 선례)
⬜ 거부 문장에 「내가 넣으려던 값」이 없다
리시빙
⬜ 차이를 닫는 RPC 와 화면      po_receipt_diff.resolved_by/at · note 는 있다 · 여러 건을 한 번에 닫기 · 닫는 이유 어휘(나눠 보냄 · 결품 · 분실·파손 · 오산)는 그때 정한다(§11-i short 를 담는 이유)
⬜ off_po(PO 밖)               po_receipt_work.po_line_id nullable + product_id + 승인 칸 + po_receipt_line.po_line_id 도 nullable · 차이 큐 off_po 어휘는 미리 있다 · 약식 제품 등록(위 「입고 차수에 셋」)과 한 묶음
⬜ 팩→낱개 환산                지금 work_save 는 낱개 총량을 받는다 · p_entered_qty · p_unit_product_id 로 **DB 가 곱하는** 안(화면이 곱하면 「계산은 DB」를 어긴다)
⬜ 확정 취소                   po_doc_cancel 에 'receipt' 가지(입고 줄·차이·분할을 어떻게 되돌리나 — 사건 차수와 함께) · 확정 전 「그만둔다」는 po_receipt_delete
⬜ po_receipt_line.receipt_id 를 NOT NULL 로   백필(09-16 검증 데이터 4행 · 짐작 — 실측 필요) 또는 정리 뒤
⬜ WMS 이관                    조사가 찾은 것(§13-i): 트랜스퍼 입고 · 창고 접근(warehouse_access 를 리시빙 RPC 가 본다) · 상품 이미지 · 미지 bin · ~~라스트 빈을 원장에서~~(→ ✅ 09-19 ims_last_bin 속 = 원장 · §11-i) · 같은 줄 동시 스캔 병합
⬜ WMS 창고 화면의 화면 값       'receiving' 을 같이 쓰면 카탈로그 room 은 하나라 worker 기본이 안 붙는다 — 값을 따로 둘지(`putaway` 등) 그때 정한다(§10-j 3-l)
그 밖
⚠️⚠️ 크레딧 채번이 PO 번호 접두어를 읽는다   분할로 PO-02011 이 PO-02011a 가 되면 CN-<po> 접두어가 안 맞아 같은 번호가 다시 난다 · 실무는 크레딧이 입고 뒤라 드물다 — 그래도 적어 둔다(§11-c)
⚠️ po 표에 closed_by 칸이 없다   closed_at 만 · 확정 RPC 가 닫는 사람은 po_receipt.confirmed_by 로만 남는다
⚠️⚠️ pre-commit 훅이 IMS 마이그레이션에 걸린다   scripts/check-class-values.sh 가 po_receipt_diff 의 kind CHECK 를 wms_reports.kind 로 오해하고 「검사 불능」으로 커밋을 막는다 · 오늘 --no-verify 로 지나갔다 ⇒ 훅이 wms_* 표만 보도록 좁힌다
⚠️⚠️ psql -f 로 적용하면 이력 표가 안 쌓인다   오늘 db push 가 22개를 처음부터 밀다가 첫 파일 둘째 문장에서 멈췄다(피해 없음 · po 34칸 · ims 정책 104 로 확인) ⇒ **적용할 때마다 `supabase migration repair --status applied <버전>` 을 함께 돌린다**
⚠️⚠️ 이름 서브쿼리 별칭          ims_staff 가 updated_by 를 갖게 되어 별칭 없는 `where id = updated_by` 가 에러 없이 null 을 낸다 — 하루에 두 번(§5 트리거) · 별칭을 반드시 붙인다
⬜ 정본 정리                   3,319행 → 오늘 더 늘었다 · 한 달 지난 절의 과정 기록을 압축한다(결론과 근거는 남긴다)
⬜ 그대로 남은 것              ~~사건(원장 이식 때 · 11-j)~~ → ✅ [09-19] inv_post_receipt(§11-j) · ~~차이 큐(재고조정 때)~~ → ✅ [09-18] 리시빙에 섰다(po_receipt_diff · 닫는 길은 아래) · 파일 업로드(Storage) · 확정 RPC(Latest 갱신) · 계정 후보 규칙 · HST · KRW 계산 · §12 재검토(짐작) · other 줄 할인(11-e) · supplier_discount 편집 화면(§10-k)
[2026-09-19 · 원장 이식 1·2차 — 오늘 늘어난 것 · 근거는 `20260919151601`·`20260919155005` 머리 주석과 ledger-design 4부 「이식」 절]
⬜⬜ inv_post_receipt 가 **create function 이라 다시 못 돈다**   고쳐 다시 밀 때 매번 drop 이 필요하다 — ⭐ create or replace 로 바꿀 것(2026-09-19 실제로 걸렸다)
⬜ 확정 취소                   되돌리는 RPC 가 생기면 **반대 방향 po_in 행을 상쇄로 넣어야 한다**(append-only · 지우지 않는다 · 위 「확정 취소」와 한 묶음)
⬜ 차이를 닫는 길              닫을 때 **초과분을 재고로 넣는 방법** — 기준까지만 들어갔으므로 닫는 순간 나머지가 장부에 들어가야 한다(조정 사건인가 · po_in 추가 행인가 · 그때 정한다 · raw.bins 가 어느 빈에 얼마가 깎였는지 갖고 있다)
⬜ 음수 잔고 229행 원인 규명    원장이 원래 갖고 있던 상태(ledger-design 4부 「이식 시점 기준선」 · 229 SKU · −2,191) · 늘면 새로 생긴 것
⬜ SKU 별칭 표                 SKU 를 고칠 때 옛 이름을 남긴다(원장은 텍스트 축 · 조인이 조용히 끊긴다 · ims_ledger_unlinked 가 그 신호) — 실제로 고칠 일이 생길 때
⬜ shadow 대조에서 source='ims'  inv_balance_vs_cin7 이 IMS 사건을 「원장만 있음」으로 잡는다 — 운영 이식 때 정한다(ledger-design 3부 컷오프 절 ⬜ · 설계는 하지 않았다)
⬜ 데이터 최신화               테스트 DB 의 원장이 2026-09-10 에서 멈춰 있다 — 운영에서 다시 가져온다 · ⚠️ **inv_* 표만** 골라야 한다(09-10 의 통째 복원 방식으로는 IMS 표 서른둘이 날아간다)
⬜ RCV-00005 백필 여부          이식 전에 확정돼 원장 행이 없다 — `select inv_post_receipt('<id>')` 한 번이면 된다(확정된 입고만 받는다 · 시험 데이터면 안 해도 된다 · Caleb 판정)
⬜ receiving.html               confirm 반환 ledger.qty_posted · 경고 ledger_trimmed_to_basis 로 「재고에 n 들어갔다 · m 은 차이 큐에」를 말할 수 있다(대화 Claude)
⚠️ 정본과 부딪히는 문장(고치지 않고 보고 · ims-doc-update-0919 ⬜1)   §3 표 ref_warehouse 「IN_TRANSIT 안 담는다」(담았다) · §11-j 모양 표 「문서 번호 = 갈라진 뒤 PO 번호」(RCV 번호)·「줄 번호 = line_ref」(po_line_id) · §12-a 「inv_snapshot 안 옮긴다」(ims_inv_balance 가 기초선으로 읽는다)·「doc_task_id 는 IMS 에 없다」(po_receipt.id)·「source 는 모듈 이름(짐작)」('ims' 하나)
[2026-09-19 오후 · 차이 닫기 · 원가 이식 1·2차 · 화면 둘 — 근거는 `20260919175712`·`192236`·`200414` 머리 주석과 ledger-design 4부 「원가 이식」]
~~⬜⬜ inv_post_receipt 가 create function 이라 다시 못 돈다~~ → ✅ `20260919192236`(create or replace) · ~~⬜ 차이를 닫는 RPC~~ → ✅ `20260919175712`(short · 화면은 대화 Claude · 여러 건 한 번에는 ⬜)
~~⬜⬜ inv_layer_apply 에 IMS 판을 넣는다~~ → ✅ `20260920142635`(bb519c7 · 테스트 DB 적용·검증 · 입고는 루프 안 inv_layer_post_receipt · 비용은 끝 inv_layer_post_charge) · ⚠️ 옛 문구 「지우고 cin7 만 되살려 통째로 사라진다」는 **틀렸었다** — 실물은 0 원 레이어로 덮어썼고 창구 멱등을 막았다(경위·실측 ledger-design 4부 「✅ 해소 — inv_layer_apply() 에 IMS 판」) · ⬜ 새로: 보조 함수 넷(transfer·adjust·assemble·credit)의 IMS 문 · Cin7 재생성 차이 +1,330(원인 불명 · 상쇄 금지)
~~⬜ over 차이 닫기~~ → ✅ `20260920171930`(f413fe3 · `po_receipt_diff_settle_over` · 이유 셋 free·billed·credited · free 는 0 · 그 밖은 기준 레이어 값 · 창구 둘 `inv_post_receipt_over`·`inv_layer_post_receipt_over` · line_ref `po_line_id:over` · reopen 거부 · RCV-00026 실물로 닫았다 · §11-i 「차이 닫기」) · ⚠️ 옛 문구 「같은 창구 inv_layer_post_receipt」는 틀렸었다 — 기존 창구는 기준까지만을 스스로 잘라 그대로 못 쓴다
⬜ billed 초과분의 landed        `inv_layer_post_charge` 가 `:over` 레이어를 못 본다(`pl.id::text = x.line_ref`) — free 는 안 얹는 것이 맞고 billed 는 논의 여지 · ⬜ over 되돌리기 = 상쇄 사건 길(지금은 거부)
⬜ 크레딧 설계                   수량(제품·개수가 붙는다) vs 가격(차액만) — 표본이 생기면(11-g 「매입 가격 이력」)
⬜ supplier_discount 0행         ⚠️ po_create 가 이미 읽는다 — 「채우면 듣는다」(주석 실물). 안 채우면 발주 원가가 할인 전 값으로 선다 · [실측 09-20] fixed 3.09 vs 실제 2.54 = 21.7% 차이 · ⭐ 세 줄이 전부 정확히 21.7%(= 1 ÷ 0.8217) — 값이 오른 게 아니라 할인이 안 잡힌 것 · 📌 Ampro 실물은 17%→1%→3% 인데 AMP-778812 에는 둘뿐이다 — 왜인지 모른다
⬜ latest·fixed 갱신을 IMS 가 맡는다  ⭐ 출처는 **인보이스**(`po_price_history` · 11-g) · ⚠️⚠️ 공짜·초과분(over free)을 가격으로 세면 안 된다 · [실측] product_supplier 에 쓰는 DB 함수 **0개**(po_lines_paste 는 읽기만 · writes_it f) — 11-d 「PO 확정이 갱신한다」는 만든 적 없는 설계 문장이었다
⬜ 「우리가 쓸 물건」(is_payable false ⓐ)  재고로 들어가는 길이 있나 — 모른다(11-g)
⬜ 비용 취소와 landed            po_charge 가 confirmed 뒤 cancelled 되면 landed 가 남는다 — 상쇄가 필요하다(취소 RPC 에 「얹혔으면 거부 또는 상쇄」)
⬜ 발주 머리의 Tax rule          ref_tax_rule 을 Settings 에 세운 뒤 드롭다운으로(⭐ QBO 가 우선 · 11-b 머리 칸 편집)
⬜ 환율                          MTFX 환율 자동 수신(API 유무 확인 중) · USD 발주 10건의 빈 환율 채우기 · ~~RCV-00005·00006 백필~~(✅ 09-20 · 테스트 값 1.35 · 레이어만 섰다) · 관세 10039192310530 백필(PO-02002·02001a 입고 뒤 inv_layer_post_charge)
⬜ Add a line 셋째 재료           po_line.unit_price 가 쌓이면 「우리가 지난번에 적은 값」(11-d)
⬜ 아침 점검                     no_basis_amount_cad · no_layers_amount_cad 합을 보는 한 줄(Cin7 대조의 「설명된 차이」) · 차이 큐 닫기 여러 건 한 번에 · [09-20 +둘] `po_price_history_skipped` 의 reason <> 'charge' 가 0 인지 · `inv_layer_apply()->'ims'->'skipped_by_event'` 가 전부 0 인지(0 이 아니면 그 사건의 창구를 만들 때)
⚠️ 회계사에게 물을 것이 다섯      (레포 밖 accountant-questions-0919.md) ① kind → QBO 계정 대응 ② 에이전트 수수료가 재고 원가인가 ③ 환율 시점과 차액 처리 ④ 초과 입고분의 원가 ⑤ 조기결제 할인 HST · 뒤늦게 붙는 원가 차액
```

---

## 9. 경위

- 2026-09-11 오전 — ① Settings 순서 확정(Caleb) · 테스트 DB 에 마스터 표 0개 확인(47개 표 전부 `inv_*`·`wms_*` ·
  `wms_sku_snapshot`·`wms_sku_bins`·`inv_sku_types` 는 Cin7 캐시라 마스터가 아니다) · GAS 프로브 3회.
- `20260911144606` brand·category·unit — §2 확인 뒤 Caleb 판정 셋: DELETE·TRUNCATE 막는다 · `updated_at` 트리거 · `name` 유니크 plain.
- `20260911161647` payment_term — `Duration` 함정 확인 · 값은 손으로.
- `20260911162906` account — 자연키 `code` · `name` 유니크 없음 · `inv-cost`/`inv-doc-cost` 필터 무접촉.
- `20260911164513` currency — 앞선 넷과 갈리는 셋(`cin7_id` 없음 · `manual` · 형식 CHECK) · 값 2행 + `inv_config` 1행.
- `20260911165946` warehouse·bin — `ref_` 표 사이 첫 FK · 기존 FK 22건 관례 실측 뒤 `no action` · bin Name 정정 발견.
- 같은 날 — 이 정본 · `asung-po` 스킬 신설 · `cin7-api` 정정(§8 location 정정 반영).
- 2026-09-12 — ② 공급처 표 넷(`20260912202952`·`210733`·`212150`) 설계·적재. 당시 §7-b·§7-c 로 적었다.
- 2026-09-13 — ③ 제품 전량 실측(18,829 · family 1,141) · 설계 검토. **하루에 판단이 넷 뒤집혔다**: ① 모집단 14,677→18,829 ② 자리 슬롯은 미사용(Caleb)
  ③ 표본 20으로 BOM 축을 뺄 뻔(진짜 조립 15) ④ ⭐ `parent_product_id` 의 출처가 접미사뿐이었다(검토에서 발견 · BOM 구성품으로 정정).
  같은 검토에서 「기본 제품 13,888」 산술 오류 · `IncludeSuppliers` 「미확인」 오기 · §3 「접두어가 갈린다」 오기를 잡았다.
  ⚠️ **셋째 부류** — 「없다」「안 봤다」를 가르라고 해 놓고 **「이미 있는데 안 찾아봤다」**(Productmaster.js)를 놓쳤다. 다음부터 「없다」고 적기 전에 GAS 레포를 grep 한다.
  **문서 이사** — §7-b·§7-c 를 §3-b·§3-c 로 옮겼다(본문 무변 · 번호와 상호 참조만). ④⑤ 전이 가장 싸다. §7-a(범위 판단)는 위험 목록에 남긴다.
  ~~표는 아직 만들지 않았다 — 프로브 1·3·4 대기(§3-d).~~ 같은 날 저녁 — 2차 실측(`ProbeProductBom.gs`)으로 셋을 결판(pack_factor = BOM Quantity ·
  parent = ComponentProductID · 관계 없음 4,161 · 재주문점 전부 0) · **마이그레이션 넷 생성 · 로컬 재생 통과**(`20260913225935`·`230500`·`230600`·`230700`) ·
  `AMP41108-12` 는 접미사가 틀린 것으로 확정 — `asung-inv-ledger` 반대 기록 정정 · 「세 축 6건」은 2,405 로 정정. 테스트 DB push · 적재 GAS 는 다음.
- 2026-09-14 (토론토 오전) — ③ 제품 표 넷 테스트 DB `db push` · **전량 적재 36,924행**(1,141 / 18,714 / 17,104 / 65 · §3-e). 카운터 넷 + 관계 표 고아를 DB 에서 SQL 로 재확인 — 전부 0.
  ⚠️ **실사고 셋**(upsert 로 부분 갱신 → 23502 · 「건너뛰는 요청」 709건에 4분 · 이어받기마다 Cin7 재훑기) — 뿌리는 **요청 하나하나의 비용을 계산하지 않았다.**
  `asung-wms` 규칙 45·46 신설(PostgREST 함정 — 규칙 29·20 계열이라 그쪽) · `asung-po` ③ 갱신 · `cin7-api` `GET /product?Sku=` 실측 · 스크립트 사본 `docs/probes/ImsLoadProduct.gs`. 운영 DB 적용은 아직.
  오후 — 바코드 중복 38 은 대체 UPC 적재 **전**의 수였다 → 전체 42 · ⭐ **활성끼리 23 이 카운터 ⑤**(무관 6 · 색상 12 · 세트 5 · Caleb 지적) · `asung-po` 스킬 15,174 → 14,000 바이트 아래로 감축(숫자·칸 목록은 정본으로) · §7 에 「Cin7 SKU 변경 시 충돌 키」 메모.
  오후 — **재적재 방식 §3-f**: 초안 「바코드·BOM 은 source=cin7 지우고 다시」가 `valid_from`·`note` 주석과 충돌(검토 지적)해 폐기 → **넷이 한 규칙**(upsert + 안 들어온 cin7 행 is_active=false · 되살아남은 upsert 가 저절로). §3-c 「사라진 행 감지」도 ⓒ 로 닫고 §3-f 를 가리킨다. SKU 변경 항목은 발동 조건 없음(Caleb · 남은 정리는 바코드뿐).
  오후 — **④ 제품↔공급처 §3-g**: `ProbeProductSupplier.gs` 전량 실측(12,728줄 · 비활성 공급처 31곳 · 기본 공급처 표시 없음) · 설계 검토에서 넷이 바뀌었다(충돌 키 cin7_id + manual 승격 · is_default 후보는 활성만 · 12,729 는 두 모집단 혼합 · ② 단계에 GET /supplier 전량) ·
  `20260914175145_product_supplier.sql` 로컬 재생 통과. `cin7-api` Suppliers 절 정정(IncludeInPricing · LocationName · Default 없음 · IncludeSuppliers Limit 1000). ~~적재는 다음.~~
  저녁 — **④ 적재 완료**(12,728줄 · 활성 12,721 · supplier 226→257 · is_default 11,480 · 카운터 여섯). Caleb 이 Cin7 에서 세트 셋·콤보 넷의 잘못 붙은 줄을 지웠다(`AS92082-6` FixedCost 0.95 = 낱개 값 복사).
  ⭐ **콤보에 방향이 둘**(묶는 8 · 사 오는 3 립오일)이 드러났다 — Cin7 은 AutoAssembly 15/15 true 로 뭉뚱그렸다 · 방향 칸은 ⑤ 에서(부모당 하나) · 발주 후보 규칙은 「공급처 줄이 있으면 후보 · 세트는 예외」.
  검토에서 바뀐 것: 카운터 ⑤를 세트(0 목표)·⑥ 사 오는 콤보(기대 3)로 가름 · is_default 끄기에서 manual 보호 제거 · 780 의 분해 정정(778+2). 실사고: is_default 를 켜기만 함 · 시트 경유 날짜 소멸 · 「내가 만든 라벨」을 실측으로 믿음.
  오후 — **화면 준비 §10**: `ims.asung.ca` 신설(GoDaddy CNAME · `asungtrading/asung-ims` · Pages · HTTPS) · `wms.asung.ca` 에 올리지 않은 이유는 동료 비공개(사람 문제) · 레포는 공개 유지 —
  ⚠️ 초안의 「private 이면 Pages 가 죽는다」는 추론을 실측처럼 적은 것이라 정정(규칙 12 의 8-19 실측이 맞다 · Visibility 만 Enterprise) · `purchasing.html` 읽고 「붙이지 않는다」 확정(GAS 브리지 재사용 각주) ·
  검토에서 드러난 구멍: **Asung-IMS 가입이 열려 있으면 「계정 있는 사람만」 방어가 없다** → 배포 전 확인 항목. 다음은 IMS 로그인(가입 닫기 → Add user → 사용자 표).
- 2026-09-15 (토론토 오전) — **`ims_staff` 신설 §10-h**(`20260915141105` · 로컬 재생·RLS 실동작 통과). 검토에서 바뀐 것 셋: 열쇠를 이메일 → **`auth_user_id`(auth.uid())**(WMS 의 대소문자 함정 회피) · RLS 를 **`security definer` `ims_is_admin()` + 정책 셋 + delete 닫음**(재귀는 select 정책이 자기 표를 읽을 때만 — 실측) ·
  **첫 admin 절차**(초안에 없었다 · postgres 로 insert · §10-f ②-b). 기각된 안 「auth_all + 화면 게이트」를 남겼다. §10-f ⓪ 가입 닫기는 Caleb 확인으로 ✅(다섯 설정).
  오후 — **첫 쓰기 `staff.html` + EF `ims-staff-create` §10-i**(caller JWT 로 rpc/ims_is_admin · 레포가 둘로 갈린다 · config.toml 블록 · 「원본도 verify_jwt=false」는 확인 없이 적은 것 → 블록이 아예 없었다) · 배포·계정 생성 실측 ✅ · URL Configuration 기본값 실사고(§10-f ⓪-b).
  **읽기 화면 다섯**(Settings·Suppliers·Products·Families·Supplier Products) → §10-j 화면 공통 규칙 신설 · §10-k 채울 칸 · 공통 파일 ims-ui.css/js 로 다섯을 옮김(3-g) · 상세 비우기 규칙 교체(3-d · 「목록에 없으면 비운다」 폐기) · 점검 목록 `asung-ims/CHECKLIST.md` 신설(3-h).
  정정 셋: 캡 넘는 표 「둘」→넷 · 「색은 is_active 에만」이 한 화면에서만 참 · 「Purchasable 217」은 어림값(실측 161). 실사고 셋: ?id= 진입 · 화면 안 SKU 이동 · 시각이 UTC(imsTs).
  저녁 — **`suppliers.html` 에 is_purchasable 쓰기**(IMS 둘째 쓰기 화면 · 드롭다운 넷 · 상세에서 고르면 바로 저장 · 10,899 → 18,151 · 커밋·브라우저 확인 다섯 통과 · Caleb).
  검토(Claude Code)에서 **실제 버그 셋** — 저장 실패 시 되돌리기 없음 · 목록 재읽기를 seq 로 함께 막음(재현되지 않는 증상) · 저장 중 경합 → **§10-j 3-i 쓰기 화면 공통** 신설의 근거.
  ⭐ **§10-k 의 40 은 전체 기준이었다** — 활성 9 는 §3-c·§8 에 이미 있었는데 잇지 않았다(두 모집단을 섞어 센다 · 내 문서의 숫자를 내가 안 본다). Caleb 판단 — 비활성 31곳은 판정 대상이 아니다.
  SQL 실측으로 스키마(nullable · default 없음)·트리거·권한(UPDATE 살아 있음)을 확인 — 짐작이었던 셋이 전부 맞았지만, 틀렸으면 설계가 깨질 자리였다. product_supplier 12,728(전체)/12,721(활성)도 SQL 로 확인.
  ⚠️ 참조 오류 — 지시서가 인계 문서의 §3-b ⑦ 을 「정본 §3-b ⑦」이라 적었다. Claude Code 가 grep 으로 잡았다(정본에 ⑦ 없음). 문서 이름을 흐리게 적지 않는다.
  저녁(집) — ⭐ **⑤ PO 본체 설계를 열었다 — §11·§12 가 그 결과**(판단만 · 표 정의 없음 · 지시서 `~/asung/prompts/po-module-design-session.md`).
  Caleb 이 다시 못 박은 것: IMS 는 Cin7 과 무관한 시스템(Cin7 은 데이터 소스) · 지금은 엮는 시점(제품→PO→SO 고리) · 작은 작업에 매몰되지 않는다 ⇒ **§10-k 는 지금의 우선순위가 아니다**(예외 제품 생성 §11-k).
  컷오버 상이 선명해졌다 — 연습 기간에 실제로 다 돌려 보고(IMS 리시빙은 테스트 리시빙 · 창고는 그대로), 컷오버 때 **거래를 지운다 · 마스터만 남긴다**(§2 「리셋」의 뜻 · 표마다 「지워지는가」 축).
  핵심 판단: Purchase 하나 · 확정=잠금(결재 아님 · → 09-16 오후 정정: **잠금 아님** · §11-b) · **부분입고는 문서가 갈라진다**(받은 쪽 a · 원본 번호는 남지 않는다 · 자동 분할·수동 취소) · 라인은 낱개 저장+입력 단위 기록 · 할인은 문서 위 줄(금액 비례 · 잔돈은 가장 큰 줄 · 동점 SKU 순) ·
  비용·인보이스는 자기 행으로 서서 PO 여럿을 가리킨다 · 결제는 IMS 가 든다(분개는 QBO) · 입고는 인보이스를 안 기다린다 + 풋어웨이까지 · 초과·부족은 WMS 규칙 20 그대로 · PO 는 원장을 부르지 않고 사건을 낸다.
  원장·원가는 IMS 로 **복사해 옮긴다**(운영 shadow 는 그대로) — PO 를 먼저 끝내고 옮긴다 · 표 21 분류(§12-a) · 늦게 오는 원가는 `inv_layer_cost_add` 로 이미 풀려 있었다 · 회계사 질문 둘로 모음.
  ⚠️ 대화 Claude 의 잘못 셋: ① Cin7 을 축에 놓고 「IMS 가 Cin7 에 밀어 넣는다」·「IMS 리시버가 창고 화면이 된다」로 두 번 끌고 갔다 ② 「제품 등록은 컷오버 근처」를 정본 내용처럼 말했다 — 내가 얹은 것이다 ③ 「인보이스 확정 → 미지급」을 빠뜨렸다(Caleb 이 짚었다).
  검토(Claude Code)에서 정정된 것 일곱: 제품 적재의 충돌 키는 지금 **sku** 다(cin7_id 는 ④ 만 — §11-k 에서 결정으로 올림) · 환산값은 product_supplier 가 아니라 product.pack_factor · 원장 유니크 키는 일곱 칸 · 원장 표는 30 이 아니라 21 · ledger-design 에 §13 절 없음(3부 소제목) ·
  「PO 모듈부터 병행 트랙」 문구는 정본에 없음 · §3-f 「구현이 다르다」는 「아직 구현 전」 + 비활성 두 갈래(Status / 부재). 검토가 어긋남으로 든 §10-d·§3-g 「⑤ 가 Cin7 에 PUT」은 **부딪치지 않는다**(Caleb 확인 · purchasing.html 791~848행 Fixed Price 인라인 수정을 옮길 때의 이야기 · 마스터 층 · 전환 기간 한정 — §11-⓪). ⬜ 표 설계 때: 단가는 두 자리(라인 단가=이번 발주만 · Fixed Price=마스터)로 갈리고 다르면 표시한다(§11-d · Caleb 실측).
  ⚠️ 문서 작업 방식 조정(Caleb): 문서는 **필요한 경우와 작업의 말미에** 한다. 코드 한 줄마다 검토를 태우지 않는다.
- 2026-09-16 — **⑤ PO 표 ①차(넷 · `20260916144201`) · ②차(일곱 · `20260916153313`) — 테스트 DB 적용 · 커밋 8a27edd · 37be987 · §13.** 파일 하나씩(Caleb — 마이그레이션은 적용되면 고치지 않고, FK 로 묶인 표는 함께 서야 뜻이 있다) · 트리거 없음 · 전부 거래(컷오버 때 지운다).
  ⭐ **실물 검증(Caleb 이 SQL 로)**: 발주 → 부분입고(두 빈 분할) → 문서 분할(a/b) → 인보이스(운임 줄 포함) → 비용(두 발주에 걸침) → 결제(조기결제 할인) → 미지급 0. **열한 표가 이어진다.**
  증명된 것 넷: 할인 체인 차이 4.68 · received_qty 없이 합으로 됨 · total_amount 대조값이 −253.90 을 드러냄 · is_payable 없으면 운임 187 이 영원히 미지급.
  ⭐ 검토(Claude Code)가 잡은 것: 거래 표는 마스터 규약 대상이 아니다(cin7_id·source·is_active·name 뺌 · §5 예외 블록) · 할인 두 층(예상/확정) · po_line_id nullable + line_kind · is_payable · **결제가 비용 문서도 가리킨다**(합의 밖 판단으로 냈고 Caleb 이 확정 — 「결제는 인보이스 여럿을 가리킨다」에서 비용 문서를 빼놓은 것은 대화 Claude 의 누락) ·
  「입고가 끝나도 바로 안 닫는다」가 두 곳(11-b·11-f) · Service 53 「담을 자리」가 세 곳(§3-d·§7·11-f) · 비용 배분 잔돈의 동점 기준(발주 단위엔 SKU 가 없다 — 11-e 를 옮기며 놓침).
  ⭐ Caleb 판단으로 닫힌 것: 연결은 바로 앞(split_from_id) · PO-02000 부터 · **closed = 입고 종료**(국내 발주는 비용이 없다) · 배분 금액은 박아 두고 재계산 없음 · Latest 는 연습 기간에도 갱신하되 적재가 덮는 것이 정상.
  ⭐ 실측으로 닫힌 것: `for_payments` 는 결제 계좌 필터가 아니다(23 중 7 카드 · 나머지 비활성 기본 계정 · 실제 은행 계좌 셋은 밖) · Cin7 결제는 은행과 연결되지 않는다(QBO 가 fund 매칭) · Service 53 을 담을 자리는 필요 없어졌다.
  ⚠️ §12 재검토(짐작): 테스트 DB 에 inv_*·wms_* 시퀀스가 전부 있다 — baseline 통째 적재로 보인다. 「복사해 옮긴다」가 틀린 전제일 수 있다. 표 존재 미확인 · 확인 SQL 은 §12-a 에 · 다음 세션.
  ⚠️ 대화 Claude 의 잘못: 「결제는 인보이스 여럿을 가리킨다」에서 비용 문서를 빼놓았다 · 「바로 안 닫는다」·「Service 자리」 문장을 한 곳씩만 짚었다(같은 문서에 옛 규칙과 새 규칙이 함께 남을 뻔 — 어제 CHECKLIST 와 같은 모양) · 11-e 잔돈 규칙을 발주 단위에 그대로 옮겼다.
  📌 검증 데이터는 지우지 않는다(Caleb) · po_number_seq 2002 까지(저녁엔 2007). ~~다음: 화면(발주 작성·입고·인보이스·결제) · 분할 함수 + 잠금 트리거 · 확정 RPC(Latest 갱신).~~ → 오후에 화면·크레딧·쓰기가 섰다(아래) · 잠금 트리거는 없어졌다.
  오후 — **크레딧 노트(§11-g 소절 신설 · `20260916175003` · 3be9a86 13:54) · 읽기 뷰 po_list·RPC po_detail(`20260916163806`·`164539` · 68aefa0 12:47) · 쓰기 RPC 넷(`20260916181719` · 540e518 14:28) · 화면 po.html(asung-ims 36c1fc2 → 4ae86d6 → 0e23369 → 609297c → d376907 · 읽기 → 크레딧 → 만들기·편집 → 수정 둘)** — 전부 §13-d.
  ⭐⭐ **§11-b 정정 — 확정은 잠금이 아니다.** 「공급사에 보낼 수량과 라인이 정해졌다」는 뜻(Caleb 실측: 확정 뒤 수량 추가·세일 품목 추가가 빈번). 설계 대화가 「결재 아님」에서 「잠금」까지 끌어낸 비약을 실무가 바로잡았다. 잠금 문장 일곱 곳(§5 · §11-b 셋 · §13 둘 · §9) 정정 · 막는 둘만 RPC(po_line_update/delete).
  ⭐ **Fixed Price 는 IMS 에서 고치지 않는다** — 전환 기간 정본은 Cin7 하나(Caleb 「우리가 개별로 가격을 수정하면 되니까」) ⇒ §11-d ⬜ 둘 닫힘(어느 쪽을 고치나 · Fixed/Last 옵션) · §11-⓪·§3-g·§10-d 의 PUT 문장도 정정(전환 기간엔 PUT 이 없다 · cin7_id 충돌 키 판단은 그대로).
  크레딧: 별도 표 아님(doc_kind) · 양수 · credit_for nullable · 줄은 po_invoice_line 그대로 · 할인 자동 복사 없음 · 유니크 셋 · 다른 행 제약은 RPC warnings · [실측] unpaid −30.90 = 받을 돈(결함 아님 · 화면 「credit due」).
  읽기: 목록은 뷰(security_invoker) · 상세는 RPC · **계산 규칙의 정본은 RPC**(→ 저녁: 문서 돈은 뷰 둘 · 13-g) · 곱 집계 po_mul(exp/ln 은 임시였다) · factor 표시 6자리 · 금액은 원래 factor 로. 쓰기: 일이 여럿이면 RPC · 미리 보기 필수 · 판정 여섯 · 500 은 판정 · created_by 서버 유도.
  ⚠️ 실사고 셋(§13-e · 문법 검사로 안 잡힌다): text[] || 리터럴(malformed array literal · 판정에 따라 되고 안 됨 · array_append · 같은 파일 재적용) · JS 선언 전 읽기(TDZ · 「Loading…」이 영원히) · 오류 자리가 없어 진짜 오류가 가려짐(alert 로라도). 곁가지: 브라우저 줄 번호가 파일과 안 맞아 배포본을 cmp 로 대조.
  ⭐ 검토(Claude Code)가 잡은 것: 할인 두 층 · po_line_id nullable · is_payable · 결제가 비용 문서도 가리킨다 · warnings 로 못 하는 이유(수량 감축과 초과 입고가 같은 모양) · 곱 집계 · security_invoker 선례 · 커밋 순서(읽기가 크레딧보다 먼저) · 잠금 문장 일곱·Fixed Price 문장 셋(지시서는 둘·하나만 짚었다) · 쓰기 RPC 주석이 확정의 뜻 한 판 앞.
  ⚠️ 대화 Claude 의 잘못: 확정=잠금 비약 · 잠금 문장을 둘만 짚었다(같은 문서에 옛 뜻과 새 뜻이 함께 남을 뻔 — 어제 CHECKLIST · 오늘 오전 「담을 자리」와 같은 모양 · 세 번째) · 커밋 순서를 틀리게 적었다.
  📌 다음(§13-f): 목록 두 모드 + 국면 다섯(po-list-wide.md) · 머리 칸(required_by · 그날의 연락처·주소) · 검색은 공급처·날짜 · 캐럿 확장 · 인보이스·비용·크레딧 만들기(자동 채우기) · 분할 함수(원래 수량 · 할인 줄 복사) · 메일.
  저녁(집) — **넓은 목록·국면 다섯·머리 칸 15(`20260916190000` · e62d16a 18:37 · 화면 po.html 749bd5f→54fefb0) · 인보이스/크레딧 만들기와 할인 편집(`20260916200000` · 160430b 19:52 · ⭐ 화면 `invoices.html` 신설 a867578→ccb58a1 · ims-auth.js 메뉴 Invoices · CHECKLIST fc718d9) · 크레딧 자동 번호(`20260916210000` · 0b4a6aa 20:48 · 화면 bbea8a9)** — §13-g · §13-h · §11-c 크레딧 번호 · §11-e 쓰기 · §11-g 만들기.
  ⭐ **크레딧은 우리가 먼저 만든다**(리시빙에서 못 받은 것을 돌린다 · Caleb) ⇒ 번호는 우리 것(CN-<po> · 첫째 꼬리 없음 · 조정은 CN-<연도>-<n> 전역), 공급처 번호는 참조(supplier_ref_number · 갈아치우지 않는다). 채번은 「최대 꼬리 + 1」 · 취소 포함 · credit_po_id 는 채번의 축(11-g 예외) · 레포 첫 advisory lock.
  ⭐ 청구 국면은 금액이 아니라 수량으로 — 금액으로 재면 다 청구됐는데 영원히 「일부」가 된다(검토 Claude · Caleb 「맞다」) · 주문 국면은 상태가 아니라 사실로(취소는 판정을 바꾸지 않는다 · Caleb) · ⭐ 미지급은 문서 기준 — 세로로 더하면 두 번 센다(주석과 화면 둘 다에).
  ⭐ 인보이스 줄은 미청구 수량(입고는 0 이 많고 주문은 둘째 장에서 이중 청구) · 할인은 복사 제안(11-e 에 이미 있었다) · 총액 안 주면 0(계산값을 넣으면 대조값이 사라진다) · ⭐ 인보이스 확정 = 장부에 받아들였다(발주 Confirm 과 다르다 · draft 만 편집 · reopen 은 결제 없을 때) · 돈 식의 정본은 뷰 둘로(지금이 옮길 때).
  ⭐ 그날의 연락처·주소는 원문만·FK 없음(정리를 막는다) · inventory account 는 회사 기본값(제품은 1곳 _58_) · 드롭십은 bin_id NOT NULL 이 막아 미룸.
  ⭐ 검토(Claude Code)가 잡은 것: 크레딧 자동 채우기의 **화면 길 누락**(가장 큼) · po.html Kind=Credit 잠김 · 크레딧 행 열 뜻 · 두 단계 · 인보이스 목록 뷰 누락 · 「정본은 RPC」 세 곳 · 「머리에 PO 칸 없음」 예외 · 13-a 파일·커밋 수와 seq 2007 · main.stack.
  ⚠️ 대화 Claude 의 잘못: §11-e 에 이미 있는 「복사 제안된다」를 「미결」이라 적었다(정본을 안 보고 지시서를 썼다) · 크레딧 자동 채우기를 뒷단에만 만들고 화면에서 닿을 길을 빼먹었다 · 선언 순서를 하루에 두 번 틀렸다(13-e ④) · 「1180 행」을 세 번 보고했는데 어느 커밋에도 없었다.
  ⚠️ 「잠금」이 일곱 곳 · 「담을 자리」가 넷 · 「정본은 RPC」가 세 곳이었다 — 한 곳만 고치면 옛 뜻과 새 뜻이 함께 남는다. 문서를 고칠 때 **같은 모양을 grep 으로 훑는다**(이 저녁분도 그렇게 했다).
  📌 다음(§13-f): ⬜⬜ 무효로 만들기(내일 회사에서 먼저 · Caleb) · 비용 만들기·배분·목록 · 결제(한 결제 = 한 통화) · 입고+분할(PO 자동 닫힘 · 입고에서 크레딧) · 주석 영어(정본 언어 먼저) · 화면 잡일.
- 2026-09-17 (회사·집) — **취소·삭제(`20260917100000` 5355033) · 비용 문서(`20260917150000` 38f1098) · 인보이스 줄별 수량(`20260917170000` 0184260) · 결제(`20260917190000` db36acd)** 뒷단 넷 + 화면(asung-ims): charges.html · payments.html 신설 · po.html/invoices.html 손질(문서 사이 이동 · + credit · 줄별 수량 · Add a charge · Pay) · 공통 CSS ⑤(af06c61) · 구매 탭(9dcee4d · db4841e).
  ⭐ 판정 축은 confirmed_at(발주도 · Caleb 이 검토안을 뒤집음 · 11-b) · ⭐ 크레딧은 삭제 금지(채번이 행을 읽는다 · 검토 이견 5 를 뒤집음 · 11-c) · ⭐ 비용 배분은 고친 줄만 · unallocated ≠ 0 은 확정 거부 · 통화 폴백 없음(11-f) · ⭐ 한 결제 한 통화를 뒷단이 · 공급처는 강제 안 함 · ref_account 무변(11-h) · ⭐ 시그니처가 바뀌면 drop + create(§5).
  ⭐ 검토(Claude Code)가 잡은 것: 입고 붙은 발주가 PostgREST 로 취소되던 길 · Reopen → 삭제 뒷문(크레딧 금지로 닫힘) · 살아 있는 po_invoice_create 정의가 200000 이 아니라 210000 · replace 가 오버로드를 만드는 것 · main/.pobox input 충돌 · 지시서의 크레딧 누락(결제).
  ⚠️ 대화 Claude 의 잘못: 결제 지시서에서 크레딧을 빠뜨렸다 · §13-b 2868행을 「오기」로 단정했다(데이터가 움직였을 가능성을 안 봤다 · 검토가 바로잡음) · 지시서의 「1.49」는 1.45 였다.
  📌 다음(§13-f): 확정 뒤 머리 칸 잠금(셋 한 차수) · 크레딧을 결제에 · 입고+분할(PO 라인 없이 받는 길 · 약식 제품) · payments 만들기 창 재설계 · .pick/.prow · .ims-nav CSS · po.html --ims-tabs-h.
- 2026-09-18 — **리시빙(§13-i · §11-i · §11-c)** — 마이그레이션 일곱 `20260918133858`(updated_by · ims_touch · f288ee8) · `161537`(표 셋 · ims_last_bin) · `163552`(2-a RPC 여덟 · 38527e7) · `165934`(Receiving 탭 ims · 9f58d40) · `173042`(unassign · e1c7115) · `174428`(split placed · b2adcb5) · `203805`(⭐⭐ 확정 · 차이 큐 · 자동 분할 · 0f50a7e) · 화면 receiving.html(대화 Claude) · asung-ims ims-auth.js Receiving 다섯째.
  ⭐⭐ 방향 전환(Caleb) — WMS 리시빙을 복사해 오는 여섯 차수 → **WMS 이관을 미루고 IMS 안에 PO 갈래의 리시빙을 먼저 세운다**(조사가 「없는 것에 걸리는」 자리를 찾았다 · 1번 철칙은 그대로 · 조사 결론은 §13-i 에 압축).
  ⭐ 판단: 표 셋·두 단계 · 빈 없는 줄 = 미배정 나머지 하나 · 같은 빈은 병합 · 빈을 고르는 순간 놓인 것 · 기준은 PO 확정 수량(인보이스는 표시만) · 빈 없는 줄이 있으면 확정 거부(빠져나갈 길을 문장에) · 차이 큐 셋(short 를 담는 이유 — 분할은 「왜」를 안 본다) · received_by 는 놓은 사람 · 분할 번호는 알파벳을 잇는다 · 0 라인은 행을 옮긴다 · po_receipt_confirm 은 security definer 예외 하나.
  ⭐ 검토(Claude Code)가 찾은 것: set_updated_at 은 IMS 만 썼다(지시서의 「WMS 도」가 틀림) · receiving.room 을 옮기면 worker 기본이 닫힌다 · split 의 새 줄이 false 라 PLACED 0 · 확정이 purchasing 표에 쓴다(definer 근거) · 0 라인 삭제는 인보이스 FK 에 막힌다(행 이동으로) · 크레딧 접두어가 분할에 흔들린다 · 별칭 없는 이름 서브쿼리 null.
  ⚠️ 실사고: pre-commit 훅이 IMS CHECK 를 오해(--no-verify) · psql -f 적용 뒤 이력 표 빈 채로 db push(repair 로) · 검증에서 po_receipt_create 재호출로 뒤가 깨짐(RCV-00005 로) · 별칭 null 두 번.
  ⚠️ 정본과 부딪힌 것(고치지 않음): §13-f 「원래 주문 수량을 라인에 남긴다」 — 오늘 분할은 그렇게 하지 않았다(§13-i 끝 · Caleb 판정 대기).
  📌 다음(§13-f): 동시 편집 화면(WMS 모양 · 리시빙 먼저) · 차이 닫기 RPC·화면 · off_po · 환산 · 확정 취소 · receipt_id NOT NULL · 훅 좁히기 · 머리 잠금 · 크레딧을 결제에.
- 2026-09-19 — **⭐⭐ 원장 이식 1·2차(§11-j · §11-i · §13-a·d·f · 정본 ledger-design 4부 「⭐⭐ 이식 — 원장이 IMS 안에서 선다」)** — 마이그레이션 둘 `20260919151601`(162행 · 축 잇기 · IN_TRANSIT · source 'ims' · ims_inv_balance · ims_ledger_unlinked · ims_last_bin 속 = 원장 · 커밋 49faf5d) · `20260919155005`(450행 · ⭐⭐ inv_post_receipt 창구 · po_receipt_confirm ⓔ · po_receipt_list open_diffs · 커밋 2d2219b). 화면 무접촉 · 운영 DB 무접촉.
  ⭐ [Caleb] 「원장은 심장이다 — 그 심장을 IMS 에 이식한다」 · 이식이지 데이터 최신화가 아니다(테스트 DB 원장 09-10 정지) · 재기준선도 플립도 아니다.
  ⭐ 판단: 원장은 텍스트 · 뷰가 잇는다(FINAL-SALE 이 근거) · 잔고를 다시 정의하지 않는다(inv_balance 하나) · 초과는 기준까지만 · basis(기록) ≠ cap(깎기) · 수량 큰 빈부터 · 멱등은 말하는 0 · 창구는 invoker(§5 예외를 늘리지 않았다).
  ⭐ 검토(Claude Code)가 잡은 것: 잔고 정의 중복 방지(inv_balance 위에 얹기) · bin 조인은 (warehouse_id, name) · 기준은 po_receipt_diff.expected_qty 에서(분할 시점 함정 회피) · 비활성 bin 후보 제외 · 창구는 ⓓ 뒤(확정된 입고만 · 갈라진 뒤 번호).
  ⚠️ 실측으로 뒤집힌 것: 지시서의 「purchase line_ref = ProductID(888행)」 — Caleb 이 TDX70301(세 PO · 세 line_ref)로 라인 id 임을 확정(대화 Claude 의 09-04 정정은 조립·트랜스퍼 축이었다) · 검증 ⑤ 에서 short 의 raw.basis 가 10 으로 남아 basis/cap 을 갈랐다.
  ⚠️ 정본과 부딪힌 것(고치지 않음 · §13-f 09-19 블록 끝): §3 표 ref_warehouse 「IN_TRANSIT 안 담는다」 · §11-j 모양 표 두 줄 · §12-a 세 문장.
  📌 다음(§13-f 09-19 블록): create or replace · 확정 취소 상쇄 · 차이 닫기와 초과분 · 음수 229 · 별칭 표 · shadow ims · 데이터 최신화(inv_* 만) · RCV-00005 백필 · 화면 ledger 표시.
- 2026-09-19 오후 — **⭐⭐ 차이 닫기 · 원가 이식 1·2차 · PO 화면 둘(§11-b·c·d·f·i·j · §13-a·d·f · 정본 ledger-design 4부 「원가 이식」)** — 마이그레이션 셋 `20260919175712`(420행 · 차이 닫기 short · 이유 어휘 다섯 · 형제 합계 po_family_* · 9a5344a) · `192236`(538행 · 입고가 레이어를 만든다 · cost_source po_line · 환율 게이트 · b09a4c0) · `200414`(280행 · 비용이 landed 를 얹는다 · 넷 다 landed · 금액 비율 · 83b79f5) · 화면 po.html(Add a line · 머리 칸 편집 · 대화 Claude) · receiving.html(차이 닫기 · 형제 한 줄).
  ⭐ [Caleb] 재고 원가는 인식 시점(발주) 환율 — 결제 환율 차액은 환차손익(회계사 확인 대기) · kind 넷 다 landed(other 도 · 에이전트 수수료 확인 중) · 환율이 없으면 확정을 막는다 · 화면은 판정하지 않는다(fixed·latest 는 재료).
  ⭐ 판단: 레이어 키 = 원장 키(RCV · po_line_id) · bin 을 접는다 · 발주의 레이어는 po_line 을 거쳐 · 형제 라인은 product_id · 「닫혔다」= resolved_at(CHECK 로 셋 묶음) · reopen 은 흔적을 남긴다 · 되돌리기는 landed 가 얹혔으면 거부.
  ⚠️ 실사고: 원문에 있던 v_base 를 두 번 선언해 적용이 멈췄다(지웠으면 분할 채번이 CADa 가 될 자리 · v_base_cur 로) · fx_direction 이 CAD 발주에서 「곱한다」고 거짓말했다(통화별 두 문장으로) · 손으로 쓴 검증 재귀가 뿌리를 중복 제거하지 않아 합이 두 배(함수는 맞았다).
  ✅ [09-20] **inv_layer_apply() 에 IMS 판**(`20260920142635` · bb519c7) — 옛 「돌리지 마라 · 통째로 사라진다」는 틀렸었다(실물은 0 원 레이어로 덮어썼고 창구 멱등을 막았다 · ledger-design 4부 「✅ 해소 — inv_layer_apply() 에 IMS 판」).
  📌 다음(§13-f 09-19 오후 블록): ~~inv_layer_apply IMS 판~~(✅ 09-20) · ~~over 닫기~~(✅ 09-20 오후) · 비용 취소와 landed · Tax rule · MTFX·빈 환율·백필 · 셋째 재료 · 아침 점검 한 줄 · 회계사 질문 다섯.
- 2026-09-20 오후 — **⭐⭐ 매입 가격 이력 · over 차이 닫기 · 보조 함수 넷에 IMS 문 · 화면 셋(§11-g 「매입 가격 이력」 · §11-i 「차이 닫기」 · §11-d·11-e 정정 · §13-f · ledger-design 4부 「✅ 해소」·「원가 이식 1차」·「이식이 남긴 것」)** — 마이그레이션 셋 `20260920163231`(150행 · 뷰 둘 po_price_history·_skipped · 497cd59) · `20260920171930`(1,008행 · over 닫기 · 형제 함수 `po_receipt_diff_settle_over` · 창구 둘 · cost_source free · line_ref :over · _resolve 문장 · _reopen 거부 · inv_layer_apply 초과분 분기 · f413fe3) · `20260920181910`(938행 · 보조 넷 문 · 본체가 종류별로 세고 지나간다 · ims.skipped_by_event · unpaired 집계 ims 제외 · 8892f03) · 화면 asung-ims po.html(검색 수리 + 미리 보기 Last paid · 161259f) · receiving.html(over 닫기 UI · 8e6fd18 · p_resolution 인자 이름 · 44f020c).
  ⭐ [Caleb] 가격의 출처는 인보이스(발주는 우리가 적은 값 · 입고는 수량의 사실) · 할인까지 보여야 확인이 된다 · CAD 공급처는 환산하지 않는다 · 초과분 실무 셋(공짜가 가장 많다 · returned 없음) · free 는 0(낸 돈이 없다 · 15 로 나누기는 기각) · billed·credited 는 기준 레이어 값(Cin7 평균원가와 갈린다 — 나아지는 부분) · 보조 넷은 「문만 낸다 — 창구는 그 사건이 날 때」.
  ⭐ 판단: factor 는 po_invoice_money 에서 읽는다(정본 하나) · 환율은 인보이스 → 같은 통화의 발주 → null(0 아님) · 빠진 줄은 여집합 뷰로 드러낸다 · line_ref `po_line_id:over`(7키 충돌 · :reversal 선례) · 초과분 값은 기준 레이어에서 읽는다(환율 식은 한 곳) · reopen 은 over 거부 · 본체가 source 로 가르고 보조 넷의 문은 방어(세는 곳은 하나).
  ⚠️ 실측: 옛 함수에 가짜 IMS 사건 넷을 태우니 `layer_avg` 9.61·9.57 로 **그럴듯한 숫자가 조용히 섰다**(0 보다 나쁘다) · 「재생성 차이 +1,330」은 결함이 아니라 09-10 대조가 `p_until '2026-09-09'` 로 하루를 뺀 것(3,642행) · purchase/unknown 85행 14,274개가 0 원(inv_cost 09-09 정지 · 재적재 때 채워진다) · 오늘 전량 재생성을 실제로 돌렸다(commit · 9.78초 · 기준선은 ledger-design 4부 「✅ 해소」 끝).
  📌 다음(§13-f 09-19 오후 블록 갱신): billed 초과분 landed · over 되돌리기 · 크레딧 설계 · supplier_discount 0행 · latest·fixed 갱신(출처 인보이스) · 우리 쓸 물건의 재고 길 · 아침 점검 둘 · purchase/unknown 85 · MTFX · Tax rule · 회계사 다섯.
