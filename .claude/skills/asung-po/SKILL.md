---
name: asung-po
description: >
  Asung Trading IMS 의 PO(발주) 모듈 — Cin7 Core 발주를 대체하는 세 번째 모듈. 마스터 표(ref_)를
  만들거나 읽거나 Cin7 에서 적재할 때 먼저 읽으세요.
  "PO 모듈", "발주 모듈", "발주앱", "purchasing.html", "Settings", "Reference Book", "마스터 데이터",
  "ref_brand", "ref_category", "ref_unit", "ref_payment_term", "ref_account", "ref_currency",
  "ref_warehouse", "ref_bin", "공급처", "제품 마스터", "결제조건", "계정과목", "통화", "set_updated_at"
  이 나오면 추측하지 말고 이 스킬과 정본 docs/design/po-module.md 를 확인하세요.
  ⚠️자연키가 표마다 다르다(name·code·복합) — 추측 금지, ⚠️ref_bin 은 2,675행으로 PostgREST 1,000행
  캡을 넘는다, ⚠️Cin7 결제조건 Duration 은 기일이 아니라 할인 기한, ⚠️Cin7 은 마스터를 GUID 가 아니라
  이름 문자열로 참조(계정만 Code), ⚠️set_updated_at() 은 하나뿐 — 다시 만들지 마라.
---

# Asung PO(발주) 모듈 스킬

⭐ **설계 정본은 `docs/design/po-module.md`** — 이 스킬은 요약과 함정만 담는다. 실측 표·경위·대안·
사고 기록은 전부 정본에 있다. **이 파일에 실측 표를 옮기지 마라**(`asung-inv-ledger` 가 190KB 가 된 길을
반복하지 않는다 · 목표 15KB 이하).
⚠️ 방향 정본 `docs/design/ims-principles.md` — 충돌하면 그쪽이 이긴다(원칙 1 Cin7 독립 · 원칙 2 레고).
관련 스킬: `asung-inv-ledger`(원장) · `asung-wms`(WMS · 규칙 29 부분 유니크 금지) · `cin7-api`(엔드포인트 실측 · `references/ref-endpoints.md`).

## 0. 어디까지 왔나

```
① Settings (8축)  ✅ 2026-09-11 — 7축(표 여덟) · 사용자는 wms_staff 확장(별건)
② 공급처           🔵 범위·칸 확정(2026-09-11 · 정본 §7-a) — 활성 226 만 담는다(비활성 462 는 경비처) · 표 셋(본체·주소·연락처) · is_purchasable 은 우리 칸(null=미판정 · false 로 밀지 마라) · FK + 원문 칸 병행 · AdditionalAttribute1(Supplier Type)·AttributeSet 담지 않음(09-12 · 정본 §7-a · 상위 근거 ims-principles §4-d)
③ 제품             ⬜ Cin7 필드 83 · ⚠️ `_숫자_` SKU 는 우리 제품이 아니다 — 거르는 판단이 첫 질문
④ 제품↔공급처      ⬜ 공급처 SKU · 단가 · Fixed Price
⑤ PO 본체          ⬜
```
- ⭐ **PO 를 Cin7 에도 쓰지 않는다.** Cin7 이 정본인 동안 두 재고가 다른 것은 정상 — 맞추려 하지 않는다.
  전환 시점에 IMS 를 리셋하고 Cin7 재고를 통째로 가져온다(정본 §2). 이중 기록 제안은 틀렸던 것.
- ⚠️ `ref_` 표 여덟은 **테스트 DB(Asung-IMS)에만 있다.** 운영에서 도는 것이 필요로 할 때만 운영에 올린다.
  `--db-url "$(cat ~/.asung-testdb-url)"` 가 보이면 테스트 · 없으면 운영.

## 1. ⭐ 표 여덟 — 자연키가 표마다 다르다. 추측하지 마라

