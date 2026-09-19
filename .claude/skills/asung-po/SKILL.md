---
name: asung-po
description: >
  Asung Trading IMS 의 PO(발주) 모듈 — Cin7 Core 발주를 대체하는 세 번째 모듈. 마스터 표(ref_)를
  만들거나 읽거나 Cin7 에서 적재할 때 먼저 읽으세요.
  "PO 모듈", "발주 모듈", "발주앱", "리시빙", "입고", "입고 확정", "풋어웨이", "po_receipt", "차이 큐", "분할", "ims_last_bin", "Settings", "Reference Book", "마스터 데이터",
  "ref_brand", "ref_category", "ref_unit", "ref_payment_term", "ref_account", "ref_currency",
  "ref_warehouse", "ref_bin", "공급처", "supplier", "제품 마스터", "product_family", "product_barcode", "product_bom",
  "pack_factor", "BOM Quantity", "UOM 세트", "콤보", "결제조건", "계정과목", "통화", "set_updated_at", "ims_touch",
  "차이 닫기", "po_family", "landed", "환율"
  이 나오면 추측하지 말고 이 스킬과 정본 docs/design/po-module.md 를 확인하세요.
  ⚠️자연키가 표마다 다르다(name·code·복합) — 추측 금지, ⚠️ref_bin 은 2,675행으로 PostgREST 1,000행
  캡을 넘는다, ⚠️Cin7 결제조건 Duration 은 기일이 아니라 할인 기한, ⚠️Cin7 은 마스터를 GUID 가 아니라
  이름 문자열로 참조(계정만 Code), ⚠️IMS 표 트리거는 ims_touch()(set_updated_at() 은 하나뿐·참조 0 — 둘 다 다시 만들지 마라),
  ⚠️세트 계수(pack_factor)의 정본은 UOM 이름이 아니라 BOM Quantity — 접미사로 읽지 마라, ⚠️product.name 유니크 금지(576종 중복).
---

# Asung PO(발주) 모듈 스킬

⭐ **설계 정본 `docs/design/po-module.md`** — 여기는 「모르면 사고가 나는 것」과 포인터만(§5 · 14KB). 방향 정본 `ims-principles.md` 가 이긴다(원칙 1 Cin7 독립 · 2 레고).
관련 스킬: `asung-inv-ledger`(원장) · `asung-wms`(규칙 29 · 45·46) · `cin7-api`.

## 0. 어디까지 왔나

```
①~④ 마스터        ✅ 09-11~14 — Settings 8축(§3-a · 사용자 `ims_staff` §10-h) · 공급처 넷(§3-b·c · is_purchasable null=미판정 · 할인은 체인) · 제품 넷(§3-d·e · ⭐ pack_factor = BOM Quantity) · product_supplier(§3-g · 충돌 키 cin7_id) · 재적재 §3-f
⑤ PO 본체          ✅ 09-16~17 — 설계 **§11** · 표 **§13-a** · 목록은 뷰 · 상세는 RPC · 돈은 뷰 po_invoice_money·po_charge_money(화면에서 다시 짜지 마라 · §13-d) · 쓰기 RPC 는 §13-d · 확정은 잠금이 아니다(§11-b)
권한               ✅ 09-17 밤 — role 넷 worker<manager<supervisor<admin(§10-h) · 쓰기 RLS + RPC 첫머리 ims_require_write(§5 권한 규약 셋) · 화면은 ims_access() 하나(3-l)
⑥ 리시빙           ✅ 09-18 — ⭐ WMS 이관을 미루고 IMS 안에 PO 갈래로 먼저(§13-i) · 표 셋 + 차이 큐 · RPC 열 · 확정·자동 분할 **§11-i·§11-c** · updated_by + ims_touch(§5) · 탭 다섯
⑦ 원장·원가 이식    ✅ 09-19 — 입고 확정이 원장 사건(`inv_post_receipt` · **§11-j**)과 원가 레이어(`inv_layer_post_receipt`)를 · 비용 확정이 landed 를(`inv_layer_post_charge` · **§11-f**) · 차이 닫기 short 만 + 형제 합계 `po_family_*`(**§11-i·§11-c**) · Last bin 속 = 원장 · 머리 칸 편집·Add a line(§11-b·§11-d) · 원가 규칙 정본은 `ledger-design.md` 4부 「이식」·「원가 이식」 · ⚠️⚠️ **`inv_layer_apply()` 금지**(아래 함정)
화면 열하나        ✅ `ims.asung.ca`(레포 `asung-ims` · ⚠️ 공개) — 마스터 다섯 · staff · po·invoices·charges·payments·receiving · 규칙 **§10-j**(3-g·3-i·3-j·3-k) · ⬜ 채울 칸 **§10-k** · 🔄 다음 **§13-f**
```
- ⭐ **IMS 표 32 · 정책 116**(2026-09-18 실측 · Caleb psql) — 전부 **테스트 DB(Asung-IMS)에만** 있다. `--db-url …testdb-url` 이 보이면 테스트 · 없으면 운영.
- ⭐ **PO 를 Cin7 에도 쓰지 않는다.** 두 재고가 다른 것은 정상 — 컷오버 때 거래를 지우고 Cin7 재고를 가져온다(§2).

