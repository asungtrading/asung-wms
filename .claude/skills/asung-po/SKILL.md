---
name: asung-po
description: >
  Asung Trading IMS 의 PO(발주) 모듈 — Cin7 Core 발주를 대체하는 세 번째 모듈. 마스터 표(ref_)를
  만들거나 읽거나 Cin7 에서 적재할 때 먼저 읽으세요.
  "PO 모듈", "발주 모듈", "발주앱", "purchasing.html", "Settings", "Reference Book", "마스터 데이터",
  "ref_brand", "ref_category", "ref_unit", "ref_payment_term", "ref_account", "ref_currency",
  "ref_warehouse", "ref_bin", "공급처", "supplier", "제품 마스터", "product_family", "product_barcode", "product_bom",
  "pack_factor", "BOM Quantity", "UOM 세트", "콤보", "결제조건", "계정과목", "통화", "set_updated_at"
  이 나오면 추측하지 말고 이 스킬과 정본 docs/design/po-module.md 를 확인하세요.
  ⚠️자연키가 표마다 다르다(name·code·복합) — 추측 금지, ⚠️ref_bin 은 2,675행으로 PostgREST 1,000행
  캡을 넘는다, ⚠️Cin7 결제조건 Duration 은 기일이 아니라 할인 기한, ⚠️Cin7 은 마스터를 GUID 가 아니라
  이름 문자열로 참조(계정만 Code), ⚠️set_updated_at() 은 하나뿐 — 다시 만들지 마라,
  ⚠️세트 계수(pack_factor)의 정본은 UOM 이름이 아니라 BOM Quantity — 접미사로 읽지 마라, ⚠️product.name 유니크 금지(576종 중복).
---

# Asung PO(발주) 모듈 스킬

⭐ **설계 정본 `docs/design/po-module.md`** — 여기는 「모르면 사고가 나는 것」과 포인터만(§5 · 14KB).
⚠️ 방향 정본 `docs/design/ims-principles.md` — 충돌하면 그쪽이 이긴다(원칙 1 Cin7 독립 · 원칙 2 레고).
관련 스킬: `asung-inv-ledger`(원장) · `asung-wms`(규칙 29 · 45·46) · `cin7-api`.

## 0. 어디까지 왔나

```
①~④ 마스터        ✅ 09-11~14 · 테스트 DB — Settings 8축(§3-a · 사용자는 `ims_staff` §10-h) · 공급처 표 넷(§3-b·c · is_purchasable 은 우리 칸 · null=미판정 · false 로 밀지 마라 · 할인은 체인) ·
                   제품 표 넷(§3-d·e · 범위는 §3-d · ⭐ pack_factor = BOM Quantity) · product_supplier(§3-g · ⭐ 충돌 키 cin7_id · is_default 우리 칸) · 재적재는 넷이 한 규칙 §3-f · 카운터는 §3-e·§3-g
⑤ PO 본체          ✅ 09-16~17 · 테스트 DB — 설계 **§11** · 표 열하나 **§13** · 목록은 뷰(po_list·po_invoice_list·po_charge_list·po_payment_list) · 상세는 RPC · 돈은 뷰 po_invoice_money·po_charge_money(화면에서 다시 짜지 마라)
                   · 쓰기 RPC — 발주 · 인보이스·크레딧(p_line_qty) · 비용 · 결제 · 취소·삭제(po_doc_cancel/delete) · 미리 보기 두 단계 · 확정은 잠금이 아니다(§11-b) · 🔄 다음 §13-f
권한               ✅ 09-17 밤 — role 넷 worker<manager<supervisor<admin(§10-h) · 표 28 쓰기 RLS(§5 권한 규약) · 쓰기 RPC 23 첫머리 ims_require_write · 화면은 ims_access() 하나(§10-j 3-l)
화면               ✅ 09-17 — `ims.asung.ca`(레포 `asung-ims` · ⚠️ 공개) · 마스터 + po·invoices·charges·payments · 규칙 **§10-j**(공통 CSS 3-j · 구매 탭 3-k) · 새 화면은 공통 넷을 순서대로(3-g) · <style> 에 공통을 복사하지 않는다 · ⬜ 채울 칸 **§10-k**
```
- ⭐ **PO 를 Cin7 에도 쓰지 않는다.** 두 재고가 다른 것은 정상 — 전환 때 IMS 를 리셋하고 Cin7 재고를 통째로 가져온다(§2).
- ⚠️ 마스터 17표와 PO 표 열하나는 **테스트 DB(Asung-IMS)에만 있다** — `--db-url …testdb-url` 이 보이면 테스트 · 없으면 운영.

