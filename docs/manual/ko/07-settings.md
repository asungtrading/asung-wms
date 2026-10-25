# 7. Settings(설정)

<!-- sections 1-3 written (manual-7a) · sections 4-11 follow in manual-7b · sections follow the work of admins and managers -->
<!-- out of this chapter: what each key opens -> chapter 0 Roles and keys · B-grade stock -> chapter 3 -->

<a id="set-start"></a>
## Settings 에 있는 것
<!-- screen: ims-auth.js · BUILD nav v13 ; system-check.html · BUILD 2026-10-24 · sc v2 -->
<!-- who: manager, admin -->

**무엇인가**
**Settings ▾** 에는 IMS 의 다른 곳이 쓰는 목록과 스위치가 있습니다: 직원 · 브랜드 · bin · 운송사 · 딜 · 문서 양식 · 웹 가게. 대부분은 보기만 하고, 몇 사람만 바꿉니다.

**누가 무엇을 바꾸나**

| 화면 | 보려면 | 바꾸려면 |
|---|---|---|
| **Settings** — 목록 | `master` 권한 | `master` 권한 write |
| **Settings** — Backorder emails · Documents · Google Drive | `master` 권한 | 부분마다 다름 — 그 절을 본다 |
| **Surcharge Groups** | `master` 권한 | admin 만 |
| **Staff** | `staff` 권한 | `staff` 권한 write · 나보다 낮은 역할의 사람만 |
| **Discount Rules** | `master` 권한 | `master` 권한 write |
| **Shopify Stores** | `shopify` 권한 | 가게 더하기 · 짝 맞추기는 admin |
| **System Check** | 권한 없이 | — 보여 주기만 한다 |