| 표 | 칸 | 자연키(유니크) | 이것만은 |
|---|---|---|---|
| `ref_brand` · `ref_category` · `ref_unit` | 8 | `name` | `ref_unit.name` 은 **text**(39/44 가 숫자 이름) — 파싱·CHECK 금지 |
| `ref_payment_term` | 12 | `name` | `net_days`·`discount_days`·`discount_percent`·`is_split` — **값은 손으로**(파싱 금지) |
| `ref_account` | 12 | ⭐ **`code`** — `name` 유니크 **없음** | `code` 형식 CHECK 없음(`_59_` 와 `2000` 두 형식) · `account_class` 만 CHECK |
| `ref_currency` | 9 | ⭐ **`code`** (`^[A-Z]{3}$`) · `name` 도 유니크 | ⚠️ **`cin7_id` 없음** · `source` default **`manual`** · ⭐ **값 2행(CAD·USD)이 든 유일한 표** · 기준통화는 `inv_config.base_currency` |
| `ref_warehouse` | 15 | `name` | `is_default` 는 **표에**(다른 둘은 `inv_config`) · ⚠️ `IN_TRANSIT` 없음(원장의 합성 창고) · `Production Facility` 는 비활성으로 담는다 |
| `ref_bin` | 11 | ⭐ **`(warehouse_id, name)`** 복합 — `name` 단독 유니크 없음 | FK → `ref_warehouse` `on delete no action` · ⚠️⚠️ **2,675행 = 1,000행 캡 초과** · `zone` 은 비어 있다 |

- ⚠️ **새 표를 다룰 때 `information_schema.columns` 를 먼저 본다.** 이 표는 요약이고 기억은 틀린다.
  ```bash
  psql "$(cat ~/.asung-testdb-url)" -P pager=off -c "select column_name, data_type, is_nullable, column_default
  from information_schema.columns where table_schema='public' and table_name='ref_bin' order by ordinal_position;"
  ```
- 「앞선 표는 name 유니크인데 여기만 없다」「여기만 값이 들어 있다」「여기만 is_default 가 표에 있다」는
  **결함이 아니라 판단**이다 — 이유는 정본 §4. 고치기 전에 그 절을 읽는다.

## 2. 공통 규약 — 새 마스터 표를 만들 때 (정본 §5)

```
공통 8칸  id uuid PK gen_random_uuid() · cin7_id uuid unique(plain · null) · name text not null · is_active boolean not null default true
          · source text not null default 'cin7' check in ('cin7','manual') · note text · created_at/updated_at timestamptz not null default now()
RLS       create policy auth_all on <t> for all to authenticated using (true) with check (true);  revoke all on <t> from anon;
⚠️ 권한    revoke delete, truncate on <t> from authenticated;   — 마스터는 지우지 않고 is_active 로 물러나게 한다
⭐ 트리거  create trigger <t>_set_updated_at before update on <t> for each row execute function set_updated_at();
          ⚠️⚠️ set_updated_at() 은 20260911144606 에 하나뿐 — create or replace 로도 다시 만들지 마라 · security definer 금지
FK        on delete no action(기존 참조 FK 관례 · RESTRICT 0건) · ❌ cascade 금지 · ⭐ FK 컬럼 인덱스를 직접 만든다(<표>_<컬럼>_idx)
금지      부분 유니크 인덱스(WMS 규칙 29) · lower(name) 유니크 · sort_order · 행 적재(ref_currency 만 예외였다)
```
- 검증 관례: `supabase start → db reset → information_schema 실물 → 실동작(문장마다 별도 트랜잭션 — now() 는
  트랜잭션 고정) → check-caps.sh → supabase stop`. `db push`·`git push`·커밋은 Caleb.
- `supabase migration new` 가 `$(…)` 안에서 멈춘다 — `date -u +%Y%m%d%H%M%S` 로 파일명을 직접 만든다.

## 3. ⚠️ Cin7 에서 적재할 때 (아직 코드 없음)

- ⭐ **Cin7 은 마스터를 이름 문자열로 참조한다**(제품 Brand·Category·UOM · 공급처 PaymentTerm) — **계정만 `Code`**
  (공급처 AccountPayable 226/226 Code 일치 · Name 일치 0). 연결 고리는 이름이고 `cin7_id` 는 보조.