## 1. ⭐ 자연키가 표마다 다르다. 추측하지 마라 (칸 목록은 §3-d · information_schema)

| 표 | 자연키(유니크) | 이것만은 |
|---|---|---|
| `ref_brand` · `ref_category` · `ref_unit` | `name` | `ref_unit.name` 은 **text**(숫자 이름 39/44) — 파싱·CHECK 금지 |
| `ref_payment_term` | `name` | 값 칸 넷(`net_days` 등)은 **손으로**(파싱 금지) |
| `ref_account` | ⭐ **`code`** — `name` 유니크 **없음** | `code` 형식 CHECK 없음 |
| `ref_currency` | ⭐ **`code`** · `name` 도 유니크 | ⚠️ `cin7_id` 없음 · `source` default `manual` · 값 2행 |
| `ref_warehouse` | `name` | `is_default` 는 표에 · ⚠️ `IN_TRANSIT` 없음 |
| `ref_bin` | ⭐ **`(warehouse_id, name)`** 복합 | ⚠️⚠️ **2,675행 · 캡 초과** |
| `supplier` | `name` | `cin7_id` 도 unique · `is_purchasable` 은 우리 칸 |
| `supplier_address` · `supplier_contact` · `supplier_discount` | `cin7_id` · `cin7_id` · `(supplier_id, seq)` | 관계 표 · DELETE 열림 |
| `product_family` | `sku`(…FAM) | ⚠️ `name` 유니크 없음 · 옵션 축 이름만 |
| `product` | `sku` | ⚠️⚠️ `name` 유니크 **금지**(§4) · ⭐ `pack_factor`=BOM Quantity · `parent_product_id`=BOM ComponentProductID |
| `product_barcode` | `(product_id, barcode)` | 관계 표 · DELETE 열림 · ⚠️ `is_primary` 부분 유니크 금지 · 바코드 중복은 카운터로 |
| `product_bom` | `(parent_product_id, component_product_id)` | 관계 표 · **구성품 2개 이상**만 · `quantity > 0` · ⚠️ 콤보 방향 칸을 여기 두지 마라(부모당 하나 · §3-g) |
| `product_supplier` | `(product_id, supplier_id)` · ⭐ **충돌 키는 `cin7_id`**(manual 승격의 열쇠) | 관계 표 · manual 줄 승격(§3-g) · ⚠️ `is_default` 부분 유니크 금지(카운터) · 단가 `numeric(18,7)` |

- ⚠️ **새 표를 다룰 때 `information_schema.columns` 를 먼저 본다.** 이 표는 요약이고 기억은 틀린다.
  `psql "$(cat ~/.asung-testdb-url)" -P pager=off -c "\d public.ref_bin"`

## 2. 공통 규약 — 새 마스터 표를 만들 때 (정본 §5)

```
공통 8칸  id uuid PK gen_random_uuid() · cin7_id uuid unique(plain · null) · name text not null · is_active boolean not null default true
          · source text not null default 'cin7' check in ('cin7','manual') · note text · created_at/updated_at timestamptz not null default now()
RLS       ⭐ [09-17] select 열림(using true) · insert/update/delete = (select ims_can_write('<묶음>')) · 정책 이름 <표>_<동사> · revoke all on <t> from anon  (~~auth_all~~ · §5 권한 규약)
⚠️ 권한    revoke delete, truncate on <t> from authenticated;   — 마스터는 지우지 않고 is_active 로(delete 정책 없음 · 셋) · 관계·거래 표는 DELETE 열림(정책 넷)
⭐ 트리거  create trigger <t>_set_updated_at before update on <t> for each row execute function set_updated_at();
          ⚠️⚠️ set_updated_at() 은 20260911144606 에 하나뿐 — create or replace 로도 다시 만들지 마라 · security definer 금지
FK        on delete no action(기존 참조 FK 관례 · RESTRICT 0건) · ❌ cascade 금지 · ⭐ FK 컬럼 인덱스를 직접 만든다(<표>_<컬럼>_idx)
CHECK     이름은 <표>_source_ck 로 통일 · 인라인 무명 CHECK 금지
금지      부분 유니크 인덱스(WMS 규칙 29) · lower(name) 유니크 · sort_order · 행 적재(ref_currency 예외) · 「종류 칸」(관계로 읽는다)
```
- 검증 관례: `supabase start → db reset → information_schema → 실동작 → supabase stop` · `migration new` 는 stdin 에서 멈춘다 — 파일명을 직접 만든다.