권한 자체는 [역할과 권한](00-getting-started.md#start-roles-keys)을 봅니다.

**절**
- [직원](#set-staff)
- [목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](#set-master)
- [할인 규칙과 딜](#set-deals) · [쿠폰](#set-coupons)
- [Surcharge 그룹](#set-surcharge)
- [문서](#set-documents) · [백오더 메일](#set-mail) · [Google Drive](#set-drive)
- [Shopify 가게](#set-shopify)
- [System Check](#set-system-check)

<a id="set-staff"></a>
## 직원(Staff)
<!-- screen: staff.html · BUILD 2026-10-20 · st v3a -->
<!-- who: manager, admin -->

**무엇인가**
**Staff**(**Settings ▾** › **Staff**)는 로그인할 수 있는 사람 모두를 보입니다: 이름 · 이메일 · 역할 · 권한 · 브랜치.

**누가**
`staff` 권한이 write 인 사람. "You can only create and edit people below your own rank."(나보다 낮은 역할의 사람만 만들고 고친다) admin 은 모두를 고칩니다.
- 권한이 없으면: "Read only — you need the 'staff' permission to change people."
- 나와 같거나 높은 사람: "Read only — this person is at or above your own rank."
- 나 자신: "Read only — you cannot edit your own record. Ask someone above you." admin 은 자기 이름 · 메모는 고치지만, 자기 역할 · 상태 · 권한 · 브랜치는 못 바꿉니다 — "you would lock yourself out"(스스로를 잠근다)

**어떻게 — 사람 더하기**
1. **+ Add staff** 를 누릅니다.
2. **Name** 과 **Email** 을 적습니다(예: Staff C, staff.c@example.com). "This becomes the login email."(로그인 이메일이 된다)
3. **Role** 을 고릅니다. 내 역할보다 낮은 것만 고를 수 있습니다.
4. **Create account** 를 누릅니다.
5. "Account created — hand these over once."(계정을 만들었다 — 한 번만 건넨다) **Copy** 를 눌러 이메일과 임시 비밀번호를 그 사람에게 줍니다. "This temporary password is shown only now. It cannot be retrieved later."(임시 비밀번호는 지금만 보인다 — 나중에 다시 볼 수 없다)
6. **Done** 을 누릅니다.

새 사람은 로그인한 뒤 **Change Password** 로 자기 비밀번호를 정합니다([로그인](00-getting-started.md#start-sign-in)).

**어떻게 — 사람 고치기**
1. 목록에서 그 사람을 누릅니다.
2. **Name** · **Role** · **Active** · **Note** 를 고칩니다.
3. **Access** — 권한:
   - **WMS** · **IMS** 중 하나나 둘을 체크하면 그 모드의 권한이 보입니다. "With none ticked every screen shows."(아무것도 체크하지 않으면 모든 화면이 보인다)
   - 권한마다 **none** · **read** · **write** 를 고릅니다.
4. **Location** — 브랜치. 이 사람이 일하는 브랜치를 체크합니다. "None ticked = every warehouse."(체크가 없으면 모든 창고) manager · worker 에게만 효과가 있습니다. supervisor · admin 은 모든 브랜치에서 일합니다.
5. **Save** 를 누릅니다. **Revert** 는 바꾼 것을 버립니다.

**알아 둘 것**
- "There is no delete — inactive people keep their row."(지우기는 없다 — 비활성인 사람도 줄이 남는다) 로그인을 막으려면 **Active** 를 끕니다.
- **Access** 에서 모드 체크를 빼면 저장할 때 그 모드의 권한이 none 이 됩니다. 저장 전에 노란 글로 먼저 알립니다.
- 비밀번호를 잊은 경우 관리자가 따로 할 일은 없습니다. 그 사람이 로그인 화면에서 **Forgot your password?** 를 누릅니다([로그인](00-getting-started.md#start-sign-in)).

**조심할 것**
- 이메일이 로그인입니다. 보이기만 하고 바꾸지 않습니다.

<!-- SCREENSHOT: set-staff-1 · Role · Access · Location 이 보이는 Staff 의 한 사람 -->

<a id="set-master"></a>
## 목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스
<!-- screen: settings.html · BUILD 2026-10-25 · set v8b -->
<!-- who: manager, admin -->

**무엇인가**
**Settings**(**Settings ▾** › **Settings**)는 왼쪽에 목록을 보입니다. 목록을 누르면 열립니다. `master` 권한이 있으면 보고, write 이면 바꿉니다.

**모든 목록**
- **Search** 는 이름(또는 코드)으로 찾습니다. **Active only** 는 꺼진 것을 숨깁니다.
- ← · → 로 페이지를 넘깁니다. 한 번에 100줄입니다.
- **Source** 는 그 줄이 어디서 왔는지 보입니다: "manual"(IMS 에서 만듦) · "before IMS"(IMS 이전부터)

**목록**

| 목록 | 무엇에 쓰나 | 할 수 있는 것 |
|---|---|---|
| **Brand** | 제품 브랜드 | 더하기 · 끄기 · 켜기 |
| **Category** | 제품 분류 | 더하기 · 끄기 · 켜기 |
| **Unit** | 단위 | 더하기 · 끄기 · 켜기 |
| **Currency** | 통화 | 보기만 |
| **Payment Term** | 고객 · 공급처의 결제 조건 | 더하기 · 끄기 · 켜기 |
| **Account** | 계정(코드로) | 보기만 |
| **Warehouse** | 브랜치 | 보기만 |
| **Bin** | 브랜치마다 선반 자리 — "Thousands of bins — search for the one you need"(bin 이 수천 개 — 찾아서 쓴다) | 더하기 · 끄기 · 켜기 · B급 표시 |
| **Carrier** | "Picked at Ship & invoice — the kind decides email and tracking"(Ship & invoice 에서 고른다 — 종류가 메일 · 송장을 정한다) | 더하기 · 고치기 |
| **Service** | "Billed on service orders as quantity × unit price — tax follows the order"(서비스 오더에 수량 × 단가로 · 세금은 오더를 따른다) | 더하기 · 고치기 |

Currency · Account · Warehouse 는 보기만 합니다. 세금 규칙은 고객 · 오더에서 고르기만 하고 여기에 없습니다. 이것들을 바꿀 일이 생기면 IMS 관리자에게 말합니다.

**어떻게 — 목록에 더하기**
1. 목록을 열고 **+ Add** 를 누릅니다(예: **+ Add brand**).
2. **Name** 을 적습니다. "It cannot be renamed later — check the spelling first."(나중에 이름을 바꿀 수 없다 — 철자를 먼저 본다)
3. 목록에 다른 칸이 있으면 채우고 **Add** 를 누릅니다.
- 같은 이름이 꺼진 채 있으면 IMS 가 알려 줍니다: **Active only** 를 풀고 찾아서 켭니다.

**어떻게 — 끄기**
1. 그 줄의 **Switch off** 를 누릅니다. "Nothing is deleted — records that already use it keep it."(지우지 않는다 — 이미 쓰는 기록은 그대로)
2. 다시 쓰려면 **Switch on** 을 누릅니다.

이름은 바꿀 수 없습니다. 이름을 바꾸려면 옛것을 끄고 새로 만듭니다.

**Payment Term**
- **Net days** — "Days until the invoice is due — 0 = due on the invoice date."(인보이스 기한까지 날 수 — 0 은 인보이스 날짜가 기한)
- **Discount days** · **Discount %** — 일찍 내면 주는 할인. 예: 2% 10 Net 30 이면 10일 · 2%. 둘 다 채우거나 둘 다 비웁니다.
- **Split** — "Paid in parts, e.g. 50% COD & 50% Net 30 — Net days is the later part"(나눠 낸다 — Net days 는 뒤의 몫)

**Unit**
"A set's unit is its pack number — a 12-pack set uses the unit 12."(세트의 단위는 팩 수 — 12 개들이 세트는 단위 12)

**Bin**
- **Warehouse** 를 고르고 **Name** 을 적습니다 — "use the spelling on the shelf label"(선반 라벨의 철자대로)
- **Staging** — "A staging spot (dock, receiving area), not a shelf"(선반이 아니라 도크 · 받는 자리)
- **Mark B-grade** 는 B급 bin 으로 만듭니다. "The bin must be empty in the books first."(먼저 장부에서 비어 있어야 한다) **Unmark B-grade** 는 보통 bin 으로 되돌립니다 — B급 재고를 먼저 옮깁니다([B급 재고](03-inventory.md#stock-bgrade)).

**Carrier**
1. **+ Add carrier** 를 누르거나, 줄의 **Edit** 를 누릅니다.
2. **Kind**: **Carrier — tracking number · shipping email**(운송사 — 송장 번호 · 출고 메일) · **Pickup — customer collects**(고객이 가져감) · **Delivery — our truck**(우리 트럭). "The kind cannot change — it decides what old orders did."(종류는 바꿀 수 없다 — 지난 오더가 그것으로 처리됐다)
3. 운송사면: **Shopify name**("exactly as in Shopify's carrier list" — Shopify 운송사 목록과 똑같이) · **Tracking link**("{number} is replaced by each tracking number" — {number} 자리에 송장 번호가 들어간다)
4. **Active** 를 끄면 "not offered at Ship & invoice (old orders keep the name)"(Ship & invoice 에 나오지 않는다 · 지난 오더는 이름을 그대로 가진다). **Save** 를 누릅니다.

**Service**
1. **+ Add service** 를 누르거나, 줄의 **Edit** 를 누릅니다.
2. **Name** — "customers see this name on the invoice"(고객이 인보이스에서 보는 이름). 나중에 바꿀 수 없습니다.
3. **Unit price** — "Filled in when the service is picked on an order; staff can change it on the line."(오더에서 고르면 채워진다 — 라인에서 바꿀 수 있다) **Sales account** — 매출이 들어가는 계정
4. **Save** 를 누릅니다.

<!-- SCREENSHOT: set-master-1 · 왼쪽 목록과 Payment Term 이 열린 Settings -->

<a id="set-deals"></a>
## 할인 규칙과 딜
<!-- screen: discount-rules.html · BUILD dr v3a -->
<!-- who: manager, admin -->
<!-- TODO manual-7b -->

<a id="set-coupons"></a>
## 쿠폰
<!-- screen: discount-rules.html · BUILD dr v3a -->
<!-- who: manager, admin -->
<!-- TODO manual-7b -->

<a id="set-surcharge"></a>
## Surcharge 그룹
<!-- screen: surcharge-groups.html · BUILD 2026-10-02 · sg v1 -->
<!-- who: admin -->
<!-- TODO manual-7b -->

<a id="set-documents"></a>
## 문서
<!-- screen: settings.html · BUILD 2026-10-25 · set v8b ; ims-doc.js -->
<!-- who: admin -->
<!-- TODO manual-7b -->

<a id="set-mail"></a>
## 백오더 메일(Backorder emails)
<!-- screen: settings.html · BUILD 2026-10-25 · set v8b -->
<!-- who: admin -->
<!-- TODO manual-7b -->

<a id="set-drive"></a>
## Google Drive
<!-- screen: settings.html · BUILD 2026-10-25 · set v8b -->
<!-- who: admin -->
<!-- TODO manual-7b -->

<a id="set-shopify"></a>
## Shopify 가게
<!-- screen: shopify-stores.html · BUILD 2026-10-20 · ss v3a -->
<!-- who: admin -->
<!-- TODO manual-7b -->

<a id="set-system-check"></a>
## System Check
<!-- screen: system-check.html · BUILD 2026-10-24 · sc v2 -->
<!-- who: all -->
<!-- TODO manual-7b -->

<!-- rulings: 150, 151, 166, 534, 538, 636, 709, 713, 714, 715, 719, 720, 721, 723, 725, 732 -->
