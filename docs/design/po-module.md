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
① Settings (8축)  ✅ 2026-09-11 완료 — 7축 · 사용자는 wms_staff 확장(별건)
② 공급처           ✅ 범위·칸 확정 2026-09-11(§7-a) — 활성 226 만 담는다 · ~~표 셋(본체·주소·연락처)~~ [2026-09-12 정정] **표 넷 — §7-b**(`supplier_discount` 추가) · is_purchasable 은 우리 칸 — §8 supplier 실측 · ✅ **표 넷 신설·적재 완료(2026-09-12 · §7-c) — 226 / 87 / 237 / 0**
③ 제품             ⬜ ⚠️ Cin7 필드 83개 · 우리 것이 아닌 항목을 거르는 판단이 첫 질문 — §8 product 실측
④ 제품↔공급처      ⬜ 공급처 SKU · 단가 · Fixed Price
⑤ PO 본체          ⬜
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

**`ref_bin.name` 에 단독 유니크가 없는 이유**: bin 이름은 창고 안에서만 유일하다. 지금은 접두어가
갈려(`A…` 토론토 · `E…` 에드먼튼) 전역 중복 0 이지만 **오늘의 우연이지 규칙이 아니다.**

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
RLS         auth_all (ALL · authenticated · using true / with check true) + revoke all from anon · service_role 개방 없음
⚠️ 권한      revoke delete, truncate from authenticated
            근거: 마스터는 지우지 않고 is_active 로 물러나게 한다. 브랜드 한 줄을 지우면 그것을 가리키던 제품이 갈 곳을 잃는다.
            ⚠️ inv_config·inv_sku_types 관례(안 막음)를 따르지 않는다 — 그쪽은 지워도 다시 만들 수 있는 캐시·설정이다
⭐ 트리거    공용 함수 set_updated_at() · 표당 트리거 하나 <표>_set_updated_at · before update · for each row
            ⚠️ 함수를 다시 만들지 마라(create or replace 도) — 하나뿐이다. 20260911144606 에서 만든 public 스키마의 첫 트리거
            ⚠️ security definer 없음 · set search_path = public, pg_temp
            returns trigger 함수는 SQL 로 직접 호출할 수 없어 PostgREST RPC 로 노출되지 않는다 — RPC 관례의 revoke/grant 불필요
FK          on delete no action (기존 참조 FK 13건 관례 · RESTRICT 0건 · CASCADE 는 문서→소유 라인 7건에만)
            ❌ cascade 금지 — 창고 한 줄에 bin 2,047개가 조용히 딸려 사라진다
            ⭐ FK 컬럼에 인덱스를 직접 만든다(Postgres 는 자동 생성 안 한다) · 이름 <표>_<컬럼>_idx
```

왜 `updated_at` 을 트리거로 (2026-09-11 이전 public 스키마에 트리거 0개 · `default now()` 만): 쓰는 쪽이
매번 실어 주는 방식은 빠뜨려도 에러가 안 나고 어느 카운터에도 안 잡힌다(감지되지 않는 결함 ·
ims-principles §1-a). 표가 비어 있는 지금이 넣기 가장 안전했다. 함수에 `ref_` 접두어를 붙이지 않은 것은
②공급처·③제품 표가 `ref_` 가 아닐 수 있어서다. ⚠️ `now()` 는 트랜잭션 시작 시각 고정 — 트리거 검증은
문장마다 별도 트랜잭션으로.

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
- ⚠️ 화면에서 통화를 기호로만 구별하면 안 된다 — CAD·USD 둘 다 `$`.
- ⚠️ 환율은 마스터가 아니라 문서에 박는다 — 필요한 것은 「그 거래를 한 날의 환율」. Cin7 도 문서마다 `CurrencyRate`
  (⚠️ Simple Purchase 의 `Invoice.CurrencyRate` 는 null 이라 상위 `CurrencyRate` — `inv-cost` 실측).
- ⬜ KRW 송금의 환차손익 — 인보이스는 USD 로 받고 결제만 원화다. 회계 담당자와 정리할 영역(Caleb 판정) · QBO 연동 때 다시 올라온다.
- ⬜ `inv-cost`·`inv-doc-cost` 가 계정 코드(`_59_`·`_136_` 등)를 하드코딩한다 — 표는 세웠지만 **필터는 건드리지 않았다.**
  QBO 연동 때 옮긴다(2026-09-10 에 고친 것을 또 흔들지 않는다).
- ⬜ 아침 점검 ⑭ — `ref_` 표 여덟은 테스트에만 있다(§2 승격 기준).
- ⬜ `ref_bin.zone` 채우는 방법 미정 — `wms_sku_bins` 에 있지만 마스터가 WMS 표를 읽으면 안 된다(원칙 2 · 원장이
  `wms_order_lines` 를 읽는 「잠정·결합」 빚을 하나 더 지는 것).
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

## 7-b. ⭐ ② 공급처 — 표 넷 확정 (2026-09-12)

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
        있다. ⑤ PO 본체에서 발주 진행단계를 정할 때 참고
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

## 7-c. ② 공급처 표 넷 적재 완료 (2026-09-12 저녁 · 테스트 DB)

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
③ 제품                    다음 모듈. Cin7 필드 83 · `_숫자_` SKU 거르는 판단이 첫 질문
```

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

```
배열 키 Products  ·  필드 83개
CostingMethod   30행 전부 FIFO  ·  UOM 빈값 0/30
⚠️⚠️ 제품이 아닌 항목이 섞여 있다 — SKU 가 [:[OrderTotalDiscount]:] · _1_ · _10_ · _10767_ 같은 것들(Type=Service 등).
   ⭐ Caleb 확인: `_숫자_` 형식은 우리 제품이 아니다. 목록이 SKU 순 정렬이라 앞쪽에 몰려 있다
⭐ 제품이 계정과목을 넷 참조한다 — InventoryAccount · COGSAccount · RevenueAccount · ExpenseAccount
📌 HSCode · CountryOfOrigin 칸이 있다
⬜ product?IncludeSuppliers=true 는 미확인 — 표본 5행이 전부 시스템 항목이라 Suppliers 0 이었다.
   실제 상품 SKU 로 다시 봐야 한다(「파라미터가 안 먹는다」와 「표본이 나쁘다」가 구별되지 않는다)
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