## 3. ⚠️ Cin7 에서 적재할 때 (코드: `docs/probes/ImsLoadProduct.gs` · `ImsRefLoad.gs` — 사본 · 원본은 GAS)

- ⭐ **Cin7 은 마스터를 이름 문자열로 참조한다** — **계정만 `Code`**. 문자열이 흔들리면(`Net 30`/`Net30`) 연결도 흔들린다 — 정확히 못 이으면 **비워 두고 센다.**
- ⚠️ `ref/account` 배열 키는 **`AccountsList`** · `ref/location` 창고 = `ParentID` 없는 행 · **bin 이름은 하위 행 `Name` 그대로** · `IN_TRANSIT` 넣지 않음 — 정본 §3-a·§8.
- ⚠️ 환율은 문서에 · `inv-cost` 계정 코드 하드코딩은 **건드리지 않는다**(QBO 때 · §7).
- ⚠️ 제품·공급처 전량은 **`IncludeDeprecated=true`** — 기본값은 활성만이다.
- ⚠️ **③ 적재 순서 의존 둘** — 세트 연결은 제품 뒤 · 대체 UPC 는 바코드 뒤(§3-e). `IncludeBOM=true` 면 `Limit` 실효 500.
- ⚠️ 충돌 키 — ③ `sku`(SKU 변경 계획 없음 · §3-f 전제) · ④ `cin7_id`.
- ⭐ **④ 는 낱개에만 붙는다 — 발주는 낱개 단위로 한다.** 세트는 부모를 `pack_factor` 로 환산 · 콤보는 「공급처 줄이 있으면 후보」(§3-g).

## 4. 함정 요약