## 1. ⭐ 자연키가 표마다 다르다. 추측하지 마라 (칸 목록은 §3-d · information_schema)

| 표 | 자연키(유니크) | 이것만은 |
|---|---|---|
| `ref_brand` · `ref_category` · `ref_unit` | `name` | `ref_unit.name` 은 **text**(숫자 이름 39/44) — 파싱·CHECK 금지 |
| `ref_payment_term` | `name` | 값 칸 넷(`net_days` 등)은 **손으로**(파싱 금지) |
| `ref_account` | ⭐ **`code`** — `name` 유니크 **없음** | `code` 형식 CHECK 없음 |
| `ref_currency` | ⭐ **`code`** · `name` 도 유니크 | ⚠️ `cin7_id` 없음 · `source` default `manual` · 값 2행 |
| `ref_warehouse` | `name` | `is_default` 는 표에 · ~~⚠️ `IN_TRANSIT` 없음~~ → ⭐ [09-19 원장 이식 1차] `IN_TRANSIT` 을 **담았다**(`source='manual'` · `is_active=false` · `cin7_id null` · 축이 끊기지 않게). Cin7 재적재는 보낸 행만 upsert 하므로 남는다 · 화면에서 고르는 창고가 아니다 · bin 은 없다 · ledger-design 4부 「이식」 |
| `ref_bin` | ⭐ **`(warehouse_id, name)`** | ⚠️⚠️ **2,675행 · 캡 초과** |
| `supplier` | `name` | `cin7_id` 도 unique · `is_purchasable` 은 우리 칸 |
| `supplier_address` · `supplier_contact` · `supplier_discount` | `cin7_id` · `cin7_id` · `(supplier_id, seq)` | 관계 표 · DELETE 열림 |
| `product_family` | `sku`(…FAM) | ⚠️ `name` 유니크 없음 · 옵션 축 이름만 |
| `product` | `sku` | ⚠️⚠️ `name` 유니크 **금지** · ⭐ `pack_factor`=BOM Quantity · `parent_product_id`=BOM ComponentProductID |
| `product_barcode` | `(product_id, barcode)` | 관계 표 · DELETE 열림 · ⚠️ `is_primary` 부분 유니크 금지 · 바코드 중복은 카운터로 |
| `product_bom` | `(parent_product_id, component_product_id)` | 관계 표 · **구성품 2개 이상**만 · ⚠️ 콤보 방향 칸은 여기 아님(§3-g) |
| `product_supplier` | `(product_id, supplier_id)` · ⭐ **충돌 키는 `cin7_id`** | 관계 표 · manual 승격(§3-g) · ⚠️ `is_default` 부분 유니크 금지 · 단가 `numeric(18,7)` |

- ⚠️ **새 표를 다룰 때 `\d` 를 먼저 본다** — 이 표는 요약이고 기억은 틀린다. `psql "$(cat ~/.asung-testdb-url)" -P pager=off -c "\d public.ref_bin"`

## 2. 공통 규약 — 새 마스터 표를 만들 때 (정본 §5)