- ⚠️ 문자열이 흔들리면 연결도 흔들린다 — `Net 30`(33곳)/`Net30`(21곳)이 별개 행. 정확히 못 이으면 **비워 두고 센다.**
  억지로 붙이면 기일이 15일 틀린다. Cin7 값을 그대로 받은 뒤 사람이 전수 검사 — `source` 가 그 근거.
- ⚠️⚠️ `ref/paymentterm` 의 `Duration` 은 **할인 기한**이다(「2%10 Net30」→ 10). `net_days` 에 넣으면 20일 당겨져 연체 오판.
- ⚠️ `ref/account` 배열 키만 복수형 **`AccountsList`**. `Status` ARCHIVED 76개도 담는다(`is_active=false`).
- ⚠️ `ref/location`: 창고 = `ParentID` 없는 행 3 · bin = 있는 행 2,675. **bin 이름은 하위 행 `Name` 그대로**(2026-09-11 정정 —
  ~~「바코드류」~~ 옛 기록은 틀렸다). `Production Facility` → `is_active=false` · `IN_TRANSIT` 넣지 않음 · bin 주소 `''` → null.
- ⚠️ 통화는 Cin7 에 목록이 없다 — 긁어올 데가 없다. 환율은 마스터가 아니라 문서에 박는다.
- ⚠️ `inv-cost`·`inv-doc-cost` 의 계정 코드 하드코딩(`_59_`·`_136_`…)은 **건드리지 않는다** — QBO 연동 때.
- ⚠️ `_135_` 의 실제 이름은 **Brokerage - COS** — 우리 문서의 "landed" 와 같은 것.
- ⚠️ 세율 이름은 **바뀐 해를 붙인다 — 연도 있는 쪽이 현행**(PE/NB/NL 2016=15% · NS 2025=14% · ON 은 연도 없음 13%).
  ⚠️ 폐지된 `HST NS (Purchase)` 15% 를 활성 공급처 16곳이 쓴다. 정본 §8-C.

## 4. 함정 요약

| 함정 | 결과 | 처방 |
|---|---|---|
| `ref_bin` 전량 select | 에러 없이 1,000행만 | 페이징 또는 `jsonb_agg` RPC · `check-caps.sh` |
| `Duration` → `net_days` | 기일 20일 당겨짐 | 손으로 채운다 · 파서 금지 |
| `ref_account.name` 에 유니크 | 중복 미측정 — 적재가 조용히 깨진다 | `code` 가 자연키 |
| `ref_account.code` 형식 CHECK | 순수 숫자 74개 탈락 | CHECK 없음 유지 |
| `set_updated_at()` 재정의 | 정의 둘 · 관례 붕괴 | 재사용만 · 정의 수 1 확인 |
| `on delete cascade` | 창고 하나에 bin 2,047개 소멸 | `no action` |
| 통화를 `$` 로 구별 | CAD·USD 구별 불가 | `code` 로 표시 |
| `ref_` 표가 운영에 있다고 가정 | 운영 조회 실패 | 테스트에만 있다 |
| 제품 목록 앞 페이지로 판단 | `_숫자_` 시스템 항목이 앞에 몰림 | 전량 · 형식 필터 |
| 공급처 전량을 226 으로 안다 | 비활성 462 를 못 본다 | ⭐ `IncludeDeprecated=true` 전량 688 |
| `AdditionalAttribute1` 로 발주처를 거른다 | 활성 72곳 빈값 · 154곳 중 8곳이 판정과 어긋남 | Caleb 판정이 정본(`is_purchasable`) |

## 5. 이 스킬을 갱신할 때

- 새 사실은 **정본에 먼저** 쓰고, 여기에는 「모르면 사고가 나는 것」만 한 줄 남긴다. 15KB 를 넘기면 정본으로 옮긴다.
- `description` 은 1024자 한도(pre-commit `scripts/check-skill-desc.sh`). 줄일 때 표 이름 키워드보다 일반어를 먼저 뺀다.
- 옛 문장은 지우지 않고 `~~취소선~~ + [정정 날짜]` 로 남긴다.
