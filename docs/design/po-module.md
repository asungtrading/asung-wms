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
② 공급처           ⬜ ⚠️ 표가 셋이 된다(본체·주소·연락처) — §8 supplier 실측
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
| `ref_currency` | `20260911164513` | 9 | ⭐ **`code`** | ⚠️ **`cin7_id` 없음**(Cin7 에 목록이 없다) · `source` default **`manual`** · ⭐ **값 2행(CAD·USD)을 넣은 유일한 표** + `inv_config.base_currency='CAD'` 1행 · `code` 형식 CHECK **있음**(`^[A-Z]{3}$`) · `name` 유니크 있음 · `symbol` 화면용(⚠️ CAD·USD 둘 다 `$`) · `rate`·`is_base`·`decimal_places` 없음 · KRW 없음(송금 수단이지 거래 통화가 아니다 · 공급처 Currency 실측 KRW 0) |
| `ref_warehouse` | `20260911165946` | 15 | `name` | 주소 6칸 + `is_default` 를 **표에 뒀다**(§4-④) · ⚠️ `IN_TRANSIT` 안 담는다(원장의 합성 창고 · 실재하지 않는다) · `Production Facility` 는 담되 비활성(Cin7 시스템 창고 · 삭제 불가 · 없으면 갈 곳 없는 참조) · Cin7 플래그 넷(`FixedAssetsLocation`·`IsCoMan`·`IsShopFloor`·`IsStaging`)·`PickZones`·`Bins` 는 담지 않는다 · ⭐ `name` 이 `inv_ledger.warehouse`·`wms_orders.location` 과 잇는 고리 |
| `ref_bin` | `20260911165946` | 11 | ⭐ **`(warehouse_id, name)`** | FK → `ref_warehouse` (`on delete no action` · 인덱스 `ref_bin_warehouse_idx`) · ⚠️⚠️ **2,675행 예정 — PostgREST 1,000행 캡을 넘는 첫 마스터** · `zone` 은 칸만 있고 비어 있다 · `is_staging` · 주소 칸 없음(bin 행 주소는 전부 빈 문자열) · `IsDeprecated` → `is_active` |

**표를 둘로 나눈 이유(창고·bin)**: Cin7 은 한 표 + `ParentID` 자기참조지만 창고 3 · bin 2,675 로 규모가
다르고, 주소·회계 의미는 창고에만 있으며, ⭐ `inv_ledger` 가 이미 `warehouse` 와 `bin` 을 별개 칸으로
둔다 — 한 표로 묶으면 쓰는 쪽이 매번 갈라야 한다.

**`ref_bin.name` 에 단독 유니크가 없는 이유**: bin 이름은 창고 안에서만 유일하다. 지금은 접두어가
갈려(`A…` 토론토 · `E…` 에드먼튼) 전역 중복 0 이지만 **오늘의 우연이지 규칙이 아니다.**

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
- ⬜ 공급처당 기본 통화는 하나(Caleb 확정) — 새 통화로 결제하면 공급처 계정을 새로 연다. 아직 발동 없음(이름 정규화 묶음 0).
- ⬜ 사용자 축은 `wms_staff` 확장 — 별건.

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
⚠️ bin 행의 주소 칸은 null 이 아니라 빈 문자열('')
⚠️ IsDeprecated 인 bin 0건
```

### supplier 226 (전량 · `IncludeDeprecated` 미사용 — 비활성은 안 봤다)

```
Currency        USD 159 · CAD 67  ·  ⚠️ KRW 0곳
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
⚠️ 이름 정규화 후 같은 이름 묶음 0개 — 통화 때문에 갈라진 공급처는 아직 없다
```

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