```
공통 8칸  id uuid PK gen_random_uuid() · cin7_id uuid unique(plain · null) · name text not null · is_active boolean not null default true
          · source text not null default 'cin7' check in ('cin7','manual') · note text · created_at/updated_at timestamptz not null default now()
RLS       ⭐ [09-17] select 열림(using true) · insert/update/delete = (select ims_can_write('<묶음>')) · 정책 이름 <표>_<동사> · revoke all on <t> from anon(§5 권한 규약)
⚠️ 권한    revoke delete, truncate on <t> from authenticated; — 마스터는 is_active 로(정책 셋) · 관계·거래 표는 DELETE 열림(정책 넷)
⭐ 트리거  ⭐⭐ [09-18] create trigger <t>_touch before update on <t> for each row execute function ims_touch();  — updated_at + **updated_by**(auth.uid()→ims_staff.id · null=system) · 새 표는 updated_by 칸·FK·<t>_updated_by_idx 도
          ⚠️⚠️ set_updated_at() 정의는 남지만 **참조 트리거 0** — 어느 쪽도 다시 만들지 마라 · §5 트리거
FK        on delete no action(기존 참조 FK 관례 · RESTRICT 0건) · ❌ cascade 금지 · ⭐ FK 컬럼 인덱스를 직접 만든다(<표>_<컬럼>_idx)
CHECK     이름은 <표>_source_ck 로 통일 · 인라인 무명 CHECK 금지
금지      부분 유니크 인덱스(WMS 규칙 29) · lower(name) 유니크 · sort_order · 행 적재(ref_currency 예외) · 「종류 칸」(관계로 읽는다)
```
- 검증 관례: `supabase start → db reset → information_schema → 실동작 → supabase stop` · `migration new` 는 stdin 에서 멈춘다 — 파일명을 직접 만든다.
- ⚠️ `psql -f` 로 적용하면 **이력 표가 안 쌓인다** — `supabase migration repair --status applied <버전>` 을 함께(09-18 실사고 · §13-f).

## 3. ⚠️ Cin7 에서 적재할 때 (사본 `docs/probes/*.gs` · 원본은 GAS)

- ⭐ **Cin7 은 마스터를 이름 문자열로 참조한다** — **계정만 `Code`**. `Net 30`/`Net30` 처럼 흔들리면 정확히 못 이은 것 — **비워 두고 센다.**
- ⚠️ `ref/account` 키는 **`AccountsList`** · 창고 = `ParentID` 없는 행 · bin 이름은 하위 행 `Name` 그대로 · ~~`IN_TRANSIT` 없음~~ → [09-19] 원장의 합성 창고를 manual·비활성으로 담았다(재적재가 지우지 않는다 · ledger-design 4부) · 환율은 문서에 · `inv-cost` 하드코딩 무접촉(§7).
- ⚠️ 전량은 **`IncludeDeprecated=true`** · ③ 순서 의존 둘(세트는 제품 뒤 · 대체 UPC 는 바코드 뒤 · §3-e) · `IncludeBOM=true` 면 `Limit` 실효 500 · 충돌 키 ③ `sku` · ④ `cin7_id`(§3-f).
- ⭐ **④ 는 낱개에만 붙는다 — 발주는 낱개 단위로 한다.** 세트는 부모를 `pack_factor` 로 환산 · 콤보는 「공급처 줄이 있으면 후보」(§3-g).

## 4. 함정 요약