| 함정 | 결과 | 처방 |
|---|---|---|
| 캡 넘는 표 넷(ref_bin·product_family·product·product_supplier) 전량 select | 에러 없이 1,000행만 | `.range()` 또는 `jsonb_agg` RPC · §10-j 3-a |
| `Duration` → `net_days` | 기일 20일 당겨짐 | 손으로 · 파서 금지 |
| `ref_account.name` 에 유니크 | 적재가 조용히 깨진다 | `code` 가 자연키 |
| `set_updated_at()` 재정의 | 정의 둘 · 관례 붕괴 | 재사용만 · 정의 수 1 확인 |
| `on delete cascade` | bin 2,047개 딸려 소멸 | `no action` |
| `AdditionalAttribute1` 로 발주처를 거른다 | 판정과 어긋난다 | Caleb 판정이 정본(`is_purchasable`) |
| `product.name` 에 유니크 | 576종 중복 — 배치 전체 실패 | `sku` 가 자연키 · 화면은 SKU 를 함께 띄운다 |
| ⭐ `pack_factor` 를 UOM 이름·SKU 접미사에서 읽는다 | **재고가 조용히 틀어진다**(§3-d) | 정본은 **BOM Quantity** · UOM·접미사는 검산 카운터 |
| upsert(`merge-duplicates`)로 부분 갱신 · PATCH 를 서버 필터로 건너뛰기 | 400/23502 · 건너뛰는 요청도 왕복 | **PATCH** · 먼저 읽어 목록에서 뺀다(asung-wms 규칙 45·46) |
| 재적재를 표마다 다르게 · 「지우고 다시」 | 값(valid_from·note·id)이 사라진다 · upsert 는 「없어진 것」을 모른다 | ⭐ **넷이 한 규칙** — upsert + 안 들어온 cin7 행은 `is_active=false` · §3-f |
| `is_default` 를 켜기만 한다 | 내린 줄·비활성 공급처가 기본으로 남는다(실사고) | **끄고 나서 켠다** · 재적재마다(§3-g) |
| 콤보를 발주 후보에서 뺀다 · 세트에 공급처 줄을 둔다 | 사 오는 콤보가 사라진다 · 세트를 하나 값으로 발주 | 「공급처 줄이 있으면 후보」 · 세트는 부모로 산다(§3-g) |
| 화면이 `is_active` 를 안 건다 | 내려간 줄이 그대로 보인다 | 읽는 쪽이 **매번** 건다 · admin 만 토글 · §10-j 3-c |
| timestamptz 를 문자열로 자른다 | UTC 로 보인다 | `imsTs()` · ⚠️ date 칸(valid_from 등)은 제외 · §10-j 3-f |
| ⭐ 확정(confirmed)을 **잠금**으로 본다 | 확정 뒤 수량·품목 추가가 빈번하다(Caleb 09-16) — 실무와 어긋난다 | 확정 = 「보낼 수량·라인이 정해졌다」 · 잠금 아님 · 막는 둘만 RPC po_line_update/delete · §11-b |
| plpgsql — text[] 에 따옴표 리터럴을 이어붙인다 | malformed array literal · format() 은 통과해 **판정마다 되고 안 됨** | `array_append` · 파일 전체 grep · 실행해야 드러난다 · §13-e |
| ⭐ 크레딧을 지운다 | 채번이 **행을 읽어** 같은 번호가 다시 난다 | 크레딧은 **취소만**(po_doc_delete 가 종류로 거부) · §11-c |
| 삭제 가부를 status 로 판정 | 확정을 거친 cancelled 가 지워진다 — 취소의 전형 | 축은 **confirmed_at**(발주도) · §11-b |
| 비용 배분 한 줄을 고치면 나머지를 다시 비례로 · unallocated ≠ 0 을 경고로 | 확인한 칸이 저절로 바뀐다 · 덜 입력한 채 확정 | **고친 줄만** · spread 는 사람이 · 확정은 **거부** · §11-f |
| 결제에 통화 다른 문서 · draft 문서를 담는다 | 미지급이 어긋난다 · 안 받아들인 청구서를 갚는다 | **한 결제 = 한 통화** · **confirmed 만** · 뒷단 검사 · §11-h |
| 인자를 늘리며 `create or replace` | 옛 판이 남아 같은 이름이 둘 | **drop + create**(`20260917170000`) · §5 |
| ⭐ RLS 가 막았는데 RPC·화면이 성공을 답한다 | RLS 는 쓰기를 **감출 뿐** 거부하지 않는다 — delete/update 0행 · 화면은 imsSaved() 되읽기 | 쓰기 RPC 첫머리 `ims_require_write('<묶음>','saved'\|'deleted')` + delete/update 뒤 row_count · §5 권한 규약 ② |
| 화면이 role·perms 를 직접 가른다 | role 넷 — 'manager' 만 아는 코드는 worker·supervisor 를 통과시킨다 | 판정은 **ims_access() 하나** · me.access · §10-j 3-l |
| role_ck 나열 순서를 등급으로 읽는다 · 같은 등급을 만든다 | 순서가 아니다(임의 나열) · 자기 승격 길 | 순서는 `ims_role_rank` 하나 · **자기보다 아래만**(자기 행 불가) · §10-h |
| 「읽기는 되는데 쓰기가 안 된다」고 말한다 | 읽기는 전부 열려 있다 — ims_can_view 는 **화면 접근** 판정이지 데이터 읽기가 아니다 | 거부 문장 하나 「You cannot change <묶음> data …」 · §5 권한 규약 ② |

- ⭐ **매니저는 정돈된 목록만 · admin 만 토글** — 감추는 것이지 막는 것이 아니다. 막는 것은 **RLS**(표 28 · §5 권한 규약).
- ⭐ **화면을 새로 만들면 `asung-ims/CHECKLIST.md` 에 항목을 더한다**(숫자까지) — 낡은 점검 목록은 거짓 안심만 준다(§10-j 3-h).

## 5. 이 스킬을 갱신할 때

- 새 사실은 **정본에 먼저**, 여기에는 「모르면 사고가 나는 것」만 한 줄. 행 수·실측 숫자는 두지 않는다 — 14KB 를 넘기면 정본으로 옮긴다.
- `description` 은 1024자 한도(pre-commit `scripts/check-skill-desc.sh`). 줄일 때 표 이름 키워드보다 일반어를 먼저 뺀다.
- 옛 문장은 `~~취소선~~ + [정정 날짜]` — 단 경위가 정본에 있으면 포인터로 대신한다.