| 함정 | 결과 | 처방 |
|---|---|---|
| 캡 넘는 표 넷(ref_bin·product_family·product·product_supplier) 전량 select | 에러 없이 1,000행만 | `.range()` 또는 jsonb RPC · §10-j 3-a |
| `Duration` → `net_days` | 기일이 당겨진다 | 손으로 · 파서 금지 |
| `ref_account.name` 에 유니크 | 적재가 조용히 깨진다 | `code` 가 자연키 |
| `set_updated_at()`·`ims_touch()` 재정의 · 새 표에 옛 트리거 | 정의 둘 · updated_by 가 안 찍힌다 | 재사용만 · 새 표는 <t>_touch(§5) |
| ⭐⭐ 이름 서브쿼리에 별칭 없음(`where id = updated_by`) | ims_staff 에도 updated_by 가 있어 **자기 칸과 비교 — 에러 없이 null**(09-18 두 번) | 항상 `s.id = <바깥>.updated_by` · §5 트리거 |
| 쓰기 RPC 를 security definer 로 | RLS 둘째 겹이 사라진다 | 전부 invoker · **예외 하나 po_receipt_confirm**(po·po_line 은 purchasing · 창고는 receiving 만) · 따라 하지 마라 · §5 권한 규약 ② |
| 리시빙을 po_receipt_line 하나로 · 화면이 계산 · 빈 없이 확정 | 검수(빈 모름)→풋어웨이 두 단계가 안 담긴다 · bin NOT NULL | 표 셋(po_receipt · po_receipt_work · po_receipt_line) · 한 줄=한 빈 · **빈 없는 줄=라인당 하나(미배정 나머지)** · 같은 빈은 **병합** · 계산은 po_receipt_detail · 확정 게이트는 빠져나갈 길을 말한다 · §11-i |
| 기준을 인보이스로 · 초과를 잘라 적는다 · 차이를 자동으로 닫는다 · 분할 번호를 겹쳐 쓴다 | 가짜 차이(WMS 08-05) · 초과가 안 보인다 · 사람 판단 소멸 · 족보 끊김 | 기준은 **PO 확정 수량**(인보이스는 표시만) · 입고 줄엔 그대로 · 차이 큐 over·short·off_po 는 사람이 · 번호는 알파벳을 잇는다(a·b → c·d) · 0 라인은 행을 b 로 · §11-i·§11-c |
| Last bin 을 po_receipt_line·wms_sku_bins 에서 직접 | 원장이 오면 고칠 곳이 여럿 | **ims_last_bin() 하나 뒤에** — 속만 갈아 끼운다 · §11-i |
| `on delete cascade` | bin 2,047개 딸려 소멸 | `no action` |
| `AdditionalAttribute1` 로 발주처를 거른다 | 판정과 어긋난다 | Caleb 판정이 정본(`is_purchasable`) |
| `product.name` 에 유니크 | 576종 중복 — 배치 전체 실패 | `sku` 가 자연키 · 화면은 SKU 를 함께 띄운다 |
| ⭐ `pack_factor` 를 UOM 이름·SKU 접미사에서 읽는다 | **재고가 조용히 틀어진다**(§3-d) | 정본은 **BOM Quantity** · UOM·접미사는 검산 카운터 |
| upsert 로 부분 갱신 · PATCH 를 서버 필터로 건너뛰기 | 400/23502 · 건너뛰는 요청도 왕복 | **PATCH** · 먼저 읽어 뺀다(asung-wms 규칙 45·46) |
| 재적재를 표마다 다르게 · 「지우고 다시」 | 값이 사라진다 · upsert 는 「없어진 것」을 모른다 | ⭐ **넷이 한 규칙** — upsert + 안 들어온 cin7 행 `is_active=false` · §3-f |
| `is_default` 를 켜기만 한다 | 내린 줄이 기본으로 남는다(실사고) | **끄고 나서 켠다**(§3-g) |
| 콤보를 발주 후보에서 뺀다 · 세트에 공급처 줄을 둔다 | 사 오는 콤보가 사라진다 | 「공급처 줄이 있으면 후보」 · 세트는 부모로(§3-g) |
| 화면이 `is_active` 를 안 건다 · timestamptz 를 문자열로 자른다 | 내려간 줄이 보인다 · UTC 로 보인다 | 읽는 쪽이 **매번** 건다(3-c) · `imsTs()`(date 칸 제외 · 3-f) |
| ⭐ 확정(confirmed)을 **잠금**으로 본다 | 확정 뒤 수량·품목 추가가 빈번하다 | 확정 = 「보낼 수량·라인이 정해졌다」 · 막는 둘만 RPC · §11-b |
| plpgsql — text[] 에 리터럴을 `\|\|` 로 | malformed array literal · **판정마다 되고 안 됨** | `array_append` · 실행해야 드러난다 · §13-e |
| ⭐ 크레딧을 지운다 · 삭제 가부를 status 로 | 채번이 **행을 읽어** 번호가 다시 난다 · 확정 거친 cancelled 가 지워진다 | 크레딧은 **취소만** · 축은 **confirmed_at** · §11-c·§11-b |
| 비용 배분 한 줄을 고치면 나머지를 다시 비례로 · unallocated ≠ 0 을 경고로 | 확인한 칸이 저절로 바뀐다 | **고친 줄만** · 확정은 **거부** · §11-f |
| 결제에 통화 다른 문서 · draft 문서를 담는다 | 미지급이 어긋난다 | **한 결제 = 한 통화** · **confirmed 만** · §11-h |
| 인자를 늘리며 `create or replace` | 옛 판이 남아 같은 이름이 둘 | **drop + create**(`20260917170000`) · §5 |
| ⭐ RLS 가 막았는데 RPC·화면이 성공을 답한다 | RLS 는 쓰기를 **감출 뿐** — 0행 | 쓰기 RPC 첫머리 `ims_require_write('<묶음>',…)` + row_count · 화면은 imsSaved() · §5 권한 규약 ② |
| 화면이 role·perms 를 직접 가른다 · role_ck 나열을 등급으로 | 'manager' 만 아는 코드가 worker 를 통과시킨다 · 자기 승격 길 | 판정은 **ims_access() 하나**(3-l) · 순서는 `ims_role_rank` · **자기보다 아래만** · §10-h |
| 「읽기는 되는데 쓰기가 안 된다」고 말한다 | ims_can_view 는 **화면 접근** 판정이지 데이터 읽기가 아니다 | 거부 문장 하나 「You cannot change <묶음> data …」 · §5 ② |
| ⭐ 차이 큐의 over 를 닫는다 · 이유를 자유 메모로 | 초과분이 재고에 안 잡힌 채 「닫힘」 · 「이 공급처가 몇 번 결품했나」를 셀 수 없다 | **short 만**(`po_receipt_diff_resolve` · 어휘 다섯 · other 는 메모 필수 · 「닫혔다」= resolved_at 하나 · CHECK 로 셋 묶음) · over 는 재고를 움직이는 **별도 차수** · §11-i |
| 형제 문서 합계를 화면이 더한다 · 라인을 line_no 로 맞춘다 | 손 재귀가 뿌리를 중복 제거 못 해 **두 배(24)** 가 났다(09-19 실사고) · b 의 새 라인 line_no 가 a 의 다른 제품과 겹친다 | **`po_family_lines` · product_id** · 계산은 DB(순환 방어 path·깊이 50) · §11-c |
| 확정된 비용을 되돌려 배분을 고치고 다시 확정 | landed 가 이미 얹힌 뒤라 멱등이 건너뛰어 **옛 금액이 남는다** | 되돌리기는 landed 있으면 **거부** · 고치려면 **상쇄 비용 문서**(append-only) · §11-f |
| 기준통화 아닌 발주·비용을 환율 없이 확정 · 환율로 **나눈다** | 원가 0 · 또는 **반값 — 에러 없음** | 확정 거부(게이트 ⑥ · 문장이 어디서 고치는지 말한다) · `exchange_rate` 는 **CAD per USD — 곱한다** · §11-j·§11-f · ledger-design 4부 |
| 발주 머리의 Supplier·Currency 를 연다 | 라인의 단가 근거·통화 뜻이 통째로 바뀐다(USD 5.19 → CAD 5.19) | **열지 않는다** — 잘못 골랐으면 새 발주 · 언제나 여는 것은 Exchange rate·Note 뿐(원가가 매달린다) · §11-b |
| ⚠️⚠️ `inv_layer_apply()` 를 돌린다 | IMS 원가(`po_line` 레이어 + 그 위 landed)가 **통째로 사라진다** — 원장은 남아 **조용하다** | IMS 판이 들어갈 때까지 **금지** · 되살리기 = 두 창구 재호출 · ledger-design 4부 「돌리면 안 되는 함수」 · 스킬 asung-inv-ledger 함정 첫 줄 |

- ⭐ **매니저는 정돈된 목록만 · admin 만 토글** — 감추는 것이지 막는 것이 아니다. 막는 것은 **RLS**(표 32 · §5 권한 규약).
- ⭐ **화면을 새로 만들면 `asung-ims/CHECKLIST.md` 에 항목을 더한다** — 낡은 점검 목록은 거짓 안심만 준다(§10-j 3-h).

## 5. 이 스킬을 갱신할 때

- 새 사실은 **정본에 먼저**, 여기에는 「모르면 사고가 나는 것」만 한 줄 · 정본에 있는 것은 옮겨 적지 말고 가리킨다 · 실측 숫자는 두지 않는다 — 14KB 를 넘기면 정본으로.
- `description` 은 1024자 한도(pre-commit `scripts/check-skill-desc.sh`). 줄일 때 표 이름 키워드보다 일반어를 먼저 뺀다.
- 옛 문장은 `~~취소선~~ + [정정 날짜]` — 단 경위가 정본에 있으면 포인터로 대신한다.
